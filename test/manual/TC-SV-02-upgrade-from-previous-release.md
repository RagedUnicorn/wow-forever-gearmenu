# TC-SV-02 — Upgrade from previous release migrates cleanly

**Area:** SavedVariables | **Client:** Forever | **Mandatory:** yes, from the second WoW: Forever release on

> Not applicable to 3.0.0, the first WoW: Forever release: Forever players start fresh, there is no
> previous Forever release to upgrade from. The v2.7.0 fixture is a Classic schema and only shows that
> Classic SavedVariables carried over by hand load without errors. Once 3.0.0 has shipped, snapshot a
> v3.0.0 fixture (with saved profiles) into `test/manual/fixtures/` and point this case at it.

## Preconditions

- Client fully logged out
- The version bump for the release under test is already applied — `pom.xml` bumped and
  `mvn generate-resources -D generate.sources.overwrite=true` re-run, so `GearMenu.toc` carries
  the **new** `## Version:`. `SetAddonVersion()` stamps whatever the TOC says; without the bump
  the version expectation below can neither pass nor fail
- The previous release's schema fixture: `test/manual/fixtures/TC-SV-02-gearmenu-v2.7.0.lua`
- Backup of the test character's current `WTF/.../SavedVariables/GearMenu.lua` taken (to restore
  after the test)

## Steps

1. Copy the fixture over the character's `SavedVariables/GearMenu.lua` and delete `GearMenu.lua.bak`
2. Log in with the character
3. Observe the screen and chat for errors
4. Verify both gearbars render exactly as configured in the fixture:
   - **Default GearBar** — vertical, three slots (upper trinket, lower trinket, head), slot
     size 40, locked (not draggable), anchored `RIGHT` at -363.7 / -144.2
   - **Demo** — horizontal, four slots (head, feet, main hand, lower finger), gear slot size 47,
     change slot size 54, unlocked (draggable), anchored `LEFT` at 280.0 / 148.7
5. Open `/rggm opt` — the QuickChange page lists no rules, and the Profiles page lists exactly
   one profile named `Default`
6. Log out and inspect the SavedVariables file

## Expected

- No Lua errors on login; the defaults backfill (`ApplyConfigurationDefaults`) runs silently.
  GearMenu Forever has no migration path, so nothing converts or logs an upgrade
- All v2.7.0 user data survives byte-for-byte: both `gearBars` entries (ids 130090 / 182509
  with their slots, sizes, positions, lock state, orientation and change menu direction), all
  scalar options, and the empty `quickChangeRules` / `frames` containers stay empty — no rules
  or frame positions are invented
- Fields introduced after v2.7.0 are present at their defaults:
  `enableFallbackToBaseItem = false`, `lastNotifiedVersion = ""`
- `GearMenuConfiguration.profiles` is created and holds **exactly one** entry named `Default`,
  seeded by `EnsureDefaultProfile()` as a snapshot of the shipped configuration defaults —
  **not** a snapshot of the imported v2.7.0 values — and `GearMenuConfiguration.activeProfile`
  reads `Default`: `EnsureActiveProfile()` adopted it (no other profile exists) and mirrored the
  imported v2.7.0 values into it, so the Profiles page shows "Default (active)" with the two
  imported gearbars. Rename/Delete refuse to touch it (see TC-PR-07)
- `addonVersion` in the file is bumped to the new release version

## Notes

The v2.6.0 schema is not identical to v2.7.0 — v2.7.0 added per-gearBar `orientation` and
`changeMenuDirection` — so this fixture covers only the v2.7.0 hop. Upgrades from older
releases rely on the nil-backfill in `SetupConfiguration` alone (GearMenu Forever has no migration
path) and are not covered by this case.

Profiles did not exist in v2.7.0, which is why this case asserts that `profiles` is *created*
rather than *preserved*. When the next release ships, snapshot a fixture that does carry saved
profiles into `test/manual/fixtures/` alongside this one and extend the case to assert those
profiles survive unchanged.
