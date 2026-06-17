# picoruby-ble Darwin step3 設計 — CoreBluetooth → BTstack バイト合成シム（central/observer v1）

最終更新: 2026-06-17。状態: **設計確定・検証済み（verdict=sound, blocking issue 0）。実装未着手。**

13-agent workflow（Understand 5 reader → Design 3 案 → Judge 3 lens → Synthesize → 敵対的 Verify）が picoruby-ble の実コードを行番号付きで精査して確定した設計。HANDOFF.md の step3 叩き台仕様の誤りはすべて本書で訂正済み。コードのパスは worktree `picoruby-ble-apple_silicon-port` の `mrbgems/picoruby-ble/` 配下。

## スコープ

central + observer のみ（v1）。peripheral/broadcaster backend は no-op stub のまま、write path も stub。0xA3 included-service・0xA6 long-value・0xA7/0xA8 notification/indication の合成はしない（`ble_central.rb` 側に decode body が無い: 0xA7 は空の TODO branch `:297-300`、0xA8 は dispatch 範囲外）。

## 最重要前提: 合成ターゲットはデコーダであって実 BTstack ではない

vendored BTstack は 1.6.2 で、GATT イベントは serialize struct を 4 byte 高い位置に置く（service_id/connection_id 挿入）。しかし `ble_central.rb` は**古い ABI offset（struct base 4, not 8）**を読む（service の start_handle を `byteslice(4,1)` で読むことで確認）。したがって「esp32/rp2040 の実 BTstack バイト = デコーダ期待」という前提はこのバージョンでは**偽**。合成は `ble_central.rb` の offset に合わせる（= HANDOFF draft の base-4 offset が正しい）。

## イベントバイト仕様（全 9 種、デコーダ実コードと一致確認済み）

handle はすべて `byteslice(N,1)`（低位 1 byte）で読まれる → **GATT handle は ≤255 必須**。例外は conn_handle のみ（`byteslice(4,2)` 16bit）。value/descriptor の length も 1 byte（≤255）。

