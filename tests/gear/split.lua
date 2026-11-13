-- Pathwise Gear without Pathwise: upgrades, tooltips, bag arrows and the
-- best quest reward on their own; its shared files the same as Pathwise
-- UI's; beside Pathwise UI, one accent.
local h = ...
local test, eq, ok, fresh, both = h.test, h.eq, h.ok, h.fresh, h.both

local function read(path)
	local f = assert(io.open(path, "rb"), path)
	local t = f:read("*a")
	f:close()
	return t
end

local INT, STR, STA = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"
local function items(stub)
	stub.player.class = "MAGE"
	stub.itemInfo[101] = { "Worn Cloth Hood", 1, 10, 5, 4, 1, "INVTYPE_HEAD", 5 }
	stub.itemInfo[102] = { "Glyphed Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }
	stub.itemInfo[103] = { "Iron Helm", 2, 18, 40, 4, 4, "INVTYPE_HEAD", 13 }
	stub.itemStats[101] = { [INT] = 2 }
	stub.itemStats[102] = { [INT] = 6, [STA] = 2 }
	stub.itemStats[103] = { [STR] = 8, [STA] = 6 }
	stub.equipped[1] = 101
end

test("split: Pathwise Gear works on its own, with its own options and minimap button", function()
	local stub, ns = fresh(items)
	ok(_G.Pathwise == nil and _G.PathwiseUI == nil, "no Pathwise, no Pathwise UI")
	eq(_G.PathwiseGear, ns)
	eq(ns.NAME, "Pathwise Gear")
	SlashCmdList.PATHWISEGEAR("")
	ok(_G.PathwiseGearConfig and _G.PathwiseGearConfig.shown, "/pwgear opens its own options")
	eq(ns.Config.Current() or ns.Config.CATEGORIES[1].key, "gear", "the Upgrades page first")
	ok(_G.PathwiseGearMinimapButton, "its own minimap button")
	ok(type(PathwiseGearSettings) == "table" and type(PathwiseGearCharSettings) == "table", "its own saved settings")
	ok(PathwiseUISettings == nil and PathwiseSettings == nil, "nothing written for Pathwise or Pathwise UI")
	ok(next(ns.UnknownEvents()) == nil, "every event it listens to is one Forever has")
end)

test("split: on its own: upgrades, the tooltip line, bag arrows and the quest reward", function()
	local stub, ns = fresh(function(s)
		items(s)
		s.bags[0] = { { itemID = 102 }, { itemID = 103 } }
	end)
	local G = ns.Gear
	local up, pct, slot = G.IsUpgrade("item:102")
	ok(up and pct > 0, "the hood is an upgrade")
	eq(slot, "Head")
	eq((G.IsUpgrade("item:103")), false, "plate is not, for a mage")
	local lines = stub.showTooltip("item:102")
	ok(lines[1] and lines[1][2]:find("upgrade · Head"), lines[1] and lines[1][2])
	local b1 = stub.bagButton(1)
	stub.bagButton(2)
	ContainerFrameCombinedBags:UpdateItems()
	local arrow
	for _, f in ipairs(stub.frames) do
		if f.parent == b1 and rawget(f, "texture") and f.texture:find("glyph%-upgrade") then arrow = f end
	end
	ok(arrow and arrow.shown, "a gold arrow on the bag upgrade")
	stub.choices = { 103, 102 }
	stub.fire("QUEST_COMPLETE")
	ok(h.lastPrint(stub):find("take item:102"), h.lastPrint(stub))
	ns.Set("gear.tooltip", false)
	eq(#stub.showTooltip("item:102"), 0, "its own setting")
end)

-- Best in Slot on its own: test entries in Gear's own data, as
-- tools/gear/data.lua writes them (Pathwise's layouts).
local function bisData(ns)
	local G = ns.GearData
	G.npcs[990200] = { "Deathguard Test", nil, nil, "H", { [1420] = { 40, 50 } } }
	G.npcs[990201] = { "Alliance Giver", nil, nil, "A", { [1420] = { 60, 60 } } }
	G.npcs[990202] = { "Test Boss", nil, nil, nil, { [1420] = { 10, 10 } } }
	G.quests[990100] = { "A Hood for You", nil, nil, 0, 0, 1420, { 990200 } }
	G.quests[990101] = { "Alliance Only", nil, nil, 0, 0, 1420, { 990201 } }
	G.quests[990102] = { "Done Already", nil, nil, 0, 0, 1420, { 990200 } }
	G.dungeons[990300] = { name = "Test Keep", levels = { 18, 22 }, entrances = { { 1420, 70.5, 20.25 } } }
	G.gear[102] = { 13, 18, 4, 1, { 990100 } }
	G.gear[109] = { 13, 18, 4, 1, { 990101 } }
	G.gear[110] = { 13, 18, 4, 1, { 990102 } }
	G.gear[104] = { 14, 20, 2, 15, nil, { 990202 }, nil, nil, 990300 }
end

test("split: on its own: Best in Slot from Gear's own data, and the game's map pin", function()
	local pins = {}
	local stub, ns = fresh(function(s)
		items(s)
		s.player.level = 20
		s.itemInfo[109] = { "Scholar's Cowl", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }
		s.itemInfo[110] = { "Ironclad Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }
		s.itemInfo[104] = { "Frost Dagger", 2, 20, 60, 2, 15, "INVTYPE_WEAPON", 14 }
		s.itemStats[109] = { [INT] = 10 }
		s.itemStats[110] = { [INT] = 12 }
		s.itemStats[104] = { [INT] = 3 }
		s.done[990102] = true
		UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
		C_Map.CanSetUserWaypointOnMap = function(map) return map == 1420 end
		C_Map.SetUserWaypoint = function(p) pins[#pins + 1] = p return true end
		C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) pins.tracked = on end }
	end)
	ok(_G.Pathwise == nil, "no Pathwise")
	ok(ns.Best.Available(), "its own data")
	ok(next(ns.GearData.gear) and next(ns.GearData.npcs), "shipped with the addon")
	bisData(ns)
	ns.Best.Clear()
	local list = ns.Best.List()
	local head, hand
	for _, e in ipairs(list) do
		if e.slot == 1 then head = e elseif e.slot == 16 then hand = e end
	end
	ok(head, "a head piece")
	eq(head.id, 102, "the other side's quest and a quest done already are left out")
	eq(ns.Best.SourceText(head.source), "Quest: A Hood for You")
	eq(ns.Best.SourceText(hand.source), "Dungeon: Test Keep (Test Boss)")
	eq(ns.Best.IsBest(102), ns.Gear.Client.Level(), "best for your level")
	-- Chase: the game's own map pin at the giver, then at the dungeon's entrance.
	ok(ns.Best.Chase(head), "a pin at the quest giver")
	eq(pins[1].uiMapID, 1420)
	ok(math.abs(pins[1].x - 0.40) < 1e-9 and math.abs(pins[1].y - 0.50) < 1e-9, "in 0-1 coordinates")
	eq(pins.tracked, true, "and tracked")
	ok(ns.Best.Chase(hand), "a pin at the entrance")
	ok(math.abs(pins[2].x - 0.705) < 1e-9 and math.abs(pins[2].y - 0.2025) < 1e-9)
	-- The page: the list, and how it points.
	local rows
	for _, c in ipairs(ns.Config.CATEGORIES) do if c.key == "best" then rows = c.rows() end end
	local texts = {}
	for _, r in ipairs(rows) do texts[#texts + 1] = tostring(r[2]) end
	local all = table.concat(texts, " | ")
	ok(all:find("Head:  Glyphed Hood", 1, true), all)
	ok(all:find("a pin on your map shows where", 1, true), all)
	ns.Config.Show("best")
	-- A map the game won't pin: no pin, said so.
	C_Map.CanSetUserWaypointOnMap = function() return false end
	eq(ns.Best.Chase(head), false)
	UiMapPoint, C_SuperTrack, C_Map.SetUserWaypoint, C_Map.CanSetUserWaypointOnMap = nil, nil, nil, nil
end)

test("split: Gear's own data is Pathwise's, as tools/gear/data.lua writes it (npm run gear:data)", function()
	local p = io.popen("lua5.1 tools/gear/data.lua --check 2>&1")
	local out = p:read("*a")
	local okExit = p:close()
	ok(out:find("up to date", 1, true), out)
	local f = assert(io.open("Pathwise_Gear/Data/Gear.lua", "rb"))
	local size = f:seek("end")
	f:close()
	ok(size < 1500000, "small enough to load quickly: " .. size .. " bytes")
end)

test("split: Pathwise Gear's shared files are Pathwise UI's, copied unchanged (npm run kit)", function()
	local kit = { "Core.lua", "Theme.lua", "Anim.lua", "Widgets.lua", "Movers.lua", "Options.lua", "Minimap.lua" }
	for _, name in ipairs(kit) do
		local copy = read("Pathwise_Gear/Kit/" .. name)
		local body = copy:gsub("^%-%- COPIED from [^\n]*\n%-%- Edit [^\n]*\n", "", 1)
		ok(body ~= copy, name .. ": has the COPIED header")
		ok(body == read("PathwiseUI/" .. name), name .. " differs from PathwiseUI/" .. name .. ": run npm run kit")
	end
	local toc = read("Pathwise_Gear/Pathwise_Gear.toc")
	ok(toc:find("## OptionalDeps: Pathwise, PathwiseUI", 1, true), "works on its own")
	ok(not toc:find("## Dependencies", 1, true), "needs nothing")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line ~= "" then
			ok(io.open("Pathwise_Gear/" .. line:gsub("\\", "/")), "Pathwise_Gear.toc lists a missing file: " .. line)
		end
	end
	for _, m in ipairs({ "icon.tga", "disc.tga", "glyph-upgrade.tga", "Fonts/Inter-Regular.ttf" }) do
		ok(read("Pathwise_Gear/Media/" .. m) == read("PathwiseUI/Media/" .. m), "Media/" .. m .. " copied")
	end
	ok(read("Pathwise_Gear/Media/glyph-best.tga") == read("Pathwise/Media/glyph-best.tga"), "its own best in slot star")
end)

test("split: the Lua files are all in the TOC", function()
	local listed = {}
	for line in read("Pathwise_Gear/Pathwise_Gear.toc"):gmatch("[^\r\n]+") do
		if line:match("%.lua$") then listed[line:gsub("\\", "/")] = true end
	end
	local cmd = package.config:sub(1, 1) == "\\" and 'dir /s /b "Pathwise_Gear\\*.lua" 2>nul' or 'find Pathwise_Gear -name "*.lua"'
	local p = io.popen(cmd)
	local n = 0
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):match("Pathwise_Gear/(.+%.lua)$")
		if rel then n = n + 1 ok(listed[rel], "not in the TOC: " .. rel) end
	end
	p:close()
	ok(n > 0, "found its files")
end)

test("split: beside Pathwise UI: two addons, one accent, no clashes", function()
	local stub, ui, gear = both(items)
	ok(_G.PathwiseUI == ui and _G.PathwiseGear == gear and ui ~= gear, "each its own table")
	ok(PathwiseUISettings ~= PathwiseGearSettings, "each its own settings")
	SlashCmdList.PATHWISEUI("")
	SlashCmdList.PATHWISEGEAR("")
	ok(_G.PathwiseUIConfig.shown and _G.PathwiseGearConfig.shown, "each its own window")
	ui.Set("look.accentMode", "custom")
	ui.Set("look.accentColor", "#FF8800")
	eq(gear.Get("look.accentColor"), "#FF8800", "Pathwise Gear follows Pathwise UI's accent")
	gear.Set("look.accentColor", "#22CC88")
	eq(ui.Get("look.accentColor"), "#22CC88", "and the other way")
end)
