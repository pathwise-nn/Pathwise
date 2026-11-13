-- Pathwise recipe book: a leveling plan per profession, skill range by
-- skill range, beside the step-by-step profession routes.
--
--   RB.Book(key)                 the profession's book, or nil
--   RB.Paths(book)               the other ways through some ranges ("Strange Dust", "Smelting")
--   RB.Steps(book, path, side)   the plan for a faction ("A" or "H"), a path's steps in place of the main ones
--   RB.At(steps, skill)          the index of the step for that skill, nil past the end
--   RB.Spell(id)                 { id, name, learn, yellow, grey, made, reagents, teach }
--   RB.Color(spell, skill)       "red" (can't learn yet), "orange", "yellow", "green", "grey"
--   RB.Materials(entries)        everything the "make" entries use, most first
--   RB.Sources(spell)            where its recipe items come from
--   RB.NextRank(book, cap)       the rank to train after the present cap
--   RB.People(rank, side)        that rank's trainers (or book sellers, quest givers) for a faction
--
-- Data: Data.recipebook (tools/data/build.lua). The choices (which recipe
-- for which range, how many, the rank trainers, the zones) are facts from
-- wow-professions.com's Forever guides, kept in data/professions/*.json;
-- names, reagents, colours and recipe items come from the Forever client's
-- own tables (tools/data/recipebook.js), the NPCs and recipe sources from
-- QuestieDB. The guides were written on Forever's beta and say which ranges
-- they could not test there (`untestedFrom`). Green is the Classic estimate,
-- halfway from yellow to grey. It only advises.

local ADDON, ns = ...
local C = ns.Compat
local RB = {}
ns.RecipeBook = RB
Pathwise.RecipeBook = RB

local function data() return ns.Data and ns.Data.recipebook end

function RB.Book(key)
	local d = data()
	for _, b in ipairs(d and d.books or {}) do if b.key == key then return b end end
	return nil
end

function RB.Side()
	local f = UnitFactionGroup and UnitFactionGroup("player")
	return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

function RB.Paths(book)
	local out, seen = {}, {}
	for _, s in ipairs(book.steps) do
		if s.path and not seen[s.path] then seen[s.path] = true out[#out + 1] = s.path end
	end
	return out
end

local function forSide(s, side) return not s.faction or not side or s.faction == side end

-- The main plan for `side`; with `path`, that path's steps replace the main
-- steps over the ranges it covers.
function RB.Steps(book, path, side)
	local main, other = {}, {}
	for _, s in ipairs(book.steps) do
		if forSide(s, side) then
			if not s.path then main[#main + 1] = s elseif s.path == path then other[#other + 1] = s end
		end
	end
	local out = {}
	if #other > 0 then
		local lo, hi = 300, 0
		for _, s in ipairs(other) do lo, hi = math.min(lo, s.from), math.max(hi, s.to) end
		for _, s in ipairs(main) do if s.to <= lo or s.from >= hi then out[#out + 1] = s end end
		for _, s in ipairs(other) do out[#out + 1] = s end
	else
		for _, s in ipairs(main) do out[#out + 1] = s end
	end
	table.sort(out, function(a, b) return a.from < b.from end)
	return out
end

function RB.At(steps, skill)
	skill = skill or 0
	for i, s in ipairs(steps) do if skill < s.to then return i end end
	return nil
end

function RB.Spell(id)
	local d = data()
	local s = d and d.spells[id]
	if not s then return nil end
	return { id = id, name = s[1], line = s[2], learn = s[3], yellow = s[4], grey = s[5], made = s[6], reagents = s[7] or {}, teach = s[8] or {} }
end

function RB.ItemName(id)
	local d = data()
	local name = d and d.items[id]
	if type(name) == "string" then return name end
	local fn = C_Item and C_Item.GetItemNameByID
	return (fn and C.Readable(fn(id))) or ("item " .. tostring(id))
end

-- A zone's name: the client's, else the one the data keeps (UiMap).
function RB.ZoneName(map)
	local d = data()
	return C.MapName(map) or (d and d.zones and d.zones[map]) or (ns.L("map ") .. tostring(map))
end

function RB.Color(spell, skill)
	skill = skill or 0
	if spell.learn and skill < spell.learn then return "red" end
	local y, g = spell.yellow, spell.grey
	if not (y and g) then return nil end
	if skill < y then return "orange" end
	if skill < math.floor((y + g) / 2) then return "yellow" end
	if skill < g then return "green" end
	return "grey"
end

-- A step's entries for a faction: { kind = "make" | "any" | "alt", spell, count }.
function RB.Entries(step, side)
	local out = {}
	for _, k in ipairs({ "make", "any", "alt" }) do
		for _, e in ipairs(step[k] or {}) do
			if not e[3] or not side or e[3] == side then
				local sp = RB.Spell(e[1])
				if sp then out[#out + 1] = { kind = k, spell = sp, count = e[2] } end
			end
		end
	end
	return out
end

-- What the "make" entries use in all: { { item, name, count }, ... }, most first.
function RB.Materials(entries)
	local by, list = {}, {}
	for _, e in ipairs(entries) do
		if e.kind == "make" and e.count then
			for _, r in ipairs(e.spell.reagents) do
				local row = by[r[1]]
				if not row then
					row = { item = r[1], name = RB.ItemName(r[1]), count = 0 }
					by[r[1]] = row
					list[#list + 1] = row
				end
				row.count = row.count + r[2] * e.count
			end
		end
	end
	table.sort(list, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.name < b.name end)
	return list
end

local function npc(id)
	local n = id and ns.Data and ns.Data.npcs[id]
	return n and { id = id, name = n[1], friendly = n[4], spawns = n[5] } or nil
end
RB.Npc = npc

-- An NPC's place for the arrow: the spawn nearest the player.
function RB.Place(id)
	local n = npc(id)
	if not n then return nil end
	local here = { C.PlayerMapPosition() }
	local from = here[1] and { map = here[1], x = here[2], y = here[3] } or nil
	local map, x, y = ns.Quests.Nearest(n.spawns, from)
	if not map then return nil end
	return { map = map, x = x, y = y, name = n.name, zone = C.MapName(map) }
end

local function friendlyTo(n, side) return not side or not n.friendly or n.friendly:find(side, 1, true) ~= nil end

-- Where a spell's recipe items come from:
-- { { item, name, vendors = { npc, ... }, drops = { npc, ... }, quests = { id, ... }, worldDrop }, ... }
function RB.Sources(spell, side)
	local d = data()
	local out = {}
	for _, it in ipairs(spell.teach or {}) do
		local s = d and d.sources[it]
		if s then
			local row = { item = it, name = RB.ItemName(it), vendors = {}, drops = {}, quests = s.quests or {}, worldDrop = s.worldDrop }
			for _, v in ipairs(s.vendors or {}) do
				local n = npc(v)
				if n and friendlyTo(n, side) then row.vendors[#row.vendors + 1] = n elseif n then row.otherSide = true end
			end
			for _, v in ipairs(s.drops or {}) do local n = npc(v) if n then row.drops[#row.drops + 1] = n end end
			out[#out + 1] = row
		end
	end
	return out
end

-- The rank to train after the present cap: { rank, cap, level, skill, cost, trainers, book, quest, ... } or nil.
function RB.NextRank(book, cap)
	for _, r in ipairs(book.ranks) do if r.cap > (cap or 0) then return r end end
	return nil
end

-- A rank's people for a faction: { { name, id, npc }, ... }; a name the data
-- does not know is kept (no id, no arrow).
function RB.People(rank, side)
	local out = {}
	for _, t in ipairs(rank.trainers or {}) do
		local n = t[2] and npc(t[2]) or nil
		if not n or friendlyTo(n, side) then out[#out + 1] = { name = t[1], id = t[2] or nil, npc = n } end
	end
	return out
end

---------------------------------------------------------------------------
-- Text, for the panel
---------------------------------------------------------------------------

function RB.EntryText(e)
	return e.count and ns.L("%dx %s"):format(e.count, e.spell.name) or e.spell.name
end

function RB.ColorText(spell)
	local bits = {}
	if spell.learn then bits[#bits + 1] = (ns.L("learn %d")):format(spell.learn) end
	if spell.yellow then bits[#bits + 1] = (ns.L("yellow %d")):format(spell.yellow) end
	if spell.grey then bits[#bits + 1] = (ns.L("grey %d")):format(spell.grey) end
	return table.concat(bits, ", ")
end

function RB.ReagentText(spell)
	local bits = {}
	for _, r in ipairs(spell.reagents) do bits[#bits + 1] = ("%d %s"):format(r[2], RB.ItemName(r[1])) end
	return table.concat(bits, ", ")
end

local function names(list, max)
	local bits = {}
	for i, n in ipairs(list) do
		if i > max then bits[#bits + 1] = (ns.L("+%d more")):format(#list - max) break end
		local zone
		for map in pairs(n.spawns or {}) do zone = C.MapName(map) break end
		bits[#bits + 1] = zone and ("%s (%s)"):format(n.name, zone) or n.name
	end
	return table.concat(bits, ", ")
end

function RB.SourceText(src)
	local bits = {}
	if #src.vendors > 0 then bits[#bits + 1] = ns.L("sold by ") .. names(src.vendors, 3) end
	if #src.quests > 0 then
		local q = {}
		for _, id in ipairs(src.quests) do
			local d = ns.Quests.Data.quests[id]
			q[#q + 1] = d and d[1] or (ns.L("quest ") .. id)
		end
		bits[#bits + 1] = ns.L("reward of ") .. table.concat(q, ", ")
	end
	if #src.drops > 0 then bits[#bits + 1] = ns.L("drops from ") .. names(src.drops, 2) end
	if src.worldDrop then bits[#bits + 1] = "a world drop (Auction House)" end
	if #bits == 0 then bits[1] = src.otherSide and "sold only to the other faction (Auction House)" or "source not in the data" end
	return table.concat(bits, "; ")
end

-- Copper as "1g 50s", "50s", "20c".
function RB.MoneyText(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local bits = {}
	if g > 0 then bits[#bits + 1] = g .. "g" end
	if s > 0 then bits[#bits + 1] = s .. "s" end
	if c > 0 or #bits == 0 then bits[#bits + 1] = c .. "c" end
	return table.concat(bits, " ")
end

function RB.RankText(r)
	local need = {}
	if r.level then need[#need + 1] = (ns.L("level %d")):format(r.level) end
	if r.skill then need[#need + 1] = (ns.L("skill %d")):format(r.skill) end
	if r.cost then need[#need + 1] = RB.MoneyText(r.cost) end
	local text = (ns.L("%s (to %d)")):format(r.rank, r.cap)
	if #need > 0 then text = text .. ": " .. table.concat(need, ", ") end
	return text
end
