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
  Development-only trinketMenu and changeMenu showcase. Loaded by the development .toc only -
  it must never ship in a release. `/rggm showcase trinkets` toggles it: while it is on, the
  real trinketMenu (and the changeMenu of a trinket gearSlot) is fed a fixed list of Classic
  trinkets instead of the bag contents, with a few of them on a running cooldown, so the menu
  can be judged full at the configured slot size and column amount without owning the items.
  `/rggm showcase changemenu` feeds that list to the changeMenu of every gearSlot instead,
  whatever its type, up to the 40 items a changeMenu shows - hover any slot to see it full.

  It works by wrapping two lookups the menu goes through - itemManager.GetItemsForInventoryType
  for the trinket inventory type and C_Container.GetItemCooldown for the showcased item ids -
  and re-rendering the menu; every later bag or cooldown update keeps showing the showcase
  until it is toggled off, which restores the originals and re-renders the real bags.

  The trinkets are not in the bags, so clicking one logs a failed swap, dragging does nothing
  and there is no tooltip. Trinkets the client does not know are skipped.

  Dispatched by gui/SlotShowcase.lua from its `showcase` sub-command.
]]--

-- luacheck: globals C_Item C_Container GetTime

local mod = rggm
local me = {}
mod.trinketShowcase = me

me.tag = "TrinketShowcase"

--[[
  Classic trinkets with distinct icons - enough for the 40 items of a changeMenu with spares in
  case the client does not know some of them
]]--
local TRINKET_ITEM_IDS = {
  13965, -- Blackhand's Breadth
  11815, -- Hand of Justice
  19406, -- Drake Fang Talisman
  18820, -- Talisman of Ephemeral Power
  11832, -- Burst of Knowledge
  19341, -- Lifegiving Gem
  19395, -- Rejuvenating Gem
  12930, -- Briarwood Reed
  19289, -- Darkmoon Card: Maelstrom
  19288, -- Darkmoon Card: Blue Dragon
  19287, -- Darkmoon Card: Heroism
  19290, -- Darkmoon Card: Twisting Nether
  13515, -- Ramstein's Lightning Bolts
  17774, -- Mark of the Chosen
  1404,  -- Tidal Charm
  4984,  -- Skull of Impending Doom
  11810, -- Force of Will
  11819, -- Second Wind
  13968, -- Eye of the Beast
  13966, -- Venomous Totem
  13209, -- Seal of the Dawn
  19812, -- Rune of the Dawn
  23206, -- Mark of the Champion
  18469, -- Royal Seal of Eldre'Thalas
  19120, -- Rune of Duty
  19343, -- Scrolls of Blinding Light
  11122, -- Carrot on a Stick
  19952, -- Gri'lek's Charm of Might
  19947, -- Nat Pagle's Broken Reel
  22954, -- Kiss of the Spider
  23001, -- Eye of Diminution
  23040, -- Slayer's Crest
  23046, -- The Restrained Essence of Sapphiron
  19930, -- Mar'li's Eye
  19991, -- Devilsaur Eye
  21625, -- Scarab Brooch
  21670, -- Badge of the Swarmguard
  21647, -- Fetish of Chitinous Spikes
  20130, -- Diamond Flask
  21180, -- Earthstrike
  13213, -- Smolderweb's Eye
  13171, -- Smokey's Lighter
  11904, -- Piccolo of the Flaming Fire
  19949, -- Zandalarian Hero Medallion
  19950, -- Zandalarian Hero Charm
  19948, -- Zandalarian Hero Badge
  19339, -- Mind Quickening Gem
  19340, -- Rune of Metamorphosis
  19336, -- Arcane Infused Gem
  19337, -- The Black Book
  19344, -- Natural Alignment Crystal
  19345, -- Aegis of Preservation
  18470, -- Royal Seal of Eldre'Thalas (Priest)
  18471, -- Royal Seal of Eldre'Thalas (Rogue)
  18472, -- Royal Seal of Eldre'Thalas (Warlock)
  18473  -- Royal Seal of Eldre'Thalas (Warrior)
}

-- every n-th showcased trinket is put on a cooldown that started COOLDOWN_ELAPSED seconds ago
local COOLDOWN_EVERY = 4
local COOLDOWN_ELAPSED = 30
local COOLDOWN_DURATION = 120

local active = false
-- true while the changeMenu variant is on: every inventory type resolves to the trinkets
local everyInventoryType = false
local showcaseItems
local cooldowns
local originalGetItemsForInventoryType
local originalGetItemCooldown

