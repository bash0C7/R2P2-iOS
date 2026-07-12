require "shellwords"
require "rbconfig"

ROOT          = __dir__
PICORUBY_REPO = ENV["PICORUBY_REPO"] || "https://github.com/bash0C7/picoruby.git"
PICORUBY_REF  = ENV["PICORUBY_REF"]  || "port-darwin"
PICORUBY_SRC  = File.join(ROOT, "vendor", "picoruby")
BUILD_DIR     = File.join(ROOT, "build")
EXAMPLE       = ENV["EXAMPLE"] || "repl"
APP_DIR       = File.join(ROOT, "examples", "ios", EXAMPLE)
VENDOR_DIR    = File.join(APP_DIR, "Vendor")
BUNDLE_ID     = "com.bash0c7.picoruby.PicoRubyRunner"

def mruby_env(cfg)
  { "MRUBY_BUILD_DIR" => BUILD_DIR, "MRUBY_CONFIG" => File.absolute_path(cfg) }
end

# Cross-build libmruby.a with the given build_config and stage the archive +
# picoruby headers under <vendor_dir>. `build_name` is the MRuby build name (the
# build/<name>/ output dir). Shared by each example's lib task.
def stage_libmruby(config_basename, build_name, vendor_dir)
  cfg = File.join(ROOT, "build_config", config_basename)
  sh mruby_env(cfg), "cd #{PICORUBY_SRC.shellescape} && rake"
  lib = File.join(BUILD_DIR, build_name, "lib", "libmruby.a")
  raise "expected #{lib} not found" unless File.file?(lib)
  rm_rf vendor_dir
  mkdir_p File.join(vendor_dir, "lib")
  mkdir_p File.join(vendor_dir, "include")
  cp lib, File.join(vendor_dir, "lib", "libmruby.a")
  cp_r File.join(PICORUBY_SRC, "include", "."), File.join(vendor_dir, "include")
  puts "Staged #{build_name} libmruby.a + headers under #{vendor_dir}"
end

# The vendored prism (picoruby -> mruby -> mrbgems/mruby-compiler-prism) ships
# its templates but not the files they generate; templates/template.rb produces
# include/prism/diagnostic.h. The host mrbc (picoruby's build_mrbc_exec hook)
# compiles prism during the presym scan, before any mrbgem.rake can run the
# generator, so on a clean clone the build aborts on the missing header.
# Generate it right after fetch. Skips when template.rb is absent (template
# layout differs) or diagnostic.h already exists (a picoruby that generates it
# itself); the generator is idempotent either way.
PRISM_TEMPLATE_DIR = File.join(
  PICORUBY_SRC,
  "mrbgems", "picoruby-mruby", "lib", "mruby",
  "mrbgems", "mruby-compiler-prism", "lib", "prism"
)

def generate_prism_templates
  template = File.join(PRISM_TEMPLATE_DIR, "templates", "template.rb")
  generated = File.join(PRISM_TEMPLATE_DIR, "include", "prism", "diagnostic.h")
  unless File.exist?(template)
    puts "prism templates: template.rb absent (#{template}); skipping"
    return
  end
  if File.exist?(generated)
    puts "prism templates: diagnostic.h already present; skipping"
    return
  end
  sh "cd #{PRISM_TEMPLATE_DIR.shellescape} && #{RbConfig.ruby.shellescape} templates/template.rb"
end

