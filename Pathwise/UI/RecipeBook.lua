-- The recipe book window (PathwiseRecipeBook), laid out like the game's
-- spellbook in Pathwise's own look: a tab per profession along the top, the
-- four ranks as chapters, a card per skill range, and a page per card with
-- what to make, the materials, the colours and where the recipes are.
-- The plan itself is Professions/RecipeBook.lua.
--
-- Drag it anywhere (recipebook.point) and resize it from any edge or corner,
-- or the grip in the bottom-right corner (recipebook.size). Escape closes it.

local ADDON, ns = ...
local T = ns.Theme
local C = ns.Compat
local Panels = ns.Panels
local floor, max, min = math.floor, math.max, math.min

local Book = {}
ns.RecipeBookWindow = Book

Book.W, Book.H = 620, 560 -- the size it opens at
Book.MIN_W, Book.MAX_W = 340, 900
Book.MIN_H, Book.MAX_H = 320, 820

ns.Defaults("recipebook", { point = nil, size = nil })

local PAD = 16
local HEADER_H = 36
local FOOT_H = 46
local TAB_GAP, SEP_W = 5, 9
local CARD_MIN_W, CARD_H, CARD_GAP = 220, 46, 8
local CHAPTER_H = 40

-- The profession tabs' icons: the game's own (Interface\Icons), the ones
-- the 1.x spellbook shows.
local ICONS = {
	alchemy = "Trade_Alchemy",
	blacksmithing = "Trade_BlackSmithing",
	enchanting = "Trade_Engraving",
	engineering = "Trade_Engineering",
	leatherworking = "INV_Misc_ArmorKit_17",
	tailoring = "Trade_Tailoring",
	herbalism = "Spell_Nature_NatureTouchGrow",
	mining = "Trade_Mining",
	skinning = "INV_Misc_Pelt_Wolf_01",
	cooking = "INV_Misc_Food_15",
	["first-aid"] = "Spell_Holy_SealOfSacrifice",
	fishing = "Trade_Fishing",
}
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function Book.ProfessionIcon(key) return ICONS[key] and ("Interface\\Icons\\" .. ICONS[key]) or QUESTION end

-- The game's difficulty colours.
local DIFF = {
	red = T.Hex("#E66B78"), orange = T.Hex("#FF8040"), yellow = T.Hex("#FFFF00"),
	green = T.Hex("#40BF40"), grey = T.Hex("#808080"),
}
local COLOR_WORD = { red = "can't learn yet", orange = "orange", yellow = "yellow", green = "green", grey = "grey" }

