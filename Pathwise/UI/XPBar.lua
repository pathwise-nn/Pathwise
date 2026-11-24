-- Pathwise's XP bar: your experience, the rested part ahead of it, and the
-- experience waiting in quests ready to hand in, with how fast you level:
--   [Level 57 ........ 204931 / 311490 |gold|blue|     65.8% (70.6%)]
--          Completed Quests: 4.8% - Rested Experience: 6.4%
--   and on hover (or always, if set): XP to level, after hand-ins, XP/h,
--   time to level, kills to level, quests ready.
-- Bold, outlined text, to read over the world.
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
	height = 22,
	text = true, -- the numbers on the bar and the line under it (else on hover only)
	stats = false, -- the pace stats under that (else on hover only)
	point = nil,
})

local COLORS = {
	xp = { 0.66, 0.33, 0.95, 1 }, -- purple; a blue-to-purple sweep where the game can draw one
	xpFrom = { 0.36, 0.42, 0.96, 1 },
	quest = { 1.00, 0.65, 0.00, 1 }, -- orange
	rested = { 0.33, 0.65, 1.00, 1 }, -- light blue
}
local QUEST_HEX, RESTED_HEX = "ffa500", "55a6ff"
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

local function pct(n) return ("%.1f%%"):format(n) end

-- The bar's three texts: "Level 57", "204931 / 311490", "65.8% (70.6%)"
-- (the second percent: with the quests ready handed in).
function B.Text(d)
	if not d then return "", "", "" end
	local right = pct(d.cur / d.max * 100)
	if d.questXP and d.questXP > 0 then right = right .. (" (%s)"):format(pct(math.min(d.max, d.cur + d.questXP) / d.max * 100)) end
	return (ns.L("Level %d")):format(d.level), ("%d / %d"):format(d.cur, d.max), right
end

-- "Completed Quests: 4.8% - Rested Experience: 6.4%", the percents in the bar's colours.
function B.Summary(d)
	if not d then return "" end
	local parts = {}
	if d.questXP and d.questXP > 0 then
		parts[#parts + 1] = ("Completed Quests: |cff%s%s|r"):format(QUEST_HEX, pct(d.questXP / d.max * 100))
	end
	if d.rested > 0 then parts[#parts + 1] = ("Rested Experience: |cff%s%s|r"):format(RESTED_HEX, pct(d.rested / d.max * 100)) end
	return table.concat(parts, " - ")
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

-- Bold, outlined, shadowed: readable over any part of the world.
local function bold(parent, size, justify)
	local fs = ns.HookText(parent:CreateFontString(nil, "OVERLAY"))
	if not fs:SetFont(T.FONTS.semibold, size, "OUTLINE") then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE") end
	fs:SetTextColor(1, 1, 1, 1)
	if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) fs:SetShadowOffset(1, -1) end
	fs:SetJustifyH(justify or "CENTER")
	fs:SetWordWrap(false)
	return fs
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
	local tex = frame.xp.GetStatusBarTexture and frame.xp:GetStatusBarTexture()
	if tex and tex.SetGradient and CreateColor then
		local a, b = COLORS.xpFrom, COLORS.xp
		pcall(tex.SetGradient, tex, "HORIZONTAL", CreateColor(a[1], a[2], a[3], 1), CreateColor(b[1], b[2], b[3], 1))
	end
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
	frame.left = bold(frame.over, 13, "LEFT")
	frame.left:SetPoint("LEFT", frame, "LEFT", 8, 0)
	frame.text = bold(frame.over, 13, "CENTER")
	frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.right = bold(frame.over, 13, "RIGHT")
	frame.right:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
	frame.summary = bold(frame, 12, "CENTER")
	frame.summary:SetPoint("TOP", frame, "BOTTOM", 0, -4)
	frame.stats = bold(frame, 11, "CENTER")
	frame.stats:SetTextColor(0.85, 0.88, 0.92, 1)
	frame.stats:SetPoint("TOP", frame.summary, "BOTTOM", 0, -3)
	frame:SetScript("OnDragStart", function(self) if T.Movable("xpbar.locked") then self:StartMoving() end end)
	frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() savePoint(self) end)
	frame:SetScript("OnEnter", function(self) self.hover = true B.Update() end)
	frame:SetScript("OnLeave", function(self) self.hover = false B.Update() end)
	return frame
end

function B.Layout()
	if not ns.Get("xpbar.enabled") then if frame then frame:Hide() end return end
	build()
	local w, h = ns.Get("xpbar.width") or 520, ns.Get("xpbar.height") or 22
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
	local left, mid, right = B.Text(d)
	local on = ns.Get("xpbar.text") or frame.hover or false
	frame.left:SetText(left) frame.text:SetText(mid) frame.right:SetText(right)
	frame.summary:SetText(B.Summary(d))
	for _, fs in ipairs({ frame.left, frame.text, frame.right, frame.summary }) do fs:SetShown(on) end
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
