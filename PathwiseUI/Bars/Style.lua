-- The action buttons drawn the Pathwise way: a square icon on a dark slot
-- with a 1 px border, your accent on hover and on what is active (every
-- state drawn inside the border, the game's cast flourishes faded), hotkeys
-- and stack counts in Inter. Only looks change: the game's own button code
-- still decides what each button does, and no field it reads is written.

local ADDON, ns = ...
local T = ns.Theme
local B = ns.Bars

local styled = setmetatable({}, { __mode = "k" }) -- button -> our textures

local function fade(region)
	if type(region) == "table" and region.SetAlpha then region:SetAlpha(0) end
end

-- Inside the 1 px border. The game sizes its state art for its own 45 px
-- frame, pinned top left (Forever's ActionButtonTemplate: 46 x 45, or the
-- atlas size), so on our slot it would spill out of the square.
local function inset(region)
	if type(region) == "table" and region.ClearAllPoints then
		region:ClearAllPoints()
		region:SetPoint("TOPLEFT", 1, -1)
		region:SetPoint("BOTTOMRIGHT", -1, 1)
	end
end

local function tint(region, r, g, b, a)
	if type(region) == "table" and region.SetColorTexture then
		region:SetColorTexture(r, g, b, a)
		inset(region)
	end
end

local function font(fs, size, flags)
	if type(fs) == "table" and fs.SetFont then pcall(fs.SetFont, fs, T.FONTS.semibold, size, flags or "OUTLINE") end
end

function B.Style(b)
	local s = styled[b]
	if not s then
		s = {}
		s.ground = b:CreateTexture(nil, "BACKGROUND", nil, -8)
		s.ground:SetAllPoints()
		s.border = T.Border(b, "OVERLAY", 6)
		T.Etch(b)
		styled[b] = s
		-- The icon fills the slot inside the border (set once, out of combat).
		local icon = b.icon or b.Icon
		if type(icon) == "table" and icon.ClearAllPoints then
			icon:ClearAllPoints()
			icon:SetPoint("TOPLEFT", 1, -1)
			icon:SetPoint("BOTTOMRIGHT", -1, 1)
		end
		-- The game re-draws parts of the button as its action changes: dress it again after.
		if hooksecurefunc and type(b.Update) == "function" then hooksecurefunc(b, "Update", function(self) B.Restyle(self) end) end
	end
	local bg, br = T.Color("bg2"), T.Color("border")
	s.ground:SetColorTexture(bg[1], bg[2], bg[3], 0.9)
	s.border:SetColor(br[1], br[2], br[3], 1)
	B.Restyle(b)
end

-- The parts the game may put back: faded or recolored again.
function B.Restyle(b)
	if not styled[b] then return end
	local icon = b.icon or b.Icon
	if type(icon) == "table" then
		if icon.SetTexCoord then icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
		if type(b.IconMask) == "table" and icon.RemoveMaskTexture then pcall(icon.RemoveMaskTexture, icon, b.IconMask) end
	end
	fade(b.NormalTexture)
	if b.GetNormalTexture then fade(b:GetNormalTexture()) end
	fade(b.SlotArt)
	fade(b.SlotBackground)
	fade(b.FloatingBG)
	local a = T.Color("accent")
	-- Hover, active (casting, toggled on), pressed: flat tints in the slot.
	tint(b.GetHighlightTexture and b:GetHighlightTexture(), a[1], a[2], a[3], 0.25)
	tint(b.GetCheckedTexture and b:GetCheckedTexture(), a[1], a[2], a[3], 0.35)
	tint(b.GetPushedTexture and b:GetPushedTexture(), 1, 1, 1, 0.15)
	-- Auto-attack / auto-shot flashing: a soft red in the slot.
	tint(b.Flash, 0.9, 0.3, 0.35, 0.45)
	-- A new action, a spell the game points out, an equipped item's border
	-- (the game tints that one): white, in the slot.
	tint(b.NewActionTexture, a[1], a[2], a[3], 0.3)
	tint(b.SpellHighlightTexture, a[1], a[2], a[3], 0.3)
	tint(b.Border, 1, 1, 1, 0.5)
	-- The game's cast fill, interrupt and targeting flourishes are drawn for
	-- its round-cornered frame: faded. Active shows in your accent instead.
	fade(b.SpellCastAnimFrame)
	fade(b.InterruptDisplay)
	fade(b.TargetReticleAnimFrame)
	font(b.Count, 12)
	font(b.Name, 10)
	if type(b.Name) == "table" and b.Name.SetAlpha then b.Name:SetAlpha(ns.Get("bars.macroNames") and 1 or 0) end
	B.StyleHotkey(b)
end

function B.StyleHotkey(b)
	local hk = b.HotKey
	if type(hk) ~= "table" then return end
	font(hk, 11)
	if hk.SetAlpha then hk:SetAlpha(ns.Get("bars.hotkeys") and 1 or 0) end
	if hk.SetTextColor then local c = T.Color("text2") hk:SetTextColor(c[1], c[2], c[3]) end
end

ns.On("ACCENT_CHANGED", function() for b in pairs(styled) do B.Restyle(b) end end)
