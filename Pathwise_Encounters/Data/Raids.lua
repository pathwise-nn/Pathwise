-- The encounters Pathwise Encounters knows, and the timers it runs for them.
--
-- Where each fact comes from:
--   * Encounter ids and boss names: Forever's own client table DungeonEncounter
--     (wago.tools, product wowf, build 1.60.1.70532). These are the ids
--     ENCOUNTER_START sends.
--   * Spell ids and timer windows: the cmangos mangos-classic boss scripts
--     (GPL-2.0-or-later; commit cc34343b, src/game/AI/ScriptDevAI/scripts/),
--     as named on each encounter. They are an emulator's re-creation of the
--     fights, not Blizzard's values, and Forever may have changed them.
--     Every timer below is an ESTIMATE until someone times it on Forever.
--   * Spell names: Forever's SpellName table (same build); the game's own
--     name is used at run time when it has one.
--
-- Nothing here comes from Deadly Boss Mods or BigWigs (neither licence
-- allows it). Never add a timer, spell id or boss without a source.
--
-- An encounter: { name, raid, source, phases = { phase, ... }, note }
-- A phase:      { name, timers = { timer, ... }, after = seconds, next = index }
--               `after`: the phase ends by itself that long after it began
--               (else only /pwenc phase N moves on, as the raid sees it).
-- A timer:      { key, spell = id | nil, name, first = { lo, hi }, every = { lo, hi } | nil }
--               first: seconds from the phase's start to the first cast;
--               every: seconds between casts (none: once). A window lo..hi
--               is shown at its middle, marked as approximate.

local ADDON, ns = ...
local D = {}
ns.EncounterData = D

D.SOURCE_CMANGOS = "cmangos mangos-classic boss script (GPL-2.0-or-later), commit cc34343b"
D.SOURCE_FOREVER = "Forever's DungeonEncounter table, build 1.60.1.70532"

-- The raids, in the order Forever's table lists their bosses.
D.RAIDS = {
	{ key = "mc", name = "Molten Core", ids = { 663, 664, 665, 666, 667, 668, 669, 670, 671, 672 } },
	{ key = "ony", name = "Onyxia's Lair", ids = { 1084 } },
	-- GAP: these raids are detected (name and fight time) but have no timers yet.
	{ key = "bwl", name = "Blackwing Lair", ids = { 610, 611, 612, 613, 614, 615, 616, 617 } },
	{ key = "zg", name = "Zul'Gurub", ids = { 785, 784, 786, 787, 788, 789, 790, 791, 792, 793 } },
	{ key = "aq20", name = "Ruins of Ahn'Qiraj", ids = { 718, 719, 720, 721, 722, 723 } },
	{ key = "aq40", name = "Ahn'Qiraj Temple", ids = { 709, 710, 711, 712, 713, 714, 715, 716, 717 } },
	{ key = "naxx", name = "Naxxramas", ids = { 1107, 1110, 1116, 1117, 1112, 1115, 1113, 1109, 1121, 1118, 1111, 1108, 1120, 1119, 1114 } },
}

local function cm(file) return D.SOURCE_CMANGOS .. ", " .. file end

