-- Pathwise Gear's pages in its own options window (Kit/Options.lua draws
-- them; the row kinds are listed there): Upgrades (who scores items, the
-- spec and its stat priority, custom weights, the upgrades in your bags),
-- Best in Slot (Level), then the look and profile pages every Pathwise addon
-- has. /pwgear, the minimap button or Pathwise's suite list opens it.

local ADDON, ns = ...
local C = ns.Config
local S, Gear, W, P = ns.S, ns.Gear, ns.Weights, ns.Panel

local function upgradeRows()
	local rows = { { "heading", "Pathwise Gear" } }
	local weights, name, from = Gear.Weights()
	rows[#rows + 1] = { "text", from == "imported" and ("Scoring with your custom weights \"%s\"."):format(name)
		or ("Scoring with Pathwise's %s weights."):format(name), "text2" }

	-- Spec and stat priority (Pathwise's weights).
	local class = Gear.Client.Class()
	local key, _, how = Gear.Spec()
	rows[#rows + 1] = { "heading", "Spec" }
	local specs = { { "Follow my talents", "auto" } }
	for _, s in ipairs(W.Specs(class)) do specs[#specs + 1] = { (s.label:gsub(" %b()", "")), s.key } end
	rows[#rows + 1] = { "dropdown", "Spec", {
		get = function() return how == "chosen" and key or "auto" end,
		set = function(v)
			if v == "auto" then
				local t = {}
				for k, x in pairs(S.Get("gear.spec") or {}) do t[k] = x end
				t[class] = nil
				S.Set("gear.spec", t)
				Gear.Clear()
			else
				Gear.SetSpec(v)
			end
		end,
	}, specs, how == "auto" and ("Following your talents (or the usual levelling spec): %s."):format(tostring((select(2, Gear.Spec())))) or "Chosen by you." }
	local main, pct = P.Priority(from == "imported" and weights or W.For(class, key))
	rows[#rows + 1] = { "heading", "Stat priority" }
	rows[#rows + 1] = { "text", main ~= "" and main or "No stats", "text" }
	if pct ~= "" then rows[#rows + 1] = { "text", "Per 1%: " .. pct, "text2" } end
	local spec = from ~= "imported" and W.Spec(class, key)
	if spec and spec.note then rows[#rows + 1] = { "text", "The class guides agree: " .. spec.note .. ".", "muted" } end
	rows[#rows + 1] = { "text", "Pathwise's own weights, ordered as the Icy Veins and Mobalytics Forever guides advise. Not yet checked in game.", "muted" }

	-- Custom weights, pasted.
	rows[#rows + 1] = { "heading", "Custom weights (optional)" }
	rows[#rows + 1] = { "input", "gear.import", "Paste your own, like Intellect=1.2, Stamina=0.5 (a guide site's scale string works too), then Apply.", function(text)
		local scale, err = Gear.ImportScale(text)
		if not scale then ns.Print(tostring(err)) return false end
		local extra = #scale.ignored > 0 and (" (left out: %s)"):format(table.concat(scale.ignored, ", ")) or ""
		ns.Print(("imported \"%s\"%s."):format(scale.name, extra))
		return true
	end }
	for _, sc in ipairs(Gear.Scales()) do
		local inUse = from == "imported" and name == sc.name
		rows[#rows + 1] = { "button", inUse and ("Stop using \"%s\""):format(sc.name) or ("Use \"%s\""):format(sc.name), function()
			Gear.UseScale(not inUse and sc.name or nil)
		end, inUse and "accent" or "default" }
	end

	-- Upgrades waiting in the bags.
	local ups = P.BagUpgrades(8)
	rows[#rows + 1] = { "heading", ("Upgrades in your bags (%d)"):format(#ups) }
	if #ups == 0 then rows[#rows + 1] = { "text", "None right now.", "muted" } end
	for _, u in ipairs(ups) do
		rows[#rows + 1] = { "text", ("%s   %s%s"):format(u.name, u.pct and ("+%.1f%%"):format(u.pct) or "empty slot", u.slot and ("  ·  " .. u.slot) or ""), "success" }
	end

	rows[#rows + 1] = { "heading", "Options" }
	rows[#rows + 1] = { "toggle", "Line on item tooltips", "gear.tooltip", "Whether an item is an upgrade for your spec, and by how much." }
	rows[#rows + 1] = { "toggle", "Arrow on bag upgrades", "gear.bags", "A gold arrow on items in the game's bags that are upgrades." }
	rows[#rows + 1] = { "toggle", "Best quest reward", "gear.rewards", ns.Pathwise() and "With a choice of rewards, the best one for you is named in chat and on its tooltip; Pathwise's quest automation can take it."
		or "With a choice of rewards, the best one for you is named in chat and on its tooltip." }
	rows[#rows + 1] = { "slider", "Smallest upgrade shown", "gear.minUpgrade", 0, 0.1, 0.01, "percent" }
	return rows
end

local function bestRows()
	local Best = ns.Best
	local rows = { { "heading", "Best in Slot (Level)" } }
	if not Best.Available() then
		rows[#rows + 1] = { "text", "Needs Pathwise: Leveling & Professions: the list is worked out from its quest, monster and dungeon data, and its arrow leads you there. Everything else in Pathwise Gear works without it.", "muted" }
		return rows
	end
	local list, pending = Best.List()
	local _, name = Gear.Weights()
	local level = Gear.Client.Level()
	local ahead = S.Get("gear.bisAhead") or 0
	rows[#rows + 1] = { "text", ("Level %d%s  ·  %s weights"):format(level, ahead > 0 and (" (and the next %d)"):format(ahead) or "", tostring(name)), "text2" }
	local missing = 0
	for _, e in ipairs(list) do if not e.have then missing = missing + 1 end end
	rows[#rows + 1] = { "text", missing == 0 and #list > 0 and "You have the best of everything Pathwise knows for your level."
		or ("%d of %d slots to chase. Click one: the arrow leads to it."):format(missing, #list) }
	if pending > 0 then rows[#rows + 1] = { "text", ("Loading %d items from the game..."):format(pending), "muted" } end
	for _, e in ipairs(list) do
		local status
		if e.wearing then status = "Wearing it"
		elseif e.have then status = "In your bags"
		elseif e.pct then status = ("%+.0f%% on what you wear"):format(e.pct)
		else status = "Empty slot" end
		local sub = Best.SourceText(e.source) .. "  ·  " .. status
		if e.minLevel and e.minLevel > level then sub = sub .. ("  ·  from level %d"):format(e.minLevel) end
		rows[#rows + 1] = { "button", ("%s:  %s%s"):format(e.slotName, tostring(e.name), e.have and "  (have)" or ""), function()
			if Best.Chase(e) then
				ns.Print(("the arrow leads to %s for %s."):format(Best.SourceText(e.source), tostring(e.name)))
			else
				ns.Print(("%s comes from %s; Pathwise has no place to point at."):format(tostring(e.name), Best.SourceText(e.source)))
			end
		end }
		rows[#rows + 1] = { "text", sub, "muted" }
	end
	if #list == 0 and pending == 0 then rows[#rows + 1] = { "text", "No gear found for your level yet." } end

	rows[#rows + 1] = { "heading", "Options" }
	rows[#rows + 1] = { "choice", "Look ahead", "gear.bisAhead", { { "Now", 0 }, { "+3", 3 }, { "+5", 5 } } }
	rows[#rows + 1] = { "toggle", "Alert when I pick one up", "gear.bisAlert", "On screen, with a sound and a chat line, and a gold star in your bags: for your level and for the level an item needs." }
	rows[#rows + 1] = { "choice", "Crafted gear", "gear.bisCrafted", { { "All", "all" }, { "Mine", "mine" }, { "Off", "off" } },
		"All: crafts you could buy from the Auction House or a crafter, and your own. Mine: only what your professions make." }
	rows[#rows + 1] = { "toggle", "Season of Discovery recipes", "gear.bisSod", "They are in Forever's game files and some were found in Forever; not all are confirmed." }
	rows[#rows + 1] = { "toggle", "Raid gear", "gear.bisRaids" }
	rows[#rows + 1] = { "text", "Worked out in game from Pathwise's weights and the item's stats as the game gives them. Where items come from: QuestieDB's Forever data; recipes: Forever's game files.", "muted" }
	return rows
end

C.CATEGORIES = {
	{ key = "gear", name = "Upgrades", rows = upgradeRows },
	{ key = "best", name = "Best in Slot", rows = bestRows },
	{ key = "look", name = "Look and accent", rows = C.AccentRows },
	{ key = "colors", name = "Colors", rows = C.ColorRows },
	{ key = "help", name = "Help and feedback", rows = C.CommunityRows },
	{ key = "profile", name = "Profile", rows = function() return C.ProfileRows() end },
}

-- Redraw as Best in Slot's items arrive, and when Gear's verdicts change.
S.On("GEAR_BEST_UPDATED", function() if S.IsOpen("best") then S.Refresh() end end)
S.On("GEAR_UPDATED", function() S.Refresh() end)
