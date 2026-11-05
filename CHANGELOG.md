# Changelog

All notable changes to Pathwise. Versions follow `major.minor.patch`; set a
new one with `npm run set-version -- <x.y.z>`, which turns "Unreleased" into
that version's section.

## Unreleased

### Pathwise Loot (new addon)
- What every dungeon and raid boss in Forever drops, working with or without
  the other Pathwise addons: `/pwloot` or its minimap button (right-click for
  options). Its CurseForge page is still to come.
- A loot browser: Forever's 39 dungeons and raids and their 338 bosses, from
  the game's own boss list, each boss's drops with quality colors, slots and
  levels, the game's item tooltip, and shift- and ctrl-click as in the game.
  Search every boss's loot, filter by slot or by what your class can use, and
  keep a wishlist per character.
- Drops come from QuestieDB's Forever data (good for dungeons, thin for
  raids, no drop chances) and from what you see drop: a boss's corpse, the
  group's loot rolls and loot received are added to that boss as you play.
- With Pathwise Gear: upgrade marks for your spec. Item tooltips say which
  boss drops an item.
- Nothing comes from AtlasLoot: its GPL-2.0 licence can't be combined with
  Pathwise's GPL-3.0, and its data is not Forever's.
- Not yet played in game.

### Pathwise UI, Pathwise Heal, Pathwise Encounters
- They share one accent color with Pathwise Loot too.

## 0.2.2 (2026-11-05)

### Pathwise: world map pins show again
- The step numbers, the step's places, quest markers and dungeon entrances on
  the world map were drawn under Forever's map (its own frames sit far higher
  than Pathwise's pin layer did). The layer now stays above them.

### Releases
- A release uploads to CurseForge only the addons that changed: one whose only
  change is its new version number is skipped.

## 0.2.1 (2026-11-05)

### Pathwise: the guide follows the character you play
- A saved route for another race, side or class (from a deleted character of
  the same name, or one picked with `/pw route`) is let go at login and on
  Sync, and the route that suits this character is chosen instead. A side
  guide for another character is let go too.
- The first route is chosen only once the game lets the addon read race,
  class and side; before, a character whose race and side could not be read
  yet at login could be given the other side's route (Westfall for a Tauren).
- Not checked in game.

### Pathwise Encounters (new addon)
- A boss mod for Forever, working with or without the other Pathwise addons:
  `/pwenc` or its minimap button. Its CurseForge page is still to come.
- Timer bars and "soon" warnings (big text and a sound) for every Molten Core
  boss and Onyxia. Ragnaros' submerge is timed; Onyxia's phases are moved on
  with `/pwenc phase 2` and `/pwenc phase 3`. Every other Forever raid boss is
  recognised by name and fight time, with no timers yet.
- The timers are estimates: Forever closes the combat log to addons and keeps a
  boss's casts secret in a fight, so they count from the pull, using timings
  from cmangos' GPL boss scripts that have not been timed on Forever.
- The game's own encounter timeline and warnings, when Forever sends them, are
  shown in the same bars and warnings. Pathwise's timers can be put on the
  game's timeline too.
- `/pwenc pull` (the game's group countdown), `/pwenc break` (a break bar sent
  to the group) and `/pwenc range` (who is close, where the game allows it).
  Each pull is kept: kill or wipe, and how long it took.
- Not yet played in game: none of this has been checked on Forever.

## 0.2.0 (2026-11-05)

### Leveling, professions and the suite
- The guide window reads like you play: a "Step N" card with what to do right
  now (the person or quest picked out in colour, objective counts), then the
  steps ahead as a numbered list, one line per action ("Talk to ...",
  "Accept ...", "Turn in ..."). Settings: how many steps are listed.
