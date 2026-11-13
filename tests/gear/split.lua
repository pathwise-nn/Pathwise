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

test("split: on its own: Best in Slot says it needs Pathwise, and is empty", function()
	local stub, ns = fresh(items)
	ok(not ns.Best.Available(), "no Pathwise data")
	local list, pending = ns.Best.List()
	eq(#list, 0)
	eq(pending, 0)
	eq(ns.Best.IsBest(102), nil)
	eq(ns.Best.Chase({ source = { kind = "drop", id = 1 } }), false)
	local rows
	for _, c in ipairs(ns.Config.CATEGORIES) do if c.key == "best" then rows = c.rows() end end
	ok(rows[2][2]:find("Needs Pathwise: Leveling & Professions"), rows[2][2])
	ns.Config.Show("best")
	ns.Config.Show("gear")
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
