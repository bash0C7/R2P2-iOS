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

### Single binary build

`rake single` builds one executable that embeds a Ruby script as the program
it runs. The script lives inside the binary, so the file is portable: copy
it elsewhere and it still runs.

```
rake single APP=path/to/app.rb        # ./build/host/bin/<basename-of-app>
rake single APP=path/to/app.rb NAME=mybin   # ./build/host/bin/mybin
```

Internals: the task generates a throwaway `mrbgems/picoruby-bin-<NAME>/` gem
under `tmp/single/` whose `mrblib/app.rb` is the user's script, then builds
the picoruby tree with `build_config/r2p2-picoruby-darwin-single.rb`. The
build config drops the REPL/shell bins, expands `minimum` (compiler + mrbc +
VM), and includes `mruby-posix`, `core`, `stdlib` gemboxes — enough for
common scripts. For networking, fonts, native extensions, or anything else,
copy the build config and add the gems you need.

A realistic example lives at [`examples/ls.rb`](examples/ls.rb): an
`ls`-like listing of the current directory exercising `Dir.entries`,
`File.directory?` / `File.file?` / `File.symlink?` / `File.size` /
`File.expand_path`, method definitions, `while`/`if-elsif-else`, sprintf,
Array `sort`/`reject`, and inline `rescue` — i.e. the kind of patterns a
typical script needs.

```
rake single APP=examples/ls.rb
./build/host/bin/ls                   # one self-contained 1.2 MB binary
```

It prints something like:

```
Listing: /Users/you/your-dir

d        -  .git/
-     410B  .gitignore
-     4.5K  README.md
d        -  build/
...

5 files (44.4K), 9 directories
```

## Layout

```
R2P2-macOS/
  Rakefile                          setup / check / build / run / clean / clobber / single
  build_config/
    r2p2-picoruby-darwin.rb         Darwin host base (used by Standard build)
    r2p2-picoruby-darwin-ble.rb     base + picoruby-ble opt-in (used by BLE Example)
    r2p2-picoruby-darwin-single.rb  base minus REPL/shell bins (used by rake single)
  examples/
    ls.rb                           current-dir listing, demo for rake single
  vendor/picoruby/                  fetched by rake setup (gitignored)
  build/                            build output, MRUBY_BUILD_DIR (gitignored)
  tmp/single/                       throwaway bin gem generated per rake single (gitignored)
```
