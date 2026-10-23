-- Pathwise Bags: bag space. How many slots are free, a warning when the bags
-- are nearly full, and what to let go first to make room.
--
--   Space.Free() -> free, total        general slots (a quiver or soul bag's own slots not counted)
--   Space.MakeRoom(n) -> { entry, ... } what to sell or drop first: junk, then
--       what you cannot use or no longer need, cheapest first

local ADDON, ns = ...
local S, Items = Pathwise.Suite, ns.Items
local Space = {}
ns.Space = Space
local readable = S.Compat.Readable

S.Defaults("bags", { warnAt = 2, warn = true })

function Space.Free()
	local Cn = C_Container
	local free, total = 0, 0
	for _, bag in ipairs(Items.BAGS) do
		local n = Items.NumSlots(bag)
		if n > 0 and Cn and Cn.GetContainerNumFreeSlots then
			local ok, f, family = pcall(Cn.GetContainerNumFreeSlots, bag)
			f, family = ok and readable(f) or 0, ok and readable(family) or 0
			-- Family 0 is a general bag; others (quivers, soul bags) take only their own kind.
			if family == 0 or family == nil then
				free = free + f
				total = total + n
			end
		end
	end
	return free, total
end

-- The order to make room in: junk first, then what can go (bound gear you
-- cannot use or that is worse, leftovers of finished quests), cheapest first.
function Space.MakeRoom(n)
	local list = {}
	for _, e in ipairs(Items.Scan()) do
		local t = e.facts.tags
		if not (t.keep or t.quest or t.profession or t.upgrade or t.best) then
			local rank
			if t.junk then rank = 1
			elseif t.questDone then rank = 2
			elseif t.unusable or t.worse then rank = 3 end
			if rank then e.rank = rank list[#list + 1] = e end
		end
	end
	table.sort(list, function(a, b)
		if a.rank ~= b.rank then return a.rank < b.rank end
		return (a.sell or 0) * (a.count or 1) < (b.sell or 0) * (b.count or 1)
	end)
	while n and #list > n do table.remove(list) end
	return list
end

-- The warning: once when the free slots fall to the limit, again only after
-- they have gone back above it.
local warned = false
function Space.Check()
	local free = Space.Free()
	local limit = S.Get("bags.warnAt") or 2
	if not S.Get("bags.warn") then return free end
	if free <= limit and not warned then
		warned = true
		local first = Space.MakeRoom(1)[1]
		local text = free == 0 and "Your bags are full" or ("Bags nearly full: %d slot%s left"):format(free, free == 1 and "" or "s")
		local c = S.Theme.Color("warning")
		if UIErrorsFrame and UIErrorsFrame.AddMessage then pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, c[1], c[2], c[3]) end
		S.Print("Pathwise Bags: " .. text .. (first and (". First to go: %s (%s)."):format(first.link or first.name or "?", first.facts.why or "") or "."))
		S.Fire("BAGS_SPACE_WARNING", free)
	elseif free > limit then
		warned = false
	end
	return free
end

S.RegisterEvent("BAG_UPDATE_DELAYED", function() Space.Check() end)
S.On("READY", function() warned = false Space.Check() end)
