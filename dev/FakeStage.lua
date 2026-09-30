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
  Development-only fake stage for the media capture. Loaded by the development .toc only - it
  must never ship in a release. The WoW Forever beta forgets SavedVariables on every client
  restart and the beta character owns almost no gear, so the README media cannot be shot
  against a real setup. `/rggm stage` builds one:

  - The configuration is staged live: the first gearBar gets head, neck, trinkets and weapons, a
    second, vertical gearBar (created when missing) rings, cloak and hands, and the TrinketMenu
    and the unequip slot are enabled - all through the same functions the settings use, so no
    reload is needed.
  - Gear is faked: every staged gearSlot shows a fake equipped item and the changeMenu,
    trinketMenu and QuickChange lists offer fake bag items (Classic item ids, skipped when the
    client does not know them). Equipping one swaps it with the fake equipped item, unequipping
    moves the fake item back into the fake bags, and a few trinkets run a cooldown.
  - The swap logic stays real: the combat / casting check, the combatQueue store, its ticker,
    the queued-item badge and the right-click drop with its red flash all run the production
    code - only the final item move and the item lookups are faked.

  The stage lives in memory only. A /reload drops it - and on the beta also the configuration,
  which the client never loads back - so shoot a whole round in one go and /reload once at the
  end to flush the shot log. `/rggm stage` again takes the fake gear away (the staged gearBars
  stay until the next reload); `/rggm stage reset` starts the fake gear over.

  Dragging a fake item from one gearSlot onto another is faked too: the cursor only carries real
  items, so the item icon follows the mouse instead and the release over a gearSlot swaps the two
  fake items when each fits the other slot. Bag drag and drop needs real items in the bags - a real
  item equipped into a staged slot takes over from its fake one.

  Registers a `stage` sub-command on the production command registry (code/Cmd.lua) without a
  help text key, so it never shows up in /rggm help.
]]--

-- luacheck: globals CreateFrame UIParent C_Item C_Container GetTime InCombatLockdown UnitAffectingCombat
-- luacheck: globals GetCursorPosition IsMouseButtonDown GetMouseFoci GetMouseFocus
-- luacheck: globals CooldownFrame_Set CooldownFrame_Clear
-- luacheck: globals INVSLOT_HEAD INVSLOT_NECK INVSLOT_TRINKET1 INVSLOT_TRINKET2 INVSLOT_MAINHAND INVSLOT_OFFHAND
-- luacheck: globals INVSLOT_FINGER1 INVSLOT_FINGER2 INVSLOT_BACK INVSLOT_HAND

local mod = rggm
local me = {}
mod.fakeStage = me

me.tag = "FakeStage"

--[[
  The staged gearBars. Everything sits in the right third of the screen: the center stays free for
  the settings window, whose clips want a bar right next to it. Positions are the offset of the
  frame center from the screen center as a fraction of the screen width / height, so the layout
  holds at any resolution and UI scale. The horizontal bar opens its changeMenu up, the vertical
  one to the left - toward the screen, not off its edge
]]--
local STAGED_GEAR_BARS = {
  {
    name = "Default GearBar",
    orientation = RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_HORIZONTAL,
    changeMenuDirection = RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_UP,
    position = { 0.30, -0.22 },
    slots = { INVSLOT_HEAD, INVSLOT_NECK, INVSLOT_TRINKET1, INVSLOT_TRINKET2, INVSLOT_MAINHAND, INVSLOT_OFFHAND }
  }, {
    name = "Rings and Cloak",
    orientation = RGGM_CONSTANTS.GEAR_BAR_ORIENTATION_VERTICAL,
    changeMenuDirection = RGGM_CONSTANTS.GEAR_BAR_CHANGE_MENU_DIRECTION_LEFT,
    position = { 0.44, 0.02 },
    slots = { INVSLOT_FINGER1, INVSLOT_FINGER2, INVSLOT_BACK, INVSLOT_HAND }
  }
}

-- the TrinketMenu above the horizontal bar, same fraction-of-screen offset from the center
local STAGED_TRINKET_MENU_POSITION = { 0.28, 0.18 }

