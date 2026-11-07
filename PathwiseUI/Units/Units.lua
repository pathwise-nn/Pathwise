-- Pathwise UI unit frames: you, your target, its target, your pet, your
-- focus and your party, in the Pathwise look.
--
-- How Forever shapes this (Blizzard's Forever API documentation):
--   * UnitHealth is always a "secret" value, and power, auras, casts, class
--     and leader can be in some places: addon code cannot read or compare
--     them. Bars and text take them as they are (StatusBar:SetValue /
--     SetMinMaxValues, FontString:SetText / SetFormattedText, Texture:
--     SetTexture accept secrets), and AbbreviateNumbers shortens them
--     ("12.3k"). Anything that needs the number itself (a timer, a count of
--     1 hidden) is only done when the value is readable.
--   * Clicks: each frame is a SecureUnitButtonTemplate (left: target,
--     right: the unit's menu), shown and hidden by RegisterUnitWatch, so it
--     works in combat. Frames are made, sized and moved out of combat only.
--
-- Nothing here comes from ElvUI or oUF; the frames are Pathwise UI's own.

local ADDON, ns = ...
local T = ns.Theme
local U = {}
ns.Units = U

ns.Defaults("units", {
	enabled = true,
	hideBlizzard = true,
	style = "slim", -- "slim" (Pathwise: text on the dark ground, slim bars) | "full" (the bars fill the frame, text on them)
	healthText = "auto", -- "auto" (both on your and your target's frame, current on small ones) | "current" | "both" (current / most) | "percent" | "full" (current / most and percent) | "none"
	healthColor = "class", -- "class" (players by class, others by reaction) | "accent" | "dark"
	powerText = true,
	powerFormat = "auto", -- as healthText, without "none" (powerText switches the number off)
	auras = true,
	onlyMyDebuffs = false,
	castbars = true,
	portraits = false,
	smooth = true, -- bars glide to a new value (the game eases them; secret values too)
	-- Which frames: player, target, targettarget, pet, focus, party.
	player = true, target = true, targettarget = true, pet = true, focus = false, party = true,
})

local readable = ns.Readable
local frames = {} -- unit -> frame
U.frames = frames

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- Is there a value? A secret value counts, and is never tested or compared
-- itself (Forever forbids that); only ordinary values are.
local function has(v)
	if issecretvalue and issecretvalue(v) then return true end
	return v ~= nil
end
U.Has = has
-- Short text for a (perhaps secret) number: "12.3k".
local function short(v)
	if AbbreviateNumbers then return AbbreviateNumbers(v) end
	return v
end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...) if ok then return a, b, c, d, e, f, g, h, i end end

---------------------------------------------------------------------------
-- Colors
---------------------------------------------------------------------------

-- From the color scheme (the Colors page changes them all).
U.REACTION = setmetatable({}, { __index = function(_, k) return T.Color(k) end })
local POWER_COLOR = { MANA = "mana", RAGE = "rage", ENERGY = "energy", FOCUS = "focus", RUNIC_POWER = "accent", HAPPINESS = "success" }
U.POWER = setmetatable({}, { __index = function(_, k) local n = POWER_COLOR[k] return n and T.Color(n) or nil end })

-- A bar color white text reads on: the very light class colors (priest
-- white, rogue yellow, hunter green) a shade deeper, same hue. Others as
-- they are.
U.LIGHT, U.DEEPEN_TO = 0.7, 0.62 -- relative luminance
function U.Readable(c)
	local lum = 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3]
	if lum <= U.LIGHT then return c end
	local k = U.DEEPEN_TO / lum
	return { c[1] * k, c[2] * k, c[3] * k }
end

-- The health bar's color for a unit.
function U.HealthColor(unit)
	local mode = ns.Get("units.healthColor")
	if mode == "accent" then return T.Color("accent") end
	if mode == "dark" then return T.Color("healthDark") end
	local isPlayer = readable(call(UnitIsPlayer, unit))
	if isPlayer then
		local class = readable(select(2, call(UnitClass, unit)))
		local c = class and T.ClassColor(class)
		if c then return U.Slim() and c or U.Readable(c) end
	end
	local r = readable(call(UnitReaction, unit, "player"))
	if type(r) == "number" then
		if r <= 3 then return U.REACTION.hostile elseif r == 4 then return U.REACTION.neutral end
		return U.REACTION.friendly
	end
	return T.Color("accent")
end

function U.PowerColor(unit)
	return T.Color(U.PowerColorName(unit))
end
-- The scheme's name for it ("mana", "rage"...), so text painted in it
-- follows the Colors page.
function U.PowerColorName(unit)
	local _, token = call(UnitPowerType, unit)
	token = readable(token)
	return (token and POWER_COLOR[token]) or "mana"
end

---------------------------------------------------------------------------
-- Building a frame
---------------------------------------------------------------------------

local BAR = "Interface\\Buttons\\WHITE8X8"

-- A bar's new value: eased by the game when smooth bars are on (it takes
-- secret values as they are), else at once.
local function ease()
	if not ns.Get("units.smooth") or not ns.Anim.Enabled() then return nil end
	local E = Enum and Enum.StatusBarInterpolation
	return E and E.ExponentialEaseOut or nil
