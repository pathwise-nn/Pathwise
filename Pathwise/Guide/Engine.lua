-- Pathwise guide engine: routes, the current step, what each goal's status is,
-- where the arrow points, skipping, alternatives, and a side guide (a
-- profession route followed beside the leveling one).
--
-- A route lists actions; the facts (names, NPCs, places, objectives) come
-- from the data (Guide/Quests.lua) unless the route gives them. Progress is
-- read from the game every time, never stored: what is saved per character is
-- the route chosen, the side guide, the quests skipped, the extra quests
-- picked as alternatives, the step being looked at and the places reached.
--
-- Route definition:
--   Pathwise.RegisterRoute({
--     id, title, category = "Leveling" | "Class" | "Professions", map,
--     levels = { min, max }, faction = "Horde" | "Alliance" | nil,
--     races = { "Scourge", 5, ... } (race file names or IDs), classes = { "MAGE" },
--     next = "<route id>",
--     steps = {
--       { title, note, only = { classes, races, factions }, when = { { k = "onquest"|"turnedin", q } },
--         { "accept", q, at = { map, x, y }, who = "NPC", name = "Quest", optional, only }, ... },
--     },
--   })
-- Goals:
--   { "accept", q }  { "turnin", q }  { "complete", q }       quests (log)
--   { "goto", map, x, y, "label" }                            reached when the arrow arrives
--   { "level", n }  { "note", "text" }
--   { "have", item, count, name = }                           items owned
--   { "bind", "Brill", at = }                                 the hearthstone's inn
--   { "skill", skillLine, level }  { "train", skillLine, rankMax }
--   { "learn", spell, name = }  { "craft", spell, name =, untilSkill =, item =, count = }
-- Any goal may carry optional = true (never holds the step), only = {...},
-- at = { map, x, y } (where to go), who = "name", from = { { map, x, y, name, faction }, ... }.

local ADDON, ns = ...
local Q = ns.Quests
local C = ns.Compat
local Engine = {}
ns.Engine = Engine
Pathwise.Engine = Engine

local routes, routeOrder = {}, {}
Engine.routes = routes

-- Ids routes had before; a saved choice under an old id finds the new route.
local ALIASES = { ["horde/undead/tirisfal"] = "forever/horde/undead/01-tirisfal-glades" }

---------------------------------------------------------------------------
-- Routes
---------------------------------------------------------------------------

local VERBS = {
	accept = 2, turnin = 2, complete = 2, ["goto"] = 4, level = 2, note = 2,
	have = 3, bind = 2, skill = 3, train = 3, learn = 2, craft = 2,
}
local QUEST_VERBS = { accept = true, turnin = true, complete = true }

