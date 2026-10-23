-- The Pathwise Gear panel (Settings > Pathwise suite > Pathwise Gear, or the
-- minimap button's Settings): who scores items, the spec and its stat
-- priority, custom weights, the upgrades in your bags, and the options.

local ADDON, ns = ...
local S, Gear, W = Pathwise.Suite, ns.Gear, ns.Weights
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

local function onOff(v) return v and "On" or "Off" end
local function toggle(path) return function() S.Set(path, not S.Get(path)) S.Refresh() end end

function P.Build()
	local rows = { { "heading", "Pathwise Gear" } }
	local weights, name, from = Gear.Weights()
	rows[#rows + 1] = { "text", from == "imported" and ("Scoring with your custom weights \"%s\"."):format(name)
		or ("Scoring with Pathwise's %s weights."):format(name), "gear" }

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
	local spec = from ~= "imported" and W.Spec(class, key)
	if spec and spec.note then rows[#rows + 1] = { "text", "The class guides agree: " .. spec.note .. ".", "muted" } end
	rows[#rows + 1] = { "text", "Pathwise's own weights, ordered as the Icy Veins and Mobalytics Forever guides advise. Not yet checked in game.", "muted" }

	-- Custom weights, pasted.
	rows[#rows + 1] = { "heading", "Custom weights (optional)" }
	rows[#rows + 1] = { "text", "Paste your own, like Intellect=1.2, Stamina=0.5 (a guide site's scale string works too), then Import." }
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

	rows[#rows + 1] = { "heading", "Best for my level" }
	rows[#rows + 1] = { "choice", "Best gear for my level", "Slot by slot: what to chase and where it comes from", function() S.Open("gearbest") end }

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

-- Best for my level: one row per slot, the best item this character can get
-- by now, where from, and whether they have it. Click a row: the arrow.
function P.BuildBest()
	local Best = ns.Best
	local list, pending = Best.List()
	local _, name = Gear.Weights()
	local level = Gear.Client.Level()
	local ahead = S.Get("gear.bisAhead") or 0
	local rows = { { "heading", "Best for my level" } }
	rows[#rows + 1] = { "text", ("Level %d%s  ·  %s weights"):format(level, ahead > 0 and (" (and the next %d)"):format(ahead) or "", tostring(name)), "gear" }
	local missing = 0
	for _, e in ipairs(list) do if not e.have then missing = missing + 1 end end
	rows[#rows + 1] = { "text", missing == 0 and #list > 0 and "You have the best of everything Pathwise knows for your level."
		or ("%d of %d slots to chase. Click one: the arrow leads to it."):format(missing, #list) }
	if pending > 0 then
		rows[#rows + 1] = { "text", ("Loading %d items from the game..."):format(pending), "muted" }
	end
	for _, e in ipairs(list) do
		local status
		if e.wearing then status = "Wearing it"
		elseif e.have then status = "In your bags"
		elseif e.pct then status = ("%+.0f%% on what you wear"):format(e.pct)
		else status = "Empty slot" end
		local sub = Best.SourceText(e.source) .. "  ·  " .. status
		if e.minLevel and e.minLevel > level then sub = sub .. ("  ·  from level %d"):format(e.minLevel) end
		rows[#rows + 1] = { "choice", ("%s:  %s%s"):format(e.slotName, tostring(e.name), e.have and "  (have)" or ""), sub, function()
			if Best.Chase(e) then
				S.Print(("Pathwise Gear: the arrow leads to %s for %s."):format(Best.SourceText(e.source), tostring(e.name)))
			else
				S.Print(("Pathwise Gear: %s comes from %s; Pathwise has no place to point at."):format(tostring(e.name), Best.SourceText(e.source)))
			end
		end }
	end
	if #list == 0 and pending == 0 then rows[#rows + 1] = { "text", "No gear found for your level yet." } end
	rows[#rows + 1] = { "heading", "Options" }
	local function pickAhead(n) return function() S.Set("gear.bisAhead", n) S.Refresh() end end
	rows[#rows + 1] = { "setting", "Look ahead", ahead == 0 and "My level" or ("+" .. ahead), {
		{ "Now", pickAhead(0), ahead == 0 and "accent" or "default" },
		{ "+3", pickAhead(3), ahead == 3 and "accent" or "default" },
		{ "+5", pickAhead(5), ahead == 5 and "accent" or "default" } } }
	rows[#rows + 1] = { "setting", "Alert when I pick one up", S.Get("gear.bisAlert") and "On" or "Off", {
		{ S.Get("gear.bisAlert") and "Turn off" or "Turn on", function() S.Set("gear.bisAlert", not S.Get("gear.bisAlert")) S.Refresh() end } } }
	rows[#rows + 1] = { "text", "On screen, with a sound and a chat line, and a gold star in your bags: for your level and for the level an item needs.", "muted" }
	local crafted = S.Get("gear.bisCrafted") or "all"
	local function pickCrafted(v) return function() S.Set("gear.bisCrafted", v) S.Refresh() end end
	rows[#rows + 1] = { "setting", "Crafted gear", ({ all = "Anyone's", mine = "Mine only", off = "Hidden" })[crafted] or crafted, {
		{ "All", pickCrafted("all"), crafted == "all" and "accent" or "default" },
		{ "Mine", pickCrafted("mine"), crafted == "mine" and "accent" or "default" },
		{ "Off", pickCrafted("off"), crafted == "off" and "accent" or "default" } } }
	rows[#rows + 1] = { "text", "All: crafts you could buy from the Auction House or a crafter, and your own. Mine: only what your professions make.", "muted" }
	rows[#rows + 1] = { "setting", "Season of Discovery recipes", S.Get("gear.bisSod") and "Shown" or "Hidden", {
		{ S.Get("gear.bisSod") and "Hide" or "Show", function() S.Set("gear.bisSod", not S.Get("gear.bisSod")) S.Refresh() end } } }
	rows[#rows + 1] = { "text", "They are in Forever's game files and some were found in Forever; not all are confirmed.", "muted" }
	rows[#rows + 1] = { "setting", "Raid gear", S.Get("gear.bisRaids") and "Shown" or "Hidden", {
		{ S.Get("gear.bisRaids") and "Hide" or "Show", function() S.Set("gear.bisRaids", not S.Get("gear.bisRaids")) S.Refresh() end } } }
	rows[#rows + 1] = { "text", "Worked out in game from Pathwise's weights and the item's stats as the game gives them. Where items come from: QuestieDB's Forever data; recipes: Forever's game files.", "muted" }
	rows[#rows + 1] = { "buttons", { { "Pathwise Gear", "default", function() S.Open("gear") end }, { "Close", "default", S.Close } } }
	return rows
end
S.Panel("gearbest", P.BuildBest)
S.On("GEAR_BEST_UPDATED", function() if S.IsOpen("gearbest") then S.Refresh() end end)
S.RegisterModule({
	key = "gear", name = "Pathwise Gear", accent = "gear",
	about = "Upgrades, stat priority, best quest rewards",
	open = function() S.Open("gear") end,
})
S.On("GEAR_UPDATED", function() end)
