import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/security/app_secrets.dart';
import '../core/timeline/timeline_entry.dart';
import '../core/timeline/timeline_logger.dart';
import 'apple_speech_service.dart';

/// Avalon API 文字起こしサービス
///
/// Avalon API は Whisper API と完全互換のエンドポイントを提供する。
/// コスト: $0.39/時間（従量課金）
/// 特徴: 低レイテンシ・日本語対応・技術用語97%精度
class AvalonApiService {
  /// Avalon API のエンドポイント（Whisper互換）
  static const String _endpoint =
      'https://asr.aquavoice.jp/v1/audio/transcriptions';

  /// タイムライン記録クラス（フォールバック失敗時に記録するために使用）
  final TimelineLogger? _timelineLogger;

  /// [timelineLogger] は省略可能。省略時はフォールバック失敗をタイムラインに記録しない。
  AvalonApiService({TimelineLogger? timelineLogger})
      : _timelineLogger = timelineLogger;

  /// API呼び出しのタイムアウト時間
  /// 長時間録音でも30秒以内にレスポンスが返ることを期待する
  static const Duration _timeout = Duration(seconds: 30);

  /// 音声認識対象の言語
  static const String _language = 'ja';

  /// 使用するモデル（Whisper互換）
  static const String _model = 'whisper-1';

  // =========================================================
  // 公開メソッド
  // =========================================================

  /// 音声ファイルを文字起こしする（Avalon API を使用）
  ///
  /// - [audioFilePath]: 文字起こし対象の音声ファイルのフルパス（m4a推奨）
  /// - 成功時: 文字起こしテキストを返す
  /// - 失敗時（APIキー未設定・ネットワークエラー・APIエラー）: null を返す
  Future<String?> transcribe(String audioFilePath) async {
    // ---- APIキーの取得 ----
    final apiKey = await AppSecrets.getAvalonApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      // APIキーが未設定の場合は何も送信しない
      // ignore: avoid_print
      print('[AvalonApiService] APIキーが未設定のため文字起こしをスキップします');
      return null;
    }

    // ---- 音声ファイルの存在確認 ----
    final file = File(audioFilePath);
    if (!file.existsSync()) {
      // ignore: avoid_print
      print('[AvalonApiService] 音声ファイルが見つかりません: $audioFilePath');
      return null;
    }

    try {
      // ---- multipart/form-data リクエストを構築 ----
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(_endpoint),
      );

      // Authorization ヘッダーにAPIキーをセット
      request.headers['Authorization'] = 'Bearer $apiKey';

      // 音声ファイルを添付
      request.files.add(
        await http.MultipartFile.fromPath('file', audioFilePath),
      );

      // Whisper互換パラメーターをセット
      request.fields['model'] = _model;
      request.fields['language'] = _language;

      // ---- タイムアウト付きでリクエストを送信 ----
      final streamedResponse = await request.send().timeout(
        _timeout,
        onTimeout: () {
          throw TimeoutException(
            'Avalon APIへのリクエストが${_timeout.inSeconds}秒でタイムアウトしました',
          );
        },
      );

      final response = await http.Response.fromStream(streamedResponse);

      // ---- レスポンスを解析 ----
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final text = json['text'] as String?;

        if (text != null && text.isNotEmpty) {
          // ignore: avoid_print
          print('[AvalonApiService] 文字起こし成功: ${text.length}文字');
          return text;
        } else {
          // ignore: avoid_print
          print('[AvalonApiService] 文字起こし結果が空でした');
          return null;
        }
      } else {
        // HTTPエラー（401 APIキー無効、429 レート制限 など）
        // ignore: avoid_print
        print(
          '[AvalonApiService] APIエラー: statusCode=${response.statusCode}, body=${response.body}',
        );
        return null;
      }
    } on TimeoutException catch (e) {
      // タイムアウト: ネットワークが遅い・サーバーが重い場合
      // ignore: avoid_print
      print('[AvalonApiService] タイムアウト: $e');
      return null;
    } on SocketException catch (e) {
      // ネットワーク未接続・DNS解決失敗など
      // ignore: avoid_print
      print('[AvalonApiService] ネットワークエラー: $e');
      return null;
    } catch (e) {
      // その他の予期しないエラー（ファイル読み込み失敗など）
      // ignore: avoid_print
      print('[AvalonApiService] 予期しないエラー: $e');
      return null;
    }
  }

  /// フォールバック付きで音声ファイルを文字起こしする
  ///
  /// まず Avalon API を試みる。失敗（null）の場合は：
  /// 1. Apple Speech Recognition（iOS オフライン）を試みる
  /// 2. それも失敗した場合はタイムラインに「文字起こし失敗（オフライン）」と記録する
  /// 3. null を返す
  Future<String?> transcribeWithFallback(String audioFilePath) async {
    // ---- Avalon API による文字起こしを試みる ----
    final result = await transcribe(audioFilePath);

    if (result != null) {
      return result;
    }

    // ---- フォールバック: Apple Speech Recognition（iOS オフライン）----
    // ignore: avoid_print
    print('[AvalonApiService] Avalon API 失敗。Apple Speech Recognition を試みます。');

    final fallbackResult = await AppleSpeechService.transcribeFile(audioFilePath);

    if (fallbackResult != null) {
      // ignore: avoid_print
      print('[AvalonApiService] Apple Speech Recognition 成功: ${fallbackResult.length}文字');
      return fallbackResult;
    }

    // ignore: avoid_print
    print('[AvalonApiService] フォールバックも失敗。タイムラインに記録します。');

    try {
      await _timelineLogger?.log(
        TimelineEventType.voiceMemo,
        '文字起こし失敗（オフライン）',
        audioFilePath: audioFilePath,
      );
    } catch (e) {
      // ignore: avoid_print
      print('[AvalonApiService] フォールバックタイムライン記録エラー: $e');
    }

    return null;
  }
}

// =========================================================
// Riverpod プロバイダー
// =========================================================

/// AvalonApiService の Riverpod プロバイダー
///
/// TimelineLogger を注入することで、フォールバック時（オフライン）に
/// タイムラインへ「文字起こし失敗」を自動記録できる。
///
/// 使い方:
/// ```dart
/// final service = ref.read(avalonApiServiceProvider);
/// final text = await service.transcribeWithFallback(filePath);
/// ```
final avalonApiServiceProvider = Provider<AvalonApiService>(
  (ref) => AvalonApiService(timelineLogger: ref.read(timelineLoggerProvider)),
);
