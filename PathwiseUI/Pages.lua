-- Pathwise UI's pages in its options window (Options.lua draws them; the row
-- kinds are listed there).

local ADDON, ns = ...
local T = ns.Theme
local C = ns.Config


C.CATEGORIES = {
	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "units", name = "Unit frames", rows = function()
		local U = ns.Units
		return {
			{ "heading", "Unit frames" },
			{ "toggle", "Pathwise unit frames", "units.enabled", "You, your target and the rest in the Pathwise look. Click: target; right-click: the menu." },
			{ "toggle", "You", "units.player" },
			{ "toggle", "Your target", "units.target" },
			{ "toggle", "Your target's target", "units.targettarget" },
			{ "toggle", "Your pet", "units.pet" },
			{ "toggle", "Your focus", "units.focus" },
			{ "toggle", "Your party", "units.party" },
			{ "heading", "What they show" },
			{ "choice", "Look", "units.style", { key = "us", { "Slim", "slim" }, { "Full bars", "full" } } },
			{ "text", "Slim: Pathwise's look, the name and health on the dark ground over slim bars. Full bars: the bars fill the frame, the text on them.", "muted" },
			{ "choice", "Health text", "units.healthText", { key = "ht", { "Auto", "auto" }, { "Numbers", "both" }, { "Current", "current" }, { "Percent", "percent" }, { "Both", "full" }, { "None", "none" } },
				"Numbers: 543 / 587. Percent: 93%. Both: 543 / 587 · 93%. Percent is not yet checked on Forever; Current always works." },
			{ "choice", "Health color", "units.healthColor", { key = "hc", { "Class", "class" }, { "Accent", "accent" }, { "Dark", "dark" } },
				"Class: players by class, others red, yellow or green by how they see you." },
			{ "toggle", "Outlined text", "units.outline", "Names and numbers on the bars get a black outline so they read on any color. Off: a soft shadow." },
			{ "toggle", "Smooth bars", "units.smooth", "Health and power glide to their new value instead of jumping." },
			{ "toggle", "Power numbers", "units.powerText", "Mana, rage or energy beside the health, in its color." },
			{ "choice", "Power text", "units.powerFormat", { key = "pt", { "Auto", "auto" }, { "Numbers", "both" }, { "Current", "current" }, { "Percent", "percent" }, { "Both", "full" } },
				"As the health text. Auto: numbers on you and your target, the current one on the rest." },
			{ "toggle", "Buffs and debuffs on you and your target, debuffs on party", "units.auras", "Curses, poisons, magic and diseases framed in their color." },
			{ "toggle", "Only your own debuffs", "units.onlyMyDebuffs" },
			{ "toggle", "Cast bars", "units.castbars" },
			{ "choice", "Your cast bar", "units.castbarSpot", { key = "cbs", { "Over the action bars", "bars" }, { "Under your frame", "frame" }, { "The game's", "game" } } },
			{ "text", "Pathwise's bar shows your casts in place of the game's. The game's comes back after a reload.", "muted" },
			{ "toggle", "Portraits", "units.portraits" },
			{ "heading", "Size and place" },
			{ "slider", "Your width", "units.PlayerW", 140, 360, 2, "count" },
			{ "slider", "Your height", "units.PlayerH", 24, 80, 1, "count" },
			{ "slider", "Target width", "units.TargetW", 140, 360, 2, "count" },
			{ "slider", "Target height", "units.TargetH", 24, 80, 1, "count" },
			{ "button", U.Unlocked() and "Lock the frames" or "Move the frames", function() U.Unlock(not U.Unlocked()) end, U.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() U.ResetPositions() end },
			{ "toggle", "Hide the game's unit frames", "units.hideBlizzard", "Off brings them back after a reload." },
		}
	end },
	{ key = "bars", name = "Action bars", rows = function()
		local B = ns.Bars
		local per = { key = "per", { "12", 12 }, { "6", 6 }, { "4", 4 }, { "3", 3 }, { "2", 2 }, { "1", 1 } }
		local rows = {
			{ "heading", "Action bars" },
			{ "toggle", "Pathwise action bars", "bars.enabled", "The game's own buttons (your spells stay where they are), in the Pathwise look. Your keys keep working." },
		}
		for _, def in ipairs(B.DEFS) do rows[#rows + 1] = { "toggle", def.label, "bars." .. def.name } end
		rows[#rows + 1] = { "heading", "Buttons per row" }
		for _, def in ipairs(B.DEFS) do rows[#rows + 1] = { "choice", def.label, "bars." .. def.name .. "Per", per } end
		for _, r in ipairs({
			{ "heading", "Look" },
			{ "slider", "Button size", "bars.size", 24, 52, 1, "count" },
			{ "slider", "Space between", "bars.spacing", 0, 10, 1, "count" },
			{ "toggle", "Key names", "bars.hotkeys" },
			{ "toggle", "Macro names", "bars.macroNames" },
			{ "toggle", "Empty slots", "bars.emptySlots", "Off: an empty slot only shows while you drag a spell." },
			{ "toggle", "Soft out of combat", "bars.fade", "Bars fade out of combat; back in combat or under the mouse." },
			{ "slider", "How soft", "bars.fadeAlpha", 0, 0.9, 0.05, "percent" },
			{ "heading", "Place" },
			{ "button", B.Unlocked() and "Lock the bars" or "Move the bars", function() B.Unlock(not B.Unlocked()) end, B.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() B.ResetPositions() end },
			{ "toggle", "Hide the game's action bars", "bars.hideBlizzard", "Off brings them back after a reload. The stance and pet bars stay the game's for now (move them in Edit Mode)." },
		}) do rows[#rows + 1] = r end
		return rows
	end },
	{ key = "plates", name = "Nameplates", rows = function() return {
		{ "heading", "Nameplates" },
		{ "toggle", "Pathwise nameplates", "plates.enabled", "A slim bar over each monster and player in the game's own health colors, the name, your target framed in your color." },
		{ "toggle", "Friendly ones too", "plates.friendly", "Where the game lets addons: friendly plates inside instances stay the game's." },
		{ "slider", "Width", "plates.width", 80, 220, 2, "count" },
		{ "slider", "Height", "plates.height", 6, 24, 1, "count" },
		{ "slider", "Your target bigger by", "plates.targetScale", 1, 1.5, 0.05, "percent" },
		{ "choice", "Health text", "plates.healthText", { key = "pht", { "None", "none" }, { "Current", "current" }, { "Percent", "percent" } } },
		{ "toggle", "Enemy players in class color", "plates.classColors" },
		{ "toggle", "Threat colors", "plates.threat", "Health in the game's threat colors, when the game shares threat. Off, as on the game's own plates." },
		{ "toggle", "Cast bars", "plates.castbars" },
		{ "toggle", "Your debuffs", "plates.debuffs" },
	} end },
	{ key = "bottom", name = "Tray, money, XP", rows = function()
		local Tr = ns.Tray
		return {
			{ "heading", "Money" },
			{ "toggle", "Money always shown", "money.enabled", "Your gold, silver and copper above the bags. Hover: this session's change and your other characters; click: your bags." },
			{ "choice", "Show", "money.style", { key = "ms", { "All coins", "full" }, { "Gold only", "gold" }, { "Short", "short" } },
				"Short: 12.3k g once you have a thousand gold or more." },
			{ "toggle", "This session in the tooltip", "money.session" },
			{ "toggle", "Your other characters in the tooltip", "money.characters", "Characters on this realm, from the last time each logged in. /pwui forget Name drops one." },
			{ "button", "Put it back where it was", function() ns.Money.ResetPosition() end },
			{ "heading", "Experience bar" },
			{ "toggle", "Pathwise experience bar", "xp.enabled", "A thin bar in your color under the main bar, rested experience ahead of it; your watched reputation at the level cap." },
			{ "toggle", "Numbers always shown", "xp.text", "Off: the numbers fade in when the mouse is over it." },
			{ "slider", "Height", "xp.height", 4, 20, 1, "count" },
			{ "toggle", "As wide as the main bar", "xp.matchBar", "And right under it, wherever you move it." },
			{ "toggle", "Hide the game's experience bar", "xp.hideBlizzard", "Off brings it back after a reload." },
			{ "heading", "System tray and bags" },
			{ "toggle", "Pathwise tray", "tray.enabled", "The game's own character, spellbook, quest, social, map and menu buttons, and your bags, as slots like the action bars." },
			{ "toggle", "Tray buttons", "tray.micro" },
			{ "toggle", "Bag buttons", "tray.bags" },
			{ "slider", "Button size", "tray.size", 20, 40, 1, "count" },
			{ "slider", "Space between", "tray.spacing", 0, 8, 1, "count" },
			{ "button", Tr.Unlocked() and "Lock the tray" or "Move the tray and bags", function() Tr.Unlock(not Tr.Unlocked()) end, Tr.Unlocked() and "accent" or "default" },
			{ "button", "Put them back where they were", function() Tr.ResetPositions() end },
			{ "text", "Turning the tray off brings the game's own back after a reload.", "muted" },
		}
	end },
	{ key = "fonts", name = "Fonts", rows = function() return {
		{ "heading", "Fonts" },
		{ "toggle", "Pathwise font everywhere", "fonts.pathwise", "Inter for every text of the game: menus, chat, tooltips, quests. Off puts the game's own back." },
		{ "slider", "Text size", "fonts.scale", 0.8, 1.3, 0.05, "percent" },
		{ "text", "Names over heads and chat bubbles take the new font after a reload.", "muted" },
		{ "button", "Reload now", function() if ReloadUI then ReloadUI() end end },
	} end },
	{ key = "tooltips", name = "Tooltips", rows = function() return {
		{ "heading", "Tooltips" },
		{ "toggle", "Pathwise look", "tooltip.skin", "A flat ground and a thin border instead of the ornate frame." },
		{ "choice", "Border", "tooltip.border", { key = "tb", { "Quality", "quality" }, { "Accent", "accent" }, { "Plain", "plain" } },
			"Quality: an item's quality color, a player's class color." },
		{ "toggle", "Player names in class color", "tooltip.classNames" },
		{ "toggle", "Health bar in class color", "tooltip.healthClass" },
		{ "toggle", "At the mouse", "tooltip.cursor", "Tooltips for the world follow your pointer instead of the corner." },
	} end },
	{ key = "windows", name = "Game windows", rows = function() return {
		{ "heading", "Game windows" },
		{ "toggle", "Pathwise look", "windows.skin", "Character, spellbook, vendor, mail, quests and more: a flat ground, a thin border and your accent along the top." },
		{ "toggle", "Accent line along the top", "windows.accentLine" },
		{ "toggle", "Round portraits", "windows.portraits" },
		{ "text", "Only windows on the game's modern frame are dressed; others keep their look. Not yet checked on Forever: tell us what looks wrong.", "muted" },
	} end },
	{ key = "heal", name = "Healing", rows = function()
		-- Click-to-heal frames are their own addon: Pathwise Heal.
		local H = _G.PathwiseHeal
		if H then
			return {
				{ "heading", "Healing frames" },
				{ "text", "Your healing frames come from Pathwise Heal, a separate addon. Its options are its own; it keeps the same accent as Pathwise UI." },
				{ "button", "Open Pathwise Heal's options", function() H.Fire("SHOW_CONFIG") end, "accent" },
			}
		end
		return {
			{ "heading", "Healing frames" },
			{ "text", "Click-to-heal party and raid frames, like HealBot or VuhDo, are a separate addon: Pathwise Heal. Install it to get them; it works with or without Pathwise UI." },
		}
	end },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
	{ key = "next", name = "Coming next", rows = function() return {
		{ "heading", "Coming next" },
		{ "text", "Pathwise UI grows in stages, each one usable on its own:" },
		{ "text", "5  Chat" },
		{ "text", "6  Minimap" },
		{ "text", "7  Data bars: gold, durability, latency, more (the experience bar and tray are in already)" },
	} end },
}
