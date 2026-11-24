-- Pathwise's quest sparkle: motes of gold light rising around the nameplate
-- of a monster you need, the way the game sparkles a quest object you can
-- loot (it does that for objects only, never for monsters).
--
-- Which monsters, from the quest data (QuestieDB's Forever data, Data/Data.lua),
-- for the quests the markers follow (QuestMarkers: the step's and the
-- tracked ones), while an objective is unfinished in the quest log:
--   kill objectives: the monster, or the monsters that give its credit;
--   item objectives: the monsters that drop the item;
--   the step's "have" goals still open: the monsters that drop the item.
-- Objects (chests, plants) have no nameplate: the game's own sparkle marks them.
--
-- Where: an addon can't draw on a monster in the world, only on its
-- nameplate (C_NamePlate.GetNamePlateForUnit, NAME_PLATE_UNIT_ADDED/REMOVED),
-- so the motes rise from just under the plate, where the monster is. It needs
-- the game's enemy nameplates on, and plates show only within their range.
-- The monster's id is read from its GUID ("Creature-0-...-<npc id>-<spawn>");
-- a GUID the game keeps secret is left alone, as is a plate forbidden to
-- addons. Works over the game's plates and Pathwise UI's alike: the frame is
-- a child of the game's plate, never of anything drawn on it.

local ADDON, ns = ...
local T = ns.Theme
local S = {}
ns.Sparkle = S

ns.Defaults("sparkle", {
	enabled = true,
})

local MOTES = 9 -- motes per monster
local WIDTH, HEIGHT = 84, 46 -- the area they rise in, under the plate
local RISE = 22 -- how far each rises, in pixels
local COLOR = { 1, 0.84, 0.36 } -- quest gold
local MAX_DROPS = 30 -- an item more monsters drop is a world drop: no sparkle

local readable = function(v) return ns.Compat.Readable(v) end
local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a = pcall(fn, ...) if ok then return a end end

---------------------------------------------------------------------------
-- Which monsters
---------------------------------------------------------------------------

local OBJECTIVES = 12
local wanted = {} -- npc id -> true

local function addDrops(out, item)
	local it = ns.Data and ns.Data.items and ns.Data.items[item]
	local list = it and it[2]
	if type(list) ~= "table" or #list > MAX_DROPS then return end
	for _, n in ipairs(list) do out[n] = true end
end

-- { [npc id] = true } for what the guide follows now.
function S.Wanted()
	local out = {}
	local M, Q = ns.QuestMarkers, ns.Quests
	if not (M and Q and ns.Data) then return out end
	local _, work = M.StepQuests()
	local log, tracked = M.LogQuests()
	for _, id in ipairs(log) do
		local q = Q.Get(id)
		if q and (work[id] or tracked[id]) and not Q.Ready(id) then
			local done = Q.Objectives(id)
			for i, o in ipairs(q[OBJECTIVES] or {}) do
				if not (done and done[i] and done[i].done) then
					local kind, oid = o[1], o[2]
					if kind == "m" then out[oid] = true
					elseif kind == "k" then for _, n in ipairs(o[4] or {}) do out[n] = true end
					elseif kind == "i" then addDrops(out, oid) end
				end
			end
		end
	end
	local E = ns.Engine
	for _, goal in ipairs(E and E.OpenGoals and E.OpenGoals() or {}) do
		if goal[1] == "have" and type(goal[2]) == "number" then addDrops(out, goal[2]) end
	end
	return out
end

-- The npc id in a unit's GUID, or nil (a player, a pet, a secret GUID).
function S.NpcId(unit)
	local guid = readable(call(UnitGUID, unit))
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

---------------------------------------------------------------------------
-- The motes
---------------------------------------------------------------------------

local shown = {} -- unit token -> sparkle frame
local pool = {}
local driver = CreateFrame("Frame")
local clock = 0

-- Each mote keeps its own pace, place and size, so the cloud never pulses
-- as one: a fixed spread (no randomness: the same every time it is drawn).
local MOTE = {}
for i = 1, MOTES do
	local f = (i * 0.618034) % 1 -- golden-ratio spread over 0..1
	MOTE[i] = {
		period = 1.5 + ((i * 0.37) % 1) * 1.1, -- 1.5 to 2.6 seconds
		offset = f, -- where in its rise it starts
		x = (f - 0.5) * WIDTH,
		y = ((i * 0.293) % 1) * (HEIGHT - RISE),
		size = 9 + ((i * 0.811) % 1) * 7, -- 9 to 16 pixels
		sway = ((i % 2 == 0) and 1 or -1) * (2 + (i % 3)),
	}
end

local function make()
	local f = CreateFrame("Frame")
	f:SetSize(WIDTH, HEIGHT)
	f.motes = {}
	for i = 1, MOTES do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetTexture(T.MEDIA .. "spark")
		t:SetBlendMode("ADD")
		t:SetVertexColor(COLOR[1], COLOR[2], COLOR[3])
		f.motes[i] = t
	end
	return f
end

-- Lay a sparkle out at time `now` (seconds): each mote rises, swaying a
-- little, fading in and out as it goes, and growing then shrinking.
function S.Draw(f, now)
	for i, t in ipairs(f.motes) do
		local m = MOTE[i]
		local p = ((now / m.period) + m.offset) % 1
		local glow = math.sin(p * math.pi) -- 0 at both ends, 1 midway
		local size = m.size * (0.55 + 0.45 * glow)
		t:ClearAllPoints()
		t:SetPoint("CENTER", f, "BOTTOM", m.x + m.sway * math.sin(p * math.pi * 2), m.y + p * RISE)
		t:SetSize(size, size)
		t:SetAlpha(0.9 * glow)
	end
end

local function attach(unit)
	local plate = call(C_NamePlate and C_NamePlate.GetNamePlateForUnit, unit)
	if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
	local f = shown[unit] or table.remove(pool) or make()
	f:SetParent(plate)
	f:ClearAllPoints()
	f:SetPoint("TOP", plate, "BOTTOM", 0, 4)
	f:SetFrameLevel((plate:GetFrameLevel() or 0) + 1)
	f:Show()
	shown[unit] = f
	S.Draw(f, clock)
end

local function detach(unit)
	local f = shown[unit]
	if not f then return end
	f:Hide()
	f:SetParent(nil)
	shown[unit] = nil
	pool[#pool + 1] = f
end

local function animate()
	if next(shown) then
		driver:SetScript("OnUpdate", function(_, elapsed)
			clock = clock + (elapsed or 0)
			for _, f in pairs(shown) do S.Draw(f, clock) end
		end)
	else
		driver:SetScript("OnUpdate", nil)
	end
end

local function wants(unit)
	if not ns.Get("sparkle.enabled") then return false end
	if readable(call(UnitIsDead, unit)) then return false end
	local id = S.NpcId(unit)
	return id ~= nil and wanted[id] == true
end

function S.Check(unit)
	if wants(unit) then attach(unit) else detach(unit) end
	animate()
end

function S.Refresh()
	wanted = S.Wanted()
	local list = C_NamePlate and call(C_NamePlate.GetNamePlates) or {}
	local seen = {}
	for _, plate in ipairs(type(list) == "table" and list or {}) do
		local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
		if type(unit) == "string" then seen[unit] = true S.Check(unit) end
	end
	for unit in pairs(shown) do if not seen[unit] then detach(unit) end end
	animate()
end

function S.Shown() return shown end

ns.RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) S.Check(unit) end)
ns.RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(_, unit) detach(unit) animate() end)
ns.On("PINS_CHANGED", S.Refresh)
ns.On("READY", S.Refresh)
ns.On("SETTING_CHANGED", function(path) if path == "sparkle.enabled" then S.Refresh() end end)
