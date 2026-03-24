# Smart Tether タスク管理

## 進行中

### ボイスメモ録音 + Avalon API 文字起こし実装
- [x] voice_memo_recorder.dart: isRecording Stream<bool> 追加
- [x] voice_memo_recorder.dart: VoiceRecorderNotifier (StateNotifier<bool>) 追加
- [x] voice_memo_recorder.dart: 10分超の自動分割送信ロジック追加
- [x] avalon_api_service.dart: フォールバック時にタイムライン記録を追加
- [x] flutter analyze --no-pub でエラーなし確認

## 完了

- [x] ADR-001: フレームワーク選定（Flutter 3.x）
- [x] ADR-002: 文字起こし（Avalon API）
- [x] ADR-003: ハードウェア（Xiaomi Smart Band 9）
- [x] ADR-004: セキュリティ設計（Keychain/Keystore + AES-256-GCM）
- [x] ADR-005: バックグラウンド処理設計（iOS/Android分離）
- [x] .claude/agents/ 10エージェント定義
- [x] pubspec.yaml 依存パッケージ選定
- [x] band_protocol.dart（BLE UUID・振動パターン定数）
- [x] rssi_smoother.dart（RSSI平滑化）
- [x] alert_state.dart（6状態定義）
- [x] app_secrets.dart（Keychain/Keystore管理）
- [x] timeline_entry.dart（データモデル）
- [x] timeline_logger.dart（ログ・永続化）
- [x] background_service.dart（骨格）
- [x] timeline_page.dart（骨格）
- [x] band_authenticator.dart（AES-128 Challenge-Response認証）
- [x] ble_manager.dart（BLE接続・RSSI監視・再接続ロジック）
- [x] background_service.dart（rssiUpdate IPC統合）
- [x] timeline_entry_widget.dart（UIデザイン仕様完全適用）
- [x] timeline_page.dart（AnimatedList・BLEステータス表示）

## バックログ（Band 9到着後）

- [ ] AppSecrets.setDevelopmentPlaceholders() を削除し実際の Auth Key・MAC を設定
- [ ] BleManager 実機接続テスト
- [ ] 指数バックオフ再接続の動作確認
- [ ] grace → warning → confirmed 状態遷移タイマー確認
- [ ] iOS: Info.plist に UIBackgroundModes `bluetooth-central` 追加
- [ ] iOS: AppDelegate.swift に CoreBluetooth State Restoration 設定
- [x] ステルストリガー（メディアコントロール）実装
  - stealth_trigger.dart: StealthAction enum + StealthTriggerNotifier 作成
  - ble_manager.dart: subscribeToCharacteristic メソッド追加
  - BLE接続状態を監視して自動で購読開始/停止
- [x] ボイスメモ録音 + Avalon API 文字起こし実装
- [ ] LEDフラッシュ制御実装
- [ ] スマートエスケープタイマー実装
- [ ] アラート音・全画面アラート実装
- [ ] 安全圏（SafeZone）GPS + Wi-Fi 登録UI
- [ ] flutter test カバレッジ 90% 以上
