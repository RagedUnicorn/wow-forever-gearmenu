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
  Spec for the general options page in gui/GeneralMenu.lua: which check buttons BuildUi wires to
  which OnShow / OnClick handlers, that each handler mirrors and writes the matching configuration
  toggle, and the item quality filter dropdown.

  The module indexes rggm.L at load time, so it is dofile'd per test with a localization table that
  echoes its keys. uiHelper and configuration are replaced by recorders; the layout itself (points,
  fonts, colors) is not asserted.
]]--

local wowStubs = require("WowStubs")

--[[
  The check button options in BuildUi order: element name, the configuration getter the OnShow
  handler mirrors and the enable / disable pair the OnClick handler calls
]]--
local CHECK_BUTTON_OPTIONS = {
  { "ELEMENT_GENERAL_OPT_ENABLE_TOOLTIPS", "EnableTooltips", "IsTooltipsEnabled", "Tooltips" },
  {
    "ELEMENT_GENERAL_OPT_ENABLE_SIMPLE_TOOLTIPS", "EnableSimpleTooltips", "IsSimpleTooltipsEnabled",
    "SimpleTooltips"
  },
  { "ELEMENT_GENERAL_OPT_ENABLE_DRAG_AND_DROP", "EnableDragAndDrop", "IsDragAndDropEnabled", "DragAndDrop" },
  { "ELEMENT_GENERAL_OPT_ENABLE_FASTPRESS", "EnableFastPress", "IsFastPressEnabled", "FastPress" },
  { "ELEMENT_GENERAL_OPT_ENABLE_UNEQUIP_SLOT", "EnableUnequipSlot", "IsUnequipSlotEnabled", "UnequipSlot" },
  {
    "ELEMENT_GENERAL_OPT_ENABLE_FALLBACK_TO_BASE_ITEM", "EnableFallbackToBaseItem",
    "IsFallbackToBaseItemEnabled", "FallbackToBaseItem"
  }
}

--[[
  A fake check button that keeps its checked state

  @param {boolean} checked

  @return {table}
]]--
local function CreateFakeCheckButton(checked)
  local checkButton = { checked = checked }

  function checkButton:SetChecked(value)
    self.checked = value
  end

  function checkButton:GetChecked()
    return self.checked
  end

  return checkButton
end

--[[
  A fake parent frame whose font strings accept every layout call

  @return {table}
]]--
local function CreateFakeParentFrame()
  local fontString = setmetatable({}, { __index = function() return function() end end })

  return {
    CreateFontString = function() return fontString end
  }
end

