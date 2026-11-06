-- How you reach Pathwise Loot: /pwloot opens the loot browser
-- (/pwloot search <words>, /pwloot options), the minimap button opens it
-- (right-click: the options), and item tooltips say which boss drops them.
-- Loaded last, after the kit's minimap button.

local ADDON, ns = ...
local L, B = ns.Loot, ns.LootBrowser

ns.Commands[""] = function() B.Toggle() end
ns.Commands["options"] = function() ns.Fire("SHOW_CONFIG") end
ns.Commands["config"] = ns.Commands["options"]
ns.Commands["search"] = function(rest)
	B.Show()
	B.Search(rest)
end
ns.Commands["help"] = function()
	ns.Print(ns.ID.slash[1] .. ": the loot browser.  " .. ns.ID.slash[1] .. " search <words>: find an item.  " .. ns.ID.slash[1] .. " options: settings.  " .. ns.ID.slash[1] .. " move: move mode.")
end

---------------------------------------------------------------------------
-- The minimap button: click the browser, right-click the options
---------------------------------------------------------------------------

local function minimap()
	local button = ns.Minimap and ns.Minimap.Button()
	if not button or button.pwLoot then return end
	button.pwLoot = true
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.Fire("SHOW_CONFIG") else B.Toggle() end
	end)
	local enter = button:GetScript("OnEnter")
	button:SetScript("OnEnter", function(self, ...)
		if enter then enter(self, ...) end
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(ns.ID.name, 1, 1, 1)
			GameTooltip:AddLine("Click: the loot browser", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Right-click: options", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
end
ns.On("READY", minimap)
ns.On("SETTING_CHANGED", function(path) if path == "minimap.shown" or path == "*" then minimap() end end)

---------------------------------------------------------------------------
-- "Drops from" on item tooltips
---------------------------------------------------------------------------
-- The same hooks as Pathwise Gear's (never tainting the game's code):
-- TooltipDataProcessor.AddTooltipPostCall for items, else OnTooltipSetItem.

local function forbidden(tt)
	if not (tt and tt.IsForbidden) then return false end
	local ok, f = pcall(tt.IsForbidden, tt)
	return not ok or f
end

-- -> left, right for an item link, or nil when no boss is known to drop it.
function L.TooltipLine(link)
	link = ns.Readable(link)
	local id = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	if not id then return nil end
	local list = L.Sources(id)
	if #list == 0 then return nil end
	local e = L.Encounter(list[1])
	if not e then return nil end
	local inst = e.map and L.Instance(e.map)
	local right = inst and (e.name .. ", " .. inst.name) or e.name
	if #list > 1 then right = right .. (" (+%d more)"):format(#list - 1) end
	return "Drops from", right
end

local function addLine(tt)
	if not ns.Get("loot.tooltip") or forbidden(tt) or not tt.GetItem then return end
	local ok, _, link = pcall(tt.GetItem, tt)
	if not (ok and link) then return end
	local left, right = L.TooltipLine(link)
	if not left then return end
	local a = ns.Theme.Color("accent")
	tt:AddDoubleLine(left, right, 0.6, 0.69, 0.75, a[1], a[2], a[3])
	tt:Show()
end
L.AddTooltipLine = addLine

local installed
function L.InstallTooltip()
	if installed then return installed end
	local P, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and E and E.Item then
		P.AddTooltipPostCall(E.Item, function(tt) addLine(tt) end)
		installed = "postcall"
	else
		for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
			if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", addLine) end
		end
		installed = "script"
	end
	return installed
end
ns.On("READY", L.InstallTooltip)