| event | code | byte layout | builtFrom / decoder offset |
|---|---|---|---|
| BTSTACK_EVENT_STATE (power-on/WORKING) | 0x60 | `[0]=0x60, [1]=filler(不読), [2]=0x02(=HCI_STATE_WORKING, ble.rb:11)`。1 回 emit | `centralManagerDidUpdateState==.poweredOn` 後。decoder: `:86 getbyte(0)`, `:90 getbyte(2)==HCI_STATE_WORKING`。`@state∈{:TC_OFF,:TC_IDLE}` でゲート(`:89`) |
| GAP_EVENT_ADVERTISING_REPORT | 0xda | `≥14 byte`: `[0]=0xda,[1]=filler,[2]=adv event_type subcode(0x00),[3]=addr_type(0x01 random),[4..9]=6byte synthetic BD_ADDR(wire LSB-first, 各 byte 非ゼロ),[10]=rssi byte=(rssi_dBm+256)&0xff,[11]=AD-data len L,[12..]=AD TLV([len][type][value], value 非空)`。complete-local-name(0x09) を入れて `name_include?` を効かせる | `didDiscover peripheral advertisementData rssi`。BD_ADDR は `peripheral.identifier` UUID を 6byte hash 後 各 byte `|0x01`。decoder: `ble_advertising_report.rb:25-39` bytesize<14 で ArgumentError; `getbyte(3)` addr_type(default 99); `5.downto(0) getbyte(4+i)` で reverse→`@address`; `getbyte(10)-256`=rssi; `getbyte(11)`=len; `byteslice(12,len)` TLV。`@state==:TC_W4_SCAN_RESULT`(`:98`) |
| HCI_EVENT_LE_META / LE_CONNECTION_COMPLETE | 0x3E (sub 0x01) | `≥6 byte`: `[0]=0x3E,[1]=filler,[2]=0x01(sub-event code),[3]=status(不読),[4..5]=conn_handle little-endian 16bit`。例: 0x0040→`40 00` | `didConnect peripheral`。conn_handle は registry の uint16(0x0040 起点) を C `con_handle` に mirror。decoder: `:102 getbyte(2)==HCI_SUBEVENT_LE_CONNECTION_COMPLETE`, `:104 little_endian_to_int16(byteslice(4,2))`(唯一の 2byte handle)。`@state==:TC_W4_CONNECT`(`:101`) |
| HCI disconnection (LE_META sub 0x05) | 0x3E (sub 0x05) | `[0]=0x3E,[1]=filler,[2]=0x05`。v1 read-only happy path では省略可 | `didDisconnectPeripheral`/`didFailToConnect`。decoder: `:113 getbyte(2)==HCI_EVENT_DISCONNECTION_COMPLETE`→`@conn_handle=0xffff`(`@state==:TC_W4_CONNECT` 時のみ) |
| GATT_EVENT_SERVICE_QUERY_RESULT | 0xA1 | `≥24 byte`: `[0]=0xA1,[4]=start_handle low([5]=0),[6]=end_handle low=0xFF([7]=0),[8..23]=uuid128 LSB-first(16byte)` | `didDiscoverServices` → CBService ごとに 1 個 + 末尾 1 個の 0xA0。end_handle=0xFF(後述)。decoder: `:123 little_endian_to_int16(byteslice(4,1))`, `:124 byteslice(6,1)`, `:125 reverse_128(byteslice(8,16))`, `:130 uuid128_to_uuid32`。`@state==:TC_W4_SERVICE_RESULT` |
| GATT_EVENT_CHARACTERISTIC_QUERY_RESULT | 0xA2 | `≥28 byte`: `[0]=0xA2,[4]=start low,[6]=value_handle low,[8]=end low,[10]=properties low,[12..27]=uuid128 LSB-first`。end_handle は**実値**(next_att-1) であって 0xFF にしない | `didDiscoverCharacteristicsFor service` → 1 char 1 個 + 末尾 0xA0。properties は CBCharacteristicProperties→(READ=0x02,WRITE=0x08,WRITE_WO_RESP=0x04,NOTIFY=0x10,INDICATE=0x20, ble.rb:21-27)。decoder: `:151 byteslice(4,1)`,`:152 byteslice(6,1)`,`:153 byteslice(8,1)`,`:160 byteslice(10,1)`,`:154 reverse_128(byteslice(12,16))`。`:169` で `service.start<char.start && char.end<=service.end` の service に格納。`@state==:TC_W4_CHARACTERISTIC_RESULT` |
| GATT_EVENT_ALL_CHARACTERISTIC_DESCRIPTORS_QUERY_RESULT | 0xA4 | `≥22 byte`: `[0]=0xA4,[4]=descriptor handle low,[6..21]=uuid128 LSB-first(16byte)`。**UUID は offset 6, not 8** | `didDiscoverDescriptorsFor characteristic` → 1 descriptor 1 個 + 末尾 0xA0。decoder: `:228 little_endian_to_int16(byteslice(4,1))`, `:229 reverse_128(byteslice(6,16))`。`:236` で `char.value<handle && handle<=char.end` の char に格納。`@state==:TC_W4_ALL_CHARACTERISTIC_DESCRIPTORS_RESULT` |
| GATT_EVENT_CHARACTERISTIC_VALUE_QUERY_RESULT | 0xA5 | `8+len byte`: `[0]=0xA5,[4]=value_handle low,[6]=value len low(≤255),[8..]=value`。characteristic value と descriptor value で**共用** | `didUpdateValueFor characteristic`(descriptor value も `readValue(for: CBCharacteristic)` で value-handle 経由, decoder comment `:254`)。decoder char-value `:203 byteslice(4,1)`/`:204 byteslice(8, little_endian_to_int16(byteslice(6,1)))`、descriptor-value `:275`/`:276` 同一 offset。`@state∈{:TC_W4_CHARACTERISTIC_VALUE_RESULT, :TC_W4_CHARACTERISTIC_DESCRIPTOR_VALUE_RESULT}` |
| GATT_EVENT_QUERY_COMPLETE (phase terminator) | 0xA0 | `2 byte`: `[0]=0xA0,[1]=0x01(filler)`。`getbyte(0)` のみ読まれる。**各 phase batch の後に正確に 1 個** | port が CB serial queue 上で phase 完了時に emit。decoder: `:86 getbyte(0)==0xA0` → FSM を advance し worklist を 1 つ shift(`:134-145,:179-191,:215-223,:249-260,:290-293`)。**0xA0 欠落で FSM 永久 stall**(packet_callback 内に timeout 無し) |

