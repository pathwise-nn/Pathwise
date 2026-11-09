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
		auras = { filter = "HARMFUL", count = 8, size = 22 }, buffs = { filter = "HELPFUL", count = 8, size = 20 }, point = { "CENTER", "CENTER", -300, -180 } },
	{ unit = "target", name = "Target", key = "target", w = 230, h = 48, big = true, power = true, castbar = true, combo = true,
		auras = { filter = "HARMFUL", count = 8, size = 22 }, buffs = { filter = "HELPFUL", count = 8, size = 20 }, point = { "CENTER", "CENTER", 300, -180 } },
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
		if d.key == "party" and U.HealHidesParty() then want = false end
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
	U.PlaceCastbar()
end

---------------------------------------------------------------------------
-- Your cast bar: above the action bars, under your frame, or the game's
---------------------------------------------------------------------------
-- "bars" (default): Pathwise's bar for your casts sits centred over the
-- topmost of Pathwise UI's bottom action bars, as wide as it. "frame": under
-- your unit frame. "game": Pathwise's is off and the game's shows.
-- With Pathwise's on, the game's own player cast bar is silenced (its events
-- off: it never shows). It is not moved or reparented: Edit Mode owns its
-- place, and an addon writing there could get the game's actions blocked.
-- Back after a reload when switched to "game".
ns.Defaults("units", { castbarSpot = "bars" })

-- The topmost shown bar of the bottom three (Pathwise UI's bars 1-3).
function U.TopBar()
	local B = ns.Bars
	if not (B and B.bars) then return nil end
	local best, bestTop
	for id = 1, 3 do
		local bar = B.bars[id]
		if bar and bar:IsShown() then
			local top = bar.GetTop and bar:GetTop()
			top = type(top) == "number" and top or id
			if not bestTop or top > bestTop then best, bestTop = bar, top end
		end
	end
	return best
end

-- Pathwise shows your casts (not "game", cast bars and your frame on).
function U.OwnPlayerCastbar()
	return ns.Get("units.enabled") and ns.Get("units.player") and ns.Get("units.castbars")
		and ns.Get("units.castbarSpot") ~= "game" and true or false
end

local silenced = false
function U.SilenceGameCastbar()
	local g = _G.PlayerCastingBarFrame
	if silenced or type(g) ~= "table" then return end
	silenced = true
	pcall(g.UnregisterAllEvents, g)
	pcall(g.Hide, g)
end

function U.PlaceCastbar()
	local f = U.frames.player
	local cb = f and f.castbar
	if not cb then return end
	if inCombat() then U.pending = true return end
	if U.OwnPlayerCastbar() then U.SilenceGameCastbar() end
	cb:ClearAllPoints()
	local top = U.OwnPlayerCastbar() and ns.Get("units.castbarSpot") == "bars" and U.TopBar() or nil
	if top then
		cb.pwAway = true
		cb:SetParent(UIParent)
		cb:SetFrameStrata("MEDIUM")
		cb:SetHeight(18)
		cb.icon:SetSize(18, 18)
		cb:SetPoint("BOTTOMLEFT", top, "TOPLEFT", 20, 12)
		cb:SetPoint("BOTTOMRIGHT", top, "TOPRIGHT", 0, 12)
	else
		cb.pwAway = nil
		cb:SetParent(f)
		cb:SetHeight(16)
		cb.icon:SetSize(16, 16)
		cb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 18, -4)
		cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
	end
	if f.auras then U.PlaceAuras(f) end
end
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and path:find("^bars%.") then U.PlaceCastbar() end
end)

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
local hidden = {} -- frame -> "moved" (under the hidden frame) or "faded"
local faded = {}  -- frames already hooked to stay faded

local function underHider(f)
	local okP, p = pcall(f.GetParent, f)
	return okP and p == hider
end

