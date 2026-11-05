-- Tooltips in the Pathwise look: a flat ground and a 1 px border instead of
-- the game's ornate frame; the border takes the item's quality color or the
-- player's class color; player names in their class color; the health bar
-- flat and class-colored; optionally the tooltip at the mouse.
--
-- Game code followed (Blizzard's Forever UI source): every tooltip's frame
-- is drawn by SharedTooltip_SetBackdropStyle (SharedTooltipTemplates.lua),
-- the default spot by GameTooltip_SetDefaultAnchor; both are followed with
-- hooksecurefunc, nothing of the game's is replaced. Item and unit lines come
-- from TooltipDataProcessor's post-calls.

local ADDON, ns = ...
local T = ns.Theme
local Tip = {}
ns.Tooltip = Tip

ns.Defaults("tooltip", {
	skin = true,
	border = "quality", -- "quality" (items, and class for players) | "accent" | "plain"
	classNames = true,
	healthClass = true,
	cursor = false,
})

local skinned = setmetatable({}, { __mode = "k" }) -- tooltip -> { ground, border }

local function layer(tt)
	local s = skinned[tt]
	if s then return s end
	s = {}
	s.ground = tt:CreateTexture(nil, "BACKGROUND", nil, -8)
	s.ground:SetAllPoints()
	s.border = T.Border(tt, "BACKGROUND", -7)
	skinned[tt] = s
	return s
end

function Tip.SetBorder(tt, c)
	local s = skinned[tt]
	if not s then return end
	c = c or (ns.Get("tooltip.border") == "accent" and T.Color("accent")) or T.Color("border")
	s.border:SetColor(c[1], c[2], c[3], 1)
end

-- Draw a tooltip the Pathwise way (or put the game's look back).
function Tip.Skin(tt)
	if not tt then return end
	local on = ns.Get("tooltip.skin")
	if not on then
		local s = skinned[tt]
		if s then
			s.ground:Hide()
			s.border:SetShown(false)
			if type(tt.NineSlice) == "table" then tt.NineSlice:SetAlpha(1) end
		end
		return
	end
	local s = layer(tt)
	if type(tt.NineSlice) == "table" then tt.NineSlice:SetAlpha(0) end
	local bg = T.Color("bg")
	s.ground:SetColorTexture(bg[1], bg[2], bg[3], ns.Get("look.opacity") or 0.92)
	s.ground:Show()
	s.border:SetShown(true)
	Tip.SetBorder(tt)
end

local function readable(v) return ns.Readable(v) end

-- An item: the border in its quality color.
function Tip.OnItem(tt)
	if not (ns.Get("tooltip.skin") and ns.Get("tooltip.border") == "quality") then return end
	if not (tt and tt.GetItem) then return end
	local ok, _, link = pcall(tt.GetItem, tt)
	link = ok and readable(link)
	if not link then return end
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local quality = f and select(3, pcall(f, link))
	quality = readable(quality)
	local q = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	if q and quality >= 2 then Tip.SetBorder(tt, { q.r, q.g, q.b, 1 }) end
end

-- A unit: a player's name (and border) in their class color; the health bar too.
function Tip.OnUnit(tt)
	if not (tt and tt.GetUnit) then return end
	local ok, _, unit = pcall(tt.GetUnit, tt)
	unit = ok and readable(unit)
	if not unit then return end
	local isPlayer = UnitIsPlayer and readable(UnitIsPlayer(unit))
	local class = isPlayer and UnitClass and readable(select(2, UnitClass(unit)))
	local c = class and T.ClassColor(class)
	if c then
		if ns.Get("tooltip.classNames") and tt.GetName then
			local first = _G[(tt:GetName() or "") .. "TextLeft1"]
			if first and first.SetTextColor then first:SetTextColor(c[1], c[2], c[3]) end
		end
		if ns.Get("tooltip.skin") and ns.Get("tooltip.border") == "quality" then Tip.SetBorder(tt, c) end
	end
	local bar = tt.StatusBar
	if type(bar) ~= "table" then bar = _G.GameTooltipStatusBar end
	if type(bar) == "table" and ns.Get("tooltip.healthClass") and bar.SetStatusBarColor then
		local hc = c or T.Color("success")
		bar:SetStatusBarColor(hc[1], hc[2], hc[3])
	end
end

local TIPS = { "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }
function Tip.SkinAll()
	for _, name in ipairs(TIPS) do Tip.Skin(_G[name]) end
end

local installed = false
function Tip.Install()
	if installed then return end
	installed = true
	if hooksecurefunc and SharedTooltip_SetBackdropStyle then
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tt) Tip.Skin(tt) end)
	end
	if hooksecurefunc and GameTooltip_SetDefaultAnchor then
		hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tt, parent)
			if ns.Get("tooltip.cursor") and tt and tt.SetOwner then tt:SetOwner(parent or UIParent, "ANCHOR_CURSOR") end
		end)
	end
	local P, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and E then
		if E.Item then P.AddTooltipPostCall(E.Item, function(tt) Tip.OnItem(tt) end) end
		if E.Unit then P.AddTooltipPostCall(E.Unit, function(tt) Tip.OnUnit(tt) end) end
	end
	-- Back to the plain border when a tooltip empties (for the next thing it shows).
	for _, name in ipairs(TIPS) do
		local tt = _G[name]
		if tt and tt.HookScript then tt:HookScript("OnHide", function(self) Tip.SetBorder(self) end) end
	end
	Tip.SkinAll()
end

ns.On("READY", function() Tip.Install() end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^tooltip%.") or path == "look.opacity" or path == "*") then Tip.SkinAll() end
end)
ns.On("ACCENT_CHANGED", function() Tip.SkinAll() end)
