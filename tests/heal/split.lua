-- Pathwise Heal on its own, and beside Pathwise UI: no clashes, its shared
-- files the same as Pathwise UI's, one accent, and Pathwise UI's party frames
-- stepping aside while the healing frames show the party.
local h = ...
local test, eq, ok, fresh, both, clean = h.test, h.eq, h.ok, h.fresh, h.both, h.clean

local function priestInParty(s)
	s.player.class = "PRIEST"
	s.units.player.class = "PRIEST"
	s.units.party1 = { name = "Florp", level = 20, class = "ROGUE", player = true, health = 700, max = 900 }
end

local function read(path)
	local f = assert(io.open(path, "rb"), path)
	local t = f:read("*a")
	f:close()
	return t
end

test("split: Pathwise Heal works on its own, with its own options and minimap button", function()
	local stub, ns = fresh(priestInParty)
	ok(_G.PathwiseUI == nil, "no Pathwise UI loaded")
	eq(_G.PathwiseHeal, ns)
	eq(ns.NAME, "Pathwise Heal")
	ok(_G.PathwiseHeal_Prompt and _G.PathwiseHeal_Prompt.shown, "a priest is asked")
	SlashCmdList.PATHWISEHEAL("")
	ok(_G.PathwiseHealConfig and _G.PathwiseHealConfig.shown, "/pwheal opens its own options")
	eq(ns.Config.Current() or ns.Config.CATEGORIES[1].key, "heal", "the Healing page first")
	ok(_G.PathwiseHealMinimapButton, "its own minimap button")
	ok(type(PathwiseHealSettings) == "table" and type(PathwiseHealCharSettings) == "table", "its own saved settings")
	ok(PathwiseUISettings == nil, "nothing written for Pathwise UI")
end)

test("split: Pathwise Heal's shared files are Pathwise UI's, copied unchanged (npm run kit)", function()
	local kit = { "Core.lua", "Theme.lua", "Anim.lua", "Widgets.lua", "Movers.lua", "Options.lua", "Minimap.lua" }
	for _, name in ipairs(kit) do
		local copy = read("Pathwise_Heal/Kit/" .. name)
		local body = copy:gsub("^%-%- COPIED from [^\n]*\n%-%- Edit [^\n]*\n", "", 1)
		ok(body ~= copy, name .. ": has the COPIED header")
		ok(body == read("PathwiseUI/" .. name), name .. " differs from PathwiseUI/" .. name .. ": run npm run kit")
	end
	local toc = read("Pathwise_Heal/Pathwise_Heal.toc")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^##") and line ~= "" then
			ok(io.open("Pathwise_Heal/" .. line:gsub("\\", "/")), "Pathwise_Heal.toc lists a missing file: " .. line)
		end
	end
	for _, m in ipairs({ "icon.tga", "disc.tga", "thumb.tga", "glyph-expand.tga", "Fonts/Inter-Regular.ttf", "Fonts/CormorantGaramond-Bold.ttf" }) do
		ok(read("Pathwise_Heal/Media/" .. m) == read("PathwiseUI/Media/" .. m), "Media/" .. m .. " copied")
	end
end)

test("split: Pathwise UI no longer carries healing frames, and points to Pathwise Heal", function()
	clean()
	local stub = dofile("./tests/ui/stub.lua")
	priestInParty(stub)
	local ui = stub.loadAddon(".", "PathwiseUI")
	stub.login("PathwiseUI")
	ok(ui.Heal == nil and ui.HealClicks == nil, "no healing code in Pathwise UI")
	ok(not _G.PathwiseHeal_Prompt, "a priest is not asked by Pathwise UI")
	ok(ui.Units.frames.party1 and ui.Units.frames.party1.shown, "its party frames show")
	ui.Config.Show("heal")
	ok(table.concat(stub.texts(), "|"):find("a separate addon: Pathwise Heal", 1, true), "says where healing frames went")
end)

