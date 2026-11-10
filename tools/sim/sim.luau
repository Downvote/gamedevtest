-- The main simulation: a new island end to end through the real client and its UI (the campfire, the HUD, the
-- tips), building what the tips ask (food, a camp, a stall, a tent, a nest: the starting shells cover them), the days
-- turning (a villager moves in and takes a job, the stores grow), an expedition from the Explore panel (the level
-- slider, the party picked, Set sail, the sailing cutscene and the boat leaving the pier, the islet's screen with the
-- boat bringing the party ashore, its stops and battles played through ExpeditionUI, a treat, home with the loot and
-- the return voyage to the pier), the Villagers, Driftlings and Index panels, the founder's looks, settings, then a
-- malicious client, then a second player. Every check is an H.expect; the SIM REPORT must show 0 findings and 0
-- errors.
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
H.expect(prof.tier == 1 and prof.tut == 1 and #prof.folk == 0 and #prof.pals == 0 and #prof.plot.placed == 0, "join", "a new island, tips at step 1, nobody else yet")
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local land1 = static and static:FindFirstChild("Land")
H.expect(land1 ~= nil and land1:FindFirstChild("Land") ~= nil and static:FindFirstChild("Office") == nil, "join", "the island is built under Plots.Plot_1.Static.Land (no house)")
H.expect(land1 ~= nil and land1:FindFirstChild("FireStone", true) ~= nil and land1:FindFirstChild("JettyPlank", true) ~= nil, "join", "its plaza's campfire and the jetty")
H.expect(plot1 and plot1:GetAttribute("StudioName") == "Pixel's Isle", "join", "the island's name", tostring(plot1 and plot1:GetAttribute("StudioName")))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there")
for _, n in { "Menu_build", "Menu_folk", "Menu_pals", "Menu_explore", "Menu_index", "Menu_looks" } do
	H.expect(H.buttonNamed(p, n) ~= nil, "join", "the menu bar's " .. n)
end
H.expect(#H.buttons(p, "^Food first", true) == 0, "join", "(tips are text, not buttons)")
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
local sh0 = prof.shells
local res = place("patch")
H.expect(res.ok and #prof.plot.placed == 1 and prof.plot.placed[1].id == "patch", "build", "a veggie patch", tostring(res.err))
H.expect(math.abs(prof.shells - (sh0 - Buildings.byId.patch.shells)) < 1, "build", "paid for in shells", string.format("%s -> %s", sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to wood (food built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("lumber")
H.expect(res.ok and prof.tut == 3, "build", "a lumber camp: the tips move on to shells", tostring(res.err))
res = place("stall")
H.expect(res.ok and prof.tut == 4, "build", "a snack stall: the tips move on to a home", tostring(res.err))
res = place("tent")
H.expect(res.ok and prof.tut == 5, "build", "a tent: the tips move on to sailing", tostring(res.err))
res = place("nest")
H.expect(res.ok and prof.wood < Tuning.StartWood, "build", "a nest (shells and wood)", tostring(res.err))
H.expect(#prof.plot.placed == 5 and prof.shells >= 0, "build", "the starting shells paid for every building the tips ask for", string.format("%d pieces, %s shells left", #prof.plot.placed, prof.shells))
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
H.expect(v ~= nil and #v.pieces == 5 and v.beds == 1 and v.nests == 2, "build", "the view: five pieces, a bed, two nest slots", v and string.format("%d %d %d", #v.pieces, v.beds, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 5, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
H.checkProfile(p, "build")
H.checkMirror(p, "build")

------------------------------------------------------------------ 3. turns and days
E.phase = "days"
local day0 = prof.day
local turnFx = 0
local f0 = #fx
E.runUntil(function()
	return #prof.folk >= 1
end, Tuning.TurnSeconds + 2, 0.1)
E.run(0.3)
for i = f0 + 1, #fx do
	if fx[i].kind == "turn" then
		turnFx += 1
	end
end
H.expect(turnFx == 1 and prof.day == day0, "days", "a turn ends every TurnSeconds (Fx turn), not a day", string.format("%d fx, day %d", turnFx, prof.day))
H.expect(#prof.folk == 1, "days", "a castaway moved into the tent", tostring(#prof.folk))
local mika = prof.folk[1]
H.expect(mika ~= nil and mika.work ~= 0, "days", "and took a job straight away", tostring(mika and mika.work))
local ticks = 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
	end
end
H.expect(ticks >= Tuning.TurnSeconds - 3, "days", "the stores reach the client every second (Fx tick)", tostring(ticks))
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
H.expect(WV.ownRigCount() == 1, "days", "the villager walks the island", tostring(WV.ownRigCount()))
local r = Island.rates(prof, s.away)
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

------------------------------------------------------------------ 5. an expedition through the UI
E.phase = "explore"
prof.food = 200
H.push(p, 0.4)
H.clickNamed(p, "Menu_explore", { wait = 0.5 })
H.expect(H.currentPanel(p) == "explore", "explore", "the Explore panel opens")
-- the sea chart: an island in the first boat's range picked; a far one refused; the boat upgraded
local Menus = H.cmod(p, "UI.Menus")
local Chart = H.sharedServer("Logic.Chart")
H.expect(prof.boat == 1 and prof.sea >= 1, "explore", "the first boat and the player's own sea")
local chosen = H.inClient(p, Menus.chosen)
H.expect(chosen >= 1 and Chart.reachable(prof, chosen), "explore", "an island in the boat's range picked at first", tostring(chosen))
H.expect(H.buttonNamed(p, "Isle_1") ~= nil and H.buttonNamed(p, "BoatUp") ~= nil, "explore", "the chart's islands to tap, the boat's upgrade")
local farId = nil
for _, c in Chart.islands(prof.sea) do
	if farId == nil and not Chart.reachable(prof, c.id) and H.buttonNamed(p, "Isle_" .. c.id) then
		farId = c.id
	end
end
if farId then
	H.clickNamed(p, "Isle_" .. farId, { wait = 0.2 })
	H.expect(H.inClient(p, Menus.chosen) == chosen, "explore", "an island past the boat's range can't be picked")
end
local cost = Chart.boatCost(1)
local shKeep, woKeep = prof.shells, prof.wood
prof.shells, prof.wood = cost.shells + 10, cost.wood + 10
H.push(p, 0.3)
H.clickNamed(p, "BoatUp", { wait = 0.5 })
local road = E.workspace.Plots.Street:FindFirstChild("Road_1")
H.expect(prof.boat == 2 and prof.shells < 60 and prof.wood < 60, "explore", "the boat upgraded for shells and wood", string.format("%d %s %s", prof.boat, prof.shells, prof.wood))
H.expect(road ~= nil and road:FindFirstChild("Boat") ~= nil and road.Boat:GetAttribute("Level") == 2, "explore", "a bigger boat at the pier")
prof.shells, prof.wood = shKeep, woKeep
H.push(p, 0.3)
H.clickNamed(p, "Isle_1", { wait = 0.3 })
H.expect(H.inClient(p, Menus.chosen) == 1, "explore", "the nearest island picked on the chart")
H.expect(H.buttonNamed(p, "Member_v" .. mika.id) ~= nil, "explore", "the villager can join the party")
H.clickNamed(p, "Member_v" .. mika.id, { wait = 0.3 })
local food0 = prof.food
local Voyage = H.cmod(p, "UI.Voyage")
H.expect(road ~= nil and road:FindFirstChild("Boat") ~= nil, "explore", "the expedition boat moored at the pier")
H.clickNamed(p, "SetSail", { wait = 0.5 })
H.expect(s.exp ~= nil and s.exp.isle.id == 1 and #s.exp.party == 2, "explore", "the expedition set sail to the chart's first island with the captain and the villager", tostring(s.exp and #s.exp.party))
H.expect(s.exp ~= nil and s.exp.isle.lvl == Chart.islands(prof.sea)[1].lvl and s.exp.isle.kind == 1 and #s.exp.isle.name > 3, "explore", "a beach near home, of its distance's level, with a name", s.exp and s.exp.isle.name)
H.expect(math.abs(prof.food - (food0 - Tuning.Supplies * 2)) < 1.5, "explore", "supplies taken", string.format("%s -> %s", food0, prof.food))
H.expect(prof.tut == 6, "explore", "the tips move on to the last", tostring(prof.tut))
H.expect(s.away["v" .. mika.id] == true, "explore", "the villager is away (not working)")
-- the cutscene: the founder walks to the pier and boards, the boat sails off, the blinds close on the island
local vs = H.inClient(p, Voyage.debugState)
H.expect(vs.phase ~= "" and vs.away, "explore", "the sailing cutscene plays", tostring(vs.phase))
H.expect(road ~= nil and road:FindFirstChild("Boat") == nil, "explore", "the boat leaves the pier")
local EUI = H.cmod(p, "UI.ExpeditionUI")
H.expect(not H.inClient(p, EUI.isOpen), "explore", "the islet's screen waits for the cutscene")
local phases: { [string]: boolean } = {}
for _ = 1, 160 do
	E.run(0.1)
	local ph = H.inClient(p, Voyage.debugState).phase
	phases[ph] = true
	if ph == "" then
		break
	end
end
H.expect(phases.walk and phases.hop and phases.sail, "explore", "walk, hop aboard, sail", string.format("%s %s %s", tostring(phases.walk), tostring(phases.hop), tostring(phases.sail)))
H.expect(H.inClient(p, EUI.isOpen) == true, "explore", "the islet's screen opens after it")
local nodeAtLanding = s.exp and s.exp.node or 0
E.run(Tuning.StageWait + 3)
local st = H.inClient(p, EUI.debugState)
H.expect(st.lifted and st.actors >= 2, "explore", "the curtain lifts on the party", string.format("%s %d", tostring(st.lifted), st.actors))
H.expect(st.arrived, "explore", "the boat brought them ashore", tostring(st.arrived))
-- no Go on to click: between stops a bar fills and the party walks on by itself (by now it may already be in a
-- battle: then its moves are up instead)
H.expect(H.buttonNamed(p, "GoOn") == nil and (s.exp == nil or s.exp.battle ~= nil or H.buttonNamed(p, "SailHome") ~= nil), "explore", "no Go on button (Sail home between stops)")
H.expect((s.exp ~= nil and s.exp.battle ~= nil and H.buttonNamed(p, "Act_fight") ~= nil) or H.buttons(p, "^AutoGo$", true)[1] ~= nil, "explore", "the next stop's bar (or a battle's moves)")
H.expect(s.exp ~= nil and s.exp.node > nodeAtLanding, "explore", "the expedition went on by itself", string.format("%d -> %s", nodeAtLanding, tostring(s.exp and s.exp.node)))
-- walk the islet: every stop, every battle fought (a treat when a wild one is hurt), until its first guardian falls (the
-- island never ends) or the party does
local Expedition = H.sharedServer("Logic.Expedition")
local battles, treats, guard = 0, 0, 0
local steps = 0
while s.exp and not s.exp.over and (s.exp.beaten or 0) < 1 and steps < 80 do
	steps += 1
	local e = s.exp
	if e.battle then
		battles += 1
		local hurt = nil
		for _, f in e.battle.foes do
			if f.hp > 0 and f.hp < f.maxHp * 0.5 then
				hurt = f
			end
		end
		if hurt and not e.battle.boss and treats < 3 and Expedition.room(prof) then
			treats += 1
			H.inClient(p, EUI.debugAct, "treat")
		elseif guard < 1 then
			guard += 1
			H.inClient(p, EUI.debugAct, "guard")
		else
			H.inClient(p, EUI.debugAct, "fight")
		end
		-- (a won battle is a small alert: nothing to tap)
		E.run(0.2)
		H.expect(H.buttonNamed(p, "ResultOk") == nil or (s.exp and s.exp.over ~= nil), "explore", "no Onward card to tap after a win")
	else
		H.inClient(p, EUI.debugGo)
	end
	E.run(0.2)
end
H.expect(battles >= 3, "explore", "battles fought through the UI", tostring(battles))
H.expect(s.exp ~= nil and (s.exp.over == "lost" or (s.exp.beaten or 0) >= 1), "explore", "the first guardian beaten (the path goes on) or the party fallen", tostring(s.exp and s.exp.over))
local over = if s.exp and (s.exp.beaten or 0) >= 1 then "won" else s.exp and s.exp.over
local loot = s.exp and E.deepCopy(s.exp.loot)
local wild = s.exp and E.deepCopy(s.exp.isle.wild) or {}
H.expect(prof.stats.battles >= 1, "explore", "battles won counted", tostring(prof.stats.battles))
local sh1 = prof.shells
-- home: after a fall the card's Sail home; after the guardian the party could go on: sail home from the screen
if over == "lost" then
	H.clickNamed(p, "ResultOk", { wait = 0.2 })
else
	E.runUntil(function()
		return not H.inClient(p, EUI.debugState).busy
	end, 20, 0.1)
	H.inClient(p, EUI.debugHome)
end
E.run(0.8)
H.expect(s.exp == nil and next(s.away) == nil, "explore", "home: the expedition over, everyone back")
H.expect(not H.inClient(p, EUI.isOpen), "explore", "the islet's screen closed behind its curtain")
-- the voyage home: the blinds open on the sea, the boat sails in and moors, the founder hops onto the pier
local homePhases: { [string]: boolean } = {}
local dirHome = false
for _ = 1, 160 do
	local d = H.inClient(p, Voyage.debugState)
	homePhases[d.phase] = true
	dirHome = dirHome or d.dir == "home"
	if d.phase == "" and dirHome then
		break
	end
	E.run(0.1)
end
H.expect(dirHome and homePhases.arrive and homePhases.hop and homePhases.land, "explore", "the voyage home: the boat sails in, the founder hops ashore", string.format("%s %s %s", tostring(homePhases.arrive), tostring(homePhases.hop), tostring(homePhases.land)))
H.expect(road ~= nil and road:FindFirstChild("Boat") ~= nil and not H.inClient(p, Voyage.debugState).away, "explore", "the boat is back at the pier")
local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
local ox1, oz1 = H.sharedServer("Data.Street").origin(1)
H.expect(root ~= nil and root.Position.Z - oz1 > H.sharedServer("Data.Street").BOARD.z1, "explore", "the founder stands on the pier", root and tostring(root.Position))
-- free to walk off: clear of the pier's walls (a character put inside one is stuck) and able to move again
local pr = H.sharedServer("Data.Street").pier()
local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
H.expect(root ~= nil and root.Position.X - ox1 > pr.x0 + 1.2 and root.Position.X - ox1 < pr.x1 - 1.2 and root.Position.Z - oz1 < pr.z1 - 1.2, "explore", "home: the founder clear of the pier's walls", root and tostring(root.Position))
H.expect(hum ~= nil and hum.WalkSpeed > 0 and hum.JumpHeight > 0, "explore", "home: the founder can walk again", hum and string.format("%s %s", hum.WalkSpeed, hum.JumpHeight))
H.expect(H.buttonNamed(p, "Menu_build") ~= nil, "explore", "the HUD is back")
if loot then
	local k = if over == "lost" then 0.5 else 1
	H.expect(prof.shells >= sh1 + math.floor(loot.shells * k) - 1, "explore", "the loot came home", string.format("%s -> %s (+%s)", sh1, prof.shells, loot.shells))
end
if over == "won" then
	H.expect(prof.islets == 1 and prof.stats.cleared == 1, "explore", "the island charted")
end
local met = false
for _, sp in wild do
	met = met or (prof.seen[sp] or 0) > 0
end
H.expect(met, "explore", "the island's driftlings are in the Index")
H.log("expedition: %s, %d battles, %d treats, %d friends, %d islands charted", tostring(over), battles, treats, #prof.pals, prof.islets)
H.checkProfile(p, "explore")
H.checkMirror(p, "explore")

------------------------------------------------------------------ 6. a driftling friend for sure, its help
E.phase = "pals"
if #prof.pals == 0 then
	-- (the treats above may have missed: a friend is made on the server for the panels)
	table.insert(prof.pals, { id = prof.nextId, sp = "clawdle", lvl = 2, xp = 0, work = 0 })
	prof.nextId += 1
	prof.seen.clawdle = 2
	H.push(p, 0.4)
end
local pal = prof.pals[1]
H.clickNamed(p, "Menu_pals", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "pals", "the Driftlings panel opens")
H.expect(H.buttonNamed(p, "Help_" .. pal.id) ~= nil and H.buttonNamed(p, "Release_" .. pal.id) ~= nil, "pals", "Help and Release on its row")
H.clickNamed(p, "Help_" .. pal.id, { wait = 0.4 })
H.expect(H.buttonNamed(p, "Go_0", true) ~= nil, "pals", "the help picker opens (Rest at least)")
H.closePanel(p)
-- releasing takes two taps
local nPals = #prof.pals
H.openPanel(p, "pals")
E.run(0.3)
H.clickNamed(p, "Release_" .. pal.id, { wait = 0.3 })
H.expect(#prof.pals == nPals, "pals", "one tap only asks Sure?")
H.closePanel(p)

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
for _, name in { "folk", "pals", "explore", "index", "looks" } do
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
-- expanding the island from the build tray
prof.shells, prof.wood = 1e6, 1e5
H.push(p, 0.4)
H.clickNamed(p, "Menu_build", { wait = 0.5 })
H.clickNamed(p, "Expand", { wait = 0.8 })
H.expect(prof.tier == 2, "panels", "Expand: the island grows", tostring(prof.tier))
E.run(0.5)
local st2 = E.workspace.Plots.Plot_1:FindFirstChild("Static")
H.expect(st2 ~= nil and st2:GetAttribute("Built") == 2, "panels", "the island is rebuilt bigger", tostring(st2 and st2:GetAttribute("Built")))
H.clickNamed(p, "BuildDone", { wait = 0.4 })
H.checkProfile(p, "panels")
H.checkMirror(p, "panels")

------------------------------------------------------------------ 9. a malicious client
E.phase = "malicious"
local function snap()
	local q = H.profile(p)
	return { shells = math.floor(q.shells), placed = #q.plot.placed, folk = #q.folk, pals = #q.pals, tier = q.tier, skin = q.founder.skin, tut = q.tut, exp = H.session(p).exp ~= nil, islets = q.islets }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
prof.food = 0 -- nothing grows while the snapshots are compared (no shops: the shells stand still)
for _, x in prof.folk do
	x.work = 0
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
ok, out = H.raw(p, "exp.start", { isle = math.huge, party = "" })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = string.rep("a", 100000), x = 0, z = 0, rot = 0 })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "island.expand", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "island.expand", "x")
expectRefused("a string payload", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { isle = 1, party = "v1,v1,v1,v1" })
expectRefused("a party of four", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { isle = 1, party = "x9" })
expectRefused("a party member that is not one", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { isle = 1, party = "v424242" })
expectRefused("a villager not on the island", ok, out, "not_found")
ok, out = H.raw(p, "exp.start", { isle = H.sharedServer("Config.Tuning").ChartIslands, party = "" })
expectRefused("an island past the boat's range", ok, out, "far")
ok, out = H.raw(p, "exp.start", { isle = 99, party = "" })
expectRefused("an island off the chart", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { lvl = 1, party = "" })
expectRefused("the old slider's level", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { islet = 1, party = "" })
expectRefused("the old islet field", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.next", {})
expectRefused("a step with no expedition", ok, out, "no_exp")
ok, out = H.raw(p, "exp.act", { act = "nuke", target = "" })
expectRefused("an unknown battle move", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.act", { act = "fight", target = "" })
expectRefused("a battle with no expedition", ok, out, "no_exp")
ok, out = H.raw(p, "folk.work", { id = 424242, uid = 0 })
expectRefused("a villager not there", ok, out, "not_found")
ok, out = H.raw(p, "pal.release", { id = 424242 })
expectRefused("a driftling not there", ok, out, "not_found")
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
