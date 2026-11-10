-- Buffs and debuffs, and cast bars, for the unit frames.
--
-- Auras come from C_UnitAuras.GetAuraDataByIndex. Their icons always show
-- (Texture:SetTexture takes secret values); a stack count and the cooldown
-- spiral only when the numbers are readable, because Cooldown:SetCooldown
-- does not take secrets from addon code (Forever's API documentation).
-- Cast bars: UnitCastingInfo / UnitChannelInfo. The spell's name and icon
-- always show; the bar fills by time. When the times are secret (enemies'
-- casts), the cast's duration object (UnitCastingDuration /
-- UnitChannelDuration) gives the bar its length in seconds and, each frame,
-- the seconds gone (or left, for a channel): small numbers, so the bar moves
-- smoothly, and the game does the sums (SetMinMaxValues and SetValue take
-- secrets from addon code). Without one, the bar runs from the cast's start
-- to its end in milliseconds and is given the time now; a bar holds numbers
-- that big coarsely, so that way it moves in steps.
-- Combo points: GetComboPoints("player", "target"), as the game's own
-- ComboFrame on Forever, which this replaces on the target's frame.

local ADDON, ns = ...
local T = ns.Theme
local U = ns.Units
local readable = ns.Readable
local has = U.Has

local function call(fn, ...) if type(fn) ~= "function" then return nil end local ok, a, b, c, d, e, f, g, h, i = pcall(fn, ...) if ok then return a, b, c, d, e, f, g, h, i end end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------

