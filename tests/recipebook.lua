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

test("professions: a skill past a rank leaves that rank's steps behind, though their materials are used", function()
	local _, ns = character({ [333] = { 150, 150 }, [197] = { 95, 150 }, [185] = { 8, 75 } })
	local P = ns.Professions
	ns.Engine.Refresh()
	eq(P.Stage(P.BY_KEY.enchanting).rankMax, 150, "Enchanting 150/150: not Apprentice any more")
	eq(P.Stage(P.BY_KEY.tailoring).rankMax, 150, "Tailoring 95/150: the Journeyman stage")
	eq(P.Stage(P.BY_KEY.cooking).rankMax, 75, "Cooking 8/75: still Apprentice")
end)


-- The recipe book window's parts (UI/RecipeBook.lua).
local function bookFrames(ns) return ns.RecipeBookWindow.frames end

-- The shown button (a card, a chapter) whose name reads `name`.
local function named(stub, name)
	for _, f in ipairs(stub.frames) do
		local n = rawget(f, "name")
		if f.kind == "Button" and f.shown and type(n) == "table" and n.text == name and f.parent and f.parent.shown then return f end
	end
end

local function click(stub, name)
	local b = named(stub, name)
	if not b then return false end
	b.scripts.OnClick(b)
	return true
end

local function tabFor(ns, key)
	for _, b in ipairs(bookFrames(ns).tabs) do if b.prof.key == key then return b end end
end

