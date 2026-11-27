-- Click-casting on the healing frames: each mouse button (with or without
-- Shift, Ctrl or Alt) casts a spell you pick on the person you click, or
-- targets them, or opens their menu. Spells are kept by NAME, so the highest
-- rank you know is cast as you level, and whatever Forever's classes have
-- comes from your own spellbook. Bindings belong to the character. Hover keys
-- (keyboard keys that cast on the frame under your mouse) are further down,
-- kept per spec.
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
-- Your worn trinkets, by slot (13 the top one, 14 the bottom one in the
-- character pane): used on whoever you click, as a secure "item" action
-- with item = "13" (SecureTemplates.lua -> SecureCmdItemParse ->
-- UseInventoryItem(13, unit)). Whatever trinket is in the slot is used, so
-- swapping trinkets needs no change. An empty slot or a trinket with no use
-- does nothing useful (not checked in game).
C.TRINKET1, C.TRINKET2 = "@trinket1", "@trinket2"
C.TRINKET_SLOT = { [C.TRINKET1] = 13, [C.TRINKET2] = 14 }

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

-- A spell at one rank, the way the game casts it: "Lesser Heal(Rank 1)"
-- (no space before the bracket). A bare name casts your highest rank.
function C.Ranked(name, rank)
	rank = tonumber(rank)
	if not rank then return name end
	return name .. "(Rank " .. rank .. ")"
end

-- The binding boxes' tooltip: a title, then lines.
C.TIP = {
	"Spell ranks",
	"A spell's name alone casts your highest rank, and moves up as you learn new ones.",
	"For a lower rank, add it: Lesser Heal [Rank 1], Lesser Heal (Rank 1) or Lesser Heal r1.",
	"Or drag that rank from your spellbook onto the box (tick Show all spell ranks in the spellbook to see them).",
	"Trinket 1 or Trinket 2 uses your top or bottom trinket on them; or drag a worn trinket from your character pane.",
}

-- "Heal (Rank 2)", "Heal [rank 2]", "Heal(2)", "Heal rank 2", "Heal r2" ->
-- "Heal(Rank 2)"; anything else is left as typed.
local function rankForm(text)
	local name, n = text:match("^(.-)%s*[%(%[]%s*[Rr][Aa][Nn][Kk]%s*(%d+)%s*[%)%]]$")
	if not name then name, n = text:match("^(.-)%s*[%(%[]%s*[Rr]?%s*(%d+)%s*[%)%]]$") end
	if not name then name, n = text:match("^(.-)%s+[Rr][Aa][Nn][Kk]%s*(%d+)$") end
	if not name then name, n = text:match("^(.-)%s+[Rr](%d+)$") end
	if name and name ~= "" then return C.Ranked(name, n) end
	return text
end

