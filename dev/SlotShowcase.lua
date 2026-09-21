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

--[[
  Development-only slot showcase. Loaded by the development .toc only - it must never
  ship in a release. `/rggm showcase` toggles a window that renders every state a slot
  can be in - an item, the empty slot with its default icon, hover, pushed, a running
  cooldown, a bound key, a queued item, the Quick Keybind Mode highlight and an old item
  icon with its built-in black corners - at the 24, 40 and 64 px slot sizes. Every
  GearMenu slot sits next to a real Blizzard action button (ActionButtonTemplate) scaled
  to the same size and put into the same state, so the look can be judged side by side
  without owning the items or waiting for a cooldown.

  The GearMenu slots are built from the production pieces (gui/UiHelper.lua
  CreateItemTexture, gui/GearBar.lua CreateCombatQueueSlot / CreateKeyBindingText,
  gui/SlotStyle.lua ApplySlotStyle, gui/Cooldown.lua CreateCooldownOverlay) so what the
  window shows is what a gearSlot renders - minus the secure click handling.

  Registers a `showcase` sub-command on the production command registry (code/Cmd.lua)
  without a help text key, so it never shows up in /rggm help.
]]--

-- luacheck: globals CreateFrame UIParent GetTime UISpecialFrames INVSLOT_HEAD

local mod = rggm
local me = {}
mod.slotShowcase = me

me.tag = "SlotShowcase"

local SLOT_SIZES = { 24, 40, 64 }
-- ActionButtonTemplate is drawn for a 45 px button; the reference is scaled down / up from that
local BLIZZARD_BUTTON_SIZE = 45
-- the icon padding of an action bar (Blizzard_ActionBar/Shared/ActionBar.lua minButtonPadding)
local BLIZZARD_BUTTON_PADDING = 2
-- the spacing strips below the grid: four buttons at the default slot size
local STRIP_SLOT_SIZE = 40
local STRIP_SLOT_COUNT = 4
local ITEM_ICON = "Interface\\Icons\\INV_Chest_Cloth_07"
local QUEUED_ITEM_ICON = "Interface\\Icons\\INV_Chest_Leather_03"
-- an icon of the 2004 generation: art drawn diagonally over a black background and a dark border ring
local OLD_ITEM_ICON = "Interface\\Icons\\INV_Boots_05"
local KEY_BINDING_TEXT = "s-q"
-- a cooldown that is already 45 seconds into its 2 minutes when the window opens
local COOLDOWN_ELAPSED = 45
local COOLDOWN_DURATION = 120

local WINDOW_NAME = "GM_SlotShowcase"
local PADDING = 16
local TITLE_HEIGHT = 30
local HEADER_HEIGHT = 24
local LABEL_WIDTH = 170
local COLUMN_WIDTH = 72
local COLUMN_GAP = 8
local ROW_HEIGHT = 64 + 12

local window

--[[
  Look up the hotkey font string of a Blizzard action button - the template keeps it
  inside its TextOverlayContainer, the mixin mirrors it onto the button

  @param {table} button

  @return {table | nil}
]]--
local function GetBlizzardHotKey(button)
  if button.HotKey ~= nil then
    return button.HotKey
  end

  if button.TextOverlayContainer ~= nil then
    return button.TextOverlayContainer.HotKey
  end

  return nil
end

