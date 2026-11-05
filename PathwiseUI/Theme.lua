-- Pathwise UI's look: a color scheme (Pathwise Signature by default, or
-- another, or entirely your own), the Inter typeface, and the accent:
-- Pathwise blue, your class color, or one you pick.
-- When Pathwise is installed too, the two keep one accent: a change in either
-- is copied to the other.

local ADDON, ns = ...
local T = {}
ns.Theme = T

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
T.MEDIA = MEDIA

local function hex(h, a)
	h = h:gsub("#", "")
	return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1 }
end
T.Hex = hex

function T.ToHex(c)
	return ("#%02X%02X%02X"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- Every color Pathwise UI draws with. Each one can be changed (the Colors
-- page): a scheme sets them all, and your own picks go on top of it.
-- T.COLORS keeps the same tables for the whole session (painted things hold
-- them), so a change is copied into them in place.
T.COLOR_GROUPS = {
	{ name = "Surfaces", keys = {
		{ "bg", "Window ground" }, { "bg2", "Panels and buttons" }, { "hover", "Hover" },
		{ "border", "Borders" }, { "divider", "Dividers" } } },
	{ name = "Text", keys = { { "text", "Text" }, { "text2", "Secondary text" }, { "muted", "Faint text" } } },
	{ name = "Status", keys = { { "success", "Good" }, { "warning", "Warning" }, { "error", "Bad" } } },
	{ name = "Money", keys = { { "gold", "Gold" }, { "silver", "Silver" }, { "copper", "Copper" } } },
	{ name = "Trim", keys = { { "flair", "Headings and trim" } } },
	{ name = "Unit frames", keys = {
		{ "hostile", "Hostile" }, { "neutral", "Neutral" }, { "friendly", "Friendly" }, { "healthDark", "Dark health" },
		{ "mana", "Mana" }, { "rage", "Rage" }, { "energy", "Energy" }, { "focus", "Focus" },
		{ "magic", "Magic debuff" }, { "curse", "Curse debuff" }, { "disease", "Disease debuff" }, { "poison", "Poison debuff" } } },
}

-- The schemes: a full set each. Their accent is used when you pick one.
T.SCHEMES = {
	{ key = "pathwise", name = "Pathwise", colors = {
		gold = "#E8C26A", silver = "#C9D3DC", copper = "#D08A5C",
		bg = "#10161E", bg2 = "#17212C", hover = "#223241", border = "#293B4B", divider = "#1F2D3A",
		text = "#F0F5FA", text2 = "#9AAFC0", muted = "#7A90A2", accent = "#66D7FF",
		success = "#59D9B2", warning = "#E4B96D", error = "#E66B78",
		hostile = "#E66B78", neutral = "#E4B96D", friendly = "#59D9B2", healthDark = "#2E4152",
		mana = "#4F8FE8", rage = "#E66B78", energy = "#E4D46D", focus = "#E0956A",
		magic = "#4F8FE8", curse = "#B69CFF", disease = "#C9A04F", poison = "#59D9B2" } },
	{ key = "blossom", name = "Blossom", colors = {
		gold = "#FFD27F", silver = "#E8D8E2", copper = "#F0A07A",
		bg = "#22121C", bg2 = "#2E1826", hover = "#422236", border = "#5A2E49", divider = "#3A1E30",
		text = "#FFF0F7", text2 = "#F0B8D4", muted = "#C48AA8", accent = "#FF7EB9",
		success = "#8EE3C8", warning = "#FFC98B", error = "#FF6F91",
		hostile = "#FF6F91", neutral = "#FFC98B", friendly = "#A8E6CF", healthDark = "#4A2A3C",
		mana = "#B39DFF", rage = "#FF6F91", energy = "#FFE29A", focus = "#FFB38A",
		magic = "#9DB8FF", curse = "#D49CFF", disease = "#E0B97A", poison = "#8EE3C8" } },
	{ key = "lavender", name = "Lavender", colors = {
		gold = "#F2D27E", silver = "#D8D4EC", copper = "#E0A07E",
		bg = "#17142A", bg2 = "#201C38", hover = "#2E2850", border = "#3E3666", divider = "#28234A",
		text = "#F4F0FF", text2 = "#C3B8F0", muted = "#968CC0", accent = "#B79CFF",
		success = "#7FE0C2", warning = "#F2C47E", error = "#F27A9B",
		hostile = "#F27A9B", neutral = "#F2C47E", friendly = "#7FE0C2", healthDark = "#3A3360",
		mana = "#7FA6FF", rage = "#F27A9B", energy = "#F2E27E", focus = "#F2A37E",
		magic = "#7FA6FF", curse = "#C99CFF", disease = "#D6B27A", poison = "#7FE0C2" } },
	{ key = "forest", name = "Forest", colors = {
		gold = "#E3C86A", silver = "#CCD6CE", copper = "#D0925C",
		bg = "#0F1712", bg2 = "#16221A", hover = "#203226", border = "#2C4433", divider = "#1C2C21",
		text = "#EEF6EF", text2 = "#A9C4AF", muted = "#7F9C86", accent = "#7FD98F",
		success = "#7FD98F", warning = "#E3C26A", error = "#E07A6A",
		hostile = "#E07A6A", neutral = "#E3C26A", friendly = "#7FD98F", healthDark = "#2C4433",
		mana = "#5F9FE0", rage = "#E07A6A", energy = "#E3D46A", focus = "#E0A06A",
		magic = "#5F9FE0", curse = "#B08CE0", disease = "#C9A04F", poison = "#7FD98F" } },
	{ key = "ember", name = "Ember", colors = {
		gold = "#FFD06B", silver = "#E6D6CF", copper = "#E8925C",
		bg = "#1A1210", bg2 = "#251916", hover = "#36231E", border = "#4A3029", divider = "#2E1F1A",
		text = "#FFF3EE", text2 = "#E0B9A8", muted = "#B08A7A", accent = "#FF9A5C",
		success = "#7FD9A8", warning = "#FFD06B", error = "#FF6B5C",
		hostile = "#FF6B5C", neutral = "#FFD06B", friendly = "#7FD9A8", healthDark = "#4A3029",
		mana = "#5C9CFF", rage = "#FF6B5C", energy = "#FFE06B", focus = "#FF9A5C",
		magic = "#5C9CFF", curse = "#C08CFF", disease = "#D6A85C", poison = "#7FD9A8" } },
	{ key = "mono", name = "Mono", colors = {
		gold = "#E0C98A", silver = "#D0D0D0", copper = "#C09A80",
		bg = "#111111", bg2 = "#1A1A1A", hover = "#262626", border = "#333333", divider = "#222222",
		text = "#F2F2F2", text2 = "#B0B0B0", muted = "#808080", accent = "#FFFFFF",
		success = "#9ED99E", warning = "#E0C98A", error = "#E08A8A",
		hostile = "#E08A8A", neutral = "#E0C98A", friendly = "#9ED99E", healthDark = "#3A3A3A",
		mana = "#8AA8E0", rage = "#E08A8A", energy = "#E0D68A", focus = "#E0AE8A",
		magic = "#8AA8E0", curse = "#B89AE0", disease = "#C9AE7A", poison = "#9ED99E" } },
}
function T.Scheme(key)
	for _, s in ipairs(T.SCHEMES) do if s.key == key then return s end end
	return T.SCHEMES[1]
end

-- The trim (window title, headings, their lines) starts as each scheme's gold.
for _, s in ipairs(T.SCHEMES) do s.colors.flair = s.colors.flair or s.colors.gold end

-- The trim's choices: your class color, the scheme's gold, or your own.
T.TRIMS = { { "Class", "class" }, { "Default", "default" }, { "Custom", "custom" } }

T.COLORS = {}
for k, v in pairs(T.SCHEMES[1].colors) do T.COLORS[k] = hex(v) end
T.COLORS.accentHover = hex("#90E4FF")
T.PATHWISE_ACCENT = hex("#66D7FF")

T.FONTS = {
	regular = MEDIA .. "Fonts\\Inter-Regular.ttf",
	medium = MEDIA .. "Fonts\\Inter-Medium.ttf",
	semibold = MEDIA .. "Fonts\\Inter-SemiBold.ttf",
	serif = MEDIA .. "Fonts\\CormorantGaramond-Bold.ttf", -- titles, headings and names
}
T.TYPE = {
	window = { "semibold", 13, "text" }, title = { "semibold", 15, "text" }, body = { "regular", 13, "text" },
	meta = { "regular", 12, "text2" }, small = { "regular", 11, "muted" }, label = { "medium", 10, "text2" },
	button = { "medium", 12, "text2" },
	-- Wayfarer: serif titles, headings and names, the trim color for the first two.
	wtitle = { "serif", 21, "flair" }, heading = { "serif", 17, "flair" },
	uname = { "serif", 16, "text" }, unameSmall = { "serif", 14, "text" },
}

ns.Defaults("look", {
	accentMode = "class", -- "pathwise" | "class" | "custom": Pathwise UI starts in your class color
	accentColor = "#66D7FF",
	opacity = 0.92, -- window and tooltip ground
	sharePathwise = true, -- keep one accent with Pathwise when it is installed
	scheme = "pathwise", -- the color set (T.SCHEMES)
	trim = "default", -- "class" | "default" (the scheme's gold) | "custom" (T.TRIMS)
	colors = nil, -- your own colors on top of it: { name = "#RRGGBB" }
})

local function valid(h) return type(h) == "string" and h:match("^#?%x%x%x%x%x%x$") ~= nil end
T.ValidHex = valid

-- A color as the scheme and your picks say (not the accent: see below).
function T.WantedColor(name)
	if name == "flair" then
		local t = ns.Get("look.trim")
		if t == "class" then
			local c = T.ClassColor()
			if c then return c end
		end
		if t ~= "custom" then
			local s = T.Scheme(ns.Get("look.scheme"))
			return hex(s.colors.flair)
		end
	end
	local own = ns.Get("look.colors")
	if type(own) == "table" and valid(own[name]) then return hex(own[name]) end
	local s = T.Scheme(ns.Get("look.scheme"))
	return hex(s.colors[name] or T.SCHEMES[1].colors[name] or "#FF00FF")
end
function T.IsOwnColor(name)
	local own = ns.Get("look.colors")
	return type(own) == "table" and valid(own[name])
end

-- Change one color (nil: back to the scheme's).
function T.SetColor(name, h)
	local own = {}
	local cur = ns.Get("look.colors")
	if type(cur) == "table" then for k, v in pairs(cur) do own[k] = v end end
	own[name] = h and (h:sub(1, 1) == "#" and h or "#" .. h):upper() or nil
	ns.Set("look.colors", next(own) and own or nil)
end

-- A whole scheme: its colors, and its accent as your accent.
function T.UseScheme(key)
	local s = T.Scheme(key)
	ns.Set("look.colors", nil)
	ns.Set("look.scheme", s.key)
	ns.Set("look.accentColor", s.colors.accent)
	ns.Set("look.accentMode", s.key == "pathwise" and "pathwise" or "custom")
end

-- Every color into T.COLORS (in place), then the accent.
function T.ApplyColors()
	for _, g in ipairs(T.COLOR_GROUPS) do
		for _, k in ipairs(g.keys) do
			local c = T.WantedColor(k[1])
			local t = T.COLORS[k[1]] or {}
			for i = 1, 4 do t[i] = c[i] end
			T.COLORS[k[1]] = t
		end
	end
	return T.ApplyAccent()
end

-- A scheme as text to share: "PWUI1:scheme:accent:bg=10161E,..." and back.
function T.ExportColors()
	local parts = {}
	for _, g in ipairs(T.COLOR_GROUPS) do
		for _, k in ipairs(g.keys) do parts[#parts + 1] = k[1] .. "=" .. T.ToHex(T.COLORS[k[1]]):sub(2) end
	end
	return ("PWUI1:%s:%s:%s"):format(ns.Get("look.scheme") or "pathwise", T.ToHex(T.COLORS.accent):sub(2), table.concat(parts, ","))
end
function T.ImportColors(text)
	text = (text or ""):gsub("%s", "")
	local scheme, accent, body = text:match("^PWUI1:(%w+):(%x%x%x%x%x%x):(.+)$")
	if not scheme then return false end
	local own = {}
	for k, v in body:gmatch("(%w+)=(%x%x%x%x%x%x)") do own[k] = "#" .. v:upper() end
	if not next(own) then return false end
	ns.Set("look.scheme", T.Scheme(scheme).key)
	ns.Set("look.colors", own)
	ns.Set("look.accentColor", "#" .. accent:upper())
	ns.Set("look.accentMode", "custom")
	return true
end

function T.Color(name)
	return T.COLORS[name] or T.COLORS.text
end

---------------------------------------------------------------------------
-- Crisp lines: one screen pixel at any UI scale
---------------------------------------------------------------------------
-- The game lays the UI out on a 768-unit-tall grid, scaled by UIParent; a
-- 1-unit border is then 0.7 or 1.4 screen pixels and blurs or doubles.
-- T.Pixel() is one real pixel in UIParent units; borders use it and opt out
-- of pixel snapping, so they stay a single sharp line.

local pixel = 1
function T.Pixel() return pixel end
function T.UpdatePixel()
	local h = GetPhysicalScreenSize and select(2, GetPhysicalScreenSize())
	local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
	if type(h) == "number" and h > 0 and type(scale) == "number" and scale > 0 then
		pixel = 768 / h / scale
	else
		pixel = 1
	end
	ns.Fire("PIXEL_CHANGED", pixel)
	return pixel
end

local function noSnap(t)
	if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
	if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
end
T.NoSnap = noSnap

-- A 1-pixel border on a frame: four edge textures.
-- -> border with :SetColor(r, g, b, a), :SetShown(on), .edges
local borders = setmetatable({}, { __mode = "k" })
local Border = {}
Border.__index = Border
function Border:SetColor(r, g, b, a) for _, e in ipairs(self.edges) do e:SetColorTexture(r, g, b, a or 1) end self.color = { r, g, b, a or 1 } end
function Border:SetShown(on) for _, e in ipairs(self.edges) do e:SetShown(on) end end
function Border:Layout()
	local px, inset = pixel, self.inset and pixel or 0
	local e = self.edges
	for _, t in ipairs(e) do t:ClearAllPoints() end
	e[1]:SetPoint("TOPLEFT", inset, -inset) e[1]:SetPoint("TOPRIGHT", -inset, -inset) e[1]:SetHeight(px)
	e[2]:SetPoint("BOTTOMLEFT", inset, inset) e[2]:SetPoint("BOTTOMRIGHT", -inset, inset) e[2]:SetHeight(px)
	e[3]:SetPoint("TOPLEFT", inset, -inset - px) e[3]:SetPoint("BOTTOMLEFT", inset, inset + px) e[3]:SetWidth(px)
	e[4]:SetPoint("TOPRIGHT", -inset, -inset - px) e[4]:SetPoint("BOTTOMRIGHT", -inset, inset + px) e[4]:SetWidth(px)
end

function T.Border(frame, layer, sublevel)
	local b = setmetatable({ edges = {} }, Border)
	for i = 1, 4 do
		local t = frame:CreateTexture(nil, layer or "BORDER", nil, sublevel)
		noSnap(t)
		b.edges[i] = t
	end
	b:Layout()
	borders[b] = true
	return b
end

ns.On("PIXEL_CHANGED", function() for b in pairs(borders) do b:Layout() end end)
ns.On("READY", T.UpdatePixel)
ns.RegisterEvent("UI_SCALE_CHANGED", function() T.UpdatePixel() end)
ns.RegisterEvent("DISPLAY_SIZE_CHANGED", function() T.UpdatePixel() end)

---------------------------------------------------------------------------
-- The accent
---------------------------------------------------------------------------

-- A class's color (Blizzard's C_ClassColor, else RAID_CLASS_COLORS);
-- the player's when no class is given.
function T.ClassColor(classFile)
	if not classFile then
		if not UnitClass then return nil end
		local _, c = UnitClass("player")
		classFile = ns.Readable(c)
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

local function lighten(c, by)
	return { c[1] + (1 - c[1]) * by, c[2] + (1 - c[2]) * by, c[3] + (1 - c[3]) * by, 1 }
end

function T.WantedAccent()
	local mode = ns.Get("look.accentMode")
	if mode == "class" then return T.ClassColor() or T.PATHWISE_ACCENT end
	if mode == "custom" then
		local h = ns.Get("look.accentColor")
		if type(h) == "string" and h:match("^#?%x%x%x%x%x%x$") then return hex(h) end
	end
	return T.PATHWISE_ACCENT
end

function T.ApplyAccent()
	local c = T.WantedAccent()
	local hov = lighten(c, 0.3)
	for i = 1, 4 do T.COLORS.accent[i] = c[i] T.COLORS.accentHover[i] = hov[i] end
	ns.Fire("ACCENT_CHANGED", c)
	return c
end

-- Keeping one accent with Pathwise (its settings "ui.accentMode" and
-- "ui.accentColor" mean the same as ours).
local syncing = false
local function toPathwise()
	local S = ns.Suite()
	if not (S and ns.Get("look.sharePathwise")) or syncing then return end
	syncing = true
	pcall(S.Set, "ui.accentMode", ns.Get("look.accentMode"))
	pcall(S.Set, "ui.accentColor", ns.Get("look.accentColor"))
	syncing = false
end
local function fromPathwise(path)
	local S = ns.Suite()
	if not (S and ns.Get("look.sharePathwise")) or syncing then return end
	if path ~= "ui.accentMode" and path ~= "ui.accentColor" then return end
	syncing = true
	ns.Set("look.accentMode", S.Get("ui.accentMode"))
	ns.Set("look.accentColor", S.Get("ui.accentColor"))
	syncing = false
end

ns.On("LOADED", function() T.ApplyColors() end)
ns.On("READY", function()
	T.ApplyColors()
	local S = ns.Suite()
	if S then
		toPathwise()
		S.On("SETTING_CHANGED", fromPathwise)
	end
end)
ns.On("SETTING_CHANGED", function(path)
	if path == "look.accentMode" or path == "look.accentColor" then
		T.ApplyAccent()
		toPathwise()
	elseif path == "look.scheme" or path == "look.colors" or path == "look.trim" or path == "*" or path == "look.*" or path == "profile.shared" then
		T.ApplyColors()
	elseif path == "look.sharePathwise" then
		T.ApplyAccent()
	end
end)