-- When the game will not let the frame be moved (Forever checks whether a
-- frame's parent may change, and a player saw the game's player frame stay):
-- invisible, its clicks off, hidden; shown again or faded back in by the
-- game, it goes again (hidden out of combat, faded any time).
local function fade(f)
	pcall(f.SetAlpha, f, 0)
	pcall(f.EnableMouse, f, false)
	pcall(f.Hide, f)
	if faded[f] or not hooksecurefunc then return end
	faded[f] = true
	local busy = false
	pcall(hooksecurefunc, f, "SetAlpha", function(self)
		if busy or underHider(self) then return end
		busy = true
		pcall(self.SetAlpha, self, 0)
		busy = false
	end)
	pcall(hooksecurefunc, f, "Show", function(self)
		if underHider(self) then return end
		pcall(self.SetAlpha, self, 0)
		if not inCombat() then pcall(self.Hide, self) end
	end)
end

-- Out of sight: their events off, parented to a hidden frame (so the game
-- showing them again changes nothing); if the game keeps the frame where it
-- is, faded instead. Checked again on each call (login, each loading
-- screen, the end of combat). Back after a reload when switched off.
function U.HideBlizzard()
	if inCombat() then U.pending = true return end
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	for key, names in pairs(GAME) do
		if ns.Get("units." .. key) then
			for _, name in ipairs(names) do
				local f = _G[name]
				if type(f) == "table" and f.SetParent and not underHider(f) then
					pcall(f.UnregisterAllEvents, f)
					pcall(f.SetParent, f, hider)
					if underHider(f) then
						hidden[f] = "moved"
					else
						hidden[f] = "faded"
						fade(f)
					end
				end
			end
		end
	end
end
function U.Hidden() return hidden end

-- /pwui frames: what happened to each of the game's unit frames, for a bug report.
function U.ReportGame()
	ns.Print("the game's unit frames:")
	for _, key in ipairs({ "player", "target", "targettarget", "pet", "focus", "party" }) do
		for _, name in ipairs(GAME[key]) do
			local f = _G[name]
			local state
			if type(f) ~= "table" then state = "not in this game"
			elseif not (ns.Get("units.enabled") and ns.Get("units." .. key) and ns.Get("units.hideBlizzard")) then state = "left alone (Pathwise's is off)"
			elseif underHider(f) then state = "put away"
			elseif hidden[f] == "faded" then state = "the game kept it: faded out"
			else state = "not put away yet" end
			local extra = ""
			if type(f) == "table" then
				local okS, shown = pcall(f.IsShown, f)
				local okA, alpha = pcall(f.GetAlpha, f)
				-- Secret values (Forever) are left out rather than printed.
				if okS and okA then
					local okF, s = pcall(function() return (" (shown %s, alpha %.2f)"):format(shown and "yes" or "no", alpha) end)
					if okF then extra = s end
				end
			end
			ns.Print("  " .. name .. ": " .. state .. extra)
		end
	end
end
ns.Commands.frames = function() U.ReportGame() end

-- The game may move or show its frames again on a loading screen.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if ns.Get("units.enabled") and ns.Get("units.hideBlizzard") then U.HideBlizzard() end
end)

ns.On("READY", function() U.Build() end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) ~= "string" then return end
	if path:find("^units%.") and not path:find("Point$") then
		U.Build()
		U.UpdateAll()
		for _, f in pairs(U.frames) do if f.auras then U.PlaceAuras(f) end end
	elseif path == "*" then
		U.Build()
	end
end)
ns.On("ACCENT_CHANGED", function() U.UpdateAll() end)

-- Pathwise Heal (a separate addon), when installed and showing your party,
-- may ask these party frames to step aside; it says when that changes.
function U.HealHidesParty()
	local H = _G.PathwiseHeal
	return type(H) == "table" and H.Heal and H.Heal.HidesUIParty and H.Heal.HidesUIParty() or false
end
ns.On("HEAL_CHANGED", function() U.Build() U.UpdateAll() end)
