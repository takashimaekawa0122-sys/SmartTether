# Smart Tether タスク管理

## 進行中

（なし）

## 完了

### 設計・アーキテクチャ
- [x] ADR-001: フレームワーク選定（Flutter 3.x）
- [x] ADR-002: 文字起こし（Avalon API）
- [x] ADR-003: ハードウェア（Xiaomi Smart Band 9）
- [x] ADR-004: セキュリティ設計（Keychain/Keystore + AES-256-GCM）
- [x] ADR-005: バックグラウンド処理設計（iOS/Android分離）
- [x] .claude/agents/ 10エージェント定義
- [x] pubspec.yaml 依存パッケージ選定

### コア実装
- [x] band_protocol.dart（BLE UUID・振動パターン定数）
- [x] rssi_smoother.dart（RSSI平滑化）
- [x] alert_state.dart（6状態定義）
- [x] app_secrets.dart（Keychain/Keystore管理 + 実機認証情報設定済み）
- [x] timeline_entry.dart（データモデル）
- [x] timeline_logger.dart（ログ・永続化）
- [x] band_authenticator.dart（AES-128 Challenge-Response認証）
- [x] ble_manager.dart（BLE接続・RSSI監視・再接続・subscribeToCharacteristic）
- [x] background_service.dart（rssiUpdate IPC統合・SafeZone・AdaptiveThreshold）
- [x] safe_zone_detector.dart（Wi-Fi SSID判定・SharedPreferences永続化）
- [x] adaptive_threshold_learner.dart（RSSI統計学習）

### ステルス機能
- [x] flash_controller.dart（LEDフラッシュ制御・SOSパターン）
- [x] escape_timer.dart（スマートエスケープタイマー・残り秒数Stream）
- [x] stealth_command_handler.dart（ダブルタップ/トリプルタップ/長押し振り分け）
- [x] stealth_trigger.dart（BLEボタン入力監視・StealthAction Riverpod）
- [x] voice_memo_recorder.dart（録音・10分自動分割・Avalon API連携）

### サービス
- [x] avalon_api_service.dart（Whisper互換API・オフラインフォールバック）
- [x] notification_service.dart（ローカル通知）
- [x] alert_sound_player.dart（アラート音ループ・HapticFeedbackフォールバック）

### UI
- [x] timeline_page.dart（AnimatedList・BLEバッジ・監視開始/停止FAB・ステルストリガー初期化）
- [x] timeline_entry_widget.dart（UIデザイン仕様完全適用）
- [x] settings_page.dart（MAC/AuthKey/APIキー/SafeZone設定）
- [x] alert_overlay.dart（全画面アラート・warning/confirmed色分け・30秒自動解除）
- [x] onboarding_page.dart（3ステップ初回起動フロー）

### iOS設定
- [x] Info.plist: UIBackgroundModes（bluetooth-central・audio・location・fetch）
- [x] AppDelegate.swift: CoreBluetooth State Restoration

### テスト
- [x] flutter test カバレッジ 90% 以上（92.5% 達成・全144テストパス）

### リファクタリング（2026-03-25）
- [x] flutter analyze: 0 issues（修正前 13 issues）
- [x] use_build_context_synchronously 修正（settings_page.dart）
- [x] prefer_const_constructors 修正（notification_service.dart × 6、onboarding_page.dart × 3、settings_page.dart × 5）
- [x] 重複文字列リテラル 'onboarding_done' を kOnboardingDoneKey 定数に共通化
- [x] _EmptyState に const コンストラクタを追加
- [x] ble_manager.dart の余分な空行を除去
- [x] 全163テストパス確認

### インフラ
- [x] codemagic.yaml（iOS Ad-hocビルド設定）
- [x] GitHubリポジトリ作成・プッシュ（takashimaekawa0122-sys/SmartTether）

## バックログ（実機テスト時）

- [ ] BleManager 実機接続テスト
- [ ] 指数バックオフ再接続の動作確認
- [ ] grace → warning → confirmed 状態遷移タイマー確認
- [ ] アラート音ファイル（assets/sounds/alert.mp3）の追加
