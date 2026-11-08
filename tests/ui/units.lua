-- Tests for Pathwise UI's unit frames: building them, health and power
-- (secret values passed on, never used in sums), colors, auras, cast bars,
-- moving them, hiding the game's frames, and their options.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

local function withTarget(stub)
	stub.units.target = { name = "Gnoll Brute", level = 20, class = "WARRIOR", player = false, reaction = 2,
		health = stub.Secret(4200), max = stub.Secret(5000), power = 0, pmax = 0, ptype = "RAGE" }
end

test("unit frames: you and your target, clickable, in the Pathwise look", function()
	local stub, ns = fresh(function(s)
		PlayerFrame = CreateFrame("Frame", "PlayerFrame")
		TargetFrame = CreateFrame("Frame", "TargetFrame")
		withTarget(s)
	end)
	local U = ns.Units
	local p, t = U.frames.player, U.frames.target
	ok(p and t, "player and target frames")
	eq(p:GetAttribute("unit"), "player")
	eq(p:GetAttribute("*type1"), "target", "left-click targets")
	eq(p:GetAttribute("*type2"), "togglemenu", "right-click: the menu")
	ok(stub.watched[t], "the target frame shows and hides with the target (in combat too)")
	ok(not stub.watched[p], "yours is always there")
	eq(stub.shown(p.name), "Frozen")
	eq(stub.shown(p.hp), "820 / 1.0k", "your health out of your most, so it says what it is")
	eq(p.health.value, 820)
	ok(p.power.value == 600, "your mana")
	near(p.health.barColor[1], 0.25, 1e-6, "your bar in your class color")
	ok(stub.shown(p.mark):find("LEVEL", 1, true), "the level over the frame, not against the name: " .. tostring(stub.shown(p.mark)))
	ok(not p.level.shown, "no number beside the name")
end)

test("unit frames: slim (the default): name and health on the dark ground over slim bars", function()
	local stub, ns = fresh()
	local p = ns.Units.frames.player
	eq(ns.Get("units.style"), "slim")
	eq(p.name.parent, p, "the name on the frame, not on the bar")
	ok((p.health.h or 0) <= 6, "a slim health bar: " .. tostring(p.health.h))
	ok((p.power.h or 0) <= 3, "a thin power bar")
	near(p.health.barColor[1], 0.25, 1e-6, "the class color at full strength")
end)

