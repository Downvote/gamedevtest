-- Expeditions (Logic/Expedition; GAME_DESIGN 7): what a wild place holds, made up from a level, a seed and its kind;
-- going into one of the island's places, walking its path, battles' ends, befriending, the guardian clearing the
-- place (a big reward the first time, a small one after; the trip over), heading home (all the loot, a defeat too).
-- (Logic/Sites, the places coming up: Sites.spec.)
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Expedition = require("../../build/luautest/shared/Logic/Expedition")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Util = require("../../build/luautest/shared/Logic/Util")
local Sites = require("../../build/luautest/shared/Logic/Sites")
local SiteData = require("../../build/luautest/shared/Data/Sites")
local Traits = require("../../build/luautest/shared/Data/Traits")

local function fresh(): any
	local p = Schema.default(0, 1)
	p.food = 500
	return p
end

-- Let the battle run to its end (half a second a step); returns the last result.
local function fightOut(p: any, e: any, rng: any): string?
	local result = nil
	local guard = 0
	while e.battle and guard < 2000 do
		guard += 1
		e.battle.paused = false
		local out = Expedition.tick(p, e, 0.5, rng)
		if out and out.result then
			result = out.result
		end
	end
	return result
end

return function()
	T.it("charting: the same level and seed make the same island; its kind open at the level; its words, driftlings, path and loot", function()
		local a = Expedition.chart(7, 1234)
		local b = Expedition.chart(7, 1234)
		T.deepEq(a, b)
		T.deepEq(Expedition.nodesOf(a), Expedition.nodesOf(b))
		local kinds: { [number]: boolean } = {}
		local names: { [string]: boolean } = {}
		for lvl = 1, 40, 3 do
			for seed = 1, 40 do
				local isle = Expedition.chart(lvl, seed * 7919)
				local def = Islets.list[isle.kind]
				T.truthy(def.lvl <= lvl, string.format("a %s at level %d", def.name, lvl))
				kinds[isle.kind] = true
				names[isle.name] = true
				local first, last = string.match(isle.name, "^(%S+) (%S+)$")
				T.truthy(first and table.find(def.first, first) and table.find(def.last, last), isle.name)
				-- every one of its kind, and maybe a common stray from another open kind
				for _, sp in def.wild do
					T.truthy(table.find(isle.wild, sp) ~= nil, "its own " .. sp)
				end
				T.truthy(#isle.wild == #def.wild or #isle.wild == #def.wild + 1, "its own and a stray")
				if #isle.wild > #def.wild then
					local stray = isle.wild[#isle.wild]
					T.truthy(table.find(Expedition.speciesAt(lvl), stray) and Creatures.byId[stray].rarity <= 2, "a common stray from an open kind")
				end
				-- its guardian: one of its own rare or epic ones
				T.truthy(table.find(def.wild, isle.boss) and string.find(isle.bossName, Creatures.byId[isle.boss].name, 1, true), "its guardian")
				T.truthy(Creatures.byId[isle.boss].rarity >= 3 and Creatures.byId[isle.boss].rarity <= 4, "a rare or epic guardian")
				-- the path ends at its guardian (GAME_DESIGN 7: "caves are no longer infinite")
				local nodes = Expedition.nodesOf(isle)
				T.eq(nodes[1], "start")
				T.eq(#nodes, 1 + Tuning.BossEvery, "the landing and BossEvery stages")
				T.eq(nodes[#nodes], "boss", "the guardian last")
				T.eq(Expedition.guardianAt(#nodes), 1)
				local wild = 0
				for i = 2, #nodes - 1 do
					T.truthy(nodes[i] == "wild" or nodes[i] == "loot" or nodes[i] == "chest" or nodes[i] == "rest", nodes[i])
					wild += if nodes[i] == "wild" then 1 else 0
				end
				T.truthy(wild >= 3, "battles on the way")
				T.deepEq(Expedition.nodesTo(isle, 40), nodes, "never longer")
			end
		end
		T.truthy(kinds[1] and kinds[2] and kinds[3] and kinds[4] and kinds[5], "every kind turns up")
		local n = 0
		for _ in names do
			n += 1
		end
		T.truthy(n >= 60, "many names: " .. n)
		local lo, hi = Expedition.chart(1, 5), Expedition.chart(20, 5)
		T.eq(Expedition.chart(1, 9).kind, 1, "only beaches at level 1")
		T.truthy(hi.loot.food > lo.loot.food and hi.loot.wood > lo.loot.wood and hi.loot.shells > lo.loot.shells and hi.reward > lo.reward, "a higher level holds more")
		T.truthy(Expedition.levelAt(hi, 2) == 19 and Expedition.levelAt(hi, 10) == 19 + math.floor(8 * Tuning.StageLvl), "the wild grow along the path")
		T.truthy(Expedition.boostAt(3) > Expedition.boostAt(2) and Expedition.boostAt(2) > Expedition.boostAt(1) - 1e-9, "and grow stronger every stage")
		T.eq(Expedition.levelAt(lo, 1), 1)
		T.eq(Expedition.rewardOf(hi, true), math.floor(hi.reward * Tuning.FirstClear + 0.5), "the first clear pays the most")
		T.truthy(Expedition.rewardOf(hi, false) < Expedition.rewardOf(hi, true), "a later clear pays less")
		-- a wild place's own: its kind's, named after it
		for _, sd in SiteData.list do
			local isle = Expedition.chart(9, 77, sd.islet)
			T.eq(isle.kind, sd.islet, sd.id .. ": its kind")
			T.truthy(string.find(isle.name, sd.name, 1, true) ~= nil, sd.id .. ": named " .. isle.name)
			local w1 = string.match(isle.name, "^(%a+)")
			T.truthy(w1 ~= nil and not string.find(string.lower(sd.name), string.lower(w1 :: string), 1, true), sd.id .. ": no word twice: " .. isle.name)
		end
	end)
	T.it("setting out: members who exist, supplies for each", function()
		local p = fresh()
		local isle = Expedition.chart(4, 99)
		T.eq(select(2, Expedition.start(p, isle, { "v7" })), "not_found")
		table.insert(p.folk, { id = 7, name = "Ana", look = p.founder, work = 0, lvl = 2, xp = 0, seed = 3, day = 1 })
		table.insert(p.pals, { id = 8, sp = "pebblit", lvl = 1, xp = 0, work = 0 })
		T.eq(select(2, Expedition.start(p, isle, { "v7", "v7" })), "bad_payload")
		T.eq(select(2, Expedition.start(p, isle, { "v7", "p8", "v7", "p8" })), "full")
		p.food = 3
		T.eq(select(2, Expedition.start(p, isle, { "v7" })), "food")
		p.food = 100
		local ok, e = Expedition.start(p, isle, { "v7", "p8" })
		T.truthy(ok)
		T.eq(p.food, 100 - Tuning.Supplies * 3)
		T.eq(#e.party, 3)
		T.eq(e.party[1].key, "f")
		T.eq(e.party[2].name, "Ana")
		T.eq(e.node, 1)
		T.deepEq(e.isle, isle)
		T.deepEq(e.nodes, Expedition.nodesOf(isle))
		local away = Expedition.away(e)
		T.truthy(away.v7 and away.p8 and away.f)
	end)
	T.it("a wild place: its card's isle, going in by its piece, the path, the guardian clearing it, the trip over", function()
		local p = fresh()
		p.cap.lvl = 12
		local pool: any = nil
		for _, q in p.plot.placed do
			if q.id == SiteData.wildId("tidepool") then
				pool = q
			end
		end
		T.truthy(pool ~= nil, "a new island has its tide pool")
		local isle = Expedition.isleOf(p, pool)
		T.eq(isle.kind, SiteData.byId.tidepool.islet)
		T.eq(isle.lvl, pool.lvl)
		T.eq(isle.id, pool.uid)
		T.deepEq(Expedition.isleOf(p, pool), isle, "the same place every visit")
		T.eq(select(2, Expedition.enter(p, 99999, {})), "not_found")
		local okE, e = Expedition.enter(p, pool.uid, {})
		T.truthy(okE)
		T.eq(e.site, pool.uid)
		local rng = Util.newRng(11)
		local kinds = {}
		local first = #e.nodes
		while e.node < first and not e.over do
			local ok, data = Expedition.next(p, e, rng)
			T.truthy(ok, tostring(data))
			table.insert(kinds, data.kind)
			if e.battle then
				T.eq(select(2, Expedition.next(p, e, rng)), "in_battle")
				T.truthy(p.seen[e.battle.foes[1].sp] ~= nil, "met")
				for _, f in e.battle.foes do
					T.truthy(table.find(e.isle.wild, f.sp) or f.sp == e.isle.boss, "the island's own: " .. tostring(f.sp))
				end
				fightOut(p, e, rng)
			end
		end
		T.deepEq(kinds, { table.unpack(e.nodes, 2, first) })
		T.eq(e.over, "won", "the guardian beaten: the trip is over")
		T.eq(e.beaten, 1)
		T.eq(p.islets, 1, "the place cleared")
		T.eq(p.stats.cleared, 1)
		T.eq(pool.id, SiteData.doneId("tidepool"), "no longer wild")
		T.truthy(e.loot.shells >= Expedition.rewardOf(e.isle, true), "the first clear's reward")
		T.truthy(e.loot.food > 0 and e.loot.wood > 0)
		T.truthy(p.cap.xp > 0 or p.cap.lvl > 12, "the captain learned")
		T.eq(select(2, Expedition.next(p, e, rng)), "no_exp", "nothing after the guardian")
		local shells = p.shells
		local got = Expedition.home(p, e)
		T.eq(p.shells, shells + got.shells)
		T.eq(got.shells, e.loot.shells)
		-- the same place again: it is cleared already, so it pays less and counts once
		local _, e2 = Expedition.enter(p, pool.uid, {})
		e2.party[1].atk, e2.party[1].hp, e2.party[1].maxHp = 5000, 99999, 99999
		while not e2.over do
			Expedition.next(p, e2, rng)
			if e2.battle then
				local before = e2.loot.shells
				local guardian = e2.battle.boss
				fightOut(p, e2, rng)
				if guardian then
					T.truthy(e2.loot.shells - before >= Expedition.rewardOf(e2.isle, false), "a later clear's reward")
					T.truthy(e2.loot.shells - before < Expedition.rewardOf(e2.isle, true), "less than the first")
				end
			end
		end
		T.eq(e2.over, "won")
		T.eq(p.islets, 1, "cleared once")
		T.eq(p.stats.cleared, 2)
	end)
	T.it("befriending: a snack is one of the trip's few and needs a nest; the friend joins the island", function()
		local p = fresh()
		p.cap.lvl = 6
		local _, e = Expedition.start(p, Expedition.chart(1, 3), {})
		T.eq(e.snacks, Tuning.SnackBase, "five snacks a trip with the first pouch")
		local rng = Util.newRng(4)
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		T.eq(select(2, Expedition.snack(p, e, "w1", rng)), "no_room")
		table.insert(p.plot.placed, { uid = 900, id = "nest", x = 0, z = 0, rot = 0 })
		local food = p.food
		local joined = nil
		local thrown = 0
		local born: { [string]: { string } } = {}
		while e.battle and e.snacks > 0 do
			local target = nil
			for _, f in e.battle.foes do
				if f.hp > 0 then
					f.hp = 1 -- (worn out: the snack likelier caught)
					target = f.key
					f.muts = { "fierce3", "lazy" } -- (born with these: they come along)
					born[f.key] = f.muts :: { string }
				end
			end
			local ok, data = Expedition.snack(p, e, target, rng)
			T.truthy(ok)
			thrown += 1
			if data.friend then
				joined = data.friend
			end
		end
		T.eq(p.food, food, "snacks cost no food")
		T.truthy(thrown <= Tuning.SnackBase)
		T.truthy(joined ~= nil, "a driftling joined")
		if joined then
			T.eq(p.pals[#p.pals].sp, joined.sp)
			T.eq(p.seen[joined.sp], 2)
			T.eq(p.stats.befriended, #p.pals)
			T.eq(e.befriended[#e.befriended], joined.sp)
			T.deepEq(p.pals[#p.pals].muts, { "fierce3", "lazy" }, "its mutations come with it")
			local f = Expedition.fighter(p, "p" .. p.pals[#p.pals].id)
			T.truthy(f ~= nil and f.muts ~= nil, "and its fighter carries them")
		end
		-- none left: refused
		e.snacks = 0
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		if not e.battle.boss then
			T.eq(select(2, Expedition.snack(p, e, "w1", rng)), "no_snacks")
		end
	end)
	T.it("the snack pouch: 5 snacks a trip, 30 at its biggest; each level paid in shells and wood", function()
		local p = fresh()
		T.eq(p.pouch, 1)
		T.eq(Expedition.snacksFor(p), 5)
		p.shells, p.wood = 0, 0
		T.eq(select(2, Expedition.upgradePouch(p)), "money")
		p.shells, p.wood = 1e6, 1e6
		for lvl = 2, #Tuning.PouchCost do
			local shells = p.shells
			local ok, data = Expedition.upgradePouch(p)
			T.truthy(ok)
			T.eq(data.pouch, lvl)
			T.eq(p.shells, shells - Tuning.PouchCost[lvl].shells)
		end
		T.eq(Expedition.snacksFor(p), 30)
		T.eq(select(2, Expedition.upgradePouch(p)), "max")
		local _, e = Expedition.start(p, Expedition.chart(1, 3), {})
		T.eq(e.snacks, 30)
	end)
	T.it("a battle starts paused; pause and run; skills and fleeing go through the expedition", function()
		local p = fresh()
		p.cap.lvl = 6
		local _, e = Expedition.start(p, Expedition.chart(1, 5), {})
		local rng = Util.newRng(6)
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		T.truthy(e.battle.paused)
		T.eq(Expedition.tick(p, e, 5, rng), nil, "paused: nothing happens")
		local ok, g = Expedition.pause(e, false)
		T.truthy(ok and not g.paused and type(g.g) == "table")
		local seen = false
		for _ = 1, 40 do
			local out = Expedition.tick(p, e, 0.5, rng)
			if out then
				seen = true
				T.truthy(type(out.events) == "table")
				break
			end
		end
		T.truthy(seen, "it runs")
		if e.battle then
			e.battle.sp = 10
			local ok2 = Expedition.skill(p, e, "f", "cry", nil, rng)
			T.truthy(ok2, "the leader's Rally Cry")
			if not e.battle.boss then
				T.truthy((Expedition.flee(p, e, rng)), "a run (whether it gets away or not)")
			end
		end
		T.eq(select(2, Expedition.pause({ over = "home" } :: any, true)), "no_exp")
	end)
	T.it("wild ones by rarity: the commons most often, a legend now and then", function()
		local isle = Expedition.chart(12, 4242)
		isle.kind = 3
		isle.wild = table.clone(Islets.list[3].wild)
		local rng = Util.newRng(9)
		local byRarity: { [number]: number } = {}
		for _ = 1, 6000 do
			local cd = Creatures.byId[Expedition.pickWild(isle, rng)]
			byRarity[cd.rarity] = (byRarity[cd.rarity] or 0) + 1
		end
		T.truthy((byRarity[1] or 0) > (byRarity[2] or 0) and (byRarity[2] or 0) > (byRarity[3] or 0), "commons, then uncommons, then rares")
		T.truthy((byRarity[3] or 0) > (byRarity[4] or 0) and (byRarity[4] or 0) > (byRarity[5] or 0), "rares, then epics, then legends")
		T.truthy((byRarity[5] or 0) > 0, "a legend does turn up")
	end)
	T.it("wild ones are born with mutations (a guardian a rarity up); a driftling's learning share grows its xp", function()
		local p = fresh()
		p.cap.lvl = 30
		local isle = Expedition.chart(20, 77)
		local _, e = Expedition.start(p, isle, {})
		local rng = Util.newRng(21)
		local seen, with = 0, 0
		for k = 1, 60 do
			while e.battle == nil and e.node < #e.nodes and not e.over do
				Expedition.next(p, e, rng)
			end
			if e.battle == nil then
				-- (the path ran out: a new trip to another place of the level)
				_, e = Expedition.start(p, Expedition.chart(20, 77 + k), {})
				while e.battle == nil and e.node < #e.nodes do
					Expedition.next(p, e, rng)
				end
			end
			for _, f in e.battle.foes do
				seen += 1
				if f.muts then
					with += 1
					T.deepEq(Traits.clean(f.muts), f.muts, "a clean list")
				end
			end
			e.battle = nil
		end
		T.truthy(with > seen * 0.4 and with < seen, "most, not all, carry some")
		-- the learning share: a Genius driftling gains more from the same win
		local function xpAfter(muts: { string }): number
			local q = fresh()
			q.cap.lvl = 30
			table.insert(q.plot.placed, { uid = 900, id = "nest", x = 0, z = 0, rot = 0 })
			table.insert(q.pals, { id = 50, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = muts })
			local _, ex = Expedition.start(q, Expedition.chart(1, 3), { "p50" })
			local r = Util.newRng(5)
			while ex.battle == nil and ex.node < #ex.nodes and not ex.over do
				Expedition.next(q, ex, r)
			end
			for _, f in ex.battle.foes do
				f.hp = 0
			end
			ex.battle.paused = false
			for _ = 1, 400 do
				local _, out = Expedition.tick(q, ex, 0.25, r)
				if out and out.result then
					break
				end
			end
			return q.pals[1].lvl * 1000 + q.pals[1].xp
		end
		T.truthy(xpAfter({ "bright4" }) > xpAfter({}), "Genius learns faster")
	end)
	T.it("the tips: setting sail moves them to fighting, the first battle's end to catching, a friend to the last", function()
		local p = fresh()
		p.tut = 5
		local _, e = Expedition.start(p, Expedition.chart(1, 8), {})
		T.eq(p.tut, 6, "set sail: the first fight")
		local rng = Util.newRng(3)
		e.party[1].hp, e.party[1].maxHp, e.party[1].atk = 9999, 9999, 999
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		fightOut(p, e, rng)
		T.eq(p.tut, 7, "the first battle over: catching")
		-- a friend made (a free nest, snacks to spare, a worn-out wild one)
		table.insert(p.plot.placed, { uid = p.nextId, id = "nest", x = 0, z = 0, rot = 0 })
		p.nextId += 1
		e.snacks = 99
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		-- the tips' first snack always befriends, even a wild one at full health and far above the party
		local foe = e.battle.foes[1]
		foe.lvl, foe.hp = 60, foe.maxHp
		local ok, out = Expedition.snack(p, e, foe.key, rng)
		T.truthy(ok and out.friend ~= nil, "the first snack: a friend for sure")
		T.eq(p.tut, 8, "a driftling befriended: the last tip")
		-- after the tips: the chance again (a healthy wild one far above the party rarely takes one)
		local misses = 0
		for _ = 1, 20 do
			local q = fresh()
			q.tut = 0
			table.insert(q.plot.placed, { uid = q.nextId, id = "nest", x = 0, z = 0, rot = 0 })
			q.nextId += 1
			local _, ex = Expedition.start(q, Expedition.chart(1, 8), {})
			while ex.battle == nil and ex.node < #ex.nodes and not ex.over do
				Expedition.next(q, ex, rng)
			end
			local w = ex.battle.foes[1]
			w.lvl, w.hp = 60, w.maxHp
			local okq, o = Expedition.snack(q, ex, w.key, rng)
			if okq and o.friend == nil then
				misses += 1
			end
		end
		T.truthy(misses > 0, "outside the tips a snack can miss")
	end)
	T.it("losing: the expedition ends, all the loot comes home (no penalty)", function()
		local p = fresh()
		local _, e = Expedition.start(p, Expedition.chart(1, 8), {})
		e.loot.shells, e.loot.food = 100, 40
		e.party[1].hp, e.party[1].atk = 1, 1
		local rng = Util.newRng(2)
		while e.battle == nil and e.node < #e.nodes and not e.over do
			Expedition.next(p, e, rng)
		end
		local result = fightOut(p, e, rng)
		T.eq(result, "lose")
		T.eq(e.over, "lost")
		T.eq(p.islets, 0, "not charted")
		local shells = p.shells
		local loot = table.clone(e.loot)
		local got = Expedition.home(p, e)
		T.truthy(loot.shells >= 100, "the shells found before the fall")
		T.eq(got.shells, math.floor(loot.shells), "every shell home")
		T.eq(p.shells, shells + math.floor(loot.shells))
		T.eq(got.food, math.floor(loot.food), "all the food too")
		T.eq(got.wood, math.floor(loot.wood))
	end)
	T.it("the wild ones grow harder along the path; a place cleared away meanwhile pays as a later clear", function()
		local p = fresh()
		p.cap.lvl = 60
		local cave: any = nil
		for _, q in p.plot.placed do
			if q.id == SiteData.wildId("tallgrass") then
				cave = q
			end
		end
		local _, e = Expedition.enter(p, cave.uid, {})
		e.party[1].atk, e.party[1].hp, e.party[1].maxHp = 5000, 99999, 99999
		-- (the place gone from the island while the party is in it: nothing to clear)
		for i, q in p.plot.placed do
			if q == cave then
				table.remove(p.plot.placed, i)
				break
			end
		end
		local rng = Util.newRng(9)
		local lvls = {}
		while not e.over do
			Expedition.next(p, e, rng)
			if e.battle then
				table.insert(lvls, e.battle.foes[1].lvl)
				fightOut(p, e, rng)
			end
		end
		T.truthy(lvls[#lvls] > lvls[1], "the wild ones grow")
		T.eq(e.over, "won")
		T.eq(p.islets, 0, "nothing cleared: the place was gone")
		T.eq(#Sites.spawn(p), 0, "and nothing comes back up")
	end)
	T.it("a low place is gentle: the new island's level 1 place is cleared by the founder and the first villager every time", function()
		-- ("the lvl 1 cave should be easy enough to be beaten by starting 2 members of the party all the time",
		-- 2026-11-12) both level 1, the battles left to run by themselves: no snacks, no skills, no fleeing
		local Island = require("../../build/luautest/shared/Logic/Island")
		local wins, worst, N = 0, math.huge, 400
		for seed = 1, N do
			local p = Schema.default(0, seed)
			p.food = 500
			local rng = Util.newRng(seed * 31 + 7)
			local v = Island.moveIn(p, rng)
			local uid = 0
			for _, q in p.plot.placed do
				if q.id == SiteData.wildId("tidepool") and q.lvl == 1 then
					uid = q.uid
				end
			end
			local ok, e = Expedition.enter(p, uid, { "v" .. v.id })
			T.truthy(ok, "seed " .. seed .. ": in")
			local guard = 0
			while e.over == nil and guard < 5000 do
				guard += 1
				if e.battle then
					e.battle.paused = false
					Expedition.tick(p, e, 0.5, rng)
				elseif not Expedition.next(p, e, rng) then
					break
				end
			end
			if e.over == "won" then
				wins += 1
				local h, m = 0, 0
				for _, f in e.party do
					h += math.max(0, f.hp)
					m += f.maxHp
				end
				worst = math.min(worst, h / m)
			end
		end
		T.eq(wins, N, "cleared every time")
		T.truthy(worst > 0.3, string.format("with health to spare (the worst run ends at %.2f)", worst))
		-- the climb: a low place climbs only its share, a place from ClimbFull up all of it
		local low, full = Expedition.chart(1, 5, 1), Expedition.chart(Tuning.ClimbFull, 5, 1)
		T.near(Expedition.climbOf(low), 1 / Tuning.ClimbFull, 1e-9)
		T.eq(Expedition.climbOf(full), 1)
		T.truthy(Expedition.levelAt(low, 8) < Expedition.levelAt(Expedition.chart(1, 5), 8) + math.floor(7 * Tuning.StageLvl) and Expedition.levelAt(low, 8) <= 2, "the level 1 place's guardian stage barely climbs")
		T.truthy(Expedition.guardianBoost(low) < 1 and Expedition.guardianBoost(full) == 1, "a low place's guardian keeps only its share of the extra strength")
	end)
	T.it("no fleeing a guardian, no snacks for it", function()
		local p = fresh()
		p.cap.lvl = 30
		local _, e = Expedition.start(p, Expedition.chart(1, 21), {})
		local rng = Util.newRng(5)
		while e.node < #e.nodes - 1 do
			Expedition.next(p, e, rng)
			fightOut(p, e, rng)
		end
		Expedition.next(p, e, rng)
		T.truthy(e.battle and e.battle.boss)
		T.eq(e.battle.foes[1].name, e.isle.bossName)
		T.eq(select(2, Expedition.flee(p, e, rng)), "blocked")
		T.eq(select(2, Expedition.snack(p, e, "w1", rng)), "blocked")
	end)
end
