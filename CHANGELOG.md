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

### Professions
- Profession routes from 1 to 300 for all twelve professions, followed
  beside the leveling route: the next profession step shows in the guide
  window when it is on the way (Speed, Balanced or Crafting).
- Professions dashboard: skill, where the guide stands, the best craft now and
  how many the bags make, materials for this rank, disenchanting, and the
  Tailoring + Enchanting tip. Advice only.

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
