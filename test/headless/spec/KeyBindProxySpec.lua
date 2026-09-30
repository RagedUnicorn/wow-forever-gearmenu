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
  Spec for the key-bind proxy module gui/KeyBindProxy.lua: the hidden secure buttons every
  GearMenu key binding targets. Covers the proxy creation (names, template, click phases,
  useOnKeyDown), the binding-name globals, the (bindIndex, position) -> "/use <slotId>" mapping
  following slot and bar changes, the idempotent attribute writes and the deferral of every
  secure-attribute write to the end of combat.

  The module reaches the client through CreateFrame / InCombatLockdown only; both come from the
  WowStubs registry (the frame stub records attributes), the gearBars from a recorder stub of
  gearBarManager. gui/KeyBindProxy.lua sets the BINDING_ globals from rggm.L at load time, so a
  localization stub is installed before the dofile.
]]--

-- luacheck: read globals BINDING_HEADER_GEARMENU PREFACE_GEARMENU_BAR1 PREFACE_GEARMENU_BAR10

local wowStubs = require("WowStubs")

local MAX_BARS = RGGM_CONSTANTS.MAX_GEAR_BARS
local MAX_SLOTS = RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS

describe("KeyBindProxy", function()
  local keyBindProxy
  local previous
  local restore
  local frames
  local gearBars
  local uiGearBars
  local keyPresses
  local fastPress

  --[[
    @param {number} bindIndex
    @param {number} position
    @return {table}
      the recorded proxy frame
  ]]--
  local function proxy(bindIndex, position)
    return frames.frames[string.format("GM_KeyBindBar%dSlot%d", bindIndex, position)]
  end

  before_each(function()
    fastPress = false
    gearBars = {}
    uiGearBars = {}
    keyPresses = {}
    frames = wowStubs.stubs.FrameRegistry()

    previous = {
      keyBindProxy = rggm.keyBindProxy,
      gearBarManager = rggm.gearBarManager,
      gearBarStorage = rggm.gearBarStorage,
      gearBar = rggm.gearBar,
      configuration = rggm.configuration,
      logger = rggm.logger,
      L = rggm.L
    }

    rggm.gearBarStorage = {
      GetGearBars = function() return uiGearBars end
    }
    rggm.gearBar = {
      GearSlotOnKeyPress = function(gearSlot, down)
        keyPresses[#keyPresses + 1] = { gearSlot = gearSlot, down = down }
      end
    }

    rggm.L = {
      keybind_category = "GearMenu",
      keybind_bar_preface = "GearBar %d",
      keybind_slot_name = "GearBar %d - Slot %d"
    }
    rggm.gearBarManager = {
      GetGearBars = function() return gearBars end
    }
    rggm.configuration = {
      IsFastPressEnabled = function() return fastPress end
    }
    rggm.logger = {
      LogDebug = function() end,
      LogInfo = function() end,
      LogWarn = function() end,
      LogError = function() end
    }

    restore = wowStubs.install({
      InCombatLockdown = wowStubs.stubs.InCombatLockdown(false),
      CreateFrame = frames.CreateFrame,
      UIParent = {}
    })

    dofile("gui/KeyBindProxy.lua")
    keyBindProxy = rggm.keyBindProxy
  end)

  after_each(function()
    restore()

    rggm.keyBindProxy = previous.keyBindProxy
    rggm.gearBarManager = previous.gearBarManager
    rggm.gearBarStorage = previous.gearBarStorage
    rggm.gearBar = previous.gearBar
    rggm.configuration = previous.configuration
    rggm.logger = previous.logger
    rggm.L = previous.L
  end)

  describe("GetProxyName / GetProxyAction", function()
    it("build the stable names Bindings.xml declares", function()
      assert.are.equal("GM_KeyBindBar3Slot12", keyBindProxy.GetProxyName(3, 12))
      assert.are.equal("CLICK GM_KeyBindBar3Slot12:LeftButton", keyBindProxy.GetProxyAction(3, 12))
    end)
  end)

  describe("SetupBindingNames", function()
    it("sets the category, the per-bar preface rows and the name of every proxy action at load", function()
      assert.are.equal("GearMenu", BINDING_HEADER_GEARMENU)
      assert.are.equal("GearBar 1", PREFACE_GEARMENU_BAR1)
      assert.are.equal("GearBar 10", PREFACE_GEARMENU_BAR10)
      assert.are.equal("GearBar 2 - Slot 5", _G["BINDING_NAME_CLICK GM_KeyBindBar2Slot5:LeftButton"])
      assert.are.equal("GearBar 10 - Slot 20", _G["BINDING_NAME_CLICK GM_KeyBindBar10Slot20:LeftButton"])
    end)
  end)

  describe("Setup", function()
    it("creates one hidden secure proxy per possible gearSlot, registered for both click phases", function()
      keyBindProxy.Setup()

      assert.is_true(keyBindProxy.IsSetUp())
      assert.are.equal(MAX_BARS * MAX_SLOTS, frames.created)

      local first = proxy(1, 1)
      local last = proxy(MAX_BARS, MAX_SLOTS)

      assert.is_table(first)
      assert.is_table(last)
      assert.are.equal("Button", first.frameType)
      assert.are.equal("SecureActionButtonTemplate", first.template)
      assert.are.same({ "LeftButtonDown", "LeftButtonUp" }, first.clicks)
      assert.is_true(first.hidden)
      assert.are.equal(false, first:GetAttribute("useOnKeyDown"))
      assert.are.equal(last, keyBindProxy.GetProxy(MAX_BARS, MAX_SLOTS))
    end)

    it("carries the fast-press option as useOnKeyDown", function()
      fastPress = true

      keyBindProxy.Setup()

      assert.are.equal(true, proxy(1, 1):GetAttribute("useOnKeyDown"))
      assert.are.equal(true, proxy(MAX_BARS, MAX_SLOTS):GetAttribute("useOnKeyDown"))
    end)

    it("creates the proxies only once", function()
      keyBindProxy.Setup()
      keyBindProxy.Setup()

      assert.are.equal(MAX_BARS * MAX_SLOTS, frames.created)
    end)

    it("defers the creation during combat lockdown and creates on FlushPending", function()
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })

      keyBindProxy.Setup()

      assert.is_false(keyBindProxy.IsSetUp())
      assert.are.equal(0, frames.created)

      restoreCombat()
      keyBindProxy.FlushPending()

      assert.is_true(keyBindProxy.IsSetUp())
      assert.are.equal(MAX_BARS * MAX_SLOTS, frames.created)
    end)
  end)

  describe("ComputeMapping", function()
    it("maps every configured slot to its slotId by bindIndex and position", function()
      local mapping = keyBindProxy.ComputeMapping({
        { bindIndex = 1, slots = { { slotId = 13 }, { slotId = 14 } } },
        { bindIndex = 4, slots = { { slotId = 1 } } }
      })

      assert.are.same({ [1] = { 13, 14 }, [4] = { 1 } }, mapping)
    end)

    it("skips bars without a bindIndex and slots without a slotId", function()
      local mapping = keyBindProxy.ComputeMapping({
        { slots = { { slotId = 13 } } },
        { bindIndex = 2, slots = { { slotId = nil }, { slotId = 16 } } }
      })

      assert.are.same({ [2] = { [2] = 16 } }, mapping)
    end)
  end)

  describe("Update", function()
    it("is a no-op before Setup", function()
      gearBars = { { bindIndex = 1, slots = { { slotId = 13 } } } }

      assert.has_no.errors(function() keyBindProxy.Update() end)
      assert.are.equal(0, frames.created)
    end)

    it("points the proxy of a configured slot at its /use macro and leaves the others without a type", function()
      gearBars = { { bindIndex = 1, slots = { [1] = { slotId = 1 }, [2] = { slotId = 13 } } } }

      keyBindProxy.Setup()

      assert.are.equal("macro", proxy(1, 2):GetAttribute("type"))
      assert.are.equal("/use 13", proxy(1, 2):GetAttribute("macrotext"))
      assert.are.equal(13, proxy(1, 2):GetAttribute("slotId"))
      assert.are.equal("/use 1", proxy(1, 1):GetAttribute("macrotext"))
      assert.is_nil(proxy(1, 3):GetAttribute("type"))
      assert.is_nil(proxy(2, 1):GetAttribute("type"))
    end)

    it("follows a slotId change, a slot removal and a bar removal", function()
      local barA = { bindIndex = 1, slots = { [1] = { slotId = 1 }, [2] = { slotId = 13 } } }
      local barB = { bindIndex = 2, slots = { [1] = { slotId = 16 } } }
      gearBars = { barA, barB }
      keyBindProxy.Setup()

      barA.slots[2].slotId = 14
      keyBindProxy.Update()
      assert.are.equal("/use 14", proxy(1, 2):GetAttribute("macrotext"))

      table.remove(barA.slots, 1)
      keyBindProxy.Update()
      assert.are.equal("/use 14", proxy(1, 1):GetAttribute("macrotext"))
      assert.is_nil(proxy(1, 2):GetAttribute("type"))
      assert.is_nil(proxy(1, 2):GetAttribute("macrotext"))
      assert.is_nil(proxy(1, 2):GetAttribute("slotId"))

      gearBars = { barA }
      keyBindProxy.Update()
      assert.is_nil(proxy(2, 1):GetAttribute("type"))
      assert.is_nil(proxy(2, 1):GetAttribute("macrotext"))
    end)

    it("only re-writes an attribute whose value changed", function()
      gearBars = { { bindIndex = 1, slots = { { slotId = 13 } } } }
      keyBindProxy.Setup()
      local writesAfterSetup = proxy(1, 1).attributeWrites
      local untouchedWrites = proxy(3, 7).attributeWrites

      keyBindProxy.Update()
      keyBindProxy.Update()

      assert.are.equal(writesAfterSetup, proxy(1, 1).attributeWrites)
      assert.are.equal(untouchedWrites, proxy(3, 7).attributeWrites)
    end)

    it("defers a re-point during combat lockdown and applies it once on FlushPending", function()
      gearBars = { { bindIndex = 1, slots = { { slotId = 13 } } } }
      keyBindProxy.Setup()
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })

      gearBars[1].slots[1].slotId = 14
      keyBindProxy.Update()

      assert.is_true(keyBindProxy.HasPendingUpdate())
      assert.are.equal("/use 13", proxy(1, 1):GetAttribute("macrotext"))

      restoreCombat()
      local writesBeforeFlush = proxy(1, 1).attributeWrites
      keyBindProxy.FlushPending()

      assert.is_false(keyBindProxy.HasPendingUpdate())
      assert.are.equal("/use 14", proxy(1, 1):GetAttribute("macrotext"))
      -- type, macrotext and slotId were written once; a second flush changes nothing
      assert.are.equal(writesBeforeFlush + 3, proxy(1, 1).attributeWrites)
      keyBindProxy.FlushPending()
      assert.are.equal(writesBeforeFlush + 3, proxy(1, 1).attributeWrites)
    end)
  end)

  describe("OnProxyClick", function()
    it("forwards a key press on a proxy to the visible gearSlot at (bindIndex, position)", function()
      local slotOne, slotTwo = {}, {}
      gearBars = { { id = 10, bindIndex = 1, slots = { {}, {} } }, { id = 20, bindIndex = 2, slots = { {} } } }
      uiGearBars = { [10] = { gearSlotReferences = { slotOne, slotTwo } }, [20] = { gearSlotReferences = { {} } } }
      keyBindProxy.Setup()

      proxy(1, 2).scripts.PreClick(proxy(1, 2), "LeftButton", true)
      proxy(1, 2).scripts.PreClick(proxy(1, 2), "LeftButton", false)

      assert.are.same({
        { gearSlot = slotTwo, down = true },
        { gearSlot = slotTwo, down = false }
      }, keyPresses)
    end)

    it("does nothing for a proxy without a bar or a slot behind it", function()
      gearBars = { { id = 10, bindIndex = 1, slots = { {} } } }
      uiGearBars = { [10] = { gearSlotReferences = { {} } } }
      keyBindProxy.Setup()

      assert.has_no.errors(function()
        keyBindProxy.OnProxyClick(1, 2, "LeftButton", false)
        keyBindProxy.OnProxyClick(5, 1, "LeftButton", false)
      end)
      assert.are.same({}, keyPresses)
    end)
  end)

  describe("UpdateClickHandler", function()
    it("re-sets useOnKeyDown on every proxy when the fast-press option flips", function()
      keyBindProxy.Setup()
      fastPress = true

      keyBindProxy.UpdateClickHandler()

      assert.are.equal(true, proxy(1, 1):GetAttribute("useOnKeyDown"))
      assert.are.equal(true, proxy(5, 10):GetAttribute("useOnKeyDown"))
      assert.are.equal(true, proxy(MAX_BARS, MAX_SLOTS):GetAttribute("useOnKeyDown"))
    end)

    it("defers the update during combat lockdown and applies it on FlushPending", function()
      keyBindProxy.Setup()
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })
      fastPress = true

      keyBindProxy.UpdateClickHandler()
      assert.are.equal(false, proxy(1, 1):GetAttribute("useOnKeyDown"))

      restoreCombat()
      keyBindProxy.FlushPending()
      assert.are.equal(true, proxy(1, 1):GetAttribute("useOnKeyDown"))
    end)
  end)
end)
