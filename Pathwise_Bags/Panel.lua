-- The Pathwise Bags panel (Settings > Pathwise suite > Pathwise Bags): the
-- bag window, selling junk, bag space, and the items you marked.

local ADDON, ns = ...
local S, Items = Pathwise.Suite, ns.Items
local P = {}
ns.Panel = P

local function onOff(v) return v and "On" or "Off" end
local function toggle(path) return function() S.Set(path, not S.Get(path)) S.Refresh() end end

function P.Build()
	local rows = { { "heading", "Pathwise Bags" } }
	local free, total = ns.Space.Free()
	rows[#rows + 1] = { "text", ("%d of %d slots free."):format(free, total), "bags" }
	rows[#rows + 1] = { "choice", ns.Window.IsShown() and "Close the bag window" or "Open the bag window", "Or press your bag key", function()
		ns.Window.Toggle()
		S.Refresh()
	end }

	rows[#rows + 1] = { "setting", "Minimap button", onOff(S.Get("bags.minimap")), { { S.Get("bags.minimap") and "Hide" or "Show", toggle("bags.minimap") } } }
	rows[#rows + 1] = { "heading", "Bag window" }
	rows[#rows + 1] = { "setting", "Use the Pathwise bag window", onOff(S.Get("bags.window")), { { S.Get("bags.window") and "Turn off" or "Turn on", toggle("bags.window") } } }
	rows[#rows + 1] = { "text", "Off: your bag key opens the game's bags again (the markers stay in this window only).", "muted" }
	local view = S.Get("bags.view") or "categories"
	local function pickView(v) return function() S.Set("bags.view", v) S.Refresh() end end
	rows[#rows + 1] = { "setting", "Show items", ({ grid = "As one grid", bags = "By bag" })[view] or "By kind", {
		{ "By kind", pickView("categories"), view == "categories" and "accent" or "default" },
		{ "Grid", pickView("grid"), view == "grid" and "accent" or "default" },
		{ "By bag", pickView("bags"), view == "bags" and "accent" or "default" } } }
	rows[#rows + 1] = { "text", "By bag: each bag in its own section; click a bag's name to hide or show it. The window's layout button switches too.", "muted" }
	local folded = S.Get("bags.folded") or {}
	if view == "bags" and next(folded) then
		rows[#rows + 1] = { "choice", "Show every bag again", nil, function() S.Set("bags.folded", nil) S.Refresh() end }
	end
	rows[#rows + 1] = { "slider", "Width (item columns)", "bags.columns", 8, 20, 1, function(v) return ("%d"):format(v) end, "count" }
	rows[#rows + 1] = { "setting", "Bag bar", onOff(S.Get("bags.bagBar")), { { S.Get("bags.bagBar") and "Hide" or "Show", toggle("bags.bagBar") } } }
	rows[#rows + 1] = { "text", "Your bags under the title, with their free slots; hover one to see its items.", "muted" }
	rows[#rows + 1] = { "setting", "Open with a vendor", onOff(S.Get("bags.openAtMerchant") ~= false), {
		{ S.Get("bags.openAtMerchant") ~= false and "Turn off" or "Turn on", function()
			S.Set("bags.openAtMerchant", S.Get("bags.openAtMerchant") == false) S.Refresh() end } } }

	rows[#rows + 1] = { "heading", "Selling junk" }
	local list, value = ns.Sell.List()
	rows[#rows + 1] = { "text", #list > 0 and ("%d item%s to sell now, %s."):format(#list, #list == 1 and "" or "s", Items.Money(value)) or "Nothing to sell right now." }
	rows[#rows + 1] = { "setting", "Sell on its own at vendors", onOff(S.Get("bags.sellAuto")), { { S.Get("bags.sellAuto") and "Turn off" or "Turn on", toggle("bags.sellAuto") } } }
	rows[#rows + 1] = { "text", "Off: a \"Sell junk\" button on the vendor window does it when you click.", "muted" }
	rows[#rows + 1] = { "setting", "Also sell bound gear you can't use or is worse", onOff(S.Get("bags.sellBound")), { { S.Get("bags.sellBound") and "Turn off" or "Turn on", toggle("bags.sellBound") } } }
	rows[#rows + 1] = { "text", "Never sold: what you keep, quest items you still need, your profession route's materials, upgrades, items with no price.", "muted" }

	rows[#rows + 1] = { "heading", "Bag space" }
	rows[#rows + 1] = { "setting", "Warn when bags are nearly full", onOff(S.Get("bags.warn")), { { S.Get("bags.warn") and "Turn off" or "Turn on", toggle("bags.warn") } } }
	rows[#rows + 1] = { "slider", "Warn at free slots", "bags.warnAt", 0, 10, 1, function(v) return ("%d"):format(v) end, "count" }
	local room = ns.Space.MakeRoom(5)
	rows[#rows + 1] = { "text", #room > 0 and "First to go when you need room:" or "Nothing to let go: everything has a use." }
	for _, e in ipairs(room) do
		rows[#rows + 1] = { "text", ("%s  ·  %s%s"):format(e.name or "?", e.facts.why or "", (e.sell or 0) > 0 and ("  ·  " .. Items.Money((e.sell or 0) * (e.count or 1))) or ""), "muted" }
	end

	rows[#rows + 1] = { "heading", "Your marks" }
	rows[#rows + 1] = { "text", "In the bag window, the coin button turns on marking: click an item to keep it (never sold), again for junk, again to clear." }
	local n = 0
	for id, what in pairs(Items.Marks()) do
		n = n + 1
		if n <= 12 then
			local name = (C_Item and C_Item.GetItemNameByID and select(2, pcall(C_Item.GetItemNameByID, id))) or ("Item " .. id)
			rows[#rows + 1] = { "choice", ("%s: %s"):format(what == "keep" and "Keep" or "Junk", tostring(name)), "Click to clear", function()
				Items.Mark(id, nil)
				S.Refresh()
			end }
		end
	end
	if n == 0 then rows[#rows + 1] = { "text", "No items marked.", "muted" } end
	rows[#rows + 1] = S.CloseButtons()
	return rows
end

S.Panel("bags", P.Build)

-- Its own minimap button, in green: click for the bag window, right-click
-- for these settings.
S.Defaults("bags", { minimap = true, minimapAngle = 165 })
S.On("READY", function()
	S.MinimapButton({
		key = "Bags", name = "Pathwise Bags", shownPath = "bags.minimap", anglePath = "bags.minimapAngle",
		accent = "bags", glyph = "bag", panels = { "bags" },
		lines = { "Click: open or close the bag window", "Right-click: Pathwise Bags settings" },
		onClick = function(which)
			if which == "RightButton" then S.Open("bags") else ns.Window.Toggle() end
		end,
	})
end)
S.RegisterModule({
	key = "bags", name = "Pathwise Bags", accent = "bags",
	about = "One bag window, keep and sell markers, junk selling, bag space",
	open = function() S.Open("bags") end,
})
