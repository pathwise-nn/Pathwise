-- Pathwise Heal: the buff and debuff rows on each healing frame.
--
--   * The buff row, top right: your HoTs first, with the time left on each
--     (red and blinking for the last seconds), then big defensives and your
--     other buffs, as Blizzard's raid frames choose them.
--   * The debuff row, along the bottom: the debuffs you can remove on the
--     left, in their type's color (a left click on one casts the spell that
--     removes it), the others on the right.
--
-- In a fight Forever makes aura data secret (SecretWhenUnitAuraRestricted):
-- an addon can still list the auras and hand their icons to the game
-- (Texture:SetTexture takes secret values), but can't compare them or read
-- their times. So in a fight:
--   * the buff row stays ours: your HoTs (the RAID_IN_COMBAT filter) and big
--     defensives, icons only, unless the game leaves the time readable. The
--     game's own container shows buffs by its raid-frame rules
--     (AuraUtil.ShouldDisplayBuff), which leave HoTs out on Forever;
--   * the game draws the debuff row and the dispel edge into the frame: one
--     private aura container (C_UnitAuras.AddPrivateAuraAnchor,
--     Blizzard_PrivateAurasUI.lua) laid out like ours (BuffsTopDebuffsBottom:
--     the debuffs you can remove bottom left, the rest bottom right), with the
--     game's countdown. It is attached only for the fight: its icons take the
--     mouse for their tooltips, and between fights our clicks are wanted there.
--
-- Which auras: filters from Blizzard's Forever UI (Blizzard_FrameXMLUtil/
-- AuraUtil.lua, AuraUtil.AuraFilters), no spell list of our own:
--   RAID_IN_COMBAT with PLAYER and HELPFUL: "self-cast HoTs";
--   BIG_DEFENSIVE: "auras that are big defensives";
--   RAID: "helpful auras the player can apply and harmful auras the player
--   can dispel".

local ADDON, ns = ...
local T = ns.Theme
local H = ns.Heal

H.MAX_BUFFS = 3
H.MAX_REMOVABLE = 3 -- Heal.xml has a secure button for each (Debuff1..3)
H.MAX_OTHER_DEBUFFS = 2
H.HOT_FILTER = "HELPFUL|PLAYER|RAID_IN_COMBAT"

local readable = H.Readable

-- The spell that removes each debuff type, by class: the first one you know.
-- The names are the click presets' (Clicks.lua, same caveats: a name the
-- game doesn't know is skipped).
H.CLEANSE = {
	PRIEST = { Magic = { "Dispel Magic" }, Disease = { "Abolish Disease", "Cure Disease" } },
	DRUID = { Curse = { "Remove Curse" }, Poison = { "Abolish Poison", "Cure Poison" } },
	SHAMAN = { Poison = { "Cure Poison" }, Disease = { "Cure Disease" } },
	PALADIN = { Magic = { "Cleanse" }, Poison = { "Cleanse", "Purify" }, Disease = { "Cleanse", "Purify" } },
	MAGE = { Curse = { "Remove Lesser Curse" } },
}
local DISPEL_ORDER = { Magic = 1, Curse = 2, Disease = 3, Poison = 4 }
local DISPEL_COLOR = { Magic = "magic", Curse = "curse", Disease = "disease", Poison = "poison" }

-- The spell you'd cast to remove a debuff of this type, or nil.
function H.CleanseSpell(kind)
	local _, class = H.Call(UnitClass, "player")
	class = readable(class)
	local list = class and H.CLEANSE[class] and H.CLEANSE[class][kind]
	local C = ns.HealClicks
	for _, name in ipairs(list or {}) do
		if not (C and C.Known) or C.Known(name) ~= false then return name end
	end
	return nil
end

local function clamp(v, lo, hi, default) v = tonumber(v) or default return math.max(lo, math.min(hi, v)) end
function H.BuffSize() return clamp(ns.Get("heal.buffSize"), 8, 24, 14) end
function H.DebuffSize() return clamp(ns.Get("heal.debuffSize"), 8, 24, 14) end

