-- Your money, always on screen: a small panel in the Pathwise look with your
-- gold, silver and copper, each in its own color (the Colors page changes
-- them). When it changes the amount counts to the new one and flashes green
-- (more) or red (less). Hover: what you made or spent this session, and what
-- each of your characters on this realm holds. Click: your bags.
--
-- GetMoney() and PLAYER_MONEY are ordinary values on Forever. Each
-- character's amount is remembered account-wide (ns.Data), so the totals
-- show characters you are not logged in on.

local ADDON, ns = ...
local T = ns.Theme
local A = ns.Anim
local Money = {}
ns.Money = Money

ns.Defaults("money", {
	enabled = true,
	style = "full", -- "full" (12g 34s 56c) | "gold" (12g only, rounded down) | "short" (1.2k g)
	session = true, -- this session's change in the tooltip
	characters = true, -- your other characters in the tooltip
	point = nil,
})
Money.DEFAULT_POINT = { "BOTTOMRIGHT", "BOTTOMRIGHT", -8, 42 } -- above the bags

local function inCombat() return InCombatLockdown and InCombatLockdown() end
local readable = ns.Readable

local frame
local startMoney -- at login, for this session's change
local shownMoney -- what the text shows now (counts toward the real amount)

function Money.Get()
	local m = readable(GetMoney and GetMoney())
	return type(m) == "number" and m or nil
end

local function grouped(n)
	local s = tostring(math.floor(n))
	while true do
		local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		s = r
		if k == 0 then return s end
	end
end

local function hexOf(name) return T.ToHex(T.Color(name)):sub(2) end

