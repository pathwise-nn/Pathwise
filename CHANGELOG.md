# Changelog

All notable changes to Pathwise. Versions follow `major.minor.patch`; set a
new one with `npm run set-version -- <x.y.z>`, which turns "Unreleased" into
that version's section.

## Unreleased

First version of the independent Pathwise (not yet released).

### Leveling
- Leveling routes from 1 to 60 for every starting race on both sides
  (Durotar, Mulgore, Tirisfal Glades, Zephras Isle; Elwynn Forest, Dun Morogh,
  Teldrassil, Zephras Isle), handing over to the next zone by themselves.
- The guide follows the quest log: steps tick off as quests are taken,
  completed and handed in; class, race and faction steps show only to those
  characters; a quest not offered yet never holds the route.
- Skip a quest (or a quest and its follow-ups) and pick one nearby instead;
  the route resumes after it.
- Zones for your level, and a Routes panel with leveling, class quest,
  reputation, mount, pet and exploration guides.

### Pathwise Gear (new addon, part of the Pathwise suite)
- Upgrade advice in gold: a line on item tooltips ("+12.4% upgrade · Head"),
  an arrow on bag items that are upgrades, and the best quest reward.
- Scores with Pawn when it is installed, else with Pathwise's own weights per
  class and spec (from your talents, or chosen), or with a Pawn scale string
  you paste in. Shows each spec's stat priority.
- Knows what each class can wear and wield, two-handers against both hands,
  rings and trinkets against the weaker one.

### Maps and dungeons
- World map pins for the step shown (the arrow's target, the other goals,
  and where an objective's monsters are) and minimap pins that follow zoom,
  indoor scale and a rotating minimap; the arrow's target stays on the rim.
  Pathwise only reads the map, so it never taints it.
- Dungeons and raids for your level (29, Forever's own included): levels
  from the monsters inside, their quests with what stands for each, and the
  nearest entrance with an arrow to it; entrance pins on the world map.

### Professions
- Profession routes from 1 to 300 for all twelve professions, followed
  beside the leveling route: the next profession step shows in the guide
  window when it is on the way (Speed, Balanced or Crafting).
- Professions dashboard: skill, where the guide stands, the best craft now and
  how many the bags make, materials for this rank, disenchanting, and the
  Tailoring + Enchanting tip. Advice only.

### No commands needed
- A minimap button (guide, settings; drag to move), key bindings in the
  game's Key Bindings menu, and a Waypoint & tools panel (a waypoint by
  coordinates, where you are, what the arrow sees). Every command's job is in
  the menus; the commands still work.

### Interface
- The Pathwise Signature look: guide window with full and compact modes,
  waypoint arrow, settings panel with sliders and exact values, window size
  50-150%, About, and Report this step (a copyable report for Discord).

### Data and credits
- Quest facts from QuestieDB's Forever data; routes adapted from Polestar
  (both GPL-3.0; see THIRD_PARTY.md).

### Not verified in game yet
- Reading recipes from the profession window, and the Enchanting skill needed
  per item level (Classic's table, shown with "≈").
- Most routes past the Tirisfal Glades start.
