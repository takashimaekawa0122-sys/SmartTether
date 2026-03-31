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

---

## 2026-03-31: SPPv2認証はSESSION_CONFIGハンドシェイクなしには動かない

### 何が起きたか
`authenticateV2()` が CMD_NONCE を送信しても Band 9 が10秒間応答せずタイムアウトした。
Gadgetbridge の実際のフローには「認証前に必須の SESSION_CONFIG ハンドシェイク」があり、
これを実装せずに CMD_NONCE を送っても Band は完全に無視する仕様だった。

### 根本原因
Gadgetbridge のドキュメントや概要説明は「CMD_NONCE → CMD_AUTH」の2ステップのみを記述しており、
その前段として必須の SESSION_CONFIG 交換を省略して説明していた。
実際には:
  1. MTU 512 をリクエスト
  2. 005e に Notify をサブスクライブ
  3. SESSION_CONFIG リクエスト（frameType=0x02, opcode=0x01）を送信
  4. Band から SESSION_CONFIG レスポンス（frameType=0x02, opcode=0x02）を受信
  5. 初めて CMD_NONCE を送信できる

### ルール
1. **認証タイムアウトの原因は「プロトコルの前段ハンドシェイク欠落」を最初に疑う**
2. Gadgetbridge のドキュメント/概要ではなく `initializeDevice()` の実コードを必ず読む
3. BLEプロトコルに「バージョン交換」「セッション設定」などの前置きがある場合、
   それが完了するまで後続コマンドは無視されることがある
4. `flutter_reactive_ble` の `requestMtu()` は `connectToDevice()` の引数ではなく
   接続後に単独で呼ぶ独立したメソッド（v5.3.x）

### デバッグのヒント
- `print('[Auth] 受信 frameType=0x...')` でフレームタイプを必ずログに出す
- frameType=0x02 が来ていない場合は SESSION_CONFIG が届いていない
- parseが null を返す場合はパケットフォーマット不一致（マジックバイト/CRC）を疑う

---

## 2026-03-31: SPPv2のCRCはCRC-16/ARCであり CCITT/XMODEM ではない

### 何が起きたか
SESSION_CONFIGを送信してもBandが応答しなかった。
CRCアルゴリズムが間違っていたため、BandがCRC不一致として全パケットを無視していた。

### 根本原因
「CRC-16」と一口に言っても実装バリアントが多数ある。
SPPv2が使うのは CRC-16/ARC（多項式 0x8005、refin=true、refout=true）であり、
一般的な CRC-16/CCITT-XMODEM（多項式 0x1021）ではない。

Gadgetbridgeの `calculatePayloadChecksum()` コメントに明記されている:
```
// CRC-16/ARC (poly=0x8005, init=0, xorout=0, refin, refout)
```

### ルール
1. **CRCアルゴリズムは必ず Gadgetbridge のソースコードで確認する（コメントに仕様が書いてある）**
2. CRC実装を移植する際は「同じデータで同じ結果になるか」の単体テストを書く
3. BandがSESSION_CONFIGにも応答しない場合、最初にCRCを疑う

---

## 2026-03-31: Xiaomi SPPv2コマンドデータはProtobufシリアライズが必要

### 何が起きたか
CMD_NONCE と CMD_AUTH のペイロードを手動バイト配列（`[familyType, subType, ...]`）で
組み立てていたが、実際には Protobuf シリアライズ形式が必要だった。

### 根本原因
Gadgetbridgeは `xiaomi.proto` で定義された `Command` メッセージを使用しており、
`XiaomiAuthService.buildNonceCommand()` は `XiaomiProto.Command.newBuilder()` で
Protobufメッセージを構築して送信する。

Protobufのwire format（TLV）:
- Command.type(field=1, varint) → `08 01`
- Command.subtype(field=2, varint) → `10 1a`（1a=26=CMD_NONCE）
- Command.auth(field=3, length-delimited) → ネスト構造

### ルール
1. **BLEコマンドデータが「謎のバイト列」に見える場合、Protobufを疑う**
2. プロジェクトに `.proto` ファイルがあれば、それがコマンドのバイト構造を決定する
3. Protobufを使う場合、ライブラリ追加なしに手動エンコード/デコードも可能
   （varint: 7ビット×複数バイト、length-delimited: tag + len + bytes）

---

## 2026-03-31: SESSION_CONFIGペイロードのTLV形式

### 何が起きたか
SESSION_CONFIGペイロードの各パラメータ（VERSION等）のフォーマットを
`[key, value...]` と実装していたが、正しくは `[key, len_lo, len_hi, value...]` だった。

### 正しい構造
各パラメータは `[key(1バイト), length(2バイトLE), value(lengthバイト)]` のTLV形式:
```
key=1, len=3(0x03 0x00), VERSION: 01 00 00
key=2, len=2(0x02 0x00), MAX_PACKET_SIZE: 00 fc
key=3, len=2(0x02 0x00), TX_WIN: 20 00
key=4, len=2(0x02 0x00), SEND_TIMEOUT: 10 27
```

### ルール
1. SESSION_CONFIGペイロードは `getPacketPayloadBytes()` の生バイトリテラルで確認する
2. 「設定パラメータを並べる」形式は基本的にTLV（Type-Length-Value）を使う

---

## 2026-03-31: BLEのRX/TXチャンネルを混同してはならない

### 何が起きたか
認証コマンド（SESSION_CONFIG, CMD_NONCE, CMD_AUTH）を `005e`（RXチャンネル）に
書き込んでいたため、Band 9 がコマンドを一切受信できず30秒タイムアウトしていた。

### 根本原因
`005e` と `005f` の両方が `write no response + notify` プロパティを持っていたため、
どちらに書き込むべきか区別できなかった。実機テストで:
- `005e` = RX（受信専用、subscribe して Band からのデータを受け取る側）
- `005f` = TX（送信用、コマンドを書き込む側）
であることが判明した。

### ルール
1. **BLEキャラクタリスティックの用途（RX/TX）は必ず実機動作で確認する**
2. プロパティ（write/notify）だけでは RX/TX の区別はつかない
3. 変数名・定数名に `rx` / `tx` を明示して取り違えを防ぐ
4. subscribe する先と write する先は別のキャラクタリスティックになる前提で設計する
