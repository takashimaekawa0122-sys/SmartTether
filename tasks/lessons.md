# Lessons Learned

## 2026-03-25: BLE UUID を実機確認なしに実装してはならない

### 何が起きたか
壁打ち段階で参照した Gadgetbridge / Mi Band の情報が Band 5 以前（fee0/fee1）のものだった。
Band 9 は 2023 年にプロトコルが全面刷新されており（fe95 / HMAC-SHA256 + AES-CCM）、
旧世代 UUID で実装したコードは実機で `Characteristic not found` エラーになった。

### 根本原因
- 「調査済み」の情報を検証なしに確定事実として扱った
- 実機スキャンを実装後まで行わなかった

### ルール
1. **BLE UUID は必ず実機スキャン（nRF Connect 等）で確認してから実装に入ること**
2. 壁打ちで得た情報は「仮説」として扱い、実機テストまで確定事実にしない
3. プロトコル定数（UUID・コマンドコード）は、テストコードで期待値を固定する前に実機で裏取りする
4. 新しいハードウェアの BLE 実装は世代ごとにプロトコルが変わる前提で設計する

### 影響
- 開発時間の浪費（旧プロトコルの実装 → 全面書き直し）
- ユーザーの実機テスト時間の浪費（動かないビルドを複数回インストール）

---

## 2026-03-25: flutter_reactive_ble の API 名はバージョンで異なる

### 何が起きたか
`DiscoveredService.serviceId` / `DiscoveredCharacteristic.characteristicId` が存在せず
`Service.id` / `Characteristic.id` が正しいプロパティ名だった（v5.4.0）。

### ルール
- flutter_reactive_ble の型は `pub.dev` ドキュメントではなく、
  ローカルキャッシュの実際のソース（`Pub/Cache/hosted/pub.dev/`）で確認すること
- `getDiscoveredServices` の戻り値は `List<Service>`（v5.4.0）であり `List<DiscoveredService>` ではない

---

## 2026-03-25: catch で握り潰すとデバッグ不能になる

### 何が起きたか
`discoverAllServices` の catch 内で `print()` のみ → Xcodeコンソールが見られない環境では
何が起きているか完全に不明になり、診断ダイアログが表示されなかった。

### ルール
- catch 内で `print()` だけにしない。UI に表示する手段（Stream / SnackBar）も必ず用意する
- 特にユーザーが Mac を持っていない場合、コンソールログは見えない前提で設計する
