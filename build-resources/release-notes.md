# GearMenu for World of Warcraft: Forever

The first release of GearMenu for World of Warcraft: Forever (Interface 16001). It is based on GearMenu 2.8.0 for Classic and starts the Forever line at version 3.0.0 - Classic Era, TBC Anniversary and Mists of Pandaria Classic keep getting GearMenu 2.x from the same project page.

# Highlights
* Key bindings live in the game's own keybinding UI: Settings > Keybindings lists a "GearMenu" section with an entry per GearBar and GearSlot (up to two keys each), and Quick Keybind Mode binds a slot by hovering it and pressing a key. A GearBar's configuration opens both, and each slot row shows its key with an "Unbind" button. Keys follow a slot that moves up when a slot before it is removed, and a change made in combat is applied as soon as you leave combat
* The GearBar slots, the change menu and the TrinketMenu look like the buttons of the game's own action bar - frame, hover and pressed state, rounded item icon, cooldown swipe, a hotkey that turns red when the target is out of range and a framed badge for a queued item
* Profiles follow a live active profile: the profile you are on is marked "(active)" and every change belongs to it and is saved automatically. Create new Profile copies your current settings, Load switches profiles, and Reset to defaults restores the factory settings - exactly like a fresh install
* The settings dropdowns look like the dropdowns of the game settings
* Translated into German, Russian and Chinese; text not translated yet falls back to English

# Differences from GearMenu 2.x for Classic
* There is a single slot look - the Classic and Custom themes and the "Choose Theme" option are not part of the Forever line
* GearMenu's own keybinding popup is replaced by the game's Keybindings list and Quick Keybind Mode (see Highlights)
* Season of Discovery rune slots are not available - WoW: Forever has no runes
* `GM_AddToCombatQueue` takes no runeAbilityId: the macro signature is `GM_AddToCombatQueue(itemId, enchantId, slotId)` (for example `/run GM_AddToCombatQueue(233734, 0, 14)`)
* QuickChange (switching rules triggered by using an item) is not available in this release
* Profile strings exported from GearMenu 2.x can be imported; settings that do not exist on Forever (such as the theme) are ignored
