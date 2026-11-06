-- The drops you see in game, kept per boss (account-wide): what fills in
-- the bosses QuestieDB's data knows little about, and the only source for
-- bosses it does not know at all. Only what the game shows you is kept.
--
-- Where a drop is read from (Forever 1.60, retail-style loot; all checked
-- against Blizzard's Forever UI source, Gethe/wow-ui-source `forever`):
--   * LOOT_HISTORY_UPDATE_DROP(encounterID, lootListKey), then
--     C_LootHistory.GetSortedInfoForDrop(...).itemHyperlink: the group's
--     loot rolls, by boss (Forever loads the game's encounter loot history)
--   * ENCOUNTER_LOOT_RECEIVED(encounterID, itemID, ...): loot a player got
--     from a boss
--   * LOOT_OPENED: the loot window's items (GetNumLootItems, GetLootSlotType,
--     GetLootSlotLink), from a boss's corpse when GetLootSourceInfo names the
--     monster, or from a chest opened just after a kill. GetLootSourceInfo is
--     not used by Forever's own UI; it is called only when the client has it
--     (UNVERIFIED on Forever).
--   * ENCOUNTER_START / ENCOUNTER_END (success) and the boss frames' units
--     (INSTANCE_ENCOUNTER_ENGAGE_UNIT, UnitGUID("boss1"..)) tie a boss to
--     its monsters and count kills.
-- Forever may hide any of these as secret values: every one passes
-- ns.Readable first, and a secret one is simply not recorded.
--
--   ns.LootLearn.Record(encounterId, itemId, key) -> true when counted

local ADDON, ns = ...
local L = ns.Loot
local D = ns.LootData
local Learn = {}
ns.LootLearn = Learn

local readable = ns.Readable
local CHEST_WINDOW = 120 -- seconds after a kill in which a chest's loot is that boss's

local function now() return (GetTime and GetTime()) or 0 end
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local r = { pcall(fn, ...) }
	if not r[1] then return nil end
	return unpack(r, 2, table.maxn(r))
end

-- "Creature-0-1465-0-2105-448-000043F59F" -> "Creature", 448
function Learn.ParseGUID(guid)
	guid = readable(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	return kind, tonumber(id)
end

local function itemOf(link)
	link = readable(link)
	if type(link) == "number" then return link end
	if type(link) ~= "string" then return nil end
	return tonumber(link:match("item:(%d+)"))
end

-- The monster -> boss index: the data's, then the ones seen in game.
local bossOf
local function bossIndex()
	if bossOf then return bossOf end
	bossOf = {}
	for eid, e in pairs(D.ENCOUNTERS) do
		for _, n in ipairs(e[4]) do bossOf[n] = bossOf[n] or eid end
	end
	for eid, s in pairs(L.Seen()) do
		if type(s) == "table" and type(s.npcs) == "table" then
			for n in pairs(s.npcs) do bossOf[n] = bossOf[n] or eid end
		end
	end
	return bossOf
end
function Learn.BossOf(npc) return bossIndex()[npc] end

-- The instance you are in: name, "party" | "raid", the client's map id.
local function instance()
	local name, kind, _, _, _, _, _, map = call(GetInstanceInfo)
	return readable(name), readable(kind), readable(map)
end

local function record(eid)
	local seen = L.Seen()
	local s = seen[eid]
	if type(s) ~= "table" then
		s = { items = {}, npcs = {}, kills = 0 }
		seen[eid] = s
		if not D.ENCOUNTERS[eid] then
			local name, kind, map = instance()
			s.instance, s.raid, s.map = name, kind == "raid" or nil, map
			L.Rebuild()
		end
	end
	s.items = type(s.items) == "table" and s.items or {}
	s.npcs = type(s.npcs) == "table" and s.npcs or {}
	return s
end

-- Each item counts once per kill (the loot history and the corpse show the
-- same drop); `key` names a drop seen outside a kill (a corpse's GUID).
local perKill = {} -- encounter id -> { [itemId] = true }
local counted = {} -- key -> true
function Learn.Record(eid, item, key)
	if not ns.Get("loot.learn") then return false end
	eid, item = readable(eid), readable(item)
	if type(eid) ~= "number" or type(item) ~= "number" or eid <= 0 or item <= 0 then return false end
	if key and counted[key] then return false end
	perKill[eid] = perKill[eid] or {}
	if perKill[eid][item] then return false end
	perKill[eid][item] = true
	if key then counted[key] = true end
	local s = record(eid)
	s.items[item] = (tonumber(s.items[item]) or 0) + 1
	ns.Fire("LOOT_SEEN", eid, item)
	return true
end

---------------------------------------------------------------------------
-- Fights
---------------------------------------------------------------------------

local fight -- { id, name } while a boss fight is on
local lastKill -- { id, at, map }

local function bossUnits()
	if not (fight and ns.Get("loot.learn")) then return end
	for i = 1, 5 do
		local unit = "boss" .. i
		if readable(call(UnitExists, unit)) then
			local kind, npc = Learn.ParseGUID(call(UnitGUID, unit))
			if kind == "Creature" and npc then
				local s = record(fight.id)
				if not s.npcs[npc] then
					s.npcs[npc] = true
					bossOf = nil
				end
			end
		end
	end
end

ns.RegisterEvent("ENCOUNTER_START", function(_, id, name)
	id, name = readable(id), readable(name)
	if type(id) ~= "number" then return end
	fight = { id = id, name = name }
	bossUnits()
end)
ns.RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT", bossUnits)
ns.RegisterEvent("ENCOUNTER_END", function(_, id, name, _, _, success)
	id, name, success = readable(id), readable(name), readable(success)
	if type(id) ~= "number" then return end
	bossUnits()
	fight = nil
	if success ~= 1 then return end
	local _, _, map = instance()
	lastKill = { id = id, at = now(), map = map }
	perKill[id] = {}
	if ns.Get("loot.learn") then
		local s = record(id)
		s.kills = (tonumber(s.kills) or 0) + 1
		if type(name) == "string" and not D.ENCOUNTERS[id] then s.name = name end
		ns.Fire("LOOT_SEEN", id, nil)
	end
end)

---------------------------------------------------------------------------
-- Drops
---------------------------------------------------------------------------

ns.RegisterEvent("LOOT_HISTORY_UPDATE_DROP", function(_, eid, key)
	eid, key = readable(eid), readable(key)
	if type(eid) ~= "number" or key == nil or not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then return end
	local info = call(C_LootHistory.GetSortedInfoForDrop, eid, key)
	if type(info) ~= "table" then return end
	local item = itemOf(info.itemHyperlink)
	-- No key: the history's keys may start again with the next kill; one
	-- kill counts an item once anyway.
	if item then Learn.Record(eid, item) end
end)

ns.RegisterEvent("ENCOUNTER_LOOT_RECEIVED", function(_, eid, item)
	Learn.Record(readable(eid), readable(item))
end)

ns.RegisterEvent("LOOT_OPENED", function()
	if not ns.Get("loot.learn") then return end
	local n = readable(call(GetNumLootItems)) or 0
	local itemType = Enum and Enum.LootSlotType and Enum.LootSlotType.Item
	for slot = 1, n do
		local kind = readable(call(GetLootSlotType, slot))
		if itemType == nil or kind == itemType then
			local item = itemOf(call(GetLootSlotLink, slot))
			if item then
				local guid = readable(call(GetLootSourceInfo, slot))
				local what, id = Learn.ParseGUID(guid)
				if what == "Creature" and id and Learn.BossOf(id) then
					Learn.Record(Learn.BossOf(id), item, guid .. ":" .. item)
				elseif what == "GameObject" and lastKill and now() - lastKill.at <= CHEST_WINDOW then
					local _, _, map = instance()
					if map == nil or lastKill.map == nil or map == lastKill.map then
						Learn.Record(lastKill.id, item, guid .. ":" .. item)
					end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Items the client finished loading
---------------------------------------------------------------------------

local pending = false
local function itemsChanged()
	if pending then return end
	pending = true
	local function fire() pending = false ns.Fire("ITEMS_CHANGED") end
	if C_Timer and C_Timer.After then C_Timer.After(0.2, fire) else fire() end
end
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", itemsChanged)
ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", itemsChanged)

-- Tests: forget the fight and kill state.
function Learn.Reset() fight, lastKill, perKill, counted, bossOf = nil, nil, {}, {}, nil end
