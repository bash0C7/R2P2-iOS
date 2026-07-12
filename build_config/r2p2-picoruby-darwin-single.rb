# Darwin host build for a single-binary picoruby app: the app's Ruby is
# embedded as mrblib. Used by `rake macos:single`, which passes the app gem
# path in via the R2P2_SINGLE_GEM_PATH env var.
#
# Omits the REPL bin (picoruby-bin-picoruby) and the R2P2 shell bin
# (picoruby-bin-r2p2), and pulls in only the gemboxes most apps need
# (mruby-posix + core + stdlib). If your app needs networking / shell /
# fonts, copy this file and add the gemboxes you want.

MRuby::Build.new do |conf|
  conf.toolchain :gcc

  conf.cc.defines << "MRB_TICK_UNIT=4"
  conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
  conf.cc.defines << "PICORB_ALLOC_ALIGN=8"
  conf.cc.defines << "PICORB_ALLOC_ESTALLOC"
  conf.cc.defines << "PICORB_PLATFORM_POSIX"
  conf.cc.defines << "PICORB_PLATFORM_DARWIN"
  conf.cc.defines << "MRB_INT64"
  conf.cc.defines << "MRB_NO_BOXING"
  conf.cc.defines << "MRB_UTF8_STRING"

  conf.picoruby

  # The `minimum` gembox minus picoruby-bin-picoruby (the REPL):
  # compiler / mrbc / VM only.
  conf.gem core: "mruby-compiler"
  conf.gem core: "mruby-bin-mrbc"
  conf.gem core: "picoruby-mruby"

  conf.gembox "mruby-posix"
  conf.gembox "core"
  conf.gembox "stdlib"

  bin_gem = ENV["R2P2_SINGLE_GEM_PATH"]
  raise "R2P2_SINGLE_GEM_PATH not set (run via `rake macos:single`, not directly)" if bin_gem.nil? || bin_gem.empty?
  conf.gem bin_gem
end
