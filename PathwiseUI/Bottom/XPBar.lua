-- The experience bar, the Pathwise way: a thin bar in your accent under the
-- main action bar, rested experience as a lighter part ahead of it, and the
-- numbers on hover. At the level cap (or with experience turned off) it shows
-- the reputation you watch, in its reaction color.
--
-- Experience and reputation are ordinary values on Forever (UnitXP,
-- UnitXPMax, GetXPExhaustion, C_Reputation.GetWatchedFactionData): no
-- secrets, so the bar shows exact numbers. The game's own experience and
-- reputation bars (StatusTrackingBarManager) are put out of sight while on.

local ADDON, ns = ...
local T = ns.Theme
local X = {}
ns.XPBar = X

ns.Defaults("xp", {
	enabled = true,
	hideBlizzard = true,
	matchBar = true, -- as wide as the main action bar
	width = 476, -- else this wide
	height = 8,
	text = false, -- the numbers always on, not only on hover
	point = nil,
})
X.DEFAULT_POINT = { "BOTTOM", "BOTTOM", 0, 58 }

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c, d = pcall(fn, ...) if ok then return a, b, c, d end end
local readable = ns.Readable

local frame

-- What the bar shows now. -> { kind = "xp" | "rep", cur, max, rested, level, name, reaction }
function X.Data()
	local level = readable(call(UnitLevel, "player")) or 1
	local maxLevel = readable(call(GetMaxPlayerLevel)) or 60
	local xpOff = readable(call(IsXPUserDisabled))
	if level < maxLevel and not xpOff then
		local cur, max = readable(call(UnitXP, "player")) or 0, readable(call(UnitXPMax, "player")) or 1
		return { kind = "xp", cur = cur, max = math.max(1, max), rested = readable(call(GetXPExhaustion)) or 0, level = level }
	end
	local get = C_Reputation and C_Reputation.GetWatchedFactionData
	local f = get and call(get)
	if type(f) == "table" and f.name then
		local lo, hi, at = f.currentReactionThreshold or 0, f.nextReactionThreshold or 1, f.currentStanding or 0
		return { kind = "rep", cur = at - lo, max = math.max(1, hi - lo), name = f.name, reaction = f.reaction }
	end
	return nil
end

-- "Level 21  ·  4,512 / 9,800 (46%)  ·  rested 2,100" or "Stormwind: 1,200 / 3,000 (40%)"
local function grouped(n)
	local s = tostring(math.floor(n))
	while true do
		local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = r
		if k == 0 then return s end
	end
end
function X.Text(d)
	if not d then return "" end
	local pct = math.floor(d.cur / d.max * 100 + 0.5)
	if d.kind == "xp" then
		local t = ("Level %d  ·  %s / %s (%d%%)"):format(d.level, grouped(d.cur), grouped(d.max), pct)
		if d.rested > 0 then t = t .. ("  ·  rested %s"):format(grouped(d.rested)) end
		return t
	end
	return ("%s: %s / %s (%d%%)"):format(d.name, grouped(d.cur), grouped(d.max), pct)
end

local REACTION = { [1] = "#E66B78", [2] = "#E66B78", [3] = "#E0956A", [4] = "#E4B96D", [5] = "#59D9B2", [6] = "#59D9B2", [7] = "#4FD1C5", [8] = "#66D7FF" }

function X.Update()
	if not frame then return end
	local d = X.Data()
	if not d or not ns.Get("xp.enabled") then frame:Hide() return end
	frame:Show()
	frame.bar:SetMinMaxValues(0, d.max)
	-- Glides to the new amount (a quest turned in fills it smoothly).
	local function to(bar, v)
		local E = Enum and Enum.StatusBarInterpolation
		if E and E.ExponentialEaseOut and ns.Anim.Enabled() and pcall(bar.SetValue, bar, v, E.ExponentialEaseOut) then return end
		bar:SetValue(v)
	end
	to(frame.bar, d.cur)
	local c = d.kind == "xp" and T.Color("accent") or T.Hex(REACTION[d.reaction or 4] or "#E4B96D")
	frame.bar:SetStatusBarColor(c[1], c[2], c[3])
	if d.kind == "xp" and d.rested > 0 then
		frame.rested:SetMinMaxValues(0, d.max)
		to(frame.rested, math.min(d.max, d.cur + d.rested))
		frame.rested:SetStatusBarColor(c[1], c[2], c[3], 0.3)
		frame.rested:Show()
	else
		frame.rested:Hide()
	end
	frame.text:SetText(X.Text(d))
	-- The numbers fade in under the mouse (or stay, if you want them always).
	frame.text:Show()
	ns.Anim.Fade(frame.text, (ns.Get("xp.text") or frame.hover) and 1 or 0, ns.Anim.FAST)
