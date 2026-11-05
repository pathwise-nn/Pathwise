-- Pathwise Loot's window: instances on the left (your wishlist first, then
-- dungeons by level, then raids), the chosen instance's bosses in the middle,
-- and the chosen boss's loot on the right, with a search box over everything.
--
-- A loot row: the item's icon and name in its quality color, its slot and
-- levels, an upgrade mark when Pathwise Gear says it is one for you, how many
-- times you have seen it drop, and a star for the wishlist. Hover: the
-- game's item tooltip. Shift-click / Ctrl-click: the game's own modified
-- click (link in chat, try it on). Right-click or the star: wishlist.
--
--   B.Show() / B.Hide() / B.Toggle() / B.Frame()
--   B.SelectInstance(map) / B.SelectBoss(id) / B.Wishlist() / B.Search(text)
--   B.State() -> { mode = "boss" | "wishlist" | "search", map, boss, text }
--   B.Rows() -> the loot rows shown: { { item, encounter, entry }, ... }

local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local L = ns.Loot
local B = {}
ns.LootBrowser = B

local W, H, HEAD, PAD = 860, 560, 52, 14
local LEFT, MID = 220, 210
local ROW, LOOT_ROW = 26, 38
local frame, lists, search, header, sub, footer, slotPick, usableBtn
local state = { mode = "boss" }
local shown = {} -- the loot rows' data, for B.Rows()

local readable = ns.Readable

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

local function qualityColor(q)
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.r then return { c.r, c.g, c.b, 1 } end
	return T.Color("text")
end

local function levelsText(inst)
	if inst.levels then
		if inst.levels[1] == inst.levels[2] then return ("%d"):format(inst.levels[1]) end
		return ("%d-%d"):format(inst.levels[1], inst.levels[2])
	end
	return ""
end

-- Two bosses of one instance with different sizes: name the size.
local function bossLabel(inst, eid, e)
	local players = L.Players(eid)
	if players and players > 0 and inst then
		for _, other in ipairs(inst.encounters) do
			local p = L.Players(other)
			if other ~= eid and p ~= players then return ("%s  (%d)"):format(e.name, players) end
		end
	end
	return e.name
end

