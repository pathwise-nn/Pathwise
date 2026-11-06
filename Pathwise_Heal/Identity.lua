-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "heal", -- in Pathwise's suite list
	name = "Pathwise Heal",
	global = "PathwiseHeal", -- _G.PathwiseHeal = ns, and the prefix of its frame names
	saved = "PathwiseHealSettings",
	charSaved = "PathwiseHealCharSettings",
	slashKey = "PATHWISEHEAL",
	slash = { "/pwheal", "/pathwiseheal" },
	about = "Click-to-heal party and raid frames, with a preset for every healing spec",
	minimapAngle = 155,
	color = "#FF6EB4", -- the logo's pink: its minimap button's mark
}
