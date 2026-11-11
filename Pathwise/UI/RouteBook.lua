-- The route book window (PathwiseRouteBook): the leveling routes laid out
-- like the recipe book. Six chapters by level (1-10 ... 50-60), a card per
-- zone route that suits the character, and a page per route with every step,
-- where you can follow the route, start it from any step, and pick the route
-- that comes after it.
--
-- Drag it anywhere (routebook.point). Escape closes it.

local ADDON, ns = ...
local T = ns.Theme
local C = ns.Compat
local Panels = ns.Panels
local floor, max, min = math.floor, math.max, math.min

local Book = {}
ns.RouteBookWindow = Book

Book.W, Book.H = 620, 560

ns.Defaults("routebook", { point = nil })

local PAD = 16
local HEADER_H = 36
local FOOT_H = 46
local CARD_MIN_W, CARD_H, CARD_GAP = 220, 46, 8
local CHAPTER_H = 40

Book.CHAPTERS = { { 1, 10 }, { 10, 20 }, { 20, 30 }, { 30, 40 }, { 40, 50 }, { 50, 60 } }

-- What the book shows: the chapter, and the route whose page is open (nil:
-- the chapter's cards).
local state = { chapter = nil, route = nil }
Book.state = state

local W = {}
Book.frames = W

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

local function edges(f)
	local list = {}
	for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = f:CreateTexture(nil, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
		list[#list + 1] = t
	end
	return list
end

local function paintEdges(list, c, a)
	for _, t in ipairs(list) do paint(t, c, a) end
end

---------------------------------------------------------------------------
-- What is shown
---------------------------------------------------------------------------

local function player() return ns.Quests.Player() end

-- The chapter a level is in.
function Book.ChapterAt(level)
	for i, ch in ipairs(Book.CHAPTERS) do
		if level < ch[2] then return i end
	end
	return #Book.CHAPTERS
end

-- A route's chapter: where the middle of its level range falls.
local function chapterOf(r)
	return Book.ChapterAt(floor(((r.levels[1] or 1) + (r.levels[2] or 60)) / 2))
end

-- The leveling routes for this character in chapter i, by level.
function Book.RoutesIn(i)
	local out = {}
	for _, r in ipairs(ns.Engine.RoutesFor(player(), "Leveling")) do
		if chapterOf(r) == i then out[#out + 1] = r end
	end
	return out
end

-- Where a route stands for this character: "done", "now" (your level),
-- "later" (above it) or "passed" (below it).
function Book.Standing(r)
	local p = ns.Engine.Progress(r)
	if not p.at then return "done", p end
	local level = player().level or 1
	if level < r.levels[1] - 2 then return "later", p end
	if level > r.levels[2] + 1 then return "passed", p end
	return "now", p
end

-- The zones a route works in, by name (its own first).
function Book.Zones(r)
	local count, names = {}, {}
	for _, step in ipairs(r.steps) do
		for _, g in ipairs(step) do
			if g.at then count[g.at[1]] = (count[g.at[1]] or 0) + 1 end
		end
	end
	local maps = {}
	for map, n in pairs(count) do if n >= 6 or map == r.map then maps[#maps + 1] = map end end
	table.sort(maps, function(a, b)
		if (a == r.map) ~= (b == r.map) then return a == r.map end
		return count[a] > count[b]
	end)
	for _, map in ipairs(maps) do names[#names + 1] = C.MapName(map) or ("Map " .. map) end
	return names
end

-- A step in a line: what you do there, whatever your level (only goals for
-- another race or class are left out); "" for a step that is not for you.
function Book.StepText(r, s)
	local E, p = ns.Engine, player()
	local step = r.steps[s]
	if step.only and not E.Fits(step.only, p) then return "", 0 end
	local parts = {}
	for _, g in ipairs(step) do
		if g[1] ~= "note" and not (g.only and not E.Fits(g.only, p)) then
			local t = E.GoalText(g)
			if type(t) == "string" and t ~= "" then parts[#parts + 1] = t end
		end
	end
	return table.concat(parts, ", "), #parts
end

---------------------------------------------------------------------------
-- Pools: the page's widgets are made once and reused
---------------------------------------------------------------------------

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

local function line(y, x, width, text, role, color)
	local fs = pool("text:" .. (role or "body"), function() return T.Text(W.child, role or "body") end)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	fs:SetWidth(width)
	textColor(fs, color or (T.TYPE[role or "body"] or T.TYPE.body)[3])
	fs:SetText(text)
	return y + max(12, fs:GetStringHeight() or 14)
end

-- A clickable row: text left, a hint right; `on` outlines it.
local function row(y, width, text, hint, onClick, on, faded)
	local b = pool("row", function()
		local b = CreateFrame("Button", nil, W.child)
		T.Panel(b, "bg2", false)
		b.ring = edges(b)
		b.label = T.Text(b, "meta", "text")
		b.label:SetPoint("LEFT", 8, 0)
		b.label:SetWordWrap(false)
		b.hint = T.Text(b, "small", "accent")
		b.hint:SetPoint("RIGHT", -8, 0)
		b.hint:SetJustifyH("RIGHT")
		b:SetScript("OnEnter", function(self) paint(self.pwGround, "hover") end)
		b:SetScript("OnLeave", function(self) paint(self.pwGround, self.on and T.Hex("#132332") or "bg2") end)
		return b
	end)
	b.on = on and true or false
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, -y)
	b:SetSize(width, 26)
	b.hint:SetText(hint or "")
	b.label:SetWidth(max(40, width - 24 - (b.hint:GetStringWidth() or 0)))
	b.label:SetText(text)
	paint(b.pwGround, on and T.Hex("#132332") or "bg2")
	paintEdges(b.ring, "accent", on and 1 or 0)
	b:SetAlpha(faded and 0.55 or 1)
	b:SetScript("OnClick", onClick)
	return y + 30
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local draw

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("routebook.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

local function buildChapter(i)
	local f = W.frame
	local b = CreateFrame("Button", nil, f)
	T.Panel(b, "bg2", false)
	b.ring = edges(b)
	b.name = T.Text(b, "meta", "text2")
	b.name:SetPoint("TOP", 0, -6)
	b.name:SetJustifyH("CENTER")
	b.sub = T.Text(b, "small", "muted")
	b.sub:SetPoint("TOP", b.name, "BOTTOM", 0, -3)
	b.sub:SetJustifyH("CENTER")
	b:SetScript("OnClick", function()
		state.chapter, state.route = i, nil
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	W.chapters[i] = b
	return b
end

local function build()
	local f = CreateFrame("Frame", "PathwiseRouteBook", UIParent)
	W.frame = f
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		savePoint(self)
	end)
	T.Panel(f)
	T.TrackGround(f)
	T.TrackScale(f)
	f:SetSize(Book.W, Book.H)
	local saved = ns.Get("routebook.point")
	f:ClearAllPoints()
	if type(saved) == "table" then f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else f:SetPoint("CENTER", UIParent, "CENTER", -200, 60) end

	W.label = T.Text(f, "label", "text2")
	W.label:SetPoint("LEFT", f, "TOPLEFT", PAD, -HEADER_H / 2)
	W.label:SetText("ROUTE BOOK")
	W.close = T.IconButton(f, "close", "Close", function() Book.Close() end)
	W.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
	local hl = T.Divider(f)
	hl:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
	hl:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)

	-- Your route and level, over a line from 1 to 60.
	local y = HEADER_H + 14
	W.title = T.Text(f, "quest", "text")
	W.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.title:SetWidth(Book.W - 2 * PAD - 120)
	W.title:SetWordWrap(false)
	W.level = T.Text(f, "meta", "text2")
	W.level:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 3))
	W.level:SetJustifyH("RIGHT")
	y = y + 26
	W.bar = T.ProgressLine(f)
	W.bar.track:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.bar.track:SetWidth(Book.W - 2 * PAD)
	y = y + 12

	W.chapters = {}
	local n = #Book.CHAPTERS
	local cw = (Book.W - 2 * PAD - (n - 1) * 4) / n
	for i = 1, n do
		local b = buildChapter(i)
		b:SetSize(cw, CHAPTER_H)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (cw + 4), -y)
	end
	y = y + CHAPTER_H + 10

	local scroll = CreateFrame("ScrollFrame", nil, f)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 6, FOOT_H + 6)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(max(0, min(W.range or 0, (self:GetVerticalScroll() or 0) - delta * 40)))
	end)
	W.scroll, W.child = scroll, child
	W.viewH = Book.H - y - FOOT_H - 6
	W.pageW = Book.W - 2 * PAD - 6

	local fl = T.Divider(f)
	fl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, FOOT_H)
	fl:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT_H)
	W.back = T.Button(f, "All routes in this range", "default", function()
		state.route = nil
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	W.back:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, FOOT_H / 2)
	W.next = T.Button(f, ">", "default", function() Book.Turn(1) end)
	W.next:SetWidth(28)
	W.next:SetHeight(26)
	W.next:SetPoint("RIGHT", f, "BOTTOMRIGHT", -PAD - 6, FOOT_H / 2)
	W.prev = T.Button(f, "<", "default", function() Book.Turn(-1) end)
	W.prev:SetWidth(28)
	W.prev:SetHeight(26)
	W.prev:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
	W.page = T.Text(f, "meta", "text2")
	W.page:SetJustifyH("RIGHT")
	W.page:SetPoint("RIGHT", W.prev, "LEFT", -10, 0)

	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PathwiseRouteBook") end
	f:Hide()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawHeader()
	local p, route = player(), ns.Engine.Route()
	W.title:SetText(route and route.title or "No route yet")
	W.level:SetText(("Level %d"):format(p.level or 1))
	W.bar:SetProgress((p.level or 1) / 60)