## threading 構造（2 スレッド境界 + per-tick VM 側 drain hook）

- **Thread A — CoreBluetooth serial queue** (`DispatchQueue(label:"pble.cb")`)。全 `CBCentralManagerDelegate`/`CBPeripheralDelegate` callback がここ。やることは 3 つだけ: (1) registry_lock 下で handle/address registry を read/mutate、(2) Swift 内で BTstack 形式 `[UInt8]` を構築、(3) C export `pble_fifo_push(ptr,len)`（libc malloc した FIFO node に memcpy, fifo_lock）。**`BLE_push_event`/`BLE_heartbeat`/`mrb_*` を一切呼ばない**。mruby state は Thread A から到達不能。
- **Thread B — mruby VM スレッド**。`BLE#start` の 100ms poll loop を回す唯一のスレッド。port C への入口は `BLE_init`/`BLE_hci_power_control`/`BLE_central_*`/`BLE_discover_*`/`BLE_read_value_*` + 新規 `BLE#__darwin_drain`。
- **`BLE_push_event` を呼ぶのは Thread B の `pble_fifo_drain_one()` 内のみ**: fifo_lock → head を 1 node unlink → unlock → `BLE_push_event(node.data, node.len)`（**lock の外**）→ free。`src/ble.c` の single-slot mailbox への唯一の producer。
- **per-tick drain hook（load-bearing な決定）**: scan 中はデコーダが tick 間に一切 `BLE_*` を呼ばない（`ble_central.rb` は WORKING 時に `start_scan` を 1 回 `:92`、`gap_local_bd_addr` を 1 回 `:91` のみ）。ABI 再入時のみ drain すると 0xda が FIFO に溜まって scan が死ぬ。**対策**: `mrblib/ble.rb` の poll loop の `packet = pop_packet`（現 139 行目）直前に `__darwin_drain if respond_to?(:__darwin_drain)` を 1 行追加。`__darwin_drain` は `pble_fifo_drain_one()` を 1 回呼ぶ。pop_packet が tick ごと 1 回 single slot を drain し、`__darwin_drain` が tick ごと最大 1 node しか push しないので、2 回の pop_packet 間に `BLE_push_event` は最大 1 回 → slot 上書きも 0xA0 ロストも起きない。これが唯一の port-local でない逸脱。second timer queue も slot 占有 bookkeeping も使わない。
- **Thread B からの CB API 呼び出し**: discover_*/read_value_*/connect/start_scan が CoreBluetooth method を呼ぶ時は、Thread B から直接ではなく `pble.cb` serial queue へ `dispatch_async`（block は mruby state に触らない）。CoreBluetooth interaction を全て Thread A に集約。
- **lock**: os_unfair_lock 2 本。fifo_lock は O(1) enqueue/dequeue のみ（serialize 中も `BLE_push_event` 中も保持しない）。registry_lock は handle/address map（Thread B が handle→object 解決時に read、Thread A が discovery 時に write）。既存 `packet_mutex`/`packet_flag` は同一スレッド再入ガード（memory barrier 無し, `src/ble.c:8-11`）で cross-thread 保護に使えない（cross-TU で読めない file-scope static）。
- **runtime assert**: `BLE_init` で VM スレッド id を `pthread_self()` 記録、`pble_fifo_push` で `pthread_self() != vm_thread_id` を assert（Thread A の誤入を捕捉）。

## synthetic handle registry アルゴリズム

CB オブジェクトは Swift 側に住むので registry も Swift（registry_lock guard）。

