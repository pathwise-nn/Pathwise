-- Pathwise Gear's default stat weights, worked out here from Classic's stat
-- rules rather than copied from any other addon. They are a starting point
-- for levelling: import a Pawn scale string (Settings > Pathwise Gear) to use
-- weights you trust, or install Pawn and let Pathwise Gear use its scores.
-- NOT verified on Forever, which may have retuned stats.
--
-- The rules used (Classic Era, level 60 values where they change by level):
--   * Melee attack power: 2 per Strength for Warriors, Paladins, Shamans and
--     Druids; 1 per Strength and 1 per Agility for Rogues and Hunters (and
--     Druids in Cat Form for Agility); Hunters also 2 ranged AP per Agility.
--   * 14 attack power adds 1 damage per second.
--   * Agility: 2 armour each, and 1% critical strike per about 20 Agility
--     (Warrior, Paladin, Shaman, Druid), 29 (Rogue) or 53 (Hunter).
--   * Intellect: 15 mana each, and 1% spell critical strike per about 60.
--   * Stamina: 10 health each.
-- From those, each spec gives a value to the stats that matter to it (a
-- point of attack power, of spell damage, of 1% crit, ...) and the rest
-- follows by conversion. Everything is then scaled so the spec's best stat
-- is 1.0, the way Pawn shows weights.

local _, ns = ...
local W = {}
ns.Weights = W

-- Class facts: attack power per Strength / Agility, ranged AP per Agility,
-- Agility and Intellect per 1% crit (melee / spell).
local CLASS = {
	WARRIOR = { apStr = 2, apAgi = 0, rapAgi = 1, agiCrit = 20, intCrit = nil },
	PALADIN = { apStr = 2, apAgi = 0, rapAgi = 0, agiCrit = 20, intCrit = 54 },
	HUNTER = { apStr = 1, apAgi = 1, rapAgi = 2, agiCrit = 53, intCrit = 60 },
	ROGUE = { apStr = 1, apAgi = 1, rapAgi = 1, agiCrit = 29, intCrit = nil },
	PRIEST = { apStr = 1, apAgi = 0, rapAgi = 0, agiCrit = 20, intCrit = 59 },
	SHAMAN = { apStr = 2, apAgi = 0, rapAgi = 0, agiCrit = 20, intCrit = 59 },
	MAGE = { apStr = 1, apAgi = 0, rapAgi = 0, agiCrit = 20, intCrit = 60 },
	WARLOCK = { apStr = 1, apAgi = 0, rapAgi = 0, agiCrit = 20, intCrit = 61 },
	DRUID = { apStr = 2, apAgi = 1, rapAgi = 0, agiCrit = 20, intCrit = 60 },
}

