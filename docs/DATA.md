# Where Pathwise's quest data comes from

Pathwise's quest, NPC, object and item facts come from
[QuestieDB](https://github.com/Questie/QuestieDB)'s Forever data, used
under GPL-3.0 with credit (see `THIRD_PARTY.md` for the licence note).
Routes in `Pathwise/Routes/` only list actions ("accept 363", "complete
364"); every name, giver, finisher, objective and position is read from the
data, never typed in.

## Rebuilding the data

1. Get QuestieDB's Forever sources into `data/sources/questiedb` (not
   committed). The version Pathwise was built from is commit `e19dfdf` (2026-11-11; Pathwise Loot's data is still from `1f538335`);
   only these folders are needed: `data/Forever`, `src/corrections/Forever`,
   `src/corrections/enum`, `src/meta`, `support/Forever`.
2. `npm run data` (that is `lua5.1 tools/data/build.lua`) writes
   `Pathwise/Data/Data.lua`.
3. `npm run gear:data` copies what Pathwise Gear's Best in Slot needs into
   `Pathwise_Gear/Data/Gear.lua` (the tests refuse a stale copy).
4. `npm test`, then check a few quests in game.

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

## Pathwise Loot's data

`npm run loot` builds `Pathwise_Loot/Data/Loot.lua` from the same QuestieDB
sources (through `tools/data/build.lua`, which with `PATHWISE_DATA_ONLY` set
hands its corrected data over and writes nothing) and Forever's client tables.
See `docs/LOOT.md`.

## The professions recipe book

The Recipe book pages (`Pathwise/Professions/RecipeBook.lua`) read
`Data.recipebook`. It is built in three steps, and nothing in it is typed
into the addon by hand:

1. `data/professions/<key>.json` holds the plan for each of the twelve
   professions. It covers the recipe for each skill range and how many to
   make, alternatives, a second way through some ranges (`path`), the zones,
   nodes and mobs for gathering, and the rank trainers, book sellers and
   quests by name. These facts come from
   [wow-professions.com](https://www.wow-professions.com/forever)'s Forever
   guides, with Pathwise's own wording (THIRD_PARTY.md). The guides were
   written on Forever's beta, and `untestedFrom` is where each one says it
   could not test.
2. `npm run recipebook` (`node tools/data/recipebook.js [build]`) checks the
   JSON against the Forever client's tables (wago.tools, build
   1.60.1.70790) and stops on any problem:
   - every spell must be a recipe of that profession (SkillLineAbility);
   - every item and zone must exist (Item, ItemSparse, UiMap);
   - for each faction, the plan must run 1-300 with no gap.

   It then adds the client's facts: names, reagents (SpellReagents), the item
   made, yellow and grey (TrivialSkillLineRankLow and High), and the recipe
   items that teach each spell with the skill they need. It writes
   `data/recipebook.lua`.
3. `npm run data` joins that with QuestieDB in `tools/data/build.lua`:
   - where each recipe item is sold, drops or is a quest reward;
   - the named NPCs, found by name (an NPC whose title names the
     profession comes first);
   - the quests by name, and the mobs to skin.

When this was built, all 227 named NPCs were in QuestieDB's Forever data.
The site's material counts matched the client's reagents in 161 of 163
craft lines; the other two were a rounding (100 against 99) and a page
quirk.

The guides and Pathwise's profession routes (`Routes/Professions.lua`,
from Polestar) often pick different recipes. The book is shown beside the
routes, and the routes are unchanged. Some rank trainers the guides name
differ from the routes' too (Expert Alchemy: two trainers in the guide,
six in the route). Neither has been checked in game.

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
