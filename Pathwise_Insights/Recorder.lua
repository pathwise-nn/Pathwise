-- Pathwise Insights: the recorder. While you play it writes down, for each
-- of your characters, how long each guide step took and the XP it gave, time
-- and XP per route, zone and level, quests turned in (how long each took and
-- what it paid), monsters killed, deaths, distance travelled, sessions and
-- days, the hours of the day you play, profession skill-ups, and where you
-- went on each continent and in each zone (a heat map and a trail), to draw
-- over the game's own maps.
--
-- Everything stays in PathwiseInsightsData (saved for the account, in
-- WTF\Account\...\SavedVariables): nothing leaves your computer.
--
-- Time is the time you are playing: AFK, loading screens and long hitches
-- are not counted.

local ADDON, ns = ...
local S = ns.S
local R = {}
ns.Recorder = R

local SCHEMA = 2
local MAX_STEPS = 1000 -- the oldest step records go first
local MAX_SESSIONS = 300
local MAX_QUESTS = 800 -- quest records kept (the newest)
local MAX_DEATHS = 300
local MAX_TRAIL = 12000 -- points per continent; past it, every other one goes
local HITCH = 2 -- a frame longer than this (a loading screen) is not counted
local GRID = 100 -- heat map cells across a continent
local TRAIL_STEP = 0.002 -- a trail point at least this far (of the continent) from the last
local ZONE_STEP = 0.005 -- the same in a zone (a zone is smaller: about as many yards)
local SAMPLE = 1 -- seconds between looks at where you are

R.GRID = GRID

S.Defaults("insights", { record = true })

local function now() return time and time() or 0 end
local dateFn = date or (os and os.date)

-- "2026-10-09"; the hour (0-23) and weekday (1 = Monday) of a time.
local function dayKey(t) return dateFn and dateFn("%Y-%m-%d", t) or "?" end
local function hourOf(t) return dateFn and tonumber(dateFn("%H", t)) or 0 end
local function weekdayOf(t)
	local w = dateFn and tonumber(dateFn("%w", t)) or 1 -- 0 = Sunday
	return w == 0 and 7 or w
end
R.DayKey = dayKey

---------------------------------------------------------------------------
-- The saved data: one log per character
---------------------------------------------------------------------------

local function charKey()
	local name = UnitName and UnitName("player") or "Player"
	local realm = GetRealmName and GetRealmName() or ""
	return realm ~= "" and (name .. "-" .. realm) or name
end
R.CharKey = charKey

function R.Data()
	local d = PathwiseInsightsData
	if type(d) ~= "table" or d.schema ~= SCHEMA then
		d = { schema = SCHEMA, chars = {} }
		PathwiseInsightsData = d
	end
	d.chars = type(d.chars) == "table" and d.chars or {}
	return d
end

local function list(t, k) t[k] = type(t[k]) == "table" and t[k] or {} return t[k] end

local function fill(log)
	log.since = log.since or now()
	log.played = log.played or 0 -- seconds counted
	log.xp = log.xp or 0
	log.deaths = log.deaths or 0
	log.quests = log.quests or 0
	log.kills = log.kills or 0
	log.dist = log.dist or 0 -- yards
	for _, k in ipairs({ "steps", "routes", "zones", "levels", "skills", "sessions", "days", "hours", "weekdays",
		"open", "records", "heat", "trail", "conts", "zonemaps", "questLog", "deathLog" }) do list(log, k) end
	-- steps: { r, s, t, xp, d, lvl, how }, oldest first
	-- routes: id -> { t, xp, d, steps, skips, done }; zones: map -> { t, xp, d, lvl }
	-- levels: level -> { t, xp, d, full } (full: seen from its start)
	-- skills: line -> { from, to, ups }; sessions: { start, t, xp, q }
	-- days: "2026-10-09" -> seconds; hours: 0-23 -> seconds; weekdays: 1-7 -> seconds
	-- open: quest -> { p = played seconds, lvl, m, x, y } when taken
	-- questLog: { q, t, xp, lvl, am, ax, ay, tm, tx, ty, ab, at } (ab: abandoned; at:
	--   played seconds when it was handed in or abandoned, so taken at at - t), oldest first
	-- deathLog: { m, x, y, lvl, r, s }; records: fastest/longest/best quest
	-- heat: continent -> { [cell] = { t, xp } }; trail: continent -> { x, y, flag, ... }
	-- conts: continent -> its name; zonemaps: zone -> its name (heat and trail
	-- hold zones too, by their map id)
	return log
