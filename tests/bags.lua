-- Tests for Pathwise_Bags: what each item is (keep, quest, profession,
-- upgrade, junk, sellable), selling junk at a vendor, bag space, the bag
-- window and its panel. Loaded by tests/run.lua.
local h = ...
local test, eq, ok, fresh, lastPrint = h.test, h.eq, h.ok, h.fresh, h.lastPrint

local INT, STR, STA = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT"

-- Item facts: { name, quality, ilvl, sell, classID, subclassID, equipLoc, minLevel }
local ITEMS = {
	[101] = { { "Worn Cloth Hood", 1, 10, 5, 4, 1, "INVTYPE_HEAD", 5 }, { [INT] = 2 } },
	[102] = { { "Glyphed Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }, { [INT] = 6, [STA] = 2 } },
	[103] = { { "Iron Helm", 2, 18, 40, 4, 4, "INVTYPE_HEAD", 13 }, { [STR] = 8, [STA] = 6 } },
	[201] = { { "Broken Fang", 0, 5, 12, 15, 0, "", 1 } },
	[202] = { { "Cracked Bone", 0, 5, 7, 15, 0, "", 1 } },
	[203] = { { "Ghoul Rib", 1, 5, 0, 12, 0, "", 1 } },
	[204] = { { "Linen Cloth", 1, 5, 1, 7, 5, "", 1 } },
	[205] = { { "Dull Pebble", 0, 1, 0, 15, 0, "", 1 } },
	[206] = { { "Lucky Charm", 0, 5, 30, 15, 0, "", 1 } },
}
local QUEST = 990100

local function bags(setup)
	local stub, ns = fresh()
	stub.player.level = 20
	for id, d in pairs(ITEMS) do stub.itemInfo[id], stub.itemStats[id] = d[1], d[2] end
	stub.equipped[1] = 101
	stub.bags[0] = {
		{ itemID = 201, quality = 0, stackCount = 3 }, -- grey junk, 3 x 12c
		{ itemID = 202, quality = 0 }, -- grey junk, 7c
		{ itemID = 203, quality = 1 }, -- a quest needs it
		{ itemID = 204, quality = 1, stackCount = 20 }, -- trade goods
		{ itemID = 205, quality = 0, hasNoValue = true }, -- grey, no price
		{ itemID = 206, quality = 0 }, -- grey, but kept by the player below
		{ itemID = 102, quality = 2 }, -- an upgrade
		{ itemID = 103, quality = 2, isBound = true }, -- plate on a mage, bound
	}
	if setup then setup(stub) end
	local gear = stub.loadAddon(".", "Pathwise_Gear")
	local b = stub.loadAddon(".", "Pathwise_Bags")
	-- A quest that asks for the Ghoul Rib.
	Pathwise.Suite.Data.quests[QUEST] = { "Ribs for the Ghoul", 20, 15, 0, 0, nil, nil, nil, nil, nil, nil, { { "i", 203, "Ghoul Rib" } } }
	stub.moveTo(1420, 60, 52)
	stub.login()
	return stub, ns, b, gear
end

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

local function slotOf(b, id)
	for _, e in ipairs(b.Items.Scan()) do if e.id == id then return e end end
end

test("bags: what each item is to you", function()
	local stub, ns, b = bags()
	local I = b.Items
	I.Mark(206, "keep")
	local junk = slotOf(b, 201)
	eq(junk.facts.category, "junk")
	ok(junk.facts.tags.junk and junk.facts.sell, "grey with a price: junk, can be sold")
	local rib = slotOf(b, 203)
	eq(rib.facts.category, "quest")
	ok(rib.facts.tags.quest and not rib.facts.sell, "a quest still wants it")
	ok(rib.facts.why:find("For a quest later: Ribs for the Ghoul"), rib.facts.why)
	stub.accept(QUEST)
	ok(slotOf(b, 203).facts.why:find("^Needed for Ribs for the Ghoul"), slotOf(b, 203).facts.why)
	eq(slotOf(b, 204).facts.category, "profession", "trade goods")
	local hood = slotOf(b, 102)
	eq(hood.facts.category, "upgrade")
	ok(hood.facts.tags.upgrade or hood.facts.tags.best, "Pathwise Gear says it is better")
	local helm = slotOf(b, 103)
	ok(helm.facts.tags.unusable and helm.facts.sell, "plate on a mage: can go")
	local pebble = slotOf(b, 205)
	ok(not pebble.facts.tags.junk and not pebble.facts.sell, "grey with no price: not junk, nothing to sell")
	local charm = slotOf(b, 206)
	ok(charm.facts.tags.keep and not charm.facts.tags.junk and not charm.facts.sell, "kept by you: never sold")
	I.Mark(204, "junk")
	ok(slotOf(b, 204).facts.tags.junk and slotOf(b, 204).facts.sell, "marked junk")
	eq(I.Money(12345), "1g 23s 45c")
	eq(I.Money(0), "0c")
end)

test("bags: selling junk at a vendor, by a click", function()
	local stub, ns, b = bags()
	b.Items.Mark(206, "keep")
	stub.merchant = true
	stub.fire("MERCHANT_SHOW")
	local btn = b.Sell.Button
	ok(btn and btn.shown, "a Sell junk button on the vendor window")
	ok(btn.pwText.text:find("^Sell junk: 2"), btn.pwText.text)
	eq(#stub.used, 0, "nothing sold before the click")
	btn.scripts.OnClick(btn)
	eq(stub.money, 3 * 12 + 7, "the two greys sold")
	ok(slotOf(b, 205) and slotOf(b, 206) and slotOf(b, 103), "no price, kept and bound gear stay")
	ok(lastPrint(stub):find("sold 2 items for 43c"), lastPrint(stub))
	stub.fire("MERCHANT_CLOSED")
	ok(not btn.shown, "gone with the vendor")
end)

test("bags: selling on its own, and bound gear you can't use", function()
	local stub, ns, b = bags()
	ns.Set("bags.sellAuto", true)
	ns.Set("bags.sellBound", true)
	stub.merchant = true
	stub.fire("MERCHANT_SHOW")
	ok(not slotOf(b, 201) and not slotOf(b, 202), "greys sold as the window opened")
	ok(not slotOf(b, 103), "the bound plate helm sold too")
	ok(slotOf(b, 102) and slotOf(b, 203) and slotOf(b, 204), "upgrade, quest item and materials stay")
end)

test("bags: free slots, the warning, and what to let go first", function()
	local stub, ns, b = bags()
	local S = b.Space
	eq(select(2, S.Free()), 16)
	eq((S.Free()), 8)
	local room = S.MakeRoom()
	eq(room[1].facts.tags.junk, true, "junk first")
	eq(room[#room].id, 103, "then gear you can't use")
	for i = 9, 14 do stub.bags[0][i] = { itemID = 204, quality = 1 } end
	stub.fire("BAG_UPDATE_DELAYED")
	ok(lastPrint(stub):find("Bags nearly full: 2 slots left. First to go: "), lastPrint(stub))
	local n = #stub.printed
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.printed, n, "said once")
end)

test("bags window: opens with the bag key, by kind, with search and marking", function()
	local stub, ns, b = bags()
	local W = b.Window
	OpenAllBags()
	ok(W.IsShown(), "the bag key opens the Pathwise window")
	local names = {}
	for _, g in ipairs(W.Groups("categories")) do names[#names + 1] = g.name end
	local list = table.concat(names, ",")
	ok(list:find("Quest") and list:find("Upgrades") and list:find("Professions") and list:find("Junk") and list:find("Empty"), list)
	local groups = W.Groups("categories")
	local last = groups[#groups]
	eq(last.key, "empty")
	eq(#last.entries, 1, "empty slots fold into one square")
	eq(last.entries[1].folded, 8, "with their count")
	eq(#W.Groups("grid")[1].entries, 16, "grid: every slot")
	local hood = slotOf(b, 102)
	eq(select(1, W.Markers(hood)), "upgrade")
	eq(select(2, W.Markers(slotOf(b, 201))), "sell")
	ok(W.Matches(hood, "glyphed"))
	ok(W.Matches(slotOf(b, 201), "junk"), "by category")
	ok(not W.Matches(hood, "fang"))
	eq(W.LevelText(hood), "18", "item level on gear")
	eq(W.LevelText(slotOf(b, 201)), nil, "not on junk")
	ok(W.MoneyText(12345):find("1.-g.-23.-s.-45.-c"), W.MoneyText(12345))
	-- Sections pack side by side: two of 3 items fit one 10-wide row.
	local places, height = W.Pack({ { entries = { 1, 2, 3 } }, { entries = { 1, 2, 3 } }, { entries = { 1, 2, 3, 4, 5, 6, 7, 8 } } }, 10 * 41 - 4, true)
	eq(places[1].y, 0)
	eq(places[2].y, 0, "second section beside the first")
	ok(places[2].x > places[1].x)
	ok(places[3].y > 0, "the third wraps to the next row")
	ok(height > places[3].y)
	-- The bag bar: your bags and their free slots.
	local info = W.BagInfo(0)
	eq(info.slots, 16)
	eq(info.free, 8)
	-- Mark mode: a click keeps, a second marks junk, a third clears.
	W.SetMarkMode(true)
	local catcher
	for _, f in ipairs(stub.frames) do
		if type(rawget(f, "pwEntry")) == "table" and f.pwEntry.id == 204 and f.scripts.OnClick and f.shown then catcher = f end
	end
	ok(catcher, "a click catcher over the Linen Cloth")
	catcher.scripts.OnClick(catcher)
	eq(b.Items.MarkOf(204), "keep")
	catcher.scripts.OnClick(catcher)
	eq(b.Items.MarkOf(204), "junk")
	catcher.scripts.OnClick(catcher)
	eq(b.Items.MarkOf(204), nil)
	ns.Set("bags.window", false)
	W.Hide()
	OpenAllBags()
	ok(not W.IsShown(), "off: the game's bags again")
end)

test("bags panel: in Settings, with selling, space and marks", function()
	local stub, ns, b = bags()
	b.Items.Mark(206, "keep")
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickLabelText("Pathwise Bags"), "listed in the Pathwise suite")
	local texts = stub.texts()
	ok(contains(texts, "Use the Pathwise bag window"), table.concat(texts, " | "))
	ok(contains(texts, "Sell on its own at vendors"))
	ok(contains(texts, "First to go when you need room"))
	ok(contains(texts, "Keep: Lucky Charm"))
end)

test("bags window: by bag, each bag its own section, foldable", function()
	local stub, ns, b = bags(function(s) s.bags[1] = { { itemID = 204, quality = 1 } } end)
	local W = b.Window
	ns.Set("bags.view", "bags")
	local groups = W.Groups("bags")
	eq(#groups, 2, "the backpack and one bag")
	ok(groups[1].name:find("^Backpack  ·  8 free"), groups[1].name)
	eq(#groups[1].entries, 16, "every slot of the backpack")
	ok(groups[2].name:find("15 free"), groups[2].name)
	W.ToggleBag(1)
	groups = W.Groups("bags")
	ok(groups[2].folded and #groups[2].entries == 0, "folded: no items")
	ok(groups[2].name:find("hidden"), groups[2].name)
	W.Show()
	local header
	for _, l in pairs(W.Headers()) do if l.pwBag == 1 and l.shown then header = l end end
	ok(header, "a clickable header for the bag")
	header.scripts.OnClick(header)
	ok(not (ns.Get("bags.folded") or {})[1], "a click shows it again")
	-- The layout button: by kind -> grid -> by bag -> by kind.
	ns.Set("bags.view", "categories")
	eq(W.NextView(), "grid")
	eq(W.NextView(), "bags")
	eq(W.NextView(), "categories")
	ns.Set("bags.view", "bags")
	ns.Fire("SHOW_SETTINGS")
	stub.clickLabelText("Pathwise Bags")
	ok(stub.clickLabel("By bag"), "the setting offers By bag")
end)

test("bags window: the bag key opens it and the next press closes it", function()
	local stub, ns, b = bags()
	local W = b.Window
	ToggleAllBags()
	ok(W.IsShown(), "first press: open")
	ToggleAllBags()
	ok(not W.IsShown(), "second press: closed")
	ToggleAllBags()
	ok(W.IsShown(), "third press: open again")
	ToggleBackpack()
	ok(not W.IsShown(), "the backpack key closes it too")
	OpenAllBags()
	ok(W.IsShown(), "a vendor or mailbox opening the bags shows it")
	OpenAllBags()
	ok(W.IsShown(), "and keeps it open")
	CloseAllBags()
	ok(not W.IsShown(), "closing all bags closes it")
end)

test("panels: Back returns to the panel a suite addon was opened from", function()
	local stub, ns, b = bags()
	ns.Fire("SHOW_SETTINGS")
	local P = _G.PathwisePanel
	ok(not P.back.shown, "no Back on the first panel")
	ok(stub.clickLabelText("Pathwise Bags"), "into Pathwise Bags")
	ok(P.back.shown, "a Back button at the top")
	ok(contains(stub.texts(), "Use the Pathwise bag window"))
	-- The Back beside Close (not the guide window's own Back, a step back).
	local function inPanel(f) while f do if f == P then return true end f = rawget(f, "parent") end return false end
	local bottom
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "pwText")
		if t and t.text == "Back" and f.shown and inPanel(f) then bottom = f end
	end
	ok(bottom, "and one beside Close")
	bottom.scripts.OnClick(bottom)
	ok(contains(stub.texts(), "PATHWISE SUITE"), "back in Pathwise's settings")
	ok(not P.back.shown, "nothing further back")
	-- Two steps: Settings > Pathwise Gear > Best in Slot (Level), then back twice.
	ok(stub.clickLabelText("Pathwise Gear"))
	ok(stub.clickLabelText("Best in Slot (Level)"))
	P.back.scripts.OnClick(P.back)
	ok(contains(stub.texts(), "Scoring with"), "back in Pathwise Gear")
	P.back.scripts.OnClick(P.back)
	ok(contains(stub.texts(), "PATHWISE SUITE"), "back in Settings")
	-- Closing forgets the way back.
	stub.clickLabelText("Pathwise Bags")
	ns.Suite.Close()
	ns.Fire("SHOW_SETTINGS")
	ok(not P.back.shown, "a fresh start after closing")
end)

test("panels: a setting's label never runs under its value or buttons", function()
	local stub, ns, b = bags()
	ns.Fire("SHOW_SETTINGS")
	stub.clickLabelText("Pathwise Bags")
	local P = _G.PathwisePanel
	local checked = 0
	for _, f in ipairs(stub.frames) do
		local label, buttons = rawget(f, "label"), rawget(f, "buttons")
		if label and type(buttons) == "table" and f.shown and rawget(f, "value") then
			local used = 0
			for _, bt in ipairs(buttons) do if bt.shown then used = used + bt.w + 4 end end
			local value = f.value.text ~= "" and (#f.value.text * 6 + 8) or 0
			ok(label.w + used + value <= f.w + 1, ("%q fits: %d + %d + %d <= %d"):format(label.text, label.w, used, value, f.w))
			checked = checked + 1
		end
	end
	ok(checked >= 6, "checked the setting rows")
	-- A choice of three shows which is picked by its highlight, not words too.
	for _, f in ipairs(stub.frames) do
		if rawget(f, "label") and f.label.text == "Show items" and f.shown then eq(f.value.text, "") end
	end
end)

test("panels: the panel holds still while a slider in it is dragged", function()
	local stub, ns = fresh()
	stub.login()
	ns.Fire("SHOW_SETTINGS")
	local P = _G.PathwisePanel
	P.GetLeft = function() return 300 end
	P.GetTop = function() return 700 end
	local s = stub.slider("ui.scale")
	ok(s, "the window size slider")
	s.GetLeft, s.GetWidth, s.GetEffectiveScale = function() return 310 end, function() return 200 end, function() return 1 end
	stub.cursor[1] = 330
	s.scripts.OnMouseDown(s, "LeftButton")
	ok(ns.Panels.IsPinned(), "pinned while dragging")
	local pt = P.points[#P.points]
	eq(pt[2], UIParent, "held where it is on the screen, not beside the guide")
	eq(pt[4], 300)
	eq(pt[5], 700)
	s.scripts.OnMouseUp(s)
	ok(not ns.Panels.IsPinned(), "let go: back beside the guide")
end)

test("panels: a suite panel opened on its own still has Back, to Pathwise's settings", function()
	local stub, ns, b = bags()
	ns.Suite.Open("bags") -- as the bag window's settings button does
	local P = _G.PathwisePanel
	ok(P.back.shown, "the back arrow at the top")
	local function inPanel(f) while f do if f == P then return true end f = rawget(f, "parent") end return false end
	local bottom
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "pwText")
		if t and t.text == "Back" and f.shown and inPanel(f) then bottom = f end
	end
	ok(bottom, "and Back beside Close at the bottom")
	bottom.scripts.OnClick(bottom)
	ok(contains(stub.texts(), "PATHWISE SUITE"), "it leads to Pathwise's settings")
	ok(not P.back.shown, "no Back from the settings themselves")
end)

test("minimap buttons: one for each suite addon, in its colour, each with its own place and switch", function()
	local stub, ns, b = bags()
	local main, gear, bagsBtn = _G.PathwiseMinimapButton, _G.PathwiseGearMinimapButton, _G.PathwiseBagsMinimapButton
	ok(main and gear and bagsBtn, "Pathwise, Pathwise Gear and Pathwise Bags each have one")
	ok(gear.shown and bagsBtn.shown)
	ok(gear.icon.texture:find("glyph%-upgrade") and bagsBtn.icon.texture:find("glyph%-bag"), "their own marks")
	ok(gear.points[1][4] ~= bagsBtn.points[1][4] or gear.points[1][5] ~= bagsBtn.points[1][5], "not on top of each other")
	-- Clicks.
	bagsBtn.scripts.OnClick(bagsBtn, "LeftButton")
	ok(b.Window.IsShown(), "Bags: click opens the bag window")
	bagsBtn.scripts.OnClick(bagsBtn, "LeftButton")
	ok(not b.Window.IsShown(), "and closes it")
	bagsBtn.scripts.OnClick(bagsBtn, "RightButton")
	ok(contains(stub.texts(), "Use the Pathwise bag window"), "right-click: Bags settings")
	gear.scripts.OnClick(gear, "LeftButton")
	ok(contains(stub.texts(), "Scoring with"), "Gear: click opens Pathwise Gear")
	gear.scripts.OnClick(gear, "RightButton")
	ok(contains(stub.texts(), "BEST IN SLOT (LEVEL)"), "right-click: Best in Slot (Level)")
	-- Hidden from its own settings; the others stay.
	ns.Set("bags.minimap", false)
	ok(not bagsBtn.shown and gear.shown and main.shown, "each has its own switch")
	-- Dragged: it remembers its own place.
	ns.Set("gear.minimapAngle", 90)
	ok(gear.points[#gear.points][5] > 0, "moved to the top")
	eq(ns.Get("bags.minimapAngle"), 165, "the others stay put")
end)

test("suite panels open by their own minimap button, Pathwise's by the guide", function()
	local stub, ns, b = bags()
	ns.Fire("SHOW_SETTINGS") -- builds this run's panel
	ns.Suite.Close()
	local P = _G.PathwisePanel
	local btn = _G.PathwiseBagsMinimapButton
	-- A 1920 x 1080 screen at scale 1; the Bags button near the top right.
	UIParent.GetWidth, UIParent.GetHeight, UIParent.GetEffectiveScale = function() return 1920 end, function() return 1080 end, function() return 1 end
	P.GetEffectiveScale = function() return 1 end
	btn.GetCenter, btn.GetEffectiveScale = function() return 1700, 900 end, function() return 1 end
	btn.scripts.OnClick(btn, "RightButton")
	local pt = P.points[#P.points]
	eq(pt[2], UIParent, "placed on the screen, not attached to anything")
	ok(pt[4] < 1700 - 24, "to the left of the button (the right half of the screen)")
	ok(pt[5] <= 1080 - 8 and pt[5] >= 900, "hanging down from the button's height")
	-- Pathwise's own settings: beside the guide window as before.
	ns.Fire("SHOW_SETTINGS")
	pt = P.points[#P.points]
	ok(pt[2] ~= UIParent or pt[1] == "CENTER", "Pathwise's settings are not by the Bags button")
	-- The button hidden: the Bags settings fall back to the guide window.
	ns.Set("bags.minimap", false)
	ns.Suite.Close()
	ns.Suite.Open("bags")
	pt = P.points[#P.points]
	ok(pt[2] ~= UIParent or pt[1] == "CENTER", "no button: by the guide")
	-- A button on the left, low down: the panel to its right, standing up from it.
	ns.Set("bags.minimap", true)
	btn.GetCenter = function() return 200, 150 end
	ns.Suite.Close()
	ns.Suite.Open("bags")
	pt = P.points[#P.points]
	eq(pt[4], 224, "to the right of the button")
end)