-- Typed text -> a binding: "" / "nothing" clears, "target" / "menu",
-- "trinket 1" / "trinket 2" (or "top trinket", "bottom trinket"), else a
-- spell (with a rank if you give one).
local TRINKET_WORDS = {
	["trinket1"] = C.TRINKET1, ["trinket 1"] = C.TRINKET1, ["@trinket1"] = C.TRINKET1, ["top trinket"] = C.TRINKET1, ["trinket top"] = C.TRINKET1,
	["trinket2"] = C.TRINKET2, ["trinket 2"] = C.TRINKET2, ["@trinket2"] = C.TRINKET2, ["bottom trinket"] = C.TRINKET2, ["trinket bottom"] = C.TRINKET2,
}
function C.Parse(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local low = text:lower()
	if low == "" or low == "nothing" or low == "none" then return nil end
	if low == "target" or low == "@target" then return C.TARGET end
	if low == "menu" or low == "@menu" then return C.MENU end
	local trinket = TRINKET_WORDS[low:gsub("%s+", " ")]
	if trinket then return trinket end
	return rankForm(text)
end
function C.Label(v)
	if v == nil then return "" end
	if v == C.TARGET then return "Target" end
	if v == C.MENU then return "Menu" end
	if v == C.TRINKET1 then return "Trinket 1" end
	if v == C.TRINKET2 then return "Trinket 2" end
	return v
end

-- One binding as a secure button's attributes: type, spell and item for
-- one button ("shift-" .. "1", or "*" .. "pwkey3").
local function setAction(b, prefix, button, v)
	local typeKey, spellKey, itemKey = prefix .. "type" .. button, prefix .. "spell" .. button, prefix .. "item" .. button
	local tType, tSpell, tItem
	if v == C.TARGET then tType = "target"
	elseif v == C.MENU then tType = "togglemenu"
	elseif C.TRINKET_SLOT[v] then tType, tItem = "item", tostring(C.TRINKET_SLOT[v])
	elseif type(v) == "string" then tType, tSpell = "spell", v end
	b:SetAttribute(typeKey, tType)
	b:SetAttribute(spellKey, tSpell)
	b:SetAttribute(itemKey, tItem)
end

function C.Set(combo, value)
	local d = C.Data()
	d.binds[combo] = value
	d.auto[combo] = nil
	d.cleared[combo] = value == nil or nil
	C.ApplyAll()
	ns.Fire("SETTING_CHANGED", "heal.binds")
end

---------------------------------------------------------------------------
-- Hover keys: a keyboard key (with Shift, Ctrl or Alt if you like) that
-- casts a spell on whoever your mouse is over, like Clique or HealBot. Your
-- own, empty until you set them, and kept per spec (Holy and Discipline each
-- have their own). While your mouse is over a healing frame they take the
-- place of what the key does elsewhere (an action bar key, say).
--
-- How: each frame carries "pw-key1".."pw-key10" (the keys) and
-- "*type-pwkey1" / "*spell-pwkey1" (what they cast; "*" whatever modifiers
-- are down, the key itself names them). Heal.xml's secure _onenter snippet
-- binds each key to a click of "pwkeyN" on that frame (SetBindingClick,
-- Blizzard_RestrictedAddOnEnvironment/RestrictedFrames.lua) and _onleave
-- clears them, so it works in a fight too. A secure unit button acts on both
-- the press and the release (SecureUnitButton_OnClick), so the press is sent
-- to a button that does nothing ("*downbutton-pwkeyN"): one cast per key.
---------------------------------------------------------------------------

C.MAX_KEYS = 10
C.KEY_NONE = "pwnone"

-- This spec's keys: slot -> { key = "SHIFT-Q", spell = "Flash Heal" }.
function C.KeyStore(specKey)
	local d = C.Data()
	d.keys = type(d.keys) == "table" and d.keys or {}
	specKey = specKey or C.Spec().key
	d.keys[specKey] = type(d.keys[specKey]) == "table" and d.keys[specKey] or {}
	return d.keys[specKey]
end
-- -> key, spell (either may be nil)
function C.Key(slot)
	local k = C.KeyStore()[slot]
	if type(k) ~= "table" then return nil, nil end
	return k.key, k.spell
end
local function slotOf(slot)
	local store = C.KeyStore()
	store[slot] = type(store[slot]) == "table" and store[slot] or {}
	return store[slot], store
end
local function keysChanged() C.ApplyAll() ns.Fire("SETTING_CHANGED", "heal.keys") end
-- A key for a slot (nil clears it); a key another slot had moves here.
function C.SetKey(slot, key)
	local s, store = slotOf(slot)
	if key then
		for i, other in pairs(store) do if i ~= slot and type(other) == "table" and other.key == key then other.key = nil end end
	end
	s.key = key
	keysChanged()
end
-- What a slot's key casts: a spell, C.TARGET, C.MENU, C.TRINKET1/2 or nil.
function C.SetKeySpell(slot, value)
	slotOf(slot).spell = value
	keysChanged()
end

-- "SHIFT-Q" -> "Shift + Q", in the game's words when it has them.
function C.KeyLabel(key)
	if type(key) ~= "string" or key == "" then return "" end
	if GetBindingText then
		local ok, t = pcall(GetBindingText, key)
		if ok and type(t) == "string" and t ~= "" and t ~= key then return t end
	end
	local out = key:gsub("ALT%-", "Alt + "):gsub("CTRL%-", "Ctrl + "):gsub("SHIFT%-", "Shift + "):gsub("META%-", "Cmd + ")
	return out
end

-- A key pressed while a key box listens -> the binding the game wants
-- ("ALT-CTRL-SHIFT-Q"), or nil for a modifier on its own (wait for the rest).
local MODIFIER = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, LMETA = true, RMETA = true }
function C.Chord(key)
	if type(key) ~= "string" or key == "" or MODIFIER[key] then return nil end
	if CreateKeyChordStringUsingMetaKeyState then
		local ok, chord = pcall(CreateKeyChordStringUsingMetaKeyState, key)
		if ok and type(chord) == "string" then return chord end
	end
	local p = ""
	if IsAltKeyDown and IsAltKeyDown() then p = p .. "ALT-" end
	if IsControlKeyDown and IsControlKeyDown() then p = p .. "CTRL-" end
	if IsShiftKeyDown and IsShiftKeyDown() then p = p .. "SHIFT-" end
	return p .. key
