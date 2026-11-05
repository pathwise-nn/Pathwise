-- Pathwise gathering: where the herbs and ore are for your skill.
--
--   G.Color(req, rank)        "red" (can't yet), "orange", "yellow", "green", "grey"
--   G.NodesOn(map, kind, rank) every node on a map, with its colour
--   G.BestZones(kind, rank, p) the zones with the most skill-ups for you
--   G.Pins(map)               map pins for the gathering professions you have
--
-- Nodes: Data.gather (tools/data/build.lua): QuestieDB's Forever spawns, the
-- skill from Forever's own Lock table. Forever's positions are Era's carried
-- over; Mulgore, Eastern Plaguelands, Redridge and Stormwind changed their
-- maps on Forever, so nodes there are marked "not checked". Forever's new
-- materials (Bauxite, Pyrite, Demonsage...) have no node in any source yet.
--
-- Colours: the usual Classic rule for gathering, a skill-up always while
-- orange (under the node's skill + 25), often yellow (+50), seldom green
-- (+100), never grey. Not yet checked on Forever.

local ADDON, ns = ...
local C = ns.Compat
local G = {}
ns.Gathering = G

G.KINDS = {
	herb = { line = 182, name = "Herbalism", key = "herbalism" },
	ore = { line = 186, name = "Mining", key = "mining" },
}
G.BY_KEY = { herbalism = "herb", mining = "ore" }
G.UNCHECKED_MAPS = { [1412] = true, [1423] = true, [1433] = true, [1453] = true } -- Mulgore, EPL, Redridge, Stormwind
G.RGB = {
	red = { 0.8, 0.1, 0.1 }, orange = { 1, 0.5, 0.25 }, yellow = { 1, 1, 0 },
	green = { 0.25, 0.75, 0.25 }, grey = { 0.5, 0.5, 0.5 },
}
local WEIGHT = { orange = 1, yellow = 0.7, green = 0.25 }

ns.Defaults("pins", { gather = true, gatherMinimap = true })

local function data() return ns.Data and ns.Data.gather or {} end

function G.Color(req, rank)
	rank = rank or 0
	if rank < req then return "red" end
	if rank < req + 25 then return "orange" end
	if rank < req + 50 then return "yellow" end
	if rank < req + 100 then return "green" end
	return "grey"
end

-- Your rank in a kind, or nil without the profession.
function G.Rank(kind)
	local k = G.KINDS[kind]
	return k and (C.SkillRank(k.line)) or nil
end

-- { { x, y, name, skill, color }, ... } for every `kind` node on the map.
function G.NodesOn(map, kind, rank)
	local out = {}
	for _, node in pairs(data()) do
		if node[2] == kind then
			local pts = node[4] and node[4][map]
			if pts then
				local color = G.Color(node[3], rank)
				for i = 1, #pts, 2 do
					out[#out + 1] = { x = pts[i], y = pts[i + 1], name = node[1], skill = node[3], color = color }
				end
			end
		end
	end
	return out
end

-- The zone levels the data knows for this side: low, high or nil.
local function zoneLevels(map, p)
	local z = ns.Data and ns.Data.zones and ns.Data.zones[map]
	local side = z and ((p and p.faction == "Alliance") and z.alliance or z.horde) or nil
	side = side or (z and (z.alliance or z.horde))
	if side then return side[1], side[2] end
	return nil
end

-- The zones with the most skill-ups for `rank`, best first:
-- { { map, name, score, low, high, unchecked, nodes = { { name, skill, color, count } } }, ... }
-- A zone far above the character's level counts for less (it is dangerous).
function G.BestZones(kind, rank, p, limit)
	p = p or ns.Quests.Player()
	local byMap = {}
	for _, node in pairs(data()) do
		if node[2] == kind then
			local color = G.Color(node[3], rank)
			local w = WEIGHT[color]
			if w then
				for map, pts in pairs(node[4] or {}) do
					local z = byMap[map] or { map = map, score = 0, kinds = {} }
					byMap[map] = z
					local n = #pts / 2
					z.score = z.score + w * n
					local entry = z.kinds[node[1]] or { name = node[1], skill = node[3], color = color, count = 0 }
					z.kinds[node[1]] = entry
					entry.count = entry.count + n
				end
			end
		end
	end
	local list = {}
	for map, z in pairs(byMap) do
		local name = C.MapName(map)
		if name then
			z.name = name
			z.low, z.high = zoneLevels(map, p)
			if z.low and z.low > (p.level or 1) + 3 then z.score = z.score * 0.3 end
			z.unchecked = G.UNCHECKED_MAPS[map] or nil
			z.nodes = {}
			for _, e in pairs(z.kinds) do z.nodes[#z.nodes + 1] = e end
			table.sort(z.nodes, function(a, b) return a.count > b.count end)
			z.kinds = nil
			list[#list + 1] = z
		end
	end
	table.sort(list, function(a, b) if a.score ~= b.score then return a.score > b.score end return a.map < b.map end)
	local out = {}
	for i = 1, math.min(limit or 5, #list) do out[i] = list[i] end
	return out
end

-- Where to head in a zone: the skill-up node nearest the middle of them all.
function G.Spot(map, kind, rank)
	local nodes = {}
	for _, n in ipairs(G.NodesOn(map, kind, rank)) do if WEIGHT[n.color] then nodes[#nodes + 1] = n end end
	if #nodes == 0 then return nil end
	local sx, sy = 0, 0
	for _, n in ipairs(nodes) do sx, sy = sx + n.x, sy + n.y end
	sx, sy = sx / #nodes, sy / #nodes
	local best, bd
	for _, n in ipairs(nodes) do
		local d = (n.x - sx) ^ 2 + (n.y - sy) ^ 2
		if not bd or d < bd then best, bd = n, d end
	end
	return best
end

-- Map pins for the gathering professions this character has: nodes you can
-- gather and still learn from (not red, not grey). setting: "pins.gather" or
-- "pins.gatherMinimap".
function G.Pins(map, setting)
	local out = {}
	if not (map and ns.Get(setting or "pins.gather")) then return out end
	for kind, k in pairs(G.KINDS) do
		local rank = G.Rank(kind)
		if rank then
			for _, n in ipairs(G.NodesOn(map, kind, rank)) do
				if WEIGHT[n.color] then
					out[#out + 1] = { map = map, x = n.x, y = n.y, kind = "gather", rgb = G.RGB[n.color], title = n.name,
						sub = ("%s %d  ·  %s"):format(k.name, n.skill, n.color) .. (G.UNCHECKED_MAPS[map] and "  ·  not checked on Forever" or "") }
				end
			end
		end
	end
	return out
end
