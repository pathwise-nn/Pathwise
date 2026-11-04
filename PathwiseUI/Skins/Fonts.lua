-- The game's text in Pathwise's typeface (Inter), at the size you like.
-- Every font of the game (Skins/FontNames.lua, from Forever's own font files)
-- gets Inter at its own size times your scale, keeping its outline. Titles,
-- headers and numbers take the semibold cut. The game's own font is put back
-- when you switch it off (exactly, from what was there before).

local ADDON, ns = ...
local T = ns.Theme
local F = {}
ns.Fonts = F

ns.Defaults("fonts", {
	pathwise = true, -- Inter everywhere
	scale = 1, -- 0.8 - 1.3
})

local original = {} -- font name -> { file, size, flags } as the game had it

local function cut(name)
	local n = name:lower()
	if n:find("header") or n:find("title") or n:find("number") or n:find("large") or n:find("huge") or n:find("zone") then
		return T.FONTS.semibold
	end
	return T.FONTS.regular
end

-- -> how many fonts were changed
function F.Apply()
	local on, scale = ns.Get("fonts.pathwise"), ns.Get("fonts.scale") or 1
	local n = 0
	for _, name in ipairs(ns.FONT_NAMES or {}) do
		local font = _G[name]
		if type(font) == "table" and font.GetFont and font.SetFont then
			local ok, file, size, flags = pcall(font.GetFont, font)
			if ok and file and size then
				original[name] = original[name] or { file, size, flags }
				local o = original[name]
				local set
				if on then set = { cut(name), math.floor(o[2] * scale * 10 + 0.5) / 10, o[3] or "" }
				else set = { o[1], o[2], o[3] or "" } end
				if pcall(font.SetFont, font, set[1], set[2], set[3]) then n = n + 1 end
			end
		end
	end
	-- The fonts the game reads from these when it draws names and chat bubbles.
	if on then
		STANDARD_TEXT_FONT = T.FONTS.regular
		UNIT_NAME_FONT = T.FONTS.semibold
	end
	return n
end

ns.On("READY", function() if ns.Get("fonts.pathwise") then F.Apply() end end)
ns.On("SETTING_CHANGED", function(path)
	if path == "fonts.pathwise" or path == "fonts.scale" or path == "fonts.*" or path == "*" then F.Apply() end
end)
