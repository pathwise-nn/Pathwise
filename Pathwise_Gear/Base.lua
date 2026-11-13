-- Pathwise Gear stands on its own. This is what it uses from the game, and
-- from Pathwise: Leveling & Professions when that is installed too:
--
--   ns.S      settings, messages and events (the kit, Kit/Core.lua), plus:
--     S.Compat      Readable, SpellKnown, PlayerMapPosition
--     S.Theme       Color(name): the kit's colours, and "gear" (gold)
--     S.Open/Refresh/IsOpen   Gear's pages in its own options window
--     S.Data, S.Quests, S.Dungeons, S.Professions, S.SetWaypoint
--                   Pathwise's (its data, its arrow), else Gear's own
--                   (Facts.lua: Data/Gear.lua and the game's map pin)
--     S.SetRewardChooser      Pathwise's quest automation, or nil
--
-- Everything works without Pathwise; with it, Best in Slot uses Pathwise's
-- data and arrow.

local ADDON, ns = ...
local T = ns.Theme

local function pathwise() return _G.Pathwise and _G.Pathwise.Suite or nil end
ns.Pathwise = pathwise

-- Pathwise's facts and its arrow, read when asked; without Pathwise, Gear's
-- own (Facts.lua), but no quest automation to hand the reward pick to.
local FROM_PATHWISE = { Data = true, Quests = true, Dungeons = true, Professions = true, SetWaypoint = true, SetRewardChooser = true }
local S = setmetatable({
	Get = ns.Get, Set = ns.Set, Defaults = ns.Defaults,
	On = ns.On, Fire = ns.Fire, RegisterEvent = ns.RegisterEvent, Print = ns.Print,
}, { __index = function(_, k)
	if FROM_PATHWISE[k] then
		local P = pathwise()
		if P and P[k] then return P[k] end
		return ns.Facts and ns.Facts[k] or nil
	end
end })
ns.S = S

local readable = ns.Readable

S.Compat = { Readable = readable }

-- Does the character know this spell (Dual Wield, a recipe)?
function S.Compat.SpellKnown(spell)
	if not spell then return false end
	if C_SpellBook and C_SpellBook.IsSpellKnown and readable(C_SpellBook.IsSpellKnown(spell)) then return true end
	if IsPlayerSpell and readable(IsPlayerSpell(spell)) then return true end
	if IsSpellKnown and readable(IsSpellKnown(spell)) then return true end
	return false
end

-- Where you stand: map, x, y (0-100). Pathwise's, else the game's.
function S.Compat.PlayerMapPosition()
	local P = pathwise()
	if P and P.Compat and P.Compat.PlayerMapPosition then return P.Compat.PlayerMapPosition() end
	local M = C_Map
	if not (M and M.GetBestMapForUnit and M.GetPlayerMapPosition) then return nil end
	local map = readable(M.GetBestMapForUnit("player"))
	local pos = map and M.GetPlayerMapPosition(map, "player")
	if not pos then return nil end
	local x, y
	if pos.GetXY then x, y = pos:GetXY() else x, y = pos.x, pos.y end
	x, y = readable(x), readable(y)
	if not (x and y) then return nil end
	return map, x * 100, y * 100
end

---------------------------------------------------------------------------
-- Colours: the kit's theme, and Pathwise Gear's gold
---------------------------------------------------------------------------

local GOLD = T.Hex(ns.ID.color)
S.Theme = { MEDIA = T.MEDIA }
function S.Theme.Color(name)
	if name == "gear" then
		-- With Pathwise, its gold (or its accent, with one colour for the whole suite).
		local P = pathwise()
		if P and P.Theme and P.Theme.Color then return P.Theme.Color("gear") end
		return GOLD
	end
	return T.Color(name)
end

---------------------------------------------------------------------------
-- Pages: Gear's own options window (Kit/Options.lua, Pages.lua)
---------------------------------------------------------------------------

function S.Open(key) if ns.Config then ns.Config.Show(key) end end
function S.IsOpen(key)
	local C = ns.Config
	local f = C and C.Frame()
	if not (f and f:IsShown()) then return false end
	return key == nil or (C.Current() or (C.CATEGORIES[1] and C.CATEGORIES[1].key)) == key
end
function S.Refresh() if S.IsOpen() then ns.Config.Render() end end

---------------------------------------------------------------------------
-- Settings from before: Pathwise Gear's settings were kept in Pathwise's.
-- Once, the first time Pathwise Gear has its own, they are copied over.
---------------------------------------------------------------------------

local KEYS = { "minUpgrade", "tooltip", "bags", "rewards", "spec", "scales", "scale",
	"bisAhead", "bisRaids", "bisCrafted", "bisSod", "bisAlert" }

local function copy(v)
	if type(v) ~= "table" then return v end
	local t = {}
	for k, x in pairs(v) do t[k] = copy(x) end
	return t
end

function ns.MoveSettings()
	local moved = ns.Data("moved")
	if moved.fromPathwise then return false end
	-- Only the first time: settings made in Pathwise Gear since then win.
	moved.fromPathwise = true
	local P = pathwise()
	if not (P and P.Get) then return false end
	local n = 0
	for _, k in ipairs(KEYS) do
		local v = P.Get("gear." .. k)
		if v ~= nil then ns.Set("gear." .. k, copy(v)) n = n + 1 end
	end
	local shown, angle = P.Get("gear.minimap"), P.Get("gear.minimapAngle")
	if shown ~= nil then ns.Set("minimap.shown", shown and true or false) end
	if type(angle) == "number" then ns.Set("minimap.angle", angle) end
	return n > 0
end
ns.On("READY", function() ns.MoveSettings() end)
