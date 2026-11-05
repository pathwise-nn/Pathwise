-- COPIED from PathwiseUI/Movers.lua by tools/kit.js: do not edit here.
-- Edit PathwiseUI/Movers.lua, then run npm run kit.
-- Moving things: one way for unit frames, action bars, the tray and the
-- experience bar. While anything is unlocked a faint grid covers the screen
-- (the center lines a little stronger) with a small bar at the top: what to do,
-- and Done. Each piece gets a handle (dimmed, corner brackets) that fades in; drag it,
-- and on release it snaps to the grid (hold Shift for free placement).
--
--   Mv.Handle(frame, label, onDrop(point, relPoint, x, y)) -> handle
--   Mv.Group(name, unlock(on))   a module's own lock switch, for "Move everything"
--   Mv.Active(name, on)          a module unlocked (or locked): the grid follows
--   Mv.All(on)                   unlock or lock every group

-- Shared file (see Core.lua): edit it here, then run npm run kit.
local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local Mv = {}
ns.Movers = Mv

Mv.GRID = 8 -- snap step
Mv.LINES = 32 -- grid line spacing

local function inCombat() return InCombatLockdown and InCombatLockdown() end

function Mv.Snap(v, free)
	if free then return math.floor(v + 0.5) end
	return math.floor(v / Mv.GRID + 0.5) * Mv.GRID
end

-- "MAIN BAR" -> "Main bar" (handles read as names, not shouted).
local function name(label)
	label = tostring(label or ""):lower()
	return (label:gsub("^%l", string.upper))
end

