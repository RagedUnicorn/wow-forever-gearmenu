# TC-KB-01 — Set keybinding, label shows, key swaps

**Area:** Keybinding | **Client:** Forever | **Mandatory:** yes

## Preconditions

- A gearbar with a slot holding a usable item; keybinding display enabled on the bar

## Steps

1. Open Settings > Keybindings and expand the `GearMenu` section (or press `Key Bindings`
   in the bar's configuration in `/rggm opt`, which opens the list at that section)
2. Bind a key to the entry of the slot (`GearBar <n> - Slot <p>`, `n` = the bar's bindIndex,
   `p` = the slot position) and confirm with Okay
3. Close the settings and check the slot
4. Press the bound key
5. Press `Quick Keybind Mode` in the bar's configuration, hover another slot of the bar, press a
   key, then Okay; check that slot
6. In the bar's configuration press `Unbind` on the first slot's row

## Expected

- The keybinding label appears on the gearslot right after Okay, without a reload, and the
  configuration row shows the same key
- Pressing the key triggers the slot exactly like clicking it (uses the item / opens swap
  behavior; respects the FastPress setting)
- The Quick Keybind tooltip on hover names the slot entry and its current key; the key pressed in
  that mode is bound and shown on the slot
- Rebinding a key already used elsewhere is handled by the game's list (old binding replaced or
  refused with its message, no Lua error)
- `Unbind` clears the key from the slot label, the row and the Keybindings list
