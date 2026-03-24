# ADR-002: 文字起こしサービス選定

- **日付**: 2026-03-22
- **ステータス**: 決定済み

## 決定事項
**Avalon API**（AquaVoiceの独自モデル）をメインに採用。
オフライン時はApple Speech Recognitionにフォールバック。

## 理由
- Whisper APIと完全互換のため実装コストが低い
- 低レイテンシ（「しゃべった瞬間に文字が出る」レベル）
- コスト: $0.39/時間（Whisper APIとほぼ同等）
- 日本語対応・技術用語97%精度

## フォールバック設計
```
Avalon API（オンライン時）
        ↓ 失敗・オフライン時
Apple Speech Recognition（オフライン・無料）
```

## 却下した選択肢
- **Whisper API単独**: レイテンシが高い
- **Google Speech-to-Text**: コストが高い
- **Typeless**: API公開状況が不明
