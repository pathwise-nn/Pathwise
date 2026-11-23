-- Drops players saw in game and sent in, for bosses QuestieDB's Forever data
-- is missing them for. tools/data/loot.lua adds them to Data/Loot.lua.
--
-- How a report gets here: a player opens Pathwise Loot's options (or types
-- /pwloot export), copies the "Send the drops Pathwise lacks" line and posts
-- it. It reads:
--   PWLOOT1 <data build>; <boss id>[=<name>@<map>] k<kills>: <item id>[x<times>], ...; ...
-- Check each item before adding it: it must have dropped from that boss
-- (not a trash mob, a chest or a quest reward), and the generator checks that
-- the boss is in Forever's boss list and the item in Forever's Item table.
--
-- Nothing here may come from Wowhead or AtlasLoot: only what players saw.
--
--   { boss (encounter id), { item ids }, "who saw them, when, how" },

return {
}
