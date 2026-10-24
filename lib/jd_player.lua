-- The player: routes pen events to whichever outputs are switched on.
-- Outputs are plain function tables (down, move, up, knob, enable, disable, stop).
-- No norns globals; Lua 5.3 compatible. The caller passes outputs, now and on_octave.
local Math = include 'lib/jd_math'

local Player = {}
Player.__index = Player

local NAMES = { "engine", "midi", "crow", "jf", "wsyn" }

function Player.new(o)
  local self = setmetatable({}, Player)
  self.outputs = o.outputs or {}
  self.now = o.now or function() return 0 end
  self.on_octave = o.on_octave
  self.root, self.octave = 0, 3
  self.noise, self.ratio, self.release = 2, 0.7, 0.5
  self.on = {}     -- name -> switched on
  self.live = {}   -- name -> got this stroke's down
  -- The tip while it is down ({x,y,p} or nil). Named tip, not pen: the method is :pen.
  self.tip, self.hover = nil, nil
  self.trails = {}
  self.flash_at = nil
  return self
end

function Player:pitch()
  local at = self.tip or self.hover
  if not at then return nil end
  return Math.note_at(at.y, self.root, self.octave)
end

-- Call method on every live output (those that got this stroke's down).
function Player:each_live(method, ...)
  for _, name in ipairs(NAMES) do
    local out = self.outputs[name]
    if out and self.live[name] then out[method](...) end
  end
end

function Player:resend_move()
  if not self.tip then return end
  self:each_live("move", self:pitch(), self.tip.x, self.tip.p)
end

function Player:prune()
  local now, kept = self.now(), {}
  for _, tr in ipairs(self.trails) do
    if not tr.up_at or now - tr.up_at <= self.release then kept[#kept + 1] = tr end
  end
  self.trails = kept
end

function Player:pen_down(d)
  self.hover = nil
  self.tip = { x = d.x, y = d.y, p = d.p }
  self.live = {}
  for _, name in ipairs(NAMES) do
    if self.on[name] and self.outputs[name] then self.live[name] = true end
  end
  self.trails[#self.trails + 1] = { points = { { x = d.x, y = d.y, p = d.p } } }
  self:each_live("down", self:pitch(), d.x, d.p)
end

function Player:pen_move(d)
  if not self.tip then return end
  self.tip = { x = d.x, y = d.y, p = d.p }
  local tr = self.trails[#self.trails]
  if tr and not tr.up_at then tr.points[#tr.points + 1] = { x = d.x, y = d.y, p = d.p } end
  self:each_live("move", self:pitch(), d.x, d.p)
end

function Player:pen_up(d)
  if not self.tip then return end
  local tr = self.trails[#self.trails]
  if tr and not tr.up_at then tr.up_at = self.now() end
  self:each_live("up", d.p)
  self.tip, self.live = nil, {}
end

function Player:pen(evt, d)
  if evt == "penDown" then self:pen_down(d)
  elseif evt == "penMove" then self:pen_move(d)
  elseif evt == "penUp" then self:pen_up(d)
  elseif evt == "hover" then self.hover = { x = d.x, y = d.y }
  elseif evt == "hoverOff" then self.hover = nil
  elseif evt == "octaveUp" then self:shift_octave(1)
  elseif evt == "octaveDown" then self:shift_octave(-1) end
  self:prune()
end

function Player:set(key, value)
  if key == "root" then
    self.root = value
    self:resend_move()
  elseif key == "octave" then
    self.octave = Math.clamp_octave(value)
    self:resend_move()
  elseif key == "noise" or key == "ratio" or key == "release" then
    self[key] = value
    for _, name in ipairs(NAMES) do
      local out = self.outputs[name]
      if out then out.knob(key, value) end
    end
  end
end

function Player:shift_octave(dir)
  local new = Math.clamp_octave(self.octave + dir)
  if new == self.octave then return end
  self.octave = new
  if self.on_octave then self.on_octave(new) end
  self.flash_at = self.now()
  self:resend_move()
end

function Player:switch(name, on)
  on = on and true or false
  if (self.on[name] or false) == on then return end
  self.on[name] = on
  local out = self.outputs[name]
  if on then
    if out then out.enable() end
  else
    self.live[name] = nil
    if out then out.disable() end
  end
end

function Player:stop_all()
  for _, name in ipairs(NAMES) do
    local out = self.outputs[name]
    if out then out.stop() end
  end
  self.tip, self.live = nil, {}
end

return Player
