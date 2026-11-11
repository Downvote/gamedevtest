-- The main simulation: a new island end to end through the real client and its UI (the campfire, the HUD, the
-- tips), building what the tips ask (food, a camp, a stall, a tent, a nest: the starting shells cover them), the days
-- turning (a villager moves in and takes a job, the stores grow), an expedition into the island's tide pool (a tap on
-- it opens its card: the party picked by itself, Explore; the founder walks to it and the blinds close, the place's
-- screen with the party dropping in, its stops and timed battles on the screen (timers, a snack, a skill), its
-- guardian clearing it, home with the loot and the founder in front of it), the Villagers, Driftlings and Index panels, the founder's looks, settings, then a
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
H.expect(prof.tier == 1 and prof.tut == 1 and #prof.folk == 0 and #prof.pals == 0 and #prof.plot.placed == 2, "join", "a new island, tips at step 1, nobody else yet (its two wild places)")
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
-- the background music: the island's tunes by the clock; the note in the corner switches it off and on (kept)
local AudioM = H.cmod(p, "Controllers.Audio")
local ms = H.inClient(p, AudioM.musicState)
H.expect((ms.mood == "day" or ms.mood == "night") and ms.on and ms.tracks >= 1, "join", "the island's music plays", string.format("%s %s %d", tostring(ms.mood), tostring(ms.on), ms.tracks))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "off" and not H.inClient(p, AudioM.musicState).on, "join", "the note switches the music off, kept with the profile", tostring(prof.settings.music))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "on" and H.inClient(p, AudioM.musicState).on, "join", "and on again", tostring(prof.settings.music))
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
H.expect(res.ok and #prof.plot.placed == 3 and prof.plot.placed[3].id == "patch", "build", "a veggie patch", tostring(res.err))
H.expect(math.abs(prof.shells - (sh0 - Buildings.byId.patch.shells)) < 1, "build", "paid for in shells", string.format("%s -> %s", sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to wood (food built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("lumber")
H.expect(res.ok and prof.tut == 3, "build", "a lumber camp: the tips move on to shells", tostring(res.err))
res = place("stall")
H.expect(res.ok and prof.tut == 4, "build", "a snack stall: the tips move on to a home", tostring(res.err))
local fxTent = #fx
res = place("tent")
H.expect(res.ok and prof.tut == 5, "build", "a tent: the tips move on to sailing", tostring(res.err))
H.expect(#prof.folk == 1 and prof.folk[1].work ~= 0, "build", "a castaway moves into the tent at once (no wait for a turn) and takes a job", tostring(#prof.folk))
local welcomed = false
for i = fxTent + 1, #fx do
	if fx[i].kind == "turn" and type(fx[i].movedIn) == "table" then
		welcomed = true
	end
end
H.expect(welcomed, "build", "the newcomer is announced (Fx turn with who moved in)")
res = place("nest")
H.expect(res.ok and prof.wood < Tuning.StartWood, "build", "a nest (shells and wood)", tostring(res.err))
H.expect(#prof.plot.placed == 7 and prof.shells >= 0, "build", "the starting shells paid for every building the tips ask for (beside the two wild places)", string.format("%d pieces, %s shells left", #prof.plot.placed, prof.shells))
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
H.expect(v ~= nil and #v.pieces == 7 and v.beds == 1 and v.nests == 2, "build", "the view: five pieces and two wild places, a bed, two nest slots", v and string.format("%d %d %d", #v.pieces, v.beds, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 7, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
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
-- the island's wild places (GAME_DESIGN 7): its tide pool tapped on the screen opens its card
H.expect(H.buttonNamed(p, "Menu_explore", true) == nil, "explore", "no Explore button: the wild places are on the island")
local Menus = H.cmod(p, "UI.Menus")
local WorldViewC = H.cmod(p, "Controllers.WorldView")
local PRc = H.cmod(p, "Pixel.PixelRenderer")
local poolQ = nil
for _, q in prof.plot.placed do
	if q.id == "wild_tidepool" then
		poolQ = q
	end
end
H.expect(poolQ ~= nil and poolQ.lvl == 1, "explore", "a level 1 tide pool on the new island")
local ox0, oz0 = H.sharedServer("Data.Street").origin(s.plot)
local poolW, poolD = H.sharedServer("Logic.Plot").footprint(poolQ.id, poolQ.rot)
local poolAt = E.v3(ox0 + poolQ.x + poolW / 2, H.sharedServer("Data.Street").LAWN_Y + 0.6, oz0 + poolQ.z + poolD / 2)
H.expect(H.inClient(p, function()
	return H.cmod(p, "UI.UIKit").canvas("World"):FindFirstChild("Site_" .. poolQ.uid) ~= nil
end), "explore", "its name and level over it")
E.raycastParts = true
H.inClient(p, function()
	local pos = PRc.project(poolAt)
	WorldViewC.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.raycastParts = nil
E.run(0.5)
H.expect(H.currentPanel(p) == "site" and H.inClient(p, Menus.chosen) == poolQ.uid, "explore", "a tap on it opens its card", tostring(H.currentPanel(p)))
if H.currentPanel(p) ~= "site" then
	H.inClient(p, H.cmod(p, "UI.UIKit").openPanel, "site", poolQ.uid)
	E.run(0.4)
end
H.expect(H.buttonNamed(p, "Explore") ~= nil and H.buttonNamed(p, "PouchUp", true) ~= nil, "explore", "the card: Explore and the snack pouch")
H.expect(H.buttonNamed(p, "Member_v" .. mika.id) ~= nil, "explore", "the villager can join the party")
H.expect(table.find(H.inClient(p, Menus.party), "v" .. mika.id) ~= nil, "explore", "the party's slots filled by themselves with the strongest (the villager)", table.concat(H.inClient(p, Menus.party), ","))
local food0 = prof.food
local Voyage = H.cmod(p, "UI.Voyage")
H.clickNamed(p, "Explore", { wait = 0.5 })
H.expect(s.exp ~= nil and s.exp.site == poolQ.uid and #s.exp.party == 2, "explore", "into the tide pool with the captain and the villager", tostring(s.exp and #s.exp.party))
H.expect(s.exp ~= nil and s.exp.isle.lvl == 1 and s.exp.isle.kind == 1 and string.find(s.exp.isle.name, "Tide Pool", 1, true) ~= nil, "explore", "a beach place of level 1, named for it", s.exp and s.exp.isle.name)
H.expect(math.abs(prof.food - (food0 - Tuning.Supplies * 2)) < 1.5, "explore", "supplies taken", string.format("%s -> %s", food0, prof.food))
H.expect(prof.tut == 6, "explore", "the tips move on to the first fight", tostring(prof.tut))
H.expect(s.away["v" .. mika.id] == true, "explore", "the villager is away (not working)")
-- the walk in: the founder walks to the place, the blinds close on its name
local vs = H.inClient(p, Voyage.debugState)
H.expect(vs.phase ~= "" and vs.dir == "out", "explore", "the walk to the place plays", tostring(vs.phase))
local EUI = H.cmod(p, "UI.ExpeditionUI")
H.expect(not H.inClient(p, EUI.isOpen), "explore", "the place's screen waits for it")
local phases: { [string]: boolean } = {}
for _ = 1, 160 do
	E.run(0.1)
	local ph = H.inClient(p, Voyage.debugState).phase
	phases[ph] = true
	if ph == "" then
		break
	end
end
H.expect(phases.walk and phases.close, "explore", "a walk, then the blinds", string.format("%s %s", tostring(phases.walk), tostring(phases.close)))
H.expect(H.inClient(p, EUI.isOpen) == true, "explore", "the place's screen opens after it")
local nodeAtLanding = s.exp and s.exp.node or 0
-- (the fights are quick: the first may be under way, or over, before the curtain's wait is: the tips' note is
-- watched for from the start)
local tips0 = prof.tut
local sawTip: { [number]: boolean } = {}
for _ = 1, math.floor((Tuning.StageWait + 3) / 0.2) do
	E.run(0.2)
	local d0 = H.inClient(p, EUI.debugState)
	if d0.tip then
		sawTip[prof.tut] = true
	end
end
local st = H.inClient(p, EUI.debugState)
H.expect(st.lifted and st.actors >= 2, "explore", "the curtain lifts on the party", string.format("%s %d", tostring(st.lifted), st.actors))
H.expect(not st.ship, "explore", "no boat: the party dropped in")
-- no Go on to click and no bar to wait on: between stops the next comes up at once (by now it may already be in a
-- battle: then its moves are up instead)
H.expect(H.buttonNamed(p, "GoOn") == nil and (s.exp == nil or s.exp.battle ~= nil or H.buttonNamed(p, "SailHome") ~= nil), "explore", "no Go on button (Sail home between stops)")
H.expect((s.exp ~= nil and s.exp.battle ~= nil and H.buttonNamed(p, "Act_skills") ~= nil) or H.buttons(p, "^AutoGo$", true)[1] == nil, "explore", "no bar to wait on between stops (or a battle's moves)")
H.expect(s.exp ~= nil and s.exp.node > nodeAtLanding, "explore", "the expedition went on by itself", string.format("%d -> %s", nodeAtLanding, tostring(s.exp and s.exp.node)))
-- walk the islet: every stop, every battle running by itself on the screen (a snack at a hurt wild one, a skill when
-- the points cover one), until its first guardian falls (the island never ends) or the party does
local Expedition = H.sharedServer("Logic.Expedition")
-- (the first snack befriends for certain: the tips' catching step is played through)
local BattleS = H.sharedServer("Logic.Battle")
local chance0 = BattleS.treatChance
local battles, treats, skillsUsed = 0, 0, 0
local sawTimers, sawRun = false, false
local lastBattle = nil
local steps = 0
while s.exp and not s.exp.over and (s.exp.beaten or 0) < 1 and steps < 900 do
	steps += 1
	local e = s.exp
	if e.battle then
		if e.battle ~= lastBattle then
			lastBattle = e.battle
			battles += 1
		end
		local dst = H.inClient(p, EUI.debugState)
		if dst.tip then
			sawTip[prof.tut] = true
		end
		sawTimers = sawTimers or dst.timers >= 2
		sawRun = sawRun or not e.battle.paused
		local hurt = nil
		for _, f in e.battle.foes do
			if f.hp > 0 and f.hp < f.maxHp * 0.5 then
				hurt = f
			end
		end
		if dst.busy or dst.aim or dst.menu or e.battle.paused then
			-- (an action under way, or still landing)
		elseif hurt and not e.battle.boss and treats < 3 and Expedition.room(prof) and e.snacks > 0 and (prof.tut ~= 6 or battles > 1) then
			treats += 1
			BattleS.treatChance = if treats == 1 then function()
				return 1
			end else chance0
			H.inClient(p, EUI.debugSnack, hurt.key)
			BattleS.treatChance = chance0
		elseif e.battle.sp >= 3 and skillsUsed < 2 then
			skillsUsed += 1
			H.inClient(p, EUI.debugSkill, "f", "cry")
		end
		E.run(0.4)
		-- (a won battle is a small alert: nothing to tap)
		H.expect(H.buttonNamed(p, "ResultOk") == nil or (s.exp and s.exp.over ~= nil), "explore", "no Onward card to tap after a win")
	else
		lastBattle = nil
		H.inClient(p, EUI.debugGo)
		E.run(0.2)
	end
end
BattleS.treatChance = chance0
H.expect(tips0 == 6 and sawTip[6] == true, "explore", "the tips' fighting step on the islet's screen in the first battle")
H.expect(sawTip[7] == true or sawTip[8] == true, "explore", "the catching step after it", string.format("%s %s", tostring(sawTip[7]), tostring(sawTip[8])))
H.expect(treats == 0 or prof.tut == 8, "explore", "a driftling caught with a snack: on to the last tip", string.format("tut %d, %d snacks", prof.tut, treats))
H.expect(sawTimers, "explore", "a timer over the fighters' heads")
H.expect(sawRun, "explore", "the battles run by themselves")
H.expect(skillsUsed >= 1, "explore", "a skill used from the screen (Rally Cry)", tostring(skillsUsed))
H.expect(battles >= 3, "explore", "battles fought through the UI", tostring(battles))
H.expect(s.exp ~= nil and (s.exp.over == "lost" or s.exp.over == "won"), "explore", "the guardian beaten (the place cleared, the trip over) or the party fallen", tostring(s.exp and s.exp.over))
local over = if s.exp and (s.exp.beaten or 0) >= 1 then "won" else s.exp and s.exp.over
local loot = s.exp and E.deepCopy(s.exp.loot)
local wild = s.exp and E.deepCopy(s.exp.isle.wild) or {}
H.expect(prof.stats.battles >= 1, "explore", "battles won counted", tostring(prof.stats.battles))
local sh1 = prof.shells
-- home: after a fall the card's Head home; after the guardian the Cleared card's Head home
if over == "lost" or over == "won" then
	-- (the card comes once the last fight has played out on the screen)
	E.runUntil(function()
		return H.buttonNamed(p, "ResultOk") ~= nil
	end, 15, 0.1)
	if over == "won" then
		H.expect(H.buttonNamed(p, "ResultOk") ~= nil and prof.islets == 1, "explore", "the Cleared card (the place no longer wild)", tostring(prof.islets))
		H.expect(string.sub(poolQ.id, 1, 5) == "done_", "explore", "the tide pool cleared", poolQ.id)
	end
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
-- home: the blinds open on the island with the founder in front of the place
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
H.expect(dirHome and homePhases.land, "explore", "home: the blinds open on the island, the founder cheers", tostring(homePhases.land))
local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
local front = E.v3(ox0 + poolQ.x + poolW / 2, 0, oz0 + poolQ.z + poolD + 1.5)
H.expect(root ~= nil and math.abs(root.Position.X - front.X) < 1 and math.abs(root.Position.Z - front.Z) < 1, "explore", "the founder stands in front of the place", root and tostring(root.Position))
local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
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
H.log("expedition: %s, %d battles, %d snacks, %d skills, %d friends, %d islands charted", tostring(over), battles, treats, skillsUsed, #prof.pals, prof.islets)
H.checkProfile(p, "explore")
H.checkMirror(p, "explore")

------------------------------------------------------------------ 6. a driftling friend for sure, its help
E.phase = "pals"
if #prof.pals == 0 then
	-- (the treats above may have missed: a friend is made on the server for the panels)
	table.insert(prof.pals, { id = prof.nextId, sp = "clawdle", lvl = 2, xp = 0, work = 0, muts = { "fierce2", "busy1" } })
	prof.nextId += 1
	prof.seen.clawdle = 2
	H.push(p, 0.4)
end
local pal = prof.pals[1]
H.clickNamed(p, "Menu_pals", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "pals", "the Driftlings panel opens")
H.expect(H.buttonNamed(p, "Help_" .. pal.id) ~= nil and H.buttonNamed(p, "Release_" .. pal.id) ~= nil, "pals", "Help and Release on its row")
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
for _, name in { "folk", "pals", "site", "index", "looks" } do
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
local sent = false
for _, x in prof.pals do
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
prof.quest = questAt("charts")
local islets0 = prof.islets
prof.islets = 0
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "no islands charted: not done", tostring(res.err))
prof.islets = islets0
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
ok, out = H.raw(p, "exp.start", { site = math.huge, party = "" })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = string.rep("a", 100000), x = 0, z = 0, rot = 0 })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "island.expand", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "island.expand", "x")
expectRefused("a string payload", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { site = 1, party = "v1,v1,v1,v1" })
expectRefused("a party of four", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { site = 1, party = "x9" })
expectRefused("a party member that is not one", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { site = H.firstSite(prof), party = "v424242" })
expectRefused("a villager not on the island", ok, out, "not_found")
ok, out = H.raw(p, "exp.start", { site = 424242, party = "" })
expectRefused("a wild place that isn't there", ok, out, "not_found")
ok, out = H.raw(p, "boat.upgrade", {})
expectRefused("the boat (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "exp.start", { isle = 99, party = "" })
expectRefused("the sea chart's island (gone)", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { lvl = 1, party = "" })
expectRefused("the old slider's level", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { islet = 1, party = "" })
expectRefused("the old islet field", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.next", {})
expectRefused("a step with no expedition", ok, out, "no_exp")
ok, out = H.raw(p, "exp.act", { act = "fight", target = "" })
expectRefused("the old battle move", ok, out, "unknown_action")
ok, out = H.raw(p, "exp.snack", { target = "w1" })
expectRefused("a snack with no expedition", ok, out, "no_exp")
ok, out = H.raw(p, "exp.snack", { target = "f" })
expectRefused("a snack at the leader", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.skill", { who = "w1", skill = "cry", target = "" })
expectRefused("a wild one's skill", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.skill", { who = "f", skill = "cry", target = "" })
expectRefused("a skill with no expedition", ok, out, "no_exp")
ok, out = H.raw(p, "exp.pause", { on = 1 })
expectRefused("a pause that is not on or off", ok, out, "bad_payload")
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
