-- Pathwise Loot's window, laid out like Pathwise's recipe book: a tab per
-- boss along the top (the icon of its best drop), the boss's name, a button
-- per kind of item (all, armor, weapons, jewelry, other), a card per item in
-- as many columns as fit, and a footer with "Show" (everything, or only what
-- your class can use) and the arrows to the boss before or after.
--
-- "All instances" opens the contents: a card per dungeon or raid (Dungeons,
-- Raids, Your wishlist along the top). The search box looks through every
-- boss's loot.
--
-- An item card: the item's icon and name in its quality color, a dot in that
-- color with its slot and levels, a corner note (an upgrade from Pathwise
-- Gear, or how often you have seen it drop) and a diamond for the wishlist.
-- Upgrades are outlined. Hover: the game's item tooltip. Shift-click /
-- Ctrl-click: the game's own modified click. Right-click or the diamond:
-- wishlist.
--
--   B.Show() / B.Hide() / B.Toggle() / B.Frame() / B.IsShown()
--   B.SelectInstance(map) / B.SelectBoss(id) / B.Contents(group) / B.Wishlist() / B.Search(text)
--   B.State() -> { mode = "boss" | "contents" | "wishlist" | "search", map, boss, group, text }
--   B.Rows() -> the item cards shown: { { item, encounter, entry, where }, ... }

local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local L = ns.Loot
local B = {}
ns.LootBrowser = B

local floor, max, min = math.floor, math.max, math.min
local readable = ns.Readable

local W_, H_ = 680, 600
local PAD, HEADER_H, FOOT_H = 16, 36, 46
local TAB_GAP = 5
local CARD_MIN_W, CARD_H, CARD_GAP = 230, 46, 8
local CHAPTER_H = 40
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local CHOSEN = { 0x13 / 255, 0x23 / 255, 0x32 / 255, 1 } -- the recipe book's chosen-card ground

local state = { mode = "boss" }
local shown = {} -- the item cards' data, for B.Rows()
local W = {} -- the window's frames
local draw

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

local function divider(parent)
	local t = parent:CreateTexture(nil, "BORDER")
	t:SetHeight(1)
	T.Paint(t, "divider")
	return t
end

