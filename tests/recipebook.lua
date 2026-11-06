-- Tests for the professions recipe book (Professions/RecipeBook.lua, the
-- Recipe book panels): the data, the plan by faction and path, colours,
-- materials, recipe sources, ranks and trainers, and the pages.
local h = ...
local test, eq, ok, fresh = h.test, h.eq, h.ok, h.fresh

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

-- An Undead Mage (Horde) in Tirisfal with `skills` = { [line] = { rank, cap } }.
local function character(skills, setup)
	local stub, ns = fresh()
	stub.player.level = 20
	for line, s in pairs(skills or {}) do stub.skills[line] = s end
	if setup then setup(stub) end
	stub.moveTo(1420, 60, 52)
	stub.login()
	return stub, ns
end

test("recipe book data: twelve professions, each planned 1-300 for both factions", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	eq(#ns.Data.recipebook.books, 12)
	for _, prof in ipairs(ns.Professions.LIST) do
		local b = RB.Book(prof.key)
		ok(b, "a book for " .. prof.key)
		eq(b.line, prof.line, prof.key .. " skill line")
		for _, side in ipairs({ "A", "H" }) do
			local steps = RB.Steps(b, nil, side)
			eq(steps[1].from, 1, prof.key .. " " .. side .. " starts at 1")
			eq(steps[#steps].to, 300, prof.key .. " " .. side .. " ends at 300")
			for i = 2, #steps do eq(steps[i].from, steps[i - 1].to, prof.key .. " " .. side .. " no gap") end
			for _, s in ipairs(steps) do
				for _, e in ipairs(RB.Entries(s, side)) do
					eq(e.spell.line, prof.line, e.spell.name .. " is a " .. prof.key .. " recipe")
				end
			end
		end
		local caps = {}
		for _, r in ipairs(b.ranks) do caps[#caps + 1] = r.cap end
		eq(table.concat(caps, ","), "75,150,225,300", prof.key .. " ranks")
	end
end)

test("recipe book data: the addon's copy matches data/recipebook.lua (build.lua was rerun)", function()
	local _, ns = fresh()
	local R = dofile("data/recipebook.lua")
	local D = ns.Data.recipebook
	eq(D.build, R.build, "client build")
	for id, s in pairs(R.spells) do
		ok(D.spells[id], "spell " .. id .. " in Data.lua")
		eq(D.spells[id][1], s[1], "name of " .. id)
	end
	for id in pairs(D.spells) do ok(R.spells[id], "spell " .. id .. " in data/recipebook.lua") end
	eq(#D.books, #R.books)
end)

test("recipe book: the client's facts for a recipe and its colour by skill", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local s = RB.Spell(7183)
	eq(s.name, "Elixir of Minor Defense")
	eq(s.yellow, 55)
	eq(s.grey, 95)
	eq(RB.Color(s, 1), "orange")
	eq(RB.Color(s, 60), "yellow")
	eq(RB.Color(s, 80), "green", "halfway from yellow to grey: the estimate")
	eq(RB.Color(s, 95), "grey")
	local belt = RB.Spell(16647)
	eq(belt.learn, 240, "Imperial Plate Belt: learned at 240 in Forever (265 in Classic)")
	eq(RB.Color(belt, 230), "red", "not learnable yet")
	eq(RB.ColorText(belt), "learn 240, yellow " .. belt.yellow .. ", grey " .. belt.grey)
end)

test("recipe book: a step's materials in all", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local steps = RB.Steps(RB.Book("alchemy"), nil, "H")
	local s = steps[RB.At(steps, 30)]
	eq(s.from, 10)
	eq(s.to, 55)
	local mats = RB.Materials(RB.Entries(s, "H"))
	eq(#mats, 3)
	local by = {}
	for _, m in ipairs(mats) do by[m.name] = m.count end
	eq(by["Silverleaf"], 45)
	eq(by["Peacebloom"], 45)
	eq(by["Empty Vial"], 45)
	eq(RB.EntryText(RB.Entries(s, "H")[1]), "45x Elixir of Minor Defense")
end)

test("recipe book: another way through some ranges replaces the main steps there", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local b = RB.Book("enchanting")
	eq(table.concat(RB.Paths(b), ","), "Strange Dust")
	local main = RB.Steps(b, nil, "H")
	local dust = RB.Steps(b, "Strange Dust", "H")
	local function at(steps, skill) return RB.Entries(steps[RB.At(steps, skill)], "H")[1].spell.id end
	eq(at(main, 80), 7426, "main: Minor Absorption")
	eq(at(dust, 80), 7457, "Strange Dust: Minor Stamina bracers")
	eq(at(main, 160), at(dust, 160), "the same again from 150")
	eq(dust[1].from, 1)
	eq(dust[#dust].to, 300)
end)

test("recipe book: steps for one faction (Skinning) and a pick of dishes by faction (Cooking)", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local skin = RB.Book("skinning")
	local h1 = RB.Steps(skin, nil, "H")[1]
	local a1 = RB.Steps(skin, nil, "A")[1]
	eq(ns.Data.npcs[h1.mobs[1]][1], "Mottled Boar")
	eq(ns.Data.npcs[a1.mobs[1]][1], "Young Wolf")
	local cook = RB.Steps(RB.Book("cooking"), nil, "H")[1]
	local horde, alliance = {}, {}
	for _, e in ipairs(RB.Entries(cook, "H")) do horde[e.spell.id] = true end
	for _, e in ipairs(RB.Entries(cook, "A")) do alliance[e.spell.id] = true end
	ok(horde[15935] and not alliance[15935], "Crispy Bat Wing: Horde")
	ok(alliance[6412] and not horde[6412], "Kaldorei Spider Kabob: Alliance")
	ok(horde[7751] and alliance[7751], "Brilliant Smallfish: both")
end)

test("recipe book: where a recipe comes from, this faction's vendors", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local spell = RB.Spell(7259) -- Nature Protection Potion
	local src = RB.Sources(spell, "H")[1]
	eq(src.name, "Recipe: Nature Protection Potion")
	local names = {}
	for _, v in ipairs(src.vendors) do names[v.name] = true end
	ok(names["Bronk"] and names["Glyx Brewright"], "Horde and neutral vendors")
	ok(not names["Logannas"], "not the Alliance one")
	ok(RB.SourceText(src):find("^sold by "), RB.SourceText(src))
	local plans = RB.Sources(RB.Spell(16647), "H")[1]
	ok(#plans.quests > 0, "Imperial Plate Belt: a quest reward")
	ok(RB.SourceText(plans):find("reward of"), RB.SourceText(plans))
end)

test("recipe book: the next rank, its trainers for your faction, books and quests", function()
	local _, ns = fresh()
	local RB = ns.RecipeBook
	local r = RB.NextRank(RB.Book("alchemy"), 150)
	eq(r.rank, "Expert")
	eq(RB.RankText(r), "Expert (to 225): level 20, skill 125, 50s")
	local people = RB.People(r, "H")
	eq(#people, 1)
	eq(people[1].name, "Doctor Herbert Halsey")
	ok(people[1].id, "found in the data")
	eq(RB.People(r, "A")[1].name, "Ainethil")
	local fa = RB.Book("first-aid")
	eq(RB.ItemName(RB.NextRank(fa, 150).book), "Expert First Aid - Under Wraps")
	local triage = RB.NextRank(fa, 225)
	eq(triage.quest, "Triage")
	ok(triage.questIds and #triage.questIds == 2, "a Triage quest per faction")
	eq(RB.MoneyText(12345), "1g 23s 45c")
end)

test("recipe book page: from the profession page, the step for your skill, the next rank and the arrow", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Professions.Scan = function() end
	ns.Panels.Open("professions")
	ok(stub.clickLabelText("Alchemy"), "the profession in the list")
	ok(stub.clickLabelText("Recipe book"), "the page offers the recipe book")
	local texts = stub.texts()
	ok(contains(texts, "NOW: 55-65"), table.concat(texts, " | "))
	ok(contains(texts, "10x Minor Mana Potion"), "the craft for 55-65")
	ok(contains(texts, "now orange"), "its colour at your skill")
	ok(contains(texts, "Expert (to 225): level 20, skill 125, 50s"), "the next rank")
	ok(not contains(texts, "Ainethil"), "the Alliance trainer is left out")
	ok(stub.clickLabelText("Doctor Herbert Halsey"), "his row")
	local t = ns.Nav.Target()
	ok(t and t.title == "Doctor Herbert Halsey", "the arrow leads to him")
	ok(stub.clickLabelText("Show every step"), "every step")
	texts = stub.texts()
	ok(contains(texts, "OTHER RECIPES"), "the late recipes")
	ok(contains(texts, "Recipe: Nature Protection Potion"), "recipe sources")
	ok(contains(texts, "not tested there from 225"), "says what the guide could not test")
end)

test("recipe books: every profession, learned or not, with its trainers and first step", function()
	local stub, ns = character()
	ns.Panels.Open("professions")
	ok(stub.clickLabelText("Recipe books"), "from the professions list")
	ok(stub.clickLabelText("Mining"), "Mining, not learned")
	local texts = stub.texts()
	ok(contains(texts, "You don't have this profession"), table.concat(texts, " | "))
	ok(contains(texts, "NOW: 1-65"), "the first step")
	ok(contains(texts, "Copper Ore"), "what to mine")
	ok(contains(texts, "Where: Durotar"), "this faction's zones")
	ok(stub.clickInRow("Way", "Smelting"), "Smelting as another way")
	ok(contains(stub.texts(), "140x Smelt Copper"), "smelt bought ore instead")
end)
