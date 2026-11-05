-- The system tray and the bag buttons, uniform with the action bars: the
-- game's own micro buttons (character, spellbook, quests, social, map,
-- menu...) and bag buttons, moved into two Pathwise bars and drawn as the
-- same dark slots with a thin border and your accent on hover. The tray
-- buttons get Pathwise glyphs instead of their art.
--
-- They stay the game's buttons, so a click runs the game's own code (opening
-- the spellbook from addon code could stop it working in combat). The game
-- lays them out again now and then (MicroMenu:Layout, BagsBar:Layout, a
-- vehicle); those are followed with hooksecurefunc and the buttons put back.
-- Names from Forever's own files (Blizzard_MicroMenu Camelot, Blizzard_
-- MainMenuBarBagButtons): the ones missing on a client are skipped.

local ADDON, ns = ...
local T = ns.Theme
local Tray = {}
ns.Tray = Tray

ns.Defaults("tray", {
	enabled = true,
	micro = true, bags = true,
	size = 28, spacing = 3,
	microPoint = nil, bagsPoint = nil,
})
Tray.MICRO_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -180, 8 }
Tray.BAGS_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -8, 8 }

Tray.MICRO = {
	{ "CharacterMicroButton", "person" }, { "ProfessionMicroButton", "prof" }, { "SpellbookMicroButton", "book" },
	{ "TalentMicroButton", "tree" }, { "LegacyMicroButton", "diamond" }, { "QuestLogMicroButton", "quest" },
	{ "HousingMicroButton", "house" }, { "GuildMicroButton", "people" }, { "LFDMicroButton", "eye" },
	{ "CollectionsMicroButton", "grid" }, { "EJMicroButton", "dungeon" }, { "HelpMicroButton", "help" },
	{ "StoreMicroButton", "coin" }, { "MainMenuMicroButton", "menu" },
}

-- Each button's name and the key binding that opens the same window, for
-- its tooltip when the game doesn't show one of its own.
Tray.LABELS = {
	CharacterMicroButton = { "Character", "TOGGLECHARACTER0" }, ProfessionMicroButton = { "Professions", "TOGGLEPROFESSIONBOOK" },
	SpellbookMicroButton = { "Spellbook", "TOGGLESPELLBOOK" }, TalentMicroButton = { "Talents", "TOGGLETALENTS" },
	LegacyMicroButton = { "Legacy", nil }, QuestLogMicroButton = { "Quest log", "TOGGLEQUESTLOG" },
	HousingMicroButton = { "Housing", "TOGGLEHOUSINGDASHBOARD" }, GuildMicroButton = { "Social", "TOGGLESOCIAL" },
	LFDMicroButton = { "Group finder", "TOGGLEGROUPFINDER" }, CollectionsMicroButton = { "Collections", "TOGGLECOLLECTIONS" },
	EJMicroButton = { "Adventure guide", "TOGGLEENCOUNTERJOURNAL" }, HelpMicroButton = { "Help", nil },
	StoreMicroButton = { "Shop", nil }, MainMenuMicroButton = { "Game menu and settings", "TOGGLEGAMEMENU" },
	MainMenuBarBackpackButton = { "Backpack", "OPENALLBAGS" }, KeyRingButton = { "Key ring", "TOGGLEKEYRING" },
}

