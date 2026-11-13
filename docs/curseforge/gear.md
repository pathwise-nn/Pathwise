# Pathwise Gear

**Is this an upgrade for me?**

Upgrade advice for World of Warcraft: Forever, in gold. Works on its own;
with [Pathwise](https://github.com/pathwise-nn/pathwise) installed too, you
also get Best in Slot (Level) and Pathwise's arrow.

**Beta.** First release on its own page. Stat names for Haste and Expertise
on Forever items are not yet checked in game.

## What it does

- **A line on item tooltips**: "+12.4% upgrade · Head", "You can't wear this
  armour", "From level 13".
- **A gold arrow** on bag items that are upgrades.
- **The best quest reward**: when a quest offers a choice, Pathwise Gear
  says which to take, in chat and on its tooltip.
- **Best in Slot (Level)** (needs Pathwise): slot by slot, the best item you can get by now
  (or a few levels ahead), where it comes from (quest, dungeon and boss,
  monster, vendor, world drop) and whether you have it. Click a slot and the
  Pathwise arrow leads there. Crafted gear is included: what you can craft,
  or what to buy from a crafter.
- A best-in-slot item you pick up is announced on screen, and gets a gold
  star in your bags.

## How it scores

- Pathwise's own stat weights for all 27 specs, ordered as the Icy Veins and
  Mobalytics Forever guides advise and spaced by Forever's stat rules. It
  picks your spec from your talents, or you choose.
- Knows what each class can wear and wield; weighs a two-hander against both
  hands, and rings and trinkets against the weaker one.
- Optional: paste your own weights ("Intellect=1.2, Stamina=0.5", or a
  scale string from a guide site).
- Scores on its own: needs no other gear addon.

## Credits

Created by leight_nn & florp. Where items come from: QuestieDB's Forever
data; recipes: Forever's game files. Free software under the GNU General
Public License, version 3. Not affiliated with Blizzard Entertainment.

Source: https://github.com/pathwise-nn/pathwise
Discord: https://discord.gg/hSDjBrG8EK
