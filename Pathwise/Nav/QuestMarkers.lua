-- Pathwise quest markers on the world map and the minimap, for the quests
-- you are following, not every quest around you (that crowded the map):
--   the quests of the guide's step shown (and its side guide's, and the extra
--   quest picked), and the quests ticked as tracked in the game's quest log.
-- For those, from the quest data (QuestieDB's Forever data, Data/Data.lua):
--   "!" at the giver of a quest the step says to take, if you can take it,
--   "?" at the finisher of a quest in the log that is ready to hand in,
--   small dots where the monsters and objects of an unfinished objective are.
-- Pins.lua draws them (its frames, its rules about not touching the map's
-- own tables); this file only decides what they are.
--
-- Quest log APIs (Forever's QuestLogDocumentation): C_QuestLog.
-- GetNumQuestLogEntries, GetInfo (questID, isHeader, isHidden),
-- GetQuestWatchType (nil when not tracked; the classic IsQuestWatched(index)
-- if that is missing), plus what Guide/Quests.lua reads.

local ADDON, ns = ...
local Q = ns.Quests
local M = {}
ns.QuestMarkers = M

ns.Defaults("pins", {
	quests = true, -- quest markers on the world map
	questsMinimap = true, -- and on the minimap
})

-- Data layout positions (tools/data/build.lua, as in Guide/Quests.lua).
local START_NPC, START_OBJ, END_NPC, END_OBJ, SPECIAL = 7, 8, 10, 11, 16

local readable = function(v) return ns.Compat.Readable(v) end

local function spawnsOf(kind, id)
	local D = Q.Data
	if kind == "n" then local n = D.npcs[id] return n and n[5], n and n[1] end
	local o = D.objects[id]
	return o and o[2], o and o[1]
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

-- Whether the quest log entry is tracked (ticked in the log): a function
-- (id, index) -> bool, or nil when the client has no way to say.
local function watchTest()
	local L = C_QuestLog
	if L and L.GetQuestWatchType then
		return function(id) return readable(L.GetQuestWatchType(id)) ~= nil end
	end
	if IsQuestWatched then
		return function(_, i) return readable(IsQuestWatched(i)) and true or false end
	end
	return nil
end

-- The quests in the log: { id, ... } (headers and hidden ones left out),
-- and { [id] = true } for the tracked ones (all of them when the client
-- cannot say which are tracked).
function M.LogQuests()
	local L = C_QuestLog
	local out, tracked = {}, {}
	if not (L and L.GetNumQuestLogEntries and L.GetInfo) then return out, tracked end
	local watched = watchTest()
	local n = readable(L.GetNumQuestLogEntries()) or 0
	for i = 1, n do
		local info = L.GetInfo(i)
		if type(info) == "table" and not readable(info.isHeader) and not readable(info.isHidden) then
			local id = readable(info.questID)
			if type(id) == "number" and id > 0 then
				out[#out + 1] = id
				if not watched or watched(id, i) then tracked[id] = true end
			end
		end
	end
	return out, tracked
end

-- The quests of the step shown (and the side guide's, and the extra quest
-- picked): { [id] = true } to take, { [id] = true } to work on or hand in.
function M.StepQuests()
	local take, work = {}, {}
	local E = ns.Engine
	if not E then return take, work end
	local goals = E.OpenGoals and E.OpenGoals() or {}
	local x = E.Extra and E.Extra()
	if x then goals[#goals + 1] = { x.verb, x.quest } end
	for _, goal in ipairs(goals) do
		local verb, id = goal[1], goal[2]
		if type(id) == "number" then
			if verb == "accept" then take[id] = true
			elseif verb == "turnin" or verb == "complete" then work[id] = true end
		end
	end
	return take, work
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
				out[#out + 1] = { map = map, x = pts[k], y = pts[k + 1], kind = kind, title = g.name, sub = sub }
			end
		end
	end
end

local function group(groups, entityKind, eid, line)
	local key = entityKind .. eid
	local g = groups[key]
	if not g then
		local spawns, name = spawnsOf(entityKind, eid)
		g = { spawns = spawns, name = name or "?", lines = {} }
		groups[key] = g
	end
	g.lines[#g.lines + 1] = line
end

-- { { map, x, y, kind, title, sub }, ... } for `map`: givers ("available"),
-- finishers ("turnin") and objective spots ("objective"), for the step's
-- quests and the tracked ones.
function M.ForMap(map)
	local out = {}
	if not map then return out end
	local p = Q.Player()
	local take, work = M.StepQuests()
	-- Givers of the quests the step says to take.
	local givers = {}
	local ids = {}
	for id in pairs(take) do ids[#ids + 1] = id end
	table.sort(ids)
	for _, id in ipairs(ids) do
		if M.Available(id, p) then
			local q = Q.Get(id)
			for _, n in ipairs(q[START_NPC] or {}) do group(givers, "n", n, levelText(id)) end
			for _, o in ipairs(q[START_OBJ] or {}) do group(givers, "o", o, levelText(id)) end
		end
	end
	atEntities(out, map, givers, "available", "Quests to take:")
	-- The log: the step's and the tracked quests, ready ones at their
	-- finisher, the others' objectives.
	local finishers = {}
	local log, tracked = M.LogQuests()
	for _, id in ipairs(log) do
		local q = Q.Get(id)
		if q and (work[id] or tracked[id]) then
			if Q.Ready(id) then
				for _, n in ipairs(q[END_NPC] or {}) do group(finishers, "n", n, Q.Name(id)) end
				for _, o in ipairs(q[END_OBJ] or {}) do group(finishers, "o", o, Q.Name(id)) end
			else
				local objs = Q.Objectives(id)
				for i = 1, Q.ObjectiveCount(id) do
					if not (objs and objs[i] and objs[i].done) then
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

-- Ticking a quest in the log or unticking it: the pins again.
ns.RegisterEvent("QUEST_WATCH_LIST_CHANGED", function() ns.Fire("PINS_CHANGED") end)
