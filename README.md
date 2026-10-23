# Pathwise

**Every quest. Every craft. Every level.**

A free, open-source leveling and profession companion for World of Warcraft:
Forever. Created by leight_nn & florp. `_nn`

> Early development. What works today: leveling routes from 1 to 60 for
> every starting race on both sides, class quest routes, profession routes
> (1-300) followed beside your leveling route, a professions dashboard
> (materials for this rank, best craft now, disenchanting, Tailoring +
> Enchanting; `/pw prof`), the guide engine following your
> quest log, skipping quests with nearby alternatives, zones for your level, a
> settings panel, the Pathwise Signature interface and the waypoint arrow.
> Routes are adapted from Polestar (GPL-3.0); quest data comes from
> QuestieDB (see `docs/DATA.md` and `THIRD_PARTY.md`).

## Try it

1. Set where your game's AddOns folder is (once), then reopen PowerShell:
   `setx WOW_FOREVER_ADDONS "G:\World of Warcraft\_classic_beta_\Interface\AddOns"`
2. Link the addon into the game: `npm run link`
3. In game, everything is in the guide window: the gear opens Settings, the
   map button opens Zones for your level, Skip offers alternatives. The same
   things as commands:
   - `/pw` shows or hides the guide window
   - `/pw settings`, `/pw zones`, `/pw skip`, `/pw route`
   - `/pw demo` previews it with a sample step
   - `/pw compact` switches full and compact mode
   - `/pw way 45 62 Inn` points the arrow at a spot on your current map (Shift-drag to move the arrow)
   - `/pw opacity 80` sets the window background opacity
   - `/pw help` lists everything

## Develop

Needs Lua 5.1 (`lua5.1`) and Node 24 or newer.

- `npm test` runs the tests (a stub of the game client; nothing here proves
  in-game behaviour)
- `npm run media` redraws the textures in `Pathwise/Media/`

## Licence

GPL-3.0. See `LICENSE` and `THIRD_PARTY.md`.