end

local function build()
	if frame then return frame end
	frame = CreateFrame("Frame", "PathwiseUI_XPBar", nil)
	frame:SetParent(UIParent)
	frame:SetFrameStrata("LOW")
	frame:EnableMouse(true)
	frame:SetMovable(true)
	T.Panel(frame, "bg", "border", 0.9)
	frame.rested = CreateFrame("StatusBar", nil, frame)
	frame.rested:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	frame.rested:SetPoint("TOPLEFT", 1, -1)
	frame.rested:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.bar = CreateFrame("StatusBar", nil, frame)
	frame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	frame.bar:SetPoint("TOPLEFT", 1, -1)
	frame.bar:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.bar:SetFrameLevel((frame.rested:GetFrameLevel() or 1) + 1)
	T.Sheen(frame.bar)
	frame.text = T.Text(frame.bar, "small", "text", "OVERLAY")
	frame.text:SetPoint("BOTTOM", frame, "TOP", 0, 3)
	frame.text:SetJustifyH("CENTER")
	T.BarText(frame.text, "small")
	ns.Anim.Set(frame.text, "alpha", 0)
	frame.text:SetAlpha(0)
	frame:SetScript("OnEnter", function(self) self.hover = true X.Update() end)
	frame:SetScript("OnLeave", function(self) self.hover = false X.Update() end)
	return frame
end

function X.Layout()
	build()
	local w = ns.Get("xp.width") or 476
	local main = ns.Bars and ns.Bars.bars and ns.Bars.bars[1]
	if ns.Get("xp.matchBar") and main and main.GetWidth and (main:GetWidth() or 0) > 0 then w = main:GetWidth() end
	frame:SetSize(w, ns.Get("xp.height") or 8)
	local p = ns.Get("xp.point")
	if inCombat() then X.pending = true X.Update() return end
	frame:ClearAllPoints()
	if not p and ns.Get("xp.matchBar") and main and main:IsShown() then
		-- Right under the main bar, wherever it is moved.
		frame:SetPoint("TOP", main, "BOTTOM", 0, -4)
	else
		p = p or X.DEFAULT_POINT
		frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	end
	X.Update()
end
function X.Frame() return frame end

-- The game's own experience and reputation bars, out of sight.
local hider, hidden = nil, {}
function X.HideBlizzard()
	if inCombat() then X.pending = true return end
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	for _, name in ipairs({ "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		local f = _G[name]
		if type(f) == "table" and not hidden[f] and f.SetParent then
			pcall(f.SetParent, f, hider)
			hidden[f] = true
		end
	end
end
function X.Hidden() return hidden end

ns.On("READY", function()
	X.Layout()
	if ns.Get("xp.enabled") and ns.Get("xp.hideBlizzard") then X.HideBlizzard() end
end)
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "UPDATE_FACTION", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN", "PLAYER_UPDATE_RESTING" }) do
	ns.RegisterEvent(ev, function() X.Update() end)
end
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if X.pending then X.pending = false X.Layout() if ns.Get("xp.hideBlizzard") then X.HideBlizzard() end end
end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^xp%.") or path:find("^bars%.") or path == "*") then
		X.Layout()
		if ns.Get("xp.enabled") and ns.Get("xp.hideBlizzard") then X.HideBlizzard() end
	end
end)
ns.On("ACCENT_CHANGED", function() X.Update() end)
