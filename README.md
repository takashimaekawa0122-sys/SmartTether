# Smart Tether

Xiaomi Smart Band 9 のコンパニオンアプリ（iPhone向け）。
Mi Fitnessを完全に代替し、Band 9のすべての機能をこの1アプリで賄う。

## 主な機能

| 機能 | 状態 |
|---|---|
| BLE認証（SPPv2） | 🔄 実装中 |
| 置き忘れ防止（RSSI監視） | 🔄 実装中 |
| ステルス操作（ボイスメモ等） | 🔄 実装中 |
| 時刻同期 | 📋 予定 |
| 通知転送 | 📋 予定 |
| 歩数・心拍表示 | 📋 予定 |
| 天気送信 | 📋 予定 |

## セットアップ

### Auth Key の取得（初回のみ）
1. Android端末に [Gadgetbridge](https://gadgetbridge.org/) をインストール
2. Band 9をGadgetbridgeでペアリング
3. デバイス設定からAuth Key（32文字HEX）を確認
4. Smart Tetherの設定画面に入力

### アプリの設定
1. 設定画面でBand 9をスキャン → 選択
2. Auth Keyを入力して保存
3. メイン画面で「監視開始」

## 技術スタック
- Flutter（iOS / Android）
- BLE: flutter_reactive_ble
- 状態管理: Riverpod
- 文字起こし: Avalon API（Whisper互換）
- セキュリティ: flutter_secure_storage

## 設計決定
`docs/adr/` を参照。