-- What each spec values directly. Physical specs: ap (1 attack power), crit
-- and hit (1%), armor, sta, spi, mp5. Casters: sp (1 spell damage in their
-- schools; `schools` lists them), heal, mana (1 point), spellCrit and
-- spellHit (1%), spi, sta, mp5. Tanks add defense, dodge, parry, block.
-- Weapon DPS is never set by hand: it is 14 attack power (melee specs) or
-- what a caster's wand is worth (rdps).
local SPEC = {
	WARRIOR = {
		{ key = "arms", label = "Arms", ap = 1, crit = 22, hit = 20, sta = 1, armor = 0.04, spi = 0.2 },
		{ key = "fury", label = "Fury", ap = 1, crit = 24, hit = 24, sta = 1, armor = 0.04, spi = 0.2 },
		{ key = "protection", label = "Protection", tank = true, ap = 0.5, crit = 8, hit = 12, sta = 2.4, armor = 0.12, defense = 2.4, dodge = 26, parry = 24, block = 16, blockValue = 1 },
	},
	PALADIN = {
		{ key = "holy", label = "Holy", heal = 1, mana = 0.09, spellCrit = 12, mp5 = 3.6, sta = 0.8, spi = 0.8 },
		{ key = "protection", label = "Protection", tank = true, ap = 0.4, sp = 0.9, schools = { "spHoly" }, mana = 0.04, sta = 2, armor = 0.1, defense = 2, dodge = 20, parry = 20, block = 12, blockValue = 0.8, hit = 8 },
		{ key = "retribution", label = "Retribution", ap = 1, crit = 20, hit = 18, sp = 0.5, schools = { "spHoly" }, mana = 0.03, sta = 1, armor = 0.04, spi = 0.3, mp5 = 1.6 },
	},
	HUNTER = {
		{ key = "beastmastery", label = "Beast Mastery", rap = 1, ap = 0.15, crit = 18, hit = 20, mana = 0.03, sta = 1, armor = 0.03, spi = 0.4, mp5 = 2 },
		{ key = "marksmanship", label = "Marksmanship", rap = 1, ap = 0.15, crit = 22, hit = 22, mana = 0.03, sta = 0.9, armor = 0.03, spi = 0.4, mp5 = 2 },
		{ key = "survival", label = "Survival", rap = 1, ap = 0.3, crit = 22, hit = 20, mana = 0.03, sta = 1, armor = 0.03, spi = 0.4, mp5 = 1.6 },
	},
	ROGUE = {
		{ key = "assassination", label = "Assassination", ap = 1, crit = 24, hit = 24, sta = 0.9, armor = 0.04, dodge = 4 },
		{ key = "combat", label = "Combat", ap = 1, crit = 22, hit = 26, sta = 0.9, armor = 0.04, dodge = 4 },
		{ key = "subtlety", label = "Subtlety", ap = 1, crit = 22, hit = 22, sta = 1, armor = 0.04, dodge = 4 },
	},
	PRIEST = {
		{ key = "discipline", label = "Discipline", heal = 0.7, sp = 0.6, schools = { "spHoly" }, mana = 0.1, spellCrit = 10, spellHit = 6, mp5 = 3.2, spi = 1.3, sta = 0.8, rdps = 4 },
		{ key = "holy", label = "Holy", heal = 1, sp = 0.3, schools = { "spHoly" }, mana = 0.1, spellCrit = 10, mp5 = 3.6, spi = 1.4, sta = 0.7, rdps = 3 },
		{ key = "shadow", label = "Shadow", sp = 1, schools = { "spShadow" }, mana = 0.07, spellCrit = 5, spellHit = 14, mp5 = 2.8, spi = 1.4, sta = 1, rdps = 4.5 },
	},
	SHAMAN = {
		{ key = "elemental", label = "Elemental", sp = 1, schools = { "spNature", "spFire", "spFrost" }, mana = 0.08, spellCrit = 13, spellHit = 13, mp5 = 3, spi = 0.5, sta = 0.8 },
		{ key = "enhancement", label = "Enhancement", ap = 1, crit = 20, hit = 20, sp = 0.3, schools = { "spNature" }, mana = 0.03, sta = 1, armor = 0.04, spi = 0.3, mp5 = 2 },
		{ key = "restoration", label = "Restoration", heal = 1, mana = 0.1, spellCrit = 10, mp5 = 4, spi = 0.6, sta = 0.7 },
	},
	MAGE = {
		{ key = "arcane", label = "Arcane", sp = 1, schools = { "spArcane", "spFire", "spFrost" }, mana = 0.09, spellCrit = 11, spellHit = 14, mp5 = 2.6, spi = 0.9, sta = 0.9, rdps = 2.5 },
		{ key = "fire", label = "Fire", sp = 1, schools = { "spFire" }, mana = 0.08, spellCrit = 14, spellHit = 14, mp5 = 2.4, spi = 0.8, sta = 0.9, rdps = 2.5 },
		{ key = "frost", label = "Frost", sp = 1, schools = { "spFrost" }, mana = 0.08, spellCrit = 9, spellHit = 14, mp5 = 2.6, spi = 0.9, sta = 1, rdps = 2.5 },
	},
	WARLOCK = {
		{ key = "affliction", label = "Affliction", sp = 1, schools = { "spShadow" }, mana = 0.07, spellCrit = 4, spellHit = 14, mp5 = 1.6, spi = 1, sta = 1.3, rdps = 3 },
		{ key = "demonology", label = "Demonology", sp = 0.9, schools = { "spShadow", "spFire" }, mana = 0.07, spellCrit = 4, spellHit = 12, mp5 = 1.6, spi = 0.9, sta = 1.6, rdps = 3 },
		{ key = "destruction", label = "Destruction", sp = 1, schools = { "spShadow", "spFire" }, mana = 0.07, spellCrit = 12, spellHit = 14, mp5 = 1.6, spi = 0.6, sta = 1.1, rdps = 3 },
	},
	DRUID = {
		{ key = "balance", label = "Balance", sp = 1, schools = { "spNature", "spArcane" }, mana = 0.08, spellCrit = 10, spellHit = 13, mp5 = 3, spi = 0.8, sta = 0.8, heal = 0.15 },
		{ key = "feral", label = "Feral", feral = true, ap = 1, crit = 20, hit = 20, sta = 1.2, armor = 0.08, defense = 0.8, dodge = 12 },
		{ key = "restoration", label = "Restoration", heal = 1, mana = 0.1, spellCrit = 7, mp5 = 3.6, spi = 1.1, sta = 0.7 },
	},
}

