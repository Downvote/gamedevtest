-- The island's rules (Logic/Island; GAME_DESIGN 3-6): what it makes (shells from the farms, the wood buildings and the
-- shops; nothing eats), charm and the shells it adds, the driftlings at work (from their huts, faster the rarer: they do
-- all the work, no villagers), expanding (for shells: one store since 2026-11-14).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Island = require("../../build/luautest/shared/Logic/Island")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island with nothing on it)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells = 1e6
	p.plot.placed = {}
	return p
end

-- what charm multiplies every shell by now (Island.charmBonus)
local function cb(p: any): number
	return 1 + Island.charmBonus(Island.charm(p))
end

local function put(p: any, id: string): number
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = 0, z = 0, rot = 0 })
	return uid
end

-- a common driftling of a knack living in hut `hut`, working at `work` (0: resting)
local KNACK = { farm = "mossbun", wood = "pebblit", shop = "conchy" }
local function worker(p: any, knack: string, hut: number, work: number): any
	local x = { id = p.nextId, sp = KNACK[knack], home = hut, work = work }
	p.nextId += 1
	table.insert(p.pals, x)
	return x
end

return function()
	T.it("a new island: one store, nothing built but its tree", function()
		local p = Schema.default(0, 1)
		T.eq(p.shells, Tuning.StartShells)
		T.eq((p :: any).wood, nil, "no wood")
		T.eq((p :: any).food, nil, "no food")
		T.eq(#p.plot.placed, 1)
		T.eq(p.plot.placed[1].id, "tree")
		local r = Island.rates(p)
		T.eq((r :: any).wood, nil)
		T.eq(r.shells, 0)
		T.eq((r :: any).food, nil)
		T.eq(Island.nests(p), 0)
	end)
	T.it("a building makes its share with no driftling there; each driftling of its knack makes its share, more the rarer", function()
		local p = fresh()
		local uid = put(p, "patch")
		-- (a farm sells what it grows: shells)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Tuning.IdleOutput * cb(p), 1e-9)
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 99, sp = "mossbun", home = hut, work = uid })
		-- (its share grows with its work share: the mossbun's passive is at farms)
		local share = Island.palWork(p, p.pals[1])
		T.truthy(share > 0, "a farm passive helps at a farm")
		local one = Tuning.PalWork * Tuning.RarityWork[1] * (1 + share)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one * cb(p), 1e-9, "one common: its share, no idle share")
		-- a second, rarer one adds its own share, bigger by its rarity
		table.insert(p.pals, { id = 98, sp = "bloomoth", home = hut, work = uid })
		local share2 = Island.palWork(p, p.pals[2])
		local two = one + Tuning.PalWork * Tuning.RarityWork[3] * (1 + share2)
		T.truthy(two - one > one, "a rare one makes more than a common")
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * two * cb(p), 1e-9)
		-- with no hut: it doesn't work
		p.pals[2].home = 0
		p.pals[2].work = 0
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one * cb(p), 1e-9)
		table.remove(p.pals, 2)
		-- a mutation for work makes it a better worker still
		p.pals[1].muts = { "grower3" }
		T.truthy(Island.palWork(p, p.pals[1]) > share, "a farming mutation adds to it")
	end)
	T.it("wood and shops: a camp sells its wood for shells, a shop its snacks, each at its plain rate", function()
		-- (the request of 2026-11-14: "the wood tab buildings will also now give shells ... remove the visitors mechanic")
		local p = fresh()
		local hut = put(p, "nest")
		local camp = put(p, "lumber")
		local w = worker(p, "wood", hut, camp)
		T.near(Island.rates(p).shells, Buildings.byId.lumber.rate * Island.palBoost(p, w, 0) * cb(p), 1e-9)
		local s = put(p, "stall")
		local v = worker(p, "shop", hut, s)
		local k = Buildings.byId.lumber.rate * Island.palBoost(p, w, 0) + Buildings.byId.stall.rate * Island.palBoost(p, v, 0)
		T.near(Island.rates(p).shells, k * cb(p), 1e-9, "no visitors to wait for")
		T.eq((Island :: any).visitors, nil, "no visitors")
	end)
	T.it("charm raises the shells: the first charm counts the most, never past CharmMax", function()
		-- (the request of 2026-11-14: "charm simply increases your shell gain")
		T.eq(Island.charmBonus(0), 0)
		T.eq(Island.charmBonus(-5), 0, "never below nothing")
		T.near(Island.charmBonus(Tuning.CharmHalf), Tuning.CharmMax / 2, 1e-9, "half the most at CharmHalf")
		T.truthy(Island.charmBonus(10) - Island.charmBonus(0) > Island.charmBonus(1010) - Island.charmBonus(1000), "the first charm counts the most")
		T.truthy(Island.charmBonus(1e9) <= Tuning.CharmMax, "never past CharmMax")
		local p = fresh()
		local farm = put(p, "patch")
		local base = Island.charm(p)
		local plain = Island.rates(p).shells / cb(p)
		T.truthy(farm > 0 and plain > 0)
		put(p, "fountain")
		T.eq(Island.charm(p), base + Buildings.byId.fountain.charm)
		T.near(Island.rates(p).shells, plain * (1 + Island.charmBonus(base + Buildings.byId.fountain.charm)), 1e-9, "more charm, more shells")
		for _ = 1, 30 do
			put(p, "statue")
		end
		T.truthy(Island.rates(p).shells > plain * (1 + Island.charmBonus(base + Buildings.byId.fountain.charm)), "decor pays")
	end)
	T.it("a turn: what it made, the shells counted as earned", function()
		local p = fresh()
		local hut = put(p, "nest")
		local x = worker(p, "farm", hut, put(p, "patch"))
		worker(p, "wood", hut, put(p, "lumber"))
		local shells, earned = p.shells, p.stats.earned
		local r = Island.rates(p)
		Island.step(p, Tuning.TurnSeconds)
		T.near(p.shells, shells + r.shells, 1e-9)
		T.near(p.stats.earned, earned + r.shells, 1e-9)
		T.truthy(r.shells > 0 and x.work ~= 0)
	end)
	T.it("a new calendar day counts the days; a day lasts hours, many turns", function()
		local p = fresh()
		Island.newDay(p)
		T.eq(p.day, 2)
		T.eq(p.stats.days, 1)
		T.truthy(Tuning.DaySeconds >= 3 * 3600, "a few hours at least")
		T.truthy(Tuning.DaySeconds >= Tuning.TurnSeconds * 100)
	end)
	T.it("work: driftlings from a hut, at any workplace, two a building; a free place is its knack's first, else anywhere", function()
		local p = fresh()
		local patch = put(p, "patch")
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 70, sp = "mossbun", home = hut, work = 0 })
		table.insert(p.pals, { id = 71, sp = "frondle", home = hut, work = 0 })
		table.insert(p.pals, { id = 72, sp = "hopsprout", home = 0, work = 0 })
		local lumber = put(p, "lumber")
		T.truthy(Island.setHelp(p, 70, lumber), "a farm driftling at the lumber camp: any driftling works anywhere")
		T.eq(p.pals[1].work, lumber)
		T.eq(select(2, Island.setHelp(p, 70, hut)), "bad_payload", "not at a hut: it makes nothing")
		T.eq(select(2, Island.setHelp(p, 999, patch)), "not_found")
		T.truthy(Island.setHelp(p, 70, patch))
		T.truthy(Island.setHelp(p, 71, patch))
		T.eq(p.pals[1].work, patch, "two at one building")
		T.eq(select(2, Island.setHelp(p, 72, patch)), "bad_payload", "one with no hut doesn't work")
		p.pals[3].home = hut
		T.truthy(Island.setHelp(p, 72, patch))
		T.eq(p.pals[1].work, 0, "a third: the first there goes back to rest")
		T.eq(p.pals[2].work, patch)
		T.eq(Island.freeJob(p, "farm"), lumber, "the only farm is full: the lumber camp has room")
		local patch2 = put(p, "patch")
		T.eq(Island.freeJob(p, "farm"), patch2, "its own knack's first: the empty farm")
		T.eq(Island.freeJob(p, "wood"), lumber)
		T.eq(Island.freeJob(p, "shop"), patch2, "no shop: the emptiest, farms first")
		-- with its effects: where it works fastest when its knack has no say (Traits.workAt)
		local stall = put(p, "stall")
		T.eq(Island.freeJob(p, "", { shop = 0.3 }), stall, "a seller's share for shops")
		T.eq(Island.freeJob(p, "", { wood = 0.2 }), lumber, "a woodworker's for wood")
		T.truthy(Island.setHelp(p, 72, 0))
		T.eq(p.pals[3].work, 0, "back to rest")
	end)
	T.it("work at another knack: a driftling's passive helps at its own knack's buildings only", function()
		local p = fresh()
		local hut = put(p, "nest")
		local lumber = put(p, "lumber")
		local patch = put(p, "patch")
		local x = { id = 80, sp = "frondle", home = hut, work = patch } -- farm +18%
		table.insert(p.pals, x)
		local atFarm = Island.palBoost(p, x)
		T.truthy(Island.setHelp(p, 80, lumber))
		local atWood = Island.palBoost(p, x)
		T.truthy(atWood > 0 and atFarm > atWood, "it still works at the camp, a little slower")
		T.near(atFarm / atWood, 1.18, 1e-9)
	end)
	T.it("expanding: its price in shells, then the next, then no more", function()
		-- (the request of 2026-11-14: "allowing you to buy decor and expansions with it")
		local p = fresh()
		T.truthy(Island.expand(p))
		T.eq(p.tier, 2)
		T.eq(p.shells, 1e6 - (Island.expandCost(1) :: any).shells, "shells")
		p.shells = 0
		T.eq(select(2, Island.expand(p)), "money")
		p.shells = 1e9
		while p.tier < #Tuning.TierCost do
			T.truthy(Island.expand(p))
		end
		T.eq(p.tier, 10, "ten tiers: a castaway's cay to Driftling Haven")
		T.eq(select(2, Island.expand(p)), "max")
	end)
	T.it("huts: a resident's comfort (its hut's and its level's) makes it work more; none with no hut", function()
		local p = fresh()
		p.tier = 6
		local farm = put(p, "patch")
		local den = put(p, "den")
		local x = { id = 500, sp = "mossbun", home = den, work = farm }
		table.insert(p.pals, x)
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort, 1e-9)
		T.near(Island.palBoost(p, x, Buildings.byId.den.comfort), Tuning.PalWork * (1 + Island.palWork(p, x) + Buildings.byId.den.comfort), 1e-9)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Island.palBoost(p, x, Buildings.byId.den.comfort) * cb(p), 1e-9)
		-- a hut's level (from an older save) adds comfort
		p.plot.placed[2].lvl = 3
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort + Tuning.ComfortLvl[3], 1e-9)
		x.home = 0
		T.eq(Island.homes(p).p500, nil, "none with no hut")
	end)
	T.it("charm: each driftling in a hut, with its charm effects; none for one with no hut", function()
		local p = fresh()
		local base = Island.charm(p)
		local hut = put(p, "nest")
		local c0 = Island.charm(p)
		table.insert(p.pals, { id = 80, sp = "pebblit", home = hut, work = 0, muts = { "armor3" } }) -- Rolling Stone +1, Adorable +3
		T.eq(Island.charm(p), c0 + 1 + 1 + 3)
		p.pals[1].home = 0
		T.eq(Island.charm(p), c0)
		T.truthy(c0 >= base)
	end)
	T.it("boosts: every building of a knack makes more; each kind counts once; never past BoostMax", function()
		local p = fresh()
		p.tier = 6
		local farm = put(p, "patch")
		local base = Island.rates(p).shells / cb(p)
		put(p, "windmill")
		T.near(Island.boosts(p).farm, 0.1, 1e-9)
		T.near(Island.rates(p).shells, base * 1.1 * cb(p), 1e-9)
		T.truthy(farm > 0)
		put(p, "windmill")
		T.near(Island.boosts(p).farm, 0.1, 1e-9, "a second windmill adds nothing")
		put(p, "watertower")
		put(p, "townhall")
		put(p, "beacon")
		T.near(Island.boostAt(Island.boosts(p), "farm"), math.min(Tuning.BoostMax, 0.1 + 0.06 + 0.1 + 0.15), 1e-9)
		T.near(Island.boostAt(Island.boosts(p), "wood"), 0.31, 1e-9, "the all-boosts at every knack")
	end)
	T.it("expanding: every building stays on the bigger island (moved over where the coast changed), nothing lost", function()
		local Plot = require("../../build/luautest/shared/Logic/Plot")
		local Street = require("../../build/luautest/shared/Data/Street")
		local p = fresh()
		-- the small island filled from its edges in: pieces right up to its coast
		local r = Street.plot(1)
		for _, id in { "patch", "stall", "flowers", "lumber", "pier", "nest", "bush", "torch" } do
			local done = false
			for z = r.z1, r.z0, -1 do
				for x = r.x1, r.x0, -1 do
					if not done and Plot.fits(1, p.plot.placed, id, x, z, 0) then
						T.truthy(Plot.place(p, id, x, z, 0))
						done = true
					end
				end
			end
		end
		local hut = 0
		for _, q in p.plot.placed do
			if q.id == "nest" then
				hut = q.uid
			end
		end
		local x = worker(p, "farm", hut, p.plot.placed[1].uid)
		local before = #p.plot.placed
		local shells = p.shells
		local ok, data = Island.expand(p)
		T.truthy(ok)
		T.eq(#p.plot.placed, before, "none lost")
		T.eq(data.cleared, 0)
		T.eq(p.shells, shells - (Island.expandCost(1) :: any).shells, "nothing refunded")
		local rest = {}
		for _, q in p.plot.placed do
			T.truthy(Plot.fits(p.tier, rest, q.id, q.x, q.z, q.rot), q.id .. " fits the bigger island")
			table.insert(rest, q)
		end
		T.eq(x.work, p.plot.placed[1].uid, "the worker keeps its place (the uid stays)")
		-- the third tier too
		T.truthy(Island.expand(p))
		rest = {}
		for _, q in p.plot.placed do
			T.truthy(Plot.fits(p.tier, rest, q.id, q.x, q.z, q.rot), q.id .. " fits the biggest island")
			table.insert(rest, q)
		end
	end)
end