end

local function drawChapters()
	local here = Book.ChapterAt(player().level or 1)
	for i, b in ipairs(W.chapters) do
		local ch, on = Book.CHAPTERS[i], state.chapter == i
		b.name:SetText(("%d-%d"):format(ch[1], ch[2]))
		local n = #Book.RoutesIn(i)
		b.sub:SetText((here == i and "you  ·  " or "") .. (n == 1 and "1 route" or (n .. " routes")))
		textColor(b.name, on and "text" or "text2")
		textColor(b.sub, here == i and "accent" or "muted")
		paint(b.pwGround, on and T.Hex("#132332") or "bg2")
		paintEdges(b.ring, "accent", on and 1 or 0)
	end
end

local STANDING = {
	now = { "for your level", "accent" }, later = { "from level %d", "muted" },
	passed = { "below your level", "text2" }, done = { "done", "success" },
}

-- A card for a route: its name, levels, how far you are; yours outlined.
local function card(x, y, w, r)
	local b = pool("card", function()
		local b = CreateFrame("Button", nil, W.child)
		T.Panel(b, "bg2", false)
		b.ring = edges(b)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetTexture(T.MEDIA .. "glyph-zones")
		b.icon:SetSize(20, 20)
		b.icon:SetPoint("LEFT", 12, 0)
		b.name = T.Text(b, "body", "text")
		b.name:SetPoint("TOPLEFT", b, "TOPLEFT", 42, -7)
		b.name:SetWordWrap(false)
		b.sub = T.Text(b, "small", "text2")
		b.sub:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -4)
		b.sub:SetWordWrap(false)
		b.here = T.Text(b, "label", "accent")
		b.here:SetPoint("TOPRIGHT", -8, -6)
		b.here:SetText("YOUR ROUTE")
		return b
	end)
	local mine = ns.Engine.Route() == r
	local standing, p = Book.Standing(r)
	local st = STANDING[standing]
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	b:SetSize(w, CARD_H)
	b.name:SetWidth(w - 54 - (mine and 80 or 0))
	b.name:SetText(r.title)
	local bits = { ("%d-%d"):format(r.levels[1], r.levels[2]), st[1]:format(r.levels[1]) }
	if p.done > 0 and p.at then bits[#bits + 1] = ("step %d / %d"):format(p.at, p.count) end
	b.sub:SetText(table.concat(bits, "  ·  "))
	textColor(b.sub, st[2])
	local c = T.Color(mine and "accent" or st[2])
	b.icon:SetVertexColor(c[1], c[2], c[3], 1)
	b.here:SetShown(mine)
	paint(b.pwGround, mine and T.Hex("#132332") or "bg2")
	paintEdges(b.ring, mine and "accent" or "border", mine and 1 or 0)
	b:SetAlpha(standing == "done" and 0.55 or 1)
	b:SetScript("OnClick", function()
		state.route = r.id
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	return b
end

local function drawCards()
	local list = Book.RoutesIn(state.chapter)
	local pw = W.pageW
	if #list == 0 then
		return line(4, 0, pw, "No leveling route for your character in this range yet.", "body", "text2")
	end
	local cols = max(1, floor((pw + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
	local cw = (pw - (cols - 1) * CARD_GAP) / cols
	local y = 0
	for i, r in ipairs(list) do
		local col = (i - 1) % cols
		card(col * (cw + CARD_GAP), y, cw, r)
		if col == cols - 1 or i == #list then y = y + CARD_H + CARD_GAP end
	end
	y = line(y + 6, 0, pw, "Click a route for its steps: follow it, start it from any step, or pick the route after it.", "small", "muted")
	return y
end

-- A route's page: what it is, Follow, every step, and the route after it.
local function drawRoute(r)
	local E, pw = ns.Engine, W.pageW
	local mine = E.Route() == r
	local standing, p = Book.Standing(r)
	local y = line(0, 0, pw, r.title, "quest", "text")
	local zones = Book.Zones(r)
	y = line(y + 2, 0, pw, ("Levels %d-%d  ·  %d steps  ·  %s"):format(r.levels[1], r.levels[2], p.count, table.concat(zones, ", ")), "meta", "text2")
	y = y + 8
	if mine then
		y = row(y, pw, "You are following this route", p.at and ("step " .. p.at) or "done", function() end, true)
	else
		y = row(y, pw, "Follow this route", standing == "later" and ("from level " .. r.levels[1]) or "switch to it", function()
			E.SetRoute(r.id)
			ns.Print(("route: %s."):format(r.title))
			draw()
		end)
	end

	y = line(y + 8, 0, pw, "STEPS  ·  CLICK ONE TO START FROM IT", "label", "text2") + 6
	for s = 1, #r.steps do
		local text, n = Book.StepText(r, s)
		if n > 0 then
			local title = r.steps[s].title
			local label = ("%d.  %s%s"):format(s, title and (title .. ": ") or "", text)
			local done = p.at == nil or s < p.at
			local here = p.at == s
			local hint = here and "you are here" or (done and "done" or "start here")
			y = row(y, pw, label, hint, function()
				E.StartAt(r.id, s)
				ns.Print(("route: %s, from step %d. Settings, Marked done by you, Bring back undoes the steps before it."):format(r.title, s))
				draw()
			end, here and mine, done)
		end
	end

	local choices = E.NextChoices(r)
	if #choices > 0 then
		y = line(y + 10, 0, pw, "THEN  ·  THE ROUTE AFTER THIS ONE", "label", "text2") + 6
		local after = E.NextOf(r)
		for _, n in ipairs(choices) do
			local picked = after == n
			y = row(y, pw, ("%s   %d-%d"):format(n.title, n.levels[1], n.levels[2]),
				picked and "next" or "go here next", function()
					E.SetNext(r.id, n.id ~= r.next and n.id or nil)
					draw()
				end, picked)
		end
	end
	return y
end

function draw()
	if not (W.frame and W.frame:IsShown()) then return end
	if not state.chapter then state.chapter = Book.ChapterAt(player().level or 1) end
	local r = state.route and ns.Engine.routes[state.route]
	if state.route and not r then state.route = nil end
	drawHeader()
	drawChapters()
	releaseAll()
	local h
	if r then
		h = drawRoute(r)
		local list = Book.RoutesIn(state.chapter)
		local at = 0
		for i, x in ipairs(list) do if x == r then at = i end end
		W.page:SetText(at > 0 and ("Route %d / %d"):format(at, #list) or "")
		W.prev:SetEnabled(at > 1)
		W.prev:SetAlpha(at > 1 and 1 or 0.35)
		W.next:SetEnabled(at > 0 and at < #list)
		W.next:SetAlpha(at > 0 and at < #list and 1 or 0.35)
		W.back:Show()
	else
		h = drawCards()
		local ch = Book.CHAPTERS[state.chapter]
		W.page:SetText(("Levels %d-%d"):format(ch[1], ch[2]))
		W.prev:SetEnabled(state.chapter > 1)
		W.prev:SetAlpha(state.chapter > 1 and 1 or 0.35)
		W.next:SetEnabled(state.chapter < #Book.CHAPTERS)
		W.next:SetAlpha(state.chapter < #Book.CHAPTERS and 1 or 0.35)
		W.back:Hide()
	end
	W.child:SetSize(W.pageW, max(1, h))
	W.range = max(0, h - W.viewH)
	W.scroll:SetVerticalScroll(min(W.scroll:GetVerticalScroll() or 0, W.range))
	W.scroll:EnableMouseWheel(W.range > 0)
end
Book.Draw = function() draw() end

---------------------------------------------------------------------------
-- Opening, turning pages, closing
---------------------------------------------------------------------------

-- Opens on your level's chapter (or `chapter`), your route's page closed.
function Book.Open(chapter)
	if not W.frame then build() end
	state.chapter = chapter or Book.ChapterAt(player().level or 1)
	state.route = nil
	W.frame:Show()
	W.scroll:SetVerticalScroll(0)
	draw()
end

-- The arrows: the chapter before or after, or the route on a route's page.
function Book.Turn(delta)
	if state.route then
		local list = Book.RoutesIn(state.chapter)
		for i, r in ipairs(list) do
			if r.id == state.route and list[i + delta] then
				state.route = list[i + delta].id
				break
			end
		end
	else
		state.chapter = max(1, min(#Book.CHAPTERS, (state.chapter or 1) + delta))
	end
	W.scroll:SetVerticalScroll(0)
	draw()
end

function Book.Close() if W.frame then W.frame:Hide() end end
function Book.Shown() return W.frame ~= nil and W.frame:IsShown() end

function Panels.OpenRouteBook(chapter) Book.Open(chapter) end

ns.On("GUIDE_UPDATED", function() if Book.Shown() then draw() end end)
