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
  Spec for code/Configuration.lua's setup of the saved variables: SetupConfiguration with its
  defaults backfill (MergeDefaults) and per-bar nil-checks, and the addon version stamp.
  GearMenu Forever has no migration path - WoW Forever started without GearMenu saved variables -
  so a configuration stamped with an old version is only backfilled, never converted.

  The module is re-dofile'd in before_each (the isolation mechanism documented in
  test/headless/Bootstrap.lua) so file-local state starts fresh each test.

  GearMenuConfiguration is the saved-variables global the module reads and mutates. busted runs each
  spec chunk in a sandboxed environment, so a bareword assignment would land in the sandbox rather
  than the _G the dofile'd module sees -- fixtures are therefore installed via the useConfig helper
  (which writes _G.GearMenuConfiguration) and assertions run against the returned local handle.

  Collaborators reached via mod.* (logger, gearBarManager, gearManager) are replaced with recorder
  stubs and restored in after_each so the shared rggm namespace does not leak across specs. The
  addon metadata comes from wowStubs.install.
]]--

-- busted extends `assert` with .same / .equal / etc. at runtime; luacheck cannot verify those
-- fields statically. Suppress warning 143 (accessing undefined field of a global variable).
-- luacheck: globals describe it before_each after_each
-- luacheck: ignore 143

local wowStubs = require("WowStubs")

--[[
  Install a fixture as the saved-variables global and return it for assertions.

  @param {table} config
  @return {table}
]]--
local function useConfig(config)
  _G.GearMenuConfiguration = config
  return config
end