--[[
  Classic items with distinct icons. The equip slot is read from the client, so the grouping
  below is only for the reader - an id the client does not know is skipped. The first item that
  fits a staged gearSlot is equipped there, everything else starts in the fake bags
]]--
local FAKE_ITEM_IDS = {
  -- head
  16866, 12640, 13404, 10588, 16921, 19375, 22267,
  -- neck
  18404, 17065, 19377, 18814, 15411,
  -- trinket
  11815, 13965, 19406, 18820, 11832, 19341, 19395, 1404, 13968, 11819, 21180, 19339, 23001,
  -- main hand and two-hand
  19019, 18832, 19352, 12590, 11684, 17076, 19364,
  -- off hand
  12602, 19349, 17106,
  -- finger
  17063, 19325, 18821, 13098, 19384, 18813,
  -- back
  13340, 18541, 19398, 17107,
  -- hands
  16863, 14551, 15063, 19157
}

--[[
  Every n-th fake item with an onUse effect runs a cooldown that started COOLDOWN_ELAPSED seconds
  ago. Long enough to outlast a whole capture session - a short one runs out before the cooldown
  clips are reached; `/rggm stage reset` restarts them
]]--
local COOLDOWN_EVERY = 3
local COOLDOWN_ELAPSED = 300
local COOLDOWN_DURATION = 3600

--[[
  slotId -> itemId of the fake equipped items
]]--
local fakeEquipped = {}
--[[
  The itemIds in the fake bags, in the order the menus list them
]]--
local fakeBag = {}
--[[
  itemId -> { equipSlot, icon } of every fake item the client knows
]]--
local fakeItems = {}
--[[
  itemId -> { startTime, duration } of the fake items on cooldown
]]--
local fakeCooldowns = {}
--[[
  name -> original function of everything wrapped while the stage is active
]]--
local originals = {}

--[[
  @param {number} itemId

  @return {boolean}
]]--
local function IsFakeItem(itemId)
  return itemId ~= nil and fakeItems[tonumber(itemId)] ~= nil
end

--[[
  @param {table} inventoryType
    List of INVTYPE_* strings
  @param {string} equipSlot

  @return {boolean}
]]--
local function MatchesInventoryType(inventoryType, equipSlot)
  for _, entry in ipairs(inventoryType) do
    if entry == equipSlot then
      return true
    end
  end

  return false
end

--[[
  @param {number} itemId
]]--
local function RemoveFromFakeBag(itemId)
  for index, bagItemId in ipairs(fakeBag) do
    if bagItemId == itemId then
      table.remove(fakeBag, index)

      return
    end
  end
end

--[[
  Resolve the fake items the client knows, equip the first match per staged gearSlot, put the
  rest into the fake bags and start the cooldowns. Asks the client to cache every item so name
  and quality are known by the time a menu lists them
]]--
local function BuildFakeGear()
  fakeEquipped = {}
  fakeBag = {}
  fakeItems = {}
  fakeCooldowns = {}

  local onUseCount = 0

  for _, itemId in ipairs(FAKE_ITEM_IDS) do
    local _, _, _, equipSlot, icon = C_Item.GetItemInfoInstant(itemId)

    if equipSlot ~= nil and equipSlot ~= "" and fakeItems[itemId] == nil then
      fakeItems[itemId] = { equipSlot = equipSlot, icon = icon }
      table.insert(fakeBag, itemId)
      C_Item.RequestLoadItemDataByID(itemId)

      if equipSlot == RGGM_CONSTANTS.TRINKET_MENU_INV_TYPE then
        onUseCount = onUseCount + 1

        if onUseCount % COOLDOWN_EVERY == 1 then
          fakeCooldowns[itemId] = { GetTime() - COOLDOWN_ELAPSED, COOLDOWN_DURATION }
        end
      end
    else
      mod.logger.LogDebug(me.tag, "Skipping unknown item " .. itemId)
    end
  end

  for _, stagedGearBar in ipairs(STAGED_GEAR_BARS) do
    for _, slotId in ipairs(stagedGearBar.slots) do
      local gearSlot = mod.gearManager.GetGearSlotForSlotId(slotId)

      for _, itemId in ipairs(fakeBag) do
        if MatchesInventoryType(gearSlot.type, fakeItems[itemId].equipSlot) then
          fakeEquipped[slotId] = itemId
          RemoveFromFakeBag(itemId)
          break
        end
      end
    end
  end
end

--[[
  Re-render everything that shows items after the fake gear changed
]]--
local function Refresh()
  mod.gearBar.UpdateGearBars(mod.gearBar.UpdateGearBarVisual)

  if mod.configuration.IsTrinketMenuEnabled() then
    mod.trinketMenu.UpdateTrinketMenu()
  end
end

