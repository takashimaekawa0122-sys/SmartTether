/// 一撃AIボイスメモ — 録音・文字起こし・タイムライン記録
///
/// トリプルタップで起動し、バックグラウンドで録音を行う。
/// 停止後に Avalon API（Whisper互換）で文字起こしし、
/// 結果をタイムラインに自動登録する。
///
/// 設計上の判断:
/// - 10分超の録音は自動でチャンクに分割してAPIに送信する。
///   Whisper API の最大ファイルサイズは 25MB であり、
///   長時間録音でも確実に文字起こしできるようにするため。
/// - isRecordingStream により UI 側が録音インジケーターを
///   リアクティブに表示できる。
/// - VoiceRecorderNotifier は StateNotifier として提供し、
///   Riverpod の watch で録音状態（bool）を監視できる。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../services/avalon_api_service.dart';
import '../timeline/timeline_entry.dart';
import '../timeline/timeline_logger.dart';

// =========================================================
// 定数
// =========================================================

/// 録音の最大継続時間。超過した場合はチャンク分割して送信する。
const Duration _kMaxRecordingDuration = Duration(minutes: 10);

// =========================================================
// データクラス
// =========================================================

/// 録音・文字起こし完了後の結果を保持するデータクラス
class VoiceMemoResult {
  /// 録音ファイルのフルパス（m4a）
  final String filePath;

  /// 文字起こし結果（全チャンクを結合済み。API失敗時は null）
  final String? transcription;

  /// 録音開始時刻
  final DateTime recordedAt;

  const VoiceMemoResult({
    required this.filePath,
    required this.transcription,
    required this.recordedAt,
  });
}

// =========================================================
// メインクラス
// =========================================================

/// 一撃AIボイスメモの録音・文字起こしを管理するクラス
///
/// 使い方:
/// ```dart
/// final recorder = ref.read(voiceMemoRecorderProvider);
///
/// // 録音開始（トリプルタップ検知時に呼ぶ）
/// final started = await recorder.startRecording();
///
/// // 録音停止 + 文字起こし（手動停止時 or 一定時間経過後に呼ぶ）
/// final result = await recorder.stopAndTranscribe();
/// if (result != null) {
///   print(result.transcription);
/// }
/// ```
class VoiceMemoRecorder {
  /// 録音パッケージのインスタンス
  final AudioRecorder _audioRecorder = AudioRecorder();

  /// 文字起こしサービス
  final AvalonApiService _avalonApiService;

  /// タイムライン記録クラス
  final TimelineLogger _timelineLogger;

  /// 録音状態をUIへ通知するストリームコントローラー
  ///
  /// broadcast にすることで複数の UI ウィジェットが同時に listen できる。
  final StreamController<bool> _isRecordingController =
      StreamController<bool>.broadcast();

  /// 現在録音中かどうかを管理するフラグ
  bool _isRecording = false;

  /// 録音開始時刻（録音時間の計算に使用）
  DateTime? _recordingStartedAt;

  /// 10分自動停止タイマー
  Timer? _autoStopTimer;

  /// ファイル名用の日時フォーマット（例: 20260322_140215）
  static final _fileNameFormat = DateFormat('yyyyMMdd_HHmmss');

  VoiceMemoRecorder(this._avalonApiService, this._timelineLogger);

  // =========================================================
  // 公開プロパティ
  // =========================================================

  /// 現在録音中かどうか
  bool get isRecording => _isRecording;

  /// 録音状態の変化を通知する Stream
  ///
  /// true = 録音中、false = 停止中。
  /// UI の録音インジケーター表示に使用する。
  ///
  /// ```dart
  /// StreamBuilder<bool>(
  ///   stream: recorder.isRecordingStream,
  ///   builder: (context, snapshot) {
  ///     final recording = snapshot.data ?? false;
  ///     return Icon(recording ? Icons.mic : Icons.mic_off);
  ///   },
  /// )
  /// ```
  Stream<bool> get isRecordingStream => _isRecordingController.stream;

  // =========================================================
  // 公開メソッド
  // =========================================================

  /// 録音を開始する
  ///
  /// - マイクのパーミッションを確認する
  /// - 保存先: アプリの Documents ディレクトリ / voice_memo_yyyyMMdd_HHmmss.m4a
  /// - 音声フォーマット: AAC（m4a）、16kHz、64kbps
  /// - 10分経過で自動停止 + 文字起こしを実行する
  ///
  /// 返り値:
  /// - true: 録音開始に成功
  /// - false: パーミッションなし、または予期しないエラー
  Future<bool> startRecording() async {
    // すでに録音中の場合は何もしない
    if (_isRecording) {
      // ignore: avoid_print
      print('[VoiceMemoRecorder] すでに録音中のため startRecording をスキップします');
      return false;
    }

    try {
      // ---- パーミッション確認 ----
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        // ignore: avoid_print
        print('[VoiceMemoRecorder] マイクのパーミッションがありません');
        return false;
      }

      // ---- 保存先パスを生成 ----
      final savePath = await _buildSavePath();

      // ---- 録音設定 ----
      // サンプリングレート 16000Hz は音声認識に最適なレート
      // ビットレート 64kbps はサイズと品質のバランスが取れた設定
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 16000,
      );

