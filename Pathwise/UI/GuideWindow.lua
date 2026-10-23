-- Pathwise guide window, Signature style. Two layouts of one window:
--   full     header, 2 px progress line, current step (title, instructions,
--            coordinates, objectives), an optional detour card, "Then", and
--            the footer (Back, Skip, Report, Next)
--   compact  one bar: title, current objective, step, distance, expand
-- Switching layouts changes nothing in the route (the view comes from the
-- guide engine either way).
--
-- The window draws a *view*; it never reads quests itself. The guide engine
-- (not built yet) will provide it through Pathwise.Guide.View(); until then
-- the window shows its empty state, and /pw demo shows a labelled sample.
--
-- view = {
--   route = "Tirisfal Glades", index = 6, count = 48, progress = 0.12,
--   title, text, coords = "30.7, 64.2",
--   objectives = { { text, have, need, done }, ... },
--   detour = { label = "Optional · Tailoring", text, sub } or nil,
--   next = "Turn in ...",
-- }

local ADDON, ns = ...
local T = ns.Theme
local floor, max = math.floor, math.max

ns.Defaults("guide", {
	shown = true,
	compact = false,
	point = nil, -- { point, x, y }
	width = 340,
})

local PAD = T.SPACE.l
local MAX_OBJECTIVES = 10

local W = {} -- widgets
local view -- what the window shows
local Guide = ns.Guide or {}
ns.Guide = Guide
Pathwise.Guide = Guide

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function savePoint(f)
	local p, _, _, x, y = f:GetPoint(1)
	ns.Set("guide.point", { p, floor(x + 0.5), floor(y + 0.5) })
end

local function label(parent, text)
	local fs = T.Text(parent, "label", "text2")
	fs:SetText(text:upper())
	return fs
end

local function build()
	local f = CreateFrame("Frame", "PathwiseGuide", UIParent)
	W.frame = f
	f:SetWidth(ns.Get("guide.width"))
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.Panel(f)
	T.TrackGround(f)
	T.TrackScale(f)
	local saved = ns.Get("guide.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
	else
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220)
	end

	-- Header: icon, name, route, counter, compact, close.
	local head = CreateFrame("Frame", nil, f)
	W.head = head
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(T.HEADER_H)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() f:StartMoving() end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)

	W.icon = T.Icon(head, 16)
	W.icon:SetPoint("LEFT", 12, 0)
	W.name = T.Text(head, "window", "text")
	W.name:SetPoint("LEFT", W.icon, "RIGHT", 8, 0)
	W.name:SetText("Pathwise")
	W.name:SetWordWrap(false)

	W.close = T.IconButton(head, "close", "Close", function() ns.Set("guide.shown", false) end)
	W.close:SetPoint("RIGHT", -6, 0)
	W.mode = T.IconButton(head, "collapse", "Compact mode", function() Guide.SetCompact(not ns.Get("guide.compact")) end)
	W.mode:SetPoint("RIGHT", W.close, "LEFT", -2, 0)
	W.settings = T.IconButton(head, "settings", "Settings", function() ns.Fire("SHOW_SETTINGS") end)
	W.settings:SetPoint("RIGHT", W.mode, "LEFT", -2, 0)
	W.zones = T.IconButton(head, "zones", "Zones for your level", function() ns.Fire("SHOW_ZONES") end)
	W.zones:SetPoint("RIGHT", W.settings, "LEFT", -2, 0)
	W.prof = T.IconButton(head, "prof", "Professions", function() ns.Fire("SHOW_PROFESSIONS") end)
	W.prof:SetPoint("RIGHT", W.zones, "LEFT", -2, 0)
	W.dungeons = T.IconButton(head, "dungeon", "Dungeons for your level", function() ns.Fire("SHOW_DUNGEONS") end)
	W.dungeons:SetPoint("RIGHT", W.prof, "LEFT", -2, 0)
	W.counter = T.Text(head, "small", "text2")
	W.counter:SetPoint("RIGHT", W.dungeons, "LEFT", -6, 0)
	W.counter:SetJustifyH("RIGHT")
	W.counter:SetWordWrap(false)
	W.route = T.Text(head, "meta", "text2")
	W.route:SetPoint("LEFT", W.name, "RIGHT", 8, 0)
	W.route:SetPoint("RIGHT", W.counter, "LEFT", -8, 0)
	W.route:SetWordWrap(false)

	W.progress = T.ProgressLine(f)
	W.progress.track:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 1, 0)
	W.progress.track:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -1, 0)

	-- Body (full layout).
	local body = CreateFrame("Frame", nil, f)
	W.body = body
	body:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -T.PROGRESS_H)
	body:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, -T.PROGRESS_H)

	W.current = label(body, "Current")
	W.title = T.Text(body, "quest", "text")
	W.text = T.Text(body, "meta", "text2")
	W.coords = T.Text(body, "small", "muted")

	W.objectives = {}
	for i = 1, MAX_OBJECTIVES do
		local row = CreateFrame("Frame", nil, body)
		row:SetHeight(18)
		row.dot = row:CreateTexture(nil, "ARTWORK")
		row.dot:SetSize(10, 10)
		row.dot:SetPoint("LEFT", 0, 0)
		row.text = T.Text(row, "body", "text")
		row.text:SetPoint("LEFT", row.dot, "RIGHT", 10, 0)
		row.text:SetWordWrap(false)
		row.count = T.Text(row, "meta", "text2")
		row.count:SetPoint("RIGHT")
		row.count:SetJustifyH("RIGHT")
		row.text:SetPoint("RIGHT", row.count, "LEFT", -8, 0)
		W.objectives[i] = row
	end

	W.divider = T.Divider(body)

	-- Detour card.
	local card = CreateFrame("Frame", nil, body)
	W.card = card
	T.Panel(card, "bg2", false)
	card.label = T.Text(card, "label", "accent")
	card.text = T.Text(card, "meta", "text")
	card.sub = T.Text(card, "small", "text2")
	card.go = T.Button(card, "Go", "default", function() ns.Fire("DETOUR_GO", view and view.detour) end)
	card.skip = T.IconButton(card, "close", "Skip this detour", function() ns.Fire("DETOUR_SKIP", view and view.detour) end, 20)

	W.thenLabel = label(body, "Then")
	W.thenText = T.Text(body, "meta", "text2")

	-- Footer.
	W.back = T.Button(f, "Back", "default", function() ns.Fire("GUIDE_BACK") end)
	W.skip = T.Button(f, "Skip", "default", function() ns.Fire("GUIDE_SKIP") end)
	W.report = T.IconButton(f, "flag", "Report this step", function() ns.Fire("REPORT_STEP", view) end, 28)
	W.next = T.Button(f, "Next", "accent", function() ns.Fire("GUIDE_NEXT") end)

	-- Empty state.
	W.empty = T.Text(body, "meta", "text2")

	-- Compact bar.
	local bar = CreateFrame("Button", nil, f)
	W.bar = bar
	bar:SetPoint("TOPLEFT")
	bar:SetPoint("TOPRIGHT")
	bar:SetHeight(48)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function() f:StartMoving() end)
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