--[[
  The showcased states, one row each. `icon` overrides the item icon of the row, `slot`
  and `blizzard` put the GearMenu slot respectively the Blizzard reference into the state.
  Rows without a `blizzard` step have no Blizzard equivalent (the reference shows the item).
]]--
local STATES = {
  {
    label = "Item"
  }, {
    label = "Empty slot (default icon)",
    icon = mod.gearManager.GetGearSlotForSlotId(INVSLOT_HEAD).textureId,
    blizzard = function(button)
      -- an empty action button shows its slot art instead of an icon
      button.icon:Hide()
    end
  }, {
    label = "Hover",
    slot = function(slot)
      slot:LockHighlight()
    end,
    blizzard = function(button)
      button:LockHighlight()
    end
  }, {
    label = "Pushed",
    slot = function(slot)
      slot:SetButtonState("PUSHED", true)
    end,
    blizzard = function(button)
      button:SetButtonState("PUSHED", true)
    end
  }, {
    label = "Cooldown",
    slot = function(slot)
      slot.cooldownOverlay:SetCooldown(GetTime() - COOLDOWN_ELAPSED, COOLDOWN_DURATION)
    end,
    blizzard = function(button)
      button.cooldown:SetCooldown(GetTime() - COOLDOWN_ELAPSED, COOLDOWN_DURATION)
    end
  }, {
    label = "Bound key",
    slot = function(slot)
      slot.keyBindingText:SetText(KEY_BINDING_TEXT)
      slot.keyBindingText:Show()
    end,
    blizzard = function(button)
      local hotKey = GetBlizzardHotKey(button)

      if hotKey ~= nil then
        hotKey:SetText(KEY_BINDING_TEXT)
        hotKey:Show()
      end
    end
  }, {
    label = "Queued item",
    slot = function(slot)
      slot.combatQueueSlot.icon:SetTexture(QUEUED_ITEM_ICON)
      slot.combatQueueSlot:Show()
    end
  }, {
    label = "Right click (queue dropped)",
    slot = function(slot)
      -- the flash SlotStyle.FlashSlot shows for a moment, held permanently here
      local color = RGGM_CONSTANTS.COLOR.QUEUE_REMOVED

      slot.flashTexture:SetVertexColor(color[1], color[2], color[3])
      slot.flashTexture:Show()
    end
  }, {
    label = "Quick Keybind Mode",
    slot = function(slot)
      slot.QuickKeybindHighlightTexture:Show()
    end,
    blizzard = function(button)
      button.QuickKeybindHighlightTexture:Show()
    end
  }, {
    label = "Old item icon (black corners)",
    icon = OLD_ITEM_ICON
  }
}

--[[
  Build a GearMenu slot exactly like gui/SlotStyle.lua CreateGearSlot does, minus the
  secure template and the event handlers. The Quick Keybind Mode highlight normally comes
  from the QuickKeybindButtonTemplate; it is recreated by hand so the style lays it out

  @param {table} parent
  @param {number} slotSize
  @param {number} index
    Unique per showcase slot - the child frames derive their global names from the slot's

  @return {table}
]]--
local function CreateShowcaseSlot(parent, slotSize, index)
  local slot = CreateFrame("Button", WINDOW_NAME .. "Slot" .. index, parent)
  slot:SetSize(slotSize, slotSize)
  slot:EnableMouse(false)

  mod.uiHelper.CreateItemTexture(slot)
  slot.combatQueueSlot = mod.gearBar.CreateCombatQueueSlot(slot, slotSize)
  slot.keyBindingText = mod.gearBar.CreateKeyBindingText(slot, slotSize)

  slot.QuickKeybindHighlightTexture = slot:CreateTexture(nil, "OVERLAY")
  slot.QuickKeybindHighlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
  slot.QuickKeybindHighlightTexture:SetBlendMode("ADD")
  slot.QuickKeybindHighlightTexture:SetAlpha(0.4)
  slot.QuickKeybindHighlightTexture:Hide()

  mod.slotStyle.ApplySlotStyle(slot, slotSize)
  slot.cooldownOverlay = mod.cooldown.CreateCooldownOverlay(
    slot,
    RGGM_CONSTANTS.ELEMENT_SLOT_COOLDOWN_FRAME,
    slotSize
  )

  return slot
end

--[[
  Build a Blizzard action button as the reference. The template's OnLoad dresses it as a
  button off a bar (the AddRow art), so the bar art is put on afterwards the way
  Blizzard_ActionBar/Mainline/ActionButtonOverrides.lua UpdateButtonArt does for a button
  on a bar. The button is scaled to the slot size and parented to a plain cell so the
  scale does not distort its anchor offsets

  @param {table} cell
    A frame of the slot size the reference fills
  @param {number} slotSize
  @param {number} index

  @return {table | nil}
    nil when the template cannot be instantiated on this client
]]--
local function CreateBlizzardReference(cell, slotSize, index)
  local ok, button = pcall(
    CreateFrame, "CheckButton", WINDOW_NAME .. "Blizzard" .. index, cell, "ActionButtonTemplate"
  )

  if not ok or button == nil then
    mod.logger.LogWarn(me.tag, "ActionButtonTemplate could not be created: " .. tostring(button))

    return nil
  end

  button:SetPoint("TOPLEFT", cell, "TOPLEFT")
  button:SetScale(slotSize / BLIZZARD_BUTTON_SIZE)
  button:EnableMouse(false)

  if button.SlotArt ~= nil and button.SlotBackground ~= nil then
    button.SlotArt:Show()
    button.SlotBackground:Hide()
  end

  button:SetNormalAtlas("UI-HUD-ActionBar-IconFrame")
  button.NormalTexture:SetDrawLayer("OVERLAY")
  button.NormalTexture:SetSize(46, 45)
  button:SetPushedAtlas("UI-HUD-ActionBar-IconFrame-Down")
  button.PushedTexture:SetDrawLayer("OVERLAY")
  button.PushedTexture:SetSize(46, 45)

  --[[
    The Quick Keybind Mode highlight belongs to the QuickKeybindButtonTemplate, which Blizzard
    mixes into its bar buttons through ActionBarButtonCodeTemplate together with the secure
    click code - not into the art template used here. Recreate it the way
    Blizzard_ActionBar/Shared/ActionButton.lua lays it out: 46 x 45 centred, the template alpha
  ]]--
  button.QuickKeybindHighlightTexture = button:CreateTexture(nil, "OVERLAY")
  button.QuickKeybindHighlightTexture:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
  button.QuickKeybindHighlightTexture:SetBlendMode("ADD")
  button.QuickKeybindHighlightTexture:SetAlpha(0.4)
  button.QuickKeybindHighlightTexture:SetPoint("CENTER")
  button.QuickKeybindHighlightTexture:SetSize(46, 45)
  button.QuickKeybindHighlightTexture:Hide()

  return button
