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

-- luacheck: read globals CreateFrame STANDARD_TEXT_FONT

local mod = rggm
local me = {}
mod.generalMenu = me

me.tag = "GeneralMenu"

--[[
  Option texts for checkbutton options
]]--
local enableTooltipsMetaData = {
  "EnableTooltips",
  rggm.L["enable_tooltips"],
  rggm.L["enable_tooltips_tooltip"]
}

local enableSimpleTooltipsMetaData = {
  "EnableSimpleTooltips",
  rggm.L["enable_simple_tooltips"],
  rggm.L["enable_simple_tooltips_tooltip"]
}

local enableDragAndDropMetaData = {
  "EnableDragAndDrop",
  rggm.L["enable_drag_and_drop"],
  rggm.L["enable_drag_and_drop_tooltip"]
}

local enableFastPressMetaData = {
  "EnableFastPress",
  rggm.L["enable_fast_press"],
  rggm.L["enable_fast_press_tooltip"]
}

local enableUnequipSlotMetaData = {
  "EnableUnequipSlot",
  rggm.L["enable_unequip_slot"],
  rggm.L["enable_unequip_slot_tooltip"]
}

local enableFallbackToBaseItemMetaData = {
  "EnableFallbackToBaseItem",
  rggm.L["enable_fallback_to_base_item"],
  rggm.L["enable_fallback_to_base_item_tooltip"]
}

-- track whether the menu was already built
local builtMenu = false

--[[
  Build the ui for the general menu

  @param {table} parentFrame
    The addon configuration frame to attach to
]]--
function me.BuildUi(parentFrame)
  if builtMenu then return end

  me.CreateGeneralMenuTitle(parentFrame)

  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_TOOLTIPS,
    {"TOPLEFT", 20, -60},
    me.EnableTooltipsOnShow,
    me.EnableTooltipsOnClick,
    enableTooltipsMetaData
  )

  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_SIMPLE_TOOLTIPS,
    {"TOPLEFT", 20, -135},
    me.EnableSimpleTooltipsOnShow,
    me.EnableSimpleTooltipsOnClick,
    enableSimpleTooltipsMetaData
  )

  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_DRAG_AND_DROP,
    {"TOPLEFT", 20, -210},
    me.EnableDragAndDropOnShow,
    me.EnableDragAndDropOnClick,
    enableDragAndDropMetaData
  )

  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_FASTPRESS,
    {"TOPLEFT", 20, -285},
    me.EnableFastPressOnShow,
    me.EnableFastPressOnClick,
    enableFastPressMetaData
  )

  --[[
    From here on move options to "second row"
  ]]--
  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_UNEQUIP_SLOT,
    {"TOPLEFT", 280, -60},
    me.EnableUnequipSlotOnShow,
    me.EnableUnequipSlotOnClick,
    enableUnequipSlotMetaData
  )

  mod.uiHelper.BuildCheckButtonOption(
    parentFrame,
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_ENABLE_FALLBACK_TO_BASE_ITEM,
    {"TOPLEFT", 280, -135},
    me.EnableFallbackToBaseItemOnShow,
    me.EnableFallbackToBaseItemOnClick,
    enableFallbackToBaseItemMetaData
  )

  me.CreateItemQualityLabel(parentFrame)
  me.CreateItemQualityDropdown(parentFrame)

  builtMenu = true
end

--[[
  @param {table} contentFrame
]]--
function me.CreateGeneralMenuTitle(contentFrame)
  local titleFontString = contentFrame:CreateFontString(
    RGGM_CONSTANTS.ELEMENT_GENERAL_MENU_TITLE, "OVERLAY", "GameFontNormalLarge")
  titleFontString:SetPoint("TOPLEFT", 16, -16)
  mod.uiHelper.SetColor(titleFontString, RGGM_CONSTANTS.COLOR.TITLE_GOLD)
  titleFontString:SetText(rggm.L["options_title"])
end

--[[
  @param {table} frame
]]--
function me.CreateItemQualityLabel(frame)
  local filterItemQualityLabel = frame:CreateFontString(
    RGGM_CONSTANTS.ELEMENT_GENERAL_LABEL_FILTER_ITEM_QUALITY,
    "OVERLAY"
  )
  filterItemQualityLabel:SetPoint("TOPLEFT", 20, -360)
  filterItemQualityLabel:SetFont(STANDARD_TEXT_FONT, 15)
  mod.uiHelper.SetColor(filterItemQualityLabel, RGGM_CONSTANTS.COLOR.BODY)
  filterItemQualityLabel:SetText(rggm.L["filter_item_quality"])
end

--[[
  @param {table} frame
]]--
function me.CreateItemQualityDropdown(frame)
  local itemQualityDropdownMenu = mod.uiHelper.CreateSettingsDropdown(
    RGGM_CONSTANTS.ELEMENT_GENERAL_OPT_FILTER_ITEM_QUALITY,
    frame,
    {"TOPLEFT", 20, -380},
    170,
    me.InitializeItemQualityDropdownMenu
  )
  -- generate once so the button shows the current selection before the menu was ever opened
  itemQualityDropdownMenu:GenerateMenu()
