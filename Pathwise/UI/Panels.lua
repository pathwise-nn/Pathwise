-- Pathwise side panels, beside the guide window: Skip (with alternatives),
-- Zones for your level, and Settings. One Signature panel, filled from a list
-- of rows each time it opens; opening another panel replaces it, opening the
-- same one again closes it.
--
-- Row kinds:
--   { "heading", text }                     small caps label
--   { "title", text }                       quest or panel title
--   { "text", text [, color] }              wrapped secondary text
--   { "choice", text, sub, onClick }        a full-width clickable row
--   { "setting", label, valueText, { { label, onClick }, ... } }
--   { "slider", label, settingPath, min, max, step, format(v) -> text }
--   { "divider" }
--   { "buttons", { { label, kind, onClick }, ... } }   right-aligned footer

local ADDON, ns = ...
local T = ns.Theme
local Panels = {}
ns.Panels = Panels

local WIDTH, PAD = 300, 16
local panel, openKind
local pool = { heading = {}, title = {}, text = {}, choice = {}, setting = {}, divider = {}, buttons = {}, slider = {} }
local used

local function build()
	panel = CreateFrame("Frame", "PathwisePanel", UIParent)
	panel:SetWidth(WIDTH)
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	T.Panel(panel)
	T.TrackGround(panel)
	-- The panel takes the window size when it opens, not while a slider in it
	-- is being dragged (it would move under the pointer).
	panel.close = T.IconButton(panel, "close", "Close", function() Panels.Close() end)
	panel.close:SetPoint("TOPRIGHT", -6, -6)
	panel:Hide()
end

local function take(kind, make)
	local list = pool[kind]
	used[kind] = (used[kind] or 0) + 1
	local w = list[used[kind]]
	if not w then
		w = make()
		list[used[kind]] = w
	end
	w:Show()
	return w
end

local function hideAll()
	for _, list in pairs(pool) do for _, w in ipairs(list) do w:Hide() end end
end

local makers = {}

function makers.heading()
	local fs = T.Text(panel, "label", "text2")
	return fs
end

function makers.title()
	return T.Text(panel, "quest", "text")
end

function makers.text()
	return T.Text(panel, "meta", "text2")
end

function makers.divider()
	return T.Divider(panel)
end

function makers.choice()
	local b = CreateFrame("Button", nil, panel)
	local hover = b:CreateTexture(nil, "BACKGROUND")
	hover:SetAllPoints()
	T.SetColor(hover, "hover")
	hover:Hide()
	b.text = T.Text(b, "body", "text")
	b.text:SetPoint("TOPLEFT", 8, -8)
	b.text:SetPoint("RIGHT", -8, 0)
	b.sub = T.Text(b, "small", "text2")
	b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -2)
	b.sub:SetPoint("RIGHT", -8, 0)
	b:SetScript("OnEnter", function() hover:Show() end)
	b:SetScript("OnLeave", function() hover:Hide() end)
	return b
end

function makers.setting()
	local f = CreateFrame("Frame", nil, panel)
	f:SetHeight(30)
	f.label = T.Text(f, "body", "text")
	f.label:SetPoint("LEFT")
	f.label:SetWordWrap(false)
	f.value = T.Text(f, "meta", "text2")
	f.value:SetJustifyH("RIGHT")
	f.buttons = {}
	return f
end

-- One slider row: the label on top; under it the slider and a box to type
-- the percentage into. The slider is made per setting (its range differs),
-- kept on the row by path; the box is shared and told which setting it edits.
local BOX_W = 46
function makers.slider()
	local f = CreateFrame("Frame", nil, panel)
	f:SetHeight(48)
	f.label = T.Text(f, "body", "text")
	f.label:SetPoint("TOPLEFT")
	f.label:SetWordWrap(false)
	f.pct = T.Text(f, "meta", "text2")
	f.pct:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -25)
	f.pct:SetText("%")
	f.box = T.NumberBox(f, BOX_W, function(n) if f.onBox then f.onBox(n) end end)
	f.box:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -20)
	f.sliders = {}
	return f