local function placeIn(child, rows, height)
	child:SetHeight(math.max(1, #rows * height))
end

---------------------------------------------------------------------------
-- A plain list row (instances, bosses)
---------------------------------------------------------------------------

local function makeRow(parent)
	local r = CreateFrame("Button", nil, parent)
	r:SetHeight(ROW)
	local hover = r:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	T.Paint(hover, "hover", 0)
	r.pick = r:CreateTexture(nil, "BORDER")
	r.pick:SetPoint("TOPLEFT", 0, 0)
	r.pick:SetPoint("BOTTOMLEFT", 0, 0)
	r.pick:SetWidth(2)
	T.Paint(r.pick, "accent")
	r.text = T.Text(r, "body", "text2")
	r.text:SetPoint("LEFT", 10, 0)
	r.text:SetPoint("RIGHT", -52, 0)
	r.text:SetJustifyV("MIDDLE")
	r.text:SetWordWrap(false)
	r.note = T.Text(r, "small", "muted")
	r.note:SetPoint("RIGHT", -8, 0)
	r.note:SetJustifyH("RIGHT")
	r.note:SetJustifyV("MIDDLE")
	local function look(p)
		local h = T.Color("hover")
		hover:SetColorTexture(h[1], h[2], h[3], 0.6 * p)
	end
	r:SetScript("OnEnter", function(self) A.Hover(self, true, look) end)
	r:SetScript("OnLeave", function(self) A.Hover(self, false, look) end)
	return r
end

-- A list in a scroll area: rows pooled, `fill(row, data)` paints one.
local function makeList(parent, width, rowHeight, make)
	local l = { rows = {}, rowHeight = rowHeight, make = make }
	l.scroll, l.child = T.Scroll(parent, rowHeight * 3)
	l.child:SetWidth(width)
	function l:Set(data, fill)
		for i, d in ipairs(data) do
			local r = self.rows[i]
			if not r then
				r = self.make(self.child)
				r:SetPoint("TOPLEFT", self.child, "TOPLEFT", 0, -(i - 1) * self.rowHeight)
				r:SetPoint("TOPRIGHT", self.child, "TOPRIGHT", 0, -(i - 1) * self.rowHeight)
				self.rows[i] = r
			end
			r:Show()
			fill(r, d)
		end
		for i = #data + 1, #self.rows do self.rows[i]:Hide() end
		placeIn(self.child, data, self.rowHeight)
		if self.scroll.PlaceThumb then self.scroll.PlaceThumb() end
	end
	return l
end

---------------------------------------------------------------------------
-- A loot row
---------------------------------------------------------------------------

local function makeLootRow(parent)
	local r = makeRow(parent)
	r:SetHeight(LOOT_ROW)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(28, 28)
	r.icon:SetPoint("LEFT", 8, 0)
	r.text:ClearAllPoints()
	r.text:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
	r.text:SetPoint("RIGHT", -96, 0)
	r.text:SetJustifyV("TOP")
	T.Font(r.text, "window")
	r.meta = T.Text(r, "small", "muted")
	r.meta:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 8, 0)
	r.meta:SetPoint("RIGHT", -96, 0)
	r.meta:SetWordWrap(false)
	r.note:ClearAllPoints()
	r.note:SetPoint("RIGHT", -34, 0)
	-- The wishlist mark: its own button, so hovering it never repaints it.
	r.star = CreateFrame("Button", nil, r)
	r.star:SetSize(22, 22)
	r.star:SetPoint("RIGHT", -6, 0)
	r.star.pwIcon = r.star:CreateTexture(nil, "ARTWORK")
	r.star.pwIcon:SetTexture(T.MEDIA .. "glyph-diamond")
	r.star.pwIcon:SetSize(14, 14)
	r.star.pwIcon:SetPoint("CENTER")
	r.star:SetScript("OnEnter", function(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(self:GetParent().pwWished and "On your wishlist: click to take it off" or "Add to your wishlist", 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	r.star:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	r:SetScript("OnEnter", function(self)
		if GameTooltip and self.pwLink then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetHyperlink, GameTooltip, self.pwLink)
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	r:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			L.Wish(self.pwItem, nil, self.pwEncounter)
			return
		end
		local modified = IsModifiedClick and readable(IsModifiedClick())
		if modified and HandleModifiedItemClick and self.pwLink then pcall(HandleModifiedItemClick, self.pwLink) end
	end)
	return r
end

local function fillLoot(r, d)
	local it = L.Item(d.item)
	r.pwItem, r.pwEncounter, r.pwLink = d.item, d.encounter, it.link
	r.icon:SetTexture(it.icon or 134400)
	r.text:SetText(it.name)
	local c = qualityColor(it.quality)
	r.text:SetTextColor(c[1], c[2], c[3], 1)
	local parts = {}
	if it.slot then parts[#parts + 1] = it.slot end
	if it.itemLevel and it.itemLevel > 0 then parts[#parts + 1] = ("item level %d"):format(it.itemLevel) end
	if it.level and it.level > 0 then parts[#parts + 1] = ("level %d"):format(it.level) end
	if d.where then parts[#parts + 1] = d.where end
	if not L.Usable(it) then parts[#parts + 1] = "not for your class" end
	r.meta:SetText(table.concat(parts, "  ·  "))
	local notes = {}
	local up, pct = L.Upgrade(it)
	if up then notes[#notes + 1] = pct and ("|cff7FD98F+%.1f%%|r"):format(pct) or "|cff7FD98Fupgrade|r" end
	if d.entry and d.entry.seen then notes[#notes + 1] = ("seen %d"):format(d.entry.seen) end
	r.note:SetText(table.concat(notes, "  "))
	local wished = L.Wished(d.item)
	local sc = wished and T.Color("accent") or T.Color("muted")
	r.star.pwIcon:SetVertexColor(sc[1], sc[2], sc[3], wished and 1 or 0.6)
	r.star:SetScript("OnClick", function() L.Wish(d.item, nil, d.encounter) end)
	r.pwWished = wished
end

---------------------------------------------------------------------------
-- What each column shows
---------------------------------------------------------------------------

local function instanceRows()
	local out = { { kind = "wishlist" }, { kind = "label", text = "Dungeons" } }
	local raids = false
	for _, inst in ipairs(L.Instances()) do
		if inst.raid and not raids then out[#out + 1] = { kind = "label", text = "Raids" } raids = true end
		out[#out + 1] = { kind = "instance", inst = inst }
	end
	return out
end

local function bossRows()
	local out = {}
	if state.mode ~= "boss" then return out end
	local inst = L.Instance(state.map)
	for _, eid in ipairs(inst and inst.encounters or {}) do
		local e = L.Encounter(eid)
		if e then out[#out + 1] = { eid = eid, e = e, inst = inst } end
	end
	return out
end

local function passes(d)
	local it = L.Item(d.item)
	if ns.Get("loot.usable") and not L.Usable(it) then return false end
	return L.SlotMatches(it, ns.Get("loot.slot"))
end

local function whereOf(eid)
	local e = eid and L.Encounter(eid)
	if not e then return nil end
	local inst = e.map and L.Instance(e.map)
	return inst and (e.name .. ", " .. inst.name) or e.name
end

local function lootRows()
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
	local kept = {}
	for _, d in ipairs(out) do if passes(d) then kept[#kept + 1] = d end end
	return kept, #out
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

function B.Render()
	if not frame then return end
	lists.left:Set(instanceRows(), function(r, d)
		r.pwData = d
		r:EnableMouse(d.kind ~= "label")
		local on = (d.kind == "wishlist" and state.mode == "wishlist") or (d.kind == "instance" and state.mode ~= "wishlist" and state.map == d.inst.map)
		r.pick:SetShown(on)
		if d.kind == "label" then
			T.Font(r.text, "label")
			T.Paint(r.text, "muted")
			r.text:SetText(d.text:upper())
			r.note:SetText("")
		elseif d.kind == "wishlist" then
			T.Font(r.text, on and "window" or "body")
			T.Paint(r.text, on and "flair" or "text2")
			r.text:SetText("Your wishlist")
			r.note:SetText(tostring(#L.Wishlist()))
			r:SetScript("OnClick", function() B.Wishlist() end)
		else
			T.Font(r.text, on and "window" or "body")
			T.Paint(r.text, on and "flair" or "text2")
			r.text:SetText(d.inst.name)
			r.note:SetText(d.inst.raid and (d.inst.size > 0 and tostring(d.inst.size) or "raid") or levelsText(d.inst))
			r:SetScript("OnClick", function() B.SelectInstance(d.inst.map) end)
		end
	end)

	lists.mid:Set(bossRows(), function(r, d)
		local on = state.boss == d.eid
		r.pick:SetShown(on)
		T.Font(r.text, on and "window" or "body")
		T.Paint(r.text, on and "flair" or "text2")
		r.text:SetText(bossLabel(d.inst, d.eid, d.e))
		r.note:SetText(#d.e.loot > 0 and tostring(#d.e.loot) or "")
		r:SetScript("OnClick", function() B.SelectBoss(d.eid) end)
	end)

	local rows, before = lootRows()
	shown = rows
	lists.right:Set(rows, fillLoot)

	-- The heading over the loot, and what to say when there is none.
	local title, line = "", ""
	if state.mode == "wishlist" then
		title = "Your wishlist"
		line = #rows > 0 and "Right-click an item, or its diamond, to take it off." or "Right-click any item, or click its diamond, to keep it here (this character's own list)."
	elseif state.mode == "search" then
		title = ("Search: %s"):format(state.text or "")
		line = #rows > 0 and ("%d found"):format(#rows) or "Nothing found. Item names the game has not loaded yet are searched by the data's names."
	elseif state.boss then
		local e = L.Encounter(state.boss)
		local inst = e and e.map and L.Instance(e.map)
		title = e and e.name or ""
		local bits = {}
		if inst then bits[#bits + 1] = inst.name end
		if e and e.kills > 0 then bits[#bits + 1] = ("you have seen %d kill%s"):format(e.kills, e.kills == 1 and "" or "s") end
		if e and #e.loot == 0 then
			bits[#bits + 1] = "no drops known yet: they fill in as you see them drop"
		end
		line = table.concat(bits, "  ·  ")
	end
	if before > #rows then line = line .. ("  ·  %d hidden by the filters"):format(before - #rows) end
	header:SetText(title)
	sub:SetText(line)
	slotPick:SetOptions(L.SLOT_FILTERS, ns.Get("loot.slot"))
	usableBtn:SetKind(ns.Get("loot.usable") and "accent" or "default")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function build()
	if frame then return frame end
	frame = CreateFrame("Frame", ns.ID.global .. "Browser", nil)
	frame:SetParent(UIParent)
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	T.Panel(frame)
	T.TrimLine(frame)
	if UISpecialFrames then table.insert(UISpecialFrames, ns.ID.global .. "Browser") end

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(T.MEDIA .. "icon")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 18, -16)
	local function tint() local a = T.Color("accent") icon:SetVertexColor(a[1], a[2], a[3]) end
	tint()
	ns.On("ACCENT_CHANGED", tint)
	local title = T.Text(frame, "wtitle", "flair")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetJustifyV("MIDDLE")
	title:SetText(ns.ID.name)

	local close = T.IconButton(frame, "close", "Close", function() B.Hide() end)
	close:SetPoint("TOPRIGHT", -10, -12)
	local settings = T.IconButton(frame, "settings", "Settings", function() ns.Fire("SHOW_CONFIG") end)
	settings:SetPoint("RIGHT", close, "LEFT", -4, 0)

	-- The search box.
	local box = CreateFrame("EditBox", ns.ID.global .. "Search", frame)
	box:SetSize(240, 26)
	box:SetPoint("RIGHT", settings, "LEFT", -10, 0)
	box:SetAutoFocus(false)
	box:SetTextInsets(10, 10, 0, 0)
	T.Panel(box, "bg2", "border")
	T.Font(box, "body")
	T.Paint(box, "text")
	local hint = T.Text(box, "small", "muted")
	hint:SetPoint("LEFT", 10, 0)
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
	search = box

	local headLine = frame:CreateTexture(nil, "BORDER")
	headLine:SetPoint("TOPLEFT", 1, -HEAD)
	headLine:SetPoint("TOPRIGHT", -1, -HEAD)
	headLine:SetHeight(1)
	T.Paint(headLine, "divider")

	-- The three columns.
	local left = CreateFrame("Frame", nil, frame)
	left:SetPoint("TOPLEFT", 1, -HEAD - 1)
	left:SetPoint("BOTTOMLEFT", 1, 1)
	left:SetWidth(LEFT)
	T.Panel(left, "bg2", false)
	local mid = CreateFrame("Frame", nil, frame)
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT", 0, 0)
	mid:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 0, 0)
	mid:SetWidth(MID)
	for _, col in ipairs({ left, mid }) do
		local edge = col:CreateTexture(nil, "BORDER")
		edge:SetPoint("TOPRIGHT")
		edge:SetPoint("BOTTOMRIGHT")
		edge:SetWidth(1)
		T.Paint(edge, "divider")
	end

	lists = {}
	lists.left = makeList(left, LEFT - 22, ROW, makeRow)
	lists.left.scroll:SetPoint("TOPLEFT", 6, -8)
	lists.left.scroll:SetPoint("BOTTOMRIGHT", -14, 8)
	lists.mid = makeList(mid, MID - 22, ROW, makeRow)
	lists.mid.scroll:SetPoint("TOPLEFT", 6, -8)
	lists.mid.scroll:SetPoint("BOTTOMRIGHT", -14, 8)

	local rightW = W - LEFT - MID - 2
	header = T.Text(frame, "heading", "flair")
	header:SetPoint("TOPLEFT", mid, "TOPRIGHT", PAD, -12)
	header:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	header:SetWordWrap(false)
	sub = T.Text(frame, "small", "muted")
	sub:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	sub:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)

	-- The filters.
	slotPick = T.Dropdown(frame, 140, function(v) ns.Set("loot.slot", v) end)
	slotPick:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -10)
	usableBtn = T.Button(frame, "Only for my class", "default", function() ns.Set("loot.usable", not ns.Get("loot.usable")) end)
	usableBtn:SetPoint("LEFT", slotPick, "RIGHT", 8, 0)

	lists.right = makeList(frame, rightW - PAD * 2 - 10, LOOT_ROW, makeLootRow)
	lists.right.scroll:SetPoint("TOPLEFT", slotPick, "BOTTOMLEFT", 0, -10)
	lists.right.scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD - 8, 30)

	footer = T.Text(frame, "small", "muted")
	footer:SetPoint("BOTTOMLEFT", mid, "BOTTOMRIGHT", PAD, 10)
	footer:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
	footer:SetWordWrap(false)
	footer:SetText("Drops: QuestieDB's Forever data and what you see drop. No drop chances.")

	frame:SetScript("OnHide", function(self) A.Set(self, "alpha", 0) end)
	frame:Hide()
	return frame
end

---------------------------------------------------------------------------
-- Choosing
---------------------------------------------------------------------------

-- The instance you are standing in, else the first one.
local function startingMap()
	if GetInstanceInfo then
		local ok, _, _, _, _, _, _, _, map = pcall(GetInstanceInfo)
		map = ok and readable(map) or nil
		if map and L.Instance(map) then return map end
	end
	local first = L.Instances()[1]
	return first and first.map
end

function B.SelectInstance(map)
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
	if search and (search:GetText() or "") ~= "" then search:SetText("") end
	B.Render()
	return true
end

function B.SelectBoss(eid)
	local e = L.Encounter(eid)
	if not e then return false end
	state.mode, state.boss, state.map, state.text = "boss", eid, e.map or state.map, nil
	B.Render()
	return true
end

function B.Wishlist()
	state.mode, state.text = "wishlist", nil
	B.Render()
end

function B.Search(text)
	text = tostring(text or "")
	if text:gsub("%s", "") == "" then
		if state.mode == "search" then B.SelectInstance(state.map or startingMap()) end
		return
	end
	state.mode, state.text = "search", text
	B.Render()
end

function B.State() return state end
function B.Rows() return shown end
function B.Frame() return frame end

function B.Show()
	build()
	if not state.map then B.SelectInstance(startingMap()) end
	if not frame:IsShown() then
		A.Set(frame, "alpha", 0)
		frame:SetAlpha(0)
		frame:Show()
		A.Fade(frame, 1, A.NORMAL)
	end
	B.Render()
end
function B.Hide()
	if not (frame and frame:IsShown()) then return end
	A.Fade(frame, 0, A.FAST, function() if A.Get(frame, "alpha") == 0 then frame:Hide() end end)
end
function B.Toggle() if frame and frame:IsShown() then B.Hide() else B.Show() end end
function B.IsShown() return frame ~= nil and frame:IsShown() end

local function refresh() if frame and frame:IsShown() then B.Render() end end
ns.On("LOOT_SEEN", refresh)
ns.On("ITEMS_CHANGED", refresh)
ns.On("WISHLIST_CHANGED", refresh)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^loot%.") or path == "*") then refresh() end
end)
