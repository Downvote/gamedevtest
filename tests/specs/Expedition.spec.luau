-- Expeditions (Logic/Expedition; GAME_DESIGN 7): islands made up from a level and a seed, setting out for one,
-- walking the island's path, battles' ends, befriending, the guardian charting the island (its whole reward the first
-- time, half after), sailing home (all the loot, a defeat too). (Logic/Chart: Chart.spec.)
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Expedition = require("../../build/luautest/shared/Logic/Expedition")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Util = require("../../build/luautest/shared/Logic/Util")

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
				-- the path never ends: blocks of BossEvery stages, a guardian at the end of each
				local nodes = Expedition.nodesTo(isle, 1 + Tuning.BossEvery * 4)
				T.eq(nodes[1], "start")
				T.eq(#nodes, 1 + Tuning.BossEvery * 4)
				for k = 1, 4 do
					local g = 1 + Tuning.BossEvery * k
					T.eq(nodes[g], "boss", "a guardian every BossEvery stages")
					T.eq(Expedition.guardianAt(g), k)
					local wild = 0
					for i = g - Tuning.BossEvery + 1, g - 1 do
						T.truthy(nodes[i] == "wild" or nodes[i] == "loot" or nodes[i] == "chest" or nodes[i] == "rest", nodes[i])
						wild += if nodes[i] == "wild" then 1 else 0
					end
					T.truthy(wild >= 3, "battles on the way")
				end
				T.deepEq(Expedition.nodesOf(isle), { table.unpack(nodes, 1, 1 + Tuning.BossEvery) }, "the first block")
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
		T.truthy(Expedition.levelAt(hi, 200) > Tuning.LevelMax, "without end")
		T.eq(Expedition.levelAt(lo, 1), 1)
		T.truthy(Expedition.rewardOf(hi, 3) > Expedition.rewardOf(hi, 2) and Expedition.rewardOf(hi, 2) > Expedition.rewardOf(hi, 1), "later guardians pay more")
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
	T.it("the path: loot, battles in the way, a rest, the guardian charting the island, and on", function()
		local p = fresh()
		p.cap.lvl = 12
		local _, e = Expedition.start(p, Expedition.chart(1, 77), {})
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
		T.eq(e.over, nil, "the guardian beaten, the path goes on")
		T.eq(e.beaten, 1)
		T.eq(p.islets, 1, "the island charted")
		T.eq(p.stats.cleared, 1)
		T.eq(e.loot.shells >= e.isle.reward, true, "its whole reward")
		T.truthy(e.loot.food > 0 and e.loot.wood > 0 and e.loot.shells >= e.isle.reward)
		T.truthy(p.cap.xp > 0 or p.cap.lvl > 12, "the captain learned")
		T.truthy((Expedition.next(p, e, rng)), "the path goes on past the guardian")
		local shells = p.shells
		local got = Expedition.home(p, e)
		T.eq(p.shells, shells + got.shells)
		T.eq(got.shells, e.loot.shells)
	end)
	T.it("befriending: a snack is one of the trip's few and needs a nest; the friend joins the island", function()
		local p = fresh()
		p.cap.lvl = 6
		local _, e = Expedition.start(p, Expedition.chart(1, 3), {})
		T.eq(e.snacks, Tuning.SnackBase, "five snacks a trip with the first pouch")
		local rng = Util.newRng(4)
		while e.battle == nil do
			Expedition.next(p, e, rng)
		end
		T.eq(select(2, Expedition.snack(p, e, "w1", rng)), "no_room")
		table.insert(p.plot.placed, { uid = 900, id = "nest", x = 0, z = 0, rot = 0 })
		local food = p.food
		local joined = nil
		local thrown = 0
		while e.battle and e.snacks > 0 do
			local target = nil
			for _, f in e.battle.foes do
				if f.hp > 0 then
					f.hp = 1 -- (worn out: the snack likelier caught)
					target = f.key
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
		end
		-- none left: refused
		e.snacks = 0
		while e.battle == nil do
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
		while e.battle == nil do
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
	T.it("the tips: setting sail moves them to fighting, the first battle's end to catching, a friend to the last", function()
		local p = fresh()
		p.tut = 5
		local _, e = Expedition.start(p, Expedition.chart(1, 8), {})
		T.eq(p.tut, 6, "set sail: the first fight")
		local rng = Util.newRng(3)
		e.party[1].hp, e.party[1].maxHp, e.party[1].atk = 9999, 9999, 999
		while e.battle == nil do
			Expedition.next(p, e, rng)
		end
		fightOut(p, e, rng)
		T.eq(p.tut, 7, "the first battle over: catching")
		-- a friend made (a free nest, snacks to spare, a worn-out wild one)
		table.insert(p.plot.placed, { uid = p.nextId, id = "nest", x = 0, z = 0, rot = 0 })
		p.nextId += 1
		e.snacks = 99
		while e.battle == nil do
			Expedition.next(p, e, rng)
		end
		for _, f in e.battle.foes do
			f.lvl, f.hp = 1, 1
		end
		for _ = 1, 40 do
			local foe = nil
			for _, f in e.battle.foes do
				if f.hp > 0 then
					foe = f
				end
			end
			if e.battle == nil or foe == nil then
				break
			end
			Expedition.snack(p, e, foe.key, rng)
			if p.tut == 8 then
				break
			end
		end
		T.eq(p.tut, 8, "a driftling befriended: the last tip")
	end)
	T.it("losing: the expedition ends, all the loot comes home (no penalty)", function()
		local p = fresh()
		local _, e = Expedition.start(p, Expedition.chart(1, 8), {})
		e.loot.shells, e.loot.food = 100, 40
		e.party[1].hp, e.party[1].atk = 1, 1
		local rng = Util.newRng(2)
		while e.battle == nil do
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
	T.it("on past the guardian: the next block, harder wild ones, a second guardian paying more", function()
		local p = fresh()
		p.cap.lvl = 60
		local _, e = Expedition.start(p, Expedition.chart(1, 31), {})
		e.party[1].atk, e.party[1].hp, e.party[1].maxHp = 5000, 99999, 99999
		local rng = Util.newRng(9)
		local rewards = {}
		local lvls = {}
		while (e.beaten or 0) < 2 and e.node < 40 do
			local ok, data = Expedition.next(p, e, rng)
			T.truthy(ok, tostring(data))
			if e.battle then
				table.insert(lvls, e.battle.foes[1].lvl)
				local guardian = e.battle.boss
				local before = e.loot.shells
				fightOut(p, e, rng)
				if guardian then
					table.insert(rewards, e.loot.shells - before)
				end
			end
		end
		T.eq(e.beaten, 2, "two guardians beaten")
		T.eq(e.node, 1 + Tuning.BossEvery * 2, "the second at the second block's end")
		T.eq(p.islets, 1, "charted once")
		T.truthy(rewards[2] > rewards[1], "the second guardian pays more")
		T.truthy(lvls[#lvls] > lvls[1], "the wild ones grow")
		T.eq(e.over, nil, "and the path goes on")
		local ok = Expedition.next(p, e, rng)
		T.truthy(ok, "a third block")
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
