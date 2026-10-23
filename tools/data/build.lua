-- Builds Pathwise/Data/Data.lua from QuestieDB's Forever sources.
--
--   lua5.1 tools/data/build.lua [questiedb-dir] [output-file]
--   (defaults: data/sources/questiedb, Pathwise/Data/Data.lua; run from the repo root)
--
-- What it does, in QuestieDB's own order (src/config.lua ownedCorrections):
--   1. loads the schemas (src/meta) and constants (src/corrections/enum);
--   2. loads the four Forever entity files (data/Forever/*.lua);
--   3. applies every Forever Static Correction, replacement fields and the
--      _add/_remove operations (src/corrections/tablePatch.lua's rules);
--   4. maps Questie's AreaTable zone ids to the game's UiMap ids
--      (support/Forever/Zones/areaIdToUiMapId.lua, overrides first);
--   5. writes only what Pathwise reads, as plain Lua tables.
-- Not applied: Dynamic Corrections (LoadFactionFixes, LoadDynamic), which
-- QuestieDB runs in the game per character. Documented in docs/DATA.md.
--
-- Every QuestieDB file is run in a sandbox: an environment holding only pure
-- functions (no io, os, require, load, dofile, debug), so a data file can do
-- nothing but build tables.

local SRC = arg[1] or "data/sources/questiedb"
local OUT = arg[2] or "Pathwise/Data/Data.lua"

local function log(...) io.stderr:write(table.concat({ ... }, " "), "\n") end

---------------------------------------------------------------------------
-- Sandbox
---------------------------------------------------------------------------

local SAFE = {
	pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber,
	select = select, unpack = unpack, error = error, assert = assert, pcall = pcall,
	setmetatable = setmetatable, getmetatable = getmetatable, rawget = rawget, rawset = rawset, rawequal = rawequal,
	string = { format = string.format, sub = string.sub, gsub = string.gsub, find = string.find, match = string.match,
		gmatch = string.gmatch, lower = string.lower, upper = string.upper, len = string.len, rep = string.rep,
		byte = string.byte, char = string.char, reverse = string.reverse },
	table = { insert = table.insert, remove = table.remove, concat = table.concat, sort = table.sort },
	math = { floor = math.floor, ceil = math.ceil, max = math.max, min = math.min, abs = math.abs,
		huge = math.huge, sqrt = math.sqrt, fmod = math.fmod, pi = math.pi },
}

local function env(extra)
	local e = {}
	for k, v in pairs(SAFE) do e[k] = v end
	for k, v in pairs(extra or {}) do e[k] = v end
	e._G = e
	return e
end

local function readFile(path)
	local f = assert(io.open(SRC .. "/" .. path, "rb"), "missing " .. SRC .. "/" .. path)
	local text = f:read("*a")
	f:close()
	return text
end

-- Runs a QuestieDB file in a sandbox `e`, passing `...` = (name, namespace).
local function run(path, e, ...)
	local chunk, err = loadstring(readFile(path), "@" .. path)
	if not chunk then error(err, 0) end
	setfenv(chunk, e)
	return chunk(...)
end

-- A string holding `return { ... }` (QuestieDB's deferred tables).
local function runString(text, name, e)
	local chunk, err = loadstring(text, "=" .. name)
	if not chunk then error(err, 0) end
	setfenv(chunk, e or env())
	return chunk()
end

---------------------------------------------------------------------------
-- Schemas and constants
---------------------------------------------------------------------------

local Lib = { Meta = {}, Enum = nil }
local ENTITIES = {
	{ name = "Quest", keysField = "questKeys", dataField = "questData", meta = "questMeta", file = "foreverQuestDB" },
	{ name = "Npc", keysField = "npcKeys", dataField = "npcData", meta = "npcMeta", file = "foreverNpcDB" },
	{ name = "Item", keysField = "itemKeys", dataField = "itemData", meta = "itemMeta", file = "foreverItemDB" },
	{ name = "Object", keysField = "objectKeys", dataField = "objectData", meta = "objectMeta", file = "foreverObjectDB" },
}
local metaOf = {}
for _, t in ipairs(ENTITIES) do
	metaOf[t.name] = run("src/meta/" .. t.meta .. ".lua", env(), "QuestieDB", Lib)
end

for _, f in ipairs({ "constants", "items", "quests", "professions", "factions", "zones", "phases", "icons", "waypoints", "expansions" }) do
	run("src/corrections/enum/" .. f .. ".lua", env(), "QuestieDB", Lib)
end
local C = assert(Lib.Enum, "constants did not load")

-- Forever reads its own tables first, then Classic's (config: rules = "Classic").
local function pick(name)
	if name ~= "classKeys" and name ~= "npcFlags" and C[name] ~= nil then return C[name] end
	local v = C.byExpansion.Forever[name]
	if v == nil then v = C.byExpansion.Classic[name] end
	return v
end

-- Field keys with the operation aliases: name_add = i + 1000, name_remove = i - 1000.
local keys = {}
for _, t in ipairs(ENTITIES) do
	local k = {}
	for name, i in pairs(metaOf[t.name].keys) do
		k[name], k[name .. "_add"], k[name .. "_remove"] = i, i + 1000, i - 1000
	end
	keys[t.name] = k
end

---------------------------------------------------------------------------
-- Entity data
---------------------------------------------------------------------------

local captured = { Quest = {}, Npc = {}, Item = {}, Object = {} }
local QuestieDB = {
	questKeys = keys.Quest, npcKeys = keys.Npc, itemKeys = keys.Item, objectKeys = keys.Object,
	raceKeys = pick("raceKeys"), classKeys = pick("classKeys"), sortKeys = pick("sortKeys"),
	specialFlags = pick("specialFlags"), factionIDs = pick("factionIDs"), questFlags = pick("questFlags"),
	npcFlags = pick("npcFlags"), itemClasses = pick("itemClasses"), waypointPresets = pick("waypointPresets"),
	questData = captured.Quest, npcData = captured.Npc, itemData = captured.Item, objectData = captured.Object,
}
local hints = { killCreditObjectiveFirst = {}, objectObjectiveFirst = {}, itemObjectiveFirst = {}, eventObjectiveFirst = {}, spellObjectiveFirst = {} }
local modules = {
	QuestieDB = QuestieDB,
	ZoneDB = { zoneIDs = pick("zoneIDs"), private = {} },
	QuestieProfessions = { professionKeys = pick("professionKeys"), specializationKeys = pick("specializationKeys"), rankNames = pick("rankNames") },
	QuestieCorrections = hints,
	Phasing = { phases = pick("phases") },
	l10n = setmetatable({}, { __call = function(_, text) return text end }),
	Expansions = { Era = 1, Classic = 1, Tbc = 2, Wotlk = 3, Cata = 4, MoP = 5, Current = 1 },
}
local Loader = {
	ImportModule = function(_, name) modules[name] = modules[name] or {} return modules[name] end,
	CreateModule = function(_, name) modules[name] = modules[name] or {} return modules[name] end,
}
local questie = {}
for k, v in pairs(C.iconTypes or {}) do questie[k] = v end
local function questieEnv() return env({ QuestieLoader = Loader, Questie = questie }) end

local db = {}
for _, t in ipairs(ENTITIES) do
	-- The file sets QuestieDB[<keysField>] (ignored: the schema is authoritative)
	-- and QuestieDB[<dataField>] = "return { ... }".
	local holder = { questKeys = {}, npcKeys = {}, itemKeys = {}, objectKeys = {} }
	local e = env({ QuestieLoader = { ImportModule = function() return holder end, CreateModule = function() return holder end } })
	run("data/Forever/" .. t.file .. ".lua", e)
	local text = holder[t.dataField]
	assert(type(text) == "string", t.file .. ": no " .. t.dataField)
	db[t.name] = runString(text, t.file)
	local n = 0
	for _ in pairs(db[t.name]) do n = n + 1 end
	log(("loaded %d %s rows"):format(n, t.name))
end

---------------------------------------------------------------------------
-- Static Corrections
---------------------------------------------------------------------------

local OFFSET = 1000
local grouped = { questgivers = true, objectives = true, spawnlist = true, waypointlist = true }
local atomic = { pair = true, trigger = true }

local function copy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, c in pairs(v) do o[k] = copy(c) end
	return o
end

local function equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

local function contains(list, v)
	for _, x in ipairs(list or {}) do if equal(x, v) then return true end end
	return false
end

-- One list (or atomic value) with additions and removals applied.
local function patchList(current, add, remove, isAtomic)
	if isAtomic then
		if remove and next(remove) and equal(current, remove) then current = nil end
		if add and next(add) then current = copy(add) end
		return current
	end
	local kept = {}
	for _, v in ipairs(current or {}) do if not contains(remove, v) then kept[#kept + 1] = v end end
	for _, v in ipairs(add or {}) do if not contains(kept, v) then kept[#kept + 1] = copy(v) end end
	return next(kept) and kept or nil
end

-- A spawn list's groups are keyed by zone, a giver list's by position.
local function patchField(meta, field, existing, add, remove)
	local shape = meta.structures[field]
	if grouped[shape] then
		local out = copy(existing or {})
		local touched = {}
		for g in pairs(add or {}) do touched[g] = true end
		for g in pairs(remove or {}) do touched[g] = true end
		for g in pairs(touched) do
			local objectivePair = shape == "objectives" and g == 4
			out[g] = patchList(out[g], add and add[g], remove and remove[g], objectivePair)
		end
		return next(out) and out or nil
	end
	return patchList(existing, add, remove, atomic[shape])
end

local stats = { rows = 0, fields = 0, ops = 0, created = 0, providers = 0 }

local function applyRow(datatype, id, fields, options)
	local meta = metaOf[datatype]
	local rows = db[datatype]
	local row = rows[id]
	if not row then
		if options and options.noNewEntries then return end
		row = {}
		rows[id] = row
		stats.created = stats.created + 1
	end
	stats.rows = stats.rows + 1
	local ops = {}
	for key, value in pairs(fields) do
		if type(key) == "number" and (key <= 0 or key >= OFFSET) then
			local field = key >= OFFSET and key - OFFSET or key + OFFSET
			ops[field] = ops[field] or {}
			ops[field][key >= OFFSET and "add" or "remove"] = value
		elseif type(key) == "number" then
			if not (options and options.noOverwrites and row[key] ~= nil) then
				row[key] = copy(value)
				stats.fields = stats.fields + 1
			end
		end
	end
	for field, op in pairs(ops) do
		row[field] = patchField(meta, field, row[field], op.add, op.remove)
		stats.ops = stats.ops + 1
	end
end

-- QuestieDB's ownedCorrections for Forever, Static functions, in order.
local PROVIDERS = {
	{ "Forever/legacy/classicQuestFixes.lua", "QuestieQuestFixes", "Quest", { "Load" } },
	{ "Forever/legacy/classicNPCFixes.lua", "QuestieNPCFixes", "Npc", { "Load" } },
	{ "Forever/legacy/classicItemFixes.lua", "QuestieItemFixes", "Item", { "Load" } },
	{ "Forever/legacy/classicObjectFixes.lua", "QuestieObjectFixes", "Object", { "Load" } },
	{ "Forever/legacy/classicQuestReputationFixes.lua", "QuestieClassicQuestReputationFixes", "Quest", { "Load" } },
	{ "Forever/legacy/itemStartFixes.lua", "QuestieItemStartFixes", "Item", { "LoadAutomaticQuestStarts" }, { noNewEntries = true, noOverwrites = true } },
	{ "Forever/generated/foreverBaseNpc.lua", "ForeverBaseNpc", "Npc", { "Load" } },
	{ "Forever/generated/foreverBaseObject.lua", "ForeverBaseObject", "Object", { "Load" } },
	{ "Forever/generated/foreverBaseQuest.lua", "ForeverBaseQuest", "Quest", { "Load" } },
	{ "Forever/generated/foreverBaseItem.lua", "ForeverBaseItem", "Item", { "Load" } },
	{ "Forever/traces/foreverQuestTraces.lua", "ForeverQuestTraces", "Quest", { "Load" } },
	{ "Forever/traces/foreverNpcTraces.lua", "ForeverNpcTraces", "Npc", { "Load" } },
	{ "Forever/traces/foreverItemTraces.lua", "ForeverItemTraces", "Item", { "Load" } },
	{ "Forever/traces/foreverObjectTraces.lua", "ForeverObjectTraces", "Object", { "Load" } },
	{ "Forever/foreverQuestFixes.lua", "ForeverQuestFixes", "Quest", { "Load" } },
	{ "Forever/foreverNPCFixes.lua", "ForeverNpcFixes", "Npc", { "Load" } },
	{ "Forever/foreverItemFixes.lua", "ForeverItemFixes", "Item", { "Load" } },
	{ "Forever/foreverObjectFixes.lua", "ForeverObjectFixes", "Object", { "Load" } },
}

for _, p in ipairs(PROVIDERS) do
	local file, module, datatype, fns, options = p[1], p[2], p[3], p[4], p[5]
	for _, buf in pairs(captured) do for k in pairs(buf) do buf[k] = nil end end
	run("src/corrections/" .. file, questieEnv())
	local mod = modules[module]
	for _, fn in ipairs(fns) do
		assert(mod and type(mod[fn]) == "function", file .. ": no " .. module .. ":" .. fn)
		local result = mod[fn](mod)
		for _, buf in pairs({ captured[datatype] }) do
			for id, row in pairs(buf) do
				if type(row) == "table" and not db[datatype][id] then db[datatype][id] = copy(row) stats.created = stats.created + 1 end
			end
		end
		for id, fields in pairs(result or {}) do
			if type(fields) == "table" then applyRow(datatype, id, fields, options) end
		end
	end
	stats.providers = stats.providers + 1
end
log(("applied %d providers: %d rows, %d replaced fields, %d add/remove operations, %d new entities"):format(
	stats.providers, stats.rows, stats.fields, stats.ops, stats.created))

---------------------------------------------------------------------------
-- Zones: AreaTable id -> UiMap id
---------------------------------------------------------------------------

local zoneEnv = env({ QuestieLoader = Loader })
modules.ZoneDB.private = {}
run("support/Forever/Zones/areaIdToUiMapId.lua", zoneEnv)
local priv = modules.ZoneDB.private
local areaToMap = runString(assert(priv.areaIdToUiMapId, "no areaIdToUiMapId"), "areaIdToUiMapId")
for area, map in pairs(runString(priv.areaIdToUiMapIdOverride or "return {}", "override")) do areaToMap[area] = map end

local function mapOf(area)
	local m = area and areaToMap[area]
	if not m or m == 0 then return nil end
	return m
end

---------------------------------------------------------------------------
-- What Pathwise ships
---------------------------------------------------------------------------

local QK, NK, OK, IK = metaOf.Quest.keys, metaOf.Npc.keys, metaOf.Object.keys, metaOf.Item.keys
local MAX_SPAWNS = 12 -- per map per entity, spread over the list

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

-- { [uiMap] = { x, y, x, y, ... } }, at most MAX_SPAWNS points per map.
local function spawnsOf(spawns)
	if type(spawns) ~= "table" then return nil end
	local out, any = {}, false
	for area, list in pairs(spawns) do
		local map = mapOf(area)
		if map and type(list) == "table" and #list > 0 then
			local pts = out[map] or {}
			local step = math.max(1, math.floor(#list / MAX_SPAWNS))
			for i = 1, #list, step do
				local c = list[i]
				if type(c) == "table" and c[1] and c[2] and c[1] >= 0 and c[2] >= 0 and #pts < MAX_SPAWNS * 2 then
					pts[#pts + 1] = round2(c[1])
					pts[#pts + 1] = round2(c[2])
				end
			end
			if #pts > 0 then out[map] = pts any = true end
		end
	end
	return any and out or nil
end

local function ids(list)
	if type(list) ~= "table" or #list == 0 then return nil end
	local out = {}
	for _, v in ipairs(list) do if type(v) == "number" then out[#out + 1] = v end end
	return #out > 0 and out or nil
end

local npcsUsed, objectsUsed, itemsUsed = {}, {}, {}
local quests = {}
for id, q in pairs(db.Quest) do
	if type(q) == "table" and type(q[QK.name]) == "string" then
		local starts = q[QK.startedBy] or {}
		local ends = q[QK.finishedBy] or {}
		local objectives = {}
		local o = q[QK.objectives] or {}
		for _, row in ipairs(o[1] or {}) do objectives[#objectives + 1] = { "m", row[1], row[2] } npcsUsed[row[1]] = true end
		for _, row in ipairs(o[2] or {}) do objectives[#objectives + 1] = { "o", row[1], row[2] } objectsUsed[row[1]] = true end
		for _, row in ipairs(o[3] or {}) do objectives[#objectives + 1] = { "i", row[1], row[2] } itemsUsed[row[1]] = true end
		for _, row in ipairs(o[5] or {}) do
			objectives[#objectives + 1] = { "k", row[2], row[3], ids(row[1]) }
			for _, n in ipairs(row[1] or {}) do npcsUsed[n] = true end
		end
		for _, n in ipairs(starts[1] or {}) do npcsUsed[n] = true end
		for _, n in ipairs(ends[1] or {}) do npcsUsed[n] = true end
		for _, n in ipairs(starts[2] or {}) do objectsUsed[n] = true end
		for _, n in ipairs(ends[2] or {}) do objectsUsed[n] = true end
		local zone = q[QK.zoneOrSort]
		quests[id] = {
			q[QK.name], q[QK.questLevel] or 0, q[QK.requiredLevel] or 0,
			q[QK.requiredRaces] or 0, q[QK.requiredClasses] or 0,
			(type(zone) == "number" and zone > 0) and mapOf(zone) or nil,
			ids(starts[1]), ids(starts[2]), ids(starts[3]), ids(ends[1]), ids(ends[2]),
			#objectives > 0 and objectives or nil,
			ids(q[QK.preQuestSingle]), ids(q[QK.preQuestGroup]), ids(q[QK.exclusiveTo]),
			q[QK.specialFlags] ~= 0 and q[QK.specialFlags] or nil,
			q[QK.breadcrumbForQuestId] ~= 0 and q[QK.breadcrumbForQuestId] or nil,
			q[QK.nextQuestInChain] ~= 0 and q[QK.nextQuestInChain] or nil,
			(type(q[QK.objectivesText]) == "table" and q[QK.objectivesText][1]) or nil,
		}
		for _, item in ipairs(starts[3] or {}) do itemsUsed[item] = true end
	end
end

-- Items an objective needs: where they drop.
local items = {}
for id in pairs(itemsUsed) do
	local it = db.Item[id]
	if type(it) == "table" and it[IK.name] then
		local drops = ids(it[IK.npcDrops])
		local objs = ids(it[IK.objectDrops])
		if drops then while #drops > 8 do table.remove(drops) end for _, n in ipairs(drops) do npcsUsed[n] = true end end
		if objs then while #objs > 8 do table.remove(objs) end for _, n in ipairs(objs) do objectsUsed[n] = true end end
		items[id] = { it[IK.name], drops, objs }
	end
end

-- Weapons and armour (item class 2 and 4) a player can get while levelling:
-- the facts Pathwise Gear's "Best in Slot (Level)" list needs to say where an
-- item comes from. Stats, slot and quality are read from the game client in
-- game (C_Item), so they are always Forever's own.
--   gear[id] = { requiredLevel, itemLevel, class, subClass, rewardQuests,
--                dropNpcs (nil when it drops from many: a world drop), vendors,
--                worldDrop, dungeon (area id, filled in below) }
local gear = {}
local MAX_DROPS = 6
for id, it in pairs(db.Item) do
	if type(it) == "table" and it[IK.name] then
		local class, req = it[IK.class], it[IK.requiredLevel] or 0
		if (class == 2 or class == 4) and req <= 60 then
			local quests = ids(it[IK.questRewards])
			local drops = ids(it[IK.npcDrops])
			local vendors = ids(it[IK.vendors])
			if quests or drops or vendors then
				local world = drops and #drops > MAX_DROPS or nil
				if world then drops = nil end
				if quests then while #quests > 3 do table.remove(quests) end end
				if vendors then while #vendors > 3 do table.remove(vendors) end end
				for _, n in ipairs(drops or {}) do npcsUsed[n] = true end
				for _, n in ipairs(vendors or {}) do npcsUsed[n] = true end
				gear[id] = { req, it[IK.itemLevel] or 0, class, it[IK.subClass] or 0, quests, drops, vendors, world }
			end
		end
	end
end

-- Crafted weapons and armour (data/recipes.lua, from the Forever client's
-- tables by tools/data/recipes.js). Kept when QuestieDB's Forever data knows
-- the item made, which is also the evidence a Season of Discovery recipe is
-- in Forever. The recipe item that teaches it (QuestieDB's teachesSpell),
-- with where it drops or is sold, goes in `items`.
--   gear[id][10] = { skillLine, skill, spell, recipeItem, sod, bindsOnPickup }
-- The item made is kept when it is a weapon or armour by QuestieDB's facts or,
-- for items QuestieDB does not know (most Season of Discovery ones), the
-- client's own tables. Season of Discovery recipes are marked `sod`: the
-- client has them, some were found in Forever, not all are confirmed.
local crafted, sodKept = 0, 0
do
	local f = io.open("data/recipes.lua", "rb")
	if f then
		f:close()
		local R = dofile("data/recipes.lua")
		-- One recipe item per spell: one someone sells, else one that drops,
		-- else the lowest id (QuestieDB says where each comes from).
		local function rank(x)
			local t = db.Item[x]
			if type(t) ~= "table" then return 3 end
			return (ids(t[IK.vendors]) and 0) or (ids(t[IK.npcDrops]) and 1) or 2
		end
		for spell, r in pairs(R.recipes) do
			local line, skill, made, auto, sod = r[1], r[2], r[3], r[4], r[5]
			-- The item made: QuestieDB's facts, else the client's own (Item, ItemSparse).
			local it = db.Item[made]
			local class = (type(it) == "table" and it[IK.class]) or r[6]
			local sub = (type(it) == "table" and it[IK.subClass]) or r[7] or 0
			local req = (type(it) == "table" and it[IK.requiredLevel]) or r[8] or 0
			local ilvl = (type(it) == "table" and it[IK.itemLevel]) or r[9] or 0
			if (class == 2 or class == 4) and req <= 60 then
				local g = gear[made]
				if not g then
					g = { req, ilvl, class, sub }
					gear[made] = g
				end
				local recipeItem
				if not auto then
					for _, x in ipairs(r[11] or {}) do
						if not recipeItem or rank(x) < rank(recipeItem) then recipeItem = x end
					end
				end
				if not g[10] or skill < g[10][2] then
					g[10] = { line, skill, spell, recipeItem, sod or nil, r[10] or nil }
				end
				if recipeItem and not items[recipeItem] and type(db.Item[recipeItem]) == "table" then
					local ri = db.Item[recipeItem]
					local drops, vendors = ids(ri[IK.npcDrops]), ids(ri[IK.vendors])
					if drops then while #drops > 8 do table.remove(drops) end for _, n in ipairs(drops) do npcsUsed[n] = true end end
					if vendors then while #vendors > 4 do table.remove(vendors) end for _, n in ipairs(vendors) do npcsUsed[n] = true end end
					items[recipeItem] = { ri[IK.name], drops, nil, vendors }
				end
				crafted = crafted + 1
				if sod then sodKept = sodKept + 1 end
			end
		end
		log(("crafted gear: %d recipes from data/recipes.lua (Forever build %s), %d of them Season of Discovery"):format(crafted, R.build, sodKept))
	else
		log("no data/recipes.lua: run node tools/data/recipes.js for crafted gear")
	end
end

local npcs = {}
for id in pairs(npcsUsed) do
	local n = db.Npc[id]
	if type(n) == "table" and n[NK.name] then
		npcs[id] = { n[NK.name], n[NK.minLevel] or 0, n[NK.maxLevel] or 0, n[NK.friendlyToFaction], spawnsOf(n[NK.spawns]) }
	end
end

local objects = {}
for id in pairs(objectsUsed) do
	local o = db.Object[id]
	if type(o) == "table" and o[OK.name] then objects[id] = { o[OK.name], spawnsOf(o[OK.spawns]) } end
end

-- Zone levels from the quests the data files under that zone and whose giver
-- stands there, per side: the 10th to 90th percentile of quest levels, so a
-- stray high or low quest does not stretch it. Side from the giver's
-- friendliness ("A", "H", "AH"/nil = both). Repeatable and event quests
-- (any special flag) are left out.
local byZone = {}
for id, q in pairs(quests) do
	local level, map = q[2], q[6]
	if level and level > 0 and map and q[7] and not q[16] then
		local npc = npcs[q[7][1]]
		local sp = npc and npc[5]
		if sp and sp[map] then
			local z = byZone[map] or { A = {}, H = {} }
			byZone[map] = z
			local f = npc[4]
			if f ~= "H" then z.A[#z.A + 1] = level end
			if f ~= "A" then z.H[#z.H + 1] = level end
		end
	end
end
local zones = {}
local function range(list)
	if #list < 6 then return nil end -- too few quests to call it a leveling zone
	table.sort(list)
	local lo = list[math.max(1, math.floor(#list * 0.1 + 0.5))]
	local hi = list[math.min(#list, math.floor(#list * 0.9 + 0.5))]
	return { lo, hi, #list }
end
for map, z in pairs(byZone) do
	local a, h = range(z.A), range(z.H)
	if a or h then zones[map] = { a, h } end
end

---------------------------------------------------------------------------
-- Dungeons and raids (support/Forever/Zones/dungeons.lua)
---------------------------------------------------------------------------
-- Kept: entries with hostile monsters in the Forever data (that leaves out
-- later expansions' instances, battlegrounds and city areas). Per instance:
--   levels: the 10th to 90th percentile of its hostile monsters' levels
--   quests: quests the data files under the instance (zoneOrSort)
--   raid:   a monster above level 62 inside (raid bosses are 63)
--   entrances: { { uiMap, x, y }, ... } as QuestieDB places them; its notes
--              mark a few as unverified on Forever, kept in `unverified`.

local dungeons = {}
local dungeonOfArea = {}
do
	local holder = { private = {} }
	local function load(faction)
		modules.ZoneDB.private = {}
		run("support/Forever/Zones/dungeons.lua", env({ QuestieLoader = Loader, UnitFactionGroup = function() return faction end }))
		return modules.ZoneDB.private.dungeons or {}
	end
	local list = load("Horde")
	local source = readFile("support/Forever/Zones/dungeons.lua")
	-- Instances that share a name are one instance (Dire Maul's wings): their
	-- areas, entrances and quests together, under the lowest area id.
	local byName = {}
	for areaId, d in pairs(list) do
		local g = byName[d[1]]
		if not g then
			g = { id = areaId, name = d[1], areas = {}, entrances = {}, unverified = false }
			byName[d[1]] = g
		end
		if areaId < g.id then g.id = areaId end
		g.areas[areaId] = true
		for _, alt in ipairs(d[2] or {}) do g.areas[alt] = true end
		-- QuestieDB's own note on the line: "unverified" placement on Forever,
		-- kept on each entrance it is about (the 4th value).
		local line = source:match("%[" .. areaId .. "%] = %b{}[^\n]*")
		local unverified = (line and line:lower():find("unverified")) and true or nil
		for _, e in ipairs(d[4] or {}) do
			local map = mapOf(e[1])
			if map and e[2] and e[3] then
				local dup = false
				for _, x in ipairs(g.entrances) do if x[1] == map and math.abs(x[2] - e[2]) < 0.5 and math.abs(x[3] - e[3]) < 0.5 then dup = true end end
				if not dup then g.entrances[#g.entrances + 1] = { map, round2(e[2]), round2(e[3]), unverified } end
			end
		end
	end
	local function pct(l, p) return l[math.max(1, math.min(#l, math.floor(#l * p + 0.5)))] end
	for _, g in pairs(byName) do
		local levels, hostile, bosses, friendlyA, friendlyH = {}, 0, 0, 0, 0
		for _, n in pairs(db.Npc) do
			if type(n) == "table" and type(n[NK.spawns]) == "table" then
				local inside = false
				for area in pairs(n[NK.spawns]) do if g.areas[area] then inside = true break end end
				if inside then
					local f = n[NK.friendlyToFaction]
					if f == "A" then friendlyA = friendlyA + 1
					elseif f == "H" then friendlyH = friendlyH + 1
					elseif f == "AH" then friendlyA, friendlyH = friendlyA + 1, friendlyH + 1
					else
						hostile = hostile + 1
						local lo, hi = n[NK.minLevel] or 0, n[NK.maxLevel] or 0
						if hi >= 63 then bosses = bosses + 1 end
						if lo > 0 and hi <= 62 then levels[#levels + 1] = lo levels[#levels + 1] = hi end
					end
				end
			end
		end
		local qs, qlevels = {}, {}
		for qid, q in pairs(db.Quest) do
			if type(q) == "table" and g.areas[q[QK.zoneOrSort]] and type(q[QK.name]) == "string" then
				qs[#qs + 1] = qid
				if (q[QK.questLevel] or 0) > 0 then qlevels[#qlevels + 1] = q[QK.questLevel] end
			end
		end
		table.sort(qs)
		-- A dungeon is mostly hostile monsters; a battleground (Alterac Valley)
		-- is mostly each side's own people. The instances Forever added (area
		-- ids from 16000, QuestieDB docs/forever-data.md) have quests in the
		-- data but no monster spawns yet: their levels come from their quests.
		-- Other instances without monsters (the Deeprun Tram, Warsong Gulch)
		-- are left out.
		local friendly = math.max(friendlyA, friendlyH)
		local lo, hi, from
		if hostile >= 8 and #levels >= 4 and friendly < hostile then
			table.sort(levels)
			lo, hi, from = pct(levels, 0.1), pct(levels, 0.9), "monsters"
		elseif g.id >= 16000 and #qlevels >= 2 then
			table.sort(qlevels)
			lo, hi, from = pct(qlevels, 0.1), pct(qlevels, 0.9), "quests"
		end
		if lo and #g.entrances > 0 then
			for area in pairs(g.areas) do dungeonOfArea[area] = g.id end
			table.sort(g.entrances, function(a, b)
				if (a[4] and 1 or 0) ~= (b[4] and 1 or 0) then return not a[4] end
				if a[1] ~= b[1] then return a[1] < b[1] end
				return a[2] < b[2]
			end)
			local all = true
			for _, e in ipairs(g.entrances) do if not e[4] then all = false end end
			dungeons[g.id] = {
				name = g.name, levels = { lo, hi }, levelsFrom = from, quests = #qs > 0 and qs or nil,
				raid = bosses >= 3 or nil, entrances = g.entrances, monsters = hostile,
				unverified = all or nil,
			}
		end
	end
end

-- A gear drop whose monsters stand inside a dungeon names that dungeon.
for _, g in pairs(gear) do
	for _, n in ipairs(g[6] or {}) do
		local npc = db.Npc[n]
		for area in pairs(type(npc) == "table" and type(npc[NK.spawns]) == "table" and npc[NK.spawns] or {}) do
			if dungeonOfArea[area] and dungeons[dungeonOfArea[area]] then g[9] = dungeonOfArea[area] break end
		end
		if g[9] then break end
	end
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

local function ser(v, out)
	local t = type(v)
	if t == "number" then
		-- %.0f, not %d: Lua 5.1's %d goes through a C int, and Forever's race
		-- masks use bits 32 and 33 (Skyborne).
		if v == math.floor(v) and math.abs(v) < 2 ^ 53 then out[#out + 1] = ("%.0f"):format(v)
		else out[#out + 1] = ("%.6g"):format(v) end
	elseif t == "string" then out[#out + 1] = ("%q"):format(v)
	elseif t == "boolean" then out[#out + 1] = tostring(v)
	elseif t == "nil" then out[#out + 1] = "nil"
	elseif t == "table" then
		out[#out + 1] = "{"
		local n = 0
		for i = 1, 30 do if v[i] ~= nil then n = i end end
		for i = 1, n do
			ser(v[i], out)
			out[#out + 1] = ","
		end
		local extra = {}
		for k in pairs(v) do
			if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then extra[#extra + 1] = k end
		end
		table.sort(extra, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(extra) do
			out[#out + 1] = "[" .. (type(k) == "number" and ("%d"):format(k) or ("%q"):format(k)) .. "]="
			ser(v[k], out)
			out[#out + 1] = ","
		end
		out[#out + 1] = "}"
	end
end

local function sortedIds(t)
	local list = {}
	for id in pairs(t) do list[#list + 1] = id end
	table.sort(list)
	return list
end

local commit = "unknown"
do
	local p = io.popen('git -C "' .. SRC .. '" rev-parse --short HEAD 2>nul || git -C "' .. SRC .. '" rev-parse --short HEAD 2>/dev/null')
	if p then commit = (p:read("*l") or "unknown"):gsub("%s", "") p:close() end
end

local f = assert(io.open(OUT, "wb"))
f:write("-- GENERATED by tools/data/build.lua from QuestieDB's Forever data (commit ", commit, ").\n")
f:write("-- Do not edit by hand: change the generator or the source and rebuild (npm run data).\n")
f:write("-- Data: the Questie team and contributors, used under GPL-3.0 (THIRD_PARTY.md).\n")
f:write("-- Layouts (by position):\n")
f:write("--   quests[id]  = { name, level, minLevel, races, classes, map, startNpcs, startObjects, startItems,\n")
f:write("--                   endNpcs, endObjects, objectives, preSingle, preGroup, exclusiveTo, special,\n")
f:write("--                   breadcrumbFor, nextInChain, objectiveText }\n")
f:write("--     objectives = { { kind (m npc, o object, i item, k kill credit), id, text, creditNpcs }, ... }\n")
f:write("--   npcs[id]    = { name, minLevel, maxLevel, friendly (\"A\", \"H\", \"AH\" or nil), spawns }\n")
f:write("--   objects[id] = { name, spawns }      spawns = { [uiMap] = { x, y, x, y, ... } }\n")
f:write("--   items[id]   = { name, dropNpcs, dropObjects, vendors }\n")
f:write("--   zones[uiMap] = { alliance = { low, high, quests }, horde = { ... } } (quest levels, 10th-90th percentile)\n\n")
f:write("local _, ns = ...\nlocal D = {}\nns.Data = D\n")
f:write(("D.SOURCE = %q\n"):format("QuestieDB Forever " .. commit))

local function section(name, t)
	f:write("D.", name, " = {\n")
	for _, id in ipairs(sortedIds(t)) do
		local out = {}
		ser(t[id], out)
		f:write("[", ("%d"):format(id), "]=", table.concat(out), ",\n")
	end
	f:write("}\n")
end
section("quests", quests)
section("npcs", npcs)
section("objects", objects)
section("items", items)
f:write("-- gear[id] = { requiredLevel, itemLevel, class, subClass, rewardQuests, dropNpcs, vendors, worldDrop, dungeon,\n")
f:write("--   craft = { skillLine, skill, spell, recipeItem, sod, bindsOnPickup } }\n")
section("gear", gear)
f:write("-- dungeons[areaId] = { name, levels = { low, high }, levelsFrom = \"monsters\" | \"quests\", quests = { ids }, raid,\n")
f:write("--   entrances = { { uiMap, x, y, unverified }, ... } (verified first), monsters, unverified (every entrance) }\n")
f:write("D.dungeons = {\n")
for _, id in ipairs(sortedIds(dungeons)) do
	local out = {}
	ser(dungeons[id], out)
	f:write("[", ("%d"):format(id), "]=", table.concat(out), ",\n")
end
f:write("}\n")
f:write("D.zones = {\n")
for _, map in ipairs(sortedIds(zones)) do
	local out = {}
	ser({ alliance = zones[map][1], horde = zones[map][2] }, out)
	f:write("[", ("%d"):format(map), "]=", table.concat(out), ",\n")
end
f:write("}\n")
f:close()

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
log(("wrote %s: %d quests, %d npcs, %d objects, %d items, %d gear, %d zones, %d dungeons and raids"):format(OUT, count(quests), count(npcs), count(objects), count(items), count(gear), count(zones), count(dungeons)))