-- Our tooltip for a tray button: its name and key ("Spellbook  P"), unless
-- the game already showed its own (or the bag's contents) for it.
function Tray.Tooltip(b)
	if not GameTooltip then return false end
	if GameTooltip.IsShown and GameTooltip:IsShown() and GameTooltip.GetOwner and GameTooltip:GetOwner() == b then return false end
	local name = b.GetName and b:GetName()
	local l = name and Tray.LABELS[name]
	local label = l and l[1]
	if not label and name then
		local n = name:match("^CharacterBag(%d)Slot$")
		if n then label = "Bag " .. (tonumber(n) + 1) end
	end
	if not label then return false end
	GameTooltip:SetOwner(b, "ANCHOR_TOP")
	GameTooltip:SetText(label, 1, 1, 1)
	local key = l and l[2] and GetBindingKey and GetBindingKey(l[2])
	if key then
		local k = T.Color("text2")
		GameTooltip:AddLine((GetBindingText and GetBindingText(key)) or key, k[1], k[2], k[3])
	end
	GameTooltip:Show()
	return true
end

local function inCombat() return InCombatLockdown and InCombatLockdown() end

local bars = {} -- "micro" | "bags" -> frame
local dressed = setmetatable({}, { __mode = "k" }) -- button -> our textures

local function fade(region)
	if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
end

-- Hide the game's art on a button, every time the game puts it back.
local function fadeArt(b)
	for _, get in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
		if type(b[get]) == "function" then fade(b[get](b)) end
	end
	for _, key in ipairs({ "Portrait", "PortraitMask", "Background", "PushedBackground", "Shadow", "NormalTexture", "IconBorder", "SlotHighlightTexture", "BorderArt" }) do
		fade(b[key])
	end
	local hl = type(b.GetHighlightTexture) == "function" and b:GetHighlightTexture()
	local a = T.Color("accent")
	if type(hl) == "table" and hl.SetColorTexture then hl:SetColorTexture(a[1], a[2], a[3], 0.25) hl:SetAlpha(1) end
end

-- A slot ground, a thin border, and (tray buttons) a glyph.
function Tray.Dress(b, glyph)
	local d = dressed[b]
	if not d then
		d = {}
		d.ground = b:CreateTexture(nil, "BACKGROUND", nil, -8)
		d.ground:SetAllPoints()
		d.border = T.Border(b, "OVERLAY", 6)
		T.Etch(b)
		if glyph then
			d.glyph = b:CreateTexture(nil, "OVERLAY", nil, 5)
			d.glyph:SetTexture(T.MEDIA .. "glyph-" .. glyph)
			d.glyph:SetPoint("CENTER")
		end
		-- Item buttons (bags): the icon square inside the border.
		local icon = b.icon or b.Icon
		if type(icon) == "table" and icon.SetTexCoord then
			for _, m in ipairs({ b.SquareMask, b.CircleMask, b.IconMask }) do
				if type(m) == "table" and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, m) end
			end
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", 1, -1)
			icon:SetPoint("BOTTOMRIGHT", -1, 1)
		end
		if type(b.Count) == "table" and b.Count.SetFont then pcall(b.Count.SetFont, b.Count, T.FONTS.semibold, 11, "OUTLINE") end
		-- The game re-sets its art on some state changes: faded again after.
		if hooksecurefunc then
			for _, m in ipairs({ "SetNormalAtlas", "SetPushedAtlas", "SetDisabledAtlas", "SetNormalTexture", "SetPushedTexture" }) do
				if type(b[m]) == "function" then hooksecurefunc(b, m, function(self) fadeArt(self) end) end
			end
		end
		-- Hover: the glyph eases to full text color.
		local function look(p)
			local g = dressed[b] and dressed[b].glyph
			if not g then return end
			local enabled = not b.IsEnabled or b:IsEnabled()
			local r, gg, bl = ns.Anim.Mix(T.Color(enabled and "text2" or "muted"), T.Color("text"), p)
			g:SetVertexColor(r, gg, bl, enabled and 1 or 0.5)
		end
		d.look = look
		b:HookScript("OnEnter", function(self)
			ns.Anim.Hover(self, true, look)
			self.pwOurTip = Tray.Tooltip(self)
		end)
		b:HookScript("OnLeave", function(self)
			ns.Anim.Hover(self, false, look)
			if self.pwOurTip and GameTooltip then GameTooltip:Hide() end
			self.pwOurTip = nil
		end)
		dressed[b] = d
	end
	Tray.Paint(b)
end

function Tray.Paint(b)
	local d = dressed[b]
	if not d then return end
	local bg, br = T.Color("bg2"), T.Color("border")
	d.ground:SetColorTexture(bg[1], bg[2], bg[3], 0.9)
	d.border:SetColor(br[1], br[2], br[3], 1)
	if d.glyph then
		local size = math.floor((ns.Get("tray.size") or 28) * 0.6)
		d.glyph:SetSize(size, size)
		local enabled = not b.IsEnabled or b:IsEnabled()
		local c = T.Color(enabled and "text2" or "muted")
		d.glyph:SetVertexColor(c[1], c[2], c[3], enabled and 1 or 0.5)
	end
	fadeArt(b)
end

---------------------------------------------------------------------------
-- The two bars
---------------------------------------------------------------------------

local function bar(kind)
	if bars[kind] then return bars[kind] end
	local f = CreateFrame("Frame", "PathwiseUI_" .. (kind == "micro" and "Tray" or "BagBar"), nil)
	f:SetParent(UIParent)
	f:SetFrameStrata("LOW")
	f:SetMovable(true)
	f.kind = kind
	bars[kind] = f
	return f
end

