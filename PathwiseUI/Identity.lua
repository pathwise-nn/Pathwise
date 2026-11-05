-- Who this addon is, for the shared files (Core, Theme, Anim, Widgets,
-- Movers, Options, Minimap) that Pathwise UI and Pathwise Heal both carry:
-- its name, global table, saved variables and slash commands. Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "ui", -- in Pathwise's suite list
	name = "Pathwise UI",
	global = "PathwiseUI", -- _G.PathwiseUI = ns, and the prefix of its frame names
	saved = "PathwiseUISettings",
	charSaved = "PathwiseUICharSettings",
	slashKey = "PATHWISEUI",
	slash = { "/pwui", "/pathwiseui" },
	about = "Your whole interface in the Pathwise look, in your color",
	minimapAngle = 135,
}
