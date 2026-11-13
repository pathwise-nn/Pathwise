-- The "Tracker" guide style (v2): a compact card, usually at the screen's
-- right edge (frame PathwiseTracker). From the top:
--   header     Pathwise, then hub, compass, collapse and close buttons
--   route      crest, route name, "Alliance · Levels 12-17", "12 / 19", bar
--   step       "STEP 12 OF 19", a card with the place (click: the hub)
--   note       the step's note, if it has one
--   objectives one row each, a checkbox ticked when done, counts on the right
--   detour     the optional profession task (Go, and a cross to skip it)
--   stats      level and its bar, XP per hour, time to the next level, and
--              your own coordinates when that is on (compass.coords)
--   footer     Back, Skip, Report, Next
-- Collapsed (guide.compact): header, route and step card only.
-- Drawn from the guide's view (GUIDE_VIEW); it never reads quests itself.

local ADDON, ns = ...
local T, Guide = ns.Theme, ns.Guide
local floor, max = math.floor, math.max

local Card = {}
ns.TrackerCard = Card

ns.Defaults("card", { point = nil, width = 340, locked = false })

local PAD = 14
local W = {}
Card.frames = W
Card.MAX_ROWS = 6 -- objective rows; the rest as "+N more"
Card.MIN_W, Card.MAX_W = 280, 560

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("card.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

local function height(fs) return fs:IsShown() and max(0, fs:GetStringHeight() or 0) or 0 end

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function rowWidget(i)
	local r = W.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, W.frame)
	r.check = T.Check(r, 16)
	r.check:SetPoint("TOPLEFT", 0, -1)
	r.text = T.Text(r, "body", "text")
	r.text:SetPoint("TOPLEFT", 26, 0)
	r.count = T.Text(r, "small", "text2")
	r.count:SetPoint("TOPRIGHT", 0, -1)
	r.count:SetJustifyH("RIGHT")
	r.text:SetPoint("RIGHT", r.count, "LEFT", -6, 0)
	W.rows[i] = r
	return r
end

