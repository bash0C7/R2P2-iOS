# R2P2-darwin

English: [README.md](README.md)

PicoRuby を Apple プラットフォームでビルド・実行するための自己完結型ハーネスです。
対象は macOS ホスト、iOS (Simulator および署名済み実機)、watchOS の 3 つです。
picoruby を静的ライブラリにクロスビルドし、薄い C ブリッジを介して SwiftUI アプリに
リンクします。付属のサンプルはアプリの振る舞いを Ruby 側に置く構成です。macOS
ホストでは picoruby 本体の `r2p2` / `picoruby` ランナーをネイティブにビルドします。

## これは何か

`R2P2-darwin` は picoruby を Apple のビルドシステム (iOS / watchOS では Xcode /
xcodebuild / Simulator / 署名、macOS ホストでは clang + Swift) に接続します。
R2P2-ESP32 の Apple 版にあたる位置づけで、iOS / watchOS が ESP-IDF と同様に
それ自体が大きな外部ビルドシステムであるため、独立したハーネスになっています。

picoruby は PicoRuby の共通コアで、各 mrbgem が `mrbgems/<gem>/ports/<arch>/`
(rp2040 / posix / esp32 / darwin など) にアーキテクチャ別実装を持ち、
インターフェースは全 port で同一です。R2P2-darwin の役割は、Apple 向けの port を
選択するビルド設定と、C ブリッジ、サンプルアプリを保持することです。Apple 固有の
グルーはこの repo に置き、picoruby のツリーには手を入れません。

すべてのプラットフォームが単一の `vendor/picoruby` チェックアウトを共有し、
環境変数で切り替えられます。

```
PICORUBY_REPO   default: https://github.com/bash0C7/picoruby.git
PICORUBY_REF    default: port-darwin  (master + darwin ports: ble/rng/mbedtls/io-console/machine + net fix)
IOS_MIN         default: 17.0   (iOS deployment minimum。iOS ビルド設定が読む)
EXAMPLE         default: repl   (ベースの ios:* タスクがビルドする examples/ios/<name>)
```

`rake setup` がツリーを `vendor/picoruby` に取得し、`rake refresh` が既存の
チェックアウトに `PICORUBY_REF` を再取得します。ビルド成果物は `./build`
(`MRUBY_BUILD_DIR`) に出るため、取得したソースが変更されることはありません。

picoruby は prism コンパイラを VM に組み込んでいるので、クロスビルドした
`libmruby.a` は実機上で実行時に Ruby ソースをコンパイル・実行できます。

## セットアップ

iOS / watchOS のビルドにはフルの Xcode.app が必要です (iOS/watchOS SDK・
Simulator・xcodebuild はそこに入っており、Command Line Tools だけでは足りません)。
macOS ホストビルドは Command Line Tools だけで動きます。Homebrew の `openssl@3`
はネットワーク系 gembox (ssl/crypto) を含むホストビルドでのみ必須で、それ以外では
任意です。

```
# フルの Xcode.app (App Store) — iOS / watchOS 用。ツールチェーンを向ける (sudo が必要):
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

brew install xcodegen         # 各サンプルの Xcode プロジェクトを生成 (iOS / watchOS)
brew install openssl@3        # ネットワーク系 gembox (ssl/crypto) を含む macOS ホストビルドのみ
# Ruby — rbenv / asdf / システムなど手元のもの >= 2.7
```

```
rake check                    # フル Xcode / iOS SDK / xcodegen を確認
rake macos:check              # ホストビルド向けに Xcode CLT / brew openssl@3 / Swift を確認
```

## サンプル

iOS と watchOS の項目はサンプルアプリです。macOS の節はサンプルアプリではなく
ホストのビルドモードを扱います。iOS / watchOS の各サンプルには、PicoRuby を
どこでどう使っているかを説明する README があります。

- [`examples/ios/repl`](examples/ios/repl/README.md)
- [`examples/ios/networking`](examples/ios/networking/README.md)
- [`examples/ios/virtual-peripheral`](examples/ios/virtual-peripheral/README.md)
- [`examples/ios/iphone-torch`](examples/ios/iphone-torch/README.md)
- [`examples/ios/stackchan`](examples/ios/stackchan/README.md)
- [`examples/ios/tilt-synth`](examples/ios/tilt-synth/README.md)
- [`examples/watchos/led-toggle`](examples/watchos/led-toggle/README.md)

