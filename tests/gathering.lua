-- Tests for gathering (Professions/Gathering.lua): herb and ore nodes from
-- the data, their skill-up colour, the best zones and the map pins.
local h = ...
local test, eq, ok, fresh = h.test, h.eq, h.ok, h.fresh

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

local function herbalist(rank, setup)
	local stub, ns = fresh()
	stub.player.level = 5
	stub.skills[182] = { rank, 75 }
	if setup then setup(stub) end
	stub.moveTo(1420, 50, 50)
	stub.login()
	return stub, ns
end

test("gathering data: every Classic herb and ore, with Forever's skill", function()
	local _, ns = fresh()
	local byName = {}
	for _, n in pairs(ns.Data.gather) do byName[n[1]] = n end
	eq(byName["Peacebloom"][2], "herb")
	eq(byName["Peacebloom"][3], 1, "Forever: skill 1, not Era's 0")
	eq(byName["Black Lotus"][3], 300)
	eq(byName["Copper Vein"][2], "ore")
	eq(byName["Rich Thorium Vein"][3], 275)
	ok(byName["Peacebloom"][4][1420], "Peacebloom grows in Tirisfal")
end)

test("gathering: skill-up colours", function()
	local _, ns = fresh()
	local G = ns.Gathering
	eq(G.Color(125, 100), "red", "can't yet")
	eq(G.Color(125, 125), "orange")
	eq(G.Color(125, 150), "yellow")
	eq(G.Color(125, 175), "green")
	eq(G.Color(125, 225), "grey")
end)

test("gathering: the best zones for your skill, the arrow to one", function()
	local stub, ns = herbalist(1)
	local G = ns.Gathering
	local zones = G.BestZones("herb", 1)
	ok(#zones > 0, "somewhere to pick")
	local tirisfal
	for _, z in ipairs(zones) do if z.map == 1420 then tirisfal = z end end
	ok(tirisfal, "Tirisfal is one")
	ok(contains((function() local t = {} for _, n in ipairs(tirisfal.nodes) do t[#t + 1] = n.name end return t end)(), "Peacebloom"))
	eq(#G.BestZones("herb", 400), 0, "all grey: nothing")
	local spot = G.Spot(1420, "herb", 1)
	ok(spot and spot.x and spot.name, "a node to head for")
	SlashCmdList.PATHWISE("prof")
	ok(stub.clickLabelText("Herbalism   1 / 75"), "Herbalism's page")
	local texts = stub.texts()
	ok(contains(texts, "WHERE TO GATHER NOW"), table.concat(texts, " | "))
	ok(stub.clickLabelText("Tirisfal Glades"), "a zone")
	eq(ns.Nav.Target().map, 1420, "the arrow there")
end)

test("gathering: nodes on the map in their colour, for your professions only, switched off in Settings", function()
	local stub, ns = herbalist(1)
	local G = ns.Gathering
	local pins = G.Pins(1420, "pins.gather")
	ok(#pins > 0, "herbs in Tirisfal")
	eq(pins[1].kind, "gather")
	eq(pins[1].rgb, G.RGB.orange, "rank 1: everything here is orange")
	local mapPins = ns.Pins.PinsFor(1420, "pins.quests", true)
	local n = 0
	for _, p in ipairs(mapPins) do if p.kind == "gather" then n = n + 1 end end
	eq(n, #pins, "on the world map")
	ns.Set("pins.gather", false)
	eq(#G.Pins(1420, "pins.gather"), 0, "switched off")
	stub.skills[182] = nil
	eq(#G.Pins(1420, "pins.gatherMinimap"), 0, "no Herbalism, no herbs")
end)
