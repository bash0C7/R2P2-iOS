## このリポジトリ

`R2P2-macOS` は picoruby/picoruby の fork ではなく独立 repo。macOS host で picoruby を
build / run するための host-side harness。具体的な責務は 3 つ:

1. `rake check` で macOS の build 前提 (Xcode CLT / brew openssl@3 / Swift) を verify
2. Darwin host 用 build config を保持。picoruby 命名規約 (`r2p2-<runtime>-<target>.rb`、
   pico2 等と同列) に沿う:
   - `build_config/r2p2-picoruby-darwin.rb` — Darwin host base (Standard build / `MRUBY_CONFIG`
     未指定時の default)。`PICORB_PLATFORM_DARWIN` を立てる
   - `build_config/r2p2-picoruby-darwin-ble.rb` — base + `picoruby-ble` + `picoruby-picotest`
     opt-in (BLE Example 用)
3. 薄い rake wrapper として `vendor/picoruby/` への fetch + `MRUBY_BUILD_DIR=./build` redirect で
   fetched source を pristine に保ちながら build / run

依存する picoruby は `PICORUBY_REPO` / `PICORUBY_REF` で切替可能 (default: upstream
`picoruby/picoruby` master)。BLE Example の build には picoruby-ble Darwin port を抱える
picoruby tree (`bash0C7/picoruby` の `picoruby-ble-darwin-port` branch、2026-06-20 時点) を
指して `MRUBY_CONFIG=$(pwd)/build_config/r2p2-picoruby-darwin-ble.rb rake setup build`。

Darwin port の実装と verification scaffold (`mrbgems/picoruby-ble/ports/darwin/`) は picoruby
tree 側に住む。本 repo は build wrapper + 前提 check + Darwin host build config の格納場所。
R2P2-ESP32 が ESP-IDF という別建て build system を picoruby に接続する harness として恒久的
に必要なのとは対照的に、R2P2-macOS は picoruby/picoruby が Darwin host 用 build config を
取り込んだ時点で役目を終える transitional repo (PR 経路は picoruby fork 側、R2P2-macOS 自身は
PR しない)。