describe("GeneralMenu", function()
  local menu
  local calls
  -- configuration state the recorder getters answer from
  local enabled
  local filterItemQuality
  local previous
  local restore

  before_each(function()
    calls = {
      checkButtons = {},   -- uiHelper.BuildCheckButtonOption(parent, name, position, onShow, onClick, metaData)
      dropdowns = {},      -- uiHelper.CreateSettingsDropdown(name, parent, position, width, generator)
      generatedMenus = 0,  -- dropdown:GenerateMenu()
      configuration = {}   -- configuration.<Enable|Disable>*()
    }
    enabled = {}
    filterItemQuality = RGGM_CONSTANTS.ITEMQUALITY.common

    previous = {
      generalMenu = rggm.generalMenu,
      uiHelper = rggm.uiHelper,
      configuration = rggm.configuration,
      L = rggm.L
    }

    rggm.L = setmetatable({}, { __index = function(_, key) return key end })

    rggm.uiHelper = {
      SetColor = function() end,
      BuildCheckButtonOption = function(parent, name, _, onShow, onClick, metaData)
        calls.checkButtons[#calls.checkButtons + 1] = {
          parent = parent, name = name, onShow = onShow, onClick = onClick, metaData = metaData
        }
      end,
      CreateSettingsDropdown = function(name, parent, _, _, generator)
        calls.dropdowns[#calls.dropdowns + 1] = { name = name, parent = parent, generator = generator }

        return {
          GenerateMenu = function() calls.generatedMenus = calls.generatedMenus + 1 end
        }
      end
    }

    rggm.configuration = setmetatable({
      GetFilterItemQuality = function() return filterItemQuality end,
      SetFilterItemQuality = function(itemQuality) filterItemQuality = itemQuality end
    }, {
      __index = function(configuration, functionName)
        local stub

        if functionName:find("^Is") then
          stub = function() return enabled[functionName] == true end
        else
          stub = function() calls.configuration[#calls.configuration + 1] = functionName end
        end

        rawset(configuration, functionName, stub)

        return stub
      end
    })

    restore = wowStubs.install({ STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF" })

    dofile("gui/GeneralMenu.lua")
    menu = rggm.generalMenu
  end)

  after_each(function()
    restore()

    for name, value in pairs(previous) do
      rggm[name] = value
    end
  end)

  describe("BuildUi", function()
    it("wires every check button option to its OnShow and OnClick handler", function()
      local parent = CreateFakeParentFrame()

      menu.BuildUi(parent)

      assert.are.equal(#CHECK_BUTTON_OPTIONS, #calls.checkButtons)

      for index, option in ipairs(CHECK_BUTTON_OPTIONS) do
        local checkButton = calls.checkButtons[index]

        assert.are.equal(parent, checkButton.parent)
        assert.are.equal(RGGM_CONSTANTS[option[1]], checkButton.name)
        assert.are.equal(menu[option[2] .. "OnShow"], checkButton.onShow)
        assert.are.equal(menu[option[2] .. "OnClick"], checkButton.onClick)
        assert.are.equal(option[2], checkButton.metaData[1])
      end
    end)

    it("builds the item quality dropdown and generates it once to show the current selection", function()
      local parent = CreateFakeParentFrame()

      menu.BuildUi(parent)

      assert.are.equal(1, #calls.dropdowns)
      assert.are.equal(RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_FILTER_ITEM_QUALITY, calls.dropdowns[1].name)
      assert.are.equal(parent, calls.dropdowns[1].parent)
      assert.are.equal(menu.InitializeItemQualityDropdownMenu, calls.dropdowns[1].generator)
      assert.are.equal(1, calls.generatedMenus)
    end)

    it("builds the page only once", function()
      menu.BuildUi(CreateFakeParentFrame())
      menu.BuildUi(CreateFakeParentFrame())

      assert.are.equal(#CHECK_BUTTON_OPTIONS, #calls.checkButtons)
      assert.are.equal(1, #calls.dropdowns)
    end)
  end)

  describe("check button handlers", function()
    for _, option in ipairs(CHECK_BUTTON_OPTIONS) do
      local handler, getter, toggle = option[2], option[3], option[4]

      it(handler .. "OnShow mirrors " .. getter, function()
        local checkButton = CreateFakeCheckButton(nil)

        enabled[getter] = true
        menu[handler .. "OnShow"](checkButton)
        assert.is_true(checkButton.checked)

        enabled[getter] = false
        menu[handler .. "OnShow"](checkButton)
        assert.is_false(checkButton.checked)
      end)

      it(handler .. "OnClick enables or disables " .. toggle, function()
        menu[handler .. "OnClick"](CreateFakeCheckButton(true))
        menu[handler .. "OnClick"](CreateFakeCheckButton(false))

        assert.are.same({ "Enable" .. toggle, "Disable" .. toggle }, calls.configuration)
      end)
    end
  end)

  describe("item quality dropdown", function()
    local function generate()
      local entries = {}
      local rootDescription = {
        CreateHighlightRadio = function(_, text, isSelected, onSelect, value)
          entries[#entries + 1] = { text = text, isSelected = isSelected, onSelect = onSelect, value = value }
        end
      }

      menu.InitializeItemQualityDropdownMenu(nil, rootDescription)

      return entries
    end

    it("offers one radio entry per item quality from poor to legendary", function()
      local entries = generate()
      local values = {}

      for index, entry in ipairs(entries) do
        values[index] = entry.value
        assert.are.equal(menu.IsItemQualitySelected, entry.isSelected)
        assert.are.equal(menu.OnItemQualitySelect, entry.onSelect)
      end

      local quality = RGGM_CONSTANTS.ITEMQUALITY

      assert.are.same(
        { quality.poor, quality.common, quality.uncommon, quality.rare, quality.epic, quality.legendary },
        values
      )
      assert.are.equal("item_quality_poor", entries[1].text)
      assert.are.equal("item_quality_legendary", entries[6].text)
    end)

    it("marks only the configured filter as selected", function()
      filterItemQuality = RGGM_CONSTANTS.ITEMQUALITY.rare

      assert.is_true(menu.IsItemQualitySelected(RGGM_CONSTANTS.ITEMQUALITY.rare))
      assert.is_false(menu.IsItemQualitySelected(RGGM_CONSTANTS.ITEMQUALITY.epic))
    end)

    it("stores the selected quality as the new filter", function()
      menu.OnItemQualitySelect(RGGM_CONSTANTS.ITEMQUALITY.epic)

      assert.are.equal(RGGM_CONSTANTS.ITEMQUALITY.epic, filterItemQuality)
      assert.is_true(menu.IsItemQualitySelected(RGGM_CONSTANTS.ITEMQUALITY.epic))
    end)
  end)
end)
