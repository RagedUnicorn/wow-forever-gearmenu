# GearMenu (WoW: Forever) – Repository Review Findings

Review date: 2026-09-28 · Commit reviewed: `11a2950` (branch `claude/sweet-fermat-tponh8`) · Review type: read-only

## 1. Review summary

GearMenu is a mature, well-organised addon. The module layout is consistent (`code/` for logic, `gui/` for frames, `localization/`, `dev/` for dev-only tooling). Most modules are well commented. Key-binding writes and key-bind proxy updates are deferred correctly during combat. There are 24 headless busted specs and a manual test catalog of 49 cases. The profile system matches its long description in `DEVELOPMENT.md`.

The most important problems:

1. **Imported profile strings are only shallowly validated.** A crafted string can put arbitrary text into the secure `/use` macro of every GearSlot and key-bind proxy. It can also contain malformed nested data that raises during `SetupConfiguration` and breaks every later login.
2. **Renaming a profile to its own name deletes it.** The rename prompt is pre-filled with the current name, so this is easy to trigger by accident.
3. **Some GearBar configuration actions have no combat guard.** Creating a GearBar in combat raises a Lua error. Deleting one leaves an orphaned bar on screen. Removing or re-typing a slot makes the visible buttons and the key bindings disagree. Similar actions next to them (add slot, size, orientation, visibility) are guarded.
4. **Release and support links still point at `wow-classic-gearmenu`.** This includes the Maven `deploy-github` target, the README badges, the release and issue links, the in-game "issues" string and `RELEASE.md`.

### Finding counts

| Severity | Count |
|----------|-------|
| Critical | 0     |
| High     | 5     |
| Medium   | 16    |
| Low      | 27    |
| **Total**| **48**|

Every finding is marked **Confirmed** (visible in the repository code or configuration) or **Unverified** (depends on runtime or client behaviour that could not be observed here).

---

## 2. Scope and review approach

### Scope
- **Instructions and docs:** `README.md`, `DEVELOPMENT.md`, `RELEASE.md`, `test/TESTING.md`, `build-resources/release-notes.md`, `LICENSE`. The repository has no `CLAUDE.md`, `AGENTS.md` or contribution guide, although `test/headless/spec/LocalizationParitySpec.lua:36` refers to a `CLAUDE.md`.
- **Manifest and build:** `GearMenu.toc`, `build-resources/*` (TOC/Environment/badge templates, properties, assembly descriptors), `pom.xml`, `docker-compose.yml`, `renovate.json`, `.github/workflows/*.yaml`, `.luacheckrc`, `.busted`, `.editorconfig`, `.gitattributes`, `.run/*.xml`.
- **Source:** all Lua files in `code/`, `gui/`, `localization/` and `dev/` (dev tooling was skimmed for release leakage), plus `gui/Frame.xml` and `Bindings.xml`.
- **Tests:** `test/headless/Bootstrap.lua`, `test/headless/WowStubs.lua`, all 24 specs, the manual catalog `test/manual/*` and its fixture.
- **Excluded:** binary assets (`assets/*`, `docs/*.gif|png|jpg|svg`), because they are not reviewable as code.

### Approach
Every source file was read in full, split into areas: core, items and combat queue, configuration and profiles, GUI slots and key bindings, GUI menus and localization, tests. Every High and Medium finding, and most Low findings, was then re-checked by re-reading the cited code. Line references were checked mechanically against the files before the report was saved (see the end of the report).

### Checks run

| Command | Result |
|---|---|
| `docker compose run --rm luacheck` / `busted` | **Not run.** The Docker CLI exists, but no daemon is running (`failed to connect to the docker API at unix:///var/run/docker.sock`). |
| `luacheck`, `busted`, `lua`, `luajit` directly | **Not run.** None is installed, and installing dependencies was out of scope. |
| `mvn -o -B -q validate` | **Pass** (exit 0). The POM is well-formed and the offline project model builds. `generate-resources` / `package` were not run: they need plugins downloaded (no local `~/.m2`) and would rewrite `GearMenu.toc` / `code/Environment.lua`. |
| XML well-formedness (Python `xml.dom.minidom`) on `pom.xml`, `Bindings.xml`, `gui/Frame.xml`, 4 assembly descriptors | **Pass** |
| `git ls-files --eol` | 7 generated or template files are stored CRLF (they are marked `-text` in `.gitattributes`, on purpose). All other text files are LF. |
| Static checks: localization key and placeholder parity, `Bindings.xml` entries against `MAX_GEAR_BARS × MAX_GEAR_BAR_SLOTS`, every module function called from `Core` exists | **Pass.** All 4 locales define the same 175 keys, with matching `%s`/`%d` counts. `Bindings.xml` declares 200 `CLICK` actions and 10 preface rows, matching 10 × 20. |

CI status on GitHub was not checked. The review is limited to the repository contents.

---

## 3. Findings

Findings are ordered from highest to lowest severity.

### High

