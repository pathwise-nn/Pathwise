-- The Signature Hub (v2): Pathwise's full window (frame PathwiseHub), opened
-- from the minimap button, a key, /pw hub, or the guide's hub button. Three
-- columns, each its own rounded panel:
--
--   menu        the mark; Leveling (this), Professions, Routes, Dungeons;
--               "On screen": which guide style shows while you play
--               (Tracker, Window, Minimal, or none), the compass and your
--               coordinates; Settings
--   routes      Leveling / Class / Professions tabs, a card per route (the
--               one you follow and the ones after it); professions you know
--               with their skill bars, and the recipe book
--   guide       the route's crest and name, "Alliance · Levels 12-17", its
--               progress; the next steps down the side; the step: its place,
--               note, objectives as checkboxes, the optional profession task,
--               your level, XP per hour and coordinates; Back, Skip, Report,
--               Next
--
-- Escape closes it. Drag any column's empty space to move it (hub.point).
-- Drawn from the guide's view (GUIDE_VIEW) like the on-screen guide.

local ADDON, ns = ...
local T, Guide = ns.Theme, ns.Guide
local floor, max, min = math.floor, math.max, math.min

local Hub = {}
ns.Hub = Hub

ns.Defaults("hub", { point = nil, tab = "Leveling", locked = false, width = nil, height = nil })

Hub.W, Hub.H = 1160, 720 -- the size it opens at; drag its corner for another
Hub.MIN_W, Hub.MAX_W, Hub.MIN_H, Hub.MAX_H = 720, 1800, 560, 1100
Hub.NARROW = 1040 -- narrower: no routes column (Routes and Professions stay in the menu)
local RAIL_W, MID_W, GAP = 168, 360, 16
local ROUTES_H = 330

-- The size wanted: the one dragged to (hub.width, hub.height), else the usual.
function Hub.Size()
	local w, h = ns.Get("hub.width"), ns.Get("hub.height")
	w = type(w) == "number" and math.min(Hub.MAX_W, math.max(Hub.MIN_W, w)) or Hub.W
	h = type(h) == "number" and math.min(Hub.MAX_H, math.max(Hub.MIN_H, h)) or Hub.H
	return w, h
end
Hub.MAX_ROWS = 5

local W = {}
Hub.frames = W

local function height(fs) return fs:IsShown() and max(0, fs:GetStringHeight() or 0) or 0 end

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("hub.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

-- A column: a rounded window ground that also moves the hub when dragged.
local function column(x, y, w, h)
	local c = CreateFrame("Frame", nil, W.frame)
	c:SetPoint("TOPLEFT", W.frame, "TOPLEFT", x, -y)
	c:SetSize(w, h)
	T.RoundWindow(c, 12)
	c:EnableMouse(true)
	c:RegisterForDrag("LeftButton")
	c:SetScript("OnDragStart", function() if T.Movable("hub.locked") then W.frame:StartMoving() end end)
	c:SetScript("OnDragStop", function() W.frame:StopMovingOrSizing() savePoint(W.frame) end)
	return c
end

-- A menu row: glyph and label; `active` draws it selected.
local function menuButton(parent, glyph, label, onClick, h)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(h or 40)
	T.Round(b, "bg", false, 8)
	b.icon = T.Glyph(b, glyph, 16, "text2")
	b.icon:SetPoint("LEFT", 12, 0)
	b.text = T.Text(b, "button", "text2")
	b.value = T.Text(b, "small", "muted")
	b.value:SetPoint("RIGHT", -10, 0)
	b.value:SetJustifyH("RIGHT")
	b.value:SetWordWrap(false)
	b.text:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
	b.text:SetPoint("RIGHT", b.value, "LEFT", -6, 0)
	b.text:SetWordWrap(false)
	b.text:SetText(label)
	local function paint(hover)
		local a = T.Color("accent")
		if b.active then
			T.PaintRound(b, { a[1], a[2], a[3], 0.14 })
			b.icon:SetVertexColor(a[1], a[2], a[3], 1)
			T.TextColor(b.text, "text")
		else
			local g = T.Color("hover")
			T.PaintRound(b, { g[1], g[2], g[3], hover and 1 or 0 })
			local c = T.Color(hover and "text" or "text2")
			b.icon:SetVertexColor(c[1], c[2], c[3], 1)
			T.TextColor(b.text, hover and "text" or "text2")
		end
	end
	function b:SetActive(on) self.active = on and true or false paint(false) end
	b:SetScript("OnEnter", function() paint(true) end)
	b:SetScript("OnLeave", function() paint(false) end)
	b:SetScript("OnClick", onClick)
	b:SetActive(false)
	return b
end

-- A card in the routes or professions list: a tile, two lines, a mark.
local function listCard(parent)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(58)
	T.Round(b, "bg2", "divider", 8)
	b.tile = CreateFrame("Frame", nil, b)
	b.tile:SetSize(48, 38)
	b.tile:SetPoint("LEFT", 10, 0)
	T.Round(b.tile, "hover", false, 6)
	b.glyph = T.Glyph(b.tile, "glyph-zones", 18, "text")
	b.glyph:SetPoint("CENTER")
	-- A class's or profession's icon (the game's, else Pathwise's).
	b.icon = T.Mark(b.tile, 30)
	b.icon:SetPoint("CENTER")
	b.icon:Hide()
	b.title = T.Text(b, "body", "text")
	T.Font(b.title, "quest")
	b.title:SetWordWrap(false)
	b.sub = T.Text(b, "small", "text2")
	b.sub:SetWordWrap(false)
	b.mark = T.Glyph(b, "glyph-chevron", 14, "text2")
	b.mark:SetPoint("RIGHT", -12, 0)
	b.value = T.Text(b, "meta", "text2")
	b.value:SetJustifyH("RIGHT")
	b.bar = T.Bar(b, 4)
	b:SetScript("OnEnter", function(self) if not self.current then T.PaintRound(self, "hover", "border") end end)
	b:SetScript("OnLeave", function(self) self:Paint() end)
	function b:Paint()
		if self.current then
			local a = T.Color("accent")
			T.PaintRound(self, { a[1], a[2], a[3], 0.08 }, "accent")
		else
			T.PaintRound(self, "bg2", "divider")
		end
	end
	return b
end

---------------------------------------------------------------------------
-- Route maps: the zone's own map (the game's art) with the route drawn
-- over it as a dotted path, from its first step to its last.
---------------------------------------------------------------------------

