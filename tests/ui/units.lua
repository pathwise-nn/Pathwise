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
	eq(stub.shown(p.hp), "820", "your health, short")
	eq(p.health.value, 820)
	ok(p.power.value == 600, "your mana")
	near(p.health.barColor[1], 0.25, 1e-6, "your bar in your class color")
end)

test("unit frames: secret health is passed on, never used in sums", function()
	local stub, ns = fresh(withTarget)
	local t = ns.Units.frames.target
	ok(issecretvalue(t.health.value), "the bar holds the secret as it came")
	eq(stub.shown(t.hp), "4.2k", "shortened by the game's AbbreviateNumbers, still secret-safe")
	ns.Set("units.healthText", "both")
	eq(stub.shown(t.hp), "4.2k / 5.0k")
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
	eq(tc.value, 1, "secret times: full while it lasts")
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
	local flags = {}
	local real = f.name.SetFont
	f.name.SetFont = function(self, file, size, fl) flags[#flags + 1] = fl return true end
	ns.Set("units.outline", false)
	eq(flags[#flags], "", "plain")
	ns.Set("units.outline", true)
	eq(flags[#flags], "OUTLINE", "outlined")
	f.name.SetFont = real
end)
