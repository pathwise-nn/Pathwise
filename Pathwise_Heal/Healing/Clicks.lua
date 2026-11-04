-- Click-casting on the healing frames: each mouse button (with or without
-- Shift, Ctrl or Alt) casts a spell you pick on the person you click, or
-- targets them, or opens their menu. Spells are kept by NAME, so the highest
-- rank you know is cast as you level, and whatever Forever's classes have
-- comes from your own spellbook. Bindings belong to the character.
--
-- They are the secure unit button's own attributes ("shift-type1" = "spell",
-- "shift-spell1" = "Flash Heal"), set out of combat; they then work in combat.

local ADDON, ns = ...
local C = {}
ns.HealClicks = C

C.COMBOS = {
	{ "1", "Left click" }, { "2", "Right click" }, { "3", "Middle click" },
	{ "shift-1", "Shift + left" }, { "shift-2", "Shift + right" },
	{ "ctrl-1", "Ctrl + left" }, { "ctrl-2", "Ctrl + right" },
	{ "alt-1", "Alt + left" }, { "alt-2", "Alt + right" },
	{ "4", "Mouse button 4" }, { "5", "Mouse button 5" },
}
C.TARGET, C.MENU = "@target", "@menu"

-- Presets by spec: what each click casts, as lists tried in order (the first
-- spell your spellbook knows is used). One layout for every spec:
--   left quick heal, right HoT or instant, middle shield or protection,
--   shift+left big heal, shift+right first cleanse, ctrl+left target,
--   ctrl+right menu, alt+left group heal, alt+right second cleanse,
--   buttons 4 and 5 the spec's own spells.
-- Classic's spell names, plus what Forever adds (Penance, Prayer of Mending,
-- Binding Heal, Riptide, Wild Growth, Oath of Light) as Forever's class
-- previews name them: NOT yet checked in game. A name the game doesn't know
-- is simply skipped, so a wrong one never casts anything; a talent you have
-- not learned leaves its click empty until you learn it (C.Refresh).
local T_, M_ = "@target", "@menu"
C.SPECS = {
	PRIEST = {
		{ key = "holy", label = "Holy", tree = 2, binds = {
			["1"] = { "Flash Heal", "Heal", "Lesser Heal" }, ["2"] = { "Renew" }, ["3"] = { "Power Word: Shield" },
			["shift-1"] = { "Greater Heal", "Heal", "Lesser Heal" }, ["shift-2"] = { "Dispel Magic" },
			["ctrl-1"] = { T_ }, ["ctrl-2"] = { M_ },
			["alt-1"] = { "Prayer of Healing" }, ["alt-2"] = { "Abolish Disease", "Cure Disease" },
			["4"] = { "Prayer of Mending" }, ["5"] = { "Binding Heal" } } },
		{ key = "discipline", label = "Discipline", tree = 1, binds = {
			["1"] = { "Flash Heal", "Heal", "Lesser Heal" }, ["2"] = { "Power Word: Shield" }, ["3"] = { "Renew" },
			["shift-1"] = { "Greater Heal", "Heal", "Lesser Heal" }, ["shift-2"] = { "Dispel Magic" },
			["ctrl-1"] = { T_ }, ["ctrl-2"] = { M_ },
			["alt-1"] = { "Prayer of Healing" }, ["alt-2"] = { "Abolish Disease", "Cure Disease" },
			["4"] = { "Penance" }, ["5"] = { "Binding Heal" } } },
	},
	DRUID = {
		{ key = "restoration", label = "Restoration", tree = 3, binds = {
			["1"] = { "Regrowth", "Healing Touch" }, ["2"] = { "Rejuvenation" }, ["3"] = { "Swiftmend" },
			["shift-1"] = { "Healing Touch" }, ["shift-2"] = { "Remove Curse" },
			["ctrl-1"] = { T_ }, ["ctrl-2"] = { M_ },
			["alt-1"] = { "Wild Growth" }, ["alt-2"] = { "Abolish Poison", "Cure Poison" },
			["4"] = { "Innervate" }, ["5"] = { "Rebirth" } } },
	},
	SHAMAN = {
		{ key = "restoration", label = "Restoration", tree = 3, binds = {
			["1"] = { "Lesser Healing Wave", "Healing Wave" }, ["2"] = { "Riptide" },
			["shift-1"] = { "Healing Wave" }, ["shift-2"] = { "Cure Poison" },
			["ctrl-1"] = { T_ }, ["ctrl-2"] = { M_ },
			["alt-1"] = { "Chain Heal" }, ["alt-2"] = { "Cure Disease" },
			["5"] = { "Ancestral Spirit" } } },
	},
	PALADIN = {
		{ key = "holy", label = "Holy", tree = 1, binds = {
			["1"] = { "Flash of Light", "Holy Light" }, ["2"] = { "Holy Shock" }, ["3"] = { "Blessing of Protection" },
			["shift-1"] = { "Holy Light" }, ["shift-2"] = { "Cleanse", "Purify" },
			["ctrl-1"] = { T_ }, ["ctrl-2"] = { M_ },
			["alt-1"] = { "Oath of Light" }, ["alt-2"] = { "Blessing of Freedom" },
			["4"] = { "Lay on Hands" }, ["5"] = { "Redemption" } } },
	},
	-- The other classes heal no one, but the frames still target and open
	-- menus; a mage can lift curses.
	MAGE = { { key = "support", label = "Support", binds = { ["1"] = { T_ }, ["2"] = { M_ }, ["shift-2"] = { "Remove Lesser Curse" } } } },
}
local SUPPORT = { { key = "support", label = "Support", binds = { ["1"] = { T_ }, ["2"] = { M_ } } } }

