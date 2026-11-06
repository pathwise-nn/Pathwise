-- A Pathwise addon's minimap button (ns.ID: Pathwise UI, Pathwise Heal): a
-- dark disc with a thin ring and the Pathwise mark in the addon's logo colour
-- (ns.ID.color), so each addon's button is told apart on the minimap; the
-- accent if it has none. Click: the options; drag: around the rim.
-- Shared file (see Core.lua): edit it here, then run npm run kit.

local ADDON, ns = ...
local T = ns.Theme
local M = {}
ns.Minimap = M

ns.Defaults("minimap", { shown = true, angle = ns.ID.minimapAngle or 135 })

local button

-- The mark's colour: the addon's logo colour, else your accent.
function M.Color()
	return ns.ID.color and T.Hex(ns.ID.color) or T.Color("accent")
end

function M.Offset(angle, width)
	local r = (width or 140) / 2 + 6
	local a = math.rad(angle)
	return math.cos(a) * r, math.sin(a) * r
end

local function place()
	local x, y = M.Offset(ns.Get("minimap.angle") or ns.ID.minimapAngle or 135, Minimap:GetWidth())
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function build()
	button = CreateFrame("Button", ns.ID.global .. "MinimapButton", nil)
	button:SetParent(Minimap)
	button:SetSize(32, 32)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	local disc = button:CreateTexture(nil, "BACKGROUND")
	disc:SetTexture(T.MEDIA .. "dot-done")
	disc:SetAllPoints()
	local function ground() local bg = T.Color("bg") disc:SetVertexColor(bg[1], bg[2], bg[3], 0.95) end
	ground()
	local ring = button:CreateTexture(nil, "BORDER")
	ring:SetTexture(T.MEDIA .. "dot-open")
	ring:SetAllPoints()
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(T.MEDIA .. "icon")
	icon:SetSize(20, 20)
	icon:SetPoint("CENTER")
	local function tint()
		local a = M.Color() icon:SetVertexColor(a[1], a[2], a[3])
		ground()
		ring:SetVertexColor(T.Color("border")[1], T.Color("border")[2], T.Color("border")[3])
	end
	tint()
	ns.On("ACCENT_CHANGED", tint)
	button.icon, button.ring = icon, ring
	button:SetScript("OnClick", function() ns.Fire("SHOW_CONFIG") end)
	local function look(p)
		local r, g, b = ns.Anim.Mix(T.Color("border"), M.Color(), p)
		ring:SetVertexColor(r, g, b)
		icon:SetSize(20 + 2 * p, 20 + 2 * p)
	end
	button:SetScript("OnEnter", function(self)
		ns.Anim.Hover(self, true, look)
		if GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT")
			GameTooltip:SetText(ns.ID.name, 1, 1, 1)
			GameTooltip:AddLine("Click: options", 0.6, 0.69, 0.75)
			GameTooltip:AddLine("Drag: move this button", 0.6, 0.69, 0.75)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(self)
		ns.Anim.Hover(self, false, look)
		if GameTooltip then GameTooltip:Hide() end
	end)
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local cx, cy = Minimap:GetCenter()
			if not (cx and GetCursorPosition) then return end
			local s = Minimap:GetEffectiveScale() or 1
			local mx, my = GetCursorPosition()
			local deg = math.deg(math.atan2(my / s - cy, mx / s - cx))
			if deg < 0 then deg = deg + 360 end
			ns.Set("minimap.angle", math.floor(deg + 0.5))
		end)
	end)
	button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
end

function M.Refresh()
	if not Minimap then return end
	if not button then build() end
	place()
	button:SetShown(ns.Get("minimap.shown") and true or false)
end
function M.Button() return button end

ns.On("READY", M.Refresh)
ns.On("SETTING_CHANGED", function(path)
	if path == "minimap.shown" or path == "minimap.angle" or path == "*" then if button then M.Refresh() end end
end)
