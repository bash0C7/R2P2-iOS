# R2P2-macOS

標準 **PicoRuby / R2P2** を **macOS host** で動かすための環境。

## 位置付け

`picoruby/R2P2`（PicoRuby ベースの shell/OS、現在は picoruby 内の `picoruby-r2p2` gem）を
別ターゲットに載せる port repo のうち、**macOS 版**。port を分ける軸は OS なので名前は
`R2P2-macOS`（iOS が出れば `R2P2-iOS`）。`R2P2-ESP32` がチップ族 ESP-IDF を軸にするのと同じ位置付けで、
こちらは OS を軸にする。中の mruby ビルド名は `host`、platform は `posix`（エコシステムの慣習どおり）。

### 設計原則

- 依存する picoruby は **GitHub upstream `picoruby/picoruby` を `rake setup` で取得**する。
  **submodule を使わない／sibling fork に依存しない。** 取得先は `vendor/picoruby`（gitignore 済み）。
- ビルド出力は `MRUBY_BUILD_DIR=./build` で R2P2-macOS 側に隔離し、取得した picoruby source は **pristine** に保つ。
- Mac ネイティブ能力（Apple Intelligence・BLE/CoreBluetooth 等）は **本リポジトリの mrbgems** として足す
  （upstream を汚さず能力だけ追加する。これが攻撃面を絞る境界にもなる）。

## 必要環境

- macOS / Apple Silicon
- **rbenv + Ruby 4.0.5**（`.ruby-version` に固定。upstream の build.rb が `>= 2.7` を要求）
- **Homebrew `openssl@3`**（`brew install openssl@3`。networking gembox が ssl/crypto をリンク）
- git

## 使い方

```bash
rake setup     # GitHub から picoruby/picoruby を vendor/picoruby に取得（PICORUBY_REF で ref 指定、既定 master）
rake build     # 標準 r2p2 + picoruby を ./build/host にビルド（setup に依存）
rake run       # r2p2 シェルを起動（rake run APP=path/to.rb で picoruby ランナー実行）
rake clean     # ./build を削除
rake clobber   # ./build と vendor/picoruby を削除
```

再現性のため release tag に pin する場合は `PICORUBY_REF=3.4.2 rake setup`。

## 構成

```
R2P2-macOS/
├── Rakefile              # setup(fetch) / build / run / clean / clobber
├── build_config/
│   ├── common.rb         # 全 runtime 共通の VM defines
│   └── default.rb        # 標準 host(posix) ビルド: r2p2 + picoruby runner + networking
├── vendor/picoruby/      # rake setup が GitHub upstream から取得（gitignore）
└── build/                # ビルド出力 MRUBY_BUILD_DIR（gitignore）
```

Mac ネイティブ能力 gem（`mrbgems/`）は今後の増分で追加する。
