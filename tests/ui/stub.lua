-- A stand-in for the WoW client (shared with Pathwise's tests), enough to
-- load Pathwise UI and drive it from
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
	-- Methods (Capitalised) are accepted and do nothing; a missing data
	-- field (lowercase) is nil, as on a real frame.
	if type(k) == "string" and k:match("^%l") then return nil end
	return noop
end

local function new(kind, name, parent)
	local w = setmetatable({ kind = kind, name = name, parent = parent, shown = true, w = 0, h = 0, scripts = {}, points = {} }, Widget)
	stub.frames[#stub.frames + 1] = w
	if name then _G[name] = w end
	return w
end

function Widget:CreateTexture() return new("Texture", nil, self) end
-- Like the client, a font string made without a template has no font, and
-- writing text to it before SetFont or SetFontObject is an error.
function Widget:CreateFontString(name, layer, template)
	local f = new("FontString", nil, self)
	f.text = ""
	rawset(f, "hasFont", template ~= nil)
	return f
end
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
function Widget:SetText(t)
	if self.kind == "FontString" and rawget(self, "hasFont") == false then error("FontString:SetText(): Font not set", 2) end
	self.text = t
end
function Widget:SetFontObject(o) rawset(self, "hasFont", true) self.fontObject = o end
function Widget:GetText() return self.text end
function Widget:GetStringWidth() return #(self.text or "") * 6 end
function Widget:GetStringHeight() return (self.text and self.text ~= "") and 14 or 0 end
function Widget:SetFont() rawset(self, "hasFont", true) return true end
function Widget:SetTexture(t) self.texture = t end
function Widget:SetRotation(r) self.rotation = r end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function Widget:SetTextColor(r, g, b, a) self.textColor = { r, g, b, a } end
-- Events: like the client, an event Forever does not have is an error
-- (tests/fixtures/forever-events.txt, shared with Pathwise's tests; from
-- Blizzard's Forever API docs).
local knownEvents = {}
do
	local here = debug.getinfo(1, "S").source:match("^@(.*)[/\\]") or "tests"
	local f = io.open(here .. "/../fixtures/forever-events.txt", "r")
	assert(f, "tests/fixtures/forever-events.txt not found")
	if f then
		for line in f:lines() do if not line:match("^#") and line ~= "" then knownEvents[line] = true end end
		f:close()
	end
end
stub.knownEvents = knownEvents
-- Events Forever keeps from addons (tests/fixtures/forever-restricted-events.txt):
-- the client blocks the call and blames the addon, so the runners fail the test
-- (BLOCKED_EVENTS), even when the addon wraps the call in pcall.
local restrictedEvents = {}
do
	local here = debug.getinfo(1, "S").source:match("^@(.*)[/\]") or "tests"
	local f = io.open(here .. "/../fixtures/forever-restricted-events.txt", "r")
	if f then
		for line in f:lines() do if not line:match("^#") and line ~= "" then restrictedEvents[line] = true end end
		f:close()
	end
end
stub.restrictedEvents = restrictedEvents
function Widget:RegisterEvent(e)
	if restrictedEvents[e] then
		BLOCKED_EVENTS = BLOCKED_EVENTS or {}
		table.insert(BLOCKED_EVENTS, e)
		error(("Frame:RegisterEvent(): %q is blocked for addons"):format(e), 2)
	end
	if next(knownEvents) and not knownEvents[e] then
		error(("Frame:RegisterEvent(): Attempt to register unknown event %q"):format(tostring(e)), 2)
	end
	stub.events[e] = stub.events[e] or {}
	table.insert(stub.events[e], self)
end
function Widget:SetScale(s) self.scale = s end
function Widget:SetAlpha(a) self.alpha = a end
function Widget:GetAlpha() return rawget(self, "alpha") or 1 end
function Widget:IsMouseOver() return rawget(self, "mouseOver") or false end
function Widget:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
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
-- Spells by name: stub.spellNames = { ["Flash Heal"] = true, ... } is your
-- spellbook; left nil, every name resolves (as before, for older tests).
stub.spellNames = nil
C_Spell = { GetSpellInfo = function(name)
	if stub.spellNames == nil or stub.spellNames[name] then return { name = name } end
	return nil
end }
-- Talent points per tree: stub.talents = { 0, 21, 0 }.
stub.talents = nil
C_SpecializationInfo = { GetSpecializationInfo = function(i)
	local p = stub.talents and stub.talents[i] or 0
	return i, "Tree " .. i, "", 0, "", false, p
end }

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

function stub.login(addon)
	stub.fire("ADDON_LOADED", addon or "Pathwise")
	stub.fire("PLAYER_LOGIN")
end

-- Pathwise UI's bits of the client: font objects, the tooltip style function,
-- class colors, reload.
stub.reloaded = 0
function ReloadUI() stub.reloaded = stub.reloaded + 1 end
RAID_CLASS_COLORS = {
	MAGE = { r = 0.25, g = 0.78, b = 0.92 }, ROGUE = { r = 1, g = 0.96, b = 0.41 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
local function fontObject(file, size, flags)
	local f = { file = file, size = size, flags = flags }
	function f:GetFont() return self.file, self.size, self.flags end
	function f:SetFont(a, b, c) self.file, self.size, self.flags = a, b, c return true end
	return f
end
GameFontNormal = fontObject("Fonts\FRIZQT__.TTF", 12, "")
GameTooltipText = fontObject("Fonts\FRIZQT__.TTF", 12, "")
GameTooltipHeaderText = fontObject("Fonts\FRIZQT__.TTF", 14, "")
NumberFontNormal = fontObject("Fonts\ARIALN.TTF", 14, "OUTLINE")
function SharedTooltip_SetBackdropStyle(tt) end
function GameTooltip_SetDefaultAnchor(tt, parent) end
ItemRefTooltip = new("GameTooltip", "ItemRefTooltip")


---------------------------------------------------------------------------
-- Units, for Pathwise UI's unit frames
---------------------------------------------------------------------------
-- stub.units[token] = { name, level, class, player, reaction, health, max, power, pmax, ptype, dead, offline, leader }
-- A value made by stub.Secret(v) acts as Forever's secret values: addon code
-- may pass it on (bars and text take it) but math or ordering on it is an error.
local secretMeta = {}
local function refuse() error("attempt to use a secret value", 2) end
secretMeta.__add, secretMeta.__sub, secretMeta.__mul, secretMeta.__div = refuse, refuse, refuse, refuse
secretMeta.__lt, secretMeta.__le, secretMeta.__unm, secretMeta.__concat = refuse, refuse, refuse, refuse
-- Two secrets compared (Lua 5.1 asks __eq only when both sides are secrets).
secretMeta.__eq = refuse
secretMeta.__tostring = function() return "<secret>" end
function stub.Secret(v) return setmetatable({ value = v }, secretMeta) end
function issecretvalue(v) return getmetatable(v) == secretMeta end
local function plain(v) if issecretvalue(v) then return v.value end return v end

stub.units = {
	player = { name = "Frozen", level = 21, class = "MAGE", player = true, reaction = 5, health = 820, max = 1000, power = 600, pmax = 900, ptype = "MANA" },
}
stub.now = stub.now or 0
local function U(u) return stub.units[u] end
function UnitExists(u) return U(u) ~= nil end
function UnitName(u) local x = U(u) return x and x.name end
function UnitLevel(u) local x = U(u or "player") return x and x.level or stub.player.level end
function UnitClass(u)
	local x = U(u or "player")
	if u == nil or u == "player" then return "Mage", stub.player.class, 8 end
	return x and x.class, x and x.class
end
function UnitIsPlayer(u) local x = U(u) return x and x.player or false end
function UnitReaction(u) local x = U(u) return x and x.reaction end
function UnitHealth(u) local x = U(u) return x and x.health or 0 end
function UnitHealthMax(u) local x = U(u) return x and x.max or 0 end
function UnitPower(u) local x = U(u) return x and x.power or 0 end
function UnitPowerMax(u) local x = U(u) return x and x.pmax or 0 end
function UnitPowerType(u) local x = U(u) return 0, x and x.ptype or "MANA" end
-- Combo points (on your target, as on Forever): stub.combo, stub.comboMax.
function GetComboPoints(u, t) if u == "player" and t == "target" and U(t) then return stub.combo or 0 end return 0 end
local unitPowerMax = UnitPowerMax
function UnitPowerMax(u, kind) if kind == 4 then return stub.comboMax or 5 end return unitPowerMax(u) end
function UnitIsDead(u) local x = U(u) return x and x.dead or false end
function UnitIsConnected(u) local x = U(u) return not (x and x.offline) end
function UnitIsGroupLeader(u) local x = U(u) return x and x.leader or false end
function IsResting() return stub.resting or false end
function GetTime() return stub.now end
function AbbreviateNumbers(n)
	if issecretvalue(n) then return stub.Secret(AbbreviateNumbers(n.value)) end
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(n)
end
stub.watched = {}
function RegisterUnitWatch(f) stub.watched[f] = true end
function UnregisterUnitWatch(f) stub.watched[f] = nil end
-- Auras: stub.auras[unit][filter] = { aura data, ... }; casts: stub.casts[unit] = { name, texture, start, finish }
stub.auras, stub.casts = {}, {}
-- An aura with nameplateOnly (as bleeds and taunts can be on Forever) comes
-- back only when the filter has INCLUDE_NAME_PLATE_ONLY, as the client does.
-- stub.auraFilters lists every filter asked for.
stub.auraFilters = {}
C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
	stub.auraFilters[#stub.auraFilters + 1] = filter
	local list = stub.auras[u] and (stub.auras[u][filter] or stub.auras[u][(filter or ""):match("^(%u+)")])
	if not list then return nil end
	local plates = (filter or ""):find("INCLUDE_NAME_PLATE_ONLY", 1, true)
	local n = 0
	for _, a in ipairs(list) do
		if plates or not a.nameplateOnly then
			n = n + 1
			if n == i then return a end
		end
	end
end }
function UnitCastingInfo(u)
	local c = stub.casts[u]
	if c then return c.name, c.name, c.texture, c.start, c.finish, false, 1, c.locked end
end
function UnitChannelInfo() return nil end
-- Cast duration objects (Forever's LuaDurationObject), for a unit whose
-- stub.durations[unit] = { start = seconds, total = seconds, secret = bool,
-- channel = bool }: its seconds gone, left and in all, secret when asked.
stub.durations = {}
local function durationOf(u, channel)
	local d = stub.durations[u]
	if not d or (d.channel or false) ~= channel then return nil end
	local function wrap(v) return d.secret and stub.Secret(v) or v end
	return {
		GetTotalDuration = function() return wrap(d.total) end,
		GetElapsedDuration = function() return wrap(math.max(0, stub.now - d.start)) end,
		GetRemainingDuration = function() return wrap(math.max(0, d.start + d.total - stub.now)) end,
	}
end
function UnitCastingDuration(u) return durationOf(u, false) end
function UnitChannelDuration(u) return durationOf(u, true) end
-- Frames: attributes, per-unit events (checked against Forever's list),
-- formatted text, bars that take secret values as the client's do.
function Widget:SetAttribute(k, v)
	local a = rawget(self, "attrs") or {}
	rawset(self, "attrs", a)
	a[k] = v
end
function Widget:GetAttribute(k) local a = rawget(self, "attrs") return a and a[k] end
function Widget:RegisterUnitEvent(e, unit)
	Widget.RegisterEvent(self, e)
	local u = rawget(self, "unitEvents") or {}
	rawset(self, "unitEvents", u)
	u[e] = unit
end
function Widget:SetFormattedText(fmt, ...)
	local args = { ... }
	for i = 1, select("#", ...) do args[i] = plain(args[i]) end
	self.text = fmt:format(unpack(args, 1, select("#", ...)))
end
local setValue = Widget.SetValue
function Widget:SetValue(v)
	if issecretvalue(v) then self.value = v return end
	return setValue(self, v)
end
function Widget:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
-- A bar takes a secret range from addon code (Forever's SetMinMaxValues):
-- kept as it came, and the value is no longer clamped by the addon side.
local setMinMax = Widget.SetMinMaxValues
function Widget:SetMinMaxValues(lo, hi)
	if issecretvalue(lo) or issecretvalue(hi) then
		self.min, self.max, self.secretRange = nil, nil, { lo, hi }
		return
	end
	self.secretRange = nil
	return setMinMax(self, lo, hi)
end
function Widget:SetFillStyle(style) self.fillStyle = style end
function Widget:SetID(id) rawset(self, "id", id) end
function Widget:GetName() return rawget(self, "name") end
function Widget:GetID() return rawget(self, "id") or 0 end
-- Key bindings: stub.bindings[action] = { keys }; override bindings: stub.overrides[key] = "Button:LeftButton".
stub.bindings, stub.overrides, stub.drivers = {}, {}, {}
function GetBindingKey(action) return unpack(stub.bindings[action] or {}) end
function SetOverrideBindingClick(owner, _, key, button, mouse) stub.overrides[key] = button .. ":" .. (mouse or "LeftButton") end
function ClearOverrideBindings() stub.overrides = {} end
function RegisterStateDriver(frame, state, rule)
	stub.drivers[frame] = stub.drivers[frame] or {}
	stub.drivers[frame][state] = rule
end
-- Experience and reputation: stub.xp = { cur, max, rested, disabled }, stub.watched = faction data.
stub.xp = { cur = 4512, max = 9800, rested = 2100 }
function UnitXP() return stub.xp.cur end
function UnitXPMax() return stub.xp.max end
function GetXPExhaustion() return stub.xp.rested end
function IsXPUserDisabled() return stub.xp.disabled or false end
function GetMaxPlayerLevel() return 60 end
C_Reputation = { GetWatchedFactionData = function() return stub.watchedFaction end }
-- The game's tray (micro) and bag buttons, made on demand by tests: stub.makeTray().
function stub.makeTray()
	for _, n in ipairs({ "CharacterMicroButton", "SpellbookMicroButton", "TalentMicroButton", "QuestLogMicroButton",
		"GuildMicroButton", "LFDMicroButton", "HelpMicroButton", "MainMenuMicroButton" }) do
		local b = CreateFrame("Button", n)
		function b:IsEnabled() return true end
	end
	MicroMenuContainer = CreateFrame("Frame", "MicroMenuContainer")
	MicroMenu = CreateFrame("Frame", "MicroMenu", MicroMenuContainer)
	BagsBar = CreateFrame("Frame", "BagsBar")
	local bagButtons = {}
	for i, n in ipairs({ "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }) do
		bagButtons[i] = CreateFrame("ItemButton", n, BagsBar)
	end
	MainMenuBarBagManager = { EnumerateBagButtons = function() return ipairs(bagButtons) end }
end
-- The game's color wheel: stub.pick(r, g, b) is you moving it, stub.cancelPick() Cancel.
ColorPickerFrame = new("Frame", "ColorPickerFrame")
ColorPickerFrame.shown = false
function ColorPickerFrame:SetupColorPickerAndShow(info) self.info = info self.rgb = { info.r, info.g, info.b } self.shown = true end
function ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end
function stub.pick(r, g, b) ColorPickerFrame.rgb = { r, g, b } ColorPickerFrame.info.swatchFunc() end
function stub.cancelPick() ColorPickerFrame.shown = false ColorPickerFrame.info.cancelFunc() end

-- Nameplates: stub.addPlate(unit, data, forbidden) makes the game's plate for a unit.
stub.namePlates = {}
function stub.addPlate(unit, data, forbidden)
	stub.units[unit] = data
	local plate = CreateFrame("Frame")
	plate.namePlateUnitToken = unit
	plate.UnitFrame = CreateFrame("Button", nil, plate)
	function plate:IsForbidden() return forbidden or false end
	stub.namePlates[unit] = plate
	return plate
end
C_NamePlate = {
	GetNamePlateForUnit = function(unit)
		if unit == "target" then return stub.namePlates[stub.targetPlate or ""] end
		return stub.namePlates[unit]
	end,
	GetNamePlates = function() local out = {} for _, p in pairs(stub.namePlates) do out[#out + 1] = p end return out end,
}
function UnitIsFriend(_, u) local x = stub.units[u] return x and x.friend or false end
function UnitIsTapDenied(u) local x = stub.units[u] return x and x.tapped or false end
function UnitThreatSituation(_, u) local x = stub.units[u] return x and x.threat end
-- The game's threat colours by status (0 none, 1 and 2 slipping, 3 yours).
function GetThreatStatusColor(s) local c = ({ [0] = { 0.69, 0.69, 0.69 }, { 1, 1, 0.47 }, { 1, 0.6, 0 }, { 1, 0, 0 } })[s] if c then return c[1], c[2], c[3] end end
-- What a font string shows, a secret one too (the test reads it as the player would).
function stub.shown(fs) return plain(fs.text) end

return stub
