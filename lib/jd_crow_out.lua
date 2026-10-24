-- The crow output: pitch on out 1, gate on out 2, pressure on out 3, x on out 4.
-- `crow` is norns's crow table (crow.output[i].volts / .slew); `connected` says whether a
-- crow is plugged in; `now` is the clock, unused here. All are passed in.
-- While crow is absent nothing is sent. No norns globals; Lua 5.3 compatible.
local M = include 'lib/jd_math'

local CrowOut = {}

local SLEW = 0.015      -- seconds; hides the stepping between tablet reports
local THRESHOLD = 0.001 -- volts; smaller changes are not sent

function CrowOut.new(opts)
  local crow, connected = opts.crow, opts.connected
  local o = {}
  local release = 0.5
  local sent = {} -- the last volts sent on each output while the pen is down

  local function active() return connected() end

  -- Sends volts to an output when they differ from what it last got by more than THRESHOLD.
  local function send(i, volts)
    local prev = sent[i]
    if prev and math.abs(volts - prev) <= THRESHOLD then return end
    sent[i] = volts
    crow.output[i].volts = volts
  end

  function o.down(pitch, x, p)
    if not active() then return end
    sent = {}
    crow.output[1].slew = SLEW
    send(1, M.pitch_volts(pitch))
    send(2, 5)
    crow.output[3].slew = SLEW
    send(3, 5 * p)
    send(4, 5 * x)
  end

  function o.move(pitch, x, p)
    if not active() then return end
    send(1, M.pitch_volts(pitch))
    send(3, 5 * p)
    send(4, 5 * x)
  end

  -- Pitch and x hold; the gate closes and pressure falls over `release`.
  function o.up(p_last)
    if not active() then return end
    crow.output[2].volts = 0
    crow.output[3].slew = release
    crow.output[3].volts = 0
    sent = {}
  end

  function o.knob(key, value)
    if key == "release" then release = value end
  end

  function o.enable() end

  -- Gate and pressure drop at once, whatever the slew was.
  local function silence()
    if not active() then return end
    crow.output[2].volts = 0
    crow.output[3].slew = 0
    crow.output[3].volts = 0
    sent = {}
  end

  o.disable = silence
  o.stop = silence

  return o
end

return CrowOut