      // ---- 録音開始 ----
      await _audioRecorder.start(config, path: savePath);
      _isRecording = true;
      _recordingStartedAt = DateTime.now();

      // UI へ録音開始を通知する
      _isRecordingController.add(true);

      // ---- 10分自動停止タイマーをセット ----
      // 10分を超えると Whisper API の 25MB 制限に近づくため自動分割する
      _autoStopTimer = Timer(_kMaxRecordingDuration, () async {
        // ignore: avoid_print
        print('[VoiceMemoRecorder] 10分経過 — 自動チャンク分割で停止します');
        await stopAndTranscribe(isAutoSplit: true);
      });

      // ignore: avoid_print
      print('[VoiceMemoRecorder] 録音開始: $savePath');
      return true;
    } catch (e) {
      // ハードウェアエラー・権限ダイアログキャンセルなど
      // ignore: avoid_print
      print('[VoiceMemoRecorder] 録音開始エラー: $e');
      _isRecording = false;
      _recordingStartedAt = null;
      _isRecordingController.add(false);
      return false;
    }
  }

  /// 録音を停止し、文字起こしを実行する
  ///
  /// - AudioRecorder.stop() で録音を終了してファイルパスを取得する
  /// - AvalonApiService.transcribeWithFallback() で文字起こしする
  /// - 結果をタイムラインに自動登録する
  ///
  /// [isAutoSplit]: true の場合、チャンク分割として処理し、
  ///               停止後に次の録音チャンクを自動で開始する。
  ///
  /// 返り値:
  /// - VoiceMemoResult: 成功（transcription は null の場合もある）
  /// - null: 録音中でない、またはファイル取得に失敗した場合
  Future<VoiceMemoResult?> stopAndTranscribe({bool isAutoSplit = false}) async {
    if (!_isRecording) {
      // ignore: avoid_print
      print('[VoiceMemoRecorder] 録音中でないため stopAndTranscribe をスキップします');
      return null;
    }

    // 自動停止タイマーをキャンセルする（手動停止時 or タイマー完了時どちらでも安全）
    _autoStopTimer?.cancel();
    _autoStopTimer = null;

    // 録音開始時刻をローカル変数に退避（stop後にリセットするため）
    final recordedAt = _recordingStartedAt ?? DateTime.now();

    try {
      // ---- 録音停止 ----
      // stop() は保存先パスを返す（キャンセル時は null）
      final filePath = await _audioRecorder.stop();
      _isRecording = false;
      _recordingStartedAt = null;

      // UI へ録音停止を通知する
      _isRecordingController.add(false);

      if (filePath == null) {
        // ignore: avoid_print
        print('[VoiceMemoRecorder] 録音ファイルのパスを取得できませんでした');
        return null;
      }

      // ignore: avoid_print
      print('[VoiceMemoRecorder] 録音停止: $filePath');

      // ---- 録音時間を計算 ----
      final audioDuration = DateTime.now().difference(recordedAt);

      // ---- 文字起こし実行（Avalon API → フォールバック） ----
      // API障害時は transcribeWithFallback 内で自動フォールバックする
      final transcription = await _avalonApiService.transcribeWithFallback(
        filePath,
      );

      // ignore: avoid_print
      print(
        '[VoiceMemoRecorder] 文字起こし完了: '
        '${transcription != null ? "${transcription.length}文字" : "失敗"}',
      );

      // ---- タイムラインに記録 ----
      // isAutoSplit の場合はチャンクであることをメッセージに付記する
      final message = isAutoSplit
          ? 'ボイスメモ（チャンク）を録音しました（${_formatDuration(audioDuration)}）'
          : 'ボイスメモを録音しました（${_formatDuration(audioDuration)}）';

      await _timelineLogger.log(
        TimelineEventType.voiceMemo,
        message,
        transcription: transcription,
        audioFilePath: filePath,
        audioDuration: audioDuration,
      );

      final result = VoiceMemoResult(
        filePath: filePath,
        transcription: transcription,
        recordedAt: recordedAt,
      );

      // ---- 自動分割の場合は次のチャンク録音を開始する ----
      if (isAutoSplit) {
        // ignore: avoid_print
        print('[VoiceMemoRecorder] 次のチャンク録音を開始します');
        await startRecording();
      }

      return result;
    } catch (e) {
      // stop() やファイル操作が失敗した場合
      // ignore: avoid_print
      print('[VoiceMemoRecorder] 録音停止・文字起こしエラー: $e');
      _isRecording = false;
      _recordingStartedAt = null;
      _isRecordingController.add(false);
      return null;
    }
  }

  /// リソースを解放する（Riverpod の ref.onDispose から呼ばれる）
  Future<void> dispose() async {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    try {
      if (_isRecording) {
        // dispose 前に録音中なら安全に停止する
        await _audioRecorder.stop();
        _isRecording = false;
        _recordingStartedAt = null;
      }
      await _audioRecorder.dispose();
    } catch (e) {
      // dispose 時のエラーは無視する（アプリ終了時のため）
      // ignore: avoid_print
      print('[VoiceMemoRecorder] dispose エラー: $e');
    } finally {
      await _isRecordingController.close();
    }
  }

  // =========================================================
  // プライベートメソッド
  // =========================================================

  /// 録音ファイルの保存先パスを生成する
  ///
  /// 例: /var/mobile/.../Documents/voice_memo_20260322_140215.m4a
  Future<String> _buildSavePath() async {
    // アプリの Documents ディレクトリを取得
    // TODO: 将来的には暗号化ストレージへの保存を検討する
    final dir = await getApplicationDocumentsDirectory();
    final timestamp = _fileNameFormat.format(DateTime.now());
    final fileName = 'voice_memo_$timestamp.m4a';
    return '${dir.path}${Platform.pathSeparator}$fileName';
  }

  /// Duration を「X分Y秒」形式の文字列にフォーマットする
  ///
  /// タイムラインのメッセージに使用する。
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    if (minutes > 0) {
      return '$minutes分$seconds秒';
    }
    return '$seconds秒';
  }
}

