-- The engine output: the first implementation of the shared output interface.
-- `engine` is norns's engine table (plain functions, called with a dot); it is passed in.
-- No norns globals; Lua 5.3 compatible.
local EngineOut = {}

function EngineOut.new(engine)
  local o = {}

  function o.down(pitch, x, p) engine.voice_on(pitch, x, p) end
  function o.move(pitch, x, p) engine.voice_move(pitch, x, p) end
  -- The voice keeps its last pressure, so it releases from there.
  function o.up(p_last) engine.voice_off() end
  function o.knob(key, value) engine["set_" .. key](value) end
  function o.enable() end
  function o.disable() engine.voice_off() end
  function o.stop() engine.voice_off() end

  return o
end

return EngineOut
