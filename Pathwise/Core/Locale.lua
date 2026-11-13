-- Translations. Pathwise is written in English; a translation is a table of
-- English text -> its translation (Locales/<code>.lua). Everything else stays
-- as it comes: quest, item and NPC names come from the game and the data.
--
-- Which language: Settings > Language ("ui.language"): the game's language
-- (GetLocale(), the usual) or one picked by the player. WoW loads saved
-- settings after the addon's files have run, so every Locales file only
-- registers its table here; once the settings have loaded (LOADED) the one
-- language in use is put together and the rest are let go. A change takes
-- effect after a reload.
--
--   ns.L(text)             the text in the chosen language, else as given
--   ns.F(template, ...)    ns.L(template):format(...); a translation may put
--                          the values in another order: { "text", 2, 1 }
--   ns.U(text)             upper case, Cyrillic and accented Latin too
--                          (string.upper in WoW only knows A-Z)
--   ns.HookText(fs)        a font string that translates what it is given
--   ns.Tip.SetText / AddLine (tooltip, text, ...)   the same for tooltips
--   ns.AddLocale(codes, table, fallback, extras)    Locales/<code>.lua use it;
--                          extras = { units = "metres", comma = true, translator = "Name" }
--   ns.Translated()        whether a translation is in use
--   ns.LANGUAGES, ns.Language(), ns.LanguageName(code)   for Settings
--
-- English (or a language with no translation yet): all of these give the
-- text back as it was, so nothing changes.

local ADDON, ns = ...
local type, select, pairs, ipairs = type, select, pairs, ipairs

ns.GAME_LOCALE = GetLocale and GetLocale() or "enUS"
ns.Defaults("ui", { language = "auto" })

-- Languages whose letters Pathwise's typeface (Inter) does not have: there
-- Pathwise writes in the game's own font (Theme/Signature.lua). Their
-- translations can only be shown on a client in that language (other
-- clients' fonts have none of their letters either).
ns.GAME_FONT_LOCALES = { koKR = true, zhCN = true, zhTW = true }

-- What Settings > Language offers, each in its own language.
ns.LANGUAGES = {
	{ "auto", "Game language" }, { "enUS", "English" }, { "deDE", "Deutsch" }, { "frFR", "Français" },
	{ "esES", "Español" }, { "ptBR", "Português (Brasil)" }, { "itIT", "Italiano" }, { "ruRU", "Русский" },
	{ "koKR", "한국어" }, { "zhCN", "简体中文" }, { "zhTW", "繁體中文" },
}
function ns.LanguageName(code)
	for _, l in ipairs(ns.LANGUAGES) do if l[1] == code then return l[2] end end
	return code
end
-- Whether a language can be picked on this client.
function ns.LanguageOffered(code)
	if ns.GAME_FONT_LOCALES[code] then return ns.GAME_LOCALE == code end
	return true
end

local T, fallback -- the translation in use, and its last resort for unknown text
local pending = {} -- code -> { { table, fallback, extras }, ... } until the settings load

function ns.AddLocale(codes, tbl, fb, extras)
	if type(tbl) ~= "table" or not pending then return false end
	if type(codes) ~= "table" then codes = { codes } end
	for _, c in ipairs(codes) do
		pending[c] = pending[c] or {}
		table.insert(pending[c], { tbl, fb, extras })
	end
	return true
end

-- The language the settings ask for (the game's when "auto" or unknown), and
-- whether it can be shown here.
function ns.Language()
	local want = ns.Get and ns.Get("ui.language") or "auto"
	if want == nil or want == "auto" or not ns.LanguageOffered(want) then return ns.GAME_LOCALE end
	return want
end
ns.ACTIVE_LOCALE = "enUS"

-- Puts language `code` together from its tables: their entries, and each
-- entry's ALL CAPS form (headings, labels) unless a table gives its own.
function ns.UseLocale(code)
	T, fallback = nil, nil
	ns.DEFAULT_UNITS, ns.DECIMAL_COMMA, ns.TRANSLATOR = nil, nil, nil
	ns.ACTIVE_LOCALE = code
	local parts = pending and pending[code]
	if not parts then return false end
	T = {}
	for _, part in ipairs(parts) do
		local tbl, fb, extras = part[1], part[2], part[3]
		for k, v in pairs(tbl) do if T[k] == nil then T[k] = v end end
		if fb then fallback = fb end
		if extras then
			if extras.units then ns.DEFAULT_UNITS = extras.units end
			if extras.comma then ns.DECIMAL_COMMA = true end
			if extras.translator then ns.TRANSLATOR = extras.translator end
		end
	end
	local caps = {}
	for k, v in pairs(T) do
		local K = k:upper()
		-- Not templates: their %s and %d would turn into %S and %D.
		if K ~= k and T[K] == nil and not k:find("%", 1, true) then
			if type(v) == "table" then
				local up = { ns.U(v[1]) }
				for i = 2, #v do up[i] = v[i] end
				caps[K] = up
			else
				caps[K] = ns.U(v)
			end
		end
	end
	for K, v in pairs(caps) do T[K] = v end
	return true
end

-- Once the settings have loaded: the language in use, and the others let go.
ns.On("LOADED", function()
	ns.UseLocale(ns.Language())
	pending = nil
end)

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
	-- Latin by hand too: upper-casing whole bytes can mangle UTF-8 on some systems.
	return (s:gsub("[a-z]", string.upper):gsub("[\195\197\208\209][\128-\191]", UP))
end

-- A font string that translates its text. Every one is hooked: the language
-- is chosen after most of them are made.
local hooked = setmetatable({}, { __mode = "k" })
function ns.HookText(fs)
	if not fs or hooked[fs] then return fs end
	hooked[fs] = true
	local set = fs.SetText
	fs.SetText = function(self, text, ...) return set(self, ns.L(text), ...) end
	return fs
end

ns.Tip = {
	SetText = function(tt, text, ...) return tt:SetText(ns.L(text), ...) end,
	AddLine = function(tt, text, ...) return tt:AddLine(ns.L(text), ...) end,
}
