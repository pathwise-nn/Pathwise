# Pathwise

**Every quest. Every craft. Every level.**

A free, open-source leveling and profession companion for World of Warcraft:
Forever. Created by leight_nn & florp. `_nn`

> Early development. What works today: leveling routes from 1 to 60 for
> every starting race on both sides, class quest routes, profession routes
> (1-300) followed beside your leveling route, a professions dashboard
> (materials for this rank, best craft now, disenchanting, Tailoring +
> Enchanting), dungeons for your level, map and minimap pins, the guide engine following your
> quest log, skipping quests with nearby alternatives, zones for your level, a
> settings panel, the Pathwise Signature interface and the waypoint arrow.
> Routes are adapted from Polestar (GPL-3.0); quest data comes from
> QuestieDB (see `docs/DATA.md` and `THIRD_PARTY.md`).

## New in 0.3

- **The Signature Hub**: Pathwise's full window. Your routes (with each
  zone's map and your route across it), your professions and the whole
  step in one place. Opens from the minimap button, `/pw hub` or a key.
- **Three guide styles** while you play: **Tracker** (a compact card, the
  default), **Window** (the guide window with tabs) and **Minimal** (text
  over the game, no window). Switch in the hub under *On screen*, in
  Settings, with `/pw style tracker|window|minimal`, or with a key.
- **The compass**: a heading strip across the top of the screen with the
  step's place, its distance and coordinates, and **your own coordinates**
  under it. Turn it off and the old arrow comes back: Settings,
  `/pw compass`, `/pw compass coords`, or a key.
- **Themes**: 17 of them, dark and light (Pathwise Blue, Midnight,
  Graphite, Rose, Amethyst, Emerald, Ocean, Gold, Sunset, Crimson, High
  Contrast; Snow, Sky, Blossom, Lavender, Mint, Sand), shared by every
  Pathwise addon. Settings > Theme or `/pw theme <name>`.
- **Rounded, resizable, pinnable**: every Pathwise window has rounded
  corners; drag a window's corner grip to any size; the pin keeps a window
  where it is. Settings is a window of its own.
- **Faction crests** (Alliance and Horde) and class and profession icons.

## The Pathwise addons

This repository holds eight addons, each its own download:

| Addon | Folder | What it is |
|---|---|---|
| Pathwise | `Pathwise/` | The leveling and profession guide |
| Pathwise Gear | `Pathwise_Gear/` | Upgrade advice; needs Pathwise |
| Pathwise Bags | `Pathwise_Bags/` | One bag window that knows what you need; works on its own, quest and profession markers with Pathwise, upgrade markers with Pathwise Gear |
| Pathwise UI | `PathwiseUI/` | Unit frames, action bars, tooltips, fonts, the game's windows; works on its own ([docs/UI.md](docs/UI.md)) |
| Pathwise Heal | `Pathwise_Heal/` | Click-to-heal party and raid frames with a preset for every healing spec; works on its own ([docs/HEAL.md](docs/HEAL.md)) |
| Pathwise Encounters | `Pathwise_Encounters/` | A boss mod: boss timers and warnings, pull and break timers; works on its own ([docs/ENCOUNTERS.md](docs/ENCOUNTERS.md)) |
| Pathwise Loot | `Pathwise_Loot/` | What every dungeon and raid boss drops: a loot browser, search, a wishlist; works on its own, upgrade marks with Pathwise Gear ([docs/LOOT.md](docs/LOOT.md)) |
| Pathwise Insights | `Pathwise_Insights/` | Your leveling numbers for every character: totals, records, when you play, routes, zones and levels, and a heat map of where you went; kept on your computer; works on its own ([docs/INSIGHTS.md](docs/INSIGHTS.md)) |

## Try it

1. Set where your game's AddOns folder is (once), then reopen PowerShell:
   `setx WOW_FOREVER_ADDONS "G:\World of Warcraft\_classic_beta_\Interface\AddOns"`
2. Link the addons into the game: `npm run link`
3. In game, everything is in Pathwise's menus; no commands needed:
   - **Minimap button**: click to open the hub, right-click for Settings,
     drag to move it.
   - **The hub**: Leveling, Professions, Routes and Dungeons on the left,
     and *On screen*: the guide style (Tracker, Window, Minimal or hidden),
     the compass and your coordinates.
   - **The guide on screen**: the hub, compass, collapse and close buttons
     on the tracker; tabs (Guide, Routes, Professions, Dungeons) on the
     window.
   - **Footer**: Back, Skip (with quests nearby instead), Report this step
     (flag), Next.
   - **Settings**: window size and opacity, the arrow, map pins, the minimap
     button, routes and the side guide, profession detours, Waypoint & tools,
     About.
   - **Key bindings**: Game Menu > Key Bindings > Pathwise.

   Commands still work for those who like them (`/pw help` lists them).

## Develop

Needs Lua 5.1 (`lua5.1`) and Node 24 or newer.

- `npm test` runs the tests (a stub of the game client; nothing here proves
  in-game behaviour): Pathwise's (`tests/`), Pathwise UI's (`tests/ui/`),
  Pathwise Heal's (`tests/heal/`), Pathwise Encounters' (`tests/encounters/`)
  and Pathwise Loot's (`tests/loot/`)
- `npm run kit` copies Pathwise UI's shared files into Pathwise Heal,
  Pathwise Encounters and Pathwise Loot (`docs/HEAL.md`)
- `npm run loot` rebuilds Pathwise Loot's boss and drop data (`docs/LOOT.md`)
- `npm run media` redraws the textures in `Pathwise/Media/`;
  `npm run media:ui` those in `PathwiseUI/Media/`
- `node tools/pack.js` builds one release zip per addon in `dist/`
- `npm run preview` draws the interface without the game: it runs
  Pathwise's Lua against the test client, lays the frames out as the game
  does and photographs them in Chromium (`preview/*.png`: the hub, each
  guide style, every window, the other addons' windows, in any theme).
  Needs `pip install lupa pillow` and Playwright. A picture of what
  Pathwise asks the game to draw, not the game itself: game art is stood
  in for.

## Licence

GPL-3.0. See `LICENSE` and `THIRD_PARTY.md`.