-- The usual levelling spec, used before talents say otherwise.
W.DEFAULT = { WARRIOR = "arms", PALADIN = "retribution", HUNTER = "beastmastery", ROGUE = "combat", PRIEST = "shadow",
	SHAMAN = "enhancement", MAGE = "frost", WARLOCK = "affliction", DRUID = "feral" }

function W.Specs(class) return SPEC[class] or {} end

function W.Spec(class, key)
	for _, s in ipairs(SPEC[class] or {}) do if s.key == key then return s end end
end

-- The weights of one spec: the values it sets, plus the stats that convert
-- into them, scaled so the best stat is 1.0.
function W.For(class, key)
	local c, s = CLASS[class], W.Spec(class, key or W.DEFAULT[class])
	if not (c and s) then return nil end
	local w = {}
	for _, k in ipairs({ "ap", "rap", "sp", "heal", "mana", "crit", "hit", "spellCrit", "spellHit", "sta", "spi", "armor",
		"mp5", "defense", "dodge", "parry", "block", "blockValue", "rdps" }) do
		if s[k] then w[k] = s[k] end
	end
	for _, school in ipairs(s.schools or {}) do w[school] = s.sp end
	local ap, rap = s.ap or 0, s.rap or 0
	-- Strength and Agility: through attack power, crit and armour.
	w.str = c.apStr * ap
	w.agi = c.apAgi * ap + c.rapAgi * rap + (s.crit or 0) / c.agiCrit + 2 * (s.armor or 0)
	if s.feral then w.agi = 1 * ap + (s.crit or 0) / c.agiCrit + 2 * (s.armor or 0) end
	-- Intellect: mana, and spell crit for casters.
	w.int = 15 * (s.mana or 0) + ((c.intCrit and s.spellCrit) and s.spellCrit / c.intCrit or 0)
	-- Weapon damage: 14 attack power is 1 DPS (feral forms ignore the weapon).
	if ap > 0 and not s.feral then w.dps = 14 * ap end
	if rap > 0 then w.rdps = 14 * rap end
	w.health = (s.sta or 0) / 10
	if s.sta then w.sta = s.sta end
	-- Scale: the best stat point is 1.0 (not the percent stats or weapon DPS).
	local top = 0
	for _, k in ipairs({ "str", "agi", "int", "sta", "spi", "sp", "heal", "ap", "rap" }) do
		if (w[k] or 0) > top then top = w[k] end
	end
	if top > 0 then for k, v in pairs(w) do w[k] = math.floor(v / top * 1000 + 0.5) / 1000 end end
	for k, v in pairs(w) do if v == 0 then w[k] = nil end end
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
