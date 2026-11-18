-- COPIED from PathwiseUI/Minimap.lua by tools/kit.js: do not edit here.
-- Edit PathwiseUI/Minimap.lua, then run npm run kit.
-- A Pathwise addon's minimap button (ns.ID: Pathwise UI, Pathwise Heal): a
-- dark disc with a thin ring and the Pathwise emblem, its star and path in
-- the addon's logo colour (ns.ID.color), so each addon's button is told apart
-- on the minimap; the accent if it has none. Click: the options; right click:
-- a menu of the options pages and Move everything; drag: around the rim.
--
-- With two or more Pathwise addons, their buttons share one: a Pathwise
-- button on the rim that opens a tray holding the others (the
-- "minimap.grouped" setting, on by default; each addon can keep its own
-- button out). The addons each carry their own copy of this file, so they
-- meet in one global table, _G.PathwiseMinimapGroup (see "The group" below);
-- Pathwise (the guide) joins it too (Pathwise/UI/MinimapButton.lua).
-- Shared file (see Core.lua): edit it here, then run npm run kit.

local ADDON, ns = ...
local T = ns.Theme
local M = {}
ns.Minimap = M

ns.Defaults("minimap", { shown = true, grouped = true, angle = ns.ID.minimapAngle or 135 })

local button
local menu, catcher

-- The right-click menu: a tree of what you can do from here. The options
-- pages (each opens straight to that page), then Move everything (Lock
-- everything while things are unlocked).
function M.Items()
	local items = { { label = "Options", heading = true } }
	local pages = ns.Config and ns.Config.CATEGORIES or {}
	for _, c in ipairs(pages) do
		if c.key and c.name then
			items[#items + 1] = { label = c.name, indent = true, run = function() ns.Config.Show(c.key) end }
		end
	end
	if ns.Movers then
		local on = ns.Movers.IsActive()
		items[#items + 1] = { label = on and "Lock everything" or "Move everything", run = function()
			ns.Movers.All(not on)
			if not on and ns.Config and ns.Config.Hide then ns.Config.Hide() end
		end }
	end
	return items
end

function M.CloseMenu()
	if menu then menu:Hide() end
	if catcher then catcher:Hide() end
end

local ROW = 22
function M.OpenMenu()
	if not menu then
		menu = CreateFrame("Frame", ns.ID.global .. "MinimapMenu", UIParent)
		menu:SetFrameStrata("FULLSCREEN_DIALOG")
		menu:SetClampedToScreen(true)
		T.Panel(menu, "bg", "border", 0.98, T.RADIUS.card)
		menu.rows = {}
		catcher = CreateFrame("Button", nil, UIParent)
		catcher:SetAllPoints(UIParent)
		catcher:SetFrameStrata("FULLSCREEN")
		catcher:RegisterForClicks("AnyUp")
		catcher:SetScript("OnClick", M.CloseMenu)
	end
	local items = M.Items()
	for i, item in ipairs(items) do
		local r = menu.rows[i]
		if not r then
			r = CreateFrame("Button", nil, menu)
			r:SetHeight(ROW)
			r.ground = T.Round(r, { 1, 1, 1, 0 }, false, 4) -- the hover, rounded inside the menu's corners
			r.text = T.Text(r, "button", "text2")
			r.text:SetJustifyV("MIDDLE")
			r:SetScript("OnLeave", function(b) b.ground:SetColorTexture(1, 1, 1, 0) end)
			menu.rows[i] = r
		end
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * ROW)
		r:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * ROW)
		r.text:ClearAllPoints()
		r.text:SetPoint("LEFT", item.indent and 22 or 10, 0)
		r.text:SetText(item.label)
		T.TextColor(r.text, item.heading and "muted" or "text")
		r.item = item
		r:SetScript("OnEnter", function(b)
			if b.item.heading then return end
			local c = T.Color("hover") b.ground:SetColorTexture(c[1], c[2], c[3], 0.9)
		end)
		r:SetScript("OnClick", function(b)
			if b.item.heading then return end
			M.CloseMenu()
			b.item.run()
		end)
		r:Show()
	end
	for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
	menu:SetSize(190, #items * ROW + 8)
	menu:ClearAllPoints()
	menu:SetPoint("TOPRIGHT", button, "BOTTOMLEFT", 0, 0)
	catcher:Show()
	menu:Show()
end
function M.Menu() return menu end

-- The mark's colour: the addon's logo colour, else your accent.
function M.Color()
	return ns.ID.color and T.Hex(ns.ID.color) or T.Color("accent")
end

function M.Offset(angle, width)
	local r = (width or 140) / 2 + 6
	local a = math.rad(angle)
	return math.cos(a) * r, math.sin(a) * r
end

-- The angle of the cursor around the minimap's centre, in degrees (0 east,
-- counter-clockwise), or nil.
function M.CursorAngle()
	local cx, cy = Minimap:GetCenter()
	if not (cx and GetCursorPosition) then return nil end
	local s = Minimap:GetEffectiveScale() or 1
	local mx, my = GetCursorPosition()
	local deg = math.deg(math.atan2(my / s - cy, mx / s - cx))
	if deg < 0 then deg = deg + 360 end
	return math.floor(deg + 0.5)