-- Where a spell comes from, for the options page (Forever's previews; not
-- checked in game).
C.NOTES = {
	["Penance"] = "Discipline talent (21 points), new in Forever",
	["Prayer of Mending"] = "Holy talent, new in Forever",
	["Binding Heal"] = "every Priest in Forever",
	["Swiftmend"] = "Restoration talent",
	["Wild Growth"] = "Restoration talent, new in Forever",
	["Riptide"] = "Restoration, new in Forever",
	["Holy Shock"] = "Holy talent",
	["Oath of Light"] = "Holy, new in Forever",
}

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local function playerClass()
	local _, class = UnitClass("player")
	return ns.Readable(class)
end

function C.Data()
	local d = ns.CharData("heal")
	d.binds = type(d.binds) == "table" and d.binds or {}
	d.auto = type(d.auto) == "table" and d.auto or {} -- combo -> the spell a preset put there
	d.cleared = type(d.cleared) == "table" and d.cleared or {} -- combos you emptied yourself
	return d
end
function C.Store() return C.Data().binds end

-- Do you know this spell? (Its name resolves in your spellbook.) nil: can't tell.
function C.Known(name)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		if ok then return info ~= nil end
	end
	if GetSpellInfo then
		local ok, n = pcall(GetSpellInfo, name)
		if ok then return n ~= nil end
	end
	return nil
end

-- Your class's specs (healers: their healing specs; others: Support).
function C.Specs(class)
	return C.SPECS[class or playerClass() or ""] or SUPPORT
end

-- The talent tree with the most points (C_SpecializationInfo), or nil.
local function talentTree()
	local Sp = C_SpecializationInfo
	if not (Sp and Sp.GetSpecializationInfo) then return nil end
	local best, bestPoints
	for i = 1, 3 do
		local ok, _, _, _, _, _, _, points = pcall(Sp.GetSpecializationInfo, i)
		points = ok and ns.Readable(points)
		if type(points) == "number" and points > 0 and (not bestPoints or points > bestPoints) then best, bestPoints = i, points end
	end
	return best
end

-- The spec whose preset you use: the one you chose, else your talents' (a
-- non-healing tree, or no talents yet: the class's first healing spec).
-- -> spec, "chosen" | "auto"
function C.Spec()
	local specs, chosen = C.Specs(), C.Data().spec
	for _, s in ipairs(specs) do if s.key == chosen then return s, "chosen" end end
	local tree = talentTree()
	for _, s in ipairs(specs) do if tree and s.tree == tree then return s, "auto" end end
	return specs[1], "auto"
end
function C.SetSpec(key)
	C.Data().spec = key ~= "auto" and key or nil
	C.Refresh()
	ns.Fire("SETTING_CHANGED", "heal.binds")
end

-- The preset's choice for a combo now: the first spell of its list you know.
local function pick(list)
	for _, name in ipairs(list or {}) do
		if name == T_ or name == M_ then return name end
		if C.Known(name) ~= false then return name end
	end
	return nil
end