// =========================================================
// Riverpod StateNotifier
// =========================================================

/// 録音状態（isRecording）を Riverpod で管理する StateNotifier
///
/// state = true  → 録音中
/// state = false → 停止中
///
/// UI での使い方:
/// ```dart
/// // 録音中かどうかを監視する
/// final isRecording = ref.watch(voiceRecorderProvider);
///
/// // 録音を開始する
/// await ref.read(voiceRecorderProvider.notifier).start();
///
/// // 録音を停止して文字起こしする
/// final result = await ref.read(voiceRecorderProvider.notifier).stop();
/// ```
class VoiceRecorderNotifier extends StateNotifier<bool> {
  final VoiceMemoRecorder _recorder;

  VoiceRecorderNotifier(this._recorder) : super(false) {
    // VoiceMemoRecorder の Stream を購読して state を同期させる
    // これにより自動分割（10分タイマー）による状態変化も Riverpod 側に伝播する
    _recorder.isRecordingStream.listen((isRecording) {
      if (mounted) state = isRecording;
    });
  }

  /// 録音を開始する
  ///
  /// 成功時は state が true に変わる（Stream 経由で自動更新）。
  /// 返り値は startRecording() の結果（true = 開始成功）。
  Future<bool> start() => _recorder.startRecording();

  /// 録音を停止し、文字起こしを実行する
  ///
  /// 成功時は state が false に変わる（Stream 経由で自動更新）。
  /// 返り値は stopAndTranscribe() の結果。
  Future<VoiceMemoResult?> stop() => _recorder.stopAndTranscribe();
}

// =========================================================
// Riverpod プロバイダー
// =========================================================

/// VoiceMemoRecorder の内部インスタンスプロバイダー
///
/// VoiceRecorderNotifier と voiceRecorderProvider の両方が
/// 同じ VoiceMemoRecorder インスタンスを共有するために使用する。
final _voiceMemoRecorderInstanceProvider = Provider<VoiceMemoRecorder>((ref) {
  final recorder = VoiceMemoRecorder(
    ref.read(avalonApiServiceProvider),
    ref.read(timelineLoggerProvider),
  );
  ref.onDispose(() { recorder.dispose(); });
  return recorder;
});

/// 録音状態（isRecording）を管理する StateNotifierProvider
///
/// - state: bool（true = 録音中、false = 停止中）
/// - notifier: start() / stop() メソッドを提供
///
/// UI での使い方:
/// ```dart
/// final isRecording = ref.watch(voiceRecorderProvider);
/// await ref.read(voiceRecorderProvider.notifier).start();
/// ```
final voiceRecorderProvider =
    StateNotifierProvider<VoiceRecorderNotifier, bool>((ref) {
  return VoiceRecorderNotifier(ref.read(_voiceMemoRecorderInstanceProvider));
});

/// VoiceMemoRecorder への直接アクセスが必要な場合に使用するプロバイダー
///
/// 通常は voiceRecorderProvider 経由で start()/stop() を呼ぶ。
/// このプロバイダーは stopAndTranscribe の結果（VoiceMemoResult）が
/// 直接必要なケースのために公開する。
final voiceMemoRecorderProvider = Provider<VoiceMemoRecorder>((ref) {
  return ref.watch(_voiceMemoRecorderInstanceProvider);
});
