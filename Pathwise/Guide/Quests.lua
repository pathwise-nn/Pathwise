-- Pathwise quest facts: reads Data/Data.lua (built from QuestieDB) and the
-- live quest log. Everything about a quest the guide shows or decides goes
-- through here.
--
-- Quest log APIs used (present on Forever: C_QuestLog in Blizzard's Forever UI
-- source; Polestar calls the same ones on Forever):
--   C_QuestLog.IsQuestFlaggedCompleted, IsOnQuest, ReadyForTurnIn, IsComplete,
--   GetQuestObjectives, GetTitleForQuestID.

local ADDON, ns = ...
local Q = {}
ns.Quests = Q

local floor = math.floor
local D = ns.Data or { quests = {}, npcs = {}, objects = {}, items = {}, zones = {} }
Q.Data = D

-- Data layout positions (tools/data/build.lua).
local NAME, LEVEL, MINLEVEL, RACES, CLASSES, MAP = 1, 2, 3, 4, 5, 6
local START_NPC, START_OBJ, START_ITEM, END_NPC, END_OBJ, OBJECTIVES = 7, 8, 9, 10, 11, 12
local PRE_SINGLE, PRE_GROUP, EXCLUSIVE, SPECIAL, BREADCRUMB_FOR, NEXT_IN_CHAIN, TEXT = 13, 14, 15, 16, 17, 18, 19

-- Class bits (QuestieDB classKeys, Classic) by the client's class file name.
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
-- Race bits by the client's race ID (QuestieDB raceMaskById; Forever's
-- Skyborne races 95/96 use bits 32/33).
local RACE_BIT = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [9] = 256, [95] = 4294967296, [96] = 8589934592 }
Q.CLASS_BIT, Q.RACE_BIT = CLASS_BIT, RACE_BIT

-- Bit test without the bit library (masks go past 32 bits on Forever).
local function hasBit(mask, bit)
	return floor(mask / bit) % 2 == 1
end
Q.HasBit = hasBit

function Q.Get(id) return D.quests[id] end
function Q.Name(id)
	local q = D.quests[id]
	local live = C_QuestLog and C_QuestLog.GetTitleForQuestID and ns.Compat.Readable(C_QuestLog.GetTitleForQuestID(id))
	return live or (q and q[NAME]) or ("Quest " .. tostring(id))
end
function Q.Level(id) local q = D.quests[id] return q and q[LEVEL] or 0 end
function Q.MinLevel(id) local q = D.quests[id] return q and q[MINLEVEL] or 0 end
function Q.Map(id) local q = D.quests[id] return q and q[MAP] end
function Q.Text(id) local q = D.quests[id] return q and q[TEXT] end
function Q.Special(id) local q = D.quests[id] return q and q[SPECIAL] end

-- The player as the guide needs them: { level, class, raceID, faction }.
function Q.Player()
	local R = ns.Compat.Readable
	local _, class = UnitClass("player")
	local _, raceFile, raceID = UnitRace("player")
	return {
		level = R(UnitLevel("player")) or 1,
		class = R(class),
		raceID = R(raceID),
		race = R(raceFile),
		faction = R(UnitFactionGroup and UnitFactionGroup("player")),
	}
end

-- Whether this character may ever take quest `id` (race and class only).
function Q.ForPlayer(id, p)
	local q = D.quests[id]
	if not q then return true end -- unknown to the data: trust the route
	p = p or Q.Player()
	local races, classes = q[RACES] or 0, q[CLASSES] or 0
	if races ~= 0 and p.raceID and RACE_BIT[p.raceID] and not hasBit(races, RACE_BIT[p.raceID]) then return false end
	if classes ~= 0 and p.class and CLASS_BIT[p.class] and not hasBit(classes, CLASS_BIT[p.class]) then return false end
	return true
end

---------------------------------------------------------------------------
-- The live quest log
---------------------------------------------------------------------------

local turnedIn = {} -- this session; the completed flag can lag QUEST_TURNED_IN

