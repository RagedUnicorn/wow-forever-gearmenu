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
  The single look of every GearMenu slot - the gearSlots of a gearBar, the changeSlots of the
  changeMenu and the trinketMenuSlots: the style of the game's own action bar buttons. The frame,
  pushed and hover art are the UI-HUD-ActionBar-IconFrame atlases the Forever action bar is built
  from (Blizzard_ActionBar/Mainline/ActionButtonTemplate.xml), the item icon fills the slot and is
  rounded by the matching mask, the slot background shows through the rounded corners and the
  cooldown swipe (gui/Cooldown.lua) sits inside the frame. The template is drawn for a 45 px
  button; every measure is scaled to the configurable slot size instead of using the atlas sizes
  so the 24 - 64 px slots keep the proportions of the template.
]]--

-- luacheck: globals CreateFrame C_Texture

local mod = rggm
local me = {}

mod.slotStyle = me

me.tag = "SlotStyle"

local SLOT_FRAME_ATLAS = "UI-HUD-ActionBar-IconFrame"
local SLOT_FRAME_PUSHED_ATLAS = "UI-HUD-ActionBar-IconFrame-Down"
local SLOT_FRAME_HIGHLIGHT_ATLAS = "UI-HUD-ActionBar-IconFrame-Mouseover"
local SLOT_BACKGROUND_ATLAS = "UI-HUD-ActionBar-IconFrame-Background"
local SLOT_ICON_MASK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mask"

-- the mask size per px of slot size, resolved once from the atlas (see GetMaskSizeModifier)
local maskSizeModifier

--[[
  The mask atlas is larger than the icon it rounds: its white area does not fill the atlas,
  so the template leaves the mask at the atlas size on its 45 px button (the 30 px
  SmallActionButtonTemplate even keeps it at 45). Sizing the mask to the icon shrinks the
  visible icon and leaves a dark gap to the frame. Scale the atlas size with the slot instead;
  fall back to the slot size should the atlas be unknown to the client

  @return {number}
]]--
local function GetMaskSizeModifier()
  if maskSizeModifier == nil then
    local atlasInfo = C_Texture.GetAtlasInfo(SLOT_ICON_MASK_ATLAS)

    if atlasInfo ~= nil and atlasInfo.width ~= nil and atlasInfo.width > 0 then
      maskSizeModifier = atlasInfo.width / RGGM_CONSTANTS.SLOT_TEMPLATE_BUTTON_SIZE
    else
      mod.logger.LogWarn(me.tag, "Unknown atlas " .. SLOT_ICON_MASK_ATLAS .. " - sizing the icon mask to the slot")
      maskSizeModifier = 1
    end
  end

  return maskSizeModifier
end

--[[
  Create a single gearSlot. Note that a gearSlot inherits from the SecureActionButtonTemplate to enable the usage
  of clicking items. Because of SetAttribute this function CANNOT be executed while in combat. Callers of this function
  need to check combatState before calling.

  @param {table} gearBarFrame
    The gearBarFrame where the gearSlot gets attached to
  @param {table} gearBar
  @param {number} position
    Position on the gearBar

  @return {table}
    The created gearSlot
]]--
function me.CreateGearSlot(gearBarFrame, gearBar, position)
  local gearSlot = mod.gearBar.CreateGearSlotBase(
    gearBarFrame,
    gearBar,
    position,
    "QuickKeybindButtonTemplate, SecureActionButtonTemplate"
  )

  me.ApplySlotStyle(gearSlot, gearBar.gearSlotSize)
  gearSlot.cooldownOverlay = mod.cooldown.CreateCooldownOverlay(
    gearSlot,
    RGGM_CONSTANTS.ELEMENT_SLOT_COOLDOWN_FRAME,
    gearBar.gearSlotSize
  )

  mod.gearBar.SetupEvents(gearSlot)

  return gearSlot
end

--[[
  Create a single changeSlot

  @param {table} changeMenuFrame
  @param {number} position

  @return {table}
    The created changeSlot
]]--
function me.CreateChangeSlot(changeMenuFrame, position)
  local changeSlot = CreateFrame(
    "Button",
    RGGM_CONSTANTS.ELEMENT_GEAR_BAR_CHANGE_SLOT .. position,
    changeMenuFrame
  )

  mod.uiHelper.CreateItemTexture(changeSlot)
  me.ApplySlotStyle(changeSlot, RGGM_CONSTANTS.GEAR_BAR_CHANGE_DEFAULT_SLOT_SIZE)
  changeSlot.cooldownOverlay = mod.cooldown.CreateCooldownOverlay(
    changeSlot,
    RGGM_CONSTANTS.ELEMENT_SLOT_COOLDOWN_FRAME,
    RGGM_CONSTANTS.GEAR_BAR_CHANGE_DEFAULT_SLOT_SIZE
  )

  mod.gearBarChangeMenu.SetupEvents(changeSlot)

  return changeSlot
