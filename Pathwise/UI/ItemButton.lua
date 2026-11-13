-- Pathwise quest item button: the item the step wants used, one click (or
-- one key: Key Bindings > Pathwise) away, beside the guide.
--
-- Which item: the quest item of a quest the step is working on (the one
-- the game's own objective tracker offers: GetQuestLogSpecialItemInfo, by
-- C_QuestLog.GetLogIndexForQuestID), else an item a note names ("Use
-- Shrine Bauble") when it is in your bags, or the item a quest to accept
-- starts from (the Befouled Water Globe).
--
-- The button is the game's SecureActionButtonTemplate with type "item": the
-- game uses the item, Pathwise only sets which. Attributes, showing and
-- hiding can't change in combat, so a change waits for combat to end.

local ADDON, ns = ...
local T = ns.Theme
local C = ns.Compat
local B = {}
ns.ItemButton = B

ns.Defaults("itemButton", {
	shown = true,
	point = nil, -- { point, x, y }; nil: beside the guide
})

BINDING_NAME_PATHWISE_ITEM = "Use the step's quest item"
_G["BINDING_NAME_CLICK PathwiseItemButton:LeftButton"] = BINDING_NAME_PATHWISE_ITEM

local function call(fn, ...) if type(fn) == "function" then return fn(...) end end
local function nameOf(link) return type(link) == "string" and link:match("%[(.-)%]") or nil end

local function iconByName(name)
	local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local ok, _, _, _, _, _, _, _, _, _, icon = pcall(get or function() end, name)
	return ok and icon or nil
end

-- The item for the step being followed: { name, icon, quest, link } or nil.
function B.ForStep()
	local E = ns.Engine
	if not E then return nil end
	local goals = E.OpenGoals()
	local L = C_QuestLog
	for _, goal in ipairs(goals) do
		local v, q = goal[1], goal[2]
		if (v == "complete" or v == "turnin") and type(q) == "number" and L and L.GetLogIndexForQuestID then
			local idx = call(L.GetLogIndexForQuestID, q)
			if idx then
				local link, icon = call(GetQuestLogSpecialItemInfo, idx)
				local name = nameOf(link)
				if name then return { name = name, icon = icon, quest = q, link = link } end
			end
		end
	end
	-- A quest started by an item in your bags: using it offers the quest.
	for _, goal in ipairs(goals) do
		local item = E.StartItem and E.StartItem(goal)
		if item and C.ItemCount(item.id) > 0 then
			return { name = item.name, icon = iconByName(item.name), quest = goal[2] }
		end
	end
	for _, goal in ipairs(goals) do
		local text = goal[1] == "note" and goal[2]
		local name = type(text) == "string" and text:match("^[Uu]se (.+)$")
		if name then
			name = name:gsub("%s+$", ""):gsub("%.$", "")
			if C.ItemCount(name) > 0 then return { name = name, icon = iconByName(name) } end
		end
	end
	return nil
end

local button, pending

local function savePoint(f)
	local p, _, _, x, y = f:GetPoint(1)
	ns.Set("itemButton.point", { p, math.floor(x + 0.5), math.floor(y + 0.5) })
end

local function build()
	local b = CreateFrame("Button", "PathwiseItemButton", UIParent, "SecureActionButtonTemplate")
	button = b
	b:SetSize(36, 36)
	b:SetFrameStrata("MEDIUM")
	b:SetClampedToScreen(true)
	b:SetMovable(true)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnDragStart", function(self) if IsShiftKeyDown and IsShiftKeyDown() and not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
	b:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePoint(self) end)
	T.Panel(b, "bg", "border")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 2, -2)
	b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count = T.Text(b, "small", "text", "OVERLAY")
	b.count:SetPoint("BOTTOMRIGHT", -3, 3)
	b:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		if self.link and GameTooltip.SetHyperlink then GameTooltip:SetHyperlink(self.link)
		else ns.Tip.SetText(GameTooltip, self.itemName or "") end
		ns.Tip.AddLine(GameTooltip, "Pathwise: the step's item. Shift-drag to move.", 0.6, 0.6, 0.6, true)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
	local saved = ns.Get("itemButton.point")
	if type(saved) == "table" then
		b:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
	elseif ns.Guide and ns.Guide.Frame and ns.Guide.Frame() then
		-- Beside the guide on screen, whichever style it is.
		b:SetPoint("TOPRIGHT", ns.Guide.Frame(), "TOPLEFT", -8, 0)
	else
		b:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
	b:Hide()
	return b
end

function B.Button() return button end

-- Shows the step's item, or hides the button; after combat if in it.
function B.Update()
	if InCombatLockdown and InCombatLockdown() then pending = true return end
	pending = false
	local item = ns.Get("itemButton.shown") and B.ForStep() or nil
	local b = button or (item and build())
	if not b then return end
	if not item then
		b:Hide()
		b.itemName, b.link = nil, nil
		return
	end
	b:SetAttribute("type", "item")
	b:SetAttribute("item", item.name)
	b.itemName, b.link = item.name, item.link
	b.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
	local n = C.ItemCount(item.name)
	b.count:SetText(n > 1 and tostring(n) or "")
	b:Show()
end

ns.On("GUIDE_UPDATED", function() B.Update() end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function() B.Update() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if pending then B.Update() end end)
ns.On("SETTING_CHANGED", function(path) if path == "itemButton.shown" then B.Update() end end)
