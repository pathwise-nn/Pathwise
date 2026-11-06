-- Tests for Pathwise Heal's healing frames: off by default, a healer asked once, the
-- frames (health, heals on the way, text, range, dispels, HoTs) with secret
-- values, click-casting, and their options page.
local h = ...
local test, eq, near, ok, fresh = h.test, h.eq, h.near, h.ok, h.fresh

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

local function priest(s)
	s.player.class = "PRIEST"
	s.units.player.class = "PRIEST"
end

-- A frame as the group header would make it, showing `unit`.
local function frame(ns, unit)
	local b = CreateFrame("Button")
	ns.Heal.NewButton(b)
	ns.Heal.SetUnit(b, unit)
	return b
end

test("healing: off by default; a mage is never asked", function()
	local stub, ns = fresh()
	eq(ns.Get("heal.enabled"), false)
	ok(not _G.PathwiseHeal_Prompt, "no question for a mage")
	ok(not (_G.PathwiseHeal_Frames and _G.PathwiseHeal_Frames.shown), "no frames")
end)

test("healing: a healer is asked once; Turn on sets up their class's clicks", function()
	local stub, ns = fresh(priest)
	local p = _G.PathwiseHeal_Prompt
	ok(p and p.shown, "a priest is asked")
	ok(table.concat(stub.texts(), "|"):find("You're playing a Priest", 1, true), table.concat(stub.texts(), " | "))
	ok(stub.clickLabel("Turn on"))
	eq(ns.Get("heal.enabled"), true)
	ok(not p.shown, "the question goes")
	ok(_G.PathwiseHeal_Frames.shown and _G.PathwiseHeal_Header.shown, "frames on")
	eq(_G.PathwiseHeal_Header:GetAttribute("template"), "PathwiseHeal_ButtonTemplate")
	eq(_G.PathwiseHeal_Header:GetAttribute("showSolo"), true)
	local C = ns.HealClicks
	eq(C.Get("1"), "Flash Heal", "left: the quick heal")
	eq(C.Get("shift-2"), "Dispel Magic", "shift + right: cleanse")
	eq(C.Get("2"), "Renew")
	eq(C.Get("ctrl-1"), C.TARGET)
	-- Next login on this character: not asked again.
	ns.Set("heal.enabled", false)
	ns.Fire("READY")
	ok(not p.shown, "asked once")
end)

test("healing: a frame draws health, heals on the way and what's missing, secret values too", function()
	local stub, ns = fresh(function(s)
		priest(s)
		s.units.party1 = { name = "Brakk", class = "WARRIOR", player = true, health = s.Secret(700), max = s.Secret(1000), ptype = "RAGE" }
		UnitGetIncomingHeals = function(u) return u == "party1" and s.Secret(150) or nil end
		UnitHealthMissing = function(u) return s.Secret(300) end
		C_StringUtil = { TruncateWhenZero = function(v) local n = v.value or v return s.Secret(n == 0 and "" or ("-" .. n)) end }
	end)
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	eq(stub.shown(b.name), "Brakk")
	ok(issecretvalue(b.health.value), "secret health passed straight to the bar")
	eq(stub.shown(b.value), "-300", "what they need")
	ok(b.incoming.shown and issecretvalue(b.incoming.value), "heals on the way, secret, on their own bar")
	near(b.health.barColor[1], 0.78, 1e-6, "warrior brown")
	eq(b.power:GetAlpha(), 0, "no mana bar for rage")
	stub.units.party1.offline = true
	ns.Heal.Update(b)
	eq(stub.shown(b.value), "Offline")
	ok(not b.incoming.shown)
	ns.Set("heal.color", "green")
	stub.units.party1.offline = false
	ns.Heal.Update(b)
	near(b.health.barColor[1], ns.Theme.Color("success")[1], 1e-6, "green")
	UnitGetIncomingHeals, UnitHealthMissing, C_StringUtil = nil, nil, nil
end)

test("healing: out of range fades, chosen by the game when the answer is secret", function()
	local stub, ns = fresh(function(s)
		priest(s)
		s.units.party1 = { name = "Nimble", class = "ROGUE", player = true, health = 500, max = 1000 }
		UnitInRange = function() return s.Secret(false), true end
		C_CurveUtil = { EvaluateColorValueFromBoolean = function(v, yes, no) return s.Secret(v.value and yes or no) end }
	end)
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(issecretvalue(b.alpha) and b.alpha.value == 0.4, "faded, by the game")
	ns.Set("heal.range", false)
	ns.Heal.Update(b)
	eq(b.alpha, 1)
	UnitInRange, C_CurveUtil = nil, nil
end)

