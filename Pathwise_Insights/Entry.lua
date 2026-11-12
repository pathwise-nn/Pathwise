-- How you reach Pathwise Insights: /pwinsights opens the window
-- (/pwinsights map, /pwinsights share, /pwinsights options), the minimap
-- button opens it (right-click: the options), and Pathwise's suite list
-- opens it when Pathwise is installed. Loaded last, after the kit's
-- minimap button.

local ADDON, ns = ...
local Win = ns.Window

ns.Commands[""] = function() Win.Toggle() end
ns.Commands["map"] = function() Win.Open("map") end
ns.Commands["share"] = function() Win.Open("share") end
ns.Commands["options"] = function() ns.Fire("SHOW_CONFIG") end
ns.Commands["config"] = ns.Commands["options"]
ns.Commands["help"] = function()
	local s = ns.ID.slash[1]
	ns.Print(s .. ": your numbers.  " .. s .. " map: the heat map.  " .. s .. " share: a share code.  " .. s .. " options: settings.")
end

---------------------------------------------------------------------------
-- The minimap button: click the window, right-click the options
---------------------------------------------------------------------------

local function minimap()
	local button = ns.Minimap and ns.Minimap.Button()
	if not button or button.pwInsights then return end
	button.pwInsights = true
	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then ns.Fire("SHOW_CONFIG") else Win.Toggle() end
	end)
	local enter = button:GetScript("OnEnter")
	button:SetScript("OnEnter", function(self, ...)
		if enter then enter(self, ...) end
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(ns.ID.name, 1, 1, 1)
			GameTooltip:AddLine("Click: your numbers", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Right-click: options", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
end
ns.On("READY", minimap)
ns.On("SETTING_CHANGED", function(path) if path == "minimap.shown" or path == "*" then minimap() end end)

-- In Pathwise's suite list (Settings > Pathwise suite): opens the window.
-- The kit lists it with its options at READY; this replaces that entry.
ns.On("READY", function()
	local S = ns.Suite()
	if S and S.RegisterModule then
		S.RegisterModule({ key = ns.ID.key, name = ns.ID.name, accent = "accent", about = ns.ID.about,
			open = function() Win.Open() end })
	end
end)
