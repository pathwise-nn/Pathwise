-- Pathwise UI nameplates: a slim bar over each monster and player in the
-- Pathwise look: health by class or reaction, the name, your target marked
-- in your accent, threat when the game shares it, the cast and your own
-- debuffs.
--
-- How (Blizzard's Forever UI source, Blizzard_NamePlates):
--   * Each nameplate the game shows to addons (NAME_PLATE_UNIT_ADDED) gets a
--     Pathwise frame of its own on it; the game's own art on that plate is
--     faded out (SetAlpha), never removed or replaced, right after the game
--     has given the plate its unit frame (hooksecurefunc on
--     NamePlateDriverFrame:OnNamePlateAdded).
--   * Colours are the game's own plates' (see P.Color).
--   * Some plates are "forbidden" to addons (FORBIDDEN_NAME_PLATE_*, e.g.
--     friendly plates in instances): they are left to the game, untouched.
--   * Health and other values may be secret: passed straight to bars and
--     text, never tested (see Units/Units.lua). The target is found by
--     comparing plates (C_NamePlate.GetNamePlateForUnit("target")), which is
--     never secret; threat colors only when the game shares threat.
-- Nothing here comes from ElvUI, Plater or any other nameplate addon.

local ADDON, ns = ...
local T = ns.Theme
local U = ns.Units
local P = {}
ns.Plates = P

ns.Defaults("plates", {
	enabled = true,
	width = 130, height = 10,
	healthText = "none", -- "none" | "current" | "percent"
	castbars = true,
	debuffs = true, -- your own debuffs on each enemy
	threat = false, -- color by threat, in the game's threat colors (the default plates: off)
	classColors = true, -- enemy players in their class color
	friendly = true, -- dress friendly plates too (where the game allows)
	targetScale = 1.15,
})

local readable = ns.Readable
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c, d = pcall(fn, ...) if ok then return a, b, c, d end end

P.plates = {} -- unit token -> our frame
local pool = {} -- our frames by their nameplate

local function gamePlate(unit)
	local get = C_NamePlate and C_NamePlate.GetNamePlateForUnit
	local plate = get and call(get, unit)
	if type(plate) ~= "table" then return nil end
	if plate.IsForbidden and plate:IsForbidden() then return nil end
	return plate
end

local BAR = "Interface\\Buttons\\WHITE8X8"

local function make(plate)
	local f = CreateFrame("Frame", nil, plate)
	f:SetPoint("CENTER", plate, "CENTER", 0, 0)
	f:SetFrameLevel((plate:GetFrameLevel() or 1) + 5)
	T.Panel(f, "bg", "border", 0.85)
	f.health = CreateFrame("StatusBar", nil, f)
	f.health:SetStatusBarTexture(BAR)
	f.health:SetPoint("TOPLEFT", 1, -1)
	f.health:SetPoint("BOTTOMRIGHT", -1, 1)
	f.name = T.Text(f, "meta", "text", "OVERLAY")
	f.name:SetPoint("BOTTOM", f, "TOP", 0, 3)
	f.name:SetJustifyH("CENTER")
	f.name:SetWordWrap(false)
	f.name:SetShadowOffset(1, -1)
	f.name:SetShadowColor(0, 0, 0, 0.9)
	f.hp = T.Text(f.health, "small", "text", "OVERLAY")
	f.hp:SetPoint("CENTER")
	f.hp:SetJustifyH("CENTER")
	f.hp:SetShadowOffset(1, -1)
	-- Your target: an accent frame around the bar.
	f.mark = CreateFrame("Frame", nil, f)
	f.mark:SetPoint("TOPLEFT", -2, 2)
	f.mark:SetPoint("BOTTOMRIGHT", 2, -2)
	f.mark.edges = {}
	for _, spec in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 }, { "TOPLEFT", "BOTTOMLEFT", 1, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 1, nil } }) do
		local t = f.mark:CreateTexture(nil, "OVERLAY")
		t:SetPoint(spec[1])
		t:SetPoint(spec[2])
		if spec[3] then t:SetWidth(spec[3]) else t:SetHeight(spec[4]) end
		T.Paint(t, "accent")
	end
	f.mark:Hide()
	-- The cast and your debuffs: the unit frames' own pieces.
	f.def = { name = "Plate" }
	U.MakeCastbar(f)
	f.castbar:SetHeight(10)
	U.MakeAuras(f, { filter = "HARMFUL|PLAYER", count = 5, size = 18 }) -- your own debuffs
	-- Debuffs above the name.
	for i, b in ipairs(f.auras.icons) do
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * 21, 18)
	end
	f.plate = plate
	return f
end

---------------------------------------------------------------------------
-- What each plate shows
---------------------------------------------------------------------------