#### H-1 · Security / input validation – Imported profile `slotId` is concatenated into secure macro text
- **Status:** Confirmed
- **Files:** `code/Profile.lua:365-377` (import checks), `gui/KeyBindProxy.lua:244-246`, `gui/KeyBindProxy.lua:281-286`, `gui/GearBar.lua:223-224`, `gui/GearBar.lua:810`
- **Problem:** `ImportString` checks only that each top-level field has the right type (`IsPayloadWellTyped`) and that gear bar ids are unique (`HasUniqueGearBarIds`). `gearBars[*].slots[*].slotId` is never checked. It is copied as-is into `"/use " .. slotId` and set as `macrotext` / `macrotext1` on the proxy buttons and the GearSlots. `SetupConfiguration` (`code/Configuration.lua:259-293`) does not normalise it either.
- **Evidence:**
  - The serializer's strings are length-prefixed and may contain any bytes, newlines included (`code/Serializer.lua:35`).
  - Whitespace is stripped only from the base64 text (`code/Profile.lua:331`), not from the decoded payload.
  - So a `slotId` such as `"13\n/run …"` survives import, Load and the reload.
- **Impact:** A profile string shared in chat or on a forum can make every click or bound key on a GearSlot run arbitrary slash commands in the secure click context. This includes `/run`, `/cast`, `/target` and chat commands. The user has to import and then Load the string, but the page presents profile strings as a normal way to share setups.
- **Fix:** In `ImportString`, reject any payload where a slot's `slotId` is not an integer known to `gearManager` (or `RGGM_CONSTANTS.INVSLOT_NONE`). As defence in depth, build the macro with `tonumber(slotId)` and skip the slot when that fails.

#### H-2 · Robustness / saved variables – A malformed imported profile can break the addon on every login
- **Status:** Confirmed code path
- **Files:** `code/Profile.lua:122-164`, `code/Profile.lua:588-599`, `code/Configuration.lua:262-281`, `code/Core.lua:300`
- **Problem:** Validation checks only top-level types. Values that pass include:
  - `gearBars = {"x"}`
  - a gear bar without `id`
  - `slots = "x"`
  - positions or slots outside `1..MAX_GEAR_BAR_SLOTS`
  - more than `MAX_GEAR_BARS` bars
  - `trinketMenuColumns = 0`
  - malformed `frames` or `quickChangeRules` entries
- **Evidence:**
  - `SwitchProfile` calls `ApplySnapshot`, which calls `SetupConfiguration`. `SetupConfiguration` runs `gearBar.isEnabled = true` on each entry, which raises for a string entry.
  - `activeProfile = name` (`code/Profile.lua:597`) is never reached. The broken data is already in the live `GearMenuConfiguration`.
  - The `PLAYER_LOGOUT` mirror then copies it into the previous profile.
  - Every later login raises at `code/Core.lua:300` before the UI is built.
- **Impact:** GearMenu stops initialising. The only way to recover is to delete the character's SavedVariables file.
- **Fix:**
  - Add a schema check in `ImportString`:
    - each bar is a table with a numeric `id`
    - `slots` is a sequence of at most `MAX_GEAR_BAR_SLOTS` tables with a valid `slotId`
    - `keyBinding` is a string or nil
    - `position` fields are strings or numbers
    - numbers are finite and within their allowed ranges
    - the bar count is at most `MAX_GEAR_BARS`
    - `frames` and `quickChangeRules` entries have the expected shape
  - Wrap `ApplySnapshot` in `pcall` and roll back to the previous live configuration on error.

#### H-3 · Logic – Renaming a profile to its current name deletes it
- **Status:** Confirmed
- **Files:** `code/Profile.lua:485-503`, `gui/ProfileMenu.lua:708`, `gui/ProfileMenu.lua:822`
- **Problem:** The UI guard `if newName ~= oldName and mod.profile.ProfileExists(newName)` lets an unchanged name through. `RenameProfile` then runs `store[newName] = store[oldName]; store[oldName] = nil`. When the names are equal, the entry is removed.
- **Evidence:** The rename popup is pre-filled with the current name (`self.EditBox:SetText(self.data or "")`). Pressing Enter or Accept without editing, or adding only surrounding whitespace (which is trimmed), deletes the profile. If it was the active profile, `activeProfile` points at a missing entry. At logout `SaveActiveProfile` falls back to Default and overwrites Default's stored copy.
- **Impact:** Silent loss of a saved profile, and possibly of the Default snapshot too.
- **Fix:** In `RenameProfile`, `if oldName == newName then return true end`. The UI handler can also treat it as a no-op.

#### H-4 · Release process – GitHub release target and release docs point at the Classic repository
- **Status:** Confirmed
- **Files:** `pom.xml:105`, `RELEASE.md:19`, `RELEASE.md:22`
- **Problem:** The `deploy-github` profile has `<repository>wow-classic-gearmenu</repository>`, but this repository is `RagedUnicorn/wow-forever-gearmenu` (see `git remote -v`). The README states that the Classic line is a separate repository (`README.md:32`). `RELEASE.md` sends the maintainer to the Classic repository's workflow pages.
- **Impact:**
  - When `release_github.yaml` runs here with the repo-scoped `GITHUB_TOKEN`, it will fail against the other repository.
  - When run manually with a broader token, it would publish the Forever build and tag `v2.8.0` on the Classic repository.
  - Either way the Forever repository gets no GitHub release.
- **Fix:**
  - Set `<repository>wow-forever-gearmenu</repository>` and update the `RELEASE.md` links.
  - Confirm whether CurseForge project `345496` is meant to be shared with the Classic line. That may be intended (one project, several game versions) and could not be verified.

