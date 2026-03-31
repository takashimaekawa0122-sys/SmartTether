# ADR-005: バックグラウンド処理設計方針

- **日付**: 2026-03-22
- **ステータス**: 決定済み

## 決定事項
**flutter_background_service** を使い、iOS・Androidそれぞれのネイティブ実装と連携する

## iOSの実装方針
- `UIBackgroundModes`: `bluetooth-central`, `audio`, `location`, `fetch`
- CoreBluetooth State Restoration で再起動後も自動復帰
- `CBCentralManagerOptionRestoreIdentifierKey` を必ず設定

## Androidの実装方針
- Android 8.0以降: Foreground Service必須（通知付き）
- `SmartTetherService.kt` でBLE監視を常時稼働
- バッテリー最適化の除外をユーザーに案内するUI実装

## 再起動後の復帰設計
```
端末再起動
        ↓
ユーザーがアプリを開く
        ↓
前回の監視状態を自動復元
        ↓
「監視が停止していました」通知を表示
```

## 省電力設計
- 安全圏（自宅Wi-Fi接続中）ではBLEポーリング頻度を極限まで下げる
- 加速度センサーが静止中は監視を弱める
- BLE再接続は指数バックオフで行う（無限ループ防止）

## 理由
- Smart Tetherの価値はバックグラウンドで動き続けることにある
- iOSとAndroidでは制約が根本的に異なるため、共通化より分離を選択
