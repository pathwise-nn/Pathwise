-- Pathwise Bags' pages in its options window (Kit/Options.lua draws them;
-- the row kinds are listed there): the bag window, selling junk, bag space
-- and your marks, then the look and profile pages every Pathwise addon has.

local ADDON, ns = ...
local C = ns.Config
local S, Items = ns.S, ns.Items

local function bagsRows()
	local free, total = ns.Space.Free()
	local view = S.Get("bags.view") or "categories"
	local rows = {
		{ "heading", "The bag window" },
		{ "text", ("%d of %d slots free."):format(free, total), "muted" },
		{ "button", ns.Window.IsShown() and "Close the bag window" or "Open the bag window", function()
			C.Hide()
			ns.Window.Toggle()
		end, "accent" },
		{ "text", ("Your bag key, %s or a click on the minimap button opens it; right-click the button for these options."):format(ns.ID.slash[1]), "muted" },
		{ "toggle", "Use the Pathwise bag window", "bags.window", "Off: your bag key opens the game's bags again (the markers are in this window only)." },
		{ "choice", "Show items", "bags.view", { { "By kind", "categories" }, { "Grid", "grid" }, { "By bag", "bags" } },
			"By bag: each bag in its own section; click a bag's name to hide or show it. The window's layout button switches too." },
	}
	if view == "bags" and next(S.Get("bags.folded") or {}) then
		rows[#rows + 1] = { "button", "Show every bag again", function() S.Set("bags.folded", nil) end }
	end
	rows[#rows + 1] = { "slider", "Width (item columns)", "bags.columns", 8, 20, 1, "count" }
	rows[#rows + 1] = { "toggle", "Bag bar", "bags.bagBar", "Your bags under the title, with their free slots; hover one to see its items." }
	rows[#rows + 1] = { "toggle", "Open with a vendor", "bags.openAtMerchant", "The bag window opens when you talk to a vendor." }

	rows[#rows + 1] = { "heading", "With Pathwise" }
	if S.Pathwise() then
		rows[#rows + 1] = { "text", "Pathwise: Leveling & Professions is installed: items a quest on your path will ask for, and your profession routes' materials, are marked and never sold.", "muted" }
	else
		rows[#rows + 1] = { "text", "Install Pathwise: Leveling & Professions to mark items quests later on your path will ask for, and your profession routes' materials. Without it, quest items are the ones the game marks.", "muted" }
	end
	rows[#rows + 1] = { "text", S.Gear() and "Pathwise Gear is installed: upgrades and best in slot are marked, and gear you can't use or that is worse can go."
		or "With Pathwise Gear installed, upgrades and best in slot are marked too.", "muted" }
	return rows
end

local function sellRows()
	local list, value = ns.Sell.List()
	return {
		{ "heading", "Selling junk" },
		{ "text", #list > 0 and ("%d item%s to sell now, %s."):format(#list, #list == 1 and "" or "s", Items.Money(value)) or "Nothing to sell right now.", "muted" },
		{ "toggle", "Sell on its own at vendors", "bags.sellAuto", "Off: a \"Sell junk\" button on the vendor window does it when you click." },
		{ "toggle", "Also sell bound gear you can't use or is worse", "bags.sellBound", "And leftovers of quests you finished." },
		{ "text", "Never sold: what you keep, quest items you still need, your profession route's materials, upgrades, items with no price.", "muted" },
	}
end

local function spaceRows()
	local rows = {
		{ "heading", "Bag space" },
		{ "toggle", "Warn when bags are nearly full", "bags.warn", "Once, on screen and in chat, with what to let go first." },
		{ "slider", "Warn at free slots", "bags.warnAt", 0, 10, 1, "count" },
	}
	local room = ns.Space.MakeRoom(5)
	rows[#rows + 1] = { "heading", "First to go" }
	if #room == 0 then rows[#rows + 1] = { "text", "Nothing to let go: everything has a use.", "muted" } end
	for _, e in ipairs(room) do
		rows[#rows + 1] = { "text", ("%s  ·  %s%s"):format(e.name or "?", e.facts.why or "", (e.sell or 0) > 0 and ("  ·  " .. Items.Money((e.sell or 0) * (e.count or 1))) or ""), "muted" }
	end
	return rows
end

local function markRows()
	local rows = {
		{ "heading", "Your marks" },
		{ "text", "In the bag window, the coin button turns on marking: click an item to keep it (never sold), again for junk, again to clear.", "muted" },
	}
	local n = 0
	for id, what in pairs(Items.Marks()) do
		n = n + 1
		if n <= 30 then
			local ok, name = false, nil
			if C_Item and C_Item.GetItemNameByID then ok, name = pcall(C_Item.GetItemNameByID, id) end
			name = ok and ns.Readable(name) or ("Item " .. id)
			rows[#rows + 1] = { "button", ("%s: %s  (clear)"):format(what == "keep" and "Keep" or "Junk", tostring(name)), function()
				Items.Mark(id, nil)
				C.Show("marks")
			end }
		end
	end
	if n == 0 then rows[#rows + 1] = { "text", "No items marked.", "muted" } end
	return rows
end

C.CATEGORIES = {
	{ key = "bags", name = "Bags", rows = bagsRows },
	{ key = "sell", name = "Selling junk", rows = sellRows },
	{ key = "space", name = "Bag space", rows = spaceRows },
	{ key = "marks", name = "Your marks", rows = markRows },
	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}
