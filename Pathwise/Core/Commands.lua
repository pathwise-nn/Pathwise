-- Pathwise slash commands (/pw, /pathwise). Loaded last: every module exists.

local ADDON, ns = ...
local Nav, Guide = ns.Nav, ns.Guide

ns.Command("help", function()
	ns.Print("commands:")
	for _, c in ipairs(ns.CommandHelp()) do
		ns.Print(("  /pw %s  -  %s"):format(c.name, c.help or ""))
	end
end, "this list")

ns.Command("way", function(args)
	local a = (args or ""):lower()
	if a == "" or a == "clear" or a == "off" then
		Nav.Clear()
		ns.Print("waypoint cleared.")
		return
	end
	-- /pw way 45.2 61.8 [title]   (on the map you are on)
	local x, y, title = args:match("^%s*([%d%.]+)[,%s]+([%d%.]+)%s*(.*)$")
	x, y = tonumber(x), tonumber(y)
	if not (x and y) or x < 0 or x > 100 or y < 0 or y > 100 then
		ns.Print("usage: /pw way <x> <y> [title]   e.g. /pw way 45.2 61.8 Inn")
		return
	end
	local map = ns.Compat.PlayerMapPosition()
	if not map then
		ns.Print("no map position here (inside an instance?).")
		return
	end
	if title == "" then title = ("%.1f, %.1f"):format(x, y) end
	Nav.SetTarget(map, x, y, title)
	ns.Print(("waypoint set: %s on %s."):format(title, ns.Compat.MapName(map) or ("map " .. map)))
end, "set a waypoint on this map: /pw way <x> <y> [title]; /pw way clear")

ns.Command("where", function()
	local C = ns.Compat
	local map, x, y = C.PlayerMapPosition()
	if not map then
		ns.Print("no map position here (inside an instance?).")
		return
	end
	ns.Print(("you are at %.1f, %.1f on %s (map %d)."):format(x, y, C.MapName(map) or "?", map))
end, "your coordinates on this map")

-- What the arrow sees, to tell a position problem from a display one.
ns.Command("debug", function()
	local C = ns.Compat
	local function n(v) return v and ("%.1f"):format(v) or "nil" end
	local map, x, y = C.PlayerMapPosition()
	ns.Print(("player map %s at %s, %s"):format(tostring(map), n(x), n(y)))
	local inst, north, west = C.PlayerWorldPosition()
	ns.Print(("player world inst %s north %s west %s, facing %s"):format(tostring(inst), n(north), n(west), n(C.PlayerFacing())))
	local t = Nav.Target()
	if not t then
		ns.Print("no waypoint set.")
		return
	end
	ns.Print(("target map %s at %s, %s -> world inst %s north %s west %s"):format(tostring(t.map), n(t.x), n(t.y), tostring(t.inst), n(t.north), n(t.west)))
	local state, dist, rot = Nav.Sample()
	ns.Print(("state %s, distance %s yd, rotation %s"):format(tostring(state), n(dist), n(rot)))
end, "what the arrow sees (for bug reports)")

ns.Command("compact", function()
	Guide.SetCompact(not ns.Get("guide.compact"))
end, "switch the guide between full and compact")

ns.Command("opacity", function(args)
	local v = tonumber(args)
	if not v or v < 40 or v > 100 then
		ns.Print("usage: /pw opacity <40-100>   (now " .. math.floor(ns.Get("ui.opacity") * 100 + 0.5) .. ")")
		return
	end
	ns.Set("ui.opacity", v / 100)
end, "window background opacity, 40-100")

ns.Command("scale", function(args)
	local v = tonumber(((args or ""):gsub("%%", "")))
	if not v or v < 50 or v > 150 then
		ns.Print(("usage: /pw scale <50-150>   (now %d%%)"):format(math.floor((ns.Get("ui.scale") or 1) * 100 + 0.5)))
		return
	end
	ns.Set("ui.scale", v / 100)
	ns.Print(("window size %d%%."):format(v))
end, "guide window size, 50-150 (also in Settings)")