#### H-5 · Combat lockdown / runtime error – Creating a GearBar in combat raises a Lua error
- **Status:** Confirmed
- **Files:** `gui/GearBarConfigurationMenu.lua:190-211`, `gui/GearBar.lua:95`, `gui/GearBar.lua:102`, `gui/GearBar.lua:135-143`, `gui/GearBar.lua:698-705`
- **Problem:** `CreateNewGearBar` has no `InCombatLockdown()` guard.
  - In combat, `CreateGearSlot` logs an error and returns `nil`, so `gearSlotReferences` stays empty.
  - `BuildGearBar` then calls `UpdateGearBarGearSlotTexturesAttributes`, which passes `gearSlotReferences[index]` (nil) to `slotStyle.UpdateSlotTextureAttributes`. That function indexes the nil slot.
- **Impact:**
  - A Lua error is shown.
  - The bar is already saved to the configuration, but it has no slots and no Settings category (code after `BuildGearBar` never runs).
  - Later visual updates of that bar keep raising until `/reload`.
- **Fix:** Refuse the action in combat with a localized user message, as `AddGearSlot` does (`gui/GearBarConfigurationSubMenu.lua:347`). Also skip nil slots in the `Update*` loops.

### Medium

#### M-1 · Combat lockdown – Deleting a GearBar in combat leaves an orphaned, clickable bar
- **Status:** Confirmed code path. That `Hide()` is blocked in combat is standard client behaviour, and the code states the same at `gui/GearBar.lua:445-448`.
- **Files:** `gui/GearBarConfigurationMenu.lua:103-118`, `gui/GearBarStorage.lua:100-104`
- **Problem:** The delete confirmation has no combat guard. It calls `gearBarReference:Hide()` on a frame with secure children and then drops the storage entry.
- **Impact:**
  - The bar stays visible and its secure buttons keep working, but nothing tracks it any more.
  - Hovering it reaches `gui/GearBarChangeMenu.lua:94-100` with a nil `gearBar` and raises.
- **Fix:** Refuse deletion in combat, or disable the button while in combat.

#### M-2 · Combat lockdown – Removing or re-typing a slot, or toggling FastPress, in combat leaves the UI out of sync
- **Status:** Confirmed
- **Files:** `gui/GearBarConfigurationSubMenu.lua:947-965`, `gui/GearBarConfigurationSubMenu.lua:1056-1072`, `gui/GeneralMenu.lua:340-348`, `gui/GearBar.lua:773-778`, `gui/GearBar.lua:972-976`
- **Problem:**
  - The slot handlers change `gearBar.slots` and call `keyBindProxy.Update()`, which is deferred and applied after combat.
  - `GearBar.UpdateGearBarGearSlots` returns early in combat and is never retried. `Core.OnPlayerAliveOrLeftCombat` (`code/Core.lua:187-195`) only replays drags, proxies and binding writes.
  - The FastPress toggle has the same problem with `UpdateClickHandler`.
- **Impact:** After combat, the key bindings follow the new layout while the visible buttons keep their old `/use` macros and icons. A click and a key press on the same slot can use different items until `/reload`.
- **Fix:** Add the same `InCombatLockdown()` guard these screens already use for add slot, size and orientation, or queue a deferred UI rebuild.

#### M-3 · UI state / frame reuse – A re-shown hidden GearSlot keeps its old size and anchor
- **Status:** Confirmed
- **Files:** `gui/GearBar.lua:718-730`, `gui/GearBar.lua:773-798`, `gui/GearBar.lua:805-813`, `gui/GearBar.lua:840-849`
- **Problem:**
  - Removing a slot only hides the trailing frame.
  - `UpdateGearSlotSizes` walks `pairs(gearBar.slots)`, so hidden frames are not resized or re-anchored.
  - `UpdateExistingSlot` only sets attributes and calls `Show()`.
- **Impact:** Remove a slot, change the slot size or orientation, then add a slot. The re-used frame comes back at the old size and position, while its textures use the new size.
- **Fix:** Call `me.UpdateGearSlotSizes(gearBar)` at the end of `UpdateGearBarGearSlots`, or resize and re-anchor the frame in `UpdateExistingSlot`.

#### M-4 · Logic – Removing a GearBar's Settings category can leave a hole in the category list
- **Status:** Confirmed by Lua 5.1 table semantics; not reproduced in the client
- **File:** `gui/AddonConfiguration.lua:220-245`
- **Problem:**
  - The function sets `categories[i] = nil` in the middle of the array and then compacts with `for i = 1, #categories`.
  - With a hole, the `#` border is undefined. Example: 3 entries in a 4-slot array part with the middle one removed gives `#categories == 1`, so the compaction loop does nothing and `{a, nil, c}` stays.
- **Impact:** Later GearBars can disappear from the Settings sidebar, because iteration stops at the hole.
- **Fix:** Use `table.remove(categories, i)` and drop the two manual loops.

#### M-5 · Logic – QuickChange item lists never refresh after the first build
- **Status:** Confirmed
- **Files:** `gui/QuickChangeMenu.lua:100`, `gui/QuickChangeMenu.lua:596-600`
- **Problem:** `BuildUi` returns early once built. The from/to item caches are only rebuilt when the selected slot changes.
- **Impact:** Items looted, bought or moved after the panel was first opened are missing until the user switches to another category and back.
- **Fix:** Invalidate both caches on panel show, or on `BAG_UPDATE_DELAYED`.

