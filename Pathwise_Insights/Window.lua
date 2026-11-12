-- The Pathwise Insights window (PathwiseInsights): a tab per character, and
-- two pages. Overview: tiles with the totals, records, when you play, and
-- the leveling detail (routes, zones, levels, slow steps, professions). Map:
-- a continent with a heat map of where you spent your time (or earned your
-- XP fastest) and the trail you walked and flew.
--
-- In the suite's look (v2, like the hub and the tracker): a rounded window
-- with the Pathwise logo, a pin, and a corner grip to make it any size.
-- Drag it by its header (insights.point, insights.size). Escape closes it.

local ADDON, ns = ...
local S, R, St = Pathwise.Suite, ns.Recorder, ns.Stats
local T = S.Theme
local floor, max, min, sqrt = math.floor, math.max, math.min, math.sqrt

local Win = {}
ns.Window = Win

Win.W, Win.H = 780, 640 -- the usual size
Win.MIN_W, Win.MIN_H, Win.MAX_W, Win.MAX_H = 640, 460, 1400, 1100
local PAD = 16
local HEADER_H = 44
local TILE_W, TILE_H, TILE_GAP = 140, 58, 8

S.Defaults("insights", { point = nil, size = nil, locked = false, layer = "time", flights = true })

-- What is shown: the character (its key), the page, the continent.
local state = { char = nil, page = "overview", cont = nil, confirm = nil, hidden = false, whole = false }
Win.state = state

local W = {}
Win.frames = W

---------------------------------------------------------------------------
-- Small builders
---------------------------------------------------------------------------

local function paint(tex, c, a)
	c = type(c) == "table" and c or T.Color(c)
	tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1)
end

local function textColor(fs, c)
	c = type(c) == "table" and c or T.Color(c)
	fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
end

local pools = {}
local function pool(kind, make)
	local p = pools[kind]
	if not p then p = { list = {}, used = 0 } pools[kind] = p end
	p.used = p.used + 1
	local w = p.list[p.used]
	if not w then w = make() p.list[p.used] = w end
	w:Show()
	return w
end

local function releaseAll()
	for _, p in pairs(pools) do
		for i = 1, #p.list do p.list[i]:Hide() end
		p.used = 0
	end
end

-- A text in role `role` on `parent` at x, y; returns the y under it.
local function text(parent, x, y, width, str, role, color, justify)
	local fs = pool("text:" .. (role or "body") .. tostring(parent), function() return T.Text(parent, role or "body") end)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	fs:SetWidth(width)
	fs:SetJustifyH(justify or "LEFT")
	textColor(fs, color or (T.TYPE[role or "body"] or T.TYPE.body)[3])
	fs:SetText(str)
	return y + max(12, fs:GetStringHeight() or 14), fs
end

-- A flat box (a bar, a heat cell, a trail dot).
local function box(parent, layer, x, y, w, h, color, alpha)
	local t = pool("box:" .. layer .. tostring(parent), function() return parent:CreateTexture(nil, layer) end)
	t:ClearAllPoints()
	t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	t:SetSize(max(0.5, w), max(0.5, h))
	paint(t, color, alpha)
	return t
end

-- A tab or choice: `on` fills it with the accent.
local function paintChip(b, hover)
	if b.on then
		local a = T.Color("insights")
		T.PaintRound(b, { a[1], a[2], a[3], hover and 0.24 or 0.16 }, "insights")
		textColor(b.text, "text")
	else
		T.PaintRound(b, hover and "hover" or "bg2", "border")
		textColor(b.text, hover and "text" or "text2")
	end
end

local function chip(parent, x, y, label, on, onClick)
	local b = pool("chip" .. tostring(parent), function()
		local b = CreateFrame("Button", nil, parent)
		T.Round(b, "bg2", "border", 6)
		b:SetHeight(28)
		b.text = T.Text(b, "button", "text2")
		b.text:SetPoint("CENTER")
		b:SetScript("OnEnter", function(self) paintChip(self, true) end)
		b:SetScript("OnLeave", function(self) paintChip(self, false) end)
		return b
	end)
	b.on = on and true or false
	b.text:SetText(label)
	paintChip(b, false)
	b:SetWidth(max(56, (b.text:GetStringWidth() or 40) + 40))
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	b:SetScript("OnClick", onClick)
	return b, b:GetWidth()
end

