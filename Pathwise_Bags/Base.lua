-- Pathwise Bags stands on its own. This is what it uses from the kit
-- (Kit/Core.lua: settings, messages, events), and from Pathwise: Leveling &
-- Professions and Pathwise Gear when they are installed too:
--
--   ns.S        settings, messages and events, plus:
--     S.Pathwise()      Pathwise's suite API, or nil
--     S.QuestData()     Pathwise's quests and quest facts (Data, Quests), or nil:
--                       which quests ask for an item, later as well as now
--     S.QuestName(q)    a quest's name: Pathwise's data, else the game's
--     S.Professions()   Pathwise's professions (Known, Shopping), or nil:
--                       the materials your profession routes ask for
--     S.Gear()          Pathwise Gear (IsUpgrade, Compare), or nil
--     S.GearBest()      Pathwise Gear's best in slot, or nil
--   ns.Look     the kit's theme (Kit/Theme.lua, Kit/Widgets.lua), with the
--               few things the bag window draws that the kit has no call for.
--
-- Without Pathwise, an item is a quest item when the game says so (its quest
-- info, or the Quest item class); profession route materials and gear
-- upgrades are not marked. Everything else works the same.
--
-- Settings and marks from before (when Pathwise Bags kept them in Pathwise's
-- saved variables) are copied over once, on the first login with this
-- version.

local ADDON, ns = ...
local T = ns.Theme

local S = {
	Get = ns.Get, Set = ns.Set, Defaults = ns.Defaults,
	On = ns.On, Fire = ns.Fire, RegisterEvent = ns.RegisterEvent, Print = ns.Print,
	Readable = ns.Readable,
}
ns.S = S

local function readable(v) return ns.Readable(v) end

function S.Pathwise() return _G.Pathwise and _G.Pathwise.Suite or nil end

function S.QuestData()
	local P = S.Pathwise()
	if P and P.Data and P.Quests then return P.Data, P.Quests end
end

function S.QuestName(q)
	local P = S.Pathwise()
	if P and P.Quests and P.Quests.Name then return P.Quests.Name(q) end
	local C = C_QuestLog
	local ok, t = false, nil
	if C and C.GetTitleForQuestID then ok, t = pcall(C.GetTitleForQuestID, q) end
	t = ok and readable(t) or nil
	if type(t) == "string" and t ~= "" then return t end
	return "Quest " .. tostring(q)
end

function S.Professions()
	local P = S.Pathwise()
	return P and P.Professions or nil
end

-- Pathwise Gear on its own (its ns), or as Pathwise had it before.
local function gear() return _G.PathwiseGear end
function S.Gear() local G = gear() return G and G.Gear or (_G.Pathwise and _G.Pathwise.Gear) or nil end
function S.GearBest() local G = gear() return G and G.Best or (_G.Pathwise and _G.Pathwise.GearBest) or nil end

---------------------------------------------------------------------------
-- The look: the kit's theme, and what the bag window adds to it
---------------------------------------------------------------------------

local L = setmetatable({}, { __index = T })
ns.Look = L

-- A soft 1 px shadow, for the item level drawn on an item's icon.
function L.Shadow(fs)
	if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
	if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0.85) end
end

-- A 1 px line across a window.
function L.Divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	T.Paint(t, "divider")
	return t
end

-- An icon button whose glyph can change (the mark button: coin or lock).
function L.IconButton(parent, glyph, tip, onClick, size)
	local b = T.IconButton(parent, glyph, tip, onClick, size)
	function b:SetGlyph(name) self.pwIcon:SetTexture(T.MEDIA .. "glyph-" .. name) end
	return b
end

---------------------------------------------------------------------------
-- Settings and marks from before: copied once from Pathwise's saved variables
---------------------------------------------------------------------------

-- Pathwise's "bags.minimap" and "bags.minimapAngle" are the kit's minimap settings.
local RENAMED = { minimap = "minimap.shown", minimapAngle = "minimap.angle" }

function S.ImportFromPathwise()
	local done = ns.Data("import")
	if not done.settings then
		done.settings = true
		local old = type(PathwiseSettings) == "table" and PathwiseSettings.bags
		if type(old) == "table" then
			for k, v in pairs(old) do
				if type(k) == "string" and k ~= "marks" then S.Set(RENAMED[k] or ("bags." .. k), v) end
			end
		end
	end
	local mine = ns.CharData("import")
	if not mine.marks then
		mine.marks = true
		local c = type(PathwiseCharSettings) == "table" and PathwiseCharSettings.bags
		local old = type(c) == "table" and c.marks
		if type(old) == "table" then
			local marks = ns.CharData("marks")
			for id, what in pairs(old) do
				if marks[id] == nil and (what == "keep" or what == "junk") then marks[id] = what end
			end
		end
	end
end
ns.On("LOADED", S.ImportFromPathwise)
