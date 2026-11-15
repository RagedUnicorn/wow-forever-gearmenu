--[[
  MIT License

  Copyright (c) 2026 Michael Wiesendanger

  Permission is hereby granted, free of charge, to any person obtaining
  a copy of this software and associated documentation files (the
  "Software"), to deal in the Software without restriction, including
  without limitation the rights to use, copy, modify, merge, publish,
  distribute, sublicense, and/or sell copies of the Software, and to
  permit persons to whom the Software is furnished to do so, subject to
  the following conditions:

  The above copyright notice and this permission notice shall be
  included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
  LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
  OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
  WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]--

-- luacheck: read globals UnitExists

local mod = rggm
local me = {}

mod.target = me

me.tag = "Target"

--[[
  Only whether the player has a target is tracked. UnitGUID can return a secret string on the
  Forever client that addon code may not compare, so the GUID itself is never stored.
]]--
local hasTarget = false

--[[
  Returns whether the player currently has a target

  @return {boolean}
]]--
function me.HasTarget()
  return hasTarget
end

--[[
  Update whether the player currently has a target
]]--
function me.UpdateCurrentTarget()
  hasTarget = UnitExists(RGGM_CONSTANTS.UNIT_ID_TARGET) and true or false
  mod.logger.LogDebug(me.tag, "Update players target - hasTarget: " .. tostring(hasTarget))
end
