-- Pathwise guide window, Signature style: the "Window" guide style (v2).
-- The guide on screen has three styles (guide.style), one shown at a time:
--   "tracker"  a compact card beside the screen's edge (UI/TrackerCard.lua)
--   "window"   this window: a header with the route's crest, tabs, the step
--   "minimal"  floating text over the game, no window (UI/Hud.lua)
-- The Signature Hub (UI/Hub.lua) is the full window, opened on demand.
-- Every style draws the same view; Guide.SetView fires GUIDE_VIEW for them.
--
-- Two layouts of this window:
--   full     header (zone, step counter), a toolbar row, 2 px progress line, the step card (what to do right
--            now: "Step 28", the action with its person or quest picked out,
--            objective counts, coordinates), the steps from here as a
--            numbered list with one line per action ("Talk to Gryan
--            Stoutmantle", "Turn in ...", "Accept ..."), an optional detour
--            card and the footer (Back, Skip, Report, Next)
--   compact  one bar: title, current objective, step, distance, expand
-- Switching layouts changes nothing in the route (the view comes from the
-- guide engine either way).
--
-- The window draws a *view* from the guide engine (Engine.View); it never
-- reads quests itself.
--
-- view = {
--   route = "Tirisfal Glades", index = 6, count = 48, progress = 0.12,
--   title, text, coords = "30.7, 64.2",
--   card = { line, ... },               what to do now (Engine.LinesOf's lines)
--   steps = { { index, title, note, current, lines = { line, ... } }, ... },
--   objectives = { { text, have, need, done }, ... }, (the compact bar)
--   detour = { label = "Optional · Tailoring", text, sub } or nil,
--   nearby = { { text = "Turn in ...", sub = "Name  ·  40 yd" }, ... }, (Engine.Nearby)
--   next = "Turn in ...",
-- }

local ADDON, ns = ...
local T = ns.Theme
local floor, max, min, abs = math.floor, math.max, math.min, math.abs

ns.Defaults("guide", {
	shown = true,
	compact = false,
	style = "tracker", -- "tracker" | "window" | "minimal"
	locked = false, -- pinned in place (the pin in its header)
	point = nil, -- { point, x, y [, relativePoint] }
	width = 400, -- room for the tabs and the buttons beside them
	height = nil, -- nil: the window fits each step; a number: the height dragged with the grip
})

local PAD = T.SPACE.l

local W = {} -- widgets
local view -- what the window shows
local Guide = ns.Guide or {}
Guide.TOOLS_H = 34 -- the tab row under the title
Guide.HEAD_H = 56 -- the header: crest, eyebrow, route
Guide.PROGRESS_GAP = 8 -- between the tabs' underline and the progress line
Guide.STYLES = { "tracker", "window", "minimal" }
Guide.STYLE_NAMES = { tracker = "Tracker", window = "Window", minimal = "Minimal" }
-- The resize grip's bounds (and the client's, SetResizeBounds).
Guide.MIN_W, Guide.MAX_W = 360, 600
Guide.MIN_H, Guide.MAX_H = 220, 900
ns.Guide = Guide
Pathwise.Guide = Guide

local liveHeight -- the height while the grip is dragged, before guide.height saves it

-- The guide style chosen (an unknown saved value reads as the tracker).
function Guide.Style()
	local s = ns.Get("guide.style")
	return Guide.STYLE_NAMES[s] and s or "tracker"
end

-- Hides the on-screen guide (any style's close button), saying once how to
-- bring it back.
local hinted
function Guide.Hide()
	ns.Set("guide.shown", false)
	if hinted then return end
	hinted = true
	ns.Print(ns.Get("minimap.shown") and "the guide is hidden: click Pathwise's minimap button for the hub, and pick a style under On screen."
		or "the guide is hidden: bring it back with your key (Key Bindings > Pathwise), or show the minimap button in Settings.")
end

-- The next style in turn (a key binding, /pw style), showing the guide.
function Guide.CycleStyle()
	local now = Guide.Style()
	local at = 1
	for i, s in ipairs(Guide.STYLES) do if s == now then at = i end end
	ns.Set("guide.style", Guide.STYLES[at % #Guide.STYLES + 1])
	ns.Set("guide.shown", true)
end

-- The frame of the guide on screen now (any style), if it is shown.
local STYLE_FRAMES = { tracker = "PathwiseTracker", window = "PathwiseGuide", minimal = "PathwiseHud" }
function Guide.Frame()
	local f = _G[STYLE_FRAMES[Guide.Style()]]
	if f and f.IsShown and f:IsShown() then return f end
	return nil
end

-- Whether the on-screen guide in `style` should show now.
function Guide.StyleShown(style)
	if ns.Hub and ns.Hub.Shown() then return false end -- the hub shows the step
	return ns.Get("guide.shown") and Guide.Style() == style and true or false
end

local function clampW(w) return min(Guide.MAX_W, max(Guide.MIN_W, w)) end
local function clampH(h) return min(Guide.MAX_H, max(Guide.MIN_H, h)) end

-- The window's own height (the grip's drag, else guide.height), or nil when
-- it fits each step.
function Guide.FixedHeight()
	local h = liveHeight or ns.Get("guide.height")
	if type(h) ~= "number" then return nil end
	return clampH(h)
end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

-- The point the window hangs from. The grip pins it by its top-left to the
-- screen's bottom-left, so the relative point is kept when it differs.
local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("guide.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

---------------------------------------------------------------------------
-- Resize grip: drag the bottom-right corner for width and height. The drag
-- is followed by hand, so the steps reflow as it goes.
---------------------------------------------------------------------------

-- A vertical drag shorter than this leaves the height fitting each step, so
-- a sideways drag only changes the width.
local HEIGHT_SLOP = 4

-- The grip's state: held, under the cursor, and the drag under way.
local drag = {}

local function paintGrip(g)
	local c = T.Color(drag.pressed and "accent" or (drag.over and "text" or "muted"))
	g.icon:SetVertexColor(c[1], c[2], c[3], 1)
end

-- The cursor in the window's own units ("Window size" included).
local function cursorAt(f)
	local x, y = GetCursorPosition()
	local s = f:GetEffectiveScale() or 1
	return x / s, y / s
end

local function resizeUpdate(g)
	local f = W.frame
	local x, y = cursorAt(f)
	local w = clampW(floor(drag.startW + (x - drag.startX) + 0.5))
	local dy = drag.startY - y -- down is taller
	if not drag.sizingH and abs(dy) >= HEIGHT_SLOP then drag.sizingH = true end
	local h = drag.sizingH and clampH(floor(drag.startH + dy + 0.5)) or liveHeight
	if w ~= floor(f:GetWidth() + 0.5) or h ~= liveHeight then
		f:SetWidth(w)
		liveHeight = h
		Guide.Refresh()
	end
end

local function resizeStart(g, button)
	if button and button ~= "LeftButton" then return end
	if ns.Get("guide.locked") then return end -- pinned: no resizing
	local f = W.frame
	-- The top-left corner stays where it is; the right and bottom edges follow the grip.
	local l, t = f:GetLeft(), f:GetTop()
	if l and t then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	end
	drag.startX, drag.startY = cursorAt(f)
	drag.startW, drag.startH = f:GetWidth(), f:GetHeight()
	drag.sizingH = nil
	liveHeight = Guide.FixedHeight()
	drag.pressed = true
	paintGrip(g)
	if GameTooltip then GameTooltip:Hide() end
	g:SetScript("OnUpdate", resizeUpdate)
end

local function resizeStop(g, button)
	if button == "RightButton" and not g:GetScript("OnUpdate") then
		-- Right-click: the height fits each step again.
		ns.Set("guide.height", nil)
		return
	end
	drag.pressed = nil
	paintGrip(g)
	if not g:GetScript("OnUpdate") then return end
	g:SetScript("OnUpdate", nil)
	local f = W.frame
	local h = drag.sizingH and liveHeight
	liveHeight = nil
	drag.sizingH = nil
	ns.Set("guide.width", floor(f:GetWidth() + 0.5))
	if h then ns.Set("guide.height", h) end
	savePoint(f)
	Guide.Refresh()
end

local function buildGrip(f)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(Guide.MIN_W, Guide.MIN_H, Guide.MAX_W, Guide.MAX_H) end
	local g = CreateFrame("Button", nil, f)
	W.grip = g
	g:SetSize(14, 14) -- inside the 16 px padding, clear of Next
	g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	g:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
	g.icon = g:CreateTexture(nil, "OVERLAY")
	g.icon:SetTexture(T.MEDIA .. "glyph-resize")
	g.icon:SetSize(12, 12)
	g.icon:SetPoint("BOTTOMRIGHT", 0, 0)
	paintGrip(g)
	g:SetScript("OnEnter", function(self)
		drag.over = true
		paintGrip(self)
		if GameTooltip and not self:GetScript("OnUpdate") then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			ns.Tip.SetText(GameTooltip, "Resize", 1, 1, 1)
			ns.Tip.AddLine(GameTooltip, "Drag to change the width and height.", nil, nil, nil, true)
			ns.Tip.AddLine(GameTooltip, "Right-click: fit the height to each step.", nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	g:SetScript("OnLeave", function(self)
		drag.over = nil
		paintGrip(self)
		if GameTooltip then GameTooltip:Hide() end
	end)
	g:SetScript("OnMouseDown", resizeStart)
	g:SetScript("OnMouseUp", resizeStop)
	g:SetScript("OnHide", resizeStop)
end

-- The step list scrolls once the window is shorter than the step.
local function scrollBy(scroll, delta)
	local v = max(0, min(W.scrollRange or 0, (scroll:GetVerticalScroll() or 0) - delta * 40))
	scroll:SetVerticalScroll(v)
	Guide.PaintThumb()
end

-- A thin thumb on the right edge says how far down the step the view is.
function Guide.PaintThumb()
	local thumb, range, viewH = W.thumb, W.scrollRange or 0, W.viewH or 0
	if not thumb then return end
	if range <= 0 or viewH <= 0 then thumb:Hide() return end
	local content = viewH + range
	local h = max(20, viewH * viewH / content)
	local at = (W.scroll:GetVerticalScroll() or 0) / range
	thumb:ClearAllPoints()
	thumb:SetPoint("TOPRIGHT", W.scroll, "TOPRIGHT", -3, -((viewH - h) * at))
	thumb:SetHeight(h)
	thumb:Show()
end

local function build()
	local f = CreateFrame("Frame", "PathwiseGuide", UIParent)
	W.frame = f
	f:SetWidth(clampW(ns.Get("guide.width") or 400))
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.RoundWindow(f, 10)
	T.TrackScale(f)
	local saved = ns.Get("guide.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220)
	end

	-- Header: the route's crest, "LEVELING ROUTE · ALLIANCE", the route and
	-- its levels, the step counter; the tabs below.
	local head = CreateFrame("Frame", nil, f)
	W.head = head
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(Guide.HEAD_H)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() if T.Movable("guide.locked") then f:StartMoving() end end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)

	W.crest = T.Crest(head, 34)
	W.crest:SetPoint("LEFT", 14, -2)
	W.icon = W.crest
	W.eyebrow = T.Text(head, "label", "accent")
	W.eyebrow:SetPoint("TOPLEFT", W.crest, "TOPRIGHT", 12, 0)
	W.eyebrow:SetWordWrap(false)
	W.name = T.TextAt(head, "semibold", 16, "text")
	W.name:SetPoint("TOPLEFT", W.eyebrow, "BOTTOMLEFT", 0, -4)
	W.name:SetText("Pathwise")
	W.name:SetWordWrap(false)

	-- Top row: the zone (route) and the step counter. The buttons have a
	-- row of their own under it, so the name has the whole width.
	W.pin = T.PinButton(head, "guide.locked", 24)
	W.pin:SetPoint("TOPRIGHT", -8, -8)
	W.counter = T.Text(head, "meta", "text2")
	W.counter:SetPoint("RIGHT", W.pin, "LEFT", -6, 0)
	W.counter:SetJustifyH("RIGHT")
	W.counter:SetWordWrap(false)
	W.name:SetPoint("RIGHT", W.counter, "LEFT", -8, 0)
	W.eyebrow:SetPoint("RIGHT", W.counter, "LEFT", -8, 0)
	W.route = W.name

	-- The tabs: Guide (this), Routes, Professions, Dungeons; then the hub,
	-- sync, settings, compact and close on the right.
	local tools = CreateFrame("Frame", nil, f)
	W.tools = tools
	tools:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	tools:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)
	tools:SetHeight(Guide.TOOLS_H)
	tools:EnableMouse(true)
	tools:RegisterForDrag("LeftButton")
	tools:SetScript("OnDragStart", function() if T.Movable("guide.locked") then f:StartMoving() end end)
	tools:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)
	W.tabs = {}
	local prevTab
	for i, spec in ipairs({ { "Guide", nil }, { "Routes", "SHOW_ZONES" }, { "Professions", "SHOW_PROFESSIONS" }, { "Dungeons", "SHOW_DUNGEONS" } }) do
		local tab = CreateFrame("Button", nil, tools)
		tab:SetHeight(Guide.TOOLS_H)
		tab.text = T.Text(tab, "button", i == 1 and "text" or "text2")
		tab.text:SetPoint("CENTER", 0, 1)
		tab.text:SetText(spec[1])
		tab:SetWidth((tab.text:GetStringWidth() or 40) + 16)
		tab.line = tab:CreateTexture(nil, "ARTWORK")
		tab.line:SetHeight(2)
		tab.line:SetPoint("BOTTOMLEFT", 6, 0)
		tab.line:SetPoint("BOTTOMRIGHT", -6, 0)
		T.SetColor(tab.line, "accent")
		tab.line:SetShown(i == 1)
		if spec[2] then
			tab:SetScript("OnClick", function() ns.Fire(spec[2]) end)
			tab:SetScript("OnEnter", function() T.TextColor(tab.text, "text") end)
			tab:SetScript("OnLeave", function() T.TextColor(tab.text, "text2") end)
		end
		tab:SetPoint("LEFT", prevTab or tools, prevTab and "RIGHT" or "LEFT", prevTab and 0 or 6, 0)
		prevTab = tab
		W.tabs[i] = tab
	end
	W.tabLine = tools:CreateTexture(nil, "BORDER")
	W.tabLine:SetHeight(1)
	W.tabLine:SetPoint("BOTTOMLEFT", 12, 0)
	W.tabLine:SetPoint("BOTTOMRIGHT", -12, 0)
	T.SetColor(W.tabLine, "border")
	W.hub = T.IconButton(tools, "grid", "Open the hub", function() ns.Fire("TOGGLE_HUB") end)
	W.sync = T.IconButton(tools, "sync", "Sync with your quest log", function() ns.Fire("GUIDE_SYNC") end)
	W.settings = T.IconButton(tools, "settings", "Settings", function() ns.Fire("SHOW_SETTINGS") end)
	W.close = T.IconButton(tools, "close", "Close", function() Guide.Hide() end)
	W.close:SetPoint("RIGHT", -6, 0)
	W.mode = T.IconButton(tools, "collapse", "Compact mode", function() Guide.SetCompact(not ns.Get("guide.compact")) end)
	W.mode:SetPoint("RIGHT", W.close, "LEFT", -2, 0)
	W.settings:SetPoint("RIGHT", W.mode, "LEFT", -2, 0)
	W.sync:SetPoint("RIGHT", W.settings, "LEFT", -2, 0)
	W.hub:SetPoint("RIGHT", W.sync, "LEFT", -2, 0)

	W.progress = T.ProgressLine(f)
	W.progress.track:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 12, -Guide.PROGRESS_GAP)
	W.progress.track:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", -12, -Guide.PROGRESS_GAP)

	-- Body (full layout): the child of a scroll area under the progress line.
	-- It fits the step, or scrolls when the window has a height of its own.
	local scroll = CreateFrame("ScrollFrame", nil, f)
	W.scroll = scroll
	scroll:SetPoint("TOPLEFT", tools, "BOTTOMLEFT", 0, -(T.PROGRESS_H + Guide.PROGRESS_GAP))
	scroll:SetPoint("TOPRIGHT", tools, "BOTTOMRIGHT", 0, -(T.PROGRESS_H + Guide.PROGRESS_GAP))
	scroll:EnableMouseWheel(false)
	scroll:SetScript("OnMouseWheel", scrollBy)
	local body = CreateFrame("Frame", nil, scroll)
	W.body = body
	body:SetWidth(f:GetWidth())
	body:SetHeight(1)
	scroll:SetScrollChild(body)
	W.thumb = f:CreateTexture(nil, "OVERLAY")
	W.thumb:SetWidth(2)
	T.SetColor(W.thumb, "muted")
	W.thumb:Hide()

	-- The step card: what to do right now.
	local now = CreateFrame("Frame", nil, body)
	W.now = now
	T.Round(now, "bg2", false, 6)
	now.accent = now:CreateTexture(nil, "ARTWORK")
	now.accent:SetWidth(2)
	now.accent:SetPoint("TOPLEFT", 0, 0)
	now.accent:SetPoint("BOTTOMLEFT", 0, 0)
	T.SetColor(now.accent, "accent")
	now.label = T.Text(now, "label", "accent")
	now.title = T.Text(now, "small", "text2")
	now.title:SetJustifyH("RIGHT")
	now.title:SetWordWrap(false)
	now.coords = T.Text(now, "small", "muted")
	now.lines = {}

	-- The steps from here on, one line per action.
	W.blocks = {}

	W.divider = T.Divider(body)

	-- Detour card.
	local card = CreateFrame("Frame", nil, body)
	W.card = card
	do
		local a = T.Color("accent")
		T.Round(card, { a[1], a[2], a[3], 0.06 }, { a[1], a[2], a[3], 0.45 }, 6)
	end
	card.star = T.Glyph(card, "glyph-star", 16, "accent")
	card.star:SetPoint("TOPLEFT", 12, -12)
	card.label = T.Text(card, "label", "accent")
	card.text = T.Text(card, "meta", "text")
	card.sub = T.Text(card, "small", "text2")
	card.go = T.Button(card, "Go", "default", function() ns.Fire("DETOUR_GO", view and view.detour) end)
	card.skip = T.IconButton(card, "close", "Skip this detour", function() ns.Fire("DETOUR_SKIP", view and view.detour) end, 20)

	-- From your quest log: held quests near the player.
	W.nearLabel = T.Text(body, "label", "accent")
	W.nearLabel:SetText(ns.U(ns.L("From your quest log")))
	W.nearRows = {}
	for i = 1, 4 do
		W.nearRows[i] = { text = T.Text(body, "meta", "text"), sub = T.Text(body, "small", "text2") }
	end

	-- Footer.
	W.back = T.RoundButton(f, "Back", "default", function() ns.Fire("GUIDE_BACK") end, 32)
	W.skip = T.RoundButton(f, "Skip", "default", function() ns.Fire("GUIDE_SKIP") end, 32)
	W.report = T.IconButton(f, "flag", "Report this step", function() ns.Fire("REPORT_STEP", view) end, 32)
	W.next = T.RoundButton(f, "Next", "primary", function() ns.Fire("GUIDE_NEXT") end, 32)

	-- Empty state.
	W.empty = T.Text(body, "meta", "text2")

	-- The leveling tracker's line (Guide/Tracker.lua).
	W.stats = T.Text(body, "small", "text2")
	W.stats:SetWordWrap(false)

	-- Compact bar.
	local bar = CreateFrame("Button", nil, f)
	W.bar = bar
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(48)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() if T.Movable("guide.locked") then f:StartMoving() end end)
	bar:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)
	bar:SetScript("OnClick", function() Guide.SetCompact(false) end)
	bar.icon = T.Icon(bar, 16)
	bar.icon:SetPoint("LEFT", 12, 0)
	bar.expand = T.IconButton(bar, "expand", "Full guide", function() Guide.SetCompact(false) end)
	bar.expand:SetPoint("RIGHT", -6, 0)
	bar.step = T.Text(bar, "small", "text2")
	bar.step:SetPoint("TOPRIGHT", bar.expand, "TOPLEFT", -8, 4)
	bar.step:SetJustifyH("RIGHT")
	bar.dist = T.Text(bar, "small", "accent")
	bar.dist:SetPoint("BOTTOMRIGHT", bar.expand, "BOTTOMLEFT", -8, -4)
	bar.dist:SetJustifyH("RIGHT")
	bar.title = T.Text(bar, "window", "text")
	bar.title:SetPoint("TOPLEFT", bar.icon, "TOPRIGHT", 10, 8)
	bar.title:SetPoint("RIGHT", bar.step, "LEFT", -10, 0)
	bar.title:SetWordWrap(false)
	bar.line = T.Text(bar, "meta", "text2")
	bar.line:SetPoint("TOPLEFT", bar.title, "BOTTOMLEFT", 0, -3)
	bar.line:SetPoint("RIGHT", bar.step, "LEFT", -10, 0)
	bar.line:SetWordWrap(false)
	W.barProgress = T.ProgressLine(f)
	W.barProgress.track:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 1, 0)
	W.barProgress.track:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", -1, 0)

	buildGrip(f)
