# R2P2-iOS

A self-contained harness for building and running **PicoRuby on iOS**. It
cross-builds picoruby into a static library for the iOS Simulator and links it
into a small SwiftUI app that evaluates Ruby at runtime.

## What this is

`R2P2-iOS` connects picoruby to the iOS build system (Xcode / xcodebuild /
Simulator / signing). It is the analogue of **R2P2-ESP32** on the iOS axis: a
permanent, self-contained harness. It does **not** depend on R2P2-macOS — iOS is
its own external build system, the way ESP-IDF is for R2P2-ESP32.

picoruby bakes the prism compiler into the VM, so the cross-built `libmruby.a`
can compile and run Ruby source at runtime, on the device. The app is just a
text field, a Run button, and an output view wired to a thin C bridge.

## Status

- **Works:** Ruby runs on the iOS Simulator (arm64). `puts "hello #{1 + 2}"`
  prints `hello 3`; `raise "boom"` surfaces the exception without crashing the app.
- **Scope:** Simulator only, no Apple Developer enrollment needed (free Apple ID).
  On-device signing and BLE / CoreBluetooth are deliberate follow-ups, not here yet.

## Setup

```
# full Xcode.app (App Store) — the iOS SDK / Simulator / xcodebuild live here;
# Command Line Tools alone are NOT enough. After installing, point the toolchain
# at it (one-time, needs sudo):
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

brew install xcodegen        # generates the Xcode project from app/project.yml
# Ruby — any ambient install (rbenv / asdf / system) >= 2.7
```

```
rake check                   # verifies full Xcode / iOS SDK / xcodegen
```

## Run it

One command fetches picoruby, cross-builds the lib, generates the project,
builds, and launches the app on a Simulator — fully headless:

```
rake ios
```

`rake ios` chains: `ios:lib` → `ios:gen` → `ios:build` → `ios:run`. The app runs
the default snippet on launch (so it prints immediately) and re-runs whatever you
type when you tap **Run**.

Individual steps:

```
rake setup                   # fetch picoruby into vendor/picoruby
rake ios:lib                 # cross-build libmruby.a (arm64 iphonesimulator) → app/Vendor
rake ios:gen                 # xcodegen generate
rake ios:build               # xcodebuild for the Simulator
rake ios:run                 # boot a simulator, install, launch
rake smoke                   # host-side smoke test of the C bridge
rake clean                   # remove build output
rake clobber                 # also remove vendor/picoruby
```

The picoruby tree is selectable:

```
PICORUBY_REPO   default: https://github.com/picoruby/picoruby.git
PICORUBY_REF    default: master
IOS_MIN         default: 17.0   (iOS Simulator deployment min)
```

## How it fits together

```
app/ (SwiftUI)  ──▶  bridge/picoruby_bridge.c  ──▶  libmruby.a (iOS arm64-sim)
  ContentView        char *picoruby_eval(src)        prism compiler + mruby VM
  Run / output       compiles + runs, captures        cross-built from vendor/picoruby
                     stdout/stderr, returns a String   by build_config/r2p2-picoruby-ios-sim.rb
```

- `build_config/r2p2-picoruby-ios-sim.rb` — `MRuby::CrossBuild` targeting the
  `iphonesimulator` SDK via `xcrun`.
- `build_config/r2p2-picoruby-host.rb` — same gem set built for the host, used by
  `rake smoke` to exercise the bridge quickly.
- `bridge/picoruby_bridge.c` — evaluates Ruby and captures output (fd redirection).
- `bridge/task_hal_ios.c` — a polling task-scheduler HAL for iOS (no SIGALRM).
- `app/` — the SwiftUI app and its `project.yml` (xcodegen).

## Constraints worth knowing

To link cleanly on iOS, the VM is built with a **reduced gem set** (no
`core`/`stdlib` gemboxes, no POSIX): the iOS-incompatible IO / VFS / machine-posix
gems are dropped. Consequences for the Ruby you can run today:

- **Present:** integer/float math, `String`, string interpolation (`"x #{1+2}"`),
  `print` / `p`, `raise` and exception messages.
- **`puts`:** not in the reduced VM (it normally comes from an IO gem) — the bridge
  installs a small `puts` shim defined in terms of core `print`.
- **Absent:** file IO, networking, and the rest of stdlib. Growing this surface
  (and bringing up the R2P2 shell, BLE, on-device signing) is future work.
