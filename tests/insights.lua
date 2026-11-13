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
	PathwiseInsightsSettings, PathwiseInsightsCharSettings, PathwiseInsights = nil, nil, nil
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
	ins.Set("insights.record", false)
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
	-- Kills: from the game's XP message (Forever keeps the combat log from
	-- addons), not from quest XP or a text the game keeps secret.
	ok(not stub.events["COMBAT_LOG_EVENT_UNFILTERED"], "the combat log is not registered")
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience.")
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Worker dies, you gain 60 experience. (+30 exp Rested bonus)")
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "You gain 900 experience.")
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Experience gained: 900.")
	issecretvalue = function() return true end
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience.")
	issecretvalue = nil
	eq(L.kills, 2)
	stub.skills[186] = { 12, 75 } -- Mining
	stub.fire("SKILL_LINES_CHANGED")
	stub.skills[186] = { 20, 75 }
	stub.fire("SKILL_LINES_CHANGED")
	eq(L.skills[186].from, 12)
	eq(L.skills[186].to, 20)
end)

test("insights: kills are read with the client's own strings, in any language", function()
	COMBATLOG_XPGAIN_FIRSTPERSON = "%1$s stirbt, Ihr bekommt %2$d Erfahrung."
	COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s stirbt, Ihr bekommt %d Erfahrung. (+%d Gruppenbonus)"
	COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "Ihr bekommt %d Erfahrung."
	local _, _, ins = setup()
	local R = ins.Recorder
	ok(R.IsKill("Koboldungeziefer stirbt, Ihr bekommt 45 Erfahrung."))
	ok(R.IsKill("Koboldarbeiter stirbt, Ihr bekommt 60 Erfahrung. (+12 Gruppenbonus)"))
	ok(not R.IsKill("Ihr bekommt 900 Erfahrung."), "quest XP is not a kill")
	ok(not R.IsKill("Kobold Vermin dies, you gain 45 experience."), "another language's text is not read")
	ok(not R.IsKill(nil))
	COMBATLOG_XPGAIN_FIRSTPERSON, COMBATLOG_XPGAIN_FIRSTPERSON_GROUP, COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = nil, nil, nil
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
	PathwiseInsightsData.chars["Alt-Test Realm"] = { race = "Gnome", class = "Warlock", faction = "Alliance", level = 18, last = 1 }
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
	eq(Win.frames.crest.faction, "Horde", "an Undead: the Horde crest")
	ok(stub.clickLabelText("Gnome Warlock"), "the alt's tab")
	ok(contains(stub.texts(), "Gnome  ·  Warlock  ·  Level 18"), "the alt's numbers")
	eq(Win.frames.crest.faction, "Alliance", "a Gnome: the Alliance crest")
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
	eq(ins.Get("insights.layer"), "rate")
	local listed = false
	for _, m in ipairs(Pathwise.Suite.Modules()) do if m.key == "insights" then listed = true end end
	ok(listed, "in Settings > Pathwise suite")
end)