end

---------------------------------------------------------------------------
-- Layout: top to bottom, spacing instead of borders
---------------------------------------------------------------------------

local function place(fs, anchor, gap, inset)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", anchor, anchor == W.body and "TOPLEFT" or "BOTTOMLEFT", anchor == W.body and (inset or PAD) or 0, -(gap or 0))
	fs:SetPoint("RIGHT", W.body, "RIGHT", -PAD, 0)
end

local function height(fs)
	return fs:IsShown() and max(0, fs:GetStringHeight() or 0) or 0
end

---------------------------------------------------------------------------
-- Action lines: an icon by kind, the text with its name picked out, a count
---------------------------------------------------------------------------

-- kind -> { texture, colour, size }
local ICON = {
	talk = { "glyph-talk", "text2", 12 },
	accept = { "glyph-quest", "warning", 12 },
	turnin = { "glyph-turnin", "warning", 12 },
	complete = { "glyph-kill", "accent", 12 },
	objective = { "dot-open", "accent", 7 },
	["goto"] = { "glyph-goto", "text2", 12 },
	have = { "glyph-bag", "text2", 12 },
	bind = { "glyph-zones", "text2", 12 },
	train = { "glyph-prof", "text2", 12 }, learn = { "glyph-prof", "text2", 12 },
	craft = { "glyph-prof", "text2", 12 }, skill = { "glyph-prof", "text2", 12 },
	level = { "glyph-upgrade", "text2", 12 },
}
local NOTE_ICON = { "dot-done", "muted", 5 }
Guide.ICON = ICON

