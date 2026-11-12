-- Pathwise Insights: what the window shows, worked out from a character's
-- log (Recorder.lua). Nothing here changes the log.

local ADDON, ns = ...
local S = ns.S
local St = {}
ns.Stats = St

local floor = math.floor

-- 4500 -> "1 h 15", 125 -> "2 min", 40 -> "40 s"
function St.Duration(sec)
	sec = floor((sec or 0) + 0.5)
	if sec < 60 then return sec .. " s" end
	local m = floor(sec / 60)
	if m < 60 then return m .. " min" end
	return ("%d h %02d"):format(floor(m / 60), m % 60)
end

-- XP an hour, once there is at least five minutes to go on; else nil.
function St.Rate(xp, sec)
	if not sec or sec < 300 then return nil end
	return floor((xp or 0) * 3600 / sec + 0.5)
end

function St.Number(n)
	local s = tostring(floor((n or 0) + 0.5))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then return s end
	end
end

function St.RateText(xp, sec)
	local r = St.Rate(xp, sec)
	return r and (St.Number(r) .. " XP/h") or "—"
end

-- Yards to "47.1 km" (or metres under one).
function St.Distance(yards)
	local m = (yards or 0) * 0.9144
	if m < 1000 then return floor(m + 0.5) .. " m" end
	return ("%.1f km"):format(m / 1000)
end

-- "2026-10-09" -> a day number (days since 1970-01-01), with no clock API.
function St.DayNumber(key)
	local y, m, d = tostring(key):match("^(%d+)-(%d+)-(%d+)$")
	y, m, d = tonumber(y), tonumber(m), tonumber(d)
	if not y then return nil end
	if m <= 2 then y = y - 1 end
	local era = floor(y / 400)
	local yoe = y - era * 400
	local doy = floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + floor(yoe / 4) - floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
-- "2026-10-09" -> "9 Oct 2026"
function St.DayText(key)
	local y, m, d = tostring(key):match("^(%d+)-(%d+)-(%d+)$")
	if not y then return "" end
	return ("%d %s %s"):format(tonumber(d), MONTHS[tonumber(m)] or "?", y)
end

local function routeTitle(id)
	local info = S.Guide.RouteInfo(id)
	return info and info.title or tostring(id)
end
St.RouteTitle = routeTitle

local function zoneName(map)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or ("Map " .. tostring(map))
end

