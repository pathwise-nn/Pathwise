-- Pathwise compass (v2): a heading strip across the top of the screen
-- (frame PathwiseCompass). The strip turns as you turn: N, NE, E ... and a
-- tick every 15 degrees, with where you face in the middle. The waypoint is
-- a caret on the strip (pinned to an end when it is behind you); under the
-- strip, the arrow, the destination's name, the distance and its
-- coordinates; under those, your own coordinates (compass.coords).
--
-- On by default; off, the classic arrow (Nav/Arrow.lua) shows instead.
-- Toggle: Settings, the tracker's and the hub's compass button, /pw compass,
-- or a key (Key Bindings > Pathwise).
--
-- ns.Coords: your position on the map, read 5 times a second while anything
-- shows it, fired as PLAYER_COORDS when it changes.

local ADDON, ns = ...
local T, Nav, C = ns.Theme, ns.Nav, ns.Compat
local floor, abs, deg = math.floor, math.abs, math.deg

ns.Defaults("compass", {
	shown = true,
	coords = true, -- your own coordinates, on the compass and the guide
	scale = 1,
	point = nil, -- { point, x, y[, relativePoint] } once moved
	locked = false, -- pinned: no drag, and clicks go through to the world
	width = nil, -- the strip's width once dragged (Compass.WIDTH)
})

local Compass = {}
ns.Compass = Compass

Compass.WIDTH = 440 -- the strip (compass.width once dragged)
Compass.MIN_W, Compass.MAX_W = 260, 900
Compass.SPAN = 180 -- degrees across the strip
Compass.LABELS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }

---------------------------------------------------------------------------
-- The maths (pure, tested)
---------------------------------------------------------------------------

-- An angle wrapped into -180..180.
local function wrap180(a)
	a = a % 360
	if a > 180 then a = a - 360 end
	return a
end
Compass.Wrap180 = wrap180

-- Where you face, in compass degrees (0 = north, 90 = east, clockwise),
-- from the game's facing (radians, 0 = north, counter-clockwise).
function Compass.Heading(facing)
	if not facing then return nil end
	return (-deg(facing)) % 360
end

-- How far from the strip's middle a compass bearing `at` sits when facing
-- `heading`: pixels, right positive; nil when off the strip.
function Compass.Offset(heading, at, width, span)
	width, span = width or Compass.WIDTH, span or Compass.SPAN
	local d = wrap180(at - heading)
	if abs(d) > span / 2 then return nil end
	return d * width / span
end

-- The waypoint's mark from the arrow's rotation (radians, counter-clockwise,
-- 0 = ahead): pixels from the middle, and whether it is pinned to an end
-- (off the strip, so behind or well to the side).
function Compass.TargetOffset(rotation, width, span)
	width, span = width or Compass.WIDTH, span or Compass.SPAN
	local d = wrap180(-deg(rotation))
	local half = width / 2 - 10
	local x = d * width / span
	if x > half then return half, true end
	if x < -half then return -half, true end
	return x, false
end

---------------------------------------------------------------------------
-- Your coordinates
---------------------------------------------------------------------------

local Coords = {}
ns.Coords = Coords
local coordText, coordMap
local ticker, tickAccum = nil, 0

-- "54.1, 50.3", or nil (turned off, or no position: an instance).
function Coords.Text()
	if not ns.Get("compass.coords") then return nil end
	return coordText
end
function Coords.Map() return coordMap end

local function readCoords()
	local map, x, y = C.PlayerMapPosition()
	local text = map and ("%.1f, %.1f"):format(x, y) or nil
	if text ~= coordText or map ~= coordMap then
		coordText, coordMap = text, map
		ns.Fire("PLAYER_COORDS", map, x, y)
	end
end
Coords.Read = readCoords

local function startCoords()
	if ticker then return end
	ticker = CreateFrame("Frame")
	ticker:SetScript("OnUpdate", function(_, elapsed)
		tickAccum = tickAccum + elapsed
		if tickAccum < 0.2 then return end
		tickAccum = 0
		if ns.Get("compass.coords") then readCoords() end
	end)
	readCoords()