-- A tile: a label, a big value, a line under it.
local function tile(parent, x, y, w, label, value, sub)
	local f = pool("tile" .. tostring(parent), function()
		local f = CreateFrame("Frame", nil, parent)
		T.Round(f, "bg2", "divider", 8)
		f.label = T.Text(f, "small", "muted")
		f.label:SetPoint("TOPLEFT", 10, -8)
		f.value = T.Text(f, "number", "text")
		f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -4)
		f.value:SetWordWrap(false)
		f.sub = T.Text(f, "small", "muted")
		f.sub:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -3)
		f.sub:SetWordWrap(false)
		return f
	end)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
	f:SetSize(w, TILE_H + (sub and 10 or 0))
	for _, fs in ipairs({ f.label, f.value, f.sub }) do fs:SetWidth(w - 20) end
	f.label:SetText(label)
	f.value:SetText(value)
	f.sub:SetText(sub or "")
	return f
end

-- Tiles in rows of COLS; returns the y under them.
local function tiles(parent, y, width, list)
	-- As many columns as fit (the window can be any width).
	local COLS = max(3, min(7, floor((width + TILE_GAP) / (TILE_W + TILE_GAP))))
	local w = (width - (COLS - 1) * TILE_GAP) / COLS
	local rowH = 0
	for i, t in ipairs(list) do
		local col = (i - 1) % COLS
		if col == 0 and i > 1 then y = y + rowH + TILE_GAP rowH = 0 end
		local f = tile(parent, col * (w + TILE_GAP), y, w, t[1], t[2], t[3])
		rowH = max(rowH, f:GetHeight())
	end
	return y + rowH
end

local function heading(parent, y, width, str)
	y = y + 18
	local line = pool("rule" .. tostring(parent), function() return T.Divider(parent) end)
	line:ClearAllPoints()
	line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y - 10))
	line:SetWidth(width)
	local fs = pool("heading" .. tostring(parent), function() return T.TextAt(parent, "semibold", 17, "text") end)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
	fs:SetWidth(width)
	textColor(fs, "text")
	fs:SetText(str)
	return y + max(18, fs:GetStringHeight() or 20) + 10
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local draw

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	S.Set("insights.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

local function build()
	local f = CreateFrame("Frame", "PathwiseInsights", UIParent)
	W.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	T.RoundWindow(f, 12)
	T.TrackScale(f)
	local size = S.Get("insights.size")
	if type(size) == "table" then
		f:SetSize(max(Win.MIN_W, min(Win.MAX_W, size[1] or Win.W)), max(Win.MIN_H, min(Win.MAX_H, size[2] or Win.H)))
	else
		f:SetSize(Win.W, Win.H)
	end
	local saved = S.Get("insights.point")
	f:ClearAllPoints()
	if type(saved) == "table" then f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else f:SetPoint("CENTER", UIParent, "CENTER", 0, 20) end

	-- The header: the Pathwise logo and the name; drag it to move.
	local head = CreateFrame("Frame", nil, f)
	W.head = head
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(HEADER_H)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() if T.Movable("insights.locked") then f:StartMoving() end end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)
	W.logo = T.Logo(head, 24)
	W.logo:SetPoint("LEFT", PAD - 3, 0)
	W.title = T.Text(head, "window", "text")
	W.title:SetPoint("LEFT", W.logo, "RIGHT", 8, 0)
	W.title:SetText("Pathwise Insights")
	W.close = T.IconButton(head, "close", "Close", function() Win.Close() end, 28)
	W.close:SetPoint("RIGHT", -8, 0)
	W.pin = T.PinButton(head, "insights.locked", 28)
	W.pin:SetPoint("RIGHT", W.close, "LEFT", -2, 0)
	local hl = T.Divider(f)
	hl:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	hl:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
	-- The pages: a segmented row in the header, like the hub's tabs.
	W.header = CreateFrame("Frame", nil, head)
	W.header:SetPoint("CENTER", head, "CENTER", 0, 0)
	W.header:SetSize(200, 34)
	T.Round(W.header, "bg2", false, 8)
	W.pages = {}
	for i, p in ipairs({ { "overview", "Overview" }, { "map", "Map" } }) do
		local b = CreateFrame("Button", nil, W.header)
		b:SetSize(97, 28)
		b:SetPoint("LEFT", 3 + (i - 1) * 97, 0)
		T.Round(b, "bg2", false, 6)
		b.text = T.Text(b, "button", "text2")
		b.text:SetPoint("CENTER")
		b.text:SetText(p[2])
		b.line = b:CreateTexture(nil, "OVERLAY")
		b.line:SetHeight(2)
		b.line:SetPoint("BOTTOMLEFT", 8, 0)
		b.line:SetPoint("BOTTOMRIGHT", -8, 0)
		b:SetScript("OnClick", function()
			state.page = p[1]
			W.scroll:SetVerticalScroll(0)
			draw()
		end)
		b.page = p[1]
		W.pages[i] = b
	end

	-- The characters and their buttons (drawn each time: they change).
	W.top = CreateFrame("Frame", nil, f)
	W.top:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(HEADER_H + 12))
	W.top:SetSize(Win.W - 2 * PAD, 1)

	local scroll = CreateFrame("ScrollFrame", nil, f)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 6, PAD)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(max(0, min(W.range or 0, (self:GetVerticalScroll() or 0) - delta * 40)))
	end)
	W.scroll, W.child = scroll, child

	-- The corner grip: any width and height; right-click for the usual size.
	W.grip = T.Grip(f, {
		minW = Win.MIN_W, maxW = Win.MAX_W, minH = Win.MIN_H, maxH = Win.MAX_H, height = true,
		lockPath = "insights.locked",
		onSize = function() draw() end,
		onDone = function(w, h) S.Set("insights.size", { w, h or f:GetHeight() }) savePoint(f) draw() end,
		onReset = function() S.Set("insights.size", nil) f:SetSize(Win.W, Win.H) draw() end,
	})

	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PathwiseInsights") end
	f:Hide()