end
function U.SetBar(bar, v)
	local how = ease()
	if how then
		if pcall(bar.SetValue, bar, v, how) then return end
	end
	bar:SetValue(v)
end

local function bar(parent)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture(BAR)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.35)
	b.bg = bg
	return b
end

-- The percent curve: UnitHealthPercent's 0-1 answer scaled to 0-100.
-- (Its documentation says "a floating point percentage value"; that it is
-- 0-1 is not yet checked in game.)
local percentCurve
local function curve()
	if percentCurve == nil then
		percentCurve = false
		if C_CurveUtil and C_CurveUtil.CreateCurve then
			local c = call(C_CurveUtil.CreateCurve)
			if c and c.AddPoint then
				pcall(c.AddPoint, c, 0, 0)
				pcall(c.AddPoint, c, 1, 100)
				percentCurve = c
			end
		end
	end
	return percentCurve or nil
end

-- A unit's health in percent (0-100), perhaps secret; nil when the client
-- cannot say.
function U.Percent(unit)
	if not (UnitHealthPercent and curve()) then return nil end
	return call(UnitHealthPercent, unit, true, curve())
end

-- A unit's power in percent (0-100), perhaps secret; nil when unknown.
-- From the numbers when they are readable, else UnitPowerPercent with the
-- curve (where the client has it; not yet checked on Forever).
function U.PowerPercent(unit, cur, max)
	local c, m = readable(cur), readable(max)
	if type(c) == "number" and type(m) == "number" then
		if m > 0 then return c / m * 100 end
		return nil
	end
	if not (UnitPowerPercent and curve()) then return nil end
	return call(UnitPowerPercent, unit, nil, true, curve())
end

-- An amount as text: "current" 543, "both" 543 / 587, "percent" 93%,
-- "full" 543 / 587 · 93%. Secret values pass through the game's own
-- formatting; a missing percent falls back to the numbers.
function U.ShowAmount(fs, mode, cur, max, pct)
	if mode == "percent" then
		if has(pct) then fs:SetFormattedText("%.0f%%", pct) else fs:SetText(short(cur)) end
	elseif mode == "full" and has(max) and has(pct) then
		fs:SetFormattedText("%s / %s  \194\183  %.0f%%", short(cur), short(max), pct)
	elseif (mode == "both" or mode == "full") and has(max) then
		fs:SetFormattedText("%s / %s", short(cur), short(max))
	else
		fs:SetText(short(cur))
	end
end
local function wantsPercent(mode) return mode == "percent" or mode == "full" end