function Q.Done(id)
	if turnedIn[id] then return true end
	local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	return f and ns.Compat.Readable(f(id)) and true or false
end

function Q.OnQuest(id)
	local f = C_QuestLog and C_QuestLog.IsOnQuest
	return f and ns.Compat.Readable(f(id)) and true or false
end

function Q.Ready(id)
	local L = C_QuestLog
	if not L then return false end
	local R = ns.Compat.Readable
	if L.ReadyForTurnIn and R(L.ReadyForTurnIn(id)) then return true end
	return L.IsComplete and R(L.IsComplete(id)) and true or false
end

-- { { text, have, need, done }, ... } from the quest log, or nil.
function Q.Objectives(id)
	local f = C_QuestLog and C_QuestLog.GetQuestObjectives
	local list = f and f(id)
	if type(list) ~= "table" or #list == 0 then return nil end
	local out = {}
	for i, o in ipairs(list) do
		local R = ns.Compat.Readable
		local text = R(o.text) or ""
		-- The log writes "Mindless Zombie slain: 5/8"; the window shows the count apart.
		text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", ""):gsub(" slain$", "")
		out[i] = { text = text, have = R(o.numFulfilled), need = R(o.numRequired), done = R(o.finished) and true or false }
	end
	return out
end

-- Prerequisites the data knows of are met: one of preSingle, all of preGroup.
function Q.PrereqsMet(id)
	local q = D.quests[id]
	if not q then return true end
	local single, group = q[PRE_SINGLE], q[PRE_GROUP]
	if group then for _, p in ipairs(group) do if not Q.Done(p) then return false end end end
	if single and #single > 0 then
		for _, p in ipairs(single) do if Q.Done(p) then return true end end
		return false
	end
	return true
end

-- Closed for good: an exclusive quest is taken or done.
function Q.Closed(id)
	local q = D.quests[id]
	if not (q and q[EXCLUSIVE]) then return false end
	for _, x in ipairs(q[EXCLUSIVE]) do if Q.Done(x) or Q.OnQuest(x) then return true end end
	return false
end

