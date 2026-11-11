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
--   { "complete", q, obj = { 1, 3 } }                         only those objectives
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

---------------------------------------------------------------------------
-- One action per step
---------------------------------------------------------------------------
-- Routes are written a place at a time (everything to do in Brill in one
-- step). Leveling and class routes are followed an action at a time: each
-- place step is split, as it registers, into steps of their own:
--   * the actions at one person in a row stay together ("Talk to Holland":
--     hand in, then accept)
--   * every other action is a step of its own (each quest to complete, each
--     place to go, each item to get)
--   * notes and optional goals go with the next action (a last one with the
--     one before), so "Hearth to Brill" shows with what you do there
--   * the place's title, `only` and `when` go to every part; its note to
--     the first
-- route.split[old step] = { first, last } and route.goalAt[old][g] =
-- { step, goal } say where each went (saved marks from before are moved).

local SPLIT_CATEGORIES = { Leveling = true, Class = true }
local AT_PERSON = { accept = true, turnin = true, bind = true, train = true }

-- Who a goal is done with, for keeping a person's actions together.
local function personOf(goal)
	if not AT_PERSON[goal[1]] then return nil end
	if goal.who then return goal.who end
	if goal.at then return ("%s:%s:%s"):format(goal.at[1], goal.at[2], goal.at[3]) end
	local p = goal[1] == "accept" and Q.Giver(goal[2]) or (goal[1] == "turnin" and Q.Finisher(goal[2])) or nil
	return p and p.name or nil
end

local function carries(goal) return goal[1] == "note" or goal.optional end

