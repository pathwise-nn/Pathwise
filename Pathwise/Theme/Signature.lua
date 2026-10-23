-- Pathwise Signature: the theme every Pathwise window is drawn with.
-- Tokens (colours, type, spacing) and small builders (panel, text, button,
-- icon button, progress line) so every module looks and spaces the same.
-- Modules differ only by their accent (Theme.MODULES).
--
-- Construction notes for the WoW client:
--  * Solid fills and 1 px lines are textures with SetColorTexture; no
--    backdrop templates, no art files, nothing animated.
--  * Corners are square: the client has no rounded clipping, and 9-slice art
--    for a 6 px radius blurs at 70% UI scale. Documented limitation.
--  * Text is Inter (SIL OFL 1.1, Media/Fonts), sizes in UI units, so the
--    game's UI scale scales it.

local ADDON, ns = ...
local T = {}
ns.Theme = T
T.NAME = "Pathwise Signature"

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
T.MEDIA = MEDIA

local function hex(h, a)
	h = h:gsub("#", "")
	return {
		tonumber(h:sub(1, 2), 16) / 255,
		tonumber(h:sub(3, 4), 16) / 255,
		tonumber(h:sub(5, 6), 16) / 255,
		a or 1,
	}
end
T.Hex = hex

T.COLORS = {
	bg = hex("#10161E"), -- window ground
	bg2 = hex("#17212C"), -- raised surface, buttons, cards
	hover = hex("#223241"),
	border = hex("#293B4B"), -- 1 px window border
	divider = hex("#1F2D3A"),
	text = hex("#F0F5FA"),
	text2 = hex("#9AAFC0"),
	muted = hex("#7A90A2"), -- 4.5:1 or more on every ground (tests)
	accent = hex("#66D7FF"),
	accentHover = hex("#90E4FF"),
	success = hex("#59D9B2"),
	warning = hex("#E4B96D"),
	error = hex("#E66B78"),
	silver = hex("#C9D6E2"),
}

-- One accent per module; the components are shared.
T.MODULES = {
	guide = hex("#66D7FF"),
	gear = hex("#E8C26A"),
	loot = hex("#B69CFF"),
	bags = hex("#7FD98F"),
	explorer = hex("#4FD1C5"),
	auction = hex("#E0956A"),
	encounters = hex("#F07A86"),
}

T.FONTS = {
	regular = MEDIA .. "Fonts\\Inter-Regular.ttf",
	medium = MEDIA .. "Fonts\\Inter-Medium.ttf",
	semibold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
}

-- The type ladder: role -> font, size, colour.
T.TYPE = {
	window = { "semibold", 13, "text" },
	quest = { "semibold", 16, "text" },
	body = { "regular", 13, "text" },
	meta = { "regular", 12, "text2" },
	small = { "regular", 11, "muted" },
	label = { "medium", 10, "text2" }, -- caps, tracked by spacing in the text
	number = { "semibold", 17, "text" },
	button = { "medium", 12, "text2" },
}

T.SPACE = { xs = 4, s = 8, m = 12, l = 16, xl = 24 }
T.HEADER_H = 36
T.PROGRESS_H = 2

ns.Defaults("ui", {
	opacity = 0.94, -- window ground alpha
	scale = 1, -- window size, 0.5-1.5, on top of the game's UI scale
})

function T.Color(name)
	return T.COLORS[name] or T.MODULES[name] or T.COLORS.text
end

local function setColor(tex, name, alpha)
	local c = type(name) == "table" and name or T.Color(name)
	tex:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
end
T.SetColor = setColor

---------------------------------------------------------------------------
-- Builders
---------------------------------------------------------------------------

