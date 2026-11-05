-- Pathwise UI action bars: five bars of the game's own secure action buttons
-- (ActionBarButtonTemplate, Forever's Blizzard_ActionBar), placed and drawn
-- the Pathwise way.
--
-- How it works (Blizzard's Forever UI source):
--   * A button with an ID acts on slot ID + (page - 1) x 12, the page taken
--     from its bar's "actionpage" attribute (SecureActionButtonMixin:
--     CalculateAction). The game's own code then does the rest: casting,
--     icons, cooldowns, range, charges, glows, dragging spells on and off.
--   * The main bar changes page with your stance, form or stealth through a
--     state driver (SecureHandlerStateTemplate + RegisterStateDriver), which
--     the game runs in combat too.
--   * Your key bindings for the game's bars (ACTIONBUTTON1, MULTIACTIONBAR1
--     BUTTON1, ...) are pointed at these buttons (SetOverrideBindingClick),
--     so the keys you already use keep working.
--   * Everything protected (making, placing, sizing, binding) is done out of
--     combat; what changes in combat waits for it to end.
-- Nothing here comes from ElvUI, Bartender or LibActionButton.

local ADDON, ns = ...
local T = ns.Theme
local B = {}
ns.Bars = B

local function inCombat() return InCombatLockdown and InCombatLockdown() end

-- page: a fixed page, or nil for the main bar (it follows stances and forms).
-- binding: the game's key binding names for its buttons.
B.DEFS = {
	-- Above the game's experience bar and micro menu at the bottom of the screen.
	{ id = 1, name = "Bar1", label = "Main bar", binding = "ACTIONBUTTON", per = 12, point = { "BOTTOM", "BOTTOM", 0, 70 } },
	{ id = 2, name = "Bar2", label = "Bar 2", page = 6, binding = "MULTIACTIONBAR1BUTTON", per = 12, point = { "BOTTOM", "BOTTOM", 0, 112 } },
	{ id = 3, name = "Bar3", label = "Bar 3", page = 5, binding = "MULTIACTIONBAR2BUTTON", per = 12, point = { "BOTTOM", "BOTTOM", 0, 154 } },
	{ id = 4, name = "Bar4", label = "Right bar", page = 3, binding = "MULTIACTIONBAR3BUTTON", per = 1, point = { "RIGHT", "RIGHT", -8, 0 } },
	{ id = 5, name = "Bar5", label = "Right bar 2", page = 4, binding = "MULTIACTIONBAR4BUTTON", per = 1, point = { "RIGHT", "RIGHT", -50, 0 } },
}

-- The main bar's page: override and vehicle bars, temporary forms, then
-- stances and forms (bonus bars 1-5: warrior stances, druid forms, rogue and
-- druid stealth, priest shadowform), then the page you picked (shift+wheel).
B.MAIN_PAGING = "[overridebar] 14; [possessbar] 12; [vehicleui] 12; [shapeshift] 13; "
	.. "[bonusbar:5] 11; [bonusbar:4] 10; [bonusbar:3] 9; [bonusbar:2] 8; [bonusbar:1] 7; "
	.. "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; 1"

do
	local d = { enabled = true, hideBlizzard = true, size = 36, spacing = 4, fade = false, fadeAlpha = 0.3,
		hotkeys = true, macroNames = false, emptySlots = true }
	for _, def in ipairs(B.DEFS) do d[def.name] = def.id <= 3 d[def.name .. "Per"] = def.per end
	ns.Defaults("bars", d)
end

B.bars = {}

---------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------

local function makeBar(def)
	local bar = CreateFrame("Frame", "PathwiseUI_" .. def.name, nil, "SecureHandlerStateTemplate")
	bar:SetParent(UIParent)
	bar:SetFrameStrata("LOW")
	bar.def, bar.buttons = def, {}
	if def.page then
		bar:SetAttribute("actionpage", def.page)
	else
		bar:SetAttribute("actionpage", 1)
		bar:SetAttribute("_onstate-page", [[ self:SetAttribute("actionpage", tonumber(newstate) or 1) ]])
		if RegisterStateDriver then RegisterStateDriver(bar, "page", B.MAIN_PAGING) end
	end
	for i = 1, 12 do
		local name = ("PathwiseUI_%sButton%d"):format(def.name, i)
		local b = CreateFrame("CheckButton", name, bar, "ActionBarButtonTemplate")
		b:SetID(i)
		b.pwBinding = def.binding .. i
		b:SetAttribute("showgrid", 1)
		bar.buttons[i] = b
		B.Style(b)
	end
	return bar
end

function B.Build()
	if inCombat() then B.pending = true return end
	local on = ns.Get("bars.enabled")
	for _, def in ipairs(B.DEFS) do
		local want = on and ns.Get("bars." .. def.name)
		local bar = B.bars[def.id]
		if want and not bar then
			bar = makeBar(def)
			B.bars[def.id] = bar
		end
		if bar then
			bar:SetMovable(true)
			B.Layout(bar)
			B.Place(bar)
			bar:SetShown(want and true or false)
		end
	end
	if on and ns.Get("bars.hideBlizzard") then B.HideBlizzard() end
	B.Bind()
	B.Watch()
	B.Fade()
end

