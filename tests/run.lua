-- Pathwise tests: lua5.1 tests/run.lua (from the repository root).
-- Each test gets a fresh client stub and a fresh copy of the addon.

local ROOT = "."
local results = { pass = 0, fail = 0 }
local tests = {}

local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function eq(a, b, msg)
	if a ~= b then error(("%s: expected %s, got %s"):format(msg or "value", tostring(b), tostring(a)), 2) end
end
local function near(a, b, eps, msg)
	if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
		error(("%s: expected ~%s, got %s"):format(msg or "value", tostring(b), tostring(a)), 2)
	end
end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

local function fresh()
	for k in pairs(package.loaded) do if k:match("^tests") then package.loaded[k] = nil end end
	PathwiseSettings, PathwiseCharSettings, Pathwise, SLASH_PATHWISE1 = nil, nil, nil, nil
	local stub = dofile(ROOT .. "/tests/stub.lua")
	local ns = stub.load(ROOT)
	return stub, ns
end

local function lastPrint(stub) return stub.printed[#stub.printed] or "" end

---------------------------------------------------------------------------

test("loads every file in the TOC and registers /pw and /pathwise", function()
	local stub, ns = fresh()
	stub.login()
	eq(SLASH_PATHWISE1, "/pw")
	eq(SLASH_PATHWISE2, "/pathwise")
	ok(type(SlashCmdList.PATHWISE) == "function", "slash handler")
	ok(ns.Theme and ns.Nav and ns.Guide and ns.Compat, "modules")
	eq(ns.VERSION, "0.1.0-test")
end)

test("the TOC lists every Lua file in the addon folder", function()
	local stub = fresh()
	local listed = {}
	for _, f in ipairs(stub.files) do listed[f] = true end
	local p = io.popen('dir /s /b "Pathwise\\*.lua" 2>nul || find Pathwise -name "*.lua"')
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):match("Pathwise/(.+%.lua)$")
		if rel then ok(listed[rel], "not in the TOC: " .. rel) end
	end
	p:close()
end)

test("settings: defaults, saved values, defaults not stored, change message", function()
	local stub, ns = fresh()
	stub.login()
	eq(ns.Get("guide.compact"), false, "default")
	local seen
	ns.On("SETTING_CHANGED", function(path, v) seen = { path, v } end)
	ns.Set("guide.compact", true)
	eq(PathwiseSettings.guide.compact, true, "stored")
	eq(seen[1], "guide.compact")
	eq(seen[2], true)
	ns.Set("guide.compact", false)
	eq(PathwiseSettings.guide.compact, nil, "a default is not stored")
	eq(ns.Get("guide.compact"), false)
end)

test("settings from another layout are cleared, not misread", function()
	local stub = dofile(ROOT .. "/tests/stub.lua")
	PathwiseSettings = { schema = 99, guide = { compact = "yes" } }
	local ns = stub.load(ROOT)
	stub.login()
	eq(PathwiseSettings.schema, 1)
	eq(ns.Get("guide.compact"), false)
end)

test("Nav.Direction: distance and rotation (0 ahead, CCW positive)", function()
	local _, ns = fresh()
	local D = ns.Nav.Direction
	local dist, rot = D(0, 0, 0, 30, 40) -- 30 north, 40 west, facing north
	near(dist, 50, 1e-9, "distance")
	near(rot, math.atan2(40, 30), 1e-9, "rotation")
	local _, ahead = D(0, 0, 0, 10, 0)
	near(ahead, 0, 1e-9, "north while facing north is straight ahead")
	local _, left = D(0, 0, 0, 0, 10)
	near(left, math.pi / 2, 1e-9, "west while facing north is to the left")
	local _, right = D(0, 0, math.pi / 2, 10, 0)
	near(right, -math.pi / 2, 1e-9, "north while facing west is to the right")
	local _, behind = D(0, 0, 0, -10, 0)
	near(math.abs(behind), math.pi, 1e-9, "south while facing north is behind")
end)

test("Nav.Sample: travel, arrived, far, instance, taxi, none", function()
	local stub, ns = fresh()
	stub.login()
	local Nav = ns.Nav
	Nav.Clear() -- the guide sets its own waypoint at login
	eq(Nav.Sample(), "none")
	Nav.SetTarget(1420, 50, 40, "Here") -- 10 map units north = 200 yd
	local state, dist = Nav.Sample()
	eq(state, "travel")
	near(dist, 200, 1e-6, "yards")
	stub.player.y = 40.2
	eq((Nav.Sample()), "arrived")
	stub.player.instance = true
	eq((Nav.Sample()), "instance")
	stub.player.instance, stub.player.taxi = false, true
	eq((Nav.Sample()), "taxi")
	stub.player.taxi = false
	Nav.SetTarget(1411, 50, 50, "Elsewhere")
	eq((Nav.Sample()), "far")
end)

