-- Pathwise Heal: your party or raid as a grid of bars built for
-- healing, off until you turn them on (a healer is asked once). Click a frame
-- to cast on that person (Healing/Clicks.lua); see their health, heals on the
-- way, debuffs you can cleanse, your HoTs, who has aggro and who is out of
-- range.
--
-- Forever's rules, learned from HealForever's notes (nothing of its code or
-- art is used; nor of VuhDo's):
--   * health, incoming heals, range, class, and "is this my target" can be
--     secret values: never compared or used in sums here, only handed to bars,
--     text and alphas, which take them; a yes/no is turned into an alpha by
--     the game (C_CurveUtil.EvaluateColorValueFromBoolean);
--   * auras can't be read by addons in a fight, so in a fight the game itself
--     draws the buff and debuff rows into each frame (a private aura anchor);
--     between fights our own rows (Auras.lua) read auras, when allowed;
--   * the frames are a SecureGroupHeaderTemplate of secure unit buttons
--     (Heal.xml), sized and bound out of combat only.

local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local H = {}
ns.Heal = H

ns.Defaults("heal", {
	enabled = false, -- off until you want it (a healer class is asked once)
	solo = true, -- your own frame when you're not in a group
	width = 84, height = 40, spacing = 3,
	grow = "down", -- "down": a column per group; "right": a row per group
	color = "class", -- "class" | "green" | "health" (green to red as it drops)
	text = "deficit", -- "none" | "percent" | "deficit"
	incoming = true, -- heals on the way
	-- The buff row (top right) and debuff row (bottom), Auras.lua: ours
	-- between fights, the game's in a fight.
	hots = true, -- your HoTs, first in the buff row
	buffs = true, -- the rest of the buff row: big defensives and your buffs
	timers = true, -- the time left on buffs, red and blinking near the end
	buffSize = 14, -- buff icons, in pixels
	debuffs = true, -- the debuff row, the ones you can remove first
	debuffSize = 14,
	cleanseClick = true, -- a left click on a debuff you can remove casts the spell that does
	dispel = true, -- the frame's edge takes the color of a debuff you can remove
	range = true, rangeAlpha = 0.4,
	aggro = true,
	mana = true,
	hideGame = true, -- the game's own party and raid frames
	hideParty = true, -- Pathwise UI's party unit frames while these are on (when it is installed)
	point = nil,
})
H.DEFAULT_POINT = { "TOPLEFT", "TOPLEFT", 30, -200 }
H.HEALERS = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c, d = pcall(fn, ...) if ok then return a, b, c, d end end

---------------------------------------------------------------------------
-- Secret values: look without touching
---------------------------------------------------------------------------

local function isSecret(v)
	if not issecretvalue then return false end
	local ok, s = pcall(issecretvalue, v)
	return (not ok) or s == true
end
H.IsSecret = isSecret

-- A yes/no that may be secret: the plain answer, or `default`.
local function bool(v, default)
	if isSecret(v) then return default end
	if v == nil then return default end
	return v and true or false
end
H.Bool = bool

-- One of two numbers chosen by a yes/no that may be secret; the game does
-- the choosing when it is. The result may be secret: give it to a widget.
local function choose(v, yes, no, unknown)
	if not isSecret(v) then
		if v == nil then return unknown end
		return v and yes or no
	end
	local eval = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
	if eval then
		local ok, r = pcall(eval, v, yes, no)
		if ok and type(r) ~= "nil" then return r end
	end
	return unknown
end
H.Choose = choose

-- Curves the game evaluates for us: percent (0..1 -> 0..100) and a health
-- color (red, yellow, green).
local percentCurve, colorCurve, tried = nil, nil, {}
local function curve(kind)
	if tried[kind] then return kind == "percent" and percentCurve or colorCurve end
	tried[kind] = true
	local C = C_CurveUtil
	if kind == "percent" and C and C.CreateCurve then
		local c = call(C.CreateCurve)
		if c and pcall(function() c:AddPoint(0, 0) c:AddPoint(1, 100) end) then percentCurve = c end
		return percentCurve
	end
	if kind == "color" and C and C.CreateColorCurve and CreateColor then
		local c = call(C.CreateColorCurve)
		local good, warn, bad = T.Color("success"), T.Color("warning"), T.Color("error")
		if c and pcall(function()
			c:AddPoint(0, CreateColor(bad[1], bad[2], bad[3], 1))
			c:AddPoint(0.3, CreateColor(bad[1], bad[2], bad[3], 1))
			c:AddPoint(0.55, CreateColor(warn[1], warn[2], warn[3], 1))
			c:AddPoint(0.85, CreateColor(good[1], good[2], good[3], 1))
			c:AddPoint(1, CreateColor(good[1], good[2], good[3], 1))
		end) then colorCurve = c end
		return colorCurve
	end
end
ns.On("ACCENT_CHANGED", function() tried.color, colorCurve = nil, nil end)

-- Auras: readable only out of a fight on Forever; a refusal pauses reads.
local auraPause, fighting = 0, false
local function aurasAllowed()
	if fighting then return false end -- from PLAYER_REGEN_DISABLED, a moment before the lockdown
	if (GetTime and GetTime() or 0) < auraPause then return false end
	local R, E = C_RestrictedActions, Enum and Enum.AddOnRestrictionType
	if R and R.IsAddOnRestrictionActive and E then
		for _, k in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch" }) do
			if E[k] and call(R.IsAddOnRestrictionActive, E[k]) then return false end
		end
	end
	return C_UnitAuras and C_UnitAuras.GetAuraDataByIndex and true or false
end
local function aura(unit, i, filter)
	local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
	if not ok then auraPause = (GetTime and GetTime() or 0) + 5 return nil, true end
	return data
end
local function readable(v) if isSecret(v) then return nil end return v end
-- For Auras.lua.
H.AurasAllowed, H.Aura, H.Readable, H.InCombat, H.Call = aurasAllowed, aura, readable, inCombat, call
function H.SetFighting(on) fighting = on and true or false end

---------------------------------------------------------------------------
-- A frame
---------------------------------------------------------------------------

local buttons = {} -- every frame we made
local byUnit = {} -- unit -> { [button] = true }
H.buttons, H.byUnit = buttons, byUnit

-- A 2 px edge just inside (or outside, `out`) a frame, for dispel and aggro.
local function edge(frame, out, layer)
	local e, o = {}, out and -2 or 0
	local function t() local x = frame:CreateTexture(nil, layer or "OVERLAY", nil, 6) T.NoSnap(x) e[#e + 1] = x return x end
	local top, bot, l, r = t(), t(), t(), t()
	top:SetPoint("TOPLEFT", o, -o) top:SetPoint("TOPRIGHT", -o, -o) top:SetHeight(2)
	bot:SetPoint("BOTTOMLEFT", o, o) bot:SetPoint("BOTTOMRIGHT", -o, o) bot:SetHeight(2)
	l:SetPoint("TOPLEFT", o, -o) l:SetPoint("BOTTOMLEFT", o, o) l:SetWidth(2)
	r:SetPoint("TOPRIGHT", -o, -o) r:SetPoint("BOTTOMRIGHT", -o, o) r:SetWidth(2)
	return {
		edges = e,
		SetColor = function(self, c, a) for _, x in ipairs(e) do x:SetColorTexture(c[1], c[2], c[3], a or 1) end end,
		SetShown = function(self, on) for _, x in ipairs(e) do x:SetShown(on) end end,
		SetAlpha = function(self, a) for _, x in ipairs(e) do if not pcall(x.SetAlpha, x, a) then x:SetAlpha(0) end end end,
	}
end

H.Edge = edge
local BAR = "Interface\\Buttons\\WHITE8X8"

-- Dress a secure unit button the header made (Heal.xml's OnLoad), or one a
-- test made. Its size and clicks are set out of combat (H.Size, Clicks).
function H.NewButton(b)
	if b.pwHeal then return b end
	b.pwHeal = true
	T.Panel(b, "bg", "border", 0.92)
	local health = CreateFrame("StatusBar", nil, b)
	health:SetStatusBarTexture(BAR)
	health:SetPoint("TOPLEFT", 1, -1)
	health:SetPoint("BOTTOMRIGHT", -1, 1)
	if health.SetClipsChildren then health:SetClipsChildren(true) end
	local hbg = health:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(0, 0, 0, 0.35)
	b.health = health
	T.Sheen(health)
	-- Heals on the way: a lighter bar starting where health ends.
	local inc = CreateFrame("StatusBar", nil, health)
	inc:SetStatusBarTexture(BAR)
	local fill = health.GetStatusBarTexture and health:GetStatusBarTexture()
	if fill then
		inc:SetPoint("TOPLEFT", fill, "TOPRIGHT")
		inc:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT")
	end
	inc:SetFrameLevel((health:GetFrameLevel() or 1))
	b.incoming = inc
	local power = CreateFrame("StatusBar", nil, b)
	power:SetStatusBarTexture(BAR)
	power:SetPoint("BOTTOMLEFT", 1, 1)
	power:SetPoint("BOTTOMRIGHT", -1, 1)
	power:SetHeight(3)
	b.power = power
	local over = CreateFrame("Frame", nil, b)
	over:SetAllPoints()
	over:SetFrameLevel((health:GetFrameLevel() or 1) + 3)
	b.over = over
	b.name = T.Text(over, "meta", "text")
	b.name:SetPoint("CENTER", 0, 5)
	b.name:SetJustifyH("CENTER")
	b.name:SetJustifyV("MIDDLE")
	b.name:SetWordWrap(false)
	T.BarText(b.name, "meta")
	b.value = T.Text(over, "small", "text2")
	b.value:SetPoint("CENTER", 0, -8)
	b.value:SetJustifyH("CENTER")
	b.value:SetJustifyV("MIDDLE")
	T.BarText(b.value, "small")
	b.dispel = edge(over, false)
	b.dispel:SetShown(false)
	b.aggro = edge(b, true, "BACKGROUND")
	b.aggro:SetColor(T.Color("error"))
	b.aggro:SetShown(false)
	b.target = T.Border(over, "OVERLAY", 7)
	T.Paint(b.target, "text")
	b.hover = over:CreateTexture(nil, "ARTWORK")
	b.hover:SetAllPoints()
	b.hover:SetColorTexture(1, 1, 1, 0)
	H.MakeAuras(b) -- the buff and debuff rows (Auras.lua)
	b:HookScript("OnEnter", function(self)
		A.Hover(self, true, function(p) self.hover:SetColorTexture(1, 1, 1, 0.08 * p) end)
		if GameTooltip and self.pwUnit then
			if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
			pcall(GameTooltip.SetUnit, GameTooltip, self.pwUnit)
			GameTooltip:Show()
		end
	end)
	b:HookScript("OnLeave", function(self)
		A.Hover(self, false, function(p) self.hover:SetColorTexture(1, 1, 1, 0.08 * p) end)
		if GameTooltip then GameTooltip:Hide() end
	end)
	if ClickCastFrames then ClickCastFrames[b] = true end -- Clique and friends
	buttons[#buttons + 1] = b
	H.Size(b)
	if ns.HealClicks then ns.HealClicks.Apply(b) end
	return b
end

-- The button's unit changed (the header sets "unit").
function H.SetUnit(b, unit)
	local old = b.pwUnit
	if old and byUnit[old] then byUnit[old][b] = nil end
	b.pwUnit = unit
	if unit then
		byUnit[unit] = byUnit[unit] or {}
		byUnit[unit][b] = true
		H.Update(b) -- in a fight this attaches the game's auras (H.Auras)
	end
end

-- Heal.xml's scripts.
function H.OnLoad(b) H.NewButton(b) end
function H.OnAttributeChanged(b, name, value)
	if name == "unit" then H.SetUnit(b, value) end
end

function H.Size(b)
	if inCombat() then H.pending = true return end
	b:SetSize(ns.Get("heal.width") or 84, ns.Get("heal.height") or 40)
	b.power:SetShown(ns.Get("heal.mana") and true or false)
	b.health:ClearAllPoints()
	b.health:SetPoint("TOPLEFT", 1, -1)
	b.health:SetPoint("BOTTOMRIGHT", -1, ns.Get("heal.mana") and 5 or 1)
	b.incoming:SetWidth(math.max(1, (ns.Get("heal.width") or 84) - 2))
	if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
	H.PlaceAuras(b) -- Auras.lua
end

---------------------------------------------------------------------------
-- Drawing a frame
---------------------------------------------------------------------------

local function setBar(bar, cur, max)
	if max ~= nil then pcall(bar.SetMinMaxValues, bar, 0, max) end
	if cur == nil then return end
	local E = Enum and Enum.StatusBarInterpolation
	local how = ns.Get("units.smooth") and A.Enabled() and E and E.ExponentialEaseOut
	if how and pcall(bar.SetValue, bar, cur, how) then return end
	pcall(bar.SetValue, bar, cur)
end

function H.Color(b, unit)
	local mode = ns.Get("heal.color")
	if mode == "health" then
		local c = UnitHealthPercent and curve("color")
		if c then
			local ok, col = pcall(UnitHealthPercent, unit, true, c)
			if ok and col and col.GetRGB then b.health:SetStatusBarColor(col:GetRGB()) return end
		end
		mode = "green"
	end
	if mode == "class" then
		local _, class = call(UnitClass, unit)
		class = readable(class)
		local c = class and T.ClassColor(class)
		if c then b.health:SetStatusBarColor(c[1], c[2], c[3]) return end
	end
	local g = T.Color("success")
	b.health:SetStatusBarColor(g[1], g[2], g[3])
end

function H.Text(b, unit)
	local mode = ns.Get("heal.text")
	local fs = b.value
	if mode == "percent" and UnitHealthPercent then
		local c = curve("percent")
		local ok = pcall(function()
			if c then fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit, true, c)) else fs:SetFormattedText("%.0f%%", UnitHealthPercent(unit)) end
		end)
		if ok then return end
	elseif mode == "deficit" and UnitHealthMissing then
		local trunc = C_StringUtil and C_StringUtil.TruncateWhenZero
		local missing = call(UnitHealthMissing, unit)
		if trunc and missing ~= nil then
			local ok, txt = pcall(trunc, missing)
			if ok then fs:SetText(txt) return end
		end
		local n = readable(missing)
		if type(n) == "number" then
			fs:SetText(n > 0 and ("-" .. (n >= 1000 and ("%.1fk"):format(n / 1000) or n)) or "")
			return
		end
	end
	fs:SetText("")
end

function H.Range(b, unit)
	if not ns.Get("heal.range") or bool(call(UnitIsUnit, unit, "player"), false) then b:SetAlpha(1) return end
	local inRange, checked = call(UnitInRange, unit)
	if bool(checked, true) == false then b:SetAlpha(1) return end
	local a = choose(inRange, 1, ns.Get("heal.rangeAlpha") or 0.4, 1)
	if not pcall(b.SetAlpha, b, a) then b:SetAlpha(1) end
end

function H.Update(b)
	local unit = b.pwUnit
	if not unit or not b.health then return end
	if call(UnitExists, unit) == false then return end
	b.name:SetText(call(UnitName, unit) or "")
	local max, cur = call(UnitHealthMax, unit), call(UnitHealth, unit)
	setBar(b.health, cur, max)
	H.Color(b, unit)
	local offline = bool(call(UnitIsConnected, unit), true) == false
	local dead = bool(call(UnitIsDeadOrGhost, unit), false)
	if offline then b.value:SetText("Offline") T.Paint(b.value, "muted")
	elseif dead then b.value:SetText("Dead") T.Paint(b.value, "error")
	else T.Paint(b.value, "text2") H.Text(b, unit) end
	-- Heals on the way.
	if ns.Get("heal.incoming") and not offline and not dead then
		local inc = call(UnitGetIncomingHeals, unit)
		b.incoming:Show()
		setBar(b.incoming, inc or 0, max)
		local g = T.Color("success")
		b.incoming:SetStatusBarColor(g[1], g[2], g[3], 0.45)
	else
		b.incoming:Hide()
	end
	-- Mana.
	if ns.Get("heal.mana") then
		local ptype, token = call(UnitPowerType, unit)
		token = readable(token)
		local mana
		if token then mana = token == "MANA" else mana = readable(ptype) == 0 end
		if mana then
			setBar(b.power, call(UnitPower, unit), call(UnitPowerMax, unit))
			local m = T.Color("mana")
			b.power:SetStatusBarColor(m[1], m[2], m[3])
			b.power:SetAlpha(1)
		else
			b.power:SetAlpha(0)
		end
	end
	-- Aggro: only when the game says it plainly.
	local threat = readable(call(UnitThreatSituation, unit))
	b.aggro:SetShown(ns.Get("heal.aggro") and type(threat) == "number" and threat >= 2 or false)
	-- Your target: a light edge, its alpha chosen by the game when secret.
	b.target:SetShown(true)
	local ta = choose(call(UnitIsUnit, unit, "target"), 1, 0, 0)
	for _, e in ipairs(b.target.edges) do if not pcall(e.SetAlpha, e, ta) then e:SetAlpha(0) end end
	H.Range(b, unit)
	H.Auras(b, unit)
end

function H.UpdateUnit(unit)
	local set = byUnit[unit]
	if not set then return end
	for b in pairs(set) do if b.pwUnit == unit and b:IsVisible() then H.Update(b) end end
end
function H.UpdateAll() for _, b in ipairs(buttons) do if b.pwUnit then H.Update(b) end end end

---------------------------------------------------------------------------
-- The grid: one secure group header for party and raid
---------------------------------------------------------------------------

local anchor, header

local function build()
	if anchor then return anchor end
	anchor = CreateFrame("Frame", "PathwiseHeal_Frames", nil)
	anchor:SetParent(UIParent)
	anchor:SetMovable(true)
	anchor:SetClampedToScreen(true)
	anchor:SetSize(84, 40)
	header = CreateFrame("Frame", "PathwiseHeal_Header", anchor, "SecureGroupHeaderTemplate")
	header:SetPoint("TOPLEFT", anchor, "TOPLEFT")
	header:SetAttribute("template", "PathwiseHeal_ButtonTemplate")
	return anchor
end
function H.Anchor() return anchor end
function H.Header() return header end

-- Everything the header needs, from the settings (out of combat).
function H.Layout()
	if inCombat() then H.pending = true return end
	build()
	local w, hgt, gap = ns.Get("heal.width") or 84, ns.Get("heal.height") or 40, ns.Get("heal.spacing") or 3
	local down = ns.Get("heal.grow") ~= "right"
	for _, b in ipairs(buttons) do H.Size(b) end
	local a = {
		showRaid = true, showParty = true, showPlayer = true, showSolo = ns.Get("heal.solo") and true or false,
		groupBy = "GROUP", groupingOrder = "1,2,3,4,5,6,7,8", sortMethod = "INDEX",
		maxColumns = 8, unitsPerColumn = 5,
		point = down and "TOP" or "LEFT",
		xOffset = down and 0 or gap, yOffset = down and -gap or 0,
		columnSpacing = gap, columnAnchorPoint = down and "LEFT" or "TOP",
		minWidth = w, minHeight = hgt,
	}
	for k, v in pairs(a) do header:SetAttribute(k, v) end
	anchor:SetSize(down and w or 5 * (w + gap) - gap, down and 5 * (hgt + gap) - gap or hgt)
	local p = ns.Get("heal.point") or H.DEFAULT_POINT
	anchor:ClearAllPoints()
	anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	local on = ns.Get("heal.enabled") and true or false
	anchor:SetShown(on)
	header:SetShown(on)
	if on and ns.Get("heal.hideGame") then H.HideGame() end
	H.UpdateAll()
end

-- The game's party and raid frames, out of sight (back after a reload when off).
local hider, hidden = nil, {}
function H.HideGame()
	if inCombat() then H.pending = true return end
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	for _, name in ipairs({ "CompactRaidFrameContainer", "CompactRaidFrameManager", "CompactPartyFrame" }) do
		local f = _G[name]
		if type(f) == "table" and not hidden[f] and f.SetParent then
			pcall(f.UnregisterAllEvents, f)
			pcall(f.SetParent, f, hider)
			hidden[f] = true
		end
	end
end
function H.Hidden() return hidden end

---------------------------------------------------------------------------
-- Moving it with everything else
---------------------------------------------------------------------------

local unlocked, handle = false, nil
function H.Unlock(on)
	if inCombat() then return false end
	if on and not ns.Get("heal.enabled") then return false end -- nothing to move while off
	unlocked = on and true or false
	build()
	if not handle then
		handle = ns.Movers.Handle(anchor, "Healing frames", function(p, rp, x, y) ns.Set("heal.point", { p, rp, x, y }) end)
	end
	handle:Reveal(unlocked and anchor:IsShown())
	ns.Movers.Active("heal", unlocked)
	return true
end
function H.Unlocked() return unlocked end
function H.ResetPosition() ns.Set("heal.point", nil) end
ns.Movers.Group("heal", function(on) if on or unlocked then H.Unlock(on) end end)
ns.On("MOVE_MODE", function(any) if not any and unlocked then H.Unlock(false) end end)

---------------------------------------------------------------------------
-- Asking a healer once
---------------------------------------------------------------------------

local prompt
function H.IsHealerClass()
	local _, class = call(UnitClass, "player")
	class = readable(class)
	return class and H.HEALERS[class] or false
end

function H.Ask()
	if prompt then prompt:Show() return prompt end
	local _, class = call(UnitClass, "player")
	local name = (readable(class) or "healer"):lower():gsub("^%l", string.upper)
	prompt = CreateFrame("Frame", "PathwiseHeal_Prompt", nil)
	prompt:SetParent(UIParent)
	prompt:SetFrameStrata("DIALOG")
	prompt:SetSize(380, 132)
	prompt:SetPoint("TOP", UIParent, "TOP", 0, -140)
	T.Panel(prompt)
	T.AccentLine(prompt)
	local title = T.Text(prompt, "title", "text")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Healing frames")
	local body = T.Text(prompt, "body", "text2")
	body:SetPoint("TOPLEFT", 16, -42)
	body:SetWidth(348)
	body:SetWordWrap(true)
	body:SetText(("You're playing a %s. Turn on Pathwise healing frames? Click a party or raid member to heal them, and see heals on the way and debuffs you can cleanse. You can change this any time: type /pwheal."):format(name))
	local yes = T.Button(prompt, "Turn on", "accent", function()
		ns.CharData("heal").asked = true
		ns.Set("heal.enabled", true)
		prompt:Hide()
	end)
	yes:SetPoint("BOTTOMRIGHT", -12, 12)
	local no = T.Button(prompt, "Not now", "default", function()
		ns.CharData("heal").asked = true
		prompt:Hide()
	end)
	no:SetPoint("RIGHT", yes, "LEFT", -8, 0)
	A.Set(prompt, "alpha", 0)
	prompt:SetAlpha(0)
	A.Fade(prompt, 1, A.NORMAL)
	return prompt
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION", "UNIT_CONNECTION", "UNIT_FLAGS",
	"UNIT_NAME_UPDATE", "UNIT_POWER_UPDATE", "UNIT_DISPLAYPOWER", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_IN_RANGE_UPDATE", "UNIT_AURA" }
for _, ev in ipairs(UNIT_EVENTS) do
	ns.RegisterEvent(ev, function(_, unit) if ns.Get("heal.enabled") and unit then H.UpdateUnit(unit) end end)
end
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() if ns.Get("heal.enabled") then H.UpdateAll() end end)
ns.RegisterEvent("GROUP_ROSTER_UPDATE", function() if ns.Get("heal.enabled") then H.UpdateAll() end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	fighting = false -- (set by Auras.lua at PLAYER_REGEN_DISABLED)
	if H.pending then H.pending = false if anchor or ns.Get("heal.enabled") then H.Layout() end end
	if ns.Get("heal.enabled") then H.UpdateAll() end -- auras readable again
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if handle then handle:Hide() end
	unlocked = false
end)

ns.On("READY", function()
	if ns.Get("heal.enabled") then H.Layout() end
	if not ns.Get("heal.enabled") and H.IsHealerClass() and not ns.CharData("heal").asked then H.Ask() end
end)
-- Pathwise UI, when installed, hides its own party frames while these show
-- them (heal.hideParty): it asks H.HidesUIParty, and hears when it changes.
function H.HidesUIParty() return ns.Get("heal.enabled") and ns.Get("heal.hideParty") and true or false end
local function tellUI()
	local UI = _G.PathwiseUI
	if type(UI) == "table" and UI.Fire then UI.Fire("HEAL_CHANGED") end
end

ns.On("SETTING_CHANGED", function(path)
	if type(path) ~= "string" then return end
	if path == "heal.enabled" or path == "heal.hideParty" or path == "*" then tellUI() end
	if path:find("^heal%.") or path == "*" then
		if H.AuraSettingChanged then H.AuraSettingChanged(path) end -- Auras.lua
		if anchor or ns.Get("heal.enabled") then H.Layout() end
	end
end)
ns.On("ACCENT_CHANGED", function() if anchor and anchor:IsShown() then H.UpdateAll() end end)
