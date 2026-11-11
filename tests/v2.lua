-- Tests for the v2 interface: the guide styles (Tracker, Window, Minimal),
-- the Signature Hub, the compass and your coordinates. Loaded by
-- tests/run.lua. The stub draws nothing: these check what each frame is
-- told to show, and that every control does what it says.
local h = ...
local test, eq, near, ok, fresh = h.test, h.eq, h.near, h.ok, h.fresh

local ROUTE = {
	id = "test/v2", title = "Deathknell (v2)", category = "Leveling", map = 1420,
	levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
	steps = {
		{ { "accept", 363 } },
		{ { "turnin", 363 }, { "accept", 364 } },
		{ title = "North of Deathknell", note = "Zombies roam the fields north of the crypt.", { "complete", 364 } },
		{ title = "The crypt door", { "goto", 1420, 32, 71.6, "The crypt door" } },
		{ { "turnin", 364 } },
	},
}

-- Logged in with the v2 defaults, on the test route.
local function start(setup)
	local stub, ns = fresh()
	stub.player.level = 2
	if setup then setup(stub) end
	stub.moveTo(1420, 30.2, 71.6)
	stub.login()
	ok(Pathwise.RegisterRoute(ROUTE), "route registers")
	ns.Engine.SetRoute(ROUTE.id)
	return stub, ns
end

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

-- A frame built in this run by its global name (frames of earlier tests'
-- runs linger as globals).
local function frame(stub, name)
	local f = _G[name]
	for _, w in ipairs(stub.frames) do if w == f then return f end end
	return nil
end

local function under(f, root)
	local p = rawget(f, "parent")
	while p do
		if p == root then return true end
		p = rawget(p, "parent")
	end
	return false
end

-- A font string under `root` whose text matches `pattern`.
local function textIn(stub, root, pattern)
	for _, f in ipairs(stub.frames) do
		if f.kind == "FontString" and rawget(f, "text") and tostring(f.text):find(pattern) and under(f, root) then return f end
	end
end

-- The button under `root` labelled `label` (T.RoundButton) and shown.
local function buttonIn(stub, root, label)
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "pwText")
		if t and t.text == label and f.shown and under(f, root) then return f end
	end
end

---------------------------------------------------------------------------
-- Styles
---------------------------------------------------------------------------

test("v2 defaults: the tracker and the compass show; the window and the old arrow do not", function()
	local stub, ns = start()
	eq(ns.Guide.Style(), "tracker")
	ok(frame(stub, "PathwiseTracker") and _G.PathwiseTracker.shown, "the tracker is on screen")
	ok(not frame(stub, "PathwiseGuide"), "the window is not even built")
	ok(not frame(stub, "PathwiseHud"), "nor the minimal guide")
	ok(frame(stub, "PathwiseCompass") and _G.PathwiseCompass.shown, "the compass is on")
	ns.Nav.SetTarget(1420, 40, 50, "West")
	ok(not (frame(stub, "PathwiseArrow") and _G.PathwiseArrow.shown), "the old arrow waits while the compass is on")
	ns.Set("compass.shown", false)
	ok(not _G.PathwiseCompass.shown, "compass off")
	ok(_G.PathwiseArrow.shown, "and the arrow is back")
end)

test("guide styles: one at a time, by setting, /pw style, cycling and the hub; hidden stays hidden", function()
	local stub, ns = start()
	local function only(name)
		for _, n in ipairs({ "PathwiseTracker", "PathwiseGuide", "PathwiseHud" }) do
			local f = frame(stub, n)
			eq(f ~= nil and f.shown or false, n == name, n .. " with " .. tostring(name) .. " wanted")
		end
	end
	only("PathwiseTracker")
	SlashCmdList.PATHWISE("style window")
	only("PathwiseGuide")
	SlashCmdList.PATHWISE("style minimal")
	only("PathwiseHud")
	SlashCmdList.PATHWISE("style")
	eq(ns.Get("guide.style"), "tracker", "after minimal, the tracker again")
	only("PathwiseTracker")
	Pathwise.Binding("style")
	eq(ns.Get("guide.style"), "window", "the key does the same")
	SlashCmdList.PATHWISE("style nonsense")
	eq(ns.Get("guide.style"), "window", "an unknown style changes nothing")
	ns.Set("guide.shown", false)
	only(nil)
	ns.Set("guide.style", "minimal")
	only(nil)
	ns.Set("guide.shown", true)
	only("PathwiseHud")
	ns.Set("guide.style", "made-up")
	eq(ns.Guide.Style(), "tracker", "a value from elsewhere reads as the tracker")
	only("PathwiseTracker")
end)

