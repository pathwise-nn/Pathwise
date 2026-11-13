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
	selected = hex("#132332"), -- a chosen row or card: the ground, a little toward the accent
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
	insights = hex("#C7E86A"),
}

T.FONTS = {
	regular = MEDIA .. "Fonts\\Inter-Regular.ttf",
	medium = MEDIA .. "Fonts\\Inter-Medium.ttf",
	semibold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
}
-- Korean and Chinese: Inter has none of their letters, so the game's own
-- font (read now, before any addon changes it), in every weight.
if ns.GAME_FONT_LOCALES and ns.GAME_FONT_LOCALES[ns.GAME_LOCALE] then
	local own = STANDARD_TEXT_FONT or ({ koKR = "Fonts\\2002.TTF", zhCN = "Fonts\\ARKai_T.ttf", zhTW = "Fonts\\bLEI00D.ttf" })[ns.GAME_LOCALE]
	T.FONTS.regular, T.FONTS.medium, T.FONTS.semibold = own, own, own
end

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
	if type(name) == "table" then return name end -- a colour already
	-- "One colour for the whole suite": the suite addons' own colours give
	-- way to the accent too.
	if T.MODULES[name] and name ~= "guide" and ns.Get("ui.accentSuite") then return T.COLORS.accent end
	return T.COLORS[name] or T.MODULES[name] or T.COLORS.text
end