test("recipe book: opens from the profession page on your rank's chapter, your step outlined", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Professions.Scan = function() end
	ns.Panels.Open("professions")
	ok(stub.clickLabelText("Alchemy"), "the profession in the list")
	ok(stub.clickLabelText("Recipe book"), "the page offers the recipe book")
	ok(_G.PathwiseRecipeBook and _G.PathwiseRecipeBook.shown, "the book opens in a window of its own")
	ok(_G.PathwisePanel.shown, "the profession page stays open beside the guide")
	local W = bookFrames(ns)
	eq(#W.tabs, 12, "a tab for every profession")
	ok(tabFor(ns, "alchemy").under.shown, "the Alchemy tab is the open one")
	ok(not tabFor(ns, "mining").under.shown)
	eq(tabFor(ns, "alchemy").icon.tex.texture, "Interface\\Icons\\Trade_Alchemy", "the game's own icon")
	local texts = stub.texts()
	ok(contains(texts, "RECIPE BOOK"), table.concat(texts, " | "))
	ok(contains(texts, "60 / 150"), "your skill")
	ok(contains(texts, "1-75  ·  you"), "the chapter you are in")
	ok(contains(texts, "Page 1 / 4"), "a page per rank")
	ok(contains(texts, "10-55  ·  45x  ·  done"), "a step behind you, marked done")
	local mana = named(stub, "Minor Mana Potion")
	ok(mana and mana.now, "your step (55-65) is the outlined card")
	ok(mana.here.shown, "YOU ARE HERE on it")
	ok(not named(stub, "Elixir of Minor Defense").now, "only one card is yours")
end)

test("recipe book: a card opens its step, the arrows turn steps and chapters", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Panels.OpenRecipeBook("alchemy")
	ok(click(stub, "Minor Mana Potion"), "the card")
	local texts = stub.texts()
	ok(contains(texts, "55-65"), table.concat(texts, " | "))
	ok(contains(texts, "MAKE"), "what to do")
	ok(contains(texts, "10x Minor Mana Potion"), "the craft and how many")
	ok(contains(texts, "now orange"), "its colour at your skill")
	ok(contains(texts, "You are here"))
	ok(contains(texts, "In all:"), "the materials")
	ok(contains(texts, "Step 3 / "), "which step of the plan")
	ok(stub.clickLabel(">"), "the next arrow")
	ok(contains(stub.texts(), "27x Elixir of Minor Fortitude"), "the next step")
	ok(stub.clickLabelText("< Apprentice"), "back to the chapter: 65-90 starts in Apprentice")
	ok(named(stub, "Minor Mana Potion"), "its cards again")
end)

test("recipe book: the chapter for a rank you have not trained says what it takes and where", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Panels.OpenRecipeBook("alchemy")
	ok(click(stub, "Expert"), "the Expert chapter")
	local texts = stub.texts()
	ok(contains(texts, "Train Expert (to 225): level 20, skill 125, 50s"), table.concat(texts, " | "))
	ok(contains(texts, "Doctor Herbert Halsey"), "the Horde trainer")
	ok(not contains(texts, "Ainethil"), "not the Alliance one")
	local W = bookFrames(ns)
	W.train.scripts.OnClick(W.train)
	local t = ns.Nav.Target()
	ok(t and t.title == "Doctor Herbert Halsey", "the arrow leads to him")
	ok(click(stub, "Journeyman"), "a rank already trained")
	ok(not W.train.shown, "no strip")
	ok(click(stub, "Artisan"), "the last chapter")
	texts = stub.texts()
	ok(contains(texts, "OTHER RECIPES"), "the late recipes")
	ok(contains(texts, "not tested there from 225"), "says what the guide could not test")
end)

test("recipe book: a profession you don't have, its trainer, gathering steps and another way", function()
	local stub, ns = character()
	ns.Panels.Open("professions")
	ok(stub.clickLabelText("Recipe books"), "from the professions list")
	ok(_G.PathwiseRecipeBook.shown)
	local mining = tabFor(ns, "mining")
	mining.scripts.OnClick(mining)
	ok(mining.under.shown, "Mining is open")
	ok(tabFor(ns, "alchemy").icon.tex.desaturated, "a profession you don't have is greyed")
	local texts = stub.texts()
	ok(contains(texts, "You don't have Mining. Learn it from a trainer."), table.concat(texts, " | "))
	ok(contains(texts, "Not learned"))
	ok(click(stub, "Copper Ore"), "the first step's card")
	texts = stub.texts()
	ok(contains(texts, "GATHER"), table.concat(texts, " | "))
	ok(contains(texts, "Where: Durotar"), "this faction's zones")
	ok(stub.clickLabel("Smelting"), "Smelting as another way")
	ok(click(stub, "Smelt Copper"), "its card")
	ok(contains(stub.texts(), "140x Smelt Copper"), "smelt bought ore instead")
end)

test("recipe book window: moved where you drag it and kept there; Escape closes it", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Panels.OpenRecipeBook("alchemy")
	local f = _G.PathwiseRecipeBook
	ok(f.shown, "open")
	local _, rel = f:GetPoint(1)
	ok(rel ~= _G.PathwiseGuide, "not anchored to the guide window")
	f.scripts.OnDragStart(f)
	f.scripts.OnDragStop(f)
	ok(type(ns.Get("recipebook.point")) == "table", "where it was left is kept")
	local esc
	for _, n in ipairs(UISpecialFrames) do if n == "PathwiseRecipeBook" then esc = true end end
	ok(esc, "Escape closes it")
	ns.Panels.CloseRecipeBook()
	ok(not f.shown, "closes")
	ok(not ns.Panels.RecipeBookShown())
	ns.Panels.OpenRecipeBook(nil)
	ok(tabFor(ns, "alchemy").under.shown, "nil opens the profession last open")
end)

test("recipe book window: resized from every edge and corner, within bounds, and kept", function()
	local stub, ns = character({ [171] = { 60, 150 } })
	ns.Panels.OpenRecipeBook("alchemy")
	local Book, f = ns.RecipeBookWindow, _G.PathwiseRecipeBook
	local H = bookFrames(ns).handles
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		ok(H[side], "a handle on " .. side)
	end
	ok(f.resizable, "resizable")
	eq(f.resizeBounds[1], Book.MIN_W)
	eq(f.w, Book.W)
	eq(f.h, Book.H)

	local function dragSide(side, dx, dy)
		f.left, f.top = 200, 700
		stub.cursor = { 500, 500 }
		H[side].scripts.OnMouseDown(H[side], "LeftButton")
		stub.cursor = { 500 + dx, 500 + dy }
		stub.advance(1 / 60)
		H[side].scripts.OnMouseUp(H[side], "LeftButton")
		local p = f.points[1]
		return f.w, f.h, p[4], p[5]
	end

	local w, h, x, y = dragSide("LEFT", -60, 0)
	eq(w, 680, "the left edge out: wider")
	eq(h, 560, "and no taller")
	eq(x, 140, "the left edge moved")
	eq(y, 700, "the top stayed")
	eq(ns.Get("recipebook.size")[1], 680, "the size is kept")

	f:SetSize(620, 560)
	w, h, x, y = dragSide("TOP", 0, 100)
	eq(h, 660, "the top edge up: taller")
	eq(y, 800, "the top moved up")
	eq(w, 620)

	f:SetSize(620, 560)
	w, h, x, y = dragSide("TOPLEFT", 50, -50)
	eq(w, 570, "the top-left corner in: narrower")
	eq(h, 510, "and shorter")
	eq(x, 250)
	eq(y, 650, "the bottom stayed where it was")

	f:SetSize(620, 560)
	w, h = dragSide("BOTTOMRIGHT", -1000, 1000)
	eq(w, Book.MIN_W, "no narrower than the minimum")
	eq(h, Book.MIN_H, "no shorter than the minimum")
	w, h = dragSide("BOTTOMRIGHT", 2000, -2000)
	eq(w, Book.MAX_W, "no wider than the maximum")
	eq(h, Book.MAX_H)

	local grip = H.BOTTOMRIGHT
	grip.scripts.OnMouseUp(grip, "RightButton")
	eq(ns.Get("recipebook.size"), nil, "right-click on the grip forgets the size")
	eq(f.w, Book.W, "and goes back to the size it opens at")
end)

test("recipe book window: the size comes back at login; tabs stay one row and cards fill the width", function()
	local stub, ns = character({ [171] = { 60, 150 } }, function()
		PathwiseSettings = { schema = 1, recipebook = { size = { 700, 600 } } }
	end)
	ns.Panels.OpenRecipeBook("alchemy")
	local f = _G.PathwiseRecipeBook
	eq(f.w, 700, "the width kept")
	eq(f.h, 600, "the height kept")

	local W = bookFrames(ns)
	local function rowEnd()
		local last = W.tabs[#W.tabs]
		local p = last.points[1]
		return p[4] + last.w, p[5]
	end
	local function check(width)
		f:SetSize(width, 600)
		f.scripts.OnSizeChanged(f)
		local right, y = rowEnd()
		ok(right <= width - 16, ("at %d wide the tabs end at %d"):format(width, right))
		eq(y, W.tabs[1].points[1][5], "one row")
	end
	check(ns.RecipeBookWindow.MIN_W)
	ok(W.tabSize < 34, "smaller tabs at the minimum width")
	check(620)
	check(ns.RecipeBookWindow.MAX_W)
	eq(W.tabSize, 34, "full size when there is room")

	-- Two cards side by side at 620, three at 900, one at the minimum.
	local function columns(width)
		f:SetSize(width, 600)
		f.scripts.OnSizeChanged(f)
		ns.RecipeBookWindow.Draw()
		local ys = {}
		for _, name in ipairs({ "Minor Arcane Elixir", "Elixir of Minor Defense", "Minor Mana Potion" }) do
			ys[#ys + 1] = named(stub, name).points[1][5]
		end
		local n = 1
		for i = 2, 3 do if ys[i] == ys[1] then n = n + 1 end end
		return n
	end
	eq(columns(620), 2)
	eq(columns(900), 3)
	eq(columns(ns.RecipeBookWindow.MIN_W), 1)
end)
