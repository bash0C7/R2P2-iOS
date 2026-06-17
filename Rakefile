# R2P2-macOS — environment to build & run standard PicoRuby / R2P2 on macOS host.
#
# Mechanism: fetch upstream picoruby/picoruby from GitHub (NO submodule, NO
# sibling fork) into vendor/picoruby via `rake setup`, then build it with our
# MRUBY_CONFIG, redirecting ALL output into ./build via MRUBY_BUILD_DIR so the
# fetched picoruby source stays pristine.
#
# The macOS environment that the upstream build requires and is easy to get wrong:
#   - rbenv Ruby 4.0.5 (upstream build.rb uses `_1`, needs >= 2.7; macOS system
#     Ruby 2.6 fails; upstream has no .ruby-version, so we pin it)
#   - Homebrew openssl@3 -L/-I flags (the networking gembox links ssl/crypto)
#
# Usage:
#   rake setup    # clone upstream picoruby/picoruby into vendor/picoruby (PICORUBY_REF, default master)
#   rake          # == rake build
#   rake build    # build standard r2p2 + picoruby into ./build/host (incremental/idempotent)
#   rake run      # run the r2p2 shell (or APP=path/to.rb on the picoruby runner)
#   rake clean    # remove ./build
#   rake clobber  # remove ./build and the fetched vendor/picoruby

require "shellwords"

R2P2_MACOS_ROOT = __dir__
PICORUBY_REPO   = "https://github.com/picoruby/picoruby.git"
PICORUBY_REF    = ENV["PICORUBY_REF"] || "master"
PICORUBY_SRC    = File.join(R2P2_MACOS_ROOT, "vendor", "picoruby")
BUILD_DIR       = File.join(R2P2_MACOS_ROOT, "build")
HOST_BIN_R2P2   = File.join(BUILD_DIR, "host", "bin", "r2p2")
HOST_BIN_PR     = File.join(BUILD_DIR, "host", "bin", "picoruby")
BUILD_RUBY      = "4.0.5"
DEFAULT_CONFIG  = File.join(R2P2_MACOS_ROOT, "build_config", "default.rb")

def openssl_prefix
  prefix = `brew --prefix openssl@3 2>/dev/null`.strip
  raise "openssl@3 not found. Run: brew install openssl@3" if prefix.empty?
  prefix
end

# Pin rbenv Ruby 4.0.5 regardless of any ambient version.
def build_env
  {
    "PATH"          => "#{Dir.home}/.rbenv/shims:#{ENV['PATH']}",
    "RBENV_VERSION" => BUILD_RUBY,
  }
end

desc "Fetch upstream picoruby/picoruby from GitHub into vendor/picoruby (PICORUBY_REF, default master)"
task :setup do
  unless Dir.exist?(PICORUBY_SRC)
    sh "git clone --recursive --branch #{PICORUBY_REF.shellescape} " \
       "#{PICORUBY_REPO} #{PICORUBY_SRC.shellescape}"
  end
  # No `bundle install`: the host build uses bare `rake`; its deps (prism etc.)
  # are git submodules pulled by --recursive, and rake is a default gem.
end

# Build via upstream's DEFAULT rake task so it honors our MRUBY_CONFIG.
# NB: do NOT use `picoruby:prod` — that task hardcodes MRUBY_CONFIG=default and
# would ignore our config. MRUBY_BUILD_DIR redirects all output out of the source.
desc "Build standard r2p2 + picoruby host runtime into ./build"
task build: :setup do
  ssl = openssl_prefix
  cmd = "cd #{PICORUBY_SRC.shellescape} && " \
        "rake LDFLAGS=-L#{ssl}/lib CFLAGS=-I#{ssl}/include"
  sh build_env.merge("MRUBY_CONFIG" => DEFAULT_CONFIG, "MRUBY_BUILD_DIR" => BUILD_DIR), cmd
  [HOST_BIN_R2P2, HOST_BIN_PR].each do |bin|
    raise "build finished but #{bin} is missing" unless File.executable?(bin)
  end
  puts "Built: #{HOST_BIN_R2P2}"
  puts "Built: #{HOST_BIN_PR}"
end

desc "Run the r2p2 shell, or a Ruby app on the picoruby runner (APP=path/to.rb)"
task :run do
  if (app = ENV["APP"])
    raise "Not built. Run `rake build` first." unless File.executable?(HOST_BIN_PR)
    exec({}, HOST_BIN_PR, app)
  else
    raise "Not built. Run `rake build` first." unless File.executable?(HOST_BIN_R2P2)
    exec({}, HOST_BIN_R2P2)
  end
end

desc "Remove ./build (keeps fetched vendor/picoruby)"
task :clean do
  rm_rf BUILD_DIR
end

desc "Remove ./build and the fetched vendor/picoruby"
task clobber: :clean do
  rm_rf PICORUBY_SRC
end

task default: :build
