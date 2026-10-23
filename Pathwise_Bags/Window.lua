-- Pathwise Bags: one bag window in the Pathwise Signature look.
--
-- Laid out the way players know from bag addons such as Baganator and
-- Bagnon (ideas only; none of their code): your name and a search box on
-- top, an optional bag bar, item sections packed side by side, empty slots
-- folded into one square with a count, free slots and money along the bottom.
-- Sections: what items are to you (Quest, Upgrades, Equipment, Consumables,
-- Professions, Other, Junk), one grid of every slot, or one section per bag
-- (each bag's header folds it away, for those who want only some bags).
--
-- On each item: Pathwise's markers (top left: why keep it, a quest, upgrade,
-- profession material, kept; top right: best in slot or can be sold), its
-- item level on gear, the game's new-item glow, and junk greyed out.
--
-- The item buttons are Blizzard's own (ContainerFrameItemButtonTemplate,
-- Forever's ContainerFrame.xml), so using, selling, dragging and tooltips
-- work as in the game's bags. A button finds its bag through its parent's
-- ID (ContainerFrameItemButtonMixin:GetBagID), so each bag has a holder
-- frame with that ID. Buttons are made out of combat only, and the window is
-- made with no parent and placed afterwards, so it never taints the game's.
--
-- "Mark items" mode lays a click catcher over the items: a click marks an
-- item Keep, then Junk, then nothing. The game's own click is untouched.
--
-- With "Use the Pathwise bag window" on, opening the bags shows this window
-- and hides the game's (hooksecurefunc on OpenAllBags, ToggleAllBags,
-- ToggleBackpack, OpenBackpack; nothing of the game's is replaced).

local ADDON, ns = ...
local S, Items = Pathwise.Suite, ns.Items
local T = S.Theme
local W = {}
ns.Window = W

S.Defaults("bags", {
	window = true, -- use this window instead of the game's bags
	view = "categories", -- "categories" (by kind) | "grid" | "bags" (one section per bag)
	folded = nil, -- by bag: { [bagID] = true } for bags folded away
	columns = 12,
	bagBar = false, -- show the bag bar under the title
	point = nil, -- { point, relPoint, x, y }
})

local SIZE, GAP, PAD = 37, 4, 12
local SECTION_GAP = 14
local TOP = 40 -- title row
local BAGBAR = 46
local FOOT = 28
local readable = S.Compat.Readable

local frame, body, holders, buttons, search, catchers, bagbar
local markMode = false
local filter = ""
local hoverBag -- a bag of the bag bar under the mouse: its items stand out

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b = pcall(fn, ...) if ok then return a, b end end

---------------------------------------------------------------------------
-- Item buttons
---------------------------------------------------------------------------

local function holder(bag)
	holders[bag] = holders[bag] or CreateFrame("Frame", nil, body)
	local h = holders[bag]
	h:SetID(bag)
	h:SetAllPoints(body)
	return h
end

local function makeButton(bag, slot)
	local key = bag * 100 + slot
	if buttons[key] then return buttons[key] end
	if inCombat() then return nil end
	local parent = holder(bag)
	local ok, b = pcall(CreateFrame, "ItemButton", nil, parent, "ContainerFrameItemButtonTemplate")
	if not ok or not b then b = CreateFrame("Button", nil, parent, "ContainerFrameItemButtonTemplate") end
	if b.Initialize then pcall(b.Initialize, b, bag, slot) else b:SetID(slot) end
	b:SetSize(SIZE, SIZE)
	-- Pathwise's markers: top left (why keep it), top right (best / sell).
	local tl = b:CreateTexture(nil, "OVERLAY", nil, 5)
	tl:SetSize(14, 14)
	tl:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
	local tr = b:CreateTexture(nil, "OVERLAY", nil, 5)
	tr:SetSize(14, 14)
	tr:SetPoint("TOPRIGHT", b, "TOPRIGHT", -1, -1)
	-- Item level (gear), bottom left; the folded empty slots' count, centre.
	local lvl = T.Text(b, "small", "text", "OVERLAY")
	lvl:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
	T.Shadow(lvl)
	local empty = T.Text(b, "meta", "text2", "OVERLAY")
	empty:SetPoint("CENTER")
	b.pwLeft, b.pwRight, b.pwLevel, b.pwEmpty = tl, tr, lvl, empty
	b.pwBag, b.pwSlot = bag, slot
	buttons[key] = b
	return b
