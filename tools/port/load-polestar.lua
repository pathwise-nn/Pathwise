-- Loads Polestar's compiled guides (Guides.lua) in a sandbox and returns
-- them: { [id] = guide }. Shared by the route converter and its checks.
-- Polestar is GPL-3.0 (https://github.com/fitzforge/polestar); the converted
-- routes credit it (THIRD_PARTY.md).

local M = {}

local SAFE = {
	pairs = pairs, ipairs = ipairs, next = next, type = type, tostring = tostring, tonumber = tonumber,
	select = select, unpack = unpack, error = error, assert = assert, setmetatable = setmetatable,
	rawget = rawget, rawset = rawset,
	string = { format = string.format, sub = string.sub, gsub = string.gsub, find = string.find, match = string.match,
		gmatch = string.gmatch, lower = string.lower, upper = string.upper, len = string.len, rep = string.rep },
	table = { insert = table.insert, remove = table.remove, concat = table.concat, sort = table.sort },
	math = { floor = math.floor, max = math.max, min = math.min, abs = math.abs, huge = math.huge },
}

-- path: the compiled Guides.lua. Returns guides by id, and their order.
function M.load(path)
	local f = assert(io.open(path, "rb"))
	local text = f:read("*a")
	f:close()
	local guides, order = {}, {}
	local env = {}
	for k, v in pairs(SAFE) do env[k] = v end
	local api = setmetatable({}, { __index = function() return function() return true end end })
	api.RegisterGuide = function(def)
		if type(def) == "table" and def.id then
			guides[def.id] = def
			order[#order + 1] = def.id
		end
		return true
	end
	env.Pathwise = api
	env.Polestar = api
	env._G = env
	local chunk = assert(loadstring(text, "=Guides.lua"))
	setfenv(chunk, env)
	chunk("Pathwise_Guides", {})
	return guides, order
end

return M
