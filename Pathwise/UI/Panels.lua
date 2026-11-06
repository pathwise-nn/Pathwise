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
--   { "slider", label, settingPath, min, max, step, format(v) -> text, unit }
--       unit "count": whole numbers (columns, slots); else a fraction shown as %
--   { "progress", fraction }                thin progress line (a profession's skill)
--   { "copy", text, lines }                 selectable text to copy (Ctrl+C)
--   { "icon", size }                        the Pathwise compass mark
--   { "coords", onSet(x, y), onClear }      X and Y boxes with Set and Clear
--   { "input", key, lines }                 a box to type or paste into; Panels.InputText(key)
--   { "divider" }
--   { "buttons", { { label, kind, onClick }, ... } }   right-aligned footer

local ADDON, ns = ...
local T = ns.Theme
local Panels = {}
ns.Panels = Panels

local WIDTH, PAD = 300, 16
local panel, openKind
local scroll, host -- the rows live on `host`, scrolled inside the panel when taller than the screen
local pool = { heading = {}, title = {}, text = {}, choice = {}, setting = {}, divider = {}, buttons = {}, slider = {}, progress = {}, copy = {}, icon = {}, coords = {}, input = {} }
local inputs = {} -- key -> the text typed into that input row
local used

local function build(name)
	panel = CreateFrame("Frame", name or "PathwisePanel", UIParent)
	panel:SetWidth(WIDTH)
	panel:SetFrameStrata("MEDIUM")
	panel:SetClampedToScreen(true)
	panel:EnableMouse(true)
	T.Panel(panel)
	T.TrackGround(panel)
	-- The panel takes the window size when it opens, not while a slider in it
	-- is being dragged (it would move under the pointer).
	scroll = CreateFrame("ScrollFrame", nil, panel)
	scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -1)
	scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 1)
	host = CreateFrame("Frame", nil, scroll)
	host:SetWidth(WIDTH)
	host:SetHeight(1)
	scroll:SetScrollChild(host)
	scroll:EnableMouseWheel(true)
	local child = host
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local maxScroll = math.max(0, (child:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * 40))
		self:SetVerticalScroll(v)
	end)
	panel.close = T.IconButton(panel, "close", "Close", function() Panels.Close() end)
	panel.close:SetPoint("TOPRIGHT", -6, -6)
	panel.close:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	-- Back: to the panel this one was opened from (Settings > a suite addon).
	panel.back = T.IconButton(panel, "back", "Back", function() Panels.Back() end)
	panel.back:SetPoint("RIGHT", panel.close, "LEFT", -2, 0)
	panel.back:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5)
	panel.back:Hide()
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
	local fs = T.Text(host, "label", "text2")
	return fs
end

function makers.title()
	return T.Text(host, "quest", "text")
end

function makers.text()
	return T.Text(host, "meta", "text2")
end

function makers.divider()
	return T.Divider(host)
end

function makers.choice()
	local b = CreateFrame("Button", nil, host)
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
	local f = CreateFrame("Frame", nil, host)
	f:SetHeight(30)
	f.label = T.Text(f, "body", "text")
	f.label:SetPoint("LEFT")
	f.label:SetWordWrap(true)
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
	local f = CreateFrame("Frame", nil, host)
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

function makers.progress()
	local f = CreateFrame("Frame", nil, host)
	f:SetHeight(T.PROGRESS_H)
	f.line = T.ProgressLine(f)
	f.line.track:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
	return f
end

-- Text to copy: a read-only, multi-line box. Clicking selects it all; the
-- player presses Ctrl+C. Typing is undone at once (the text stays as built).
function makers.copy()
	local f = CreateFrame("Frame", nil, host)
	T.Panel(f, "bg2")
	local e = CreateFrame("EditBox", nil, f)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetPoint("TOPLEFT", 8, -6)
	e:SetPoint("BOTTOMRIGHT", -8, 6)
	if not e:SetFont(T.FONTS.regular, 11, "") then e:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end
	local c = T.Color("text2")
	e:SetTextColor(c[1], c[2], c[3])
	e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	e:SetScript("OnMouseUp", function(self) self:SetFocus() self:HighlightText() end)
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnTextChanged", function(self, user)
		if user and f.text and self:GetText() ~= f.text then self:SetText(f.text) self:HighlightText() end
	end)
	f.box = e
	return f
end

-- X and Y boxes with Set and Clear, for a waypoint on the map the player is on.
function makers.coords()
	local f = CreateFrame("Frame", nil, host)
	f:SetHeight(26)
	f.xl = T.Text(f, "meta", "text2")
	f.xl:SetPoint("LEFT", f, "LEFT", 0, 0)
	f.xl:SetText("X")
	f.x = T.NumberBox(f, 52, function() end)
	f.x:SetPoint("LEFT", f.xl, "RIGHT", 6, 0)
	f.yl = T.Text(f, "meta", "text2")
	f.yl:SetPoint("LEFT", f.x, "RIGHT", 10, 0)
	f.yl:SetText("Y")
	f.y = T.NumberBox(f, 52, function() end)
	f.y:SetPoint("LEFT", f.yl, "RIGHT", 6, 0)
	f.clear = T.Button(f, "Clear", "default")
	f.clear:SetPoint("RIGHT", f, "RIGHT", 0, 0)
	f.clear:SetHeight(24)
	f.set = T.Button(f, "Set", "accent")
	f.set:SetPoint("RIGHT", f.clear, "LEFT", -6, 0)
	f.set:SetHeight(24)
	return f
end

-- A box to type or paste into (several lines); what it holds is kept by key.
function makers.input()
	local f = CreateFrame("Frame", nil, host)
	T.Panel(f, "bg2")
	local e = CreateFrame("EditBox", nil, f)
	e:SetMultiLine(true)
	e:SetAutoFocus(false)
	e:SetPoint("TOPLEFT", 8, -6)
	e:SetPoint("BOTTOMRIGHT", -8, 6)
	if not e:SetFont(T.FONTS.regular, 11, "") then e:SetFont("Fonts\\FRIZQT__.TTF", 11, "") end
	local c = T.Color("text")
	e:SetTextColor(c[1], c[2], c[3])
	e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	e:SetScript("OnTextChanged", function(self) if f.key then inputs[f.key] = self:GetText() end end)
	e:SetScript("OnMouseUp", function(self) self:SetFocus() end)
	f.box = e
	return f
end

function Panels.InputText(key) return inputs[key] end
function Panels.ClearInput(key) inputs[key] = nil end

function makers.icon()
	return T.Icon(host, 40)
end