-- The buttons of each bar, in order, as the client has them now.
function Tray.Buttons(kind)
	local out = {}
	if kind == "micro" then
		for _, m in ipairs(Tray.MICRO) do
			local b = _G[m[1]]
			if type(b) == "table" and b.SetParent then out[#out + 1] = { b, m[2] } end
		end
	else
		local M = MainMenuBarBagManager
		if M and M.EnumerateBagButtons then
			local ok, iter, st, init = pcall(M.EnumerateBagButtons, M)
			if ok and iter then for _, b in iter, st, init do if type(b) == "table" then out[#out + 1] = { b } end end end
		end
		if #out == 0 then
			for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }) do
				if type(_G[name]) == "table" then out[#out + 1] = { _G[name] } end
			end
		end
		if type(KeyRingButton) == "table" then out[#out + 1] = { KeyRingButton } end
	end
	return out
end

-- Lay a bar out: its buttons in a row (right to left from the corner),
-- the ones the game hides left out.
function Tray.LayoutBar(kind)
	if inCombat() then Tray.pending = true return end
	local f = bar(kind)
	local on = ns.Get("tray.enabled") and ns.Get("tray." .. kind)
	local size, gap = ns.Get("tray.size") or 28, ns.Get("tray.spacing") or 3
	local list = Tray.Buttons(kind)
	local n = 0
	for _, e in ipairs(list) do
		local b = e[1]
		if on then
			if b:GetParent() ~= f then b:SetParent(f) end
			Tray.Dress(b, e[2])
			-- The game decides which buttons a character has (its rules hide
			-- some): a button's own shown state says so, whatever its parent does.
			if b:IsShown() then
				b:ClearAllPoints()
				b:SetSize(size, size)
				b:SetPoint("TOPLEFT", f, "TOPLEFT", n * (size + gap), 0)
				n = n + 1
			end
		end
	end
	f:SetSize(math.max(1, n * (size + gap) - gap), size)
	local p = ns.Get("tray." .. kind .. "Point") or (kind == "micro" and Tray.MICRO_POINT or Tray.BAGS_POINT)
	f:ClearAllPoints()
	f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	f:SetShown(on and n > 0)
end

local hider, hidden = nil, {}
function Tray.HideGame()
	hider = hider or CreateFrame("Frame")
	hider:Hide()
	local names = {}
	if ns.Get("tray.micro") then names[#names + 1] = "MicroMenuContainer" end
	if ns.Get("tray.bags") then names[#names + 1] = "BagsBar" names[#names + 1] = "BagBarExpandToggle" end
	for _, name in ipairs(names) do
		local f = _G[name]
		if type(f) == "table" and not hidden[f] and f.SetParent then pcall(f.SetParent, f, hider) hidden[f] = true end
	end
end
function Tray.Hidden() return hidden end

function Tray.Build()
	if inCombat() then Tray.pending = true return end
	if not ns.Get("tray.enabled") then
		for _, f in pairs(bars) do f:Hide() end
		return
	end
	Tray.LayoutBar("micro")
	Tray.LayoutBar("bags")
	Tray.HideGame()
end

-- The game moving them back: ours again, right after.
local hooked = false
local busy = false
local function relayout()
	if busy then return end
	if inCombat() then Tray.pending = true return end
	if ns.Get("tray.enabled") then
		busy = true
		local ok, err = pcall(Tray.Build)
		busy = false
		if not ok then ns.Error("tray", err) end
	end
end
function Tray.Install()
	if hooked or not hooksecurefunc then return end
	hooked = true
	if type(MicroMenu) == "table" and type(MicroMenu.Layout) == "function" then hooksecurefunc(MicroMenu, "Layout", relayout) end
	if type(BagsBar) == "table" and type(BagsBar.Layout) == "function" then hooksecurefunc(BagsBar, "Layout", relayout) end
	for _, fn in ipairs({ "UpdateMicroButtonsParent", "MoveMicroButtons", "UpdateMicroButtons" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, relayout) end
	end
	-- A button the game shows or hides (its rules): the row again, if the
	-- tray itself is up (a hidden tray hides its buttons too: no relayout).
	for _, m in ipairs(Tray.MICRO) do
		local b = _G[m[1]]
		if type(b) == "table" and b.HookScript then
			local function changed() if bars.micro and bars.micro:IsShown() then relayout() end end
			b:HookScript("OnHide", changed)
			b:HookScript("OnShow", changed)
		end
	end
end

---------------------------------------------------------------------------
-- Moving them
---------------------------------------------------------------------------

local unlocked = false
local handles = {}
function Tray.Unlock(on)
	if inCombat() then ns.Print("the tray can be moved out of combat.") return false end
	unlocked = on and true or false
	for kind, f in pairs(bars) do
		local h = handles[f]
		if not h then
			h = ns.Movers.Handle(f, kind == "micro" and "TRAY" or "BAGS", function(p, rp, x, y)
				ns.Set("tray." .. kind .. "Point", { p, rp, x, y })
			end)
			handles[f] = h
		end
		h:Reveal(unlocked and f:IsShown())
	end
	ns.Movers.Active("tray", unlocked)
	return true
end
function Tray.Unlocked() return unlocked end
ns.Movers.Group("tray", function(on) if on or unlocked then Tray.Unlock(on) end end)
ns.On("MOVE_MODE", function(any) if not any and unlocked then Tray.Unlock(false) end end)
function Tray.ResetPositions()
	ns.Set("tray.microPoint", nil)
	ns.Set("tray.bagsPoint", nil)
end

ns.On("READY", function() Tray.Install() Tray.Build() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if Tray.pending then Tray.pending = false Tray.Build() end end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() for _, h in pairs(handles) do h:Hide() end unlocked = false end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^tray%.") or path == "*") then Tray.Build() end
end)
ns.On("ACCENT_CHANGED", function() for b in pairs(dressed) do Tray.Paint(b) end end)
