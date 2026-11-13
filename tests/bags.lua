-- Tests for Pathwise_Bags: what each item is (keep, quest, profession,
-- upgrade, junk, sellable), selling junk at a vendor, bag space, the bag
-- window and its options, with Pathwise and Pathwise Gear installed and on its
-- own. Loaded by tests/run.lua.
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

-- The bags the tests start with.
local function fill(stub)
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
end

-- No Pathwise Bags settings or marks from an earlier test (a fresh install).
local function clean()
	PathwiseBagsSettings, PathwiseBagsCharSettings, PathwiseBags = nil, nil, nil
	PathwiseBagsFrame, PathwiseBagsMinimapButton, PathwiseBagsMinimapMenu, PathwiseBagsConfig = nil, nil, nil, nil
end

-- Pathwise, Pathwise Gear and Pathwise Bags, logged in. `setup(stub, ns)`
-- runs before Pathwise Bags loads.
local function bags(setup)
	clean()
	local stub, ns = fresh()
	stub.player.level = 20
	fill(stub)
	if setup then setup(stub, ns) end
	local gear = stub.loadAddon(".", "Pathwise_Gear")
	local b = stub.loadAddon(".", "Pathwise_Bags")
	-- A quest that asks for the Ghoul Rib.
	Pathwise.Suite.Data.quests[QUEST] = { "Ribs for the Ghoul", 20, 15, 0, 0, nil, nil, nil, nil, nil, nil, { { "i", 203, "Ghoul Rib" } } }
	stub.moveTo(1420, 60, 52)
	stub.fire("ADDON_LOADED", "Pathwise_Bags")
	stub.login()
	return stub, ns, b, gear
end

-- Pathwise Bags on its own: no Pathwise, no Pathwise Gear.
local function alone(setup)
	clean()
	PathwiseSettings, PathwiseCharSettings, Pathwise = nil, nil, nil
	for k in pairs(_G) do if type(k) == "string" and k:find("^PathwiseGear") then _G[k] = nil end end
	local stub = dofile("./tests/stub.lua")
	stub.player.level = 20
	fill(stub)
	if setup then setup(stub) end
	local b = stub.loadAddon(".", "Pathwise_Bags")
	stub.fire("ADDON_LOADED", "Pathwise_Bags")
	stub.fire("PLAYER_LOGIN")
	return stub, b
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
	ok(lastPrint(stub):find("Sold 2 items for 43c"), lastPrint(stub))
	stub.fire("MERCHANT_CLOSED")
	ok(not btn.shown, "gone with the vendor")
end)

test("bags: selling on its own, and bound gear you can't use", function()
	local stub, ns, b = bags()
	b.Set("bags.sellAuto", true)
	b.Set("bags.sellBound", true)
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
	b.Set("bags.window", false)
	W.Hide()
	OpenAllBags()
	ok(not W.IsShown(), "off: the game's bags again")
end)

test("bags options: its own window, listed in the Pathwise suite, with selling, space and marks", function()
	local stub, ns, b = bags()
	b.Items.Mark(206, "keep")
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickLabelText("Pathwise Bags"), "listed in the Pathwise suite")
	ok(_G.PathwiseBagsConfig and _G.PathwiseBagsConfig.shown, "it opens Pathwise Bags' own options")
	local texts = stub.texts()
	ok(contains(texts, "Use the Pathwise bag window"), table.concat(texts, " | "))
	ok(contains(texts, "Pathwise: Leveling & Professions is installed"), "says what Pathwise adds")
	ok(contains(texts, "Pathwise Gear is installed"))
	b.Config.Show("sell")
	ok(contains(stub.texts(), "Sell on its own at vendors"))
	b.Config.Show("space")
	ok(contains(stub.texts(), "FIRST TO GO") or contains(stub.texts(), "First to go"), table.concat(stub.texts(), " | "))
	b.Config.Show("marks")
	ok(stub.clickLabel("Keep: Lucky Charm  (clear)"), "a kept item, a click clears it")
	eq(b.Items.MarkOf(206), nil)
