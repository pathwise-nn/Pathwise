-- Route audit: the leveling routes read against Pathwise's own quest data
-- (Pathwise/Data/Data.lua, from QuestieDB), one route chain at a time.
--
--   lua5.1 tools/routes/audit.lua [--free] [route id prefix]
--
-- A route chain is a first route and its `next` routes, so a quest handed
-- in on an earlier route counts later. The character's level at a step is
-- read from the route's level range, spread over its steps (a guess: good
-- enough to find quests far off it). It prints, per route:
--   PREREQ   an accept before its prerequisite is handed in (the data's
--            preSingle: one of; preGroup: all of)
--   ORPHAN   a hand-in of a quest never taken (and not started by an item)
--   DANGLING a quest taken and never handed in, on the whole chain
--   LOW      an accept whose quest is grey at that level (little XP)
--   HIGH     an accept below the quest's minimum level
--   PLACE    a goal's place far from every spawn of its NPC in the data
-- With --free, also quests on no route that cost no detour: no objectives
-- (a letter, a talk), taken from an NPC within NEAR of a stop and handed in
-- to one within NEAR of the same or a later stop, at a level that suits.
-- Its findings are leads: each fix goes into tools/port/fixes.lua by hand,
-- with a why, checked in the data.

local NEAR = 2.0 -- map percent: the same place
local PLACE_OFF = 6.0 -- map percent: a goal this far from its NPC is suspect

local args, FREE, PREFIX = arg or {}, false, nil
for _, a in ipairs(args) do if a == "--free" then FREE = true else PREFIX = a end end

local data = {}
assert(loadfile("Pathwise/Data/Data.lua"))("Pathwise", data)
local D = data.Data
local Q, N = D.quests, D.npcs

