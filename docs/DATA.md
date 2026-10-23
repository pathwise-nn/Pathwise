# Where Pathwise's quest data comes from

Pathwise's quest, NPC, object and item facts come from
[QuestieDB](https://github.com/Questie/QuestieDB)'s Forever data, used
under GPL-3.0 with credit (see `THIRD_PARTY.md` for the licence note).
Routes in `Pathwise/Routes/` only list actions ("accept 363", "complete
364"); every name, giver, finisher, objective and position is read from the
data, never typed in.

## Rebuilding the data

1. Get QuestieDB's Forever sources into `data/sources/questiedb` (not
   committed). The version Pathwise was built from is commit `1f538335`;
   only these folders are needed: `data/Forever`, `src/corrections/Forever`,
   `src/corrections/enum`, `src/meta`, `support/Forever`.
2. `npm run data` (that is `lua5.1 tools/data/build.lua`) writes
   `Pathwise/Data/Data.lua`.
3. `npm test`, then check a few quests in game.

`tools/data/build.lua` runs every QuestieDB file in a sandbox that can only
build tables (no file, OS or network access).

## What the build does

- Loads QuestieDB's schemas (`src/meta`) and constants (`src/corrections/enum`).
- Loads the four Forever entity files (quests, NPCs, objects, items).
- Applies every Forever **Static Correction** in QuestieDB's own order
  (`src/config.lua`, `ownedCorrections`): replacement fields and the
  `_add`/`_remove` operations, following `src/corrections/tablePatch.lua`.
  Forever uses Classic rules, so corrections may create entities, as in
  QuestieDB.
- Maps Questie's zone ids (AreaTable) to the game's map ids (UiMap) with
  `support/Forever/Zones/areaIdToUiMapId.lua`, overrides first.
- Keeps only what Pathwise reads: per quest its name, level, required level,
  race and class masks, map, givers and finishers, objectives,
  prerequisites, exclusive quests and flags; per NPC/object its name,
  friendliness and up to 12 spawn points per map; per item where it drops.
- Estimates each zone's level range per side from the levels of the quests
  given there (10th to 90th percentile, repeatable and event quests left
  out). These are estimates, and the Zones panel says so.

## Dungeons and raids

From `support/Forever/Zones/dungeons.lua`: names, areas and entrances.
Instances with the same name are merged (Dire Maul's wings). Kept are
those with mostly hostile monsters in the data (leaving out later
expansions' instances, battlegrounds and city areas), plus Forever's own
instances (area ids from 16000), whose levels come from their quests.
Levels are the 10th to 90th percentile of the monsters' levels; a raid has
three or more monsters above level 62. Entrances QuestieDB marks as
unverified on Forever keep that mark, and the guide says so.

## Known gaps

- **Dynamic Corrections are not applied** (`LoadFactionFixes`,
  `LoadDynamic`). QuestieDB runs these in the game per character; a few
  quests differ by faction because of them.
- Objective order: the guide matches the quest log's objectives to the
  data's by position. Where they differ, the arrow may lead to the second
  objective's place first.
- QuestieDB marks a handful of positions as unverified (see its
  `docs/forever-data.md`); Pathwise takes them as they are.
- Forever race masks use bits 32 and 33 (Skyborne). They are stored whole
  and tested without the client's 32-bit `bit` library.
