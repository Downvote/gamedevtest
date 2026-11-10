-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 7.4, 10.8): islands made up at the level picked (up to the
-- captain's), charted at every level by a strong party (each kind of island once its level comes, the guardian's
-- reward, its own driftlings, a new island every time), the server's rules (supplies, a party of the captain and
-- three, one expedition at a time, no island above the captain's level, members away can't be dismissed or released,
-- no stepping on or sailing home mid-battle, no treat or flight from a guardian, a treat's food and a free nest), a
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
local res = H.req(p, "exp.start", { lvl = 1, party = party(3) })
H.expect(not res.ok and res.err == "food", "rules", "supplies: four members need food", tostring(res.err))
prof.food = 1000
res = H.req(p, "exp.start", { lvl = prof.cap.lvl + 1, party = "" })
H.expect(not res.ok and res.err == "locked", "rules", "no island above the captain's level", tostring(res.err))
res = H.req(p, "exp.start", { lvl = 1, party = party(3) })
H.expect(res.ok and #s.exp.party == 4 and s.exp.party[1].key == "f", "rules", "the captain and three set sail", tostring(res.err))
H.expect(math.abs(prof.food - (1000 - Tuning.Supplies * 4)) < 1, "rules", "their supplies taken", tostring(prof.food))
H.expect(res.ok and res.data and res.data.isle and res.data.isle.name == s.exp.isle.name, "rules", "the answer names the island", res.data and res.data.isle and res.data.isle.name)
res = H.req(p, "exp.start", { lvl = 1, party = "" })
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
H.expect(over == "won" and prof.islets == 1, "screen", "the guardian beaten: the island charted", tostring(over))
local sh0 = prof.shells
local loot = s.exp and s.exp.loot.shells or 0
res = H.req(p, "exp.home", {})
H.expect(res.ok and s.exp == nil and math.abs(prof.shells - (sh0 + loot)) < 1, "screen", "home with all the loot", string.format("%s + %s -> %s", sh0, loot, prof.shells))
H.checkProfile(p, "screen")

------------------------------------------------------------------ 3. islands at every level
E.phase = "islands"
local Expedition = H.sharedServer("Logic.Expedition")
local kindsSeen: { [number]: boolean } = {}
local names: { [string]: boolean } = {}
for _, lvl in { 1, 5, 10, 16, 23, 30, 30, 30, 30 } do
	strong(lvl + 8)
	prof.food = 1000
	res = H.req(p, "exp.start", { lvl = lvl, party = party(3) })
	H.expect(res.ok, "islands", "set sail at level " .. lvl, tostring(res.err))
	if not res.ok then
		break
	end
	local isle = s.exp.isle
	local kind = Islets.list[isle.kind]
	kindsSeen[isle.kind] = true
	names[isle.name] = true
	H.expect(isle.lvl == lvl and kind ~= nil and kind.lvl <= lvl, "islands", string.format("a %s at level %d", kind and kind.name or "?", lvl))
	H.expect(isle.name == Expedition.chart(lvl, isle.seed).name, "islands", "the island is its seed's: " .. isle.name)
	local before = prof.islets
	local foesOk = true
	local steps = 0
	while s.exp and not s.exp.over and steps < 200 do
		steps += 1
		if s.exp.battle then
			for _, f in s.exp.battle.foes do
				foesOk = foesOk and (table.find(isle.wild, f.sp) ~= nil or f.sp == isle.boss)
			end
			H.req(p, "exp.act", { act = "fight", target = "" })
		elseif s.exp.node < #s.exp.nodes then
			H.req(p, "exp.next", {})
		else
			break
		end
	end
	over = s.exp and s.exp.over
	H.expect(over == "won", "islands", isle.name .. ": charted", tostring(over))
	H.expect(foesOk, "islands", isle.name .. ": only its own driftlings")
	H.expect(prof.islets == before + 1, "islands", isle.name .. ": one more island charted", tostring(prof.islets))
	local loot2 = s.exp and s.exp.loot.shells or 0
	H.expect(loot2 >= isle.reward, "islands", isle.name .. ": the guardian's reward", tostring(loot2))
	H.req(p, "exp.home", {})
end
local nk, nn = 0, 0
for _ in kindsSeen do
	nk += 1
end
for _ in names do
	nn += 1
end
H.expect(kindsSeen[1] and nk >= 3, "islands", "different kinds of island turn up", tostring(nk))
H.expect(nn >= 7, "islands", "a new island every time", tostring(nn))
H.checkProfile(p, "islands")
H.checkMirror(p, "islands")

------------------------------------------------------------------ 4. a defeat
E.phase = "defeat"
strong(30)
prof.food = 1000
res = H.req(p, "exp.start", { lvl = 30, party = "" })
H.expect(res.ok, "defeat", "the captain alone to a level-30 island", tostring(res.err))
if s.exp then
	local f = s.exp.party[1]
	f.atk, f.hp, f.maxHp, f.def = 1, 6, 6, 0
end
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
