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

-- Pathwise's own route fixes (tools/port/fixes.lua), as written into the routes.
test("route fixes: Ashenvale's hunt trophies wait for The Ashenvale Hunt, which Splintertree offers", function()
	local _, ns = fresh()
	local route = ns.Engine.routes["forever/horde/07-ashenvale"]
	local held, splinter = 0, nil
	for _, step in ipairs(route.steps) do
		for g, goal in ipairs(step) do
			if goal[1] == "have" and (goal[2] == 16303 or goal[2] == 16304 or goal[2] == 16305) then
				local w = step.when and step.when[1]
				ok(w and w.k == "turnedin" and w.q == 6383, "the hunt for item " .. goal[2] .. " waits for 6383")
				held = held + 1
			end
			if goal[1] == "accept" and goal[2] == 6383 and not splinter then
				splinter = step
				eq(step[g + 1][1], "turnin", "taken and handed straight back")
				eq(step[g + 2][2], 23, "before the first trophy hand-in")
			end
		end
	end
	eq(held, 3, "all three hunts")
	ok(splinter, "Senani offers The Ashenvale Hunt on this route")
end)

-- The bug class behind the Ashenvale hunt: a route that offers a quest
-- whose prerequisite nothing before it hands in.
test("routes: every required accept has its prerequisite handed in before it", function()
	local _, ns = fresh()
	local D, routes = ns.Quests.Data, ns.Engine.routes
	local prev = {}
	for id, r in pairs(routes) do
		if r.category == "Leveling" and r.next then prev[r.next] = prev[r.next] or {} table.insert(prev[r.next], id) end
	end
	local function earlier(id, seen, out)
		for _, p in ipairs(prev[id] or {}) do
			if not seen[p] then
				seen[p] = true
				for _, step in ipairs(routes[p].steps) do
					for _, g in ipairs(step) do if g[1] == "turnin" then out[g[2]] = true end end
				end
				earlier(p, seen, out)
			end
		end
		return out
	end
	local bad = {}
	for id, r in pairs(routes) do
		if r.category == "Leveling" then
			local done = earlier(id, {}, {})
			for s, step in ipairs(r.steps) do
				local held = {}
				for _, w in ipairs(step.when or {}) do
					for _, q in ipairs(type(w.q) == "table" and w.q or { w.q }) do held[q] = true end
				end
				for _, g in ipairs(step) do
					local q = g[1] == "accept" and not g.optional and not step.only and not step.when and D.quests[g[2]]
					if q then
						local pre = q[13] -- any one of them
						local any = not pre or #pre == 0
						for _, p in ipairs(pre or {}) do if done[p] or held[p] then any = true end end
						for _, p in ipairs(q[14] or {}) do if not done[p] then any = false end end -- all of them
						if not any then bad[#bad + 1] = ("%s step %d: %s"):format(id, s, q[1]) end
					end
					if g[1] == "turnin" then done[g[2]] = true end
				end
			end
		end
	end
	table.sort(bad)
	eq(#bad, 0, table.concat(bad, "; "))
end)

-- tools/routes/efficiency.lua: no stop that only does what an earlier
-- visit to the same person could have done.
test("routes: no comeback stops (tools/routes/efficiency.lua)", function()
	EFFICIENCY_LIB = true
	local Eff = dofile("tools/routes/efficiency.lua")
	EFFICIENCY_LIB = nil
	local bad = {}
	for _, r in ipairs(Eff.routes) do
		for _, c in ipairs(Eff.route(r).comebacks) do
			bad[#bad + 1] = ("%s step %d (%s, %.0f yd)"):format(r.id, c.step, c.who, c.saved)
		end
	end
	eq(#bad, 0, table.concat(bad, "; "))
	-- And it finds one: Torwa's quest taken on a second visit, as before the fix.
	local route = { id = "test/torwa", levels = { 48, 52 }, steps = {
		{ { "turnin", 4291, at = { 1449, 71.64, 75.96 }, who = "Torwa Pathfinder" } },
		{ { "goto", 1449, 77.2, 50, "Eastern Crystal Pylon" } },
		{ { "accept", 4289, at = { 1449, 71.64, 75.96 }, who = "Torwa Pathfinder" } },
		{ { "goto", 1449, 48.69, 85.32, "The hive" } },
	} }
	local f = Eff.route(route)
	eq(#f.comebacks, 1, "the second visit to Torwa")
	eq(f.comebacks[1].to, 1, "done on the first")
	ok(f.walked > 1000, "yards walked: " .. f.walked)
end)

test("route fixes: a fix that no longer finds its goal stops the build", function()
	package.path = "tools/port/?.lua;" .. package.path
	local Fix = require("fixes")
	local saved = Fix.FIXES["test/route"]
	Fix.FIXES["test/route"] = { { why = "test", drop = { "accept", 1 } } }
	local okay, err = pcall(Fix.apply, { id = "test/route", steps = { { { "accept", 2 } } } })
	Fix.FIXES["test/route"] = saved
	ok(not okay and tostring(err):find("nothing to drop"), "stale fix: " .. tostring(err))
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

-- A trainer the guide names (Annora for Artisan Enchanting, riding
-- trainers) keeps its name; only class training says "class trainer".
test("routes: named trainers keep their names, not the class trainer text", function()
	local _, ns = fresh()
	local CLASS_TEXT = "Train new spells at your class trainer"
	for _, r in ipairs(ns.Engine.Routes()) do
		local riding = r.id:find("^forever/collectibles/mounts/alliance/") or r.id:find("^forever/collectibles/mounts/horde/")
		if r.category == "Professions" or riding then
			for i, step in ipairs(r.steps) do
				for _, g in ipairs(step) do
					ok(not (g[1] == "note" and g[2] == CLASS_TEXT), ("%s step %d: %s"):format(r.id, i, CLASS_TEXT))
				end
			end
		end
	end
	local found
	for _, step in ipairs(ns.Engine.routes["forever/professions/enchanting"].steps) do
		if step.title == "Artisan Enchanting" then
			for _, g in ipairs(step) do
				if g[1] == "note" and g[2]:find("Annora", 1, true) and g[2]:find("Uldaman", 1, true) then found = true end
			end
		end
	end
	ok(found, "Artisan Enchanting names Annora in Uldaman")
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

test("waypoints you are past do not hold the route: the quest log is what counts", function()
	local stub, ns = login()
	ok(Pathwise.RegisterRoute({
		id = "test/waypoints", title = "Waypoints (test)", category = "Leveling", map = 1420,
		levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
		steps = {
			{ { "accept", 363 } },
			{ title = "Walk to Sarvis", { "goto", 1420, 30.8, 66.2, "The crypt door" } },
			{ { "accept", 364 } },
			{ title = "Quests and waypoints", { "complete", 364 }, { "goto", 1420, 26, 60, "The field" }, { "goto", 1420, 25, 59, "The far end" } },
			{ { "turnin", 364 } },
		},
	}), "registers")
	ns.Engine.SetRoute("test/waypoints")
	eq(ns.Engine.LiveStep(), 1)
	stub.accept(363)
	eq(ns.Engine.LiveStep(), 2, "nothing further done yet: the walk still shows")
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	eq(ns.Engine.LiveStep(), 4, "a quest further on is taken: the walk is behind you")
	stub.progress(364, 1, 8)
	ns.Engine.Update()
	eq(ns.Engine.LiveStep(), 5, "the quest is done: its waypoints do not hold the step")
end)

test("sync: the guide's button and /pw sync bring it in line with the quest log", function()
	local stub, ns = fixture()
	-- The button in the title bar, by its glyph.
	local button
	for _, f in ipairs(stub.frames) do
		local icon = rawget(f, "pwIcon")
		local tex = icon and rawget(icon, "texture")
		if type(tex) == "string" and tex:find("glyph%-sync") then button = f end
	end
	ok(button, "a sync button in the guide")
	-- Paged ahead with Next: sync lets go of it.
	ns.Engine.Next()
	ns.Engine.Next()
	ok(ns.Engine.CurrentStep() ~= ns.Engine.LiveStep(), "paged ahead")
	button.scripts.OnClick(button)
	eq(ns.Engine.CurrentStep(), ns.Engine.LiveStep(), "back on the live step")
	ok(lastPrint(stub):find("synced with your quest log: Deathknell %(test%), step 1 of"), lastPrint(stub))
	eq(ns.Engine.Route().id, FIXTURE.id, "a route still open is kept")
	-- A finished route: sync moves on to the one that suits the character.
	-- (The fixture's own last steps ask for items and a level: a one-step
	-- route stands in for it, its quest handed in.)
	stub.done[363] = true
	local route = ns.Engine.Route()
	local saved = route.steps
	route.steps = { { { "accept", 363 } } }
	SlashCmdList.PATHWISE("sync")
	ok(ns.Engine.Route().id ~= FIXTURE.id, "finished: on to " .. tostring(ns.Engine.Route() and ns.Engine.Route().id))
	ok(lastPrint(stub):find("now on"), lastPrint(stub))
	route.steps = saved
end)

test("an item to fetch is behind you once a quest further on is done (Samuel's Remains)", function()
	local stub, ns = login()
	ok(Pathwise.RegisterRoute({
		id = "test/item", title = "Item (test)", category = "Leveling", map = 1420,
		levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
		steps = {
			{ title = "Fetch the remains", { "have", 16333, 1, name = "Samuel's Remains" } },
			{ { "accept", 363 } },
			{ { "turnin", 363 } },
		},
	}), "registers")
	ns.Engine.SetRoute("test/item")
	eq(ns.Engine.LiveStep(), 1, "not had yet: fetch it")
	stub.accept(363)
	eq(ns.Engine.LiveStep(), 3, "a quest further on done: the item step is behind you")
end)

test("a quest split over steps: each step is done with its own objectives (The Warsong Reports)", function()
	local stub, ns = login()
	local function obj(text) return { text = text, numFulfilled = 0, numRequired = 1, finished = false } end
	ok(Pathwise.RegisterRoute({
		id = "test/split", title = "Split (test)", category = "Leveling", map = 1420,
		levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
		steps = {
			{ title = "First", { "complete", 363, at = { 1420, 30, 70 }, obj = { 1 } } },
			{ title = "On the way", { "goto", 1420, 40, 60, "Somewhere" } },
			{ title = "Second", { "complete", 363, at = { 1420, 50, 50 }, obj = { 2 } } },
		},
	}), "registers")
	ns.Engine.SetRoute("test/split")
	stub.accept(363, { obj("Scout Update"), obj("Runner Update") })
	eq(ns.Engine.LiveStep(), 1, "the first objective is open")
	local rows = ns.Engine.View().objectives
	eq(#rows, 1, "the step lists only its own objective")
	eq(rows[1].text, "Scout Update")
	stub.progress(363, 1, 1)
	eq(ns.Engine.LiveStep(), 2, "its objective done: on to the next place, the quest still open")
	stub.moveTo(1420, 40, 60)
	ns.Engine.Refresh()
	stub.advance(1)
	eq(ns.Engine.LiveStep(), 3, "then the step for the other objective")
	eq(ns.Engine.View().objectives[1].text, "Runner Update")

	-- The route this came from: each visit is for its own update.
	local route
	for _, r in ipairs(ns.Engine.Routes()) do if r.id == "forever/horde/05-stonetalon-mountains" then route = r end end
	ok(route, "the Stonetalon route")
	local objs = {}
	for _, step in ipairs(route.steps) do
		for _, goal in ipairs(step) do
			if goal[1] == "complete" and goal[2] == 6543 then objs[#objs + 1] = goal.obj and table.concat(goal.obj, ",") or "all" end
		end
	end
	eq(table.concat(objs, " "), "1 3 2", "scout, outrider, runner")
end)

test("done by you: a quest, or a whole step, and back again", function()
	local stub, ns = fixture()
	eq(ns.Engine.LiveStep(), 1)
	ns.Panels.Open("skip")
	ok(stub.clickLabelText("I've already done it"), "the Skip panel offers it")
	ok(ns.Quests.Done(363), "counts as handed in")
	eq(ns.Engine.LiveStep(), 2, "on to the quest after it")
	ok(lastPrint(stub):find("marked .* done"), lastPrint(stub))
	ns.Panels.Open("skip")
	ok(stub.clickLabelText("This step is done"), "and the whole step")
	eq(ns.Engine.LiveStep(), 3, "the step behind you")
	eq(ns.Engine.Marked(), 2, "two marks")
	ns.Engine.ClearMarked()
	eq(ns.Engine.LiveStep(), 1, "brought back: the game's word again")
	ok(not ns.Quests.Done(363))
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
	-- One action per step: the cloth first, then the inn with its note and
	-- the optional graveyard.
	stub.items[2589] = 10
	stub.fire("BAG_UPDATE_DELAYED")
	v = ns.Guide.View()
	eq(v.title, "Gear up", "the same place, its next step")
	texts = {}
	for _, r in ipairs(v.objectives) do
		texts[#texts + 1] = r.text
		if r.text == "The graveyard" then optional = r.optional end
		if r.text == "Hearth to Brill" then info = r.info end
	end
	ok(contains(texts, "Make Brill your home"), "bind")
	ok(info, "a note row, marked as an instruction")
	ok(optional, "optional goal marked")
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

-- The text of every shown copy box (an EditBox in a shown row).
local function copyBoxes(stub)
	local out = {}
	for _, f in ipairs(stub.frames) do
		if f.kind == "EditBox" and f.shown and (not f.parent or f.parent.shown) and rawget(f, "text") then out[f.text] = true end
	end
	return out
end

test("report and about: the website and the Discord invite, ready to copy", function()
	local stub, ns = fixture()
	stub.accept(363)
	ns.Fire("REPORT_STEP")
	local boxes = copyBoxes(stub)
	ok(boxes["https://pathwise.quest/report"], "the website's report form")
	ok(boxes["https://discord.gg/hSDjBrG8EK"], "the Discord invite")
	ok(contains(stub.texts(), "Log in with Discord, then paste the report into the form."), "how to use the link")
	SlashCmdList.PATHWISE("about")
	boxes = copyBoxes(stub)
	ok(boxes["https://pathwise.quest"], "the website on About")
	ok(boxes["https://discord.gg/hSDjBrG8EK"], "the invite on About")
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
	stub.mapShown = 1411 -- Durotar: nothing of this step there, and no other quests' givers
	stub.advance(0.05)
	for _, f in ipairs(shownPins(stub, layer)) do
		ok(f.pin.kind ~= "available" and f.pin.kind ~= "turnin", "no marker of a quest not followed: " .. tostring(f.pin.kind))
	end
	ns.Set("pins.map", false)
	stub.mapShown = 1420
	stub.advance(0.05)
	eq(#shownPins(stub, layer), 0, "switched off in Settings")
end)

-- WCAG contrast, for a glyph on its badge.
local function contrast(a, b)
	local function lum(c)
		local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
		return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
	end
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

test("quest markers stand out on the map: solid, a readable size, on a dark badge with a ring", function()
	local stub, ns = fixture()
	local P, T = ns.Pins, ns.Theme
	local bg = T.Color("bg")
	-- Every quest marker's look: opaque, big enough, its glyph legible on the badge.
	for _, kind in ipairs({ "available", "turnin", "dungeon" }) do
		local look = P.LOOK[kind]
		eq(look.alpha, 1, kind .. ": opaque")
		ok(look.size >= 20, kind .. ": size " .. look.size)
		ok(look.size * look.badge >= 14, kind .. ": glyph " .. look.size * look.badge)
		ok(look.ring, kind .. ": a ring in its colour")
		ok(contrast(T.Color(look.color), bg) >= 4.5, kind .. " on the badge: " .. contrast(T.Color(look.color), bg))
	end
	ok(P.LOOK.objective.alpha == 1 and P.LOOK.objective.badge, "objective dots: solid, outlined")
	ok(P.BADGE_ALPHA >= 0.85, "the badge is near solid")
	-- Drawn: the step's first goal is to take The Damned from Undertaker
	-- Mordo, so the step's lead pin there wears the "!" badge.
	stub.mapShown = 1420
	stub.advance(0.05)
	local layer = P.world.layer
	local warning = T.Color("warning")
	local lead
	for _, f in ipairs(shownPins(stub, layer)) do
		local look = P.LOOK[f.pin.marker or f.pin.kind]
		if f.pin.kind == "lead" then lead = f end
		if look.badge then
			eq(f.w, look.size, "pin size")
			near(f.tex.w, look.size * look.badge, 1e-9, "the glyph inside the badge")
			eq(f.tex.vertex[4], 1, "the glyph is opaque")
			ok(f.back.shown, "the dark disc is shown")
			eq(f.back.texture, T.MEDIA .. "pin-disc")
			near(f.back.vertex[1], bg[1], 1e-9, "the disc is the theme's ground")
			eq(f.back.vertex[4], P.BADGE_ALPHA)
		else
			ok(not f.back.shown and not f.ring.shown, "no badge under " .. f.pin.kind)
			eq(f.tex.w, f.w, "the glyph fills its pin")
		end
	end
	ok(lead, "the step's lead pin")
	eq(lead.pin.marker, "available", "the lead at a giver: a \"!\"")
	eq(lead.pin.title, "Undertaker Mordo", "the step's tooltip kept")
	eq(lead.num.text, lead.pin.label, "and its step number")
	ok(lead.ring.shown, "the ring is shown")
	near(lead.ring.vertex[1], warning[1], 1e-9, "the ring in the marker's gold")
	near(lead.tex.vertex[1], warning[1], 1e-9, "the glyph in the marker's gold")
	eq(lead.tex.texture, T.MEDIA .. "glyph-quest")
	-- The minimap: the same badges, smaller, the glyph scaled with them.
	for _, g in ipairs(shownPins(stub, Minimap)) do
		local look = P.LOOK[g.pin.marker or g.pin.kind]
		if look.badge then near(g.tex.w, g.w * look.badge, 1e-9, "minimap glyph follows its badge") end
	end
end)

test("quest markers: only the step's quests and the tracked ones", function()
	local stub, ns = login()
	local M, Q = ns.QuestMarkers, ns.Quests
	local function find(kind, text)
		for _, p in ipairs(M.ForMap(1420)) do
			if p.kind == kind and (not text or (p.title or ""):find(text, 1, true) or (p.sub or ""):find(text, 1, true)) then return p end
		end
	end
	ok(Pathwise.RegisterRoute(FIXTURE), "fixture registers")
	ns.Engine.SetRoute(FIXTURE.id)
	-- Quests you could take on this map that the step does not name: no "!".
	local others = 0
	for id in pairs(Q.Data.quests) do
		if id ~= 363 and M.Available(id) then
			for _, n in ipairs(Q.Get(id)[7] or {}) do
				local npc = Q.Data.npcs[n]
				if npc and type(npc[5]) == "table" and npc[5][1420] then
					others = others + 1
					ok(not find("available", Q.Name(id)), "not the step's: no \"!\" for " .. Q.Name(id))
				end
			end
		end
	end
	ok(others > 0, "there are other quests to take around Deathknell")
	local damned = Q.Name(363)
	local giver = find("available", damned)
	ok(giver, "the step says take " .. damned .. ": a \"!\"")
	eq(giver.title, "Undertaker Mordo", "at its giver")
	ok(giver.sub:find("Quests to take", 1, true), giver.sub)
	ok(not find("available", Q.Name(376)), "a later step's quest: no \"!\" yet")
	-- Taken and ready: no ! for it, a ? at its finisher (the step's turn-in).
	stub.accept(363)
	ok(not find("available", damned), "taken: no ! for it")
	local hand = find("turnin", damned)
	ok(hand, "a ? to hand it in")
	eq(hand.title, "Shadow Priest Sarvis")
	stub.watch(363, false)
	ok(find("turnin", damned), "not tracked, but the step's: still shown")
	stub.turnin(363)
	-- A tracked quest with objectives left: dots where its monsters are.
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false },
		{ text = "Wretched Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	ok(find("objective", "Mindless Zombie"), "tracked: objective spots")
	-- Unticked in the log, and not the step's (it takes 376 and 1470 now): gone.
	stub.watch(364, false)
	ok(not find("objective", "Mindless Zombie"), "untracked: no dots")
	stub.watch(364, true)
	stub.progress(364, 1, 8)
	stub.progress(364, 2, 8)
	ok(not find("objective", "Mindless Zombie"), "finished: no more dots")
	ok(find("turnin", Q.Name(364)), "and a ? instead")
	-- A client that cannot say what is tracked: every quest in the log.
	stub.watch(364, false)
	C_QuestLog.GetQuestWatchType = nil
	ok(find("turnin", Q.Name(364)), "no watch API: the log's quests all shown")
	-- Switched off in Settings.
	ns.Set("pins.quests", false)
	for _, p in ipairs(ns.Pins.PinsFor(1420, "pins.quests", false)) do
		ok(p.kind ~= "available" and p.kind ~= "turnin" and p.kind ~= "objective" and not p.marker, "off: no quest markers")
	end
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

-- Forever's map stacks its own frames far above the canvas (level 2920 seen in
-- game, with Pathwise's layer at 53, under them): the pins stay on top.
test("world map pins: above the map's own frames, also ones made later", function()
	local stub, ns = fixture()
	local tiles = CreateFrame("Frame", nil, nil)
	tiles:SetParent(stub.canvas)
	tiles:SetFrameLevel(2920)
	stub.mapShown = 1420
	stub.advance(0.05)
	local layer = ns.Pins.world.layer
	ok(#shownPins(stub, layer) >= 1, "pins drawn")
	ok(layer:GetFrameLevel() > 2920, "above the map's frames, got " .. layer:GetFrameLevel())
	local later = CreateFrame("Frame", nil, nil)
	later:SetParent(stub.canvas)
	later:SetFrameLevel(3100)
	stub.advance(1.1)
	ok(layer:GetFrameLevel() > 3100, "above one made after the map opened, got " .. layer:GetFrameLevel())
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
	-- The list: each profession, its skill and one line; nothing more.
	local texts = stub.texts()
	ok(contains(texts, "Tailoring   1 / 75"), table.concat(texts, " | "))
	ok(contains(texts, "Enchanting   30 / 75"))
	ok(contains(texts, "Now: "), "what is next, in one line")
	ok(not contains(texts, "MATERIALS FOR THIS RANK"), "materials wait for the profession's page")
	ok(not contains(texts, "DISENCHANTING"))
	-- Tailoring's page.
	ok(stub.clickLabelText("Tailoring   1 / 75"), "click into Tailoring")
	texts = stub.texts()
	ok(contains(texts, "Best now: Bolt of Linen Cloth  ·  96 from your bags"), table.concat(texts, " | "))
	ok(contains(texts, "Open your Tailoring window once"), "asks for the recipe scan")
	ok(not contains(texts, "Enchanting   30 / 75"), "only Tailoring on its page")
	ok(stub.clickLabelText("Follow beside your route"), "follow from its page")
	ok(ns.Engine.Side(), "a side guide now")
	-- Back to the list, then Enchanting's page with disenchanting.
	ok(_G.PathwisePanel.back.shown, "a Back arrow")
	_G.PathwisePanel.back.scripts.OnClick(_G.PathwisePanel.back)
	ok(contains(stub.texts(), "Enchanting   30 / 75"), "back on the list")
	ok(stub.clickLabelText("Enchanting   30 / 75"))
	texts = stub.texts()
	ok(contains(texts, "DISENCHANTING"), table.concat(texts, " | "))
	ok(contains(texts, "Green Gloves  ·  skill ≈25"))
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

test("zones at 28 (Undead): a route working in a zone counts, cities and other races' starts say so", function()
	local stub, ns = login()
	stub.player.level = 28
	local by = {}
	for _, z in ipairs(ns.Engine.Zones()) do by[z.map] = z end
	ok(by[1441] and by[1441].route, "Thousand Needles has a route")
	eq(by[1441].route.id, "forever/horde/07-ashenvale", "Ashenvale & Thousand Needles works there")
	eq(by[1442] and by[1442].route and by[1442].route.id, "forever/horde/05-stonetalon-mountains")
	ok(by[1454] and by[1454].city and not by[1454].route, "Orgrimmar is a city")
	eq(by[1412] and by[1412].route and by[1412].route.id, "forever/horde/07-ashenvale", "Mulgore: the route that stops there")
	ns.Panels.Open("zones")
	local texts = stub.texts()
	ok(contains(texts, "City: the routes stop here for trainers and hand-ins"), "the city note")
	local coming = 0
	for _, z in pairs(by) do if not (z.route or z.city or z.raceRoute) then coming = coming + 1 eq(z.map, 1431, "only Duskwood, which has no Horde route") end end
	eq(coming, 1)
end)

test("zones: another race's starting zone names its route, and does not offer it", function()
	local stub, ns = login(function(s) s.player.race, s.player.raceID, s.player.faction = "NightElf", 4, "Alliance" end)
	stub.player.level = 8
	local dun
	for _, z in ipairs(ns.Engine.Zones()) do if z.map == 1426 then dun = z end end
	ok(dun, "Dun Morogh listed at 8")
	ok(not dun.route, "no route of a Night Elf's works there")
	ok(dun.raceRoute and dun.raceRoute.races[1] == "Dwarf", "the Dwarf and Gnome route")
end)

test("zones: a route you pick stays, even one you have outlevelled", function()
	local stub, ns = login()
	stub.player.level = 28
	local E = ns.Engine
	E.SetRoute("forever/horde/05-stonetalon-mountains") -- levels 23-25
	E.Update()
	eq(E.Route().id, "forever/horde/05-stonetalon-mountains", "not handed on to the next route")
	ok(E.LiveStep(), "a step to do")
end)

-- The route book (UI/RouteBook.lua): a button in it by the start of its text.
local function bookRow(stub, prefix)
	for _, f in ipairs(stub.frames) do
		local l = rawget(f, "label") or rawget(f, "name")
		if f.kind == "Button" and f.shown and type(l) == "table" and type(l.text) == "string"
			and l.text:sub(1, #prefix) == prefix and f.scripts.OnClick then return f end
	end
end

test("route book: Zones opens it on your level, a window of its own, with a card per route", function()
	local stub, ns = login()
	stub.player.level = 28
	ns.Fire("SHOW_ZONES")
	local f = _G.PathwiseRouteBook
	ok(f and f.shown, "the route book opens")
	eq(f.points[1][1], "CENTER", "on its own, not on the guide window")
	eq(f.points[1][2], UIParent)
	local B = ns.RouteBookWindow
	eq(B.state.chapter, 3, "levels 20-30")
	local titles = {}
	for _, r in ipairs(B.RoutesIn(3)) do titles[r.id] = true end
	ok(titles["forever/horde/07-ashenvale"] and titles["forever/horde/05-stonetalon-mountains"], "the 20s' routes")
	ok(bookRow(stub, "Ashenvale & Thousand Needles"), "a card for Ashenvale & Thousand Needles")
end)

test("route book: a route's page follows it, starts it from a step, and picks the route after it", function()
	local stub, ns = login()
	stub.player.level = 28
	local E, B = ns.Engine, ns.RouteBookWindow
	B.Open(3)
	local r = E.routes["forever/horde/05-stonetalon-mountains"]
	bookRow(stub, r.title).scripts.OnClick()
	eq(B.state.route, r.id, "its page")
	ok(bookRow(stub, "1.  "), "the steps, numbered")
	bookRow(stub, "Follow this route").scripts.OnClick()
	eq(E.Route().id, r.id, "followed")
	ok(bookRow(stub, "You are following this route"), "and it says so")
	bookRow(stub, "5.  ").scripts.OnClick()
	eq(E.Route().id, r.id)
	ok(E.State().stepsDone[r.id .. ":4"] and not E.State().stepsDone[r.id .. ":5"], "the steps before 5 count as done")
	eq(E.Progress(r).at >= 5, true, "the guide is at step 5 or past it")
	local choices = E.NextChoices(r)
	ok(#choices >= 2, "more than one way on")
	eq(choices[1].id, r.next, "its own next first")
	eq(E.NextOf(r), choices[1])
	bookRow(stub, choices[2].title).scripts.OnClick()
	eq(E.NextOf(r), choices[2], "the route after it, as picked")
	bookRow(stub, choices[1].title).scripts.OnClick()
	eq(E.State().nexts[r.id], nil, "back to its own")
end)

test("route book: going to a zone moves the guide there at once, on the route you follow", function()
	local stub, ns = login()
	stub.player.level = 28
	local E, B = ns.Engine, ns.RouteBookWindow
	stub.maps[1440] = { inst = 1, name = "Ashenvale", n0 = 0, ny = -20, w0 = 0, wx = -30 }
	stub.maps[1441] = { inst = 1, name = "Thousand Needles", n0 = 0, ny = -20, w0 = 0, wx = -30 }
	local r = E.routes["forever/horde/07-ashenvale"]
	E.SetRoute(r.id)
	local before = E.CurrentStep()
	eq(E.StepMap(r, before), 1440, "starts in Ashenvale")
	B.Open(3)
	bookRow(stub, r.title).scripts.OnClick()
	bookRow(stub, "Go to Thousand Needles").scripts.OnClick()
	local now = E.CurrentStep()
	eq(E.StepMap(r, now), 1441, "the guide's step is in Thousand Needles now")
	ok(now > before, "further on the route")
	eq(ns.Guide.View().index, now, "the guide window shows it")
	eq(E.Route().id, r.id, "the same route")
	ok(bookRow(stub, "Go to Thousand Needles"), "still listed")
	-- Following a route again goes back to its own order.
	E.SetRoute(r.id)
	eq(E.CurrentStep(), before, "back to the route's order")
end)

-- Synced with the quest log: picking a route you have partly done starts
-- after what you did, a home you set back then included.
test("quest log sync: a route picked part-done starts after what you did, hearth steps behind you too", function()
	local stub, ns = login()
	stub.player.level = 28
	local E = ns.Engine
	local r = E.routes["forever/horde/05-stonetalon-mountains"]
	local last = 0
	for s = 1, 10 do
		for _, g in ipairs(r.steps[s]) do
			if type(g[2]) == "number" and (g[1] == "turnin" or g[1] == "accept" or g[1] == "complete") then stub.done[g[2]] = true last = s end
		end
	end
	E.SetRoute(r.id)
	ok(E.LiveStep() > last, ("starts after step %d, at %s"):format(last, tostring(E.LiveStep())))
	local bindStep
	for s = 1, last do for _, g in ipairs(r.steps[s]) do if g[1] == "bind" then bindStep = s end end end
	ok(bindStep, "a hearth step among them")
	for g, goal in ipairs(r.steps[bindStep]) do
		if goal[1] == "bind" then eq(E.GoalStatus(r, bindStep, g, goal), "done", "the home behind you is done, set elsewhere now") end
	end
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
	ok(stub.clickInRow("Quest item button", "Hide"), "quest item button toggle")
	eq(ns.Get("itemButton.shown"), false)
	ok(stub.clickInRow("Show the arrow", "Hide"), "arrow toggle")
	eq(ns.Get("arrow.shown"), false)
	ok(stub.clickInRow("Lock the arrow", "Lock"), "arrow lock")
	eq(ns.Get("arrow.locked"), true)
	ok(stub.clickInRow("Lock the arrow", "Unlock"), "and unlock")
	eq(ns.Get("arrow.locked"), false)
	ok(stub.clickInRow("Accept and hand in quests", "Turn off"), "automation toggle")
	eq(ns.Get("auto.quests"), false)
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

test("accent: Pathwise blue, your class colour, or one you pick; the suite can follow it", function()
	local stub, ns = fresh()
	RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
	stub.login()
	local T = ns.Theme
	near(T.Color("accent")[1], 0x66 / 255, 1e-6, "Pathwise blue by default")
	ns.Set("ui.accentMode", "class")
	near(T.Color("accent")[1], 0.25, 1e-6, "a mage's colour")
	ok(T.Color("accentHover")[1] > 0.25, "hover a little lighter")
	ns.Set("ui.accentMode", "custom")
	ns.Set("ui.accentColor", "#FF0000")
	eq(T.ToHex(T.Color("accent")), "#FF0000")
	near(T.Color("gear")[1], 0xE8 / 255, 1e-6, "Pathwise Gear keeps its gold")
	ns.Set("ui.accentSuite", true)
	eq(T.ToHex(T.Color("gear")), "#FF0000", "the whole suite in your colour")
	-- In Settings: the three choices and the custom box.
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickLabel("Class"))
	eq(ns.Get("ui.accentMode"), "class")
	ok(stub.clickLabel("Custom"))
	local input
	for _, f in ipairs(stub.frames) do if rawget(f, "key") == "ui.accentColor" and f.shown then input = f end end
	ok(input, "a box for your colour")
	input.box:SetText("7fd98f")
	input.box.scripts.OnTextChanged(input.box, true)
	ok(stub.clickLabel("Apply"))
	eq(ns.Get("ui.accentColor"), "#7FD98F")
	RAID_CLASS_COLORS = nil
end)

-- The guide follows the character played, never a route saved for another
-- one: a saved route for another race, side or class is let go, and the
-- route is chosen only once race, class and side can be read.
local function saved(guide)
	return function() PathwiseCharSettings = { schema = 1, guide = guide } end
end

test("character: a saved route for another race and side is replaced at login", function()
	-- A Tauren whose saved file holds a Human's route (a deleted Human of the
	-- same name, or a route picked by id).
	local stub, ns = fresh()
	stub.player.level, stub.player.race, stub.player.raceID, stub.player.class, stub.player.faction = 1, "Tauren", 6, "WARRIOR", "Horde"
	saved({ route = "forever/alliance/human/01-elwynn-forest", layout = 2 })()
	stub.moveTo(1412, 50, 50) -- Mulgore
	stub.login()
	eq(ns.Engine.Route().id, "forever/horde/tauren/01-mulgore", "the Tauren's own first route")
end)

test("character: sync lets go of a route that is not for this character", function()
	local stub, ns = fresh()
	stub.player.level, stub.player.race, stub.player.raceID, stub.player.class, stub.player.faction = 1, "Tauren", 6, "WARRIOR", "Horde"
	stub.moveTo(1412, 50, 50) -- Mulgore
	stub.login()
	-- Chosen by id for another character (/pw route), then synced.
	ns.Engine.SetRoute("forever/alliance/human/01-elwynn-forest")
	local route = ns.Engine.Sync()
	eq(route.id, "forever/horde/tauren/01-mulgore", "synced to the Tauren's route")
end)

test("character: a class route for another class is let go", function()
	local stub, ns = fresh()
	stub.player.level, stub.player.race, stub.player.raceID, stub.player.class, stub.player.faction = 10, "Tauren", 6, "WARRIOR", "Horde"
	saved({ route = "forever/class/druid/bear-form", layout = 2 })()
	stub.moveTo(1412, 50, 50) -- Mulgore
	stub.login()
	local r = ns.Engine.Route()
	ok(r and ns.Engine.Fits(r, ns.Quests.Player()), "a route for a Tauren warrior, got " .. tostring(r and r.id))
end)

test("character: race and side not readable at login: no route is chosen until they are", function()
	local stub, ns = fresh()
	stub.player.level, stub.player.race, stub.player.raceID, stub.player.class, stub.player.faction = 1, nil, nil, "WARRIOR", nil
	stub.moveTo(1412, 50, 50) -- Mulgore
	stub.login()
	local r = ns.Engine.Route()
	ok(not r, "nothing chosen blind, got " .. tostring(r and r.id))
	-- Readable a moment later: the next update picks the character's route.
	stub.player.race, stub.player.raceID, stub.player.faction = "Tauren", 6, "Horde"
	ns.Engine.Update()
	eq(ns.Engine.Route() and ns.Engine.Route().id, "forever/horde/tauren/01-mulgore", "chosen once readable")
end)

---------------------------------------------------------------------------
-- The guide window's resize grip
---------------------------------------------------------------------------

-- The resize grip on window f.
local function findGrip(stub, f)
	for _, w in ipairs(stub.frames) do
		if w.parent == f and w.kind == "Button" and rawget(w, "icon") and tostring(w.icon.texture):find("glyph%-resize$") then return w end
	end
end

-- Drag the grip from (x0, y0) to (x1, y1) on screen and let go.
local function drag(stub, g, x0, y0, x1, y1, keep)
	stub.cursor = { x0, y0 }
	g.scripts.OnMouseDown(g, "LeftButton")
	stub.cursor = { x1, y1 }
	stub.advance(0.05)
	if not keep then g.scripts.OnMouseUp(g, "LeftButton") end
end

test("guide grip: width and height follow the drag, are clamped and saved; the steps scroll inside", function()
	local stub, ns = login()
	local f = _G.PathwiseGuide
	f.left, f.top = 600, 800
	local grip = findGrip(stub, f)
	ok(grip and grip.shown, "the grip is on the window")
	eq(f.resizable, true, "the window is resizable")
	eq(table.concat(f.resizeBounds, " "), "280 220 600 900", "with its bounds")
	local fitH = f.h
	drag(stub, grip, 100, 500, 160, 380, true) -- 60 right, 120 down
	eq(f.w, 400, "width follows the cursor")
	eq(f.h, fitH + 120, "height follows the cursor down, from the height on screen")
	eq(f.points[1][1], "TOPLEFT", "the top-left stays put while dragging")
	eq(f.points[1][3], "BOTTOMLEFT")
	eq(ns.Get("guide.height"), nil, "nothing saved before letting go")
	grip.scripts.OnMouseUp(grip, "LeftButton")
	eq(ns.Get("guide.width"), 400)
	eq(ns.Get("guide.height"), fitH + 120)
	local p = ns.Get("guide.point")
	eq(table.concat({ p[1], p[2], p[3], p[4] }, " "), "TOPLEFT 600 800 BOTTOMLEFT", "position saved by the corner it is pinned by")
	eq(grip.scripts.OnUpdate, nil, "no OnUpdate once let go")

	-- Shorter than the step: the footer keeps the bottom edge, the list scrolls.
	drag(stub, grip, 100, 500, 100, 3000)
	eq(ns.Get("guide.height"), 220, "clamped to the minimum")
	eq(f.h, 220)
	local scroll
	for _, w in ipairs(stub.frames) do if w.kind == "ScrollFrame" and w.parent == f then scroll = w end end
	ok(scroll, "the steps sit in a scroll area")
	eq(scroll.wheel, true, "the wheel scrolls the steps")
	scroll.scripts.OnMouseWheel(scroll, -1)
	ok(scroll:GetVerticalScroll() > 0, "scrolled down")
	-- The same step drawn again keeps its place; a new step starts at the top.
	ns.Guide.SetView(ns.Guide.View())
	ok(scroll:GetVerticalScroll() > 0, "a refresh keeps the scroll")
	local v = {}
	for k, val in pairs(ns.Guide.View()) do v[k] = val end
	v.index = (v.index or 0) + 1
	ns.Guide.SetView(v)
	eq(scroll:GetVerticalScroll(), 0, "a new step starts at its top")

	-- Taller than any step: room below, nothing to scroll.
	drag(stub, grip, 100, 500, 100, -5000)
	eq(ns.Get("guide.height"), 900, "clamped to the maximum")
	eq(f.h, 900)
	eq(scroll.wheel, false, "nothing to scroll: the wheel zooms the camera")
	drag(stub, grip, 100, 500, 5000, 500)
	eq(ns.Get("guide.width"), 600, "width clamped to the maximum")
end)

test("guide grip: a sideways drag keeps the height fitting each step; right-click fits it again", function()
	local stub, ns = login()
	local f = _G.PathwiseGuide
	local grip = findGrip(stub, f)
	drag(stub, grip, 100, 500, 180, 497) -- 3 px of wobble
	eq(ns.Get("guide.height"), nil, "the height still fits each step")
	eq(ns.Get("guide.width"), 420)
	ns.Set("guide.height", 300)
	eq(f.h, 300)
	grip.scripts.OnMouseDown(grip, "RightButton")
	eq(grip.scripts.OnUpdate, nil, "a right-click does not start a drag")
	grip.scripts.OnMouseUp(grip, "RightButton")
	eq(ns.Get("guide.height"), nil, "right-click: back to fitting each step")
	ok(f.h ~= 300, "and the window fits the step again")
	-- Settings: the row says so, and its button does the same.
	ns.Set("guide.height", 300)
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickInRow("Window height", "Fit to step"), "the settings row's button")
	eq(ns.Get("guide.height"), nil)
end)

test("guide grip: the saved size comes back at login, follows the cursor at any window size, and compact mode is one bar", function()
	local stub, ns = login(function()
		PathwiseSettings = { schema = 1, guide = { width = 420, height = 333 }, ui = { scale = 1.5 } }
	end)
	local f = _G.PathwiseGuide
	eq(f.w, 420, "width restored")
	eq(f.h, 333, "height restored")
	near(f.scale, 1.5, 1e-9, "the Window size setting still applies")
	local grip = findGrip(stub, f)
	drag(stub, grip, 100, 500, 175, 350) -- 75 right, 150 down on screen: 50 and 100 at 150%
	eq(ns.Get("guide.width"), 470)
	eq(ns.Get("guide.height"), 433)
	SlashCmdList.PATHWISE("compact")
	eq(grip.shown, false, "no grip on the compact bar")
	ok(f.h < 100, "the compact bar keeps its own height")
	SlashCmdList.PATHWISE("compact")
	eq(grip.shown, true)
	eq(f.h, 433, "back to the height set")
end)

test("guide grip: with a height of its own, the level line stays over the buttons, not in the scrolling list", function()
	local stub, ns = login()
	ns.Tracker.Line = function() return "Level 2  ·  35%  ·  3.8k XP/h" end
	local f = _G.PathwiseGuide
	local function line()
		for _, w in ipairs(stub.frames) do
			if w.kind == "FontString" and w.text == "Level 2  ·  35%  ·  3.8k XP/h" then return w end
		end
	end
	ns.Guide.Refresh()
	local s = line()
	ok(s and s.shown, "the level line is shown")
	ok(s.parent ~= f, "fitting each step: it is under the list, in it")
	ns.Set("guide.height", 230)
	ns.Guide.Refresh()
	eq(s.parent, f, "a height of its own: on the window, out of the scroll area")
	eq(s.points[1][1], "BOTTOMLEFT")
	ok(s.points[1][5] > 16, "over the buttons, not under them")
	ok(s.shown, "still shown")
	ns.Guide.SetCompact(true)
	ok(not s.shown, "compact: the bar alone")
	ns.Guide.SetCompact(false)
	ok(s.shown, "back with the full window")
	ns.Set("guide.height", nil)
	ns.Guide.Refresh()
	ok(s.parent ~= f, "fitting each step again: back in the list")
end)

-- The Befouled Element (1918): no one gives it; the Befouled Water Globe
-- (16408), from Tideress in Ashenvale, starts it (both from the data).
test("a quest started by an item: the arrow leads to what drops it, then the item button offers it", function()
	local stub, ns = login(function(s) s.player.level = 25 end)
	local Q, E = ns.Quests, ns.Engine
	eq(Q.StartItem(363), nil, "a quest someone gives has no start item")
	local item = Q.StartItem(1918)
	eq(item and item.id, 16408)
	eq(item and item.name, "Befouled Water Globe")
	ok(Pathwise.RegisterRoute({
		id = "test/globe", title = "Globe (test)", category = "Leveling", map = 1440,
		levels = { 23, 30 }, faction = "Horde",
		steps = { { title = "Tideress", { "accept", 1918 } } },
	}), "route registers")
	stub.moveTo(1440, 50, 60)
	E.SetRoute("test/globe")
	local goal = E.Route().steps[1][1]
	eq(E.GoalText(goal), "Use Befouled Water Globe: accept The Befouled Element")
	local p = E.PlaceOf(goal)
	ok(p, "without the globe: a place")
	eq(p and p.name, "Tideress", "where the globe drops")
	eq(ns.Nav.Target() and ns.Nav.Target().title, "Tideress", "and the arrow leads there")
	local line = E.LinesOf(E.Route(), 1, true)[1]
	eq(line.lead .. line.name .. line.tail, "Use Befouled Water Globe: accept The Befouled Element")
	stub.items[16408] = 1
	eq(E.PlaceOf(goal), nil, "with the globe: nowhere to go")
	E.Update()
	local b = _G.PathwiseItemButton
	ok(b and b.shown, "the item button shows")
	eq(b and b:GetAttribute("item"), "Befouled Water Globe", "with the globe, one click to accept")
	stub.items[16408] = nil
	E.Update()
	ok(not b.shown, "the globe gone: the button hides")
end)

-- The stub cannot load fonts, so a label the game drew blank is stood in for
-- by emptying its text: the point is that Pathwise sets it again.
test("guide buttons: Back, Skip and Next draw their labels again on a redraw and on entering the world", function()
	local stub, ns = fixture()
	ns.Guide.Refresh()
	local buttons = {}
	for _, f in ipairs(stub.frames) do
		local label = rawget(f, "pwLabel")
		if label and f.parent == _G.PathwiseGuide then buttons[label] = f end
	end
	for _, label in ipairs({ "Back", "Skip", "Next" }) do
		local b = buttons[label]
		ok(b and b.shown, label .. " is shown")
		b.pwText.text = ""
		b.w = 0
	end
	ns.Guide.Refresh()
	for _, label in ipairs({ "Back", "Skip", "Next" }) do
		eq(buttons[label].pwText.text, label, label .. ": its label is back after a redraw")
		ok(buttons[label].w >= 64, label .. ": its width too")
	end
	buttons.Next.pwText.text = ""
	stub.fire("PLAYER_ENTERING_WORLD", true, false)
	eq(buttons.Next.pwText.text, "Next", "and on entering the world")
end)

test("guide grip: muted at rest, brighter under the cursor, the accent while held", function()
	local stub, ns = login()
	local f, T = _G.PathwiseGuide, ns.Theme
	local grip = findGrip(stub, f)
	local function is(name)
		local c, v = T.Color(name), grip.icon.vertex
		return math.abs(c[1] - v[1]) < 1e-9 and math.abs(c[2] - v[2]) < 1e-9 and math.abs(c[3] - v[3]) < 1e-9
	end
	ok(is("muted"), "at rest")
	grip.scripts.OnEnter(grip)
	ok(is("text"), "under the cursor")
	grip.scripts.OnMouseDown(grip, "LeftButton")
	ok(is("accent"), "held")
	grip.scripts.OnMouseUp(grip, "LeftButton")
	ok(is("text"), "let go, still under the cursor")
	grip.scripts.OnLeave(grip)
	ok(is("muted"), "left")
end)

---------------------------------------------------------------------------
-- Routing from the quest log: the route holding the player's quests, quests
-- they have passed, and "From your quest log"
---------------------------------------------------------------------------

-- The leveling routes for an Undead mage at `level`, and a quest of the
-- second one that the first does not have (from the converted routes).
local function twoRoutes(ns, level)
	local E = ns.Engine
	local p = { race = "Scourge", raceID = 5, faction = "Horde", level = level, class = "MAGE" }
	local first = E.BestRoute(p, nil)
	local mine = {}
	for _, step in ipairs(first.steps) do for _, g in ipairs(step) do mine[g[2]] = true end end
	for _, r in ipairs(E.RoutesFor(p, "Leveling")) do
		if r ~= first and level >= r.levels[1] and level <= r.levels[2] then
			local qs = {}
			for _, step in ipairs(r.steps) do
				for _, g in ipairs(step) do
					if g[1] == "accept" and not mine[g[2]] and ns.Quests.Get(g[2]) then qs[#qs + 1] = g[2] end
				end
			end
			if #qs >= 2 then return p, first, r, qs end
		end
	end
	error("no second route at level " .. level)
end

test("a level-20 newcomer with a mixed quest log gets the route their quests are on", function()
	local stub, ns = fresh()
	local p, first, other, qs = twoRoutes(ns, 20)
	eq(ns.Engine.BestRoute(p, nil).id, first.id, "nothing held: as before")
	stub.log[qs[1]] = { objectives = {}, ready = true, watched = true }
	stub.log[qs[2]] = { objectives = { { text = "x: 0/5", numFulfilled = 0, numRequired = 5, finished = false } }, ready = false, watched = true }
	eq(ns.Engine.BestRoute(p, nil).id, other.id, "one ready, one under way: their route wins")
end)

test("the route picked at login moves to the one the quest log holds, until something is done on it", function()
	local stub, ns = fresh()
	local p, first, other, qs = twoRoutes(ns, 20)
	stub.player.level = 20
	stub.login()
	eq(ns.Engine.Route().id, first.id, "the log empty at login: picked by level")
	stub.accept(qs[1])
	stub.advance(1)
	eq(ns.Engine.Route().id, other.id, "the log fills: the route holding the quest")
	ok(lastPrint(stub):find(other.title, 1, true), "says so")

	-- Chosen by the player, or with work done on it, a route stays.
	local stub2, ns2 = fresh()
	stub2.player.level = 20
	stub2.login()
	ns2.Engine.SetRoute(first.id)
	stub2.accept(qs[1])
	stub2.advance(1)
	eq(ns2.Engine.Route().id, first.id, "the player's own choice stands")
end)

test("quests you have passed: green and grey quests behind the last quest done go, unless turned off", function()
	local stub, ns = fixture(function(s) s.player.level = 6 s.done[6395] = true end)
	local Q = ns.Quests
	ok(Q.Level(363) < 4 and Q.Level(376) < 4 and Q.Level(6395) >= 4, "the data: Deathknell's quests are low at 6, Marla's Last Wish is not")
	eq(ns.Guide.View().title, "Gear up", "Marla's Last Wish done: the low quests before it are left out")
	ns.Set("guide.skipPassed", false)
	ns.Engine.Update()
	eq(ns.Engine.LiveStep(), 1, "turned off: back to the first quest not done")
end)

test("quests you have passed: a level-up leaves out what it made too low, without a reload", function()
	local stub, ns = fixture(function(s) s.done[6395] = true end)
	eq(ns.Engine.LiveStep(), 1, "at 2 nothing is too low")
	stub.player.level = 6
	stub.fire("PLAYER_LEVEL_UP", 6)
	stub.advance(1)
	eq(ns.Guide.View().title, "Gear up")
end)

test("quests you have passed: nothing goes ahead of the last quest done, nor a quest a later one needs", function()
	local stub, ns = fixture(function(s) s.player.level = 6 end)
	eq(ns.Engine.LiveStep(), 1, "nothing done: nothing is behind")
	local E = ns.Engine
	local route = E.Route()
	ok(not E.PassedLow(route, 1, 363), "step 1 is not behind progress")
end)

test("from your quest log: a ready quest near you is listed, takes the arrow and is handed in for you", function()
	local stub, ns = fixture()
	local Q = ns.Quests
	stub.accept(376) -- ready: no objectives
	local fin = Q.Finisher(376)
	stub.moveTo(fin.map, fin.x + 0.5, fin.y)
	ns.Engine.Update()
	eq(ns.Engine.LiveStep(), 1, "the route's own step stays")
	local near = ns.Guide.View().nearby
	eq(#near, 1)
	eq(near[1].quest, 376)
	eq(near[1].verb, "turnin")
	ok(near[1].text:find("Turn in", 1, true), near[1].text)
	eq(ns.Nav.Target().title, fin.name, "nearer than Undertaker Mordo: the arrow leads to the hand-in")
	ok(ns.Engine.Wanted("turnin")[376], "the automation hands it in")

	stub.moveTo(1420, 80, 20)
	ns.Engine.Update()
	eq(#ns.Guide.View().nearby, 0, "far away: not listed")
	eq(ns.Nav.Target().title, "Undertaker Mordo", "the arrow is the step's again")
end)

test("from your quest log: objectives under way are listed by their place; skipped quests are not", function()
	local stub, ns = fixture()
	local Q = ns.Quests
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false },
		{ text = "Wretched Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	local at = Q.ObjectivePlace(364, 1)
	stub.moveTo(at.map, at.x, at.y)
	ns.Engine.Update()
	local near = ns.Guide.View().nearby
	eq(near[1] and near[1].quest, 364)
	eq(near[1].verb, "complete")
	ns.Engine.SkipQuest(364)
	eq(#ns.Guide.View().nearby, 0, "skipped: not listed")
end)
