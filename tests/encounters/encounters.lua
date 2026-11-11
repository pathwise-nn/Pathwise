-- Tests for Pathwise Encounters: a fight's start and end, its timers, warnings
-- and phases, the pull history, the game's own timeline and warnings (with
-- secret values), pull and break timers, the range check, the data's shape
-- and the options page.
local h = ...
local test, eq, near, ok = h.test, h.eq, h.near, h.ok

-- Forever's client APIs this addon calls, as a test wants them. Every test
-- sets them all, so none leaks from one test into the next.
local function client(o)
	o = o or {}
	return function(s)
		s.sent, s.countdowns, s.scripted, s.canceled = {}, {}, {}, {}
		s.group = o.group or false
		function IsInGroup() return s.group end
		function IsInRaid() return o.raid or false end
		C_PartyInfo = { DoCountdown = function(sec)
			s.countdowns[#s.countdowns + 1] = sec
			if o.refuse then error("not allowed") end
			return true
		end }
		C_ChatInfo = {
			RegisterAddonMessagePrefix = function(p) s.prefix = p return 0 end,
			SendAddonMessage = function(prefix, text, chan) s.sent[#s.sent + 1] = { prefix, text, chan } return 0 end,
		}
		C_Spell = { GetSpellName = function(id) return o.spellNames and o.spellNames[id] end, GetSpellTexture = function(id) return 136000 + (id % 1000) end }
		C_EncounterTimeline = {
			AddScriptEvent = function(info) s.scripted[#s.scripted + 1] = info return #s.scripted end,
			CancelScriptEvent = function(id) s.canceled[#s.canceled + 1] = id end,
			GetEventState = function(id) return s.timelineState and s.timelineState[id] end,
		}
		C_InstanceEncounter = { IsEncounterInProgress = function() return o.inProgress or false end }
		SOUNDKIT = { RAID_WARNING = 8959 }
		Enum = Enum or {}
		Enum.EncounterTimelineEventSource = { Encounter = 0, Script = 1, EditMode = 2 }
		Enum.EncounterTimelineEventState = { Active = 0, Paused = 1, Finished = 2, Canceled = 3 }
		Enum.EncounterEventSeverity = { Low = 0, Medium = 1, High = 2 }
		s.distances = o.distances or {}
		function UnitDistanceSquared(u)
			local d = s.distances[u]
			if d == nil then return 0, false end
			return d, true
		end
		function UnitIsUnit(a, b) return a == b end
		if o.setup then o.setup(s) end
	end
end

local function fresh(o) return h.fresh(client(o)) end

-- Time passes: the clock moves, and the ticker runs.
local function wait(stub, seconds)
	local step = 0.1
	for _ = 1, math.floor(seconds / step + 0.5) do
		stub.now = stub.now + step
		stub.advance(step)
	end
end

local function timer(ns, id) return ns.Enc.Timer(id) end
local function labels(ns)
	local out = {}
	for _, t in ipairs(ns.Enc.Timers()) do out[#out + 1] = tostring(t.label) end
	return table.concat(out, ", ")
end
local function warning(stub, ns) return stub.shown(ns.EncWarnings.text) end

---------------------------------------------------------------------------
-- A fight
---------------------------------------------------------------------------

test("fight: Lucifron's pull starts his timers, from Forever's encounter id", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	local f = ns.Enc.Fight()
	ok(f and f.id == 663 and f.name == "Lucifron", "the fight is on")
	eq(labels(ns), "Impending Doom, Lucifron's Curse", "soonest first")
	local doom = timer(ns, "boss:doom")
	near(doom.ends - stub.now, 7.5, 1e-6, "Impending Doom at the middle of 5-10 s")
	ok(doom.approx, "a window, so 'about'")
	ok(_G.PathwiseEncounters_Bars.shown, "the bars show")
	ok(stub.shown(ns.EncBars.header):find("Lucifron", 1, true), "the header names him")
	local row = ns.EncBars.Rows()[1]
	eq(stub.shown(row.label), "Impending Doom")
	eq(stub.shown(row.about), "about")
	eq(row.icon.texture, 136702, "the game's icon for the spell")
end)

test("fight: the game's spell name wins over the data's", function()
	local stub, ns = fresh({ spellNames = { [19702] = "Drohendes Verderben" } })
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	eq(timer(ns, "boss:doom").label, "Drohendes Verderben")
end)

test("fight: a warning before the ability, then the timer repeats", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	wait(stub, 2.0)
	ok(not (_G.PathwiseEncounters_Warning and _G.PathwiseEncounters_Warning.shown), "nothing yet")
	wait(stub, 0.6) -- 5 s before 7.5
	eq(warning(stub, ns), "Impending Doom soon")
	ok(#stub.sounds >= 1 and stub.sounds[#stub.sounds] == 8959, "the raid warning sound")
	wait(stub, 5.1)
	local doom = timer(ns, "boss:doom")
	near(doom.ends - stub.now, 22.5 - 0.2, 0.11, "next one 22.5 s (20-25) after the last was due")
	ok(not doom.warned, "warns again next time")
end)

test("fight: warnings and sound can be switched off", function()
	local stub, ns = fresh()
	ns.Set("enc.warnings", false)
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	wait(stub, 3)
	ok(not _G.PathwiseEncounters_Warning, "no warning frame")
	ns.Set("enc.warnings", true)
	ns.Set("enc.sound", false)
	wait(stub, 5)
	eq(#stub.sounds, 0, "no sound")
end)

test("fight: a wipe clears the bars and is kept in the pull history", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	wait(stub, 61)
	stub.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
	ok(ns.Enc.Fight() == nil, "over")
	eq(#ns.Enc.Timers(), 0, "no timers left")
	ok(not _G.PathwiseEncounters_Bars.shown, "bars hidden")
	local p = ns.Enc.History()[1]
	ok(p and p.id == 663 and p.kill == false and p.seconds == 61, "a 61 s wipe")
	ok(h.lastPrint(stub):find("Lucifron: wipe after 1:01", 1, true), h.lastPrint(stub))
	ok(PathwiseEncountersSettings.data.pulls[1] == p, "kept in the saved variables, apart from settings")
end)

test("fight: a kill, by ENCOUNTER_END or BOSS_KILL, says so", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 664, "Magmadar", 9, 40)
	wait(stub, 2)
	stub.fire("BOSS_KILL", 664, "Magmadar")
	eq(ns.Enc.History()[1].kill, true)
	eq(warning(stub, ns), "Magmadar defeated")
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	stub.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
	eq(ns.Enc.History()[1].kill, true, "success = 1 is a kill")
	eq(#ns.Enc.History(), 2)
end)

test("fight: another encounter's end doesn't stop this one", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	stub.fire("ENCOUNTER_END", 664, "Magmadar", 9, 40, 0)
	ok(ns.Enc.Fight(), "still on")
end)

test("fight: a boss without timers gets its name and the fight's time only", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 617, "Nefarian", 9, 40)
	local f = ns.Enc.Fight()
	ok(f and f.name == "Nefarian" and f.raid.key == "bwl", "a raid boss we know")
	eq(#ns.Enc.Timers(), 0, "no timers: a marked gap")
	ok(_G.PathwiseEncounters_Bars.shown, "the header still shows")
	wait(stub, 12)
	ok(stub.shown(ns.EncBars.header):find("Nefarian   12", 1, true), stub.shown(ns.EncBars.header))
	stub.fire("ENCOUNTER_END", 617, "Nefarian", 9, 40, 0)
	ok(h.lastPrint(stub):find("Nefarian: wipe", 1, true), "raid wipes are said")
end)

test("fight: dungeon bosses only when asked", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 227, "High Interrogator Gerstahn", 1, 5)
	eq(ns.Enc.Fight().name, "High Interrogator Gerstahn", "the game's name")
	stub.fire("ENCOUNTER_END", 227, "High Interrogator Gerstahn", 1, 5, 1)
	ok(not h.lastPrint(stub):find("Gerstahn", 1, true), "a dungeon kill isn't announced in chat")
	ns.Set("enc.dungeons", false)
	stub.fire("ENCOUNTER_START", 227, "High Interrogator Gerstahn", 1, 5)
	ok(ns.Enc.Fight() == nil, "off: no header")
end)

test("fight: a secret encounter id is ignored, not an error", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", stub.Secret(663), stub.Secret("Lucifron"), 9, 40)
	ok(ns.Enc.Fight() == nil)
end)

test("fight: after a loading screen, a fight the game says is over is dropped", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	stub.fire("PLAYER_ENTERING_WORLD")
	ok(ns.Enc.Fight() == nil)
	eq(#ns.Enc.History(), 1, "kept as a wipe")
end)

---------------------------------------------------------------------------
-- Phases
---------------------------------------------------------------------------

test("phases: Ragnaros goes under after 3 minutes and comes back", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 672, "Ragnaros", 9, 40)
	ok(timer(ns, "boss:wrath") and timer(ns, "boss:submerge"), "phase 1 timers")
	wait(stub, 180.2)
	eq(ns.Enc.Fight().phase, 2)
	eq(labels(ns), "Ragnaros emerges", "only the emerge timer while the Sons fight")
	ok(stub.shown(ns.EncBars.header):find("Sons of Flame", 1, true), "the header names the phase")
	wait(stub, 93.6)
	eq(ns.Enc.Fight().phase, 3)
	near(timer(ns, "boss:wrath").ends - stub.now, 20, 0.11, "Wrath 20 s after he emerges")
end)

test("phases: Onyxia moves on when the raid says so", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 1084, "Onyxia", 9, 40)
	eq(labels(ns), "Flame Breath, Wing Buffet, Knock Away")
	SlashCmdList.PATHWISEENCOUNTERS("phase 2")
	eq(labels(ns), "Whelps")
	eq(warning(stub, ns), "Phase 2 (in the air)")
	SlashCmdList.PATHWISEENCOUNTERS("phase 3")
	ok(timer(ns, "boss:roar"), "Bellowing Roar")
	wait(stub, 0.2)
	ok(warning(stub, ns):find("Bellowing Roar", 1, true), "right away in phase 3")
	SlashCmdList.PATHWISEENCOUNTERS("phase 9")
	ok(h.lastPrint(stub):find("phases 1 to 3", 1, true), h.lastPrint(stub))
	eq(ns.Enc.Fight().phase, 3, "unchanged")
end)

test("phases: no fight, no phase", function()
	local stub, ns = fresh()
	eq(ns.Enc.SetPhase(2), false)
	ok(h.lastPrint(stub):find("No boss fight", 1, true))
end)

---------------------------------------------------------------------------
-- The game's own timeline and warnings
---------------------------------------------------------------------------

test("game: a timeline event becomes a bar, its secret name drawn as it is", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	stub.fire("ENCOUNTER_TIMELINE_EVENT_ADDED", { id = 41, source = 0, spellName = stub.Secret("Shadow Shock"),
		iconFileID = stub.Secret(135000), duration = 3, maxQueueDuration = 0 })
	local t = timer(ns, "game:41")
	ok(t and t.kind == "game", "a game bar")
	eq(ns.Enc.Timers()[1], t, "soonest")
	local row = ns.EncBars.Rows()[1]
	ok(issecretvalue(row.label.text), "the secret name, passed straight on")
	eq(stub.shown(row.label), "Shadow Shock")
	ok(issecretvalue(row.icon.texture), "the secret icon too")
	stub.fire("ENCOUNTER_TIMELINE_EVENT_REMOVED", 41)
	ok(timer(ns, "game:41") == nil, "removed with the game's")
end)

test("game: paused and canceled timeline events", function()
	local stub, ns = fresh({ setup = function(s) s.timelineState = {} end })
	stub.fire("ENCOUNTER_TIMELINE_EVENT_ADDED", { id = 7, source = 0, spellName = "Thing", iconFileID = 1, duration = 20 })
	wait(stub, 5)
	stub.timelineState[7] = 1
	stub.fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 7)
	near(timer(ns, "game:7").paused, 15, 0.11, "paused with 15 s left")
	wait(stub, 10)
	near(ns.Enc.Remaining(timer(ns, "game:7")), 15, 0.11, "still 15")
	stub.timelineState[7] = 0
	stub.fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 7)
	near(ns.Enc.Remaining(timer(ns, "game:7")), 15, 0.11, "running again")
	stub.timelineState[7] = 3
	stub.fire("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", 7)
	ok(timer(ns, "game:7") == nil, "canceled")
end)

test("game: an addon's own timeline events aren't shown twice, and the option turns them off", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_TIMELINE_EVENT_ADDED", { id = 8, source = 1, spellName = "Ours", duration = 9 })
	stub.fire("ENCOUNTER_TIMELINE_EVENT_ADDED", { id = 9, source = 2, spellName = "Edit Mode", duration = 9 })
	eq(#ns.Enc.Timers(), 0)
	ns.Set("enc.timeline", false)
	stub.fire("ENCOUNTER_TIMELINE_EVENT_ADDED", { id = 10, source = 0, spellName = "Theirs", duration = 9 })
	eq(#ns.Enc.Timers(), 0)
end)

test("game: an encounter warning, secret text and all, in the Pathwise style", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_WARNING", { text = stub.Secret("Living Bomb on you!"), severity = 2, shouldShowWarning = true, shouldPlaySound = true })
	ok(issecretvalue(ns.EncWarnings.text.text), "passed straight on")
	eq(warning(stub, ns), "Living Bomb on you!")
	eq(#stub.sounds, 1, "the game asked for a sound")
	ns.EncWarnings.text.text = ""
	stub.fire("ENCOUNTER_WARNING", { text = stub.Secret("Hidden"), severity = 0, shouldShowWarning = false })
	eq(warning(stub, ns), "", "not when the game says not to")
	ns.Set("enc.gameWarnings", false)
	stub.fire("ENCOUNTER_WARNING", { text = "Off", severity = 1, shouldShowWarning = true })
	eq(warning(stub, ns), "")
end)

test("game: Pathwise's timers go onto the game's timeline only when asked", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	eq(#stub.scripted, 0, "off by default")
	ns.Enc.Stop()
	ns.Set("enc.pushTimeline", true)
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	eq(#stub.scripted, 2)
	local e = stub.scripted[1]
	ok(e.spellID == 19702 or e.spellID == 19703, "the spell")
	ok(type(e.duration) == "number" and e.duration > 0 and not issecretvalue(e.duration), "plain values")
	stub.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 0)
	eq(#stub.canceled, 2, "taken off when the fight ends")
end)

---------------------------------------------------------------------------
-- Pull, break, range
---------------------------------------------------------------------------

test("pull: in a group it's the game's countdown, and its bar", function()
	local stub, ns = fresh({ group = true })
	SlashCmdList.PATHWISEENCOUNTERS("pull 12")
	eq(stub.countdowns[1], 12, "C_PartyInfo.DoCountdown(12)")
	ok(timer(ns, "pull") == nil, "the bar waits for the game's event")
	stub.fire("START_PLAYER_COUNTDOWN", "Player-1", 12, 12, true, "Frozen")
	near(timer(ns, "pull").ends - stub.now, 12, 1e-6)
	wait(stub, 12.2)
	ok(timer(ns, "pull") == nil, "done")
	eq(warning(stub, ns), "Pull!")
end)

test("pull: the boss's pull ends the countdown bar; cancel and refusals", function()
	local stub, ns = fresh({ group = true, refuse = true })
	ns.EncGroup.Pull(8)
	ok(h.lastPrint(stub):find("just for you", 1, true), "the game refused: a bar for you")
	ok(timer(ns, "pull"), "local bar")
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	ok(timer(ns, "pull") == nil, "pulled")
	ns.EncGroup.Pull(8)
	eq(ns.EncGroup.Pull(0), "canceled")
	ok(timer(ns, "pull") == nil)
	eq(stub.countdowns[#stub.countdowns], 0, "the game's countdown canceled too")
	stub.fire("START_PLAYER_COUNTDOWN", "Player-1", 10, 10, true)
	stub.fire("CANCEL_PLAYER_COUNTDOWN", "Player-1")
	ok(timer(ns, "pull") == nil, "someone else canceled it")
end)

test("pull: alone, a bar just for you, with the default length", function()
	local stub, ns = fresh()
	eq(ns.EncGroup.Pull(), "local")
	eq(#stub.countdowns, 0, "no group countdown")
	near(timer(ns, "pull").ends - stub.now, 10, 1e-6)
	stub.fire("START_PLAYER_COUNTDOWN", "Player-1", stub.Secret(5), stub.Secret(5), true)
	near(timer(ns, "pull").ends - stub.now, 10, 1e-6, "a secret countdown is left alone")
end)

test("break: a bar, sent to the group; one from the group starts one too", function()
	local stub, ns = fresh({ group = true, raid = true })
	eq(stub.prefix, "PathwiseEnc", "its addon message prefix")
	SlashCmdList.PATHWISEENCOUNTERS("break 3")
	near(timer(ns, "break").ends - stub.now, 180, 1e-6)
	eq(stub.sent[1][1], "PathwiseEnc")
	eq(stub.sent[1][2], "BREAK:180")
	eq(stub.sent[1][3], "RAID")
	ns.Enc.RemoveTimer("break")
	stub.fire("CHAT_MSG_ADDON", "PathwiseEnc", "BREAK:120", "RAID", "Florp")
	near(timer(ns, "break").ends - stub.now, 120, 1e-6)
	stub.fire("CHAT_MSG_ADDON", "PathwiseEnc", "BREAK:0", "RAID", "Florp")
	ok(timer(ns, "break") == nil, "0 ends it")
	stub.fire("CHAT_MSG_ADDON", "OtherAddon", "BREAK:60", "RAID", "Florp")
	stub.fire("CHAT_MSG_ADDON", stub.Secret("PathwiseEnc"), "BREAK:60", "RAID", "Florp")
	ok(timer(ns, "break") == nil, "other prefixes and secret ones ignored")
end)

test("range: who's close, while the game gives distances", function()
	local stub, ns = fresh({ group = true, distances = { party1 = 25, party2 = 400 }, setup = function(s)
		s.units.party1 = { name = "Florp", player = true }
		s.units.party2 = { name = "Brakk", player = true }
	end })
	SlashCmdList.PATHWISEENCOUNTERS("range 10")
	ok(_G.PathwiseEncounters_Range.shown)
	eq(stub.shown(ns.EncGroup.rangeTitle), "Within 10 yards")
	eq(stub.shown(ns.EncGroup.rangeBody), "1 player that close: Florp")
	stub.distances.party1 = nil
	stub.distances.party2 = nil
	ns.EncGroup.UpdateRange()
	ok(stub.shown(ns.EncGroup.rangeBody):find("isn't telling addons distances", 1, true), "says so in a fight")
	stub.distances.party1 = stub.Secret(4)
	ns.EncGroup.UpdateRange()
	ok(stub.shown(ns.EncGroup.rangeBody):find("isn't telling", 1, true), "a secret distance is unknown")
	SlashCmdList.PATHWISEENCOUNTERS("range")
	ok(not _G.PathwiseEncounters_Range.shown, "again to close")
end)

test("range: alone", function()
	local stub, ns = fresh()
	eq(ns.EncGroup.RangeText(10), "No one else in your group.")
end)

---------------------------------------------------------------------------
-- The data
---------------------------------------------------------------------------

test("data: every encounter has a source, and every timer a sane window", function()
	local stub, ns = fresh()
	local D = ns.EncounterData
	local n = 0
	for id, e in pairs(D.ENCOUNTERS) do
		ok(type(e.name) == "string" and e.name ~= "", id .. ": a name")
		ok(type(e.source) == "string" and e.source:find("cmangos", 1, true), id .. ": names its source")
		ok(D.RaidOf(id), id .. ": in a raid's list")
		ok(#e.phases >= 1, id .. ": a phase")
		for pi, p in ipairs(e.phases) do
			if p.after then ok(p.after > 0 and e.phases[p.next or pi + 1], id .. ": its next phase exists") end
			local keys = {}
			for _, t in ipairs(p.timers) do
				n = n + 1
				ok(not keys[t.key], id .. ": " .. t.key .. " once per phase")
				keys[t.key] = true
				ok(type(t.name) == "string", id .. ": " .. t.key .. " named")
				ok(t.spell == nil or (type(t.spell) == "number" and t.spell > 0), id .. ": " .. t.key .. " spell id")
				ok(t.first[1] >= 0 and t.first[2] >= t.first[1], id .. ": " .. t.key .. " first window")
				if t.every then ok(t.every[1] > 0 and t.every[2] >= t.every[1], id .. ": " .. t.key .. " repeat window") end
			end
		end
	end
	ok(n >= 25, "Molten Core and Onyxia have their timers: " .. n)
	for _, r in ipairs(D.RAIDS) do
		for _, id in ipairs(r.ids) do ok(D.ENCOUNTERS[id] or D.BOSSES[id], id .. ": named") end
	end
end)

---------------------------------------------------------------------------
-- Options and moving
---------------------------------------------------------------------------

test("options: the Encounters page says what's covered, and lists your pulls", function()
	local stub, ns = fresh()
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	wait(stub, 30)
	stub.fire("ENCOUNTER_END", 663, "Lucifron", 9, 40, 1)
	SlashCmdList.PATHWISEENCOUNTERS("")
	local text = table.concat(stub.texts(), "|")
	ok(text:find("Molten Core and Onyxia's Lair", 1, true), "what has timers")
	ok(text:find("Blackwing Lair", 1, true), "what doesn't")
	ok(text:find("Lucifron: kill, 30", 1, true), "the pull")
	ok(stub.clickLabel("Clear them"))
	eq(#ns.Enc.History(), 0)
end)

test("options: test bars, moving them, and the saved place", function()
	local stub, ns = fresh()
	SlashCmdList.PATHWISEENCOUNTERS("test")
	ok(ns.Enc.Fight() and ns.Enc.Fight().test, "a test fight")
	ok(timer(ns, "pull") and timer(ns, "boss:doom"), "bars to look at")
	SlashCmdList.PATHWISEENCOUNTERS("stop")
	ok(ns.Enc.Fight() == nil and #ns.Enc.Timers() == 0)
	eq(#ns.Enc.History(), 0, "a test isn't a pull")
	ns.EncBars.Unlock(true)
	ok(ns.EncBars.Unlocked() and _G.PathwiseEncounters_Bars.shown, "shown to be moved")
	ns.Set("enc.point", { "TOP", "TOP", 0, -100 })
	local p = _G.PathwiseEncounters_Bars.points[1]
	eq(p[1], "TOP")
	eq(p[5], -100)
	ns.EncBars.Unlock(false)
	ok(not _G.PathwiseEncounters_Bars.shown, "locked and nothing to show: hidden")
	ns.Set("enc.bars", false)
	stub.fire("ENCOUNTER_START", 663, "Lucifron", 9, 40)
	ok(not _G.PathwiseEncounters_Bars.shown, "bars off")
end)

test("look: the range window is rounded, the timer bars square", function()
	local stub, ns = fresh({ group = true, distances = { party1 = 25 }, setup = function(s)
		s.units.party1 = { name = "Florp", player = true }
	end })
	SlashCmdList.PATHWISEENCOUNTERS("range 10")
	local r = _G.PathwiseEncounters_Range
	eq(r.pwRadius, 10, "a rounded window")
	ok(r.pwGround.pieces and #r.pwBorder.edges == 4, "pieced ground and border")
	ns.Theme.UseScheme("sand")
	near(r.pwGround.color[1], 0xFB / 255, 1e-6, "a light theme repaints it")
end)
