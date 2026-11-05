-- Pathwise automation: the talking to NPCs the guide already says to do,
-- done for you, only for what the route asks for, and never while Shift is
-- held (hold it when you talk to someone to do it yourself).
--   * quests: at a giver, the route's quests are picked, accepted, handed in;
--     a reward is taken when there is no choice to make, or (Rewards on) the
--     one Pathwise Gear recommends
--   * flight masters: when the step says "Fly to X", you fly there
--   * innkeepers: when the step says to make an inn your home, the game's
--     "make this your home?" question is answered yes
--   * trainers (off unless switched on): when the step is training, every
--     spell or rank you can afford is learned
--
-- Game functions (Forever's own UI code uses each: QuestFrame.lua,
-- TaxiFrame.xml, Blizzard_TrainerUI.lua, StaticPopup's CONFIRM_BINDER, and
-- GossipInfoDocumentation): C_GossipInfo.GetActiveQuests / GetAvailableQuests
-- / SelectActiveQuest / SelectAvailableQuest; GetNumActiveQuests,
-- GetActiveQuestID, GetActiveTitle, GetNumAvailableQuests,
-- GetAvailableQuestInfo, SelectActiveQuest, SelectAvailableQuest (the old
-- greeting); GetQuestID, AcceptQuest, IsQuestCompletable, CompleteQuest,
-- GetNumQuestChoices, GetQuestItemLink, GetQuestMoneyToGet, GetQuestReward;
-- NumTaxiNodes, TaxiNodeName, TaxiNodeGetType, TakeTaxiNode;
-- C_PlayerInteractionManager.ConfirmationInteraction / ClearInteraction;
-- GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceCost,
-- BuyTrainerService.

local ADDON, ns = ...
local A = {}
ns.Automate = A

ns.Defaults("auto", {
	quests = true, -- accept and hand in the route's quests
	rewards = false, -- with a choice of rewards, take Pathwise Gear's pick
	fly = true, -- "Fly to X": fly there at the flight master
	bind = true, -- say yes to making the step's inn your home
	train = false, -- learn what the trainer has when the step is training
})

local function E() return ns.Engine end
local function call(fn, ...) if type(fn) == "function" then return fn(...) end end

-- Held Shift: hands off.
function A.Paused() return IsShiftKeyDown and IsShiftKeyDown() and true or false end
local function on(key) return ns.Get("auto." .. key) and not A.Paused() end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------

-- The route's quests to take and to hand in.
function A.ToAccept() return E() and E().Wanted("accept") or {} end
function A.ToTurnIn() return E() and E().Wanted("turnin") or {} end

-- A gossip window (the newer NPC dialogue): a quest to hand in first, then
-- one to take. -> what was picked ("turnin" | "accept"), or nil
function A.OnGossip()
	if not on("quests") then return nil end
	local G = C_GossipInfo
	if type(G) ~= "table" then return nil end
	local turnin = A.ToTurnIn()
	for _, q in ipairs(call(G.GetActiveQuests) or {}) do
		if q.isComplete and turnin[q.questID] then
			G.SelectActiveQuest(q.questID)
			return "turnin"
		end
	end
	local accept = A.ToAccept()
	for _, q in ipairs(call(G.GetAvailableQuests) or {}) do
		if accept[q.questID] then
			G.SelectAvailableQuest(q.questID)
			return "accept"
		end
	end
	return nil
end

-- The older greeting window (a list of quests, no gossip).
function A.OnGreeting()
	if not on("quests") then return nil end
	local turnin = A.ToTurnIn()
	for i = 1, call(GetNumActiveQuests) or 0 do
		local id = call(GetActiveQuestID, i)
		local _, complete = call(GetActiveTitle, i)
		if id and turnin[id] and complete then
			SelectActiveQuest(i)
			return "turnin"
		end
	end
	local accept = A.ToAccept()
	for i = 1, call(GetNumAvailableQuests) or 0 do
		local id = select(5, call(GetAvailableQuestInfo, i))
		if id and accept[id] then
			SelectAvailableQuest(i)
			return "accept"
		end
	end
	return nil
end

function A.OnDetail()
	if not on("quests") then return false end
	local id = call(GetQuestID)
	if id and A.ToAccept()[id] then
		AcceptQuest()
		return true
	end
	return false
end

function A.OnProgress()
	if not on("quests") then return false end
	local id = call(GetQuestID)
	if id and A.ToTurnIn()[id] and call(IsQuestCompletable) then
		CompleteQuest()
		return true
	end
	return false
end