--[[
  Build the item records the way itemManager.GetItemsForInventoryType returns them, from the
  trinkets the client knows. GetItemInfoInstant answers without the item cache; the name and
  quality come from GetItemInfo when it is cached and stay placeholders otherwise

  @param {number} itemCap
    How many trinkets to collect at most

  @return {table} items
  @return {table} cooldowns
    itemId -> { startTime, duration } for the trinkets on cooldown
]]--
local function BuildShowcaseItems(itemCap)
  local items = {}
  local itemCooldowns = {}

  for _, itemId in ipairs(TRINKET_ITEM_IDS) do
    if #items >= itemCap then break end

    local _, _, _, equipSlot, icon = C_Item.GetItemInfoInstant(itemId)

    if equipSlot == RGGM_CONSTANTS.TRINKET_MENU_INV_TYPE then
      local itemName, _, itemRarity = C_Item.GetItemInfo(itemId)

      items[#items + 1] = {
        bag = nil,
        slot = nil,
        name = itemName or ("item:" .. itemId),
        icon = icon,
        id = itemId,
        equipSlot = equipSlot,
        quality = itemRarity or RGGM_CONSTANTS.ITEMQUALITY.rare,
        enchantId = nil
      }

      if #items % COOLDOWN_EVERY == 0 then
        itemCooldowns[itemId] = { GetTime() - COOLDOWN_ELAPSED, COOLDOWN_DURATION }
      end
    else
      mod.logger.LogDebug(me.tag, "Skipping unknown or non-trinket item " .. itemId)
    end
  end

  return items, itemCooldowns
end

--[[
  Route the trinket inventory type - or every inventory type in the changeMenu variant - to the
  showcase items, everything else to the real lookup

  @param {table} inventoryType

  @return {table}
]]--
local function GetItemsForInventoryType(inventoryType)
  if everyInventoryType then
    return showcaseItems
  end

  if type(inventoryType) == "table" then
    for _, entry in ipairs(inventoryType) do
      if entry == RGGM_CONSTANTS.TRINKET_MENU_INV_TYPE then
        return showcaseItems
      end
    end
  end

  return originalGetItemsForInventoryType(inventoryType)
end

--[[
  Answer the showcased cooldowns, everything else from the real api

  @param {number} itemId

  @return {number} startTime
  @return {number} duration
  @return {number} enable
]]--
local function GetItemCooldown(itemId)
  local cooldown = cooldowns[itemId]

  if cooldown ~= nil then
    return cooldown[1], cooldown[2], 1
  end

  return originalGetItemCooldown(itemId)
end

--[[
  Feed the showcase into the trinketMenu, or into the changeMenu of every gearSlot

  @param {boolean} forEveryInventoryType
    true for the changeMenu variant
]]--
function me.Enable(forEveryInventoryType)
  everyInventoryType = forEveryInventoryType == true

  local itemCap = RGGM_CONSTANTS.TRINKET_MENU_DEFAULT_SLOT_AMOUNT

  if everyInventoryType then
    itemCap = RGGM_CONSTANTS.GEAR_BAR_CHANGE_SLOT_AMOUNT_ITEMS
  end

  showcaseItems, cooldowns = BuildShowcaseItems(itemCap)

  originalGetItemsForInventoryType = mod.itemManager.GetItemsForInventoryType
  originalGetItemCooldown = C_Container.GetItemCooldown
  mod.itemManager.GetItemsForInventoryType = GetItemsForInventoryType
  C_Container.GetItemCooldown = GetItemCooldown
  active = true

  if mod.configuration.IsTrinketMenuEnabled() then
    mod.trinketMenu.UpdateTrinketMenu()
  end

  if everyInventoryType then
    print("|cFF00FFB0GearMenu:|r changeMenu showcase on - " .. #showcaseItems .. " trinkets on every "
      .. "gearSlot, hover one; `/rggm showcase changemenu` again restores the bags")
  else
    print("|cFF00FFB0GearMenu:|r trinket showcase on - " .. #showcaseItems .. " trinkets, "
      .. "`/rggm showcase trinkets` again restores the bags")
  end
end

--[[
  Restore the real lookups and re-render the bags
]]--
function me.Disable()
  mod.itemManager.GetItemsForInventoryType = originalGetItemsForInventoryType
  C_Container.GetItemCooldown = originalGetItemCooldown
  originalGetItemsForInventoryType = nil
  originalGetItemCooldown = nil
  showcaseItems = nil
  cooldowns = nil
  active = false
  everyInventoryType = false

  if mod.configuration.IsTrinketMenuEnabled() then
    mod.trinketMenu.UpdateTrinketMenu()
  end

  print("|cFF00FFB0GearMenu:|r showcase off - the menus show the bags again")
end

--[[
  Toggle the showcase; either variant turns a running one off. The trinketMenu variant needs
  the trinketMenu to be enabled - it is the real menu that renders

  @param {boolean} forEveryInventoryType
    true for the changeMenu variant
]]--
function me.Toggle(forEveryInventoryType)
  if active then
    me.Disable()

    return
  end

  if not forEveryInventoryType and not mod.configuration.IsTrinketMenuEnabled() then
    print("|cFF00FFB0GearMenu:|r enable the TrinketMenu in the settings first - the showcase renders through it")

    return
  end

  me.Enable(forEveryInventoryType)
end