describe("Configuration setup", function()
  local configuration
  local previousModules
  local previousConfig
  local restore
  -- recorder state for the gearBarManager / gearManager collaborators
  local calls

  before_each(function()
    calls = {
      addGearBar = { count = 0, args = nil },
      gearSlotsRequested = {}
    }

    previousModules = {
      logger = rggm.logger,
      gearBarManager = rggm.gearBarManager,
      gearManager = rggm.gearManager
    }
    -- snapshot the global the setup mutates so it does not leak into other specs
    previousConfig = _G.GearMenuConfiguration

    -- silence the configuration logging
    rggm.logger = {
      LogDebug = function() end,
      LogInfo = function() end,
      LogError = function() end
    }
    -- AddGearBar mirrors the real GearBarManager.AddGearBar by appending to
    -- GearMenuConfiguration.gearBars
    rggm.gearBarManager = {
      AddGearBar = function(displayName, isLocked)
        calls.addGearBar.count = calls.addGearBar.count + 1
        calls.addGearBar.args = { displayName = displayName, isLocked = isLocked }
        local gearBar = { id = 1, slots = {} }
        table.insert(_G.GearMenuConfiguration.gearBars, gearBar)
        return gearBar
      end,
      -- SetupConfiguration backfills the per-bar bindIndex through this (covered by GearBarManagerSpec)
      EnsureBindIndices = function() end
    }
    -- GetGearSlotForSlotId returns a fresh gearSlot
    rggm.gearManager = {
      GetGearSlotForSlotId = function(slotId)
        calls.gearSlotsRequested[#calls.gearSlotsRequested + 1] = slotId
        return { slotId = slotId }
      end
    }

    restore = wowStubs.install({
      C_AddOns = wowStubs.stubs.C_AddOns({ Version = "v2.0.0" })
    })

    dofile("code/Configuration.lua")
    configuration = rggm.configuration
  end)

  after_each(function()
    restore()

    rggm.logger = previousModules.logger
    rggm.gearBarManager = previousModules.gearBarManager
    rggm.gearManager = previousModules.gearManager
    _G.GearMenuConfiguration = previousConfig
  end)

  describe("SetupConfiguration", function()
    -- SetupConfiguration backfills per-bar orientation / changeMenuDirection through the
    -- gearBarManager pure helpers. The outer before_each only stubs AddGearBar, so augment the
    -- stub with the two helpers (their own behaviour is covered by GearBarManagerSpec); the outer
    -- after_each restores the original module table.
    before_each(function()
      rggm.gearBarManager.IsChangeMenuDirectionValidForOrientation = function(direction, orientation)
        if orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
          return direction == RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_LEFT
            or direction == RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_RIGHT
        end

        return direction == RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_UP
          or direction == RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_DOWN
      end
      rggm.gearBarManager.GetDefaultChangeMenuDirection = function(orientation)
        if orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
          return RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_RIGHT
        end

        return RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_UP
      end
    end)

    it("backfills a nil orientation to horizontal", function()
      local config = useConfig({ gearBars = { { id = 1, slots = {} } } })

      configuration.SetupConfiguration()

      assert.are.equal(RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_HORIZONTAL, config.gearBars[1].orientation)
    end)

    -- gearBars is a userOwned collection, so the per-bar loop is the only backfill site for a
    -- per-bar field added in a later version
    it("backfills a nil per-bar visibility flag to visible", function()
      local config = useConfig({ gearBars = { { id = 1, slots = {} }, { id = 2, slots = {} } } })

      configuration.SetupConfiguration()

      assert.is_true(config.gearBars[1].isEnabled)
      assert.is_true(config.gearBars[2].isEnabled)
    end)

    it("preserves a stored hidden gearBar across setup", function()
      local config = useConfig({ gearBars = { { id = 1, slots = {}, isEnabled = false } } })

      configuration.SetupConfiguration()

      assert.is_false(config.gearBars[1].isEnabled)
    end)

    it("normalizes a now-invalid change menu direction to the orientation default", function()
      -- LEFT is invalid for a (backfilled) horizontal bar, so it resets to UP
      local config = useConfig({
        gearBars = { { id = 1, slots = {}, changeMenuDirection = RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_LEFT } }
      })

      configuration.SetupConfiguration()

      assert.are.equal(
        RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_UP, config.gearBars[1].changeMenuDirection)
    end)

    it("backfills a nil change menu direction to the orientation default", function()
      local config = useConfig({
        gearBars = { { id = 1, slots = {}, orientation = RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL } }
      })

      configuration.SetupConfiguration()

      assert.are.equal(
        RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_RIGHT, config.gearBars[1].changeMenuDirection)
    end)

    it("leaves a valid orientation / direction pair untouched", function()
      local config = useConfig({
        gearBars = {
          {
            id = 1,
            slots = {},
            orientation = RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL,
            changeMenuDirection = RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_LEFT
          }
        }
      })

      configuration.SetupConfiguration()

      assert.are.equal(RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL, config.gearBars[1].orientation)
      assert.are.equal(
        RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_LEFT, config.gearBars[1].changeMenuDirection)
    end)

    -- the defaults-backfill fixtures set firstTimeInitializationDone so SetAddonVersion does not
    -- run FirstTimeInitialization (its AddGearSlot/UpdateGearSlot collaborators are not stubbed)
    it("backfills a missing scalar field with its declared default", function()
      local config = useConfig({ firstTimeInitializationDone = true })

      configuration.SetupConfiguration()

      assert.is_true(config.enableTooltips)
      assert.are.equal(2, config.filterItemQuality)
      assert.are.same({}, config.gearBars)
    end)

    it("backfills a missing boolean false default as false, not merely truthy", function()
      local config = useConfig({ firstTimeInitializationDone = true })

      configuration.SetupConfiguration()

      assert.is_false(config.enableSimpleTooltips)
      assert.is_false(config.enableFastPress)
      assert.is_false(config.lockTrinketMenuFrame)
    end)

    it("preserves a saved false value for a field whose default is true", function()
      local config = useConfig({ firstTimeInitializationDone = true, enableTooltips = false })

      configuration.SetupConfiguration()

      assert.is_false(config.enableTooltips)
    end)

    it("leaves user-owned collection content untouched", function()
      local config = useConfig({
        firstTimeInitializationDone = true,
        profiles = { raid = { enableTooltips = false, filterItemQuality = 4 } },
        quickChangeRules = { { changeFromItemId = 1, changeToItemId = 2, delay = 0 } },
        frames = { GM_TrinketMenu = { point = "CENTER", posX = 5, posY = 10 } }
      })

      configuration.SetupConfiguration()

      assert.are.same({ raid = { enableTooltips = false, filterItemQuality = 4 } }, config.profiles)
      assert.are.same({ { changeFromItemId = 1, changeToItemId = 2, delay = 0 } }, config.quickChangeRules)
      assert.are.same({ GM_TrinketMenu = { point = "CENTER", posX = 5, posY = 10 } }, config.frames)
    end)

    it("produces the same effective configuration for a fresh install and an upgrade", function()
      local freshConfig = useConfig({ firstTimeInitializationDone = true })
      configuration.SetupConfiguration()

      -- an upgraded player carries some fields from the previous version; the rest are missing
      local upgradedConfig = useConfig({
        firstTimeInitializationDone = true,
        addonVersion = "v2.0.0",
        enableTooltips = true,
        filterItemQuality = 2
      })
      configuration.SetupConfiguration()

      assert.are.same(freshConfig, upgradedConfig)
    end)

    it("backfills each bar independently", function()
      local config = useConfig({
        gearBars = {
          { id = 1, slots = {} },
          {
            id = 2,
            slots = {},
            orientation = RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL,
            changeMenuDirection = RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_RIGHT
          }
        }
      })

      configuration.SetupConfiguration()

      assert.are.equal(RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_HORIZONTAL, config.gearBars[1].orientation)
      assert.are.equal(
        RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_UP, config.gearBars[1].changeMenuDirection)
      assert.are.equal(RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL, config.gearBars[2].orientation)
      assert.are.equal(
        RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_RIGHT, config.gearBars[2].changeMenuDirection)
    end)
  end)

  describe("MergeDefaults", function()
    it("fills a missing nested key while preserving present sibling values", function()
      local target = { window = { posX = 10 } }
      local defaults = { window = { posX = 0, posY = 0 }, scale = 1 }

      configuration.MergeDefaults(target, defaults)

      assert.are.equal(10, target.window.posX)
      assert.are.equal(0, target.window.posY)
      assert.are.equal(1, target.scale)
    end)

    it("treats false as a present value and never overwrites it", function()
      local target = { enabled = false }

      configuration.MergeDefaults(target, { enabled = true })

      assert.is_false(target.enabled)
    end)

    it("deep-copies a backfilled table so the defaults are never aliased", function()
      local target = {}
      local defaults = { window = { posX = 0 } }

      configuration.MergeDefaults(target, defaults)
      target.window.posX = 42

      assert.are.equal(0, defaults.window.posX)
    end)
  end)

  describe("SetAddonVersion", function()
    it("keeps a configuration stamped with a v1.x version intact apart from the new stamp", function()
      local frames = { GM_TrinketMenu = { point = "CENTER", relativePoint = "CENTER", posX = 1, posY = 2 } }
      local config = useConfig({
        addonVersion = "v1.6.0",
        firstTimeInitializationDone = true,
        gearBars = {},
        frames = frames
      })

      configuration.SetAddonVersion()

      assert.are.equal("v2.0.0", config.addonVersion)
      assert.are.equal(frames, config.frames)
      assert.are.equal(0, calls.addGearBar.count)
    end)

    it("leaves the frame position store a table after setting up a v1.x configuration", function()
      local config = useConfig({ addonVersion = "v1.0.0", firstTimeInitializationDone = true, gearBars = {} })

      configuration.SetupConfiguration()

      assert.is_table(config.frames)
    end)
  end)
end)