-- def = { unit, name, w, h, power (bool), castbar (bool), auras = { filter, count }, buffs = { filter, count } }
function U.Make(def)
	if frames[def.unit] then return frames[def.unit] end
	if inCombat() then return nil end
	local f = CreateFrame("Button", "PathwiseUI_" .. def.name, nil, "SecureUnitButtonTemplate")
	f:SetParent(UIParent)
	f.unit, f.def = def.unit, def
	f:SetAttribute("unit", def.unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f:SetFrameStrata("LOW")
	T.Panel(f, "bg", "border", 0.9)

	-- Health, power, texts.
	f.health = bar(f)
	f.power = bar(f)
	f.name = T.Text(f.health, "body", "text")
	f.name:SetPoint("LEFT", f.health, "LEFT", 6, 0)
	f.name:SetJustifyV("MIDDLE")
	f.name:SetWordWrap(false)
	f.level = T.Text(f.health, "meta", "text2")
	f.level:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
	f.level:SetJustifyV("MIDDLE")
	f.hp = T.Text(f.health, "body", "text")
	f.hp:SetPoint("RIGHT", f.health, "RIGHT", -6, 0)
	f.hp:SetJustifyH("RIGHT")
	f.hp:SetJustifyV("MIDDLE")
	f.pp = T.Text(f.power, "small", "text")
	f.pp:SetPoint("RIGHT", f.power, "RIGHT", -6, 0)
	f.pp:SetJustifyH("RIGHT")
	f.pp:SetJustifyV("MIDDLE")
	T.BarText(f.name, "uname") T.BarText(f.level, "meta")
	T.Sheen(f.health) T.Sheen(f.power) T.BarText(f.hp, "body") T.BarText(f.pp, "small")

	-- Portrait (optional), status marks.
	f.portrait = f:CreateTexture(nil, "ARTWORK")
	f.portrait:Hide()
	f.mark = T.Text(f, "label", "text2")
	-- A thin line in your accent along the top while this is your target.
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetPoint("TOPLEFT", 1, -1)
	f.glow:SetPoint("TOPRIGHT", -1, -1)
	f.glow:SetHeight(2)
	T.Paint(f.glow, "accent")
	f.glow:SetAlpha(0)
	f.mark:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 3)

	-- Hover: the unit's tooltip.
	f:SetScript("OnEnter", function(self)
		T.SetBorder(self, "muted")
		if not GameTooltip then return end
		if GameTooltip_SetDefaultAnchor then GameTooltip_SetDefaultAnchor(GameTooltip, self) else GameTooltip:SetOwner(self, "ANCHOR_RIGHT") end
		pcall(GameTooltip.SetUnit, GameTooltip, self.unit)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function(self) T.SetBorder(self, "border") if GameTooltip then GameTooltip:Hide() end end)

	if def.unit ~= "player" and RegisterUnitWatch then RegisterUnitWatch(f) end
	if def.castbar then U.MakeCastbar(f) end
	if def.auras then U.MakeAuras(f, def.auras, def.buffs) end
	frames[def.unit] = f
	U.Layout(f)
	U.Events(f)
	U.Update(f)
	return f
end

-- Size and inner layout from the settings (out of combat).
function U.Layout(f)
	if inCombat() then U.pending = true return end
	local d = f.def
	local w = ns.Get("units." .. d.name .. "W") or d.w
	local h = ns.Get("units." .. d.name .. "H") or d.h
	f:SetSize(w, h)
	local portrait = ns.Get("units.portraits") and d.big
	local left = 1
	if portrait then
		f.portrait:ClearAllPoints()
		f.portrait:SetPoint("TOPLEFT", 1, -1)
		f.portrait:SetSize(h - 2, h - 2)
		f.portrait:Show()
		left = h
	else
		f.portrait:Hide()
	end
	if U.Slim() then return U.LayoutSlim(f, w, h, left) end
	-- Full bars: health fills the frame, the texts on it.
	f.name:SetParent(f.health) f.hp:SetParent(f.health) f.pp:SetParent(f.power)
	f.pp:ClearAllPoints()
	f.pp:SetPoint("RIGHT", f.power, "RIGHT", -6, 0)
	f.pp:SetJustifyV("MIDDLE")
	T.Paint(f.pp, "text")
	for _, b in ipairs({ f.health, f.power }) do
		for _, t in ipairs(b.pwSheen or {}) do t:Show() end
	end
	-- The power bar is tall enough for its number when it shows one.
	local powerText = ns.Get("units.powerText")
	local powerH = (d.power and h >= 30) and math.max(powerText and 12 or 4, math.floor(h * (powerText and 0.27 or 0.22))) or 0
	f.name:ClearAllPoints()
	f.name:SetPoint("LEFT", f.health, "LEFT", 6, 0)
	f.name:SetPoint("RIGHT", f.hp, "LEFT", -6, 0)
	f.hp:ClearAllPoints()
	f.hp:SetPoint("RIGHT", f.health, "RIGHT", -6, 0)
	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", left, -1)
	f.health:SetPoint("BOTTOMRIGHT", -1, 1 + powerH + (powerH > 0 and 1 or 0))
	f.power:ClearAllPoints()
	f.power:SetPoint("BOTTOMLEFT", left, 1)
	f.power:SetPoint("BOTTOMRIGHT", -1, 1)
	f.power:SetHeight(math.max(1, powerH))
	f.power:SetShown(powerH > 0)
	f.pp:SetShown(powerH >= 8 and powerText and true or false)
	T.BarText(f.pp, "small", math.min(11, powerH - 1))
	T.BarText(f.name, h >= 30 and "uname" or "unameSmall")
	T.BarText(f.hp, h >= 30 and "body" or "meta")