-- A window or card ground with a 1 px border. Returns the textures so the
-- caller can recolour them (opacity setting, hover).
function T.Panel(frame, ground, border)
	local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	setColor(bg, ground or "bg", ground == nil and ns.Get("ui.opacity") or nil)
	frame.pwGround = bg
	if border ~= false then
		local edges = {}
		local function line(p1, p2, w, h)
			local t = frame:CreateTexture(nil, "BORDER")
			t:SetPoint(p1)
			t:SetPoint(p2)
			if w then t:SetWidth(w) else t:SetHeight(h) end
			setColor(t, border or "border")
			edges[#edges + 1] = t
		end
		line("TOPLEFT", "TOPRIGHT", nil, 1)
		line("BOTTOMLEFT", "BOTTOMRIGHT", nil, 1)
		line("TOPLEFT", "BOTTOMLEFT", 1, nil)
		line("TOPRIGHT", "BOTTOMRIGHT", 1, nil)
		frame.pwEdges = edges
	end
	return bg
end

-- A horizontal 1 px divider inside a panel.
function T.Divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	setColor(t, "divider")
	return t
end

-- A font string in a type role. `upper` for small caps labels.
function T.Text(parent, role, color, layer)
	local r = T.TYPE[role] or T.TYPE.body
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	T.Font(fs, role)
	local c = T.Color(color or r[3])
	fs:SetTextColor(c[1], c[2], c[3], c[4])
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	return fs
end

function T.Font(fs, role)
	local r = T.TYPE[role] or T.TYPE.body
	if not fs:SetFont(T.FONTS[r[1]], r[2], "") then
		-- The font file failed to load: fall back to the game's own.
		fs:SetFont("Fonts\\FRIZQT__.TTF", r[2], "")
	end
end

-- A soft 1 px shadow for text drawn straight on the game world (the arrow),
-- so it stays readable over snow, sand and bright skies. Windows have their
-- own ground and do not need it.
function T.Shadow(fs)
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.85)
end

function T.TextColor(fs, name)
	local c = T.Color(name)
	fs:SetTextColor(c[1], c[2], c[3], c[4])
end

