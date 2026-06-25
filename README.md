# R2P2-iOS

A self-contained harness for building and running PicoRuby on iOS — on the
Simulator and on a signed physical device. It cross-builds picoruby into a
static library, links it into SwiftUI apps through a thin C bridge, and ships
examples that put the application's behavior in Ruby.

## What this is

`R2P2-iOS` connects picoruby to the iOS build system (Xcode / xcodebuild /
Simulator / signing). It is the analogue of **R2P2-ESP32** on the iOS axis: a
permanent, self-contained harness, because iOS is its own substantial external
build system the way ESP-IDF is. It does **not** depend on R2P2-macOS.

picoruby is a common PicoRuby core whose mrbgems carry per-architecture
implementations under `mrbgems/<gem>/ports/<arch>/` (rp2040 / posix / esp32 /
darwin …) behind identical interfaces. R2P2-iOS's job is to hold the iOS
**build configs** that select the iOS-appropriate ports, plus the C bridge and
the example apps. iOS-specific glue lives here; the picoruby tree stays pristine.

picoruby bakes the prism compiler into the VM, so the cross-built `libmruby.a`
compiles and runs Ruby source at runtime, on the device.

## Setup

```
# full Xcode.app (App Store) — the iOS SDK / Simulator / xcodebuild live here;
# Command Line Tools alone are NOT enough. Point the toolchain at it (needs sudo):
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

brew install xcodegen         # generates each example's Xcode project
# Ruby — any ambient install (rbenv / asdf / system) >= 2.7
```

```
rake check                    # verifies full Xcode / iOS SDK / xcodegen
```

The picoruby tree and deployment target are selectable by env:

```
PICORUBY_REPO   default: https://github.com/bash0C7/picoruby.git
PICORUBY_REF    default: picoruby-ble-darwin-port  (master + picoruby-ble Darwin port)
IOS_MIN         default: 17.0   (iOS deployment minimum)
EXAMPLE         default: repl   (which examples/<name> the base ios:* tasks build)
```

## Examples

Each example has its own README explaining where and how PicoRuby is used:
[`examples/repl`](examples/repl/README.md),
[`examples/virtual-peripheral`](examples/virtual-peripheral/README.md),
[`examples/iphone-torch`](examples/iphone-torch/README.md),
[`examples/watch-led-toggle`](examples/watch-led-toggle/README.md), and
[`examples/stackchan`](examples/stackchan/README.md).

### `repl` — evaluate Ruby on the device

A SwiftUI app with a text field, a Run button, and an output view wired to the
bridge. It compiles and runs whatever you type and shows the captured output;
`puts "hello #{1 + 2}"` prints `hello 3`, `raise "boom"` surfaces the exception
without crashing the app.

```
rake ios                      # Simulator: lib -> gen -> build -> run (headless)
rake ios:device:all           # connected device: build, sign, install, launch
```

### `virtual-peripheral` — a BLE peripheral written in Ruby