end

-- Slim, Pathwise's own look (as its guide window): the name and health in
-- text on the dark ground, a slim health bar under them in the unit's color,
-- a thin power bar under that, its number beside the health in its color.
-- No text sits on a colored bar.
--   | Florp           207 / 207   180 / 180 |
--   | ███████████████████░░░░░░░░░░░ |
--   | ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬ |
function U.Slim() return ns.Get("units.style") ~= "full" end

function U.LayoutSlim(f, w, h, left)
	local d = f.def
	local roomy = h >= 34
	local pad = roomy and 9 or 5
	local x = left + pad - 1
	local powerH = (d.power and h >= 30) and 3 or 0
	local healthH = roomy and 6 or 4
	local gap = powerH > 0 and 2 or 0
	f.power:ClearAllPoints()
	f.power:SetPoint("BOTTOMLEFT", x, pad - 1)
	f.power:SetPoint("BOTTOMRIGHT", -pad, pad - 1)
	f.power:SetHeight(math.max(1, powerH))
	f.power:SetShown(powerH > 0)
	f.health:ClearAllPoints()
	f.health:SetPoint("BOTTOMLEFT", x, pad - 1 + powerH + gap)
	f.health:SetPoint("BOTTOMRIGHT", -pad, pad - 1 + powerH + gap)
	f.health:SetHeight(healthH)
	for _, b in ipairs({ f.health, f.power }) do
		for _, t in ipairs(b.pwSheen or {}) do t:Hide() end
	end
	-- The texts on the frame's own ground, over the bars.
	-- The power number (when the frame has a power bar) at the right, the
	-- health number before it.
	local showPP = powerH > 0 and ns.Get("units.powerText") and true or false
	local lift = roomy and 5 or 3
	f.name:SetParent(f) f.hp:SetParent(f) f.pp:SetParent(f)
	f.name:ClearAllPoints()
	f.hp:ClearAllPoints()
	f.pp:ClearAllPoints()
	if showPP then
		f.pp:SetPoint("BOTTOMRIGHT", f.health, "TOPRIGHT", 0, lift)
		f.hp:SetPoint("BOTTOMRIGHT", f.pp, "BOTTOMLEFT", -10, 0)
	else
		f.hp:SetPoint("BOTTOMRIGHT", f.health, "TOPRIGHT", 0, lift)
	end
	f.name:SetPoint("BOTTOMLEFT", f.health, "TOPLEFT", 0, lift)
	f.name:SetPoint("RIGHT", f.hp, "LEFT", -8, 0)
	f.name:SetJustifyV("BOTTOM") f.hp:SetJustifyV("BOTTOM") f.pp:SetJustifyV("BOTTOM")
	T.PlainText(f.name, roomy and "window" or "body", "text")
	T.PlainText(f.hp, roomy and "meta" or "small", "text2")
	T.PlainText(f.pp, roomy and "meta" or "small", U.PowerColorName(f.unit))
	f.pp:SetShown(showPP)