-- Health color, as the game's own plates have it (Forever's
-- CompactUnitFrame_UpdateHealthColor, with the nameplate options): grey when
-- dead or offline, threat (only when switched on), class for players, light
-- grey when tapped by someone else, red once it is in combat with you, then
-- the game's selection color (UnitSelectionColor: red, yellow, green...).
P.GREY, P.TAPPED, P.HOSTILE = { 0.5, 0.5, 0.5 }, { 0.9, 0.9, 0.9 }, { 1, 0, 0 }
P.SELECTION = { hostile = { 1, 0, 0 }, neutral = { 1, 1, 0 }, friendly = { 0, 1, 0 } } -- when the game gives none
local function num(...) local a, b, c = ... a, b, c = readable(a), readable(b), readable(c) if type(a) == "number" and type(b) == "number" and type(c) == "number" then return { a, b, c } end end
function P.Color(unit)
	local isPlayer = readable(call(UnitIsPlayer, unit))
	if readable(call(UnitIsConnected, unit)) == false or (readable(call(UnitIsDead, unit)) and not isPlayer) then return P.GREY end
	if ns.Get("plates.threat") then
		local s = readable(call(UnitThreatSituation, "player", unit))
		if type(s) == "number" and s > 0 then
			local c = GetThreatStatusColor and num(call(GetThreatStatusColor, s))
			if c then return c end
		end
	end
	if isPlayer and ns.Get("plates.classColors") then
		local class = readable(select(2, call(UnitClass, unit)))
		local cc = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
		if cc then return { cc.r, cc.g, cc.b } end
		local c = class and T.ClassColor(class)
		if c then return c end
	end
	if not readable(call(UnitPlayerControlled, unit)) and readable(call(UnitIsTapDenied, unit)) then return P.TAPPED end
	local friend = readable(call(UnitIsFriend, "player", unit))
	if not friend then
		local _, status = call(UnitDetailedThreatSituation, "player", unit)
		if readable(status) ~= nil then return P.HOSTILE end
	end
	local c = UnitSelectionColor and num(call(UnitSelectionColor, unit, true))
	if c then return c end
	local r = readable(call(UnitReaction, unit, "player"))
	if type(r) == "number" then
		if r <= 3 then return P.SELECTION.hostile elseif r == 4 then return P.SELECTION.neutral end
		return P.SELECTION.friendly
	end
	return T.Color("text2")
end

function P.UpdateHealth(f)
	local u = f.unit
	local max, cur = call(UnitHealthMax, u), call(UnitHealth, u)
	if U.Has(max) then f.health:SetMinMaxValues(0, max) end
	if U.Has(cur) then f.health:SetValue(cur) end
	local c = P.Color(u)
	f.health:SetStatusBarColor(c[1], c[2], c[3])
	local mode = ns.Get("plates.healthText")
	if mode == "none" or not U.Has(cur) then f.hp:SetText("")
	elseif mode == "percent" and UnitHealthPercent and C_CurveUtil then
		f.hp:SetText("")
		local pct = U.Percent and U.Percent(u)
		if U.Has(pct) then f.hp:SetFormattedText("%.0f%%", pct) end
	else
		f.hp:SetText(AbbreviateNumbers and AbbreviateNumbers(cur) or cur)
	end
end

function P.UpdateName(f)
	local name = call(UnitName, f.unit)
	if U.Has(name) then f.name:SetText(name) else f.name:SetText("") end
end

-- The game's own art on a plate, faded (or back). The game gives each plate
-- a unit frame from a pool when it is added (NamePlateDriverMixin:
-- OnNamePlateAdded) and takes it back when removed, so the one faded is kept
-- (faded[f]) and given back its look when the plate goes: a pooled frame
-- never carries our fade to another plate.
--
-- The game sets that frame's alpha again on its own (CompactUnitFrame.lua:
-- CompactUnitFrame_UpdateCenterStatusIcon ends with the range alpha, on many
-- unit events), so each unit frame gets a SetAlpha hook once, which puts our
-- fade back while the frame is ours (hidden[uf]).
local faded = setmetatable({}, { __mode = "k" }) -- our frame -> the game's unit frame we faded
local hidden = setmetatable({}, { __mode = "k" }) -- game unit frame -> true while faded by us
local hooked = setmetatable({}, { __mode = "k" })
local refading = false
local function keepFaded(uf)
	if hooked[uf] or not hooksecurefunc then return end
	hooked[uf] = true
	hooksecurefunc(uf, "SetAlpha", function(self)
		if hidden[self] and not refading then
			refading = true
			self:SetAlpha(0)
			refading = false
		end
	end)
end
local function unfade(f)
	local uf = faded[f]
	faded[f] = nil
	if type(uf) == "table" and uf.SetAlpha then
		hidden[uf] = nil
		uf:SetAlpha(1)
	end
