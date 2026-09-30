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

-- luacheck: read globals CreateFrame UIParent GetInventoryItemID GetCursorInfo
-- luacheck: read globals GetInventoryItemLink C_Item C_Container InCombatLockdown
-- luacheck: read globals C_PaperDollInfo EquipCursorItem ClearCursor IsInventoryItemLocked PickupInventoryItem
-- luacheck: read globals QuickKeybindButtonTemplateMixin QuickKeybindFrame C_Timer NumberFontNormalSmallGray

--[[
  The gearBar (GM_Gearbar) module is responsible for building and showing gearBars to the user.
  A gearBar can have n amount of slots where the user can define different gearSlot types and keybinds to activate them.

  A gearBar is always bound to a gearBarConfiguration that was created in the ui configuration of the addon.
  This configuration tells the gearBar exactly how many slots it should have and how those are configured.
  The module responsible for holding and changing this information is the gearBarManager (GM_GearBarManager).
  The gearBar module however should never change values in the gearBarManager. Its sole purpose is to read
  all of the present configurations and display them exactly as described to the user.
]]--

local mod = rggm
local me = {}

mod.gearBar = me

me.tag = "GearBar"

--[[
  ELEMENTS
]]--

--[[
  Initial setup of all configured gearBars. Used during addon startup
]]--
function me.BuildGearBars()
  local gearBars = mod.gearBarManager.GetGearBars()

  for _, gearBar in pairs(gearBars) do
    me.BuildGearBar(gearBar)
  end
end

--[[
  Build a gearBar based on the passed metadata

  @param {table} gearBar

  @return {table}
    The created gearBarFrame
]]--
function me.BuildGearBar(gearBar)
  local gearBarFrame = CreateFrame(
    "Frame",
    RGGM_CONSTANTS.ELEMENT_GEAR_BAR_BASE_FRAME_NAME .. gearBar.id,
    UIParent,
    "BackdropTemplate"
  )
  if gearBar.orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
    gearBarFrame:SetWidth(RGGM_CONSTANTS.GEAR_BAR_DEFAULT_SLOT_SIZE)
    gearBarFrame:SetHeight(RGGM_CONSTANTS.GEAR_BAR_DEFAULT_SLOT_SIZE + RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE)
  else
    gearBarFrame:SetWidth(RGGM_CONSTANTS.GEAR_BAR_DEFAULT_SLOT_SIZE + RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE)
    gearBarFrame:SetHeight(RGGM_CONSTANTS.GEAR_BAR_DEFAULT_SLOT_SIZE)
  end
  gearBarFrame:SetPoint("CENTER", 0, 0)
  gearBarFrame:SetMovable(true)
  -- prevent dragging the frame outside the actual 3d-window
  gearBarFrame:SetClampedToScreen(true)

  gearBarFrame.id = gearBar.id
  -- store ui element reference
  mod.gearBarStorage.AddGearBar(gearBar.id, gearBarFrame)

  me.CreateGearSlots(gearBarFrame, gearBar)
  me.SetupDragFrame(gearBarFrame)
  me.CreateDragHandle(gearBarFrame)
  me.UpdateGearBarSize(gearBar)
  me.UpdateGearBarPosition(gearBar)
  me.UpdateGearBarLockedState(gearBar)
  me.UpdateGearBarVisibility(gearBar)
  me.UpdateGearBarGearSlotTexturesAttributes(gearBar)

  return gearBarFrame
end

--[[
  Create all configured slots for the gearBar and use all data available to create the slots
  with the proper size and position

  @param {table} gearBarFrame
  @param {table} gearBar
]]--
function me.CreateGearSlots(gearBarFrame, gearBar)
  for i = 1, #gearBar.slots do
    local gearSlot = me.CreateGearSlot(gearBarFrame, gearBar, i)
    -- store ui element reference
    mod.gearBarStorage.AddGearSlot(gearBar.id, gearSlot)
  end
end

--[[
  Create a single gearSlot. Note that a gearSlot inherits from the SecureActionButtonTemplate to enable the usage
  of clicking items. Because of SetAttribute this function CANNOT be executed while in combat

  @param {table} gearBarFrame
    The gearBarFrame where the gearSlot gets attached to
  @param {table} gearBar
  @param {number} position
    Position on the gearBar

  @return {table}
    The created gearSlot
]]--
function me.CreateGearSlot(gearBarFrame, gearBar, position)
  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_update_slots_combat"])

    return
  end

  return mod.slotStyle.CreateGearSlot(gearBarFrame, gearBar, position)
end