test("unit frames: slim: your mana beside your health, in the mana color, off the bar", function()
	local stub, ns = fresh()
	local p = ns.Units.frames.player
	ok(p.pp.shown, "the power number shows")
	eq(p.pp.parent, p, "on the dark ground, not on the thin bar")
	eq(stub.shown(p.pp), "600 / 900", "current / most, as the health")
	eq(stub.shown(p.hp), "820 / 1.0k")
	local mana = ns.Theme.Color("mana")
	near((p.pp.textColor or p.pp.color)[1], mana[1], 1e-6, "in the mana color")
	eq(p.hp.points[#p.hp.points][2], p.pp, "the health number just before it")
	ns.Set("units.powerText", false)
	ok(not p.pp.shown, "switched off")
	eq(p.hp.points[#p.hp.points][2], p.health, "and the health number back at the right")
end)

test("unit frames: health and power as numbers, percent or both", function()
	local stub, ns = fresh()
	local p = ns.Units.frames.player
	ns.Set("units.powerFormat", "percent")
	eq(stub.shown(p.pp), "67%", "600 of 900 mana")
	ns.Set("units.powerFormat", "full")
	eq(stub.shown(p.pp), "600 / 900  \194\183  67%", "numbers and percent")
	ns.Set("units.powerFormat", "current")
	eq(stub.shown(p.pp), "600")
	ns.Set("units.healthText", "full")
	ok(tostring(stub.shown(p.hp)):find("820 / 1.0k", 1, true), "health numbers, and the percent when the client gives one: " .. tostring(stub.shown(p.hp)))
end)

test("unit frames: a monster without mana shows no power number", function()
	local stub, ns = fresh(withTarget)
	eq(stub.shown(ns.Units.frames.target.pp), "", "not 0 / 0")
end)

test("unit frames: your own buffs and debuffs on your frame, curses in their color", function()
	local stub, ns = fresh(function(s)
		s.auras.player = {
			HELPFUL = { { icon = 135932, auraInstanceID = 31 } },
			HARMFUL = { { icon = 136139, auraInstanceID = 32, dispelName = "Curse" } },
		}
	end)
	local f = ns.Units.frames.player
	ok(f.buffs and f.auras, "your frame has a buff row and a debuff row")
	ok(f.buffs.icons[1].shown and not f.buffs.icons[2].shown, "your buff")
	ok(f.auras.icons[1].shown, "your curse")
	local curse = ns.Theme.Color("curse")
	local edge = f.auras.icons[1].pwBorder
	ok(edge and edge.color and math.abs(edge.color[1] - curse[1]) < 1e-6, "framed in the curse color")
	ns.Set("units.onlyMyDebuffs", true)
	ok(f.auras.icons[1].shown, "only-my-debuffs leaves your own frame alone")
end)

test("unit frames: combo points over your target's frame, for rogues and cat druids", function()
	local stub, ns = fresh(function(s) withTarget(s) s.player.class = "ROGUE" s.units.player.ptype = "ENERGY" s.combo = 3 end)
	local U = ns.Units
	local t = U.frames.target
	ok(t.combo and t.combo.shown, "the pips show for a rogue")
	ok(not U.frames.player.combo, "not on your own frame: on Forever they are on the target")
	local filled = 0
	for i = 1, 5 do
		local p = t.combo.pips[i]
		ok(p.shown, "pip " .. i)
		eq(p.min, i - 1) eq(p.max, i)
		if p.value == i then filled = filled + 1 end
	end
	eq(filled, 3, "three points, three pips full")
	ok(not t.combo.pips[6].shown, "five pips, as the game says")
	stub.combo = 5
	stub.fire("COMBO_TARGET_CHANGED")
	eq(t.combo.pips[5].value, 5, "a new count on the event")
	-- A secret count still fills them: the bar is given it as it is.
	stub.combo = stub.Secret(2)
	stub.fire("UNIT_POWER_UPDATE", "player", "COMBO_POINTS")
	ok(issecretvalue(t.combo.pips[1].value), "secret count passed on")
	-- A druid only in cat form.
	stub.combo = 1
	stub.player.class = "DRUID" stub.units.player.ptype = "MANA"
	stub.fire("UNIT_DISPLAYPOWER", "player")
	ok(not t.combo.shown, "a druid out of cat form: none")
	stub.units.player.ptype = "ENERGY"
	stub.fire("UNIT_DISPLAYPOWER", "player")
	ok(t.combo.shown, "in cat form")
	-- The option switches them off, and mages have none.
	ns.Set("units.comboPoints", false)
	ok(not t.combo.shown, "switched off")
	ns.Set("units.comboPoints", true)
	stub.player.class = "MAGE"
	stub.fire("COMBO_TARGET_CHANGED")
	ok(not t.combo.shown, "not for a mage")
end)

test("unit frames: a light class color is drawn a shade deeper, so the text reads", function()
	local _, ns = fresh()
	local U = ns.Units
	local white = U.Readable({ 1, 1, 1 })
	ok(white[1] < 0.7 and math.abs(white[1] - white[2]) < 1e-9, "priest white: a grey white text reads on")
	local mage = { 0.25, 0.78, 0.92 }
	eq(U.Readable(mage), mage, "a mid color as it is")
end)

test("unit frames: full bars: the power number fits its bar and says how much of how much", function()
	local stub, ns = fresh()
	ns.Set("units.style", "full")
	local p = ns.Units.frames.player
	ok(p.pp.shown, "shown")
	ok((p.power.h or 0) >= 12, "the bar is tall enough for the number: " .. tostring(p.power.h))
	ok(tostring(stub.shown(p.pp)):find(" / ", 1, true), "current / most: " .. tostring(stub.shown(p.pp)))
end)

test("unit frames: secret health is passed on, never used in sums", function()
	local stub, ns = fresh(withTarget)
	local t = ns.Units.frames.target
	ok(issecretvalue(t.health.value), "the bar holds the secret as it came")
	eq(stub.shown(t.hp), "4.2k / 5.0k", "shortened by the game's AbbreviateNumbers, still secret-safe")
	ns.Set("units.healthText", "current")
	eq(stub.shown(t.hp), "4.2k")
	near(t.health.barColor[1], ns.Theme.Hex("#E66B78")[1], 1e-6, "a hostile monster in red")
end)

test("unit frames: dead and offline", function()
	local stub, ns = fresh(function(s)
		s.units.party1 = { name = "Florp", level = 20, class = "ROGUE", player = true, health = 0, max = 900, offline = true }
	end)
	local f = ns.Units.frames.party1
	ok(f, "a party frame")
	eq(stub.shown(f.hp), "Offline")
	stub.units.party1.offline = false
	stub.units.party1.dead = true
	ns.Units.Update(f)
	eq(stub.shown(f.hp), "Dead")
end)

test("unit frames: debuffs on the target, timers only when readable", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		s.auras.target = { HARMFUL = {
			{ icon = 136207, applications = 3, duration = 18, expirationTime = 30, auraInstanceID = 11, dispelName = "Magic" },
			{ icon = s.Secret(135812), applications = s.Secret(1), duration = s.Secret(10), expirationTime = s.Secret(20), auraInstanceID = 12 },
		} }
	end)
	local a = ns.Units.frames.target.auras
	ok(a.icons[1].shown and a.icons[2].shown, "both shown")
	ok(not a.icons[3].shown)
	eq(a.icons[1].count.text, 3, "a readable stack count")
	eq(a.icons[2].count.text, "", "a secret count left out")
	ok(a.icons[1].cd == nil or a.icons[1].cd.shown ~= false, "a readable timer spins")
	ok(issecretvalue(a.icons[2].icon.texture), "a secret icon passed on")
	ns.Set("units.auras", false)
	ok(not a.icons[1].shown, "switched off")
end)

test("unit frames: the target's buffs in a row, its debuffs under them", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		s.auras.target = {
			HELPFUL = { { icon = 135987, auraInstanceID = 21 }, { icon = s.Secret(136078), auraInstanceID = 22 } },
			HARMFUL = { { icon = 136207, auraInstanceID = 11 } },
		}
	end)
	local f = ns.Units.frames.target
	ok(f.buffs, "the target has a buff row")
	ok(f.buffs.icons[1].shown and f.buffs.icons[2].shown and not f.buffs.icons[3].shown, "its two buffs shown")
	ok(f.auras.icons[1].shown, "and its debuff")
	local function y(b) local p = b.points[#b.points] return p[5] end
	ok(y(f.auras.icons[1]) < y(f.buffs.icons[1]), "the debuffs under the buffs")
	stub.auras.target.HELPFUL = {}
	stub.fire("UNIT_AURA", "target")
	ok(not f.buffs.icons[1].shown, "no buffs: none shown")
	eq(y(f.auras.icons[1]), y(f.buffs.icons[1]), "and the debuffs move up into their place")
	ok(ns.Units.frames.party1 == nil or ns.Units.frames.party1.buffs == nil, "party frames keep debuffs only")
	ns.Set("units.auras", false)
	stub.auras.target.HELPFUL = { { icon = 135987, auraInstanceID = 21 } }
	stub.fire("UNIT_AURA", "target")
	ok(not f.buffs.icons[1].shown, "switched off with the debuffs")
end)

test("unit frames: cast bars fill by time, or stay full when the times are secret", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		s.casts.player = { name = "Frostbolt", texture = 135846, start = 1000, finish = 3000 }
		s.casts.target = { name = "Bash", texture = 132337, start = s.Secret(1000), finish = s.Secret(2000) }
	end)
	local pc, tc = ns.Units.frames.player.castbar, ns.Units.frames.target.castbar
	ok(pc.shown and stub.shown(pc.text) == "Frostbolt")
	stub.now = 2
	pc.scripts.OnUpdate(pc)
	near(pc.value, 0.5, 1e-6, "half way through")
	ok(tc.shown and stub.shown(tc.text) == "Bash")
	ok(tc.secretRange and issecretvalue(tc.secretRange[1]), "secret times: the cast is the bar's range, passed on as it came")
	tc.scripts.OnUpdate(tc)
	eq(tc.value, 2000, "and the bar is given the time now, so the game fills it")
	stub.casts.player = nil
	ns.Units.UpdateCast(ns.Units.frames.player)
	ok(pc.shown, "it fades out rather than vanishing")
	stub.advance(0.5)
	ok(not pc.shown, "gone when the cast ends")
	-- Interrupted: red, "Interrupted", then gone.
	stub.casts.target = nil
	stub.fire("UNIT_SPELLCAST_INTERRUPTED", "target")
	eq(stub.shown(tc.text), "Interrupted")
	near(tc.barColor[1], ns.Theme.Color("error")[1], 1e-6, "in the bad color")
	stub.advance(1)
	ok(not tc.shown, "then gone")
	eq(tc.max, 1, "back to a plain bar")
end)

test("unit frames: an enemy's cast with secret times runs smoothly in seconds", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		s.now = 1000
		s.casts.target = { name = "Bash", texture = 132337, start = s.Secret(1000000), finish = s.Secret(1002500) }
		s.durations.target = { start = 1000, total = 2.5, secret = true }
	end)
	local tc = ns.Units.frames.target.castbar
	ok(tc.shown and stub.shown(tc.text) == "Bash")
	ok(tc.secretRange, "the range is the cast's length")
	eq(tc.secretRange[1], 0, "from nothing")
	eq(tc.secretRange[2].value, 2.5, "to its length in seconds, not the clock in milliseconds")
	stub.now = 1001
	tc.scripts.OnUpdate(tc)
	ok(issecretvalue(tc.value) and tc.value.value == 1, "each frame, the seconds gone")
	stub.now = 1001.016
	tc.scripts.OnUpdate(tc)
	near(tc.value.value, 1.016, 1e-9, "a frame later, a frame further: no steps")
	stub.casts.target = nil
	stub.durations.target = nil
	ns.Units.UpdateCast(ns.Units.frames.target)
	stub.advance(1)
	eq(tc.max, 1, "a plain bar again after")
	ok(not tc.pwDur)
end)

test("unit frames: an enemy's channel with secret times drains smoothly", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		s.now = 50
		function UnitChannelInfo(u)
			if u == "target" then return "Drain Life", "Drain Life", 136169, s.Secret(50000), s.Secret(55000), false, false end
		end
		s.durations.target = { start = 50, total = 5, secret = true, channel = true }
	end)
	local tc = ns.Units.frames.target.castbar
	eq(tc.secretRange[2].value, 5, "the channel's length in seconds")
	stub.now = 52
	tc.scripts.OnUpdate(tc)
	eq(tc.value.value, 3, "the seconds left, so it drains")
	ok(tc.fillStyle ~= "REVERSE" and not tc.track.shown, "a plain bar does it")
end)