### iOS

各 iOS サンプルは Simulator 向けと、接続した署名済み実機向けにビルドできます。

#### repl — 実機上で Ruby を評価する

テキストフィールド・Run ボタン・出力ビューをブリッジにつないだ SwiftUI アプリです。
入力した Ruby をその場でコンパイル・実行し、キャプチャした出力を表示します。
`puts "hello #{1 + 2}"` は `hello 3` を出力し、`raise "boom"` はアプリを落とさずに
例外を表示します。

```
rake ios                      # Simulator: lib -> gen -> build -> run (ヘッドレス)
rake ios:device:all           # 接続した実機: build, sign, install, launch
```

#### networking — Ruby から HTTP/TLS

生の BSD ソケットと mbedTLS ハンドシェイクを、upstream の `picoruby-net` gem の
`Net::HTTPSClient` から駆動します。エントロピーは `picoruby-mbedtls` /
`picoruby-rng` の Darwin port (`SecRandomCopyBytes`) が供給します。OpenSSL も
`URLSession` も使わず、PicoRuby 自身の TLS が実機上で動きます。`repl` と同じく
full-REPL gembox (`posix?=true`) が必要で、他のサンプルが使う reduced VM では
動きません。gembox を選ぶ理由と、このサンプルが依存する fork 側の修正については
[サンプルの README](examples/ios/networking/README.md) を参照してください。

```
rake ios:net:all              # Simulator: lib -> gen -> build -> run
rake ios:net:device:all       # 接続した実機: build, sign, install, launch
```

#### virtual-peripheral — Ruby で書いた BLE ペリフェラル

