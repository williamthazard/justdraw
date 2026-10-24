-- just draw
-- a one-voice instrument
-- played on a wacom one pen tablet
--
-- plug the tablet into norns.
-- the pen's y is pitch, x is sound,
-- pressure is loudness.
--
-- E1: noise
-- E2: ratio
-- E3: release
-- K2: octave down
-- K3: octave up
--
-- outputs (engine, midi, crow,
-- just friends, w/syn) and every
-- other setting live in PARAMS.

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

local player, tablet, midi_out, crow_out, jf_out, wsyn_out
local redraw_metro, sched_metro
local active_port                  -- the hid port being read, or nil
local status                       -- shown on screen when something is wrong
local overlay                      -- { text, until }
local dirty = true
local prior_crow_add

-- Stands in for the MIDI device until the bang connects the one the param names.
local NO_DEVICE = setmetatable({}, { __index = function() return function() end end })

local function now() return util.time() end

local function crow_here() return norns.crow.connected() end

-- Which hid port to read: the chosen one, or the first that looks like the tablet.
-- `gone` is a device that is being unplugged and no longer counts.
local function connect_tablet(gone)
  local devices = {}
  for i = 1, 4 do
    local vp = hid.vports[i]
    local here = vp.device and vp.device ~= gone
    devices[i] = { name = here and vp.name or "" }
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

function init()
  local function ports()
    local names = {}
    for i = 1, 16 do names[i] = midi.vports[i].name end
    return names
  end

  local jf_settings = { mode = 1 }
  local wsyn_settings = { voices = 4, lpg_time = 0, lpg_symmetry = 0, hold = true }

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
    for _, name in ipairs({ "crow", "jf", "wsyn" }) do
      if player.on[name] then
        local out = player.outputs[name]
        out.disable()
        out.enable()
      end
    end
  end

  Params.add(params, {
    player = player, midi_out = midi_out, jf_out = jf_out, wsyn_out = wsyn_out,
    tablet = tablet, ports = ports,
  })

  redraw_metro = metro.init()
  redraw_metro.time = 1 / FPS
  redraw_metro.event = function()
    player:prune()
    if overlay and now() >= overlay["until"] then overlay = nil; dirty = true end
    local fading = #player.trails > 0
    local flashing = player.flash_at and now() - player.flash_at < 0.5
    if dirty or fading or flashing then
      dirty = false
      redraw()
    end
  end
  redraw_metro:start()

  params:bang()
end

function enc(n, d)
  local id = ENCODERS[n]
  if not id then return end
  params:delta(id, d)
  overlay = { text = id .. " " .. params:string(id), ["until"] = now() + OVERLAY }
  dirty = true
end

function key(n, z)
  if z ~= 1 then return end
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
    overlay = overlay,
    status = status,
    flip = params:get("flip") == 1,
  }, now())
end

function cleanup()
  if redraw_metro then redraw_metro:stop() end
  if sched_metro then sched_metro:stop() end
  if active_port then hid.vports[active_port].event = nil end
  if prior_crow_add then norns.crow.add = prior_crow_add end
  if player then player:stop_all() end
end
