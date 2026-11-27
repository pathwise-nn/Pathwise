-- Pathwise Heal: hover keys (Healing/Clicks.lua, Heal.xml, the options page).

local h = ...
local test, eq, ok, fresh = h.test, h.eq, h.ok, h.fresh

local function priest(s)
	s.player.class = "PRIEST"
	s.units.player.class = "PRIEST"
end
local function frame(ns, unit)
	local b = CreateFrame("Button")
	ns.Heal.NewButton(b)
	ns.Heal.SetUnit(b, unit)
	return b
end

-- Heal.xml's secure snippets, as the game would run them: in their own
-- environment (no globals), on a frame handle.
local function snippet(name)
	local f = assert(io.open("Pathwise_Heal/Healing/Heal.xml", "r"))
	local xml = f:read("*a")
	f:close()
	local body = xml:match('name="' .. name .. '" type="string" value="(.-)"/>')
	assert(body, name .. " in Heal.xml")
	local fn = assert(loadstring(body))
	setfenv(fn, {})
	return fn, xml
end
local function handle(b)
	local h = { bound = {}, cleared = 0 }
	function h:GetAttribute(k) return b:GetAttribute(k) end
	function h:ClearBindings() self.cleared = self.cleared + 1 self.bound = {} end
	function h:SetBindingClick(priority, key, target, button)
		assert(priority == true and target == self, "a priority binding on this frame")
		self.bound[key] = button
	end
	return h
end
local function run(fn, self)
	-- A snippet sees `self`; give it as the chunk's first local.
	local env = getfenv(fn)
	env.self = self
	fn()
	env.self = nil
end

test("hover keys: a key and its spell become the frame's attributes; one cast per press", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "player")
	eq(b:GetAttribute("pw-key1"), nil, "empty until you set one")
	C.SetKey(1, "Q")
	eq(b:GetAttribute("pw-key1"), nil, "a key with nothing to cast binds nothing")
	C.SetKeySpell(1, "Flash Heal")
	eq(b:GetAttribute("pw-key1"), "Q")
	eq(b:GetAttribute("*type-pwkey1"), "spell")
	eq(b:GetAttribute("*spell-pwkey1"), "Flash Heal")
	eq(b:GetAttribute("*downbutton-pwkey1"), C.KEY_NONE, "the press does nothing, the release casts")
	C.SetKey(2, "SHIFT-E")
	C.SetKeySpell(2, C.Parse("target"))
	eq(b:GetAttribute("*type-pwkey2"), "target")
	eq(b:GetAttribute("type1"), "spell", "mouse clicks untouched")
	-- A key another slot had moves to the new one.
	C.SetKey(2, "Q")
	eq(b:GetAttribute("pw-key2"), "Q")
	eq(b:GetAttribute("pw-key1"), nil, "Q left slot 1")
	-- In a fight: after it.
	stub.combat = true
	C.SetKey(1, "F")
	C.SetKeySpell(3, "Renew")
	eq(b:GetAttribute("pw-key1"), nil, "not changed in combat")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	eq(b:GetAttribute("pw-key1"), "F", "once combat ends")
	C.SetKeySpell(1, nil)
	eq(b:GetAttribute("pw-key1"), nil, "cleared")
	eq(b:GetAttribute("*type-pwkey1"), nil)
end)

test("hover keys: each spec has its own", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "player")
	C.SetSpec("holy")
	C.SetKey(1, "Q")
	C.SetKeySpell(1, "Renew")
	C.SetSpec("discipline")
	eq(C.Key(1), nil, "Discipline starts empty")
	eq(b:GetAttribute("pw-key1"), nil)
	C.SetKey(1, "Q")
	C.SetKeySpell(1, "Power Word: Shield")
	C.SetSpec("holy")
	local key, spell = C.Key(1)
	eq(key, "Q")
	eq(spell, "Renew", "Holy's key kept")
	eq(b:GetAttribute("*spell-pwkey1"), "Renew")
	C.SetSpec("discipline")
	eq(b:GetAttribute("*spell-pwkey1"), "Power Word: Shield")
end)

test("hover keys: entering a frame binds its keys to it, leaving clears them (secure snippets)", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "party1")
	C.SetKey(1, "Q") C.SetKeySpell(1, "Flash Heal")
	C.SetKey(4, "ALT-2") C.SetKeySpell(4, "Renew")
	C.SetKey(5, "R") -- no spell: not bound
	local enter, xml = snippet("_onenter")
	local leave = snippet("_onleave")
	ok(xml:find('inherits="SecureUnitButtonTemplate, SecureHandlerEnterLeaveTemplate"', 1, true), "the frames run them securely")
	ok(xml:find("for i = 1, " .. C.MAX_KEYS .. " do", 1, true), "the snippet looks at every slot")
	local hd = handle(b)
	run(enter, hd)
	eq(hd.bound.Q, "pwkey1")
	eq(hd.bound["ALT-2"], "pwkey4")
	eq(hd.bound.R, nil)
	run(leave, hd)
	eq(next(hd.bound), nil, "leaving clears them")
end)