local function build()
	local f = CreateFrame("Frame", "PathwiseTracker", UIParent)
	W.frame = f
	f:SetWidth(ns.Get("card.width") or 340)
	f:SetHeight(200)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	T.RoundWindow(f, 12)
	T.TrackScale(f)
	local saved = ns.Get("card.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 40)
	end

	-- Header: drag to move.
	local head = CreateFrame("Frame", nil, f)
	W.head = head
	head:SetPoint("TOPLEFT")
	head:SetPoint("TOPRIGHT")
	head:SetHeight(44)
	head:EnableMouse(true)
	head:RegisterForDrag("LeftButton")
	head:SetScript("OnDragStart", function() if T.Movable("card.locked") then f:StartMoving() end end)
	head:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)
	W.logo = T.Logo(head, 24)
	W.logo:SetPoint("LEFT", PAD - 3, 0)
	W.title = T.Text(head, "window", "text")
	W.title:SetPoint("LEFT", W.logo, "RIGHT", 8, 0)
	W.title:SetText("Pathwise")
	W.close = T.IconButton(head, "close", "Close", function() Guide.Hide() end, 28)
	W.close:SetPoint("RIGHT", -8, 0)
	W.collapse = T.IconButton(head, "collapse", "Collapse", function() Guide.SetCompact(not ns.Get("guide.compact")) end, 28)
	W.collapse:SetPoint("RIGHT", W.close, "LEFT", -2, 0)
	W.compass = T.IconButton(head, "compass", "Compass on or off", function() ns.Set("compass.shown", not ns.Get("compass.shown")) end, 28)
	W.compass:SetPoint("RIGHT", W.collapse, "LEFT", -2, 0)
	W.hub = T.IconButton(head, "grid", "Open the hub", function() ns.Fire("TOGGLE_HUB") end, 28)
	W.hub:SetPoint("RIGHT", W.compass, "LEFT", -2, 0)
	W.pin = T.PinButton(head, "card.locked", 28)
	W.pin:SetPoint("RIGHT", W.hub, "LEFT", -2, 0)
	W.headLine = T.Divider(f)
	W.headLine:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, 0)
	W.headLine:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", 0, 0)

	-- The route.
	W.crest = T.Crest(f, 30)
	W.route = T.TextAt(f, "semibold", 15, "text")
	W.route:SetWordWrap(false)
	W.routeLine = T.Text(f, "meta", "text2")
	W.routeLine:SetWordWrap(false)
	W.counter = T.TextAt(f, "semibold", 14, "accent")
	W.counter:SetJustifyH("RIGHT")
	W.bar = T.Bar(f, 5)

	-- The step.
	W.stepLabel = T.Text(f, "label", "accent")
	local step = CreateFrame("Button", nil, f)
	W.step = step
	do
		local a = T.Color("accent")
		T.Round(step, { a[1], a[2], a[3], 0.08 }, "accent", 8)
	end
	step:SetScript("OnClick", function() ns.Fire("TOGGLE_HUB", true) end)
	step:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			ns.Tip.SetText(GameTooltip, "Open the hub", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	step:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	step.pin = T.Glyph(step, "glyph-goto", 18, "accent")
	step.pin:SetPoint("LEFT", 12, 0)
	step.chev = T.Glyph(step, "glyph-chevron", 16, "accent")
	step.chev:SetPoint("RIGHT", -10, 0)
	step.title = T.TextAt(step, "semibold", 15, "text")
	step.title:SetPoint("TOPLEFT", 40, -11)
	step.title:SetPoint("RIGHT", step.chev, "LEFT", -8, 0)
	step.sub = T.Text(step, "meta", "text2")
	step.sub:SetPoint("TOPLEFT", step.title, "BOTTOMLEFT", 0, -3)
	step.sub:SetPoint("RIGHT", step.chev, "LEFT", -8, 0)
	step.sub:SetWordWrap(false)

	W.note = T.Text(f, "meta", "text2")
	W.rows = {}

	-- The optional profession task.
	local card = CreateFrame("Frame", nil, f)
	W.card = card
	do
		local a = T.Color("accent")
		T.Round(card, { a[1], a[2], a[3], 0.05 }, { a[1], a[2], a[3], 0.4 }, 8)
	end
	card.star = T.Glyph(card, "glyph-star", 18, "accent")
	card.star:SetPoint("TOPLEFT", 12, -12)
	card.skip = T.IconButton(card, "close", "Skip this detour", function() ns.Fire("DETOUR_SKIP", Guide.View() and Guide.View().detour) end, 22)
	card.skip:SetPoint("TOPRIGHT", -6, -6)
	card.go = T.RoundButton(card, "Go", "outline", function() ns.Fire("DETOUR_GO", Guide.View() and Guide.View().detour) end, 26)
	card.go:SetPoint("RIGHT", card.skip, "LEFT", -4, 0)
	card.label = T.Text(card, "label", "accent")
	card.label:SetPoint("TOPLEFT", 40, -10)
	card.label:SetPoint("RIGHT", card.go, "LEFT", -8, 0)
	card.label:SetWordWrap(false)
	card.text = T.Text(card, "body", "text")
	card.text:SetPoint("TOPLEFT", card.label, "BOTTOMLEFT", 0, -4)
	card.text:SetPoint("RIGHT", card, "RIGHT", -12, 0)
	card.sub = T.Text(card, "small", "text2")
	card.sub:SetPoint("TOPLEFT", card.text, "BOTTOMLEFT", 0, -2)
	card.sub:SetPoint("RIGHT", card, "RIGHT", -12, 0)

	-- Stats.
	W.level = T.Text(f, "meta", "text")
	W.levelBar = T.Bar(f, 4, "success")
	W.rate = T.Text(f, "meta", "text2")
	W.rate:SetJustifyH("RIGHT")
	W.rate:SetWordWrap(false)
	W.coords = T.Text(f, "small", "muted")
	W.coords:SetWordWrap(false)

	-- Footer.
	W.footLine = T.Divider(f)
	W.back = T.RoundButton(f, "Back", "default", function() ns.Fire("GUIDE_BACK") end, 32)
	W.skip = T.RoundButton(f, "Skip", "default", function() ns.Fire("GUIDE_SKIP") end, 32)
	W.report = T.IconButton(f, "flag", "Report this step", function() ns.Fire("REPORT_STEP", Guide.View()) end, 32)
	W.next = T.RoundButton(f, "Next", "primary", function() ns.Fire("GUIDE_NEXT") end, 32)

	W.empty = T.Text(f, "meta", "text2")

	-- The corner grip: as wide as you like; the height fits the step.
	W.grip = T.Grip(f, {
		minW = Card.MIN_W, maxW = Card.MAX_W, lockPath = "card.locked",
		onSize = function() Card.Refresh() end,
		onDone = function(w) ns.Set("card.width", w) savePoint(f) end,
		onReset = function() ns.Set("card.width", nil) end,
	})
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

-- The rows a view's step card makes: its action lines (Engine's lines),
-- notes left out (the note is shown above the rows).
function Card.Rows(v)
	local out = {}
	for _, line in ipairs(v and v.card or {}) do
		if line.kind ~= "note" then out[#out + 1] = line end
	end
	return out
end

-- "Lv 14", the bar's fraction, "9.5k XP/h  ·  18m to 15"
function Card.Stats()
	local K = ns.Tracker
	if not (K and ns.Get("tracker.shown")) then return nil end
	local s = K.Stats()
	local lvl = K.Level()
	local bits = {}
	if s.xpPerHour then bits[#bits + 1] = (s.xpPerHour >= 1000 and (ns.L("%.1fk")):format(s.xpPerHour / 1000) or tostring(floor(s.xpPerHour))) .. ns.L(" XP/h") end
	if s.secondsToLevel then bits[#bits + 1] = (ns.L("%s to %d")):format(K.Duration(s.secondsToLevel), lvl + 1) end
	return (ns.L("Lv %d")):format(lvl), s.percent or 0, table.concat(bits, "  ·  ")
end

local function place(widget, y, left, right)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", W.frame, "TOPLEFT", left or PAD, -y)
	widget:SetPoint("RIGHT", W.frame, "RIGHT", -(right or PAD), 0)
end

function Card.Refresh()
	local f = W.frame
	if not f then return end
	local v = Guide.View()
	local width = f:GetWidth()
	local collapsed = ns.Get("guide.compact") and true or false
	W.collapse:SetGlyph(collapsed and "expand" or "collapse")
	local cc = T.Color(ns.Get("compass.shown") and "accent" or "text2")
	W.compass.pwIcon:SetVertexColor(cc[1], cc[2], cc[3], 1)
	local y = 44 + 14

	-- Route.
	W.crest:ClearAllPoints()
	W.crest:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.crest:SetFaction(v and v.faction)
	W.counter:ClearAllPoints()
	W.counter:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 2))
	W.counter:SetText(v and v.count and ("%d " .. T.Esc("text2") .. "/ %d|r"):format(v.index or 0, v.count) or "")
	W.route:ClearAllPoints()
	W.route:SetPoint("TOPLEFT", W.crest, "TOPRIGHT", 10, 0)
	W.route:SetPoint("RIGHT", W.counter, "LEFT", -8, 0)
	W.route:SetText(v and v.route or "Pathwise")
	W.routeLine:ClearAllPoints()
	W.routeLine:SetPoint("TOPLEFT", W.route, "BOTTOMLEFT", 0, -3)
	W.routeLine:SetPoint("RIGHT", W.counter, "LEFT", -8, 0)
	W.routeLine:SetText(Guide.RouteLine(v))
	y = y + 34 + 8
	place(W.bar, y)
	W.bar:SetProgress(v and v.progress or 0, width - 2 * PAD)
	y = y + 5 + 14

	local has = v ~= nil
	for _, w in ipairs({ W.stepLabel, W.step, W.back, W.skip, W.report, W.next, W.footLine }) do w:SetShown(has) end
	W.empty:SetShown(not has)
	if has then for _, b in ipairs({ W.back, W.skip, W.next }) do T.Relabel(b) end end
	if not has then
		place(W.empty, y)
		W.empty:SetText("No route for this character yet. Open the hub to pick one.")
		for _, r in ipairs(W.rows) do r:Hide() end
		for _, w in ipairs({ W.note, W.card, W.level, W.levelBar, W.rate, W.coords }) do w:Hide() end
		f:SetHeight(y + height(W.empty) + PAD)
		return
	end

	-- Step.
	place(W.stepLabel, y)
	W.stepLabel:SetText(v.index and v.count and ns.U((ns.L("Step %d of %d")):format(v.index, v.count)) or (v.extra and "EXTRA QUEST" or "NOW"))
	y = y + max(12, height(W.stepLabel)) + 8
	local step = W.step
	place(step, y)
	step.title:SetText(v.title or "")
	local where = Guide.PlaceLine(v)
	step.sub:SetText(where)
	step.sub:SetShown(where ~= "")
	local sh = 11 + max(18, height(step.title)) + (where ~= "" and (3 + height(step.sub)) or 0) + 11
	step:SetHeight(sh)
	y = y + sh + 10

	-- Note, objectives, detour, stats: not when collapsed.
	local note = not collapsed and v.text and v.text ~= "" and v.text ~= v.title
	W.note:SetShown(note and true or false)
	if note then
		place(W.note, y)
		W.note:SetText(v.text)
		if W.note.SetMaxLines then W.note:SetMaxLines(3) end
		y = y + height(W.note) + 10
	end

	local rows = collapsed and {} or Card.Rows(v)
	if #rows > Card.MAX_ROWS then
		local cut = {}
		for k = 1, Card.MAX_ROWS - 1 do cut[k] = rows[k] end
		cut[#cut + 1] = { kind = "note", lead = (ns.L("+%d more in the hub")):format(#rows - (Card.MAX_ROWS - 1)), info = true }
		rows = cut
	end
	for i, line in ipairs(rows) do
		local r = rowWidget(i)
		r:Show()
		place(r, y, PAD + 2)
		r.check:SetShown(not line.info)
		r.check:SetChecked(line.done)
		r.text:SetText(Guide.LineText(line))
		T.TextColor(r.text, line.done and "muted" or ((line.info or line.optional) and "text2" or "text"))
		r.count:SetText(line.need and ("%d/%d"):format(line.have or 0, line.need) or "")
		local h = max(18, height(r.text))
		r:SetHeight(h)
		y = y + h + 8
	end
	for i = #rows + 1, #W.rows do W.rows[i]:Hide() end
	if #rows > 0 then y = y + 4 end

	local d = not collapsed and v.detour
	W.card:SetShown(d and true or false)
	if d then
		local card = W.card
		place(card, y)
		card.label:SetText(ns.U(ns.L(d.label or "Optional")))
		card.text:SetText(d.text or "")
		card.sub:SetText(d.sub or "")
		card.go.pwText:SetText(d.aimed and "Stop" or "Go")
		local ch = 10 + height(card.label) + 4 + height(card.text) + 2 + height(card.sub) + 12
		card:SetHeight(ch)
		y = y + ch + 12
	end

	local lvl, frac, rate = Card.Stats()
	local stats = not collapsed and lvl ~= nil
	for _, w in ipairs({ W.level, W.levelBar, W.rate }) do w:SetShown(stats) end
	if stats then
		W.level:ClearAllPoints()
		W.level:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
		W.level:SetText(lvl)
		W.rate:ClearAllPoints()
		W.rate:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
		W.rate:SetText(rate)
		local rw = (W.rate:GetStringWidth() or 0)
		local lw = (W.level:GetStringWidth() or 30)
		W.levelBar:ClearAllPoints()
		W.levelBar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + lw + 10, -(y + 5))
		local bw = max(20, width - 2 * PAD - lw - 10 - (rw > 0 and rw + 12 or 0))
		W.levelBar:SetWidth(bw)
		W.levelBar:SetProgress(frac, bw)
		y = y + 16 + 8
	end
	local xy = not collapsed and ns.Coords and ns.Coords.Text()
	W.coords:SetShown(xy and true or false)
	if xy then
		place(W.coords, y)
		W.coords:SetText(ns.L("You  ") .. xy)
		y = y + height(W.coords) + 8
	end

	-- Footer.
	place(W.footLine, y + 2, 0, 0)
	W.footLine:SetHeight(1)
	y = y + 12
	W.back:ClearAllPoints()
	W.back:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.skip:ClearAllPoints()
	W.skip:SetPoint("LEFT", W.back, "RIGHT", 8, 0)
	W.next:ClearAllPoints()
	W.next:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -y)
	W.report:ClearAllPoints()
	W.report:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
	f:SetHeight(y + 32 + PAD)
