-- Pathwise's XP bar: your experience, the rested part ahead of it, and the
-- experience waiting in quests ready to hand in, with how fast you level:
--   [purple XP | gold hand-ins | blue rested           ]  ticks every 5%
--   Level 23 · 54% · 7,420 / 13,700 XP · +2,350 in quests · Rested 4,600
--   To level 6,280 · After hand-ins 3,930 · 18.2k XP/h · Level in 21m · Kills to level ~48 · Quests ready 3
--
-- Off by default (Pathwise UI has its own plain bar); turned on in the
-- options, moved by dragging unless locked. Hidden at the level cap.
--
-- Where the numbers come from:
--   UnitXP, UnitXPMax, GetXPExhaustion: the game's.
--   Hand-ins: GetQuestLogRewardXP(quest id) for quests ready to turn in.
--     Forever's own UI calls it (QuestUtils) but it isn't in the API docs:
--     without it the gold part and "After hand-ins" are left out.
--   XP/h and time to level: Pathwise's leveling tracker (ns.Tracker).
--   Kills to level: the average of your last kills' XP, read from the
--     game's own "X dies, you gain N experience" line (its strings, so any
--     language), CHAT_MSG_COMBAT_XP_GAIN.

local ADDON, ns = ...
local T = ns.Theme
local B = {}
ns.XPTrack = B

ns.Defaults("xpbar", {
	enabled = false,
	locked = false,
	width = 520,
	height = 16,
	text = true, -- the numbers on the bar (else on hover only)
	stats = true, -- the line of stats under it
	point = nil,
})

local COLORS = {
	xp = { 0.64, 0.24, 0.93, 1 },
	quest = { 0.90, 0.71, 0.13, 0.75 },
	rested = { 0.18, 0.44, 0.84, 0.55 },
}
local KILLS_KEPT = 10

local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return ns.Compat.Readable(a), ns.Compat.Readable(b) end
end
local function num(v) return type(v) == "number" and v or nil end

---------------------------------------------------------------------------
-- The numbers
---------------------------------------------------------------------------

