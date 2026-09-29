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

-- luacheck: globals GetBindingKey SetBinding GetCurrentBindingSet SaveBindings InCombatLockdown
-- luacheck: globals Settings SettingsPanel QuickKeybindFrame

--[[
  The keyBind (GM_KeyBind) module reads and writes the key bindings of gearSlots.

  Keys are bound in the game's own ui - Settings > Keybindings (category "GearMenu") or Quick
  Keybind Mode by hovering a gearSlot - to the proxy actions of gui/KeyBindProxy.lua:
  "CLICK GM_KeyBindBar<bindIndex>Slot<position>:LeftButton". WoW's binding set is the single
  source of truth: the label on a gearSlot and in the configuration row is GetBindingKey of the
  slot's proxy action, refreshed on UPDATE_BINDINGS, and the slot's keyBinding field is only a
  mirror of it kept as the profile export payload.

  GearMenu itself writes bindings in three cases only: unbinding a slot from the configuration
  row, moving the keys of the slots that shift up when a slot is deleted, and applying a
  profile (clear every proxy action, bind the profile's keys). Setting or clearing a binding is a
  protected action during combat lockdown - the client refuses it without a Lua error - so every
  write goes through WhenOutOfCombat and is queued until PLAYER_REGEN_ENABLED when in combat.
]]--

local mod = rggm
local me = {}
mod.keyBind = me

me.tag = "KeyBind"

-- binding writes queued during combat lockdown, run in order by FlushPending
local pendingWrites = {}
-- whether the user was told about the deferral for the current combat
local deferralAnnounced = false

--[[
  Run a binding write now, or queue it until combat ends when InCombatLockdown. The user is told
  once per combat that the change is applied later.

  @param {function} write

  @return {boolean}
    true - if the write ran immediately
    false - if it was queued
]]--
function me.WhenOutOfCombat(write)
  if not InCombatLockdown() then
    write()

    return true
  end

  table.insert(pendingWrites, write)

  if not deferralAnnounced then
    deferralAnnounced = true
    mod.logger.PrintUserMessage(rggm.L["keybind_deferred_combat"])
  end

  return false
end

--[[
  Run the binding writes queued during combat, in order. Invoked once the player leaves combat.
]]--
function me.FlushPending()
  if InCombatLockdown() then return end

  deferralAnnounced = false

  if #pendingWrites == 0 then return end

  local queued = pendingWrites
  pendingWrites = {}

  mod.logger.LogInfo(me.tag, "Running " .. #queued .. " key binding change(s) deferred during combat")

  for _, write in ipairs(queued) do
    write()
  end
end

--[[
  @return {boolean}
    whether binding writes are waiting for the end of combat
]]--
function me.HasPendingWrites()
  return #pendingWrites > 0
end

--[[
  The keys bound to a gearSlot (up to two - the Keybindings list allows a primary and a
  secondary key per action)

  @param {table} gearBar
  @param {number} position

  @return {string | nil, string | nil}
]]--
function me.GetSlotKeys(gearBar, position)
  if gearBar == nil or gearBar.bindIndex == nil then return nil end

  return GetBindingKey(mod.keyBindProxy.GetProxyAction(gearBar.bindIndex, position))
end

--[[
  The primary key bound to a gearSlot - what the slot label and the configuration row show

  @param {table} gearBar
  @param {number} position

  @return {string | nil}
]]--
function me.GetSlotKeyBinding(gearBar, position)
  local key = me.GetSlotKeys(gearBar, position)

  return key
end

--[[
  Clear every key bound to an action

  @param {string} action

  @return {number}
    the amount of keys that were cleared
]]--
local function ClearActionKeys(action)
  local keys = { GetBindingKey(action) }

  for _, key in ipairs(keys) do
    SetBinding(key)
  end

  return #keys
end

--[[
  Bind a key to an action, replacing whatever the key was bound to. A refused bind (SetBinding
  returns false for a key the client does not accept) is logged and reported to the user.

  @param {string} key
  @param {string} action

  @return {boolean}
    whether the key was bound
]]--
local function BindKey(key, action)
  if SetBinding(key, action) then
    mod.logger.LogInfo(me.tag, "Bound " .. key .. " to " .. action)

    return true
  end

  mod.logger.LogWarn(me.tag, "Failed to bind " .. tostring(key) .. " to " .. action)
  mod.logger.PrintUserError(string.format(rggm.L["keybind_set_failed"], tostring(key)))

  return false
end

--[[
  Blizzard api for saving keybinds. If this is not called after a change the keyBinds are lost after
  a reload of WoW
]]--
function me.SaveBindings()
  mod.logger.LogInfo(me.tag, "Attempting to save bindings in - " .. GetCurrentBindingSet())
  SaveBindings(GetCurrentBindingSet())
end

--[[
  Unbind every key of a gearSlot. Ui entrypoint of the configuration row's unbind button

  @param {number} gearBarId
  @param {number} position
]]--
function me.UnsetKeyBinding(gearBarId, position)
  local gearBar = mod.gearBarManager.GetGearBar(gearBarId)

  if gearBar == nil or gearBar.bindIndex == nil or gearBar.slots[position] == nil then
    mod.logger.LogError(me.tag, "Unable to unbind - no gearSlot at position " .. tostring(position)
      .. " on gearBar with id: " .. tostring(gearBarId))

    return
  end

  local action = mod.keyBindProxy.GetProxyAction(gearBar.bindIndex, position)

  me.WhenOutOfCombat(function()
    if ClearActionKeys(action) > 0 then
      mod.logger.LogInfo(me.tag, "Unbound " .. action)
      me.SaveBindings()
    else
      mod.logger.LogInfo(me.tag, "GearSlot has no keybinding set. Nothing to reset")
    end

    me.RefreshKeyBindingLabels()
  end)
end

--[[
  After a gearSlot was removed from a gearBar the slots behind it moved up one position. Move
  their keys along - the keys of position p+1 become the keys of position p, from the removed
  position up to the last possible one - so every key keeps triggering the slot it was bound
  to (the same repair the former CheckKeyBindingSlots did against the slot frames).

  @param {number} gearBarId
  @param {number} position
    the position the slot was removed from
]]--
function me.OnGearSlotRemoved(gearBarId, position)
  local gearBar = mod.gearBarManager.GetGearBar(gearBarId)

  if gearBar == nil or gearBar.bindIndex == nil then return end

  local bindIndex = gearBar.bindIndex

  me.WhenOutOfCombat(function()
    local changed = false

    for current = position, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      local action = mod.keyBindProxy.GetProxyAction(bindIndex, current)
      local nextKeys = {}

      if current < RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS then
        nextKeys = { GetBindingKey(mod.keyBindProxy.GetProxyAction(bindIndex, current + 1)) }
      end

      if ClearActionKeys(action) > 0 then
        changed = true
      end

      for _, key in ipairs(nextKeys) do
        if BindKey(key, action) then
          changed = true
        end
      end
    end

    if changed then
      me.SaveBindings()
    end

    me.RefreshKeyBindingLabels()
  end)
end

--[[
  Clear the keys of every proxy action of a bindIndex. Invoked when a gearBar is removed so a
  later gearBar taking over the freed bindIndex does not inherit its keys.

  @param {number} bindIndex
]]--
function me.OnGearBarRemoved(bindIndex)
  if bindIndex == nil then return end

  me.WhenOutOfCombat(function()
    local changed = false

    for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
      if ClearActionKeys(mod.keyBindProxy.GetProxyAction(bindIndex, position)) > 0 then
        changed = true
      end
    end

    if changed then
      mod.logger.LogInfo(me.tag, "Cleared the keybindings of bindIndex " .. bindIndex)
      me.SaveBindings()
    end
  end)
end

--[[
  Clear the keys of every GearMenu proxy action. Used before applying a profile so the outgoing
  profile's keys do not linger on proxies the incoming profile leaves unbound. Keys bound to
  other actions are never touched.
]]--
function me.ClearGearBarKeyBindings()
  me.WhenOutOfCombat(function()
    local cleared = 0

    for bindIndex = 1, RGGM_CONSTANTS.MAX_GEAR_BARS do
      for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
        cleared = cleared + ClearActionKeys(mod.keyBindProxy.GetProxyAction(bindIndex, position))
      end
    end

    if cleared > 0 then
      mod.logger.LogInfo(me.tag, "Cleared " .. cleared .. " GearMenu keybinding(s)")
      me.SaveBindings()
    end
  end)
end

--[[
  Bind the keyBinding mirror of every configured gearSlot to its proxy action. Used after a
  profile is applied: the profile carries the key per slot but not WoW's binding set, so
  without this the keys would show nowhere and do nothing. Binds purely from configuration
  data, so it does not depend on the gearSlot ui frames and runs before the ReloadUI that
  follows a profile apply. Profile import validates the slots already; the numeric loop and
  the type checks keep a malformed slot table from ever reaching SetBinding regardless.
]]--
function me.ApplyGearBarKeyBindings()
  me.WhenOutOfCombat(function()
    local didBind = false

    for _, gearBar in pairs(mod.gearBarManager.GetGearBars()) do
      if gearBar.bindIndex ~= nil and type(gearBar.slots) == "table" then
        for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
          local gearSlot = gearBar.slots[position]

          if type(gearSlot) == "table" and type(gearSlot.keyBinding) == "string" and gearSlot.keyBinding ~= "" then
            if BindKey(gearSlot.keyBinding, mod.keyBindProxy.GetProxyAction(gearBar.bindIndex, position)) then
              didBind = true
            end
          end
        end
      end
    end

    if didBind then
      me.SaveBindings()
    end

    me.RefreshKeyBindingLabels()
  end)
end

--[[
  Bring everything that shows a key in line with WoW's binding set: the keyBinding mirror of
  every gearSlot, the labels on the gearSlots and the rows of the open gearBar configuration.
]]--
function me.RefreshKeyBindingLabels()
  for _, gearBar in pairs(mod.gearBarManager.GetGearBars()) do
    if type(gearBar.slots) == "table" then
      -- numeric loop - a position that is not an integer in range would raise in the proxy action format
      for position = 1, RGGM_CONSTANTS.MAX_GEAR_BAR_SLOTS do
        if type(gearBar.slots[position]) == "table" then
          mod.gearBarManager.SetSlotKeyBinding(gearBar.id, position, me.GetSlotKeyBinding(gearBar, position))
        end
      end
    end
  end

  mod.gearBar.UpdateGearBars(mod.gearBar.UpdateKeyBindingState)
  mod.gearBarConfigurationSubMenu.UpdateGearBarConfigurationMenu()
end

--[[
  Callback for the UPDATE_BINDINGS event - bindings changed, in GearMenu or anywhere else (the
  Keybindings list, Quick Keybind Mode, a binding set switch). Also run once at initialization.
]]--
function me.OnUpdateKeyBindings()
  mod.logger.LogDebug(me.tag, "UPDATE_BINDINGS event. Refreshing gearMenus keyBinding labels")
  me.RefreshKeyBindingLabels()
end

--[[
  Open Settings > Keybindings with the GearMenu section expanded. Ui entrypoint of the
  gearBar configuration
]]--
function me.OpenKeyBindingSettings()
  if Settings.KEYBINDINGS_CATEGORY_ID == nil then
    mod.logger.LogError(me.tag, "Keybindings settings category not available")

    return
  end

  local sectionName = _G[RGGM_CONSTANTS.KEY_BIND_CATEGORY]
  local category = SettingsPanel:GetCategory(Settings.KEYBINDINGS_CATEGORY_ID)
  local layout = SettingsPanel:GetLayout(category)

  -- expand the section before scrolling to it, the way Blizzard's ping system settings do
  for _, initializer in layout:EnumerateInitializers() do
    if initializer:GetName() == sectionName then
      initializer.data.expanded = true
      break
    end
  end

  Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID, sectionName)
end

--[[
  Close the settings and open Blizzard's Quick Keybind Mode, in which hovering a gearSlot and
  pressing a key binds it. Refused in combat - the mode writes bindings and shows the
  protected QuickKeybindFrame. Ui entrypoint of the gearBar configuration
]]--
function me.OpenQuickKeybindMode()
  if InCombatLockdown() then
    mod.logger.PrintUserError(rggm.L["gear_bar_configuration_quick_keybind_combat"])

    return
  end

  local skipTransitionBackToOpeningPanel = true
  SettingsPanel:Close(skipTransitionBackToOpeningPanel)
  QuickKeybindFrame:Show()
end

--[[
  Convert actual keybinding text to a shorter one to be displayed on top of action buttons

  @param {string} keyBindingText

  return {string}
]]--
function me.ConvertKeyBindingText(keyBindingText)
  local convertedKeyBindingText = string.gsub(string.lower(keyBindingText), "ctrl", "c")

  convertedKeyBindingText = string.gsub(convertedKeyBindingText, "shift", "s")
  convertedKeyBindingText = string.gsub(convertedKeyBindingText, "alt", "a")

  return convertedKeyBindingText
end