--[[
  Anchor a gearSlot within its gearBar based on the bar orientation. This is the single
  source of truth for gearSlot positioning math and is used both when a slot is first
  created (by gui/SlotStyle.lua) and when a slot is resized (me.UpdateGearSlotSize).

  @param {table} gearSlot
    The gearSlot to anchor
  @param {table} anchorFrame
    The frame the gearSlot is anchored to (the gearBarFrame)
  @param {number} position
    Position on the gearBar
  @param {number} gearSlotSize
  @param {number} orientation
    One of RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_HORIZONTAL or RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL
]]--
function me.AnchorGearSlot(gearSlot, anchorFrame, position, gearSlotSize, orientation)
  -- the distance between the same corners of two neighbouring slots (see SLOT_SPACING_MODIFIER)
  local slotPitch = gearSlotSize + gearSlotSize * RGGM_CONSTANTS.SLOT_SPACING_MODIFIER

  gearSlot:ClearAllPoints()

  if orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
    gearSlot:SetPoint(
      "TOP",
      anchorFrame,
      "TOP",
      RGGM_CONSTANTS.GEAR_BAR_SLOT_X,
      RGGM_CONSTANTS.GEAR_BAR_SLOT_Y - (position - 1) * slotPitch
    )
  else
    gearSlot:SetPoint(
      "LEFT",
      anchorFrame,
      "LEFT",
      RGGM_CONSTANTS.GEAR_BAR_SLOT_X + (position - 1) * slotPitch,
      RGGM_CONSTANTS.GEAR_BAR_SLOT_Y
    )
  end
end

--[[
  Bare gearSlot construction for gui/SlotStyle.lua. Creates the secure button, sizes and
  anchors it, applies the secure macro attributes and wires up the child widgets that do not
  depend on the slot look. The styling (textures, cooldownOverlay) is layered on top by the
  slot style. Because of SetAttribute this CANNOT run in combat; the me.CreateGearSlot
  dispatcher already guards against that.

  @param {table} gearBarFrame
    The gearBarFrame where the gearSlot gets attached to
  @param {table} gearBar
  @param {number} position
    Position on the gearBar
  @param {string} template
    The frame template the button inherits from

  @return {table}
    The created gearSlot
]]--
function me.CreateGearSlotBase(gearBarFrame, gearBar, position, template)
  local gearSlot = CreateFrame(
    "Button",
    RGGM_CONSTANTS.ELEMENT_GEAR_BAR_SLOT .. position,
    gearBarFrame,
    template
  )

  gearSlot:SetSize(gearBar.gearSlotSize, gearBar.gearSlotSize)
  me.AnchorGearSlot(gearSlot, gearBarFrame, position, gearBar.gearSlotSize, gearBar.orientation)

  local gearSlotMetaData = gearBar.slots[position]

  if gearSlotMetaData ~= nil then
    --[[
      A "/use <slotId>" macro instead of the secure "item" action: the item action resolves a
      slot number to the equipped item link and passes it to C_Item.IsEquippableItem, which
      errors on an empty slot (nil argument). The use command goes straight to UseInventoryItem
      and is a no-op on an empty slot. The plain slotId attribute is what the addon reads back
    ]]--
    gearSlot:SetAttribute("type1", "macro")
    gearSlot:SetAttribute("macrotext1", "/use " .. gearSlotMetaData.slotId)
    gearSlot:SetAttribute("slotId", gearSlotMetaData.slotId)
  end

  mod.uiHelper.CreateItemTexture(gearSlot)
  gearSlot.combatQueueSlot = me.CreateCombatQueueSlot(gearSlot, gearBar.gearSlotSize)
  gearSlot.keyBindingText = me.CreateKeyBindingText(gearSlot, gearBar.gearSlotSize)
  gearSlot.position = position
  --[[
    Quick Keybind Mode (QuickKeybindButtonTemplate, mixed into the slot by the slot style): hovering
    the slot in that mode binds the pressed key to commandName - the slot's proxy action, which
    is fixed by the bar's bindIndex and the slot position for the lifetime of the frame. The
    template's highlight texture ships without anchors; gui/SlotStyle.lua lays it out together
    with the hover highlight
  ]]--
  gearSlot.commandName = mod.keyBindProxy.GetProxyAction(gearBar.bindIndex, position)

  return gearSlot
end

--[[
  The queued item sits in the top left corner of the slot - the top right belongs to the key
  binding text like the hotkey of an action button - framed like a small slot of its own. The
  frame is hidden until an item is queued (me.UpdateCombatQueue)

  @param {table} gearSlot
  @param {number} gearSlotSize

  @return {table}
    The created combatQueueSlot
]]--
function me.CreateCombatQueueSlot(gearSlot, gearSlotSize)
  local combatQueueSlot = CreateFrame("Frame", RGGM_CONSTANTS.ELEMENT_GEAR_BAR_COMBAT_QUEUE_SLOT, gearSlot)
  local combatQueueSlotSize = gearSlotSize * RGGM_CONSTANTS.GEAR_BAR_COMBAT_QUEUE_SLOT_SIZE_MODIFIER

  combatQueueSlot:SetSize(
    combatQueueSlotSize,
    combatQueueSlotSize
  )
  combatQueueSlot:SetPoint("TOPLEFT", gearSlot)

  local iconHolderTexture = combatQueueSlot:CreateTexture(
    RGGM_CONSTANTS.ELEMENT_GEAR_BAR_SLOT_ICON_TEXTURE_NAME,
    "BACKGROUND",
    nil
  )
  iconHolderTexture:SetPoint("TOPLEFT", combatQueueSlot, "TOPLEFT")
  iconHolderTexture:SetPoint("BOTTOMRIGHT", combatQueueSlot, "BOTTOMRIGHT")
  iconHolderTexture:SetTexCoord(0.1, 0.9, 0.1, 0.9)

  combatQueueSlot.icon = iconHolderTexture
  mod.slotStyle.ApplyInsetSlotStyle(combatQueueSlot, combatQueueSlotSize)
  combatQueueSlot:Hide()

  return combatQueueSlot
