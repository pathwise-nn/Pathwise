-- Pathwise Gear's hunts: the gear you chose to go after. Right-click a slot
-- on the character panel to see the best you can get for it, ranked (the
-- Hunts page). Track one: the arrow (or the game's map pin, without
-- Pathwise) leads to where it comes from, and when it is in your bags or on
-- you, it is done: on screen, with a sound and in chat. Items that are not
-- for you can be hidden from every list, and shown again.
--
--   Hunts.Track(entry)  Hunts.Untrack(id)  Hunts.Hide(id)  Hunts.Unhide(id)
--   Hunts.Tracked() -> { { id, slot, entry }, ... }   Hunts.Done()  Hunts.Hidden()
--   Hunts.Claimed(id)   tracked, or done just now: the other alerts stay quiet
--
-- Kept per character (ns.CharData("hunts")), never reset with the settings.
--
-- Hook: HookScript("OnClick") on the character panel's slot buttons (after
-- the game's own click, which it leaves as it is: a right-click on a trinket
-- still uses it).

local ADDON, ns = ...
local S, Gear, Best = ns.S, ns.Gear, ns.Best
local Client = Gear.Client
local readable = S.Compat.Readable
local Hunts = {}
ns.Hunts = Hunts

S.Defaults("gear", { slotClick = true, huntAlert = true })

local function store()
	local d = ns.CharData("hunts")
	for _, k in ipairs({ "tracked", "done", "hidden" }) do if type(d[k]) ~= "table" then d[k] = {} end end
	return d
end
local function now() return (time and time()) or 0 end
local justDone = {} -- this session: done just now, so the other alerts keep quiet

-- The slot the Hunts page shows (the one last right-clicked).
Hunts.slot = 1

local function changed()
	S.Fire("GEAR_HUNTS_CHANGED")
	S.Refresh()
end

local function nameOf(id, entry)
	local n = entry and entry.name
	if not n then local _, _, _, _, _, name = Client.Info("item:" .. id) n = name end
	return n or ("item " .. id)
end

local function wearing(id)
	for slot = 1, 18 do
		local l = Client.Equipped(slot)
		if l and tonumber(tostring(l):match("item:(%d+)")) == id then return true end
	end
	return false
end
local function owned(id) return wearing(id) or Best.Have(id) end

function Hunts.IsTracked(id) return id ~= nil and store().tracked[id] ~= nil end
function Hunts.IsHidden(id) return id ~= nil and store().hidden[id] ~= nil end
function Hunts.Claimed(id) return Hunts.IsTracked(id) or justDone[id] == true end

-- Track it and point the way. -> true, or false and why.
function Hunts.Track(entry)
	local id = entry and entry.id
	if not id then return false end
	local name = nameOf(id, entry)
	if owned(id) then
		S.Print(("you have %s already."):format(name))
		return false, "have"
	end
	local d = store()
	d.tracked[id] = { at = now(), slot = entry.slot }
	d.done[id] = nil
	local arrow = ns.Pathwise() ~= nil
	if Best.Chase(entry) then
		S.Print(("tracking %s: %s %s."):format(name, arrow and "the arrow leads to" or "a pin on your map shows", Best.SourceText(entry.source)))
	else
		S.Print(("tracking %s: %s."):format(name, Best.SourceText(entry.source)))
	end
	changed()
	return true
end

function Hunts.Untrack(id)
	store().tracked[id] = nil
	changed()
end

-- Point the way again to a hunt's source as it is now.
function Hunts.Chase(id)
	local e = Best.Entry(id)
	if e and Best.Chase(e) then return true end
	S.Print(("%s comes from %s; there is no place to point at."):format(nameOf(id, e), Best.SourceText(e and e.source)))
	return false
end

-- Not for me: out of every list (and no longer tracked).
function Hunts.Hide(id)
	local d = store()
	d.hidden[id] = true
	d.tracked[id] = nil
	Best.Clear()
	changed()
end
function Hunts.Unhide(id)
	store().hidden[id] = nil
	Best.Clear()
	changed()
end
function Hunts.ClearDone()
	store().done = {}
	changed()
end

