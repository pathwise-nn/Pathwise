-- Pathwise Loot's pages in its options window (Kit/Options.lua draws them;
-- the row kinds are listed there): Loot first, then the look and profile
-- pages every Pathwise addon has. The loot browser is its own window
-- (Loot/Browser.lua).

local ADDON, ns = ...
local C = ns.Config
local D = ns.LootData
local L = ns.Loot

-- How much the data and your own drops know.
local function counts()
	local bosses, withLoot, instances = 0, 0, #D.INSTANCES
	for _, e in pairs(D.ENCOUNTERS) do
		bosses = bosses + 1
		if #e[5] > 0 then withLoot = withLoot + 1 end
	end
	local seenBosses, seenDrops = 0, 0
	for _, s in pairs(L.Seen()) do
		if type(s) == "table" and type(s.items) == "table" and next(s.items) then
			seenBosses = seenBosses + 1
			for _ in pairs(s.items) do seenDrops = seenDrops + 1 end
		end
	end
	return instances, bosses, withLoot, seenBosses, seenDrops
end

C.CATEGORIES = {
	{ key = "loot", name = "Loot", rows = function()
		local instances, bosses, withLoot, seenBosses, seenDrops = counts()
		return {
			{ "heading", "The loot browser" },
			{ "button", "Open the loot browser", function() C.Hide() ns.LootBrowser.Show() end, "accent" },
			{ "text", ("%s or a click on the minimap button opens it; right-click the button for these options. %s search finds an item in every boss's loot."):format(ns.ID.slash[1], ns.ID.slash[1]), "muted" },

			{ "heading", "What it knows" },
			{ "text", ("%d bosses in %d dungeons and raids, from Forever's own boss list. QuestieDB's Forever data names drops for %d of them; the rest fill in as you see them drop. There are no drop chances: the data has none."):format(bosses, instances, withLoot), "muted" },
			{ "text", seenDrops > 0 and ("You have seen %d different drops from %d bosses."):format(seenDrops, seenBosses) or "You have not seen any drops yet.", "muted" },
			{ "toggle", "Keep the drops you see", "loot.learn", "Loot from a boss you kill (its corpse, the group's loot rolls, what you receive) is added to that boss, on every character." },
			{ "toggle", "Drops from, on item tooltips", "loot.tooltip", "Which boss drops an item, on the game's item tooltips." },
			{ "toggle", "Upgrade marks from Pathwise Gear", "loot.gear", L.HasGear() and "Items Pathwise Gear says are an upgrade for your spec show by how much." or "Needs Pathwise Gear (it needs Pathwise); without it, nothing shows." },

			{ "heading", "Your drops" },
			{ "button", "Forget the drops you have seen", function()
				local seen = L.Seen()
				for k in pairs(seen) do seen[k] = nil end
				L.Rebuild()
				ns.Fire("LOOT_SEEN")
				C.Show("loot")
			end },
		}
	end },

	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}
