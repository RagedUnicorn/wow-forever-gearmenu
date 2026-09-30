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
  Spec for the action-button look of the slots in gui/SlotStyle.lua: which atlases a slot and an
  inset icon frame are dressed in, how the mask and frame art scale with the slot size, the
  slot size each slot type is built with, and the click feedback flash.

  The spec pins the decisions, not the pixel layout: fake buttons and textures record the atlas,
  size and visibility they are given. C_Texture.GetAtlasInfo reports the size of the mask atlas
  and C_Timer.After keeps its callbacks so a test can run them.
]]--

local wowStubs = require("WowStubs")

local MASK_ATLAS = "UI-HUD-ActionBar-IconFrame-Mask"
-- the width of the mask atlas on a 45 px template button
local MASK_ATLAS_WIDTH = 64
local SLOT_SIZE = 36
local RED = { 1, 0, 0 }

--[[
  A fake texture (or mask texture) recording what it is given

  @param {string} layer

  @return {table}
]]--
local function CreateFakeTexture(layer)
  local texture = { layer = layer, shown = true, alpha = 1, masks = {}, points = {} }

  function texture:SetAtlas(atlas) self.atlas = atlas end
  function texture:SetAllPoints(relativeTo) self.allPoints = relativeTo end
  function texture:ClearAllPoints() self.points = {} end
  function texture:SetPoint(point, relativeTo) self.points[point] = relativeTo end
  function texture:SetSize(width, height) self.size = { width, height } end
  function texture:SetBlendMode(blendMode) self.blendMode = blendMode end
  function texture:SetVertexColor(r, g, b) self.vertexColor = { r, g, b } end
  function texture:SetAlpha(alpha) self.alpha = alpha end
  function texture:Show() self.shown = true end
  function texture:Hide() self.shown = false end
  function texture:AddMaskTexture(mask) self.masks[#self.masks + 1] = mask end

  return texture
end

--[[
  A fake Button that creates fake textures and keeps its normal, pushed and highlight art

  @param {string} name
  @param {table} parent

  @return {table}
]]--
local function CreateFakeButton(name, parent)
  local button = { name = name, parent = parent, art = {} }

  button.CreateTexture = function(_, _, layer) return CreateFakeTexture(layer) end
  button.CreateMaskTexture = function() return CreateFakeTexture("MASK") end

  for _, kind in ipairs({ "Normal", "Pushed", "Highlight" }) do
    button["Set" .. kind .. "Atlas"] = function(self, atlas)
      self.art[kind] = CreateFakeTexture("ARTWORK")
      self.art[kind]:SetAtlas(atlas)
    end
    button["Get" .. kind .. "Texture"] = function(self) return self.art[kind] end
  end

  return button
end

describe("SlotStyle", function()
  local slotStyle
  local atlasInfo
  local atlasLookups
  local timers
  local warnings
  local overlays
  local eventSetups
  local previous
  local restore

  local function CreateStyledSlot(size)
    local slot = CreateFakeButton("GM_TestSlot")

    slot.itemTexture = CreateFakeTexture("ARTWORK")
    slotStyle.ApplySlotStyle(slot, size or SLOT_SIZE)

    return slot
  end

  local function RunTimers()
    local pending = timers
    timers = {}

    for _, timer in ipairs(pending) do timer.callback() end
  end

  before_each(function()
    atlasInfo = { width = MASK_ATLAS_WIDTH, height = MASK_ATLAS_WIDTH }
    atlasLookups = 0
    timers = {}
    warnings = 0
    overlays = {}
    eventSetups = {}

    previous = {}
    for _, name in ipairs({
      "logger", "gearBar", "gearBarChangeMenu", "trinketMenu", "uiHelper", "cooldown", "configuration"
    }) do
      previous[name] = rggm[name]
    end

    rggm.logger = { LogWarn = function() warnings = warnings + 1 end }
    rggm.uiHelper = {
      CreateItemTexture = function(slot) slot.itemTexture = CreateFakeTexture("ARTWORK") end
    }
    rggm.cooldown = {
      CreateCooldownOverlay = function(slot, frameName, size)
        local overlay = { slot = slot, frameName = frameName, size = size }
        overlays[#overlays + 1] = overlay

        return overlay
      end
    }
    rggm.gearBar = {
      CreateGearSlotBase = function(gearBarFrame, gearBar, position, template)
        local gearSlot = CreateFakeButton("GM_GearSlot" .. position, gearBarFrame)

        gearSlot.template = template
        gearSlot.gearBar = gearBar
        rggm.uiHelper.CreateItemTexture(gearSlot)

        return gearSlot
      end,
      SetupEvents = function(slot) eventSetups[#eventSetups + 1] = { "gearBar", slot } end
    }
    rggm.gearBarChangeMenu = {
      SetupEvents = function(slot) eventSetups[#eventSetups + 1] = { "gearBarChangeMenu", slot } end
    }
    rggm.trinketMenu = {
      SetupEvents = function(slot) eventSetups[#eventSetups + 1] = { "trinketMenu", slot } end
    }
    rggm.configuration = { GetTrinketMenuSlotSize = function() return 50 end }

    restore = wowStubs.install({
      CreateFrame = function(_, name, parent) return CreateFakeButton(name, parent) end,
      C_Texture = {
        GetAtlasInfo = function(atlas)
          assert.are.equal(MASK_ATLAS, atlas)
          atlasLookups = atlasLookups + 1
          return atlasInfo
        end
      },
      C_Timer = {
        After = function(duration, callback)
          timers[#timers + 1] = { duration = duration, callback = callback }
        end
      }
    })

    -- fresh module state: the mask size modifier is resolved once per load
    dofile("gui/SlotStyle.lua")
    slotStyle = rggm.slotStyle
  end)

  after_each(function()
    restore()

    for name, module in pairs(previous) do
      rggm[name] = module
    end
  end)

  describe("ApplySlotStyle", function()
    it("dresses the slot in the frame, pushed and hover atlases of the action button", function()
      local slot = CreateStyledSlot()

      assert.are.equal("UI-HUD-ActionBar-IconFrame", slot:GetNormalTexture().atlas)
      assert.are.equal("UI-HUD-ActionBar-IconFrame-Down", slot:GetPushedTexture().atlas)
      assert.are.equal("UI-HUD-ActionBar-IconFrame-Mouseover", slot:GetHighlightTexture().atlas)
    end)

    it("puts the slot background beneath the icon over the whole slot", function()
      local slot = CreateStyledSlot()

      assert.are.equal("UI-HUD-ActionBar-IconFrame-Background", slot.slotBackground.atlas)
      assert.are.equal("BACKGROUND", slot.slotBackground.layer)
      assert.are.equal(slot, slot.slotBackground.allPoints)
    end)

    it("rounds the item icon with the mask centred on it", function()
      local slot = CreateStyledSlot()

      assert.are.equal(MASK_ATLAS, slot.itemTextureMask.atlas)
      assert.are.equal(slot.itemTexture, slot.itemTextureMask.points.CENTER)
      assert.are.same({ slot.itemTextureMask }, slot.itemTexture.masks)
    end)

    it("prepares a hidden, additive copy of the hover glow for the click flash", function()
      local slot = CreateStyledSlot()

      assert.are.equal("UI-HUD-ActionBar-IconFrame-Mouseover", slot.flashTexture.atlas)
      assert.are.equal("ADD", slot.flashTexture.blendMode)
      assert.are.equal("OVERLAY", slot.flashTexture.layer)
      assert.is_false(slot.flashTexture.shown)
    end)
  end)

  describe("UpdateSlotTextureAttributes", function()
    it("scales the mask with the atlas proportions of the template button", function()
      local slot = CreateStyledSlot()
      local maskSize = SLOT_SIZE * (MASK_ATLAS_WIDTH / RGGM_CONSTANTS.SLOT_TEMPLATE_BUTTON_SIZE)

      assert.are.same({ maskSize, maskSize }, slot.itemTextureMask.size)
    end)

    it("lays every frame texture top left and slightly wider than the slot", function()
      local slot = CreateStyledSlot()
      local frameSize = { SLOT_SIZE * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, SLOT_SIZE }

      for _, texture in ipairs({
        slot:GetNormalTexture(), slot:GetPushedTexture(), slot:GetHighlightTexture(), slot.flashTexture
      }) do
        assert.are.same(frameSize, texture.size)
        assert.are.equal(slot, texture.points.TOPLEFT)
      end
    end)

    it("lays the Quick Keybind Mode highlight of a gearSlot like the hover highlight", function()
      local slot = CreateStyledSlot()
      local resized = 48

      slot.QuickKeybindHighlightTexture = CreateFakeTexture("HIGHLIGHT")
      slotStyle.UpdateSlotTextureAttributes(slot, resized)

      assert.are.same(slot:GetHighlightTexture().size, slot.QuickKeybindHighlightTexture.size)
      assert.are.same({ resized * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, resized },
        slot.QuickKeybindHighlightTexture.size)
    end)

    it("resolves the mask atlas size only once", function()
      local slot = CreateStyledSlot()

      slotStyle.UpdateSlotTextureAttributes(slot, 24)
      slotStyle.UpdateSlotTextureAttributes(slot, 64)

      assert.are.equal(1, atlasLookups)
    end)

    it("falls back to a mask the size of the slot and warns when the atlas is unknown", function()
      atlasInfo = nil

      local slot = CreateStyledSlot()

      assert.are.same({ SLOT_SIZE, SLOT_SIZE }, slot.itemTextureMask.size)
      assert.are.equal(1, warnings)
    end)
  end)

  describe("slot creation", function()
    it("builds a secure, key-bindable gearSlot at the gearSlot size of its gearBar", function()
      local gearBar = { id = 1, gearSlotSize = 42 }
      local gearSlot = slotStyle.CreateGearSlot({}, gearBar, 3)

      assert.are.equal("QuickKeybindButtonTemplate, SecureActionButtonTemplate", gearSlot.template)
      assert.are.same({ 42 * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, 42 }, gearSlot:GetNormalTexture().size)
      assert.are.equal(gearSlot.cooldownOverlay, overlays[1])
      assert.are.equal(42, overlays[1].size)
      assert.are.same({ { "gearBar", gearSlot } }, eventSetups)
    end)

    it("builds a changeSlot at the default changeMenu slot size", function()
      local changeSlot = slotStyle.CreateChangeSlot({}, 2)

      assert.are.equal(RGGM_CONSTANTS.ELEMENT_GEAR_BAR_CHANGE_SLOT .. 2, changeSlot.name)
      assert.are.equal(RGGM_CONSTANTS.GEAR_BAR_CHANGE_DEFAULT_SLOT_SIZE, overlays[1].size)
      assert.are.same({ { "gearBarChangeMenu", changeSlot } }, eventSetups)
    end)

    it("builds a trinketMenuSlot at the configured trinketMenu slot size", function()
      local trinketMenuSlot = slotStyle.CreateTrinketSlot({}, 4)

      assert.are.equal(RGGM_CONSTANTS.ELEMENT_TRINKET_MENU_SLOT .. 4, trinketMenuSlot.name)
      assert.are.equal(50, overlays[1].size)
      assert.are.same({ 50 * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, 50 }, trinketMenuSlot:GetNormalTexture().size)
      assert.are.same({ { "trinketMenu", trinketMenuSlot } }, eventSetups)
    end)
  end)

  describe("FlashSlot", function()
    it("shows the tinted glow and mutes the hover highlight meanwhile", function()
      local slot = CreateStyledSlot()

      slotStyle.FlashSlot(slot, RED, 0.3)

      assert.is_true(slot.flashTexture.shown)
      assert.are.same(RED, slot.flashTexture.vertexColor)
      assert.are.equal(0, slot:GetHighlightTexture().alpha)
      assert.are.equal(0.3, timers[1].duration)
    end)

    it("hides the glow and restores the hover highlight once the flash ran out", function()
      local slot = CreateStyledSlot()

      slotStyle.FlashSlot(slot, RED, 0.3)
      RunTimers()

      assert.is_false(slot.flashTexture.shown)
      assert.are.equal(1, slot:GetHighlightTexture().alpha)
    end)

    it("keeps a newer flash showing when the timer of an older one runs out", function()
      local slot = CreateStyledSlot()

      slotStyle.FlashSlot(slot, RED, 0.3)
      local olderTimer = timers[1]
      slotStyle.FlashSlot(slot, { 0, 1, 0 }, 0.3)

      olderTimer.callback()

      assert.is_true(slot.flashTexture.shown)
      assert.are.equal(0, slot:GetHighlightTexture().alpha)

      timers[2].callback()

      assert.is_false(slot.flashTexture.shown)
      assert.are.equal(1, slot:GetHighlightTexture().alpha)
    end)
  end)

  describe("ApplyInsetSlotStyle", function()
    it("rounds the inset icon with the slot mask and frames it with the slot frame art", function()
      local frame = CreateFakeButton("GM_TestCombatQueueSlot")
      local size = 20

      frame.icon = CreateFakeTexture("ARTWORK")
      slotStyle.ApplyInsetSlotStyle(frame, size)

      assert.are.equal(MASK_ATLAS, frame.iconMask.atlas)
      assert.are.same({ frame.iconMask }, frame.icon.masks)
      assert.are.equal("UI-HUD-ActionBar-IconFrame", frame.frameTexture.atlas)
      assert.are.equal("OVERLAY", frame.frameTexture.layer)
      assert.are.same({ size * RGGM_CONSTANTS.SLOT_FRAME_WIDTH_MODIFIER, size }, frame.frameTexture.size)

      local maskSize = size * (MASK_ATLAS_WIDTH / RGGM_CONSTANTS.SLOT_TEMPLATE_BUTTON_SIZE)

      assert.are.same({ maskSize, maskSize }, frame.iconMask.size)
    end)
  end)
end)
