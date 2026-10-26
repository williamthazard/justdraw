---just draw
---
---draw on a wacom one
---to play one voice.
---
---y is pitch
---x is the sound
---pressure is loudness
---pen buttons: octave
---
---E1: noise
---E2: ratio
---E3: release
---K2: octave down
---K3: octave up
---K1 hold: shift
---
---outputs and other
---settings: PARAMS

engine.name = 'JustDraw'

local Math = include 'lib/jd_math'
local Tablet = include 'lib/jd_tablet'
local Player = include 'lib/jd_player'
local Params = include 'lib/jd_params'
local Screen = include 'lib/jd_screen'
local EngineOut = include 'lib/jd_engine_out'
local MidiOut = include 'lib/jd_midi_out'
local CrowOut = include 'lib/jd_crow_out'
local Ii = include 'lib/jd_ii_out'

local FPS = 30
local OVERLAY = 1                 -- seconds an encoder's name and value stay on screen
local ENCODERS = { "noise", "ratio", "release" }
local OUTPUT_NAMES = { "engine", "midi", "crow", "jf", "wsyn" }   -- the E M C J W row, left to right

local player, tablet, midi_out, crow_out, jf_out, wsyn_out
local redraw_metro, sched_metro
local active_port                  -- the hid port being read, or nil
local status                       -- shown on screen when something is wrong
local overlay                      -- { text, until }
local dirty = true
local shift = false                -- K1 is held
local cursor = 1                   -- the output the shift layer's K3 switches
local prior_crow_add
local prior_tempo_handler
local last_tempo
local poll_at = 0
local TEMPO_POLL = 0.25            -- seconds between tempo checks

-- Stands in for the MIDI device until the bang connects the one the param names.
local NO_DEVICE = setmetatable({}, { __index = function() return function() end end })

local function now() return util.time() end

local function crow_here() return norns.crow.connected() end

-- Does the device list ABS_PRESSURE (0x18) among its EV_ABS (3) codes? nil when it doesn't say.
local function reports_pressure(device)
  local codes = type(device) == "table" and device.codes
  local abs = type(codes) == "table" and codes[3]
  if type(abs) ~= "table" or next(abs) == nil then return nil end
  if abs[0x18] ~= nil then return true end
  for _, c in pairs(abs) do
    if c == 0x18 then return true end
  end
  return false
end

-- Which hid port to read: the chosen one, or the first that looks like the tablet.
-- `gone` is a device that is being unplugged and no longer counts.
local function connect_tablet(gone)
  local devices = {}
  for i = 1, 4 do
    local vp = hid.vports[i]
    local here = vp.device and vp.device ~= gone
    devices[i] = { name = here and vp.name or "", has_pressure = nil }
    if here then devices[i].has_pressure = reports_pressure(vp.device) end
  end
  local port = tablet.port
  if not port then port = Tablet.pick(devices) end
  local target = (port and devices[port].name ~= "") and port or nil
  -- Leaving the port a stroke may be on: lift it before the old handler is dropped.
  if active_port and target ~= active_port then tablet:removed() end
  if active_port then hid.vports[active_port].event = nil end
  active_port = nil
  if target then
    local vp = hid.connect(port)
    vp.event = function(t, c, v) tablet:event(t, c, v) end
    tablet:set_model(vp.name)
    active_port = port
    status = nil
  else
    status = "plug in the tablet"
  end
  dirty = true
end

-- norns' crow.ii.<module> returns a one-off table that every index appends to, so a cached
-- module accumulates the names of earlier calls. Resolve it afresh on every call.
local function ii_module(name)
  return setmetatable({}, { __index = function(_, fn)
    return function(...) return crow.ii[name][fn](...) end
  end })
end

-- Re-sends the delay time when it follows the clock. Call after the tempo changes.
local function resync_delay()
  last_tempo = clock.get_tempo()
  if params:get("delay_sync") > 1 then
    engine.set_delay_time(Params.delay_time_now(params, clock.get_beat_sec()))
  end
end

-- Sends the settings of each named output that is on. `restart` switches it off and on again,
-- which also re-sends a blank module's wave shape but releases a sounding note; without it the
-- settings are applied in place. Returns how many it sent to.
local function resend(names, restart)
  local n = 0
  for _, name in ipairs(names) do
    if player.on[name] then
      local out = player.outputs[name]
      if restart then
        out.disable()
        out.enable()
      elseif out.apply_settings then
        out.apply_settings()
      end
      n = n + 1
    end
  end
  return n
end

local function say(text)
  overlay = { text = text, ["until"] = now() + OVERLAY }
  dirty = true
end