end

local GLYPH = {
	quest = { "glyph-quest", "warning" },
	upgrade = { "glyph-upgrade", "gear" },
	best = { "glyph-best", "gear" },
	profession = { "glyph-prof", "bags" },
	keep = { "glyph-lock", "text2" },
	sell = { "glyph-coin", "warning" },
}

local function glyph(tex, kind)
	local g = kind and GLYPH[kind]
	if not g then tex:Hide() return end
	tex:SetTexture(T.MEDIA .. g[1])
	local c = T.Color(g[2])
	tex:SetVertexColor(c[1], c[2], c[3], 1)
	tex:Show()
end

-- The markers an item shows: left = why keep it, right = best / can be sold.
function W.Markers(e)
	local t = e.facts.tags
	local left = (t.keep and "keep") or (t.quest and "quest") or (t.upgrade and "upgrade") or (t.profession and "profession") or nil
	local right = (t.best and "best") or (e.facts.sell and "sell") or nil
	return left, right
end

-- The item level shown on gear (bottom left), or nil.
function W.LevelText(e)
	if e.equipLoc and e.equipLoc ~= "" and e.equipLoc ~= "INVTYPE_BAG" and (e.classID == 2 or e.classID == 4) and (e.ilvl or 0) > 1 then
		return tostring(e.ilvl)
	end
end

local function paintButton(b, e)
	if SetItemButtonTexture then
		local icon = C_Item and C_Item.GetItemIconByID and readable(call(C_Item.GetItemIconByID, e.id))
		call(SetItemButtonTexture, b, icon)
	end
	call(SetItemButtonCount, b, e.count)
	call(SetItemButtonQuality, b, e.quality, e.link)
	if e.quest then call(b.UpdateQuestItem, b, e.quest.isQuestItem, e.quest.questID, e.quest.isActive) end
	call(b.UpdateJunkItem, b, e.quality, e.noValue)
	call(b.UpdateNewItem, b, e.quality)
	call(b.SetHasItem, b, true)
	call(b.UpdateCooldown, b, true)
	-- Junk greyed out, as bag addons do.
	call(SetItemButtonDesaturated, b, e.facts.tags.junk and true or false)
	local left, right = W.Markers(e)
	glyph(b.pwLeft, left)
	glyph(b.pwRight, right)
	local lvl = W.LevelText(e)
	b.pwLevel:SetText(lvl or "")
	b.pwLevel:SetShown(lvl ~= nil)
	if lvl and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[e.quality or 1] then
		local q = ITEM_QUALITY_COLORS[e.quality or 1]
		b.pwLevel:SetTextColor(q.r or 1, q.g or 1, q.b or 1, 1)
	end
	b.pwEmpty:Hide()
	b.pwEntry = e
end

local function paintEmpty(b, folded)
	call(SetItemButtonTexture, b, nil)
	call(SetItemButtonCount, b, 0)
	call(SetItemButtonQuality, b, nil)
	call(SetItemButtonDesaturated, b, false)
	call(b.SetHasItem, b, false)
	b.pwLeft:Hide()
	b.pwRight:Hide()
	b.pwLevel:Hide()
	b.pwEmpty:SetText(folded and tostring(folded) or "")
	b.pwEmpty:SetShown(folded ~= nil)
	b.pwEntry = nil
end

---------------------------------------------------------------------------
-- Sections
---------------------------------------------------------------------------

-- Does an entry match the search? Name, category, or why it is kept.
function W.Matches(e, text)
	text = (text or ""):lower()
	if text == "" then return true end
	local hay = table.concat({ e.name or "", e.facts.category or "", e.facts.why or "" }, " "):lower()
	return hay:find(text, 1, true) ~= nil
end