- **conn_handle (16bit, ≤255 制約の対象外)**: uint16 カウンタ 0x0040 起点、connection ごとに increment。registry に保持し C global `con_handle` へ `pble_set_con_handle` で mirror。CBPeripheral⇔conn_handle 双方向。disconnect で 0xffff + child map クリア。
- **GATT handle (uint8, 1..255)**: 単一 monotonic cursor `next_att`（1 起点）を **pre-order DFS** で採番。discovery を厳密に nest させる（service i の char と descriptor を採番し終えるまで service i+1 の char discovery を発行しない）。
  ```
  for each service S (CBPeripheral.services 順):
    S.start_handle = next_att++          // service が block の先頭番号を取る
    for each characteristic C in S:
      C.start_handle = next_att++        // declaration handle
      C.value_handle = next_att++        // value = decl + 1
      for each descriptor D of C:
        D.handle = next_att++
      C.end_handle = next_att - 1        // この char(descriptor 込み)を覆う
    S.end_handle = next_att - 1          // (本来) service block 全体を覆う
  ```
  これで構築的に保証: `:169` で `service.start < char.start`（service が先に番号取得）、`:236` で `char.value < descriptor.handle <= char.end`。
- **service の end_handle は 0xFF 固定で emit**: デコーダは service.end_handle を `:169` の上界比較（`char.end <= service.end`）でしか使わないので、0xFF にすれば全 char で自明に成立し、span 予約/back-patch 不要。**characteristic の end_handle は実値**（`:236` で descriptor 上界に使うため 0xFF 不可）。
- **cap**: next_att が 255 超過なら以降の entity を drop（log）。value/descriptor 長も 1 byte なので value は 255 byte に truncate。
- **reverse map** (registry_lock): conn_handle→CBPeripheral; att_handle(uint8)→CBService/CBCharacteristic/CBDescriptor（Thread B の command 関数が低位 byte だけ受け取り CB object を解決）。
- **address registry**: CoreBluetooth は `peripheral.identifier`(UUID) を出し BD_ADDR を出さない。identifier を 6byte hash → **各 byte `|0x01` で非ゼロ化**（`BLE_central_gap_connect` が `mrb_get_args 'z'`(NUL 終端, `src/mruby/ble_central.c:133` 確認済み)で interior 0x00 を切断するため）。wire[4..9] に置き、AdvertisingReport が reverse して @address に、connect が @address を gap_connect へ返すので、wire 順と reverse 順の両方を CBPeripheral に紐付けて registry に保持。

## ファイル変更計画