-- Copper as text: "1,234g 56s 78c" with each part in its color.
-- style: "full" | "gold" | "short"; plain: no color codes (for tests and sums).
function Money.Format(copper, style, plain)
	copper = math.floor(math.abs(copper or 0))
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local function part(n, letter, color)
		if plain then return n .. letter end
		return ("|cff%s%s|r|cff%s%s|r"):format(hexOf("text"), n, hexOf(color), letter)
	end
	if style == "short" and g >= 1000 then
		local v = g >= 1000000 and ("%.1fm"):format(g / 1000000) or ("%.1fk"):format(g / 1000)
		return part((v:gsub("%.0([km])$", "%1")), "g", "gold")
	end
	if style == "gold" or style == "short" then
		if g > 0 then return part(grouped(g), "g", "gold") end
	end
	local out = {}
	if g > 0 then out[#out + 1] = part(grouped(g), "g", "gold") end
	if s > 0 or (g > 0 and c > 0) then out[#out + 1] = part(s, "s", "silver") end
	if c > 0 or #out == 0 then out[#out + 1] = part(c, "c", "copper") end
	return table.concat(out, " ")
end

---------------------------------------------------------------------------
-- Every character's money (this realm), remembered
---------------------------------------------------------------------------

local function me()
	local name = readable(UnitName and UnitName("player"))
	local realm = readable(GetRealmName and GetRealmName()) or ""
	if type(name) ~= "string" then return nil end
	return name .. "-" .. realm, name, realm
end

function Money.Remember()
	local key, name, realm = me()
	local m = Money.Get()
	if not (key and m) then return end
	local _, class = UnitClass("player")
	ns.Data("money")[key] = { name = name, realm = realm, copper = m, class = readable(class) }
end

-- -> { { name, copper, class, me }, ... } on this realm, richest first; total
function Money.Characters()
	local key, _, realm = me()
	local list, total = {}, 0
	for k, v in pairs(ns.Data("money")) do
		if type(v) == "table" and v.realm == realm and type(v.copper) == "number" then
			list[#list + 1] = { name = v.name, copper = v.copper, class = v.class, me = k == key }
			total = total + v.copper
		end
	end
	table.sort(list, function(a, b) return a.copper > b.copper end)
	return list, total
end

-- Forget a character (they were deleted): /pwui forget Name
function Money.Forget(name)
	local _, _, realm = me()
	for k, v in pairs(ns.Data("money")) do
		if type(v) == "table" and v.realm == realm and type(v.name) == "string" and v.name:lower() == (name or ""):lower() then
			ns.Data("money")[k] = nil
			return true
		end
	end
	return false
end

---------------------------------------------------------------------------
-- The panel
---------------------------------------------------------------------------

local function paintText(v)
	if not frame then return end
	frame.text:SetText(Money.Format(v, ns.Get("money.style")))
	local w = (frame.text:GetStringWidth() or 60) + 20
	frame:SetWidth(math.max(60, math.floor(w + 0.5)))
end

local function build()
	if frame then return frame end
	frame = CreateFrame("Button", "PathwiseUI_Money", nil)
	frame:SetParent(UIParent)
	frame:SetFrameStrata("LOW")
	frame:SetHeight(24)
	frame:SetMovable(true)
	frame:RegisterForClicks("LeftButtonUp")
	T.Panel(frame, "bg", "border", 0.9)
	frame.flash = frame:CreateTexture(nil, "ARTWORK")
	frame.flash:SetPoint("TOPLEFT", 1, -1)
	frame.flash:SetPoint("BOTTOMRIGHT", -1, 1)
	frame.flash:SetAlpha(0)
	frame.text = T.Text(frame, "body", "text")
	frame.text:SetPoint("CENTER")
	frame.text:SetJustifyH("CENTER")
	frame.text:SetJustifyV("MIDDLE")
	local function look(p) T.Blend(frame.pwBorder, "border", "muted", p) end
	frame:SetScript("OnEnter", function(self)
		A.Hover(self, true, look)
		Money.Tooltip(self)
	end)
	frame:SetScript("OnLeave", function(self)
		A.Hover(self, false, look)
		if GameTooltip then GameTooltip:Hide() end
	end)
	frame:SetScript("OnClick", function() if ToggleAllBags and not inCombat() then ToggleAllBags() end end)
	return frame
end
function Money.Frame() return frame end

function Money.Tooltip(owner)
	if not GameTooltip then return end
	GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
	GameTooltip:SetText("Money", 1, 1, 1)
	local m = Money.Get()
	if ns.Get("money.session") and m and startMoney then
		local d = m - startMoney
		local good, bad = T.Color("success"), T.Color("error")
		local c = d >= 0 and good or bad
		GameTooltip:AddDoubleLine("This session", (d >= 0 and "+" or "-") .. Money.Format(math.abs(d), "full"), 0.6, 0.69, 0.75, c[1], c[2], c[3])
	end
	if ns.Get("money.characters") then
		local list, total = Money.Characters()
		if #list > 1 then
			GameTooltip:AddLine(" ")
			for _, ch in ipairs(list) do
				local cc = ch.class and T.ClassColor(ch.class) or T.Color("text")
				GameTooltip:AddDoubleLine(ch.name .. (ch.me and " (you)" or ""), Money.Format(ch.copper, "full"), cc[1], cc[2], cc[3], 1, 1, 1)
			end
			GameTooltip:AddDoubleLine("All characters", Money.Format(total, "full"), 1, 1, 1, 1, 1, 1)
		end
	end
	GameTooltip:AddLine("Click: your bags", 0.48, 0.56, 0.64)
	GameTooltip:Show()
end

-- New amount: count to it and flash green (more) or red (less).
function Money.Update(instant)
	if not frame then return end
	local m = Money.Get()
	if not (m and ns.Get("money.enabled")) then frame:Hide() return end
	frame:Show()
	Money.Remember()
	local from = shownMoney
	shownMoney = m
	if instant or from == nil or from == m then
		A.Set(frame, "money", m, paintText)
		return
	end
	T.Paint(frame.flash, m > from and "success" or "error", 0.22)
	A.Set(frame.flash, "alpha", 1)
	frame.flash:SetAlpha(1)
	A.Fade(frame.flash, 0, 0.8)
	if A.Get(frame, "money") == nil then A.Set(frame, "money", from) end
	A.Tween(frame, "money", m, 0.5, function(v) paintText(math.floor(v + 0.5)) end)
end
function Money.Shown() return shownMoney end

function Money.Layout()
	build()
	if inCombat() then Money.pending = true Money.Update(true) return end
	local p = ns.Get("money.point") or Money.DEFAULT_POINT
	frame:ClearAllPoints()
	frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	Money.Update(true)
end

---------------------------------------------------------------------------
-- Moving it (with everything else in move mode)
---------------------------------------------------------------------------

local unlocked, handle = false, nil
function Money.Unlock(on)
	if inCombat() then return false end
	unlocked = on and true or false
	build()
	if not handle then
		handle = ns.Movers.Handle(frame, "MONEY", function(p, rp, x, y) ns.Set("money.point", { p, rp, x, y }) end)
	end
	handle:Reveal(unlocked and frame:IsShown())
	ns.Movers.Active("money", unlocked)
	return true
end
function Money.Unlocked() return unlocked end
function Money.ResetPosition() ns.Set("money.point", nil) end
ns.Movers.Group("money", function(on) if on or unlocked then Money.Unlock(on) end end)
ns.On("MOVE_MODE", function(any) if not any and unlocked then Money.Unlock(false) end end)

---------------------------------------------------------------------------

ns.On("READY", function()
	startMoney = Money.Get()
	Money.Layout()
end)
ns.RegisterEvent("PLAYER_MONEY", function() Money.Update() end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if Money.pending then Money.pending = false Money.Layout() end end)
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function() if handle then handle:Hide() end unlocked = false end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^money%.") or path == "*") then Money.Layout() end
end)
ns.On("ACCENT_CHANGED", function() if frame and shownMoney then paintText(A.Get(frame, "money") or shownMoney) end end)
-- /pwui forget Name: drop a deleted character from the money totals.
ns.Commands.forget = function(name)
	if name == "" then ns.Print("forget whom? /pwui forget Name") return end
	if Money.Forget(name) then ns.Print(name .. " forgotten.") else ns.Print("no character called " .. name .. " here.") end
end