- Automation, only for what the route asks (hold Shift to do it yourself):
  accept and hand in the route's quests, take a reward when there is no
  choice (or Pathwise Gear's pick, if you switch that on), fly where the step
  says, set the hearthstone at the step's inn, and (off by default) learn
  what the trainer has when the step is training. Each can be switched off.
- A quest item button beside the guide for the item the step wants used,
  with its own key binding.
- A leveling tracker: XP per hour this session and time to your next level
  in the guide window, and the time each level took (Settings > Leveling
  tracker > Times).
- Sync with your quest log, mark a quest or step done yourself, and quest
  markers for every quest around you on the map and minimap.
- Gathering guides for Herbalism and Mining: every Classic herb and ore node
  (about 25,000, from QuestieDB's Forever data, with the skill each needs
  from Forever's own tables) on the map and minimap in its skill-up colour,
  for the gathering professions you have; the profession's page lists the
  zones with the most skill-ups for your skill and level, and a click sets
  the arrow there. Forever's new herbs and ores have no node data yet; nodes
  in Mulgore, Eastern Plaguelands, Redridge and Stormwind are marked as not
  checked on Forever.
- Pathwise Bags: the bag key opens the window with one press (it needed two);
  selling to a vendor, tooltips with gear comparison and using items work
  from the window.
- Pathwise UI: nameplates (a slim bar in the game's own health colors, your
  target framed, cast bar and your debuffs; the game's plate no longer shows
  through), a tidier tray and bag bar, and cleaner buttons while casting.
- Releases: a version tag uploads the changed addons to their CurseForge
  projects (tools/curseforge.js, .github/workflows/release.yml).

### Pathwise Heal: click-to-heal frames as their own addon
- The healing frames (click-casting, a preset for every healing spec, heals
  on the way, cleanses, HoTs, aggro, range) move out of Pathwise UI into
  Pathwise Heal (`Pathwise_Heal/`), its own download. It works on its own:
  players who don't want Pathwise UI don't need it. Options: `/pwheal` or
  its minimap button; settings in PathwiseHealSettings.
- With Pathwise UI installed too: one accent between them (set from either;
  Pathwise UI's wins at login), and Pathwise UI's party frames step aside
  while Pathwise Heal shows your party (Pathwise Heal > Healing > "Hide
  Pathwise UI's party frames"). Pathwise UI's Healing page points to it.
- Pathwise UI's core, theme, motion, widgets, move mode, options window and
  minimap button are now shared: told who they serve by each addon's
  `Identity.lua` (name, global, saved variables, slash command, frame
  names), so both addons run side by side. `tools/kit.js` (`npm run kit`)
  copies them and the media into `Pathwise_Heal/`; the tests and
  `tools/pack.js` refuse stale copies. The options window is split into the
  shared `Options.lua` and each addon's `Pages.lua`.
- Tests: `tests/heal/` (`npm run test:heal`): the healing tests, Pathwise Heal
  alone, the copies matching, and both addons together (no clashes, one
  accent, party frames stepping aside).

### Pathwise UI joins this repository (new addon, its own CurseForge project)
- Pathwise UI (unit frames, action bars, healing frames, tooltips, fonts and
  the game's windows in the Pathwise look) moves here from its own
  repository, from its last commit there (pathwise-nn/Pathwise-UI 6e02f4b),
  as `PathwiseUI/`. It works on its own; with Pathwise it shares the accent.
- Its tests run with Pathwise's: `npm test` runs both, `npm run test:ui`
  only its own (`tests/ui/`). `tools/media-ui.js` draws its textures.
- `npm run set-version`, `tools/pack.js` and `tools/link.js` take it in;
  it shares the suite's version (0.1.1). A test checks the four agree.
- What it has so far:

#### Wayfarer look
- Signature plus Etched and Codex details: T.Etch (top highlight, bottom
  shadow, vertical sheen) on every panel, action button and tray slot;
  T.Sheen on health, power, cast, healing and experience bars.
- Cormorant Garamond Bold (OFL) for the options title, headings, the move
  bar and unit frame names; headings in title case with a fading rule.
- Trim color ("flair") from a dropdown (T.Dropdown, a new widget): Class
  (your class color), Default (each scheme's gold) or Custom (the color
  wheel, shown only then); on the Colors page and in scheme codes. The window's top line fades at both ends.
- Capsule switches (Media/disc.tga ends and knob, drawn by tools/media.js)
  with a soft knob shadow; picked choices pressed in (top inner shadow).
- The selected category's label in the trim color.

#### Healing frames (ideas from HealForever's notes and VuhDo's feature list; none of either's code or art used)
- Healing/Heal.lua, Clicks.lua, Heal.xml: a SecureGroupHeaderTemplate of
  secure unit buttons (party and raid, solo optional), off by default; a
  healer class is asked once (per character, ns.CharData).
- Health and incoming heals (UnitGetIncomingHeals) passed to bars as they
  come (secret or not); text from UnitHealthPercent with a curve or
  UnitHealthMissing + C_StringUtil.TruncateWhenZero; health color by class,
  green, or a game-evaluated color curve; range fade through
  C_CurveUtil.EvaluateColorValueFromBoolean; target edge the same way.
- Dispellable debuffs drawn by the game (C_UnitAuras.AddPrivateAuraAnchor),
  in combat too; out of combat a dispel-colored edge and your HoTs (own aura
  reads, paused when the client refuses). Aggro when UnitThreatSituation is
  readable. Mana bars.
- Click-casting: 11 mouse combos as secure attributes by spell name, class
  defaults (heal, HoT, big heal, cleanse, shield), drag a spell from the
  spellbook onto a box; applied out of combat. ClickCastFrames registered.
- Presets for every healing spec: Holy and Discipline Priest, Restoration
  Druid, Restoration Shaman, Holy Paladin (other classes: target and menu; a
  mage's Remove Lesser Curse). One layout for all: quick heal, HoT or
  instant, shield, big heal, two cleanses, group heal, target, menu and the
  spec's own spells on buttons 4 and 5. Spec from your talents (the tree with
  the most points) or a Spec dropdown on the Healing page.
- Forever's new healing spells in the presets: Penance, Prayer of Mending,
  Binding Heal, Riptide, Wild Growth, Oath of Light, named from Forever's
  class previews; not checked in game. A name the game doesn't know is
  skipped, never cast.
- Clicks fill in as you learn spells (a talent, a better heal as you level,
  a new spec), on SPELLS_CHANGED, LEARNED_SPELL_IN_SKILL_LINE, level and
  talent events, out of combat. A click you set or emptied yourself is never
  changed.
- Options page, move mode, hides the game's raid/party frames and Pathwise
  party frames while on.

#### Polish (ideas from studying EllesmereUI; none of its code or art used)
- Color schemes and every color your own (Colors page): six schemes,
  24 colors on the game's color wheel (ColorPickerFrame), right-click to
  reset one, back to the scheme, scheme codes to share (PWUI1:...).
- Motion (Anim.lua): one shared driver, idle when nothing moves; eased
  hovers, sliding switches, segmented choices with a gliding highlight,
  smooth scrolling with a fading thumb, fading windows, pages, bars, auras,
  cast bars (interrupted in red), XP numbers; health, power and experience
  eased by the game (StatusBarInterpolation, secret values included).
  "look.motion" off makes it all instant.
- Options window rebuilt: rows with label left and control right, hover
  grounds and dividers, the selected category a tab joined to the page,
  choices that look pressed in, "Move everything".
- Move mode (Movers.lua): one handle style for unit frames, bars and the
  tray (dimmed, corner brackets, plain names); a grid; drops snap to 8 px (Shift: free);
  Done locks all. /pwui move.
- Money display (Bottom/Money.lua): GetMoney/PLAYER_MONEY, gold/silver/
  copper in scheme colors (Colors > Money), counts to new amounts with a
  green/red flash, tooltip with this session and every character on the
  realm (account-wide ns.Data, untouched by resets; /pwui forget Name),
  click for bags, three styles, moves in move mode.
- Pixel-perfect 1 px borders (T.Border), one helper instead of five copies.
- Your target's accent line on party and focus frames.

#### Action bars
- Five bars of the game's own secure action buttons (ActionBarButtonTemplate)
  on Pathwise UI's bars: pages as the game's bars (main 1, bar 2 = 6,
  bar 3 = 5, right = 3, right 2 = 4); the main bar pages with stances, forms,
  stealth, vehicles and override bars through a state driver.
- Your bindings for the game's bars point at these (override bindings).
- Pathwise look: dark slot, thin border, accent on hover and checked, Inter
  key names and counts; buttons per row, size, spacing, empty slots, fade
  out of combat; move, reset; the game's action bars put away while on.
- Experience bar (UnitXP, GetXPExhaustion; reputation by
  C_Reputation.GetWatchedFactionData at the cap): as wide as the main bar and
  under it; the game's StatusTrackingBarManager put away.
- System tray and bag buttons: the game's own micro and bag buttons moved
  into two Pathwise rows, drawn as action-bar slots with glyphs; put back
  after the game lays them out again (MicroMenu, BagsBar).

#### Unit frames
- You, your target, its target, your pet, your focus (off by default) and
  your party: class-colored health (others by reaction), power, names,
  levels, short numbers; click to target, right-click for the menu.
- Debuffs (target, party; only yours optional), cast bars (you, target,
  focus), combat/resting/leader marks, portraits.
- Move, size, reset; the game's own unit frames put away while on.
- Secret values (Forever): passed straight to bars and text, never used in
  sums; timers and stack counts only when readable.

#### Look and feel

- Accent color: Pathwise blue, your class color, or one you type; shared
  with Pathwise when it is installed.
- Tooltips in the Pathwise look: flat ground, thin border by item quality or
  class color, class-colored names and health bars, optional mouse anchor.
- Inter for all the game's text, at your size; the game's font back when off.
- The game's windows on a flat ground with your accent along the top (modern
  frames only; others keep their look).
- Profiles: shared by every character or each its own; back to defaults.
- Options window (/pwui), minimap button, listed in Pathwise's suite.

#### Not checked in game yet
- Everything: the look of tooltips and windows on Forever, the fonts, the
  unit frames (health percent in particular: its 0-1 scale is a guess from
  the documentation), the action bars (casting, paging and keys in game).

## 0.1.1 (2026-11-04)

### Changed
- Pathwise Gear and Pathwise Bags are their own downloads on CurseForge,
  each needing Pathwise. Pathwise's download no longer includes them: if you
  use either, install it from its own page. Updating Pathwise may remove the
  copies that came with 0.1.0.
- `node tools/pack.js` builds one zip per addon (`dist/<Addon>-<x.y.z>.zip`);
  `docs/curseforge/` has a description and project settings for each.

## 0.1.0 (2026-11-04)

First version of the independent Pathwise, released as a beta on CurseForge.

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
- Enchanting at 225 said "Train new spells at your class trainer" instead of
  where Artisan is taught: it now says Annora teaches it inside Uldaman
  (Badlands). Riding steps in the mount guides name their riding trainer
  too, instead of the class trainer.
- Running the tests on Linux or macOS left a file named `nul` behind.
- Pathwise Gear and Pathwise Bags kept a "-dev" version when a release was
  set; `npm run set-version` now sets all three addons.
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
