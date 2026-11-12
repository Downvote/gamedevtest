-- The island's rules (Logic/Island; GAME_DESIGN 3-6): what it makes and eats, charm and visitors, the driftlings at
-- work (from their huts, faster the rarer: they do all the work, no villagers), expanding.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Island = require("../../build/luautest/shared/Logic/Island")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island with nothing on it, the tree too: the rules of building and living, apart from it: Tree.spec)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood, p.food = 1e6, 1e6, 100
	p.plot.placed = {}
	return p
end

local function put(p: any, id: string): number
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = 0, z = 0, rot = 0 })
	return uid
end

-- a common driftling of a knack living in hut `hut`, working at `work` (0: resting)
local KNACK = { farm = "mossbun", wood = "pebblit", fish = "clawdle", shop = "conchy" }
local function worker(p: any, knack: string, hut: number, work: number): any
	local x = { id = p.nextId, sp = KNACK[knack], home = hut, work = work }
	p.nextId += 1
	table.insert(p.pals, x)
	return x
end

return function()
	T.it("a new island: its stores, nothing built but its Tree of Life, nobody to feed", function()
		local p = Schema.default(0, 1)
		T.eq(p.shells, Tuning.StartShells)
		T.eq(p.food, Tuning.StartFood)
		T.eq(p.wood, Tuning.StartWood)
		T.eq(#p.plot.placed, 1, "the tree")
		T.eq(Buildings.byId[p.plot.placed[1].id].kind, "tree")
		local r = Island.rates(p)
		T.eq(r.food, 0)
		T.eq(r.shells, 0)
		T.eq(Island.nests(p), 0)
	end)
	T.it("a building makes half with no driftling there; each driftling of its knack makes its share, more the rarer", function()
		local p = fresh()
		local uid = put(p, "patch")
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * Tuning.IdleOutput, 1e-9)
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 99, sp = "mossbun", home = hut, work = uid })
		-- (its share grows with its work share: the mossbun's passive is at farms)
		local share = Island.palWork(p, p.pals[1])
		T.truthy(share > 0, "a farm passive helps at a farm")
		local one = Tuning.PalWork * Tuning.RarityWork[1] * (1 + share)
		-- (the mossbun eats less: its passive)
		local eat = Tuning.EatPal * (1 + (Island.fxOf(p.pals[1]).eat or 0))
		T.truthy(eat < Tuning.EatPal)
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * one - eat, 1e-9, "one common: its share, no idle half")
		-- a second, rarer one adds its own share, bigger by its rarity
		table.insert(p.pals, { id = 98, sp = "bloomoth", home = hut, work = uid })
		local share2 = Island.palWork(p, p.pals[2])
		local two = one + Tuning.PalWork * Tuning.RarityWork[3] * (1 + share2)
		T.truthy(two - one > one, "a rare one makes more than a common")
		local eat2 = eat + Tuning.EatPal
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * two - eat2, 1e-9)
		-- in the pen: neither works nor eats
		p.pals[2].home = 0
		p.pals[2].work = 0
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * one - eat, 1e-9)
		table.remove(p.pals, 2)
		-- hungry: everything at half
		p.food = 0
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * one * Tuning.Hungry - eat, 1e-9)
		-- a mutation for work makes it a better worker still
		p.food = 100
		p.pals[1].muts = { "grower3" }
		T.truthy(Island.palWork(p, p.pals[1]) > share, "a farming mutation adds to it")
	end)
	T.it("wood and shops: a shop sells to visitors, eating food", function()
		local p = fresh()
		local hut = put(p, "nest")
		local camp = put(p, "lumber")
		local w = worker(p, "wood", hut, camp)
		T.near(Island.rates(p).wood, Buildings.byId.lumber.rate * Island.palBoost(p, w, 0), 1e-9)
		local s = put(p, "stall")
		local v = worker(p, "shop", hut, s)
		local r = Island.rates(p)
		local k = math.min(2, Island.visitors(p) / Tuning.ShopVisitors) * Island.palBoost(p, v, 0)
		T.near(r.shells, Buildings.byId.stall.rate * k, 1e-9)
		local eat = 0
		for _, x in p.pals do
			eat += Tuning.EatPal * math.max(0.1, 1 + (Island.fxOf(x).eat or 0))
		end
		T.near(r.food, -Buildings.byId.stall.eats * k - eat, 1e-9)
		p.food = 0
		T.eq(Island.rates(p).shells, 0, "nothing to sell")
	end)
	T.it("charm and visitors", function()
		local p = fresh()
		local base = Island.charm(p)
		put(p, "fountain")
		T.eq(Island.charm(p), base + Buildings.byId.fountain.charm)
		T.near(Island.visitors(p), math.min(Tuning.VisitorsMax, 1 + Island.charm(p) / Tuning.VisitorCharm), 1e-9)
		for _ = 1, 30 do
			put(p, "statue")
		end
		T.eq(Island.visitors(p), Tuning.VisitorsMax)
	end)
	T.it("a turn: what it made, the food never below none", function()
		local p = fresh()
		local hut = put(p, "nest")
		local x = worker(p, "farm", hut, put(p, "patch"))
		local food = p.food
		local r = Island.rates(p)
		Island.step(p, Tuning.TurnSeconds)
		T.near(p.food, food + r.food, 1e-9)
		T.truthy(r.food > 0 and x.work ~= 0)
		x.work = 0
		for _ = 1, 60 do
			worker(p, "farm", hut, 0)
		end
		Island.step(p, Tuning.TurnSeconds * 10)
		T.eq(p.food, 0)
	end)
	T.it("a new calendar day counts the days; a day lasts hours, many turns", function()
		local p = fresh()
		Island.newDay(p)
		T.eq(p.day, 2)
		T.eq(p.stats.days, 1)
		T.truthy(Tuning.DaySeconds >= 3 * 3600, "a few hours at least")
		T.truthy(Tuning.DaySeconds >= Tuning.TurnSeconds * 100)
	end)
	T.it("work: driftlings from a hut, at their knack, two a building; a free place is the emptiest of its knack", function()
		local p = fresh()
		local patch = put(p, "patch")
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 70, sp = "mossbun", home = hut, work = 0 })
		table.insert(p.pals, { id = 71, sp = "frondle", home = hut, work = 0 })
		table.insert(p.pals, { id = 72, sp = "hopsprout", home = 0, work = 0 })
		local lumber = put(p, "lumber")
		T.eq(select(2, Island.setHelp(p, 70, lumber)), "bad_payload", "a farm driftling at the lumber camp")
		T.eq(select(2, Island.setHelp(p, 999, patch)), "not_found")
		T.truthy(Island.setHelp(p, 70, patch))
		T.truthy(Island.setHelp(p, 71, patch))
		T.eq(p.pals[1].work, patch, "two at one building")
		T.eq(select(2, Island.setHelp(p, 72, patch)), "bad_payload", "the pen's don't work")
		p.pals[3].home = hut
		T.truthy(Island.setHelp(p, 72, patch))
		T.eq(p.pals[1].work, 0, "a third: the first there goes back to rest")
		T.eq(p.pals[2].work, patch)
		T.eq(Island.freeJob(p, "farm"), 0, "the only farm is full")
		local patch2 = put(p, "patch")
		T.eq(Island.freeJob(p, "farm"), patch2, "the empty farm")
		T.eq(Island.freeJob(p, "wood"), lumber)
		T.eq(Island.freeJob(p, "fish"), 0, "no pier")
		T.truthy(Island.setHelp(p, 72, 0))
		T.eq(p.pals[3].work, 0, "back to rest")
	end)
	T.it("expanding: its price, then the next, then no more", function()
		local p = fresh()
		T.truthy(Island.expand(p))
		T.eq(p.tier, 2)
		T.eq(p.shells, 1e6 - Tuning.TierCost[2].shells)
		p.wood = 0
		T.eq(select(2, Island.expand(p)), "wood")
		p.wood = 1e9
		p.shells = 1e9
		while p.tier < #Tuning.TierCost do
			T.truthy(Island.expand(p))
		end
		T.eq(p.tier, 6, "six tiers: a castaway's cay to a capital")
		T.eq(select(2, Island.expand(p)), "max")
	end)
	T.it("huts: a resident's comfort (its hut's and its level's) makes it work more; none in the pen", function()
		local p = fresh()
		p.tier = 6
		local farm = put(p, "patch")
		local den = put(p, "den")
		local x = { id = 500, sp = "mossbun", home = den, work = farm }
		table.insert(p.pals, x)
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort, 1e-9)
		T.near(Island.palBoost(p, x, Buildings.byId.den.comfort), Tuning.PalWork * (1 + Island.palWork(p, x) + Buildings.byId.den.comfort), 1e-9)
		local eat = Tuning.EatPal * (1 + (Island.fxOf(x).eat or 0))
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * Island.palBoost(p, x, Buildings.byId.den.comfort) - eat, 1e-9)
		-- a hut's level (from an older save) adds comfort
		p.plot.placed[2].lvl = 3
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort + Tuning.ComfortLvl[3], 1e-9)
		x.home = 0
		T.eq(Island.homes(p).p500, nil, "none in the pen")
	end)
	T.it("charm: each driftling in a hut, with its charm effects; none for the pen's", function()
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
		local base = Island.rates(p).food
		put(p, "windmill")
		T.near(Island.boosts(p).farm, 0.1, 1e-9)
		T.near(Island.rates(p).food, base * 1.1, 1e-9)
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
		T.eq(p.shells, shells - Tuning.TierCost[2].shells, "nothing refunded")
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
