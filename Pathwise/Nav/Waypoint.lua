-- Pathwise waypoint: the one place the arrow points at. Anything (the guide,
-- a profession detour, /pw way) sets it; the arrow only reads it.
--
-- Pathwise.SetWaypoint(map, x, y, title) / Pathwise.ClearWaypoint()
-- Fires WAYPOINT_CHANGED(target or nil).

local ADDON, ns = ...
local Nav = {}
ns.Nav = Nav

local sqrt, atan2, pi = math.sqrt, math.atan2, math.pi
local TWO_PI = 2 * pi
local YARDS_ARRIVED = 8

local target -- { map, x, y, title, inst, north, west }

-- Angle wrapped into -pi..pi.
local function wrap(a)
	a = a % TWO_PI
	if a > pi then a = a - TWO_PI end
	return a
end
Nav.Wrap = wrap

-- Pure maths, tested: distance in yards and the arrow's rotation (radians,
-- counter-clockwise, 0 = straight ahead) from the player to a point.
-- World coordinates grow north and west; facing is 0 at north, CCW.
function Nav.Direction(pNorth, pWest, facing, tNorth, tWest)
	local dn, dw = tNorth - pNorth, tWest - pWest
	local dist = sqrt(dn * dn + dw * dw)
	local bearing = atan2(dw, dn) -- 0 = north, CCW toward west
	local rotation = facing and wrap(bearing - facing) or nil
	return dist, rotation, bearing
end

function Nav.SetTarget(map, x, y, title)
	if not (map and x and y) then return false end
	local inst, north, west = ns.Compat.MapToWorld(map, x, y)
	target = { map = map, x = x, y = y, title = title, inst = inst, north = north, west = west }
	ns.Fire("WAYPOINT_CHANGED", target)
	return true
end

function Nav.Clear()
	if not target then return end
	target = nil
	ns.Fire("WAYPOINT_CHANGED", nil)
end

function Nav.Target() return target end

-- The player's relation to the target, for the arrow:
--   "none"      no target
--   "instance"  inside a dungeon or raid: no positions there, the arrow hides
--   "taxi"      on a flight
--   "unknown"   no position for the player or the target
--   "far"       on another continent or instance
--   "arrived"   within YARDS_ARRIVED
--   "travel"    with distance and rotation
function Nav.Sample()
	if not target then return "none" end
	local C = ns.Compat
	if C.InInstance() then return "instance" end
	if C.OnTaxi() then return "taxi" end
	if not target.inst then
		target.inst, target.north, target.west = C.MapToWorld(target.map, target.x, target.y)
		if not target.inst then return "unknown" end
	end
	local inst, north, west = C.PlayerWorldPosition()
	if not inst then return "unknown" end
	if inst ~= target.inst then return "far" end
	local dist, rotation = Nav.Direction(north, west, C.PlayerFacing(), target.north, target.west)
	if dist <= YARDS_ARRIVED then return "arrived", dist end
	return "travel", dist, rotation
end

-- What the arrow sees, as text for bug reports (Waypoint & tools, /pw debug).
function Nav.DebugText()
	local C = ns.Compat
	local function n(v) return v and ("%.1f"):format(v) or "nil" end
	local lines = {}
	local map, x, y = C.PlayerMapPosition()
	lines[#lines + 1] = ("player map %s (%s) at %s, %s"):format(tostring(map), tostring(map and C.MapName(map)), n(x), n(y))
	local inst, north, west = C.PlayerWorldPosition()
	lines[#lines + 1] = ("player world inst %s north %s west %s, facing %s"):format(tostring(inst), n(north), n(west), n(C.PlayerFacing()))
	local t = target
	if t then
		lines[#lines + 1] = ("target %s: map %s at %s, %s -> world inst %s north %s west %s"):format(tostring(t.title), tostring(t.map), n(t.x), n(t.y), tostring(t.inst), n(t.north), n(t.west))
		local state, dist, rot = Nav.Sample()
		lines[#lines + 1] = ("state %s, distance %s yd, rotation %s"):format(tostring(state), n(dist), n(rot))
	else
		lines[#lines + 1] = "no waypoint set"
	end
	lines[#lines + 1] = ("instance %s, taxi %s"):format(tostring(C.InInstance()), tostring(C.OnTaxi()))
	return table.concat(lines, "\n")
end

Pathwise.SetWaypoint = function(map, x, y, title) return Nav.SetTarget(map, x, y, title) end
Pathwise.ClearWaypoint = function() Nav.Clear() end
