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
  Spec for gui/KeyBind.lua - the binding reads and writes against the proxy actions of
  gui/KeyBindProxy.lua, with WoW's binding set as the source of truth. Covers the label /
  mirror refresh (RefreshKeyBindingLabels / OnUpdateKeyBindings), unbinding a slot, the key
  shift after a slot removal, clearing a removed bar, the profile clear / apply pair and the
  combat deferral queue every write goes through (WhenOutOfCombat / FlushPending).

  The binding globals come from the in-memory BindingSet stub, whose SetBinding refuses while the
  InCombatLockdown stub reports combat - the client's protected-action behaviour. The real
  gui/KeyBindProxy.lua is loaded for the action strings (its CreateFrame is never reached);
  gearBarManager, gearBar, gearBarConfigurationSubMenu and logger are recorder stubs.
]]--

local wowStubs = require("WowStubs")

local function action(bindIndex, position)
  return string.format("CLICK GM_KeyBindBar%dSlot%d:LeftButton", bindIndex, position)
end

describe("KeyBind", function()
  local keyBind
  local previous
  local restore
  local bindingSet
  local gearBars
  local calls

  --[[
    Install a fresh binding set stub (replacing the one installed in before_each)

    @param {table} initial
      key -> action map
    @param {table} refusedKeys
  ]]--
  local function useBindingSet(initial, refusedKeys)
    bindingSet = wowStubs.stubs.BindingSet(initial, refusedKeys)
    wowStubs.install(bindingSet.globals)
  end

  before_each(function()
    gearBars = {}
    calls = {
      labelUpdates = 0,     -- gearBar.UpdateGearBars(UpdateKeyBindingState)
      configUpdates = 0,    -- gearBarConfigurationSubMenu.UpdateGearBarConfigurationMenu()
      userMessages = {},    -- logger.PrintUserMessage(msg)
      userErrors = {},      -- logger.PrintUserError(msg)
      warnings = 0          -- logger.LogWarn
    }

    previous = {
      keyBind = rggm.keyBind,
      keyBindProxy = rggm.keyBindProxy,
      gearBarManager = rggm.gearBarManager,
      gearBar = rggm.gearBar,
      gearBarConfigurationSubMenu = rggm.gearBarConfigurationSubMenu,
      configuration = rggm.configuration,
      logger = rggm.logger,
      L = rggm.L
    }

    rggm.L = setmetatable({
      keybind_deferred_combat = "deferred",
      keybind_set_failed = "failed %s"
    }, { __index = function(_, key) return key end })

    rggm.gearBarManager = {
      GetGearBars = function() return gearBars end,
      GetGearBar = function(id)
        for _, gearBar in ipairs(gearBars) do
          if gearBar.id == id then return gearBar end
        end
        return nil
      end,
      SetSlotKeyBinding = function(id, position, key)
        rggm.gearBarManager.GetGearBar(id).slots[position].keyBinding = key
      end
    }
    rggm.gearBar = {
      UpdateGearBars = function() calls.labelUpdates = calls.labelUpdates + 1 end,
      UpdateKeyBindingState = function() end
    }
    rggm.gearBarConfigurationSubMenu = {
      UpdateGearBarConfigurationMenu = function() calls.configUpdates = calls.configUpdates + 1 end
    }
    rggm.configuration = {
      IsFastPressEnabled = function() return false end
    }
    rggm.logger = {
      LogDebug = function() end,
      LogInfo = function() end,
      LogWarn = function() calls.warnings = calls.warnings + 1 end,
      LogError = function() end,
      PrintUserMessage = function(msg) calls.userMessages[#calls.userMessages + 1] = msg end,
      PrintUserError = function(msg) calls.userErrors[#calls.userErrors + 1] = msg end
    }

    bindingSet = wowStubs.stubs.BindingSet({})
    local stubs = { InCombatLockdown = wowStubs.stubs.InCombatLockdown(false) }
    for name, value in pairs(bindingSet.globals) do stubs[name] = value end
    restore = wowStubs.install(stubs)

    dofile("gui/KeyBindProxy.lua")
    dofile("gui/KeyBind.lua")
    keyBind = rggm.keyBind
  end)

  after_each(function()
    restore()

    rggm.keyBind = previous.keyBind
    rggm.keyBindProxy = previous.keyBindProxy
    rggm.gearBarManager = previous.gearBarManager
    rggm.gearBar = previous.gearBar
    rggm.gearBarConfigurationSubMenu = previous.gearBarConfigurationSubMenu
    rggm.configuration = previous.configuration
    rggm.logger = previous.logger
    rggm.L = previous.L
  end)

  describe("GetSlotKeyBinding / GetSlotKeys", function()
    it("reads the keys bound to the proxy action of the slot", function()
      useBindingSet({ ["F1"] = action(2, 3), ["SHIFT-F1"] = action(2, 3) })
      local gearBar = { id = 7, bindIndex = 2, slots = { {}, {}, {} } }

      assert.are.equal("F1", keyBind.GetSlotKeyBinding(gearBar, 3))
      assert.are.same({ "F1", "SHIFT-F1" }, { keyBind.GetSlotKeys(gearBar, 3) })
      assert.is_nil(keyBind.GetSlotKeyBinding(gearBar, 1))
    end)

    it("returns nil for a bar without a bindIndex", function()
      useBindingSet({ ["F1"] = action(1, 1) })

      assert.is_nil(keyBind.GetSlotKeyBinding({ id = 7, slots = { {} } }, 1))
      assert.is_nil(keyBind.GetSlotKeyBinding(nil, 1))
    end)
  end)

  describe("RefreshKeyBindingLabels / OnUpdateKeyBindings", function()
    it("mirrors the primary key of every slot from the binding set and refreshes the labels", function()
      -- the stub reports keys in sorted order, so F1 is the primary key of (1, 1)
      useBindingSet({
        ["F1"] = action(1, 1),
        ["SHIFT-F1"] = action(1, 1),
        ["F3"] = action(3, 2),
        ["P"] = "TOGGLEWORLDMAP"
      })
      gearBars = {
        { id = 10, bindIndex = 1, slots = { { keyBinding = "STALE" }, { keyBinding = "STALE" } } },
        { id = 30, bindIndex = 3, slots = { {}, {} } }
      }

      keyBind.OnUpdateKeyBindings()

      assert.are.equal("F1", gearBars[1].slots[1].keyBinding)
      assert.is_nil(gearBars[1].slots[2].keyBinding)
      assert.is_nil(gearBars[2].slots[1].keyBinding)
      assert.are.equal("F3", gearBars[2].slots[2].keyBinding)
      assert.are.equal(1, calls.labelUpdates)
      assert.are.equal(1, calls.configUpdates)
    end)
  end)

  describe("UnsetKeyBinding", function()
    it("clears both keys of the slot, saves once and refreshes", function()
      useBindingSet({ ["F1"] = action(1, 2), ["ALT-F1"] = action(1, 2), ["F2"] = action(1, 1) })
      gearBars = { { id = 10, bindIndex = 1, slots = { { keyBinding = "F2" }, { keyBinding = "F1" } } } }

      keyBind.UnsetKeyBinding(10, 2)

      assert.are.same({}, bindingSet.GetKeys(action(1, 2)))
      assert.are.same({ "F2" }, bindingSet.GetKeys(action(1, 1)))
      assert.are.equal(1, bindingSet.savedCount)
      assert.is_nil(gearBars[1].slots[2].keyBinding)
      assert.are.equal("F2", gearBars[1].slots[1].keyBinding)
    end)

    it("does not save when the slot had no key", function()
      useBindingSet({})
      gearBars = { { id = 10, bindIndex = 1, slots = { {} } } }

      keyBind.UnsetKeyBinding(10, 1)

      assert.are.equal(0, bindingSet.savedCount)
      assert.are.equal(1, calls.labelUpdates)
    end)

    it("ignores an unknown slot", function()
      useBindingSet({ ["F1"] = action(1, 1) })
      gearBars = { { id = 10, bindIndex = 1, slots = { {} } } }

      keyBind.UnsetKeyBinding(10, 5)
      keyBind.UnsetKeyBinding(99, 1)

      assert.are.same({ "F1" }, bindingSet.GetKeys(action(1, 1)))
      assert.are.equal(0, bindingSet.savedCount)
    end)
  end)

  describe("OnGearSlotRemoved", function()
    it("moves the keys of the slots after the removed position up by one and saves once", function()
      useBindingSet({
        ["F1"] = action(1, 1),
        ["F2"] = action(1, 2),
        ["F3"] = action(1, 3),
        ["ALT-F3"] = action(1, 3),
        ["F4"] = action(1, 4)
      })
      -- slot 2 was already removed from the configuration; three slots remain
      gearBars = { { id = 10, bindIndex = 1, slots = { {}, {}, {} } } }

      keyBind.OnGearSlotRemoved(10, 2)

      assert.are.same({ "F1" }, bindingSet.GetKeys(action(1, 1)))
      assert.are.same({ "ALT-F3", "F3" }, bindingSet.GetKeys(action(1, 2)))
      assert.are.same({ "F4" }, bindingSet.GetKeys(action(1, 3)))
      assert.are.same({}, bindingSet.GetKeys(action(1, 4)))
      assert.is_nil(bindingSet.actions["F2"])
      assert.are.equal(1, bindingSet.savedCount)
      assert.are.equal("F1", gearBars[1].slots[1].keyBinding)
      assert.are.equal("ALT-F3", gearBars[1].slots[2].keyBinding)
      assert.are.equal("F4", gearBars[1].slots[3].keyBinding)
    end)

    it("clears the key of the last slot when it is the one removed", function()
      useBindingSet({ ["F1"] = action(1, 1), ["F2"] = action(1, 2) })
      gearBars = { { id = 10, bindIndex = 1, slots = { {} } } }

      keyBind.OnGearSlotRemoved(10, 2)

      assert.are.same({ "F1" }, bindingSet.GetKeys(action(1, 1)))
      assert.are.same({}, bindingSet.GetKeys(action(1, 2)))
      assert.are.equal(1, bindingSet.savedCount)
    end)

    it("leaves other bars alone and does not save when nothing was bound", function()
      useBindingSet({ ["F1"] = action(2, 1) })
      gearBars = { { id = 10, bindIndex = 1, slots = { {} } }, { id = 20, bindIndex = 2, slots = { {} } } }

      keyBind.OnGearSlotRemoved(10, 1)

      assert.are.same({ "F1" }, bindingSet.GetKeys(action(2, 1)))
      assert.are.equal(0, bindingSet.savedCount)
    end)
  end)

  describe("OnGearBarRemoved", function()
    it("clears every key of the bindIndex and saves once", function()
      useBindingSet({ ["F1"] = action(2, 1), ["F2"] = action(2, 20), ["F3"] = action(1, 1) })

      keyBind.OnGearBarRemoved(2)

      assert.is_nil(bindingSet.actions["F1"])
      assert.is_nil(bindingSet.actions["F2"])
      assert.are.equal(action(1, 1), bindingSet.actions["F3"])
      assert.are.equal(1, bindingSet.savedCount)
    end)

    it("ignores a nil bindIndex", function()
      useBindingSet({ ["F1"] = action(2, 1) })

      keyBind.OnGearBarRemoved(nil)

      assert.are.equal(action(2, 1), bindingSet.actions["F1"])
      assert.are.equal(0, bindingSet.savedCount)
    end)
  end)

  describe("ClearGearBarKeyBindings", function()
    it("clears every GearMenu proxy action and leaves foreign actions alone", function()
      useBindingSet({
        ["F1"] = action(1, 1),
        ["F2"] = action(10, 20),
        ["P"] = "TOGGLEWORLDMAP",
        ["T"] = "CLICK SomeOtherAddonButton:LeftButton"
      })

      keyBind.ClearGearBarKeyBindings()

      assert.are.same({ P = "TOGGLEWORLDMAP", T = "CLICK SomeOtherAddonButton:LeftButton" }, bindingSet.actions)
      assert.are.equal(1, bindingSet.savedCount)
    end)

    it("does not save when nothing was bound", function()
      useBindingSet({ ["P"] = "TOGGLEWORLDMAP" })

      keyBind.ClearGearBarKeyBindings()

      assert.are.equal(0, bindingSet.savedCount)
    end)
  end)

  describe("ApplyGearBarKeyBindings", function()
    it("binds every slot keyBinding to its proxy action, saves once and refreshes", function()
      useBindingSet({})
      gearBars = {
        { id = 3, bindIndex = 1, slots = { [1] = { keyBinding = "T" }, [2] = { keyBinding = nil } } },
        { id = 7, bindIndex = 4, slots = { [1] = { keyBinding = "CTRL-Q" }, [2] = { keyBinding = "" } } }
      }

      keyBind.ApplyGearBarKeyBindings()

      assert.are.same({ T = action(1, 1), ["CTRL-Q"] = action(4, 1) }, bindingSet.actions)
      assert.are.equal(1, bindingSet.savedCount)
      assert.are.equal(1, calls.labelUpdates)
    end)

    it("skips a bar without a bindIndex and does not save when nothing was bound", function()
      useBindingSet({})
      gearBars = { { id = 3, slots = { [1] = { keyBinding = "T" } } } }

      keyBind.ApplyGearBarKeyBindings()

      assert.are.same({}, bindingSet.actions)
      assert.are.equal(0, bindingSet.savedCount)
    end)

    it("reports a key the client refuses and binds the rest", function()
      useBindingSet({}, { ["BAD"] = true })
      gearBars = { { id = 3, bindIndex = 1, slots = { { keyBinding = "BAD" }, { keyBinding = "F2" } } } }

      keyBind.ApplyGearBarKeyBindings()

      assert.are.same({ F2 = action(1, 2) }, bindingSet.actions)
      assert.are.equal(1, calls.warnings)
      assert.are.same({ "failed BAD" }, calls.userErrors)
      assert.are.equal(1, bindingSet.savedCount)
    end)

    it("skips malformed slots instead of raising and binds the well-formed ones", function()
      useBindingSet({})
      gearBars = {
        { id = 3, bindIndex = 1, slots = {
          [1] = { keyBinding = 42 },
          [2] = "F3",
          [3] = { keyBinding = "F4" },
          first = { keyBinding = "F5" },
          [RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS + 1] = { keyBinding = "F6" }
        } },
        { id = 7, bindIndex = 2, slots = "x" }
      }

      keyBind.ApplyGearBarKeyBindings()

      assert.are.same({ F4 = action(1, 3) }, bindingSet.actions)
      assert.are.equal(1, bindingSet.savedCount)
    end)
  end)

  describe("combat deferral", function()
    it("runs a write immediately out of combat", function()
      local ran = 0

      local immediate = keyBind.WhenOutOfCombat(function() ran = ran + 1 end)

      assert.is_true(immediate)
      assert.are.equal(1, ran)
      assert.is_false(keyBind.HasPendingWrites())
    end)

    it("queues writes during combat lockdown, tells the user once and flushes them in order", function()
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })
      local order = {}

      local first = keyBind.WhenOutOfCombat(function() order[#order + 1] = "first" end)
      keyBind.WhenOutOfCombat(function() order[#order + 1] = "second" end)
      keyBind.FlushPending() -- still in combat: nothing runs

      assert.is_false(first)
      assert.is_true(keyBind.HasPendingWrites())
      assert.are.same({}, order)
      assert.are.same({ "deferred" }, calls.userMessages)

      restoreCombat()
      keyBind.FlushPending()

      assert.are.same({ "first", "second" }, order)
      assert.is_false(keyBind.HasPendingWrites())
    end)

    it("announces the deferral again in a later combat", function()
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })
      keyBind.WhenOutOfCombat(function() end)
      restoreCombat()
      keyBind.FlushPending()

      restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })
      keyBind.WhenOutOfCombat(function() end)
      restoreCombat()

      assert.are.equal(2, #calls.userMessages)
    end)

    it("issues no binding call in combat and performs the unbind on PLAYER_REGEN_ENABLED", function()
      useBindingSet({ ["F1"] = action(1, 1) })
      gearBars = { { id = 10, bindIndex = 1, slots = { { keyBinding = "F1" } } } }
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })

      keyBind.UnsetKeyBinding(10, 1)

      assert.are.equal(action(1, 1), bindingSet.actions["F1"])
      assert.are.equal(0, bindingSet.savedCount)
      assert.are.equal(0, calls.labelUpdates)

      restoreCombat()
      keyBind.FlushPending()

      assert.is_nil(bindingSet.actions["F1"])
      assert.are.equal(1, bindingSet.savedCount)
      assert.are.equal(1, calls.labelUpdates)
      assert.is_nil(gearBars[1].slots[1].keyBinding)
    end)

    it("defers a profile clear and apply in the order they were requested", function()
      useBindingSet({ ["F1"] = action(1, 1) })
      gearBars = { { id = 10, bindIndex = 1, slots = { { keyBinding = "F5" } } } }
      local restoreCombat = wowStubs.install({ InCombatLockdown = wowStubs.stubs.InCombatLockdown(true) })

      keyBind.ClearGearBarKeyBindings()
      keyBind.ApplyGearBarKeyBindings()

      assert.are.equal(action(1, 1), bindingSet.actions["F1"])

      restoreCombat()
      keyBind.FlushPending()

      assert.are.same({ F5 = action(1, 1) }, bindingSet.actions)
      assert.are.equal(2, bindingSet.savedCount)
    end)
  end)

  describe("ConvertKeyBindingText", function()
    it("shortens the modifier names", function()
      assert.are.equal("c-s-a-f1", keyBind.ConvertKeyBindingText("CTRL-SHIFT-ALT-F1"))
    end)
  end)
end)
