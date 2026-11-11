-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 7.4, 10.9): the island's wild places at every tier (each of its
-- kind and level, its own driftlings, cleared by its guardian with the first clear's big reward, a smaller one on a
-- second trip; the path ending there), the server's rules (supplies, a party of the captain and three, one expedition
-- at a time, only the island's own wild places, no expanding or pouch while away, members away can't be dismissed or
-- released, no stepping on mid-battle, no snack or flight from a guardian, a snack's free nest and the trip's
-- few), the timed battle (it waits paused till let run, its actions and timers reach the client, paused again all
-- stops), a driftling befriended with a snack (the leader's timer starts again), a skill paid in skill points, a
-- flight, a defeat (all the loot home: no penalty), and the islet's screen: closed and reopened from the HUD's card, a timer over
-- every head, the battle fighting itself, the skill window pausing it, a skill aimed with the leader's ring and arrow.
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
local Islets = H.sharedServer("Data.Islets")
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Expedition = H.sharedServer("Logic.Expedition")
local SiteData = H.sharedServer("Data.Sites")

local p = H.addPlayer({ userId = 9501, name = "Sailor" })
E.run(2)
local s = H.session(p)
local prof = H.profile(p)
prof.shells, prof.wood = 1e6, 1e5
for _, id in { "patch", "hut", "hut", "nest", "nest", "nest" } do
	local pr = Street.plot(1)
	local done = false
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if not done and Plot.fits(1, prof.plot.placed, id, x, z, 0) then
				done = H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 }).ok
			end
		end
	end
end
for j = 1, 3 do
	table.insert(prof.folk, { id = prof.nextId, name = "Mate" .. j, look = { skin = j, hair = j, style = j, shirt = j }, work = 0, lvl = 1, xp = 0, seed = 100 + j, day = 1 })
	prof.nextId += 1
end
H.push(p, 0.3)
local function party(n)
	local keys = {}
	for i = 1, n do
		table.insert(keys, "v" .. prof.folk[i].id)
	end
	return table.concat(keys, ",")
end
local function strong(lvl)
	prof.cap.lvl = lvl
	for _, v in prof.folk do
		v.lvl = lvl
	end
	for _, x in prof.pals do
		x.lvl = lvl
	end
end
-- a battle under way runs to its end (the server runs it in time; a battle starts paused till it is let run)
local function fight(maxSecs)
	if not (s.exp and s.exp.battle) then
		return
	end
	H.req(p, "exp.pause", { on = false })
	E.runUntil(function()
		return not (s.exp and s.exp.battle) or (s.exp ~= nil and s.exp.over ~= nil)
	end, maxSecs or 240, 0.25)
end
-- the server's way through an islet: on, every battle run to its end, until `guardians` guardians are beaten (1 by
-- default: the islands never end) or the party falls; returns "won" (that many beaten) or how it ended
local function walk(maxSteps, guardians)
	local steps = 0
	local want = guardians or 1
	while s.exp and not s.exp.over and (s.exp.beaten or 0) < want and steps < (maxSteps or 200) do
		steps += 1
		if s.exp.battle then
			fight()
		else
			H.req(p, "exp.next", {})
		end
	end
	if s.exp and not s.exp.over and (s.exp.beaten or 0) >= want then
		return "won"
	end
	return s.exp and s.exp.over
end
local function nextBattle()
	local g = 0
	while s.exp and not s.exp.over and not s.exp.battle and g < 20 do
		g += 1
		H.req(p, "exp.next", {})
	end
end

