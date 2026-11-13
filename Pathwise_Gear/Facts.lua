-- Best in Slot (Level)'s facts without Pathwise: its own copy of what it
-- needs from Pathwise's data (Data/Gear.lua, npm run gear:data), and the few
-- questions Pathwise would answer, in Pathwise's own words (Guide/Quests.lua,
-- Guide/Dungeons.lua) so Best.lua reads them the same way. With Pathwise
-- installed, Base.lua gives Pathwise's instead.
--
--   ns.Facts.Data          gear, quests, npcs, objects, items, dungeons
--   ns.Facts.Quests        Get, Name, Player, ForPlayer, Done, Closed, Giver, Nearest
--   ns.Facts.Dungeons      Get, GuideTo
--   ns.Facts.Professions   Known, BY_LINE, Recipes (unknown without Pathwise: nil)
--   ns.Facts.SetWaypoint(map, x, y, title)   the game's own map pin (x, y 0-100)
--
-- Client APIs (Blizzard's Forever UI source, Gethe/wow-ui-source `forever`):
-- C_QuestLog.IsQuestFlaggedCompleted, IsOnQuest, GetTitleForQuestID;
-- C_Map.CanSetUserWaypointOnMap, SetUserWaypoint and
-- C_SuperTrack.SetSuperTrackedUserWaypoint with UiMapPoint.CreateFromCoordinates
-- (0-1 coordinates), as Blizzard_SharedMapDataProviders/
-- WaypointLocationDataProvider.lua sets a pin. Not yet checked in game.

local ADDON, ns = ...
local D = ns.GearData or { gear = {}, quests = {}, npcs = {}, objects = {}, items = {}, dungeons = {} }
local F = { Data = D }
ns.Facts = F
local readable = ns.Readable
local floor = math.floor

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

local NAME, RACES, CLASSES, MAP, START_NPC, START_OBJ, EXCLUSIVE = 1, 4, 5, 6, 7, 8, 15
-- As Pathwise reads QuestieDB's masks (Guide/Quests.lua).
local CLASS_BIT = { WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024 }
local RACE_BIT = { [1] = 1, [2] = 2, [3] = 4, [4] = 8, [5] = 16, [6] = 32, [7] = 64, [8] = 128, [9] = 256, [95] = 4294967296, [96] = 8589934592 }
local function hasBit(mask, bit) return floor(mask / bit) % 2 == 1 end

local Q = {}
F.Quests = Q

function Q.Get(id) return D.quests[id] end

function Q.Name(id)
	local q = D.quests[id]
	local live = C_QuestLog and C_QuestLog.GetTitleForQuestID and readable(C_QuestLog.GetTitleForQuestID(id))
	return live or (q and q[NAME]) or ("Quest " .. tostring(id))
end

function Q.Player()
	local _, class = UnitClass("player")
	local _, raceFile, raceID = UnitRace("player")
	return {
		level = readable(UnitLevel("player")) or 1,
		class = readable(class), raceID = readable(raceID), race = readable(raceFile),
		faction = readable(UnitFactionGroup and UnitFactionGroup("player")),
	}
end

function Q.ForPlayer(id, p)
	local q = D.quests[id]
	if not q then return true end
	p = p or Q.Player()
	local races, classes = q[RACES] or 0, q[CLASSES] or 0
	if races ~= 0 and p.raceID and RACE_BIT[p.raceID] and not hasBit(races, RACE_BIT[p.raceID]) then return false end
	if classes ~= 0 and p.class and CLASS_BIT[p.class] and not hasBit(classes, CLASS_BIT[p.class]) then return false end
	return true
end

local turnedIn = {} -- this session; the completed flag can lag QUEST_TURNED_IN
function Q.Done(id)
	if turnedIn[id] then return true end
	local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
	return f and readable(f(id)) and true or false
end
ns.RegisterEvent("QUEST_TURNED_IN", function(_, id) if id then turnedIn[id] = true end end)

local function onQuest(id)
	local f = C_QuestLog and C_QuestLog.IsOnQuest
	return f and readable(f(id)) and true or false
end

-- Closed for good: an exclusive quest is taken or done.
function Q.Closed(id)
	local q = D.quests[id]
	if not (q and q[EXCLUSIVE]) then return false end
	for _, x in ipairs(q[EXCLUSIVE]) do if Q.Done(x) or onQuest(x) then return true end end
	return false
end

-- The nearest point of spawns { [map] = { x, y, ... } }: the player's map
-- first, then `prefer`, then any. -> map, x, y
function Q.Nearest(spawns, from, prefer)
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
	else
		local maps = {}
		for map in pairs(spawns) do maps[#maps + 1] = map end
		table.sort(maps)
		if maps[1] then scan(maps[1], spawns[maps[1]]) end
	end
	if not best then return nil end
	local pts = spawns[bestMap]
	return bestMap, pts[best], pts[best + 1]
end

function Q.Giver(id, from)
	local q = D.quests[id]
	if not q then return nil end
	for _, n in ipairs(q[START_NPC] or {}) do
		local npc = D.npcs[n]
		if npc then
			local map, x, y = Q.Nearest(npc[5], from, q[MAP])
			if map then return { map = map, x = x, y = y, name = npc[1], npc = n } end
		end
	end
	for _, o in ipairs(q[START_OBJ] or {}) do
		local obj = D.objects[o]
		if obj then
			local map, x, y = Q.Nearest(obj[2], from, q[MAP])
			if map then return { map = map, x = x, y = y, name = obj[1], object = o } end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- The game's own map pin, for Pathwise's arrow
---------------------------------------------------------------------------

function F.SetWaypoint(map, x, y, title)
	local M, S = C_Map, C_SuperTrack
	if not (map and x and y and M and M.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then return false end
	if M.CanSetUserWaypointOnMap then
		local ok, can = pcall(M.CanSetUserWaypointOnMap, map)
		if not ok or readable(can) == false then return false end
	end
	local ok, set = pcall(M.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
	if not ok or readable(set) == false then return false end
	if S and S.SetSuperTrackedUserWaypoint then pcall(S.SetSuperTrackedUserWaypoint, true) end
	return true
end

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------

local Dg = {}
F.Dungeons = Dg

function Dg.Get(id)
	local d = D.dungeons[id]
	if not d then return nil end
	return { id = id, name = d.name, raid = d.raid, low = d.levels and d.levels[1], high = d.levels and d.levels[2], entrances = d.entrances or {} }
end

-- To the entrance: on the player's map if one is, else the first.
function Dg.GuideTo(id)
	local d = Dg.Get(id)
	if not (d and d.entrances[1]) then return false end
	local here = ns.S.Compat.PlayerMapPosition()
	local e = d.entrances[1]
	for _, x in ipairs(d.entrances) do if here and x[1] == here and not x[4] then e = x break end end
	return F.SetWaypoint(e[1], e[2], e[3], d.name)
end

---------------------------------------------------------------------------
-- Professions: the game's skill lines (as Pathwise Insights reads them)
---------------------------------------------------------------------------

local P = { LIST = {
	{ line = 171, name = "Alchemy" }, { line = 164, name = "Blacksmithing" }, { line = 333, name = "Enchanting" },
	{ line = 202, name = "Engineering" }, { line = 165, name = "Leatherworking" }, { line = 197, name = "Tailoring" },
	{ line = 182, name = "Herbalism" }, { line = 186, name = "Mining" }, { line = 393, name = "Skinning" },
	{ line = 185, name = "Cooking" }, { line = 129, name = "First Aid" }, { line = 356, name = "Fishing" },
}, BY_LINE = {} }
F.Professions = P
for _, p in ipairs(P.LIST) do P.BY_LINE[p.line] = p end

local function rank(line)
	local C = C_SkillInfo
	if C and C.GetSkillLineInfoByID then
		local ok, info = pcall(C.GetSkillLineInfoByID, line)
		if ok and type(info) == "table" and not info.isHeader then
			local r, cap = tonumber(readable(info.rank)) or 0, tonumber(readable(info.maxRank)) or 0
			if r > 0 or cap > 0 then return r end
		end
	end
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			if list[i] then
				local _, _, r, _, _, _, skillLine = GetProfessionInfo(list[i])
				if readable(skillLine) == line then return readable(r) or 0 end
			end
		end
	end
	return nil
end

-- { { prof = { line, name }, rank }, ... }
function P.Known()
	local out = {}
	for _, p in ipairs(P.LIST) do
		local r = rank(p.line)
		if r then out[#out + 1] = { prof = p, rank = r } end
	end
	return out
end
-- Which recipes you know: Pathwise reads the profession window; without it, unknown.
function P.Recipes() return nil end
