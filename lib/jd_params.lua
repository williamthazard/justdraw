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

-- Delay sync: option 1 is free; the rest are beat counts (schicksalslied 2's list).
local SYNC_OPTIONS = { "free", "1/16", "1/12", "1/8", "1/6", "3/16", "1/4", "1/3", "3/8", "1/2",
  "2/3", "3/4", "1", "4/3", "3/2", "2", "8/3", "3", "4", "5", "6", "7", "8" }
local SYNC_BEATS = { 1/16, 1/12, 1/8, 1/6, 3/16, 1/4, 1/3, 3/8, 1/2, 2/3, 3/4, 1, 4/3, 3/2, 2,
  8/3, 3, 4, 5, 6, 7, 8 }
local MAX_DELAY = 8

-- The delay time in seconds: the delay_time param while free, else the beats at beat_sec,
-- capped at the engine's longest delay.
function Params.delay_time_now(p, beat_sec)
  local i = p:get("delay_sync")
  if i == 1 then return p:get("delay_time") end
  return math.min(SYNC_BEATS[i - 1] * beat_sec, MAX_DELAY)
end

function Params.add(p, deps)
  local player = deps.player
  local midi_out, jf_out, wsyn_out, tablet = deps.midi_out, deps.jf_out, deps.wsyn_out, deps.tablet
  local connect = deps.midi_connect or function(port) return midi.connect(port) end

  local beat_sec = deps.beat_sec or function() return clock.get_beat_sec() end

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
  p:add_number("midi_device", "device", 1, 16, 1, function(param)
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
  p:add_group("effects", "effects", 11)
  local function fx(id, name, min, max, warp, default, units, command)
    p:add_control(id, name, controlspec.new(min, max, warp, 0, default, units))
    p:set_action(id, function(v) engine[command](v) end)
  end
  fx("reverb_send", "reverb send", 0, 1, "lin", 0, "", "set_reverb_send")
  fx("delay_send", "delay send", 0, 1, "lin", 0, "", "set_delay_send")
  -- delay_sync (default "1", one beat) follows the norns clock; delay_time is the free setting,
  -- shown only while free. justdraw.lua re-sends the synced time when the tempo changes.
  p:add_option("delay_sync", "delay sync", SYNC_OPTIONS, 13)
  p:add_control("delay_time", "delay time", controlspec.new(0.01, 8, "lin", 0, 0.3, "s"))
  p:set_action("delay_time", function(v)
    if p:get("delay_sync") == 1 then engine.set_delay_time(v) end
  end)
  p:set_action("delay_sync", function(i)
    if i == 1 then p:show("delay_time") else p:hide("delay_time") end
    if _menu then _menu.rebuild_params() end
    engine.set_delay_time(Params.delay_time_now(p, beat_sec()))
  end)
  fx("delay_decay", "delay decay", 0.01, 60, "exp", 0.5, "s", "set_delay_decay")
  fx("delay_level", "delay level", 0, 2, "lin", 1, "", "set_delay_level")
  fx("delay_to_reverb", "delay to reverb", 0, 1, "lin", 1, "", "set_delay_to_reverb")
  fx("delay_to_dry", "delay to dry", 0, 1, "lin", 0, "", "set_delay_to_dry")
  fx("reverb_room", "reverb room", 0, 1, "lin", 0.5, "", "set_reverb_room")
  fx("reverb_damp", "reverb damp", 0, 1, "lin", 0.5, "", "set_reverb_damp")
  fx("reverb_level", "reverb level", 0, 2, "lin", 1, "", "set_reverb_level")

  -- Carter's delay: schicksalslied 2's granular chain, ported. It stays unallocated until grains_on
  -- is switched on. Each action sends its value to the engine, which stores it until the chain
  -- is allocated; params:bang() then brings the engine in line.
  p:add_group("carters_delay", "carter's delay", 37)
  p:add_binary("grains_on", "carter's delay", "toggle", 0)
  p:set_action("grains_on", function(v) engine.grains_on(v) end)
  local function grain(id, name, min, max, warp, step, default, units, command)
    p:add_control(id, name, controlspec.new(min, max, warp, step, default, units))
    p:set_action(id, function(v) engine[command](v) end)
  end
  local function grain_option(id, name, options, command)
    p:add_option(id, name, options, 1)
    p:set_action(id, function(i) engine[command](i - 1) end)
  end
  local OFF_ON = { "off", "on" }
  grain("grains_send", "send to delay", 0, 1, "lin", 0.01, 0, "", "set_grains_send")
  grain("grains_level", "delay level", 0, 1, "lin", 0.01, 0.3, "", "set_grains_level")

  p:add_separator("jd_grain_engine", "granular engine")
  grain_option("granular_freeze", "granular freeze", OFF_ON, "set_grains_freeze")
  -- The delay buffer is not saved, so recalling "on" would bring the chain up frozen on silence.
  p:set_save("granular_freeze", false)
  grain("buffer_preservation", "buffer preservation", 0, 1, "lin", 0.01, 0, "", "set_grains_rec_pre")
  grain_option("grain_window", "grain window", { "hann", "percussive", "swell", "reverse swell" },
    "set_grains_window")
  grain("grain_sync_distribution", "grain sync distribution", 0, 1, "lin", 0.01, 1, "",
    "set_grains_sync")
  grain("granular_cutoff_ceiling", "grain cutoff ceiling", 200, 16000, "exp", 1, 16000, "Hz",
    "set_grains_cutoff_ceiling")
  grain("grain_rate_mult", "grain rate mult", 0.25, 4, "lin", 0.01, 1, "x", "set_grains_rate_mult")
  grain_option("grain_octaves", "grain octaves", OFF_ON, "set_grains_octaves")
  grain_option("grain_fifths", "grain fifths & 4ths", OFF_ON, "set_grains_fifths")
  grain_option("grain_suboctaves", "grain sub-octaves", OFF_ON, "set_grains_suboctaves")
  grain_option("grain_reverse", "grain reverse", OFF_ON, "set_grains_reverse")
  -- Takes effect the next time the chain is allocated (switch carter's delay off and on).
  grain("grain_delay_scale", "grain delay scale", 0.01, 2, "lin", 0.01, 1, "", "set_grains_delay_scale")

  p:add_separator("jd_grain_fb", "feedback patch")
  grain("feedback_amp", "feedback amp", 0, 2, "lin", 0.01, 0, "", "set_grains_fb_amp")
  grain("feedback_balance", "feedback balance", -1, 1, "lin", 0.01, 0, "", "set_grains_fb_balance")
  grain("feedback_hpf", "feedback hpf", 5, 2000, "exp", 1, 12, "Hz", "set_grains_fb_hpf")
  p:add_separator("jd_grain_fb_adv", "(advanced)")
  grain("noise_inject_level", "noise inject level", 0, 1, "lin", 0.01, 0, "", "set_grains_fb_noise")
  grain("sine_inject_level", "sine inject level", 0, 1, "lin", 0.01, 0, "", "set_grains_fb_sine_level")
  grain("sine_inject_freq", "sine inject freq", 20, 2000, "exp", 0.1, 55, "Hz", "set_grains_fb_sine_hz")

  p:add_separator("jd_grain_lfo", "grain LFO rates")
  local LFOS = { { "pan", "pan" }, { "cutoff", "cutoff" }, { "res", "res" } }
  for n = 0, 3 do
    for _, l in ipairs(LFOS) do
      local id = "grain_" .. n .. "_" .. l[1] .. "_rate"
      p:add_control(id, "grain " .. (n + 1) .. " " .. l[2] .. " rate",
        controlspec.new(1, 64, "lin", 0.1, math.random(1, 64), "beats"))
      p:set_action(id, function(v) engine["set_grains_" .. l[1] .. "_rate"](n, v) end)
    end
  end
  p:add_trigger("randomize_grain_lfo_rates", "randomize all grain LFO rates")
  p:set_action("randomize_grain_lfo_rates", function()
    for n = 0, 3 do
      for _, l in ipairs(LFOS) do
        p:set("grain_" .. n .. "_" .. l[1] .. "_rate", math.random(10, 6400) / 100)
      end
    end
  end)
end

return Params
