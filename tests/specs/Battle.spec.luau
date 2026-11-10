-- Battles (Logic/Battle; GAME_DESIGN 7): fighters by level, the timers (the quicker act more often, one action at a
-- time, paused while aiming), skills every few actions, snacks, fleeing, the skill points and the learnt skills.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Battle = require("../../build/luautest/shared/Logic/Battle")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Skills = require("../../build/luautest/shared/Data/Skills")
local Util = require("../../build/luautest/shared/Logic/Util")

-- Run a battle until it ends (or `secs` pass); the events and the result.
local function run(party: { any }, b: any, secs: number, seed: number?): ({ any }, string?)
	b.paused = false
	local rng = Util.newRng(seed or 1)
	local all = {}
	local t = 0
	while t < secs do
		local ev, r = Battle.step(party, b, 0.1, rng)
		for _, e in ev do
			table.insert(all, e)
		end
		if r then
			return all, r
		end
		t += 0.1
	end
	return all, nil
end

local function tough(f: any): any
	f.hp, f.maxHp = 1e6, 1e6
	return f
end

return function()
	T.it("fighters: the founder, villagers by their seed, driftlings by species, all growing with their level", function()
		local p = Schema.default(0, 1)
		local f = Battle.founder(p)
		T.eq(f.key, "f")
		T.eq(f.maxHp, Battle.FOUNDER.hp)
		T.eq(f.gauge, 0)
		p.cap.lvl = 11
		T.eq(Battle.founder(p).maxHp, Battle.grow(Battle.FOUNDER.hp, 11))
		T.deepEq(Battle.villagerBase(42), Battle.villagerBase(42), "the same seed, the same villager")
		local w = Battle.wild("pebblit", 3, 1, false)
		T.eq(w.key, "w1")
		T.eq(w.maxHp, Battle.grow(Creatures.byId.pebblit.hp, 3))
		local boss = Battle.wild("pebblit", 3, 1, true)
		T.truthy(boss.maxHp > w.maxHp and boss.atk > w.atk, "a guardian is stronger")
	end)
	T.it("a timer's pace: the quicker fill sooner, within the bounds", function()
		local slow = Battle.wild("magmole", 1, 1, false)
		local quick = Battle.wild("scorchwing", 1, 1, false)
		T.truthy(Battle.fillTime(quick) < Battle.fillTime(slow), string.format("%.2f < %.2f", Battle.fillTime(quick), Battle.fillTime(slow)))
		local f = Battle.wild("pebblit", 1, 1, false)
		f.spd = Tuning.AtbRef
		T.near(Battle.fillTime(f), Tuning.AtbTime, 1e-6)
		f.spd = 1e6
		T.eq(Battle.fillTime(f), Tuning.AtbMin)
		f.spd = 0
		T.near(Battle.fillTime(f), math.min(Tuning.AtbMax, Tuning.AtbTime * 2), 1e-6, "the slowest: twice the time, within the most")
	end)
	T.it("a new battle waits (paused) till it is let run; paused, nothing moves", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local b = Battle.new({ Battle.wild("pebblit", 1, 1, false) }, false, party, Util.newRng(1))
		T.truthy(b.paused)
		T.eq(b.sp, 0)
		local g0 = party[1].gauge
		local ev = Battle.step(party, b, 5, Util.newRng(2))
		T.eq(#ev, 0)
		T.eq(party[1].gauge, g0)
		T.eq(b.sp, 0, "no skill points while paused")
	end)
	T.it("a fight: the founder beats a lone Pebblit in a few seconds; each action starts the timer again", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local b = Battle.new({ Battle.wild("pebblit", 1, 1, false) }, false, party, Util.newRng(1))
		local ev, result = run(party, b, 60, 7)
		T.eq(result, "win")
		T.truthy(b.clock < 40, string.format("%.1f s", b.clock))
		T.truthy(party[1].hp > 0)
		T.truthy(#ev >= 2)
	end)
	T.it("the quicker act more often; one action at a time, the others wait while it plays", function()
		local p = Schema.default(0, 1)
		local party = { tough(Battle.founder(p)) }
		party[1].spd = 4
		local fast = tough(Battle.wild("gullfin", 1, 1, false))
		fast.spd = 30
		local b = Battle.new({ fast }, false, party)
		local ev = run(party, b, 30)
		local mine, theirs = 0, 0
		for _, e in ev do
			if e.t == "hit" or e.t == "rally" then
				if e.by == "f" then
					mine += 1
				elseif e.by == "w1" then
					theirs += 1
				end
			end
		end
		T.truthy(theirs > mine * 1.5, string.format("%d vs %d", theirs, mine))
		-- an action holds every timer: right after one, nobody fills
		b.paused = false
		b.lock = 0
		party[1].gauge, fast.gauge = 0.999, 0.999
		local first = Battle.step(party, b, 0.05, Util.newRng(3))
		T.eq(#first > 0, true, "one acts")
		T.truthy(b.lock > 0, "and holds the rest")
		local g = fast.gauge
		local again = Battle.step(party, b, 0.1, Util.newRng(4))
		T.eq(#again, 0, "nobody acts while it plays")
		T.eq(fast.gauge, g)
	end)
	T.it("skills every few actions", function()
		local p = Schema.default(0, 1)
		local party = { tough(Battle.founder(p)) }
		local b = Battle.new({ tough(Battle.wild("clawdle", 1, 1, false)) }, false, party)
		local ev = run(party, b, 60)
		local skills = 0
		for _, e in ev do
			if e.skill or e.t == "rally" or e.t == "shield" or e.t == "heal" then
				skills += 1
			end
		end
		T.truthy(skills >= 2, tostring(skills) .. " skills")
	end)
	T.it("snacks: likelier on a hurt wild one, never a guardian; a friend leaves the battle; the leader's timer starts again", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local foe = Battle.wild("pebblit", 1, 1, false)
		local full = Battle.treatChance(foe, party, false)
		foe.hp = 1
		local hurt = Battle.treatChance(foe, party, false)
		T.truthy(hurt > full, string.format("%.2f > %.2f", hurt, full))
		T.eq(Battle.treatChance(foe, party, true), 0)
		local b = Battle.new({ foe }, false, party)
		T.eq(select(2, Battle.snack(party, b, "w9", Util.newRng(1))), "not_found")
		local ok = false
		for seed = 1, 40 do
			foe.hp = 1
			party[1].gauge = 0.7
			local done, ev, result = Battle.snack(party, b, "w1", Util.newRng(seed))
			T.truthy(done)
			T.eq(party[1].gauge, 0, "the leader's timer starts again")
			T.truthy(not b.paused, "the battle runs again")
			if ev[1].t == "treat" and ev[1].ok then
				ok = true
				T.eq(result, "win")
				T.truthy((foe :: any).friend)
				break
			end
		end
		T.truthy(ok, "befriended within 40 tries")
		local gb = Battle.new({ Battle.wild("pebblit", 1, 1, true) }, true, party)
		T.eq(select(2, Battle.snack(party, gb, "w1", Util.newRng(1))), "blocked")
	end)
	T.it("fleeing: by speed, never from a guardian; a miss starts the leader's timer again", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local slow = { Battle.wild("magmole", 1, 1, false) }
		local quick = { Battle.wild("scorchwing", 30, 1, false) }
		T.truthy(Battle.fleeChance(party, slow) > Battle.fleeChance(party, quick))
		local gb = Battle.new({ Battle.wild("pebblit", 1, 1, true) }, true, party)
		T.eq(select(2, Battle.flee(party, gb, Util.newRng(1))), "blocked")
		local fled, missed = false, false
		local rng = Util.newRng(77)
		for _ = 1, 60 do
			local b = Battle.new({ Battle.wild("magmole", 1, 1, false) }, false, party)
			party[1].gauge = 0.5
			local _, ev, result = Battle.flee(party, b, rng)
			if ev[1].ok then
				fled = true
				T.eq(result, "fled")
			else
				missed = true
				T.eq(party[1].gauge, 0)
			end
		end
		T.truthy(fled and missed, "both happen")
	end)
	T.it("the party beaten: lose", function()
		local p = Schema.default(0, 1)
		local party = { Battle.founder(p) }
		local b = Battle.new({ Battle.wild("tidewyrm", 40, 1, true) }, true, party)
		local _, result = run(party, b, 120, 9)
		T.eq(result, "lose")
	end)
	T.it("skill points charge while the battle runs, up to the most", function()
		local p = Schema.default(0, 1)
		local party = { tough(Battle.founder(p)) }
		local b = Battle.new({ tough(Battle.wild("pebblit", 1, 1, false)) }, false, party)
		run(party, b, 2)
		T.near(b.sp, 2 * Tuning.SpRate, 0.11)
		run(party, b, 120)
		T.eq(b.sp, Tuning.SpMax)
	end)
	T.it("learnt skills: by level, the leader's and each battle skill's family", function()
		T.eq(Skills.lineOf("founder", "rally"), "lead")
		T.eq(Skills.lineOf("villager", "heal"), "heal")
		T.eq(Skills.lineOf("pal", "zap"), "zap")
		T.eq(#Skills.known("lead", 1), 1)
		T.truthy(#Skills.known("lead", 20) > #Skills.known("lead", 1))
		T.truthy(Skills.knows("heal", 8, "revive"))
		T.truthy(not Skills.knows("heal", 7, "revive"))
		local got = Skills.learnt("heal", 3, 8)
		T.eq(#got, 2, "rain at 4, revive at 8")
		-- every family's skills cost more the stronger they are (the later learnt)
		for line, list in Skills.LINES do
			local last = 0
			for _, l in list do
				local d = Skills.byId[l.id]
				T.truthy(d ~= nil, l.id)
				T.truthy(d.cost >= last, line .. ": " .. l.id)
				last = d.cost
			end
		end
	end)
	T.it("using a skill: paid in points, the user's timer starts again; a mend, a team heal, a blow on every foe", function()
		local p = Schema.default(0, 1)
		p.cap.lvl = 10
		local lead = Battle.founder(p)
		local healer = Battle.villager({ id = 1, name = "Mia", look = p.founder, work = 0, lvl = 8, xp = 0, seed = 1, day = 1 } :: any)
		healer.skill = "heal"
		local zapper = Battle.pal({ id = 2, sp = "twiggle", lvl = 9, xp = 0, work = 0 } :: any)
		local party = { lead, healer, zapper }
		local foes = { tough(Battle.wild("pebblit", 1, 1, false)), tough(Battle.wild("pebblit", 1, 2, false)) }
		local b = Battle.new(foes, false, party)
		local rng = Util.newRng(5)
		b.sp = 2
		T.eq(select(2, Battle.useSkill(party, b, "f", "cry", nil, rng)), "sp", "not enough points")
		b.sp = 10
		T.eq(select(2, Battle.useSkill(party, b, "f", "mend", nil, rng)), "locked", "the leader doesn't know Mend")
		T.eq(select(2, Battle.useSkill(party, b, "v1", "mend", "w1", rng)), "not_found", "Mend aims at a member")
		-- a mend on the most hurt
		lead.hp = 5
		healer.gauge = 0.8
		local ok, ev = Battle.useSkill(party, b, "v1", "mend", "f", rng)
		T.truthy(ok)
		T.eq(ev[1].t, "skill")
		T.truthy(lead.hp > 5, "mended")
		T.eq(healer.gauge, 0, "the user's timer starts again")
		T.near(b.sp, 10 - Skills.byId.mend.cost, 1e-6)
		-- the team's heal
		b.sp = 10
		lead.hp, zapper.hp = 5, 5
		ok = Battle.useSkill(party, b, "v1", "rain", nil, rng)
		T.truthy(ok and lead.hp > 5 and zapper.hp > 5)
		-- a wave on every wild one
		b.sp = 10
		local h1, h2 = foes[1].hp, foes[2].hp
		ok = Battle.useSkill(party, b, "p2", "tide", nil, rng)
		T.truthy(ok and foes[1].hp < h1 and foes[2].hp < h2, "both hit")
	end)
	T.it("revive, rally, a rush of timers, dizzy foes", function()
		local p = Schema.default(0, 1)
		p.cap.lvl = 10
		local lead = Battle.founder(p)
		local healer = Battle.villager({ id = 1, name = "Mia", look = p.founder, work = 0, lvl = 8, xp = 0, seed = 1, day = 1 } :: any)
		healer.skill = "heal"
		local shell = Battle.pal({ id = 2, sp = "pebblit", lvl = 9, xp = 0, work = 0 } :: any)
		local party = { lead, healer, shell }
		local foe = tough(Battle.wild("pebblit", 1, 1, false))
		local b = Battle.new({ foe }, false, party)
		local rng = Util.newRng(6)
		b.sp = 10
		T.eq(select(2, Battle.useSkill(party, b, "v1", "revive", "p2", rng)), "not_found", "nobody down to revive")
		shell.hp = 0
		local ok = Battle.useSkill(party, b, "v1", "revive", "p2", rng)
		T.truthy(ok and shell.hp > 0, "back up")
		b.sp = 10
		local atk = healer.atk
		Battle.useSkill(party, b, "f", "cry", nil, rng)
		T.truthy(healer.atk > atk, "the team hits harder")
		b.sp = 10
		healer.gauge, shell.gauge = 0, 0
		Battle.useSkill(party, b, "f", "charge", nil, rng)
		T.eq(healer.gauge, 1)
		T.eq(shell.gauge, 1)
		b.sp = 10
		foe.gauge = 0.9
		Battle.useSkill(party, b, "p2", "dizzy", nil, rng)
		T.eq(foe.gauge, 0)
	end)
	T.it("an action holds the battle as long as its events play", function()
		T.truthy(Battle.playTime({ { t = "hit", by = "f", to = "w1", dmg = 1 } }) > 0.5)
		local one = Battle.playTime({ { t = "hit", by = "f", to = "w1", dmg = 1, skill = "tide" } })
		local three = Battle.playTime({ { t = "hit", skill = "tide" }, { t = "hit", skill = "tide" }, { t = "hit", skill = "tide" } })
		T.truthy(three > one * 2, "three blows hold longer")
		T.eq(Battle.moveOf("mbonk"), "bash")
		T.eq(Battle.moveOf(nil), "attack")
		T.eq(Battle.moveOf("quick"), "quick")
	end)
end
