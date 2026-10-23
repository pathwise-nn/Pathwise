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

-- A minimap button in the Pathwise look. Used by Pathwise and by each suite
-- addon (Pathwise.Suite.MinimapButton), each with its own colour and place.
--   def = { key, name, shownPath, anglePath, accent ("accent", "gear", ...),
--           glyph (Media/glyph-<name>) or nil for the compass mark,
--           lines = { tooltip lines }, onClick(which) }
local buttons = {}
MB.Buttons = buttons

function MB.Make(def)
	if buttons[def.key] then return buttons[def.key] end
	local b = CreateFrame("Button", "Pathwise" .. def.key .. "MinimapButton", nil)
	b:SetParent(Minimap)
	b:SetSize(SIZE, SIZE)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b.def = def

	-- A dark disc with a thin ring and the mark, in Pathwise's colours.
	local disc = b:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(T.MEDIA .. "dot-done")
	disc:SetAllPoints()
	local bg = T.Color("bg")
	disc:SetVertexColor(bg[1], bg[2], bg[3], 0.95)
	local ring = b:CreateTexture(nil, "BORDER")
	ring:SetTexture(T.MEDIA .. "dot-open")
	ring:SetAllPoints()
	local edge = T.Color("border")
	ring:SetVertexColor(edge[1], edge[2], edge[3])
	b.ring = ring
	local accent = T.Color(def.accent or "accent")
	local icon
	if def.glyph then
		icon = b:CreateTexture(nil, "ARTWORK")
		icon:SetTexture(T.MEDIA .. "glyph-" .. def.glyph)
		icon:SetSize(18, 18)
		icon:SetVertexColor(accent[1], accent[2], accent[3])
	else
		icon = T.Icon(b, 20)
	end
	icon:SetPoint("CENTER")
	b.icon = icon

	local function place()
		local x, y = MB.Offset(ns.Get(def.anglePath) or 225, Minimap:GetWidth())
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", x, y)
	end
	b.Place = place

	b:SetScript("OnClick", function(_, which) def.onClick(which) end)
	b:SetScript("OnEnter", function(self)
		ring:SetVertexColor(accent[1], accent[2], accent[3])
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(def.name, 1, 1, 1)
			for _, line in ipairs(def.lines or {}) do GameTooltip:AddLine(line, 0.6, 0.69, 0.75) end
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
	b:SetScript("OnLeave", function()
		ring:SetVertexColor(edge[1], edge[2], edge[3])
		if GameTooltip then GameTooltip:Hide() end
	end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local cx, cy = Minimap:GetCenter()
			if not (cx and GetCursorPosition) then return end
			local scale = Minimap:GetEffectiveScale() or 1
			local mx, my = GetCursorPosition()
			ns.Set(def.anglePath, MB.AngleFrom(cx, cy, mx / scale, my / scale))
			place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

	function b:Refresh()
		place()
		self:SetShown(ns.Get(def.shownPath) and true or false)
	end
	buttons[def.key] = b
	b:Refresh()
	return b
end

-- Pathwise's own: left-click the guide, right-click Settings.
local button
function MB.Refresh()
	if not Minimap then return end
	if not button then
		button = MB.Make({
			key = "", name = "Pathwise", shownPath = "minimap.shown", anglePath = "minimap.angle",
			lines = { "Click: show or hide the guide", "Right-click: settings" },
			onClick = function(which)
				if which == "RightButton" then ns.Fire("SHOW_SETTINGS") else ns.Fire("TOGGLE_GUIDE") end
			end,
		})
	end
	for _, b in pairs(buttons) do b:Refresh() end
end

ns.On("READY", MB.Refresh)
ns.On("SETTING_CHANGED", function(path)
	for _, b in pairs(buttons) do
		if path == b.def.shownPath or path == b.def.anglePath then b:Refresh() end
	end
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
