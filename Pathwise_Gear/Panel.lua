-- The Pathwise Gear panel (Settings > Pathwise suite > Pathwise Gear, or the
-- minimap button's Settings): who scores items, the spec and its stat
-- priority, Pawn scale strings, the upgrades in your bags, and the options.

local ADDON, ns = ...
local S, Gear, W = Pathwise.Suite, ns.Gear, ns.Weights
local P = {}
ns.Panel = P

local NAMES = {
	str = "Strength", agi = "Agility", sta = "Stamina", int = "Intellect", spi = "Spirit", armor = "Armour",
	ap = "Attack power", rap = "Ranged attack power", sp = "Spell damage", heal = "Healing", mp5 = "Mana per 5 sec",
	crit = "Crit %", hit = "Hit %", spellCrit = "Spell crit %", spellHit = "Spell hit %", defense = "Defense",
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
	local PCT = { crit = true, hit = true, spellCrit = true, spellHit = true, dodge = true, parry = true, block = true, dps = true, rdps = true }
	local SKIP = { health = true, mana = true, armor = true, blockValue = true, spFire = true, spFrost = true, spShadow = true, spArcane = true, spNature = true, spHoly = true }
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

local function onOff(v) return v and "On" or "Off" end
local function toggle(path) return function() S.Set(path, not S.Get(path)) S.Refresh() end end

function P.Build()
	local rows = { { "heading", "Pathwise Gear" } }
	local source = Gear.Source()
	local weights, name, from = Gear.Weights()
	if source == "pawn" then
		rows[#rows + 1] = { "text", "Scoring with Pawn: its scales decide what is an upgrade.", "gear" }
	else
		rows[#rows + 1] = { "text", from == "imported" and ("Scoring with your Pawn scale \"%s\"."):format(name)
			or ("Scoring with Pathwise's %s weights."):format(name), "gear" }
	end
	local want = S.Get("gear.source")
	local function pick(v) return function() S.Set("gear.source", v) Gear.Clear() S.Refresh() end end
	local choices = { { "Automatic", pick("auto"), want == "auto" and "accent" or "default" } }
	if Gear.PawnLoaded() then choices[#choices + 1] = { "Pawn", pick("pawn"), want == "pawn" and "accent" or "default" } end
	choices[#choices + 1] = { "Pathwise", pick("pathwise"), want == "pathwise" and "accent" or "default" }
	rows[#rows + 1] = { "setting", "Scores from", "", choices }
	if not Gear.PawnLoaded() then
		rows[#rows + 1] = { "text", "Have Pawn installed? Automatic uses it.", "muted" }
	end

	-- Spec and stat priority (Pathwise's weights).
	local class = Gear.Client.Class()
	local key, label, how = Gear.Spec()
	rows[#rows + 1] = { "heading", "Spec" }
	local specButtons = {}
	for _, s in ipairs(W.Specs(class)) do
		specButtons[#specButtons + 1] = { s.label:gsub(" %b()", ""), function() Gear.SetSpec(s.key) S.Refresh() end, s.key == key and "accent" or "default" }
	end
	rows[#rows + 1] = { "setting", "", "", specButtons }
	rows[#rows + 1] = { "text", how == "auto" and "Following your talents (or the usual levelling spec)." or "Chosen by you.", "muted" }
	if how == "chosen" then
		rows[#rows + 1] = { "choice", "Follow my talents again", nil, function()
			local t = {}
			for k, v in pairs(S.Get("gear.spec") or {}) do t[k] = v end
			t[class] = nil
			S.Set("gear.spec", t)
			Gear.Clear()
			S.Refresh()
		end }
	end
	local main, pct = P.Priority(from == "imported" and weights or W.For(class, key))
	rows[#rows + 1] = { "heading", "Stat priority" }
	rows[#rows + 1] = { "text", main ~= "" and main or "No stats", "text" }
	if pct ~= "" then rows[#rows + 1] = { "text", "Per 1%: " .. pct } end
	rows[#rows + 1] = { "text", "Pathwise's own weights from Classic's stat rules, not yet checked on Forever.", "muted" }

	-- Pawn scale strings.
	rows[#rows + 1] = { "heading", "Your own weights (Pawn scale string)" }
	rows[#rows + 1] = { "text", "Paste a scale string from Pawn or a guide site, then Import." }
	rows[#rows + 1] = { "input", "gear.import", 3 }
	rows[#rows + 1] = { "buttons", { { "Import", "accent", function()
		local scale, err = Gear.ImportScale(S.InputText("gear.import"))
		if scale then
			S.ClearInput("gear.import")
			local extra = #scale.ignored > 0 and (" (left out: %s)"):format(table.concat(scale.ignored, ", ")) or ""
			S.Print(("Pathwise Gear: imported \"%s\"%s."):format(scale.name, extra))
		else
			S.Print("Pathwise Gear: " .. tostring(err))
		end
		S.Refresh()
	end } } }
	for _, sc in ipairs(Gear.Scales()) do
		local inUse = from == "imported" and name == sc.name
		rows[#rows + 1] = { "choice", sc.name, inUse and "In use  ·  click to use Pathwise's weights" or "Click to use it", function()
			Gear.UseScale(not inUse and sc.name or nil)
			S.Refresh()
		end }
	end

	-- Upgrades waiting in the bags.
	local ups = P.BagUpgrades(8)
	rows[#rows + 1] = { "heading", ("Upgrades in your bags (%d)"):format(#ups) }
	if #ups == 0 then rows[#rows + 1] = { "text", "None right now." } end
	for _, u in ipairs(ups) do
		rows[#rows + 1] = { "text", ("%s   %s%s"):format(u.name, u.pct and ("+%.1f%%"):format(u.pct) or "empty slot", u.slot and ("  ·  " .. u.slot) or ""), "success" }
	end

	rows[#rows + 1] = { "heading", "Options" }
	rows[#rows + 1] = { "setting", "Line on item tooltips", onOff(S.Get("gear.tooltip")), { { S.Get("gear.tooltip") and "Hide" or "Show", toggle("gear.tooltip") } } }
	rows[#rows + 1] = { "setting", "Arrow on bag upgrades", onOff(S.Get("gear.bags")), { { S.Get("gear.bags") and "Hide" or "Show", toggle("gear.bags") } } }
	rows[#rows + 1] = { "setting", "Best quest reward", onOff(S.Get("gear.rewards")), { { S.Get("gear.rewards") and "Hide" or "Show", toggle("gear.rewards") } } }
	rows[#rows + 1] = { "slider", "Smallest upgrade shown", "gear.minUpgrade", 0, 0.1, 0.01, function(v) return ("%d%%"):format(v * 100) end }
	rows[#rows + 1] = { "buttons", { { "Close", "default", S.Close } } }
	return rows
end

S.Panel("gear", P.Build)
S.RegisterModule({
	key = "gear", name = "Pathwise Gear", accent = "gear",
	about = "Upgrades, stat priority, Pawn scales, best quest rewards",
	open = function() S.Open("gear") end,
})
S.On("GEAR_UPDATED", function() end)
