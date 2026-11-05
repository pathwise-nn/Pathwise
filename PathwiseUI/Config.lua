-- Pathwise UI's options window: categories on the left, the chosen one's
-- settings on the right as rows (label on the left, its control on the
-- right). Switches slide, choices glide, pages fade in, the list scrolls
-- smoothly, and the window fades in and out. /pwui, the minimap button, or
-- Pathwise's suite list opens it.

local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local C = {}
ns.Config = C

local W, H, NAV = 700, 540, 172
local PAD = 18
local HEAD = 52
local frame, nav, body, scroll
local current = "look"

---------------------------------------------------------------------------
-- What each category holds
---------------------------------------------------------------------------
-- Rows: { "heading", text }  { "text", text, color }
--       { "toggle", label, path, note }
--       { "choice", label, path, { { label, value }, ... }, note }
--       { "slider", label, path, min, max, step, "percent" | "count" }
--       { "input", key, hint, onApply(text), text }
--       { "button", label, onClick, kind }
--       { "color", label, name }            one of the theme's colors
--       { "accent" }                        your accent, on the wheel
--       { "schemes" }                       the color schemes, to pick one
--       { "bind", label, combo }            a click-casting box for one mouse combo
--       { "dropdown", label, path, { { label, value }, ... }, note }
--                                           (path may be { get = fn, set = fn } for
--                                           a value kept elsewhere, per character)

