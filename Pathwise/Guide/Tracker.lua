-- Pathwise leveling tracker: how fast you are levelling and how long each
-- level took, per character.
--   * this session: XP gained, XP per hour, time to the next level at that
--     pace, rested XP
--   * per level: time played at it, counted while logged in (and set right
--     whenever the game reports /played: TIME_PLAYED_MSG)
-- Nothing asks the game for /played itself (that prints in chat).

local ADDON, ns = ...
local K = {}
ns.Tracker = K

ns.Defaults("tracker", { shown = true })

-- One value from the game; nil when it has none, or keeps it secret (a boss
-- fight: comparing a secret is an error).
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local v = ns.Compat.Readable((fn(...)))
	if type(v) == "number" then return v end
	return nil
end
local function now() return call(GetTime) or 0 end
local function readXP() return call(UnitXP, "player"), call(UnitXPMax, "player") end
local function xp() local cur, max = readXP() return cur or 0, max or 0 end
local function level() return call(UnitLevel, "player") or 1 end
K.Level = level

local function state()
	local c = ns.CharState()
	c.tracker = type(c.tracker) == "table" and c.tracker or {}
	local t = c.tracker
	t.levels = type(t.levels) == "table" and t.levels or {} -- level -> seconds played at it
	t.atLevel = tonumber(t.atLevel) or 0 -- seconds at the current level before this session
	return t
end

local session = { start = nil, gained = 0, lastXP = 0, lastMax = 0, since = nil }

function K.Start()
	local t = state()
	session.start, session.since, session.gained = now(), now(), 0
	session.lastXP, session.lastMax = xp()
	t.level = t.level or level()
	if t.level ~= level() then t.level, t.atLevel = level(), 0 end
end

-- Seconds played at the current level, this session included.
function K.LevelSeconds()
	local t = state()
	return t.atLevel + (session.since and (now() - session.since) or 0)
end

local function bank()
	local t = state()
	t.atLevel = K.LevelSeconds()
	session.since = now()
end

function K.OnXP()
	local cur, max = readXP()
	if not (cur and max) then return end -- secret for now: counted at the next readable update
	if cur >= session.lastXP then session.gained = session.gained + (cur - session.lastXP)
	else session.gained = session.gained + (session.lastMax - session.lastXP) + cur end -- a level up in between
	session.lastXP, session.lastMax = cur, max
	ns.Fire("TRACKER_UPDATED")
end

function K.OnLevelUp(newLevel)
	local t = state()
	local old = (tonumber(newLevel) or level()) - 1
	t.levels[old] = K.LevelSeconds()
	t.level, t.atLevel, session.since = tonumber(newLevel) or level(), 0, now()
	ns.Fire("TRACKER_UPDATED")
end

function K.OnTimePlayed(_, thisLevel)
	if type(thisLevel) ~= "number" then return end
	state().atLevel, session.since = thisLevel, now()
end

-- { xpPerHour, secondsToLevel, gained, rested, levelSeconds }; rates nil in
-- the first minute.
function K.Stats()
	local elapsed = session.start and (now() - session.start) or 0
	local cur, max = xp()
	local rate = (elapsed >= 60 and session.gained > 0) and session.gained / (elapsed / 3600) or nil
	local eta = rate and max > cur and (max - cur) / rate * 3600 or nil
	return {
		xpPerHour = rate, secondsToLevel = eta, gained = session.gained,
		rested = call(GetXPExhaustion) or 0, levelSeconds = K.LevelSeconds(),
		percent = max > 0 and cur / max or 0,
	}
end

-- "1h 05m", "18m", "45s"
function K.Duration(s)
	s = math.floor((s or 0) + 0.5)
	if s >= 3600 then return (ns.L("%dh %02dm")):format(math.floor(s / 3600), math.floor(s % 3600 / 60)) end
	if s >= 60 then return (ns.L("%dm")):format(math.floor(s / 60)) end
	return (ns.L("%ds")):format(s)
end

local function short(n)
	if n >= 1000 then return (ns.L("%.1fk")):format(n / 1000) end
	return tostring(math.floor(n + 0.5))
end

-- The guide window's line: "Level 14 · 62% · 23.4k XP/h · 18m to 15".
function K.Line()
	if not ns.Get("tracker.shown") then return nil end
	local s = K.Stats()
	local parts = { (ns.L("Level %d")):format(level()), ("%d%%"):format(math.floor(s.percent * 100)) }
	if s.xpPerHour then parts[#parts + 1] = short(s.xpPerHour) .. ns.L(" XP/h") end
	if s.secondsToLevel then parts[#parts + 1] = (ns.L("%s to %d")):format(K.Duration(s.secondsToLevel), level() + 1) end
	return table.concat(parts, "  ·  ")
end

-- Every level's time: { { level, seconds }, ... } from 1 up.
function K.Levels()
	local out = {}
	for lvl, secs in pairs(state().levels) do out[#out + 1] = { level = tonumber(lvl), seconds = secs } end
	table.sort(out, function(a, b) return a.level < b.level end)
	return out
end

function K.Reset()
	local t = state()
	t.levels, t.atLevel = {}, 0
	session.since = now()
	ns.Fire("TRACKER_UPDATED")
end

ns.On("READY", function() K.Start() end)
ns.RegisterEvent("PLAYER_XP_UPDATE", function() K.OnXP() end)
ns.RegisterEvent("PLAYER_LEVEL_UP", function(_, newLevel) K.OnLevelUp(newLevel) end)
ns.RegisterEvent("TIME_PLAYED_MSG", function(_, total, thisLevel) K.OnTimePlayed(total, thisLevel) end)
ns.RegisterEvent("PLAYER_LOGOUT", function() bank() end)
