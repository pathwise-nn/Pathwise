-- Pathwise UI tests: lua5.1 tests/ui/run.lua (from the repository root).
-- Each test gets a fresh client stub and a fresh copy of the addon.

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

-- A fresh client and Pathwise UI, logged in. `setup(stub)` runs before loading.
local function fresh(setup)
	PathwiseUISettings, PathwiseUICharSettings, PathwiseUI, Pathwise = nil, nil, nil, nil
	local stub = dofile(ROOT .. "/tests/ui/stub.lua")
	if setup then setup(stub) end
	local ns = stub.loadAddon(ROOT, "PathwiseUI")
	stub.login("PathwiseUI")
	return stub, ns
end

local function lastPrint(stub) return stub.printed[#stub.printed] or "" end

assert(loadfile(ROOT .. "/tests/ui/ui.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })
assert(loadfile(ROOT .. "/tests/ui/units.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })
assert(loadfile(ROOT .. "/tests/ui/bars.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })
assert(loadfile(ROOT .. "/tests/ui/bottom.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })
assert(loadfile(ROOT .. "/tests/ui/plates.lua"))({ test = test, eq = eq, near = near, ok = ok, fresh = fresh, lastPrint = lastPrint })

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
