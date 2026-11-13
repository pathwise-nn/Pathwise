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
