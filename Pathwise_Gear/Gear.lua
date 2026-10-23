-- Pathwise Gear: is this item an upgrade for me?
--
--   Gear.Score(link) -> score | nil         the item's value under the weights in use
--   Gear.Compare(link) -> { score, old, delta, pct, slot, empty, usable, reason, minLevel } | nil
--   Gear.IsUpgrade(link) -> bool, pct, slot  wearable now and at least gear.minUpgrade % better
--   Gear.Spec() -> key, label, how ("auto" | "chosen")
--   Gear.Weights() -> weights, name, source ("pathwise" | "imported")
--   Gear.Source() -> "pawn" | "pathwise"     who scores items now
--   Gear.ImportScale(text) -> scale | nil, err   a Pawn scale string
--
-- Stats: the client's own (C_Item.GetItemStats), so Forever's numbers.
-- With Pawn installed and gear.source "auto" or "pawn", Pawn's own upgrade
-- verdicts are used instead (PawnGetItemData + PawnIsItemAnUpgrade, Pawn's
-- public functions; nothing of Pawn is copied into Pathwise).

local ADDON, ns = ...
local S = Pathwise.Suite
local W = ns.Weights
local Gear = {}
ns.Gear = Gear
Pathwise.Gear = Gear

S.Defaults("gear", {
	source = "auto", -- "auto" (Pawn when installed), "pawn", "pathwise"
	minUpgrade = 0.01, -- the smallest gain that counts as an upgrade (0.01 = 1%)
	tooltip = true, bags = true, rewards = true,
	spec = nil, -- per class: { MAGE = "frost", ... } when chosen
	scales = nil, -- imported scales: { { name, class, weights }, ... }
	scale = nil, -- per class: the imported scale's name in use
})

local readable = S.Compat.Readable

---------------------------------------------------------------------------
-- The client (Forever 1.60; every call through pcall)
---------------------------------------------------------------------------

local Client = {}
Gear.Client = Client

function Client.Class()
	local _, class, id = UnitClass("player")
	return readable(class), readable(id)
end

function Client.Level() return readable(UnitLevel("player")) or 1 end

function Client.Equipped(slot)
	return GetInventoryItemLink and readable(GetInventoryItemLink("player", slot)) or nil
end

function Client.Stats(link)
	local f = C_Item and C_Item.GetItemStats
	if not (f and link) then return nil end
	local ok, t = pcall(f, link)
	return ok and type(t) == "table" and t or nil
end

-- equipLoc, classID, subclassID, minLevel, quality, name
function Client.Info(link)
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if not (f and link) then return nil end
	local ok, name, _, quality, _, minLevel, _, _, _, equipLoc, _, _, classID, subclassID = pcall(f, link)
	if not (ok and name) then return nil end
	return equipLoc, classID, subclassID, minLevel, quality, name
end

function Client.Knows(spell)
	return S.Compat.SpellKnown and S.Compat.SpellKnown(spell) or false
end

-- The talent tree with the most points (C_SpecializationInfo, as Forever's
-- character frame reads it), or nil.
function Client.TalentTree()
	local Sp = C_SpecializationInfo
	if not (Sp and Sp.GetSpecializationInfo) then return nil end
	local best, bestPoints
	for i = 1, 3 do
		local ok, _, _, _, _, _, _, points = pcall(Sp.GetSpecializationInfo, i)
		points = ok and readable(points)
		if type(points) == "number" and points > 0 and (not bestPoints or points > bestPoints) then best, bestPoints = i, points end
	end
	return best
end

---------------------------------------------------------------------------
-- Stats
---------------------------------------------------------------------------