test("hover keys: a frame hidden under the mouse drops its keys, out of combat", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local b = CreateFrame("Button")
	local hooks = {}
	b.HookScript = function(self, k, fn) hooks[k] = hooks[k] or {} table.insert(hooks[k], fn) end
	ns.Heal.NewButton(b)
	ok(hooks.OnHide and #hooks.OnHide > 0, "an OnHide hook")
	local cleared = 0
	local was = _G.ClearOverrideBindings
	_G.ClearOverrideBindings = function(owner) if owner == b then cleared = cleared + 1 end end
	for _, fn in ipairs(hooks.OnHide) do fn(b) end
	eq(cleared, 1, "cleared on hide")
	stub.combat = true
	for _, fn in ipairs(hooks.OnHide) do fn(b) end
	eq(cleared, 1, "never in combat")
	stub.combat = false
	_G.ClearOverrideBindings = was
end)

test("hover keys: keys read and shown the game's way", function()
	local stub, ns = fresh(priest)
	local C = ns.HealClicks
	eq(C.Chord("LSHIFT"), nil, "a modifier alone waits for the key")
	eq(C.Chord("Q"), "Q")
	local was = _G.IsShiftKeyDown
	_G.IsShiftKeyDown = function() return true end
	_G.IsControlKeyDown = function() return true end
	eq(C.Chord("Q"), "CTRL-SHIFT-Q")
	_G.IsShiftKeyDown, _G.IsControlKeyDown = was, nil
	eq(C.KeyLabel("ALT-CTRL-SHIFT-Q"), "Alt + Ctrl + Shift + Q")
	eq(C.KeyLabel(nil), "")
end)

test("hover keys: the options page sets a key by pressing it, then its spell", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	ns.Config.Show("heal")
	local function rows()
		local out = {}
		for _, f in ipairs(stub.frames) do if f.shown and f.pwSlot and f.key then out[f.pwSlot] = f end end
		return out
	end
	local texts = table.concat(stub.texts(), " | ")
	ok(texts:find("Hover keys", 1, true), texts)
	local r = rows()
	ok(r[1] and not r[2], "one empty slot to start")
	local k = r[1].key
	k.scripts.OnClick(k, "LeftButton")
	ok(k.pwListening, "listening for a key")
	k.scripts.OnKeyDown(k, "LSHIFT")
	ok(k.pwListening, "Shift alone: still waiting")
	_G.IsShiftKeyDown = function() return true end
	k.scripts.OnKeyDown(k, "Q")
	_G.IsShiftKeyDown = function() return false end
	eq(ns.HealClicks.Key(1), "SHIFT-Q")
	local box = rows()[1].box
	box:SetText("Flash Heal")
	box.scripts.OnEnterPressed(box)
	local key, spell = ns.HealClicks.Key(1)
	eq(spell, "Flash Heal")
	ok(rows()[2], "a second slot to add another")
	-- Right click clears the key.
	local k1 = rows()[1].key
	k1.scripts.OnClick(k1, "RightButton")
	eq(ns.HealClicks.Key(1), nil)
	-- Escape stops listening without changing anything.
	k1.scripts.OnClick(k1, "LeftButton")
	k1.scripts.OnKeyDown(k1, "ESCAPE")
	ok(not k1.pwListening)
	eq(ns.HealClicks.Key(1), nil)
end)

test("trinkets: a click or a hover key uses your top or bottom trinket on them", function()
	local stub, ns = fresh(priest)
	ns.Set("heal.enabled", true)
	local C = ns.HealClicks
	local b = frame(ns, "party1")
	for _, typed in ipairs({ "trinket 1", "Trinket1", " top trinket ", "@trinket1", "TRINKET  1" }) do
		eq(C.Parse(typed), C.TRINKET1, typed)
	end
	eq(C.Parse("trinket 2"), C.TRINKET2)
	eq(C.Parse("bottom trinket"), C.TRINKET2)
	eq(C.Label(C.TRINKET1), "Trinket 1")
	eq(C.Label(C.TRINKET2), "Trinket 2")
	-- A click: the game's item action, by inventory slot (13 top, 14 bottom).
	C.Set("alt-2", C.Parse("trinket 1"))
	eq(b:GetAttribute("alt-type2"), "item")
	eq(b:GetAttribute("alt-item2"), "13")
	eq(b:GetAttribute("alt-spell2"), nil)
	-- Back to a spell: the item goes.
	C.Set("alt-2", "Renew")
	eq(b:GetAttribute("alt-type2"), "spell")
	eq(b:GetAttribute("alt-item2"), nil)
	-- A hover key.
	C.SetKey(1, "T")
	C.SetKeySpell(1, C.TRINKET2)
	eq(b:GetAttribute("pw-key1"), "T")
	eq(b:GetAttribute("*type-pwkey1"), "item")
	eq(b:GetAttribute("*item-pwkey1"), "14")
	eq(b:GetAttribute("*downbutton-pwkey1"), C.KEY_NONE, "one use per press")
	C.SetKeySpell(1, "Flash Heal")
	eq(b:GetAttribute("*item-pwkey1"), nil)
end)

test("trinkets: a worn trinket dropped on a box binds its slot; anything else is ignored", function()
	local stub, ns = fresh(priest)
	local C = ns.HealClicks
	stub.equipped[13], stub.equipped[14] = 111, 222
	local cursor
	_G.GetCursorInfo = function() if cursor then return "item", cursor, "item:" .. cursor end end
	_G.ClearCursor = function() cursor = nil end
	_G.GetInventoryItemID = function(_, slot) return stub.equipped[slot] end
	cursor = 222
	eq(C.FromCursor(), C.TRINKET2)
	eq(cursor, nil, "put back")
	cursor = 111
	eq(C.FromCursor(), C.TRINKET1)
	cursor = 999
	eq(C.FromCursor(), nil, "not a worn trinket")
	eq(cursor, 999, "left on the cursor")
	_G.GetCursorInfo, _G.ClearCursor, _G.GetInventoryItemID = nil, nil, nil
end)