local function list(t, extra)
	local out = {}
	for id, v in pairs(t) do
		local e = { id = id, at = type(v) == "table" and v.at or 0, slot = type(v) == "table" and v.slot or nil }
		if extra then e.entry = Best.Entry(id) end
		e.name = nameOf(id, e.entry)
		out[#out + 1] = e
	end
	table.sort(out, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.id < b.id end)
	return out
end
function Hunts.Tracked() return list(store().tracked, true) end
function Hunts.Done() return list(store().done) end
function Hunts.Hidden() return list(store().hidden) end

-- Got it: done, said loudly.
function Hunts.Complete(id)
	local d = store()
	local t = d.tracked[id]
	if not t then return end
	d.tracked[id] = nil
	d.done[id] = { at = now(), slot = t.slot }
	justDone[id] = true
	if S.Get("gear.huntAlert") ~= false then
		local name = nameOf(id)
		local slot = t.slot and Gear.SLOT_NAMES[t.slot]
		local text = ("Hunt done: %s%s"):format(name, slot and (" (" .. slot .. ")") or "")
		local c = S.Theme.Color("gear")
		local shown = false
		if RaidWarningUtil and RaidWarningUtil.AddMessage then
			shown = pcall(RaidWarningUtil.AddMessage, text, { r = c[1], g = c[2], b = c[3] }, 5)
		end
		if not shown and UIErrorsFrame and UIErrorsFrame.AddMessage then
			pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, c[1], c[2], c[3])
		end
		local sound = SOUNDKIT and (SOUNDKIT.IG_QUEST_LIST_COMPLETE or SOUNDKIT.RAID_WARNING)
		if PlaySound and sound then pcall(PlaySound, sound) end
		local I = C_Item
		local ok, _, link = false, nil, nil
		if I and I.GetItemInfo then ok, _, link = pcall(I.GetItemInfo, id) end
		S.Print(("hunt done: %s%s."):format(readable(link) or name, slot and (" for your " .. slot:lower()) or ""))
	end
	S.Fire("GEAR_HUNT_DONE", id)
	changed()
end

-- Is a tracked item in the bags or on you now?
function Hunts.Check()
	local d = store()
	local got = {}
	for id in pairs(d.tracked) do if owned(id) then got[#got + 1] = id end end
	table.sort(got)
	for _, id in ipairs(got) do Hunts.Complete(id) end
end
S.On("READY", function() Hunts.Check() end)
S.RegisterEvent("BAG_UPDATE_DELAYED", function() Hunts.Check() end)
S.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() Hunts.Check() end)

---------------------------------------------------------------------------
-- The character panel: right-click a slot
---------------------------------------------------------------------------

local SLOT_FRAMES = {
	[1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot", [15] = "CharacterBackSlot",
	[5] = "CharacterChestSlot", [9] = "CharacterWristSlot", [10] = "CharacterHandsSlot", [6] = "CharacterWaistSlot",
	[7] = "CharacterLegsSlot", [8] = "CharacterFeetSlot", [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot",
	[13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot", [16] = "CharacterMainHandSlot",
	[17] = "CharacterSecondaryHandSlot", [18] = "CharacterRangedSlot",
}
Hunts.SLOT_FRAMES = SLOT_FRAMES

-- Open the Hunts page on this slot.
function Hunts.Show(slot)
	Hunts.slot = slot or Hunts.slot
	if ns.Config then ns.Config.Show("hunts") end
end

local hooked = {}
function Hunts.HookSlots()
	local n = 0
	for slot, name in pairs(SLOT_FRAMES) do
		local f = _G[name]
		if f and not hooked[f] and f.HookScript then
			hooked[f] = true
			f:HookScript("OnClick", function(_, button)
				if button == "RightButton" and S.Get("gear.slotClick") ~= false then Hunts.Show(slot) end
			end)
			n = n + 1
		end
	end
	return n
end
S.On("READY", function()
	Hunts.HookSlots()
	-- The panel may be made later: look again when it opens.
	if hooksecurefunc and _G.ToggleCharacter then pcall(hooksecurefunc, "ToggleCharacter", Hunts.HookSlots) end
end)