---------------------------------------------------------------------------
-- Themes (v2): the whole palette, dark or light. Every theme's text passes
-- the same contrast checks as Pathwise Blue (tests/v2.lua): 7:1 for text,
-- 4.5:1 for the secondary text, the accent, success and warning on every
-- ground, and the ground on the accent (a filled button's label).
-- world: a light theme's accent for text drawn straight on the game
-- world (the compass, the minimal guide), which stays light-on-dark.
---------------------------------------------------------------------------

T.THEMES = {
	{ key = "pathwise", name = "Pathwise Blue", mode = "dark",
		bg = "#10161E", bg2 = "#17212C", hover = "#223241", border = "#293B4B", divider = "#1F2D3A", text = "#F0F5FA", text2 = "#9AAFC0", muted = "#7A90A2", accent = "#66D7FF", success = "#59D9B2", warning = "#E4B96D", error = "#E66B78" },
	{ key = "midnight", name = "Midnight", mode = "dark",
		bg = "#0B0B0D", bg2 = "#161618", hover = "#222226", border = "#36363D", divider = "#1E1E22", text = "#F5F5F7", text2 = "#B4B4BC", muted = "#8E8E98", accent = "#FFFFFF", success = "#5ED7B0", warning = "#E8BF6E", error = "#F07580" },
	{ key = "graphite", name = "Graphite", mode = "dark",
		bg = "#17191C", bg2 = "#202327", hover = "#2B2F34", border = "#3C4148", divider = "#262A2F", text = "#F2F4F6", text2 = "#B0B6BE", muted = "#8D949D", accent = "#9FB4C8", success = "#5ED7B0", warning = "#E4B96D", error = "#EE7580" },
	{ key = "rose", name = "Rose", mode = "dark",
		bg = "#1C1218", bg2 = "#26171F", hover = "#33202A", border = "#4C3040", divider = "#2E1C26", text = "#FBEFF4", text2 = "#D9AFC2", muted = "#BA8EA2", accent = "#FF7EB6", success = "#62D9B2", warning = "#EBC07A", error = "#FF7B86" },
	{ key = "amethyst", name = "Amethyst", mode = "dark",
		bg = "#16121F", bg2 = "#1F192B", hover = "#2A2239", border = "#40355A", divider = "#262033", text = "#F3EEFC", text2 = "#BDB0D6", muted = "#9D90B8", accent = "#B69CFF", success = "#5ED7B0", warning = "#E8BF6E", error = "#F07580" },
	{ key = "emerald", name = "Emerald", mode = "dark",
		bg = "#0F1A16", bg2 = "#16241F", hover = "#1F322B", border = "#2D4B3F", divider = "#1C2C26", text = "#EEF8F3", text2 = "#A7C7B9", muted = "#86A799", accent = "#5FE0A6", success = "#7BD8E6", warning = "#E8BF6E", error = "#F07580" },
	{ key = "ocean", name = "Ocean", mode = "dark",
		bg = "#0D1A1C", bg2 = "#132427", hover = "#1B3135", border = "#294B50", divider = "#18292C", text = "#EAF8F8", text2 = "#A4C8CA", muted = "#83A7A9", accent = "#4FD8D0", success = "#7FE0A8", warning = "#E8BF6E", error = "#F07580" },
	{ key = "gold", name = "Gold", mode = "dark",
		bg = "#1A1610", bg2 = "#241F16", hover = "#312A1E", border = "#4B402D", divider = "#2B251B", text = "#FBF5EA", text2 = "#CDBFA4", muted = "#AB9D82", accent = "#F2C14E", success = "#62D9B2", warning = "#F0A36E", error = "#F07580" },
	{ key = "sunset", name = "Sunset", mode = "dark",
		bg = "#1C130E", bg2 = "#271B14", hover = "#34241B", border = "#4F3728", divider = "#2E2018", text = "#FCF2EB", text2 = "#D8BBA8", muted = "#B69886", accent = "#FF9A5A", success = "#62D9B2", warning = "#F2C46E", error = "#FF7B86" },
	{ key = "crimson", name = "Crimson", mode = "dark",
		bg = "#1C1012", bg2 = "#26161A", hover = "#331E23", border = "#4E2E35", divider = "#2E1A1F", text = "#FCEFF1", text2 = "#D8B0B6", muted = "#B78F96", accent = "#FF6B7A", success = "#62D9B2", warning = "#EBC07A", error = "#FF8A6B" },
	{ key = "contrast", name = "High Contrast", mode = "dark",
		bg = "#000000", bg2 = "#0E0E0E", hover = "#1C1C1C", border = "#5A5A5A", divider = "#2A2A2A", text = "#FFFFFF", text2 = "#E0E0E0", muted = "#C4C4C4", accent = "#FFD400", success = "#5CF2B8", warning = "#FFB84D", error = "#FF6F6F" },
	{ key = "snow", name = "Snow", mode = "light", world = "#FFFFFF",
		bg = "#F6F7F9", bg2 = "#FFFFFF", hover = "#ECEFF3", border = "#D0D6DE", divider = "#E4E8ED", text = "#12161C", text2 = "#475261", muted = "#5A6573", accent = "#111418", success = "#0F7556", warning = "#875800", error = "#B3261E" },
	{ key = "sky", name = "Sky", mode = "light", world = "#66D7FF",
		bg = "#F2F8FC", bg2 = "#FFFFFF", hover = "#E3EEF7", border = "#C5DAEA", divider = "#DCE8F2", text = "#0F1D29", text2 = "#3D5467", muted = "#4F6577", accent = "#0A6699", success = "#0F7556", warning = "#875800", error = "#B3261E" },
	{ key = "blossom", name = "Blossom", mode = "light", world = "#FF8CC0",
		bg = "#FFF4F8", bg2 = "#FFFFFF", hover = "#FBE4ED", border = "#EEC4D5", divider = "#F6DCE6", text = "#2A1620", text2 = "#6B4458", muted = "#7C5567", accent = "#B8175A", success = "#0F7556", warning = "#875800", error = "#B3261E" },
	{ key = "lavender", name = "Lavender", mode = "light", world = "#C4ADFF",
		bg = "#F7F3FD", bg2 = "#FFFFFF", hover = "#ECE5FA", border = "#D6C9F0", divider = "#E6DDF6", text = "#1F1630", text2 = "#54476E", muted = "#655980", accent = "#6235C9", success = "#0F7556", warning = "#875800", error = "#B3261E" },
	{ key = "mint", name = "Mint", mode = "light", world = "#6FE6B0",
		bg = "#F1FAF6", bg2 = "#FFFFFF", hover = "#E1F2EA", border = "#C0E2D2", divider = "#D7EEE3", text = "#10241B", text2 = "#3E5C4F", muted = "#4F6E60", accent = "#0B7048", success = "#0A6B7A", warning = "#875800", error = "#B3261E" },
	{ key = "sand", name = "Sand", mode = "light", world = "#F2C14E",
		bg = "#FBF7EF", bg2 = "#FFFFFF", hover = "#F2EADB", border = "#E0D2B6", divider = "#ECE2CF", text = "#251C0F", text2 = "#5E5038", muted = "#6E6046", accent = "#8C4F00", success = "#0F7556", warning = "#7A4E00", error = "#B3261E" },
}
T.THEME_BY = {}
for _, th in ipairs(T.THEMES) do T.THEME_BY[th.key] = th end

ns.Defaults("ui", { theme = "pathwise" })

-- The theme in use (an unknown saved key reads as Pathwise Blue).
function T.Theme() return T.THEME_BY[ns.Get("ui.theme")] or T.THEME_BY.pathwise end

-- Colours for text drawn on the game world, not on a window: a dark theme's
-- own; a light theme's dark-window colours with its world accent, so they
-- read over grass and sky as Pathwise Blue does.
function T.World(name)
	local th = T.Theme()
	if th.mode ~= "light" then return T.Color(name) end
	if name == "accent" or name == "accentHover" then
		if ns.Get("ui.accentMode") ~= "pathwise" then return T.Color(name) end
		return hex(th.world or "#66D7FF")
	end
	local base = T.THEME_BY.pathwise
	if base[name] then return hex(base[name]) end
	if name == "silver" then return hex("#C9D6E2") end
	return T.Color(name)
end

-- "|cffRRGGBB" for a colour, to colour part of a text.
function T.Esc(name)
	local c = T.Color(name)
	return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

---------------------------------------------------------------------------
-- The accent: the theme's, your class colour, or one you pick
---------------------------------------------------------------------------

ns.Defaults("ui", {
	accentMode = "pathwise", -- "pathwise" | "class" | "custom"
	accentColor = "#66D7FF", -- for "custom"
	accentSuite = false, -- the suite addons use the accent instead of their own colours
})

T.PATHWISE_ACCENT = hex("#66D7FF")

-- The player's class colour (Blizzard's C_ClassColor, else RAID_CLASS_COLORS).
function T.ClassColor(classFile)
	if not classFile then
		if not UnitClass then return nil end
		local _, c = UnitClass("player")
		classFile = ns.Compat and ns.Compat.Readable and ns.Compat.Readable(c) or c
	end
	if not classFile then return nil end
	local c
	if C_ClassColor and C_ClassColor.GetClassColor then
		local ok, col = pcall(C_ClassColor.GetClassColor, classFile)
		if ok and col then c = col end
	end
	c = c or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
	if not (c and c.r) then return nil end
	return { c.r, c.g, c.b, 1 }
