-- How you reach Pathwise Gear: /pwgear opens its options on Upgrades
-- (/pwgear best: Best in Slot (Level)), the minimap button opens them
-- (right-click: its pages), and Pathwise's suite list opens them when
-- Pathwise is installed. Loaded last, after the kit's minimap button.

local ADDON, ns = ...
local C = ns.Config

ns.Commands[""] = function() C.Toggle() end
ns.Commands["best"] = function() C.Show("best") end
ns.Commands["bis"] = ns.Commands["best"]
ns.Commands["options"] = function() C.Show("gear") end
ns.Commands["help"] = function()
	local s = ns.ID.slash[1]
	ns.Print(s .. ": upgrades, your spec and the options.  " .. s .. " best: Best in Slot (Level).")
end

-- In Pathwise's suite list (Settings > Pathwise suite), in Gear's gold. The
-- kit lists it at READY; this replaces that entry.
ns.On("READY", function()
	local S = ns.Suite()
	if S and S.RegisterModule then
		S.RegisterModule({ key = ns.ID.key, name = ns.ID.name, accent = "gear", about = ns.ID.about,
			open = function() C.Show("gear") end })
	end
end)