local function dot(row, done, info, optional)
	if info then
		-- An instruction (hearth, fly, train): a small muted dot, no tick.
		row.dot:SetTexture(T.MEDIA .. "dot-done")
		local c = T.Color("muted")
		row.dot:SetVertexColor(c[1], c[2], c[3])
		row.dot:SetSize(6, 6)
		T.TextColor(row.text, "text2")
		T.TextColor(row.count, "text2")
		return
	end
	row.dot:SetSize(10, 10)
	if optional and not done then
		row.dot:SetTexture(T.MEDIA .. "dot-open")
		local c = T.Color("muted")
		row.dot:SetVertexColor(c[1], c[2], c[3])
		T.TextColor(row.text, "text2")
		T.TextColor(row.count, "muted")
		return
	end
	if done then
		row.dot:SetTexture(T.MEDIA .. "dot-done")
		local c = T.Color("success")
		row.dot:SetVertexColor(c[1], c[2], c[3])
		T.TextColor(row.text, "muted")
		T.TextColor(row.count, "muted")
	else
		row.dot:SetTexture(T.MEDIA .. "dot-open")
		local c = T.Color("accent")
		row.dot:SetVertexColor(c[1], c[2], c[3])
		T.TextColor(row.text, "text")
		T.TextColor(row.count, "text2")
	end
end