end

---------------------------------------------------------------------------
-- The frame
---------------------------------------------------------------------------

local W = {}
Compass.frames = W
local SAMPLE, EASE, BEHIND = 0.1, 12, 2.4
local accum, lastHeading = 0, nil
local curRot, goalRot, hasRot = 0, 0, false
local mode

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("compass.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

local function build()
	local f = CreateFrame("Frame", "PathwiseCompass", UIParent)
	W.frame = f
	f:SetSize(Compass.WIDTH, 150)
	-- A heads-up display: under windows (the hub, panels), like the game's own.
	f:SetFrameStrata("LOW")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(T.Movable("compass.locked"))
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) if T.Movable("compass.locked") then self:StartMoving() end end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePoint(self) end)
	f:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText("Pathwise compass", 1, 1, 1)
		GameTooltip:AddLine("Drag to move it. Turn it off in Settings, or with /pw compass.", nil, nil, nil, true)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	local saved = ns.Get("compass.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else
		f:SetPoint("TOP", UIParent, "TOP", 0, -24)
	end
	f:SetScale(ns.Get("compass.scale") or 1)
	Compass.WIDTH = math.min(Compass.MAX_W, math.max(Compass.MIN_W, ns.Get("compass.width") or 440))
	f:SetWidth(Compass.WIDTH)

	-- The strip.
	local strip = CreateFrame("Frame", nil, f)
	W.strip = strip
	strip:SetSize(Compass.WIDTH, 40)
	strip:SetPoint("TOP")
	T.Round(strip, "bg", "border", 20)
	T.PaintRound(strip, "bg", "border", 0.82)
	W.ticks = {}
	for i = 0, 23 do
		local t = strip:CreateTexture(nil, "ARTWORK")
		local major = i % 3 == 0
		t:SetSize(1, major and 8 or 5)
		T.SetColor(t, "text2", major and 0.7 or 0.45)
		t.at = i * 15
		W.ticks[#W.ticks + 1] = t
	end
	W.labels = {}
	for i, name in ipairs(Compass.LABELS) do
		local fs = T.TextAt(strip, i == 1 and "semibold" or "medium", i == 1 and 15 or 12, i == 1 and "accent" or "text2")
		fs:SetJustifyH("CENTER")
		fs:SetText(name)
		fs.at = (i - 1) * 45
		W.labels[#W.labels + 1] = fs
	end
	-- The middle: where you face.
	W.centre = strip:CreateTexture(nil, "OVERLAY")
	W.centre:SetSize(2, 10)
	W.centre:SetPoint("TOP", strip, "TOP", 0, -1)
	T.SetColor(W.centre, "text", 0.8)
	-- The waypoint's caret.
	W.caret = T.Glyph(strip, "caret", 12, "accent", "OVERLAY")

	-- Under the strip: arrow, name, distance, coordinates.
	W.dart = f:CreateTexture(nil, "ARTWORK")
	W.dart:SetTexture(T.MEDIA .. "arrow")
	W.dart:SetSize(46, 46)
	W.dart:SetPoint("TOP", strip, "BOTTOM", 0, -2)
	W.mark = f:CreateTexture(nil, "ARTWORK")
	W.mark:SetTexture(T.MEDIA .. "arrived")
	W.mark:SetSize(36, 36)
	W.mark:SetPoint("CENTER", W.dart, "CENTER")
	W.mark:Hide()
	W.name = T.TextAt(f, "semibold", 16, T.World("text"))
	W.name:SetJustifyH("CENTER")
	W.name:SetWidth(Compass.WIDTH)
	W.name:SetWordWrap(false)
	W.name:SetPoint("TOP", W.dart, "BOTTOM", 0, -2)
	T.Shadow(W.name)
	W.dist = T.TextAt(f, "semibold", 15, T.World("accent"))
	W.dist:SetJustifyH("CENTER")
	W.dist:SetWidth(200)
	W.dist:SetPoint("TOP", W.name, "BOTTOM", 0, -2)
	T.Shadow(W.dist)
	W.where = T.Text(f, "small", T.World("silver"))
	W.where:SetJustifyH("CENTER")
	W.where:SetWidth(Compass.WIDTH)
	W.where:SetWordWrap(false)
	W.where:SetPoint("TOP", W.dist, "BOTTOM", 0, -2)
	T.Shadow(W.where)
	W.you = T.Text(f, "small", T.World("text2"))
	W.you:SetJustifyH("CENTER")
	W.you:SetWidth(Compass.WIDTH)
	W.you:SetWordWrap(false)
	T.Shadow(W.you)

	-- The grip at the strip's end: a wider strip spreads the same half
	-- circle out; a narrower one packs it in.
	W.grip = T.Grip(f, {
		minW = Compass.MIN_W, maxW = Compass.MAX_W, lockPath = "compass.locked", centered = true, at = strip,
		onSize = function(w) Compass.SetWidth(w) end,
		onDone = function(w) ns.Set("compass.width", w) savePoint(f) end,
		onReset = function() ns.Set("compass.width", nil) end,
	})
	f:Hide()
end

-- The strip's width: the frame, the texts under it, the ticks and labels.
function Compass.SetWidth(w)
	Compass.WIDTH = w
	if not W.frame then return end
	W.frame:SetWidth(w)
	W.strip:SetWidth(w)
	for _, fs in ipairs({ W.name, W.where, W.you }) do fs:SetWidth(w) end
	lastHeading = nil
	Compass.Turn(Compass.Heading(C.PlayerFacing()) or 0)
end

-- Turn the strip to `heading`: every tick and label where it belongs.
function Compass.Turn(heading)
	if not W.frame or not heading then return end
	for _, t in ipairs(W.ticks) do
		local x = Compass.Offset(heading, t.at)
		t:SetShown(x ~= nil)
		if x then
			t:ClearAllPoints()
			t:SetPoint("BOTTOM", W.strip, "BOTTOM", x, 4)
		end
	end
	for _, fs in ipairs(W.labels) do
		local x = Compass.Offset(heading, fs.at)
		-- Labels fade out toward the ends.
		fs:SetShown(x ~= nil and abs(x) < Compass.WIDTH / 2 - 14)
		if x then
			fs:ClearAllPoints()
			fs:SetPoint("CENTER", W.strip, "CENTER", x, 3)
			fs:SetAlpha(1 - 0.6 * abs(x) / (Compass.WIDTH / 2))
		end
	end
end

local function youLine()
	local xy = ns.Coords.Text()
	if not xy then return nil end
	local zone = coordMap and C.MapName(coordMap)
	return "You  " .. xy .. (zone and ("  ·  " .. zone) or "")
end

local function paintYou(anchor)
	local line = youLine()
	W.you:SetShown(line ~= nil)
	if not line then return end
	W.you:SetText(line)
	W.you:ClearAllPoints()
	W.you:SetPoint("TOP", anchor, "BOTTOM", 0, -4)
end

local function setMode(m, target)
	mode = m
	local travel, arrived = m == "travel", m == "arrived"
	local hasTarget = target ~= nil and m ~= "none"
	W.dart:SetShown(travel)
	W.mark:SetShown(arrived)
	W.caret:SetShown(travel)
	W.name:SetShown(hasTarget)
	W.dist:SetShown(hasTarget and (travel or arrived or m == "far"))
	W.where:SetShown(hasTarget)
	if hasTarget then
		W.name:SetText(target.title or "Waypoint")
		local zone = C.MapName(target.map)
		W.where:SetText(("%.1f, %.1f"):format(target.x, target.y) .. (zone and ("  ·  " .. zone) or ""))
	end
	if arrived then
		-- The guide counts a "go to" as reached on this (as from the arrow).
		ns.Fire("WAYPOINT_ARRIVED", target)
		local c = T.World("success")
		W.mark:SetVertexColor(c[1], c[2], c[3])
		T.TextColor(W.dist, c)
		W.dist:SetText("Arrived")
	elseif m == "far" then
		T.TextColor(W.dist, T.World("text2"))
		W.dist:SetText("Far away")
	else
		T.TextColor(W.dist, T.World("accent"))
	end
	paintYou(hasTarget and W.where or W.strip)
end

local function sample()
	local target = Nav.Target()
	local state, dist, rot = Nav.Sample()
	if state == "taxi" then W.frame:SetAlpha(0.35) else W.frame:SetAlpha(1) end
	if state ~= mode then setMode(state, target) end
	if state == "travel" then
		local yards = Nav.FormatYards and Nav.FormatYards(dist) or ("%d yd"):format(floor(dist + 0.5))
		W.dist:SetText(yards)
		if ns.Guide and ns.Guide.SetDistance then ns.Guide.SetDistance(yards) end
		if rot then
			goalRot = rot
			if not hasRot then curRot, hasRot = rot, true end
			local c = T.World(abs(rot) > BEHIND and "warning" or "accent")
			W.dart:SetVertexColor(c[1], c[2], c[3])
			local x, pinned = Compass.TargetOffset(rot)
			W.caret:ClearAllPoints()
			W.caret:SetPoint("TOP", W.strip, "TOP", x, -26)
			W.caret:SetVertexColor(c[1], c[2], c[3], pinned and 0.6 or 1)
		end
	end
end

local function onUpdate(_, elapsed)
	local h = Compass.Heading(C.PlayerFacing())
	if h and (not lastHeading or abs(wrap180(h - lastHeading)) > 0.15) then
		lastHeading = h
		Compass.Turn(h)
	end
	accum = accum + elapsed
	if accum >= SAMPLE then
		accum = 0
		sample()
	end
	if mode == "travel" and hasRot then
		local d = Nav.Wrap(goalRot - curRot)
		curRot = Nav.Wrap(curRot + d * math.min(1, EASE * elapsed))
		W.dart:SetRotation(curRot)
	end
end

function Compass.Refresh()
	local on = ns.Get("compass.shown") and true or false
	if on and not W.frame then build() end
	if ns.Get("compass.coords") or on then startCoords() end
	if not W.frame then return end
	if not on then
		W.frame:SetScript("OnUpdate", nil)
		W.frame:Hide()
		return
	end
	mode, hasRot, accum, lastHeading = "?", false, SAMPLE, nil
	W.frame:Show()
	W.frame:SetScript("OnUpdate", onUpdate)
	Compass.Turn(Compass.Heading(C.PlayerFacing()) or 0)
	sample()
	if mode == "?" then setMode("none", nil) end
end

function Compass.Shown() return W.frame ~= nil and W.frame:IsShown() end

function Compass.Toggle()
	ns.Set("compass.shown", not ns.Get("compass.shown"))
end

ns.On("READY", Compass.Refresh)
ns.On("WAYPOINT_CHANGED", function() if Compass.Shown() then mode = "?" sample() end end)
ns.On("PLAYER_COORDS", function()
	if Compass.Shown() then paintYou((mode == "travel" or mode == "arrived" or mode == "far") and W.where or W.strip) end
end)
ns.On("TOGGLE_COMPASS", Compass.Toggle)
ns.On("SETTING_CHANGED", function(path)
	if path == "compass.shown" or path == "compass.coords" then
		Compass.Refresh()
		if path == "compass.coords" then readCoords() ns.Fire("PLAYER_COORDS", coordMap) end
	elseif path == "compass.scale" and W.frame then W.frame:SetScale(ns.Get("compass.scale") or 1)
	elseif path == "compass.locked" and W.frame then W.frame:EnableMouse(T.Movable("compass.locked"))
	elseif path == "compass.width" and W.frame and not W.grip.pwState.held then
		Compass.SetWidth(math.min(Compass.MAX_W, math.max(Compass.MIN_W, ns.Get("compass.width") or 440)))
	end
end)