local function hex(name)
	local c = T.Color(name)
	return ("|cff%02x%02x%02x"):format(floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- The text of a line: "Talk to |cff..Simmer|r", the name in the accent while
-- the line is still to do.
function Guide.LineText(line)
	local name = line.name or ""
	if name ~= "" and not line.done then name = hex(line.kind == "talk" and "success" or "accent") .. name .. "|r" end
	local text = (line.lead or "") .. name .. (line.tail or "")
	if line.optional and not line.done then text = text .. "  (optional)" end
	return text
end

local function lineWidget(pool, parent, i)
	local w = pool[i]
	if w then return w end
	w = CreateFrame("Frame", nil, parent)
	w.icon = w:CreateTexture(nil, "ARTWORK")
	w.icon:SetPoint("TOPLEFT", 0, -2)
	w.text = T.Text(w, "meta", "text")
	w.text:SetPoint("TOPLEFT", 18, 0)
	w.count = T.Text(w, "small", "text2")
	w.count:SetPoint("TOPRIGHT", 0, -1)
	w.count:SetJustifyH("RIGHT")
	w.text:SetPoint("RIGHT", w.count, "LEFT", -6, 0)
	pool[i] = w
	return w
end

local function paintLine(w, line)
	local spec = ICON[line.kind] or NOTE_ICON
	if line.kind == "objective" and line.done then spec = { "dot-done", "success", 7 } end
	w.icon:SetTexture(T.MEDIA .. spec[1])
	w.icon:SetSize(spec[3], spec[3])
	local c = T.Color(line.done and "success" or spec[2])
	w.icon:SetVertexColor(c[1], c[2], c[3])
	w.icon:SetAlpha(line.done and 0.7 or 1)
	w.text:SetText(Guide.LineText(line))
	T.TextColor(w.text, line.done and "muted" or ((line.info or line.optional) and "text2" or "text"))
	w.count:SetText(line.need and ("%d/%d"):format(line.have or 0, line.need) or "")
	T.TextColor(w.count, line.done and "muted" or "text2")
	w.lineKind = line.kind
end

-- Lines one under another in `parent`, from `y` down, `inset` from its left
-- and `right` from its right; -> the y under the last line.
local function drawLines(pool, parent, lines, y, inset, right)
	for i, line in ipairs(lines) do
		local w = lineWidget(pool, parent, i)
		w:Show()
		paintLine(w, line)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -y)
		w:SetPoint("RIGHT", parent, "RIGHT", -right, 0)
		local indent = line.kind == "objective" and 18 or 0
		w.icon:ClearAllPoints()
		w.icon:SetPoint("TOPLEFT", indent + (line.kind == "objective" and 3 or 0), line.kind == "objective" and -5 or -2)
		w.text:ClearAllPoints()
		w.text:SetPoint("TOPLEFT", 18 + indent, 0)
		w.text:SetPoint("RIGHT", w.count, "LEFT", -6, 0)
		local h = max(14, height(w.text))
		w:SetHeight(h)
		y = y + h + 3
	end
	for i = #lines + 1, #pool do pool[i]:Hide() end
	return y