A PicoRuby-first virtual BLE peripheral, useful as a test stub for debugging a
BLE *central*. `app.rb` is a `BLE` subclass (`role :peripheral`); the **GATT
profile and every per-event behavior** (advertise / read / write / subscribe /
notify) live in it, running in a persistent VM. CoreBluetooth is driven through
picoruby-ble's Darwin port — there is no Swift CoreBluetooth code; Swift only
hosts the VM (a tick timer) and a read-only log. It advertises a Heart Rate
profile as `PBLE-TEST` and answers reads, writes, and subscriptions out of
`app.rb`. The picoruby-ble Darwin port ships in the `bash0C7/picoruby` fork that is
the default `vendor/picoruby` source — see the
[example README](examples/virtual-peripheral/README.md#dependencies).

```
rake ios:vperiph:all          # Simulator (advertising needs a real radio)
rake ios:vperiph:device:all   # connected device: build, sign, install, launch
rake ios:vperiph:write        # macOS BLE central helper that drives the peripheral
```

`rake ios:vperiph:write` builds and runs `tools/ble_write.swift`, a CoreBluetooth
central that scans for `PBLE-TEST`, connects, reads, subscribes, and writes.
`WRITE_HEX`, `TARGET_NAME`, and `APP_SERVICES` pass through the environment
(e.g. `WRITE_HEX=02 rake ios:vperiph:write`).

### `iphone-torch` — Ruby-driven flashlight (the iPhone "L チカ")

The flashlight as the LED-blink of iOS: two buttons turn the iPhone torch on and
off. The whole behaviour is Ruby — `app.rb` calls a `Torch` class, and the
`picoruby-iphone-torch` gem's Darwin port turns those calls into
`AVCaptureDevice` torch operations. The SwiftUI layer only boots the VM and
forwards button taps; there is no torch logic in Swift. See the
[example README](examples/iphone-torch/README.md) for the gem structure.

```
rake ios:torch:all            # Simulator: lib -> gen -> build -> run
rake ios:torch:device:all     # connected device: build, sign, install, launch
```

### `stackchan` — a Stack-chan BLE central written in Ruby

A PicoRuby-first BLE *central* that connects to a
[Stack-chan](https://github.com/meganetaaan/stack-chan) robot running the
`stackchan-picoruby` firmware and sends face / LED / head / torque commands over
Nordic UART Service (NUS). The entire BLE logic — scan, connect, GATT discovery,
NUS RX write — lives in `app.rb` using `picoruby-ble`'s central API; Swift only
hosts the VM and forwards button taps. The example-specific build config adds the
three stdlib gems that `picoruby-ble`'s mrblib depends on (`mruby-string-ext`,
`mruby-pack`, `mruby-sprintf`) without touching the minimal base config.

```
rake ios:stackchan:device:lib   # cross-build BLE-enabled libmruby.a for iphoneos
rake ios:stackchan:gen          # xcodegen generate
rake ios:stackchan:device:build # sign and build for the connected iPhone
rake ios:stackchan:device:run   # install + launch with console output
rake ios:stackchan:device:all   # lib -> gen -> build -> run in one step
```

See [examples/stackchan/README.md](examples/stackchan/README.md) for wiring
details, the codec test, and known device constraints.

### `watch-led-toggle` — an LED blink, in Ruby, on the Apple Watch

A watchOS standalone app: the embedded "hello world" LED, stood in by a 🔴 / 🔵
you toggle by tapping. The state machine lives in `app.rb` (`LEDApp#tick` /
`#toggle`) and runs in a persistent VM on the watch; Swift hosts the VM and
renders whatever colour Ruby returns. The notable work is the CPU ABI: a physical
Apple Watch is **`arm64_32` (ILP32 — 64-bit registers, 32-bit pointers)**, so the
VM is built `MRB_NO_BOXING` + `MRB_INT64` (word/NaN boxing are invalid on ILP32),
and an extra step recompiles the mruby objects to `arm64_32`. See the
[example README](examples/watch-led-toggle/README.md) for the full notes.

```
rake ios:watch:all            # watchOS Simulator: lib -> gen -> build -> run
# device (arm64_32) is an explicit pipeline — see the example README:
rake ios:watch:device:lib && ruby build_config/recompile_arm64_32.rb
```

### On-device builds

Device tasks build for the connected iPhone with automatic signing. Set
`DEVELOPMENT_TEAM` in the example's `project.yml` to your own team (a free Apple
ID works); the first launch of each bundle id needs a one-time on-device trust
(Settings → General → VPN & Device Management → your Apple ID → Trust).

## How it fits together

```
examples/<name>/Sources (SwiftUI)
        │  Swift ⇄ C bridging header
        ▼
bridge/picoruby_bridge.c   ──▶  libmruby.a (iOS arm64)
  repl_eval(src)                  prism compiler + mruby VM
  vm_open / vm_call / vm_close    cross-built from vendor/picoruby by
                                  build_config/r2p2-picoruby-ios-{sim,device}.rb
```

