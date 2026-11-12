-- The main simulation: a new island end to end through the real client and its UI (the campfire, the Tree of Life,
-- the HUD, the tips), building what the tips ask (food, a camp, a stall, a tent, a hut: the starting shells cover
-- them), the days turning (a villager moves in and takes a job, the stores grow), the Tree of Life growing driftlings
-- into its pen and the pen sending the best to the hut (the tree's card, its panel: a level of Speed, selling from the
-- pen, a tap on the tree in the world), the Driftlings panel (moving one to the pen and back in a swap, help, selling),
-- the Villagers and Index panels, the founder's looks, settings, expanding, the questline, then a malicious client,
-- then a second player. Every check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
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
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Island = H.sharedServer("Logic.Island")

------------------------------------------------------------------ 1. a new island
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(1.5)
local fx = H.watchFx(p)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(prof.shells == Tuning.StartShells and prof.food == Tuning.StartFood and prof.wood == Tuning.StartWood, "join", "the starting stores", string.format("%s %s %s", prof.shells, prof.food, prof.wood))
H.expect(prof.tier == 1 and prof.tut == 1 and #prof.folk == 0 and #prof.plot.placed == 1 and prof.plot.placed[1].id == "tree", "join", "a new island, tips at step 1, nobody else yet (its Tree of Life)")
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local land1 = static and static:FindFirstChild("Land")
H.expect(land1 ~= nil and land1:FindFirstChild("Land") ~= nil and static:FindFirstChild("Office") == nil, "join", "the island is built under Plots.Plot_1.Static.Land (no house)")
H.expect(land1 ~= nil and land1:FindFirstChild("FireStone", true) ~= nil and land1:FindFirstChild("JettyPlank", true) ~= nil, "join", "its plaza's campfire and the jetty")
H.expect(plot1 and plot1:GetAttribute("StudioName") == "Pixel's Isle", "join", "the island's name", tostring(plot1 and plot1:GetAttribute("StudioName")))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there")
for _, n in { "Menu_build", "Menu_folk", "Menu_pals", "Menu_index", "Menu_looks" } do
	H.expect(H.buttonNamed(p, n) ~= nil, "join", "the menu bar's " .. n)
end
H.expect(#H.buttons(p, "^Food first", true) == 0, "join", "(tips are text, not buttons)")
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
	local pg = p:FindFirstChildOfClass("PlayerGui")
	H.expect(pg ~= nil and pg:FindFirstChild("LoadingCard") == nil, "join", "and nothing of it left on the screen")
end
-- the background music: the island's tunes by the clock; the note in the corner switches it off and on (kept)
local AudioM = H.cmod(p, "Controllers.Audio")
local ms = H.inClient(p, AudioM.musicState)
H.expect((ms.mood == "day" or ms.mood == "night") and ms.on and ms.tracks >= 1, "join", "the island's music plays", string.format("%s %s %d", tostring(ms.mood), tostring(ms.on), ms.tracks))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "off" and not H.inClient(p, AudioM.musicState).on, "join", "the note switches the music off, kept with the profile", tostring(prof.settings.music))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "on" and H.inClient(p, AudioM.musicState).on, "join", "and on again", tostring(prof.settings.music))
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
H.checkProfile(p, "join")
H.checkMirror(p, "join")

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
H.expect(H.clickNamed(p, "Menu_build", { wait = 0.4 }) and BuildUI.isOpen(), "build", "Build mode opens")
local bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "food" and bst.goal == "patch", "build", "the first tip: the Food tab, the veggie patch to build", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the tip's banner shows in Build mode")
H.clickNamed(p, "Tab_decor", { wait = 0.3 })
H.expect(H.inClient(p, BuildUI.debugState).tab == "decor", "build", "the player can still look round the other tabs")
local sh0 = prof.shells
local res = place("patch")
E.run(0.5)
bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "wood" and bst.goal == "lumber" and H.buttonNamed(p, "Buy_lumber") ~= nil, "build", "the patch built: the tray turns to the Wood tab and the lumber camp", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the next tip's banner over the tray")
H.clickNamed(p, "BuildDone", { wait = 0.3 })
H.expect(not BuildUI.isOpen() and tipShown(), "build", "Done: the tray goes, the tip stays")
H.expect(res.ok and #prof.plot.placed == 2 and prof.plot.placed[2].id == "patch", "build", "a veggie patch", tostring(res.err))
H.expect(math.abs(prof.shells - (sh0 - Buildings.byId.patch.shells)) < 1, "build", "paid for in shells", string.format("%s -> %s", sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to wood (food built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("lumber")
H.expect(res.ok and prof.tut == 3, "build", "a lumber camp: the tips move on to shells", tostring(res.err))
res = place("stall")
H.expect(res.ok and prof.tut == 4, "build", "a snack stall: the tips move on to a home", tostring(res.err))
local fxTent = #fx
res = place("tent")
H.expect(res.ok and prof.tut == 5, "build", "a tent: the tips move on to a hut", tostring(res.err))
H.expect(#prof.folk == 1 and prof.folk[1].work ~= 0, "build", "a castaway moves into the tent at once (no wait for a turn) and takes a job", tostring(#prof.folk))
local welcomed = false
for i = fxTent + 1, #fx do
	if fx[i].kind == "turn" and type(fx[i].movedIn) == "table" then
		welcomed = true
	end
end
H.expect(welcomed, "build", "the newcomer is announced (Fx turn with who moved in)")
res = place("nest")
H.expect(res.ok and prof.wood < Tuning.StartWood and prof.tut == 6, "build", "a hut (shells and wood): the tips move on to the tree", string.format("%s tut %d", tostring(res.err), prof.tut))
H.expect(#prof.plot.placed == 6 and prof.shells >= 0, "build", "the starting shells paid for every building the tips ask for (beside the tree)", string.format("%d pieces, %s shells left", #prof.plot.placed, prof.shells))
res = place("orchard")
H.expect(not res.ok and res.err == "locked", "build", "an orchard waits for a bigger island", tostring(res.err))
prof.shells = 5
res = place("hut")
H.expect(not res.ok and res.err == "money", "build", "not enough shells", tostring(res.err))
prof.shells = 1000
local wood0 = prof.wood
prof.wood = 0
res = place("hut")
H.expect(not res.ok and res.err == "wood", "build", "not enough wood", tostring(res.err))
prof.wood = wood0
H.push(p, 0.4)
local v = H.view(p)
H.expect(v ~= nil and #v.pieces == 6 and v.beds == 1 and v.nests == 2 and v.pen == Tuning.PenRoom[1], "build", "the view: five pieces and the tree, a bed, a hut's room for two, the pen's room", v and string.format("%d %d %d %d", #v.pieces, v.beds, v.nests, v.pen))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 6, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
H.checkProfile(p, "build")
H.checkMirror(p, "build")

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
H.expect(#prof.folk == 1, "days", "the castaway lives in the tent (one bed: nobody else yet)", tostring(#prof.folk))
local mika = prof.folk[1]
H.expect(mika ~= nil and mika.work ~= 0, "days", "and took a job straight away", tostring(mika and mika.work))
local ticks = 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
	end
end
H.expect(ticks >= math.floor(E.now() - t0) - 3, "days", "the stores reach the client every second (Fx tick)", string.format("%d ticks in %.1f s", ticks, E.now() - t0))
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
H.expect(H.inClient(p, WV.ownCount, "v") == 1, "days", "the villager walks the island", tostring(H.inClient(p, WV.ownCount, "v")))
local r = Island.rates(prof)
H.expect(r.food > 0 and r.wood > 0, "days", "food and wood come in", string.format("%.1f %.1f", r.food, r.wood))
H.checkProfile(p, "days")
H.checkMirror(p, "days")

------------------------------------------------------------------ 4. Villagers: a job through the panel
E.phase = "folk"
H.clickNamed(p, "Menu_folk", { wait = 0.4 })
H.expect(H.currentPanel(p) == "folk", "folk", "the Villagers panel opens", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "Job_" .. mika.id) ~= nil, "folk", "a Job button on their row")
H.clickNamed(p, "Job_" .. mika.id, { wait = 0.4 })
local lumberUid = 0
for _, q in prof.plot.placed do
	if q.id == "lumber" then
		lumberUid = q.uid
	end
end
H.expect(H.buttonNamed(p, "Go_" .. lumberUid) ~= nil or mika.work == lumberUid, "folk", "the job picker lists the lumber camp")
if mika.work ~= lumberUid then
	H.clickNamed(p, "Go_" .. lumberUid, { wait = 0.5 })
end
H.expect(mika.work == lumberUid, "folk", "they work at the camp now", tostring(mika.work))
H.expect(H.currentPanel(p) == "folk", "folk", "back on the list")
H.closePanel(p)

------------------------------------------------------------------ 5. the Tree of Life (GAME_DESIGN 6)
E.phase = "tree"
local TreeL = H.sharedServer("Logic.Tree")
local CreaturesT = H.sharedServer("Data.Creatures")
local treeQ = nil
for _, q in prof.plot.placed do
	if q.id == "tree" then
		treeQ = q
	end
end
H.expect(treeQ ~= nil, "tree", "the island's Tree of Life")
local treeModel = nil
for _, c in decor:GetChildren() do
	if c:GetAttribute("Decor") == "tree" then
		treeModel = c
	end
end
H.expect(treeModel ~= nil and treeModel:FindFirstChild("Pod", true) ~= nil and treeModel:FindFirstChild("PenFloor", true) ~= nil and treeModel:FindFirstChild("Gate", true) ~= nil, "tree", "its model: the tree with its glowing hollow, and the fenced pen")
-- it grows a driftling every few seconds into the pen; the pen sends the best on to the hut, which take jobs
local fTree = #fx
local nBefore = #prof.pals
E.runUntil(function()
	return #prof.pals > nBefore and #prof.pals >= 3
end, Tuning.TreeSecs[1] * 4 + 2, 0.2)
E.run(0.4)
local grownFx = 0
for i = fTree + 1, #fx do
	if fx[i].kind == "tree" and type(fx[i].grown) == "table" then
		grownFx += #fx[i].grown
	end
end
H.expect(#prof.pals >= 3 and grownFx >= 1, "tree", "the tree grows driftlings every few seconds (Fx tree)", string.format("%d driftlings, %d grown in the fx", #prof.pals, grownFx))
H.expect(prof.stats.grown >= 1 and prof.seen[prof.pals[1].sp] == 2, "tree", "each one counted and in the Index")
local housed, working = 0, 0
for _, x in prof.pals do
	if x.home ~= 0 then
		housed += 1
		if x.work ~= 0 then
			working += 1
		end
	end
end
H.expect(housed == Buildings.byId.nest.slots, "tree", "the pen sent its best two to the hut", tostring(housed))
H.checkProfile(p, "tree")
-- (a newborn walks from the hollow into the pen: a few seconds for every one to be in)
E.runUntil(function()
	local _, a, b = H.inClient(p, WV.ownCount, "p")
	return a > 0 and a == b
end, 6, 0.25)
local npals, npen, inside = H.inClient(p, WV.ownCount, "p")
H.expect(npals == #prof.pals and npen == TreeL.inPen(prof), "tree", "every driftling on the island, the pen's too", string.format("%d of %d, %d in the pen", npals, #prof.pals, npen))
H.expect(inside == npen, "tree", "the pen's stand inside its fence", string.format("%d of %d", inside, npen))
-- the HUD's tree card: its bar and the pen; Open opens the tree's panel
H.expect(H.buttonNamed(p, "TreeOpen") ~= nil, "tree", "the tree's card with Open")
prof.shells = math.max(prof.shells, 1000)
prof.wood = math.max(prof.wood, 200)
H.push(p, 0.4)
H.clickNamed(p, "TreeOpen", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "tree", "Open opens the Tree of Life's panel", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "Upgrade_speed") ~= nil and H.buttonNamed(p, "Upgrade_luck") ~= nil, "tree", "its Speed and Luck with their prices")
H.clickNamed(p, "Upgrade_speed", { wait = 0.5 })
H.expect(prof.tree.speed == 2 and prof.tut == 7, "tree", "Speed bought from the panel; the tips move on", string.format("speed %d tut %d", prof.tree.speed, prof.tut))
H.expect(math.abs(TreeL.secs(prof) - Tuning.TreeSecs[2] / (1 + (TreeL.hutFx(prof)))) < 1e-6 and TreeL.secs(prof) < Tuning.TreeSecs[1], "tree", "it grows faster now (the huts' Leafy ones speed it too)", tostring(TreeL.secs(prof)))
H.closePanel(p)
-- the pen fills; the tree waits, ready, until there is room
E.runUntil(function()
	return TreeL.waiting(prof)
end, Tuning.TreeSecs[2] * (Tuning.PenRoom[1] + 3), 0.25)
H.expect(TreeL.waiting(prof), "tree", "the pen fills", string.format("%d of %d", TreeL.inPen(prof), TreeL.penRoom(prof)))
local nFull = #prof.pals
E.run(Tuning.TreeSecs[2] * 2)
H.expect(#prof.pals == nFull, "tree", "a full pen: the tree waits", string.format("%d -> %d", nFull, #prof.pals))
-- selling from the pen: two taps on a row's Sell
H.openPanel(p, "tree")
local penOne = nil
for _, x in prof.pals do
	if x.home == 0 and penOne == nil then
		penOne = x
	end
end
local price = penOne and TreeL.price(penOne) or 0
local shBefore = prof.shells
H.clickNamed(p, "PenSell_" .. (if penOne then penOne.id else 0), { wait = 0.3 })
H.expect(#prof.pals == nFull, "tree", "one tap only asks Sure?")
H.clickNamed(p, "PenSell_" .. (if penOne then penOne.id else 0), { wait = 0.5 })
H.expect(prof.stats.sold == 1 and math.abs(prof.shells - (shBefore + price)) < 2 and penOne ~= nil and table.find(prof.pals, penOne) == nil, "tree", "the second sells it for its price (the waiting tree fills its place at once)", string.format("%d driftlings, %+.0f shells (price %d)", #prof.pals, prof.shells - shBefore, price))
-- a common one or two in the pen: Sell commons sells them all at once
local commons = 0
for _, x in prof.pals do
	local d = CreaturesT.byId[x.sp]
	if x.home == 0 and d and d.rarity == 1 then
		commons += 1
	end
end
if commons > 0 then
	H.push(p, 0.3)
	H.openPanel(p, "tree")
	local sold0 = prof.stats.sold
	H.clickNamed(p, "SellCommons", { wait = 0.5 })
	H.expect(prof.stats.sold == sold0 + commons, "tree", "Sell commons sells every common one in the pen", string.format("%d of %d", prof.stats.sold - sold0, commons))
end
H.closePanel(p)
-- a tap on the tree in the world opens its panel
do
	local PRc = H.cmod(p, "Pixel.PixelRenderer")
	local ox0, oz0 = Street.origin(s.plot)
	local tw, td = Plot.footprint(treeQ.id, treeQ.rot)
	-- (the footprint's middle: where the tree's lawn meets the pen's floor, both the tree's model)
	local treeAt = E.v3(ox0 + treeQ.x + tw / 2 + 0.3, Street.LAWN_Y + 0.05, oz0 + treeQ.z + td / 2 + 0.3)
	E.raycastParts = true
	H.inClient(p, function()
		local pos = PRc.project(treeAt)
		WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
	end)
	E.raycastParts = nil
	E.run(0.5)
	H.expect(H.currentPanel(p) == "tree", "tree", "a tap on the tree opens its panel", tostring(H.currentPanel(p)))
	H.closePanel(p)
end
H.checkProfile(p, "tree")
H.checkMirror(p, "tree")

------------------------------------------------------------------ 6. the Driftlings panel: moving, helping, selling
E.phase = "pals"
local pal = nil
for _, x in prof.pals do
	if x.home ~= 0 and pal == nil then
		pal = x
	end
end
H.clickNamed(p, "Menu_pals", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "pals", "the Driftlings panel opens")
H.expect(pal ~= nil and H.buttonNamed(p, "Move_" .. pal.id) ~= nil and H.buttonNamed(p, "Help_" .. pal.id) ~= nil and H.buttonNamed(p, "Sell_" .. pal.id) ~= nil, "pals", "Move, Help and Sell on its row")
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
H.clickNamed(p, "Help_" .. pal.id, { wait = 0.4 })
H.expect(H.buttonNamed(p, "Go_0", true) ~= nil, "pals", "the help picker opens (Rest at least)")
H.openPanel(p, "pals")
-- Move: the hut picker; to the pen it goes (and stays: held), the hut's room filled from the pen
local hutUid = pal.home
H.clickNamed(p, "Move_" .. pal.id, { wait = 0.4 })
H.expect(H.buttonNamed(p, "Move_0") ~= nil, "pals", "the hut picker lists the pen")
-- (the pen is full: make room first, as a player would by selling one)
if TreeL.inPen(prof) >= TreeL.penRoom(prof) then
	for _, x in prof.pals do
		if x.home == 0 then
			H.req(p, "pal.sell", { id = x.id })
			break
		end
	end
	H.openPanel(p, "pals", { move = pal.id })
end
H.clickNamed(p, "Move_0", { wait = 0.5 })
H.expect(pal.home == 0 and pal.held == 1 and pal.work == 0, "pals", "moved to the pen: it stays there, not working", string.format("home %d held %s", pal.home, tostring(pal.held)))
local refilled = 0
for _, x in prof.pals do
	if x.home == hutUid then
		refilled += 1
	end
end
H.expect(refilled == Buildings.byId.nest.slots, "pals", "the hut's room filled again from the pen", tostring(refilled))
-- back in a swap: the hut is full, so it swaps with one living there
H.openPanel(p, "pals", { move = pal.id })
local other = nil
for _, x in prof.pals do
	if x.home == hutUid and other == nil then
		other = x
	end
end
H.expect(other ~= nil and H.buttonNamed(p, "SwapWith_" .. other.id) ~= nil, "pals", "a full hut: swap with one of its driftlings")
H.clickNamed(p, "SwapWith_" .. (if other then other.id else 0), { wait = 0.5 })
H.expect(pal.home == hutUid and pal.held == nil and other ~= nil and other.home == 0 and other.held == 1, "pals", "swapped: it lives in the hut again, the other waits in the pen", string.format("%d / %s", pal.home, tostring(other and other.home)))
-- selling from the panel takes two taps
local nPals = #prof.pals
H.openPanel(p, "pals")
E.run(0.3)
H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.3 })
H.expect(#prof.pals == nPals, "pals", "one tap only asks Sure?")
H.closePanel(p)
H.checkProfile(p, "pals")
H.checkMirror(p, "pals")

------------------------------------------------------------------ 7. the founder's looks
E.phase = "looks"
local skin0 = prof.founder.skin
H.openPanel(p, "looks")
E.run(0.4)
H.clickNamed(p, "Next_skin", { wait = 0.2 })
H.clickNamed(p, "SaveLook", { wait = 0.6 })
H.expect(prof.founder.skin == skin0 % 4 + 1, "looks", "the new skin is saved", string.format("%d -> %d", skin0, prof.founder.skin))
H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", prof.founder.skin, prof.founder.hair, prof.founder.style, prof.founder.shirt), "looks", "every client sees the new look (the Founder attribute)", tostring(p:GetAttribute("Founder")))
H.closePanel(p)

------------------------------------------------------------------ 8. the other panels, settings, tips
E.phase = "panels"
local errs0 = #E.errors
for _, name in { "folk", "pals", "tree", "hatch", "index", "looks" } do
	H.openPanel(p, name)
	E.run(0.3)
	H.expect(H.currentPanel(p) == name, "panels", name .. " opens")
end
H.closePanel(p)
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
-- expanding the island from the build tray: the next island was built ahead in the background, so the expansion
-- swaps it in (no ~1,200 parts made in the frame of the click), and the cheer waits for the bigger island's picture
prof.shells, prof.wood = 1e6, 1e5
H.push(p, 0.4)
local PS = H.smod("PlotService")
local guardNext = 0
while not select(2, PS.debugNext(1)) and guardNext < 40 do
	guardNext += 1
	E.run(0.25)
end
local nt, nready, swaps0 = PS.debugNext(1)
H.expect(nt == 2 and nready, "panels", "the next island is built ahead in the background", string.format("%s %s", tostring(nt), tostring(nready)))
local function statusSays(pattern)
	for _, d in p.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, pattern, 1, true) then
			return true
		end
	end
	return false
end
H.clickNamed(p, "Menu_build", { wait = 0.5 })
H.clickNamed(p, "Expand", { wait = 0 })
H.expect(prof.tier == 2, "panels", "Expand: the island grows", tostring(prof.tier))
local _, _, swaps1 = PS.debugNext(1)
H.expect(swaps1 == swaps0 + 1, "panels", "the expansion swaps in the island built ahead", string.format("%d -> %d", swaps0, swaps1))
local cheerAt = -1
for k = 1, 30 do
	E.run(0.05)
	if statusSays("Your island grew") then
		cheerAt = k * 0.05
		break
	end
end
H.expect(cheerAt > 0 and cheerAt <= 1.5, "panels", "the cheer comes with the bigger island's picture", string.format("%.2f s", cheerAt))
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
H.checkProfile(p, "panels")
H.checkMirror(p, "panels")

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
prof.quest = 1
for _, x in prof.pals do
	x.work = 0
end
prof.tree.t = 0
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestGo") ~= nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "the first quest's card: put a driftling to work, Go")
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "quests", "Go opens the Driftlings panel", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "QuestGo") == nil, "quests", "the card steps aside for the panel")
H.closePanel(p)
E.run(0.3)
local res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "a claim before the goal is met is refused", tostring(res.err))
-- (a driftling sent to help at a building of its knack, the way the Driftlings panel's Help does)
local CreaturesQ = H.sharedServer("Data.Creatures")
local BuildingsQ = H.sharedServer("Data.Buildings")
-- (whichever driftling lives in a hut: when nothing on the island suits its knack yet, a building that does goes up
-- first, as a player would build one)
do
	local suits = false
	for _, x in prof.pals do
		if x.home == 0 then
			continue
		end
		local d = CreaturesQ.byId[x.sp]
		for _, q in prof.plot.placed do
			local b = BuildingsQ.byId[q.id]
			if d and b and b.knack == d.knack then
				suits = true
			end
		end
	end
	local first = nil
	for _, x in prof.pals do
		if x.home ~= 0 and first == nil then
			first = x
		end
	end
	local d = first and CreaturesQ.byId[first.sp]
	if not suits and d then
		for _, b in BuildingsQ.list do
			if not suits and b.knack == d.knack and b.tier <= prof.tier and b.kind ~= "tree" then
				prof.shells, prof.wood = prof.shells + 5000, prof.wood + 500
				suits = place(b.id).ok
			end
		end
	end
end
local sent = false
for _, x in prof.pals do
	if x.home == 0 then
		continue
	end
	local d = CreaturesQ.byId[x.sp]
	for _, q in prof.plot.placed do
		local b = BuildingsQ.byId[q.id]
		if not sent and d and b and b.knack == d.knack then
			sent = H.req(p, "pal.work", { id = x.id, uid = q.uid }).ok
		end
	end
end
H.expect(sent, "quests", "a driftling sent to help at a building of its knack")
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "a driftling at work: Claim shows")
local shells0 = prof.shells
H.clickNamed(p, "QuestClaim", { wait = 0.5 })
H.expect(prof.quest == 2 and prof.shells >= shells0 + (Quests.list[1].reward.shells or 0), "quests", "Claim pays the reward and moves on", string.format("quest %d, shells %+d", prof.quest, prof.shells - shells0))
prof.quest = questAt("paths")
H.push(p, 0.5)
local paths = 0
for _, q in prof.plot.placed do
	if q.id == "dirtpath" or q.id == "stonepath" or q.id == "brickroad" or q.id == "marblewalk" then
		paths += 1
	end
end
if paths < 8 then
	H.clickNamed(p, "QuestGo", { wait = 0.5 })
	local BuildUIq = H.cmod(p, "UI.BuildUI")
	H.expect(H.inClient(p, BuildUIq.isOpen) and H.inClient(p, BuildUIq.debugState).tab == "path", "quests", "Go opens Build mode on the Paths tab")
	H.clickNamed(p, "BuildDone", { wait = 0.4 })
end
prof.quest = questAt("luck5")
local luck0 = prof.tree.luck
prof.tree.luck = 1
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "the tree's luck not up to 5: not done", tostring(res.err))
prof.tree.luck = luck0
prof.tut = 5
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_found", "quests", "no quests while the tips are on", tostring(res.err))
prof.tut = 0
prof.quest = #Quests.list + 1
H.push(p, 0.4)
H.expect(H.buttonNamed(p, "QuestGo") == nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "every quest done: no card")
prof.quest = 2
H.push(p, 0.3)
H.checkProfile(p, "quests")
H.checkMirror(p, "quests")

------------------------------------------------------------------ 9. a malicious client
E.phase = "malicious"
local function snap()
	local q = H.profile(p)
	return { shells = math.floor(q.shells), placed = #q.plot.placed, folk = #q.folk, pals = #q.pals, tier = q.tier, skin = q.founder.skin, tut = q.tut, luck = q.tree.luck, speed = q.tree.speed, sold = q.stats.sold }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
prof.food = 0 -- nothing grows while the snapshots are compared (no shops: the shells stand still)
for _, x in prof.folk do
	x.work = 0
end
-- (the tree waits while the pen is full: no new driftling while they are compared)
while not TreeL.waiting(prof) do
	TreeL.add(prof, "pebblit", {}).held = 1
end
H.push(p, 0.3)
local before = snap()
local ok, out = H.raw(p, "shells.give", { n = 1e9 })
expectRefused("an unknown action", ok, out, "unknown_action")
ok, out = H.rawArgs(p, nil)
expectRefused("no action", ok, out, "unknown_action")
ok, out = H.raw(p, "game.make", { a = 1, b = 2, c = 3 })
expectRefused("the old studio's actions", ok, out, "unknown_action")
ok, out = H.raw(p, "folk.work", { id = 0 / 0, uid = 1 })
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
ok, out = H.raw(p, "pal.house", { id = 424242, uid = 0, swap = 0 })
expectRefused("a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = H.treeUid(prof), swap = 0 })
expectRefused("the tree is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0 })
expectRefused("a move without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.sell", { id = 424242 })
expectRefused("selling a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "pen.sell", { r = 9 })
expectRefused("a rarity that isn't one", ok, out, "bad_payload")
ok, out = H.raw(p, "tree.upgrade", { what = "size" })
expectRefused("an upgrade the tree hasn't", ok, out, "bad_payload")
ok, out = H.raw(p, "tree.upgrade", {})
expectRefused("an upgrade of nothing", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.store", { i = (function()
	for i, q in prof.plot.placed do
		if q.id == "tree" then
			return i
		end
	end
	return 1
end)() })
expectRefused("clearing the tree away", ok, out, "fixed")
ok, out = H.raw(p, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 })
expectRefused("buying a second tree", ok, out, "bad_payload")
ok, out = H.raw(p, "folk.work", { id = 424242, uid = 0 })
expectRefused("a villager not there", ok, out, "not_found")
ok, out = H.raw(p, "founder.set", { skin = 9, hair = 1, style = 1, shirt = 1 })
expectRefused("a skin that does not exist", ok, out, "bad_payload")
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
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
H.checkMirror(p, "malicious")

------------------------------------------------------------------ 10. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets island 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their island is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own island")
H.expect(H.cmod(q, "Controllers.WorldView").rigCount() >= #prof.folk, "second", "the second client draws the first island's villagers", tostring(H.cmod(q, "Controllers.WorldView").rigCount()))
H.checkProfile(q, "second")
H.checkMirror(q, "second")
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