local function enumValue(group, key, fallback)
	local e = Enum and Enum[group]
	return (e and e[key]) or fallback
end

---------------------------------------------------------------------------
-- The icons
---------------------------------------------------------------------------

-- An icon texture (with the time left on it, `timer`) on `parent`.
local function icon(parent, layer, timer)
	local ic = parent:CreateTexture(nil, layer or "ARTWORK")
	ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	ic:Hide()
	if timer then
		local t = parent:CreateFontString(nil, "OVERLAY", nil, 7)
		t:SetPoint("CENTER", ic, "CENTER", 1, 0)
		T.BarText(t, "small", 9) -- a font first: text on a font string without one is an error
		t:SetJustifyH("CENTER")
		t:SetText("")
		ic.pwText = t
	end
	return ic
end

local function tooltip(owner, unit, id, filter)
	if not (GameTooltip and unit and id) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMRIGHT")
	pcall(GameTooltip.SetUnitDebuffByAuraInstanceID, GameTooltip, unit, id, filter)
	GameTooltip:Show()
end

-- Called by H.NewButton. The secure debuff buttons come from Heal.xml; a
-- frame made without it (tests) gets its own, out of combat.
function H.MakeAuras(b)
	local level = (b.health and b.health:GetFrameLevel() or 1) + 2 -- over the bars, under the names
	local layer = CreateFrame("Frame", nil, b)
	layer:SetAllPoints()
	layer:SetFrameLevel(level)
	b.auraLayer = layer
	b.buffs = {}
	for i = 1, H.MAX_BUFFS do b.buffs[i] = icon(layer, "ARTWORK", true) end
	b.hots = b.buffs -- the HoTs lead the buff row
	b.otherDebuffs = {}
	for i = 1, H.MAX_OTHER_DEBUFFS do
		local ic = icon(layer, "ARTWORK")
		b.otherDebuffs[i] = ic
	end
	b.removable = {}
	for i = 1, H.MAX_REMOVABLE do
		local d = rawget(b, "Debuff" .. i) -- Heal.xml's parentKey
		if not d and not H.InCombat() then
			d = CreateFrame("Button", nil, b, "PathwiseHeal_DebuffTemplate")
			d:SetAttribute("useparent*", true)
		end
		if d then
			if not H.InCombat() then d:SetFrameLevel(level + 1) end
			d.icon = icon(d, "ARTWORK")
			d.icon:SetAllPoints()
			d.icon:Show()
			d.edge = H.Edge(d, false)
			d.count = d:CreateFontString(nil, "OVERLAY", nil, 7)
			d.count:SetPoint("BOTTOMRIGHT", 1, -1)
			T.BarText(d.count, "small", 8)
			d:HookScript("OnEnter", function(self) tooltip(self, b.pwUnit, self.pwAura, "HARMFUL") end)
			d:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
			b.removable[i] = d
		end
	end
	-- The game draws both rows here in a fight.
	b.gameAuras = CreateFrame("Frame", nil, b.over or b)
	b.gameAuras:SetAllPoints()
end

-- Sizes and places (out of combat: H.Size).
-- A frame whose rows were all made (a frame made half way is left alone).
local function built(b) return b.buffs and b.otherDebuffs and b.removable and true or false end

function H.PlaceAuras(b)
	if not built(b) then return end
	local bs, ds = H.BuffSize(), H.DebuffSize()
	for i, ic in ipairs(b.buffs) do
		ic:SetSize(bs, bs)
		ic:ClearAllPoints()
		ic:SetPoint("TOPRIGHT", b, "TOPRIGHT", -3 - (i - 1) * (bs + 1), -3)
		T.BarText(ic.pwText, "small", math.max(8, math.floor(bs * 0.64 + 0.5)))
	end
	local y = (ns.Get("heal.mana") and 5 or 1) + 2
	for i, d in ipairs(b.removable) do
		d:SetSize(ds, ds)
		d:ClearAllPoints()
		d:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 3 + (i - 1) * (ds + 1), y)
		if d.RegisterForClicks then d:RegisterForClicks("AnyUp") end
		d:SetAttribute("useparent*", true)
	end
	for i, ic in ipairs(b.otherDebuffs) do
		ic:SetSize(ds, ds)
		ic:ClearAllPoints()
		ic:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3 - (i - 1) * (ds + 1), y)
	end