-- Four 1 px edges around a frame; returns them to recolour.
local function edges(f, layer)
	local out = {}
	for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = f:CreateTexture(nil, layer or "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
		out[#out + 1] = t
	end
	return out
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

-- A flat toggle, like the recipe book's "Way" choices: accent when chosen.
local function segment(parent, label, onClick)
	local b = CreateFrame("Button", nil, parent)
	T.Panel(b, "bg2", false)
	b.pwText = T.Text(b, "button", "text2")
	b.pwText:SetPoint("CENTER")
	b.pwText:SetJustifyH("CENTER")
	b.pwText:SetJustifyV("MIDDLE")
	b.pwText:SetText(label)
	b:SetHeight(24)
	b:SetWidth((b.pwText:GetStringWidth() or 40) + 18)
	b:SetScript("OnClick", onClick)
	function b:SetOn(on)
		self.pwOn = on
		paint(self.pwGround, on and "accent" or "bg2")
		textColor(self.pwText, on and "bg" or "text2")
	end
	b:SetScript("OnEnter", function(self) if not self.pwOn then textColor(self.pwText, "text") end end)
	b:SetScript("OnLeave", function(self) if not self.pwOn then textColor(self.pwText, "text2") end end)
	return b
end

local function qualityColor(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.r then return { c.r, c.g, c.b, 1 } end
	return T.Color("text")
end

local function levelsText(inst)
	if not inst.levels then return nil end
	if inst.levels[1] == inst.levels[2] then return ("%d"):format(inst.levels[1]) end
	return ("%d-%d"):format(inst.levels[1], inst.levels[2])
end

local function myLevel()
	local ok, lv = pcall(UnitLevel, "player")
	lv = ok and readable(lv) or nil
	return type(lv) == "number" and lv or nil
end

local function hereMap()
	if not GetInstanceInfo then return nil end
	local ok, _, _, _, _, _, _, _, map = pcall(GetInstanceInfo)
	return ok and readable(map) or nil
end

-- Two bosses of one instance with different sizes: name the size.
local function bossLabel(inst, eid, e)
	local players = L.Players(eid)
	if players and players > 0 and inst then
		for _, other in ipairs(inst.encounters) do
			if other ~= eid and L.Players(other) ~= players then return ("%s (%d)"):format(e.name, players) end
		end
	end
	return e.name
end

-- A boss's face: the icon of its best drop (quality, then item level).
local function bossIcon(e)
	local best, bq, bl
	for _, entry in ipairs(e and e.loot or {}) do
		local it = L.Item(entry.id, true)
		local q, lv = it.quality or 0, it.itemLevel or 0
		if not best or q > bq or (q == bq and lv > bl) then best, bq, bl = it, q, lv end
	end
	return best and best.icon or nil
end

---------------------------------------------------------------------------
-- What is shown
---------------------------------------------------------------------------

-- The kinds of item, as the buttons under the boss's name.
B.KINDS = L.SLOT_FILTERS
local GROUPS = { { "Dungeons", "dungeon" }, { "Raids", "raid" }, { "Your wishlist", "wishlist" } }

local function passesClass(it) return not ns.Get("loot.usable") or L.Usable(it) end

local function whereOf(eid)
	local e = eid and L.Encounter(eid)
	if not e then return nil end
	local inst = e.map and L.Instance(e.map)
	return inst and (e.name .. ", " .. inst.name) or e.name
end

-- The item cards for the current view, before the kind filter: { d, ... }
local function allItems()
	local out = {}
	if state.mode == "boss" and state.boss then
		local e = L.Encounter(state.boss)
		for _, entry in ipairs(e and e.loot or {}) do
			out[#out + 1] = { item = entry.id, encounter = state.boss, entry = entry }
		end
	elseif state.mode == "wishlist" then
		for _, w in ipairs(L.Wishlist()) do out[#out + 1] = { item = w.item, encounter = w.encounter, where = whereOf(w.encounter) } end
	elseif state.mode == "search" then
		for _, s in ipairs(L.Search(state.text)) do out[#out + 1] = { item = s.item, encounter = s.encounter, where = whereOf(s.encounter) } end
	end
	return out
end

local function itemRows()
	local out, before = {}, allItems()
	local kind = ns.Get("loot.slot")
	for _, d in ipairs(before) do
		local it = L.Item(d.item)
		if passesClass(it) and L.SlotMatches(it, kind) then out[#out + 1] = d end
	end
	return out, #before
end

local function instancesOf(group)
	local out = {}
	for _, inst in ipairs(L.Instances()) do
		if (group == "raid") == (inst.raid and true or false) then out[#out + 1] = inst end
	end
	return out
end

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

-- A line of text in the page at y; returns the y below it.
local function line(y, x, width, text, role, color)
	local fs = pool("text:" .. (role or "body"), function() return T.Text(W.child, role or "body") end)
	fs:ClearAllPoints()
	fs:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	fs:SetWidth(width)
	textColor(fs, color or (T.TYPE[role or "body"] or T.TYPE.body)[3])
	fs:SetText(text)
	return y + max(12, fs:GetStringHeight() or 14)
end

-- A card's frame: ground, ring, icon, name, dot, line and a corner note.
local function newCard()
	local b = CreateFrame("Button", nil, W.child)
	T.Panel(b, "bg2", false)
	b.ring = edges(b)
	b.icon = iconFrame(b, 34)
	b.icon:SetPoint("LEFT", 6, 0)
	b.name = T.Text(b, "body", "text")
	b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 10, -2)
	b.name:SetWordWrap(false)
	b.dot = b:CreateTexture(nil, "ARTWORK")
	b.dot:SetTexture(T.MEDIA .. "disc")
	b.dot:SetSize(8, 8)
	b.dot:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -5)
	b.sub = T.Text(b, "small", "text2")
	b.sub:SetPoint("LEFT", b.dot, "RIGHT", 5, 0)
	b.sub:SetWordWrap(false)
	b.corner = T.Text(b, "label", "accent")
	b.corner:SetPoint("TOPRIGHT", -8, -5)
	b.corner:SetJustifyH("RIGHT")
	b.corner:SetWordWrap(false)
	return b
end

local function cardLook(b, chosen)
	b.pwChosen = chosen
	paint(b.pwGround, chosen and CHOSEN or "bg2", chosen and 1 or 0)
	paintEdges(b.ring, chosen and "accent" or "border", chosen and 1 or 0)
end
local function cardHover(b, on)
	if b.pwChosen then return end
	paint(b.pwGround, "bg2", on and 1 or 0)
	paintEdges(b.ring, "border", on and 1 or 0)
end

-- An item's card.
local function itemCard(x, y, w, d)
	local b = pool("item", function()
		local b = newCard()
		b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		b.corner:SetPoint("TOPRIGHT", -30, -5)
		-- The wishlist mark: its own button, so hovering it never repaints it.
		b.star = CreateFrame("Button", nil, b)
		b.star:SetSize(22, 22)
		b.star:SetPoint("RIGHT", -6, 0)
		b.star.pwIcon = b.star:CreateTexture(nil, "ARTWORK")
		b.star.pwIcon:SetTexture(T.MEDIA .. "glyph-diamond")
		b.star.pwIcon:SetSize(14, 14)
		b.star.pwIcon:SetPoint("CENTER")
		b.star:SetScript("OnEnter", function(self)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_TOP")
				GameTooltip:SetText(self:GetParent().pwWished and "On your wishlist: click to take it off" or "Add to your wishlist", 1, 1, 1)
				GameTooltip:Show()
			end
		end)
		b.star:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		b:SetScript("OnEnter", function(self)
			cardHover(self, true)
			if GameTooltip and self.pwLink then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				pcall(GameTooltip.SetHyperlink, GameTooltip, self.pwLink)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function(self)
			cardHover(self, false)
			if GameTooltip then GameTooltip:Hide() end
		end)
		b:SetScript("OnClick", function(self, button)
			if button == "RightButton" then
				L.Wish(self.pwItem, nil, self.pwEncounter)
				return
			end
			local modified = IsModifiedClick and readable(IsModifiedClick())
			if modified and HandleModifiedItemClick and self.pwLink then pcall(HandleModifiedItemClick, self.pwLink) end
		end)
		return b
	end)
	local it = L.Item(d.item)
	b.pwItem, b.pwEncounter, b.pwLink = d.item, d.encounter, it.link
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	b:SetSize(w, CARD_H)
	b.icon.tex:SetTexture(it.icon or QUESTION)

	local up, pct = L.Upgrade(it)
	local corner = ""
	if up then corner = pct and ("|cff7FD98FUPGRADE +%.1f%%|r"):format(pct) or "|cff7FD98FUPGRADE|r"
	elseif d.entry and d.entry.seen then corner = ("SEEN %d"):format(d.entry.seen) end
	b.corner:SetText(corner)
	local cw = corner ~= "" and ((b.corner:GetStringWidth() or 0) + 8) or 0

	b.name:SetWidth(max(40, w - 80 - cw))
	b.name:SetText(it.name)
	textColor(b.name, qualityColor(it.quality))
	local c = qualityColor(it.quality)
	b.dot:SetVertexColor(c[1], c[2], c[3], 1)

	local bits = {}
	if it.slot then bits[#bits + 1] = it.slot end
	if it.itemLevel and it.itemLevel > 0 then bits[#bits + 1] = ("item level %d"):format(it.itemLevel) end
	if it.level and it.level > 0 then bits[#bits + 1] = ("level %d"):format(it.level) end
	if d.where then bits[#bits + 1] = d.where end
	local usable = L.Usable(it)
	if not usable then bits[#bits + 1] = "not for your class" end
	b.sub:SetWidth(max(40, w - 80))
	b.sub:SetText(table.concat(bits, "  ·  "))

	local wished = L.Wished(d.item)
	local sc = wished and T.Color("accent") or T.Color("muted")
	b.star.pwIcon:SetVertexColor(sc[1], sc[2], sc[3], wished and 1 or 0.6)
	b.star:SetScript("OnClick", function() L.Wish(d.item, nil, d.encounter) end)
	b.pwWished = wished

	cardLook(b, up and true or false)
	b:SetAlpha(usable and 1 or 0.55)
	return b
end

-- An instance's card in the contents.
local function instanceCard(x, y, w, inst, here, level)
	local b = pool("instance", function()
		local b = newCard()
		b:SetScript("OnEnter", function(self) cardHover(self, true) end)
		b:SetScript("OnLeave", function(self) cardHover(self, false) end)
		return b
	end)
	b.pwMap = inst.map
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", W.child, "TOPLEFT", x, -y)
	b:SetSize(w, CARD_H)
	local icon
	for _, eid in ipairs(inst.encounters) do
		icon = bossIcon(L.Encounter(eid))
		if icon then break end
	end
	b.icon.tex:SetTexture(icon or QUESTION)
	local isHere = here ~= nil and here == inst.map
	b.corner:SetText(isHere and "YOU ARE HERE" or "")
	b.name:SetWidth(max(40, w - 60 - (isHere and 84 or 0)))
	b.name:SetText(inst.name)
	textColor(b.name, "text")

	local bits = {}
	local lv = levelsText(inst)
	local mine = level and inst.levels and level >= inst.levels[1] and level <= inst.levels[2]
	if lv then bits[#bits + 1] = "level " .. lv end
	if inst.raid and inst.size and inst.size > 0 then bits[#bits + 1] = ("%d players"):format(inst.size) end
	bits[#bits + 1] = ("%d boss%s"):format(#inst.encounters, #inst.encounters == 1 and "" or "es")
	if mine then bits[#bits + 1] = "you" end
	b.sub:SetWidth(max(40, w - 60))
	b.sub:SetText(table.concat(bits, "  ·  "))
	local dc = mine and T.Color("accent") or T.Color("muted")
	b.dot:SetVertexColor(dc[1], dc[2], dc[3], 1)
	b:SetScript("OnClick", function() B.SelectInstance(inst.map) end)
	cardLook(b, isHere)
	b:SetAlpha(level and inst.levels and level < inst.levels[1] - 5 and 0.7 or 1)
	return b
end

---------------------------------------------------------------------------
-- Building the window
---------------------------------------------------------------------------

-- A boss tab: the icon of its best drop; the chosen one outlined.
local function tab(i)
	local b = W.tabs[i]
	if b then return b end
	b = CreateFrame("Button", nil, W.frame)
	b.icon = iconFrame(b, 34)
	b.icon:SetAllPoints()
	b.ring = edges(b, "OVERLAY")
	b.under = b:CreateTexture(nil, "OVERLAY")
	b.under:SetHeight(2)
	b.under:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 0, -6)
	b.under:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", 0, -6)
	T.Paint(b.under, "accent")
	b:SetScript("OnClick", function(self) B.SelectBoss(self.pwBoss) end)
	b:SetScript("OnEnter", function(self)
		self.pwHover = true
		B.PaintTabs()
		local e = L.Encounter(self.pwBoss)
		if GameTooltip and e then
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			GameTooltip:SetText(e.name, 1, 1, 1)
			local n = #e.loot
			GameTooltip:AddLine(n > 0 and ("%d item%s"):format(n, n == 1 and "" or "s") or "No drops known yet", 0.6, 0.69, 0.75)
			if e.kills > 0 then GameTooltip:AddLine(("You have seen %d kill%s"):format(e.kills, e.kills == 1 and "" or "s"), 0.6, 0.69, 0.75) end
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self)
		self.pwHover = false
		B.PaintTabs()
		if GameTooltip then GameTooltip:Hide() end
	end)
	W.tabs[i] = b
	return b
end

function B.PaintTabs()
	for _, b in ipairs(W.tabs or {}) do
		if b:IsShown() then
			local on = b.pwBoss == state.boss
			local lit = on or b.pwHover or b.pwHasLoot
			b.icon.tex:SetDesaturated(not lit)
			b.icon:SetAlpha(lit and 1 or 0.55)
			if on then paintEdges(b.ring, "accent") else paintEdges(b.ring, b.pwHover and "text2" or "border", b.pwHover and 1 or 0) end
			b.under:SetShown(on)
		end
	end
end

-- A chapter button: a kind of item (or a group in the contents) and its count.
local function chapter(i)
	local b = W.chapters[i]
	if b then return b end
	b = CreateFrame("Button", nil, W.frame)
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
	b:SetScript("OnEnter", function(self) if not self.pwOn then paint(self.pwGround, "hover") end end)
	b:SetScript("OnLeave", function(self) if not self.pwOn then paint(self.pwGround, "bg2") end end)
	W.chapters[i] = b
	return b
end

local function build()
	if W.frame then return W.frame end
	local f = CreateFrame("Frame", ns.ID.global .. "Browser", nil)
	f:SetParent(UIParent)
	W.frame = f
	f:SetSize(W_, H_)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	T.Panel(f)
	if UISpecialFrames then table.insert(UISpecialFrames, ns.ID.global .. "Browser") end

	-- Header: the name, the search box, settings and close.
	W.label = T.Text(f, "label", "text2")
	W.label:SetPoint("LEFT", f, "TOPLEFT", PAD, -HEADER_H / 2)
	W.label:SetJustifyV("MIDDLE")
	W.label:SetText(ns.ID.name:upper())
	W.close = T.IconButton(f, "close", "Close", function() B.Hide() end)
	W.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -6)
	W.settings = T.IconButton(f, "settings", "Settings", function() ns.Fire("SHOW_CONFIG") end)
	W.settings:SetPoint("RIGHT", W.close, "LEFT", -2, 0)

	local box = CreateFrame("EditBox", ns.ID.global .. "Search", f)
	box:SetSize(220, 22)
	box:SetPoint("RIGHT", W.settings, "LEFT", -8, 0)
	box:SetAutoFocus(false)
	box:SetTextInsets(8, 8, 0, 0)
	T.Panel(box, "bg2", "border")
	T.Font(box, "meta")
	T.Paint(box, "text")
	local hint = T.Text(box, "small", "muted")
	hint:SetPoint("LEFT", 8, 0)
	hint:SetJustifyV("MIDDLE")
	hint:SetText("Search every boss's loot")
	box:SetScript("OnTextChanged", function(self, user)
		local text = self:GetText() or ""
		hint:SetShown(text == "")
		if user ~= false then B.Search(text) end
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box.pwHint = hint
	W.search = box

	W.headerLine = divider(f)
	W.headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -HEADER_H)
	W.headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -HEADER_H)

	W.tabs, W.chapters = {}, {}
	W.tabLine = divider(f)

	-- The boss's (or the page's) name, a note on the right, a line under it.
	W.title = T.Text(f, "title", "text")
	W.title:SetWordWrap(false)
	W.info = T.Text(f, "meta", "text2")
	W.info:SetJustifyH("RIGHT")
	W.back = CreateFrame("Button", nil, f)
	W.back.pwText = T.Text(W.back, "meta", "accent")
	W.back.pwText:SetPoint("RIGHT")
	W.back.pwText:SetJustifyH("RIGHT")
	W.back:SetHeight(18)
	W.back:SetScript("OnEnter", function(self) textColor(self.pwText, "text") end)
	W.back:SetScript("OnLeave", function(self) textColor(self.pwText, "accent") end)
	W.sub = T.Text(f, "small", "muted")
	W.sub:SetWordWrap(false)

	-- The page: a scroll area with a thin thumb.
	local scroll = CreateFrame("ScrollFrame", nil, f)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		self:SetVerticalScroll(max(0, min(W.range or 0, (self:GetVerticalScroll() or 0) - delta * 40)))
		B.PaintThumb()
	end)
	W.scroll, W.child = scroll, child
	W.thumb = f:CreateTexture(nil, "OVERLAY")
	W.thumb:SetWidth(2)
	T.Paint(W.thumb, "border")

	-- Footer: what to show, the page and the arrows.
	W.footLine = divider(f)
	W.footLine:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, FOOT_H)
	W.footLine:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, FOOT_H)
	W.showLabel = T.Text(f, "meta", "text2")
	W.showLabel:SetText("Show")
	W.showLabel:SetPoint("LEFT", f, "BOTTOMLEFT", PAD, FOOT_H / 2)
	W.showAll = segment(f, "Everything", function() ns.Set("loot.usable", false) end)
	W.showAll:SetPoint("LEFT", W.showLabel, "RIGHT", 8, 0)
	W.showMine = segment(f, "For my class", function() ns.Set("loot.usable", true) end)
	W.showMine:SetPoint("LEFT", W.showAll, "RIGHT", 3, 0)
	W.next = T.Button(f, ">", "default", function() B.Turn(1) end)
	W.next:SetWidth(28)
	W.next:SetPoint("RIGHT", f, "BOTTOMRIGHT", -PAD - 6, FOOT_H / 2)
	W.prev = T.Button(f, "<", "default", function() B.Turn(-1) end)
	W.prev:SetWidth(28)
	W.prev:SetPoint("RIGHT", W.next, "LEFT", -6, 0)
	W.page = T.Text(f, "meta", "text2")
	W.page:SetJustifyH("RIGHT")
	W.page:SetPoint("RIGHT", W.prev, "LEFT", -10, 0)

	f:SetScript("OnHide", function(self) A.Set(self, "alpha", 0) end)
	f:Hide()
	return f
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function B.PaintThumb()
	local range, viewH = W.range or 0, W.viewH or 0
	if range <= 0 or viewH <= 0 then W.thumb:Hide() return end
	local h = max(20, viewH * viewH / (viewH + range))
	local at = (W.scroll:GetVerticalScroll() or 0) / range
	W.thumb:ClearAllPoints()
	W.thumb:SetHeight(h)
	W.thumb:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -5, -(W.pageTop + (viewH - h) * at))
	W.thumb:Show()
end

-- The boss tabs; returns the y below them (y when there are none).
local function drawTabs(y, bosses)
	for _, b in ipairs(W.tabs) do b:Hide() end
	W.tabLine:Hide()
	if #bosses == 0 then return y end
	local n = #bosses
	local s = max(18, min(34, floor((W_ - 2 * PAD - (n - 1) * TAB_GAP) / n)))
	local x = PAD
	for i, eid in ipairs(bosses) do
		local b = tab(i)
		local e = L.Encounter(eid)
		b.pwBoss, b.pwHasLoot = eid, e and #e.loot > 0
		b:ClearAllPoints()
		b:SetSize(s, s)
		b:SetPoint("TOPLEFT", W.frame, "TOPLEFT", x, -y)
		b.icon.tex:SetTexture(bossIcon(e) or QUESTION)
		b:Show()
		x = x + s + TAB_GAP
	end
	B.PaintTabs()
	y = y + s + 8
	W.tabLine:ClearAllPoints()
	W.tabLine:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -y)
	W.tabLine:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", 0, -y)
	W.tabLine:Show()
	return y + 14
end

-- The title row and the line under it; returns the y below.
local function drawTitle(y, title, info, back, onBack, sub)
	W.title:ClearAllPoints()
	W.title:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD, -y)
	W.title:SetText(title)
	W.back.pwText:SetText(back or "")
	W.back:SetShown(back ~= nil)
	W.back:SetWidth((W.back.pwText:GetStringWidth() or 60) + 4)
	W.back:ClearAllPoints()
	W.back:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -PAD, -(y + 1))
	W.back:SetScript("OnClick", onBack)
	W.info:SetText(info or "")
	W.info:ClearAllPoints()
	if back then W.info:SetPoint("TOPRIGHT", W.back, "TOPLEFT", -12, -1)
	else W.info:SetPoint("TOPRIGHT", W.frame, "TOPRIGHT", -PAD, -(y + 3)) end
	local used = (back and (W.back:GetWidth() + 12) or 0) + (W.info:GetStringWidth() or 0) + 16
	W.title:SetWidth(max(80, W_ - 2 * PAD - used))
	y = y + 22
	W.sub:ClearAllPoints()
	W.sub:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD, -y)
	W.sub:SetWidth(W_ - 2 * PAD)
	W.sub:SetText(sub or "")
	return y + 18
end

-- The chapter buttons: { { name, line, value, empty } }, the chosen value.
local function drawChapters(y, list, chosen, onPick)
	for _, b in ipairs(W.chapters) do b:Hide() end
	if #list == 0 then return y end
	local bw = W_ - 2 * PAD
	local cw = (bw - (#list - 1) * 4) / #list
	for i, c in ipairs(list) do
		local b = chapter(i)
		local on = c[3] == chosen
		b.pwOn = on
		b:ClearAllPoints()
		b:SetSize(cw, CHAPTER_H)
		b:SetPoint("TOPLEFT", W.frame, "TOPLEFT", PAD + (i - 1) * (cw + 4), -y)
		b.name:SetText(c[1])
		b.range:SetText(c[2])
		textColor(b.name, on and "text" or "text2")
		textColor(b.range, on and "accent" or "muted")
		paint(b.pwGround, on and CHOSEN or "bg2")
		paintEdges(b.ring, "accent", on and 1 or 0)
		b:SetAlpha(c[4] and not on and 0.5 or 1)
		b:SetScript("OnClick", function() onPick(c[3]) end)
		b:Show()
	end
	return y + CHAPTER_H + 10
end

local function placeScroll(top)
	local f = W.frame
	W.scroll:ClearAllPoints()
	W.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -top)
	W.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD + 6, FOOT_H + 6)
	W.viewH = max(0, H_ - top - FOOT_H - 6)
	W.pageW = W_ - 2 * PAD - 6
	W.pageTop = top
end

local function columns()
	local pw = W.pageW
	local cols = max(1, floor((pw + CARD_GAP) / (CARD_MIN_W + CARD_GAP)))
	return cols, (pw - (cols - 1) * CARD_GAP) / cols
end

-- The item cards; returns the page's height.
local function drawItems(rows, empty, note)
	local pw = W.pageW
	local cols, cw = columns()
	local y = 0
	for n, d in ipairs(rows) do
		local col, row = (n - 1) % cols, floor((n - 1) / cols)
		itemCard(col * (cw + CARD_GAP), row * (CARD_H + CARD_GAP), cw, d)
		y = (row + 1) * (CARD_H + CARD_GAP)
	end
	if #rows == 0 then y = line(y, 0, pw, empty, "meta", "text2") + 6 end
	y = y + 8
	if note then y = line(y, 0, pw, note, "small", "muted") end
	return y
end

local SOURCE = "Drops: QuestieDB's Forever data, and what you see drop as you play. No drop chances: neither QuestieDB nor the game has them for Forever."

-- The kind buttons for these items, with their counts.
local function kindChapters(items)
	local list = {}
	for _, k in ipairs(B.KINDS) do
		local n, seen = 0, 0
		for _, d in ipairs(items) do
			local it = L.Item(d.item, true)
			if passesClass(it) and L.SlotMatches(it, k[2]) then
				n = n + 1
				if d.entry and d.entry.seen then seen = seen + 1 end
			end
		end
		local text = ("%d item%s"):format(n, n == 1 and "" or "s")
		if seen > 0 then text = text .. ("  ·  %d seen"):format(seen) end
		list[#list + 1] = { k[1], text, k[2], n == 0 }
	end
	return list
end

local function groupChapters()
	local list = {}
	for _, g in ipairs(GROUPS) do
		local n = g[2] == "wishlist" and #L.Wishlist() or #instancesOf(g[2])
		local what = g[2] == "wishlist" and "item" or (g[2] == "raid" and "raid" or "dungeon")
		list[#list + 1] = { g[1], ("%d %s%s"):format(n, what, n == 1 and "" or "s"), g[2], n == 0 }
	end
	return list
end

local function pickKind(v) ns.Set("loot.slot", v) end
local function pickGroup(v) if v == "wishlist" then B.Wishlist() else B.Contents(v) end end

local function drawFooter(label, canBack, canOn, filters)
	local mine = ns.Get("loot.usable") and true or false
	W.showAll:SetOn(not mine)
	W.showMine:SetOn(mine)
	W.showLabel:SetShown(filters)
	W.showAll:SetShown(filters)
	W.showMine:SetShown(filters)
	W.page:SetText(label or "")
	W.prev:SetShown(label ~= nil)
	W.next:SetShown(label ~= nil)
	W.prev:SetEnabled(canBack)
	W.prev:SetAlpha(canBack and 1 or 0.35)
	W.next:SetEnabled(canOn)
	W.next:SetAlpha(canOn and 1 or 0.35)
end

local function indexOf(list, v)
	for i, x in ipairs(list) do if x == v then return i end end
	return nil
end

function draw()
	if not (W.frame and W.frame:IsShown()) then return end
	releaseAll()
	local y = HEADER_H + 12
	local h
	shown = {}

	if state.mode == "boss" then
		local inst = L.Instance(state.map)
		local bosses = inst and inst.encounters or {}
		y = drawTabs(y, bosses)
		local e = state.boss and L.Encounter(state.boss)
		local bits = {}
		if inst then bits[#bits + 1] = inst.name .. (levelsText(inst) and ("  ·  level " .. levelsText(inst)) or "") end
		if e and e.kills > 0 then bits[#bits + 1] = ("you have seen %d kill%s"):format(e.kills, e.kills == 1 and "" or "s") end
		local items = allItems()
		local rows, before = itemRows()
		if before > #rows then bits[#bits + 1] = ("%d hidden by the filters"):format(before - #rows) end
		y = drawTitle(y, e and bossLabel(inst, state.boss, e) or "", ("%d item%s"):format(#items, #items == 1 and "" or "s"),
			"All instances", function() B.Contents(inst and inst.raid and "raid" or "dungeon") end, table.concat(bits, "  ·  "))
		y = drawChapters(y, kindChapters(items), ns.Get("loot.slot"), pickKind)
		placeScroll(y)
		shown = rows
		local empty = #items == 0 and "No drops known for this boss yet: they fill in as you see them drop." or "Nothing of this kind. Pick All, or Show: Everything."
		h = drawItems(rows, empty, SOURCE)
		local i = indexOf(bosses, state.boss) or 1
		drawFooter(("Boss %d / %d"):format(i, #bosses), i > 1, i < #bosses, true)
	elseif state.mode == "contents" or state.mode == "wishlist" then
		y = drawTabs(y, {})
		if state.mode == "contents" then
			local list = instancesOf(state.group)
			local raid = state.group == "raid"
			y = drawTitle(y, raid and "Raids" or "Dungeons", ("%d"):format(#list), state.map and "Back to the bosses" or nil,
				function() B.SelectInstance(state.map) end, raid and "Forever's raids. Pick one for its bosses and their loot." or "Forever's dungeons, by level. Pick one for its bosses and their loot.")
			y = drawChapters(y, groupChapters(), state.group, pickGroup)
			placeScroll(y)
			local cols, cw = columns()
			local here, level = hereMap(), myLevel()
			h = 0
			for n, inst in ipairs(list) do
				local col, row = (n - 1) % cols, floor((n - 1) / cols)
				instanceCard(col * (cw + CARD_GAP), row * (CARD_H + CARD_GAP), cw, inst, here, level)
				h = (row + 1) * (CARD_H + CARD_GAP)
			end
			h = line(h + 8, 0, W.pageW, "Instances, bosses and levels: Forever's own client data.", "small", "muted")
			local gi = state.group == "raid" and 2 or 1
			drawFooter(("Page %d / %d"):format(gi, #GROUPS), gi > 1, gi < #GROUPS, false)
		else
			local rows, before = itemRows()
			local sub = "This character's own list. Right-click any item, or click its diamond, to add or take it off."
			if before > #rows then sub = sub .. ("  ·  %d hidden by the filters"):format(before - #rows) end
			y = drawTitle(y, "Your wishlist", ("%d"):format(before), state.map and "Back to the bosses" or nil,
				function() B.SelectInstance(state.map) end, sub)
			y = drawChapters(y, groupChapters(), "wishlist", pickGroup)
			placeScroll(y)
			shown = rows
			h = drawItems(rows, before == 0 and "Nothing on your wishlist yet." or "Nothing here for these filters.", nil)
			drawFooter(("Page %d / %d"):format(3, #GROUPS), true, false, true)
		end
	else -- search
		y = drawTabs(y, {})
		local rows, before = itemRows()
		local sub = #rows > 0 and ("%d found"):format(#rows) or "Nothing found. Items the game has not loaded yet are searched by the data's names."
		if before > #rows then sub = sub .. ("  ·  %d hidden by the filters"):format(before - #rows) end
		y = drawTitle(y, ("Search: %s"):format(state.text or ""), nil, state.map and "Back to the bosses" or nil, function()
			W.search:SetText("")
			W.search:ClearFocus()
			B.SelectInstance(state.map)
		end, sub)
		y = drawChapters(y, {}, nil, pickKind)
		placeScroll(y)
		shown = rows
		h = drawItems(rows, "", nil)
		drawFooter(nil, false, false, true)
	end

	W.child:SetSize(W.pageW, max(1, h))
	W.range = max(0, h - W.viewH)
	W.scroll:SetVerticalScroll(min(W.scroll:GetVerticalScroll() or 0, W.range))
	W.scroll:EnableMouseWheel(W.range > 0)
	B.PaintThumb()
end
B.Render = function() draw() end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------

-- The instance you are standing in, else the first one.
local function startingMap()
	local map = hereMap()
	if map and L.Instance(map) then return map end
	local first = L.Instances()[1]
	return first and first.map
end

local function top() if W.scroll then W.scroll:SetVerticalScroll(0) end end

-- Opens an instance on its first boss with loot (no drawing).
local function choose(map)
	local inst = L.Instance(map)
	if not inst then return false end
	state.mode, state.map, state.text = "boss", map, nil
	state.boss = nil
	-- The first boss with loot, else the first.
	for _, eid in ipairs(inst.encounters) do
		local e = L.Encounter(eid)
		if e and #e.loot > 0 then state.boss = eid break end
	end
	state.boss = state.boss or inst.encounters[1]
	return true
end

function B.SelectInstance(map)
	if not choose(map) then return false end
	if W.search and (W.search:GetText() or "") ~= "" then W.search:SetText("") end
	top()
	draw()
	return true
end

function B.SelectBoss(eid)
	local e = L.Encounter(eid)
	if not e then return false end
	state.mode, state.boss, state.map, state.text = "boss", eid, e.map or state.map, nil
	top()
	draw()
	return true
end

function B.Contents(group)
	state.mode, state.group, state.text = "contents", group == "raid" and "raid" or "dungeon", nil
	top()
	draw()
end

function B.Wishlist()
	state.mode, state.text = "wishlist", nil
	top()
	draw()
end

function B.Search(text)
	text = tostring(text or "")
	if text:gsub("%s", "") == "" then
		if state.mode == "search" then B.SelectInstance(state.map or startingMap()) end
		return
	end
	state.mode, state.text = "search", text
	top()
	draw()
end

-- The arrows: the boss before or after, or the contents' page.
function B.Turn(delta)
	if state.mode == "boss" then
		local inst = L.Instance(state.map)
		local list = inst and inst.encounters or {}
		local i = (indexOf(list, state.boss) or 1) + delta
		if list[i] then B.SelectBoss(list[i]) end
	elseif state.mode == "contents" or state.mode == "wishlist" then
		local i = (state.mode == "wishlist" and 3 or (state.group == "raid" and 2 or 1)) + delta
		if GROUPS[i] then pickGroup(GROUPS[i][2]) end
	end
end

function B.State() return state end
function B.Rows() return shown end
function B.Frame() return W.frame end

function B.Show()
	local f = build()
	if not state.map then choose(startingMap()) end
	if not f:IsShown() then
		A.Set(f, "alpha", 0)
		f:SetAlpha(0)
		f:Show()
		A.Fade(f, 1, A.NORMAL)
	end
	draw()
end
function B.Hide()
	local f = W.frame
	if not (f and f:IsShown()) then return end
	A.Fade(f, 0, A.FAST, function() if A.Get(f, "alpha") == 0 then f:Hide() end end)
end
function B.Toggle() if W.frame and W.frame:IsShown() then B.Hide() else B.Show() end end
function B.IsShown() return W.frame ~= nil and W.frame:IsShown() end

local function refresh() if W.frame and W.frame:IsShown() then draw() end end
ns.On("LOOT_SEEN", refresh)
ns.On("ITEMS_CHANGED", refresh)
ns.On("WISHLIST_CHANGED", refresh)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^loot%.") or path == "*") then refresh() end
end)