-- Quests that need `id` first, as far as the data knows.
function Q.FollowUps(id)
	local out = {}
	for qid, q in pairs(D.quests) do
		for _, list in ipairs({ q[PRE_SINGLE] or {}, q[PRE_GROUP] or {} }) do
			for _, p in ipairs(list) do if p == id then out[#out + 1] = qid end end
		end
	end
	table.sort(out)
	return out
end

ns.RegisterEvent("QUEST_TURNED_IN", function(_, id) if id then turnedIn[id] = true end end)

---------------------------------------------------------------------------
-- Places: givers, finishers, objective targets
---------------------------------------------------------------------------

-- The nearest point of an entity's spawns: map, x, y, name. `from` is the
-- player's map position { map, x, y }; points on the player's map win, then
-- the quest's map, then any.
local function nearest(spawns, from, prefer)
	if type(spawns) ~= "table" then return nil end
	local best, bestD, bestMap
	local function scan(map, pts)
		for i = 1, #pts, 2 do
			local d
			if from and from.map == map then
				local dx, dy = pts[i] - from.x, pts[i + 1] - from.y
				d = dx * dx + dy * dy
			else
				d = 1e9 + i
			end
			if not bestD or d < bestD then best, bestD, bestMap = i, d, map end
		end
	end
	if from and spawns[from.map] then scan(from.map, spawns[from.map])
	elseif prefer and spawns[prefer] then scan(prefer, spawns[prefer])
	else for map, pts in pairs(spawns) do scan(map, pts) break end end
	if not best then return nil end
	local pts = spawns[bestMap]
	return bestMap, pts[best], pts[best + 1]
end
Q.Nearest = nearest

local function npcPlace(id, from, prefer)
	local n = D.npcs[id]
	if not n then return nil end
	local map, x, y = nearest(n[5], from, prefer)
	if not map then return nil end
	return { map = map, x = x, y = y, name = n[1], npc = id }
end

local function objectPlace(id, from, prefer)
	local o = D.objects[id]
	if not o then return nil end
	local map, x, y = nearest(o[2], from, prefer)
	if not map then return nil end
	return { map = map, x = x, y = y, name = o[1], object = id }
end

local function firstPlace(npcIds, objIds, from, prefer)
	for _, n in ipairs(npcIds or {}) do local p = npcPlace(n, from, prefer) if p then return p end end
	for _, o in ipairs(objIds or {}) do local p = objectPlace(o, from, prefer) if p then return p end end
	return nil
end

function Q.Giver(id, from)
	local q = D.quests[id]
	if not q then return nil end
	return firstPlace(q[START_NPC], q[START_OBJ], from, q[MAP])
end

function Q.Finisher(id, from)
	local q = D.quests[id]
	if not q then return nil end
	return firstPlace(q[END_NPC], q[END_OBJ], from, q[MAP])
end

-- Where to go for objective `i` (1-based, data order) of quest `id`.
function Q.ObjectivePlace(id, i, from)
	local q = D.quests[id]
	local o = q and q[OBJECTIVES] and q[OBJECTIVES][i]
	if not o then return nil end
	local kind, oid = o[1], o[2]
	local p
	if kind == "m" then p = npcPlace(oid, from, q[MAP])
	elseif kind == "k" then p = firstPlace(o[4], nil, from, q[MAP])
	elseif kind == "o" then p = objectPlace(oid, from, q[MAP])
	elseif kind == "i" then
		local it = D.items[oid]
		if it then p = firstPlace(it[2], it[3], from, q[MAP]) end
		if p then p.item = it[1] end
	end
	return p
end

-- Every spot of objective `i` (1-based) on `map`: { x, y, x, y, ... } and the
-- name, for pins (up to 12 per map; the data keeps no more).
function Q.ObjectiveSpots(id, i, map)
	local q = D.quests[id]
	local o = q and q[OBJECTIVES] and q[OBJECTIVES][i]
	if not o then return nil end
	local kind, oid = o[1], o[2]
	local entity, name
	if kind == "m" then entity = D.npcs[oid] and { D.npcs[oid][5], D.npcs[oid][1] }
	elseif kind == "k" and o[4] then entity = D.npcs[o[4][1]] and { D.npcs[o[4][1]][5], o[3] or D.npcs[o[4][1]][1] }
	elseif kind == "o" then entity = D.objects[oid] and { D.objects[oid][2], D.objects[oid][1] }
	elseif kind == "i" then
		local it = D.items[oid]
		local n = it and it[2] and D.npcs[it[2][1]]
		local ob = it and it[3] and D.objects[it[3][1]]
		if n then entity = { n[5], n[1] } elseif ob then entity = { ob[2], ob[1] } end
		name = it and it[1]
	end
	if not (entity and type(entity[1]) == "table" and entity[1][map]) then return nil end
	return entity[1][map], name and (entity[2] .. " (" .. name .. ")") or entity[2]
end

function Q.ObjectiveCount(id)
	local q = D.quests[id]
	return q and q[OBJECTIVES] and #q[OBJECTIVES] or 0
end

---------------------------------------------------------------------------
-- Zones by level (Data's estimate from quest levels)
---------------------------------------------------------------------------

-- { { map, low, high, quests }, ... } for the player's side, levels around `level`.
function Q.ZonesFor(level, faction)
	local side = faction == "Alliance" and "alliance" or "horde"
	local out = {}
	for map, z in pairs(D.zones or {}) do
		local r = z[side]
		if r and level >= r[1] - 2 and level <= r[2] + 1 then
			out[#out + 1] = { map = map, low = r[1], high = r[2], quests = r[3] }
		end
	end
	table.sort(out, function(a, b)
		if a.low ~= b.low then return a.low < b.low end
		return a.map < b.map
	end)
	return out
end
