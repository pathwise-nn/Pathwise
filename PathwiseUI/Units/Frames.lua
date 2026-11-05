-- Which unit frames there are, where they sit, moving them, and putting the
-- game's own unit frames out of sight while Pathwise UI's are on.

local ADDON, ns = ...
local T = ns.Theme
local U = ns.Units

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- name: the settings prefix (units.<name>W, units.<name>H, units.<name>Point)
-- key: the switch for it (units.<key>)
U.DEFS = {
	{ unit = "player", name = "Player", key = "player", w = 230, h = 48, big = true, power = true, castbar = true,
		point = { "CENTER", "CENTER", -300, -180 } },
	{ unit = "target", name = "Target", key = "target", w = 230, h = 48, big = true, power = true, castbar = true,
		auras = { filter = "HARMFUL", count = 8, size = 22 }, point = { "CENTER", "CENTER", 300, -180 } },
	{ unit = "targettarget", name = "TargetTarget", key = "targettarget", w = 130, h = 24,
		point = { "CENTER", "CENTER", 490, -170 } },
	{ unit = "pet", name = "Pet", key = "pet", w = 130, h = 24, power = true,
		point = { "CENTER", "CENTER", -490, -170 } },
	{ unit = "focus", name = "Focus", key = "focus", w = 190, h = 36, big = true, power = true, castbar = true,
		point = { "CENTER", "CENTER", -300, -90 } },
}
for i = 1, 4 do
	U.DEFS[#U.DEFS + 1] = { unit = "party" .. i, name = "Party" .. i, key = "party", w = 190, h = 38, big = true, power = true,
		auras = { filter = "HARMFUL", count = 4, size = 18, at = "RIGHT" },
		point = { "TOPLEFT", "TOPLEFT", 30, -220 - (i - 1) * 52 } }
end

-- Each frame's size has a default, so the size sliders start where it is.
do
	local d = {}
	for _, def in ipairs(U.DEFS) do d[def.name .. "W"], d[def.name .. "H"] = def.w, def.h end
	ns.Defaults("units", d)
end

function U.Def(unit) for _, d in ipairs(U.DEFS) do if d.unit == unit then return d end end end

function U.Place(f)
	if inCombat() then U.pending = true return end
	local d = f.def
	local p = ns.Get("units." .. d.name .. "Point") or d.point
	f:ClearAllPoints()
	f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- Every frame as the settings say (out of combat; else once combat ends).
function U.Build()
	if inCombat() then U.pending = true return end
	local on = ns.Get("units.enabled")
	for _, d in ipairs(U.DEFS) do
		local want = on and ns.Get("units." .. d.key)
		-- Healing frames show your party already: Pathwise's party frames step aside.
		if d.key == "party" and ns.Get("heal.enabled") and ns.Get("heal.hideParty") then want = false end
		local f = U.frames[d.unit]
		if want and not f then f = U.Make(d) end
		if f then
			f:SetMovable(true)
			U.Layout(f)
			U.Place(f)
			if want then
				if d.unit ~= "player" and RegisterUnitWatch then RegisterUnitWatch(f) else f:Show() end
				U.Update(f)
			else
				if UnregisterUnitWatch then UnregisterUnitWatch(f) end
				f:Hide()
			end
		end
	end
	if on and ns.Get("units.hideBlizzard") then U.HideBlizzard() end
end

---------------------------------------------------------------------------
-- Moving the frames
---------------------------------------------------------------------------

local unlocked = false
local movers = {}

local function mover(f)
	local m = movers[f]
	if m then return m end
	m = ns.Movers.Handle(f, f.def.name:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2"):upper(), function(p, rp, x, y)
		ns.Set("units." .. f.def.name .. "Point", { p, rp, x, y })
	end)
	movers[f] = m
	return m
end

function U.Unlock(on)
	if inCombat() then ns.Print("frames can be moved out of combat.") return false end
	unlocked = on and true or false
	for _, f in pairs(U.frames) do
		local m = mover(f)
		local want = ns.Get("units.enabled") and ns.Get("units." .. f.def.key)
		if unlocked and want then
			if UnregisterUnitWatch then UnregisterUnitWatch(f) end
			f:Show()
			m:Reveal(true)
		else
			m:Reveal(false)
		end
	end
	if not unlocked then U.Build() end
	ns.Movers.Active("units", unlocked)
	ns.Fire("UNITS_UNLOCKED", unlocked)
	return true
end
function U.Unlocked() return unlocked end
ns.Movers.Group("units", function(on) if on or unlocked then U.Unlock(on) end end)

function U.ResetPositions()
	for _, d in ipairs(U.DEFS) do ns.Set("units." .. d.name .. "Point", nil) end
	for _, f in pairs(U.frames) do U.Place(f) end
end

ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- Combat: the handles go (the frames stay put until it ends).
	for _, m in pairs(movers) do m:Hide() end
	if unlocked then unlocked = false U.pending = true end
end)

---------------------------------------------------------------------------
-- The game's own unit frames
---------------------------------------------------------------------------

local hider
local GAME = {
	player = { "PlayerFrame" }, target = { "TargetFrame", "ComboFrame" }, targettarget = { "TargetFrameToT" },
	pet = { "PetFrame" }, focus = { "FocusFrame" },
	party = { "PartyFrame", "PartyMemberFrame1", "PartyMemberFrame2", "PartyMemberFrame3", "PartyMemberFrame4" },
}
local hidden = {}

-- Out of sight: their events off, parented to a hidden frame (so the game
-- showing them again changes nothing). Back after a reload when switched off.
function U.HideBlizzard()
	if inCombat() then U.pending = true return end
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	for key, names in pairs(GAME) do
		if ns.Get("units." .. key) then
			for _, name in ipairs(names) do
				local f = _G[name]
				if type(f) == "table" and not hidden[f] and f.SetParent then
					pcall(f.UnregisterAllEvents, f)
					pcall(f.SetParent, f, hider)
					hidden[f] = true
				end
			end
		end
	end
end
function U.Hidden() return hidden end

ns.On("READY", function() U.Build() end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) ~= "string" then return end
	if (path:find("^units%.") and not path:find("Point$")) or path == "heal.enabled" or path == "heal.hideParty" then
		U.Build()
		U.UpdateAll()
		for _, f in pairs(U.frames) do if f.auras then U.PlaceAuras(f) end end
	elseif path == "*" then
		U.Build()
	end
end)
ns.On("ACCENT_CHANGED", function() U.UpdateAll() end)
