-- Pathwise Heal tests: lua5.1 tests/heal/run.lua (from the repository root).
-- Each test gets a fresh client stub (Pathwise UI's, tests/ui/stub.lua) and
-- a fresh copy of the addon; `both` loads Pathwise UI beside it.

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
		if type(k) == "string" and (k:find("^PathwiseHeal") or k:find("^PathwiseUI")) then drop[#drop + 1] = k end
	end
	for _, k in ipairs(drop) do _G[k] = nil end
end

-- A fresh client and Pathwise Heal, logged in. `setup(stub)` runs before loading.
local function fresh(setup)
	clean()
	local stub = dofile(ROOT .. "/tests/ui/stub.lua")
	if setup then setup(stub) end
	local ns = stub.loadAddon(ROOT, "Pathwise_Heal")
	stub.login("Pathwise_Heal")
	return stub, ns
end

-- Pathwise UI and Pathwise Heal together, as a player with both installed.
local function both(setup)
	clean()
	local stub = dofile(ROOT .. "/tests/ui/stub.lua")
	if setup then setup(stub) end
	local ui = stub.loadAddon(ROOT, "PathwiseUI")
	local heal = stub.loadAddon(ROOT, "Pathwise_Heal")
	stub.fire("ADDON_LOADED", "PathwiseUI")
	stub.fire("ADDON_LOADED", "Pathwise_Heal")
	stub.fire("PLAYER_LOGIN")
	return stub, ui, heal
end

local function lastPrint(stub) return stub.printed[#stub.printed] or "" end

local h = { test = test, eq = eq, near = near, ok = ok, fresh = fresh, both = both, clean = clean, lastPrint = lastPrint }
assert(loadfile(ROOT .. "/tests/heal/heal.lua"))(h)
assert(loadfile(ROOT .. "/tests/heal/split.lua"))(h)
assert(loadfile(ROOT .. "/tests/heal/auras.lua"))(h)

for _, t in ipairs(tests) do
	local okRun, err = pcall(t.fn)
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
