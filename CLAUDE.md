# Smart Tether - Claude向け開発ガイド

## プロジェクト概要
iPhoneとXiaomi Smart Band 9を連携させる**Band 9コンパニオンアプリ**。
Mi Fitnessを完全に不要にし、Band 9のすべての機能をSmart Tether一本で賄う。
個人使用目的。App Store非公開。

### 実装する機能（優先順）
1. **BLE認証（SPPv2）** ← 現在対応中。すべての機能の土台
2. **置き忘れ防止**（RSSI監視・アラート）
3. **ステルス操作**（Band 9ボタンでボイスメモ等を操作）
4. **時刻同期**（接続時に自動）
5. **通知転送**（電話・メッセージをBand 9に表示）
6. **ヘルスデータ表示**（歩数・心拍をアプリ内で確認）
7. **天気送信**（Band 9の天気表示を維持）

### Mi Fitness不要化の方針
- Band 9はSmart Tetherが常時接続を保持する
- Mi Fitnessとの共存は**しない**（BLE排他制約のため）
- Auth Keyの取得はAndroid + Gadgetbridgeで1回だけ実施

## アーキテクチャ
→ `.claude/agents/architect.md` を必ず最初に読むこと

## エージェント一覧
→ `.claude/agents/` 配下の各ファイルを参照

## 設計決定の記録（ADR）
→ `docs/adr/` を参照。実装前に必ず確認すること

## 技術スタック
- Flutter（iOS + Android クロスプラットフォーム）
- BLE: flutter_reactive_ble
- 状態管理: Riverpod
- 文字起こし: Avalon API（Whisper互換）
- セキュリティ: flutter_secure_storage（Keychain/Keystore）

## 主要コマンド
```bash
# 静的解析（コード書いたら必ず実行）
flutter analyze

# テスト実行
flutter test

# ビルド確認（iOS）
flutter build ios --debug

# ビルド確認（Android）
flutter build apk --debug
```

## 絶対に守るルール
1. Auth Key・APIキーはハードコード禁止 → flutter_secure_storage を使う
2. RSSIの生値をそのまま使わない → rssi_smoother.dart を必ず通す
3. BLE操作は必ずtry-catchで囲む
4. 新規ファイル作成より既存ファイルの修正を優先する
5. バックグラウンド処理はiOSとAndroidで実装を分ける

## ユーザーについて
- エンジニアではない
- 説明は平易な日本語で行う
- 実行前に何をするか必ず説明する