--[[
  Move a fake item from the fake bags into a slot. The previously equipped one takes the bag
  position of the new one - a real swap leaves the old item in the bag slot the new one came from,
  so the menus, which list in bag order, keep their order

  @param {number} itemId
  @param {number} slotId
]]--
local function FakeSwitchItems(itemId, slotId)
  local previousItemId = fakeEquipped[slotId]

  fakeEquipped[slotId] = itemId

  for index, bagItemId in ipairs(fakeBag) do
    if bagItemId == itemId then
      if previousItemId ~= nil then
        fakeBag[index] = previousItemId
      else
        table.remove(fakeBag, index)
      end

      break
    end
  end

  mod.combatQueue.RemoveFromQueue(slotId)
  Refresh()
end

--[[
  The wraps. Each keeps the production contract and only answers differently for fake items or
  fake equipped slots - everything else goes to the original
]]--
local wraps = {}

-- changeMenu and trinketMenu: the fake bag items of the inventory type, filtered by quality
wraps.GetItemsForInventoryType = function(inventoryType)
  local items = {}

  if inventoryType == nil then return items end

  for _, itemId in ipairs(fakeBag) do
    local fakeItem = fakeItems[itemId]

    if MatchesInventoryType(inventoryType, fakeItem.equipSlot) then
      local itemName, _, itemRarity = C_Item.GetItemInfo(itemId)
      local quality = itemRarity or RGGM_CONSTANTS.ITEMQUALITY.rare

      if quality >= mod.configuration.GetFilterItemQuality() then
        table.insert(items, {
          bag = nil,
          slot = nil,
          name = itemName or ("item:" .. itemId),
          icon = fakeItem.icon,
          id = itemId,
          equipSlot = fakeItem.equipSlot,
          quality = quality,
          enchantId = nil
        })
      end
    end
  end

  return items
end

-- QuickChange rule editor: the fake bag and fake equipped items of the inventory type
wraps.FindQuickChangeItems = function(inventoryType, mustHaveOnUse)
  local items = {}

  if inventoryType == nil then return items end

  local candidates = {}

  for _, itemId in ipairs(fakeBag) do
    table.insert(candidates, itemId)
  end

  for _, itemId in pairs(fakeEquipped) do
    table.insert(candidates, itemId)
  end

  for _, itemId in ipairs(candidates) do
    if not mod.itemManager.IsDuplicateItem(items, itemId, nil)
      and MatchesInventoryType(inventoryType, fakeItems[itemId].equipSlot)
      and C_Item.GetItemInfo(itemId) ~= nil then
      local item = mod.itemManager.AddItemsMatchingInventoryType(inventoryType, itemId, nil, mustHaveOnUse)

      if item then
        table.insert(items, item)
      end
    end
  end

  return items
end

-- the swap: the production combat / casting check and combatQueue, a fake item move at the end
wraps.EquipItemByItemAndEnchantId = function(item)
  if item == nil or not IsFakeItem(item.itemId) then
    return originals.EquipItemByItemAndEnchantId(item)
  end

  local itemId = tonumber(item.itemId)
  local slotId = tonumber(item.slotId)

  if UnitAffectingCombat(RGGM_CONSTANTS.UNIT_ID_PLAYER) or mod.common.IsPlayerReallyDead()
    or mod.combatQueue.IsEquipChangeBlocked() or mod.common.IsPlayerCasting() then
    mod.combatQueue.AddToQueue(itemId, tonumber(item.enchantId), slotId)
  else
    FakeSwitchItems(itemId, slotId)
  end
end

wraps.UnequipItemToBag = function(slot)
  local itemId = fakeEquipped[slot.slotId]

  if itemId == nil then
    return originals.UnequipItemToBag(slot)
  end

  fakeEquipped[slot.slotId] = nil
  table.insert(fakeBag, itemId)
  Refresh()
end

wraps.HasItemEquipedInSlot = function(slotId)
  if fakeEquipped[slotId] ~= nil then
    return true
  end

  return originals.HasItemEquipedInSlot(slotId)
end

wraps.UpdateGearSlotTexture = function(gearSlot, gearSlotMetaData)
  local itemId = fakeEquipped[gearSlotMetaData.slotId]

  if itemId == nil then
    return originals.UpdateGearSlotTexture(gearSlot, gearSlotMetaData)
  end

  gearSlot.itemTexture:SetTexture(fakeItems[itemId].icon)
end

