-- The main simulation: a new island end to end through the real client and its UI (the sign, the Tree of
-- Life with its first lot of eggs round its roots, the HUD with the tree's card, the tips), building what the tips ask
-- in their order (a lumber camp, a veggie patch, a hut, then an egg hatched by tapping it, then a snack stall: the
-- starting shells cover them; Build mode turns its tray to Work's Workplaces row, then Huts, then back), the
-- tree in Build mode (moved like any piece, never cleared away), the days turning (the stores grow, every building
-- working a little with nobody at it), the tree's eggs (the plot's Eggs attribute, the ring every client lays them on,
-- the price tags and their rules, the card's best three and the time to the next lot, hatching from the card, a tag and
-- the panel, the swap picker when every hut is full, the picker going back to the list when a new lot replaced its egg,
-- a new lot every Tree.secs, a tap on the tree opening its panel), the Driftlings panel (moving one to a second hut and
-- back in a swap, Work, selling in two taps), the Index panel, the founder's looks, settings, expanding for shells (the
-- extra eggs laid at once, the cheer naming the new island), the build catalog (the tray's tabs and icons, each tab's
-- chips, Decor's 13 themes, the cards cheapest first with the locked ones after, a card's tooltip, the search box, each
-- tab's count), fences drawn through the UI (a line, a box, one over another, Erase), a river two tiles wide (its
-- tiles' banks in their model names) with a bridge over it and lily pads on it (refused on the grass, taken up with
-- their tile), decor put down with its effects (BuildFx's drop, Puffs' particles, with the pixel filter on for them),
-- Copy, Replace within the row, the inventory (Put away, Free on a card, the Inventory tab, a piece down again from it
-- for nothing, Quick remove's taps and drags, Sell), the keys R and Esc, the questline (Go on an old tab's name opening
-- Work's row), then a
-- malicious client (the fences' and tiles' payloads among the rest), then a second player, then the first island grown
-- on to Everdrift (tier 20, Island max, land far north of where Driftling Haven ended, the pieces of tiers 7 to 20 built
-- up there). No villagers since 2026-11-12, no food since 2026-11-13, the Tree of Life's eggs in place of the tide
-- since 2026-11-13, the build catalog since 2026-11-13. Every check is an H.expect; the SIM REPORT must show 0 findings
-- and 0 errors.
local E = require("./loader")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.verboseUi = false
E.dt = 0.05
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Buildings = H.sharedServer("Data.Buildings")
local Creatures = H.sharedServer("Data.Creatures")
local Traits = H.sharedServer("Data.Traits")
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Island = H.sharedServer("Logic.Island")
local Numbers = H.sharedServer("Logic.Numbers")
local TreeL = H.sharedServer("Logic.Tree")
local DecorModels = H.sharedServer("Models.DecorModels")

------------------------------------------------------------------ 1. a new island
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(1.5)
local fx = H.watchFx(p)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(prof.shells == Tuning.StartShells and prof.wood == nil and prof.food == nil, "join", "the starting store (shells, no wood, no food)", string.format("%s %s %s", tostring(prof.shells), tostring(prof.wood), tostring(prof.food)))
H.expect(prof.tier == 1 and prof.tut == 1 and prof.folk == nil and #prof.plot.placed == 1 and prof.plot.placed[1].id == "tree" and prof.tree == nil, "join", "a new island, tips at step 1, no villagers, nothing built but its Tree of Life", string.format("%d pieces", #prof.plot.placed))
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local land1 = static and static:FindFirstChild("Land")
H.expect(land1 ~= nil and land1:FindFirstChild("Land") ~= nil and static:FindFirstChild("Office") == nil, "join", "the island is built under Plots.Plot_1.Static.Land (no house)")
H.expect(land1 ~= nil and land1:FindFirstChild("FireStone", true) == nil and land1:FindFirstChild("Plaza", true) == nil and land1:FindFirstChild("PlotSign", true) ~= nil, "join", "its sign, no campfire or plaza (the Tree of Life in the middle since 2026-11-20)")
do
	-- the Tree of Life in the island's middle (the request of 2026-11-20: "Remove the campfire in the middle and put the
	-- tree in the middle instead"), no rock wall and no trail on the land (the rock is the floating island's underside)
	local tq = prof.plot.placed[1]
	H.expect(tq ~= nil and tq.id == "tree" and tq.x + 4 == Street.CENTER.x and tq.z + 4 == Street.CENTER.z, "join", "the Tree of Life stands in the island's middle", tq and string.format("%d,%d", tq.x, tq.z))
	local rocky = 0
	for _, d in (land1 and land1:GetDescendants() or {}) do
		if d.Name == "RockWall" or d.Name == "Trail" then
			rocky += 1
		end
	end
	H.expect(rocky == 0, "join", "no rock wall or trail on the land", tostring(rocky))
end
H.expect(land1 ~= nil and land1:FindFirstChild("JettyPlank", true) == nil and land1:FindFirstChild("Mailbox", true) == nil and land1:FindFirstChild("Bound", true) ~= nil, "join", "no jetty, no mailbox; an invisible wall round the grass (a floating island since 2026-11-20)")
H.expect(land1 ~= nil and land1:FindFirstChild("Lip", true) ~= nil and land1:FindFirstChild("Rock", true) ~= nil and land1:FindFirstChild("Water", true) == nil, "join", "a floating island: the earth lip and the rock under its edge, no sea")
H.expect(plot1 and plot1:GetAttribute("StudioName") == "Pixel's Isle", "join", "the island's name", tostring(plot1 and plot1:GetAttribute("StudioName")))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there")
for _, n in { "Menu_build", "Menu_pals", "Menu_index", "Menu_looks", "Menu_store", "Menu_settings" } do
	H.expect(H.buttonNamed(p, n) ~= nil, "join", "the menu bar's " .. n)
end
H.expect(H.buttonNamed(p, "Menu_folk") == nil, "join", "no Villagers button (the driftlings do all the work)")
H.expect(#H.buttons(p, "^Shells pay", true) == 0, "join", "(tips are text, not buttons)")
-- the loading card (src/first/LoadingCard: ReplicatedFirst's Boot put it up before the rest arrived): it went up, its
-- title centred on the canvas, and it is gone once the first picture is on screen
do
	local ctx = E.clientCtx(p)
	local inst = E.find("ReplicatedFirst.Loading.LoadingCard")
	local entry = ctx and inst and ctx.modules[inst]
	local st = entry and H.inClient(p, entry.value.state)
	H.expect(st ~= nil and st.finished and not st.up, "join", "the loading card went up and is gone now the island shows", st and string.format("finished %s up %s", tostring(st.finished), tostring(st.up)))
	local mid = st and st.title and (st.title.x0 + st.title.x1) / 2
	H.expect(mid ~= nil and math.abs(mid - st.size.X / 2) <= 1, "join", "its title centred on the screen", if st and st.title then string.format("%s of %d", tostring(mid), st.size.X) else "no title")
	-- (the request of 2026-11-20: "make the island loading screen like this view, but render it as a still image, then
	-- polish it like a pixel art illustration": the island's picture in the middle, under the bar, on the screen)
	local still = st and st.still
	local fits = still ~= nil and math.abs(still.x0 + still.w / 2 - st.size.X / 2) <= 1 and still.x0 >= 0 and still.x0 + still.w <= st.size.X and still.y0 > (st.title and st.title.y1 or 0)
	H.expect(st ~= nil and (st.fallback or fits), "join", "it showed the island's picture in the middle, under the title", if st and still then string.format("%s %dx%d at %d,%d on %dx%d", still.name, still.w, still.h, still.x0, still.y0, st.size.X, st.size.Y) else (if st then "fallback " .. tostring(st.fallback) else "?"))
	local pg = p:FindFirstChildOfClass("PlayerGui")
	H.expect(pg ~= nil and pg:FindFirstChild("LoadingCard") == nil, "join", "and nothing of it left on the screen")
end
-- the background music: the island's tunes by the clock; the Settings panel (the menu bar's Settings, in place of the
-- note in the corner since 2026-11-14) switches it and the sounds off and on, and sets the pixel art's detail (kept)
local AudioM = H.cmod(p, "Controllers.Audio")
local ms = H.inClient(p, AudioM.musicState)
H.expect((ms.mood == "day" or ms.mood == "night") and ms.on and ms.tracks >= 1, "join", "the island's music plays", string.format("%s %s %d", tostring(ms.mood), tostring(ms.on), ms.tracks))
H.expect(H.buttonNamed(p, "MusicToggle", true) == nil, "settings", "no music note in the corner any more")
do
	-- (a desktop's top bar is a resource bar across the screen, the PC builders' (2026-11-21: "research on popular
	-- desktop tycoons and replicate their UIs"); the island card docked under it at the right)
	local hudCard = p.PlayerGui:FindFirstChild("IslandCard", true)
	local hudTop = p.PlayerGui:FindFirstChild("TopBar", true)
	local below = hudCard and hudTop and hudCard.AbsolutePosition.Y - (hudTop.AbsolutePosition.Y + hudTop.AbsoluteSize.Y)
	local hudGui = p.PlayerGui:FindFirstChild("Hud")
	local hudCanvas = hudGui and hudGui:FindFirstChild("Canvas")
	H.expect(hudCard ~= nil and hudTop ~= nil and hudCanvas ~= nil and hudTop.AbsoluteSize.X >= hudCanvas.AbsoluteSize.X * 0.9 and below ~= nil and below >= 0 and below <= 12, "settings", "the top bar runs across the screen, the island card docked under it", hudCard and hudTop and string.format("bar %d wide of %d, card %s px under it", hudTop.AbsoluteSize.X, if hudCanvas then hudCanvas.AbsoluteSize.X else -1, tostring(below)) or "missing")
	local rate = p.PlayerGui:FindFirstChild("Chip_rate", true)
	local isle = p.PlayerGui:FindFirstChild("Chip_isle", true)
	local rv = rate and rate:FindFirstChild("Value")
	H.expect(rv ~= nil and string.find(rv.Text, "/min", 1, true) ~= nil and isle ~= nil, "hud", "the resource bar has the coins a minute and the island's level", rv and rv.Text or "missing")
	-- (its Working line: the driftlings at work out of the places at work; the requests of 2026-11-16, "can you make
	-- another detail to show creatures working, with x/y", and 2026-11-17, "for working, make it x/y, where x is
	-- amount of creatures working and y being the amount of work spaces available")
	local working = 0
	for _, x in prof.pals do
		if x.work ~= 0 then
			working += 1
		end
	end
	local wl = hudCard and hudCard:FindFirstChild("Working", true)
	local wr = hudCard and hudCard:FindFirstChild("WorkingR", true)
	local places = Island.jobPlaces(prof.plot.placed)
	H.expect(wl ~= nil and wl.Text == "Working" and wr ~= nil and wr.Text == string.format("%d/%d", working, places), "hud", "the island card's Working line: at work out of the places at work (2026-11-17)", wr and wr.Text or "missing")
end
H.expect(H.clickNamed(p, "Menu_settings", { wait = 0.4 }) and H.currentPanel(p) == "settings", "settings", "the menu bar's Settings opens the Settings panel", tostring(H.currentPanel(p)))
for _, b in { "Set_music_on", "Set_music_off", "Set_sfx_on", "Set_sfx_off", "Set_pixel_high", "Set_pixel_medium", "Set_pixel_low" } do
	H.expect(H.buttonNamed(p, b) ~= nil, "settings", "the panel's " .. b)
end
H.expect(H.buttonNamed(p, "Set_pixel_off", true) == nil, "settings", "no way to turn the pixel filter off")
H.expect(H.clickNamed(p, "Set_music_off", { wait = 0.5 }) and prof.settings.music == "off" and not H.inClient(p, AudioM.musicState).on, "settings", "Music Off: the music stops, kept with the profile", tostring(prof.settings.music))
H.expect(H.clickNamed(p, "Set_music_on", { wait = 0.5 }) and prof.settings.music == "on" and H.inClient(p, AudioM.musicState).on, "settings", "and On again", tostring(prof.settings.music))
H.expect(H.clickNamed(p, "Set_sfx_off", { wait = 0.5 }) and prof.settings.sfx == "off" and not H.inClient(p, AudioM.soundsOn) and not H.inClient(p, AudioM.play, "click"), "settings", "Sounds Off: no sound plays, kept with the profile", tostring(prof.settings.sfx))
H.expect(H.clickNamed(p, "Set_sfx_on", { wait = 0.5 }) and prof.settings.sfx == "on" and H.inClient(p, AudioM.soundsOn), "settings", "and On again", tostring(prof.settings.sfx))
local PRm = H.cmod(p, "Pixel.PixelRenderer")
H.expect(H.clickNamed(p, "Set_pixel_low", { wait = 0.5 }) and prof.settings.pixel == "low", "settings", "Pixel art Low, kept with the profile", tostring(prof.settings.pixel))
H.expect(H.clickNamed(p, "Set_pixel_high", { wait = 0.5 }) and prof.settings.pixel == "high", "settings", "and High again", tostring(prof.settings.pixel))
H.expect(H.req(p, "settings.set", { k = "sfx", v = "loud" }).err == "bad_payload", "settings", "a sounds value that isn't on or off: bad_payload")
-- the Screen choice (the report of 2026-11-20, "the tree still looks like this", with screenshots whose every pixel was
-- 2.5 of the screen's: Pixel/DisplayScale fits the pixel size to a whole number of the screen's own pixels)
do
	local DS = H.cmod(p, "Pixel.DisplayScale")
	local PRs = H.cmod(p, "Pixel.PixelRenderer")
	for _, b in { "Set_screen_auto", "Set_screen_100", "Set_screen_125", "Set_screen_150", "Set_screen_175", "Set_screen_200" } do
		H.expect(H.buttonNamed(p, b) ~= nil, "settings", "the panel's " .. b)
	end
	local k0 = H.inClient(p, PRs.pixelScale)
	H.expect(prof.settings.screen == "auto" and H.inClient(p, DS.factor) == 1, "settings", "a new player's Screen: Auto, the sim's screen found at 100%", string.format("%s %g", tostring(prof.settings.screen), H.inClient(p, DS.factor)))
	H.expect(H.clickNamed(p, "Set_screen_125", { wait = 0.6 }) and prof.settings.screen == "125", "settings", "Screen 125%, kept with the profile", tostring(prof.settings.screen))
	local k1 = H.inClient(p, PRs.pixelScale)
	local px1 = k1 * 1.25
	H.expect(H.inClient(p, DS.factor) == 1.25 and math.abs(px1 - math.floor(px1 + 0.5)) < 1e-6 and k1 ~= k0, "settings", "at 125% the pixel size is a whole number of the screen's pixels", string.format("%g units -> %g units (%g pixels)", k0, k1, px1))
	-- (the next report, "it still looks uneven no matter what pixel scale i use": Roblox keeps an Offset whole, so the
	-- pixel size reaches the picture through a UIScale, never an offset; the harness keeps offsets whole too)
	-- (the pixel layer's own UIScale is checked with the sky, where the filter is on)
	local spg = p:FindFirstChildOfClass("PlayerGui")
	local fl = spg and spg:FindFirstChild("Found_screen", true)
	H.expect(fl ~= nil and (fl :: any).Text == "Found 100%", "settings", "beside Screen, what Auto found (the sim's screen: 100%)", if fl then (fl :: any).Text else "none")
	H.expect(H.clickNamed(p, "Set_screen_auto", { wait = 0.6 }) and prof.settings.screen == "auto" and math.abs(H.inClient(p, PRs.pixelScale) - k0) < 1e-6, "settings", "and Auto again: back as it was", string.format("%g", H.inClient(p, PRs.pixelScale)))
	-- (Auto finds a screen at 125% from what Roblox reports there: sizes 0.8 of a unit apart, among whole mouse
	-- positions that say nothing; the report of 2026-11-20, "its still uneven", Auto left at 100% by them)
	local found = H.inClient(p, function()
		for _, v in { 100, 205, 63, 640, 1092.8, 412, 614.4, 333 } do
			DS.observe(v)
		end
		return DS.factor()
	end)
	H.expect(found == 1.25, "settings", "Auto finds a screen at 125% from the sizes with a fraction, whole mouse positions among them", tostring(found))
	H.inClient(p, DS.debugReset)
	local whole = H.inClient(p, function()
		for _, v in { 100, 205, 63, 640, 1280, 720 } do
			DS.observe(v)
		end
		return DS.factor()
	end)
	H.expect(whole == 1, "settings", "and stays at 100% when every value is whole", tostring(whole))
	H.inClient(p, DS.debugReset)
	E.run(0.3)
	H.expect(math.abs(H.inClient(p, PRs.pixelScale) - k0) < 1e-6, "settings", "(and the sim's screen back at 100%)", string.format("%g", H.inClient(p, PRs.pixelScale)))
	H.expect(H.req(p, "settings.set", { k = "screen", v = "133" }).err == "bad_payload", "settings", "a Screen value that isn't one of the choices: bad_payload")
end
local _ = PRm
-- the View slider (the request of 2026-11-18: "make a view slider for zooming the camera in and out, with 10
-- notches"): ten notches under its track, the default's marked, - and + step a notch, the camera follows a moment after
-- the last one at that notch's art px a stud, and the notch is kept with the profile
do
	local CCs = H.cmod(p, "Controllers.CameraController")
	local SUs = H.cmod(p, "UI.SettingsUI")
	local panel = p.PlayerGui:FindFirstChild("Panel_settings", true)
	local ticks, longTick = 0, 0
	if panel then
		for _, d in panel:GetDescendants() do
			local i = tonumber(string.match(d.Name, "^ZoomTick_(%d+)$"))
			if i then
				ticks += 1
				if d.Size.Y.Offset == 4 then
					longTick = i
				end
			end
		end
	end
	H.expect(ticks == 10 and longTick == Tuning.CamZoomDefault, "settings", "the View slider: ten notches, the default's tick longer", string.format("%d ticks, long %d", ticks, longTick))
	H.expect(H.buttonNamed(p, "ZoomOut") ~= nil and H.buttonNamed(p, "ZoomIn") ~= nil and panel ~= nil and panel:FindFirstChild("ZoomKnob", true) ~= nil and panel:FindFirstChild("ZoomSlider", true) ~= nil, "settings", "with - and + at its ends, a knob and a track to drag")
	H.expect(prof.settings.zoom == Tuning.CamZoomDefault and H.inClient(p, CCs.zoom) == Tuning.CamZoomDefault and CCs.view().grid.a == 11, "settings", "a new player on the default notch, the seventh: 11 art px a stud", string.format("%s %s %g", tostring(prof.settings.zoom), tostring(H.inClient(p, CCs.zoom)), CCs.view().grid.a))
	local knob = panel and panel:FindFirstChild("ZoomKnob", true)
	local kx0 = if knob and knob:IsA("GuiObject") then knob.Position.X.Offset else -1
	H.clickNamed(p, "ZoomOut", { wait = 0.05 })
	H.clickNamed(p, "ZoomOut", { wait = 0.05 })
	local kx1 = if knob and knob:IsA("GuiObject") then knob.Position.X.Offset else -1
	H.expect(kx1 < kx0 and H.inClient(p, SUs.zoom) == Tuning.CamZoomDefault - 2 and H.inClient(p, CCs.zoom) == Tuning.CamZoomDefault, "settings", "two taps on -: the knob moves two notches at once, the camera waits for the last", string.format("knob %d -> %d, notch %d, camera %d", kx0, kx1, H.inClient(p, SUs.zoom), H.inClient(p, CCs.zoom)))
	E.run(0.6)
	local want = Tuning.CamZoomNotches[Tuning.CamZoomDefault - 2]
	H.expect(H.inClient(p, CCs.zoom) == Tuning.CamZoomDefault - 2 and CCs.view().grid.a == want and prof.settings.zoom == Tuning.CamZoomDefault - 2, "settings", "then the island at that notch, kept with the profile", string.format("%g art px a stud, saved %s", CCs.view().grid.a, tostring(prof.settings.zoom)))
	-- the far ends: as a drag to them would; past them it stays
	H.inClient(p, SUs.setZoom, 1)
	E.run(0.6)
	H.expect(CCs.view().grid.a == Tuning.CamZoomNotches[1] and prof.settings.zoom == 1, "settings", "dragged all the way out: the first notch", string.format("%g", CCs.view().grid.a))
	H.clickNamed(p, "ZoomOut", { wait = 0.6 })
	H.expect(prof.settings.zoom == 1, "settings", "and - does nothing past it", tostring(prof.settings.zoom))
	H.inClient(p, SUs.setZoom, 10)
	E.run(0.6)
	H.expect(CCs.view().grid.a == Tuning.CamZoomNotches[10] and prof.settings.zoom == 10, "settings", "all the way in: the tenth", string.format("%g", CCs.view().grid.a))
	H.clickNamed(p, "ZoomIn", { wait = 0.6 })
	H.expect(prof.settings.zoom == 10, "settings", "and + does nothing past it", tostring(prof.settings.zoom))
	for _, bad in { 0, 11, 2.5, "close" } do
		H.expect(H.req(p, "settings.set", { k = "zoom", v = bad }).err == "bad_payload", "settings", "a View notch that isn't 1 to 10: bad_payload", tostring(bad))
	end
	H.inClient(p, SUs.setZoom, Tuning.CamZoomDefault)
	E.run(0.6)
	H.expect(CCs.view().grid.a == 11 and prof.settings.zoom == Tuning.CamZoomDefault, "settings", "and back to the default", string.format("%g", CCs.view().grid.a))
end
H.closePanel(p)
-- the sounds (GAME_DESIGN 11): every event has a library sound, each of its takes too; the founder's feet are heard
-- (the game's own step sounds: Roblox's are switched off by the empty RbxCharacterSounds)
local Mon = H.sharedServer("Config.Monetization")
local noSound = {}
for name, ev in AudioM.EVENTS do
	local ok = H.inClient(p, AudioM.has, name)
	for _, k in ev.ids or {} do
		ok = ok and (Mon.Sounds[k] or 0) > 0
	end
	if not ok then
		table.insert(noSound, name)
	end
end
table.sort(noSound)
H.expect(#noSound == 0, "join", "every sound has a library sound behind it (each take too)", table.concat(noSound, ","))
local function stepSounds(): number
	return H.inClient(p, AudioM.playCount, "step_grass") + H.inClient(p, AudioM.playCount, "step_sand") + H.inClient(p, AudioM.playCount, "step_wood")
end
local steps0 = stepSounds()
local walkRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if walkRoot then
	local at = walkRoot.Position
	for k = 1, 16 do
		p.Character:PivotTo(E.cf.new(at.X + k * 0.6, at.Y, at.Z))
		E.run(0.05)
	end
	p.Character:PivotTo(E.cf.new(at.X, at.Y, at.Z))
	E.run(0.3)
end
H.expect(stepSounds() > steps0, "join", "the founder's footsteps are heard as they walk", string.format("%d -> %d", steps0, stepSounds()))
local tipsOk = H.buttonNamed(p, "TipsOk")
H.expect(tipsOk == nil, "join", "the first tips have no OK (they move on by building)")
-- a line of the HUD or a notice saying `pattern` (plain)
local function statusSays(pattern)
	for _, d in p.PlayerGui:GetDescendants() do
		-- (shown words only: a closed scene's labels left hidden don't count)
		if d:IsA("TextLabel") and string.find(d.Text, pattern, 1, true) and H.guiVisible(d) then
			return true
		end
	end
	return false
end
-- the Fx messages of `kind` the first player's client heard since the i0-th
local function fxSince(i0, kind)
	local out = {}
	for i = i0 + 1, #fx do
		if fx[i].kind == kind then
			table.insert(out, fx[i])
		end
	end
	return out
end
local UIKitP = H.cmod(p, "UI.UIKit")
local EggViewP = H.cmod(p, "Controllers.EggView")
local SCp = H.cmod(p, "Controllers.StateClient")
local PRp = H.cmod(p, "Pixel.PixelRenderer")
local WVp = H.cmod(p, "Controllers.WorldView")
-- the profile's egg `id` while it is still under the tree, or nil
local function eggOf(id)
	for _, e in prof.clutch.list do
		if e.id == id then
			return e
		end
	end
	return nil
end
local function idsOf(list)
	local out = {}
	for _, e in list do
		table.insert(out, tostring(e.id))
	end
	return table.concat(out, ",")
end
-- the eggs as the plot's Eggs attribute writes them: "id.rarity;..."
-- the eggs the world shows round the tree: the rarest Tuning.EggShown of the lot, the first laid of two the same
-- (Logic/Tree.shown, the ring's room; the tree's panel lists them all)
local function shownOf(list)
	local shown = table.clone(list)
	table.sort(shown, function(a, b)
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	while #shown > Tuning.EggShown do
		table.remove(shown)
	end
	return shown
end
local function eggsAttr(list)
	local out = {}
	for _, e in shownOf(list) do
		table.insert(out, string.format("%d.%d", e.id, e.r) .. (if e.wx then "." .. e.wx else ""))
	end
	return table.concat(out, ";")
end
-- the best n eggs, as the HUD's card picks them (GAME_DESIGN 6): the rarest first (the older of two the same), and if
-- the shells cover none of those, the best one they do in the last place
local function bestOf(list, shells, n)
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	local out, can = {}, false
	for i = 1, math.min(n, #sorted) do
		table.insert(out, sorted[i])
		can = can or shells >= sorted[i].cost
	end
	if not can and #out > 0 then
		for i = n + 1, #sorted do
			if shells >= sorted[i].cost then
				out[#out] = sorted[i]
				break
			end
		end
	end
	return out
end
-- the view's eggs and the profile's are the same ones (a whole view reaches the client a frame after the server's change)
local function eggsSynced(pl)
	local v, pr = H.view(pl), H.profile(pl)
	return v ~= nil and pr ~= nil and type(v.clutch) == "table" and idsOf(v.clutch) == idsOf(pr.clutch.list)
end
local function mirror(pl, label)
	E.runUntil(function()
		return eggsSynced(pl)
	end, 0.5)
	H.checkMirror(pl, label)
end
-- the Tree of Life's piece on a profile's island
local function treePiece(pr)
	for _, q in (pr or prof).plot.placed do
		if q.id == "tree" then
			return q
		end
	end
	return nil
end
-- its middle on the lawn (world), as EggView finds it from its model
local function treeMiddle(plot, q)
	local ox, oz = Street.origin(plot)
	local w, d = Plot.footprint(q.id, q.rot)
	return E.v3(ox + q.x + w / 2, Street.LAWN_Y, oz + q.z + d / 2)
end
-- the tree's model on island `plot` (Static.Decor: "uid:tree:x:z:rot:stage"), or nil
local function treeModel(plot)
	local pm = E.workspace.Plots:FindFirstChild("Plot_" .. plot)
	local decor = pm and pm:FindFirstChild("Decor", true)
	for _, c in (decor and decor:GetChildren() or {}) do
		if c:GetAttribute("Decor") == "tree" then
			return c
		end
	end
	return nil
end
-- island `plot`'s eggs as client `pl` draws them (EggView.where): how many, whether each lies on the ring round the
-- tree's middle, on the lawn, and none on another's spot
local function ringState(pl, plot, list, q)
	local ev = H.cmod(pl, "Controllers.EggView")
	local mid = treeMiddle(plot, q)
	local drawn, onRing, apart = 0, true, true
	local spots = {}
	local clash = {}
	for _, e in list do
		local at = H.inClient(pl, ev.where, plot, e.id)
		if at then
			drawn += 1
			local dx, dz = at.X - mid.X, at.Z - mid.Z
			onRing = onRing and math.abs(math.sqrt(dx * dx + dz * dz) - DecorModels.EGG_RING) < 0.01 and math.abs(at.Y - Street.LAWN_Y) < 0.01
			for _, o in spots do
				if (at.X - o.at.X) ^ 2 + (at.Z - o.at.Z) ^ 2 <= 1 then
					apart = false
					table.insert(clash, string.format("%d/%d", o.id, e.id))
				end
			end
			table.insert(spots, { id = e.id, at = at })
		end
	end
	return drawn, onRing, apart, table.concat(clash, " ")
end
-- "m:ss", as the HUD and the panel write a time; and the seconds in such a text
local function clockOf(secs)
	local n = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", n // 60, n % 60)
end
local function secsIn(text)
	local m, ss = string.match(text or "", "(%d+):(%d%d)")
	return if m then tonumber(m) * 60 + tonumber(ss) else nil
end
-- the rarity an egg of rarity r hatches at (its own on every island since the request of 2026-11-19, "Make all eggs
-- obtainable regardless of expansion level": one none of the open kinds has hatches a kind not open yet)
local function hatchRarity(r)
	return r
end
-- the shells the island may have earned on its own since t1 (a turn's rate over TurnSeconds, with room to spare;
-- `rate`: the rate before a change that may have lowered it)
local function earnedSince(t1, rate)
	return math.max(rate or 0, Island.rates(prof).shells) / Tuning.TurnSeconds * (E.now() - t1) * 1.5 + 0.5
end
-- the shells moved since sh1 come to `want`, give or take what the island earned on its own since t1
local function paid(sh1, want, t1, rate)
	local got = prof.shells - sh1
	return got >= want - 0.5 and got <= want + earnedSince(t1, rate)
end
-- the Tree of Life (GAME_DESIGN 6): every island has one in its middle, its model by its stage. Its first lot of
-- eggs is laid the moment the island wakes (Tree.count by the tier, the first two cheap commons on a new island), the
-- next lot Tree.secs away. The view carries the eggs with their prices; the HUD's tree card shows the time to the next
-- lot and the best three (EggView.best); EggView lays every egg on a ring round the tree, the price tags over them
local treeQ = treePiece()
do
	local model = treeModel(s.plot)
	H.expect(treeQ ~= nil and model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", treeQ.uid, treeQ.x, treeQ.z, treeQ.rot, TreeL.stage(prof.tier)), "join", "the tree's model on the island, named by its piece and its stage", model and model.Name)
	local c = prof.clutch
	local n = TreeL.count(prof.tier)
	H.expect(n == Tuning.EggCount[1] and #c.list == n and c.next == n + 1, "join", "its first lot laid at once: Tree.count(1) eggs round its roots", string.format("%d of %d, next %d", #c.list, n, c.next))
	local common = TreeL.cost(prof, 1)
	H.expect(#c.list >= 2 and c.list[1].r == 1 and c.list[2].r == 1 and common == Tuning.EggPrice[1] * Tuning.EggTier[1] and 2 * common <= Tuning.StartShells, "join", "the first two cheap commons the starting shells cover", eggsAttr(c.list))
	H.expect(math.abs(TreeL.secs(prof) - Tuning.EggSecs) < 1e-9 and c.left > TreeL.secs(prof) - 16 and c.left <= TreeL.secs(prof), "join", "the next lot Tree.secs (EggSecs) away (the Settings checks before it take a few seconds)", string.format("%.1f s of %.1f", c.left, TreeL.secs(prof)))
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list) and plot1:GetAttribute("Tide") == nil, "join", "the plot's Eggs attribute: each egg's id and rarity (no Tide)", tostring(plot1:GetAttribute("Eggs")))
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local v0 = H.view(p)
	local same = v0 ~= nil and #v0.clutch == #c.list
	for i, e in c.list do
		same = same and v0.clutch[i].id == e.id and v0.clutch[i].r == e.r and v0.clutch[i].cost == TreeL.cost(prof, e.r)
	end
	H.expect(same and v0.clutchSecs == TreeL.secs(prof) and math.abs(v0.clutchLeft - c.left) <= 1.1 and v0.tide == nil and v0.tideSecs == nil and v0.tree == nil and v0.penN == nil, "join", "the view carries the eggs with their prices, the time to the next lot and between two (no tide, no tree levels, no pen)", v0 and string.format("%d of %d, %s s, %s left", #v0.clutch, #c.list, tostring(v0.clutchSecs), tostring(v0.clutchLeft)))
	local left, secs = H.inClient(p, SCp.clutchLeft)
	H.expect(math.abs(left - c.left) < 0.6 and secs == TreeL.secs(prof), "join", "StateClient.clutchLeft: the server's time to the next lot, run down by the clock", string.format("%.2f vs %.2f, %s", left, c.left, tostring(secs)))
	local card = p.PlayerGui:FindFirstChild("TreeCard", true)
	local nextL = card and card:FindFirstChild("TreeNext", true)
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TreeOpen") ~= nil and card:FindFirstChild("TreeBar", true) ~= nil and nextL ~= nil, "join", "the HUD's Tree of Life card with Open, the time to the next lot and its bar")
	H.expect(nextL ~= nil and nextL.Text == "New eggs in " .. clockOf(left), "join", "its time to the next lot", nextL and nextL.Text)
	H.expect(p.PlayerGui:FindFirstChild("TideCard", true) == nil and H.buttonNamed(p, "TideOpen", true) == nil, "join", "(no tide card)")
	local best3 = H.inClient(p, EggViewP.best, v0, 3)
	local rows, cardRows, buys = 0, 0, 0
	for _, e in best3 do
		local price = card and card:FindFirstChild("CardPrice_" .. e.id, true)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if price and price:IsA("TextLabel") and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and price.Text == Numbers.coins(e.cost) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardPrice_" then
			cardRows += 1
		end
		if string.sub(x.Name, 1, 10) == "CardHatch_" then
			buys += 1
		end
	end
	H.expect(#best3 == 3 and idsOf(best3) == idsOf(bestOf(v0.clutch, v0.shells, 3)) and rows == #best3 and cardRows == #best3, "join", "the card shows the best three eggs, each with its egg, its rarity and its price", string.format("%s: %d rows, %d on the card", idsOf(best3), rows, cardRows))
	-- (the request of 2026-11-13: "the eggs should be buyable only after the player clicks on the tree or enters the tree
	-- menu": the card has no buy buttons, a tap on it opens the tree's panel)
	H.expect(buys == 0 and H.buttonNamed(p, "TreeCardTap") ~= nil, "join", "the card buys nothing itself: a tap on it opens the tree's panel", string.format("%d buy buttons", buys))
	-- (each egg rises out of the lawn, one after another)
	local shown0 = shownOf(c.list)
	E.runUntil(function()
		return H.inClient(p, EggViewP.count, s.plot) == #shown0
	end, 3, 0.1)
	E.run(1.5)
	local drawn, onRing, apart, clash = ringState(p, s.plot, shown0, treeQ)
	H.expect(#shown0 == math.min(#c.list, Tuning.EggShown) and drawn == #shown0 and H.inClient(p, EggViewP.count, s.plot) == #shown0 and onRing and apart, "join", "EggView lays the rarest dozen on the ring round the tree, each on its own spot", string.format("%d drawn of %d, ring %s, on one spot: %s", drawn, #shown0, tostring(onRing), clash))
	local tags = H.inClient(p, function()
		local n = 0
		for _, d in UIKitP.canvas("World"):GetDescendants() do
			if string.sub(d.Name, 1, 9) == "EggHatch_" then
				n += 1
			end
		end
		return n
	end)
	H.expect(tags == 0, "join", "no price tags over the eggs (they are bought in the tree's panel)", tostring(tags))
	H.log("eggs: %s laid, %d drawn", eggsAttr(c.list), drawn)
	local named = H.inClient(p, function()
		for _, d in UIKitP.canvas("World"):GetDescendants() do
			if string.sub(d.Name, 1, 8) == "EggName_" then
				return true
			end
		end
		return false
	end)
	H.expect(not named, "join", "no names over the eggs (their spots show the rarity)")
	-- no hut yet: a tap on the card opens the tree's panel; Hatch there is refused (no_hut) and says why
	local e1 = nil
	for _, e in best3 do
		if e.cost <= prof.shells and (e1 == nil or e.cost < e1.cost) then
			e1 = e
		end
	end
	H.expect(e1 ~= nil, "join", "an egg on the card the starting shells cover")
	if e1 then
		local sh = prof.shells
		H.clickNamed(p, "TreeCardTap", { wait = 0.5 })
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "PanelHatch_" .. e1.id) ~= nil, "join", "a tap on the card opens the tree's panel, the egg there with its Hatch", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. e1.id, { wait = 0.5 })
		H.expect(#prof.pals == 0 and prof.shells == sh and eggOf(e1.id) ~= nil, "join", "no hut yet: hatching is refused, nothing paid, the egg still there", string.format("%d driftlings, %s shells", #prof.pals, tostring(prof.shells)))
		H.expect(statusSays("Build a hut first"), "join", "and the notice says to build a hut first")
		H.closePanel(p)
		local res = H.req(p, "egg.hatch", { id = e1.id, swap = 0 })
		H.expect(not res.ok and res.err == "no_hut", "join", "the server's word for it: no_hut", tostring(res.err))
	end
end
H.checkProfile(p, "join")
mirror(p, "join")

------------------------------------------------------------------ 2. building
E.phase = "build"
-- a cell where a piece fits (from the south-east, the side the camera sees)
local function spot(id, rot)
	local pr = Street.plot(prof.tier)
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if Plot.fits(prof.tier, prof.plot.placed, id, x, z, rot) then
				return x, z
			end
		end
	end
	return nil, nil
end
local function place(id)
	local x, z = spot(id, 0)
	return H.req(p, "plot.place", { id = id, x = x or 0, z = z or 0, rot = 0 })
end
local function pieceOf(id)
	for _, q in prof.plot.placed do
		if q.id == id then
			return q
		end
	end
	return nil
end
-- the tips in Build mode: the tray opens on the tip's tab, its building pulsing, the tip's banner over the tray
local BuildUI = H.cmod(p, "UI.BuildUI")
local function tipShown()
	local pg = p:FindFirstChild("PlayerGui")
	for _, x in pg:GetDescendants() do
		if x.Name == "Tips" and H.guiVisible(x) then
			return true
		end
	end
	return false
end
-- the card of the tip's building in the tray, marked to pulse (TutGoal), or nil
local function goalCard(id)
	local c = p.PlayerGui:FindFirstChild("Card_" .. id, true)
	return if c and c:GetAttribute("TutGoal") == true then c else nil
end
-- opens Build mode and says where the tray turned: its tab, its row and the tip's building
local function trayOn()
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	local st = H.inClient(p, BuildUI.debugState)
	return st, string.format("%s %s %s", tostring(st.tab), tostring(st.chip), tostring(st.goal))
end
-- the tips (the request of 2026-11-21: "Guide the player to put down a hut "Make a place for your driftlings to live
-- in!" > Guide the player to hatch a driftling: "You got your first driftling! Now, put down a work space for it to earn
-- coins in. > Guide the player to put down a workspace, the best one > "Great! You can hatch more driftlings from the
-- tree, which refreshes with eggs every few minutes.""): their banners in the user's own words
local TIP_HUT_TEXT = "Make a place for your driftlings to live in!"
local TIP_WORK_TEXT = "You got your first driftling! Now, put down a work space for it to earn coins in."
local TIP_LAST_TEXT = "Great! You can hatch more driftlings from the tree, which refreshes with eggs every few minutes."
local function tipSource(): string
	local t = p.PlayerGui:FindFirstChild("Tips", true)
	local w = t and t:FindFirstChild("Words")
	return if w then tostring(w:GetAttribute("Source")) else "no tip"
end
H.expect(tipSource() == TIP_HUT_TEXT, "build", "the first tip: make a place for the driftlings to live in", tipSource())
do
	-- (Build mode shut, a tip asking for something built: the menu bar's Build button pulses yellow)
	local mb = H.buttonNamed(p, "Menu_build")
	H.expect(mb ~= nil and mb:GetAttribute("TipPulse") == true, "build", "the menu bar's Build button pulses for the hut's tip")
end
H.expect(H.clickNamed(p, "Menu_build", { wait = 0.4 }) and BuildUI.isOpen(), "build", "Build mode opens")
-- (the request of 2026-11-14: "add the free decor gamepass in the build menu")
H.expect(H.buttonNamed(p, "BuyFreeDecor") ~= nil, "build", "Build mode offers the Free Decor pass (not owned)")
local bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "nest" and bst.goal == "nest" and goalCard("nest") ~= nil, "build", "the first tip: the Huts tab, the hut's card pulsing", string.format("%s %s %s", tostring(bst.tab), tostring(bst.chip), tostring(bst.goal)))
H.expect(tipShown(), "build", "the tip's banner shows in Build mode")
do
	local mb = H.buttonNamed(p, "Menu_build")
	H.expect(mb == nil or mb:GetAttribute("TipPulse") ~= true, "build", "Build mode open: the Build button's pulse stops")
end
do
	-- (the request of 2026-11-20: "make the highlight during tutorial make the whole green button yellow instead and
	-- shine"): the tip's building's whole button is yellow (pulsing toward a paler yellow), never the green one
	local b = H.buttonNamed(p, "Buy_nest")
	local plate = b and b:FindFirstChild("Plate")
	local fill = plate and plate:FindFirstChild("Fill")
	local c = fill and fill.BackgroundColor3
	H.expect(c ~= nil and c.R > 0.95 and c.G > 0.75 and c.B < 0.65, "build", "the tip's building's whole button is yellow", if c then string.format("%.2f %.2f %.2f", c.R, c.G, c.B) else "no fill")
end
H.clickNamed(p, "Tab_decor", { wait = 0.3 })
H.expect(H.inClient(p, BuildUI.debugState).tab == "decor", "build", "the player can still look round the other tabs")
H.expect(H.buttonNamed(p, "Buy_tree", true) == nil, "build", "no Tree of Life in the tray (every island has its one)")
H.clickNamed(p, "Tab_nest", { wait = 0.3 })
-- (the tip's banner rides on the tray, whatever height it is: the user's report of 2026-11-14, "the tutorial tooltip
-- sometimes gets hidden by the build menu after something is built": a piece still picked when the camp went up, the
-- next tip's banner was laid on the short tray, then the tray turned to the next tip's row at its full height)
local function tipsAbove(): (boolean, string)
	local tipsF = p.PlayerGui:FindFirstChild("Tips", true)
	local trayF = p.PlayerGui:FindFirstChild("BuildTray", true)
	if tipsF == nil or trayF == nil then
		return false, "missing " .. (if tipsF == nil then "Tips" else "BuildTray")
	end
	local bottom = tipsF.AbsolutePosition.Y + tipsF.AbsoluteSize.Y
	return bottom <= trayF.AbsolutePosition.Y, string.format("banner's bottom %d, tray's top %d", bottom, trayF.AbsolutePosition.Y)
end
-- (the banner rides on the tray as it changes height, a piece picked and let go)
do
	H.inClient(p, BuildUI.pick, "nest")
	E.run(0.5)
	local ok, say = tipsAbove()
	H.expect(ok, "build", "a piece picked, the tray shorter: the tip's banner comes down with it, above it", say)
	H.clickNamed(p, "Cancel", { wait = 0.5 })
	ok, say = tipsAbove()
	H.expect(ok, "build", "the pick let go, the tray full height again: the tip's banner goes back up over it", say)
end
-- the tray's own placing, as a player does it: a card picked, a tap on the lawn, Place
local function placeFromTray(id)
	H.inClient(p, BuildUI.pick, id)
	E.run(0.3)
	local lx, lz = spot(id, 0)
	local ox, oz = Street.origin(s.plot)
	local w, d = Plot.footprint(id, 0)
	local at = H.inClient(p, function()
		local pos = PRp.project(E.v3(ox + (lx or 0) + w / 2, Street.LAWN_Y, oz + (lz or 0) + d / 2))
		return E.v2(pos.X, pos.Y - E.inset)
	end)
	H.inClient(p, BuildUI.tapScreen, at, false)
	E.run(0.2)
	H.clickNamed(p, "Place", { wait = 0.6 })
	return { ok = pieceOf(id) ~= nil, err = if pieceOf(id) then nil else "not placed" }
end
local sh0 = prof.shells
local res = placeFromTray("nest")
H.expect(res.ok and #prof.plot.placed == 2 and pieceOf("nest") ~= nil, "build", "a hut, built from the tray", tostring(res.err))
H.expect(math.abs(prof.shells - (sh0 - Buildings.byId.nest.shells)) < 2 and prof.wood == nil, "build", "paid for in shells (no wood any more)", string.format("shells %s -> %s", sh0, prof.shells))
H.expect(prof.tut == Plot.TIP_HATCH, "build", "a hut: the tips move on to hatching an egg", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
-- (the request of 2026-11-14: "auto close the build tab when going to the hatching step and point towards the tree of
-- life for the player to click": the hut placed with Build mode open, it closes itself a moment later, and an arrow
-- points at the Tree of Life, or from the screen's edge the way to it)
E.run(1.3)
H.expect(not BuildUI.isOpen(), "build", "the hut placed in Build mode: Build mode closes itself for the hatching tip")
do
	local arrow = p.PlayerGui:FindFirstChild("TutArrow", true)
	H.expect(arrow ~= nil and arrow:IsA("GuiObject") and arrow.Visible, "build", "an arrow points at the Tree of Life for the hatching tip")
	local mb = H.buttonNamed(p, "Menu_build")
	H.expect(mb ~= nil and mb:GetAttribute("TipPulse") ~= true, "build", "no pulse on the Build button for the hatching tip (it asks for nothing built)")
end
-- (how full the buildings are, the request of 2026-11-14: "if noone is working on a building, make a alert on top of
-- said work building stating so. do the same for huts and housing", and then "Make it say "Empty"": with no driftling
-- yet, the hut has no alert over it)
local BTp = H.cmod(p, "Controllers.BuildingTags")
do
	E.run(0.6)
	local bt = H.inClient(p, BTp.debugState)
	-- (no alerts since the request of 2026-11-17: "remove the empty alert that appears above huts and work places")
	H.expect(bt.spots == 1 and bt.alerts == 0, "build", "with no driftling yet: the hut known, no \"Empty\" over it", string.format("%d spots, %d alerts: %s", bt.spots, bt.alerts, table.concat(bt.words, ",")))
end
-- (the starting shells cover the rest of the tips with room for a second egg: "give the player more shells so every
-- task is completable at the start without needing to wait"; the tips' workplace is free besides)
H.expect(prof.shells >= Buildings.byId[Plot.tipWork(prof.tier)].shells + 2 * Tuning.EggPrice[2] * Tuning.EggTier[1], "build", "after the hut, the shells left pay for the best workplace and two uncommon eggs", tostring(prof.shells))
-- the hatching tip: an egg hatched. A tap on an egg under the tree (EggView.tapAt: WorldView's taps ask it first) opens the tree's
-- panel and buys nothing (the request of 2026-11-13: "the eggs should be buyable only after the player clicks on the tree
-- or enters the tree menu"); Hatch there on the cheapest the shells cover plays the hatch scene (UI/HatchScene: the egg
-- floating, each tap revealing a step up or a mutation, the tap after them hatching it), one more goes back; what hatches (a new island's
-- first) moves into the hut and rests there till a workplace stands, and the panel is there again
local HSp = H.cmod(p, "UI.HatchScene")
do
	H.push(p, 0.3)
	H.expect(statusSays("There are new eggs under the tree! Tap it to hatch one."), "build", "the tip asks for an egg hatched")
	-- (in the client: the cheapest such egg and the screen point in the middle of it, as a tap's position)
	local function target()
		local v = H.view(p)
		return H.inClient(p, function()
			local pick, pos = nil, nil
			for _, e in v.clutch do
				local at = EggViewP.where(s.plot, e.id)
				if at and (e.cost or math.huge) <= v.shells and Street.LAWN_Y - at.Y < 0.05 then
					local foot, on = PRp.project(at)
					local top = PRp.project(at + E.v3(0, 1.3, 0))
					if on and (pick == nil or e.cost < pick.cost) then
						pick, pos = e, E.v2(foot.X, (foot.Y + top.Y) / 2 - E.inset)
					end
				end
			end
			return pick, pos
		end)
	end
	local pick, pos = nil, nil
	E.runUntil(function()
		pick, pos = target()
		return pick ~= nil
	end, 3, 0.1)
	H.expect(pick ~= nil and prof.shells >= pick.cost, "build", "an egg under the tree the starting shells cover, in view", pick and string.format("%s shells, it costs %d", tostring(prof.shells), pick.cost) or "none")
	if pick then
		local sh1, t1, rate0 = prof.shells, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.inClient(p, WVp.tapScreen, pos)
		E.run(0.6)
		H.expect(#prof.pals == 0 and eggOf(pick.id) ~= nil and H.currentPanel(p) == "tree", "build", "a tap on the egg opens the tree's panel and buys nothing", string.format("%d driftlings, panel %s", #prof.pals, tostring(H.currentPanel(p))))
		H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.3 })
		local hs = H.inClient(p, HSp.debugState)
		H.expect(hs.open and hs.r == pick.r and hs.hr == pick.r and H.currentPanel(p) == nil, "build", "Hatch: the hatch scene opens on the egg (the panel shut meanwhile; a new island's first never turns rarer)", string.format("open %s r %d hr %d", tostring(hs.open), hs.r, hs.hr))
		-- (the request of 2026-11-14: "make the player click to hatch the egg, each click revealing a mutation or a tier
		-- up upgrade if there is any, otherwise it just hatches": no blinds, the egg there at once)
		hs = H.inClient(p, HSp.debugState)
		H.expect(hs.phase == "egg" and hs.egg and not hs.pal, "build", "the egg floats there at once, waiting for a tap", string.format("phase %s", hs.phase))
		-- (its title the rarity alone: "no need for "A x egg" for rarities for eggs, just do "Legendary" "Common" etc.")
		H.expect(hs.title == Traits.RARITY[pick.r].name, "build", "the egg's title: its rarity alone", string.format("%q", hs.title))
		-- (centred over the screen, by scale: the user's report of 2026-11-14, "it sometimes doesnt center the text here")
		H.expect(math.abs(hs.titleOff) <= 1, "build", "the egg's title sits in the middle of the screen", string.format("%.1f px off", hs.titleOff))
		-- (then "make the egg rise up into view when it is being opened", and since "Make the egg drop down and bounce a
		-- bit instead of appearing by going up": it drops in from above onto its pedestal, and a tap while it comes
		-- down waits; the cracks crunch, Audio "crack", and the hatch breaks it open, "crack_open")
		H.expect(hs.lift > 0.5, "build", "it is still dropping into view", string.format("%.2f studs over its spot at %.2f s", hs.lift, hs.clock))
		local Aud = H.cmod(p, "Controllers.Audio")
		local crack0, open0 = H.inClient(p, Aud.playCount, "crack"), H.inClient(p, Aud.playCount, "crack_open")
		H.inClient(p, HSp.skip)
		E.run(0.05)
		local hsr = H.inClient(p, HSp.debugState)
		H.expect(hsr.left == hsr.reveals and not hsr.pal, "build", "a tap while it comes down does nothing yet", string.format("%d of %d left", hsr.left, hsr.reveals))
		E.run(1)
		hs = H.inClient(p, HSp.debugState)
		H.expect(hs.lift == 0, "build", "it has landed on its pedestal", string.format("%.2f", hs.lift))
		H.expect(hs.rings >= 1, "build", "rings spread from under it once it has landed", tostring(hs.rings))
		local taps, revealed = 0, 0
		local shook, broke = 0, nil
		while not hs.pal and taps < 12 do
			H.inClient(p, HSp.skip)
			E.run(0.05)
			hs = H.inClient(p, HSp.debugState)
			shook = math.max(shook, hs.shake)
			E.run(0.3)
			taps += 1
			local before = revealed
			hs = H.inClient(p, HSp.debugState)
			revealed = hs.reveals - hs.left
			if hs.phase == "breaking" then
				-- (the request of 2026-11-14: "Make eggs shake while being cracked open": the tap that hatches it
				-- shakes it harder and harder, every crack showing, then the shell opens)
				broke = { shake = hs.shake, crack = hs.crack, pal = hs.pal, glowing = hs.glowing, beams = hs.beams }
				E.run(0.45)
				hs = H.inClient(p, HSp.debugState)
			elseif not hs.pal then
				H.expect(revealed == before + 1, "build", "a tap before it hatches reveals one step up or mutation", string.format("tap %d: %d revealed", taps, revealed))
			end
		end
		H.expect(hs.pal and taps == hs.reveals + 1, "build", "each tap reveals a step up or a mutation, the one after them hatches it", string.format("%d taps, %d reveals", taps, hs.reveals))
		H.expect(broke ~= nil and broke.shake > 0.7 and broke.crack == 3 and broke.glowing and not broke.pal and (hs.reveals == 0 or shook > 0.2), "build", "it shakes as it cracks: each tap, then harder as it breaks open, every crack lit", broke and string.format("shake %.2f at the break, cracks %d, %.2f a tap", broke.shake, broke.crack, shook) or "no break")
		-- (the requests of 2026-11-14: "cracks sometimes become filled like this, can you make it such that light streams
		-- out instead when this happens?", then "make light stream out, as in rays of light streaming out, like the
		-- image": rays of light out of the cracks shown)
		H.expect(broke ~= nil and broke.beams > 0, "build", "rays of light stream out of the cracks as it cracks", broke and tostring(broke.beams) or "no break")
		local crack1, open1 = H.inClient(p, Aud.playCount, "crack"), H.inClient(p, Aud.playCount, "crack_open")
		H.expect(crack1 - crack0 == hs.reveals + 1 and open1 - open0 == 1, "build", "each reveal cracks it with a crunch, so does the tap that hatches it, and the shell opens with a sound", string.format("%d crunches for %d reveals, %d opens", crack1 - crack0, hs.reveals, open1 - open0))
		E.run(0.8)
		hs = H.inClient(p, HSp.debugState)
		local def0 = prof.pals[1] and Creatures.byId[prof.pals[1].sp]
		H.expect(hs.name == (def0 and def0.name) and hs.shown == hs.muts and hs.phase == "done" and def0 ~= nil and hs.passive == def0.passive.name, "build", "its name under it, its passive on a plate above its mutations (no \"No mutations\" plate)", string.format("%q, %d of %d, %s", hs.name, hs.shown, hs.muts, hs.phase))
		-- (the request of 2026-11-14: "there should a tip saying "New!" If the creature caught is new")
		H.expect(hs.fresh, "build", "the first of its kind: a \"New!\" tag by its name", tostring(hs.fresh))
		H.inClient(p, HSp.skip)
		E.runUntil(function()
			return not H.inClient(p, HSp.debugState).open
		end, 4, 0.1)
		E.run(0.3)
		H.expect(not H.inClient(p, HSp.debugState).open and H.currentPanel(p) == "tree", "build", "a tap goes back to the island, the tree's panel there again", tostring(H.currentPanel(p)))
		local first = prof.pals[1]
		local c = first and Creatures.byId[first.sp]
		H.expect(#prof.pals == 1 and prof.stats.taken == 1 and paid(sh1, -pick.cost, t1, rate0), "build", "Hatch in the tree's panel hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r), "build", "a driftling of the egg's rarity (a new island's first)", first and string.format("%s r%d", first.sp, pick.r))
		H.expect(eggOf(pick.id) == nil, "build", "and the egg is gone from under the tree")
		local hatched = fxSince(f1, "hatched")
		H.expect(#hatched == 1 and type(hatched[1].data) == "table" and hatched[1].data.egg == pick.id and hatched[1].data.sp == (first and first.sp), "build", "the client hears of it (Fx hatched)", tostring(#hatched))
		H.expect(statusSays("Hatched "), "build", "and says what hatched")
		H.expect(type(hatched[1]) == "table" and type(hatched[1].data) == "table" and hatched[1].data.new == true and statusSays("New! Hatched "), "build", "a kind never had: the result says new, the notice starts with \"New!\"", tostring(hatched[1] and hatched[1].data and hatched[1].data.new))
		H.closePanel(p)
		-- (from here on the scene ends at once: the hatches below test the rules and the panels, not the scene)
		H.inClient(p, HSp.setQuick, true)
		-- (the island's eggs went while the hatch scene's stage was in view, and come back at the next sync, within half
		-- a second: wait for them)
		E.runUntil(function()
			return H.inClient(p, EggViewP.where, s.plot, pick.id) == nil and H.inClient(p, EggViewP.count, s.plot) == #shownOf(prof.clutch.list)
		end, 2, 0.1)
		H.expect(H.inClient(p, EggViewP.where, s.plot, pick.id) == nil and H.inClient(p, EggViewP.count, s.plot) == #shownOf(prof.clutch.list), "build", "its egg cracks open and is gone, the others stay", tostring(H.inClient(p, EggViewP.count, s.plot)))
		local hut = pieceOf("nest")
		H.expect(first ~= nil and hut ~= nil and first.home == hut.uid and first.work == 0, "build", "it moves into the hut and rests there: no workplace yet", first and string.format("home %d work %d", first.home, first.work))
		H.expect(prof.tut == Plot.TIP_WORK, "build", "the tips move on to a workplace", tostring(prof.tut))
		E.run(0.3)
		H.expect(tipSource() == TIP_WORK_TEXT, "build", "the tip after the first hatch: your first driftling, now a work space", tipSource())
		H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on it (it moves on by building)")
		do
			local mb = H.buttonNamed(p, "Menu_build")
			H.expect(mb ~= nil and mb:GetAttribute("TipPulse") == true, "build", "the menu bar's Build button pulses for the workplace's tip")
		end
		-- (the hut has someone living there; a tap on the hut shows how full it is, "show capacities of work buildings when hovered over", a phone's tap for the hover)
		E.run(0.6)
		local bt = H.inClient(p, BTp.debugState)
		H.expect(bt.alerts == 0, "build", "no alerts over the buildings, empty or not", string.format("%d alerts", bt.alerts))
		local hutTap = nil
		for _, sp in H.inClient(p, BTp.debugSpots) do
			if sp.uid == hut.uid then
				hutTap = sp.tap
			end
		end
		E.raycastParts = true
		local shown = hutTap ~= nil and H.inClient(p, BTp.tapAt, hutTap)
		E.raycastParts = nil
		E.run(0.2)
		bt = H.inClient(p, BTp.debugState)
		H.expect(shown and bt.card == string.format("%s Living here 1/%d", Buildings.byId.nest.name, Buildings.byId.nest.slots), "build", "a tap on the hut: its card, how many live there of its room", string.format("%s %q at %s, the ray met %s", tostring(shown), bt.card, tostring(hutTap), bt.hit))
		E.run(3.2)
		H.expect(H.inClient(p, BTp.debugState).card == "", "build", "the tap's card goes after a few seconds")
	end
end
-- the workplace's tip (the same request: "Guide the player to put down a workspace, the best one"): Build mode opens on
-- Work's Workplaces row, the best workplace the island has pulsing (Plot.tipWork: a first island's Fishing Pier) and
-- free (the request of 2026-11-14 made the tips' first snack stall free); built from the tray it costs nothing, the
-- driftling resting in the hut goes to work there, and the last tip's banner sits above the tray
local best = Plot.tipWork(prof.tier)
do
	E.run(0.3)
	local st, say = trayOn()
	H.expect(best == "pier" and st.tab == "work" and st.chip == "work" and st.goal == best and goalCard(best) ~= nil, "build", "Build mode opens on Work's Workplaces row for the workplace's tip, the best one's card pulsing (a first island's: the Fishing Pier)", say)
	local card = goalCard(best)
	H.expect(card ~= nil and table.find(H.textsOf(card), "Free") ~= nil, "build", "the tips' workplace's card says Free", card and table.concat(H.textsOf(card), "/"))
	H.expect(tipShown(), "build", "the tip's banner over the tray")
end
local shWork = prof.shells
res = placeFromTray(best)
do
	local ok, say = tipsAbove()
	H.expect(ok, "build", "the workplace built from the tray: the next tip's banner sits above the tray, not under it", say)
end
H.expect(res.ok and prof.tut == Plot.TIP_LAST, "build", "the best workplace: the tips move on to the last", string.format("%s tut %d", tostring(res.err), prof.tut))
H.expect(math.abs(prof.shells - shWork) < 1, "build", "the tips' workplace cost nothing", string.format("%.0f -> %.0f", shWork, prof.shells))
E.run(0.3)
H.expect(tipSource() == TIP_LAST_TEXT, "build", "the last tip: more driftlings from the tree, new eggs every few minutes", tipSource())
do
	local first = prof.pals[1]
	local wp = pieceOf(best)
	H.expect(first ~= nil and wp ~= nil and first.work == wp.uid, "build", "the driftling resting in the hut goes to work there", first and string.format("work %d", first.work))
end
H.clickNamed(p, "BuildDone", { wait = 0.3 })
H.expect(not BuildUI.isOpen() and tipShown(), "build", "Done: the tray goes, the tip stays")
-- the rest of a first island's work at their prices (the scenes below were written round a camp and a patch; the
-- stall comes later, one more workplace)
do
	local sh2 = prof.shells
	res = place("lumber")
	H.expect(res.ok and math.abs(prof.shells - (sh2 - Buildings.byId.lumber.shells)) < 2, "build", "a lumber camp at its price", string.format("%s, shells %s -> %s", tostring(res.err), sh2, prof.shells))
	res = place("patch")
	H.expect(res.ok, "build", "a veggie patch", tostring(res.err))
	H.expect(prof.tut == Plot.TIP_LAST, "build", "(the last tip waits for its OK)", tostring(prof.tut))
end
do
	E.run(0.6)
	-- (the island card's Working line with workplaces standing: at work out of two places at each)
	local at, places = 0, 0
	for _, x in prof.pals do
		if x.work ~= 0 then
			at += 1
		end
	end
	places += Island.jobPlaces(prof.plot.placed)
	local wr = p.PlayerGui:FindFirstChild("WorkingR", true)
	H.expect(places >= 4 and at >= 1 and wr ~= nil and wr.Text == string.format("%d/%d", at, places), "hud", "Working with the workplaces up: at work out of their places", wr and wr.Text or "missing")
	-- a tap on the tips' workplace: how full, and what it earns a minute (the request of 2026-11-15: "while hovering
	-- over a work building, show how much it is earning"; Island.output times the charm bonus and the passes)
	local wp = pieceOf(best)
	local wpTap = nil
	for _, sp in H.inClient(p, BTp.debugSpots) do
		if wp and sp.uid == wp.uid then
			wpTap = sp.tap
		end
	end
	E.raycastParts = true
	local shownC = wpTap ~= nil and H.inClient(p, BTp.tapAt, wpTap)
	E.raycastParts = nil
	E.run(0.6)
	local bt = H.inClient(p, BTp.debugState)
	local cv = H.view(p)
	local made = Island.output(prof)[wp and wp.uid or 0] or 0
	local want = string.format("Earns %s coins/min", Numbers.short(math.floor(made * (1 + cv.charmBonus) * cv.incomeMult * 60 / Tuning.TurnSeconds + 0.5)))
	H.expect(shownC and bt.card == string.format("%s Workers 1/%d", Buildings.byId[best].name, Buildings.byId[best].jobs) and bt.card2 == want, "build", "a tap on the tips' workplace: its workers and what it earns a minute", string.format("%q / %q (want %q)", bt.card, bt.card2, want))
	E.run(3.2)
end
local tipCost = Buildings.byId.nest.shells
H.expect(#prof.plot.placed == 5 and tipCost <= Tuning.StartShells and prof.shells >= 0, "build", "the starting shells paid for the tips' hut and the first egg (their workplace free), a camp and a patch besides", string.format("%d pieces, %d shells of %d, %.0f left", #prof.plot.placed, tipCost, Tuning.StartShells, prof.shells))
res = place("orchard")
H.expect(not res.ok and res.err == "locked", "build", "an orchard waits for a bigger island", tostring(res.err))
res = place("tent")
H.expect(not res.ok and res.err == "bad_payload", "build", "no homes to build any more (the Tent is gone)", tostring(res.err))
res = place("tree")
H.expect(not res.ok and res.err == "bad_payload", "build", "a second Tree of Life can't be bought", tostring(res.err))
do
	local sh = prof.shells
	prof.shells = 5
	res = place("nest")
	H.expect(not res.ok and res.err == "money", "build", "not enough shells", tostring(res.err))
	prof.shells = 1000
	res = place("flowers")
	H.expect(res.ok and prof.wood == nil, "build", "shells pay for decor", tostring(res.err))
	if res.ok then
		res = H.req(p, "plot.store", { i = #prof.plot.placed })
		H.expect(res.ok, "build", "(the flowers cleared away again)", tostring(res.err))
	end
	prof.shells = sh
end
H.push(p, 0.4)
local v = H.view(p)
H.expect(v ~= nil and #v.pieces == 5 and v.nests == 2 and v.beds == nil and v.pen == nil and v.folk == nil and v.food == nil, "build", "the view: four pieces and the tree, a hut's room for two (no beds, no pen, no food)", v and string.format("%d %d", #v.pieces, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 5, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
-- the tree in Build mode: tapped, it is picked up like any piece, but Clear away is off for it and nothing replaces it;
-- moved to another free spot, its model and its eggs go with it. The server refuses clearing it away too (fixed)
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	local q = treePiece()
	local ti = table.find(prof.plot.placed, q)
	local uid0 = q.uid
	local function screenOf(world)
		return H.inClient(p, function()
			local pos = PRp.project(world)
			return E.v2(pos.X, pos.Y - E.inset)
		end)
	end
	E.raycastParts = true
	H.inClient(p, BuildUI.tapScreen, screenOf(treeMiddle(s.plot, q) + E.v3(0, 2, 0)), false)
	E.raycastParts = nil
	E.run(0.3)
	local what = p.PlayerGui:FindFirstChild("What", true)
	H.expect(what ~= nil and what.Text == "Moving: Tree of Life" and H.buttonNamed(p, "Place") ~= nil, "build", "a tap on the tree picks it up to move", what and what.Text)
	H.expect(H.buttonNamed(p, "Store", true) ~= nil and H.buttonNamed(p, "Store") == nil and H.buttonNamed(p, "Replace", true) == nil, "build", "Clear away is off for it, and nothing replaces it")
	H.clickNamed(p, "Store", { includeDisabled = true, wait = 0.3 })
	H.expect(treePiece() == q and #prof.plot.placed == 5, "build", "(a tap on Clear away does nothing)")
	-- (a free spot a few cells off)
	local w, d = Plot.footprint("tree", q.rot)
	local pr = Street.plot(prof.tier)
	local tx, tz, best = nil, nil, math.huge
	for z = pr.z0, pr.z1 do
		for x = pr.x0, pr.x1 do
			local dd = (x - q.x) ^ 2 + (z - q.z) ^ 2
			if dd >= 4 and dd < best and Plot.fits(prof.tier, prof.plot.placed, "tree", x, z, q.rot, ti) then
				tx, tz, best = x, z, dd
			end
		end
	end
	H.expect(tx ~= nil, "build", "(a free spot for the tree)")
	if tx then
		local ox, oz = Street.origin(s.plot)
		H.inClient(p, BuildUI.tapScreen, screenOf(E.v3(ox + tx + w / 2, Street.LAWN_Y, oz + tz + d / 2)), false)
		E.run(0.2)
		H.clickNamed(p, "Place", { wait = 0.6 })
		H.expect(q.x == tx and q.z == tz and q.uid == uid0 and treePiece() == q, "build", "Move here: the tree moves, its uid kept", string.format("%d,%d (wanted %d,%d)", q.x, q.z, tx, tz))
		E.run(0.6)
		local model = treeModel(s.plot)
		H.expect(model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, TreeL.stage(prof.tier)), "build", "its model stands in its new place", model and model.Name)
		local shownQ = shownOf(prof.clutch.list)
		local drawn, onRing, apart, clash = ringState(p, s.plot, shownQ, q)
		H.expect(drawn == #shownQ and onRing and apart, "build", "and its eggs lie round it there", string.format("%d of %d, ring %s, on one spot: %s", drawn, #shownQ, tostring(onRing), clash))
	end
	H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	res = H.req(p, "plot.store", { i = table.find(prof.plot.placed, q) })
	H.expect(not res.ok and res.err == "fixed" and treePiece() == q, "build", "the server won't clear the tree away (fixed)", tostring(res.err))
end
H.checkProfile(p, "build")
mirror(p, "build")

------------------------------------------------------------------ 3. turns and days
E.phase = "days"
local day0 = prof.day
local turnFx = 0
local f0 = #fx
local t0 = E.now()
E.runUntil(function()
	for i = f0 + 1, #fx do
		if fx[i].kind == "turn" then
			return true
		end
	end
	return false
end, Tuning.TurnSeconds + 2, 0.1)
E.run(0.3)
for i = f0 + 1, #fx do
	if fx[i].kind == "turn" then
		turnFx += 1
	end
end
H.expect(turnFx == 1 and prof.day == day0, "days", "a turn ends every TurnSeconds (Fx turn), not a day", string.format("%d fx, day %d", turnFx, prof.day))
local ticks, treeTicks = 0, 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
		if H.finite(fx[i].clutchLeft) and H.finite(fx[i].clutchSecs) and fx[i].clutchSecs > 0 and fx[i].tideSecs == nil and fx[i].tideT == nil and fx[i].grow == nil and fx[i].food == nil then
			treeTicks += 1
		end
	end
end
H.expect(ticks >= math.floor(E.now() - t0) - 3, "days", "the stores reach the client every second (Fx tick)", string.format("%d ticks in %.1f s", ticks, E.now() - t0))
H.expect(treeTicks == ticks, "days", "each tick carries the time to the tree's next eggs and the time between two (no tide, no food)", string.format("%d of %d", treeTicks, ticks))
do
	local left = H.inClient(p, SCp.clutchLeft)
	H.expect(math.abs(left - prof.clutch.left) < 0.6, "days", "the client's time to the next lot keeps up with the server's", string.format("%.2f vs %.2f", left, prof.clutch.left))
end
-- a calendar day is hours of the sea's clock: jumped to a day's end, the island counts one (Fx day)
do
	local WC = H.smod("WorldClock")
	local d1 = prof.day
	local f1 = #fx
	WC.shift(Tuning.DaySeconds - (WC.now() % Tuning.DaySeconds) - 0.5)
	E.run(1.2)
	local days = 0
	for i = f1 + 1, #fx do
		if fx[i].kind == "day" then
			days += 1
		end
	end
	H.expect(prof.day == d1 + 1 and days == 1, "days", "the sea's clock passing a day's end counts a day (Fx day)", string.format("day %d -> %d, %d fx", d1, prof.day, days))
	local v1 = H.view(p)
	H.expect(v1 ~= nil and v1.dayFrac < 0.01, "days", "the view's clock at the new day's dawn", tostring(v1 and v1.dayFrac))
end
E.run(0.6)
local WV = H.cmod(p, "Controllers.WorldView")
local function housedN(): number
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
H.expect(housedN() == 1 and H.inClient(p, WV.ownCount) == housedN(), "days", "the hut's driftling walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
local r = Island.rates(prof)
H.expect(r.shells > 0 and r.wood == nil and r.food == nil, "days", "shells come in (a building works a little with nobody at it)", string.format("%.1f", r.shells))
H.checkProfile(p, "days")
mirror(p, "days")

------------------------------------------------------------------ 4. the Tree of Life's eggs (GAME_DESIGN 6)
E.phase = "tree"
-- the cheapest egg under the tree (that `ok` likes), or nil
local function cheapestEgg(ok)
	local best = nil
	for _, e in prof.clutch.list do
		if (ok == nil or ok(e)) and (best == nil or TreeL.cost(prof, e.r) < TreeL.cost(prof, best.r)) then
			best = e
		end
	end
	return best
end
-- the hut driftling the swap picker lists first: the weakest worker
local function weakest()
	local weak = nil
	for _, x in prof.pals do
		if x.home ~= 0 and (weak == nil or TreeL.better(weak, x)) then
			weak = x
		end
	end
	return weak
end
-- a snack stall, one more workplace (the tips built the Fishing Pier)
prof.shells = math.max(prof.shells, 400)
res = place("stall")
H.expect(res.ok, "tree", "a snack stall", tostring(res.err))
-- EggView.best's rule on made-up eggs: three uncommons the shells don't cover and two commons they do; the uncommons
-- first, the older first, and the older common in the last place. With the shells, the three uncommons
do
	local made = {
		{ id = 1, r = 2, cost = 90 },
		{ id = 2, r = 1, cost = 20 },
		{ id = 3, r = 2, cost = 90 },
		{ id = 4, r = 1, cost = 20 },
		{ id = 5, r = 2, cost = 90 },
	}
	local poor = H.inClient(p, EggViewP.best, { clutch = made, shells = 50 }, 3)
	H.expect(idsOf(poor) == "1,3,2" and idsOf(poor) == idsOf(bestOf(made, 50, 3)), "tree", "the best three: the rarest, the best one the shells cover last when they cover none of those", idsOf(poor))
	local rich = H.inClient(p, EggViewP.best, { clutch = made, shells = 500 }, 3)
	H.expect(idsOf(rich) == "1,3,5" and idsOf(rich) == idsOf(bestOf(made, 500, 3)), "tree", "and with the shells, simply the rarest three", idsOf(rich))
end
-- the HUD's tree card: the best three eggs, each with its egg, its rarity's name and its price; over them the time to the
-- next lot, counting down, with a bar running down beside it. A tap on the card opens the tree's panel, where Hatch
-- hatches an egg (the hut has room for one more), and what hatches walks the island
prof.shells = math.max(prof.shells, 2000)
H.push(p, 0.4)
do
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local v1 = H.view(p)
	local best3 = H.inClient(p, EggViewP.best, v1, 3)
	H.expect(idsOf(best3) == idsOf(bestOf(v1.clutch, v1.shells, 3)), "tree", "EggView.best picks the rarest three under the tree", idsOf(best3))
	local card = p.PlayerGui:FindFirstChild("TreeCard", true)
	local rows, cardRows = 0, 0
	for _, e in best3 do
		local price = card and card:FindFirstChild("CardPrice_" .. e.id, true)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if price and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and price.Text == Numbers.coins(e.cost) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardPrice_" then
			cardRows += 1
		end
	end
	H.expect(card ~= nil and H.guiVisible(card) and #best3 == math.min(3, #v1.clutch) and rows == #best3 and cardRows == #best3, "tree", "the tree's card shows them, each with its rarity and its price", string.format("%d of %d, %d on the card", rows, #best3, cardRows))
	local function nextText()
		local c = p.PlayerGui:FindFirstChild("TreeCard", true)
		local t = c and c:FindFirstChild("TreeNext", true)
		return t and t.Text
	end
	local left, secs = H.inClient(p, SCp.clutchLeft)
	local text1 = nextText()
	H.expect(text1 == "New eggs in " .. clockOf(left) and math.abs(left - prof.clutch.left) < 0.6, "tree", "the time to the next lot on the card", string.format("%s (%.1f s on the server)", tostring(text1), prof.clutch.left))
	local back = card and card:FindFirstChild("TreeBar", true)
	local fill = back and back:GetChildren()[1]
	local want = back and math.floor((back.Size.X.Offset - 2) * math.clamp(left / math.max(1, secs), 0, 1) + 0.5)
	H.expect(fill ~= nil and math.abs(fill.Size.X.Offset - want) <= 1, "tree", "its bar as long as the time left", string.format("%s of %s", tostring(fill and fill.Size.X.Offset), tostring(want)))
	local w1 = fill and fill.Size.X.Offset
	E.run(3)
	local text2 = nextText()
	local down = (secsIn(text1) or 0) - (secsIn(text2) or 0)
	H.expect(down >= 2 and down <= 4, "tree", "and it counts down", string.format("%s -> %s", tostring(text1), tostring(text2)))
	card = p.PlayerGui:FindFirstChild("TreeCard", true)
	back = card and card:FindFirstChild("TreeBar", true)
	fill = back and back:GetChildren()[1]
	H.expect(fill ~= nil and w1 ~= nil and fill.Size.X.Offset <= w1, "tree", "the bar with it", string.format("%s -> %s", tostring(w1), tostring(fill and fill.Size.X.Offset)))
	-- hatch one: a tap on the card opens the panel, Hatch there
	local pick = nil
	for _, e in H.inClient(p, EggViewP.best, H.view(p), 3) do
		if e.cost <= prof.shells and card and card:FindFirstChild("CardPrice_" .. e.id, true) ~= nil and (pick == nil or e.cost < pick.cost) then
			pick = e
		end
	end
	H.expect(pick ~= nil, "tree", "an egg on the card the shells cover")
	if pick then
		local sh1, n0, t1, rate0 = prof.shells, #prof.pals, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.clickNamed(p, "TreeCardTap", { wait = 0.4 })
		H.expect(H.currentPanel(p) == "tree" and #prof.pals == n0, "tree", "a tap on the card opens the tree's panel, nothing bought", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		local c = x and Creatures.byId[x.sp]
		H.expect(#prof.pals == n0 + 1 and prof.stats.taken == 2 and paid(sh1, -pick.cost, t1, rate0), "tree", "Hatch in the panel hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(H.currentPanel(p) == "tree", "tree", "and the panel is there again after the hatch scene", tostring(H.currentPanel(p)))
		H.closePanel(p)
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r), "tree", "a driftling of the egg's rarity (a new island's second)", x and string.format("%s r%d", x.sp, pick.r))
		H.expect(x.home == pieceOf("nest").uid and eggOf(pick.id) == nil, "tree", "into the hut with room, the egg gone from under the tree", tostring(x.home))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
		H.expect(#hatched == 1 and type(data) == "table" and data.egg == pick.id and data.id == x.id and data.r == pick.r and data.hr == pick.r and data.cost == pick.cost and data.sold == 0 and data.swapped == 0, "tree", "the client hears of it (Fx hatched: the egg, what hatched, its price; the tips' second never turns rarer)", tostring(#hatched))
		local function onCard(id)
			local cd = p.PlayerGui:FindFirstChild("TreeCard", true)
			return cd ~= nil and cd:FindFirstChild("CardPrice_" .. id, true) ~= nil
		end
		E.runUntil(function()
			return not onCard(pick.id) and H.inClient(p, EggViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list) and not onCard(pick.id), "tree", "gone from the plot's Eggs attribute and from the card", tostring(plot1:GetAttribute("Eggs")))
		H.expect(H.inClient(p, EggViewP.where, s.plot, pick.id) == nil, "tree", "its egg cracks open under the tree and is gone")
		E.runUntil(function()
			return H.inClient(p, WV.ownCount) == housedN()
		end, 3, 0.25)
		H.expect(H.inClient(p, WV.ownCount) == housedN() and housedN() == 2, "tree", "what hatched walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
	end
end
-- a tap on one of the own driftlings on the island opens its details (the request of 2026-11-14, "allow players to
-- click on creatures to open up a menu seeing their details"): its name, rarity, passive and every mutation with what
-- it does (a weather's with its icon), where it works and lives, its price; Work, Move and Sell. Work's picker and
-- Move's go back to the details
do
	local x = prof.pals[#prof.pals]
	local d = x and Creatures.byId[x.sp]
	if x and d then
		local muts0 = x.muts
		-- (and a fabled one, tier 6: the request of 2026-11-20, "add another tier of mutations, which are the strongest
		-- and rarest")
		x.muts = { "bright2", "rainy3", "crown6" }
		H.push(p, 0.6)
		H.inClient(p, WV.holdPal, s.plot, x.id, 6)
		E.run(0.2)
		local pos = H.inClient(p, WV.palScreen, s.plot, x.id)
		H.expect(pos ~= nil, "pals", "the driftling is on the screen", tostring(pos))
		if pos then
			local key = H.inClient(p, WV.palKeyAt, pos)
			H.expect(key == s.plot .. ":p" .. x.id, "pals", "the pick finds it under the tap (its box on the screen)", tostring(key))
			H.inClient(p, WV.tapScreen, pos)
			E.run(0.4)
			local panel = p.PlayerGui:FindFirstChild("Panel_pal", true)
			local function label(name)
				local l = panel and panel:FindFirstChild(name, true)
				return if l and l:IsA("TextLabel") then l.Text else nil
			end
			local rar = Traits.RARITY[d.rarity]
			H.expect(H.currentPanel(p) == "pal" and label("Name") == d.name, "pals", "a tap on it opens its details, its name at the top", string.format("%s %s", tostring(H.currentPanel(p)), tostring(label("Name"))))
			H.expect(label("Rarity") == rar.name .. " " .. string.rep("*", d.rarity) and label("Passive") == d.passive.name, "pals", "its rarity with its stars, its passive", string.format("%s / %s", tostring(label("Rarity")), tostring(label("Passive"))))
			local sw, rn = Traits.byId.bright2, Traits.byId.rainy3
			-- (the request of 2026-11-14: "the * in mutations should be replaced with small star sprites to show the
			-- rarity of mutations": the name alone in the label, one star sprite a tier after it)
			local function stars(name)
				local l = panel and panel:FindFirstChild(name, true)
				return H.inClient(p, H.cmod(p, "UI.TierStars").shown, l)
			end
			H.expect(label("Mut_bright2") == sw.name and stars("Mut_bright2") == sw.tier and label("MutFx_bright2") == sw.blurb and label("Mut_rainy3") == rn.name and stars("Mut_rainy3") == rn.tier and label("MutFx_rainy3") == rn.blurb, "pals", "every mutation with its star sprites and what it does", string.format("%s %d / %s %d", tostring(label("Mut_bright2")), stars("Mut_bright2"), tostring(label("Mut_rainy3")), stars("Mut_rainy3")))
			local cr = Traits.byId.crown6
			H.expect(cr ~= nil and cr.tier == 6 and label("Mut_crown6") == cr.name and stars("Mut_crown6") == 6 and label("MutFx_crown6") == cr.blurb, "pals", "a fabled mutation with its six star sprites and what it does", string.format("%s %d %s", tostring(label("Mut_crown6")), stars("Mut_crown6"), tostring(label("MutFx_crown6"))))
			H.expect(panel ~= nil and panel:FindFirstChild("MutIcon_rainy3", true) ~= nil and panel:FindFirstChild("MutIcon_bright2", true) == nil, "pals", "a weather's mutation with that weather's icon")
			local work = x.work ~= 0 and Buildings.byId[(function()
				for _, q in prof.plot.placed do
					if q.uid == x.work then
						return q.id
					end
				end
				return ""
			end)()]
			local where = panel and panel:FindFirstChild("Where", true)
			local whereTop = where and where:FindFirstChild("Top")
			H.expect(work and whereTop and whereTop.Text == "Works at the " .. work.name, "pals", "where it works", whereTop and whereTop.Text)
			local priceRow = panel and panel:FindFirstChild("Price", true)
			local priceTop = priceRow and priceRow:FindFirstChild("Top")
			H.expect(priceTop and priceTop.Text == string.format("Sells for %s coins", Numbers.coins(TreeL.price(x))), "pals", "what it sells for, in coins", priceTop and priceTop.Text)
			H.expect(H.buttonNamed(p, "PalWork") ~= nil and H.buttonNamed(p, "PalMove") ~= nil and H.buttonNamed(p, "PalSell") ~= nil and label("ReadOnly") == nil, "pals", "its own: Work, Move and Sell")
			H.clickNamed(p, "PalWork", { wait = 0.3 })
			H.expect(H.currentPanel(p) == "pals" and H.buttonNamed(p, "Go_0", true) ~= nil, "pals", "Work opens the work picker", tostring(H.currentPanel(p)))
			H.clickNamed(p, "Back", { wait = 0.3 })
			H.expect(H.currentPanel(p) == "pal", "pals", "its Back goes back to the details", tostring(H.currentPanel(p)))
			H.clickNamed(p, "PalMove", { wait = 0.3 })
			H.expect(H.currentPanel(p) == "pals" and p.PlayerGui:FindFirstChild("Hut_" .. x.home, true) ~= nil, "pals", "Move opens the hut picker", tostring(H.currentPanel(p)))
			H.clickNamed(p, "Back", { wait = 0.3 })
			H.expect(H.currentPanel(p) == "pal", "pals", "and its Back goes back to the details too", tostring(H.currentPanel(p)))
			H.closePanel(p)
		end
		x.muts = muts0
		H.push(p, 0.4)
	end
end
-- the tree's panel from the card's Open: how often it lays and the time to the next lot with its bar, how many eggs a
-- lot and the huts' room, the odds, and under the tree every egg with Hatch, the rarest first
H.clickNamed(p, "TreeOpen", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "tree", "Open on the tree's card opens the tree's panel", tostring(H.currentPanel(p)))
local function panelRows()
	local pg = p.PlayerGui
	local v1 = H.view(p)
	local rows, all = 0, 0
	for _, e in v1.clutch do
		local f = pg:FindFirstChild("Egg_" .. e.id, true)
		local name = f and f:FindFirstChild("Name")
		local b = H.buttonNamed(p, "PanelHatch_" .. e.id, true)
		if f and name and name.Text == Traits.RARITY[e.r].name and b and table.find(H.textsOf(b), Numbers.coins(e.cost)) then
			rows += 1
		end
	end
	for _, x in pg:GetDescendants() do
		if string.sub(x.Name, 1, 4) == "Egg_" then
			all += 1
		end
	end
	return rows, all, #v1.clutch
end
do
	local pg = p.PlayerGui
	local v1 = H.view(p)
	local pace = pg:FindFirstChild("Pace", true)
	local body = pace and pace.Parent
	local nxt = body and body:FindFirstChild("Next")
	local room = body and body:FindFirstChild("Room")
	H.expect(pace ~= nil and pace.Text == "New eggs every " .. clockOf(v1.clutchSecs) and v1.clutchSecs == TreeL.secs(prof), "tree", "how often it lays", pace and pace.Text)
	local left = H.inClient(p, SCp.clutchLeft)
	H.expect(nxt ~= nil and nxt.Text == "Next in " .. clockOf(left) and body:FindFirstChild("TreeBar") ~= nil, "tree", "the time to the next lot and its bar", nxt and nxt.Text)
	H.expect(room ~= nil and room.Text == string.format("%d eggs a lot. In huts %d/%d", TreeL.count(prof.tier), housedN(), v1.nests), "tree", "how many eggs a lot and the huts' room", room and room.Text)
	local odds = 0
	for k = 1, 5 do
		local o = body and body:FindFirstChild("Odds_" .. k)
		if o and o.Text == Traits.RARITY[k].name then
			odds += 1
		end
	end
	H.expect(odds == 5, "tree", "the odds of each rarity", tostring(odds))
	-- (the left column scrolls since 2026-11-19: the heading is on the panel's body, its parent)
	local panelBody = if body and body.Name == "Left" then body.Parent else body
	local head = panelBody and panelBody:FindFirstChild("Eggs")
	H.expect(head ~= nil and head.Text == "Under the tree" and panelBody:FindFirstChild("Jetty") == nil, "tree", "under the tree", head and head.Text)
	local rows, all, n = panelRows()
	H.expect(n == #prof.clutch.list and rows == n and all == n, "tree", "every egg under the tree with its rarity and Hatch at its price", string.format("%d of %d, %d rows", rows, n, all))
	local card = pg:FindFirstChild("TreeCard", true)
	H.expect(card == nil or not H.guiVisible(card), "tree", "the HUD's cards step aside for the wide panel")
end
H.closePanel(p)
-- every hut full: an egg tapped under the tree opens the tree's panel; Hatch there opens the swap picker; Swap sells
-- the one picked and what hatches takes its place
do
	local e, pos = nil, nil
	E.runUntil(function()
		local v = H.view(p)
		e, pos = H.inClient(p, function()
			local pick, at2 = nil, nil
			for _, x in v.clutch do
				local at = EggViewP.where(s.plot, x.id)
				if at and (x.cost or math.huge) <= v.shells and Street.LAWN_Y - at.Y < 0.05 then
					local foot, on = PRp.project(at)
					local top = PRp.project(at + E.v3(0, 1.3, 0))
					if on and pick == nil then
						pick, at2 = x, E.v2(foot.X, (foot.Y + top.Y) / 2 - E.inset)
					end
				end
			end
			return pick, at2
		end)
		return e ~= nil
	end, 3, 0.1)
	H.expect(e ~= nil, "tree", "an egg in view under the tree the shells cover")
	if e then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.inClient(p, WVp.tapScreen, pos)
		E.run(0.5)
		H.expect(H.currentPanel(p) == "tree" and #prof.pals == n0, "tree", "a tap on the egg opens the tree's panel", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0 and eggOf(e.id) ~= nil, "tree", "every hut full: Hatch hatches nothing yet", string.format("%d driftlings", #prof.pals))
		local pg = p.PlayerGui
		local rows = 0
		for _, x in prof.pals do
			if x.home ~= 0 and pg:FindFirstChild("SwapOut_" .. x.id, true) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil then
				rows += 1
			end
		end
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "Back") ~= nil and pg:FindFirstChild("Pace", true) == nil, "tree", "the tree's panel opens on the swap picker", tostring(H.currentPanel(p)))
		H.expect(rows == housedN(), "tree", "the picker lists every hut driftling with Swap", string.format("%d of %d", rows, housedN()))
		local weak = weakest()
		local price = TreeL.price(weak)
		local sh1, sold0, hut, t1, rate0 = prof.shells, prof.stats.sold, weak.home, E.now(), Island.rates(prof).shells
		-- (every kind had for this one, so what hatches is no first: no "New!"; the Index put back after)
		local seen0 = table.clone(prof.seen)
		for _, cd in Creatures.list do
			prof.seen[cd.id] = 2
		end
		-- (every kind seen earns the Index's titles: given now, so their notices don't cover the hatch's)
		local titles0 = table.clone(prof.titles)
		for _, tid in { "collector", "naturalist", "archivist" } do
			prof.titles[tid] = true
		end
		local f1 = #fx
		H.clickNamed(p, "SwapTake_" .. weak.id, { wait = 0.6 })
		do
			local got = fxSince(f1, "hatched")[1]
			local gx = prof.pals[#prof.pals]
			local shownWords = {}
			for _, d in p.PlayerGui:GetDescendants() do
				if d:IsA("TextLabel") and H.guiVisible(d) and (string.find(d.Text, "New", 1, true) or string.find(d.Text, "hatched", 1, true)) then
					table.insert(shownWords, d.Text)
				end
			end
			H.expect(type(got) == "table" and type(got.data) == "table" and got.data.new == false and statusSays("Hatched ") and not statusSays("New!"), "tree", "a kind had before: not new, no \"New!\" in the notice", string.format("%s | %s", tostring(got and got.data and got.data.new), table.concat(shownWords, " / ")))
			table.clear(prof.titles)
			for k, on in titles0 do
				prof.titles[k] = on
			end
			table.clear(prof.seen)
			for k, n in seen0 do
				prof.seen[k] = n
			end
			if gx then
				prof.seen[gx.sp] = 2
			end
		end
		local x = prof.pals[#prof.pals]
		local c = x and Creatures.byId[x.sp]
		H.expect(table.find(prof.pals, weak) == nil and prof.stats.sold == sold0 + 1 and prof.stats.taken == taken0 + 1, "tree", "Swap: the one picked is sold", string.format("sold %d, taken %d", prof.stats.sold, prof.stats.taken))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
		H.expect(c ~= nil and type(data) == "table" and data.hr >= e.r and c.rarity == hatchRarity(data.hr) and x.home == hut and #prof.pals == n0 and eggOf(e.id) == nil and paid(sh1, price - e.cost, t1, rate0), "tree", "and what hatches (of the rarity it hatched as) takes its place in the hut, paid less what the other sold for", string.format("%+.1f shells (cost %d, sold for %d)", prof.shells - sh1, e.cost, price))
		H.expect(#hatched == 1 and type(data) == "table" and data.egg == e.id and data.swapped == weak.id and data.sold == price, "tree", "the client hears of the swap (Fx hatched: the one swapped out and what it sold for)", tostring(#hatched))
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "SwapTake_" .. (prof.pals[1] and prof.pals[1].id or 0)) == nil and pg:FindFirstChild("Pace", true) ~= nil, "tree", "the panel stays open, back on the eggs", tostring(H.currentPanel(p)))
	end
	H.closePanel(p)
end
-- the panel's Hatch with every hut full opens the picker too. Then the tree lays a new lot (its time cut short on the
-- server): Tree.count new eggs, the ones left gone, the next lot Tree.secs away (Fx eggs and a whole view), and the
-- picker's egg is gone, so it gives way to the list and says so. EggView sinks the old eggs and raises the new ones
local oldEgg = nil
do
	H.openPanel(p, "tree")
	local e = cheapestEgg(function(x)
		return TreeL.cost(prof, x.r) <= prof.shells and H.buttonNamed(p, "PanelHatch_" .. x.id) ~= nil
	end)
	H.expect(e ~= nil, "tree", "an egg in the panel the shells cover")
	if e then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
		local hutPal = weakest()
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0 and H.currentPanel(p) == "tree" and hutPal ~= nil and H.buttonNamed(p, "SwapTake_" .. hutPal.id) ~= nil, "tree", "every hut full: Hatch in the panel opens the swap picker", tostring(H.currentPanel(p)))
		local old = {}
		for _, x in prof.clutch.list do
			old[x.id] = true
		end
		oldEgg = e.id
		local next0 = prof.clutch.next
		local f1 = #fx
		prof.clutch.left = 2
		E.run(1.5)
		H.expect(eggOf(e.id) ~= nil and #fxSince(f1, "eggs") == 0, "tree", "no new lot before its time")
		E.runUntil(function()
			return #fxSince(f1, "eggs") > 0
		end, 2, E.dt)
		E.run(0.3)
		local c = prof.clutch
		local fresh = #c.list == TreeL.count(prof.tier)
		for _, x in c.list do
			fresh = fresh and not old[x.id] and x.id >= next0
		end
		H.expect(fresh and c.next == next0 + #c.list, "tree", "when its time comes the tree lays a new lot: Tree.count new eggs, the ones left gone", string.format("%s (next %d)", eggsAttr(c.list), c.next))
		H.expect(math.abs(c.left - TreeL.secs(prof)) < 0.5, "tree", "the next lot Tree.secs away", string.format("%.1f of %.1f", c.left, TreeL.secs(prof)))
		local laid = fxSince(f1, "eggs")
		local vw = TreeL.view(prof)
		local same = #laid == 1 and laid[1].more == 0 and type(laid[1].laid) == "table" and #laid[1].laid == #vw
		if same then
			for i, x in vw do
				local y = laid[1].laid[i]
				same = same and type(y) == "table" and y.id == x.id and y.r == x.r and y.cost == x.cost
			end
		end
		H.expect(same, "tree", "the client hears of it (Fx eggs: the new lot with its prices)", tostring(#laid))
		H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list), "tree", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
		E.runUntil(function()
			return eggsSynced(p)
		end, 0.5)
		H.expect(eggsSynced(p), "tree", "a whole view brings the new lot to the client")
		E.run(0.3)
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "SwapTake_" .. hutPal.id) == nil and p.PlayerGui:FindFirstChild("Pace", true) ~= nil, "tree", "the picker's egg gone, it gives way to the eggs under the tree", tostring(H.currentPanel(p)))
		H.expect(statusSays("That egg is gone."), "tree", "and says the egg is gone")
		local rows, all, n = panelRows()
		H.expect(rows == n and all == n and n == #c.list, "tree", "the panel lists the new lot", string.format("%d of %d, %d rows", rows, n, all))
		E.run(1.5 + Tuning.EggShown * 0.12)
		local oldDrawn = 0
		for id in old do
			if H.inClient(p, EggViewP.where, s.plot, id) ~= nil then
				oldDrawn += 1
			end
		end
		local shownN = shownOf(c.list)
		local drawn, onRing, apart, clash = ringState(p, s.plot, shownN, treePiece())
		H.expect(oldDrawn == 0 and drawn == #shownN and H.inClient(p, EggViewP.count, s.plot) == #shownN and onRing and apart, "tree", "the old eggs sink into the lawn, the new lot's rarest dozen rise on the ring", string.format("%d old left, %d of %d new, ring %s, on one spot: %s", oldDrawn, drawn, #shownN, tostring(onRing), clash))
	end
	H.closePanel(p)
end
-- not enough shells, an egg of a lot gone, one never laid: refused, nothing changes
do
	local sh = prof.shells
	prof.shells = 0
	local e = cheapestEgg()
	local n0 = #prof.pals
	res = H.req(p, "egg.hatch", { id = e.id, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "money" and #prof.pals == n0 and eggOf(e.id) ~= nil, "tree", "not enough shells", tostring(res.err))
	-- the panel's Hatch short of shells goes to the egg for Robux instead (the request of 2026-11-18: "if the player
	-- dosent have enough shells while buying an egg, make them go to purchasing it with robux instead"); the products
	-- aren't on sale here, so it says so, and nothing hatches
	H.push(p, 0.3)
	H.openPanel(p, "tree")
	local hb = H.buttonNamed(p, "PanelHatch_" .. e.id, true)
	H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.4, optional = true })
	local said = ""
	for _, x in p.PlayerGui:GetDescendants() do
		if x:IsA("TextLabel") and string.find(x.Text, "coins", 1, true) and string.find(x.Text, "Robux", 1, true) then
			said = x.Text
		end
	end
	H.expect(#prof.pals == n0 and eggOf(e.id) ~= nil and said ~= "", "tree", "Hatch short of shells: the egg for Robux instead", string.format("%q (button %s, panel %s, view shells %s)", said, tostring(hb ~= nil), tostring(H.currentPanel(p)), tostring(H.view(p).shells)))
	H.closePanel(p)
	prof.shells = sh
	res = H.req(p, "egg.hatch", { id = oldEgg or 424242, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "not_found" and #prof.pals == n0, "tree", "an egg of the lot the new one replaced", string.format("%s (%s)", tostring(res.err), tostring(oldEgg)))
	res = H.req(p, "egg.hatch", { id = 424242, swap = 0 })
	H.expect(not res.ok and res.err == "not_found", "tree", "an egg never laid", tostring(res.err))
end
-- a tap on the own Tree of Life in the world opens its panel
do
	local n0 = #prof.pals
	E.raycastParts = true
	H.inClient(p, function()
		local pos = PRp.project(treeMiddle(s.plot, treePiece()) + E.v3(0, 2, 0))
		WVp.tapScreen(E.v2(pos.X, pos.Y - E.inset))
	end)
	E.raycastParts = nil
	E.run(0.5)
	H.expect(H.currentPanel(p) == "tree" and p.PlayerGui:FindFirstChild("Pace", true) ~= nil and H.buttonNamed(p, "Back") == nil and #prof.pals == n0, "tree", "a tap on the tree opens its panel (on its eggs, no egg hatched)", tostring(H.currentPanel(p)))
	H.closePanel(p)
end
-- the Index: every kind hatched counts
do
	local seen = 0
	for _, n in prof.seen do
		if n >= 1 then
			seen += 1
		end
	end
	H.push(p, 0.3)
	H.openPanel(p, "index")
	H.expect(statusSays(string.format("Seen %d of %d kinds", seen, #Creatures.list)), "tree", "the Index counts every kind hatched", string.format("%d seen", seen))
	H.closePanel(p)
end
H.checkProfile(p, "tree")
mirror(p, "tree")

------------------------------------------------------------------ 5. the Driftlings panel: moving, working, selling
E.phase = "pals"
-- a second hut, so there is somewhere to move one to
prof.shells = math.max(prof.shells, 200)
res = place("nest")
local hutA = pieceOf("nest")
local hutB = prof.plot.placed[#prof.plot.placed]
H.expect(res.ok and hutB.id == "nest" and hutB ~= hutA, "pals", "a second hut", tostring(res.err))
H.push(p, 0.4)
local pal = nil
for _, x in prof.pals do
	if x.home == hutA.uid and x.work ~= 0 and pal == nil then
		pal = x
	end
end
H.clickNamed(p, "Menu_pals", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "pals", "the Driftlings panel opens")
H.expect(pal ~= nil and H.buttonNamed(p, "Move_" .. pal.id) ~= nil and H.buttonNamed(p, "Help_" .. pal.id) ~= nil and H.buttonNamed(p, "Sell_" .. pal.id) ~= nil, "pals", "Move, Work and Sell on its row")
do
	local b = H.buttonNamed(p, "OpenTree")
	H.expect(b ~= nil and table.find(H.textsOf(b), "Eggs") and H.buttonNamed(p, "OpenTide", true) == nil and H.buttonNamed(p, "EquipBest", true) == nil, "pals", "Eggs beside the hint (no Tide, no Equip best)")
end
-- its mutations on its row, each by name (Data/Traits), or "No mutations"
do
	local pg = p:FindFirstChild("PlayerGui")
	local shown = 0
	for _, id in pal.muts or {} do
		if pg and pg:FindFirstChild("Mut_" .. id, true) then
			shown += 1
		end
	end
	local none = pg and pg:FindFirstChild("Muts", true)
	H.expect(if #(pal.muts or {}) > 0 then shown == #(pal.muts or {}) else none ~= nil, "pals", "its mutations on its row", string.format("%d of %d", shown, #(pal.muts or {})))
end
-- Work: the work picker (every workplace, what it would make at each a minute, and Rest); Rest, then back to work
do
	local job = pal.work
	H.clickNamed(p, "Help_" .. pal.id, { wait = 0.4 })
	H.expect(H.buttonNamed(p, "Go_0") ~= nil and H.buttonNamed(p, "Go_" .. job, true) ~= nil, "pals", "Work opens the work picker (its building, Rest)")
	local listed, n = true, 0
	for _, q in prof.plot.placed do
		if Island.works(q.id) then
			n += 1
			listed = listed and H.buttonNamed(p, "Go_" .. q.uid, true) ~= nil
		end
	end
	local speed = p.PlayerGui:FindFirstChild("Speed", true)
	H.expect(listed and n >= 3, "pals", "the work picker lists every workplace", tostring(n))
	H.expect(speed ~= nil and string.match(speed.Text, "^[%d%.]+[KMB]?/min$") ~= nil, "pals", "with what it would make at each a minute", speed and speed.Text)
	H.clickNamed(p, "Go_0", { wait = 0.5 })
	H.expect(pal.work == 0, "pals", "Rest: it stops work", tostring(pal.work))
	H.openPanel(p, "pals", { pal = pal.id })
	H.clickNamed(p, "Go_" .. job, { wait = 0.5 })
	H.expect(pal.work == job, "pals", "Go: back to work there", tostring(pal.work))
end
-- Move: the hut picker (both huts, no pen); to the empty one it goes
H.openPanel(p, "pals")
H.clickNamed(p, "Move_" .. pal.id, { wait = 0.4 })
H.expect(H.buttonNamed(p, "Move_" .. hutB.uid) ~= nil and H.buttonNamed(p, "Move_" .. hutA.uid, true) ~= nil, "pals", "the hut picker lists both huts")
H.expect(H.buttonNamed(p, "Move_0", true) == nil, "pals", "and no pen")
H.clickNamed(p, "Move_" .. hutB.uid, { wait = 0.5 })
H.expect(pal.home == hutB.uid and H.currentPanel(p) == "pals", "pals", "moved to the second hut", string.format("home %d", pal.home))
-- back in a swap: one more hatched from the tree's panel fills the first hut again, so it swaps with one living there
do
	prof.shells = math.max(prof.shells, 2000)
	H.push(p, 0.3)
	H.openPanel(p, "tree")
	local e = cheapestEgg(function(x)
		return H.buttonNamed(p, "PanelHatch_" .. x.id) ~= nil
	end)
	local n0 = #prof.pals
	if e then
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
	end
	local x = prof.pals[#prof.pals]
	H.expect(e ~= nil and #prof.pals == n0 + 1 and x.home == hutA.uid and eggOf(e.id) == nil, "pals", "one more hatched from Hatch in the tree's panel, into the first hut (the comfiest with room)", string.format("%d driftlings, home %d", #prof.pals, x.home))
	H.expect(H.currentPanel(p) == "tree" and p.PlayerGui:FindFirstChild("Pace", true) ~= nil, "pals", "(the panel stays open on the eggs)", tostring(H.currentPanel(p)))
end
H.openPanel(p, "pals", { move = pal.id })
local other = nil
for _, x in prof.pals do
	if x.home == hutA.uid and other == nil then
		other = x
	end
end
H.expect(other ~= nil and H.buttonNamed(p, "SwapWith_" .. other.id) ~= nil, "pals", "a full hut: swap with one of its driftlings")
H.clickNamed(p, "SwapWith_" .. (if other then other.id else 0), { wait = 0.5 })
H.expect(pal.home == hutA.uid and other ~= nil and other.home == hutB.uid, "pals", "swapped: it lives in the first hut again, the other in the second", string.format("%d / %s", pal.home, tostring(other and other.home)))
-- a pointer over a driftling's row: what its numbers mean (the request of 2026-11-15: "when hovering or holding onto
-- each creature, show what their mutation and stats do"); leaving the row hides it. (Its species is the one the sim
-- hatched: a passive with egg price or charm adds itself to the island line, "Its egg luck and egg price count ...".)
do
	local I = require("./inst")
	pal.muts = { "bright2", "fierce1" }
	H.push(p, 0.3)
	H.openPanel(p, "pals")
	E.run(0.3)
	local PT = H.cmod(p, "UI.PalTip")
	local rowF = p.PlayerGui:FindFirstChild("Pal_" .. pal.id, true)
	if rowF then
		I.fire(I.getSig(rowF, "MouseEnter"), 40, 40)
	end
	E.run(0.1)
	local st = H.inClient(p, PT.debugState)
	local all = table.concat(st.texts, " | ")
	local d = H.sharedServer("Data.Creatures").byId[pal.sp]
	local function has(w)
		return string.find(all, w, 1, true) ~= nil
	end
	H.expect(rowF ~= nil and st.shown and string.find(all, "Works [%a ,%d%.x]-x%d") ~= nil and has(d.passive.name .. ": ") and has("Blessed: +10% egg luck") and has("Shiny: +30% sell price") and (has("Its egg luck counts while in a hut") or string.find(all, "Its egg luck[%a ,]- count while in a hut") ~= nil) and has("Sells for "), "pals", "over a driftling's row: its tip, how fast it works, its passive and each mutation and what they do", all)
	local tipF = p.PlayerGui:FindFirstChild("PalTip", true)
	H.expect(tipF ~= nil and tipF.Visible ~= false, "pals", "(the tip's card on the Popup root)")
	if rowF then
		I.fire(I.getSig(rowF, "MouseLeave"))
	end
	E.run(0.1)
	H.expect(not H.inClient(p, PT.debugState).shown, "pals", "leaving the row hides it")
end
-- selling from the panel takes two taps
do
	local nPals, sold0, sh1, t1 = #prof.pals, prof.stats.sold, prof.shells, E.now()
	local price, rate0 = TreeL.price(pal), Island.rates(prof).shells
	H.openPanel(p, "pals")
	E.run(0.3)
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.3 })
	H.expect(#prof.pals == nPals, "pals", "one tap only asks Sure?")
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.5 })
	-- (the island earns meanwhile: its shells a second, a turn's rate over TurnSeconds, at the rate before the sale)
	local earned = earnedSince(t1, rate0)
	local got = prof.shells - sh1
	H.expect(#prof.pals == nPals - 1 and table.find(prof.pals, pal) == nil and prof.stats.sold == sold0 + 1 and got >= price - 0.5 and got <= price + earned, "pals", "the second sells it for its price", string.format("%d driftlings, %+.1f shells (price %d, the island's own %.1f at most)", #prof.pals, got, price, earned))
end
-- Eggs beside the hint opens the tree's panel
H.openPanel(p, "pals")
H.clickNamed(p, "OpenTree", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "pals", "Eggs opens the tree's panel", tostring(H.currentPanel(p)))
H.closePanel(p)
H.checkProfile(p, "pals")
mirror(p, "pals")

------------------------------------------------------------------ 6. the founder's looks
-- The My founder screen (UI/FounderUI; the request of 2026-11-20: "Port the entire character customization menu from
-- the bakery game to this game, such accessory colors and other features, along with the accessories it has"): a skin
-- picked and saved (the profile and the Founder attribute, Data/Looks.encode of the look), an apron in a colour, a free
-- hat tinted, a held piece turned, a locked piece tried on but never saved (and refused when sent by hand), an outfit
-- saved, worn and deleted, Randomise and Reset, Cancel, and a look left unsaved by the X coming back on the next opening.
E.phase = "looks"
do
	local LooksD = H.sharedServer("Data.Looks")
	local CosD = H.sharedServer("Data.Cosmetics")
	local FounderP = H.cmod(p, "UI.FounderUI")
	local function attrIsLook(label)
		H.expect(p:GetAttribute("Founder") == LooksD.encode(prof.founder), "looks", label .. ": every client sees it (the Founder attribute)", tostring(p:GetAttribute("Founder")))
	end
	local function tintOf(id)
		for i, t in LooksD.tints do
			if t.id == id then
				return i
			end
		end
		return 0
	end
	-- a skin, saved
	local skin0 = prof.founder.skin
	local skin1 = skin0 % #LooksD.skin + 1
	H.openPanel(p, "looks", "skin")
	E.run(0.4)
	H.expect(H.currentPanel(p) == "looks" and H.buttonNamed(p, "Stage", true) ~= nil and H.buttonNamed(p, "TurnLeft") ~= nil, "looks", "the screen opens with its stage and turning arrows")
	H.expect(H.buttonNamed(p, "LooksTab_titles") ~= nil and H.buttonNamed(p, "LooksTab_outfits") ~= nil and H.buttonNamed(p, "LooksTab_hand") ~= nil, "looks", "its tabs, Outfits and Titles among them")
	H.clickNamed(p, "Option_" .. skin1, { wait = 0.2 })
	H.expect(statusSays("Not saved yet"), "looks", "a change says it isn't saved yet")
	H.clickNamed(p, "TurnRight", { wait = 0.1 })
	H.clickNamed(p, "SaveLook", { wait = 0.4 })
	-- (six skins since 2026-11-14, eleven since 2026-11-20: Data/Looks)
	H.expect(prof.founder.skin == skin1, "looks", "the new skin is saved", string.format("%d -> %d", skin0, prof.founder.skin))
	attrIsLook("the new skin")
	E.run(0.8)
	H.expect(H.currentPanel(p) == nil and FounderP.working() == nil, "looks", "Save closes the screen", tostring(H.currentPanel(p)))
	-- an apron, and its colour
	H.openPanel(p, "looks", "apron")
	E.run(0.3)
	H.clickNamed(p, "Option_3", { wait = 0.1 })
	H.clickNamed(p, "Tint_sky", { wait = 0.1 })
	H.clickNamed(p, "SaveLook", { wait = 0.4 })
	H.expect(prof.founder.apron == 3 and prof.founder.apronTint == tintOf("sky"), "looks", "an apron in a colour is saved", string.format("%s %s", tostring(prof.founder.apron), tostring(prof.founder.apronTint)))
	attrIsLook("the apron")
	E.run(0.8)
	-- a free hat in blue (the bakery's own beret)
	H.openPanel(p, "looks", "hat")
	E.run(0.3)
	H.expect(H.buttonNamed(p, "ShopCell") ~= nil, "looks", "a piece tab ends with the shop's cell")
	H.clickNamed(p, "Option_beret", { wait = 0.1 })
	H.clickNamed(p, "Tint_blue", { wait = 0.1 })
	H.clickNamed(p, "SaveLook", { wait = 0.4 })
	H.expect(prof.founder.hat == "beret" and prof.founder.hatTint == tintOf("blue"), "looks", "a hat tinted blue is saved", string.format("%s %s", tostring(prof.founder.hat), tostring(prof.founder.hatTint)))
	attrIsLook("the tinted hat")
	E.run(0.8)
	-- a held piece, turned (one owned for the test)
	prof.owned.magic_wand = true
	H.push(p, 0.3)
	H.openPanel(p, "looks", "hand")
	E.run(0.3)
	H.clickNamed(p, "Option_magic_wand", { wait = 0.1 })
	H.clickNamed(p, "TurnHeld", { wait = 0.1 })
	local w = FounderP.working()
	H.expect(w ~= nil and w.hand == "magic_wand" and w.turn == 2, "looks", "Turn turns what is in the hand", w and tostring(w.turn))
	H.clickNamed(p, "SaveLook", { wait = 0.4 })
	H.expect(prof.founder.hand == "magic_wand" and prof.founder.turn == 2, "looks", "the held piece and its turn are saved", string.format("%s %s", tostring(prof.founder.hand), tostring(prof.founder.turn)))
	attrIsLook("the turned wand")
	E.run(0.8)
	-- a locked piece: tried on, never saved
	local lockedHat = nil
	for _, c in CosD.bySlot.hat do
		if not CosD.owns(prof.owned, c.id) then
			lockedHat = c.id
			break
		end
	end
	H.openPanel(p, "looks", "hat")
	E.run(0.3)
	local lockedCell = lockedHat and H.buttonNamed(p, "Option_" .. lockedHat)
	H.expect(lockedCell ~= nil and lockedCell:GetAttribute("Owned") == false and lockedCell:FindFirstChild("Lock", true) ~= nil, "looks", "a piece not owned shows, padlocked", tostring(lockedHat))
	H.clickNamed(p, "Option_" .. tostring(lockedHat), { wait = 0.1 })
	w = FounderP.working()
	H.expect(w ~= nil and w.hat == lockedHat, "looks", "a locked piece can be tried on", w and tostring(w.hat))
	local founder0 = LooksD.encode(prof.founder)
	H.clickNamed(p, "SaveLook", { wait = 0.4 })
	H.expect(LooksD.encode(prof.founder) == founder0 and prof.founder.hat == "beret", "looks", "Save never saves a piece not owned", LooksD.encode(prof.founder))
	H.expect(H.currentPanel(p) == "looks", "looks", "and the screen stays open to say so")
	local tried = table.clone(prof.founder)
	tried.hat = lockedHat
	res = H.req(p, "look.set", { look = LooksD.encode(tried) })
	H.expect(not res.ok and res.err == "locked" and prof.founder.hat == "beret", "looks", "look.set with a piece not owned is refused", tostring(res.err))
	-- Randomise wears only pieces owned; Reset takes everything off; Cancel drops it all
	H.clickNamed(p, "Randomise", { wait = 0.1 })
	w = FounderP.working()
	local onlyOwned = w ~= nil
	for _, slot in LooksD.worn do
		local id = w and w[slot]
		if type(id) == "string" and id ~= "" and not CosD.owns(prof.owned, id) then
			onlyOwned = false
		end
	end
	H.expect(onlyOwned, "looks", "Randomise wears only pieces owned", w and LooksD.encode(w))
	H.clickNamed(p, "ResetLook", { wait = 0.1 })
	w = FounderP.working()
	local bare = w ~= nil and (w.apron or 1) == 1
	for _, slot in LooksD.worn do
		if w and w[slot] ~= nil and w[slot] ~= "" then
			bare = false
		end
	end
	H.expect(bare, "looks", "Reset takes everything worn off", w and LooksD.encode(w))
	H.clickNamed(p, "CancelLook", { wait = 0.3 })
	H.expect(H.currentPanel(p) == nil and LooksD.encode(prof.founder) == founder0, "looks", "Cancel closes and saves nothing", LooksD.encode(prof.founder))
	-- an outfit: saved, worn after a change, deleted with two taps
	local n0 = #prof.outfits
	H.openPanel(p, "looks", "outfits")
	E.run(0.3)
	H.clickNamed(p, "SaveOutfit", { wait = 0.4 })
	H.expect(#prof.outfits == n0 + 1 and prof.outfits[#prof.outfits] == LooksD.encode(prof.founder), "looks", "the look on show saved as an outfit", string.format("%d -> %d", n0, #prof.outfits))
	H.clickNamed(p, "SaveOutfit", { wait = 0.3 })
	H.expect(#prof.outfits == n0 + 1, "looks", "and not twice")
	local n1 = #prof.outfits
	H.clickNamed(p, "LooksTab_skin", { wait = 0.2 })
	H.clickNamed(p, "Option_" .. skin0, { wait = 0.1 })
	H.clickNamed(p, "LooksTab_outfits", { wait = 0.2 })
	H.clickNamed(p, "Outfit_" .. n1, { wait = 0.1 })
	w = FounderP.working()
	H.expect(w ~= nil and w.skin == skin1 and w.hat == "beret", "looks", "a tap on an outfit puts it on", w and LooksD.encode(w))
	H.expect(H.buttonNamed(p, "DeleteOutfit_" .. n1) ~= nil, "looks", "the outfit worn has its X")
	H.clickNamed(p, "DeleteOutfit_" .. n1, { wait = 0.2 })
	H.expect(#prof.outfits == n1, "looks", "one tap on the X only arms it")
	H.clickNamed(p, "DeleteOutfit_" .. n1, { wait = 0.4 })
	H.expect(#prof.outfits == n1 - 1, "looks", "a second tap deletes the outfit", tostring(#prof.outfits))
	-- the X with a change unsaved: it waits for the next opening
	H.clickNamed(p, "LooksTab_skin", { wait = 0.2 })
	H.clickNamed(p, "Option_" .. skin0, { wait = 0.1 })
	H.clickNamed(p, "Close", { wait = 0.3 })
	H.expect(H.currentPanel(p) == nil and prof.founder.skin == skin1, "looks", "the X closes without saving")
	H.openPanel(p, "looks")
	E.run(0.3)
	w = FounderP.working()
	H.expect(w ~= nil and w.skin == skin0 and statusSays("Not saved yet"), "looks", "the unsaved look comes back on the next opening", w and tostring(w.skin))
	H.clickNamed(p, "CancelLook", { wait = 0.3 })
	H.openPanel(p, "looks")
	E.run(0.3)
	w = FounderP.working()
	H.expect(w ~= nil and w.skin == skin1, "looks", "and Cancel drops it for good", w and tostring(w.skin))
	H.closePanel(p)
end

------------------------------------------------------------------ 7. the other panels, settings, tips, expanding
E.phase = "panels"
local errs0 = #E.errors
for _, name in { "pals", "tree", "hatch", "index", "looks", "store" } do
	H.openPanel(p, name)
	E.run(0.3)
	H.expect(H.currentPanel(p) == name, "panels", name .. " opens")
end
H.closePanel(p)
H.openPanel(p, "tide")
H.expect(H.currentPanel(p) == nil, "panels", "no tide panel any more", tostring(H.currentPanel(p)))
H.expect(#E.errors == errs0, "panels", "no script errors in the panels", tostring(#E.errors - errs0))
res = H.req(p, "settings.set", { k = "pixel", v = "low" })
H.expect(res.ok and prof.settings.pixel == "low", "panels", "the pixel tier setting")
res = H.req(p, "settings.set", { k = "pixel", v = "ultra" })
H.expect(not res.ok and res.err == "bad_payload", "panels", "an unknown tier refused")
H.req(p, "settings.set", { k = "pixel", v = "high" })
E.run(0.4)
H.expect(H.buttonNamed(p, "TipsOk") ~= nil, "panels", "the last tip has an OK")
H.clickNamed(p, "TipsOk", { wait = 0.5 })
H.expect(prof.tut == 0 and H.buttonNamed(p, "TipsOk") == nil, "panels", "OK puts the tips away for good")
-- expanding costs shells (GAME_DESIGN 3: "make shells the main currency, allowing you to buy decor and expansions with
-- it"): short of them, refused
prof.shells = 10
res = H.req(p, "island.expand", {})
H.expect(not res.ok and res.err == "money" and prof.tier == 1, "panels", "Expand short of shells is refused", tostring(res.err))
-- expanding from the build tray: the next island was built ahead in the background, so the expansion swaps it in (no
-- ~1,200 parts made in the frame of the click), and the cheer waits for the bigger island's picture
prof.shells = Island.expandCost(1).shells + 800
H.push(p, 0.4)
local PS = H.smod("PlotService")
local guardNext = 0
while not select(2, PS.debugNext(1)) and guardNext < 40 do
	guardNext += 1
	E.run(0.25)
end
local nt, nready, swaps0 = PS.debugNext(1)
H.expect(nt == 2 and nready, "panels", "the next island is built ahead in the background", string.format("%s %s", tostring(nt), tostring(nready)))
H.clickNamed(p, "Menu_build", { wait = 0.5 })
local shellsX, tX = prof.shells, E.now()
-- (the eggs before: a bigger island lays more)
local eggs0, eggIds0, fEggs = #prof.clutch.list, {}, #fx
for _, e in prof.clutch.list do
	eggIds0[e.id] = true
end
-- Expand: the loading card comes up first, behind a bank of cloud, and the server is asked once it covers the screen;
-- the cheer comes on the bigger island once it has gone again (the request of 2026-11-20: "make a transition for
-- expansion, hiding the game with a loading transition")
local cardCtx = E.clientCtx(p)
local cardInst = E.find("ReplicatedFirst.Loading.LoadingCard")
local cardMod = cardCtx and cardInst and cardCtx.modules[cardInst]
local function cardState()
	return if cardMod then H.inClient(p, cardMod.value.state) else nil
end
local tClick = E.now()
H.clickNamed(p, "Expand", { wait = 0 })
local cs0 = cardState()
local cardGui = p.PlayerGui:FindFirstChild("LoadingCard")
local cardRoot = cardGui and cardGui:FindFirstChild("Root")
H.expect(cs0 ~= nil and cs0.up and cs0.mode == "cover" and cs0.cover == "closing" and prof.tier == 1, "panels", "Expand: the loading card comes up first, the island not grown yet", cs0 and string.format("up %s mode %s cover %s tier %d", tostring(cs0.up), tostring(cs0.mode), tostring(cs0.cover), prof.tier) or "no card")
H.expect(cardRoot ~= nil and cardRoot.BackgroundTransparency == 1 and cs0 ~= nil and cs0.clip ~= nil and cs0.clip.h == 0, "panels", "the game still shows: nothing of the card yet but what the bank has passed", cs0 and cs0.clip and string.format("clip %d+%d", cs0.clip.y, cs0.clip.h) or "?")
local sawCovered, grewHidden, coveredAt, clipFull = false, true, -1, false
E.runUntil(function()
	local st = cardState()
	if st and st.covered and not sawCovered then
		sawCovered, coveredAt = true, E.now() - tClick
		clipFull = st.clip ~= nil and st.clip.y == 0 and st.clip.h == st.size.Y
	end
	if prof.tier == 2 and not (st and st.covered) then
		grewHidden = false
	end
	return prof.tier == 2
end, 4, 0.05)
H.expect(prof.tier == 2 and sawCovered and grewHidden, "panels", "the island grows only once the card covers the screen", string.format("tier %d, covered %s at %.2f s, hidden %s", prof.tier, tostring(sawCovered), coveredAt, tostring(grewHidden)))
H.expect(clipFull and coveredAt >= 0.6 and coveredAt <= 1.2, "panels", "the bank brings it in over about 0.7 s, then all of it shows", string.format("%.2f s, clip full %s", coveredAt, tostring(clipFull)))
do
	local st = cardState()
	H.expect(st ~= nil and st.status == "Growing your island" or st ~= nil and st.status == "Drawing your island", "panels", "its words say what is happening", st and st.status or "?")
	H.expect(statusSays(H.sharedServer("Data.Office").plan(2).name) or (st ~= nil and st.fallback), "panels", "its title the island it grows into", st and tostring(st.fallback) or "?")
end
do
	local own = math.max(0, Island.rates(prof).shells) / Tuning.TurnSeconds * (E.now() - tX) * 1.5 + 2
	local moved = prof.shells - shellsX
	local cost2 = Island.expandCost(1).shells
	H.expect(moved >= -cost2 - 2 and moved <= -cost2 + own, "panels", "for its shells", string.format("shells %+.1f (cost %d)", moved, cost2))
end
local _, _, swaps1 = PS.debugNext(1)
H.expect(swaps1 == swaps0 + 1, "panels", "the expansion swaps in the island built ahead", string.format("%d -> %d", swaps0, swaps1))
local cheerAt, upAtCheer, sawOpening = -1, true, false
for _ = 1, 120 do
	E.run(0.05)
	local st = cardState()
	if st and st.cover == "opening" then
		sawOpening = true
	end
	if statusSays("Your island grew") then
		cheerAt = E.now() - tClick
		upAtCheer = st ~= nil and st.up
		break
	end
end
H.expect(cheerAt > 0 and cheerAt <= 4 and sawOpening and not upAtCheer, "panels", "the bank takes the card away, then the cheer on the bigger island", string.format("%.2f s after the click, opening seen %s, card up %s", cheerAt, tostring(sawOpening), tostring(upAtCheer)))
H.expect(p.PlayerGui:FindFirstChild("LoadingCard") == nil, "panels", "and nothing of the card left on the screen")
H.expect(statusSays("Your island grew into " .. H.sharedServer("Data.Office").plan(2).name .. "."), "panels", "and names the island it grew into (tier 2's)")
local PRx = H.cmod(p, "Pixel.PixelRenderer")
H.log("expansion: the next island was ready, swapped in; the cheer came %.2f s after the click (filter %s, bakes %d)", cheerAt, tostring(PRx.tier()), PRx.debugStatic().bakes)
E.run(0.5)
local st2 = E.workspace.Plots.Plot_1:FindFirstChild("Static")
H.expect(st2 ~= nil and st2:GetAttribute("Built") == 2, "panels", "the island is rebuilt bigger", tostring(st2 and st2:GetAttribute("Built")))
local lands = 0
for _, c in st2:GetChildren() do
	if c.Name == "Land" then
		lands += 1
	end
end
H.expect(lands == 1, "panels", "one island model after the swap", tostring(lands))
H.expect((PS.debugNext(1)) == 3, "panels", "the island after that is planned", tostring((PS.debugNext(1))))
H.clickNamed(p, "BuildDone", { wait = 0.4 })
-- a bigger island lays more eggs: the extra ones at once (Fx eggs saying how many more), the ones there kept, each
-- priced by the bigger island (EggTier); the tree's model grows to its next stage
do
	local c = prof.clutch
	local kept = true
	for id in eggIds0 do
		kept = kept and eggOf(id) ~= nil
	end
	H.expect(#c.list == TreeL.count(2) and TreeL.count(2) == Tuning.EggCount[2] and TreeL.count(2) > eggs0 and kept, "panels", "the tree lays its extra eggs at once, the ones there kept", string.format("%d -> %d of %d", eggs0, #c.list, TreeL.count(2)))
	local laid = fxSince(fEggs, "eggs")
	H.expect(#laid == 1 and laid[1].more == TreeL.count(2) - eggs0 and type(laid[1].laid) == "table" and #laid[1].laid == #c.list, "panels", "the client hears of it (Fx eggs: how many more)", string.format("%d fx, more %s", #laid, tostring(laid[1] and laid[1].more)))
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list), "panels", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local _, off = TreeL.hutFx(prof)
	local priced = true
	for _, e in H.view(p).clutch do
		priced = priced and e.cost == math.max(1, math.floor(Tuning.EggPrice[e.r] * Tuning.EggTier[2] * (1 - off) + 0.5))
	end
	H.expect(priced, "panels", "each egg priced by the bigger island (EggPrice x EggTier[2])")
	local q = treePiece()
	local model = treeModel(s.plot)
	H.expect(TreeL.stage(2) == Tuning.TreeStage[2] and model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, TreeL.stage(2)), "panels", "the tree's model at its next stage", model and model.Name)
	local shownX = shownOf(c.list)
	E.runUntil(function()
		return H.inClient(p, EggViewP.count, s.plot) == #shownX
	end, 2, 0.1)
	E.run(1.5)
	local drawn, onRing, apart, clash = ringState(p, s.plot, shownX, q)
	H.expect(drawn == #shownX and onRing and apart, "panels", "EggView lays the bigger lot's rarest dozen on the ring, each on its own spot", string.format("%d of %d, ring %s, on one spot: %s", drawn, #shownX, tostring(onRing), clash))
end
-- the housing limit by the island's tier (Tuning.HousingLimit; GAME_DESIGN 4; the request of 2026-11-14: "instead of a
-- hut (building) limit per expansion, make it such that the limit of driftling housing is the limit, such that you can
-- have 2 driftling huts in the place of a cozy burrow at the cost of comfort"): small huts up to its room, one more
-- refused (huts); in Build mode the Huts tab counts the room out of the limit and the hut cards say No room, while the
-- other tabs' count leaves the Tree of Life out; a bigger hut can't replace a small one at the limit, but two small ones
-- make way for it. The huts added go again after
do
	prof.shells = math.max(prof.shells, 30000)
	local most = Plot.housingLimit(prof.tier)
	local nest = Buildings.byId.nest.slots
	local added = {}
	local placedOk = most == Tuning.HousingLimit[2] and Plot.housing(prof.plot.placed) + nest <= most
	while placedOk and Plot.housing(prof.plot.placed) + nest <= most do
		res = place("nest")
		placedOk = res.ok
		if res.ok then
			table.insert(added, prof.plot.placed[#prof.plot.placed].uid)
		end
	end
	local room = Plot.housing(prof.plot.placed)
	H.expect(placedOk and room > most - nest and room <= most, "panels", "small huts up to the island's room (HousingLimit by its tier)", string.format("%d of %d", room, most))
	local n0 = #prof.plot.placed
	res = place("nest")
	H.expect(not res.ok and res.err == "huts" and #prof.plot.placed == n0, "panels", "one hut past the room is refused (huts)", tostring(res.err))
	H.push(p, 0.3)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_nest", { wait = 0.3 })
	local count = p.PlayerGui:FindFirstChild("Count", true)
	H.expect(count ~= nil and count.Text == string.format("%d/%d", room, most), "panels", "the Huts tab counts the room out of the limit", count and count.Text)
	local card = H.buttonNamed(p, "Buy_burrow", true)
	H.expect(card ~= nil and table.find(H.textsOf(card), "Full") ~= nil, "panels", "the burrow's card says Full", card and table.concat(H.textsOf(card), "/"))
	H.clickNamed(p, "Buy_burrow", { includeDisabled = true, wait = 0.3 })
	H.expect(H.buttonNamed(p, "Place", true) == nil and statusSays("No more hut room"), "panels", "a tap on it picks nothing up and says why")
	H.clickNamed(p, "Tab_decor", { wait = 0.3 })
	count = p.PlayerGui:FindFirstChild("Count", true)
	local pieces = 0
	for _, q in prof.plot.placed do
		if Plot.group(q.id) == "piece" then
			pieces += 1
		end
	end
	H.expect(count ~= nil and pieces == #prof.plot.placed - 1 and count.Text == string.format("%d/%d", pieces, Plot.limit(prof.tier)), "panels", "the Decor tab counts the pieces, the tree left out", count and count.Text)
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	local function indexOf(uid)
		for i, q in prof.plot.placed do
			if q.uid == uid then
				return i
			end
		end
		return 0
	end
	local swap = Buildings.byId.burrow.slots // nest
	if #added >= swap then
		res = H.req(p, "plot.replace", { i = indexOf(added[1]), id = "burrow" })
		H.expect(not res.ok and res.err == "huts", "panels", "at the limit a bigger hut can't replace a small one (huts)", tostring(res.err))
		-- small huts make way for a burrow (four of them since 2026-11-19, when a burrow grew to 8): the same room, with
		-- comfort
		for _ = 1, swap do
			H.req(p, "plot.store", { i = indexOf(added[#added]) })
			table.remove(added)
		end
		res = place("burrow")
		H.expect(res.ok and Plot.housing(prof.plot.placed) == room, "panels", "small huts down, a burrow up: the same room", tostring(res.err))
		if res.ok then
			table.insert(added, prof.plot.placed[#prof.plot.placed].uid)
		end
	end
	for _, uid in added do
		H.req(p, "plot.store", { i = indexOf(uid) })
	end
	H.expect(#prof.plot.placed <= n0 - #added, "panels", "(the huts added cleared away again)", string.format("%d pieces", #prof.plot.placed))
end
-- the work cap by the island's tier (Plot.workLimit: its driftling limit; GAME_DESIGN 4; the request of 2026-11-18:
-- "increase the capacity of work buildings by alot, in turn, make a cap for the amount of work spaces possible in each
-- island expansion. it should match the number of max driftlings possible for each expansion"): an orchard takes three
-- patches' driftlings, workplaces up to the cap, one more refused (work) with nothing paid; in Build mode the Work tab
-- counts the places at work out of the cap and a workplace's card says No room; a bigger workplace can't replace a
-- smaller one at the cap. The workplaces added go again after
do
	prof.shells = math.max(prof.shells, 1e6)
	local most = Plot.workLimit(prof.tier)
	local patchJobs, orchardJobs = Buildings.byId.patch.jobs, Buildings.byId.orchard.jobs
	H.expect(most == Plot.housingLimit(prof.tier) and orchardJobs == Tuning.WorkRoom[2] and orchardJobs >= 3 * patchJobs, "panels", "the work cap is the island's driftling limit; an orchard takes three patches' driftlings", string.format("cap %d, orchard %d, patch %d", most, orchardJobs, patchJobs))
	local added = {}
	local placedOk = Plot.work(prof.plot.placed) + patchJobs <= most
	while placedOk and Plot.work(prof.plot.placed) + patchJobs <= most do
		res = place(if Plot.work(prof.plot.placed) + orchardJobs <= most then "orchard" else "patch")
		placedOk = res.ok
		if res.ok then
			table.insert(added, prof.plot.placed[#prof.plot.placed].uid)
		end
	end
	H.expect(placedOk and Plot.work(prof.plot.placed) == most, "panels", "workplaces up to the cap", string.format("%d of %d places (%s)", Plot.work(prof.plot.placed), most, tostring(res.err)))
	local n0, shells0 = #prof.plot.placed, prof.shells
	res = place("lumber")
	H.expect(not res.ok and res.err == "work" and #prof.plot.placed == n0 and prof.shells >= shells0, "panels", "one workplace past the cap is refused (work), nothing paid", tostring(res.err))
	res = place("nest")
	if res.ok then
		table.insert(added, prof.plot.placed[#prof.plot.placed].uid)
	end
	H.expect(res.ok or res.err == "huts", "panels", "huts and decor still go up", tostring(res.err))
	H.push(p, 0.3)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_work", { wait = 0.3 })
	H.clickNamed(p, "Chip_work", { wait = 0.25 })
	local count = p.PlayerGui:FindFirstChild("Count", true)
	H.expect(count ~= nil and count.Text == string.format("%d/%d", most, most), "panels", "the Work tab counts the places at work out of the cap", count and count.Text)
	local card = H.buttonNamed(p, "Buy_orchard", true)
	H.expect(card ~= nil and table.find(H.textsOf(card), "Full") ~= nil, "panels", "the orchard's card says Full", card and table.concat(H.textsOf(card), "/"))
	H.clickNamed(p, "Buy_orchard", { includeDisabled = true, wait = 0.3 })
	H.expect(H.buttonNamed(p, "Place", true) == nil and statusSays("No more work spots"), "panels", "a tap on it picks nothing up and says why")
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	local function indexOf(uid)
		for i, q in prof.plot.placed do
			if q.uid == uid then
				return i
			end
		end
		return 0
	end
	local patchAt = 0
	for _, uid in added do
		local q = prof.plot.placed[indexOf(uid)]
		if q and q.id == "patch" then
			patchAt = indexOf(uid)
		end
	end
	if patchAt > 0 then
		res = H.req(p, "plot.replace", { i = patchAt, id = "orchard" })
		H.expect(not res.ok and res.err == "work", "panels", "at the cap a bigger workplace can't replace a smaller one (work)", tostring(res.err))
	end
	-- (put away and sold, so the inventory is as it was)
	local stored: { [string]: number } = {}
	for k = #added, 1, -1 do
		local q = prof.plot.placed[indexOf(added[k])]
		if q then
			stored[q.id] = (stored[q.id] or 0) + 1
			H.req(p, "plot.store", { i = indexOf(added[k]) })
		end
	end
	for id, n in stored do
		H.req(p, "inv.sell", { id = id, n = n })
	end
	H.expect(Plot.work(prof.plot.placed) < most, "panels", "(the workplaces added cleared away again)", string.format("%d places", Plot.work(prof.plot.placed)))
end
H.checkProfile(p, "panels")
mirror(p, "panels")

------------------------------------------------------------------ 7b. the build catalog (GAME_DESIGN 4)
-- "Make much, much more building options, like paths and fences. Polish the build ui more, just like the bakery game,
-- and reference bloxburg. Also, add effects and polish when putting down decor and other amenities." The tray: its
-- tabs and their icons, each tab's row of chips, the cards (cheapest first, the locked ones after with their level),
-- a card's tooltip, the search box, the count on each tab. Then fences drawn through the UI (a line, a box, one fence
-- over another, Erase), a river two tiles wide with a bridge over it and lily pads on it, decor put down with its
-- effects, Copy, Replace within the row, and the keys R and Esc
E.phase = "tray"
local TrayCheck = {}
do
	local PixelSpritesP = H.cmod(p, "UI.PixelSprites")
	local TABS = { "work", "nest", "path", "fence", "water", "nature", "decor", "fun" }
	local ROWS: { [string]: { string } } = {
		work = { "work", "gen" },
		water = { "tiles", "bridge", "float" },
		nature = { "trees", "plants", "rocks" },
		decor = { "beach", "garden", "farm", "harbour", "town", "jungle", "frost", "autumn", "desert", "fairy", "zen", "volcano", "grand" },
		fun = { "seats", "lights", "play", "treats", "fountains" },
	}
	-- every piece but the tree is on one of the tabs, in one of its rows
	local stray = {}
	for _, d in Buildings.list do
		if d.kind ~= "tree" and (not table.find(TABS, d.tab) or (ROWS[d.tab] ~= nil and not table.find(ROWS[d.tab], d.sub))) then
			table.insert(stray, d.id .. "@" .. d.tab .. "/" .. d.sub)
		end
	end
	H.expect(#stray == 0 and #ROWS.decor == 13, "tray", "every piece sits on a tab and one of its rows (Decor's 13 themes)", table.concat(stray, " "))
	-- the cards in the tray now, in their order: each with its id and its corner label (a level, No room, or nil)
	local function trayCards()
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local list = tray and tray:FindFirstChild("Cards", true)
		local out = {}
		for _, c in (list and list:GetChildren() or {}) do
			local id = string.match(c.Name, "^Card_(.+)$")
			if id then
				local lock = c:FindFirstChild("Lock", true)
				table.insert(out, { id = id, order = c.LayoutOrder, lock = lock and lock.Text })
			end
		end
		table.sort(out, function(a, b)
			return a.order < b.order
		end)
		return out
	end
	TrayCheck.cards = trayCards
	-- what's wrong with the cards shown for a tab's row ("" all): not the row's pieces, or not cheapest first with the
	-- locked ones after (by the level they open at, each saying "Lv<n>")
	local function cardProblems(tabKey, row)
		local shown = trayCards()
		local bad = {}
		local want = {}
		for _, d in Buildings.list do
			if d.kind ~= "tree" and d.tab == tabKey and (row == "" or d.sub == row) then
				want[d.id] = true
			end
		end
		local n = 0
		for _ in want do
			n += 1
		end
		if #shown ~= n then
			table.insert(bad, string.format("%d cards of %d", #shown, n))
		end
		local lastWood, lastTier, sawLocked = -1, 0, false
		for _, c in shown do
			local d = Buildings.byId[c.id]
			if not want[c.id] or d == nil then
				table.insert(bad, "stray " .. c.id)
				continue
			end
			if d.tier > prof.tier then
				if c.lock ~= "Lv" .. d.tier then
					table.insert(bad, string.format("%s says %s", c.id, tostring(c.lock)))
				end
				if d.tier < lastTier then
					table.insert(bad, "level order at " .. c.id)
				end
				sawLocked, lastTier = true, d.tier
			else
				if sawLocked then
					table.insert(bad, "open after a locked one: " .. c.id)
				end
				if c.lock ~= nil and c.lock ~= "Full" then
					table.insert(bad, string.format("%s says %s", c.id, tostring(c.lock)))
				end
				if d.shells < lastWood then
					table.insert(bad, "price order at " .. c.id)
				end
				lastWood = d.shells
			end
		end
		return bad, #shown
	end
	TrayCheck.problems = cardProblems
	-- the count a tab shows: the pieces against the piece limit, the huts against theirs, the tiles (paths and water
	-- together) and the fences against their own
	local function wantCount(tabKey)
		if tabKey == "nest" then
			return string.format("%d/%d", Plot.housing(prof.plot.placed), Plot.housingLimit(prof.tier))
		elseif tabKey == "work" then
			-- (the places at work against the work cap: the request of 2026-11-18)
			return string.format("%d/%d", Plot.work(prof.plot.placed), Plot.workLimit(prof.tier))
		end
		local group = if tabKey == "path" or tabKey == "water" then "tile" elseif tabKey == "fence" then "fence" else "piece"
		local n = 0
		for _, q in prof.plot.placed do
			if Plot.group(q.id) == group then
				n += 1
			end
		end
		return string.format("%d/%d", n, Plot.groupLimit(group, prof.tier))
	end
	TrayCheck.count = wantCount
	local function countText()
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local c = tray and tray:FindFirstChild("Count", true)
		return c and c.Text
	end
	TrayCheck.countText = countText
	prof.shells = math.max(prof.shells, 20000)
	H.push(p, 0.4)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	for _, t in TABS do
		local b = H.buttonNamed(p, "Tab_" .. t)
		local icon = b and b:FindFirstChild("Sprite_mini_" .. t, true)
		H.expect(b ~= nil and icon ~= nil and H.inClient(p, PixelSpritesP.has, "mini_" .. t), "tray", "the " .. t .. " tab with its icon", tostring(b))
		H.clickNamed(p, "Tab_" .. t, { wait = 0.25 })
		H.expect(H.inClient(p, BuildUI.debugState).tab == t, "tray", "a tap on it turns the tray to it", H.inClient(p, BuildUI.debugState).tab)
		H.expect(countText() == wantCount(t), "tray", "the " .. t .. " tab's count", string.format("%s, want %s", tostring(countText()), wantCount(t)))
		local rows = ROWS[t]
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		if rows then
			local chips = 0
			for _, x in (tray and tray:GetDescendants() or {}) do
				if string.sub(x.Name, 1, 5) == "Chip_" and x:IsA("GuiButton") then
					chips += 1
				end
			end
			H.expect(chips == #rows + 1, "tray", "the " .. t .. " tab's chips: All and one a row", string.format("%d of %d", chips, #rows + 1))
			H.clickNamed(p, "Chip_all", { wait = 0.25 })
			local bad, n = cardProblems(t, "")
			H.expect(#bad == 0 and n > 0 and H.inClient(p, BuildUI.debugState).chip == "", "tray", "All shows the whole " .. t .. " tab, cheapest first, the locked ones after", table.concat(bad, " "))
			H.log("tray: %s has %d cards in %d rows", t, n, #rows)
			for _, row in rows do
				H.clickNamed(p, "Chip_" .. row, { wait = 0.2 })
				local badR, nR = cardProblems(t, row)
				H.expect(#badR == 0 and nR > 0 and H.inClient(p, BuildUI.debugState).chip == row, "tray", string.format("the %s chip narrows the %s cards to its row", row, t), table.concat(badR, " "))
			end
			H.clickNamed(p, "Chip_all", { wait = 0.2 })
		else
			local hint = tray and tray:FindFirstChild("TabHint", true)
			local bad, n = cardProblems(t, "")
			H.expect(hint ~= nil and (tray :: Instance):FindFirstChild("Chips", true) == nil and #bad == 0 and n > 0, "tray", "the " .. t .. " tab: a hint in place of chips, every card in order", table.concat(bad, " "))
		end
	end
	-- a card's tooltip (a mouse over it): its name, what it is (its blurb, its charm, whether it goes on or over water)
	-- and, on a locked one, the level it opens at
	local function tipOf(id)
		local ok = H.inClient(p, BuildUI.debugTip, id)
		local tipF = p.PlayerGui:FindFirstChild("BuildTip", true)
		local function txt(n)
			local l = tipF and tipF:FindFirstChild(n, true)
			return l and l.Text
		end
		return ok and tipF ~= nil, txt("TipName"), txt("TipAbout"), txt("TipLocked")
	end
	H.clickNamed(p, "Tab_decor", { wait = 0.2 })
	H.clickNamed(p, "Chip_beach", { wait = 0.2 })
	do
		local d = Buildings.byId.sandcastle
		local shown, name, about, locked = tipOf("sandcastle")
		H.expect(shown and name == d.name and about ~= nil and string.find(about, "Charm +" .. math.floor(Buildings.charmOf(d, H.profile(p).tier)), 1, true) ~= nil and locked == nil, "tray", "a card's tooltip: its name and what it is, nothing locked", string.format("%s / %s / %s", tostring(name), tostring(about), tostring(locked)))
		local lg = Buildings.byId.lifeguard
		shown, name, about, locked = tipOf("lifeguard")
		H.expect(lg.tier > prof.tier and shown and name == lg.name and locked == string.format("Opens at island level %d.", lg.tier), "tray", "a locked one's says the level it opens at", string.format("%s / %s", tostring(name), tostring(locked)))
	end
	H.clickNamed(p, "Tab_water", { wait = 0.2 })
	do
		local _, name, about = tipOf("lilypads")
		H.expect(name == Buildings.byId.lilypads.name and about ~= nil and string.find(about, "Goes on water.", 1, true) ~= nil, "tray", "lily pads go on water, the tooltip says", tostring(about))
		_, name, about = tipOf("plankbridge")
		H.expect(name == Buildings.byId.plankbridge.name and about ~= nil and string.find(about, "Goes over water.", 1, true) ~= nil, "tray", "a bridge goes over it", tostring(about))
		local d = Buildings.byId.stream
		_, name, about = tipOf("stream")
		H.expect(name == d.name and about ~= nil and (d.blurb == "" or string.find(about, d.blurb, 1, true) ~= nil), "tray", "and a water tile's tooltip has its blurb", tostring(about))
	end
	-- the search box: "lantern" lists every piece with lantern in its name from every tab (the chips give way to a line
	-- saying what it found; a Carved Pumpkin isn't one); clearing it brings the tab back
	H.clickNamed(p, "Tab_decor", { wait = 0.2 })
	H.clickNamed(p, "Chip_zen", { wait = 0.2 })
	do
		local box = p.PlayerGui:FindFirstChild("BuildSearch", true)
		H.expect(box ~= nil and box:FindFirstChild("Box") ~= nil and H.guiVisible(box), "tray", "the search box")
		-- the search button by it puts the cursor in the box
		local sb = p.PlayerGui:FindFirstChild("SearchButton", true)
		local tb = if box then box:FindFirstChild("Box") else nil
		H.expect(sb ~= nil and H.guiVisible(sb), "tray", "the search button by the box")
		H.expect(H.clickNamed(p, "SearchButton", { wait = 0.2 }) and tb ~= nil and tb:IsFocused(), "tray", "the search button puts the cursor in the box")
		if tb then
			H.inClient(p, function()
				tb:ReleaseFocus()
			end)
		end
		H.inClient(p, BuildUI.debugSearch, "lantern")
		E.run(0.3)
		local got = {}
		for _, c in trayCards() do
			table.insert(got, c.id)
		end
		table.sort(got)
		local want = { "fairylantern", "icelantern", "lanternrope", "lanterntower", "paperlanterns", "stonelantern", "waterlanterns" }
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local hint = tray and tray:FindFirstChild("TabHint", true)
		local query = p.PlayerGui:FindFirstChild("Query", true)
		H.expect(table.concat(got, ",") == table.concat(want, ","), "tray", "\"lantern\" lists the lantern pieces from every tab (not the Carved Pumpkin)", table.concat(got, ","))
		H.expect(hint ~= nil and hint.Text == "Everything called \"lantern\":" and tray:FindFirstChild("Chips", true) == nil and query ~= nil and query.Text == "lantern", "tray", "the chips give way to a line saying what it found", hint and hint.Text)
		H.expect(H.clickNamed(p, "ClearSearch", { wait = 0.3 }), "tray", "the search's clear mark")
		local bad, n = cardProblems("decor", "zen")
		tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		H.expect(#bad == 0 and n > 0 and tray ~= nil and tray:FindFirstChild("Chips", true) ~= nil and tray:FindFirstChild("TabHint", true) == nil, "tray", "clearing it brings the tab and its row back", table.concat(bad, " "))
	end
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end

-- Fences drawn through Build mode's draw bar (BuildUI.debugDraw, corner to corner, as a drag along the grid lines):
-- a line goes along x then z, a box runs all the way round; each length lies on the even grid running east (rot 0) or
-- south (rot 90). One fence drawn over another swaps it (the old one into the inventory); Erase takes them down into
-- the inventory (2026-11-14: nothing paid back)
E.phase = "fences"
-- the shells moved since w1 come to `want`, give or take what the island made on its own since t1
local function woodMoved(w1, want, t1)
	local got = prof.shells - w1
	local own = math.max(0, Island.rates(prof).shells) / Tuning.TurnSeconds * (E.now() - t1) * 1.5 + 0.5
	return got >= want - 0.5 and got <= want + own, string.format("%+.1f shells (want %+d)", got, want)
end
-- how many of a piece wait in the player's inventory
local function heldNow(id)
	local inv = prof.inv or {}
	return inv[id] or 0
end
-- the fence length on edge e of the island, or nil
local function fenceOn(e)
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) and q.x == e[1] and q.z == e[2] and q.rot == e[3] then
			return q
		end
	end
	return nil
end
-- the edges of a line from corner a to corner b (along x, then z) and of the box between them
local function lineEdges(a, b)
	local out = {}
	for x = math.min(a[1], b[1]), math.max(a[1], b[1]) - 2, 2 do
		table.insert(out, { x, a[2], 0 })
	end
	for z = math.min(a[2], b[2]), math.max(a[2], b[2]) - 2, 2 do
		table.insert(out, { b[1], z, 90 })
	end
	return out
end
local function boxEdges(a, b)
	local out = {}
	for x = a[1], b[1] - 2, 2 do
		table.insert(out, { x, a[2], 0 })
		table.insert(out, { x, b[2], 0 })
	end
	for z = a[2], b[2] - 2, 2 do
		table.insert(out, { a[1], z, 90 })
		table.insert(out, { b[1], z, 90 })
	end
	return out
end
-- the even corner nearest the island's south-east (the side the camera sees) where every edge edgesAt(x, z) gives fits
local function fenceSpot(id, edgesAt)
	local pr = Street.plot(prof.tier)
	local z1, x1 = math.floor(pr.z1 / 2) * 2, math.floor(pr.x1 / 2) * 2
	for z = z1, math.floor(pr.z0), -2 do
		for x = x1, math.floor(pr.x0), -2 do
			local ok = true
			for _, e in edgesAt(x, z) do
				if not Plot.fits(prof.tier, prof.plot.placed, id, e[1], e[2], e[3]) then
					ok = false
					break
				end
			end
			if ok then
				return x, z
			end
		end
	end
	return nil, nil
end
local function plannedAll(plan, what, n)
	local k = 0
	for _, x in plan do
		if x == what then
			k += 1
		end
	end
	return k == n and #plan == n
end
local fenceBox = nil
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_fence", { wait = 0.3 })
	H.clickNamed(p, "Buy_ropefence", { wait = 0.3 })
	H.expect(H.buttonNamed(p, "DrawLine") ~= nil and H.buttonNamed(p, "DrawBox") ~= nil and H.buttonNamed(p, "DrawErase") ~= nil, "fences", "a fence picked: the draw bar (Line, Box, Erase)")
	-- a box 8 by 6 studs
	local bx, bz = fenceSpot("ropefence", function(x, z)
		return boxEdges({ x, z }, { x + 8, z + 6 })
	end)
	H.expect(bx ~= nil, "fences", "(room for a fenced box)")
	if bx then
		local a, b = { bx, bz }, { bx + 8, bz + 6 }
		fenceBox = { a, b }
		H.log("fences: a box from %d,%d to %d,%d", a[1], a[2], b[1], b[2])
		local edges = boxEdges(a, b)
		local n0, w1, t1 = #prof.plot.placed, prof.shells, E.now()
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "box")
		E.run(0.4)
		local all = true
		for _, e in edges do
			local q = fenceOn(e)
			all = all and q ~= nil and q.id == "ropefence"
		end
		H.expect(plannedAll(plan, "lay", #edges) and #edges == 14, "fences", "Box: the plan runs a length along each of the box's 14 edges", table.concat(plan, ","))
		H.expect(all and #prof.plot.placed == n0 + #edges, "fences", "and the island gets them, all the way round", string.format("%d pieces (was %d)", #prof.plot.placed, n0))
		local ok, say = woodMoved(w1, -#edges * Buildings.byId.ropefence.shells, t1)
		H.expect(ok, "fences", "paid in shells, a length at a time", say)
	end
	-- a line from one corner to another: along x, then z
	local lx, lz = fenceSpot("ropefence", function(x, z)
		return lineEdges({ x, z }, { x + 6, z + 4 })
	end)
	H.expect(lx ~= nil, "fences", "(room for a line of fence)")
	if lx then
		local a, b = { lx, lz }, { lx + 6, lz + 4 }
		local edges = lineEdges(a, b)
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "line")
		E.run(0.4)
		local all = true
		for _, e in edges do
			all = all and fenceOn(e) ~= nil
		end
		H.expect(plannedAll(plan, "lay", 5) and all, "fences", "Line: three lengths along x, then two along z", table.concat(plan, ","))
		-- every fence on the island: on the even grid, running east or south
		local off = {}
		for _, q in prof.plot.placed do
			if Plot.isFence(q.id) and (q.x % 2 ~= 0 or q.z % 2 ~= 0 or (q.rot ~= 0 and q.rot ~= 90)) then
				table.insert(off, string.format("%d,%d,%d", q.x, q.z, q.rot))
			end
		end
		H.expect(#off == 0, "fences", "every length on the even grid, turned 0 or 90", table.concat(off, " "))
		-- Erase: the line taken down, into the inventory
		local n0, w1, t1 = #prof.plot.placed, prof.shells, E.now()
		local held0 = heldNow("ropefence")
		plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "erase")
		E.run(0.4)
		local gone = true
		for _, e in edges do
			gone = gone and fenceOn(e) == nil
		end
		H.expect(plannedAll(plan, "lift", 5) and gone and #prof.plot.placed == n0 - 5, "fences", "Erase takes the line down", table.concat(plan, ","))
		local ok, say = woodMoved(w1, 0, t1)
		H.expect(ok and heldNow("ropefence") == held0 + 5, "fences", "the five lengths go into the inventory, nothing paid back", string.format("%s, %d held", say, heldNow("ropefence")))
	end
	-- one fence over another: a picket line along the box's north side swaps the rope there, the count unchanged
	if fenceBox then
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		H.clickNamed(p, "Buy_picket", { wait = 0.3 })
		local a = fenceBox[1]
		local b = { a[1] + 8, a[2] }
		local edges = lineEdges(a, b)
		local uids = {}
		for i, e in edges do
			local q = fenceOn(e)
			uids[i] = q and q.uid
		end
		local n0, w1, t1 = #prof.plot.placed, prof.shells, E.now()
		local rope0, picket0 = heldNow("ropefence"), heldNow("picket")
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "line")
		E.run(0.4)
		local swapped = true
		for i, e in edges do
			local q = fenceOn(e)
			swapped = swapped and q ~= nil and q.id == "picket" and q.uid == uids[i]
		end
		H.expect(plannedAll(plan, "swap", 4) and swapped and #prof.plot.placed == n0, "fences", "a picket fence drawn over the rope one swaps it where it runs", table.concat(plan, ","))
		local ok, say = woodMoved(w1, -math.max(0, 4 - picket0) * Buildings.byId.picket.shells, t1)
		H.expect(ok and heldNow("ropefence") == rope0 + 4, "fences", "for its price (or from the inventory), the old lengths into the inventory", string.format("%s, %d rope held", say, heldNow("ropefence")))
	end
	H.clickNamed(p, "Cancel", { wait = 0.2 })
	H.expect(TrayCheck.countText() == TrayCheck.count("fence"), "fences", "the Fences tab counts the fence lengths", string.format("%s, want %s", tostring(TrayCheck.countText()), TrayCheck.count("fence")))
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	E.run(0.3)
	local models = 0
	local decorF = static:FindFirstChild("Decor")
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) and decorF and decorF:FindFirstChild(string.format("%d:%s:%d:%d:%d:1", q.uid, q.id, q.x, q.z, q.rot)) then
			models += 1
		end
	end
	local fences = 0
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) then
			fences += 1
		end
	end
	H.expect(fences == 14 and models == fences, "fences", "a model for each length in Static.Decor", string.format("%d of %d", models, fences))
end
H.checkProfile(p, "fences")
mirror(p, "fences")

------------------------------------------------------------------ 7c. water
-- ("add the ability to add water to make rivers")
-- A river two tiles wide dug through the draw bar, each tile's model named with the water round it (its banks drawn
-- only where the water ends); a bridge put over it and lily pads on it as a player does (pick, tap, Place), lily pads
-- refused on the grass; a tile taken up takes the lily pads floating on it
E.phase = "water"
-- the screen point (as an InputObject's) where the pixel layer shows a world point
local function screenAt(world)
	return H.inClient(p, function()
		local pos = PRp.project(world)
		return E.v2(pos.X, pos.Y - E.inset)
	end)
end
-- a tap on the lawn over the middle of piece id's footprint at plot-local (x, z) (a touch: the ghost goes there)
local function tapFor(id, x, z, rot)
	local ox, oz = Street.origin(s.plot)
	local w, d = Plot.footprint(id, rot or 0)
	H.inClient(p, BuildUI.tapScreen, screenAt(E.v3(ox + x + w / 2, Street.LAWN_Y, oz + z + d / 2)), false)
	E.run(0.2)
end
-- the piece `id` standing at (x, z), or nil
local function pieceAt(id, x, z)
	for _, q in prof.plot.placed do
		if q.id == id and q.x == x and q.z == z then
			return q
		end
	end
	return nil
end
local function countOf(id)
	local n = 0
	for _, q in prof.plot.placed do
		if q.id == id then
			n += 1
		end
	end
	return n
end
-- what's wrong with the water tiles' models (Static.Decor "uid:id:x:z:rot:mask"): the mask 1 + north 1, east 2, south
-- 4, west 8 for each side with water next to it
local function maskProblems()
	local wet = {}
	for _, q in prof.plot.placed do
		if Plot.isWater(q.id) then
			wet[q.x .. "," .. q.z] = true
		end
	end
	local decorF = static:FindFirstChild("Decor")
	local bad, n = {}, 0
	for _, q in prof.plot.placed do
		if Plot.isWater(q.id) then
			n += 1
			local m = 1
			m += if wet[q.x .. "," .. (q.z - 2)] then 1 else 0
			m += if wet[(q.x + 2) .. "," .. q.z] then 2 else 0
			m += if wet[q.x .. "," .. (q.z + 2)] then 4 else 0
			m += if wet[(q.x - 2) .. "," .. q.z] then 8 else 0
			local name = string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, m)
			if decorF == nil or decorF:FindFirstChild(name) == nil then
				table.insert(bad, name)
			end
		end
	end
	return bad, n
end
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_water", { wait = 0.3 })
	H.clickNamed(p, "Chip_tiles", { wait = 0.2 })
	H.clickNamed(p, "Buy_stream", { wait = 0.3 })
	H.expect(H.buttonNamed(p, "DrawBox") ~= nil, "water", "a water tile picked: the draw bar")
	-- (a spot for a river five tiles long and two wide with grass at both ends of a bridge across its middle)
	local L = 5
	local function riverCells(x, z)
		local out = {}
		for j = 0, 1 do
			for i = 0, L - 1 do
				table.insert(out, { x + 2 * i, z + 2 * j })
			end
		end
		return out
	end
	local pr = Street.plot(prof.tier)
	local rx, rz = nil, nil
	for z = math.floor(pr.z1 / 2) * 2, math.floor(pr.z0), -2 do
		for x = math.floor(pr.x1 / 2) * 2, math.floor(pr.x0), -2 do
			if rx == nil and Plot.fits(prof.tier, prof.plot.placed, "plankbridge", x + 4, z - 1, 0) then
				local ok = true
				for _, c in riverCells(x, z) do
					ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stream", c[1], c[2], 0)
				end
				if ok then
					rx, rz = x, z
				end
			end
		end
	end
	H.expect(rx ~= nil, "water", "(room for a river)")
	if rx then
		H.log("water: a river from %d,%d, five tiles long and two wide", rx, rz)
		local cells = riverCells(rx, rz)
		local n0, w1, t1 = #prof.plot.placed, prof.shells, E.now()
		local plan = H.inClient(p, BuildUI.debugDraw, { { rx, rz }, { rx + 2 * (L - 1), rz + 2 } }, "box")
		E.run(0.5)
		local all = true
		for _, c in cells do
			all = all and pieceAt("stream", c[1], c[2]) ~= nil
		end
		H.expect(plannedAll(plan, "lay", 2 * L) and all and #prof.plot.placed == n0 + 2 * L, "water", "a river two tiles wide dug in one box", table.concat(plan, ","))
		local ok, say = woodMoved(w1, -2 * L * Buildings.byId.stream.shells, t1)
		H.expect(ok, "water", "paid in shells, a tile at a time", say)
		local bad, n = maskProblems()
		H.expect(n == 2 * L and #bad == 0, "water", "each tile's model in Static.Decor carries the water round it (its banks only at the river's edge)", table.concat(bad, " "))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		local tiles = TrayCheck.count("water")
		H.expect(TrayCheck.countText() == tiles and tiles == TrayCheck.count("path"), "water", "the Water tab counts the tiles", string.format("%s, want %s", tostring(TrayCheck.countText()), tiles))
		H.clickNamed(p, "Tab_path", { wait = 0.2 })
		H.expect(TrayCheck.countText() == tiles, "water", "and so does Paths: paths and water count together", tostring(TrayCheck.countText()))
		-- a bridge over it: picked, tapped where it spans the river, Place
		H.clickNamed(p, "Tab_water", { wait = 0.2 })
		H.clickNamed(p, "Chip_bridge", { wait = 0.2 })
		H.clickNamed(p, "Buy_plankbridge", { wait = 0.3 })
		local bx, bz = rx + 4, rz - 1
		tapFor("plankbridge", bx, bz)
		H.expect(H.buttonNamed(p, "Place") ~= nil, "water", "the bridge's ghost fits across the river (Place on)")
		H.clickNamed(p, "Place", { wait = 0.6 })
		local bridge = pieceAt("plankbridge", bx, bz)
		H.expect(bridge ~= nil and pieceAt("stream", bx, rz) ~= nil and pieceAt("stream", bx, rz + 2) ~= nil, "water", "Place: a plank bridge stands over the water tiles", string.format("%s at %d,%d", tostring(bridge ~= nil), bx, bz))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- lily pads: refused on the grass (the ghost red, Place off, the server says blocked), they float on the river
		H.clickNamed(p, "Chip_float", { wait = 0.2 })
		H.clickNamed(p, "Buy_lilypads", { wait = 0.3 })
		local gx, gz = spot("sandcastle", 0)
		local nPads = countOf("lilypads")
		if gx then
			tapFor("lilypads", gx, gz)
			H.expect(H.buttonNamed(p, "Place") == nil and H.buttonNamed(p, "Place", true) ~= nil, "water", "lily pads over the grass: Place is off")
			H.clickNamed(p, "Place", { includeDisabled = true, wait = 0.4 })
			H.expect(countOf("lilypads") == nPads, "water", "(a tap on it puts nothing down)")
			res = H.req(p, "plot.place", { id = "lilypads", x = gx, z = gz, rot = 0 })
			H.expect(not res.ok and res.err == "blocked" and countOf("lilypads") == nPads, "water", "the server refuses lily pads on the grass (blocked)", tostring(res.err))
		end
		tapFor("lilypads", rx, rz)
		H.expect(H.buttonNamed(p, "Place") ~= nil, "water", "over the water Place is on")
		H.clickNamed(p, "Place", { wait = 0.6 })
		local pads = pieceAt("lilypads", rx, rz)
		H.expect(pads ~= nil and countOf("lilypads") == nPads + 1, "water", "Place: lily pads float on the river")
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- Erase the tile under them: they come up with it, both into the inventory; the bridge stays
		H.clickNamed(p, "Chip_tiles", { wait = 0.2 })
		H.clickNamed(p, "Buy_stream", { wait = 0.3 })
		local w2, t2 = prof.shells, E.now()
		local stream0, pads0 = heldNow("stream"), heldNow("lilypads")
		plan = H.inClient(p, BuildUI.debugDraw, { { rx, rz } }, "erase")
		E.run(0.5)
		H.expect(plannedAll(plan, "lift", 1) and pieceAt("stream", rx, rz) == nil and countOf("lilypads") == nPads, "water", "Erase on the tile under the lily pads takes them up with it", table.concat(plan, ","))
		ok, say = woodMoved(w2, 0, t2)
		H.expect(ok and heldNow("stream") == stream0 + 1 and heldNow("lilypads") == pads0 + 1, "water", "the tile and the lily pads into the inventory, nothing paid back", string.format("%s, %d stream, %d pads held", say, heldNow("stream"), heldNow("lilypads")))
		H.expect(pieceAt("plankbridge", bx, bz) ~= nil, "water", "the bridge stays")
		bad = maskProblems()
		H.expect(#bad == 0, "water", "the tiles next to it are built again with their new banks", table.concat(bad, " "))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
	end
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end
H.checkProfile(p, "water")
mirror(p, "water")

------------------------------------------------------------------ 7d. decor put down: its effects, Copy, Replace, keys
-- ("add effects and polish when putting down decor and other amenities"). The effects draw over the pixel filter, so
-- the filter is switched on for them (the sims run the classic look otherwise: EditableImages allowed for a moment);
-- a piece put down drops in (BuildFx: a stand-in falls while the server's model is held back) and lands in a burst of
-- 1 px particles (Puffs), all gone within a second, the real model back in its place. Then a piece picked up off the
-- island: Copy puts down another, Replace offers its own row only; R turns the piece picked, Esc drops it, then leaves
E.phase = "decor"
do
	local I = require("./inst")
	local BuildFxP = H.cmod(p, "Controllers.BuildFx")
	local PuffsP = H.cmod(p, "Controllers.Puffs")
	-- a key pressed as Roblox reports it to the game (UserInputService.InputBegan, not over a text box)
	local function press(key)
		local input = I.new("InputObject")
		input.UserInputType = E.Enum.UserInputType.Keyboard
		input.KeyCode = E.Enum.KeyCode[key]
		input.UserInputState = E.Enum.UserInputState.Begin
		I.fire(I.getSig(E.services.UserInputService, "InputBegan"), input, false)
		E.flushDeferred()
		E.run(0.3)
	end
	-- the model of piece q in Static.Decor, if it is there now
	local function modelOf(q)
		local decorF = static:FindFirstChild("Decor")
		return decorF and decorF:FindFirstChild(string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl))
	end
	-- a tap on piece q in Build mode (the ray hits its model's biggest part)
	local function tapPiece(q)
		local m = modelOf(q)
		local big, vol = nil, 0
		for _, part in (m and m:GetDescendants() or {}) do
			if part:IsA("BasePart") and part.Size.X * part.Size.Y * part.Size.Z > vol then
				big, vol = part, part.Size.X * part.Size.Y * part.Size.Z
			end
		end
		if big then
			E.raycastParts = true
			H.inClient(p, BuildUI.tapScreen, screenAt(big.Position), false)
			E.raycastParts = nil
			E.run(0.3)
		end
		local what = p.PlayerGui:FindFirstChild("What", true)
		return what and what.Text
	end
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_decor", { wait = 0.3 })
	H.clickNamed(p, "Chip_beach", { wait = 0.2 })
	H.clickNamed(p, "Buy_sandcastle", { wait = 0.3 })
	local sx, sz = spot("sandcastle", 0)
	H.expect(sx ~= nil, "decor", "(room for a sandcastle)")
	tapFor("sandcastle", sx, sz)
	-- the pixel filter on (the saved tier too: the client applies the saved one whenever the state's copy changes, and a
	-- tier set here alone gave way to it at the next sync, a whole new picture baked just as the piece came down), Place
	E.editableImageMode = "ok"
	local pixel0 = prof.settings.pixel
	H.req(p, "settings.set", { k = "pixel", v = "low" })
	E.run(0.3)
	H.inClient(p, PRp.setTier, "low")
	H.expect(H.inClient(p, PRp.isActive), "decor", "(the pixel filter on for the effects)")
	-- (its first picture drawn and nothing waiting to be cast, as on an island a while after joining: a whole bake under
	-- way holds a landed stand-in up to its limit)
	local calm = 0
	local settled = E.runUntil(function()
		local st = H.inClient(p, PRp.debugStatic)
		calm = if H.inClient(p, PRp.ready) and st.shown and st.queued == 0 then calm + 1 else 0
		return calm >= 20
	end, 30, 0.05)
	H.expect(settled, "decor", "(the pixel filter's first picture drawn before the piece is put down)")
	local dyn2 = E.workspace:FindFirstChild("PixelDynamic")
	H.clickNamed(p, "Place", { wait = 0 })
	local q = nil
	local firstShow, firstPuffs, standIn, heldBack = -1, -1, false, false
	-- (every frame from the click until it is cast: the piece shows somewhere, as its ghost, its stand-in, or the real
	-- model with its rect cast (PixelRenderer.casting); the stand-in moves by world height alone, upright over its spot;
	-- no ghost over it while it drops in. The report of 2026-11-20: "when a building is placed, it seems to shift right
	-- instead of shifting down. also, they seem to vanish for awhile before appearing, especially for bigger buildings")
	local gaps, frames, ghostOver, sideways, tilted = 0, 0, 0, 0, 0
	local sx0, sz0, scr0 = nil, nil, nil
	local maxSlide = 0
	local t0 = E.now()
	for f = 1, 60 do
		E.run(0.05)
		q = q or pieceAt("sandcastle", sx, sz)
		local sh = H.inClient(p, BuildFxP.showing)
		if sh > 0 and firstShow < 0 then
			firstShow = E.now() - t0
		end
		if H.inClient(p, PuffsP.count) > 0 and firstPuffs < 0 then
			firstPuffs = E.now() - t0
		end
		local stand = dyn2 and dyn2:FindFirstChild("DropIn")
		local ghostNow = dyn2 ~= nil and dyn2:FindFirstChild("Ghost") ~= nil
		if sh > 0 then
			standIn = standIn or stand ~= nil
			heldBack = heldBack or (q ~= nil and modelOf(q) == nil)
			if ghostNow then
				ghostOver += 1
			end
		end
		if stand then
			local pv = stand:GetPivot()
			local scr = H.inClient(p, PRp.project, pv.Position)
			sx0, sz0, scr0 = sx0 or pv.Position.X, sz0 or pv.Position.Z, scr0 or scr.X
			local slide = math.max(math.abs(pv.Position.X - sx0), math.abs(pv.Position.Z - sz0))
			maxSlide = math.max(maxSlide, slide)
			if slide > 1e-3 or math.abs(scr.X - scr0) > 0.5 then
				sideways += 1
			end
			if pv.UpVector.Y < 0.999 then
				tilted += 1
			end
		end
		local real = q and modelOf(q)
		local drawn = real ~= nil and not H.inClient(p, PRp.casting, real)
		frames += 1
		-- (its ghost stands for it until the drop begins; from then on it goes with the pointer, so only the stand-in or
		-- the real one cast count)
		if not ((firstShow < 0 and ghostNow) or stand ~= nil or drawn) then
			gaps += 1
		end
		if firstShow >= 0 and sh == 0 and drawn and H.inClient(p, PuffsP.count) == 0 and f >= 16 then
			break
		end
	end
	H.expect(q ~= nil, "decor", "Place: a sandcastle on the island", tostring(q))
	H.expect(firstShow >= 0 and firstShow <= 0.3 and standIn and heldBack, "decor", "right after it's put down it drops in (BuildFx.showing, a stand-in falling, the server's model held back)", string.format("showing after %.2f s, stand-in %s, held %s", firstShow, tostring(standIn), tostring(heldBack)))
	H.expect(firstPuffs >= 0 and firstPuffs <= 0.5, "decor", "and lands in a burst of particles (Puffs.count)", string.format("puffs after %.2f s", firstPuffs))
	H.expect(sideways == 0 and tilted == 0 and sx0 ~= nil, "decor", "the stand-in drops straight down: its pivot upright over its spot, the same x and z (and the same x on screen) every frame", string.format("%d frames off its spot by up to %.3f studs, %d tilted", sideways, maxSlide, tilted))
	H.expect(gaps == 0, "decor", "the piece is on screen every frame from the click on (its ghost until the drop, then its stand-in or the real one cast)", string.format("%d of %d frames with none of them", gaps, frames))
	H.expect(ghostOver == 0, "decor", "no ghost over it while it drops in (the piece stays picked, its ghost off the spot just filled)", string.format("%d frames with a ghost", ghostOver))
	local quiet = E.runUntil(function()
		return H.inClient(p, BuildFxP.showing) == 0 and H.inClient(p, PuffsP.count) == 0
	end, 2, 0.05)
	H.expect(quiet and H.inClient(p, BuildFxP.showing) == 0 and H.inClient(p, PuffsP.count) == 0, "decor", "both back to nothing within a moment", string.format("%d showing, %d particles, %.2f s", H.inClient(p, BuildFxP.showing), H.inClient(p, PuffsP.count), E.now() - t0))
	H.expect((dyn2 == nil or dyn2:FindFirstChild("DropIn") == nil) and q ~= nil and modelOf(q) ~= nil, "decor", "the stand-in gone and the real model back in Static.Decor")
	H.log("effects: dropping %.2f s after the click, particles %.2f s, quiet %.2f s", firstShow, firstPuffs, E.now() - t0)
	-- the pointer going on to another cell while the server answers: the piece drops in where it was put down, the real
	-- one comes back into the island at once, and the ghost waits under the pointer (the report of 2026-11-20: "putting
	-- down a building/anything leaves a clone of it that lingers awhile if you drag away while doing it": the stand-in fell
	-- where the pointer had gone and stood there for its 3 s, the real one held out of the island for 5)
	do
		local ax, az = spot("sandcastle", 0)
		local bx, bz = nil, nil
		if ax then
			for _, d in { { -4, 0 }, { 0, -4 }, { -6, 0 }, { 0, -6 }, { -4, -4 } } do
				local cx, cz = ax + d[1], az + d[2]
				if Plot.fits(prof.tier, prof.plot.placed, "sandcastle", cx, cz, 0) then
					bx, bz = cx, cz
					break
				end
			end
		end
		H.expect(ax ~= nil and bx ~= nil, "decor", "(room for two more sandcastles)")
		if ax and bx then
			local ox, oz = Street.origin(s.plot)
			local w, d = Plot.footprint("sandcastle", 0)
			local at = E.v3(ox + ax + w / 2, Street.LAWN_Y, oz + az + d / 2)
			local bt = E.v3(ox + bx + w / 2, Street.LAWN_Y, oz + bz + d / 2)
			tapFor("sandcastle", ax, az)
			local bScreen = screenAt(bt)
			local orig = SCp.request
			SCp.request = function(action, payload)
				if action == "plot.place" then
					SCp.request = orig
					-- (the pointer on the other cell before the answer comes)
					BuildUI.tapScreen(bScreen, false)
				end
				return orig(action, payload)
			end
			local t1 = E.now()
			H.inClient(p, BuildUI.confirm)
			SCp.request = orig
			local qa = nil
			local offSpot, backAt, goneAt, seen = 0, -1, -1, false
			for _ = 1, 40 do
				E.run(0.05)
				qa = qa or pieceAt("sandcastle", ax, az)
				local stand = dyn2 and dyn2:FindFirstChild("DropIn")
				if stand then
					seen = true
					local pv = stand:GetPivot().Position
					if math.abs(pv.X - at.X) > 0.5 or math.abs(pv.Z - at.Z) > 0.5 then
						offSpot += 1
					end
				elseif seen and goneAt < 0 then
					goneAt = E.now() - t1
				end
				if backAt < 0 and qa and modelOf(qa) then
					backAt = E.now() - t1
				end
			end
			local ghost = dyn2 and dyn2:FindFirstChild("Ghost")
			local gp = ghost and ghost:GetPivot().Position
			H.expect(qa ~= nil and pieceAt("sandcastle", bx, bz) == nil, "decor", "the pointer moved on while the server answered: the piece goes down where it was put, not under the pointer", string.format("at %d,%d %s, at %d,%d %s", ax, az, tostring(qa ~= nil), bx, bz, tostring(pieceAt("sandcastle", bx, bz) ~= nil)))
			H.expect(seen and offSpot == 0 and goneAt > 0 and goneAt <= 1.5, "decor", "its stand-in drops on that spot and goes once the real one is drawn (no copy left under the pointer)", string.format("%d frames off the spot, gone after %.2f s", offSpot, goneAt))
			H.expect(backAt >= 0 and backAt <= 1, "decor", "the real one back in the island within a second, not held for the watch's 5 s", string.format("%.2f s", backAt))
			H.expect(gp ~= nil and math.abs(gp.X - bt.X) < 0.5 and math.abs(gp.Z - bt.Z) < 0.5, "decor", "and the ghost waits under the pointer for the next one", if gp then string.format("%.1f,%.1f against %.1f,%.1f", gp.X, gp.Z, bt.X, bt.Z) else "no ghost")
		end
	end
	-- (the classic look again, the saved tier as it was)
	H.req(p, "settings.set", { k = "pixel", v = pixel0 })
	E.run(0.3)
	H.inClient(p, PRp.setTier, "off")
	E.editableImageMode = "fail"
	H.clickNamed(p, "Cancel", { wait = 0.2 })
	-- Copy: the sandcastle tapped, Copy picks another of it; tapped elsewhere and Place puts the second down
	if q then
		local what = tapPiece(q)
		H.expect(what == "Moving: Sandcastle" and H.buttonNamed(p, "Copy") ~= nil and H.buttonNamed(p, "Replace") ~= nil and H.buttonNamed(p, "Store") ~= nil, "decor", "a tap on it picks it up: Copy, Replace, Clear away", tostring(what))
		H.clickNamed(p, "Copy", { wait = 0.3 })
		local what2 = p.PlayerGui:FindFirstChild("What", true)
		H.expect(what2 ~= nil and what2.Text == "Placing: Sandcastle" and H.buttonNamed(p, "Copy") == nil, "decor", "Copy: another sandcastle picked to place", what2 and what2.Text)
		local cx, cz = spot("sandcastle", 0)
		local n0, w1, t1 = countOf("sandcastle"), prof.shells, E.now()
		if cx then
			tapFor("sandcastle", cx, cz)
			H.clickNamed(p, "Place", { wait = 0.6 })
		end
		local copy = cx and pieceAt("sandcastle", cx, cz)
		H.expect(copy ~= nil and countOf("sandcastle") == n0 + 1 and pieceAt("sandcastle", sx, sz) == q, "decor", "Place: a second sandcastle, the first where it was", string.format("%d sandcastles", countOf("sandcastle")))
		local ok, say = woodMoved(w1, -Buildings.byId.sandcastle.shells, t1)
		H.expect(ok, "decor", "the copy paid for", say)
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- Replace: only the others of its row (the beach's, open at this level), each with its price; one taken
		if copy then
			tapPiece(copy)
			H.clickNamed(p, "Replace", { wait = 0.3 })
			local offered = {}
			local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
			for _, x in (tray and tray:GetDescendants() or {}) do
				local id = string.match(x.Name, "^Swap_(.+)$")
				if id then
					table.insert(offered, id)
				end
			end
			table.sort(offered)
			local want = {}
			for _, d in Buildings.list do
				if d.tab == "decor" and d.sub == "beach" and d.id ~= "sandcastle" and d.tier <= prof.tier then
					table.insert(want, d.id)
				end
			end
			table.sort(want)
			H.expect(#want >= 3 and table.concat(offered, ",") == table.concat(want, ","), "decor", "Replace lists the beach row's others, nothing from another row", table.concat(offered, ","))
			local uid = copy.uid
			H.clickNamed(p, "SwapTo_umbrella", { wait = 0.6 })
			local rq = pieceAt("umbrella", cx, cz)
			H.expect(rq ~= nil and rq.uid == uid and countOf("sandcastle") == n0, "decor", "a tap on one replaces it where it stands", tostring(rq and rq.uid))
		end
	end
	-- the inventory (GAME_DESIGN 4.5, 2026-11-14): a piece put away waits in the Inventory tab with how many, a catalog
	-- card for it says Free, it goes down again from there for nothing (the last one down, nothing stays picked); Quick
	-- remove (its button by the tabs) puts a tapped piece away with no menu, never the tree, and takes up the paths and
	-- the fences a drag goes over; Sell sells one for its share of the price
	do
		local function held(id)
			local inv = prof.inv or {}
			return inv[id] or 0
		end
		local um = pieceOf("umbrella")
		if H.expect(um ~= nil, "inventory", "(the umbrella to put away)") then
			local h0 = held("umbrella")
			local w1, t1 = prof.shells, E.now()
			tapPiece(um)
			H.expect(H.buttonNamed(p, "Store") ~= nil, "inventory", "a piece picked up has Put away")
			H.clickNamed(p, "Store", { wait = 0.4 })
			local ok, say = woodMoved(w1, 0, t1)
			H.expect(pieceOf("umbrella") == nil and held("umbrella") == h0 + 1 and ok, "inventory", "Put away: the umbrella into the inventory, nothing paid back", say)
			-- the catalog's card for it: Free
			H.clickNamed(p, "Tab_decor", { optional = true, wait = 0.2 })
			H.clickNamed(p, "Chip_beach", { wait = 0.2 })
			local cc = p.PlayerGui:FindFirstChild("Card_umbrella", true)
			local cl = cc and cc:FindFirstChild("Held", true)
			H.expect(cl ~= nil and string.find(cl.Text, "Free", 1, true) ~= nil, "inventory", "its catalog card says Free", cl and cl.Text)
			-- the Inventory tab: its card with how many, the row's buttons
			H.clickNamed(p, "Tab_inv", { wait = 0.3 })
			local st = H.inClient(p, BuildUI.debugState)
			local card = p.PlayerGui:FindFirstChild("InvCard_umbrella", true)
			local line = card and card:FindFirstChild("Count", true)
			H.expect(st.tab == "inv" and line ~= nil and line.Text == "x" .. held("umbrella"), "inventory", "the Inventory tab lists it with how many", line and line.Text)
			H.expect(H.buttonNamed(p, "InvSell") ~= nil and H.buttonNamed(p, "Clear_pieces") ~= nil and H.buttonNamed(p, "Clear_tiles", true) ~= nil and H.buttonNamed(p, "Clear_fences", true) ~= nil, "inventory", "its row: Sell and the three Remove all buttons")
			-- picked there and put down: free, out of the inventory, nothing left picked
			H.clickNamed(p, "Inv_umbrella", { wait = 0.3 })
			local heldLabel = p.PlayerGui:FindFirstChild("Held", true)
			H.expect(heldLabel ~= nil and string.find(heldLabel.Text, "in the inventory", 1, true) ~= nil, "inventory", "picked: the plate says how many wait, no price", heldLabel and heldLabel.Text)
			local ux, uz = spot("umbrella", 0)
			w1, t1 = prof.shells, E.now()
			if ux then
				tapFor("umbrella", ux, uz)
				H.clickNamed(p, "Place", { wait = 0.6 })
			end
			ok, say = woodMoved(w1, 0, t1)
			H.expect(ux ~= nil and pieceAt("umbrella", ux, uz) ~= nil and held("umbrella") == h0 and ok, "inventory", "an Inventory card puts it down again for nothing", say)
			H.expect(H.buttonNamed(p, "Place", true) == nil, "inventory", "the last one down: nothing stays picked")
			-- Quick remove: its bar in place of the tabs, a tap puts a piece away at once
			H.clickNamed(p, "QuickRemove", { wait = 0.3 })
			st = H.inClient(p, BuildUI.debugState)
			H.expect(st.quick and H.buttonNamed(p, "QuickStop") ~= nil and H.buttonNamed(p, "Tab_decor") == nil, "inventory", "Quick remove on: its bar in place of the tabs")
			local um2 = pieceOf("umbrella")
			w1, t1 = prof.shells, E.now()
			if um2 then
				tapPiece(um2)
			end
			ok, say = woodMoved(w1, 0, t1)
			H.expect(um2 ~= nil and pieceOf("umbrella") == nil and held("umbrella") == h0 + 1 and H.buttonNamed(p, "Store") == nil and ok, "inventory", "a tap puts the piece away at once, no menu", say)
			local tq = treePiece()
			E.raycastParts = true
			H.inClient(p, BuildUI.tapScreen, screenAt(treeMiddle(s.plot, tq) + E.v3(0, 2, 0)), false)
			E.raycastParts = nil
			E.run(0.3)
			H.expect(treePiece() == tq and held("tree") == 0, "inventory", "a tap on the tree leaves it be")
			-- a drag over paths takes them up; with Fences, a drag along the grid takes the fence up
			local pr = Street.plot(prof.tier)
			local row = nil
			for z = pr.z1 - 2 - pr.z1 % 2, pr.z0, -2 do
				for x = pr.x0 - pr.x0 % 2 + 2, pr.x1 - 6, 2 do
					if row == nil and Plot.fits(prof.tier, prof.plot.placed, "dirtpath", x, z, 0) and Plot.fits(prof.tier, prof.plot.placed, "dirtpath", x + 2, z, 0) and Plot.fits(prof.tier, prof.plot.placed, "dirtpath", x + 4, z, 0) and Plot.fits(prof.tier, prof.plot.placed, "picket", x, z, 0) and Plot.fits(prof.tier, prof.plot.placed, "picket", x + 2, z, 0) then
						row = { { x, z }, { x + 2, z }, { x + 4, z } }
					end
				end
			end
			if H.expect(row ~= nil, "inventory", "(three cells in a row for a path)") then
				local x, z = row[1][1], row[1][2]
				local rp = H.req(p, "plot.paint", { id = "dirtpath", cells = Plot.cellString(row) })
				E.run(0.3)
				local d0 = held("dirtpath")
				local plan = H.inClient(p, BuildUI.debugDraw, { row[1], row[3] }, "line")
				E.run(0.4)
				H.expect(rp.ok and plannedAll(plan, "lift", 3) and pieceAt("dirtpath", x, z) == nil and pieceAt("dirtpath", x + 4, z) == nil and held("dirtpath") == d0 + 3, "inventory", "a drag over three path tiles takes them up into the inventory", table.concat(plan, ","))
				H.clickNamed(p, "QuickFences", { wait = 0.2 })
				local rf = H.req(p, "plot.fence", { id = "picket", edges = Plot.edgeString({ { x, z, 0 }, { x + 2, z, 0 } }) })
				E.run(0.3)
				local f0 = held("picket")
				local planF = H.inClient(p, BuildUI.debugDraw, { { x, z }, { x + 4, z } }, "line")
				E.run(0.4)
				local left = 0
				for _, q in prof.plot.placed do
					if q.id == "picket" and q.z == z and (q.x == x or q.x == x + 2) and q.rot == 0 then
						left += 1
					end
				end
				H.expect(rf.ok and plannedAll(planF, "lift", 2) and left == 0 and held("picket") == f0 + 2, "inventory", "with Fences on, a drag along the grid takes the fence up", string.format("%s, fence %s", table.concat(planF, ","), tostring(rf.err)))
			end
			H.clickNamed(p, "QuickStop", { wait = 0.3 })
			st = H.inClient(p, BuildUI.debugState)
			H.expect(not st.quick and H.buttonNamed(p, "Tab_decor") ~= nil, "inventory", "Stop: the tabs back")
			-- Sell: a tap on a card sells one for its share
			H.clickNamed(p, "Tab_inv", { wait = 0.3 })
			H.clickNamed(p, "InvSell", { wait = 0.2 })
			local u0 = held("umbrella")
			w1, t1 = prof.shells, E.now()
			H.clickNamed(p, "Inv_umbrella", { wait = 0.4 })
			ok, say = woodMoved(w1, math.floor(Buildings.byId.umbrella.shells * Tuning.Refund), t1)
			H.expect(H.inClient(p, BuildUI.debugState).selling and held("umbrella") == u0 - 1 and ok, "inventory", "Sell on: a tap on a card sells one for its share of the price", say)
			H.clickNamed(p, "InvSell", { wait = 0.2 })
		end
	end
	-- the keys: R turns the piece picked a quarter, Esc drops it, a second Esc leaves Build mode
	H.clickNamed(p, "Tab_decor", { optional = true, wait = 0.2 })
	H.clickNamed(p, "Chip_garden", { wait = 0.2 })
	H.clickNamed(p, "Buy_gnome", { wait = 0.3 })
	local gx, gz = spot("gnome", 0)
	if gx then
		tapFor("gnome", gx, gz)
	end
	press("R")
	H.clickNamed(p, "Place", { wait = 0.6 })
	local g = gx and pieceAt("gnome", gx, gz)
	H.expect(g ~= nil and g.rot == 90, "decor", "R turns the piece picked a quarter before it goes down", tostring(g and g.rot))
	H.expect(H.buttonNamed(p, "Place", true) ~= nil, "decor", "(still picked for another)")
	press("Escape")
	H.expect(H.buttonNamed(p, "Place", true) == nil and H.buttonNamed(p, "Tab_decor") ~= nil and H.inClient(p, BuildUI.isOpen), "decor", "Esc drops what is picked, Build mode stays open")
	press("Escape")
	H.expect(not H.inClient(p, BuildUI.isOpen) and p.PlayerGui:FindFirstChild("BuildTray", true) == nil, "decor", "a second Esc leaves Build mode")
	if H.inClient(p, BuildUI.isOpen) then
		H.clickNamed(p, "BuildDone", { wait = 0.3 })
	end
end
H.checkProfile(p, "decor")
mirror(p, "decor")

------------------------------------------------------------------ the questline (GAME_DESIGN 9)
-- once the tips are over a card down the left names the quest on the go: Go opens the place it needs, and when its
-- goal is met Claim pays its reward and the next quest comes up; claims too early or during the tips are refused
E.phase = "quests"
local Quests = H.sharedServer("Data.Quests")
local function questAt(id)
	for i, q in Quests.list do
		if q.id == id then
			return i
		end
	end
	return 1
end
-- the first quest after the tips (the request of 2026-11-21: "the first goal after the tutorial should be "Place down 4
-- huts""): its card names it; with fewer than four huts Go opens Build mode on the Huts tab, with four Claim shows
prof.quest = 1
H.push(p, 0.5)
do
	local huts = 0
	for _, q in prof.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "nest" then
			huts += 1
		end
	end
	H.expect(Quests.list[1].id == "huts4" and statusSays("Place down 4 huts"), "quests", "the first quest's card: place down 4 huts")
	if huts < 4 then
		H.expect(H.buttonNamed(p, "QuestGo") ~= nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "fewer than four huts: Go", tostring(huts))
		H.clickNamed(p, "QuestGo", { wait = 0.4 })
		local st = H.inClient(p, BuildUI.debugState)
		H.expect(BuildUI.isOpen() and st.tab == "nest", "quests", "Go opens Build mode on the Huts tab", tostring(st.tab))
		H.clickNamed(p, "BuildDone", { wait = 0.3 })
	else
		H.expect(H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "four huts already: Claim", tostring(huts))
	end
end
prof.quest = questAt("help")
for _, x in prof.pals do
	x.work = 0
end
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestGo") ~= nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "the next quest's card: put a driftling to work, Go")
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "quests", "Go opens the Driftlings panel", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "QuestGo") == nil, "quests", "the card steps aside for the panel")
H.closePanel(p)
E.run(0.3)
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "a claim before the goal is met is refused", tostring(res.err))
-- (a driftling sent to work at another workplace, the way the Driftlings panel's Work does: any driftling works
-- anywhere)
local sent = false
for _, x in prof.pals do
	if x.home == 0 then
		continue
	end
	for _, q in prof.plot.placed do
		if not sent and q.uid ~= x.work and Island.works(q.id) then
			sent = H.req(p, "pal.work", { id = x.id, uid = q.uid }).ok
		end
	end
end
H.expect(sent, "quests", "a driftling sent to work at another workplace")
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "a driftling at work: Claim shows")
do
	local shells0 = prof.shells
	local reward = Quests.list[questAt("help")].reward
	H.clickNamed(p, "QuestClaim", { wait = 0.5 })
	H.expect(prof.quest == questAt("help") + 1 and prof.shells >= shells0 + (reward.shells or 0), "quests", "Claim pays the reward (shells) and moves on", string.format("quest %d, shells %+d", prof.quest, prof.shells - shells0))
end
-- a quest's Go naming a row ("build:work": Another workplace, "build:gen": Build a boost) opens Build mode on Work's row
-- of that name (the second camp's quest went on 2026-11-18: the first island's work spaces ran out before Another
-- farm); the first of them not met yet here (a met one shows Claim instead)
do
	local qid: string? = nil
	for _, id in { "farm", "boost" } do
		prof.quest = questAt(id)
		H.push(p, 0.5)
		if H.buttonNamed(p, "QuestGo") ~= nil then
			qid = id
			break
		end
	end
	H.expect(qid ~= nil, "quests", "the quest card of a quest building on Work's rows, with Go")
	local row = if qid then string.match(Quests.list[questAt(qid)].go, "^build:(%w+)$") else nil
	H.clickNamed(p, "QuestGo", { wait = 0.5 })
	local st = H.inClient(p, BuildUI.debugState)
	H.expect(row ~= nil and H.inClient(p, BuildUI.isOpen) and st.tab == "work" and st.chip == row, "quests", "Go on it opens Build mode on Work's row of that name", string.format("%s: %s %s", tostring(qid), tostring(st.tab), tostring(st.chip)))
	H.clickNamed(p, "BuildDone", { wait = 0.4 })
end
-- the tree's quests: "Hatch three eggs" counts the eggs hatched (two of three: Go opens the tree's panel, a claim is
-- refused; three: Claim), and sixty hatched is a long way off
do
	local taken0 = prof.stats.taken
	prof.quest = questAt("take3")
	prof.stats.taken = 2
	H.push(p, 0.5)
	H.expect(Quests.list[questAt("take3")].go == "tree" and statusSays("Hatch three eggs") and H.buttonNamed(p, "QuestGo") ~= nil, "quests", "the quest card: Hatch three eggs, with Go")
	H.clickNamed(p, "QuestGo", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "tree", "quests", "Go on a tree quest opens the tree's panel", tostring(H.currentPanel(p)))
	H.closePanel(p)
	res = H.req(p, "quest.claim", {})
	H.expect(not res.ok and res.err == "not_done", "quests", "two eggs hatched: not done", tostring(res.err))
	prof.stats.taken = taken0
	H.push(p, 0.5)
	H.expect(prof.stats.taken >= 3 and H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "three eggs hatched: Claim shows", string.format("taken %d", prof.stats.taken))
	H.clickNamed(p, "QuestClaim", { wait = 0.5 })
	H.expect(prof.quest == questAt("take3") + 1, "quests", "and Claim moves on", tostring(prof.quest))
end
prof.quest = questAt("crowd")
H.push(p, 0.5)
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "quests", "Go on sixty hatched opens the tree's panel too", tostring(H.currentPanel(p)))
H.closePanel(p)
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "sixty hatched not reached: not done", string.format("%s taken %d", tostring(res.err), prof.stats.taken))
-- a quest asking for a rarity (the request of 2026-11-14: "also, while the rare one quest is active or any rarity
-- related quests, make it such that an egg of that rarity will always spawn in the tree of life."): with none of it
-- under the tree the commonest egg turns into one within a second (the same eggs), the client hears of it and says so,
-- the view and the plot's Eggs attribute follow, and the next lot holds one too; once it's met the help stops
do
	local qid = if #TreeL.pool(prof.tier)[3] > 0 then "rare" else "uncommon"
	local want = Quests.list[questAt(qid)].goal.n
	local best0 = prof.stats.best
	prof.stats.best = want - 1
	for i, e in prof.clutch.list do
		if e.r == want or i == 1 then
			e.r = 1
		end
	end
	local ids0 = idsOf(prof.clutch.list)
	local f1 = #fx
	prof.quest = questAt(qid)
	E.run(1.4)
	local function wanted(list)
		local n = 0
		for _, e in list do
			if e.r == want then
				n += 1
			end
		end
		return n
	end
	local heard = fxSince(f1, "eggs")
	H.expect(TreeL.wanted(prof) == want and wanted(prof.clutch.list) == 1 and idsOf(prof.clutch.list) == ids0, "quests", "a quest asking for a rarity: one egg of it under the tree within a second, the same eggs", string.format("%s: %s", qid, eggsAttr(prof.clutch.list)))
	H.expect(#heard >= 1 and heard[#heard].turned == want and heard[#heard].more == 0, "quests", "the client hears of it (Fx eggs with turned)", tostring(#heard))
	local rar = Traits.RARITY[want]
	H.expect(statusSays(string.lower(rar.name) .. " egg waits at the tree."), "quests", "and a notice names it")
	local v = H.view(p)
	H.expect(v ~= nil and wanted(v.clutch) == 1, "quests", "the view has it, at its price")
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list), "quests", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
	-- the next lot holds one too
	local f2 = #fx
	prof.clutch.left = 0.05
	E.runUntil(function()
		return #fxSince(f2, "eggs") > 0
	end, 2, E.dt)
	E.run(0.3)
	H.expect(wanted(prof.clutch.list) >= 1 and #prof.clutch.list == TreeL.count(prof.tier), "quests", "a new lot while it's on: one egg of that rarity among them", eggsAttr(prof.clutch.list))
	-- the lot hatched out before the quest was met (the bug report of 2026-11-16: "there is a bug, the tree dosent have
	-- the rare egg in this quest"): nothing is left to turn, so the tree lays one within a second
	local lot0 = table.clone(prof.clutch.list)
	local next0 = prof.clutch.next
	table.clear(prof.clutch.list)
	prof.clutch.left = TreeL.secs(prof) -- (no lot due while the check runs)
	local f3 = #fx
	E.run(1.4)
	local heard3 = fxSince(f3, "eggs")
	H.expect(#prof.clutch.list == 1 and wanted(prof.clutch.list) == 1 and prof.clutch.list[1].id == next0, "quests", "an empty tree lays the quest's egg within a second", eggsAttr(prof.clutch.list))
	H.expect(#heard3 >= 1 and heard3[#heard3].turned == want, "quests", "the client hears of the laid one", tostring(#heard3))
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list), "quests", "the plot's Eggs attribute shows it", tostring(plot1:GetAttribute("Eggs")))
	table.clear(prof.clutch.list)
	for _, e in lot0 do
		table.insert(prof.clutch.list, e)
	end
	-- met: the help stops
	prof.stats.best = want
	H.expect(TreeL.wanted(prof) == 0, "quests", "met: no more help")
	prof.stats.best = best0
end
prof.quest = questAt("paths")
H.push(p, 0.5)
local paths = 0
for _, q in prof.plot.placed do
	if Plot.isPath(q.id) then
		paths += 1
	end
end
if paths < 8 then
	H.clickNamed(p, "QuestGo", { wait = 0.5 })
	H.expect(H.inClient(p, BuildUI.isOpen) and H.inClient(p, BuildUI.debugState).tab == "path", "quests", "Go opens Build mode on the Paths tab")
	H.clickNamed(p, "BuildDone", { wait = 0.4 })
end
prof.tut = Plot.TIP_WORK
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_found", "quests", "no quests while the tips are on", tostring(res.err))
prof.tut = 0
prof.quest = #Quests.list + 1
H.push(p, 0.4)
H.expect(H.buttonNamed(p, "QuestGo") == nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "every quest done: no card")
prof.quest = 2
H.push(p, 0.3)
H.checkProfile(p, "quests")
mirror(p, "quests")

------------------------------------------------------------------ 8. a malicious client
E.phase = "malicious"
local function snap()
	local q = H.profile(p)
	return { placed = #q.plot.placed, pals = #q.pals, tier = q.tier, skin = q.founder.skin, tut = q.tut, sold = q.stats.sold, taken = q.stats.taken, eggs = idsOf(q.clutch.list), eggNext = q.clutch.next }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
-- (every hut full first, so a hatch asks for a swap)
prof.shells = math.max(prof.shells, 5000)
for _ = 1, 4 do
	local e = cheapestEgg()
	if TreeL.room(prof) > 0 and e then
		H.req(p, "egg.hatch", { id = e.id, swap = 0 })
	end
end
H.expect(TreeL.room(prof) == 0 and #prof.clutch.list > 0, "malicious", "(the huts filled from the tree's eggs, some left)", string.format("room %d, %d eggs", TreeL.room(prof), #prof.clutch.list))
-- (the shells aside: every building works a little with nobody at it, so the farms and the stall go on selling;
-- they are checked apart, a jump being what a refusal let through)
prof.shells = math.max(prof.shells, 5500)
H.push(p, 0.3)
local before = snap()
local shellsBefore = prof.shells
local ok, out = H.raw(p, "shells.give", { n = 1e9 })
expectRefused("an unknown action", ok, out, "unknown_action")
ok, out = H.rawArgs(p, nil)
expectRefused("no action", ok, out, "unknown_action")
ok, out = H.raw(p, "game.make", { a = 1, b = 2, c = 3 })
expectRefused("the old studio's actions", ok, out, "unknown_action")
-- (the run's two deliberate non-finite payloads: the engine lists them apart)
ok, out = H.raw(p, "pal.work", { id = 0 / 0, uid = 1 })
expectRefused("NaN", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = math.huge, uid = 0, swap = 0 })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = string.rep("a", 100000), x = 0, z = 0, rot = 0 })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "island.expand", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "island.expand", "x")
expectRefused("a string payload", ok, out, "bad_payload")
for _, old in { "exp.start", "exp.next", "exp.snack", "exp.skill", "exp.flee", "exp.pause", "exp.home", "pouch.upgrade", "pal.release", "boat.upgrade" } do
	ok, out = H.raw(p, old, {})
	expectRefused("the expeditions' " .. old .. " (gone)", ok, out, "unknown_action")
end
for _, old in { "folk.work", "folk.dismiss" } do
	ok, out = H.raw(p, old, { id = 1, uid = 0 })
	expectRefused("the villagers' " .. old .. " (gone)", ok, out, "unknown_action")
end
-- the old pen's and tree levels' actions, and the tide's (all gone)
ok, out = H.raw(p, "pen.sell", { r = 1 })
expectRefused("the pen's pen.sell (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "pen.best", {})
expectRefused("the pen's pen.best (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "tree.upgrade", { what = "speed" })
expectRefused("the tree's tree.upgrade (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "tide.take", { id = 1, swap = 0 })
expectRefused("the tide's tide.take (gone)", ok, out, "unknown_action")
-- the eggs': bad payloads, an egg not there, a swap that isn't in a hut, every hut full and no swap
ok, out = H.raw(p, "egg.hatch", { id = "1", swap = 0 })
expectRefused("an egg id that isn't a number", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = -1, swap = 0 })
expectRefused("a negative egg id", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1.5, swap = 0 })
expectRefused("an egg id with a fraction", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1 })
expectRefused("a hatch without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1, swap = 0, n = 5 })
expectRefused("a hatch with an extra field", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 424242, swap = 0 })
expectRefused("an egg that isn't under the tree", ok, out, "not_found")
do
	-- (every hut full, so a swap is asked for: one that lives nowhere is no swap)
	local e = cheapestEgg()
	if H.expect(TreeL.room(prof) == 0 and e ~= nil and TreeL.cost(prof, e.r) <= prof.shells, "malicious", "(every hut full, an egg the shells cover)") then
		ok, out = H.raw(p, "egg.hatch", { id = e.id, swap = 424242 })
		expectRefused("a swap that isn't one of theirs", ok, out, "bad_payload")
		ok, out = H.raw(p, "egg.hatch", { id = e.id, swap = 0 })
		expectRefused("every hut full and no swap", ok, out, "full")
	end
end
ok, out = H.raw(p, "pal.house", { id = 424242, uid = 0, swap = 0 })
expectRefused("a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = pieceOf("lumber").uid, swap = 0 })
expectRefused("a lumber camp is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = treePiece().uid, swap = 0 })
expectRefused("the Tree of Life is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0, swap = 0 })
expectRefused("moving out of every hut (no pen)", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0 })
expectRefused("a move without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.sell", { id = 424242 })
expectRefused("selling a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "plot.store", { i = 1000 })
expectRefused("clearing away a piece that isn't there", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.store", { i = table.find(prof.plot.placed, treePiece()) })
expectRefused("clearing the Tree of Life away", ok, out, "fixed")
ok, out = H.raw(p, "plot.replace", { i = table.find(prof.plot.placed, treePiece()), id = "nest" })
expectRefused("replacing the Tree of Life", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 })
expectRefused("buying a second Tree of Life", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "cottage", x = 0, z = 0, rot = 0 })
expectRefused("a home (gone)", ok, out, "bad_payload")
-- the fences' and the tiles' payloads (plot.fence / plot.unfence / plot.unpaint): bad edges, a turn that isn't 0 or 90,
-- odd corners, more than 40 at once, the eraser's kind missing or unknown, an unknown id, a fence painted as a tile
do
	local function many(n, rot)
		local parts = {}
		for k = 0, n - 1 do
			table.insert(parts, if rot then string.format("%d,0,%d", 2 * (k % 20) - 20, rot) else string.format("%d,%d", 2 * (k % 20) - 20, 2 * (k // 20)))
		end
		return table.concat(parts, ";")
	end
	-- (a free stretch of grass by the fenced box: odd corners there, and an even edge where nothing stands)
	local fx0, fz0 = 0, 0
	if fenceBox then
		fx0, fz0 = fenceBox[1][1] + 2, fenceBox[1][2] + 2
	end
	for _, bad in { "a,b,c", "0,0", "0,0,0;;2,0,0", ";0,0,0", "0,0,0;", "9999,0,0", "0,-999,0", "0.5,0,0", "0,0,180" } do
		ok, out = H.raw(p, "plot.fence", { id = "picket", edges = bad })
		expectRefused(string.format("fence edges \"%s\"", bad), ok, out, "bad_payload")
	end
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,45", fx0, fz0) })
	expectRefused("a fence turned 45", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0;%d,%d,90", fx0 + 1, fz0 + 1, fx0 + 3, fz0 - 1) })
	expectRefused("fence lengths from odd corners (off the even grid)", ok, out, "blocked")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = many(41, 0) })
	expectRefused("41 fence lengths at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "laserfence", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence that doesn't exist", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "stream", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("water drawn as a fence", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "crystalfence", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence of a bigger island", ok, out, "locked")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", fx0, fz0), n = 1 })
	expectRefused("a fence request with an extra field", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence request without its id", ok, out, "bad_payload")
	do
		-- (through the Tree of Life in the island's middle)
		local tq = treePiece()
		local ex, ez = math.floor((tq.x + 2) / 2) * 2, math.floor((tq.z + 4) / 2) * 2
		ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", ex, ez) })
		expectRefused("a fence through the Tree of Life", ok, out, "blocked")
	end
	ok, out = H.raw(p, "plot.unfence", { edges = string.format("%d,%d,45", fx0, fz0) })
	expectRefused("taking down a fence turned 45", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = many(41, 90) })
	expectRefused("taking down 41 lengths at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = "x" })
	expectRefused("taking down bad edges", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("taking down a fence that isn't there", ok, out, "not_found")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("an eraser without its kind", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "lava" })
	expectRefused("an eraser of an unknown kind", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "fence" })
	expectRefused("an eraser of fences on the tiles' action", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = many(41), kind = "all" })
	expectRefused("erasing 41 cells at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "water" })
	expectRefused("erasing water where there's none", ok, out, "not_found")
	ok, out = H.raw(p, "plot.paint", { id = "picket", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("a fence painted as a tile", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.paint", { id = "sandcastle", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("decor painted as a tile", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.paint", { id = "icepond", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("water of a bigger island", ok, out, "locked")
	ok, out = H.raw(p, "plot.paint", { id = "stream", cells = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a cell with an edge's turn", ok, out, "bad_payload")
end
ok, out = H.raw(p, "founder.set", { skin = #H.sharedServer("Data.Looks").skin + 1, hair = 1, style = 1, shirt = 1 })
expectRefused("a skin that does not exist", ok, out, "bad_payload")
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
H.expect(math.abs(prof.shells - shellsBefore) < 50, "malicious", "and moved no shells (the island's own earnings aside)", string.format("%+.1f", prof.shells - shellsBefore))
-- a flood: 30 requests at once, the rate limit refuses most
local results = {}
H.inClient(p, function()
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	local done = 0
	for i = 1, 30 do
		E.task.spawn(function()
			results[i] = remote:InvokeServer("tut.next", {})
			done += 1
		end)
	end
	while done < 30 do
		E.task.wait(0.05)
	end
end)
local rated = 0
for _, x in results do
	if type(x) == "table" and x.err == "rate" then
		rated += 1
	end
end
H.expect(rated >= 30 - Tuning.RateLimitPerSec, "malicious", "the rate limit refuses a flood", string.format("%d of 30 refused", rated))
E.run(0.5)
H.checkProfile(p, "malicious")
mirror(p, "malicious")

------------------------------------------------------------------ 9. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets island 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their island is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own island")
H.expect(housedN() > 0 and H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount) >= housedN(), "second", "the second client draws the first island's hut driftlings", string.format("%d of %d", H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount), housedN()))
-- their own Tree of Life with its first lot (the first two cheap commons); the second client draws both islands' eggs
-- round their trees (each from its plot's Eggs attribute), and the first island's carry no price tags there
do
	local qp = sq.profile
	local qTree = treePiece(qp)
	local qc = qp.clutch
	local plot2 = E.workspace.Plots:FindFirstChild("Plot_2")
	H.expect(qTree ~= nil and #qp.plot.placed == 1 and #qc.list == TreeL.count(1) and qc.list[1].r == 1 and qc.list[2].r == 1, "second", "their own Tree of Life, its first lot laid, the first two commons", eggsAttr(qc.list))
	H.expect(plot2 ~= nil and plot2:GetAttribute("Eggs") == eggsAttr(qc.list), "second", "their plot's Eggs attribute", tostring(plot2 and plot2:GetAttribute("Eggs")))
	local EVq = H.cmod(q, "Controllers.EggView")
	local UIKitQ = H.cmod(q, "UI.UIKit")
	local sh1, sh2 = shownOf(prof.clutch.list), shownOf(qc.list)
	E.runUntil(function()
		return H.inClient(q, EVq.count, 2) == #sh2 and H.inClient(q, EVq.count, 1) == #sh1
	end, 3, 0.1)
	E.run(1.5 + Tuning.EggShown * 0.12)
	local d1, ring1, apart1, clash1 = ringState(q, 1, sh1, treePiece())
	local d2, ring2, apart2, clash2 = ringState(q, 2, sh2, qTree)
	H.expect(d1 == #sh1 and ring1 and apart1, "second", "the second client lays the first island's eggs (the rarest dozen) round its tree", string.format("%d of %d, ring %s, on one spot: %s", d1, #sh1, tostring(ring1), clash1))
	H.expect(d2 == #sh2 and ring2 and apart2, "second", "and their own round theirs", string.format("%d of %d, ring %s, on one spot: %s", d2, #sh2, tostring(ring2), clash2))
	local own = {}
	for _, e in qc.list do
		own[e.id] = true
	end
	local tags = 0
	H.inClient(q, function()
		for _, d in UIKitQ.canvas("World"):GetDescendants() do
			if string.match(d.Name, "^EggHatch_(%d+)$") then
				tags += 1
			end
		end
	end)
	H.expect(tags == 0, "second", "no egg carries a price tag on the second client, theirs or the first island's", tostring(tags))
	local _ = own
end
H.checkProfile(q, "second")
mirror(q, "second")

------------------------------------------------------------------ 10. to the last island
-- ("allow the player to expand their land even more"; the request of 2026-11-14: "allow expansion up to level 20")
-- The first island pushed to tier 19 (Farshore) as if expanded that far, then Expand from the tray to tier 20:
-- Everdrift, the last (the button says Island max after), its land reaching on north past where Driftling Haven
-- (tier 10) ended, the pieces of tiers 7 to 20 open and built up there
E.phase = "everdrift"
do
	local Office = H.sharedServer("Data.Office")
	prof.tier = 19
	Plot.refit(prof)
	PS.build(s)
	H.push(p, 0.5)
	H.expect(static:GetAttribute("Built") == 19 and Office.plan(19).name == "Farshore", "everdrift", "(the island at tier 19, Farshore)", tostring(static:GetAttribute("Built")))
	local guard = 0
	while not select(2, PS.debugNext(1)) and guard < 80 do
		guard += 1
		E.run(0.25)
	end
	local nt, nready, swaps0 = PS.debugNext(1)
	H.expect(nt == 20 and nready, "everdrift", "Everdrift is built ahead in the background", string.format("%s %s", tostring(nt), tostring(nready)))
	prof.shells = Island.expandCost(19).shells + 3000000
	H.push(p, 0.4)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_decor", { wait = 0.3 })
	H.clickNamed(p, "Chip_grand", { wait = 0.3 })
	local function lockOf(id)
		for _, c in TrayCheck.cards() do
			if c.id == id then
				return c.lock, true
			end
		end
		return nil, false
	end
	local lock, has = lockOf("seacrown")
	H.expect(has and lock == "Lv20" and Buildings.byId.seacrown.tier == 20, "everdrift", "at tier 19 the Crown of the Sea waits for level 20", tostring(lock))
	res = H.req(p, "plot.place", { id = "seacrown", x = 0, z = -20, rot = 0 })
	H.expect(not res.ok and res.err == "locked", "everdrift", "and the server won't build it yet (locked)", tostring(res.err))
	local cost = p.PlayerGui:FindFirstChild("ExpandCost", true)
	H.expect(H.buttonNamed(p, "Expand") ~= nil and cost ~= nil and table.find(H.textsOf(cost), Numbers.coins(Island.expandCost(19).shells)) ~= nil, "everdrift", "Expand on, its price the last step's shells", cost and table.concat(H.textsOf(cost), "/"))
	local shells1, f1, eggs1, tH = prof.shells, #fx, #prof.clutch.list, E.now()
	H.clickNamed(p, "Expand", { wait = 0 })
	-- (behind the loading card: the cheer once it has gone)
	local cheer = E.runUntil(function()
		return statusSays("Your island grew into Everdrift.")
	end, 5, 0.05)
	local ownH = math.max(0, Island.rates(prof).shells) / Tuning.TurnSeconds * (E.now() - tH) * 1.5 + 2
	local movedH = prof.shells - shells1
	H.expect(prof.tier == 20 and movedH >= -Island.expandCost(19).shells - 2 and movedH <= -Island.expandCost(19).shells + ownH, "everdrift", "Expand: tier 20 for its shells", string.format("tier %d, shells %+.0f", prof.tier, movedH))
	local grew = ""
	for _, d in p.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "grew", 1, true) then
			grew = d.Text
		end
	end
	H.expect(cheer and Office.plan(20).name == "Everdrift", "everdrift", "the cheer names the island it grew into: Everdrift", grew)
	local _, _, swaps1 = PS.debugNext(1)
	E.run(0.5)
	H.expect(swaps1 == swaps0 + 1 and static:GetAttribute("Built") == 20, "everdrift", "the island built ahead swapped in", string.format("%d -> %d, built %s", swaps0, swaps1, tostring(static:GetAttribute("Built"))))
	local maxB = H.buttonNamed(p, "Expand", true)
	H.expect(maxB ~= nil and table.find(H.textsOf(maxB), "Island max") ~= nil and H.buttonNamed(p, "Expand") == nil and p.PlayerGui:FindFirstChild("ExpandCost", true) == nil, "everdrift", "the button says Island max after, greyed, no price", maxB and table.concat(H.textsOf(maxB), "/"))
	res = H.req(p, "island.expand", {})
	H.expect(not res.ok and res.err == "max" and prof.tier == 20, "everdrift", "and the server grows it no more (max)", tostring(res.err))
	H.expect(#prof.clutch.list == TreeL.count(20) and #prof.clutch.list >= eggs1 and #fxSince(f1, "eggs") >= (if TreeL.count(20) > eggs1 then 1 else 0), "everdrift", "the tree lays the biggest island's eggs", string.format("%d of %d", #prof.clutch.list, TreeL.count(20)))
	-- the land reaches north past where Driftling Haven (tier 10) ended
	local pr20, pr10 = Street.plot(20), Street.plot(10)
	local edge = pr10.z0 -- (z -106)
	local north = 0
	for x = math.floor(pr20.x0), math.floor(pr20.x1) do
		if Street.buildable(20, x, edge - 8) then
			north += 1
		end
	end
	local ox, oz = Street.origin(s.plot)
	local landParts = 0
	local landM = static:FindFirstChild("Land")
	for _, d in (landM and landM:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Position.Z < oz + edge - 8 and math.abs(d.Position.X - ox) < 70 then
			landParts += 1
		end
	end
	-- (the open ground grows both ways round the plaza since 2026-11-20)
	-- (the open ground grows outward evenly round the plaza since 2026-11-20: past Driftling Haven's every way)
	H.expect(pr20.z0 < edge - 8 and pr20.z1 > pr10.z1 + 8 and pr20.x0 < pr10.x0 - 8 and pr20.x1 > pr10.x1 + 8 and north > 0 and landParts > 0, "everdrift", "the open ground reaches past where Driftling Haven's ended every way (grass to build on, the island's model there)", string.format("grass x %d .. %d, z %d .. %d (Driftling Haven x %d .. %d, z %d .. %d), %d cells at z %d, %d parts", pr20.x0, pr20.x1, pr20.z0, pr20.z1, pr10.x0, pr10.x1, edge, pr10.z1, north, edge - 8, landParts))
	-- every card open now: no level on any of them
	local locked = {}
	for _, t in { "work", "nest", "path", "fence", "water", "nature", "decor", "fun" } do
		H.clickNamed(p, "Tab_" .. t, { wait = 0.2 })
		H.clickNamed(p, "Chip_all", { optional = true, wait = 0.2 })
		for _, c in TrayCheck.cards() do
			if c.lock ~= nil and c.lock ~= "Full" then
				table.insert(locked, c.id)
			end
		end
	end
	local high = 0
	for _, d in Buildings.list do
		if d.tier >= 7 and d.tier <= 20 then
			high += 1
		end
	end
	H.expect(#locked == 0 and high >= 40, "everdrift", "every card open at tier 20, the pieces of tiers 7 to 20 among them", table.concat(locked, " "))
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	-- tiers 7 to 20 built up north: a Crown of the Sea (20), a Driftling Citadel (20), a Geode (13), a Crystal Fence (8), a
	-- Gilded Walk (7)
	-- (the first spot north of Driftling Haven's end where every one of the pieces at(x, z) gives, {dx, dz, rot} from it,
	-- fits)
	local function northSpot(id, at)
		for z = edge - 2, math.floor(pr20.z0), -1 do
			for x = math.floor(pr20.x0), math.floor(pr20.x1) do
				local ok = not Plot.isDrawn(id) or (x % 2 == 0 and z % 2 == 0)
				for _, o in at or { { 0, 0, 0 } } do
					ok = ok and Plot.fits(prof.tier, prof.plot.placed, id, x + o[1], z + o[2], o[3])
				end
				if ok then
					return x, z
				end
			end
		end
		return nil, nil
	end
	-- (the dearest of them, the Crown of the Sea, costs most: the store topped up for them all)
	prof.shells = math.max(prof.shells, Buildings.byId.seacrown.shells + Buildings.byId.citadel.shells + Buildings.byId.geode.shells + 1e6)
	H.push(p, 0.3)
	local got = {}
	for _, id in { "seacrown", "citadel", "geode" } do
		local x, z = northSpot(id)
		res = if x then H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 }) else { ok = false, err = "no spot" }
		table.insert(got, string.format("%s %s", id, if res.ok then "ok" else tostring(res.err)))
		H.expect(res.ok and z ~= nil and z < edge and pieceAt(id, x, z) ~= nil, "everdrift", string.format("a %s (tier %d) built north of Driftling Haven's end", Buildings.byId[id].name, Buildings.byId[id].tier), tostring(res.err))
	end
	do
		local x, z = northSpot("goldpath", { { 0, 0, 0 }, { 2, 0, 0 } })
		res = if x then H.req(p, "plot.paint", { id = "goldpath", cells = string.format("%d,%d;%d,%d", x, z, x + 2, z) }) else { ok = false, err = "no spot" }
		H.expect(res.ok and type(res.data) == "table" and res.data.placed == 2 and pieceAt("goldpath", x, z) ~= nil, "everdrift", "a Gilded Walk (tier 7) laid up there", tostring(res.err))
		x, z = northSpot("crystalfence", { { 0, 0, 0 }, { 0, 0, 90 } })
		res = if x then H.req(p, "plot.fence", { id = "crystalfence", edges = string.format("%d,%d,0;%d,%d,90", x, z, x, z) }) else { ok = false, err = "no spot" }
		H.expect(res.ok and type(res.data) == "table" and res.data.placed == 2 and fenceOn({ x, z, 0 }) ~= nil and fenceOn({ x, z, 90 }) ~= nil, "everdrift", "a Crystal Fence (tier 8) run along the grid up there", tostring(res.err))
	end
	H.log("everdrift: %s", table.concat(got, ", "))
	E.run(0.4)
	local card = p.PlayerGui:FindFirstChild("IslandCard", true)
	local title = card and card:FindFirstChild("Title", true)
	H.expect(title ~= nil and title.Text == "Everdrift", "everdrift", "the HUD's island card says Everdrift", title and title.Text)
end
H.checkProfile(p, "everdrift")
mirror(p, "everdrift")

------------------------------------------------------------------ 11. the store (GAME_DESIGN 14)
-- The request (2026-11-14): "make titles. make much more cosmetics, and a rotating shop for cosmetics. make gamepasses
-- ...". The menu bar's Store opens on its four tabs; a pass's Buy asks Roblox (the harness's test ids); a pass set shows
-- Owned; the rotating shop sells a piece for shells and it can be worn (the Founder attribute carries it); the pass
-- track's level 1 is claimed; a product paid through MonetizationService.grant (the way ProcessReceipt does) is told
-- and never paid twice; its egg waits in the bag and hatches from the Tree panel for nothing (a swap when every hut is
-- full); a title is worn from Looks (the Title attribute); the Starter Pack's HUD offer opens the Store.
E.phase = "store"
do
	local StoreL = H.sharedServer("Logic.Store")
	local Cos = H.sharedServer("Data.Cosmetics")
	local Mon = H.sharedServer("Config.Monetization")
	local MS = H.smod("MonetizationService")
	local sh0 = prof.shells
	H.closePanel(p)
	H.clickNamed(p, "BuildDone", { wait = 0.3, optional = true })
	H.push(p, 0.3)
	-- the Starter Pack's offer on the HUD (not bought yet) opens the Store on its Eggs tab
	H.expect(H.buttonNamed(p, "Offer_StarterPack_Go") ~= nil, "store", "the HUD offers the Starter Pack")
	H.clickNamed(p, "Offer_StarterPack_Go", { wait = 0.4, optional = true })
	H.expect(H.currentPanel(p) == "store" and H.buttonNamed(p, "Buy_StarterPack") ~= nil, "store", "the offer opens the Store on the Starter Pack", tostring(H.currentPanel(p)))
	H.closePanel(p)
	-- (the request of 2026-11-14: "add a join group notification if the player hasnt joined the group below the
	-- starter pack as well")
	do
		local sp = p.PlayerGui:FindFirstChild("Offer_StarterPack", true)
		local g = p.PlayerGui:FindFirstChild("Offer_Group", true)
		local words = g and g:FindFirstChild("Text")
		local said = if words and words:IsA("TextLabel") then words.Text else "none"
		H.expect(sp and g and sp:IsA("GuiObject") and g:IsA("GuiObject") and said == "Join the group" and g.Position.Y.Offset == sp.Position.Y.Offset + 16, "store", "not in the group: \"Join the group\" right under the Starter Pack", said)
	end
	H.clickNamed(p, "Menu_store", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "store", "store", "the menu bar's Store opens it", tostring(H.currentPanel(p)))
	local tabs = 0
	for _, t in { "passes", "eggs", "shop", "track" } do
		if H.buttonNamed(p, "Tab_" .. t) then
			tabs += 1
		end
	end
	H.expect(tabs == 4, "store", "its four tabs: Passes, Eggs, Shop, Track", tostring(tabs))
	-- the passes: each with its price; Buy asks Roblox for the pass
	H.clickNamed(p, "Tab_passes", { wait = 0.3 })
	local rows = 0
	for _, key in StoreL.PASSES do
		if H.buttonNamed(p, "Buy_" .. key, true) or (key == "VIP" and H.buttonNamed(p, "VipGift", true)) then
			rows += 1
		end
	end
	H.expect(rows == #StoreL.PASSES, "store", "every pass has its row and button", string.format("%d of %d", rows, #StoreL.PASSES))
	local pr0 = #E.prompts
	H.clickNamed(p, "Buy_DoubleIncome", { wait = 0.3 })
	local last = E.prompts[#E.prompts]
	H.expect(#E.prompts == pr0 + 1 and last and last.kind == "pass" and last.id == Mon.GamePasses.DoubleIncome, "store", "Buy asks Roblox to sell the pass", last and string.format("%s %s", tostring(last.kind), tostring(last.id)))
	-- a pass owned (as the purchase's finish sets it: Store.setPass): Owned, and every shell counts twice
	local r0 = Island.rates(prof).shells
	StoreL.setPass(prof, "DoubleIncome", true)
	H.push(p, 0.4)
	local own = H.buttonNamed(p, "Buy_DoubleIncome", true)
	H.expect(own ~= nil and table.find(H.textsOf(own), "Owned") ~= nil, "store", "a pass owned says Owned", own and table.concat(H.textsOf(own), "/"))
	H.expect(math.abs(Island.rates(prof).shells - 2 * r0) < 1e-6 * math.max(1, r0) and H.view(p).incomeMult == 2, "store", "Double Income: every shell x2", string.format("%.1f -> %.1f", r0, Island.rates(prof).shells))
	StoreL.setPass(prof, "DoubleIncome", false)
	-- the rotating shop: its pieces (Tuning.ShopSize: eight since 2026-11-20), one bought for shells, then worn
	prof.shells = math.max(prof.shells, 1e9)
	H.push(p, 0.3)
	H.clickNamed(p, "Tab_shop", { wait = 0.3 })
	local v = H.view(p)
	H.expect(#v.shopList == Tuning.ShopSize and p.PlayerGui:FindFirstChild("Piece_" .. v.shopList[1], true) ~= nil, "store", string.format("the shop shows its %d pieces", Tuning.ShopSize), tostring(#v.shopList))
	local id = nil
	for _, x in v.shopList do
		if not prof.owned[x] then
			id = x
			break
		end
	end
	if id then
		local cost = StoreL.price(prof, id)
		H.clickNamed(p, "ShopBuy_" .. id, { wait = 0.4 })
		H.expect(prof.owned[id] == true and p.PlayerGui:FindFirstChild("Wear_" .. id, true) ~= nil, "store", "Buy: the piece is theirs (Wear in its place)", string.format("%s for %d", id, cost))
		H.clickNamed(p, "Wear_" .. id, { wait = 0.4 })
		local slot = Cos.byId[id].slot
		H.expect((prof.founder :: any)[slot] == id and string.find(tostring(p:GetAttribute("Founder")), id, 1, true) ~= nil, "store", "Wear: the founder wears it, every client sees it (the Founder attribute)", tostring(p:GetAttribute("Founder")))
	else
		H.expect(false, "store", "a piece in the shop not owned yet")
	end
	-- the pass track: points for growing the island, level 1's free reward claimed
	StoreL.addXp(prof, "expand")
	H.push(p, 0.3)
	H.clickNamed(p, "Tab_track", { wait = 0.3 })
	local f0 = #fx
	H.clickNamed(p, "Claim_1", { wait = 0.5 })
	local told = fxSince(f0, "rewards")
	H.expect(table.find(prof.track.got, 1) ~= nil and #told == 1 and told[1].from == "track", "store", "the track's level 1 claimed, the reward told", string.format("%d rewards", #told))
	H.expect(statusSays("Pass track:"), "store", "a notice says what the track gave")
	H.expect(H.buttonNamed(p, "ClaimP_1") == nil, "store", "the premium side stays locked without its pass")
	H.closePanel(p)
	-- a product paid as ProcessReceipt pays it: an epic egg in the bag, told; the same receipt again pays nothing
	local bag0 = #prof.bag
	local f1 = #fx
	-- (in the server's context, as ProcessReceipt runs)
	local paid, saved = E.call(E.serverCtx, 15, MS.grant, s, "EggEpic", "sim-receipt-1")
	E.run(0.4)
	H.expect(paid and saved and #prof.bag == bag0 + 1 and prof.bag[#prof.bag].r == 4, "store", "an Epic Egg bought: in the bag", string.format("paid %s saved %s bag %d", tostring(paid), tostring(saved), #prof.bag))
	H.expect(#fxSince(f1, "rewards") == 1 and statusSays("Epic Egg: an epic egg"), "store", "a notice says what it gave")
	E.call(E.serverCtx, 15, MS.grant, s, "EggEpic", "sim-receipt-1")
	H.expect(#prof.bag == bag0 + 1, "store", "the same receipt again pays nothing", tostring(#prof.bag))
	-- (the request of 2026-11-14: "make a developer product to refresh eggs in the tree of life": New Eggs lays a
	-- fresh lot at the server's next tick, told the usual way)
	do
		local ids0: { [number]: boolean } = {}
		for _, e in prof.clutch.list do
			ids0[e.id] = true
		end
		local f2 = #fx
		local okR = E.call(E.serverCtx, 15, MS.grant, s, "RefreshEggs", "sim-receipt-eggs")
		E.run(1.2)
		local fresh = #prof.clutch.list > 0
		for _, e in prof.clutch.list do
			if ids0[e.id] then
				fresh = false
			end
		end
		H.expect(okR and fresh and #fxSince(f2, "eggs") >= 1 and statusSays("New Eggs"), "store", "New Eggs bought: the tree lays a fresh lot at once, told", string.format("%d eggs, fresh %s", #prof.clutch.list, tostring(fresh)))
	end
	-- the bag's egg hatched from the Tree panel for nothing (every hut full: the swap picker, then a swap)
	local egg = prof.bag[#prof.bag]
	local pals0, taken0 = #prof.pals, prof.stats.taken
	H.openPanel(p, "tree")
	E.run(0.4)
	H.expect(H.buttonNamed(p, "BagHatch_" .. egg.id) ~= nil, "store", "the Tree panel lists the bag's egg with Hatch")
	-- (the request of 2026-11-14: "make a developer product to refresh eggs in the tree of life, and put the gamepass to
	-- cut the tree of life time to 5 min in the tree of life menu as well")
	H.expect(H.buttonNamed(p, "TreeRefresh") ~= nil and (H.buttonNamed(p, "TreeQuick") ~= nil) == not (prof.passes and prof.passes.QuickTree), "store", "the Tree panel sells New Eggs and, without it, the Quick Tree pass")
	-- (the request of 2026-11-14: "make it possible to purchase eggs in the tree of life menu below the eggs under the
	-- tree tab": an egg a rarity from Uncommon up, each with its Robux, after the eggs lying there)
	do
		local missing = nil
		for key, _ in StoreL.EGG_R do
			if H.buttonNamed(p, "Buy_" .. key) == nil then
				missing = missing or key
			end
		end
		local head = p.PlayerGui:FindFirstChild("BuyHead", true)
		local lastEgg = 0
		for _, g in p.PlayerGui:GetDescendants() do
			if g:IsA("GuiObject") and (string.sub(g.Name, 1, 4) == "Egg_" or string.sub(g.Name, 1, 7) == "BagEgg_") then
				lastEgg = math.max(lastEgg, g.LayoutOrder)
			end
		end
		H.expect(missing == nil and head ~= nil and head:IsA("GuiObject") and head.LayoutOrder > lastEgg, "store", "the Tree panel sells an egg of each rarity from Uncommon up, under the eggs", tostring(missing))
	end
	local function inBag(): boolean
		for _, e in prof.bag do
			if e.id == egg.id then
				return true
			end
		end
		return false
	end
	local hut0 = TreeL.room(prof)
	H.clickNamed(p, "BagHatch_" .. egg.id, { wait = 0.6 })
	local swapped = false
	if inBag() and hut0 == 0 then
		-- (every hut full: the swap picker, as with the tree's own eggs)
		local swap = nil
		for _, b in H.buttons(p) do
			local n = b.Name
			if string.sub(n, 1, 9) == "SwapTake_" then
				swap = n
				break
			end
		end
		H.expect(swap ~= nil and H.currentPanel(p) == "tree", "store", "every hut full: the swap picker for the bag's egg")
		if swap then
			H.clickNamed(p, swap, { wait = 0.6 })
			swapped = true
		end
	end
	-- (the sims' hatch scene ends at once, HatchScene.setQuick; the tree's panel comes back after it)
	H.expect(not inBag() and prof.stats.taken == taken0 + 1 and #prof.pals == pals0 + (if swapped then 0 else 1), "store", "it hatched out of the bag for nothing", string.format("%d pals (was %d), room %d, swapped %s", #prof.pals, pals0, hut0, tostring(swapped)))
	H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "BagHatch_" .. egg.id) == nil, "store", "the tree's panel back, the egg gone from its list", tostring(H.currentPanel(p)))
	H.closePanel(p)
	-- Free Decor: Build mode's decor reads Free and goes down for no shells
	StoreL.setPass(prof, "FreeDecor", true)
	H.push(p, 0.3)
	local BUIp = H.cmod(p, "UI.BuildUI")
	H.inClient(p, BUIp.open, "nature")
	E.run(0.5)
	local card = p.PlayerGui:FindFirstChild("Card_oak", true)
	local price = card and card:FindFirstChild("Shells", true)
	H.expect(price ~= nil and price.Text == "Free" and Plot.price(H.view(p), "oak") == 0, "store", "Free Decor: an Oak Tree's card reads Free", price and price.Text)
	H.clickNamed(p, "BuildDone", { wait = 0.3, optional = true })
	StoreL.setPass(prof, "FreeDecor", false)
	-- VIP: today's gift waits on the HUD; a tap claims it (shells and an egg), told
	StoreL.setPass(prof, "VIP", true)
	prof.vipDay = -1
	H.push(p, 0.4)
	H.expect(H.buttonNamed(p, "Offer_VipGift_Go") ~= nil, "store", "VIP: today's gift waits on the HUD")
	local f2, bag2 = #fx, #prof.bag
	H.clickNamed(p, "Offer_VipGift_Go", { wait = 0.5, optional = true })
	H.expect(prof.vipDay >= 0 and #prof.bag == bag2 + 1 and #fxSince(f2, "rewards") == 1 and statusSays("VIP gift:"), "store", "a tap claims it: shells and an egg, told", string.format("day %d, bag %d -> %d", prof.vipDay, bag2, #prof.bag))
	H.push(p, 0.3)
	H.expect(H.buttonNamed(p, "Offer_VipGift_Go") == nil, "store", "and the gift is gone till tomorrow")
	StoreL.setPass(prof, "VIP", false)
	-- a title worn from Looks: every client sees it (the Title attribute)
	prof.titles.settler = true
	H.push(p, 0.3)
	H.openPanel(p, "looks", "titles")
	E.run(0.4)
	H.clickNamed(p, "WearTitle_settler", { wait = 0.4 })
	H.expect(prof.title == "settler" and p:GetAttribute("Title") == "settler", "store", "a title worn from Looks (the Title attribute)", tostring(p:GetAttribute("Title")))
	H.expect(H.buttonNamed(p, "LooksTab_hat") ~= nil, "store", "Looks has its pieces too")
	H.closePanel(p)
	prof.shells = sh0
	H.push(p, 0.3)
end
H.checkProfile(p, "store")
mirror(p, "store")

-- notices fired together each get their own place in the stack (three new titles at once, as a hatch can bring, all
-- ended up on one spot: each one's slide in kept going to the place it was given first), and the ones under a notice
-- that goes move up into its gap
E.phase = "notices"
do
	H.closePanel(p)
	E.run(0.3)
	local function shown(): { any }
		local out = {}
		for _, d in p.PlayerGui:GetDescendants() do
			if d.Name == "Notice" and d:IsA("Frame") and H.guiVisible(d) then
				table.insert(out, d)
			end
		end
		table.sort(out, function(a: any, b: any): boolean
			return a.Position.Y.Offset < b.Position.Y.Offset
		end)
		return out
	end
	UIKitP.clearNotices()
	UIKitP.notice("First of three notices at once.", nil, 2)
	UIKitP.notice("Second of three.", nil, 4)
	UIKitP.notice("And the third one, the longest of them all.", nil, 6)
	E.run(0.6)
	local ns = shown()
	local ys = {}
	for _, n in ns do
		table.insert(ys, tostring(n.Position.Y.Offset))
	end
	local apart = #ns == 3
	for i = 2, #ns do
		apart = apart and ns[i].Position.Y.Offset >= ns[i - 1].Position.Y.Offset + ns[i - 1].Size.Y.Offset
	end
	H.expect(apart, "notices", "three notices at once each have their own place, one under another", table.concat(ys, ", "))
	-- (a desktop stacks them in the bottom right corner, the PC builders' message corner (2026-11-21: "research on
	-- popular desktop tycoons and replicate their UIs"): the newest lowest, its foot NOTICE_FOOT over the bottom, each
	-- ending 6 px from the right edge)
	local ps = UIKitP.size("Popup")
	local foot = ps.Y - UIKitP.NOTICE_FOOT
	local function inCorner(list: { any }): boolean
		local ok = #list > 0 and list[#list].Position.Y.Offset + list[#list].Size.Y.Offset == foot
		for _, n in list do
			ok = ok and n.Position.X.Offset + n.Size.X.Offset == ps.X - 6
		end
		return ok
	end
	H.expect(inCorner(ns), "notices", "a desktop's notices stack in the bottom right corner, the newest lowest", table.concat(ys, ", "))
	-- the oldest goes after 2 s: the newer two stay put at the foot of the corner
	E.run(2.2)
	local left = shown()
	H.expect(#left == 2 and inCorner(left), "notices", "when the oldest goes, the rest stay in the corner, the newest lowest", left[1] and tostring(left[1].Position.Y.Offset))
	-- a new day's banner at the top: the corner stack is nowhere near it and stays (a touch screen's notices, at the top,
	-- move down below it: the sweep of 2026-11-19 found the banner over them)
	UIKitP.setNoticeTop(70)
	E.run(0.3)
	local under = shown()
	H.expect(#under == 2 and inCorner(under), "notices", "a banner at the top leaves the desktop's corner stack where it is", under[1] and tostring(under[1].Position.Y.Offset))
	UIKitP.setNoticeTop(nil)
	E.run(0.3)
	UIKitP.clearNotices()
	E.run(0.2)
end

-- phones and tablets (the request of 2026-11-19: "make mobile and tablet as responsive and catered to as possible ...
-- Make menus fill the screen on mobile with currency showing and an exit button"): a phone's screen (touch, no mouse): a
-- panel fills the screen under Roblox's top bar, the shells on its awning kept up to date, an exit button with a pad a
-- fingertip wide, and a small button in the body padded too; a tablet's: the panel a third bigger than its design,
-- within the screen; then back to the desktop, the panel its design again with no pads
E.phase = "touch"
do
	local I = require("./inst")
	local uis = I.getD(E.services.UserInputService).props
	local vp0 = E.viewport
	local UIKitC = H.cmod(p, "UI.UIKit")
	local NumbersC = H.sharedServer("Logic.Numbers")
	local function screen(w: number, h: number, touch: boolean)
		E.viewport = E.v2(w, h)
		uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = touch, not touch, not touch
		-- (the engine gives no signal for the switch: the canvases laid out again, the HUD built for the screen)
		H.inClient(p, UIKitC.relayout)
		E.run(0.5)
	end
	local function sheet()
		local panel = p.PlayerGui:FindFirstChild("Panel_pals", true)
		return if panel then panel:FindFirstChild("Frame") else nil
	end
	local K = H.inClient(p, UIKitC.P)
	local need = math.ceil(44 / K)
	-- the touch layout (2026-11-21: "rearrange and redo the UI on mobile and tablet. Reference other mobile tycoon
	-- games in landscape and replicate their UI design"): the menus as squares a fingertip wide in a grid down the
	-- left, Build the grid's last square ("Put the build button as the 6th button here instead of next to jump"), no
	-- button of the HUD's under the jump button, and the bottom left (the thumbstick's corner) clear of buttons; since
	-- "flush the first ui part to the left, and put the second image, the buttons, to the bottom, just like in pc" the
	-- squares in a row along the bottom and the quest's card against the left edge
	local function touchHud(tag: string)
		E.run(0.6)
		local cs = H.inClient(p, UIKitC.size, "Hud")
		local Kn = H.inClient(p, UIKitC.P)
		local hud = p.PlayerGui:FindFirstChild("Hud")
		local canvas = hud and hud:FindFirstChild("Canvas")
		if canvas == nil then
			H.expect(false, "touch", tag .. ": the HUD's canvas")
			return
		end
		local small = math.min(cs.X, cs.Y) * Kn <= 500
		local js = (if small then 70 else 120) / Kn
		local jx0, jy0 = cs.X - (if small then 95 else 170) / Kn, cs.Y - (if small then 90 else 210) / Kn
		-- (the engine's AbsoluteSize may leave the canvas's UIScale out: u, its units a UI px)
		local u = math.max(1e-6, canvas.AbsoluteSize.X / math.max(1, cs.X))
		local under, corner = {}, {}
		for _, d in canvas:GetDescendants() do
			if d:IsA("GuiButton") and d.Name ~= "Hit" and H.guiVisible(d) then
				local x0 = (d.AbsolutePosition.X - canvas.AbsolutePosition.X) / u
				local y0 = (d.AbsolutePosition.Y - canvas.AbsolutePosition.Y) / u
				local x1, y1 = x0 + d.AbsoluteSize.X / u, y0 + d.AbsoluteSize.Y / u
				if x0 < jx0 + js and x1 > jx0 and y0 < jy0 + js and y1 > jy0 then
					table.insert(under, d.Name)
				end
				if x0 < cs.X * 0.3 and y1 > cs.Y * 0.62 then
					table.insert(corner, d.Name)
				end
			end
		end
		H.expect(#under == 0, "touch", tag .. ": no HUD button under the jump button", table.concat(under, ", "))
		H.expect(#corner == 0, "touch", tag .. ": the thumbstick's corner (bottom left) clear of buttons", table.concat(corner, ", "))
		local pals = H.buttonNamed(p, "Menu_pals")
		H.expect(pals ~= nil and pals.Parent ~= nil and pals.Parent.Name == "MenuBar" and pals.AbsoluteSize.X / u * Kn >= 43 and pals.AbsoluteSize.Y / u * Kn >= 43, "touch", tag .. ": the menus are squares a fingertip wide in the row along the bottom", pals and tostring(pals.AbsoluteSize) or "missing")
		local mb = H.buttonNamed(p, "Menu_build")
		local last = nil
		if mb and mb.Parent and mb.Parent.Name == "MenuBar" then
			for _, d in mb.Parent:GetChildren() do
				if d:IsA("GuiButton") and d.Visible and (last == nil or d.AbsolutePosition.Y > last.AbsolutePosition.Y or (d.AbsolutePosition.Y == last.AbsolutePosition.Y and d.AbsolutePosition.X > last.AbsolutePosition.X)) then
					last = d
				end
			end
		end
		H.expect(mb ~= nil and last == mb and math.abs(mb.AbsoluteSize.X - pals.AbsoluteSize.X) < 1 and math.abs(mb.AbsoluteSize.Y - pals.AbsoluteSize.Y) < 1, "touch", tag .. ": Build the last square of the grid, as big as the rest", if mb then string.format("%s in %s, last %s", tostring(mb.AbsoluteSize), mb.Parent and mb.Parent.Name or "nothing", last and last.Name or "none") else "missing")
		-- (every square of the row level with the others, its foot near the screen's bottom edge)
		local foots, tops = {}, {}
		local row = mb and mb.Parent
		if row and row.Name == "MenuBar" then
			for _, d in row:GetChildren() do
				if d:IsA("GuiButton") and d.Visible then
					table.insert(foots, (d.AbsolutePosition.Y + d.AbsoluteSize.Y - canvas.AbsolutePosition.Y) / u)
					table.insert(tops, (d.AbsolutePosition.Y - canvas.AbsolutePosition.Y) / u)
				end
			end
		end
		local lowest = if #foots > 0 then math.max(table.unpack(foots)) else -1
		local level = #tops > 0 and math.max(table.unpack(tops)) - math.min(table.unpack(tops)) < 1
		H.expect(#foots >= 5 and level and lowest >= cs.Y - 12 and lowest <= cs.Y, "touch", tag .. ": the squares in one row along the bottom", string.format("%d squares, foot at %.0f of %d", #foots, lowest, cs.Y))
		local qf = canvas:FindFirstChild("Quest")
		local qx = if qf and qf:IsA("GuiObject") then (qf.AbsolutePosition.X - canvas.AbsolutePosition.X) / u else nil
		H.expect(qx ~= nil and math.abs(qx - 5) < 1, "touch", tag .. ": the quest's card against the left edge", if qx then string.format("at %.0f", qx) else "missing")
	end
	screen(844, 390, true)
	touchHud("a phone")
	screen(1024, 768, true)
	touchHud("a tablet")
	screen(844, 390, true)
	H.openPanel(p, "pals")
	E.run(0.6)
	local f = sheet()
	local cs = H.inClient(p, UIKitC.size, "Modal")
	H.expect(f ~= nil and f.Size.X.Offset == cs.X and f.Size.Y.Offset == cs.Y, "touch", "a phone: the panel fills the screen", string.format("%s vs %dx%d", if f then tostring(f.Size) else "none", cs.X, cs.Y))
	local wallet = f and f:FindFirstChild("Wallet", true)
	local shells = wallet and wallet:FindFirstChild("Shells", true)
	H.expect(shells ~= nil and shells.Text == NumbersC.short(math.floor(prof.shells)), "touch", "with the shells on its awning", shells and shells.Text)
	prof.shells += 12345
	H.push(p, 0.4)
	H.expect(shells ~= nil and shells.Text == NumbersC.short(math.floor(prof.shells)), "touch", "kept up to date while it's open", shells and shells.Text)
	prof.shells -= 12345
	local close = H.buttonNamed(p, "Close")
	local hit = close and close:FindFirstChild("Hit")
	H.expect(close ~= nil and close.Size.X.Offset >= 20 and (close.Size.X.Offset >= need or (hit ~= nil and close.Size.X.Offset + 2 * -hit.Position.X.Offset >= need)), "touch", "an exit button a fingertip wide (44 screen px)", close and string.format("%d + pad %d, K %d", close.Size.X.Offset, hit and -hit.Position.X.Offset or 0, K))
	local eggs = H.buttonNamed(p, "OpenTree")
	local ehit = eggs and eggs:FindFirstChild("Hit")
	H.expect(eggs ~= nil and ehit ~= nil and eggs.Size.Y.Offset + 2 * -ehit.Position.Y.Offset >= need, "touch", "a small button in the body padded too", eggs and tostring(eggs.Size))
	H.expect(H.clickNamed(p, "Close", { wait = 0.4 }) and H.currentPanel(p) == nil, "touch", "and the exit closes it")
	screen(1024, 768, true)
	H.openPanel(p, "pals")
	E.run(0.6)
	f = sheet()
	cs = H.inClient(p, UIKitC.size, "Modal")
	H.expect(f ~= nil and f.Size.X.Offset > 320 and f.Size.X.Offset <= cs.X - 24 and f:FindFirstChild("Wallet", true) ~= nil, "touch", "a tablet: the panel bigger than its design, within the screen, the shells shown", f and tostring(f.Size))
	H.closePanel(p)
	E.viewport = vp0
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = false, true, true
	H.inClient(p, UIKitC.relayout)
	E.run(0.5)
	H.openPanel(p, "pals")
	E.run(0.6)
	f = sheet()
	local c2 = H.buttonNamed(p, "Close")
	H.expect(f ~= nil and f.Size.X.Offset == 320 and f:FindFirstChild("Wallet", true) == nil and c2 ~= nil and c2:FindFirstChild("Hit") == nil, "touch", "back on the desktop: the panel its design, no pads", f and tostring(f.Size))
	H.closePanel(p)
end
-- the sky round the floating islands (UI/SkyBackdrop; the request of 2026-11-20, "polish the skybox more. it should be
-- of the same quality as the ones in the egg hatching screen, with day and night cycles with moon and sun rising"):
-- hidden in the classic look (the world itself shows); with the pixel filter on, painted behind its picture: held at
-- noon the sun is high, no moon and no stars; at midnight the moon is up and the night full; at sunrise the sun sits
-- low on the sea of clouds; the night's sounds and birds follow DayLight.night
do
	local SBm = H.cmod(p, "UI.SkyBackdrop")
	local DLm = H.cmod(p, "Controllers.DayLight")
	local PRs = H.cmod(p, "Pixel.PixelRenderer")
	local WVs = H.cmod(p, "Controllers.WeatherView")
	local pg = p:FindFirstChildOfClass("PlayerGui")
	local g0 = pg and pg:FindFirstChild("SkyBackdrop")
	H.expect(g0 == nil or not g0.Enabled, "sky", "in the classic look no painted sky covers the world")
	E.editableImageMode = "ok"
	H.inClient(p, PRs.setTier, "low")
	H.inClient(p, WVs.debugSet, "sunny") -- (a clear night: rain would hide the stars)
	E.run(1)
	local g = pg and pg:FindFirstChild("SkyBackdrop")
	local whole = g ~= nil and g.Enabled
	-- (on its Canvas frame, laid out in art px under a UIScale of K)
	local cv = g and g:FindFirstChild("Canvas")
	for _, n in { "Sky", "Sun", "Moon", "FarA", "FarB", "Life" } do
		whole = whole and cv ~= nil and cv:FindFirstChild(n) ~= nil
	end
	local lay = pg and pg:FindFirstChild("PixelLayer")
	local img = lay and lay:FindFirstChild("Image")
	local isc = img and img:FindFirstChildOfClass("UIScale")
	local kNow = H.inClient(p, PRs.pixelScale)
	local artW = math.ceil(E.viewport.X / kNow)
	H.expect(isc ~= nil and img ~= nil and math.abs(isc.Scale - kNow) < 1e-6 and img.Size.X.Offset == artW, "sky", "the pixel layer sized in art px and scaled by the pixel size with a UIScale (Roblox keeps an Offset whole)", if isc and img then string.format("UIScale %g, K %g, %d art px (the screen: %d)", isc.Scale, kNow, img.Size.X.Offset, artW) else "no UIScale on the layer")
	local cvs = cv and cv:FindFirstChildOfClass("UIScale")
	H.expect(cvs ~= nil and math.abs(cvs.Scale - H.inClient(p, PRs.pixelScale)) < 1e-6, "sky", "the painted sky's canvas scaled by the pixel size (no K in an offset)", if cvs then string.format("%g, K %g", cvs.Scale, H.inClient(p, PRs.pixelScale)) else "no UIScale")
	H.expect(whole and g:FindFirstChild("CloudsA") == nil, "sky", "with the pixel filter on, the sky behind the islands: its picture, the sun, the moon, the far islets and the sea of clouds twice, its life; no clouds drifting across it")
	local function at(h)
		H.inClient(p, SBm.debugHour, h, 0)
		E.run(0.6)
		return H.inClient(p, SBm.debugState)
	end
	local function said(d)
		return string.format("on %s, hour %.3f, %s, sun %s at %d, moon %s, stars %.2f, painted %d, pending %s", tostring(d.on), d.hour, d.key, tostring(d.sun), d.sunY, tostring(d.moon), d.stars, d.paints, tostring(d.pending))
	end
	local noon = at(0.5)
	H.expect(noon.on and noon.sun and not noon.moon and noon.stars == 0 and not noon.pending and noon.W > 0, "sky", "at noon the sun is up, no moon, no stars", said(noon))
	local night = at(0.95)
	H.expect(night.moon and not night.sun and night.stars > 0.9 and night.paints > noon.paints and not night.pending, "sky", "at midnight the moon is up and the night full, painted as a new notch", said(night))
	local rise = at(0.235)
	H.expect(rise.sun and rise.sunY > noon.sunY + rise.H * 0.4 and rise.stars < 0.3, "sky", "at sunrise the sun sits low on the sea of clouds, the stars nearly gone", said(rise))
	H.expect(H.inClient(p, DLm.night, 0.5) == 0 and H.inClient(p, DLm.night, 0.95) == 1, "sky", "DayLight.night: none at noon, full at midnight")
	H.inClient(p, WVs.debugSet, "rain")
	local rain = at(0.95)
	H.expect(rain.moon and rain.stars < 0.3 and rain.key ~= night.key, "sky", "the same midnight in the rain: the stars hidden, another notch", said(rain))
	H.inClient(p, WVs.debugSet, nil)
	H.inClient(p, SBm.debugHour, nil)
	H.inClient(p, PRs.setTier, "off")
	E.editableImageMode = "fail"
	E.run(0.2)
	H.expect(g ~= nil and not g.Enabled, "sky", "the classic look again: the painted sky hidden again")
end
-- the Tree of Life's edges (the request of 2026-11-20: "the tree has alot of jaggied outlines, and stray pixels around
-- the outline, especially near the fruits"). Its model at every stage and turned every way: no motes cast as parts
-- (loose two and three pixel squares round it), every gold fruit on a stalk up into the leaves (the third of a cloud's
-- hung in the air on nothing), and no glowing marks on its bark, keystone or stones (the same day: "there are strange
-- blue rectangles as well", "on the tree"; they were cyan blocks). (The picture itself is the preview's to check: the
-- simulator's rays meet only its ground. The scenario treeink counts the glowing marks at an outline and the loose bits
-- on the village's tree.)
do
	local bad: { string } = {}
	for _, rot in { 0, 90, 180, 270 } do
		for stage = 1, 6 do
			local at = E.cf.new(0, 0, 0) * E.cf.Angles(0, math.rad(rot), 0)
			local m = DecorModels.build("tree", at, stage)
			local marks, motes, loose, stalks, fruit = 0, 0, 0, {}, {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					if d.Name == "Mote" then
						motes += 1
					elseif d.Name == "Rune" or d.Name == "Glyph" then
						marks += 1
					elseif d.Name == "Stalk" then
						table.insert(stalks, d)
					elseif d.Name == "Fruit" or d.Name == "Sparkle" then
						table.insert(fruit, d)
					end
				end
			end
			for _, f in fruit do
				local held = false
				for _, st in stalks do
					local dx, dz = st.Position.X - f.Position.X, st.Position.Z - f.Position.Z
					local foot = st.Position.Y - st.Size.Y / 2
					if dx * dx + dz * dz < 0.01 and math.abs(foot - (f.Position.Y + 0.2)) < 0.08 then
						held = true
					end
				end
				if not held then
					loose += 1
				end
			end
			if motes > 0 or loose > 0 or marks > 0 then
				table.insert(bad, string.format("rot %d stage %d: %d motes, %d fruit on no stalk, %d glowing marks", rot, stage, motes, loose, marks))
			end
			m:Destroy()
		end
	end
	H.expect(#bad == 0, "tree", "the Tree of Life's model, every stage turned every way: no motes, no glowing marks, every fruit on a stalk", table.concat(bad, "; "))
end
H.checkProfile(p, "end")
mirror(p, "end")

report(E, H)