end

function makers.buttons()
	local f = CreateFrame("Frame", nil, panel)
	f:SetHeight(28)
	f.buttons = {}
	return f
end

-- A small control button inside a setting or footer row, made once per slot.
local function control(row, i, label, kind, onClick)
	local b = row.buttons[i]
	if not b or b.pwKind ~= kind then
		if b then b:Hide() end
		b = T.Button(row, label, kind)
		b.pwKind = kind
		row.buttons[i] = b
	end
	b.pwText:SetText(label)
	b:SetWidth(math.max(32, (b.pwText:GetStringWidth() or 10) + 20))
	b:SetHeight(24)
	b:SetScript("OnClick", function() onClick() end)
	b:Show()
	return b
end

local function render(rows)
	used = {}
	hideAll()
	panel.close:Show()
	local inner = WIDTH - PAD * 2
	local y = PAD
	local function place(w, h, gap, inset)
		w:ClearAllPoints()
		w:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (inset or 0), -(y + (gap or 0)))
		w:SetWidth(inner - (inset or 0) * 2)
		y = y + (gap or 0) + h
	end
	for i, r in ipairs(rows) do
		local kind = r[1]
		local first = i == 1
		if kind == "heading" then
			local fs = take("heading", makers.heading)
			fs:SetText(tostring(r[2]):upper())
			fs:SetWidth(inner - (first and 28 or 0))
			place(fs, fs:GetStringHeight() or 10, first and 0 or 14)
		elseif kind == "title" then
			local fs = take("title", makers.title)
			fs:SetText(r[2])
			fs:SetWidth(inner - (first and 28 or 0))
			place(fs, fs:GetStringHeight() or 18, first and 0 or 6)
		elseif kind == "text" then
			local fs = take("text", makers.text)
			T.TextColor(fs, r[3] or "text2")
			fs:SetWidth(inner)
			fs:SetText(r[2])
			place(fs, fs:GetStringHeight() or 14, 4)
		elseif kind == "divider" then
			local d = take("divider", makers.divider)
			d:ClearAllPoints()
			d:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y + 12))
			d:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -(y + 12))
			y = y + 13
		elseif kind == "choice" then
			local b = take("choice", makers.choice)
			b.text:SetText(r[2])
			b.sub:SetText(r[3] or "")
			b.sub:SetShown(r[3] ~= nil)
			b:SetWidth(inner + 8)
			local h = 8 + (b.text:GetStringHeight() or 14) + (r[3] and (2 + (b.sub:GetStringHeight() or 12)) or 0) + 8
			b:SetHeight(h)
			b:SetScript("OnClick", function() r[4]() end)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD - 8, -(y + 4))
			y = y + 4 + h
		elseif kind == "setting" then
			local f = take("setting", makers.setting)
			f.label:SetText(r[2])
			for _, b in ipairs(f.buttons) do b:Hide() end
			local anchor
			local ctrls = r[4] or {}
			for j = #ctrls, 1, -1 do
				local c = ctrls[j]
				local b = control(f, j, c[1], c[3] or "default", c[2])
				b:ClearAllPoints()
				if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -4, 0) else b:SetPoint("RIGHT", f, "RIGHT", 0, 0) end
				anchor = b
			end
			f.value:ClearAllPoints()
			if anchor then f.value:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else f.value:SetPoint("RIGHT") end
			f.value:SetText(r[3] or "")
			place(f, 30, 6)
		elseif kind == "slider" then
			local f = take("slider", makers.slider)
			local label, path, lo, hi, stepBy, format = r[2], r[3], r[4], r[5], r[6], r[7]
			f.label:SetText(label)
			for _, s in pairs(f.sliders) do s:Hide() end
			local s = f.sliders[path]
			local function percent(v) return math.floor(v * 100 + 0.5) end
			if not s then
				s = T.Slider(f, inner - BOX_W - 24, lo, hi, stepBy, function(v)
					ns.Set(path, v)
					f.box:SetNumber(percent(v))
				end)
				s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -22)
				f.sliders[path] = s
			end
			s:Show()
			-- Typed: any whole percentage in range (not only the slider's steps);
			-- outside the range it is held to the nearest end, and the box says so.
			f.onBox = function(n)
				local v = n and math.max(lo, math.min(hi, n / 100)) or (ns.Get(path) or lo)
				ns.Set(path, v)
				s:SetQuietly(v)
				f.box:SetNumber(percent(v))
				if n and n / 100 ~= v then
					ns.Print(("%s: %d-%d%%, so %d%%."):format(label, percent(lo), percent(hi), percent(v)))
				end
			end
			local v = ns.Get(path) or lo
			s:SetQuietly(v)
			f.box:SetNumber(percent(v))
			place(f, 48, 8)
		elseif kind == "buttons" then
			local f = take("buttons", makers.buttons)
			for _, b in ipairs(f.buttons) do b:Hide() end
			local anchor
			local list = r[2] or {}
			for j = #list, 1, -1 do
				local c = list[j]
				local b = control(f, j, c[1], c[2] or "default", c[3])
				b:ClearAllPoints()
				if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else b:SetPoint("RIGHT", f, "RIGHT", 0, 0) end
				anchor = b
			end
			place(f, 28, 16)
		end
	end
	panel:SetHeight(y + PAD)
end

-- Beside the guide window, on whichever side has room.
local function anchor()
	panel:ClearAllPoints()
	local g = _G.PathwiseGuide
	if g and g:IsShown() then
		local left = g.GetLeft and g:GetLeft()
		if left and left > WIDTH + 20 then
			panel:SetPoint("TOPRIGHT", g, "TOPLEFT", -8, 0)
		else
			panel:SetPoint("TOPLEFT", g, "TOPRIGHT", 8, 0)
		end
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
end

local builders = {}

function Panels.Open(kind)
	if not panel then build() end
	if openKind == kind and panel:IsShown() then return Panels.Close() end
	local rows = builders[kind] and builders[kind]()
	if not rows then return end
	openKind = kind
	panel:SetScale(ns.Get("ui.scale") or 1)
	render(rows)
	anchor()
	panel:Show()
end

function Panels.Refresh()
	if panel and panel:IsShown() and openKind and builders[openKind] then render(builders[openKind]()) end
end

function Panels.Close()
	if panel then panel:Hide() end
	openKind = nil
end

function Panels.IsOpen(kind) return panel ~= nil and panel:IsShown() and openKind == kind end

---------------------------------------------------------------------------
-- Skip
---------------------------------------------------------------------------

local function yardsText(y)
	if not y then return nil end
	return ns.Nav.FormatYards(y)
end

function builders.skip()
	local E, Q = ns.Engine, ns.Quests
	local rows = { { "heading", "Skip quest" } }
	local quests = E.SkippableQuests()
	if #quests == 0 then
		rows[#rows + 1] = { "text", "Nothing to skip on this step." }
	end
	for i, q in ipairs(quests) do
		if i > 1 then rows[#rows + 1] = { "divider" } end
		rows[#rows + 1] = { "title", Q.Name(q) }
		rows[#rows + 1] = { "choice", "Skip just this quest", "Its follow-ups stay in the route", function()
			E.SkipQuest(q, false)
			ns.Print(("skipped %s."):format(Q.Name(q)))
			Panels.Refresh()
		end }
		rows[#rows + 1] = { "choice", "Skip it and its follow-ups", "The whole chain leaves the route", function()
			local list = E.SkipQuest(q, true)
			ns.Print(("skipped %s and %d follow-up%s."):format(Q.Name(q), #list - 1, #list == 2 and "" or "s"))
			Panels.Refresh()
		end }
	end
	rows[#rows + 1] = { "divider" }
	rows[#rows + 1] = { "heading", "Instead, nearby" }
	local alts = E.Alternatives(5)
	if #alts == 0 then
		rows[#rows + 1] = { "text", "No other quests at your level are open on this map right now." }
	end
	for _, a in ipairs(alts) do
		local sub = ("Level %d  ·  %s%s"):format(a.level, a.giver or "?", a.yards and ("  ·  " .. yardsText(a.yards)) or "")
		rows[#rows + 1] = { "choice", a.name, sub, function()
			E.AddExtra(a.quest)
			ns.Print(("%s added; the route picks up again after it."):format(a.name))
			Panels.Close()
		end }
	end
	rows[#rows + 1] = { "buttons", { { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Zones for your level
---------------------------------------------------------------------------

function builders.zones()
	local E, Q = ns.Engine, ns.Quests
	local p = Q.Player()
	local rows = { { "heading", ("Zones for level %d"):format(p.level or 1) } }
	local current = E.Route()
	local zones = E.Zones()
	if #zones == 0 then rows[#rows + 1] = { "text", "No zone data for your level and side." } end
	for _, z in ipairs(zones) do
		local note
		if z.route and current and z.route.id == current.id then note = "Your route"
		elseif z.route then note = "Pathwise route  ·  click to switch"
		else note = "Route coming" end
		rows[#rows + 1] = { "choice", ("%s   %d-%d"):format(z.name, z.low, z.high), note, function()
			if z.route then
				E.SetRoute(z.route.id)
				ns.Print(("route: %s."):format(z.route.title))
				Panels.Close()
			else
				ns.Print(("there is no Pathwise route for %s yet."):format(z.name))
			end
		end }
	end
	rows[#rows + 1] = { "text", "Level ranges are estimated from the quests in each zone (QuestieDB data).", "muted" }
	rows[#rows + 1] = { "buttons", { { "All routes", "default", function() Panels.Open("routes") end }, { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Routes: leveling routes near the character's level, class quests, and
-- profession guides to follow beside them
---------------------------------------------------------------------------

local showAll = { leveling = false, professions = false }

-- A profession route's skill line: its first train or skill goal's.
local function lineOf(route)
	for _, step in ipairs(route.steps) do
		for _, g in ipairs(step) do
			if g[1] == "train" or g[1] == "skill" then return g[2] end
		end
	end
end

function builders.routes()
	local E, Q = ns.Engine, ns.Quests
	local p = Q.Player()
	local current, side = E.Route(), E.Side()
	local rows = { { "heading", "Routes" } }

	rows[#rows + 1] = { "heading", "Leveling" }
	local shown = 0
	for _, r in ipairs(E.RoutesFor(p, "Leveling")) do
		local near = p.level >= r.levels[1] - 4 and p.level <= r.levels[2] + 2
		if showAll.leveling or near or (current and current.id == r.id) then
			shown = shown + 1
			local mine = current and current.id == r.id
			rows[#rows + 1] = { "choice", ("%s   %d-%d"):format(r.title, r.levels[1], r.levels[2]),
				mine and "Your route" or nil, function()
					E.SetRoute(r.id)
					ns.Print("route: " .. r.title)
					Panels.Refresh()
				end }
		end
	end
	if shown == 0 then rows[#rows + 1] = { "text", "No leveling route near your level." } end
	rows[#rows + 1] = { "choice", showAll.leveling and "Show routes near my level" or "Show every leveling route", nil, function()
		showAll.leveling = not showAll.leveling
		Panels.Refresh()
	end }

	local class = E.RoutesFor(p, "Class")
	if #class > 0 then
		rows[#rows + 1] = { "heading", "Class quests" }
		for _, r in ipairs(class) do
			local mine = current and current.id == r.id
			rows[#rows + 1] = { "choice", ("%s   %d-%d"):format(r.title, r.levels[1], r.levels[2]),
				mine and "Your route" or (p.level < r.levels[1] and ("From level " .. r.levels[1])) or nil, function()
					E.SetRoute(r.id)
					ns.Print("route: " .. r.title)
					Panels.Refresh()
				end }
		end
	end

	rows[#rows + 1] = { "heading", "Professions, beside your route" }
	local listed = 0
	for _, r in ipairs(E.RoutesFor(p, "Professions")) do
		local line = lineOf(r)
		local have = line and ns.Compat.SkillRank(line)
		local mine = side and side.id == r.id
		if showAll.professions or have or mine then
			listed = listed + 1
			rows[#rows + 1] = { "choice", r.title, mine and "Following  ·  click to stop" or (have and ("Skill " .. have)) or nil, function()
				E.SetSide(mine and nil or r.id)
				ns.Print(mine and "stopped following " .. r.title .. "." or ("following " .. r.title .. " beside your route."))
				Panels.Refresh()
			end }
		end
	end
	if listed == 0 then rows[#rows + 1] = { "text", "You have no professions yet." } end
	rows[#rows + 1] = { "choice", showAll.professions and "Show my professions only" or "Show every profession", nil, function()
		showAll.professions = not showAll.professions
		Panels.Refresh()
	end }
	rows[#rows + 1] = { "text", "Routes adapted from Polestar (GPL-3.0); quest data from QuestieDB.", "muted" }
	rows[#rows + 1] = { "buttons", { { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local function pct(v) return ("%d%%"):format(math.floor(v * 100 + 0.5)) end
local function toggle(path)
	return function()
		ns.Set(path, not ns.Get(path))
		Panels.Refresh()
	end
end
local function onOff(v) return v and "On" or "Off" end

function builders.settings()
	local E = ns.Engine
	local route = E.Route()
	local skippedN = #E.Skipped()
	return {
		{ "heading", "Settings" },
		{ "heading", "Guide window" },
		{ "slider", "Window size", "ui.scale", 0.5, 1.5, 0.05, pct },
		{ "slider", "Background opacity", "ui.opacity", 0.4, 1, 0.05, pct },
		{ "setting", "Compact mode", onOff(ns.Get("guide.compact")), { { ns.Get("guide.compact") and "Turn off" or "Turn on", toggle("guide.compact") } } },
		{ "heading", "Waypoint arrow" },
		{ "setting", "Show the arrow", onOff(ns.Get("arrow.shown")), { { ns.Get("arrow.shown") and "Hide" or "Show", toggle("arrow.shown") } } },
		{ "slider", "Arrow size", "arrow.scale", 0.5, 2, 0.1, pct },
		{ "text", "Shift-drag the arrow to move it.", "muted" },
		{ "heading", "Route" },
		{ "setting", route and route.title or "No route", "", { { "Routes", function() Panels.Open("routes") end }, { "Zones", function() Panels.Open("zones") end } } },
		{ "setting", "Side guide", E.Side() and E.Side().title or "None", E.Side() and { { "Stop", function() E.SetSide(nil) Panels.Refresh() end } } or {} },
		{ "setting", "Skipped quests", tostring(skippedN), skippedN > 0 and { { "Bring back", function()
			for _, q in ipairs(E.Skipped()) do E.State().skipped[q] = nil end
			E.Update()
			Panels.Refresh()
		end } } or {} },
		{ "divider" },
		{ "setting", "Window positions", "", { { "Reset", function()
			ns.Set("guide.point", nil)
			ns.Set("arrow.point", nil)
			local g, a = _G.PathwiseGuide, _G.PathwiseArrow
			if g then g:ClearAllPoints() g:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -60, -220) end
			if a then a:ClearAllPoints() a:SetPoint("TOP", UIParent, "TOP", 0, -140) end
			Panels.Refresh()
		end } } },
		{ "text", ("Pathwise %s  ·  Every quest. Every craft. Every level.\nCreated by leight_nn & florp   _nn"):format(ns.VERSION), "muted" },
	}
end

ns.On("GUIDE_SKIP", function() Panels.Open("skip") end)
ns.On("SHOW_ZONES", function() Panels.Open("zones") end)
ns.On("SHOW_SETTINGS", function() Panels.Open("settings") end)
ns.On("SHOW_ROUTES", function() Panels.Open("routes") end)
ns.On("GUIDE_UPDATED", function() if Panels.IsOpen("skip") then Panels.Refresh() end end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" and not ns.Get("guide.shown") then Panels.Close() end
end)
