-- Tests for Pathwise_Gear: weights, scoring, wearing rules, Pawn scale
-- strings, Pawn's own verdicts when installed, the tooltip line, bag arrows,
-- quest reward picks and the panel. Loaded by tests/run.lua.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local INT, SP, STR, AGI, STA, DPS = "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPELL_DAMAGE_DONE_SHORT", "ITEM_MOD_STRENGTH_SHORT",
	"ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_DAMAGE_PER_SECOND_SHORT"

-- Item facts: { name, quality, ilvl, sell, classID, subclassID, equipLoc, minLevel }
local ITEMS = {
	[101] = { { "Worn Cloth Hood", 1, 10, 5, 4, 1, "INVTYPE_HEAD", 5 }, { [INT] = 2 } },
	[102] = { { "Glyphed Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }, { [INT] = 6, [STA] = 2 } },
	[103] = { { "Iron Helm", 2, 18, 40, 4, 4, "INVTYPE_HEAD", 13 }, { [STR] = 8, [STA] = 6 } },
	[104] = { { "Frost Dagger", 2, 20, 60, 2, 15, "INVTYPE_WEAPON", 14 }, { [INT] = 3, [SP] = 4, [DPS] = 8 } },
	[105] = { { "Elder Staff", 2, 22, 70, 2, 10, "INVTYPE_2HWEAPON", 15 }, { [INT] = 8, [SP] = 7, [DPS] = 14 } },
	[106] = { { "Mail Gloves", 2, 18, 30, 4, 3, "INVTYPE_HAND", 13 }, { [INT] = 9 } },
	[107] = { { "Hood of Ages", 2, 25, 90, 4, 1, "INVTYPE_HEAD", 30 }, { [INT] = 12 } },
	[108] = { { "Silk Cowl", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }, { [INT] = 4 } },
}

local function gear(setup)
	local stub, ns = fresh()
	stub.player.level = 20
	for id, d in pairs(ITEMS) do stub.itemInfo[id], stub.itemStats[id] = d[1], d[2] end
	stub.equipped[1] = 101 -- the worn hood on the head
	if setup then setup(stub) end
	local g = stub.loadAddon(".", "Pathwise_Gear")
	stub.moveTo(1420, 60, 52)
	stub.login()
	return stub, ns, g
end

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

test("gear: Pathwise's weights for every class and spec, scaled so the best stat is 1", function()
	local _, _, g = gear()
	local W = g.Weights
	for class, list in pairs({ WARRIOR = 3, PALADIN = 3, HUNTER = 3, ROGUE = 3, PRIEST = 3, SHAMAN = 3, MAGE = 3, WARLOCK = 3, DRUID = 3 }) do
		eq(#W.Specs(class), list, class)
		for _, s in ipairs(W.Specs(class)) do
			local w = W.For(class, s.key)
			local top = 0
			for _, k in ipairs({ "str", "agi", "int", "sta", "spi", "sp", "heal", "ap", "rap" }) do top = math.max(top, w[k] or 0) end
			near(top, 1, 1e-9, class .. " " .. s.key)
		end
	end
	local arms = W.For("WARRIOR", "arms")
	ok(arms.str > arms.agi and arms.agi > 0, "Strength over Agility for a Warrior")
	ok(not arms.int, "no Intellect for a Warrior")
	ok(arms.dps > 5, "weapon DPS counts a lot")
	local frost = W.For("MAGE", "frost")
	ok(frost.sp > 0 and frost.int > 0 and not frost.str, "a Frost Mage: spell damage and Intellect, no Strength")
	ok(frost.spFrost == frost.sp, "frost damage counts like spell damage")
end)

test("gear: each spec's weights keep the order the Forever class guides give", function()
	local _, _, g = gear()
	local F = g.Weights.For
	local function above(class, spec, a, b) local w = F(class, spec); ok((w[a] or 0) > (w[b] or 0), ("%s %s: %s over %s"):format(class, spec, a, b)) end
	-- Melee: weapon damage first, then Hit, then Crit.
	for _, cs in ipairs({ { "WARRIOR", "arms" }, { "WARRIOR", "fury" }, { "ROGUE", "combat" }, { "PALADIN", "retribution" }, { "SHAMAN", "enhancement" } }) do
		above(cs[1], cs[2], "hit", "crit")
		ok(F(cs[1], cs[2]).expertise, cs[2] .. " values Expertise")
	end
	above("ROGUE", "assassination", "agi", "str")
	above("WARRIOR", "arms", "str", "agi")
	-- Forever's changes the guides point out.
	above("DRUID", "feral", "str", "agi")
	above("HUNTER", "survival", "dps", "rdps")
	above("HUNTER", "marksmanship", "int", "spi")
	ok(F("HUNTER", "marksmanship").int > F("HUNTER", "beastmastery").int, "Careful Aim: Marksmanship values Intellect most")
	above("SHAMAN", "enhancement", "int", "agi")
	above("PALADIN", "retribution", "int", "agi")
	above("PALADIN", "protection", "sp", "int")
	above("WARLOCK", "affliction", "spi", "int")
	above("WARLOCK", "destruction", "haste", "spi")
	above("MAGE", "arcane", "spi", "int")
	above("PRIEST", "holy", "spi", "int")
	above("PRIEST", "shadow", "sp", "int")
	above("DRUID", "balance", "int", "spi")
	-- Forever's stat rules: one crit for spells and melee; gear's attack power counts for ranged.
	for _, cs in ipairs({ { "MAGE", "frost" }, { "PRIEST", "shadow" }, { "WARLOCK", "affliction" }, { "SHAMAN", "restoration" } }) do
		local w = F(cs[1], cs[2])
		ok(w.crit and w.crit == w.spellCrit, cs[2] .. ": plain crit counts like spell crit")
	end
	local bm = F("HUNTER", "beastmastery")
	eq(bm.ap, bm.rap, "a Hunter values attack power like ranged attack power")
end)

test("gear: Haste and Expertise on an item are read and scored", function()
	local _, _, g = gear(function(s)
		s.itemInfo[109] = { "Swift Band", 2, 20, 30, 4, 0, "INVTYPE_FINGER", 15 }
		s.itemStats[109] = { ITEM_MOD_HASTE_RATING_SHORT = 1, ITEM_MOD_EXPERTISE_RATING_SHORT = 2 }
	end)
	local st = g.Gear.Stats("item:109")
	eq(st.haste, 1)
	eq(st.expertise, 2)
end)

-- Best in Slot (Level): test items given a source in Pathwise's gear data
-- (a world drop), as tools/data/build.lua writes them.
local function withGear(stub)
	local G = Pathwise.Suite.Data.gear
	G[102] = { 13, 18, 4, 1, nil, nil, nil, true }
	G[108] = { 13, 18, 4, 1, nil, nil, nil, true }
	G[107] = { 30, 25, 4, 1, nil, nil, nil, true }
	G[103] = { 13, 18, 4, 4, nil, nil, nil, true }
	G[104] = { 14, 20, 2, 15, nil, nil, nil, true }
end

test("gear best: the best per slot for my level, and where it comes from", function()
	local stub, ns, g = gear()
	withGear(stub)
	local B = g.Best
	B.Clear()
	local list = B.List()
	local head
	for _, e in ipairs(list) do if e.slot == 1 then head = e end end
	ok(head, "a head piece")
	eq(head.id, 102, "Glyphed Hood beats Silk Cowl, plate is left out, Hood of Ages needs 30")
	eq(B.SourceText(head.source), "World drop (random monsters)")
	ok(head.pct and head.pct > 0, "better than the worn hood")
	for _, e in ipairs(list) do ok(e.id ~= 103, "no plate for a mage") end
	-- Looking 10 levels ahead (the panel offers up to +5; ListFor takes any).
	local ahead = B.ListFor(30)
	for _, e in ipairs(ahead) do if e.slot == 1 then eq(e.id, 107, "at 30 the Hood of Ages") end end
	-- Is it the best? For my level, for the level it needs, or not at all.
	eq(B.IsBest(102), 20)
	eq(select(2, B.IsBest(102)), "Head")
	eq(B.IsBest(108), nil, "Silk Cowl is not")
	eq(B.IsBest(107), 30, "the best at the level it needs")
	eq(B.IsBest(103), nil, "plate: never for a mage")
end)

test("gear best: items the game has not loaded are asked for", function()
	local stub, ns, g = gear()
	withGear(stub)
	stub.uncached[108] = true
	g.Best.Clear()
	local _, pending = g.Best.List()
	ok(pending >= 1, "one still loading")
	ok(stub.requested[108], "asked the game for it")
end)

test("gear best: picking one up is announced on screen, with a sound and in chat", function()
	local stub, ns, g = gear(function(s) s.bags[0] = { { itemID = 101 } } end)
	withGear(stub)
	g.Best.Clear()
	g.Best.CheckBags() -- the first look only counts
	eq(#stub.notices, 0)
	stub.bags[0][2] = { itemID = 108 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.notices, 0, "Silk Cowl is not the best: no alert")
	stub.bags[0][3] = { itemID = 102 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(stub.notices[1], "Best in slot for your level: Glyphed Hood (Head)")
	eq(stub.sounds[1], 8959)
	ok(lastPrint(stub):find("best in slot for your level"), lastPrint(stub))
	stub.bags[0][4] = { itemID = 107 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(stub.notices[2], "Best in slot for level 30: Hood of Ages (Head)", "and up: the level it needs")
	g.Set("gear.bisAlert", false)
	stub.bags[0][5] = { itemID = 104 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.notices, 2, "switched off")
end)

test("gear best: a star in the bags and a line on the tooltip", function()
	local stub, ns, g = gear(function(s) s.bags[0] = { { itemID = 102 }, { itemID = 108 } } end)
	withGear(stub)
	g.Best.Clear()
	local b1, b2 = stub.bagButton(1), stub.bagButton(2)
	ContainerFrameCombinedBags:UpdateItems()
	local function star(b)
		for _, f in ipairs(stub.frames) do
			if f.parent == b and rawget(f, "texture") and f.texture:find("glyph%-best") then return f end
		end
	end
	ok(star(b1) and star(b1).shown, "a star on the Glyphed Hood")
	ok(not star(b2) or not star(b2).shown, "none on the Silk Cowl")
	local lines = stub.showTooltip("item:102")
	ok(lines[1][2]:find("^Best in slot · %+"), lines[1][2])
	lines = stub.showTooltip("item:107")
	eq(lines[1][2], "Best in slot for level 30")
end)

-- Crafted: a cloth helm Tailoring makes at 110 (spell 990001, taught by
-- recipe item 990002, sold by a vendor of the data), better than any other.
local function withCraft(stub, opts)
	opts = opts or {}
	local D = Pathwise.Suite.Data
	stub.itemInfo[990000] = { "Tailored Cap", 2, 20, 50, 4, 1, "INVTYPE_HEAD", opts.req or 15 }
	stub.itemStats[990000] = { ITEM_MOD_INTELLECT_SHORT = 10 }
	local vendor
	for id, n in pairs(D.npcs) do if n[5] and not n[4] then vendor = id break end end
	D.items[990002] = { "Pattern: Tailored Cap", nil, nil, { vendor } }
	D.gear[990000] = { opts.req or 15, 20, 4, 1, nil, nil, nil, nil, nil, { 197, 110, 990001, 990002, opts.sod, opts.bop } }
	return vendor
end

test("gear best: crafted gear, by anyone or by me, with its recipe", function()
	local stub, ns, g = gear()
	withGear(stub)
	local vendor = withCraft(stub)
	local B = g.Best
	B.Clear()
	local function head() for _, e in ipairs(B.List()) do if e.slot == 1 then return e end end end
	eq(head().id, 990000, "the crafted cap is the best head")
	eq(head().source.kind, "craft")
	ok(B.SourceText(head().source):find("^Crafted: Tailoring 110 %(Auction House"), B.SourceText(head().source))
	eq(B.Chase(head()), false, "nowhere to point when you are not the crafter")
	-- With Tailoring: my craft, its recipe from the vendor, and the arrow there.
	stub.skills[197] = { 90, 150 }
	B.Clear()
	local text = B.SourceText(head().source)
	ok(text:find("^Craft it at Tailoring 110 %(you have 90%)"), text)
	ok(text:find("Pattern: Tailored Cap from "), text)
	ok(B.Chase(head()), "the arrow goes to the pattern's vendor")
	-- Mine only, without the profession: gone.
	stub.skills[197] = nil
	g.Set("gear.bisCrafted", "mine")
	B.Clear()
	ok(head().id ~= 990000, "not mine: left out")
	g.Set("gear.bisCrafted", "off")
	stub.skills[197] = { 120, 150 }
	B.Clear()
	ok(head().id ~= 990000, "crafted gear off")
end)

test("gear best: bind on pickup crafts are only yours; Season of Discovery recipes can be hidden", function()
	local stub, ns, g = gear()
	withGear(stub)
	withCraft(stub, { bop = true, sod = true })
	local B = g.Best
	local function head() B.Clear() for _, e in ipairs(B.List()) do if e.slot == 1 then return e end end end
	ok(head().id ~= 990000, "binds on pickup: no one can sell it to you")
	stub.skills[197] = { 120, 150 }
	eq(head().id, 990000, "but you can make it")
	ok(B.SourceText(head().source):find("Season of Discovery recipe: found in Forever, not confirmed"), B.SourceText(head().source))
	g.Set("gear.bisSod", false)
	ok(head().id ~= 990000, "Season of Discovery recipes hidden")
end)

-- A page of Gear's own options window: its rows, and their texts.
local function page(g, key)
	for _, c in ipairs(g.Config.CATEGORIES) do
		if c.key == key then
			local rows = c.rows()
			local texts = {}
			for _, r in ipairs(rows) do
				if type(r[2]) == "string" then texts[#texts + 1] = r[2] end
				if r[1] == "toggle" or r[1] == "dropdown" or r[1] == "choice" then texts[#texts + 1] = r[r[1] == "toggle" and 4 or 5] end
			end
			return rows, texts
		end
	end
end
local function row(rows, kind, label)
	for _, r in ipairs(rows) do if r[1] == kind and tostring(r[2]):find(label, 1, true) then return r end end
end

test("gear best page: slot by slot, and the options", function()
	local stub, ns, g = gear()
	withGear(stub)
	g.Best.Clear()
	SlashCmdList.PATHWISEGEAR("best")
	ok(_G.PathwiseGearConfig and _G.PathwiseGearConfig.shown, "/pwgear best opens Gear's own window")
	eq(g.Config.Current(), "best", "on Best in Slot")
	local rows, texts = page(g, "best")
	ok(contains(texts, "Best in Slot (Level)"), "its heading")
	ok(row(rows, "button", "Head:  Glyphed Hood"), table.concat(texts, " | "))
	ok(contains(texts, "World drop"), "where it comes from")
	ok(row(rows, "toggle", "Alert when I pick one up"))
	ok(row(rows, "choice", "Crafted gear") and row(rows, "toggle", "Season of Discovery recipes"))
	eq(row(rows, "choice", "Look ahead")[3], "gear.bisAhead")
	row(rows, "button", "Head:  Glyphed Hood")[3]()
	ok(lastPrint(stub):find("World drop"), lastPrint(stub))
end)

-- An item card on a page: by its name, and (when given) its corner note.
local function card(rows, title, corner)
	for _, r in ipairs(rows) do
		if r[1] == "item" and r[3].title == title and (not corner or r[3].corner == corner) then return r end
	end
end

test("gear hunts: one slot's best, ranked, with two-handers in the main hand", function()
	local stub, ns, g = gear()
	withGear(stub)
	Pathwise.Suite.Data.gear[105] = { 15, 22, 2, 10, nil, nil, nil, true }
	local B = g.Best
	B.Clear()
	local head = B.Ranked(1)
	eq(#head, 2, "Glyphed Hood and Silk Cowl: plate left out, Hood of Ages needs 30")
	eq(head[1].id, 102)
	eq(head[1].rank, 1)
	eq(head[2].id, 108)
	ok(head[1].pct > head[2].pct, "the best gains most on the worn hood")
	local main = B.Ranked(16)
	local two
	for _, e in ipairs(main) do if e.id == 105 then two = e end end
	ok(two and two.slotName == "Two-hand", "the staff, in the main hand's list")
	-- Looking ahead.
	g.Set("gear.bisAhead", 10)
	B.Clear()
	eq(B.Ranked(1)[1].id, 107, "at 30 the Hood of Ages first")
end)

test("gear hunts: right-click a slot, track the best, and hear when you have it", function()
	local stub, ns, g = gear(function(s)
		CharacterHeadSlot = CreateFrame("Button", "CharacterHeadSlot")
		CharacterHeadSlot:SetScript("OnClick", function() end)
		s.bags[0] = { { itemID = 101 } }
	end)
	withGear(stub)
	g.Best.Clear()
	local H = g.Hunts
	CharacterHeadSlot.scripts.OnClick(CharacterHeadSlot, "LeftButton")
	ok(not (_G.PathwiseGearConfig and _G.PathwiseGearConfig.shown), "a left-click is the game's")
	CharacterHeadSlot.scripts.OnClick(CharacterHeadSlot, "RightButton")
	ok(_G.PathwiseGearConfig and _G.PathwiseGearConfig.shown, "a right-click opens Gear's window")
	eq(g.Config.Current(), "hunts")
	eq(H.slot, 1)
	local drawn
	for _, f in ipairs(stub.frames) do if rawget(f, "text") == "Glyphed Hood" then drawn = f end end
	ok(drawn and drawn.shown, "its card is drawn in the window")
	local rows, texts = page(g, "hunts")
	ok(contains(texts, "Best for your head"), table.concat(texts, " | "))
	local first = card(rows, "Glyphed Hood")
	ok(first and card(rows, "Silk Cowl"), "a card each")
	eq(first[2], "item:102", "the item, for its icon and tooltip")
	ok(first[3].sub:find("^#1  ·  level 13  ·  World drop"), first[3].sub)
	ok(card(rows, "Silk Cowl")[3].sub:find("^#2"))
	ok(first[3].corner:find("^%+%d+%%$"), first[3].corner)
	eq(first[3].mark, false, "an unlit diamond")
	first[3].onClick("LeftButton")
	ok(H.IsTracked(102), "tracked")
	ok(lastPrint(stub):find("tracking Glyphed Hood"), lastPrint(stub))
	rows, texts = page(g, "hunts")
	ok(card(rows, "Glyphed Hood", "SHOW THE WAY"), "in Tracking")
	local ranked = card(rows, "Glyphed Hood", "TRACKING")
	ok(ranked and ranked[3].chosen and ranked[3].mark == true, "chosen, its diamond lit")
	-- Picked up: done, on screen and in chat, and no other alert for it.
	local notices = #stub.notices
	stub.bags[0][2] = { itemID = 102 }
	stub.items[102] = 1
	stub.fire("BAG_UPDATE_DELAYED")
	eq(stub.notices[notices + 1], "Hunt done: Glyphed Hood (Head)")
	eq(#stub.notices, notices + 1, "not best in slot too")
	ok(lastPrint(stub):find("hunt done"), lastPrint(stub))
	ok(not H.IsTracked(102))
	eq(#H.Done(), 1)
	rows, texts = page(g, "hunts")
	ok(contains(texts, "Done (1)"))
	-- Already yours: nothing to track.
	eq(H.Track(g.Best.Ranked(1)[1]), false)
	-- Switched off: the right-click is the game's alone.
	g.Set("gear.slotClick", false)
	g.Config.Show("gear")
	CharacterHeadSlot.scripts.OnClick(CharacterHeadSlot, "RightButton")
	eq(g.Config.Current(), "gear")
	CharacterHeadSlot = nil
end)

test("gear hunts: hide one that is not for you, and show it again", function()
	local stub, ns, g = gear()
	withGear(stub)
	local B, H = g.Best, g.Hunts
	B.Clear()
	H.Track(B.Ranked(1)[1])
	card(page(g, "hunts"), "Glyphed Hood", "SHOW THE WAY")[3].onClick("RightButton")
	ok(not H.IsTracked(102), "hidden: no longer tracked")
	eq(B.Ranked(1)[1].id, 108, "out of the slot's list")
	for _, e in ipairs(B.List()) do if e.slot == 1 then eq(e.id, 108, "and out of Best in Slot") end end
	local rows = page(g, "hunts")
	card(rows, "Glyphed Hood", "SHOW AGAIN")[3].onClick("LeftButton")
	eq(B.Ranked(1)[1].id, 102, "back")
end)

test("gear: an item better than what is worn is an upgrade, by how much and where", function()
	local stub, ns, g = gear()
	local G = g.Gear
	local up, pct, slot, by = G.IsUpgrade("item:102")
	eq(by, "pathwise")
	ok(up, "Glyphed Hood beats the worn hood")
	ok(pct > 100, ("+%.1f%%"):format(pct))
	eq(slot, "Head")
	eq((G.IsUpgrade("item:101")), false, "the hood worn is not an upgrade over itself")
	eq((G.IsUpgrade("item:108")), true, "Silk Cowl too")
	ok(select(2, G.IsUpgrade("item:102")) > select(2, G.IsUpgrade("item:108")), "the bigger gain is bigger")
end)

test("gear: what a class can wear and when", function()
	local stub, ns, g = gear()
	local G = g.Gear
	local usable, reason = G.Usable("item:103")
	eq(usable, false, "plate on a mage")
	eq(reason, "armor")
	eq((G.Usable("item:104")), true, "a dagger is fine")
	eq((G.IsUpgrade("item:103")), false)
	local _, why, level = G.Usable("item:107")
	eq(why, "level")
	eq(level, 30)
	eq((G.IsUpgrade("item:107")), false, "not wearable yet: not an upgrade")
end)

test("gear: an empty slot is filled; a two-hander is weighed against both hands", function()
	local stub, ns, g = gear(function(s) s.equipped[16] = 104 end)
	local G = g.Gear
	local up, pct, slot = G.IsUpgrade("item:106")
	eq(up, false, "mail gloves: a mage can't")
	local r = G.Compare("item:105")
	near(r.old, G.Score("item:104"), 1e-9, "the staff against the dagger (no off hand)")
	stub.equipped[17] = 104
	G.Clear()
	r = G.Compare("item:105")
	near(r.old, 2 * G.Score("item:104"), 1e-9, "and against both hands when both are full")
end)

test("gear: custom weights are read, imported and used", function()
	local stub, ns, g = gear()
	local G = g.Gear
	local p = G.ParseScale("Intellect=1.5, Stamina=0.5, Haste=4")
	ok(p, "a plain list")
	near(p.weights.int, 1.5, 1e-9)
	near(p.weights.haste, 4, 1e-9)
	eq(p.name, "Custom weights")
	eq(G.ParseScale('"Tank": Stamina=1, Defense=2').name, "Tank")
	local s, err = G.ParseScale('( Pawn: v1: "Frost levelling": Class=Mage, Spec=3, Intellect=1.25, SpellDamage=1, CritRating=10, HasteRating=3, FireResistance=1 )')
	ok(s, err)
	eq(s.name, "Frost levelling")
	eq(s.class, "MAGE")
	near(s.weights.int, 1.25, 1e-9)
	near(s.weights.sp, 1, 1e-9)
	near(s.weights.crit, 10, 1e-9)
	near(s.weights.haste, 3, 1e-9, "Haste, a Forever stat, is read")
	eq(s.ignored[1], "FireResistance", "a stat Pathwise does not score is left out and named")
	local _, bad = G.ParseScale("hello")
	ok(bad:find("No stats Pathwise knows"), bad)
	ok(G.ImportScale('( Pawn: v1: "Int only": Class=Mage, Intellect=2 )'))
	local w, name, from = G.Weights()
	eq(from, "imported")
	eq(name, "Int only")
	near(G.Score("item:102"), 12, 1e-9, "6 Intellect x 2")
	G.UseScale(nil)
	eq(select(3, G.Weights()), "pathwise", "back to Pathwise's weights")
end)

test("gear: scores on its own, even with another gear addon loaded", function()
	local called = false
	local stub, ns, g = gear(function()
		function PawnGetItemData() called = true end
		function PawnIsItemAnUpgrade() called = true end
	end)
	local G = g.Gear
	local up, pct, slot, by = G.IsUpgrade("item:102")
	ok(up)
	eq(by, "pathwise")
	ok(not called, "no other addon is asked")
	ok(not G.Source and not G.PawnUpgrade, "no bridge left")
	PawnGetItemData, PawnIsItemAnUpgrade = nil, nil
end)

test("gear: the tooltip line", function()
	local stub, ns, g = gear()
	local lines = stub.showTooltip("item:102")
	eq(#lines, 2)
	ok(lines[1][1]:find("Pathwise Gear · Frost"), lines[1][1])
	ok(lines[1][2]:find("big upgrade · Head"), lines[1][2])
	eq(lines[2][2], "Intellect +4, Stamina +2", "the stats that make it so, the one worth most first")
	lines = stub.showTooltip("item:103")
	eq(lines[1][2], "You can't wear this armour")
	g.Set("gear.tooltip", false)
	eq(#stub.showTooltip("item:102"), 0, "switched off")
end)

-- Two more hoods, beside the Glyphed Hood (6 Intellect, 2 Stamina): the same,
-- and a little better.
local function hoods(stub)
	stub.itemInfo[109], stub.itemStats[109] = { "Twin Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }, { [INT] = 6, [STA] = 2 }
	stub.itemInfo[111], stub.itemStats[111] = { "Sturdy Hood", 2, 18, 40, 4, 1, "INVTYPE_HEAD", 13 }, { [INT] = 6, [STA] = 3 }
end

test("gear: verdicts in steps: big, up, about the same, worse, later, can't", function()
	local stub, ns, g = gear(hoods)
	local G = g.Gear
	eq(G.Verdict("item:102").grade, "big", "6 Intellect over 2: a big upgrade")
	stub.equipped[1] = 102
	G.Clear()
	local up = G.Verdict("item:111")
	eq(up.grade, "up", "one more Stamina")
	ok(up.pct > 1 and up.pct < G.BIG, tostring(up.pct))
	eq(up.changes[1].key, "sta")
	eq(G.Verdict("item:109").grade, "same", "the same stats")
	eq(G.Verdict("item:108").grade, "worse")
	eq(G.Verdict("item:107").grade, "later", "better, from level 30")
	eq(G.Verdict("item:107").minLevel, 30)
	eq(G.Verdict("item:103").grade, "cant")
	eq(G.Verdict("item:102").grade, "equipped")
	ok(not G.IsUpgrade("item:107"), "not an upgrade until you can wear it")
	-- On the tooltip.
	eq(stub.showTooltip("item:109")[1][2], "About the same (+0.0%)")
	ok(stub.showTooltip("item:107")[1][2]:find("^Upgrade at level 30 %(%+"), stub.showTooltip("item:107")[1][2])
	ok(stub.showTooltip("item:108")[1][2]:find("worse"))
	ok(stub.showTooltip("item:111")[1][2]:find("^%+%d+%.%d%% upgrade · Head$"), stub.showTooltip("item:111")[1][2])
	-- A smaller step counts as the same when the smallest upgrade is raised.
	g.Set("gear.minUpgrade", 0.1)
	eq(G.Verdict("item:111").grade, "same")
end)

test("gear: following the talents, the weights mix the trees by their points", function()
	local points = {}
	local stub, ns, g = gear(function()
		C_SpecializationInfo = { GetSpecializationInfo = function(i) return i, "Tree " .. i, "", 0, "", false, points[i] or 0 end }
	end)
	local G, W = g.Gear, g.Weights
	near(G.Weights().sta, W.For("MAGE", "frost").sta, 1e-9, "no talents yet: the levelling spec")
	points = { 0, 5, 15 }
	G.Clear()
	eq(select(2, G.Weights()), "Frost", "named after the tree with most points")
	local w = G.Weights()
	near(w.sta, 0.75 * W.For("MAGE", "frost").sta + 0.25 * W.For("MAGE", "fire").sta, 1e-9, "75% Frost, 25% Fire")
	near(w.mp5, 0.25 * W.For("MAGE", "fire").mp5, 1e-9, "a stat only Fire values counts for its share")
	local mix = G.Mix()
	eq(#mix, 2)
	eq(mix[1].spec.key, "frost")
	near(mix[2].share, 0.25, 1e-9)
	local _, rows = nil, g.Config.CATEGORIES[1].rows()
	local found = false
	for _, r in ipairs(rows) do if r[1] == "text" and tostring(r[2]):find("Your talents mix the weights: Frost 15 %(75%%%), Fire 5 %(25%%%)") then found = true end end
	ok(found, "the page says so")
	-- A spec chosen by hand is used alone.
	G.SetSpec("fire")
	near(G.Weights().sta, W.For("MAGE", "fire").sta, 1e-9, "chosen: Fire's alone")
	C_SpecializationInfo = nil
end)

test("gear: picking up an upgrade says so in chat, with the stats", function()
	local stub, ns, g = gear(function(s) s.bags[0] = { { itemID = 108 } } end)
	local before = #stub.printed
	stub.bags[0][2] = { itemID = 102 }
	stub.fire("BAG_UPDATE_DELAYED")
	ok(#stub.printed > before, "a chat line")
	ok(lastPrint(stub):find("item:102 is a big upgrade %(%+%d+%.%d%%%) for your head: Intellect %+4, Stamina %+2%."), lastPrint(stub))
	-- Not for what was there already, nor what you can't wear.
	before = #stub.printed
	stub.bags[0][3] = { itemID = 103 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.printed, before, "the plate helm: nothing")
	-- Taking off what you wear is not a new item.
	stub.equipped[1] = nil
	stub.bags[0][4] = { itemID = 101 }
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.printed, before, "the hood taken off: nothing")
	-- Switched off.
	g.Set("gear.alert", false)
	stub.bags[0][5] = { itemID = 111 }
	hoods(stub)
	stub.fire("BAG_UPDATE_DELAYED")
	eq(#stub.printed, before, "off: nothing")
end)

test("gear: a gold arrow on bag items that are upgrades", function()
	local stub, ns, g = gear(function(s)
		s.bags[0] = { { itemID = 102 }, { itemID = 103 } }
	end)
	local b1, b2 = stub.bagButton(1), stub.bagButton(2)
	ContainerFrameCombinedBags:UpdateItems()
	local function arrow(b)
		for _, f in ipairs(stub.frames) do
			if f.parent == b and rawget(f, "texture") and f.texture:find("glyph%-upgrade") then return f end
		end
	end
	ok(arrow(b1) and arrow(b1).shown, "the hood is an upgrade")
	ok(not arrow(b2) or not arrow(b2).shown, "the plate helm is not")
	g.Set("gear.bags", false)
	ContainerFrameCombinedBags:UpdateItems()
	eq(arrow(b1).shown, false, "switched off")
end)

test("gear: the best quest reward, in chat and on its tooltip", function()
	local stub, ns, g = gear()
	stub.choices = { 103, 108, 102 }
	stub.fire("QUEST_COMPLETE")
	ok(lastPrint(stub):find("take item:102"), lastPrint(stub))
	local lines = stub.showTooltip("item:102")
	eq(lines[1][2], "Best reward for you")
	stub.fire("QUEST_FINISHED")
	lines = stub.showTooltip("item:102")
	ok(lines[1][2]:find("upgrade"), "the panel closed: back to the comparison")
end)

test("gear page: Upgrades, with spec, stat priority, custom weights and bag upgrades", function()
	local stub, ns, g = gear(function(s) s.bags[0] = { { itemID = 102 } } end)
	ns.Fire("SHOW_SETTINGS")
	ok(contains(stub.texts(), "PATHWISE SUITE"), "a Pathwise suite section")
	ok(stub.clickLabelText("Pathwise Gear"), "listed there")
	ok(_G.PathwiseGearConfig and _G.PathwiseGearConfig.shown, "it opens Gear's own window")
	eq(g.Config.Current(), "gear", "on Upgrades")
	local rows, texts = page(g, "gear")
	ok(contains(texts, "Scoring with Pathwise's Frost weights"), table.concat(texts, " | "))
	ok(contains(texts, "Stat priority"))
	ok(contains(texts, "Intellect") and contains(texts, "Spell damage"))
	ok(contains(texts, "The class guides agree: Hit, Spell power (Frost)"), "the spec's guide order")
	ok(contains(texts, "Glyphed Hood"), "an upgrade in the bags")
	ok(not contains(texts, "Pawn"), "the page never mentions another addon")
	-- Paste a scale and apply it.
	local input = row(rows, "input", "gear.import")
	ok(input, "the paste box")
	eq(input[4]("hello"), false, "nothing it knows: kept in the box")
	eq(input[4]('"Pasted": Intellect=1'), true)
	ok(lastPrint(stub):find('imported "Pasted"'), lastPrint(stub))
	eq(select(2, g.Gear.Weights()), "Pasted")
	rows = page(g, "gear")
	row(rows, "button", 'Stop using "Pasted"')[3]()
	eq(select(3, g.Gear.Weights()), "pathwise", "back to Pathwise's weights")
	-- Choose a spec by hand, then follow the talents again.
	local spec = row(page(g, "gear"), "dropdown", "Spec")
	eq(spec[3].get(), "auto")
	spec[3].set("fire")
	eq(g.Get("gear.spec").MAGE, "fire")
	eq(row(page(g, "gear"), "dropdown", "Spec")[3].get(), "fire")
	row(page(g, "gear"), "dropdown", "Spec")[3].set("auto")
	eq(g.Get("gear.spec").MAGE, nil)
end)

test("gear: settings kept in Pathwise's before are moved over once", function()
	local stub, ns, g = gear(function()
		PathwiseSettings = nil
	end)
	-- As 0.3.3 left them: in Pathwise's settings.
	PathwiseGearSettings, PathwiseGearCharSettings = nil, nil
	ns.Set("gear.tooltip", false)
	ns.Set("gear.spec", { MAGE = "fire" })
	ns.Set("gear.minimap", false)
	ok(g.MoveSettings(), "moved")
	eq(g.Get("gear.tooltip"), false)
	eq(g.Get("gear.spec").MAGE, "fire")
	eq(g.Get("minimap.shown"), false, "the minimap button stays hidden")
	g.Set("gear.tooltip", true)
	ok(not g.MoveSettings(), "only once")
	eq(g.Get("gear.tooltip"), true, "what you set since stays")
end)

---------------------------------------------------------------------------
-- Pathwise's settings panel
---------------------------------------------------------------------------

test("panels: a setting's label never runs under its value or buttons", function()
	local stub, ns = gear()
	ns.Fire("SHOW_SETTINGS")
	stub.clickLabelText("Pathwise Gear")
	local checked = 0
	for _, f in ipairs(stub.frames) do
		local label, buttons = rawget(f, "label"), rawget(f, "buttons")
		if label and type(buttons) == "table" and f.shown and type(rawget(f, "value")) == "table" then
			local used = 0
			for _, bt in ipairs(buttons) do if bt.shown then used = used + bt.w + 4 end end
			local value = f.value.text ~= "" and (#f.value.text * 6 + 8) or 0
			ok(label.w + used + value <= f.w + 1, ("%q fits: %d + %d + %d <= %d"):format(label.text, label.w, used, value, f.w))
			checked = checked + 1
		end
	end
	ok(checked >= 5, "checked the setting rows: " .. checked)
end)

