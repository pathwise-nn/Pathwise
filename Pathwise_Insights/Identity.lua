-- Who this addon is, for the shared files in Kit/ (copied from Pathwise UI by
-- tools/kit.js): its name, global table, saved variables and slash commands.
-- Loaded first.

local ADDON, ns = ...
ns.ID = {
	key = "insights", -- in Pathwise's suite list
	name = "Pathwise Insights",
	global = "PathwiseInsights", -- _G.PathwiseInsights = ns, and the prefix of its frame names
	saved = "PathwiseInsightsSettings",
	charSaved = "PathwiseInsightsCharSettings",
	slashKey = "PATHWISEINSIGHTS",
	slash = { "/pwinsights", "/pathwiseinsights" },
	about = "Your leveling numbers, records and a heat map of where you went",
	minimapAngle = 165,
	color = "#C7E86A", -- its minimap button's mark
}