wraps.UpdateGearSlotCooldown = function(gearBar, uiSlot, gearSlotMetaData)
  local itemId = fakeEquipped[gearSlotMetaData.slotId]

  if itemId == nil then
    return originals.UpdateGearSlotCooldown(gearBar, uiSlot, gearSlotMetaData)
  end

  local cooldown = fakeCooldowns[itemId]

  if cooldown ~= nil and mod.gearBarManager.IsShowCooldownsEnabled(gearBar.id) then
    CooldownFrame_Set(uiSlot.cooldownOverlay, cooldown[1], cooldown[2], true)
  else
    CooldownFrame_Clear(uiSlot.cooldownOverlay)
  end
end

-- the queued-item badge: production looks the icon up in the real bags
wraps.UpdateCombatQueue = function(itemId, enchantId, slotId)
  if not IsFakeItem(itemId) then
    return originals.UpdateCombatQueue(itemId, enchantId, slotId)
  end

  for _, gearBar in pairs(mod.gearBarStorage.GetGearBars()) do
    for _, gearSlot in ipairs(gearBar.gearSlotReferences) do
      if gearSlot:GetAttribute("slotId") == slotId then
        gearSlot.combatQueueSlot.icon:SetTexture(fakeItems[tonumber(itemId)].icon)
        gearSlot.combatQueueSlot:Show()
      end
    end
  end
end

-- changeMenu entries carry the target slotId, which would show the equipped item's tooltip
wraps.UpdateTooltipForItem = function(item)
  if item ~= nil and IsFakeItem(item.itemId) then
    return originals.UpdateTooltipForItem({ itemId = item.itemId })
  end

  return originals.UpdateTooltipForItem(item)
end

wraps.UpdateTooltipForSlot = function(inventorySlotId)
  local itemId = fakeEquipped[inventorySlotId]

  if itemId == nil then
    return originals.UpdateTooltipForSlot(inventorySlotId)
  end

  originals.UpdateTooltipForItem({ itemId = itemId })
end

wraps.UpdateTooltipForBagItem = function(itemId)
  if not IsFakeItem(itemId) then
    return originals.UpdateTooltipForBagItem(itemId)
  end

  originals.UpdateTooltipForItem({ itemId = itemId })
end

wraps.GetItemCooldown = function(itemId)
  local cooldown = fakeCooldowns[itemId]

  if cooldown ~= nil then
    return cooldown[1], cooldown[2], 1
  end

  if IsFakeItem(itemId) then
    return 0, 0, 1
  end

  return originals.GetItemCooldown(itemId)
end

--[[
  The fake drag between gearSlots. The real one picks the equipped item up
  (GearSlotOnDragStart) and equips the cursor item on the gearSlot it is dropped on
  (GearSlotOnReceiveDrag). A fake item never reaches the cursor, and OnReceiveDrag only fires with
  something on it - so an icon frame follows the mouse and the release is detected in its OnUpdate
]]--
local dragFrame
-- { slotId, itemId } of the gearSlot the running fake drag started on
local dragSource

--[[
  @return {table | nil}
    The configured gearSlot under the mouse, nil if the mouse is not over a gearSlot
]]--
local function GetGearSlotUnderMouse()
  local focus

  if GetMouseFoci ~= nil then
    focus = GetMouseFoci()[1]
  elseif GetMouseFocus ~= nil then
    focus = GetMouseFocus()
  end

  if focus == nil then return nil end

  for _, uiGearBar in pairs(mod.gearBarStorage.GetGearBars()) do
    for _, uiGearSlot in pairs(uiGearBar.gearSlotReferences) do
      if uiGearSlot == focus then
        return mod.gearBarManager.GetGearSlot(uiGearSlot:GetParent().id, uiGearSlot.position)
      end
    end
  end

  return nil
end

--[[
  Swap the fake items of the source and the target gearSlot, when each fits the other slot - the
  real drop onto a slot that cannot take the item does nothing either
]]--
local function EndFakeDrag()
  local target = GetGearSlotUnderMouse()

  if target ~= nil and target.slotId ~= dragSource.slotId then
    local sourceItemId = dragSource.itemId
    local targetItemId = fakeEquipped[target.slotId]
    local source = mod.gearManager.GetGearSlotForSlotId(dragSource.slotId)

    if MatchesInventoryType(target.type, fakeItems[sourceItemId].equipSlot)
      and (targetItemId == nil or MatchesInventoryType(source.type, fakeItems[targetItemId].equipSlot)) then
      fakeEquipped[target.slotId] = sourceItemId
      fakeEquipped[dragSource.slotId] = targetItemId
      Refresh()
    end
  end

  dragSource = nil
  dragFrame:Hide()
