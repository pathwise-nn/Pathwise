-- Pathwise Encounters on its own, and beside Pathwise UI: no clashes, its
-- shared files the same as Pathwise UI's, one accent.
local h = ...
local test, eq, ok, fresh, both = h.test, h.eq, h.ok, h.fresh, h.both

local function read(path)
	local f = assert(io.open(path, "rb"), path)
	local t = f:read("*a")
	f:close()
	return t
end

test("split: Pathwise Encounters works on its own, with its own options and minimap button", function()
	local stub, ns = fresh()
	ok(_G.PathwiseUI == nil, "no Pathwise UI loaded")
	eq(_G.PathwiseEncounters, ns)
	eq(ns.NAME, "Pathwise Encounters")
	SlashCmdList.PATHWISEENCOUNTERS("")
	ok(_G.PathwiseEncountersConfig and _G.PathwiseEncountersConfig.shown, "/pwenc opens its own options")
	eq(ns.Config.Current() or ns.Config.CATEGORIES[1].key, "encounters", "the Encounters page first")
	ok(_G.PathwiseEncountersMinimapButton, "its own minimap button")
	ok(type(PathwiseEncountersSettings) == "table" and type(PathwiseEncountersCharSettings) == "table", "its own saved settings")
	ok(PathwiseUISettings == nil, "nothing written for Pathwise UI")
	ok(next(ns.UnknownEvents()) == nil, "every event it listens to is one Forever has")
end)

test("split: Pathwise Encounters' shared files are Pathwise UI's, copied unchanged (npm run kit)", function()
	local kit = { "Core.lua", "Theme.lua", "Anim.lua", "Widgets.lua", "Movers.lua", "Options.lua", "Minimap.lua" }
	for _, name in ipairs(kit) do
		local copy = read("Pathwise_Encounters/Kit/" .. name)
		local body = copy:gsub("^%-%- COPIED from [^\n]*\n%-%- Edit [^\n]*\n", "", 1)
		ok(body ~= copy, name .. ": has the COPIED header")
		ok(body == read("PathwiseUI/" .. name), name .. " differs from PathwiseUI/" .. name .. ": run npm run kit")
	end
	local toc = read("Pathwise_Encounters/Pathwise_Encounters.toc")
	ok(toc:find("## OptionalDeps: Pathwise, PathwiseUI, Pathwise_Heal", 1, true), "works on its own")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line ~= "" then
			ok(io.open("Pathwise_Encounters/" .. line:gsub("\\", "/")), "Pathwise_Encounters.toc lists a missing file: " .. line)
		end
	end
	for _, m in ipairs({ "icon.tga", "disc.tga", "thumb.tga", "Fonts/Inter-Regular.ttf" }) do
		ok(read("Pathwise_Encounters/Media/" .. m) == read("PathwiseUI/Media/" .. m), "Media/" .. m .. " copied")
	end
end)

test("split: the Lua files are all in the TOC", function()
	local listed = {}
	for line in read("Pathwise_Encounters/Pathwise_Encounters.toc"):gmatch("[^\r\n]+") do
		if line:match("%.lua$") then listed[line:gsub("\\", "/")] = true end
	end
	local cmd = package.config:sub(1, 1) == "\\" and 'dir /s /b "Pathwise_Encounters\\*.lua" 2>nul' or 'find Pathwise_Encounters -name "*.lua"'
	local p = io.popen(cmd)
	local n = 0
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):match("Pathwise_Encounters/(.+%.lua)$")
		if rel then n = n + 1 ok(listed[rel], "not in the TOC: " .. rel) end
	end
	p:close()
	ok(n > 0, "found its files")
end)

test("split: beside Pathwise UI: two addons, one accent, no clashes", function()
	local stub, ui, enc = both()
	ok(_G.PathwiseUI == ui and _G.PathwiseEncounters == enc and ui ~= enc, "each its own table")
	ok(PathwiseUISettings ~= PathwiseEncountersSettings, "each its own settings")
	SlashCmdList.PATHWISEUI("")
	SlashCmdList.PATHWISEENCOUNTERS("")
	ok(_G.PathwiseUIConfig.shown and _G.PathwiseEncountersConfig.shown, "each its own window")
	ui.Set("look.accentMode", "custom")
	ui.Set("look.accentColor", "#FF8800")
	eq(enc.Get("look.accentColor"), "#FF8800", "Pathwise Encounters follows Pathwise UI's accent")
	enc.Set("look.accentColor", "#22CC88")
	eq(ui.Get("look.accentColor"), "#22CC88", "and the other way")
end)

test("split: beside Pathwise UI: one theme", function()
	local stub, ui, enc = both()
	ui.Theme.UseScheme("lavender")
	eq(enc.Get("look.scheme"), "lavender", "Pathwise Encounters follows Pathwise UI's theme")
	enc.Theme.UseScheme("emerald")
	eq(ui.Get("look.scheme"), "emerald", "and the other way")
	eq(ui.Theme.ToHex(ui.Theme.Color("accent")), "#5FE0A6")
end)