local function accentRows()
	local rows = {
		{ "heading", "Accent" },
		{ "choice", "Accent", "look.accentMode", { key = "accent", { "Pathwise", "pathwise" }, { "Class", "class" }, { "Custom", "custom" } },
			"Your class color follows each character: a mage blue, a rogue yellow." },
		{ "accent" },
		{ "heading", "Trim" },
		{ "dropdown", "Trim color", "look.trim", T.TRIMS,
			"The window title, section headings, the lines beside them and the window's top line. Class: your class color; Default: gold; Custom: any color." },
	}
	if ns.Get("look.trim") == "custom" then rows[#rows + 1] = { "color", "Your trim color", "flair" } end
	if ns.Suite() then
		rows[#rows + 1] = { "toggle", "Same color as Pathwise", "look.sharePathwise", "One accent for the guide, its suite and Pathwise UI." }
	end
	rows[#rows + 1] = { "heading", "Look" }
	rows[#rows + 1] = { "slider", "Background opacity", "look.opacity", 0.4, 1, 0.02, "percent" }
	rows[#rows + 1] = { "toggle", "Motion", "look.motion", "Hovers, switches, fades and scrolling ease into place. Off: everything changes at once." }
	rows[#rows + 1] = { "text", "Every other color is yours to change too: see Colors.", "muted" }
	return rows
end

local function colorRows()
	local rows = {
		{ "heading", "Schemes" },
		{ "text", "A whole set at once. Pick one, then change any color below to make it yours.", "muted" },
		{ "schemes" },
		{ "heading", "Accent" },
		{ "accent" },
	}
	for _, g in ipairs(T.COLOR_GROUPS) do
		rows[#rows + 1] = { "heading", g.name }
		for _, k in ipairs(g.keys) do rows[#rows + 1] = { "color", k[2], k[1] } end
	end
	rows[#rows + 1] = { "heading", "Share" }
	rows[#rows + 1] = { "input", "colors.code", "A scheme code: paste one from a friend and Apply, or show yours to copy.", function(text)
		if T.ImportColors(text) then ns.Print("colors applied.") C.exportText = nil return true end
		ns.Print("that is not a Pathwise UI scheme code.")
		return false
	end, C.exportText }
	rows[#rows + 1] = { "button", "Show my code", function() C.exportText = T.ExportColors() end }
	rows[#rows + 1] = { "button", "Back to the scheme's colors", function() ns.Set("look.colors", nil) end }
	rows[#rows + 1] = { "text", "Click a color to open the color wheel; right-click puts the scheme's back.", "muted" }
	return rows
end

C.CATEGORIES = {
	{ key = "look", name = "Look and accent", rows = accentRows },
	{ key = "colors", name = "Colors", rows = colorRows },
	{ key = "units", name = "Unit frames", rows = function()
		local U = ns.Units
		return {
			{ "heading", "Unit frames" },
			{ "toggle", "Pathwise unit frames", "units.enabled", "You, your target and the rest in the Pathwise look. Click: target; right-click: the menu." },
			{ "toggle", "You", "units.player" },
			{ "toggle", "Your target", "units.target" },
			{ "toggle", "Your target's target", "units.targettarget" },
			{ "toggle", "Your pet", "units.pet" },
			{ "toggle", "Your focus", "units.focus" },
			{ "toggle", "Your party", "units.party" },
			{ "heading", "What they show" },
			{ "choice", "Health text", "units.healthText", { key = "ht", { "Current", "current" }, { "Both", "both" }, { "Percent", "percent" }, { "None", "none" } },
				"Percent is not yet checked on Forever; Current always works." },
			{ "choice", "Health color", "units.healthColor", { key = "hc", { "Class", "class" }, { "Accent", "accent" }, { "Dark", "dark" } },
				"Class: players by class, others red, yellow or green by how they see you." },
			{ "toggle", "Outlined text", "units.outline", "Names and numbers on the bars get a black outline so they read on any color. Off: a soft shadow." },
			{ "toggle", "Smooth bars", "units.smooth", "Health and power glide to their new value instead of jumping." },
			{ "toggle", "Power numbers", "units.powerText" },
			{ "toggle", "Debuffs on your target and party", "units.auras" },
			{ "toggle", "Only your own debuffs", "units.onlyMyDebuffs" },
			{ "toggle", "Cast bars", "units.castbars" },
			{ "toggle", "Portraits", "units.portraits" },
			{ "heading", "Size and place" },
			{ "slider", "Your width", "units.PlayerW", 140, 360, 2, "count" },
			{ "slider", "Your height", "units.PlayerH", 24, 80, 1, "count" },
			{ "slider", "Target width", "units.TargetW", 140, 360, 2, "count" },
			{ "slider", "Target height", "units.TargetH", 24, 80, 1, "count" },
			{ "button", U.Unlocked() and "Lock the frames" or "Move the frames", function() U.Unlock(not U.Unlocked()) end, U.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() U.ResetPositions() end },
			{ "toggle", "Hide the game's unit frames", "units.hideBlizzard", "Off brings them back after a reload." },
		}
	end },
	{ key = "bars", name = "Action bars", rows = function()
		local B = ns.Bars
		local per = { key = "per", { "12", 12 }, { "6", 6 }, { "4", 4 }, { "3", 3 }, { "2", 2 }, { "1", 1 } }
		local rows = {
			{ "heading", "Action bars" },
			{ "toggle", "Pathwise action bars", "bars.enabled", "The game's own buttons (your spells stay where they are), in the Pathwise look. Your keys keep working." },
		}
		for _, def in ipairs(B.DEFS) do rows[#rows + 1] = { "toggle", def.label, "bars." .. def.name } end
		rows[#rows + 1] = { "heading", "Buttons per row" }
		for _, def in ipairs(B.DEFS) do rows[#rows + 1] = { "choice", def.label, "bars." .. def.name .. "Per", per } end
		for _, r in ipairs({
			{ "heading", "Look" },
			{ "slider", "Button size", "bars.size", 24, 52, 1, "count" },
			{ "slider", "Space between", "bars.spacing", 0, 10, 1, "count" },
			{ "toggle", "Key names", "bars.hotkeys" },
			{ "toggle", "Macro names", "bars.macroNames" },
			{ "toggle", "Empty slots", "bars.emptySlots", "Off: an empty slot only shows while you drag a spell." },
			{ "toggle", "Soft out of combat", "bars.fade", "Bars fade out of combat; back in combat or under the mouse." },
			{ "slider", "How soft", "bars.fadeAlpha", 0, 0.9, 0.05, "percent" },
			{ "heading", "Place" },
			{ "button", B.Unlocked() and "Lock the bars" or "Move the bars", function() B.Unlock(not B.Unlocked()) end, B.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() B.ResetPositions() end },
			{ "toggle", "Hide the game's action bars", "bars.hideBlizzard", "Off brings them back after a reload. The stance and pet bars stay the game's for now (move them in Edit Mode)." },
		}) do rows[#rows + 1] = r end
		return rows
	end },
	{ key = "bottom", name = "Tray, money, XP", rows = function()
		local Tr = ns.Tray
		return {
			{ "heading", "Money" },
			{ "toggle", "Money always shown", "money.enabled", "Your gold, silver and copper above the bags. Hover: this session's change and your other characters; click: your bags." },
			{ "choice", "Show", "money.style", { key = "ms", { "All coins", "full" }, { "Gold only", "gold" }, { "Short", "short" } },
				"Short: 12.3k g once you have a thousand gold or more." },
			{ "toggle", "This session in the tooltip", "money.session" },
			{ "toggle", "Your other characters in the tooltip", "money.characters", "Characters on this realm, from the last time each logged in. /pwui forget Name drops one." },
			{ "button", "Put it back where it was", function() ns.Money.ResetPosition() end },
			{ "heading", "Experience bar" },
			{ "toggle", "Pathwise experience bar", "xp.enabled", "A thin bar in your color under the main bar, rested experience ahead of it; your watched reputation at the level cap." },
			{ "toggle", "Numbers always shown", "xp.text", "Off: the numbers fade in when the mouse is over it." },
			{ "slider", "Height", "xp.height", 4, 20, 1, "count" },
			{ "toggle", "As wide as the main bar", "xp.matchBar", "And right under it, wherever you move it." },
			{ "toggle", "Hide the game's experience bar", "xp.hideBlizzard", "Off brings it back after a reload." },
			{ "heading", "System tray and bags" },
			{ "toggle", "Pathwise tray", "tray.enabled", "The game's own character, spellbook, quest, social, map and menu buttons, and your bags, as slots like the action bars." },
			{ "toggle", "Tray buttons", "tray.micro" },
			{ "toggle", "Bag buttons", "tray.bags" },
			{ "slider", "Button size", "tray.size", 20, 40, 1, "count" },
			{ "slider", "Space between", "tray.spacing", 0, 8, 1, "count" },
			{ "button", Tr.Unlocked() and "Lock the tray" or "Move the tray and bags", function() Tr.Unlock(not Tr.Unlocked()) end, Tr.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() Tr.ResetPositions() end },
			{ "text", "Turning the tray off brings the game's own back after a reload.", "muted" },
		}
	end },
	{ key = "fonts", name = "Fonts", rows = function() return {
		{ "heading", "Fonts" },
		{ "toggle", "Pathwise font everywhere", "fonts.pathwise", "Inter for every text of the game: menus, chat, tooltips, quests. Off puts the game's own back." },
		{ "slider", "Text size", "fonts.scale", 0.8, 1.3, 0.05, "percent" },
		{ "text", "Names over heads and chat bubbles take the new font after a reload.", "muted" },
		{ "button", "Reload now", function() if ReloadUI then ReloadUI() end end },
	} end },
	{ key = "tooltips", name = "Tooltips", rows = function() return {
		{ "heading", "Tooltips" },
		{ "toggle", "Pathwise look", "tooltip.skin", "A flat ground and a thin border instead of the ornate frame." },
		{ "choice", "Border", "tooltip.border", { key = "tb", { "Quality", "quality" }, { "Accent", "accent" }, { "Plain", "plain" } },
			"Quality: an item's quality color, a player's class color." },
		{ "toggle", "Player names in class color", "tooltip.classNames" },
		{ "toggle", "Health bar in class color", "tooltip.healthClass" },
		{ "toggle", "At the mouse", "tooltip.cursor", "Tooltips for the world follow your pointer instead of the corner." },
	} end },
	{ key = "windows", name = "Game windows", rows = function() return {
		{ "heading", "Game windows" },
		{ "toggle", "Pathwise look", "windows.skin", "Character, spellbook, vendor, mail, quests and more: a flat ground, a thin border and your accent along the top." },
		{ "toggle", "Accent line along the top", "windows.accentLine" },
		{ "toggle", "Round portraits", "windows.portraits" },
		{ "text", "Only windows on the game's modern frame are dressed; others keep their look. Not yet checked on Forever: tell us what looks wrong.", "muted" },
	} end },
	{ key = "heal", name = "Healing", rows = function()
		local H = ns.Heal
		local rows = {
			{ "heading", "Healing frames" },
			{ "toggle", "Healing frames", "heal.enabled", "Your party or raid as bars built for healing: click someone to heal them, see heals on the way, debuffs you can cleanse, your HoTs, aggro and range. Off by default; healers are asked once." },
		}
		if not ns.Get("heal.enabled") then
			rows[#rows + 1] = { "text", "Turn them on to set them up: how they look, and what each click casts.", "muted" }
			return rows
		end
		for _, r in ipairs({
			{ "toggle", "Show when you're on your own", "heal.solo", "Your own frame when you're not in a group." },
			{ "heading", "What they show" },
			{ "choice", "Health color", "heal.color", { key = "hcol", { "Class", "class" }, { "Green", "green" }, { "By health", "health" } },
				"By health: green, turning yellow then red as it drops." },
			{ "choice", "Health text", "heal.text", { key = "htxt", { "Missing", "deficit" }, { "Percent", "percent" }, { "None", "none" } },
				"Missing: how much they need (-1.2k), blank when full." },
			{ "toggle", "Heals on the way", "heal.incoming", "A lighter bar past their health: heals being cast on them." },
			{ "toggle", "Debuffs you can cleanse", "heal.dispel", "Drawn by the game in each frame, in combat too; out of combat the frame's edge also takes the debuff's color." },
			{ "toggle", "Your HoTs", "heal.hots", "Your heals over time and shields, top right. Forever hides auras from addons in a fight, so these show between fights." },
			{ "toggle", "Aggro", "heal.aggro", "A red edge around whoever the enemy is hitting, when the game says so." },
			{ "toggle", "Mana bars", "heal.mana" },
			{ "toggle", "Fade when out of range", "heal.range" },
			{ "slider", "How faded", "heal.rangeAlpha", 0.1, 0.9, 0.05, "percent" },
			{ "heading", "Size and place" },
			{ "slider", "Width", "heal.width", 50, 160, 2, "count" },
			{ "slider", "Height", "heal.height", 24, 80, 1, "count" },
			{ "slider", "Space between", "heal.spacing", 0, 10, 1, "count" },
			{ "choice", "Groups", "heal.grow", { key = "hgrow", { "In columns", "down" }, { "In rows", "right" } } },
			{ "button", H.Unlocked() and "Lock it" or "Move the healing frames", function() H.Unlock(not H.Unlocked()) end, H.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() H.ResetPosition() end },
			{ "toggle", "Hide the game's party and raid frames", "heal.hideGame", "Off brings them back after a reload." },
			{ "toggle", "Hide Pathwise party frames", "heal.hideParty", "These show your party already." },
			{ "heading", "Click-casting" },
		}) do rows[#rows + 1] = r end
		local C = ns.HealClicks
		local spec, how = C.Spec()
		local options = { { "Follow my talents", "auto" } }
		for _, s in ipairs(C.Specs()) do options[#options + 1] = { s.label, s.key } end
		rows[#rows + 1] = { "dropdown", "Spec", { get = function() return how == "chosen" and spec.key or "auto" end, set = C.SetSpec }, options,
			("Your clicks follow the %s preset%s. Its spells fill in as you learn them; a click you set yourself is never changed."):format(spec.label,
				how == "auto" and " (from your talents)" or "") }
		local talents = {}
		for _, list in pairs(spec.binds) do
			for _, name in ipairs(list) do
				if C.NOTES[name] then talents[#talents + 1] = ("%s: %s"):format(name, C.NOTES[name]) end
			end
		end
		table.sort(talents)
		if #talents > 0 then
			rows[#rows + 1] = { "text", table.concat(talents, ". ") .. ". Forever's new spells are named from its previews and not yet checked in game: a name the game doesn't know is skipped.", "muted" }
		end
		rows[#rows + 1] = { "text", "What each click on a frame does. Type a spell's name (your highest rank is cast), target or menu, then Enter; or drag a spell from your spellbook onto a box. Empty does nothing.", "muted" }
		for _, c in ipairs(C.COMBOS) do rows[#rows + 1] = { "bind", c[2], c[1] } end
		rows[#rows + 1] = { "button", ("Use the %s preset (replaces your own clicks)"):format(spec.label), function() C.Defaults(true) end }
		return rows
	end },
	{ key = "profile", name = "Profile", rows = function() return {
		{ "heading", "Profile" },
		{ "toggle", "Same settings on every character", "profile.shared", "Off: this character keeps its own (it starts from the shared ones)." },
		{ "toggle", "Minimap button", "minimap.shown", "Without it, type /pwui." },
		{ "button", "Back to the defaults", function() ns.Reset() ns.Print("settings back to the defaults.") end },
	} end },
	{ key = "next", name = "Coming next", rows = function() return {
		{ "heading", "Coming next" },
		{ "text", "Pathwise UI grows in stages, each one usable on its own:" },
		{ "text", "4  Nameplates" },
		{ "text", "5  Chat" },
		{ "text", "6  Minimap" },
		{ "text", "7  Data bars: gold, durability, latency, more (the experience bar and tray are in already)" },
	} end },
}

---------------------------------------------------------------------------
-- Drawing the rows (pooled: a page reuses the widgets the last one left)
---------------------------------------------------------------------------

local pool, used = {}, {}
local function take(kind, make)
	pool[kind] = pool[kind] or {}
	used[kind] = (used[kind] or 0) + 1
	local w = pool[kind][used[kind]]
	if not w then w = make() pool[kind][used[kind]] = w end
	w:Show()
	return w
end

-- A row: a label on the left, a note under it, its control on the right,
-- a faint ground on hover and a divider under it.
local function makeRow(withControl)
	local f = CreateFrame("Frame", nil, body)
	f:EnableMouse(true)
	local hover = f:CreateTexture(nil, "BACKGROUND")
	hover:SetPoint("TOPLEFT", -8, 0)
	hover:SetPoint("BOTTOMRIGHT", 8, 0)
	T.Paint(hover, "hover", 0)
	local function look(p) local c = T.Color("hover") hover:SetColorTexture(c[1], c[2], c[3], 0.45 * p) end
	f:SetScript("OnEnter", function(self) A.Hover(self, true, look) end)
	f:SetScript("OnLeave", function(self) if not (self.IsMouseOver and self:IsMouseOver()) then A.Hover(self, false, look) end end)
	local line = f:CreateTexture(nil, "BORDER")
	line:SetPoint("BOTTOMLEFT")
	line:SetPoint("BOTTOMRIGHT")
	line:SetHeight(1)
	T.NoSnap(line)
	T.Paint(line, "divider")
	f.label = T.Text(f, "body", "text")
	f.label:SetPoint("TOPLEFT", 0, -10)
	f.note = T.Text(f, "small", "muted")
	f.note:SetWordWrap(true)
	f.note:SetPoint("TOPLEFT", 0, -28)
	if withControl then f.control = withControl(f) end
	return f
end

local makers = {}
-- A heading: serif, in the trim color, with a rule beside it fading out.
function makers.heading()
	local f = CreateFrame("Frame", nil, body)
	f.text = T.Text(f, "heading", "flair")
	f.text:SetPoint("BOTTOMLEFT", 0, 6)
	f.rule = f:CreateTexture(nil, "ARTWORK")
	f.rule:SetPoint("LEFT", f.text, "RIGHT", 10, 0)
	f.rule:SetPoint("RIGHT", f, "RIGHT")
	f.rule:SetHeight(1)
	T.NoSnap(f.rule)
	T.FadeRule(f.rule)
	return f
end
function makers.text() local f = T.Text(body, "body", "text") f:SetWordWrap(true) return f end
function makers.toggle()
	return makeRow(function(f)
		local s = T.Switch(f)
		s:SetPoint("TOPRIGHT", 0, -10)
		return s
	end)
end
function makers.choice()
	return makeRow(function(f)
		local g = T.Segmented(f)
		g:SetPoint("TOPRIGHT", 0, -6)
		return g
	end)
end
function makers.dropdown()
	return makeRow(function(f)
		local d = T.Dropdown(f, 150)
		d:SetPoint("TOPRIGHT", 0, -6)
		return d
	end)
end
function makers.color()
	local f = makeRow()
	f.hex = T.Text(f, "meta", "text2")
	f.hex:SetJustifyH("RIGHT")
	f.own = T.Text(f, "small", "accent")
	f.own:SetJustifyH("RIGHT")
	return f
end
function makers.slider()
	local f = makeRow()
	f.value = T.Text(f, "meta", "text2")
	f.value:SetPoint("TOPRIGHT", 0, -10)
	f.value:SetJustifyH("RIGHT")
	f.sliders = {}
	return f
end
function makers.input()
	local f = CreateFrame("Frame", nil, body)
	f.hint = T.Text(f, "meta", "text2")
	f.hint:SetPoint("TOPLEFT")
	f.hint:SetWordWrap(true)
	local e = CreateFrame("EditBox", nil, f)
	e:SetAutoFocus(false)
	e:SetSize(220, 26)
	T.Panel(e, "bg2")
	T.Font(e, "body")
	e:SetTextInsets(8, 8, 0, 0)
	e:SetScript("OnEditFocusGained", function(self) T.SetBorder(self, "accent") if self.HighlightText then self:HighlightText() end end)
	e:SetScript("OnEditFocusLost", function(self) T.SetBorder(self, "border") end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.box = e
	f.apply = T.Button(f, "Apply", "accent")
	f.apply:SetPoint("LEFT", e, "RIGHT", 8, 0)
	e:SetScript("OnEnterPressed", function() f.apply:Click() end)
	return f
end
function makers.button() return T.Button(body, "", "default") end
function makers.bind()
	local f = makeRow()
	local e = CreateFrame("EditBox", nil, f)
	e:SetAutoFocus(false)
	e:SetSize(190, 24)
	e:SetPoint("TOPRIGHT", 0, -7)
	T.Panel(e, "bg2")
	T.Font(e, "body")
	e:SetTextInsets(8, 8, 0, 0)
	local function commit(self)
		if f.pwCombo then ns.HealClicks.Set(f.pwCombo, ns.HealClicks.Parse(self:GetText())) end
		self:ClearFocus()
	end
	e:SetScript("OnEnterPressed", commit)
	e:SetScript("OnEscapePressed", function(self) self:SetText(ns.HealClicks.Label(ns.HealClicks.Get(f.pwCombo))) self:ClearFocus() end)
	e:SetScript("OnEditFocusGained", function(self) T.SetBorder(self, "accent") if self.HighlightText then self:HighlightText() end end)
	e:SetScript("OnEditFocusLost", function(self) T.SetBorder(self, "border") end)
	-- A spell dragged from the spellbook and dropped on the box.
	local function drop(self)
		local name = ns.HealClicks.FromCursor()
		if name and f.pwCombo then ns.HealClicks.Set(f.pwCombo, name) end
	end
	e:SetScript("OnReceiveDrag", drop)
	e:SetScript("OnMouseUp", function(self) if GetCursorInfo and GetCursorInfo() == "spell" then drop(self) end end)
	f.box = e
	return f
end
function makers.schemes()
	local f = CreateFrame("Frame", nil, body)
	f.cards = {}
	return f
end

-- A scheme card: its ground, a strip of its main colors, its name.
local function schemeCard(f, i, s, picked)
	local b = f.cards[i]
	if not b then
		b = CreateFrame("Button", nil, f)
		b:SetSize(96, 58)
		b.ground = b:CreateTexture(nil, "BACKGROUND")
		b.ground:SetAllPoints()
		b.border = T.Border(b, "BORDER")
		b.strip = {}
		for j = 1, 4 do
			local t = b:CreateTexture(nil, "ARTWORK")
			t:SetSize(18, 6)
			t:SetPoint("TOPLEFT", 8 + (j - 1) * 20, -10)
			b.strip[j] = t
		end
		b.pwText = T.Text(b, "button", "text")
		b.pwText:SetPoint("BOTTOMLEFT", 8, 9)
		b:SetScript("OnEnter", function(self) if not self.pwPicked then self.border:SetColor(self.pwHover[1], self.pwHover[2], self.pwHover[3], 1) end end)
		b:SetScript("OnLeave", function(self) self:Paint() end)
		function b:Paint()
			local c = self.pwColors
			if self.pwPicked then T.Paint(self.border, "accent") else self.border:SetColor(c.border[1], c.border[2], c.border[3], 1) end
		end
		f.cards[i] = b
	end
	local hex = T.Hex
	b.pwColors = { border = hex(s.colors.border) }
	b.pwHover = hex(s.colors.text2)
	b.pwPicked = picked
	local g = hex(s.colors.bg)
	b.ground:SetColorTexture(g[1], g[2], g[3], 1)
	for j, k in ipairs({ "accent", "text", "bg2", "success" }) do
		local c = hex(s.colors[k])
		b.strip[j]:SetColorTexture(c[1], c[2], c[3], 1)
	end
	b.pwText:SetText(s.name)
	local tc = hex(s.colors.text)
	b.pwText:SetTextColor(tc[1], tc[2], tc[3], 1)
	b:SetScript("OnClick", function() T.UseScheme(s.key) end)
	b:Paint()
	b:Show()
	return b
end

local lastPaths = {} -- a pooled control -> the setting it showed last time (to animate only real changes)

function C.Render()
	if not body then return end
	for _, list in pairs(pool) do for _, w in ipairs(list) do w:Hide() end end
	used = {}
	local cat
	for _, c in ipairs(C.CATEGORIES) do if c.key == current then cat = c end end
	cat = cat or C.CATEGORIES[1]
	local inner = W - NAV - PAD * 2 - 14
	body:SetWidth(inner)
	local y = 0
	local function place(w, h, gap)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + (gap or 0)))
		w:SetWidth(inner)
		y = y + (gap or 0) + h
	end
	local function noteHeight(f, note, right)
		f.note:SetText(note or "")
		f.note:SetWidth(inner - (right or 0))
		f.label:SetWidth(inner - (right or 0) - 8)
		return note and note ~= "" and ((f.note:GetStringHeight() or 12) + 6) or 0
	end
	for i, r in ipairs(cat.rows()) do
		local kind = r[1]
		if kind == "heading" then
			local f = take("heading", makers.heading)
			f.text:SetText(r[2])
			f:SetHeight(32)
			place(f, 32, i == 1 and 0 or 12)
		elseif kind == "text" then
			local fs = take("text", makers.text)
			fs:SetWidth(inner)
			fs:SetText(r[2])
			T.TextColor(fs, r[3] or "text")
			place(fs, (fs:GetStringHeight() or 14), 8)
		elseif kind == "toggle" then
			local f = take("toggle", makers.toggle)
			local path = r[3]
			f.label:SetText(r[2])
			local sw = f.control
			sw:SetOn(ns.Get(path) and true or false, lastPaths[sw] == path)
			lastPaths[sw] = path
			sw.pwOnToggle = function(on) if path == "profile.shared" then ns.SetShared(on) else ns.Set(path, on) end end
			local h = 38 + noteHeight(f, r[4], 50)
			f:SetHeight(h)
			place(f, h)
		elseif kind == "choice" then
			local f = take("choice", makers.choice)
			local path = r[3]
			f.label:SetText(r[2])
			local g = f.control
			g:SetOptions(r[4], ns.Get(path))
			lastPaths[g] = path
			g.pwOnPick = function(v) ns.Set(path, v) end
			local wide = (g:GetWidth() or 0) > inner * 0.55
			local h
			if wide then
				-- Too wide beside its label: under it.
				g:ClearAllPoints()
				g:SetPoint("TOPLEFT", 0, -32)
				h = 66 + noteHeight(f, r[5], 0)
				f.note:ClearAllPoints()
				f.note:SetPoint("TOPLEFT", 0, -64)
			else
				g:ClearAllPoints()
				g:SetPoint("TOPRIGHT", 0, -6)
				f.note:ClearAllPoints()
				f.note:SetPoint("TOPLEFT", 0, -28)
				h = 38 + noteHeight(f, r[5], (g:GetWidth() or 0) + 12)
			end
			f:SetHeight(h)
			place(f, h)
		elseif kind == "dropdown" then
			local f = take("dropdown", makers.dropdown)
			local path = r[3]
			local get = type(path) == "table" and path.get or function() return ns.Get(path) end
			local set = type(path) == "table" and path.set or function(v) ns.Set(path, v) end
			f.label:SetText(r[2])
			local now = get()
			local known = false
			for _, o in ipairs(r[4]) do if o[2] == now then known = true end end
			-- A value no longer offered (an older setting) shows as the second choice: Default.
			f.control:SetOptions(r[4], known and now or (r[4][2] or r[4][1])[2])
			f.control.pwOnPick = function(v) set(v) end
			f.note:ClearAllPoints()
			f.note:SetPoint("TOPLEFT", 0, -28)
			local h = 38 + noteHeight(f, r[5], 162)
			f:SetHeight(h)
			place(f, h)
		elseif kind == "slider" then
			local f = take("slider", makers.slider)
			local path, lo, hi, step, unit = r[3], r[4], r[5], r[6], r[7]
			f.label:SetText(r[2])
			f.note:SetText("")
			for _, s in pairs(f.sliders) do s:Hide() end
			local function show(v) f.value:SetText(unit == "percent" and ("%d%%"):format(v * 100 + 0.5) or tostring(v)) end
			local s = f.sliders[path]
			if not s then
				s = T.Slider(f, inner, lo, hi, step, function(v) ns.Set(path, v) show(v) end)
				s:SetPoint("TOPLEFT", 0, -32)
				f.sliders[path] = s
			end
			s:Show()
			s:SetQuietly(ns.Get(path) or lo)
			show(ns.Get(path) or lo)
			f:SetHeight(60)
			place(f, 60)
		elseif kind == "color" or kind == "accent" then
			local f = take("color", makers.color)
			local name = r[3]
			local isAccent = kind == "accent"
			f.label:SetText(isAccent and "Your accent" or r[2])
			local sw = f.swatch
			if not sw then
				sw = T.Swatch(f, function() return T.Color(f.pwName) end, function(h) f.pwSet(h) end, function() f.pwReset() end)
				sw:SetPoint("TOPRIGHT", 0, -9)
				f.swatch = sw
			end
			f.pwName = isAccent and "accent" or name
			if isAccent then
				f.pwSet = function(h) ns.Set("look.accentColor", h) ns.Set("look.accentMode", "custom") end
				f.pwReset = function() ns.Set("look.accentMode", "pathwise") end
				sw.pwSnapshot = function()
					local mode, color = ns.Get("look.accentMode"), ns.Get("look.accentColor")
					return function() ns.Set("look.accentColor", color) ns.Set("look.accentMode", mode) end
				end
			elseif name == "flair" then
				-- The trim: picking a color makes it Custom; right-click: back to gold.
				sw.pwSnapshot = function()
					local trim, own = ns.Get("look.trim"), ns.Get("look.colors")
					own = type(own) == "table" and own.flair or nil
					return function() T.SetColor("flair", own) ns.Set("look.trim", trim) end
				end
				f.pwSet = function(h) T.SetColor("flair", h) ns.Set("look.trim", "custom") end
				f.pwReset = function() T.SetColor("flair", nil) ns.Set("look.trim", "default") end
			else
				sw.pwSnapshot = nil
				f.pwSet = function(h) T.SetColor(name, h) end
				f.pwReset = function() T.SetColor(name, nil) end
			end
			sw:Refresh()
			f.hex:ClearAllPoints()
			f.hex:SetPoint("RIGHT", sw, "LEFT", -10, 0)
			f.hex:SetText(T.ToHex(T.Color(f.pwName)))
			f.own:ClearAllPoints()
			f.own:SetPoint("RIGHT", f.hex, "LEFT", -10, 0)
			local own = isAccent and ns.Get("look.accentMode") ~= "pathwise" or (not isAccent and T.IsOwnColor(name))
			f.own:SetText(own and (isAccent and (ns.Get("look.accentMode") == "class" and "CLASS" or "YOURS") or "YOURS") or "")
			local h = 38 + noteHeight(f, isAccent and "Click to pick any color on the wheel; right-click for Pathwise blue." or nil, 120)
			f:SetHeight(h)
			place(f, h)
		elseif kind == "schemes" then
			local f = take("schemes", makers.schemes)
			for _, b in ipairs(f.cards) do b:Hide() end
			local per = math.max(1, math.floor((inner + 8) / 104))
			local now = ns.Get("look.scheme")
			for j, s in ipairs(T.SCHEMES) do
				local b = schemeCard(f, j, s, s.key == now and not ns.Get("look.colors"))
				b:ClearAllPoints()
				b:SetPoint("TOPLEFT", f, "TOPLEFT", ((j - 1) % per) * 104, -math.floor((j - 1) / per) * 66)
			end
			local h = math.ceil(#T.SCHEMES / per) * 66
			f:SetHeight(h)
			place(f, h, 6)
		elseif kind == "input" then
			local f = take("input", makers.input)
			f.hint:SetWidth(inner)
			f.hint:SetText(r[3] or "")
			local hintH = f.hint:GetStringHeight() or 14
			f.box:ClearAllPoints()
			f.box:SetPoint("TOPLEFT", 0, -(hintH + 8))
			f.box:SetText(r[5] or "")
			f.apply:SetScript("OnClick", function()
				if r[4](f.box:GetText()) then f.box:SetText("") f.box:ClearFocus() C.Render() end
			end)
			local h = hintH + 8 + 26
			f:SetHeight(h)
			place(f, h, 10)
		elseif kind == "bind" then
			local f = take("bind", makers.bind)
			f.label:SetText(r[2])
			f.pwCombo = r[3]
			local v = ns.HealClicks.Get(r[3])
			if not (f.box.HasFocus and f.box:HasFocus()) then f.box:SetText(ns.HealClicks.Label(v)) end
			T.Paint(f.box, (v == nil) and "muted" or "text")
			f:SetHeight(38)
			place(f, 38)
		elseif kind == "button" then
			local b = take("button", makers.button)
			b.pwText:SetText(r[2])
			b:SetKind(r[4] or "default")
			b:Fit()
			b:SetScript("OnClick", function() r[3]() C.Render() end)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -(y + 12))
			y = y + 12 + 26
		end
	end
	-- Taller than the window: it scrolls.
	body:SetHeight(math.max(1, y + 16))
	if scroll then
		local max = scroll:Range()
		if (scroll:GetVerticalScroll() or 0) > max then scroll:ScrollTo(max, true) end
		scroll.PlaceThumb()
	end
	C.PaintNav(false)
end

---------------------------------------------------------------------------
-- The nav: the chosen category is a tab joined to the page: it takes the
-- page's ground, the line between nav and page opens there, and its label
-- is brighter and bolder
---------------------------------------------------------------------------

function C.PaintNav(animate)
	if not nav then return end
	local at
	for i, b in ipairs(nav.items) do
		local on = b.key == current
		b.pwOn = on
		b.look(A.Get(b, "hover") or 0)
		if on then at = i end
	end
	if not at then return end
	local top = 10 + (at - 1) * 32
	nav.pick:ClearAllPoints()
	nav.pick:SetPoint("TOPLEFT", nav, "TOPLEFT", 0, -top)
	nav.pick:SetPoint("TOPRIGHT", nav, "TOPRIGHT", 0, -top)
	-- Above the tab and below it: the nav's ground and its edge.
	local above, below = nav.parts[1], nav.parts[2]
	for _, part in ipairs(nav.parts) do part.ground:ClearAllPoints() part.edge:ClearAllPoints() end
	above.ground:SetPoint("TOPLEFT", nav, "TOPLEFT")
	above.ground:SetPoint("BOTTOMRIGHT", nav.pick, "TOPRIGHT")
	above.edge:SetPoint("TOPRIGHT", nav, "TOPRIGHT")
	above.edge:SetPoint("BOTTOMRIGHT", nav.pick, "TOPRIGHT")
	below.ground:SetPoint("TOPLEFT", nav.pick, "BOTTOMLEFT")
	below.ground:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT")
	below.edge:SetPoint("TOPRIGHT", nav.pick, "BOTTOMRIGHT")
	below.edge:SetPoint("BOTTOMRIGHT", nav, "BOTTOMRIGHT")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local function build()
	if frame then return frame end
	frame = CreateFrame("Frame", "PathwiseUIConfig", nil)
	frame:SetParent(UIParent)
	frame:SetSize(W, H)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	T.Panel(frame)
	T.TrimLine(frame)
	if UISpecialFrames then table.insert(UISpecialFrames, "PathwiseUIConfig") end

	local icon = frame:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(T.MEDIA .. "icon")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", PAD, -16)
	local function tint() local a = T.Color("accent") icon:SetVertexColor(a[1], a[2], a[3]) end
	tint()
	ns.On("ACCENT_CHANGED", tint)
	local title = T.Text(frame, "wtitle", "flair")
	title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
	title:SetJustifyV("MIDDLE")
	title:SetText("Pathwise UI")
	local version = T.Text(frame, "small", "muted")
	version:SetPoint("LEFT", title, "RIGHT", 10, -1)
	version:SetJustifyV("MIDDLE")
	version:SetText(ns.VERSION .. "  ·  leight_nn & florp   _nn")
	local close = T.IconButton(frame, "close", "Close", function() C.Hide() end)
	close:SetPoint("TOPRIGHT", -10, -12)
	local move = T.Button(frame, "Move everything", "default", function()
		local on = not (ns.Movers and ns.Movers.IsActive())
		if ns.Movers then ns.Movers.All(on) end
		if on then C.Hide() end
	end)
	move:SetPoint("RIGHT", close, "LEFT", -8, 0)
	frame.pwMove = move
	local headLine = frame:CreateTexture(nil, "BORDER")
	headLine:SetPoint("TOPLEFT", 1, -HEAD)
	headLine:SetPoint("TOPRIGHT", -1, -HEAD)
	headLine:SetHeight(1)
	T.NoSnap(headLine)
	T.Paint(headLine, "divider")

	-- The nav.
	nav = CreateFrame("Frame", nil, frame)
	nav:SetPoint("TOPLEFT", 1, -HEAD - 1)
	nav:SetPoint("BOTTOMLEFT", 1, 1)
	nav:SetWidth(NAV)
	-- The nav's ground and its edge against the page are drawn in two
	-- parts, above and below the selected tab, leaving a gap there: the
	-- window's own ground shows through, so the tab is the page itself.
	nav.parts = {}
	for i = 1, 2 do
		local g = nav:CreateTexture(nil, "BACKGROUND")
		T.Paint(g, "bg2")
		local e = nav:CreateTexture(nil, "BORDER")
		e:SetWidth(1)
		T.NoSnap(e)
		T.Paint(e, "border")
		nav.parts[i] = { ground = g, edge = e }
	end
	nav.pick = CreateFrame("Frame", nil, nav) -- the gap (nothing drawn)
	nav.pick:SetHeight(32)
	nav.items = {}
	for i, c in ipairs(C.CATEGORIES) do
		local b = CreateFrame("Button", nil, nav)
		b:SetHeight(32)
		b:SetPoint("TOPLEFT", 0, -10 - (i - 1) * 32)
		b:SetPoint("TOPRIGHT", 0, -10 - (i - 1) * 32)
		b.key = c.key
		b.text = T.Text(b, "body", "text2")
		b.text:SetPoint("LEFT", PAD, 0)
		b.text:SetJustifyV("MIDDLE")
		b.text:SetText(c.name)
		b:SetFrameLevel((nav:GetFrameLevel() or 1) + 2)
		b.look = function(p)
			T.Font(b.text, b.pwOn and "window" or "body")
			if b.pwOn then T.Paint(b.text, "flair") else T.Blend(b.text, "text2", "text", p) end
		end
		b:SetScript("OnEnter", function(self) A.Hover(self, true, self.look) end)
		b:SetScript("OnLeave", function(self) A.Hover(self, false, self.look) end)
		b:SetScript("OnClick", function() C.Show(c.key) end)
		nav.items[i] = b
	end

	scroll, body = T.Scroll(frame, 64)
	scroll:SetPoint("TOPLEFT", NAV + PAD + 1, -HEAD - 14)
	scroll:SetPoint("BOTTOMRIGHT", -PAD - 8, PAD)
	body:SetSize(W - NAV - PAD * 2 - 14, 1)
	frame:SetScript("OnHide", function(self) A.Set(self, "alpha", 0) end)
	frame:Hide()
	return frame
end

function C.Show(key)
	build()
	local changed = key and key ~= current
	if changed then
		current = key
		scroll:ScrollTo(0, true)
	end
	if not frame:IsShown() then
		A.Set(frame, "alpha", 0)
		frame:SetAlpha(0)
		frame:Show()
		A.Fade(frame, 1, A.NORMAL)
	end
	C.Render()
	if changed then
		-- The new page fades in.
		A.Set(body, "alpha", 0)
		body:SetAlpha(0)
		A.Fade(body, 1, A.NORMAL)
		C.PaintNav(true)
	end
end
function C.Hide()
	if not (frame and frame:IsShown()) then return end
	A.Fade(frame, 0, A.FAST, function() if A.Get(frame, "alpha") == 0 then frame:Hide() end end)
end
function C.Toggle() if frame and frame:IsShown() then C.Hide() else C.Show() end end
function C.Frame() return frame end
function C.Current() return current end

ns.On("SHOW_CONFIG", function() C.Toggle() end)
ns.On("SETTING_CHANGED", function() if frame and frame:IsShown() then C.Render() end end)
ns.On("MOVE_MODE", function(on)
	if frame and frame.pwMove then
		frame.pwMove.pwText:SetText(on and "Done moving" or "Move everything")
		frame.pwMove:SetKind(on and "accent" or "default")
		frame.pwMove:Fit()
	end
end)

-- Listed in Pathwise's suite when Pathwise is installed.
ns.On("READY", function()
	local S = ns.Suite()
	if S and S.RegisterModule then
		S.RegisterModule({ key = "ui", name = "Pathwise UI", accent = "accent",
			about = "Your whole interface in the Pathwise look, in your color", open = function() C.Show() end })
	end
end)

