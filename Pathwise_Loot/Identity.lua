-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "loot", -- in Pathwise's suite list
	name = "Pathwise Loot",
	global = "PathwiseLoot", -- _G.PathwiseLoot = ns, and the prefix of its frame names
	saved = "PathwiseLootSettings",
	charSaved = "PathwiseLootCharSettings",
	slashKey = "PATHWISELOOT",
	slash = { "/pwloot", "/pathwiseloot" },
	about = "What every dungeon and raid boss drops, and a wishlist",
	minimapAngle = 160,
	color = "#A970FF", -- the logo's purple: its minimap button's mark
}
