# Releasing on CurseForge

Steps for a maintainer. Nothing here uploads by itself: CurseForge takes the
zips by hand.

Pathwise is five CurseForge projects, built from this one repository:

| Project | Folder | Zip | Description to paste |
|---|---|---|---|
| Pathwise | `Pathwise/` | `dist/Pathwise-<x.y.z>.zip` | [description.md](description.md) |
| Pathwise Gear | `Pathwise_Gear/` | `dist/Pathwise_Gear-<x.y.z>.zip` | [gear.md](gear.md) |
| Pathwise Bags | `Pathwise_Bags/` | `dist/Pathwise_Bags-<x.y.z>.zip` | [bags.md](bags.md) |
| Pathwise UI | `PathwiseUI/` | `dist/PathwiseUI-<x.y.z>.zip` | [ui.md](ui.md) |
| Pathwise Heal | `Pathwise_Heal/` | `dist/Pathwise_Heal-<x.y.z>.zip` | [heal.md](heal.md) |

Gear and Bags need Pathwise (`## Dependencies: Pathwise` in their TOCs).
Pathwise UI and Pathwise Heal work on their own (`## OptionalDeps`). All five
share one version; the tests check that the TOCs agree. Pathwise Heal carries
copies of Pathwise UI's shared files (`npm run kit`); the build refuses stale
copies.

## Before every release

1. Tests pass: `npm test`.
2. Play it in Forever: a few steps of a starting zone, one profession trainer,
   the Professions dashboard, the bag window and an upgrade tooltip. For
   Pathwise UI: the unit frames and casting from its action bars in combat.
   For Pathwise Heal, on a healer in a group, alone and with Pathwise UI:
   click-cast a heal, the Spec dropdown, a spell you learn filling in. Say in the changelog what was
   checked in game and what was not.
3. Check the game version. In game, type `/dump select(4, GetBuildInfo())`.
   It must match `## Interface:` in the five TOCs (16001 for client 1.60.1).
   If Forever patched, change it in all five.
4. Set the version: `npm run set-version -- <x.y.z>`. This sets the five TOCs,
   `package.json`, and turns "Unreleased" in CHANGELOG.md into that version.
5. Build the zips: `node tools/pack.js`. It writes one zip per project, each
   with its addon folder at the root, plus `LICENSE` and `THIRD_PARTY.md`.
   `node tools/pack.js Pathwise_Gear` builds just one;
   `node tools/pack.js --list` shows what goes in without building.

Upload a new file only to the projects whose addon changed; a version where
only Pathwise changed needs only the Pathwise upload.

## The project pages (once per project)

For all five:

- Game: World of Warcraft. Flavor: **Forever** (game version 1.60.1).
- License: GNU General Public License version 3 (GPLv3).
- Source: https://github.com/pathwise-nn/pathwise
- Issues: https://github.com/pathwise-nn/pathwise/issues

| | Pathwise | Pathwise Gear | Pathwise Bags | Pathwise UI | Pathwise Heal |
|---|---|---|---|---|---|
| Summary | Every quest. Every craft. Every level. Leveling routes 1-60 and profession guides 1-300 for WoW: Forever. | Is this an upgrade for me? Upgrade arrows, tooltip advice, the best quest reward and Best in Slot (Level) for WoW: Forever. | One bag window that knows what you need: sorted bags, keep and junk marks, and junk selling for WoW: Forever. | Your whole interface, in your color: unit frames, action bars, nameplates, tooltips and fonts for WoW: Forever. | Click-to-heal party and raid frames, like HealBot or VuhDo, with a preset for every healing spec, for WoW: Forever. |
| Categories | Quests & Leveling; Professions | Bags & Inventory; Tooltip | Bags & Inventory | the closest to Unit Frames, Action Bars | the closest to Raid Frames, Healer, Unit Frames |
| Relations | none | Pathwise: **Required Dependency** | Pathwise: **Required Dependency**; Pathwise Gear: **Optional Dependency** | Pathwise: **Optional Dependency** | Pathwise, Pathwise UI: **Optional Dependency** |

With the relations set, the CurseForge app installs Pathwise when someone
installs Gear or Bags.

## Uploading a file

- File: the project's zip from `dist/`.
- Display name: `Pathwise <x.y.z>`, `Pathwise Gear <x.y.z>`, `Pathwise Bags <x.y.z>`,
  `Pathwise UI <x.y.z>`, `Pathwise Heal <x.y.z>`.
- Release type: **Beta** until it has been played in game, then Release.
- Game version: Forever 1.60.1 only.
- Changelog: that version's section of CHANGELOG.md.

## Moving players from 0.1.0 (once, for 0.1.1)

Pathwise 0.1.0 shipped Gear and Bags inside its own zip. When the CurseForge
app updates Pathwise to 0.1.1, it may remove the `Pathwise_Gear` and
`Pathwise_Bags` folders that came with 0.1.0. So:

1. Publish Pathwise Gear and Pathwise Bags (and wait for their approval)
   before uploading Pathwise 0.1.1.
2. Keep the note in [description.md](description.md) and the changelog
   telling players to install them from their own pages.

## After uploading

Install each with the CurseForge app, set to Forever, on a clean AddOns
folder, and log in once: the addons should be listed, none out of date.
Install Pathwise Gear alone once to check that the app brings Pathwise with it.
For Pathwise UI: `/pwui` opens. For Pathwise Heal, log in once on a healer:
the healing question is asked once, and `/pwheal` opens.