-- What the book shows: the profession, the way (path), the chapter and the
-- step whose page is open (nil: the chapter's cards).
local state = { key = nil, path = nil, chapter = nil, step = nil }
Book.state = state

local W = {} -- the window's frames
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

-- Four 1 px edges around a frame; returns them to recolour.
local function edges(f, layer)
	-- A rounded 1 px border (v2), recoloured like the old four lines.
	return T.RoundEdges(f, 8, layer)
end

local function paintEdges(list, c, a)
	for _, t in ipairs(list) do paint(t, c, a) end
end

-- An icon square with a thin dark rim, like the game's own icons.
local function iconFrame(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size, size)
	local rim = holder:CreateTexture(nil, "BACKGROUND")
	rim:SetAllPoints()
	rim:SetColorTexture(0, 0, 0, 1)
	local tex = holder:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	holder.tex = tex
	return holder
end

local function upper(s) return (s or ""):upper() end

---------------------------------------------------------------------------
-- The plan for what is shown
---------------------------------------------------------------------------

local function profession() return ns.Professions.BY_KEY[state.key] end
local function book() return state.key and ns.RecipeBook.Book(state.key) or nil end

local function skill()
	local prof = profession()
	if not prof then return nil end
	return C.SkillRank(prof.line)
end

-- The four chapters: { rank, lo, hi, r } from the book's ranks.
function Book.Chapters(b)
	local out, lo = {}, 0
	for _, r in ipairs(b.ranks) do
		out[#out + 1] = { rank = r.rank, lo = lo, hi = r.cap, r = r }
		lo = r.cap
	end
	return out
end

-- The chapter a skill is in.
function Book.ChapterAt(chapters, rank)
	rank = rank or 0
	for i, ch in ipairs(chapters) do if rank < ch.hi then return i end end
	return #chapters
end

-- The steps (indexes into `steps`) whose range starts in a chapter.
function Book.InChapter(steps, ch)
	local out = {}
	for i, s in ipairs(steps) do
		if s.from >= ch.lo and s.from < ch.hi then out[#out + 1] = i end
	end
	return out
end

local function steps(b) return ns.RecipeBook.Steps(b, state.path, ns.RecipeBook.Side()) end

-- A step's name for its card, its icon and its first craft (or nil).
function Book.StepFace(step, side)
	local RB = ns.RecipeBook
	local first, more = nil, 0
	for _, e in ipairs(RB.Entries(step, side)) do
		if e.kind ~= "alt" then
			if first then more = more + 1 else first = e end
		end
	end
	if first then
		return first.spell.name, C.ItemIcon(first.spell.made) or C.SpellIcon(first.spell.id), first, more
	end
	if step.nodes and step.nodes[1] then
		local names = {}
		for _, n in ipairs(step.nodes) do names[#names + 1] = RB.ItemName(n) end
		return table.concat(names, ", "), C.ItemIcon(step.nodes[1]), nil, 0
	end
	if step.mobs and step.mobs[1] then
		local n = RB.Npc(step.mobs[1])
		return n and n.name or "Skinning", nil, nil, 0
	end
	return ("%d-%d"):format(step.from, step.to), nil, nil, 0
end

-- The arrow to an NPC; prints where it leads.
local function arrowTo(id, what)
	local p = ns.RecipeBook.Place(id)
	if not p then return ns.Print(("no position for %s in the data."):format(what or "them")) end
	ns.Nav.SetTarget(p.map, p.x, p.y, p.name)
	ns.Print(("the arrow leads to %s%s."):format(p.name, p.zone and (" in " .. p.zone) or ""))
end
Book.ArrowTo = arrowTo

---------------------------------------------------------------------------
-- Pools: the page's widgets are made once and reused on every draw
---------------------------------------------------------------------------

local pools = {}
local function pool(kind, make)
	local p = pools[kind]
	if not p then p = { list = {}, used = 0, make = make } pools[kind] = p end
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

local function newText(role, color)
	return pool("text:" .. role, function()
		local fs = T.Text(W.child, role, color)
		return fs
	end)
end

-- A line of text in the page at y; returns the y below it.
local function line(y, x, width, text, role, color)
	local fs = newText(role or "body")
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	fs:SetWidth(width)
	textColor(fs, color or (T.TYPE[role or "body"] or T.TYPE.body)[3])
	fs:SetText(text)
	return y + max(12, fs:GetStringHeight() or 14)
end

-- A clickable row with a ground: text left, a hint right.
local function linkRow(y, x, width, text, hint, onClick)
	local b = pool("link", function()
		local b = CreateFrame("Button", nil, W.child)
		T.Panel(b, "bg2", false)
		b.label = T.Text(b, "meta", "text")
		b.label:SetPoint("LEFT", 8, 0)
		b.hint = T.Text(b, "small", "accent")
		b.hint:SetPoint("RIGHT", -8, 0)
		b.hint:SetJustifyH("RIGHT")
		b:SetScript("OnEnter", function(self) paint(self.pwGround, "hover") end)
		b:SetScript("OnLeave", function(self) paint(self.pwGround, "bg2") end)
		return b
	end)
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	b:SetSize(width, 26)
	b.hint:SetText(hint or "")
	b.label:SetWidth(max(40, width - 24 - (b.hint:GetStringWidth() or 0)))
	b.label:SetWordWrap(false)
	b.label:SetText(text)
	b:SetScript("OnClick", onClick)
	return y + 30
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

local layout, draw

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("recipebook.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

local function clampW(w) return min(Book.MAX_W, max(Book.MIN_W, w)) end
local function clampH(h) return min(Book.MAX_H, max(Book.MIN_H, h)) end

-- A tab: the profession's icon; yours in full colour, the others faded.
local function buildTab(i, prof)
	local b = CreateFrame("Button", nil, W.frame)
	b.prof, b.hover = prof, false
	b.icon = iconFrame(b, 34)
	b.icon:SetAllPoints()
	b.icon.tex:SetTexture(Book.ProfessionIcon(prof.key))
	b.ring = edges(b, "OVERLAY")
	b.under = b:CreateTexture(nil, "OVERLAY")
	b.under:SetHeight(2)
	b.under:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -6)
	b.under:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -6)
	paint(b.under, "accent")
	b:SetScript("OnClick", function() Book.Open(prof.key) end)
	b:SetScript("OnEnter", function(self)
		self.hover = true
		Book.PaintTabs()
		if GameTooltip then
			local rank, cap = C.SkillRank(prof.line)
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(prof.name, 1, 1, 1)
			GameTooltip:AddLine(rank and ("%d / %d"):format(rank, cap or 0) or "Not learned", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.hover = false
		Book.PaintTabs()
		if GameTooltip then GameTooltip:Hide() end
	end)
	W.tabs[i] = b
end

function Book.PaintTabs()
	for _, b in ipairs(W.tabs or {}) do
		local on = b.prof.key == state.key
		local known = C.SkillRank(b.prof.line) ~= nil
		local lit = on or known or b.hover
		b.icon.tex:SetDesaturated(not lit)
		b.icon:SetAlpha(lit and 1 or 0.55)
		if on then paintEdges(b.ring, "accent") else paintEdges(b.ring, b.hover and "text2" or "border", b.hover and 1 or 0) end
		b.under:SetShown(on)
	end
end

-- A chapter button: the rank's name and its range.
local function buildChapter(i)
	local b = CreateFrame("Button", nil, W.frame)
	T.Panel(b, "bg2", false)
	b.ring = edges(b)
	b.name = T.Text(b, "meta", "text2")
	b.name:SetPoint("TOPLEFT", 8, -5)
	b.name:SetPoint("TOPRIGHT", -6, -5)
	b.name:SetWordWrap(false)
	b.range = T.Text(b, "small", "muted")
	b.range:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
	b.range:SetPoint("TOPRIGHT", b.name, "BOTTOMRIGHT", 0, -2)
	b.range:SetWordWrap(false)
	b:SetScript("OnClick", function()
		state.chapter, state.step = i, nil
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	b:SetScript("OnEnter", function(self) if state.chapter ~= i or state.step then paint(self.pwGround, "hover") end end)
	b:SetScript("OnLeave", function() draw() end)
	W.chapters[i] = b
end

-- The way through (main, or another path such as Strange Dust): a segment.
local function buildWay(i)
	local b = CreateFrame("Button", nil, W.frame)
	T.Panel(b, "bg2", false)
	b.pwText = T.Text(b, "button", "text2")
	b.pwText:SetPoint("CENTER")
	b:SetHeight(24)
	W.ways[i] = b
	return b
end

-- The resize handles: four edges and four corners, and the grip.
local SIDES = {
	-- name, points, horizontal (-1 left, 1 right), vertical (1 top, -1 bottom)
	{ "TOP", { "TOPLEFT", 12, 0 }, { "TOPRIGHT", -12, -5 }, 0, 1 },
	{ "BOTTOM", { "BOTTOMLEFT", 12, 5 }, { "BOTTOMRIGHT", -12, 0 }, 0, -1 },
	{ "LEFT", { "TOPLEFT", 0, -12 }, { "BOTTOMLEFT", 5, 12 }, -1, 0 },
	{ "RIGHT", { "TOPRIGHT", -5, -12 }, { "BOTTOMRIGHT", 0, 12 }, 1, 0 },
	{ "TOPLEFT", { "TOPLEFT", 0, 0 }, { "TOPLEFT", 12, -12 }, -1, 1 },
	{ "TOPRIGHT", { "TOPRIGHT", -12, 0 }, { "TOPRIGHT", 0, -12 }, 1, 1 },
	{ "BOTTOMLEFT", { "BOTTOMLEFT", 0, 12 }, { "BOTTOMLEFT", 12, 0 }, -1, -1 },
}

-- The drag under way: the handle, where it started and the window then.
local drag = {}

local function cursorAt(f)
	local x, y = GetCursorPosition()
	local s = f:GetEffectiveScale() or 1
	return x / s, y / s
end

-- The window's rectangle for the cursor now: the dragged sides follow it,
-- within the size bounds; the other sides stay put.
function Book.SizeFor(h, v, start, dx, dy)
	local l, t, w, hh = start.l, start.t, start.w, start.h
	local r, b = l + w, t - hh
	if h == 1 then w = clampW(w + dx) elseif h == -1 then w = clampW(w - dx) l = r - w end
	if v == -1 then hh = clampH(hh - dy) elseif v == 1 then hh = clampH(hh + dy) t = b + hh end
	return floor(l + 0.5), floor(t + 0.5), floor(w + 0.5), floor(hh + 0.5)
end

local function sizeUpdate(handle)
	local f = W.frame
	local x, y = cursorAt(f)
	local l, t, w, h = Book.SizeFor(handle.h, handle.v, drag.start, x - drag.x, y - drag.y)
	if w == drag.w and h == drag.h and l == drag.l and t == drag.t then return end
	drag.l, drag.t, drag.w, drag.h = l, t, w, h
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	f:SetSize(w, h)
	layout()
	draw()
end

local function paintHandle(handle)
	if handle.icon then
		local c = T.Color(handle.pressed and "accent" or (handle.over and "text" or "muted"))
		handle.icon:SetVertexColor(c[1], c[2], c[3], 1)
	elseif handle.glow then
		handle.glow:SetShown(handle.pressed or handle.over)
	end
end

local function sizeStart(handle, button)
	if button and button ~= "LeftButton" then return end
	local f = W.frame
	local l, t = f:GetLeft(), f:GetTop()
	if not (l and t) then return end
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
	drag.x, drag.y = cursorAt(f)
	drag.start = { l = l, t = t, w = f:GetWidth(), h = f:GetHeight() }
	drag.l, drag.t, drag.w, drag.h = nil, nil, nil, nil
	handle.pressed = true
	paintHandle(handle)
	if GameTooltip then GameTooltip:Hide() end
	handle:SetScript("OnUpdate", sizeUpdate)
end

local function sizeStop(handle, button)
	if button == "RightButton" and handle.icon and not handle:GetScript("OnUpdate") then
		-- Right-click on the grip: the size it opens at.
		ns.Set("recipebook.size", nil)
		W.frame:SetSize(Book.W, Book.H)
		layout()
		draw()
		return
	end
	handle.pressed = false
	paintHandle(handle)
	if not handle:GetScript("OnUpdate") then return end
	handle:SetScript("OnUpdate", nil)
	local f = W.frame
	ns.Set("recipebook.size", { floor(f:GetWidth() + 0.5), floor(f:GetHeight() + 0.5) })
	savePoint(f)
end

local function hookHandle(handle)
	handle:SetScript("OnMouseDown", sizeStart)
	handle:SetScript("OnMouseUp", sizeStop)
	handle:SetScript("OnHide", sizeStop)
	handle:SetScript("OnLeave", function(self)
		self.over = false
		paintHandle(self)
		if GameTooltip then GameTooltip:Hide() end
	end)
end

local function buildHandles(f)
	f:SetResizable(true)
	if f.SetResizeBounds then f:SetResizeBounds(Book.MIN_W, Book.MIN_H, Book.MAX_W, Book.MAX_H) end
	W.handles = {}
	for _, s in ipairs(SIDES) do
		local hnd = CreateFrame("Frame", nil, f)
		hnd:EnableMouse(true)
		hnd:SetPoint(s[2][1], f, s[2][1], s[2][2], s[2][3])
		hnd:SetPoint(s[3][1], f, s[3][1], s[3][2], s[3][3])
		hnd:SetFrameLevel((f:GetFrameLevel() or 0) + 20)
		hnd.side, hnd.h, hnd.v = s[1], s[4], s[5]
		hnd.icon, hnd.over, hnd.pressed = false, false, false
		hnd.glow = hnd:CreateTexture(nil, "OVERLAY")
		hnd.glow:SetAllPoints()
		paint(hnd.glow, "accent", 0.25)
		hnd.glow:Hide()
		hookHandle(hnd)
		hnd:SetScript("OnEnter", function(self) self.over = true paintHandle(self) end)
		W.handles[s[1]] = hnd
	end
	-- The grip: the bottom-right corner, drawn like the guide window's.
	local g = CreateFrame("Button", nil, f)
	g:SetSize(14, 14)
	g:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
	g:SetFrameLevel((f:GetFrameLevel() or 0) + 21)
	g.side, g.h, g.v = "BOTTOMRIGHT", 1, -1
	g.over, g.pressed = false, false
	g.icon = g:CreateTexture(nil, "OVERLAY")
	g.icon:SetTexture(T.MEDIA .. "glyph-resize")
	g.icon:SetSize(12, 12)
	g.icon:SetPoint("BOTTOMRIGHT", 0, 0)
	hookHandle(g)
	g:SetScript("OnEnter", function(self)
		self.over = true
		paintHandle(self)
		if GameTooltip and not self:GetScript("OnUpdate") then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText("Resize", 1, 1, 1)
			GameTooltip:AddLine("Drag any edge or corner to change the size.", nil, nil, nil, true)
			GameTooltip:AddLine("Right-click: back to the size it opens at.", nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	paintHandle(g)
	W.grip = g
	W.handles.BOTTOMRIGHT = g
end

local function build()
	local f = CreateFrame("Frame", "PathwiseRecipeBook", UIParent)
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

	local size = ns.Get("recipebook.size")
	if type(size) == "table" then f:SetSize(clampW(size[1] or Book.W), clampH(size[2] or Book.H))
	else f:SetSize(Book.W, Book.H) end
	local saved = ns.Get("recipebook.point")
	f:ClearAllPoints()
	if type(saved) == "table" then f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else f:SetPoint("CENTER", UIParent, "CENTER", -200, 60) end

	-- Header.
	W.label = T.Text(f, "label", "text2")
	W.label:SetPoint("LEFT", f, "TOPLEFT", PAD, -HEADER_H / 2)
	W.label:SetText("RECIPE BOOK")
	W.label:SetWordWrap(false)
	W.close = T.IconButton(f, "close", "Close", function() Book.Close() end)
	W.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -7)
	W.headerLine = T.Divider(f)
	W.headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
	W.headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)

	-- Tabs, in three groups: crafts, gathering, the secondary skills.
	W.tabs = {}
	for i, prof in ipairs(ns.Professions.LIST) do buildTab(i, prof) end
	W.seps = { T.Divider(f), T.Divider(f) }
	W.tabLine = T.Divider(f)

	-- The profession's name, your skill and a line for it.
	W.title = T.Text(f, "quest", "text")
	W.title:SetWordWrap(false)
	W.skill = T.Text(f, "meta", "text2")
	W.skill:SetJustifyH("RIGHT")
	W.bar = T.ProgressLine(f)
	W.ticks = {}
	for i = 1, 3 do
		local t = f:CreateTexture(nil, "ARTWORK", nil, 2)
		t:SetSize(1, 6)
		paint(t, "border")
		W.ticks[i] = t
	end

	W.chapters = {}
	for i = 1, 4 do buildChapter(i) end

	-- The strip for a rank to train, or a profession to learn.
	local s = CreateFrame("Button", nil, f)
	T.Panel(s, T.Hex("#E4B96D", 0.08), false)
	s.bar = s:CreateTexture(nil, "ARTWORK")
	s.bar:SetPoint("TOPLEFT")
	s.bar:SetPoint("BOTTOMLEFT")
	s.bar:SetWidth(2)
	paint(s.bar, "warning")
	s.text = T.Text(s, "meta", "warning")
	s.text:SetPoint("TOPLEFT", 10, -6)
	s.text:SetWordWrap(false)
	s.sub = T.Text(s, "small", "text2")
	s.sub:SetPoint("TOPLEFT", s.text, "BOTTOMLEFT", 0, -2)
	s.sub:SetWordWrap(false)
	s.go = T.Text(s, "small", "accent")
	s.go:SetPoint("RIGHT", -10, 0)
	s.go:SetJustifyH("RIGHT")
	s:SetScript("OnEnter", function(self) paint(self.pwGround, T.Hex("#E4B96D", 0.16)) end)
	s:SetScript("OnLeave", function(self) paint(self.pwGround, T.Hex("#E4B96D", 0.08)) end)
	W.train = s

	-- The page: a scroll area with a thin thumb.
	local scroll = CreateFrame("ScrollFrame", nil, f)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local v = max(0, min(W.range or 0, (self:GetVerticalScroll() or 0) - delta * 40))
		self:SetVerticalScroll(v)
		Book.PaintThumb()
	end)
	W.scroll, W.child = scroll, child
	W.thumb = f:CreateTexture(nil, "OVERLAY")
	W.thumb:SetWidth(2)
	paint(W.thumb, "border")

	-- Footer: the ways, the page and the arrows.
	W.footLine = T.Divider(f)
	W.footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, FOOT_H)
	W.footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT_H)
	W.ways = {}
	W.wayLabel = T.Text(f, "meta", "text2")
	W.wayLabel:SetText("Way")
	W.wayLabel:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, FOOT_H / 2)
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

	buildHandles(f)
	f:SetScript("OnSizeChanged", function() if f:IsShown() then layout() end end)
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PathwiseRecipeBook") end
	f:Hide()
end

---------------------------------------------------------------------------
-- Layout: where the fixed parts go for the window's size
---------------------------------------------------------------------------

local function tabSize(width)
	local n = #W.tabs
	return max(18, min(34, floor((width - 2 * PAD - 2 * SEP_W - (n - 1) * TAB_GAP) / n)))
end

function layout()
	local f = W.frame
	local fw = f:GetWidth() or Book.W
	local y = HEADER_H + 12
	local s = tabSize(fw)
	W.tabSize = s
	local x = PAD
	for i, b in ipairs(W.tabs) do
		b:ClearAllPoints()
		b:SetSize(s, s)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", x, -y)
		x = x + s + TAB_GAP
		if i == 6 or i == 9 then
			local sep = W.seps[i == 6 and 1 or 2]
			sep:ClearAllPoints()
			sep:SetSize(1, floor(s * 0.65))
			sep:SetPoint("TOPLEFT", f, "TOPLEFT", x + 4 - TAB_GAP, -(y + floor(s * 0.18)))
			x = x + SEP_W
		end
	end
	y = y + s + 8
	W.tabLine:ClearAllPoints()
	W.tabLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	W.tabLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)

	y = y + 14
	W.title:ClearAllPoints()
	W.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.title:SetWidth(fw - 2 * PAD - 110)
	W.skill:ClearAllPoints()
	W.skill:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(y + 3))
	y = y + 26
	local bw = fw - 2 * PAD
	W.bar.track:ClearAllPoints()
	W.bar.track:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -y)
	W.bar.track:SetWidth(bw)
	for i, t in ipairs(W.ticks) do
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + floor(bw * i / 4), -(y - 2))
	end
	y = y + 12

	local cw = (bw - 3 * 4) / 4
	for i, b in ipairs(W.chapters) do
		b:ClearAllPoints()
		b:SetSize(cw, CHAPTER_H)
		b:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + (i - 1) * (cw + 4), -y)
	end
	y = y + CHAPTER_H + 10
	W.trainY = y
	W.width = fw