-- A low-profile text button: dark surface, 1 px outline.
-- kind "default" (Back) or "accent" (Next).
function T.Button(parent, label, kind, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(28)
	local accent = kind == "accent"
	T.Panel(b, "bg2", false)
	local edges = {}
	for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
		{ "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = b:CreateTexture(nil, "BORDER")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
		edges[#edges + 1] = t
	end
	local text = T.Text(b, "button", accent and "accent" or "text2")
	text:SetPoint("CENTER")
	text:SetText(label)
	b.pwText = text
	local function paint(hover)
		for _, t in ipairs(edges) do
			if accent then setColor(t, hover and "accentHover" or "accent", hover and 1 or 0.4)
			else setColor(t, "border") end
		end
		setColor(b.pwGround, hover and not accent and "hover" or "bg2")
		T.TextColor(text, accent and (hover and "accentHover" or "accent") or (hover and "text" or "text2"))
	end
	paint(false)
	b:SetScript("OnEnter", function() paint(true) end)
	b:SetScript("OnLeave", function() paint(false) end)
	if onClick then b:SetScript("OnClick", onClick) end
	b:SetWidth(math.max(64, (text:GetStringWidth() or 30) + 28))
	return b
end

-- A small icon-only button: a white glyph texture (Media/glyph-<name>.tga,
-- drawn by tools/media.js) tinted secondary, primary on hover. `tip` is its
-- tooltip and its name.
function T.IconButton(parent, glyph, tip, onClick, size)
	local b = CreateFrame("Button", nil, parent)
	size = size or 22
	b:SetSize(size, size)
	local hover = b:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	setColor(hover, "hover")
	hover:Hide()
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(MEDIA .. "glyph-" .. glyph)
	icon:SetSize(16, 16)
	icon:SetPoint("CENTER")
	local text = { -- tints the glyph like a font string would be tinted
		SetTextColor = function(_, r, g, b2, a) icon:SetVertexColor(r, g, b2, a) end,
	}
	T.TextColor(text, "text2")
	b.pwIcon = icon
	function b:SetGlyph(name) icon:SetTexture(MEDIA .. "glyph-" .. name) end
	b:SetScript("OnEnter", function(self)
		hover:Show()
		T.TextColor(text, "text")
		if tip and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(tip, 1, 1, 1)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function()
		hover:Hide()
		T.TextColor(text, "text2")
		if GameTooltip then GameTooltip:Hide() end
	end)
	if onClick then b:SetScript("OnClick", onClick) end
	return b
end

-- A thin progress line: track plus fill. line:SetProgress(0..1).
function T.ProgressLine(parent, color)
	local track = parent:CreateTexture(nil, "ARTWORK")
	track:SetHeight(T.PROGRESS_H)
	setColor(track, "bg2")
	local fill = parent:CreateTexture(nil, "ARTWORK", nil, 1)
	fill:SetHeight(T.PROGRESS_H)
	fill:SetPoint("TOPLEFT", track, "TOPLEFT")
	setColor(fill, color or "accent")
	local line = { track = track, fill = fill }
	function line:SetProgress(p)
		p = math.max(0, math.min(1, p or 0))
		local w = track:GetWidth() or 0
		if p <= 0 or w <= 0 then fill:Hide() return end
		fill:Show()
		fill:SetWidth(w * p)
	end
	return line
end

-- A slider: the game's Slider control drawn the Signature way, a 2 px track,
-- an accent fill up to the value and a round handle (Media/thumb.tga).
-- onChange(value) runs as it moves (rounded to `step`); the slider never
-- re-reads a setting itself, so the caller sets it with slider:SetValue().
function T.Slider(parent, width, min, max, step, onChange)
	local s = CreateFrame("Slider", nil, parent)
	s:SetOrientation("HORIZONTAL")
	s:SetSize(width, 18)
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	s:EnableMouseWheel(true)
	local track = s:CreateTexture(nil, "BACKGROUND")
	track:SetHeight(T.PROGRESS_H)
	track:SetPoint("LEFT", s, "LEFT", 0, 0)
	track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
	setColor(track, "border")
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetHeight(T.PROGRESS_H)
	fill:SetPoint("LEFT", track, "LEFT", 0, 0)
	setColor(fill, "accent")
	local thumb = s:CreateTexture(nil, "OVERLAY")
	thumb:SetTexture(MEDIA .. "thumb")
	thumb:SetSize(14, 14)
	local c = T.Color("text")
	thumb:SetVertexColor(c[1], c[2], c[3])
	s:SetThumbTexture(thumb)
	s.pwFill, s.pwMin, s.pwMax, s.pwStep, s.pwWidth = fill, min, max, step, width
	local function paintFill(v)
		local p = (v - min) / (max - min)
		p = p < 0 and 0 or (p > 1 and 1 or p)
		if p <= 0 then fill:Hide() else fill:Show() fill:SetWidth(width * p) end
	end
	local last -- the last value onChange was told, so a drag only reports real changes
	local function snap(v)
		v = min + math.floor((v - min) / step + 0.5) * step
		v = math.floor(v * 100 + 0.5) / 100
		return v < min and min or (v > max and max or v)
	end
	s:SetScript("OnValueChanged", function(self, v)
		v = snap(v)
		paintFill(v)
		if self.pwQuiet then last = v return end
		if v == last then return end
		last = v
		if onChange then onChange(v) end
	end)
	-- Dragging: the value follows the pointer along the bar, every frame,
	-- worked out from where the bar really is on screen. Smooth whatever
	-- the window's size, and it never jumps to an end.
	function s:ValueAt(cursorX)
		local left, w, scale = self:GetLeft(), self:GetWidth(), self:GetEffectiveScale()
		if not (left and w and w > 0 and scale and scale > 0) then return nil end
		local p = (cursorX / scale - left) / w
		p = p < 0 and 0 or (p > 1 and 1 or p)
		return snap(min + p * (max - min))
	end
	local function follow(self)
		local x = GetCursorPosition and GetCursorPosition()
		local v = x and self:ValueAt(x)
		if v and v ~= self:GetValue() then self:SetValue(v) end
	end
	s:SetScript("OnMouseDown", function(self, button)
		if button and button ~= "LeftButton" then return end
		self.pwDragging = true
		-- Whoever holds the slider (a panel) can hold still while it moves.
		if self.pwOnDragStart then self.pwOnDragStart(self) end
		follow(self)
		self:SetScript("OnUpdate", follow)
	end)
	local function stop(self)
		if not self.pwDragging then return end
		self.pwDragging = false
		self:SetScript("OnUpdate", nil)
		if self.pwOnDragStop then self.pwOnDragStop(self) end
	end
	s:SetScript("OnMouseUp", stop)
	s:SetScript("OnHide", stop)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(math.max(min, math.min(max, (self:GetValue() or min) + delta * step)))
	end)
	s:SetScript("OnEnter", function() thumb:SetVertexColor(T.Color("accentHover")[1], T.Color("accentHover")[2], T.Color("accentHover")[3]) end)
	s:SetScript("OnLeave", function() thumb:SetVertexColor(c[1], c[2], c[3]) end)
	-- Sets the value without calling onChange (opening a panel, a reset).
	function s:SetQuietly(v)
		self.pwQuiet = true
		self:SetValue(v)
		self.pwQuiet = false
		paintFill(v)
	end
	return s
end

-- A small number box: type a value, Enter (or clicking away) commits it,
-- Escape puts back the last value. onCommit(n) gets the typed number, or nil
-- when it is not one; the caller decides what the box then shows
-- (box:SetNumber). The 1 px border lights up in the accent while typing.
function T.NumberBox(parent, width, onCommit)
	local e = CreateFrame("EditBox", nil, parent)
	e:SetSize(width, 22)
	e:SetAutoFocus(false)
	e:SetMaxLetters(5)
	e:SetJustifyH("RIGHT")
	e:SetTextInsets(6, 6, 0, 0)
	if not e:SetFont(T.FONTS.regular, 12, "") then e:SetFont("Fonts\\FRIZQT__.TTF", 12, "") end
	local tc = T.Color("text")
	e:SetTextColor(tc[1], tc[2], tc[3])
	T.Panel(e, "bg2")
	local function edges(name)
		for _, t in ipairs(e.pwEdges or {}) do setColor(t, name) end
	end
	local shown = ""
	function e:SetNumber(n)
		shown = n and tostring(n) or ""
		self:SetText(shown)
	end
	local function commit(self)
		local text = (self:GetText() or ""):gsub("[%%%s]", ""):gsub(",", ".")
		onCommit(text:match("^%d+%.?%d*$") and tonumber(text) or nil)
	end
	e:SetScript("OnEditFocusGained", function(self) edges("accent") self:HighlightText() end)
	e:SetScript("OnEditFocusLost", function(self)
		edges("border")
		if self:GetText() ~= shown then commit(self) end
	end)
	e:SetScript("OnEnterPressed", function(self) commit(self) self:ClearFocus() end)
	e:SetScript("OnEscapePressed", function(self) self:SetText(shown) self:ClearFocus() end)
	return e
end

-- The small compass mark used in headers (Media/icon.tga).
function T.Icon(parent, size)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(MEDIA .. "icon")
	t:SetSize(size or 16, size or 16)
	return t
end

-- Re-tint every window ground when the opacity setting changes.
local grounds = setmetatable({}, { __mode = "k" })
function T.TrackGround(frame)
	grounds[frame] = true
end
-- Windows that follow the "Window size" setting (ui.scale), on top of the
-- game's own UI scale.
local scaled = setmetatable({}, { __mode = "k" })
function T.TrackScale(frame)
	scaled[frame] = true
	frame:SetScale(ns.Get("ui.scale") or 1)
end

ns.On("SETTING_CHANGED", function(path, value)
	if path == "ui.opacity" then
		for frame in pairs(grounds) do
			if frame.pwGround then setColor(frame.pwGround, "bg", value) end
		end
	elseif path == "ui.scale" then
		for frame in pairs(scaled) do frame:SetScale(value or 1) end
	end
end)