end

-- A disc in the Pathwise look with the emblem: the buttons, the group's too.
-- Returns the button; button.logo is the emblem, button.icon its star (the
-- coloured part), button.ring the ring.
local function disc(name, color)
	local b = CreateFrame("Button", name, nil)
	b:SetParent(Minimap)
	b:SetSize(32, 32)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b.pwTrayed, b.pwTrayClick = false, false -- in the group's tray; its wrapped click
	local ground = b:CreateTexture(nil, "BACKGROUND")
	ground:SetTexture(T.MEDIA .. "dot-done")
	ground:SetAllPoints()
	local ring = b:CreateTexture(nil, "BORDER")
	ring:SetTexture(T.MEDIA .. "dot-open")
	ring:SetAllPoints()
	local logo = T.Logo(b, 22)
	logo:SetPoint("CENTER")
	function b:Tint()
		local bg = T.Color("bg")
		ground:SetVertexColor(bg[1], bg[2], bg[3], 0.95)
		local e = T.Color("border")
		ring:SetVertexColor(e[1], e[2], e[3])
		logo:Paint(color())
	end
	b:Tint()
	ns.On("ACCENT_CHANGED", function() b:Tint() end)
	b.logo, b.icon, b.ring = logo, logo.glow, ring
	b.look = function(p)
		local r, g, bl = ns.Anim.Mix(T.Color("border"), color(), p)
		ring:SetVertexColor(r, g, bl)
		logo:SetSize(22 + 2 * p, 22 + 2 * p)
	end
	return b
end

---------------------------------------------------------------------------
-- The group: one Pathwise button for every Pathwise addon's
---------------------------------------------------------------------------
-- _G.PathwiseMinimapGroup, made by whichever addon loads first:
--   members[key] = { key, name, order, button, shown(), grouped(), place(),
--                    angle(), setAngle(deg) }
--   Join(member), Layout(), Open(), Close(), Toggle(), IsOpen()
-- The newest copy of this code (GROUP_VERSION) provides the functions; a
-- member is plain data, so an older or newer copy can lay it out.
-- With two or more members grouped (and shown), they leave the rim for a
-- tray beside the group's button, which sits where the first of them sat
-- (Pathwise, then Pathwise UI, ... ; dragging it moves that one's place).

local GROUP_VERSION = 1
local G = _G.PathwiseMinimapGroup
if type(G) ~= "table" then
	G = { members = {}, version = 0 }
	_G.PathwiseMinimapGroup = G
end
G.members = G.members or {}

if (G.version or 0) < GROUP_VERSION then
	G.version = GROUP_VERSION
	local SIZE, GAP, PAD, COLS = 32, 4, 6, 4

	local function grouped()
		local list = {}
		for _, m in pairs(G.members) do
			if m.button and m.shown() and m.grouped() then list[#list + 1] = m end
		end
		table.sort(list, function(a, b) return (a.order or 99) < (b.order or 99) end)
		return list
	end
	G.Grouped = grouped

	-- A member's own click, then the tray closes (not for a right click: its
	-- menu opens beside it).
	local function wrap(b)
		local inner = b:GetScript("OnClick")
		if inner == b.pwTrayClick then return end
		b.pwTrayClick = function(self, which, ...)
			if inner then inner(self, which, ...) end
			if which ~= "RightButton" and self.pwTrayed then G.Close() end
		end
		b:SetScript("OnClick", b.pwTrayClick)
	end

	local function place(list)
		local tray, gb = G.tray, G.button
		local n = #list
		local cols = math.min(COLS, n)
		local rows = math.ceil(n / cols)
		tray:SetSize(cols * SIZE + (cols - 1) * GAP + 2 * PAD, rows * SIZE + (rows - 1) * GAP + 2 * PAD)
		for i, m in ipairs(list) do
			local b = m.button
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			b:SetParent(tray)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", tray, "TOPLEFT", PAD + col * (SIZE + GAP), -PAD - row * (SIZE + GAP))
			b:SetFrameLevel((tray:GetFrameLevel() or 1) + 2)
			b:Show()
			wrap(b)
		end
		-- Away from the minimap: to the right of a button on its right half.
		local x = M.Offset(list[1].angle() or 135, Minimap:GetWidth())
		tray:ClearAllPoints()
		if x >= 0 then tray:SetPoint("LEFT", gb, "RIGHT", 4, 0)
		else tray:SetPoint("RIGHT", gb, "LEFT", -4, 0) end
	end

	function G.Layout()
		local list = grouped()
		local together = #list >= 2
		local inTray = {}
		if together then for _, m in ipairs(list) do inTray[m] = true end end
		-- Everyone else: on the rim, as before.
		for _, m in pairs(G.members) do
			local b = m.button
			if b and not inTray[m] then
				b.pwTrayed = false
				b:SetParent(Minimap)
				b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
				m.place()
				b:SetShown(m.shown() and true or false)
			end
		end
		if not together then
			if G.button then G.button:Hide() end
			if G.tray then G.tray:Hide() end
			return
		end
		if not G.button then G.Build() end
		local lead = list[1]
		local x, y = M.Offset(lead.angle() or 135, Minimap:GetWidth())
		G.button:ClearAllPoints()
		G.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
		G.button:Show()
		G.list = list
		for _, m in ipairs(list) do m.button.pwTrayed = true end
		place(list)
		G.tray:SetShown(G.open and true or false)
	end

	function G.IsOpen() return G.open and true or false end
	function G.Open() G.open = true G.Layout() end
	function G.Close() G.open = false if G.tray then G.tray:Hide() end end
	function G.Toggle() if G.open then G.Close() else G.Open() end end

	function G.Join(m)
		G.members[m.key] = m
		G.Layout()
	end

	-- The group's button (the Pathwise emblem in your accent) and its tray.
	function G.Build()
		local b = disc("PathwiseMinimapGroupButton", function() return T.Color("accent") end)
		b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 9)
		b:SetScript("OnClick", function() G.Toggle() end)
		b:SetScript("OnEnter", function(self)
			ns.Anim.Hover(self, true, self.look)
			if GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_LEFT")
				GameTooltip:SetText("Pathwise", 1, 1, 1)
				for _, m in ipairs(G.list or {}) do GameTooltip:AddLine(m.name, 0.85, 0.88, 0.92) end
				GameTooltip:AddLine("Click: " .. (G.open and "hide" or "show") .. " their buttons", 0.6, 0.69, 0.75)
				GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
				GameTooltip:Show()
			end
		end)
		b:SetScript("OnLeave", function(self)
			ns.Anim.Hover(self, false, self.look)
			if GameTooltip then GameTooltip:Hide() end
		end)
		b:SetScript("OnDragStart", function(self)
			self:SetScript("OnUpdate", function()
				local lead = G.list and G.list[1]
				local deg = M.CursorAngle()
				if lead and deg then lead.setAngle(deg) G.Layout() end
			end)
		end)
		b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
		local tray = CreateFrame("Frame", "PathwiseMinimapTray", nil)
		tray:SetParent(Minimap)
		tray:SetFrameStrata("MEDIUM")
		tray:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
		tray:SetClampedToScreen(true)
		T.Panel(tray, "bg", "border", 0.96, T.RADIUS.card)
		tray:Hide()
		G.button, G.tray = b, tray
	end
