-- Pathwise Bags: what is in the bags, and what each item is to this
-- character: keep it (a quest needs it, your profession route needs it, a
-- gear upgrade), or let it go (junk, a finished quest's leftover, gear you
-- cannot use or that is worse than what you wear).
--
--   Items.Scan() -> { entry, ... }      every filled bag slot, with its facts
--   Items.Facts(entry) -> facts         { category, tags = { name = true }, why, sell }
--   Items.Mark(itemID, "keep" | "junk" | nil)   the player's own marks
--
-- Client calls (Blizzard's Forever API documentation, ContainerDocumentation):
-- C_Container.GetContainerNumSlots, GetContainerItemInfo (itemID, stackCount,
-- quality, hasNoValue, isBound, itemName, hyperlink), GetContainerItemQuestInfo.
-- C_Item.GetItemInfo for sell price, type and slot.
-- Inspired by what Bagnon and Baganator offer (categories, junk, search);
-- none of their code is used (Bagnon is All Rights Reserved; Baganator's
-- source is not public).

local ADDON, ns = ...
local S = Pathwise.Suite
local Items = {}
ns.Items = Items
Pathwise.Bags = Items
local readable = S.Compat.Readable

S.Defaults("bags", {
	marks = nil, -- per character: { [itemID] = "keep" | "junk" } (kept in CharState)
})

Items.BAGS = { 0, 1, 2, 3, 4 }

-- Categories in the order the window shows them.
Items.CATEGORIES = {
	{ key = "quest", name = "Quest" },
	{ key = "upgrade", name = "Upgrades" },
	{ key = "equipment", name = "Equipment" },
	{ key = "consumable", name = "Consumables" },
	{ key = "profession", name = "Professions" },
	{ key = "other", name = "Other" },
	{ key = "junk", name = "Junk" },
}

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g, h, i, j, k, l, m, n = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g, h, i, j, k, l, m, n
end

---------------------------------------------------------------------------
-- The player's marks (per character)
---------------------------------------------------------------------------

local function marks()
	local c = S.CharState()
	c.bags = type(c.bags) == "table" and c.bags or {}
	c.bags.marks = type(c.bags.marks) == "table" and c.bags.marks or {}
	return c.bags.marks
end

function Items.Mark(id, what)
	if not id then return end
	marks()[id] = (what == "keep" or what == "junk") and what or nil
	S.Fire("BAGS_CHANGED")
end
function Items.MarkOf(id) return id and marks()[id] end
function Items.Marks() return marks() end

---------------------------------------------------------------------------
-- What quests and professions need
---------------------------------------------------------------------------

-- itemID -> { questID, ... } that ask for it (objectives) or start with it.
local needs
local function questNeeds()
	if needs then return needs end
	needs = {}
	local D = S.Data
	for qid, q in pairs(D and D.quests or {}) do
		for _, o in ipairs(q[12] or {}) do
			if o[1] == "i" and o[2] then
				needs[o[2]] = needs[o[2]] or {}
				table.insert(needs[o[2]], qid)
			end
		end
		for _, it in ipairs(q[9] or {}) do
			needs[it] = needs[it] or {}
			table.insert(needs[it], qid)
		end
	end
	return needs
end

-- For item `id`: the quest in your log that needs it, else one you can still
-- do, else "done" when every quest that wants it is behind you.
-- -> "log", questID | "later", questID | "done" | nil
local function questUse(id)
	local list = questNeeds()[id]
	if not list then return nil end
	local Q = S.Quests
	local p = Q.Player()
	local later, any = nil, false
	for _, q in ipairs(list) do
		if Q.ForPlayer(q, p) then
			any = true
			if Q.OnQuest(q) then return "log", q end
			if not Q.Done(q) and not Q.Closed(q) and not later then later = q end
		end
	end
	if later then return "later", later end
	if any then return "done" end
	return nil
end
Items.QuestUse = questUse

-- itemID -> profession name, for materials your profession routes still ask
-- for (Pathwise's Shopping list per profession you have).
local profNeeds, profAt
local function professionNeeds()
	local now = GetTime and GetTime() or 0
	if profNeeds and profAt and now - profAt < 5 then return profNeeds end
	profNeeds, profAt = {}, now
	local P = S.Professions
	for _, k in ipairs(P and P.Known and P.Known() or {}) do
		if k.prof.kind == "craft" and P.Shopping then
			local ok, rows = pcall(P.Shopping, k.prof)
			for _, r in ipairs(ok and rows or {}) do
				if r.item and not profNeeds[r.item] then profNeeds[r.item] = k.prof.name end
			end
		end
	end
	return profNeeds
end

---------------------------------------------------------------------------
-- The bags
---------------------------------------------------------------------------

-- One filled slot: { bag, slot, id, link, count, quality, name, noValue,
-- bound, quest = { isQuestItem, questID, isActive }, sell (copper each),
-- classID, subclassID, equipLoc, minLevel }
function Items.Slot(bag, slot)
	local Cn = C_Container
	local info = Cn and call(Cn.GetContainerItemInfo, bag, slot)
	if type(info) ~= "table" then return nil end
	local id = readable(info.itemID)
	if not id then return nil end
	local e = {
		bag = bag, slot = slot, id = id,
		link = readable(info.hyperlink) or ("item:" .. id),
		count = readable(info.stackCount) or 1,
		quality = readable(info.quality),
		name = readable(info.itemName),
		noValue = readable(info.hasNoValue) and true or false,
		bound = readable(info.isBound) and true or false,
	}
	local q = Cn.GetContainerItemQuestInfo and call(Cn.GetContainerItemQuestInfo, bag, slot)
	if type(q) == "table" then
		e.quest = { isQuestItem = readable(q.isQuestItem) and true or false, questID = readable(q.questID), isActive = readable(q.isActive) and true or false }
	end
	local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local name, _, quality, ilvl, minLevel, _, _, _, equipLoc, _, sell, classID, subclassID = call(f, id)
	e.name = e.name or readable(name)
	e.quality = e.quality or readable(quality)
	e.minLevel, e.equipLoc, e.ilvl = readable(minLevel), readable(equipLoc), readable(ilvl)
	e.sell = readable(sell) or 0
	e.classID, e.subclassID = readable(classID), readable(subclassID)
	return e
end

function Items.NumSlots(bag)
	local Cn = C_Container
	return (Cn and readable(call(Cn.GetContainerNumSlots, bag))) or 0
end

function Items.Scan()
	local out = {}
	for _, bag in ipairs(Items.BAGS) do
		for slot = 1, Items.NumSlots(bag) do
			local e = Items.Slot(bag, slot)
			if e then
				e.facts = Items.Facts(e)
				out[#out + 1] = e
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Facts
---------------------------------------------------------------------------

local Gear = function() return Pathwise.Gear end

-- -> { category, tags = { ... }, why = "text", sell = true when it can go to a vendor }
function Items.Facts(e)
	local tags, why, category = {}, nil, "other"
	local mark = Items.MarkOf(e.id)
	local isEquip = e.equipLoc and e.equipLoc ~= "" and e.equipLoc ~= "INVTYPE_BAG" and (e.classID == 2 or e.classID == 4)

	-- Category by what it is.
	if e.classID == 12 or (e.quest and e.quest.isQuestItem) then category = "quest"
	elseif isEquip then category = "equipment"
	elseif e.classID == 0 then category = "consumable"
	elseif e.classID == 7 or e.classID == 9 then category = "profession" end

	-- What this character needs it for.
	local use, q = questUse(e.id)
	if e.quest and e.quest.questID and e.quest.isActive then use, q = "log", e.quest.questID end
	if use == "log" then
		tags.quest = true
		why = "Needed for " .. S.Quests.Name(q)
		category = "quest"
	elseif use == "later" then
		tags.quest = true
		why = "For a quest later: " .. S.Quests.Name(q)
		category = "quest"
	elseif use == "done" and category == "quest" then
		tags.questDone = true
		why = "Its quests are done"
	end
	local prof = professionNeeds()[e.id]
	if prof then
		tags.profession = true
		why = why or ("For your " .. prof .. " route")
		category = category == "other" and "profession" or category
	end
	if isEquip and Gear() then
		local G = Gear()
		local ok, up, pct = pcall(G.IsUpgrade, e.link)
		local best = Pathwise.GearBest and Pathwise.GearBest.IsBest and Pathwise.GearBest.IsBest(e.id)
		if best then
			tags.best = true
			why = why or "Best in slot for your level"
			category = "upgrade"
		elseif ok and up then
			tags.upgrade = true
			why = why or (pct and ("Upgrade: +%.1f%%"):format(pct) or "Upgrade: an empty slot")
			category = "upgrade"
		else
			local r = G.Compare and select(2, pcall(G.Compare, e.link))
			if type(r) == "table" and not r.usable then
				tags.unusable = true
				why = why or "You can't use it"
			elseif type(r) == "table" and r.reason ~= "level" and r.delta and r.delta < 0 then
				tags.worse = true
				why = why or ("Worse than what you wear (%.0f%%)"):format(r.pct or 0)
			end
		end
	end

	-- Junk: grey with a vendor price, or marked by you.
	if e.quality == 0 and not e.noValue then tags.junk = true why = why or "Junk (grey)" end
	if mark == "junk" then tags.junk = true tags.marked = true why = "Marked as junk" end
	if mark == "keep" then
		tags.keep = true
		tags.junk = nil
		why = "Kept by you"
	end
	if tags.junk then category = "junk" end

	-- Can it go to a vendor? Never what you keep or need; only with a price.
	local needed = tags.keep or tags.quest or tags.profession or tags.upgrade or tags.best
	local sell = not needed and not e.noValue and (e.sell or 0) > 0
		and (tags.junk or tags.unusable or tags.worse or tags.questDone) and true or false
	return { category = category, tags = tags, why = why, sell = sell }
end

-- Money as "1g 23s 45c".
function Items.Money(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local out = {}
	if g > 0 then out[#out + 1] = g .. "g" end
	if s > 0 then out[#out + 1] = s .. "s" end
	if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
	return table.concat(out, " ")
end
