-- Tests for your HoTs on the healing frames: an icon each with the time left
-- between fights (red and blinking near the end), and the game's own HoTs in
-- a fight, when Forever hides auras from addons.
local h = ...
local test, eq, near, ok, fresh = h.test, h.eq, h.near, h.ok, h.fresh

local HOTS = "HELPFUL|PLAYER|RAID_IN_COMBAT"

-- A font string's color (the stub lets T.Paint take the texture branch).
local function color(fs) return fs.textColor or fs.color end

-- A priest with a party member, the game's aura anchors recorded, and
-- "in combat" as the stub's flag.
local function setup(auras)
	return function(s)
		s.player.class = "PRIEST"
		s.units.player.class = "PRIEST"
		s.units.party1 = { name = "Lumen", class = "WARRIOR", player = true, health = 600, max = 1000 }
		s.auras.party1 = auras
		s.anchors, s.removed = {}, {}
		C_UnitAuras.AddPrivateAuraAnchor = function(args)
			local id = #s.anchors + 1
			local a = {}
			for k, v in pairs(args.parent.attrs or {}) do a[k] = v end
			s.anchors[id] = { args = args, attrs = a }
			return id
		end
		C_UnitAuras.RemovePrivateAuraAnchor = function(id) s.removed[id] = true end
		C_RestrictedActions = { IsAddOnRestrictionActive = function() return s.combat end }
		Enum.AddOnRestrictionType = { Combat = 1 }
	end
end

local function frame(ns, unit)
	local b = CreateFrame("Button")
	ns.Heal.NewButton(b)
	ns.Heal.SetUnit(b, unit)
	return b
end

-- The anchor that draws HoTs (buffs on, debuffs off) for this frame.
local function hotAnchor(stub, b)
	for id, a in ipairs(stub.anchors) do
		if a.args.parent == b.gameHots and not stub.removed[id] then return a, id end
	end
end

local function done()
	C_RestrictedActions = nil
end