end

---------------------------------------------------------------------------
-- The characters
---------------------------------------------------------------------------

local function selected()
	local chars = R.Characters()
	local pick
	for _, c in ipairs(chars) do if c.key == state.char then pick = c end end
	if not pick then
		state.char = R.CharKey()
		pick = { key = state.char, log = R.Log() }
	end
	return pick, chars
end
Win.Selected = selected

-- The tabs and the buttons under them; returns the height used.
local function drawTop(chars, pick)
	local p = W.top
	local x, y, width = 0, 0, W.pageW + 6
	local hidden = 0
	for _, c in ipairs(chars) do
		if c.log.hidden and c.key ~= pick.key and not state.hidden then
			hidden = hidden + 1
		else
			local label = St.CharLabel(c.log, c.key) .. (c.log.hidden and " (hidden)" or "")
			local b, w = chip(p, x, y, label, c.key == pick.key, function()
				state.char, state.confirm = c.key, nil
				W.scroll:SetVerticalScroll(0)
				draw()
			end)
			if x > 0 and x + w > width then
				x, y = 0, y + 34
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -y)
			end
			x = x + w + 6
		end
	end
	y = y + 38
	local bx = 0
	local _, w = chip(p, bx, y, pick.log.hidden and "Show this character" or "Hide this character", false, function()
		R.Hide(pick.key, not pick.log.hidden)
	end)
	bx = bx + w + 6
	local sure = state.confirm == pick.key
	_, w = chip(p, bx, y, sure and "Yes, delete it" or "Delete this character...", sure, function()
		if sure then
			state.confirm, state.char = nil, nil
			R.Delete(pick.key)
			S.Print(("Pathwise Insights: %s's numbers are deleted."):format(St.CharLabel(pick.log, pick.key)))
		else
			state.confirm = pick.key
		end
		draw()
	end)
	bx = bx + w + 6
	if hidden > 0 or state.hidden then
		chip(p, bx, y, state.hidden and "Leave hidden ones out" or ("Show hidden (%d)"):format(hidden), false, function()
			state.hidden = not state.hidden
			draw()
		end)
	end
	return y + 34
end

---------------------------------------------------------------------------
-- Overview
---------------------------------------------------------------------------

-- Bars: values from a list, labels under them.
local function bars(parent, x, y, width, height, values, labels)
	local top = 0
	for _, v in ipairs(values) do top = max(top, v) end
	local n = #values
	local gap = n > 10 and 3 or 8
	local bw = (width - (n - 1) * gap) / n
	for i, v in ipairs(values) do
		local h = top > 0 and floor(v / top * height + 0.5) or 0
		if h > 0 then box(parent, "ARTWORK", x + (i - 1) * (bw + gap), y + height - h, bw, h, "insights", 0.9) end
		local _, fs = text(parent, x + (i - 1) * (bw + gap) - 6, y + height + 4, bw + 12, labels[i], "small", "muted", "CENTER")
	end
	return y + height + 18
