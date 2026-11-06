-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "encounters", -- in Pathwise's suite list
	name = "Pathwise Encounters",
	global = "PathwiseEncounters", -- _G.PathwiseEncounters = ns, and the prefix of its frame names
	saved = "PathwiseEncountersSettings",
	charSaved = "PathwiseEncountersCharSettings",
	slashKey = "PATHWISEENCOUNTERS",
	slash = { "/pwenc", "/pathwiseencounters" },
	about = "Boss timers, warnings, pull and break timers for raids",
	minimapAngle = 125,
	color = "#FF4D4D", -- the logo's red: its minimap button's mark
}