# Destination id of the SPECIFIC connected device (not generic/platform=...) so
# -allowProvisioningUpdates can register it with the Personal Team and generate
# a profile. `platform` is "iOS" or "watchOS".
def connected_destination(proj, scheme, platform)
  dest = `xcodebuild -project #{proj.shellescape} -scheme #{scheme} -showdestinations 2>/dev/null`.lines
         .grep(/platform:#{platform},/).reject { |l| l =~ /Simulator|placeholder/ }
         .first&.match(/id:(\S+)/)&.captures&.first
  raise "no connected #{platform} device destination (xcodebuild -showdestinations)" unless dest
  dest
end

# Signed device build against the connected device. Automatic signing resolves
# the team set in the example's project.yml.
def device_build(proj, scheme, derived, archs:, platform: "iOS")
  dest = connected_destination(proj, scheme, platform)
  sh "xcodebuild -project #{proj.shellescape} -scheme #{scheme} " \
     "-destination 'id=#{dest}' " \
     "-derivedDataPath #{derived.shellescape} " \
     "ARCHS=#{archs} -allowProvisioningUpdates build"
end

# Simulator build. libmruby.a (and, where present, the PicoBLEDarwin Swift
# package) are arm64 only; restrict to arm64 so the linker does not reject them
# for the x86_64 slice of the generic simulator destination.
def sim_build(proj, scheme, derived, platform: "iOS Simulator", exclude_x86_64: true)
  archs = "ARCHS=arm64 ONLY_ACTIVE_ARCH=NO"
  archs += " EXCLUDED_ARCHS=x86_64" if exclude_x86_64
  sh "xcodebuild -project #{proj.shellescape} " \
     "-scheme #{scheme} -destination 'generic/platform=#{platform}' " \
     "-derivedDataPath #{derived.shellescape} " \
     "#{archs} build"
end

# Path to the built .app under <derived>/Build/Products; raises with the build
# task to run when absent. `products_glob` selects the platform products dir
# (e.g. "*-iphonesimulator", "*-iphoneos", "*-watchos").
def built_app(derived, products_glob, app_name, build_task)
  app = Dir.glob(File.join(derived, "Build", "Products", products_glob, "#{app_name}.app")).first
  raise "app not built; run `rake #{build_task}`" unless app
  app
end

# Boot the first available simulator matching `device_label` ("iPhone" or
# "Apple Watch"), then install and launch the app.
def sim_install_launch(device_label, app, bundle_id)
  udid = `xcrun simctl list devices available`.lines
         .grep(/#{device_label}/).first&.match(/\(([0-9A-F-]{36})\)/)&.captures&.first
  raise "no available #{device_label} simulator" unless udid
  sh "xcrun simctl boot #{udid} 2>/dev/null; true"
  sh "open -a Simulator"
  sh "xcrun simctl install #{udid} #{app.shellescape}"
  sh "xcrun simctl launch #{udid} #{bundle_id}"
end

# UUID of the first connected device matching `pattern` (/iPhone|iPad/ or
# /Watch/); `label` names it in the error message.
def devicectl_udid(pattern, label)
  dev = `xcrun devicectl list devices`.lines
        .grep(pattern).first
        &.match(/([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})/)&.captures&.first
  raise "no connected #{label} (xcrun devicectl list devices)" unless dev
  dev
end

# Install and launch the app on the connected device via devicectl.
def device_install_launch(pattern, label, app, bundle_id)
  dev = devicectl_udid(pattern, label)
  sh "xcrun devicectl device install app --device #{dev} #{app.shellescape}"
  sh "xcrun devicectl device process launch --console --device #{dev} #{bundle_id}"
end

desc "Verify iOS build prerequisites"
task :check do
  if File.directory?("/Applications/Xcode.app") &&
     system("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path", out: File::NULL, err: File::NULL)
    puts "iOS SDK:    ok"
  else
    abort "iOS SDK:    missing — install full Xcode.app (App Store); CLT alone is not enough"
  end
  if system("which", "xcodegen", out: File::NULL, err: File::NULL)
    puts "xcodegen:   ok"
  else
    warn "xcodegen:   missing — run `brew install xcodegen`"
  end
end

desc "Fetch picoruby into vendor/picoruby"
task :setup do
  unless Dir.exist?(PICORUBY_SRC)
    sh "git clone --recursive --branch #{PICORUBY_REF.shellescape} " \
       "#{PICORUBY_REPO.shellescape} #{PICORUBY_SRC.shellescape}"
  end
  generate_prism_templates
end

desc "Re-fetch PICORUBY_REF into the existing vendor/picoruby"
task :refresh do
  raise "vendor/picoruby absent; run `rake setup`" unless Dir.exist?(PICORUBY_SRC)
  sh "git -C #{PICORUBY_SRC.shellescape} fetch #{PICORUBY_REPO.shellescape} #{PICORUBY_REF.shellescape}"
  sh "git -C #{PICORUBY_SRC.shellescape} checkout -B #{PICORUBY_REF.shellescape} FETCH_HEAD"
  sh "git -C #{PICORUBY_SRC.shellescape} submodule update --init --recursive"
  generate_prism_templates
end

# Defines the full ios:<name> namespace for one example app:
# lib/gen/build/run/all for the Simulator plus a device:{lib,build,run,all}
# sub-namespace. Paths derive from the parameters:
#   examples/ios/<dir>/<scheme>.xcodeproj, bundle com.bash0c7.picoruby.<scheme>,
#   build_config/r2p2-picoruby-ios-<name>-{sim,device}.rb,
#   build/ios-<name>-{sim,device} (libmruby), build/ios-<name>-app{,-device}
#   (derived data). `label` names the app in task descriptions; `lib_phrase`
#   states what the libmruby build includes (`device_lib_phrase` overrides it
#   for the device lib task).
def define_ios_example(name:, label:, dir:, scheme:, lib_phrase:, device_lib_phrase: lib_phrase)
  app_dir        = File.join(ROOT, "examples", "ios", dir)
  proj           = File.join(app_dir, "#{scheme}.xcodeproj")
  bundle         = "com.bash0c7.picoruby.#{scheme}"
  vendor         = File.join(app_dir, "Vendor")
  derived        = File.join(ROOT, "build", "ios-#{name}-app")
  device_derived = File.join(ROOT, "build", "ios-#{name}-app-device")
  vendor_rel     = "examples/ios/#{dir}/Vendor"

  namespace :ios do
    namespace name do
      desc "Cross-build libmruby.a (Simulator) #{lib_phrase} and stage under #{vendor_rel}"
      task lib: :setup do
        stage_libmruby("r2p2-picoruby-ios-#{name}-sim.rb", "ios-#{name}-sim", vendor)
      end

      desc "Generate the #{label} Xcode project from project.yml"
      task :gen do
        sh "cd #{app_dir.shellescape} && xcodegen generate"
      end

      desc "Build the #{label} app for the iOS Simulator"
      task :build do
        sim_build(proj, scheme, derived)
      end

      desc "Boot a simulator, install, and launch the #{label} app"
      task :run do
        app = built_app(derived, "*-iphonesimulator", scheme, "ios:#{name}:build")
        sim_install_launch("iPhone", app, bundle)
      end

      desc "Full #{label} Simulator pipeline: lib -> gen -> build -> run"
      task all: [:lib, :gen, :build, :run]

      namespace :device do
        desc "Cross-build libmruby.a (iphoneos arm64) #{device_lib_phrase} and stage under #{vendor_rel}"
        task lib: :setup do
          stage_libmruby("r2p2-picoruby-ios-#{name}-device.rb", "ios-#{name}-device", vendor)
        end

        desc "Build the #{label} app, signed, for the connected iOS device"
        task :build do
          device_build(proj, scheme, device_derived, archs: "arm64")
        end

        desc "Install and launch the #{label} app on the connected iOS device"
        task :run do
          app = built_app(device_derived, "*-iphoneos", scheme, "ios:#{name}:device:build")
          device_install_launch(/iPhone|iPad/, "iOS device", app, bundle)
        end

        desc "Full #{label} device pipeline: lib -> gen -> build -> run (needs a connected, signed device)"
        task all: [:lib, "ios:#{name}:gen", :build, :run]
      end
    end
  end
end

IOS_EXAMPLES = [
  { name: "stackchan", label: "Stack-chan",         dir: "stackchan",
    scheme: "Stackchan",         lib_phrase: "WITH picoruby-ble + Darwin port" },
  { name: "vperiph",   label: "Virtual Peripheral", dir: "virtual-peripheral",
    scheme: "VirtualPeripheral", lib_phrase: "WITH picoruby-ble + Darwin port" },
  { name: "torch",     label: "Torch",              dir: "iphone-torch",
    scheme: "Torch",             lib_phrase: "WITH picoruby-iphone-torch" },
  { name: "tiltsynth", label: "TiltSynth",          dir: "tilt-synth",
    scheme: "TiltSynth",         lib_phrase: "WITH the tilt-synth gems" },
  { name: "net",       label: "Networking",         dir: "networking",
    scheme: "Networking",        lib_phrase: "WITH picoruby-net (mbedTLS)",
    device_lib_phrase: "WITH picoruby-net" },
]

IOS_EXAMPLES.each { |example| define_ios_example(**example) }

# The base ios: namespace builds the EXAMPLE-env-selected app (default: repl)
# with the PicoRubyRunner project/scheme/bundle shared by those examples.
namespace :ios do
  desc "Cross-build libmruby.a for the iOS Simulator and stage under app/Vendor"
  task lib: :setup do
    # Full REPL (posix?=true + darwin port-chain): the complete core/stdlib/shell
    # gembox set. BLE-free, so the REPL example stays self-contained.
    stage_libmruby("r2p2-picoruby-ios-repl-sim.rb", "ios-repl-sim", VENDOR_DIR)
  end

  desc "Generate the Xcode project from project.yml"
  task :gen do
    sh "cd #{APP_DIR.shellescape} && xcodegen generate"
  end

  desc "Build the app for the iOS Simulator"
  task :build do
    sim_build(File.join(APP_DIR, "PicoRubyRunner.xcodeproj"), "PicoRubyRunner",
              File.join(ROOT, "build", "ios-app"))
  end

  desc "Boot a simulator, install, and launch the app"
  task :run do
    app = built_app(File.join(ROOT, "build", "ios-app"), "*-iphonesimulator",
                    "PicoRubyRunner", "ios:build")
    sim_install_launch("iPhone", app, BUNDLE_ID)
  end

  desc "Full headless pipeline: lib -> gen -> build -> run"
  task all: [:lib, :gen, :build, :run]

  namespace :device do
    desc "Cross-build libmruby.a for an iOS device (iphoneos arm64) and stage under app/Vendor"
    task lib: :setup do
      stage_libmruby("r2p2-picoruby-ios-repl-device.rb", "ios-repl-device", VENDOR_DIR)
    end

    desc "Build the app, signed, for the connected iOS device"
    task :build do
      device_build(File.join(APP_DIR, "PicoRubyRunner.xcodeproj"), "PicoRubyRunner",
                   File.join(ROOT, "build", "ios-app-device"), archs: "arm64")
    end

    desc "Install and launch the app on the connected iOS device"
    task :run do
      app = built_app(File.join(ROOT, "build", "ios-app-device"), "*-iphoneos",
                      "PicoRubyRunner", "ios:device:build")
      device_install_launch(/iPhone|iPad/, "iOS device", app, BUNDLE_ID)
    end

    desc "Full device pipeline: lib -> gen -> build -> run (needs a connected, signed device)"
    task all: [:lib, "ios:gen", :build, :run]
  end

  namespace :vperiph do
    desc "Build+run the macOS BLE central helper (scan PBLE-TEST, connect, write WRITE_HEX, read/subscribe) to exercise the peripheral from the Mac"
    task :write do
      src = File.join(ROOT, "examples", "ios", "virtual-peripheral", "tools", "ble_write.swift")
      bin = File.join(ROOT, "build", "ble_write")
      sh "swiftc -O #{src.shellescape} -o #{bin.shellescape}"
      # WRITE_HEX / TARGET_NAME / APP_SERVICES pass through the environment.
      sh bin.shellescape
    end
  end
end

namespace :watchos do
  namespace :led do
    watch_dir            = File.join(ROOT, "examples", "watchos", "led-toggle")
    watch_proj           = File.join(watch_dir, "WatchLEDToggle.xcodeproj")
    watch_bundle         = "com.bash0c7.picoruby.WatchLEDToggle"
    watch_vendor         = File.join(watch_dir, "Vendor")
    watch_derived        = File.join(ROOT, "build", "watchos-app")
    watch_device_derived = File.join(ROOT, "build", "watchos-app-device")

    desc "Cross-build libmruby.a for watchOS Simulator and stage under examples/watchos/led-toggle/Vendor"
    task lib: :setup do
      stage_libmruby("r2p2-picoruby-watchos-sim.rb", "watchos-sim", watch_vendor)
    end

    desc "Generate the Watch LED Toggle Xcode project from project.yml"
    task :gen do
      sh "cd #{watch_dir.shellescape} && xcodegen generate"
    end

    desc "Build the Watch LED Toggle app for the watchOS Simulator"
    task :build do
      sim_build(watch_proj, "WatchLEDToggle", watch_derived,
                platform: "watchOS Simulator", exclude_x86_64: false)
    end

    desc "Boot a watchOS simulator, install, and launch the Watch LED Toggle app"
    task :run do
      app = built_app(watch_derived, "*-watchsimulator", "WatchLEDToggle", "watchos:led:build")
      sim_install_launch("Apple Watch", app, watch_bundle)
    end

    desc "Full Watch pipeline: lib -> gen -> build -> run"
    task all: [:lib, :gen, :build, :run]

    namespace :device do
      desc "Cross-build libmruby.a for watchOS device (arm64_32) and stage under examples/watchos/led-toggle/Vendor"
      task lib: :setup do
        stage_libmruby("r2p2-picoruby-watchos-device.rb", "watchos-device", watch_vendor)
        # stage_libmruby copies the fat/arm64 archive mruby just built; the
        # physical watch needs arm64_32. Recompile in place and re-stage so
        # Vendor/lib never ends up with an arch the device can't run.
        sh "ruby #{File.join(ROOT, "build_config", "recompile_arm64_32.rb").shellescape}"
        lib = File.join(BUILD_DIR, "watchos-device", "lib", "libmruby.a")
        cp lib, File.join(watch_vendor, "lib", "libmruby.a")
        puts "Re-staged arm64_32 libmruby.a under #{watch_vendor}"
      end

      desc "Build the Watch LED Toggle app, signed, for the connected Apple Watch"
      task :build do
        device_build(watch_proj, "WatchLEDToggle", watch_device_derived,
                     archs: "arm64_32", platform: "watchOS")
      end

      desc "Install and launch the Watch LED Toggle app on the connected Apple Watch"
      task :run do
        app = built_app(watch_device_derived, "*-watchos", "WatchLEDToggle", "watchos:led:device:build")
        device_install_launch(/Watch/, "Apple Watch", app, watch_bundle)
      end

      desc "Full Watch device pipeline: lib -> gen -> build -> run (needs a connected, signed Apple Watch)"
      task all: [:lib, "watchos:led:gen", :build, :run]
    end
  end
end

desc "Build and launch the PicoRuby iOS Runner on the Simulator"
task ios: "ios:all"

namespace :host do
  desc "Host build of picoruby (for the bridge smoke test)"
  task lib: :setup do
    cfg = File.join(ROOT, "build_config", "r2p2-picoruby-host.rb")
    sh mruby_env(cfg), "cd #{PICORUBY_SRC.shellescape} && rake"
  end
end

desc "Compile + run the bridge smoke test on the host"
task smoke: "host:lib" do
  lib    = File.join(BUILD_DIR, "host", "lib", "libmruby.a")
  out    = "/tmp/picoruby_smoke"

  # Defines must match the host build config (r2p2-picoruby-host.rb) so the
  # bridge sees the same ABI (no-boxing, int64, estalloc, task scheduler).
  defines = %w[
    PICORB_ALLOC_ESTALLOC PICORB_ALLOC_ALIGN=8
    MRB_NO_BOXING MRB_INT64 MRB_UTF8_STRING
    PICORB_PLATFORM_DARWIN
    MRB_TICK_UNIT=4 MRB_TIMESLICE_TICK_COUNT=3
    MRB_USE_TASK_SCHEDULER=1 MRB_USE_VM_SWITCH_DISPATCH=1
  ].map { |d| "-D#{d}" }.join(" ")

  # picoruby.h uses angle-bracket includes for mrc_common.h (mruby-compiler),
  # mruby.h (picoruby-mruby/lib/mruby), and prism.h (mruby-compiler/lib/prism).
  # build/host/include supplies the generated presym/id.h.
  # task.h is in mruby-task/include.
  includes = [
    File.join(PICORUBY_SRC, "include"),
    File.join(PICORUBY_SRC, "mrbgems", "mruby-compiler", "include"),
    File.join(PICORUBY_SRC, "mrbgems", "mruby-compiler", "lib", "prism", "include"),
    File.join(PICORUBY_SRC, "mrbgems", "picoruby-mruby", "lib", "mruby", "include"),
    File.join(PICORUBY_SRC, "mrbgems", "picoruby-mruby", "include"),
    File.join(BUILD_DIR, "host", "include"),
    File.join(PICORUBY_SRC, "mrbgems", "picoruby-mruby", "lib", "mruby",
              "mrbgems", "mruby-task", "include"),
    File.join(ROOT, "bridge"),
  ].map { |p| "-I #{p.shellescape}" }.join(" ")

  sh "clang #{defines} #{includes} " \
     "#{File.join(ROOT, "bridge", "smoke_test.c").shellescape} " \
     "#{File.join(ROOT, "bridge", "picoruby_bridge.c").shellescape} " \
     "#{lib.shellescape} -o #{out.shellescape}"
  sh out
end

desc "Remove build output (keeps vendor/picoruby)"
task :clean do
  rm_rf BUILD_DIR
  rm_rf VENDOR_DIR
end

desc "Remove build output and vendor/picoruby"
task clobber: :clean do
  rm_rf PICORUBY_SRC
end
