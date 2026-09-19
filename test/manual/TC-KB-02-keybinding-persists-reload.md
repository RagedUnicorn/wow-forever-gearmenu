# TC-KB-02 — Keybinding persists across /reload and follows slot changes

**Area:** Keybinding | **Client:** Forever | **Mandatory:** yes

## Preconditions

- A gearbar with three slots, keys bound to slot 1 and slot 3 (TC-KB-01)

## Steps

1. `/reload`
2. Check the gearslot labels
3. Press the bound keys
4. Log out to character select and back in; check again
5. In the bar's configuration remove slot 2; check the labels and press the key that was on
   slot 3
6. Change the gear slot type of slot 1 in its dropdown; press its key
7. Enter combat (a target dummy works) and press `Unbind` on a row, then leave combat

## Expected

- The keybinding labels are still shown after `/reload` and after a full relog, without delay
- The keys still trigger their slots
- After removing slot 2 the key of the former slot 3 is shown on and triggers the slot that
  moved into position 2 (`GearBar <n> - Slot 2` in the Keybindings list)
- Changing the slot type keeps the key; pressing it uses the new slot type
- In combat the unbind is not performed and a chat message says it is deferred; on leaving combat
  the key is unbound and the label disappears, with no `ADDON_ACTION_BLOCKED`