end
Guide.MAX_LINES = 8 -- per listed step; the rest as "+N more"

-- One step of the list: its number, title, note and lines.
local function blockWidget(i)
	local b = W.blocks[i]
	if b then return b end
	b = CreateFrame("Frame", nil, W.body)
	b.num = T.Text(b, "label", "muted")
	b.num:SetPoint("TOPRIGHT", 0, 0)
	b.num:SetJustifyH("RIGHT")
	b.title = T.Text(b, "label", "text2")
	b.title:SetPoint("TOPLEFT", 0, 0)
	b.title:SetPoint("RIGHT", b, "RIGHT", -24, 0)
	b.title:SetWordWrap(false)
	b.note = T.Text(b, "small", "warning")
	b.lines = {}
	W.blocks[i] = b
	return b
end

-- Size the scroll area for a body `contentH` tall and the window around it.
-- `footH`: the footer's room under the step list when the window has its own
-- height (the footer then stays at the bottom edge; else it follows the list).
local CHROME_H -- header, toolbar and progress line
local function fitBody(contentH, footH)
	local f, scroll = W.frame, W.scroll
	CHROME_H = Guide.HEAD_H + Guide.TOOLS_H + T.PROGRESS_H + Guide.PROGRESS_GAP
	local fixed = Guide.FixedHeight()
	local viewH = fixed and max(1, fixed - CHROME_H - footH) or contentH
	W.body:SetWidth(f:GetWidth())
	W.body:SetHeight(max(1, contentH))
	scroll:SetHeight(max(1, viewH))
	W.viewH = viewH
	W.scrollRange = max(0, contentH - viewH)
	if (scroll:GetVerticalScroll() or 0) > W.scrollRange then scroll:SetVerticalScroll(W.scrollRange) end
	-- The wheel only where there is something to scroll, so it zooms the camera otherwise.
	scroll:EnableMouseWheel(W.scrollRange > 0)
	f:SetHeight(fixed or (CHROME_H + contentH))
	Guide.PaintThumb()
	return fixed