end

---------------------------------------------------------------------------
-- The game's rows, in a fight
---------------------------------------------------------------------------

function H.DetachGame(b)
	if b.pwAnchor and C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor then pcall(C_UnitAuras.RemovePrivateAuraAnchor, b.pwAnchor) end
	b.pwAnchor, b.pwAnchorUnit = nil, nil
end

function H.AttachGame(b)
	local unit, U = b.pwUnit, C_UnitAuras
	local buffs = false -- the buff row stays ours (H.FightBuffs)
	local debuffs, dispel = ns.Get("heal.debuffs"), ns.Get("heal.dispel")
	if not (unit and b.gameAuras and (debuffs or dispel) and U and U.AddPrivateAuraAnchor) then H.DetachGame(b) return false end
	if b.pwAnchor and b.pwAnchorUnit == unit then return true end
	H.DetachGame(b)
	local g, bs, ds = b.gameAuras, H.BuffSize(), H.DebuffSize()
	local timers = ns.Get("heal.timers") and true or false
	local ok, id = pcall(function()
		-- The settings the game's raid-aura drawing reads off the holder.
		g:SetAttribute("max-buffs", buffs and H.MAX_BUFFS or 0)
		g:SetAttribute("max-debuffs", debuffs and H.MAX_OTHER_DEBUFFS or 0)
		g:SetAttribute("max-dispel-debuffs", debuffs and H.MAX_REMOVABLE or 0)
		g:SetAttribute("aura-organization-type", enumValue("RaidAuraOrganizationType", "BuffsTopDebuffsBottom", 1))
		g:SetAttribute("display-only-dispellable-debuffs", false)
		g:SetAttribute("ignore-buffs", not buffs)
		g:SetAttribute("ignore-debuffs", not debuffs)
		g:SetAttribute("ignore-dispel-debuffs", not debuffs)
		g:SetAttribute("dispel-indicator-option", dispel and enumValue("RaidDispelDisplayType", "DispellableByMe", 1) or enumValue("RaidDispelDisplayType", "Disabled", 0))
		g:SetAttribute("display-larger-role-specific-debuffs", false)
		g:SetAttribute("dispel-indicator-overlay-type", dispel and enumValue("RaidDispelOverlayType", "UseDebuffColor", 1) or enumValue("RaidDispelOverlayType", "Disabled", 0))
		g:SetAttribute("dispel-indicator-overlay-animation", false)
		g:SetAttribute("dispel-indicator-animated-border", false)
		g:SetAttribute("show-big-defensive", false)
		g:SetAttribute("big-defensive-size", bs)
		g:SetAttribute("debuff-size", ds)
		g:SetAttribute("buff-size", bs)
		g:SetAttribute("debuff-border-scale", 1)
		g:SetAttribute("buff-border-scale", 1)
		g:SetAttribute("always-hide-duration", true) -- the countdown numbers say it, inside the icon
		g:SetAttribute("set-aura-size-to-icon-size", true)
		g:SetAttribute("power-bar-used-height", ns.Get("heal.mana") and 4 or 0)
		g:SetAttribute("group-type", enumValue("EditModeUnitFrameSystemIndices", "Party", 0))
		return U.AddPrivateAuraAnchor({
			unitToken = unit, auraIndex = 1, parent = g, isContainer = true,
			showCooldownFrame = timers, showCooldownEdge = false, showCountdownNumbers = timers, showDispelIcon = true,
			iconInfo = { iconAnchor = { point = "BOTTOMRIGHT", relativeTo = g, relativePoint = "BOTTOMRIGHT", offsetX = -3, offsetY = 3 },
				iconWidth = ds, iconHeight = ds, borderScale = 1 },
		})
	end)
	if ok and id then b.pwAnchor, b.pwAnchorUnit = id, unit return true end
	return false
