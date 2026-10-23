-- Pathwise Gear's default stat weights, per class and spec, for World of
-- Warcraft: Forever.
--
-- How they were set (October 2026, Forever beta, level cap 30):
--   * The stat ORDER of each spec follows the Forever class guides of
--     Icy Veins (icy-veins.com/wow-forever, "Level 30 Gear, Stat Priority")
--     and Mobalytics (mobalytics.gg/wow-forever, each spec's "Stat Priority"),
--     cross-checked with Icy Veins' Classic Era level 60 stat priorities.
--     Wowhead's Forever guides were read too; they list gear, not stat orders.
--   * The NUMBERS are Pathwise's own: they keep each spec's order and follow
--     Forever's stat rules (Warcraft Tavern's Forever stats guide; the same
--     as Classic's) for how far apart stats sit: 2 attack power per Strength
--     for Warriors, Paladins, Shamans and Druids; 2 ranged attack power per
--     Agility for Hunters; 14 attack power = 1 weapon DPS; 10 health per
--     Stamina; 15 mana per Intellect. Plain attack power on Forever gear
--     counts for melee and ranged, and crit is mostly one stat for melee and
--     spells; healers all have talents that keep Spirit working in combat.
--   * Haste was on no beta gear the guides saw, and Expertise is not
--     explained yet: their weights are a best guess from the guides' order.
--   * Where the guides disagree (levelling solo vs dungeon play), the weights
--     favour levelling, which is what the Forever beta offers so far.
-- Nothing of those guides' text is reproduced; only the order of stats, which
-- is a fact about the game. Forever's own changes the guides point out are in:
--   Expertise and Haste exist on Forever gear; Survival Hunters fight in
--   melee; Marksmanship's Careful Aim adds damage from Intellect; Paladins'
--   Champion of the Light and Enhancement's Mental Dexterity make Intellect
--   worth more; Warlocks' Life Tap scales with Spirit; Feral Druids value
--   Strength over Agility while levelling.
-- Level 60 weights will follow when Forever's level 60 guides exist.
--
-- Units: base stats per point; crit, hit, spellCrit, spellHit, expertise,
-- haste, dodge, parry, block per 1%; dps and rdps per 1 weapon DPS (dps =
-- melee weapons, rdps = bows, guns, crossbows, thrown and wands); sp = spell
-- damage of every school, spFire etc. one school (set to the spec's own
-- schools), heal = healing power.

local _, ns = ...
local W = {}
ns.Weights = W

W.SOURCES = {
	{ name = "Icy Veins: WoW Forever class guides", url = "https://www.icy-veins.com/wow-forever/all-class-guides" },
	{ name = "Mobalytics: WoW Forever class guides", url = "https://mobalytics.gg/wow-forever/classes" },
	{ name = "Wowhead: WoW Forever class guides", url = "https://www.wowhead.com/forever/guides/classes" },
	{ name = "Warcraft Tavern: WoW Forever stats guide", url = "https://www.warcrafttavern.com/forever/guides/stats/" },
	{ name = "Icy Veins: WoW Classic (Era) stat priorities", url = "https://www.icy-veins.com/wow-classic/" },
}

-- Each spec: key, label, schools (its spell damage schools), and its
-- weights. `note` says what the guides agree on, shown in the Gear panel.
local SPEC = {
	WARRIOR = {
		{ key = "arms", label = "Arms", note = "Weapon damage, then Hit, Crit, Strength, Agility",
			w = { dps = 8.5, hit = 16, expertise = 12, crit = 14, str = 1, ap = 0.5, agi = 0.7, sta = 0.45, armor = 0.01, dodge = 2, parry = 2 } },
		{ key = "fury", label = "Fury", note = "Weapon damage, then Hit, Crit, Strength, Agility",
			w = { dps = 8, hit = 18, expertise = 13, crit = 15, str = 1, ap = 0.5, agi = 0.75, sta = 0.4, armor = 0.01, dodge = 2, parry = 2 } },
		{ key = "protection", label = "Protection", note = "Weapon damage and Hit for threat, Strength, then Armour and Stamina",
			w = { dps = 5, hit = 10, expertise = 8, crit = 6, str = 1, ap = 0.5, agi = 0.8, armor = 0.06, sta = 0.75, defense = 1, dodge = 10, parry = 9, block = 4, blockValue = 0.3 } },
	},
	PALADIN = {
		{ key = "holy", label = "Holy", schools = { "spHoly" }, note = "Healing, Intellect, MP5, Crit, Haste, Spirit",
			w = { heal = 1, int = 0.9, mp5 = 1.8, spellCrit = 7, haste = 5, spi = 0.6, sta = 0.3, sp = 0.15 } },
		{ key = "protection", label = "Protection", schools = { "spHoly" }, note = "Strength, Stamina, Spell power, Intellect, Block, Hit",
			w = { str = 1, ap = 0.5, sta = 0.9, sp = 0.8, int = 0.6, block = 6, blockValue = 0.4, hit = 8, spellHit = 4, defense = 0.8, armor = 0.04, agi = 0.5, spi = 0.2, dps = 3 } },
		{ key = "retribution", label = "Retribution", schools = { "spHoly" }, note = "Weapon damage, Hit, Crit, Strength; Intellect over Agility with Champion of the Light",
			w = { dps = 8, hit = 14, expertise = 10, crit = 12, str = 1, ap = 0.5, sp = 0.6, int = 0.6, agi = 0.55, sta = 0.4, spi = 0.25, mp5 = 1 } },
	},
	HUNTER = {
		{ key = "beastmastery", label = "Beast Mastery", note = "Ranged weapon damage, Hit, Agility, Crit, Intellect",
			w = { rdps = 9, hit = 14, agi = 1, crit = 12, rap = 0.45, ap = 0.45, str = 0.3, int = 0.45, spi = 0.2, sta = 0.3, mp5 = 1 } },
		{ key = "marksmanship", label = "Marksmanship", note = "Ranged weapon damage, Hit, Agility, Crit; Intellect adds damage (Careful Aim)",
			w = { rdps = 9, hit = 14, agi = 1, crit = 13, rap = 0.45, ap = 0.45, int = 0.7, spi = 0.2, sta = 0.3, mp5 = 1 } },
		{ key = "survival", label = "Survival (melee)", note = "Melee weapon damage, Hit, Agility, Crit, Strength",
			w = { dps = 8.5, rdps = 2, hit = 14, expertise = 10, agi = 1, crit = 12, str = 0.6, ap = 0.45, int = 0.3, spi = 0.15, sta = 0.3 } },
	},
	ROGUE = {
		{ key = "assassination", label = "Assassination", note = "Weapon damage, Hit and Expertise, Agility, Crit, Strength",
			w = { dps = 9, hit = 18, expertise = 14, agi = 1, ap = 0.5, crit = 14, str = 0.55, sta = 0.35, dodge = 2 } },
		{ key = "combat", label = "Combat", note = "Weapon damage, Hit and Expertise, Agility, Crit, Strength",
			w = { dps = 9.5, hit = 19, expertise = 15, agi = 1, ap = 0.5, crit = 12, str = 0.55, sta = 0.35, dodge = 2 } },
		{ key = "subtlety", label = "Subtlety", note = "Weapon damage, Hit and Expertise, Agility, attack power, Crit",
			w = { dps = 9, hit = 17, expertise = 13, agi = 1, ap = 0.55, crit = 11, str = 0.55, sta = 0.4, dodge = 2 } },
	},
	PRIEST = {
		{ key = "discipline", label = "Discipline", schools = { "spHoly" }, note = "Healing, MP5, Spirit, Intellect, Crit",
			w = { heal = 1, mp5 = 1.8, spi = 0.9, int = 0.8, spellCrit = 5, sp = 0.3, sta = 0.3, rdps = 2 } },
		{ key = "holy", label = "Holy", schools = { "spHoly" }, note = "Healing, MP5, Spirit, Intellect, Crit",
			w = { heal = 1, mp5 = 1.8, spi = 0.85, int = 0.8, spellCrit = 4, sp = 0.2, sta = 0.3, rdps = 1.5 } },
		{ key = "shadow", label = "Shadow", schools = { "spShadow" }, note = "Spell power, Crit, Hit, Intellect, Spirit",
			w = { sp = 1, spellCrit = 9, spellHit = 9, int = 0.6, spi = 0.55, sta = 0.4, mp5 = 1.2, rdps = 2.5 } },
	},
	SHAMAN = {
		{ key = "elemental", label = "Elemental", schools = { "spNature", "spFire", "spFrost" }, note = "Spell power, Crit, Hit, Intellect, MP5",
			w = { sp = 1, spellCrit = 11, spellHit = 10, int = 0.65, mp5 = 1.4, spi = 0.35, sta = 0.45 } },
		{ key = "enhancement", label = "Enhancement", schools = { "spNature" }, note = "Weapon damage, Hit, Crit, Strength, Intellect (Mental Dexterity), Agility",
			w = { dps = 8, hit = 14, expertise = 10, crit = 12, str = 1, ap = 0.5, int = 0.7, agi = 0.6, spi = 0.2, sp = 0.2, sta = 0.35, mp5 = 1 } },
		{ key = "restoration", label = "Restoration", note = "Healing, Crit, Intellect, Spirit, MP5",
			w = { heal = 1, spellCrit = 9, int = 0.85, spi = 0.6, mp5 = 1.8, sta = 0.45 } },
	},
	MAGE = {
		{ key = "arcane", label = "Arcane", schools = { "spArcane" }, note = "Hit, then Spirit, Intellect, Spell power, Crit",
			w = { sp = 1, spellHit = 14, spi = 0.75, int = 0.7, spellCrit = 8, sta = 0.35, rdps = 2 } },
		{ key = "fire", label = "Fire", schools = { "spFire" }, note = "Hit, Spell power, Crit, Spirit, Intellect",
			w = { sp = 1, spellHit = 14, spellCrit = 11, spi = 0.6, int = 0.55, sta = 0.35, mp5 = 1, rdps = 2 } },
		{ key = "frost", label = "Frost", schools = { "spFrost" }, note = "Hit, Spell power (Frost), Crit, Spirit, Intellect",
			w = { sp = 1, spellHit = 14, spellCrit = 9, spi = 0.6, int = 0.55, sta = 0.4, rdps = 2 } },
	},
	WARLOCK = {
		{ key = "affliction", label = "Affliction", schools = { "spShadow" }, note = "Spell power, Hit, Crit, Intellect, Spirit (Life Tap), Haste",
			w = { sp = 1, spellHit = 12, spellCrit = 6, int = 0.5, spi = 0.55, haste = 5, sta = 0.45, rdps = 2 } },
		{ key = "demonology", label = "Demonology", schools = { "spShadow", "spFire" }, note = "Spell power, Hit, Intellect, Crit, Spirit (Life Tap), Haste",
			w = { sp = 0.95, spellHit = 11, int = 0.55, spellCrit = 5, spi = 0.5, haste = 4, sta = 0.6, rdps = 2 } },
		{ key = "destruction", label = "Destruction", schools = { "spFire", "spShadow" }, note = "Spell power, Hit, Haste, Crit, Spirit (Life Tap)",
			w = { sp = 1, spellHit = 12, haste = 9, spellCrit = 9, spi = 0.5, int = 0.45, sta = 0.4, rdps = 2 } },
	},
	DRUID = {
		{ key = "balance", label = "Balance", schools = { "spNature", "spArcane" }, note = "Intellect, Spell power, Spirit, MP5, Crit",
			w = { int = 1, sp = 0.95, spi = 0.7, mp5 = 1.4, spellCrit = 7, haste = 5, spellHit = 8, sta = 0.35 } },
		{ key = "feral", label = "Feral", note = "Hit, Crit, Strength, Agility, Stamina",
			w = { dps = 5, hit = 14, expertise = 10, crit = 12, str = 1, ap = 0.5, agi = 0.8, sta = 0.6, armor = 0.02, int = 0.25, spi = 0.2, dodge = 6, defense = 0.4 } },
		{ key = "restoration", label = "Restoration", note = "Intellect, Healing, Spirit, MP5, Crit",
			w = { heal = 1, int = 0.95, spi = 0.7, mp5 = 1.6, spellCrit = 5, haste = 4, sta = 0.3 } },
	},
}

-- The usual levelling spec, used before talents say otherwise.
W.DEFAULT = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "beastmastery", ROGUE = "combat", PRIEST = "shadow",
	SHAMAN = "enhancement", MAGE = "frost", WARLOCK = "affliction", DRUID = "feral" }

