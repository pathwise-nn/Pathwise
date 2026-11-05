# Releasing on CurseForge

Steps for a maintainer. Nothing here uploads by itself: CurseForge takes the
zip by hand.

## Before every release

1. Tests pass: `npm test`.
2. Play it in Forever: a few steps of a starting zone, one profession trainer,
   the Professions dashboard, the bag window and an upgrade tooltip. Say in
   the changelog what was checked in game and what was not.
3. Check the game version. In game, type `/dump select(4, GetBuildInfo())`.
   It must match `## Interface:` in `Pathwise/Pathwise.toc` (16001 for client
   1.60.1). If Forever patched, change it in all three TOCs; the tests check
   that the three agree.
4. Set the version: `npm run set-version -- <x.y.z>`. This sets the three TOCs,
   `package.json`, and turns "Unreleased" in CHANGELOG.md into that version.
5. Build the zip: `node tools/pack.js`. It writes `dist/Pathwise-<x.y.z>.zip`
   with three folders at its root: `Pathwise/`, `Pathwise_Gear/` and
   `Pathwise_Bags/`, each with `LICENSE` and `THIRD_PARTY.md`.
   `node tools/pack.js --list` shows what goes in without building.

## The project page (first release only)

- Game: World of Warcraft. Flavor: **Forever** (game version 1.60.1).
- Name: Pathwise. Summary: "Every quest. Every craft. Every level. Leveling
  routes 1-60 and profession guides 1-300 for WoW: Forever."
- Categories: Quests & Leveling; Professions; Bags & Inventory.
- License: GNU General Public License version 3 (GPLv3).
- Source: https://github.com/pathwise-nn/pathwise
- Issues: https://github.com/pathwise-nn/pathwise/issues
- Description: paste [description.md](description.md).

## Uploading a file

- File: `dist/Pathwise-<x.y.z>.zip`.
- Display name: `Pathwise <x.y.z>`.
- Release type: **Beta** until the routes have been played in game, then
  Release.
- Game version: Forever 1.60.1 only.
- Changelog: paste that version's section of CHANGELOG.md.

## After uploading

Install it with the CurseForge app, set to Forever, on a clean AddOns folder,
and log in once: the three addons should be listed, none out of date.
