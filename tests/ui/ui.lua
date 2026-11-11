-- Tests for Pathwise UI: the accent (and sharing it with Pathwise), settings
-- per character or shared, fonts, tooltips, game windows, the options
-- window and the minimap button.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

test("loads on its own, with no Pathwise installed", function()
	local stub, ns = fresh()
	ok(ns.Theme and ns.Config and ns.Tooltip and ns.Fonts and ns.Windows, "every part loaded")
	ok(not ns.Suite(), "no Pathwise needed")
	ok(_G.PathwiseUIMinimapButton and _G.PathwiseUIMinimapButton.shown, "its own minimap button")
	for name in pairs(ns.UnknownEvents()) do ok(false, "an event Forever lacks: " .. name) end
end)

test("accent: your class color by default, Pathwise blue, or one you pick", function()
	local stub, ns = fresh()
	local T = ns.Theme
	near(T.Color("accent")[1], 0.25, 1e-6, "a mage starts in mage blue")
	ns.Set("look.accentMode", "pathwise")
	eq(T.ToHex(T.Color("accent")), "#66D7FF")
	ns.Set("look.accentMode", "custom")
	ns.Set("look.accentColor", "#E8C26A")
	eq(T.ToHex(T.Color("accent")), "#E8C26A")
	ok(T.Color("accentHover")[1] > T.Color("accent")[1], "hover lighter")
	stub.player.class = "ROGUE"
	ns.Set("look.accentMode", "class")
	near(T.Color("accent")[2], 0.96, 1e-6, "a rogue in rogue yellow")
end)

test("accent: things painted in it change at once", function()
	local stub, ns = fresh()
	local T = ns.Theme
	local f = CreateFrame("Frame")
	local line = T.AccentLine(f)
	ns.Set("look.accentMode", "custom")
	ns.Set("look.accentColor", "#FF0000")
	eq(line.color[1], 1)
	eq(line.color[2], 0, "repainted without a reload")
end)

test("accent: one color with Pathwise when both are installed", function()
	local pathwise = { settings = { ["ui.accentMode"] = "pathwise", ["ui.accentColor"] = "#66D7FF" }, listeners = {} }
	local stub, ns = fresh(function()
		Pathwise = { Suite = {
			Get = function(p) return pathwise.settings[p] end,
			Set = function(p, v)
				pathwise.settings[p] = v
				for _, fn in ipairs(pathwise.listeners) do fn(p, v) end
			end,
			On = function(msg, fn) if msg == "SETTING_CHANGED" then table.insert(pathwise.listeners, fn) end end,
			RegisterModule = function(def) pathwise.module = def end,
		} }
	end)
	ok(ns.Suite(), "Pathwise seen")
	eq(pathwise.settings["ui.accentMode"], "class", "Pathwise takes Pathwise UI's class color")
	ok(pathwise.module and pathwise.module.name == "Pathwise UI", "listed in Pathwise's suite")
	-- A change in Pathwise comes back.
	Pathwise.Suite.Set("ui.accentColor", "#7FD98F")
	Pathwise.Suite.Set("ui.accentMode", "custom")
	eq(ns.Get("look.accentMode"), "custom")
	eq(ns.Theme.ToHex(ns.Theme.Color("accent")), "#7FD98F")
	-- Unlinked: each its own.
	ns.Set("look.sharePathwise", false)
	ns.Set("look.accentMode", "pathwise")
	eq(pathwise.settings["ui.accentMode"], "custom", "Pathwise keeps its own")
	Pathwise = nil
end)

test("profile: shared by every character, or this character's own", function()
	local stub, ns = fresh()
	ns.Set("fonts.scale", 1.2)
	ok(PathwiseUISettings.fonts and PathwiseUISettings.fonts.scale == 1.2, "shared by default")
	ns.SetShared(false)
	eq(ns.Get("fonts.scale"), 1.2, "this character starts from the shared settings")
	ns.Set("fonts.scale", 0.9)
	eq(PathwiseUISettings.fonts.scale, 1.2, "the shared ones stay")
	eq(PathwiseUICharSettings.fonts.scale, 0.9)
	ns.SetShared(true)
	eq(ns.Get("fonts.scale"), 1.2)
	ns.Reset()
	eq(ns.Get("fonts.scale"), 1, "back to the defaults")
end)

