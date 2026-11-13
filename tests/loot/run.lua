-- Pathwise Loot tests: lua5.1 tests/loot/run.lua (from the repository root).
-- Each test gets a fresh client stub (Pathwise UI's, tests/ui/stub.lua) and
-- a fresh copy of the addon, logged in; `both` loads Pathwise UI beside it.

local ROOT = "."
local results = { pass = 0, fail = 0 }
local tests = {}

local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function eq(a, b, msg)
	if a ~= b then error(("%s: expected %s, got %s"):format(msg or "value", tostring(b), tostring(a)), 2) end
end
local function near(a, b, eps, msg)
	if type(a) ~= "number" or math.abs(a - b) > (eps or 1e-6) then
		error(("%s: expected ~%s, got %s"):format(msg or "value", tostring(b), tostring(a)), 2)
	end
end
local function ok(v, msg) if not v then error(msg or "expected true", 2) end end

-- A clean slate: no saved settings, addon tables or named frames from an
-- earlier test (as after a fresh install).
local function clean()
	local drop = {}
	for k in pairs(_G) do
		if type(k) == "string" and (k:find("^PathwiseLoot") or k:find("^PathwiseUI")) then drop[#drop + 1] = k end
	end
	for _, k in ipairs(drop) do _G[k] = nil end
end

-- A fresh client and Pathwise Loot, logged in. `setup(stub)` runs before loading.
local function fresh(setup)
	clean()
	local stub = dofile(ROOT .. "/tests/ui/stub.lua")
	if setup then setup(stub) end
	local ns = stub.loadAddon(ROOT, "Pathwise_Loot")
	stub.login("Pathwise_Loot")
	return stub, ns
end

-- Pathwise UI and Pathwise Loot together, as a player with both installed.
local function both(setup)
	clean()
	local stub = dofile(ROOT .. "/tests/ui/stub.lua")
	if setup then setup(stub) end
	local ui = stub.loadAddon(ROOT, "PathwiseUI")
	local enc = stub.loadAddon(ROOT, "Pathwise_Loot")
	stub.fire("ADDON_LOADED", "PathwiseUI")
	stub.fire("ADDON_LOADED", "Pathwise_Loot")
	stub.fire("PLAYER_LOGIN")
	return stub, ui, enc
end

local function lastPrint(stub) return stub.printed[#stub.printed] or "" end

local h = { test = test, eq = eq, near = near, ok = ok, fresh = fresh, both = both, clean = clean, lastPrint = lastPrint }
assert(loadfile(ROOT .. "/tests/loot/loot.lua"))(h)
assert(loadfile(ROOT .. "/tests/loot/split.lua"))(h)

for _, t in ipairs(tests) do
	local okRun, err = pcall(t.fn)
	if okRun and BLOCKED_EVENTS then
		okRun, err = false, "registers an event Forever blocks for addons: " .. table.concat(BLOCKED_EVENTS, ", ")
	end
	BLOCKED_EVENTS = nil
	-- Anything the addon reported as an error fails the test too.
	if okRun and _G.stub then
		for _, line in ipairs(_G.stub.printed) do
			if tostring(line):find("error|r in", 1, true) then okRun, err = false, "reported: " .. tostring(line) break end
		end
	end
	if okRun then
		results.pass = results.pass + 1
		print("ok    " .. t.name)
	else
		results.fail = results.fail + 1
		print("FAIL  " .. t.name)
		print("      " .. tostring(err))
	end
end
print(("\n%d passed, %d failed"):format(results.pass, results.fail))
if results.fail > 0 then os.exit(1) end
