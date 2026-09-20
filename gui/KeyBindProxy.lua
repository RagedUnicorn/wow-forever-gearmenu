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

-- luacheck: globals CreateFrame UIParent InCombatLockdown

--[[
  The keyBindProxy (GM_KeyBindProxy) module owns the hidden secure buttons that GearMenu's key
  bindings target.

  A key can only reach a SecureActionButtonTemplate through a "CLICK <FrameName>:<Button>" binding
  action, and Bindings.xml can only declare actions whose frame names are known ahead of time. The
  real gearSlot frames carry the random id of their gearBar in their name, so they can never be
  declared. Instead one hidden proxy button exists for every possible gearSlot -
  MAX_GEAR_BARS x MAX_GEAR_BAR_SLOTS of them, named GM_KeyBindBar<bindIndex>Slot<position> - and
  Bindings.xml declares exactly those CLICK actions. Every proxy runs the same "/use <slotId>" macro
  as the gearSlot configured at (bindIndex, position); a proxy without a slot behind it has no
  action and a key bound to it does nothing.

  Whenever the configuration changes (bar or slot added, removed, re-typed, profile applied) the
  proxies are re-pointed - never re-bound. Secure attributes cannot change during combat lockdown,
  so a re-point requested in combat is deferred to PLAYER_REGEN_ENABLED (FlushPending). The same
  goes for the initial setup after a /reload in combat.

  The binding names shown in Settings > Keybindings (BINDING_HEADER_, PREFACE_ and BINDING_NAME_
  globals) are set from the localization at file load, before ADDON_LOADED rebuilds the list.
]]--

local mod = rggm
local me = {}
mod.keyBindProxy = me

me.tag = "KeyBindProxy"

-- the proxy buttons keyed [bindIndex][position]
local proxies = {}
-- whether the proxy buttons have been created
local isSetUp = false
-- set when Setup was requested in combat; flushed on leaving combat
local pendingSetup = false
-- set when a re-point was requested in combat; flushed on leaving combat
local pendingUpdate = false
-- set when a useOnKeyDown update was requested in combat; flushed on leaving combat
local pendingClickHandler = false

--[[
  The frame name of the proxy for a gearSlot position on a gearBar

  @param {number} bindIndex
  @param {number} position

  @return {string}
]]--
function me.GetProxyName(bindIndex, position)
  return string.format(RGGM_CONSTANTS.ELEMENT_KEY_BIND_PROXY_NAME, bindIndex, position)
end

--[[
  The binding action a key is bound to for a gearSlot position on a gearBar. The single place
  the action string is built - it has to match the names declared in Bindings.xml.

  @param {number} bindIndex
  @param {number} position

  @return {string}
]]--
function me.GetProxyAction(bindIndex, position)
  return string.format(RGGM_CONSTANTS.KEY_BIND_PROXY_ACTION, bindIndex, position)
end

--[[
  Set the globals the game's Keybindings list reads for the actions Bindings.xml declares: the
  category header, one text row per gearBar and the name of every proxy action. Positional names
  ("Gear Bar 2 - Slot 3") on purpose - the list is only rebuilt on ADDON_LOADED / reload, so a
  display name could not follow a gearBar rename.
]]--
function me.SetupBindingNames()
  _G[RGGM_CONSTANTS.KEY_BIND_CATEGORY] = rggm.L["keybind_category"]

  for bindIndex = 1, RGGM_CONSTANTS.MAX_GEAR_BARS do
    _G[string.format(RGGM_CONSTANTS.KEY_BIND_BAR_PREFACE, bindIndex)] =
      string.format(rggm.L["keybind_bar_preface"], bindIndex)

    for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      _G["BINDING_NAME_" .. me.GetProxyAction(bindIndex, position)] =
        string.format(rggm.L["keybind_slot_name"], bindIndex, position)
    end
  end
end

--[[
  @return {boolean}
    whether the proxy buttons have been created
]]--
function me.IsSetUp()
  return isSetUp
end

--[[
  @return {boolean}
    whether a re-point is waiting for the end of combat
]]--
function me.HasPendingUpdate()
  return pendingUpdate
end

--[[
  @param {number} bindIndex
  @param {number} position

  @return {table | nil}
    the proxy button, nil before Setup ran
]]--
function me.GetProxy(bindIndex, position)
  return proxies[bindIndex] and proxies[bindIndex][position]
end

--[[
  Create one hidden proxy button

  @param {number} bindIndex
  @param {number} position

  @return {table}
    the created button
]]--
local function CreateProxy(bindIndex, position)
  local proxy = CreateFrame("Button", me.GetProxyName(bindIndex, position), UIParent, "SecureActionButtonTemplate")
  --[[
    Register both phases of the click. The ui engine executes the secure action of a button in
    one direction only - chosen by the useOnKeyDown attribute - and a button registered for one
    direction only is unreachable for a binding dispatched in the other. useOnKeyDown maps the
    fastpress option onto that, exactly like the real gearSlots (gui/GearBar.lua SetupEvents)
  ]]--
  proxy:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  proxy:SetAttribute("useOnKeyDown", mod.configuration.IsFastPressEnabled())
  -- insecure feedback on the visible gearSlot; the secure action itself runs on this button
  proxy:SetScript("PreClick", function(_, button, down)
    me.OnProxyClick(bindIndex, position, button, down)
  end)
  proxy:Hide()

  return proxy
end

