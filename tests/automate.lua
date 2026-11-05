-- Tests for the step list (one line per action), automation at NPCs, the
-- quest item button and the leveling tracker. Loaded by tests/run.lua.
local h = ...
local test, eq, near, ok, fresh = h.test, h.eq, h.near, h.ok, h.fresh

-- Deathknell's first quests (real ids and people from the data).
local ROUTE = {
	id = "test/auto", title = "Automation (test)", category = "Leveling", map = 1420,
	levels = { 1, 6 }, faction = "Horde", races = { "Scourge" },
	steps = {
		{ title = "The crypt", { "accept", 363, who = "Undertaker Mordo" } },
		{ note = "Up the path to the chapel.", { "turnin", 363, who = "Shadow Priest Sarvis" }, { "accept", 364, who = "Shadow Priest Sarvis" } },
		{ title = "Zombies", { "complete", 364 }, { "note", "Use Test Charm" } },
		{ title = "Travel", { "note", "Fly to Brill" }, { "bind", "Brill", who = "Innkeeper Renee" }, { "note", "Train new spells at your class trainer" } },
	},
}

local function start(setup)
	local stub, ns = fresh()
	stub.player.level = 2
	if setup then setup(stub) end
	stub.moveTo(1420, 30.2, 71.6)
	stub.login()
	ok(Pathwise.RegisterRoute(ROUTE), "route registers")
	ns.Engine.SetRoute(ROUTE.id)
	return stub, ns
end

local function kinds(lines)
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = l.kind end
	return table.concat(out, ",")
end