-- The client's stat names (its global strings) -> Pathwise's stat keys.
local STATS = {
	ITEM_MOD_STRENGTH_SHORT = "str", ITEM_MOD_AGILITY_SHORT = "agi", ITEM_MOD_STAMINA_SHORT = "sta",
	ITEM_MOD_INTELLECT_SHORT = "int", ITEM_MOD_SPIRIT_SHORT = "spi", RESISTANCE0_NAME = "armor",
	ITEM_MOD_HEALTH_SHORT = "health", ITEM_MOD_MANA_SHORT = "mana",
	ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "dps",
	ITEM_MOD_ATTACK_POWER_SHORT = "ap", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rap",
	ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "sp", ITEM_MOD_SPELL_POWER_SHORT = "sp",
	ITEM_MOD_SPELL_HEALING_DONE_SHORT = "heal",
	ITEM_MOD_MANA_REGENERATION_SHORT = "mp5", ITEM_MOD_POWER_REGEN0_SHORT = "mp5",
	ITEM_MOD_HEALTH_REGEN_SHORT = "hp5", ITEM_MOD_HEALTH_REGENERATION_SHORT = "hp5",
	ITEM_MOD_CRIT_RATING_SHORT = "crit", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "crit",
	ITEM_MOD_HIT_RATING_SHORT = "hit", ITEM_MOD_HIT_MELEE_RATING_SHORT = "hit",
	ITEM_MOD_CRIT_SPELL_RATING_SHORT = "spellCrit", ITEM_MOD_HIT_SPELL_RATING_SHORT = "spellHit",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "defense", ITEM_MOD_DODGE_RATING_SHORT = "dodge",
	ITEM_MOD_PARRY_RATING_SHORT = "parry", ITEM_MOD_BLOCK_RATING_SHORT = "block",
	ITEM_MOD_BLOCK_VALUE_SHORT = "blockValue",
}
Gear.STATS = STATS

local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }

function Gear.Stats(link)
	local raw = Client.Stats(link)
	if not raw then return nil end
	local out = {}
	for k, v in pairs(raw) do
		local key = STATS[k]
		if key and type(v) == "number" then out[key] = (out[key] or 0) + v end
	end
	-- A ranged weapon's DPS is ranged DPS.
	local equipLoc = Client.Info(link)
	if out.dps and RANGED[equipLoc] then out.rdps, out.dps = out.dps, nil end
	return out
end

---------------------------------------------------------------------------
-- Spec, weights, imported scales
---------------------------------------------------------------------------

function Gear.Spec()
	local class = Client.Class()
	local chosen = S.Get("gear.spec")
	if type(chosen) == "table" and chosen[class] and W.Spec(class, chosen[class]) then
		local s = W.Spec(class, chosen[class])
		return s.key, s.label, "chosen"
	end
	local tree = Client.TalentTree()
	local specs = W.Specs(class)
	local s = (tree and specs[tree]) or W.Spec(class, W.DEFAULT[class])
	if not s then return nil end
	return s.key, s.label, "auto"
end

function Gear.SetSpec(key)
	local class = Client.Class()
	local t = {}
	for k, v in pairs(S.Get("gear.spec") or {}) do t[k] = v end
	t[class] = key
	S.Set("gear.spec", t)
	Gear.Clear()
end

function Gear.Scales()
	local out, class = {}, Client.Class()
	for _, s in ipairs(S.Get("gear.scales") or {}) do
		if not s.class or s.class == class then out[#out + 1] = s end
	end
	return out
end

local function chosenScale()
	local class = Client.Class()
	local names = S.Get("gear.scale")
	local name = type(names) == "table" and names[class]
	if not name then return nil end
	for _, s in ipairs(Gear.Scales()) do if s.name == name then return s end end
end

function Gear.UseScale(name)
	local class = Client.Class()
	local t = {}
	for k, v in pairs(S.Get("gear.scale") or {}) do t[k] = v end
	t[class] = name
	S.Set("gear.scale", t)
	Gear.Clear()
end

function Gear.Weights()
	local imported = chosenScale()
	if imported then return imported.weights, imported.name, "imported" end
	local class = Client.Class()
	local key, label = Gear.Spec()
	return W.For(class, key) or {}, label or "?", "pathwise"
end

-- Pawn's stat names in its scale strings (the format Pawn exports and
-- imports) -> Pathwise's keys. Names not listed are ignored and reported.
local PAWN_STATS = {
	strength = { "str" }, agility = { "agi" }, stamina = { "sta" }, intellect = { "int" }, spirit = { "spi" },
	armor = { "armor" }, ap = { "ap" }, rap = { "rap" }, spelldamage = { "sp" }, spellpower = { "sp" },
	healing = { "heal" }, mp5 = { "mp5" }, hp5 = { "hp5" }, critrating = { "crit" }, hitrating = { "hit" },
	spellcritrating = { "spellCrit" }, spellhitrating = { "spellHit" }, defenserating = { "defense" },
	dodgerating = { "dodge" }, parryrating = { "parry" }, blockrating = { "block" }, blockvalue = { "blockValue" },
	dps = { "dps", "rdps" }, meleedps = { "dps" }, rangeddps = { "rdps" },
	firespelldamage = { "spFire" }, frostspelldamage = { "spFrost" }, shadowspelldamage = { "spShadow" },
	arcanespelldamage = { "spArcane" }, naturespelldamage = { "spNature" }, holyspelldamage = { "spHoly" },
}