test("insights: the share code: what goes in, what never does, and reading it back", function()
	local stub, _, ins = setup()
	local R, Sh = ins.Recorder, ins.Share
	eq(Sh.Decode64(Sh.Encode64("Pathwise!")), "Pathwise!")
	eq(Sh.Decode64(Sh.Encode64("ab")), "ab")
	eq(Sh.Decode64(Sh.Encode64("a")), "a")
	R.Play(90)
	levelTo(stub, 3, 50)
	R.Play(30)
	local code, L = Sh.CodeFor()
	ok(code:match("^PWI1:[%w%+/=]+:%x+$"), "one line: " .. code:sub(1, 30))
	ok(L.shareId and #L.shareId == 10, "a random id for the character")
	eq(select(2, Sh.CodeFor()), L)
	eq(Sh.CodeFor(), code, "the same id each time")
	local text = Sh.Decode64(code:match("^PWI1:([^:]+):"))
	ok(not text:find("Testchar"), "no name")
	ok(not text:find("Test Realm"), "no realm")
	local p = assert(Sh.Read(code))
	eq(p.id, L.shareId)
	eq(p.race, "Undead")
	eq(p.class, "Mage")
	eq(p.faction, "Horde")
	eq(p.level, 3)
	eq(p.played, 120)
	eq(#p.steps, 1)
	eq(p.steps[1].route, ROUTE.id)
	eq(p.steps[1].step, 1)
	eq(p.steps[1].t, 90)
	eq(p.steps[1].how, "done")
	eq(p.routes[ROUTE.id].steps, 1)
	ok(p.levels[3].full, "level 3 seen from its start")
	eq(p.zones[1420].t, 120)
	-- A code cut short, changed, or not a code at all.
	local cut = code:sub(1, #code - 20) .. code:sub(-5)
	ok(not Sh.Read(cut), "cut short")
	local body = code:match("^PWI1:([^:]+):")
	local changed = code:gsub(body:sub(5, 8), body:sub(5, 8) == "AAAA" and "BBBB" or "AAAA", 1)
	ok(not Sh.Read(changed), "changed by hand")
	ok(not Sh.Read("hello"), "not a code")
	-- Spaces and line breaks from a paste do not matter.
	ok(Sh.Read(code:sub(1, 40) .. "\n  " .. code:sub(41)), "a pasted code with a line break")
end)

test("insights: the Share tab shows the code, what is in it, and where to send it; it resizes with the window", function()
	local stub, ns, ins = setup()
	local Win = ins.Window
	ins.Recorder.Play(120)
	Win.Open()
	ok(stub.clickLabelText("Make a share code"), "the button on the Overview")
	eq(Win.state.page, "share", "the Share tab")
	local texts = stub.texts()
	for _, want in ipairs({ "Help tune the guides", "WHAT IS IN YOUR CODE", "Guide steps", "Quests", "Deaths", "Totals",
		"Your code", "Never in it", "Your character's name, realm or guild", "SEND IT", "On GitHub", "On Discord" }) do
		ok(contains(texts, want), "shows " .. want)
	end
	local boxes = {}
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "text")
		if f.kind == "EditBox" and type(t) == "string" and f.shown then boxes[#boxes + 1] = t end
	end
	ok(boxes[1] and boxes[1]:match("^PWI1:"), "the code in a box to copy")
	ok(contains(boxes, "github.com/pathwise-nn/Pathwise/issues/new?template=leveling_numbers.yml"), "the GitHub form")
	ok(contains(boxes, Pathwise.Suite.DISCORD), "the Discord invite")
	ok(ins.Share.Read(boxes[1]), "a code that reads back")
	-- Typing in the box changes nothing.
	for _, f in ipairs(stub.frames) do
		if f.kind == "EditBox" and f.text == boxes[1] then
			f:SetText("hello")
			f.scripts.OnTextChanged(f, true)
			eq(f.text, boxes[1], "the code stays")
		end
	end
	-- The tabs: Overview, Map, Share.
	ok(stub.clickLabelText("Overview"), "back to the Overview")
	eq(Win.state.page, "overview")
	ok(stub.clickLabelText("Share"), "the Share tab from the header")
	eq(Win.state.page, "share")
	-- Narrow: the cards go one under another, still all there.
	PathwiseInsightsWindow:SetWidth(640)
	Win.Draw()
	ok(contains(stub.texts(), "On Discord"), "narrow")
end)

test("insights: the import tool reads codes, keeps the newest per character, and flags steps", function()
	local stub, _, ins = setup()
	local Sh = ins.Share
	-- Three players on the route: step 2 slow for all, step 3 skipped by two.
	local function player(id, played, t2, skip3)
		return Sh.Make({ shareId = id, race = "Gnome", class = "Mage", faction = "Alliance", level = 10, played = played, xp = 5000,
			steps = { { r = ROUTE.id, s = 1, t = 60, xp = 100, d = 0, lvl = 2, how = "done" },
				{ r = ROUTE.id, s = 2, t = t2, xp = 100, d = 1, lvl = 3, how = "done" },
				{ r = ROUTE.id, s = 3, t = 30, xp = 0, d = 0, lvl = 4, how = skip3 and "skip" or "done" },
				{ r = ROUTE.id, s = 4, t = 70, xp = 100, d = 0, lvl = 4, how = "done" } },
			routes = { [ROUTE.id] = { t = 3000, xp = 4000, d = 1, steps = 3, skips = skip3 and 1 or 0, done = true } },
			levels = { [3] = { t = 900, full = true } }, zones = {} })
	end
	local dir = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/pathwise-insights-test.txt"
	local f = assert(io.open(dir, "wb"))
	f:write("issue one\n", player("aaaaaaaaaa", 100, 600, true), "\n")
	f:write("issue two\n", player("bbbbbbbbbb", 100, 700, true), "\n")
	f:write("an older code\n", player("cccccccccc", 50, 50, false), "\n")
	f:write("the newer one\n", player("cccccccccc", 200, 800, false), "\n")
	f:write("broken: PWI1:QUJD:ffff\n")
	f:close()
	local p = io.popen('lua5.1 tools/insights/import.lua "' .. dir .. '"')
	local report = p:read("*a")
	p:close()
	os.remove(dir)
	ok(report:find("3 characters %(5 codes read, 1 could not be read%)"), report:sub(1, 200))
	ok(report:find("test/insights  %(3 players, 3 finished%)"), "the route")
	ok(report:find("step   2  median 11m40s"), "step 2's median: the newer code's 800 s, with 600 and 700")
	ok(report:find("step   2[^\n]*SLOW"), "step 2 is slow")
	ok(report:find("step   2[^\n]*DEADLY"), "a death each time")
	ok(report:find("step   3[^\n]*OFTEN SKIPPED"), "step 3 skipped by two of three")
	ok(not report:find("step   1[^\n]*<%-"), "step 1 is fine")
	ok(report:find("level  3  median 15m00s"), "time per level")
end)

test("insights: for the guides: each step's version, kills, yards, flying, group and end; quests and deaths with places", function()
	local stub, ns, ins = setup({ before = continent })
	local R, Sh = ins.Recorder, ins.Share
	local L = log()
	eq(L.cur.v, "0.1.0-test", "the step is timed on this Pathwise version")
	-- Kills, yards, a group, a flight, a death, on step 1.
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience.")
	stub.fire("CHAT_MSG_COMBAT_XP_GAIN", "Kobold Vermin dies, you gain 45 experience.")
	stub.moveTo(1420, 50, 50)
	R.Tick(1)
	stub.moveTo(1420, 51, 50) -- 30 yards west
	R.Tick(1)
	function IsInGroup() return true end
	R.Play(20)
	IsInGroup = nil
	stub.player.taxi = true
	R.Tick(1)
	R.Play(10)
	stub.player.taxi = false
	R.Tick(1)
	stub.fire("PLAYER_DEAD")
	-- A quest taken here and handed in there; another abandoned.
	stub.moveTo(1420, 30, 70)
	stub.accept(364)
	R.Play(100)
	stub.moveTo(1420, 32, 66)
	stub.log[364] = nil
	stub.done[364] = true
	stub.fire("QUEST_TURNED_IN", 364, 450, 0)
	stub.fire("QUEST_REMOVED", 364)
	stub.accept(376)
	R.Play(40)
	stub.log[376] = nil
	stub.fire("QUEST_REMOVED", 376)
	levelTo(stub, 3) -- step 1 ends
	local st = L.steps[1]
	eq(st.v, "0.1.0-test")
	eq(st.k, 2, "kills")
	ok(math.abs(st.yd - 30) < 0.6, "yards walked: " .. st.yd)
	eq(st.grp, 20, "in a group")
	eq(st.fly, 11, "on a flight: the second it was seen, and ten more")
	eq(st.m, 1420, "where it ended")
	eq(st.x, 320)
	eq(st.y, 660)
	eq(#L.questLog, 2, "the handed-in quest and the abandoned one")
	local q = L.questLog[1]
	eq(q.q, 364)
	eq(q.t, 100)
	eq(q.xp, 450)
	eq(q.am, 1420)
	eq(q.ax, 300)
	eq(q.ay, 700)
	eq(q.tx, 320)
	eq(q.ty, 660)
	ok(not q.ab, "handed in, not abandoned")
	eq(L.questLog[2].q, 376)
	ok(L.questLog[2].ab, "abandoned")
	eq(L.questLog[2].t, 40)
	eq(#L.deathLog, 1)
	eq(L.deathLog[1].m, 1420)
	eq(L.deathLog[1].x, 510)
	eq(L.deathLog[1].r, ROUTE.id)
	eq(L.deathLog[1].s, 1)
	-- All of it in the code, and back.
	local p = assert(Sh.Read((Sh.CodeFor())))
	eq(p.version, "0.1.0-test")
	local s1 = p.steps[1]
	eq(s1.version, "0.1.0-test")
	eq(s1.kills, 2)
	eq(s1.grouped, 20)
	eq(s1.flying, 11)
	eq(s1.map, 1420)
	ok(math.abs(s1.x - 0.32) < 1e-9, "x")
	eq(#p.quests, 2)
	eq(p.quests[1].quest, 364)
	eq(p.quests[1].xp, 450)
	ok(math.abs(p.quests[1].inX - 0.32) < 1e-9, "where it was handed in")
	ok(p.quests[2].abandoned, "abandoned")
	eq(#p.deaths, 1)
	eq(p.deaths[1].route, ROUTE.id)
	eq(p.deaths[1].step, 1)
end)

test("insights: the import tool: quests slow for their XP, abandoned, handed in away from the data; death spots", function()
	local _, ns, ins = setup()
	local Sh = ins.Share
	local fin = ns.Quests.Finisher(364) -- where the data puts the hand-in
	ok(fin and fin.map == 1420, "364 is handed in in Tirisfal")
	local function player(id, off)
		local quests = {
			-- 364: handed in `off` map units east of where the data says.
			{ q = 364, t = 300, xp = 450, lvl = 3, tm = 1420, tx = math.floor((fin.x + off) * 10), ty = math.floor(fin.y * 10) },
			-- 376: abandoned by everyone but one.
			{ q = 376, t = 100, xp = 0, lvl = 3, ab = id ~= "aaaaaaaaaa" },
			-- 3901: slow for what it pays.
			{ q = 3901, t = 3000, xp = 100, lvl = 4 },
			{ q = 3095, t = 120, xp = 400, lvl = 4 },
			{ q = 3098, t = 120, xp = 400, lvl = 4 },
		}
		return Sh.Make({ shareId = id, race = "Undead", class = "Mage", faction = "Horde", level = 5, played = 1000, xp = 2000,
			steps = {}, routes = {}, levels = {}, zones = {}, questLog = quests,
			deathLog = { { m = 1420, x = 455, y = 655, lvl = 4, r = ROUTE.id, s = 2 } } })
	end
	local file = (os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp") .. "/pathwise-insights-test2.txt"
	local f = assert(io.open(file, "wb"))
	f:write(player("aaaaaaaaaa", 8), "\n", player("bbbbbbbbbb", 8), "\n", player("cccccccccc", 8), "\n")
	f:close()
	local p = io.popen('lua5.1 tools/insights/import.lua "' .. file .. '"')
	local report = p:read("*a")
	p:close()
	os.remove(file)
	ok(report:find("== Quests =="), report:sub(1, 300))
	ok(report:find("364 The Mindless Ones[^\n]*handed in at 1420 [%d%.]+, [%d%.]+: the data says"), "364's hand-in is away from the data")
	ok(report:find("376 [^\n]*OFTEN ABANDONED"), "376 abandoned")
	ok(report:find("3901 [^\n]*SLOW FOR ITS XP"), "3901 slow for its XP")
	ok(not report:find("3095 [^\n]*<%-"), "3095 is fine")
	ok(report:find("map 1420  45, 65  3 deaths, 3 players, median level 4  %(mostly test/insights step 2%)"), "the death spot")
end)

---------------------------------------------------------------------------
-- On its own: no Pathwise installed
---------------------------------------------------------------------------

-- A fresh client with Pathwise Insights only (no Pathwise), logged in.
local function alone(before)
	PathwiseSettings, PathwiseCharSettings, Pathwise = nil, nil, nil
	PathwiseInsightsData, PathwiseInsightsSettings, PathwiseInsightsCharSettings, PathwiseInsights = nil, nil, nil, nil
	local stub = dofile("./tests/stub.lua")
	stub.player.level, stub.player.xp, stub.player.xpMax, stub.player.afk = 1, 0, 400, false
	function UnitXP() return stub.player.xp end
	function UnitXPMax() return stub.player.xpMax end
	function UnitIsAFK() return stub.player.afk end
	function UnitName() return "Testchar" end
	function GetRealmName() return "Test Realm" end
	stub.clock = os.time({ year = 2026, month = 10, day = 9, hour = 14 })
	function time() return stub.clock end
	CombatLogGetCurrentEventInfo, UnitGUID = nil, nil
	if before then before(stub) end
	local ins = stub.loadAddon(".", "Pathwise_Insights")
	stub.moveTo(1420, 30.2, 71.6)
	stub.fire("ADDON_LOADED", "Pathwise_Insights")
	stub.fire("PLAYER_LOGIN")
	return stub, ins
end

test("insights alone: loads and records without Pathwise; the window, its options and the share code work", function()
	local stub, ins = alone()
	eq(rawget(_G, "Pathwise"), nil, "no Pathwise")
	ok(not ins.S.Guide.Available(), "no guide")
	ins.Recorder.Play(90)
	stub.player.xp = 300
	stub.fire("PLAYER_XP_UPDATE", "player")
	local L = log()
	eq(L.played, 90)
	eq(L.xp, 300)
	eq(L.race, "Undead")
	stub.skills[186] = { 12, 75 }
	stub.fire("SKILL_LINES_CHANGED")
	eq(L.skills[186].from, 12, "professions from the game")
	eq(ins.S.Quests.Name(363), "Quest 363", "no data: the game's name, else a number")
	SlashCmdList.PATHWISEINSIGHTS("")
	ok(ins.Window.Shown(), "/pwinsights opens it")
	ok(contains(stub.texts(), "Time played"), "the Overview")
	SlashCmdList.PATHWISEINSIGHTS("share")
	eq(ins.Window.state.page, "share")
	ok(ins.Share.Read((ins.Share.CodeFor())), "a code that reads back")
	ins.Window.Close()
	SlashCmdList.PATHWISEINSIGHTS("options")
	ok(contains(stub.texts(), "Install Pathwise: Leveling & Professions to time each guide step"), "the options say what Pathwise adds")
end)

test("insights alone: follows the quest log against its own copy of the routes, with Pathwise's step numbers", function()
	local stub, ins = alone()
	local R, K = ins.Recorder, ins.Track
	ok(K.Active(), "on without Pathwise")
	local ROUTE_ID = "forever/horde/undead/01-tirisfal-glades"
	ok(K.byId[ROUTE_ID], "the route is bundled")
	eq(log().cur, nil, "no quest yet: no route")
	-- Step 1 takes Rude Awakening (363): taken, so step 2 (hand it in) is live.
	stub.accept(363)
	eq(log().track.route, ROUTE_ID, "the route of the quest")
	eq(log().cur.r, ROUTE_ID)
	eq(log().cur.s, 2)
	eq(log().cur.src, "quests")
	R.Play(50)
	-- Step 2: hand it in, take The Mindless Ones (364).
	stub.turnin(363)
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	local L = log()
	eq(#L.steps, 1, "step 2 is done")
	eq(L.steps[1].s, 2)
	eq(L.steps[1].t, 50)
	eq(L.steps[1].how, "done")
	eq(L.steps[1].src, "quests")
	eq(L.steps[1].v, "0.1.0-test", "the routes' version (Insights' own)")
	eq(L.cur.s, 3, "step 3: do 364")
	R.Play(120)
	stub.progress(364, 1, 8)
	eq(#L.steps, 2, "objectives done: step 3 is done")
	eq(L.steps[2].s, 3)
	eq(L.steps[2].t, 120)
	eq(L.cur.s, 4)
	-- In the share code, told apart from Pathwise's timing.
	local p = assert(ins.Share.Read((ins.Share.CodeFor())))
	eq(p.steps[1].src, "quests")
	eq(p.steps[1].route, ROUTE_ID)
end)

test("insights with Pathwise: Pathwise says where you are; the quest-log tracker stays off", function()
	local stub, ns, ins = setup()
	ok(not ins.Track.Active(), "off with Pathwise")
	ins.Recorder.Play(30)
	levelTo(stub, 3)
	eq(log().steps[1].src, "guide")
end)

test("insights: the bundled routes are up to date with Pathwise's", function()
	local p = io.popen("lua5.1 tools/insights/routes.lua --check 2>&1")
	local out = p:read("*a")
	p:close()
	ok(out:find("is up to date"), out)
end)
