-- Pathwise's minimap button: the way into Pathwise without typing.
--   left-click   show or hide the guide window
--   right-click  Settings
--   drag         move it around the minimap's edge (remembered)
-- Made with no parent and then set under the minimap (as every Pathwise frame
-- under a game frame), so the gamepad interface's CreateFrame hook never runs
-- for it.

local ADDON, ns = ...
local T = ns.Theme
local MB = {}
ns.MinimapButton = MB

ns.Defaults("minimap", { shown = true, angle = 225 }) -- degrees, 0 = east, counter-clockwise

local SIZE = 32
local button

-- Offset from the minimap's centre for an angle: just outside its edge.
function MB.Offset(angle, minimapWidth)
	local r = (minimapWidth or 140) / 2 + 6
	local a = math.rad(angle)
	return math.cos(a) * r, math.sin(a) * r
end

-- The angle of the cursor around the minimap's centre, in degrees.
function MB.AngleFrom(cx, cy, mx, my)
	local deg = math.deg(math.atan2(my - cy, mx - cx))
	if deg < 0 then deg = deg + 360 end
	return math.floor(deg + 0.5)
end

local function place()
	local x, y = MB.Offset(ns.Get("minimap.angle"), Minimap:GetWidth())
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function build()
	button = CreateFrame("Button", "PathwiseMinimapButton", nil)
	button:SetParent(Minimap)
	button:SetSize(SIZE, SIZE)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")

	-- A dark disc with a thin ring and the compass mark, in Pathwise's colours.
	local disc = button:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(T.MEDIA .. "dot-done")
	disc:SetAllPoints()
	local bg = T.Color("bg")
	disc:SetVertexColor(bg[1], bg[2], bg[3], 0.95)
	local ring = button:CreateTexture(nil, "BORDER")
	ring:SetTexture(T.MEDIA .. "dot-open")
	ring:SetAllPoints()
	local edge = T.Color("border")
	ring:SetVertexColor(edge[1], edge[2], edge[3])
	button.ring = ring
	local icon = T.Icon(button, 20)
	icon:SetPoint("CENTER")

	button:SetScript("OnClick", function(_, which)
		if which == "RightButton" then ns.Fire("SHOW_SETTINGS") else ns.Fire("TOGGLE_GUIDE") end
	end)
	button:SetScript("OnEnter", function(self)
		local a = T.Color("accent")
		ring:SetVertexColor(a[1], a[2], a[3])
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText("Pathwise", 1, 1, 1)
			GameTooltip:AddLine("Click: show or hide the guide", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Right-click: settings", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function()
		ring:SetVertexColor(edge[1], edge[2], edge[3])
		if GameTooltip then GameTooltip:Hide() end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local cx, cy = Minimap:GetCenter()
			if not (cx and GetCursorPosition) then return end
			local scale = Minimap:GetEffectiveScale() or 1
			local mx, my = GetCursorPosition()
			ns.Set("minimap.angle", MB.AngleFrom(cx, cy, mx / scale, my / scale))
			place()
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function MB.Refresh()
	if not Minimap then return end
	if not button then build() end
	place()
	button:SetShown(ns.Get("minimap.shown") and true or false)
end

ns.On("READY", MB.Refresh)
ns.On("SETTING_CHANGED", function(path)
	if path == "minimap.shown" or path == "minimap.angle" then if button then MB.Refresh() end end
end)

---------------------------------------------------------------------------
-- Key bindings (Bindings.xml): the game's Key Bindings menu lists these
-- under "Pathwise".
---------------------------------------------------------------------------

BINDING_HEADER_PATHWISE = "Pathwise"
BINDING_NAME_PATHWISE_TOGGLE = "Show or hide the guide"
BINDING_NAME_PATHWISE_COMPACT = "Full or compact guide"
BINDING_NAME_PATHWISE_PROFESSIONS = "Professions"
BINDING_NAME_PATHWISE_DUNGEONS = "Dungeons for your level"
BINDING_NAME_PATHWISE_SETTINGS = "Settings"
BINDING_NAME_PATHWISE_REPORT = "Report this step"

function Pathwise.Binding(what)
	if what == "toggle" then ns.Fire("TOGGLE_GUIDE")
	elseif what == "compact" then ns.Guide.SetCompact(not ns.Get("guide.compact"))
	elseif what == "professions" then ns.Fire("SHOW_PROFESSIONS")
	elseif what == "dungeons" then ns.Fire("SHOW_DUNGEONS")
	elseif what == "settings" then ns.Fire("SHOW_SETTINGS")
	elseif what == "report" then ns.Fire("REPORT_STEP") end
end
