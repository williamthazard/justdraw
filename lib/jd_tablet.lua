-- Tablet reader: raw Linux HID events (type, code, value) from a Wacom One become pen events.
-- No norns globals; Lua 5.3 compatible. The caller passes emit and schedule.
local Tablet = {}
Tablet.__index = Tablet

-- Which pen button is which. Swap here if the user's reading says the other way round.
local UPPER = 0x14c   -- BTN_STYLUS2
local LOWER = 0x14b   -- BTN_STYLUS

local EV_KEY, EV_ABS = 1, 3
local BTN_TOOL_PEN, BTN_TOUCH = 0x140, 0x14a
local ABS_X, ABS_Y, ABS_PRESSURE = 0, 1, 0x18

local MODELS = {
  ["CTL-472"] = { x = 15200, y = 9500, p = 2047 },
  ["CTL-672"] = { x = 21600, y = 13500, p = 2047 },
}

local function clamp01(v)
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

function Tablet.new(o)
  local self = setmetatable({}, Tablet)
  self.emit = o.emit
  self.schedule = o.schedule
  self.flip = o.flip and true or false
  self.max = MODELS["CTL-472"]
  -- pending state, updated by every event
  self.raw_x, self.raw_y, self.raw_p = 0, 0, 0
  self.tool, self.touch = false, false
  self.upper, self.lower = 0, 0
  -- state at the last flush
  self.was_touch, self.was_tool = false, false
  self.was_upper, self.was_lower = 0, 0
  self.last_p = 0          -- last nonzero pressure of the stroke (0..1)
  self.hx, self.hy = nil, nil  -- last hover position emitted
  self.pending = false
  return self
end

-- The first device whose name looks like the tablet; among those, the first that reports
-- pressure (has_pressure == true; nil means unknown and does not count as false).
function Tablet.pick(devices)
  local first
  for i, d in ipairs(devices) do
    local name = d.name or ""
    if name:find("CTL-472", 1, true) or name:find("CTL-672", 1, true) or name:find("Wacom", 1, true) then
      if d.has_pressure == true then return i end
      first = first or i
    end
  end
  return first
end

-- Which device to read: a port number, or nil for auto. Stored as a preference; the app
-- sets on_select to re-open the device when the param changes.
function Tablet:select(port)
  self.port = port
  if self.on_select then self.on_select(port) end
end

function Tablet:set_flip(b) self.flip = b and true or false end

function Tablet:set_model(name)
  name = name or ""
  self.max = name:find("672", 1, true) and MODELS["CTL-672"] or MODELS["CTL-472"]
end

function Tablet:event(type_, code, value)
  if type_ == EV_KEY then
    if code == BTN_TOOL_PEN then self.tool = value ~= 0
    elseif code == BTN_TOUCH then self.touch = value ~= 0
    elseif code == UPPER then self.upper = value
    elseif code == LOWER then self.lower = value
    else return end
  elseif type_ == EV_ABS then
    if code == ABS_X then self.raw_x = value
    elseif code == ABS_Y then self.raw_y = value
    elseif code == ABS_PRESSURE then self.raw_p = value
    else return end   -- ABS_DISTANCE and the rest
  else
    return
  end
  if not self.pending then
    self.pending = true
    self.schedule(function() self:flush() end, 0.002)
  end
end

function Tablet:position()
  local x = clamp01(self.raw_x / self.max.x)
  local y = clamp01(self.raw_y / self.max.y)
  if self.flip then x, y = 1 - x, 1 - y end
  return x, y
end

function Tablet:flush()
  self.pending = false
  local x, y = self:position()
  local down = self.tool and self.touch
  local was_down = self.was_touch and self.was_tool

  -- a pressure of 0 is never applied while the tip is down
  if down then
    local p = clamp01(self.raw_p / self.max.p)
    if p > 0 then self.last_p = p end
  end
  local p = self.last_p

  -- buttons: rising edges since the last flush, tip up or down
  local up_edge = self.upper ~= 0 and self.was_upper == 0
  local low_edge = self.lower ~= 0 and self.was_lower == 0
  self.was_upper, self.was_lower = self.upper, self.lower

  if down and not was_down then
    self.emit("penDown", { x = x, y = y, p = p })
  elseif down then
    self.emit("penMove", { x = x, y = y, p = p })
  elseif was_down then
    self.emit("penUp", { p = p })
    self.last_p = 0
    self.hx = nil
  end

  if not down then
    if self.tool then
      if x ~= self.hx or y ~= self.hy then
        self.hx, self.hy = x, y
        self.emit("hover", { x = x, y = y })
      end
    elseif self.was_tool then
      self.hx, self.hy = nil, nil
      self.emit("hoverOff", {})
    end
  end

  self.was_touch, self.was_tool = self.touch, self.tool
  if up_edge then self.emit("octaveUp", {}) end
  if low_edge then self.emit("octaveDown", {}) end
end

-- The device was unplugged: leave range at once.
function Tablet:removed()
  self.tool, self.touch = false, false
  self.upper, self.lower = 0, 0
  self:flush()
end

return Tablet