function makers.buttons()
	local f = CreateFrame("Frame", nil, host)
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
		w:SetPoint("TOPLEFT", host, "TOPLEFT", PAD + (inset or 0), -(y + (gap or 0)))
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
			d:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -(y + 12))
			d:SetPoint("TOPRIGHT", host, "TOPRIGHT", -PAD, -(y + 12))
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
			b:SetPoint("TOPLEFT", host, "TOPLEFT", PAD - 8, -(y + 4))
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
			-- The state words ("On", "By kind") only when the buttons do not
			-- already show it: a highlighted choice says it for them.
			local choice = false
			for _, c in ipairs(ctrls) do if c[3] == "accent" then choice = true end end
			local valueText = choice and "" or (r[3] or "")
			f.value:ClearAllPoints()
			if anchor then f.value:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else f.value:SetPoint("RIGHT") end
			f.value:SetText(valueText)
			-- The label takes what is left of the row, and wraps rather than
			-- running under the value and the buttons.
			local used = 0
			for j = 1, #ctrls do local b = f.buttons[j] if b and b:IsShown() then used = used + (b:GetWidth() or 0) + 4 end end
			if valueText ~= "" then used = used + (f.value:GetStringWidth() or 0) + 8 end
			local room = inner - used - 6
			f.label:ClearAllPoints()
			f.label:SetPoint("LEFT")
			f.label:SetWidth(math.max(60, room))
			local h = math.max(30, (f.label:GetStringHeight() or 14) + 12)
			f:SetHeight(h)
			place(f, h, 6)
		elseif kind == "copy" then
			local f = take("copy", makers.copy)
			f.text = r[2]
			f.box:SetText(r[2])
			f.box:SetWidth(inner - 16)
			place(f, 12 + (r[3] or 6) * 14, 6)
		elseif kind == "input" then
			local f = take("input", makers.input)
			f.key = r[2]
			f.box:SetText(inputs[r[2]] or "")
			f.box:SetWidth(inner - 16)
			place(f, 12 + (r[3] or 3) * 14, 6)
		elseif kind == "coords" then
			local f = take("coords", makers.coords)
			local function read(box)
				local t = (box:GetText() or ""):gsub("%s", ""):gsub(",", ".")
				return t:match("^%d+%.?%d*$") and tonumber(t) or nil
			end
			f.set:SetScript("OnClick", function() r[2](read(f.x), read(f.y)) end)
			f.clear:SetScript("OnClick", function() r[3]() end)
			place(f, 26, 8)
		elseif kind == "icon" then
			local ic = take("icon", makers.icon)
			ic:SetSize(r[2] or 40, r[2] or 40)
			ic:ClearAllPoints()
			ic:SetPoint("TOPLEFT", host, "TOPLEFT", PAD, -y)
			y = y + (r[2] or 40) + 4
		elseif kind == "progress" then
			local f = take("progress", makers.progress)
			f.line.track:SetWidth(inner) -- set, not anchored: the fill reads it at once
			f.line:SetProgress(r[2])
			place(f, T.PROGRESS_H, 6)
		elseif kind == "slider" then
			local f = take("slider", makers.slider)
			local label, path, lo, hi, stepBy, format = r[2], r[3], r[4], r[5], r[6], r[7]
			local count = r[8] == "count"
			local mul = count and 1 or 100
			f.label:SetText(label)
			f.pct:SetText(count and "" or "%")
			for _, s in pairs(f.sliders) do s:Hide() end
			local s = f.sliders[path]
			local function percent(v) return math.floor(v * mul + 0.5) end
			if not s then
				s = T.Slider(f, inner - BOX_W - 24, lo, hi, stepBy, function(v)
					ns.Set(path, v)
					f.box:SetNumber(percent(v))
				end)
				s:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -22)
				s.pwOnDragStart = function() Panels.Pin() end
				s.pwOnDragStop = function() Panels.Unpin() end
				f.sliders[path] = s
			end
			s:Show()
			-- Typed: any whole percentage in range (not only the slider's steps);
			-- outside the range it is held to the nearest end, and the box says so.
			f.onBox = function(n)
				if count and n then n = math.floor(n + 0.5) end
				local v = n and math.max(lo, math.min(hi, n / mul)) or (ns.Get(path) or lo)
				ns.Set(path, v)
				s:SetQuietly(v)
				f.box:SetNumber(percent(v))
				if n and n / mul ~= v then
					local u = count and "" or "%"
					ns.Print(("%s: %d-%d%s, so %d%s."):format(label, percent(lo), percent(hi), u, percent(v), u))
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
	-- Taller than 80% of the screen: the panel stops there and scrolls.
	local full = y + PAD
	host:SetHeight(full)
	local screen = (UIParent.GetHeight and UIParent:GetHeight() or 0) * 0.8 / (panel:GetScale() or 1)
	if screen < 200 then screen = full end
	panel:SetHeight(math.min(full, screen))
	panel.scrolls = full > screen
end

-- While a slider in the panel is dragged, the panel holds still where it
-- is on screen: "Window size" resizes the guide window, and a panel pinned
-- beside it would slide under the pointer and the slider would swing from
-- end to end. Let go and it goes back beside the guide.
local pinned = false
function Panels.Pin()
	if not panel or pinned then return end
	local left, top = panel:GetLeft(), panel:GetTop()
	if not (left and top) then return end
	pinned = true
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
end
function Panels.IsPinned() return pinned end

-- A suite addon's panels open by its own minimap button (Panels.SetHome).
local homes = {} -- kind -> function returning the frame to open beside
function Panels.SetHome(kind, frameFn)
	if type(kind) == "string" then homes[kind] = frameFn end
end

-- Beside `home` (a minimap button), on the side of the screen with room:
-- left of it on the right half, right of it on the left half; hanging down
-- from it in the top half, standing up from it in the bottom half. Placed
-- by screen position, not attached to the button. -> true when placed
function Panels.PlaceBy(home)
	local cx, cy = home:GetCenter()
	local hs, ps = home:GetEffectiveScale(), panel:GetEffectiveScale()
	local us = UIParent:GetEffectiveScale()
	if not (cx and cy and hs and ps and ps > 0) then return false end
	local x, y = cx * hs / ps, cy * hs / ps
	local w = (UIParent:GetWidth() or 0) * us / ps
	local h = (UIParent:GetHeight() or 0) * us / ps
	local ph = panel:GetHeight() or 0
	local left = (x > w / 2) and (x - 24 - WIDTH) or (x + 24)
	local top
	if y > h / 2 then top = math.min(h - 8, y + 16) else top = math.max(ph + 8, y - 16 + ph) end
	panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	return true
end

-- By its minimap button (a suite addon's panel), else beside the guide
-- window on whichever side has room.
local function anchor()
	panel:ClearAllPoints()
	local home = openKind and homes[openKind] and homes[openKind]()
	if home and home.IsShown and home:IsShown() and Panels.PlaceBy(home) then return end
	panel:ClearAllPoints()
	local g = _G.PathwiseGuide
	if g and g:IsShown() then
		local left = g.GetLeft and g:GetLeft()
		local ok
		if left and left > WIDTH + 20 then
			ok = pcall(panel.SetPoint, panel, "TOPRIGHT", g, "TOPLEFT", -8, 0)
		else
			ok = pcall(panel.SetPoint, panel, "TOPLEFT", g, "TOPRIGHT", 8, 0)
		end
		if ok then return end
		panel:ClearAllPoints()
	end
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
end

function Panels.Unpin()
	if not pinned then return end
	pinned = false
	if panel and panel:IsShown() then anchor() end
end

local builders = {}

-- Where the open panel came from: a list of kinds, the last one first back.
local history = {}
local goingBack = false

function Panels.Open(kind)
	if not panel then build() end
	if openKind == kind and panel:IsShown() then return Panels.Close() end
	if not builders[kind] then return end
	local before = #history
	if goingBack then
		-- Panels.Back pops history itself.
	elseif panel:IsShown() and openKind and openKind ~= kind then
		history[#history + 1] = openKind
	else
		history = {}
	end
	local was = openKind
	openKind = kind -- the builder asks S.CanGoBack(), which looks at this
	local rows = builders[kind]()
	if not rows then
		openKind = was
		while #history > before do table.remove(history) end
		return
	end
	panel.back:SetShown(Panels.CanGoBack())
	panel:SetScale(ns.Get("ui.scale") or 1)
	scroll:SetVerticalScroll(0)
	render(rows)
	anchor()
	panel:Show()
end

-- Another Pathwise addon's panel (Pathwise.Suite.Panel).
-- The suite addons' panels: Back always leads somewhere from them (at least
-- to Pathwise's settings, where the suite is listed).
local suiteKinds = {}
function Panels.Register(kind, builder)
	if type(kind) == "string" and type(builder) == "function" then
		builders[kind] = builder
		suiteKinds[kind] = true
	end
end

function Panels.Refresh()
	if panel and panel:IsShown() and openKind and builders[openKind] then
		render(builders[openKind]())
		if not pinned then anchor() end
	end
end

function Panels.Close()
	if panel then panel:Hide() end
	openKind = nil
	history = {}
end

-- Back to the panel this one was opened from. -> true when there was one
function Panels.Back()
	local prev = table.remove(history)
	if not prev and openKind and suiteKinds[openKind] then prev = "settings" end
	if not prev then return false end
	goingBack = true
	openKind = nil
	local ok, err = pcall(Panels.Open, prev)
	goingBack = false
	if not ok then ns.Error("Back", err) end
	return true
end
function Panels.CanGoBack() return #history > 0 or (openKind ~= nil and suiteKinds[openKind] == true) end

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
		rows[#rows + 1] = { "choice", "I've already done it", "Counts as handed in: the quests after it come up", function()
			E.MarkQuestDone(q)
			ns.Print(("marked %s done."):format(Q.Name(q)))
			Panels.Refresh()
		end }
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
	if E.CurrentStep() and not E.Extra() then
		rows[#rows + 1] = { "divider" }
		rows[#rows + 1] = { "choice", "This step is done", "Everything on it, items and places too: on to the next", function()
			E.MarkStepDone()
			ns.Print("step marked done.")
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
Panels.showAll = showAll

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
	-- More guides, folded until opened: reputation, mounts, pets, exploration, the rest.
	local function section(key, title, list)
		if #list == 0 then return end
		local open = showAll[key]
		rows[#rows + 1] = { "choice", ("%s %s (%d)"):format(open and "Hide" or "Show", title, #list), nil, function()
			showAll[key] = not showAll[key]
			Panels.Refresh()
		end }
		if not open then return end
		for _, r in ipairs(list) do
			local mine = current and current.id == r.id
			rows[#rows + 1] = { "choice", r.title, mine and "Your route" or (r.levels and p.level < r.levels[1] and ("From level " .. r.levels[1])) or nil, function()
				E.SetRoute(r.id)
				ns.Print("route: " .. r.title)
				Panels.Refresh()
			end }
		end
	end
	local mounts, pets = {}, {}
	for _, r in ipairs(E.RoutesFor(p, "Collectibles")) do
		if r.id:find("/pets/") then pets[#pets + 1] = r else mounts[#mounts + 1] = r end
	end
	rows[#rows + 1] = { "heading", "More guides" }
	section("reputation", "reputation guides", E.RoutesFor(p, "Reputation"))
	section("mounts", "mount guides", mounts)
	section("pets", "pet guides", pets)
	section("exploration", "exploration guides", E.RoutesFor(p, "Exploration"))
	section("misc", "other guides", E.RoutesFor(p, "Miscellaneous"))

	rows[#rows + 1] = { "text", "Routes adapted from Polestar (GPL-3.0); quest data from QuestieDB.", "muted" }
	rows[#rows + 1] = { "buttons", { { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Professions dashboard: per profession its skill, where the guide stands,
-- the best craft now and the materials for this rank; then disenchanting and
-- the Tailoring + Enchanting tip. Advice only: Pathwise never crafts, buys,
-- sells or disenchants.
---------------------------------------------------------------------------

local SOURCE = { vendor = "vendor", farm = "farm" }
local MAX_MATERIALS = 6

-- Professions: a list of yours, each with its skill and what is next;
-- click one for its page (Panels.Open("profession")).
local profKey -- the profession whose page is open

-- One line about where a profession stands, for the list.
local function professionSummary(prof)
	local P, E = ns.Professions, ns.Engine
	local route, st = P.Route(prof), P.Stage(prof)
	if not route then return "No guide for this profession yet" end
	if not st then return "Every step of the guide is done" end
	local bits = {}
	local step = route.steps[st.step]
	bits[#bits + 1] = "Now: " .. (step.title or E.GoalText(step[1]) or "the next step")
	local missing = 0
	for _, r in ipairs(P.Shopping(prof)) do if r.missing > 0 then missing = missing + 1 end end
	if missing > 0 then bits[#bits + 1] = ("%d material%s to get"):format(missing, missing == 1 and "" or "s") end
	local side = E.Side()
	if side and side.id == route.id then bits[#bits + 1] = "following" end
	return table.concat(bits, "  ·  ")
end

function builders.professions()
	local P, E = ns.Professions, ns.Engine
	E.Refresh()
	local rows = { { "heading", "Professions" } }
	local known = P.Known()
	if #known == 0 then
		rows[#rows + 1] = { "text", "No professions yet. Visit a profession trainer to learn one: Pathwise follows it from there." }
		rows[#rows + 1] = { "choice", "Browse the profession guides", nil, function() Panels.Open("routes") end }
	else
		rows[#rows + 1] = { "text", "Click a profession for its next craft, materials and guide.", "muted" }
	end
	for _, k in ipairs(known) do
		local prof = k.prof
		rows[#rows + 1] = { "choice", ("%s   %d / %d"):format(prof.name, k.rank, k.cap), professionSummary(prof), function()
			profKey = prof.key
			Panels.Open("profession")
		end }
		rows[#rows + 1] = { "progress", k.cap > 0 and k.rank / k.cap or 0 }
	end
	rows[#rows + 1] = { "choice", "Recipe books", "Every profession's plan by skill range, learned or not", function() Panels.OpenRecipeBook(nil) end }
	rows[#rows + 1] = { "buttons", { { "Profession guides", "default", function() Panels.Open("routes") end }, { "Close", "default", Panels.Close } } }
	return rows
end

-- One profession's page: skill, the guide's step, the best craft now, every
-- material for this rank, following it beside the route; for Enchanting,
-- disenchanting too.
function builders.profession()
	local P, E = ns.Professions, ns.Engine
	E.Refresh()
	local prof = profKey and P.BY_KEY[profKey]
	local k
	for _, x in ipairs(P.Known()) do if prof and x.prof.key == prof.key then k = x end end
	if not (prof and k) then return builders.professions() end
	local rows = { { "heading", "Professions" } }
	rows[#rows + 1] = { "title", ("%s   %d / %d"):format(prof.name, k.rank, k.cap) }
	rows[#rows + 1] = { "progress", k.cap > 0 and k.rank / k.cap or 0 }
	local route = P.Route(prof)
	local st = P.Stage(prof)
	if not route then
		rows[#rows + 1] = { "text", "No guide for this profession yet." }
	elseif not st then
		rows[#rows + 1] = { "text", "Every step of the guide is done.", "success" }
	else
		local step = route.steps[st.step]
		rows[#rows + 1] = { "text", "Now: " .. (step.title or E.GoalText(step[1]) or "the next step"), "text" }
		local craft = P.NextCraft(prof)
		if craft then
			local bits = { "Best now: " .. (craft.name or "?") }
			if craft.craftable then bits[#bits + 1] = ("%d from your bags"):format(craft.craftable) end
			if craft.untilSkill then bits[#bits + 1] = ("until %d"):format(craft.untilSkill) end
			if craft.difficulty then bits[#bits + 1] = craft.difficulty end
			if craft.known == false then bits[#bits + 1] = "learn it first" end
			rows[#rows + 1] = { "text", table.concat(bits, "  ·  "), "text" }
		end
		if prof.kind == "craft" and not P.Recipes(prof.line) then
			rows[#rows + 1] = { "text", ("Open your %s window once so Pathwise can read your recipes."):format(prof.name), "muted" }
		end
		local shop = P.Shopping(prof)
		if #shop > 0 then
			rows[#rows + 1] = { "heading", "Materials for this rank" }
			for _, r in ipairs(shop) do
				local how = SOURCE[r.src] or "made or found"
				if r.where then how = how .. ": " .. r.where end
				local status = r.missing > 0 and ("%d to get"):format(r.missing) or "ready"
				rows[#rows + 1] = { "text", ("%s   %d / %d  ·  %s  ·  %s"):format(r.name, r.have, r.need, status, how),
					r.missing > 0 and "text2" or "success" }
			end
		end
		local side = E.Side()
		local following = side and side.id == route.id
		rows[#rows + 1] = { "choice", following and "Following beside your route" or "Follow beside your route",
			following and "Click to stop" or "Its next step shows in the guide window", function()
				E.SetSide(following and nil or route.id)
				Panels.Refresh()
			end }
	end

	-- Herbalism and Mining: the zones with the most skill-ups for your rank.
	local G = ns.Gathering
	local gk = G and G.BY_KEY[prof.key]
	if gk then
		rows[#rows + 1] = { "heading", "Where to gather now" }
		local zones = G.BestZones(gk, k.rank, nil, 5)
		if #zones == 0 then
			rows[#rows + 1] = { "text", "Nothing left that gives you skill: every node is grey to you.", "muted" }
		end
		for _, z in ipairs(zones) do
			local bits = {}
			for j = 1, math.min(3, #z.nodes) do bits[#bits + 1] = ("%d %s"):format(z.nodes[j].count, z.nodes[j].name) end
			local about = table.concat(bits, ", ")
			if z.unchecked then about = about .. "  ·  not checked on Forever" end
			local levels = z.low and (" (%d-%d)"):format(z.low, z.high) or ""
			rows[#rows + 1] = { "choice", z.name .. levels, about, function()
				local spot = G.Spot(z.map, gk, k.rank)
				if spot then
					ns.Nav.SetTarget(z.map, spot.x, spot.y, ("%s, %s"):format(spot.name, z.name))
					ns.Print(("the arrow leads to %s in %s."):format(spot.name, z.name))
				end
			end }
		end
		rows[#rows + 1] = { "text", "Click a zone for the arrow. Every node that still gives you skill is on your map and minimap in its colour: orange always, yellow often, green seldom (Settings > Map pins).", "muted" }
		rows[#rows + 1] = { "text", "Forever's new herbs and ores (Bauxite, Pyrite, Demonsage...) aren't in the data yet.", "muted" }
	end

	-- Disenchanting and the Tailoring tip, on the Enchanting page.
	if prof.line == 333 then
		local list = P.Disenchantable(k.rank)
		if #list > 0 then
			rows[#rows + 1] = { "heading", "Disenchanting" }
			local needs, row = P.EnchantingNeedsDust()
			if needs then
				rows[#rows + 1] = { "text", ("Your Enchanting rank still needs %s: these are worth disenchanting."):format(row.name), "accent" }
			else
				rows[#rows + 1] = { "text", "Nothing in your Enchanting rank needs these now: compare the vendor price with what they fetch." }
			end
			for j, it in ipairs(list) do
				if j > 6 then break end
				local skill = it.skill and ((P.DE_SKILL_VERIFIED and "" or "≈") .. it.skill) or "?"
				rows[#rows + 1] = { "text", ("%s  ·  skill %s  ·  item level %d"):format(it.name, skill, it.ilvl or 0),
					it.canNow and "text" or "muted" }
			end
			if not P.DE_SKILL_VERIFIED then
				rows[#rows + 1] = { "text", "Skill needed is the Classic table, not yet checked on Forever: your tooltip has the last word.", "muted" }
			end
		end
		local te = P.TailorEnchant()
		if te and #te > 0 then
			rows[#rows + 1] = { "heading", "Tailoring + Enchanting" }
			rows[#rows + 1] = { "text", ("Disenchant what you craft for points instead of selling it: %s."):format(table.concat(te, ", ")) }
		end
	end
	rows[#rows + 1] = { "choice", "Recipe book", "What to craft for every skill range, where the recipes and trainers are", function()
		Panels.OpenRecipeBook(prof.key)
	end }
	rows[#rows + 1] = { "buttons", { { "Back", "default", function() if not Panels.Back() then Panels.Open("professions") end end }, { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Recipe book: a profession's leveling plan by skill range (Professions/
-- RecipeBook.lua), for any profession, known or not.
---------------------------------------------------------------------------

local book = { key = nil, path = nil, all = false }

-- The book has a window of its own (PathwiseRecipeBook): the panel's rows
-- in a frame that is not beside the guide. Drag it anywhere; it stays
-- there (recipebook.point) and Escape closes it. It is built like the panel
-- (build, render) with its own frames, swapped in while it is drawn.
ns.Defaults("recipebook", { point = nil })
local win -- { panel, scroll, host, pool }

local function swapIn(s)
	local before = { panel = panel, scroll = scroll, host = host, pool = pool, used = used }
	panel, scroll, host, pool, used = s.panel, s.scroll, s.host, s.pool, s.used
	return before
end

local function buildWindow()
	local fresh = {}
	for k in pairs(pool) do fresh[k] = {} end
	local main = swapIn({ pool = fresh })
	build("PathwiseRecipeBook")
	win = { panel = panel, scroll = scroll, host = host, pool = pool }
	swapIn(main)
	local f = win.panel
	f:SetFrameStrata("MEDIUM")
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, _, x, y = self:GetPoint(1)
		if p and x and y then ns.Set("recipebook.point", { p, math.floor(x + 0.5), math.floor(y + 0.5) }) end
	end)
	f.close:SetScript("OnClick", function() Panels.CloseRecipeBook() end)
	f.back:SetScript("OnClick", function() Panels.OpenRecipeBook(nil) end)
	local saved = ns.Get("recipebook.point")
	f:ClearAllPoints()
	if type(saved) == "table" then f:SetPoint(saved[1], UIParent, saved[1], saved[2], saved[3])
	else f:SetPoint("CENTER", UIParent, "CENTER", -200, 60) end
	if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "PathwiseRecipeBook") end
end

local function drawWindow()
	local rows = book.key and builders.recipebook() or builders.recipebooks()
	local main = swapIn(win)
	panel:SetScale(ns.Get("ui.scale") or 1)
	render(rows)
	win.used = used
	swapIn(main)
	win.panel.back:SetShown(book.key ~= nil)
end

-- Opens the window on a profession's book, or on the list with nil.
function Panels.OpenRecipeBook(key)
	if book.key ~= key then book.key, book.path, book.all = key, nil, false end
	if not win then buildWindow() end
	win.scroll:SetVerticalScroll(0)
	drawWindow()
	win.panel:Show()
end

function Panels.RefreshRecipeBook()
	if win and win.panel:IsShown() then drawWindow() end
end

function Panels.CloseRecipeBook()
	if win then win.panel:Hide() end
end

function Panels.RecipeBookShown() return win ~= nil and win.panel:IsShown() end

-- The arrow to an NPC; prints where it leads.
local function arrowTo(id, what)
	local p = ns.RecipeBook.Place(id)
	if not p then return ns.Print(("no position for %s in the data."):format(what or "them")) end
	ns.Nav.SetTarget(p.map, p.x, p.y, p.name)
	ns.Print(("the arrow leads to %s%s."):format(p.name, p.zone and (" in " .. p.zone) or ""))
end

local COLOR_WORD = { red = "can't learn yet", orange = "orange", yellow = "yellow", green = "green", grey = "grey" }

-- One step's rows: its crafts with reagents and colour, materials, where the
-- recipes come from; for gathering, the zones, nodes and mobs.
local function stepRows(rows, step, skill, side, full)
	local RB = ns.RecipeBook
	local entries = RB.Entries(step, side)
	local anyShown
	for _, e in ipairs(entries) do
		local lead = (e.kind == "alt" and "or " or (e.kind == "any" and (anyShown and "or " or "one of: ") or ""))
		if e.kind == "any" then anyShown = true end
		local bits = { RB.ReagentText(e.spell) }
		local col = skill and RB.Color(e.spell, skill)
		if full or e.kind ~= "alt" then bits[#bits + 1] = RB.ColorText(e.spell) end
		if col then bits[#bits + 1] = "now " .. COLOR_WORD[col] end
		rows[#rows + 1] = { "text", lead .. RB.EntryText(e), e.kind == "alt" and "text2" or "text" }
		rows[#rows + 1] = { "text", table.concat(bits, "  ·  "), "muted" }
		if full then
			for _, src in ipairs(RB.Sources(e.spell, side)) do
				local first = src.vendors[1] or src.drops[1]
				local sub = RB.SourceText(src)
				if first then
					rows[#rows + 1] = { "choice", src.name, sub, function() arrowTo(first.id, first.name) end }
				else
					rows[#rows + 1] = { "text", ("%s: %s"):format(src.name, sub), "text2" }
				end
			end
		end
	end
	if full then
		local mats = RB.Materials(entries)
		if #mats > 0 then
			local bits = {}
			for _, m in ipairs(mats) do bits[#bits + 1] = ("%d %s"):format(m.count, m.name) end
			rows[#rows + 1] = { "text", "In all: " .. table.concat(bits, ", "), "text2" }
		end
	end
	if step.nodes then
		local bits = {}
		for _, n in ipairs(step.nodes) do bits[#bits + 1] = RB.ItemName(n) end
		rows[#rows + 1] = { "text", table.concat(bits, ", "), "text" }
	end
	if step.zones then
		local list = {}
		for _, k in ipairs({ side or "A", "AH" }) do
			for _, map in ipairs(step.zones[k] or {}) do list[#list + 1] = RB.ZoneName(map) end
		end
		if #list > 0 then rows[#rows + 1] = { "text", "Where: " .. table.concat(list, ", "), "text2" } end
	end
	if step.mobs and full then
		for _, id in ipairs(step.mobs) do
			local n = RB.Npc(id)
			if n then
				local lv = ns.Data.npcs[id]
				rows[#rows + 1] = { "choice", n.name, ("level %d-%d  ·  arrow to the nearest"):format(lv[2], lv[3]), function() arrowTo(id, n.name) end }
			end
		end
	end
	if step.keep and full then rows[#rows + 1] = { "text", step.keep, "accent" } end
end

function builders.recipebook()
	local RB, P = ns.RecipeBook, ns.Professions
	local prof = book.key and P.BY_KEY[book.key]
	local b = prof and RB.Book(prof.key)
	if not b then return builders.recipebooks() end
	local side = RB.Side()
	local rank, cap = ns.Compat.SkillRank(prof.line)
	local rows = { { "heading", "Recipe book" } }
	rows[#rows + 1] = { "title", rank and ("%s   %d / %d"):format(prof.name, rank, cap or 0) or prof.name }
	local paths = RB.Paths(b)
	if #paths > 0 then
		local opts = { { "Main", function() book.path = nil Panels.RefreshRecipeBook() end, not book.path and "accent" or nil } }
		for _, p in ipairs(paths) do
			opts[#opts + 1] = { p, function() book.path = p Panels.RefreshRecipeBook() end, book.path == p and "accent" or nil }
		end
		rows[#rows + 1] = { "setting", "Way", book.path or "Main", opts }
	end

	-- Next rank to train.
	local nr = rank and RB.NextRank(b, cap)
	if nr and nr.rank ~= "Apprentice" then
		rows[#rows + 1] = { "heading", "Next rank" }
		rows[#rows + 1] = { "text", RB.RankText(nr), "text" }
		if nr.book then rows[#rows + 1] = { "text", "Learned from the book " .. RB.ItemName(nr.book) .. ", sold by:", "text2" } end
		if nr.quest then rows[#rows + 1] = { "text", "Learned from the quest " .. nr.quest .. ", given by:", "text2" } end
		for _, p in ipairs(RB.People(nr, side)) do
			local zone
			for map in pairs(p.npc and p.npc.spawns or {}) do zone = ns.Compat.MapName(map) break end
			if p.id then
				rows[#rows + 1] = { "choice", p.name, (zone and (zone .. "  ·  ") or "") .. "click for the arrow", function() arrowTo(p.id, p.name) end }
			else
				rows[#rows + 1] = { "text", p.name, "text2" }
			end
		end
		if nr.needs then
			local bits = {}
			for _, it in ipairs(nr.needs) do bits[#bits + 1] = RB.ItemName(it) end
			rows[#rows + 1] = { "text", "Needs: " .. table.concat(bits, ", "), "text2" }
		end
		if nr.note then rows[#rows + 1] = { "text", nr.note, "muted" } end
	elseif not rank then
		local first = b.ranks[1]
		rows[#rows + 1] = { "text", "You don't have this profession. Its trainers:", "text2" }
		local people = RB.People(first, side)
		for i, p in ipairs(people) do
			if i > 6 then break end
			if p.id then rows[#rows + 1] = { "choice", p.name, "click for the arrow", function() arrowTo(p.id, p.name) end } end
		end
		if first.note then rows[#rows + 1] = { "text", first.note, "muted" } end
	end

	-- The step for your skill, then the plan.
	local steps = RB.Steps(b, book.path, side)
	local now = RB.At(steps, rank or 0)
	if now then
		local s = steps[now]
		rows[#rows + 1] = { "heading", ("Now: %d-%d"):format(s.from, s.to) }
		stepRows(rows, s, rank, side, true)
	elseif rank then
		rows[#rows + 1] = { "text", "Your skill is past the end of the plan.", "success" }
	end
	rows[#rows + 1] = { "heading", book.all and "Every step" or "Coming up" }
	local shown = 0
	for i, s in ipairs(steps) do
		if i ~= now and (book.all or (now and i > now and shown < 3) or (not now and not rank and shown < 3)) then
			shown = shown + 1
			rows[#rows + 1] = { "text", ("%d-%d"):format(s.from, s.to), "accent" }
			stepRows(rows, s, rank, side, book.all)
		end
	end
	rows[#rows + 1] = { "choice", book.all and "Show fewer steps" or "Show every step",
		book.all and nil or "With recipe sources, materials and the other recipes", function()
			book.all = not book.all
			Panels.RefreshRecipeBook()
		end }

	if book.all then
		if b.extra then
			rows[#rows + 1] = { "heading", "Other recipes" }
			rows[#rows + 1] = { "text", "Drops, reputation and vendor recipes the guide lists for the late ranges.", "muted" }
			for _, id in ipairs(b.extra) do
				local sp = RB.Spell(id)
				if sp then
					rows[#rows + 1] = { "text", sp.name, "text" }
					local srcs = RB.Sources(sp, side)
					local where = srcs[1] and RB.SourceText(srcs[1]) or nil
					rows[#rows + 1] = { "text", RB.ReagentText(sp) .. "  ·  " .. RB.ColorText(sp) .. (where and ("  ·  " .. where) or ""), "muted" }
				end
			end
		end
		if b.tools or b.bonuses then rows[#rows + 1] = { "heading", "Tools and bonuses" } end
		if b.tools then
			local bits = {}
			for _, it in ipairs(b.tools) do bits[#bits + 1] = RB.ItemName(it) end
			rows[#rows + 1] = { "text", "Carry: " .. table.concat(bits, ", "), "text2" }
		end
		for _, x in ipairs(b.bonuses or {}) do
			local name = x.name or (x.item and RB.ItemName(x.item)) or "?"
			rows[#rows + 1] = { "text", name .. (x.amount and ("  ·  +%d"):format(x.amount) or "") .. (x.note and ("  ·  " .. x.note) or ""), "text2" }
		end
		for _, r in ipairs(b.ranks) do
			if r.rank ~= "Apprentice" then
				rows[#rows + 1] = { "text", RB.RankText(r), "text2" }
			end
		end
	end
	for _, n in ipairs(b.notes or {}) do rows[#rows + 1] = { "text", n, "muted" } end
	local src = "From wow-professions.com's Forever guide, written on the beta"
	if b.untestedFrom then src = src .. (", not tested there from %d"):format(b.untestedFrom) end
	rows[#rows + 1] = { "text", src .. ". Recipes, colours and materials: the Forever client's own data; green is an estimate.", "muted" }
	rows[#rows + 1] = { "buttons", { { "All professions", "default", function() Panels.OpenRecipeBook(nil) end }, { "Close", "default", function() Panels.CloseRecipeBook() end } } }
	return rows
end

-- Every profession's recipe book.
function builders.recipebooks()
	local RB, P = ns.RecipeBook, ns.Professions
	local rows = { { "heading", "Recipe books" }, { "text", "What to craft or gather for every skill range, for every profession.", "muted" } }
	for _, prof in ipairs(P.LIST) do
		if RB.Book(prof.key) then
			local rank, cap = ns.Compat.SkillRank(prof.line)
			rows[#rows + 1] = { "choice", rank and ("%s   %d / %d"):format(prof.name, rank, cap or 0) or prof.name, nil, function() Panels.OpenRecipeBook(prof.key) end }
		end
	end
	rows[#rows + 1] = { "buttons", { { "Close", "default", function() Panels.CloseRecipeBook() end } } }
	return rows
end

---------------------------------------------------------------------------
-- Dungeons for your level, and one dungeon's page
---------------------------------------------------------------------------

local dungeonId -- the dungeon whose page is open
local showAllDungeons = false

local STATUS = {
	now = "Take it now", log = "In your quest log", ready = "Ready to hand in",
	level = "From level %d", pre = "Needs another quest first", done = "Done",
}

function builders.dungeons()
	local Dg, Q = ns.Dungeons, ns.Quests
	local p = Q.Player()
	local list = showAllDungeons and Dg.All() or Dg.ForLevel(p.level or 1)
	local rows = { { "heading", showAllDungeons and "Every dungeon and raid" or ("Dungeons for level %d"):format(p.level or 1) } }
	if #list == 0 then rows[#rows + 1] = { "text", "None for your level yet: the first dungeons start in the low teens." } end
	for _, d in ipairs(list) do
		local open = 0
		for _, q in ipairs(Dg.Quests(d.id)) do if q.status == "now" or q.status == "log" or q.status == "ready" then open = open + 1 end end
		local e = Dg.Entrance(d.id)
		local where = e and ns.Compat.MapName(e.map) or nil
		local bits = {}
		if d.raid then bits[#bits + 1] = "Raid" end
		if where then bits[#bits + 1] = where end
		if open > 0 then bits[#bits + 1] = ("%d quest%s for you"):format(open, open == 1 and "" or "s") end
		rows[#rows + 1] = { "choice", ("%s   %d-%d"):format(d.name, d.low, d.high), #bits > 0 and table.concat(bits, "  ·  ") or nil, function()
			dungeonId = d.id
			Panels.Open("dungeon")
		end }
	end
	rows[#rows + 1] = { "choice", showAllDungeons and "Show dungeons for my level" or "Show every dungeon and raid", nil, function()
		showAllDungeons = not showAllDungeons
		Panels.Refresh()
	end }
	rows[#rows + 1] = { "text", "Levels are those of the monsters inside, from QuestieDB's data: an estimate.", "muted" }
	rows[#rows + 1] = { "buttons", { { "Close", "default", Panels.Close } } }
	return rows
end

function builders.dungeon()
	local Dg = ns.Dungeons
	local d = dungeonId and Dg.Get(dungeonId)
	if not d then return builders.dungeons() end
	local rows = {
		{ "heading", d.raid and "Raid" or "Dungeon" },
		{ "title", d.name },
		{ "text", ("Levels %d-%d%s"):format(d.low, d.high, d.levelsFrom == "quests" and " (from its quests)" or "") },
	}
	local e = Dg.Entrance(d.id)
	if e then
		local zone = ns.Compat.MapName(e.map) or ("map " .. e.map)
		rows[#rows + 1] = { "choice", "Go to the entrance", ("%s  ·  %.1f, %.1f%s"):format(zone, e.x, e.y,
			e.unverified and "  ·  not yet checked on Forever" or ""), function()
			Dg.GuideTo(d.id)
			ns.Print(("the arrow leads to %s."):format(d.name))
		end }
	end
	local quests = Dg.Quests(d.id)
	rows[#rows + 1] = { "heading", ("Quests (%d)"):format(#quests) }
	if #quests == 0 then rows[#rows + 1] = { "text", "No quests for your character here." } end
	for _, q in ipairs(quests) do
		local status = q.status == "level" and STATUS.level:format(q.minLevel) or STATUS[q.status]
		local giver = q.giver and q.giver.name
		local sub = ("Level %d  ·  %s%s"):format(q.level, status, giver and q.status ~= "done" and ("  ·  " .. giver) or "")
		rows[#rows + 1] = { "choice", q.name, sub, function()
			if q.giver and q.status ~= "done" then
				ns.Nav.SetTarget(q.giver.map, q.giver.x, q.giver.y, q.giver.name)
				ns.Print(("the arrow leads to %s for %s."):format(q.giver.name, q.name))
			end
		end }
	end
	rows[#rows + 1] = { "buttons", { { "All dungeons", "default", function() Panels.Open("dungeons") end }, { "Close", "default", Panels.Close } } }
	return rows
end

---------------------------------------------------------------------------
-- Waypoint & tools: a waypoint by coordinates, where you are, debug text
---------------------------------------------------------------------------

function builders.tools()
	local C, Nav = ns.Compat, ns.Nav
	local map, x, y = C.PlayerMapPosition()
	local t = Nav.Target()
	return {
		{ "heading", "Waypoint & tools" },
		{ "text", map and ("You are at %.1f, %.1f  ·  %s"):format(x, y, C.MapName(map) or ("map " .. map)) or "No map position here (inside an instance?).", "text" },
		{ "heading", "Set a waypoint on this map" },
		{ "coords", function(wx, wy)
			if not (wx and wy) or wx > 100 or wy > 100 then
				ns.Print("type two numbers from 0 to 100, like 45.2 and 61.8.")
				return
			end
			local here = C.PlayerMapPosition()
			if not here then
				ns.Print("no map position here (inside an instance?).")
				return
			end
			Nav.SetTarget(here, wx, wy, ("%.1f, %.1f"):format(wx, wy))
			Panels.Refresh()
		end, function()
			Nav.Clear()
			Panels.Refresh()
		end },
		{ "text", t and ("The arrow leads to %s."):format(t.title or "a waypoint") or "No waypoint set.", "muted" },
		{ "heading", "For bug reports" },
		{ "text", "What the arrow sees. Click, Ctrl+C, and paste it with a report." },
		{ "copy", Nav.DebugText(), 6 },
		{ "buttons", { { "Report this step", "default", function() Panels.Open("report") end }, { "Close", "default", Panels.Close } } },
	}
end

---------------------------------------------------------------------------
-- Report this step, and About
---------------------------------------------------------------------------

-- The game opens no links: these are copy boxes, for the player's browser.
local DISCORD = "https://discord.gg/hSDjBrG8EK"
local WEBSITE = "https://pathwise.quest"
local REPORT_URL = WEBSITE .. "/report"
Panels.DISCORD, Panels.WEBSITE, Panels.REPORT_URL = DISCORD, WEBSITE, REPORT_URL

function builders.report()
	local text = ns.Engine.ReportText()
	local n = 1
	for _ in text:gmatch("\n") do n = n + 1 end
	return {
		{ "heading", "Report this step" },
		{ "text", "Click the box, press Ctrl+C, and paste it into a bug report with a line on what went wrong. Nothing is sent from the game." },
		{ "copy", text, math.min(16, n + 1) },
		{ "heading", "On the website" },
		{ "text", "Copy the link and open it in your browser. Log in with Discord, then paste the report into the form.", "muted" },
		{ "copy", REPORT_URL, 1 },
		{ "heading", "Or on Discord" },
		{ "text", "Paste it in #report-a-bug. Not in the server yet? Copy the invite.", "muted" },
		{ "copy", DISCORD, 1 },
		{ "buttons", { { "Close", "default", Panels.Close } } },
	}
end

function builders.about()
	local Q = ns.Quests
	return {
		{ "icon", 40 },
		{ "title", "Pathwise" },
		{ "text", "Every quest. Every craft. Every level.", "accent" },
		{ "text", ("Version %s"):format(ns.VERSION) },
		{ "text", "Created by leight_nn & florp", "text" },
		{ "text", "_nn", "muted" },
		{ "divider" },
		{ "heading", "Thanks" },
		{ "text", "Routes adapted from Polestar by the Polestar authors (GPL-3.0)." },
		{ "text", "Quest data from QuestieDB by the Questie team and contributors." },
		{ "text", "Typeface: Inter by Rasmus Andersson (SIL Open Font License)." },
		{ "text", ("Data: %s"):format(tostring(Q.Data.SOURCE)), "muted" },
		{ "heading", "Licence" },
		{ "text", "Free and open source under the GNU General Public License, version 3." },
		{ "heading", "Website" },
		{ "text", "Known issues, suggestions and bug reports. Copy the link and open it in your browser.", "muted" },
		{ "copy", WEBSITE, 1 },
		{ "heading", "Discord" },
		{ "copy", DISCORD, 1 },
		{ "buttons", { { "Close", "default", Panels.Close } } },
	}
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

-- The leveling tracker: this session's pace and every level's time.
function builders.leveling()
	local K = ns.Tracker
	local s = K.Stats()
	local rows = {
		{ "heading", "Leveling" },
		{ "heading", "This session" },
		{ "setting", "XP gained", tostring(s.gained), {} },
		{ "setting", "XP per hour", s.xpPerHour and ("%d"):format(s.xpPerHour) or "after a minute", {} },
		{ "setting", "To the next level", s.secondsToLevel and K.Duration(s.secondsToLevel) or "-", {} },
		{ "setting", "Rested XP", tostring(s.rested), {} },
		{ "setting", "At this level", K.Duration(s.levelSeconds), {} },
		{ "heading", "Time per level" },
	}
	local levels = K.Levels()
	if #levels == 0 then
		rows[#rows + 1] = { "text", "Each level's time shows here once you reach the next one with Pathwise on.", "muted" }
	end
	local total = 0
	for _, l in ipairs(levels) do
		total = total + l.seconds
		rows[#rows + 1] = { "setting", ("Level %d"):format(l.level), K.Duration(l.seconds), {} }
	end
	if #levels > 1 then rows[#rows + 1] = { "setting", "In all", K.Duration(total), {} } end
	rows[#rows + 1] = { "text", "Counted while you play with Pathwise on; /played sets the current level right.", "muted" }
	rows[#rows + 1] = { "divider" }
	rows[#rows + 1] = { "setting", "Start again", "", { { "Clear", function() K.Reset() Panels.Refresh() end } } }
	return rows
end

function builders.settings()
	local E = ns.Engine
	local route = E.Route()
	local skippedN = #E.Skipped()
	local rows = {
		{ "heading", "Settings" },
		{ "heading", "Guide window" },
		{ "slider", "Window size", "ui.scale", 0.5, 1.5, 0.05, pct },
		{ "slider", "Background opacity", "ui.opacity", 0.4, 1, 0.05, pct },
		{ "setting", "Compact mode", onOff(ns.Get("guide.compact")), { { ns.Get("guide.compact") and "Turn off" or "Turn on", toggle("guide.compact") } } },
		{ "slider", "Steps listed", "guide.ahead", 1, 12, 1, function(v) return ("%d"):format(v) end, "count" },
		{ "setting", "Quest item button", onOff(ns.Get("itemButton.shown")), { { ns.Get("itemButton.shown") and "Hide" or "Show", toggle("itemButton.shown") } } },
		{ "text", "The item the step wants used, beside the guide. Shift-drag it to move; a key for it is in Key Bindings > Pathwise.", "muted" },
		{ "setting", "Leveling tracker", onOff(ns.Get("tracker.shown")), { { ns.Get("tracker.shown") and "Hide" or "Show", toggle("tracker.shown") }, { "Times", function() Panels.Open("leveling") end } } },
		{ "heading", "Automation" },
		{ "text", "Only for what the route asks. Hold Shift when you talk to someone to do it yourself.", "muted" },
		{ "setting", "Accept and hand in quests", onOff(ns.Get("auto.quests")), { { ns.Get("auto.quests") and "Turn off" or "Turn on", toggle("auto.quests") } } },
		{ "setting", "Pick rewards", onOff(ns.Get("auto.rewards")), { { ns.Get("auto.rewards") and "Turn off" or "Turn on", toggle("auto.rewards") } } },
		{ "text", "With a choice of rewards, take the one Pathwise Gear recommends (Gear needed). A single reward is always taken.", "muted" },
		{ "setting", "Fly where the step says", onOff(ns.Get("auto.fly")), { { ns.Get("auto.fly") and "Turn off" or "Turn on", toggle("auto.fly") } } },
		{ "setting", "Set your hearthstone", onOff(ns.Get("auto.bind")), { { ns.Get("auto.bind") and "Turn off" or "Turn on", toggle("auto.bind") } } },
		{ "setting", "Train at trainers", onOff(ns.Get("auto.train")), { { ns.Get("auto.train") and "Turn off" or "Turn on", toggle("auto.train") } } },
		{ "text", "When the step is training: learns everything the trainer has that you can afford.", "muted" },
	}
	-- Colour: the accent, for Pathwise and (if chosen) the whole suite.
	local mode = ns.Get("ui.accentMode") or "pathwise"
	local function pickMode(v) return function() ns.Set("ui.accentMode", v) Panels.Refresh() end end
	rows[#rows + 1] = { "heading", "Colour" }
	rows[#rows + 1] = { "setting", "Accent", "", {
		{ "Pathwise", pickMode("pathwise"), mode == "pathwise" and "accent" or "default" },
		{ "Class", pickMode("class"), mode == "class" and "accent" or "default" },
		{ "Custom", pickMode("custom"), mode == "custom" and "accent" or "default" } } }
	if mode == "custom" then
		rows[#rows + 1] = { "text", ("Your colour: %s. Type another as #RRGGBB, then Apply."):format(ns.Get("ui.accentColor") or "#66D7FF") }
		rows[#rows + 1] = { "input", "ui.accentColor", 1 }
		rows[#rows + 1] = { "buttons", { { "Apply", "accent", function()
			local text = (Panels.InputText("ui.accentColor") or ""):gsub("%s", "")
			if not text:match("^#?%x%x%x%x%x%x$") then
				ns.Print("a colour is six hex digits, like #66D7FF.")
				return
			end
			if text:sub(1, 1) ~= "#" then text = "#" .. text end
			ns.Set("ui.accentColor", text:upper())
			Panels.ClearInput("ui.accentColor")
			Panels.Refresh()
		end } } }
	elseif mode == "class" then
		rows[#rows + 1] = { "text", "Your class colour, on every character its own.", "muted" }
	end
	rows[#rows + 1] = { "setting", "Whole suite in this colour", onOff(ns.Get("ui.accentSuite")), { { ns.Get("ui.accentSuite") and "Turn off" or "Turn on", toggle("ui.accentSuite") } } }
	rows[#rows + 1] = { "text", "On: Pathwise Gear, Bags and the rest use it instead of their own colours.", "muted" }
	rows[#rows + 1] = { "choice", "Reload now", "Windows already open take the new colour after a reload", function()
		if ReloadUI then ReloadUI() end
	end }
	for _, r in ipairs({
		{ "heading", "Waypoint arrow" },
		{ "setting", "Show the arrow", onOff(ns.Get("arrow.shown")), { { ns.Get("arrow.shown") and "Hide" or "Show", toggle("arrow.shown") } } },
		{ "slider", "Arrow size", "arrow.scale", 0.5, 2, 0.1, pct },
		{ "text", "Shift-drag the arrow to move it.", "muted" },
		{ "setting", "Minimap button", onOff(ns.Get("minimap.shown")), { { ns.Get("minimap.shown") and "Hide" or "Show", toggle("minimap.shown") } } },
		{ "text", ns.Get("minimap.shown") and "Click it to show the guide, right-click for settings, drag to move it."
			or "Without it, open Pathwise with a key: Game Menu > Key Bindings > Pathwise.", "muted" },
		{ "heading", "Map pins" },
		{ "setting", "On the world map", onOff(ns.Get("pins.map")), { { ns.Get("pins.map") and "Hide" or "Show", toggle("pins.map") } } },
		{ "setting", "On the minimap", onOff(ns.Get("pins.minimap")), { { ns.Get("pins.minimap") and "Hide" or "Show", toggle("pins.minimap") } } },
		{ "setting", "Dungeon entrances", onOff(ns.Get("pins.dungeons")), { { ns.Get("pins.dungeons") and "Hide" or "Show", toggle("pins.dungeons") } } },
		{ "setting", "Herbs and ore on the map", onOff(ns.Get("pins.gather")), { { ns.Get("pins.gather") and "Hide" or "Show", toggle("pins.gather") } } },
		{ "setting", "Herbs and ore on the minimap", onOff(ns.Get("pins.gatherMinimap")), { { ns.Get("pins.gatherMinimap") and "Hide" or "Show", toggle("pins.gatherMinimap") } } },
		{ "text", "For Herbalism and Mining: the nodes that still give you skill, in their colour.", "muted" },
		{ "setting", "Step numbers on the map", onOff(ns.Get("pins.stepNumbers")), { { ns.Get("pins.stepNumbers") and "Hide" or "Show", toggle("pins.stepNumbers") } } },
		{ "slider", "Steps numbered ahead", "pins.stepCount", 1, 20, 1, function(v) return ("%d"):format(v) end, "count" },
		{ "setting", "Quest markers on the map", onOff(ns.Get("pins.quests")), { { ns.Get("pins.quests") and "Hide" or "Show", toggle("pins.quests") } } },
		{ "setting", "Quest markers on the minimap", onOff(ns.Get("pins.questsMinimap")), { { ns.Get("pins.questsMinimap") and "Hide" or "Show", toggle("pins.questsMinimap") } } },
		{ "heading", "Route" },
		{ "setting", route and route.title or "No route", "", { { "Routes", function() Panels.Open("routes") end }, { "Zones", function() Panels.Open("zones") end } } },
		{ "setting", "Side guide", E.Side() and E.Side().title or "None", E.Side() and { { "Stop", function() E.SetSide(nil) Panels.Refresh() end } } or {} },
		{ "heading", "Profession detours" },
		{ "setting", "Mode", "", (function()
			local mode = ns.Get("professions.detour")
			local function pick(value) return function() ns.Set("professions.detour", value) E.Update() Panels.Refresh() end end
			return {
				{ "Speed", pick("speed"), mode == "speed" and "accent" or "default" },
				{ "Balanced", pick("balanced"), mode == "balanced" and "accent" or "default" },
				{ "Crafting", pick("craft"), mode == "craft" and "accent" or "default" },
			}
		end)() },
		{ "text", ({ speed = "Only when a profession step is right on your way (about 150 yd).",
			balanced = "When a profession step is near (about 600 yd).",
			craft = "Always: professions come first." })[ns.Get("professions.detour")] or "", "muted" },
		{ "setting", "Skipped quests", tostring(skippedN), skippedN > 0 and { { "Bring back", function()
			for _, q in ipairs(E.Skipped()) do E.State().skipped[q] = nil end
			E.Update()
			Panels.Refresh()
		end } } or {} },
		{ "setting", "Marked done by you", tostring(E.Marked()), E.Marked() > 0 and { { "Bring back", function()
			E.ClearMarked()
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
	}) do rows[#rows + 1] = r end
	-- The other Pathwise addons installed (Pathwise.Suite.RegisterModule).
	local mods = ns.Suite and ns.Suite.Modules() or {}
	if #mods > 0 then
		rows[#rows + 1] = { "heading", "Pathwise suite" }
		for _, m in ipairs(mods) do rows[#rows + 1] = { "choice", m.name, m.about, function() m.open() end } end
	end
	rows[#rows + 1] = { "choice", "Waypoint & tools", "Set a waypoint by coordinates; what the arrow sees", function() Panels.Open("tools") end }
	rows[#rows + 1] = { "choice", "About Pathwise", ("Version %s  ·  created by leight_nn & florp   _nn"):format(ns.VERSION), function() Panels.Open("about") end }
	return rows
end

ns.On("GUIDE_SKIP", function() Panels.Open("skip") end)
ns.On("SHOW_ZONES", function() Panels.Open("zones") end)
ns.On("SHOW_SETTINGS", function() Panels.Open("settings") end)
ns.On("SHOW_ROUTES", function() Panels.Open("routes") end)
ns.On("SHOW_PROFESSIONS", function() Panels.Open("professions") end)
ns.On("REPORT_STEP", function() Panels.Open("report") end)
ns.On("SHOW_DUNGEONS", function() Panels.Open("dungeons") end)
ns.On("SHOW_ABOUT", function() Panels.Open("about") end)
ns.On("GUIDE_UPDATED", function() if Panels.IsOpen("skip") or Panels.IsOpen("professions") or Panels.IsOpen("profession") then Panels.Refresh() end end)
ns.On("PROFESSIONS_CHANGED", function() if Panels.IsOpen("professions") or Panels.IsOpen("profession") then Panels.Refresh() end
	Panels.RefreshRecipeBook()
end)
ns.On("SETTING_CHANGED", function(path)
	if path == "guide.shown" and not ns.Get("guide.shown") then Panels.Close() end
end)