function W.Specs(class) return SPEC[class] or {} end

function W.Spec(class, key)
	for _, s in ipairs(SPEC[class] or {}) do if s.key == key then return s end end
end

-- The weights of one spec, scaled so its best stat point is 1.0, with a
-- spec's schools valued like spell damage, and health and mana valued from
-- Stamina and Intellect (10 health, 15 mana a point).
function W.For(class, key)
	local s = W.Spec(class, key or W.DEFAULT[class])
	if not s then return nil end
	local w = {}
	for k, v in pairs(s.w) do w[k] = v end
	if w.sp then for _, school in ipairs(s.schools or {}) do w[school] = w.sp end end
	-- Forever gear mostly gives one "Critical Strike Chance" for melee,
	-- ranged and spells alike (Warcraft Tavern's stats guide), so a caster
	-- values plain crit like spell crit.
	if w.spellCrit and not w.crit then w.crit = w.spellCrit end
	local top = 0
	for _, k in ipairs({ "str", "agi", "int", "sta", "spi", "sp", "heal", "ap", "rap" }) do
		if (w[k] or 0) > top then top = w[k] end
	end
	if top > 0 and top ~= 1 then for k, v in pairs(w) do w[k] = math.floor(v / top * 1000 + 0.5) / 1000 end end
	if w.sta then w.health = w.health or w.sta / 10 end
	if w.int then w.mana = w.mana or w.int / 15 end
	return w
end

-- What each class can wear and wield (Classic trainers; game facts).
-- Armour subclass: 1 cloth, 2 leather, 3 mail, 4 plate; mail and plate from
-- level 40 for the classes that learn them. Weapon subclasses: 0/1 axe,
-- 2 bow, 3 gun, 4/5 mace, 6 polearm, 7/8 sword, 10 staff, 13 fist, 15 dagger,
-- 16 thrown, 18 crossbow, 19 wand.
local function set(...)
	local t = {}
	for i = 1, select("#", ...) do t[select(i, ...)] = true end
	return t
end
W.WEAR = {
	WARRIOR = { armor = 3, at40 = 4, shield = true, weapons = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
	PALADIN = { armor = 3, at40 = 4, shield = true, weapons = set(0, 1, 4, 5, 6, 7, 8) },
	HUNTER = { armor = 2, at40 = 3, weapons = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
	ROGUE = { armor = 2, weapons = set(2, 3, 4, 7, 13, 15, 16, 18) },
	PRIEST = { armor = 1, weapons = set(4, 10, 15, 19) },
	SHAMAN = { armor = 2, at40 = 3, shield = true, weapons = set(0, 1, 4, 5, 10, 13, 15) },
	MAGE = { armor = 1, weapons = set(7, 10, 15, 19) },
	WARLOCK = { armor = 1, weapons = set(7, 10, 15, 19) },
	DRUID = { armor = 2, weapons = set(4, 5, 10, 13, 15) },
}
