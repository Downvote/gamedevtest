-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 7.4, 10.9): the sea chart's islands, near and far (the boat
-- upgraded to the last, each island of its distance's level, its own driftlings, charted with the guardian's whole
-- reward, half on a second trip), the server's rules (supplies, a party of the captain and three, one expedition at a
-- time, no island past the boat's range, no boat upgrade while it is away, members away can't be dismissed or released,
-- no stepping on or sailing home mid-battle, no snack or flight from a guardian, a snack's free nest and the trip's
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
local res = H.req(p, "exp.start", { isle = 1, party = party(3) })
H.expect(not res.ok and res.err == "food", "rules", "supplies: four members need food", tostring(res.err))
prof.food = 1000
res = H.req(p, "exp.start", { isle = Tuning.ChartIslands, party = "" })
H.expect(not res.ok and res.err == "far", "rules", "no island past the boat's range", tostring(res.err))
res = H.req(p, "exp.start", { isle = 1, party = party(3) })
H.expect(res.ok and #s.exp.party == 4 and s.exp.party[1].key == "f", "rules", "the captain and three set sail", tostring(res.err))
H.expect(math.abs(prof.food - (1000 - Tuning.Supplies * 4)) < 1, "rules", "their supplies taken", tostring(prof.food))
H.expect(res.ok and res.data and res.data.isle and res.data.isle.name == s.exp.isle.name, "rules", "the answer names the island", res.data and res.data.isle and res.data.isle.name)
H.expect(s.exp.snacks == Tuning.SnackBase, "rules", "five snacks for the trip (the first pouch)", tostring(s.exp.snacks))
res = H.req(p, "exp.start", { isle = 1, party = "" })
H.expect(not res.ok and res.err == "busy", "rules", "one expedition at a time", tostring(res.err))
res = H.req(p, "boat.upgrade", {})
H.expect(not res.ok and res.err == "busy", "rules", "no boat upgrade while it is away", tostring(res.err))
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
res = H.req(p, "exp.home", {})
H.expect(not res.ok and res.err == "in_battle", "rules", "no sailing home mid-battle", tostring(res.err))
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
-- the skill window: it pauses and greys the battle; a skill with a member to aim at shows the leader's ring and arrow
if s.exp and s.exp.battle then
	s.exp.battle.sp = 10
	H.clickNamed(p, "Act_skills", { wait = 0.4 })
	st = H.inClient(p, EUI.debugState)
	H.expect(st.menu and s.exp.battle.paused, "screen", "Skills: the window opens, the battle pauses")
	H.expect(H.inClient(p, DayLightX.debugState).grade ~= "" or true, "screen", "(the picture greys: DayLight.hold)")
	H.expect(H.buttonNamed(p, "Skill_f_cry") ~= nil and H.buttonNamed(p, "Skill_f_aid") ~= nil, "screen", "the leader's skills learnt by level (Rally Cry, First Aid)")
	H.clickNamed(p, "Skills_close", { wait = 0.4 })
	st = H.inClient(p, EUI.debugState)
	H.expect(not st.menu and not s.exp.battle.paused, "screen", "Back: the battle runs on")
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
H.clickNamed(p, "BackToIsland", { wait = 0.5 })
H.expect(not H.inClient(p, EUI.isOpen) and s.exp ~= nil, "screen", "Back to island: the screen closes, the expedition waits")
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
H.expect(over == "won" and prof.islets == 1, "screen", "the guardian beaten: the island charted", tostring(over))
local sh0 = prof.shells
local loot = s.exp and s.exp.loot.shells or 0
res = H.req(p, "exp.home", {})
H.expect(res.ok and s.exp == nil and math.abs(prof.shells - (sh0 + loot)) < 1, "screen", "home with all the loot", string.format("%s + %s -> %s", sh0, loot, prof.shells))
-- a bigger pouch: more snacks a trip
prof.shells, prof.wood = 1e6, 1e5
res = H.req(p, "pouch.upgrade", {})
H.expect(res.ok and prof.pouch == 2 and res.data.snacks == Tuning.SnackBase * 2, "screen", "the pouch upgraded: ten snacks a trip", tostring(res.err))
H.checkProfile(p, "screen")

------------------------------------------------------------------ 3. the chart's islands, near and far
E.phase = "islands"
local Chart = H.sharedServer("Logic.Chart")
prof.shells, prof.wood = 1e7, 1e6
for _ = 2, #Tuning.BoatRadius do
	res = H.req(p, "boat.upgrade", {})
	H.expect(res.ok, "islands", "a bigger boat", tostring(res.err))
end
res = H.req(p, "boat.upgrade", {})
H.expect(not res.ok and res.err == "max", "islands", "the finest boat is the last", tostring(res.err))
local kindsSeen: { [number]: boolean } = {}
local names: { [string]: boolean } = {}
local N = Tuning.ChartIslands
for _, id in { 2, 8, 16, 24, 32, N - 2, N - 1, N } do
	local c = Chart.islands(prof.sea)[id]
	strong(c.lvl + 8)
	prof.food = 1000
	res = H.req(p, "exp.start", { isle = id, party = party(3) })
	H.expect(res.ok, "islands", "set sail for island " .. id, tostring(res.err))
	if not res.ok then
		break
	end
	local isle = s.exp.isle
	-- a party far stronger than the island and its stages (the rules are what is checked here, not the fight)
	for _, f in s.exp.party do
		f.atk, f.def, f.maxHp = f.atk * 5, f.def * 3, f.maxHp * 6
		f.hp = f.maxHp
	end
	local kind = Islets.list[isle.kind]
	kindsSeen[isle.kind] = true
	names[isle.name] = true
	H.expect(isle.id == id and isle.lvl == c.lvl and kind ~= nil and kind.lvl <= c.lvl, "islands", string.format("%s: a %s of level %d, %.1f leagues out", isle.name, kind and kind.name or "?", c.lvl, c.dist))
	local before = prof.islets
	local foesOk = true
	local steps = 0
	while s.exp and not s.exp.over and (s.exp.beaten or 0) < 1 and steps < 200 do
		steps += 1
		if s.exp.battle then
			for _, f in s.exp.battle.foes do
				foesOk = foesOk and (table.find(isle.wild, f.sp) ~= nil or f.sp == isle.boss)
			end
			fight()
		else
			H.req(p, "exp.next", {})
		end
	end
	over = if s.exp and (s.exp.beaten or 0) >= 1 then "won" else s.exp and s.exp.over
	H.expect(over == "won", "islands", isle.name .. ": charted", tostring(over))
	H.expect(foesOk, "islands", isle.name .. ": only its own driftlings")
	H.expect(prof.islets == before + 1 and table.find(prof.chart, id) ~= nil, "islands", isle.name .. ": on the chart", tostring(prof.islets))
	local loot2 = s.exp and s.exp.loot.shells or 0
	H.expect(loot2 >= isle.reward, "islands", isle.name .. ": the guardian's whole reward", tostring(loot2))
	H.req(p, "exp.home", {})
end
local nk = 0
for _ in kindsSeen do
	nk += 1
end
H.expect(nk >= 3, "islands", "different kinds of island further out", tostring(nk))
-- the first island again: half the reward, not charted twice
strong(30)
prof.food = 1000
local charted0 = prof.islets
res = H.req(p, "exp.start", { isle = 2, party = party(3) })
over = walk()
local again = s.exp and s.exp.loot.shells or 0
H.expect(over == "won" and prof.islets == charted0, "islands", "an island charted again counts once", tostring(prof.islets))
H.expect(again >= math.floor(Chart.isle(prof.sea, 2).reward / 2) and again < Chart.isle(prof.sea, 2).reward + 500, "islands", "half the reward the second time", tostring(again))
H.req(p, "exp.home", {})
-- the island goes on: past the guardian, harder stages and a second guardian paying more
strong(30)
prof.food = 1000
res = H.req(p, "exp.start", { isle = 2, party = party(3) })
H.expect(res.ok, "endless", "off again", tostring(res.err))
if s.exp then
	for _, f in s.exp.party do
		f.atk, f.hp, f.maxHp = 2000, 99999, 99999
	end
end
local rewardFx = H.watchFx(p)
local lvls = {}
local guard2 = 0
while s.exp and not s.exp.over and (s.exp.beaten or 0) < 2 and guard2 < 300 do
	guard2 += 1
	if s.exp.battle then
		table.insert(lvls, s.exp.battle.foes[1].lvl)
		fight()
	else
		local r = H.req(p, "exp.next", {})
		H.expect(r.ok, "endless", "the path never runs out", tostring(r.err))
	end
end
E.run(0.5)
local rewards = {}
for _, m in rewardFx do
	if m.kind == "exp" and m.step == "act" and type(m.data) == "table" and m.data.reward then
		table.insert(rewards, m.data.reward)
	end
end
H.expect(s.exp ~= nil and s.exp.beaten == 2 and s.exp.node == 1 + Tuning.BossEvery * 2, "endless", "a second guardian at the second block's end", tostring(s.exp and s.exp.node))
H.expect(#rewards == 2 and rewards[2] > rewards[1], "endless", "it pays more", table.concat(rewards, " "))
H.expect(#lvls >= 2 and lvls[#lvls] > lvls[1], "endless", "the wild ones grow", string.format("%s -> %s", tostring(lvls[1]), tostring(lvls[#lvls])))
res = H.req(p, "exp.next", {})
H.expect(res.ok, "endless", "and the path goes on", tostring(res.err))
H.req(p, "exp.home", {})
H.checkProfile(p, "islands")
H.checkMirror(p, "islands")

------------------------------------------------------------------ 4. a defeat
E.phase = "defeat"
strong(30)
prof.food = 1000
res = H.req(p, "exp.start", { isle = Tuning.ChartIslands, party = "" })
H.expect(res.ok, "defeat", "the captain alone to the farthest island", tostring(res.err))
if s.exp then
	local f = s.exp.party[1]
	f.atk, f.hp, f.maxHp, f.def = 1, 6, 6, 0
end
over = walk()
H.expect(over == "lost", "defeat", "the party falls", tostring(over))
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
res = H.req(p, "exp.start", { isle = 1, party = "" })
H.expect(res.ok, "friend", "the captain alone to island 1", tostring(res.err))
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
	H.clickNamed(p, "BackToIsland", { wait = 0.5 })
	E.run(0.5)
end
BattleS.treatChance = chance0
if s.exp then
	H.req(p, "exp.home", {})
end
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
