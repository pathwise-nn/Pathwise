-- Pathwise Encounters' pages in its options window (Kit/Options.lua draws
-- them; the row kinds are listed there): Encounters first, then the look
-- and profile pages every Pathwise addon has.

local ADDON, ns = ...
local C = ns.Config
local D = ns.EncounterData
local E = ns.Enc

local function covered()
	local with, without = {}, {}
	for _, r in ipairs(D.RAIDS) do
		local n = 0
		for _, id in ipairs(r.ids) do if D.ENCOUNTERS[id] then n = n + 1 end end
		if n > 0 then with[#with + 1] = r.name else without[#without + 1] = r.name end
	end
	return with, without
end

local function pulls()
	local h = E.History()
	if #h == 0 then return "None yet: each boss you pull is kept here, kill or wipe, with how long it took." end
	local lines = {}
	for i = 1, math.min(6, #h) do
		local p = h[i]
		lines[i] = ("%s: %s, %s"):format(p.name, p.kill and "kill" or "wipe", E.Clock(p.seconds))
	end
	return table.concat(lines, ". ") .. "."
end

C.CATEGORIES = {
	{ key = "encounters", name = "Encounters", rows = function()
		local B = ns.EncBars
		local with, without = covered()
		return {
			{ "heading", "Boss timers" },
			{ "toggle", "Timer bars", "enc.bars", "A bar for each ability coming up, soonest on top, with the boss and the fight's time above them." },
			{ "toggle", "Warnings", "enc.warnings", "Big text in the middle of the screen: an ability soon, a new phase, the pull." },
			{ "toggle", "Sound", "enc.sound", "The raid warning sound with each warning." },
			{ "slider", "Warn this many seconds before", "enc.warnBefore", 2, 10, 1, "count" },
			{ "toggle", "Dungeon and world bosses", "enc.dungeons", "The boss's name and the fight's time for every boss, not only raid bosses." },
			{ "text", ("Pathwise's own timers cover %s. %s are recognised (name and time) but have no timers yet."):format(
				table.concat(with, " and "), table.concat(without, ", ")), "muted" },
			{ "text", "They are estimates: Forever hides a boss's casts from addons, so they count from the pull, and come from an open-source server's boss scripts, not yet timed on Forever. For Onyxia, type /pwenc phase 2 when she lifts off and /pwenc phase 3 when she lands.", "muted" },

			{ "heading", "The game's own boss warnings" },
			{ "toggle", "The game's timeline as bars", "enc.timeline", "When the game sends its own timers for a fight, they show here too, in the warning color." },
			{ "toggle", "The game's warnings in this style", "enc.gameWarnings" },
			{ "toggle", "Put Pathwise's timers on the game's timeline", "enc.pushTimeline", "For the game's own timeline display, if you use it." },

			{ "heading", "Size and place" },
			{ "slider", "Width", "enc.width", 160, 360, 4, "count" },
			{ "slider", "Bars at most", "enc.maxBars", 3, 12, 1, "count" },
			{ "button", B.Unlocked() and "Lock it" or "Move the timer bars", function() B.Unlock(not B.Unlocked()) end, B.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() B.ResetPosition() end },
			{ "button", "Show test bars", function() E.Test() end },
			{ "button", "Stop the test", function() E.Stop() end },

			{ "heading", "Pull, break and range" },
			{ "slider", "Pull countdown (seconds)", "enc.pull", 3, 30, 1, "count" },
			{ "slider", "Break (minutes)", "enc.breakMinutes", 1, 30, 1, "count" },
			{ "slider", "Range check (yards)", "enc.range", 5, 40, 1, "count" },
			{ "text", "/pwenc pull starts the game's countdown for your group (you may need to lead or assist). /pwenc break sends a break bar to the group. /pwenc range shows who is that close; Forever stops telling addons distances in a boss fight. Add a number to any of them; 0 cancels a pull or break.", "muted" },

			{ "heading", "Your pulls" },
			{ "text", pulls(), "muted" },
			{ "button", "Clear them", function()
				local h = E.History()
				for i = #h, 1, -1 do h[i] = nil end
				C.Show("encounters")
			end },
		}
	end },

	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}