end

-- One frame's hover-key attributes.
local function applyKeys(b)
	for i = 1, C.MAX_KEYS do
		local key, v = C.Key(i)
		local btn = "pwkey" .. i
		b:SetAttribute("*downbutton-" .. btn, C.KEY_NONE)
		setAction(b, "*", "-" .. btn, v)
		b:SetAttribute("pw-key" .. i, (key and v ~= nil) and key or nil)
	end
	-- Keys left from a frame the mouse is no longer over (one hidden under
	-- it skips _onleave): out of combat we may clear them ourselves.
	if ClearOverrideBindings and not (b.IsMouseOver and b:IsMouseOver()) then pcall(ClearOverrideBindings, b) end
end

-- The attributes on one frame (out of combat; else once combat ends).
function C.Apply(b)
	if inCombat() then C.pending = true return end
	if not b.SetAttribute then return end
	applyKeys(b)
	local store = C.Store()
	for _, c in ipairs(C.COMBOS) do
		local combo = c[1]
		local prefix, button = combo:match("^(.-)(%d)$")
		setAction(b, prefix, button, store[combo])
	end
end
function C.ApplyAll()
	if inCombat() then C.pending = true return end
	for _, b in ipairs(ns.Heal.buttons) do C.Apply(b) end
end

local function rankOf(sub)
	return type(sub) == "string" and tonumber(sub:match("(%d+)")) or nil
end

-- The id the game casts for a bare name: your highest rank. nil: can't tell.
local function highestId(name)
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		if ok and type(info) == "table" then return info.spellID end
	end
	if GetSpellInfo then
		local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, name)
		if ok then return id end
	end
end

-- A spell dropped on a binding box from your spellbook: its name, with its
-- rank when it isn't your highest (dragging Rank 1 binds Rank 1; dragging
-- the top rank binds the bare name, so it keeps up as you learn higher ones).
-- A trinket you wear, dropped there from your character pane (or the same
-- one from your bags): that trinket slot. Any other item: nothing.
function C.FromCursor()
	if not GetCursorInfo then return nil end
	local kind, slot, book, id = GetCursorInfo()
	if kind == "item" then
		local itemID = tonumber(slot)
		local found
		if itemID and GetInventoryItemID then
			for v, inv in pairs(C.TRINKET_SLOT) do
				local ok, worn = pcall(GetInventoryItemID, "player", inv)
				if ok and worn == itemID then found = v end
			end
		end
		if found and ClearCursor then ClearCursor() end
		return found
	end
	if kind ~= "spell" then return nil end
	if ClearCursor then ClearCursor() end
	local name, sub
	if type(id) == "number" then
		if C_Spell and C_Spell.GetSpellName then
			local ok, n = pcall(C_Spell.GetSpellName, id)
			if ok then name = n end
		end
		if not name and GetSpellInfo then name = GetSpellInfo(id) end
		if C_Spell and C_Spell.GetSpellSubtext then
			local ok, s = pcall(C_Spell.GetSpellSubtext, id)
			if ok then sub = s end
		end
		if not sub and GetSpellSubtext then
			local ok, s = pcall(GetSpellSubtext, id)
			if ok then sub = s end
		end
	end
	if not name and type(slot) == "number" and GetSpellBookItemName then
		local ok, n, s = pcall(GetSpellBookItemName, slot, book)
		if ok then name, sub = n, sub or s end
	end
	if type(name) ~= "string" then return nil end
	local rank = rankOf(sub)
	if not rank or (type(id) == "number" and highestId(name) == id) then return name end
	return C.Ranked(name, rank)
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
