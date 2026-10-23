-- Pathwise Gear in the game's own windows: a line on item tooltips, a gold
-- arrow on bag items that are upgrades, and the best quest reward.
--
-- Hooks, all of the kind that never taints the game's code (as checked for
-- Forever):
--   * tooltips: TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, fn),
--     else GameTooltip's OnTooltipSetItem; forbidden tooltips are skipped
--   * bags: hooksecurefunc on each bag frame's UpdateItems (the client's
--     ContainerFrameContainer.ContainerFrames and ContainerFrameCombinedBags);
--     the arrow is a texture of Pathwise's on the item button, kept here, not
--     in the button's table
--   * quest rewards: QUEST_COMPLETE, the choices read with GetNumQuestChoices
--     and GetQuestItemLink("choice", i); the pick shows on its tooltip and in chat

local ADDON, ns = ...
local S, Gear = Pathwise.Suite, ns.Gear
local T = S.Theme
local H = {}
ns.Hooks = H

local function gold() local c = T.Color("gear") return c[1], c[2], c[3] end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------

local pick -- { link, pct, quest } of the reward panel open now

-- The line for an item: left, right, and the right colour, or nil.
function H.TooltipLine(link)
	if not (S.Get("gear.tooltip") and link) then return nil end
	local up, pct, slot = Gear.IsUpgrade(link)
	local _, name = Gear.Weights()
	local left = "Pathwise Gear · " .. tostring(name)
	if pick and pick.link == link then
		return left, "Best reward for you", T.Color("gear")
	end
	local id = tonumber(tostring(link):match("item:(%d+)"))
	local at = S.Get("gear.bisAlert") ~= false and ns.Best and id and ns.Best.IsBest(id)
	if at then
		local right = at > Gear.Client.Level() and ("Best in slot for level %d"):format(at) or "Best in slot for your level"
		if up and pct then right = ("Best in slot · +%.1f%%"):format(pct) .. (slot and (" · " .. slot) or "") end
		return left, right, T.Color("gear")
	end
	if up then
		local right = pct and ("+%.1f%% upgrade"):format(pct) or "Upgrade (empty slot)"
		if slot then right = right .. " · " .. slot end
		return left, right, T.Color("success")
	end
	local r = Gear.Compare(link)
	if r and not r.usable then
		return left, ({ armor = "You can't wear this armour", weapon = "You can't use this weapon", shield = "You can't use shields" })[r.reason] or "Not for you", T.Color("muted")
	end
	if r and r.reason == "level" then return left, ("From level %d"):format(r.minLevel or 0), T.Color("muted") end
	if r and r.pct and r.delta < 0 then return left, ("%.1f%% worse"):format(-r.pct), T.Color("muted") end
	return nil
end

local function forbidden(tt)
	if not (tt and tt.IsForbidden) then return false end
	local ok, f = pcall(tt.IsForbidden, tt)
	return not ok or f
end

local function addLine(tt)
	if forbidden(tt) or not tt.GetItem then return end
	local ok, _, link = pcall(tt.GetItem, tt)
	if not (ok and link) then return end
	local left, right, c = H.TooltipLine(link)
	if not left then return end
	local r, g, b = gold()
	tt:AddDoubleLine(left, right, r, g, b, c[1], c[2], c[3])
	tt:Show()
end
H.AddLine = addLine

function H.InstallTooltip()
	local P, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and E and E.Item then
		P.AddTooltipPostCall(E.Item, function(tt) addLine(tt) end)
		return "postcall"
	end
	for _, tt in ipairs({ GameTooltip, ItemRefTooltip }) do
		if tt and tt.HookScript then tt:HookScript("OnTooltipSetItem", addLine) end
	end
	return "script"
end

---------------------------------------------------------------------------
-- Bag arrows
---------------------------------------------------------------------------

local arrows = setmetatable({}, { __mode = "k" }) -- item button -> texture
local hooked = setmetatable({}, { __mode = "k" })

local function arrowFor(button)
	local t = arrows[button]
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 3)
		t:SetTexture(T.MEDIA .. "glyph-upgrade")
		t:SetSize(16, 16)
		t:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		local r, g, b = gold()
		t:SetVertexColor(r, g, b)
		arrows[button] = t
	end
	return t
end

