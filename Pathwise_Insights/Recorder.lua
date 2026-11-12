-- Pathwise Insights: the recorder. While you level with Pathwise it writes
-- down, for this character only, how long each guide step took, the XP it
-- gave, deaths, skips, time and XP per zone and per level, and profession
-- skill-ups. Everything stays in PathwiseInsightsLog (saved per character,
-- in WTF\Account\...\SavedVariables): nothing leaves your computer.
--
-- Time is the time you are playing: AFK, loading screens and long hitches
-- are not counted.

local ADDON, ns = ...
local S = Pathwise.Suite
local R = {}
ns.Recorder = R

local SCHEMA = 1
local MAX_STEPS = 1000 -- the oldest step records go first
local HITCH = 2 -- a frame longer than this (a loading screen) is not counted

S.Defaults("insights", { record = true, minimap = true, minimapAngle = 165 })

local function now() return time and time() or 0 end

-- The saved log, made fresh when missing or of another layout.
function R.Log()
	local log = PathwiseInsightsLog
	if type(log) ~= "table" or log.schema ~= SCHEMA then
		log = { schema = SCHEMA }
		PathwiseInsightsLog = log
	end
	log.since = log.since or now()
	log.played = log.played or 0 -- seconds counted
	log.xp = log.xp or 0
	log.deaths = log.deaths or 0
	log.steps = type(log.steps) == "table" and log.steps or {} -- { r, s, t, xp, d, lvl, how }, oldest first
	log.routes = type(log.routes) == "table" and log.routes or {} -- id -> { t, xp, d, steps, skips, done }
	log.zones = type(log.zones) == "table" and log.zones or {} -- map -> { t, xp, d, lvl }
	log.levels = type(log.levels) == "table" and log.levels or {} -- level -> { t, xp, d }
	log.skills = type(log.skills) == "table" and log.skills or {} -- line -> { from, to, ups }
	return log
end

function R.Clear()
	PathwiseInsightsLog = nil
	R.Start(true)
	S.Fire("INSIGHTS_UPDATED")
end

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

-- Where the counted time and XP go: the step, its route, the zone, the level.
local zone
local function targets(log)
	local out = {}
	local cur = log.cur
	if cur then
		out[#out + 1] = cur
		out[#out + 1] = bucket(log.routes, cur.r)
	end
	if zone then out[#out + 1] = bucket(log.zones, zone) end
	out[#out + 1] = bucket(log.levels, level())
	return out
end

local TOTAL = { t = "played", xp = "xp", d = "deaths" }
local function add(field, n)
	if not recording() or n <= 0 then return end
	local log = R.Log()
	log[TOTAL[field]] = log[TOTAL[field]] + n
	for _, b in ipairs(targets(log)) do b[field] = (b[field] or 0) + n end
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
	local list = log.steps
	list[#list + 1] = { r = cur.r, s = cur.s, t = math.floor(cur.t + 0.5), xp = cur.xp or 0, d = cur.d or 0, lvl = cur.lvl, how = how }
	while #list > MAX_STEPS do table.remove(list, 1) end
	local route = bucket(log.routes, cur.r)
	if how == "skip" then route.skips = (route.skips or 0) + 1
	elseif how == "done" then route.steps = (route.steps or 0) + 1 end
end

local function open(log, route, step)
	if step then
		log.cur = { r = route, s = step, t = 0, xp = 0, d = 0, lvl = level() }
	else
		bucket(log.routes, route).done = true -- the route is finished
	end
end

-- Pathwise's GUIDE_STEP (Guide/Engine.lua): the live step moved.
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
	open(log, info.route, info.step)
	S.Fire("INSIGHTS_UPDATED")
end
S.On("GUIDE_STEP", R.OnStep)

---------------------------------------------------------------------------
-- The game: time, XP, deaths, zones, skills
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
		elseif lvl == lastLevel + 1 then gain = (lastMax - lastXP) + xp
		end
		if gain and gain > 0 then add("xp", gain) end
	end
	lastXP, lastMax, lastLevel = xp, max, lvl
end

local function afk() return UnitIsAFK and UnitIsAFK("player") end

-- Counts `sec` seconds of play, unless you are AFK.
function R.Play(sec)
	if afk() then return end
	add("t", sec)
end

-- Every frame: a frame longer than HITCH (a loading screen) is not play.
function R.Tick(elapsed)
	if not elapsed or elapsed <= 0 or elapsed > HITCH then return end
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

-- Starts (or, after Clear, restarts) the recorder at login.
function R.Start(cleared)
	R.Log()
	lastXP = nil
	R.OnXP()
	R.OnZone()
	R.OnSkills()
	if cleared then
		local id = S.Guide.Route()
		local step = S.Guide.Step()
		if id and step and recording() then open(R.Log(), id, step) end
	end
end

local clock = CreateFrame("Frame")
clock:SetScript("OnUpdate", function(_, elapsed) R.Tick(elapsed) end)

S.RegisterEvent("PLAYER_XP_UPDATE", function() R.OnXP() end)
S.RegisterEvent("PLAYER_LEVEL_UP", function() R.OnXP() end)
S.RegisterEvent("PLAYER_DEAD", function() add("d", 1) S.Fire("INSIGHTS_UPDATED") end)
S.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() R.OnZone() end)
S.RegisterEvent("SKILL_LINES_CHANGED", function() R.OnSkills() end)
S.On("READY", function() R.Start() end)
