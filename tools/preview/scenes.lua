-- The preview's scenes: one character at one moment, drawn in each style.
-- An Alliance warrior, level 14, at Sentinel Hill in Westfall on the real
-- converted route, following Tailoring beside it, with Tailoring, Enchanting
-- and Cooking learned and a session's worth of XP.
local stub, render, scene = ...

local function setup()
	local p = stub.player
	p.race, p.raceID, p.class, p.faction, p.level = "Human", 1, "WARRIOR", "Alliance", 14
	-- Westfall, about 3,000 yards across; Stormwind and Elwynn beside it.
	stub.maps[1436] = { inst = 0, name = "Westfall", n0 = 3000, ny = -30, w0 = 4000, wx = -30 }
	stub.maps[1453] = { inst = 0, name = "Stormwind City", n0 = 9000, ny = -10, w0 = 3000, wx = -10 }
	stub.maps[1429] = { inst = 0, name = "Elwynn Forest", n0 = 6500, ny = -30, w0 = 3500, wx = -30 }
	stub.moveTo(1436, 54.8, 49.6)
	stub.skills[197] = { 48, 75 } -- Tailoring
	stub.skills[333] = { 41, 75 } -- Enchanting
	stub.skills[185] = { 22, 75 } -- Cooking
	stub.xp = 2410
	UnitXP = function() return stub.xp end
	UnitXPMax = function() return 9000 end
	GetXPExhaustion = function() return 0 end
	-- A minimap in the top-right corner, for the minimap button to sit on.
	Minimap:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -28, -28)
	render.Skip(GameTooltip)
end

local function onRoute(ns, id, home)
	local E = ns.Engine
	id = id or "forever/alliance/02-westfall"
	E.SetRoute(id)
	-- The step where you make the zone's inn your home.
	local r = E.Route()
	local at
	for s, step in ipairs(r.steps) do
		for _, g in ipairs(step) do
			if g[1] == "bind" and tostring(g[2]):find(home or "Sentinel") then at = at or s end
		end
	end
	if at then E.StartAt(id, at) end
	ns.Set("professions.detour", "craft")
	E.SetSide("forever/professions/tailoring")
	-- Twenty minutes in: 3,170 XP since login.
	stub.now = 1200
	stub.xp = 5580
	stub.fire("PLAYER_XP_UPDATE")
	E.Update()
	-- Face a little left of the waypoint, so the compass shows it to the right.
	local t = ns.Nav.Target()
	if t then
		local _, pn, pw = ns.Compat.PlayerWorldPosition()
		if pn and t.north then
			local _, _, bearing = ns.Nav.Direction(pn, pw, 0, t.north, t.west)
			stub.player.facing = bearing + 0.35
		end
	end
	stub.advance(0.4)
end

-- A Horde character instead: an Undead mage at Brill in Tirisfal Glades.
local function horde()
	local p = stub.player
	p.race, p.raceID, p.class, p.faction, p.level = "Scourge", 5, "MAGE", "Horde", 9
	stub.moveTo(1420, 59.8, 51.6)
end

-- Settings, scrolled down to its theme tiles.
local function settingsAtThemes(ns)
	ns.Fire("SHOW_SETTINGS")
	for _, f in ipairs(stub.frames) do
		if rawget(f, "tiles") and f.shown then
			local host = f.parent
			local scroll = rawget(host, "scrollParent")
			local top, ftop = host:GetTop(), f:GetTop()
			if scroll and top and ftop then scroll:SetVerticalScroll(math.max(0, top - ftop - 60)) end
		end
	end
end

-- Bags and Gear: a few items to show (as the Bags tests have them).
-- Pathwise Insights: a sample of what a few hours' play leaves in its log
-- (made-up numbers, for the picture only).
local function insightsLog()
	local E, W = "forever/alliance/human/01-elwynn-forest", "forever/alliance/02-westfall"
	local function step(r, s, t, xp, how) return { r = r, s = s, t = t, xp = xp, d = 0, lvl = 10, how = how or "done" } end
	PathwiseInsightsLog = {
		schema = 1, since = 0, played = 20520, xp = 41800, deaths = 3,
		steps = { step(E, 12, 720, 1400), step(E, 27, 840, 2100), step(E, 31, 610, 1600), step(E, 33, 90, 0, "skip"),
			step(W, 9, 1260, 3100), step(W, 14, 980, 2700), step(W, 16, 60, 0, "skip") },
		routes = { [E] = { t = 10920, xp = 21600, d = 1, steps = 38, skips = 2, done = true },
			[W] = { t = 9600, xp = 20200, d = 2, steps = 21, skips = 1 } },
		zones = { [1429] = { t = 10200, xp = 20900, d = 1, lvl = 1 }, [1436] = { t = 9100, xp = 19800, d = 2, lvl = 11 },
			[1453] = { t = 1220, xp = 1100, d = 0, lvl = 10 } },
		levels = { [14] = { t = 1500, xp = 2410, d = 0 }, [13] = { t = 2400, xp = 8000, d = 1 }, [12] = { t = 2100, xp = 7200, d = 1 },
			[11] = { t = 1900, xp = 6500, d = 0 }, [10] = { t = 1700, xp = 5800, d = 1 } },
		skills = { [197] = { from = 1, to = 48, ups = 47 }, [333] = { from = 1, to = 41, ups = 40 } },
	}
