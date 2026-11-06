-- Pathwise Heal's pages in its options window (Kit/Options.lua draws them;
-- the row kinds are listed there): Healing first, then the look and profile
-- pages every Pathwise addon has.

local ADDON, ns = ...
local T = ns.Theme
local C = ns.Config

C.CATEGORIES = {
	{ key = "heal", name = "Healing", rows = function()
		local H = ns.Heal
		local rows = {
			{ "heading", "Healing frames" },
			{ "toggle", "Healing frames", "heal.enabled", "Your party or raid as bars built for healing: click someone to heal them, see heals on the way, debuffs you can cleanse, your HoTs, aggro and range. Off by default; healers are asked once." },
		}
		if not ns.Get("heal.enabled") then
			rows[#rows + 1] = { "text", "Turn them on to set them up: how they look, and what each click casts.", "muted" }
			return rows
		end
		for _, r in ipairs({
			{ "toggle", "Show when you're on your own", "heal.solo", "Your own frame when you're not in a group." },
			{ "heading", "What they show" },
			{ "choice", "Health color", "heal.color", { key = "hcol", { "Class", "class" }, { "Green", "green" }, { "By health", "health" } },
				"By health: green, turning yellow then red as it drops." },
			{ "choice", "Health text", "heal.text", { key = "htxt", { "Missing", "deficit" }, { "Percent", "percent" }, { "None", "none" } },
				"Missing: how much they need (-1.2k), blank when full." },
			{ "toggle", "Heals on the way", "heal.incoming", "A lighter bar past their health: heals being cast on them." },
			{ "toggle", "Debuffs you can cleanse", "heal.dispel", "Drawn by the game in each frame, in combat too; out of combat the frame's edge also takes the debuff's color." },
			{ "toggle", "Your HoTs", "heal.hots", "Your heals over time and shields, top right. Forever hides auras from addons in a fight, so these show between fights." },
			{ "toggle", "Aggro", "heal.aggro", "A red edge around whoever the enemy is hitting, when the game says so." },
			{ "toggle", "Mana bars", "heal.mana" },
			{ "toggle", "Fade when out of range", "heal.range" },
			{ "slider", "How faded", "heal.rangeAlpha", 0.1, 0.9, 0.05, "percent" },
			{ "heading", "Size and place" },
			{ "slider", "Width", "heal.width", 50, 160, 2, "count" },
			{ "slider", "Height", "heal.height", 24, 80, 1, "count" },
			{ "slider", "Space between", "heal.spacing", 0, 10, 1, "count" },
			{ "choice", "Groups", "heal.grow", { key = "hgrow", { "In columns", "down" }, { "In rows", "right" } } },
			{ "button", H.Unlocked() and "Lock it" or "Move the healing frames", function() H.Unlock(not H.Unlocked()) end, H.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() H.ResetPosition() end },
			{ "toggle", "Hide the game's party and raid frames", "heal.hideGame", "Off brings them back after a reload." },
			_G.PathwiseUI and { "toggle", "Hide Pathwise UI's party frames", "heal.hideParty", "These show your party already." } or false, -- false, not nil: ipairs stops at nil

			{ "heading", "Click-casting" },
		}) do if r then rows[#rows + 1] = r end end
		local C = ns.HealClicks
		local spec, how = C.Spec()
		local options = { { "Follow my talents", "auto" } }
		for _, s in ipairs(C.Specs()) do options[#options + 1] = { s.label, s.key } end
		rows[#rows + 1] = { "dropdown", "Spec", { get = function() return how == "chosen" and spec.key or "auto" end, set = C.SetSpec }, options,
			("Your clicks follow the %s preset%s. Its spells fill in as you learn them; a click you set yourself is never changed."):format(spec.label,
				how == "auto" and " (from your talents)" or "") }
		local talents = {}
		for _, list in pairs(spec.binds) do
			for _, name in ipairs(list) do
				if C.NOTES[name] then talents[#talents + 1] = ("%s: %s"):format(name, C.NOTES[name]) end
			end
		end
		table.sort(talents)
		if #talents > 0 then
			rows[#rows + 1] = { "text", table.concat(talents, ". ") .. ". Forever's new spells are named from its previews and not yet checked in game: a name the game doesn't know is skipped.", "muted" }
		end
		rows[#rows + 1] = { "text", "What each click on a frame does. Type a spell's name (your highest rank is cast), target or menu, then Enter; or drag a spell from your spellbook onto a box. Empty does nothing.", "muted" }
		for _, c in ipairs(C.COMBOS) do rows[#rows + 1] = { "bind", c[2], c[1] } end
		rows[#rows + 1] = { "button", ("Use the %s preset (replaces your own clicks)"):format(spec.label), function() C.Defaults(true) end }
		return rows
	end },

	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}