end

--[[
  @param {table} parent
  @param {string} text
  @param {string} fontObject
  @param {number} width

  @return {table}
]]--
local function CreateLabel(parent, text, fontObject, width)
  local label = parent:CreateFontString(nil, "OVERLAY", fontObject)
  label:SetWidth(width)
  label:SetJustifyH("LEFT")
  label:SetText(text)

  return label
end

--[[
  Build the showcase window: one row per state, per slot size a Blizzard reference column
  and a GearMenu slot column
]]--
function me.BuildShowcase()
  local columnCount = #SLOT_SIZES * 2
  local width = PADDING * 2 + LABEL_WIDTH + columnCount * COLUMN_WIDTH + (columnCount - 1) * COLUMN_GAP
  -- the state rows plus the spacing strips row
  local height = PADDING * 2 + TITLE_HEIGHT + HEADER_HEIGHT + (#STATES + 1) * ROW_HEIGHT

  window = CreateFrame("Frame", WINDOW_NAME, UIParent, "BackdropTemplate")
  window:SetSize(width, height)
  window:SetPoint("CENTER")
  window:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
  })
  window:SetMovable(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  -- closes on escape like the other addon windows
  table.insert(UISpecialFrames, WINDOW_NAME)

  local title = CreateLabel(
    window,
    "GearMenu slot showcase - Blizzard action button | GearMenu slot",
    "GameFontNormalLarge",
    width - PADDING * 2
  )
  title:SetPoint("TOPLEFT", window, "TOPLEFT", PADDING, -PADDING)

  local columnsLeft = PADDING + LABEL_WIDTH
  local headerTop = PADDING + TITLE_HEIGHT

  for sizeIndex, slotSize in ipairs(SLOT_SIZES) do
    local blizzardLeft = columnsLeft + (sizeIndex - 1) * 2 * (COLUMN_WIDTH + COLUMN_GAP)
    local slotLeft = blizzardLeft + COLUMN_WIDTH + COLUMN_GAP

    local blizzardHeader = CreateLabel(window, "Blizzard " .. slotSize, "GameFontHighlightSmall", COLUMN_WIDTH)
    blizzardHeader:SetPoint("TOPLEFT", window, "TOPLEFT", blizzardLeft, -headerTop)
    local slotHeader = CreateLabel(window, "GearMenu " .. slotSize, "GameFontHighlightSmall", COLUMN_WIDTH)
    slotHeader:SetPoint("TOPLEFT", window, "TOPLEFT", slotLeft, -headerTop)
  end

  local rowsTop = headerTop + HEADER_HEIGHT
  local index = 0

  for stateIndex, state in ipairs(STATES) do
    local rowTop = rowsTop + (stateIndex - 1) * ROW_HEIGHT
    local icon = state.icon or ITEM_ICON

    local rowLabel = CreateLabel(window, state.label, "GameFontHighlight", LABEL_WIDTH)
    rowLabel:SetPoint("LEFT", window, "TOPLEFT", PADDING, -(rowTop + ROW_HEIGHT / 2))

    for sizeIndex, slotSize in ipairs(SLOT_SIZES) do
      index = index + 1

      local blizzardLeft = columnsLeft + (sizeIndex - 1) * 2 * (COLUMN_WIDTH + COLUMN_GAP)
      local slotLeft = blizzardLeft + COLUMN_WIDTH + COLUMN_GAP
      -- centre both widgets in their column cells
      local cellOffsetX = (COLUMN_WIDTH - slotSize) / 2
      local cellOffsetY = (ROW_HEIGHT - slotSize) / 2

      local cell = CreateFrame("Frame", nil, window)
      cell:SetSize(slotSize, slotSize)
      cell:SetPoint("TOPLEFT", window, "TOPLEFT", blizzardLeft + cellOffsetX, -(rowTop + cellOffsetY))

      local blizzardButton = CreateBlizzardReference(cell, slotSize, index)

      if blizzardButton ~= nil then
        blizzardButton.icon:SetTexture(icon)

        if state.blizzard ~= nil then
          state.blizzard(blizzardButton)
        end
      end

      local slot = CreateShowcaseSlot(window, slotSize, index)
      slot:SetPoint("TOPLEFT", window, "TOPLEFT", slotLeft + cellOffsetX, -(rowTop + cellOffsetY))
      slot.itemTexture:SetTexture(icon)

      if state.slot ~= nil then
        state.slot(slot)
      end
    end
  end

  me.BuildSpacingStrips(rowsTop + #STATES * ROW_HEIGHT, columnsLeft, index)
end

--[[
  Two strips of four buttons below the grid to judge the slot pitch: the Blizzard buttons at the
  pitch of the action bar (its 2 px icon padding on the 45 px button, scaled - the bar art
  dividers that fill that padding are not drawn) and the GearMenu slots at the pitch of a
  gearBar (RGGM_CONSTANTS.SLOT_SPACING_MODIFIER)

  @param {number} stripsTop
  @param {number} stripsLeft
  @param {number} index
    The last slot index used by the grid - the strips continue the numbering
]]--
function me.BuildSpacingStrips(stripsTop, stripsLeft, index)
  local slotSize = STRIP_SLOT_SIZE
  local blizzardPitch = slotSize + BLIZZARD_BUTTON_PADDING * slotSize / BLIZZARD_BUTTON_SIZE
  local slotPitch = slotSize + slotSize * RGGM_CONSTANTS.SLOT_SPACING_MODIFIER
  local gearMenuStripLeft = stripsLeft + #SLOT_SIZES * (COLUMN_WIDTH + COLUMN_GAP)

  local rowLabel = CreateLabel(window, "Bar of four (" .. slotSize .. " px)", "GameFontHighlight", LABEL_WIDTH)
  rowLabel:SetPoint("LEFT", window, "TOPLEFT", PADDING, -(stripsTop + ROW_HEIGHT / 2))

  for stripIndex = 1, STRIP_SLOT_COUNT do
    index = index + 1

    local cellOffsetY = (ROW_HEIGHT - slotSize) / 2

    local cell = CreateFrame("Frame", nil, window)
    cell:SetSize(slotSize, slotSize)
    cell:SetPoint(
      "TOPLEFT", window, "TOPLEFT", stripsLeft + (stripIndex - 1) * blizzardPitch, -(stripsTop + cellOffsetY))

    local blizzardButton = CreateBlizzardReference(cell, slotSize, index)

    if blizzardButton ~= nil then
      blizzardButton.icon:SetTexture(ITEM_ICON)
    end

    local slot = CreateShowcaseSlot(window, slotSize, index)
    slot:SetPoint(
      "TOPLEFT", window, "TOPLEFT", gearMenuStripLeft + (stripIndex - 1) * slotPitch, -(stripsTop + cellOffsetY))
    slot.itemTexture:SetTexture(ITEM_ICON)
  end
end

--[[
  Toggle the showcase window, building it on first use
]]--
function me.Toggle()
  if window == nil then
    me.BuildShowcase()
    print("|cFF00FFB0GearMenu:|r slot showcase built - `/rggm showcase` toggles it, escape closes it")

    return
  end

  if window:IsShown() then
    window:Hide()
  else
    window:Show()
  end
end

--[[
  `showcase` toggles the slot window, `showcase trinkets` the trinketMenu showcase
  (dev/TrinketShowcase.lua)

  @param {table} args
    The arguments after the sub-command
]]--
local function HandleShowcaseCommand(args)
  if args[1] == "trinkets" then
    mod.trinketShowcase.Toggle()
  else
    me.Toggle()
  end
end

--[[
  The dev module cannot hook into code/Core.lua's initialization without touching a
  production file, so it drives its own PLAYER_LOGIN setup.
]]--
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
  -- no helpTextKey - the dev-only command must not show up in /rggm help
  mod.cmd.RegisterCommand("showcase", HandleShowcaseCommand)
end)