#### M-6 · Logic – A QuickChange rule between two enchant variants of the same item never fires
- **Status:** Confirmed
- **Files:** `code/QuickChange.lua:47-51`, `code/QuickChange.lua:215-216`
- **Problem:** Adding a rule only rejects the case where both the item and the enchant are equal, so "same item, different enchant" is accepted. At run time the rule also requires `not C_Item.IsEquippedItem(quickChangeRule.changeToItemId)`. That is always false here, because the "from" copy with the same itemId is equipped.
- **Impact:** A rule type the UI accepts silently does nothing.
- **Fix:** Reject such rules when they are added, or compare item and enchant using the equipped item link instead of `IsEquippedItem(itemId)`.

#### M-7 · Logic – The "item equipped elsewhere" fallback in `SwitchItems` ignores the target slot, enchant and lock state
- **Status:** Confirmed
- **Files:** `code/ItemManager.lua:332-343`, `code/ItemManager.lua:361-374`
- **Problem:** `FindEquipedItem(itemId)` matches on itemId only and also checks the target slot itself. The code then runs `PickupInventoryItem(found)` and `PickupInventoryItem(slotId)` and reports `SWAP_EVENT_COMPLETED`.
- **Impact:**
  - When the item is already in the target slot, the swap is a no-op but is reported as successful, and the "not found" message is not shown.
  - A copy with a different enchant can be swapped in even when fallback to the base item is disabled.
  - Locked items are not checked.
- **Fix:** Exclude `slotId` from the search, respect the enchant and fallback setting, and check `IsInventoryItemLocked` on both slots.

#### M-8 · Logic – `FindSpace` ignores bag families (quivers, ammo pouches, soul bags)
- **Status:** Confirmed code; the client's refusal is standard behaviour
- **Files:** `code/ItemManager.lua:626-647` (the comment at 628-630 admits the limitation), used at `code/ItemManager.lua:289`, `:664`, `:704`
- **Problem:** The first empty slot in bags 0–4 is returned, even when it is in a special bag that cannot hold the item.
- **Impact:**
  - Unequip and drop-to-TrinketMenu fail with "no bag space" while a normal bag still has room.
  - The two-hand displacement pre-check can pass wrongly, so the item is picked up and then refused by the client.
- **Fix:** Use `C_Container.GetContainerNumFreeSlots(bag)` and accept a bag only when its family is 0 or matches `C_Item.GetItemFamily(itemId)`.

#### M-9 · Logic – Off-hand equip while a two-hander is worn has no bag-space check
- **Status:** The code gap is Confirmed; the client reaction is Unverified
- **File:** `code/ItemManager.lua:230-240`
- **Problem:** `RequiresOffhandDisplacement` only handles "2H into main hand with an off-hand worn". It does not handle "off-hand or shield into the off-hand slot with a 2H worn", which also pushes the 2H into the bags.
- **Impact:** With full bags, the swap is refused after the pickup and GearMenu shows no message. The item may stay on the cursor.
- **Fix:** Also return `true` when `slotId == INVSLOT_OFFHAND` and the equipped main-hand item's equip location is `INVTYPE_2HWEAPON`.

#### M-10 · Edge cases – `UnequipItemToBag` skips all the safety checks the equip path has
- **Status:** Confirmed
- **Files:** `code/ItemManager.lua:699-713` (called from `gui/GearBarChangeMenu.lua:441`)
- **Problem:** It calls `PickupInventoryItem(slot.slotId)` without checking `CursorHasItem()`, `SpellIsTargeting()`, the lock state, combat, death, casting or loss of control.
- **Impact:**
  - With an item already on the cursor, the pickup equips the cursor item into the slot instead, which is an unintended equip.
  - In combat, the action silently does nothing but reports success (returns nil).
- **Fix:** Reuse the guards from `SwitchItems`, and refuse or queue the action in combat.

#### M-11 · Input validation – Imported key bindings are bound without validation
- **Status:** Confirmed
- **File:** `gui/KeyBind.lua:322-336`
- **Problem:** `ApplyGearBarKeyBindings` binds whatever string is in `gearSlot.keyBinding`, for example `W`, `ESCAPE` or `BUTTON1`, at any `position` from `pairs(slots)`.
  - A non-numeric position breaks the `%d` format in the proxy action name.
  - A table value makes `SetBinding` raise.
- **Impact:** Loading a shared profile can silently rebind movement or other core keys, or raise an error.
- **Fix:**
  - Validate during import: `keyBinding` is a string or nil, positions are `1..MAX_GEAR_BAR_SLOTS`.
  - Consider listing the keys that will be rebound in the Load confirmation.

#### M-12 · Untrusted input / saved variables – Any group or guild member can permanently silence update notices
- **Status:** Confirmed
- **Files:** `code/Comm.lua:112-118`, `code/Comm.lua:145-163`
- **Problem:** `OnChatMsgAddon` saves the raw message in `GearMenuConfiguration.lastNotifiedVersion` and prints it. The only check is that it starts with something `IsVersionBefore` can parse.
- **Impact:** A single message such as `v99.0.0<text>` from any guild or group member suppresses all real update notices for that character. It also puts attacker-controlled text into chat.
- **Fix:** Accept only `^v?%d+%.%d+%.%d+$` with a length limit, and save and print the normalised version.