end

local DAYS = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" }

local function drawOverview(log, key)
	local c, width = W.child, W.pageW
	local y = 0
	local parts = {}
	if log.race then parts[#parts + 1] = log.race end
	if log.class then parts[#parts + 1] = log.class end
	parts[#parts + 1] = "Level " .. (log.level or 1)
	if not W.crest then
		W.crest = T.Crest(c, 34)
		W.who = T.TextAt(c, "semibold", 20, "text")
		W.whoSub = T.Text(c, "meta", "text2")
	end
	W.crest:Show() W.who:Show() W.whoSub:Show()
	W.crest:SetFaction(log.faction)
	W.crest:ClearAllPoints()
	W.crest:SetPoint("TOPLEFT", c, "TOPLEFT", 0, -y)
	W.who:ClearAllPoints()
	W.who:SetPoint("TOPLEFT", c, "TOPLEFT", 44, -(y + 1))
	W.who:SetWidth(width - 44)
	W.who:SetText(table.concat(parts, "  ·  "))
	W.whoSub:ClearAllPoints()
	W.whoSub:SetPoint("TOPLEFT", W.who, "BOTTOMLEFT", 0, -3)
	W.whoSub:SetWidth(width - 44)
	W.whoSub:SetText(log.name or key)
	y = y + 46
	local t = St.Totals(log)
	y = tiles(c, y, width, {
		{ "Time played", St.Duration(t.played) },
		{ "XP per hour", t.rate and St.Number(t.rate) or "—" },
		{ "Turned in", St.Number(t.quests) },
		{ "Monsters killed", St.Number(t.kills) },
		{ "Deaths", St.Number(t.deaths) },
		{ "Distance travelled", St.Distance(t.dist) },
		{ "Sessions", St.Number(t.sessions) },
		{ "Days played", St.Number(t.days) },
	})
	local meta = {}
	if log.faction then meta[#meta + 1] = log.faction end
	if t.first then meta[#meta + 1] = "Since " .. St.DayText(t.first) end
	if t.last then meta[#meta + 1] = "Last played " .. St.DayText(t.last) end
	if #meta > 0 then y = text(c, 0, y + 10, width, table.concat(meta, "  ·  "), "meta", "text2") end

	local rec = St.Records(log)
	local list = {}
	local function add(k, label) if rec[k] then list[#list + 1] = { label, rec[k][1], rec[k][2] } end end
	add("fastLevel", "Fastest level")
	add("slowLevel", "Longest level")
	add("bestSession", "Best session")
	add("longSession", "Longest session")
	add("mostQuests", "Busiest session")
	add("bigDay", "Biggest day")
	add("streak", "Days in a row")
	add("fastQuest", "Fastest quest")
	add("slowQuest", "Longest quest")
	add("bestQuest", "Best-paying quest")
	y = heading(c, y, width, "Records")
	if #list > 0 then y = tiles(c, y, width, list)
	else y = text(c, 0, y, width, "Records come as you play: a level from start to end, a session, a quest.", "meta", "muted") end

	local hours, week = St.Hours(log)
	if t.played >= 1 then
		y = heading(c, y, width, "When you play")
		local half = (width - 24) / 2
		local hv, hl, wv = {}, {}, {}
		for i = 0, 23 do hv[#hv + 1] = hours[i] hl[#hl + 1] = i % 3 == 0 and (i .. "h") or "" end
		for i = 1, 7 do wv[#wv + 1] = week[i] end
		text(c, 0, y, half, "HOURS PLAYED", "label", "text2")
		text(c, half + 24, y, half, "DAYS OF THE WEEK", "label", "text2")
		y = y + 18
		bars(c, 0, y, half, 70, hv, hl)
		y = bars(c, half + 24, y, half, 70, wv, DAYS)
	end

	local d = St.Detail(log)
	if #d.routes > 0 then
		y = heading(c, y, width, "Routes")
		for i, r in ipairs(d.routes) do
			if i > 8 then break end
			local bits = { St.Duration(r.t), St.RateText(r.xp, r.t) }
			if (r.b.steps or 0) > 0 then bits[#bits + 1] = r.b.steps .. " steps" end
			if (r.b.skips or 0) > 0 then bits[#bits + 1] = r.b.skips .. " skipped" end
			if r.d > 0 then bits[#bits + 1] = r.d .. (r.d == 1 and " death" or " deaths") end
			if r.b.done then bits[#bits + 1] = "finished" end
			y = text(c, 0, y, width * 0.4, r.name, "body", "text")
			y = text(c, 0, y - 2, width, table.concat(bits, "  ·  "), "small", "muted") + 6
		end
	end
	if #d.zones > 0 then
		y = heading(c, y, width, "Zones")
		local top = d.zones[1].t
		for i, z in ipairs(d.zones) do
			if i > 10 then break end
			text(c, 0, y, 160, z.name, "body", "text")
			box(c, "ARTWORK", 170, y + 4, width - 170 - 200, 8, "bg2", 1)
			box(c, "OVERLAY", 170, y + 4, (width - 170 - 200) * z.t / top, 8, "insights", 0.9)
			local bits = St.Duration(z.t) .. "  ·  " .. St.RateText(z.xp, z.t)
			y = text(c, width - 190, y, 190, bits, "meta", "text2", "RIGHT") + 6
		end
	end
	if #d.levels > 0 then
		y = heading(c, y, width, "Time at each level")
		local half = (width - 24) / 2
		for i, l in ipairs(d.levels) do
			if i > 12 then break end
			local x = ((i - 1) % 2) * (half + 24)
			local line = ("Level %d"):format(l.level)
			text(c, x, y, half, line, "body", "text")
			local ny = text(c, x, y, half, St.Duration(l.t) .. "  ·  " .. St.RateText(l.xp, l.t), "meta", "text2", "RIGHT")
			if i % 2 == 0 or i == #d.levels or i == 12 then y = ny + 6 end
		end
	end
	if #d.slowest > 0 then
		y = heading(c, y, width, "Slowest steps")
		for _, st in ipairs(d.slowest) do
			text(c, 0, y, width - 100, ("%s, step %d"):format(St.RouteTitle(st.r), st.s), "body", "text")
			y = text(c, width - 100, y, 100, St.Duration(st.t), "meta", "text2", "RIGHT") + 6
		end
	end
	if #d.skills > 0 then
		y = heading(c, y, width, "Professions")
		for _, s in ipairs(d.skills) do
			text(c, 0, y, width - 100, s.name, "body", "text")
			y = text(c, width - 100, y, 100, ("%d → %d"):format(s.from, s.to), "meta", "text2", "RIGHT") + 6
		end
	end

	y = heading(c, y, width, "Share with Pathwise")
	y = text(c, 0, y, width, "Send this character's numbers to help tune the guides: real step and quest times, the steps people skip, where they get stuck or die, and NPCs that are not where the guide says. You see what is in the code first; no name or realm is in it.", "meta", "text2") + 8
	chip(c, 0, y, "Make a share code", false, function() ns.Share.Open(key) end)
	y = y + 34
	y = text(c, 0, y, width, "Where you stand among other players comes once enough characters are shared.", "small", "muted")

	y = heading(c, y, width, "Options")
	local x = 0
	local _, w = chip(c, x, y, S.Get("insights.record") and "Recording: on" or "Recording: off", S.Get("insights.record"), function()
		S.Set("insights.record", not S.Get("insights.record"))
		draw()
	end)
	x = x + w + 6
	chip(c, x, y, S.Get("insights.minimap") and "Minimap button: shown" or "Minimap button: hidden", false, function()
		S.Set("insights.minimap", not S.Get("insights.minimap"))
		draw()
	end)
	y = y + 36
	y = text(c, 0, y, width, "Kept on your computer for every character on this account. Not counted: time AFK and loading screens. Not yet checked in game.", "small", "muted")
	return y + 8
end

---------------------------------------------------------------------------
-- Map
---------------------------------------------------------------------------

-- A continent's art: tiles and their size, or nil.
function Win.MapArt(map)
	if not (T.GameArt() and map and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures) then return nil end
	local ok, layers = pcall(C_Map.GetMapArtLayers, map)
	local l = ok and type(layers) == "table" and layers[1]
	if not (l and l.tileWidth and l.layerWidth) then return nil end
	local ok2, files = pcall(C_Map.GetMapArtLayerTextures, map, 1)
	if not (ok2 and type(files) == "table" and #files > 0) then return nil end
	return { files = files, tw = l.tileWidth, th = l.tileHeight, lw = l.layerWidth, lh = l.layerHeight,
		cols = math.ceil(l.layerWidth / l.tileWidth), rows = math.ceil(l.layerHeight / l.tileHeight) }
end

-- 0..1 to a colour: deep purple, pink, orange, yellow (like a heat map).
local RAMP = { { 0.27, 0.05, 0.45 }, { 0.62, 0.11, 0.55 }, { 0.90, 0.30, 0.38 }, { 0.98, 0.60, 0.16 }, { 0.98, 0.90, 0.25 } }
function Win.Ramp(v)
	v = max(0, min(1, v)) * (#RAMP - 1)
	local i = floor(v)
	local a, b = RAMP[i + 1], RAMP[min(#RAMP, i + 2)]
	local f = v - i
	return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, 1 }
end

local MAX_DOTS = 2500

-- A soft round spot (the heat map), centred on x, y.
local function blob(parent, x, y, size, color, alpha)
	local t = pool("blob" .. tostring(parent), function()
		local t = parent:CreateTexture(nil, "OVERLAY")
		t:SetTexture(T.MEDIA .. "dot-done")
		return t
	end)
	t:ClearAllPoints()
	t:SetPoint("CENTER", parent, "TOPLEFT", x, -y)
	t:SetSize(size, size)
	color = type(color) == "table" and color or T.Color(color)
	t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
	return t
end

-- The part of the continent to show (0-1): around everywhere you went, with
-- a margin, shaped like the canvas; the whole continent when asked.
function Win.View(log, cont, aspect, whole)
	if whole then return 0, 0, 1, 1 end
	local x0, y0, x1, y1 = 1, 1, 0, 0
	local function take(x, y)
		if x < x0 then x0 = x end
		if x > x1 then x1 = x end
		if y < y0 then y0 = y end
		if y > y1 then y1 = y end
	end
	local trail = log.trail[cont] or {}
	for i = 1, #trail, 3 do take(trail[i] / 10000, trail[i + 1] / 10000) end
	local G = R.GRID
	for cell in pairs(log.heat[cont] or {}) do take((cell % G + 0.5) / G, (floor(cell / G) + 0.5) / G) end
	if x1 < x0 then return 0, 0, 1, 1 end
	local w, h = max(x1 - x0, 0.06), max(y1 - y0, 0.06)
	w, h = w * 1.3, h * 1.3
	-- Shaped like the canvas: aspect = canvas height / width, in continent units.
	if h / w < aspect then h = w * aspect else w = h / aspect end
	if w > 1 or h > 1 then return 0, 0, 1, 1 end
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	local vx = min(1 - w, max(0, cx - w / 2))
	local vy = min(1 - h, max(0, cy - h / 2))
	return vx, vy, w, h
end

local function drawMap(log, viewH)
	local c, width = W.child, W.pageW
	local y = 0
	local conts = St.Continents(log)
	if #conts == 0 then
		return text(c, 0, y, width, "No map yet: your path and the places you spend time show here once you have played a little with Insights on.", "meta", "muted")
	end
	local zones = St.Zones(log, 10)
	-- The map shown: a continent or one of your zones.
	local cont
	for _, k in ipairs(conts) do if k.id == state.cont then cont = k end end
	for _, k in ipairs(zones) do if k.id == state.cont then cont = k end end
	cont = cont or conts[1]
	state.cont = cont.id

	-- The continents, then the zones you spent the most time in.
	local x = 0
	local function pick(k)
		local b, w = chip(c, x, y, k.name, k.id == cont.id, function() state.cont = k.id draw() end)
		if x > 80 and x + w > width then
			x, y = 80, y + 34
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", c, "TOPLEFT", x, -y)
		end
		x = x + w + 6
	end
	text(c, 0, y + 6, 80, "Continent", "meta", "text2")
	x = 80
	for _, k in ipairs(conts) do pick(k) end
	if #zones > 0 then
		y, x = y + 34, 0
		text(c, 0, y + 6, 80, "Zone", "meta", "text2")
		x = 80
		for _, k in ipairs(zones) do pick(k) end
	end
	y, x = y + 40, 0
	text(c, 0, y + 6, 80, "Show", "meta", "text2")
	x = 80
	local layer = S.Get("insights.layer")
	for _, l in ipairs({ { "time", "Time spent" }, { "rate", "XP an hour" } }) do
		local _, w = chip(c, x, y, l[2], layer == l[1], function() S.Set("insights.layer", l[1]) draw() end)
		x = x + w + 6
	end
	x = x + 12
	local flights = S.Get("insights.flights")
	local _, w = chip(c, x, y, "Flights", flights, function()
		S.Set("insights.flights", not flights)
		draw()
	end)
	x = x + w + 6
	local isZone = true
	for _, k in ipairs(conts) do if k.id == cont.id then isZone = false end end
	chip(c, x, y, isZone and "Whole zone" or "Whole continent", state.whole, function()
		state.whole = not state.whole
		draw()
	end)
	y = y + 40

	-- The canvas: as wide as the page, as tall as fits above the legend.
	local art = Win.MapArt(cont.id)
	local cw = width
	local ch = max(200, (viewH or 400) - y - 30)
	-- The continent's own shape (height / width of the whole map).
	local shape = art and art.lh / art.lw or 0.66
	-- What part of it to show, in continent units, shaped like the canvas.
	local vx, vy, vw, vh = Win.View(log, cont.id, (ch / cw) / shape, state.whole)
	if state.whole then
		-- The whole continent, fitted in: narrower or shorter than the canvas.
		if cw * shape > ch then cw = floor(ch / shape) else ch = floor(cw * shape) end
	end
	local sx, sy = cw / vw, ch / vh -- canvas pixels per continent unit
	local function px(u) return (u - vx) * sx end
	local function py(v) return (v - vy) * sy end

	local canvas = W.canvas
	if not canvas then
		canvas = CreateFrame("Frame", nil, c)
		if canvas.SetClipsChildren then canvas:SetClipsChildren(true) end
		canvas.ground = canvas:CreateTexture(nil, "BACKGROUND")
		canvas.ground:SetAllPoints()
		canvas.tiles = {}
		canvas.shade = canvas:CreateTexture(nil, "ARTWORK", nil, 2)
		canvas.shade:SetAllPoints()
		W.canvas = canvas
	end
	canvas:Show()
	canvas:ClearAllPoints()
	canvas:SetPoint("TOPLEFT", c, "TOPLEFT", floor((width - cw) / 2), -y)
	canvas:SetSize(cw, ch)
	paint(canvas.ground, "bg2", 1)
	for _, t in ipairs(canvas.tiles) do t:Hide() end
	if art then
		-- Tiles in art pixels; one continent unit is lw art pixels across.
		local ax, ay = sx / art.lw, sy / art.lh
		for row = 0, art.rows - 1 do
			for col = 0, art.cols - 1 do
				local i = row * art.cols + col + 1
				if art.files[i] then
					local t = canvas.tiles[i]
					if not t then t = canvas:CreateTexture(nil, "ARTWORK", nil, 1) canvas.tiles[i] = t end
					t:SetTexture(art.files[i])
					t:SetSize(art.tw * ax, art.th * ay)
					t:ClearAllPoints()
					t:SetPoint("TOPLEFT", canvas, "TOPLEFT", px(col * art.tw / art.lw), -py(row * art.th / art.lh))
					t:Show()
				end
			end
		end
	end
	paint(canvas.shade, "bg", art and 0.35 or 0)

	-- Heat: a soft spot per cell, the hotter the bigger and brighter.
	local cells, top = St.Heat(log, cont.id, layer)
	table.sort(cells, function(a, b) return a.v < b.v end) -- the hottest on top
	local G = R.GRID
	local cell = sx / G
	for _, k in ipairs(cells) do
		local cx, cy = (k.cell % G + 0.5) / G, (floor(k.cell / G) + 0.5) / G
		local v = layer == "time" and sqrt(k.v / top) or k.v / top
		blob(canvas, px(cx), py(cy), cell * (1.1 + 1.3 * v), Win.Ramp(v), 0.3 + 0.5 * v)
	end

	-- The trail: a dot every few points; flights in the accent.
	local trail = log.trail[cont.id] or {}
	local n = #trail / 3
	local every = max(1, math.ceil(n / MAX_DOTS))
	for i = 1, n, every do
		local u, v, flag = trail[i * 3 - 2] / 10000, trail[i * 3 - 1] / 10000, trail[i * 3]
		if flag ~= 1 then
			box(canvas, "OVERLAY", px(u) - 1, py(v) - 1, 2, 2, "text", 0.6)
		elseif flights then
			box(canvas, "OVERLAY", px(u) - 1, py(v) - 1, 2, 2, "insights", 0.8)
		end
	end
	-- You are here.
	local hc, hx, hy = R.OnContinent()
	if hc == cont.id and R.CharKey() == state.char then
		blob(canvas, px(hx), py(hy), 10, "accent", 1)
	end
	y = y + ch + 10

	-- The legend.
	local lw = 160
	for i = 0, 19 do box(c, "ARTWORK", 24 + i * lw / 20, y + 3, lw / 20 + 0.5, 8, Win.Ramp(i / 19), 1) end
	text(c, 0, y, 20, "0", "small", "muted")
	local most = layer == "time" and (St.Duration(top) .. " in one spot") or (St.Number(top) .. " XP/h or more")
	text(c, 24 + lw + 8, y, 260, most, "small", "muted")
	text(c, width - 320, y, 320, "White: your path" .. (flights and "  ·  Green: flights" or ""), "small", "muted", "RIGHT")
	return y + 20
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawHeader()
	for _, b in ipairs(W.pages) do
		local on = b.page == state.page
		local a = T.Color("insights")
		T.PaintRound(b, on and { a[1], a[2], a[3], 0.16 } or "bg2")
		textColor(b.text, on and "text" or "text2")
		paint(b.line, "insights")
		b.line:SetShown(on)
	end
	W.logo:Paint()
end

draw = function()
	if not W.frame then return end
	releaseAll()
	if W.canvas then W.canvas:Hide() end
	if W.crest then W.crest:Hide() W.who:Hide() W.whoSub:Hide() end
	-- The page fills the window, whatever its size.
	local fw, fh = W.frame:GetWidth() or Win.W, W.frame:GetHeight() or Win.H
	W.pageW = fw - 2 * PAD - 6
	W.child:SetWidth(W.pageW)
	W.top:SetWidth(fw - 2 * PAD)
	local pick, chars = selected()
	drawHeader()
	local topH = drawTop(chars, pick)
	W.scroll:ClearAllPoints()
	W.scroll:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD, -(HEADER_H + 12 + topH + 6))
	W.scroll:SetPoint("BOTTOMRIGHT", W.frame, "BOTTOMRIGHT", -PAD + 6, PAD)
	local view = fh - (HEADER_H + 12 + topH + 6) - PAD
	local h
	if state.page == "map" then h = drawMap(pick.log, view) else h = drawOverview(pick.log, pick.key) end
	W.child:SetHeight(max(1, h))
	W.range = max(0, h - view)
	if (W.scroll:GetVerticalScroll() or 0) > W.range then W.scroll:SetVerticalScroll(W.range) end
end
Win.Draw = draw

function Win.Open(page)
	if not W.frame then build() end
	state.char = state.char or R.CharKey()
	state.page = page or state.page
	state.confirm = nil
	W.frame:Show()
	W.scroll:SetVerticalScroll(0)
	draw()
end

function Win.Toggle()
	if Win.Shown() then Win.Close() else Win.Open() end
end

function Win.Close() if W.frame then W.frame:Hide() end end
function Win.Shown() return W.frame ~= nil and W.frame:IsShown() end

S.On("INSIGHTS_UPDATED", function() if Win.Shown() then draw() end end)
-- A new theme or accent: everything painted again.
S.On("THEME_CHANGED", function() if Win.Shown() then draw() end end)
S.On("ACCENT_CHANGED", function() if Win.Shown() then draw() end end)

S.On("READY", function()
	S.MinimapButton({
		key = "Insights", name = "Pathwise Insights", shownPath = "insights.minimap", anglePath = "insights.minimapAngle",
		accent = "insights", glyph = "list",
		lines = { "Click: your leveling numbers", "Right-click: the map" },
		onClick = function(which)
			if which == "RightButton" then Win.Open("map") else Win.Toggle() end
		end,
	})
end)

S.RegisterModule({
	key = "insights", name = "Pathwise Insights", accent = "insights",
	about = "Your leveling numbers, records and a heat map of where you went",
	open = function() Win.Open() end,
})

SLASH_PATHWISEINSIGHTS1 = "/pwinsights"
SlashCmdList = SlashCmdList or {}
SlashCmdList.PATHWISEINSIGHTS = function(msg)
	if tostring(msg or ""):lower():find("map") then Win.Open("map") else Win.Toggle() end
end
