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
- Scores on its own, needing no other addon: Pathwise's weights for all 27
  specs, ordered as the Icy Veins and Mobalytics Forever guides advise and
  spaced by Forever's stat rules (Warcraft Tavern). Picks the spec from your
  talents, or you choose. Shows each spec's stat priority.
- Forever's stats: shared crit for casters and melee, attack power that
  counts for ranged, Haste and Expertise (their names on items are not yet
  checked in game).
- Optional custom weights you paste in ("Intellect=1.2, Stamina=0.5").
- Best in Slot (Level): slot by slot, the best item this character can
  get by now (or a few levels ahead), where it comes from (quest, dungeon
  and boss, monster, vendor, world drop) and whether you have it. Click a
  slot: the arrow leads to the quest giver, dungeon entrance, monster or
  vendor. Worked out in game from the item stats the game gives and
  QuestieDB's Forever data; no BiS site's lists are used.
- Crafted gear in the list (1,576 weapons and armour from Forever's recipes):
  "Craft it: Tailoring 110", the recipe and where it is sold or drops (the
  arrow leads there), or "Crafted: ... (Auction House or a crafter)" for
  someone else's craft. Bind-on-pickup crafts count only for their crafter.
  Choose all crafts, only your professions', or none. Season of Discovery
  recipes Forever's files hold (99 make gear) are shown, marked "found in
  Forever, not confirmed", and can be hidden.
- Picking up a best-in-slot item for your level, or for the higher level it
  needs, is announced on screen with a sound and a chat line; such items
  get a gold star in the bags and a "Best in slot" tooltip line.
- Knows what each class can wear and wield, two-handers against both hands,
  rings and trinkets against the weaker one.

### Pathwise Bags (new addon, part of the Pathwise suite)
- One bag window in the Pathwise look (green), opened by your bag key: items
  grouped by what they are to you (Quest, Upgrades, Equipment, Consumables,
  Professions, Other, Junk) or as one grid; search by name, quest, upgrade or
  junk; the game's sort; free slots and money. Uses the game's own item
  buttons, so using, selling and dragging work as usual. Can be turned off.
- Markers on items: needed for a quest (in your log or later), material for
  your profession route, Pathwise Gear upgrade or best in slot, kept by you,
  can be sold.
- Selling junk: a "Sell junk" button on the vendor window with the count and
  gold (or sell on its own): greys and items you mark; optionally bound gear
  you can't use or is worse. Never what you keep, quest items you need,
  profession materials, upgrades.
- Bag space: a warning when bags are nearly full, with what to let go first.
- Mark items: keep (never sold) or junk, from the bag window.

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
- Professions: a list of yours with skill and what is next; click one for its
  page. Professions dashboard: skill, where the guide stands, the best craft now and
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

### Suite
- Accent colour (Settings > Colour): Pathwise blue, your class colour, or one
  you type; "Whole suite in this colour" puts Gear, Bags and the rest in it
  too. Pathwise UI, when installed, keeps the same accent.
- Each suite addon has its own minimap button in its colour (Pathwise Gear:
  gold arrow, Pathwise Bags: green bag), placed apart, draggable, each with
  its own show/hide switch; its settings open beside it.
- Back in the side panel: from a suite addon's settings to where you came
  from, or to Pathwise's settings.

### Fixed
- Map pins for an objective's monsters had lost the monster's name.
- Settings, Professions and the other panels drew at the top left of the
  screen with "anchor family connection" errors: the panel's scrolling area
  was anchored to its own contents.
- Sliders swung between their ends while dragged ("Window size" moved the
  panel under the pointer): the panel now holds still while a slider is
  dragged, and the value follows the pointer step by step.
- Count sliders (bag window width, free slots) showed "1200 %".
- Setting labels ran under their buttons; they now wrap.
- The bag key opened the Pathwise bag window and closed it at once.
- An error at login on Forever: Pathwise listened for a Classic event name
  (LEARNED_SPELL_IN_TAB); it uses Forever's (LEARNED_SPELL_IN_SKILL_LINE)
  and skips any event the client does not have. Tests now reject events
  Forever lacks.

### Not verified in game yet
- Reading recipes from the profession window, and the Enchanting skill needed
  per item level (Classic's table, shown with "≈").
- Most routes past the Tirisfal Glades start.
