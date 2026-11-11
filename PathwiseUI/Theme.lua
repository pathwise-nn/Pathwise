-- Pathwise UI's look: a theme (Pathwise's 17, dark and light: Pathwise Blue
-- by default), your own colors on top of it, the Inter typeface, and the
-- accent: the theme's, your class color, or one you pick.
-- When Pathwise is installed too, the two keep one theme and one accent: a
-- change in either is copied to the other.

-- Shared file (see Core.lua): edit it here, then run npm run kit.
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

-- The themes: Pathwise's 17 (the same keys, names and colors as its
-- Theme/Signature.lua T.THEMES, copied here so this addon stands alone),
-- dark or light. Pathwise and Pathwise UI keep one theme when both are
-- installed (Pathwise's setting "ui.theme" is our "look.scheme").
-- world: a light theme's accent for things drawn on the game world.
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

-- Pathwise UI paints more than Pathwise's palette: money, the trim and
-- the unit frames. Dark themes share one set; light ones take darker
-- colors, so text in them reads on a light ground (4.5:1 or more).
-- Reaction colors follow the theme's status colors.
local EXTRA = {
	dark = { gold = "#E8C26A", silver = "#C9D3DC", copper = "#D08A5C", flair = "#E8C26A",
		mana = "#4F8FE8", energy = "#E4D46D", focus = "#E0956A", poison = "#59D9B2",
		magic = "#4F8FE8", curse = "#B69CFF", disease = "#C9A04F" },
	light = { gold = "#7A5600", silver = "#5A6573", copper = "#9A4A1C", flair = "#7A5600",
		mana = "#2F6FD0", energy = "#9A7F00", focus = "#B4602A", poison = "#0F7556",
		magic = "#2F6FD0", curse = "#6E45C8", disease = "#86651C" },
}
local PALETTE = { "bg", "bg2", "hover", "border", "divider", "text", "text2", "muted", "accent", "success", "warning", "error" }

local function lift(h, by)
	local c = hex(h)
	return T.ToHex({ c[1] + (1 - c[1]) * by, c[2] + (1 - c[2]) * by, c[3] + (1 - c[3]) * by })
end

-- The schemes: a full set of colors per theme. Their accent is used when
-- you pick one.
T.SCHEMES = {}
for _, th in ipairs(T.THEMES) do
	local c = {}
	for k, v in pairs(EXTRA[th.mode] or EXTRA.dark) do c[k] = v end
	for _, k in ipairs(PALETTE) do c[k] = th[k] end
	c.hostile, c.neutral, c.friendly, c.rage = th.error, th.warning, th.success, th.error
	-- Dark health: a little above the border (the secondary text on a light theme).
	c.healthDark = th.mode == "light" and th.text2 or lift(th.border, 0.04)
	T.SCHEMES[#T.SCHEMES + 1] = { key = th.key, name = th.name, mode = th.mode, world = th.world, colors = c }
end
T.SCHEMES[1].colors.healthDark = "#2E4152" -- Pathwise UI's own, from before the themes

-- Schemes from before the themes, and the theme each became.
local RENAMED = { forest = "emerald", ember = "sunset", mono = "midnight" }
function T.Scheme(key)
	key = RENAMED[key] or key
	for _, s in ipairs(T.SCHEMES) do if s.key == key then return s end end
	return T.SCHEMES[1]
end
-- Is the theme in use a light one?
function T.IsLight() return T.Scheme(ns.Get("look.scheme")).mode == "light" end

-- The trim's choices: your class color, the scheme's gold, or your own.
T.TRIMS = { { "Class", "class" }, { "Default", "default" }, { "Custom", "custom" } }

T.COLORS = {}
for k, v in pairs(T.SCHEMES[1].colors) do T.COLORS[k] = hex(v) end
T.COLORS.accentHover = hex("#90E4FF")
T.PATHWISE_ACCENT = hex("#66D7FF")

-- Contrast between two colors (WCAG: 1 to 21).
local function luminance(c)
	local function ch(v) return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * ch(c[1]) + 0.7152 * ch(c[2]) + 0.0722 * ch(c[3])
end
function T.Contrast(a, b)
	local x, y = luminance(a), luminance(b)
	if x < y then x, y = y, x end
	return (x + 0.05) / (y + 0.05)
end

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
	sharePathwise = true, -- keep one theme and accent with Pathwise when it is installed
	scheme = "pathwise", -- the theme (T.THEMES; the same keys as Pathwise's "ui.theme")
	trim = "default", -- "class" | "default" (the scheme's gold) | "custom" (T.TRIMS)
	colors = nil, -- your own colors on top of it: { name = "#RRGGBB" }
})

local function valid(h) return type(h) == "string" and h:match("^#?%x%x%x%x%x%x$") ~= nil end
T.ValidHex = valid

-- On a light theme, a color picked for text (your class color, one off
-- the wheel) is darkened until it reads on the grounds: 4.5:1 or more.
function T.Legible(c)
	if not T.IsLight() then return c end
	local bg, bg2 = T.WantedColor("bg"), T.WantedColor("bg2")
	local out = { c[1], c[2], c[3], c[4] or 1 }
	for _ = 1, 20 do
		if math.min(T.Contrast(out, bg), T.Contrast(out, bg2)) >= 4.5 then break end
		out[1], out[2], out[3] = out[1] * 0.9, out[2] * 0.9, out[3] * 0.9
	end
	return out
end

-- A color as the scheme and your picks say (not the accent: see below).
function T.WantedColor(name)
	if name == "flair" then
		local t = ns.Get("look.trim")
		if t == "class" then
			local c = T.ClassColor()
			if c then return T.Legible(c) end
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

-- A whole theme: its colors, and its own accent as your accent.
function T.UseScheme(key)
	local s = T.Scheme(key)
	ns.Set("look.colors", nil)
	ns.Set("look.scheme", s.key)
	ns.Set("look.accentColor", s.colors.accent)
	ns.Set("look.accentMode", "pathwise")
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
-- A little darker (hover on a light theme, and on a white accent).
local function darken(c, by)
	return { c[1] * (1 - by), c[2] * (1 - by), c[3] * (1 - by), 1 }
end

-- "pathwise" is the theme's own accent (Pathwise Blue's is Pathwise blue),
-- as in Pathwise. On a light theme, a class or custom accent is darkened
-- until it reads (T.Legible).
function T.WantedAccent()
	local mode = ns.Get("look.accentMode")
	local own = hex(T.Scheme(ns.Get("look.scheme")).colors.accent)
	if mode == "class" then return T.Legible(T.ClassColor() or own) end
	if mode == "custom" then
		local h = ns.Get("look.accentColor")
		if type(h) == "string" and h:match("^#?%x%x%x%x%x%x$") then return T.Legible(hex(h)) end
	end
	return own
end

function T.ApplyAccent()
	local c = T.WantedAccent()
	local light = T.IsLight() or (c[1] + c[2] + c[3]) > 2.85
	local hov = light and darken(c, 0.18) or lighten(c, 0.3)
	for i = 1, 4 do T.COLORS.accent[i] = c[i] T.COLORS.accentHover[i] = hov[i] end
	ns.Fire("ACCENT_CHANGED", c)
	return c
end

-- Keeping one theme and one accent with Pathwise: its settings "ui.theme",
-- "ui.accentMode" and "ui.accentColor" mean the same as our "look.scheme",
-- "look.accentMode" and "look.accentColor".
local syncing = false
local function toPathwise()
	local S = ns.Suite()
	if not (S and ns.Get("look.sharePathwise")) or syncing then return end
	syncing = true
	pcall(S.Set, "ui.theme", T.Scheme(ns.Get("look.scheme")).key)
	pcall(S.Set, "ui.accentMode", ns.Get("look.accentMode"))
	pcall(S.Set, "ui.accentColor", ns.Get("look.accentColor"))
	syncing = false
end
-- Pathwise's theme, when it is one we know.
local function pathwiseTheme(S)
	local ok, key = pcall(S.Get, "ui.theme")
	return ok and T.THEME_BY[key] and key or nil
end
local function fromPathwise(path)
	local S = ns.Suite()
	if not (S and ns.Get("look.sharePathwise")) or syncing then return end
	if path ~= "ui.theme" and path ~= "ui.accentMode" and path ~= "ui.accentColor" then return end
	syncing = true
	if path == "ui.theme" then
		local key = pathwiseTheme(S)
		if key then ns.Set("look.scheme", key) end
	else
		ns.Set("look.accentMode", S.Get("ui.accentMode"))
		ns.Set("look.accentColor", S.Get("ui.accentColor"))
	end
	syncing = false
end
-- At login: still on the first theme while Pathwise has picked another?
-- Take Pathwise's (else ours goes to Pathwise, like the accent).
local function themeFromPathwise()
	local S = ns.Suite()
	if not (S and ns.Get("look.sharePathwise")) then return end
	local key = pathwiseTheme(S)
	if key and key ~= "pathwise" and T.Scheme(ns.Get("look.scheme")).key == "pathwise" then
		syncing = true
		ns.Set("look.scheme", key)
		syncing = false
	end
end

-- One theme and accent with the other Pathwise addons built on these files
-- (Pathwise UI, Heal, Encounters, Loot; ns.Peers). Same setting names, so a
-- value is simply copied; copying stops when the two agree, so nothing loops.
local SHARED = { "look.scheme", "look.accentMode", "look.accentColor" }
local function toPeers()
	if not ns.Get("look.sharePathwise") then return end
	for _, P in ipairs(ns.Peers()) do
		if P.Get("look.sharePathwise") then
			for _, k in ipairs(SHARED) do
				if P.Get(k) ~= ns.Get(k) then P.Set(k, ns.Get(k)) end
			end
		end
	end
end
-- At login: take the theme and accent of a peer listed before this addon
-- (Pathwise UI's wins), so two addons never start in two colors.
local function fromEarlierPeer()
	if not ns.Get("look.sharePathwise") then return end
	for _, g in ipairs(ns.PEERS) do
		if g == ns.ID.global then return end
		local P = _G[g]
		if type(P) == "table" and P.Get and P.Get("look.sharePathwise") then
			-- Read them all first: each change here is copied on to the peers.
			local want = {}
			for i, k in ipairs(SHARED) do want[i] = P.Get(k) end
			for i, k in ipairs(SHARED) do
				if want[i] ~= ns.Get(k) then ns.Set(k, want[i]) end
			end
			return
		end
	end
end
T.SyncPeers = toPeers

ns.On("LOADED", function() T.ApplyColors() end)
ns.On("READY", function()
	T.ApplyColors()
	fromEarlierPeer()
	local S = ns.Suite()
	if S then
		themeFromPathwise()
		toPathwise()
		S.On("SETTING_CHANGED", fromPathwise)
	end
end)
ns.On("SETTING_CHANGED", function(path)
	if path == "look.accentMode" or path == "look.accentColor" then
		T.ApplyAccent()
		toPathwise()
		toPeers()
	elseif path == "look.scheme" then
		T.ApplyColors()
		toPathwise()
		toPeers()
	elseif path == "look.colors" or path == "look.trim" or path == "*" or path == "look.*" or path == "profile.shared" then
		T.ApplyColors()
	elseif path == "look.sharePathwise" then
		T.ApplyAccent()
	end
end)