end

---------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------

function U.UpdateHealth(f)
	local u = f.unit
	local max = call(UnitHealthMax, u)
	local cur = call(UnitHealth, u)
	if has(max) then f.health:SetMinMaxValues(0, max) end
	if has(cur) then U.SetBar(f.health, cur) end
	local c = U.HealthColor(u)
	f.health:SetStatusBarColor(c[1], c[2], c[3])
	local dead = readable(call(UnitIsDead, u))
	local online = readable(call(UnitIsConnected, u))
	local mode = ns.Get("units.healthText")
	if mode == "auto" then mode = f.def.big and "both" or "current" end
	if online == false then f.hp:SetText("Offline")
	elseif dead then f.hp:SetText("Dead")
	elseif mode == "none" or not has(cur) then f.hp:SetText("")
	else
		U.ShowAmount(f.hp, mode, cur, max, wantsPercent(mode) and U.Percent(u) or nil)
	end
	f:SetAlpha(online == false and 0.6 or 1)
end

function U.UpdatePower(f)
	if not f.power:IsShown() then return end
	local u = f.unit
	local max = call(UnitPowerMax, u)
	local cur = call(UnitPower, u)
	if has(max) then f.power:SetMinMaxValues(0, max) end
	if has(cur) then U.SetBar(f.power, cur) end
	local c = U.PowerColor(u)
	f.power:SetStatusBarColor(c[1], c[2], c[3])
	if f.pp:IsShown() then
		if U.Slim() then T.Paint(f.pp, U.PowerColorName(u)) end
		-- Auto: "427 / 427" on your and your target's frame, so it says what it is.
		local mode = ns.Get("units.powerFormat")
		if mode == "auto" then mode = f.def.big and "both" or "current" end
		if not has(cur) or readable(max) == 0 then f.pp:SetText("") -- nothing to show (a monster without mana)
		else U.ShowAmount(f.pp, mode, cur, max, wantsPercent(mode) and U.PowerPercent(u, cur, max) or nil) end
	end
end

function U.UpdateName(f)
	local u = f.unit
	local name = call(UnitName, u)
	if has(name) then f.name:SetText(name) else f.name:SetText("") end
	local level = call(UnitLevel, u)
	local lv = readable(level)
	if lv == -1 then f.level:SetText("??") elseif has(level) then f.level:SetText(level) else f.level:SetText("") end
	-- The level is in the line over the frame (U.UpdateMarks), not against the name.
	f.level:Hide()
	f.levelText = (lv == -1 and "??") or (type(lv) == "number" and tostring(lv)) or nil
	if f.portrait:IsShown() and SetPortraitTexture then pcall(SetPortraitTexture, f.portrait, u) end
end

-- Little words over the frame, Pathwise's labels: the level quiet, then
-- combat, resting and party leader in your accent: "LEVEL 10 · LEADER".
local function hexOf(name)
	local c = T.Color(name)
	return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end
