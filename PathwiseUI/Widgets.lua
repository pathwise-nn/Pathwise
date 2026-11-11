-- Pathwise UI's widgets, drawn the Signature way (Pathwise v2): rounded
-- grounds with crisp 1-pixel borders, Inter text, quiet buttons that ease into their hover
-- color, switches that slide, segmented choices with a moving highlight,
-- smooth sliders and smooth scrolling. Anything painted in the accent is
-- remembered and repainted when the accent changes, so a new color shows at
-- once, without a reload.

-- Shared file (see Core.lua): edit it here, then run npm run kit.
local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim

local painted = setmetatable({}, { __mode = "k" }) -- texture, font string or border -> color name
local function paint(obj, name, alpha)
	local c = type(name) == "table" and name or T.Color(name)
	local a = alpha or c[4]
	if obj.edges and obj.SetColor then obj:SetColor(c[1], c[2], c[3], a)
	elseif obj.SetColorTexture then obj:SetColorTexture(c[1], c[2], c[3], a)
	elseif obj.SetTextColor then obj:SetTextColor(c[1], c[2], c[3], a) end
	if type(name) == "string" then painted[obj] = { name, alpha } else painted[obj] = nil end
end
T.Paint = paint
function T.TextColor(fs, name) paint(fs, name) end

-- Paint a mix of two named colors (p 0..1), e.g. mid-hover. Accent mixes
-- are repainted from the same progress when the accent changes.
local function blend(obj, from, to, p, alpha)
	local a, b = T.Color(from), T.Color(to)
	local r, g, bl, al = A.Mix(a, b, p)
	if alpha then al = alpha end
	if obj.edges and obj.SetColor then obj:SetColor(r, g, bl, al)
	elseif obj.SetColorTexture then obj:SetColorTexture(r, g, bl, al)
	elseif obj.SetTextColor then obj:SetTextColor(r, g, bl, al) end
	if p <= 0 then painted[obj] = { from, alpha } elseif p >= 1 then painted[obj] = { to, alpha } else painted[obj] = nil end
end
T.Blend = blend

-- ACCENT_CHANGED fires for any color change (the accent, a scheme, one of
-- your own): everything painted by name is painted again.
ns.On("ACCENT_CHANGED", function()
	for obj, p in pairs(painted) do paint(obj, p[1], p[2]) end
end)

function T.Font(fs, role, size, flags)
	local r = T.TYPE[role] or T.TYPE.body
	if not fs:SetFont(T.FONTS[r[1]], size or r[2], flags or "") then fs:SetFont("Fonts\\FRIZQT__.TTF", size or r[2], flags or "") end
end

-- Text over a colored bar (names, health and power numbers, cast names): a
-- black outline so it reads on any color ("units.outline"), else a shadow.
-- Remembered, so switching the setting redraws them all.
ns.Defaults("units", { outline = true })
local barTexts = setmetatable({}, { __mode = "k" })
function T.BarText(fs, role, size)
	barTexts[fs] = { role, size }
	local on = ns.Get("units.outline")
	T.Font(fs, role, size, on and "OUTLINE" or "")
	fs:SetShadowOffset(on and 0 or 1, on and 0 or -1)
	fs:SetShadowColor(0, 0, 0, on and 0 or 0.8)
	return fs