| file | 変更 |
|---|---|
| `ports/darwin/ext/Sources/PicoBLEDarwin/PicoBLEDarwin.swift` | `pble_darwin_probe()` は不変。`PBLECentral`(CBCentralManagerDelegate+CBPeripheralDelegate) を追加し CBCentralManager(queue:`pble.cb`)・registry(os_unfair_lock)・next_att を所有。`@c`(SE-0495, **@_cdecl 不可**) export: `pble_central_init(role)`,`pble_power_on/off`,`pble_start/stop_scan`,`pble_connect(addr,addrType)`,`pble_discover_services(conn)`,`pble_discover_characteristics(conn,start,end)`,`pble_read_value(conn,valueHandle)`,`pble_discover_descriptors(conn,value,end)`。各 callback が eventByteSpec 通りに packet を作り `pble_fifo_push` を呼ぶ(didConnect では先に `pble_set_con_handle`)。command export は実 CB 呼び出しを `dispatch_async` で `pble.cb` へ。`pble_fifo_push`/`pble_set_con_handle` は C import。Swift は `BLE_push_event`/`mrb_*` を呼ばない。UUID は 128bit を LSB-first で emit（uuid128_to_uuid32 の 16bit alias 復元に依存しない: 0x180D→0x0D180000）。 |
| `ports/darwin/ble_event_bridge.c`（**新規**, Dir.glob が自動取込） | thread-safe FIFO(`{uint8_t* data; uint16_t len; node* next}` 単方向 list + fifo_lock os_unfair_lock); `pble_fifo_push`(Thread A: malloc+memcpy+append, `pthread_self()!=vm_thread` assert, mruby API 不使用); `pble_fifo_drain_one`(VM thread: head unlink → lock 外で `BLE_push_event` → free); `pble_set_con_handle`(extern con_handle 書込)。`BLE_push_event`/`BLE_heartbeat`/`BLE_write_data`/`BLE_read_data` は再定義しない。`PicoBLEDarwin-Swift.h` include。 |
| `ports/darwin/ble.c` | stub を実体化。`BLE_init`: ble_role 保存・`pthread_self()` を VM thread id 記録・`pble_central_init(role)`・probe printf。`BLE_hci_power_control`: ON→`pble_power_on()`, OFF→`pble_power_off()+pble_stop_scan()`。`BLE_gap_local_bd_addr`: memset 0 維持。`BLE_discover_primary_services`→`pble_discover_services(conn_handle)`。`BLE_discover_characteristics_for_service`→`pble_discover_characteristics`。`BLE_read_value_of_characteristic_using_value_handle`→`pble_read_value`。`BLE_discover_characteristic_descriptors`→`pble_discover_descriptors`。write_* は return-0 stub 維持。 |
| `ports/darwin/ble_central.c` | `BLE_central_set_scan_params`→no-op。`start_scan`→`pble_start_scan()`。`stop_scan`→`pble_stop_scan()`。`BLE_central_gap_connect(addr,addr_type)`→`pble_connect(addr,addr_type)`, accepted で return 0(Ruby connect() が ==0 判定)。 |
| `ports/darwin/ble_common.h` (or 新 `ble_event_bridge.h`) | `pble_fifo_push`/`pble_fifo_drain_one`/`pble_set_con_handle`/VM-thread-id setter の prototype。con_handle は extern のまま(ble_peripheral.c 定義)。 |
| `ports/darwin/ble_peripheral.c` | 機能変更なし。peripheral no-op stub と `uint16_t con_handle = 0;` 維持。 |
| `src/mruby/ble.c` | `mrb_picoruby_ble_gem_init` 内に `#ifdef PICORB_BLE_DARWIN` で `BLE#__darwin_drain`(→`pble_fifo_drain_one()`, nil 返す tiny static) を `mrb_define_method_id` 登録。BLE_init は mrb_state* を受けない(`BLE_init(const uint8_t*, int)`)ため port 単独で登録不可 → mrb_state* と class handle がある唯一の site がここ。非 Darwin は無追加。共有 4 helper と single-slot mailbox は不変。 |
| `mrblib/ble.rb` | `BLE#start` の loop, `packet = pop_packet`(現 139 行)直前に `__darwin_drain if respond_to?(:__darwin_drain)` 1 行。respond_to? guard で rp2040/esp32 は無影響。 |
| `mrbgem.rake` | build.darwin? block に `spec.cc.defines << 'PICORB_BLE_DARWIN'`。他変更なし(ble_event_bridge.c は既存 Dir.glob、新 @c export は既存 -lPicoBLEDarwin link line と emitted header に乗る、CoreBluetooth は `import CoreBluetooth` で自動 link)。 |

## 検証計画