function U.UpdateMarks(f)
	local bits = {}
	if f.def.big and f.levelText then bits[#bits + 1] = "LEVEL " .. f.levelText end
	local flags = {}
	if f.unit == "player" then
		if inCombat() then flags[#flags + 1] = "COMBAT" elseif readable(call(IsResting)) then flags[#flags + 1] = "RESTING" end
	end
	if readable(call(UnitIsGroupLeader, f.unit)) then flags[#flags + 1] = "LEADER" end
	for _, w in ipairs(flags) do bits[#bits + 1] = ("|cff%s%s|r"):format(hexOf("accent"), w) end
	f.mark:SetText(table.concat(bits, "  ·  "))
end

-- Your target among the others (party, focus...): the accent line fades in.
function U.UpdateTargeted(f)
	if not f.glow then return end
	local on = f.unit ~= "target" and f.unit ~= "targettarget" and readable(call(UnitIsUnit, f.unit, "target")) == true
	ns.Anim.Fade(f.glow, on and 1 or 0, ns.Anim.NORMAL)
end

function U.Update(f)
	if not (f and readable(call(UnitExists, f.unit)) ~= false) then return end
	U.UpdateName(f)
	U.UpdateTargeted(f)
	U.UpdateHealth(f)
	U.UpdatePower(f)
	U.UpdateMarks(f)
	if f.auras then U.UpdateAuras(f) end
	if f.castbar then U.UpdateCast(f) end
end

function U.UpdateAll() for _, f in pairs(frames) do U.Update(f) end end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local UNIT_EVENTS = {
	UNIT_HEALTH = "health", UNIT_MAXHEALTH = "health", UNIT_CONNECTION = "health", UNIT_FACTION = "health", UNIT_FLAGS = "health",
	UNIT_POWER_UPDATE = "power", UNIT_MAXPOWER = "power", UNIT_DISPLAYPOWER = "power",
	UNIT_NAME_UPDATE = "name", UNIT_LEVEL = "name", UNIT_PORTRAIT_UPDATE = "name",
	UNIT_AURA = "auras",
	UNIT_SPELLCAST_START = "cast", UNIT_SPELLCAST_STOP = "cast", UNIT_SPELLCAST_FAILED = "cast",
	UNIT_SPELLCAST_INTERRUPTED = "interrupted", UNIT_SPELLCAST_DELAYED = "cast",
	UNIT_SPELLCAST_CHANNEL_START = "cast", UNIT_SPELLCAST_CHANNEL_STOP = "cast", UNIT_SPELLCAST_CHANNEL_UPDATE = "cast",
}
local DO = {
	health = U.UpdateHealth, power = U.UpdatePower, name = U.UpdateName,
	auras = function(f) if f.auras then U.UpdateAuras(f) end end,
	cast = function(f) if f.castbar then U.UpdateCast(f) end end,
	interrupted = function(f) if f.castbar then f.pwInterrupted = true U.UpdateCast(f) end end,
}

function U.Events(f)
	local driver = CreateFrame("Frame")
	f.driver = driver
	for ev in pairs(UNIT_EVENTS) do
		if driver.RegisterUnitEvent then pcall(driver.RegisterUnitEvent, driver, ev, f.unit) else pcall(driver.RegisterEvent, driver, ev) end
	end
	driver:SetScript("OnEvent", function(_, ev, unit)
		if unit and unit ~= f.unit then return end
		local what = UNIT_EVENTS[ev]
		if what and DO[what] then
			local ok, err = pcall(DO[what], f)
			if not ok then ns.Error(ev, err) end
		end
	end)
end

-- The whole frame again when what it shows changes.
local function onChange(units)
	return function()
		for _, u in ipairs(units) do if frames[u] then U.Update(frames[u]) end end
	end
end
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function()
	onChange({ "target", "targettarget" })()
	for _, f in pairs(frames) do U.UpdateTargeted(f) end
end)
ns.RegisterEvent("PLAYER_FOCUS_CHANGED", onChange({ "focus" }))
ns.RegisterEvent("UNIT_PET", function(_, owner) if owner == "player" then onChange({ "pet" })() end end)
ns.RegisterEvent("GROUP_ROSTER_UPDATE", onChange({ "party1", "party2", "party3", "party4" }))
ns.RegisterEvent("PARTY_LEADER_CHANGED", function() for _, f in pairs(frames) do U.UpdateMarks(f) end end)
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function() U.UpdateAll() end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() if frames.player then U.UpdateMarks(frames.player) end end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if frames.player then U.UpdateMarks(frames.player) end
	if U.pending then U.pending = false U.Build() end
end)
ns.RegisterEvent("PLAYER_UPDATE_RESTING", function() if frames.player then U.UpdateMarks(frames.player) end end)

-- The target's target has no events of its own: a look four times a second.
local tot = CreateFrame("Frame")
local since = 0
tot:SetScript("OnUpdate", function(_, dt)
	since = since + (dt or 0)
	if since < 0.25 then return end
	since = 0
	local f = frames.targettarget
	if f and f:IsVisible() then U.Update(f) end
end)
