-- Pathwise Loot on its own, and beside Pathwise UI: no clashes, its
-- shared files the same as Pathwise UI's, one accent.
local h = ...
local test, eq, ok, fresh, both = h.test, h.eq, h.ok, h.fresh, h.both

local function read(path)
	local f = assert(io.open(path, "rb"), path)
	local t = f:read("*a")
	f:close()
	return t
end

test("split: Pathwise Loot works on its own, with its own options and minimap button", function()
	local stub, ns = fresh()
	ok(_G.PathwiseUI == nil, "no Pathwise UI loaded")
	eq(_G.PathwiseLoot, ns)
	eq(ns.NAME, "Pathwise Loot")
	SlashCmdList.PATHWISELOOT("")
	ok(_G.PathwiseLootBrowser and _G.PathwiseLootBrowser.shown, "/pwloot opens the loot browser")
	ok(not _G.PathwiseLootConfig or not _G.PathwiseLootConfig.shown, "not the options")
	SlashCmdList.PATHWISELOOT("options")
	ok(_G.PathwiseLootConfig and _G.PathwiseLootConfig.shown, "/pwloot options opens its own options")
	eq(ns.Config.Current() or ns.Config.CATEGORIES[1].key, "loot", "the Loot page first")
	ok(_G.PathwiseLootMinimapButton, "its own minimap button")
	ok(type(PathwiseLootSettings) == "table" and type(PathwiseLootCharSettings) == "table", "its own saved settings")
	ok(PathwiseUISettings == nil, "nothing written for Pathwise UI")
	ok(next(ns.UnknownEvents()) == nil, "every event it listens to is one Forever has")
end)

test("split: Pathwise Loot's shared files are Pathwise UI's, copied unchanged (npm run kit)", function()
	local kit = { "Core.lua", "Theme.lua", "Anim.lua", "Widgets.lua", "Movers.lua", "Options.lua", "Minimap.lua" }
	for _, name in ipairs(kit) do
		local copy = read("Pathwise_Loot/Kit/" .. name)
		local body = copy:gsub("^%-%- COPIED from [^\n]*\n%-%- Edit [^\n]*\n", "", 1)
		ok(body ~= copy, name .. ": has the COPIED header")
		ok(body == read("PathwiseUI/" .. name), name .. " differs from PathwiseUI/" .. name .. ": run npm run kit")
	end
	local toc = read("Pathwise_Loot/Pathwise_Loot.toc")
	ok(toc:find("## OptionalDeps: Pathwise, PathwiseUI, Pathwise_Gear", 1, true), "works on its own")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line ~= "" then
			ok(io.open("Pathwise_Loot/" .. line:gsub("\\", "/")), "Pathwise_Loot.toc lists a missing file: " .. line)
		end
	end
	for _, m in ipairs({ "icon.tga", "disc.tga", "thumb.tga", "Fonts/Inter-Regular.ttf" }) do
		ok(read("Pathwise_Loot/Media/" .. m) == read("PathwiseUI/Media/" .. m), "Media/" .. m .. " copied")
	end
end)

test("split: the Lua files are all in the TOC", function()
	local listed = {}
	for line in read("Pathwise_Loot/Pathwise_Loot.toc"):gmatch("[^\r\n]+") do
		if line:match("%.lua$") then listed[line:gsub("\\", "/")] = true end
	end
	local cmd = package.config:sub(1, 1) == "\\" and 'dir /s /b "Pathwise_Loot\\*.lua" 2>nul' or 'find Pathwise_Loot -name "*.lua"'
	local p = io.popen(cmd)
	local n = 0
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):match("Pathwise_Loot/(.+%.lua)$")
		if rel then n = n + 1 ok(listed[rel], "not in the TOC: " .. rel) end
	end
	p:close()
	ok(n > 0, "found its files")
end)

test("split: beside Pathwise UI: two addons, one accent, no clashes", function()
	local stub, ui, enc = both()
	ok(_G.PathwiseUI == ui and _G.PathwiseLoot == enc and ui ~= enc, "each its own table")
	ok(PathwiseUISettings ~= PathwiseLootSettings, "each its own settings")
	SlashCmdList.PATHWISEUI("")
	SlashCmdList.PATHWISELOOT("options")
	ok(_G.PathwiseUIConfig.shown and _G.PathwiseLootConfig.shown, "each its own window")
	ok(enc.Theme.Color("accent") ~= nil, "Pathwise Loot has its own theme")
	ui.Set("look.accentMode", "custom")
	ui.Set("look.accentColor", "#FF8800")
	eq(enc.Get("look.accentColor"), "#FF8800", "Pathwise Loot follows Pathwise UI's accent")
	enc.Set("look.accentColor", "#22CC88")
	eq(ui.Get("look.accentColor"), "#22CC88", "and the other way")
end)

test("split: beside Pathwise UI: the dead Adventure Guide button in the tray opens Pathwise Loot", function()
	local stub, ui, loot = both(function(s)
		s.makeTray()
		local b = CreateFrame("Button", "EJMicroButton", MicroMenu)
		function b:IsEnabled() return false end
	end)
	local tray, button = _G.PathwiseUI_Tray, _G.PathwiseUI_TrayLootButton
	ok(button, "Pathwise UI's own button for Pathwise Loot")
	eq(button.parent, tray, "in the tray")
	ok(button.shown and #button.points > 0, "shown, in the row")
	ok(EJMicroButton.parent ~= tray, "the game's dead button left out")
	eq(tray.w, 9 * 28 + 8 * 3, "in the Adventure Guide's place: nine buttons")
	ok(not loot.LootBrowser.IsShown(), "the browser closed")
	button.scripts.OnClick(button, "LeftButton")
	ok(loot.LootBrowser.IsShown(), "a click opens the loot browser")
	button.scripts.OnClick(button, "LeftButton")
	ok(not loot.LootBrowser.IsShown(), "and closes it")
	ok(ui.Tray.Tooltip(button), "its tooltip")
	-- The game turns the Adventure Guide on: its own button back.
	AdventureGuideUtil = { IsAvailable = function() return true end }
	ui.Tray.Build()
	eq(EJMicroButton.parent, tray, "the game's button back in the tray")
	local inTray = false
	for _, e in ipairs(ui.Tray.Buttons("micro")) do if e[1] == button then inTray = true end end
	ok(not inTray, "and the Pathwise Loot button out of the row")
	ok(not button.shown, "and out of sight")
	-- Off again: the Pathwise Loot button back.
	AdventureGuideUtil = nil
	ui.Tray.Build()
	ok(button.shown and button.parent == tray, "the Pathwise Loot button back")
	ok(EJMicroButton.parent == MicroMenu, "the game's button back under its own menu")
end)