end
local function gameArt(plate, show, f)
	local uf = plate and plate.UnitFrame
	if f and faded[f] ~= uf then unfade(f) end
	if type(uf) == "table" and uf.SetAlpha then
		if not show then keepFaded(uf) end
		hidden[uf] = (not show) or nil
		uf:SetAlpha(show and 1 or 0)
		if f then faded[f] = (not show) and uf or nil end
	end
end

-- Your target: marked, a little bigger, always on top.
function P.UpdateTarget(f)
	local target = gamePlate("target")
	local on = target ~= nil and target == f.plate
	f.mark:SetShown(on)
	gameArt(f.plate, false, f) -- still faded, whatever the game did on the target change
	local s = on and (ns.Get("plates.targetScale") or 1.15) or 1
	f:SetScale(s)
	f:SetFrameLevel(((f.plate and f.plate:GetFrameLevel()) or 1) + (on and 20 or 5))
end

function P.Layout(f)
	f:SetSize(ns.Get("plates.width") or 130, ns.Get("plates.height") or 10)
	if f.castbar then
		f.castbar:ClearAllPoints()
		f.castbar:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, -3)
		f.castbar:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -3)
	end
end

function P.Update(f)
	P.UpdateName(f)
	P.UpdateHealth(f)
	P.UpdateTarget(f)
	if ns.Get("plates.debuffs") then U.UpdateAuras(f) else for _, b in ipairs(f.auras.icons) do b:Hide() end end
	if ns.Get("plates.castbars") then U.UpdateCast(f) else f.castbar:Hide() end
end

---------------------------------------------------------------------------
-- Plates coming and going
---------------------------------------------------------------------------


function P.Added(unit)
	if not ns.Get("plates.enabled") then return end
	local plate = gamePlate(unit)
	if not plate then return end
	local friendly = readable(call(UnitIsFriend, "player", unit))
	if friendly and not ns.Get("plates.friendly") then gameArt(plate, true) return end
	local f = pool[plate] or make(plate)
	pool[plate] = f
	f.unit = unit
	P.plates[unit] = f
	gameArt(plate, false, f)
	P.Layout(f)
	f:Show()
	P.Update(f)
end

function P.Removed(unit)
	local f = P.plates[unit]
	if f then
		unfade(f)
		f:Hide()
		f.unit = nil
		if f.castbar then f.castbar:Hide() end
	end
	P.plates[unit] = nil
end

function P.RefreshAll()
	for unit, f in pairs(P.plates) do P.Removed(unit) end
	local list = C_NamePlate and C_NamePlate.GetNamePlates and call(C_NamePlate.GetNamePlates)
	for _, plate in ipairs(type(list) == "table" and list or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then
			if ns.Get("plates.enabled") then P.Added(unit) else gameArt(plate, true) end
		end
	end
end

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) P.Added(unit) end)
-- The game's own handler of that event gives the plate its unit frame, and
-- the order of the two handlers is not fixed: again right after the game's.
local driverHooked = false
function P.HookDriver()
	local d = NamePlateDriverFrame
	if driverHooked or not (hooksecurefunc and type(d) == "table" and type(d.OnNamePlateAdded) == "function") then return end
	driverHooked = true
	hooksecurefunc(d, "OnNamePlateAdded", function(_, unit) if type(unit) == "string" then P.Added(unit) end end)
end
ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) P.Removed(unit) end)
ns.RegisterEvent("PLAYER_TARGET_CHANGED", function() for _, f in pairs(P.plates) do P.UpdateTarget(f) end end)

-- Unit events for every plate, from one listener.
local UNIT = {
	UNIT_HEALTH = P.UpdateHealth, UNIT_MAXHEALTH = P.UpdateHealth, UNIT_FACTION = P.UpdateHealth,
	UNIT_THREAT_SITUATION_UPDATE = P.UpdateHealth, UNIT_THREAT_LIST_UPDATE = P.UpdateHealth,
	UNIT_NAME_UPDATE = P.UpdateName,
	UNIT_AURA = function(f) if ns.Get("plates.debuffs") then U.UpdateAuras(f) end end,
}
for _, ev in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE" }) do
	UNIT[ev] = function(f) if ns.Get("plates.castbars") then U.UpdateCast(f) end end
end
for ev, fn in pairs(UNIT) do
	ns.RegisterEvent(ev, function(_, unit)
		local f = unit and P.plates[unit]
		if f then fn(f) end
	end)
end

ns.On("READY", function() P.HookDriver() P.RefreshAll() end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^plates%.") or path == "*") then P.RefreshAll() end
end)
ns.On("ACCENT_CHANGED", function() for _, f in pairs(P.plates) do P.UpdateHealth(f) end end)