test("healing: debuffs you can cleanse color the edge; HoTs show; nothing read in combat", function()
	local stub, ns = fresh(function(s)
		priest(s)
		s.units.party1 = { name = "Lumen", class = "PRIEST", player = true, health = 900, max = 1000 }
		s.auras.party1 = {
			["HARMFUL|RAID"] = { { dispelName = "Poison", icon = 1 }, { dispelName = "Magic", icon = 2 } },
			["HELPFUL|PLAYER"] = { { icon = 135953, duration = 15 }, { icon = 1, duration = 3600 } },
		}
		C_RestrictedActions = { IsAddOnRestrictionActive = function(id) return s.combat end }
		Enum.AddOnRestrictionType = { Combat = 1 }
	end)
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.dispel.edges[1].shown, "an edge")
	near(b.dispel.edges[1].color[1], ns.Theme.Color("magic")[1], 1e-6, "magic before poison")
	ok(b.hots[1].shown and b.hots[1].texture == 135953, "your Renew")
	ok(not b.hots[2].shown, "an hour-long buff is not a HoT")
	stub.combat = true
	ns.Heal.Update(b)
	ok(not b.hots[1].shown, "in combat auras aren't read")
	C_RestrictedActions = nil
end)

test("healing: clicks are the frame's own attributes, and wait for the end of combat", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "player")
	eq(b:GetAttribute("type1"), "spell")
	eq(b:GetAttribute("spell1"), "Flash Heal")
	eq(b:GetAttribute("type2"), "spell")
	eq(b:GetAttribute("ctrl-type1"), "target")
	eq(b:GetAttribute("type3"), "spell")
	eq(b:GetAttribute("spell3"), "Power Word: Shield")
	eq(C.Parse("  menu "), C.MENU)
	eq(C.Parse(""), nil)
	eq(b:GetAttribute("alt-spell1"), "Prayer of Healing", "the Holy preset's group heal")
	stub.combat = true
	C.Set("alt-1", "Lesser Heal")
	eq(b:GetAttribute("alt-spell1"), "Prayer of Healing", "not changed in combat")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	eq(b:GetAttribute("alt-spell1"), "Lesser Heal", "once combat ends")
	C.Set("1", nil)
	eq(b:GetAttribute("type1"), nil, "cleared")
end)

test("healing: its options page, typing a spell, and move mode", function()
	local stub, ns = fresh(priest)
	ns.Config.Show("heal")
	ok(contains(stub.texts(), "Turn them on to set them up"), "short while off")
	ns.Set("heal.enabled", true)
	local texts = stub.texts()
	ok(contains(texts, "Click-casting") and contains(texts, "Shift + left") and contains(texts, "Heals on the way"), table.concat(texts, " | "))
	ok(stub.clickLabel("By health"))
	eq(ns.Get("heal.color"), "health")
	-- Typing a spell in a box.
	local box
	for _, f in ipairs(stub.frames) do if f.kind == "EditBox" and f.shown and f.parent and f.parent.pwCombo == "alt-2" then box = f end end
	ok(box, "a box for Alt + right")
	box:SetText("Abolish Disease")
	box.scripts.OnEnterPressed(box)
	eq(ns.HealClicks.Get("alt-2"), "Abolish Disease")
	SlashCmdList.PATHWISEHEAL("move")
	ok(ns.Heal.Unlocked(), "/pwheal move: the frames move")
	ok(stub.clickLabel("Done"))
end)

-- Spec presets ------------------------------------------------------------

local function as(class)
	return function(s)
		s.player.class = class
		s.units.player.class = class
	end
end

