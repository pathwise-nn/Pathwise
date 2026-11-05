-- The game's own boss mod, in the Pathwise look.
--
-- Forever's client has Blizzard's encounter timeline (C_EncounterTimeline)
-- and encounter warnings (C_EncounterWarnings). Whether Forever's servers
-- send any events for its Classic raids is not known yet (not checked in
-- game); when they do:
--   * each timeline event becomes a bar. Its id and duration are never
--     secret; its spell name and icon may be, and are drawn as they come.
--   * each ENCOUNTER_WARNING is shown as a Pathwise warning. Its text is
--     secret; whether to show it and to play a sound are plain.
-- And, if you want (enc.pushTimeline), Pathwise's own timers go onto the
-- game's timeline too (AddScriptEvent takes plain values only, which ours are).

local ADDON, ns = ...
local E = ns.Enc
local W = ns.EncWarnings
local call, readable = E.call, ns.Readable

local function enum(set, key, fallback)
	local e = Enum and Enum[set]
	return (e and e[key] ~= nil) and e[key] or fallback
end
local function TL() return C_EncounterTimeline end

---------------------------------------------------------------------------
-- The game's timeline, as bars
---------------------------------------------------------------------------

ns.RegisterEvent("ENCOUNTER_TIMELINE_EVENT_ADDED", function(_, info)
	if not ns.Get("enc.timeline") or type(info) ~= "table" then return end
	local source = readable(info.source)
	if source == enum("EncounterTimelineEventSource", "Script", 1) or source == enum("EncounterTimelineEventSource", "EditMode", 2) then
		return -- an addon's (ours too) or Edit Mode's preview
	end
	local id, duration = readable(info.id), readable(info.duration)
	if type(id) ~= "number" or type(duration) ~= "number" then return end
	E.AddTimer({ id = "game:" .. id, kind = "game", gameID = id, label = info.spellName, icon = info.iconFileID,
		ends = (GetTime() or 0) + duration, total = duration, hold = readable(info.maxQueueDuration) or 0 })
end)

ns.RegisterEvent("ENCOUNTER_TIMELINE_EVENT_REMOVED", function(_, id)
	id = readable(id)
	if id then E.RemoveTimer("game:" .. id) end
end)

ns.RegisterEvent("ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED", function(_, id)
	id = readable(id)
	local t = id and E.Timer("game:" .. id)
	if not (t and TL()) then return end
	local state = readable(call(TL().GetEventState, id))
	if state == enum("EncounterTimelineEventState", "Paused", 1) then
		t.paused = t.paused or math.max(0, t.ends - GetTime())
	elseif state == enum("EncounterTimelineEventState", "Active", 0) then
		if t.paused then t.ends, t.paused = GetTime() + t.paused, nil end
	elseif state == enum("EncounterTimelineEventState", "Finished", 2) or state == enum("EncounterTimelineEventState", "Canceled", 3) then
		E.RemoveTimer(t.id)
	end
	ns.Fire("TIMERS_CHANGED")
end)

---------------------------------------------------------------------------
-- The game's warnings
---------------------------------------------------------------------------

ns.RegisterEvent("ENCOUNTER_WARNING", function(_, info)
	if not ns.Get("enc.gameWarnings") or type(info) ~= "table" then return end
	if readable(info.shouldShowWarning) == false then return end
	local high = readable(info.severity) == enum("EncounterEventSeverity", "High", 2)
	W.Show(info.text, high and "gameHigh" or "game")
	if readable(info.shouldPlaySound) then W.Sound() end
end)

---------------------------------------------------------------------------
-- Pathwise's timers on the game's timeline (off by default)
---------------------------------------------------------------------------

ns.On("TIMER_ADDED", function(t)
	if t.kind ~= "boss" or not ns.Get("enc.pushTimeline") or not (TL() and TL().AddScriptEvent) then return end
	local left = t.ends - GetTime()
	if left <= 0 then return end
	t.scriptID = readable(call(TL().AddScriptEvent, {
		spellID = t.spell or 0,
		iconFileID = type(t.icon) == "number" and t.icon or 0,
		duration = left,
		overrideName = t.label,
	}))
end)
ns.On("TIMER_REMOVED", function(t)
	if t.scriptID and TL() then call(TL().CancelScriptEvent, t.scriptID) t.scriptID = nil end
end)
