-- Expeditions (Logic/Expedition; GAME_DESIGN 7): islands made up from a level and a seed, setting out for one,
-- walking the island's path, battles' ends, befriending, the guardian charting the island (its whole reward the first
-- time, half after), sailing home. (Logic/Chart: Chart.spec.)
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

-- Fight every battle to its end; returns the last result.
local function fightOut(p: any, e: any, rng: any, act: string?): string?
	local result = nil
	local guard = 0
	while e.battle and guard < 60 do
		guard += 1
		local _, data = Expedition.act(p, e, act or "fight", "", rng)
		result = data.result
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
				T.eq(#isle.wild, 3)
				T.truthy(isle.wild[1] ~= isle.wild[2] and isle.wild[1] ~= isle.wild[3] and isle.wild[2] ~= isle.wild[3], "three species")
				T.truthy(table.find(def.wild, isle.wild[1]) and table.find(def.wild, isle.wild[2]), "two of its own")
				T.truthy(table.find(Expedition.speciesAt(lvl), isle.wild[3]), "a stray from an open kind")
				T.truthy(table.find(def.wild, isle.boss) and string.find(isle.bossName, Creatures.byId[isle.boss].name, 1, true), "its guardian")
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
	T.it("befriending: a treat costs food and needs a nest; the friend joins the island", function()
		local p = fresh()
		p.cap.lvl = 6
		local _, e = Expedition.start(p, Expedition.chart(1, 3), {})
		local rng = Util.newRng(4)
		while e.battle == nil do
			Expedition.next(p, e, rng)
		end
		T.eq(select(2, Expedition.act(p, e, "treat", "w1", rng)), "no_room")
		table.insert(p.plot.placed, { uid = 900, id = "nest", x = 0, z = 0, rot = 0 })
		local food = p.food
		local joined = nil
		for _ = 1, 30 do
			if e.battle == nil then
				break
			end
			local target = nil
			for _, f in e.battle.foes do
				if f.hp > 0 then
					target = f.key
				end
			end
			local _, data = Expedition.act(p, e, "treat", target, rng)
			if data.friend then
				joined = data.friend
			end
		end
		T.truthy(p.food < food, "treats eaten")
		T.truthy(joined ~= nil, "a driftling joined")
		if joined then
			T.eq(p.pals[#p.pals].sp, joined.sp)
			T.eq(p.seen[joined.sp], 2)
			T.eq(p.stats.befriended, #p.pals)
			T.eq(e.befriended[#e.befriended], joined.sp)
		end
	end)
	T.it("losing: the expedition ends, half the loot comes home", function()
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
		local got = Expedition.home(p, e)
		T.eq(got.shells, 50)
		T.eq(p.shells, shells + 50)
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
	T.it("the risk: the fight under way, else the next stop's likely foes; none when no fight is next", function()
		local p = fresh()
		p.cap.lvl = 5
		local _, e = Expedition.start(p, Expedition.chart(8, 44), {})
		local rng = Util.newRng(6)
		-- walk to the stop before a fight
		local guard = 0
		while guard < 30 do
			guard += 1
			local nxt = Expedition.nodesTo(e.isle, e.node + 1)[e.node + 1]
			if nxt == "wild" or nxt == "boss" then
				break
			end
			Expedition.next(p, e, rng)
		end
		local r = Expedition.risk(e)
		T.truthy(r ~= nil, "a fight next")
		e.party[1].hp = 1
		T.truthy((Expedition.risk(e) :: any).danger, "worn out: likely to lose")
		e.party[1].hp, e.party[1].atk = 99999, 9999
		T.truthy(not (Expedition.risk(e) :: any).danger, "strong: safe")
		Expedition.next(p, e, rng)
		T.truthy(e.battle ~= nil and Expedition.risk(e) ~= nil, "the fight under way")
	end)
	T.it("no fleeing a guardian, no treats for it", function()
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
		T.eq(select(2, Expedition.act(p, e, "flee", "", rng)), "blocked")
		T.eq(select(2, Expedition.act(p, e, "treat", "w1", rng)), "blocked")
	end)
end