end

--[[
  @param {table} uiGearSlot
    The gearSlot the drag starts on - the icon takes its size
  @param {number} slotId
  @param {number} itemId
]]--
local function StartFakeDrag(uiGearSlot, slotId, itemId)
  if dragFrame == nil then
    dragFrame = CreateFrame("Frame", nil, UIParent)
    dragFrame:SetFrameStrata("TOOLTIP")
    dragFrame.icon = dragFrame:CreateTexture(nil, "ARTWORK")
    dragFrame.icon:SetAllPoints()
    dragFrame:SetScript("OnUpdate", function(self)
      local scale = UIParent:GetEffectiveScale()
      local cursorX, cursorY = GetCursorPosition()

      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cursorX / scale, cursorY / scale)

      if not IsMouseButtonDown("LeftButton") then
        EndFakeDrag()
      end
    end)
  end

  local size = uiGearSlot:GetWidth() * uiGearSlot:GetEffectiveScale() / UIParent:GetEffectiveScale()

  dragSource = { slotId = slotId, itemId = itemId }
  dragFrame:SetSize(size, size)
  dragFrame.icon:SetTexture(fakeItems[itemId].icon)
  dragFrame:Show()
end

wraps.GearSlotOnDragStart = function(self)
  if not mod.configuration.IsDragAndDropEnabled() then return end

  local gearSlot = mod.gearBarManager.GetGearSlot(self:GetParent().id, self.position)

  if gearSlot == nil or fakeEquipped[gearSlot.slotId] == nil then
    return originals.GearSlotOnDragStart(self)
  end

  StartFakeDrag(self, gearSlot.slotId, fakeEquipped[gearSlot.slotId])
end

--[[
  The wrapped functions - name in `wraps` / `originals`, owning table, field name
]]--
local function GetWrapTargets()
  return {
    { "GetItemsForInventoryType", mod.itemManager },
    { "FindQuickChangeItems", mod.itemManager },
    { "EquipItemByItemAndEnchantId", mod.itemManager },
    { "UnequipItemToBag", mod.itemManager },
    { "HasItemEquipedInSlot", mod.itemManager },
    { "UpdateGearSlotTexture", mod.gearBar },
    { "UpdateCombatQueue", mod.gearBar },
    { "GearSlotOnDragStart", mod.gearBar },
    { "UpdateGearSlotCooldown", mod.cooldown },
    { "UpdateTooltipForItem", mod.tooltip },
    { "UpdateTooltipForSlot", mod.tooltip },
    { "UpdateTooltipForBagItem", mod.tooltip },
    { "GetItemCooldown", C_Container }
  }
end

--[[
  Turn a fraction-of-screen offset into UI units

  @param {table} position
    { x, y } as fractions of the UIParent width / height

  @return {number} posX
  @return {number} posY
]]--
local function ToScreenOffset(position)
  return math.floor(UIParent:GetWidth() * position[1]), math.floor(UIParent:GetHeight() * position[2])
end

--[[
  Give a gearBar exactly the passed gearSlots, orientation and position through the functions the
  settings use - they rebuild the gearSlot frames live. Existing positions are re-pointed rather
  than removed: removing a gearSlot moves the real key bindings (gui/KeyBind.lua OnGearSlotRemoved)

  @param {table} gearBar
  @param {table} stagedGearBar
]]--
local function StageGearBar(gearBar, stagedGearBar)
  for position = #gearBar.slots, #stagedGearBar.slots + 1, -1 do
    mod.gearBarManager.RemoveGearSlot(gearBar.id, position)
  end

  for position, slotId in ipairs(stagedGearBar.slots) do
    if gearBar.slots[position] == nil then
      mod.gearBarManager.AddGearSlot(gearBar.id, true)
    end

    local gearSlot = mod.common.Clone(mod.gearManager.GetGearSlotForSlotId(slotId))
    gearSlot.keyBinding = gearBar.slots[position].keyBinding
    mod.gearBarManager.UpdateGearSlot(gearBar.id, position, gearSlot, true)
  end

  mod.gearBar.UpdateGearBarGearSlots(gearBar)
  mod.gearBarManager.SetGearBarOrientation(gearBar.id, stagedGearBar.orientation)
  mod.gearBarManager.SetChangeMenuDirection(gearBar.id, stagedGearBar.changeMenuDirection)

  local posX, posY = ToScreenOffset(stagedGearBar.position)

  mod.gearBarManager.UpdateGearBarPosition(gearBar.id, "CENTER", nil, "CENTER", posX, posY)
  mod.gearBar.UpdateGearBarPosition(gearBar)
