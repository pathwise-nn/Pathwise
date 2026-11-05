# Pathwise UI

Your whole World of Warcraft: Forever interface in the Pathwise look, in your
color. A free, open-source addon by **leight_nn & florp** (`_nn`).

Works on its own. With [Pathwise](../README.md) installed too,
the two share one accent color and Pathwise UI appears in Pathwise's suite.

## Now (stage 1: look and feel)

- **Your color:** Pathwise blue, your class color (each character its own),
  or any color you type. Everything painted in it changes at once.
- **Tooltips:** a flat ground and a thin border; the border in an item's
  quality color or a player's class color; names and health bars in class
  color; tooltips at the mouse if you like.
- **Fonts:** Inter for all the game's text, at the size you choose.
- **Game windows:** character, spellbook, vendor, mail, quests and more on a
  flat ground with your accent along the top.
- **Profiles:** the same settings on every character, or each its own.
- Options: `/pwui`, the minimap button, or Pathwise's suite list.

## Unit frames (stage 2)

- You, your target, its target, your pet, your focus and your party, in the
  Pathwise look: health in your class color (players) or by how a monster
  sees you; power; names and levels; short health numbers ("12.3k").
- Click to target, right-click for the menu, in combat too.
- Debuffs on your target and party (only yours if you like), cast bars for
  you, your target and focus; combat, resting and leader marks; portraits.
- Move them (Options > Unit frames > Move the frames), size them, put them
  back; the game's own unit frames are put away while these are on.
- Forever keeps health and some other numbers "secret" from addons: bars and
  text show them, but a timer or count appears only when the game shares it.

## Action bars (stage 3)

- Five bars of the game's own secure buttons (your spells stay where they
  are): the main bar plus bar 2 and bar 3 on by default, two right bars.
- The main bar follows your stance, form or stealth, in combat too.
- Your keys for the game's bars work on these; key names, macro names and
  stack counts in Inter; your accent on hover and on what is active.
- Buttons per row (12, 6, 4, 3, 2, 1), size, spacing, empty slots, soft out
  of combat; move them, put them back; the game's bars put away.
- The stance and pet bars stay the game's for now (move them in Edit Mode).
- Experience bar: thin, in your color, right under the main bar and as wide;
  rested experience ahead of it; numbers on hover; your watched reputation
  at the level cap.
- System tray and bags: the game's own character, spellbook, talents,
  quests, social, finder, journal, help and menu buttons, and your bags,
  as slots like the action buttons, with a Pathwise glyph on each.

## The Wayfarer look

- Pathwise's Signature look (your colors, Inter, flat grounds, crisp lines)
  with soft etched edges and a light sheen on panels, buttons and bars.
- Serif titles, headings and unit frame names (Cormorant Garamond); the
  title, headings and the window's top line in a trim color, from a
  dropdown: Class (your class color), Default (gold) or Custom (any color
  on the wheel) (Options > Look).
- Capsule switches with round knobs; choices that look pressed in.

## Polish: smoother and fully yours

- **Your colors, all of them:** pick a scheme (Pathwise, Blossom, Lavender,
  Forest, Ember, Mono), then change any color on the game's color wheel:
  backgrounds, borders, text, accent, good/warning/bad, and the unit frames'
  reaction, power and debuff colors. Share a scheme as a code.
- **Motion:** buttons, the menu and switches ease into their hover color,
  switches slide, pages and windows fade, the options list
  scrolls smoothly, bars fade in and out, cast bars fade (red when
  interrupted), health and power glide (Options > Look > Motion turns it off).
- **Move everything at once:** `/pwui move` or the button at the top of the
  options; a grid to line things up, drops snap to it (Shift: free), Done.
- **Money, always shown:** your gold, silver and copper above the bags, in
  their own colors; it counts to a new amount and flashes green or red.
  Hover: this session's change and every character on the realm; click:
  your bags. All coins, gold only, or short (12.3k g).
- **Crisp lines:** borders are one screen pixel at any UI scale.

## Healing frames (off until you want them)

- Your party or raid as a grid built for healing; a priest, druid, paladin or
  shaman is asked once, and anyone can turn it on in /pwui > Healing.
- Click-casting: each click (with Shift, Ctrl or Alt) casts a spell you pick
  on the person you click; type the name or drag it from your spellbook.
- A preset for every healing spec: Holy or Discipline Priest, Restoration
  Druid, Restoration Shaman, Holy Paladin. Pathwise UI picks it from your
  talents, or choose it under /pwui > Healing > Spec. The same layout for
  every spec: left quick heal, right HoT, middle shield, Shift big heal or
  cleanse, Alt group heal or second cleanse, Ctrl target or menu, buttons 4
  and 5 your spec's own spells.
- Spells fill in as you learn them: talents like Penance, Swiftmend or Holy
  Shock appear once you have them, and a better heal replaces a lower one as
  you level. A click you set yourself is never changed.
- Heals on the way, what each person is missing (or their percent), debuffs
  you can cleanse (drawn by the game, so they show in a fight too), your
  HoTs between fights, aggro, mana, and fading out of range.
- Forever keeps health, range and auras secret from addons: the frames pass
  those straight to the game's bars and let the game draw what it hides.

## Coming next

Nameplates, chat, minimap, data bars: one stage at a time, each usable on its
own.

## Developing

Pathwise UI lives in this repository beside Pathwise (folder `PathwiseUI/`).

- `npm run test:ui` (`lua5.1 tests/ui/run.lua`): its tests (a stand-in
  client; no game needed). `npm test` runs Pathwise's and these.
- `npm run link`: links Pathwise's addons, Pathwise UI included, into the
  game's AddOns folder (`WOW_FOREVER_ADDONS` or `--dest`).
- `node tools/pack.js PathwiseUI`: its release zip in `dist/`.
- `npm run media:ui` (`node tools/media-ui.js`): redraws the textures in
  `PathwiseUI/Media`.

GPL-3.0 (see `LICENSE`). Third-party material: `THIRD_PARTY.md`.