test("fonts: Inter everywhere at your size, the game's own back when off", function()
	local stub, ns = fresh()
	ok(GameFontNormal.file:find("Inter%-Regular"), GameFontNormal.file)
	ok(GameTooltipHeaderText.file:find("Inter%-SemiBold"), "headers in the semibold cut")
	eq(NumberFontNormal.flags, "OUTLINE", "outlines kept")
	ns.Set("fonts.scale", 1.2)
	near(GameFontNormal.size, 14.4, 1e-6, "your size")
	ns.Set("fonts.pathwise", false)
	ok(GameFontNormal.file:find("FRIZQT"), "the game's own font back")
	eq(GameFontNormal.size, 12, "at its own size")
end)

test("tooltips: a flat ground, borders by quality and class, names in class color", function()
	local stub, ns = fresh()
	local Tip = ns.Tooltip
	GameTooltip.NineSlice = CreateFrame("Frame")
	Tip.Skin(GameTooltip)
	-- The ornate frame faded out, the flat ground drawn.
	local ground
	for _, f in ipairs(stub.frames) do if f.kind == "Texture" and f.parent == GameTooltip and f.color and f.color[1] < 0.1 then ground = f end end
	ok(ground, "a dark flat ground on the tooltip")
	-- The game re-styles the tooltip: Pathwise UI follows.
	SharedTooltip_SetBackdropStyle(GameTooltip)
	-- A player of another class under the mouse.
	local first = CreateFrame("FontString", "GameTooltipTextLeft1")
	GameTooltip.GetName = function() return "GameTooltip" end
	GameTooltip.GetUnit = function() return "Frozen", "mouseover" end
	UnitIsPlayer = function() return true end
	local realClass = UnitClass
	UnitClass = function(u) if u == "mouseover" then return "Rogue", "ROGUE" end return realClass(u) end
	Tip.OnUnit(GameTooltip)
	near(first.textColor[2], 0.96, 1e-6, "the name in rogue yellow")
	UnitClass, UnitIsPlayer = realClass, nil
	ns.Set("tooltip.skin", false)
	ok(not ground.shown, "off: the game's look again")
end)

test("game windows: only modern frames are dressed, and undressed when off", function()
	local stub, ns = fresh(function()
		CharacterFrame = CreateFrame("Frame", "CharacterFrame")
		CharacterFrame.NineSlice = CreateFrame("Frame", nil, CharacterFrame)
		CharacterFrame.Bg = CharacterFrame:CreateTexture()
		CharacterFrame.GetAlpha = nil
		FriendsFrame = CreateFrame("Frame", "FriendsFrame") -- no NineSlice: an older window
	end)
	local Win = ns.Windows
	ok(Win.Dressed()[CharacterFrame], "the character window dressed")
	ok(not Win.Dressed()[FriendsFrame], "an older window left as it is")
	ns.Set("windows.skin", false)
	local d = Win.Dressed()[CharacterFrame]
	ok(not d.ground.shown, "off: the game's own look")
end)

test("game windows wait for the end of combat", function()
	local stub, ns = fresh(function()
		stub.combat = true
		CharacterFrame = CreateFrame("Frame", "CharacterFrame")
		CharacterFrame.NineSlice = CreateFrame("Frame", nil, CharacterFrame)
	end)
	ok(not ns.Windows.Dressed()[CharacterFrame], "not in combat")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	ok(ns.Windows.Dressed()[CharacterFrame], "dressed once combat ends")
end)