-- opts = { filter = "HELPFUL" | "HARMFUL", count, size, grow = "RIGHT" | "LEFT", at = "BELOW" | "RIGHT" }
-- One row of aura icons.
local function makeRow(f, opts)
	local row = { opts = opts, icons = {} }
	local size = opts.size or 22
	for i = 1, opts.count or 8 do
		local b = CreateFrame("Button", nil, f)
		b:SetSize(size, size)
		T.Panel(b, "bg", "border", 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		local ok, cd = pcall(CreateFrame, "Cooldown", nil, b, "CooldownFrameTemplate")
		if ok and cd then
			cd:SetAllPoints(b.icon)
			if cd.SetDrawEdge then cd:SetDrawEdge(false) end
			if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
			b.cd = cd
		end
		b.count = T.Text(b, "small", "text", "OVERLAY")
		b.count:SetPoint("BOTTOMRIGHT", -1, 1)
		b.count:SetShadowOffset(1, -1)
		b:SetScript("OnEnter", function(self)
			if not (GameTooltip and self.auraID) then return end
			GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
			local fn = opts.filter:find("HARMFUL") and GameTooltip.SetUnitDebuffByAuraInstanceID or GameTooltip.SetUnitBuffByAuraInstanceID
			if fn then pcall(fn, GameTooltip, f.unit, self.auraID, self.filter) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
		b:Hide()
		row.icons[i] = b
	end
	return row
end

-- f.auras: the debuffs (or the frame's one row); f.buffs: a row of buffs
-- over them, when the frame has one (the target's).
function U.MakeAuras(f, opts, buffs)
	f.auras = makeRow(f, opts)
	if buffs then f.buffs = makeRow(f, buffs) end
	U.PlaceAuras(f)
end

local function placeRow(f, row, below)
	local o = row.opts
	local size, gap = o.size or 22, 3
	for i, b in ipairs(row.icons) do
		b:ClearAllPoints()
		local step = (i - 1) * (size + gap)
		if o.at == "RIGHT" then
			b:SetPoint("LEFT", f, "RIGHT", 4 + step, 0)
		elseif o.grow == "LEFT" then
			b:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -step, below)
		else
			b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", step, below)
		end
	end
end

function U.PlaceAuras(f)
	if not f.auras then return end
	local below = (f.castbar and not f.castbar.pwAway) and -24 or -4 -- under the cast bar when there is one
	if f.buffs then
		placeRow(f, f.buffs, below)
		-- The debuffs under the buffs, or in their place when there are none.
		if f.buffs.n and f.buffs.n > 0 then below = below - (f.buffs.opts.size or 22) - 3 end
	end
	placeRow(f, f.auras, below)
end

-- The debuff border color by dispel type (Magic blue, Curse purple...).
local DISPEL = { Magic = "magic", Curse = "curse", Disease = "disease", Poison = "poison" }

local function updateRow(f, a)
	local on = ns.Get("units.auras")
	local shown = 0
	local filter = a.opts.filter
	if filter == "HARMFUL" and ns.Get("units.onlyMyDebuffs") and f.unit ~= "player" then filter = "HARMFUL|PLAYER" end
	-- Debuffs flagged for nameplates only (bleeds, taunts...) too: without
	-- this the game leaves them out. Its own target frame asks the same way
	-- (TargetFrameAuraShared: Harmful + IncludeNameplateOnly).
	if filter:find("^HARMFUL") and not filter:find("INCLUDE_NAME_PLATE_ONLY", 1, true) then
		filter = filter .. "|INCLUDE_NAME_PLATE_ONLY"
	end
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	for i, b in ipairs(a.icons) do
		local data = on and get and call(get, f.unit, i, filter)
		if type(data) == "table" then
			b.icon:SetTexture(data.icon)
			b.auraID, b.filter = data.auraInstanceID, filter
			local n = readable(data.applications)
			b.count:SetText((type(n) == "number" and n > 1) and n or "")
			local dur, exp = readable(data.duration), readable(data.expirationTime)
			if b.cd then
				if type(dur) == "number" and type(exp) == "number" and dur > 0 then
					pcall(b.cd.SetCooldown, b.cd, exp - dur, dur)
					b.cd:Show()
				else
					b.cd:Hide()
				end
			end
			local c = a.opts.filter:find("HARMFUL") and DISPEL[readable(data.dispelName) or ""] or nil
			-- In a fight the aura's ID is secret and can't be compared (an
			-- error there left the row empty): the icon just shows.
			local id = readable(data.auraInstanceID)
			if id == nil then
				b.pwAura = nil
				ns.Anim.Set(b, "alpha", 1)
				b:SetAlpha(1)
			elseif b.pwAura ~= id then
				-- A new aura in this slot: it fades in.
				b.pwAura = id
				if not b:IsShown() then ns.Anim.Set(b, "alpha", 0) b:SetAlpha(0) end
				ns.Anim.Fade(b, 1, ns.Anim.NORMAL)
			end
			T.SetBorder(b, c or "border")
			b:Show()
			shown = shown + 1
		else
			b.auraID, b.pwAura = nil, nil
			b:Hide()
		end
	end
	return shown
end

-- /pwui auras: what the game gives Pathwise UI for your target's debuffs.
-- Typed in a fight it shows whether the reads are refused, secret or empty.
function U.ReportAuras()
	local fight = (InCombatLockdown and InCombatLockdown()) and "in a fight" or "out of a fight"
	local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	local filter = "HARMFUL|INCLUDE_NAME_PLATE_ONLY"
	local state
	if not get then state = "no aura API"
	elseif not (UnitExists and UnitExists("target")) then state = "no target"
	else
		local n, secret = 0, false
		for i = 1, 40 do
			local ok, d = pcall(get, "target", i, filter)
			if not ok then state = "refused (" .. tostring(d):sub(1, 60) .. ")" break end
			if type(d) ~= "table" then break end
			n = n + 1
			if readable(d.auraInstanceID) == nil then secret = true end
		end
		state = state or (n .. " debuff(s)" .. (secret and ", secret" or ""))
	end
	local f = U.frames and U.frames.target
	local shown = 0
	if f and f.auras then for _, b in ipairs(f.auras.icons) do if b:IsShown() then shown = shown + 1 end end end
	ns.Print(("target debuffs, %s: the game gives %s; the frame shows %d."):format(fight, state, shown))
end
ns.Commands.auras = function() U.ReportAuras() end

function U.UpdateAuras(f)
	if not f.auras then return end
	if f.buffs then
		local n = updateRow(f, f.buffs)
		local moved = (n > 0) ~= ((f.buffs.n or 0) > 0)
		f.buffs.n = n
		if moved then U.PlaceAuras(f) end
	end
	updateRow(f, f.auras)
end

---------------------------------------------------------------------------
-- Cast bars
---------------------------------------------------------------------------

function U.MakeCastbar(f)
	local cb = CreateFrame("StatusBar", nil, f)
	cb:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
	cb:SetHeight(16)
	cb:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 18, -4)
	cb:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -4)
	T.Panel(cb, "bg", "border", 0.9)
	cb.icon = cb:CreateTexture(nil, "ARTWORK")
	cb.icon:SetSize(16, 16)
	cb.icon:SetPoint("RIGHT", cb, "LEFT", -2, 0)
	cb.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	cb.text = T.BarText(T.Text(cb, "small", "text", "OVERLAY"), "small")
	T.Sheen(cb)
	cb.text:SetPoint("LEFT", 4, 0)
	cb.text:SetJustifyV("MIDDLE")
	cb.text:SetWordWrap(false)
	-- Behind the fill, for a channel with secret times: the cast's color,
	-- which the fill (in the ground's color) covers from the right as time
	-- passes, so it drains as a channel does.
	cb.track = cb:CreateTexture(nil, "BACKGROUND", nil, 2)
	cb.track:SetPoint("TOPLEFT", 1, -1)
	cb.track:SetPoint("BOTTOMRIGHT", -1, 1)
	cb.track:Hide()
	cb:SetMinMaxValues(0, 1)
	cb:Hide()
	cb:SetScript("OnUpdate", function(self)
		if self.pwEnding then return end
		if self.pwDur then
			local d = self.pwDur
			local ok, v = pcall(self.channel and d.GetRemainingDuration or d.GetElapsedDuration, d)
			if ok and v ~= nil then self:SetValue(v) end
			return
		end
		if self.pwSecret then self:SetValue((GetTime and GetTime() or 0) * 1000) return end
		if not (self.start and self.finish) then return end
		local now = (GetTime and GetTime() or 0) * 1000
		local p = (now - self.start) / math.max(1, self.finish - self.start)
		if p >= 1 then U.EndCast(f, false) return end
		self:SetValue(self.channel and (1 - p) or p)
	end)
	f.castbar = cb
	-- Cast bars under frames with auras below them push the auras down.
	if f.auras then U.PlaceAuras(f) end
end

function U.UpdateCast(f)
	local cb = f.castbar
	if not cb then return end
	if not ns.Get("units.castbars") or (f.unit == "player" and ns.Get("units.castbarSpot") == "game") then cb:Hide() return end
	local name, _, texture, startMS, endMS, _, _, notInterruptible = call(UnitCastingInfo, f.unit)
	local channel = false
	if not has(name) then
		name, _, texture, startMS, endMS, _, notInterruptible = call(UnitChannelInfo, f.unit)
		channel = true
	end
	if not has(name) then U.EndCast(f, f.pwInterrupted) f.pwInterrupted = nil return end
	cb.pwEnding = false
	ns.Anim.Set(cb, "alpha", 1)
	cb:SetAlpha(1)
	cb.text:SetText(name)
	if has(texture) then cb.icon:SetTexture(texture) end
	local s, e = readable(startMS), readable(endMS)
	local drain = false
	if type(s) == "number" and type(e) == "number" then
		U.PlainCastRange(cb)
		cb.start, cb.finish, cb.channel = s, e, channel
	elseif U.CastDuration(cb, f.unit, channel) then
		-- Secret times: 0 to the cast's length in seconds, filled by the
		-- seconds gone, or drained by the seconds left for a channel.
		cb.start, cb.finish, cb.channel = nil, nil, channel
		local d = cb.pwDur
		local ok, v = pcall(channel and d.GetRemainingDuration or d.GetElapsedDuration, d)
		cb:SetValue(ok and v or 0)
	elseif has(startMS) and has(endMS) and pcall(cb.SetMinMaxValues, cb, startMS, endMS) then
		-- Secret times: the range is the cast, the value the time now.
		cb.start, cb.finish, cb.channel = nil, nil, channel
		cb.pwSecret = true
		drain = channel and pcall(cb.SetFillStyle, cb, "REVERSE") or false
		cb:SetValue((GetTime and GetTime() or 0) * 1000)
	else
		U.PlainCastRange(cb)
		cb.start, cb.finish = nil, nil
		cb:SetValue(1)
	end
	local locked = readable(notInterruptible)
	local c = locked and T.Color("muted") or T.Color("accent")
	if drain then
		cb.track:SetColorTexture(c[1], c[2], c[3], 1)
		cb.track:Show()
		local g = T.Color("bg")
		cb:SetStatusBarColor(g[1], g[2], g[3])
	else
		cb.track:Hide()
		cb:SetStatusBarColor(c[1], c[2], c[3])
	end
	cb:Show()
end

-- The cast's duration object, when the game gives one: the bar then runs
-- from 0 to the cast's length in seconds. True when it was set up so.
function U.CastDuration(cb, unit, channel)
	local dur = call(channel and UnitChannelDuration or UnitCastingDuration, unit)
	if dur == nil then return false end
	local ok, total = pcall(function() return dur:GetTotalDuration() end)
	if not (ok and has(total)) then return false end
	U.PlainCastRange(cb)
	if not pcall(cb.SetMinMaxValues, cb, 0, total) then return false end
	cb.pwDur, cb.pwSecret = dur, true
	return true
end

-- Back to a 0-1 bar filled from the left (after a cast with secret times).
function U.PlainCastRange(cb)
	cb.pwDur = nil
	if cb.pwSecret then
		cb.pwSecret = nil
		cb:SetMinMaxValues(0, 1)
		pcall(cb.SetFillStyle, cb, "STANDARD")
	end
	cb.track:Hide()
end

-- A cast that ends: the bar fills (done) or turns red (interrupted), then
-- fades out instead of vanishing.
function U.EndCast(f, interrupted)
	local cb = f.castbar
	if not cb or not cb:IsShown() or cb.pwEnding then
		if cb and not cb:IsShown() then cb.start, cb.finish = nil, nil end
		return
	end
	cb.pwEnding = true
	cb.start, cb.finish = nil, nil
	U.PlainCastRange(cb)
	if interrupted then
		local e = T.Color("error")
		cb:SetStatusBarColor(e[1], e[2], e[3])
		cb.text:SetText("Interrupted")
	end
	cb:SetValue(1)
	ns.Anim.Fade(cb, 0, interrupted and 0.6 or ns.Anim.SLOW, function()
		if cb.pwEnding then cb:Hide() cb.pwEnding = false end
	end)
end

---------------------------------------------------------------------------
-- Combo points
---------------------------------------------------------------------------

-- On Forever your combo points are on your target (the game's ComboFrame
-- and TargetBoundComboPointBar read GetComboPoints("player", "target")).
-- A row of pips over the right of the target's frame, for rogues and for
-- druids in cat form. Each pip is a tiny bar over one point (pip 3 runs from
-- 2 to 3), so a secret count fills them too: SetValue takes it as it is.
local MAX_PIPS = 7
local COMBO = Enum and Enum.PowerType and Enum.PowerType.ComboPoints or 4
local PIP_W, PIP_H, PIP_GAP = 16, 6, 3

function U.MakeCombo(f)
	local row = CreateFrame("Frame", nil, f)
	row:SetHeight(PIP_H)
	row:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", 0, 4)
	row.pips = {}
	for i = 1, MAX_PIPS do
		local p = CreateFrame("StatusBar", nil, row)
		p:SetSize(PIP_W, PIP_H)
		p:SetPoint("LEFT", row, "LEFT", (i - 1) * (PIP_W + PIP_GAP), 0)
		p:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
		local bg = p:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetColorTexture(0, 0, 0, 0.5)
		p.bg = bg
		p:SetMinMaxValues(i - 1, i)
		p:SetValue(0)
		row.pips[i] = p
	end
	row:Hide()
	f.combo = row
end

-- Rogues always; druids while their power is energy (cat form). When the
-- game keeps that hidden, the pips show.
function U.WantsCombo()
	if not ns.Get("units.comboPoints") then return false end
	local _, class = call(UnitClass, "player")
	class = readable(class)
	if class == "ROGUE" then return true end
	if class ~= "DRUID" then return false end
	local _, token = call(UnitPowerType, "player")
	token = readable(token)
	return token == nil or token == "ENERGY"
end

function U.UpdateCombo(f)
	local row = f.combo
	if not row then return end
	local n = U.WantsCombo() and call(GetComboPoints, "player", "target") or nil
	if n == nil then row:Hide() return end
	local most = readable(call(UnitPowerMax, "player", COMBO))
	if type(most) ~= "number" or most < 1 then most = 5 end
	most = math.min(most, MAX_PIPS)
	row:SetWidth(most * (PIP_W + PIP_GAP) - PIP_GAP)
	local c = T.Color("accent")
	for i, p in ipairs(row.pips) do
		if i <= most then
			p:SetStatusBarColor(c[1], c[2], c[3])
			p:SetValue(n)
			p:Show()
		else
			p:Hide()
		end
	end
	row:Show()
end

local function comboChanged()
	local f = U.frames and U.frames.target
	if f and f.combo then U.UpdateCombo(f) end
end
ns.RegisterEvent("COMBO_TARGET_CHANGED", comboChanged)
ns.RegisterEvent("UNIT_POWER_UPDATE", function(_, unit) if unit == "player" then comboChanged() end end)
ns.RegisterEvent("UNIT_POWER_FREQUENT", function(_, unit, kind) if unit == "player" and kind == "COMBO_POINTS" then comboChanged() end end)
ns.RegisterEvent("UNIT_MAXPOWER", function(_, unit) if unit == "player" then comboChanged() end end)
ns.RegisterEvent("UNIT_DISPLAYPOWER", function(_, unit) if unit == "player" then comboChanged() end end) -- into or out of cat form