test("unit frames: an enemy's channel with secret times drains", function()
	local stub, ns = fresh(function(s)
		withTarget(s)
		function UnitChannelInfo(u)
			if u == "target" then return "Drain Life", "Drain Life", 136169, s.Secret(1000), s.Secret(6000), false, false end
		end
	end)
	local tc = ns.Units.frames.target.castbar
	ok(tc.shown and stub.shown(tc.text) == "Drain Life")
	ok(tc.secretRange, "the channel is the bar's range")
	eq(tc.fillStyle, "REVERSE", "filled from the right")
	ok(tc.track.shown, "over the cast's color, so what is left shrinks")
	UnitChannelInfo = function() return nil end
	ns.Units.UpdateCast(ns.Units.frames.target)
	stub.advance(1)
	eq(tc.fillStyle, "STANDARD", "a plain bar again after")
	ok(not tc.track.shown)
end)

test("unit frames: move them, put them back, sizes from the options", function()
	local stub, ns = fresh(withTarget)
	local U = ns.Units
	local p = U.frames.player
	ok(U.Unlock(true), "unlocked")
	ok(not stub.watched[U.frames.target] and U.frames.target.shown, "every frame shown to be moved")
	ns.Set("units.PlayerPoint", { "CENTER", "CENTER", -100, -50 })
	U.Place(p)
	local pt = p.points[#p.points]
	eq(pt[4], -100)
	U.Unlock(false)
	ok(stub.watched[U.frames.target], "locked: back to showing with its unit")
	U.ResetPositions()
	pt = p.points[#p.points]
	eq(pt[4], -300, "back to where it was")
	ns.Set("units.PlayerW", 280)
	eq(p.w, 280, "wider")
	stub.combat = true
	ok(not U.Unlock(true), "not in combat")
	stub.combat = false
end)

test("unit frames: the game's own frames put away, ours switched off", function()
	local stub, ns = fresh(function()
		PlayerFrame = CreateFrame("Frame", "PlayerFrame")
		PetFrame = CreateFrame("Frame", "PetFrame")
	end)
	local U = ns.Units
	ok(U.Hidden()[PlayerFrame], "the game's player frame put away")
	ok(PlayerFrame.parent ~= UIParent, "under a hidden frame")
	ns.Set("units.player", false)
	ok(not U.frames.player.shown, "ours off")
	ns.Set("units.enabled", false)
	for _, f in pairs(U.frames) do ok(not f.shown, "all off") end
end)

test("unit frames: their page in the options", function()
	local stub, ns = fresh()
	ns.Config.Show("units")
	local texts = stub.texts()
	ok(contains(texts, "Pathwise unit frames") and contains(texts, "Your party") and contains(texts, "Health text"), table.concat(texts, " | "))
	ok(stub.clickLabel("Percent"))
	eq(ns.Get("units.healthText"), "percent")
	ok(stub.clickLabel("Move the frames"))
	ok(ns.Units.Unlocked())
	ok(stub.clickLabel("Lock the frames"))
	ok(not ns.Units.Unlocked())
end)

test("unit frames: names and numbers outlined in black, or a shadow when off", function()
	local stub, ns = fresh()
	local f = ns.Units.frames.player
	ns.Set("units.style", "full") -- text on the bars: outlined; slim text sits on the dark ground
	local flags = {}
	local real = f.name.SetFont
	f.name.SetFont = function(self, file, size, fl) flags[#flags + 1] = fl return true end
	ns.Set("units.outline", false)
	eq(flags[#flags], "", "plain")
	ns.Set("units.outline", true)
	eq(flags[#flags], "OUTLINE", "outlined")
	f.name.SetFont = real
end)

test("your cast bar: over the topmost action bar, the game's silenced; under your frame; or the game's", function()
	local unregistered = false
	local stub, ns = fresh(function()
		PlayerCastingBarFrame = CreateFrame("StatusBar", "PlayerCastingBarFrame")
		function PlayerCastingBarFrame:UnregisterAllEvents() unregistered = true end
	end)
	local U, B = ns.Units, ns.Bars
	local cb = U.frames.player.castbar
	local top = U.TopBar()
	ok(top and B.bars[top.def.id] == top, "a bottom bar to sit on")
	eq(cb.parent, UIParent, "off your frame")
	eq(cb.points[1][2], top, "anchored to the topmost bar")
	eq(cb.points[1][1], "BOTTOMLEFT")
	ok(unregistered and not PlayerCastingBarFrame.shown, "the game's cast bar silenced, not moved")
	ns.Set("units.castbarSpot", "frame")
	eq(cb.parent, U.frames.player, "under your frame")
	eq(cb.points[1][2], U.frames.player)
	ns.Set("units.castbarSpot", "game")
	stub.units.player.casting = { "Bolt of Linen Cloth" }
	U.UpdateCast(U.frames.player)
	ok(not cb.shown, "the game's: Pathwise's stays hidden")
end)
