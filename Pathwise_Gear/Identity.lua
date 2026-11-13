-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "gear", -- in Pathwise's suite list
	name = "Pathwise Gear",
	global = "PathwiseGear", -- _G.PathwiseGear = ns, and the prefix of its frame names
	saved = "PathwiseGearSettings",
	charSaved = "PathwiseGearCharSettings",
	slashKey = "PATHWISEGEAR",
	slash = { "/pwgear", "/pathwisegear" },
	about = "Upgrades, stat priority, best quest rewards",
	minimapAngle = 195,
	color = "#E8C26A", -- Pathwise Gear's gold: its minimap button's mark
}
