-- The MIDI output: one channel, played from the pen. Pitch bend carries the fine pitch,
-- channel pressure the pen pressure, and one chosen CC the x position.
-- A port of tabletseq lib/jd_midi.scd. `dev` is a norns midi device (colon methods);
-- it is passed in. No norns globals; Lua 5.3 compatible.
local M = include 'lib/jd_math'

local MidiOut = {}

local function round(v) return math.floor(v + 0.5) end

function MidiOut.new(dev)
  local o = {}
  local chan, range, cc_num = 1, 24, 74
  local sounding, last_bend, last_touch, last_cc

  local function note_up()
    if sounding then
      dev:note_off(sounding, 0, chan)
      sounding = nil
    end
  end

  local function silence()
    note_up()
    dev:cc(123, 0, chan)
    dev:pitchbend(8192, chan)
    last_bend, last_touch, last_cc = nil, nil, nil
  end

  -- The shared start of every note: its bend first, then any shaping messages the caller
  -- sends (between), then the note-on.
  local function start_note(pitch, n, p, between)
    last_bend = M.bend_for(pitch, n, range)
    dev:pitchbend(last_bend, chan)
    if between then between() end
    dev:note_on(n, M.velocity_for(p), chan)
    sounding = n
  end

  -- A new channel while a note sounds ends it on the old channel first. The next move
  -- resends bend and CC, since the range or CC number may have changed.
  function o.configure(ch, bend_range, cc)
    if ch ~= chan and sounding then silence() end
    chan, range, cc_num = ch, bend_range, cc
    last_bend, last_cc = nil, nil
  end

  -- Silences the old device before the new one takes over.
  function o.set_device(new_dev)
    silence()
    dev = new_dev
  end

  -- For MIDI-learn in the synth: sweeps the CC to both ends, then rests it in the middle.
  function o.send_cc()
    for _, v in ipairs({ 0, 127, 64 }) do dev:cc(cc_num, v, chan) end
    last_cc = nil
  end

  -- Bend, CC and pressure go first so the note starts already shaped.
  function o.down(pitch, x, p)
    local n = round(pitch)
    if sounding then note_up() end
    last_cc = M.cc_for(x)
    last_touch = M.touch_for(p)
    start_note(pitch, n, p, function()
      dev:cc(cc_num, last_cc, chan)
      dev:channel_pressure(last_touch, chan)
    end)
  end

  function o.move(pitch, x, p)
    if not sounding then return end
    if not M.fits_bend(pitch, sounding, range) then
      -- out of the bend range: end the note and start the nearest one
      dev:note_off(sounding, 0, chan)
      start_note(pitch, round(pitch), p)
      return
    end
    local bend = M.bend_for(pitch, sounding, range)
    local touch = M.touch_for(p)
    local cc = M.cc_for(x)
    if bend ~= last_bend then last_bend = bend; dev:pitchbend(bend, chan) end
    if touch ~= last_touch then last_touch = touch; dev:channel_pressure(touch, chan) end
    if cc ~= last_cc then last_cc = cc; dev:cc(cc_num, cc, chan) end
  end

  -- The bend stays where it is: the next pen-down sets it before its note-on.
  function o.up(p_last) note_up() end

  function o.knob(key, value) end
  function o.enable() end
  function o.disable() silence() end
  function o.stop() silence() end

  return o
end

return MidiOut
