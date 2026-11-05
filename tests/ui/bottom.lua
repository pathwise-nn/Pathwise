-- Tests for the experience bar and the system tray / bag buttons.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

test("experience bar: your experience and rested, under the main bar, as wide", function()
	local stub, ns = fresh(function()
		StatusTrackingBarManager = CreateFrame("Frame", "StatusTrackingBarManager")
	end)
	local X = ns.XPBar
	local f = X.Frame()
	ok(f and f.shown, "shown")
	eq(f.bar.value, 4512)
	eq(f.rested.value, 4512 + 2100, "rested ahead of it")
	eq(X.Text(X.Data()), "Level 21  ·  4,512 / 9,800 (46%)  ·  rested 2,100")
	local main = ns.Bars.bars[1]
	eq(f.w, main.w, "as wide as the main bar")
	eq(f.points[#f.points][2], main, "right under it")
	ok(X.Hidden()[StatusTrackingBarManager], "the game's bar put away")
	near(f.bar.barColor[1], ns.Theme.Color("accent")[1], 1e-6, "in your color")
end)

test("experience bar: the watched reputation at the level cap", function()
	local stub, ns = fresh(function(s)
		s.player.level = 60
		s.units.player.level = 60
		s.watchedFaction = { name = "Stormwind", reaction = 6, currentReactionThreshold = 3000, nextReactionThreshold = 9000, currentStanding = 4200 }
	end)
	eq(ns.XPBar.Text(ns.XPBar.Data()), "Stormwind: 1,200 / 6,000 (20%)")
	stub.watchedFaction = nil
	ns.XPBar.Update()
	ok(not ns.XPBar.Frame().shown, "nothing to show: hidden")
end)

test("tray and bags: the game's own buttons in two Pathwise rows", function()
	local stub, ns = fresh(function(s) s.makeTray() end)
	local Tr = ns.Tray
	local tray, bags = _G.PathwiseUI_Tray, _G.PathwiseUI_BagBar
	ok(tray and tray.shown and bags and bags.shown, "both rows shown")
	eq(CharacterMicroButton.parent, tray, "the game's character button in the tray")
	eq(MainMenuBarBackpackButton.parent, bags, "the backpack in the bag row")
	eq(tray.w, 8 * 28 + 7 * 3, "eight buttons at 28 + 3")
	ok(Tr.Hidden()[MicroMenuContainer] and Tr.Hidden()[BagsBar], "the game's own rows put away")
	-- A glyph on each tray button.
	local glyph
	for _, f in ipairs(stub.frames) do
		if f.parent == SpellbookMicroButton and rawget(f, "texture") and f.texture:find("glyph%-book") then glyph = f end
	end
	ok(glyph, "the spellbook's glyph")
	-- The game hides one: the row closes up.
	HelpMicroButton:Hide()
	Tr.Build()
	eq(tray.w, 7 * 28 + 6 * 3)
	-- The game lays its micro menu out again: ours put back.
	CharacterMicroButton:SetParent(MicroMenu)
	MicroMenu:Layout()
	eq(CharacterMicroButton.parent, tray, "back in the tray")
end)

test("tray and bags: the tray left of the bag row, never over it", function()
	local stub, ns = fresh(function(s) s.makeTray() end)
	local tray, bags = _G.PathwiseUI_Tray, _G.PathwiseUI_BagBar
	local p = tray.points[#tray.points]
	eq(p[2], bags, "against the bag row")
	eq(p[1], "BOTTOMRIGHT")
	eq(p[3], "BOTTOMLEFT")
	eq(p[4], -ns.Tray.GAP, "with a gap")
	-- Bags off: the tray goes to its own corner place.
	ns.Set("tray.bags", false)
	p = tray.points[#tray.points]
	eq(p[2], UIParent, "on its own")
	-- Moved by the player: their place, bags or not.
	ns.Set("tray.bags", true)
	ns.Set("tray.microPoint", { "BOTTOM", "BOTTOM", 0, 100 })
	p = tray.points[#tray.points]
	eq(p[2], UIParent)
	eq(p[5], 100)
end)

test("tray and bags: size, moving, off", function()
	local stub, ns = fresh(function(s) s.makeTray() end)
	local Tr = ns.Tray
	ns.Set("tray.size", 32)
	eq(CharacterMicroButton.w, 32)
	ok(Tr.Unlock(true))
	Tr.Unlock(false)
	ns.Set("tray.bags", false)
	ok(not _G.PathwiseUI_BagBar.shown, "bags off")
	ns.Config.Show("bottom")
	local texts = stub.texts()
	ok(contains(texts, "Pathwise experience bar") and contains(texts, "Pathwise tray"), table.concat(texts, " | "))
end)

test("money: always shown, counts to a new amount, flashes green or red", function()
	local stub, ns = fresh(function(s) s.money = 123456 end)
	local M = ns.Money
	local f = _G.PathwiseUI_Money
	ok(f and f.shown, "shown at login")
	eq(M.Format(123456, "full", true), "12g 34s 56c")
	ok(stub.shown(f.text):find("12|r"), "colored parts: " .. stub.shown(f.text))
	eq(M.Format(5, "full", true), "5c")
	eq(M.Format(0, "full", true), "0c")
	eq(M.Format(12345678, "gold", true), "1,234g")
	eq(M.Format(12345678 * 10, "short", true), "12.3kg")
	eq(M.Format(50, "gold", true), "50c", "under a gold: still shown")
	stub.money = 223456
	stub.fire("PLAYER_MONEY")
	eq(M.Shown(), 223456)
	ok(not stub.shown(f.text):find("^|cff%x+22|r"), "still counting")
	near(f.flash.color[1], ns.Theme.Color("success")[1], 1e-6, "green: more")
	stub.advance(0.6)
	ok(stub.shown(f.text):find("22|r"), "counted to it: " .. stub.shown(f.text))
	stub.money = 100
	stub.fire("PLAYER_MONEY")
	near(f.flash.color[1], ns.Theme.Color("error")[1], 1e-6, "red: less")
	ns.Set("money.enabled", false)
	ok(not f.shown, "off")
end)

test("money: this session and every character in the tooltip", function()
	local stub, ns = fresh(function(s)
		s.money = 50000
		PathwiseUISettings = { schema = 1, data = { money = {
			["Alt-"] = { name = "Alt", realm = "", copper = 2000000, class = "ROGUE" },
			["Faraway-Other"] = { name = "Faraway", realm = "Other", copper = 9 } } } }
	end)
	local M = ns.Money
	stub.money = 80000
	stub.fire("PLAYER_MONEY")
	stub.tooltipLines = {}
	M.Tooltip(_G.PathwiseUI_Money)
	local lines = {}
	for _, l in ipairs(stub.tooltipLines) do lines[#lines + 1] = tostring(l[1]) .. "=" .. tostring(l[2]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
	local all = table.concat(lines, " ; ")
	ok(all:find("This session=%+3g", 1), all)
	ok(all:find("Alt=200g", 1, true) and all:find("Frozen %(you%)=8g"), all)
	ok(all:find("All characters=208g", 1, true), all)
	ok(not all:find("Faraway", 1, true), "other realms left out")
	SlashCmdList.PATHWISEUI("forget alt")
	local list = M.Characters()
	eq(#list, 1, "forgotten")
	ns.Reset()
	ok(PathwiseUISettings.data.money, "defaults never clear the records")
end)

test("money: moves with everything else, and its options", function()
	local stub, ns = fresh()
	SlashCmdList.PATHWISEUI("move")
	ok(ns.Money.Unlocked(), "in move mode")
	ok(stub.clickLabel("Done"))
	ok(not ns.Money.Unlocked())
	ns.Config.Show("bottom")
	local texts = {}
	for _, t in ipairs(stub.texts()) do texts[#texts + 1] = t end
	ok(table.concat(texts, "|"):find("Money always shown", 1, true), table.concat(texts, " | "))
	ok(stub.clickLabel("Gold only"))
	eq(ns.Get("money.style"), "gold")
	ns.Config.Show("colors")
	ok(table.concat(stub.texts(), "|"):find("Copper", 1, true), "its colors on the Colors page")
end)

test("tray: a tooltip with the button's name and key, unless the game shows its own", function()
	local stub, ns = fresh(function(s) s.makeTray() s.bindings.TOGGLESPELLBOOK = { "P" } end)
	local Tr = ns.Tray
	local said = {}
	GameTooltip.SetText = function(_, t) said.text = t end
	GameTooltip.AddLine = function(_, t) said.line = t end
	GameTooltip.IsShown = function() return said.shown end
	GameTooltip.GetOwner = function() return said.owner end
	GameTooltip.SetOwner = function(_, o) said.owner = o end
	GameTooltip.Show = function() said.shown = true end
	ok(Tr.Tooltip(SpellbookMicroButton))
	eq(said.text, "Spellbook")
	eq(said.line, "P", "its key")
	said.text, said.line = nil, nil
	ok(Tr.Tooltip(MainMenuMicroButton))
	eq(said.text, "Game menu and settings")
	ok(Tr.Tooltip(CharacterBag1Slot))
	eq(said.text, "Bag 2")
	said.owner, said.shown = HelpMicroButton, true
	ok(not Tr.Tooltip(HelpMicroButton), "the game's own tooltip stays")
end)