test("steps: a card for what to do now, then the steps as one line per action", function()
	local stub, ns = start()
	local v = ns.Guide.View()
	eq(kinds(v.card), "talk,accept", "card: talk to the giver, then accept")
	eq(v.card[1].name, "Undertaker Mordo")
	eq(v.card[2].name, ns.Quests.Name(363))
	eq(#v.steps, 3, "three steps listed by default")
	ok(v.steps[1].current and v.steps[1].index == 1)
	eq(kinds(v.steps[2].lines), "talk,accept", "a hand-in for a quest not taken yet is not listed")
	eq(v.steps[2].note, "Up the path to the chapel.")
	ok(ns.Guide.LineText(v.card[1]):find("|cff%x%x%x%x%x%xUndertaker Mordo|r"), "the name picked out in colour")
	stub.accept(363)
	v = ns.Guide.View()
	eq(v.steps[1].index, 2, "on to Sarvis")
	eq(kinds(v.steps[1].lines), "talk,turnin,accept", "one 'Talk to' for two actions at the same person")
	stub.turnin(363)
	v = ns.Guide.View()
	local lines = v.steps[1].lines
	ok(lines[2].done and not lines[3].done, "handed in: done; the next accept still to do")
	ok(not lines[1].done, "Talk to stays open while something at that person is")
	ns.Set("guide.ahead", 1)
	ns.Engine.Update()
	eq(#ns.Guide.View().steps, 1, "Steps listed: 1")
end)

test("steps: an open objective is listed under its quest with its count", function()
	local stub, ns = start()
	stub.accept(363) stub.turnin(363)
	stub.accept(364, { { text = "Mindless Zombie slain: 3/8", numFulfilled = 3, numRequired = 8, finished = false } })
	local v = ns.Guide.View()
	eq(kinds(v.card), "complete,objective,note", "the whole step: the quest, its objective, the note with it")
	eq(v.card[2].have, 3)
	eq(v.card[2].need, 8)
	ok(_G.PathwiseGuide.shown, "the window draws it")
end)

test("automation: the route's quests are picked, accepted and handed in; Shift or Off leaves them", function()
	local picked, accepted, completed, reward
	local stub, ns = start(function()
		C_GossipInfo = {
			GetActiveQuests = function() return stub_active or {} end,
			GetAvailableQuests = function() return { { questID = 999 }, { questID = 363 } } end,
			SelectAvailableQuest = function(id) picked = id end,
			SelectActiveQuest = function(id) picked = id end,
		}
		function GetQuestID() return current_quest end
		function AcceptQuest() accepted = current_quest end
		function IsQuestCompletable() return true end
		function CompleteQuest() completed = current_quest end
		function GetQuestReward(i) reward = i end
	end)
	stub.fire("GOSSIP_SHOW")
	eq(picked, 363, "the route's quest, not another")
	current_quest = 363
	stub.fire("QUEST_DETAIL")
	eq(accepted, 363)
	current_quest, accepted = 999, nil
	stub.fire("QUEST_DETAIL")
	eq(accepted, nil, "a quest the route does not take is left to you")

	stub.accept(363)
	stub_active = { { questID = 363, isComplete = true } }
	picked = nil
	stub.fire("GOSSIP_SHOW")
	eq(picked, 363, "hand-ins first")
	current_quest = 363
	stub.fire("QUEST_PROGRESS")
	eq(completed, 363)
	stub.fire("QUEST_COMPLETE")
	eq(reward, 0, "no choice: taken")

	stub.choices = { 101, 102 }
	reward = nil
	stub.fire("QUEST_COMPLETE")
	eq(reward, nil, "a choice: yours, with Rewards off")
	ns.Set("auto.rewards", true)
	Pathwise.Suite.SetRewardChooser(function(links) return 2 end)
	stub.fire("QUEST_COMPLETE")
	eq(reward, 2, "Rewards on: the recommended one")

	picked = nil
	IsShiftKeyDown = function() return true end
	stub.fire("GOSSIP_SHOW")
	eq(picked, nil, "Shift held: hands off")
	IsShiftKeyDown = function() return false end
	ns.Set("auto.quests", false)
	stub.fire("GOSSIP_SHOW")
	eq(picked, nil, "switched off")
	C_GossipInfo, stub_active, current_quest = nil, nil, nil
end)

local function toTravel(stub)
	stub.accept(363) stub.turnin(363)
	stub.accept(364) stub.turnin(364)
end

test("automation: fly where the step says, set the hearthstone, train when asked", function()
	local flew, confirmed, bought = nil, false, {}
	local stub, ns = start(function()
		local nodes = { { "Undercity, Tirisfal", "REACHABLE" }, { "Brill, Tirisfal Glades", "REACHABLE" }, { "Deathknell", "CURRENT" } }
		function NumTaxiNodes() return #nodes end
		function TaxiNodeName(i) return nodes[i][1] end
		function TaxiNodeGetType(i) return nodes[i][2] end
		function TakeTaxiNode(i) flew = i end
		Enum.PlayerInteractionType = { Binder = 5 }
		C_PlayerInteractionManager = { ConfirmationInteraction = function(k) confirmed = k end, ClearInteraction = function() end }
		local services = { { "Frost Armor", "Rank 1", "available", 10 }, { "Fireball", "Rank 2", "available", 100000 }, { "Arcane Intellect", "Rank 1", "used", 0 } }
		function GetNumTrainerServices() return #services end
		function GetTrainerServiceInfo(i) return services[i][1], services[i][2], services[i][3] end
		function GetTrainerServiceCost(i) return services[i][4] end
		function BuyTrainerService(i) bought[#bought + 1] = services[i][1] services[i][3] = "used" end
	end)
	stub.money = 500
	toTravel(stub)
	eq(ns.Guide.View().title, "Travel")
	eq(ns.Automate.FlyTarget(), "Brill")
	stub.fire("TAXIMAP_OPENED")
	eq(flew, 2, "Brill's flight master")
	stub.fire("CONFIRM_BINDER", "Brill")
	eq(confirmed, 5, "make this your home: yes")
	stub.fire("TRAINER_SHOW")
	eq(#bought, 0, "training is off unless switched on")
	ns.Set("auto.train", true)
	stub.fire("TRAINER_SHOW")
	stub.fire("TRAINER_UPDATE")
	stub.fire("TRAINER_UPDATE")
	eq(table.concat(bought, ","), "Frost Armor", "what is available and affordable, once")
	TakeTaxiNode, C_PlayerInteractionManager, BuyTrainerService = nil, nil, nil
end)

test("quest item button: the step's quest item, set after combat, gone with the step", function()
	local stub, ns = start(function()
		C_QuestLog.GetLogIndexForQuestID = function(q) return stub_log_has and stub_log_has(q) and 1 or nil end
		function GetQuestLogSpecialItemInfo() return "|cffffffff|Hitem:9999::::::::|h[Test Charm]|h|r", "charm-icon" end
	end)
	stub_log_has = function(q) return q == 364 end
	stub.accept(363) stub.turnin(363)
	stub.combat = true
	stub.accept(364, { { text = "Mindless Zombie slain: 0/8", numFulfilled = 0, numRequired = 8, finished = false } })
	ns.Engine.Update()
	ok(not _G.PathwiseItemButton or not _G.PathwiseItemButton.shown, "not in combat")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	local b = _G.PathwiseItemButton
	ok(b and b.shown, "shown after combat")
	eq(b:GetAttribute("type"), "item")
	eq(b:GetAttribute("item"), "Test Charm")
	stub.progress(364, 1, 8)
	stub.turnin(364)
	ns.Engine.Update()
	ok(not b.shown, "the step is done: hidden")
	stub_log_has = nil
end)

test("leveling tracker: XP per hour, time to level, each level's time", function()
	local xp, max = 0, 1000
	local stub, ns = start(function()
		function UnitXP() return xp end
		function UnitXPMax() return max end
	end)
	local K = ns.Tracker
	stub.now = 120
	xp = 500
	stub.fire("PLAYER_XP_UPDATE")
	local s = K.Stats()
	near(s.xpPerHour, 15000, 1e-6, "500 XP in 2 minutes")
	near(s.secondsToLevel, 120, 1e-6, "500 more at that pace")
	ok(K.Line():find("15.0k XP/h", 1, true), K.Line())
	stub.now = 300
	stub.player.level = 3
	xp, max = 100, 1400
	stub.fire("PLAYER_XP_UPDATE")
	stub.fire("PLAYER_LEVEL_UP", 3)
	eq(K.Stats().gained, 1100, "the rest of level 2 and 100 into 3")
	local levels = K.Levels()
	eq(levels[1].level, 2)
	near(levels[1].seconds, 300, 1e-6)
	stub.fire("TIME_PLAYED_MSG", 5000, 40)
	near(K.LevelSeconds(), 40, 1e-6, "/played sets the level's time right")
	ns.Panels.Open("leveling")
	ok(_G.PathwisePanel.shown, "the Times panel")
	UnitXP, UnitXPMax = nil, nil
end)

test("one action per step: a place's step split, a person's actions kept together, notes with the next action", function()
	local _, ns = fresh()
	local r = ns.Engine.SplitRoute({ id = "t", category = "Leveling", steps = {
		{ title = "Brill", note = "The town.",
			{ "note", "Hearth to Brill" },
			{ "turnin", 363, who = "Gretchen Dedmar" }, { "accept", 364, who = "Gretchen Dedmar" },
			{ "accept", 376, who = "Magistrate Sevren" },
			{ "complete", 364 }, { "complete", 376 },
			{ "note", "Sell and repair" } },
	} })
	eq(#r.steps, 4, "Gretchen, Sevren, two quests")
	eq(r.steps[1][1][1], "note", "the note goes with the next action")
	eq(#r.steps[1], 3, "note, hand in and accept at Gretchen")
	eq(r.steps[1].note, "The town.", "the place's note on its first step")
	eq(r.steps[2].note, nil)
	eq(r.steps[2].title, "Brill", "every part keeps the place's name")
	eq(r.steps[4][2][2], "Sell and repair", "a last note goes with the last action")
	eq(r.split[1][1], 1)
	eq(r.split[1][2], 4)
	eq(r.goalAt[1][5][1], 3, "goal 5 (complete 364) is step 3")
end)

test("one action per step: marks saved by place move to the steps the place became", function()
	local stub, ns = fresh()
	local id = "test/marks"
	ok(Pathwise.RegisterRoute({ id = id, title = "Marks (test)", category = "Leveling", map = 1420, levels = { 1, 6 }, steps = {
		{ { "accept", 363, who = "Undertaker Mordo" }, { "accept", 376, who = "Novice Elreth" }, { "complete", 364 } },
		{ { "accept", 3901, who = "Shadow Priest Sarvis" } },
	} }))
	local c = ns.CharState()
	c.guide = { route = id, stepsDone = { [id .. ":2"] = true }, reached = { [id .. ":1:3"] = true } }
	stub.login()
	local g = ns.Engine.State()
	eq(g.layout, 2)
	ok(g.stepsDone[id .. ":4"], "place 2 is step 4 now")
	ok(not g.stepsDone[id .. ":2"], "not the new step 2")
	ok(g.reached[id .. ":3:1"], "place 1's third goal is step 3's first")
end)

test("map: the steps ahead are numbered pins where each begins, the current one too", function()
	local stub, ns = start()
	local labels = {}
	for _, p in ipairs(ns.Engine.Pins()) do if p.label then labels[#labels + 1] = p.kind .. p.label end end
	local text = table.concat(labels, ",")
	ok(text:find("lead1", 1, true), text)
	ok(text:find("step2", 1, true), "the next step numbered: " .. text)
	ns.Set("pins.stepNumbers", false)
	labels = {}
	for _, p in ipairs(ns.Engine.Pins()) do if p.kind == "step" then labels[#labels + 1] = p end end
	eq(#labels, 0, "switched off")
end)
