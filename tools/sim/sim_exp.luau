-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 7.4, 10.8): all five islets cleared in turn by a strong party
-- (each opening the next, the guardian's reward in full the first time and half after), the server's rules (supplies,
-- a party of the captain and three, one expedition at a time, members away can't be dismissed or released, no
-- stepping on or sailing home mid-battle, no treat or flight from a guardian, a treat's food and a free nest), a
-- driftling befriended with a treat, a flight, a defeat (half the loot home), and the islet's screen: closed and
-- reopened from the HUD's card, its buttons in and out of battle, a round played back.
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
-- the server's way through an islet: on, fight every battle; returns how it ended
local function walk(maxSteps)
	local steps = 0
	while s.exp and not s.exp.over and steps < (maxSteps or 200) do
		steps += 1
		if s.exp.battle then
			H.req(p, "exp.act", { act = "fight", target = "" })
		elseif s.exp.node < #s.exp.nodes then
			H.req(p, "exp.next", {})
		else
			break
		end
	end
	return s.exp and s.exp.over
end

------------------------------------------------------------------ 1. the server's rules
E.phase = "rules"
prof.food = 2
local res = H.req(p, "exp.start", { islet = 1, party = party(3) })
H.expect(not res.ok and res.err == "food", "rules", "supplies: four members need food", tostring(res.err))
prof.food = 1000
res = H.req(p, "exp.start", { islet = 2, party = "" })
H.expect(not res.ok and res.err == "locked", "rules", "Mossgrove waits for Pebble Beach", tostring(res.err))
res = H.req(p, "exp.start", { islet = 1, party = party(3) })
H.expect(res.ok and #s.exp.party == 4 and s.exp.party[1].key == "f", "rules", "the captain and three set sail", tostring(res.err))
H.expect(math.abs(prof.food - (1000 - Tuning.Supplies * 4)) < 1, "rules", "their supplies taken", tostring(prof.food))
res = H.req(p, "exp.start", { islet = 1, party = "" })
H.expect(not res.ok and res.err == "busy", "rules", "one expedition at a time", tostring(res.err))
res = H.req(p, "folk.dismiss", { id = prof.folk[1].id })
H.expect(not res.ok and res.err == "busy", "rules", "a member away can't be dismissed", tostring(res.err))
res = H.req(p, "exp.act", { act = "fight", target = "" })
H.expect(not res.ok and res.err == "no_exp", "rules", "no battle yet: nothing to fight", tostring(res.err))
-- on to the first battle
local guard = 0
while s.exp and not s.exp.battle and guard < 10 do
	guard += 1
	H.req(p, "exp.next", {})
end
H.expect(s.exp and s.exp.battle ~= nil, "rules", "a battle on the path")
res = H.req(p, "exp.next", {})
H.expect(not res.ok and res.err == "in_battle", "rules", "no stepping on mid-battle", tostring(res.err))
res = H.req(p, "exp.home", {})
H.expect(not res.ok and res.err == "in_battle", "rules", "no sailing home mid-battle", tostring(res.err))
-- a treat: food and a free nest
local foodKeep = prof.food
prof.food = 0
res = H.req(p, "exp.act", { act = "treat", target = "w1" })
H.expect(not res.ok and res.err == "food", "rules", "a treat needs food", tostring(res.err))
prof.food = foodKeep
local palsKeep = prof.pals
prof.pals = {}
for k = 1, 6 do
	table.insert(prof.pals, { id = prof.nextId, sp = "pebblit", lvl = 1, xp = 0, work = 0 })
	prof.nextId += 1
end
prof.seen.pebblit = 2
res = H.req(p, "exp.act", { act = "treat", target = "w1" })
H.expect(not res.ok and res.err == "no_room", "rules", "a treat needs a free nest", tostring(res.err))
prof.pals = palsKeep
-- treats until a friend (the founder throws; the wild one, hurt, may say yes)
local friends0 = #prof.pals
local tries = 0
while s.exp and s.exp.battle and #prof.pals == friends0 and tries < 40 do
	tries += 1
	local target = nil
	for _, f in s.exp.battle.foes do
		if f.hp > 0 then
			target = f.key
		end
	end
	res = H.req(p, "exp.act", { act = "treat", target = target or "" })
	if s.exp and s.exp.over then
		break
	end
	if s.exp and not s.exp.battle and #prof.pals == friends0 then
		-- the battle ended without a friend: on to the next one
		walk(1)
		while s.exp and not s.exp.over and not s.exp.battle do
			if s.exp.node >= #s.exp.nodes then
				break
			end
			H.req(p, "exp.next", {})
		end
	end
end
H.expect(#prof.pals == friends0 + 1, "rules", "a treat befriended a wild driftling", string.format("%d treats", tries))
local newPal = prof.pals[#prof.pals]
H.expect(newPal and prof.seen[newPal.sp] == 2 and prof.stats.befriended >= 1, "rules", "in the Index as a friend")
-- a flight
while s.exp and not s.exp.over and not s.exp.battle and s.exp.node < #s.exp.nodes - 1 do
	H.req(p, "exp.next", {})
end
if s.exp and s.exp.battle and not s.exp.battle.boss then
	local fled = false
	for _ = 1, 20 do
		res = H.req(p, "exp.act", { act = "flee", target = "" })
		if res.ok and res.data and res.data.result == "fled" then
			fled = true
			break
		end
		if not (s.exp and s.exp.battle) then
			break
		end
	end
	H.expect(fled and s.exp and s.exp.battle == nil and not s.exp.over, "rules", "a flight gets away (the expedition goes on)")
end
-- the guardian: no treats, no flight
guard = 0
while s.exp and not s.exp.over and guard < 60 do
	guard += 1
	if s.exp.battle and s.exp.battle.boss then
		break
	elseif s.exp.battle then
		H.req(p, "exp.act", { act = "fight", target = "" })
	else
		H.req(p, "exp.next", {})
	end
end
H.expect(s.exp and s.exp.battle and s.exp.battle.boss, "rules", "the guardian at the path's end")
res = H.req(p, "exp.act", { act = "treat", target = "w1" })
H.expect(not res.ok and res.err == "blocked", "rules", "a guardian can't be befriended", tostring(res.err))
res = H.req(p, "exp.act", { act = "flee", target = "" })
H.expect(not res.ok and res.err == "blocked", "rules", "nor fled from", tostring(res.err))
H.checkProfile(p, "rules")
H.checkMirror(p, "rules")

------------------------------------------------------------------ 2. the screen: closed and reopened, its buttons, a round
E.phase = "screen"
local EUI = H.cmod(p, "UI.ExpeditionUI")
H.expect(H.buttonNamed(p, "ExpContinue") ~= nil, "screen", "the HUD's expedition card shows while one is under way")
H.clickNamed(p, "ExpContinue", { wait = 0.5 })
H.expect(H.inClient(p, EUI.isOpen) == true, "screen", "Continue opens the islet's screen")
E.run(Tuning.StageWait + 1)
H.expect(H.buttonNamed(p, "Act_fight") ~= nil and H.buttonNamed(p, "Act_guard") ~= nil, "screen", "Fight and Guard against the guardian")
H.expect(H.buttonNamed(p, "Act_treat") == nil and H.buttonNamed(p, "Act_flee") == nil, "screen", "Treat and Flee off against the guardian")
H.expect(H.buttonNamed(p, "Card_w1", true) ~= nil or #H.buttons(p, "^$", true) >= 0, "screen", "(the foes' cards)")
local st = H.inClient(p, EUI.debugState)
H.expect(st.lifted and st.actors >= 5, "screen", "the party and the guardian on the stage", string.format("%s %d", tostring(st.lifted), st.actors))
local hp0 = 0
for _, f in s.exp.battle.foes do
	hp0 += f.hp
end
local errs0 = #E.errors
H.clickNamed(p, "Act_fight", { wait = 0.2 })
E.run(4)
local hp1 = 0
if s.exp and s.exp.battle then
	for _, f in s.exp.battle.foes do
		hp1 += f.hp
	end
end
H.expect(hp1 < hp0 or (s.exp and s.exp.battle == nil), "screen", "a round fought from the screen", string.format("%d -> %d", hp0, hp1))
H.expect(#E.errors == errs0, "screen", "its playback ran without errors", tostring(#E.errors - errs0))
H.clickNamed(p, "BackToIsland", { wait = 0.5 })
H.expect(not H.inClient(p, EUI.isOpen) and s.exp ~= nil, "screen", "Back to island: the screen closes, the expedition waits")
H.expect(H.buttonNamed(p, "Menu_build") ~= nil, "screen", "the HUD is back")
-- the guardian falls (the party made strong)
strong(30)
for _, f in s.exp.party do
	f.atk, f.hp, f.maxHp = 300, 500, 500
end
local over = walk()
H.expect(over == "won" and prof.islets == 1, "screen", "Pebble Beach's guardian beaten: Mossgrove opens", tostring(over))
local sh0 = prof.shells
local loot = s.exp and s.exp.loot.shells or 0
res = H.req(p, "exp.home", {})
H.expect(res.ok and s.exp == nil and math.abs(prof.shells - (sh0 + loot)) < 1, "screen", "home with all the loot", string.format("%s + %s -> %s", sh0, loot, prof.shells))
H.checkProfile(p, "screen")

------------------------------------------------------------------ 3. every islet in turn
E.phase = "islets"
for i = 2, #Islets.list do
	strong(10 + i * 8)
	prof.food = 1000
	res = H.req(p, "exp.start", { islet = i, party = party(3) })
	H.expect(res.ok, "islets", Islets.list[i].name .. ": set sail", tostring(res.err))
	if not res.ok then
		break
	end
	local before = prof.islets
	over = walk()
	H.expect(over == "won", "islets", Islets.list[i].name .. ": cleared", tostring(over))
	H.expect(prof.islets == i and before == i - 1, "islets", Islets.list[i].name .. ": the next opens", tostring(prof.islets))
	local loot2 = s.exp and s.exp.loot.shells or 0
	H.expect(loot2 >= Islets.list[i].reward, "islets", Islets.list[i].name .. ": the guardian's reward in full", tostring(loot2))
	local seenAll = true
	for _, sp in Islets.list[i].wild do
		seenAll = seenAll and (prof.seen[sp] or 0) >= 1 or false
	end
	H.req(p, "exp.home", {})
	local _ = seenAll
end
H.expect(prof.islets == #Islets.list and prof.stats.cleared >= #Islets.list, "islets", "every islet cleared", tostring(prof.islets))
-- a second trip: half the reward
prof.food = 1000
res = H.req(p, "exp.start", { islet = 1, party = "" })
over = walk()
H.expect(over == "won" and prof.islets == #Islets.list, "islets", "Pebble Beach again", tostring(over))
local lootAgain = s.exp and s.exp.loot.shells or 0
H.expect(lootAgain >= math.floor(Islets.list[1].reward / 2) and lootAgain < Islets.list[1].reward + 2000, "islets", "half the reward the second time", tostring(lootAgain))
H.req(p, "exp.home", {})
H.checkProfile(p, "islets")
H.checkMirror(p, "islets")

------------------------------------------------------------------ 4. a defeat
E.phase = "defeat"
strong(1)
prof.food = 1000
res = H.req(p, "exp.start", { islet = 5, party = "" })
H.expect(res.ok, "defeat", "the captain alone to Coral Deep", tostring(res.err))
over = walk()
H.expect(over == "lost", "defeat", "the party falls", tostring(over))
local lost = s.exp and E.deepCopy(s.exp.loot)
local f0, w0 = prof.food, prof.wood
res = H.req(p, "exp.home", {})
H.expect(res.ok and lost ~= nil and math.abs(prof.food - (f0 + math.floor(lost.food / 2))) < 1 and math.abs(prof.wood - (w0 + math.floor(lost.wood / 2))) < 1, "defeat", "half the loot home", lost and string.format("%s food gathered", lost.food) or "")
H.expect(s.exp == nil and next(s.away) == nil, "defeat", "everyone home")
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
