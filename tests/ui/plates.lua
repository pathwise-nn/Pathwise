-- Tests for Pathwise UI's nameplates.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

local function gnoll(s) return { name = "Gnoll Brute", level = 20, reaction = 2, health = s.Secret(4200), max = s.Secret(5000) } end

test("nameplates: a Pathwise bar on each plate, the game's art faded", function()
	local stub, ns = fresh()
	local plate = stub.addPlate("nameplate1", gnoll(stub))
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local f = ns.Plates.plates.nameplate1
	ok(f and f.shown, "dressed")
	eq(f.parent, plate, "on the game's plate")
	eq(plate.UnitFrame.alpha, 0, "the game's art faded, not removed")
	eq(stub.shown(f.name), "Gnoll Brute")
	ok(issecretvalue(f.health.value), "secret health passed on")
	eq(f.health.barColor[1], 1, "hostile: the game's red")
	eq(f.health.barColor[2], 0)
	eq(f.w, 130)
	stub.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	ok(not f.shown and not ns.Plates.plates.nameplate1, "gone with its plate")
end)

test("nameplates: the game's plate stays hidden whichever handler runs first, and pooled frames get their look back", function()
	local stub, ns = fresh(function(s)
		-- Forever's NamePlateDriverFrame: gives the plate a unit frame from its pool.
		NamePlateDriverFrame = {}
		function NamePlateDriverFrame:OnNamePlateAdded(unit)
			local plate = s.namePlates[unit]
			plate.UnitFrame = CreateFrame("Button", nil, plate)
		end
	end)
	local plate = stub.addPlate("nameplate1", gnoll(stub))
	plate.UnitFrame = nil -- not given yet: Pathwise's handler runs first
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	NamePlateDriverFrame:OnNamePlateAdded("nameplate1")
	local uf = plate.UnitFrame
	eq(uf.alpha, 0, "faded right after the game gave it")
	ok(ns.Plates.plates.nameplate1.shown, "ours shown")
	stub.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	eq(uf.alpha, 1, "back to the pool with its own look")
end)

test("nameplates: the game setting its plate's alpha again does not bring it back", function()
	local stub, ns = fresh()
	local plate = stub.addPlate("nameplate1", gnoll(stub))
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local uf = plate.UnitFrame
	uf:SetAlpha(1) -- CompactUnitFrame_UpdateCenterStatusIcon's range alpha
	eq(uf.alpha, 0, "still faded")
	stub.fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
	eq(uf.alpha, 1, "its look back once the plate goes")
	uf:SetAlpha(0.5)
	eq(uf.alpha, 0.5, "the game's own alpha again, once not ours")
end)

test("nameplates: forbidden plates left to the game", function()
	local stub, ns = fresh()
	stub.addPlate("nameplate2", { name = "Florp", reaction = 5, friend = true, health = 10, max = 10 }, true)
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	ok(not ns.Plates.plates.nameplate2, "untouched")
end)

test("nameplates: your target framed and bigger; tapped grey; threat", function()
	local stub, ns = fresh()
	stub.addPlate("nameplate1", gnoll(stub))
	stub.addPlate("nameplate3", { name = "Kobold", reaction = 2, health = 100, max = 100, tapped = true })
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	local a, b = ns.Plates.plates.nameplate1, ns.Plates.plates.nameplate3
	stub.targetPlate = "nameplate1"
	stub.fire("PLAYER_TARGET_CHANGED")
	ok(a.mark.shown and not b.mark.shown, "the target framed")
	near(a.scale, 1.15, 1e-6, "and bigger")
	eq(b.health.barColor[1], 0.9, "tapped by someone else: the game's light grey")
	stub.units.nameplate1.threat = 3
	stub.fire("UNIT_THREAT_SITUATION_UPDATE", "nameplate1")
	eq(a.health.barColor[2], 0, "threat colours off by default, as on the game's plates")
	stub.units.nameplate1.threat = 2
	ns.Set("plates.threat", true)
	a = ns.Plates.plates.nameplate1
	eq(a.health.barColor[2], 0.6, "switched on: the game's threat colour")
end)

test("nameplates: friendly plates optional, switched off, options page", function()
	local stub, ns = fresh()
	local p = stub.addPlate("nameplate4", { name = "Guard", reaction = 5, friend = true, health = 10, max = 10 })
	ns.Set("plates.friendly", false)
	stub.fire("NAME_PLATE_UNIT_ADDED", "nameplate4")
	ok(not ns.Plates.plates.nameplate4, "friendly off: the game's own")
	ns.Set("plates.friendly", true)
	ok(ns.Plates.plates.nameplate4, "on again")
	ns.Set("plates.enabled", false)
	eq(p.UnitFrame.alpha, 1, "off: the game's art back")
	ns.Config.Show("plates")
	ok(contains(stub.texts(), "Pathwise nameplates"))
end)
