-- Pathwise Gear: the best gear for my level, slot by slot, and where to get
-- it, so a player can chase what they are missing.
--
--   Best.List() -> { { slot, name, id, link, score, pct, have, source, place }, ... }, pending
--   Best.Chase(entry)   point the arrow at where the item comes from
--
-- Which items: Pathwise's data (tools/data/build.lua, "gear"): every weapon
-- and armour piece QuestieDB's Forever data knows a source for (quest
-- reward, monster drop, vendor), with its required level. Stats, slot and
-- quality come from the game client (C_Item), so they are Forever's own;
-- items the client has not loaded yet are asked for
-- (C_Item.RequestLoadItemDataByID) and the list fills in as they arrive.
-- Scores are the same as everywhere in Pathwise Gear: the spec's weights.
-- Nothing is taken from any BiS site: the list is worked out in game.

local ADDON, ns = ...
local S, Gear, W = Pathwise.Suite, ns.Gear, ns.Weights
local Client = Gear.Client
local Best = {}
ns.Best = Best
local readable = S.Compat.Readable

S.Defaults("gear", {
	bisAhead = 0, bisRaids = false,
	bisCrafted = "all", -- "all" (anyone's crafts: the Auction House), "mine" (my professions), "off"
	bisSod = true, -- Season of Discovery recipes (in the client; some found in Forever)
})

-- Data layout (tools/data/build.lua): gear[id] = { requiredLevel, itemLevel,
-- class, subClass, rewardQuests, dropNpcs, vendors, worldDrop, dungeon,
-- craft = { skillLine, skill, spell, recipeItem, sod, bindsOnPickup } }
local REQ, CLASS, SUB, QUESTS, DROPS, VENDORS, WORLD, DUNGEON, CRAFT = 1, 3, 4, 5, 6, 7, 8, 9, 10
local DUAL_WIELD = 674

-- The slots of the list, in the character frame's order.
local ORDER = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
Best.ORDER = ORDER

local function data() return (S.Data and S.Data.gear) or {} end

-- Cheap checks from the data alone, before asking the client: level, and
-- armour or weapon type this class can never use.
local function mayUse(g, class, maxLevel)
	if (g[REQ] or 0) > maxLevel then return false end
	local wear = W.WEAR[class]
	if not wear then return true end
	if g[CLASS] == 4 then
		local sub = g[SUB]
		if sub == 6 then return wear.shield and true or false end
		if sub and sub >= 1 and sub <= 4 then return sub <= (wear.at40 or wear.armor) end
		return true
	elseif g[CLASS] == 2 then
		return wear.weapons[g[SUB]] and true or false
	end
	return true
end

local SIDE = { Horde = "H", Alliance = "A" }

-- Can this character get it? A quest reward needs a quest this race and
-- class may take, from a giver of its side, not done or closed already.
-- A vendor of the other side does not count.
local function sources(g, p)
	local Q, D = S.Quests, S.Data
	local side = SIDE[p.faction]
	local out = {}
	for _, q in ipairs(g[QUESTS] or {}) do
		if Q and Q.Get(q) and Q.ForPlayer(q, p) and not Q.Closed(q) then
			local giver = Q.Get(q)[7]
			local npc = giver and D.npcs[giver[1]]
			local gs = npc and npc[4]
			if not gs or gs == "AH" or not side or gs == side then
				out[#out + 1] = { kind = "quest", id = q, done = Q.Done(q) }
			end
		end
	end
	if g[DUNGEON] then out[#out + 1] = { kind = "dungeon", id = g[DUNGEON], npc = g[DROPS] and g[DROPS][1] }
	elseif g[DROPS] then out[#out + 1] = { kind = "drop", id = g[DROPS][1] } end
	for _, v in ipairs(g[VENDORS] or {}) do
		local npc = D.npcs[v]
		local vs = npc and npc[4]
		if not vs or vs == "AH" or not side or vs == side then out[#out + 1] = { kind = "vendor", id = v } break end
	end
	if g[WORLD] then out[#out + 1] = { kind = "world" } end
	-- Crafted: by you (your profession), else by anyone (the Auction House,
	-- unless it binds on pickup). Your own craft goes first.
	local c = g[CRAFT]
	local crafted = S.Get("gear.bisCrafted") or "all"
	if c and crafted ~= "off" and (S.Get("gear.bisSod") or not c[5]) then
		local rank = p.professions and p.professions[c[1]]
		local s = { kind = "craft", line = c[1], skill = c[2], spell = c[3], recipeItem = c[4], sod = c[5], bop = c[6], mine = rank ~= nil, rank = rank }
		if s.mine then table.insert(out, 1, s)
		elseif crafted == "all" and not s.bop then out[#out + 1] = s end
	end
	-- A quest done already gave its reward (or another one): only other ways count.
	local open = {}
	for _, s in ipairs(out) do if not s.done then open[#open + 1] = s end end
	return open
end

-- The character's professions: { [skillLine] = rank }.
local function professions()
	local out = {}
	local P = S.Professions
	for _, k in ipairs(P and P.Known and P.Known() or {}) do out[k.prof.line] = k.rank end
	return out
end

local function professionName(line)
	local P = S.Professions
	local p = P and P.BY_LINE and P.BY_LINE[line]
	return p and p.name or ("Profession " .. tostring(line))
end

-- The recipe item's name (the client's, else Pathwise's data).
local function recipeName(id)
	if not id then return nil end
	local I = C_Item
	if I and I.GetItemNameByID then
		local ok, n = pcall(I.GetItemNameByID, id)
		n = ok and readable(n)
		if n then return n end
	end
	local it = S.Data.items and S.Data.items[id]
	return it and it[1] or nil
end

-- Where a recipe item comes from: a vendor first, else a monster that drops it.
-- -> { kind = "vendor" | "drop", npc } or nil
local function recipePlace(id)
	local it = id and S.Data.items and S.Data.items[id]
	if not it then return nil end
	if it[4] and it[4][1] then return { kind = "vendor", npc = it[4][1] } end
	if it[2] and it[2][1] then return { kind = "drop", npc = it[2][1] } end
	return nil
end
Best.RecipePlace = recipePlace

-- Do I know this recipe? From the profession window as last read (Pathwise
-- reads it when it opens), else unknown (nil).
local function knowsRecipe(line, spell)
	local P = S.Professions
	local list = P and P.Recipes and P.Recipes(line)
	local r = list and list[spell]
	if r then return r.learned and true or false end
	return nil
end

local function npcName(id) local n = S.Data.npcs[id] return n and n[1] end

-- "Quest: Name", "Dungeon: Name (Boss)", "Drop: Monster", "Vendor: Name", "World drop".
function Best.SourceText(s)
	if not s then return "Unknown source" end
	if s.kind == "quest" then return "Quest: " .. S.Quests.Name(s.id) end
	if s.kind == "dungeon" then
		local d = S.Dungeons and S.Dungeons.Get(s.id)
		local boss = s.npc and npcName(s.npc)
		return "Dungeon: " .. (d and d.name or "?") .. (boss and (" (" .. boss .. ")") or "")
	end
	if s.kind == "drop" then return "Drop: " .. (npcName(s.id) or "a monster") end
	if s.kind == "vendor" then return "Vendor: " .. (npcName(s.id) or "a vendor") end
	if s.kind == "craft" then
		local prof = ("%s %d"):format(professionName(s.line), s.skill or 1)
		local text
		if s.mine then
			local known = knowsRecipe(s.line, s.spell)
			if known then text = ("Craft it: %s (you know it)"):format(prof)
			elseif (s.rank or 0) >= (s.skill or 1) then text = ("Craft it: %s (your skill is enough)"):format(prof)
			else text = ("Craft it at %s (you have %d)"):format(prof, s.rank or 0) end
		else
			text = ("Crafted: %s (Auction House or a crafter)"):format(prof)
		end
		local place = recipePlace(s.recipeItem)
		if s.mine and s.recipeItem and knowsRecipe(s.line, s.spell) ~= true then
			local rn = recipeName(s.recipeItem) or "its recipe"
			if place then text = text .. ("  ·  %s from %s"):format(rn, npcName(place.npc) or (place.kind == "vendor" and "a vendor" or "a monster"))
			else text = text .. "  ·  needs " .. rn end
		end
		if s.sod then text = text .. "  ·  Season of Discovery recipe: found in Forever, not confirmed" end
		return text
	end
	return "World drop (random monsters)"
end

-- Point the arrow at the source: the quest giver, the dungeon's entrance,
-- the monster or the vendor (nearest spawn). -> true when it could.
function Best.Chase(entry)
	local s = entry and entry.source
	if not s then return false end
	if s.kind == "dungeon" then return S.Dungeons.GuideTo(s.id) end
	local Q = S.Quests
	local here
	do
		if S.Compat.PlayerMapPosition then
			local map, x, y = S.Compat.PlayerMapPosition()
			if map and x and y then here = { map = map, x = x, y = y } end
		end
	end
	if s.kind == "quest" then
		local p = Q.Giver(s.id, here)
		return p and S.SetWaypoint(p.map, p.x, p.y, Q.Name(s.id) .. " (" .. tostring(p.name) .. ")") or false
	end
	-- A craft: to the recipe's vendor or the monster that drops it, when you
	-- do not know the recipe yet.
	if s.kind == "craft" then
		local place = s.mine and knowsRecipe(s.line, s.spell) ~= true and recipePlace(s.recipeItem)
		if not place then return false end
		s = { kind = place.kind, id = place.npc }
	end
	if s.kind == "drop" or s.kind == "vendor" then
		local n = S.Data.npcs[s.id]
		if not n then return false end
		local map, x, y = Q.Nearest(n[5], here)
		return map and S.SetWaypoint(map, x, y, n[1] .. " · " .. (entry.name or "")) or false
	end
	return false
end

---------------------------------------------------------------------------
-- Loading items from the client
---------------------------------------------------------------------------

local requested = {}
local function cached(id)
	local I = C_Item
	if I and I.IsItemDataCachedByID then
		local ok, yes = pcall(I.IsItemDataCachedByID, id)
		if ok then return readable(yes) and true or false end
	end
	return Client.Info("item:" .. id) ~= nil
end

local function request(id)
	if requested[id] then return end
	requested[id] = true
	local I = C_Item
	if I and I.RequestLoadItemDataByID then pcall(I.RequestLoadItemDataByID, id) end
end

local function have(id)
	local I = C_Item
	local f = I and I.GetItemCount
	if not f then return false end
	local ok, n = pcall(f, id, true)
	return ok and (readable(n) or 0) > 0
end

---------------------------------------------------------------------------
-- The list
---------------------------------------------------------------------------

local lists = {} -- key -> { list, pending }

function Best.Clear() lists = {} end

-- What a list depends on: the level it is for, class, spec or scale, settings.
local function key(maxLevel)
	local class = Client.Class()
	local _, name, from = Gear.Weights()
	local profs = {}
	for line, rank in pairs(professions()) do profs[#profs + 1] = line .. "=" .. rank end
	table.sort(profs)
	return table.concat({ tostring(class), Client.Level(), maxLevel, tostring(name), tostring(from),
		tostring(S.Get("gear.bisRaids")), tostring(S.Get("gear.bisCrafted")), tostring(S.Get("gear.bisSod")),
		table.concat(profs, ","), tostring(Client.Knows(DUAL_WIELD)) }, "|")
end

-- The list for the player's level (and the levels ahead they chose to see).
function Best.List()
	local list, pending = Best.ListFor(Client.Level() + (S.Get("gear.bisAhead") or 0))
	-- Bags change all the time: whether you have it is looked at each time.
	for _, e in ipairs(list) do e.have = e.wearing or have(e.id) end
	return list, pending
end

-- The best per slot among the items this character can get up to maxLevel.
function Best.ListFor(maxLevel)
	local k = key(maxLevel)
	if lists[k] then return lists[k][1], lists[k][2] end
	local class, level = Client.Class(), Client.Level()
	local raids = S.Get("gear.bisRaids")
	local p = S.Quests.Player()
	p.professions = professions()
	local dual = Client.Knows(DUAL_WIELD)
	local bySlot = {} -- slot -> { entries }, best first
	local twoHand
	local pending = 0
	for id, g in pairs(data()) do
		local dungeon = g[DUNGEON] and S.Dungeons and S.Dungeons.Get(g[DUNGEON])
		if mayUse(g, class, maxLevel) and (raids or not (dungeon and dungeon.raid)) then
			local src = sources(g, p)
			if #src > 0 then
				if not cached(id) then
					request(id)
					pending = pending + 1
				else
					local link = "item:" .. id
					local equipLoc, _, _, minLevel, quality, name = Client.Info(link)
					local usable, why = Gear.Usable(link)
					local slots = equipLoc and Gear.SLOTS[equipLoc]
					local score = slots and usable and (why == nil or (why == "level" and (minLevel or 0) <= maxLevel)) and Gear.Score(link)
					if score and score > 0 then
						local e = { id = id, link = link, name = name, quality = quality, score = score, minLevel = minLevel,
							source = src[1], sources = src, have = have(id), equipLoc = equipLoc }
						if equipLoc == "INVTYPE_2HWEAPON" then
							if not twoHand or score > twoHand.score then twoHand = e end
						else
							for _, slot in ipairs(slots) do
								if not (slot == 17 and equipLoc == "INVTYPE_WEAPON" and not dual) then
									local t = bySlot[slot] or {}
									bySlot[slot] = t
									t[#t + 1] = e
								end
							end
						end
					end
				end
			end
		end
	end
	for _, t in pairs(bySlot) do table.sort(t, function(a, b) return a.score > b.score end) end
	local out = {}
	local used = {}
	local function take(slot)
		for _, e in ipairs(bySlot[slot] or {}) do
			if not used[e.id] then used[e.id] = true return e end
		end
	end
	for _, slot in ipairs(ORDER) do
		local e
		if slot == 16 then
			local mh = take(16)
			local oh = (bySlot[17] or {})[1]
			-- A two-hander when it beats the best one-hander and off hand together.
			if twoHand and twoHand.score >= ((mh and mh.score or 0) + (oh and oh.score or 0)) then
				e = twoHand
				used.offhand = true
				if mh then used[mh.id] = nil end
			else
				e = mh
			end
		elseif slot == 17 then
			if not used.offhand then e = take(17) end
		else
			e = take(slot)
		end
		if e then
			local equipped = Client.Equipped(slot)
			local worn = equipped and Gear.Score(equipped) or 0
			if slot == 16 and e.equipLoc == "INVTYPE_2HWEAPON" then
				local off = Client.Equipped(17)
				worn = worn + (off and Gear.Score(off) or 0)
			end
			local wornId = equipped and tonumber(tostring(equipped):match("item:(%d+)"))
			out[#out + 1] = {
				slot = slot, slotName = (slot == 16 and e.equipLoc == "INVTYPE_2HWEAPON") and "Two-hand" or Gear.SLOT_NAMES[slot],
				id = e.id, link = e.link, name = e.name, quality = e.quality, score = e.score, minLevel = e.minLevel,
				source = e.source, sources = e.sources, wearing = wornId == e.id, have = e.have or wornId == e.id,
				pct = worn > 0 and ((e.score - worn) / worn * 100) or nil,
			}
		end
	end
	lists[k] = { out, pending }
	return out, pending
end

-- Is item `id` the best for its slot, at the player's level or at the level
-- it needs when that is higher ("for your level and up")?
-- -> level it is best for, slot name; or nil.
function Best.IsBest(id)
	local g = id and data()[id]
	if not g then return nil end
	local level = Client.Level()
	local at = math.max(level, g[REQ] or 0)
	if at > 60 then return nil end
	for _, e in ipairs((Best.ListFor(at))) do
		if e.id == id then return at, e.slotName end
	end
	return nil
end

---------------------------------------------------------------------------
-- Picking one up
---------------------------------------------------------------------------

S.Defaults("gear", { bisAlert = true })

local seen -- itemID -> count in the bags, from the last look; nil before the first

local function bagCounts()
	local out = {}
	local Cn = C_Container
	if not (Cn and Cn.GetContainerNumSlots and Cn.GetContainerItemInfo) then return out end
	for bag = 0, 4 do
		local ok, n = pcall(Cn.GetContainerNumSlots, bag)
		n = ok and readable(n) or 0
		for slot = 1, n do
			local ok2, info = pcall(Cn.GetContainerItemInfo, bag, slot)
			local id = ok2 and type(info) == "table" and readable(info.itemID)
			if id then out[id] = (out[id] or 0) + (readable(info.stackCount) or 1) end
		end
	end
	return out
end

-- Say it loudly: in the middle of the screen, with a sound, and in chat.
function Best.Announce(id, at, slotName)
	local _, _, _, _, _, name = Client.Info("item:" .. id)
	local I = C_Item
	local link = I and I.GetItemInfo and select(2, pcall(I.GetItemInfo, id))
	link = readable(link) or name or ("item " .. id)
	local level = Client.Level()
	local when = at > level and (" for level %d"):format(at) or " for your level"
	local text = ("Best in slot%s: %s (%s)"):format(when, tostring(name or link), tostring(slotName))
	local c = S.Theme.Color("gear")
	local r, g, b = c[1], c[2], c[3]
	local shown = false
	if RaidWarningUtil and RaidWarningUtil.AddMessage then
		shown = pcall(RaidWarningUtil.AddMessage, text, { r = r, g = g, b = b }, 5)
	end
	if not shown and UIErrorsFrame and UIErrorsFrame.AddMessage then
		pcall(UIErrorsFrame.AddMessage, UIErrorsFrame, text, r, g, b)
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then pcall(PlaySound, SOUNDKIT.RAID_WARNING) end
	S.Print(("Pathwise Gear: %s is your best in slot%s (%s)."):format(link, when, tostring(slotName)))
	S.Fire("GEAR_BEST_PICKED", id, at)
end

-- New items in the bags since the last look (the first look only counts).
function Best.CheckBags()
	local now = bagCounts()
	if seen and S.Get("gear.bisAlert") then
		for id, n in pairs(now) do
			if n > (seen[id] or 0) and data()[id] then
				local at, slotName = Best.IsBest(id)
				if at then Best.Announce(id, at, slotName) end
			end
		end
	end
	seen = now
end
S.On("READY", function() seen = nil Best.CheckBags() end)
S.RegisterEvent("BAG_UPDATE_DELAYED", function() Best.CheckBags() end)

-- Rebuild as items arrive from the server (at most twice a second).
local waiting = false
local function soon()
	if waiting then return end
	waiting = true
	local function run()
		waiting = false
		Best.Clear()
		S.Fire("GEAR_BEST_UPDATED")
	end
	if C_Timer and C_Timer.After then C_Timer.After(0.5, run) else run() end
end
S.RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, id) if id and requested[id] then soon() end end)
S.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, id) if id and requested[id] then soon() end end)
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "PLAYER_EQUIPMENT_CHANGED", "QUEST_TURNED_IN" }) do
	S.RegisterEvent(ev, function() Best.Clear() end)
end
-- Gear's own refresh (talents, items arriving): at most twice a second.
S.On("GEAR_UPDATED", function() soon() end)
S.On("SETTING_CHANGED", function(path) if type(path) == "string" and path:find("^gear%.") then Best.Clear() end end)
