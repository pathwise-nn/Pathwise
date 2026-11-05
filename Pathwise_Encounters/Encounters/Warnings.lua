-- Warnings: big text in the upper middle of the screen, with a sound.
-- "Impending Doom soon" from Pathwise's own timers, "Pull!", a new phase,
-- and the game's own encounter warnings (Timeline.lua), whose text may be
-- secret: it is handed straight to the font string.
--
--   W.Show(text, kind)   kind: soon, phase, pull, break, kill, game, gameHigh

local ADDON, ns = ...
local T = ns.Theme
local W = {}
ns.EncWarnings = W

local HOLD, FADE = 2.5, 0.6
local COLOR = { soon = "accent", phase = "flair", pull = "success", ["break"] = "success", kill = "success",
	game = "warning", gameHigh = "error" }
local LOUD = { soon = true, phase = true, pull = true } -- the game's own say themselves (Timeline.lua)

local frame, text, untilAt

local function build()
	if frame then return end
	frame = CreateFrame("Frame", "PathwiseEncounters_Warning", UIParent)
	frame:SetFrameStrata("HIGH")
	frame:SetSize(640, 40)
	frame:SetPoint("TOP", UIParent, "TOP", 0, -190)
	text = frame:CreateFontString(nil, "OVERLAY")
	T.Font(text, "title", 26, "OUTLINE")
	text:SetPoint("CENTER")
	text:SetJustifyH("CENTER")
	W.text = text
	frame:Hide()
	frame:SetScript("OnUpdate", function(self)
		local now = GetTime and GetTime() or 0
		if not untilAt then return end
		local left = untilAt - now
		if left <= 0 then self:Hide() untilAt = nil return end
		self:SetAlpha(left < FADE and left / FADE or 1)
	end)
end

function W.Sound()
	if not ns.Get("enc.sound") or not PlaySound then return end
	local id = SOUNDKIT and SOUNDKIT.RAID_WARNING
	if id then pcall(PlaySound, id, "Master") end
end

function W.Show(msg, kind)
	build()
	text:SetText(msg) -- may be secret: passed as it is
	local c = T.Color(COLOR[kind] or "accent")
	text:SetTextColor(c[1], c[2], c[3])
	untilAt = (GetTime and GetTime() or 0) + HOLD + FADE
	frame:SetAlpha(1)
	frame:Show()
	if LOUD[kind] then W.Sound() end
end
function W.Frame() build() return frame end

ns.On("WARN", function(msg, kind)
	if ns.Get("enc.warnings") then W.Show(msg, kind) end
end)
