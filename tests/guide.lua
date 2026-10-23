-- Tests for the data (Pathwise/Data/Data.lua), the guide engine, the routes
-- (converted from Polestar) and the panels. Loaded by tests/run.lua.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

-- A small fixed route for the engine's behaviour, independent of the big
-- converted routes (real quest ids from the data: the Deathknell start).
local FIXTURE = {
	id = "test/deathknell", title = "Deathknell (test)", category = "Leveling", map = 1420,
	levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
	steps = {
		{ { "accept", 363 } },
		{ { "turnin", 363 }, { "accept", 364 } },
		{ { "accept", 376 }, { "accept", 1470 } },
		{ title = "North of Deathknell", { "complete", 364 }, { "complete", 376 }, { "complete", 1470 } },
		{ { "turnin", 364 }, { "accept", 3901 }, { "accept", 3095 }, { "accept", 3098 } },
		{ title = "Your class trainer", { "turnin", 3095 }, { "turnin", 3098 } },
		{ { "turnin", 376 }, { "accept", 6395 } },
		{ title = "Gear up", { "have", 2589, 10, name = "Linen Cloth" }, { "bind", "Brill", at = { 1420, 61.7, 52.0 }, who = "Innkeeper Renee" },
			{ "note", "Hearth to Brill" }, { "goto", 1420, 33.0, 63.0, "The graveyard", optional = true } },
		{ title = "Mages only", only = { classes = { "MAGE" } }, { "note", "Train Frost Armor" }, { "level", 4 } },
		{ title = "Warriors only", only = { classes = { "WARRIOR" } }, { "level", 4 } },
	},
}

local function login(setup)
	local stub, ns = fresh()
	stub.player.level = 2 -- The Damned asks for level 2
	if setup then setup(stub) end
	stub.moveTo(1420, 30.2, 71.6) -- Undertaker Mordo's crypt, where Undead start
	stub.login()
	return stub, ns
end

local function fixture(setup)
	local stub, ns = login(setup)
	ok(Pathwise.RegisterRoute(FIXTURE), "fixture registers")
	ns.Engine.SetRoute(FIXTURE.id)
	return stub, ns
end

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

test("data: the Deathknell quests, their people and places, and Skyborne race bits", function()
	local _, ns = fresh()
	local Q = ns.Quests
	eq(Q.Name(364), "The Mindless Ones")
	local giver = Q.Giver(364)
	eq(giver.name, "Shadow Priest Sarvis")
	eq(giver.map, 1420)
	near(giver.x, 30.84, 0.01, "x")
	eq(Q.Finisher(383).name, "Executor Zygand")
	eq(Q.Get(364)[4], 8589934770)
	ok(Q.HasBit(Q.Get(364)[4], 8589934592), "Skyborne Horde bit")
	ok(Q.HasBit(Q.Get(364)[4], 16), "Undead bit")
end)

test("data: zone levels for Tirisfal and Silverpine are leveling ranges, Horde only", function()
	local _, ns = fresh()
	local z = ns.Quests.Data.zones
	ok(z[1420].horde[1] <= 5 and z[1420].horde[2] <= 15, "Tirisfal is a starting zone")
	ok(z[1421].horde[1] >= 8 and z[1421].horde[2] <= 25, "Silverpine follows it")
	eq(z[1420].alliance, nil)
end)

---------------------------------------------------------------------------
-- The converted routes
---------------------------------------------------------------------------

