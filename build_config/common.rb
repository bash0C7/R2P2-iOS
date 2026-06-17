# Base VM defines shared by every R2P2-macOS runtime. Each build_config loads
# this file and calls base_defines. Keep ONLY premises common to all runtimes
# here; config-specific capability boundaries (gembox selection, MRB_NO_* gates,
# security boundaries) stay in the caller.
module R2P2MacOSBuild
  def self.base_defines(conf)
    conf.cc.defines << "MRB_TICK_UNIT=4"
    conf.cc.defines << "MRB_TIMESLICE_TICK_COUNT=3"
    conf.cc.defines << "PICORB_ALLOC_ALIGN=8"
    conf.cc.defines << "PICORB_ALLOC_ESTALLOC"
    conf.cc.defines << "PICORB_PLATFORM_POSIX"
    conf.cc.defines << "MRB_INT64"
    conf.cc.defines << "MRB_NO_BOXING"
    conf.cc.defines << "MRB_UTF8_STRING"
  end
end
