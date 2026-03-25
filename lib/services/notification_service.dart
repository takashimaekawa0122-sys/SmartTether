import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 通知サービス — アプリ全体で使う通知処理をまとめたシングルトンクラス
///
/// 用途：
///   - Android Foreground Service 用の常駐通知
///   - 置き忘れアラート通知
///   - ボイスメモ完了通知
class NotificationService {
  NotificationService._();

  /// シングルトンインスタンス
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  // ===== 通知ID定数 =====

  /// Android Foreground Service 用の常駐通知ID
  static const int _idPersistent = 1;

  /// 置き忘れアラート通知ID
  static const int _idAlert = 2;

  /// ボイスメモ完了通知ID
  static const int _idVoiceMemo = 3;

  // ===== Androidチャンネル定数 =====

  /// Androidチャンネルの識別子
  static const String _channelId = 'smart_tether_channel';

  /// Androidチャンネルの表示名
  static const String _channelName = 'Smart Tether';

  /// Androidチャンネルの説明
  static const String _channelDescription = 'Smart Tether の通知チャンネル';

  // ===== 初期化フラグ =====

  bool _initialized = false;

  // =========================================================
  // 初期化
  // =========================================================

  /// 通知サービスを初期化する
  ///
  /// - iOS: マイク・通知権限を申請する
  /// - Android: 重要度 high のチャンネルを作成する
  /// アプリ起動時に一度だけ呼ぶこと。
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // ---- iOS の初期設定 ----
      const iosSettings = DarwinInitializationSettings(
        // 起動時には権限ダイアログを出さず、必要なタイミングで申請する
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      // ---- Android の初期設定 ----
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher', // アプリアイコンを通知アイコンとして使用
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // ---- Android: 通知チャンネルを作成 ----
      await _createAndroidChannel();

      // ---- iOS: 通知権限を申請 ----
      await _requestIosPermission();

      _initialized = true;
    } catch (e) {
      // 初期化失敗時はログに残すが、アプリの動作は止めない
      // ignore: avoid_print
      print('[NotificationService] 初期化エラー: $e');
    }
  }

  /// Android の通知チャンネルを作成する（既存チャンネルがあれば上書きしない）
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
    );

    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] Androidチャンネル作成エラー: $e');
    }
  }

  /// iOS の通知権限を申請する
  Future<void> _requestIosPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] iOS権限申請エラー: $e');
    }
  }

  // =========================================================
  // 通知タップ時のコールバック
  // =========================================================

  /// 通知タップ時の処理
  ///
  /// アラート通知をタップするとアプリが前面に出る。
  /// 現時点では通知IDに応じた処理のひな形のみ実装。
  void _onNotificationTapped(NotificationResponse response) {
    // 将来: 通知IDに応じてルーティング処理を追加する
    // ignore: avoid_print
    print('[NotificationService] 通知タップ: id=${response.id}');
  }

  // =========================================================
  // 公開メソッド
  // =========================================================

  /// Android Foreground Service 用の常駐通知を表示する
  ///
  /// - 通知ID: 1
  /// - 常駐表示のため ongoing: true を設定する
  /// - ユーザーはスワイプで消せない
  Future<void> showPersistentNotification({
    required String title,
    required String body,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.low, // 常駐通知は低重要度で静かに表示する
        priority: Priority.low,
        ongoing: true, // スワイプで消せないようにする
        autoCancel: false,
        showWhen: false,
      );

      const details = NotificationDetails(android: androidDetails);

      await _plugin.show(_idPersistent, title, body, details);
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] 常駐通知表示エラー: $e');
    }
  }

  /// 置き忘れアラート通知を表示する
  ///
  /// - 通知ID: 2
  /// - 重要度 high で即座にユーザーへ届ける
  /// - タップするとアプリが前面に出る
  Future<void> showAlertNotification({
    required String title,
    required String body,
  }) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: true,
        // タップでアプリを前面に出すためのフルスクリーンインテント
        fullScreenIntent: true,
      );

      // iOS: タップ時にアプリを前面へ出す（デフォルト動作）
      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(_idAlert, title, body, details);
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] アラート通知表示エラー: $e');
    }
  }

  /// ボイスメモ完了通知を表示する
  ///
  /// - 通知ID: 3
  /// - 録音時間と文字起こし結果（冒頭50文字）を表示する
  /// - 文字起こしが未完了の場合は duration のみ表示する
  Future<void> showVoiceMemoNotification({
    required Duration duration,
    String? transcription,
  }) async {
    try {
      // 録音時間を "X分Y秒" 形式に整形する
      final minutes = duration.inMinutes;
      final seconds = duration.inSeconds % 60;
      final durationText =
          minutes > 0 ? '$minutes分$seconds秒' : '$seconds秒';

      // 通知本文: 文字起こし結果があれば冒頭50文字を表示する
      final body =
          transcription != null && transcription.isNotEmpty
              ? '録音時間: $durationText\n「${transcription.length > 50 ? '${transcription.substring(0, 50)}…' : transcription}」'
              : '録音時間: $durationText';

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
        // 長い文字起こしを折りたたんで表示するスタイル
        styleInformation: BigTextStyleInformation(''),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false, // ボイスメモ完了は無音で通知する
      );

      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _plugin.show(_idVoiceMemo, 'ボイスメモを保存しました', body, details);
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] ボイスメモ通知表示エラー: $e');
    }
  }

  /// 表示中のすべての通知を消す
  Future<void> dismissAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      // ignore: avoid_print
      print('[NotificationService] 全通知削除エラー: $e');
    }
  }
}

// =========================================================
// Riverpod プロバイダー
// =========================================================

/// NotificationService の Riverpod プロバイダー
///
/// 使い方:
/// ```dart
/// final service = ref.read(notificationServiceProvider);
/// await service.showAlertNotification(title: '警告', body: '...');
/// ```
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);
