-- Pathwise pins: the step's places on the world map and the minimap, the
-- quests around you (Nav/QuestMarkers.lua: givers, finishers, objectives),
-- and the entrances of dungeons for the character's level on the world map.
--
-- Forever's interface is protected like retail's: a value an addon writes into
-- the world map's own tables (a data provider, a pin from its pool) taints
-- the map, and the game then blocks its own actions there ("An action was
-- blocked because of taint"). So Pathwise only READS the map
--   WorldMapFrame:GetMapID(), :GetCanvas(), :GetCanvasScale()
-- and draws on frames of its own, made with no parent and then set under the
-- map's canvas or the minimap (Polestar found the gamepad interface hooks
-- CreateFrame for frames on the open map). Pins take the mouse for a tooltip
-- only: no clicks (the gamepad's map navigation reads click scripts).
--
-- Minimap: radius in yards from C_Minimap.GetViewRadius when the client has
-- it, else the zoom table below (outdoor / indoor diameters, the values the
-- minimap is known to use); a rotating minimap (CVar rotateMinimap) turns the
-- pins with the player's facing. Pins beyond the rim are hidden, but the
-- arrow's target stays on the rim to show the way.

local ADDON, ns = ...
local T, C = ns.Theme, ns.Compat
local Pins = {}
ns.Pins = Pins

ns.Defaults("pins", { map = true, minimap = true, dungeons = true, stepNumbers = true, stepCount = 8 })

local cos, sin, sqrt, max, abs = math.cos, math.sin, math.sqrt, math.max, math.abs

local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local LOOK = {
	lead = { tex = "dot-open", size = 18, color = "accent", alpha = 1 },
	goal = { tex = "dot-open", size = 14, color = "text2", alpha = 0.9 },
	spot = { tex = "dot-done", size = 7, color = "accent", alpha = 0.55 },
	-- Herb and ore nodes, in the skill-up colour of each (pin.rgb).
	gather = { tex = "dot-done", size = 7, color = "text2", alpha = 0.9 },
	-- The steps ahead, each with its number on a dark disc.
	step = { tex = "dot-done", size = 16, color = "bg", alpha = 0.9 },
	-- Badges (badge = the glyph's share of the pin): the glyph on a dark disc
	-- with a ring in its colour (ring = true). A bare light glyph was lost on
	-- the world map's parchment, close to the theme's gold in colour.
	dungeon = { tex = "glyph-dungeon", size = 24, color = "warning", alpha = 1, badge = 0.7, ring = true },
	-- Quest markers (Nav/QuestMarkers.lua): givers, finishers, objectives.
	available = { tex = "glyph-quest", size = 24, color = "warning", alpha = 1, badge = 0.7, ring = true },
	availableLow = { tex = "glyph-quest", size = 20, color = "muted", alpha = 1, badge = 0.7, ring = true },
	turnin = { tex = "glyph-turnin", size = 24, color = "warning", alpha = 1, badge = 0.7, ring = true },
	objective = { tex = "dot-done", size = 10, color = "text2", alpha = 1, badge = 0.7 },
}
Pins.LOOK = LOOK
Pins.BADGE_ALPHA = 0.9 -- the dark disc under a badge's glyph

local function frameUnder(parent)
	local f = CreateFrame("Frame", nil, nil)
	f:SetParent(parent)
	return f
end

local function tooltip(self)
	local pin = self.pin
	if not (pin and GameTooltip) then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(pin.title or "Pathwise", 1, 1, 1)
	if pin.sub then GameTooltip:AddLine(pin.sub, 0.6, 0.69, 0.75, true) end
	GameTooltip:Show()
end

local function makePin(parent)
	local f = frameUnder(parent)
	f:SetSize(16, 16)
	-- A badge's dark disc and ring, under the glyph.
	f.back = f:CreateTexture(nil, "ARTWORK", nil, 0)
	f.back:SetAllPoints()
	f.back:SetTexture(T.MEDIA .. "pin-disc")
	f.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
	f.ring:SetAllPoints()
	f.ring:SetTexture(T.MEDIA .. "dot-open")
	f.tex = f:CreateTexture(nil, "OVERLAY")
	f.num = T.Text(f, "small", "accent", "OVERLAY")
	f.num:SetPoint("CENTER", 0, 0)
	f.num:SetJustifyH("CENTER")
	f.num:SetShadowOffset(1, -1)
	f.num:SetShadowColor(0, 0, 0, 1)
	f:EnableMouse(true)
	f:SetScript("OnEnter", tooltip)
	f:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	return f
end

-- `k` scales the pin (smaller on the minimap).
local function dress(f, pin, k)
	local look = LOOK[pin.kind] or LOOK.goal
	f.pin = pin
	f.tex:SetTexture(T.MEDIA .. look.tex)
	local c = pin.rgb or T.Color(look.color)
	f.tex:SetVertexColor(c[1], c[2], c[3], look.alpha)
	local size = look.size
	if pin.kind == "step" and pin.label then size = max(size, 7 * #pin.label + 4) end -- room for "128"
	size = size * (k or 1)
	f.size = size
	f:SetSize(size, size)
	local glyph = size * (look.badge or 1)
	f.tex:ClearAllPoints()
	f.tex:SetPoint("CENTER", f, "CENTER", 0, 0)
	f.tex:SetSize(glyph, glyph)
	if look.badge then
		local bg = T.Color("bg")
		f.back:SetVertexColor(bg[1], bg[2], bg[3], Pins.BADGE_ALPHA)
		f.back:Show()
		f.ring:SetVertexColor(c[1], c[2], c[3], look.alpha)
		f.ring:SetShown(look.ring == true)
	else
		f.back:Hide()
		f.ring:Hide()
	end
	-- A step number: on the dark disc, or beside the lead's ring.
	f.num:SetText(pin.label or "")
	f.num:ClearAllPoints()
	if pin.label and pin.kind == "lead" then
		f.num:SetPoint("LEFT", f, "RIGHT", 2, 0)
		T.TextColor(f.num, "accent")
	else
		f.num:SetPoint("CENTER", 0, 0)
		T.TextColor(f.num, "accent")
	end
end

---------------------------------------------------------------------------
-- What to show
---------------------------------------------------------------------------

local function stepPins()
	return ns.Engine and ns.Engine.Pins and ns.Engine.Pins() or {}
end


-- Dungeon entrances for the character's level (world map only).
local function dungeonPins()
	if not (ns.Get("pins.dungeons") and ns.Dungeons) then return {} end
	local out = {}
	local level = ns.Quests.Player().level or 1
	for _, d in ipairs(ns.Dungeons.ForLevel(level)) do
		for _, e in ipairs(d.entrances) do
			out[#out + 1] = { map = e[1], x = e[2], y = e[3], kind = "dungeon", title = d.name,
				sub = ("%s, levels %d-%d%s"):format(d.raid and "Raid" or "Dungeon", d.low, d.high, e[4] and "  ·  entrance not yet checked on Forever" or "") }
		end
	end
	return out
end
Pins.DungeonPins = dungeonPins

local function pinKey(p) return ("%d:%.1f:%.1f"):format(p.map, p.x, p.y) end

-- What a map shows, bottom to top: quest markers, dungeon entrances (world
-- map), then the step's own pins. A quest marker where the step already has
-- a pin is left out.
local function pinsFor(map, setting, withDungeons)
	local step = stepPins()
	local taken = {}
	for _, p in ipairs(step) do if p.map and p.x then taken[pinKey(p)] = true end end
	local list = {}
	-- Herb and ore nodes at the bottom (Professions/Gathering.lua).
	if map and ns.Gathering then
		for _, p in ipairs(ns.Gathering.Pins(map, withDungeons and "pins.gather" or "pins.gatherMinimap")) do list[#list + 1] = p end
	end
	if map and ns.Get(setting) and ns.QuestMarkers then
		for _, p in ipairs(ns.QuestMarkers.ForMap(map)) do
			if not taken[pinKey(p)] then list[#list + 1] = p end
		end
	end
	if withDungeons then for _, p in ipairs(dungeonPins()) do list[#list + 1] = p end end
	for _, p in ipairs(step) do list[#list + 1] = p end
	return list
end
Pins.PinsFor = pinsFor

---------------------------------------------------------------------------
-- World map
---------------------------------------------------------------------------

local wm = { pins = {}, active = 0 }
Pins.world = wm

-- The layer sits above every other frame on the canvas: Forever's map stacks
-- its own frames far above the canvas (level 2920 seen in game), so a fixed
-- level put the pins under the map. Only Pathwise's own layer is changed.
local MAX_LEVEL = 9000
local function raiseWorld(canvas)
	local layer = wm.layer
	local top = canvas:GetFrameLevel() or 0
	for _, f in ipairs({ canvas:GetChildren() }) do
		if f ~= layer then
			local l = f.GetFrameLevel and f:GetFrameLevel()
			if type(l) == "number" and l > top then top = l end
		end
	end
	local want = math.min(top + 10, MAX_LEVEL)
	if layer:GetFrameLevel() ~= want then layer:SetFrameLevel(want) end
end
Pins.RaiseWorld = raiseWorld

local function drawWorld()
	local map = WorldMapFrame
	if not (wm.layer and map and map:IsShown()) then return end
	local id = map:GetMapID()
	local canvas = map:GetCanvas()
	raiseWorld(canvas)
	local w, h = canvas:GetWidth() or 0, canvas:GetHeight() or 0
	local scale = map.GetCanvasScale and map:GetCanvasScale() or 1
	if not scale or scale <= 0 then scale = 1 end
	wm.mapID, wm.width, wm.height, wm.scale = id, w, h, scale
	local n = 0
	if ns.Get("pins.map") and w > 0 then
		local list = pinsFor(id, "pins.quests", true)
		for _, pin in ipairs(list) do
			if pin.map == id then
				n = n + 1
				local f = wm.pins[n]
				if not f then
					f = makePin(wm.layer)
					wm.pins[n] = f
				end
				dress(f, pin)
				f:SetScale(1 / scale) -- the same size on screen at any zoom
				f:ClearAllPoints()
				f:SetPoint("CENTER", wm.layer, "TOPLEFT", w * pin.x / 100 * scale, -h * pin.y / 100 * scale)
				f:Show()
			end
		end
	end
	for i = n + 1, #wm.pins do wm.pins[i]:Hide() end
	wm.active = n
end
Pins.DrawWorld = drawWorld

-- A layer under the map's canvas, covering it; its OnUpdate runs only while
-- the map is shown and redraws when the map, its size or its zoom changes.
local function attachWorld()
	local map = WorldMapFrame
	if wm.layer or not (map and map.GetCanvas) then return end
	local canvas = map:GetCanvas()
	if not canvas then return end
	local layer = frameUnder(canvas)
	layer:SetAllPoints(canvas)
	layer:SetFrameLevel((canvas:GetFrameLevel() or 1) + 50)
	wm.layer = layer
	local since = 0
	layer:SetScript("OnUpdate", function(_, elapsed)
		-- The map makes frames as it is used: checked again once a second.
		since = since + (elapsed or 0)
		if since >= 1 then
			since = 0
			raiseWorld(canvas)
		end
		local id = map:GetMapID()
		local s = map.GetCanvasScale and map:GetCanvasScale() or 1
		if id ~= wm.mapID or s ~= wm.scale or canvas:GetWidth() ~= wm.width or wm.dirty then
			wm.dirty = false
			drawWorld()
		end
	end)
end
Pins.AttachWorld = attachWorld

---------------------------------------------------------------------------
-- Minimap
---------------------------------------------------------------------------

local mm = { pins = {}, list = {} }
Pins.mini = mm

local function viewRadius()
	if C_Minimap and C_Minimap.GetViewRadius then
		local r = C_Minimap.GetViewRadius()
		if type(r) == "number" and r > 0 then return r end
	end
	local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
	local d = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or OUTDOOR[0]
	return d / 2
end

local function rotating()
	return GetCVar ~= nil and GetCVar("rotateMinimap") == "1"
end

local function square()
	return GetMinimapShape ~= nil and GetMinimapShape() == "SQUARE"
end

-- Pixels from the minimap's centre (east, north) for a world offset from the
-- player (yards north, yards west), and whether it lies beyond the rim.
function Pins.Project(dNorth, dWest, facing, radius, half, rotate, isSquare)
	local k = half / radius
	local x, y = -dWest * k, dNorth * k
	if rotate and facing then
		local c, s = cos(facing), sin(facing)
		x, y = x * c + y * s, -x * s + y * c
	end
	local reach = isSquare and max(abs(x), abs(y)) or sqrt(x * x + y * y)
	if reach > half then return x * half / reach, y * half / reach, true end
	return x, y, false
end

local function placeMini()
	if not Minimap then return end
	local inst, pn, pw = C.PlayerWorldPosition()
	local radius = viewRadius()
	local half = (Minimap:GetWidth() or 140) / 2 - 4
	local rotate = rotating()
	local facing = rotate and C.PlayerFacing() or nil
	local isSquare = square()
	for i, pin in ipairs(mm.list) do
		local f = mm.pins[i]
		local ok = false
		if inst and pin.inst == inst then
			local x, y, out = Pins.Project(pin.north - pn, pin.west - pw, facing, radius, half, rotate, isSquare)
			if not out or pin.kind == "lead" then
				f:ClearAllPoints()
				f:SetPoint("CENTER", Minimap, "CENTER", x, y)
				f:SetAlpha(out and 0.7 or 1)
				ok = true
			end
		end
		f:SetShown(ok)
	end
end
Pins.PlaceMini = placeMini

local function buildMini()
	if not (Minimap and ns.Get("pins.minimap")) then
		for _, f in ipairs(mm.pins) do f:Hide() end
		mm.list = {}
		return
	end
	mm.list = {}
	for _, pin in ipairs(pinsFor((C.PlayerMapPosition()), "pins.questsMinimap", false)) do
		local inst, north, west = C.MapToWorld(pin.map, pin.x, pin.y)
		if inst then
			pin.inst, pin.north, pin.west = inst, north, west
			mm.list[#mm.list + 1] = pin
		end
	end
	for i, pin in ipairs(mm.list) do
		local f = mm.pins[i]
		if not f then
			f = makePin(Minimap)
			mm.pins[i] = f
		end
		dress(f, pin, (pin.kind == "spot" or pin.kind == "objective") and 0.8 or 0.75)
	end
	for i = #mm.list + 1, #mm.pins do mm.pins[i]:Hide() end
	placeMini()
end
Pins.BuildMini = buildMini

-- Positions move as the player does: placed ten times a second while there
-- are minimap pins; nothing runs when there are none.
local driver = CreateFrame("Frame")
local acc = 0
driver:SetScript("OnUpdate", function(_, elapsed)
	acc = acc + elapsed
	if acc < 0.1 then return end
	acc = 0
	if #mm.list > 0 then placeMini() end
end)

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

function Pins.Refresh()
	wm.dirty = true
	drawWorld()
	buildMini()
end

ns.On("PINS_CHANGED", Pins.Refresh)
ns.On("SETTING_CHANGED", function(path) if type(path) == "string" and path:find("^pins%.") then Pins.Refresh() end end)
ns.On("READY", function() attachWorld() Pins.Refresh() end)
ns.RegisterEvent("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" then attachWorld() end end)
ns.RegisterEvent("PLAYER_LEVEL_UP", function() wm.dirty = true end)
-- A new zone: its quest markers on the minimap.
ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() buildMini() end)