end

--[[
  Move the TrinketMenu and store the position like a drag does, so a rebuild keeps it
]]--
local function StageTrinketMenuPosition()
  local trinketMenuFrame = _G[RGGM_CONSTANTS.ELEMENT_TRINKET_MENU_FRAME_NAME]

  if trinketMenuFrame == nil then return end

  local posX, posY = ToScreenOffset(STAGED_TRINKET_MENU_POSITION)

  trinketMenuFrame:ClearAllPoints()
  trinketMenuFrame:SetPoint("CENTER", UIParent, "CENTER", posX, posY)
  mod.configuration.SaveUserPlacedFramePosition(
    RGGM_CONSTANTS.ELEMENT_TRINKET_MENU_FRAME_NAME, "CENTER", nil, "CENTER", posX, posY)
end

--[[
  Stage the gearBars - the first one is reused, missing ones are created like the settings create
  them - and enable the TrinketMenu and the unequip slot
]]--
local function StageConfiguration()
  for index, stagedGearBar in ipairs(STAGED_GEAR_BARS) do
    local gearBar = mod.gearBarManager.GetGearBars()[index]

    if gearBar == nil then
      mod.gearBarConfigurationMenu.CreateNewGearBar(stagedGearBar.name)
      gearBar = mod.gearBarManager.GetGearBars()[index]
    end

    StageGearBar(gearBar, stagedGearBar)
  end

  if not mod.configuration.IsTrinketMenuEnabled() then
    mod.configuration.EnableTrinketMenu()
  end

  StageTrinketMenuPosition()
  mod.configuration.EnableUnequipSlot()
end

--[[
  Build the fake gear, install the wraps and stage the gearBars
]]--
function me.Enable()
  BuildFakeGear()

  for _, target in ipairs(GetWrapTargets()) do
    local name, owner = target[1], target[2]

    originals[name] = owner[name]
    owner[name] = wraps[name]
  end

  StageConfiguration()
  Refresh()
  print("|cFF00FFB0GearMenu:|r fake stage on - `/rggm stage` again takes the fake gear away, "
    .. "`/rggm stage reset` starts it over. A /reload drops the stage")
end

--[[
  Put the originals back - the staged gearBars stay until the next reload
]]--
function me.Disable()
  for _, target in ipairs(GetWrapTargets()) do
    local name, owner = target[1], target[2]

    owner[name] = originals[name]
  end

  originals = {}
  fakeEquipped = {}
  Refresh()
  print("|cFF00FFB0GearMenu:|r fake stage off - the gearBars show the real gear again")
end

--[[
  @return {boolean}
]]--
function me.IsActive()
  return next(originals) ~= nil
end

--[[
  `/rggm stage` toggles the stage, `/rggm stage reset` starts the fake gear over without a reload
]]--
local function HandleStageCommand(args)
  if InCombatLockdown() then
    print("|cFF00FFB0GearMenu:|r the stage cannot be changed in combat")

    return
  end

  if args ~= nil and args[1] == "reset" then
    if not me.IsActive() then
      print("|cFF00FFB0GearMenu:|r no stage is active - `/rggm stage` builds one")

      return
    end

    BuildFakeGear()
    Refresh()
    print("|cFF00FFB0GearMenu:|r fake gear reset")

    return
  end

  if me.IsActive() then
    me.Disable()
  else
    me.Enable()
  end
end

--[[
  The dev module cannot hook into code/Core.lua's initialization without touching a production
  file, so it drives its own PLAYER_LOGIN setup like the other dev modules.
]]--
local eventFrame = CreateFrame("Frame")

eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_EQUIPMENT_CHANGED" then
    --[[
      A real item was put into or taken out of a slot (the bag drag and drop clips) - it takes
      over from the fake one. The fake swaps never fire this event. Re-rendered here because the
      order in which code/Core.lua and this frame see the event is not guaranteed
    ]]--
    if me.IsActive() and fakeEquipped[arg1] ~= nil then
      fakeEquipped[arg1] = nil
      Refresh()
    end
  elseif event == "PLAYER_LOGIN" then
    -- no helpTextKey - the dev-only command must not show up in /rggm help
    mod.cmd.RegisterCommand("stage", HandleStageCommand)
  end
end)