#### M-13 · Documentation / support – README, in-game text and release docs link to the Classic repository
- **Status:** Confirmed
- **Files:** `README.md:9-10` (CI badges), `README.md:24`, `README.md:329`, `README.md:339`, `localization/enUS.lua:21`, `localization/deDE.lua:23`, `localization/ruRU.lua:23`, `localization/zhCN.lua:22`
- **Problem:** The badges show the Classic repository's CI status. The release download links and the issue links send Forever users to `wow-classic-gearmenu`. The "issues" string shown in the About panel does the same.
- **Impact:** Users download the wrong line and file issues in the wrong tracker. The CI badges do not reflect this repository.
- **Fix:** Point all of these at `RagedUnicorn/wow-forever-gearmenu`. Keep the one intentional cross-reference in `README.md:32`.

#### M-14 · Localization – zhCN strings with the wrong meaning, plus untranslated blocks
- **Status:** Confirmed
- **Files:** `localization/zhCN.lua:141`, `localization/zhCN.lua:144`, `localization/zhCN.lua:63-74`
- **Problem:**
  - "Add Gearslot" is translated as 添加装备条 ("Add GearBar"), and the max-slots message also uses 装备条 (bar) instead of 装备槽 (slot).
  - The whole TrinketMenu block is still in English.
- **Impact:** Chinese users see a button that says it adds a bar when it adds a slot.
- **Fix:** Use 添加装备槽 / 装备槽 and translate lines 63–74.

#### M-15 · Tests – Two click-handling specs cannot fail
- **Status:** Confirmed
- **Files:** `test/headless/spec/GearBarClickHandlingSpec.lua:153`, `test/headless/spec/GearBarClickHandlingSpec.lua:252-272`
- **Problem:** The `C_Timer.After` stub runs its callback immediately. A single flash therefore records `{"PUSHED","NORMAL"}`, so the down-then-up assertions pass even if the key-phase gate at `gui/GearBar.lua:1023` were inverted.
- **Impact:** A regression in FastPress key handling would not be caught.
- **Fix:** Queue timer callbacks in the stub and assert the state after each phase separately.

#### M-16 · Tests – Module state leaks between spec files
- **Status:** Confirmed code; whether it breaks anything depends on file order
- **Files:** for example `test/headless/spec/ConfigurationMigrationSpec.lua:130`, `test/headless/spec/UiHelperPoolSpec.lua:40`, `test/headless/spec/LocalizationParitySpec.lua:93`, `test/headless/spec/LocalizationParitySpec.lua:97`, `test/headless/spec/ProfileSpec.lua:98-106`
- **Problem:** Specs load real modules into the shared `rggm` table, and set `rggm.L = nil`, without restoring them. busted's insulation restores globals but not fields of `rggm`.
- **Impact:** Results can depend on the order spec files run in. `ProfileSpec` already has to work around a module left behind by `ConfigurationMigrationSpec`.
- **Fix:** Snapshot and restore `rggm` (or the module under test) in `before_each` / `after_each` through a shared helper in `Bootstrap.lua`.

### Low

