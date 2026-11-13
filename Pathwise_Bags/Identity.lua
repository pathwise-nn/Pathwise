-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "bags", -- in Pathwise's suite list
	name = "Pathwise Bags",
	global = "PathwiseBags", -- _G.PathwiseBags = ns, and the prefix of its frame names
	saved = "PathwiseBagsSettings",
	charSaved = "PathwiseBagsCharSettings",
	slashKey = "PATHWISEBAGS",
	slash = { "/pwbags", "/pathwisebags" },
	about = "One bag window, keep and sell markers, junk selling, bag space",
	minimapAngle = 165,
	color = "#7FD98F", -- Pathwise Bags' green: its minimap button's mark
}