- `bridge/picoruby_bridge.c` — `repl_eval(src)` evaluates Ruby in a fresh VM and
  captures stdout/stderr; `vm_open`/`vm_call`/`vm_close` own a persistent VM and
  invoke a method on the Ruby global `$app` (used by `virtual-peripheral`). One
  owner thread touches the VM.
- `bridge/task_hal_ios.c` — a polling task-scheduler HAL for iOS (no SIGALRM).
- `build_config/r2p2-picoruby-ios-{sim,device}.rb` — `MRuby::CrossBuild` for the
  `iphonesimulator` / `iphoneos` SDKs via `xcrun`; the base reduced VM.
- `build_config/r2p2-picoruby-host.rb` — the same gem set built for the host, so
  `rake smoke` can exercise the bridge quickly.
- An example that needs extra gems (e.g. BLE) carries its own example-specific
  build config, so it never drags dependencies into the other examples' link.

Gems are linked statically; there is no runtime `require`. Every mrbgem selected
by the build config is compiled into `libmruby.a`, and its classes are registered
when the VM opens, so the example Ruby references them directly — `virtual-peripheral`'s
`app.rb` uses `BLE` with no `require`. The reduced VM has no POSIX/VFS, so file-based
`require` is not available in the first place. To make a class available to an
example, add its gem to that example's build config, not a `require` in Ruby.

## Constraints worth knowing

To link cleanly on iOS, the VM uses a **reduced gem set** — no `core`/`stdlib`
gemboxes and no POSIX, so the iOS-incompatible IO / VFS / machine-posix gems are
absent. The Ruby surface is therefore smaller than full mruby/CRuby:

- integer/float math, `String`, string interpolation, `print` / `p`, `raise`,
  `Hash`/`Array` literals + `each`, `while`, ternary, default args, and
  `begin`/`rescue` are available.
- `puts` is not in the reduced VM (it comes from an IO gem); the bridge installs
  a small `puts` shim defined in terms of core `print`.
- `defined?`, `String#ord`, `Integer#chr`, and `String#%` are absent in the base
  VM. Probe new bundled Ruby against the host build (`rake smoke`'s `libmruby.a`)
  before relying on it on-device. (Examples that need `Array#pack`, `String#<<`,
  or `sprintf` can add `mruby-pack`, `mruby-string-ext`, `mruby-sprintf` to their
  own example-scoped build config — see `examples/stackchan`.)

## Layout

```
R2P2-iOS/
  Rakefile                          check / setup / smoke / ios:* / clean / clobber
  build_config/
    r2p2-picoruby-ios-sim.rb        base reduced VM, iphonesimulator (CrossBuild)
    r2p2-picoruby-ios-device.rb     base reduced VM, iphoneos (CrossBuild)
    r2p2-picoruby-watchos-sim.rb    base reduced VM, watchsimulator (CrossBuild)
    r2p2-picoruby-watchos-device.rb base reduced VM, watchos / arm64_32 (CrossBuild)
    recompile_arm64_32.rb           recompiles the device objects to arm64_32, re-archives
    r2p2-picoruby-host.rb           same gem set, host build for rake smoke
  bridge/
    picoruby_bridge.{c,h}           repl_eval + persistent vm_open/vm_call/vm_close
    task_hal_ios.c                  polling task-scheduler HAL (no SIGALRM)
    smoke_test.c                    host-side bridge exercise
  examples/
    repl/                           evaluate Ruby on the device
    virtual-peripheral/             a BLE peripheral whose behavior lives in app.rb
      tools/ble_write.swift         macOS BLE central helper
    iphone-torch/                   Ruby-driven iPhone flashlight (picoruby-iphone-torch gem)
    watch-led-toggle/               a 🔴/🔵 LED blink in Ruby, watchOS (arm64_32)
    stackchan/                      Stack-chan BLE central: face/LED/head/torque over NUS
  vendor/picoruby/                  fetched by rake setup (gitignored)
  build/                            build output, MRUBY_BUILD_DIR (gitignored)
```
