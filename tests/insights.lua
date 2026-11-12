-- Tests for Pathwise_Insights: Pathwise's GUIDE_STEP hook and the read-only
-- S.Guide, the recorder (time, XP, deaths, steps, zones, levels, skills) and
-- the window. Loaded by tests/run.lua.
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
	PathwiseInsightsData = opts.data
	stub.player.level, stub.player.xp, stub.player.xpMax, stub.player.afk = 2, 100, 1000, false
	function UnitXP() return stub.player.xp end
	function UnitXPMax() return stub.player.xpMax end
	function UnitIsAFK() return stub.player.afk end
	function UnitName() return "Testchar" end
	function GetRealmName() return "Test Realm" end
	-- A Friday afternoon: 9 October 2026, 14:00 (local time).
	stub.clock = os.time({ year = 2026, month = 10, day = 9, hour = 14 })
	function time() return stub.clock end
	CombatLogGetCurrentEventInfo, UnitGUID = nil, nil
	if opts.before then opts.before(stub) end
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

local function log() return PathwiseInsightsData.chars["Testchar-Test Realm"] end

test("insights: time, XP and deaths go to the step, its route, the zone, the level and the session", function()
	local stub, _, ins = setup()
	local R = ins.Recorder
	R.Play(60)
	stub.player.xp = 400
	stub.fire("PLAYER_XP_UPDATE", "player")
	stub.fire("PLAYER_DEAD")
	R.Play(30)
	levelTo(stub, 3, 50) -- 600 to finish level 2, 50 into level 3
	local L = log()
	ok(L, "saved for the account, under this character")
	eq(L.played, 90)
	eq(L.xp, 300 + 650)
	eq(L.deaths, 1)
	eq(#L.steps, 1, "step 1 closed")
	local st = L.steps[1]
	eq(st.r, ROUTE.id)
	eq(st.s, 1)
	eq(st.t, 90)
	eq(st.xp, 950)
	eq(st.d, 1)
	eq(st.how, "done")
	eq(L.cur.s, 2, "step 2 is being timed")
	eq(L.routes[ROUTE.id].steps, 1)
	eq(L.zones[1420].t, 90, "Tirisfal Glades")
	eq(L.zones[1420].lvl, 2, "came at level 2")
	eq(L.levels[2].t, 90)
	eq(L.levels[3].xp, 650, "the XP of the level-up lands on the new level")
	ok(L.levels[3].full, "level 3 seen from its start")
	ok(not L.levels[2].full, "level 2 was not")
	eq(#L.sessions, 1)
	eq(L.sessions[1].t, 90)
	eq(L.days["2026-10-09"], 90, "the day")
	eq(L.hours[14], 90, "the hour")
	eq(L.weekdays[5], 90, "a Friday")
	eq(L.name, "Testchar")
	eq(L.class, "Mage")
	eq(L.level, 3)
end)

test("insights: AFK, loading screens and recording off are not counted", function()
	local stub, ns, ins = setup()
	local R = ins.Recorder
	stub.player.afk = true
	R.Play(10)
	stub.player.afk = false
	R.Tick(30) -- a loading screen
	eq(log().played, 0)
	stub.advance(1) -- the clock frame
	ok(math.abs(log().played - 1) < 0.01, "one second of play: " .. log().played)
	ns.Set("insights.record", false)
	R.Tick(1)
	stub.fire("PLAYER_DEAD")
	ok(math.abs(log().played - 1) < 0.01, "off: no time")
	eq(log().deaths, 0, "off: no deaths")
end)

test("insights: after a /reload the same step goes on being timed", function()
	local _, _, ins = setup()
	local R = ins.Recorder
	R.Play(45)
	R.OnStep({ route = ROUTE.id, step = 1, how = "login" })
	eq(#log().steps, 0, "nothing closed")
	R.Play(15)
	eq(log().cur.t, 60)
	R.OnStep({ route = ROUTE.id, step = 3, how = "login" })
	eq(log().steps[1].how, "moved")
	eq(log().cur.s, 3)
end)

test("insights: skipped steps and left steps are told apart", function()
	local stub, ns, ins = setup()
	local R = ins.Recorder
	R.Play(20)
	levelTo(stub, 4)
	R.Play(20)
	ns.Engine.SkipQuest(363)
	R.Play(20)
	ns.Engine.SetRoute("forever/horde/07-ashenvale")
	local L = log()
	eq(#L.steps, 3)
	eq(L.steps[1].how, "done")
	eq(L.steps[2].how, "skip")
	eq(L.steps[3].how, "moved")
	eq(L.routes[ROUTE.id].skips, 1)
end)

test("insights: quests (time taken in play, XP paid), kills and skill-ups", function()
	local stub, _, ins = setup()
	local R = ins.Recorder
	stub.accept(364)
	R.Play(130)
	stub.log[364] = nil
	stub.done[364] = true
	stub.fire("QUEST_TURNED_IN", 364, 450, 0)
	stub.accept(376)
	R.Play(5)
	stub.fire("QUEST_TURNED_IN", 376, 900, 0) -- handed in at once: not a "fastest"
	local L = log()
	eq(L.quests, 2)
	eq(L.records.fastQuest.t, 130)
	eq(L.records.fastQuest.name, "The Mindless Ones")
	eq(L.records.slowQuest.t, 130)
	eq(L.records.bestQuest.xp, 900)
	eq(L.sessions[1].q, 2)
	-- Kills: yours and your pet's, not someone else's.
	local ev
	function CombatLogGetCurrentEventInfo() return unpack(ev) end
	function UnitGUID(u) return u == "player" and "P-1" or (u == "pet" and "P-2" or nil) end
	for _, src in ipairs({ "P-1", "P-2", "P-9" }) do
		ev = { 0, "PARTY_KILL", false, src }
		stub.fire("COMBAT_LOG_EVENT_UNFILTERED")
	end
	ev = { 0, "SWING_DAMAGE", false, "P-1" }
	stub.fire("COMBAT_LOG_EVENT_UNFILTERED")
	eq(L.kills, 2)
	stub.skills[186] = { 12, 75 } -- Mining
	stub.fire("SKILL_LINES_CHANGED")
	stub.skills[186] = { 20, 75 }
	stub.fire("SKILL_LINES_CHANGED")
	eq(L.skills[186].from, 12)
	eq(L.skills[186].to, 20)
end)

-- Tirisfal Glades inside a continent (1415, as Eastern Kingdoms), where the
-- stub puts you at 40% + x/1000 across and 30% + y/1000 down.
local function continent(stub)
	local info = C_Map.GetMapInfo
	C_Map.GetMapInfo = function(m)
		if m == 1415 then return { name = "Eastern Kingdoms", mapType = 2 } end
		local i = info(m)
		if i then i.mapType, i.parentMapID = 3, 1415 end
		return i
	end
	local pos = C_Map.GetPlayerMapPosition
	C_Map.GetPlayerMapPosition = function(m, u)
		if m == 1415 then return CreateVector2D(0.4 + stub.player.x / 1000, 0.3 + stub.player.y / 1000) end
		return pos(m, u)
	end
end

test("insights: where you went: heat map cells, a trail, flights apart, distance", function()
	local stub, _, ins = setup({ before = continent })
	local R = ins.Recorder
	eq(R.ContinentOf(1420), 1415, "Tirisfal is in the continent")
	stub.moveTo(1420, 50, 50) -- 0.45, 0.35 on the continent
	R.Tick(1)
	R.Play(60)
	local L = log()
	eq(L.conts[1415], "Eastern Kingdoms")
	-- The zone too, on its own map: Tirisfal at 50, 50.
	eq(L.zonemaps[1420], "Tirisfal Glades")
	eq(L.trail[1420][1], 5000)
	ok(L.heat[1420][R.CellOf(0.5, 0.5)].t >= 60, "the zone's cell")
	eq(ins.Stats.Zones(L)[1].name, "Tirisfal Glades")
	eq(#L.trail[1415], 3, "one point")
	eq(L.trail[1415][1], 4500)
	eq(L.trail[1415][2], 3500)
	local cell = R.CellOf(0.45, 0.35)
	ok(L.heat[1415][cell].t >= 60, "the time lands in the cell")
	R.Tick(0.5) -- not a second yet: no look
	stub.moveTo(1420, 50.1, 50) -- 3 yards: too close for a new point, but walked
	R.Tick(0.6)
	eq(#L.trail[1415], 3, "too close for a new point")
	ok(math.abs(L.dist - 3) < 0.01, "3 yards: " .. L.dist)
	stub.player.taxi = true
	stub.moveTo(1420, 60, 50)
	R.Tick(1)
	eq(#L.trail[1415], 6, "a flight point")
	eq(L.trail[1415][6], 1, "marked as a flight")
	local cellNow = R.CellOf(0.46, 0.35)
	local before = L.heat[1415][cellNow] and L.heat[1415][cellNow].t or 0
	R.Play(30)
	eq(L.heat[1415][cellNow] and L.heat[1415][cellNow].t or 0, before, "no heat while flying")
	local St = ins.Stats
	local cells, top = St.Heat(L, 1415, "time")
	ok(#cells >= 1 and top >= 60, "the heat map")
	eq(St.Continents(L)[1].name, "Eastern Kingdoms")
end)

test("insights: records from levels, sessions, days and quests", function()
	local _, _, ins = setup()
	local St, R = ins.Stats, ins.Recorder
	eq(St.DayNumber("1970-01-01"), 0)
	eq(St.DayNumber("2026-10-10") - St.DayNumber("2026-10-09"), 1)
	eq(St.DayNumber("2026-03-01") - St.DayNumber("2026-02-28"), 1)
	eq(St.DayText("2026-10-09"), "9 Oct 2026")
	eq(St.Duration(4500), "1 h 15")
	eq(St.Duration(125), "2 min")
	eq(St.Duration(40), "40 s")
	eq(St.Distance(51500), "47.1 km")
	eq(St.Number(1234567), "1,234,567")
	local L = R.Log()
	L.level = 9
	L.levels = { [6] = { t = 900, full = true }, [7] = { t = 600, full = true }, [8] = { t = 2000, full = true },
		[5] = { t = 100 }, [9] = { t = 50, full = true } }
	L.sessions = { { start = os.time({ year = 2026, month = 10, day = 9, hour = 12 }), t = 3600, xp = 20000, q = 4 },
		{ start = os.time({ year = 2026, month = 10, day = 11, hour = 12 }), t = 9000, xp = 30000, q = 9 } }
	L.days = { ["2026-10-09"] = 3600, ["2026-10-10"] = 200, ["2026-10-11"] = 9000, ["2026-10-14"] = 60 }
	local rec = St.Records(L)
	eq(rec.fastLevel[1], "Level 7", "fastest of the levels seen whole")
	eq(rec.slowLevel[1], "Level 8")
	eq(rec.bestSession[1], "20,000 XP/h")
	eq(rec.bestSession[2], "9 Oct 2026 · 1 h 00")
	eq(rec.longSession[1], "2 h 30")
	eq(rec.mostQuests[1], "9 quests")
	eq(rec.bigDay[2], "11 Oct 2026")
	eq(rec.streak[1], "3", "9, 10 and 11 October")
	local t = St.Totals(L)
	eq(t.days, 4)
	eq(t.first, "2026-10-09")
	eq(t.last, "2026-10-14")
end)

test("insights: every character on the account, hidden or deleted", function()
	local _, _, ins = setup()
	local R = ins.Recorder
	PathwiseInsightsData.chars["Alt-Test Realm"] = { race = "Gnome", class = "Warlock", level = 18, last = 1 }
	local chars = R.Characters()
	eq(#chars, 2)
	eq(chars[1].key, "Testchar-Test Realm", "the last played first")
	eq(ins.Stats.CharLabel(chars[2].log, chars[2].key), "Gnome Warlock lvl 18")
	R.Hide("Alt-Test Realm", true)
	ok(PathwiseInsightsData.chars["Alt-Test Realm"].hidden, "hidden")
	R.Delete("Alt-Test Realm")
	eq(PathwiseInsightsData.chars["Alt-Test Realm"], nil, "deleted")
end)

test("insights: the window: tabs per character, tiles, records, the map; delete asks first", function()
	local stub, ns, ins = setup({ before = continent })
	local R, Win = ins.Recorder, ins.Window
	PathwiseInsightsData.chars["Alt-Test Realm"] = { race = "Gnome", class = "Warlock", level = 18, last = 1 }
	stub.moveTo(1420, 50, 50)
	R.Tick(1)
	R.Play(600)
	stub.player.xp = 700
	stub.fire("PLAYER_XP_UPDATE", "player")
	levelTo(stub, 3)
	Win.Open()
	ok(Win.Shown(), "open")
	local texts = stub.texts()
	for _, want in ipairs({ "Pathwise Insights", "Overview", "Map", "Undead Mage lvl 3", "Gnome Warlock lvl 18",
		"Time played", "10 min", "XP per hour", "5,391", "Turned in", "Monsters killed", "Distance travelled",
		"Records", "When you play", "Routes", "Insights (test)", "Zones", "Tirisfal Glades", "Where you stand" }) do
		ok(contains(texts, want), "shows " .. want)
	end
	ok(stub.clickLabelText("Gnome Warlock"), "the alt's tab")
	ok(contains(stub.texts(), "Gnome  ·  Warlock  ·  Level 18"), "the alt's numbers")
	ok(stub.clickLabelText("Delete this character"), "Delete")
	ok(PathwiseInsightsData.chars["Alt-Test Realm"], "not yet")
	ok(stub.clickLabelText("Yes, delete it"), "Yes")
	eq(PathwiseInsightsData.chars["Alt-Test Realm"], nil, "deleted")
	ok(stub.clickLabelText("Map"), "the Map tab")
	texts = stub.texts()
	ok(contains(texts, "Eastern Kingdoms"), "the continent")
	ok(stub.clickLabelText("Tirisfal Glades"), "a zone you went to")
	ok(contains(stub.texts(), "in one spot"), "its heat map")
	ok(contains(texts, "Time spent"), "the layers")
	ok(contains(texts, "in one spot"), "the legend")
	ok(stub.clickLabelText("XP an hour"), "the XP layer")
	eq(ns.Get("insights.layer"), "rate")
	local listed = false
	for _, m in ipairs(Pathwise.Suite.Modules()) do if m.key == "insights" then listed = true end end
	ok(listed, "in Settings > Pathwise suite")
end)
