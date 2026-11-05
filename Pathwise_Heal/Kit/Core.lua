-- COPIED from PathwiseUI/Core.lua by tools/kit.js: do not edit here.
-- Edit PathwiseUI/Core.lua, then run npm run kit.
-- Settings, messages and game events for a Pathwise addon (Pathwise UI,
-- Pathwise Heal: this file is shared; who it serves is ns.ID, from the
-- addon's Identity.lua). Works on its own; with Pathwise installed too it
-- shares the accent color and is listed in Pathwise's suite.
--
-- Shared file: PathwiseUI/ holds the original; tools/kit.js copies it into
-- Pathwise_Heal/Kit/. Edit it here, then run npm run kit.
--
--   ns.Get(path) / ns.Set(path, value) / ns.Defaults(section, table)
--       settings, "section.key"; per character or for every character
--       (the "profile.shared" setting decides; on by default)
--   ns.On(message, fn) / ns.Fire(message, ...)
--   ns.RegisterEvent(event, fn)   an event the client lacks is skipped, not an error
--   ns.Print(...), ns.Readable(v)
--
-- Messages: LOADED (settings readable), READY (logged in), SETTING_CHANGED(path, value).

local ADDON, ns = ...
local ID = assert(ns.ID, "Identity.lua must load first")
_G[ID.global] = ns
ns.NAME = ID.name
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"

-- Forever can hand addons "secret" values; they are unusable, so nil.
function ns.Readable(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end

---------------------------------------------------------------------------
-- Messages
---------------------------------------------------------------------------

local listeners = {}
function ns.On(msg, fn)
	listeners[msg] = listeners[msg] or {}
	table.insert(listeners[msg], fn)
end
function ns.Fire(msg, ...)
	for _, fn in ipairs(listeners[msg] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Error(msg, err) end
	end
end

local seen = {}
function ns.Error(where, err)
	local key = tostring(where) .. tostring(err)
	if seen[key] then return end
	seen[key] = true
	ns.Print(("|cffE66B78error|r in %s: %s"):format(tostring(where), tostring(err)))
end

function ns.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local text = "|cff66D7FF" .. ID.name .. "|r  " .. table.concat(parts, " ")
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(text) end
end

---------------------------------------------------------------------------
-- Game events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local events = {}
local unknown = {}
function ns.RegisterEvent(event, fn)
	if unknown[event] then return false end
	if not events[event] then
		if not pcall(frame.RegisterEvent, frame, event) then
			unknown[event] = true
			return false
		end
		events[event] = {}
	end
	table.insert(events[event], fn)
	return true
end
function ns.UnknownEvents() return unknown end
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(events[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then ns.Error(event, err) end
	end
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local SCHEMA = 1
local defaults = {}
function ns.Defaults(section, tbl)
	defaults[section] = defaults[section] or {}
	for k, v in pairs(tbl) do defaults[section][k] = v end
end
ns.Defaults("profile", { shared = true })

local function split(path)
	return path:match("^([^.]+)%.(.+)$")
end

local function account()
	local a = _G[ID.saved]
	if type(a) ~= "table" or a.schema ~= SCHEMA then
		a = { schema = SCHEMA }
		_G[ID.saved] = a
	end
	return a
end
local function character()
	if type(_G[ID.charSaved]) ~= "table" then _G[ID.charSaved] = {} end
	return _G[ID.charSaved]
end

-- Where settings live: every character's (shared) or this character's own.
-- The "profile" section itself always lives with the character.
local function store(section)
	if section == "profile" then return character() end
	local shared = character().profile
	shared = not (type(shared) == "table" and shared.shared == false)
	return shared and account() or character()
end

function ns.Get(path)
	local section, key = split(path)
	if not section then return nil end
	local s = store(section)[section]
	if type(s) == "table" and s[key] ~= nil then return s[key] end
	local d = defaults[section]
	return d and d[key]
end

function ns.Set(path, value)
	local section, key = split(path)
	if not section then return end
	local st = store(section)
	if type(st[section]) ~= "table" then st[section] = {} end
	local d = defaults[section]
	if d and d[key] == value then value = nil end
	if st[section][key] == value then return end
	st[section][key] = value
	ns.Fire("SETTING_CHANGED", path, ns.Get(path))
end

-- Back to the defaults: this profile's settings, or one section of them.
function ns.Reset(section)
	local st = store(section or "x")
	if section then st[section] = nil else
		for k in pairs(st) do if k ~= "schema" and k ~= "profile" and k ~= "data" then st[k] = nil end end
	end
	ns.Fire("SETTING_CHANGED", section and (section .. ".*") or "*")
end

-- Copy every character's settings into this character's own, or back.
function ns.SetShared(on)
	local from, to = store("x"), nil
	character().profile = character().profile or {}
	character().profile.shared = on and true or false
	to = store("x")
	if from ~= to then
		for k, v in pairs(from) do
			if k ~= "schema" and k ~= "profile" and k ~= "data" and to[k] == nil and type(v) == "table" then
				local c = {}
				for kk, vv in pairs(v) do c[kk] = vv end
				to[k] = c
			end
		end
	end
	ns.Fire("SETTING_CHANGED", "profile.shared", on)
end

-- Account-wide records that are not settings (every character's gold...):
-- kept apart, so "Back to the defaults" never clears them.
function ns.Data(name)
	local a = account()
	a.data = type(a.data) == "table" and a.data or {}
	a.data[name] = type(a.data[name]) == "table" and a.data[name] or {}
	return a.data[name]
end

-- This character's own records (its click-casting, whether it was asked
-- about healing frames): always per character, never shared or reset.
function ns.CharData(name)
	local c = character()
	c.data = type(c.data) == "table" and c.data or {}
	c.data[name] = type(c.data[name]) == "table" and c.data[name] or {}
	return c.data[name]
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------

ns.RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	account()
	character()
	ns.Fire("LOADED")
end)
ns.RegisterEvent("PLAYER_LOGIN", function() ns.Fire("READY") end)

-- Is Pathwise (the guide) installed? Its suite API, or nil.
function ns.Suite() return _G.Pathwise and _G.Pathwise.Suite or nil end

-- The other Pathwise addons built on these shared files (they keep one
-- accent between them), in the order whose accent wins at login.
ns.PEERS = { "PathwiseUI", "PathwiseHeal" }
function ns.Peers()
	local out = {}
	for _, g in ipairs(ns.PEERS) do
		local p = _G[g]
		if g ~= ID.global and type(p) == "table" and p.Get then out[#out + 1] = p end
	end
	return out
end

-- Slash commands: "move" for move mode, any in ns.Commands (word -> fn(rest)),
-- else the options.
ns.Commands = {}
for i, cmd in ipairs(ID.slash) do _G["SLASH_" .. ID.slashKey .. i] = cmd end
SlashCmdList[ID.slashKey] = function(msg)
	msg = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.-)$")
	cmd = (cmd or ""):lower()
	if cmd == "move" then ns.Fire("MOVE_ALL")
	elseif ns.Commands[cmd] then ns.Commands[cmd](rest or "")
	else ns.Fire("SHOW_CONFIG") end
end
