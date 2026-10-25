-- The screen: a 102 x 64 canvas at the left (the tablet's aspect) with the 15 x 10 dot grid,
-- the hover ring, the tip dot and the fading trails; a narrow column at the right with the
-- note, its octave range, the outputs that are on, and a strip at the bottom for the
-- encoder overlay or a status line.
-- `s` is norns' screen (or a recorder). No norns globals; Lua 5.3 compatible.
local Math = include 'lib/jd_math'

local Screen = {}

local W, H = 102, 64          -- the canvas
local COL = 104               -- the right column starts here
local OUTPUTS = { { "engine", "E" }, { "midi", "M" }, { "crow", "C" }, { "jf", "J" }, { "wsyn", "W" } }
local FLASH = 0.3             -- seconds the range stays bright after an octave change

local function round(v) return math.floor(v + 0.5) end

local function trail(s, player, now)
  local release = player.release
  for _, tr in ipairs(player.trails) do
    local fade = 1
    if tr.up_at then fade = 1 - (now - tr.up_at) / release end
    if fade > 0 then
      local lx, ly
      for _, pt in ipairs(tr.points) do
        local x, y = pt.x * W, pt.y * H
        -- thin the points: a dot per pixel is plenty
        if not lx or math.abs(x - lx) >= 1 or math.abs(y - ly) >= 1 then
          lx, ly = x, y
          s.level(math.max(2, round((3 + 9 * pt.p) * fade)))
          s.circle(x, y, 1)
          s.fill()
        end
      end
    end
  end
end

-- The raw tablet values in place of the normal page (PARAMS > tablet readings).
local function readings(s, r)
  s.font_face(1)
  s.font_size(8)
  s.level(15)
  local lines = {
    "max x " .. r.max_x, "max y " .. r.max_y, "max p " .. r.max_p,
    "button " .. (r.button and (r.button .. " (" .. tostring(r.button_code) .. ")") or "none"),
  }
  for i, line in ipairs(lines) do
    s.move(2, 8 + (i - 1) * 9)
    s.text(line)
  end
  s.level(8)
  s.move(2, 52)
  s.text("x " .. r.x .. "  y " .. r.y .. "  p " .. r.p)
  s.level(3)
  s.move(2, 61)
  s.text("PARAMS > tablet readings")
  s.update()
end

function Screen.draw(s, player, ui, now)
  s.clear()
  s.aa(0)
  if ui.readings then return readings(s, ui.readings) end

  -- the dot grid, a whole pixel each: with aa off, a 0.5 circle near a pixel corner lights nothing
  s.level(2)
  for col = 1, 15 do
    for row = 1, 10 do
      s.pixel(math.floor(col / 16 * W), math.floor(row / 11 * H))
      s.fill()
    end
  end

  trail(s, player, now)

  if player.hover then
    s.level(8)
    s.circle(player.hover.x * W, player.hover.y * H, 4)
    s.stroke()
  end
  if player.tip then
    s.level(15)
    s.circle(player.tip.x * W, player.tip.y * H, 1.5 + 4 * player.tip.p)
    s.fill()
  end

  -- the right column
  s.font_face(1)
  s.font_size(8)
  if ui.note_text then
    s.level(15)
    s.move(COL, 9)
    s.text(ui.note_text)
  end
  local low = 12 * (player.octave + 1) + player.root
  local flashing = player.flash_at and now - player.flash_at < FLASH
  s.level(flashing and 15 or 5)
  s.move(COL, 21)
  s.text(Math.note_name(low))
  s.move(COL, 29)
  s.text(Math.note_name(low + 11))

  s.font_size(6)
  for i, o in ipairs(OUTPUTS) do
    s.level(ui.outputs[o[1]] and 15 or 2)
    s.move(COL + (i - 1) * 5, 41)
    s.text(o[2])
  end
  if ui.flip then
    s.level(4)
    s.move(COL, 49)
    s.text("flip")
  end

  -- the bottom strip: the encoder overlay while it lasts, otherwise the status
  local msg
  if ui.overlay and now < ui.overlay["until"] then msg = ui.overlay.text
  elseif ui.status then msg = ui.status end
  if msg then
    s.level(0)
    s.rect(0, 55, 128, 9)
    s.fill()
    s.font_size(8)
    s.level(15)
    s.move(2, 62)
    s.text(msg)
  end

  s.update()
end

return Screen