test("options window: categories, switches, choices, sliders", function()
	local stub, ns = fresh()
	SlashCmdList.PATHWISEUI("")
	local frame = _G.PathwiseUIConfig
	ok(frame and frame.shown, "/pwui opens it")
	stub.advance(0.3)
	near(frame.alpha, 1, 1e-6, "faded in")
	local texts = stub.texts()
	ok(contains(texts, "Look and accent") and contains(texts, "Colors") and contains(texts, "Coming next"), table.concat(texts, " | "))
	ok(stub.clickLabel("Custom"), "pick Custom")
	eq(ns.Get("look.accentMode"), "custom")
	ns.Config.Show("tooltips")
	ok(stub.clickLabel("Accent"), "tooltip border: accent")
	eq(ns.Get("tooltip.border"), "accent")
	-- A switch: it slides, and the setting follows.
	local sw
	for _, f in ipairs(stub.frames) do if rawget(f, "pwKnob") and f.shown and f.parent.shown and f.parent.label.text == "At the mouse" then sw = f end end
	ok(sw and not sw:IsOn(), "a switch, off")
	sw:Click()
	eq(ns.Get("tooltip.cursor"), true, "on")
	ok(sw:IsOn())
	stub.advance(0.2)
	near(ns.Anim.Get(sw, "on"), 1, 1e-6, "slid all the way")
	ns.Config.Show("fonts")
	ok(contains(stub.texts(), "Pathwise font everywhere"))
	ok(stub.clickLabel("Reload now"))
	eq(stub.reloaded, 1)
	-- Closing fades it out, then hides it.
	ns.Config.Hide()
	ok(frame.shown, "still fading")
	stub.advance(0.3)
	ok(not frame.shown, "closed")
end)

test("colors: a scheme changes everything at once", function()
	local stub, ns = fresh()
	local T = ns.Theme
	local f = CreateFrame("Frame")
	local ground = T.Panel(f, "bg", "border", 1)
	T.UseScheme("rose")
	eq(T.ToHex(T.Color("bg")), "#1C1218", "the ground")
	eq(T.ToHex(T.Color("accent")), "#FF7EB6", "the accent with it")
	eq(ns.Get("look.accentMode"), "pathwise", "the theme's own accent")
	near(ground.color[1], 0x1C / 255, 1e-6, "painted things repainted")
	near(f.pwBorder.color[1], 0x4C / 255, 1e-6, "borders too")
	near(ns.Units.REACTION.hostile[1], 1, 1e-6, "unit frame colors follow the scheme")
	T.UseScheme("pathwise")
	eq(T.ToHex(T.Color("bg")), "#10161E")
	eq(ns.Get("look.accentMode"), "pathwise")
end)

test("colors: any one of them on the wheel, cancel puts it back, right-click resets", function()
	local stub, ns = fresh()
	local T = ns.Theme
	ns.Config.Show("colors")
	local texts = stub.texts()
	ok(contains(texts, "Blossom") and contains(texts, "Window ground") and contains(texts, "Poison debuff"), table.concat(texts, " | "))
	local row
	for _, f in ipairs(stub.frames) do if rawget(f, "swatch") and f.shown and f.label.text == "Window ground" then row = f end end
	ok(row, "a swatch for the window ground")
	row.swatch.scripts.OnClick(row.swatch, "LeftButton")
	ok(ColorPickerFrame.shown, "the color wheel opens")
	stub.pick(1, 0.8, 0.9)
	eq(T.ToHex(T.Color("bg")), "#FFCCE6", "yours, live")
	ok(T.IsOwnColor("bg"))
	stub.cancelPick()
	eq(T.ToHex(T.Color("bg")), "#10161E", "cancel: the one before")
	row.swatch.scripts.OnClick(row.swatch, "LeftButton")
	stub.pick(0.2, 0.1, 0.15)
	row.swatch.scripts.OnClick(row.swatch, "RightButton")
	ok(not T.IsOwnColor("bg"), "right-click: the scheme's again")
	-- The accent on the wheel makes it custom.
	for _, f in ipairs(stub.frames) do if rawget(f, "swatch") and f.shown and f.label.text == "Your accent" then row = f end end
	row.swatch.scripts.OnClick(row.swatch, "LeftButton")
	stub.pick(1, 0.5, 0.75)
	eq(ns.Get("look.accentMode"), "custom")
	eq(T.ToHex(T.Color("accent")), "#FF80BF")
	stub.cancelPick()
	eq(ns.Get("look.accentMode"), "class", "cancel: back to your class color")
end)

test("colors: a scheme code to share, and back", function()
	local stub, ns = fresh()
	local T = ns.Theme
	T.UseScheme("amethyst")
	T.SetColor("text", "#FFE0F0")
	local code = T.ExportColors()
	ok(code:find("^PWUI1:amethyst:B69CFF:"), code)
	T.UseScheme("pathwise")
	ok(not T.ImportColors("nonsense"), "not a code")
	ok(T.ImportColors(code), "a code")
	eq(T.ToHex(T.Color("text")), "#FFE0F0")
	eq(T.ToHex(T.Color("accent")), "#B69CFF")
	-- Through the options: show my code, paste one.
	ns.Config.Show("colors")
	ok(stub.clickLabel("Show my code"))
	local box
	for _, f in ipairs(stub.frames) do if f.kind == "EditBox" and f.shown and f.parent and f.parent.apply then box = f end end
	eq(box.text, T.ExportColors(), "your code in the box")
	T.UseScheme("pathwise")
	box.parent.apply.scripts.OnClick(box.parent.apply)
	eq(T.ToHex(T.Color("text")), "#FFE0F0", "applied")
end)