test("hots: the time left on each, counting down without UNIT_AURA", function()
	local stub, ns = fresh(setup({
		[HOTS] = {
			{ auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12.2 }, -- Renew, 12.2 s left
			{ auraInstanceID = 2, icon = 136081, duration = 0, expirationTime = 0 }, -- no duration: not a HoT
		},
		["HELPFUL|PLAYER"] = {
			{ auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12.2 }, -- the same Renew again
			{ auraInstanceID = 3, icon = 135940, duration = 30, expirationTime = 75 }, -- a shield
			{ auraInstanceID = 4, icon = 135987, duration = 1800, expirationTime = 1800 }, -- Fortitude: too long
		},
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.hots[1].shown and b.hots[1].texture == 135953, "Renew first")
	ok(b.hots[2].shown and b.hots[2].texture == 135940, "then the shield, Renew not twice")
	ok(not b.hots[3].shown, "no permanent or hour-long buff")
	eq(b.hots[1].pwText.text, "13", "12.2 s left, rounded up")
	eq(b.hots[2].pwText.text, "2m", "75 s left")
	eq(b.hots[1].w, 14, "14 px icons by default")
	ok(H.Ticker() and H.Ticker().shown, "the timer runs while a countdown shows")
	local white = ns.Theme.Color("text")
	near(color(b.hots[1].pwText)[1], white[1], 1e-6, "plain while there's time")
	eq(b.hots[1].alpha, 1)
	-- Time passes: the timer redraws the text, no event needed.
	stub.now = 9.5
	stub.advance(0.2)
	eq(b.hots[1].pwText.text, "3", "2.7 s left")
	local red = ns.Theme.Color("error")
	near(color(b.hots[1].pwText)[1], red[1], 1e-6, "red near the end")
	ok(b.hots[1].pwWarn, "marked as running out")
	local dimmest = 1
	for i = 1, 10 do
		stub.now = 9.5 + i * 0.05
		stub.advance(0.1)
		dimmest = math.min(dimmest, b.hots[1].alpha)
	end
	ok(dimmest < 0.7, "it blinks: alpha down to " .. dimmest)
	near(color(b.hots[2].pwText)[1], white[1], 1e-6, "the shield still has time")
	-- It runs out: UNIT_AURA redraws the frame without it, and the timer stops.
	stub.auras.party1 = {}
	H.Update(b) -- as UNIT_AURA does for a shown frame
	ok(not b.hots[1].shown and not b.hots[2].shown, "gone")
	ok(not H.Ticker().shown, "the timer stops")
	ok(next(H.live) == nil, "nothing counting down")
	done()
end)

test("hots: at most three, and the time format fits an icon", function()
	local list = {}
	for i = 1, 5 do list[i] = { auraInstanceID = i, icon = 100 + i, duration = 12, expirationTime = 10 } end
	local _, ns = fresh(setup({ [HOTS] = list }))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	eq(#b.hots, 3)
	ok(b.hots[3].shown and b.hots[3].texture == 103, "three")
	local F = ns.Heal.FormatLeft
	eq(F(0.4), "1")
	eq(F(9), "9")
	eq(F(59.5), "60")
	eq(F(61), "2m")
	eq(F(0), "")
	eq(F(nil), "")
	near(ns.Heal.WarnAt(15), 3, 1e-9, "the last 3 s")
	near(ns.Heal.WarnAt(6), 2, 1e-9, "a short one: its last third")
	done()
end)

test("hots: in a fight the game draws them, with its own countdown; ours come back after", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.hots[1].shown, "ours between fights")
	ok(not hotAnchor(stub, b), "no game HoTs between fights: their icons would take the clicks")
	-- The fight starts: ours step aside (auras can't be read), the game's come.
	stub.fire("PLAYER_REGEN_DISABLED")
	stub.combat = true
	ok(not b.hots[1].shown, "ours hidden")
	ok(not H.Ticker().shown, "no timer of ours in a fight")
	local a, id = hotAnchor(stub, b)
	ok(a, "a game anchor for HoTs")
	eq(a.attrs["max-buffs"], 3)
	eq(a.attrs["ignore-buffs"], false, "buffs on")
	eq(a.attrs["ignore-debuffs"], true, "debuffs off (the other anchor draws cleanses)")
	eq(a.attrs["ignore-dispel-debuffs"], true)
	eq(a.attrs["max-debuffs"], 0)
	eq(a.args.unitToken, "party1")
	eq(a.args.isContainer, true)
	eq(a.args.showCountdownNumbers, true, "the game's countdown")
	eq(a.args.showCooldownFrame, true)
	eq(a.args.iconInfo.iconWidth, 14)
	eq(a.args.iconInfo.iconAnchor.point, "TOPRIGHT", "where ours are")
	H.Update(b) -- an aura changes mid-fight
	local again, id2 = hotAnchor(stub, b)
	eq(id2, id, "the same anchor, not a new one each update")
	eq(#stub.anchors, 2, "one for cleanses, one for HoTs")
	-- It ends.
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	ok(b.hots[1].shown, "ours again")
	ok(stub.removed[id] and not hotAnchor(stub, b), "the game's removed")
	ok(H.Ticker().shown)
	done()
end)

test("hots: a frame that gets a new person in a fight follows them", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	stub.fire("PLAYER_REGEN_DISABLED")
	stub.combat = true
	local _, id = hotAnchor(stub, b)
	stub.units.party2 = { name = "Brakk", class = "MAGE", player = true, health = 1, max = 1 }
	ns.Heal.SetUnit(b, "party2")
	local a2, id2 = hotAnchor(stub, b)
	ok(stub.removed[id], "the old one removed")
	eq(a2.args.unitToken, "party2", "a new one for the new person")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	done()
end)

test("hots: a restriction that starts without the combat event hands over at the next tick", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
	}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.hots[1].shown)
	stub.combat = true -- e.g. an encounter
	stub.advance(0.2)
	ok(not b.hots[1].shown, "ours hidden")
	ok(hotAnchor(stub, b), "the game's attached")
	ok(not ns.Heal.Ticker().shown, "and the timer stops")
	done()
end)

test("hots: the settings: no timers, a bigger icon, or none at all", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	eq(ns.Get("heal.hots"), true, "on by default")
	eq(ns.Get("heal.hotTimers"), true, "timers on by default")
	local function fight(fn)
		stub.fire("PLAYER_REGEN_DISABLED")
		stub.combat = true
		fn()
		stub.combat = false
		stub.fire("PLAYER_REGEN_ENABLED")
	end
	ns.Set("heal.hotTimers", false)
	ok(b.hots[1].shown, "the icon stays")
	eq(b.hots[1].pwText.text, "", "no countdown")
	ok(not H.Ticker().shown, "no timer running")
	fight(function() eq(hotAnchor(stub, b).args.showCountdownNumbers, false, "the game's countdown off too") end)
	ns.Set("heal.hotTimers", true)
	ns.Set("heal.hotSize", 18)
	eq(b.hots[1].w, 18, "bigger icons")
	fight(function() eq(hotAnchor(stub, b).args.iconInfo.iconWidth, 18, "the game's too") end)
	ok(H.Ticker().shown, "counting down")
	ns.Set("heal.enabled", false)
	ok(not H.Ticker().shown, "no timer while the frames are off")
	ns.Set("heal.enabled", true)
	ns.Set("heal.hots", false)
	ok(not b.hots[1].shown, "none of ours")
	fight(function() ok(not hotAnchor(stub, b), "nor the game's in a fight") end)
	done()
end)

test("hots: the settings change in a fight: the game's take them at once", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	stub.fire("PLAYER_REGEN_DISABLED")
	stub.combat = true
	local _, id = hotAnchor(stub, b)
	ns.Set("heal.hotTimers", false)
	local a2 = hotAnchor(stub, b)
	ok(stub.removed[id] and a2, "attached again")
	eq(a2.args.showCountdownNumbers, false)
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	done()
end)

test("hots: the options page offers the countdown and the icon size", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	ns.Config.Show("heal")
	local found = {}
	for _, t in ipairs(stub.texts()) do found[t] = true end
	ok(found["Time left on your HoTs"], "the countdown toggle")
	ok(found["HoT icon size"], "the size slider")
	done()
end)