-- The reward: none or one to take, or Pathwise Gear's pick when several
-- (Rewards on). A quest that costs money is left to you.
-- -> the choice taken (0 for none), or nil
function A.OnComplete()
	if not on("quests") then return nil end
	local id = call(GetQuestID)
	if not (id and A.ToTurnIn()[id]) then return nil end
	if (call(GetQuestMoneyToGet) or 0) > 0 then return nil end
	local n = call(GetNumQuestChoices) or 0
	local choice
	if n <= 1 then
		choice = n
	elseif ns.Get("auto.rewards") then
		local pick = Pathwise.Suite and Pathwise.Suite.RewardChooser and Pathwise.Suite.RewardChooser()
		if pick then
			local links = {}
			for i = 1, n do links[i] = call(GetQuestItemLink, "choice", i) end
			choice = pick(links)
		end
	end
	if not choice then return nil end
	GetQuestReward(choice)
	return choice
end

---------------------------------------------------------------------------
-- Flight masters
---------------------------------------------------------------------------

-- Where the step says to fly: "Fly to Rut'theran Village" -> the place.
function A.FlyTarget()
	for _, goal in ipairs(E() and E().OpenGoals() or {}) do
		local text = goal[1] == "note" and goal[2] or (goal[1] == "goto" and goal[5]) or nil
		local where = type(text) == "string" and text:match("^[Ff]ly to ([^%.,;:]+)")
		if where then return (where:gsub("%s+$", "")) end
	end
	return nil
end

-- The flight master's map: the node whose name begins with the place.
-- -> the node's index and name, or nil
function A.FindNode(where)
	if not where then return nil end
	local want = where:lower()
	for i = 1, call(NumTaxiNodes) or 0 do
		local name = call(TaxiNodeName, i)
		local kind = call(TaxiNodeGetType, i)
		if type(name) == "string" and kind == "REACHABLE" then
			local n = name:lower()
			if n:sub(1, #want) == want or n:find(want, 1, true) then return i, name end
		end
	end
	return nil
end

function A.OnTaxiMap()
	if not on("fly") then return nil end
	local where = A.FlyTarget()
	local i, name = A.FindNode(where)
	if not i then return nil end
	ns.Print(("flying to %s. Hold Shift when you talk to the flight master to choose yourself."):format(name))
	TakeTaxiNode(i)
	return name
end

---------------------------------------------------------------------------
-- Innkeepers
---------------------------------------------------------------------------

local function wantsBind()
	for _, goal in ipairs(E() and E().OpenGoals() or {}) do
		if goal[1] == "bind" then return goal end
	end
	return nil
end

function A.OnConfirmBinder()
	if not on("bind") or not wantsBind() then return false end
	local P = C_PlayerInteractionManager
	local kind = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Binder
	if not (type(P) == "table" and P.ConfirmationInteraction and kind) then return false end
	P.ConfirmationInteraction(kind)
	if P.ClearInteraction then P.ClearInteraction(kind) end
	if StaticPopup_Hide then StaticPopup_Hide("CONFIRM_BINDER") end
	return true
end

---------------------------------------------------------------------------
-- Trainers
---------------------------------------------------------------------------

local function wantsTraining()
	for _, goal in ipairs(E() and E().OpenGoals() or {}) do
		local v = goal[1]
		if v == "train" or v == "learn" then return true end
		if v == "note" and type(goal[2]) == "string" and goal[2]:match("^Train") then return true end
	end
	return false
end

-- One thing at a time: the list changes after each, and TRAINER_UPDATE
-- brings us back for the next. Each is tried once per visit, so one the game
-- refuses is not asked for again and again. -> the service learned, or nil
local tried = {}
function A.OnTrainer(fresh)
	if fresh then tried = {} end
	if not on("train") or not wantsTraining() then return nil end
	local money = call(GetMoney) or 0
	for i = 1, call(GetNumTrainerServices) or 0 do
		local name, rank, kind = call(GetTrainerServiceInfo, i)
		local key = tostring(name) .. ":" .. tostring(rank)
		local cost = call(GetTrainerServiceCost, i) or 0
		if kind == "available" and cost <= money and not tried[key] then
			tried[key] = true
			BuyTrainerService(i)
			return name or i
		end
	end
	return nil
end

ns.RegisterEvent("GOSSIP_SHOW", function() A.OnGossip() end)
ns.RegisterEvent("QUEST_GREETING", function() A.OnGreeting() end)
ns.RegisterEvent("QUEST_DETAIL", function() A.OnDetail() end)
ns.RegisterEvent("QUEST_PROGRESS", function() A.OnProgress() end)
ns.RegisterEvent("QUEST_COMPLETE", function() A.OnComplete() end)
ns.RegisterEvent("TAXIMAP_OPENED", function() A.OnTaxiMap() end)
ns.RegisterEvent("CONFIRM_BINDER", function() A.OnConfirmBinder() end)
ns.RegisterEvent("TRAINER_SHOW", function() A.OnTrainer(true) end)
ns.RegisterEvent("TRAINER_UPDATE", function() A.OnTrainer() end)
