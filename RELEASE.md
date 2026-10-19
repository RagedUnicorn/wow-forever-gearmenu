# Release

> This document explains how a new release is created for GearMenu

## Versioning

This repository is the World of Warcraft: Forever line of GearMenu and releases `3.x` versions
(3.0.0, 3.1.0, 3.1.1, ...). The Classic line in
[wow-classic-gearmenu](https://github.com/RagedUnicorn/wow-classic-gearmenu) stays on `2.x`. Both
lines publish into the same CurseForge and Wago projects as separate files.

## Version bump

* Bump `<version>` in `pom.xml` (`addon.tag.version` and the `## Version:` line of the TOC are derived from it)
* Regenerate the sources: `mvn generate-resources -D generate.sources.overwrite=true -P development`
  and commit the regenerated `GearMenu.toc` and `code/Environment.lua`

## Pre-release testing

Complete the test procedure in [test/TESTING.md](test/TESTING.md) before creating any deployment:

* Automated gates - luacheck and busted must be green (locally and in CI)
* Full manual test case catalog ([test/manual/](test/manual/)) on WoW: Forever

## Deployment

Push all commits before proceeding
* Make sure `build-resources/release-notes.md` are up-to-date
* Make sure Metadata https://github.com/RagedUnicorn/wow-gearmenu-meta is up-to-date. The store
  description is shared with the Classic line - it has to stay correct for both
* Make sure the repository secret `TOKEN_CURSEFORGE` exists
* Create a GitHub deployment (from `master`)
  * Invoke GitHub action
    * https://github.com/RagedUnicorn/wow-forever-gearmenu/actions/workflows/release_github.yaml
* Create a CurseForge deployment (from `master`)
  * Invoke CurseForge action
    * https://github.com/RagedUnicorn/wow-forever-gearmenu/actions/workflows/release_curseforge.yaml
* Wago: no deployment yet - wago-release-maven-plugin cannot set Wago's Forever game version
