-- Pathwise Bags: selling junk at a vendor.
--
-- When a merchant opens, a "Sell junk" button sits on the merchant window
-- with how many items and how much gold. Clicking it sells them one by one
-- (C_Container.UseContainerItem with the merchant open sells an item; its
-- documentation asks for an untainted call, so it runs from your click).
-- "Sell on its own" sells as the window opens instead, for those who want it.
--
-- What is sold: grey items with a price and items you marked as junk.
-- With "Also sell bound gear you can't use or is worse" on: soulbound
-- equipment that is not for you, and leftovers of quests you finished.
-- Never: what you keep, quest items you still need, profession materials
-- your route needs, upgrades, items with no price.

local ADDON, ns = ...
local S, Items = Pathwise.Suite, ns.Items
local Sell = {}
ns.Sell = Sell
local T = S.Theme

S.Defaults("bags", {
	sellAuto = false,
	sellBound = false,
})

-- What would be sold now: { entry, ... }, total copper.
function Sell.List()
	local out, total = {}, 0
	for _, e in ipairs(Items.Scan()) do
		local f = e.facts
		local ok = f.sell and (f.tags.junk or (S.Get("bags.sellBound") and e.bound and (f.tags.unusable or f.tags.worse or f.tags.questDone)))
		if ok then
			out[#out + 1] = e
			total = total + (e.sell or 0) * (e.count or 1)
		end
	end
	table.sort(out, function(a, b) return (a.sell or 0) * (a.count or 1) < (b.sell or 0) * (b.count or 1) end)
	return out, total
end

local merchantOpen = false
local queue, sold, earned

local function step()
	if not (queue and merchantOpen) then queue = nil return end
	local e = table.remove(queue, 1)
	if not e then
		queue = nil
		if sold > 0 then
			S.Print(("Pathwise Bags: sold %d item%s for %s."):format(sold, sold == 1 and "" or "s", Items.Money(earned)))
			if sold > 12 then S.Print("Pathwise Bags: the vendor's buyback only keeps the last 12.") end
		end
		S.Fire("BAGS_CHANGED")
		return
	end
	-- Still the same item in that slot? (Bags move while selling.)
	local now = Items.Slot(e.bag, e.slot)
	if now and now.id == e.id then
		local ok = pcall(C_Container.UseContainerItem, e.bag, e.slot)
		if ok then
			sold = sold + 1
			earned = earned + (e.sell or 0) * (e.count or 1)
		end
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.15, step) else step() end
end

-- Sell the list. -> number of items queued
function Sell.Run()
	if not merchantOpen or queue then return 0 end
	if not (C_Container and C_Container.UseContainerItem) then return 0 end
	local list = Sell.List()
	if #list == 0 then return 0 end
	queue, sold, earned = list, 0, 0
	step()
	return #list
end

function Sell.IsMerchantOpen() return merchantOpen end

---------------------------------------------------------------------------
-- The button on the merchant window
---------------------------------------------------------------------------

local button
local function refresh()
	if not button then return end
	local list, total = Sell.List()
	button.pwText:SetText(#list > 0 and ("Sell junk: %d  ·  %s"):format(#list, Items.Money(total)) or "No junk to sell")
	button:SetWidth(math.max(120, (button.pwText:GetStringWidth() or 60) + 28))
	button:SetEnabled(#list > 0)
	button:SetShown(merchantOpen)
end
Sell.Refresh = refresh

local function ensureButton()
	if button or not MerchantFrame then return end
	-- Made with no parent, then placed: it never touches the merchant frame's own code.
	button = T.Button(nil, "Sell junk", "accent", function() Sell.Run() end)
	button:SetParent(MerchantFrame)
	button:SetFrameStrata("HIGH")
	button:SetPoint("BOTTOMLEFT", MerchantFrame, "TOPLEFT", 4, 4)
	local c = T.Color("bags")
	if button.pwText then button.pwText:SetTextColor(c[1], c[2], c[3], 1) end
	button:Hide()
	Sell.Button = button
end

S.RegisterEvent("MERCHANT_SHOW", function()
	merchantOpen = true
	ensureButton()
	refresh()
	if S.Get("bags.sellAuto") then Sell.Run() end
end)
S.RegisterEvent("MERCHANT_CLOSED", function()
	merchantOpen = false
	queue = nil
	if button then button:Hide() end
end)
S.RegisterEvent("BAG_UPDATE_DELAYED", function() if merchantOpen and not queue then refresh() end end)
S.On("BAGS_CHANGED", function() if merchantOpen and not queue then refresh() end end)