test("split: both installed: two addons, no clashes", function()
	local stub, ui, heal = both(priestInParty)
	ok(_G.PathwiseUI == ui and _G.PathwiseHeal == heal and ui ~= heal, "each its own table")
	ok(type(PathwiseUISettings) == "table" and type(PathwiseHealSettings) == "table" and PathwiseUISettings ~= PathwiseHealSettings, "each its own settings")
	SlashCmdList.PATHWISEUI("")
	SlashCmdList.PATHWISEHEAL("")
	ok(_G.PathwiseUIConfig.shown and _G.PathwiseHealConfig.shown, "/pwui and /pwheal each open their own window")
	ok(_G.PathwiseUIMinimapButton and _G.PathwiseHealMinimapButton and _G.PathwiseUIMinimapButton ~= _G.PathwiseHealMinimapButton, "two minimap buttons")
	ui.Config.Show("heal")
	ok(table.concat(stub.texts(), "|"):find("Open Pathwise Heal's options", 1, true), "Pathwise UI's Healing page opens Pathwise Heal's")
end)

test("split: both installed: one accent, set from either", function()
	local stub, ui, heal = both()
	eq(heal.Get("look.accentMode"), ui.Get("look.accentMode"), "same at login")
	ui.Set("look.accentMode", "custom")
	ui.Set("look.accentColor", "#FF8800")
	eq(heal.Get("look.accentMode"), "custom")
	eq(heal.Get("look.accentColor"), "#FF8800", "Pathwise Heal follows Pathwise UI")
	heal.Set("look.accentColor", "#22CC88")
	eq(ui.Get("look.accentColor"), "#22CC88", "and the other way")
	heal.Set("look.sharePathwise", false)
	ui.Set("look.accentColor", "#123456")
	eq(heal.Get("look.accentColor"), "#22CC88", "not when sharing is off")
end)

test("split: each minimap button's mark is its own logo's colour, not the shared accent", function()
	local stub, ui, heal = both()
	local function mark(b) return ui.Theme.ToHex(b.icon.vertex) end
	eq(mark(_G.PathwiseUIMinimapButton), ui.ID.color, "Pathwise UI: its logo's blue")
	eq(mark(_G.PathwiseHealMinimapButton), heal.ID.color, "Pathwise Heal: its logo's pink")
	ok(ui.ID.color ~= heal.ID.color, "told apart")
	ui.Set("look.accentMode", "custom")
	ui.Set("look.accentColor", "#FF8800")
	ui.Fire("ACCENT_CHANGED")
	heal.Fire("ACCENT_CHANGED")
	eq(mark(_G.PathwiseUIMinimapButton), ui.ID.color, "a new accent leaves the mark alone")
	eq(mark(_G.PathwiseHealMinimapButton), heal.ID.color)
end)

test("split: both installed: Pathwise UI's party frames stay with the healing frames, unless you hide them", function()
	local stub, ui, heal = both(priestInParty)
	local party = ui.Units.frames.party1
	ok(party and party.shown and stub.watched[party], "party frames before healing frames")
	heal.Set("heal.enabled", true)
	ok(stub.watched[party], "both show by default")
	heal.Set("heal.hideParty", true)
	ok(not ui.Units.frames.party1.shown, "stepped aside when you ask")
	ok(not stub.watched[party], "and not watched: the game won't show it")
	-- Back: watched again (the game shows a watched frame while its unit exists).
	heal.Set("heal.hideParty", false)
	ok(stub.watched[party], "back when you want both")
	heal.Set("heal.hideParty", true)
	ok(not stub.watched[party], "aside again")
	heal.Set("heal.enabled", false)
	ok(stub.watched[party], "back when healing frames are off")
	heal.Config.Show("heal")
	heal.Set("heal.enabled", true)
	ok(table.concat(stub.texts(), "|"):find("Hide Pathwise UI's party frames", 1, true), "the option shows when Pathwise UI is installed")
end)