local function splitRoute(def)
	local out, split, goalAt = {}, {}, {}
	for s, step in ipairs(def.steps) do
		goalAt[s] = {}
		local anchors = 0
		for _, goal in ipairs(step) do if not carries(goal) then anchors = anchors + 1 end end
		local first = #out + 1
		if anchors == 0 then
			out[#out + 1] = step
			for g in ipairs(step) do goalAt[s][g] = { #out, g } end
		else
			local cur, curPerson, carry = nil, nil, {}
			local function newStep()
				cur = { title = step.title, only = step.only, when = step.when, note = (#out + 1 == first) and step.note or nil }
				out[#out + 1] = cur
			end
			for g, goal in ipairs(step) do
				if carries(goal) then
					carry[#carry + 1] = { g, goal }
				else
					local person = personOf(goal)
					if not cur or not person or person ~= curPerson or #carry > 0 then newStep() end
					curPerson = person
					for _, c in ipairs(carry) do
						cur[#cur + 1] = c[2]
						goalAt[s][c[1]] = { #out, #cur }
					end
					carry = {}
					cur[#cur + 1] = goal
					goalAt[s][g] = { #out, #cur }
				end
			end
			for _, c in ipairs(carry) do -- after the last action: with it
				cur[#cur + 1] = c[2]
				goalAt[s][c[1]] = { #out, #cur }
			end
		end
		split[s] = { first, #out }
	end
	local copy = {}
	for k, v in pairs(def) do copy[k] = v end
	copy.steps, copy.split, copy.goalAt, copy.placeSteps = out, split, goalAt, def.steps
	return copy
end
Engine.SplitRoute = splitRoute

function Pathwise.RegisterRoute(def)
	local problems = Engine.Check(def)
	if #problems > 0 then
		ns.Error("route " .. tostring(def and def.id), table.concat(problems, "; "))
		return false
	end
	if SPLIT_CATEGORIES[def.category or "Leveling"] and def.split ~= false then def = splitRoute(def) end
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

-- Each route's quests ({ [q] = true }), cached by route.
local questSets = setmetatable({}, { __mode = "k" })
local function questsOf(r)
	local set = questSets[r]
	if set then return set end
	set = {}
	for _, step in ipairs(r.steps) do
		for _, goal in ipairs(step) do
			if QUEST_VERBS[goal[1]] then set[goal[2]] = true end
		end
	end
	questSets[r] = set
	return set
end

-- How many of route r's quests are in the player's quest log.
function Engine.HeldIn(r)
	if not r then return 0 end
	local set, n = questsOf(r), 0
	for _, q in ipairs(Q.LogQuests()) do
		if set[q] then n = n + 1 end
	end
	return n
end

-- The leveling route that suits the character now: among those for their
-- level, the one holding the most quests in their quest log (a character who
-- comes to Pathwise at level 20 with Westfall quests gets Westfall), then
-- the one whose zone they stand in, else one for their level (their race's
-- own first), else the nearest above their level.
function Engine.BestRoute(p, map)
	p = p or Q.Player()
	local list = Engine.RoutesFor(p, "Leveling")
	local best, bestScore
	for _, r in ipairs(list) do
		local lo, hi = r.levels[1], r.levels[2]
		local score
		if p.level >= lo and p.level <= hi then
			score = -1000 * Engine.HeldIn(r)
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
	g.stepsDone = type(g.stepsDone) == "table" and g.stepsDone or {} -- "route:step" -> true, marked by the player
	if g.route and not routes[g.route] and ALIASES[g.route] then g.route = ALIASES[g.route] end
	if g.layout ~= 2 then Engine.MoveMarks(g) end
	return g
end

-- Saved before routes were split an action at a time: marks by place step
-- moved to the new steps ("route:12" -> each step it became; places reached
-- likewise). The step being looked at is let go.
function Engine.MoveMarks(g)
	local done, reached = {}, {}
	for key, v in pairs(g.stepsDone) do
		local id, s = key:match("^(.*):(%d+)$")
		local r = id and routes[id]
		local span = r and r.split and r.split[tonumber(s)]
		if span then
			for n = span[1], span[2] do done[id .. ":" .. n] = v end
		elseif not (r and r.split) then
			done[key] = v
		end
	end
	for key, v in pairs(g.reached) do
		local id, s, gi = key:match("^(.*):(%d+):(%d+)$")
		local r = id and routes[id]
		local at = r and r.goalAt and r.goalAt[tonumber(s)] and r.goalAt[tonumber(s)][tonumber(gi)]
		if at then reached[("%s:%d:%d"):format(id, at[1], at[2])] = v
		elseif not (r and r.split) then reached[key] = v end
	end
	g.stepsDone, g.reached, g.pin, g.layout = done, reached, nil, 2
end
Engine.State = state

function Engine.Route()
	local id = state().route
	return id and routes[id]
end

function Engine.SetRoute(id)
	if id and not routes[id] then return false end
	local s = state()
	-- Picked by the player (the zones and routes panels, /pw route): its
	-- quests stay in even when the character has outlevelled the route.
	s.route, s.pin, s.picked, s.chosen = id, nil, nil, id
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

-- A "complete" can be for some of a quest's objectives (obj = { 1 }): the
-- route splits the quest over several steps, one place each.
local function wantsObjective(goal, i)
	if not goal.obj then return true end
	for _, k in ipairs(goal.obj) do if k == i then return true end end
	return false
end
Engine.WantsObjective = wantsObjective

local function objectivesDone(goal)
	local log = Q.Objectives(goal[2])
	if not log then return false end
	for _, i in ipairs(goal.obj) do
		if not (log[i] and log[i].done) then return false end
	end
	return true
end

local function goalKey(route, s, g) return route.id .. ":" .. s .. ":" .. g end

-- A "go to" is only a way to the quests, so it also counts as done once the
-- player is past it: every quest of its step is done (or not for them), or
-- they have done a quest further along the route. Without this, a character
-- who did the quests without walking past each waypoint (or before the
-- guide was installed) stays stuck on old waypoints.
local furthest = {} -- route id -> last step with a quest done, this update
local function stepQuestsDone(route, s)
	local any = false
	for _, goal in ipairs(route.steps[s]) do
		if QUEST_VERBS[goal[1]] and not (goal.only and not fits(goal.only, player)) then
			local st = questStatus(goal[1], goal[2])
			if st == "done" then any = true elseif st ~= "na" then return false end
		end
	end
	return any
end
local function furthestDone(route)
	local f = furthest[route.id]
	if f then return f end
	f = 0
	for s = #route.steps, 1, -1 do
		local step = route.steps[s]
		for _, goal in ipairs(step) do
			if QUEST_VERBS[goal[1]] and not (goal.only and not fits(goal.only, player))
				and questStatus(goal[1], goal[2]) == "done" then f = s break end
		end
		if f > 0 then break end
	end
	furthest[route.id] = f
	return f
end
-- A profession route has no quests to say how far along you are: there,
-- the last step whose skill, craft-until or training goal you already meet
-- does. A step before it is behind you, though its materials are used up.
-- Read live (no cache): the skill changes between guide updates.
local function furthestSkill(route)
	for s = #route.steps, 1, -1 do
		for _, goal in ipairs(route.steps[s]) do
			local verb, rank, cap = goal[1], nil, nil
			if verb == "skill" or verb == "train" then rank, cap = C.SkillRank(goal[2])
			elseif verb == "craft" and goal.untilSkill and goal.skillLine then rank = C.SkillRank(goal.skillLine) end
			if (verb == "skill" and rank and rank >= goal[3])
				or (verb == "train" and cap and cap >= goal[3])
				or (verb == "craft" and rank and goal.untilSkill and rank >= goal.untilSkill) then
				return s
			end
		end
	end
	return 0
end

local function passed(route, s)
	return stepQuestsDone(route, s) or s < furthestDone(route)
end

local function bindMatches(where)
	local loc = C.BindLocation()
	if not (loc and where) then return false end
	loc, where = loc:lower(), where:lower()
	return loc == where or loc:find(where, 1, true) ~= nil or where:find(loc, 1, true) ~= nil
end

-- Quests you have passed (guide.skipPassed, on by default): on a leveling
-- route, a quest more than 2 levels below the character (green or grey) in a
-- step behind the last quest done on the route, or anywhere on a route whose
-- top level the character is 2 past, is left out ("na"), unless a quest from
-- 2 levels below up that the route still has to do needs it first (its
-- follow-ups, as far as the data knows). A quest in the log goes the same
-- way until it is ready to hand in. Going back for it is a detour.
ns.Defaults("guide", { skipPassed = true })
local followCache = {} -- q -> Q.FollowUps(q): static data, read once
local function followUps(q)
	local f = followCache[q]
	if not f then
		f = Q.FollowUps(q)
		followCache[q] = f
	end
	return f
end
local neededCache = {} -- "route:q" -> bool, this update
local function neededAhead(route, q, level)
	local key = route.id .. ":" .. q
	local v = neededCache[key]
	if v ~= nil then return v end
	v = false
	local set = questsOf(route)
	local seen, queue, n = { [q] = true }, { q }, 0
	while #queue > 0 and n < 200 and not v do
		n = n + 1
		for _, f in ipairs(followUps(table.remove(queue, 1))) do
			if not seen[f] then
				seen[f] = true
				if set[f] and not Q.Done(f) and Q.Level(f) >= level - 2 then
					v = true
					break
				end
				queue[#queue + 1] = f
			end
		end
	end
	neededCache[key] = v
	return v
end
local function passedLow(route, s, q)
	if not ns.Get("guide.skipPassed") or (route.category or "Leveling") ~= "Leveling" then return false end
	local level = player.level or 1
	local lvl = Q.Level(q)
	if not (lvl > 0 and lvl < level - 2) then return false end
	local outgrown = route.levels and route.levels[2] and level >= route.levels[2] + 2
		and state().chosen ~= route.id
	if not (outgrown or s < furthestDone(route)) then return false end
	if Q.OnQuest(q) and Q.Ready(q) then return false end
	return not neededAhead(route, q, level)
end
Engine.PassedLow = function(route, s, q)
	player = player or Q.Player()
	return passedLow(route, s, q)
end

local function goalStatus(route, s, g, goal)
	if goal.only and not fits(goal.only, player) then return "na" end
	if state().stepsDone[route.id .. ":" .. s] and goal[1] ~= "note" then return "done" end
	local verb = goal[1]
	if QUEST_VERBS[verb] then
		local st = questStatus(verb, goal[2])
		if st == "open" and verb == "complete" and goal.obj and objectivesDone(goal) then return "done" end
		if (st == "open" or st == "wait") and passedLow(route, s, goal[2]) then return "na" end
		return st
	end
	if verb == "level" then return (player.level or 1) >= goal[2] and "done" or "open" end
	if verb == "goto" then return (state().reached[goalKey(route, s, g)] or passed(route, s)) and "done" or "open" end
	-- An item to fetch: had, or behind you (a quest further on done: the item
	-- may have gone into it, as Samuel's Remains do into Marla's Last Wish).
	if verb == "have" then
		return (C.ItemCount(goal[2]) >= (goal[3] or 1) or s < furthestDone(route) or s < furthestSkill(route)) and "done" or "open"
	end
	if verb == "bind" then return bindMatches(goal[2]) and "done" or "open" end
	if verb == "skill" then
		local rank = C.SkillRank(goal[2])
		return rank and rank >= goal[3] and "done" or "open"
	end
	if verb == "train" then
		local _, cap = C.SkillRank(goal[2])
		return cap and cap >= goal[3] and "done" or "open"
	end
	if verb == "learn" then return (C.SpellKnown(goal[2]) or s < furthestSkill(route)) and "done" or "open" end
	if verb == "craft" then
		if goal.untilSkill and goal.skillLine then
			local rank = C.SkillRank(goal.skillLine)
			return rank and rank >= goal.untilSkill and "done" or "open"
		end
		if goal.item and goal.count then
			return (C.ItemCount(goal.item) >= goal.count or s < furthestSkill(route)) and "done" or "open"
		end
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
local nearby = {} -- Engine.Nearby(): the quest-log stops of this update

-- Whether race, class and side can be read: until then no route is chosen
-- or let go (Forever can hide them, and they can be nil early at login).
local function known(p) return p.race ~= nil and p.class ~= nil and p.faction ~= nil end
Engine.Known = known

-- The route and side guide are for the character played: one saved for
-- another race, side or class (a deleted character of the same name, or a
-- route picked by id) is let go, and with no route the one that suits the
-- character is chosen.
local function ownRoutes(s)
	if not known(player) then return end
	local route = Engine.Route()
	if route and not fits(route, player) then
		s.route, s.pin = nil, nil
		ns.Print(("%s is not for this character: choosing one that is."):format(route.title))
	end
	if not s.route then
		local best = Engine.BestRoute(player, (C.PlayerMapPosition()))
		if best then s.route, s.picked = best.id, best.id end
	end
	-- Picked for the player before the quest log could say where they are
	-- (it can be empty for a moment at login): while nothing on the picked
	-- route is done or held, a route holding quests in their log wins.
	local picked = s.picked and s.picked == s.route and routes[s.route]
	if picked and Engine.HeldIn(picked) == 0 and furthestDone(picked) == 0 then
		local best = Engine.BestRoute(player, (C.PlayerMapPosition()))
		if best and best.id ~= picked.id and Engine.HeldIn(best) > 0 then
			s.route, s.picked, s.pin = best.id, best.id, nil
			ns.Print(("your quests are on %s: following that route."):format(best.title))
		end
	elseif s.picked and s.picked ~= s.route then
		s.picked = nil
	end
	local side = Engine.Side()
	if side and not fits(side, player) then s.side, s.aimSide, s.sideHidden = nil, nil, nil end
end

local function compute()
	player = Q.Player()
	furthest, neededCache = {}, {}
	extra = openExtra()
	local s = state()
	ownRoutes(s)
	local route = Engine.Route()
	live = firstOpen(route)
	-- A finished route hands over to the next one, when it is for this character.
	local hops = 0
	while route and not live and Engine.NextOf(route) and hops < 5 do
		hops = hops + 1
		route = Engine.NextOf(route)
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

-- For automation (Guide/Automate.lua): the quests the guide wants handled,
-- { [q] = true } for "accept" or "turnin": every open goal of that verb on
-- the route and the side guide (any step: a quest taken early is fine), and
-- the extra quest picked.
function Engine.Wanted(verb)
	player = player or Q.Player()
	local out = {}
	for _, route in pairs({ Engine.Route() or false, Engine.Side() or false }) do
		if route then
			for s, step in ipairs(route.steps) do
				if stepApplies(step) then
					for g, goal in ipairs(step) do
						if goal[1] == verb and goalStatus(route, s, g, goal) == "open" then out[goal[2]] = true end
					end
				end
			end
		end
	end
	if extra and extra.verb == verb then out[extra.quest] = true end
	if verb == "turnin" then
		for _, n in ipairs(nearby) do
			if n.verb == "turnin" then out[n.quest] = true end
		end
	end
	return out
end

-- The goals of the step being followed (and the side guide's), still to do
-- or instructions: { goal, ... }.
function Engine.OpenGoals()
	local out = {}
	local function add(route, s)
		if not (route and s and route.steps[s]) then return end
		for g, goal in ipairs(route.steps[s]) do
			local st = goalStatus(route, s, g, goal)
			if st == "open" or st == "info" then out[#out + 1] = goal end
		end
	end
	add(Engine.Route(), current)
	add(Engine.Side(), sideLive)
	return out
end

function Engine.LiveStep() return live end
function Engine.CurrentStep() return current end
function Engine.Extra() return extra end
function Engine.SideStep() return sideLive end

local function here()
	local map, x, y = C.PlayerMapPosition()
	return map and { map = map, x = x, y = y } or nil
end

-- Yards from the player to a place, or nil (no position, other continent).
local function yardsTo(p)
	local h = here()
	if not (h and p) then return nil end
	local i1, n1, w1 = C.MapToWorld(h.map, h.x, h.y)
	local i2, n2, w2 = C.MapToWorld(p.map, p.x, p.y)
	if not (i1 and i2) or i1 ~= i2 then return nil end
	return math.sqrt((n2 - n1) ^ 2 + (w2 - w1) ^ 2)
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
	if verb == "accept" then
		local p = atPlace(goal.who) or Q.Giver(q, from)
		if p then return p end
		-- Started by an item: where it drops until you have it; then nowhere
		-- to go, you use it from your bags (the step item button offers it).
		local item = Q.StartItem(q)
		if item and C.ItemCount(item.id) == 0 then return Q.ItemPlace(item.id, from, Q.Map(q)) end
		return nil
	end
	if verb == "turnin" then return atPlace(goal.who) or Q.Finisher(q, from) end
	if verb == "complete" then
		local log = Q.Objectives(q)
		if goal.obj and goal.at then return atPlace(qname(goal)) end
		for i = 1, Q.ObjectiveCount(q) do
			if wantsObjective(goal, i) and not (log and log[i] and log[i].done) then
				local p = Q.ObjectivePlace(q, i, from)
				if p then return p end
			end
		end
		return atPlace(qname(goal)) or Q.ObjectivePlace(q, goal.obj and goal.obj[1] or 1, from)
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

-- The item an accept goal's quest starts from, when no one gives it and the
-- route names no one either: { id, name } or nil.
local function startItemOf(goal)
	if goal[1] ~= "accept" or goal.who or goal.at or type(goal[2]) ~= "number" then return nil end
	return Q.StartItem(goal[2])
end
Engine.StartItem = startItemOf

local RANKS = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }
local VERB_TEXT = { accept = "Accept %s", turnin = "Turn in %s", complete = "Complete %s" }

local function goalText(goal)
	local verb = goal[1]
	local item = startItemOf(goal)
	if item then return ("Use %s: accept %s"):format(item.name, qname(goal)) end
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
	local goal, g = leadIn(Engine.Route(), current)
	-- On the live step, a ready turn-in from the quest log nearer than the
	-- step's own place takes the arrow: hand it in on the way.
	if goal and current == live then
		for _, n in ipairs(nearby) do
			if n.verb == "turnin" then
				local d = yardsTo(placeOf(goal))
				if not d or n.yards < d then return { "turnin", n.quest } end
				break
			end
		end
	end
	return goal, g
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
					for i, o in ipairs(log) do
						if wantsObjective(goal, i) then rows[#rows + 1] = { text = o.text, have = o.have, need = o.need, done = o.done } end
					end
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

-- A step as the player reads it at the NPC, one line per action:
--   { kind, lead, name, tail, done, info, optional, have, need }
-- kind: "talk" heads the goals that share a giver ("Talk to Gryan
-- Stoutmantle"), then "accept", "turnin", "complete" (with "objective" lines
-- under it while open), "goto", "have", "bind", "note"... lead and tail are
-- plain, name is the part to pick out (a person, quest or item).
local LINE = {
	accept = "Accept ", turnin = "Turn in ", complete = "", have = "Get ", learn = "Learn ",
}
local function goalLine(route, s, g, goal, st, withObjectives, out)
	local verb = goal[1]
	local line = { kind = verb, done = st == "done", info = st == "info", optional = goal.optional }
	local item = startItemOf(goal)
	if item then
		line.lead, line.name, line.tail = "Use ", item.name, ": accept " .. qname(goal)
	elseif QUEST_VERBS[verb] then
		line.lead, line.name = LINE[verb], qname(goal)
	elseif verb == "have" then
		local name = goal.name or (Q.Data.items[goal[2]] and Q.Data.items[goal[2]][1]) or ("item " .. goal[2])
		line.lead, line.name = LINE.have, name
		if (goal[3] or 1) > 1 then line.have, line.need = math.min(C.ItemCount(goal[2]), goal[3]), goal[3] end
	elseif verb == "bind" then
		line.lead, line.name, line.tail = "Make ", goal[2] or "this inn", " your home"
	elseif verb == "learn" then
		line.lead, line.name = LINE.learn, goal.name or "the recipe"
	else
		line.lead = goalText(goal) or ""
	end
	out[#out + 1] = line
	if verb == "complete" and st == "open" and withObjectives then
		for i, o in ipairs(Q.Objectives(goal[2]) or {}) do
			if wantsObjective(goal, i) then
				out[#out + 1] = { kind = "objective", lead = o.text or "", have = o.have, need = o.need, done = o.done }
			end
		end
	end
end

local TALK = { accept = true, turnin = true, bind = true, train = true }
local function linesOf(route, s, withObjectives)
	local out, lastWho, talk = {}, nil, nil
	for g, goal in ipairs(route.steps[s]) do
		local st = goalStatus(route, s, g, goal)
		if st ~= "na" and st ~= "wait" then
			local who = TALK[goal[1]] and goal.who or nil
			if who and who ~= lastWho then
				talk = { kind = "talk", lead = "Talk to ", name = who, done = true }
				out[#out + 1] = talk
			elseif not who then
				talk = nil
			end
			lastWho = who
			if talk and st ~= "done" then talk.done = false end
			goalLine(route, s, g, goal, st, withObjectives, out)
		end
	end
	return out
end
Engine.LinesOf = linesOf

-- The card at the top: the step being followed, every line of it (steps are
-- one action each: Engine's splitting), its objectives' progress.
local function cardOf(route, s)
	return linesOf(route, s, true)
end

-- How many steps the window lists below the card (the current one included).
ns.Defaults("guide", { ahead = 6 })

local function stepsAhead(route, from)
	local out = {}
	local want = ns.Get("guide.ahead") or 6
	for s = from, #route.steps do
		if #out >= want then break end
		if s == from or stepOpen(route, s) then
			local step = route.steps[s]
			out[#out + 1] = {
				index = s, current = s == from, title = titleOf(step, route, s),
				note = step.note, lines = linesOf(route, s, s == from),
			}
		end
	end
	return out
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

-- "From your quest log": quests in the log near the player, nearest first,
-- at most NEAR_MAX: a quest ready to hand in by its finisher, else one with
-- objectives left by the nearest place of one, within NEAR_YARDS. Quests the
-- step shown (or the extra quest) deals with, and skipped ones, are left
-- out. Any quest the data knows, on the route or not: what the player holds
-- is done on the spot rather than come back for. A ready turn-in nearer than
-- the live step's own place takes the arrow (leadGoal), and the automation
-- hands it in (Wanted).
-- -> { { quest, verb = "turnin" | "complete", text, sub, yards, place }, ... }
Engine.NEAR_YARDS, Engine.NEAR_MAX = 250, 4
local function computeNearby()
	local out = {}
	local from = here()
	if not from then return out end
	local inStep = {}
	local route = Engine.Route()
	if route and current and route.steps[current] then
		for _, goal in ipairs(route.steps[current]) do
			if QUEST_VERBS[goal[1]] then inStep[goal[2]] = true end
		end
	end
	if extra then inStep[extra.quest] = true end
	for _, q in ipairs(Q.LogQuests()) do
		if not inStep[q] and not skipped(q) and not Q.Done(q) and Q.Get(q) then
			local ready = Q.Ready(q)
			local p
			if ready then
				p = Q.Finisher(q, from)
			else
				local log = Q.Objectives(q)
				for i = 1, Q.ObjectiveCount(q) do
					if not (log and log[i] and log[i].done) then
						p = Q.ObjectivePlace(q, i, from)
						if p then break end
					end
				end
			end
			local yards = p and yardsTo(p)
			if yards and yards <= Engine.NEAR_YARDS then
				local verb = ready and "turnin" or "complete"
				out[#out + 1] = {
					quest = q, verb = verb, place = p, yards = yards,
					text = VERB_TEXT[verb]:format(Q.Name(q)),
					sub = (p.name and (p.name .. "  ·  ") or "") .. ns.Nav.FormatYards(yards),
				}
			end
		end
	end
	table.sort(out, function(a, b)
		if a.yards ~= b.yards then return a.yards < b.yards end
		return a.quest < b.quest
	end)
	while #out > Engine.NEAR_MAX do table.remove(out) end
	return out
end
function Engine.Nearby() return nearby end

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
			card = (function()
				local lines = {}
				goalLine(nil, nil, nil, goal, "open", true, lines)
				return lines
			end)(),
			next = route and live and ("Then back to the route: " .. (titleOf(route.steps[live], route, live) or "")) or nil,
			nearby = nearby,
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
			objectives = {}, nearby = nearby,
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
		card = cardOf(route, current), steps = stepsAhead(route, current),
		nearby = nearby,
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
	nearby = computeNearby()
	if ns.Guide and ns.Guide.SetView then ns.Guide.SetView(Engine.View()) end
	updateWaypoint()
	ns.Fire("GUIDE_UPDATED")
	ns.Fire("PINS_CHANGED")
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
	"ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "HEARTHSTONE_BOUND", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "SPELLS_CHANGED",
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

ns.On("SETTING_CHANGED", function(path) if path == "guide.ahead" then Engine.Schedule() end end)

-- The first route is chosen by the update (see ownRoutes), once race, class
-- and side can be read.
ns.On("READY", function() Engine.Update() end)

---------------------------------------------------------------------------
-- Pins: the places of the step shown, for the world map and the minimap.
--   { map, x, y, kind = "lead" | "goal" | "spot", title, sub }
-- lead: where the arrow points; goal: the step's other open goals; spot: the
-- places an open objective's monsters or objects are (from the data).
---------------------------------------------------------------------------

function Engine.Pins()
	local out = {}
	local route = Engine.Route()
	local lead = leadGoal()
	local seen = {}
	local function add(p, kind, title, sub)
		if not (p and p.map and p.x and p.y) then return end
		local key = ("%d:%.1f:%.1f"):format(p.map, p.x, p.y)
		if seen[key] then return end
		seen[key] = true
		out[#out + 1] = { map = p.map, x = p.x, y = p.y, kind = kind, title = title or p.name, sub = sub }
	end
	if lead then add(placeOf(lead), "lead", nil, goalText(lead)) end
	if out[1] and route and current and not extra then out[1].label = tostring(current) end
	-- The steps after this one, numbered where each begins (the map's step
	-- numbers): as many as Settings says.
	if route and current and not extra and ns.Get("pins.stepNumbers") then
		local shown = 0
		for s = current + 1, #route.steps do
			if shown >= (ns.Get("pins.stepCount") or 8) then break end
			if stepOpen(route, s) then
				shown = shown + 1
				local goal = leadIn(route, s)
				local p = goal and placeOf(goal)
				local before = #out
				add(p, "step", ("Step %d · %s"):format(s, titleOf(route.steps[s], route, s)), goal and goalText(goal))
				if #out > before then out[#out].label = tostring(s) end
			end
		end
	end
	local goals = {}
	if extra then goals[1] = { extra.verb, extra.quest }
	elseif route and current then
		for g, goal in ipairs(route.steps[current]) do
			if goalStatus(route, current, g, goal) == "open" then goals[#goals + 1] = goal end
		end
	end
	for _, goal in ipairs(goals) do
		if goal ~= lead then add(placeOf(goal), "goal", nil, goalText(goal)) end
		if goal[1] == "complete" then
			local q = goal[2]
			local log = Q.Objectives(q)
			for i = 1, Q.ObjectiveCount(q) do
				if wantsObjective(goal, i) and not (log and log[i] and log[i].done) then
					local p = placeOf(goal)
					local map = p and p.map
					local pts, name
					if map then pts, name = Q.ObjectiveSpots(q, i, map) end
					for k = 1, pts and #pts or 0, 2 do
						add({ map = map, x = pts[k], y = pts[k + 1] }, "spot", name, qname(goal))
					end
				end
			end
		end
	end
	return out
end

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
-- Sync: the guide again from the quest log, now
---------------------------------------------------------------------------

-- The leveling route as the quest log has it: the step paged to (Back /
-- Next) let go, every quest read again, and, when the route is finished or
-- left behind (more than 2 levels above it), the route that suits the
-- character now. Class and profession routes are never swapped. Returns the
-- route shown, its live step, and the route switched to (or nil).
function Engine.Sync()
	local s = state()
	player = Q.Player()
	furthest = {}
	s.pin = nil
	ownRoutes(s)
	local route = Engine.Route()
	local switched
	local leveling = not route or (route.category or "Leveling") == "Leveling"
	local hi = route and route.levels and route.levels[2]
	if leveling and (not route or not firstOpen(route) or (hi and (player.level or 1) > hi + 2)) then
		local best = Engine.BestRoute(player, (C.PlayerMapPosition()))
		if best and best ~= route then s.route, switched = best.id, best end
	end
	Engine.Update()
	route = Engine.Route()
	if not route then
		ns.Print("synced: no leveling route for this character.")
	elseif not live then
		ns.Print(("synced with your quest log: %s is done."):format(route.title))
	else
		ns.Print(("synced with your quest log: %s%s, step %d of %d."):format(
			switched and "now on " or "", route.title, live, #route.steps))
	end
	return route, live, switched
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

-- "I've already done it": the player says so, when the game does not (a
-- quest done before the guide, or one Forever reports differently). It
-- counts as handed in (Quests.Done), so its follow-ups come up.
function Engine.MarkQuestDone(q)
	Q.MarkDone(q, true)
	Engine.Update()
end

-- "This step is done": every goal of the step shown, for a step that is not
-- just quests (an item, a place).
function Engine.MarkStepDone()
	local route = Engine.Route()
	if not (route and current) then return nil end
	local s = current
	state().stepsDone[route.id .. ":" .. s] = true
	state().pin = nil
	Engine.Update()
	return s
end

-- The route book (UI/RouteBook.lua): how far a route is, starting one at a
-- step, and the route to go on to.

-- { at = first open step or nil, count = steps, done = steps behind } for
-- any route, the way the guide would see it now.
function Engine.Progress(r)
	player = player or Q.Player()
	local at = firstOpen(r)
	return { at = at, count = #r.steps, done = at and (at - 1) or #r.steps }
end

-- Follow route `id` from step `s`: the steps before it count as done (marked
-- by you: Settings, Marked done by you, Bring back undoes it).
function Engine.StartAt(id, s)
	local r = routes[id]
	if not (r and r.steps[s]) then return false end
	local st = state()
	for k = 1, s - 1 do st.stepsDone[id .. ":" .. k] = true end
	for k = s, #r.steps do st.stepsDone[id .. ":" .. k] = nil end
	return Engine.SetRoute(id)
end

-- The route that follows `r`: the one you picked in the route book, else the
-- route's own; nil when none is for this character.
function Engine.NextOf(r)
	player = player or Q.Player()
	local st = state()
	local id = st.nexts and st.nexts[r.id] or r.next
	local n = id and routes[id]
	if n and fits(n, player) then return n end
	if id ~= r.next and r.next and routes[r.next] and fits(routes[r.next], player) then return routes[r.next] end
	return nil
end

-- Pick the route that follows `id` (nil: the route's own).
function Engine.SetNext(id, nextId)
	local st = state()
	st.nexts = st.nexts or {}
	st.nexts[id] = nextId
	Engine.Update()
end

-- Routes to go on to after `r`: the leveling routes for this character that
-- start within a few levels of where `r` ends, its own next first.
function Engine.NextChoices(r)
	player = player or Q.Player()
	local out, seen = {}, {}
	local own = r.next and routes[r.next]
	if own and fits(own, player) then out[1] = own seen[own.id] = true end
	local top = r.levels and r.levels[2] or 60
	for _, n in ipairs(Engine.RoutesFor(player, "Leveling")) do
		if not seen[n.id] and n.id ~= r.id and n.levels[1] >= top - 4 and n.levels[1] <= top + 2 then
			out[#out + 1] = n
			seen[n.id] = true
		end
	end
	return out
end

-- Everything the player marked done, back to what the game says.
function Engine.Marked()
	local n = 0
	for _ in pairs(state().stepsDone) do n = n + 1 end
	return n + #Q.Marked()
end
function Engine.ClearMarked()
	state().stepsDone = {}
	for _, q in ipairs(Q.Marked()) do Q.MarkDone(q, nil) end
	Engine.Update()
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

-- The capitals (UiMap ids): the routes stop there for trainers and hand-ins,
-- nobody levels there.
local CITIES = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true }
Engine.CITIES = CITIES

-- The maps a route works in: its own, and every map with at least 6 quest
-- goals on it ("Ashenvale & Thousand Needles" covers both), with how many.
local mapSets = setmetatable({}, { __mode = "k" })
local function mapsOf(r)
	local set = mapSets[r]
	if set then return set end
	local count = {}
	for _, step in ipairs(r.steps) do
		for _, goal in ipairs(step) do
			if QUEST_VERBS[goal[1]] and goal.at then count[goal.at[1]] = (count[goal.at[1]] or 0) + 1 end
		end
	end
	set = {}
	for map, n in pairs(count) do if n >= 6 then set[map] = n end end
	if r.map then set[r.map] = math.max(set[r.map] or 0, 1000) end
	mapSets[r] = set
	return set
end

-- Zones for the player's level: { { map, name, low, high, route, city,
-- raceRoute }, ... }. `route` is the leveling route working in that zone
-- that suits the character: the one followed if it does, else one for the
-- level, else the one most at home there. `raceRoute` is a starting zone's
-- route for other races (Mulgore for Tauren), shown, not offered.
function Engine.Zones()
	player = Q.Player()
	local current = Engine.Route()
	local function rank(r, map)
		local fitsLevel = player.level >= r.levels[1] - 2 and player.level <= r.levels[2] + 1
		return (current and r.id == current.id and 4 or 0) + (fitsLevel and 2 or 0), mapsOf(r)[map] or 0
	end
	local mine = Engine.RoutesFor(player, "Leveling")
	local out = {}
	for _, z in ipairs(Q.ZonesFor(player.level, player.faction)) do
		z.name = C.MapName(z.map) or ("Map " .. z.map)
		z.city = CITIES[z.map] or nil
		if not z.city then
			local best, bestA, bestB
			for _, r in ipairs(mine) do
				if mapsOf(r)[z.map] then
					local a, b = rank(r, z.map)
					if not best or a > bestA or (a == bestA and b > bestB) then best, bestA, bestB = r, a, b end
				end
			end
			z.route = best
			if not best then
				for _, id in ipairs(routeOrder) do
					local r = routes[id]
					if (r.category or "Leveling") == "Leveling" and r.map == z.map and r.races
						and (not r.faction or r.faction == player.faction) then
						z.raceRoute = r
						break
					end
				end
			end
		end
		out[#out + 1] = z
	end
	return out
end