-- XP from quests ready to hand in -> total, count (total nil: the game won't say).
function B.QuestXP()
	local Q = ns.Quests
	if not Q then return nil, 0 end
	local total, count, known = 0, 0, type(GetQuestLogRewardXP) == "function"
	for _, id in ipairs(Q.LogQuests()) do
		if Q.Ready(id) then
			count = count + 1
			local xp = known and num((call(GetQuestLogRewardXP, id)))
			if xp and xp > 0 then total = total + xp end
		end
	end
	return known and total or nil, count
end

-- Kills: the game's kill lines -> the XP each gave.
local KILL_STRINGS = {
	"COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_FIRSTPERSON_GROUP", "COMBATLOG_XPGAIN_FIRSTPERSON_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION1", "COMBATLOG_XPGAIN_EXHAUSTION1_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION1_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION2", "COMBATLOG_XPGAIN_EXHAUSTION2_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION2_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION4", "COMBATLOG_XPGAIN_EXHAUSTION4_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION4_RAID",
	"COMBATLOG_XPGAIN_EXHAUSTION5", "COMBATLOG_XPGAIN_EXHAUSTION5_GROUP", "COMBATLOG_XPGAIN_EXHAUSTION5_RAID",
}
local heads
-- "%s dies, you gain %d experience." -> "^.+ dies, you gain " (the text before the number).
local function killHeads()
	if heads then return heads end
	heads = {}
	for _, key in ipairs(KILL_STRINGS) do
		local fmt = _G[key]
		local head = type(fmt) == "string" and fmt:match("^(.-)%%%d?%$?d")
		if head and head:find("%%%d?%$?s") then
			head = head:gsub("%%%d%$", "%%"):gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"):gsub("%%s", ".+")
			local p = "^" .. head
			local seen = false
			for _, q in ipairs(heads) do if q == p then seen = true end end
			if not seen then heads[#heads + 1] = p end
		end
	end
	if #heads == 0 then heads[1] = "^.+ dies, you gain " end
	return heads
end

-- The XP a kill line gave, or nil (not a kill, or a secret text).
function B.KillXP(text)
	if type(ns.Compat.Readable(text)) ~= "string" then return nil end
	for _, p in ipairs(killHeads()) do
		local _, e = text:find(p)
		if e then return tonumber(text:sub(e + 1):match("^(%d+)")) end
	end
	return nil
end

local kills = {}
function B.OnXPGain(text)
	local xp = B.KillXP(text)
	if not xp then return end
	kills[#kills + 1] = xp
	while #kills > KILLS_KEPT do table.remove(kills, 1) end
	B.Update()
end
function B.ResetKills() kills = {} end

-- Everything the bar shows, or nil at the level cap.
function B.Data()
	local level = num((call(UnitLevel, "player"))) or 1
	local maxLevel = num((call(GetMaxPlayerLevel))) or 60
	if level >= maxLevel then return nil end
	local cur, max = num((call(UnitXP, "player"))), num((call(UnitXPMax, "player")))
	if not (cur and max and max > 0) then return nil end
	local d = { level = level, cur = cur, max = max, rested = num((call(GetXPExhaustion))) or 0 }
	d.toLevel = max - cur
	d.questXP, d.ready = B.QuestXP()
	if d.questXP then d.afterQuests = math.max(0, d.toLevel - d.questXP) end
	local s = ns.Tracker and ns.Tracker.Stats() or {}
	d.xpPerHour, d.secondsToLevel = s.xpPerHour, s.secondsToLevel
	if #kills > 0 then
		local sum = 0
		for _, k in ipairs(kills) do sum = sum + k end
		local avg = sum / #kills
		if avg > 0 then d.killsToLevel = math.ceil(d.toLevel / avg) end
	end
	return d
end

local function grouped(n)
	local s = tostring(math.floor(n + 0.5))
	while true do
		local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = r
		if k == 0 then return s end
	end
end
local function short(n)
	if n >= 1000 then return ("%.1fk"):format(n / 1000) end
	return tostring(math.floor(n + 0.5))
end

-- "Level 23 · 54% · 7,420 / 13,700 XP · +2,350 in quests · Rested 4,600"
function B.Text(d)
	if not d then return "" end
	local parts = { (ns.L("Level %d")):format(d.level), ("%d%%"):format(math.floor(d.cur / d.max * 100)),
		("%s / %s XP"):format(grouped(d.cur), grouped(d.max)) }
	if d.questXP and d.questXP > 0 then parts[#parts + 1] = ("+%s in quests"):format(grouped(d.questXP)) end
	if d.rested > 0 then parts[#parts + 1] = ("Rested %s"):format(grouped(d.rested)) end
	return table.concat(parts, "  ·  ")
end

-- "To level 6,280 · After hand-ins 3,930 · 18.2k XP/h · Level in 21m · Kills to level ~48 · Quests ready 3"
function B.Stats(d)
	if not d then return "" end
	local parts = { ("To level %s"):format(grouped(d.toLevel)) }
	if d.afterQuests and d.questXP > 0 then parts[#parts + 1] = ("After hand-ins %s"):format(grouped(d.afterQuests)) end
	if d.xpPerHour then parts[#parts + 1] = short(d.xpPerHour) .. " XP/h" end
	if d.secondsToLevel and ns.Tracker then parts[#parts + 1] = "Level in " .. ns.Tracker.Duration(d.secondsToLevel) end
	if d.killsToLevel then parts[#parts + 1] = ("Kills to level ~%d"):format(d.killsToLevel) end
	if d.ready > 0 then parts[#parts + 1] = ("Quests ready %d"):format(d.ready) end
	return table.concat(parts, "  ·  ")
end

---------------------------------------------------------------------------
-- The bar
---------------------------------------------------------------------------

local frame

local function savePoint(f)
	local p, _, rel, x, y = f:GetPoint(1)
	if not (p and x and y) then return end
	ns.Set("xpbar.point", { p, math.floor(x + 0.5), math.floor(y + 0.5), rel ~= p and rel or nil })
end

local function bar(parent, color, level)
	local b = CreateFrame("StatusBar", nil, parent)
	b:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	b:SetStatusBarColor(color[1], color[2], color[3], color[4])
	b:SetPoint("TOPLEFT", 1, -1)
	b:SetPoint("BOTTOMRIGHT", -1, 1)
	b:SetFrameLevel((parent:GetFrameLevel() or 0) + level)
	return b
end

local function build()
	if frame then return frame end
	frame = CreateFrame("Frame", "PathwiseXPBar", UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	T.Panel(frame, "bg", "border", 3)
	frame.rested = bar(frame, COLORS.rested, 1)
	frame.quest = bar(frame, COLORS.quest, 2)
	frame.xp = bar(frame, COLORS.xp, 3)
	-- Ticks every 5%, over the bars.
	frame.over = CreateFrame("Frame", nil, frame)
	frame.over:SetAllPoints()
	frame.over:SetFrameLevel((frame:GetFrameLevel() or 0) + 4)
	frame.ticks = {}
	for i = 1, 19 do
		local t = frame.over:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(0, 0, 0, 0.45)
		t:SetWidth(1)
		frame.ticks[i] = t
	end
	frame.text = T.Text(frame.over, "small", "text", "OVERLAY")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	T.Shadow(frame.text)
	frame.stats = T.Text(frame, "small", "muted", "OVERLAY")
	frame.stats:SetPoint("TOP", frame, "BOTTOM", 0, -3)
	T.Shadow(frame.stats)
	frame:SetScript("OnDragStart", function(self) if T.Movable("xpbar.locked") then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePoint(self) end)
	frame:SetScript("OnEnter", function(self) self.hover = true B.Update() end)
	frame:SetScript("OnLeave", function(self) self.hover = false B.Update() end)
	return frame
end

function B.Layout()
	if not ns.Get("xpbar.enabled") then if frame then frame:Hide() end return end
	build()
	local w, h = ns.Get("xpbar.width") or 520, ns.Get("xpbar.height") or 16
	frame:SetSize(w, h)
	for i, t in ipairs(frame.ticks) do
		t:ClearAllPoints()
		t:SetPoint("TOP", frame, "TOPLEFT", w * i / 20, -1)
		t:SetPoint("BOTTOM", frame, "BOTTOMLEFT", w * i / 20, 1)
	end
	frame:ClearAllPoints()
	local p = ns.Get("xpbar.point")
	if type(p) == "table" then frame:SetPoint(p[1], UIParent, p[4] or p[1], p[2], p[3])
	else frame:SetPoint("TOP", UIParent, "TOP", 0, -24) end
	B.Update()
end

function B.Update()
	if not frame then return end
	local d = ns.Get("xpbar.enabled") and B.Data()
	if not d then frame:Hide() return end
	frame:Show()
	for _, b in ipairs({ frame.xp, frame.quest, frame.rested }) do b:SetMinMaxValues(0, d.max) end
	frame.xp:SetValue(d.cur)
	frame.quest:SetValue(math.min(d.max, d.cur + (d.questXP or 0)))
	frame.rested:SetValue(math.min(d.max, d.cur + d.rested))
	frame.text:SetText(B.Text(d))
	frame.text:SetShown(ns.Get("xpbar.text") or frame.hover or false)
	frame.stats:SetText(B.Stats(d))
	frame.stats:SetShown(ns.Get("xpbar.stats") or frame.hover or false)
end
function B.Frame() return frame end

ns.On("READY", B.Layout)
ns.On("TRACKER_UPDATED", function() B.Update() end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^xpbar%.") or path == "*") then B.Layout() end
end)
for _, ev in ipairs({ "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION", "PLAYER_UPDATE_RESTING", "QUEST_LOG_UPDATE" }) do
	ns.RegisterEvent(ev, function() B.Update() end)
end
ns.RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN", function(_, text) B.OnXPGain(text) end)
-- XP/h and time to level change with the clock too.
if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, function() B.Update() end) end
