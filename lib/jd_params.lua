-- Every setting as a norns param, so PSETs save and load them all. Each action calls into
-- the deps; init() ends with params:bang(), so the defaults reach every output.
-- `p` is the paramset (norns' `params`). deps = { player, midi_out, jf_out, wsyn_out,
-- tablet, ports = fn() -> names, midi_connect = fn(port) -> device (default: midi.connect) }.
-- Lua 5.3 compatible. Uses the norns globals `controlspec` and `engine` and (by default) `midi`.
local Params = {}

local ROOTS = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local OUTPUTS = {
  { "engine", "engine", 1 }, { "midi", "MIDI", 0 }, { "crow", "crow", 0 },
  { "jf", "Just Friends", 0 }, { "wsyn", "w/syn", 0 },
}

function Params.add(p, deps)
  local player = deps.player
  local midi_out, jf_out, wsyn_out, tablet = deps.midi_out, deps.jf_out, deps.wsyn_out, deps.tablet
  local connect = deps.midi_connect or function(port) return midi.connect(port) end

  local function on(id) return p:get(id) == 1 end

  p:add_separator("jd_play", "just draw")

  local function knob(id, name, min, max, warp, default, units)
    p:add_control(id, name, controlspec.new(min, max, warp, 0, default, units))
    p:set_action(id, function(v) player:set(id, v) end)
  end
  knob("noise", "noise", 0, 24, "lin", 2, "")
  knob("ratio", "ratio", 0.5, 2, "exp", 0.7, "")
  knob("release", "release", 0.05, 3, "exp", 0.5, "s")

  p:add_option("root", "root", ROOTS, 1)
  p:set_action("root", function(i) player:set("root", i - 1) end)

  p:add_number("octave", "octave", 1, 6, 3)
  p:set_action("octave", function(v) player:set("octave", v) end)
  -- The player changes the octave from the pen buttons: mirror it into the param silently,
  -- so the action does not call back into the player.
  player.on_octave = function(n) p:set("octave", n, true) end

  p:add_binary("flip", "flip 180", "toggle", 0)
  p:set_action("flip", function(v) tablet:set_flip(v == 1) end)

  p:add_option("tablet", "tablet", { "auto", "port 1", "port 2", "port 3", "port 4" }, 1)
  p:set_action("tablet", function(i) tablet:select(i > 1 and i - 1 or nil) end)

  p:add_separator("jd_outputs", "outputs")
  for _, o in ipairs(OUTPUTS) do
    local name, label, default = o[1], o[2], o[3]
    p:add_binary("out_" .. name, label, "toggle", default)
    p:set_action("out_" .. name, function(v) player:switch(name, v == 1) end)
  end

  p:add_separator("jd_midi", "MIDI")
  p:add_number("midi_device", "device", 1, 16, 1, "", function(param)
    local n = param:get()
    return (deps.ports and deps.ports()[n]) or ("port " .. n)
  end)
  p:set_action("midi_device", function(n) midi_out.set_device(connect(n)) end)

  local function configure_midi()
    midi_out.configure(p:get("midi_channel"), p:get("midi_bend"), p:get("midi_cc"))
  end
  p:add_number("midi_channel", "channel", 1, 16, 1)
  p:add_number("midi_bend", "bend range", 1, 48, 24)
  p:add_number("midi_cc", "x CC", 0, 119, 74)
  for _, id in ipairs({ "midi_channel", "midi_bend", "midi_cc" }) do
    p:set_action(id, configure_midi)
  end
  p:add_trigger("midi_send_cc", "send CC (for MIDI learn)")
  p:set_action("midi_send_cc", function() midi_out.send_cc() end)

  p:add_separator("jd_ii", "crow ii")
  -- A module's setting is stored at once and sent only while its output is on; the output
  -- sends everything itself when it is switched on.
  local function ii_setting(out_id, out, apply)
    return function(v)
      apply(out.settings, v)
      if on(out_id) then out.apply_settings() end
    end
  end

  p:add_option("jf_mode", "JF mode", { "normal", "synthesis" }, 2)
  p:set_action("jf_mode", ii_setting("out_jf", jf_out,
    function(s, i) s.mode = i - 1 end))

  p:add_number("wsyn_voices", "w/syn voices", 0, 4, 4)
  p:set_action("wsyn_voices", ii_setting("out_wsyn", wsyn_out,
    function(s, v) s.voices = v end))
  p:add_control("wsyn_lpg_time", "w/syn LPG time", controlspec.new(-5, 5, "lin", 0, 0, "V"))
  p:set_action("wsyn_lpg_time", ii_setting("out_wsyn", wsyn_out,
    function(s, v) s.lpg_time = v end))
  p:add_control("wsyn_lpg_symmetry", "w/syn LPG symmetry", controlspec.new(-5, 5, "lin", 0, 0, "V"))
  p:set_action("wsyn_lpg_symmetry", ii_setting("out_wsyn", wsyn_out,
    function(s, v) s.lpg_symmetry = v end))
  p:add_option("wsyn_hold", "w/syn envelope", { "hold", "pluck" }, 1)
  p:set_action("wsyn_hold", ii_setting("out_wsyn", wsyn_out,
    function(s, i) s.hold = (i == 1) end))

  -- Reverb and delay live in the engine, after the voice. Each action sends its value to the
  -- engine command of the same name; params:bang() then brings the engine in line.
  p:add_group("effects", "effects", 10)
  local function fx(id, name, min, max, warp, default, units, command)
    p:add_control(id, name, controlspec.new(min, max, warp, 0, default, units))
    p:set_action(id, function(v) engine[command](v) end)
  end
  fx("reverb_send", "reverb send", 0, 1, "lin", 0, "", "set_reverb_send")
  fx("delay_send", "delay send", 0, 1, "lin", 0, "", "set_delay_send")
  fx("delay_time", "delay time", 0.01, 8, "lin", 0.3, "s", "set_delay_time")
  fx("delay_decay", "delay decay", 0.01, 60, "exp", 0.5, "s", "set_delay_decay")
  fx("delay_level", "delay level", 0, 2, "lin", 1, "", "set_delay_level")
  fx("delay_to_reverb", "delay to reverb", 0, 1, "lin", 1, "", "set_delay_to_reverb")
  fx("delay_to_dry", "delay to dry", 0, 1, "lin", 0, "", "set_delay_to_dry")
  fx("reverb_room", "reverb room", 0, 1, "lin", 0.5, "", "set_reverb_room")
  fx("reverb_damp", "reverb damp", 0, 1, "lin", 0.5, "", "set_reverb_damp")
  fx("reverb_level", "reverb level", 0, 2, "lin", 1, "", "set_reverb_level")
end

return Params