-- Reads "( Pawn: v1: "Name": Class=Mage, Strength=1.5, ... )".
-- -> { name, class, weights, ignored = { names } } or nil, reason.
function Gear.ParsePawn(text)
	if type(text) ~= "string" or text == "" then return nil, "empty" end
	local body = text:match("[Pp]awn%s*:%s*v1%s*:(.*)")
	if not body then return nil, "This is not a Pawn scale string (it starts with \"( Pawn: v1:\")." end
	body = body:gsub("%)%s*$", "")
	local name = body:match('^%s*"([^"]*)"%s*:') or "Imported scale"
	body = body:gsub('^%s*"[^"]*"%s*:', "")
	local weights, ignored, class = {}, {}, nil
	for key, value in body:gmatch("([%w_]+)%s*=%s*([^,%)]+)") do
		local lower = key:lower()
		if lower == "class" then
			class = value:gsub("%s", ""):upper()
		elseif lower ~= "spec" then
			local n = tonumber((value:gsub("%s", "")))
			local to = PAWN_STATS[lower]
			if n and to then
				for _, k in ipairs(to) do weights[k] = n end
			elseif n then
				ignored[#ignored + 1] = key
			end
		end
	end
	if not next(weights) then return nil, "No stats Pathwise knows were found in it." end
	if class == "DEATHKNIGHT" or class == "DEMONHUNTER" or class == "MONK" or class == "EVOKER" then class = nil end
	return { name = name, class = class, weights = weights, ignored = ignored }
end

function Gear.ImportScale(text)
	local scale, err = Gear.ParsePawn(text)
	if not scale then return nil, err end
	scale.class = scale.class or Client.Class()
	local list = {}
	for _, s in ipairs(S.Get("gear.scales") or {}) do
		if not (s.name == scale.name and s.class == scale.class) then list[#list + 1] = s end
	end
	list[#list + 1] = { name = scale.name, class = scale.class, weights = scale.weights }
	S.Set("gear.scales", list)
	if scale.class == Client.Class() then Gear.UseScale(scale.name) end
	return scale
end

---------------------------------------------------------------------------
-- Can I wear it?
---------------------------------------------------------------------------

local ANY_ARMOR = { INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true, INVTYPE_HOLDABLE = true }
local DUAL_WIELD = 674

-- -> usable, reason ("armor" | "weapon" | "shield" | "level"), minLevel
function Gear.Usable(link)
	local equipLoc, classID, subclassID, minLevel = Client.Info(link)
	if not equipLoc or equipLoc == "" then return false, "slot" end
	local class, level = Client.Class(), Client.Level()
	local wear = W.WEAR[class]
	if not wear then return true end
	if classID == 4 and not ANY_ARMOR[equipLoc] then
		if subclassID == 6 then
			if not wear.shield then return false, "shield" end
		elseif subclassID and subclassID >= 1 and subclassID <= 4 then
			local best = (wear.at40 and level >= 40) and wear.at40 or wear.armor
			if subclassID > best then return false, "armor" end
		end
	elseif classID == 2 then
		if not wear.weapons[subclassID] then return false, "weapon" end
	end
	if minLevel and minLevel > level then return true, "level", minLevel end
	return true, nil, minLevel
end

---------------------------------------------------------------------------
-- Scoring and comparing
---------------------------------------------------------------------------

function Gear.Score(link)
	local stats = Gear.Stats(link)
	if not stats then return nil end
	local w = Gear.Weights()
	local s = 0
	for k, v in pairs(stats) do s = s + v * (w[k] or 0) end
	-- A caster's school damage counts too when the weights name the school.
	return s
end

local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 }, INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
Gear.SLOTS = SLOTS
Gear.SLOT_NAMES = { "Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger", "Finger", "Trinket", "Trinket", "Back", "Main hand", "Off hand", "Ranged" }

local cache = {}
function Gear.Clear()
	cache = {}
	S.Fire("GEAR_UPDATED")
end

local function equippedScore(slot)
	local link = Client.Equipped(slot)
	if not link then return 0, nil end
	return Gear.Score(link) or 0, link
end

function Gear.Compare(link)
	if not link then return nil end
	if cache[link] then return cache[link] end
	local equipLoc = Client.Info(link)
	local slots = equipLoc and SLOTS[equipLoc]
	local score = slots and Gear.Score(link)
	if not score then return nil end
	local usable, reason, minLevel = Gear.Usable(link)
	local best
	for _, slot in ipairs(slots) do
		-- A one-hander only goes in the off hand for those who can dual wield.
		if not (slot == 17 and equipLoc == "INVTYPE_WEAPON" and not Client.Knows(DUAL_WIELD)) then
			local old, oldLink = equippedScore(slot)
			if oldLink == link then old = score end
			-- A two-hander replaces both hands.
			if equipLoc == "INVTYPE_2HWEAPON" then old = old + (equippedScore(17)) end
			local r = { score = score, old = old, delta = score - old, slot = slot, empty = oldLink == nil, equipped = oldLink == link }
			-- Rings and trinkets: compare with the weaker one.
			if not best or r.old < best.old then best = r end
		end
	end
	if not best then return nil end
	best.pct = best.old > 0 and (best.delta / best.old * 100) or nil
	best.usable, best.reason, best.minLevel = usable, reason, minLevel
	cache[link] = best
	return best
end

---------------------------------------------------------------------------
-- Pawn, when installed
---------------------------------------------------------------------------

function Gear.PawnLoaded()
	return type(PawnGetItemData) == "function" and type(PawnIsItemAnUpgrade) == "function"
end

function Gear.Source()
	local want = S.Get("gear.source")
	if want == "pathwise" then return "pathwise" end
	if Gear.PawnLoaded() then return "pawn" end
	return "pathwise"
end

-- Pawn's verdict: the best percent upgrade over its visible scales, and the
-- scale's name. nil when Pawn says nothing.
function Gear.PawnUpgrade(link)
	if not Gear.PawnLoaded() then return nil end
	local ok, item = pcall(PawnGetItemData, link)
	if not (ok and item) then return nil end
	local ok2, info = pcall(PawnIsItemAnUpgrade, item)
	if not (ok2 and type(info) == "table" and info[1]) then return nil end
	local best
	for _, u in ipairs(info) do
		if type(u.PercentUpgrade) == "number" and (not best or u.PercentUpgrade > best.PercentUpgrade) then best = u end
	end
	if not best then return nil end
	return best.PercentUpgrade * 100, best.LocalizedScaleName or best.ScaleName
end

---------------------------------------------------------------------------
-- The verdict
---------------------------------------------------------------------------

-- -> isUpgrade, pct (nil when it fills an empty slot), slot name, by ("pawn" | "pathwise")
function Gear.IsUpgrade(link)
	if not link then return false end
	if Gear.Source() == "pawn" then
		local pct, scale = Gear.PawnUpgrade(link)
		if pct and pct >= (S.Get("gear.minUpgrade") or 0) * 100 then return true, pct, scale, "pawn" end
		return false, nil, nil, "pawn"
	end
	local r = Gear.Compare(link)
	if not r or not r.usable or r.reason == "level" or r.equipped then return false, nil, nil, "pathwise" end
	local slotName = Gear.SLOT_NAMES[r.slot]
	if r.empty then return r.score > 0, nil, slotName, "pathwise" end
	if r.pct and r.pct >= (S.Get("gear.minUpgrade") or 0) * 100 and r.delta > 0 then return true, r.pct, slotName, "pathwise" end
	return false, r.pct, slotName, "pathwise"
end

-- Clear the verdicts when what they depend on changes.
for _, ev in ipairs({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "GET_ITEM_INFO_RECEIVED" }) do
	S.RegisterEvent(ev, function() Gear.Clear() end)
end
S.On("SETTING_CHANGED", function(path) if type(path) == "string" and path:find("^gear%.") then cache = {} end end)