D.ENCOUNTERS = {
	-- Molten Core -------------------------------------------------------
	[663] = { name = "Lucifron", raid = "mc", source = cm("molten_core/boss_lucifron.cpp"), phases = { { timers = {
		{ key = "doom", spell = 19702, name = "Impending Doom", first = { 5, 10 }, every = { 20, 25 } },
		{ key = "curse", spell = 19703, name = "Lucifron's Curse", first = { 10, 15 }, every = { 20, 25 } },
	} } } },
	[664] = { name = "Magmadar", raid = "mc", source = cm("molten_core/boss_magmadar.cpp"), phases = { { timers = {
		{ key = "panic", spell = 19408, name = "Panic", first = { 6, 10 }, every = { 30, 35 } },
		{ key = "frenzy", spell = 19451, name = "Frenzy", first = { 30, 30 }, every = { 15, 20 } },
	} } } },
	[665] = { name = "Gehennas", raid = "mc", source = cm("molten_core/boss_gehennas.cpp"), phases = { { timers = {
		{ key = "curse", spell = 19716, name = "Gehennas' Curse", first = { 5, 10 }, every = { 25, 30 } },
	} } } },
	[666] = { name = "Garr", raid = "mc", source = cm("molten_core/boss_garr.cpp"), phases = { { timers = {
		{ key = "pulse", spell = 19492, name = "Antimagic Pulse", first = { 10, 15 }, every = { 15, 20 } },
		{ key = "shackles", spell = 19496, name = "Magma Shackles", first = { 5, 10 }, every = { 10, 15 } },
		{ key = "eruption", spell = 20483, name = "Massive Eruption", first = { 360, 360 }, every = { 20, 20 } },
	} } } },
	[667] = { name = "Shazzrah", raid = "mc", source = cm("molten_core/boss_shazzrah.cpp"), phases = { { timers = {
		{ key = "curse", spell = 19713, name = "Shazzrah's Curse", first = { 10, 10 }, every = { 20, 20 } },
		{ key = "counter", spell = 19715, name = "Counterspell", first = { 15, 15 }, every = { 16, 20 } },
		{ key = "deaden", spell = 19714, name = "Deaden Magic", first = { 24, 24 }, every = { 35, 35 } },
		{ key = "gate", spell = 23138, name = "Gate of Shazzrah", first = { 30, 30 }, every = { 45, 45 } },
	} } } },
	[668] = { name = "Baron Geddon", raid = "mc", source = cm("molten_core/boss_baron_geddon.cpp"), phases = { { timers = {
		{ key = "ignite", spell = 19659, name = "Ignite Mana", first = { 30, 30 }, every = { 30, 30 } },
		{ key = "bomb", spell = 20475, name = "Living Bomb", first = { 35, 35 }, every = { 35, 35 } },
		{ key = "inferno", spell = 19695, name = "Inferno", first = { 45, 45 }, every = { 45, 45 } },
	} } } },
	[669] = { name = "Sulfuron Harbinger", raid = "mc", source = cm("molten_core/boss_sulfuron_harbinger.cpp"), phases = { { timers = {
		{ key = "hand", spell = 19780, name = "Hand of Ragnaros", first = { 6, 6 }, every = { 12, 15 } },
		{ key = "shout", spell = 19778, name = "Demoralizing Shout", first = { 15, 15 }, every = { 15, 20 } },
	} } } },
	-- Golemagg: the script has no timed ability worth a bar (Pyroblast every
	-- 7 s; Earthquake at 10% health, which an addon can't see on Forever).
	[670] = { name = "Golemagg the Incinerator", raid = "mc", source = cm("molten_core/boss_golemagg.cpp"), phases = { { timers = {} } } },
	[671] = { name = "Majordomo Executus", raid = "mc", source = cm("molten_core/boss_majordomo_executus.cpp"), phases = { { timers = {
		{ key = "shield", spell = 20619, name = "Reflection shield", first = { 15, 15 }, every = { 30, 30 } },
		{ key = "teleport", spell = 20534, name = "Teleport (tank)", first = { 15, 15 }, every = { 25, 30 } },
		{ key = "teleport2", spell = 20618, name = "Teleport (random)", first = { 30, 30 }, every = { 25, 30 } },
	} } } },
	-- Ragnaros: up for 3 minutes, then under the lava for about 93 s while his
	-- Sons of Flame fight, then up again (the script's phase changes). When
	-- ENCOUNTER_START fires against his 10 s intro is not known: unchecked.
	[672] = { name = "Ragnaros", raid = "mc", source = cm("molten_core/boss_ragnaros.cpp"), phases = {
		{ name = "Ragnaros", after = 180, next = 2, timers = {
			{ key = "wrath", spell = 20566, name = "Wrath of Ragnaros", first = { 30, 30 }, every = { 25, 25 } },
			{ key = "submerge", spell = 21107, name = "Submerge", first = { 180, 180 } },
		} },
		{ name = "Sons of Flame", after = 93.5, next = 3, timers = {
			{ key = "emerge", spell = 20568, name = "Ragnaros emerges", first = { 93.5, 93.5 } },
		} },
		{ name = "Ragnaros", after = 180, next = 2, timers = {
			{ key = "wrath", spell = 20566, name = "Wrath of Ragnaros", first = { 20, 20 }, every = { 25, 25 } },
			{ key = "submerge", spell = 21107, name = "Submerge", first = { 180, 180 } },
		} },
	} },

	-- Onyxia ------------------------------------------------------------
	-- Her phases change at 65% and 40% health. Forever keeps a boss's health
	-- and yells secret from addons in a fight, so the raid moves the timers
	-- on with /pwenc phase 2 and /pwenc phase 3.
	[1084] = { name = "Onyxia", raid = "ony", source = cm("onyxias_lair/boss_onyxia.cpp"), phases = {
		{ name = "Phase 1", timers = {
			{ key = "breath", spell = 18435, name = "Flame Breath", first = { 10, 20 }, every = { 10, 20 } },
			{ key = "buffet", spell = 18500, name = "Wing Buffet", first = { 10, 20 }, every = { 15, 30 } },
			{ key = "knock", spell = 19633, name = "Knock Away", first = { 20, 30 }, every = { 25, 40 } },
		} },
		{ name = "Phase 2 (in the air)", timers = {
			-- The script summons a wave as she lifts off, then about every 90 s.
			{ key = "whelps", name = "Whelps", first = { 90, 90 }, every = { 90, 90 } },
		} },
		{ name = "Phase 3", timers = {
			-- Bellowing Roar: spell 18431 in the script; not in Forever's SpellName table.
			{ key = "roar", spell = 18431, name = "Bellowing Roar", first = { 0, 0 }, every = { 15, 45 } },
			{ key = "breath", spell = 18435, name = "Flame Breath", first = { 10, 20 }, every = { 10, 20 } },
			{ key = "knock", spell = 19633, name = "Knock Away", first = { 10, 20 }, every = { 25, 40 } },
		} },
	} },
}

-- Raid bosses with no timers yet: detected by name and fight time only.
D.BOSSES = {
	[610] = "Razorgore the Untamed", [611] = "Vaelastrasz the Corrupt", [612] = "Broodlord Lashlayer", [613] = "Firemaw",
	[614] = "Ebonroc", [615] = "Flamegor", [616] = "Chromaggus", [617] = "Nefarian",
	[784] = "High Priest Venoxis", [785] = "High Priestess Jeklik", [786] = "High Priestess Mar'li", [787] = "Bloodlord Mandokir",
	[788] = "Edge of Madness", [789] = "High Priest Thekal", [790] = "Gahz'ranka", [791] = "High Priestess Arlokk",
	[792] = "Jin'do the Hexxer", [793] = "Hakkar",
	[718] = "Kurinnaxx", [719] = "General Rajaxx", [720] = "Moam", [721] = "Buru the Gorger", [722] = "Ayamiss the Hunter",
	[723] = "Ossirian the Unscarred",
	[709] = "The Prophet Skeram", [710] = "Silithid Royalty", [711] = "Battleguard Sartura", [712] = "Fankriss the Unyielding",
	[713] = "Viscidus", [714] = "Princess Huhuran", [715] = "Twin Emperors", [716] = "Ouro", [717] = "C'thun",
	[1107] = "Anub'Rekhan", [1110] = "Grand Widow Faerlina", [1116] = "Maexxna", [1117] = "Noth the Plaguebringer",
	[1112] = "Heigan the Unclean", [1115] = "Loatheb", [1113] = "Instructor Razuvious", [1109] = "Gothik the Harvester",
	[1121] = "The Four Horsemen", [1118] = "Patchwerk", [1111] = "Grobbulus", [1108] = "Gluth", [1120] = "Thaddius",
	[1119] = "Sapphiron", [1114] = "Kel'Thuzad",
}

-- The raid an encounter id belongs to, or nil (a dungeon or world boss).
function D.RaidOf(id)
	for _, r in ipairs(D.RAIDS) do
		for _, x in ipairs(r.ids) do if x == id then return r end end
	end
end
