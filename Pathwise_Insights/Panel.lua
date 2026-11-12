-- The Pathwise Insights page (its minimap button, or Settings > Pathwise
-- suite > Pathwise Insights): your own numbers, read from the recorder's log.

local ADDON, ns = ...
local S, R = Pathwise.Suite, ns.Recorder
local P = {}
ns.Panel = P

-- 4500 -> "1 h 15 m", 125 -> "2 m", 40 -> "40 s"
function P.Duration(sec)
	sec = math.floor((sec or 0) + 0.5)
	if sec < 60 then return sec .. " s" end
	local m = math.floor(sec / 60)
	if m < 60 then return m .. " m" end
	return ("%d h %d m"):format(math.floor(m / 60), m % 60)
end

-- XP an hour, once there is at least five minutes to go on; else nil.
function P.Rate(xp, sec)
	if not sec or sec < 300 then return nil end
	return math.floor((xp or 0) * 3600 / sec + 0.5)
end

local function number(n)
	local s = tostring(math.floor(n + 0.5))
	while true do
		local k
		s, k = s:gsub("^(%d+)(%d%d%d)", "%1,%2")
		if k == 0 then return s end
	end
end
P.Number = number

local function rateText(xp, sec)
	local r = P.Rate(xp, sec)
	return r and (number(r) .. " XP/h") or "—"
end

local function routeTitle(id)
	local info = S.Guide.RouteInfo(id)
	return info and info.title or tostring(id)
end

local function zoneName(map)
	local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name or ("Map " .. tostring(map))
end