end)

test("bags window: by bag, each bag its own section, foldable", function()
	local stub, ns, b = bags(function(s) s.bags[1] = { { itemID = 204, quality = 1 } } end)
	local W = b.Window
	b.Set("bags.view", "bags")
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
	ok(not (b.Get("bags.folded") or {})[1], "a click shows it again")
	-- The layout button: by kind -> grid -> by bag -> by kind.
	b.Set("bags.view", "categories")
	eq(W.NextView(), "grid")
	eq(W.NextView(), "bags")
	eq(W.NextView(), "categories")
	b.Set("bags.view", "bags")
	b.Config.Show("bags")
	ok(contains(stub.texts(), "By bag"), "the setting offers By bag")
end)

test("bags window: the bag key opens it and the next press closes it", function()
	local stub, ns, b = bags()
	local W = b.Window
	-- Each press in a frame of its own (the stub runs Forever's chain:
	-- ToggleAllBags -> OpenBackpack -> ToggleBackpack -> ToggleBag(0)).
	local function press(fn) stub.now = stub.now + 1 fn() end
	press(ToggleAllBags)
	ok(W.IsShown(), "first press: open")
	press(ToggleAllBags)
	ok(not W.IsShown(), "second press: closed")
	press(ToggleAllBags)
	ok(W.IsShown(), "third press: open again")
	press(ToggleBackpack)
	ok(not W.IsShown(), "the backpack key closes it too")
	press(OpenAllBags)
	ok(W.IsShown(), "a vendor or mailbox opening the bags shows it")
	press(OpenAllBags)
	ok(W.IsShown(), "and keeps it open")
	press(CloseAllBags)
	ok(not W.IsShown(), "closing all bags closes it")
end)

test("bags window: the bag bar's tiles open it, not the game's bags", function()
	local stub, ns, b = bags()
	local W = b.Window
	ToggleBag(0)
	ok(W.IsShown(), "the backpack tile opens the Pathwise window")
	stub.now = stub.now + 1
	ToggleBag(2)
	ok(not W.IsShown(), "a bag tile closes it again")
	stub.now = stub.now + 1
	ToggleBag(5)
	ToggleBag(-2)
	ok(not W.IsShown(), "no reagent bag in this client (no Enum.BagIndex), and the keyring stay the game's")
	b.Set("bags.window", false)
	stub.now = stub.now + 1
	ToggleBag(0)
	ok(not W.IsShown(), "window off: the game's bags")
end)