end

--[[
  Place and size the key binding text of a gearSlot like the hotkey of an action button: a small
  right-aligned field in the top right corner, everything scaled from the 45 px template button
  to the slot size

  @param {table} keybindingFontString
  @param {table} gearSlot
  @param {number} gearSlotSize
]]--
local function LayoutKeyBindingText(keybindingFontString, gearSlot, gearSlotSize)
  local fontFile, _, fontFlags = keybindingFontString:GetFont()

  keybindingFontString:ClearAllPoints()
  keybindingFontString:SetPoint(
    "TOPRIGHT",
    gearSlot,
    "TOPRIGHT",
    gearSlotSize * RGGM_CONSTANTS.SLOT_KEY_BINDING_TEXT_OFFSET_X_MODIFIER,
    gearSlotSize * RGGM_CONSTANTS.SLOT_KEY_BINDING_TEXT_OFFSET_Y_MODIFIER
  )
  keybindingFontString:SetSize(
    gearSlotSize * RGGM_CONSTANTS.SLOT_KEY_BINDING_TEXT_WIDTH_MODIFIER,
    gearSlotSize * RGGM_CONSTANTS.SLOT_KEY_BINDING_TEXT_HEIGHT_MODIFIER
  )
  keybindingFontString:SetFont(fontFile, gearSlotSize * RGGM_CONSTANTS.SLOT_KEY_BINDING_TEXT_SIZE_MODIFIER, fontFlags)
end

--[[
  @param {table} gearSlot
  @param {number} gearSlotSize

  @return {table}
    The created keybindingFontString
]]--
function me.CreateKeyBindingText(gearSlot, gearSlotSize)
  local keybindingFontString = gearSlot:CreateFontString(nil, "OVERLAY")
  -- the face and outline of the action-button hotkey; the size is scaled to the slot below
  keybindingFontString:SetFontObject(NumberFontNormalSmallGray)
  keybindingFontString:SetJustifyH("RIGHT")
  mod.uiHelper.SetColor(keybindingFontString, RGGM_CONSTANTS.COLOR.KEY_BINDING)
  LayoutKeyBindingText(keybindingFontString, gearSlot, gearSlotSize)
  keybindingFontString:Hide()

  return keybindingFontString
end

--[[
  Create the drag handle (grip) for a gearBar. The handle is a mouse-enabled child
  frame that lives in the trailing margin strip of the bar and is only shown while
  the bar is unlocked. It drives the parent gearBarFrame's existing drag handlers so
  the bar can be moved by grabbing the handle. The actual size and position of the
  handle is set in me.UpdateGearBarSize once the orientation and slotSize are known.

  @param {table} gearBarFrame
    The gearBarFrame the drag handle gets attached to
]]--
function me.CreateDragHandle(gearBarFrame)
  local dragHandle = CreateFrame("Frame", nil, gearBarFrame)
  dragHandle:EnableMouse(true)

  local texture = dragHandle:CreateTexture(nil, "OVERLAY")
  texture:SetAllPoints(dragHandle)
  texture:SetColorTexture(1, 1, 1, .3)
  dragHandle.texture = texture

  dragHandle:SetScript("OnEnter", function(self)
    self.texture:SetColorTexture(1, 1, 1, .5)
    local tooltip = _G[RGGM_CONSTANTS.ELEMENT_TOOLTIP]
    tooltip:SetOwner(self, "ANCHOR_TOP")
    tooltip:SetText(rggm.L["gear_bar_drag_handle_tooltip"])
    tooltip:Show()
  end)

  dragHandle:SetScript("OnLeave", function(self)
    self.texture:SetColorTexture(1, 1, 1, .3)
    mod.tooltip.TooltipClear()
  end)

  dragHandle:SetScript("OnMouseDown", function(self)
    me.StartDragFrame(self:GetParent())
  end)

  dragHandle:SetScript("OnMouseUp", function(self)
    me.StopDragFrame(self:GetParent())
  end)

  gearBarFrame.dragHandle = dragHandle

  return dragHandle
end

--[[
  UPDATE

  GearBar update functions
]]--

--[[
  Update all GearBars with a certain operation (see param)

  @param {function} func
    A function to invoke for each gearBar
]]--
function me.UpdateGearBars(func)
  local gearBars = mod.gearBarManager.GetGearBars()

  for _, gearBar in pairs(gearBars) do
      func(gearBar)
  end
end

--[[
  Load the initial gearBar state once the addon is initialized

  @param {table} gearBar
]]--
function me.UpdateGearBarVisual(gearBar)
  me.UpdateGearBarGearSlotTextures(gearBar)
  me.UpdateGearBarGearSlotCooldowns(gearBar)
  me.UpdateKeyBindingState(gearBar)
end

--[[
  Update the position of a gearBar. This is called onInit when the bar is first loaded from the configuration

  @param {table} gearBar
]]--
function me.UpdateGearBarPosition(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)
  uiGearBar.gearBarReference:ClearAllPoints()
  uiGearBar.gearBarReference:SetPoint(
    gearBar.position.point,
    nil,
    gearBar.position.relativePoint,
    gearBar.position.posX,
    gearBar.position.posY
  )
end