end

local function layoutFull()
	local f, body = W.frame, W.body
	W.head:Show()
	W.tools:Show()
	W.scroll:Show()
	W.body:Show()
	W.grip:Show()
	W.bar:Hide()
	W.barProgress.track:Hide()
	W.barProgress.fill:Hide()
	W.progress.track:Show()
	local width = f:GetWidth()
	local y = PAD -- running height of the body

	local has = view ~= nil
	W.route:SetText(has and view.route or "Pathwise")
	W.eyebrow:SetText(Guide.Eyebrow(view))
	W.crest:SetFaction(has and view.faction or nil)
	W.counter:SetText(has and view.count and ("%d / %d"):format(view.index or 0, view.count) or "")
	W.progress:SetProgress(has and view.progress or 0)


	W.now:SetShown(has)
	W.empty:SetShown(not has)
	W.back:SetShown(has)
	W.skip:SetShown(has)
	W.next:SetShown(has)
	W.report:SetShown(has)
	-- Their labels are drawn again with the step text, so a label lost while
	-- the font was loading comes back on the next redraw (T.Relabel).
	if has then for _, b in ipairs({ W.back, W.skip, W.next }) do T.Relabel(b) end end

	if not has then
		place(W.empty, body, y)
		W.empty:SetText("No route for this character yet.\n\nOpen Zones for your level (the map button above) to pick one.")
		local h = y + height(W.empty) + PAD
		W.divider:Hide()
		W.card:Hide()
		W.stats:Hide()
		W.nearLabel:Hide()
		for _, row in ipairs(W.nearRows) do row.text:Hide() row.sub:Hide() end
		for _, b in ipairs(W.blocks) do b:Hide() end
		fitBody(h, 0)
		return
	end

	-- The step card: "STEP 28", what to do now, where.
	local now = W.now
	now:ClearAllPoints()
	now:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
	now:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
	now.label:ClearAllPoints()
	now.label:SetPoint("TOPLEFT", 12, -10)
	now.label:SetText(view.index and ns.U((ns.L("Step %d")):format(view.index)) or (view.extra and "EXTRA QUEST" or "PATHWISE"))
	now.title:ClearAllPoints()
	now.title:SetPoint("TOPRIGHT", -10, -10)
	now.title:SetPoint("LEFT", now.label, "RIGHT", 10, 0)
	now.title:SetText(view.title or "")
	local cardLines = view.card
	if not cardLines or #cardLines == 0 then
		cardLines = { { kind = "note", lead = view.text or view.title or "" } }
	end
	local cy = drawLines(now.lines, now, cardLines, 10 + max(12, height(now.label)) + 8, 12, 10)
	now.coords:SetText(view.coords or "")
	now.coords:SetShown(view.coords ~= nil)
	now.coords:ClearAllPoints()
	now.coords:SetPoint("TOPLEFT", now, "TOPLEFT", 30, -(cy + 2))
	now.coords:SetPoint("RIGHT", now, "RIGHT", -10, 0)
	if view.coords then cy = cy + 2 + height(now.coords) end
	local nowH = cy + 8
	now:SetHeight(nowH)
	y = y + nowH + 12

	-- The steps from here: number, title, the current one's note, its lines.
	local listed = view.steps or {}
	for i, step in ipairs(listed) do
		local b = blockWidget(i)
		b:Show()
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
		b:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
		b.num:SetText(("%02d"):format(step.index))
		T.TextColor(b.num, step.current and "accent" or "muted")
		-- The place's name where it changes (steps at one place follow each
		-- other); the number on the right of every step.
		local newPlace = i == 1 or (listed[i - 1].title ~= step.title)
		b.title:SetShown(newPlace)
		b.title:SetText(newPlace and ns.U(ns.L(step.title or "")) or "")
		T.TextColor(b.title, step.current and "text" or "text2")
		local by = newPlace and (max(12, height(b.title)) + 6) or 0
		b.num:ClearAllPoints()
		b.num:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -by)
		local showNote = step.note and step.note ~= ""
		b.note:SetShown(showNote and true or false)
		if showNote then
			b.note:SetText(step.note)
			if b.note.SetMaxLines then b.note:SetMaxLines(step.current and 0 or 2) end
			b.note:ClearAllPoints()
			b.note:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -by)
			b.note:SetPoint("RIGHT", b, "RIGHT", -24, 0)
			by = by + height(b.note) + 4
		end
		local lines = step.lines or {}
		if #lines > Guide.MAX_LINES then
			local cut = {}
			for k = 1, Guide.MAX_LINES - 1 do cut[k] = lines[k] end
			cut[#cut + 1] = { kind = "note", lead = (ns.L("+%d more")):format(#lines - (Guide.MAX_LINES - 1)), info = true }
			lines = cut
		end
		by = drawLines(b.lines, b, lines, by, 0, 24)
		b:SetHeight(by)
		b:SetAlpha(step.current and 1 or 0.75)
		y = y + by + 8
	end
	for i = #listed + 1, #W.blocks do W.blocks[i]:Hide() end

	W.divider:Show()
	W.divider:ClearAllPoints()
	W.divider:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -y)
	W.divider:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
	y = y + 1

	local d = view.detour
	if d then
		local card = W.card
		card:Show()
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(y + 12))
		card:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
		card.skip:ClearAllPoints()
		card.skip:SetPoint("RIGHT", -6, 0)
		card.go:ClearAllPoints()
		card.go:SetPoint("RIGHT", card.skip, "LEFT", -4, 0)
		card.go:SetHeight(24)
		card.go:SetWidth(48)
		card.go.pwText:SetText(d.aimed and "Stop" or "Go")
		card.label:SetText(ns.U(ns.L(d.label or "Optional")))
		card.text:SetText(d.text or "")
		card.sub:SetText(d.sub or "")
		card.label:ClearAllPoints()
		card.label:SetPoint("TOPLEFT", 36, -10)
		card.label:SetPoint("RIGHT", card.go, "LEFT", -8, 0)
		card.text:ClearAllPoints()
		card.text:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -3)
		card.text:SetPoint("RIGHT", card.go, "LEFT", -8, 0)
		card.sub:ClearAllPoints()
		card.sub:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -2)
		card.sub:SetPoint("RIGHT", card.go, "LEFT", -8, 0)
		local ch = 10 + height(card.label) + 3 + height(card.text) + 2 + height(card.sub) + 10
		card:SetHeight(ch)
		y = y + 12 + ch
	else
		W.card:Hide()
	end

	local near = view.nearby or {}
	W.nearLabel:SetShown(#near > 0)
	if #near > 0 then
		W.nearLabel:ClearAllPoints()
		W.nearLabel:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(y + 12))
		W.nearLabel:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
		y = y + 12 + height(W.nearLabel)
	end
	for i, row in ipairs(W.nearRows) do
		local n = near[i]
		row.text:SetShown(n ~= nil)
		row.sub:SetShown(n ~= nil)
		if n then
			row.text:SetText(n.text or "")
			row.sub:SetText(n.sub or "")
			row.text:ClearAllPoints()
			row.text:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(y + 6))
			row.text:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
			row.sub:ClearAllPoints()
			row.sub:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
			row.sub:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
			y = y + 6 + height(row.text) + 2 + height(row.sub)
		end
	end

	-- The leveling tracker's line: under the list, or with a height of its
	-- own, pinned over the buttons so scrolling never hides it.
	local stats = ns.Tracker and ns.Tracker.Line()
	local fixed = Guide.FixedHeight()
	local btnH = W.next:GetHeight()
	W.stats:SetShown(stats ~= nil)
	W.stats:SetParent(fixed and f or body)
	W.stats:ClearAllPoints()
	local statsH = 0
	if stats then
		W.stats:SetText(stats)
		if fixed then
			W.stats:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD + btnH + 10)
			W.stats:SetPoint("RIGHT", f, "RIGHT", -PAD, 0)
			statsH = height(W.stats) + 10
		else
			W.stats:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -(y + 10))
			W.stats:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
			y = y + 10 + height(W.stats)
		end
	end

	-- Footer: Back left; Skip, Report, Next right. Under the list, or at the
	-- bottom edge when the window has its own height (the list scrolls above it).
	W.back:ClearAllPoints()
	W.next:ClearAllPoints()
	if fixed then
		W.back:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
		W.next:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
		fitBody(y + 4, PAD + btnH + PAD + statsH)
	else
		local footY = y + PAD
		W.back:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -footY)
		W.next:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -footY)
		fitBody(footY + btnH + PAD, 0)
	end
	W.report:ClearAllPoints()
	W.report:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
	W.skip:ClearAllPoints()
	W.skip:SetPoint("LEFT", W.back, "RIGHT", 8, 0)
	f:SetWidth(width)
