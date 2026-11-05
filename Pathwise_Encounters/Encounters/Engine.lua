-- The boss mod's engine: which fight is on, its phase, and the timers.
--
-- What Forever lets an addon see (Blizzard's Forever UI source):
--   * ENCOUNTER_START / ENCOUNTER_END / BOSS_KILL carry the encounter id,
--     name and result as plain values. They start and stop everything here.
--   * The combat log is closed to addons (C_CombatLogSecure is SecureOnly),
--     and in a fight a boss's casts, auras, health and yells are secret. So
--     no timer here can follow what the boss actually does: Pathwise's own
--     timers run from the pull (or a phase you set), as estimates.
--   * The game's own encounter timeline and warnings (Timeline.lua) are
--     shown too: their names may be secret, but can still be drawn.
--
--   E.Start(id, name, difficulty, size) / E.Finish(kill)   a fight begins / ends
--   E.SetPhase(n)            move the timers to phase n (the raid saw it happen)
--   E.AddTimer(t) / E.RemoveTimer(id) / E.Timers()
--       t = { id, kind, label, icon, ends, total, approx, spell }
--       kind: "boss" (Pathwise's estimate), "game" (the game's timeline),
--             "pull", "break"
--   E.Fight()                the fight on now, or nil
--   E.Update(now)            the ticker: warnings, repeats, phase changes
--
-- Messages: TIMERS_CHANGED, TIMER_ADDED(t), TIMER_REMOVED(t), TICK(now),
--           WARN(text, kind), FIGHT_STARTED(fight), FIGHT_ENDED(fight, kill, seconds),
--           PHASE_CHANGED(fight).

local ADDON, ns = ...
local D = ns.EncounterData
local E = {}
ns.Enc = E

ns.Defaults("enc", {
	bars = true, -- the timer bars
	warnings = true, -- big text in the middle of the screen
	sound = true,
	warnBefore = 5, -- seconds before an ability its "soon" warning shows
	dungeons = true, -- a header (name and time) for dungeon and world bosses too
	timeline = true, -- the game's own encounter timeline, as bars
	gameWarnings = true, -- the game's own encounter warnings, in the Pathwise look
	pushTimeline = false, -- Pathwise's timers on the game's timeline as well
	width = 240,
	maxBars = 8,
	pull = 10, -- /pwenc pull, seconds
	breakMinutes = 5, -- /pwenc break, minutes
	range = 10, -- /pwenc range, yards
})

local function now() return GetTime and GetTime() or 0 end
local function readable(v) return ns.Readable(v) end
local function call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end
E.call = call

local function mid(w) return (w[1] + w[2]) / 2 end
local function rough(w) return w[1] ~= w[2] end

-- "1:23", or "8.4" under ten seconds.
function E.Clock(s)
	s = math.max(0, s or 0)
	if s < 10 then return ("%.1f"):format(s) end
	s = math.floor(s + 0.5)
	if s < 60 then return tostring(s) end
	return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- The game's name and icon for a spell, else the data's.
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
function E.SpellName(spec)
	local n = spec.spell and C_Spell and readable(call(C_Spell.GetSpellName, spec.spell))
	return (type(n) == "string" and n ~= "") and n or spec.name
end
function E.SpellIcon(spell)
	local i = spell and C_Spell and readable(call(C_Spell.GetSpellTexture, spell))
	return i or QUESTION
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------

local timers = {}
function E.AddTimer(t)
	assert(t.id and t.ends, "a timer needs an id and an end")
	local old = timers[t.id]
	if old then ns.Fire("TIMER_REMOVED", old) end
	t.started = now()
	t.total = t.total or math.max(0.1, t.ends - t.started)
	timers[t.id] = t
	ns.Fire("TIMER_ADDED", t)
	ns.Fire("TIMERS_CHANGED")
	E.Wake()
	return t
end
function E.RemoveTimer(id)
	local t = timers[id]
	if not t then return end
	timers[id] = nil
	ns.Fire("TIMER_REMOVED", t)
	ns.Fire("TIMERS_CHANGED")
end
function E.Timer(id) return timers[id] end
-- Remove every timer of these kinds (all, without any).
function E.Clear(...)
	local kinds = select("#", ...) > 0 and {} or nil
	for i = 1, select("#", ...) do kinds[select(i, ...)] = true end
	local any = false
	for id, t in pairs(timers) do
		if not kinds or kinds[t.kind] then timers[id] = nil any = true ns.Fire("TIMER_REMOVED", t) end
	end
	if any then ns.Fire("TIMERS_CHANGED") end
end
function E.Remaining(t, at)
	if t.paused then return t.paused end
	return t.ends - (at or now())
end
-- Soonest first.
function E.Timers()
	local list = {}
	for _, t in pairs(timers) do list[#list + 1] = t end
	local at = now()
	table.sort(list, function(a, b)
		local ra, rb = E.Remaining(a, at), E.Remaining(b, at)
		if ra ~= rb then return ra < rb end
		return a.id < b.id
	end)
	return list
end

---------------------------------------------------------------------------
-- A fight
---------------------------------------------------------------------------

local fight
function E.Fight() return fight end

local function schedule(spec, at, approx)
	E.AddTimer({ id = "boss:" .. spec.key, kind = "boss", spec = spec, spell = spec.spell,
		label = E.SpellName(spec), icon = E.SpellIcon(spec.spell), ends = at, approx = approx })
end

local function startPhase(n)
	local p = fight.data.phases[n]
	fight.phase, fight.phaseStart = n, now()
	E.Clear("boss")
	for _, spec in ipairs(p.timers) do
		schedule(spec, fight.phaseStart + mid(spec.first), rough(spec.first))
	end
	ns.Fire("PHASE_CHANGED", fight)
end

function E.PhaseName(f)
	f = f or fight
	if not (f and f.data) then return nil end
	local p = f.data.phases[f.phase]
	if #f.data.phases < 2 then return nil end
	return p and (p.name or ("Phase " .. f.phase))
end

function E.Start(id, name, difficulty, size, test)
	id, name = readable(id), readable(name)
	if type(id) ~= "number" then return end
	if fight then E.Finish(false, true) end
	local data = D.ENCOUNTERS[id]
	local raid = D.RaidOf(id)
	if not data and not raid and not ns.Get("enc.dungeons") then return end
	fight = { id = id, name = (data and data.name) or (type(name) == "string" and name) or D.BOSSES[id] or ("Encounter " .. id),
		data = data, raid = raid, difficulty = readable(difficulty), size = readable(size), start = now(), test = test }
	E.Clear("pull", "boss")
	if data then startPhase(1) end
	ns.Fire("FIGHT_STARTED", fight)
	E.Wake()
	return fight
end

-- The last pulls, newest first, kept between sessions (not settings).
local HISTORY = 100
function E.History() return ns.Data("pulls") end

function E.Finish(kill, quiet)
	local f = fight
	if not f then return end
	fight = nil
	local length = now() - f.start
	E.Clear("boss", "game")
	if not f.test then
		local h = E.History()
		table.insert(h, 1, { id = f.id, name = f.name, kill = kill and true or false, seconds = math.floor(length + 0.5),
			difficulty = f.difficulty, size = f.size, phase = f.phase, when = time and time() or nil })
		while #h > HISTORY do table.remove(h) end
	end
	if not quiet and (f.raid or f.data) then
		ns.Print(("%s: %s %s"):format(f.name, kill and "defeated in" or "wipe after", E.Clock(length)))
		if kill then ns.Fire("WARN", f.name .. " defeated", "kill") end
	end
	ns.Fire("FIGHT_ENDED", f, kill and true or false, length)
end

function E.SetPhase(n)
	n = tonumber(n)
	if not (fight and fight.data) then ns.Print("No boss fight with timers is on.") return false end
	if not (n and fight.data.phases[n]) then
		ns.Print(("%s has phases 1 to %d."):format(fight.name, #fight.data.phases))
		return false
	end
	startPhase(n)
	ns.Fire("WARN", E.PhaseName() or ("Phase " .. n), "phase")
	return true
end

-- A fight without a boss, to see and place the bars (/pwenc test).
function E.Test()
	E.Start(663, "Lucifron", 0, 40, true)
	E.AddTimer({ id = "pull", kind = "pull", label = "Pull", icon = QUESTION, ends = now() + 10, total = 10 })
end
function E.Stop()
	if fight then E.Finish(false, true) end
	E.Clear()
end

---------------------------------------------------------------------------
-- The ticker
---------------------------------------------------------------------------

local ENDINGS = { pull = "Pull!", ["break"] = "Break is over" }

function E.Update(at)
	at = at or now()
	if fight and fight.data then
		local p = fight.data.phases[fight.phase]
		if p.after and at >= fight.phaseStart + p.after then
			startPhase(p.next or fight.phase + 1)
			ns.Fire("WARN", E.PhaseName() or "Next phase", "phase")
		end
	end
	local soon = ns.Get("enc.warnBefore") or 5
	for id, t in pairs(timers) do
		if not t.paused then
			local left = t.ends - at
			if t.kind == "boss" and not t.warned and left <= soon then
				t.warned = true
				ns.Fire("WARN", t.label .. (left > 0.5 and " soon" or ""), "soon")
			end
			if left <= 0 then
				local spec = t.kind == "boss" and t.spec
				if spec and spec.every then
					-- The next cast, counted from when this one was due: drift adds up,
					-- which is why every bar of Pathwise's own says "about".
					local ends, guard = t.ends, 0
					repeat ends, guard = ends + mid(spec.every), guard + 1 until ends > at or guard > 1000
					schedule(spec, ends, true)
				elseif t.kind == "game" then
					if left <= -(t.hold or 0) - 2 then E.RemoveTimer(id) end
				else
					E.RemoveTimer(id)
					if ENDINGS[t.kind] then ns.Fire("WARN", ENDINGS[t.kind], t.kind) end
				end
			end
		end
	end
	ns.Fire("TICK", at)
end

-- One frame ticks while there is anything to count (10 times a second).
local ticker = CreateFrame("Frame")
ticker:Hide()
local since = 0
ticker:SetScript("OnUpdate", function(self, dt)
	since = since + (dt or 0)
	if since < 0.1 then return end
	since = 0
	E.Update(now())
	if not fight and not next(timers) then self:Hide() end
end)
function E.Wake() ticker:Show() end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------

ns.RegisterEvent("ENCOUNTER_START", function(_, id, name, difficulty, size) E.Start(id, name, difficulty, size) end)
ns.RegisterEvent("ENCOUNTER_END", function(_, id, name, difficulty, size, success)
	id = readable(id)
	if fight and fight.id == id then E.Finish(readable(success) == 1) end
end)
ns.RegisterEvent("BOSS_KILL", function(_, id)
	id = readable(id)
	if fight and fight.id == id then E.Finish(true) end
end)
-- After a reload or a loading screen: drop a fight the game says is over.
ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	if fight and not fight.test and C_InstanceEncounter then
		local on = readable(call(C_InstanceEncounter.IsEncounterInProgress))
		if on == false then E.Finish(false, true) end
	end
end)

ns.Commands.phase = function(rest) E.SetPhase(rest) end
ns.Commands.test = function() E.Test() end
ns.Commands.stop = function() E.Stop() end
