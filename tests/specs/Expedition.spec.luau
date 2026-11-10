-- Expeditions (Logic/Expedition; GAME_DESIGN 7): setting out, walking the islet's path, battles' ends, befriending,
-- the guardian opening the next islet, sailing home.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Expedition = require("../../build/luautest/shared/Logic/Expedition")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Islets = require("../../build/luautest/shared/Data/Islets")
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
	T.it("setting out: an open islet, members who exist, supplies for each", function()
		local p = fresh()
		T.eq(select(2, Expedition.start(p, 2, {})), "locked")
		T.eq(select(2, Expedition.start(p, 9, {})), "bad_payload")
		T.eq(select(2, Expedition.start(p, 1, { "v7" })), "not_found")
		table.insert(p.folk, { id = 7, name = "Ana", look = p.founder, work = 0, lvl = 2, xp = 0, seed = 3, day = 1 })
		table.insert(p.pals, { id = 8, sp = "pebblit", lvl = 1, xp = 0, work = 0 })
		T.eq(select(2, Expedition.start(p, 1, { "v7", "v7" })), "bad_payload")
		T.eq(select(2, Expedition.start(p, 1, { "v7", "p8", "v7", "p8" })), "full")
		p.food = 3
		T.eq(select(2, Expedition.start(p, 1, { "v7" })), "food")
		p.food = 100
		local ok, e = Expedition.start(p, 1, { "v7", "p8" })
		T.truthy(ok)
		T.eq(p.food, 100 - Tuning.Supplies * 3)
		T.eq(#e.party, 3)
		T.eq(e.party[1].key, "f")
		T.eq(e.party[2].name, "Ana")
		T.eq(e.node, 1)
		local away = Expedition.away(e)
		T.truthy(away.v7 and away.p8 and away.f)
	end)
	T.it("the path: loot, battles in the way, a rest, the guardian at the end", function()
		local p = fresh()
		p.cap.lvl = 12
		local _, e = Expedition.start(p, 1, {})
		local rng = Util.newRng(11)
		local kinds = {}
		while e.node < #e.nodes and not e.over do
			local ok, data = Expedition.next(p, e, rng)
			T.truthy(ok, tostring(data))
			table.insert(kinds, data.kind)
			if e.battle then
				T.eq(select(2, Expedition.next(p, e, rng)), "in_battle")
				T.truthy(p.seen[e.battle.foes[1].sp] ~= nil, "met")
				fightOut(p, e, rng)
			end
		end
		T.deepEq(kinds, { table.unpack(Islets.list[1].nodes, 2) })
		T.eq(e.over, "won", "the guardian beaten")
		T.eq(p.islets, 1, "the next islet opens")
		T.truthy(e.loot.food > 0 and e.loot.wood > 0 and e.loot.shells >= Islets.list[1].reward)
		T.truthy(p.cap.xp > 0 or p.cap.lvl > 12, "the captain learned")
		T.eq(select(2, Expedition.next(p, e, rng)), "no_exp")
		local shells = p.shells
		local got = Expedition.home(p, e)
		T.eq(p.shells, shells + got.shells)
		T.eq(got.shells, e.loot.shells)
	end)
	T.it("befriending: a treat costs food and needs a nest; the friend joins the island", function()
		local p = fresh()
		p.cap.lvl = 6
		local _, e = Expedition.start(p, 1, {})
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
			T.eq(p.pals[1].sp, joined.sp)
			T.eq(p.seen[joined.sp], 2)
			T.eq(p.stats.befriended, 1)
			T.eq(e.befriended[1], joined.sp)
		end
	end)
	T.it("losing: the expedition ends, half the loot comes home", function()
		local p = fresh()
		local _, e = Expedition.start(p, 1, {})
		e.loot.shells, e.loot.food = 100, 40
		e.party[1].hp, e.party[1].atk = 1, 1
		local rng = Util.newRng(2)
		while e.battle == nil do
			Expedition.next(p, e, rng)
		end
		local result = fightOut(p, e, rng)
		T.eq(result, "lose")
		T.eq(e.over, "lost")
		local shells = p.shells
		local got = Expedition.home(p, e)
		T.eq(got.shells, 50)
		T.eq(p.shells, shells + 50)
	end)
	T.it("no fleeing a guardian, no treats for it", function()
		local p = fresh()
		p.cap.lvl = 30
		local _, e = Expedition.start(p, 1, {})
		local rng = Util.newRng(5)
		while e.node < #e.nodes - 1 do
			Expedition.next(p, e, rng)
			fightOut(p, e, rng)
		end
		Expedition.next(p, e, rng)
		T.truthy(e.battle and e.battle.boss)
		T.eq(select(2, Expedition.act(p, e, "flee", "", rng)), "blocked")
		T.eq(select(2, Expedition.act(p, e, "treat", "w1", rng)), "blocked")
	end)
end