end

-- The page area starts below the strip when there is one.
local function placeScroll(top)
	local f = W.frame
	W.scroll:ClearAllPoints()
	W.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
	W.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 6, FOOT_H + 6)
	W.viewH = max(0, (f:GetHeight() or Book.H) - top - FOOT_H - 6)
	W.pageW = (f:GetWidth() or Book.W) - 2 * PAD - 6
	W.pageTop = top
end

function Book.PaintThumb()
	local range, viewH = W.range or 0, W.viewH or 0
	if range <= 0 or viewH <= 0 then W.thumb:Hide() return end
	local h = max(20, viewH * viewH / (viewH + range))
	local at = (W.scroll:GetVerticalScroll() or 0) / range
	W.thumb:ClearAllPoints()
	W.thumb:SetHeight(h)
	W.thumb:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -5, -(W.pageTop + (viewH - h) * at))
	W.thumb:Show()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local function drawHeader(prof, rank, cap)
	W.title:SetText(prof.name)
	W.skill:SetText(rank and ("%d / %d"):format(rank, cap or 0) or "Not learned")
	W.bar:SetProgress((rank or 0) / 300)
end

local function drawChapters(chapters, rank)
	local here = rank and Book.ChapterAt(chapters, rank)
	for i, b in ipairs(W.chapters) do
		local ch = chapters[i]
		b:SetShown(ch ~= nil)
		if ch then
			local on = state.chapter == i
			local done = rank and rank >= ch.hi
			b.name:SetText(ch.rank)
			local range = ("%d-%d"):format(max(1, ch.lo), ch.hi)
			if done then range = range .. "  ·  done" elseif here == i then range = range .. "  ·  you" end
			b.range:SetText(range)
			textColor(b.name, on and "text" or (done and "success" or "text2"))
			textColor(b.range, here == i and "accent" or "muted")
			paint(b.pwGround, on and "selected" or "bg2")
			paintEdges(b.ring, "accent", on and 1 or 0)
		end
	end