ns.Command("arrow", function(args)
	local sub, rest = (args or ""):lower():match("^(%S*)%s*(.-)%s*$")
	if sub == "scale" then
		local v = tonumber((rest:gsub("%%", "")))
		if not v or v < 50 or v > 200 then
			ns.Print(("usage: /pw arrow scale <50-200>   (now %d%%)"):format(math.floor((ns.Get("arrow.scale") or 1) * 100 + 0.5)))
			return
		end
		ns.Set("arrow.scale", v / 100)
		ns.Print(("arrow size %d%%."):format(v))
		return
	end
	ns.Set("arrow.shown", not ns.Get("arrow.shown"))
	ns.Print(ns.Get("arrow.shown") and "arrow on (Shift-drag to move)." or "arrow off.")
end, "show or hide the arrow; /pw arrow scale <50-200> sets its size")

ns.Command("reset", function()
	ns.Set("guide.point", nil)
	ns.Set("arrow.point", nil)
	ns.Print("window positions reset; /reload to apply.")
end, "reset window positions")

-- A labelled sample so the layout can be checked in game before the guide
-- engine exists. Quest names are from the Undead start in Tirisfal Glades.
ns.Command("demo", function()
	if Guide.View() then
		Guide.SetView(nil)
		ns.Print("sample cleared.")
		return
	end
	Guide.SetView({
		route = "Sample · Tirisfal Glades", index = 6, count = 48, progress = 0.12,
		title = "The Mindless Ones",
		text = "Kill Mindless and Wretched Zombies in the fields just north of Deathknell.",
		coords = "30.7, 64.2",
		objectives = {
			{ text = "Mindless Zombie", have = 5, need = 8 },
			{ text = "Wretched Zombie", have = 8, need = 8, done = true },
		},
		detour = { label = "Optional · Tailoring", text = "Train Apprentice Tailoring", sub = "On your way · about 1 min" },
		next = "Turn in The Mindless Ones at Shadow Priest Sarvis",
	})
	ns.Set("guide.shown", true)
	ns.Print("showing a sample step (/pw demo again to clear).")
end, "preview the guide window with a sample step")

ns.Command("about", function()
	ns.Print(("Pathwise %s  ·  Every quest. Every craft. Every level.  ·  created by leight_nn & florp  _nn"):format(ns.VERSION))
	ns.Fire("SHOW_ABOUT")
end, "version and credits")
ns.Command("report", function() ns.Fire("REPORT_STEP") end, "a report of this step to paste into Discord")

ns.Command("settings", function() ns.Fire("SHOW_SETTINGS") end, "open the settings panel")
ns.Command("zones", function() ns.Fire("SHOW_ZONES") end, "zones for your level (and switching routes)")
ns.Command("routes", function() ns.Fire("SHOW_ROUTES") end, "every route for you: leveling, class quests, professions")
ns.Command("prof", function() ns.Fire("SHOW_PROFESSIONS") end, "your professions: skill, best craft, materials")
ns.Command("dungeons", function() ns.Fire("SHOW_DUNGEONS") end, "dungeons and raids for your level, their quests and entrances")
ns.Command("professions", function() ns.Fire("SHOW_PROFESSIONS") end, "same as /pw prof")
ns.Command("skip", function() ns.Fire("GUIDE_SKIP") end, "skip the current quest, or pick one nearby instead")

ns.Command("route", function(args)
	local E = ns.Engine
	if args and args ~= "" then
		for _, r in ipairs(E.Routes()) do
			if r.id == args or r.title:lower() == args:lower() then
				E.SetRoute(r.id)
				ns.Print("route: " .. r.title)
				return
			end
		end
		ns.Print("no route called '" .. args .. "'.")
		return
	end
	local r = E.Route()
	ns.Print("route: " .. (r and (r.title .. " (" .. r.id .. ")") or "none"))
	for _, x in ipairs(E.Routes()) do ns.Print("  " .. x.id .. "  " .. x.title) end
end, "show or choose the route: /pw route <id or title>")

ns.On("GUIDE_BACK", function() ns.Engine.Back() end)
ns.On("GUIDE_NEXT", function() ns.Engine.Next() end)
