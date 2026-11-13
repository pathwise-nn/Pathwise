-- Translations. Pathwise is written in English; a translation is a table of
-- English text -> its translation (Locales/<code>.lua), used only when the
-- game runs in that language (GetLocale()). Everything else stays English:
-- quest, item and NPC names come from the game and the data as they are.
--
--   ns.L(text)             the text in the player's language, else as given
--   ns.F(template, ...)    ns.L(template):format(...); a translation may put
--                          the values in another order: { "text", 2, 1 }
--   ns.U(text)             upper case, Cyrillic too (string.upper in WoW only
--                          knows Latin letters)
--   ns.HookText(fs)        a font string that translates what it is given
--   ns.Tip.SetText / AddLine (tooltip, text, ...)   the same for tooltips
--   ns.AddLocale(code, table, fallback)             Locales/<code>.lua use it
--   ns.Translated()        whether a translation is in use
--
-- With no translation for the game's language (English, or one not done
-- yet) all of these give the text back as it was: nothing changes.

local ADDON, ns = ...
local type, select, pairs = type, select, pairs

ns.GAME_LOCALE = GetLocale and GetLocale() or "enUS"

local T, fallback -- the translation in use, and its last resort for unknown text

-- code: the game's language code, or a list of them (esES and esMX share
-- one Spanish). Every entry also gets its ALL CAPS form (headings, labels),
-- unless the table gives one of its own.
function ns.AddLocale(code, tbl, fb)
	local match = code == ns.GAME_LOCALE
	if type(code) == "table" then
		for _, c in ipairs(code) do if c == ns.GAME_LOCALE then match = true end end
	end
	if not match or type(tbl) ~= "table" then return false end
	T = T or {}
	for k, v in pairs(tbl) do if T[k] == nil then T[k] = v end end
	for k, v in pairs(tbl) do
		local K = k:upper()
		-- Not templates: their %s and %d would turn into %S and %D.
		if K ~= k and T[K] == nil and not k:find("%", 1, true) then
			if type(v) == "table" then
				local up = { ns.U(v[1]) }
				for i = 2, #v do up[i] = v[i] end
				T[K] = up
			else
				T[K] = ns.U(v)
			end
		end
	end
	if fb then fallback = fb end
	return true
end

-- Languages whose letters Pathwise's typeface (Inter) does not have: there
-- Pathwise writes in the game's own font (Theme/Signature.lua).
ns.GAME_FONT_LOCALES = { koKR = true, zhCN = true, zhTW = true }

function ns.Translated() return T ~= nil end
-- The translation in use (for the tests), or nil.
function ns.LocaleEntries() return T end

local miss, missCount = {}, 0
local function lookup(s)
	local t = T[s]
	if t ~= nil then return t end
	if miss[s] or not fallback then return nil end
	t = fallback(s)
	if t then T[s] = t return t end
	missCount = missCount + 1
	if missCount > 4000 then miss, missCount = {}, 0 end
	miss[s] = true
	return nil
end

function ns.L(s)
	if not T or type(s) ~= "string" then return s end
	local t = lookup(s)
	if type(t) == "table" then return t[1] end
	return t or s
end

function ns.F(template, ...)
	if not T then return template:format(...) end
	local t = lookup(template)
	if type(t) == "table" then
		local args = {}
		for i = 2, #t do args[i - 1] = (select(t[i], ...)) end
		return t[1]:format(unpack(args, 1, #t - 1))
	end
	return (t or template):format(...)
end

-- Upper case for the letters string.upper leaves alone: Cyrillic, and the
-- accented Latin of German, French, Spanish, Portuguese and Italian.
local UP = {}
do
	local lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюяàáâãäåæçèéêëìíîïñòóôõöøùúûüýœ"
	local upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÑÒÓÔÕÖØÙÚÛÜÝŒ"
	local lo, up = {}, {}
	for ch in lower:gmatch("[\192-\255][\128-\191]*") do lo[#lo + 1] = ch end
	for ch in upper:gmatch("[\192-\255][\128-\191]*") do up[#up + 1] = ch end
	for i = 1, #lo do UP[lo[i]] = up[i] end
end
function ns.U(s)
	if type(s) ~= "string" then return s end
	if not T then return s:upper() end
	-- Latin by hand too: upper-casing whole bytes can mangle UTF-8 on some systems.
	return (s:gsub("[a-z]", string.upper):gsub("[\195\197\208\209][\128-\191]", UP))
end

-- A font string that translates its text (only when a translation is in use).
local hooked = setmetatable({}, { __mode = "k" })
function ns.HookText(fs)
	if not T or not fs or hooked[fs] then return fs end
	hooked[fs] = true
	local set = fs.SetText
	fs.SetText = function(self, text, ...) return set(self, ns.L(text), ...) end
	return fs
end

ns.Tip = {
	SetText = function(tt, text, ...) return tt:SetText(ns.L(text), ...) end,
	AddLine = function(tt, text, ...) return tt:AddLine(ns.L(text), ...) end,
}
