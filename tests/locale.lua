-- Tests for translations (Core/Locale.lua, Locales/): English is unchanged,
-- and a Russian client gets Pathwise in Russian. Loaded by tests/run.lua.
local h = ...
local test, eq, ok, fresh = h.test, h.eq, h.ok, h.fresh

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

-- A fresh client in Russian.
local function russian()
	local stub, ns
	stub = dofile("./tests/stub.lua")
	PathwiseSettings, PathwiseCharSettings, Pathwise, SLASH_PATHWISE1 = nil, nil, nil, nil
	GetLocale = function() return "ruRU" end
	ns = stub.load(".")
	stub.login()
	return stub, ns
end

test("locale: an English client sees no change: no translation, yards, no translator credit", function()
	local stub, ns = fresh()
	stub.login()
	ok(not ns.Translated(), "no translation")
	eq(ns.L("Accent"), "Accent")
	eq(ns.F("Train %s %s", "Apprentice", "Tailoring"), "Train Apprentice Tailoring")
	eq(ns.U("abc"), "ABC")
	eq(ns.Nav.FormatYards(1240), "1,240 yd")
	ns.Panels.Open("about")
	ok(not contains(stub.texts(), "translation"), "no credit")
	ok(not contains(stub.texts(), "Designer"), "no credit")
end)

test("locale: a Russian client gets Pathwise in Russian, the credit, and metres", function()
	local stub, ns = russian()
	ok(ns.Translated(), "the Russian translation")
	eq(ns.L("Accent"), "Акцент")
	eq(ns.L("Text Pathwise does not know"), "Text Pathwise does not know", "unknown text stays English")
	-- Another word order: the profession first.
	eq(ns.F("Train %s %s", "Ученик", "Портняжное дело"), "Учиться: Портняжное дело (Ученик)")
	eq(ns.U("шаг"), "ШАГ", "capitals for Cyrillic")
	eq(ns.U("Маршрут прокачки · step"), "МАРШРУТ ПРОКАЧКИ · STEP", "capitals already there stay as they are")
	-- Route texts, and route titles made of zone names.
	eq(ns.L("Zeppelin to Grom'gol"), "Дирижабль в Гром'гол")
	eq(ns.L("Deadwind Pass & Dalaran"), "Перевал Мертвого Ветра и Даларан")
	-- Metres by default, with a decimal comma; yards when chosen.
	eq(ns.Nav.FormatYards(100), "91 м")
	eq(ns.Nav.FormatYards(2000), "1,8 км")
	ns.Set("nav.units", "yards")
	eq(ns.Nav.FormatYards(2000), "2,000 yd")
	-- The panels.
	ns.Panels.Open("settings")
	ok(contains(stub.texts(), "Расстояния"), "a setting in Russian")
	ns.Panels.Open("about")
	ok(contains(stub.texts(), "Русский перевод: Designer"), "the translator")
	GetLocale = nil
end)