test("bags: the reagent bag, where the client has one", function()
	local secret = setmetatable({}, {})
	local stub, ns, b = bags(function(s)
		Enum.BagIndex = { Backpack = 0, ReagentBag = 5 }
		s.bags[5] = { { itemID = 204, quality = 1, stackCount = 40 } }
		function C_Container.ContainerIDToInventoryID(bag) return 30 + bag end
		function GetInventoryItemTexture(_, inv) return "icon-" .. inv end
		-- The bag's name kept secret: the window names it itself.
		function issecretvalue(v) return v == secret end
		function C_Container.GetBagName(bag) return bag == 5 and secret or nil end
	end)
	local I, W, Sp = b.Items, b.Window, b.Space
	eq(I.REAGENT_BAG, 5)
	eq(I.BAGS[#I.BAGS], 5, "read with the other bags")
	local inReagent
	for _, x in ipairs(I.Scan()) do if x.bag == 5 and x.id == 204 then inReagent = x end end
	ok(inReagent and inReagent.count == 40, "its items are scanned")
	eq(select(2, Sp.Free()), 16, "bag space leaves the reagent bag out")
	local groups = W.Groups("bags")
	eq(#groups, 2, "the backpack and the reagent bag")
	ok(groups[2].name:find("^Reagent bag  ·  15 free"), groups[2].name)
	eq(groups[2].bag, 5)
	eq(#W.Groups("grid")[1].entries, 32, "the grid has its slots")
	b.Set("bags.bagBar", true)
	W.Show()
	local bar = W.BagBar()
	local tile = bar.slots[#I.BAGS]
	ok(tile.shown, "a tile on the bag bar")
	eq(tile.text.text, "15/16")
	eq(W.BagInfo(5).icon, "icon-35")
	W.Hide()
	stub.now = stub.now + 1
	ToggleBag(5)
	ok(W.IsShown(), "the reagent bag's own tile opens the Pathwise window")
	issecretvalue = nil
end)

test("bags: no reagent bag in the client, nothing read for one", function()
	local stub, ns, b = bags(function(s) s.bags[5] = { { itemID = 204, quality = 1 } } end)
	eq(b.Items.REAGENT_BAG, nil)
	eq(#b.Items.BAGS, 5, "bags 0-4 only")
	for _, x in ipairs(b.Items.Scan()) do ok(x.bag ~= 5, "bag 5 not read") end
	b.Set("bags.bagBar", true)
	b.Window.Show()
	eq(#b.Window.BagBar().slots, 5, "five tiles")
end)

test("bags window: separate bags, where the backpack key runs ToggleBag itself", function()
	local stub, ns, b = bags(function()
		-- Forever's ToggleBackpack_Individual: the backpack through ToggleBag(0),
		-- which builds a bag frame of the game's (no open hook runs).
		function ToggleBag() end
		function ToggleBackpack() ToggleBag(0) end
	end)
	local W = b.Window
	ToggleBackpack()
	ok(W.IsShown(), "one press: open, not opened and closed again")
	stub.now = stub.now + 1
	ToggleBackpack()
	ok(not W.IsShown(), "the next press closes it")
	stub.now = stub.now + 1
	ToggleBag(1)
	ok(W.IsShown(), "a bag tile opens it")
	stub.now = stub.now + 1
	ToggleBackpack()
	ok(not W.IsShown(), "and the backpack key, a moment later, closes it")
end)

test("bags window: each item button is the game's for its own bag and slot (selling, tooltips)", function()
	local stub, ns, b = bags(function()
		-- Forever's ContainerFrameItemButtonMixin: Initialize(containerFrame, bag, slot).
		local make = CreateFrame
		function CreateFrame(kind, name, parent, template)
			local f = make(kind, name, parent, template)
			if template == "ContainerFrameItemButtonTemplate" then
				function f:Initialize(containerFrame, bag, slot)
					self.initialized = true
					self.bagID = bag
					self:SetID(slot)
				end
				function f:GetBagID() return rawget(self, "bagID") or self:GetParent():GetID() end
			end
			return f
		end
	end)
	local W = b.Window
	OpenAllBags()
	local seen = 0
	for _, f in ipairs(stub.frames) do
		if rawget(f, "pwSlot") then
			seen = seen + 1
			eq(f:GetBagID(), f.pwBag, "the button's bag")
			eq(f:GetID(), f.pwSlot, "the button's slot")
			ok(not rawget(f, "initialized"), "Initialize left alone: nothing of ours on the game's button")
		end
	end
	ok(seen >= 8, "every item has its button: " .. seen)
end)


---------------------------------------------------------------------------
-- Its own minimap button, settings and slash command
---------------------------------------------------------------------------

test("bags: its own minimap button, in its own green, and /pwbags", function()
	local stub, ns, b = bags()
	local btn = _G.PathwiseBagsMinimapButton
	ok(btn and btn.shown, "a minimap button")
	btn.scripts.OnClick(btn, "LeftButton")
	ok(b.Window.IsShown(), "click: the bag window")
	btn.scripts.OnClick(btn, "LeftButton")
	ok(not b.Window.IsShown(), "and closes it")
	btn.scripts.OnClick(btn, "RightButton")
	ok(contains(stub.texts(), "Use the Pathwise bag window"), "right-click: the options")
	b.Set("minimap.shown", false)
	ok(not btn.shown, "its own switch")
	SlashCmdList.PATHWISEBAGS("")
	ok(b.Window.IsShown(), "/pwbags opens the bag window")
	eq(PathwiseBagsSettings.bags, nil, "nothing stored that is a default")
	b.Set("bags.columns", 14)
	eq(PathwiseBagsSettings.bags.columns, 14, "kept in its own saved variables")
	eq(type(PathwiseSettings.bags), "nil", "not in Pathwise's")
end)

test("bags: settings and marks kept in Pathwise from before are carried over once", function()
	local stub, ns, b = bags(function(_, pw)
		pw.Set("bags.sellAuto", true)
		pw.Set("bags.columns", 16)
		pw.Set("bags.minimap", false)
		pw.CharState().bags = { marks = { [206] = "keep", [204] = "junk" } }
	end)
	eq(b.Get("bags.sellAuto"), true, "a setting")
	eq(b.Get("bags.columns"), 16)
	eq(b.Get("minimap.shown"), false, "the minimap switch, by its new name")
	eq(b.Items.MarkOf(206), "keep", "a mark")
	eq(b.Items.MarkOf(204), "junk")
	-- Changed after: the copy is not made again.
	b.Items.Mark(206, nil)
	b.Set("bags.columns", 12)
	b.S.ImportFromPathwise()
	eq(b.Items.MarkOf(206), nil, "a mark cleared stays cleared")
	eq(b.Get("bags.columns"), 12)
end)

---------------------------------------------------------------------------
-- On its own: no Pathwise installed
---------------------------------------------------------------------------

test("bags alone: loads without Pathwise; junk, the game's quest items, selling, the window and its options", function()
	local stub, b = alone(function(s)
		-- The game says the Ghoul Rib is for a quest in your log.
		function C_Container.GetContainerItemQuestInfo(bag, slot)
			local i = s.bags[bag] and s.bags[bag][slot]
			if i and i.itemID == 203 then return { isQuestItem = true, questID = 777, isActive = true } end
			return { isQuestItem = false, isActive = false }
		end
		function C_QuestLog.GetTitleForQuestID(q) return q == 777 and "Rib Hunt" or nil end
	end)
	eq(rawget(_G, "Pathwise"), nil, "no Pathwise")
	local junk = slotOf(b, 201)
	ok(junk.facts.tags.junk and junk.facts.sell, "grey with a price: junk")
	local rib = slotOf(b, 203)
	eq(rib.facts.category, "quest")
	ok(rib.facts.tags.quest and not rib.facts.sell, "a quest in your log needs it")
	eq(rib.facts.why, "Needed for Rib Hunt", "named by the game")
	eq(slotOf(b, 204).facts.category, "profession", "trade goods, by the game's item class")
	ok(not slotOf(b, 204).facts.tags.profession, "no profession routes without Pathwise")
	local hood = slotOf(b, 102)
	eq(hood.facts.category, "equipment", "no upgrades without Pathwise Gear")
	ok(not hood.facts.sell and not slotOf(b, 103).facts.sell, "gear is never sold without Pathwise Gear to judge it")
	b.Items.Mark(206, "keep")
	stub.merchant = true
	stub.fire("MERCHANT_SHOW")
	local btn = b.Sell.Button
	ok(btn and btn.shown and btn.pwText.text:find("^Sell junk: 2"), btn and btn.pwText.text)
	btn.scripts.OnClick(btn)
	eq(stub.money, 3 * 12 + 7, "the two greys sold")
	ok(lastPrint(stub):find("Sold 2 items for 43c"), lastPrint(stub))
	stub.fire("MERCHANT_CLOSED")
	b.Window.Hide()
	stub.now = stub.now + 1
	OpenAllBags()
	ok(b.Window.IsShown(), "the bag key opens the Pathwise window")
	local list = {}
	for _, g in ipairs(b.Window.Groups("categories")) do list[#list + 1] = g.name end
	-- The greys are sold; the no-price grey and the kept one are not junk.
	eq(table.concat(list, ","), "Quest,Equipment,Professions,Other,Empty")
	SlashCmdList.PATHWISEBAGS("options")
	ok(contains(stub.texts(), "Install Pathwise: Leveling & Professions to mark items"), "the options say what Pathwise adds")
	ok(contains(stub.texts(), "With Pathwise Gear installed, upgrades"))
end)

test("bags alone: no quest data, no gear and no errors when the game says nothing either", function()
	local stub, b = alone()
	for _, e in ipairs(b.Items.Scan()) do ok(e.facts and e.facts.category, "facts for every item") end
	eq(slotOf(b, 203).facts.category, "quest", "the game's Quest item class")
	ok(not slotOf(b, 203).facts.sell, "and not sold")
	eq(b.S.QuestName(42), "Quest 42", "no name anywhere: a number")
	local room = b.Space.MakeRoom()
	eq(room[1].facts.tags.junk, true, "junk first to go")
	b.Window.Show()
	b.Set("bags.view", "bags")
	b.Set("bags.bagBar", true)
	b.Window.Refresh()
	ok(b.Window.IsShown())
end)

local function read(path)
	local f = assert(io.open(path, "rb"), "missing " .. path)
	local s = f:read("*a")
	f:close()
	return s
end

test("bags alone: its shared files are Pathwise UI's, copied unchanged (npm run kit); every file in its TOC", function()
	for _, name in ipairs({ "Core.lua", "Theme.lua", "Anim.lua", "Widgets.lua", "Movers.lua", "Options.lua", "Minimap.lua" }) do
		local copy = read("Pathwise_Bags/Kit/" .. name)
		local body = copy:gsub("^%-%- COPIED from [^\n]*\n%-%- Edit [^\n]*\n", "", 1)
		ok(body ~= copy, name .. ": has the COPIED header")
		ok(body == read("PathwiseUI/" .. name), name .. " differs from PathwiseUI/" .. name .. ": run npm run kit")
	end
	local toc = read("Pathwise_Bags/Pathwise_Bags.toc")
	ok(toc:find("## OptionalDeps: Pathwise, PathwiseUI, Pathwise_Gear", 1, true), "works on its own")
	ok(not toc:find("## Dependencies", 1, true), "needs nothing")
	local listed = {}
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line ~= "" then
			ok(io.open("Pathwise_Bags/" .. line:gsub("\\", "/")), "Pathwise_Bags.toc lists a missing file: " .. line)
			listed[line:gsub("\\", "/")] = true
		end
	end
	local cmd = package.config:sub(1, 1) == "\\" and 'dir /s /b "Pathwise_Bags\\*.lua" 2>nul' or 'find Pathwise_Bags -name "*.lua"'
	local p = io.popen(cmd)
	local n = 0
	for line in p:lines() do
		local rel = line:gsub("\\", "/"):match("Pathwise_Bags/(.+%.lua)$")
		if rel then n = n + 1 ok(listed[rel], "not in the TOC: " .. rel) end
	end
	p:close()
	ok(n > 0, "found its files")
	-- Every glyph the bag window draws is in its own Media.
	for _, g in ipairs({ "best", "lock", "search", "sort", "zones", "bag", "coin", "quest", "upgrade", "prof", "settings", "close" }) do
		ok(io.open("Pathwise_Bags/Media/glyph-" .. g .. ".tga"), "Media/glyph-" .. g .. ".tga")
	end
end)

test("bags alone with Pathwise Gear alone: it finds Gear's upgrades and best in slot", function()
	local stub, b = alone(function(stub) stub.loadAddon(".", "Pathwise_Gear") end)
	eq(rawget(_G, "Pathwise"), nil, "no Pathwise")
	ok(_G.PathwiseGear and _G.PathwiseGear.Gear, "Pathwise Gear loaded")
	eq(b.S.Gear(), _G.PathwiseGear.Gear, "Bags reads Gear's own")
	eq(b.S.GearBest(), _G.PathwiseGear.Best, "and its best in slot")
end)