-- Buttons in rows: so many per row, at your size and spacing.
function B.Layout(bar)
	if inCombat() then B.pending = true return end
	local size, gap = ns.Get("bars.size") or 36, ns.Get("bars.spacing") or 4
	local per = math.max(1, math.min(12, ns.Get("bars." .. bar.def.name .. "Per") or bar.def.per))
	local rows = math.ceil(12 / per)
	for i, b in ipairs(bar.buttons) do
		local col, row = (i - 1) % per, math.floor((i - 1) / per)
		b:SetSize(size, size)
		b:ClearAllPoints()
		b:SetPoint("TOPLEFT", bar, "TOPLEFT", col * (size + gap), -row * (size + gap))
		b:SetAttribute("showgrid", ns.Get("bars.emptySlots") and 1 or 0)
		B.Style(b)
	end
	bar:SetSize(per * (size + gap) - gap, rows * (size + gap) - gap)
end

function B.Place(bar)
	if inCombat() then B.pending = true return end
	local p = ns.Get("bars." .. bar.def.name .. "Point") or bar.def.point
	bar:ClearAllPoints()
	bar:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

---------------------------------------------------------------------------
-- Moving the bars: a handle in your color on each, drag, then lock
---------------------------------------------------------------------------

local unlocked = false
local handles = {}
local function handle(bar)
	local m = handles[bar]
	if m then return m end
	m = ns.Movers.Handle(bar, bar.def.label:upper(), function(p, rp, x, y)
		ns.Set("bars." .. bar.def.name .. "Point", { p, rp, x, y })
	end)
	handles[bar] = m
	return m
end

function B.Unlock(on)
	if inCombat() then ns.Print("bars can be moved out of combat.") return false end
	unlocked = on and true or false
	for _, bar in pairs(B.bars) do handle(bar):Reveal(unlocked and bar:IsShown()) end
	ns.Movers.Active("bars", unlocked)
	B.Fade()
	return true
end
function B.Unlocked() return unlocked end
ns.Movers.Group("bars", function(on) if on or unlocked then B.Unlock(on) end end)
function B.ResetPositions()
	for _, def in ipairs(B.DEFS) do ns.Set("bars." .. def.name .. "Point", nil) end
	for _, bar in pairs(B.bars) do B.Place(bar) end
end
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	for _, m in pairs(handles) do m:Hide() end
	unlocked = false
end)
ns.On("MOVE_MODE", function(any) if not any and unlocked then B.Unlock(false) end end)

---------------------------------------------------------------------------
-- Keys: your bindings for the game's bars, on these buttons
---------------------------------------------------------------------------

local binder
function B.Bind()
	if inCombat() then B.pending = true return end
	if not (SetOverrideBindingClick and ClearOverrideBindings and GetBindingKey) then return end
	binder = binder or CreateFrame("Frame")
	ClearOverrideBindings(binder)
	if not ns.Get("bars.enabled") then return end
	for _, bar in pairs(B.bars) do
		if bar:IsShown() then
			for _, b in ipairs(bar.buttons) do
				local keys = { GetBindingKey(b.pwBinding) }
				for _, key in ipairs(keys) do
					SetOverrideBindingClick(binder, false, key, b:GetName(), "LeftButton")
				end
				-- The hotkey text from the same binding.
				if b.UpdateHotkeys then pcall(b.UpdateHotkeys, b, b.pwBinding:gsub("%d+$", "")) end
				B.StyleHotkey(b)
			end
		end
	end
end

---------------------------------------------------------------------------
-- The game's own bars
---------------------------------------------------------------------------

local hider
local GAME = { "MainActionBar", "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight" }
local hidden = {}
function B.HideBlizzard()
	if inCombat() then B.pending = true return end
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	for _, name in ipairs(GAME) do
		local f = _G[name]
		if type(f) == "table" and not hidden[f] and f.SetParent then
			pcall(f.SetParent, f, hider)
			hidden[f] = true
		end
	end
end
function B.Hidden() return hidden end

---------------------------------------------------------------------------
-- Fading: bars soft out of combat, full on mouse-over or in combat
---------------------------------------------------------------------------

-- Each bar eases to its alpha (0.2 s in, 0.4 s out); the mouse watch only
-- runs while fading is on.
local over = {}
local function want(id, bar)
	if not ns.Get("bars.fade") or inCombat() or over[id] or unlocked then return 1 end
	return ns.Get("bars.fadeAlpha") or 0.3
end
function B.Fade(instant)
	for id, bar in pairs(B.bars) do
		local a = want(id, bar)
		if instant then ns.Anim.Set(bar, "alpha", a, function(v) bar:SetAlpha(v) end)
		else ns.Anim.Fade(bar, a, a >= 1 and 0.2 or 0.4) end
	end
end
B.Alpha = function(bar) return ns.Anim.Get(bar, "alpha") end

local watcher = CreateFrame("Frame")
watcher:Hide()
local since = 0
watcher:SetScript("OnUpdate", function(_, dt)
	since = since + (dt or 0)
	if since < 0.1 then return end
	since = 0
	local changed = false
	for id, bar in pairs(B.bars) do
		local o = bar:IsShown() and bar.IsMouseOver and bar:IsMouseOver() or false
		if o ~= (over[id] or false) then over[id] = o changed = true end
	end
	if changed then B.Fade() end
end)
function B.Watch() watcher:SetShown(ns.Get("bars.fade") and true or false) end

---------------------------------------------------------------------------

ns.On("READY", function() B.Build() end)
-- After the game's own hotkey update (it runs on the same event): a frame later.
ns.RegisterEvent("UPDATE_BINDINGS", function()
	if C_Timer and C_Timer.After then C_Timer.After(0, B.Bind) else B.Bind() end
end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() B.Fade() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if B.pending then B.pending = false B.Build() end
	B.Fade()
end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) ~= "string" then return end
	if path:find("^bars%.") and not path:find("Point$") then B.Build()
	elseif path == "*" then B.Build() end
end)