test("split: both installed: the healing frames start beside Pathwise UI's party frames, not on them", function()
	local stub, ui, heal = both(priestInParty)
	heal.Set("heal.enabled", true)
	local p = _G.PathwiseHeal_Frames.points[1]
	eq(p[4], heal.Heal.BESIDE_UI_POINT[3], "to the right of the party column")
	ok(p[4] >= 30 + 190 + 4 * 18, "clear of the party frames and their debuffs")
	heal.Set("heal.hideParty", true)
	eq(_G.PathwiseHeal_Frames.points[1][4], 30, "only these: back at the left edge")
	heal.Set("heal.point", { "TOPLEFT", "TOPLEFT", 500, -300 })
	heal.Set("heal.hideParty", false)
	eq(_G.PathwiseHeal_Frames.points[1][4], 500, "a place you chose wins")
end)

test("split: both installed: the healing frames start beside Pathwise UI's party frames, not on them", function()
	local stub, ui, heal = both(priestInParty)
	heal.Set("heal.enabled", true)
	local p = _G.PathwiseHeal_Frames.points[1]
	eq(p[4], heal.Heal.BESIDE_UI_POINT[3], "to the right of the party column")
	ok(p[4] >= 30 + 190 + 4 * 18, "clear of the party frames and their debuffs")
	heal.Set("heal.hideParty", true)
	eq(_G.PathwiseHeal_Frames.points[1][4], 30, "only these: back at the left edge")
	heal.Set("heal.point", { "TOPLEFT", "TOPLEFT", 500, -300 })
	heal.Set("heal.hideParty", false)
	eq(_G.PathwiseHeal_Frames.points[1][4], 500, "a place you chose wins")
end)

test("split: right click on Pathwise Heal's minimap button: its pages and Move everything", function()
	local stub, ns = fresh(priestInParty)
	ns.Set("heal.enabled", true)
	local button = _G.PathwiseHealMinimapButton
	button.scripts.OnClick(button, "RightButton")
	local menu = _G.PathwiseHealMinimapMenu
	ok(menu and menu.shown, "the menu opens")
	ok(not (_G.PathwiseHealConfig and _G.PathwiseHealConfig.shown), "not the options window")
	local texts = table.concat(stub.texts(), "|")
	for _, page in ipairs({ "Options", "Healing", "Look and accent", "Profile", "Move everything" }) do
		ok(texts:find(page, 1, true), page .. " in the menu")
	end
	ok(stub.clickLabelText("Move everything"))
	ok(not menu.shown, "the menu closes")
	ok(ns.Heal.Unlocked(), "the healing frames can be moved")
	button.scripts.OnClick(button, "RightButton")
	ok(stub.clickLabelText("Lock everything"), "then Lock everything")
	ok(not ns.Heal.Unlocked(), "locked again")
	button.scripts.OnClick(button, "RightButton")
	ok(stub.clickLabelText("Colors"))
	eq(ns.Config.Current(), "colors", "a page opens straight to it")
	ok(_G.PathwiseHealConfig.shown)
end)

test("split: both installed: HoTs and debuffs still show on the healing frames", function()
	local HOTS = "HELPFUL|PLAYER|RAID_IN_COMBAT"
	local stub, ui, heal = both(function(s)
		priestInParty(s)
		s.auras.party1 = {
			[HOTS] = { { auraInstanceID = 1, icon = 135953, duration = 15, expirationTime = 12 } },
			["HARMFUL|RAID"] = {}, -- none you can remove
			["HARMFUL"] = { { auraInstanceID = 5, icon = 136207, duration = 10, expirationTime = 8 } },
		}
	end)
	heal.Set("heal.enabled", true)
	ok(ui.Units.frames.party1.shown, "Pathwise UI's party frame shows too")
	local b = CreateFrame("Button")
	heal.Heal.NewButton(b)
	heal.Heal.SetUnit(b, "party1")
	ok(b.buffs[1].shown and b.buffs[1].texture == 135953, "the HoT")
	ok(b.otherDebuffs[1].shown and b.otherDebuffs[1].texture == 136207, "the debuff")
	stub.fire("UNIT_AURA", "party1")
	ok(b.buffs[1].shown, "still there after UNIT_AURA")
	ui.Set("accent", "blue")
	stub.fire("UNIT_AURA", "party1")
	ok(b.buffs[1].shown, "and after Pathwise UI changes the accent")
end)
