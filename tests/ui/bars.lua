-- Tests for Pathwise UI's action bars: the game's secure buttons on our
-- bars, paging for stances and forms, your keys on them, layout, moving,
-- fading, hiding the game's bars, and their options page.
local h = ...
local test, eq, near, ok, fresh, lastPrint = h.test, h.eq, h.near, h.ok, h.fresh, h.lastPrint

local function contains(list, text)
	for _, t in ipairs(list) do if tostring(t):find(text, 1, true) then return true end end
	return false
end

test("bars: three bars of the game's own buttons by default, on the right pages", function()
	local stub, ns = fresh()
	local B = ns.Bars
	ok(B.bars[1] and B.bars[2] and B.bars[3], "main bar, bar 2, bar 3")
	ok(not B.bars[4] and not B.bars[5], "the right bars are off until you want them")
	local main = B.bars[1]
	eq(#main.buttons, 12)
	eq(main.buttons[5]:GetID(), 5, "button 5 acts on slot 5 of the bar's page")
	eq(B.bars[2]:GetAttribute("actionpage"), 6, "bar 2: the game's bottom-left bar's slots")
	eq(B.bars[3]:GetAttribute("actionpage"), 5, "bar 3: the bottom-right bar's slots")
	eq(main.buttons[1]:GetAttribute("showgrid"), 1, "empty slots shown")
end)

test("bars: active, pressed and flashing drawn inside the slot; the game's cast flourishes faded", function()
	local stub, ns = fresh()
	local b = CreateFrame("CheckButton")
	local checked, pushed = b:CreateTexture(), b:CreateTexture()
	-- Forever's template: 46 x 45, pinned top left.
	checked:SetPoint("TOPLEFT") pushed:SetPoint("TOPLEFT")
	function b:GetCheckedTexture() return checked end
	function b:GetPushedTexture() return pushed end
	b.Flash = b:CreateTexture()
	b.SpellCastAnimFrame = CreateFrame("Frame", nil, b)
	b.InterruptDisplay = CreateFrame("Frame", nil, b)
	ns.Bars.Style(b)
	for name, t in pairs({ checked = checked, pushed = pushed, flash = b.Flash }) do
		eq(#t.points, 2, name .. ": two corners")
		eq(t.points[1][1], "TOPLEFT", name)
		eq(t.points[1][2], 1, name .. ": inside the border")
		eq(t.points[2][1], "BOTTOMRIGHT", name)
		eq(t.points[2][2], -1, name)
	end
	eq(b.SpellCastAnimFrame.alpha, 0, "cast fill faded")
	eq(b.InterruptDisplay.alpha, 0, "interrupt faded")
end)

test("bars: the main bar follows stances, forms and stealth, in combat too", function()
	local stub, ns = fresh()
	local main = ns.Bars.bars[1]
	local d = stub.drivers[main]
	ok(d, "state drivers on the main bar")
	ok(d.page:find("%[bonusbar:1%] b1") and d.page:find("%[overridebar%]") and d.page:find("; 1$"), d.page)
	ok(d.form:find("%[form:1%] 1") and d.form:find("%[stealth%]") and d.form:find("; 0$"), d.form)
	for _, id in ipairs({ "page", "form" }) do
		local code = main:GetAttribute("_onstate-" .. id)
		ok(code and code:find("GetBonusBarIndex") and code:find('SetAttribute%("actionpage"'), "the page asked of the game on a " .. id .. " change")
	end
	ok(not stub.drivers[ns.Bars.bars[2]], "other bars keep their page")
end)

test("bars: a stance or form change redraws the main bar's buttons at once", function()
	local stub, ns = fresh()
	local main = ns.Bars.bars[1]
	-- Run the secure snippets as the game would: the bar's page state, then
	-- each button's child update.
	local function run(code, env) local fn = assert(loadstring(code)) setfenv(fn, env) fn() end
	local control = { ChildUpdate = function(_, id, message)
		for _, b in ipairs(main.buttons) do
			local code = b:GetAttribute("_childupdate-" .. id)
			if code then run(code, { self = b, message = message }) end
		end
	end }
	-- The game, as the secure code sees it: page 1, then battle stance (bonus
	-- bar 7), bear form (9), then shift+wheel to page 3 with no form.
	local game = { page = 1 }
	local env = { self = main, control = control, tonumber = tonumber,
		GetActionBarPage = function() return game.page end,
		HasBonusActionBar = function() return game.bonus ~= nil end,
		GetBonusBarIndex = function() return game.bonus end,
		HasVehicleActionBar = function() return false end,
		HasOverrideActionBar = function() return false end,
		HasTempShapeshiftActionBar = function() return false end }
	game.bonus = 7
	run(main:GetAttribute("_onstate-form"), env)
	eq(main:GetAttribute("actionpage"), 7, "battle stance's page on the bar")
	for i, b in ipairs(main.buttons) do eq(b:GetAttribute("actionpage"), 7, "and on button " .. i .. ", which redraws it") end
	game.bonus = 9
	run(main:GetAttribute("_onstate-page"), env)
	eq(main.buttons[1]:GetAttribute("actionpage"), 9, "bear form")
	game.bonus, game.page = nil, 3
	run(main:GetAttribute("_onstate-page"), env)
	eq(main.buttons[12]:GetAttribute("actionpage"), 3, "no form: the page you picked")
	ok(ns.Bars.bars[2].buttons[1]:GetAttribute("_childupdate-actionpage") == nil, "a fixed bar's buttons keep their page")
end)

test("bars: your keys for the game's bars work on these", function()
	local stub, ns = fresh(function(s)
		s.bindings.ACTIONBUTTON1 = { "1" }
		s.bindings.ACTIONBUTTON2 = { "2", "SHIFT-2" }
		s.bindings.MULTIACTIONBAR1BUTTON1 = { "Q" }
	end)
	eq(stub.overrides["1"], "PathwiseUI_Bar1Button1:LeftButton")
	eq(stub.overrides["SHIFT-2"], "PathwiseUI_Bar1Button2:LeftButton")
	eq(stub.overrides["Q"], "PathwiseUI_Bar2Button1:LeftButton")
	stub.bindings.ACTIONBUTTON1 = { "F" }
	stub.fire("UPDATE_BINDINGS")
	eq(stub.overrides["F"], "PathwiseUI_Bar1Button1:LeftButton", "a changed key follows")
	ns.Set("bars.enabled", false)
	eq(next(stub.overrides), nil, "off: the keys go back to the game's bars")
end)

test("bars: rows, size, spacing; moving; nothing protected in combat", function()
	local stub, ns = fresh()
	local B = ns.Bars
	local main = B.bars[1]
	eq(main.w, 12 * 40 - 4, "one row of 12 at 36 + 4")
	ns.Set("bars.Bar1Per", 6)
	eq(main.h, 2 * 40 - 4, "two rows")
	ns.Set("bars.size", 30)
	eq(main.buttons[1].w, 30)
	ok(B.Unlock(true))
	ns.Set("bars.Bar1Point", { "BOTTOM", "BOTTOM", 120, 60 })
	B.Place(main)
	eq(main.points[#main.points][4], 120)
	B.Unlock(false)
	B.ResetPositions()
	eq(main.points[#main.points][4], 0, "back where it was")
	stub.combat = true
	ns.Set("bars.size", 40)
	eq(main.buttons[1].w, 30, "in combat: waits")
	stub.combat = false
	stub.fire("PLAYER_REGEN_ENABLED")
	eq(main.buttons[1].w, 40, "after combat: done")
end)

test("bars: soft out of combat, the game's bars put away", function()
	local stub, ns = fresh(function()
		MainActionBar = CreateFrame("Frame", "MainActionBar")
		MultiBarBottomLeft = CreateFrame("Frame", "MultiBarBottomLeft")
	end)
	local B = ns.Bars
	ok(B.Hidden()[MainActionBar] and B.Hidden()[MultiBarBottomLeft], "the game's bars put away")
	ns.Set("bars.fade", true)
	near(B.bars[1].alpha or 1, 1, 1e-6, "eases, does not snap")
	stub.advance(0.5)
	near(B.bars[1].alpha, 0.3, 1e-6, "soft out of combat")
	B.bars[1].mouseOver = true
	stub.advance(0.4)
	near(B.bars[1].alpha, 1, 1e-6, "full under the mouse")
end)

test("bars: their page in the options", function()
	local stub, ns = fresh()
	ns.Config.Show("bars")
	local texts = stub.texts()
	ok(contains(texts, "Pathwise action bars") and contains(texts, "Buttons per row"), table.concat(texts, " | "))
	ok(stub.clickLabel("Move the bars"))
	ok(ns.Bars.Unlocked())
	ok(stub.clickLabel("Lock the bars"))
	ok(not ns.Bars.Unlocked())
end)
