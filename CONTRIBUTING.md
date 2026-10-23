# Contributing to Pathwise

Thanks for helping. Pathwise is a free, open-source leveling and profession
companion for World of Warcraft: Forever, under GPL-3.0.

## The rules that matter most

- **Never invent game facts.** Quest IDs, NPC IDs, item IDs, coordinates,
  recipes and client APIs come from the data (QuestieDB), the routes
  (Polestar), Blizzard's Forever UI source (Gethe/wow-ui-source, `forever`
  branch), or what you checked in game. If something is not verified, say so
  in the code and the pull request.
- **Never claim a test passed you did not run,** and never claim something
  works in game unless you checked it in game.
- **Do not copy RestedXP's guides** or any other paid or proprietary guide.
- **Keep credits intact**: THIRD_PARTY.md, the headers of generated files,
  and the About panel.

## Set up

You need Lua 5.1 (`lua5.1`, `luac5.1`) and Node 24 or newer.

```bash
npm test
```

```bash
npm run link
```

`npm run link` links `Pathwise/` into the game (set `WOW_FOREVER_ADDONS` to
your `Interface\AddOns` folder first); `/reload` in game picks up changes.

## Where things are

| Path | What |
|---|---|
| `Pathwise/Core` | Start-up, settings, commands, the one place client APIs are read (`Compat.lua`) |
| `Pathwise/Guide` | Quest facts (`Quests.lua`) and the guide engine (`Engine.lua`) |
| `Pathwise/Professions` | The professions dashboard's logic |
| `Pathwise/UI`, `Pathwise/Theme`, `Pathwise/Nav` | Windows, panels, the Signature theme, the arrow |
| `Pathwise/Data/Data.lua` | Generated from QuestieDB: `npm run data` (docs/DATA.md) |
| `Pathwise/Routes/*.lua` | Generated from Polestar: `npm run routes` (tools/port/polestar.lua) |
| `tests/` | Lua tests against a stub of the game client |

Do not edit generated files by hand: change their generator and rebuild.

## Fixing a route

1. In game, open the step and use **Report this step** (the flag): paste the
   report into the issue or pull request.
2. Hand-written routes use the format at the top of `Guide/Engine.lua`.
   Quest goals only need the quest ID; the data fills in the rest.
3. Run `npm test`, then play the fix.

## Pull requests

- One change per pull request, with a line on what players will notice.
- Add a test for behaviour changes (`tests/`).
- Add a line under "Unreleased" in CHANGELOG.md.
- If an AI assistant helped, say which one in the description.
