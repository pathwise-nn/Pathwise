-- The timer bars: a header (the boss, the fight's time, its phase) and one
-- bar per timer, soonest on top. Pathwise's own estimates in your accent,
-- the game's timeline in the warning color, pull and break in green.
-- A name the game keeps secret is handed straight to the font string;
-- nothing here compares or joins it.

local ADDON, ns = ...
local T = ns.Theme
local E = ns.Enc
local B = {}
ns.EncBars = B

local BAR = "Interface\\Buttons\\WHITE8X8"
local ROW, GAP, HEAD = 20, 3, 22
local COLOR = { boss = "accent", game = "warning", pull = "success", ["break"] = "success" }

local anchor, header, rows = nil, nil, {}
local unlocked, handle = false, nil

local function place()
	anchor:ClearAllPoints()
	local p = ns.Get("enc.point")
	if type(p) == "table" and p[1] then anchor:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else anchor:SetPoint("CENTER", UIParent, "CENTER", 320, 100) end
end

local function newRow(i)
	local r = CreateFrame("Frame", nil, anchor)
	r:SetHeight(ROW)
	r:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -(HEAD + (i - 1) * (ROW + GAP)))
	r:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -(HEAD + (i - 1) * (ROW + GAP)))
	T.Panel(r, "bg", "border", 0.85)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(ROW - 2, ROW - 2)
	r.icon:SetPoint("LEFT", r, "LEFT", 1, 0)
	r.bar = CreateFrame("StatusBar", nil, r)
	r.bar:SetStatusBarTexture(BAR)
	r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", ROW, -1)
	r.bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -1, 1)
	local over = CreateFrame("Frame", nil, r.bar)
	over:SetAllPoints()
	r.label = T.Text(over, "meta", "text")
	r.label:SetPoint("LEFT", r.bar, "LEFT", 5, 0)
	r.label:SetPoint("RIGHT", r.bar, "RIGHT", -44, 0)
	r.label:SetJustifyV("MIDDLE")
	T.BarText(r.label, "meta")
	r.about = T.Text(over, "small", "text2")
	r.about:SetPoint("RIGHT", r.bar, "RIGHT", -38, 0)
	r.time = T.Text(over, "meta", "text")
	r.time:SetPoint("RIGHT", r.bar, "RIGHT", -5, 0)
	r.time:SetJustifyH("RIGHT")
	T.BarText(r.time, "meta")
	rows[i] = r
	return r
end

local function build()
	if anchor then return end
	anchor = CreateFrame("Frame", "PathwiseEncounters_Bars", UIParent)
	anchor:SetFrameStrata("MEDIUM")
	anchor:SetSize(ns.Get("enc.width"), HEAD)
	place()
	header = T.Text(anchor, "window", "text")
	header:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 2, -HEAD + 4)
	B.header = header
	anchor:Hide()
end

-- What the header says: "Lucifron  1:23", the phase after it.
local function headerText(at)
	local f = E.Fight()
	if not f then return unlocked and "Boss timers" or "" end
	local text = f.name .. "   " .. E.Clock(at - f.start)
	local phase = E.PhaseName(f)
	if phase then text = text .. "   " .. phase end
	return text
end

function B.Refresh(at)
	build()
	at = at or (GetTime and GetTime() or 0)
	local list = E.Timers()
	local want = ns.Get("enc.bars") and (E.Fight() or #list > 0 or unlocked)
	if not want then anchor:Hide() return end
	anchor:SetWidth(ns.Get("enc.width"))
	header:SetText(headerText(at))
	local max = ns.Get("enc.maxBars") or 8
	local shown = 0
	for i = 1, max do
		local t = list[i]
		local r = rows[i]
		if t then
			r = r or newRow(i)
			shown = i
			local left = math.max(0, E.Remaining(t, at))
			r.bar:SetMinMaxValues(0, t.total)
			r.bar:SetValue(math.min(left, t.total))
			local c = T.Color(COLOR[t.kind] or "accent")
			r.bar:SetStatusBarColor(c[1], c[2], c[3])
			r.label:SetText(t.label) -- may be secret (the game's timeline): passed as it is
			r.icon:SetTexture(t.icon)
			r.about:SetText(t.approx and "about" or "")
			r.time:SetText(t.paused and "paused" or E.Clock(left))
			r.timer = t
			r:Show()
		elseif r then
			r.timer = nil
			r:Hide()
		end
	end
	for i = max + 1, #rows do rows[i].timer = nil rows[i]:Hide() end
	anchor:SetHeight(HEAD + shown * (ROW + GAP))
	anchor:Show()
end
function B.Anchor() build() return anchor end
function B.Rows() return rows end

ns.On("TICK", function(at) B.Refresh(at) end)
ns.On("TIMERS_CHANGED", function() B.Refresh() end)
ns.On("FIGHT_STARTED", function() B.Refresh() end)
ns.On("FIGHT_ENDED", function() B.Refresh() end)
ns.On("SETTING_CHANGED", function(path)
	if path == "enc.point" and anchor then place() end
	if type(path) == "string" and (path:find("^enc%.") or path == "*") then B.Refresh() end
end)

---------------------------------------------------------------------------
-- Moving it with everything else
---------------------------------------------------------------------------

function B.Unlock(on)
	build()
	unlocked = on and true or false
	if not handle then
		handle = ns.Movers.Handle(anchor, "Boss timers", function(p, rp, x, y) ns.Set("enc.point", { p, rp, x, y }) end)
	end
	B.Refresh()
	if unlocked then anchor:SetHeight(HEAD + 3 * (ROW + GAP)) end
	handle:Reveal(unlocked)
	ns.Movers.Active("encounters", unlocked)
	return true
end
function B.Unlocked() return unlocked end
function B.ResetPosition() ns.Set("enc.point", nil) end
ns.Movers.Group("encounters", function(on) if on or unlocked then B.Unlock(on) end end)
ns.On("MOVE_MODE", function(any) if not any and unlocked then B.Unlock(false) end end)