end

-- A character's log (this character's when no key is given).
function R.Log(key)
	local d = R.Data()
	key = key or charKey()
	local log = d.chars[key]
	if type(log) ~= "table" then
		log = {}
		d.chars[key] = log
	end
	return fill(log)
end

-- Every character with a log: { { key, log }, ... }, the last played first.
function R.Characters()
	local out = {}
	for key, log in pairs(R.Data().chars) do
		if type(log) == "table" then out[#out + 1] = { key = key, log = fill(log) } end
	end
	table.sort(out, function(a, b) return (a.log.last or 0) > (b.log.last or 0) end)
	return out
end

function R.Hide(key, hidden)
	local log = R.Data().chars[key]
	if log then log.hidden = hidden and true or nil end
	S.Fire("INSIGHTS_UPDATED")
end

function R.Delete(key)
	R.Data().chars[key] = nil
	if key == charKey() then R.Start(true) end
	S.Fire("INSIGHTS_UPDATED")
end

function R.Clear() R.Delete(charKey()) end

local function recording() return S.Get("insights.record") end

local function bucket(tbl, key)
	local b = tbl[key]
	if not b then
		b = { t = 0, xp = 0, d = 0 }
		tbl[key] = b
	end
	return b
end

local function level() return UnitLevel and UnitLevel("player") or 1 end
local function mapNow() return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") end

---------------------------------------------------------------------------
-- Where you are on the continent
---------------------------------------------------------------------------

-- The continent a map is in (walking up its parents), or nil.
local CONTINENT = 2 -- Enum.UIMapType.Continent
local continentCache = {}
function R.ContinentOf(map)
	if not map then return nil end
	if continentCache[map] ~= nil then return continentCache[map] or nil end
	local found, m, hops = false, map, 0
	while m and hops < 8 do
		local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(m)
		if not info then break end
		if info.mapType == CONTINENT then found = m break end
		m, hops = info.parentMapID, hops + 1
	end
	continentCache[map] = found
	return found or nil
end

-- Where you stand in your zone (the map the game puts you on): map, x, y (0-1).
function R.Where()
	local map = mapNow()
	if not (map and C_Map and C_Map.GetPlayerMapPosition) then return nil end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return nil end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return map, x, y
end

-- Where you stand on your continent: continent, x, y (0-1), or nil.
local function onContinent()
	local cont = R.ContinentOf(mapNow())
	if not (cont and C_Map and C_Map.GetPlayerMapPosition) then return nil end
	local pos = C_Map.GetPlayerMapPosition(cont, "player")
	if not pos then return nil end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return cont, x, y
end
R.OnContinent = onContinent

local function cellOf(x, y)
	local cx = math.min(GRID - 1, math.max(0, math.floor(x * GRID)))
	local cy = math.min(GRID - 1, math.max(0, math.floor(y * GRID)))
	return cy * GRID + cx
end
R.CellOf = cellOf

---------------------------------------------------------------------------
-- Counting
---------------------------------------------------------------------------

-- Where the counted time and XP go: the step, its route, the zone, the
-- level, the session and the heat map cell you stand in.
local zone, here, session
local function targets(log)
	local out = {}
	local cur = log.cur
	if cur then
		out[#out + 1] = cur
		out[#out + 1] = bucket(log.routes, cur.r)
	end
	if zone then out[#out + 1] = bucket(log.zones, zone) end
	out[#out + 1] = bucket(log.levels, level())
	if session then out[#out + 1] = session end
	if here and not here.taxi then
		out[#out + 1] = bucket(list(log.heat, here.cont), here.cell)
		if here.zone then out[#out + 1] = bucket(list(log.heat, here.zone), here.zcell) end
	end
	return out
end

local TOTAL = { t = "played", xp = "xp", d = "deaths" }
local function add(field, n)
	if not recording() or n <= 0 then return end
	local log = R.Log()
	log[TOTAL[field]] = log[TOTAL[field]] + n
	for _, b in ipairs(targets(log)) do b[field] = (b[field] or 0) + n end
	if field == "t" then
		local t = now()
		local day = dayKey(t)
		log.days[day] = (log.days[day] or 0) + n
		local h = hourOf(t)
		log.hours[h] = (log.hours[h] or 0) + n
		local w = weekdayOf(t)
		log.weekdays[w] = (log.weekdays[w] or 0) + n
		log.last = t
	end
end
R.Add = add

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------

-- The step being timed ends: kept in log.steps, counted on its route.
local function close(log, how)
	local cur = log.cur
	log.cur = nil
	if not cur or (cur.t or 0) < 1 then return end
	local steps = log.steps
	-- Where it ended (the place the step's last goal was done).
	local m, x, y = R.Where()
	steps[#steps + 1] = { r = cur.r, s = cur.s, t = math.floor(cur.t + 0.5), xp = cur.xp or 0, d = cur.d or 0, lvl = cur.lvl, how = how,
		v = cur.v, src = cur.src, k = cur.k or 0, yd = math.floor((cur.yd or 0) + 0.5), fly = math.floor((cur.fly or 0) + 0.5),
		grp = math.floor((cur.grp or 0) + 0.5), m = m, x = x and math.floor(x * 1000 + 0.5), y = y and math.floor(y * 1000 + 0.5) }
	while #steps > MAX_STEPS do table.remove(steps, 1) end
	local route = bucket(log.routes, cur.r)
	if how == "skip" then route.skips = (route.skips or 0) + 1
	elseif how == "done" then route.steps = (route.steps or 0) + 1 end
end

local function open(log, route, step, src)
	if step then
		-- v: the version whose routes the step numbers are (they change between
		-- releases): Pathwise's, or Insights' own copy of the routes (the same
		-- release). src: who said where you are: "guide" (Pathwise) or "quests"
		-- (Track.lua, from your quest log, without Pathwise).
		log.cur = { r = route, s = step, t = 0, xp = 0, d = 0, lvl = level(), v = S.VERSION or ns.VERSION, k = 0, yd = 0,
			fly = 0, grp = 0, src = src or "guide" }
	else
		bucket(log.routes, route).done = true -- the route is finished
	end
end

-- The live step moved: Pathwise's GUIDE_STEP (Guide/Engine.lua), or
-- Track.lua's when Pathwise is not installed.
function R.OnStep(info)
	if not recording() or type(info) ~= "table" or not info.route then return end
	local log = R.Log()
	local cur = log.cur
	if info.how == "login" then
		-- After a /reload or a new session: the same step goes on being timed.
		if cur and cur.r == info.route and cur.s == info.step then return end
		close(log, "moved")
	else
		close(log, info.how)
	end
	open(log, info.route, info.step, info.src)
	S.Fire("INSIGHTS_UPDATED")
end
-- Pathwise's message (only when Pathwise is installed: it times the steps).
do
	local P = ns.Pathwise()
	if P and P.On then P.On("GUIDE_STEP", R.OnStep) end
end

---------------------------------------------------------------------------
-- Quests: how long each took (played time) and what it paid
---------------------------------------------------------------------------

local function questName(q)
	return S.Quests and S.Quests.Name and S.Quests.Name(q) or ("Quest " .. tostring(q))
end

local function pos3(x) return x and math.floor(x * 1000 + 0.5) or nil end

function R.OnAccepted(q)
	if not (recording() and type(q) == "number") then return end
	local log = R.Log()
	if log.open[q] then return end
	local m, x, y = R.Where()
	log.open[q] = { p = log.played, lvl = level(), m = m, x = pos3(x), y = pos3(y) }
end

local function keepQuest(log, rec)
	local list = log.questLog
	list[#list + 1] = rec
	while #list > MAX_QUESTS do table.remove(list, 1) end
end

-- QUEST_REMOVED: handed in (QUEST_TURNED_IN said so) or abandoned.
function R.OnRemoved(q)
	if not (recording() and type(q) == "number") then return end
	local log = R.Log()
	local taken = log.open[q]
	if type(taken) ~= "table" then return end
	local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q)
	if done then return end
	log.open[q] = nil
	keepQuest(log, { q = q, t = math.floor(log.played - taken.p + 0.5), xp = 0, lvl = taken.lvl,
		am = taken.m, ax = taken.x, ay = taken.y, ab = true, at = math.floor(log.played + 0.5) })
end

-- QUEST_TURNED_IN: questID, xpReward, moneyReward.
function R.OnTurnedIn(q, xp)
	if not (recording() and type(q) == "number") then return end
	local log = R.Log()
	log.quests = log.quests + 1
	if session then session.q = (session.q or 0) + 1 end
	local rec = log.records
	local taken = log.open[q]
	log.open[q] = nil
	if type(taken) == "number" then taken = { p = taken } end -- kept by an older version
	local m, x, y = R.Where()
	keepQuest(log, { q = q, t = taken and math.floor(log.played - taken.p + 0.5) or nil, xp = tonumber(xp) or 0,
		lvl = taken and taken.lvl or level(), am = taken and taken.m, ax = taken and taken.x, ay = taken and taken.y,
		tm = m, tx = pos3(x), ty = pos3(y), at = math.floor(log.played + 0.5) })
	if taken then
		local t = math.floor(log.played - taken.p + 0.5)
		-- Taken and handed in on the spot is not a "fastest" quest.
		if t >= 10 and (not rec.fastQuest or t < rec.fastQuest.t) then rec.fastQuest = { q = q, name = questName(q), t = t } end
		if not rec.slowQuest or t > rec.slowQuest.t then rec.slowQuest = { q = q, name = questName(q), t = t } end
	end
	xp = tonumber(xp)
	if xp and xp > 0 and (not rec.bestQuest or xp > rec.bestQuest.xp) then
		rec.bestQuest = { q = q, name = questName(q), xp = xp }
	end
	S.Fire("INSIGHTS_UPDATED")
end

---------------------------------------------------------------------------
-- The game: time, XP, deaths, kills, zones, skills, distance
---------------------------------------------------------------------------

local lastXP, lastMax, lastLevel

local function readXP()
	return UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 0, level()
end

-- XP gained since the last look: across a level up, the rest of the old
-- level and what is in the new one.
function R.OnXP()
	local xp, max, lvl = readXP()
	if lastXP then
		local gain
		if lvl == lastLevel then gain = xp - lastXP
		elseif lvl == lastLevel + 1 then
			gain = (lastMax - lastXP) + xp
			if recording() then bucket(R.Log().levels, lvl).full = true end -- seen from its start
		end
		if gain and gain > 0 then add("xp", gain) end
	end
	lastXP, lastMax, lastLevel = xp, max, lvl
end

local function afk() return UnitIsAFK and UnitIsAFK("player") end

-- Where you are, every SAMPLE seconds: the heat map cell, the trail, and
-- the distance walked (or flown).
local since = 0
local function mapName(map)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or ("Map " .. map)
end

-- A trail point on map `map`, when far enough from the last one.
local function addPoint(log, map, x, y, taxi, step)
	local trail = list(log.trail, map)
	local n = #trail
	local lx, ly = n >= 3 and trail[n - 2] / 10000, n >= 3 and trail[n - 1] / 10000
	local moved = lx and math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2) or 1
	if moved < step then return end
	trail[n + 1] = math.floor(x * 10000 + 0.5)
	trail[n + 2] = math.floor(y * 10000 + 0.5)
	trail[n + 3] = taxi and 1 or 0
	if #trail > MAX_TRAIL * 3 then
		local kept = {}
		for i = 1, #trail, 6 do kept[#kept + 1], kept[#kept + 2], kept[#kept + 3] = trail[i], trail[i + 1], trail[i + 2] end
		log.trail[map] = kept
	end
end

-- Where you stand in the zone (the map the game puts you on): zone, x, y.
local function inZone(cont)
	local map = mapNow()
	if not (map and map ~= cont and C_Map and C_Map.GetPlayerMapPosition) then return nil end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return nil end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	if not (x and y) or (x == 0 and y == 0) then return nil end
	return map, x, y
end

function R.Sample()
	local cont, x, y = onContinent()
	if not cont then here = nil return end
	local taxi = UnitOnTaxi and UnitOnTaxi("player") or false
	local log = R.Log()
	log.conts[cont] = log.conts[cont] or mapName(cont)
	addPoint(log, cont, x, y, taxi, TRAIL_STEP)
	local zone, zx, zy = inZone(cont)
	if zone then
		log.zonemaps[zone] = log.zonemaps[zone] or mapName(zone)
		addPoint(log, zone, zx, zy, taxi, ZONE_STEP)
	end
	-- Yards: from the world position, when the last look was close by.
	local inst, north, west
	if S.Compat and S.Compat.PlayerWorldPosition then inst, north, west = S.Compat.PlayerWorldPosition() end
	if here and here.inst == inst and north and here.north then
		local d = math.sqrt((north - here.north) ^ 2 + (west - here.west) ^ 2)
		if d < 300 then
			log.dist = log.dist + d
			if log.cur then log.cur.yd = (log.cur.yd or 0) + d end
		end
	end
	here = { cont = cont, cell = cellOf(x, y), zone = zone, zcell = zone and cellOf(zx, zy), taxi = taxi,
		inst = inst, north = north, west = west }
end

-- Counts `sec` seconds of play, unless you are AFK.
function R.Play(sec)
	if afk() then return end
	add("t", sec)
	local cur = recording() and R.Log().cur
	if cur then
		if here and here.taxi then cur.fly = (cur.fly or 0) + sec end
		if IsInGroup and IsInGroup() then cur.grp = (cur.grp or 0) + sec end
	end
end

-- Every frame: a frame longer than HITCH (a loading screen) is not play.
function R.Tick(elapsed)
	if not elapsed or elapsed <= 0 or elapsed > HITCH then return end
	since = since + elapsed
	if since >= SAMPLE and recording() then
		since = 0
		R.Sample()
	end
	R.Play(elapsed)
end

function R.OnZone()
	zone = mapNow()
	if zone and recording() then
		local z = bucket(R.Log().zones, zone)
		z.lvl = z.lvl or level()
	end
end

-- Professions: the first rank seen and the highest, and the points gained.
function R.OnSkills()
	if not recording() or not (S.Professions and S.Professions.Known) then return end
	local log = R.Log()
	for _, k in ipairs(S.Professions.Known()) do
		local line = k.prof.line
		local s = log.skills[line]
		if not s then
			log.skills[line] = { from = k.rank, to = k.rank, ups = 0 }
		elseif k.rank > s.to then
			s.ups = (s.ups or 0) + (k.rank - s.to)
			s.to = k.rank
		end
	end
end

-- Who this character is, for the tabs.
local function describe(log)
	local race = UnitRace and UnitRace("player")
	local class = UnitClass and UnitClass("player")
	local _, classKey = UnitClass and UnitClass("player")
	log.name = UnitName and UnitName("player") or log.name
	log.race, log.class, log.classKey = race or log.race, class or log.class, classKey or log.classKey
	log.faction = UnitFactionGroup and UnitFactionGroup("player") or log.faction
	log.level = level()
end

-- A kill of yours (or your pet's): the combat log's PARTY_KILL.
function R.OnCombatLog()
	if not (recording() and CombatLogGetCurrentEventInfo) then return end
	local _, sub, _, source = CombatLogGetCurrentEventInfo()
	if sub ~= "PARTY_KILL" then return end
	if source == (UnitGUID and UnitGUID("player")) or source == (UnitGUID and UnitGUID("pet")) then
		local log = R.Log()
		log.kills = log.kills + 1
		if log.cur then log.cur.k = (log.cur.k or 0) + 1 end
	end
end

-- Starts (or, after a clear, restarts) the recorder: a new session.
function R.Start(cleared)
	local log = R.Log()
	describe(log)
	log.last = log.last or now()
	lastXP = nil
	R.OnXP()
	R.OnZone()
	R.OnSkills()
	session = { start = now(), t = 0, xp = 0, q = 0 }
	if recording() then
		log.sessions[#log.sessions + 1] = session
		while #log.sessions > MAX_SESSIONS do table.remove(log.sessions, 1) end
	end
	if cleared then
		local id = S.Guide.Route()
		local step = S.Guide.Step()
		if id and step and recording() then open(log, id, step) end
	end
end

local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(_, elapsed) R.Tick(elapsed) end)

S.RegisterEvent("PLAYER_XP_UPDATE", function() R.OnXP() end)
S.RegisterEvent("PLAYER_LEVEL_UP", function() R.OnXP() R.Log().level = level() end)
function R.OnDead()
	add("d", 1)
	if recording() then
		local log = R.Log()
		local m, x, y = R.Where()
		local list = log.deathLog
		list[#list + 1] = { m = m, x = pos3(x), y = pos3(y), lvl = level(), r = log.cur and log.cur.r, s = log.cur and log.cur.s }
		while #list > MAX_DEATHS do table.remove(list, 1) end
	end
	S.Fire("INSIGHTS_UPDATED")
end
S.RegisterEvent("PLAYER_DEAD", function() R.OnDead() end)
S.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() R.OnZone() end)
S.RegisterEvent("SKILL_LINES_CHANGED", function() R.OnSkills() end)
S.RegisterEvent("QUEST_ACCEPTED", function(_, q) R.OnAccepted(q) end)
S.RegisterEvent("QUEST_TURNED_IN", function(_, q, xp) R.OnTurnedIn(q, xp) end)
S.RegisterEvent("QUEST_REMOVED", function(_, q) R.OnRemoved(q) end)
S.RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function() R.OnCombatLog() end)
S.On("READY", function() R.Start() end)