end

local function bagItems()
	local items = {
		[201] = { "Broken Fang", 0, 5, 3, 12 }, [202] = { "Cracked Bone", 0, 5, 7, 15 }, [203] = { "Ghoul Rib", 1, 5, 0, 12 },
		[204] = { "Linen Cloth", 1, 5, 1, 7 }, [205] = { "Dull Pebble", 0, 1, 0, 15 }, [206] = { "Lucky Charm", 0, 5, 30, 15 },
	}
	for id, d in pairs(items) do stub.itemInfo[id] = d end
	stub.bags[0] = {
		{ itemID = 201, quality = 0, stackCount = 3 }, { itemID = 202, quality = 0 }, { itemID = 203, quality = 1 },
		{ itemID = 204, quality = 1, stackCount = 20 }, { itemID = 205, quality = 0 }, { itemID = 206, quality = 0 },
	}
end

return {
	setup = setup,
	-- Other Pathwise addons a scene loads with Pathwise.
	addons = { bags = { "Pathwise_Gear", "Pathwise_Bags" }, gear = { "Pathwise_Gear" }, insights = { "Pathwise_Insights" }, ["insights-end"] = { "Pathwise_Insights" } },
	before = { ["hub-horde"] = horde, ["tracker-horde"] = horde, bags = bagItems, insights = insightsLog, ["insights-end"] = insightsLog },
	scenes = {
		hub = function(ns)
			onRoute(ns)
			ns.Fire("TOGGLE_HUB", true)
		end,
		["hub-wide"] = function(ns)
			onRoute(ns)
			ns.Set("hub.width", 1520) ns.Set("hub.height", 640)
			ns.Fire("TOGGLE_HUB", true)
		end,
		["hub-narrow"] = function(ns)
			onRoute(ns)
			ns.Set("hub.width", 760) ns.Set("hub.height", 820)
			ns.Fire("TOGGLE_HUB", true)
		end,
		["hub-horde"] = function(ns)
			onRoute(ns, "forever/horde/undead/01-tirisfal-glades", "Brill")
			ns.Fire("TOGGLE_HUB", true)
		end,
		["tracker-horde"] = function(ns)
			onRoute(ns, "forever/horde/undead/01-tirisfal-glades", "Brill")
		end,
		["hub-class"] = function(ns)
			onRoute(ns)
			ns.Set("hub.tab", "Class")
			ns.Fire("TOGGLE_HUB", true)
		end,
		["hub-prof"] = function(ns)
			onRoute(ns)
			ns.Set("hub.tab", "Professions")
			ns.Fire("TOGGLE_HUB", true)
		end,
		tracker = function(ns)
			onRoute(ns)
		end,
		window = function(ns)
			onRoute(ns)
			ns.Set("guide.style", "window")
		end,
		minimal = function(ns)
			onRoute(ns)
			ns.Set("guide.style", "minimal")
		end,
		settings = function(ns)
			onRoute(ns)
			ns.Fire("SHOW_SETTINGS")
		end,
		["settings-themes"] = function(ns)
			onRoute(ns)
			settingsAtThemes(ns)
		end,
		routebook = function(ns)
			onRoute(ns)
			ns.Fire("SHOW_ZONES")
		end,
		["routebook-page"] = function(ns)
			onRoute(ns)
			ns.RouteBookWindow.OpenRoute(ns.Engine.Route())
		end,
		recipebook = function(ns)
			onRoute(ns)
			ns.Panels.OpenRecipeBook(nil)
		end,
		professions = function(ns)
			onRoute(ns)
			ns.Fire("SHOW_PROFESSIONS")
		end,
		profession = function(ns)
			onRoute(ns)
			ns.Panels.OpenProfession("tailoring")
		end,
		dungeons = function(ns)
			onRoute(ns)
			ns.Fire("SHOW_DUNGEONS")
		end,
		skip = function(ns)
			onRoute(ns)
			ns.Fire("GUIDE_SKIP")
		end,
		bags = function(ns)
			onRoute(ns)
			ToggleBackpack()
		end,
		gear = function(ns)
			onRoute(ns)
			ns.Panels.Open("gear")
		end,
		insights = function(ns)
			onRoute(ns)
			ns.Panels.Open("insights")
		end,
		-- The same page scrolled to its end (the panel's scroll frame).
		["insights-end"] = function(ns)
			onRoute(ns)
			ns.Panels.Open("insights")
			for _, f in ipairs(stub.frames) do
				local wheel = f.kind == "ScrollFrame" and f.scripts.OnMouseWheel
				local child = rawget(f, "scrollChild")
				if wheel and child and f.parent and rawget(f.parent, "pin") then wheel(f, -100) end
			end
		end,
	},
	order = { "hub", "hub-horde", "hub-class", "hub-prof", "hub-wide", "hub-narrow", "tracker", "tracker-horde", "window", "minimal",
		"settings", "settings-themes", "routebook", "routebook-page", "recipebook", "professions", "profession", "dungeons", "skip", "bags", "gear", "insights", "insights-end" },
}
