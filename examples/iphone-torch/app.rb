# iPhone Torch — the whole behaviour is Ruby. The `Torch` class comes from the
# linked picoruby-iphone-torch gem; its on/off/available? drive AVCaptureDevice
# through the gem's Darwin port. This app owns the dispatch the Swift buttons call.
#
# vm_call(vm, "on"/"off", "") invokes $app.on / $app.off and returns whatever this
# prints (captured stdout), which the UI appends to its log. No timer: torch is a
# fire-and-forget on/off, so there is no poll loop.
class TorchApp
  def initialize
    @torch = Torch.new
    @log = []
    if @torch.available?
      log "ready: torch available"
    else
      log "ready: no torch on this device (Simulator?) — on/off will be no-ops"
    end
  end

  def on(arg = nil)
    if @torch.on
      log "torch ON"
    else
      log "torch unavailable (no actuation)"
    end
    flush_log
  end

  def off(arg = nil)
    if @torch.off
      log "torch OFF"
    else
      log "torch unavailable (no actuation)"
    end
    flush_log
  end

  private

  def log(msg)
    @log.push(msg)
  end

  def flush_log
    return nil if @log.empty?
    out = @log.join("\n")
    @log = []
    print out
    nil
  end
end

$app = TorchApp.new