end

--[[
  @param {table} trinketMenuFrame
    The trinketMenuFrame to attach the created slot to
  @param {number} position
    Position withing the trinketMenu

  @return {table}
    The created trinketMenuSlot
]]--
function me.CreateTrinketSlot(trinketMenuFrame, position)
  local trinketMenuSlot = CreateFrame(
    "Button",
    RGGM_CONSTANTS.ELEMENT_TRINKET_MENU_SLOT .. position,
    trinketMenuFrame
  )
  local trinketMenuSlotSize = mod.configuration.GetTrinketMenuSlotSize()

  mod.uiHelper.CreateItemTexture(trinketMenuSlot)
  me.ApplySlotStyle(trinketMenuSlot, trinketMenuSlotSize)
  trinketMenuSlot.cooldownOverlay = mod.cooldown.CreateCooldownOverlay(
    trinketMenuSlot,
    RGGM_CONSTANTS.ELEMENT_SLOT_COOLDOWN_FRAME,
    trinketMenuSlotSize
  )

  mod.trinketMenu.SetupEvents(trinketMenuSlot)

  return trinketMenuSlot
end

--[[
  Dress a slot in the action-button look: the slot background beneath the item icon, the mask
  that rounds the icon, and the frame, pushed and hover atlases of the button. Expects the item
  icon to exist already (mod.uiHelper.CreateItemTexture)

  @param {table} slot
  @param {number} slotSize
]]--
function me.ApplySlotStyle(slot, slotSize)
  -- shows through the rounded corners of the masked icon (and behind an icon that is not set)
  slot.slotBackground = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
  slot.slotBackground:SetAtlas(SLOT_BACKGROUND_ATLAS)
  slot.slotBackground:SetAllPoints(slot)

  slot.itemTextureMask = slot:CreateMaskTexture()
  slot.itemTextureMask:SetAtlas(SLOT_ICON_MASK_ATLAS)
  slot.itemTextureMask:SetPoint("CENTER", slot.itemTexture)
  slot.itemTexture:AddMaskTexture(slot.itemTextureMask)

  slot:SetNormalAtlas(SLOT_FRAME_ATLAS)
  slot:SetPushedAtlas(SLOT_FRAME_PUSHED_ATLAS)
  slot:SetHighlightAtlas(SLOT_FRAME_HIGHLIGHT_ATLAS)

  me.UpdateSlotTextureAttributes(slot, slotSize)
end

--[[
  Lay a frame texture over the slot the way the template does: anchored to the top left and
  slightly wider than the button (the frame art is 46 x 45 on a 45 px button)

  @param {table} texture
    nil is accepted so optional textures (the Quick Keybind Mode highlight) can be passed as is
  @param {table} slot
  @param {number} slotSize
]]--
local function LayoutFrameTexture(texture, slot, slotSize)
  if texture == nil then return end

  texture:ClearAllPoints()
  texture:SetPoint("TOPLEFT", slot, "TOPLEFT")
  texture:SetSize(slotSize * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, slotSize)
end

--[[
  Scale the textures of a slot to its size. The item icon fills the slot and follows it on its
  own; the mask, the frame art and the highlights carry explicit sizes and are re-laid here

  @param {table} slot
  @param {number} slotSize
]]--
function me.UpdateSlotTextureAttributes(slot, slotSize)
  local maskSize = slotSize * GetMaskSizeModifier()

  slot.itemTextureMask:SetSize(maskSize, maskSize)

  LayoutFrameTexture(slot:GetNormalTexture(), slot, slotSize)
  LayoutFrameTexture(slot:GetPushedTexture(), slot, slotSize)
  LayoutFrameTexture(slot:GetHighlightTexture(), slot, slotSize)
  --[[
    gearSlots only: the Quick Keybind Mode highlight of the QuickKeybindButtonTemplate ships
    without anchors and uses the hover atlas - lay it out exactly like the hover highlight
  ]]--
  LayoutFrameTexture(slot.QuickKeybindHighlightTexture, slot, slotSize)
end
