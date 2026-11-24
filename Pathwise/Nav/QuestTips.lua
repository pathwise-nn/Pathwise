-- Quest progress on tooltips: hover a monster you need, or an item a quest
-- asks for, and the tooltip names the quest and how far along you are:
--   The Mindless Ones
--     Mindless Zombie: 5/8
--
-- Which, from the quest data (Data/Data.lua, QuestieDB's Forever data) for
-- every quest in your log that isn't ready to hand in:
--   a monster: kill objectives for it (or that it gives credit for), and item
--     objectives it drops (not world drops: an item more than MAX_DROPS
--     monsters drop would be on every tooltip);
--   an item: the item objectives that ask for it.
-- The count is the quest log's own (C_QuestLog.GetQuestObjectives), matched to
-- the data's objectives by position, as the guide does (docs/DATA.md).
--
-- Hooked through TooltipDataProcessor's post-calls (Unit and Item); the
-- monster's id comes from its GUID, the item's from the tooltip data or link.
-- Secret values are left alone.

local ADDON, ns = ...
local QT = {}
ns.QuestTips = QT

ns.Defaults("questtips", {
	enabled = true,
})

local OBJECTIVES = 12
local MAX_DROPS = 30
local GOLD = { 1, 0.82, 0 } -- the game's quest-title yellow
local readable = function(v) return ns.Compat.Readable(v) end

local function dropsOf(item)
	local it = ns.Data and ns.Data.items and ns.Data.items[item]
	local list = it and it[2]
	if type(list) ~= "table" or #list > MAX_DROPS then return nil end
	return list
end

local function has(list, id)
	for _, v in ipairs(list or {}) do if v == id then return true end end
	return false
end

-- Does data objective `o` want monster `npc` (kind "npc") or item `item` (kind "item")?
local function matches(o, kind, id)
	local k, oid = o[1], o[2]
	if kind == "item" then return k == "i" and oid == id end
	if k == "m" then return oid == id end
	if k == "k" then return has(o[4], id) end
	if k == "i" then return has(dropsOf(oid), id) end
	return false
end

-- { { quest = id, name = text, lines = { { text, have, need, done }, ... } }, ... }
-- for monster or item `id` (`kind`: "npc" | "item"), quests in log order.
function QT.For(kind, id)
	local out = {}
	local Q = ns.Quests
	if not (Q and ns.Data and type(id) == "number") then return out end
	for _, qid in ipairs(Q.LogQuests()) do
		local q = Q.Get(qid)
		if q and not Q.Ready(qid) then
			local log = Q.Objectives(qid) or {}
			local lines
			for i, o in ipairs(q[OBJECTIVES] or {}) do
				if matches(o, kind, id) then
					local l = log[i] or {}
					lines = lines or {}
					lines[#lines + 1] = { text = l.text ~= "" and l.text or nil, have = l.have, need = l.need, done = l.done }
				end
			end
			if lines then out[#out + 1] = { quest = qid, name = Q.Name(qid), lines = lines } end
		end
	end
	return out
end

-- The npc id in a GUID ("Creature-0-...-<npc id>-<spawn>"), or nil.
function QT.NpcFromGuid(guid)
	guid = readable(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-[^-]*%-[^-]*%-[^-]*%-[^-]*%-(%d+)")
	if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
	return tonumber(id)
end

function QT.Add(tt, kind, id)
	if not (tt and tt.AddLine) or not ns.Get("questtips.enabled") then return end
	if tt.IsForbidden and tt:IsForbidden() then return end
	local found = QT.For(kind, id)
	if #found == 0 then return end
	for _, f in ipairs(found) do
		tt:AddLine(f.name or ("Quest " .. f.quest), GOLD[1], GOLD[2], GOLD[3])
		for _, l in ipairs(f.lines) do
			local count = (type(l.have) == "number" and type(l.need) == "number") and (l.have .. "/" .. l.need) or nil
			local text = "  " .. (l.text and count and (l.text .. ": " .. count) or l.text or count or "")
			if l.done then tt:AddLine(text, 0.5, 0.5, 0.5) else tt:AddLine(text, 1, 1, 1) end
		end
	end
	if tt.Show then tt:Show() end
end

local function itemId(tt, data)
	local id = data and readable(data.id)
	if type(id) == "number" then return id end
	if tt and tt.GetItem then
		local _, link = tt:GetItem()
		link = readable(link)
		return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
	end
end

local function unitNpc(tt, data)
	local id = QT.NpcFromGuid(data and data.guid)
	if id then return id end
	if tt and tt.GetUnit and UnitGUID then
		local _, unit = tt:GetUnit()
		unit = readable(unit)
		if type(unit) == "string" then return QT.NpcFromGuid(UnitGUID(unit)) end
	end
end

function QT.OnUnit(tt, data) local id = unitNpc(tt, data) if id then QT.Add(tt, "npc", id) end end
function QT.OnItem(tt, data) local id = itemId(tt, data) if id then QT.Add(tt, "item", id) end end

local installed = false
function QT.Install()
	if installed then return end
	installed = true
	local P, E = TooltipDataProcessor, Enum and Enum.TooltipDataType
	if P and P.AddTooltipPostCall and E then
		if E.Unit then P.AddTooltipPostCall(E.Unit, QT.OnUnit) end
		if E.Item then P.AddTooltipPostCall(E.Item, QT.OnItem) end
		return
	end
	if GameTooltip and GameTooltip.HookScript then
		GameTooltip:HookScript("OnTooltipSetUnit", function(tt) QT.OnUnit(tt) end)
		GameTooltip:HookScript("OnTooltipSetItem", function(tt) QT.OnItem(tt) end)
	end
end

ns.On("READY", QT.Install)