test("healing presets: every healing spec, one layout, target and menu always reachable", function()
	local _, ns = fresh()
	local C = ns.HealClicks
	local want = { PRIEST = { "holy", "discipline" }, DRUID = { "restoration" }, SHAMAN = { "restoration" }, PALADIN = { "holy" } }
	for class, keys in pairs(want) do
		ok(ns.Heal.HEALERS[class], class .. " is asked")
		local specs = C.Specs(class)
		eq(#specs, #keys, class .. " specs")
		for i, key in ipairs(keys) do
			local s = specs[i]
			eq(s.key, key)
			eq(s.binds["ctrl-1"][1], C.TARGET, class .. " " .. key .. ": ctrl + left targets")
			eq(s.binds["ctrl-2"][1], C.MENU, class .. " " .. key .. ": ctrl + right opens the menu")
			for _, combo in ipairs({ "1", "shift-1", "shift-2", "alt-1" }) do
				ok(s.binds[combo] and #s.binds[combo] > 0, class .. " " .. key .. ": " .. combo)
			end
			for combo in pairs(s.binds) do
				local known = false
				for _, c in ipairs(C.COMBOS) do if c[1] == combo then known = true end end
				ok(known, class .. " " .. key .. ": " .. combo .. " is a combo")
			end
		end
	end
	eq(C.Specs("WARRIOR")[1].key, "support", "non-healers: target and menu")
	eq(C.Specs("MAGE")[1].binds["shift-2"][1], "Remove Lesser Curse")
end)

test("healing presets: each healing class gets its spec's spells", function()
	local cases = {
		{ "DRUID", { ["1"] = "Regrowth", ["2"] = "Rejuvenation", ["shift-2"] = "Remove Curse", ["alt-1"] = "Wild Growth", ["alt-2"] = "Abolish Poison" } },
		{ "SHAMAN", { ["1"] = "Lesser Healing Wave", ["2"] = "Riptide", ["alt-1"] = "Chain Heal", ["shift-2"] = "Cure Poison" } },
		{ "PALADIN", { ["1"] = "Flash of Light", ["2"] = "Holy Shock", ["shift-2"] = "Cleanse", ["alt-1"] = "Oath of Light", ["4"] = "Lay on Hands" } },
		{ "PRIEST", { ["1"] = "Flash Heal", ["2"] = "Renew", ["alt-1"] = "Prayer of Healing", ["4"] = "Prayer of Mending", ["5"] = "Binding Heal" } },
	}
	for _, case in ipairs(cases) do
		local _, ns = fresh(as(case[1]))
		ns.Set("heal.enabled", true)
		for combo, spell in pairs(case[2]) do eq(ns.HealClicks.Get(combo), spell, case[1] .. " " .. combo) end
	end
end)

test("healing presets: Discipline from your talents; choosing a spec swaps its spells, not yours", function()
	local stub, ns = fresh(function(s) as("PRIEST")(s) s.talents = { 21, 0, 0 } end)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local spec, how = C.Spec()
	eq(spec.key, "discipline")
	eq(how, "auto")
	eq(C.Get("2"), "Power Word: Shield", "Discipline: shield on right click")
	eq(C.Get("4"), "Penance")
	C.Set("5", "Resurrection") -- your own
	C.SetSpec("holy")
	eq(C.Get("2"), "Renew", "Holy's right click")
	eq(C.Get("4"), "Prayer of Mending")
	eq(C.Get("5"), "Resurrection", "your own click stays")
	C.SetSpec("auto")
	eq(C.Spec().key, "discipline", "back to your talents")
	-- Shadow points: the first healing spec.
	stub.talents = { 0, 0, 31 }
	C.Data().spec = nil
	eq(C.Spec().key, "holy")
end)

test("healing presets: spells you learn later fill in by themselves; cleared clicks stay empty", function()
	local stub, ns = fresh(function(s)
		as("PRIEST")(s)
		s.spellNames = { ["Lesser Heal"] = true, ["Renew"] = true, ["Power Word: Shield"] = true, ["Dispel Magic"] = true }
	end)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "player")
	eq(C.Get("1"), "Lesser Heal", "the heal you know at this level")
	eq(C.Get("4"), nil, "Prayer of Mending not learned yet")
	eq(C.Get("alt-1"), nil, "nor Prayer of Healing")
	C.Set("alt-2", nil) -- you empty this one
	stub.spellNames["Flash Heal"] = true
	stub.spellNames["Prayer of Mending"] = true
	stub.spellNames["Cure Disease"] = true
	stub.fire("LEARNED_SPELL_IN_SKILL_LINE")
	eq(C.Get("1"), "Flash Heal", "upgraded to the quick heal")
	eq(C.Get("4"), "Prayer of Mending", "the talent, once learned")
	eq(b:GetAttribute("spell4"), "Prayer of Mending", "on the frame too")
	eq(C.Get("alt-2"), nil, "a click you emptied stays empty")
	-- Learned in combat: waits for the end of the fight.
	stub.spellNames["Binding Heal"] = true
	stub.combat = true
	stub.fire("SPELLS_CHANGED")
	eq(b:GetAttribute("spell5"), nil, "not in combat")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	eq(b:GetAttribute("spell5"), "Binding Heal")
end)

test("healing presets: the options page has a spec dropdown and names the talents", function()
	local stub, ns = fresh(as("PALADIN"))
	ns.Set("heal.enabled", true)
	ns.Config.Show("heal")
	local texts = stub.texts()
	ok(contains(texts, "Spec") and contains(texts, "Holy preset"), table.concat(texts, " | "))
	ok(contains(texts, "Holy Shock: Holy talent"), "talent notes")
	ok(contains(texts, "Use the Holy preset"), "the reset button names the spec")
end)

test("help and feedback: the website and Discord, in Pathwise Heal's own options", function()
	local stub, ns = fresh()
	ns.Config.Show("help")
	local found = {}
	for _, f in ipairs(stub.frames) do
		if f.kind == "EditBox" and f.shown and (not f.parent or f.parent.shown) and rawget(f, "text") then found[f.text] = true end
	end
	ok(found["https://pathwise.quest/report"], "the report link")
	ok(found["https://discord.gg/hSDjBrG8EK"], "the Discord invite")
end)