--[[
  Update the visual representation of a gearBar whether the gearBar is locked or unlocked

  @param {table} gearBar
]]--
function me.UpdateGearBarLockedState(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  if gearBar.isLocked then
    uiGearBar.gearBarReference:SetBackdrop(nil)
    uiGearBar.gearBarReference.dragHandle:Hide()
  else
    uiGearBar.gearBarReference:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background"
    })
    uiGearBar.gearBarReference.dragHandle:Show()
  end
end

--[[
  Show or hide the whole gearBarFrame based on the per-gearBar visibility flag.

  Hiding is purely visual - the gearSlots keep their keyBindings and the range-check ticker
  is left untouched, so a hidden gearBar can still be triggered by its keyBindings.

  Note that the gearSlots of a gearBar inherit from the SecureActionButtonTemplate. Changing the
  visibility of their parent frame is a protected operation and CANNOT be executed while in combat.
  Guard the update here so a visibility change made during combat hits the graceful error path
  instead of a blocked protected operation.

  @param {table} gearBar
]]--
function me.UpdateGearBarVisibility(gearBar)
  if InCombatLockdown() then
    mod.logger.LogError(me.tag, "Unable to change the visibility of a gearBar in combat")

    return
  end

  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  if mod.gearBarManager.IsGearBarVisible(gearBar.id) then
    uiGearBar.gearBarReference:Show()
  else
    uiGearBar.gearBarReference:Hide()
  end
end