test("settings: the style buttons, Show it, the compass and coordinate rows", function()
	local stub, ns = start()
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickInRow("Style", "Minimal"), "the style row")
	eq(ns.Get("guide.style"), "minimal")
	ok(stub.clickInRow("Style", "Window"))
	eq(ns.Get("guide.style"), "window")
	ok(stub.clickInRow("Compass", "Hide"), "the compass row")
	eq(ns.Get("compass.shown"), false)
	ok(stub.clickInRow("Your coordinates", "Hide"), "the coordinates row")
	eq(ns.Get("compass.coords"), false)
	ok(stub.clickInRow("Show it", "Hide"), "the guide's own row")
	eq(ns.Get("guide.shown"), false)
end)

---------------------------------------------------------------------------
-- Tracker
---------------------------------------------------------------------------

test("tracker: the route, its side and levels, the step, objectives as checkboxes", function()
	local stub, ns = start()
	local f = _G.PathwiseTracker
	stub.accept(363)
	stub.turnin(363)
	stub.accept(364, { { text = "Mindless Zombie slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } })
	ns.Engine.Update()
	ok(textIn(stub, f, "^Deathknell %(v2%)$"), "the route's name")
	ok(textIn(stub, f, "^Horde  ·  Levels 1%-6$"), "its side and levels")
	ok(textIn(stub, f, "^STEP 3 OF 5$"), "the step label")
	ok(textIn(stub, f, "^North of Deathknell$"), "the step's title on its card")
	ok(textIn(stub, f, "Zombies roam"), "the note")
	ok(textIn(stub, f, "^3/8$"), "the objective's count")
	local checks = {}
	for _, w in ipairs(stub.frames) do
		if rawget(w, "checked") ~= nil and w.shown and w.parent and w.parent.parent == f and w.parent.shown then checks[#checks + 1] = w end
	end
	ok(#checks >= 1, "a checkbox per objective row")
	ok(not checks[#checks].checked, "not done yet: unticked")
	stub.progress(364, 1, 8)
	ns.Engine.Update()
	ok(textIn(stub, f, "^Step 4 of 5$") or textIn(stub, f, "^STEP 4 OF 5$"), "done: on to the next step")
end)

test("tracker: its buttons go back, skip, next, open the hub, collapse and close", function()
	local stub, ns = start()
	local f = _G.PathwiseTracker
	local fired = {}
	for _, m in ipairs({ "GUIDE_BACK", "GUIDE_SKIP", "GUIDE_NEXT" }) do ns.On(m, function() fired[m] = true end) end
	for label, m in pairs({ Back = "GUIDE_BACK", Skip = "GUIDE_SKIP", Next = "GUIDE_NEXT" }) do
		local b = buttonIn(stub, f, label)
		ok(b, label .. " is on the tracker")
		b.scripts.OnClick(b)
		ok(fired[m], label .. " fires " .. m)
	end
	local W = ns.TrackerCard.frames
	W.hub.scripts.OnClick(W.hub)
	ok(_G.PathwiseHub and _G.PathwiseHub.shown, "the hub button opens the hub")
	eq(f.shown, false, "the tracker steps aside while the hub is open")
	ns.Hub.Show(false)
	ok(f.shown, "and is back when it closes")
	W.step.scripts.OnClick(W.step)
	ok(_G.PathwiseHub.shown, "the step card opens it too")
	ns.Hub.Show(false)
	local tall = f.h
	W.collapse.scripts.OnClick(W.collapse)
	eq(ns.Get("guide.compact"), true)
	ok(f.h < tall, "collapsed: shorter")
	W.compass.scripts.OnClick(W.compass)
	eq(ns.Get("compass.shown"), false, "the compass button turns it off")
	local n = #stub.printed
	W.close.scripts.OnClick(W.close)
	eq(ns.Get("guide.shown"), false)
	ok(stub.printed[#stub.printed]:find("hub"), "says how to bring it back")
	eq(#stub.printed, n + 1)
end)

test("tracker: a profession detour shows as the optional task with Go", function()
	local stub, ns = start()
	local v = {}
	for k, val in pairs(ns.Guide.View()) do v[k] = val end
	v.detour = { label = "Optional · Tailoring", text = "Craft 12 Bolt of Linen Cloth", sub = "Wherever you are" }
	ns.Guide.SetView(v)
	local f = _G.PathwiseTracker
	ok(textIn(stub, f, "^OPTIONAL · TAILORING$"), "its label")
	ok(textIn(stub, f, "^Craft 12 Bolt of Linen Cloth$"), "what to do")
	local went
	ns.On("DETOUR_GO", function(d) went = d end)
	local go = buttonIn(stub, f, "Go")
	ok(go, "a Go button")
	go.scripts.OnClick(go)
	eq(went and went.text, "Craft 12 Bolt of Linen Cloth", "Go takes the detour")
end)

---------------------------------------------------------------------------
-- Minimal
---------------------------------------------------------------------------

test("minimal: route and step over the game, objectives, the detour line and buttons", function()
	local stub, ns = start()
	ns.Set("guide.style", "minimal")
	local f = _G.PathwiseHud
	ok(f and f.shown, "shown")
	ok(textIn(stub, f, "^DEATHKNELL %(V2%)  ·  1 / 5$"), "the route and the step count")
	local v = {}
	for k, val in pairs(ns.Guide.View()) do v[k] = val end
	v.detour = { label = "Optional · Tailoring", text = "Craft 12 Bolt of Linen Cloth" }
	ns.Guide.SetView(v)
	ok(textIn(stub, f, "^%+ Tailoring: Craft 12 Bolt of Linen Cloth$"), "the detour as one line")
	ok(textIn(stub, f, "^You  30%.2, 71%.6$"), "your coordinates")
	local next = buttonIn(stub, f, "Next")
	ok(next, "Next")
	local fired
	ns.On("GUIDE_NEXT", function() fired = true end)
	next.scripts.OnClick(next)
	ok(fired, "Next fires")
end)

---------------------------------------------------------------------------
-- Hub
---------------------------------------------------------------------------

test("hub: opens and closes (key, /pw hub), is an Escape window, draws the route and the step", function()
	local stub, ns = start()
	UISpecialFrames = {}
	SlashCmdList.PATHWISE("hub")
	local f = _G.PathwiseHub
	ok(f and f.shown, "open")
	eq(UISpecialFrames[1], "PathwiseHub", "Escape closes it")
	ok(textIn(stub, f, "^LEVELING ROUTE  ·  HORDE$"), "the eyebrow")
	ok(textIn(stub, f, "^Deathknell %(v2%)$"), "the route")
	ok(textIn(stub, f, "^STEP 1 OF 5$"), "the step")
	ok(textIn(stub, f, "^Step 1$"), "the steps down the side")
	ok(textIn(stub, f, "^Level 2"), "your level")
	ok(textIn(stub, f, "^You  30%.2, 71%.6$"), "your coordinates")
	ok(buttonIn(stub, f, "Next"), "Next")
	Pathwise.Binding("hub")
	eq(f.shown, false, "the key closes it")
	ns.Fire("TOGGLE_HUB", true)
	ns.Fire("TOGGLE_HUB", true)
	ok(f.shown, "asked to open, it stays open")
end)

test("hub: On screen picks the guide style or hides it; compass and coordinates rows", function()
	local stub, ns = start()
	ns.Fire("TOGGLE_HUB")
	local W = ns.Hub.frames
	ok(W.styles.tracker.active, "the tracker row is selected")
	W.styles.window.scripts.OnClick(W.styles.window)
	eq(ns.Get("guide.style"), "window")
	ok(not _G.PathwiseTracker.shown, "nothing on screen while the hub is open")
	ok(W.styles.window.active and not W.styles.tracker.active, "and its row is selected")
	W.styles.off.scripts.OnClick(W.styles.off)
	eq(ns.Get("guide.shown"), false, "Hidden hides the guide")
	ok(W.styles.off.active, "Hidden is selected")
	W.styles.minimal.scripts.OnClick(W.styles.minimal)
	eq(ns.Get("guide.shown"), true, "a style shows it again")
	ns.Hub.Show(false)
	ok(_G.PathwiseHud.shown, "the minimal guide, once the hub closes")
	ns.Hub.Show(true)
	eq(W.compassRow.value.text, "On")
	W.compassRow.scripts.OnClick(W.compassRow)
	eq(ns.Get("compass.shown"), false)
	eq(W.compassRow.value.text, "Off")
	W.coordsRow.scripts.OnClick(W.coordsRow)
	eq(ns.Get("compass.coords"), false)
	ok(not W.coords.shown, "no coordinates in the hub when off")
end)

test("hub: the route cards follow the route and its next ones; tabs; professions", function()
	local stub, ns = start(function(s) s.skills[197] = { 48, 75 } end)
	ok(Pathwise.RegisterRoute({ id = "test/v2-next", title = "Brill (v2)", category = "Leveling", map = 1420, levels = { 6, 10 }, faction = "Horde", steps = { { { "note", "x" } } } }))
	ns.Engine.SetNext(ROUTE.id, "test/v2-next")
	local cards = ns.Hub.RouteCards("Leveling")
	eq(cards[1].route.id, ROUTE.id, "the route you follow first")
	ok(cards[1].current)
	eq(cards[1].sub, "Following now")
	eq(cards[2] and cards[2].route.id, "test/v2-next", "then the next one")
	eq(cards[2].sub, "Next route")
	ns.Fire("TOGGLE_HUB")
	local W = ns.Hub.frames
	ok(W.routeCards[1].shown and W.routeCards[2].shown, "drawn")
	W.tabs.Class.scripts.OnClick(W.tabs.Class)
	eq(ns.Get("hub.tab"), "Class")
	ok(W.tabs.Class.line.shown and not W.tabs.Leveling.line.shown, "the tab is marked")
	for _, c in ipairs(ns.Hub.RouteCards("Class")) do eq(c.route.category, "Class") end
end)

---------------------------------------------------------------------------
-- Compass
---------------------------------------------------------------------------

test("compass maths: heading from facing, offsets on the strip, the target pinned at the ends", function()
	local _, ns = fresh()
	local K = ns.Compass
	eq(K.Heading(0), 0, "facing north")
	near(K.Heading(math.pi / 2), 270, 1e-9, "a quarter turn counter-clockwise faces west")
	near(K.Heading(-math.pi / 2), 90, 1e-9, "and clockwise, east")
	eq(K.Offset(0, 0, 440, 180), 0, "north in the middle facing north")
	near(K.Offset(0, 45, 440, 180), 110, 1e-9, "NE to the right")
	near(K.Offset(350, 10, 440, 180), 48.888, 0.01, "across north")
	eq(K.Offset(0, 180, 440, 180), nil, "south is off the strip facing north")
	local x, pinned = K.TargetOffset(0, 440, 180)
	eq(x, 0) eq(pinned, false)
	x, pinned = K.TargetOffset(math.pi / 2, 440, 180) -- 90 degrees to the left
	near(x, -210, 1e-9, "left, pinned at the end")
	eq(pinned, true)
	x, pinned = K.TargetOffset(-math.pi / 4, 440, 180) -- 45 to the right
	near(x, 110, 1e-9)
	eq(pinned, false)
end)

test("compass: the strip turns with you; the waypoint, its distance and coordinates; yours", function()
	local stub, ns = start()
	local W = ns.Compass.frames
	ok(W.frame.shown, "shown")
	local function labelX(name)
		for _, fs in ipairs(W.labels) do
			if fs.text == name then return fs.shown and fs.points[1][4] or nil end
		end
	end
	eq(labelX("N"), 0, "facing north: N in the middle")
	stub.player.facing = -math.pi / 2 -- turn to face east
	stub.advance(0.05)
	eq(labelX("E"), 0, "facing east: E in the middle")
	near(labelX("NE"), -110, 1e-6, "NE to the left")
	eq(labelX("N"), nil, "N at the very end fades away")
	stub.player.facing = 0
	ns.Nav.SetTarget(1420, 30.2, 61.6, "North point") -- 200 yd due north
	stub.advance(0.2)
	eq(W.name.text, "North point")
	eq(W.dist.text, "200 yd")
	eq(W.where.text, "30.2, 61.6  ·  Tirisfal Glades")
	ok(W.caret.shown, "the caret marks it")
	near(W.caret.points[1][4], 0, 1e-6, "dead ahead: in the middle")
	eq(W.you.text, "You  30.2, 71.6  ·  Tirisfal Glades")
	stub.moveTo(1420, 30.2, 61.65)
	stub.advance(0.3)
	eq(W.dist.text, "Arrived")
	eq(W.you.text, "You  30.2, 61.6  ·  Tirisfal Glades", "yours follow you")
	ns.Set("compass.coords", false)
	ok(not W.you.shown, "coordinates off")
	SlashCmdList.PATHWISE("compass")
	ok(not W.frame.shown, "/pw compass turns it off")
	Pathwise.Binding("compass")
	ok(W.frame.shown, "the key turns it back on")
end)

test("compass: arriving reaches a 'go to' step, as the arrow did", function()
	local stub, ns = start()
	stub.accept(363) stub.turnin(363)
	stub.accept(364, { { text = "Mindless Zombie slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } })
	stub.progress(364, 1, 8)
	ns.Engine.Update()
	eq(ns.Engine.LiveStep(), 4, "on the go-to step")
	stub.moveTo(1420, 32, 71.6)
	stub.advance(0.5)
	ok(ns.Engine.LiveStep() ~= 4, "reached with the compass: past it")
end)

---------------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------------

test("rounded panels: four corners, a middle and strips; recoloured and following opacity", function()
	local stub, ns = start()
	local f = _G.PathwiseTracker
	local rd = f.pwRound
	ok(rd and #rd.fills == 7, "four corners, the middle and two strips")
	eq(#rd.lines, 8, "four corner lines and four edges")
	for i = 1, 4 do ok(rd.fills[i].texture:find("corner$"), "corner " .. i) end
	SlashCmdList.PATHWISE("opacity 50")
	near(rd.fills[5].color[4], 0.5, 1e-9, "the middle follows the opacity setting")
	near(rd.fills[1].vertex[4], 0.5, 1e-9, "and the corners")
end)

---------------------------------------------------------------------------
-- Themes
---------------------------------------------------------------------------

local function lum(c)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function contrast(a, b)
	local la, lb = lum(a), lum(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

test("themes: every one is legible, dark or light, and a filled button's label reads on its accent", function()
	local _, ns = fresh()
	local T = ns.Theme
	ok(#T.THEMES >= 15, "a good many themes")
	local seen, light, dark = {}, 0, 0
	for _, th in ipairs(T.THEMES) do
		ok(not seen[th.key], "unique key " .. th.key)
		seen[th.key] = true
		if th.mode == "light" then light = light + 1 else dark = dark + 1 end
		local c = {}
		for k, v in pairs(th) do if type(v) == "string" and v:match("^#%x+$") then c[k] = T.Hex(v) end end
		for _, ground in ipairs({ "bg", "bg2", "hover" }) do
			ok(contrast(c.text, c[ground]) >= 7, th.key .. ": text on " .. ground)
			for _, role in ipairs({ "text2", "accent", "success", "warning" }) do
				ok(contrast(c[role], c[ground]) >= 4.5, th.key .. ": " .. role .. " on " .. ground .. " " .. contrast(c[role], c[ground]))
			end
		end
		ok(contrast(c.muted, c.bg) >= 4.5 and contrast(c.muted, c.bg2) >= 4.5, th.key .. ": muted")
		ok(contrast(c.bg, c.accent) >= 4.5, th.key .. ": a filled button's label")
		if th.mode == "light" then ok(th.world, th.key .. ": a light theme has a world accent") end
	end
	ok(light >= 5 and dark >= 8, "both kinds")
	for _, key in ipairs({ "pathwise", "midnight", "snow", "rose", "blossom", "amethyst", "lavender" }) do ok(seen[key], key) end
end)

test("themes: picking one changes the palette in place; the accent follows unless class or custom", function()
	local stub, ns = start()
	local T = ns.Theme
	local bg, accent = T.COLORS.bg, T.COLORS.accent
	ns.Set("ui.theme", "blossom")
	eq(T.COLORS.bg, bg, "the same table")
	eq(T.ToHex(T.COLORS.bg), "#FFF4F8", "now Blossom's ground")
	eq(T.ToHex(T.COLORS.accent), "#B8175A", "and its accent")
	eq(T.COLORS.accent, accent)
	-- Over the world, a light theme stays light.
	ok(lum(T.World("text")) > 0.8, "world text stays light")
	eq(T.ToHex(T.World("accent")), "#FF8CC0", "the world accent")
	ns.Set("ui.accentMode", "custom")
	ns.Set("ui.accentColor", "#123456")
	eq(T.ToHex(T.COLORS.accent), "#123456", "a custom accent wins over the theme's")
	ns.Set("ui.accentMode", "pathwise")
	eq(T.ToHex(T.COLORS.accent), "#B8175A", "back to the theme's")
	SlashCmdList.PATHWISE("theme midnight")
	eq(ns.Get("ui.theme"), "midnight")
	eq(T.ToHex(T.COLORS.accent), "#FFFFFF")
	SlashCmdList.PATHWISE("theme High Contrast")
	eq(ns.Get("ui.theme"), "contrast", "by name too")
	SlashCmdList.PATHWISE("theme nonsense")
	eq(ns.Get("ui.theme"), "contrast", "an unknown name changes nothing")
	ns.Set("ui.theme", "gone")
	eq(T.Theme().key, "pathwise", "an unknown saved theme reads as Pathwise Blue")
end)

test("themes: Settings shows a tile per theme in its colours; clicking one picks it; open windows repaint", function()
	local stub, ns = start()
	ns.Fire("SHOW_SETTINGS")
	local tiles = {}
	for _, f in ipairs(stub.frames) do
		if rawget(f, "theme") and f.shown and f.parent and f.parent.shown then tiles[f.theme.key] = f end
	end
	local n = 0
	for _ in pairs(tiles) do n = n + 1 end
	eq(n, #ns.Theme.THEMES, "every theme has a tile")
	ok(tiles.pathwise.selected and not tiles.lavender.selected, "the theme in use is marked")
	eq(tiles.lavender.name.text, "Lavender")
	tiles.lavender.scripts.OnClick(tiles.lavender)
	eq(ns.Get("ui.theme"), "lavender")
	ok(stub.printed[#stub.printed]:find("reload"), "says a reload finishes it")
	local mid = _G.PathwiseTracker.pwRound.fills[5]
	eq(ns.Theme.ToHex(mid.color), "#F7F3FD", "the tracker's ground repaints at once")
end)

---------------------------------------------------------------------------
-- Pins
---------------------------------------------------------------------------

test("pins: the hub, tracker and window pin in place and ignore drags; the minimal guide and compass let clicks through", function()
	local stub, ns = start()
	local f = _G.PathwiseTracker
	local W = ns.TrackerCard.frames
	W.pin.scripts.OnClick(W.pin)
	eq(ns.Get("card.locked"), true, "the tracker's pin")
	near(W.pin.pwIcon.vertex[1], ns.Theme.COLORS.accent[1], 1e-9, "tinted in the accent")
	W.head.scripts.OnDragStart(W.head)
	ok(not rawget(f, "moving"), "pinned: a drag does nothing")
	W.pin.scripts.OnClick(W.pin)
	W.head.scripts.OnDragStart(W.head)
	ok(rawget(f, "moving"), "unpinned: it moves")
	W.head.scripts.OnDragStop(W.head)

	ns.Fire("TOGGLE_HUB", true)
	local H = ns.Hub.frames
	H.lock.scripts.OnClick(H.lock)
	eq(ns.Get("hub.locked"), true, "the hub's pin")
	H.main.scripts.OnDragStart(H.main)
	ok(not rawget(_G.PathwiseHub, "moving"), "the hub holds still")
	ns.Hub.Show(false)

	ns.Set("guide.style", "window")
	ns.Guide.Show(true)
	ns.Set("guide.locked", true)
	local g = _G.PathwiseGuide
	local head
	for _, w in ipairs(stub.frames) do if w.parent == g and rawget(w, "scripts") and w.scripts.OnDragStart and w.h == ns.Guide.HEAD_H then head = w end end
	ok(head, "the window's header")
	head.scripts.OnDragStart(head)
	ok(not rawget(g, "moving"), "the window holds still")

	ns.Set("guide.style", "minimal")
	local hud = ns.Hud.frames
	eq(hud.grip.mouse, true, "the minimal guide's top line takes the mouse to move it")
	hud.pin.scripts.OnClick(hud.pin)
	eq(ns.Get("hud.locked"), true)
	eq(hud.grip.mouse, false, "pinned: no mouse, clicks go to the world")

	local c = _G.PathwiseCompass
	eq(c.mouse, true)
	SlashCmdList.PATHWISE("compass pin")
	eq(ns.Get("compass.locked"), true)
	eq(c.mouse, false, "the pinned compass lets clicks through")
end)

---------------------------------------------------------------------------
-- Resize grips
---------------------------------------------------------------------------

-- Drags grip `g` by (dx, dy) on screen (down is positive dy).
local function dragGrip(stub, g, dx, dy, button)
	stub.cursor = { 500, 500 }
	g.scripts.OnMouseDown(g, button or "LeftButton")
	stub.cursor = { 500 + dx, 500 - dy }
	stub.advance(0.05)
	g.scripts.OnMouseUp(g, button or "LeftButton")
end

test("hub grip: any width and height, clamped and saved; narrow, the routes column steps aside", function()
	local stub, ns = start()
	ns.Fire("TOGGLE_HUB", true)
	local f, H = _G.PathwiseHub, ns.Hub.frames
	eq(f.w, 1160) eq(f.h, 720)
	dragGrip(stub, H.grip, 200, 150)
	eq(f.w, 1360, "wider")
	eq(f.h, 870, "taller")
	eq(ns.Get("hub.width"), 1360, "saved")
	eq(ns.Get("hub.height"), 870)
	eq(H.main.w, 1360 - (168 + 16 + 360 + 16), "the guide column takes the new room")
	ok(H.routes.shown, "wide: the routes column")
	dragGrip(stub, H.grip, -560, 0)
	eq(f.w, 800)
	ok(not H.routes.shown and not H.prof.shown, "narrow: routes and professions step aside")
	eq(H.main.w, 800 - 184, "the guide beside the menu")
	dragGrip(stub, H.grip, -5000, -5000)
	eq(f.w, ns.Hub.MIN_W, "never narrower than the least")
	eq(f.h, ns.Hub.MIN_H)
	dragGrip(stub, H.grip, 0, 0, "RightButton")
	eq(ns.Get("hub.width"), nil, "right-click: the usual size again")
	eq(f.w, 1160)
	ns.Set("hub.locked", true)
	dragGrip(stub, H.grip, 300, 0)
	eq(f.w, 1160, "pinned: it does not resize")
end)

test("hub grip: a shorter hub lists fewer professions, never under the recipe book button", function()
	local stub, ns = start(function(s) s.skills[197] = { 48, 75 } s.skills[333] = { 41, 75 } s.skills[185] = { 22, 75 } s.skills[129] = { 30, 75 } end)
	ns.Fire("TOGGLE_HUB", true)
	local H = ns.Hub.frames
	local function shown() local n = 0 for _, c in ipairs(H.profCards) do if c.shown then n = n + 1 end end return n end
	eq(shown(), 3, "the usual height: three, above the recipe book button")
	ns.Set("hub.height", 900)
	eq(shown(), 4, "taller: all four")
	ns.Set("hub.height", 560)
	ok(shown() < 3, "shorter: fewer rows (" .. shown() .. ")")
end)

test("tracker, minimal guide and compass grips: width, saved, reset; the compass grows from its middle", function()
	local stub, ns = start()
	local W = ns.TrackerCard.frames
	dragGrip(stub, W.grip, 100, 80)
	eq(_G.PathwiseTracker.w, 440, "the tracker widens")
	eq(ns.Get("card.width"), 440)
	eq(ns.Get("card.height"), nil, "its height fits the step")
	dragGrip(stub, W.grip, 0, 0, "RightButton")
	eq(_G.PathwiseTracker.w, 340, "reset")

	ns.Set("guide.style", "minimal")
	local hud = ns.Hud.frames
	dragGrip(stub, hud.sizer, 60, 0)
	eq(_G.PathwiseHud.w, 380, "the minimal guide's lines run wider")
	ns.Set("hud.locked", true)
	eq(hud.sizer.shown, false, "pinned: no grip")

	local K = ns.Compass
	dragGrip(stub, K.frames.grip, 50, 0)
	eq(K.WIDTH, 540, "the compass grows both ways: twice the drag")
	eq(K.frames.strip.w, 540)
	eq(ns.Get("compass.width"), 540)
	ns.Set("compass.width", nil)
	eq(K.WIDTH, 440, "reset")
end)

---------------------------------------------------------------------------
-- Crests, class and profession icons, route maps
---------------------------------------------------------------------------

test("crests: the Alliance shield, the Horde badge, the theme's shield with no side", function()
	local stub, ns = start()
	local T = ns.Theme
	local c = T.Crest(UIParent, 40)
	c:SetFaction("Alliance")
	ok(c.fill.texture:find("crest%-alliance$") and c.edge.texture:find("crest%-alliance%-edge$") and c.mark.texture:find("crest%-alliance%-mark$"), "the shield")
	eq(T.ToHex(c.fill.vertex), "#2A4FA8", "in Alliance blue")
	c:SetFaction("Horde")
	ok(c.fill.texture:find("crest%-horde$"), "the badge")
	eq(T.ToHex(c.fill.vertex), "#9E2B25", "in Horde red")
	c:SetFaction(nil)
	eq(T.ToHex(c.fill.vertex), T.ToHex(T.Color("bg2")), "no side: the theme's colours")
	-- The tracker draws the route's side.
	eq(ns.TrackerCard.frames.crest.faction, "Horde", "the test route is a Horde one")
	for _, name in ipairs({ "crest-alliance", "crest-alliance-edge", "crest-alliance-mark", "crest-horde", "crest-horde-edge", "crest-horde-mark" }) do
		local f = io.open("Pathwise/Media/" .. name .. ".tga", "rb")
		ok(f, name .. ".tga") if f then f:close() end
	end
end)

test("class and profession icons: the game's where it has them, Pathwise's drawings where not", function()
	local stub, ns = start()
	local T = ns.Theme
	local m = T.Mark(UIParent, 24)
	m:SetProfession("tailoring")
	ok(m.icon.shown and m.icon.texture == "Interface\\Icons\\Trade_Tailoring", "the game's Tailoring icon")
	ok(not m.glyph.shown)
	m:SetClass("MAGE")
	ok(m.glyph.shown and m.glyph.texture:find("class%-mage$"), "no class icon table here: the drawing")
	CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }
	m:SetClass("MAGE")
	ok(m.icon.shown and m.icon.texture:find("UI%-Classes%-Circles$"), "with it: the game's class icon")
	CLASS_ICON_TCOORDS = nil
	PATHWISE_PREVIEW = true
	m:SetProfession("first-aid")
	ok(m.glyph.shown and m.glyph.texture:find("prof%-first%-aid$"), "no game art (the preview): the drawing")
	PATHWISE_PREVIEW = nil
	-- A drawing for every class with a route and every profession.
	local names = {}
	for _, p in ipairs({ "alchemy", "blacksmithing", "enchanting", "engineering", "leatherworking", "tailoring", "herbalism", "mining", "skinning", "cooking", "first-aid", "fishing" }) do
		names[#names + 1] = "prof-" .. p
		ok(T.PROF_ICONS[p], "a game icon for " .. p)
	end
	for _, c in ipairs({ "warrior", "paladin", "hunter", "rogue", "priest", "mage", "warlock", "druid", "shaman" }) do names[#names + 1] = "class-" .. c end
	for _, n in ipairs(names) do
		local f = io.open("Pathwise/Media/" .. n .. ".tga", "rb")
		ok(f, n .. ".tga") if f then f:close() end
	end
end)

test("route maps: the route's path across its zone, evenly spaced, from the first place to the last", function()
	local stub, ns = start()
	local r = ns.Engine.routes["forever/alliance/02-westfall"]
	local path = ns.Hub.RoutePath(r, 20)
	ok(path and #path == 20, "twenty points")
	for _, p in ipairs(path) do ok(p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1, "on the map") end
	local first
	for _, step in ipairs(r.steps) do
		for _, g in ipairs(step) do if not first and type(g.at) == "table" and g.at[1] == r.map then first = g.at end end
	end
	near(path[1][1], first[2] / 100, 1e-9, "starts at the first place")
	eq(ns.Hub.RoutePath({ map = 1, steps = {} }, 10), nil, "no places: no path")
	eq(ns.Hub.MapArt(1436), nil, "no map art in the test client")
end)

---------------------------------------------------------------------------
-- Settings: a window of its own
---------------------------------------------------------------------------

test("settings: its own window, not beside the guide; dragged, kept, pinned; the other panels stay beside the guide", function()
	local stub, ns = start()
	UISpecialFrames = UISpecialFrames or {}
	ns.Fire("SHOW_SETTINGS")
	local p = _G.PathwisePanel
	ok(p.shown, "open")
	eq(p.points[1][1], "CENTER", "mid-screen, not beside the guide")
	eq(p.points[1][2], UIParent)
	ok(ns.Panels.IsWindow("settings") and ns.Panels.IsWindow("about"), "Settings and its pages")
	ok(not ns.Panels.IsWindow("skip"), "not Skip")
	ok(p.pin.shown, "a pin")
	p.scripts.OnDragStart(p)
	ok(rawget(p, "moving"), "dragged")
	p.points = { { "TOPLEFT", UIParent, "TOPLEFT", 120, -80 } }
	p.scripts.OnDragStop(p)
	local saved = ns.Get("settings.point")
	eq(saved and saved[1], "TOPLEFT", "its place is kept")
	ns.Panels.Close()
	ns.Fire("SHOW_SETTINGS")
	eq(p.points[1][1], "TOPLEFT", "and it opens there again")
	eq(p.points[1][4], 120)
	ns.Set("settings.locked", true)
	p.moving = false
	p.scripts.OnDragStart(p)
	ok(not rawget(p, "moving"), "pinned: it stays")
	ns.Panels.Close()
	ns.Fire("GUIDE_SKIP")
	ok(not p.pin.shown, "Skip has no pin")
	ok(p.points[1][1] ~= "TOPLEFT" or p.points[1][4] ~= 120, "and opens beside the guide, not where Settings was")
end)