-- A handle: the frame dimmed under a dark see-through ground, a faint
-- outline, corner brackets, its name in the middle. Hover brightens it.
function Mv.Handle(frame, label, onDrop)
	local h = CreateFrame("Frame", nil, frame)
	h:SetAllPoints()
	h:SetFrameLevel((frame:GetFrameLevel() or 1) + 30)
	h:EnableMouse(true)
	local tint = h:CreateTexture(nil, "OVERLAY")
	tint:SetAllPoints()
	T.Paint(tint, "bg", 0.7)
	local edge = T.Border(h, "OVERLAY", 6)
	T.Paint(edge, "text", 0.25)
	local brackets = {}
	for _, c in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
		local across = h:CreateTexture(nil, "OVERLAY", nil, 7)
		across:SetSize(8, 2)
		across:SetPoint(c[1], h, c[1], 0, 0)
		local down = h:CreateTexture(nil, "OVERLAY", nil, 7)
		down:SetSize(2, 8)
		down:SetPoint(c[1], h, c[1], 0, 0)
		brackets[#brackets + 1] = across
		brackets[#brackets + 1] = down
	end
	local function look(p)
		local g = T.Color("bg")
		tint:SetColorTexture(g[1], g[2], g[3], 0.7 + 0.15 * p)
		for _, t in ipairs(brackets) do T.Blend(t, "text2", "text", p) end
		T.Blend(edge, "border", "text2", p, 0.6)
	end
	look(0)
	ns.On("ACCENT_CHANGED", function() look(ns.Anim.Get(h, "hover") or 0) end)
	local text = T.Text(h, "meta", "text", "OVERLAY")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetText(name(label))
	h.pwLabel, h.pwTint = text, tint
	h:SetScript("OnEnter", function(self) A.Hover(self, true, look) end)
	h:SetScript("OnLeave", function(self) if not self.pwMoving then A.Hover(self, false, look) end end)
	h:SetScript("OnMouseDown", function()
		if inCombat() then return end
		frame:StartMoving()
		h.pwMoving = true
	end)
	h:SetScript("OnMouseUp", function()
		if not h.pwMoving then return end
		h.pwMoving = false
		frame:StopMovingOrSizing()
		local p, _, rp, x, y = frame:GetPoint()
		if not p then return end
		local free = IsShiftKeyDown and IsShiftKeyDown()
		x, y = Mv.Snap(x or 0, free), Mv.Snap(y or 0, free)
		frame:ClearAllPoints()
		frame:SetPoint(p, UIParent, rp, x, y)
		if onDrop then onDrop(p, rp, x, y) end
	end)
	-- Shown and hidden with a short fade.
	function h:Reveal(on)
		if on then
			if not self:IsShown() then self:SetAlpha(0) A.Set(self, "alpha", 0) end
			self:Show()
			A.Fade(self, 1, A.NORMAL)
		elseif self:IsShown() then
			A.Fade(self, 0, A.FAST, function() if A.Get(self, "alpha") == 0 then self:Hide() end end)
		end
	end
	h:Hide()
	return h
end

---------------------------------------------------------------------------
-- The grid and the bar at the top
---------------------------------------------------------------------------

local groups, active = {}, {}
local overlay

local function buildOverlay()
	if overlay then return overlay end
	overlay = CreateFrame("Frame", ns.ID.global .. "_MoveGrid", nil)
	overlay:SetParent(UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("BACKGROUND")
	local shade = overlay:CreateTexture(nil, "BACKGROUND")
	shade:SetAllPoints()
	shade:SetColorTexture(0, 0, 0, 0.25)
	overlay.lines = {}

	local bar = CreateFrame("Frame", nil, overlay)
	bar:SetFrameStrata("DIALOG")
	bar:SetSize(420, 40)
	bar:SetPoint("TOP", UIParent, "TOP", 0, -60)
	T.Panel(bar, "bg", "border", 0.96)
	local title = T.Text(bar, "heading", "flair")
	title:SetPoint("LEFT", 14, 0)
	title:SetJustifyV("MIDDLE")
	title:SetText("Move mode")
	local hint = T.Text(bar, "meta", "text2")
	hint:SetPoint("LEFT", title, "RIGHT", 10, 0)
	hint:SetJustifyV("MIDDLE")
	hint:SetText("Drag to move. Shift: no snapping.")
	local done = T.Button(bar, "Done", "accent", function() Mv.All(false) end)
	done:SetPoint("RIGHT", -8, 0)
	overlay.bar = bar
	overlay:Hide()
	return overlay
end

local function drawGrid()
	local w, h = UIParent:GetWidth() or 0, UIParent:GetHeight() or 0
	local n = 0
	local px = T.Pixel()
	local function line(vertical, at, accent)
		n = n + 1
		local t = overlay.lines[n]
		if not t then
			t = overlay:CreateTexture(nil, "BORDER")
			T.NoSnap(t)
			overlay.lines[n] = t
		end
		t:ClearAllPoints()
		if vertical then
			t:SetPoint("TOP", overlay, "TOP", at, 0)
			t:SetPoint("BOTTOM", overlay, "BOTTOM", at, 0)
			t:SetWidth(px)
		else
			t:SetPoint("LEFT", overlay, "LEFT", 0, at)
			t:SetPoint("RIGHT", overlay, "RIGHT", 0, at)
			t:SetHeight(px)
		end
		T.Paint(t, "text", accent and 0.22 or 0.06)
		t:Show()
	end
	for x = Mv.LINES, w / 2, Mv.LINES do line(true, x) line(true, -x) end
	for y = Mv.LINES, h / 2, Mv.LINES do line(false, y) line(false, -y) end
	line(true, 0, true)
	line(false, 0, true)
	for i = n + 1, #overlay.lines do overlay.lines[i]:Hide() end
end

local function refresh()
	local any = next(active) ~= nil
	if any then
		buildOverlay()
		drawGrid()
		if not overlay:IsShown() then overlay:SetAlpha(0) A.Set(overlay, "alpha", 0) overlay:Show() end
		A.Fade(overlay, 1, A.NORMAL)
	elseif overlay and overlay:IsShown() then
		A.Fade(overlay, 0, A.FAST, function() if not next(active) then overlay:Hide() end end)
	end
	ns.Fire("MOVE_MODE", any)
end

function Mv.Group(name, unlock) groups[name] = unlock end
function Mv.Active(name, on)
	active[name] = on and true or nil
	refresh()
end
function Mv.IsActive(name) if name then return active[name] == true end return next(active) ~= nil end
function Mv.Overlay() return overlay end

function Mv.All(on)
	if on and inCombat() then ns.Print("things can be moved out of combat.") return false end
	for _, unlock in pairs(groups) do pcall(unlock, on) end
	return true
end

ns.On("MOVE_ALL", function() Mv.All(not Mv.IsActive()) end)
ns.On("PIXEL_CHANGED", function() if overlay and overlay:IsShown() then drawGrid() end end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	for k in pairs(active) do active[k] = nil end
	refresh()
end)
