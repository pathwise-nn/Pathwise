-- Pathwise Insights: the share code. A character's leveling numbers, made
-- into one line of text the player copies and sends (a GitHub form, the
-- Pathwise Discord). Nothing is sent from the game.
--
-- What goes in, all of it for tuning the routes:
--   the character: race, class, faction, level, time played, XP, the
--     Pathwise version
--   each guide step timed: route, step, the Pathwise version it was timed on
--     (step numbers change between releases), seconds, XP, deaths, kills,
--     yards walked, seconds on a flight and in a group, the level, how it
--     ended (done, skipped, ...) and where (zone and x, y)
--   each quest: seconds from taking it to handing it in (played time), the
--     XP it paid, the level, where it was taken and handed in, or abandoned
--   each death: where, at what level, on which step
--   each route's, level's and zone's time, XP and deaths
-- A random id (made once per character, not from its name) lets a newer code
-- replace an older one. What never goes in: the character's name, realm,
-- guild, its path on the map, or anything about other players.
--
-- The codec has no game calls: tools/insights/import.lua loads this file to
-- read the codes.
--
--   PWI1:<base64 of the lines>:<checksum>
--   h|1|<id>|<race>|<class>|<faction>|<level>|<played>|<xp>|<quests>|<deaths>|<version>
--   r|<n>|<route id>                          route ids by number
--   V|<n>|<Pathwise version>                  versions by number
--   s|<route n>|<step>|<t>|<xp>|<d>|<lvl>|<how>|<version n>|<kills>|<yards>|<flying>|<grouped>|<map>|<x>|<y>|<src>
--       how: d s k m y l (done skip marked moved sync login); x, y in thousandths;
--       src: g (Pathwise's guide said where you were) or q (your quest log, without Pathwise)
--   q|<quest>|<t>|<xp>|<lvl>|<map taken>|<x>|<y>|<map handed in>|<x>|<y>|<abandoned 0/1>|<at>
--       at: played seconds when it was handed in (or abandoned): quests in order, to
--       line them up against a route even for players not following Pathwise
--   x|<map>|<x>|<y>|<lvl>|<route n>|<step>    a death
--   o|<route n>|<t>|<xp>|<d>|<steps>|<skips>|<done 0/1>
--   v|<level>|<t>|<xp>|<d>|<full 0/1>
--   z|<map>|<t>|<xp>|<d>|<lvl>

local ADDON, ns = ...
ns = ns or {}
local Sh = {}
ns.Share = Sh

Sh.VERSION = 1
Sh.MAX_STEPS = 600 -- the newest; older ones are left out to keep the code short
Sh.MAX_QUESTS = 600
Sh.MAX_DEATHS = 200

local floor = math.floor

---------------------------------------------------------------------------
-- Base64 and a checksum, in plain Lua 5.1 (no bit library)
---------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local DEC = {}
for i = 1, 64 do DEC[B64:sub(i, i)] = i - 1 end

function Sh.Encode64(s)
	local out = {}
	for i = 1, #s, 3 do
		local a, b, c = s:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1, c2 = floor(n / 262144) % 64, floor(n / 4096) % 64
		local c3, c4 = floor(n / 64) % 64, n % 64
		out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
			.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

function Sh.Decode64(s)
	s = s:gsub("[^%w%+/=]", "")
	if #s % 4 ~= 0 then return nil end
	local out = {}
	for i = 1, #s, 4 do
		local q = { s:byte(i, i + 3) }
		local n, pad = 0, 0
		for k = 1, 4 do
			local ch = string.char(q[k])
			if ch == "=" then pad = pad + 1 n = n * 64
			else
				local v = DEC[ch]
				if not v then return nil end
				n = n * 64 + v
			end
		end
		local a, b, c = floor(n / 65536) % 256, floor(n / 256) % 256, n % 256
		out[#out + 1] = string.char(a)
		if pad < 2 then out[#out + 1] = string.char(b) end
		if pad < 1 then out[#out + 1] = string.char(c) end
	end
	return table.concat(out)
end

-- A short checksum: a pasted code cut short or changed by hand is caught.
function Sh.Checksum(s)
	local a, b = 1, 0
	for i = 1, #s do
		a = (a + s:byte(i)) % 65521
		b = (b + a) % 65521
	end
	return ("%x"):format(b * 65536 + a)
end

---------------------------------------------------------------------------
-- Making a code
---------------------------------------------------------------------------

local HOW = { done = "d", skip = "s", marked = "k", moved = "m", sync = "y", login = "l" }
local HOW_BACK = {}
for k, v in pairs(HOW) do HOW_BACK[v] = k end

-- Text fields may not hold the separator.
local function clean(v) return (tostring(v == nil and "" or v):gsub("[|\n\r:]", " ")) end
local function int(v) return floor((tonumber(v) or 0) + 0.5) end
local function opt(v) return v ~= nil and floor((tonumber(v) or 0) + 0.5) or "" end

-- A random id for the character, made once (from the clock and random
-- numbers, never from its name).
function Sh.NewId()
	local chars = "abcdefghijkmnpqrstuvwxyz23456789"
	local t = {}
	for i = 1, 10 do
		local k = math.random(1, #chars)
		t[i] = chars:sub(k, k)
	end
	return table.concat(t)
end

-- The lines of a code, from a character's log (Recorder.lua).
function Sh.Lines(log)
	local lines = {}
	local function add(...)
		local parts = { ... }
		for i = 1, select("#", ...) do parts[i] = clean(parts[i]) end
		lines[#lines + 1] = table.concat(parts, "|")
	end
	local S = ns.S
	add("h", Sh.VERSION, log.shareId or "", log.race, log.class, log.faction, int(log.level), int(log.played),
		int(log.xp), int(log.quests), int(log.deaths), S and S.VERSION or "")
	local vIndex, vn = {}, 0
	local function version(v)
		if v == nil then return "" end
		if not vIndex[v] then
			vn = vn + 1
			vIndex[v] = vn
			add("V", vn, v)
		end
		return vIndex[v]
	end
	-- The routes, by number.
	local index, n = {}, 0
	local function route(id)
		if not index[id] then
			n = n + 1
			index[id] = n
			add("r", n, id)
		end
		return index[id]
	end
	local steps = log.steps or {}
	local first = math.max(1, #steps - Sh.MAX_STEPS + 1)
	for i = first, #steps do
		local s = steps[i]
		add("s", route(s.r), int(s.s), int(s.t), int(s.xp), int(s.d), int(s.lvl), HOW[s.how] or "d", version(s.v),
			opt(s.k), opt(s.yd), opt(s.fly), opt(s.grp), opt(s.m), opt(s.x), opt(s.y), s.src == "quests" and "q" or "g")
	end
	local quests = log.questLog or {}
	for i = math.max(1, #quests - Sh.MAX_QUESTS + 1), #quests do
		local q = quests[i]
		add("q", int(q.q), opt(q.t), int(q.xp), opt(q.lvl), opt(q.am), opt(q.ax), opt(q.ay), opt(q.tm), opt(q.tx), opt(q.ty),
			q.ab and 1 or 0, opt(q.at))
	end
	local deaths = log.deathLog or {}
	for i = math.max(1, #deaths - Sh.MAX_DEATHS + 1), #deaths do
		local d = deaths[i]
		add("x", opt(d.m), opt(d.x), opt(d.y), opt(d.lvl), d.r and route(d.r) or "", opt(d.s))
	end
	for id, b in pairs(log.routes or {}) do
		if (b.t or 0) >= 1 then
			add("o", route(id), int(b.t), int(b.xp), int(b.d), int(b.steps), int(b.skips), b.done and 1 or 0)
		end
	end
	for lvl, b in pairs(log.levels or {}) do
		if (b.t or 0) >= 1 then add("v", int(lvl), int(b.t), int(b.xp), int(b.d), b.full and 1 or 0) end
	end
	for map, b in pairs(log.zones or {}) do
		if (b.t or 0) >= 1 then add("z", int(map), int(b.t), int(b.xp), int(b.d), int(b.lvl)) end
	end
	return lines
end

-- The code: "PWI1:<base64>:<checksum>".
function Sh.Make(log)
	local body = Sh.Encode64(table.concat(Sh.Lines(log), "\n"))
	return ("PWI%d:%s:%s"):format(Sh.VERSION, body, Sh.Checksum(body))
end

---------------------------------------------------------------------------
-- Reading a code (the import tool, and the tests)
---------------------------------------------------------------------------

-- -> a table { id, race, class, faction, level, played, xp, questCount,
-- deathCount, version, steps = { {...} }, quests = { {...} }, deaths = { {...} },
-- routes = { id -> {...} }, levels = { lvl -> {...} }, zones = { map -> {...} } },
-- or nil and why.
function Sh.Read(code)
	code = tostring(code or ""):gsub("%s", "")
	local ver, body, sum = code:match("PWI(%d+):([%w%+/=]+):(%x+)")
	if not ver then return nil, "not a Pathwise Insights code" end
	if tonumber(ver) ~= Sh.VERSION then return nil, "a code from another version (" .. ver .. ")" end
	if Sh.Checksum(body) ~= sum then return nil, "the code is cut short or changed" end
	local text = Sh.Decode64(body)
	if not text then return nil, "the code does not decode" end
	local out = { steps = {}, routes = {}, levels = {}, zones = {}, quests = {}, deaths = {} }
	local ids, versions = {}, {}
	for line in text:gmatch("[^\n]+") do
		local f = {}
		for part in (line .. "|"):gmatch("([^|]*)|") do f[#f + 1] = part end
		local kind = f[1]
		local num = function(i) return tonumber(f[i]) or 0 end
		local maybe = function(i) return tonumber(f[i]) end
		if kind == "h" then
			out.id, out.race, out.class, out.faction = f[3], f[4], f[5], f[6]
			out.level, out.played, out.xp, out.questCount, out.deathCount = num(7), num(8), num(9), num(10), num(11)
			out.version = f[12] ~= "" and f[12] or nil
		elseif kind == "r" then
			ids[num(2)] = f[3]
		elseif kind == "V" then
			versions[num(2)] = f[3]
		elseif kind == "s" then
			out.steps[#out.steps + 1] = { route = ids[num(2)], step = num(3), t = num(4), xp = num(5), d = num(6),
				lvl = num(7), how = HOW_BACK[f[8]] or "done", version = versions[maybe(9) or -1], kills = maybe(10),
				yards = maybe(11), flying = maybe(12), grouped = maybe(13), map = maybe(14),
				x = maybe(15) and maybe(15) / 1000, y = maybe(16) and maybe(16) / 1000,
				src = f[17] == "q" and "quests" or "guide" }
		elseif kind == "q" then
			out.quests[#out.quests + 1] = { quest = num(2), t = maybe(3), xp = num(4), lvl = maybe(5),
				takenMap = maybe(6), takenX = maybe(7) and maybe(7) / 1000, takenY = maybe(8) and maybe(8) / 1000,
				inMap = maybe(9), inX = maybe(10) and maybe(10) / 1000, inY = maybe(11) and maybe(11) / 1000, abandoned = f[12] == "1",
				at = maybe(13) }
		elseif kind == "x" then
			out.deaths[#out.deaths + 1] = { map = maybe(2), x = maybe(3) and maybe(3) / 1000, y = maybe(4) and maybe(4) / 1000,
				lvl = maybe(5), route = ids[maybe(6) or -1], step = maybe(7) }
		elseif kind == "o" then
			local id = ids[num(2)]
			if id then out.routes[id] = { t = num(3), xp = num(4), d = num(5), steps = num(6), skips = num(7), done = f[8] == "1" } end
		elseif kind == "v" then
			out.levels[num(2)] = { t = num(3), xp = num(4), d = num(5), full = f[6] == "1" }
		elseif kind == "z" then
			out.zones[num(2)] = { t = num(3), xp = num(4), d = num(5), lvl = num(6) }
		end
	end
	if not out.id or out.id == "" then return nil, "the code has no id" end
	return out
end

---------------------------------------------------------------------------
-- In game: the character's code (the window's Share tab draws it)
---------------------------------------------------------------------------

local S = ns.S
if not S then return Sh end -- read by the import tool: the codec only

Sh.GITHUB_FORM = "https://github.com/pathwise-nn/Pathwise/issues/new?template=leveling_numbers.yml"

-- The character's code, with its id made the first time.
function Sh.CodeFor(key)
	local R = ns.Recorder
	local log = R.Log(key)
	log.shareId = log.shareId or Sh.NewId()
	return Sh.Make(log), log
end

-- The Share tab of the window (Window.lua, Win.DrawShare) shows the code.
function Sh.Open(key)
	ns.Window.Open("share", key)
end

return Sh