local routes, byId, isNext = {}, {}, {}
Pathwise = { RegisterRoute = function(r) routes[#routes + 1] = r byId[r.id] = r end }
assert(loadfile("Pathwise/Routes/Leveling.lua"))("Pathwise", {})
for _, r in ipairs(routes) do if r.next then isNext[r.next] = true end end

local HORDE, ALLIANCE = 178, 77 -- the classic race bits (low byte of the mask)
local function forFaction(q, faction)
	local mask = Q[q] and Q[q][4] or 0
	if mask == 0 then return true end
	local low = mask % 256
	local bits = faction == "Horde" and HORDE or ALLIANCE
	-- any shared bit: test bit by bit (Lua 5.1 has no bit ops)
	for b = 0, 7 do
		local v = 2 ^ b
		if math.floor(low / v) % 2 == 1 and math.floor(bits / v) % 2 == 1 then return true end
	end
	return false
end

local function grey(level)
	if level <= 5 then return 0 end
	if level <= 39 then return level - math.floor(level / 10) - 5 end
	return level - math.floor(level / 5) - 1
end

local function dist(m1, x1, y1, m2, x2, y2)
	if m1 ~= m2 then return math.huge end
	return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
end

-- Nearest spawn of any of the NPCs to a place, in map percent.
local function nearest(npcs, map, x, y)
	local best = math.huge
	for _, id in ipairs(npcs or {}) do
		local n = N[id]
		local sp = n and n[5] and n[5][map]
		if sp then
			for i = 1, #sp, 2 do
				local d = dist(map, x, y, map, sp[i], sp[i + 1])
				if d < best then best = d end
			end
		end
	end
	return best
end

local function spawned(npcs)
	for _, id in ipairs(npcs or {}) do if N[id] and N[id][5] and next(N[id][5]) then return true end end
	return false
end

local function prereqsDone(q, done)
	local d = Q[q]
	if not d then return true end
	local single, group = d[13], d[14]
	if single and #single > 0 then
		local any = false
		for _, p in ipairs(single) do if done[p] then any = true break end end
		if not any then return false end
	end
	if group then for _, p in ipairs(group) do if not done[p] then return false end end end
	return true
end

local function plain(step) return not step.only end

local out = {}
local function say(r, s, kind, text) out[#out + 1] = ("  %-8s %-18s step %3d  %s"):format(kind, "", s, text) end

-- Every quest any route of a faction touches.
local onRoute = { Horde = {}, Alliance = {} }
for _, r in ipairs(routes) do
	for _, st in ipairs(r.steps) do
		for _, g in ipairs(st) do
			if type(g[2]) == "number" then
				if r.faction then onRoute[r.faction][g[2]] = true
				else onRoute.Horde[g[2]] = true onRoute.Alliance[g[2]] = true end
			end
		end
	end
end

local function name(q) return Q[q] and Q[q][1] or "?" end

local function audit(chain)
	local done, taken, takenAt = {}, {}, {}
	local stops = {} -- { route, step, map, x, y, level }
	for _, r in ipairs(chain) do
		local lo, hi = r.levels and r.levels[1] or 1, r.levels and r.levels[2] or 60
		local n = #r.steps
		local lines = {}
		local function add(s, kind, text) lines[#lines + 1] = ("  %-8s step %3d  %s"):format(kind, s, text) end
		for s, st in ipairs(r.steps) do
			local level = math.floor(lo + (hi - lo) * (s - 1) / math.max(1, n - 1) + 0.5)
			for _, g in ipairs(st) do
				local verb, q = g[1], g[2]
				local d = type(q) == "number" and Q[q]
				if g.at and plain(st) then stops[#stops + 1] = { r = r, s = s, map = g.at[1], x = g.at[2], y = g.at[3], level = level, verb = verb, q = q } end
				if verb == "accept" and d then
					if plain(st) and not g.optional and not prereqsDone(q, done) then
						local pre = {}
						for _, p in ipairs(d[13] or {}) do pre[#pre + 1] = p .. " " .. name(p) end
						for _, p in ipairs(d[14] or {}) do if not done[p] then pre[#pre + 1] = "+" .. p .. " " .. name(p) end end
						add(s, "PREREQ", ("%d %s needs %s"):format(q, d[1], table.concat(pre, ", ")))
					end
					if plain(st) and not g.optional and (d[5] or 0) == 0 and d[2] and d[2] > 0 and d[2] <= grey(level) then add(s, "LOW", ("%d %s (level %d) at ~%d"):format(q, d[1], d[2], level)) end
					if d[3] and d[3] > level + 1 then add(s, "HIGH", ("%d %s (min %d) at ~%d"):format(q, d[1], d[3], level)) end
					taken[q], takenAt[q] = true, r.id .. " step " .. s
					if g.at and d[7] and spawned(d[7]) then
						local off = nearest(d[7], g.at[1], g.at[2], g.at[3])
						if off > PLACE_OFF and off < math.huge then add(s, "PLACE", ("accept %d %s: %.1f%% from its giver"):format(q, d[1], off)) end
					end
				elseif verb == "turnin" and d then
					if not taken[q] and not (d[9] and #d[9] > 0) and not (d[8] and #d[8] > 0) then
						add(s, "ORPHAN", ("%d %s handed in, never taken"):format(q, d[1]))
					end
					done[q], taken[q] = true, nil
					if g.at and d[10] and spawned(d[10]) then
						local off = nearest(d[10], g.at[1], g.at[2], g.at[3])
						if off > PLACE_OFF and off < math.huge then add(s, "PLACE", ("turnin %d %s: %.1f%% from its NPC"):format(q, d[1], off)) end
					end
				end
			end
		end
		if #lines > 0 and (not PREFIX or r.id:find(PREFIX, 1, true)) then
			print(r.id .. "  (levels " .. lo .. "-" .. hi .. ")")
			for _, l in ipairs(lines) do print(l) end
		end
	end
	local dangling = {}
	for q in pairs(taken) do dangling[#dangling + 1] = q end
	table.sort(dangling)
	local first = chain[1]
	if #dangling > 0 and (not PREFIX or first.id:find(PREFIX, 1, true)) then
		print(first.id .. " chain: taken, never handed in")
		for _, q in ipairs(dangling) do print(("  DANGLING %d %s (%s)"):format(q, name(q), takenAt[q])) end
	end
	if not FREE then return end
	-- Free quests: no objectives, for anyone of the faction (no class), the
	-- prerequisites handed in by then (on the route, or an earlier free
	-- quest), giver and receiver by stops, in order. Repeated until no more
	-- turn up, so a chain of letters comes out whole.
	local faction = first.faction
	local found, turnedAt = {}, {}
	for i, a in ipairs(stops) do
		if a.verb == "turnin" and not turnedAt[a.q] then turnedAt[a.q] = i end
	end
	local function metBy(q, i)
		local d = Q[q]
		local single, group = d[13], d[14]
		if single and #single > 0 then
			local any = false
			for _, p in ipairs(single) do if turnedAt[p] and turnedAt[p] <= i then any = true break end end
			if not any then return false end
		end
		for _, p in ipairs(group or {}) do if not (turnedAt[p] and turnedAt[p] <= i) then return false end end
		for _, p in ipairs(d[15] or {}) do if onRoute[faction][p] then return false end end
		return true
	end
	local more = true
	while more do
		more = false
		for q, d in pairs(Q) do
			if not turnedAt[q] and not onRoute[faction][q] and forFaction(q, faction) and (d[5] or 0) == 0
				and not (d[12] and #d[12] > 0) and not (d[9] and #d[9] > 0) and d[7] and d[10] and not d[16] then
				local ok = true
				for _, id in ipairs(d[7]) do local f = N[id] and N[id][4] if f and not f:find(faction == "Horde" and "H" or "A") then ok = false end end
				for i, a in ipairs(ok and stops or {}) do
					if a.level >= (d[3] or 1) and (d[2] or 0) > grey(a.level) and metBy(q, i) and nearest(d[7], a.map, a.x, a.y) <= NEAR then
						local hit, hj
						for j = i, #stops do
							local b = stops[j]
							if nearest(d[10], b.map, b.x, b.y) <= NEAR and (d[2] or 0) > grey(b.level) then hit, hj = b, j break end
						end
						if hit then
							turnedAt[q] = hj
							more = true
							found[#found + 1] = ("  FREE     %d %s (level %d): take at %s step %d, hand in at %s step %d"):format(
								q, d[1], d[2] or 0, a.r.id, a.s, hit.r.id, hit.s)
							break
						end
					end
				end
			end
		end
	end
	table.sort(found)
	if #found > 0 and (not PREFIX or first.id:find(PREFIX, 1, true)) then
		print(first.id .. " chain: quests on the way")
		for _, l in ipairs(found) do print(l) end
	end
end

for _, r in ipairs(routes) do
	if r.category == "Leveling" and not isNext[r.id] then
		local chain, seen, cur = {}, {}, r
		while cur and not seen[cur.id] do
			chain[#chain + 1] = cur
			seen[cur.id] = true
			cur = cur.next and byId[cur.next]
		end
		audit(chain)
	end
end
