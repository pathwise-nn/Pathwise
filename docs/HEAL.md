# Pathwise Heal

Click-to-heal party and raid frames for World of Warcraft: Forever, like
HealBot or VuhDo. A free, open-source addon by **leight_nn & florp** (`_nn`).

**Works on its own.** You don't need Pathwise or Pathwise UI. With either
installed it keeps the same accent color; with Pathwise UI it can hide Pathwise
UI's party frames while its own frames show your party. Options: `/pwheal`
or its minimap button.

## Healing frames (off until you want them)

- Your party or raid as a grid built for healing; a priest, druid, paladin or
  shaman is asked once, and anyone can turn it on: type /pwheal.
- Click-casting: each click (with Shift, Ctrl or Alt) casts a spell you pick
  on the person you click; type the name or drag it from your spellbook.
- A preset for every healing spec: Holy or Discipline Priest, Restoration
  Druid, Restoration Shaman, Holy Paladin. Pathwise Heal picks it from your
  talents, or choose it under /pwheal > Healing > Spec. The same layout for
  every spec: left quick heal, right HoT, middle shield, Shift big heal or
  cleanse, Alt group heal or second cleanse, Ctrl target or menu, buttons 4
  and 5 your spec's own spells.
- Spells fill in as you learn them: talents like Penance, Swiftmend or Holy
  Shock appear once you have them, and a better heal replaces a lower one as
  you level. A click you set yourself is never changed.
- Heals on the way, what each person is missing (or their percent), aggro,
  mana, and fading out of range.
- A buff row (top right): your HoTs first, with the time left in its last
  minute (red and blinking when one is about to run out), then big defensives and the
  buffs you put on them. A debuff row (along the bottom): the ones you can
  remove on the left, in their type's color, the others on the right.
- Left click on a debuff you can remove casts the spell that removes it;
  every other click on it is the frame's own. In a fight your HoTs and big
  defensives stay in the buff row (the time left only where the game lets
  addons read it), the game draws the debuff row in the same place with its
  own countdown, and your cleanse clicks (Shift or Alt + right) remove
  debuffs there.
- Forever keeps health, range and auras secret from addons: the frames pass
  those straight to the game's bars and let the game draw what it hides.

## Developing

Pathwise Heal lives in this repository beside Pathwise and Pathwise UI
(folder `Pathwise_Heal/`).

- Its own code: `Healing/` (the frames, their buff and debuff rows in
  `Auras.lua`, and click-casting), `Pages.lua` (its
  options pages) and `Identity.lua` (its name, settings and `/pwheal`).
- `Kit/` and `Media/` are **copies** of Pathwise UI's shared files (settings
  and events, theme, motion, widgets, move mode, options window, minimap
  button) and its media, so Pathwise Heal can stand alone. Edit the originals
  in `PathwiseUI/`, then run `npm run kit`. The tests fail, and
  `node tools/pack.js` refuses to build, while a copy is out of date.
- `npm run test:heal` (`lua5.1 tests/heal/run.lua`): its tests, alone and
  beside Pathwise UI. `npm test` runs every suite.

GPL-3.0 (see `LICENSE`). Third-party material: `THIRD_PARTY.md`.