test("routes: every converted route loads (57 leveling, 66 class, 12 professions)", function()
	local stub, ns = fresh()
	for _, m in ipairs(stub.printed) do ok(not m:find("error"), m) end
	local count = {}
	for _, r in ipairs(ns.Engine.Routes()) do count[r.category] = (count[r.category] or 0) + 1 end
	eq(count.Leveling, 57)
	eq(count.Class, 66)
	eq(count.Professions, 12)
	for _, r in ipairs(ns.Engine.Routes()) do
		local problems = ns.Engine.Check(r)
		eq(#problems, 0, r.id .. ": " .. table.concat(problems, "; "))
	end
end)

test("routes: every next route exists, and coordinates are on the map", function()
	local _, ns = fresh()
	local routes = ns.Engine.routes
	for _, r in ipairs(ns.Engine.Routes()) do
		if r.next then ok(routes[r.next], r.id .. " -> " .. r.next) end
		for i, step in ipairs(r.steps) do
			for _, g in ipairs(step) do
				local a = g.at or (g[1] == "goto" and { g[2], g[3], g[4] })
				if a then ok(a[2] >= 0 and a[2] <= 100 and a[3] >= 0 and a[3] <= 100, ("%s step %d: %s,%s"):format(r.id, i, a[2], a[3])) end
			end
		end
	end
end)

-- Every race starts at level 1 and its chain of routes reaches 60.
local CHARACTERS = {
	{ "Human", 1, "Alliance" }, { "Dwarf", 3, "Alliance" }, { "Gnome", 7, "Alliance" }, { "NightElf", 4, "Alliance" }, { "Skyborne", 95, "Alliance" },
	{ "Orc", 2, "Horde" }, { "Troll", 8, "Horde" }, { "Tauren", 6, "Horde" }, { "Scourge", 5, "Horde" }, { "Skyborne", 96, "Horde" },
}
test("routes: every race and side has a route from level 1 that chains to 60", function()
	local _, ns = fresh()
	local E = ns.Engine
	for _, c in ipairs(CHARACTERS) do
		local p = { race = c[1], raceID = c[2], faction = c[3], level = 1, class = "WARRIOR" }
		local r = E.BestRoute(p, nil)
		ok(r, c[1] .. " " .. c[3] .. ": a first route")
		eq(r.levels[1], 1, c[1] .. " starts at 1 (" .. r.id .. ")")
		local hops, last = 0, r
		while last.next and hops < 40 do
			last = E.routes[last.next]
			hops = hops + 1
			ok(E.Fits(last, p), c[1] .. ": " .. last.id .. " fits")
		end
		eq(last.levels[2], 60, c[1] .. " " .. c[3] .. " ends at 60 (" .. last.id .. ")")
	end
end)

test("routes: Polestar's places agree with QuestieDB's, also on the four maps Forever changed", function()
	local _, ns = fresh()
	local Q = ns.Quests
	local byMap, n, far = {}, 0, 0
	for _, r in ipairs(ns.Engine.Routes()) do
		for _, step in ipairs(r.steps) do
			for _, g in ipairs(step) do
				if g[1] == "accept" and g.at and Q.Get(g[2]) then
					local giver = Q.Giver(g[2], { map = g.at[1], x = g.at[2], y = g.at[3] })
					if giver and giver.map == g.at[1] then
						local d = math.sqrt((giver.x - g.at[2]) ^ 2 + (giver.y - g.at[3]) ^ 2)
						n = n + 1
						if d > 2 then far = far + 1 end
						local m = byMap[g.at[1]] or { n = 0, sum = 0 }
						m.n, m.sum = m.n + 1, m.sum + d
						byMap[g.at[1]] = m
					end
				end
			end
		end
	end
	ok(n > 1000, "compared " .. n .. " quest givers")
	ok(far / n < 0.03, ("%d of %d givers more than 2 map units apart"):format(far, n))
	for _, map in ipairs({ 1412, 1423, 1433, 1453 }) do
		local m = byMap[map]
		ok(m and m.n > 3, "givers compared on map " .. map)
		ok(m.sum / m.n < 1.0, ("map %d: average %.2f units apart"):format(map, m.sum / m.n))
	end
end)

test("an Undead character starts on Polestar's Tirisfal route at Undertaker Mordo", function()
	local stub, ns = login()
	eq(ns.Engine.Route().id, "forever/horde/undead/01-tirisfal-glades")
	local v = ns.Guide.View()
	eq(v.title, "Undertaker Mordo")
	eq(ns.Nav.Target().title, "Undertaker Mordo")
end)

test("a saved choice of the old hand-written Tirisfal route finds the new one", function()
	local stub, ns = login(function() PathwiseCharSettings = { schema = 1, guide = { route = "horde/undead/tirisfal" } } end)
	eq(ns.Engine.Route().id, "forever/horde/undead/01-tirisfal-glades")
end)

test("a level 30 Tauren in Desolace gets the Desolace route", function()
	local stub, ns = fresh()
	local E = ns.Engine
	local r = E.BestRoute({ race = "Tauren", raceID = 6, faction = "Horde", level = 31, class = "WARRIOR" }, 1443)
	eq(r.id, "forever/horde/30-40/01-desolace")
end)

---------------------------------------------------------------------------
-- The engine (fixture route)
---------------------------------------------------------------------------

test("the route follows the quest log: accept, hand in, objectives", function()
	local stub, ns = fixture()
	eq(ns.Guide.View().title, "Undertaker Mordo")
	stub.accept(363)
	eq(ns.Guide.View().title, "Shadow Priest Sarvis", "after accepting: hand in at Sarvis")
	stub.turnin(363)
	eq(ns.Engine.LiveStep(), 2, "still at Sarvis: accept The Mindless Ones")
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false },
		{ text = "Wretched Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	eq(ns.Guide.View().title, "Novice Elreth")
	stub.accept(376, { { text = "Scavenger Paw: 0/6", numFulfilled = 0, numRequired = 6, finished = false } })
	local v = ns.Guide.View()
	eq(v.title, "North of Deathknell")
	eq(v.objectives[1].text, "Mindless Zombie", "the log's text without the count")
	stub.progress(364, 1, 5)
	eq(ns.Guide.View().objectives[1].have, 5)
	eq(ns.Nav.Target().title, "Mindless Zombie", "the arrow leads to the first unfinished objective")
	stub.progress(364, 1, 8)
	eq(ns.Nav.Target().title, "Wretched Zombie", "then to the next")
end)

test("class quests: a mage gets the Glyphic Scroll, not the warrior's or warlock's", function()
	local stub, ns = fixture()
	stub.accept(363) stub.turnin(363) stub.accept(364, {}) stub.accept(376)
	for _, row in ipairs(ns.Guide.View().objectives) do ok(not row.text:find("Piercing the Veil"), "no warlock quest") end
	stub.log[364].ready = true
	stub.turnin(364)
	local texts = {}
	for _, r in ipairs(ns.Guide.View().objectives) do texts[#texts + 1] = r.text end
	ok(contains(texts, "Accept Glyphic Scroll"), table.concat(texts, " | "))
	ok(not contains(texts, "Simple Scroll"), "no warrior scroll")
end)

test("a quest not offered yet does not hold the route, which comes back for it", function()
	local stub, ns = fixture(function(s) s.player.level = 1 end)
	stub.accept(363) stub.turnin(363) stub.accept(364, {})
	eq(ns.Guide.View().title, "North of Deathknell", "The Damned asks for level 2: on to the zombies")
	stub.player.level = 2
	stub.fire("PLAYER_LEVEL_UP", 2)
	eq(ns.Guide.View().title, "Novice Elreth", "and back for it at level 2")
end)

local function toGearUp(stub, ns)
	stub.accept(363) stub.turnin(363)
	for _, q in ipairs({ 364, 376, 3901, 3098 }) do stub.accept(q) end
	for _, q in ipairs({ 364, 3098, 376 }) do stub.turnin(q) end
	stub.accept(6395)
end

test("have, bind, notes and optional goals", function()
	local stub, ns = fixture()
	toGearUp(stub, ns)
	local v = ns.Guide.View()
	eq(v.title, "Gear up")
	local texts, optional, info = {}, false, false
	for _, r in ipairs(v.objectives) do
		texts[#texts + 1] = r.text
		if r.text == "The graveyard" then optional = r.optional end
		if r.text == "Hearth to Brill" then info = r.info end
	end
	ok(contains(texts, "Get 10 Linen Cloth (0)"), table.concat(texts, " | "))
	ok(contains(texts, "Make Brill your home"), "bind")
	ok(info, "a note row, marked as an instruction")
	ok(optional, "optional goal marked")
	stub.items[2589] = 10
	stub.bind = "Brill"
	stub.fire("BAG_UPDATE_DELAYED")
	ok(ns.Guide.View().title ~= "Gear up", "items and hearthstone done: the optional goto does not hold the step")
end)

test("class-only steps: a mage gets the mage step, not the warrior's", function()
	local stub, ns = fixture(function(s) s.player.level = 3 end)
	toGearUp(stub, ns)
	stub.items[2589] = 10
	stub.bind = "Brill"
	stub.fire("BAG_UPDATE_DELAYED")
	eq(ns.Guide.View().title, "Mages only")
	stub.player.level = 4
	stub.fire("PLAYER_LEVEL_UP", 4)
	eq(ns.Guide.View().title, "Route complete", "the warrior step is not for a mage")
end)

test("skip: just the quest, or the quest and its follow-ups", function()
	local stub, ns = fixture()
	stub.accept(363) stub.turnin(363) stub.accept(364, {})
	local E = ns.Engine
	eq(E.SkippableQuests()[1], 376, "The Damned is the open quest at Novice Elreth")
	local list = E.SkipQuest(376, true)
	local skipped = {}
	for _, q in ipairs(list) do skipped[q] = true end
	ok(skipped[380] and skipped[3902] and skipped[6395], "its follow-ups")
	ok(E.LiveStep() > 3, "the route moved past Elreth")
	E.UnskipQuest(376)
	eq(E.LiveStep(), 3, "brought back")
end)

test("alternatives: nearby, at the player's level, not already in the route", function()
	local stub, ns = fixture()
	stub.player.level = 7
	stub.moveTo(1420, 60.6, 51.8) -- Brill
	local alts = ns.Engine.Alternatives(5)
	ok(#alts > 0, "some quests around Brill at level 7")
	local last = 0
	for _, a in ipairs(alts) do
		ok(a.level >= 5 and a.level <= 10, a.name .. " level " .. a.level)
		ok((a.yards or 0) >= last, "nearest first")
		last = a.yards or last
	end
end)

test("an alternative goes ahead of the route, which resumes after it", function()
	local stub, ns = fixture()
	stub.player.level = 7
	stub.moveTo(1420, 60.6, 51.8)
	local alt = ns.Engine.Alternatives(1)[1]
	ns.Engine.AddExtra(alt.quest)
	local v = ns.Guide.View()
	ok(v.extra, "the extra quest is shown")
	eq(v.title, alt.name)
	stub.accept(alt.quest)
	stub.turnin(alt.quest)
	ok(not ns.Guide.View().extra, "back to the route")
end)

test("Back and Next look at other steps without changing the live one", function()
	local stub, ns = fixture()
	stub.accept(363) stub.turnin(363) stub.accept(364, {})
	local E = ns.Engine
	eq(E.LiveStep(), 3)
	E.Next()
	eq(E.CurrentStep(), 4)
	eq(E.LiveStep(), 3)
	ok(ns.Guide.View().pinned)
	E.Back() E.Back()
	eq(E.CurrentStep(), 2)
	E.Next()
	eq(E.CurrentStep(), 3, "back on the live step")
end)

test("a finished route hands over to its next route", function()
	local stub, ns = login()
	local E = ns.Engine
	Pathwise.RegisterRoute({ id = "test/a", title = "A", levels = { 1, 2 }, faction = "Horde", next = "test/b", steps = { { { "level", 2 } } } })
	Pathwise.RegisterRoute({ id = "test/b", title = "B", levels = { 2, 3 }, faction = "Horde", steps = { { { "level", 3 } } } })
	E.SetRoute("test/a")
	eq(E.Route().id, "test/b", "level 2 already: on to B")
	ok(lastPrint(stub):find("next route: B"), lastPrint(stub))
end)

---------------------------------------------------------------------------
-- Professions beside the route
---------------------------------------------------------------------------

test("a profession route followed beside the leveling route: card, Go, skill and recipes", function()
	local stub, ns = fixture()
	local E = ns.Engine
	ns.Set("professions.detour", "craft") -- the trainer is across the zone: show it anyway
	ok(E.SetSide("forever/professions/tailoring"), "side guide")
	local card = ns.Guide.View().detour
	ok(card, "the detour card")
	ok(card.label:find("^Optional · Tailoring"), card.label)
	ok(card.text:find("Apprentice") or card.text:find("Tailoring"), card.text)
	local before = ns.Nav.Target().title
	ns.Fire("DETOUR_GO")
	ok(ns.Nav.Target().title ~= before, "Go: the arrow leads to the profession step (" .. tostring(ns.Nav.Target().title) .. ")")
	ok(ns.Guide.View().detour.aimed, "the card says so")
	ns.Fire("DETOUR_GO")
	eq(ns.Nav.Target().title, before, "Stop: back to the route")
	-- Learning Tailoring and buying the thread the first step asks for moves it on.
	local step = E.SideStep()
	stub.skills[197] = { 1, 75 }
	stub.fire("SKILL_LINES_CHANGED")
	eq(E.SideStep(), step, "trained, but the thread is still to buy")
	stub.items[2320] = 96
	stub.fire("BAG_UPDATE_DELAYED")
	ok(E.SideStep() > step, "apprentice trained and thread bought: next profession step")
	ns.Fire("DETOUR_SKIP")
	eq(ns.Guide.View().detour, nil, "skipped: the card hides until the next profession step")
end)

test("detour modes: the profession card shows when the step is on the way, by mode", function()
	local stub, ns = fixture()
	local E = ns.Engine
	E.SetSide("forever/professions/tailoring")
	-- Deathknell to Brill's tailoring trainer is far: Balanced hides the card.
	eq(ns.Guide.View().detour, nil, "balanced: too far")
	stub.moveTo(1420, 52.0, 55.0) -- next to Bowen Brisboise
	E.Update()
	local card = ns.Guide.View().detour
	ok(card, "balanced: near, shown")
	ok(card.sub:find("yd"), "with the distance: " .. card.sub)
	ns.Set("professions.detour", "speed")
	E.Update()
	ok(ns.Guide.View().detour, "speed: right on the way, shown")
	stub.moveTo(1420, 45.0, 55.0)
	E.Update()
	eq(ns.Guide.View().detour, nil, "speed: a few hundred yards off, hidden")
	ns.Set("professions.detour", "craft")
	E.Update()
	ok(ns.Guide.View().detour, "crafting: always")
end)

test("report this step: a copyable report with the route, step, log and position", function()
	local stub, ns = fixture()
	stub.accept(363)
	ns.Fire("REPORT_STEP")
	local text = ns.Engine.ReportText()
	ok(text:find("Route: Deathknell %(test%) %(test/deathknell%)"), text)
	ok(text:find("turnin 363 Rude Awakening"), "the step's goals")
	ok(text:find("%[log: on quest"), "quest log state")
	ok(text:find("Position: map 1420"), "position")
	ok(text:find("Character: Scourge MAGE, level 2, Horde"), "character")
	ok(_G.PathwisePanel.shown, "the report panel")
	ok(contains(stub.texts(), "Report this step") or contains(stub.texts(), "REPORT THIS STEP"))
end)

test("about panel: name, tagline, creators, signature, credits", function()
	local stub, ns = login()
	SlashCmdList.PATHWISE("about")
	local texts = stub.texts()
	ok(contains(texts, "Every quest. Every craft. Every level."))
	ok(contains(texts, "Created by leight_nn & florp"))
	ok(contains(texts, "_nn"))
	ok(contains(texts, "Polestar"), "credits Polestar")
	ok(contains(texts, "QuestieDB"), "credits QuestieDB")
end)

test("more guides: reputation, mounts and pets are listed, folded until opened", function()
	local stub, ns = login()
	local cats = {}
	for _, r in ipairs(ns.Engine.Routes()) do cats[r.category] = (cats[r.category] or 0) + 1 end
	ok((cats.Reputation or 0) > 10, "reputation routes")
	ok((cats.Collectibles or 0) > 40, "mount and pet routes")
	ns.Fire("SHOW_ROUTES")
	ok(stub.clickLabelText("Show mount guides"), "open mounts")
	ok(contains(stub.texts(), "Hide mount guides"))
end)

---------------------------------------------------------------------------
-- Map and minimap pins
---------------------------------------------------------------------------

-- The pin frames shown under a parent, with their points.
local function shownPins(stub, parent)
	local out = {}
	for _, f in ipairs(stub.frames) do
		if f.parent == parent and f.shown and rawget(f, "pin") then out[#out + 1] = f end
	end
	return out
end

test("pins: the step's places, the arrow's first, and the spots of open objectives", function()
	local stub, ns = fixture()
	stub.accept(363) stub.turnin(363)
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false },
		{ text = "Wretched Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	stub.accept(376, {})
	local pins = ns.Engine.Pins()
	eq(pins[1].kind, "lead")
	local spots = 0
	for _, p in ipairs(pins) do
		eq(p.map, 1420)
		if p.kind == "spot" then spots = spots + 1 end
	end
	ok(spots >= 6, "zombie spots: " .. spots)
end)

test("world map pins: drawn on the map shown, the same size at any zoom, read-only", function()
	local stub, ns = fixture()
	stub.mapShown = 1420
	stub.advance(0.05)
	local layer = ns.Pins.world.layer
	ok(layer, "a layer of Pathwise's under the canvas")
	eq(layer.parent, stub.canvas)
	local pins = shownPins(stub, layer)
	ok(#pins >= 1, "a pin for Undertaker Mordo")
	local lead
	for _, f in ipairs(pins) do if f.pin.kind == "lead" then lead = f end end
	eq(lead.pin.title, "Undertaker Mordo")
	local pt = lead.points[1]
	eq(pt[2], layer)
	near(pt[4], 1000 * 30.22 / 100, 0.01, "x on the canvas")
	near(pt[5], -666 * 71.65 / 100, 0.01, "y on the canvas")
	stub.mapScale = 2
	stub.advance(0.05)
	near(lead.scale, 0.5, 1e-9, "zoomed in: the pin keeps its size on screen")
	near(lead.points[1][4], 1000 * 30.22 / 100 * 2, 0.01, "and its place")
	stub.mapShown = 1411 -- Durotar: nothing of this step there
	stub.advance(0.05)
	eq(#shownPins(stub, layer), 0)
	ns.Set("pins.map", false)
	stub.mapShown = 1420
	stub.advance(0.05)
	eq(#shownPins(stub, layer), 0, "switched off in Settings")
end)

test("minimap: projection by zoom, rotation and the rim", function()
	local _, ns = fresh()
	local P = ns.Pins
	-- 100 yd north, outdoor zoom 0 (466.67 yd across), 66 px from the centre to the rim.
	local x, y, out = P.Project(100, 0, nil, 466.67 / 2, 66, false, false)
	near(x, 0, 1e-9)
	near(y, 100 * 66 / 233.335, 1e-3)
	eq(out, false)
	-- 100 yd west on a non-rotating minimap: to the left.
	x = P.Project(0, 100, nil, 233.335, 66, false, false)
	ok(x < 0, "west is left")
	-- Facing west on a rotating minimap: north turns to the right.
	x, y = P.Project(100, 0, math.pi / 2, 233.335, 66, true, false)
	ok(x > 0 and math.abs(y) < 1e-6, ("north is to the right: %.2f, %.2f"):format(x, y))
	-- Beyond the rim: held to it.
	x, y, out = P.Project(1000, 0, nil, 233.335, 66, false, false)
	eq(out, true)
	near(y, 66, 1e-9)
end)

test("minimap pins: the step's places near the player; the arrow's target held to the rim", function()
	local stub, ns = fixture()
	local pins = shownPins(stub, Minimap)
	ok(#pins >= 1, "Undertaker Mordo on the minimap")
	stub.moveTo(1420, 60, 50) -- far away in Brill
	stub.advance(0.2)
	local lead
	for _, f in ipairs(shownPins(stub, Minimap)) do if f.pin.kind == "lead" then lead = f end end
	ok(lead, "the arrow's target stays, on the rim")
	local pt = lead.points[1]
	near(math.sqrt(pt[4] ^ 2 + pt[5] ^ 2), 66, 0.01, "on the rim")
	ns.Set("pins.minimap", false)
	eq(#shownPins(stub, Minimap), 0, "switched off")
end)

---------------------------------------------------------------------------
-- Dungeons
---------------------------------------------------------------------------

test("dungeons: by level, from the data, Forever's own included", function()
	local _, ns = fresh()
	local Dg = ns.Dungeons
	local names = {}
	for _, d in ipairs(Dg.ForLevel(18)) do names[d.name] = d end
	ok(names["The Deadmines"] and names["Wailing Caverns"], "Deadmines and Wailing Caverns at 18")
	ok(not names["Molten Core"], "no raid at 18")
	local all = {}
	for _, d in ipairs(Dg.All()) do all[d.name] = d end
	ok(all["Ruins of Lordaeron"] and all["The Hall of Thanes"], "Forever's instances")
	ok(all["Molten Core"].raid, "Molten Core is a raid")
	ok(not all["Zul'Farrak"].raid, "Zul'Farrak is not")
	ok(not all["Alterac Valley"] and not all["Warsong Gulch"] and not all["Deeprun Tram"], "no battlegrounds, no tram")
	eq(#all["Dire Maul"].quests > 10, true, "Dire Maul's wings as one, with its quests")
end)

test("dungeon quests: this side's, with what stands for each", function()
	local stub, ns = login(function(s) s.player.level = 18 end)
	local Dg = ns.Dungeons
	local wc = Dg.Quests(718)
	ok(#wc > 0, "Wailing Caverns quests for a Horde character")
	local seen = {}
	for _, q in ipairs(wc) do seen[q.status] = true end
	ok(seen.now or seen.pre or seen.level, "statuses")
	-- Taking one shows it in the log.
	local first = wc[1].quest
	stub.accept(first)
	local again
	for _, q in ipairs(Dg.Quests(718)) do if q.quest == first then again = q end end
	ok(again and (again.status == "log" or again.status == "ready"), again and again.status)
	-- The Deadmines' quests are given in Westfall and Stormwind: Alliance only.
	local hordeCount = #Dg.Quests(1581)
	local _, ns2 = login(function(s) s.player.level = 18 s.player.raceID, s.player.race, s.player.faction = 1, "Human", "Alliance" end)
	ok(#ns2.Dungeons.Quests(1581) > hordeCount, "more Deadmines quests for the Alliance")
end)

test("dungeon entrance: the nearest, and the arrow to it", function()
	local stub, ns = login()
	stub.moveTo(1427, 30, 80) -- Searing Gorge
	local e = ns.Dungeons.Entrance(1584)
	eq(e.map, 1427, "Blackrock Depths from the Searing Gorge side")
	ok(ns.Dungeons.GuideTo(1584))
	eq(ns.Nav.Target().title, "Blackrock Depths")
end)

test("dungeons panel and page; entrance pins on the world map", function()
	local stub, ns = login(function(s) s.player.level = 19 end)
	SlashCmdList.PATHWISE("dungeons")
	local texts = stub.texts()
	ok(contains(texts, "Wailing Caverns   18-21"), table.concat(texts, " | "))
	ok(stub.clickLabelText("Wailing Caverns"), "open its page")
	texts = stub.texts()
	ok(contains(texts, "Go to the entrance"))
	ok(contains(texts, "QUESTS"))
	ok(stub.clickLabelText("Go to the entrance"))
	eq(ns.Nav.Target().title, "Wailing Caverns")
	stub.mapShown = 1413 -- The Barrens
	stub.advance(0.05)
	local found
	for _, f in ipairs(stub.frames) do
		if f.parent == ns.Pins.world.layer and f.shown and rawget(f, "pin") and f.pin.kind == "dungeon" then found = f.pin end
	end
	ok(found and found.title == "Wailing Caverns", "an entrance pin on the Barrens map")
end)

---------------------------------------------------------------------------
-- Everything without commands: minimap button, key bindings, tools
---------------------------------------------------------------------------

test("minimap button: click shows and hides the guide, right-click opens Settings", function()
	local stub, ns = login()
	local b = _G.PathwiseMinimapButton
	ok(b and b.shown, "the button is on the minimap")
	eq(b.parent, Minimap)
	b.scripts.OnClick(b, "LeftButton")
	eq(ns.Get("guide.shown"), false, "hidden")
	b.scripts.OnClick(b, "LeftButton")
	eq(ns.Get("guide.shown"), true, "shown again")
	b.scripts.OnClick(b, "RightButton")
	ok(contains(stub.texts(), "SETTINGS"), "settings open")
	ns.Set("minimap.shown", false)
	eq(b.shown, false, "hidden from Settings")
end)

test("minimap button: placed on the edge, dragged around it, remembered", function()
	local stub, ns = login()
	local MB = ns.MinimapButton
	local x, y = MB.Offset(0, 140)
	near(x, 76, 1e-9) near(y, 0, 1e-9)
	x, y = MB.Offset(90, 140)
	near(x, 0, 1e-9) near(y, 76, 1e-9)
	eq(MB.AngleFrom(0, 0, 0, -10), 270)
	local b = _G.PathwiseMinimapButton
	stub.cursor = { 1000, 700 } -- straight above the minimap's centre
	b.scripts.OnDragStart(b)
	stub.advance(0.05)
	b.scripts.OnDragStop(b)
	eq(ns.Get("minimap.angle"), 90)
	eq(PathwiseSettings.minimap.angle, 90, "saved")
end)

test("key bindings: listed under Pathwise, each one works", function()
	local stub, ns = login()
	eq(BINDING_HEADER_PATHWISE, "Pathwise")
	local xml = assert(io.open("Pathwise/Bindings.xml")):read("*a")
	for _, name in ipairs({ "TOGGLE", "COMPACT", "PROFESSIONS", "DUNGEONS", "SETTINGS", "REPORT" }) do
		ok(xml:find('name="PATHWISE_' .. name .. '"', 1, true), name .. " in Bindings.xml")
		ok(_G["BINDING_NAME_PATHWISE_" .. name], name .. " has a name in the menu")
	end
	Pathwise.Binding("toggle")
	eq(ns.Get("guide.shown"), false)
	Pathwise.Binding("dungeons")
	ok(_G.PathwisePanel.shown, "dungeons open")
end)

test("waypoint & tools: a waypoint by coordinates, cleared, and the debug text", function()
	local stub, ns = login()
	ns.Panels.Open("tools")
	ok(contains(stub.texts(), "You are at 30.2, 71.6  ·  Tirisfal Glades"), table.concat(stub.texts(), " | "))
	local row
	for _, f in ipairs(stub.frames) do if rawget(f, "set") and rawget(f, "x") and f.shown then row = f end end
	ok(row, "the X and Y row")
	row.x:SetText("45.2")
	row.y:SetText("61,8") -- a comma works too
	row.set.scripts.OnClick(row.set)
	local t = ns.Nav.Target()
	eq(t.map, 1420)
	near(t.x, 45.2, 1e-9)
	near(t.y, 61.8, 1e-9)
	row.x:SetText("abc")
	row.set.scripts.OnClick(row.set)
	ok(lastPrint(stub):find("two numbers"), "explains")
	near(ns.Nav.Target().x, 45.2, 1e-9, "unchanged")
	row.clear.scripts.OnClick(row.clear)
	eq(ns.Nav.Target(), nil)
	ok(ns.Nav.DebugText():find("player map 1420"), "debug text")
end)

test("closing the guide says how to bring it back, once", function()
	local stub, ns = login()
	local n = #stub.printed
	for _, f in ipairs(stub.frames) do
		if rawget(f, "pwIcon") and f.parent and f.parent.parent == _G.PathwiseGuide and rawget(f.pwIcon, "texture") and f.pwIcon.texture:find("glyph%-close$") then
			f.scripts.OnClick(f)
			break
		end
	end
	eq(ns.Get("guide.shown"), false)
	ok(lastPrint(stub):find("minimap button"), lastPrint(stub))
	eq(#stub.printed, n + 1, "one hint")
end)

---------------------------------------------------------------------------
-- Professions dashboard
---------------------------------------------------------------------------

-- An Undead Mage with Tailoring 1/75 (trained, thread bought) and Enchanting.
local function tailor(setup)
	return login(function(s)
		s.skills[197] = { 1, 75 }
		s.skills[333] = { 30, 75 }
		s.items[2320] = 96 -- Coarse Thread
		s.items[2589] = 46 -- Linen Cloth
		if setup then setup(s) end
	end)
end

test("professions: the character's professions and where their guides stand", function()
	local stub, ns = tailor()
	local P = ns.Professions
	local known = P.Known()
	eq(#known, 2)
	eq(known[2].prof.name, "Tailoring")
	eq(known[2].rank, 1)
	local st = P.Stage(P.BY_KEY.tailoring)
	ok(st and st.rankMax == 75, "the Apprentice rank of the guide")
	eq(st.route.steps[st.step].title, "Linen Cloth", "trained and thread bought: on to the cloth")
end)

test("professions: the shopping list for this rank, from the guide, with what is owned", function()
	local stub, ns = tailor()
	local shop = ns.Professions.Shopping(ns.Professions.BY_KEY.tailoring)
	local linen
	for _, r in ipairs(shop) do if r.item == 2589 then linen = r end end
	ok(linen, "Linen Cloth on the list")
	eq(linen.need, 192)
	eq(linen.have, 46)
	eq(linen.missing, 146)
	eq(linen.src, "farm")
	ok(shop[1].missing > 0, "missing materials first")
end)

test("professions: the best craft now and how many the bags make", function()
	local stub, ns = tailor(function(s) s.items[2589] = 192 end)
	local craft = ns.Professions.NextCraft(ns.Professions.BY_KEY.tailoring)
	eq(craft.name, "Bolt of Linen Cloth")
	eq(craft.craftable, 96, "192 linen, 2 a bolt")
end)

test("professions: the profession window's recipes are read and kept (difficulty colour)", function()
	local stub, ns = tailor(function(s) s.items[2589] = 192 end)
	stub.tradeSkill = { professionID = 197, recipes = { [2963] = { name = "Bolt of Linen Cloth", learned = true, relativeDifficulty = 0 } } }
	stub.fire("TRADE_SKILL_SHOW")
	local P = ns.Professions
	ok(P.Recipes(197) and P.Recipes(197)[2963], "kept")
	eq(P.NextCraft(P.BY_KEY.tailoring).difficulty, "orange")
	ok(PathwiseCharSettings.professions.recipes[197][2963].learned, "saved per character")
end)

test("professions: disenchantable gear in the bags, with the skill it asks (marked unverified)", function()
	local stub, ns = tailor(function(s)
		s.itemInfo[9001] = { "Green Gloves", 2, 22, 120, 4 }
		s.itemInfo[9002] = { "Blue Sword", 3, 48, 900, 2 }
		s.itemInfo[9003] = { "Grey Cup", 0, 10, 5, 4 }
		s.bags[0] = { { itemID = 9001, quality = 2 }, { itemID = 9002, quality = 3 }, { itemID = 9003, quality = 0 } }
	end)
	local list = ns.Professions.Disenchantable(30)
	eq(#list, 2, "the grey cup is not")
	eq(list[1].name, "Blue Sword", "highest level first")
	eq(list[1].skill, 150)
	eq(list[1].canNow, false)
	eq(list[2].skill, 25)
	eq(list[2].canNow, true)
	eq(ns.Professions.DE_SKILL_VERIFIED, false)
end)

test("professions: Tailoring + Enchanting names the green Tailoring crafts to disenchant", function()
	local stub, ns = tailor(function(s)
		s.items[2589] = 192
		s.itemInfo[10045] = { "Simple Linen Pants", 1, 7, 10, 4 }
		s.itemInfo[2996] = { "Bolt of Linen Cloth", 1, 5, 2, 7 }
	end)
	local P = ns.Professions
	eq(#P.TailorEnchant(), 0, "white items: nothing to disenchant")
	stub.itemInfo[10045][2] = 2
	local names = P.TailorEnchant()
	eq(names[1], "Simple Linen Pants")
end)

test("professions dashboard: skill, guide step, best craft, materials, disenchanting", function()
	local stub, ns = tailor(function(s)
		s.items[2589] = 192
		s.itemInfo[9001] = { "Green Gloves", 2, 22, 120, 4 }
		s.bags[0] = { { itemID = 9001, quality = 2 } }
	end)
	SlashCmdList.PATHWISE("prof")
	local texts = stub.texts()
	ok(contains(texts, "Tailoring   1 / 75"), table.concat(texts, " | "))
	ok(contains(texts, "Enchanting   30 / 75"))
	ok(contains(texts, "Best now: Bolt of Linen Cloth  ·  96 from your bags"))
	ok(contains(texts, "Open your Tailoring window once"), "asks for the recipe scan")
	ok(contains(texts, "DISENCHANTING"))
	ok(contains(texts, "Green Gloves  ·  skill ≈25"))
	ok(stub.clickLabelText("Follow beside your route"), "follow from the dashboard")
	ok(ns.Engine.Side(), "a side guide now")
end)

test("professions dashboard: no professions yet", function()
	local stub, ns = login()
	ns.Fire("SHOW_PROFESSIONS")
	ok(contains(stub.texts(), "No professions yet"))
end)

---------------------------------------------------------------------------
-- Panels
---------------------------------------------------------------------------

test("zones for the player's level list Tirisfal with its route", function()
	local stub, ns = login()
	stub.player.level = 5
	local tirisfal
	for _, z in ipairs(ns.Engine.Zones()) do if z.map == 1420 then tirisfal = z end end
	ok(tirisfal, "Tirisfal listed at level 5")
	eq(tirisfal.route.id, "forever/horde/undead/01-tirisfal-glades")
end)

test("routes panel: leveling near the level, class quests for a mage, professions as side guides", function()
	local stub, ns = login()
	ns.Fire("SHOW_ROUTES")
	local texts = stub.texts()
	ok(contains(texts, "Tirisfal Glades   1-13"), "the leveling route")
	ok(not contains(texts, "Felwood"), "level 60 routes hidden at level 2")
	ok(contains(texts, "CLASS QUESTS"), "class quests")
	ok(contains(texts, "Polymorph: Pig") or contains(texts, "Pig"), "a mage class quest")
	ok(not contains(texts, "Whirlwind"), "no warrior class quest")
	ok(contains(texts, "You have no professions yet"), "no professions")
	ok(stub.clickLabelText("Show every profession"), "show all professions")
	ok(contains(stub.texts(), "Tailoring"), "Tailoring listed")
	ok(stub.clickLabelText("Tailoring"), "follow Tailoring")
	eq(ns.Engine.Side().id, "forever/professions/tailoring")
end)

test("settings panel: sliders, compact and arrow toggles", function()
	local stub, ns = login()
	ns.Fire("SHOW_SETTINGS")
	stub.slider("ui.opacity"):SetValue(0.7)
	near(ns.Get("ui.opacity"), 0.7, 1e-9, "opacity slider")
	stub.slider("arrow.scale"):SetValue(1.5)
	near(ns.Get("arrow.scale"), 1.5, 1e-9, "arrow size slider")
	ok(stub.clickLabel("Turn on"), "compact toggle")
	eq(ns.Get("guide.compact"), true)
	ok(stub.clickLabel("Hide"), "arrow toggle")
	eq(ns.Get("arrow.shown"), false)
end)

test("window size slider: the guide shrinks as it moves, saved, steps of 5%", function()
	local stub, ns = login()
	ns.Fire("SHOW_SETTINGS")
	local s = stub.slider("ui.scale")
	s:SetValue(0.73)
	near(ns.Get("ui.scale"), 0.75, 1e-9, "rounded to the 5% step")
	near(_G.PathwiseGuide.scale, 0.75, 1e-9, "the guide window scales at once")
	s:SetValue(0.1)
	near(ns.Get("ui.scale"), 0.5, 1e-9, "never below 50%")
	s:SetValue(1)
	eq(PathwiseSettings.ui.scale, nil, "back to 100% is not stored")
end)

test("typing a size into the box beside the slider", function()
	local stub, ns = login()
	ns.Fire("SHOW_SETTINGS")
	local box = stub.type("ui.scale", "72")
	near(ns.Get("ui.scale"), 0.72, 1e-9)
	near(stub.slider("ui.scale").value, 0.72, 1e-9, "the slider moves to it")
	stub.type("ui.scale", "300%")
	near(ns.Get("ui.scale"), 1.5, 1e-9, "held to 150%")
	eq(box.text, "150")
	stub.type("ui.scale", "abc")
	eq(box.text, "150", "not a number: unchanged")
	box:SetText("90")
	box.scripts.OnEscapePressed(box)
	eq(box.text, "150", "Escape puts the value back")
end)

test("/pw scale sets the window size; the panel opens at that size", function()
	local stub, ns = login()
	SlashCmdList.PATHWISE("scale 80")
	near(_G.PathwiseGuide.scale, 0.8, 1e-9)
	ns.Fire("SHOW_SETTINGS")
	near(_G.PathwisePanel.scale, 0.8, 1e-9)
end)

test("skip panel lists the step's quest and nearby alternatives", function()
	local stub, ns = fixture()
	stub.accept(363) stub.turnin(363) stub.accept(364, {})
	ns.Fire("GUIDE_SKIP")
	local texts = stub.texts()
	ok(contains(texts, "The Damned"), "the quest")
	ok(contains(texts, "Skip just this quest"))
	ok(contains(texts, "INSTEAD, NEARBY"))
end)

test("events: every event Pathwise listens for exists on Forever; an unknown one is skipped, not an error", function()
	local stub, ns = fresh()
	ok(next(stub.knownEvents), "the Forever event list is loaded")
	eq(ns.RegisterEvent("LEARNED_SPELL_IN_TAB", function() end), false, "a Classic-only name is skipped")
	eq(ns.RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", function() end), true)
	ok(ns.UnknownEvents()["LEARNED_SPELL_IN_TAB"])
	for name in pairs(ns.UnknownEvents()) do
		ok(name == "LEARNED_SPELL_IN_TAB", "Pathwise itself asked for an event Forever lacks: " .. name)
	end
end)

test("side panel: its scrolling area hangs off the panel, and count sliders show plain numbers", function()
	local stub, ns = fresh()
	stub.login()
	ns.Fire("SHOW_SETTINGS")
	local panel = _G.PathwisePanel
	ok(panel, "the panel")
	local scroll
	for _, f in ipairs(stub.frames) do if f.kind == "ScrollFrame" and f.parent == panel then scroll = f end end
	ok(scroll, "its scroll frame")
	for _, pt in ipairs(scroll.points) do
		ok(pt[2] == panel, ("anchored to the panel, not %s"):format(tostring(pt[2])))
	end
	-- A count slider: no % sign, the setting's own number in the box.
	ns.Suite.Panel("countTest", function() return { { "slider", "Columns", "bags.columns", 8, 20, 1, nil, "count" } } end)
	ns.Set("bags.columns", 12)
	ns.Suite.Open("countTest")
	local row
	for _, f in ipairs(stub.frames) do if type(rawget(f, "sliders")) == "table" and f.sliders["bags.columns"] and f.shown then row = f end end
	ok(row, "the slider row")
	eq(row.box.text, "12")
	eq(row.pct.text, "")
	stub.type("bags.columns", "15")
	eq(ns.Get("bags.columns"), 15)
end)

test("sliders: dragging follows the pointer smoothly, step by step, never jumping to an end", function()
	local stub, ns = fresh()
	stub.login()
	local T = ns.Theme
	local seen = {}
	local s = T.Slider(UIParent, 200, 0.5, 1.5, 0.05, function(v) seen[#seen + 1] = v end)
	-- The bar: 200 px wide from x = 100, at scale 1.
	s.GetLeft = function() return 100 end
	s.GetWidth = function() return 200 end
	s.GetEffectiveScale = function() return 1 end
	s:SetQuietly(1)
	stub.cursor[1] = 150 -- a quarter along
	s.scripts.OnMouseDown(s, "LeftButton")
	eq(s:GetValue(), 0.75)
	ok(s.scripts.OnUpdate, "following the pointer while held")
	for x = 150, 250, 5 do stub.cursor[1] = x s.scripts.OnUpdate(s) end
	eq(s:GetValue(), 1.25, "three quarters along")
	for i = 2, #seen do
		ok(math.abs(seen[i] - seen[i - 1]) <= 0.05 + 1e-9, ("one step at a time: %s then %s"):format(seen[i - 1], seen[i]))
		ok(seen[i] ~= seen[i - 1], "only real changes are reported")
	end
	stub.cursor[1] = 9999
	s.scripts.OnUpdate(s)
	eq(s:GetValue(), 1.5, "past the end: the end, no further")
	s.scripts.OnMouseUp(s)
	ok(not s.scripts.OnUpdate, "let go: stops following")
	-- A count slider (the bag window's columns): whole numbers.
	local c = T.Slider(UIParent, 120, 8, 20, 1, function() end)
	c.GetLeft, c.GetWidth, c.GetEffectiveScale = function() return 0 end, function() return 120 end, function() return 1 end
	eq(c:ValueAt(60), 14)
	eq(c:ValueAt(-50), 8)
end)