end
-- Text on the dark ground (the slim unit frames, like Pathwise's windows):
-- no outline, no shadow, in a color of the scheme. Forgets any BarText.
function T.PlainText(fs, role, color, size)
	barTexts[fs] = nil
	T.Font(fs, role, size, "")
	fs:SetShadowOffset(0, 0)
	fs:SetShadowColor(0, 0, 0, 0)
	if color then T.Paint(fs, color) end
	return fs
end

ns.On("SETTING_CHANGED", function(path)
	if path == "units.outline" or path == "*" or path == "units.*" then
		for fs, r in pairs(barTexts) do T.BarText(fs, r[1], r[2]) end
	end
end)

function T.Text(parent, role, color, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	T.Font(fs, role)
	paint(fs, color or (T.TYPE[role] or T.TYPE.body)[3])
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	return fs
end

local grounds = setmetatable({}, { __mode = "k" }) -- windows whose ground follows the opacity setting

---------------------------------------------------------------------------
-- Rounded grounds and borders, as Pathwise draws them (v2)
---------------------------------------------------------------------------
-- The client has no rounded clipping, so the shape is pieced together: four
-- corners (Media/corner and corner-line, flipped by texture coordinates),
-- the strips between them and a middle. Windows take radius 10, cards,
-- menus and buttons 6. Unit frames, bars and nameplates stay square.
-- A proxy stands for the pieces, so a caller recolours it as it did the one
-- texture (ground:SetColorTexture) or border (border:SetColor) it held.

T.RADIUS = { window = 10, card = 6 }

local CORNERS = {
	-- point, texcoord left, right, top, bottom
	{ "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
	{ "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
}

local Pieces = {}
Pieces.__index = Pieces
-- Corners are white art, tinted; the rest are solid colors.
function Pieces:SetColorTexture(r, g, b, a)
	a = a or 1
	for _, t in ipairs(self.pieces) do
		if self.corners[t] then t:SetVertexColor(r, g, b, a) else t:SetColorTexture(r, g, b, a) end
	end
	self.color = { r, g, b, a }
end
Pieces.SetColor = Pieces.SetColorTexture
Pieces.SetVertexColor = Pieces.SetColorTexture
function Pieces:SetShown(on)
	self.shown = on and true or false
	for _, t in ipairs(self.pieces) do t:SetShown(self.shown) end
end
function Pieces:Show() self:SetShown(true) end
function Pieces:Hide() self:SetShown(false) end
function Pieces:IsShown() return self.shown end
function Pieces:SetAlpha(a) for _, t in ipairs(self.pieces) do t:SetAlpha(a) end end

local rounds = setmetatable({}, { __mode = "k" }) -- borders whose straight edges follow the pixel size

-- The pieces of a rounded shape on frame: kind "fill" or "line".
local function pieces(frame, kind, r)
	local p = setmetatable({ pieces = {}, corners = {}, shown = true, radius = r }, Pieces)
	local line = kind == "line"
	local function tex()
		local t = frame:CreateTexture(nil, line and "BORDER" or "BACKGROUND", nil, line and 0 or -8)
		T.NoSnap(t)
		p.pieces[#p.pieces + 1] = t
		return t
	end
	for _, c in ipairs(CORNERS) do
		local t = tex()
		t:SetTexture(T.MEDIA .. (not line and "corner" or (r >= 8 and "corner-line" or "corner-line-small")))
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		t:SetSize(r, r)
		t:SetPoint(c[1])
		p.corners[t] = true
	end
	if line then
		-- The four straight edges, one pixel wide (top, bottom, left, right).
		p.edges = {}
		for _, spec in ipairs({
			{ "TOPLEFT", r, 0, "TOPRIGHT", -r, 0 }, { "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0 },
			{ "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r }, { "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r },
		}) do
			local t = tex()
			t:SetPoint(spec[1], spec[2], spec[3])
			t:SetPoint(spec[4], spec[5], spec[6])
			p.edges[#p.edges + 1] = t
		end
		function p:Layout()
			local px = T.Pixel()
			self.edges[1]:SetHeight(px) self.edges[2]:SetHeight(px)
			self.edges[3]:SetWidth(px) self.edges[4]:SetWidth(px)
		end
		p:Layout()
		rounds[p] = true
	else
		-- The middle (full width, between the corners' rows), and the strips
		-- between the corners, top and bottom.
		local mid = tex()
		mid:SetPoint("TOPLEFT", 0, -r)
		mid:SetPoint("BOTTOMRIGHT", 0, r)
		local top = tex()
		top:SetPoint("TOPLEFT", r, 0)
		top:SetPoint("TOPRIGHT", -r, 0)
		top:SetHeight(r)
		local bottom = tex()
		bottom:SetPoint("BOTTOMLEFT", r, 0)
		bottom:SetPoint("BOTTOMRIGHT", -r, 0)
		bottom:SetHeight(r)
	end
	return p
end
ns.On("PIXEL_CHANGED", function() for p in pairs(rounds) do p:Layout() end end)

-- A rounded ground and 1-pixel border on frame, with no shading.
-- ground/border: color names or { r, g, b, a }; false: none (border nil:
-- "border"). radius: T.RADIUS.card when nil. alpha: the ground's.
-- -> the ground (frame.pwGround); the border is frame.pwBorder.
function T.Round(frame, ground, border, radius, alpha)
	local r = radius or T.RADIUS.card
	frame.pwRadius = r
	local bg
	if ground ~= false then
		bg = pieces(frame, "fill", r)
		paint(bg, ground or "bg", alpha)
		frame.pwGround = bg
	end
	if border ~= false then
		local b = pieces(frame, "line", r)
		paint(b, border or "border")
		frame.pwBorder = b
	end
	return bg
end

-- Recolour a rounded (or square) frame, as Pathwise's T.PaintRound does.
function T.PaintRound(frame, ground, border, alpha, borderAlpha)
	if ground and frame.pwGround then paint(frame.pwGround, ground, alpha) end
	if border and frame.pwBorder then paint(frame.pwBorder, border, borderAlpha) end
end
---------------------------------------------------------------------------
-- Wayfarer's shading: a gradient on a texture, an etched edge, a bar's sheen
---------------------------------------------------------------------------

-- A vertical (or horizontal) gradient from c1 to c2 ({ r, g, b, a } each);
-- "VERTICAL" runs bottom (c1) to top (c2). Quietly nothing on a client
-- without gradients.
function T.Gradient(tex, orientation, c1, c2)
	tex:SetColorTexture(1, 1, 1, 1)
	if CreateColor and tex.SetGradient then
		local ok = pcall(tex.SetGradient, tex, orientation, CreateColor(c1[1], c1[2], c1[3], c1[4]), CreateColor(c2[1], c2[2], c2[3], c2[4]))
		if ok then return true end
	end
	if tex.SetGradientAlpha then
		local ok = pcall(tex.SetGradientAlpha, tex, orientation, c1[1], c1[2], c1[3], c1[4], c2[1], c2[2], c2[3], c2[4])
		if ok then return true end
	end
	tex:SetColorTexture(0, 0, 0, 0)
	return false
end

local etched = setmetatable({}, { __mode = "k" })
-- Etched: a faint highlight along the top inside edge, a shadow along the
-- bottom, and a soft sheen down the ground (lighter at the top).
-- On a rounded frame the sheen is left out (it would show square corners)
-- and the two lines stop where the corners start.
function T.Etch(frame)
	if frame.pwEtch then return frame.pwEtch end
	local e = {}
	local r = frame.pwRadius or 0
	local x = r > 0 and r or 1
	if r == 0 then
		e.sheen = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
		e.sheen:SetPoint("TOPLEFT", 1, -1)
		e.sheen:SetPoint("BOTTOMRIGHT", -1, 1)
		T.Gradient(e.sheen, "VERTICAL", { 0, 0, 0, 0.10 }, { 1, 1, 1, 0.035 })
	end
	e.top = frame:CreateTexture(nil, "BORDER", nil, 1)
	e.top:SetPoint("TOPLEFT", x, -1)
	e.top:SetPoint("TOPRIGHT", -x, -1)
	e.top:SetHeight(T.Pixel())
	e.top:SetColorTexture(1, 1, 1, 0.06)
	e.bottom = frame:CreateTexture(nil, "BORDER", nil, 1)
	e.bottom:SetPoint("BOTTOMLEFT", x, 1)
	e.bottom:SetPoint("BOTTOMRIGHT", -x, 1)
	e.bottom:SetHeight(T.Pixel())
	e.bottom:SetColorTexture(0, 0, 0, 0.35)
	for _, t in pairs(e) do T.NoSnap(t) end
	frame.pwEtch = e
	etched[e] = true
	return e
end
ns.On("PIXEL_CHANGED", function(px) for e in pairs(etched) do e.top:SetHeight(px) e.bottom:SetHeight(px) end end)

-- A bar's sheen: lighter at the top of its fill, darker at the bottom. It
-- rides on the fill texture, so it moves with the value.
function T.Sheen(bar)
	local fill = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not fill or bar.pwSheen then return end
	local top = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	top:SetPoint("TOPLEFT", fill, "TOPLEFT")
	top:SetPoint("BOTTOMRIGHT", fill, "RIGHT")
	T.Gradient(top, "VERTICAL", { 1, 1, 1, 0 }, { 1, 1, 1, 0.16 })
	local bottom = bar:CreateTexture(nil, "ARTWORK", nil, 2)
	bottom:SetPoint("TOPLEFT", fill, "LEFT")
	bottom:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT")
	T.Gradient(bottom, "VERTICAL", { 0, 0, 0, 0.16 }, { 0, 0, 0, 0 })
	bar.pwSheen = { top, bottom }
end

-- A line in the trim color that fades out at both ends (the window's top).
local trimLines = setmetatable({}, { __mode = "k" })
local function paintTrimLine(l)
	local c = T.Color("flair")
	T.Gradient(l.left, "HORIZONTAL", { c[1], c[2], c[3], 0 }, { c[1], c[2], c[3], l.alpha })
	T.Gradient(l.right, "HORIZONTAL", { c[1], c[2], c[3], l.alpha }, { c[1], c[2], c[3], 0 })
end
function T.TrimLine(frame, alpha)
	local l = { alpha = alpha or 0.7 }
	local x = math.max(1, frame.pwRadius or 0) -- clear of round corners
	l.left = frame:CreateTexture(nil, "ARTWORK", nil, 3)
	l.left:SetPoint("TOPLEFT", x, -1)
	l.left:SetPoint("BOTTOMRIGHT", frame, "TOP", 0, -1 - T.Pixel())
	l.right = frame:CreateTexture(nil, "ARTWORK", nil, 3)
	l.right:SetPoint("TOPLEFT", frame, "TOP", 0, -1)
	l.right:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -x, -1 - T.Pixel())
	trimLines[l] = true
	paintTrimLine(l)
	return l
end
-- A rule in the trim color fading out to the right (beside a heading).
local fades = setmetatable({}, { __mode = "k" })
function T.FadeRule(tex, alpha)
	fades[tex] = alpha or 0.35
	local c = T.Color("flair")
	T.Gradient(tex, "HORIZONTAL", { c[1], c[2], c[3], fades[tex] }, { c[1], c[2], c[3], 0 })
	return tex
end
ns.On("ACCENT_CHANGED", function()
	for l in pairs(trimLines) do paintTrimLine(l) end
	for t, a in pairs(fades) do T.FadeRule(t, a) end
end)

-- A ground with a 1-pixel border and the etched shading.
-- -> the ground (frame.pwGround); the border is frame.pwBorder.
-- radius: rounded corners (T.Round); nil: T.RADIUS.window for a window's
-- ground (ground nil, which follows the opacity setting), else square (0).
-- Unit frames, bars and nameplates leave it square.
function T.Panel(frame, ground, border, alpha, radius)
	local r = radius
	if r == nil then r = ground == nil and T.RADIUS.window or 0 end
	if r > 0 then
		local bg = T.Round(frame, ground or "bg", border, r, alpha or (ground == nil and ns.Get("look.opacity")) or nil)
		if ground == nil then grounds[frame] = true end
		if border ~= false then T.Etch(frame) end
		return bg
	end
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	paint(bg, ground or "bg", alpha or (ground == nil and ns.Get("look.opacity")) or nil)
	frame.pwGround = bg
	if ground == nil then grounds[frame] = true end
	if border ~= false then
		local b = T.Border(frame, "BORDER")
		paint(b, border or "border")
		frame.pwBorder = b
		T.Etch(frame)
	end
	return bg
end
function T.SetBorder(frame, name, alpha)
	if frame.pwBorder then paint(frame.pwBorder, name, alpha) end
end
ns.On("SETTING_CHANGED", function(path)
	if path == "look.opacity" then
		for f in pairs(grounds) do if f.pwGround then paint(f.pwGround, "bg", ns.Get("look.opacity")) end end
	end
end)

-- A thin accent line along the top of a window (clear of round corners).
function T.AccentLine(frame)
	local x = math.max(1, frame.pwRadius or 0)
	local t = frame:CreateTexture(nil, "ARTWORK")
	t:SetPoint("TOPLEFT", x, -1)
	t:SetPoint("TOPRIGHT", -x, -1)
	t:SetHeight(2)
	paint(t, "accent")
	return t
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

-- A text button: kind "default" or "accent" (the picked choice, the main
-- action). Hover eases the ground, border and text over 0.12 s.
function T.Button(parent, label, kind, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	T.Panel(b, "bg2", "border", nil, T.RADIUS.card)
	local text = T.Text(b, "button", kind == "accent" and "accent" or "text2")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetText(label)
	b.pwText = text
	local function look(p)
		blend(b.pwGround, "bg2", "hover", p)
		if b.pwKind == "accent" then
			blend(b.pwBorder, "accent", "accentHover", p, 0.6 + 0.4 * p)
			blend(text, "accent", "accentHover", p)
		else
			blend(b.pwBorder, "border", "muted", p)
			blend(text, "text2", "text", p)
		end
	end
	function b:SetKind(k)
		self.pwKind = k
		look(A.Get(self, "hover") or 0)
	end
	b:SetKind(kind)
	b:SetScript("OnEnter", function(self) A.Hover(self, true, look) end)
	b:SetScript("OnLeave", function(self) A.Hover(self, false, look) end)
	b:SetScript("OnMouseDown", function() text:SetPoint("CENTER", 0, -1) end)
	b:SetScript("OnMouseUp", function() text:SetPoint("CENTER") end)
	if onClick then b:SetScript("OnClick", onClick) end
	function b:Fit() self:SetWidth(math.max(64, (text:GetStringWidth() or 30) + 28)) end
	b:Fit()
	return b
end

-- An icon-only button: a glyph (Media/glyph-<name>.tga) tinted secondary,
-- easing to primary on hover.
function T.IconButton(parent, glyph, tip, onClick, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size or 24, size or 24)
	local hover = T.Round(b, "hover", false, T.RADIUS.card, 0)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(T.MEDIA .. "glyph-" .. glyph)
	icon:SetSize(16, 16)
	icon:SetPoint("CENTER")
	b.pwIcon = icon
	-- b.pwTint(p) -> a color of its own for the glyph (the pin's accent).
	local function look(p)
		local h = T.Color("hover")
		hover:SetColorTexture(h[1], h[2], h[3], p)
		local tint = b.pwTint and b.pwTint(p)
		if tint then icon:SetVertexColor(tint[1], tint[2], tint[3]) return end
		local r, g, bl = A.Mix(T.Color("text2"), T.Color("text"), p)
		icon:SetVertexColor(r, g, bl)
	end
	b.pwLook = look
	look(0)
	b:SetScript("OnEnter", function(self)
		A.Hover(self, true, look)
		if tip and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_TOP") GameTooltip:SetText(tip, 1, 1, 1) GameTooltip:Show() end
	end)
	b:SetScript("OnLeave", function(self)
		A.Hover(self, false, look)
		if GameTooltip then GameTooltip:Hide() end
	end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- The pin (as Pathwise's v2): anchors a window where it is. Click to pin or
-- unpin; pinned, it is tinted in the accent, and the window ignores drags
-- and its grip. `path` is the window's setting ("config.locked"); the
-- window checks it when dragged (T.Movable).
local pins = setmetatable({}, { __mode = "k" })
function T.PinButton(parent, path, size)
	local b = T.IconButton(parent, "pin", nil, function() ns.Set(path, not ns.Get(path)) end, size)
	b.pwPath = path
	b.pwTint = function(p)
		if ns.Get(path) then return T.Color("accent") end
		return { A.Mix(T.Color("text2"), T.Color("text"), p) }
	end
	local enter = b:GetScript("OnEnter")
	b:SetScript("OnEnter", function(self)
		enter(self)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(ns.Get(path) and "Pinned in place" or "Pin in place", 1, 1, 1)
			GameTooltip:AddLine(ns.Get(path) and "Click to unpin, to drag and resize it again." or "Click so it cannot be dragged or resized by accident.", nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	pins[b] = true
	return b
end
-- Whether a window pinned with `path` may move now.
function T.Movable(path) return not ns.Get(path) end
local function repaintPins(path)
	for b in pairs(pins) do
		if path == b.pwPath or path == "*" or path == "profile.shared" or (path and path:match("%.%*$")) then b.pwLook(A.Get(b, "hover") or 0) end
	end
end
ns.On("SETTING_CHANGED", repaintPins)
ns.On("ACCENT_CHANGED", function() repaintPins("*") end)

-- The resize grip (as Pathwise's v2): the corner you drag to make a window
-- any size. The top-left corner stays put while the grip follows the cursor.
--   o = { minW, maxW, minH, maxH, lockPath,
--         onSize(w, h) while dragging, onDone(w, h) let go, onReset() right-click }
-- A pinned window (o.lockPath) does not resize. Returns the grip.
function T.Grip(frame, o)
	if frame.SetResizable then frame:SetResizable(true) end
	if frame.SetResizeBounds then frame:SetResizeBounds(o.minW, o.minH, o.maxW, o.maxH) end
	local g = CreateFrame("Button", nil, frame)
	g:SetSize(16, 16)
	g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
	g:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
	g.icon = g:CreateTexture(nil, "OVERLAY")
	g.icon:SetTexture(T.MEDIA .. "glyph-resize")
	g.icon:SetSize(12, 12)
	g.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	local st = {}
	g.pwState = st
	local function look()
		local c = T.Color(st.held and "accent" or (st.over and "text" or "muted"))
		g.icon:SetVertexColor(c[1], c[2], c[3], 1)
	end
	g.pwLook = look
	local function clamp(v, lo, hi) return math.min(hi or v, math.max(lo or v, v)) end
	local function cursor()
		local x, y = GetCursorPosition()
		local sc = frame:GetEffectiveScale() or 1
		return x / sc, y / sc
	end
	local function update()
		local x, y = cursor()
		local w = math.floor(clamp(st.w0 + (x - st.x0), o.minW, o.maxW) + 0.5)
		local h = math.floor(clamp(st.h0 + (st.y0 - y), o.minH, o.maxH) + 0.5)
		if w == st.w and h == st.h then return end
		st.w, st.h = w, h
		frame:SetSize(w, h)
		if o.onSize then o.onSize(w, h) end
	end
	g.pwUpdate = update
	local function stop()
		if not st.held then return end
		st.held = nil
		look()
		g:SetScript("OnUpdate", nil)
		if o.onDone then o.onDone(st.w or frame:GetWidth(), st.h or frame:GetHeight()) end
	end
	g:SetScript("OnMouseDown", function(_, button)
		if button and button ~= "LeftButton" then return end
		if o.lockPath and ns.Get(o.lockPath) then return end
		local l, t = frame:GetLeft(), frame:GetTop()
		if l and t then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
		end
		st.x0, st.y0 = cursor()
		st.w0, st.h0 = frame:GetWidth(), frame:GetHeight()
		st.w, st.h, st.held = nil, nil, true
		look()
		if GameTooltip then GameTooltip:Hide() end
		g:SetScript("OnUpdate", update)
	end)
	g:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and not st.held then
			if o.onReset and not (o.lockPath and ns.Get(o.lockPath)) then o.onReset() end
			return
		end
		stop()
	end)
	g:SetScript("OnHide", stop)
	g:SetScript("OnEnter", function(self)
		st.over = true
		look()
		if GameTooltip and not st.held then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:SetText("Resize", 1, 1, 1)
			if o.lockPath and ns.Get(o.lockPath) then
				GameTooltip:AddLine("Pinned: unpin it to resize.", nil, nil, nil, true)
			else
				GameTooltip:AddLine("Drag to change the width and height.", nil, nil, nil, true)
				GameTooltip:AddLine("Right-click: back to the usual size.", nil, nil, nil, true)
			end
			GameTooltip:Show()
		end
	end)
	g:SetScript("OnLeave", function()
		st.over = nil
		look()
		if GameTooltip then GameTooltip:Hide() end
	end)
	ns.On("ACCENT_CHANGED", look)
	look()
	return g
end

---------------------------------------------------------------------------
-- Switch: a square track with a square knob that slides, filled in the
-- accent when on (square like everything else in Pathwise UI)
---------------------------------------------------------------------------

function T.Switch(parent, onToggle)
	local s = CreateFrame("Button", nil, parent)
	s:SetSize(36, 20)
	-- The capsule: two round ends and the middle between them, one color.
	local track = {}
	for i, side in ipairs({ "LEFT", "RIGHT" }) do
		local cap = s:CreateTexture(nil, "BACKGROUND")
		cap:SetTexture(T.MEDIA .. "disc")
		cap:SetSize(20, 20)
		cap:SetPoint(side)
		track[i] = cap
	end
	local mid = s:CreateTexture(nil, "BACKGROUND")
	mid:SetPoint("TOPLEFT", 10, 0)
	mid:SetPoint("BOTTOMRIGHT", -10, 0)
	track[3] = mid
	-- The knob: a round disc with a soft shadow under it.
	local shadow = s:CreateTexture(nil, "ARTWORK", nil, 1)
	shadow:SetTexture(T.MEDIA .. "disc")
	shadow:SetSize(15, 15)
	shadow:SetVertexColor(0, 0, 0, 0.45)
	local knob = s:CreateTexture(nil, "ARTWORK", nil, 2)
	knob:SetTexture(T.MEDIA .. "disc")
	knob:SetSize(14, 14)
	s.pwKnob, s.pwTrack = knob, track
	local function look(p)
		-- Off: a dark well; on: your accent. Solid colors, so the pieces join.
		local off = T.Color("bg")
		local r, g, b = A.Mix({ off[1] * 0.7, off[2] * 0.7, off[3] * 0.7 }, T.Color("accent"), p)
		track[1]:SetVertexColor(r, g, b, 1)
		track[2]:SetVertexColor(r, g, b, 1)
		mid:SetColorTexture(r, g, b, 1)
		local kr, kg, kb = A.Mix(T.Color(s.pwHover and "text" or "text2"), { 1, 1, 1 }, p)
		knob:SetVertexColor(kr, kg, kb, 1)
		knob:ClearAllPoints()
		knob:SetPoint("LEFT", s, "LEFT", 3 + p * 16, 0)
		shadow:ClearAllPoints()
		shadow:SetPoint("CENTER", knob, "CENTER", 0, -1)
	end
	s.pwLook = look
	-- on: the state; animate: slide there (else jump).
	function s:SetOn(on, animate)
		self.pwOn = on and true or false
		if animate then A.Tween(self, "on", self.pwOn and 1 or 0, A.FAST, look)
		else A.Set(self, "on", self.pwOn and 1 or 0, look) end
	end
	function s:IsOn() return self.pwOn end
	s:SetScript("OnClick", function(self)
		self:SetOn(not self.pwOn, true)
		if onToggle then onToggle(self.pwOn) end
		if self.pwOnToggle then self.pwOnToggle(self.pwOn) end
	end)
	s:SetScript("OnEnter", function(self) self.pwHover = true look(A.Get(self, "on") or 0) end)
	s:SetScript("OnLeave", function(self) self.pwHover = false look(A.Get(self, "on") or 0) end)
	ns.On("ACCENT_CHANGED", function() look(A.Get(s, "on") or 0) end)
	s:SetOn(false)
	return s
end

---------------------------------------------------------------------------
-- Dropdown: the current choice and an arrow; click for a menu of the rest
---------------------------------------------------------------------------

local openMenu -- the one menu open at a time
local catcher -- a click anywhere else closes it

local function closeMenu()
	if openMenu then
		local m = openMenu
		openMenu = nil
		m:Hide()
		if m.pwOwner then m.pwOwner.pwArrow:SetRotation(0) end
	end
	if catcher then catcher:Hide() end
end
T.CloseMenu = closeMenu

function T.Dropdown(parent, width, onPick)
	local d = CreateFrame("Button", nil, parent)
	d:SetSize(width or 160, 26)
	T.Panel(d, "bg2", "border", nil, T.RADIUS.card)
	local text = T.Text(d, "button", "text")
	text:SetPoint("LEFT", 10, 0)
	text:SetPoint("RIGHT", -24, 0)
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	d.pwText = text
	local arrow = d:CreateTexture(nil, "ARTWORK")
	arrow:SetTexture(T.MEDIA .. "glyph-expand")
	arrow:SetSize(14, 14)
	arrow:SetPoint("RIGHT", -6, 0)
	local function tintArrow() local c = T.Color("text2") arrow:SetVertexColor(c[1], c[2], c[3]) end
	tintArrow()
	ns.On("ACCENT_CHANGED", tintArrow)
	d.pwArrow = arrow
	local function look(p)
		blend(d.pwGround, "bg2", "hover", p)
		blend(d.pwBorder, "border", "muted", p)
	end
	d:SetScript("OnEnter", function(self) A.Hover(self, true, look) end)
	d:SetScript("OnLeave", function(self) A.Hover(self, false, look) end)

	-- The menu: on top of everything (not clipped by the scrolling page).
	local menu = CreateFrame("Frame", nil, UIParent)
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetClampedToScreen(true)
	T.Panel(menu, "bg", "border", 0.98, T.RADIUS.card)
	menu:Hide()
	menu.pwOwner, menu.items = d, {}
	d.pwMenu = menu

	-- options = { { label, value }, ... }; picked = the current value.
	function d:SetOptions(options, picked)
		self.pwOptions, self.pwPicked = options, picked
		local shown
		for _, o in ipairs(options) do if o[2] == picked then shown = o[1] end end
		text:SetText(shown or (options[1] and options[1][1]) or "")
		for i, o in ipairs(options) do
			local it = menu.items[i]
			if not it then
				it = CreateFrame("Button", nil, menu)
				it:SetHeight(24)
				it.ground = T.Round(it, { 1, 1, 1, 0 }, false, 4)
				it.pwText = T.Text(it, "button", "text2")
				it.pwText:SetPoint("LEFT", 10, 0)
				it.pwText:SetJustifyV("MIDDLE")
				it:SetScript("OnEnter", function(b) local c = T.Color("hover") b.ground:SetColorTexture(c[1], c[2], c[3], 0.9) end)
				it:SetScript("OnLeave", function(b) b.ground:SetColorTexture(1, 1, 1, 0) end)
				menu.items[i] = it
			end
			it:ClearAllPoints()
			it:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (i - 1) * 24)
			it:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -4, -4 - (i - 1) * 24)
			it.pwText:SetText(o[1])
			local on = o[2] == picked
			T.Font(it.pwText, on and "window" or "button", 12)
			paint(it.pwText, on and "flair" or "text2")
			it:SetScript("OnClick", function()
				closeMenu()
				if onPick then onPick(o[2]) end
				if d.pwOnPick then d.pwOnPick(o[2]) end
			end)
			it:Show()
		end
		for i = #options + 1, #menu.items do menu.items[i]:Hide() end
		menu:SetSize(self:GetWidth() or 160, #options * 24 + 8)
	end

	d:SetScript("OnClick", function(self)
		if openMenu == menu then closeMenu() return end
		closeMenu()
		menu:ClearAllPoints()
		menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
		menu:SetWidth(self:GetWidth() or 160)
		if not catcher then
			catcher = CreateFrame("Button", nil, UIParent)
			catcher:SetAllPoints(UIParent)
			catcher:SetFrameStrata("FULLSCREEN")
			catcher:RegisterForClicks("AnyUp")
			catcher:SetScript("OnClick", closeMenu)
		end
		catcher:Show()
		menu:Show()
		openMenu = menu
		arrow:SetRotation(math.pi)
		A.Set(menu, "alpha", 0)
		menu:SetAlpha(0)
		A.Fade(menu, 1, A.FAST)
	end)
	d:SetScript("OnHide", function() if openMenu == menu then closeMenu() end end)
	return d
end

---------------------------------------------------------------------------
-- Segmented choice: joined segments; the picked one looks pressed in (the
-- window's darker ground, brighter and bolder text), the rest stay raised
---------------------------------------------------------------------------

function T.Segmented(parent, onPick)
	local g = CreateFrame("Frame", nil, parent)
	g:SetHeight(26)
	T.Panel(g, "bg2", "border", nil, T.RADIUS.card)
	g.segments, g.dividers = {}, {}

	-- options = { { label, value }, ... }; picked = the current value.
	function g:SetOptions(options, picked)
		local x = 1
		for i, o in ipairs(options) do
			local seg = self.segments[i]
			if not seg then
				seg = CreateFrame("Button", nil, self)
				-- The picked one's ground: rounded, inside the group's corners.
				T.Round(seg, { 0, 0, 0, 0 }, false, 5)
				-- Pressed in: a shadow just under the top edge.
				seg.pwShade = seg:CreateTexture(nil, "BORDER")
				seg.pwShade:SetPoint("TOPLEFT", 5, 0)
				seg.pwShade:SetPoint("TOPRIGHT", -5, 0)
				seg.pwShade:SetHeight(3)
				T.Gradient(seg.pwShade, "VERTICAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.55 })
				seg.pwText = T.Text(seg, "button", "text2")
				seg.pwText:SetPoint("CENTER")
				seg.pwText:SetJustifyH("CENTER")
				seg.pwText:SetJustifyV("MIDDLE")
				local function look(p) if not seg.pwPicked then blend(seg.pwText, "text2", "text", p) end end
				seg:SetScript("OnEnter", function(s) A.Hover(s, true, look) end)
				seg:SetScript("OnLeave", function(s) A.Hover(s, false, look) end)
				self.segments[i] = seg
				if i > 1 then
					local d = self:CreateTexture(nil, "BORDER")
					paint(d, "border")
					d:SetWidth(T.Pixel())
					T.NoSnap(d)
					self.dividers[i] = d
				end
			end
			seg.pwPicked = o[2] == picked
			T.Font(seg.pwText, seg.pwPicked and "window" or "button", 12)
			seg.pwText:SetText(o[1])
			local w = math.max(48, (seg.pwText:GetStringWidth() or 24) + 24)
			seg:ClearAllPoints()
			seg:SetPoint("TOPLEFT", self, "TOPLEFT", x, -1)
			seg:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x, 1)
			seg:SetWidth(w)
			paint(seg.pwText, seg.pwPicked and "text" or "text2")
			seg.pwShade:SetShown(seg.pwPicked)
			if seg.pwPicked then paint(seg.pwGround, "bg") else seg.pwGround:SetColorTexture(0, 0, 0, 0) painted[seg.pwGround] = nil end
			seg:SetScript("OnClick", function() if onPick then onPick(o[2], i) end if self.pwOnPick then self.pwOnPick(o[2], i) end end)
			seg:Show()
			local d = self.dividers[i]
			if d then
				d:ClearAllPoints()
				d:SetPoint("TOPLEFT", self, "TOPLEFT", x - 1, -1)
				d:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", x - 1, 1)
				d:Show()
			end
			x = x + w
		end
		for i = #options + 1, #self.segments do
			self.segments[i]:Hide()
			if self.dividers[i] then self.dividers[i]:Hide() end
		end
		self:SetWidth(x + 1)
	end
	return g
end

---------------------------------------------------------------------------
-- Color: the game's color wheel (ColorPickerFrame), and a swatch for it
---------------------------------------------------------------------------

-- Opens the wheel at color c ({ r, g, b }); onChange(r, g, b) while you
-- pick, onCancel() puts the old one back. -> false when there is no wheel.
function T.PickColor(c, onChange, onCancel)
	local P = ColorPickerFrame
	if type(P) ~= "table" then return false end
	local function current()
		if P.GetColorRGB then return P:GetColorRGB() end
		if P.Content and P.Content.ColorPicker and P.Content.ColorPicker.GetColorRGB then return P.Content.ColorPicker:GetColorRGB() end
	end
	local function changed()
		local r, g, b = current()
		if r and onChange then onChange(r, g, b) end
	end
	local function cancel() if onCancel then onCancel() end end
	if P.SetupColorPickerAndShow then
		P:SetupColorPickerAndShow({ r = c[1], g = c[2], b = c[3], hasOpacity = false,
			swatchFunc = changed, cancelFunc = cancel })
	else
		P.func, P.swatchFunc, P.cancelFunc, P.hasOpacity = changed, changed, cancel, false
		if P.SetColorRGB then P:SetColorRGB(c[1], c[2], c[3]) end
		P:Show()
	end
	return true
end

-- A swatch: a square of the color inside a border; click opens the wheel.
-- get() -> { r, g, b }; set(hex) commits; reset() (right-click) when given;
-- snapshot() -> a function that puts things back as they were (Cancel),
-- else Cancel sets the color from before.
function T.Swatch(parent, get, set, reset, snapshot)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(36, 20)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- The chip: a rounded square of the color inside a rounded border.
	local inner = CreateFrame("Frame", nil, b)
	inner:SetPoint("TOPLEFT", 2, -2)
	inner:SetPoint("BOTTOMRIGHT", -2, 2)
	local chip = T.Round(inner, { 0, 0, 0, 1 }, false, 3)
	T.Round(b, false, "border", 4)
	local border = b.pwBorder
	b.pwChip = chip
	function b:Refresh()
		local c = get()
		chip:SetColorTexture(c[1], c[2], c[3], 1)
	end
	b:SetScript("OnEnter", function() paint(border, "text") end)
	b:SetScript("OnLeave", function() paint(border, "border") end)
	b:SetScript("OnClick", function(self, button)
		if button == "RightButton" then if reset then reset() end return end
		local before = T.ToHex(get())
		local restore = (self.pwSnapshot or snapshot) and (self.pwSnapshot or snapshot)()
		T.PickColor(get(), function(r, g, bl) set(T.ToHex({ r, g, bl })) end, function()
			if restore then restore() else set(before) end
		end)
	end)
	b:Refresh()
	return b
end

---------------------------------------------------------------------------
-- Slider: 2 px track, accent fill, round handle that grows under the mouse.
-- While held, the value follows the pointer along the bar step by step
-- (never jumping to an end); onChange(v) only on a real change.
---------------------------------------------------------------------------

function T.Slider(parent, width, min, max, step, onChange)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 18)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetHeight(4)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	paint(track, "bg2")
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(4)
	fill:SetPoint("LEFT", track, "LEFT")
	paint(fill, "accent")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(T.MEDIA .. "thumb")
	thumb:SetSize(14, 14)
	s:SetThumbTexture(thumb)
	local function grow(p) thumb:SetSize(14 + 4 * p, 14 + 4 * p) end
	s:SetScript("OnEnter", function(self) A.Hover(self, true, grow) end)
	s:SetScript("OnLeave", function(self) if not self.pwHeld then A.Hover(self, false, grow) end end)
	local function snap(v)
		v = min + math.floor((v - min) / step + 0.5) * step
		v = math.floor(v * 100 + 0.5) / 100
		return v < min and min or (v > max and max or v)
	end
	local function paintFill(v)
		local p = (v - min) / (max - min)
		if p <= 0 then fill:Hide() else fill:Show() fill:SetWidth(width * math.min(1, p)) end
	end
	local last
	s:SetScript("OnValueChanged", function(self, v)
		v = snap(v)
		paintFill(v)
		if self.pwQuiet then last = v return end
		if v == last then return end
		last = v
		if onChange then onChange(v) end
	end)
	function s:ValueAt(x)
		local left, w, sc = self:GetLeft(), self:GetWidth(), self:GetEffectiveScale()
		if not (left and w and w > 0 and sc and sc > 0) then return nil end
		local p = math.max(0, math.min(1, (x / sc - left) / w))
		return snap(min + p * (max - min))
	end
	local function follow(self)
		local x = GetCursorPosition and GetCursorPosition()
		local v = x and self:ValueAt(x)
		if v and v ~= self:GetValue() then self:SetValue(v) end
	end
	s:SetScript("OnMouseDown", function(self)
		self.pwHeld = true
		follow(self)
		self:SetScript("OnUpdate", follow)
	end)
	local function stop(self)
		self.pwHeld = false
		self:SetScript("OnUpdate", nil)
		if not (self.IsMouseOver and self:IsMouseOver()) then A.Hover(self, false, grow) end
	end
	s:SetScript("OnMouseUp", stop)
	s:SetScript("OnHide", stop)
	function s:SetQuietly(v)
		self.pwQuiet = true
		self:SetValue(v)
		self.pwQuiet = false
		paintFill(snap(v))
	end
	return s
end

---------------------------------------------------------------------------
-- Smooth scrolling: the wheel sets a target and the view glides to it; a
-- thin thumb on the right shows where you are (drag it too). It fades in
-- while you scroll or hover it, and stays faint otherwise.
---------------------------------------------------------------------------

function T.Scroll(parent, step)
	local sf = CreateFrame("ScrollFrame", nil, parent)
	local child = CreateFrame("Frame", nil, sf)
	child:SetSize(1, 1)
	sf:SetScrollChild(child)
	sf:EnableMouseWheel(true)
	step = step or 60

	local track = CreateFrame("Frame", nil, parent)
	track:SetWidth(6)
	track:SetPoint("TOPLEFT", sf, "TOPRIGHT", 4, 0)
	track:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 4, 0)
	local thumb = CreateFrame("Frame", nil, track)
	thumb:SetWidth(4)
	thumb:EnableMouse(true)
	local thumbTex = thumb:CreateTexture(nil, "ARTWORK")
	thumbTex:SetAllPoints()
	paint(thumbTex, "muted")
	thumb:SetAlpha(0.35)
	sf.pwThumb, sf.pwTrack, sf.pwChild = thumb, track, child

	local function range()
		return math.max(0, (child:GetHeight() or 0) - (sf:GetHeight() or 0))
	end
	function sf:Range() return range() end
	local function placeThumb()
		local max = range()
		if max <= 0 then thumb:Hide() return end
		thumb:Show()
		local th, vh = track:GetHeight() or 0, sf:GetHeight() or 0
		local h = math.max(24, th * vh / (vh + max))
		thumb:SetHeight(h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOP", track, "TOP", 0, -((sf:GetVerticalScroll() or 0) / max) * (th - h))
	end
	sf.PlaceThumb = placeThumb

	-- Glide to y (clamped).
	function sf:ScrollTo(y, instant)
		y = math.max(0, math.min(range(), y))
		self.pwTarget = y
		if A.Get(self, "y") == nil then A.Set(self, "y", self:GetVerticalScroll() or 0) end
		local function apply(v) self:SetVerticalScroll(v) placeThumb() end
		if instant then A.Set(self, "y", y, apply) else A.Tween(self, "y", y, A.SLOW, apply) end
	end
	function sf:Target() return self.pwTarget or self:GetVerticalScroll() or 0 end

	local function wake()
		A.Fade(thumb, 0.9, A.FAST)
		sf.pwIdle = (GetTime and GetTime() or 0) + 0.8
		if C_Timer and C_Timer.After then
			C_Timer.After(0.9, function()
				if (GetTime and GetTime() or 0) >= (sf.pwIdle or 0) and not thumb.pwDrag and not (thumb.IsMouseOver and thumb:IsMouseOver()) then
					A.Fade(thumb, 0.35, A.SLOW)
				end
			end)
		end
	end
	sf:SetScript("OnMouseWheel", function(self, delta)
		self:ScrollTo(self:Target() - delta * step)
		wake()
	end)
	thumb:SetScript("OnEnter", function() A.Fade(thumb, 0.9, A.FAST) end)
	thumb:SetScript("OnLeave", function() if not thumb.pwDrag then A.Fade(thumb, 0.35, A.SLOW) end end)
	thumb:SetScript("OnMouseDown", function(self)
		local _, y = GetCursorPosition()
		self.pwDrag = { y = y / (self:GetEffectiveScale() or 1), from = sf:GetVerticalScroll() or 0 }
		self:SetScript("OnUpdate", function(t)
			local _, cy = GetCursorPosition()
			cy = cy / (t:GetEffectiveScale() or 1)
			local th, h = track:GetHeight() or 1, t:GetHeight() or 1
			local per = range() / math.max(1, th - h)
			sf:ScrollTo(t.pwDrag.from + (t.pwDrag.y - cy) * per, true)
		end)
	end)
	thumb:SetScript("OnMouseUp", function(self)
		self.pwDrag = nil
		self:SetScript("OnUpdate", nil)
		A.Fade(thumb, 0.35, A.SLOW)
	end)
	sf:SetScript("OnSizeChanged", placeThumb)
	return sf, child
end
