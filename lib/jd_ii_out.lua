-- The Just Friends and w/syn outputs, over crow's ii bus.
-- `jf` / `wsyn` are crow.ii.jf / crow.ii.wsyn; `connected` says whether a crow is plugged in;
-- `settings` is the live settings table the params edit. All are passed in.
-- While crow is absent nothing is sent. JF's `mode` is only ever sent by apply_settings, never
-- at switch-off or cleanup. No norns globals; Lua 5.3 compatible.
local M = include 'lib/jd_math'

local THRESHOLD = 0.001 -- volts; smaller changes are not sent

local IiOut = {}

-- Returns send(key, value, fn): calls fn(value) unless `key` last sent the same value.
-- reset() forgets what was sent; note(key, value) records a value sent some other way.
local function changes()
  local sent = {}
  local function send(key, value, fn)
    local prev = sent[key]
    if prev and math.abs(value - prev) <= THRESHOLD then return end
    sent[key] = value
    fn(value)
  end
  local function reset() sent = {} end
  local function note(key, value) sent[key] = value end -- record a value another call carried
  return send, reset, note
end

-- Just Friends: each touch plays the next of six channels; the lift plays it again at level 0.
local JfOut = {}

function JfOut.new(opts)
  local jf, connected, settings = opts.jf, opts.connected, opts.settings
  local o = { settings = settings }
  local ratio = 0.7
  local enabled = false -- knobs reach the module only while the output is switched on
  local ch = 0         -- the channel of the latest touch
  local sounding = false
  local pitch_v = 0    -- the latest pitch, in volts
  local send, reset, note = changes()

  function o.apply_settings()
    if not connected() then return end
    jf.mode(settings.mode)
  end

  function o.reconnected() o.apply_settings() end

  function o.enable()
    enabled = true
    if not connected() then return end
    o.apply_settings()
    jf.run_mode(1)
    jf.run(M.run_volts(ratio))
  end

  function o.down(pitch, x, p)
    if not connected() then return end
    ch = ch % 6 + 1
    sounding = true
    pitch_v = M.pitch_volts(pitch)
    reset()
    note("pitch", pitch_v) -- play_voice carries the pitch
    jf.play_voice(ch, pitch_v, M.level_volts(p))
  end

  function o.move(pitch, x, p)
    if not connected() or not sounding then return end
    pitch_v = M.pitch_volts(pitch)
    send("pitch", pitch_v, function(v) jf.pitch(ch, v) end)
  end

  local function release()
    if not sounding then return end
    sounding = false
    if not connected() then return end
    jf.play_voice(ch, pitch_v, 0)
  end

  function o.up(p_last) release() end

  function o.knob(key, value)
    if key ~= "ratio" then return end
    ratio = value
    if not enabled or not connected() then return end
    jf.run(M.run_volts(ratio))
  end

  -- The module's settings are left alone; only a sounding note is released.
  function o.disable() enabled = false; release() end
  function o.stop() enabled = false; release() end

  return o
end

-- w/syn: each touch plays the next voice (within `voices`); x walks the wave shape.
local WsynOut = {}

function WsynOut.new(opts)
  local wsyn, connected, settings = opts.wsyn, opts.connected, opts.settings
  local o = { settings = settings }
  local noise = opts.noise or 0.5
  local ratio = 0.7
  local enabled = false -- knobs reach the module only while the output is switched on
  local v = 0          -- the voice of the latest touch
  local sounding = false
  local x_now = 0
  local send, reset, note = changes()

  function o.apply_settings()
    if not connected() then return end
    wsyn.voices(settings.voices)
    wsyn.lpg_time(settings.lpg_time)
    wsyn.lpg_symmetry(settings.lpg_symmetry)
    wsyn.fm_env(settings.fm_env)
    wsyn.ar_mode(settings.hold and 0 or 1)
  end

  function o.reconnected()
    reset() -- the module may have lost its shape too
    o.apply_settings()
  end

  local function send_fm_index()
    send("fm_index", math.min(M.depth_at(x_now, noise), 5), wsyn.fm_index)
  end

  -- The wave shape for x, each only when changed.
  local function shape()
    send("curve", 5 * M.curve_at(x_now), wsyn.curve)
    send("ramp", 10 * (0.5 - M.ramp_at(x_now)), wsyn.ramp)
    send_fm_index()
  end

  function o.enable()
    enabled = true
    if not connected() then return end
    reset()
    o.apply_settings()
    shape()
    wsyn.fm_ratio(ratio, 1)
  end

  function o.down(pitch, x, p)
    if not connected() then return end
    local n = settings.voices
    v = (n and n > 0) and (v % n + 1) or 1
    sounding = true
    x_now = x
    note("pitch", M.pitch_volts(pitch)) -- play_voice carries the pitch
    note("velocity", M.level_volts(p))   -- and the velocity
    wsyn.play_voice(v, M.pitch_volts(pitch), M.level_volts(p))
    shape()
  end

  function o.move(pitch, x, p)
    if not connected() or not sounding then return end
    x_now = x
    send("pitch", M.pitch_volts(pitch), function(volts) wsyn.pitch(v, volts) end)
    if settings.hold then
      send("velocity", M.level_volts(p), function(volts) wsyn.velocity(v, volts) end)
    end
    shape()
  end

  function o.up(p_last)
    if not sounding then return end
    sounding = false
    if connected() and settings.hold then wsyn.velocity(v, 0) end
  end

  -- Stored always; sent only while switched on (enable sends the latest values).
  function o.knob(key, value)
    if key == "noise" then
      noise = value
      if enabled and connected() then send_fm_index() end
    elseif key == "ratio" then
      ratio = value
      if enabled and connected() then wsyn.fm_ratio(ratio, 1) end
    end
  end

  local function silence()
    if not sounding then return end
    sounding = false
    if connected() then wsyn.velocity(v, 0) end
  end

  function o.disable() enabled = false; silence() end
  function o.stop() enabled = false; silence() end

  return o
end

IiOut.Jf, IiOut.Wsyn = JfOut, WsynOut

return IiOut
