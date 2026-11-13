-- What Pathwise Gear's pages show (Pages.lua draws them): the stat names,
-- a spec's stat priority, and the upgrades in your bags.

local ADDON, ns = ...
local S, Gear = ns.S, ns.Gear
local P = {}
ns.Panel = P

local NAMES = {
	str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = "Armour",
	ap = "Attack power", rap = "Ranged attack power", sp = "Spell damage", heal = "Healing", mp5 = "Mana per 5 sec",
	crit = "Crit %", hit = "Hit %", spellCrit = "Spell crit %", spellHit = "Spell hit %", defense = "Defense",
	haste = "Haste %", expertise = "Expertise",
	dodge = "Dodge %", parry = "Parry %", block = "Block %", blockValue = "Block value", dps = "Weapon DPS",
	rdps = "Ranged DPS", health = "Health", mana = "Mana", hp5 = "Health per 5 sec",
	spFire = "Fire damage", spFrost = "Frost damage", spShadow = "Shadow damage", spArcane = "Arcane damage",
	spNature = "Nature damage", spHoly = "Holy damage",
}
P.NAMES = NAMES

-- The spec's stats in order of value per point, the base stats first (the
-- percent stats and weapon DPS are per 1% and per 1 DPS, so they are listed
-- apart). -> "Intellect › Spell damage › ...", "Hit %, Crit %"
function P.Priority(weights)
	local base, pct = {}, {}
	local PCT = { crit = true, hit = true, spellCrit = true, spellHit = true, dodge = true, parry = true, block = true,
		dps = true, rdps = true, haste = true, expertise = true }
	local SKIP = { health = true, mana = true, armor = true, blockValue = true, spFire = true, spFrost = true, spShadow = true, spArcane = true, spNature = true, spHoly = true }
	-- A caster's plain crit copies its spell crit: list it once.
	if weights and weights.spellCrit and weights.crit == weights.spellCrit then SKIP.spellCrit = true end
	for k, v in pairs(weights or {}) do
		if NAMES[k] and v > 0 and not SKIP[k] then
			if PCT[k] then pct[#pct + 1] = { k, v } else base[#base + 1] = { k, v } end
		end
	end
	table.sort(base, function(a, b) return a[2] > b[2] end)
	table.sort(pct, function(a, b) return a[2] > b[2] end)
	local a, b = {}, {}
	for i, r in ipairs(base) do if i <= 6 then a[#a + 1] = NAMES[r[1]] end end
	for i, r in ipairs(pct) do if i <= 4 then b[#b + 1] = NAMES[r[1]] end end
	return table.concat(a, "  ›  "), table.concat(b, "  ›  ")
end

-- Upgrades in the bags: { { link, name, pct, slot }, ... }, biggest first.
function P.BagUpgrades(limit)
	local out = {}
	local Cn = C_Container
	if not (Cn and Cn.GetContainerNumSlots and Cn.GetContainerItemLink) then return out end
	for bag = 0, 4 do
		for slot = 1, Cn.GetContainerNumSlots(bag) or 0 do
			local link = S.Compat.Readable(Cn.GetContainerItemLink(bag, slot))
			if link then
				local up, pct, where = Gear.IsUpgrade(link)
				if up then
					local _, _, _, _, _, name = Gear.Client.Info(link)
					out[#out + 1] = { link = link, name = name or link, pct = pct, slot = where }
				end
			end
		end
	end
	table.sort(out, function(a, b) return (a.pct or 1e9) > (b.pct or 1e9) end)
	while #out > (limit or 8) do table.remove(out) end
	return out
end
