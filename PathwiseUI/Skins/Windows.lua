-- The game's windows in the Pathwise look: a flat ground, a 1 px border and
-- an accent line along the top instead of the game's ornate frame; titles in
-- Inter. Only windows built on the game's modern frame template (the ones
-- with a NineSlice frame) are changed; any other keeps its own look, so
-- nothing is ever drawn over art it does not know. Windows that load later
-- (the game's own load-on-demand addons) are dressed when they appear.
-- Not yet checked in game on Forever: each window can be left alone (Config).

local ADDON, ns = ...
local T = ns.Theme
local Win = {}
ns.Windows = Win

ns.Defaults("windows", {
	skin = true,
	portraits = false, -- keep the round portraits
	accentLine = true,
})

-- The windows Pathwise UI dresses, when they exist on the client.
Win.NAMES = {
	"CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "FriendsFrame", "MerchantFrame", "MailFrame",
	"OpenMailFrame", "GossipFrame", "QuestFrame", "QuestLogFrame", "TaxiFrame", "BankFrame", "TradeFrame",
	"LootFrame", "DressUpFrame", "GameMenuFrame", "TabardFrame", "PetStableFrame", "AddonList", "SettingsPanel",
	"ClassTrainerFrame", "TradeSkillFrame", "InspectFrame", "TalentFrame", "ProfessionsFrame", "HelpFrame",
	"ItemTextFrame", "GuildRegistrarFrame", "PetitionFrame", "ContainerFrameCombinedBags", "LFGParentFrame",
	"PVEFrame", "PVPFrame", "WorldStateScoreFrame", "MacroFrame", "KeyBindingFrame", "ChannelFrame",
	"CommunitiesFrame", "AuctionHouseFrame", "AuctionFrame", "EncounterJournal", "CollectionsJournal",
}

local dressed = setmetatable({}, { __mode = "k" }) -- window -> { ground, border, line, hidden = {} }

local function hide(list, region)
	if type(region) == "table" and region.GetAlpha then
		list[#list + 1] = { region, region:GetAlpha() }
		region:SetAlpha(0)
	end
end

-- Dress one window. -> true when it was (or already is) dressed
function Win.Dress(f)
	if type(f) ~= "table" or type(f.NineSlice) ~= "table" then return false end
	local d = dressed[f]
	if not d then
		d = { hidden = {} }
		d.ground = f:CreateTexture(nil, "BACKGROUND", nil, -8)
		d.ground:SetAllPoints()
		d.border = T.Border(f, "BORDER", 7)
		d.line = f:CreateTexture(nil, "ARTWORK", nil, 7)
		d.line:SetPoint("TOPLEFT", 1, -1)
		d.line:SetPoint("TOPRIGHT", -1, -1)
		d.line:SetHeight(2)
		T.Paint(d.line, "accent")
		dressed[f] = d
	end
	Win.Paint(f)
	return true
end

function Win.Paint(f)
	local d = dressed[f]
	if not d then return end
	-- Undo the last dressing, then dress again as the settings now say.
	for _, h in ipairs(d.hidden) do h[1]:SetAlpha(h[2]) end
	d.hidden = {}
	local on = ns.Get("windows.skin")
	d.ground:SetShown(on)
	d.border:SetShown(on)
	d.line:SetShown(on and ns.Get("windows.accentLine"))
	if not on then return end
	local bg, br = T.Color("bg"), T.Color("border")
	d.ground:SetColorTexture(bg[1], bg[2], bg[3], ns.Get("look.opacity") or 0.92)
	d.border:SetColor(br[1], br[2], br[3], 1)
	hide(d.hidden, f.NineSlice)
	hide(d.hidden, f.Bg)
	hide(d.hidden, f.TitleBg)
	hide(d.hidden, f.TopTileStreaks)
	if type(f.Inset) == "table" then hide(d.hidden, f.Inset.NineSlice) hide(d.hidden, f.Inset.Bg) end
	if not ns.Get("windows.portraits") then
		hide(d.hidden, f.PortraitContainer)
		hide(d.hidden, f.portrait)
	end
	local title = type(f.TitleContainer) == "table" and f.TitleContainer.TitleText or f.TitleText
	if type(title) == "table" and title.GetFont then
		local _, size = title:GetFont()
		pcall(title.SetFont, title, T.FONTS.semibold, size or 13, "")
	end
end

local waiting = false
function Win.DressAll()
	if InCombatLockdown and InCombatLockdown() then waiting = true return 0 end
	local n = 0
	for _, name in ipairs(Win.NAMES) do
		local f = _G[name]
		if type(f) == "table" and Win.Dress(f) then n = n + 1 end
	end
	return n
end
function Win.Dressed() return dressed end

ns.On("READY", function() Win.DressAll() end)
-- The game's own addons that load later (the talent, professions, auction windows...).
ns.RegisterEvent("ADDON_LOADED", function(_, name)
	if type(name) == "string" and name:find("^Blizzard_") then Win.DressAll() end
end)
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function() if waiting then waiting = false Win.DressAll() end end)
ns.On("ACCENT_CHANGED", function()
	if InCombatLockdown and InCombatLockdown() then waiting = true return end
	for f in pairs(dressed) do Win.Paint(f) end
end)
ns.On("SETTING_CHANGED", function(path)
	if type(path) == "string" and (path:find("^windows%.") or path == "look.opacity" or path == "*") then
		if InCombatLockdown and InCombatLockdown() then waiting = true return end
		for f in pairs(dressed) do Win.Paint(f) end
	end
end)
