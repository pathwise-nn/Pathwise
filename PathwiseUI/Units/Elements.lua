-- Buffs and debuffs, and cast bars, for the unit frames.
--
-- Auras come from C_UnitAuras.GetAuraDataByIndex. Their icons always show
-- (Texture:SetTexture takes secret values); a stack count and the cooldown
-- spiral only when the numbers are readable, because Cooldown:SetCooldown
-- does not take secrets from addon code (Forever's API documentation).
-- Cast bars: UnitCastingInfo / UnitChannelInfo. The spell's name and icon
-- always show; the bar fills by time when the times are readable, else it
-- stays full while the cast lasts.

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
function U.MakeAuras(f, opts)
	f.auras = { opts = opts, icons = {} }
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
		f.auras.icons[i] = b
	end
	U.PlaceAuras(f)
end

function U.PlaceAuras(f)
	local a = f.auras
	if not a then return end
	local o = a.opts
	local size, gap = o.size or 22, 3
	local below = (f.castbar and not f.castbar.pwAway) and -24 or -4 -- under the cast bar when there is one
	for i, b in ipairs(a.icons) do
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

-- The debuff border color by dispel type (Magic blue, Curse purple...).
local DISPEL = { Magic = "magic", Curse = "curse", Disease = "disease", Poison = "poison" }

function U.UpdateAuras(f)
	local a = f.auras
	if not a then return end
	local on = ns.Get("units.auras")
	local filter = a.opts.filter
	if filter == "HARMFUL" and ns.Get("units.onlyMyDebuffs") and f.unit ~= "player" then filter = "HARMFUL|PLAYER" end
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
			if b.pwAura ~= data.auraInstanceID then
				-- A new aura in this slot: it fades in.
				b.pwAura = data.auraInstanceID
				if not b:IsShown() then ns.Anim.Set(b, "alpha", 0) b:SetAlpha(0) end
				ns.Anim.Fade(b, 1, ns.Anim.NORMAL)
			end
			T.SetBorder(b, c or "border")
			b:Show()
		else
			b.auraID, b.pwAura = nil, nil
			b:Hide()
		end
	end
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
	cb:SetMinMaxValues(0, 1)
	cb:Hide()
	cb:SetScript("OnUpdate", function(self)
		if not (self.start and self.finish) or self.pwEnding then return end
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
	if type(s) == "number" and type(e) == "number" then
		cb.start, cb.finish, cb.channel = s, e, channel
	else
		cb.start, cb.finish = nil, nil
		cb:SetValue(1)
	end
	local locked = readable(notInterruptible)
	local c = locked and T.Color("muted") or T.Color("accent")
	cb:SetStatusBarColor(c[1], c[2], c[3])
	cb:Show()
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
