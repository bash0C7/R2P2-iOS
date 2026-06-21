# iOS Simulator (arm64) cross-build for picoruby → libmruby.a for the
# iphonesimulator SDK. prism compiler + VM are baked in, so Ruby is compiled &
# run at runtime in-app. Mirrors the cross-build shape of picoruby's
# r2p2-picoruby-pico2.rb (target cc + host_command) and R2P2-macOS darwin defines.
#
# PICORB_PLATFORM_POSIX is intentionally omitted: iOS Simulator has __APPLE__
# defined but not gethostuuid() or other macOS-only POSIX APIs used by the
# picoruby-machine posix port. Without POSIX, the gemboxes that depend on it
# (core, stdlib) are also dropped so only the bare VM + compiler are built in.

sdk_path = `xcrun --sdk iphonesimulator --show-sdk-path`.strip
clang    = `xcrun --sdk iphonesimulator --find clang`.strip
ar       = `xcrun --sdk iphonesimulator --find ar`.strip
ios_min  = ENV["IOS_MIN"] || "17.0"

# vendor/picoruby (upstream master) defines build.posix?/wasm? but NOT darwin?.
# The bash0C7 fork adds darwin? (== PICORB_PLATFORM_DARWIN defined) and the
# picoruby-ble Darwin port's mrbgem.rake gates on it. Provide the predicate here
# so the upstream-master base can host the fork's BLE gem unchanged.
module MRuby
  class Build
    def darwin?
      cc.defines.include?("PICORB_PLATFORM_DARWIN")
    end unless method_defined?(:darwin?)
  end
end

MRuby::CrossBuild.new("ios-sim") do |conf|
  conf.toolchain :clang

  # The gcc/clang toolchain sets -lm by default, but libm is part of
  # libSystem on Apple platforms and iOS Simulator explicitly marks it
  # unavailable as a separate library. Remove it to avoid link failure.
  conf.linker.libraries.delete("m")

  conf.cc.command       = clang
  conf.linker.command   = clang
  conf.archiver.command = ar
  conf.cc.host_command  = "clang"   # builds mrbc / compiler for the host

  conf.cc.flags << "-arch" << "arm64"
  conf.cc.flags << "-isysroot" << sdk_path
  conf.cc.flags << "-mios-simulator-version-min=#{ios_min}"

  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
  conf.cc.defines << "PICORB_ALLOC_ALIGN=8"
  conf.cc.defines << "PICORB_ALLOC_ESTALLOC"
  conf.cc.defines << "PICORB_PLATFORM_DARWIN"
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  conf.picoruby

  conf.gem core: "mruby-compiler2"
  # mruby-bin-mrbc2 produces a host-executable picorbc; it must not appear in
  # a cross-build because the ios-sim linker cannot produce a host-runnable
  # binary. The host mrbc tool is built by picoruby's build_mrbc_exec hook.

  # picoruby-ble (CoreBluetooth Darwin port). The gem lives in the bash0C7
  # picoruby fork worktree, not in vendor/picoruby (upstream master, which has
  # only the rp2040 BLE port). Point at it by path; its add_dependency lines
  # (picoruby-mbedtls / picoruby-rng / picoruby-base64 / picoruby-cyw43) resolve
  # back into vendor/picoruby/mrbgems via core:. The gem's mrbgem.rake fires its
  # build.darwin? branch here (PICORB_PLATFORM_DARWIN is defined): it compiles
  # ports/darwin/*.c into libmruby.a and generates PicoBLEDarwin-Swift.h. The
  # Swift backend dylib it also builds is a macOS artifact and is NOT linked into
  # this cross-built .a (archiving ignores linker libs); the iOS app target links
  # the iOS Swift backend itself. The pble_* symbols stay undefined in the .a and
  # resolve at app-link time.
  ble_gemdir = ENV["PICORUBY_BLE_GEMDIR"] ||
    File.expand_path("../../picoruby-ble-darwin-port/mrbgems/picoruby-ble", __dir__)
  conf.gem ble_gemdir
end
