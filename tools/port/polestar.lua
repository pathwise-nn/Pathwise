-- Converts Polestar's compiled guides into Pathwise routes.
--
--   lua5.1 tools/port/polestar.lua <Polestar Guides.lua> [out dir]
--   (default out dir: Pathwise/Routes; run from the repository root)
--
-- Polestar (https://github.com/fitzforge/polestar) is GPL-3.0, like Pathwise.
-- Its leveling, class and profession routes are adapted here with credit:
-- each generated file names the source, and THIRD_PARTY.md lists it.
--
-- What changes on the way:
--   * Quest goals: accept and turnin stay; kill, collect, interact, use and
--     complete for a quest become one "complete" per quest and step (the guide
--     window shows the quest log's own objectives).
--   * Places: Polestar writes coordinates in the Classic map frame; four
--     Forever maps changed frame (Mulgore, Eastern Plaguelands, Redridge,
--     Stormwind) and are converted with QuestieDB's coefficients
--     (data/Forever/conversion.json); the others are the same in both frames.
--   * Items without a quest (buy, collect) become "have N"; bind, flight
--     paths and talks become places to go; hearth, fly, class training,
--     reputation and the like become notes; profession goals keep their
--     meaning (skill, learn, craft, train).
--   * Text placeholders ({npc:1569}, {area:154}, ...) are written out with
--     the guide's own names, else Pathwise's data.
-- Steps with conditions Pathwise does not read are kept and say so.

local SRC = arg[1] or "../pathwise/addon/Pathwise_Guides/Guides.lua"
local OUT = arg[2] or "Pathwise/Routes"

package.path = "tools/port/?.lua;" .. package.path
local L = require("load-polestar")
local guides, order = L.load(SRC)

-- Pathwise's own data, for names.
local data = {}
assert(loadfile("Pathwise/Data/Data.lua"))("Pathwise", data)
local D = data.Data

-- Classic frame -> Forever frame for the maps that changed (QuestieDB
-- conversion.json, geometry.transforms[changed]): live = era * s + o.
local FRAME = {
	[1412] = { sx = 0.8348002068275978, ox = 7.007453108736848, sy = 0.8349418225477033, oy = 13.15387327724201 }, -- Mulgore
	[1423] = { sx = 0.8997577709204458, ox = -1.6464926382438023, sy = 0.9004358590984077, oy = -3.7790494664060477 }, -- Eastern Plaguelands
	[1433] = { sx = 0.9999996626080551, ox = -5.086374584221827, sy = 1.0, oy = 0.0 }, -- Redridge Mountains
	[1453] = { sx = 0.7736792385183993, ox = 19.680449646264936, sy = 0.773826866980289, oy = 24.433287807510073 }, -- Stormwind City
}

local function r2(v) return math.floor(v * 100 + 0.5) / 100 end

local function live(map, x, y, f)
	if not (map and x and y) then return nil end
	local t = f == "e" and FRAME[map]
	if t then x, y = x * t.sx + t.ox, y * t.sy + t.oy end
	return map, r2(x), r2(y)
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

local function nameOf(kind, id, g)
	local key = kind .. ":" .. id
	if g.names and g.names[key] then return g.names[key] end
	local n = tonumber(id)
	if kind == "npc" and D.npcs[n] then return D.npcs[n][1] end
	if kind == "quest" and D.quests[n] then return D.quests[n][1] end
	if kind == "item" and D.items[n] then return D.items[n][1] end
	if kind == "object" and D.objects[n] then return D.objects[n][1] end
	if (kind == "zone" or kind == "area") and n == g.zone and g.zoneName then return g.zoneName end
	return nil
end

local unresolved = 0
local function text(s, g)
	if type(s) ~= "string" then return nil end
	if g.written and g.written[s] then return g.written[s] end
	return (s:gsub("{(%a+):(%d+)}", function(kind, id)
		local n = nameOf(kind, id, g)
		if not n then unresolved = unresolved + 1 end
		return n or ""
	end):gsub("%s+([,.;:])", "%1"):gsub("  +", " "))
end

---------------------------------------------------------------------------
-- Goals
---------------------------------------------------------------------------

local QUEST_WORK = { kill = true, collect = true, interact = true, use = true, complete = true }

local function at(goal)
	local map, x, y = live(goal.map, goal.x, goal.y, goal.f)
	if not map then return nil end
	return { map, x, y }
end

-- Vendor/trainer candidates: { { map, x, y, name, faction }, ... }, at most 8.
local function candidates(goal, g)
	local out = {}
	for _, c in ipairs(goal.candidates or {}) do
		local map, x, y = live(c.map, c.x, c.y, c.f)
		if map and #out < 8 then
			out[#out + 1] = { map, x, y, c.npcName and text(c.npcName, g) or nil, c.faction }
		end
	end
	return #out > 0 and out or nil
end

local function onlyOf(o)
	if type(o) ~= "table" then return nil end
	local out = {}
	for _, k in ipairs({ "classes", "races", "factions" }) do
		if type(o[k]) == "table" and #o[k] > 0 then out[k] = o[k] end
	end
	return next(out) and out or nil
end

local stats = { goals = 0, notes = 0, missingQuests = 0 }

local function questKnown(q) return D.quests[q] ~= nil end

-- One Polestar goal -> a Pathwise goal (or nil when folded into another).
local function convertGoal(goal, g, seenComplete)
	local t = goal.t
	local function with(out)
		out.optional = goal.optional or nil
		out.only = onlyOf(goal.only)
		stats.goals = stats.goals + 1
		return out
	end
	if goal.quest and (t == "accept" or t == "turnin") then
		local out = { t, goal.quest, at = at(goal), who = goal.npcName and text(goal.npcName, g) or (goal.objName and text(goal.objName, g)) }
		if not questKnown(goal.quest) then out.name = goal.title stats.missingQuests = stats.missingQuests + 1 end
		return with(out)
	end
	if goal.quest and QUEST_WORK[t] then
		if seenComplete[goal.quest] then
			if not goal.optional then seenComplete[goal.quest].optional = nil end
			return nil
		end
		local out = with({ "complete", goal.quest, at = at(goal) })
		if not questKnown(goal.quest) then out.name = goal.title stats.missingQuests = stats.missingQuests + 1 end
		seenComplete[goal.quest] = out
		return out
	end
	if t == "goto" or t == "explore" then
		local map, x, y = live(goal.map, goal.x, goal.y, goal.f)
		if not map then return nil end
		return with({ "goto", map, x, y, text(goal.text, g) or (goal.area and nameOf("area", goal.area, g)) or nil })
	end
	if t == "talk" or t == "getfp" then
		local map, x, y = live(goal.map, goal.x, goal.y, goal.f)
		local who = goal.npcName and text(goal.npcName, g)
		local label = t == "getfp" and ("Get the flight path" .. (goal.location and (" at " .. text(goal.location, g)) or ""))
			or ("Talk to " .. (who or "them"))
		if not map then return with({ "note", label }) end
		return with({ "goto", map, x, y, label })
	end
	if t == "sethome" then
		return with({ "bind", text(goal.location, g), at = at(goal), who = goal.npcName and text(goal.npcName, g) })
	end
	if t == "level" then return with({ "level", goal.level }) end
	if t == "buy" or (t == "collect" and goal.item) then
		-- src: where the item comes from, for the shopping list (bought from a
		-- vendor, farmed from mobs, or made/disenchanted by another profession).
		local src = t == "buy" and "vendor" or (goal.candidates and "farm") or (goal.fromKind == "item" and "made") or nil
		return with({ "have", goal.item, goal.count or 1, name = goal.itemName, at = at(goal), from = candidates(goal, g), src = src,
			hint = goal.note and text(goal.note, g) or nil })
	end
	if t == "skill" and goal.skillLine then
		return with({ "skill", goal.skillLine, goal.level, name = goal.skill })
	end
	if t == "learn" and goal.spell then
		return with({ "learn", goal.spell, name = goal.spellName, at = at(goal), from = candidates(goal, g) })
	end
	if t == "craft" and goal.spell then
		local reagents
		for _, r in ipairs(goal.reagents or {}) do
			reagents = reagents or {}
			reagents[#reagents + 1] = { r.item, r.count or 1, r.itemName }
		end
		return with({ "craft", goal.spell, name = goal.spellName, skillLine = goal.skillLine, untilSkill = goal.untilSkill,
			item = goal.item, count = goal.count, reagents = reagents })
	end
	if t == "train" and goal.rankMax and goal.skillLine then
		return with({ "train", goal.skillLine, goal.rankMax, name = goal.skill, from = candidates(goal, g) })
	end
	-- Everything else is an instruction.
	local label
	if t == "hearth" then label = "Hearth to " .. (text(goal.location, g) or "your inn")
	elseif t == "fly" then label = "Fly to " .. (text(goal.location, g) or "the next flight point")
	elseif t == "train" then label = goal.text and text(goal.text, g) or "Train new spells at your class trainer"
	elseif t == "vendor" then label = "Sell and repair" .. (goal.npcName and (" at " .. text(goal.npcName, g)) or "")
	elseif t == "rep" then label = ("%s: reach %s"):format(goal.factionName or "Reputation", ({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" })[goal.standing or 4] or "")
	elseif t == "note" then label = text(goal.text, g)
	else label = text(goal.text, g) or (goal.target and ("Kill " .. text(goal.target, g))) or (goal.objName and text(goal.objName, g)) or (goal.itemName and ("Use " .. goal.itemName)) end
	if not label or label == "" then return nil end
	stats.notes = stats.notes + 1
	return with({ "note", label })
end

---------------------------------------------------------------------------
-- Guides
---------------------------------------------------------------------------

local function convertGuide(g)
	local steps = {}
	for _, s in ipairs(g.steps or {}) do
		local out = { title = text(s.title, g), note = text(s.note, g), only = onlyOf(s.only) }
		if s.when then
			local w = {}
			for _, p in ipairs(s.when) do w[#w + 1] = { k = p.k, q = p.q } end
			out.when = w
		end
		local seen = {}
		for _, goal in ipairs(s.goals or {}) do
			local c = convertGoal(goal, g, seen)
			if c then out[#out + 1] = c end
		end
		if #out > 0 then steps[#steps + 1] = out end
	end
	local title = text(g.title, g) or g.zoneName or g.id
	return {
		id = g.id, title = title, category = g.category, map = g.zone ~= 947 and g.zone or nil,
		levels = { g.minLevel or 1, g.maxLevel or 60 }, faction = g.faction, races = g.races, classes = g.classes,
		next = type(g.next) == "string" and g.next or nil, steps = steps,
	}
end

-- Lua writer: arrays positionally, keys sorted, two decimals already rounded.
local function ser(v, out, depth)
	local t = type(v)
	if t == "number" then out[#out + 1] = (v == math.floor(v)) and ("%.0f"):format(v) or tostring(v)
	elseif t == "string" then out[#out + 1] = ("%q"):format(v):gsub("\\\n", "\\n")
	elseif t == "boolean" then out[#out + 1] = tostring(v)
	elseif t == "table" then
		out[#out + 1] = "{"
		local n = #v
		for i = 1, n do
			if i > 1 then out[#out + 1] = ", " end
			ser(v[i], out, depth + 1)
		end
		local keys = {}
		for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n) then keys[#keys + 1] = k end end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		for i, k in ipairs(keys) do
			if n > 0 or i > 1 then out[#out + 1] = ", " end
			out[#out + 1] = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. (type(k) == "number" and ("%.0f"):format(k) or ("%q"):format(k)) .. "]")
			out[#out + 1] = " = "
			ser(v[k], out, depth + 1)
		end
		out[#out + 1] = "}"
	else out[#out + 1] = "nil" end
end

local function writeFile(name, list, what)
	local path = OUT .. "/" .. name
	local f = assert(io.open(path, "wb"))
	f:write("-- GENERATED by tools/port/polestar.lua: ", what, ".\n")
	f:write("-- Adapted from Polestar's guides (https://github.com/fitzforge/polestar),\n")
	f:write("-- Copyright (c) 2026 The Polestar authors, GPL-3.0. Changes: converted to\n")
	f:write("-- Pathwise's route format; see the converter for what changed.\n")
	f:write("-- Edit the converter or write a route by hand; do not edit this file.\n\n")
	local steps = 0
	for _, r in ipairs(list) do
		local header = {}
		for _, k in ipairs({ "id", "title", "category", "map", "levels", "faction", "races", "classes", "next" }) do header[k] = r[k] end
		local out = {}
		ser(header, out, 0)
		local head = table.concat(out):gsub("}$", "")
		f:write("Pathwise.RegisterRoute(", head, ", steps = {\n")
		for _, s in ipairs(r.steps) do
			local o = {}
			ser(s, o, 1)
			f:write("\t", table.concat(o), ",\n")
			steps = steps + 1
		end
		f:write("} })\n\n")
	end
	f:close()
	io.stderr:write(("wrote %s: %d routes, %d steps\n"):format(path, #list, steps))
end

local leveling, class, professions = {}, {}, {}
for _, id in ipairs(order) do
	local g = guides[id]
	if g.category == "Leveling" then leveling[#leveling + 1] = convertGuide(g)
	elseif g.category == "Class" then class[#class + 1] = convertGuide(g)
	elseif g.category == "Professions" then professions[#professions + 1] = convertGuide(g) end
end

writeFile("Leveling.lua", leveling, "every leveling route, 1-60, both factions")
writeFile("Class.lua", class, "class quest routes")
writeFile("Professions.lua", professions, "profession routes, 1-300")
io.stderr:write(("goals %d, notes %d, quests not in Pathwise's data %d, unresolved names %d\n"):format(
	stats.goals, stats.notes, stats.missingQuests, unresolved))