local function layoutFull()
	local f, body = W.frame, W.body
	W.head:Show()
	W.body:Show()
	W.bar:Hide()
	W.barProgress.track:Hide()
	W.barProgress.fill:Hide()
	W.progress.track:Show()
	local width = f:GetWidth()
	local y = PAD -- running height of the body

	local has = view ~= nil
	W.route:SetText(has and view.route or "")
	W.counter:SetText(has and view.count and ("%d / %d"):format(view.index or 0, view.count) or "")
	W.progress:SetProgress(has and view.progress or 0)

	for _, fs in ipairs({ W.current, W.title, W.text, W.coords, W.thenLabel, W.thenText }) do fs:SetShown(has) end
	W.empty:SetShown(not has)
	W.back:SetShown(has)
	W.skip:SetShown(has)
	W.next:SetShown(has)
	W.report:SetShown(has)

	if not has then
		place(W.empty, body, y)
		W.empty:SetText("No route for this character yet.\n\nOpen Zones for your level (the map button above) to pick one. Routes so far: Tirisfal Glades for Undead, levels 1-10.")
		local h = y + height(W.empty) + PAD
		W.divider:Hide()
		W.card:Hide()
		for _, row in ipairs(W.objectives) do row:Hide() end
		body:SetHeight(h)
		f:SetHeight(T.HEADER_H + T.PROGRESS_H + h)
		return
	end

	place(W.current, body, y)
	y = y + height(W.current) + 6
	W.title:SetText(view.title or "")
	place(W.title, W.current, 6)
	y = y + height(W.title) + 6
	W.text:SetText(view.text or "")
	place(W.text, W.title, 6)
	y = y + height(W.text)
	W.coords:SetText(view.coords or "")
	W.coords:SetShown(view.coords ~= nil)
	place(W.coords, W.text, 6)
	y = y + (view.coords and (height(W.coords) + 6) or 0)

	local anchor = view.coords and W.coords or W.text
	local objs = view.objectives or {}
	for i, row in ipairs(W.objectives) do
		local o = objs[i]
		if o then
			row:Show()
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(i == 1 and 12 or 6))
			row:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
			row.text:SetText((o.optional and not o.done) and ((o.text or "") .. "  (optional)") or (o.text or ""))
			row.count:SetText(o.need and ("%d / %d"):format(o.have or 0, o.need) or "")
			dot(row, o.done, o.info, o.optional)
			y = y + 18 + (i == 1 and 12 or 6)
			anchor = row
		else
			row:Hide()
		end
	end

	y = y + 14
	W.divider:Show()
	W.divider:ClearAllPoints()
	W.divider:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
	W.divider:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
	anchor = W.divider

	local d = view.detour
	if d then
		local card = W.card
		card:Show()
		card:ClearAllPoints()
		card:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
		card:SetPoint("RIGHT", body, "RIGHT", -PAD, 0)
		card.skip:ClearAllPoints()
		card.skip:SetPoint("RIGHT", -6, 0)
		card.go:ClearAllPoints()
		card.go:SetPoint("RIGHT", card.skip, "LEFT", -4, 0)
		card.go:SetHeight(24)
		card.go:SetWidth(48)
		card.go.pwText:SetText(d.aimed and "Stop" or "Go")
		card.label:SetText((d.label or "Optional"):upper())
		card.text:SetText(d.text or "")
		card.sub:SetText(d.sub or "")
		card.label:ClearAllPoints()
		card.label:SetPoint("TOPLEFT", 12, -10)
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
		anchor = card
	else
		W.card:Hide()
	end

	W.thenLabel:SetShown(view.next ~= nil)
	W.thenText:SetShown(view.next ~= nil)
	if view.next then
		place(W.thenLabel, anchor, 14)
		W.thenText:SetText(view.next)
		place(W.thenText, W.thenLabel, 4)
		y = y + 14 + height(W.thenLabel) + 4 + height(W.thenText)
	end

	-- Footer: Back left; Skip, Report, Next right.
	local footY = y + PAD
	W.back:ClearAllPoints()
	W.back:SetPoint("TOPLEFT", body, "TOPLEFT", PAD, -footY)
	W.next:ClearAllPoints()
	W.next:SetPoint("TOPRIGHT", body, "TOPRIGHT", -PAD, -footY)
	W.report:ClearAllPoints()
	W.report:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
	W.skip:ClearAllPoints()
	W.skip:SetPoint("LEFT", W.back, "RIGHT", 8, 0)
	local h = footY + W.next:GetHeight() + PAD
	body:SetHeight(h)
	f:SetHeight(T.HEADER_H + T.PROGRESS_H + h)
	f:SetWidth(width)
end

local function layoutCompact()
	local f, bar = W.frame, W.bar
	W.head:Hide()
	W.body:Hide()
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
	view = v
	Guide.Refresh()
end

function Guide.View() return view end

function Guide.SetCompact(on)
	ns.Set("guide.compact", on and true or nil)
end

function Guide.Show(on)
	if on == nil then on = true end
	if on and not W.frame then build() end
	if not W.frame then return end
	W.frame:SetShown(on)
	if on then Guide.Refresh() end
end

ns.On("TOGGLE_GUIDE", function() ns.Set("guide.shown", not ns.Get("guide.shown")) end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" then Guide.Show(ns.Get("guide.shown"))
	elseif path == "guide.compact" then Guide.Refresh() end
end)
ns.On("READY", function() if ns.Get("guide.shown") then Guide.Show(true) end end)

-- The compact bar shows the arrow's distance when there is one.
ns.On("WAYPOINT_CHANGED", function(target)
	if not target then W.distance = nil Guide.Refresh() end
end)
function Guide.SetDistance(text)
	if W.distance == text then return end
	W.distance = text
	if W.frame and ns.Get("guide.compact") then W.bar.dist:SetText(text or "") end
end