end

---------------------------------------------------------------------------
-- Our rows, between fights
---------------------------------------------------------------------------

local live = {} -- frames with a countdown running
H.live = live

-- The secure buttons: shown, hidden and given spells only out of combat.
local function setRemovable(d, data, kind, spell)
	if H.InCombat() then return end
	if not data then
		d:Hide()
		d:SetAttribute("type1", nil)
		d:SetAttribute("spell1", nil)
		d.pwAura, d.pwSpell = nil, nil
		return
	end
	d.icon:SetTexture(data.icon)
	local c = kind and DISPEL_COLOR[kind]
	d.edge:SetColor(T.Color(c or "border"))
	local n = readable(data.applications)
	d.count:SetText((type(n) == "number" and n > 1) and n or "")
	d.pwAura, d.pwSpell = readable(data.auraInstanceID), spell
	d:SetAttribute("type1", spell and "spell" or nil) -- nil: the frame's own left click
	d:SetAttribute("spell1", spell)
	d:Show()
end

-- One buff: `need` = "timed" (has a duration) or "any".
local function addBuff(b, d, seen, need, maxDuration)
	if b.pwBuffs >= H.MAX_BUFFS or type(d) ~= "table" then return end
	local id = readable(d.auraInstanceID)
	if id ~= nil and seen[id] then return end
	local dur, exp = readable(d.duration), readable(d.expirationTime)
	if need == "timed" and (type(dur) ~= "number" or dur <= 0) then return end
	if maxDuration and not (type(dur) == "number" and dur > 0 and dur <= maxDuration) then return end
	if id ~= nil then seen[id] = true end
	b.pwBuffs = b.pwBuffs + 1
	local ic = b.buffs[b.pwBuffs]
	ic:SetTexture(d.icon)
	ic.pwDuration = type(dur) == "number" and dur or nil
	ic.pwExpires = (type(exp) == "number" and exp > 0) and exp or nil
	ic:SetAlpha(1)
	ic:Show()
end

-- Each aura of `filter` in turn (stops at the end or a refusal).
local function each(unit, filter, fn)
	for i = 1, 40 do
		local d, refused = H.Aura(unit, i, filter)
		if refused or type(d) ~= "table" then return end
		if fn(d) == false then return end
	end
end

