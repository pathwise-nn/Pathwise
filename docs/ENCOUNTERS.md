# Pathwise Encounters

A boss mod for World of Warcraft: Forever, by **leight_nn & florp**. **Works
on its own.** With Pathwise, Pathwise UI or Pathwise Heal installed, it shares
their accent color. Options: `/pwenc` or its minimap button.

**Not yet played in game.** Everything below has been checked against
Blizzard's Forever UI source and the tests' client stub only.

## What it does

- **Timer bars** for every Molten Core boss and Onyxia: abilities coming up,
  soonest first. Above them are the boss's name, the fight's time and the
  phase.
- **Warnings**: big text and the raid warning sound a few seconds before each
  ability (`enc.warnBefore`, 5 s), on a phase change, at the pull and on a
  kill.
- **Phases**: Ragnaros changes phase by the clock (3 minutes up, then about
  93 s under the lava). For Onyxia, the raid types `/pwenc phase 2` and
  `/pwenc phase 3`.
- **Every raid boss is recognised**, along with dungeon and world bosses
  (`enc.dungeons`), and gets a header with its name and the fight's time.
- **Pull history**: each pull's encounter, kill or wipe, length and phase is
  kept in `ns.Data("pulls")` (100 pulls). These are the first step towards
  timings observed on Forever.
- **The game's own boss mod**: the client's encounter timeline
  (`ENCOUNTER_TIMELINE_EVENT_*`) is shown as bars, and its warnings
  (`ENCOUNTER_WARNING`) are shown in the Pathwise style. Pathwise's timers can
  also go onto the game's timeline (`enc.pushTimeline`, off).
- `/pwenc pull [s]` (`C_PartyInfo.DoCountdown`, the game's group countdown;
  alone or when refused, a bar just for you), `/pwenc break [min]` (a bar,
  sent as addon message `PathwiseEnc` `BREAK:<seconds>`), `/pwenc range [yd]`
  (`UnitDistanceSquared`, when the game answers), `/pwenc test`,
  `/pwenc stop`, `/pwenc move`.

## What Forever allows (wow-ui-source, `forever` branch)

| | On Forever | So |
|---|---|---|
| Combat log | `GetCurrentEventInfo` is only in `C_CombatLogSecure` (SecureOnly) | No timer follows a boss's casts |
| `UNIT_SPELLCAST_*`, `UnitCastingInfo` | `SecretWhenUnitSpellCastRestricted` | Same |
| Auras, `UnitGUID`, `UnitName`, `UnitIsUnit` | Secret under restriction | "Targets you" can't be decided by an addon |
| Boss emotes and yells | `SecretInChatMessagingLockdown` | No phase from yells; Onyxia's phases are typed |
| `ENCOUNTER_START` / `END`, `BOSS_KILL` | Plain | Fights start and stop here |
| Timeline events | id and duration never secret; name and icon may be | Bars, the names drawn as they come |
| `ENCOUNTER_WARNING` | Text and target secret; show and sound flags plain | Shown as they come |
| `UnitInRange` | Secret; `UnitDistanceSquared` unmarked | Range only where the game answers |

Secret values are never compared, joined or used in sums. They are handed
straight to `SetText` and `SetTexture`, as in Pathwise Heal.

## Where the timings come from

`Pathwise_Encounters/Data/Raids.lua` names a source for every encounter:

- Encounter ids and boss names come from Forever's `DungeonEncounter` table.
- Spell ids and timer windows come from the cmangos mangos-classic boss
  scripts (GPL-2.0-or-later, commit `cc34343b`).
- Spell names come from Forever's `SpellName` table, and the game's own name
  is used at run time.

The cmangos numbers are an emulator's re-creation, and the timers count from
the pull and from when the last cast was due, so they drift. Every bar of
Pathwise's own says "about".

Deadly Boss Mods (All Rights Reserved) was the model for the feature list.
None of its code, timings, sounds or art is used, and none of BigWigs' (no
licence).

## Gaps, marked

- No timers yet for Blackwing Lair, Zul'Gurub, Ahn'Qiraj (both), Naxxramas,
  the world bosses, Scarlet Enclave or any dungeon. Those fights get only the
  header.
- Golemagg has no timer: the script has nothing worth a bar, and his
  Earthquake comes at 10% health, which an addon can't see.
- Onyxia phase 2's whelp timer (every 90 s) is the script's.
  Bellowing Roar (18431) is not in Forever's SpellName table.
- When `ENCOUNTER_START` fires against Ragnaros' intro is unchecked.
- Whether Forever's servers send timeline events or encounter warnings for
  Classic raids is unchecked.
- Whether `DoCountdown(0)` cancels a countdown on Forever is unchecked.
- Whether `UnitDistanceSquared` answers in instances is unchecked.

## Files

`Identity.lua`; `Kit/` and `Media/` (copied from Pathwise UI by
`npm run kit`, do not edit); `Data/Raids.lua`; `Encounters/Engine.lua`
(fights, phases, timers, history); `Bars.lua`; `Warnings.lua`;
`Timeline.lua` (the game's timeline and warnings); `Group.lua` (pull, break,
range); `Pages.lua` (options). Tests: `npm run test:encounters`
(`tests/encounters/`).
