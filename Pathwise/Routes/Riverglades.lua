-- Riverglades for the Horde, levels 38-46: Pathwise's own route, written by
-- hand (Polestar has no quest route for the zone). Every quest, giver and
-- objective is QuestieDB's Forever data (Data/Data.lua): goals name only the
-- quest, and the guide finds who and where from the data. The few `at`
-- places are data positions too, given where the data's own answer would be
-- wrong (an item the data says drops in Elwynn) or missing (no objective).
-- The order follows the zone's hubs and quest chains, checked against one
-- player's Pathwise Insights log (issue #108, levels 43-44). Not yet walked
-- in game from start to end.

local R = "pathwise/horde/riverglades"

Pathwise.RegisterRoute({category = "Leveling", faction = "Horde", id = R, levels = {38, 46}, map = 2548, title = "Riverglades", steps = {
	{{"accept", 93786}, {"accept", 93787}, {"accept", 93788}, {"accept", 95951}, {"accept", 96107}, {"accept", 95992, optional = true},
		note = "Rog'mar is the Horde town at the heart of the Riverglades. Krom'rosh, Kreza Darkthorn, Tan'jani and Neza Bloodsnout all stand in town; the Ghostmaw poster hangs by Neza.", title = "Rog'mar"},
	{{"accept", 96063}, note = "Sleebo Fizzlespout's camp, a short way east of Rog'mar.", title = "Sleebo's camp"},
	{{"complete", 96107}, {"complete", 96063}, {"accept", 96103}, note = "South of Rog'mar: Plains Buzzards circle the grass, and the marsh gas vents bubble to the south-east. The picked carcass lies among the vents.", title = "The plains south of Rog'mar"},
	{{"complete", 93788}, {"complete", 95951, at = {2548, 40.1, 63.6}}, {"complete", 95992, optional = true},
		note = "Turner's Logging Camp, south-west: the lumberjacks carry the axes, and the woodpiles give the bundles to fletch into spears. Ghostmaw prowls nearby.", title = "Turner's Logging Camp"},
	{{"complete", 93786}, {"complete", 93787}, note = "Meadowsbrook, the Alliance farm further south: farmhands in the fields, feed satchels by the buildings.", title = "Meadowsbrook"},
	{{"turnin", 93788}, {"turnin", 95951}, {"accept", 95955}, {"turnin", 95992, optional = true}, {"turnin", 96107}, {"accept", 96108}, {"turnin", 96103}, {"accept", 96104},
		{"turnin", 93786}, {"turnin", 93787}, {"accept", 94480}, {"accept", 94483}, {"turnin", 94480}, {"accept", 94481}, title = "Back to Rog'mar"},
	{{"turnin", 96063}, {"accept", 96067, optional = true}, {"complete", 96067, optional = true}, {"turnin", 96067, optional = true}, note = "Sleebo has a test for you once the gas is in.", title = "Sleebo's camp"},
	{{"complete", 94481}, note = "The Rog'mar training grounds, north of town.", title = "The training grounds"},
	{{"complete", 96108}, {"complete", 96104}, note = "Back to the plains south of town: Glade Vipers in the grass, Roving Tallstriders on the open ground.", title = "The plains again"},
	{{"complete", 94483}, {"complete", 95955}, note = "Farholde's priests and scouts camp south of the river; the crocolisks lie along its banks.", title = "Farholde, south of the river"},
	{{"turnin", 94481}, {"turnin", 95955}, {"turnin", 96108}, {"accept", 96109}, {"turnin", 96104}, {"accept", 96105}, {"turnin", 94483}, {"accept", 94672}, {"accept", 94680}, title = "Rog'mar"},
	{{"complete", 96109}, {"complete", 96105}, note = "The lion pride on the plains: the Wildplains Patriarchs give the hides. Use the Tallstrider Call where the pride gathers to bring out Ombassa.", title = "The lion pride"},
	{{"accept", 94961}, {"complete", 94672}, {"complete", 94680}, {"complete", 94961}, {"turnin", 94961}, {"accept", 94963},
		note = "Sunnyglade, west of Rog'mar, is held by the Twilight's Hammer. Fuzzle waits on its eastern edge and wants the Shadowmancers' finger bones.", title = "Sunnyglade"},
	{{"turnin", 94672}, {"turnin", 94680}, {"accept", 94727}, {"turnin", 96109}, {"turnin", 96105}, title = "Rog'mar"},
	{{"turnin", 94727}, {"accept", 95417}, {"accept", 95602}, {"turnin", 95417}, {"accept", 95601}, {"complete", 95601}, {"complete", 95602},
		{"turnin", 95601}, {"turnin", 95602}, {"accept", 95427}, {"complete", 95427}, {"turnin", 95427}, {"accept", 95418}, {"turnin", 94963, optional = true},
		note = "Clubtoe hides by the caves beneath Sunnyglade. The missing ogres, the ritual circles and Chogg'Zac are all inside. Fuzzle's treasure is buried at Sunnyglade on the way out.", title = "The caves beneath Sunnyglade"},
	{{"turnin", 95418}, {"accept", 95420}, {"accept", 95882, optional = true}, note = "The Scoutmaster Vargas poster by Neza is for later, at the Eastsea camp on the coast.", title = "Rog'mar"},
	{{"accept", 95163}, {"accept", 95162}, {"accept", 94556}, {"complete", 94556}, {"turnin", 95420}, {"turnin", 94556}, {"accept", 95424}, {"accept", 95425}, {"accept", 95183},
		note = "North to Bolder'ok, the ogre town. Na'zok's farm lies east of the way; Jom-jom waits further east and walks with you to Clugfist. Hamur is in town.", title = "Bolder'ok"},
	{{"complete", 95424}, {"complete", 95425}, {"complete", 95183}, {"complete", 95163, at = {2548, 72.7, 37.0}}, {"complete", 95162, at = {2548, 72.7, 37.0}},
		note = "East and south of Bolder'ok: the Twilight Maulers and Firecallers, Klunk with Clugfist's club, the rock piles, and the paletusks below Na'zok's farm (the boar meat is theirs).", title = "Around Bolder'ok"},
	{{"turnin", 95163}, {"turnin", 95162}, {"turnin", 95424}, {"turnin", 95425}, {"accept", 94668}, {"accept", 95428}, {"turnin", 95183},
		note = "Hamur then asks for Heavy Weightstones, a blacksmith's make; this route leaves that one out.", title = "Bolder'ok"},
	{{"turnin", 94668}, {"accept", 94669}, {"complete", 94669, at = {2548, 65.6, 21.4}}, {"turnin", 94669}, {"accept", 94670}, {"complete", 94670, at = {2548, 65.6, 21.4}}, {"turnin", 94670},
		{"accept", 94739}, {"complete", 94739, at = {2548, 65.6, 21.4}}, {"turnin", 94739}, {"accept", 94962}, {"complete", 94962, at = {2548, 65.6, 21.4}}, {"turnin", 94962},
		{"accept", 94964}, {"complete", 94964, at = {2548, 65.6, 21.4}}, {"turnin", 94964}, {"accept", 94733},
		note = "The Bloodmaster's Ring: Jezap Jinglesprocket takes the deposit, then sends in one challenger after another.", title = "The Bloodmaster's Ring"},
	{{"turnin", 94733}, {"accept", 94734}, {"complete", 94734, at = {2548, 78.6, 37.1}, obj = {1}}, {"complete", 94734, at = {2548, 62.4, 40.8}, obj = {2}}, {"turnin", 94734}, {"accept", 94737},
		note = "Gobam, in Bolder'ok, wants sweetberries from the bushes south-east of town and riverweed from the water to the south.", title = "Gobam's treats"},
	{{"turnin", 94737}, {"accept", 94965}, {"complete", 94965, at = {2548, 65.6, 21.4}}, {"turnin", 94965}, {"accept", 95063}, {"complete", 95063, at = {2548, 65.6, 21.4}}, {"turnin", 95063},
		note = "Back to the Ring for the last two fights, then the news goes to Clugfist.", title = "Champion of the Ring"},
	{{"accept", 95118}, {"accept", 95119}, {"accept", 95121}, {"accept", 95288}, {"accept", 95254, optional = true}, {"accept", 95120, optional = true},
		note = "South-east to Powderfuse Port, the neutral goblin port: Wharfmaster Whizzbuzz, Friz Frazzlespark and Fimbo Greasemitz are on the docks, the WANTED posters by the water.", title = "Powderfuse Port"},
	{{"complete", 95119}, {"complete", 95288}, {"complete", 95254, optional = true}, note = "Eastsea Buccaneers and Musketeers along the shore just north of the port; the Smuggled Goods are on them. Trapclaw scuttles at the docks.", title = "North of the port"},
	{{"complete", 95118}, {"complete", 95121}, {"complete", 95120, optional = true}, note = "South along the Eastwind Shore: murlocs on the beach, sand crawlers further south. Old Rot-Chum lurks among the murlocs.", title = "The Eastwind Shore"},
	{{"turnin", 95118}, {"turnin", 95119}, {"accept", 95122}, {"accept", 95123}, {"turnin", 95121}, {"turnin", 95254, optional = true}, {"turnin", 95120, optional = true}, {"turnin", 95288}, {"accept", 95293}, title = "Powderfuse Port"},
	{{"complete", 95122}, {"complete", 95123}, {"complete", 95882, optional = true}, {"turnin", 95293}, {"accept", 95294},
		note = "The Eastsea camp up the coast to the north: raiders, bombardiers and the powder kegs, with Scoutmaster Vargas among them. Captain Bentcoin and Captain Haynes are at the north-eastern point.", title = "The Eastsea camp"},
	{{"turnin", 95122}, {"turnin", 95123}, {"accept", 95124}, {"accept", 95165}, {"turnin", 95294}, title = "Powderfuse Port"},
	{{"complete", 95124}, {"complete", 95165}, note = "Admiral Lamora holds the far north-eastern point, his chest beside him. Plant a charge on each of the Eastsea's three boats along the way.", title = "Admiral Lamora"},
	{{"turnin", 95124}, {"turnin", 95165}, title = "Powderfuse Port"},
	{{"turnin", 95428}, {"accept", 94744}, {"turnin", 95882, optional = true}, title = "Rog'mar"},
	{{"turnin", 94744}, {"accept", 94745}, {"accept", 94748}, {"accept", 95431}, {"turnin", 95431}, {"accept", 95432}, {"complete", 95432, at = {2548, 27.7, 36.5}}, {"turnin", 95432}, {"accept", 95433},
		note = "Da'grosh waits in the hills west of Sunnyglade; Crag'rog is in the cave close by and wants five ogre miners freed to fight.", title = "Da'grosh"},
	{{"complete", 94745}, {"complete", 94748}, {"complete", 95433}, note = "The Twilight's Shroud, west of Da'grosh: fanatics, corrupters and champions, the captive scouts, and Executioner Morg.", title = "The Twilight's Shroud"},
	{{"turnin", 94745}, {"turnin", 94748}, {"accept", 94768}, {"complete", 94768}, {"turnin", 94768}, {"accept", 95278},
		note = "Overlord Kilgar holds the heart of the Shroud.", title = "Overlord Kilgar"},
	{{"turnin", 95278}, {"turnin", 95433}, note = "Krom'rosh in Rog'mar takes the missive; then north once more to Clugfist with the Executioner's Mace. Krom'rosh's next quest leads into Krol'dok Stronghold, which this route leaves out.", title = "Last hand-ins"},
}})
