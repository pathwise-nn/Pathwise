-- A stand-in for the WoW client, enough to load Pathwise and drive it from
-- tests: frames that remember what was set on them, a fake map and player,
-- events and time. Nothing here claims how the real client behaves beyond
-- what Pathwise calls.

local stub = { events = {}, frames = {}, printed = {}, now = 0 }
_G.stub = stub

local function noop() end

-- Widgets: any method call is accepted; a few remember state.
local Widget = {}
Widget.__index = function(self, k)
	local v = rawget(Widget, k)
	if v ~= nil then return v end
	return noop
end

local function new(kind, name, parent)
	local w = setmetatable({ kind = kind, name = name, parent = parent, shown = true, w = 0, h = 0, scripts = {}, points = {} }, Widget)
	stub.frames[#stub.frames + 1] = w
	if name then _G[name] = w end
	return w
end

function Widget:CreateTexture() return new("Texture", nil, self) end
function Widget:CreateFontString() local f = new("FontString", nil, self) f.text = "" return f end
function Widget:SetScript(k, fn) self.scripts[k] = fn end
function Widget:GetScript(k) return self.scripts[k] end
function Widget:Show() self.shown = true end
function Widget:Hide() self.shown = false end
function Widget:SetShown(on) self.shown = on and true or false end
function Widget:IsShown() return self.shown end
function Widget:SetWidth(w) self.w = w end
function Widget:SetHeight(h) self.h = h end
function Widget:SetSize(w, h) self.w, self.h = w, h end
function Widget:GetWidth() return self.w end
function Widget:GetHeight() return self.h end
function Widget:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Widget:ClearAllPoints() self.points = {} end
function Widget:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function Widget:SetText(t) self.text = t end
function Widget:GetText() return self.text end
function Widget:GetStringWidth() return #(self.text or "") * 6 end
function Widget:GetStringHeight() return (self.text and self.text ~= "") and 14 or 0 end
function Widget:SetFont() return true end
function Widget:SetTexture(t) self.texture = t end
function Widget:SetRotation(r) self.rotation = r end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Widget:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
-- Events: like the client, an event Forever does not have is an error
-- (tests/fixtures/forever-events.txt, from Blizzard's Forever API docs).
local knownEvents = {}
do
	local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "tests"
	local f = io.open(here .. "/fixtures/forever-events.txt", "r")
	if f then
		for line in f:lines() do if not line:match("^#") and line ~= "" then knownEvents[line] = true end end
		f:close()
	end
end
stub.knownEvents = knownEvents
function Widget:RegisterEvent(e)
	if next(knownEvents) and not knownEvents[e] then
		error(("Frame:RegisterEvent(): Attempt to register unknown event %q"):format(tostring(e)), 2)
	end
	stub.events[e] = stub.events[e] or {}
	table.insert(stub.events[e], self)
end
function Widget:SetScale(s) self.scale = s end
function Widget:SetShadowOffset(x, y) self.shadow = { x, y } end
-- Sliders: SetValue clamps and fires OnValueChanged, as the client does.
function Widget:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function Widget:SetValue(v)
	if self.min then v = math.max(self.min, math.min(self.max, v)) end
	self.value = v
	if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function Widget:GetValue() return self.value end

-- Typing into the number box beside setting `path`'s slider, then Enter.
function stub.type(path, text)
	for _, f in ipairs(stub.frames) do
		local list = rawget(f, "sliders")
		if list and list[path] and list[path].shown and f.shown then
			f.box:SetText(text)
			f.box.scripts.OnEnterPressed(f.box)
			return f.box
		end
	end
	error("no box for " .. path)
end

-- The slider in the settings panel for setting `path` (its row keeps them by path).
function stub.slider(path)
	for _, f in ipairs(stub.frames) do
		local list = rawget(f, "sliders")
		if list and list[path] and list[path].shown and f.shown then return list[path] end
	end
end

function Widget:SetParent(p) self.parent = p end
function Widget:GetParent() return self.parent end

function CreateFrame(kind, name, parent) return new(kind, name, parent) end
UIParent = new("Frame", "UIParent")

-- The world map: shown on stub.mapShown, a 1000 x 666 canvas at stub.mapScale.
stub.mapShown, stub.mapScale = nil, 1
WorldMapFrame = new("Frame", "WorldMapFrame")
local canvas = new("Frame", nil, WorldMapFrame)
canvas.w, canvas.h = 1000, 666
function WorldMapFrame:GetMapID() return stub.mapShown end
function WorldMapFrame:GetCanvas() return canvas end
function WorldMapFrame:GetCanvasScale() return stub.mapScale end
function WorldMapFrame:IsShown() return stub.mapShown ~= nil end
stub.canvas = canvas

-- The minimap: 140 px wide, zoom 0, outdoors, not rotating unless stub.cvars says.
Minimap = new("Frame", "Minimap")
Minimap.w, Minimap.h = 140, 140
function Minimap:GetZoom() return 0 end
function Minimap:GetCenter() return 1000, 600 end
function Minimap:GetEffectiveScale() return 1 end
stub.cursor = { 1000, 600 }
function GetCursorPosition() return stub.cursor[1], stub.cursor[2] end
function IsIndoors() return false end
stub.cvars = {}
function GetCVar(name) return stub.cvars[name] end
GameTooltip = new("GameTooltip", "GameTooltip")
function GameTooltip:GetItem() return "Item", stub.tooltipLink end
function GameTooltip:AddDoubleLine(l, r) stub.tooltipLines[#stub.tooltipLines + 1] = { l, r } end
function GameTooltip:IsForbidden() return false end

-- The combined backpack: item buttons for bag 0's slots.
ContainerFrameCombinedBags = new("Frame", "ContainerFrameCombinedBags")
stub.bagButtons = {}
function ContainerFrameCombinedBags:UpdateItems() end
function ContainerFrameCombinedBags:EnumerateValidItems()
	local i = 0
	return function()
		i = i + 1
		local b = stub.bagButtons[i]
		if b then return i, b end
	end
end
function stub.bagButton(slot)
	local b = new("Button", nil, ContainerFrameCombinedBags)
	b.GetBagID = function() return 0 end
	b.GetID = function() return slot end
	stub.bagButtons[#stub.bagButtons + 1] = b
	return b
end
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) stub.printed[#stub.printed + 1] = m end }
SlashCmdList = {}
C_AddOns = { GetAddOnMetadata = function(_, f) if f == "Version" then return "0.1.0-test" end end }
function IsShiftKeyDown() return false end
function CreateVector2D(x, y) return { x = x, y = y, GetXY = function(v) return v.x, v.y end } end

-- The fake world: one map 0-100 maps to world yards linearly.
-- map 1420: north = 2000 - y*20, west = 3000 - x*30 (yards), instance 0.
stub.player = { map = 1420, x = 50, y = 50, facing = 0, instance = false, taxi = false }
stub.maps = {
	[1420] = { inst = 0, name = "Tirisfal Glades", n0 = 2000, ny = -20, w0 = 3000, wx = -30 },
	[1411] = { inst = 1, name = "Durotar", n0 = 0, ny = -20, w0 = 0, wx = -30 },
}
C_Map = {
	GetBestMapForUnit = function() return stub.player.map end,
	GetPlayerMapPosition = function() return CreateVector2D(stub.player.x / 100, stub.player.y / 100) end,
	GetWorldPosFromMapPos = function(map, v)
		local m = stub.maps[map]
		if not m then return nil end
		return m.inst, CreateVector2D(m.n0 + m.ny * v.y * 100, m.w0 + m.wx * v.x * 100)
	end,
	GetMapInfo = function(map) local m = stub.maps[map] return m and { name = m.name } end,
}
-- The character: an Undead Mage by default (the reference character).
stub.player.level, stub.player.race, stub.player.raceID, stub.player.class, stub.player.faction = 1, "Scourge", 5, "MAGE", "Horde"
function UnitLevel() return stub.player.level end
function UnitRace() return "Undead", stub.player.race, stub.player.raceID end
function UnitClass() return "Mage", stub.player.class, 8 end
function UnitFactionGroup() return stub.player.faction end

-- Bags, hearthstone and professions.
stub.items, stub.bind, stub.skills, stub.spells = {}, "Deathknell", {}, {}
-- Item facts: stub.itemInfo[id] = { name, quality, ilvl, sell, classID, subclassID, equipLoc, minLevel }.
-- Item stats: stub.itemStats[id] = { ITEM_MOD_INTELLECT_SHORT = 5, ... }.
-- Bags: stub.bags[bag][slot] = { itemID, quality }. Equipped: stub.equipped[slot] = id.
-- Links are "item:<id>" (any string holding item:<id> works).
stub.itemInfo, stub.bags, stub.itemStats, stub.equipped = {}, {}, {}, {}
local function idOf(x) return type(x) == "number" and x or tonumber(tostring(x):match("item:(%d+)")) end
C_Item = {
	GetItemCount = function(id) return stub.items[id] or 0 end,
	GetItemInfo = function(x)
		local id = idOf(x)
		local i = id and stub.itemInfo[id]
		if not i then return nil end
		return i[1], "item:" .. id, i[2], i[3], i[8] or 1, "", "", 1, i[7] or "", 0, i[4], i[5], i[6]
	end,
	GetItemNameByID = function(id) local i = stub.itemInfo[id] return i and i[1] end,
	GetItemStats = function(x) local id = idOf(x) return id and stub.itemStats[id] end,
	-- Loading: an item is cached when stub.itemInfo has it and stub.uncached does not.
	IsItemDataCachedByID = function(id) return stub.itemInfo[id] ~= nil and not stub.uncached[id] end,
	RequestLoadItemDataByID = function(id) stub.requested[id] = true end,
}
stub.uncached, stub.requested = {}, {}
-- Alerts and sounds: what was shown in the middle of the screen, and played.
stub.notices, stub.sounds = {}, {}
RaidWarningUtil = { AddMessage = function(text) stub.notices[#stub.notices + 1] = text end }
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound(id) stub.sounds[#stub.sounds + 1] = id end
function GetInventoryItemLink(_, slot) local id = stub.equipped[slot] return id and ("item:" .. id) or nil end
C_Container = {
	GetContainerNumSlots = function(bag) return stub.bags[bag] and 16 or 0 end,
	GetContainerItemInfo = function(bag, slot) return stub.bags[bag] and stub.bags[bag][slot] end,
	GetContainerItemLink = function(bag, slot)
		local i = stub.bags[bag] and stub.bags[bag][slot]
		return i and ("item:" .. i.itemID) or nil
	end,
	-- Free slots of a general bag (family 0).
	GetContainerNumFreeSlots = function(bag)
		if not stub.bags[bag] then return 0, 0 end
		local n = 0
		for slot = 1, 16 do if not stub.bags[bag][slot] then n = n + 1 end end
		return n, 0
	end,
	-- With a vendor open (stub.merchant), using an item sells it: the slot
	-- empties and its price (itemInfo's sell) goes to stub.money.
	UseContainerItem = function(bag, slot)
		local i = stub.bags[bag] and stub.bags[bag][slot]
		if not i then return end
		stub.used[#stub.used + 1] = { bag, slot, i.itemID }
		if stub.merchant then
			local info = stub.itemInfo[i.itemID]
			stub.money = stub.money + (info and info[4] or 0) * (i.stackCount or 1)
			stub.bags[bag][slot] = nil
		end
	end,
	SortBags = function() stub.sorted = (stub.sorted or 0) + 1 end,
}
stub.used, stub.money, stub.merchant, stub.combat = {}, 0, false, false
function GetMoney() return stub.money end
function InCombatLockdown() return stub.combat end
MerchantFrame = new("Frame", "MerchantFrame")
UISpecialFrames = {}
-- The game's bag functions, for hooksecurefunc to follow.
stub.bagsOpened = 0
-- Like Forever's ContainerFrame.lua: the bag key's toggle opens the bags
-- through OpenAllBags when none of the game's own bags is open (and they
-- never are while Pathwise Bags shows its window).
function OpenAllBags() stub.bagsOpened = stub.bagsOpened + 1 end
function ToggleAllBags() OpenAllBags() end
function CloseAllBags() end
function OpenBackpack() end
function CloseBackpack() end
function ToggleBackpack() OpenBackpack() end

-- Tooltips: TooltipDataProcessor keeps the post-calls; GameTooltip shows stub.tooltipLink.
stub.postCalls, stub.tooltipLines = {}, {}
Enum = { TooltipDataType = { Item = 0 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) stub.postCalls[#stub.postCalls + 1] = fn end }
function stub.showTooltip(link)
	stub.tooltipLink, stub.tooltipLines = link, {}
	for _, fn in ipairs(stub.postCalls) do fn(GameTooltip) end
	return stub.tooltipLines
end
function hooksecurefunc(t, name, fn)
	if type(t) == "string" then t, name, fn = _G, t, name end
	local orig = t[name]
	t[name] = function(...) local r = orig(...) fn(...) return r end
end

-- Quest rewards: stub.choices = { ids }.
stub.choices = {}
function GetNumQuestChoices() return #stub.choices end
function GetQuestItemLink(kind, i) return kind == "choice" and stub.choices[i] and ("item:" .. stub.choices[i]) or nil end
-- The profession window: stub.tradeSkill = { professionID, recipes = { [id] = { name, learned, relativeDifficulty } } }
C_TradeSkillUI = {
	GetBaseProfessionInfo = function() return stub.tradeSkill and { professionID = stub.tradeSkill.professionID } end,
	GetAllRecipeIDs = function()
		local ids = {}
		for id in pairs(stub.tradeSkill and stub.tradeSkill.recipes or {}) do ids[#ids + 1] = id end
		return ids
	end,
	GetRecipeInfo = function(id) return stub.tradeSkill and stub.tradeSkill.recipes[id] end,
}
function GetBindLocation() return stub.bind end
C_SkillInfo = { GetSkillLineInfoByID = function(line)
	local s = stub.skills[line]
	if not s then return { rank = 0, maxRank = 0 } end
	return { rank = s[1], maxRank = s[2] }
end }
C_SpellBook = { IsSpellKnown = function(id) return stub.spells[id] == true end }

-- The quest log: log[id] ={ objectives = { {text, numFulfilled, numRequired, finished}, ... }, ready }
stub.log, stub.done = {}, {}
C_QuestLog = {
	IsOnQuest = function(id) return stub.log[id] ~= nil end,
	IsQuestFlaggedCompleted = function(id) return stub.done[id] == true end,
	ReadyForTurnIn = function(id) return stub.log[id] ~= nil and stub.log[id].ready == true end,
	IsComplete = function(id) return stub.log[id] ~= nil and stub.log[id].ready == true end,
	GetQuestObjectives = function(id) return stub.log[id] and stub.log[id].objectives or {} end,
	GetTitleForQuestID = function() return nil end,
}
function stub.accept(id, objectives)
	stub.log[id] = { objectives = objectives or {}, ready = objectives == nil }
	stub.fire("QUEST_ACCEPTED", id)
	stub.fire("QUEST_LOG_UPDATE")
end
function stub.progress(id, i, have)
	local o = stub.log[id].objectives[i]
	o.numFulfilled = have
	o.finished = have >= o.numRequired
	local all = true
	for _, x in ipairs(stub.log[id].objectives) do if not x.finished then all = false end end
	stub.log[id].ready = all
	stub.fire("QUEST_LOG_UPDATE")
end
function stub.turnin(id)
	stub.log[id] = nil
	stub.done[id] = true
	stub.fire("QUEST_TURNED_IN", id)
	stub.fire("QUEST_LOG_UPDATE")
end
function stub.moveTo(map, x, y) stub.player.map, stub.player.x, stub.player.y = map, x, y end

-- Clicks the shown button whose label is `label` (T.Button) or whose tooltip
-- name is `label` (T.IconButton has none: use stub.click(frame)).
function stub.clickLabel(label)
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "pwText")
		if t and t.text == label and f.shown and (not f.parent or f.parent.shown ~= false) then
			f.scripts.OnClick(f)
			return true
		end
	end
	return false
end

-- Clicks the shown panel row (a "choice") whose text starts with `text`.
function stub.clickLabelText(text)
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "text")
		if f.kind == "Button" and type(t) == "table" and f.shown and t.text and t.text:sub(1, #text) == text then
			f.scripts.OnClick(f)
			return true
		end
	end
	return false
end

-- The texts of every shown font string whose parent is shown, in creation order.
function stub.texts()
	local out = {}
	for _, f in ipairs(stub.frames) do
		if f.kind == "FontString" and f.shown and rawget(f, "text") and f.text ~= "" and (not f.parent or f.parent.shown) then
			out[#out + 1] = f.text
		end
	end
	return out
end

function GetBuildInfo() return "1.60.1", "70532", "Oct 2026", 16001 end
function GetPlayerFacing() return stub.player.facing end
function IsInInstance() return stub.player.instance end
function UnitOnTaxi() return stub.player.taxi end

function stub.fire(event, ...)
	for _, f in ipairs(stub.events[event] or {}) do
		local fn = f.scripts.OnEvent
		if fn then fn(f, event, ...) end
	end
end

-- Runs every shown frame's OnUpdate for `seconds`, in 1/60 s ticks.
function stub.advance(seconds)
	local dt = 1 / 60
	for _ = 1, math.floor(seconds / dt + 0.5) do
		for _, f in ipairs(stub.frames) do
			local fn = f.scripts.OnUpdate
			if fn and f.shown then fn(f, dt) end
		end
	end
end

-- Loads the addon's files in TOC order into a fresh namespace.
function stub.load(root)
	local ns = {}
	local toc = assert(io.open(root .. "/Pathwise/Pathwise.toc")):read("*a")
	local files = {}
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%.lua$") then files[#files + 1] = line:gsub("\\", "/") end
	end
	for _, f in ipairs(files) do
		local chunk = assert(loadfile(root .. "/Pathwise/" .. f))
		chunk("Pathwise", ns)
	end
	stub.ns, stub.files = ns, files
	return ns
end

-- Loads another Pathwise addon (Pathwise_Gear, ...) from its own TOC, after Pathwise.
function stub.loadAddon(root, name)
	local ns = {}
	local toc = assert(io.open(root .. "/" .. name .. "/" .. name .. ".toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line:match("%.lua$") then
			assert(loadfile(root .. "/" .. name .. "/" .. line:gsub("\\", "/")))(name, ns)
		end
	end
	return ns
end

-- The texture whose file path matches `pattern`.
function stub.find(pattern)
	for _, f in ipairs(stub.frames) do
		local t = rawget(f, "texture")
		if type(t) == "string" and t:match(pattern) then return f end
	end
end

function stub.login()
	stub.fire("ADDON_LOADED", "Pathwise")
	stub.fire("PLAYER_LOGIN")
end

return stub