--[[
  PreClick of a proxy - a key bound to it was pressed. The secure "/use" runs on the hidden
  proxy, so the visible gearSlot would show nothing; forward the press to the gearSlot at
  (bindIndex, position) for the same insecure click feedback a mouse click gives (gui/GearBar.lua
  GearSlotOnKeyPress). Fires for both click phases like the gearSlot's own PreClick.

  @param {number} bindIndex
  @param {number} position
  @param {string} button
  @param {boolean} down
]]--
function me.OnProxyClick(bindIndex, position, button, down)
  mod.logger.LogDebug(me.tag, "Key press on " .. me.GetProxyName(bindIndex, position)
    .. " (" .. tostring(button) .. ", down=" .. tostring(down) .. ")")

  for _, gearBar in pairs(mod.gearBarManager.GetGearBars()) do
    if gearBar.bindIndex == bindIndex then
      local uiGearBar = mod.gearBarStorage.GetGearBars()[gearBar.id]
      local uiGearSlot = uiGearBar and uiGearBar.gearSlotReferences[position]

      if uiGearSlot ~= nil then
        mod.gearBar.GearSlotOnKeyPress(uiGearSlot, button, down)
      end

      return
    end
  end
end

--[[
  Create all proxy buttons once and point them at the configured gearSlots. Secure attributes
  cannot be written during combat lockdown, so a setup requested in combat (a /reload mid-fight)
  is deferred to PLAYER_REGEN_ENABLED.
]]--
function me.Setup()
  if isSetUp then return end

  if InCombatLockdown() then
    mod.logger.LogWarn(me.tag, "Unable to create the key-bind proxies in combat - deferred until combat ends")
    pendingSetup = true

    return
  end

  pendingSetup = false

  for bindIndex = 1, RGGM_CONSTANTS.MAX_GEAR_BARS do
    proxies[bindIndex] = {}

    for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      proxies[bindIndex][position] = CreateProxy(bindIndex, position)
    end
  end

  isSetUp = true
  mod.logger.LogDebug(me.tag, "Created " .. RGGM_CONSTANTS.MAX_GEAR_BARS * RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS
    .. " key-bind proxies")

  me.Update()
end

--[[
  The slotId every proxy should run "/use" for, derived from the gearBars. Pure - headless-tested.

  @param {table} gearBars
    the gearBars as returned by gearBarManager.GetGearBars

  @return {table}
    { [bindIndex] = { [position] = slotId } } - only the proxies that have a slot behind them
]]--
function me.ComputeMapping(gearBars)
  local mapping = {}

  for _, gearBar in pairs(gearBars) do
    if gearBar.bindIndex ~= nil then
      mapping[gearBar.bindIndex] = mapping[gearBar.bindIndex] or {}

      for position, gearSlot in pairs(gearBar.slots) do
        if gearSlot.slotId ~= nil then
          mapping[gearBar.bindIndex][position] = gearSlot.slotId
        end
      end
    end
  end

  return mapping
end

--[[
  Point every proxy at the gearSlot configured at its (bindIndex, position) - the same
  "/use <slotId>" macro the real gearSlot runs (see gui/GearBar.lua CreateGearSlotBase for why a
  macro and not the secure item action) - and clear the proxies that have no slot behind them.
  Idempotent: an attribute is only re-written when its value changed. In combat the re-point is
  deferred to PLAYER_REGEN_ENABLED; a call before Setup is a no-op (Setup ends with an Update).
]]--
function me.Update()
  if not isSetUp then return end

  if InCombatLockdown() then
    pendingUpdate = true

    return
  end

  pendingUpdate = false

  local mapping = me.ComputeMapping(mod.gearBarManager.GetGearBars())
  local changed = 0

  for bindIndex = 1, RGGM_CONSTANTS.MAX_GEAR_BARS do
    for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      local proxy = proxies[bindIndex][position]
      local slotId = mapping[bindIndex] and mapping[bindIndex][position]

      if slotId ~= nil then
        local macrotext = "/use " .. slotId

        if proxy:GetAttribute("macrotext") ~= macrotext then
          proxy:SetAttribute("type", "macro")
          proxy:SetAttribute("macrotext", macrotext)
          proxy:SetAttribute("slotId", slotId)
          changed = changed + 1
        end
      elseif proxy:GetAttribute("type") ~= nil then
        proxy:SetAttribute("type", nil)
        proxy:SetAttribute("macrotext", nil)
        proxy:SetAttribute("slotId", nil)
        changed = changed + 1
      end
    end
  end

  if changed > 0 then
    mod.logger.LogDebug(me.tag, "Re-pointed " .. changed .. " key-bind proxies")
  end
end

--[[
  Mirror the fastpress option onto the useOnKeyDown attribute of every proxy (see CreateProxy).
  Deferred to PLAYER_REGEN_ENABLED in combat.
]]--
function me.UpdateClickHandler()
  if not isSetUp then return end

  if InCombatLockdown() then
    pendingClickHandler = true

    return
  end

  pendingClickHandler = false

  for bindIndex = 1, RGGM_CONSTANTS.MAX_GEAR_BARS do
    for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      proxies[bindIndex][position]:SetAttribute("useOnKeyDown", mod.configuration.IsFastPressEnabled())
    end
  end
end

--[[
  Run whatever was deferred during combat. Invoked once the player leaves combat.
]]--
function me.FlushPending()
  if InCombatLockdown() then return end

  if pendingSetup then
    me.Setup() -- ends with an Update
  end

  if pendingUpdate then
    me.Update()
  end

  if pendingClickHandler then
    me.UpdateClickHandler()
  end
end

me.SetupBindingNames()
