-- Pathwise Insights stands on its own. This is what it uses from the game,
-- and from Pathwise: Leveling & Professions when that is installed too:
--
--   ns.S      settings, messages and events (the kit, Kit/Core.lua), plus:
--     S.Guide       the guide's route and step (Pathwise only; else nil)
--     S.Quests      quest names: Pathwise's data, else the game's
--     S.Professions the character's professions and their ranks
--     S.Compat      where you stand in the world, in yards
--     S.VERSION     Pathwise's version (step numbers belong to it), or nil
--     S.DISCORD     the Pathwise Discord invite
--   ns.Look   the look: the kit's theme (Kit/Theme.lua, Kit/Widgets.lua),
--             with the logo, the faction crest and the type sizes Insights
--             uses.
--
-- Without Pathwise, everything is recorded but the guide's steps and routes.

local ADDON, ns = ...
local T = ns.Theme

local function pathwise() return _G.Pathwise and _G.Pathwise.Suite or nil end
ns.Pathwise = pathwise

local S = {
	Get = ns.Get, Set = ns.Set, Defaults = ns.Defaults,
	On = ns.On, Fire = ns.Fire, RegisterEvent = ns.RegisterEvent, Print = ns.Print,
	DISCORD = "https://discord.gg/hSDjBrG8EK",
}
ns.S = S
do
	local P = pathwise()
	S.VERSION = P and P.VERSION or nil
end

local function readable(v) return ns.Readable and ns.Readable(v) or v end

---------------------------------------------------------------------------
-- The guide (Pathwise only)
---------------------------------------------------------------------------

S.Guide = {}
function S.Guide.Route()
	local P = pathwise()
	if P and P.Guide then return P.Guide.Route() end
end
function S.Guide.Step()
	local P = pathwise()
	if P and P.Guide then return P.Guide.Step() end
end
function S.Guide.RouteInfo(id)
	local P = pathwise()
	if P and P.Guide then return P.Guide.RouteInfo(id) end
end
function S.Guide.Available()
	local P = pathwise()
	return P ~= nil and P.Guide ~= nil
end

---------------------------------------------------------------------------
-- Quest names: Pathwise's data, else the game (the quest log), else a number
---------------------------------------------------------------------------

S.Quests = {}
function S.Quests.Name(q)
	local P = pathwise()
	if P and P.Quests and P.Quests.Name then return P.Quests.Name(q) end
	local t = C_QuestLog and C_QuestLog.GetTitleForQuestID and readable(C_QuestLog.GetTitleForQuestID(q))
	if type(t) == "string" and t ~= "" then return t end
	return "Quest " .. tostring(q)
end

---------------------------------------------------------------------------
-- Professions: the game's skill lines
---------------------------------------------------------------------------

S.Professions = { LIST = {
	{ line = 171, name = "Alchemy" }, { line = 164, name = "Blacksmithing" }, { line = 333, name = "Enchanting" },
	{ line = 202, name = "Engineering" }, { line = 165, name = "Leatherworking" }, { line = 197, name = "Tailoring" },
	{ line = 182, name = "Herbalism" }, { line = 186, name = "Mining" }, { line = 393, name = "Skinning" },
	{ line = 185, name = "Cooking" }, { line = 129, name = "First Aid" }, { line = 356, name = "Fishing" },
}, BY_LINE = {} }
for _, p in ipairs(S.Professions.LIST) do S.Professions.BY_LINE[p.line] = p end

local function learned(info)
	if type(info) ~= "table" or info.isHeader then return nil end
	local rank, cap = tonumber(readable(info.rank)) or 0, tonumber(readable(info.maxRank)) or 0
	if rank == 0 and cap == 0 then return nil end
	return rank, cap
end

-- A skill line's rank and cap, or nil when the character does not have it.
function S.Professions.Rank(line)
	local C = C_SkillInfo
	if C and C.GetSkillLineInfoByID then
		local ok, info = pcall(C.GetSkillLineInfoByID, line)
		if ok then
			local rank, cap = learned(info)
			if rank then return rank, cap end
		end
	end
	if GetProfessions and GetProfessionInfo then
		local list = { GetProfessions() }
		for i = 1, 6 do
			if list[i] then
				local _, _, rank, cap, _, _, skillLine = GetProfessionInfo(list[i])
				if readable(skillLine) == line then return readable(rank) or 0, readable(cap) or 0 end
			end
		end
	end
	return nil
end

