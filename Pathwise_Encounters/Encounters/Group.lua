-- The group's timers and the range check.
--
--   /pwenc pull [seconds]   the game's own countdown for the group
--                           (C_PartyInfo.DoCountdown, which every client shows);
--                           alone, or when the game says no, a bar just for you.
--                           0 cancels.
--   /pwenc break [minutes]  a break bar, sent to the group as an addon message
--                           (Pathwise Encounters users see it). 0 cancels.
--   /pwenc range [yards]    who in the group is that close, while the game
--                           tells addons distances (not in a boss fight on
--                           Forever: it says so). Again to close.

local ADDON, ns = ...
local T = ns.Theme
local E = ns.Enc
local call, readable = E.call, ns.Readable
local G = {}
ns.EncGroup = G

G.PREFIX = "PathwiseEnc"
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"

local function now() return GetTime and GetTime() or 0 end
local function inGroup() return IsInGroup and readable(call(IsInGroup)) or false end
local function channel() return (IsInRaid and readable(call(IsInRaid))) and "RAID" or "PARTY" end

---------------------------------------------------------------------------
-- Pull
---------------------------------------------------------------------------

local function localPull(sec)
	E.AddTimer({ id = "pull", kind = "pull", label = "Pull", icon = QUESTION, ends = now() + sec, total = sec })
end

function G.Pull(sec)
	sec = tonumber(sec) or ns.Get("enc.pull") or 10
	sec = math.max(0, math.min(60, math.floor(sec)))
	local P = C_PartyInfo
	if sec == 0 then
		if inGroup() and P and P.DoCountdown then call(P.DoCountdown, 0) end
		E.RemoveTimer("pull")
		return "canceled"
	end
	if inGroup() and P and P.DoCountdown then
		local ok, res = pcall(P.DoCountdown, sec)
		if ok and readable(res) ~= false then return "group" end -- the bar comes with START_PLAYER_COUNTDOWN
		ns.Print("The game didn't start a group countdown (it may need the leader or an assistant); the bar is just for you.")
	end
	localPull(sec)
	return "local"
end

ns.RegisterEvent("START_PLAYER_COUNTDOWN", function(_, _, remaining, total)
	remaining, total = readable(remaining), readable(total)
	if type(remaining) ~= "number" then return end
	E.AddTimer({ id = "pull", kind = "pull", label = "Pull", icon = QUESTION, ends = now() + remaining,
		total = type(total) == "number" and total or remaining })
end)
ns.RegisterEvent("CANCEL_PLAYER_COUNTDOWN", function() E.RemoveTimer("pull") end)

---------------------------------------------------------------------------
-- Break
---------------------------------------------------------------------------

local function breakBar(sec)
	if sec <= 0 then E.RemoveTimer("break") return end
	E.AddTimer({ id = "break", kind = "break", label = "Break", icon = QUESTION, ends = now() + sec, total = sec })
end

function G.Break(minutes)
	minutes = tonumber(minutes) or ns.Get("enc.breakMinutes") or 5
	local sec = math.max(0, math.min(60, minutes)) * 60
	breakBar(sec)
	if inGroup() and C_ChatInfo and C_ChatInfo.SendAddonMessage then
		call(C_ChatInfo.SendAddonMessage, G.PREFIX, "BREAK:" .. math.floor(sec), channel())
	end
	return sec
end

ns.RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text)
	if readable(prefix) ~= G.PREFIX then return end
	text = readable(text)
	local sec = type(text) == "string" and tonumber(text:match("^BREAK:(%d+)$"))
	if sec then breakBar(math.min(sec, 3600)) end
end)
ns.On("LOADED", function()
	if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then call(C_ChatInfo.RegisterAddonMessagePrefix, G.PREFIX) end
end)

---------------------------------------------------------------------------
-- Range
---------------------------------------------------------------------------

local range, body, title, yards
local function units()
	local list = {}
	if IsInRaid and readable(call(IsInRaid)) then
		for i = 1, 40 do list[#list + 1] = "raid" .. i end
	else
		for i = 1, 4 do list[#list + 1] = "party" .. i end
	end
	return list
end

-- { near = { names }, count, members, unknown } for the group now.
function G.Measure(yd)
	local out = { near = {}, count = 0, members = 0, unknown = 0 }
	for _, u in ipairs(units()) do
		if readable(call(UnitExists, u)) and not readable(call(UnitIsUnit, u, "player")) then
			out.members = out.members + 1
			local d, checked = call(UnitDistanceSquared, u)
			d, checked = readable(d), readable(checked)
			if type(d) == "number" and checked then
				if d <= yd * yd then
					out.count = out.count + 1
					local name = readable(call(UnitName, u))
					if type(name) == "string" then out.near[#out.near + 1] = name end
				end
			else
				out.unknown = out.unknown + 1
			end
		end
	end
	return out
end

function G.RangeText(yd)
	local m = G.Measure(yd)
	if m.members == 0 then return "No one else in your group." end
	if m.unknown == m.members then return "The game isn't telling addons distances here (Forever hides them in a fight)." end
	local text = m.count == 0 and "No one is that close." or (m.count == 1 and "1 player" or (m.count .. " players")) .. " that close"
	if #m.near > 0 then
		table.sort(m.near)
		local shown = {}
		for i = 1, math.min(5, #m.near) do shown[i] = m.near[i] end
		text = text .. ": " .. table.concat(shown, ", ") .. (#m.near > 5 and ", ..." or "")
	end
	if m.unknown > 0 then text = text .. ("\n%d out of sight of the game's distance check."):format(m.unknown) end
	return text
end

local function buildRange()
	if range then return end
	range = CreateFrame("Frame", "PathwiseEncounters_Range", UIParent)
	range:SetSize(230, 70)
	range:SetPoint("CENTER", UIParent, "CENTER", 320, -80)
	range:SetFrameStrata("MEDIUM")
	T.Panel(range)
	title = T.Text(range, "title", "text")
	title:SetPoint("TOPLEFT", 10, -8)
	body = T.Text(range, "meta", "text2")
	body:SetPoint("TOPLEFT", 10, -30)
	body:SetPoint("RIGHT", range, "RIGHT", -10, 0)
	local since = 1
	range:SetScript("OnUpdate", function(_, dt)
		since = since + (dt or 0)
		if since < 0.5 then return end
		since = 0
		G.UpdateRange()
	end)
	range:Hide()
	G.rangeTitle, G.rangeBody = title, body
end
function G.UpdateRange()
	if not (range and range:IsShown()) then return end
	title:SetText(("Within %d yards"):format(yards))
	body:SetText(G.RangeText(yards))
end
function G.Range(yd)
	buildRange()
	yd = tonumber(yd)
	if range:IsShown() and not yd then range:Hide() return false end
	yards = math.max(2, math.min(100, yd or ns.Get("enc.range") or 10))
	range:Show()
	G.UpdateRange()
	return true
end
function G.RangeFrame() return range end

ns.Commands.pull = function(rest) G.Pull(rest ~= "" and rest or nil) end
ns.Commands["break"] = function(rest) G.Break(rest ~= "" and rest or nil) end
ns.Commands.range = function(rest) G.Range(rest ~= "" and rest or nil) end
