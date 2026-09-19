# New Features
* Profiles now follow the live active profile model: the profile you are on is marked "(active)" in gold and every change you make belongs to it - it is saved automatically when you switch profiles, at logout and reload, on export and at every login, so there is no Save / Update step to remember
* Create new Profile copies the current settings into a new profile and makes it active; Load switches to the selected profile and reloads the UI, the profile you leave keeping your settings as they are; deleting the active profile falls back to Default
* Add a Reset to defaults button that restores the factory settings into the active profile - the shipped options and the starter GearBar, exactly like a fresh install

# Breaking Changes
* The Default profile is now your editable home profile instead of a frozen copy of the factory settings: it is never deleted or renamed, but loading it brings back what you last had in it. Use Reset to defaults to get the factory settings back
* The Save current as... and Apply buttons are gone; Create new Profile and Load replace them. On the first login after the update the profile you had applied and not edited since becomes the active one, otherwise Default takes over your current settings - nothing is lost either way
* Season of Discovery rune support is gone: the rune slots on the GearBar, the "Enable rune slots" option and the engraved-item tracking are removed because GearMenu Forever targets WoW Forever, which has no runes
* `GM_AddToCombatQueue` no longer takes a runeAbilityId: the macro signature is now `GM_AddToCombatQueue(itemId, enchantId, slotId)` - update existing macros by dropping the third argument (for example `/run GM_AddToCombatQueue(233734, 0, 14)`)

# Bug Fixes
* Fix a flood of Lua errors on WoW Forever when a GearBar change menu is open or the custom theme frame is hovered: the client removed the MouseIsOver global, GearMenu now uses the IsMouseOver widget method instead