-- Brings the preset up to date without touching your own choices: a combo
-- still holding what a preset put there (or empty, and not emptied by you)
-- takes the preset's current pick. So a spell learned later (a talent, a
-- higher heal) fills in by itself, and a new spec swaps its spells in.
function C.Refresh()
	if inCombat() then C.pending = true return end
	local d = C.Data()
	local binds = C.Spec().binds
	for _, c in ipairs(C.COMBOS) do
		local combo = c[1]
		local now = d.binds[combo]
		local mine = now ~= nil and now ~= d.auto[combo]
		if not mine and not (now == nil and d.cleared[combo]) then
			local want = pick(binds[combo])
			d.binds[combo] = want
			d.auto[combo] = want
		end
	end
	C.ApplyAll()
end

-- The spec's preset in every combo (`replace`: your own choices too).
function C.Defaults(replace)
	local d = C.Data()
	if replace then
		for k in pairs(d.binds) do d.binds[k] = nil end
		for k in pairs(d.auto) do d.auto[k] = nil end
		for k in pairs(d.cleared) do d.cleared[k] = nil end
	end
	C.Refresh()
end

function C.Get(combo) return C.Store()[combo] end

-- Typed text -> a binding: "" / "nothing" clears, "target" / "menu", else a spell.
function C.Parse(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local low = text:lower()
	if low == "" or low == "nothing" or low == "none" then return nil end
	if low == "target" or low == "@target" then return C.TARGET end
	if low == "menu" or low == "@menu" then return C.MENU end
	return text
end
function C.Label(v)
	if v == nil then return "" end
	if v == C.TARGET then return "Target" end
	if v == C.MENU then return "Menu" end
	return v
end

function C.Set(combo, value)
	local d = C.Data()
	d.binds[combo] = value
	d.auto[combo] = nil
	d.cleared[combo] = value == nil or nil
	C.ApplyAll()
	ns.Fire("SETTING_CHANGED", "heal.binds")
end

-- The attributes on one frame (out of combat; else once combat ends).
function C.Apply(b)
	if inCombat() then C.pending = true return end
	if not b.SetAttribute then return end
	local store = C.Store()
	for _, c in ipairs(C.COMBOS) do
		local combo = c[1]
		local prefix, button = combo:match("^(.-)(%d)$")
		local v = store[combo]
		local typeKey, spellKey = prefix .. "type" .. button, prefix .. "spell" .. button
		if v == C.TARGET then b:SetAttribute(typeKey, "target") b:SetAttribute(spellKey, nil)
		elseif v == C.MENU then b:SetAttribute(typeKey, "togglemenu") b:SetAttribute(spellKey, nil)
		elseif type(v) == "string" then b:SetAttribute(typeKey, "spell") b:SetAttribute(spellKey, v)
		else b:SetAttribute(typeKey, nil) b:SetAttribute(spellKey, nil) end
	end
end
function C.ApplyAll()
	if inCombat() then C.pending = true return end
	for _, b in ipairs(ns.Heal.buttons) do C.Apply(b) end
end

-- A spell dropped on a binding box from your spellbook: its name.
function C.FromCursor()
	if not GetCursorInfo then return nil end
	local kind, a, b, c = GetCursorInfo()
	if kind ~= "spell" then return nil end
	local id = c or b or a
	local name
	if C_Spell and C_Spell.GetSpellName then
		local ok, n = pcall(C_Spell.GetSpellName, id)
		if ok then name = n end
	end
	if not name and GetSpellInfo then name = GetSpellInfo(id) end
	if ClearCursor then ClearCursor() end
	return type(name) == "string" and name or nil
end

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if C.pending then C.pending = false C.Refresh() end end)
-- New spells, a level or talents: fill in what the preset can now cast.
for _, ev in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE",
	"CHARACTER_POINTS_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED" }) do
	ns.RegisterEvent(ev, function() if ns.Get("heal.enabled") and C.Data().defaulted then C.Refresh() end end)
end
-- The first time healing frames are on for this character: the class's defaults.
ns.On("SETTING_CHANGED", function(path)
	if path == "heal.enabled" and ns.Get("heal.enabled") and not ns.CharData("heal").defaulted then
		ns.CharData("heal").defaulted = true
		C.Defaults(false)
	end
end)
ns.On("READY", function()
	if ns.Get("heal.enabled") and not ns.CharData("heal").defaulted then
		ns.CharData("heal").defaulted = true
		C.Defaults(false)
	end
end)
