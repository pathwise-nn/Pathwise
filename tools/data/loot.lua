-- Builds Pathwise_Loot/Data/Loot.lua: every dungeon and raid boss of the
-- Forever client, and what QuestieDB's Forever data says each one drops.
--
--   lua5.1 tools/data/loot.lua <questiedb-dir> <wago-build-dir> [output-file]
--   (npm run loot downloads the client tables first: tools/data/loot.js)
--
-- Where each fact comes from (nothing is typed in by hand):
--   * Instances and bosses: Forever's own client tables Map, Difficulty and
--     DungeonEncounter (wago.tools, product wowf). The encounter ids are the
--     ones ENCOUNTER_START, ENCOUNTER_END and the loot history send.
--   * Which monster a boss is: a QuestieDB Forever NPC found by the boss's
--     name (the rules are at "Bosses" below). Bosses with no such NPC (a
--     council like "The Seven") get none here; the addon learns them in game.
--   * What a boss drops: QuestieDB's Forever item data (npcDrops), corrected
--     the way build.lua corrects it. Items that drop from more than
--     MAX_SOURCES monsters are world or trash drops and left out. QuestieDB
--     has no drop chances, so neither does this.
--   * The items themselves: Forever's Item table (slot, type; an item the
--     client does not have is left out) and ItemSparse (name, quality, item
--     level, level, classes). ItemSparse holds only some items; for the
--     rest the name and levels are QuestieDB's and the quality is 0
--     (unknown) until the game client tells the addon.
--   * A boss's portrait: the client's Encounter Journal art
--     (Interface/EncounterJournal/UI-EJ-BOSS-<name>), found in the game's
--     file list by the boss's name (letters and digits, any case; only an
--     exact match). The file list is wago.tools' for the build
--     (ej-boss-files.json, npm run loot downloads it); it lists files of
--     every WoW client, so a portrait Forever lacks is possible: the addon
--     then shows the boss's best item instead.
--
-- Nothing here comes from AtlasLoot (GPL-2.0 only, and not Forever's data).

local QDB, WAGO = arg[1], arg[2]
local OUT = arg[3] or "Pathwise_Loot/Data/Loot.lua"
assert(QDB and WAGO, "usage: lua5.1 tools/data/loot.lua <questiedb-dir> <wago-build-dir> [output-file]")

local MAX_SOURCES = 12

local function log(...) io.stderr:write(table.concat({ ... }, " "), "\n") end

---------------------------------------------------------------------------
-- QuestieDB, corrected (build.lua in its data-only mode)
---------------------------------------------------------------------------

PATHWISE_DATA_ONLY = true
local saved = arg
arg = { QDB, "nothing" }
local Q = assert(dofile("tools/data/build.lua"), "build.lua returned nothing")
arg = saved
local db, NK, IK = Q.db, Q.npcKeys, Q.itemKeys

local commit = "unknown"
do
	local p = io.popen('git -C "' .. QDB .. '" rev-parse --short HEAD 2>nul || git -C "' .. QDB .. '" rev-parse --short HEAD 2>/dev/null')
	if p then commit = (p:read("*l") or "unknown"):gsub("%s", "") p:close() end
end

---------------------------------------------------------------------------
-- The client's tables (CSV)
---------------------------------------------------------------------------

local function csv(name)
	local path = WAGO .. "/" .. name .. ".csv"
	local f = assert(io.open(path, "rb"), "missing " .. path .. " (npm run loot downloads it)")
	local text = f:read("*a")
	f:close()
	local rows, row, field, i, q = {}, {}, {}, 1, false
	local n = #text
	while i <= n do
		local c = text:sub(i, i)
		if q then
			if c == '"' then
				if text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"' i = i + 1 else q = false end
			else field[#field + 1] = c end
		elseif c == '"' then q = true
		elseif c == "," then row[#row + 1] = table.concat(field) field = {}
		elseif c == "\n" then row[#row + 1] = table.concat(field) field = {} rows[#rows + 1] = row row = {}
		elseif c ~= "\r" then field[#field + 1] = c end
		i = i + 1
	end
	if #field > 0 or #row > 0 then row[#row + 1] = table.concat(field) rows[#rows + 1] = row end
	local head = table.remove(rows, 1)
	local out = {}
	for _, r in ipairs(rows) do
		local o = {}
		for k, h in ipairs(head) do o[h] = r[k] end
		out[#out + 1] = o
	end
	log(("read %s: %d rows"):format(name, #out))
	return out
end

local build = WAGO:match("([%d%.]+)[/\\]?$") or "unknown"

---------------------------------------------------------------------------
-- Instances: the client's Map rows that hold encounters
---------------------------------------------------------------------------

local function norm(s)
	s = tostring(s or ""):lower():gsub("^the ", ""):gsub("[^%w]", "")
	return s
end

-- Pathwise's dungeons (build.lua) by name, and their areas.
local dungeonByName, areasOf = {}, {}
for id, d in pairs(Q.dungeons) do dungeonByName[norm(d.name)] = id end
for area, id in pairs(Q.dungeonOfArea) do
	areasOf[id] = areasOf[id] or {}
	areasOf[id][area] = true
end

local maps, players = {}, {}
for _, m in ipairs(csv("Map")) do maps[tonumber(m.ID)] = m end
-- A boss row's difficulty: Forever names them all "Normal"; the player count
-- tells a raid version (10 or 20) from the dungeon (5).
for _, d in ipairs(csv("Difficulty")) do players[tonumber(d.ID)] = tonumber(d.MaxPlayers) or 0 end

local instances, encounters, unmatched = {}, {}, {}
local skippedMaps = {}
for _, e in ipairs(csv("DungeonEncounter")) do
	local mapId, id = tonumber(e.MapID), tonumber(e.ID)
	local m = maps[mapId]
	local kind = m and tonumber(m.InstanceType)
	local name = m and m.MapName_lang
	-- A dungeon (1) or raid (2) with a name; not the client's test map or
	-- rows Blizzard marks unused.
	if not (kind == 1 or kind == 2) or not name or name:find("^Test ") or e.Name_lang == "No Longer in Use" then
		skippedMaps[(name or ("map " .. tostring(mapId))) .. " (" .. tostring(e.Name_lang) .. ")"] = true
	else
		local inst = instances[mapId]
		if not inst then
			local area = tonumber(m.AreaTableID)
			local dungeon = (area and Q.dungeonOfArea[area]) or dungeonByName[norm(name)]
			inst = { map = mapId, name = name, raid = kind == 2, size = tonumber(m.MaxPlayers) or 0, dungeon = dungeon, list = {} }
			if dungeon and Q.dungeons[dungeon] then
				local lv = Q.dungeons[dungeon].levels
				inst.levels = lv and { lv[1], lv[2] } or nil
			end
			instances[mapId] = inst
		end
		inst.list[#inst.list + 1] = { id = id, order = tonumber(e.OrderIndex) or 0 }
		encounters[id] = { name = e.Name_lang, map = mapId, players = players[tonumber(e.DifficultyID) or 0] or 0, npcs = {} }
	end
end

---------------------------------------------------------------------------
-- Bosses: the QuestieDB NPC with the boss's name, inside the instance
---------------------------------------------------------------------------

local npcsByName = {}
for nid, n in pairs(db.Npc) do
	if type(n) == "table" and type(n[NK.name]) == "string" then
		local k = norm(n[NK.name])
		npcsByName[k] = npcsByName[k] or {}
		table.insert(npcsByName[k], nid)
	end
end

local function inside(nid, areas)
	local n = db.Npc[nid]
	local spawns = type(n) == "table" and n[NK.spawns]
	if not (areas and type(spawns) == "table") then return false end
	for area in pairs(spawns) do if areas[area] then return true end end
	return false
end

local function spawnless(nid)
	local s = db.Npc[nid][NK.spawns]
	return type(s) ~= "table" or next(s) == nil
end

-- In this order, the first rule that finds any:
--   1. an NPC of exactly the boss's name inside the instance;
--   2. one whose name starts with the boss's, or the boss's with its, inside
--      the instance (the client says "Kirtonos", QuestieDB "Kirtonos the Herald");
--   3. the only NPC of exactly that name anywhere, when QuestieDB has no
--      spawn for it (nothing places it elsewhere).
local matched, byRule = 0, { 0, 0, 0 }
for id, enc in pairs(encounters) do
	local inst = instances[enc.map]
	local areas = {}
	for a in pairs(inst.dungeon and areasOf[inst.dungeon] or {}) do areas[a] = true end
	local own = tonumber(maps[enc.map].AreaTableID)
	if own and own > 0 then areas[own] = true end
	local key = norm(enc.name)
	for _, nid in ipairs(npcsByName[key] or {}) do
		if inside(nid, areas) then enc.npcs[#enc.npcs + 1] = nid end
	end
	if #enc.npcs > 0 then byRule[1] = byRule[1] + 1 end
	if #enc.npcs == 0 and #key >= 5 then
		for k, list in pairs(npcsByName) do
			if k ~= key and (k:sub(1, #key) == key or (#k >= 5 and key:sub(1, #k) == k)) then
				for _, nid in ipairs(list) do if inside(nid, areas) then enc.npcs[#enc.npcs + 1] = nid end end
			end
		end
		if #enc.npcs > 0 then byRule[2] = byRule[2] + 1 end
	end
	local same = npcsByName[key]
	if #enc.npcs == 0 and same and #same == 1 and spawnless(same[1]) then
		enc.npcs[1] = same[1]
		byRule[3] = byRule[3] + 1
	end
	table.sort(enc.npcs)
	if #enc.npcs > 0 then matched = matched + 1 else unmatched[#unmatched + 1] = ("%s (%s)"):format(enc.name, inst.name) end
end
table.sort(unmatched)

---------------------------------------------------------------------------
-- Drops, and the items as Forever's client knows them
---------------------------------------------------------------------------

local sparse, itemRows = {}, {}
for _, r in ipairs(csv("ItemSparse")) do sparse[tonumber(r.ID)] = r end
for _, r in ipairs(csv("Item")) do itemRows[tonumber(r.ID)] = r end

local dropsOf = {} -- npc id -> { item ids }
for iid, it in pairs(db.Item) do
	local drops = type(it) == "table" and it[IK.npcDrops]
	if type(drops) == "table" and #drops > 0 and #drops <= MAX_SOURCES and itemRows[iid] then
		for _, nid in ipairs(drops) do
			dropsOf[nid] = dropsOf[nid] or {}
			table.insert(dropsOf[nid], iid)
		end
	end
end

local items, withLoot, drops = {}, 0, 0
for _, enc in pairs(encounters) do
	local set, list = {}, {}
	for _, nid in ipairs(enc.npcs) do
		for _, iid in ipairs(dropsOf[nid] or {}) do
			if not set[iid] then set[iid] = true list[#list + 1] = iid end
		end
	end
	local function q(iid) return sparse[iid] and tonumber(sparse[iid].OverallQualityID) or 0 end
	table.sort(list, function(a, b)
		if q(a) ~= q(b) then return q(a) > q(b) end
		return a < b
	end)
	enc.items = list
	if #list > 0 then withLoot = withLoot + 1 end
	drops = drops + #list
	for _, iid in ipairs(list) do
		if not items[iid] then
			-- The client ships only some items in ItemSparse (the rest reach it
			-- from the server in game); Item has them all. Where ItemSparse has
			-- none: the name and levels are QuestieDB's, the quality unknown (0)
			-- until the game tells the addon.
			local s, r, qd = sparse[iid], itemRows[iid], db.Item[iid]
			local classes = s and tonumber(s.AllowableClass) or -1
			items[iid] = {
				(s and s.Display_lang ~= "" and s.Display_lang) or qd[IK.name] or "",
				s and tonumber(s.OverallQualityID) or 0,
				(s and tonumber(s.ItemLevel)) or qd[IK.itemLevel] or 0,
				(s and tonumber(s.RequiredLevel)) or qd[IK.requiredLevel] or 0,
				tonumber(r.InventoryType) or 0, tonumber(r.ClassID) or 0, tonumber(r.SubclassID) or 0,
				(classes > 0 and classes ~= 32767 and classes ~= 4095) and classes or nil,
			}
		end
	end
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

local function sortedKeys(t)
	local list = {}
	for k in pairs(t) do list[#list + 1] = k end
	table.sort(list)
	return list
end

local function list(t)
	local out = {}
	for i, v in ipairs(t) do out[i] = ("%d"):format(v) end
	return "{" .. table.concat(out, ",") .. "}"
end

-- Dungeons by their level, then raids by theirs; ties by name.
local order = {}
for _, inst in pairs(instances) do
	table.sort(inst.list, function(a, b) if a.order ~= b.order then return a.order < b.order end return a.id < b.id end)
	order[#order + 1] = inst
end
table.sort(order, function(a, b)
	if a.raid ~= b.raid then return not a.raid end
	local la, lb = a.levels and a.levels[1] or 99, b.levels and b.levels[1] or 99
	if la ~= lb then return la < lb end
	return a.name < b.name
end)

---------------------------------------------------------------------------
-- Portraits: the Encounter Journal's boss art, by the boss's name
---------------------------------------------------------------------------

local portraits, nPortraits = {}, 0
do
	local path = WAGO .. "/ej-boss-files.json"
	local fh = assert(io.open(path, "rb"), "missing " .. path .. " (npm run loot downloads it)")
	local text = fh:read("*a")
	fh:close()
	local function key(s) return tostring(s or ""):lower():gsub("[^%w]", "") end
	local byKey = {} -- name key -> lowest file id
	for id, file in text:gmatch('"(%d+)"%s*:%s*"([^"]+)"') do
		local name = file:gsub("\\/", "/"):lower():match("^interface/encounterjournal/ui%-ej%-boss%-(.+)%.blp$")
		if name then
			local k, n = key(name), tonumber(id)
			if not byKey[k] or n < byKey[k] then byKey[k] = n end
		end
	end
	for id, e in pairs(encounters) do
		local fid = byKey[key(e.name)] or byKey[key((e.name:gsub("^[Tt]he ", "")))]
		if fid then portraits[id] = fid nPortraits = nPortraits + 1 end
	end
end

local f = assert(io.open(OUT, "wb"))
f:write("-- GENERATED by tools/data/loot.lua (npm run loot). Do not edit by hand:\n")
f:write("-- change the generator or its sources and rebuild.\n")
f:write("--\n")
f:write(("-- Instances, bosses and items: Forever's client tables Map, Difficulty,\n-- DungeonEncounter, ItemSparse and Item (build %s, via wago.tools; (c) Blizzard Entertainment).\n"):format(build))
f:write(("-- Who drops what: QuestieDB's Forever data (commit %s), by the Questie team\n-- and contributors, used under GPL-3.0 (THIRD_PARTY.md). It has no drop chances.\n"):format(commit))
f:write("-- Nothing here comes from AtlasLoot.\n")
f:write("--\n")
f:write("--   INSTANCES[i]     = { map, name, raid, size, { lowLevel, highLevel } | nil, { encounter ids } }\n")
f:write("--   ENCOUNTERS[id]   = { name, map, players (0: the instance's own size), { npc ids }, { item ids } }\n")
f:write("--   ITEMS[id]        = { name, quality, itemLevel, requiredLevel, inventoryType, class, subClass, classMask | nil }\n")
f:write("--   PORTRAITS[id]    = file id of the boss's Encounter Journal art (UI-EJ-BOSS-<name>), by its name; from\n")
f:write("--                      the game's file list, which may hold files Forever lacks (the addon checks)\n")
f:write("\nlocal ADDON, ns = ...\nlocal D = {}\nns.LootData = D\n\n")
f:write(("D.BUILD = %q\nD.QUESTIEDB = %q\n\n"):format(build, commit))

f:write("D.INSTANCES = {\n")
for _, inst in ipairs(order) do
	local ids = {}
	for i, e in ipairs(inst.list) do ids[i] = e.id end
	f:write(("\t{ %d, %q, %s, %d, %s, %s },\n"):format(inst.map, inst.name, tostring(inst.raid), inst.size,
		inst.levels and ("{ %d, %d }"):format(inst.levels[1], inst.levels[2]) or "nil", list(ids)))
end
f:write("}\n\n")

f:write("D.ENCOUNTERS = {\n")
for _, id in ipairs(sortedKeys(encounters)) do
	local e = encounters[id]
	f:write(("\t[%d] = { %q, %d, %d, %s, %s },\n"):format(id, e.name, e.map, e.players, list(e.npcs), list(e.items)))
end
f:write("}\n\n")

f:write("D.PORTRAITS = {\n")
for _, id in ipairs(sortedKeys(portraits)) do f:write(("\t[%d] = %d,\n"):format(id, portraits[id])) end
f:write("}\n\n")

f:write("D.ITEMS = {\n")
for _, id in ipairs(sortedKeys(items)) do
	local it = items[id]
	f:write(("\t[%d] = { %q, %d, %d, %d, %d, %d, %d%s },\n"):format(id, it[1], it[2], it[3], it[4], it[5], it[6], it[7],
		it[8] and (", %d"):format(it[8]) or ""))
end
f:write("}\n")
f:close()

local nInst, nEnc = 0, 0
for _ in pairs(instances) do nInst = nInst + 1 end
for _ in pairs(encounters) do nEnc = nEnc + 1 end
log(("wrote %s: %d instances, %d bosses (%d matched to a monster, %d with loot), %d drops of %d items"):format(
	OUT, nInst, nEnc, matched, withLoot, drops, (function() local n = 0 for _ in pairs(items) do n = n + 1 end return n end)()))
log(("portraits found by name: %d of %d bosses"):format(nPortraits, nEnc))
log(("bosses matched by name inside: %d, by a longer or shorter name inside: %d, by a unique name with no spawn: %d"):format(byRule[1], byRule[2], byRule[3]))
for k in pairs(skippedMaps) do log("left out: " .. k) end
log(("no monster in the data for %d bosses: %s"):format(#unmatched, table.concat(unmatched, "; ")))
