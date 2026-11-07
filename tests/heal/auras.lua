-- Tests for the buff and debuff rows on the healing frames (Healing/Auras.lua):
-- your HoTs with the time left (red and blinking near the end), the other
-- buffs, the debuffs (the ones you can remove first, a left click casting the
-- spell that does), and the game's own rows in a fight, when Forever hides
-- auras from addons.
local h = ...
local test, eq, near, ok, fresh = h.test, h.eq, h.near, h.ok, h.fresh

local HOTS = "HELPFUL|PLAYER|RAID_IN_COMBAT"

-- A font string's color (the stub lets T.Paint take the texture branch).
local function color(fs) return fs.textColor or fs.color end

-- A player of `class` with a party member, the game's aura anchors recorded,
-- and a restriction (`s.restricted`) apart from combat lockdown (`s.combat`).
local function setup(auras, class)
	return function(s)
		class = class or "PRIEST"
		s.player.class = class
		s.units.player.class = class
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
		C_RestrictedActions = { IsAddOnRestrictionActive = function() return s.combat or s.restricted end }
		Enum.AddOnRestrictionType = { Combat = 1 }
	end
end

local function frame(ns, unit)
	local b = CreateFrame("Button")
	ns.Heal.NewButton(b)
	ns.Heal.SetUnit(b, unit)
	return b
end

-- The game's anchor on this frame, if attached.
local function gameAnchor(stub, b)
	for id, a in ipairs(stub.anchors) do
		if a.args.parent == b.gameAuras and not stub.removed[id] then return a, id end
	end
end

-- A fight: the event, then the lockdown; `fn` runs inside it.
local function fight(stub, fn)
	stub.fire("PLAYER_REGEN_DISABLED")
	stub.combat = true
	fn()
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
end

local function done() C_RestrictedActions = nil end

-- The buff row ------------------------------------------------------------