local function sorted(tbl, nameOf)
	local out = {}
	for k, b in pairs(tbl) do
		if (b.t or 0) >= 1 then out[#out + 1] = { key = k, name = nameOf(k), t = b.t, xp = b.xp or 0, d = b.d or 0, b = b } end
	end
	table.sort(out, function(a, b) return a.t > b.t end)
	return out
end

-- What the page shows, worked out from the log (the tests read it too).
function P.Summary()
	local log = R.Log()
	local out = { played = log.played, xp = log.xp, deaths = log.deaths, since = log.since }
	out.routes = sorted(log.routes, routeTitle)
	out.zones = sorted(log.zones, zoneName)
	-- The slowest steps you finished (not the ones you skipped or left).
	local slow = {}
	for _, st in ipairs(log.steps) do if st.how == "done" then slow[#slow + 1] = st end end
	table.sort(slow, function(a, b) return a.t > b.t end)
	while #slow > 5 do table.remove(slow) end
	out.slowest = slow
	local skipped = 0
	for _, st in ipairs(log.steps) do if st.how == "skip" then skipped = skipped + 1 end end
	out.skipped, out.recorded = skipped, #log.steps
	-- Time to level, the last few levels first.
	local levels = {}
	for lvl, b in pairs(log.levels) do if (b.t or 0) >= 1 then levels[#levels + 1] = { level = lvl, t = b.t, xp = b.xp or 0, d = b.d or 0 } end end
	table.sort(levels, function(a, b) return a.level > b.level end)
	while #levels > 8 do table.remove(levels) end
	out.levels = levels
	local skills = {}
	for line, s in pairs(log.skills) do
		local prof = S.Professions and S.Professions.BY_LINE and S.Professions.BY_LINE[line]
		if (s.ups or 0) > 0 then skills[#skills + 1] = { name = prof and prof.name or ("Skill " .. line), from = s.from, to = s.to } end
	end
	table.sort(skills, function(a, b) return a.name < b.name end)
	out.skills = skills
	return out
end

local confirmClear = false

function P.Build()
	local sum = P.Summary()
	local rows = { { "heading", "Pathwise Insights" } }
	rows[#rows + 1] = { "text", "Your own leveling numbers, from the time you play with Pathwise. They stay on your computer.", "insights" }
	if not S.Get("insights.record") then
		rows[#rows + 1] = { "text", "Recording is off: nothing new is written down.", "muted" }
	end

	rows[#rows + 1] = { "heading", "So far" }
	rows[#rows + 1] = { "setting", "Time played", P.Duration(sum.played) }
	rows[#rows + 1] = { "setting", "XP gained", number(sum.xp) }
	rows[#rows + 1] = { "setting", "XP an hour", rateText(sum.xp, sum.played) }
	rows[#rows + 1] = { "setting", "Deaths", tostring(sum.deaths) }
	rows[#rows + 1] = { "setting", "Steps recorded", ("%d (%d skipped)"):format(sum.recorded, sum.skipped) }
	if sum.played < 1 then
		rows[#rows + 1] = { "text", "Nothing yet: follow a route and come back.", "muted" }
	end

	if #sum.routes > 0 then
		rows[#rows + 1] = { "heading", "Routes" }
		for i, r in ipairs(sum.routes) do
			if i > 8 then break end
			local bits = { P.Duration(r.t), rateText(r.xp, r.t) }
			if (r.b.steps or 0) > 0 then bits[#bits + 1] = r.b.steps .. " steps" end
			if (r.b.skips or 0) > 0 then bits[#bits + 1] = r.b.skips .. " skipped" end
			if r.d > 0 then bits[#bits + 1] = r.d .. (r.d == 1 and " death" or " deaths") end
			if r.b.done then bits[#bits + 1] = "finished" end
			rows[#rows + 1] = { "text", r.name, "text" }
			rows[#rows + 1] = { "text", table.concat(bits, "  ·  "), "muted" }
		end
	end

	if #sum.zones > 0 then
		rows[#rows + 1] = { "heading", "Zones" }
		for i, z in ipairs(sum.zones) do
			if i > 8 then break end
			local bits = { P.Duration(z.t), rateText(z.xp, z.t) }
			if z.b.lvl then bits[#bits + 1] = "came at level " .. z.b.lvl end
			if z.d > 0 then bits[#bits + 1] = z.d .. (z.d == 1 and " death" or " deaths") end
			rows[#rows + 1] = { "setting", z.name, table.concat(bits, "  ·  ") }
		end
	end

	if #sum.levels > 0 then
		rows[#rows + 1] = { "heading", "Time at each level" }
		for _, l in ipairs(sum.levels) do
			rows[#rows + 1] = { "setting", "Level " .. l.level, P.Duration(l.t) .. "  ·  " .. rateText(l.xp, l.t) }
		end
	end

	if #sum.slowest > 0 then
		rows[#rows + 1] = { "heading", "Slowest steps" }
		for _, st in ipairs(sum.slowest) do
			rows[#rows + 1] = { "setting", ("%s, step %d"):format(routeTitle(st.r), st.s), P.Duration(st.t) }
		end
	end

	if #sum.skills > 0 then
		rows[#rows + 1] = { "heading", "Professions" }
		for _, s in ipairs(sum.skills) do
			rows[#rows + 1] = { "setting", s.name, ("%d → %d"):format(s.from, s.to) }
		end
	end

	rows[#rows + 1] = { "heading", "Options" }
	rows[#rows + 1] = { "setting", "Recording", S.Get("insights.record") and "On" or "Off", {
		{ S.Get("insights.record") and "Turn off" or "Turn on", function() S.Set("insights.record", not S.Get("insights.record")) S.Refresh() end } } }
	rows[#rows + 1] = { "setting", "Minimap button", S.Get("insights.minimap") and "On" or "Off", {
		{ S.Get("insights.minimap") and "Hide" or "Show", function() S.Set("insights.minimap", not S.Get("insights.minimap")) S.Refresh() end } } }
	rows[#rows + 1] = { "setting", "This character's numbers", confirmClear and "Sure?" or "", {
		{ confirmClear and "Yes, clear" or "Clear", function()
			if confirmClear then
				confirmClear = false
				R.Clear()
				S.Print("Pathwise Insights: this character's numbers are cleared.")
			else
				confirmClear = true
			end
			S.Refresh()
		end, confirmClear and "accent" or "default" } } }
	rows[#rows + 1] = { "text", "Not counted: time AFK and loading screens. Not yet checked in game.", "muted" }
	rows[#rows + 1] = S.CloseButtons()
	return rows
end

S.Panel("insights", P.Build)
S.On("INSIGHTS_UPDATED", function() if S.IsOpen("insights") then S.Refresh() end end)

function P.Open()
	confirmClear = false
	S.Open("insights")
end

S.On("READY", function()
	S.MinimapButton({
		key = "Insights", name = "Pathwise Insights", shownPath = "insights.minimap", anglePath = "insights.minimapAngle",
		accent = "insights", glyph = "list", panels = { "insights" },
		lines = { "Click: your leveling numbers" },
		onClick = function() P.Open() end,
	})
end)

S.RegisterModule({
	key = "insights", name = "Pathwise Insights", accent = "insights",
	about = "Your leveling numbers: time, XP an hour, deaths, slow steps",
	open = P.Open,
})

SLASH_PATHWISEINSIGHTS1 = "/pwinsights"
SlashCmdList = SlashCmdList or {}
SlashCmdList.PATHWISEINSIGHTS = function() P.Open() end
