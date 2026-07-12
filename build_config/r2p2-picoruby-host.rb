# Host build used only to link the bridge smoke test (`rake smoke`). Its gem
# set is the shared core every iOS cross-build starts from (picoruby VM +
# mruby-compiler; each iOS config adds its own gems on top), so the smoke
# test, which links against THIS build, predicts what that shared core can
# run. Toolchain is host-appropriate (plain MRuby::Build, no -arch/-isysroot).
# PICORB_PLATFORM_POSIX is omitted to match the bare-VM iOS configs (the host
# builds clean without it).
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

  conf.gem core: "mruby-compiler"
end