end

-- The strip over the page: the rank this chapter needs, or the profession
-- to learn. Returns its height (0 when none).
local function drawTrain(b, ch, rank, cap)
	local s, RB = W.train, ns.RecipeBook
	local side = RB.Side()
	local r, text, sub, who
	if not rank and ch.r == b.ranks[1] then
		r = b.ranks[1]
		text = ("You don't have %s. Learn it from a trainer."):format(profession().name)
	elseif rank and ch.r.cap > (cap or 0) and ch.r.rank ~= "Apprentice" then
		r = ch.r
		text = "Train " .. RB.RankText(r)
	end
	if not r then s:Hide() return 0 end
	for _, p in ipairs(RB.People(r, side)) do
		if p.id then who = p break end
		who = who or p
	end
	if r.book then sub = "From the book " .. RB.ItemName(r.book) .. (who and (", sold by " .. who.name) or "")
	elseif r.quest then sub = "From the quest " .. r.quest .. (who and (", given by " .. who.name) or "")
	elseif who then
		local zone
		for map in pairs(who.npc and who.npc.spawns or {}) do zone = C.MapName(map) break end
		sub = who.name .. (zone and (", " .. zone) or "")
	else sub = r.note or "" end
	s:ClearAllPoints()
	s:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD, -W.trainY)
	s:SetSize((W.width or Book.W) - 2 * PAD, 38)
	s.text:SetText(text)
	s.sub:SetText(sub or "")
	s.go:SetText(who and who.id and "click for the arrow" or "")
	s.text:SetWidth(s:GetWidth() - 130)
	s.sub:SetWidth(s:GetWidth() - 130)
	s:SetScript("OnClick", function() if who and who.id then arrowTo(who.id, who.name) end end)
	s:Show()
	return 38 + 10