-- The buff row in a fight, from secret aura data: no two filters that could
-- list the same aura (their ids can't be compared), no duration check (the
-- in-combat HoT filter is the game's own choice). A refusal ends a filter
-- without pausing the reads that resume after the fight.
function H.FightBuffs(b, unit)
	local filters = {}
	if ns.Get("heal.hots") then filters[#filters + 1] = H.HOT_FILTER end
	if ns.Get("heal.buffs") then
		filters[#filters + 1] = "HELPFUL|BIG_DEFENSIVE"
		if not ns.Get("heal.hots") then filters[#filters + 1] = "HELPFUL|PLAYER|RAID" end
	end
	local seen = {}
	for _, filter in ipairs(filters) do
		for i = 1, 40 do
			if b.pwBuffs >= H.MAX_BUFFS then return end
			local okCall, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not okCall or type(d) ~= "table" then break end
			addBuff(b, d, seen, "any")
		end
	end
end

local handedOver = false -- the fight's rows are up (H.Fighting)

-- A frame counts down while one of its buffs has a time we can read.
local function counting(b)
	if not ns.Get("heal.timers") then return false end
	for i = 1, b.pwBuffs or 0 do if b.buffs[i].pwExpires then return true end end
	return false
end

function H.Auras(b, unit)
	if not built(b) then return end
	for _, ic in ipairs(b.buffs) do ic:Hide() ic.pwText:SetText("") ic.pwShown, ic.pwExpires, ic.pwWarn = nil, nil, nil end
	for _, ic in ipairs(b.otherDebuffs) do ic:Hide() end
	for _, d in ipairs(b.removable) do setRemovable(d, nil) end
	b.pwBuffs = 0
	live[b] = nil
	if not H.AurasAllowed() then -- our buff row from secret data; the game draws the debuffs (and the dispel edge)
		b.dispel:SetShown(false)
		H.AttachGame(b)
		H.FightBuffs(b, unit)
		if counting(b) then live[b] = true end
		H.Timers(b)
		H.Ticking()
		return
	end
	handedOver = false
	H.DetachGame(b)
	-- The debuffs you can remove: the left of the row, and the frame's edge.
	local seen, best, n = {}, nil, 0
	each(unit, "HARMFUL|RAID", function(d)
		local kind = readable(d.dispelName)
		if kind and DISPEL_ORDER[kind] and (not best or DISPEL_ORDER[kind] < DISPEL_ORDER[best]) then best = kind end
		local id = readable(d.auraInstanceID)
		if id ~= nil then seen[id] = true end
		if ns.Get("heal.debuffs") and n < #b.removable then
			n = n + 1
			local spell = ns.Get("heal.cleanseClick") and kind and H.CleanseSpell(kind) or nil
			setRemovable(b.removable[n], d, kind, spell)
		end
	end)
	best = ns.Get("heal.dispel") and best or nil
	if best then b.dispel:SetColor(T.Color(DISPEL_COLOR[best])) end
	b.dispel:SetShown(best and true or false)
	-- The other debuffs: the right of the row.
	if ns.Get("heal.debuffs") then
		local m = 0
		each(unit, "HARMFUL", function(d)
			local id = readable(d.auraInstanceID)
			if id ~= nil and seen[id] then return end
			m = m + 1
			local ic = b.otherDebuffs[m]
			ic:SetTexture(d.icon)
			ic:Show()
			if m >= #b.otherDebuffs then return false end
		end)
	end
	-- The buff row: your HoTs, big defensives, your short buffs, your other buffs.
	local had = {}
	local full = function() if b.pwBuffs >= H.MAX_BUFFS then return false end end
	if ns.Get("heal.hots") then
		for i = 1, 40 do -- a client that refuses the HoT filter: skipped
			if b.pwBuffs >= H.MAX_BUFFS then break end
			local okCall, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, H.HOT_FILTER)
			if not okCall or type(d) ~= "table" then break end
			addBuff(b, d, had, "timed")
		end
		each(unit, "HELPFUL|PLAYER", function(d) addBuff(b, d, had, "timed", 60) return full() end)
	end
	if ns.Get("heal.buffs") then
		each(unit, "HELPFUL|BIG_DEFENSIVE", function(d) addBuff(b, d, had, "any") return full() end)
		each(unit, "HELPFUL|PLAYER|RAID", function(d) addBuff(b, d, had, "any") return full() end)
	end
	if counting(b) then live[b] = true end
	H.Timers(b)
	H.Ticking()
end

---------------------------------------------------------------------------
-- The time left on buffs (between fights): a light timer that runs only
-- while a countdown shows; UNIT_AURA redraws the icons themselves.
---------------------------------------------------------------------------

H.TICK = 0.1
-- Red and blinking for its last 3 seconds (the last third of a short one).
function H.WarnAt(duration) return math.min(3, (duration or 9) / 3) end

-- 75 -> "2m", 12.2 -> "13", 0.4 -> "1", an hour -> "1h": whole units,
-- rounded up, to fit an icon.
function H.FormatLeft(sec)
	if type(sec) ~= "number" or sec <= 0 then return "" end
	if sec >= 3600 then return ("%dh"):format(math.ceil(sec / 3600)) end
	if sec >= 60 then return ("%dm"):format(math.ceil(sec / 60)) end
	return ("%d"):format(math.ceil(sec))
end

-- A countdown shows only in its last minute: "57m" is wider than an icon
-- and ran over the icons beside it (a long buff shows just its icon).
H.TIMER_FROM = 60

function H.Timers(b, now)
	now = now or (GetTime and GetTime() or 0)
	local timers = ns.Get("heal.timers")
	for i = 1, b.pwBuffs or 0 do
		local ic = b.buffs[i]
		local left = ic.pwExpires and (ic.pwExpires - now)
		if not (timers and left and left <= H.TIMER_FROM) then
			if ic.pwShown ~= "" then ic.pwText:SetText("") ic.pwShown = "" end
			if ic.pwWarn then T.Paint(ic.pwText, "text") end
			ic.pwWarn = nil
			ic:SetAlpha(1)
		else
			local text = H.FormatLeft(left)
			if text ~= ic.pwShown then ic.pwText:SetText(text) ic.pwShown = text end
			local warn = left <= H.WarnAt(ic.pwDuration)
			if warn ~= ic.pwWarn then T.Paint(ic.pwText, warn and "error" or "text") ic.pwWarn = warn end
			-- Near the end it blinks, twice a second.
			ic:SetAlpha(warn and (0.4 + 0.6 * (0.5 + 0.5 * math.cos(now * 4 * math.pi))) or 1)
		end
	end
end
H.HotTimers = H.Timers

local ticker, since = nil, 0
-- The timer runs while any frame has a countdown (and the frames are on).
function H.Ticking()
	local on = ns.Get("heal.enabled") and next(live) ~= nil or false
	if on and not ticker then
		ticker = CreateFrame("Frame")
		ticker:SetScript("OnUpdate", function(_, dt)
			since = since + (dt or 0)
			if since < H.TICK then return end
			since = 0
			if not H.AurasAllowed() and not handedOver then H.Fighting() return end -- a fight began without the combat event
			local now = GetTime and GetTime() or 0
			for b in pairs(live) do H.Timers(b, now) end
		end)
	end
	if ticker then ticker:SetShown(on) end
	return on
end
function H.Ticker() return ticker end

-- Auras just turned secret: every frame switches to its fight rows.
function H.Fighting()
	handedOver = true
	for _, b in ipairs(H.buttons) do
		if b.pwUnit then H.Auras(b, b.pwUnit) else live[b] = nil end
	end
	H.Ticking()
end

-- Every frame's auras, at most five times a second (a UNIT_AURA that doesn't
-- say whose).
local soon = false
function H.AurasSoon()
	if soon then return end
	local function run()
		soon = false
		if not ns.Get("heal.enabled") then return end
		for _, b in ipairs(H.buttons) do if b.pwUnit then H.Auras(b, b.pwUnit) end end
	end
	if C_Timer and C_Timer.After then soon = true C_Timer.After(0.2, run) else run() end
end

---------------------------------------------------------------------------
-- Events and settings
---------------------------------------------------------------------------

-- The fight starts a moment after this: hand over now, while our secure
-- debuff buttons can still be hidden.
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	H.SetFighting(true)
	if ns.Get("heal.enabled") then H.Fighting() end
end)
-- Fired just before a restriction starts, or after it ends: look again soon.
ns.RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED", function()
	if ns.Get("heal.enabled") and C_Timer and C_Timer.After then C_Timer.After(0.05, H.UpdateAll) end
end)

local AURA_SETTINGS = { ["heal.hots"] = true, ["heal.buffs"] = true, ["heal.timers"] = true, ["heal.buffSize"] = true,
	["heal.debuffs"] = true, ["heal.debuffSize"] = true, ["heal.cleanseClick"] = true, ["heal.dispel"] = true, ["heal.mana"] = true, ["*"] = true }
-- The rows (and the game's, in a fight too) take a new setting at once.
function H.AuraSettingChanged(path)
	if not AURA_SETTINGS[path] then return end
	for _, b in ipairs(H.buttons) do
		H.DetachGame(b)
		if b.pwUnit and ns.Get("heal.enabled") then H.Auras(b, b.pwUnit) end
	end
	H.Ticking()
end
