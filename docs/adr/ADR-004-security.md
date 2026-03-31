# ADR-004: セキュリティ設計方針

- **日付**: 2026-03-22
- **ステータス**: 決定済み

## 決定事項
機密データは**flutter_secure_storage**（iOS: Keychain / Android: Keystore）で管理する

## 保護対象と保管方法

| データ | 保管方法 |
|---|---|
| Band 9 Auth Key | flutter_secure_storage |
| Avalon APIキー | flutter_secure_storage |
| 録音ファイル | AES-256-GCM暗号化 |
| 自宅GPS座標 | 暗号化DB |

## ハードコード禁止リスト
以下はソースコードに絶対に書かない:
- Auth Key
- Avalon APIキー
- 自宅SSID
- GPS座標

## 通知プライバシー
- ロック画面には内容を表示しない（「Smart Tetherからの通知」のみ）
- 録音ファイルは30日後に自動削除

## 理由
- 個人使用とはいえ、iPhoneが盗難された際のデータ保護が必要
- パワハラ証拠録音は特に機密性が高い
- APIキーの流出はコスト被害につながる