end

-- A card for a step: its icon, name, range and count; your step outlined.
local function card(x, y, w, i, step, rank, side)
	local b = pool("card", function()
		local b = CreateFrame("Button", nil, W.child)
		T.Panel(b, "bg2", false)
		b.ring = edges(b)
		b.icon = iconFrame(b, 34)
		b.icon:SetPoint("LEFT", 6, 0)
		b.name = T.Text(b, "body", "text")
		b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -2)
		b.name:SetWordWrap(false)
		b.dot = b:CreateTexture(nil, "ARTWORK")
		b.dot:SetTexture(T.MEDIA .. "pin-disc")
		b.dot:SetSize(8, 8)
		b.dot:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -5)
		b.sub = T.Text(b, "small", "text2")
		b.sub:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
		b.sub:SetWordWrap(false)
		b.here = T.Text(b, "label", "accent")
		b.here:SetPoint("TOPRIGHT", -8, -5)
		b.here:SetText("YOU ARE HERE")
		b.here:SetWordWrap(false)
		b:SetScript("OnEnter", function(self) if not self.now then paint(self.pwGround, "bg2", 1) paintEdges(self.ring, "border") end end)
		b:SetScript("OnLeave", function(self) if not self.now then paint(self.pwGround, "bg2", 0) paintEdges(self.ring, "border", 0) end end)
		return b
	end)
	local name, icon, first, more = Book.StepFace(step, side)
	local done = rank and rank >= step.to
	local now = rank and rank >= step.from and rank < step.to
	b.now = now and true or false
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	b:SetSize(w, CARD_H)
	b.icon.tex:SetTexture(icon or Book.ProfessionIcon(state.key))
	b.name:SetWidth(w - 60 - (now and 80 or 0))
	b.name:SetText(name)
	local bits = { ("%d-%d"):format(step.from, step.to) }
	if first and first.count then bits[#bits + 1] = first.count .. "x" end
	if more > 0 then bits[#bits + 1] = ("+%d more"):format(more) end
	if done then bits[#bits + 1] = "done" end
	b.sub:SetText(table.concat(bits, "  ·  "))
	local col = first and rank and ns.RecipeBook.Color(first.spell, rank)
	if col then b.dot:SetVertexColor(DIFF[col][1], DIFF[col][2], DIFF[col][3], 1) b.dot:Show()
	else b.dot:SetVertexColor(0, 0, 0, 0) end
	b.here:SetShown(now and true or false)
	paint(b.pwGround, now and "selected" or "bg2", now and 1 or 0)
	paintEdges(b.ring, now and "accent" or "border", now and 1 or 0)
	b:SetAlpha(done and 0.55 or 1)
	b:SetScript("OnClick", function()
		state.step = i
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	return b
end

-- The chapter's page: its cards in as many columns as fit, then the notes.
local function drawCards(b, list, ch, rank)
	local RB, side = ns.RecipeBook, ns.RecipeBook.Side()
	local pw = W.pageW
	local cols = max(1, floor((pw + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
	local cw = (pw - (cols - 1) * CARD_GAP) / cols
	local idx = Book.InChapter(list, ch)
	local y = 0
	for n, i in ipairs(idx) do
		local col = (n - 1) % cols
		local row = floor((n - 1) / cols)
		card(col * (cw + CARD_GAP), row * (CARD_H + CARD_GAP), cw, i, list[i], rank, side)
		y = (row + 1) * (CARD_H + CARD_GAP)
	end
	if #idx == 0 then y = line(y, 0, pw, "No steps start in this rank.", "meta", "text2") end
	y = y + 8

	-- The late recipes the guide lists, on the last chapter.
	if ch.r == b.ranks[#b.ranks] and b.extra then
		y = line(y + 4, 0, pw, "OTHER RECIPES", "label", "text2") + 4
		y = line(y, 0, pw, "Drops, reputation and vendor recipes the guide lists for the late ranges.", "small", "muted") + 4
		for _, id in ipairs(b.extra) do
			local sp = RB.Spell(id)
			if sp then
				y = line(y, 0, pw, sp.name, "body", "text")
				local srcs = RB.Sources(sp, side)
				local where = srcs[1] and RB.SourceText(srcs[1]) or nil
				y = line(y, 0, pw, RB.ReagentText(sp) .. "  ·  " .. RB.ColorText(sp) .. (where and ("  ·  " .. where) or ""), "small", "muted") + 6
			end
		end
	end
	if b.tools or b.bonuses then
		y = line(y + 4, 0, pw, "TOOLS AND BONUSES", "label", "text2") + 4
		if b.tools then
			local bits = {}
			for _, it in ipairs(b.tools) do bits[#bits + 1] = RB.ItemName(it) end
			y = line(y, 0, pw, "Carry: " .. table.concat(bits, ", "), "meta", "text2")
		end
		for _, x in ipairs(b.bonuses or {}) do
			local name = x.name or (x.item and RB.ItemName(x.item)) or "?"
			y = line(y, 0, pw, name .. (x.amount and ("  ·  +%d"):format(x.amount) or "") .. (x.note and ("  ·  " .. x.note) or ""), "meta", "text2")
		end
		y = y + 6
	end
	for _, n in ipairs(b.notes or {}) do y = line(y, 0, pw, n, "small", "muted") + 2 end
	local src = "From wow-professions.com's Forever guide, written on the beta"
	if b.untestedFrom then src = src .. (", not tested there from %d"):format(b.untestedFrom) end
	y = line(y + 2, 0, pw, src .. ". Recipes, colours and materials: the Forever client's own data; green is an estimate.", "small", "muted")
	return y
end

-- The bar from learnable to grey, with your skill on it.
local function diffBar(y, x, w, spell, rank)
	if not (spell.yellow and spell.grey) then return y end
	local bar = pool("diff", function()
		local f = CreateFrame("Frame", nil, W.child)
		f.parts = {}
		for i = 1, 4 do f.parts[i] = f:CreateTexture(nil, "ARTWORK") end
		f.me = f:CreateTexture(nil, "OVERLAY")
		f.me:SetSize(2, 12)
		f.me:SetColorTexture(1, 1, 1, 1)
		f.ticks = {}
		for i = 1, 3 do
			f.ticks[i] = T.Text(f, "small", "muted")
			f.ticks[i]:SetWordWrap(false)
		end
		return f
	end)
	local lo = spell.learn or max(1, spell.yellow - 25)
	local Y, G = spell.yellow, spell.grey
	local M = floor((Y + G) / 2)
	local hi = G + 10
	local function at(v) return floor((v - lo) / (hi - lo) * w + 0.5) end
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	bar:SetSize(w, 24)
	local stops = { { lo, Y, "orange" }, { Y, M, "yellow" }, { M, G, "green" }, { G, hi, "grey" } }
	for i, s in ipairs(stops) do
		local t = bar.parts[i]
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", bar, "TOPLEFT", at(s[1]), -2)
		t:SetSize(max(1, at(s[2]) - at(s[1])), 5)
		paint(t, DIFF[s[3]])
	end
	for i, v in ipairs({ lo, Y, G }) do
		local fs = bar.ticks[i]
		fs:ClearAllPoints()
		fs:SetPoint("TOP", bar, "TOPLEFT", at(v), -10)
		fs:SetText(tostring(v))
	end
	bar.me:ClearAllPoints()
	if rank and rank >= lo and rank <= hi then
		bar.me:SetPoint("TOP", bar, "TOPLEFT", at(rank), 2)
		bar.me:Show()
	else
		bar.me:Hide()
	end
	return y + 26
end

-- A step's page: each craft with its icon, materials, colours and recipe
-- sources; for gathering, the nodes, zones and mobs.
local function drawStep(list, i, ch, rank)
	local RB, side = ns.RecipeBook, ns.RecipeBook.Side()
	local step = list[i]
	local pw = W.pageW
	local y = 0

	local back = pool("crumb", function()
		local b = CreateFrame("Button", nil, W.child)
		b.text = T.Text(b, "meta", "accent")
		b.text:SetPoint("LEFT")
		return b
	end)
	back:ClearAllPoints()
	back:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, 0)
	back.text:SetText("< " .. ch.rank)
	back:SetSize((back.text:GetStringWidth() or 60) + 8, 18)
	back:SetScript("OnClick", function()
		state.step = nil
		W.scroll:SetVerticalScroll(0)
		draw()
	end)
	y = 24
	local top = y
	y = line(y, 0, pw - 120, ("%d-%d"):format(step.from, step.to), "quest", "text")
	if rank and rank >= step.from and rank < step.to then line(top + 4, pw - 120, 120, "You are here", "meta", "accent") end
	y = y + 8

	local ix, iw = 46, pw - 46
	local anyShown
	local entries = RB.Entries(step, side)
	for _, e in ipairs(entries) do
		local lead = e.kind == "alt" and "OR INSTEAD" or (e.kind == "any" and (anyShown and "OR" or "ONE OF") or "MAKE")
		if e.kind == "any" then anyShown = true end
		local ic = pool("icon", function() return iconFrame(W.child, 36) end)
		ic:ClearAllPoints()
		ic:SetPoint("TOPLEFT", W.child, "TOPLEFT", 0, -(y + 2))
		ic.tex:SetTexture(C.ItemIcon(e.spell.made) or C.SpellIcon(e.spell.id) or QUESTION)
		local start = y
		y = line(y, ix, iw, lead, "label", "muted") + 2
		y = line(y, ix, iw, RB.EntryText(e), "body", e.kind == "alt" and "text2" or "text")
		local col = rank and RB.Color(e.spell, rank)
		local status = RB.ColorText(e.spell)
		if col then status = "now " .. COLOR_WORD[col] .. "  ·  " .. status end
		y = line(y + 1, ix, iw, status, "small", col and DIFF[col] or "muted")
		y = line(y + 1, ix, iw, RB.ReagentText(e.spell), "meta", "text2")
		y = diffBar(y + 6, ix, min(iw, 360), e.spell, rank)
		for _, src in ipairs(RB.Sources(e.spell, side)) do
			local first = src.vendors[1] or src.drops[1]
			if first then
				y = linkRow(y, ix, iw, src.name .. ": " .. RB.SourceText(src), "arrow", function() arrowTo(first.id, first.name) end)
			else
				y = line(y, ix, iw, ("%s: %s"):format(src.name, RB.SourceText(src)), "meta", "text2") + 4
			end
		end
		y = max(y, start + 40) + 12
	end

	local mats = RB.Materials(entries)
	if #mats > 0 then
		local bits = {}
		for _, m in ipairs(mats) do bits[#bits + 1] = ("%d %s"):format(m.count, m.name) end
		y = line(y, 0, pw, "In all: " .. table.concat(bits, ", "), "meta", "text2") + 6
	end
	if step.nodes then
		local bits = {}
		for _, n in ipairs(step.nodes) do bits[#bits + 1] = RB.ItemName(n) end
		y = line(y, 0, pw, "GATHER", "label", "muted") + 2
		y = line(y, 0, pw, table.concat(bits, ", "), "body", "text") + 4
	end
	if step.zones then
		local zones = {}
		for _, k in ipairs({ side or "A", "AH" }) do
			for _, map in ipairs(step.zones[k] or {}) do zones[#zones + 1] = RB.ZoneName(map) end
		end
		if #zones > 0 then y = line(y, 0, pw, "Where: " .. table.concat(zones, ", "), "meta", "text2") + 6 end
	end
	if step.mobs then
		for _, id in ipairs(step.mobs) do
			local n = RB.Npc(id)
			local lv = ns.Data.npcs[id]
			if n and lv then
				y = linkRow(y, 0, pw, ("%s  ·  level %d-%d"):format(n.name, lv[2], lv[3]), "arrow to the nearest", function() arrowTo(id, n.name) end)
			end
		end
	end
	if step.keep then y = line(y + 2, 0, pw, step.keep, "meta", "accent") end
	return y
end

local function drawFooter(b, label, canBack, canOn)
	local paths = ns.RecipeBook.Paths(b)
	for _, w in ipairs(W.ways) do w:Hide() end
	W.wayLabel:SetShown(#paths > 0)
	if #paths > 0 then
		local opts = { "Main" }
		for _, p in ipairs(paths) do opts[#opts + 1] = p end
		local prev = W.wayLabel
		for i, name in ipairs(opts) do
			local w = W.ways[i] or buildWay(i)
			local on = (state.path or "Main") == name
			w.pwText:SetText(name)
			w:SetWidth((w.pwText:GetStringWidth() or 40) + 18)
			w:ClearAllPoints()
			w:SetPoint("LEFT", prev, "RIGHT", i == 1 and 8 or 3, 0)
			paint(w.pwGround, on and "accent" or "bg2")
			textColor(w.pwText, on and "bg" or "text2")
			w:SetScript("OnClick", function()
				state.path = name ~= "Main" and name or nil
				state.step = nil
				draw()
			end)
			w:Show()
			prev = w
		end
	end
	W.page:SetText(label)
	W.prev:SetEnabled(canBack)
	W.prev:SetAlpha(canBack and 1 or 0.35)
	W.next:SetEnabled(canOn)
	W.next:SetAlpha(canOn and 1 or 0.35)
end

function draw()
	if not (W.frame and W.frame:IsShown()) then return end
	local prof, b = profession(), book()
	if not (prof and b) then return end
	local rank, cap = skill()
	local chapters = Book.Chapters(b)
	if not state.chapter then state.chapter = Book.ChapterAt(chapters, rank) end
	state.chapter = max(1, min(#chapters, state.chapter))
	local ch = chapters[state.chapter]
	local list = steps(b)
	if state.step and not list[state.step] then state.step = nil end

	Book.PaintTabs()
	drawHeader(prof, rank, cap)
	drawChapters(chapters, rank)
	local stripH = state.step and 0 or drawTrain(b, ch, rank, cap)
	if state.step then W.train:Hide() end
	placeScroll(W.trainY + stripH)

	releaseAll()
	local h
	if state.step then
		h = drawStep(list, state.step, ch, rank)
		drawFooter(b, ("Step %d / %d"):format(state.step, #list), state.step > 1, state.step < #list)
	else
		h = drawCards(b, list, ch, rank)
		drawFooter(b, ("Page %d / %d"):format(state.chapter, #chapters), state.chapter > 1, state.chapter < #chapters)
	end
	W.child:SetSize(W.pageW, max(1, h))
	W.range = max(0, h - W.viewH)
	W.scroll:SetVerticalScroll(min(W.scroll:GetVerticalScroll() or 0, W.range))
	W.scroll:EnableMouseWheel(W.range > 0)
	Book.PaintThumb()
end
Book.Draw = function() draw() end

---------------------------------------------------------------------------
-- Opening, turning pages, closing
---------------------------------------------------------------------------

-- The profession to open on: the one asked for, the one last open, else
-- the first you have.
local function pick(key)
	if key and ns.RecipeBook.Book(key) then return key end
	if state.key then return state.key end
	for _, prof in ipairs(ns.Professions.LIST) do
		if C.SkillRank(prof.line) and ns.RecipeBook.Book(prof.key) then return prof.key end
	end
	return ns.Professions.LIST[1].key
end

function Book.Open(key)
	key = pick(key)
	if state.key ~= key then state.key, state.path, state.chapter, state.step = key, nil, nil, nil end
	if not W.frame then build() end
	W.frame:Show()
	layout()
	W.scroll:SetVerticalScroll(0)
	draw()
end

-- The arrows: the chapter before or after, or the step on a step's page.
function Book.Turn(delta)
	local b = book()
	if not b then return end
	if state.step then
		local list = steps(b)
		local i = state.step + delta
		if not list[i] then return end
		state.step = i
		state.chapter = Book.ChapterAt(Book.Chapters(b), list[i].from)
	else
		local n = #Book.Chapters(b)
		state.chapter = max(1, min(n, (state.chapter or 1) + delta))
	end
	W.scroll:SetVerticalScroll(0)
	draw()
end

function Book.Close()
	if W.frame then W.frame:Hide() end
end

function Book.Shown() return W.frame ~= nil and W.frame:IsShown() end

-- The names the rest of the addon calls.
function Panels.OpenRecipeBook(key) Book.Open(key) end
function Panels.RefreshRecipeBook() draw() end
function Panels.CloseRecipeBook() Book.Close() end
function Panels.RecipeBookShown() return Book.Shown() end
