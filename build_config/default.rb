# Standard PicoRuby / R2P2 host (POSIX) build for R2P2-macOS.
# Don't invoke directly — use `rake build`, which fetches upstream
# picoruby/picoruby (rake setup), pins the macOS environment (rbenv Ruby 4.0.5,
# Homebrew openssl@3 flags) and sets MRUBY_BUILD_DIR so all output lands under
# R2P2-macOS/build while the fetched picoruby source stays pristine.
load File.expand_path("common.rb", __dir__)

MRuby::Build.new do |conf|
  conf.toolchain :gcc

  R2P2MacOSBuild.base_defines(conf)

  conf.picoruby

  # networking gembox links ssl/crypto (Homebrew openssl@3 via the Rakefile flags).
  conf.linker.libraries << "ssl"
  conf.linker.libraries << "crypto"

  conf.gembox "mruby-posix"
  conf.gembox "minimum"
  conf.gembox "core"
  conf.gembox "stdlib"
  conf.gembox "shell"
  conf.gembox "networking"
  conf.gem core: "picoruby-shinonome"
  conf.gem core: "picoruby-bin-r2p2"        # the `r2p2` shell binary
  conf.gem core: "picoruby-bin-picoruby"    # the `picoruby <file.rb>` runner
end
