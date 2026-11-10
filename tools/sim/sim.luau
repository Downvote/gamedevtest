-- The main simulation: a new island end to end through the real client and its UI (the castaway's hut, the HUD, the
-- tips), building food, a tent, a nest and a camp, the days turning (a villager moves in and takes a job, the stores
-- grow), an expedition from the Explore panel (the party picked, Set sail, the islet's screen, its stops and battles
-- played through ExpeditionUI, a treat, home with the loot), the Villagers, Driftlings and Index panels, the
-- founder's looks, settings, then a malicious client, then a second player. Every check is an H.expect; the SIM
-- REPORT must show 0 findings and 0 errors.
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
H.expect(prof.tier == 1 and prof.tut == 1 and #prof.folk == 0 and #prof.pals == 0 and #prof.plot.placed == 0, "join", "the castaway's hut, tips at step 1, nobody else yet")
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local officeF = static and static:FindFirstChild("Office")
local office = officeF and officeF:FindFirstChild("Office")
H.expect(office ~= nil and office:GetAttribute("Tier") == 1, "join", "the hut is built under Plots.Plot_1.Static.Office")
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
H.expect(prof.tut == 2, "build", "the tips move on (food built)", tostring(prof.tut))
res = place("tent")
H.expect(res.ok and prof.tut == 3, "build", "a tent: the tips move on", tostring(res.err))
res = place("nest")
H.expect(res.ok and prof.wood < Tuning.StartWood, "build", "a nest (shells and wood)", tostring(res.err))
prof.shells += 200
res = place("lumber")
H.expect(res.ok, "build", "a lumber camp", tostring(res.err))
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
H.expect(v ~= nil and #v.pieces == 4 and v.beds == 1 and v.nests == 2, "build", "the view: four pieces, a bed, two nest slots", v and string.format("%d %d %d", #v.pieces, v.beds, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 4, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
H.checkProfile(p, "build")
H.checkMirror(p, "build")

------------------------------------------------------------------ 3. the days
E.phase = "days"
local day0 = prof.day
local dayFx = 0
local f0 = #fx
E.runUntil(function()
	return prof.day > day0
end, Tuning.DaySeconds + 2, 0.1)
E.run(0.3)
for i = f0 + 1, #fx do
	if fx[i].kind == "day" then
		dayFx += 1
	end
end
H.expect(prof.day == day0 + 1 and dayFx == 1, "days", "a day turns every DaySeconds (Fx day)", string.format("day %d, %d fx", prof.day, dayFx))
H.expect(#prof.folk == 1, "days", "a castaway moved into the tent", tostring(#prof.folk))
local mika = prof.folk[1]
H.expect(mika ~= nil and mika.work ~= 0, "days", "and took a job straight away", tostring(mika and mika.work))
local ticks = 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
	end
end
H.expect(ticks >= Tuning.DaySeconds - 3, "days", "the stores reach the client every second (Fx tick)", tostring(ticks))
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
H.expect(H.buttonNamed(p, "Islet_1") ~= nil, "explore", "Pebble Beach is listed")
H.expect(H.buttonNamed(p, "Member_v" .. mika.id) ~= nil, "explore", "the villager can join the party")
H.clickNamed(p, "Member_v" .. mika.id, { wait = 0.3 })
local food0 = prof.food
H.clickNamed(p, "SetSail", { wait = 1 })
H.expect(s.exp ~= nil and s.exp.islet == 1 and #s.exp.party == 2, "explore", "the expedition set sail with the captain and the villager", tostring(s.exp and #s.exp.party))
H.expect(math.abs(prof.food - (food0 - Tuning.Supplies * 2)) < 1.5, "explore", "supplies taken", string.format("%s -> %s", food0, prof.food))
H.expect(prof.tut == 4, "explore", "the tips move on", tostring(prof.tut))
H.expect(s.away["v" .. mika.id] == true, "explore", "the villager is away (not working)")
local EUI = H.cmod(p, "UI.ExpeditionUI")
H.expect(H.inClient(p, EUI.isOpen) == true, "explore", "the islet's screen opens")
E.run(Tuning.StageWait + 1)
local st = H.inClient(p, EUI.debugState)
H.expect(st.lifted and st.actors >= 2, "explore", "the curtain lifts on the party", string.format("%s %d", tostring(st.lifted), st.actors))
H.expect(H.buttonNamed(p, "GoOn") ~= nil and H.buttonNamed(p, "SailHome") ~= nil, "explore", "Go on and Sail home")
-- walk the islet: every stop, every battle fought (a treat when a wild one is hurt), until the guardian or a fall
local Expedition = H.sharedServer("Logic.Expedition")
local battles, treats, guard = 0, 0, 0
local steps = 0
while s.exp and not s.exp.over and steps < 80 do
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
		-- a result card: Onward
		E.run(0.2)
		if H.buttonNamed(p, "ResultOk") and s.exp and not s.exp.over then
			H.clickNamed(p, "ResultOk", { wait = 0.2 })
		end
	elseif e.node < #e.nodes then
		H.inClient(p, EUI.debugGo)
	else
		break
	end
	E.run(0.2)
end
H.expect(battles >= 3, "explore", "battles fought through the UI", tostring(battles))
H.expect(s.exp ~= nil and s.exp.over ~= nil, "explore", "the islet ends: the guardian beaten or the party fallen", tostring(s.exp and s.exp.over))
local over = s.exp and s.exp.over
local loot = s.exp and E.deepCopy(s.exp.loot)
H.expect(prof.stats.battles >= 1, "explore", "battles won counted", tostring(prof.stats.battles))
local sh1 = prof.shells
H.clickNamed(p, "ResultOk", { wait = 0.2 })
E.run(0.3)
if H.buttonNamed(p, "SailHome") then
	H.clickNamed(p, "SailHome", { wait = 1 })
end
E.run(0.5)
H.expect(s.exp == nil and next(s.away) == nil, "explore", "home: the expedition over, everyone back")
H.expect(not H.inClient(p, EUI.isOpen), "explore", "the islet's screen closed")
if loot then
	local k = if over == "lost" then 0.5 else 1
	H.expect(prof.shells >= sh1 + math.floor(loot.shells * k) - 1, "explore", "the loot came home", string.format("%s -> %s (+%s)", sh1, prof.shells, loot.shells))
end
if over == "won" then
	H.expect(prof.islets == 1 and prof.stats.cleared == 1, "explore", "Pebble Beach cleared: Mossgrove opens")
end
H.expect(prof.seen.pebblit or prof.seen.clawdle or prof.seen.gullfin, "explore", "the islet's driftlings are in the Index")
H.log("expedition: %s, %d battles, %d treats, %d friends, %d islets", tostring(over), battles, treats, #prof.pals, prof.islets)
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
local lodgeF = E.workspace.Plots.Plot_1:FindFirstChild("Static") and E.workspace.Plots.Plot_1.Static:FindFirstChild("Office")
local lodge = lodgeF and lodgeF:FindFirstChild("Office")
H.expect(lodge ~= nil and lodge:GetAttribute("Tier") == 2, "panels", "the lodge is rebuilt bigger", tostring(lodge and lodge:GetAttribute("Tier")))
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
ok, out = H.raw(p, "exp.start", { islet = math.huge, party = "" })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = string.rep("a", 100000), x = 0, z = 0, rot = 0 })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "island.expand", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "island.expand", "x")
expectRefused("a string payload", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { islet = 1, party = "v1,v1,v1,v1" })
expectRefused("a party of four", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { islet = 1, party = "x9" })
expectRefused("a party member that is not one", ok, out, "bad_payload")
ok, out = H.raw(p, "exp.start", { islet = 1, party = "v424242" })
expectRefused("a villager not on the island", ok, out, "not_found")
ok, out = H.raw(p, "exp.start", { islet = 5, party = "" })
expectRefused("an islet not open yet", ok, out, "locked")
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
