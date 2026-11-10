-- Battles (Logic/Battle; GAME_DESIGN 7): fighters by level, the turn order, guarding, skills, treats and fleeing.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Battle = require("../../build/luautest/shared/Logic/Battle")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Util = require("../../build/luautest/shared/Logic/Util")

return function()
	T.it("fighters: the founder, villagers by their seed, driftlings by species, all growing with their level", function()
		local p = Schema.default(0, 1)
		local f = Battle.founder(p)
		T.eq(f.key, "f")
		T.eq(f.maxHp, Battle.FOUNDER.hp)
		p.cap.lvl = 11
		T.eq(Battle.founder(p).maxHp, Battle.grow(Battle.FOUNDER.hp, 11))
		T.deepEq(Battle.villagerBase(42), Battle.villagerBase(42), "the same seed, the same villager")
		local w = Battle.wild("pebblit", 3, 1, false)
		T.eq(w.key, "w1")
		T.eq(w.maxHp, Battle.grow(Creatures.byId.pebblit.hp, 3))
		local boss = Battle.wild("pebblit", 3, 1, true)
		T.truthy(boss.maxHp > w.maxHp and boss.atk > w.atk, "a guardian is stronger")
	end)
	T.it("a fight: the founder beats a lone Pebblit in a few rounds", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local b = Battle.new({ Battle.wild("pebblit", 1, 1, false) }, false)
		local rng = Util.newRng(7)
		local result = nil
		local rounds = 0
		while result == nil and rounds < 30 do
			local _, r = Battle.round(party, b, "fight", nil, rng)
			result = r
			rounds += 1
		end
		T.eq(result, "win")
		T.truthy(rounds <= 8, tostring(rounds) .. " rounds")
		T.truthy(party[1].hp > 0)
	end)
	T.it("the faster act first; skills every few actions", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		party[1].hp, party[1].maxHp = 1e6, 1e6
		local fast = Battle.wild("gullfin", 20, 1, false)
		fast.hp, fast.maxHp = 1e6, 1e6
		local b = Battle.new({ fast }, false)
		local ev = Battle.round(party, b, "fight", nil, Util.newRng(1))
		T.eq(ev[1].by, "w1", "the gullfin is quicker")
		local skills = 0
		for _ = 1, Tuning.SkillEvery * 2 do
			for _, e in Battle.round(party, b, "fight", nil, Util.newRng(2)) do
				if e.skill or e.t == "rally" or e.t == "shield" or e.t == "heal" then
					skills += 1
				end
			end
		end
		T.truthy(skills >= 2, tostring(skills) .. " skills")
	end)
	T.it("guarding takes less damage; nobody in the party attacks", function()
		local p = Schema.default(0, 1)
		local function hits(act: string): (number, number)
			local party = { Battle.founder(p) }
			party[1].hp, party[1].maxHp = 1e6, 1e6
			local foe = Battle.wild("clawdle", 15, 1, false)
			foe.hp, foe.maxHp = 1e6, 1e6
			foe.skill = "none"
			local b = Battle.new({ foe }, false)
			local taken, dealt = 0, 0
			local rng = Util.newRng(3)
			for _ = 1, 20 do
				for _, e in Battle.round(party, b, act, nil, rng) do
					if e.t == "hit" and e.to == "f" then
						taken += e.dmg
					elseif e.t == "hit" then
						dealt += e.dmg
					end
				end
			end
			return taken, dealt
		end
		local tf, df = hits("fight")
		local tg, dg = hits("guard")
		T.truthy(tg < tf * 0.7, string.format("%d vs %d", tg, tf))
		T.eq(dg, 0)
		T.truthy(df > 0)
	end)
	T.it("treats: likelier on a hurt wild one, never a guardian; a friend leaves the battle", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local foe = Battle.wild("pebblit", 1, 1, false)
		local full = Battle.treatChance(foe, party, false)
		foe.hp = 1
		local hurt = Battle.treatChance(foe, party, false)
		T.truthy(hurt > full, string.format("%.2f > %.2f", hurt, full))
		T.eq(Battle.treatChance(foe, party, true), 0)
		local b = Battle.new({ foe }, false)
		local ok = false
		for seed = 1, 40 do
			foe.hp = 1
			local ev, result = Battle.round(party, b, "treat", "w1", Util.newRng(seed))
			if ev[1].t == "treat" and ev[1].ok then
				ok = true
				T.eq(result, "win")
				T.truthy((foe :: any).friend)
				break
			end
		end
		T.truthy(ok, "befriended within 40 tries")
	end)
	T.it("fleeing: by speed, never from a guardian", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local slow = { Battle.wild("magmole", 1, 1, false) }
		local quick = { Battle.wild("scorchwing", 30, 1, false) }
		T.truthy(Battle.fleeChance(party, slow) > Battle.fleeChance(party, quick))
		local b = Battle.new({ Battle.wild("pebblit", 1, 1, true) }, true)
		local ev, result = Battle.round(party, b, "flee", nil, Util.newRng(1))
		T.eq(ev[1].ok, false)
		T.truthy(result ~= "fled")
	end)
	T.it("the party beaten: lose", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local b = Battle.new({ Battle.wild("tidewyrm", 40, 1, true) }, true)
		local result = nil
		for _ = 1, 30 do
			local _, r = Battle.round(party, b, "fight", nil, Util.newRng(9))
			if r then
				result = r
				break
			end
		end
		T.eq(result, "lose")
	end)
end
