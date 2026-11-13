-- The "Minimal" guide style (v2): no window, text over the game (frame
-- PathwiseHud). From the top:
--   "WESTFALL · 12 / 19"            "Lv 14 · 18m to 15"
--   a 2 px progress line
--   the step's title
--   its objectives: done ones muted with a tick, the rest with a dot
--   "+ Tailoring: Craft 12 Bolt of Linen Cloth" (the detour)
--   your coordinates, when that is on
--   small round buttons: Back, Skip, Next, and the hub
-- Every text has a shadow so it reads over snow and sky. Drag the title
-- line to move it. Drawn from the guide's view (GUIDE_VIEW).

local ADDON, ns = ...
local T, Guide = ns.Theme, ns.Guide
local floor, max = math.floor, math.max

local Hud = {}
ns.Hud = Hud

ns.Defaults("hud", { point = nil, width = 320, locked = false })

local W = {}
Hud.frames = W
Hud.MAX_ROWS = 6
Hud.MIN_W, Hud.MAX_W = 220, 520

local function shadowed(fs) T.Shadow(fs) fs:SetShadowColor(0, 0, 0, 0.95) return fs end
-- Text over the game world: light on a light theme too (Theme.World).
local function wt(parent, role, color) return shadowed(T.Text(parent, role, T.World(color))) end
local function height(fs) return fs:IsShown() and max(0, fs:GetStringHeight() or 0) or 0 end

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("hud.point", { p, floor(x + 0.5), floor(y + 0.5), rel ~= p and rel or nil })
end