test("a new frame gets every row, its timers with a font (the game refuses text without one)", function()
	local stub, ns = fresh(setup({}))
	local b = frame(ns, "party1")
	ok(b.buffs and b.otherDebuffs and b.removable, "all three rows made")
	eq(#b.buffs, ns.Heal.MAX_BUFFS)
	eq(#b.otherDebuffs, ns.Heal.MAX_OTHER_DEBUFFS)
	for _, ic in ipairs(b.buffs) do ok(rawget(ic.pwText, "hasFont"), "a timer with a font") end
	-- A frame whose rows were only half made is left alone, not an error on every update.
	b.otherDebuffs, b.removable = nil, nil
	ns.Heal.Auras(b, "party1")
	ns.Heal.PlaceAuras(b)
	done()
end)

test("buff row: your HoTs first, with the time left, counting down without UNIT_AURA", function()
	local stub, ns = fresh(setup({
		[HOTS] = {
			{ auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12.2 }, -- Renew, 12.2 s left
			{ auraInstanceID = 2, icon = 136081, duration = 0, expirationTime = 0 }, -- no duration: not a HoT
		},
		["HELPFUL|PLAYER"] = {
			{ auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12.2 }, -- the same Renew again
			{ auraInstanceID = 3, icon = 135940, duration = 30, expirationTime = 75 }, -- a shield
		},
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.buffs[1].shown and b.buffs[1].texture == 135953, "Renew first")
	ok(b.buffs[2].shown and b.buffs[2].texture == 135940, "then the shield, Renew not twice")
	ok(not b.buffs[3].shown, "nothing else")
	eq(b.buffs[1].pwText.text, "13", "12.2 s left, rounded up")
	eq(b.buffs[2].pwText.text, "2m", "75 s left")
	eq(b.buffs[1].w, 14, "14 px icons by default")
	ok(H.Ticker() and H.Ticker().shown, "the timer runs while a countdown shows")
	local white, red = ns.Theme.Color("text"), ns.Theme.Color("error")
	near(color(b.buffs[1].pwText)[1], white[1], 1e-6, "plain while there's time")
	eq(b.buffs[1].alpha, 1)
	stub.now = 9.5
	stub.advance(0.2)
	eq(b.buffs[1].pwText.text, "3", "2.7 s left")
	near(color(b.buffs[1].pwText)[1], red[1], 1e-6, "red near the end")
	local dimmest = 1
	for i = 1, 10 do
		stub.now = 9.5 + i * 0.05
		stub.advance(0.1)
		dimmest = math.min(dimmest, b.buffs[1].alpha)
	end
	ok(dimmest < 0.7, "it blinks: alpha down to " .. dimmest)
	near(color(b.buffs[2].pwText)[1], white[1], 1e-6, "the shield still has time")
	-- Gone: the next redraw (UNIT_AURA) drops it, and the timer stops.
	stub.auras.party1 = {}
	H.Update(b)
	ok(not b.buffs[1].shown and not b.buffs[2].shown, "gone")
	ok(not H.Ticker().shown, "the timer stops")
	ok(next(H.live) == nil, "nothing counting down")
	done()
end)

test("buff row: then big defensives and your other buffs, three at most", function()
	local _, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
		["HELPFUL|BIG_DEFENSIVE"] = { { auraInstanceID = 5, icon = 132362, duration = 10, expirationTime = 8 } }, -- someone's Shield Wall
		["HELPFUL|PLAYER|RAID"] = {
			{ auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 }, -- Renew again
			{ auraInstanceID = 6, icon = 135987, duration = 1800, expirationTime = 1700 }, -- Fortitude
			{ auraInstanceID = 7, icon = 135932, duration = 1800, expirationTime = 1800 }, -- a fourth: no room
		},
	}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	eq(#b.buffs, 3)
	eq(b.buffs[1].texture, 135953, "the HoT")
	eq(b.buffs[2].texture, 132362, "the big defensive")
	eq(b.buffs[3].texture, 135987, "your Fortitude")
	eq(b.buffs[3].pwText.text, "29m")
	ns.Set("heal.buffs", false)
	ok(b.buffs[1].shown and not b.buffs[2].shown, "only your HoTs")
	ns.Set("heal.buffs", true)
	ns.Set("heal.hots", false)
	eq(b.buffs[1].texture, 132362, "no HoTs first")
	local F = ns.Heal.FormatLeft
	eq(F(0.4), "1")
	eq(F(59.5), "60")
	eq(F(61), "2m")
	eq(F(3601), "2h")
	eq(F(0), "")
	eq(F(nil), "")
	near(ns.Heal.WarnAt(15), 3, 1e-9, "the last 3 s")
	near(ns.Heal.WarnAt(6), 2, 1e-9, "a short one: its last third")
	done()
end)

-- The debuff row ----------------------------------------------------------

test("debuff row: the ones you can remove on the left, in their color; a left click removes it", function()
	local stub, ns = fresh(setup({
		["HARMFUL|RAID"] = {
			{ auraInstanceID = 11, icon = 136139, dispelName = "Curse", applications = 2 },
			{ auraInstanceID = 12, icon = 132104, dispelName = "Poison" },
		},
		HARMFUL = {
			{ auraInstanceID = 11, icon = 136139, dispelName = "Curse" }, -- listed again: only once
			{ auraInstanceID = 13, icon = 136134 }, -- one you can't remove
		},
	}, "DRUID"))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	local d1, d2, d3 = b.removable[1], b.removable[2], b.removable[3]
	ok(d1.shown and d1.icon.texture == 136139, "the curse first")
	near(d1.edge.edges[1].color[1], ns.Theme.Color("curse")[1], 1e-6, "in the curse color")
	eq(d1.count.text, 2, "its stacks")
	eq(d1:GetAttribute("type1"), "spell")
	eq(d1:GetAttribute("spell1"), "Remove Curse", "a left click removes it")
	eq(d2:GetAttribute("spell1"), "Abolish Poison", "the poison: your best poison cure")
	ok(not d3.shown, "two to remove")
	eq(d1:GetAttribute("useparent*"), true, "every other click is the frame's own")
	eq(d1:GetAttribute("shift-type1"), nil, "nothing of its own but the left click")
	ok(b.otherDebuffs[1].shown and b.otherDebuffs[1].texture == 136134, "the one you can't remove, on the right")
	ok(not b.otherDebuffs[2].shown, "and nothing twice")
	ok(b.dispel.edges[1].shown, "the frame's edge too")
	near(b.dispel.edges[1].color[1], ns.Theme.Color("curse")[1], 1e-6, "curse before poison")
	-- No cleanse click: the icon is still there, a left click heals as usual.
	ns.Set("heal.cleanseClick", false)
	ok(d1.shown)
	eq(d1:GetAttribute("type1"), nil, "the frame's own left click")
	ns.Set("heal.cleanseClick", true)
	-- A spell you don't know yet: shown, not cast.
	stub.spellNames = { ["Cure Poison"] = true }
	ns.Heal.Update(b)
	eq(d1:GetAttribute("type1"), nil, "no Remove Curse yet")
	eq(d2:GetAttribute("spell1"), "Cure Poison", "the cure you have")
	-- Off.
	ns.Set("heal.debuffs", false)
	ok(not d1.shown and not b.otherDebuffs[1].shown, "no debuff row")
	ok(b.dispel.edges[1].shown, "the edge is its own setting")
	done()
end)

test("debuff row: each class removes what its spells can", function()
	local _, ns = fresh(setup({}, "PALADIN"))
	local H = ns.Heal
	eq(H.CleanseSpell("Magic"), "Cleanse")
	eq(H.CleanseSpell("Disease"), "Cleanse")
	eq(H.CleanseSpell("Curse"), nil, "paladins can't remove curses")
	local _, ns2 = fresh(setup({}, "PRIEST"))
	eq(ns2.Heal.CleanseSpell("Magic"), "Dispel Magic")
	eq(ns2.Heal.CleanseSpell("Disease"), "Abolish Disease")
	local _, ns3 = fresh(setup({}, "WARRIOR"))
	eq(ns3.Heal.CleanseSpell("Poison"), nil)
	done()
end)

-- In a fight ----------------------------------------------------------------

test("in a fight: the game draws both rows, ours and our clicks step aside; back after", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
		["HARMFUL|RAID"] = { { auraInstanceID = 11, icon = 136139, dispelName = "Magic" } },
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	ok(b.buffs[1].shown and b.removable[1].shown, "ours between fights")
	ok(not gameAnchor(stub, b), "no game rows between fights: their icons would take the clicks")
	local id
	fight(stub, function()
		ok(not b.buffs[1].shown, "our buffs hidden")
		ok(not b.removable[1].shown, "our clickable debuffs hidden before the lockdown")
		eq(b.removable[1]:GetAttribute("type1"), nil, "and their spell cleared")
		ok(not b.dispel.edges[1].shown, "the game colors the edge in a fight")
		ok(not H.Ticker().shown, "no timer of ours")
		local a
		a, id = gameAnchor(stub, b)
		ok(a, "the game's rows")
		eq(#stub.anchors, 1, "one container for both rows")
		eq(a.attrs["aura-organization-type"], 1, "buffs top, debuffs bottom, like ours")
		eq(a.attrs["max-buffs"], 3)
		eq(a.attrs["max-dispel-debuffs"], 3, "the ones you can remove (bottom left)")
		eq(a.attrs["max-debuffs"], 2, "the others (bottom right)")
		eq(a.attrs["ignore-buffs"], false)
		eq(a.attrs["ignore-debuffs"], false)
		eq(a.attrs["ignore-dispel-debuffs"], false)
		eq(a.attrs["display-only-dispellable-debuffs"], false)
		eq(a.attrs["dispel-indicator-option"], 1, "the edge, for what you can remove")
		eq(a.args.unitToken, "party1")
		eq(a.args.isContainer, true)
		eq(a.args.showCountdownNumbers, true, "the game's countdown")
		-- An aura changes, or the frame redraws: the same anchor.
		H.Update(b)
		local _, id2 = gameAnchor(stub, b)
		eq(id2, id, "not a new one each update")
		-- Nothing of ours is touched under lockdown.
		stub.auras.party1["HARMFUL|RAID"] = {}
		H.Update(b)
	end)
	ok(stub.removed[id] and not gameAnchor(stub, b), "the game's rows removed after")
	ok(b.buffs[1].shown, "ours again")
	ok(not b.removable[1].shown, "the debuff it had is gone")
	ok(H.Ticker().shown)
	done()
end)

test("in a fight: a frame that gets a new person follows them", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	fight(stub, function()
		local _, id = gameAnchor(stub, b)
		stub.units.party2 = { name = "Brakk", class = "MAGE", player = true, health = 1, max = 1 }
		ns.Heal.SetUnit(b, "party2")
		local a2 = gameAnchor(stub, b)
		ok(stub.removed[id], "the old one removed")
		eq(a2.args.unitToken, "party2", "a new one for the new person")
	end)
	done()
end)

test("in a fight: a restriction that starts without the combat event hands over at the next tick", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
		["HARMFUL|RAID"] = { { auraInstanceID = 11, icon = 136139, dispelName = "Magic" } },
	}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	stub.restricted = true -- e.g. an encounter, no lockdown yet
	stub.advance(0.2)
	ok(not b.buffs[1].shown and not b.removable[1].shown, "ours hidden")
	ok(gameAnchor(stub, b), "the game's attached")
	ok(not ns.Heal.Ticker().shown, "and the timer stops")
	stub.restricted = false
	done()
end)

-- Settings ------------------------------------------------------------------

test("settings: on by default; timers, sizes and rows, ours and the game's", function()
	local stub, ns = fresh(setup({
		[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
		["HARMFUL|RAID"] = { { auraInstanceID = 11, icon = 136139, dispelName = "Magic" } },
	}))
	local H = ns.Heal
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	for _, k in ipairs({ "hots", "buffs", "timers", "debuffs", "cleanseClick", "dispel" }) do
		eq(ns.Get("heal." .. k), true, k .. " on by default")
	end
	ns.Set("heal.timers", false)
	ok(b.buffs[1].shown, "the icon stays")
	eq(b.buffs[1].pwText.text, "", "no countdown")
	ok(not H.Ticker().shown, "no timer running")
	fight(stub, function() eq(gameAnchor(stub, b).args.showCountdownNumbers, false, "the game's countdown off too") end)
	ns.Set("heal.timers", true)
	ok(H.Ticker().shown, "counting down")
	ns.Set("heal.enabled", false)
	ok(not H.Ticker().shown, "no timer while the frames are off")
	ns.Set("heal.enabled", true)
	ns.Set("heal.buffSize", 18)
	ns.Set("heal.debuffSize", 12)
	eq(b.buffs[1].w, 18, "bigger buffs")
	eq(b.removable[1].w, 12, "smaller debuffs")
	fight(stub, function()
		local a = gameAnchor(stub, b)
		eq(a.attrs["buff-size"], 18)
		eq(a.attrs["debuff-size"], 12)
	end)
	ns.Set("heal.hots", false)
	ns.Set("heal.buffs", false)
	fight(stub, function()
		local a = gameAnchor(stub, b)
		eq(a.attrs["max-buffs"], 0, "no buffs from the game either")
		eq(a.attrs["ignore-buffs"], true)
		eq(a.attrs["max-dispel-debuffs"], 3, "the debuffs still")
	end)
	ns.Set("heal.debuffs", false)
	ns.Set("heal.dispel", false)
	fight(stub, function() ok(not gameAnchor(stub, b), "nothing for the game to draw") end)
	done()
end)

test("settings: changed in a fight, the game's rows take them at once", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	local b = frame(ns, "party1")
	fight(stub, function()
		local _, id = gameAnchor(stub, b)
		ns.Set("heal.timers", false)
		local a2 = gameAnchor(stub, b)
		ok(stub.removed[id] and a2, "attached again")
		eq(a2.args.showCountdownNumbers, false)
	end)
	done()
end)

test("settings: the options page has both rows and the cleanse click", function()
	local stub, ns = fresh(setup({}))
	ns.Set("heal.enabled", true)
	ns.Config.Show("heal")
	local found = {}
	for _, t in ipairs(stub.texts()) do found[t] = true end
	for _, label in ipairs({ "Your HoTs", "Other buffs", "Time left on buffs", "Buff icon size", "Debuffs",
		"Click a debuff to remove it", "Color the edge", "Debuff icon size" }) do
		ok(found[label], label)
	end
	done()
end)