end

---------------------------------------------------------------------------
-- Showing
---------------------------------------------------------------------------

function Card.Show()
	local on = Guide.StyleShown("tracker")
	if on and not W.frame then build() end
	if not W.frame then return end
	W.frame:SetShown(on)
	if on then Card.Refresh() end
end

function Card.Shown() return W.frame ~= nil and W.frame:IsShown() end

local function refreshIfShown() if Card.Shown() then Card.Refresh() end end

ns.On("READY", Card.Show)
ns.On("HUB_TOGGLED", Card.Show)
ns.On("GUIDE_VIEW", refreshIfShown)
ns.On("TRACKER_UPDATED", refreshIfShown)
-- Your coordinates change often: only their text, unless they come or go.
ns.On("PLAYER_COORDS", function()
	if not Card.Shown() then return end
	local xy = not ns.Get("guide.compact") and ns.Coords and ns.Coords.Text()
	if (xy ~= nil) ~= (W.coords:IsShown() and true or false) then Card.Refresh()
	elseif xy then W.coords:SetText(ns.L("You  ") .. xy) end
end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" or path == "guide.style" then Card.Show()
	elseif path == "guide.compact" or path == "compass.shown" or path == "compass.coords" or path == "tracker.shown" then refreshIfShown()
	elseif path == "card.width" and W.frame and not W.grip.pwState.held then
		W.frame:SetWidth(math.min(Card.MAX_W, math.max(Card.MIN_W, ns.Get("card.width") or 340)))
		refreshIfShown()
	end
end)