-- Problems found in a route: { "step 3: unknown verb 'x'", ... }.
function Engine.Check(def)
	local problems = {}
	if type(def) ~= "table" or type(def.id) ~= "string" or type(def.steps) ~= "table" then
		return { "a route needs an id and steps" }
	end
	for i, step in ipairs(def.steps) do
		if #step == 0 then problems[#problems + 1] = ("step %d: no goals"):format(i) end
		for _, g in ipairs(step) do
			local need = VERBS[g[1]]
			if not need then
				problems[#problems + 1] = ("step %d: unknown verb '%s'"):format(i, tostring(g[1]))
			elseif #g < need then
				problems[#problems + 1] = ("step %d: '%s' needs %d values"):format(i, g[1], need - 1)
			elseif QUEST_VERBS[g[1]] and not Q.Get(g[2]) and not g.name then
				problems[#problems + 1] = ("step %d: quest %s is not in the data"):format(i, tostring(g[2]))
			end
		end
	end
	return problems
end

function Pathwise.RegisterRoute(def)
	local problems = Engine.Check(def)
	if #problems > 0 then
		ns.Error("route " .. tostring(def and def.id), table.concat(problems, "; "))
		return false
	end
	if not routes[def.id] then routeOrder[#routeOrder + 1] = def.id end
	routes[def.id] = def
	return true
end

function Engine.Routes()
	local out = {}
	for _, id in ipairs(routeOrder) do out[#out + 1] = routes[id] end
	return out
end

-- Race names: the client's file names ("Scourge"), with "Undead" as the same.
local function sameRace(a, p)
	if type(a) == "number" then return a == p.raceID end
	if a == p.race then return true end
	if (a == "Undead" or a == "Scourge") and (p.race == "Undead" or p.race == "Scourge") then return true end
	return false
end

local function inList(list, fn)
	for _, v in ipairs(list) do if fn(v) then return true end end
	return false
end

-- Whether a route (or a step's `only`) is for this character.
local function fits(def, p)
	if def.faction and p.faction and def.faction ~= p.faction then return false end
	local races = def.races
	if races and #races > 0 and not inList(races, function(r) return sameRace(r, p) end) then return false end
	local classes = def.classes
	if classes and #classes > 0 and not inList(classes, function(c) return c == p.class end) then return false end
	local factions = def.factions
	if factions and #factions > 0 and not inList(factions, function(f) return f == p.faction end) then return false end
	return true
end
Engine.Fits = fits

-- The routes of a category for this character, by their starting level.
function Engine.RoutesFor(p, category)
	p = p or Q.Player()
	local out = {}
	for _, id in ipairs(routeOrder) do
		local r = routes[id]
		if (not category or (r.category or "Leveling") == category) and fits(r, p) then out[#out + 1] = r end
	end
	table.sort(out, function(a, b)
		local la, lb = a.levels and a.levels[1] or 1, b.levels and b.levels[1] or 1
		if la ~= lb then return la < lb end
		return a.id < b.id
	end)
	return out
end

-- The leveling route that suits the character now: one for their level whose
-- zone they stand in, else one for their level (their race's own first),
-- else the nearest above their level.
function Engine.BestRoute(p, map)
	p = p or Q.Player()
	local list = Engine.RoutesFor(p, "Leveling")
	local best, bestScore
	for _, r in ipairs(list) do
		local lo, hi = r.levels[1], r.levels[2]
		local score
		if p.level >= lo and p.level <= hi then
			score = 0
			if map and r.map == map then score = score - 100 end
			if r.races then score = score - 10 end
			score = score + (p.level - lo) * 0.1
		elseif p.level < lo then
			score = 50 + (lo - p.level)
		else
			score = 200 + (p.level - hi)
		end
		if not bestScore or score < bestScore then best, bestScore = r, score end
	end
	return best
end

---------------------------------------------------------------------------
-- Per-character state
---------------------------------------------------------------------------

local function state()
	local c = ns.CharState()
	c.guide = type(c.guide) == "table" and c.guide or {}
	local g = c.guide
	g.skipped = type(g.skipped) == "table" and g.skipped or {}
	g.extras = type(g.extras) == "table" and g.extras or {}
	g.reached = type(g.reached) == "table" and g.reached or {}
	if g.route and not routes[g.route] and ALIASES[g.route] then g.route = ALIASES[g.route] end
	return g
end
Engine.State = state

function Engine.Route()
	local id = state().route
	return id and routes[id]
end

function Engine.SetRoute(id)
	if id and not routes[id] then return false end
	local s = state()
	s.route, s.pin = id, nil
	Engine.Update()
	return true
end

function Engine.Side()
	local id = state().side
	return id and routes[id]
end

-- The side guide (a profession route) shown in the detour card.
function Engine.SetSide(id)
	if id and not routes[id] then return false end
	local s = state()
	s.side, s.aimSide, s.sideHidden = id, nil, nil
	Engine.Update()
	return true
end

---------------------------------------------------------------------------
-- Goal status: "done", "open", "na" (not for this character, skipped or
-- closed), "wait" (an accept not offered yet: a prerequisite or the level;
-- it does not hold the route, which comes back to it once it opens),
-- "info" (a note: never holds the step)
---------------------------------------------------------------------------

local player

local function skipped(q) return state().skipped[q] ~= nil end

local function questStatus(verb, q)
	if skipped(q) or not Q.ForPlayer(q, player) then return "na" end
	if verb == "accept" then
		if Q.OnQuest(q) or Q.Done(q) then return "done" end
		if Q.Closed(q) then return "na" end
		if not Q.PrereqsMet(q) or Q.MinLevel(q) > (player.level or 1) then return "wait" end
		return "open"
	elseif verb == "turnin" then
		if Q.Done(q) then return "done" end
		if not Q.OnQuest(q) then return "na" end -- never taken or abandoned: nothing to hand in
		return "open"
	else -- complete
		if Q.Done(q) or (Q.OnQuest(q) and Q.Ready(q)) then return "done" end
		if not Q.OnQuest(q) then return "na" end
		return "open"
	end
end

local function goalKey(route, s, g) return route.id .. ":" .. s .. ":" .. g end

local function bindMatches(where)
	local loc = C.BindLocation()
	if not (loc and where) then return false end
	loc, where = loc:lower(), where:lower()
	return loc == where or loc:find(where, 1, true) ~= nil or where:find(loc, 1, true) ~= nil
end

local function goalStatus(route, s, g, goal)
	if goal.only and not fits(goal.only, player) then return "na" end
	local verb = goal[1]
	if QUEST_VERBS[verb] then return questStatus(verb, goal[2]) end
	if verb == "level" then return (player.level or 1) >= goal[2] and "done" or "open" end
	if verb == "goto" then return state().reached[goalKey(route, s, g)] and "done" or "open" end
	if verb == "have" then return C.ItemCount(goal[2]) >= (goal[3] or 1) and "done" or "open" end
	if verb == "bind" then return bindMatches(goal[2]) and "done" or "open" end
	if verb == "skill" then
		local rank = C.SkillRank(goal[2])
		return rank and rank >= goal[3] and "done" or "open"
	end
	if verb == "train" then
		local _, cap = C.SkillRank(goal[2])
		return cap and cap >= goal[3] and "done" or "open"
	end
	if verb == "learn" then return C.SpellKnown(goal[2]) and "done" or "open" end
	if verb == "craft" then
		if goal.untilSkill and goal.skillLine then
			local rank = C.SkillRank(goal.skillLine)
			return rank and rank >= goal.untilSkill and "done" or "open"
		end
		if goal.item and goal.count then return C.ItemCount(goal.item) >= goal.count and "done" or "open" end
		return "info"
	end
	return "info"
end

-- A step applies when it is for this character and its conditions hold.
local function whenHolds(step)
	for _, w in ipairs(step.when or {}) do
		local qs = type(w.q) == "table" and w.q or { w.q }
		local any = false
		for _, q in ipairs(qs) do
			if (w.k == "onquest" and Q.OnQuest(q)) or (w.k == "turnedin" and Q.Done(q)) then any = true end
		end
		if (w.k == "onquest" or w.k == "turnedin") and not any then return false end
	end
	return true
end

local function stepApplies(step)
	return (not step.only or fits(step.only, player)) and whenHolds(step)
end

local function stepOpen(route, s)
	local step = route.steps[s]
	if not stepApplies(step) then return false end
	for g, goal in ipairs(step) do
		if not goal.optional and goalStatus(route, s, g, goal) == "open" then return true end
	end
	return false
end

local function firstOpen(route)
	if not route then return nil end
	for s = 1, #route.steps do
		if stepOpen(route, s) then return s end
	end
	return nil
end

-- Extra quests the player picked (alternatives): a virtual step each, ahead of
-- the route, until done. Returns the first open one: { quest, verb }.
local function openExtra()
	local s = state()
	local keep = {}
	local first
	for _, q in ipairs(s.extras) do
		if not Q.Done(q) and not skipped(q) and not Q.Closed(q) then
			keep[#keep + 1] = q
			if not first then
				local verb = not Q.OnQuest(q) and "accept" or (Q.Ready(q) and "turnin" or "complete")
				first = { quest = q, verb = verb }
			end
		end
	end
	s.extras = keep
	return first
end

---------------------------------------------------------------------------
-- The current step
---------------------------------------------------------------------------

local live, current, extra, sideLive

local function compute()
	player = Q.Player()
	extra = openExtra()
	local s = state()
	local route = Engine.Route()
	live = firstOpen(route)
	-- A finished route hands over to the next one, when it is for this character.
	local hops = 0
	while route and not live and route.next and routes[route.next] and fits(routes[route.next], player) and hops < 5 do
		hops = hops + 1
		route = routes[route.next]
		s.route, s.pin = route.id, nil
		live = firstOpen(route)
		ns.Print(("on to the next route: %s."):format(route.title))
	end
	local pin = s.pin
	if pin and route and route.steps[pin] and pin ~= live then current = pin
	else
		s.pin = nil
		current = live
	end
	local side = Engine.Side()
	local before = sideLive
	sideLive = firstOpen(side)
	if sideLive ~= before then s.aimSide, s.sideHidden = nil, nil end
end

-- For other modules (the profession dashboard): any route's first open step,
-- and a goal's status, read now.
function Engine.FirstOpen(route)
	player = player or Q.Player()
	return firstOpen(route)
end
function Engine.GoalStatus(route, s, g, goal)
	player = player or Q.Player()
	return goalStatus(route, s, g, goal)
end
function Engine.Refresh() player = Q.Player() end

function Engine.LiveStep() return live end
function Engine.CurrentStep() return current end
function Engine.Extra() return extra end
function Engine.SideStep() return sideLive end

local function here()
	local map, x, y = C.PlayerMapPosition()
	return map and { map = map, x = x, y = y } or nil
end

-- The best of a goal's candidates: this side's, on the player's map, nearest.
local function pickFrom(list, from)
	local best, bestD
	for _, c in ipairs(list) do
		local f = c[5]
		local ok = not f or f == "AH" or (player.faction == "Horde" and f:find("H")) or (player.faction == "Alliance" and f:find("A"))
		if ok then
			local d = 1e9
			if from and from.map == c[1] then d = (c[2] - from.x) ^ 2 + (c[3] - from.y) ^ 2 end
			if not bestD or d < bestD then best, bestD = c, d end
		end
	end
	return best
end

local function qname(goal) return goal.name or Q.Name(goal[2]) end

-- Where a goal leads: { map, x, y, name } or nil.
local function placeOf(goal)
	local verb, q = goal[1], goal[2]
	local from = here()
	local function atPlace(name)
		local a = goal.at
		return a and { map = a[1], x = a[2], y = a[3], name = name } or nil
	end
	if verb == "accept" then return atPlace(goal.who) or Q.Giver(q, from) end
	if verb == "turnin" then return atPlace(goal.who) or Q.Finisher(q, from) end
	if verb == "complete" then
		local log = Q.Objectives(q)
		for i = 1, Q.ObjectiveCount(q) do
			if not (log and log[i] and log[i].done) then
				local p = Q.ObjectivePlace(q, i, from)
				if p then return p end
			end
		end
		return atPlace(qname(goal)) or Q.ObjectivePlace(q, 1, from)
	end
	if verb == "goto" then return { map = goal[2], x = goal[3], y = goal[4], name = goal[5] } end
	if goal.from then
		local c = pickFrom(goal.from, from)
		if c then return { map = c[1], x = c[2], y = c[3], name = c[4] } end
	end
	if verb == "bind" then return atPlace(goal.who or ("Innkeeper, " .. tostring(goal[2]))) end
	if verb == "have" or verb == "learn" then return atPlace(goal.name) end
	return nil
end
Engine.PlaceOf = placeOf

local RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local VERB_TEXT = { accept = "Accept %s", turnin = "Turn in %s", complete = "Complete %s" }

local function goalText(goal)
	local verb = goal[1]
	if VERB_TEXT[verb] then return VERB_TEXT[verb]:format(qname(goal)) end
	if verb == "goto" then return goal[5] or "Go to the marked spot" end
	if verb == "level" then return ("Reach level %d"):format(goal[2]) end
	if verb == "have" then
		local name = goal.name or (Q.Data.items[goal[2]] and Q.Data.items[goal[2]][1]) or ("item " .. goal[2])
		local n = goal[3] or 1
		return n > 1 and ("Get %d %s (%d)"):format(n, name, C.ItemCount(goal[2])) or ("Get " .. name)
	end
	if verb == "bind" then return ("Make %s your home"):format(goal[2] or "this inn") end
	if verb == "skill" then return ("Reach %s %d"):format(goal.name or "skill", goal[3]) end
	if verb == "train" then return ("Train %s %s"):format(RANKS[goal[3]] or "", goal.name or "") end
	if verb == "learn" then return "Learn " .. (goal.name or "the recipe") end
	if verb == "craft" then
		if goal.untilSkill then return ("Craft %s until %d"):format(goal.name or "it", goal.untilSkill) end
		if goal.count then return ("Craft %d %s"):format(goal.count, goal.name or "") end
		return "Craft " .. (goal.name or "")
	end
	return goal[2]
end
Engine.GoalText = goalText

-- The goal the arrow and the window lead with in step s of a route.
local function leadIn(route, s)
	if not (route and s) then return nil end
	for g, goal in ipairs(route.steps[s]) do
		if goalStatus(route, s, g, goal) == "open" and placeOf(goal) then return goal, g end
	end
	return nil
end

local function leadGoal()
	if extra then return { extra.verb, extra.quest } end
	local s = state()
	if s.aimSide and sideLive then
		local goal, g = leadIn(Engine.Side(), sideLive)
		if goal then return goal, g, true end
	end
	return leadIn(Engine.Route(), current)
end

---------------------------------------------------------------------------
-- What the window shows
---------------------------------------------------------------------------

local function titleOf(step, route, s)
	if step.title and step.title ~= "" then return step.title end
	for _, goal in ipairs(step) do
		if goal[1] == "complete" then return qname(goal) end
	end
	for g, goal in ipairs(step) do
		if goalStatus(route, s, g, goal) == "open" then
			local p = placeOf(goal)
			if p and p.name then return p.name end
		end
	end
	return goalText(step[1])
end

local function rowsOf(route, s)
	local rows = {}
	for g, goal in ipairs(route.steps[s]) do
		local st = goalStatus(route, s, g, goal)
		if st ~= "na" and st ~= "wait" then
			if goal[1] == "complete" and st == "open" then
				local log = Q.Objectives(goal[2])
				if log then
					for _, o in ipairs(log) do rows[#rows + 1] = { text = o.text, have = o.have, need = o.need, done = o.done } end
				else
					rows[#rows + 1] = { text = goalText(goal) }
				end
			else
				rows[#rows + 1] = { text = goalText(goal), done = st == "done", info = st == "info", optional = goal.optional }
			end
		end
	end
	return rows
end

local function textOf(step)
	if step.note and step.note ~= "" then return step.note end
	for _, goal in ipairs(step) do
		if goal[1] == "complete" then return Q.Text(goal[2]) end
	end
	return nil
end

local function coordsOf(p)
	if not (p and p.x) then return nil end
	local zone = C.MapName(p.map)
	local h = here()
	local xy = ("%.1f, %.1f"):format(p.x, p.y)
	if zone and not (h and h.map == p.map) then xy = xy .. "  ·  " .. zone end
	return xy
end

local function progressOf(route)
	local done, total = 0, 0
	for s = 1, #route.steps do
		if stepApplies(route.steps[s]) then
			total = total + 1
			if not stepOpen(route, s) then done = done + 1 end
		end
	end
	return done / math.max(1, total)
end

local function nextSummary(route, from)
	for s = from + 1, #route.steps do
		if stepOpen(route, s) then
			for g, goal in ipairs(route.steps[s]) do
				if goalStatus(route, s, g, goal) == "open" then return goalText(goal) end
			end
		end
	end
	return nil
end

-- How far a profession step may be from the player for its card to show:
-- "speed" and "balanced" only when it is on the way (yards), "craft" always.
ns.Defaults("professions", { detour = "balanced" })
Engine.DETOUR_YARDS = { speed = 150, balanced = 600 }

-- Yards from the player to a place, or nil (no position, other continent).
local function yardsTo(p)
	local h = here()
	if not (h and p) then return nil end
	local i1, n1, w1 = C.MapToWorld(h.map, h.x, h.y)
	local i2, n2, w2 = C.MapToWorld(p.map, p.x, p.y)
	if not (i1 and i2) or i1 ~= i2 then return nil end
	return math.sqrt((n2 - n1) ^ 2 + (w2 - w1) ^ 2)
end

-- The side guide's card: its next goal, or nil (none, hidden by the player,
-- or not on the way for the detour mode).
local function sideCard()
	local side = Engine.Side()
	local s = state()
	if not (side and sideLive) or s.sideHidden == sideLive then return nil end
	local step = side.steps[sideLive]
	local text
	for g, goal in ipairs(step) do
		if goalStatus(side, sideLive, g, goal) == "open" then text = goalText(goal) break end
	end
	local goal = leadIn(side, sideLive)
	local p = goal and placeOf(goal)
	local yards = p and yardsTo(p)
	local budget = Engine.DETOUR_YARDS[ns.Get("professions.detour")]
	if budget and p and not s.aimSide and (not yards or yards > budget) then return nil end
	local sub
	if s.aimSide then sub = "The arrow leads here now"
	elseif not p then sub = "Wherever you are"
	elseif yards then sub = ("%s  ·  %s"):format(p.name or step.title or "On your way", ns.Nav.FormatYards(yards))
	else sub = p.name or step.title end
	return {
		label = "Optional · " .. side.title,
		text = text or titleOf(step, side, sideLive),
		sub = sub, aimed = s.aimSide, yards = yards,
	}
end

function Engine.View()
	local route = Engine.Route()
	if extra then
		local goal = { extra.verb, extra.quest }
		local p = placeOf(goal)
		local rows = {}
		if extra.verb == "complete" then
			for _, o in ipairs(Q.Objectives(extra.quest) or {}) do rows[#rows + 1] = { text = o.text, have = o.have, need = o.need, done = o.done } end
		else
			rows[1] = { text = goalText(goal) }
		end
		return {
			route = route and route.title or "Extra quest", extra = true,
			index = route and live or nil, count = route and #route.steps or nil,
			progress = route and progressOf(route) or 0,
			title = Q.Name(extra.quest),
			text = extra.verb == "complete" and Q.Text(extra.quest) or (p and p.name and ((extra.verb == "accept" and "From " or "To ") .. p.name)) or nil,
			coords = coordsOf(p), objectives = rows, detour = sideCard(),
			next = route and live and ("Then back to the route: " .. (titleOf(route.steps[live], route, live) or "")) or nil,
		}
	end
	if not route then
		local card = sideCard()
		if not card then return nil end
		return { route = "No leveling route", title = "Choose a route", text = "Open Routes in Settings, or Zones for your level.", objectives = {}, detour = card, progress = 0 }
	end
	if not current then
		return {
			route = route.title, index = #route.steps, count = #route.steps, progress = 1,
			title = "Route complete", detour = sideCard(),
			text = "Pick your next route from Zones for your level, or Routes in Settings.",
			objectives = {},
		}
	end
	local step = route.steps[current]
	local lead = leadIn(route, current)
	local p = lead and placeOf(lead)
	return {
		route = route.title, index = current, count = #route.steps, progress = progressOf(route),
		title = titleOf(step, route, current), text = textOf(step), coords = coordsOf(p),
		objectives = rowsOf(route, current), next = nextSummary(route, current),
		pinned = current ~= live, detour = sideCard(),
	}
end

---------------------------------------------------------------------------
-- Updating: the window and the arrow, after game events
---------------------------------------------------------------------------

local lastWaypoint

local function updateWaypoint()
	local goal = leadGoal()
	local p = goal and placeOf(goal)
	local key = p and ("%d:%.2f:%.2f"):format(p.map, p.x, p.y) or nil
	if key == lastWaypoint then return end
	lastWaypoint = key
	if p then ns.Nav.SetTarget(p.map, p.x, p.y, p.name or goalText(goal)) else ns.Nav.Clear() end
end

function Engine.Update()
	compute()
	if ns.Guide and ns.Guide.SetView then ns.Guide.SetView(Engine.View()) end
	updateWaypoint()
	ns.Fire("GUIDE_UPDATED")
end

-- Events come in bursts: one update a moment after the last.
local pending = false
function Engine.Schedule()
	if pending then return end
	pending = true
	local function run() pending = false Engine.Update() end
	if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end

for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP",
	"ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "HEARTHSTONE_BOUND", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB",
	"NEW_RECIPE_LEARNED", "TRADE_SKILL_LIST_UPDATE" }) do
	ns.RegisterEvent(ev, Engine.Schedule)
end

-- "Go to" goals are reached by arriving: the arrow says so.
ns.On("WAYPOINT_ARRIVED", function()
	local goal, g, onSide = leadGoal()
	if goal and goal[1] == "goto" then
		local route = onSide and Engine.Side() or Engine.Route()
		local s = onSide and sideLive or current
		if route and s then
			state().reached[goalKey(route, s, g)] = true
			Engine.Schedule()
		end
	end
end)

ns.On("DETOUR_GO", function()
	local s = state()
	s.aimSide = not s.aimSide or nil
	lastWaypoint = nil
	Engine.Update()
end)

ns.On("DETOUR_SKIP", function()
	local s = state()
	s.sideHidden, s.aimSide = sideLive, nil
	lastWaypoint = nil
	Engine.Update()
end)

ns.On("READY", function()
	local s = state()
	if not s.route then
		local best = Engine.BestRoute(Q.Player(), (C.PlayerMapPosition()))
		if best then s.route = best.id end
	end
	Engine.Update()
end)

---------------------------------------------------------------------------
-- A report of the step shown, for "Report this step": plain text the player
-- copies into Discord or an issue. Nothing is sent anywhere.
---------------------------------------------------------------------------

function Engine.ReportText()
	compute()
	local lines = {}
	local function add(s) lines[#lines + 1] = s end
	local version = ns.VERSION
	local build = GetBuildInfo and select(1, GetBuildInfo()) or "?"
	add(("Pathwise %s report  ·  client %s  ·  data %s"):format(version, tostring(build), tostring(Q.Data.SOURCE)))
	local route = Engine.Route()
	if route then
		add(("Route: %s (%s)  ·  step %s of %d, live step %s"):format(route.title, route.id, tostring(current), #route.steps, tostring(live)))
		local step = current and route.steps[current]
		if step then
			add("Step: " .. (titleOf(step, route, current) or "?"))
			for g, goal in ipairs(step) do
				local verb = goal[1]
				local what = QUEST_VERBS[verb] and ("%s %d %s"):format(verb, goal[2], qname(goal)) or goalText(goal)
				local log = ""
				if QUEST_VERBS[verb] then
					local q = goal[2]
					log = ("  [log: %s%s%s]"):format(Q.OnQuest(q) and "on quest" or "not in log", Q.Done(q) and ", done" or "",
						Q.OnQuest(q) and Q.Ready(q) and ", ready" or "")
					for _, o in ipairs(Q.Objectives(q) or {}) do
						log = log .. (" %s %s/%s;"):format(o.text, tostring(o.have), tostring(o.need))
					end
				end
				add(("  %d. %s: %s%s"):format(g, goalStatus(route, current, g, goal), what, log))
			end
		end
	else
		add("Route: none")
	end
	if extra then add(("Extra quest: %d %s (%s)"):format(extra.quest, Q.Name(extra.quest), extra.verb)) end
	local p = Q.Player()
	add(("Character: %s %s, level %d, %s"):format(tostring(p.race), tostring(p.class), p.level or 0, tostring(p.faction)))
	local map, x, y = C.PlayerMapPosition()
	add(map and ("Position: map %d (%s) %.2f, %.2f"):format(map, C.MapName(map) or "?", x, y) or "Position: none")
	local t = ns.Nav.Target()
	add(t and ("Arrow: %s, map %d %.2f, %.2f"):format(tostring(t.title), t.map, t.x, t.y) or "Arrow: none")
	add("What went wrong: ")
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Navigation (Back / Next look at other steps; they change nothing)
---------------------------------------------------------------------------

function Engine.Back()
	local route = Engine.Route()
	if not (route and current) then return end
	state().pin = math.max(1, current - 1)
	Engine.Update()
end

function Engine.Next()
	local route = Engine.Route()
	if not route then return end
	local to = (current or #route.steps) + 1
	if to > #route.steps then return end
	state().pin = to
	if to == live then state().pin = nil end
	Engine.Update()
end

function Engine.BackToLive()
	state().pin = nil
	Engine.Update()
end

---------------------------------------------------------------------------
-- Skipping and alternatives
---------------------------------------------------------------------------

-- The open quests of the step shown (what Skip offers).
function Engine.SkippableQuests()
	local out, seen = {}, {}
	if extra then return { extra.quest } end
	local route = Engine.Route()
	if not (route and current) then return out end
	for g, goal in ipairs(route.steps[current]) do
		local q = goal[2]
		if QUEST_VERBS[goal[1]] and not seen[q] and goalStatus(route, current, g, goal) == "open" then
			seen[q] = true
			out[#out + 1] = q
		end
	end
	return out
end

-- Skip quest q (and, with followUps, every quest that needs it, as far as
-- the data knows). Returns the quests skipped.
function Engine.SkipQuest(q, followUps)
	local s = state()
	local list = { q }
	s.skipped[q] = followUps and "chain" or true
	if followUps then
		local queue, seen = { q }, { [q] = true }
		local n = 0
		while #queue > 0 and n < 200 do
			n = n + 1
			for _, f in ipairs(Q.FollowUps(table.remove(queue, 1))) do
				if not seen[f] then
					seen[f] = true
					s.skipped[f] = "chain"
					list[#list + 1] = f
					queue[#queue + 1] = f
				end
			end
		end
	end
	Engine.Update()
	return list
end

function Engine.UnskipQuest(q)
	state().skipped[q] = nil
	Engine.Update()
end

function Engine.Skipped()
	local out = {}
	for q in pairs(state().skipped) do out[#out + 1] = q end
	table.sort(out)
	return out
end

-- Quests to do instead: for this character, at their level, available now
-- (prerequisites met, not closed), not already part of the route ahead,
-- given on the map the player is on; nearest giver first.
-- -> { { quest, name, level, giver, yards }, ... }
function Engine.Alternatives(limit)
	limit = limit or 5
	player = Q.Player()
	local from = here()
	if not from then return {} end
	local inRoute = {}
	local route = Engine.Route()
	if route then
		for s = live or 1, #route.steps do
			for _, goal in ipairs(route.steps[s]) do
				if QUEST_VERBS[goal[1]] then inRoute[goal[2]] = true end
			end
		end
	end
	local _, pn, pw = C.MapToWorld(from.map, from.x, from.y)
	local list = {}
	for id, q in pairs(Q.Data.quests) do
		local level, minLevel = q[2] or 0, q[3] or 0
		if level >= player.level - 2 and level <= player.level + 3 and minLevel <= player.level
			and not inRoute[id] and not q[16] and not skipped(id) and Q.ForPlayer(id, player) then
			local giver = Q.Giver(id, from)
			if giver and giver.map == from.map and not Q.Done(id) and not Q.OnQuest(id)
				and Q.PrereqsMet(id) and not Q.Closed(id) then
				local yards
				local _, gn, gw = C.MapToWorld(giver.map, giver.x, giver.y)
				if pn and gn then yards = math.sqrt((gn - pn) ^ 2 + (gw - pw) ^ 2) end
				list[#list + 1] = { quest = id, name = Q.Name(id), level = level, giver = giver.name, yards = yards }
			end
		end
	end
	table.sort(list, function(a, b)
		if (a.yards or 1e9) ~= (b.yards or 1e9) then return (a.yards or 1e9) < (b.yards or 1e9) end
		return a.quest < b.quest
	end)
	while #list > limit do table.remove(list) end
	return list
end

function Engine.AddExtra(q)
	local s = state()
	for _, x in ipairs(s.extras) do if x == q then return end end
	s.extras[#s.extras + 1] = q
	s.skipped[q] = nil
	Engine.Update()
end

-- Zones for the player's level: { { map, name, low, high, route }, ... }.
-- `route` is the leveling route for that zone that suits the character.
function Engine.Zones()
	player = Q.Player()
	local out = {}
	local byMap = {}
	for _, r in ipairs(Engine.RoutesFor(player, "Leveling")) do
		local cur = byMap[r.map]
		local fitsLevel = player.level >= r.levels[1] - 2 and player.level <= r.levels[2] + 1
		if r.map and (not cur or (fitsLevel and not cur.fitsLevel)) then byMap[r.map] = { route = r, fitsLevel = fitsLevel } end
	end
	for _, z in ipairs(Q.ZonesFor(player.level, player.faction)) do
		z.name = C.MapName(z.map) or ("Map " .. z.map)
		z.route = byMap[z.map] and byMap[z.map].route
		out[#out + 1] = z
	end
	return out
end
