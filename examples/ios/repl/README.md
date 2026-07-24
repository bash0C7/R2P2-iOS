# repl — evaluate Ruby on the device

日本語版: [README_jp.md](README_jp.md)

A SwiftUI app (`PicoRubyRunner`) with a text editor, a Run button, and an output
view. It compiles and runs the Ruby you type, on the device, and shows the
captured output.

## How it works

There is no bundled `.rb` in this example — the Ruby is what you type at
runtime. The cross-built `libmruby.a` carries the prism compiler inside the VM,
so the source is compiled and run on the device itself, not ahead of time.

Each Run goes through one bridge call:

```
ContentView (TextEditor + Run)
        │  repl_eval(source)            bridge/picoruby_bridge.c
        ▼
  fresh single-use PicoRuby VM         prism compiles the source, the VM runs it
        │  captured stdout + stderr     (uncaught exceptions surface as a backtrace
        ▼                               string instead of crashing the app)
  String shown in the output view
```

- `repl_eval(const char *src)` (`../../../bridge/picoruby_bridge.h`) opens a
  fresh VM, compiles and runs `src`, and returns the captured stdout+stderr —
  compile diagnostics and uncaught-exception backtraces included — as a
  malloc'd string the caller must free.
- A new VM per Run means each evaluation starts clean.
- `ContentView.run()` calls it on a background thread and frees the returned
  string; a NULL return (allocation/setup failure) is shown as
  `(VM failed to start)`.

## Files

The Ruby VM, the bridge, and the build configs live at the repo root
(`../../../bridge`, `../../../build_config`); this directory is only the app.

- `Sources/App.swift` — the `@main` app entry; one `WindowGroup`.
- `Sources/ContentView.swift` — editor + Run + output; calls `repl_eval`.
- `Sources/PicoRubyRunner-Bridging-Header.h` — exposes the C bridge to Swift.
- `project.yml` — xcodegen project; compiles the bridge sources and links
  `-lmruby` (the staged `libmruby.a` under `Vendor/lib`).
- `aot-kernel/bench_tick.{rb,rbs}` — the AOT kernel: single source of truth for
  both the interpreted baseline and the native build (see AOT native kernel below).
- `picoruby-bench_tick/` — the suppify-generated mrbgem. Not committed
  (gitignored); regenerated from `aot-kernel/`.

## Build & run

The app runs on the iOS Simulator and on a connected device.

The bare `ios:*` tasks are aliases of `ios:repl:*`, so `rake ios` builds this app.

### Simulator

```
rake ios                  # Simulator: lib -> gen -> build -> run (headless)
```

### Device

Before the first on-device build, replace `DEVELOPMENT_TEAM: YOUR_TEAM_ID` in
`project.yml` with your own Team ID — see [On-device builds](../../../README.md#on-device-builds)
for details.

```
rake ios:device:all       # connected, signed device: lib -> gen -> build -> run
```

## AOT native kernel

This example also runs a Ruby kernel as native AOT code next to the interpreted
version, to benchmark the two. `bench_tick` (`aot-kernel/bench_tick.{rb,rbs}`) is
compiled to native by matz's [spinel](https://github.com/matz/spinel) and wrapped
into the `picoruby-bench_tick` mrbgem by
[bash0C7/suppify](https://github.com/bash0C7/suppify). The seed in
`Sources/ContentView.swift` parity-checks interpreted vs native, then sweeps the
per-call batch size `n`. On a real iPhone 16e the native version reaches ~50× once
each call does enough work to amortize the VM boundary cost (VM dispatch + arg
check + spinel's `setjmp`); the interpreter stays roughly flat.

The generated gem `picoruby-bench_tick/` is **not committed** — it is gitignored
and regenerated from the kernel source, the way `vendor/picoruby` is fetched.
spinel and suppify are external tools, discovered like `cc`:

```
cd aot-kernel
SPINEL=/path/to/spinel/spinel SPINEL_LIB=/path/to/spinel/lib \
  ruby /path/to/suppify/suppify.rb bench_tick.rb -o bench_tick -t picoruby -d ..
#   -> ../picoruby-bench_tick/
```

Generation is deterministic for a given spinel/suppify version, so the gem is a
reproducible build product, not source. The build_config wires it in with one
`conf.gem` line, so `rake ios:repl:lib` needs the gem regenerated first. Full
apply-and-embed procedure: the `aot-embed` skill (`.claude/skills/aot-embed/`).

## Known constraints

The VM is built by `build_config/r2p2-picoruby-ios-repl-{sim,device}.rb` with
the full-REPL gem set, so the full `core`/`stdlib` Ruby surface is available.

- Gemboxes: `mruby-posix` + `core` + `stdlib` + `shell`, with Darwin ports
  preferred over their POSIX siblings (`conf.ports :darwin, :posix`).
- Networking gems and OpenSSL are excluded from this build config.
- The bridge prepends a one-line `puts` shim (defined via core `print`) to
  every eval; it is one physical line, so line numbers in diagnostics shift by
  exactly 1 relative to what you typed.
- See the repository README's "Constraints worth knowing" for the full picture.
