-- Pathwise Insights' pages in its options window (Kit/Options.lua draws them;
-- the row kinds are listed there): Insights first, then the look and profile
-- pages every Pathwise addon has. The numbers are their own window
-- (Window.lua).

local ADDON, ns = ...
local C = ns.Config

C.CATEGORIES = {
	{ key = "insights", name = "Insights", rows = function()
		local guide = ns.S.Guide.Available()
		return {
			{ "heading", "Your numbers" },
			{ "button", "Open Pathwise Insights", function() C.Hide() ns.Window.Open() end, "accent" },
			{ "text", ("%s or a click on the minimap button opens it; right-click the button for these options. %s map opens the map, %s share the Share tab."):format(ns.ID.slash[1], ns.ID.slash[1], ns.ID.slash[1]), "muted" },
			{ "toggle", "Record", "insights.record", "Time played, XP, quests, kills, deaths and where you went, for every character. Time AFK and loading screens are not counted." },
			{ "heading", "Guide steps" },
			{ "text", guide and "Pathwise: Leveling & Professions is installed: each guide step's time is recorded too."
				or "Install Pathwise: Leveling & Professions to time each guide step and route as well. Everything else works without it.", "muted" },
			{ "heading", "Your data" },
			{ "text", "Kept on your computer, for every character on this account. Hide or delete a character from its tab in the window.", "muted" },
		}
	end },

	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}
