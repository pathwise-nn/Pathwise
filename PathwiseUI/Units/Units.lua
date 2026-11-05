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
	healthText = "current", -- "current" | "both" | "percent" | "none"
	healthColor = "class", -- "class" (players by class, others by reaction) | "accent" | "dark"
	powerText = true,
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

-- The health bar's color for a unit.
function U.HealthColor(unit)
	local mode = ns.Get("units.healthColor")
	if mode == "accent" then return T.Color("accent") end
	if mode == "dark" then return T.Color("healthDark") end
	local isPlayer = readable(call(UnitIsPlayer, unit))
	if isPlayer then
		local class = readable(select(2, call(UnitClass, unit)))
		local c = class and T.ClassColor(class)
		if c then return c end
	end
	local r = readable(call(UnitReaction, unit, "player"))
	if type(r) == "number" then
		if r <= 3 then return U.REACTION.hostile elseif r == 4 then return U.REACTION.neutral end
		return U.REACTION.friendly
	end
	return T.Color("accent")
end

function U.PowerColor(unit)
	local _, token = call(UnitPowerType, unit)
	token = readable(token)
	return (token and U.POWER[token]) or U.POWER.MANA
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

-- def = { unit, name, w, h, power (bool), castbar (bool), auras = { filter, count } }
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
	f.mark = T.Text(f, "label", "warning")
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
	if def.auras then U.MakeAuras(f, def.auras) end
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
	local powerH = (d.power and h >= 30) and math.max(4, math.floor(h * 0.22)) or 0
	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", left, -1)
	f.health:SetPoint("BOTTOMRIGHT", -1, 1 + powerH + (powerH > 0 and 1 or 0))
	f.power:ClearAllPoints()
	f.power:SetPoint("BOTTOMLEFT", left, 1)
	f.power:SetPoint("BOTTOMRIGHT", -1, 1)
	f.power:SetHeight(math.max(1, powerH))
	f.power:SetShown(powerH > 0)
	f.pp:SetShown(powerH >= 8 and ns.Get("units.powerText"))
	T.BarText(f.name, h >= 30 and "uname" or "unameSmall")
	T.BarText(f.hp, h >= 30 and "body" or "meta")
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
	if online == false then f.hp:SetText("Offline")
	elseif dead then f.hp:SetText("Dead")
	elseif mode == "none" or not has(cur) then f.hp:SetText("")
	elseif mode == "percent" then
		local pct
		if UnitHealthPercent and curve() then pct = call(UnitHealthPercent, u, true, curve()) end
		if has(pct) then f.hp:SetFormattedText("%.0f%%", pct) else f.hp:SetText(short(cur)) end
	elseif mode == "both" and has(max) then
		f.hp:SetFormattedText("%s / %s", short(cur), short(max))
	else
		f.hp:SetText(short(cur))
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
	if f.pp:IsShown() and has(cur) then f.pp:SetText(short(cur)) end
end

function U.UpdateName(f)
	local u = f.unit
	local name = call(UnitName, u)
	if has(name) then f.name:SetText(name) else f.name:SetText("") end
	local level = call(UnitLevel, u)
	local lv = readable(level)
	if lv == -1 then f.level:SetText("??") elseif has(level) then f.level:SetText(level) else f.level:SetText("") end
	f.level:SetShown(f.def.big and true or false)
	if f.portrait:IsShown() and SetPortraitTexture then pcall(SetPortraitTexture, f.portrait, u) end
end

-- Little words over the frame: combat, resting, party leader.
function U.UpdateMarks(f)
	local bits = {}
	if f.unit == "player" then
		if inCombat() then bits[#bits + 1] = "COMBAT" elseif readable(call(IsResting)) then bits[#bits + 1] = "RESTING" end
	end
	if readable(call(UnitIsGroupLeader, f.unit)) then bits[#bits + 1] = "LEADER" end
	f.mark:SetText(table.concat(bits, "  "))
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
