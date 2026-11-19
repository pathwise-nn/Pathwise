-- Pathwise's own route fixes, applied by tools/port/polestar.lua after it
-- converts a route. They are ours: each one is checked against Pathwise's
-- data (QuestieDB) or in game, says why, and is written in our own words.
-- Other guides' changes can be a lead for a fix, never its source: their
-- text and positions are not copied here.
--
-- FIXES[route id] = { fix, ... }. A goal is named { verb, quest } (verb "*"
-- for every goal of that quest). Each fix has a `why` and one of:
--   drop = goal                 remove the goal(s) from the route
--   move = goal, after = goal   move a goal to just after another goal
--                               (into that goal's step); `before` likewise
--   add = { goal, ... }, after = goal  new goals just after another goal
--                               (or `before`), into that goal's step
--   when = goal, k = "turnedin" | "onquest", q = quest
--                               the step holding `goal` shows only then
--   optional = goal             the goal(s) no longer hold the step
--   at = goal, place = { map, x, y }   where the goal leads; take the
--                               numbers from the data (Quests.Giver and the
--                               like), never from another guide
--   step = "title", note = "..."       a step's note, in our words
--   open = goal                 the goal(s) for every race and class (and a
--                               step that holds only them)
--   levels = { min, max }       the route's level range
-- A fix that no longer finds its goal or step stops the build, so a fix
-- never rots silently when the routes change.

local FIXES = {
	-- Ursangous's Paw, Sharptalon's Claw and Shadumbra's Head start quests
	-- (23, 2, 24) that need The Ashenvale Hunt (6383) handed in (the data's
	-- prerequisite); a player reported the trophies did not drop without it.
	-- This route never offered 6383 (only the Stonetalon route does), so a
	-- player who skipped that route hunted for nothing.
	["forever/horde/07-ashenvale"] = {
		{ why = "the hunts wait for The Ashenvale Hunt", when = { "have", 16303 }, k = "turnedin", q = 6383 },
		{ why = "the hunts wait for The Ashenvale Hunt", when = { "have", 16305 }, k = "turnedin", q = 6383 },
		{ why = "the hunts wait for The Ashenvale Hunt", when = { "have", 16304 }, k = "turnedin", q = 6383 },
		{ why = "Senani gives The Ashenvale Hunt on the first Splintertree stop (hidden once done)",
			add = { { "accept", 6383, at = { 1440, 73.78, 61.46 }, who = "Senani Thunderheart" },
				{ "turnin", 6383, at = { 1440, 73.78, 61.46 }, who = "Senani Thunderheart" } },
			before = { "turnin", 23 } },
		-- The Assassination Note (12564) drops only from the Galak Messenger
		-- (10617, the data's one source), who can be missed; Protect Kanati
		-- Greycloud already waits for the plot (its prerequisite, 4881).
		{ why = "the Galak Messenger's note can be missed", optional = { "have", 12564 } },
		{ why = "the plot needs the note", optional = { "accept", 4881 } },
		{ why = "Dizzywig's letter rides to Ratchet (see the Arathi route)",
			add = { { "accept", 1111, at = { 1441, 77.79, 77.27 }, who = "Kravel Koalbeard", optional = true },
				{ "note", "Wharfmaster Dizzywig is a letter for Ratchet: keep it until the guide flies there, after the Badlands." } },
			after = { "accept", 1106 } },
		{ why = "Goblin Sponsorship: Pozzik's word for Gazlowe in Ratchet (see the Arathi route)",
			add = { { "accept", 1178, at = { 1441, 80.18, 75.88 }, who = "Pozzik", optional = true } },
			after = { "turnin", 1176 } },
		-- Tideress drops the Befouled Water Globe only with Stonetalon
		-- Standstill (25) taken (players' reports, via Polestar); the route
		-- meets her before Splintertree, where 25 is given. The first visit
		-- does not hold; the Mystral Lake trip for 25 passes her again.
		{ why = "Tideress's globe needs Stonetalon Standstill taken", optional = { "have", 16408 } },
		{ why = "Tideress's globe needs Stonetalon Standstill taken", optional = { "accept", 1918 } },
		{ why = "Tideress again, on the Mystral Lake trip for Stonetalon Standstill",
			add = { { "have", 16408, 1, at = { 1440, 46, 70 }, name = "Befouled Water Globe", optional = true },
				{ "accept", 1918, optional = true } },
			after = { "complete", 25 } },
	},
	-- The Apes of Un'Goro (4289) has no prerequisite and opens at 47 (the
	-- data), so Torwa gives it on the first visit; the route came back to
	-- him for it alone (tools/routes/efficiency.lua: a comeback stop).
	["forever/alliance/40-50/07-un-goro-crater"] = {
		{ why = "take The Apes of Un'Goro on the first visit to Torwa", move = { "accept", 4289 }, after = { "turnin", 4291 } },
	},
	-- Lightforge Ingots (526) needs Lightforge Iron (321) handed in (the data's
	-- prerequisite), which comes on the 30-40 Ashenvale route, after this one:
	-- here it is never offered.
	-- Wharfmaster Dizzywig (1111): Kravel Koalbeard at the Mirage Raceway
	-- sends a letter to Ratchet's dock (the data: start 4452, end 3453). The
	-- route stands by Kravel at the raceway and flies to Ratchet before
	-- Dustwallow Marsh: about 1,400 XP for no detour (a player's Insights
	-- numbers, issue 92). Its follow-up goes back to the raceway: left.
	["forever/horde/30-40/03-arathi-highlands"] = {
		{ why = "Dizzywig's letter, carried from the Mirage Raceway",
			add = { { "turnin", 1111, at = { 1413, 63.35, 38.45 }, who = "Wharfmaster Dizzywig", optional = true },
				{ "note", "Wharfmaster Dizzywig's next task, Parts for Kravel, goes back to the Shimmering Flats: leave it." } },
			after = { "have", 3713 } },
		{ why = "Goblin Sponsorship: Gazlowe sends you on to Booty Bay (see the Stranglethorn 40-50 route)",
			add = { { "turnin", 1178, at = { 1413, 62.68, 36.23 }, who = "Gazlowe", optional = true },
				{ "accept", 1180, at = { 1413, 62.68, 36.23 }, who = "Gazlowe", optional = true } },
			after = { "turnin", 1111 } },
	},
	-- Letters and errands on the way: quests with nothing to do but carry a
	-- word, from a person the route stands by to one it reaches later, for
	-- anyone of the faction, the prerequisite handed in by then (the data:
	-- start and end NPCs, prerequisites, no objectives). Found with
	-- tools/routes/audit.lua --free; each is optional.
	["forever/horde/40-50/01-stranglethorn-vale"] = {
		{ why = "Goblin Sponsorship, carried from Ratchet: Lozgil, then Baron Revilgaz",
			add = { { "turnin", 1180, at = { 1434, 26.35, 73.56 }, who = "Wharfmaster Lozgil", optional = true },
				{ "accept", 1181, at = { 1434, 26.35, 73.56 }, who = "Wharfmaster Lozgil", optional = true },
				{ "turnin", 1181, at = { 1434, 27.23, 76.87 }, who = "Baron Revilgaz", optional = true },
				{ "note", "Baron Revilgaz's next Goblin Sponsorship wants blueprints from the Venture Co.: leave it." } },
			after = { "turnin", 617 } },
	},
	-- Darsok gives Letter to Jin'Zil once Serena Bloodfeather (876) is in;
	-- the Stonetalon route goes to Jin'Zil's cave for his own quest.
	["forever/horde/04-the-barrens"] = {
		{ why = "Letter to Jin'Zil, for the Stonetalon route's Malaka'jin stop",
			add = { { "accept", 1060, at = { 1413, 51.62, 30.9 }, who = "Darsok Swiftdagger", optional = true } },
			after = { "turnin", 876 } },
	},
	["forever/horde/05-stonetalon-mountains"] = {
		{ why = "Darsok's letter, from the Crossroads",
			add = { { "turnin", 1060, at = { 1442, 74.54, 97.94 }, who = "Witch Doctor Jin'Zil", optional = true } },
			before = { "accept", 1058 } },
	},
	-- Speak with Sevren: Coleman Farthing's word, once 354 and 362 are in,
	-- for the magistrate a few steps away in Brill.
	["forever/horde/undead/01-tirisfal-glades"] = {
		{ why = "Speak with Sevren, in Brill",
			add = { { "accept", 355, at = { 1420, 61.72, 52.29 }, who = "Coleman Farthing", optional = true },
				{ "turnin", 355, at = { 1420, 61.26, 50.84 }, who = "Magistrate Sevren", optional = true } },
			after = { "turnin", 427 } },
	},
	-- Grove of the Ancients: Fandral's message for Onu, once 940 is in; the
	-- Darkshore route visits Onu.
	["forever/alliance/nightelf/01-teldrassil"] = {
		{ why = "Fandral's message for Onu (Darkshore route)",
			add = { { "accept", 952, at = { 1457, 34.81, 9.26 }, who = "Arch Druid Fandral Staghelm", optional = true } },
			after = { "turnin", 940 } },
	},
	["forever/alliance/03-darkshore"] = {
		{ why = "Fandral's message, from Darnassus",
			add = { { "turnin", 952, at = { 1439, 43.55, 76.29 }, who = "Onu", optional = true } },
			before = { "turnin", 948 } },
	},
	-- Crimson Crate Delivery: James Halloran in Menethil, for Howin
	-- Kindfeather on the road east, where the Hillsbrad route stops.
	["forever/alliance/06-ashenvale"] = {
		{ why = "Crimson Crate Delivery, for the Hillsbrad route's Green Belt stop",
			add = { { "accept", 98240, at = { 1437, 8.55, 55.74 }, who = "James Halloran", optional = true } },
			after = { "accept", 279 } },
	},
	["forever/alliance/30-40/01-hillsbrad-foothills"] = {
		{ why = "Old Habits is offered only while Nek'rosh's Gambit is in the log", move = { "accept", 98223 }, before = { "turnin", 465 } },
		{ why = "James Halloran's crate, from Menethil",
			add = { { "turnin", 98240, at = { 1437, 49.36, 42.13 }, who = "Howin Kindfeather", optional = true } },
			before = { "turnin", 98230 } },
	},
	-- Prompt Potion Runner (97891) is a level 16 quest (the data), a timed
	-- run across the Undercity; at the route's 55-60 it gives next to no XP.
	["forever/horde/50-60/04-azshara"] = {
		{ why = "a level 16 timed run gives next to no XP at 57", optional = { "*", 97891 } },
	},
	-- Old Habits (98223) is offered only while Nek'rosh's Gambit (465) is in
	-- the log (players' reports, via Polestar): take it before handing 465 in.
	-- Whuut's the Rush (97275) opens once Yelmak's Medley (97242) is handed
	-- in (players' reports, via Polestar): take it back at Kor'geld.
	["forever/horde/03-silverpine-forest"] = {
		{ why = "Whuut's the Rush opens after Yelmak's Medley", move = { "accept", 97275 }, after = { "turnin", 97242 } },
		{ why = "Whuut's the Rush opens after Yelmak's Medley", move = { "turnin", 97275 }, after = { "accept", 97275 } },
	},
	-- Eagan Peltskinner (5261) leads to Wolves Across the Border (33, the
	-- data's breadcrumb): hand it in to Eagan before taking his quest.
	["forever/alliance/human/01-elwynn-forest"] = {
		{ why = "hand in the breadcrumb before taking the quest it leads to", move = { "turnin", 5261 }, before = { "accept", 33 } },
	},
	-- Alba Fairmoon's chain in Westfall is open to every Alliance race (the
	-- data's race mask), Humans too.
	["forever/alliance/02-westfall"] = {
		{ why = "the data opens Alba Fairmoon's chain to Humans too", open = { "*", 92742 } },
		{ why = "the data opens Alba Fairmoon's chain to Humans too", open = { "*", 92744 } },
		{ why = "the data opens Alba Fairmoon's chain to Humans too", open = { "*", 92745 } },
		{ why = "the data opens Alba Fairmoon's chain to Humans too", open = { "*", 92747 } },
		{ why = "the data opens Alba Fairmoon's chain to Humans too", open = { "*", 92748 } },
	},
	["forever/alliance/30-40/05-arathi-highlands"] = {
		{ why = "Krazek's ore comes from the Lesser Bloodstone Deposits, not the kobolds (the data)", step = "Drywhisker Gorge",
			note = "The Drywhisker kobolds dig in the gorge east of Hammerfall (Horde); skirt the town to the north. They drop the motes. Krazek's Lesser Bloodstone Ore is mined from the Lesser Bloodstone Deposits in the gorge: Mining only." },
	},
	["forever/alliance/07-thousand-needles"] = {
		{ why = "Lightforge Ingots is not offered this early", drop = { "*", 526 } },
	},
}

-- Goals that should not hold their step: rare or roaming sources, short
-- timers, group fights, and givers players report never offering. Leads
-- from players' reports in Polestar (fitzforge/polestar, since 2026-10-22)
-- and from our data, checked in the data where it can be; the why says.
local OPTIONAL = {
	["forever/alliance/03-darkshore"] = {
		{ "accept", 990, "Sentinel Selarin stands by Terenthis only a few minutes after an escort" },
	},
	["forever/alliance/05-duskwood"] = {
		{ "have", 4371, "Herble's Bronze Tubes are often out of stock: the Auction House is the other way" },
	},
	["forever/alliance/06-ashenvale"] = {
		{ "*", 1090, "a five-minute defence against waves; it fails if Piznik dies" },
	},
	["forever/alliance/07-thousand-needles"] = {
		{ "have", 4371, "Herble's Bronze Tubes are often out of stock: the Auction House is the other way" },
	},
	["forever/alliance/30-40/01-hillsbrad-foothills"] = {
		{ "*", 87318, "Hearts of the Lost is reported missing from the live game" },
		{ "accept", 98463, "players who walked past Barkeep Kelly were never offered Talk of the Town" },
		{ "*", 565, "Bartolo's cloak needs a Hillman's Cloak and Woolen Cloth: crafted, sold by no one" },
		{ "*", 98059, "Captain McManus rarely offers Hillsbrad's Hoard" },
		{ "*", 98310, "the hearts drop only from summoned elites" },
		{ "*", 87491, "an escort through Dun Modr's elites" },
	},
	["forever/alliance/30-40/04-stranglethorn-vale"] = {
		{ "*", 627, "Krazek's ore is mined from Lesser Bloodstone Deposits (the data: object 2653, no creature drops it): Mining only" },
		{ "accept", 215, "Private Thorsen gives Jungle Secrets only while he walks outside the camp" },
	},
	["forever/alliance/30-40/05-arathi-highlands"] = {
		{ "*", 93176, "My Little Friends' giver is reported never seen in game" },
		{ "*", 212, "A Meal Served Cold has a timer far shorter than the route's way to its hand-in" },
		{ "*", 627, "Krazek's ore is mined from Lesser Bloodstone Deposits (the data: object 2653, no creature drops it): Mining only" },
		{ "*", 1392, "Noboru's cudgel drops only from the roaming Noboru" },
		{ "have", 6196, "Noboru's cudgel drops only from the roaming Noboru" },
		{ "*", 522, "the contract drops only from one stealthed, roaming assassin" },
		{ "have", 3668, "the contract drops only from one stealthed, roaming assassin" },
		{ "*", 565, "Bartolo's cloak needs a Hillman's Cloak and Woolen Cloth: crafted, sold by no one" },
	},
	["forever/alliance/30-40/06-badlands"] = {
		{ "accept", 5943, "the Gizelton Caravan sets out about once an hour; the quest is offered only then" },
		{ "*", 709, "the chest stands in Uldaman's mouth, by elite golems" },
	},
	["forever/alliance/40-50/01-stranglethorn-vale"] = {
		{ "*", 1288, "Vimes's Report is not in our data, and players report Vimes never offers it" },
		{ "*", 93176, "My Little Friends' giver is reported never seen in game" },
		{ "*", 212, "A Meal Served Cold has a timer far shorter than the route's way to its hand-in" },
		{ "*", 627, "Krazek's ore is mined from Lesser Bloodstone Deposits (the data: object 2653, no creature drops it): Mining only" },
		{ "*", 624, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "have", 4056, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "accept", 608, "The Bloodsail Buccaneers' work is optional already" },
	},
	["forever/alliance/40-50/02-badlands"] = {
		{ "accept", 706, "Fiery Blaze Enchantments' work is optional already (a rare drop)" },
	},
	["forever/alliance/40-50/06-searing-gorge"] = {
		{ "*", 3377, "Zamael stands among elite guards" },
	},
	["forever/alliance/40-50/07-un-goro-crater"] = {
		{ "*", 3701, "the relics stand among mobs well above your level" },
	},
	["forever/alliance/50-60/01-burning-steppes"] = {
		{ "*", 3701, "the relics stand among mobs well above your level" },
	},
	["forever/alliance/50-60/03-winterspring"] = {
		{ "*", 5211, "Carlin is reported to offer Defenders of Darrowshire only once Uncle Carlin is in" },
	},
	["forever/alliance/50-60/04-western-plaguelands"] = {
		{ "*", 5781, "Taelan's Hammer drops from an elite with guards (optional on the Alliance routes already)" },
	},
	["forever/alliance/50-60/05-silithus"] = {
		{ "*", 5781, "Taelan's Hammer drops from an elite with guards (optional on the Alliance routes already)" },
		{ "*", 3701, "the relics stand among mobs well above your level" },
	},
	["forever/alliance/50-60/06-silithus"] = {
		{ "*", 5781, "Taelan's Hammer drops from an elite with guards (optional on the Alliance routes already)" },
	},
	["forever/horde/05-stonetalon-mountains"] = {
		{ "*", 1090, "a five-minute defence against waves; it fails if Piznik dies" },
	},
	["forever/horde/06-hillsbrad-foothills"] = {
		{ "accept", 515, "Elixir of Agony's work is optional already; its accept should not hold the step" },
	},
	["forever/horde/30-40/03-arathi-highlands"] = {
		{ "*", 8263, "Defiler's Basic Care Package wants reputation with the Defilers, which the route never earns" },
		{ "*", 709, "the chest stands in Uldaman's mouth, by elite golems" },
	},
	["forever/horde/30-40/04-dustwallow-marsh"] = {
		{ "accept", 5943, "the Gizelton Caravan sets out about once an hour; the quest is offered only then" },
	},
	["forever/horde/40-50/01-stranglethorn-vale"] = {
		{ "*", 1392, "Noboru's cudgel drops only from the roaming Noboru" },
		{ "have", 6196, "Noboru's cudgel drops only from the roaming Noboru" },
		{ "*", 624, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "have", 4056, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "accept", 608, "The Bloodsail Buccaneers' work is optional already" },
	},
	["forever/horde/40-50/03-feralas"] = {
		{ "*", 624, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "*", 625, "Cortello's scroll lies among Bloodsail crews well above your level" },
		{ "*", 1173, "Overlord Mok'Morokk is a group fight" },
	},
	["forever/horde/40-50/05-the-hinterlands"] = {
		{ "*", 7849, "every troll in Jintha'Alor is elite: a group quest" },
		{ "*", 7845, "every troll in Jintha'Alor is elite: a group quest" },
		{ "*", 7850, "every troll in Jintha'Alor is elite: a group quest" },
	},
	["forever/horde/40-50/06-azshara"] = {
		{ "*", 3504, "Belgrom does not offer Betrayed on Forever; Ag'tor gives the next part (players' reports, via Polestar)" },
	},
	["forever/horde/50-60/01-un-goro-crater"] = {
		{ "*", 5211, "Carlin is reported to offer Defenders of Darrowshire only once Uncle Carlin is in" },
	},
	["forever/horde/50-60/03-winterspring"] = {
		{ "*", 3786, "growing Morrowgrain is random and its pouch has a cooldown" },
		{ "*", 3804, "growing Morrowgrain is random and its pouch has a cooldown" },
	},
	["forever/horde/50-60/04-azshara"] = {
		{ "*", 3504, "Belgrom does not offer Betrayed on Forever; Ag'tor gives the next part (players' reports, via Polestar)" },
		{ "*", 3506, "the old Betrayed parts are not offered after Ag'tor's (players' reports, via Polestar)" },
		{ "*", 3507, "the old Betrayed parts are not offered after Ag'tor's (players' reports, via Polestar)" },
	},
	["forever/horde/50-60/06-silithus"] = {
		{ "*", 5781, "Taelan's Hammer drops from an elite with guards (optional on the Alliance routes already)" },
	},
	["forever/horde/orc-troll/01-durotar"] = {
		{ "accept", 832, "the Eye of Burning Shadow drops only from Gazz'uz at the back of Skull Rock" },
		{ "have", 4903, "the Eye of Burning Shadow drops only from Gazz'uz at the back of Skull Rock" },
	},
}
for id, list in pairs(OPTIONAL) do
	FIXES[id] = FIXES[id] or {}
	for _, o in ipairs(list) do
		table.insert(FIXES[id], { why = o[3], optional = { o[1], o[2] } })
	end
end


local M = {}

local function matches(goal, ref)
	return goal[2] == ref[2] and (ref[1] == "*" or goal[1] == ref[1])
end

local function find(route, ref)
	for s, step in ipairs(route.steps) do
		for g, goal in ipairs(step) do
			if matches(goal, ref) then return s, g end
		end
	end
end

local function fail(route, fix, what)
	error(("tools/port/fixes.lua: %s: %s (%s)"):format(route.id, what, fix.why or "no why"), 0)
end

local used = {}

function M.apply(route, D)
	local list = FIXES[route.id]
	if not list then return route end
	used[route.id] = true
	for _, fix in ipairs(list) do
		if not fix.why then fail(route, fix, "a fix needs a why") end
		if fix.drop then
			local n = 0
			for _, step in ipairs(route.steps) do
				for g = #step, 1, -1 do
					if matches(step[g], fix.drop) then table.remove(step, g) n = n + 1 end
				end
			end
			if n == 0 then fail(route, fix, "nothing to drop for quest " .. tostring(fix.drop[2])) end
			-- A step left with nothing to do goes.
			for s = #route.steps, 1, -1 do if #route.steps[s] == 0 then table.remove(route.steps, s) end end
		elseif fix.move then
			local s, g = find(route, fix.move)
			if not s then fail(route, fix, "no goal to move for quest " .. tostring(fix.move[2])) end
			local goal = table.remove(route.steps[s], g)
			local anchor = fix.after or fix.before
			local ts, tg = find(route, anchor)
			if not ts then fail(route, fix, "no goal to move next to: quest " .. tostring(anchor[2])) end
			table.insert(route.steps[ts], fix.after and tg + 1 or tg, goal)
			if #route.steps[s] == 0 then table.remove(route.steps, s) end
		elseif fix.add then
			local anchor = fix.after or fix.before
			local ts, tg = find(route, anchor or {})
			if not ts then fail(route, fix, "no goal to add next to: quest " .. tostring(anchor and anchor[2])) end
			local at = fix.after and tg + 1 or tg
			for i, goal in ipairs(fix.add) do table.insert(route.steps[ts], at + i - 1, goal) end
		elseif fix.when then
			local s = find(route, fix.when)
			if not s then fail(route, fix, "no step to hold for " .. tostring(fix.when[2])) end
			local step = route.steps[s]
			step.when = step.when or {}
			step.when[#step.when + 1] = { k = fix.k, q = fix.q }
		elseif fix.optional then
			local n = 0
			for _, step in ipairs(route.steps) do
				for _, goal in ipairs(step) do
					if matches(goal, fix.optional) then goal.optional = true n = n + 1 end
				end
			end
			if n == 0 then fail(route, fix, "nothing to make optional for " .. tostring(fix.optional[2])) end
		elseif fix.open then
			-- The goal(s), and a step holding only them, for everyone again.
			local n = 0
			for _, step in ipairs(route.steps) do
				local hit, other
				for _, goal in ipairs(step) do
					if matches(goal, fix.open) then goal.only = nil n = n + 1 hit = true
					elseif type(goal[2]) == "number" then other = true end
				end
				if hit and not other then step.only = nil end
			end
			if n == 0 then fail(route, fix, "nothing to open for " .. tostring(fix.open[2])) end
		elseif fix.at then
			local s, g = find(route, fix.at)
			if not s then fail(route, fix, "no goal to place for quest " .. tostring(fix.at[2])) end
			route.steps[s][g].at = { fix.place[1], fix.place[2], fix.place[3] }
		elseif fix.step then
			local hit
			for _, step in ipairs(route.steps) do
				if step.title == fix.step then step.note = fix.note hit = true break end
			end
			if not hit then fail(route, fix, "no step titled " .. fix.step) end
		elseif fix.levels then
			route.levels = { fix.levels[1], fix.levels[2] }
		else
			fail(route, fix, "a fix with nothing to do")
		end
	end
	return route
end

-- Route ids with fixes that never met their route (renamed or gone).
function M.Unused()
	local out = {}
	for id in pairs(FIXES) do if not used[id] then out[#out + 1] = id end end
	table.sort(out)
	return out
end

M.FIXES = FIXES
return M
