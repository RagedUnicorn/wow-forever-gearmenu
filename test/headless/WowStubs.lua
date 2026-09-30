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
  Opt-in registry of WoW-global stubs.

  This is deliberately NOT a full Blizzard API mock. A spec requires this module and pulls only the
  stubs it needs, installs them onto the global table for the duration of the test, then restores
  the previous values so nothing leaks across specs. The Bootstrap helper prepends test/headless to
  package.path so this resolves as `require("WowStubs")`.

  Usage:
    local wowStubs = require("WowStubs")

    local restore
    before_each(function()
      restore = wowStubs.install({
        InCombatLockdown = wowStubs.stubs.InCombatLockdown(false),
        C_LossOfControl  = wowStubs.stubs.C_LossOfControl({}),
      })
    end)
    after_each(function() restore() end)

  `install` also accepts any ad-hoc stub the registry does not provide, e.g.
    wowStubs.install({ SomeApi = function() return 42 end })
]]--

local unpack = table.unpack or unpack -- luacheck: ignore

local M = {}

--[[
  Install a table of name -> value stubs onto the global table.

  @param {table} stubs
    map of global name to stub value (function, table, ...)

  @return {function}
    a restore function that puts the previous global values back (including nil for globals that
    did not previously exist). Call it from after_each.
]]--
function M.install(stubs)
  local previous = {}
  local names = {}

  for name, value in pairs(stubs) do
    previous[name] = _G[name]
    names[#names + 1] = name
    _G[name] = value
  end

  return function()
    for _, name in ipairs(names) do
      _G[name] = previous[name]
    end
  end
end

--[[
  Ready-made stub builders for the WoW globals the near-term pilot specs touch. Each returns a fresh
  stub configured by its arguments; add more here as new specs need them.
]]--
M.stubs = {}

--[[
  InCombatLockdown() -> boolean (CombatQueue.ProcessQueue)

  @param {boolean} inCombat
  @return {function}
]]--
function M.stubs.InCombatLockdown(inCombat)
  return function()
    return inCombat and true or false
  end
end

--[[
  C_LossOfControl namespace (CombatQueue.UpdateEquipChangeBlockStatus). `events` is the list of
  active loss-of-control data entries to report.

  @param {table} events
  @return {table}
]]--
function M.stubs.C_LossOfControl(events)
  events = events or {}

  return {
    GetActiveLossOfControlDataCount = function()
      return #events
    end,
    GetActiveLossOfControlData = function(index)
      return events[index]
    end
  }
end

--[[
  C_AddOns namespace (Logger.PrintLogMessage, Configuration.SetAddonVersion). `metadata` maps the
  requested key (e.g. "Title", "Version") to the value to return.

  @param {table} metadata
  @return {table}
]]--
function M.stubs.C_AddOns(metadata)
  metadata = metadata or {}

  return {
    GetAddOnMetadata = function(_, key)
      return metadata[key]
    end
  }
end

--[[
  C_Item namespace - the namespaced GetItemInfo / GetItemInfoInstant used across the item modules.
  `results` maps an itemId/itemLink to a list of return values for GetItemInfo; `instantResults`
  does the same for the cache-free GetItemInfoInstant (whose 4th return is the equip slot).

  @param {table} results
  @param {table} instantResults
  @return {table}
]]--
function M.stubs.C_Item(results, instantResults)
  results = results or {}
  instantResults = instantResults or {}

  return {
    GetItemInfo = function(item)
      local values = results[item] or {}
      return unpack(values)
    end,
    GetItemInfoInstant = function(item)
      local values = instantResults[item] or {}
      return unpack(values)
    end
  }
end

--[[
  UIErrorsFrame (Logger.PrintUserError) - captures messages added to it.

  @return {table}
]]--
function M.stubs.UIErrorsFrame()
  local frame = { messages = {} }

  function frame:AddMessage(message, ...)
    self.messages[#self.messages + 1] = { message = message, ... }
  end

  return frame
end

--[[
  GetLocale() -> string (localization files branch on this at load time).

  @param {string} locale
  @return {function}
]]--
function M.stubs.GetLocale(locale)
  return function()
    return locale or "enUS"
  end
end

--[[
  An in-memory WoW binding set (gui/KeyBind.lua). Returns a table of the binding globals to
  install - SetBinding / GetBindingKey / GetBindingAction / GetCurrentBindingSet / SaveBindings -
  plus inspection helpers. SetBinding refuses (returns false, changes nothing) while the
  InCombatLockdown stub reports combat, mirroring the client's protected-action behaviour; the
  `refusedKeys` set makes it refuse specific keys out of combat too (a key the client rejects).

    local bindingSet = wowStubs.stubs.BindingSet({ ["F1"] = "CLICK GM_KeyBindBar1Slot1:LeftButton" })
    restore = wowStubs.install(bindingSet.globals)
    ...
    bindingSet.GetKeys(action)   -- list of keys bound to an action (binding order)
    bindingSet.actions           -- key -> action map
    bindingSet.savedCount        -- SaveBindings invocations

  @param {table} initial
    key -> action map to start from
  @param {table} refusedKeys
    optional set of keys SetBinding refuses regardless of combat
  @return {table}
]]--
function M.stubs.BindingSet(initial, refusedKeys)
  local bindingSet = {
    actions = {},
    savedCount = 0,
    savedSets = {},
    refusedKeys = refusedKeys or {}
  }

  for key, action in pairs(initial or {}) do
    bindingSet.actions[key] = action
  end

  --[[
    @param {string} action
    @return {table}
      the keys bound to the action, in a stable (sorted) order
  ]]--
  function bindingSet.GetKeys(action)
    local keys = {}

    for key, boundAction in pairs(bindingSet.actions) do
      if boundAction == action then
        keys[#keys + 1] = key
      end
    end

    table.sort(keys)

    return keys
  end

  bindingSet.globals = {
    SetBinding = function(key, action)
      if (_G.InCombatLockdown ~= nil and _G.InCombatLockdown()) or bindingSet.refusedKeys[key] then
        return false
      end

      bindingSet.actions[key] = action

      return true
    end,
    GetBindingKey = function(action)
      return unpack(bindingSet.GetKeys(action))
    end,
    GetBindingAction = function(key)
      return bindingSet.actions[key] or ""
    end,
    GetCurrentBindingSet = function()
      return 1
    end,
    SaveBindings = function(set)
      bindingSet.savedCount = bindingSet.savedCount + 1
      bindingSet.savedSets[#bindingSet.savedSets + 1] = set
    end
  }

  return bindingSet
end

--[[
  CreateFrame(frameType, name, parent, template) -> a recording frame (gui/KeyBindProxy.lua).
  Every created frame is registered by name in the returned registry's `frames` map and records
  its template, RegisterForClicks arguments, Hide / Show calls and attributes. Like the client,
  Hide / Show run the frame's OnHide / OnShow script (with the frame as self) only when the call
  actually changes the visibility - a frame starts shown, so a first Show does not fire OnShow.

    local frames = wowStubs.stubs.FrameRegistry()
    restore = wowStubs.install({ CreateFrame = frames.CreateFrame, UIParent = {} })
    ...
    frames.frames["GM_KeyBindBar1Slot1"]:GetAttribute("macrotext")

  @return {table}
]]--
function M.stubs.FrameRegistry()
  local registry = { frames = {}, created = 0 }

  function registry.CreateFrame(frameType, name, parent, template)
    local frame = {
      frameType = frameType,
      name = name,
      parent = parent,
      template = template,
      attributes = {},
      attributeWrites = 0,
      clicks = nil,
      scripts = {},
      hidden = false
    }

    function frame:RegisterForClicks(...)
      self.clicks = { ... }
    end

    function frame:SetScript(scriptType, handler)
      self.scripts[scriptType] = handler
    end

    function frame:GetScript(scriptType)
      return self.scripts[scriptType]
    end

    function frame:SetAttribute(attribute, value)
      self.attributes[attribute] = value
      self.attributeWrites = self.attributeWrites + 1
    end

    function frame:GetAttribute(attribute)
      return self.attributes[attribute]
    end

    function frame:Hide()
      if self.hidden then return end

      self.hidden = true

      if self.scripts.OnHide then self.scripts.OnHide(self) end
    end

    function frame:Show()
      if not self.hidden then return end

      self.hidden = false

      if self.scripts.OnShow then self.scripts.OnShow(self) end
    end

    function frame:GetName()
      return self.name
    end

    registry.created = registry.created + 1

    if name ~= nil then
      registry.frames[name] = frame
    end

    return frame
  end

  return registry
end

return M