end

---------------------------------------------------------------------------
-- This addon's button
---------------------------------------------------------------------------

local function place()
	local x, y = M.Offset(ns.Get("minimap.angle") or ns.ID.minimapAngle or 135, Minimap:GetWidth())
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Where this addon stands among the Pathwise addons (Pathwise itself is 0).
local function order()
	for i, g in ipairs(ns.PEERS or {}) do if g == ns.ID.global then return i end end
	return 50
end

local function build()
	button = disc(ns.ID.global .. "MinimapButton", M.Color)
	button:SetScript("OnClick", function(_, which)
		if which == "RightButton" then
			if menu and menu:IsShown() then M.CloseMenu() else M.OpenMenu() end
			return
		end
		M.CloseMenu()
		ns.Fire("SHOW_CONFIG")
	end)
	button:SetScript("OnEnter", function(self)
		ns.Anim.Hover(self, true, self.look)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(ns.ID.name, 1, 1, 1)
			GameTooltip:AddLine("Click: options", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Right click: pages and Move everything", 0.6, 0.69, 0.75)
			if not self.pwTrayed then GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75) end
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		ns.Anim.Hover(self, false, self.look)
		if GameTooltip then GameTooltip:Hide() end
	end)
	button:SetScript("OnDragStart", function(self)
		if self.pwTrayed then return end -- in the tray it stays put
		self:SetScript("OnUpdate", function()
			local deg = M.CursorAngle()
			if deg then ns.Set("minimap.angle", deg) end
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function M.Refresh()
	if not Minimap then return end
	if not button then
		build()
		G.Join({
			key = ns.ID.global, name = ns.ID.name, order = order(), button = button,
			shown = function() return ns.Get("minimap.shown") and true or false end,
			grouped = function() return ns.Get("minimap.grouped") ~= false end,
			place = place,
			angle = function() return ns.Get("minimap.angle") or ns.ID.minimapAngle or 135 end,
			setAngle = function(deg) ns.Set("minimap.angle", deg) end,
		})
		return
	end
	G.Layout()
end
function M.Button() return button end
function M.Group() return G end

ns.On("READY", M.Refresh)
ns.On("SETTING_CHANGED", function(path)
	if path == "minimap.shown" or path == "minimap.angle" or path == "minimap.grouped" or path == "*" then
		if button then M.Refresh() end
	end
end)
