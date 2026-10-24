-- Pure maths for just draw: pitch, MIDI values, volts, and the voice's envelopes.
-- No norns globals; Lua 5.3 compatible.
local M = {}

local NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function round(v) return math.floor(v + 0.5) end

-- y in 0..1, 0 at the far edge (after Flip)
function M.note_at(y, root, octave)
  return 12 * (octave + 1) + root + 11 * (1 - y)
end

function M.clamp_octave(o) return clamp(o, 1, 6) end

function M.note_name(note)
  local n = round(note)
  return NAMES[n % 12 + 1] .. (n // 12 - 1)
end

function M.bend_for(pitch, note, range)
  return clamp(round(8192 + (pitch - note) / range * 8192), 0, 16383)
end

function M.fits_bend(pitch, note, range)
  return math.abs(pitch - note) <= range
end

function M.cc_for(x) return round(127 * clamp(x, 0, 1)) end
function M.touch_for(p) return round(127 * clamp(p, 0, 1)) end
function M.velocity_for(p) return round(30 + 97 * clamp(p, 0, 1)) end

function M.pitch_volts(note) return (note - 60) / 12 end
function M.level_volts(p) return 1 + 4 * p end
function M.run_volts(ratio) return 5 * math.log(ratio, 2) end

-- Piecewise-linear lookup like IEnvGen on Env(levels, times); clamps outside the range.
function M.env_at(levels, times, x)
  local t0 = 0
  if x <= t0 then return levels[1] end
  for i = 1, #times do
    local t1 = t0 + times[i]
    if x <= t1 then
      return levels[i] + (levels[i + 1] - levels[i]) * (x - t0) / times[i]
    end
    t0 = t1
  end
  return levels[#levels]
end

-- The voice's own envelopes, copied from the \jd_voice SynthDef.
function M.ramp_at(x)
  return M.env_at({ 0.5, 0.5, 0.15, 0.04, 0.01 }, { 0.1, 0.3, 0.3, 0.3 }, x)
end

function M.curve_at(x)
  return M.env_at({ 1, 0.5, 0, -0.5, -0.85 }, { 0.2, 0.2, 0.3, 0.3 }, x)
end

function M.depth_at(x, noise)
  return M.env_at({ 0, 0, 1.5, noise }, { 0.45, 0.3, 0.25 }, x)
end

return M
