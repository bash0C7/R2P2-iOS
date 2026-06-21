# Stack-chan controller — the bundled, fixed Ruby that the persistent PicoRuby
# VM runs on iOS. This is NOT user-editable and is not downloaded: PicoRuby is
# simply the implementation language for the app's own behavior (Guideline
# 2.5.2-free).
#
# The frame encoders are inlined from the PC CLI's verified codec
# (stackchan-picoruby/pc/stackchan/lib/stackchan/ble/{frame_codec,face_table,
# led_color_table}.rb). Two adaptations for the reduced iOS VM and the
# Swift->VM call seam:
#   1. No require_relative / module namespacing — the bundled app is one source.
#   2. String keys (not Symbols) because vm_call delivers a single String arg
#      from the Swift UI. The emitted frames are byte-identical to the PC codec.
#
# The wire frame format and the left/right reversal are load-bearing and were
# verified on real hardware; do not "fix" SIDE_TO_CHAR.

module FrameCodec
  # API "left"/"right" are StackChan's own perspective (its hands); the firmware
  # wires them reversed, so "left" -> "R" and "right" -> "L" on the wire.
  SIDE_TO_CHAR = { "left" => "R", "right" => "L", "both" => "B" }
  MODE_TO_CHAR = { "solid" => "s", "blink" => "b", "breathing" => "p", "off" => "o" }
  FACE_INDICES = {
    "neutral" => "0", "smile" => "1", "joy" => "2",
    "surprised" => "3", "sad" => "4", "angry" => "5",
  }
  LED_COLORS = {
    "red" => [255, 0, 0], "green" => [0, 255, 0], "blue" => [0, 0, 255],
    "yellow" => [255, 255, 0], "cyan" => [0, 255, 255], "magenta" => [255, 0, 255],
    "white" => [255, 255, 255], "off" => [0, 0, 0],
  }

  ACK_OK    = "."
  ACK_ERROR = "?"
  TOUCH_PREFIX = "<touch:"

  def self.encode_pairs(pairs)
    "<" + pairs.map { |k, v| "#{k}:#{v}" }.join(",") + ">\n"
  end

  def self.encode_face(name)
    index = FACE_INDICES[name]
    raise ArgumentError, "unknown face: #{name}" unless index
    encode_pairs({ "F" => index })
  end

  # color: a named color string ("red"...). side: "left"/"right"/"both".
  # mode: "solid"/"blink"/"breathing"/"off".
  def self.encode_led(color:, side:, mode:)
    rgb = LED_COLORS[color]
    raise ArgumentError, "unknown color: #{color}" unless rgb
    side_char = SIDE_TO_CHAR[side]
    raise ArgumentError, "unknown side: #{side}" unless side_char
    mode_char = MODE_TO_CHAR[mode]
    raise ArgumentError, "unknown mode: #{mode}" unless mode_char
    encode_pairs({
      "L" => "1", "R" => rgb[0].to_s, "G" => rgb[1].to_s, "B" => rgb[2].to_s,
      "S" => side_char, "M" => mode_char,
    })
  end

  # Exactly one of yaw_left/yaw_right may be set (0..100); pitch_up optional
  # (0..100); time_ms optional. nil means "omit".
  def self.encode_head(yaw_left: nil, yaw_right: nil, pitch_up: nil, time_ms: nil)
    if !yaw_left.nil? && !yaw_right.nil?
      raise ArgumentError, "yaw_left and yaw_right are mutually exclusive"
    end
    if yaw_left.nil? && yaw_right.nil? && pitch_up.nil?
      raise ArgumentError, "encode_head needs one of yaw_left/yaw_right/pitch_up"
    end
    pairs = {}
    pairs["YL"] = yaw_left.to_s  unless yaw_left.nil?
    pairs["YR"] = yaw_right.to_s unless yaw_right.nil?
    pairs["PU"] = pitch_up.to_s  unless pitch_up.nil?
    pairs["T"]  = time_ms.to_s   if time_ms
    encode_pairs(pairs)
  end

  def self.encode_torque(on)
    encode_pairs({ "torque" => (on ? "on" : "off") })
  end

  # frame[0,1] is safe on a bare 1-char ACK byte too.
  def self.parse_ack(frame)
    case frame[0, 1]
    when ACK_OK    then :ok
    when ACK_ERROR then :error
    else raise ArgumentError, "unknown ack frame: #{frame}"
    end
  end

  # Reduced VM has no Regexp; parse "<touch:N>" by hand. Returns the zone Integer
  # or nil if the frame is not a touch event.
  def self.parse_touch(frame)
    return nil unless frame[0, TOUCH_PREFIX.length] == TOUCH_PREFIX
    rest = frame[TOUCH_PREFIX.length, frame.length]
    digits = ""
    i = 0
    while i < rest.length
      c = rest[i, 1]
      break unless c >= "0" && c <= "9"
      digits += c
      i += 1
    end
    return nil if digits.empty?
    digits.to_i
  end
end

# The BLE transport seam. Phase 3 wires this to picoruby-ble: write(frame) will
# write the ASCII frame to the Nordic UART RX characteristic (6e400002) of the
# connected Stack-chan. Until then it records frames so the host frame tests and
# the persistent-VM path are exercisable without a radio.
class BleLink
  attr_reader :sent

  def initialize
    @sent = []
  end

  def write(frame)
    @sent << frame
    # Echo so vm_call's stdout capture surfaces the frame during bring-up.
    print frame
    :ok
  end
end

# The dispatcher object the persistent-VM bridge calls. vm_call(method, arg)
# invokes one of these with a single String arg from the Swift UI.
class Stackchan
  attr_reader :ble

  def initialize(ble = BleLink.new)
    @ble = ble
  end

  # arg: a face name, e.g. "joy".
  def face(arg)
    @ble.write(FrameCodec.encode_face(arg))
  end

  # arg: "color" or "color:mode" or "color:mode:side"
  # (defaults mode=solid, side=both), e.g. "red", "red:blink", "green:solid:left".
  def led(arg)
    parts = arg.split(":")
    color = parts[0]
    mode  = parts[1] || "solid"
    side  = parts[2] || "both"
    @ble.write(FrameCodec.encode_led(color: color, side: side, mode: mode))
  end

  # arg: "dir:magnitude" or "dir:magnitude:time_ms"; dir is "left"/"right"/"up",
  # magnitude 0..100, e.g. "left:50:500".
  def head(arg)
    parts = arg.split(":")
    dir = parts[0]
    mag = parts[1] ? parts[1].to_i : 0
    t   = parts[2] ? parts[2].to_i : nil
    case dir
    when "left"  then @ble.write(FrameCodec.encode_head(yaw_left: mag, time_ms: t))
    when "right" then @ble.write(FrameCodec.encode_head(yaw_right: mag, time_ms: t))
    when "up"    then @ble.write(FrameCodec.encode_head(pitch_up: mag, time_ms: t))
    else raise ArgumentError, "unknown head dir: #{dir}"
    end
  end

  # arg: "on" / "off".
  def torque(arg)
    @ble.write(FrameCodec.encode_torque(arg == "on"))
  end
end

$app = Stackchan.new