-- The route's path on its zone: up to `n` points (0-1 across and down the
-- map) spread evenly along the steps' places, in order. nil when the route
-- has fewer than two places on its map.
function Hub.RoutePath(r, n)
	local pts = {}
	for _, step in ipairs(r and r.steps or {}) do
		for _, goal in ipairs(step) do
			local at = goal.at
			if type(at) == "table" and at[1] == r.map and at[2] and at[3] then
				local last = pts[#pts]
				local x, y = at[2] / 100, at[3] / 100
				if not last or math.abs(last[1] - x) + math.abs(last[2] - y) > 0.01 then pts[#pts + 1] = { x, y } end
			end
		end
	end
	if #pts < 2 then return nil end
	-- Evenly along the way, so the dots read as a line.
	local total, lens = 0, { 0 }
	for i = 2, #pts do
		total = total + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		lens[i] = total
	end
	if total <= 0 then return nil end
	local out, seg = {}, 2
	for k = 0, n - 1 do
		local d = total * k / (n - 1)
		while seg < #pts and lens[seg] < d do seg = seg + 1 end
		local a, b = pts[seg - 1], pts[seg]
		local span = lens[seg] - lens[seg - 1]
		local t = span > 0 and (d - lens[seg - 1]) / span or 0
		out[#out + 1] = { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t }
	end
	return out
end

-- The zone map's art: its tiles and their size, or nil (no such art here).
function Hub.MapArt(map)
	if not (map and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
	local ok, layers = pcall(C_Map.GetMapArtLayers, map)
	local l = ok and type(layers) == "table" and layers[1]
	if not (l and l.tileWidth and l.layerWidth) then return nil end
	local ok2, files = pcall(C_Map.GetMapArtLayerTextures, map, 1)
	if not (ok2 and type(files) == "table" and #files > 0) then return nil end
	return {
		files = files, tw = l.tileWidth, th = l.tileHeight, lw = l.layerWidth, lh = l.layerHeight,
		cols = math.ceil(l.layerWidth / l.tileWidth), rows = math.ceil(l.layerHeight / l.tileHeight),
	}
end

local PATH_DOTS = 40
local function mapView(tile)
	local v = CreateFrame("Frame", nil, tile)
	v:SetPoint("TOPLEFT", 2, -2)
	v:SetPoint("BOTTOMRIGHT", -2, 2)
	if v.SetClipsChildren then v:SetClipsChildren(true) end
	v.art = CreateFrame("Frame", nil, v)
	v.art:SetAllPoints()
	v.tiles = {}
	v.shade = v.art:CreateTexture(nil, "ARTWORK", nil, 2)
	v.shade:SetAllPoints()
	v.dots = {}
	for i = 1, PATH_DOTS do
		local d = v.art:CreateTexture(nil, "OVERLAY")
		d:SetTexture(T.MEDIA .. "dot-done")
		d:SetSize(i == 1 and 7 or (i == PATH_DOTS and 8 or 2.5), i == 1 and 7 or (i == PATH_DOTS and 8 or 2.5))
		v.dots[i] = d
	end
	return v
end

-- Draws route `r` on map view `v`, `w` by `h`.
local function drawMapView(v, r, w, h)
	local art = T.GameArt() and Hub.MapArt(r.map)
	for _, t in ipairs(v.tiles) do t:Hide() end
	if art then
		local scale = w / art.lw
		for row = 0, art.rows - 1 do
			for col = 0, art.cols - 1 do
				local i = row * art.cols + col + 1
				local file = art.files[i]
				if file then
					local t = v.tiles[i]
					if not t then
						t = v.art:CreateTexture(nil, "ARTWORK", nil, 1)
						v.tiles[i] = t
					end
					t:SetTexture(file)
					t:SetSize(art.tw * scale, art.th * scale)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", v.art, "TOPLEFT", col * art.tw * scale, -row * art.th * scale)
					t:Show()
				end
			end
		end
	end
	-- Over the art, a light shade so the path reads; none on a plain tile.
	T.SetColor(v.shade, "bg", art and 0.25 or 0)
	local path = Hub.RoutePath(r, PATH_DOTS)
	for i, d in ipairs(v.dots) do
		local p = path and path[i]
		d:SetShown(p ~= nil)
		if p then
			d:ClearAllPoints()
			d:SetPoint("CENTER", v.art, "TOPLEFT", p[1] * w, -p[2] * h)
			local c = T.Color(i == 1 and "success" or (i == PATH_DOTS and "accent" or "text"))
			d:SetVertexColor(c[1], c[2], c[3], 1)
		end
	end
end
Hub.DrawMapView = drawMapView

-- A tile colour by level band (every 5 levels), so the cards read at a
-- glance: the routes after yours come in other colours.
local BANDS = { "#3F8F6A", "#4F8F4A", "#C9A34F", "#B5603E", "#3F6F8F", "#5B6FB0", "#7A5BB0", "#9E3D52", "#8F5A3F", "#5F7F8F", "#6A8F5A", "#B0803F" }
function Hub.BandColor(level)
	local i = min(#BANDS, max(1, floor((level or 1) / 5) + 1))
	return T.Hex(BANDS[i])
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function buildRail()
	local rail = column(0, 0, RAIL_W, Hub.H)
	W.rail = rail
	W.logo = T.Logo(rail, 64)
	W.logo:SetPoint("TOP", 0, -16)
	local name = T.TextAt(rail, "semibold", 15, "text")
	name:SetPoint("TOP", W.logo, "BOTTOM", 0, -6)
	name:SetJustifyH("CENTER")
	name:SetText("Pathwise")
	local sub = T.Text(rail, "label", "text2")
	sub:SetPoint("TOP", name, "BOTTOM", 0, -4)
	sub:SetJustifyH("CENTER")
	sub:SetText("LEVELING · PROFESSIONS")

	W.menu = {}
	local y = 136
	for _, spec in ipairs({
		{ "book", "glyph-book", "Leveling", function() Hub.Focus() end },
		{ "prof", "glyph-prof", "Professions", function() ns.Fire("SHOW_PROFESSIONS") end },
		{ "routes", "glyph-list", "Routes", function() ns.Fire("SHOW_ZONES") end },
		{ "dungeons", "glyph-dungeon", "Dungeons", function() ns.Fire("SHOW_DUNGEONS") end },
	}) do
		local b = menuButton(rail, spec[2], spec[3], spec[4])
		b:SetPoint("TOPLEFT", 10, -y)
		b:SetPoint("RIGHT", -10, 0)
		W.menu[spec[1]] = b
		y = y + 44
	end
	W.menu.book:SetActive(true)

	-- On screen: the guide style while you play, the compass, coordinates.
	W.onLabel = T.Text(rail, "label", "muted")
	W.onLabel:SetPoint("TOPLEFT", 20, -(y + 14))
	W.onLabel:SetText("ON SCREEN")
	y = y + 34
	W.styles = {}
	for _, spec in ipairs({ { "tracker", "glyph-list", "Tracker" }, { "window", "glyph-grid", "Window" }, { "minimal", "glyph-collapse", "Minimal" }, { "off", "glyph-close", "Hidden" } }) do
		local b = menuButton(rail, spec[2], spec[3], function() Hub.SetStyle(spec[1]) end, 32)
		b:SetPoint("TOPLEFT", 10, -y)
		b:SetPoint("RIGHT", -10, 0)
		W.styles[spec[1]] = b
		y = y + 34
	end
	y = y + 8
	W.compassRow = menuButton(rail, "glyph-compass", "Compass", function() ns.Set("compass.shown", not ns.Get("compass.shown")) end, 32)
	W.compassRow:SetPoint("TOPLEFT", 10, -y)
	W.compassRow:SetPoint("RIGHT", -10, 0)
	y = y + 34
	W.coordsRow = menuButton(rail, "glyph-goto", "Coordinates", function() ns.Set("compass.coords", not ns.Get("compass.coords")) end, 32)
	W.coordsRow:SetPoint("TOPLEFT", 10, -y)
	W.coordsRow:SetPoint("RIGHT", -10, 0)

	W.settingsRow = menuButton(rail, "glyph-settings", "Settings", function() ns.Fire("SHOW_SETTINGS") end)
	W.settingsRow:SetPoint("BOTTOMLEFT", 10, 12)
	W.settingsRow:SetPoint("RIGHT", -10, 0)
end

local TABS = { "Leveling", "Class", "Professions" }

local function buildMiddle()
	local x = RAIL_W + GAP
	local routesH = 330
	local routes = column(x, 0, MID_W, routesH)
	W.routes = routes
	local h = T.TextAt(routes, "semibold", 17, "text")
	h:SetPoint("TOPLEFT", 18, -18)
	h:SetText("Routes")
	local search = T.IconButton(routes, "search", "The route book: every route by level", function() ns.Fire("SHOW_ZONES") end, 28)
	search:SetPoint("TOPRIGHT", -12, -14)
	-- Tabs: a segmented row.
	local seg = CreateFrame("Frame", nil, routes)
	seg:SetPoint("TOPLEFT", 16, -52)
	seg:SetPoint("TOPRIGHT", -16, -52)
	seg:SetHeight(34)
	T.Round(seg, "bg2", false, 8)
	W.tabs = {}
	local tw = (MID_W - 32 - 6) / #TABS
	for i, name in ipairs(TABS) do
		local b = CreateFrame("Button", nil, seg)
		b:SetSize(tw, 28)
		b:SetPoint("LEFT", 3 + (i - 1) * tw, 0)
		T.Round(b, "bg2", false, 6)
		b.text = T.Text(b, "button", "text2")
		b.text:SetPoint("CENTER")
		b.text:SetText(name)
		b.line = b:CreateTexture(nil, "OVERLAY")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 8, 0)
		b.line:SetPoint("BOTTOMRIGHT", -8, 0)
		T.SetColor(b.line, "accent")
		b:SetScript("OnClick", function() ns.Set("hub.tab", name) Hub.Refresh() end)
		W.tabs[name] = b
	end
	W.routeCards = {}
	for i = 1, 3 do
		local c = listCard(routes)
		c:SetPoint("TOPLEFT", 16, -(98 + (i - 1) * 66))
		c:SetPoint("RIGHT", -16, 0)
		c.tile:SetSize(72, 46)
		c.map = mapView(c.tile)
		c.title:SetPoint("TOPLEFT", c.tile, "TOPRIGHT", 12, -1)
		c.title:SetPoint("RIGHT", c.mark, "LEFT", -8, 0)
		c.sub:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -4)
		c.sub:SetPoint("RIGHT", c.mark, "LEFT", -8, 0)
		c.value:Hide()
		c.bar:Hide()
		W.routeCards[i] = c
	end
	W.routesEmpty = T.Text(routes, "meta", "text2")
	W.routesEmpty:SetPoint("TOPLEFT", 18, -104)
	W.routesEmpty:SetPoint("RIGHT", -18, 0)

	local prof = column(x, routesH + GAP, MID_W, Hub.H - routesH - GAP)
	W.prof = prof
	local ph = T.TextAt(prof, "semibold", 17, "text")
	ph:SetPoint("TOPLEFT", 18, -18)
	ph:SetText("Professions")
	W.profCount = T.Text(prof, "meta", "text2")
	W.profCount:SetPoint("TOPRIGHT", -18, -21)
	W.profCount:SetJustifyH("RIGHT")
	W.profCards = {}
	for i = 1, 4 do
		local c = listCard(prof)
		c:SetPoint("TOPLEFT", 16, -(54 + (i - 1) * 64))
		c:SetPoint("RIGHT", -16, 0)
		c.tile:SetSize(38, 38)
		c.glyph:Hide()
		c.icon:SetSize(30, 30)
		c.icon:Show()
		c.mark:Show()
		c.value:SetPoint("RIGHT", c.mark, "LEFT", -8, 0)
		c.value:SetPoint("TOP", c, "TOP", 0, -12)
		c.title:SetPoint("TOPLEFT", c.tile, "TOPRIGHT", 12, -2)
		c.title:SetPoint("RIGHT", c.value, "LEFT", -8, 0)
		c.bar:SetPoint("TOPLEFT", c.title, "BOTTOMLEFT", 0, -9)
		c.bar:SetPoint("RIGHT", c.mark, "LEFT", -8, 0)
		c.sub:Hide()
		W.profCards[i] = c
	end
	W.profEmpty = T.Text(prof, "meta", "text2")
	W.profEmpty:SetPoint("TOPLEFT", 18, -58)
	W.profEmpty:SetPoint("RIGHT", -18, 0)
	W.recipes = T.RoundButton(prof, "Open the recipe book", "default", function() ns.Panels.OpenRecipeBook(nil) end, 40)
	W.recipes:SetPoint("BOTTOMLEFT", 16, 16)
	W.recipes:SetPoint("BOTTOMRIGHT", -16, 16)
end

local function buildMain()
	local main = column(0, 0, Hub.W, Hub.H) -- placed by Hub.Layout
	W.main = main
	-- Header.
	W.crest = T.Crest(main, 48)
	W.crest:SetPoint("TOPLEFT", 24, -22)
	W.eyebrow = T.Text(main, "label", "accent")
	W.eyebrow:SetPoint("TOPLEFT", W.crest, "TOPRIGHT", 14, 0)
	W.title = T.TextAt(main, "semibold", 24, "text")
	W.title:SetPoint("TOPLEFT", W.eyebrow, "BOTTOMLEFT", 0, -4)
	W.title:SetWordWrap(false)
	W.routeLine = T.Text(main, "meta", "text2")
	W.routeLine:SetPoint("TOPLEFT", W.title, "BOTTOMLEFT", 0, -4)
	W.close = T.IconButton(main, "close", "Close", function() Hub.Show(false) end, 30)
	W.close:SetPoint("TOPRIGHT", -14, -16)
	W.lock = T.PinButton(main, "hub.locked", 30)
	W.lock:SetPoint("RIGHT", W.close, "LEFT", -2, 0)
	W.title:SetPoint("RIGHT", W.lock, "LEFT", -12, 0)
	W.headLine = T.Divider(main)
	W.headLine:SetPoint("TOPLEFT", 0, -98)
	W.headLine:SetPoint("TOPRIGHT", 0, -98)

	-- Progress and the step counter.
	W.pill = CreateFrame("Frame", nil, main)
	W.pill:SetSize(84, 28)
	W.pill:SetPoint("TOPRIGHT", -24, -112)
	T.Round(W.pill, "bg2", "border", 14)
	W.pillText = T.TextAt(W.pill, "semibold", 14, "text")
	W.pillText:SetPoint("CENTER")
	W.pillText:SetJustifyH("CENTER")
	W.bar = T.Bar(main, 6)
	W.bar:SetPoint("LEFT", main, "TOPLEFT", 24, -126)
	W.bar:SetPoint("RIGHT", W.pill, "LEFT", -14, 0)

	-- The steps down the side.
	W.steps = {}
	W.stepLine = main:CreateTexture(nil, "BORDER")
	W.stepLine:SetWidth(2)
	T.SetColor(W.stepLine, "border")
	for i = 1, 7 do
		local s = CreateFrame("Frame", nil, main)
		s:SetSize(140, 36)
		s:SetPoint("TOPLEFT", 20, -(156 + (i - 1) * 40))
		T.Round(s, "bg", false, 18)
		s.dot = s:CreateTexture(nil, "ARTWORK")
		s.dot:SetPoint("LEFT", 10, 0)
		s.text = T.Text(s, "body", "text2")
		s.text:SetPoint("LEFT", 32, 0)
		s.text:SetPoint("RIGHT", -8, 0)
		s.text:SetWordWrap(false)
		W.steps[i] = s
	end

	-- The step card.
	local card = CreateFrame("Frame", nil, main)
	W.card = card
	card:SetPoint("TOPLEFT", 176, -152)
	card:SetPoint("BOTTOMRIGHT", -24, 76)
	T.Round(card, "bg2", "divider", 10)
	W.label = T.Text(card, "label", "accent")
	W.stepTitle = T.TextAt(card, "semibold", 22, "text")
	W.pin = T.Glyph(card, "glyph-goto", 14, "accent")
	W.place = T.Text(card, "meta", "text2")
	W.place:SetWordWrap(false)
	W.note = T.Text(card, "body", "text")
	W.divider = T.Divider(card)
	W.objLabel = T.Text(card, "label", "text2")
	W.objLabel:SetText("OBJECTIVES")
	W.rows = {}
	W.empty = T.Text(card, "body", "text2")

	local d = CreateFrame("Frame", nil, card)
	W.detour = d
	do
		local a = T.Color("accent")
		T.Round(d, { a[1], a[2], a[3], 0.06 }, { a[1], a[2], a[3], 0.45 }, 8)
	end
	d.star = T.Glyph(d, "glyph-star", 20, "accent")
	d.star:SetPoint("LEFT", 14, 0)
	d.skip = T.IconButton(d, "close", "Skip this detour", function() ns.Fire("DETOUR_SKIP", Guide.View() and Guide.View().detour) end, 26)
	d.skip:SetPoint("RIGHT", -8, 0)
	d.go = T.RoundButton(d, "Go", "outline", function() ns.Fire("DETOUR_GO", Guide.View() and Guide.View().detour) end, 32)
	d.go:SetWidth(64)
	d.go:SetPoint("RIGHT", d.skip, "LEFT", -6, 0)
	d.label = T.Text(d, "label", "accent")
	d.label:SetPoint("TOPLEFT", 46, -12)
	d.label:SetPoint("RIGHT", d.go, "LEFT", -10, 0)
	d.label:SetWordWrap(false)
	d.text = T.Text(d, "body", "text")
	T.Font(d.text, "quest")
	d.text:SetPoint("TOPLEFT", d.label, "BOTTOMLEFT", 0, -4)
	d.text:SetPoint("RIGHT", d.go, "LEFT", -10, 0)
	d.sub = T.Text(d, "small", "text2")
	d.sub:SetPoint("TOPLEFT", d.text, "BOTTOMLEFT", 0, -3)
	d.sub:SetPoint("RIGHT", d.go, "LEFT", -10, 0)

	-- Stats along the card's bottom.
	W.statsLine = T.Divider(card)
	W.statsLine:SetPoint("BOTTOMLEFT", 20, 52)
	W.statsLine:SetPoint("BOTTOMRIGHT", -20, 52)
	W.level = T.Text(card, "body", "text")
	W.level:SetPoint("BOTTOMLEFT", 20, 28)
	W.levelBar = T.Bar(card, 4)
	W.levelBar:SetPoint("BOTTOMLEFT", 20, 18)
	W.rate = T.Text(card, "meta", "text2")
	W.rate:SetPoint("BOTTOMRIGHT", -20, 28)
	W.rate:SetJustifyH("RIGHT")
	W.coords = T.Text(card, "small", "muted")
	W.coords:SetPoint("BOTTOMRIGHT", -20, 12)
	W.coords:SetJustifyH("RIGHT")

	-- Footer.
	W.back = T.RoundButton(main, "Back", "default", function() ns.Fire("GUIDE_BACK") end, 40)
	W.back:SetWidth(96)
	W.back:SetPoint("BOTTOMLEFT", 24, 22)
	W.skip = T.RoundButton(main, "Skip", "default", function() ns.Fire("GUIDE_SKIP") end, 40)
	W.skip:SetWidth(88)
	W.skip:SetPoint("LEFT", W.back, "RIGHT", 10, 0)
	W.report = T.IconButton(main, "flag", "Report this step", function() ns.Fire("REPORT_STEP", Guide.View()) end, 40)
	W.report:SetPoint("LEFT", W.skip, "RIGHT", 10, 0)
	W.next = T.RoundButton(main, "Next", "primary", function() ns.Fire("GUIDE_NEXT") end, 40)
	W.next:SetWidth(120)
	W.next:SetPoint("BOTTOMRIGHT", -24, 22)
end

local function build()
	local f = CreateFrame("Frame", "PathwiseHub", UIParent)
	W.frame = f
	local w, h = Hub.Size()
	f:SetSize(w, h)
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false) -- the gaps between the columns let clicks through
	T.TrackScale(f)
	local saved = ns.Get("hub.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else
		f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
	end
	buildRail()
	buildMiddle()
	buildMain()
	Hub.Layout(w, h)
	-- The corner grip: any size, wide or tall; the columns follow.
	W.grip = T.Grip(f, {
		minW = Hub.MIN_W, maxW = Hub.MAX_W, minH = Hub.MIN_H, maxH = Hub.MAX_H, height = true,
		lockPath = "hub.locked",
		onSize = function(gw, gh) Hub.Layout(gw, gh) Hub.Refresh() end,
		onDone = function(gw, gh)
			ns.Set("hub.width", gw)
			if gh then ns.Set("hub.height", gh) end
			savePoint(f)
		end,
		onReset = function() ns.Set("hub.width", nil) ns.Set("hub.height", nil) end,
	})
	-- Escape closes it, as the game's own windows.
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PathwiseHub") end
	f:SetScript("OnHide", function() ns.Fire("HUB_TOGGLED", false) end)
	f:Hide()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function player() return ns.Quests.Player() end

-- The cards for a tab: { { route, title, sub, current }, ... } (up to 3).
function Hub.RouteCards(tab)
	local E = ns.Engine
	local out = {}
	local function levels(r)
		local l = r.levels or {}
		return l[1] and (l[2] and l[2] ~= l[1] and ("%d-%d"):format(l[1], l[2]) or tostring(l[1])) or ""
	end
	if tab == "Leveling" then
		local r = E.Route()
		if r and (r.category or "Leveling") ~= "Leveling" then r = nil end
		local subs = { "Following now", "Next route", "Then" }
		local seen = {}
		while r and #out < 3 and not seen[r.id] do
			seen[r.id] = true
			out[#out + 1] = { route = r, title = ("%s   %s"):format(levels(r), r.title or r.id), sub = subs[#out + 1], current = #out == 0 }
			r = E.NextOf(r)
		end
		if #out == 0 then
			-- No route followed: the ones for your level.
			local lvl = player().level or 1
			for _, x in ipairs(E.RoutesFor(player(), "Leveling")) do
				if #out >= 3 then break end
				if (x.levels and x.levels[2] or 60) >= lvl then
					out[#out + 1] = { route = x, title = ("%s   %s"):format(levels(x), x.title or x.id), sub = "For your level" }
				end
			end
		end
	else
		local side = E.Side()
		local current = E.Route()
		for _, x in ipairs(E.RoutesFor(player(), tab)) do
			if #out >= 3 then break end
			local on = (side and side.id == x.id) or (current and current.id == x.id)
			out[#out + 1] = { route = x, title = (tab == "Class" and (levels(x) .. "   ") or "") .. (x.title or x.id), sub = on and "Following now" or (tab == "Class" and "Class route" or "Beside your route"), current = on }
		end
	end
	return out
end

local function drawRail()
	local style = ns.Get("guide.shown") and Guide.Style() or "off"
	for key, b in pairs(W.styles) do b:SetActive(key == style) end
	W.compassRow.value:SetText(ns.Get("compass.shown") and "On" or "Off")
	W.compassRow:SetActive(ns.Get("compass.shown"))
	W.coordsRow.value:SetText(ns.Get("compass.coords") and "On" or "Off")
	W.coordsRow:SetActive(ns.Get("compass.coords"))
end

local function drawMiddle()
	local tab = ns.Get("hub.tab") or "Leveling"
	for name, b in pairs(W.tabs) do
		local on = name == tab
		local a = T.Color("accent")
		T.PaintRound(b, on and { a[1], a[2], a[3], 0.16 } or "bg2")
		T.TextColor(b.text, on and "text" or "text2")
		b.line:SetShown(on)
	end
	local cards = Hub.RouteCards(tab)
	for i, c in ipairs(W.routeCards) do
		local data = cards[i]
		c:SetShown(data ~= nil)
		if data then
			c.current = data.current
			c:Paint()
			c.title:SetText(data.title)
			c.sub:SetText(data.sub or "")
			local r = data.route
			local leveling = tab == "Leveling"
			c.glyph:Hide()
			c.map:SetShown(leveling)
			c.icon:SetShown(not leveling)
			if leveling then
				-- The zone's map with the route across it.
				T.PaintRound(c.tile, Hub.BandColor(r.levels and r.levels[1]))
				drawMapView(c.map, r, 68, 42)
			elseif tab == "Class" then
				T.PaintRound(c.tile, "hover")
				c.icon:SetClass(r.classes and r.classes[1])
			else
				T.PaintRound(c.tile, "hover")
				c.icon:SetProfession((r.id or ""):match("professions/([%w%-]+)$"))
			end
			c:SetScript("OnClick", function()
				if tab == "Leveling" then ns.RouteBookWindow.OpenRoute(r) else ns.Panels.Open("routes") end
			end)
		end
	end
	W.routesEmpty:SetShown(#cards == 0)
	W.routesEmpty:SetText(tab == "Leveling" and "No leveling route for this character yet." or (ns.L("No %s routes for this character.")):format(ns.L(tab):lower()))

	local P = ns.Professions
	local known = P and P.Known() or {}
	W.profCount:SetText(#known > 0 and (ns.L("%d learned")):format(#known) or "")
	for i, c in ipairs(W.profCards) do
		local k = known[i]
		c:SetShown(k ~= nil and i <= (W.profFit or #W.profCards))
		if k and i <= (W.profFit or #W.profCards) then
			c.current = false
			c:Paint()
			c.title:SetText(k.prof.name)
			c.icon:SetProfession(k.prof.key)
			c.value:SetText(("%d / %d"):format(k.rank, k.cap))
			c.bar:SetProgress(k.cap > 0 and k.rank / k.cap or 0, MID_W - 32 - 48 - 12 - 34)
			local key = k.prof.key
			c:SetScript("OnClick", function() ns.Panels.OpenProfession(key) end)
		end
	end
	W.profEmpty:SetShown(#known == 0)
	W.profEmpty:SetText("No professions yet. Learn one at a trainer: Pathwise follows it beside your route.")
end

local function rowWidget(i)
	local r = W.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, W.card)
	r.check = T.Check(r, 18)
	r.check:SetPoint("TOPLEFT", 0, 0)
	r.text = T.Text(r, "body", "text")
	T.Font(r.text, "quest")
	r.text:SetPoint("TOPLEFT", 30, 0)
	r.count = T.Text(r, "meta", "text2")
	r.count:SetPoint("TOPRIGHT", 0, -1)
	r.count:SetJustifyH("RIGHT")
	r.text:SetPoint("RIGHT", r.count, "LEFT", -8, 0)
	W.rows[i] = r
	return r
end

local function drawMain(v)
	local MAIN_W = W.main:GetWidth() or Hub.W
	local card = W.card
	W.crest:SetFaction(v and v.faction)
	W.eyebrow:SetText(Guide.Eyebrow(v))
	W.title:SetText(v and v.route or "Pathwise")
	W.routeLine:SetText(Guide.RouteLine(v))
	W.pillText:SetText(v and v.count and ("%s%d|r %s/ %d|r"):format(T.Esc("accent"), v.index or 0, T.Esc("text2"), v.count) or "-")
	local pw = max(64, (W.pillText:GetStringWidth() or 40) + 28)
	W.pill:SetWidth(pw)
	W.bar:SetProgress(v and v.progress or 0, MAIN_W - 48 - pw - 14)

	-- The steps down the side.
	local steps = v and v.steps or {}
	local n = min(#steps, #W.steps)
	for i, s in ipairs(W.steps) do
		local st = steps[i]
		s:SetShown(st ~= nil)
		if st then
			s.text:SetText((ns.L("Step %d")):format(st.index))
			local a = T.Color("accent")
			if st.current then
				T.PaintRound(s, { a[1], a[2], a[3], 0.12 })
				s.dot:SetTexture(T.MEDIA .. "dot-done")
				s.dot:SetSize(12, 12)
				s.dot:SetVertexColor(a[1], a[2], a[3], 1)
				T.TextColor(s.text, "text")
			else
				T.PaintRound(s, { 0, 0, 0, 0 })
				s.dot:SetTexture(T.MEDIA .. "dot-open")
				s.dot:SetSize(12, 12)
				local m = T.Color("muted")
				s.dot:SetVertexColor(m[1], m[2], m[3], 1)
				T.TextColor(s.text, "text2")
			end
		end
	end
	W.stepLine:SetShown(n > 1)
	if n > 1 then
		W.stepLine:ClearAllPoints()
		W.stepLine:SetPoint("TOP", W.steps[1].dot, "CENTER", 0, 0)
		W.stepLine:SetPoint("BOTTOM", W.steps[n].dot, "CENTER", 0, 0)
	end

	local has = v ~= nil
	for _, w in ipairs({ W.label, W.stepTitle, W.pin, W.place, W.back, W.skip, W.report, W.next }) do w:SetShown(has) end
	W.empty:SetShown(not has)
	local x, width = 20, MAIN_W - 176 - 24 - 40
	local function place(w, y, inset)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", card, "TOPLEFT", x + (inset or 0), -y)
		w:SetPoint("RIGHT", card, "RIGHT", -20, 0)
	end
	local y = 20
	if not has then
		place(W.empty, y)
		W.empty:SetText("No route for this character yet.\n\nPick one from Routes on the left, or the route book.")
		for _, w in ipairs({ W.note, W.divider, W.objLabel, W.detour }) do w:Hide() end
		for _, r in ipairs(W.rows) do r:Hide() end
	else
		for _, b in ipairs({ W.back, W.skip, W.next }) do T.Relabel(b) end
		place(W.label, y)
		W.label:SetText(v.index and v.count and ns.U((ns.L("Step %d of %d")):format(v.index, v.count)) or (v.extra and "EXTRA QUEST" or "NOW"))
		y = y + max(12, height(W.label)) + 8
		place(W.stepTitle, y)
		W.stepTitle:SetText(v.title or "")
		y = y + height(W.stepTitle) + 8
		local where = Guide.PlaceLine(v)
		W.pin:SetShown(where ~= "")
		W.place:SetShown(where ~= "")
		if where ~= "" then
			W.pin:ClearAllPoints()
			W.pin:SetPoint("TOPLEFT", card, "TOPLEFT", x, -(y + 1))
			place(W.place, y, 20)
			W.place:SetText(where)
			y = y + height(W.place) + 10
		end
		local note = v.text and v.text ~= "" and v.text ~= v.title
		W.note:SetShown(note and true or false)
		if note then
			place(W.note, y)
			W.note:SetText(v.text)
			if W.note.SetMaxLines then W.note:SetMaxLines(3) end
			y = y + height(W.note) + 14
		end

		local rows = ns.TrackerCard.Rows(v)
		if #rows > Hub.MAX_ROWS then
			local cut = {}
			for k = 1, Hub.MAX_ROWS - 1 do cut[k] = rows[k] end
			cut[#cut + 1] = { kind = "note", lead = (ns.L("+%d more")):format(#rows - (Hub.MAX_ROWS - 1)), info = true }
			rows = cut
		end
		W.divider:SetShown(#rows > 0)
		W.objLabel:SetShown(#rows > 0)
		if #rows > 0 then
			place(W.divider, y)
			W.divider:SetHeight(1)
			y = y + 14
			place(W.objLabel, y)
			y = y + height(W.objLabel) + 10
		end
		for i, line in ipairs(rows) do
			local r = rowWidget(i)
			r:Show()
			place(r, y)
			r.check:SetShown(not line.info)
			r.check:SetChecked(line.done)
			r.text:SetText(Guide.LineText(line))
			T.TextColor(r.text, line.done and "muted" or ((line.info or line.optional) and "text2" or "text"))
			r.count:SetText(line.need and ("%d/%d"):format(line.have or 0, line.need) or "")
			local h = max(20, height(r.text))
			r:SetHeight(h)
			y = y + h + 8
		end
		for i = #rows + 1, #W.rows do W.rows[i]:Hide() end

		local d = v.detour
		W.detour:SetShown(d and true or false)
		if d then
			local dd = W.detour
			place(dd, y + 6)
			dd.label:SetText(ns.U(ns.L(d.label or "Optional")))
			dd.text:SetText(d.text or "")
			dd.sub:SetText(d.sub or "")
			dd.go.pwText:SetText(d.aimed and "Stop" or "Go")
			dd:SetHeight(max(64, 12 + height(dd.label) + 4 + height(dd.text) + 3 + height(dd.sub) + 12))
		end
	end

	-- Stats.
	local lvl, frac, rate = ns.TrackerCard.Stats()
	local K = ns.Tracker
	local stats = lvl ~= nil
	for _, w in ipairs({ W.statsLine, W.level, W.levelBar, W.rate }) do w:SetShown(stats) end
	if stats then
		W.level:SetText((ns.L("Level %d  ") .. T.Esc("text2") .. "·  %d%%|r"):format(UnitLevel and UnitLevel("player") or 1, floor((frac or 0) * 100)))
		W.rate:SetText(rate ~= "" and rate or "XP per hour after a minute")
		local bw = max(60, width - (W.rate:GetStringWidth() or 0) - 24)
		W.levelBar:SetWidth(bw)
		W.levelBar:SetProgress(frac, bw)
	end
	local xy = ns.Coords and ns.Coords.Text()
	W.coords:SetShown(xy and true or false)
	if xy then W.coords:SetText(ns.L("You  ") .. xy) end
end

-- Places the columns for a size: the menu, the routes and professions
-- column (when wide enough), and the guide taking the rest.
function Hub.Layout(w, h)
	if not W.frame then return end
	local narrow = w < Hub.NARROW
	W.narrow = narrow
	local function put(col, x, y, cw, ch)
		col:ClearAllPoints()
		col:SetPoint("TOPLEFT", W.frame, "TOPLEFT", x, -y)
		col:SetSize(cw, ch)
	end
	put(W.rail, 0, 0, RAIL_W, h)
	W.routes:SetShown(not narrow)
	W.prof:SetShown(not narrow)
	local profH = h - ROUTES_H - GAP
	if not narrow then
		put(W.routes, RAIL_W + GAP, 0, MID_W, ROUTES_H)
		put(W.prof, RAIL_W + GAP, ROUTES_H + GAP, MID_W, profH)
	end
	-- As many profession rows as fit above the recipe book button.
	W.profFit = math.max(0, floor((profH - 54 - 72) / 64))
	local mx = RAIL_W + GAP + (narrow and 0 or (MID_W + GAP))
	put(W.main, mx, 0, w - mx, h)
end

function Hub.Refresh()
	if not (W.frame and W.frame:IsShown()) then return end
	drawRail()
	drawMiddle()
	drawMain(Guide.View())
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- The guide style on screen: "tracker", "window", "minimal", or "off".
function Hub.SetStyle(style)
	if style == "off" then
		ns.Set("guide.shown", false)
	else
		ns.Set("guide.style", style)
		ns.Set("guide.shown", true)
	end
	Hub.Refresh()
end

function Hub.Show(on)
	if on == nil then on = true end
	if on and not W.frame then build() end
	if not W.frame then return end
	local was = W.frame:IsShown()
	W.frame:SetShown(on)
	if on then
		W.frame:Raise()
		Hub.Refresh()
	end
	-- The guide on screen steps aside while the hub is open (it shows the
	-- same step) and comes back when it closes.
	if was ~= (on and true or false) then ns.Fire("HUB_TOGGLED", on and true or false) end
end

function Hub.Shown() return W.frame ~= nil and W.frame:IsShown() end

function Hub.Toggle(open)
	if open then Hub.Show(true) else Hub.Show(not Hub.Shown()) end
end

-- The Leveling menu row: back to the guide (closes a side panel).
function Hub.Focus()
	if ns.Panels and ns.Panels.Close then ns.Panels.Close() end
	Hub.Refresh()
end

ns.On("TOGGLE_HUB", function(open) Hub.Toggle(open) end)
ns.On("GUIDE_VIEW", function() if Hub.Shown() then drawMain(Guide.View()) drawMiddle() end end)
ns.On("TRACKER_UPDATED", function() if Hub.Shown() then drawMain(Guide.View()) end end)
ns.On("PROFESSIONS_CHANGED", function() if Hub.Shown() then drawMiddle() end end)
ns.On("PLAYER_COORDS", function()
	if not Hub.Shown() then return end
	local xy = ns.Coords.Text()
	W.coords:SetShown(xy and true or false)
	if xy then W.coords:SetText(ns.L("You  ") .. xy) end
end)
ns.On("SETTING_CHANGED", function(path)
	if (path == "hub.width" or path == "hub.height") and W.frame and not (W.grip and W.grip.pwState.held) then
		local w, h = Hub.Size()
		W.frame:SetSize(w, h)
		Hub.Layout(w, h)
		Hub.Refresh()
		return
	end
	if not Hub.Shown() then return end
	if path == "guide.style" or path == "guide.shown" or path == "compass.shown" or path == "compass.coords" or path == "tracker.shown" then Hub.Refresh() end
end)
Pathwise.ToggleHub = function() Hub.Toggle() end