test("locale: every Russian text takes the values its English text gives, no more", function()
	local _, ns = russian()
	local T = ns.LocaleEntries()
	local function specs(s)
		local n = 0
		for spec in s:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*[sdif]") do n = n + 1 end
		return n
	end
	local bad = {}
	for en, ru in pairs(T) do
		if type(ru) == "table" then
			if specs(ru[1]) ~= #ru - 1 or #ru - 1 > specs(en) then bad[#bad + 1] = en end
		elseif type(ru) == "string" and specs(ru) > specs(en) then
			bad[#bad + 1] = en .. " -> " .. ru
		end
	end
	table.sort(bad)
	ok(#bad == 0, "more values than the English gives: " .. table.concat(bad, " | "))
	GetLocale = nil
end)

-- A fresh client in any language.
local function client(code)
	local stub = dofile("./tests/stub.lua")
	PathwiseSettings, PathwiseCharSettings, Pathwise, SLASH_PATHWISE1 = nil, nil, nil, nil
	GetLocale = function() return code end
	local ns = stub.load(".")
	stub.login()
	return stub, ns
end

local function specs(s)
	local out = {}
	for spec in s:gsub("%%%%", ""):gmatch("%%[%-%+ #0]*%d*%.?%d*([sdif])") do out[#out + 1] = spec end
	return out
end

-- What each language says for a few texts, as its translation has it.
local SAMPLE = {
	deDE = { "Settings", "Einstellungen" }, frFR = { "Settings", "Paramètres" }, esES = { "Settings", "Opciones" },
	esMX = { "Settings", "Opciones" }, ptBR = { "Settings", "Configurações" }, itIT = { "Settings", "Impostazioni" },
	koKR = { "Settings", "설정" }, zhCN = { "Settings", "设置" }, zhTW = { "Settings", "設定" },
}

test("locale: every language: in use only in its own game, every text safe to fill, headings in capitals", function()
	for _, code in ipairs({ "deDE", "frFR", "esES", "esMX", "ptBR", "itIT", "koKR", "zhCN", "zhTW" }) do
		local stub, ns = client(code)
		ok(ns.Translated(), code .. ": translated")
		eq(ns.L(SAMPLE[code][1]), SAMPLE[code][2], code)
		ok(ns.L("Step %d of %d") ~= "Step %d of %d", code .. ": a template")
		eq(ns.L("Text Pathwise does not know"), "Text Pathwise does not know", code .. ": unknown text stays")
		-- Every translation fills safely: no more values than the English gives,
		-- in the same order unless it says another.
		for en, tr in pairs(ns.LocaleEntries()) do
			local want, have = specs(en), specs(type(tr) == "table" and tr[1] or tr)
			ok(#have <= #want, code .. ": too many values in: " .. en)
			if type(tr) ~= "table" then
				for i = 1, #have do ok(have[i] == want[i], code .. ": values out of order in: " .. en) end
			end
		end
		-- Capitals are made for the headings, accents and all.
		eq(ns.L("OBJECTIVES"), ns.U(ns.L("Objectives")), code .. ": capitals")
		ns.Panels.Open("settings")
		ok(#stub.texts() > 10, code .. ": the settings draw")
		GetLocale = nil
	end
end)

test("locale: capitals for accented letters, and Korean and Chinese in the game's own font", function()
	local _, ns = client("frFR")
	eq(ns.U("élève à côté"), "ÉLÈVE À CÔTÉ")
	eq(ns.U("übernehmen"), "ÜBERNEHMEN")
	eq(ns.Nav.FormatYards(2000), "1,8 km", "metres with a decimal comma")
	ok(ns.Theme.FONTS.regular:find("Inter"), "Inter has French letters")
	STANDARD_TEXT_FONT = "Fonts\\2002.TTF"
	local _, ko = client("koKR")
	eq(ko.Theme.FONTS.regular, "Fonts\\2002.TTF", "Korean: the game's font")
	eq(ko.Theme.FONTS.semibold, "Fonts\\2002.TTF")
	STANDARD_TEXT_FONT = nil
	local _, zh = client("zhCN")
	eq(zh.Theme.FONTS.regular, "Fonts\\ARKai_T.ttf", "no game font known: the Chinese client's own")
	GetLocale = nil
end)

test("locale: the language files are up to date with their lists", function()
	local p = io.popen("lua5.1 tools/locales/build.lua --check 2>&1")
	local out = p:read("*a")
	p:close()
	ok(out:find("every language is up to date"), out)
end)

-- A client in `code` whose saved settings pick `language` (as after a reload).
local function picked(code, language)
	local stub = dofile("./tests/stub.lua")
	PathwiseCharSettings, Pathwise, SLASH_PATHWISE1 = nil, nil, nil
	PathwiseSettings = { schema = 1, ui = { language = language } }
	GetLocale = function() return code end
	local ns = stub.load(".")
	stub.login()
	return stub, ns
end

test("language setting: the game's language unless the player picks another, after a reload", function()
	local _, de = picked("deDE", "enUS")
	ok(not de.Translated(), "a German client set to English: English")
	eq(de.L("Settings"), "Settings")
	eq(de.Nav.FormatYards(1240), "1,240 yd", "and yards")
	local _, en = picked("enUS", "deDE")
	eq(en.L("Settings"), "Einstellungen", "an English client set to German")
	eq(en.Nav.FormatYards(2000), "1,8 km", "German's metres")
	local _, ko = picked("enUS", "koKR")
	ok(not ko.Translated(), "Korean needs a Korean client: English stays")
	local _, ru = picked("enUS", "ruRU")
	eq(ru.TRANSLATOR, "Designer", "Russian, with its translator")
	ok(not ru.UseLocale("frFR"), "the other languages are let go once one is chosen")
	GetLocale = nil
end)

test("language setting: Settings > Language lists the languages; a pick asks for a reload", function()
	local stub, ns = picked("enUS", "auto")
	ns.Fire("SHOW_SETTINGS")
	ok(stub.clickLabelText("Language"), "the Language row")
	ok(ns.Panels.IsOpen("language"), "the language list")
	local texts = stub.texts()
	ok(contains(texts, "Game language (English)"), "the game's language first")
	ok(contains(texts, "Deutsch") and contains(texts, "Русский") and contains(texts, "Português (Brasil)"), "each in its own language")
	ok(not contains(texts, "한국어"), "Korean only on a Korean client")
	ok(stub.clickLabelText("Français"), "pick French")
	eq(ns.Get("ui.language"), "frFR")
	ok(contains(stub.texts(), "Reload to switch"), "it says to reload")
	ok(not ns.Translated(), "still English until the reload")
	GetLocale = nil
end)
