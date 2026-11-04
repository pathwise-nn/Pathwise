# Third-party material

| What | Used for | Licence | Where |
|---|---|---|---|
| [Inter](https://github.com/rsms/inter) by Rasmus Andersson | The interface typeface (Regular, Medium, SemiBold) | SIL Open Font License 1.1 | `Pathwise/Media/Fonts/`, `PathwiseUI/Media/Fonts/` and `Pathwise_Heal/Media/Fonts/`, licence in `Inter-OFL.txt` |
| [Cormorant Garamond](https://github.com/CatharsisFonts/Cormorant) by Christian Thalmann (Catharsis Fonts) | Pathwise UI's and Pathwise Heal's Wayfarer serif: window title, headings, unit frame names (Bold) | SIL Open Font License 1.1 | `PathwiseUI/Media/Fonts/` and `Pathwise_Heal/Media/Fonts/`, licence in `CormorantGaramond-OFL.txt` |
| [QuestieDB](https://github.com/Questie/QuestieDB) by the Questie team and contributors (Forever data, commit `1f538335`) | Quest, NPC, object and item facts (ids, givers, finishers, objectives, spawn positions, levels, prerequisites) that Pathwise's routes are built on | The Questie team permits use under GPL-3.0; parts of the historic data have no recorded licence from every contributor (QuestieDB `LICENSE.md`). The Questie name and logo are not used | Downloaded to `data/sources/questiedb` (not committed); Pathwise ships only the fields it needs, built by its own tools |
| Blizzard's Forever client tables (SkillLineAbility, SpellEffect, Item, ItemSparse, ItemEffect, ItemXItemEffect), as CSV from [wago.tools](https://wago.tools) (product `wowf`) | Recipes for Pathwise Gear's crafted gear: which profession and skill make each item, which recipe item teaches it, the item's type and levels. `tools/data/recipes.js` follows Polestar's profession tool's method (below), keeping Season of Discovery recipes, marked | © Blizzard Entertainment | Downloaded to `data/sources/wago/` (not committed); `data/recipes.lua` is generated from them |
| Blizzard's Forever UI source ([Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), `forever` branch) | Checking which client APIs, events and fonts exist on Forever; `PathwiseUI/Skins/FontNames.lua` lists the client's font names from it | © Blizzard Entertainment | Read while developing |
| [Polestar](https://github.com/fitzforge/polestar), Copyright (c) 2026 The Polestar authors | Its leveling routes (1-60, both factions, every starting race), class quest routes and profession routes, adapted into Pathwise's route format by `tools/port/polestar.lua` (what changes is listed in that file). Also a reference for how Forever behaves (secret values, map and world positions, facing, skills); Pathwise's addon code is its own | GPL-3.0 | `Pathwise/Routes/Leveling.lua`, `Class.lua`, `Professions.lua` (generated; each file names its source) |

## References, nothing copied

Pathwise Gear's weights are its own numbers. The order of stats for each spec
follows these guides, and the stat rules follow Warcraft Tavern's. Only the
facts (which stat comes before which, and how many points give what) are
used. None of their text is in Pathwise (`Pathwise_Gear/Weights.lua`
explains how the numbers were set).

| Reference | Used for |
|---|---|
| [Icy Veins: WoW Forever class guides](https://www.icy-veins.com/wow-forever/all-class-guides) | Each spec's stat priority at level 30; their Classic Era guides for level 60 |
| [Mobalytics: WoW Forever class guides](https://mobalytics.gg/wow-forever/classes) | Each spec's levelling stat priority, and Forever's talent changes that move it |
| [Warcraft Tavern: WoW Forever stats guide](https://www.warcrafttavern.com/forever/guides/stats/) | Forever's stat rules (attack power, crit, Spirit for healers, Haste) |
| [Wowhead: WoW Forever class guides](https://www.wowhead.com/forever/guides/classes) | Read as a cross-check; they list gear rather than stat orders |

Pathwise Gear's "Best in Slot (Level)" list is worked out in game: which items
exist and where they come from is QuestieDB's Forever data (above), their
stats are what the game client reports. ForeverChanges' BiS lists (its terms
forbid copying its compiled data) and Foresight's data (all rights reserved
since 15 October 2026) were looked at and are not used.

Pathwise Bags is its own code. Features were compared with
[Bagnon](https://github.com/Jaliborc/Bagnon) (its code is All Rights Reserved)
and Baganator by plusmouse (its main source is not public); nothing of either
is used. Its item buttons are the game's own (`ContainerFrameItemButtonTemplate`).

Pathwise Gear needs no other addon. Its custom-weights box also reads the
`( Pawn: v1: ... )` text format that guide sites share, without Pawn
installed; no Pawn code is in Pathwise.

Pathwise UI is its own code. [ElvUI](https://github.com/tukui-org/ElvUI)
(Tukui) was the reference for what a complete interface addon offers and how
its options are laid out; ElvUI's code is all rights reserved and none of it
is in Pathwise UI (its unit frames are its own, not oUF; its action bars use
the game's own action buttons, not LibActionButton). Its polish came from
studying EllesmereUI; none of its code or art is used. Pathwise Heal is its
own code too: its healing frames came from HealForever's notes and VuhDo's
feature list; none of their code or art is used. The names of Forever's new
healing spells in its click-casting presets (Penance, Prayer of
Mending, Binding Heal, Riptide, Wild Growth, Oath of Light) come from
coverage of Forever's class changes, such as
[Maxroll](https://maxroll.gg/wow-forever/news/wow-forever-class-deep-dives-whats-changing-for-all-nine-classes),
[games.gg](https://games.gg/world-of-warcraft/guides/wow-forever-every-class-new-ability-and-talent-change/)
and [MMOEXP](https://www.mmoexp.com/News/wow-forever-class-changes-new-abilities-talent-reworks-and-what-players-can-expect.html);
only the spell names are used, and they are not yet checked in game.

Everything else in this repository (code, textures drawn by `tools/media.js`
and `tools/media-ui.js`, documents) is Pathwise's own, under GPL-3.0 (see
`LICENSE`).
