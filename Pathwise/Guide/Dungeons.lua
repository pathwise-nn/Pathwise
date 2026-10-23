-- Pathwise dungeons: dungeons and raids for the character's level, their
-- quests and their entrances, from Data/Data.lua (built from QuestieDB:
-- tools/data/build.lua, "Dungeons and raids").
--
--   Dungeons.All()                 every instance, by level
--   Dungeons.ForLevel(level)       those that suit a level
--   Dungeons.Quests(id)            its quests for this character, with status
--   Dungeons.Entrance(id)          the nearest entrance: { map, x, y, unverified }
--   Dungeons.GuideTo(id)           the arrow to that entrance
--
-- Level ranges are the levels of the monsters inside (or, for the instances
-- Forever added, of their quests): estimates from the data, said so where shown.

local ADDON, ns = ...
local Q, C = ns.Quests, ns.Compat
local Dg = {}
ns.Dungeons = Dg
Pathwise.Dungeons = Dg

local function data() return Q.Data.dungeons or {} end

local list
function Dg.All()
	if list then return list end
	list = {}
	for id, d in pairs(data()) do
		list[#list + 1] = {
			id = id, name = d.name, low = d.levels[1], high = d.levels[2], raid = d.raid,
			levelsFrom = d.levelsFrom, entrances = d.entrances or {}, quests = d.quests or {},
		}
	end
	table.sort(list, function(a, b)
		if a.low ~= b.low then return a.low < b.low end
		return a.name < b.name
	end)
	return list
end

function Dg.Get(id)
	for _, d in ipairs(Dg.All()) do if d.id == id then return d end end
end

-- Instances that suit a level: from three below their range to two above it.
function Dg.ForLevel(level)
	local out = {}
	for _, d in ipairs(Dg.All()) do
		if level >= d.low - 3 and level <= d.high + 2 then out[#out + 1] = d end
	end
	return out
end

-- The giver's side: "A", "H", "AH" or nil (anyone).
local function giverSide(q)
	local quest = Q.Get(q)
	local npc = quest and quest[7] and Q.Data.npcs[quest[7][1]]
	return npc and npc[4]
end

local SIDE = { Horde = "H", Alliance = "A" }

-- The quests of an instance for this character, each with what stands:
--   "done", "log" (in the quest log), "ready" (ready to hand in),
--   "now" (can be taken now), "level" (needs a higher level),
--   "pre" (needs another quest first)
-- -> { { quest, name, level, minLevel, status, giver }, ... }, by level.
function Dg.Quests(id)
	local d = Dg.Get(id)
	local out = {}
	if not d then return out end
	local p = Q.Player()
	local side = SIDE[p.faction]
	for _, q in ipairs(d.quests) do
		local gs = giverSide(q)
		local sideOk = not gs or gs == "AH" or not side or gs == side
		if sideOk and Q.ForPlayer(q, p) and not Q.Special(q) and not Q.Closed(q) then
			local status
			if Q.Done(q) then status = "done"
			elseif Q.OnQuest(q) then status = Q.Ready(q) and "ready" or "log"
			elseif Q.MinLevel(q) > (p.level or 1) then status = "level"
			elseif not Q.PrereqsMet(q) then status = "pre"
			else status = "now" end
			local giver = Q.Giver(q)
			out[#out + 1] = { quest = q, name = Q.Name(q), level = Q.Level(q), minLevel = Q.MinLevel(q),
				status = status, giver = giver }
		end
	end
	table.sort(out, function(a, b)
		if a.level ~= b.level then return a.level < b.level end
		return a.quest < b.quest
	end)
	return out
end

-- The entrance nearest the player (same continent first), verified ones
-- before unverified ones when as near.
function Dg.Entrance(id)
	local d = Dg.Get(id)
	if not d or #d.entrances == 0 then return nil end
	local map, x, y = C.PlayerMapPosition()
	local best, bestD
	for _, e in ipairs(d.entrances) do
		local dist = 1e12
		if map then
			local i1, n1, w1 = C.MapToWorld(map, x, y)
			local i2, n2, w2 = C.MapToWorld(e[1], e[2], e[3])
			if i1 and i2 and i1 == i2 then dist = (n2 - n1) ^ 2 + (w2 - w1) ^ 2 end
		end
		if e[4] then dist = dist + 1 end
		if not bestD or dist < bestD then best, bestD = e, dist end
	end
	return { map = best[1], x = best[2], y = best[3], unverified = best[4] }
end

function Dg.GuideTo(id)
	local d, e = Dg.Get(id), Dg.Entrance(id)
	if not (d and e) then return false end
	ns.Nav.SetTarget(e.map, e.x, e.y, d.name)
	return true
end

-- Quests of the instances for a level that can be taken now, for the
-- guide's "Dungeons" count.
function Dg.OpenQuestCount(level)
	local n = 0
	for _, d in ipairs(Dg.ForLevel(level)) do
		for _, q in ipairs(Dg.Quests(d.id)) do if q.status == "now" then n = n + 1 end end
	end
	return n
end