local function sorted(tbl, nameOf)
	local out = {}
	for k, b in pairs(tbl) do
		if (b.t or 0) >= 1 then out[#out + 1] = { key = k, name = nameOf(k), t = b.t, xp = b.xp or 0, d = b.d or 0, b = b } end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

-- The days you played, in order: { key, n }, ...
local function dayList(log)
	local out = {}
	for key, t in pairs(log.days) do
		local n = St.DayNumber(key)
		if n and t >= 1 then out[#out + 1] = { key = key, n = n, t = t } end
	end
	table.sort(out, function(a, b) return a.n < b.n end)
	return out
end

-- The tiles at the top.
function St.Totals(log)
	local days = dayList(log)
	return {
		played = log.played, xp = log.xp, rate = St.Rate(log.xp, log.played), quests = log.quests, kills = log.kills,
		deaths = log.deaths, dist = log.dist, sessions = #log.sessions, days = #days,
		first = days[1] and days[1].key, last = days[#days] and days[#days].key,
	}
end

-- Records: { key = { value, sub } }; missing when there is nothing to tell.
function St.Records(log)
	local rec = {}
	-- Levels seen from start to end (not the one you are on).
	local fast, slow
	for lvl, b in pairs(log.levels) do
		if b.full and lvl < (log.level or 0) and (b.t or 0) >= 1 then
			if not fast or b.t < fast.t then fast = { level = lvl, t = b.t } end
			if not slow or b.t > slow.t then slow = { level = lvl, t = b.t } end
		end
	end
	if fast then rec.fastLevel = { "Level " .. fast.level, St.Duration(fast.t) } end
	if slow then rec.slowLevel = { "Level " .. slow.level, St.Duration(slow.t) } end
	local best, long, most
	for _, s in ipairs(log.sessions) do
		local r = St.Rate(s.xp, s.t)
		if r and (s.t or 0) >= 600 and (not best or r > best.r) then best = { r = r, s = s } end
		if (s.t or 0) >= 1 and (not long or s.t > long.t) then long = s end
		if (s.q or 0) > 0 and (not most or s.q > most.q) then most = s end
	end
	local function dayOf(s) return St.DayText(ns.Recorder.DayKey(s.start)) end
	if best then rec.bestSession = { St.Number(best.r) .. " XP/h", dayOf(best.s) .. " · " .. St.Duration(best.s.t) } end
	if long then rec.longSession = { St.Duration(long.t), dayOf(long) } end
	if most then rec.mostQuests = { most.q .. (most.q == 1 and " quest" or " quests"), dayOf(most) } end
	local days = dayList(log)
	local big
	for _, d in ipairs(days) do if not big or d.t > big.t then big = d end end
	if big then rec.bigDay = { St.Duration(big.t), St.DayText(big.key) } end
	local run, bestRun = 0, 0
	for i, d in ipairs(days) do
		run = (i > 1 and d.n == days[i - 1].n + 1) and run + 1 or 1
		if run > bestRun then bestRun = run end
	end
	if bestRun > 0 then rec.streak = { tostring(bestRun), bestRun == 1 and "day" or "days" } end
	local r = log.records
	if r.fastQuest then rec.fastQuest = { St.Duration(r.fastQuest.t), r.fastQuest.name } end
	if r.slowQuest then rec.slowQuest = { St.Duration(r.slowQuest.t), r.slowQuest.name } end
	if r.bestQuest then rec.bestQuest = { St.Number(r.bestQuest.xp) .. " XP", r.bestQuest.name } end
	return rec
end

-- The leveling detail below the records.
function St.Detail(log)
	local out = {}
	out.routes = sorted(log.routes, routeTitle)
	out.zones = sorted(log.zones, zoneName)
	local slow = {}
	for _, st in ipairs(log.steps) do if st.how == "done" then slow[#slow + 1] = st end end
	table.sort(slow, function(a, b) return a.t > b.t end)
	while #slow > 5 do table.remove(slow) end
	out.slowest = slow
	local skipped = 0
	for _, st in ipairs(log.steps) do if st.how == "skip" then skipped = skipped + 1 end end
	out.skipped, out.recorded = skipped, #log.steps
	local levels = {}
	for lvl, b in pairs(log.levels) do if (b.t or 0) >= 1 then levels[#levels + 1] = { level = lvl, t = b.t, xp = b.xp or 0 } end end
	table.sort(levels, function(a, b) return a.level > b.level end)
	out.levels = levels
	local skills = {}
	for line, s in pairs(log.skills) do
		local prof = S.Professions and S.Professions.BY_LINE and S.Professions.BY_LINE[line]
		if (s.ups or 0) > 0 then skills[#skills + 1] = { name = prof and prof.name or ("Skill " .. line), from = s.from, to = s.to } end
	end
	table.sort(skills, function(a, b) return a.name < b.name end)
	out.skills = skills
	return out
end

-- Seconds by hour of day (0-23) and by weekday (1 = Monday).
function St.Hours(log)
	local h, w = {}, {}
	for i = 0, 23 do h[i] = log.hours[i] or 0 end
	for i = 1, 7 do w[i] = log.weekdays[i] or 0 end
	return h, w
end

-- A tab's name: "Gnome Warlock lvl 18".
function St.CharLabel(log, key)
	local who = (log.race and log.class) and (log.race .. " " .. log.class) or (log.name or key)
	return ("%s lvl %d"):format(who, log.level or 1)
end

-- The heat map of a continent: { { cell, value }, ... } and the biggest
-- value. layer: "time" (seconds) or "rate" (XP an hour, cells with a minute
-- or more).
function St.Heat(log, cont, layer)
	local out, top = {}, 0
	for cell, b in pairs(log.heat[cont] or {}) do
		local v
		if layer == "rate" then v = (b.t or 0) >= 60 and (b.xp or 0) * 3600 / b.t or nil
		else v = b.t or 0 end
		if v and v > 0 then
			out[#out + 1] = { cell = cell, v = v }
			if v > top then top = v end
		end
	end
	return out, top
end

-- The maps with a trail or heat, by time spent: { { id, name, t } }.
local function maps(log, names)
	local out = {}
	for cont, name in pairs(names) do
		local t = 0
		for _, b in pairs(log.heat[cont] or {}) do t = t + (b.t or 0) end
		out[#out + 1] = { id = cont, name = name, t = t }
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

function St.Continents(log) return maps(log, log.conts) end
-- The zones you spent the most time in (the first `limit`).
function St.Zones(log, limit)
	local out = maps(log, log.zonemaps or {})
	while limit and #out > limit do table.remove(out) end
	return out
end