-- A small round button over the game: faint dark ground, light outline.
local function pill(parent, label, primary, onClick, glyph, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(26)
	local a = T.Color(primary and "accent" or "bg")
	T.Round(b, { a[1], a[2], a[3], primary and 1 or 0.6 }, primary and "accent" or { 0.94, 0.96, 0.98, 0.35 }, 13)
	if glyph then
		b.icon = T.Glyph(b, glyph, 14, "text")
		b.icon:SetPoint("CENTER")
		b:SetWidth(26)
	else
		b.pwText = T.Text(b, "button", primary and "bg" or "text")
		b.pwText:SetPoint("CENTER")
		b.pwText:SetText(label)
		b.pwLabel = label
		b:SetWidth((b.pwText:GetStringWidth() or 30) + 24)
	end
	b:SetScript("OnClick", onClick)
	if tip then
		b:SetScript("OnEnter", function(self)
			if not GameTooltip then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
			ns.Tip.SetText(GameTooltip, tip, 1, 1, 1)
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	end
	return b
end

local function build()
	local f = CreateFrame("Frame", "PathwiseHud", UIParent)
	W.frame = f
	f:SetWidth(ns.Get("hud.width") or 320)
	f:SetHeight(120)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	T.TrackScale(f)
	local saved = ns.Get("hud.point")
	if type(saved) == "table" then
		f:SetPoint(saved[1], UIParent, saved[4] or saved[1], saved[2], saved[3])
	else
		f:SetPoint("RIGHT", UIParent, "RIGHT", -40, 60)
	end
	-- Only the top line takes the mouse (to move it): the rest lets clicks
	-- through to the world.
	local grip = CreateFrame("Frame", nil, f)
	W.grip = grip
	grip:SetPoint("TOPLEFT")
	grip:SetPoint("TOPRIGHT")
	grip:SetHeight(18)
	-- Pinned, it takes no mouse at all: clicks go to the world.
	grip:EnableMouse(T.Movable("hud.locked"))
	grip:RegisterForDrag("LeftButton")
	grip:SetScript("OnDragStart", function() if T.Movable("hud.locked") then f:StartMoving() end end)
	grip:SetScript("OnDragStop", function() f:StopMovingOrSizing() savePoint(f) end)

	W.route = wt(f, "label", "accentHover")
	W.route:SetPoint("TOPLEFT", 0, -2)
	W.route:SetWordWrap(false)
	W.level = wt(f, "small", "silver")
	W.level:SetPoint("TOPRIGHT", 0, -2)
	W.level:SetJustifyH("RIGHT")
	W.level:SetWordWrap(false)
	W.route:SetPoint("RIGHT", W.level, "LEFT", -8, 0)

	W.track = f:CreateTexture(nil, "ARTWORK")
	W.track:SetHeight(2)
	W.track:SetPoint("TOPLEFT", 0, -20)
	W.track:SetPoint("TOPRIGHT", 0, -20)
	T.SetColor(W.track, "text", 0.25)
	W.fill = f:CreateTexture(nil, "ARTWORK", nil, 1)
	W.fill:SetHeight(2)
	W.fill:SetPoint("TOPLEFT", W.track, "TOPLEFT")
	T.SetColor(W.fill, T.World("accent"))

	W.title = shadowed(T.TextAt(f, "semibold", 17, T.World("text")))
	W.rows = {}
	W.detour = shadowed(T.Text(f, "meta", "loot"))
	W.coords = wt(f, "small", "silver")
	W.empty = wt(f, "meta", "text")

	W.back = pill(f, "Back", false, function() ns.Fire("GUIDE_BACK") end)
	W.skip = pill(f, "Skip", false, function() ns.Fire("GUIDE_SKIP") end)
	W.next = pill(f, "Next", true, function() ns.Fire("GUIDE_NEXT") end)
	W.hub = pill(f, nil, false, function() ns.Fire("TOGGLE_HUB", true) end, "glyph-grid", "Open the hub")
	W.pin = pill(f, nil, false, function() ns.Set("hud.locked", not ns.Get("hud.locked")) end, "glyph-pin", "Pin in place (or unpin)")
	-- The corner grip: how wide the lines run (hidden while pinned).
	W.sizer = T.Grip(f, {
		minW = Hud.MIN_W, maxW = Hud.MAX_W, lockPath = "hud.locked",
		onSize = function() Hud.Refresh() end,
		onDone = function(w) ns.Set("hud.width", w) savePoint(f) end,
		onReset = function() ns.Set("hud.width", nil) end,
	})
end

local function row(i)
	local r = W.rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, W.frame)
	r.dot = r:CreateTexture(nil, "ARTWORK")
	r.dot:SetPoint("TOPLEFT", 0, -4)
	r.text = wt(r, "body", "text")
	r.text:SetPoint("TOPLEFT", 16, 0)
	r.text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	W.rows[i] = r
	return r
end

local function place(widget, y)
	widget:ClearAllPoints()
	widget:SetPoint("TOPLEFT", W.frame, "TOPLEFT", 0, -y)
	widget:SetPoint("RIGHT", W.frame, "RIGHT", 0, 0)
end

function Hud.Refresh()
	local f = W.frame
	if not f then return end
	local v = Guide.View()
	local width = f:GetWidth()
	W.route:SetText(v and v.count and ns.U(("%s  ·  %d / %d"):format(ns.L(v.route or ""), v.index or 0, v.count)) or ns.U(ns.L(v and v.route or "PATHWISE")))
	local lvl, _, rate = ns.TrackerCard.Stats()
	local lvlBits = {}
	if lvl then lvlBits[#lvlBits + 1] = lvl end
	if rate and rate ~= "" then lvlBits[#lvlBits + 1] = rate:match("[^·]+$"):gsub("^%s+", "") end
	W.level:SetText(table.concat(lvlBits, "  ·  "))
	local p = v and v.progress or 0
	W.fill:SetShown(p > 0)
	if p > 0 then W.fill:SetWidth(width * math.min(1, p)) end
	local y = 30

	local has = v ~= nil
	W.title:SetShown(has)
	W.empty:SetShown(not has)
	if not has then
		place(W.empty, y)
		W.empty:SetText("No route yet: open the hub to pick one.")
		y = y + height(W.empty) + 10
	else
		place(W.title, y)
		W.title:SetText(v.title or "")
		y = y + height(W.title) + 8
	end

	local rows = has and ns.TrackerCard.Rows(v) or {}
	local n = math.min(#rows, Hud.MAX_ROWS)
	for i = 1, n do
		local line, r = rows[i], row(i)
		r:Show()
		place(r, y)
		local done = line.done
		r.dot:SetTexture(T.MEDIA .. (done and "check" or "dot-done"))
		local s = done and 14 or 6
		r.dot:SetSize(s, s)
		r.dot:ClearAllPoints()
		r.dot:SetPoint("TOPLEFT", done and -2 or 3, done and 0 or -5)
		local c = T.World(done and "success" or "accent")
		r.dot:SetVertexColor(c[1], c[2], c[3], 1)
		local text = Guide.LineText(line)
		if line.need then text = text .. ("  %d/%d"):format(line.have or 0, line.need) end
		r.text:SetText(text)
		T.TextColor(r.text, T.World(done and "muted" or "text"))
		local h = max(16, height(r.text))
		r:SetHeight(h)
		y = y + h + 5
	end
	for i = n + 1, #W.rows do W.rows[i]:Hide() end

	local d = has and v.detour
	W.detour:SetShown(d and true or false)
	if d then
		place(W.detour, y + 4)
		local kind = (d.label or ""):gsub("^Optional%s*·%s*", "")
		W.detour:SetText("+ " .. (kind ~= "" and (kind .. ": ") or "") .. (d.text or ""))
		y = y + 4 + height(W.detour) + 4
	end
	local xy = ns.Coords and ns.Coords.Text()
	W.coords:SetShown(xy and true or false)
	if xy then
		place(W.coords, y + 2)
		W.coords:SetText(ns.L("You  ") .. xy)
		y = y + 2 + height(W.coords) + 4
	end

	y = y + 8
	for _, b in ipairs({ W.back, W.skip, W.next }) do b:SetShown(has) end
	W.back:ClearAllPoints()
	W.back:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y)
	W.skip:ClearAllPoints()
	W.skip:SetPoint("LEFT", W.back, "RIGHT", 6, 0)
	W.next:ClearAllPoints()
	W.next:SetPoint("LEFT", W.skip, "RIGHT", 6, 0)
	W.hub:ClearAllPoints()
	if has then W.hub:SetPoint("LEFT", W.next, "RIGHT", 6, 0)
	else W.hub:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -y) end
	W.pin:ClearAllPoints()
	W.pin:SetPoint("LEFT", W.hub, "RIGHT", 6, 0)
	local pc = T.World(ns.Get("hud.locked") and "accent" or "text")
	W.pin.icon:SetVertexColor(pc[1], pc[2], pc[3], 1)
	W.grip:EnableMouse(T.Movable("hud.locked"))
	W.sizer:SetShown(T.Movable("hud.locked"))
	f:SetHeight(y + 26)
end

function Hud.Show()
	local on = Guide.StyleShown("minimal")
	if on and not W.frame then build() end
	if not W.frame then return end
	W.frame:SetShown(on)
	if on then Hud.Refresh() end
end

function Hud.Shown() return W.frame ~= nil and W.frame:IsShown() end
local function refreshIfShown() if Hud.Shown() then Hud.Refresh() end end

ns.On("READY", Hud.Show)
ns.On("HUB_TOGGLED", Hud.Show)
ns.On("GUIDE_VIEW", refreshIfShown)
ns.On("TRACKER_UPDATED", refreshIfShown)
ns.On("PLAYER_COORDS", function()
	if not Hud.Shown() then return end
	local xy = ns.Coords.Text()
	if (xy ~= nil) ~= (W.coords:IsShown() and true or false) then Hud.Refresh()
	elseif xy then W.coords:SetText(ns.L("You  ") .. xy) end
end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" or path == "guide.style" then Hud.Show()
	elseif path == "compass.coords" or path == "tracker.shown" or path == "hud.locked" then refreshIfShown()
	elseif path == "hud.width" and W.frame and not W.sizer.pwState.held then
		W.frame:SetWidth(math.min(Hud.MAX_W, math.max(Hud.MIN_W, ns.Get("hud.width") or 320)))
		refreshIfShown()
	end
end)
