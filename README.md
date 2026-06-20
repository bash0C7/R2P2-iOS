# R2P2-macOS

A staging harness for building and running PicoRuby with Darwin-native
capabilities on a macOS host.

## What this is

`picoruby/picoruby` ships per-target build configs under `build_config/`
(`r2p2-picoruby-pico2.rb`, `r2p2-femtoruby-pico_w.rb`, etc.), but as of
2026-06-20 it has none for a macOS host. R2P2-macOS stores that build config
here and wraps the fetch + build with the macOS prerequisites (Xcode CLT,
Homebrew openssl@3, Swift) verified by `rake check`. Once an equivalent
build config is contributed upstream, this repository's job ends.

R2P2-ESP32 is the analogue on the ESP-IDF axis but is permanent, because
ESP-IDF is a substantial external build system. macOS has no such external
system — Darwin-native code (e.g. picoruby-ble's CoreBluetooth port) lives
inside the picoruby tree as mrbgems with their own `mrbgem.rake`
(self-compiles Swift, links frameworks). R2P2-macOS is a thin host-side
wrapper, not a long-lived port.

## Setup

```
brew install openssl@3            # networking gembox links ssl/crypto
xcode-select --install            # clang + Swift toolchain
# Ruby — any ambient install (rbenv / asdf / system) >= 2.7
```

```
rake check                        # verifies the above
```

## Choosing what to build

The picoruby tree and build config are selectable by env:

```
PICORUBY_REPO   default: https://github.com/picoruby/picoruby.git
PICORUBY_REF    default: master
MRUBY_CONFIG    default: build_config/r2p2-picoruby-darwin.rb (Darwin host base)
```

### Standard build

Uses `build_config/r2p2-picoruby-darwin.rb` — the Darwin host base config.
It mirrors picoruby's per-target naming (parallel to `r2p2-picoruby-pico2.rb`
upstream) and sets `PICORB_PLATFORM_DARWIN` so the picoruby tree compiles as
a Darwin host build, not just a generic POSIX one.

```
rake build                        # ./build/host/bin/{r2p2,picoruby}
rake run                          # r2p2 shell
rake run APP=path/to.rb           # run a Ruby file on the picoruby runner
```

### Example: picoruby-ble Darwin port (CoreBluetooth)

The picoruby-ble Darwin port is the present macOS-dependent capability this
harness serves — it uses CoreBluetooth, which only exists on Darwin. As of
2026-06-20 the port lives at `https://github.com/bash0C7/picoruby.git` on
branch `picoruby-ble-darwin-port`. Point `PICORUBY_REPO`/`PICORUBY_REF` at
it and select the BLE build config (Darwin host base + `picoruby-ble` +
`picoruby-picotest` opt-in):

```
PICORUBY_REPO=https://github.com/bash0C7/picoruby.git \
PICORUBY_REF=picoruby-ble-darwin-port \
MRUBY_CONFIG=$(pwd)/build_config/r2p2-picoruby-darwin-ble.rb \
rake setup build
```

Tests and design docs for the port live with the port itself under
`mrbgems/picoruby-ble/ports/darwin/` in the picoruby tree.

To rebuild after editing the picoruby tree (e.g. switching branches):

```
PICORUBY_REPO=... PICORUBY_REF=... rake refresh build
```

## Layout

```
R2P2-macOS/
  Rakefile                          setup / check / build / run / clean / clobber
  build_config/
    r2p2-picoruby-darwin.rb         Darwin host base (used by Standard build)
    r2p2-picoruby-darwin-ble.rb     base + picoruby-ble opt-in (used by Example)
  vendor/picoruby/                  fetched by rake setup (gitignored)
  build/                            build output, MRUBY_BUILD_DIR (gitignored)
```