end

local function layoutCompact()
	local f, bar = W.frame, W.bar
	W.head:Hide()
	W.tools:Hide()
	W.scroll:Hide()
	W.body:Hide()
	W.thumb:Hide()
	W.grip:Hide() -- the bar is one line: it keeps its size
	W.stats:Hide() -- over the buttons when the window has a height of its own
	W.progress.track:Hide()
	W.progress.fill:Hide()
	for _, b in ipairs({ W.back, W.skip, W.next, W.report }) do b:Hide() end
	bar:Show()
	W.barProgress.track:Show()
	local has = view ~= nil
	bar.title:SetText(has and view.title or "Pathwise")
	local o = has and view.objectives and view.objectives[1]
	for _, ob in ipairs(has and view.objectives or {}) do
		if not ob.done then o = ob break end
	end
	bar.line:SetText(o and (o.need and ("%s  %d / %d"):format(o.text, o.have or 0, o.need) or o.text) or (has and view.text or "No route loaded yet"))
	bar.step:SetText(has and view.count and ("%d / %d"):format(view.index or 0, view.count) or "")
	bar.dist:SetText(W.distance or "")
	W.barProgress:SetProgress(has and view.progress or 0)
	f:SetHeight(bar:GetHeight() + T.PROGRESS_H)
end

