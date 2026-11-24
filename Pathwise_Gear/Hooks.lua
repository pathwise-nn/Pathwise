-- Pathwise Gear in the game's own windows: a line on item tooltips (how
-- much better or worse, and the stats that make it so), an arrow on bag
-- items that are upgrades (gold; bigger for a big one; grey for one you
-- can wear from a later level), a chat line when you pick up an upgrade,
-- and the best quest reward.
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
local S, Gear = ns.S, ns.Gear
local T = S.Theme
local H = {}
ns.Hooks = H

local function gold() local c = T.Color("gear") return c[1], c[2], c[3] end

---------------------------------------------------------------------------
-- Tooltip line
---------------------------------------------------------------------------

local pick -- { link, pct, quest } of the reward panel open now

-- "Intellect +6, Spirit -3": the stats that make the difference, the ones
-- worth most to you first.
function H.ChangesText(changes, n)
	local NAMES = ns.Panel and ns.Panel.NAMES or {}
	local out = {}
	for i, c in ipairs(changes or {}) do
		if i > (n or 3) then break end
		local d = c.diff == math.floor(c.diff) and ("%d"):format(math.abs(c.diff)) or ("%.1f"):format(math.abs(c.diff))
		out[#out + 1] = ("%s %s%s"):format(NAMES[c.key] or c.key, c.diff > 0 and "+" or "-", d)
	end
	return table.concat(out, ", ")
end

-- The line for an item: left, right, the right colour, and the stats line
-- (or nil); nil when there is nothing to say.
function H.TooltipLine(link)
	if not (S.Get("gear.tooltip") and link) then return nil end
	local up, pct, slot = Gear.IsUpgrade(link)
	local v = Gear.Verdict(link)
	local detail = v and v.changes and #v.changes > 0 and H.ChangesText(v.changes) or nil
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
		return left, right, T.Color("gear"), detail
	end
	if not v or v.grade == "equipped" then return nil end
	local where = v.slot and (" · " .. v.slot) or ""
	local g = v.grade
	if g == "big" then return left, ("+%.1f%% big upgrade%s"):format(v.pct, where), T.Color("success"), detail end
	if g == "up" then return left, ("+%.1f%% upgrade%s"):format(v.pct, where), T.Color("success"), detail end
	if g == "empty" then return left, "Upgrade (empty slot)" .. where, T.Color("success"), detail end
	if g == "later" then
		return left, ("Upgrade at level %d%s"):format(v.minLevel or 0, v.pct and (" (+%.1f%%)"):format(v.pct) or ""), T.Color("warning"), detail
	end
	if g == "cant" then
		return left, ({ armor = "You can't wear this armour", weapon = "You can't use this weapon", shield = "You can't use shields" })[v.reason] or "Not for you", T.Color("muted")
	end
	local later = v.minLevel and v.minLevel > Gear.Client.Level() and (" · from level %d"):format(v.minLevel) or ""
	if g == "same" then
		return left, (v.pct and ("About the same (%+.1f%%)"):format(v.pct) or "About the same") .. later, T.Color("text2"), detail
	end
	if g == "worse" then return left, ("%.1f%% worse"):format(-v.pct) .. later, T.Color("muted"), detail end
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
	local left, right, c, detail = H.TooltipLine(link)
	if not left then return end
	local r, g, b = gold()
	tt:AddDoubleLine(left, right, r, g, b, c[1], c[2], c[3])
	if detail then
		local m = T.Color("text2")
		tt:AddDoubleLine(" ", detail, r, g, b, m[1], m[2], m[3])
	end
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
		arrows[button] = t
	end
	return t
end

-- The arrow for a verdict: gold, bigger for a big upgrade, grey for one
-- from a later level; nil for none.
local function arrowLook(link)
	local v = Gear.Verdict(link)
	local g = v and v.grade
	if g == "big" then return 20, gold() end
	if g == "up" or g == "empty" then return 16, gold() end
	if g == "later" then local c = T.Color("muted") return 14, c[1], c[2], c[3] end
	return nil
end
H.ArrowLook = arrowLook

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
		local size, r, g, b
		if link then size, r, g, b = arrowLook(link) end
		if size then
			local t = arrowFor(button)
			t:SetSize(size, size)
			t:SetVertexColor(r, g, b)
			t:Show()
		elseif arrows[button] then arrows[button]:Hide() end
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
-- Picked up: an upgrade for you is named in chat as soon as it is in your
-- bags (a best in slot item says so itself, Best.lua).
---------------------------------------------------------------------------

S.Defaults("gear", { alert = true })

local had          -- links in the bags and worn at the last look; nil before the first
local waiting = {} -- new items the game had not described yet: judged when it does

local function bagLinks()
	local out = {}
	local Cn = C_Container
	if Cn and Cn.GetContainerNumSlots and Cn.GetContainerItemLink then
		for bag = 0, 4 do
			local ok, n = pcall(Cn.GetContainerNumSlots, bag)
			n = ok and S.Compat.Readable(n) or 0
			for slot = 1, n do
				local ok2, link = pcall(Cn.GetContainerItemLink, bag, slot)
				link = ok2 and S.Compat.Readable(link)
				if link then out[link] = (out[link] or 0) + 1 end
			end
		end
	end
	-- Worn too, so taking something off is not a new item.
	for slot = 1, 18 do
		local link = Gear.Client.Equipped(slot)
		if link then out[link] = (out[link] or 0) + 1 end
	end
	return out
end

-- Says so in chat when the item is an upgrade. -> its grade ("best" when
-- Best in Slot announces it instead), or nil
function H.Announce(link)
	local id = tonumber(tostring(link):match("item:(%d+)"))
	if ns.Hunts and id and ns.Hunts.Claimed(id) then return "hunt" end
	if S.Get("gear.bisAlert") ~= false and ns.Best and id and ns.Best.IsBest(id) then return "best" end
	local v = Gear.Verdict(link)
	if not v then return nil end
	local g = v.grade
	if not (g == "big" or g == "up" or g == "empty" or g == "later") then return g end
	local how = (g == "big" and ("a big upgrade (+%.1f%%)"):format(v.pct))
		or (g == "up" and ("an upgrade (+%.1f%%)"):format(v.pct))
		or (g == "empty" and "an upgrade (an empty slot)")
		or ("an upgrade from level %d%s"):format(v.minLevel or 0, v.pct and (" (+%.1f%%)"):format(v.pct) or "")
	local why = v.changes and #v.changes > 0 and (": " .. H.ChangesText(v.changes)) or ""
	S.Print(("%s is %s%s%s."):format(link, how, v.slot and (" for your " .. v.slot:lower()) or "", why))
	S.Fire("GEAR_UPGRADE_PICKED", link, g)
	return g
end

-- New since the last look (the first look only counts).
function H.CheckBags()
	local now = bagLinks()
	if had and S.Get("gear.alert") then
		for link, n in pairs(now) do
			if n > (had[link] or 0) then
				if Gear.Compare(link) then H.Announce(link) else waiting[link] = true end
			end
		end
	end
	had = now
end

-- The game described an item: judge the ones that were waiting.
function H.CheckWaiting()
	for link in pairs(waiting) do
		if Gear.Compare(link) then
			waiting[link] = nil
			if S.Get("gear.alert") and had and had[link] then H.Announce(link) end
		end
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
	S.Print(pct and ("take %s (+%.1f%%)."):format(link, pct) or ("take %s."):format(link))
end
H.OnQuestComplete = onQuestComplete
function H.Pick() return pick end

S.RegisterEvent("QUEST_COMPLETE", onQuestComplete)
S.RegisterEvent("QUEST_FINISHED", function() pick = nil end)

---------------------------------------------------------------------------

-- Pathwise's quest automation takes this pick when Rewards is on.
if S.SetRewardChooser then S.SetRewardChooser(function(links) return (H.BestChoice(links)) end) end

S.On("READY", function()
	H.InstallTooltip()
	H.InstallBags()
	had = nil
	H.CheckBags()
end)
S.RegisterEvent("BAG_UPDATE_DELAYED", function() H.InstallBags() H.CheckBags() end)
S.On("GEAR_UPDATED", function() H.RedrawBags() if next(waiting) then H.CheckWaiting() end end)
S.On("SETTING_CHANGED", function(path) if path == "gear.bags" or path == "gear.bisAlert" or path == "gear.bisRaids" or path == "gear.minUpgrade" or path == "gear.scale" or path == "gear.spec" then H.RedrawBags() end end)