test("arrow: shows with a waypoint, hides in instances, eases toward the bearing", function()
	local stub, ns = fresh()
	stub.login()
	ns.Nav.SetTarget(1420, 40, 50, "West") -- due west of the player
	local arrow = _G.PathwiseArrow
	ok(arrow and arrow.shown, "arrow shown")
	stub.advance(1)
	local dart = stub.find("\\arrow$")
	ok(dart, "dart texture")
	near(dart.rotation, math.pi / 2, 0.01, "points left (west) when facing north")
	stub.player.instance = true
	stub.advance(0.2)
	eq(arrow.shown, false, "hidden in an instance")
	ns.Nav.Clear()
	eq(arrow.shown, false)
end)

test("arrow turns amber when the target is behind", function()
	local stub, ns = fresh()
	stub.login()
	ns.Nav.SetTarget(1420, 50, 60, "South")
	stub.advance(0.3)
	local dart = stub.find("\\arrow$")
	local warning = ns.Theme.COLORS.warning
	near(dart.vertex[1], warning[1], 1e-6, "red channel")
	near(dart.vertex[3], warning[3], 1e-6, "blue channel")
end)

test("FormatYards", function()
	local _, ns = fresh()
	eq(ns.Nav.FormatYards(41.6), "42 yd")
	eq(ns.Nav.FormatYards(999.4), "999 yd")
	eq(ns.Nav.FormatYards(1240.2), "1,240 yd")
	eq(ns.Nav.FormatYards(123456), "123,456 yd")
end)

test("the arrow's distance counts down as the player walks", function()
	local stub, ns = fresh()
	stub.login()
	ns.Nav.SetTarget(1420, 50, 10, "North") -- 40 map units = 800 yd north
	stub.advance(0.2)
	local dist = _G.PathwiseArrow
	local text
	for _, f in ipairs(stub.frames) do
		if f.parent == dist and rawget(f, "text") and tostring(f.text):match("yd$") then text = f end
	end
	ok(text, "distance text")
	eq(text.text, "800 yd")
	stub.player.y = 45 -- walked 100 yd north
	stub.advance(0.2)
	eq(text.text, "700 yd")
end)

test("/pw arrow scale sets the arrow's size and is remembered", function()
	local stub, ns = fresh()
	stub.login()
	SlashCmdList.PATHWISE("way 50 40")
	SlashCmdList.PATHWISE("arrow scale 150")
	eq(ns.Get("arrow.scale"), 1.5)
	eq(_G.PathwiseArrow.scale, 1.5, "applied to the frame")
	eq(PathwiseSettings.arrow.scale, 1.5, "saved")
	SlashCmdList.PATHWISE("arrow scale 300")
	ok(lastPrint(stub):find("usage"), "out of range explains")
	eq(ns.Get("arrow.scale"), 1.5, "unchanged")
	SlashCmdList.PATHWISE("arrow scale 100")
	eq(PathwiseSettings.arrow.scale, nil, "back to the default is not stored")
end)

test("the arrow's text has a shadow", function()
	local stub, ns = fresh()
	stub.login()
	SlashCmdList.PATHWISE("way 50 40")
	local shadowed = 0
	for _, f in ipairs(stub.frames) do
		if f.parent == _G.PathwiseArrow and f.kind == "FontString" and rawget(f, "shadow") then shadowed = shadowed + 1 end
	end
	eq(shadowed, 2, "distance and title")
end)

test("/pw where and /pw debug print positions", function()
	local stub = fresh()
	stub.login()
	SlashCmdList.PATHWISE("where")
	ok(lastPrint(stub):find("50.0, 50.0 on Tirisfal Glades"), lastPrint(stub))
	SlashCmdList.PATHWISE("way 50 40")
	SlashCmdList.PATHWISE("debug")
	local found = false
	for _, m in ipairs(stub.printed) do if m:find("state travel, distance 200.0 yd") then found = true end end
	ok(found, "the distance line")
end)

test("/pw way sets a waypoint on the current map; bad input explains", function()
	local stub, ns = fresh()
	stub.login()
	SlashCmdList.PATHWISE("way 45.2 61.8 Inn")
	local t = ns.Nav.Target()
	ok(t, "target")
	eq(t.map, 1420)
	near(t.x, 45.2, 1e-9)
	eq(t.title, "Inn")
	SlashCmdList.PATHWISE("way 120 5")
	ok(lastPrint(stub):find("usage"), "usage on a bad coordinate")
	SlashCmdList.PATHWISE("way clear")
	eq(ns.Nav.Target(), nil)
end)

