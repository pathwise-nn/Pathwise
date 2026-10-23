# Third-party material

| What | Used for | Licence | Where |
|---|---|---|---|
| [Inter](https://github.com/rsms/inter) by Rasmus Andersson | The interface typeface (Regular, Medium, SemiBold) | SIL Open Font License 1.1 | `Pathwise/Media/Fonts/`, licence in `Inter-OFL.txt` |
| [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team and contributors (Forever data, commit `1f538335`) | Quest, NPC, object and item facts (ids, givers, finishers, objectives, spawn positions, levels, prerequisites) that Pathwise's routes are built on | The Questie team permits use under GPL-3.0; parts of the historic data have no recorded licence from every contributor (QuestieDB `LICENSE.md`). The Questie name and logo are not used | Downloaded to `data/sources/questiedb` (not committed); Pathwise ships only the fields it needs, built by its own tools |
| Blizzard's Forever UI source ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), `forever` branch) | Checking which client APIs exist on Forever | © Blizzard Entertainment | Read while developing; nothing copied |
| [Polestar](https://github.com/fitzforge/polestar), Copyright (c) 2026 The Polestar authors | Its leveling routes (1-60, both factions, every starting race), class quest routes and profession routes, adapted into Pathwise's route format by `tools/port/polestar.lua` (what changes is listed in that file). Also a reference for how Forever behaves (secret values, map and world positions, facing, skills); Pathwise's addon code is its own | GPL-3.0 | `Pathwise/Routes/Leveling.lua`, `Class.lua`, `Professions.lua` (generated; each file names its source) |

## Works with, nothing copied

| What | How Pathwise uses it |
|---|---|
| [Pawn](https://github.com/vgermods/pawn) by Travis Spomer (CC BY-NC-ND 3.0) | Pathwise Gear calls Pawn's public functions (`PawnGetItemData`, `PawnIsItemAnUpgrade`) at run time when the player has Pawn installed, and reads Pawn's scale-string format so players can paste their own weights. No Pawn code or scale data is in Pathwise: its licence allows no derivatives |

Pathwise Gear's default weights are its own, worked out from Classic's
stat rules (`Pathwise_Gear/Weights.lua` explains how).

Everything else in this repository (code, textures drawn by `tools/media.js`,
documents) is Pathwise's own, under GPL-3.0 (see `LICENSE`).