--[[
  Update gearBar size in cases such as a new gearSlot was added or one was removed or the
  size of the gearSlot was changed.

  @param {table} gearBar
    Data representation of a gearBar
]]--
function me.UpdateGearBarSize(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)
  local gearBarReference = uiGearBar.gearBarReference

  local slotsExtent = mod.uiHelper.CalculateGridExtent(
    #gearBar.slots, gearBar.gearSlotSize, gearBar.gearSlotSize * RGGM_CONSTANTS.SLOT_SPACING_MODIFIER)

  if gearBar.orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
    gearBarReference:SetWidth(gearBar.gearSlotSize)
    gearBarReference:SetHeight(slotsExtent + RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE)
  else
    gearBarReference:SetWidth(slotsExtent + RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE)
    gearBarReference:SetHeight(gearBar.gearSlotSize)
  end

  me.UpdateDragHandleLayout(gearBar)
end

--[[
  Position and size the drag handle (grip) on the trailing edge of the gearBar based
  on its current orientation and slotSize. Called from me.UpdateGearBarSize so the
  handle stays correct after slotSize and orientation changes.

  @param {table} gearBar
    Data representation of a gearBar
]]--
function me.UpdateDragHandleLayout(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)
  local dragHandle = uiGearBar.gearBarReference.dragHandle

  dragHandle:ClearAllPoints()

  if gearBar.orientation == RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL then
    -- bottom strip spanning the width of the bar
    dragHandle:SetSize(gearBar.gearSlotSize, RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE)
    dragHandle:SetPoint("BOTTOMLEFT", uiGearBar.gearBarReference, "BOTTOMLEFT", 0, 0)
  else
    -- right strip spanning the height of the bar
    dragHandle:SetSize(RGGM_CONSTANTS.GEAR_BAR_DRAG_HANDLE_SIZE, gearBar.gearSlotSize)
    dragHandle:SetPoint("TOPRIGHT", uiGearBar.gearBarReference, "TOPRIGHT", 0, 0)
  end
end

--[[
  UPDATE

  GearSlot update functions
]]--

--[[
  Update the visual representation of the combatQueue on all present gearBars by
  locking through all gearBars and whether they have a slot with a matching slotId or
  not. This catches cases where multiple gearBars have the same slot present

  @param {number} itemId
    The itemId to update the combatQueue for
  @param {number} enchantId
    The enchantId to update the combatQueue for
  @param {number} slotId
    The slotId to update the combatQueue for
]]--
function me.UpdateCombatQueue(itemId, enchantId, slotId)
  mod.logger.LogDebug(me.tag, "Updating combatqueues for slotId - " .. slotId)

  for _, gearBar in pairs(mod.gearBarStorage.GetGearBars()) do
    local gearSlots = gearBar.gearSlotReferences

    for i = 1, #gearSlots do
      if gearSlots[i]:GetAttribute("slotId") == slotId then
        local combatQueueSlot = gearSlots[i].combatQueueSlot

        if itemId then
          local bagNumber, bagPos = mod.itemManager.FindItemInBag(itemId, enchantId)

          if bagNumber ~= nil and bagPos ~= nil then
            local itemInfo = C_Container.GetContainerItemInfo(bagNumber, bagPos)
            combatQueueSlot.icon:SetTexture(itemInfo.iconFileID)
            combatQueueSlot:Show()
          else
            --[[
              With the introduction of the macrobridge it would be possible for items to not be found if the player
              passed an item that he doesn't have in his inventory
            ]]--
            mod.logger.LogError(me.tag, "Failed to find item in bag")
          end
        else
          combatQueueSlot:Hide()
        end
      end
    end
  end
end

--[[
  Update visual display of itemrange for all gearslots
]]--
function me.UpdateSpellRange()
  local uiGearBars = mod.gearBarStorage.GetGearBars()

  for _, uiGearBar in pairs(uiGearBars) do
    local gearBarId = uiGearBar.gearBarReference.id
    local gearBar = mod.gearBarManager.GetGearBar(gearBarId)

    for _, gearSlot in pairs(uiGearBar.gearSlotReferences) do
      if mod.target.GetCurrentTargetGuid() == "" then
        mod.uiHelper.SetColor(gearSlot.keyBindingText, RGGM_CONSTANTS.COLOR.KEY_BINDING)
      else
        local gearSlotMetaData = gearBar.slots[gearSlot.position]

        if gearSlotMetaData ~= nil then
          local itemLink = GetInventoryItemLink(RGGM_CONSTANTS.UNIT_ID_PLAYER, gearSlotMetaData.slotId)
          --[[
            - Returns true if item is in range
            - Returns false if item is not in range
            - Returns nil if not applicable(e.g. item is passive only) or the slot might be empty
          ]]--
          local isInRange = C_Item.IsItemInRange(itemLink or "", RGGM_CONSTANTS.UNIT_ID_TARGET)

          if isInRange == nil or isInRange == true then
            mod.uiHelper.SetColor(gearSlot.keyBindingText, RGGM_CONSTANTS.COLOR.KEY_BINDING)
          else
            mod.uiHelper.SetColor(gearSlot.keyBindingText, RGGM_CONSTANTS.COLOR.KEY_BINDING_OUT_OF_RANGE)
          end
        end
      end
    end
  end
end

--[[
  Update the cooldown of all gearSlots on all gearBars in response to BAG_UPDATE_COOLDOWN
  or a visual update of the gearBars

  @param {table} gearBar
]]--
function me.UpdateGearBarGearSlotCooldowns(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for index, gearSlotMetaData in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[index]

    mod.cooldown.UpdateGearSlotCooldown(gearBar, uiGearSlot, gearSlotMetaData)
  end
end

--[[
  Update the keyBinding text and hide the keyBinding if no text is available on all slots of the
  passed gearBar. The text is the key bound to the slot's proxy action in WoW's binding set
  (gui/KeyBind.lua GetSlotKeyBinding) - the binding set is the source of truth, not the
  configuration.

  * Handles the event where the player activates or deactivates showKeyBindings
  * Handles the event where we receive an UPDATE_BINDINGS event

  @param {table} gearBar
]]--
function me.UpdateKeyBindingState(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)
  local showKeyBindings = mod.gearBarManager.IsShowKeyBindingsEnabled(gearBar.id)
  local hasVisibleKeyBinding = false

  for index, _ in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[index]
    local keyBinding = mod.keyBind.GetSlotKeyBinding(gearBar, index)

    if keyBinding and showKeyBindings then
      hasVisibleKeyBinding = true
      uiGearSlot.keyBindingText:SetText(mod.keyBind.ConvertKeyBindingText(keyBinding))
      uiGearSlot.keyBindingText:Show()
    else
      uiGearSlot.keyBindingText:SetText("")
      uiGearSlot.keyBindingText:Hide()
    end
  end

  if hasVisibleKeyBinding then
    mod.ticker.RegisterForTickerRangeCheck(gearBar.id)
  else
    mod.ticker.UnregisterForTickerRangeCheck(gearBar.id)
  end
end

--[[
  Update all gearSlot textures of the passed gearBar

  @param {table} gearBar
]]--
function me.UpdateGearBarGearSlotTextures(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for index, gearSlot in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[index]

    me.UpdateGearSlotTexture(uiGearSlot, gearSlot)
    mod.slotStyle.UpdateSlotTextureAttributes(uiGearSlot, gearBar.gearSlotSize)
  end
end

--[[
  Update the button texture style and add icon for the currently worn item. If no item is worn
  the default icon is displayed

  @param {table} gearSlot
  @param {table} gearSlotMetaData
]]--
function me.UpdateGearSlotTexture(gearSlot, gearSlotMetaData)
  local itemId = GetInventoryItemID(RGGM_CONSTANTS.UNIT_ID_PLAYER, gearSlotMetaData.slotId)

  if itemId then
    local itemIcon = select(10, C_Item.GetItemInfo(itemId))
    -- If an actual item was found in the inventory slot said icon is used
    gearSlot.itemTexture:SetTexture(itemIcon or gearSlotMetaData.textureId)
  else
    -- If no item can be found in the inventory slot use the default icon
    gearSlot.itemTexture:SetTexture(gearSlotMetaData.textureId)
  end
end

--[[
  Update the texture attributes of all gearSlots of the passed gearBar

  @param {table} gearBar
]]--
function me.UpdateGearBarGearSlotTexturesAttributes(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for index, _ in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[index]

    mod.slotStyle.UpdateSlotTextureAttributes(uiGearSlot, gearBar.gearSlotSize)
  end
end

--[[
  GearSlot size adjustment in response to a configuration change
]]--

--[[
  Update the size of a gearSlot and all its underlying components that need to be adapted
  as well

  @param {table} gearBar
]]--
function me.UpdateGearSlotSizes(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for position, _ in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[position]

    me.UpdateGearSlotSize(uiGearBar, uiGearSlot, gearBar.gearSlotSize, position, gearBar.orientation)
    mod.cooldown.UpdateCooldownOverlaySize(uiGearSlot, gearBar.gearSlotSize)
    me.UpdateGearSlotCombatQueueSize(uiGearSlot, gearBar.gearSlotSize)
    me.UpdateGearSlotKeyBindingTextSize(uiGearSlot, gearBar.gearSlotSize)
    mod.slotStyle.UpdateSlotTextureAttributes(uiGearSlot, gearBar.gearSlotSize)
  end
end

--[[
  @param {table} uiGearBar
  @param {table} uiGearSlot
  @param {number} gearSlotSize
  @param {number} position
  @param {number} orientation
    One of RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_HORIZONTAL or RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL
]]--
function me.UpdateGearSlotSize(uiGearBar, uiGearSlot, gearSlotSize, position, orientation)
  uiGearSlot:SetSize(gearSlotSize, gearSlotSize)
  me.AnchorGearSlot(uiGearSlot, uiGearBar.gearBarReference, position, gearSlotSize, orientation)
end

--[[
  @param {table} uiGearSlot
  @param {number} slotSize
]]--
function me.UpdateGearSlotCombatQueueSize(uiGearSlot, slotSize)
  local combatQueueSlotSize = slotSize * RGGM_CONSTANTS.GEAR_BAR_COMBAT_QUEUE_SLOT_SIZE_MODIFIER

  uiGearSlot.combatQueueSlot:SetSize(combatQueueSlotSize, combatQueueSlotSize)
  mod.slotStyle.UpdateInsetSlotTextureAttributes(uiGearSlot.combatQueueSlot, combatQueueSlotSize)
end

--[[
  @param {table} uiGearSlot
  @param {number} slotSize
]]--
function me.UpdateGearSlotKeyBindingTextSize(uiGearSlot, slotSize)
  LayoutKeyBindingText(uiGearSlot.keyBindingText, uiGearSlot, slotSize)
end

--[[
  Used in response to adding, removing or updating a gearSlot in the Interfaces Panel

  Note that gearSlots inherit from the SecureActionButtonTemplate. Creating a new slot or updating an
  existing one calls SetAttribute, which CANNOT be executed while in combat. Guard the whole update here
  so a slot change made during combat hits the graceful error path instead of a blocked protected operation.

  @param {table} gearBar
]]--
function me.UpdateGearBarGearSlots(gearBar)
  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_update_slots_combat"])

    return
  end

  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for position, gearSlotMetaData in pairs(gearBar.slots) do
    local uiGearSlot = uiGearBar.gearSlotReferences[position]

    if uiGearSlot == nil then
      me.CreateNewGearSlot(gearBar, uiGearBar, position)
    else
      me.UpdateExistingSlot(uiGearBar, gearSlotMetaData, position)
    end
  end

  -- update visual elements of the gearBar
  me.UpdateGearBarGearSlotTextures(gearBar)
  me.UpdateGearBarGearSlotCooldowns(gearBar)
  me.UpdateKeyBindingState(gearBar)
  me.UpdateGearBarSize(gearBar)
  me.CleanupOrphanedGearSlots(gearBar)
end

--[[
  @param {table} uiGearSlot
  @param {table} gearSlotMetaData
  @param {number} position
]]--
function me.UpdateExistingSlot(uiGearBar, gearSlotMetaData, position)
  local uiGearSlot = uiGearBar.gearSlotReferences[position]

  -- see me.CreateGearSlotBase for why a /use macro is used instead of the secure item action
  uiGearSlot:SetAttribute("type1", "macro")
  uiGearSlot:SetAttribute("macrotext1", "/use " .. gearSlotMetaData.slotId)
  uiGearSlot:SetAttribute("slotId", gearSlotMetaData.slotId)
  uiGearSlot:Show()
end

--[[
  @param {table} uiGearSlot
  @param {table} uiGearBar
  @param {number} position
]]--
function me.CreateNewGearSlot(gearBar, uiGearBar, position)
  -- create new gearSlot
  mod.logger.LogInfo(me.tag, "GearSlot does not yet exist. Creating a new one")

  local gearSlot = me.CreateGearSlot(uiGearBar.gearBarReference, gearBar, position)
  mod.gearBarStorage.AddGearSlot(gearBar.id, gearSlot)
end

--[[
  Search for orphan gearSlots that should be removed. Note it is not possible to delete
  a frame. It can only be hidden but will of course not be recreated once the user reloads the ui

  Note: It is very important to not lose a reference to a slot because just recreating the same slot
  with the same name won't work with keybinds. In that case a reload is required to recreate the ui

  @param {table} gearBar
    The configuration of a gearBar
  @param {table} gearBarUi
    The visual representation of a gearBar
]]--
function me.CleanupOrphanedGearSlots(gearBar)
  local uiGearBar = mod.gearBarStorage.GetGearBar(gearBar.id)

  for i = 1, #uiGearBar.gearSlotReferences do
    if gearBar.slots[i] == nil then
      -- simply hide gearSlots that are not in use
      uiGearBar.gearSlotReferences[i]:Hide()
    end
  end
end

--[[
  EVENTS
]]--

--[[
  Setup events for gearBar frame

  @param {table} gearBar
    The gearBar to attach the drag handlers to
]]--
function me.SetupDragFrame(gearBar)
  gearBar:SetScript("OnMouseDown", me.StartDragFrame)
  gearBar:SetScript("OnMouseUp", me.StopDragFrame)
end

--[[
  Frame callback to start moving the gearBar frame

  The gearBarFrame is the anchor parent of its gearSlots, which inherit from the
  SecureActionButtonTemplate. Moving a frame that protected frames are anchored to is itself a
  protected operation and CANNOT be executed while in combat. Refuse the drag here so the
  user gets a message instead of a blocked protected operation.

  @param {table} self
]]--
function me.StartDragFrame(self)
  if mod.gearBarManager.IsGearBarLocked(self.id) then return end

  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_move_combat"])

    return
  end

  self.isMoving = true
  self:StartMoving()
end

--[[
  Frame callback to stop moving the gearBar frame

  Only a gearBar that was actually started moving is stopped. A drag that combat interrupted
  stays pending (the frame keeps following the cursor) because stopping it is a protected
  operation as well - it is finished by me.StopPendingDragFrames once combat ends.

  @param {table} self
]]--
function me.StopDragFrame(self)
  if not self.isMoving then return end

  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_move_combat"])

    return
  end

  self.isMoving = false
  self:StopMovingOrSizing()

  local point, relativeTo, relativePoint, posX, posY = self:GetPoint()
  mod.gearBarManager.UpdateGearBarPosition(self.id, point, relativeTo, relativePoint, posX, posY)
end

--[[
  Finish every drag that was interrupted by combat. Invoked once the player leaves combat.
]]--
function me.StopPendingDragFrames()
  for _, uiGearBar in pairs(mod.gearBarStorage.GetGearBars()) do
    if uiGearBar.gearBarReference.isMoving then
      me.StopDragFrame(uiGearBar.gearBarReference)
    end
  end
end

--[[
  Setup event for a changeSlot

  @param {table} gearSlot
]]--
function me.SetupEvents(gearSlot)
  --[[
    Register both the down and the up phase of a click. The modern ui engine executes the secure
    action of a button in a single direction only - chosen by the useOnKeyDown attribute
    respectively the ActionButtonUseKeyDown cvar as fallback. A button that is registered for one
    direction only is unreachable for keybindings dispatched in the other direction. The
    useOnKeyDown attribute maps the fastpress option onto that engine behavior - action on
    keypress when fastpress is enabled, on keyrelease otherwise (see me.UpdateClickHandler for
    updates on configuration change).

    Note: SecureActionButtons ignore right clicks by default - reenable right clicks
  ]]--
  gearSlot:RegisterForClicks("LeftButtonDown", "LeftButtonUp", "RightButtonDown", "RightButtonUp")
  gearSlot:SetAttribute("useOnKeyDown", mod.configuration.IsFastPressEnabled())

  gearSlot:RegisterForDrag("LeftButton")
  --[[
    Replacement for OnCLick. Do not overwrite click event for protected button
  ]]--
  gearSlot:SetScript("PreClick", function(self, button, down)
    me.GearSlotOnClick(self, button, down)
  end)

  gearSlot:SetScript("OnEnter", me.GearSlotOnEnter)
  gearSlot:SetScript("OnLeave", me.GearSlotOnLeave)

  gearSlot:SetScript("OnReceiveDrag", function(self)
    me.GearSlotOnReceiveDrag(self)
  end)

  gearSlot:SetScript("OnDragStart", function(self)
    me.GearSlotOnDragStart(self)
  end)
end

--[[
  Update the useOnKeyDown attribute on all gearSlots to match the fastpress configuration.
  Click registration itself is static (see me.SetupEvents); the attribute alone decides whether
  the secure action fires on keypress or on keyrelease. Because gearSlots are protected frames
  the attribute cannot be updated during combat lockdown
]]--
function me.UpdateClickHandler()
  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_update_slots_combat"])

    return
  end

  local uiGearBars = mod.gearBarStorage.GetGearBars()

  for _, uiGearBar in pairs(uiGearBars) do
    for _, gearSlot in pairs(uiGearBar.gearSlotReferences) do
      gearSlot:SetAttribute("useOnKeyDown", mod.configuration.IsFastPressEnabled())
    end
  end
end

--[[
  Callback for a gearBarSlot PreClick. Because gearSlots are registered for both click directions
  (see me.SetupEvents) this fires for the down and the up phase of every click. The work is gated
  to the phase that matches the fastpress configuration so it runs exactly once per activation -
  in the same direction in which the secure action fires

  @param {table} self
  @param {string} button
  @param {boolean} down
    true for the buttonDown phase, false for the buttonUp phase
]]--
function me.GearSlotOnClick(self, button, down)
  if down ~= mod.configuration.IsFastPressEnabled() then
    return
  end

  if button == "RightButton" then
    mod.combatQueue.RemoveFromQueue(self:GetAttribute("slotId"))
    -- the red flash confirms the drop; a left click has the pushed state of the button
    mod.slotStyle.FlashSlot(
      self, RGGM_CONSTANTS.COLOR.QUEUE_REMOVED, RGGM_CONSTANTS.GEAR_SLOT_REMOVE_FLASH_DURATION)
  end
end

--[[
  A key bound to the gearSlot was pressed (forwarded from the PreClick of its key-bind proxy,
  gui/KeyBindProxy.lua OnProxyClick). The secure action runs on the hidden proxy, so the
  gearSlot itself gets no click - give it the same feedback a mouse click gives: a short pushed
  state (the slot's pushed texture). Gated to the fastpress phase exactly like
  me.GearSlotOnClick

  @param {table} self
    the gearSlot
  @param {boolean} down
]]--
function me.GearSlotOnKeyPress(self, down)
  if down ~= mod.configuration.IsFastPressEnabled() then
    return
  end

  me.FlashGearSlot(self)
end

--[[
  Show the pushed state of a gearSlot for a moment. SetButtonState is purely visual, so it is
  allowed on the protected button in combat. A token makes a newer press outlive the reset timer
  of an older one - its own field, as slotStyle.FlashSlot keeps flashToken on the same gearSlot
  for the colour flash

  @param {table} gearSlot
]]--
function me.FlashGearSlot(gearSlot)
  gearSlot.pushFlashToken = (gearSlot.pushFlashToken or 0) + 1
  local pushFlashToken = gearSlot.pushFlashToken

  gearSlot:SetButtonState("PUSHED")

  C_Timer.After(RGGM_CONSTANTS.GEAR_SLOT_KEY_PRESS_FLASH_DURATION, function()
    if gearSlot.pushFlashToken ~= pushFlashToken then return end

    gearSlot:SetButtonState("NORMAL")
  end)
end

--[[
  Callback for a gearSlot OnEnter. The QuickKeybindButtonTemplate hover handler is forwarded by
  hand because this script replaces the template's - in Quick Keybind Mode it selects the slot's
  commandName for the next key press and shows the binding tooltip (Blizzard's action buttons do
  the same from their own OnEnter)

  @param {table} self
]]--
function me.GearSlotOnEnter(self)
  mod.gearBarChangeMenu.UpdateChangeMenu(self.position, self:GetParent().id)

  mod.tooltip.UpdateTooltipForSlot(self:GetAttribute("slotId"))
  QuickKeybindButtonTemplateMixin.QuickKeybindButtonOnEnter(self)
end

--[[
  Callback for a gearSlot OnLeave (see me.GearSlotOnEnter for the Quick Keybind Mode forward)

  @param {table} self
]]--
function me.GearSlotOnLeave(self)
  mod.tooltip.TooltipClear()
  QuickKeybindButtonTemplateMixin.QuickKeybindButtonOnLeave(self)
end

--[[
  Hook Blizzard's Quick Keybind Mode so every gearSlot shows the mode's highlight while it is
  active and its mouse wheel forwards to the mode - the same treatment Blizzard gives its own
  action buttons through ActionButtonUtil. The frame exists from login on (Blizzard_QuickKeybind
  is not load-on-demand); the hooks are plain script hooks, nothing protected is called.
]]--
function me.SetupQuickKeybindMode()
  QuickKeybindFrame:HookScript("OnShow", function()
    me.UpdateQuickKeybindMode(true)
  end)

  QuickKeybindFrame:HookScript("OnHide", function()
    me.UpdateQuickKeybindMode(false)
  end)
end

--[[
  Toggle the Quick Keybind Mode visuals of every gearSlot

  @param {boolean} isInQuickKeybindMode
]]--
function me.UpdateQuickKeybindMode(isInQuickKeybindMode)
  for _, uiGearBar in pairs(mod.gearBarStorage.GetGearBars()) do
    for _, gearSlot in pairs(uiGearBar.gearSlotReferences) do
      gearSlot:DoModeChange(isInQuickKeybindMode)
      gearSlot:UpdateMouseWheelHandler()
    end
  end
end

--[[
  Callback for a gearSlot OnReceiveDrag

  @param {table} self
]]--
function me.GearSlotOnReceiveDrag(self)
  if not mod.configuration.IsDragAndDropEnabled() then return end

  local gearSlot = mod.gearBarManager.GetGearSlot(self:GetParent().id, self.position)

  if gearSlot == nil then return end

  local gearSlotMetaData = mod.gearManager.GetGearSlotForSlotId(gearSlot.slotId)
  -- abort if no item could be found
  if gearSlotMetaData == nil then return end

  if C_PaperDollInfo.CursorCanGoInSlot(gearSlotMetaData.slotId) then
    if InCombatLockdown() or mod.common.IsPlayerCasting() then
      local cursorType, _, itemLink = GetCursorInfo()

      if cursorType ~= "item" or itemLink == nil then return end

      local itemInfo = mod.common.GetItemInfo(itemLink)

      mod.combatQueue.AddToQueue(itemInfo.itemId, itemInfo.enchantId, gearSlotMetaData.slotId)
      ClearCursor()
    else
      EquipCursorItem(gearSlotMetaData.slotId)
    end
  else
    mod.logger.LogInfo(me.tag, "Invalid item for slotId - " .. gearSlotMetaData.slotId)
    ClearCursor() -- clear cursor from item
  end
end

--[[
  Callback for a gearSlot OnDragStart

  @param {table} self
]]--
function me.GearSlotOnDragStart(self)
  if not mod.configuration.IsDragAndDropEnabled() then return end

  local gearSlot = mod.gearBarManager.GetGearSlot(self:GetParent().id, self.position)

  if gearSlot == nil then return end

  local gearSlotMetaData = mod.gearManager.GetGearSlotForSlotId(gearSlot.slotId)
  -- abort if no item could be found
  if gearSlotMetaData == nil then return end

  if not IsInventoryItemLocked(gearSlotMetaData.slotId) then
    PickupInventoryItem(gearSlotMetaData.slotId)
  end
end
