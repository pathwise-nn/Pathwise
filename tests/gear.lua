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
	ns.Set("gear.bisAlert", false)
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
	ns.Set("gear.bisCrafted", "mine")
	B.Clear()
	ok(head().id ~= 990000, "not mine: left out")
	ns.Set("gear.bisCrafted", "off")
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
	ns.Set("gear.bisSod", false)
	ok(head().id ~= 990000, "Season of Discovery recipes hidden")
end)

test("gear best panel: slot by slot, and the options", function()
	local stub, ns, g = gear()
	withGear(stub)
	g.Best.Clear()
	ns.Fire("SHOW_SETTINGS")
	stub.clickLabelText("Pathwise Gear")
	ok(stub.clickLabelText("Best in Slot (Level)"), "open it from the Gear panel")
	ok(contains(stub.texts(), "BEST IN SLOT (LEVEL)"), "its heading")
	local texts = stub.texts()
	ok(contains(texts, "Head:  Glyphed Hood"), table.concat(texts, " | "))
	ok(contains(texts, "World drop"), "where it comes from")
	ok(contains(texts, "Alert when I pick one up"))
	ok(contains(texts, "Crafted gear") and contains(texts, "Season of Discovery recipes"))
	ok(stub.clickLabel("+3"))
	eq(ns.Get("gear.bisAhead"), 3)
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
	eq(#lines, 1)
	ok(lines[1][1]:find("Pathwise Gear · Frost"), lines[1][1])
	ok(lines[1][2]:find("upgrade · Head"), lines[1][2])
	lines = stub.showTooltip("item:103")
	eq(lines[1][2], "You can't wear this armour")
	ns.Set("gear.tooltip", false)
	eq(#stub.showTooltip("item:102"), 0, "switched off")
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
	ns.Set("gear.bags", false)
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

test("gear panel: in Settings, with spec, stat priority, Pawn import and bag upgrades", function()
	local stub, ns, g = gear(function(s) s.bags[0] = { { itemID = 102 } } end)
	ns.Fire("SHOW_SETTINGS")
	ok(contains(stub.texts(), "PATHWISE SUITE"), "a Pathwise suite section")
	ok(stub.clickLabelText("Pathwise Gear"), "open Pathwise Gear")
	local texts = stub.texts()
	ok(contains(texts, "Scoring with Pathwise's Frost weights"), table.concat(texts, " | "))
	ok(contains(texts, "STAT PRIORITY"))
	ok(contains(texts, "Intellect") and contains(texts, "Spell damage"))
	ok(contains(texts, "The class guides agree: Hit, Spell power (Frost)"), "the spec's guide order")
	ok(contains(texts, "Glyphed Hood"), "an upgrade in the bags")
	-- Paste a scale and import it.
	local input
	for _, f in ipairs(stub.frames) do if rawget(f, "key") == "gear.import" and f.shown then input = f end end
	ok(input, "the paste box")
	ok(not contains(texts, "Pawn"), "the panel never mentions another addon")
	input.box:SetText('"Pasted": Intellect=1')
	input.box.scripts.OnTextChanged(input.box, true)
	ok(stub.clickLabel("Import"))
	ok(lastPrint(stub):find('imported "Pasted"'), lastPrint(stub))
	eq(select(2, g.Gear.Weights()), "Pasted")
	-- Choose a spec by hand.
	ok(stub.clickLabel("Fire"))
	eq(ns.Get("gear.spec").MAGE, "fire")
end)