function init()
  local function ports()
    local names = {}
    for i = 1, 16 do names[i] = midi.vports[i].name end
    return names
  end

  local jf_settings = { mode = 1 }
  local wsyn_settings = { voices = 4, lpg_time = 0, lpg_symmetry = 0, fm_env = 0, hold = true }

  midi_out = MidiOut.new(NO_DEVICE)
  crow_out = CrowOut.new{ crow = crow, connected = crow_here }
  jf_out = Ii.Jf.new{ jf = ii_module('jf'), connected = crow_here, settings = jf_settings }
  wsyn_out = Ii.Wsyn.new{ wsyn = ii_module('wsyn'), connected = crow_here, settings = wsyn_settings }

  player = Player.new{
    outputs = {
      engine = EngineOut.new(engine), midi = midi_out, crow = crow_out,
      jf = jf_out, wsyn = wsyn_out,
    },
    now = now,
  }

  -- One-shot timer for the tablet's 2 ms report-end wait.
  sched_metro = metro.init()
  sched_metro.time = 0.002
  local pending
  sched_metro.event = function()
    sched_metro:stop()
    local f = pending
    pending = nil
    if f then f() end
  end

  tablet = Tablet.new{
    emit = function(evt, d) player:pen(evt, d); dirty = true end,
    now = now,
    schedule = function(f, secs)
      pending = f
      sched_metro:start(secs, 1)
    end,
  }
  tablet.on_select = function() connect_tablet() end

  hid.add = function() connect_tablet() end
  hid.remove = function(dev)
    if active_port and hid.vports[active_port].device == dev then tablet:removed() end
    connect_tablet(dev)
  end

  crow.ii.pullup(true)
  -- A crow plugged in later starts blank: pull-ups again, and each module output that is on
  -- sends its settings (switching it off and on again does exactly that).
  prior_crow_add = norns.crow.add
  norns.crow.add = function(...)
    if prior_crow_add then prior_crow_add(...) end
    crow.ii.pullup(true)
    resend({ "crow", "jf", "wsyn" }, true)
  end

  Params.add(params, {
    player = player, midi_out = midi_out, jf_out = jf_out, wsyn_out = wsyn_out,
    tablet = tablet, ports = ports,
    on_readings = function() dirty = true end,
  })

  -- A tempo edit in PARAMETERS calls the handler; the redraw metro's poll catches the rest.
  prior_tempo_handler = clock.tempo_change_handler
  clock.tempo_change_handler = function(...)
    if prior_tempo_handler then prior_tempo_handler(...) end
    resync_delay()
  end

  redraw_metro = metro.init()
  redraw_metro.time = 1 / FPS
  redraw_metro.event = function()
    local trails = #player.trails
    tablet:check_idle(now())
    player:prune()
    -- the last trail just expired: draw once more so its partly faded frame does not stay on screen
    if #player.trails ~= trails then dirty = true end
    -- Link, MIDI and crow clocks change the tempo without calling the handler: poll for it.
    if now() >= poll_at then
      poll_at = now() + TEMPO_POLL
      if math.abs(clock.get_tempo() - last_tempo) > 0.01 then resync_delay() end
    end
    if overlay and now() >= overlay["until"] then overlay = nil; dirty = true end
    local fading = #player.trails > 0
    local flashing = player.flash_at and now() - player.flash_at < 0.5
    local reading = params:get("tablet_readings") == 1     -- the readings page redraws continuously
    if dirty or fading or flashing or reading then
      dirty = false
      redraw()
    end
  end
  redraw_metro:start()

  params:bang()
  last_tempo = clock.get_tempo()
end

-- K1 held: E2 and E3 reach the delay.
local SHIFT_ENCODERS = { [2] = "delay_sync", [3] = "delay_decay" }

function enc(n, d)
  if shift then
    if n == 1 then
      cursor = math.max(1, math.min(#OUTPUT_NAMES, cursor + d))
      dirty = true
      return
    end
    local id = SHIFT_ENCODERS[n]
    if not id then return end
    params:delta(id, d)
    say(id:gsub("_", " ") .. " " .. params:string(id))
    return
  end
  local id = ENCODERS[n]
  if not id then return end
  params:delta(id, d)
  say(id .. " " .. params:string(id))
end

function key(n, z)
  if n == 1 then shift = (z == 1); dirty = true; return end
  if z ~= 1 then return end
  if shift then
    if n == 3 then
      local id = "out_" .. OUTPUT_NAMES[cursor]
      params:set(id, 1 - params:get(id))
      say(OUTPUT_NAMES[cursor] .. " " .. (params:get(id) == 1 and "on" or "off"))
    elseif n == 2 then
      if not crow_here() then say("crow not connected")
      else say(resend({ "jf", "wsyn" }) > 0 and "JF and w/syn settings sent" or "no ii outputs on") end
    end
    dirty = true
    return
  end
  if n == 2 then player:shift_octave(-1)
  elseif n == 3 then player:shift_octave(1) end
  dirty = true
end

function redraw()
  local note_text
  local pitch = player:pitch()
  if pitch then note_text = Math.note_name(pitch) end
  local outputs = {}
  for name, on in pairs(player.on) do outputs[name] = on end
  Screen.draw(screen, player, {
    note_text = note_text,
    outputs = outputs,
    cursor = shift and cursor or nil,
    overlay = overlay,
    status = status,
    flip = params:get("flip") == 1,
    readings = params:get("tablet_readings") == 1 and tablet:readings() or nil,
  }, now())
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if sched_metro then sched_metro:stop() end
  if active_port then hid.vports[active_port].event = nil end
  if prior_crow_add then norns.crow.add = prior_crow_add end
  if player then clock.tempo_change_handler = prior_tempo_handler end
  if player then player:stop_all() end
end