-- The sections the window shows: { { key, name, entries }, ... }.
-- By kind, the empty slots fold into one entry { empty = true, folded = n }
-- (the first free slot, so items can still be dropped on it).
function W.Groups(view)
	local entries = Items.Scan()
	local filled = {}
	for _, e in ipairs(entries) do filled[e.bag * 100 + e.slot] = e end
	local empty = {}
	for _, bag in ipairs(Items.BAGS) do
		for slot = 1, Items.NumSlots(bag) do
			if not filled[bag * 100 + slot] then empty[#empty + 1] = { bag = bag, slot = slot, empty = true } end
		end
	end
	if view == "bags" then
		local folded = S.Get("bags.folded") or {}
		local groups = {}
		for _, bag in ipairs(Items.BAGS) do
			local n = Items.NumSlots(bag)
			if n > 0 then
				local list, free = {}, 0
				for slot = 1, n do
					local e = filled[bag * 100 + slot]
					if not e then free = free + 1 end
					list[#list + 1] = e or { bag = bag, slot = slot, empty = true }
				end
				local name = W.BagName(bag)
				local isFolded = folded[bag] and true or false
				groups[#groups + 1] = {
					key = "bag" .. bag, bag = bag, folded = isFolded,
					name = ("%s  ·  %d free%s"):format(name, free, isFolded and "  ·  hidden" or ""),
					entries = isFolded and {} or list,
				}
			end
		end
		return groups
	end
	if view == "grid" then
		local all = {}
		for _, bag in ipairs(Items.BAGS) do
			for slot = 1, Items.NumSlots(bag) do
				all[#all + 1] = filled[bag * 100 + slot] or { bag = bag, slot = slot, empty = true }
			end
		end
		return { { key = "all", entries = all } }
	end
	local by = {}
	for _, e in ipairs(entries) do
		local k = e.facts.category
		by[k] = by[k] or {}
		table.insert(by[k], e)
	end
	local groups = {}
	for _, c in ipairs(Items.CATEGORIES) do
		local list = by[c.key]
		if list and #list > 0 then
			table.sort(list, function(a, b)
				if (a.quality or 0) ~= (b.quality or 0) then return (a.quality or 0) > (b.quality or 0) end
				if (a.ilvl or 0) ~= (b.ilvl or 0) then return (a.ilvl or 0) > (b.ilvl or 0) end
				return (a.name or "") < (b.name or "")
			end)
			groups[#groups + 1] = { key = c.key, name = c.name, entries = list }
		end
	end
	if #empty > 0 then
		local first = empty[1]
		groups[#groups + 1] = { key = "empty", name = "Empty", entries = { { bag = first.bag, slot = first.slot, empty = true, folded = #empty } } }
	end
	return groups
end

-- A bag's name: "Backpack", else the bag item's own name.
function W.BagName(bag)
	if bag == 0 then return "Backpack" end
	local name = C_Container and C_Container.GetBagName and readable(call(C_Container.GetBagName, bag))
	return name or ("Bag " .. bag)
end

-- Fold a bag away (by bag), or show it again.
function W.ToggleBag(bag)
	local t = {}
	for k, v in pairs(S.Get("bags.folded") or {}) do t[k] = v end
	t[bag] = not t[bag] or nil
	S.Set("bags.folded", t)
end

-- Packs sections into rows, side by side, `width` px wide (Baganator-like).
-- -> { { x, y, cols, rows } per section }, total height
function W.Pack(groups, width, labels)
	local out = {}
	local maxCols = math.max(1, math.floor((width + GAP) / (SIZE + GAP)))
	local x, y, rowH = 0, 0, 0
	local labelH = labels and 16 or 0
	for i, g in ipairs(groups) do
		local n = #g.entries
		local cols = math.max(1, math.min(n, maxCols))
		if labels then cols = math.max(cols, math.min(maxCols, 2)) end
		local rows = math.max(1, math.ceil(n / cols))
		local w = cols * (SIZE + GAP) - GAP
		local h = labelH + rows * (SIZE + GAP) - GAP
		-- A folded bag: its header only, as wide as its words.
		if n == 0 then rows, w, h = 0, math.min(width, 4 * (SIZE + GAP)), labelH end
		if x > 0 and x + w > width then
			x, y = 0, y + rowH + 10
			rowH = 0
		end
		out[i] = { x = x, y = y, cols = cols, rows = rows, w = w, h = h }
		x = x + w + SECTION_GAP
		rowH = math.max(rowH, h)
	end
	return out, y + rowH
end

-- Section headers: text, and in the by-bag view a click folds the bag.
local labels = {}
local function label(i)
	local l = labels[i]
	if not l then
		l = CreateFrame("Button", nil, body)
		l:SetHeight(14)
		l.text = T.Text(l, "label", "text2")
		l.text:SetPoint("LEFT")
		l:SetScript("OnClick", function(self) if self.pwBag then W.ToggleBag(self.pwBag) end end)
		l:SetScript("OnEnter", function(self) if self.pwBag then T.TextColor(self.text, "text") end end)
		l:SetScript("OnLeave", function(self) if self.pwBag then T.TextColor(self.text, "text2") end end)
		labels[i] = l
	end
	return l
end
W.Headers = function() return labels end

local function dimFor(e)
	if e.empty then return 1 end
	if hoverBag ~= nil and e.bag ~= hoverBag then return 0.25 end
	if not W.Matches(e, filter) then return 0.2 end
	return 1
end

function W.Refresh()
	if not (frame and frame:IsShown()) then return end
	if inCombat() then W.pending = true end
	local cols = S.Get("bags.columns") or 12
	local view = S.Get("bags.view") or "categories"
	local width = cols * (SIZE + GAP) - GAP
	local groups = W.Groups(view)
	local byKind = view ~= "grid"
	local places, height = W.Pack(groups, width, byKind)
	for _, b in pairs(buttons) do b:Hide() end
	for _, l in pairs(labels) do l:Hide() end
	for gi, g in ipairs(groups) do
		local p = places[gi]
		local top = p.y
		if byKind then
			local l = label(gi)
			T.TextColor(l.text, g.key == "junk" and "warning" or "text2")
			l.text:SetText((g.bag and ((g.folded and "+ " or "- ") .. g.name) or (g.name or "")):upper())
			l:SetWidth(math.max(40, (l.text:GetStringWidth() or 40) + 4))
			l.pwBag = g.bag
			l:EnableMouse(g.bag ~= nil)
			l:ClearAllPoints()
			l:SetPoint("TOPLEFT", body, "TOPLEFT", p.x, -p.y)
			l:Show()
			top = top + 16
		end
		for n, e in ipairs(g.entries) do
			local b = makeButton(e.bag, e.slot)
			if b then
				local i = n - 1
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", body, "TOPLEFT", p.x + (i % p.cols) * (SIZE + GAP), -(top + math.floor(i / p.cols) * (SIZE + GAP)))
				if e.empty then paintEmpty(b, e.folded) else paintButton(b, e) end
				b:SetAlpha(dimFor(e))
				b:Show()
			end
		end
	end
	local barH = S.Get("bags.bagBar") and BAGBAR or 0
	body:ClearAllPoints()
	body:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + barH))
	body:SetSize(width, math.max(height, SIZE))
	frame:SetSize(width + PAD * 2, TOP + barH + math.max(height, SIZE) + 10 + FOOT)
	W.RefreshBagBar()
	-- Footer: free slots and what can be sold on the left, money on the right.
	local free, total = ns.Space.Free()
	frame.pwFree:SetText(("%d / %d free"):format(free, total))
	T.TextColor(frame.pwFree, free <= (S.Get("bags.warnAt") or 2) and "warning" or "text2")
	local list, junkValue = ns.Sell.List()
	frame.pwSell:SetText(#list > 0 and ("%d to sell  ·  %s"):format(#list, Items.Money(junkValue)) or "")
	frame.pwMoney:SetText(W.MoneyText(GetMoney and readable(call(GetMoney)) or 0))
	W.RefreshCatchers()
end

-- Money in the game's coin colours: gold, silver, copper.
function W.MoneyText(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = ("|cffF8D25A%d|r|cff9AAFC0g|r"):format(g) end
	if g > 0 or s > 0 then out[#out + 1] = ("|cffC9D6E2%d|r|cff9AAFC0s|r"):format(s) end
	out[#out + 1] = ("|cffE0956A%d|r|cff9AAFC0c|r"):format(c)
	return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- The bag bar: your bags, their free slots; hover one to see its items
---------------------------------------------------------------------------

local BACKPACK_ICON = "Interface\\Buttons\\Button-Backpack-Up"

function W.BagInfo(bag)
	local n = Items.NumSlots(bag)
	local free = 0
	if C_Container and C_Container.GetContainerNumFreeSlots then free = readable(call(C_Container.GetContainerNumFreeSlots, bag)) or 0 end
	local icon = BACKPACK_ICON
	if bag > 0 and C_Container and C_Container.ContainerIDToInventoryID and GetInventoryItemTexture then
		local inv = call(C_Container.ContainerIDToInventoryID, bag)
		icon = inv and readable(call(GetInventoryItemTexture, "player", inv)) or nil
	end
	return { bag = bag, slots = n, free = free, icon = icon }
end

function W.RefreshBagBar()
	if not bagbar then return end
	local on = S.Get("bags.bagBar")
	bagbar:SetShown(on and true or false)
	if not on then return end
	for i, bag in ipairs(Items.BAGS) do
		local s = bagbar.slots[i]
		local info = W.BagInfo(bag)
		s.icon:SetTexture(info.icon or nil)
		s.icon:SetAlpha(info.slots > 0 and 1 or 0.25)
		s.text:SetText(info.slots > 0 and ("%d/%d"):format(info.free, info.slots) or "")
	end
end

local function buildBagBar()
	bagbar = CreateFrame("Frame", nil, frame)
	bagbar:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TOP + 2)
	bagbar:SetSize(5 * 44, BAGBAR - 6)
	bagbar.slots = {}
	for i, bag in ipairs(Items.BAGS) do
		local s = CreateFrame("Button", nil, bagbar)
		s:SetSize(28, 28)
		s:SetPoint("TOPLEFT", (i - 1) * 44, 0)
		T.Panel(s, "bg2")
		s.icon = s:CreateTexture(nil, "ARTWORK")
		s.icon:SetPoint("TOPLEFT", 2, -2)
		s.icon:SetPoint("BOTTOMRIGHT", -2, 2)
		s.text = T.Text(bagbar, "small")
		s.text:SetPoint("TOP", s, "BOTTOM", 0, -1)
		s:SetScript("OnEnter", function() hoverBag = bag W.Refresh() end)
		s:SetScript("OnLeave", function() hoverBag = nil W.Refresh() end)
		bagbar.slots[i] = s
	end
	bagbar:Hide()
end

function W.HoverBag(bag) hoverBag = bag W.Refresh() end

---------------------------------------------------------------------------
-- Mark mode: click catchers over the items
---------------------------------------------------------------------------

local NEXT = { [""] = "keep", keep = "junk", junk = "" }

function W.RefreshCatchers()
	for _, c in pairs(catchers) do c:Hide() end
	if not markMode then return end
	local i = 0
	for _, b in pairs(buttons) do
		if b:IsShown() and type(b.pwEntry) == "table" then
			i = i + 1
			local c = catchers[i]
			if not c then
				c = CreateFrame("Button", nil, body)
				c:SetFrameLevel((b:GetFrameLevel() or 1) + 5)
				local edge = c:CreateTexture(nil, "OVERLAY")
				edge:SetAllPoints()
				T.SetColor(edge, "bags", 0.18)
				c:SetScript("OnClick", function(self)
					local e = self.pwEntry
					if not e then return end
					local now = Items.MarkOf(e.id) or ""
					local nxt = NEXT[now]
					Items.Mark(e.id, nxt ~= "" and nxt or nil)
					S.Print(("Pathwise Bags: %s %s."):format(e.link or e.name or "item",
						nxt == "keep" and "will be kept (never sold)" or nxt == "junk" and "is marked as junk" or "is no longer marked"))
				end)
				catchers[i] = c
			end
			c.pwEntry = b.pwEntry
			c:ClearAllPoints()
			c:SetAllPoints(b)
			c:Show()
		end
	end
end

function W.SetMarkMode(on)
	markMode = on and true or false
	if frame and frame.pwMark then
		frame.pwMark:SetGlyph(markMode and "lock" or "coin")
	end
	W.RefreshCatchers()
end
function W.MarkMode() return markMode end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function playerTitle()
	local name = UnitName and readable(call(UnitName, "player"))
	return name and (name .. "'s Bags") or "Bags"
end

local function build()
	if frame then return frame end
	holders, buttons, catchers = {}, {}, {}
	frame = CreateFrame("Frame", "PathwiseBagsFrame", nil)
	frame:SetParent(UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		S.Set("bags.point", { p, rp, x, y })
	end)
	T.Panel(frame)
	local accent = frame:CreateTexture(nil, "ARTWORK")
	accent:SetPoint("TOPLEFT", 1, -1)
	accent:SetPoint("TOPRIGHT", -1, -1)
	accent:SetHeight(2)
	T.SetColor(accent, "bags")
	local p = S.Get("bags.point")
	if type(p) == "table" then frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -60, 120) end
	if UISpecialFrames then table.insert(UISpecialFrames, "PathwiseBagsFrame") end

	-- Title row: name, search, buttons.
	local title = T.Text(frame, "window", "text")
	title:SetPoint("TOPLEFT", PAD, -14)
	title:SetText(playerTitle())
	frame.pwTitle = title

	local close = T.IconButton(frame, "close", "Close", function() W.Hide() end)
	close:SetPoint("TOPRIGHT", -8, -9)
	local settings = T.IconButton(frame, "settings", "Pathwise Bags settings", function() S.Open("bags") end)
	settings:SetPoint("RIGHT", close, "LEFT", -2, 0)
	local mark = T.IconButton(frame, "coin", "Mark items: click one to keep it, again for junk, again to clear", function()
		W.SetMarkMode(not markMode)
	end)
	mark:SetPoint("RIGHT", settings, "LEFT", -2, 0)
	frame.pwMark = mark
	local sort = T.IconButton(frame, "sort", "Sort the bags (the game's own sort)", function()
		if C_Container and C_Container.SortBags and not inCombat() then call(C_Container.SortBags) end
	end)
	sort:SetPoint("RIGHT", mark, "LEFT", -2, 0)
	local bags = T.IconButton(frame, "bag", "Show your bags: hover one to see its items", function()
		S.Set("bags.bagBar", not S.Get("bags.bagBar"))
	end)
	bags:SetPoint("RIGHT", sort, "LEFT", -2, 0)
	local view = T.IconButton(frame, "zones", "Show items: by kind, one grid, or by bag (click to switch)", function()
		W.NextView()
	end)
	view:SetPoint("RIGHT", bags, "LEFT", -2, 0)
	frame.pwView = view

	local box = CreateFrame("EditBox", nil, frame)
	box:SetAutoFocus(false)
	box:SetHeight(22)
	box:SetPoint("LEFT", title, "RIGHT", 12, 0)
	box:SetPoint("RIGHT", view, "LEFT", -8, 0)
	T.Panel(box, "bg2")
	T.Font(box, "body")
	box:SetTextInsets(24, 6, 0, 0)
	local icon = box:CreateTexture(nil, "OVERLAY")
	icon:SetTexture(T.MEDIA .. "glyph-search")
	icon:SetSize(14, 14)
	icon:SetPoint("LEFT", 6, 0)
	local hint = T.Text(box, "small")
	hint:SetPoint("LEFT", 24, 0)
	hint:SetText("Search")
	box:SetScript("OnTextChanged", function(self)
		filter = self:GetText() or ""
		hint:SetShown(filter == "")
		W.Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	search = box
	frame.pwSearch = box

	buildBagBar()
	body = CreateFrame("Frame", nil, frame)

	-- Footer.
	local line = T.Divider(frame)
	line:SetPoint("BOTTOMLEFT", PAD, FOOT)
	line:SetPoint("BOTTOMRIGHT", -PAD, FOOT)
	frame.pwFree = T.Text(frame, "meta")
	frame.pwFree:SetPoint("BOTTOMLEFT", PAD, 9)
	frame.pwSell = T.Text(frame, "small", "warning")
	frame.pwSell:SetPoint("LEFT", frame.pwFree, "RIGHT", 12, 0)
	frame.pwMoney = T.Text(frame, "meta", "text")
	frame.pwMoney:SetPoint("BOTTOMRIGHT", -PAD, 9)
	frame.pwMoney:SetJustifyH("RIGHT")

	frame:SetScript("OnHide", function() W.SetMarkMode(false) hoverBag = nil end)
	frame:Hide()
	return frame
end

-- By kind -> one grid -> by bag -> by kind.
local VIEWS = { categories = "grid", grid = "bags", bags = "categories" }
local VIEW_NAMES = { categories = "by kind", grid = "as one grid", bags = "by bag" }
function W.NextView()
	local now = S.Get("bags.view") or "categories"
	local nxt = VIEWS[now] or "categories"
	S.Set("bags.view", nxt)
	S.Print("Pathwise Bags: items shown " .. VIEW_NAMES[nxt] .. ".")
	return nxt
end

function W.Show()
	if inCombat() and not frame then return end
	build():Show()
	W.Refresh()
end
function W.Hide() if frame then frame:Hide() end end
function W.Toggle() if frame and frame:IsShown() then W.Hide() else W.Show() end end
function W.IsShown() return frame ~= nil and frame:IsShown() end
function W.Frame() return frame end
function W.SetSearch(text) build() search:SetText(text or "") filter = text or "" W.Refresh() end

---------------------------------------------------------------------------
-- Taking over the bag keys
---------------------------------------------------------------------------

local function hideGame()
	if ContainerFrameCombinedBags and ContainerFrameCombinedBags.IsShown and ContainerFrameCombinedBags:IsShown() then ContainerFrameCombinedBags:Hide() end
	local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	for _, f in ipairs(list or {}) do if f.IsShown and f:IsShown() then f:Hide() end end
end

-- The bag key runs the game's ToggleAllBags, which itself calls OpenAllBags
-- or CloseBackpack/CloseAllBags (Forever's ContainerFrame.lua). Since the
-- game's bags stay hidden, the game always thinks they are closed and opens
-- them: so a toggle that ends in "open" while this window was already shown
-- means the player pressed the key to close it.
local opened -- { wasShown } set by the open hook during one toggle
local closed -- set by the close hooks during one toggle
local function onOpen()
	if not S.Get("bags.window") then return end
	opened, closed = { wasShown = W.IsShown() }, nil
	W.Show()
	hideGame()
end
local function onToggle()
	if not S.Get("bags.window") then return end
	local o, c = opened, closed
	opened, closed = nil, nil
	if c and not o then
		W.Hide()
	elseif o then
		if o.wasShown then W.Hide() end
	else
		W.Toggle()
	end
	hideGame()
end
-- Within one key press the game closes before it opens, so a close always closes.
local function onClose()
	if not S.Get("bags.window") then return end
	closed, opened = true, nil
	W.Hide()
end

local hooked = false
function W.Install()
	if hooked or not hooksecurefunc then return end
	hooked = true
	if OpenAllBags then hooksecurefunc("OpenAllBags", onOpen) end
	if OpenBackpack then hooksecurefunc("OpenBackpack", onOpen) end
	if ToggleAllBags then hooksecurefunc("ToggleAllBags", onToggle) end
	if ToggleBackpack then hooksecurefunc("ToggleBackpack", onToggle) end
	if CloseAllBags then hooksecurefunc("CloseAllBags", onClose) end
	if CloseBackpack then hooksecurefunc("CloseBackpack", onClose) end
end
W.OnOpen, W.OnToggle, W.OnClose = onOpen, onToggle, onClose

local function refreshSoon()
	if not W.IsShown() or W.waiting then return end
	W.waiting = true
	local function run() W.waiting = false W.Refresh() end
	if C_Timer and C_Timer.After then C_Timer.After(0.1, run) else run() end
end

S.On("READY", function() W.Install() end)
for _, ev in ipairs({ "BAG_UPDATE_DELAYED", "PLAYER_MONEY", "ITEM_LOCK_CHANGED", "BAG_UPDATE_COOLDOWN", "QUEST_LOG_UPDATE" }) do
	S.RegisterEvent(ev, refreshSoon)
end
S.RegisterEvent("PLAYER_REGEN_ENABLED", function() if W.pending then W.pending = false refreshSoon() end end)
S.On("BAGS_CHANGED", refreshSoon)
S.On("GEAR_UPDATED", refreshSoon)
S.On("SETTING_CHANGED", function(path) if type(path) == "string" and path:find("^bags%.") then refreshSoon() end end)
S.RegisterEvent("MERCHANT_SHOW", function() if S.Get("bags.window") and S.Get("bags.openAtMerchant") ~= false then W.Show() end end)
