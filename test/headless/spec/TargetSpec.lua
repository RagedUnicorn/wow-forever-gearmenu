--[[
  MIT License

  Copyright (c) 2026 Michael Wiesendanger

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]--

--[[
  Spec for the tracked target in code/Target.lua (me.UpdateCurrentTarget, me.HasTarget).
  gui/GearBar.lua reads it to tell whether the player has a target at all, so a target that
  was cleared must not be reported afterwards. Only UnitExists is consulted - UnitGUID can
  return a secret string on the Forever client that addon code may not compare.

  CoreInitializeSpec covers the seeding on login; this spec covers the updates that
  PLAYER_TARGET_CHANGED drives afterwards. UnitExists is stubbed per test.
]]--

local wowStubs = require("WowStubs")

describe("Target", function()
  local target
  local targetExists
  local queriedUnits
  local previousLogger
  local restore

  before_each(function()
    targetExists = false
    queriedUnits = {}

    previousLogger = rggm.logger
    rggm.logger = { LogDebug = function() end }

    restore = wowStubs.install({
      UnitExists = function(unit)
        queriedUnits[#queriedUnits + 1] = unit
        return targetExists
      end,
      UnitGUID = function()
        error("Target must not read the target GUID")
      end
    })

    -- fresh file-local target state
    dofile("code/Target.lua")
    target = rggm.target
  end)

  after_each(function()
    restore()
    rggm.logger = previousLogger
  end)

  it("starts without a target before the first update", function()
    assert.is_false(target.HasTarget())
  end)

  it("checks whether the target unit exists", function()
    targetExists = true

    target.UpdateCurrentTarget()

    assert.are.same({ RGGM_CONSTANTS.UNIT_ID_TARGET }, queriedUnits)
    assert.is_true(target.HasTarget())
  end)

  it("treats a nil result as no target", function()
    targetExists = nil

    target.UpdateCurrentTarget()

    assert.is_false(target.HasTarget())
  end)

  it("forgets the previous target once the target is cleared", function()
    targetExists = true
    target.UpdateCurrentTarget()

    targetExists = false
    target.UpdateCurrentTarget()

    assert.is_false(target.HasTarget())
  end)
end)
