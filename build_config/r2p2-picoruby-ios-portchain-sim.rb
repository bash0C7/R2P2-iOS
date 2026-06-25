# iOS Simulator port-chain model PoC: posix?=true + conf.ports :darwin,:posix.
# Proves a gem's darwin port replaces its posix port with no double-compile,
# across rng / mbedtls / io-console / machine. Not the REPL base config.

sdk_path = `xcrun --sdk iphonesimulator --show-sdk-path`.strip
clang    = `xcrun --sdk iphonesimulator --find clang`.strip
ar       = `xcrun --sdk iphonesimulator --find ar`.strip
ios_min  = ENV["IOS_MIN"] || "17.0"

MRuby::CrossBuild.new("ios-portchain-sim") do |conf|
  conf.toolchain :clang
  conf.linker.libraries.delete("m")

  conf.cc.command       = clang
  conf.linker.command   = clang
  conf.archiver.command = ar
  conf.cc.host_command  = "clang"

  conf.cc.flags << "-arch" << "arm64"
  conf.cc.flags << "-isysroot" << sdk_path
  conf.cc.flags << "-mios-simulator-version-min=#{ios_min}"

  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
  conf.cc.defines << "PICORB_ALLOC_ALIGN=8"
  conf.cc.defines << "PICORB_ALLOC_ESTALLOC"
  conf.cc.defines << "PICORB_PLATFORM_POSIX"   # iOS IS POSIX
  conf.cc.defines << "PICORB_PLATFORM_DARWIN"  # ...and darwin (additive)
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  # iOS port selection: darwin first, posix fallback.
  conf.ports :darwin, :posix

  conf.picoruby

  conf.gem core: "mruby-compiler2"

  # The four gems whose posix port reaches an iOS-absent API and thus ship
  # a darwin port. machine depends on io-console.
  conf.gem "#{MRUBY_ROOT}/mrbgems/picoruby-rng"
  conf.gem "#{MRUBY_ROOT}/mrbgems/picoruby-mbedtls"
  conf.gem "#{MRUBY_ROOT}/mrbgems/picoruby-io-console"
  conf.gem "#{MRUBY_ROOT}/mrbgems/picoruby-machine"

  # rng/mbedtls darwin ports use SecRandomCopyBytes.
  conf.linker.flags << "-framework" << "Security"
end
