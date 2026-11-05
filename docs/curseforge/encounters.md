# Pathwise Encounters

**Know what the boss does next.**

A boss mod for World of Warcraft: Forever: timer bars, warnings, and pull and
break timers. **Works on its own**: no other addon needed. With Pathwise,
Pathwise UI or Pathwise Heal installed, it uses the same accent color.

**Beta.** This is Pathwise Encounters' first release and it has not yet been
played in Forever. Its timers are estimates (see below). Tell us on Discord how
they compare with your raid's fights.

## Boss timers

- Timer bars for **Molten Core** (every boss) and **Onyxia**: what's coming
  up, soonest first, with the boss's name and the fight's time above them.
- A warning in the middle of the screen, with a sound, a few seconds before
  each ability ("Impending Doom soon").
- Ragnaros' submerge and the Sons of Flame are timed by the addon. For Onyxia,
  type `/pwenc phase 2` when she lifts off and `/pwenc phase 3` when she
  lands.
- Every raid boss in Forever is recognised: Blackwing Lair, Zul'Gurub, both
  Ahn'Qiraj raids and Naxxramas show the boss and the fight's time. Their
  timers are still to come.
- Your pulls are kept: each boss, kill or wipe, and how long it took.

**Why "about"?** Forever doesn't let addons see a boss's casts during a fight,
so the timers count from the pull. Their timings come from an open-source
server's boss scripts, not from Forever itself, so each bar says "about".

## The game's own boss warnings

Forever's client has Blizzard's own encounter timeline and warnings. When the
game sends them for a fight, Pathwise Encounters shows them in its own bars
and warnings, including the ones that say an ability is aimed at you. It can
also put its own timers on the game's timeline.

## Pull, break and range

- `/pwenc pull 10`: the game's countdown for your whole group (lead or
  assist), with a bar.
- `/pwenc break 5`: a break bar for you and everyone in the group who has
  Pathwise Encounters.
- `/pwenc range 10`: who in your group is that close. Forever stops telling
  addons distances during a boss fight, and the window says so.

## Your look

Your accent color (Pathwise blue, your class color or any color), color
schemes, smooth motion and crisp lines, in the same clean look as the other
Pathwise addons. Move the bars with everything else. Settings can be shared
by every character or kept per character. Options: `/pwenc` or the minimap
button. `/pwenc test` shows sample bars.

## Credits

Created by leight_nn & florp. Inter by Rasmus Andersson and Cormorant
Garamond by Christian Thalmann (SIL Open Font License). Boss timings are taken
from the cmangos project's boss scripts (GPL). Encounter and spell names come
from Forever's own game data. Deadly Boss Mods' feature list was the model for
what a boss mod should do; none of its code, timings or art is used. Free
software under the GNU General Public License, version 3. Not affiliated with
Blizzard Entertainment.

Source: https://github.com/pathwise-nn/pathwise
Discord: https://discord.gg/hSDjBrG8EK