test("motion: off makes everything land at once", function()
	local stub, ns = fresh()
	ns.Set("look.motion", false)
	ns.Config.Show()
	eq(_G.PathwiseUIConfig.alpha, 1, "no fade")
	local f = CreateFrame("Frame")
	ns.Anim.Fade(f, 0.3)
	eq(f.alpha, 0.3)
	ok(not ns.Anim.Busy(), "nothing left moving")
end)

test("move mode: everything at once, a grid, Done locks it all", function()
	local stub, ns = fresh(function(s) s.makeTray() end)
	SlashCmdList.PATHWISEUI("move")
	ok(ns.Units.Unlocked() and ns.Bars.Unlocked() and ns.Tray.Unlocked(), "all unlocked")
	ok(_G.PathwiseUI_MoveGrid and _G.PathwiseUI_MoveGrid.shown, "the grid")
	eq(ns.Movers.Snap(13), 16, "drops snap to the grid")
	eq(ns.Movers.Snap(13, true), 13, "Shift: free")
	ok(stub.clickLabel("Done"))
	ok(not ns.Units.Unlocked() and not ns.Bars.Unlocked() and not ns.Tray.Unlocked(), "all locked")
	stub.advance(0.3)
	ok(not _G.PathwiseUI_MoveGrid.shown, "grid gone")
end)

test("crisp borders: one screen pixel at any UI scale", function()
	local stub, ns = fresh(function()
		GetPhysicalScreenSize = function() return 2560, 1440 end
		UIParent.GetEffectiveScale = function() return 0.64 end
	end)
	near(ns.Theme.Pixel(), 768 / 1440 / 0.64, 1e-9)
	local f = CreateFrame("Frame")
	T = ns.Theme
	T.Panel(f, "bg")
	near(f.pwBorder.edges[1].h, ns.Theme.Pixel(), 1e-9, "top edge one pixel tall")
	GetPhysicalScreenSize, T = nil, nil
end)