function Guide.Refresh()
	if not W.frame then return end
	if ns.Get("guide.compact") then layoutCompact() else layoutFull() end
end

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

-- The engine (or /pw demo) hands the window what to show.
function Guide.SetView(v)
	-- A new step starts at its top.
	if W.scroll and not (v and view and v.index == view.index and v.route == view.route) then W.scroll:SetVerticalScroll(0) end
	view = v
	Guide.Refresh()
	ns.Fire("GUIDE_VIEW", v)
end

-- "LEVELING ROUTE · ALLIANCE": what kind of route, and whose.
local KIND = { Leveling = "Leveling route", Class = "Class route", Professions = "Profession route" }
function Guide.Eyebrow(v)
	if not v then return "PATHWISE" end
	if v.extra then return "EXTRA QUEST" end
	local bits = { ns.L(KIND[v.category] or "Route") }
	if v.faction then bits[#bits + 1] = ns.L(v.faction) end
	return ns.U(table.concat(bits, "  ·  "))
end

-- "Alliance  ·  Levels 12-17"
function Guide.RouteLine(v)
	if not v then return "" end
	local bits = {}
	if v.faction then bits[#bits + 1] = ns.L(v.faction) end
	if v.levels and v.levels[1] then
		bits[#bits + 1] = v.levels[2] and v.levels[2] ~= v.levels[1] and (ns.L("Levels %d-%d")):format(v.levels[1], v.levels[2]) or (ns.L("Level %d")):format(v.levels[1])
	end
	return table.concat(bits, "  ·  ")
end

-- "56.6, 52.6  ·  Westfall"
function Guide.PlaceLine(v)
	if not v then return "" end
	if v.xy then return v.zone and (v.xy .. "  ·  " .. v.zone) or v.xy end
	return v.coords or ""
end

function Guide.View() return view end

function Guide.SetCompact(on)
	ns.Set("guide.compact", on and true or nil)
end

function Guide.Show(on)
	if on == nil then on = true end
	-- This window is the "window" style; the others draw their own. None
	-- while the hub is open.
	if not Guide.StyleShown("window") then on = false end
	if on and not W.frame then build() end
	if not W.frame then return end
	W.frame:SetShown(on)
	if on then Guide.Refresh() end
end

ns.On("TOGGLE_GUIDE", function() ns.Set("guide.shown", not ns.Get("guide.shown")) end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" or path == "guide.style" then Guide.Show(ns.Get("guide.shown"))
	elseif path == "guide.compact" or path == "guide.height" then Guide.Refresh()
	elseif path == "guide.width" and W.frame then
		W.frame:SetWidth(clampW(ns.Get("guide.width") or 400))
		Guide.Refresh()
	end
end)
ns.On("READY", function() if ns.Get("guide.shown") then Guide.Show(true) end end)
ns.On("HUB_TOGGLED", function() Guide.Show(ns.Get("guide.shown")) end)
ns.On("TRACKER_UPDATED", function() if W.frame and W.frame:IsShown() then Guide.Refresh() end end)

-- The compact bar shows the arrow's distance when there is one.
ns.On("WAYPOINT_CHANGED", function(target)
	if not target then W.distance = nil Guide.Refresh() end
end)
function Guide.SetDistance(text)
	if W.distance == text then return end
	W.distance = text
	if W.frame and ns.Get("guide.compact") then W.bar.dist:SetText(text or "") end
end