end

-- A colour a little lighter, for hover.
local function lighten(c, by)
	return { c[1] + (1 - c[1]) * by, c[2] + (1 - c[2]) * by, c[3] + (1 - c[3]) * by, 1 }
end
-- A little darker (hover on a light theme, and on a white accent).
local function darken(c, by)
	return { c[1] * (1 - by), c[2] * (1 - by), c[3] * (1 - by), 1 }
end

-- The accent the settings ask for. -> { r, g, b, 1 }
function T.WantedAccent()
	local mode = ns.Get("ui.accentMode")
	if mode == "class" then return T.ClassColor() or hex(T.Theme().accent) end
	if mode == "custom" then
		local h = ns.Get("ui.accentColor")
		if type(h) == "string" and h:match("^#?%x%x%x%x%x%x$") then return hex(h) end
	end
	return hex(T.Theme().accent)
end

-- Sets the accent in place, so every colour lookup after this sees it.
function T.ApplyAccent()
	local c = T.WantedAccent()
	local light = T.Theme().mode == "light" or (c[1] + c[2] + c[3]) > 2.85
	local hov = light and darken(c, 0.18) or lighten(c, 0.3)
	for i = 1, 4 do T.COLORS.accent[i] = c[i] T.COLORS.accentHover[i] = hov[i] end
	local g = T.COLORS.bg2
	for i = 1, 3 do T.COLORS.selected[i] = g[i] + (c[i] - g[i]) * 0.16 end
	T.COLORS.selected[4] = 1
	T.MODULES.guide[1], T.MODULES.guide[2], T.MODULES.guide[3] = c[1], c[2], c[3]
	ns.Fire("ACCENT_CHANGED", c)
	return c
end

-- "#RRGGBB" of a colour, for the custom colour box.
function T.ToHex(c)
	return ("#%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Puts the theme's palette in place (the tables stay the same, so every
-- lookup after this sees it), then the accent on top.
local ROLES = { "bg", "bg2", "hover", "border", "divider", "text", "text2", "muted", "success", "warning", "error" }
function T.ApplyTheme()
	local th = T.Theme()
	for _, role in ipairs(ROLES) do
		local c = hex(th[role])
		for i = 1, 4 do T.COLORS[role][i] = c[i] end
	end
	-- Silver: the secondary text, a touch brighter (darker on a light theme).
	local t2 = hex(th.text2)
	local sv = th.mode == "light" and darken(t2, 0.15) or lighten(t2, 0.35)
	for i = 1, 4 do T.COLORS.silver[i] = sv[i] end
	T.ApplyAccent()
	ns.Fire("THEME_CHANGED", th)
	return th
end

ns.On("LOADED", function() T.ApplyTheme() end)
ns.On("SETTING_CHANGED", function(path)
	if path == "ui.theme" then T.ApplyTheme()
	elseif path == "ui.accentMode" or path == "ui.accentColor" or path == "ui.accentSuite" then T.ApplyAccent() end
end)

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
function T.Panel(frame, ground, border, radius)
	-- v2: every window and card is rounded (Theme.Round). Callers that
	-- recolour the ground or the border (frame.pwGround, frame.pwEdges) get
	-- stand-ins whose SetColorTexture repaints every piece.
	T.Round(frame, ground or "bg", border == false and false or (border or "border"), radius or (ground == nil and 10 or 6))
	local rd = rawget(frame, "pwRound")
	frame.pwGround = T.Pieces(rd.fills)
	frame.pwEdges = border ~= false and { T.Pieces(rd.lines) } or nil
	return frame.pwGround
