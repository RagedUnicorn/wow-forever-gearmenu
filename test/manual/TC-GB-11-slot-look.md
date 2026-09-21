# TC-GB-11 — Slots render in the action-button look

**Area:** GearBar | **Client:** Forever | **Mandatory:** yes

## Preconditions

- Development build (the `dev/` modules are loaded); a gearbar with at least one slot holding an
  item; TrinketMenu enabled

## Steps

1. `/rggm showcase` and compare every row of the GearMenu columns with the Blizzard columns at
   24, 40 and 64
2. `/rggm showcase changemenu`, then on a real gearbar hover a slot, click it, right-click it and
   open its ChangeMenu - it lists the showcase trinkets on every slot; toggle the showcase off
3. `/rggm showcase trinkets`, open the TrinketMenu, move the column amount and slot size sliders
   across their whole range, then `/rggm showcase trinkets` again
4. Enter Quick Keybind Mode and hover a slot

## Expected

- Frame, hover glow, pushed state, rounded icon, cooldown swipe and countdown match the Blizzard
  button of the same size; no stretched or clipped frame art at any of the three sizes
- The bound key sits in the top right corner in small grey text, a queued item is framed in the
  top left corner; the right-click flash is red only - the hover glow does not shine through
- Neighbouring slots on the gearbar, in the ChangeMenu and in the TrinketMenu sit as close
  together as the action bar buttons in the "Bar of four" row
- The TrinketMenu shows the showcase trinkets, some on cooldown, at every column amount and slot
  size; toggling the showcase off brings the bag trinkets back
- Quick Keybind Mode highlights the slot like an action button
- No Lua errors
