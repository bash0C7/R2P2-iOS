# Host build used only to link the bridge smoke test (Task 2). Its gem set is
# kept in EXACT parity with build_config/r2p2-picoruby-ios-sim.rb so the smoke
# test, which links against THIS build, actually predicts what the reduced
# ios-sim libmruby.a can run. Toolchain is host-appropriate (plain MRuby::Build,
# no -arch/-isysroot). PICORB_PLATFORM_POSIX is dropped to mirror ios-sim for
# maximum parity (it builds clean on the host without it).
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

MRuby::Build.new("host") do |conf|
  conf.toolchain :clang

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

  # picoruby-ble (CoreBluetooth Darwin port), kept in parity with the ios-sim
  # gem set. On the host (macOS, PICORB_PLATFORM_DARWIN) the gem's mrbgem.rake
  # build.darwin? branch builds the PicoBLEDarwin Swift dylib and links it, so a
  # host binary linking THIS libmruby.a (the bridge smoke test) pulls in the
  # CoreBluetooth backend. add_dependency lines resolve into vendor/picoruby.
  ble_gemdir = ENV["PICORUBY_BLE_GEMDIR"] ||
    File.expand_path("../../picoruby-ble-darwin-port/mrbgems/picoruby-ble", __dir__)
  conf.gem ble_gemdir
end
