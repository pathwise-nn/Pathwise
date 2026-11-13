-- How you reach Pathwise Bags: your bag key opens the bag window, /pwbags
-- too (/pwbags options for the settings, /pwbags sell at a vendor), the
-- minimap button opens it (right-click: the options), and Pathwise's suite
-- list opens the options when Pathwise is installed. Loaded last, after the
-- kit's minimap button.

local ADDON, ns = ...
local W = ns.Window

ns.Commands[""] = function() W.Toggle() end
ns.Commands["options"] = function() ns.Fire("SHOW_CONFIG") end
ns.Commands["config"] = ns.Commands["options"]
ns.Commands["sell"] = function()
	if not ns.Sell.IsMerchantOpen() then ns.Print("Talk to a vendor first.") return end
	if ns.Sell.Run() == 0 then ns.Print("No junk to sell.") end
end
ns.Commands["help"] = function()
	local s = ns.ID.slash[1]
	ns.Print(s .. ": the bag window.  " .. s .. " sell: sell junk at a vendor.  " .. s .. " options: settings.")
end

---------------------------------------------------------------------------
-- The minimap button: click the bag window, right-click the options
---------------------------------------------------------------------------

local hooked -- the button whose clicks are ours
local function minimap()
	local button = ns.Minimap and ns.Minimap.Button()
	if not button or hooked == button then return end
	hooked = button
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.Fire("SHOW_CONFIG") else W.Toggle() end
	end)
	local enter = button:GetScript("OnEnter")
	button:SetScript("OnEnter", function(self, ...)
		if enter then enter(self, ...) end
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(ns.ID.name, 1, 1, 1)
			GameTooltip:AddLine("Click: open or close the bag window", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Right-click: options", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
end
ns.On("READY", minimap)
ns.On("SETTING_CHANGED", function(path) if path == "minimap.shown" or path == "*" then minimap() end end)
