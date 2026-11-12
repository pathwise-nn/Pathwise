-- Reads Pathwise Insights share codes (players send them from the game:
-- Insights > Share with Pathwise) and reports what they say about the
-- routes: how long each step really takes, the steps people skip, the ones
-- where they get stuck, and the time each level takes.
--
--   npm run insights                       every code in data/insights/
--   npm run insights -- <file or folder>... codes in those (any text: a
--                                          saved GitHub issue, a Discord export)
--   npm run insights -- --out report.txt   the report to a file as well
--
-- The codes stay out of the repository (data/insights/ is ignored): the
-- report holds only sums and medians over several players. A newer code
-- from the same character (its random id) replaces an older one.

package.path = "./?.lua;" .. package.path

local Share = assert(loadfile("Pathwise_Insights/Share.lua"))("Pathwise_Insights", {})

local MIN_PLAYERS = 3 -- a step is only flagged with this many players' times
local MAX_STEP = 6 * 3600 -- a step "taking" longer was left open (AFK, logged off)

local args, out = {}, nil
local i = 1
while arg[i] do
	if arg[i] == "--out" then out = arg[i + 1] i = i + 1 else args[#args + 1] = arg[i] end
	i = i + 1
end
if #args == 0 then args = { "data/insights" } end

local SEP = package.config:sub(1, 1)
local function filesIn(path)
	-- A file: read it. A folder: every file in it.
	local f = io.open(path, "rb")
	if f then
		local first = f:read(1)
		f:close()
		if first ~= nil then return { path } end
	end
	local list = {}
	local cmd = SEP == "\\" and ('dir /b /s /a-d "' .. path:gsub("/", "\\") .. '" 2>nul') or ('find "' .. path .. '" -type f 2>/dev/null')
	local p = io.popen(cmd)
	if p then
		for line in p:lines() do list[#list + 1] = line end
		p:close()
	end
	return list
end

-- Every code in every file; the newest per character (most time played).
local players, bad, seen = {}, {}, 0
for _, path in ipairs(args) do
	for _, file in ipairs(filesIn(path)) do
		local f = io.open(file, "rb")
		local text = f and f:read("*a") or ""
		if f then f:close() end
		for code in text:gmatch("PWI%d+:[%w%+/=%s]+:%x+") do
			seen = seen + 1
			local p, why = Share.Read(code)
			if p then
				local old = players[p.id]
				if not old or (p.played or 0) > (old.played or 0) then players[p.id] = p end
			else
				bad[#bad + 1] = file .. ": " .. tostring(why)
			end
		end
	end
end

local function median(list)
	if #list == 0 then return nil end
	table.sort(list)
	local m = (#list + 1) / 2
	return (list[math.floor(m)] + list[math.ceil(m)]) / 2
end
local function quantile(list, q)
	if #list == 0 then return nil end
	table.sort(list)
	return list[math.max(1, math.min(#list, math.floor(q * #list + 0.5)))]
end
local function dur(sec)
	if not sec then return "-" end
	sec = math.floor(sec + 0.5)
	if sec < 60 then return sec .. "s" end
	if sec < 3600 then return ("%dm%02ds"):format(math.floor(sec / 60), sec % 60) end
	return ("%dh%02dm"):format(math.floor(sec / 3600), math.floor(sec / 60) % 60)
end


-- Pathwise's data, to check where players took and handed in quests
-- against where the data puts the people and objects.
local data = {}
assert(loadfile("Pathwise/Data/Data.lua"))("Pathwise", data)
local D = data.Data
local START_NPC, START_OBJ, END_NPC, END_OBJ = 7, 8, 10, 11
local function questName(q) local d = D.quests[q] return d and d[1] or ("Quest " .. q) end

-- The nearest spot (0-100) on `map` of any of the quest's people or objects.
local function nearestOf(q, npcField, objField, map, x, y)
	local d = D.quests[q]
	if not d then return nil end
	local best, bx, by
	local function scan(spawns)
		local pts = type(spawns) == "table" and spawns[map]
		for i = 1, pts and #pts or 0, 2 do
			local dist = math.sqrt((pts[i] - x) ^ 2 + (pts[i + 1] - y) ^ 2)
			if not best or dist < best then best, bx, by = dist, pts[i], pts[i + 1] end
		end
	end
	for _, n in ipairs(d[npcField] or {}) do local npc = D.npcs[n] if npc then scan(npc[5]) end end
	for _, o in ipairs(d[objField] or {}) do local obj = D.objects[o] if obj then scan(obj[2]) end end
	return best, bx, by
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function pct(a, b) return b > 0 and math.floor(100 * a / b + 0.5) or 0 end

---------------------------------------------------------------------------
-- Sums
---------------------------------------------------------------------------

-- Routes are kept apart by the Pathwise version the steps were timed on:
-- step numbers change between releases.
local routes, levels, quests, deaths, versions, chars = {}, {}, {}, {}, {}, 0
local function route(id, version, src)
	local key = id .. (version and ("  @ " .. version) or "") .. (src == "quests" and "  [from quest logs, without Pathwise]" or "")
	local r = routes[key]
	if not r then
		r = { key = key, id = id, players = {}, finished = {}, rates = {}, steps = {} }
		routes[key] = r
	end
	return r
end
local function quest(q)
	local e = quests[q]
	if not e then
		e = { q = q, who = {}, times = {}, xp = {}, abandoned = 0, done = 0, taken = {}, handed = {} }
		quests[q] = e
	end
	return e
end

for _, p in pairs(players) do
	chars = chars + 1
	if p.version then versions[p.version] = (versions[p.version] or 0) + 1 end
	for _, s in ipairs(p.steps) do
		if s.route then
			-- Steps worked out from the quest log (players without Pathwise)
			-- are kept apart from those Pathwise's guide timed.
			local r = route(s.route, s.version, s.src)
			r.players[p.id] = true
			local st = r.steps[s.step]
			if not st then
				st = { times = {}, kills = {}, yards = {}, done = 0, skip = 0, deaths = 0, who = {}, flying = 0, grouped = 0, timed = 0 }
				r.steps[s.step] = st
			end
			st.who[p.id] = true
			if s.how == "done" and s.t > 0 and s.t <= MAX_STEP then
				st.times[#st.times + 1] = s.t
				st.done = st.done + 1
				st.deaths = st.deaths + (s.d or 0)
				if s.kills then st.kills[#st.kills + 1] = s.kills end
				if s.yards then st.yards[#st.yards + 1] = s.yards end
				st.timed = st.timed + s.t
				st.flying = st.flying + (s.flying or 0)
				st.grouped = st.grouped + (s.grouped or 0)
			elseif s.how == "skip" then
				st.skip = st.skip + 1
			end
		end
	end
	for id, b in pairs(p.routes) do
		local r = route(id, nil)
		r.players[p.id] = true
		if b.done and b.t > 0 then r.finished[#r.finished + 1] = b.t end
		if b.t >= 300 then r.rates[#r.rates + 1] = b.xp * 3600 / b.t end
	end
	for lvl, b in pairs(p.levels) do
		if b.full and b.t > 0 then
			levels[lvl] = levels[lvl] or {}
			table.insert(levels[lvl], b.t)
		end
	end
	for _, q in ipairs(p.quests) do
		local e = quest(q.quest)
		e.who[p.id] = true
		if q.abandoned then e.abandoned = e.abandoned + 1
		else
			e.done = e.done + 1
			if q.t and q.t > 0 and q.t <= MAX_STEP then e.times[#e.times + 1] = q.t end
			if q.xp and q.xp > 0 then e.xp[#e.xp + 1] = q.xp end
			if q.inMap and q.inX then table.insert(e.handed, { q.inMap, q.inX * 100, q.inY * 100 }) end
		end
		if q.takenMap and q.takenX then table.insert(e.taken, { q.takenMap, q.takenX * 100, q.takenY * 100 }) end
	end
	for _, d in ipairs(p.deaths) do
		if d.map and d.x then
			-- Grouped in squares of 2% of the map.
			local key = ("%d:%d:%d"):format(d.map, math.floor(d.x * 50), math.floor(d.y * 50))
			local e = deaths[key]
			if not e then e = { map = d.map, x = (math.floor(d.x * 50) + 0.5) * 2, y = (math.floor(d.y * 50) + 0.5) * 2, n = 0, who = {}, lvls = {}, steps = {} } deaths[key] = e end
			e.n = e.n + 1
			e.who[p.id] = true
			if d.lvl then e.lvls[#e.lvls + 1] = d.lvl end
			if d.route and d.step then
				local s = d.route .. " step " .. d.step
				e.steps[s] = (e.steps[s] or 0) + 1
			end
		end
	end
end

---------------------------------------------------------------------------
-- The report
---------------------------------------------------------------------------

local lines = {}
local function say(fmt, ...) lines[#lines + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

say("Pathwise Insights: %d characters (%d codes read, %d could not be read)", chars, seen, #bad)
for _, b in ipairs(bad) do say("  unreadable: %s", b) end
local vl = {}
for v, n in pairs(versions) do vl[#vl + 1] = ("%s (%d)"):format(v, n) end
table.sort(vl)
if #vl > 0 then say("Pathwise versions: %s", table.concat(vl, ", ")) end
say("Flags need %d or more players. SLOW: over 2.5x the route's usual step. LONG WALK: over 2.5x its usual yards.", MIN_PLAYERS)
say("")

-- Routes and their steps.
say("== Routes ==")
local list = {}
for _, r in pairs(routes) do r.n = count(r.players) list[#list + 1] = r end
table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
for _, r in ipairs(list) do
	if next(r.steps) or #r.finished > 0 then
		say("%s  (%d players%s)", r.key, r.n, #r.finished > 0 and (", " .. #r.finished .. " finished") or "")
		if #r.finished > 0 or #r.rates > 0 then
			say("  route: median %s to finish, median %s XP/h", dur(median(r.finished)),
				median(r.rates) and tostring(math.floor(median(r.rates) + 0.5)) or "-")
		end
		local mt, my = {}, {}
		for _, st in pairs(r.steps) do
			local m = median(st.times)
			if m then mt[#mt + 1] = m end
			local y = median(st.yards)
			if y then my[#my + 1] = y end
		end
		local usualT, usualY = median(mt), median(my)
		local nums = {}
		for s in pairs(r.steps) do nums[#nums + 1] = s end
		table.sort(nums)
		for _, s in ipairs(nums) do
			local st = r.steps[s]
			local n = count(st.who)
			local m, y = median(st.times), median(st.yards)
			local flags = {}
			if n >= MIN_PLAYERS and m and usualT and m > 2.5 * usualT then flags[#flags + 1] = "SLOW" end
			if n >= MIN_PLAYERS and y and usualY and usualY > 0 and y > 2.5 * usualY then flags[#flags + 1] = "LONG WALK" end
			local tried = st.done + st.skip
			if n >= MIN_PLAYERS and tried > 0 and st.skip / tried >= 0.4 then flags[#flags + 1] = "OFTEN SKIPPED" end
			if n >= MIN_PLAYERS and st.done > 0 and st.deaths / st.done >= 0.5 then flags[#flags + 1] = "DEADLY" end
			say("  step %3d  median %-8s p75 %-8s timed %-3d skipped %-3d deaths %-3d kills %-4s yards %-5s flying %3d%% grouped %3d%%%s",
				s, dur(m), dur(quantile(st.times, 0.75)), st.done, st.skip, st.deaths,
				median(st.kills) and tostring(math.floor(median(st.kills) + 0.5)) or "-",
				y and tostring(math.floor(y + 0.5)) or "-", pct(st.flying, st.timed), pct(st.grouped, st.timed),
				#flags > 0 and ("  <- " .. table.concat(flags, ", ")) or "")
		end
		say("")
	end
end

-- Quests: time, XP for the time, abandoned, and where people found the
-- people the data names.
say("== Quests ==")
local rates, qlist = {}, {}
for _, e in pairs(quests) do
	e.n = count(e.who)
	e.time, e.pay = median(e.times), median(e.xp)
	if e.time and e.pay and e.time > 0 then
		e.rate = e.pay * 60 / e.time
		rates[#rates + 1] = e.rate
	end
	qlist[#qlist + 1] = e
end
local usualRate = median(rates)
table.sort(qlist, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.q < b.q end)
for _, e in ipairs(qlist) do
	local flags = {}
	if e.n >= MIN_PLAYERS and e.rate and usualRate and e.rate < 0.4 * usualRate then flags[#flags + 1] = "SLOW FOR ITS XP" end
	local tried = e.done + e.abandoned
	if e.n >= MIN_PLAYERS and tried > 0 and e.abandoned / tried >= 0.3 then flags[#flags + 1] = "OFTEN ABANDONED" end
	-- Where players handed it in and took it, against the data.
	local where = {}
	for _, spec in ipairs({ { e.handed, END_NPC, END_OBJ, "handed in" }, { e.taken, START_NPC, START_OBJ, "taken" } }) do
		local byMap = {}
		for _, pt in ipairs(spec[1]) do
			byMap[pt[1]] = byMap[pt[1]] or { xs = {}, ys = {} }
			table.insert(byMap[pt[1]].xs, pt[2])
			table.insert(byMap[pt[1]].ys, pt[3])
		end
		for map, pts in pairs(byMap) do
			if #pts.xs >= MIN_PLAYERS then
				local x, y = median(pts.xs), median(pts.ys)
				local d, dx, dy = nearestOf(e.q, spec[2], spec[3], map, x, y)
				if not d then
					flags[#flags + 1] = ("%s at %d %.1f, %.1f: the data has no one there on that map"):format(spec[4], map, x, y)
				elseif d > 3 then
					flags[#flags + 1] = ("%s at %d %.1f, %.1f: the data says %.1f, %.1f"):format(spec[4], map, x, y, dx, dy)
				end
			end
		end
	end
	say("%6d %-34s players %-3d median %-8s %-6s XP %-6s XP/min abandoned %d%s", e.q, questName(e.q):sub(1, 34), e.n,
		dur(e.time), e.pay and tostring(math.floor(e.pay + 0.5)) or "-", e.rate and ("%.0f"):format(e.rate) or "-",
		e.abandoned, #flags > 0 and ("  <- " .. table.concat(flags, "; ")) or "")
end
say("")

-- Deaths: the spots where several players died.
local dl = {}
for _, e in pairs(deaths) do e.players = count(e.who) dl[#dl + 1] = e end
table.sort(dl, function(a, b) if a.players ~= b.players then return a.players > b.players end return a.n > b.n end)
if #dl > 0 then
	say("== Where players die (squares of 2% of the map) ==")
	for i, e in ipairs(dl) do
		if i > 25 then break end
		local top, topN = nil, 0
		for s, n in pairs(e.steps) do if n > topN then top, topN = s, n end end
		say("  map %d  %.0f, %.0f  %d deaths, %d players, median level %s%s", e.map, e.x, e.y, e.n, e.players,
			median(e.lvls) and tostring(math.floor(median(e.lvls) + 0.5)) or "-", top and ("  (mostly " .. top .. ")") or "")
	end
	say("")
end

local lv = {}
for l in pairs(levels) do lv[#lv + 1] = l end
table.sort(lv)
if #lv > 0 then
	say("== Time per level (levels seen from start to end) ==")
	for _, l in ipairs(lv) do say("  level %2d  median %-8s (%d players)", l, dur(median(levels[l])), #levels[l]) end
end

local report = table.concat(lines, "\n") .. "\n"
io.write(report)
if out then
	local f = assert(io.open(out, "wb"))
	f:write(report)
	f:close()
	io.write("written: " .. out .. "\n")
end