test("Wayfarer: trim color from a dropdown: Class, Default (gold) or Custom on the wheel", function()
	local stub, ns = fresh()
	local T = ns.Theme
	eq(T.ToHex(T.Color("flair")), "#E8C26A", "gold by default")
	ns.Config.Show("look")
	-- The dropdown shows Default; opening it lists the three.
	local dd
	for _, f in ipairs(stub.frames) do if rawget(f, "pwMenu") and f.shown and f.parent.label.text == "Trim color" then dd = f end end
	ok(dd, "a Trim color dropdown")
	eq(dd.pwText.text, "Default")
	dd.scripts.OnClick(dd)
	ok(dd.pwMenu.shown, "its menu opens")
	local items = {}
	for _, it in ipairs(dd.pwMenu.items) do if it.shown then items[#items + 1] = it.pwText.text end end
	eq(table.concat(items, ","), "Class,Default,Custom")
	dd.pwMenu.items[1].scripts.OnClick(dd.pwMenu.items[1])
	ok(not dd.pwMenu.shown, "picking closes it")
	eq(ns.Get("look.trim"), "class")
	near(T.Color("flair")[1], 0.25, 1e-6, "a mage's blue")
	-- No color wheel until Custom.
	local function swatchRow()
		for _, f in ipairs(stub.frames) do if rawget(f, "swatch") and f.shown and f.label.text == "Your trim color" then return f end end
	end
	ok(not swatchRow(), "no picker for Class")
	ns.Set("look.trim", "custom")
	local row = swatchRow()
	ok(row, "Custom: the color picker")
	row.swatch.scripts.OnClick(row.swatch, "LeftButton")
	stub.pick(0.6, 0.5, 1)
	eq(T.ToHex(T.Color("flair")), "#9980FF")
	stub.cancelPick()
	eq(ns.Get("look.trim"), "custom", "cancel: as it was")
	row.swatch.scripts.OnClick(row.swatch, "RightButton")
	eq(ns.Get("look.trim"), "default", "right-click: back to gold")
	ns.Set("look.trim", "silver") -- an old quick pick from before
	eq(T.ToHex(T.Color("flair")), "#E8C26A", "reads as Default")
	T.UseScheme("blossom")
	ns.Set("look.trim", "default")
	eq(T.ToHex(T.Color("flair")), "#7A5600", "a light theme's darker gold")
end)

test("Wayfarer: serif headings in the trim color, capsule switches", function()
	local stub, ns = fresh()
	ns.Config.Show("tooltips")
	local heading
	for _, f in ipairs(stub.frames) do if f.kind == "FontString" and f.shown and f.text == "Tooltips" and rawget(f.parent, "rule") then heading = f end end
	ok(heading, "a heading with its rule")
	near((heading.textColor or heading.color)[1], ns.Theme.Color("flair")[1], 1e-6, "in the trim color")
	local sw
	for _, f in ipairs(stub.frames) do if rawget(f, "pwKnob") and f.shown then sw = f break end end
	eq(sw.pwKnob.texture, ns.Theme.MEDIA .. "disc", "a round knob")
	eq(sw.pwTrack[1].texture, ns.Theme.MEDIA .. "disc", "round ends")
end)

test("help and feedback: the website and Discord as links to copy, read-only", function()
	local stub, ns = fresh()
	local listed = false
	for _, c in ipairs(ns.Config.CATEGORIES) do if c.key == "help" then listed = true end end
	ok(listed, "in the options menu")
	ns.Config.Show("help")
	local boxes = {}
	for _, f in ipairs(stub.frames) do
		if f.kind == "EditBox" and f.shown and (not f.parent or f.parent.shown) and rawget(f, "text") then boxes[f.text] = f end
	end
	for _, url in ipairs({ "https://pathwise.quest/report", "https://pathwise.quest/suggest", "https://pathwise.quest/known-issues", "https://discord.gg/hSDjBrG8EK" }) do
		ok(boxes[url], "a box with " .. url)
	end
	local box = boxes["https://pathwise.quest/report"]
	box:SetText("typed over")
	box.scripts.OnTextChanged(box, true)
	eq(box:GetText(), "https://pathwise.quest/report", "typing puts the link back")
end)

---------------------------------------------------------------------------
-- The Pathwise v2 look: rounded windows and buttons, the 17 themes shared
-- with Pathwise, the options window's grip and pin
---------------------------------------------------------------------------

-- Pathwise's own themes, read from its file: { key, name, mode, colors }.
local function pathwiseThemes()
	local f = assert(io.open("Pathwise/Theme/Signature.lua", "r"))
	local src = f:read("*a")
	f:close()
	local out = {}
	for body in src:match("T%.THEMES = (%b{})"):sub(2, -2):gmatch("(%b{})") do
		local th = { colors = {} }
		th.key, th.name, th.mode = body:match('key = "(%w+)"'), body:match('name = "([^"]+)"'), body:match('mode = "(%w+)"')
		for k, v in body:gmatch('(%w+) = "(#%x+)"') do th.colors[k] = v end
		out[#out + 1] = th
	end
	return out
end

test("themes: Pathwise's 17, the same keys, names and colors", function()
	local stub, ns = fresh()
	local T = ns.Theme
	local theirs = pathwiseThemes()
	eq(#theirs, 17, "Pathwise has 17")
	eq(#T.THEMES, 17)
	eq(#T.SCHEMES, 17, "a scheme for each")
	for i, th in ipairs(theirs) do
		local mine = T.THEMES[i]
		eq(mine.key, th.key, "theme " .. i)
		eq(mine.name, th.name, th.key)
		eq(mine.mode, th.mode, th.key)
		for k, v in pairs(th.colors) do eq(mine[k], v, th.key .. "." .. k) end
		local s = T.Scheme(th.key)
		for _, k in ipairs({ "bg", "bg2", "hover", "border", "divider", "text", "text2", "muted", "accent", "success", "warning", "error" }) do
			eq(s.colors[k], th.colors[k], th.key .. " scheme " .. k)
		end
		for _, g in ipairs(T.COLOR_GROUPS) do
			for _, k in ipairs(g.keys) do ok(T.ValidHex(s.colors[k[1]]), th.key .. " has " .. k[1]) end
		end
	end
	eq(T.Scheme("forest").key, "emerald", "an old scheme's key: the theme it became")
	eq(T.Scheme("nonsense").key, "pathwise")
end)

test("themes: light ones stay legible, a class accent too", function()
	local stub, ns = fresh()
	local T = ns.Theme
	local light = 0
	for _, s in ipairs(T.SCHEMES) do
		if s.mode == "light" then
			light = light + 1
			for _, ground in ipairs({ "bg", "bg2" }) do
				for _, k in ipairs({ "text", "text2", "muted", "accent", "gold", "silver", "copper", "flair", "success", "warning", "error" }) do
					local c = T.Contrast(T.Hex(s.colors[k]), T.Hex(s.colors[ground]))
					ok(c >= 4.5, ("%s: %s on %s only %.2f:1"):format(s.key, k, ground, c))
				end
			end
		end
	end
	eq(light, 6, "six light themes")
	-- A light theme: the accent is the theme's; a pale class color is darkened.
	stub.player.class = "ROGUE"
	T.UseScheme("snow")
	eq(T.ToHex(T.Color("accent")), "#111418", "Snow's own accent")
	ns.Set("look.accentMode", "class")
	ok(T.Contrast(T.Color("accent"), T.Color("bg2")) >= 4.5, "rogue yellow darkened to read on white")
	ok(T.Color("accentHover")[1] < T.Color("accent")[1], "hover darker on a light theme")
	ns.Set("look.trim", "class")
	ok(T.Contrast(T.Color("flair"), T.Color("bg")) >= 4.5, "the trim too")
	-- A dark theme leaves it as it is.
	T.UseScheme("pathwise")
	ns.Set("look.accentMode", "class")
	near(T.Color("accent")[2], 0.96, 1e-6, "rogue yellow on a dark theme")
end)

test("themes: one theme with Pathwise, both ways", function()
	local pathwise = { settings = { ["ui.theme"] = "rose", ["ui.accentMode"] = "pathwise", ["ui.accentColor"] = "#66D7FF" }, listeners = {} }
	local stub, ns = fresh(function()
		Pathwise = { Suite = {
			Get = function(p) return pathwise.settings[p] end,
			Set = function(p, v)
				pathwise.settings[p] = v
				for _, fn in ipairs(pathwise.listeners) do fn(p, v) end
			end,
			On = function(msg, fn) if msg == "SETTING_CHANGED" then table.insert(pathwise.listeners, fn) end end,
			RegisterModule = function() end,
		} }
	end)
	local T = ns.Theme
	eq(ns.Get("look.scheme"), "rose", "a first start takes Pathwise's theme")
	eq(T.ToHex(T.Color("bg")), "#1C1218")
	T.UseScheme("sky")
	eq(pathwise.settings["ui.theme"], "sky", "a theme picked here goes to Pathwise")
	eq(pathwise.settings["ui.accentMode"], "pathwise", "with its own accent")
	Pathwise.Suite.Set("ui.theme", "ocean")
	eq(ns.Get("look.scheme"), "ocean", "and one picked in Pathwise comes back")
	eq(T.ToHex(T.Color("accent")), "#4FD8D0", "its accent with it")
	Pathwise.Suite.Set("ui.theme", "nonsense")
	eq(ns.Get("look.scheme"), "ocean", "an unknown one is left alone")
	ns.Set("look.sharePathwise", false)
	T.UseScheme("gold")
	eq(pathwise.settings["ui.theme"], "nonsense", "unlinked: each its own")
	Pathwise = nil
end)

test("rounded: windows and buttons are pieced, recolour as one; unit frames stay square", function()
	local stub, ns = fresh()
	local T = ns.Theme
	local win = CreateFrame("Frame")
	local ground = T.Panel(win)
	eq(win.pwRadius, T.RADIUS.window, "a window: radius 10")
	eq(#ground.pieces, 7, "four corners, a middle and two strips")
	local corners = 0
	for _, t in ipairs(ground.pieces) do if t.texture and t.texture:find("corner$") then corners = corners + 1 end end
	eq(corners, 4)
	near(ground.color[4], ns.Get("look.opacity"), 1e-6, "follows the opacity")
	ns.Set("look.opacity", 0.6)
	for _, t in ipairs(ground.pieces) do
		local c = ground.corners[t] and t.vertex or t.color
		near(c[4], 0.6, 1e-6, "every piece at the new opacity")
	end
	eq(#win.pwBorder.edges, 4, "the border's straight edges")
	near(win.pwBorder.edges[1].h, T.Pixel(), 1e-9, "one pixel")
	T.SetBorder(win, "accent")
	for _, t in ipairs(win.pwBorder.pieces) do
		local c = win.pwBorder.corners[t] and t.vertex or t.color
		near(c[1], T.Color("accent")[1], 1e-6, "every border piece in the accent")
	end
	ok(win.pwBorder.pieces[1].texture:find("corner%-line$"), "a window's corner line")
	-- Repainted by name with the rest.
	T.UseScheme("crimson")
	near(ground.color[1], 0x1C / 255, 1e-6, "a new theme repaints the pieces")
	-- Buttons, dropdowns, menus: radius 6.
	local b = T.Button(UIParent, "Go", "default")
	eq(b.pwRadius, 6, "a button: radius 6")
	ok(b.pwGround.pieces and b.pwBorder.pieces[1].texture:find("corner%-line%-small$"), "rounded, its smaller corner line")
	b.scripts.OnEnter(b)
	stub.advance(0.3)
	near(b.pwGround.color[1], T.Color("hover")[1], 1e-6, "hover eases the whole ground")
	local d = T.Dropdown(UIParent, 120)
	eq(d.pwRadius, 6)
	eq(d.pwMenu.pwRadius, 6, "its menu too")
	-- Unit frames and other bars: square.
	local sq = CreateFrame("Frame")
	local t = T.Panel(sq, "bg", "border", 0.9)
	ok(not t.pieces and not sq.pwRadius, "square")
	eq(#sq.pwBorder.edges, 4)
end)

test("options window: a resize grip, a pin on its header", function()
	local stub, ns = fresh()
	ns.Config.Show("look")
	local f = _G.PathwiseUIConfig
	eq(f.pwRadius, 10, "rounded")
	eq(f.w, 700)
	local g = f.pwGrip
	ok(g, "a grip")
	-- Drag it 100 right and 100 down.
	stub.cursor = { 1000, 600 }
	g.scripts.OnMouseDown(g, "LeftButton")
	stub.cursor = { 1100, 500 }
	g.scripts.OnUpdate(g)
	eq(f.w, 800, "wider")
	eq(f.h, 640, "taller")
	local body
	for _, fr in ipairs(stub.frames) do if fr.kind == "Frame" and fr.parent and fr.parent.kind == "ScrollFrame" and fr.parent.parent == f then body = fr end end
	eq(body.w, 800 - 172 - 36 - 14, "the page laid out again at the new width")
	g.scripts.OnMouseUp(g, "LeftButton")
	eq(ns.Get("config.width"), 800, "the size is kept")
	eq(ns.Get("config.height"), 640)
	stub.cursor = { 1000, 600 }
	g.scripts.OnMouseDown(g, "LeftButton")
	stub.cursor = { 3000, -2000 }
	g.scripts.OnUpdate(g)
	g.scripts.OnMouseUp(g, "LeftButton")
	eq(f.w, 1200, "no wider than its limit")
	g.scripts.OnMouseUp(g, "RightButton")
	eq(f.w, 700, "right-click: back to the usual size")
	-- The pin: no dragging, no resizing.
	local pin = f.pwPin
	ok(pin, "a pin")
	pin.scripts.OnClick(pin)
	eq(ns.Get("config.locked"), true, "pinned")
	near(pin.pwIcon.vertex[1], ns.Theme.Color("accent")[1], 1e-6, "in the accent")
	local moved = false
	rawset(f, "StartMoving", function() moved = true end)
	f.scripts.OnDragStart(f)
	ok(not moved, "a pinned window stays put")
	stub.cursor = { 1000, 600 }
	g.scripts.OnMouseDown(g, "LeftButton")
	ok(not g.pwState.held, "and keeps its size")
	pin.scripts.OnClick(pin)
	f.scripts.OnDragStart(f)
	ok(moved, "unpinned: it moves again")
	-- Back to the defaults: the usual size.
	ns.Set("config.width", 900)
	ns.Reset()
	eq(f.w, 700)
end)