PicoRuby 主導の仮想 BLE ペリフェラルで、BLE セントラルをデバッグする際のテスト
スタブとして使えます。`app.rb` は `BLE` のサブクラス (`role :peripheral`) で、GATT
プロファイルとイベントごとの振る舞い (advertise / read / write / subscribe /
notify) がすべてそこに書かれ、永続 VM の中で動きます。CoreBluetooth は
picoruby-ble の Darwin port 経由で駆動され、Swift 側に CoreBluetooth のコードは
ありません。Swift は VM のホスト (tick タイマー) と読み取り専用ログだけを持ちます。
`PBLE-TEST` という名前で Heart Rate プロファイルを advertise し、read / write /
subscribe に `app.rb` から応答します。picoruby-ble の Darwin port は、default の
`vendor/picoruby` ソースである `bash0C7/picoruby` fork に入っています —
[サンプルの README](examples/ios/virtual-peripheral/README.md#dependencies) を
参照してください。

```
rake ios:vperiph:all          # Simulator (advertise には実際の無線が必要)
rake ios:vperiph:device:all   # 接続した実機: build, sign, install, launch
rake ios:vperiph:write        # ペリフェラルを駆動する macOS BLE セントラルヘルパー
```

`rake ios:vperiph:write` は `examples/ios/virtual-peripheral/tools/ble_write.swift`
をビルドして実行します。`PBLE-TEST` をスキャンし、接続・read・subscribe・write を
行う CoreBluetooth セントラルです。`WRITE_HEX`、`TARGET_NAME`、`APP_SERVICES` を
環境変数で渡せます (例: `WRITE_HEX=02 rake ios:vperiph:write`)。

#### iphone-torch — Ruby で操作するフラッシュライト (iPhone の「L チカ」)

iOS における LED 点滅にあたるフラッシュライトの例で、2 つのボタンで iPhone の
トーチを点灯・消灯します。振る舞いはすべて Ruby です。`app.rb` が `Torch` クラスを
呼び、`picoruby-iphone-torch` gem の Darwin port がその呼び出しを
`AVCaptureDevice` のトーチ操作に変換します。SwiftUI 層は VM の起動とボタンタップの
転送だけを行い、Swift 側にトーチのロジックはありません。gem の構造は
[サンプルの README](examples/ios/iphone-torch/README.md) を参照してください。

```
rake ios:torch:all            # Simulator: lib -> gen -> build -> run
rake ios:torch:device:all     # 接続した実機: build, sign, install, launch
```

#### stackchan — Ruby で書いた Stack-chan 向け BLE セントラル

`stackchan-picoruby` ファームウェアで動く
[Stack-chan](https://github.com/meganetaaan/stack-chan) ロボットに接続し、
Nordic UART Service (NUS) 経由で顔 / LED / 首 / トルクのコマンドを送る、PicoRuby
主導の BLE セントラルです。scan・connect・GATT discovery・NUS RX write という BLE
ロジック全体が、`picoruby-ble` のセントラル API を使って `app.rb` に書かれています。
Swift は VM のホストとボタンタップの転送だけを担当します。サンプル専用のビルド設定
が、`picoruby-ble` の mrblib が依存する 3 つの stdlib gem (`mruby-string-ext`、
`mruby-pack`、`mruby-sprintf`) を、最小構成のベース設定に触れずに追加します。
配線の詳細・コーデックテスト・既知の実機制約は
[examples/ios/stackchan/README.md](examples/ios/stackchan/README.md) を参照して
ください。

```
rake ios:stackchan:device:lib   # BLE 入り libmruby.a を iphoneos 向けにクロスビルド
rake ios:stackchan:gen          # xcodegen generate
rake ios:stackchan:device:build # 接続した iPhone 向けに署名してビルド
rake ios:stackchan:device:run   # インストールしてコンソール出力付きで起動
rake ios:stackchan:device:all   # lib -> gen -> build -> run を一括実行
```

#### tilt-synth — Ruby で書いた Device Motion FM シンセサイザー

iPhone を傾けると Ruby が音を出します。`app.rb` が `picoruby-iphone-motion` gem の
Darwin port (`CMDeviceMotion`) から Device Motion の姿勢 (pitch / roll) を読み、
pitch を 2 オクターブの C メジャーペンタトニックスケールに量子化し、roll を FM
depth にマッピングして、`picoruby-iphone-synth` gem の Darwin port 経由で
`AVAudioEngine` の sine+FM オシレーターを駆動します。スケール・レンジ・tick ループ
はすべて `app.rb` にあり、どちらの gem の Swift バックエンドにも音楽マッピングの
ロジックはありません。両 gem は `vendor/picoruby` に無いローカル mrbgem で、
`picoruby-iphone-torch` と同じ構造です。ボタンはなく、VM 起動の瞬間から tick
タイマーが回り続けます — `virtual-peripheral` と同じ常時稼働モデルです。Simulator
には Device Motion が無いため `Motion#available?` は `false` になり、アプリは無音の
ままです。Simulator ターゲットはビルドがリンクでき VM が動くことの確認用です。
`ruby examples/ios/tilt-synth/test_mapping.rb` で量子化 / clamp の計算を Xcode
なしで検証できます。詳細は
[サンプルの README](examples/ios/tilt-synth/README.md) を参照してください。

```
rake ios:tiltsynth:all          # Simulator: lib -> gen -> build -> run
rake ios:tiltsynth:device:all   # 接続した実機: build, sign, install, launch (実際の傾き + 音)
```

### macOS

macOS では picoruby をホスト上でネイティブに動かします。以下の小節はサンプル
アプリではなくホストのビルドモードです。成果物は `./build/host/bin` に出ます。
ビルド設定は `MRUBY_CONFIG` で選択でき、default は
`build_config/r2p2-picoruby-darwin.rb` (Darwin ホストのベース設定) です。これは
`PICORB_PLATFORM_DARWIN` を立て、ツリーを汎用 POSIX ではなく Darwin ホストビルド
としてコンパイルします。

#### 標準ビルド

```
rake macos:build                    # ./build/host/bin/{r2p2,picoruby}
rake macos:run                      # r2p2 シェル
rake macos:run APP=path/to.rb       # picoruby ランナーで Ruby ファイルを実行
```

#### BLE バリアント (CoreBluetooth)

picoruby-ble の Darwin port は CoreBluetooth を使い、これは Darwin にしか
ありません。BLE 用ビルド設定 (Darwin ホストベース + `picoruby-ble` +
`picoruby-picotest` のオプトイン) を選択します。

```
MRUBY_CONFIG=$(pwd)/build_config/r2p2-picoruby-darwin-ble.rb rake macos:build
```

port のテストと設計ドキュメントは、picoruby ツリー側の
`mrbgems/picoruby-ble/ports/darwin/` に port 本体と一緒に置かれています。

#### シングルバイナリ

`rake macos:single` は Ruby スクリプトを埋め込んだ実行ファイルを 1 つビルドします
(`APP=` は必須、`NAME=` は任意で、省略するとスクリプトの basename になります)。
スクリプトはバイナリの中に入るため、ファイル単体で
持ち運べます。`examples/macos/ls/ls.rb` は現実的なデモで、カレントディレクトリを
`ls` 風に一覧します。

```
rake macos:single APP=examples/macos/ls/ls.rb   # ./build/host/bin/ls
./build/host/bin/ls                             # 自己完結した 1 バイナリ
```

### watchOS

watchOS のサンプルは watchOS Simulator 向けと実機の Apple Watch (`arm64_32`)
向けにビルドできます。

#### led-toggle — Apple Watch 上の Ruby で LED 点滅

watchOS のスタンドアロンアプリです。組み込みの「hello world」である LED を、タップ
で切り替わる赤 / 青の円で置き換えています。状態機械は `app.rb` (`LEDApp#tick` /
`#toggle`) にあり、watch 上の永続 VM で動きます。Swift は VM をホストし、Ruby が
返した色を描画するだけです。特筆すべきは CPU ABI で、物理 Apple Watch は
`arm64_32` (ILP32 — レジスタ 64-bit、ポインタ 32-bit) です。そのため VM は
`MRB_NO_BOXING` + `MRB_INT64` でビルドし (word / NaN boxing は ILP32 では成立
しません)、追加ステップで mruby のオブジェクトを `arm64_32` に再コンパイルします。
詳細は [サンプルの README](examples/watchos/led-toggle/README.md) を参照して
ください。

```
rake watchos:led:all          # watchOS Simulator: lib -> gen -> build -> run
rake watchos:led:device:all   # 接続した Apple Watch: build, sign, install, launch
```

### 実機ビルド

device 系タスクは、接続した iPhone / Apple Watch 向けに自動署名でビルドします。
各サンプルの `project.yml` の `DEVELOPMENT_TEAM` を自分のチームに設定してください
(無料の Apple ID でも可)。bundle id ごとに、初回起動時に実機上での信頼設定が
1 回必要です (設定 → 一般 → VPN とデバイス管理 → 自分の Apple ID → 信頼)。

## 全体の構成

```
examples/ios/<name>/Sources (SwiftUI)
        │  Swift ⇄ C bridging header
        ▼
bridge/picoruby_bridge.c   ──▶  libmruby.a (iOS arm64)
  repl_eval(src)                  prism compiler + mruby VM
  vm_open / vm_call / vm_close    cross-built from vendor/picoruby by
                                  build_config/r2p2-picoruby-ios-repl-{sim,device}.rb
```

- `bridge/picoruby_bridge.c` — `repl_eval(src)` は使い捨ての VM で Ruby を評価し
  stdout/stderr をキャプチャします。`vm_open`/`vm_call`/`vm_close` は永続 VM を
  保持し、Ruby のグローバル `$app` のメソッドを呼びます (`repl` 以外の全サンプルが
  使用)。VM に触るのは単一のオーナースレッドだけです。
- `bridge/task_hal_ios.c` — iOS 向けのポーリング式タスクスケジューラ HAL
  (SIGALRM 不使用)。
- `build_config/r2p2-picoruby-ios-repl-{sim,device}.rb` — `xcrun` で
  `iphonesimulator` / `iphoneos` SDK に向けた `MRuby::CrossBuild`。full-REPL VM。
- `build_config/r2p2-picoruby-host.rb` — 同じ gem 構成のホストビルド。`rake smoke`
  でブリッジを素早く検証するためのものです。
- `build_config/r2p2-picoruby-darwin.rb` — `macos:` タスク用の Darwin ホスト
  ベース。クロスビルドではなくネイティブビルドです。
- 追加の gem (BLE など) が要るサンプルは、専用のビルド設定を持ちます。他の
  サンプルのリンクに依存を持ち込まないためです。

gem は静的リンクされ、実行時の `require` はありません。ビルド設定が選択した
mrbgem はすべて `libmruby.a` にコンパイルされ、VM オープン時にクラスが登録される
ので、サンプルの Ruby は直接それを参照します — `virtual-peripheral` の `app.rb` は
`require` なしで `BLE` を使います。reduced VM には POSIX/VFS が無いため、そもそも
ファイルベースの `require` は使えません。サンプルからクラスを使えるようにするには、
Ruby に `require` を書くのではなく、そのサンプルのビルド設定に gem を追加します。

## 知っておくべき制約

iOS/watchOS のサンプルには、サンプルごとに 2 種類の gembox 構成が共存しています。

`virtual-peripheral` / `iphone-torch` / `stackchan` / `tilt-synth` /
`led-toggle` は reduced gem set を使います。`core`/`stdlib` gembox も POSIX も
含まないため、iOS 非対応の IO / VFS / machine-posix 系 gem は入っていません。
その分、使える Ruby の範囲はフルの mruby/CRuby より狭くなります。

- 整数 / 浮動小数点演算、`String`、文字列補間、`print` / `p`、`raise`、
  `Hash`/`Array` リテラル + `each`、`while`、三項演算子、デフォルト引数、
  `begin`/`rescue` は使えます。
- `puts` は reduced VM にありません (IO 系 gem 由来のため)。ブリッジがコアの
  `print` を使った小さな `puts` shim を導入します。
- `defined?`、`String#ord`、`Integer#chr`、`String#%` はベース VM にありません。
  新しく組み込む Ruby は、実機で使う前にホストビルド (`rake smoke` の
  `libmruby.a`) で動作を確かめてください。
- `Array#pack`、`String#<<`、`sprintf` が要るサンプルは、`mruby-pack`、
  `mruby-string-ext`、`mruby-sprintf` を自分専用のビルド設定に追加します —
  `examples/ios/stackchan` を参照してください。

`repl` / `networking` は full-REPL gembox (`mruby-posix` + `core` + `stdlib` +
`shell`、`build.posix?` が true、`conf.ports :darwin, :posix`) を使います。iOS を
POSIX ターゲットとして扱い、gem ごとに `ports/darwin` を優先、`ports/posix` を
フォールバックにします。これにより `Array#map`、`RNG`/`Machine`、ホストアプリを
落とさず `mrb_print_error` 経由でバックトレース付きで表示される例外など、
`core`/`stdlib` のフルの Ruby が使えるようになりますが、そのぶんリンクは大きく
なります。他のサンプルが reduced gembox に留まるのはこのためです。`Machine.unique_id` が
iOS で `nil` を返すのは設計どおりです (`ports/darwin/machine.c`: iOS には C だけで
取れる安定した unique id が無いため、でっち上げずに利用不可と報告します)。バグでは
ありません。

## vendor の fork: darwin ports と picoruby-net の POSIX 修正

default の `vendor/picoruby` ソース (`bash0C7/picoruby` の `port-darwin` branch)
は、darwin ports (ble / rng / mbedtls / io-console / machine) と、picoruby-net の
POSIX port への修正を含んでいます。修正の内容は、
`mrbgems/picoruby-net/ports/posix/{tcp,tls,udp}_client.c` が受信バッファ
(`res->recv_data`) を VM アロケータ (`picorb_alloc` / `picorb_realloc` /
`picorb_free`。実体は `mrb_malloc` / `mrb_realloc` / `mrb_free`) で確保する
ことです。これにより `src/mruby/net.c` が解放に使う `mrb_free` と対になり、
LwIP 経路 (`src/tcp.c`) と同じ規律になります。共有の POSIX port への修正なので、
macOS ホストビルドを含む picoruby-net の全 POSIX ビルドに適用されます。mruby の
default アロケータ (`mrb_open`) では `mrb_free` がシステムの `free` なのでこの
区別は効きませんが、iOS ブリッジは `mrb_open_with_custom_alloc` で VM を独自の
8 MB estalloc プール (`bridge/picoruby_bridge.c`) 上に開くため、システムヒープの
ポインタをプールの free に渡してはならず、iOS でのネットワーキングはこの修正に
依存します。upstream の `picoruby/picoruby` master には darwin ports もこの修正も
無いため、`PICORUBY_REF` を upstream に向けると、fork にしか無いコードに依存する
`networking` (アロケータ修正と darwin の mbedtls/rng エントロピー port) や
`virtual-peripheral` / `stackchan` (picoruby-ble の darwin port) が動かなく
なります。

## レイアウト

```
R2P2-darwin/
  Rakefile                          check / setup / refresh / smoke / host:lib / ios:* / watchos:led:* / clean / clobber
  rakelib/
    macos.rake                      macos:check / macos:build / macos:run / macos:single
  build_config/
    r2p2-picoruby-ios-repl-sim.rb    full REPL (posix?=true + darwin port-chain), iphonesimulator (CrossBuild)
    r2p2-picoruby-ios-repl-device.rb full REPL (posix?=true + darwin port-chain), iphoneos (CrossBuild)
    r2p2-picoruby-ios-net-sim.rb     full-REPL gembox + picoruby-net, iphonesimulator (CrossBuild)
    r2p2-picoruby-ios-net-device.rb  full-REPL gembox + picoruby-net, iphoneos (CrossBuild)
    r2p2-picoruby-ios-mbedtls-sim.rb base reduced VM + picoruby-mbedtls のみ, symbol-level check 用
    r2p2-picoruby-ios-rng-sim.rb     base reduced VM + picoruby-rng のみ, symbol-level check 用
    r2p2-picoruby-ios-io-console-sim.rb base reduced VM + picoruby-io-console のみ, symbol-level check 用
    r2p2-picoruby-ios-vperiph-{sim,device}.rb   base reduced VM + picoruby-ble, darwin port
    r2p2-picoruby-ios-torch-{sim,device}.rb     base reduced VM + picoruby-iphone-torch, darwin port
    r2p2-picoruby-ios-stackchan-{sim,device}.rb base reduced VM + picoruby-ble + pack/string-ext/sprintf
    r2p2-picoruby-ios-tiltsynth-{sim,device}.rb base reduced VM + ローカルの motion/synth gem, darwin ports
    r2p2-picoruby-watchos-sim.rb    base reduced VM, watchsimulator (CrossBuild)
    r2p2-picoruby-watchos-device.rb base reduced VM, watchos / arm64_32 (CrossBuild)
    recompile_arm64_32.rb           device のオブジェクトを arm64_32 に再コンパイルして再アーカイブ
    r2p2-picoruby-host.rb           同じ gem 構成のホストビルド (rake smoke 用)
    r2p2-picoruby-darwin.rb         Darwin ホストベース (macos:build の default)
    r2p2-picoruby-darwin-ble.rb     Darwin ホストベース + picoruby-ble オプトイン
    r2p2-picoruby-darwin-single.rb  Darwin ホストベースから REPL/shell bin を除いたもの (macos:single)
    r2p2-stackchan-pc.rb            Stack-chan PC セントラル向けの Darwin ホストビルド設定
  bridge/
    picoruby_bridge.{c,h}           repl_eval + 永続 vm_open/vm_call/vm_close
    task_hal_ios.c                  ポーリング式タスクスケジューラ HAL (SIGALRM 不使用)
    smoke_test.c                    ホスト側でのブリッジ動作確認
  docs/                             設計プランと handoff ノート
  examples/
    ios/
      repl/                         実機上で Ruby を評価
      networking/                   Ruby から HTTP/TLS (picoruby-net + mbedTLS)
      virtual-peripheral/           振る舞いが app.rb にある BLE ペリフェラル
        tools/ble_write.swift       macOS BLE セントラルヘルパー
      iphone-torch/                 Ruby で操作する iPhone フラッシュライト (picoruby-iphone-torch gem)
      stackchan/                    Stack-chan BLE セントラル: 顔/LED/首/トルクを NUS で送信
      tilt-synth/                   Device Motion FM シンセ。マッピングは app.rb
        picoruby-iphone-motion/     ローカル gem: CMDeviceMotion attitude -> Motion
        picoruby-iphone-synth/      ローカル gem: AVAudioEngine sine+FM -> Synth
    macos/
      ls/ls.rb                      カレントディレクトリの一覧。rake macos:single のデモ
    watchos/
      led-toggle/                   赤/青の LED 点滅を Ruby で。watchOS (arm64_32)
  vendor/picoruby/                  rake setup が取得 (gitignored)
  build/                            ビルド成果物。MRUBY_BUILD_DIR (gitignored)
  tmp/single/                       macos:single ごとに生成される使い捨て bin gem (gitignored)
```