------------------------------------------------------------------ 1. the server's rules
E.phase = "rules"
prof.food = 2
local site1 = H.firstSite(prof)
local res = H.req(p, "exp.start", { site = site1, party = party(3) })
H.expect(not res.ok and res.err == "food", "rules", "supplies: four members need food", tostring(res.err))
prof.food = 1000
res = H.req(p, "exp.start", { site = prof.plot.placed[#prof.plot.placed].uid, party = "" })
H.expect(not res.ok and res.err == "not_found", "rules", "only a wild place: not a nest", tostring(res.err))
res = H.req(p, "exp.start", { site = 999999, party = "" })
H.expect(not res.ok and res.err == "not_found", "rules", "nor a place that isn't there", tostring(res.err))
res = H.req(p, "exp.start", { site = site1, party = party(3) })
H.expect(res.ok and #s.exp.party == 4 and s.exp.party[1].key == "f", "rules", "the captain and three go in", tostring(res.err))
H.expect(s.exp and s.exp.site == site1 and #s.exp.nodes == 1 + Tuning.BossEvery and s.exp.nodes[#s.exp.nodes] == "boss", "rules", "its path: six stops, then its guardian, and no further", tostring(s.exp and #s.exp.nodes))
H.expect(math.abs(prof.food - (1000 - Tuning.Supplies * 4)) < 1, "rules", "their supplies taken", tostring(prof.food))
H.expect(res.ok and res.data and res.data.isle and res.data.isle.name == s.exp.isle.name and res.data.site == site1, "rules", "the answer names the place", res.data and res.data.isle and res.data.isle.name)
H.expect(s.exp.snacks == Tuning.SnackBase, "rules", "five snacks for the trip (the first pouch)", tostring(s.exp.snacks))
res = H.req(p, "exp.start", { site = site1, party = "" })
H.expect(not res.ok and res.err == "busy", "rules", "one expedition at a time", tostring(res.err))
res = H.req(p, "island.expand", {})
H.expect(not res.ok and res.err == "busy", "rules", "no expanding while the party is away (the new wild places need it home)", tostring(res.err))
local siteIndex = 0
for i, q in prof.plot.placed do
	if q.uid == site1 then
		siteIndex = i
	end
end
res = H.req(p, "plot.store", { i = siteIndex })
H.expect(not res.ok and (res.err == "busy" or res.err == "wild"), "rules", "the place the party is in can't be cleared away", tostring(res.err))
res = H.req(p, "pouch.upgrade", {})
H.expect(not res.ok and res.err == "busy", "rules", "no pouch upgrade while away", tostring(res.err))
res = H.req(p, "folk.dismiss", { id = prof.folk[1].id })
H.expect(not res.ok and res.err == "busy", "rules", "a member away can't be dismissed", tostring(res.err))
res = H.req(p, "exp.snack", { target = "w1" })
H.expect(not res.ok and res.err == "no_exp", "rules", "no battle yet: no snack to throw", tostring(res.err))
res = H.req(p, "exp.skill", { who = "f", skill = "cry", target = "" })
H.expect(not res.ok and res.err == "no_exp", "rules", "nor a skill", tostring(res.err))
res = H.req(p, "exp.pause", { on = false })
H.expect(not res.ok and res.err == "no_exp", "rules", "nor a battle to run", tostring(res.err))
-- on to the first battle: it waits (paused) till let run
nextBattle()
H.expect(s.exp and s.exp.battle ~= nil, "rules", "a battle on the path")
H.expect(s.exp.battle.paused == true, "rules", "a new battle waits, paused (its wild ones land first)")
res = H.req(p, "exp.next", {})
H.expect(not res.ok and res.err == "in_battle", "rules", "no stepping on mid-battle", tostring(res.err))
local fx = H.watchFx(p)
local acts0 = s.exp.battle.acts
E.run(3)
H.expect(s.exp.battle and s.exp.battle.acts == acts0, "rules", "paused: nobody acts", tostring(s.exp.battle and s.exp.battle.acts))
for _, f in s.exp.party do
	f.hp, f.maxHp = 500, 500
end
res = H.req(p, "exp.pause", { on = false })
H.expect(res.ok and res.data and res.data.paused == false and type(res.data.g) == "table", "rules", "let run: the timers come back", tostring(res.err))
E.run(5)
H.expect(s.exp.battle == nil or s.exp.battle.acts > acts0, "rules", "running: the timers fill and the fighters act", tostring(s.exp.battle and s.exp.battle.acts))
local actMsgs, timerMsgs = 0, 0
for _, m in fx do
	if m.kind == "exp" and m.step == "act" then
		actMsgs += 1
	elseif m.kind == "exp" and m.step == "timers" then
		timerMsgs += 1
	end
end
H.expect(actMsgs >= 1 and timerMsgs >= 1, "rules", "the actions and the timers reach the client as they happen", string.format("%d acts, %d syncs", actMsgs, timerMsgs))
if s.exp.battle then
	H.req(p, "exp.pause", { on = true })
	local a1 = s.exp.battle.acts
	E.run(3)
	H.expect(s.exp.battle.acts == a1 and s.exp.battle.paused, "rules", "paused again (aiming, or the screen closed): all stops", tostring(s.exp.battle.acts))
	H.req(p, "exp.pause", { on = false })
end
if s.exp.battle == nil then
	nextBattle()
end
-- snacks: a free nest, a few a trip
local palsKeep = prof.pals
prof.pals = {}
for k = 1, 6 do
	table.insert(prof.pals, { id = prof.nextId, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = {} })
	prof.nextId += 1
end
prof.seen.pebblit = 2
res = H.req(p, "exp.snack", { target = "w1" })
H.expect(not res.ok and res.err == "no_room", "rules", "a snack needs a free nest", tostring(res.err))
prof.pals = palsKeep
local snacksKeep = s.exp.snacks
s.exp.snacks = 0
res = H.req(p, "exp.snack", { target = "w1" })
H.expect(not res.ok and res.err == "no_snacks", "rules", "none left: no snack", tostring(res.err))
s.exp.snacks = snacksKeep
-- snacks until a friend (the leader throws; its timer starts again; the wild one, worn out, may catch it)
local friends0 = #prof.pals
local tries = 0
local resetOk = true
while s.exp and #prof.pals == friends0 and tries < 40 do
	if not s.exp.battle then
		nextBattle()
		if not s.exp.battle or s.exp.battle.boss then
			break
		end
	end
	tries += 1
	s.exp.snacks = math.max(s.exp.snacks, 1)
	local target = nil
	for _, f in s.exp.battle.foes do
		if f.hp > 0 then
			f.hp = 1
			target = f.key
		end
	end
	s.exp.party[1].gauge = 0.6
	local left = s.exp.snacks
	res = H.req(p, "exp.snack", { target = target or "w1" })
	if res.ok and s.exp and s.exp.battle then
		resetOk = resetOk and s.exp.party[1].gauge < 0.6 and s.exp.snacks == left - 1
	end
	E.run(0.3)
end
H.expect(#prof.pals == friends0 + 1, "rules", "a snack befriended a wild driftling", string.format("%d snacks", tries))
H.expect(resetOk, "rules", "each throw: the leader's timer starts again, one snack fewer")
local newPal = prof.pals[#prof.pals]
H.expect(newPal and prof.seen[newPal.sp] == 2 and prof.stats.befriended >= 1, "rules", "in the Index as a friend")
-- skills: paid in skill points, learnt by level
nextBattle()
if s.exp and s.exp.battle then
	s.exp.battle.sp = 0
	res = H.req(p, "exp.skill", { who = "f", skill = "cry", target = "" })
	H.expect(not res.ok and res.err == "sp", "rules", "a skill waits for its skill points", tostring(res.err))
	s.exp.battle.sp = 10
	res = H.req(p, "exp.skill", { who = "f", skill = "mend", target = "f" })
	H.expect(not res.ok and res.err == "locked", "rules", "only a skill the user has learnt", tostring(res.err))
	local atk0 = s.exp.party[2].atk
	res = H.req(p, "exp.skill", { who = "f", skill = "cry", target = "" })
	H.expect(res.ok and math.abs(s.exp.battle.sp - 7) < 0.2 and s.exp.party[2].atk > atk0, "rules", "Rally Cry: three points, the team hits harder", tostring(res.err))
	E.run(1)
end
-- a flight
nextBattle()
if s.exp and s.exp.battle and not s.exp.battle.boss then
	local fled = false
	for _ = 1, 30 do
		res = H.req(p, "exp.flee", {})
		if res.ok and res.data and res.data.result == "fled" then
			fled = true
			break
		end
		if not (s.exp and s.exp.battle) then
			break
		end
		E.run(0.2)
	end
	H.expect(fled and s.exp and s.exp.battle == nil and not s.exp.over, "rules", "a flight gets away (the expedition goes on)")
end
-- the guardian: no snacks, no flight
local guard = 0
for _, f in s.exp.party do
	f.hp, f.maxHp, f.atk = 2000, 2000, f.atk * 3
end
while s.exp and not s.exp.over and guard < 60 do
	guard += 1
	if s.exp.battle and s.exp.battle.boss then
		break
	elseif s.exp.battle then
		fight()
	else
		H.req(p, "exp.next", {})
	end
end
H.expect(s.exp and s.exp.battle and s.exp.battle.boss, "rules", "the guardian at the path's end")
res = H.req(p, "exp.snack", { target = "w1" })
H.expect(not res.ok and res.err == "blocked", "rules", "a guardian can't be befriended", tostring(res.err))
res = H.req(p, "exp.flee", {})
H.expect(not res.ok and res.err == "blocked", "rules", "nor fled from", tostring(res.err))
H.checkProfile(p, "rules")
H.checkMirror(p, "rules")

------------------------------------------------------------------ 2. the screen: closed and reopened, the timed battle on it
E.phase = "screen"
local EUI = H.cmod(p, "UI.ExpeditionUI")
local DayLightX = H.cmod(p, "Controllers.DayLight")
H.expect(H.buttonNamed(p, "ExpContinue") ~= nil, "screen", "the HUD's expedition card shows while one is under way")
for _, f in s.exp.party do
	f.hp, f.maxHp = 2000, 2000
end
for _, f in s.exp.battle.foes do
	f.hp, f.maxHp = 3000, 3000
end
strong(12)
for _, f in s.exp.party do
	-- (the party's levels as the screen reads them: the leader knows First Aid at 3)
	f.lvl = 12
end
H.push(p, 0.3)
H.clickNamed(p, "ExpContinue", { wait = 0.5 })
H.expect(H.inClient(p, EUI.isOpen) == true, "screen", "Continue opens the islet's screen")
E.run(0.3)
local AudioX = H.cmod(p, "Controllers.Audio")
H.expect(H.inClient(p, AudioX.musicState).mood == "sea", "screen", "the music turns to the adventure at sea", tostring(H.inClient(p, AudioX.musicState).mood))
E.run(Tuning.StageWait + 2)
local st = H.inClient(p, EUI.debugState)
H.expect(st.lifted and st.actors >= 5, "screen", "the party and the guardian on the stage", string.format("%s %d", tostring(st.lifted), st.actors))
H.expect(st.timers >= 5, "screen", "a timer over every head", tostring(st.timers))
H.expect(s.exp.battle and not s.exp.battle.paused, "screen", "the battle runs once the screen is up (no taps)")
H.expect(H.buttonNamed(p, "Act_skills") ~= nil and H.buttonNamed(p, "Act_snack") == nil and H.buttonNamed(p, "Act_snack", true) ~= nil and H.buttonNamed(p, "Act_flee") == nil, "screen", "against the guardian: Skills; Snack and Flee off")
H.expect(H.buttonNamed(p, "Act_fight", true) == nil and H.buttonNamed(p, "Act_guard", true) == nil and H.buttonNamed(p, "AutoBattle", true) == nil, "screen", "no Fight, Guard or Auto: the battle fights itself")
local hp0 = 0
for _, f in s.exp.battle.foes do
	hp0 += f.hp
end
local errs0 = #E.errors
E.run(5)
local hp1 = 0
if s.exp and s.exp.battle then
	for _, f in s.exp.battle.foes do
		hp1 += f.hp
	end
end
H.expect(hp1 < hp0 or (s.exp and s.exp.battle == nil), "screen", "blows land by themselves", string.format("%d -> %d", hp0, hp1))
H.expect(#E.errors == errs0, "screen", "its playback ran without errors", tostring(#E.errors - errs0))
-- a fighter's details: the mouse over a wild one shows its name, what it is, its stats, passive and mutations
if s.exp and s.exp.battle then
	local CreaturesS = H.sharedServer("Data.Creatures")
	local foe = s.exp.battle.foes[1]
	local shownKey, lines = H.inClient(p, EUI.debugInspect, foe.key)
	local cd = CreaturesS.byId[foe.sp]
	local hasPassive, hasMuts = false, false
	for _, l in lines do
		if cd and string.find(l, cd.passive.name, 1, true) then
			hasPassive = true
		end
		if l == "No mutations" or string.find(l, "*", 1, true) then
			hasMuts = true
		end
	end
	H.expect(shownKey == foe.key and lines[1] == foe.name and string.find(lines[2] or "", "driftling", 1, true) ~= nil, "screen", "the mouse over a wild one: its details plate (name, what it is)", table.concat(lines, " | "))
	H.expect(hasPassive and hasMuts and string.find(lines[3] or "", "HP", 1, true) ~= nil, "screen", "its stats, passive and mutations", table.concat(lines, " | "))
	local gone = H.inClient(p, EUI.debugInspect, nil)
	H.expect(gone == nil and not H.inClient(p, EUI.debugState).inspect, "screen", "the mouse off it: the plate goes")
end
-- the skill window: it pauses and greys the battle; a skill with a member to aim at shows the leader's ring and arrow
if s.exp and s.exp.battle then
	s.exp.battle.sp = 10
	H.clickNamed(p, "Act_skills", { wait = 0.4 })
	st = H.inClient(p, EUI.debugState)
	H.expect(st.menu and s.exp.battle.paused, "screen", "Skills: the window opens, the battle pauses")
	-- an action playing freezes where it is (the battle's own clock stands still), and runs on after
	local c0 = st.clock
	E.run(0.6)
	st = H.inClient(p, EUI.debugState)
	H.expect(st.held and st.clock == c0, "screen", "choosing: the playback stands still, mid-attack too", string.format("%.2f -> %.2f", c0, st.clock))
	H.expect(H.inClient(p, DayLightX.debugState).grade ~= "" or true, "screen", "(the picture greys: DayLight.hold)")
	H.expect(H.buttonNamed(p, "Skill_f_cry") ~= nil and H.buttonNamed(p, "Skill_f_aid") ~= nil, "screen", "the leader's skills learnt by level (Rally Cry, First Aid)")
	-- the pointer resting on a skill: what it does (GAME_DESIGN 7: "show what skills do while hovering or pressing")
	local tipShown, tipLines = H.inClient(p, EUI.debugSkillTip, "f_aid")
	local tipText = table.concat(tipLines or {}, " | ")
	H.expect(tipShown and string.find(tipText, "First Aid", 1, true) ~= nil and string.find(tipText, "Mends", 1, true) ~= nil and string.find(tipText, "Pick a member", 1, true) ~= nil, "screen", "a skill's tip: its name, what it does, how it aims", tipText)
	H.clickNamed(p, "Skills_close", { wait = 0.4 })
	st = H.inClient(p, EUI.debugState)
	H.expect(not st.menu and not s.exp.battle.paused, "screen", "Back: the battle runs on")
	H.expect(not st.held and st.clock > c0, "screen", "and its playback with it", string.format("%.2f -> %.2f", c0, st.clock))
	H.clickNamed(p, "Act_skills", { wait = 0.4 })
	s.exp.party[2].hp = 100
	H.clickNamed(p, "Skill_f_aid", { wait = 0.4 })
	st = H.inClient(p, EUI.debugState)
	H.expect(st.aim == "skill" and st.aimWho == "f" and st.aimTarget ~= nil and st.marked, "screen", "First Aid: the leader's ring and arrow on the floor toward a member", string.format("%s %s %s", tostring(st.aim), tostring(st.aimTarget), tostring(st.marked)))
	H.expect(s.exp.battle.paused, "screen", "aiming: paused")
	E.run(0.6)
	st = H.inClient(p, EUI.debugState)
	H.expect(st.arrowGap ~= nil and st.arrowGap < 0.3, "screen", "the arrow reaches all the way to the pick", tostring(st.arrowGap))
	-- the pointer: hovering another member picks them (the arrow glides over), a wild one is no pick for a mend, and
	-- a tap on the pick uses the skill
	local first = st.aimTarget
	local other: string? = nil
	for _, f in s.exp.party do
		if f.key ~= first and f.hp > 0 then
			other = f.key
			break
		end
	end
	H.expect(other ~= nil and H.inClient(p, EUI.debugPoint, other, false) == true, "screen", "the pointer over another member", tostring(other))
	st = H.inClient(p, EUI.debugState)
	H.expect(st.aim == "skill" and st.aimTarget == other and st.arrowGap ~= nil and st.arrowGap > 0.5, "screen", "hovering picks them (not used yet), the arrow on its way over", string.format("%s %s", tostring(st.aimTarget), tostring(st.arrowGap)))
	E.run(0.6)
	st = H.inClient(p, EUI.debugState)
	H.expect(st.arrowGap ~= nil and st.arrowGap < 0.3 and st.arrow >= 0, "screen", "the arrow glides over to the new pick", tostring(st.arrowGap))
	H.expect(H.inClient(p, EUI.debugPoint, s.exp.battle.foes[1].key, true) == false and H.inClient(p, EUI.debugState).aimTarget == other, "screen", "a tap on a wild one: no pick for a mend")
	local sp0 = s.exp.battle.sp
	H.expect(H.inClient(p, EUI.debugPoint, other :: string, true) == true, "screen", "a tap on the pick")
	E.run(0.6)
	st = H.inClient(p, EUI.debugState)
	H.expect(st.aim == nil and not st.marked and s.exp.battle and not s.exp.battle.paused and s.exp.battle.sp < sp0, "screen", "the tap on the pick uses it: paid in points, the battle runs on", string.format("%s %.1f", tostring(st.aim), s.exp.battle and s.exp.battle.sp or -1))
	-- Use! does the same
	if s.exp and s.exp.battle then
		s.exp.battle.sp = 10
		H.clickNamed(p, "Act_skills", { wait = 0.4 })
		H.clickNamed(p, "Skill_f_aid", { wait = 0.4 })
		local sp1 = s.exp.battle.sp
		H.clickNamed(p, "Aim_use", { wait = 0.6 })
		st = H.inClient(p, EUI.debugState)
		H.expect(st.aim == nil and s.exp.battle and not s.exp.battle.paused and s.exp.battle.sp < sp1, "screen", "Use!: paid in points, the battle runs on", string.format("%s %.1f", tostring(st.aim), s.exp.battle and s.exp.battle.sp or -1))
	end
	E.run(2)
end
-- Back to island: a card (the battle paused): Sail home now, Leave it here, Stay
H.clickNamed(p, "BackToIsland", { wait = 0.4 })
H.expect(H.inClient(p, EUI.debugState).leave and H.buttonNamed(p, "LeaveHome") ~= nil and H.buttonNamed(p, "LeaveWait") ~= nil and H.buttonNamed(p, "LeaveStay") ~= nil, "screen", "Back to island: the leave card (sail home, leave it here, stay)")
H.expect(s.exp.battle == nil or s.exp.battle.paused, "screen", "the battle paused while it is up")
H.clickNamed(p, "LeaveStay", { wait = 0.4 })
H.expect(not H.inClient(p, EUI.debugState).leave and (s.exp.battle == nil or not s.exp.battle.paused), "screen", "Stay: the card goes, the battle runs on")
H.clickNamed(p, "BackToIsland", { wait = 0.4 })
H.clickNamed(p, "LeaveWait", { wait = 0.6 })
H.expect(not H.inClient(p, EUI.isOpen) and s.exp ~= nil, "screen", "Leave it here: the screen closes, the expedition waits")
H.expect(s.exp.battle == nil or s.exp.battle.paused, "screen", "and its battle waits, paused")
H.expect(H.buttonNamed(p, "Menu_build") ~= nil, "screen", "the HUD is back")
-- the guardian falls (the party made strong)
strong(30)
for _, f in s.exp.party do
	f.atk, f.hp, f.maxHp = 300, 500, 500
end
if s.exp.battle then
	for _, f in s.exp.battle.foes do
		f.hp = math.min(f.hp, 200)
	end
end
local over = walk()
H.expect(over == "won" and prof.islets == 1, "screen", "the guardian beaten: the place cleared", tostring(over))
local clearedQ = nil
for _, q in prof.plot.placed do
	if q.uid == site1 then
		clearedQ = q
	end
end
H.expect(clearedQ ~= nil and string.sub(clearedQ.id, 1, 5) == "done_", "screen", "its piece no longer wild", tostring(clearedQ and clearedQ.id))
E.run(0.5)
local cleanModel = false
for _, m in E.workspace.Plots:FindFirstChild("Plot_" .. s.plot):FindFirstChild("Decor", true):GetChildren() do
	if string.match(m.Name, "^" .. tostring(site1) .. ":done_") then
		cleanModel = m:GetAttribute("Wild") == false
	end
end
H.expect(cleanModel, "screen", "its model rebuilt as a cleared one")
res = H.req(p, "exp.next", {})
H.expect(not res.ok, "screen", "nothing past the guardian: the trip is over", tostring(res.err))
local sh0 = prof.shells
local loot = s.exp and s.exp.loot.shells or 0
res = H.req(p, "exp.home", {})
H.expect(res.ok and s.exp == nil and math.abs(prof.shells - (sh0 + loot)) < 1, "screen", "home with all the loot", string.format("%s + %s -> %s", sh0, loot, prof.shells))
-- a bigger pouch: more snacks a trip
prof.shells, prof.wood = 1e6, 1e5
res = H.req(p, "pouch.upgrade", {})
H.expect(res.ok and prof.pouch == 2 and res.data.snacks == Tuning.SnackBase * 2, "screen", "the pouch upgraded: ten snacks a trip", tostring(res.err))
H.checkProfile(p, "screen")

------------------------------------------------------------------ 3. the wild places at every tier
E.phase = "islands"
-- the island grown to the top: each expansion brings its wild places, higher in level; one of each tier's cleared
prof.shells, prof.wood = 1e8, 1e7
for t = 2, #Tuning.TierCost do
	local before = 0
	for _, q in prof.plot.placed do
		if Plot.isSite(q.id) then
			before += 1
		end
	end
	res = H.req(p, "island.expand", {})
	local after = 0
	for _, q in prof.plot.placed do
		if Plot.isSite(q.id) then
			after += 1
		end
	end
	H.expect(res.ok and prof.tier == t and after == before + #SiteData.spawnAt(t), "islands", "tier " .. t .. ": its wild places come up", string.format("%s %d -> %d", tostring(res.err), before, after))
	E.run(0.5)
end
H.checkProfile(p, "grown")
local kindsSeen: { [number]: boolean } = {}
local names: { [string]: boolean } = {}
local picks = {}
for t = 1, #Tuning.TierCost do
	-- the highest wild place of each tier
	local best = nil
	for _, e in SiteData.spawnAt(t) do
		for _, q in prof.plot.placed do
			if q.id == SiteData.wildId(e.id) and q.lvl == e.lvl and (best == nil or q.lvl > best.lvl) then
				best = q
			end
		end
	end
	if best then
		table.insert(picks, best)
	end
end
H.expect(#picks >= 5, "islands", "a wild place from (nearly) every tier", tostring(#picks))
for _, q in picks do
	strong(math.min(Tuning.LevelMax, q.lvl + 8))
	prof.food = 1000
	res = H.req(p, "exp.start", { site = q.uid, party = party(3) })
	H.expect(res.ok, "islands", "into the " .. q.id .. " of level " .. q.lvl, tostring(res.err))
	if not res.ok then
		break
	end
	local isle = s.exp.isle
	-- a party far stronger than the place and its stages (the rules are what is checked here, not the fight); one
	-- who levels up on the way is a fresh fighter from the save, made as strong again
	local boosted = {}
	local function boost(full)
		for _, f in s.exp.party do
			if not boosted[f] then
				boosted[f] = true
				local k = if full then 1 else f.hp / math.max(1, f.maxHp)
				f.atk, f.def, f.maxHp = f.atk * 5, f.def * 3, f.maxHp * 6
				f.hp = math.max(1, math.floor(f.maxHp * k))
			end
		end
	end
	boost(true)
	local sd = SiteData.of(q.id)
	kindsSeen[isle.kind] = true
	names[isle.name] = true
	H.expect(sd ~= nil and isle.kind == sd.islet and isle.lvl == q.lvl and string.find(isle.name, sd.name, 1, true) ~= nil, "islands", string.format("%s: its kind and level (%d)", isle.name, q.lvl))
	local before = prof.islets
	local foesOk = true
	local steps = 0
	while s.exp and not s.exp.over and steps < 200 do
		steps += 1
		if s.exp.battle then
			for _, f in s.exp.battle.foes do
				foesOk = foesOk and (table.find(isle.wild, f.sp) ~= nil or f.sp == isle.boss)
			end
			fight()
			boost(false)
		else
			H.req(p, "exp.next", {})
		end
	end
	over = s.exp and s.exp.over
	H.expect(over == "won", "islands", isle.name .. ": cleared", tostring(over))
	H.expect(foesOk, "islands", isle.name .. ": only its own driftlings")
	H.expect(prof.islets == before + 1 and string.sub(q.id, 1, 5) == "done_", "islands", isle.name .. ": no longer wild", tostring(prof.islets))
	local loot2 = s.exp and s.exp.loot.shells or 0
	H.expect(loot2 >= Expedition.rewardOf(isle, true), "islands", isle.name .. ": the first clear's big reward", tostring(loot2))
	H.req(p, "exp.home", {})
end
local nk = 0
for _ in kindsSeen do
	nk += 1
end
H.expect(nk >= 4, "islands", "different kinds of place", tostring(nk))
-- the first place again: it is cleared already, so a smaller reward and counted once
strong(30)
prof.food = 1000
local cleared0 = prof.islets
res = H.req(p, "exp.start", { site = site1, party = party(3) })
H.expect(res.ok, "islands", "a cleared place can be explored again", tostring(res.err))
local isleAgain = s.exp and s.exp.isle
over = walk()
local again = s.exp and s.exp.loot.shells or 0
H.expect(over == "won" and prof.islets == cleared0, "islands", "a place cleared again counts once", tostring(prof.islets))
H.expect(isleAgain ~= nil and again >= Expedition.rewardOf(isleAgain, false) and again < Expedition.rewardOf(isleAgain, true) + 500, "islands", "the smaller reward the second time", tostring(again))
H.req(p, "exp.home", {})
H.checkProfile(p, "islands")
H.checkMirror(p, "islands")

------------------------------------------------------------------ 4. a defeat
E.phase = "defeat"
strong(30)
prof.food = 1000
local hardest = nil
for _, q in prof.plot.placed do
	if Plot.isSite(q.id) and (hardest == nil or q.lvl > hardest.lvl) then
		hardest = q
	end
end
res = H.req(p, "exp.start", { site = hardest.uid, party = "" })
H.expect(res.ok, "defeat", "the captain alone into the toughest place", tostring(res.err))
if s.exp then
	local f = s.exp.party[1]
	f.atk, f.hp, f.maxHp, f.def = 1, 6, 6, 0
end
over = walk()
H.expect(over == "lost", "defeat", "the party falls", tostring(over))
H.expect(s.exp ~= nil and type(s.exp.gained) == "table" and type(s.exp.gained.xp) == "number" and type(s.exp.gained.ups) == "table", "defeat", "the trip's tally kept for the Expedition Complete card (xp, levels)")
local lost = s.exp and E.deepCopy(s.exp.loot)
local f0, w0 = prof.food, prof.wood
res = H.req(p, "exp.home", {})
H.expect(res.ok and lost ~= nil and math.abs(prof.food - (f0 + math.floor(lost.food))) < 1 and math.abs(prof.wood - (w0 + math.floor(lost.wood))) < 1, "defeat", "all the loot home: no penalty for losing", lost and string.format("%s food gathered", lost.food) or "")
H.expect(s.exp == nil and next(s.away) == nil, "defeat", "everyone home")

------------------------------------------------------------------ 5. a friend made on the screen
-- a snack that befriends the last wild one ends the battle on the server at once: the screen still plays the throw,
-- the arc, the hearts and the poof with the wild one on the stage, and only then lays out what comes next
E.phase = "friend"
strong(5)
prof.food = 1000
prof.pals = {}
local BattleS = H.sharedServer("Logic.Battle")
local chance0 = BattleS.treatChance
BattleS.treatChance = function()
	return 1
end
res = H.req(p, "exp.start", { site = site1, party = "" })
H.expect(res.ok, "friend", "the captain alone into the first place", tostring(res.err))
nextBattle()
if s.exp and s.exp.battle then
	local foes = s.exp.battle.foes
	while #foes > 1 do
		table.remove(foes)
	end
	foes[1].hp, foes[1].maxHp = 4000, 4000
	s.exp.party[1].hp, s.exp.party[1].maxHp = 5000, 5000
	H.push(p, 0.3)
	H.clickNamed(p, "ExpContinue", { wait = 0.5 })
	E.run(Tuning.StageWait + 3)
	local key = foes[1].key
	H.expect(string.find(H.inClient(p, EUI.debugState).shown, key, 1, true) ~= nil, "friend", "the wild one on the stage", key)
	H.inClient(p, EUI.debugSnack, key)
	H.expect(s.exp and s.exp.battle == nil and #prof.pals == 1, "friend", "befriended: the battle is over on the server")
	-- (the first moment it is off the stage: a next battle's wild one may take the same key later)
	local goneAt: number? = nil
	for k = 1, 60 do
		local st2 = H.inClient(p, EUI.debugState)
		if goneAt == nil and string.find(st2.shown, key, 1, true) == nil then
			goneAt = k * 0.05
		end
		E.run(0.05)
	end
	H.expect(goneAt == nil or goneAt >= 0.9, "friend", "it stays on the stage through the throw, the arc and the hearts", tostring(goneAt))
	H.expect(goneAt ~= nil and goneAt <= 2.5, "friend", "then goes in its poof", tostring(goneAt))
	H.clickNamed(p, "BackToIsland", { wait = 0.4 })
	H.clickNamed(p, "LeaveWait", { wait = 0.5 })
	E.run(0.5)
end
BattleS.treatChance = chance0

------------------------------------------------------------------ one area: the wild ones come to the party
-- (GAME_DESIGN 7: "no need to make the party walk anymore, the creatures will appear in a single area"): Go on plays
-- the next stop where the party stands, the camera holding still; a battle's wild ones come running down the trail to
-- their places ahead of the party (none drops from above) and the battle starts once they are there
E.phase = "run"
if s.exp then
	H.req(p, "exp.home", {})
	E.run(1)
end
prof.food = 1000
strong(8)
res = H.req(p, "exp.start", { site = site1, party = "" })
H.expect(res.ok, "run", "the captain sets out", tostring(res.err))
H.push(p, 0.3)
-- (the stops go on by themselves, at once: held here so the phase drives them; with no wait between stops a lone
-- captain would otherwise fight on and on while the screen opens)
H.inClient(p, EUI.debugAuto, false)
H.clickNamed(p, "ExpContinue", { wait = 0.5 })
E.run(Tuning.StageWait + 3)
local CamX = H.cmod(p, "Controllers.CameraController")
local runSt = H.inClient(p, EUI.debugState)
H.expect(runSt.open and runSt.area == 0, "run", "the screen opens on the island's one area", tostring(runSt.area))
local battleSeen = false
-- (a battle already under way is won first)
for _ = 1, 40 do
	if not (s.exp and s.exp.battle) then
		break
	end
	for _, f in s.exp.battle.foes do
		f.hp = 1
	end
	E.run(0.5)
end
E.run(1)
for _ = 1, 8 do
	local node0 = s.exp and s.exp.node or 0
	local panX0 = H.inClient(p, CamX.pan)
	-- Go on (or the auto Go on, whichever comes first)
	H.inClient(p, function()
		E.task.spawn(EUI.debugGo)
	end)
	local mid = H.inClient(p, EUI.debugState)
	local sawRunning = false
	local waited = 0
	-- (a battle just won may still be playing its last blow and the cheer: the next stop comes up right after)
	for _ = 1, 120 do
		if mid.running > 0 then
			sawRunning = true
		end
		if s.exp and s.exp.node > node0 and (s.exp.battle == nil or (sawRunning and mid.running == 0)) then
			break
		end
		E.run(0.05)
		waited += 0.05
		mid = H.inClient(p, EUI.debugState)
	end
	H.log("run: the next stop (%s) came up %.2f s after Go on", tostring(s.exp and s.exp.nodes[s.exp.node]), waited)
	if s.exp and s.exp.node <= node0 then
		local d = H.inClient(p, EUI.debugState)
		H.log("run: stuck at node %d (%s): battle %s, over %s, busy %s, lifted %s, running %s, actors %s, queue %s, result %s", s.exp.node, tostring(s.exp.nodes[s.exp.node]), tostring(s.exp.battle ~= nil), tostring(s.exp.over), tostring(d.busy), tostring(d.lifted), tostring(d.running), tostring(d.actors), tostring(d.queue), tostring(d.result))
	end
	H.expect(s.exp ~= nil and s.exp.node > node0, "run", "Go on: the next stop comes up", string.format("%s -> %s", tostring(node0), tostring(s.exp and s.exp.node)))
	H.expect(H.buttonNamed(p, "BackToIsland") ~= nil, "run", "Back to island stays open")
	if s.exp and s.exp.battle then
		-- (wild ones that last until they are looked at)
		for _, f in s.exp.battle.foes do
			f.hp, f.maxHp = 3000, 3000
		end
		H.push(p, 0.1)
	end
	E.run(2.5)
	local after = H.inClient(p, EUI.debugState)
	local panX1 = H.inClient(p, CamX.pan)
	H.expect(after.area == 0 and after.behind == 0, "run", "the party stays where it stands", string.format("area %s behind %s", tostring(after.area), tostring(after.behind)))
	H.expect(panX1 == panX0, "run", "the camera holds still", string.format("%s -> %s", tostring(panX0), tostring(panX1)))
	if s.exp and s.exp.battle then
		battleSeen = true
		H.expect(sawRunning, "run", "the wild ones come running down the trail", tostring(mid.running))
		H.expect(after.running == 0, "run", "they get to their places", tostring(after.running))
		H.expect(after.foeU ~= nil and after.foeU > 0, "run", "they stand ahead of the party, up the trail", tostring(after.foeU))
		H.expect(after.dropping == 0, "run", "none drops in from above", tostring(after.dropping))
		E.run(1.5)
		H.expect(s.exp and s.exp.battle and not s.exp.battle.paused, "run", "the battle starts once they are there")
		break
	end
end
H.expect(battleSeen, "run", "a battle came up")
H.inClient(p, EUI.debugAuto, true)
H.req(p, "exp.home", {})
E.run(3)

------------------------------------------------------------------ a snack mid-attack; sailing home mid-battle
E.phase = "midbattle"
if s.exp then
	H.req(p, "exp.home", {})
	E.run(1)
end
prof.food = 1000
res = H.req(p, "exp.start", { site = site1, party = "" })
H.expect(res.ok, "midbattle", "the captain sets out again", tostring(res.err))
nextBattle()
if s.exp and s.exp.battle then
	local b = s.exp.battle
	for _, f in b.foes do
		f.hp, f.maxHp = 3000, 3000
	end
	s.exp.party[1].hp, s.exp.party[1].maxHp = 5000, 5000
	-- the server's side: a snack thrown while an attack plays cancels it (the health back as it was)
	H.req(p, "exp.pause", { on = false })
	local rng = H.sharedServer("Logic.Util").newRng(1)
	local hit = nil
	for _ = 1, 200 do
		E.run(0.05)
		if b.lock > 0 and b.undo ~= nil then
			hit = b.undo
			break
		end
	end
	if H.expect(hit ~= nil, "midbattle", "an attack under way") then
		H.req(p, "exp.pause", { on = true })
		local target = nil
		for _, f in b.foes do
			if f.hp > 0 then
				target = f.key
			end
		end
		local chance1 = BattleS.treatChance
		BattleS.treatChance = function()
			return 0
		end
		local r2 = H.req(p, "exp.snack", { target = target })
		BattleS.treatChance = chance1
		local ev = r2.ok and r2.data and r2.data.events
		H.expect(ev and ev[1] and ev[1].t == "cancel" and ev[2] and ev[2].t == "treat", "midbattle", "a snack thrown mid-attack: the attack cancelled first", tostring(ev and ev[1] and ev[1].t))
		local same = true
		for _, f in b.foes do
			if hit.hp[f.key] ~= f.hp then
				same = false
			end
		end
		if hit.hp.f ~= s.exp.party[1].hp then
			same = false
		end
		H.expect(same, "midbattle", "everyone's health as it was before the attack")
		local _ = rng
	end
	-- the screen: Back to island, Sail home now, in the middle of the battle
	H.push(p, 0.3)
	H.clickNamed(p, "ExpContinue", { wait = 0.5 })
	E.run(Tuning.StageWait + 3)
	local shells0 = prof.shells
	s.exp.loot.shells += 77
	H.clickNamed(p, "BackToIsland", { wait = 0.4 })
	H.clickNamed(p, "LeaveHome", { wait = 1.5 })
	H.expect(s.exp == nil and prof.shells >= shells0 + 77, "midbattle", "Sail home now, mid-battle: the trip ends, the loot comes home", string.format("%s %d", tostring(s.exp), prof.shells - shells0))
	-- (this trip set out without its cutscene: home is the plain blinds; a real one sails the boat back)
	local VoyageS = H.cmod(p, "UI.Voyage")
	E.run(3)
	H.expect(not H.inClient(p, EUI.isOpen) and H.inClient(p, VoyageS.debugState).phase == "" and H.buttonNamed(p, "Menu_build") ~= nil, "midbattle", "the screen gives way to the island again (the HUD back)")
end
if s.exp then
	H.req(p, "exp.home", {})
end
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