-- { { prof = { line, name }, rank, cap }, ... }
function S.Professions.Known()
	local out = {}
	for _, p in ipairs(S.Professions.LIST) do
		local rank, cap = S.Professions.Rank(p.line)
		if rank then out[#out + 1] = { prof = p, rank = rank, cap = cap or 0 } end
	end
	return out
end

---------------------------------------------------------------------------
-- Where you stand in the world: instance, north, west (yards)
---------------------------------------------------------------------------

S.Compat = {}
function S.Compat.PlayerWorldPosition()
	if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetWorldPosFromMapPos) then return nil end
	local map = readable(C_Map.GetBestMapForUnit("player"))
	if not map then return nil end
	local pos = C_Map.GetPlayerMapPosition(map, "player")
	if not pos then return nil end
	local ok, inst, world = pcall(C_Map.GetWorldPosFromMapPos, map, pos)
	if not (ok and world) then return nil end
	local north, west
	if world.GetXY then north, west = world:GetXY() else north, west = world.x, world.y end
	inst, north, west = readable(inst), readable(north), readable(west)
	if not (inst and north and west) then return nil end
	return inst, north, west
end

---------------------------------------------------------------------------
-- The look: the kit's theme, and what Insights adds to it
---------------------------------------------------------------------------

local L = setmetatable({}, { __index = T })
ns.Look = L

-- Two sizes the kit has no role for: a section title and a big number.
L.TYPE = setmetatable({ quest = { "semibold", 16, "text" }, number = { "semibold", 17, "text" } }, { __index = T.TYPE })

-- A text at a size of its own.
function L.TextAt(parent, weight, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if not fs:SetFont(T.FONTS[weight] or T.FONTS.regular, size, "") then fs:SetFont("Fonts\\FRIZQT__.TTF", size, "") end
	T.TextColor(fs, color or "text")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	fs:SetWordWrap(true)
	return fs
end

function L.Text(parent, role, color, layer)
	local own = rawget(L.TYPE, role)
	if own then return L.TextAt(parent, own[1], own[2], color or own[3]) end
	local fs = T.Text(parent, role, color, layer)
	fs:SetWordWrap(true)
	return fs
end

function L.Divider(parent)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetHeight(1)
	T.Paint(t, "divider")
	return t
end

-- The window ground (the kit's, at the look's opacity).
function L.RoundWindow(frame) T.Panel(frame) return frame end
function L.TrackScale() end
-- Whether to draw the game's own art (the preview has none).
function L.GameArt() return not PATHWISE_PREVIEW end

-- The Pathwise logo: the compass star, in the theme's colors.
function L.Logo(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 32, size or 32)
	holder.body = holder:CreateTexture(nil, "ARTWORK")
	holder.body:SetTexture(T.MEDIA .. "logo-body")
	holder.body:SetAllPoints()
	holder.glow = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.glow:SetTexture(T.MEDIA .. "logo-glow")
	holder.glow:SetAllPoints()
	function holder:Paint()
		local b, g = T.Color("text"), T.Color("accent")
		self.body:SetVertexColor(b[1], b[2], b[3], 1)
		self.glow:SetVertexColor(g[1], g[2], g[3], 1)
	end
	holder:Paint()
	return holder
end

-- The faction crest: a blue shield in a gold border (Alliance), a red
-- spiked arch on two blades (Horde), each with the Pathwise star.
local function hex(h)
	h = h:gsub("#", "")
	return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1 }
end
local CREST = {
	Alliance = { shape = "crest-alliance", fill = "#2A4FA8", edge = "#E4B96D", mark = "#F2D387" },
	Horde = { shape = "crest-horde", fill = "#9E2B25", edge = "#1E1414", mark = "#F2D387" },
}
function L.Crest(parent, size)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(size or 40, size or 40)
	holder.fill = holder:CreateTexture(nil, "ARTWORK")
	holder.fill:SetAllPoints()
	holder.edge = holder:CreateTexture(nil, "ARTWORK", nil, 1)
	holder.edge:SetAllPoints()
	holder.mark = holder:CreateTexture(nil, "OVERLAY")
	holder.mark:SetAllPoints()
	local function tint(tex, c) tex:SetVertexColor(c[1], c[2], c[3], 1) end
	function holder:SetFaction(f)
		local spec = CREST[f]
		local shape = spec and spec.shape or "crest-alliance"
		self.fill:SetTexture(T.MEDIA .. shape)
		self.edge:SetTexture(T.MEDIA .. shape .. "-edge")
		self.mark:SetTexture(T.MEDIA .. shape .. "-mark")
		tint(self.fill, spec and hex(spec.fill) or T.Color("bg2"))
		tint(self.edge, spec and hex(spec.edge) or T.Color("border"))
		tint(self.mark, spec and hex(spec.mark) or T.Color("accent"))
		self.faction = f
	end
	holder:SetFaction(nil)
	return holder
end
