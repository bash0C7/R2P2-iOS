# R2P2-macOS — host-side build harness for picoruby on Darwin.
#
# Fetches a picoruby tree from GitHub into vendor/picoruby and builds it on a
# macOS host. Build output is redirected into ./build via MRUBY_BUILD_DIR so
# the fetched source stays pristine.
#
#   PICORUBY_REPO  default https://github.com/picoruby/picoruby.git
#   PICORUBY_REF   default master
#   MRUBY_CONFIG   default build_config/r2p2-picoruby-darwin.rb (Darwin host
#                  base). Override to point at the BLE variant or another
#                  bundled config.
#
# Why this repo: picoruby/picoruby ships per-target build_config files
# (r2p2-picoruby-pico2.rb etc.) but as of 2026-06-20 has no equivalent for a
# Darwin host. Until that lands upstream, R2P2-macOS stores the Darwin host
# build config and pins the per-host prerequisites (Xcode CLT, brew openssl@3,
# Swift toolchain) via `rake check`.

require "shellwords"

R2P2_MACOS_ROOT = __dir__
PICORUBY_REPO   = ENV["PICORUBY_REPO"] || "https://github.com/picoruby/picoruby.git"
PICORUBY_REF    = ENV["PICORUBY_REF"]  || "master"
PICORUBY_SRC    = File.join(R2P2_MACOS_ROOT, "vendor", "picoruby")
BUILD_DIR       = File.join(R2P2_MACOS_ROOT, "build")

# Brew openssl@3 prefix on LDFLAGS/CFLAGS so the networking gembox can find
# ssl/crypto. macOS-specific: brew installs into /opt/homebrew which is not
# on the default ld search path. Inert if openssl@3 isn't brew-installed.
def build_env
  env = { "MRUBY_BUILD_DIR" => BUILD_DIR }
  ssl = `brew --prefix openssl@3 2>/dev/null`.strip
  unless ssl.empty?
    env["LDFLAGS"] = [ENV["LDFLAGS"], "-L#{ssl}/lib"].compact.join(" ")
    env["CFLAGS"]  = [ENV["CFLAGS"],  "-I#{ssl}/include"].compact.join(" ")
  end
  cfg = ENV["MRUBY_CONFIG"] || File.join(R2P2_MACOS_ROOT, "build_config", "r2p2-picoruby-darwin.rb")
  env["MRUBY_CONFIG"] = File.absolute_path(cfg)
  env
end

desc "Verify macOS prerequisites (Xcode CLT, brew openssl@3, Swift)"
task :check do
  ok = true
  if system("xcode-select", "-p", out: File::NULL, err: File::NULL)
    puts "Xcode CLT:  ok"
  else
    warn "Xcode CLT:  missing — run `xcode-select --install`"
    ok = false
  end

  ssl = `brew --prefix openssl@3 2>/dev/null`.strip
  if ssl.empty?
    warn "openssl@3:  missing — run `brew install openssl@3` (networking gem links ssl/crypto)"
    ok = false
  else
    puts "openssl@3:  #{ssl}"
  end

  swift = `swift --version 2>/dev/null`.lines.first&.strip
  if swift.nil? || swift.empty?
    warn "Swift:      missing — install Xcode (needed for the picoruby-ble Darwin port)"
  else
    puts "Swift:      #{swift}"
  end

  abort "missing prerequisites" unless ok
end

desc "Fetch picoruby from PICORUBY_REPO at PICORUBY_REF into vendor/picoruby"
task :setup do
  unless Dir.exist?(PICORUBY_SRC)
    sh "git clone --recursive --branch #{PICORUBY_REF.shellescape} " \
       "#{PICORUBY_REPO.shellescape} #{PICORUBY_SRC.shellescape}"
  end
end

desc "Re-fetch PICORUBY_REF into the existing vendor/picoruby (no re-clone)"
task :refresh do
  raise "vendor/picoruby absent; run `rake setup` first" unless Dir.exist?(PICORUBY_SRC)
  sh "git -C #{PICORUBY_SRC.shellescape} fetch #{PICORUBY_REPO.shellescape} #{PICORUBY_REF.shellescape}"
  sh "git -C #{PICORUBY_SRC.shellescape} checkout -B #{PICORUBY_REF.shellescape} FETCH_HEAD"
  sh "git -C #{PICORUBY_SRC.shellescape} submodule update --init --recursive"
end

desc "Build the fetched picoruby tree into ./build"
task build: :setup do
  sh build_env, "cd #{PICORUBY_SRC.shellescape} && rake"
end

desc "Run the r2p2 shell, or APP=path/to.rb on the picoruby runner"
task :run do
  r2p2 = File.join(BUILD_DIR, "host", "bin", "r2p2")
  pr   = File.join(BUILD_DIR, "host", "bin", "picoruby")
  if (app = ENV["APP"])
    raise "Not built. Run `rake build` first." unless File.executable?(pr)
    exec({}, pr, app)
  elsif File.executable?(r2p2)
    exec({}, r2p2)
  else
    raise "Not built (or this build has no r2p2 shell — try APP=path/to.rb)."
  end
end

desc "Remove build output (keeps vendor/picoruby)"
task :clean do
  rm_rf BUILD_DIR
end

desc "Remove build output and vendor/picoruby"
task clobber: :clean do
  rm_rf PICORUBY_SRC
end

task default: :build
