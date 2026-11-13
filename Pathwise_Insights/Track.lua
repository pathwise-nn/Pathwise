-- Pathwise Insights: the guide's steps without Pathwise. When Pathwise:
-- Leveling & Professions is not installed, this follows your quest log
-- against the same leveling routes (Data/Routes.lua, made from Pathwise's)
-- and says when a step is done, with Pathwise's step numbers, so the times
-- compare with those of players following Pathwise. With Pathwise
-- installed, Pathwise says it (GUIDE_STEP) and this stays off.
--
-- How it tells where you are:
--   * a goal is done when the game says so: a quest taken (in your log or
--     handed in), its objectives done (ready to hand in, or handed in), or
--     handed in; goals for another race or class, and optional ones, do
--     not count
--   * the route is the one your last quest belongs to that suits your
--     character (faction, race, levels); a finished route goes on to its
--     next one
--   * the live step is the first unfinished step after the furthest finished
--     one. Steps with no quest (travel, a hearthstone) have no time of their
--     own: it goes to the next step with a quest.

local ADDON, ns = ...
local S = ns.S
local K = {}
ns.Track = K

local ROUTES = ns.Routes or {}
local byId, byQuest = {}, {}
for _, r in ipairs(ROUTES) do
	byId[r.id] = r
	for s, st in ipairs(r.steps) do
		for _, g in ipairs(st) do
			byQuest[g[2]] = byQuest[g[2]] or {}
			table.insert(byQuest[g[2]], { r = r, s = s })
		end
	end
end
K.byId = byId

-- On only when Pathwise is not there to say it.
function K.Active() return not S.Guide.Available() end

local function player()
	local R = ns.Recorder.Readable
	local _, race = UnitRace and UnitRace("player")
	local _, class = UnitClass and UnitClass("player")
	local level = UnitLevel and R(UnitLevel("player"))
	return { race = R(race), class = R(class), faction = UnitFactionGroup and R(UnitFactionGroup("player")),
		level = type(level) == "number" and level or 1 }
end

local function inList(list, v)
	for _, x in ipairs(list or {}) do if x == v then return true end end
	return false
end

local function fits(only, p)
	if type(only) ~= "table" then return true end
	if only.races and not inList(only.races, p.race) then return false end
	if only.classes and not inList(only.classes, p.class) then return false end
	return true
end

-- Whether a route suits the character: faction, race, and not far below
-- its level.
function K.Suits(r, p)
	p = p or player()
	if r.faction and p.faction and r.faction ~= p.faction then return false end
	if r.races and p.race and not inList(r.races, p.race) then return false end
	return true
end

-- Quest states as the game gives them; a secret one counts as "no".
local function yes(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, v = pcall(fn, ...)
	return ok and ns.Recorder.Readable(v) == true
end
local function questDone(q) return C_QuestLog and yes(C_QuestLog.IsQuestFlaggedCompleted, q) or false end
local function onQuest(q) return C_QuestLog and yes(C_QuestLog.IsOnQuest, q) or false end
local function ready(q)
	if not C_QuestLog then return false end
	if yes(C_QuestLog.ReadyForTurnIn, q) then return true end
	return yes(C_QuestLog.IsComplete, q)
end

local function goalDone(g)
	local v, q = g[1], g[2]
	if questDone(q) then return true end
	if v == "a" then return onQuest(q) end
	if v == "c" then return onQuest(q) and ready(q) end
	return false
end

-- A step's state for this character: "none" (no quest goal for you), "done", or "open".
function K.StepState(r, s, p)
	p = p or player()
	local st = r.steps[s]
	if not st or not fits(st.only, p) then return "none" end
	local any = false
	for _, g in ipairs(st) do
		if not g.opt and fits(g.only, p) then
			any = true
			if not goalDone(g) then return "open" end
		end
	end
	return any and "done" or "none"
end

-- The live step of route r: the first open step after the furthest done
-- one (nil: the route is done).
function K.Live(r, p)
	p = p or player()
	local furthest = 0
	local states = {}
	for s = 1, #r.steps do
		states[s] = K.StepState(r, s, p)
		if states[s] == "done" then furthest = s end
	end
	for s = furthest + 1, #r.steps do
		if states[s] == "open" then return s end
	end
	return nil
end

-- The route a quest points to: its routes that suit you, the one whose
-- levels you are in first, then the one you are on.
function K.RouteOf(q, p, current)
	p = p or player()
	local best, bestScore
	for _, e in ipairs(byQuest[q] or {}) do
		local r = e.r
		if K.Suits(r, p) then
			local score = 0
			if current and r.id == current then score = score + 4 end
			local lo, hi = r.levels and r.levels[1] or 1, r.levels and r.levels[2] or 60
			if p.level >= lo - 2 and p.level <= hi + 2 then score = score + 2 end
			if not bestScore or score > bestScore then best, bestScore = r, score end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Following along
---------------------------------------------------------------------------

local last -- { route, step } as last told

-- Where you are now: route id and live step, or nil.
function K.Where(hint)
	if not K.Active() then return nil end
	local p = player()
	local log = ns.Recorder.Log()
	local id = (hint and hint.id) or (log.track and log.track.route)
	-- None yet: the route of a quest in your log.
	if not id and C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
		local R = ns.Recorder.Readable
		local n = R(C_QuestLog.GetNumQuestLogEntries())
		for i = 1, type(n) == "number" and n or 0 do
			local info = R(C_QuestLog.GetInfo(i))
			local q = type(info) == "table" and R(info.isHeader) ~= true and R(info.questID)
			local found = q and K.RouteOf(q, p)
			if found then id = found.id break end
		end
	end
	local r = id and byId[id]
	if r and not K.Suits(r, p) then r = nil end
	local hops = 0
	local live = r and K.Live(r, p)
	-- A finished route goes on to its next one.
	while r and not live and r.next and byId[r.next] and hops < 5 do
		hops = hops + 1
		r = byId[r.next]
		live = K.Live(r, p)
	end
	if not r then return nil end
	return r.id, live
end

-- Tells the recorder when the live step moved, as Pathwise would.
function K.Update(hint, how)
	if not K.Active() then return end
	local id, step = K.Where(hint)
	if not id then return end
	local log = ns.Recorder.Log()
	log.track = { route = id }
	local key = id .. ":" .. tostring(step)
	if last and last.key == key then return end
	local from = last and { route = last.route, step = last.step } or nil
	last = { key = key, route = id, step = step }
	ns.Recorder.OnStep({ route = id, step = step, from = from, how = from and (how or "done") or "login", src = "quests" })
end

-- A quest you took or handed in may put you on another route.
function K.OnQuest(q)
	if not K.Active() or type(q) ~= "number" then return end
	local log = ns.Recorder.Log()
	local current = log.track and log.track.route
	local r = K.RouteOf(q, nil, current)
	if r and r.id ~= current then
		K.Update({ id = r.id }, "moved")
	else
		K.Update()
	end
end

-- Quest log updates come in bursts: one look a moment after the last.
local pending = false
local function soon()
	if pending then return end
	pending = true
	local function run() pending = false K.Update() end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
K.Soon = soon

function K.Reset() last = nil end

S.RegisterEvent("QUEST_ACCEPTED", function(_, q) K.OnQuest(q) end)
S.RegisterEvent("QUEST_TURNED_IN", function(_, q) K.OnQuest(q) end)
S.RegisterEvent("QUEST_LOG_UPDATE", function() soon() end)
S.RegisterEvent("PLAYER_LEVEL_UP", function() soon() end)
S.On("READY", function() K.Reset() K.Update() end)
