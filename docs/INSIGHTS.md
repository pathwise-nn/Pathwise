# Pathwise Insights: shared numbers for the guides

Players can send their leveling numbers from Pathwise Insights so we can
tune the routes. This page covers what a share code holds, how players send
one, and how to read the codes.

## What a share code holds

A character's numbers, kept on the player's computer until they copy the
code. In game it is under **Insights > Share with Pathwise > Make a share code**.

- **The character:** race, class, faction, level, time played, XP, and the
  Pathwise version.
- **Each guide step timed (the newest 600):**
  - route, step, and the Pathwise version it was timed on
  - seconds, XP, deaths and kills
  - yards walked, and seconds spent flying and in a group
  - the level, how the step ended (done, skipped, marked, moved), and where
    (zone, x, y)
- **Each quest (the newest 600):** play time from taking it to handing it
  in, the XP it paid, the level, and where it was taken and handed in. Or
  that it was abandoned.
- **Each death (the newest 200):** where, at what level, and on which step.
- **Totals:** time, XP and deaths per route, level and zone.

A random id, made once per character, stands in for the character, so a
newer code replaces an older one. The code never holds the character's
name, realm or guild, its path on the map, or anything about other players.

Format: `PWI1:<base64>:<checksum>`. The line layout is described at the top
of `Pathwise_Insights/Share.lua`. The checksum catches a code that was cut
short or changed by hand.

## How players send one

- **GitHub:** the "Share leveling numbers" issue form
  (`.github/ISSUE_TEMPLATE/leveling_numbers.yml`). It is public, and the form
  says so.
- **Discord:** the Pathwise Discord (the invite is on the share page).

## Reading the codes

Save the codes anywhere under `data/insights/`. That folder is ignored by git,
so codes are never committed. Any text works: saved issues, a Discord
export, a file of pasted codes. Then run:

```
npm run insights
npm run insights -- path/to/file-or-folder --out report.txt
```

The report covers:

- **Routes, by the Pathwise version the steps were timed on:**
  - the median time to finish and XP an hour
  - each step's median and 75th-percentile time, skips, deaths, kills,
    yards, and the share of time flying and grouped
  - steps flagged **SLOW** (over 2.5 times the route's usual step),
    **LONG WALK**, **OFTEN SKIPPED** (40% or more) and **DEADLY** (a death
    every other time or more)
- **Quests:**
  - median time, XP and XP a minute
  - **SLOW FOR ITS XP** (under 40% of the usual XP a minute)
  - **OFTEN ABANDONED** (30% or more)
  - the median spot where players took and handed each quest in. It is
    checked against Pathwise's data and flagged when it is more than 3% of
    the map from the person or object the data names, or when the data has
    no one on that map.
- **Where players die:** spots 2% of the map across, with the level and the
  step.
- **Time per level.**

A flag needs at least three players. The report holds only medians and
counts, never one player's codes.