| ID | Category | File:line | Problem | Suggested fix | Status |
|---|---|---|---|---|---|
| L-1 | Runtime error | `code/GearBarManager.lua:562-574` | `SetGearSlotSize` calls `mod.gearBar.UpdateGearBarSize(gearBar)` outside the `if gearBar` block, so an unknown id logs an error and then raises. | Move the call inside the `if`. | Confirmed |
| L-2 | Runtime error | `gui/GearBarConfigurationSubMenu.lua:354-366` | `#gearBar.slots` runs before the `gearBar == nil` check, so the nil check can never help. | Swap the two checks. | Confirmed |
| L-3 | Runtime error | `gui/GearBarChangeMenu.lua:94-100` | `gearBar.changeMenuDirection` is read without a nil check. The bag-update refresh (`code/ItemManager.lua:98-101`) can reach it for a bar deleted while its menu was open. | `if gearBar == nil then return end`. | Confirmed (narrow window) |
| L-4 | Edge case | `code/Macro.lua:147-155` | `FireSwapEvent` loops `1..#swapListeners` over a live array. A listener that unregisters itself makes the next listener get skipped and a `pcall(nil)` "listener failed" error get logged. | Iterate over a copy. | Confirmed |
| L-5 | Logic | `code/Core.lua:156-168` | `quickChange.OnUnitSpellCastSucceeded` is skipped whenever a channel is active. The channel-stop handler only processes the combat queue, so a QuickChange rule tied to that cast is dropped. | Always forward to QuickChange; skip only the queue processing. | Confirmed code; frequency Unverified |
| L-6 | UX / state | `code/Target.lua:35`, `code/Core.lua:207-209` | `currentTargetGuid` is only set on `PLAYER_TARGET_CHANGED` and never at initialize, so after `/reload` with a target selected the out-of-range colouring stays off until the target changes. | Call `UpdateCurrentTarget()` in `Initialize`. | Confirmed |
| L-7 | Network use | `code/Core.lua:277`, `code/Comm.lua:73-95` | Every `GROUP_ROSTER_UPDATE` also broadcasts to GUILD. A broadcast skipped by the 10 s cooldown is dropped, not delayed, so late joiners may never receive the version. | Send to GUILD only on login; delay a skipped broadcast instead of dropping it. | Confirmed |
| L-8 | Performance | `code/Core.lua:187-195`, `code/CombatQueue.lua:230-231` | The 0.1 s combat-queue ticker is restarted on `PLAYER_ALIVE`/`PLAYER_UNGHOST` and on loss-of-control events without checking combat, so it can tick for a whole fight doing nothing. | Start it only when `not InCombatLockdown()`. | Confirmed |
| L-9 | Duplication | `code/Core.lua:316`, `code/Core.lua:325` | `UpdateGearBars(UpdateGearBarVisual)` is called twice in `Initialize`. Each equip also refreshes twice (`PLAYER_EQUIPMENT_CHANGED` + `UNIT_INVENTORY_CHANGED`, `code/Core.lua:109-122`, `:231-237`). | Remove the duplicate call or debounce the two events. | Confirmed |
| L-10 | Combat queue | `code/ItemManager.lua:323`, `code/ItemManager.lua:345-349` | A locked item is treated as a permanent failure, so the queued entry is removed. Busy-cursor and spell-targeting failures keep the entry for a retry. | Keep queued entries on `itemLocked`. | Confirmed |
| L-11 | Consistency | `code/ItemManager.lua:211`, `code/CombatQueue.lua:151` | Combat is checked with `UnitAffectingCombat` in one place and `InCombatLockdown` in another. When they disagree, the item is re-queued every tick and the "queued" event is fired repeatedly. | Use one helper for both. | Confirmed |
| L-12 | Edge case | `code/QuickChange.lua:217-223` | A delayed rule does not re-check the slot when the timer fires, so it overwrites a manual change made during the delay. | Confirm the slot still holds `changeFromItemId` inside the callback. | Confirmed |
| L-13 | Robustness | `code/Configuration.lua:531` | The v2.0.0 migration sets `frames = nil` after the defaults backfill has already filled it in. The TrinketMenu then indexes `GearMenuConfiguration.frames[...]` (`code/Configuration.lua:884`) in that session. Probably only reachable with SavedVariables carried over from v1.x. | Reset with `frames = {}`. | Confirmed code; reachability Unverified |
| L-14 | Migration | `code/Profile.lua:557-567` | Login adoption compares stored snapshots with the live configuration using `DeepEquals`. The live one has already been normalised by `SetupConfiguration` (`bindIndex`, `isEnabled`, …), so older stored snapshots never match and the player falls back to Default. | Normalise candidates the same way before comparing. | Confirmed code; impact Unverified |
| L-15 | Input validation | `gui/ProfileMenu.lua:847` | A non-string `envelope.name` from an import raises in the popup's `OnShow` (`SetText`). | Drop `name` unless it is a string. | Confirmed |
| L-16 | Saved variables | `code/Profile.lua:436`, `gui/ProfileMenu.lua:323` | Imported payloads are stored with all their keys, not only `PROFILE_FIELDS`, and the paste box has no length limit, so SavedVariables can grow with junk. | Copy only the known fields; cap the paste length. | Confirmed |
| L-17 | Serializer | `code/Serializer.lua:93`, `code/Serializer.lua:200` | `tonumber` may accept `nan`/`inf`. A NaN table key raises ("table index is NaN"), which breaks the "never raises" contract. NaN/inf values also pass validation. | Reject non-finite numbers when encoding and decoding. | Unverified (depends on the client's `strtod`) |
| L-18 | Persistence | `gui/TrinketMenu.lua:288-289`, `gui/TrinketMenu.lua:53-60` | `relativeTo` from `GetPoint()` is saved and passed back into `SetPoint`. If the client returns a frame object, a table ends up in SavedVariables and in exports. | Always anchor to `UIParent`; do not persist `relativeTo`. | Unverified |
| L-19 | UI edge case | `gui/TrinketMenu.lua:126-138` | The frame height uses the uncapped item count while only 30 slots exist. With 0 trinkets, an unlocked menu has zero height and cannot be grabbed. | Clamp the count to 1..`TRINKET_MENU_DEFAULT_SLOT_AMOUNT`. | Confirmed |
| L-20 | Race | `gui/GearBar.lua:1036-1042` | `FlashGearSlot` has no token, so two quick presses end the second flash early. `gui/SlotStyle.lua:214-238` already solves this with `flashToken`. | Reuse the token pattern. | Confirmed |
| L-21 | Tooltip | `code/Tooltip.lua:131-134` | Simple tooltips call `GetItemQualityColor(itemRarity)` even when the item is not cached and `itemRarity` is nil. | Return early when `itemName == nil`. | Unverified |
| L-22 | Localization | `gui/GearBar.lua:137`, `gui/GearBar.lua:775`, `gui/GearBar.lua:973` | A user-visible error is hard-coded in English and has a typo: "after your are out of combat". | Localize it and fix the typo. | Confirmed |
| L-23 | Localization robustness | `localization/deDE.lua:6`, `localization/ruRU.lua:7`, `localization/zhCN.lua:6` | Each locale replaces the table (`rggm.L = {}`) with no fallback to enUS, so a key added only to enUS later becomes `nil` (`SetText(nil)` or format errors). The parity spec catches this only when it is run. | Add an `__index` fallback to enUS. | Confirmed |
| L-24 | Spelling / grammar | `localization/deDE.lua:48`, `:54`, `:124`, `:183`; `localization/enUS.lua:11`, `:32`; `localization/ruRU.lua:72` | deDE: "Violet" → "Violett", "Sekunde" → "Sekunden", "das bewegen des Ausrüstungsbalken" → "das Bewegen des Ausrüstungsbalkens", "itemdId". enUS: "Optionsmenu", "instead on keypress up". ruRU: "секунд" after 1–4. Terms are also inconsistent (GearSlot / Gearslot / itemslot; GearBar / Ausrüstungsbalken). | Correct the strings; pick one term per concept. | Confirmed |
| L-25 | Lint config | `.luacheckrc:1-19`, inline `-- luacheck: globals` headers (e.g. `code/Configuration.lua:27-28`) | WoW API names are declared as writable `globals`, not `read_globals`, so an accidental assignment to `SetBinding`, `RGGM_CONSTANTS` and the like is never flagged. Specs also use a file-wide `-- luacheck: ignore 143`. | Switch to `read_globals`; use `std = "lua51+busted"` for `test/`. | Confirmed |
| L-26 | Manifest | `build-resources/gearmenu-release.toc.tpl:8` | The release TOC declares `X-Wago-ID` although `DEVELOPMENT.md:410` and the release notes say there is no Wago release for this line. | Remove it until Wago supports Forever. | Confirmed |
| L-27 | Dead code | `code/Filter.lua:42-65`, `code/Target.lua:52-54`, `code/GearManager.lua:226-240`, `code/Debug.lua:39-43` | Dead or unused code: `RegisterFilter`/`DeregisterFilter` are never called, so `ShouldFilterTag` always returns false on every log line; `GetCurrentTargetName` is unused; `bagMap`/`GetMappedBag` are unused; the dev helpers use retail item ids (55881, 128959) that do not exist on this client. | Remove the dead code or wire it up; use valid Classic-era ids. | Confirmed |

---

## 4. Documentation, testing and development-process gaps

These are useful to track but are not code defects.

### Documentation
- **README errors:**
  - `README.md:48`: `Finger1Slot` is described as "Second/Upper Ring slot"; it should be Lower.
  - `README.md:52`: `MainhandSlot` should be `MainHandSlot`, the client's slot name.
  - `README.md:325`: "screenshot off the error" → "of"; "all others addons" → "other".
  - `README.md:94` and `README.md:96` repeat "The bound key is shown …".
- **README macro example:** `README.md:146` uses item id `233734` for Hand of Justice, while the Wowhead link example (`README.md:163-167`) uses `11815` from `classic.wowhead.com`. Say which database matches the Forever client.
- **DEVELOPMENT.md:**
  - It opens with raw "Invtypes" / "SlotTypes" lists that have no introduction. It has no "prerequisites / quick start" section (Docker, Maven, JDK 25 as used in CI).
  - `DEVELOPMENT.md:92` refers to a "wow-media-capture skill" that is not in the repository.
  - `DEVELOPMENT.md:118-121` says `.luacheckrc` holds WoW-specific globals; it only lists the addon's own 6 globals. WoW globals are declared inline per file.
  - The "writes bindings in three cases" paragraph (`DEVELOPMENT.md:379-383`) leaves out `KeyBind.OnGearBarRemoved` (`gui/KeyBind.lua:274-291`).
- **Stale comments:**
  - `code/Profile.lua:274-276`: the `ApplySnapshot` docstring says missing fields are backfilled with defaults. In fact the live value is kept, as `DEVELOPMENT.md:304-306` correctly says.
  - `test/headless/Bootstrap.lua:38` understates which modules are loaded.
  - `test/headless/spec/LocalizationParitySpec.lua:36` cites a non-existent `CLAUDE.md`.
- **Missing docs:** there is no CONTRIBUTING guide and no CHANGELOG history. `build-resources/release-notes.md` only covers the current release.

### Testing
- **How to run:** `docker compose run --rm luacheck` and `docker compose run --rm busted`, or `busted` / `luacheck .` from the repo root if they are installed locally. CI runs both on push to `master` and on pull requests (`.github/workflows/test.yaml`, `lint.yaml`). The Lua version of the `ragedunicorn/busted` image is not documented. WoW runs Lua 5.1, so pinning to 5.1 or LuaJIT should be stated.
- **Modules with no automated coverage:** `code/Core.lua` (event wiring and init order), `code/QuickChange.lua` (a README feature; `IsRuleMatching` is pure and easy to test), `Ticker`, `Tooltip`, `Target`, `Filter`, and the GUI modules `GearBarChangeMenu`, `GearBarStorage`, `Cooldown`, `SlotStyle`, `ProfileMenu`, `QuickChangeMenu`, `GeneralMenu`, `GearBarConfigurationMenu`, `AddonConfiguration`.
- **Real item-link parsing is never tested:** `Common.GetItemInfo` is stubbed in every item spec.
- **Stub fidelity:** in `test/headless/WowStubs.lua`:
  - `SetBinding` silently returns false in combat (`:239-240`).
  - `GetBindingKey` sorts keys (`:233`).
  - `SetAttribute` accepts writes in combat (`:306`).
  - `CreateFrame` does not register `_G[name]` (`:330`).

  Each of these can hide real combat-lockdown or key-order bugs.
- **Weak assertions:**
  - The `ItemManagerSwapFailureSpec` success paths (`:202`, `:372`) do not assert which pickup calls were made.
  - "prefers the exact copy" (`:428`) has only one candidate in the bags.
  - `UiHelperPoolSpec:110-120` passes if `ForEach` visits nothing.
- **Missing manual cases:**
  - GearBar Hide/Show (including key bindings still working while hidden)
  - Tooltip modes
  - Out-of-range key colour
  - The "fallback to base item" option
  - The update notice
  - The packaged release build: `test/TESTING.md:39` says only the dev checkout is tested, so the release TOC, `LOG_LEVEL=1` and `DEBUG=false` are never exercised.
  - Combat refusal of bar changes.
- **TC-SV-02:** `test/manual/TC-SV-02-upgrade-from-previous-release.md` expects gear bars to survive "byte-for-byte", but setup adds `isEnabled` and `bindIndex`. Its fixture has no key bindings.

### Development and release process
- **No local lint/test without Docker.** The `.run/*.xml` IDE configurations call the older `docker-compose` through `powershell.exe`, which is Windows-only and inconsistent with the documented `docker compose`.
- **Generated files are committed in development state** (`GearMenu.toc`, `code/Environment.lua`), which is documented. As a result, anyone installing straight from a git checkout gets dev logging, the `dev/` modules and the extra `GearMenuShotLog` SavedVariable. In the dev build, `dev/Capture.lua:763` also permanently sets the `screenshotFormat` CVar at every login.
- **Undocumented release steps.** `RELEASE.md` does not say how to bump the version: `pom.xml` `<version>` drives `addon.tag.version`, and `DEVELOPMENT.md:215` says to update `addon.tag.version`, which is derived and should not be edited directly. It also does not say that `generate-sources.yaml` auto-commits regenerated files to PR branches.
- **Hand-managed Forever values.** The Forever-specific values in `pom.xml` (`addon.interface.forever`, `addon.curseforge.gameVersionForever`) are managed by hand. This is documented in `DEVELOPMENT.md:406-410`; it needs a reminder in the release checklist.
- **Metadata still names Classic.** `pom.xml:5` `groupId` `com.ragedunicorn.wow.classic` feeds `ADDON_IDENTIFIER`. This is harmless, but it can mislead.

### Questions needing in-game validation (Unverified)
- **Weapon swaps in combat.** `code/ItemManager.lua:207-213` queues every swap in combat, weapons included. On Classic-era clients, addons can often swap weapons, off-hands, ranged items and ammo in combat. If that holds on Forever, users wait for combat to end with no need.
- **Loss-of-control flag.** `isEquipChangeBlocked` (`code/CombatQueue.lua:198-232`) only changes on `LOSS_OF_CONTROL_ADDED/UPDATE`. If the Forever client does not fire an update when an effect expires, every swap stays queued until the next loss-of-control event. Re-checking in `ProcessQueue` would make this robust.
- **Group messages in battlegrounds.** `code/Comm.lua:90-94` sends RAID/PARTY messages; inside Classic-era battlegrounds these may require the `INSTANCE_CHAT` / `BATTLEGROUND` channel.
- **Change menu parent.** The change menu frame has no parent (`gui/GearBarChangeMenu.lua:50`), so it will not hide with Alt+Z UI hiding.

---

## 5. Areas reviewed with no findings

- **Event bus** (`code/Event.lua`): the gated/ungated design, init gating on `PLAYER_ENTERING_WORLD`, unit events registered via `RegisterUnitEvent`, and `PLAYER_LOGOUT` gated so nothing is written before configuration exists. One design note: the bus keeps one handler per event, and a second registration silently replaces the first. That is fine today, but it is a trap for future changes.
- **Key-bind proxies** (`gui/KeyBindProxy.lua`, `Bindings.xml`):
  - They are created once, with combat deferral, and attributes are only rewritten when they change.
  - Deferred work is flushed in the correct order (proxies first, then binding writes).
  - The positional key shift on slot removal is correct.
  - The 200 binding entries match the constants exactly.
- **Encoder / serializer:** base64 length and padding validation, checksum, trailing-data rejection, depth limit (64), and no `loadstring` use.
- **Bind indexes:** `EnsureBindIndices` and `AllocateBindIndex` handle duplicates, out-of-range values and exhaustion, and consumers check for nil.
- **Profile page combat guards:** Load, Reset and delete-active are refused in combat and wrapped in the documented key-binding dance.
- **Guarded bar changes:** add slot, visibility, size, orientation, Quick Keybind Mode and bar drag.
- **Bag cache** (`code/ItemLocationCache.lua`): invalidation on `BAG_UPDATE` / `ITEM_LOCK_CHANGED`, re-validation against live links, a single rescan, and correct bag and slot loop bounds.
- **Localization parity:** key sets and format placeholder counts are identical in all four locales, and every key used in code exists in enUS.
- **Release packaging:** the release TOC template and `assembly-release.xml` correctly leave out `dev/`, `code/Debug.lua` and `GearMenuShotLog`. Both release workflows build with `-P release`.
- **Manifest:** `## Interface: 16001` matches `pom.xml` `addon.interface.forever`. `SavedVariablesPerCharacter` and `Category` are consistent between the dev and release templates.

---

*Reference check: every `path:line` cited in this report was checked to exist, with the line number within the file length, using a script run against commit `11a2950` before the report was saved.*