local function bagLink(button)
	if not (button.GetBagID and button.GetID) then return nil end
	local ok, bag = pcall(button.GetBagID, button)
	if not ok or not bag then return nil end
	local f = C_Container and C_Container.GetContainerItemLink
	return f and S.Compat.Readable(f(bag, button:GetID())) or nil
end

-- Best in slot for your level (or the level it needs): a gold star.
local stars = setmetatable({}, { __mode = "k" })
local function starFor(button)
	local t = stars[button]
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 4)
		t:SetTexture(T.MEDIA .. "glyph-best")
		t:SetSize(16, 16)
		t:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
		local r, g, b = gold()
		t:SetVertexColor(r, g, b)
		stars[button] = t
	end
	return t
end

function H.MarkFrame(frame)
	if not (frame and frame.EnumerateValidItems) then return end
	local on = S.Get("gear.bags")
	local bis = on and S.Get("gear.bisAlert") ~= false
	for _, button in frame:EnumerateValidItems() do
		local link = on and bagLink(button)
		local up = link and Gear.IsUpgrade(link)
		if up then arrowFor(button):Show() elseif arrows[button] then arrows[button]:Hide() end
		local id = bis and link and tonumber(tostring(link):match("item:(%d+)"))
		local best = id and ns.Best and ns.Best.IsBest(id)
		if best then starFor(button):Show() elseif stars[button] then stars[button]:Hide() end
	end
end

local function bagFrames()
	local out = {}
	local list = ContainerFrameContainer and ContainerFrameContainer.ContainerFrames
	for _, f in ipairs(list or {}) do out[#out + 1] = f end
	if ContainerFrameCombinedBags then out[#out + 1] = ContainerFrameCombinedBags end
	return out
end

function H.InstallBags()
	if not hooksecurefunc then return 0 end
	local n = 0
	for _, f in ipairs(bagFrames()) do
		if not hooked[f] and type(f.UpdateItems) == "function" then
			hooksecurefunc(f, "UpdateItems", H.MarkFrame)
			hooked[f] = true
			n = n + 1
		end
	end
	return n
end

function H.RedrawBags()
	for _, f in ipairs(bagFrames()) do
		if hooked[f] and f.IsShown and f:IsShown() then H.MarkFrame(f) end
	end
end

---------------------------------------------------------------------------
-- Quest rewards
---------------------------------------------------------------------------

-- The choice to take: the biggest upgrade, else the best score you can use.
-- -> index, link, pct (nil when not an upgrade)
function H.BestChoice(links)
	local best, bestKey
	for i, link in ipairs(links) do
		local up, pct = Gear.IsUpgrade(link)
		local r = Gear.Compare(link)
		local usable = r and r.usable and r.reason ~= "level"
		local key
		if up then key = 2000 + (pct or 1000)
		elseif usable and r then key = 1000 + (r.score or 0) / 1000 end
		if key and (not bestKey or key > bestKey) then best, bestKey = i, key end
	end
	if not best then return nil end
	local up, pct = Gear.IsUpgrade(links[best])
	return best, links[best], up and pct or nil
end

local function onQuestComplete()
	pick = nil
	if not S.Get("gear.rewards") then return end
	local n = GetNumQuestChoices and GetNumQuestChoices() or 0
	if n < 2 then return end
	local links = {}
	for i = 1, n do links[i] = GetQuestItemLink and GetQuestItemLink("choice", i) end
	local i, link, pct = H.BestChoice(links)
	if not i then return end
	pick = { link = link, pct = pct }
	S.Print(pct and ("Pathwise Gear: take %s (+%.1f%%)."):format(link, pct) or ("Pathwise Gear: take %s."):format(link))
end
H.OnQuestComplete = onQuestComplete
function H.Pick() return pick end

S.RegisterEvent("QUEST_COMPLETE", onQuestComplete)
S.RegisterEvent("QUEST_FINISHED", function() pick = nil end)

---------------------------------------------------------------------------

S.On("READY", function()
	H.InstallTooltip()
	H.InstallBags()
end)
S.RegisterEvent("BAG_UPDATE_DELAYED", function() H.InstallBags() end)
S.On("GEAR_UPDATED", function() H.RedrawBags() end)
S.On("SETTING_CHANGED", function(path) if path == "gear.bags" or path == "gear.bisAlert" or path == "gear.bisRaids" or path == "gear.minUpgrade" or path == "gear.scale" or path == "gear.spec" then H.RedrawBags() end end)
