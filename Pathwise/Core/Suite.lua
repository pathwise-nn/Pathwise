-- Pathwise.Suite: what the other Pathwise addons (Pathwise_Gear, ...) use, so
-- they look, save and behave like Pathwise. Loaded last: every module exists.
--
--   S.Theme                    the Signature theme (each addon has an accent in Theme.MODULES)
--   S.Get(path) / S.Set(path, value) / S.Defaults(section, defaults)
--   S.On(message, fn) / S.Fire(message, ...) / S.RegisterEvent(event, fn)
--   S.Print(...), S.Error(where, err), S.CharState(), S.Compat, S.VERSION
--   S.Panel(kind, builder)     a side panel of rows (UI/Panels.lua's row kinds)
--   S.Open(kind) / S.Refresh() / S.Close() / S.Back() / S.CanGoBack()
--   S.CloseButtons(extra) -> the bottom row: Back (when there is one), extra, Close
--   S.RegisterModule({ key, name, accent, about, open = fn })
--       lists the addon in Settings > Pathwise suite; open() shows its panel.
--   S.Modules() -> { module, ... }
--   S.Data, S.Quests, S.Dungeons, S.SetWaypoint: see below
--   S.MinimapButton(def)       the addon's own minimap button

local ADDON, ns = ...
local S = {}
Pathwise.Suite = S

S.Theme = ns.Theme
S.Compat = ns.Compat
S.VERSION = ns.VERSION
S.Get, S.Set, S.Defaults = ns.Get, ns.Set, ns.Defaults
S.On, S.Fire, S.RegisterEvent = ns.On, ns.Fire, ns.RegisterEvent
S.Print, S.Error, S.CharState = ns.Print, ns.Error, ns.CharState

-- Pathwise's facts, for the suite's addons to read (never change them):
--   S.Data       Data/Data.lua (quests, npcs, items, gear, dungeons, zones)
--   S.Quests     Guide/Quests.lua (Name, Player, ForPlayer, Done, Giver, Nearest, ...)
--   S.Dungeons   Guide/Dungeons.lua (Get, GuideTo, ...)
--   S.Professions Professions/Professions.lua (Known, Recipes, BY_LINE)
--   S.SetWaypoint(map, x, y, title)   point the arrow
S.Data = ns.Data
S.Quests = ns.Quests
S.Dungeons = ns.Dungeons
S.Professions = ns.Professions -- Known(), Recipes(line), BY_LINE
function S.SetWaypoint(map, x, y, title) return ns.Nav.SetTarget(map, x, y, title) end

function S.Panel(kind, builder) ns.Panels.Register(kind, builder) end
function S.Open(kind) ns.Panels.Open(kind) end
function S.Refresh() ns.Panels.Refresh() end
function S.Close() ns.Panels.Close() end
function S.IsOpen(kind) return ns.Panels.IsOpen(kind) end
function S.Back() return ns.Panels.Back() end
function S.CanGoBack() return ns.Panels.CanGoBack() end
-- The bottom row of a suite panel: Back (when it came from another panel) and Close.
function S.CloseButtons(extra)
	local list = {}
	if ns.Panels.CanGoBack() then list[#list + 1] = { "Back", "default", function() ns.Panels.Back() end } end
	for _, b in ipairs(extra or {}) do list[#list + 1] = b end
	list[#list + 1] = { "Close", "default", S.Close }
	return { "buttons", list }
end
-- A minimap button of the suite addon's own (UI/MinimapButton.lua, MB.Make):
-- call it at READY. def = { key, name, shownPath, anglePath, accent, glyph, lines,
-- onClick(which), panels = { kinds } } -- those panels open beside the button.
function S.MinimapButton(def)
	if not (ns.MinimapButton and Minimap) then return nil end
	local b = ns.MinimapButton.Make(def)
	for _, kind in ipairs(def.panels or {}) do ns.Panels.SetHome(kind, function() return b end) end
	return b
end
function S.InputText(key) return ns.Panels.InputText(key) end
function S.ClearInput(key) ns.Panels.ClearInput(key) end

local modules = {}
function S.RegisterModule(def)
	if type(def) ~= "table" or type(def.key) ~= "string" then return false end
	for i, m in ipairs(modules) do
		if m.key == def.key then modules[i] = def return true end
	end
	modules[#modules + 1] = def
	ns.Fire("SUITE_CHANGED")
	return true
end
function S.Modules() return modules end
ns.Suite = S