- **Phase1 — build (host, radio 不要)**: gem の Darwin build で `swift build -c release` + `-emit-clang-header-path`。`PicoBLEDarwin-Swift.h` 再生成と新 @c export を grep 確認。`ports/darwin/*.c`(ble_event_bridge.c 含む)が -lPicoBLEDarwin に対し **`BLE_push_event`/`BLE_heartbeat`/`BLE_write_data`/`BLE_read_data` の duplicate-symbol 無し**(共有 helper 未再定義の証明)・16 個の port ABI が missing-symbol 無しでリンク。`PICORB_BLE_DARWIN` define 確認。
- **Phase2 — offset/byte-format unit check (host, radio 不要, 主 gate)**: `pble_fifo_push` に eventByteSpec 通りの手組み packet を流し、FIFO+`__darwin_drain` 経路で `BLE#packet_callback` を scan→connect→discover→read 通し駆動。assert: @services が正しい start/end/value/descriptor handle と uuid128 で埋まる; @state が :TC_IDLE に到達; handle が低位 byte で round-trip(≤255); conn_handle が 2byte で生存; descriptor UUID を offset 6 から読む; value len を offset 6 から読む; reverse_128 が canonical UUID を出す; uuid128_to_uuid32 を 16bit alias と等値比較しない。negative: 0xA0 を 1 つ落として FSM が stall することを確認。
- **Phase3 — threading check**: Swift package + bridge を ThreadSanitizer build、実機 scan で data race 0、`pble.cb` queue 上に `mrb_*`/`BLE_push_event` frame 無し、`pble_fifo_push` の assert 不発、push==drain(多 characteristic discovery で FIFO ロスト無し)、`BLE_push_event` が pop_packet ごと最大 1 回(single-slot 上書き無し)。
- **Phase4 — live CoreBluetooth E2E（実 BLE ペリフェラル必須。Claude は電波観測不可 → user/実機）**: Bluetooth 許可済みで scan→`name_include?` で device 選択→connect→discover→既知 characteristic(例: Device Info Manufacturer Name)を read、値一致と @state==:TC_IDLE を確認。多 service burst で emit/decode の 0xA1/0xA2/0xA4 と 0xA0 数一致。
- **Phase5 — connect timing**: LE_CONNECTION_COMPLETE が connect() の `start(10,:TC_IDLE)`(~1tick)窓内でなく後続 start()/scan() loop で観測される(rp2040/esp32 と同挙動)。caller は connect() が true 後も poll 継続が必要。
- Phase2/Phase4 は fresh-context verifier subagent で。

## open risks（実装時に watch）

- `__darwin_drain` hook が load-bearing。ble.rb 1 行 + macro-guarded `src/mruby/ble.c` 登録が無いと scan 中 0xda が FIFO から出ず scan が死ぬ。登録(`PICORB_BLE_DARWIN`)と毎 tick 呼び出しを確認。
- service end_handle=0xFF は「デコーダが `:169` 上界比較でしか使わない」前提でのみ正しい。将来デコーダが service.end_handle を他用途に使うと壊れる。char end_handle は実値維持(`:236`)。
- 255-handle cap: ATT entry 255 超のペリフェラルは結果 drop で 0xA0 欠落 stall の恐れ。v1 は小規模ペリフェラル対象、cap hit を log。
- NUL-free BD_ADDR: 6 byte 全てに `|0x01` を適用しないと address→CBPeripheral lookup が壊れ connect 失敗/誤接続。
- single-slot 上書き: pop_packet が tick ごと 1 回・`__darwin_drain` が tick ごと最大 1 node 前提。将来 ble.rb が 1 iteration 内で `BLE_*` + `__darwin_drain` を pop 無しで呼ぶと slot 上書きの恐れ。Phase3 の push==drain/never-overwrite assert で担保。
- value/descriptor 長 1 byte → 255 byte 超は truncate。long-value(0xA6) は decode body 無しで v1 非対応。
- v1 は単一接続(1 conn_handle)前提。並行接続は phase ordering を壊し得るので scope 外。
- registry_lock と fifo_lock は別物のまま、いずれも `BLE_push_event`/serialize を跨いで保持しない。Phase3 の TSan で担保。

## verifier verdict

**sound（blocking issue 0）**。全 9 イベントの byteSpecChecks が `matchesDecoder: true`。threadingCheck/handleCheck とも sound。minor issues(実装で吸収可):
- `pble_set_con_handle` の C `con_handle` mirror は v1 read path では不要(decoder は 0x3E packet から @conn_handle 導出、C con_handle の唯一の reader は esp32 の write path)。無害だが happy path では dead work。
- デコーダの state 名不整合(pre-existing): `init_central` コメント(`:33`)は `:TC_W4_CHARACTERISTIC_DESCRIPTOR_RESULT` だが実 transition は `:TC_W4_CHARACTERISTIC_DESCRIPTOR_VALUE_RESULT`(`:256,:261`)。設計は実行側名を採用済み。
- characteristic の 0xA2(実 end_handle 付き)を、その characteristic の descriptor 採番前に emit しないこと(char.end_handle が `:236` の descriptor 上界)。

設計の出所: workflow `ble-darwin-step3-design`（13 agent, run wf_0e998a3d-398）。
