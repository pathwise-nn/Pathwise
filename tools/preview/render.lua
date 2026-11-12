-- The preview's client additions, loaded after tests/stub.lua: the stub's
-- widgets remember what they are told; these add what drawing needs.
--   * anchors resolved as the client does (two points on an axis set the
--     size, one point and a size place it), so GetWidth, GetLeft and the
--     rest answer as in game, and every region gets a rectangle
--   * text measured with the real fonts (Python's `pymeasure`, Pillow)
--   * draw layers, sublevels, strata, texture coordinates, blend modes
-- render.Dump() lists every visible texture and text, back to front, for
-- tools/preview/preview.py to turn into a page.

local stub = ...
local Widget = getmetatable(UIParent)
local render = {}

-- The screen: 1600 x 900, or taller with PREVIEW_H (a whole long page at once).
local PREVIEW_H = tonumber(os.getenv("PREVIEW_H") or "") or 900
UIParent.w, UIParent.h = 1600, PREVIEW_H
local SCREEN_W, SCREEN_H = 1600, PREVIEW_H

---------------------------------------------------------------------------
-- What the stub forgot
---------------------------------------------------------------------------

local created = 0
local function stamp(region, layer, sub)
	created = created + 1
	rawset(region, "order", created)
	rawset(region, "layer", layer or "ARTWORK")
	rawset(region, "sublevel", sub or 0)
	return region
end

local baseTexture, baseFont = Widget.CreateTexture, Widget.CreateFontString
function Widget:CreateTexture(_, layer, _, sub) return stamp(baseTexture(self), layer, sub) end
function Widget:CreateFontString(name, layer, template) return stamp(baseFont(self, name, layer, template), layer or "OVERLAY", 0) end
-- An edit box's text (a copy box): drawn by a font string of its own, as
-- the game draws it, wrapped at any character (a code has no spaces).
local baseSetFont, baseSetText = Widget.SetFont, Widget.SetText
function Widget:SetFont(path, size, flags)
	if self.kind == "EditBox" then rawset(self, "boxFont", { path, size, flags }) end
	return baseSetFont(self, path, size, flags)
end
function Widget:SetText(t)
	baseSetText(self, t)
	if self.kind ~= "EditBox" then return end
	local m = rawget(self, "mirror")
	if not m then
		m = self:CreateFontString(nil, "OVERLAY")
		local f = rawget(self, "boxFont")
		if f then m:SetFont(f[1], f[2], f[3]) end
		m:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
		m:SetJustifyH("LEFT")
		m:SetJustifyV("TOP")
		m:SetWordWrap(true)
		rawset(self, "mirror", m)
	end
	local c = rawget(self, "textColor")
	if c then m:SetTextColor(c[1], c[2], c[3], c[4] or 1) end
	-- Break the text into lines that fit the box (about 6 px a character).
	local w = self:GetWidth() or 0
	if w <= 0 and #self.points >= 2 then w = 0 end
	local per = math.max(20, math.floor(((rawget(self, "parent") and rawget(self, "parent").w or 400) - 16) / 6.1))
	local out, s = {}, tostring(t or "")
	for i = 1, #s, per do out[#out + 1] = s:sub(i, i + per - 1) end
	-- No more lines than the box holds.
	local h = rawget(self, "parent") and rawget(self, "parent").h or 100
	local lines = math.max(1, math.floor((h - 12) / 14))
	while #out > lines do table.remove(out) end
	m:SetWidth(per * 6.1 + 10)
	m:SetText(table.concat(out, string.char(10)))
end
function Widget:SetDrawLayer(layer, sub) rawset(self, "layer", layer) rawset(self, "sublevel", sub or 0) end

function Widget:SetAllPoints(rel)
	self.points = {}
	rel = rel or rawget(self, "parent")
	self.points[1] = { "TOPLEFT", rel, "TOPLEFT", 0, 0 }
	self.points[2] = { "BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0 }
end

-- A scroll frame's child hangs from its top-left, moved by the scroll.
function Widget:SetScrollChild(child)
	rawset(self, "scrollChild", child)
	rawset(child, "scrollParent", self)
end

-- The points a region is placed by: its own, or a scroll child's.
local function pointsOf(region)
	local pts = region.points or {}
	if #pts == 0 then
		local sp = rawget(region, "scrollParent")
		if sp then return { { "TOPLEFT", sp, "TOPLEFT", 0, sp:GetVerticalScroll() or 0 } } end
	end
	return pts
end

function Widget:SetFont(file, size, flags)
	rawset(self, "font", file) rawset(self, "fontSize", size) rawset(self, "fontFlags", flags)
	rawset(self, "hasFont", true) -- the kit's stub checks a font is set
	return true
end
-- A font object (the kit's stub has some): its file and size.
function Widget:SetFontObject(o)
	rawset(self, "hasFont", true)
	if type(o) == "table" and o.GetFont then
		local file, size, flags = o:GetFont()
		rawset(self, "font", file) rawset(self, "fontSize", size) rawset(self, "fontFlags", flags)
	end
end
function Widget:GetFont() return rawget(self, "font"), rawget(self, "fontSize"), rawget(self, "fontFlags") end
function Widget:SetJustifyH(j) rawset(self, "justifyH", j) end
function Widget:SetJustifyV(j) rawset(self, "justifyV", j) end
function Widget:SetWordWrap(on) rawset(self, "wrap", on and true or false) end
function Widget:SetMaxLines(n) rawset(self, "maxLines", n) end
function Widget:SetShadowColor(r, g, b, a) rawset(self, "shadowColor", { r, g, b, a }) end
function Widget:SetTexCoord(l, r, t, b) rawset(self, "texCoord", { l, r, t, b }) end
function Widget:SetBlendMode(m) rawset(self, "blend", m) end
function Widget:SetFrameStrata(s) rawset(self, "strata", s) end
function Widget:GetFrameStrata()
	local f = self
	while f do
		local s = rawget(f, "strata")
		if s then return s end
		f = rawget(f, "parent")
	end
	return "MEDIUM"
end
-- Gradients (the kit's sheen and etch): kept, drawn as CSS gradients.
if not CreateColor then
	function CreateColor(r, g, b, a)
		return { r = r, g = g, b = b, a = a or 1, GetRGBA = function(c) return c.r, c.g, c.b, c.a end }
	end
end
function Widget:SetGradient(orientation, c1, c2)
	local function rgba(c) if type(c) == "table" and c.GetRGBA then return { c:GetRGBA() } end return { 1, 1, 1, 1 } end
	rawset(self, "gradient", { orientation, rgba(c1), rgba(c2) })
end
function Widget:SetGradientAlpha(orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	rawset(self, "gradient", { orientation, { r1, g1, b1, a1 }, { r2, g2, b2, a2 } })
end
local baseTex, baseColor = Widget.SetTexture, Widget.SetColorTexture
function Widget:SetTexture(t) baseTex(self, t) rawset(self, "fill", "file") end
function Widget:SetColorTexture(r, g, b, a)
	-- The stub gives every widget every method; the game's font strings have
	-- no SetColorTexture, so code that picks by method colours text with it
	-- here. Taken as the text's colour, as the game would take SetTextColor.
	if self.kind == "FontString" then self.textColor = { r, g, b, a } return end
	baseColor(self, r, g, b, a) rawset(self, "fill", "color") rawset(self, "gradient", nil)
end
function Widget:IsVisible()
	local f = self
	while f do
		if f.shown == false then return false end
		f = rawget(f, "parent")
	end
	return true
end

---------------------------------------------------------------------------
-- Text: measured with the real font
---------------------------------------------------------------------------

local function plain(text)
	text = tostring(text or "")
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
	return text
end
render.Plain = plain

-- The width the text wraps in: its own, or the one its anchors give.
local hrange -- forward
local function wrapWidth(fs)
	local l, r = hrange(fs, true)
	if l and r and r > l then return r - l end
	local w = rawget(fs, "w") or 0
	return w > 0 and w or nil
end

local function measure(fs, width)
	local file, size = rawget(fs, "font"), rawget(fs, "fontSize") or 12
	local wrap = rawget(fs, "wrap")
	if wrap == nil then wrap = true end
	local w, h, lines = pymeasure(plain(fs.text), file or "", size, width or 0, wrap and width and true or false, rawget(fs, "maxLines") or 0)
	return w, h, lines
end

function Widget:GetStringWidth()
	if self.kind ~= "FontString" then return 0 end
	return (measure(self, nil))
end
function Widget:GetStringHeight()
	if self.kind ~= "FontString" then return 0 end
	if (self.text or "") == "" then return 0 end
	local _, h = measure(self, wrapWidth(self))
	return h
end

---------------------------------------------------------------------------
-- Anchors
---------------------------------------------------------------------------

local H = { TOPLEFT = "L", LEFT = "L", BOTTOMLEFT = "L", TOPRIGHT = "R", RIGHT = "R", BOTTOMRIGHT = "R", TOP = "C", BOTTOM = "C", CENTER = "C" }
local V = { TOPLEFT = "T", TOP = "T", TOPRIGHT = "T", BOTTOMLEFT = "B", BOTTOM = "B", BOTTOMRIGHT = "B", LEFT = "C", RIGHT = "C", CENTER = "C" }

-- A point as { point, relativeTo, relativePoint, x, y }.
local function norm(region, p)
	local point, a2, a3, a4, a5 = p[1], p[2], p[3], p[4], p[5]
	local parent = rawget(region, "parent") or UIParent
	if a2 == nil then return point, parent, point, 0, 0 end
	if type(a2) == "number" then return point, parent, point, a2, a3 or 0 end
	if type(a2) == "string" then a2 = _G[a2] or parent end
	if type(a3) == "string" then return point, a2, a3, a4 or 0, a5 or 0 end
	if type(a3) == "number" then return point, a2, point, a3, a4 or 0 end
	return point, a2, point, 0, 0
end

local busy = {}
local vrange
local function edge(rel, which, horizontal)
	if rel == UIParent then
		if horizontal then return which == "L" and 0 or (which == "R" and SCREEN_W or SCREEN_W / 2) end
		return which == "B" and 0 or (which == "T" and SCREEN_H or SCREEN_H / 2)
	end
	local a, b
	if horizontal then a, b = hrange(rel) else a, b = vrange(rel) end
	if not a then return nil end
	if which == "L" or which == "B" then return a end
	if which == "R" or which == "T" then return b end
	return (a + b) / 2
end

-- Left and right of a region (nil when it has no horizontal place).
-- `widthOnly`: for a font string, without its text's width (wrapping).
function hrange(region, widthOnly)
	if region == UIParent then return 0, SCREEN_W end
	local key = region
	if busy[key] then return nil end
	busy[key] = true
	local L, R, C
	for _, p in ipairs(pointsOf(region)) do
		local point, rel, rp, x = norm(region, p)
		local v = rel and edge(rel, H[rp] or "C", true)
		if v then
			v = v + (x or 0)
			local k = H[point] or "C"
			if k == "L" then L = v elseif k == "R" then R = v else C = v end
		end
	end
	local w = rawget(region, "w") or 0
	if region.kind == "FontString" and w <= 0 and not (L and R) and not widthOnly then w = (measure(region, nil)) end
	busy[key] = nil
	if L and R then return L, R end
	if L then return L, L + w end
	if R then return R - w, R end
	if C then return C - w / 2, C + w / 2 end
	return nil
end

-- Bottom and top (y grows upward, as in game).
function vrange(region)
	if region == UIParent then return 0, SCREEN_H end
	local key = region
	if busy[key] then return nil end
	busy[key] = true
	local T, B, C
	for _, p in ipairs(pointsOf(region)) do
		local point, rel, rp, _, y = norm(region, p)
		local v = rel and edge(rel, V[rp] or "C", false)
		if v then
			v = v + (y or 0)
			local k = V[point] or "C"
			if k == "T" then T = v elseif k == "B" then B = v else C = v end
		end
	end
	local h = rawget(region, "h") or 0
	if region.kind == "FontString" and h <= 0 and not (T and B) then
		busy[key] = nil
		local _, fh = measure(region, wrapWidth(region))
		busy[key] = true
		h = fh
	end
	busy[key] = nil
	if T and B then return B, T end
	if T then return T - h, T end
	if B then return B, B + h end
	if C then return C - h / 2, C + h / 2 end
	return nil
end
render.H, render.V = hrange, vrange

function Widget:GetWidth()
	local l, r = hrange(self)
	if l and r then return r - l end
	return rawget(self, "w") or 0
end
function Widget:GetHeight()
	local b, t = vrange(self)
	if b and t then return t - b end
	return rawget(self, "h") or 0
end
function Widget:GetLeft() return (hrange(self)) end
function Widget:GetRight() local _, r = hrange(self) return r end
function Widget:GetBottom() return (vrange(self)) end
function Widget:GetTop() local _, t = vrange(self) return t end
function Widget:GetCenter()
	local l, r = hrange(self)
	local b, t = vrange(self)
	if not (l and b) then return nil end
	return (l + r) / 2, (b + t) / 2
end
function Widget:GetRect()
	local l, r = hrange(self)
	local b, t = vrange(self)
	if not (l and b) then return nil end
	return l, b, r - l, t - b
end

---------------------------------------------------------------------------
-- Dumping what is on screen
---------------------------------------------------------------------------

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local LAYER = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

local function alphaOf(region)
	local a, f = 1, region
	while f do
		a = a * (rawget(f, "alpha") or 1)
		f = rawget(f, "parent")
	end
	return a
end

-- The frames left out of a picture (the stub's own stand-ins).
local SKIP = {}
function render.Skip(frame) SKIP[frame] = true end

local function skipped(region)
	local f = region
	while f do
		if SKIP[f] then return true end
		f = rawget(f, "parent")
	end
	return false
end

function render.Dump()
	local out = {}
	for _, r in ipairs(stub.frames) do
		local kind = r.kind
		if (kind == "Texture" or kind == "FontString") and r:IsVisible() and not skipped(r) then
			local l, rr = hrange(r)
			local b, t = vrange(r)
			local owner = rawget(r, "parent") or UIParent
			if l and b and rr - l > 0 and t - b > 0 then
				local item = {
					kind = kind, x = l, y = SCREEN_H - t, w = rr - l, h = t - b,
					alpha = alphaOf(r),
					strata = STRATA[owner:GetFrameStrata()] or 3,
					level = owner:GetFrameLevel() or 0,
					layer = LAYER[rawget(r, "layer") or "ARTWORK"] or 3,
					sub = rawget(r, "sublevel") or 0,
					order = rawget(r, "order") or 0,
				}
				if kind == "Texture" then
					item.fill = rawget(r, "fill")
					item.texture = rawget(r, "texture")
					item.color = rawget(r, "color")
					item.vertex = rawget(r, "vertex")
					item.texCoord = rawget(r, "texCoord")
					item.rotation = rawget(r, "rotation")
					item.blend = rawget(r, "blend")
					item.gradient = rawget(r, "gradient")
				else
					local text = r.text
					if text and text ~= "" then
						item.text = tostring(text)
						item.font = rawget(r, "font")
						item.size = rawget(r, "fontSize") or 12
						item.color = rawget(r, "textColor")
						item.justifyH = rawget(r, "justifyH") or "CENTER"
						item.justifyV = rawget(r, "justifyV") or "MIDDLE"
						local wrap = rawget(r, "wrap")
						item.wrap = wrap == nil and true or wrap
						item.maxLines = rawget(r, "maxLines") or 0
						-- No width of its own (one horizontal anchor, no size): one line.
						local hs = {}
						for _, p in ipairs(r.points or {}) do hs[H[p[1]] or "C"] = true end
						item.autoWidth = not (hs.L and hs.R) and (rawget(r, "w") or 0) <= 0
						item.shadow = rawget(r, "shadow")
						item.shadowColor = rawget(r, "shadowColor")
					else
						item = nil
					end
				end
				-- Inside a scroll frame: clipped to it, as the game does.
				if item then
					local f = r
					while f do
						local sp = rawget(f, "scrollParent")
						if sp then
							local cl, cr = hrange(sp)
							local cb, ct = vrange(sp)
							if cl then
								item.clip = { cl, SCREEN_H - ct, cr, SCREEN_H - cb }
							end
							break
						end
						f = rawget(f, "parent")
					end
				end
				if item then out[#out + 1] = item end
			end
		end
	end
	return out
end

return render
