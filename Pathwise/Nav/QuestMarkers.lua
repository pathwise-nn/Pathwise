-- Pathwise quest markers: every quest around you on the world map and the
-- minimap, from the quest data (QuestieDB's Forever data, Data/Data.lua),
-- not just the guide's step:
--   "!" at a giver for each quest this character can take now,
--   "?" at the finisher of each quest in the log that is ready to hand in,
--   small dots where the monsters and objects of an unfinished objective are,
--     for every quest in the log.
-- Pins.lua draws them (its frames, its rules about not touching the map's
-- own tables); this file only decides what they are.
--
-- Quest log APIs (Forever's QuestLogDocumentation): C_QuestLog.
-- GetNumQuestLogEntries, GetInfo (questID, isHeader, isHidden), plus what
-- Guide/Quests.lua reads.

local ADDON, ns = ...
local Q = ns.Quests
local M = {}
ns.QuestMarkers = M

ns.Defaults("pins", {
	quests = true, -- quest markers on the world map
	questsMinimap = true, -- and on the minimap
	lowLevel = false, -- also quests far below your level
})

-- Data layout positions (tools/data/build.lua, as in Guide/Quests.lua).
local START_NPC, START_OBJ, END_NPC, END_OBJ, SPECIAL = 7, 8, 10, 11, 16
M.LOW = 5 -- a quest this many levels below you or more is "low" (hidden unless lowLevel)

local readable = function(v) return ns.Compat.Readable(v) end

---------------------------------------------------------------------------
-- Index: the quests whose giver stands on each map (built once)
---------------------------------------------------------------------------

local byMap
local function spawnsOf(kind, id)
	local D = Q.Data
	if kind == "n" then local n = D.npcs[id] return n and n[5], n and n[1] end
	local o = D.objects[id]
	return o and o[2], o and o[1]
end

function M.Index()
	if byMap then return byMap end
	byMap = {}
	for id, q in pairs(Q.Data.quests) do
		local maps = {}
		for _, n in ipairs(q[START_NPC] or {}) do
			local sp = spawnsOf("n", n)
			if type(sp) == "table" then for map in pairs(sp) do maps[map] = true end end
		end
		for _, o in ipairs(q[START_OBJ] or {}) do
			local sp = spawnsOf("o", o)
			if type(sp) == "table" then for map in pairs(sp) do maps[map] = true end end
		end
		for map in pairs(maps) do
			byMap[map] = byMap[map] or {}
			local list = byMap[map]
			list[#list + 1] = id
		end
	end
	for _, list in pairs(byMap) do table.sort(list) end
	return byMap
end

---------------------------------------------------------------------------
-- Which quests
---------------------------------------------------------------------------

local function skipped(id)
	local E = ns.Engine
	local s = E and E.State and E.State()
	return s and s.skipped and s.skipped[id] ~= nil
end

-- A quest this character can take now.
function M.Available(id, p)
	local q = Q.Get(id)
	if not q or q[SPECIAL] then return false end
	p = p or Q.Player()
	if Q.Done(id) or Q.OnQuest(id) or skipped(id) then return false end
	if not Q.ForPlayer(id, p) or Q.Closed(id) or not Q.PrereqsMet(id) then return false end
	if Q.MinLevel(id) > (p.level or 1) then return false end
	return true
end

-- Far below the character: a grey quest.
function M.Low(id, p)
	local lvl = Q.Level(id)
	return lvl > 0 and lvl <= ((p and p.level) or 1) - M.LOW
end

-- The quests in the log: { id, ... } (headers and hidden ones left out).
function M.LogQuests()
	local L = C_QuestLog
	local out = {}
	if not (L and L.GetNumQuestLogEntries and L.GetInfo) then return out end
	local n = readable(L.GetNumQuestLogEntries()) or 0
	for i = 1, n do
		local info = L.GetInfo(i)
		if type(info) == "table" and not readable(info.isHeader) and not readable(info.isHidden) then
			local id = readable(info.questID)
			if type(id) == "number" and id > 0 then out[#out + 1] = id end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- The pins of a map
---------------------------------------------------------------------------

local function levelText(id)
	local lvl = Q.Level(id)
	return lvl > 0 and ("[%d] %s"):format(lvl, Q.Name(id)) or Q.Name(id)
end

-- Every spot of an NPC or object list on `map`, one pin per spot, all the
-- quests at that giver in one tooltip.
local function atEntities(out, map, groups, kind, header)
	for _, g in pairs(groups) do
		local pts = g.spawns and g.spawns[map]
		if pts then
			table.sort(g.lines)
			local sub = header .. "\n" .. table.concat(g.lines, "\n")
			for k = 1, #pts, 2 do
				out[#out + 1] = { map = map, x = pts[k], y = pts[k + 1], kind = g.low and "availableLow" or kind, title = g.name, sub = sub }
			end
		end
	end
end

local function group(groups, entityKind, eid, line, low)
	local key = entityKind .. eid
	local g = groups[key]
	if not g then
		local spawns, name = spawnsOf(entityKind, eid)
		g = { spawns = spawns, name = name or "?", lines = {}, low = true }
		groups[key] = g
	end
	g.lines[#g.lines + 1] = line
	if not low then g.low = false end
end

-- { { map, x, y, kind, title, sub }, ... } for `map`: givers ("available",
-- "availableLow"), finishers ("turnin") and objective spots ("objective").
function M.ForMap(map)
	local out = {}
	if not map then return out end
	local p = Q.Player()
	local showLow = ns.Get("pins.lowLevel")
	-- Givers.
	local givers = {}
	for _, id in ipairs(M.Index()[map] or {}) do
		if M.Available(id, p) then
			local low = M.Low(id, p)
			if showLow or not low then
				local q = Q.Get(id)
				for _, n in ipairs(q[START_NPC] or {}) do group(givers, "n", n, levelText(id), low) end
				for _, o in ipairs(q[START_OBJ] or {}) do group(givers, "o", o, levelText(id), low) end
			end
		end
	end
	atEntities(out, map, givers, "available", "Quests to take:")
	-- The log: ready ones at their finisher, the others' objectives.
	local finishers = {}
	for _, id in ipairs(M.LogQuests()) do
		local q = Q.Get(id)
		if q then
			if Q.Ready(id) then
				for _, n in ipairs(q[END_NPC] or {}) do group(finishers, "n", n, Q.Name(id), false) end
				for _, o in ipairs(q[END_OBJ] or {}) do group(finishers, "o", o, Q.Name(id), false) end
			else
				local log = Q.Objectives(id)
				for i = 1, Q.ObjectiveCount(id) do
					if not (log and log[i] and log[i].done) then
						local pts, name = Q.ObjectiveSpots(id, i, map)
						for k = 1, pts and #pts or 0, 2 do
							out[#out + 1] = { map = map, x = pts[k], y = pts[k + 1], kind = "objective", title = name, sub = Q.Name(id) }
						end
					end
				end
			end
		end
	end
	atEntities(out, map, finishers, "turnin", "Hand in:")
	return out
end

-- For other modules: forget the index (new data in tests).
function M.Reset() byMap = nil end