end

--[[
  Menu generator for the item quality dropdown - fills the root description with a radio
  entry per filterable item quality

  @param {table} _
    The dropdown the menu is generated for (unused)
  @param {table} rootDescription
]]--
function me.InitializeItemQualityDropdownMenu(_, rootDescription)
  local itemQualities = {
    { value = RGGM_CONSTANTS.ITEMQUALITY.poor, text = rggm.L["item_quality_poor"] },
    { value = RGGM_CONSTANTS.ITEMQUALITY.common, text = rggm.L["item_quality_common"] },
    { value = RGGM_CONSTANTS.ITEMQUALITY.uncommon, text = rggm.L["item_quality_uncommon"] },
    { value = RGGM_CONSTANTS.ITEMQUALITY.rare, text = rggm.L["item_quality_rare"] },
    { value = RGGM_CONSTANTS.ITEMQUALITY.epic, text = rggm.L["item_quality_epic"] },
    { value = RGGM_CONSTANTS.ITEMQUALITY.legendary, text = rggm.L["item_quality_legendary"] }
  }

  for _, itemQuality in ipairs(itemQualities) do
    rootDescription:CreateHighlightRadio(
      itemQuality.text,
      me.IsItemQualitySelected,
      me.OnItemQualitySelect,
      itemQuality.value
    )
  end
end

--[[
  Whether the passed item quality is the currently configured filter

  @param {number} itemQuality

  @return {boolean}
]]--
function me.IsItemQualitySelected(itemQuality)
  return mod.configuration.GetFilterItemQuality() == itemQuality
end

--[[
  Callback for when an item quality is selected

  @param {number} itemQuality
    The selected item quality filter
]]--
function me.OnItemQualitySelect(itemQuality)
  mod.configuration.SetFilterItemQuality(itemQuality)
end

--[[
  OnShow callback for checkbuttons - enable tooltips

  @param {table} self
]]--
function me.EnableTooltipsOnShow(self)
  if mod.configuration.IsTooltipsEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable tooltips

  @param {table} self
]]--
function me.EnableTooltipsOnClick(self)
  local enabled = self:GetChecked()

  if enabled then
    mod.configuration.EnableTooltips()
  else
    mod.configuration.DisableTooltips()
  end
end

--[[
  OnShow callback for checkbuttons - enable simple tooltips

  @param {table} self
]]--
function me.EnableSimpleTooltipsOnShow(self)
  if mod.configuration.IsSimpleTooltipsEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable simple tooltips

  @param {table} self
]]--
function me.EnableSimpleTooltipsOnClick(self)
  local enabled = self:GetChecked()

  if enabled then
    mod.configuration.EnableSimpleTooltips()
  else
    mod.configuration.DisableSimpleTooltips()
  end
end

--[[
  OnShow callback for checkbuttons - enable drag and drop

  @param {table} self
]]--
function me.EnableDragAndDropOnShow(self)
  if mod.configuration.IsDragAndDropEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable drag and drop

  @param {table} self
]]--
function me.EnableDragAndDropOnClick(self)
  local enabled = self:GetChecked()

  if enabled then
    mod.configuration.EnableDragAndDrop()
  else
    mod.configuration.DisableDragAndDrop()
  end
end

--[[
  OnShow callback for checkbuttons - enable fastpress

  @param {table} self
]]--
function me.EnableFastPressOnShow(self)
  if mod.configuration.IsFastPressEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable fastpress

  @param {table} self
]]--
function me.EnableFastPressOnClick(self)
  local enabled = self:GetChecked()

  if enabled then
    mod.configuration.EnableFastPress()
  else
    mod.configuration.DisableFastPress()
  end
end

--[[
  OnShow callback for checkbuttons - enable unequipSlot

  @param {table} self
]]--
function me.EnableUnequipSlotOnShow(self)
  if mod.configuration.IsUnequipSlotEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable unequipSlot

  @param {table} self
]]--
function me.EnableUnequipSlotOnClick(self)
  local enabled = self:GetChecked()
  -- force checkbox to keep checked state until the user decided in the dialog what to do
  if enabled then
    mod.configuration.EnableUnequipSlot()
  else
    mod.configuration.DisableUnequipSlot()
  end
end

--[[
  OnShow callback for checkbuttons - enable fallback to base item

  @param {table} self
]]--
function me.EnableFallbackToBaseItemOnShow(self)
  if mod.configuration.IsFallbackToBaseItemEnabled() then
    self:SetChecked(true)
  else
    self:SetChecked(false)
  end
end

--[[
  OnClick callback for checkbuttons - enable fallback to base item

  @param {table} self
]]--
function me.EnableFallbackToBaseItemOnClick(self)
  local enabled = self:GetChecked()

  if enabled then
    mod.configuration.EnableFallbackToBaseItem()
  else
    mod.configuration.DisableFallbackToBaseItem()
  end
end