end

-- One stand-in for several textures (a rounded ground's pieces): what is
-- done to it is done to each, corners tinted, straight pieces filled.
function T.Pieces(list)
	local p = { list = list }
	function p:SetColorTexture(r, g, b, a)
		self.color = { r, g, b, a }
		for _, t in ipairs(self.list) do
			if rawget(t, "pwCorner") then t:SetVertexColor(r, g, b, a or 1) else t:SetColorTexture(r, g, b, a or 1) end
		end
	end
	for _, m in ipairs({ "Show", "Hide", "SetShown", "SetAlpha", "SetDrawLayer" }) do
		p[m] = function(self, ...) for _, t in ipairs(self.list) do t[m](t, ...) end end
	end
	function p:SetVertexColor(r, g, b, a) self:SetColorTexture(r, g, b, a) end
	function p:SetAllPoints() end
	function p:IsShown() return self.list[1] and self.list[1]:IsShown() end
	return p
end

-- A rounded 1 px border alone (no ground), for frames that draw their own
-- ground. -> { stand-in }, recoloured with SetColorTexture.
function T.RoundEdges(frame, radius, layer)
	local r = radius or 8
	local list = {}
	local function tex()
		local t = frame:CreateTexture(nil, layer or "BORDER")
		list[#list + 1] = t
		return t
	end
	for _, c in ipairs({ { "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 }, { "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 } }) do
		local t = tex()
		t:SetTexture(MEDIA .. "corner-line")
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		t:SetSize(r, r)
		t:SetPoint(c[1])
		t.pwCorner = true
	end
	for _, spec in ipairs({
		{ "TOPLEFT", r, 0, "TOPRIGHT", -r, 0, nil, 1 }, { "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, nil, 1 },
		{ "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, 1, nil }, { "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, 1, nil },
	}) do
		local t = tex()
		t:SetPoint(spec[1], spec[2], spec[3])
		t:SetPoint(spec[4], spec[5], spec[6])
		if spec[7] then t:SetWidth(spec[7]) else t:SetHeight(spec[8]) end
	end
	local p = T.Pieces(list)
	local c = T.Color("border")
	p:SetColorTexture(c[1], c[2], c[3], c[4])
	return { p }
end

-- A rounded ground with a 1 px border (v2): the client has no rounded
-- clipping, so the shape is pieced together: four corners (Media/corner and
-- corner-line, flipped by texture coordinates), the straight strips between
-- them, and a middle. `radius` in UI units (8 for windows, 6 for cards).
-- ground/border: colour names or { r, g, b, a }; border false: none.
-- Returns the frame; T.PaintRound recolours it (hover, opacity).
local CORNERS = {
	-- point, texcoord left, right, top, bottom
	{ "TOPLEFT", 0, 1, 0, 1 }, { "TOPRIGHT", 1, 0, 0, 1 },
	{ "BOTTOMLEFT", 0, 1, 1, 0 }, { "BOTTOMRIGHT", 1, 0, 1, 0 },
}
function T.Round(frame, ground, border, radius, layer)
	local r = radius or 8
	local fills, lines = {}, {}
	local function tex(kind, sub)
		local t = frame:CreateTexture(nil, kind == "line" and "BORDER" or (layer or "BACKGROUND"), nil, sub)
		local list = kind == "line" and lines or fills
		list[#list + 1] = t
		return t
	end
	for _, c in ipairs(CORNERS) do
		local t = tex("fill", -8)
		t:SetTexture(MEDIA .. "corner")
		t:SetTexCoord(c[2], c[3], c[4], c[5])
		t:SetSize(r, r)
		t:SetPoint(c[1])
		t.pwCorner = true
		if border ~= false then
			local l = tex("line")
			l:SetTexture(MEDIA .. "corner-line")
			l:SetTexCoord(c[2], c[3], c[4], c[5])
			l:SetSize(r, r)
			l:SetPoint(c[1])
			l.pwCorner = true
		end
	end
	-- The middle (full height between the corners' rows) and the strips
	-- beside the corners, top and bottom.
	local mid = tex("fill", -8)
	mid:SetPoint("TOPLEFT", 0, -r)
	mid:SetPoint("BOTTOMRIGHT", 0, r)
	local top = tex("fill", -8)
	top:SetPoint("TOPLEFT", r, 0)
	top:SetPoint("TOPRIGHT", -r, 0)
	top:SetHeight(r)
	local bottom = tex("fill", -8)
	bottom:SetPoint("BOTTOMLEFT", r, 0)
	bottom:SetPoint("BOTTOMRIGHT", -r, 0)
	bottom:SetHeight(r)
	if border ~= false then
		for _, spec in ipairs({
			{ "TOPLEFT", r, 0, "TOPRIGHT", -r, 0, nil, 1 }, { "BOTTOMLEFT", r, 0, "BOTTOMRIGHT", -r, 0, nil, 1 },
			{ "TOPLEFT", 0, -r, "BOTTOMLEFT", 0, r, 1, nil }, { "TOPRIGHT", 0, -r, "BOTTOMRIGHT", 0, r, 1, nil },
		}) do
			local l = tex("line")
			l:SetPoint(spec[1], spec[2], spec[3])
			l:SetPoint(spec[4], spec[5], spec[6])
			if spec[7] then l:SetWidth(spec[7]) else l:SetHeight(spec[8]) end
		end
	end
	frame.pwRound = { fills = fills, lines = lines, radius = r }
	T.PaintRound(frame, ground or "bg", border == nil and "border" or border, ground == nil and ns.Get("ui.opacity") or nil)
	return frame
end

-- Recolour a T.Round frame. alpha/borderAlpha override the colours' own.
function T.PaintRound(frame, ground, border, alpha, borderAlpha)
	local rd = rawget(frame, "pwRound")
	if not rd then return end
	local function apply(list, name, a)
		local c = type(name) == "table" and name or T.Color(name)
		for _, t in ipairs(list) do
			if rawget(t, "pwCorner") then
				t:SetVertexColor(c[1], c[2], c[3], a or c[4])
			else
				t:SetColorTexture(c[1], c[2], c[3], a or c[4])
			end
		end
	end
	if ground then apply(rd.fills, ground, alpha) rd.ground, rd.alpha = ground, alpha end
	if border then apply(rd.lines, border, borderAlpha) end
end

-- A rounded window ground that follows the opacity setting.
function T.RoundWindow(frame, radius)
	T.Round(frame, nil, "border", radius or 10)
	T.TrackGround(frame)
	return frame
end

-- A text in a type role at a size of its own (the hub's big titles).
function T.TextAt(parent, weight, size, color)
	local fs = ns.HookText(parent:CreateFontString(nil, "OVERLAY"))
	if not fs:SetFont(T.FONTS[weight] or T.FONTS.regular, size, "") then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end
	local c = T.Color(color or "text")
	fs:SetTextColor(c[1], c[2], c[3], c[4])
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	return fs
end

-- A glyph texture tinted a colour (Media/<name>.tga).
function T.Glyph(parent, name, size, color, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetTexture(MEDIA .. name)
	t:SetSize(size or 16, size or 16)
	local c = T.Color(color or "text2")
	t:SetVertexColor(c[1], c[2], c[3], c[4])
	return t
end

-- The Pathwise emblem (v2, from the addon's logo): its metal in the
-- theme's silver, its star and path in the accent. Media/icon is the same
-- emblem in fixed colours, for the addon list and the minimap button.
function T.Logo(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 32, size or 32)
	holder.body = holder:CreateTexture(nil, "ARTWORK")
	holder.body:SetTexture(MEDIA .. "logo-body")
	holder.body:SetAllPoints()
	holder.glow = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.glow:SetTexture(MEDIA .. "logo-glow")
	holder.glow:SetAllPoints()
	function holder:Paint()
		local b, g = T.Color("silver"), T.Color("accent")
		self.body:SetVertexColor(b[1], b[2], b[3], 1)
		self.glow:SetVertexColor(g[1], g[2], g[3], 1)
	end
	holder:Paint()
	return holder
end

-- The faction crest (v2): Pathwise's own badges after the factions'
-- emblems: for the Alliance a blue shield in a flaming gold border, for the
-- Horde a red spiked arch on two blades; in each, the Pathwise star and its
-- winding path. No faction: the shield in the theme's colours.
T.FACTION = { Alliance = hex("#2A4FA8"), Horde = hex("#9E2B25") }
local CREST = {
	Alliance = { shape = "crest-alliance", fill = "#2A4FA8", edge = "#E4B96D", mark = "#F2D387" },
	Horde = { shape = "crest-horde", fill = "#9E2B25", edge = "#1E1414", mark = "#F2D387" },
}
function T.Crest(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 40, size or 40)
	holder.fill = holder:CreateTexture(nil, "ARTWORK")
	holder.fill:SetAllPoints()
	holder.edge = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.edge:SetAllPoints()
	holder.mark = holder:CreateTexture(nil, "OVERLAY")
	holder.mark:SetAllPoints()
	local function tint(tex, c) tex:SetVertexColor(c[1], c[2], c[3], 1) end
	function holder:SetFaction(f)
		local spec = CREST[f]
		local shape = spec and spec.shape or "crest-alliance"
		self.fill:SetTexture(MEDIA .. shape)
		self.edge:SetTexture(MEDIA .. shape .. "-edge")
		self.mark:SetTexture(MEDIA .. shape .. "-mark")
		tint(self.fill, spec and hex(spec.fill) or T.Color("bg2"))
		tint(self.edge, spec and hex(spec.edge) or T.Color("border"))
		tint(self.mark, spec and hex(spec.mark) or T.Color("accent"))
		self.faction = f
	end
	holder:SetFaction(nil)
	return holder
end

-- Whether to show the game's own art (class and profession icons, zone
-- maps). The preview (tools/preview) has no game files: it shows Pathwise's
-- own drawings, as the game does where its art is missing.
function T.GameArt() return not PATHWISE_PREVIEW end

-- The game's icon for each profession (Interface\Icons).
T.PROF_ICONS = {
	alchemy = "Trade_Alchemy", blacksmithing = "Trade_BlackSmithing", enchanting = "Trade_Engraving",
	engineering = "Trade_Engineering", leatherworking = "INV_Misc_ArmorKit_17", tailoring = "Trade_Tailoring",
	herbalism = "Trade_Herbalism", mining = "Trade_Mining", skinning = "INV_Misc_Pelt_Wolf_01",
	cooking = "INV_Misc_Food_15", ["first-aid"] = "Spell_Holy_SealOfSacrifice", fishing = "Trade_Fishing",
}

-- A class or profession mark: the game's icon where it has one, else
-- Pathwise's drawing (Media/class-<class>, Media/prof-<key>) tinted.
function T.Mark(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 24, size or 24)
	holder.glyph = holder:CreateTexture(nil, "ARTWORK")
	holder.glyph:SetPoint("CENTER")
	holder.glyph:SetSize((size or 24) * 0.82, (size or 24) * 0.82)
	holder.icon = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.icon:SetAllPoints()
	local function show(gameTex, coords, drawn, color)
		local game = T.GameArt() and gameTex ~= nil
		holder.icon:SetShown(game)
		holder.glyph:SetShown(not game and drawn ~= nil)
		if game then
			holder.icon:SetTexture(gameTex)
			holder.icon:SetTexCoord(unpack(coords))
		elseif drawn then
			holder.glyph:SetTexture(MEDIA .. drawn)
			local c = T.Color(color or "text")
			holder.glyph:SetVertexColor(c[1], c[2], c[3], 1)
		end
	end
	function holder:SetClass(classFile, color)
		local tc = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
		show(tc and "Interface\\TargetingFrame\\UI-Classes-Circles" or nil, tc or { 0, 1, 0, 1 },
			classFile and ("class-" .. classFile:lower()) or nil, color)
	end
	function holder:SetProfession(key, color)
		local icon = key and T.PROF_ICONS[key]
		show(icon and ("Interface\\Icons\\" .. icon) or nil, { 0.07, 0.93, 0.07, 0.93 }, key and ("prof-" .. key) or nil, color)
	end
	return holder
end

-- A checkbox look (not a control): box, fill and tick. :SetChecked(on).
function T.Check(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	size = size or 18
	holder:SetSize(size, size)
	holder.fill = holder:CreateTexture(nil, "ARTWORK")
	holder.fill:SetTexture(MEDIA .. "box-fill")
	holder.fill:SetAllPoints()
	holder.box = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.box:SetTexture(MEDIA .. "box")
	holder.box:SetAllPoints()
	holder.tick = holder:CreateTexture(nil, "OVERLAY")
	holder.tick:SetTexture(MEDIA .. "check")
	holder.tick:SetAllPoints()
	function holder:SetChecked(on)
		local c = T.Color(on and "accent" or "muted")
		self.box:SetVertexColor(c[1], c[2], c[3], 1)
		self.fill:SetShown(on and true or false)
		if on then self.fill:SetVertexColor(c[1], c[2], c[3], 1) end
		local d = T.Color("bg")
		self.tick:SetVertexColor(d[1], d[2], d[3], 1)
		self.tick:SetShown(on and true or false)
		self.checked = on and true or false
	end
	holder:SetChecked(false)
	return holder
end

-- A thick rounded progress bar (the hub's): track and fill, 4-6 px.
function T.Bar(parent, height, color)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(height or 6)
	T.Round(bar, "border", false, math.floor((height or 6) / 2))
	bar.fill = CreateFrame("Frame", nil, bar)
	bar.fill:SetPoint("TOPLEFT")
	bar.fill:SetPoint("BOTTOMLEFT")
	T.Round(bar.fill, color or "accent", false, math.floor((height or 6) / 2))
	function bar:SetProgress(p, width)
		p = math.max(0, math.min(1, p or 0))
		local w = width or self:GetWidth() or 0
		self.progress = p
		if p <= 0 or w <= 0 then self.fill:Hide() return end
		self.fill:Show()
		self.fill:SetWidth(math.max(height or 6, w * p))
	end
	-- Width known only once laid out: draw again when it changes size.
	bar:SetScript("OnSizeChanged", function(self) self:SetProgress(self.progress or 0) end)
	return bar
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
	local fs = ns.HookText(parent:CreateFontString(nil, layer or "OVERLAY"))
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

-- Every text button, to draw its label again (T.Relabel).
local labelled = setmetatable({}, { __mode = "k" })

-- A low-profile text button: dark surface, 1 px outline.
-- kind "default" (Back) or "accent" (Next).
function T.Button(parent, label, kind, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(28)
	local accent = kind == "accent"
	T.Panel(b, "bg2", "border", 6) -- rounded (v2)
	local edges = b.pwEdges
	local text = T.Text(b, "button", accent and "accent" or "text2")
	text:SetPoint("CENTER")
	text:SetText(label)
	b.pwText = text
	b.pwLabel = label
	labelled[b] = true
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

-- The hub's rounded button (v2). kind "default" (Back, Skip: dark with a
-- border), "primary" (Next: filled accent, dark label) or "outline" (Go:
-- accent border on a faint accent ground).
function T.RoundButton(parent, label, kind, onClick, height)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(height or 36)
	kind = kind or "default"
	T.Round(b, "bg2", "border", 6)
	local text = T.Text(b, "button", "text")
	text:SetPoint("CENTER")
	text:SetText(label)
	b.pwText, b.pwLabel, b.pwKind = text, label, kind
	labelled[b] = true
	local function paint(hover)
		if kind == "primary" then
			T.PaintRound(b, hover and "accentHover" or "accent", hover and "accentHover" or "accent")
			T.TextColor(text, "bg")
		elseif kind == "outline" then
			local a = T.Color("accent")
			T.PaintRound(b, { a[1], a[2], a[3], hover and 0.24 or 0.12 }, hover and "accentHover" or "accent")
			T.TextColor(text, "text")
		else
			T.PaintRound(b, hover and "hover" or "bg2", "border")
			T.TextColor(text, hover and "text" or "text")
		end
	end
	b.pwPaint = paint
	paint(false)
	b:SetScript("OnEnter", function() paint(true) end)
	b:SetScript("OnLeave", function() paint(false) end)
	if onClick then b:SetScript("OnClick", onClick) end
	b:SetWidth(math.max(64, (text:GetStringWidth() or 30) + 32))
	return b
end

-- A label set while the game is still loading our font file can draw blank
-- until a /reload (seen on the guide's Back, Skip and Next after a fresh
-- start). Setting the font and text again once it has loaded draws it.
function T.Relabel(b)
	local text, label = b.pwText, b.pwLabel
	if not text or not label then return end
	T.Font(text, "button")
	text:SetText("")
	text:SetText(label)
	b:SetWidth(math.max(64, (text:GetStringWidth() or 30) + 28))
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	for b in pairs(labelled) do T.Relabel(b) end
end)

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
			ns.Tip.SetText(GameTooltip, tip, 1, 1, 1)
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

-- The pin (v2): anchors a window where it is. Click to pin or unpin; pinned,
-- it is tinted in the accent, and the window ignores drags. `path` is the
-- window's setting ("hub.locked"); the window checks it when dragged.
local pins = {}
function T.PinButton(parent, path, size)
	local b = T.IconButton(parent, "pin", nil, function() ns.Set(path, not ns.Get(path)) end, size)
	b.pwPath = path
	local function paint(hover)
		local c = T.Color(ns.Get(path) and "accent" or (hover and "text" or "text2"))
		b.pwIcon:SetVertexColor(c[1], c[2], c[3], 1)
	end
	b.pwPaint = paint
	local enter, leave = b:GetScript("OnEnter"), b:GetScript("OnLeave")
	b:SetScript("OnEnter", function(self)
		enter(self)
		paint(true)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			ns.Tip.SetText(GameTooltip, ns.Get(path) and "Pinned in place" or "Pin in place", 1, 1, 1)
			ns.Tip.AddLine(GameTooltip, ns.Get(path) and "Click to unpin and drag it again." or "Click so it cannot be dragged by accident.", nil, nil, nil, true)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function(self) leave(self) paint(false) end)
	paint(false)
	pins[#pins + 1] = b
	return b
end

-- The resize grip (v2): the corner you drag to make a window any size
-- (o.height: both ways; else only its width, the height fitting what it
-- shows). The top-left corner stays put while the grip follows the cursor.
--   o = { minW, maxW, minH, maxH, height, lockPath,
--         onSize(w, h) while dragging, onDone(w, h) let go, onReset() right-click,
--         centered: the window grows both ways from its middle (the compass),
--         at: the frame to put the grip on (default the window) }
-- A pinned window (o.lockPath) does not resize. Returns the grip.
function T.Grip(frame, o)
	frame:SetResizable(true)
	if frame.SetResizeBounds then frame:SetResizeBounds(o.minW, o.minH or 1, o.maxW, o.maxH or 4000) end
	local host = o.at or frame
	local g = CreateFrame("Button", nil, host)
	g:SetSize(16, 16)
	g:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
	g:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
	g.icon = g:CreateTexture(nil, "OVERLAY")
	g.icon:SetTexture(MEDIA .. "glyph-resize")
	g.icon:SetSize(12, 12)
	g.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	local st = {}
	g.pwState = st
	local function paint()
		local c = T.Color(st.held and "accent" or (st.over and "text" or "muted"))
		g.icon:SetVertexColor(c[1], c[2], c[3], 1)
	end
	local function clamp(v, lo, hi) return math.min(hi or v, math.max(lo or v, v)) end
	local function cursor()
		local x, y = GetCursorPosition()
		local sc = frame:GetEffectiveScale() or 1
		return x / sc, y / sc
	end
	local function update()
		local x, y = cursor()
		local w = math.floor(clamp(st.w0 + (x - st.x0) * (o.centered and 2 or 1), o.minW, o.maxW) + 0.5)
		local h = o.height and math.floor(clamp(st.h0 + (st.y0 - y), o.minH, o.maxH) + 0.5) or nil
		if w == st.w and h == st.h then return end
		st.w, st.h = w, h
		frame:SetWidth(w)
		if h then frame:SetHeight(h) end
		if o.onSize then o.onSize(w, h) end
	end
	local function stop()
		if not st.held then return end
		st.held = nil
		paint()
		g:SetScript("OnUpdate", nil)
		if o.onDone then o.onDone(st.w or frame:GetWidth(), st.h) end
	end
	g:SetScript("OnMouseDown", function(_, button)
		if button and button ~= "LeftButton" then return end
		if o.lockPath and ns.Get(o.lockPath) then return end
		local l, t = frame:GetLeft(), frame:GetTop()
		if l and t and not o.centered then
			frame:ClearAllPoints()
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
		end
		st.x0, st.y0 = cursor()
		st.w0, st.h0 = frame:GetWidth(), frame:GetHeight()
		st.w, st.h, st.held = nil, nil, true
		paint()
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
		paint()
		if GameTooltip and not st.held then
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			ns.Tip.SetText(GameTooltip, "Resize", 1, 1, 1)
			if o.lockPath and ns.Get(o.lockPath) then
				ns.Tip.AddLine(GameTooltip, "Pinned: unpin it to resize.", nil, nil, nil, true)
			else
				ns.Tip.AddLine(GameTooltip, o.height and "Drag to change the width and height." or "Drag to change the width.", nil, nil, nil, true)
				ns.Tip.AddLine(GameTooltip, "Right-click: back to the usual size.", nil, nil, nil, true)
			end
			GameTooltip:Show()
		end
	end)
	g:SetScript("OnLeave", function()
		st.over = nil
		paint()
		if GameTooltip then GameTooltip:Hide() end
	end)
	paint()
	return g
end

-- Whether a window pinned with `path` may move now.
function T.Movable(path) return not ns.Get(path) end

ns.On("SETTING_CHANGED", function(path)
	for _, b in ipairs(pins) do if b.pwPath == path then b.pwPaint(false) end end
end)

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
	-- The wheel scrolls the list the slider sits in (scrolling past a slider
	-- must not move it); Shift + wheel steps the value.
	s:SetScript("OnMouseWheel", function(self, delta)
		if IsShiftKeyDown and IsShiftKeyDown() then
			self:SetValue(math.max(min, math.min(max, (self:GetValue() or min) + delta * step)))
			return
		end
		local p = self:GetParent()
		while p do
			local wheel = p.GetScript and p:GetScript("OnMouseWheel")
			if type(wheel) == "function" then return wheel(p, delta) end
			p = p.GetParent and p:GetParent() or nil
		end
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
-- A new theme: every tracked window ground takes it at once (texts and
-- the rest follow after a reload).
ns.On("THEME_CHANGED", function()
	local a = ns.Get("ui.opacity")
	for frame in pairs(grounds) do
		if rawget(frame, "pwRound") then T.PaintRound(frame, "bg", "border", a)
		elseif frame.pwGround then setColor(frame.pwGround, "bg", a) end
	end
end)
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
			if rawget(frame, "pwRound") then T.PaintRound(frame, "bg", nil, value)
			elseif frame.pwGround then setColor(frame.pwGround, "bg", value) end
		end
	elseif path == "ui.scale" then
		for frame in pairs(scaled) do frame:SetScale(value or 1) end
	end
end)
