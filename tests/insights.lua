-- Tests for Pathwise_Insights: Pathwise's GUIDE_STEP hook and the read-only
-- S.Guide, the recorder (time, XP, deaths, steps, zones, levels, skills) and
-- the page. Loaded by tests/run.lua.
local h = ...
local test, eq, ok, fresh = h.test, h.eq, h.ok, h.fresh

-- Three steps that end by levelling, then one that ends with a quest (363,
-- the Undead start: real data), for skipping.
local ROUTE = {
	id = "test/insights", title = "Insights (test)", category = "Leveling", levels = { 2, 6 }, faction = "Horde",
	steps = {
		{ { "level", 3 } },
		{ { "level", 4 } },
		{ { "accept", 363 } },
		{ { "level", 6 } },
	},
}

local function setup(opts)
	opts = opts or {}
	local stub, ns = fresh()
	PathwiseInsightsLog = opts.log
	stub.player.level, stub.player.xp, stub.player.xpMax, stub.player.afk = 2, 100, 1000, false
	function UnitXP() return stub.player.xp end
	function UnitXPMax() return stub.player.xpMax end
	function UnitIsAFK() return stub.player.afk end
	local steps = {}
	ns.On("GUIDE_STEP", function(info) steps[#steps + 1] = info end)
	local ins = stub.loadAddon(".", "Pathwise_Insights")
	stub.moveTo(1420, 30.2, 71.6)
	stub.login()
	ok(Pathwise.RegisterRoute(ROUTE), "route registers")
	ns.Engine.SetRoute(ROUTE.id)
	return stub, ns, ins, steps
end

-- Level up to `lvl` with `xp` into the new level.
local function levelTo(stub, lvl, xp)
	stub.player.level, stub.player.xp = lvl, xp or 0
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("PLAYER_LEVEL_UP", lvl)
end

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

test("insights: Pathwise says when the live step moves, and why", function()
	local stub, ns, _, steps = setup()
	local last = steps[#steps]
	eq(last.route, ROUTE.id, "on the route")
	eq(last.step, 1)
	eq(last.how, "moved", "a route picked by you")
	levelTo(stub, 3)
	last = steps[#steps]
	eq(last.step, 2, "level 3: step 2")
	eq(last.how, "done")
	eq(last.from.route, ROUTE.id)
	eq(last.from.step, 1)
	local n = #steps
	stub.fire("QUEST_LOG_UPDATE")
	eq(#steps, n, "nothing moved: no message")
	levelTo(stub, 4)
	ns.Engine.SkipQuest(363)
	last = steps[#steps]
	eq(last.step, 4)
	eq(last.how, "skip", "a quest skipped")
	ns.Engine.MarkStepDone()
	last = steps[#steps]
	eq(last.step, nil, "the route is done")
	eq(last.how, "marked")
end)

test("insights: S.Guide reads the route and step, and changes nothing", function()
	setup()
	local G = Pathwise.Suite.Guide
	local id, title = G.Route()
	eq(id, ROUTE.id)
	eq(title, "Insights (test)")
	eq(G.Step(), 1)
	local info = G.RouteInfo(ROUTE.id)
	eq(info.steps, 4)
	eq(info.levels[1], 2)
	info.title = "changed"
	eq(G.RouteInfo(ROUTE.id).title, "Insights (test)", "a copy")
	eq(G.RouteInfo("nope"), nil)
end)

test("insights: time, XP and deaths go to the step, its route, the zone and the level", function()
	local stub, _, ins = setup()
	local R = ins.Recorder
	R.Play(60)
	stub.player.xp = 400
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("PLAYER_DEAD")
	R.Play(30)
	levelTo(stub, 3, 50) -- 600 to finish level 2, 50 into level 3
	local log = PathwiseInsightsLog
	eq(log.played, 90)
	eq(log.xp, 300 + 650)
	eq(log.deaths, 1)
	eq(#log.steps, 1, "step 1 closed")
	local st = log.steps[1]
	eq(st.r, ROUTE.id)
	eq(st.s, 1)
	eq(st.t, 90)
	eq(st.xp, 950)
	eq(st.d, 1)
	eq(st.lvl, 2)
	eq(st.how, "done")
	eq(log.cur.s, 2, "step 2 is being timed")
	local route = log.routes[ROUTE.id]
	eq(route.t, 90)
	eq(route.steps, 1)
	eq(log.zones[1420].t, 90, "Tirisfal Glades")
	eq(log.zones[1420].lvl, 2, "came at level 2")
	eq(log.levels[2].t, 90)
	eq(log.levels[2].xp, 300)
	eq(log.levels[3].xp, 650, "the XP of the level-up lands on the new level")
end)

test("insights: AFK, loading screens and recording off are not counted", function()
	local stub, ns, ins = setup()
	local R = ins.Recorder
	stub.player.afk = true
	R.Play(10)
	stub.player.afk = false
	R.Tick(30) -- a loading screen
	eq(PathwiseInsightsLog.played, 0)
	stub.advance(1) -- the clock frame
	ok(math.abs(PathwiseInsightsLog.played - 1) < 0.01, "one second of play: " .. PathwiseInsightsLog.played)
	ns.Set("insights.record", false)
	R.Tick(1)
	stub.fire("PLAYER_DEAD")
	ok(math.abs(PathwiseInsightsLog.played - 1) < 0.01, "off: no time")
	eq(PathwiseInsightsLog.deaths, 0, "off: no deaths")
end)

test("insights: after a /reload the same step goes on being timed", function()
	local _, _, ins = setup()
	local R = ins.Recorder
	R.Play(45)
	-- A new session: Pathwise announces the step it is on, as at login.
	R.OnStep({ route = ROUTE.id, step = 1, how = "login" })
	eq(#PathwiseInsightsLog.steps, 0, "nothing closed")
	R.Play(15)
	eq(PathwiseInsightsLog.cur.t, 60)
	-- Another step at login (played elsewhere): the old one is closed as left.
	R.OnStep({ route = ROUTE.id, step = 3, how = "login" })
	eq(PathwiseInsightsLog.steps[1].how, "moved")
	eq(PathwiseInsightsLog.cur.s, 3)
end)

test("insights: skipped steps and left steps are told apart", function()
	local stub, ns, ins = setup()
	local R = ins.Recorder
	R.Play(20)
	levelTo(stub, 4) -- straight to step 3
	R.Play(20)
	ns.Engine.SkipQuest(363)
	R.Play(20)
	ns.Engine.SetRoute("forever/horde/07-ashenvale")
	local log = PathwiseInsightsLog
	eq(#log.steps, 3)
	eq(log.steps[1].how, "done")
	eq(log.steps[2].how, "skip")
	eq(log.steps[2].s, 3)
	eq(log.steps[3].how, "moved")
	eq(log.routes[ROUTE.id].skips, 1)
	eq(log.cur.r, "forever/horde/07-ashenvale", "timing the new route")
end)

test("insights: profession skill-ups, from the first rank seen", function()
	local stub, ns, ins = setup()
	stub.skills[186] = { 12, 75 } -- Mining
	stub.fire("SKILL_LINES_CHANGED")
	stub.skills[186] = { 20, 75 }
	stub.fire("SKILL_LINES_CHANGED")
	local s = PathwiseInsightsLog.skills[186]
	eq(s.from, 12)
	eq(s.to, 20)
	eq(s.ups, 8)
end)

test("insights: the page shows the numbers; Clear asks first", function()
	local stub, ns, ins = setup()
	local R, P = ins.Recorder, ins.Panel
	R.Play(600)
	stub.player.xp = 700
	stub.fire("PLAYER_XP_UPDATE", "player")
	levelTo(stub, 3)
	eq(P.Duration(4500), "1 h 15 m")
	eq(P.Duration(125), "2 m")
	eq(P.Duration(40), "40 s")
	eq(P.Rate(900, 600), 5400)
	eq(P.Rate(900, 60), nil, "too short to tell")
	eq(P.Number(1234567), "1,234,567")
	P.Open()
	ok(ns.Panels.IsOpen("insights"), "the page is open")
	local texts = stub.texts()
	ok(contains(texts, "PATHWISE INSIGHTS"), "heading")
	ok(contains(texts, "10 m"), "time played")
	ok(contains(texts, "5,400 XP/h"), "XP an hour")
	ok(contains(texts, "Insights (test)"), "the route")
	ok(contains(texts, "Tirisfal Glades"), "the zone")
	ok(contains(texts, "Level 2"), "time at level 2")
	ok(stub.clickLabel("Clear"), "Clear")
	eq(PathwiseInsightsLog.played, 600, "not yet")
	ok(stub.clickLabel("Yes, clear"), "Yes, clear")
	eq(PathwiseInsightsLog.played, 0, "cleared")
	eq(PathwiseInsightsLog.cur.s, 2, "the step you are on is timed from now")
	local listed = false
	for _, m in ipairs(Pathwise.Suite.Modules()) do if m.key == "insights" then listed = true end end
	ok(listed, "in Settings > Pathwise suite")
end)
