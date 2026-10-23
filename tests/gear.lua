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

test("gear: a Pawn scale string is read, imported and used", function()
	local stub, ns, g = gear()
	local G = g.Gear
	local s, err = G.ParsePawn('( Pawn: v1: "Frost levelling": Class=Mage, Spec=3, Intellect=1.25, SpellDamage=1, CritRating=10, HasteRating=3 )')
	ok(s, err)
	eq(s.name, "Frost levelling")
	eq(s.class, "MAGE")
	near(s.weights.int, 1.25, 1e-9)
	near(s.weights.sp, 1, 1e-9)
	near(s.weights.crit, 10, 1e-9)
	eq(s.ignored[1], "HasteRating", "a stat Classic has not is left out and named")
	local _, bad = G.ParsePawn("hello")
	ok(bad:find("not a Pawn scale"), bad)
	ok(G.ImportScale('( Pawn: v1: "Int only": Class=Mage, Intellect=2 )'))
	local w, name, from = G.Weights()
	eq(from, "imported")
	eq(name, "Int only")
	near(G.Score("item:102"), 12, 1e-9, "6 Intellect x 2")
	G.UseScale(nil)
	eq(select(3, G.Weights()), "pathwise", "back to Pathwise's weights")
end)

test("gear: with Pawn installed, Pawn's own verdict is used", function()
	local stub, ns, g = gear(function()
		function PawnGetItemData(link) return { link = link } end
		function PawnIsItemAnUpgrade(item)
			if item.link == "item:108" then return { { ScaleName = "x", LocalizedScaleName = "Frost (Pawn)", PercentUpgrade = 0.25 } } end
			return nil
		end
	end)
	local G = g.Gear
	eq(G.Source(), "pawn")
	local up, pct, scale, by = G.IsUpgrade("item:108")
	ok(up)
	near(pct, 25, 1e-9)
	eq(scale, "Frost (Pawn)")
	eq(by, "pawn")
	eq((G.IsUpgrade("item:102")), false, "Pawn says nothing about this one")
	ns.Set("gear.source", "pathwise")
	eq(G.Source(), "pathwise", "the player can choose Pathwise's weights")
	eq((G.IsUpgrade("item:102")), true)
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
	ok(contains(texts, "Glyphed Hood"), "an upgrade in the bags")
	-- Paste a scale and import it.
	local input
	for _, f in ipairs(stub.frames) do if rawget(f, "key") == "gear.import" and f.shown then input = f end end
	ok(input, "the paste box")
	input.box:SetText('( Pawn: v1: "Pasted": Class=Mage, Intellect=1 )')
	input.box.scripts.OnTextChanged(input.box, true)
	ok(stub.clickLabel("Import"))
	ok(lastPrint(stub):find('imported "Pasted"'), lastPrint(stub))
	eq(select(2, g.Gear.Weights()), "Pasted")
	-- Choose a spec by hand.
	ok(stub.clickLabel("Fire"))
	eq(ns.Get("gear.spec").MAGE, "fire")
end)