test("guide window: empty state, sample step, compact mode keeps the view", function()
	local stub, ns = fresh()
	-- A character no route is for (every playable race has one now): the empty state.
	stub.player.raceID, stub.player.race, stub.player.faction = 99, "Nobody", "Neutral"
	stub.login()
	local f = _G.PathwiseGuide
	ok(f and f.shown, "guide window shown at login")
	local emptyH = f.h
	ok(emptyH > 0, "has a height")
	SlashCmdList.PATHWISE("demo")
	local view = ns.Guide.View()
	ok(view and view.title == "The Mindless Ones", "sample view")
	ok(f.h > emptyH, "full layout grows with the step")
	local fullH = f.h
	SlashCmdList.PATHWISE("compact")
	eq(ns.Get("guide.compact"), true)
	ok(f.h < fullH, "compact is shorter")
	eq(ns.Guide.View(), view, "same view in compact mode")
	SlashCmdList.PATHWISE("compact")
	eq(f.h, fullH, "back to the same full height")
end)

test("guide window toggles with /pw and remembers it", function()
	local stub, ns = fresh()
	stub.login()
	SlashCmdList.PATHWISE("")
	eq(ns.Get("guide.shown"), false)
	eq(_G.PathwiseGuide.shown, false)
	SlashCmdList.PATHWISE("")
	eq(_G.PathwiseGuide.shown, true)
end)

test("no button prints 'not built yet' any more", function()
	local stub, ns = fresh()
	stub.login()
	for _, msg in ipairs({ "REPORT_STEP", "DETOUR_GO", "DETOUR_SKIP", "GUIDE_SKIP", "SHOW_ZONES", "SHOW_SETTINGS", "SHOW_ABOUT", "SHOW_PROFESSIONS" }) do
		ns.Fire(msg)
		for _, m in ipairs(stub.printed) do ok(not m:find("not built yet"), msg .. ": " .. m) end
	end
end)

test("opacity setting re-tints the window ground", function()
	local stub, ns = fresh()
	stub.login()
	SlashCmdList.PATHWISE("opacity 60")
	near(_G.PathwiseGuide.pwGround.color[4], 0.6, 1e-9, "alpha")
end)

-- WCAG contrast of the theme's text on its grounds.
local function lum(c)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
local function contrast(a, b)
	local la, lb = lum(a), lum(b)
	if la < lb then la, lb = lb, la end
	return (la + 0.05) / (lb + 0.05)
end

test("theme text is legible on every ground (7:1 primary, 4.5:1 the rest)", function()
	local _, ns = fresh()
	local C = ns.Theme.COLORS
	for _, ground in ipairs({ "bg", "bg2", "hover" }) do
		ok(contrast(C.text, C[ground]) >= 7, "text on " .. ground)
		for _, role in ipairs({ "text2", "accent", "success", "warning" }) do
			ok(contrast(C[role], C[ground]) >= 4.5, role .. " on " .. ground .. ": " .. contrast(C[role], C[ground]))
		end
	end
	ok(contrast(C.muted, C.bg) >= 4.5, "muted on bg")
	ok(contrast(C.muted, C.bg2) >= 4.5, "muted on bg2: " .. contrast(C.muted, C.bg2))
end)

test("every texture the addon names exists", function()
	local names = {}
	local p = io.popen('dir /s /b "Pathwise\\*.lua" 2>nul || find Pathwise -name "*.lua"')
	for line in p:lines() do
		local src = assert(io.open(line)):read("*a")
		for n in src:gmatch('MEDIA %.%. "([%w%-]+)"') do names[n] = true end
		for n in src:gmatch('IconButton%([^,]+,%s*"([%w%-]+)"') do names["glyph-" .. n] = true end
	end
	p:close()
	names["glyph-"] = nil -- the prefix the glyph helper builds names from
	names["glyph-collapse"], names["glyph-expand"] = true, true
	for n in pairs(names) do
		local f = io.open("Pathwise/Media/" .. n .. ".tga", "rb")
		ok(f, "missing Pathwise/Media/" .. n .. ".tga")
		if f then f:close() end
	end
end)

-- The guide engine, the data and the panels.
assert(loadfile(ROOT .. "/tests/guide.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })
assert(loadfile(ROOT .. "/tests/gear.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })

---------------------------------------------------------------------------

for _, t in ipairs(tests) do
	local good, err = pcall(t.fn)
	if good then
		results.pass = results.pass + 1
		print("ok    " .. t.name)
	else
		results.fail = results.fail + 1
		print("FAIL  " .. t.name .. "\n      " .. tostring(err))
	end
end
print(("\n%d passed, %d failed"):format(results.pass, results.fail))
os.exit(results.fail == 0 and 0 or 1)
