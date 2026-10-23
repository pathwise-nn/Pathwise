-- Pathwise core: the namespace, events, a small message bus, settings and
-- slash commands. Everything else hangs off `ns`; the public table
-- `Pathwise` is what other addons may call.

local ADDON, ns = ...

Pathwise = Pathwise or {}
ns.API = Pathwise

local type, pairs, ipairs, select, tostring = type, pairs, ipairs, select, tostring

local function meta(field)
	local get = C_AddOns and C_AddOns.GetAddOnMetadata
	return get and get(ADDON, field) or nil
end
ns.VERSION = meta("Version") or "dev"
ns.NAME = "Pathwise"

---------------------------------------------------------------------------
-- Printing
---------------------------------------------------------------------------

function ns.Print(...)
	local parts = {}
	for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
	local line = "|cff66d7ffPathwise|r  " .. table.concat(parts, " ")
	if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(line) else print(line) end
end

---------------------------------------------------------------------------
-- Game events: one frame, many listeners per event
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local gameListeners = {}

-- ns.RegisterEvent(event, fn): fn(event, ...) on every firing. An event the
-- client does not have (names differ between WoW versions) is skipped, never
-- an error. -> true when the event exists
local unknownEvents = {}
function ns.RegisterEvent(event, fn)
	if unknownEvents[event] then return false end
	local list = gameListeners[event]
	if not list then
		if not pcall(eventFrame.RegisterEvent, eventFrame, event) then
			unknownEvents[event] = true
			return false
		end
		list = {}
		gameListeners[event] = list
	end
	list[#list + 1] = fn
	return true
end
function ns.UnknownEvents() return unknownEvents end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = gameListeners[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then ns.Error(event, err) end
	end
end)

-- Errors in a listener are caught so one module cannot stop the others; they
-- are printed once each so the player can report them.
local seenErrors = {}
function ns.Error(where, err)
	local key = tostring(where) .. tostring(err)
	if seenErrors[key] then return end
	seenErrors[key] = true
	ns.Print("|cffe66b78error|r in " .. tostring(where) .. ": " .. tostring(err))
end

---------------------------------------------------------------------------
-- Message bus (Pathwise's own messages, not game events)
---------------------------------------------------------------------------

local messageListeners = {}

function ns.On(message, fn)
	local list = messageListeners[message]
	if not list then
		list = {}
		messageListeners[message] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(message, ...)
	local list = messageListeners[message]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], ...)
		if not ok then ns.Error(message, err) end
	end
end

---------------------------------------------------------------------------
-- Settings: defaults per section, saved values on top
---------------------------------------------------------------------------

local SCHEMA = 1
local defaults = {}

-- ns.Defaults("ui", { mode = "full", ... }): every module declares its own.
function ns.Defaults(section, tbl)
	defaults[section] = defaults[section] or {}
	for k, v in pairs(tbl) do defaults[section][k] = v end
end

local function store()
	if type(PathwiseSettings) ~= "table" then PathwiseSettings = {} end
	local s = PathwiseSettings
	if s.schema ~= SCHEMA then
		-- Unknown or older layout: start clean, keep nothing we cannot read.
		for k in pairs(s) do s[k] = nil end
		s.schema = SCHEMA
	end
	return s
end

local function split(path)
	local section, key = path:match("^([^%.]+)%.(.+)$")
	return section, key
end

function ns.Get(path)
	local section, key = split(path)
	if not section then return nil end
	local saved = store()[section]
	if type(saved) == "table" and saved[key] ~= nil then return saved[key] end
	local d = defaults[section]
	return d and d[key]
end

function ns.Set(path, value)
	local section, key = split(path)
	if not section then return end
	local s = store()
	if type(s[section]) ~= "table" then s[section] = {} end
	local d = defaults[section]
	-- A value equal to the default is not stored, so new defaults reach players.
	if d and d[key] == value then value = nil end
	if s[section][key] == value then return end
	s[section][key] = value
	ns.Fire("SETTING_CHANGED", path, ns.Get(path))
end

-- Per-character state (window positions belong to the account; progress to
-- the character).
function ns.CharState()
	if type(PathwiseCharSettings) ~= "table" then PathwiseCharSettings = {} end
	local c = PathwiseCharSettings
	if c.schema ~= SCHEMA then
		for k in pairs(c) do c[k] = nil end
		c.schema = SCHEMA
	end
	return c
end

---------------------------------------------------------------------------
-- Slash commands: /pw and /pathwise
---------------------------------------------------------------------------

local commands, commandOrder = {}, {}

-- ns.Command("way", fn, "help text"): /pw way <args> calls fn(args).
function ns.Command(name, fn, help)
	if not commands[name] then commandOrder[#commandOrder + 1] = name end
	commands[name] = { fn = fn, help = help }
end

function ns.RunCommand(text)
	text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local name, rest = text:match("^(%S+)%s*(.*)$")
	name = name and name:lower()
	local c = name and commands[name]
	if c then
		local ok, err = pcall(c.fn, rest or "")
		if not ok then ns.Error("/pw " .. name, err) end
		return true
	end
	if not name then
		ns.Fire("TOGGLE_GUIDE")
		return true
	end
	ns.Print(("Unknown command '%s'. Type /pw help."):format(name))
	return false
end

function ns.CommandHelp()
	local out = {}
	for _, name in ipairs(commandOrder) do
		out[#out + 1] = { name = name, help = commands[name].help }
	end
	return out
end

SLASH_PATHWISE1 = "/pw"
SLASH_PATHWISE2 = "/pathwise"
if SlashCmdList then SlashCmdList.PATHWISE = ns.RunCommand end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

ns.RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	store()
	ns.CharState()
	ns.Fire("LOADED")
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	ns.Fire("READY")
end)

-- For tests: the defaults table, read-only use.
ns._defaults = defaults
