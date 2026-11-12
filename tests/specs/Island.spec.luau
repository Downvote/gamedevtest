-- The island's rules (Logic/Island; GAME_DESIGN 3-6): what it makes and eats, charm and visitors, villagers moving
-- in, jobs and helpers (driftlings work from their huts, faster the rarer), expanding.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Island = require("../../build/luautest/shared/Logic/Island")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Util = require("../../build/luautest/shared/Logic/Util")

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

local function villager(p: any, work: number): any
	local v = { id = p.nextId, name = "V", look = p.founder, work = work, day = 1 }
	p.nextId += 1
	table.insert(p.folk, v)
	return v
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
		T.eq(Island.beds(p), 0)
	end)
	T.it("a building makes half with nobody there, all with a villager, more with driftlings of its knack", function()
		local p = fresh()
		local uid = put(p, "patch")
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * Tuning.IdleOutput, 1e-9)
		villager(p, uid)
		T.near(Island.rates(p).food, Buildings.byId.patch.rate - Tuning.EatFolk, 1e-9, "a villager eats")
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 99, sp = "mossbun", home = hut, work = uid })
		-- (the helper's boost grows with its work share: the mossbun's passive is at farms)
		local share = Island.palWork(p, p.pals[1])
		T.truthy(share > 0, "a farm passive helps at a farm")
		local boost = 1 + Tuning.PalBoost * Tuning.RarityWork[1] * (1 + share)
		-- (the mossbun eats less: its passive)
		local eat = Tuning.EatPal * (1 + (Island.fxOf(p.pals[1]).eat or 0))
		T.truthy(eat < Tuning.EatPal)
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * boost - Tuning.EatFolk - eat, 1e-9)
		-- a second, rarer helper adds its own boost, bigger by its rarity
		table.insert(p.pals, { id = 98, sp = "bloomoth", home = hut, work = uid })
		local share2 = Island.palWork(p, p.pals[2])
		local boost2 = boost + Tuning.PalBoost * Tuning.RarityWork[3] * (1 + share2)
		local eat2 = eat + Tuning.EatPal
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * boost2 - Tuning.EatFolk - eat2, 1e-9)
		-- in the pen: neither works nor eats
		p.pals[2].home = 0
		p.pals[2].work = 0
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * boost - Tuning.EatFolk - eat, 1e-9)
		table.remove(p.pals, 2)
		-- hungry: everything at half
		p.food = 0
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * boost * Tuning.Hungry - Tuning.EatFolk - eat, 1e-9)
		-- a mutation for work makes it a better helper still
		p.food = 100
		p.pals[1].muts = { "grower3" }
		T.truthy(Island.palWork(p, p.pals[1]) > share, "a farming mutation adds to it")
	end)
	T.it("wood and shops: a shop sells to visitors, eating food", function()
		local p = fresh()
		villager(p, put(p, "lumber"))
		T.near(Island.rates(p).wood, Buildings.byId.lumber.rate, 1e-9)
		local s = put(p, "stall")
		villager(p, s)
		local r = Island.rates(p)
		local k = math.min(2, Island.visitors(p) / Tuning.ShopVisitors)
		T.near(r.shells, Buildings.byId.stall.rate * k, 1e-9)
		T.near(r.food, -Buildings.byId.stall.eats * k - 2 * Tuning.EatFolk, 1e-9)
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
		villager(p, put(p, "patch"))
		local food = p.food
		Island.step(p, Tuning.TurnSeconds)
		T.near(p.food, food + Buildings.byId.patch.rate - Tuning.EatFolk, 1e-9)
		p.folk = {}
		for _ = 1, 50 do
			villager(p, 0)
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
	T.it("a turn: a visitor moves into a free bed and takes a free job", function()
		local p = fresh()
		local rng = Util.newRng(5)
		local news = Island.turn(p, rng)
		T.eq(news.movedIn, nil, "no bed")
		T.eq(p.day, 1, "a turn is not a day")
		put(p, "tent")
		local job = put(p, "patch")
		news = Island.turn(p, rng)
		T.truthy(news.movedIn ~= nil and #p.folk == 1, "moved in")
		T.eq(p.folk[1].work, job)
		T.eq(p.stats.movedIn, 1)
		news = Island.turn(p, rng)
		T.eq(#p.folk, 1, "the tent is full")
		-- they come while the charm keeps up with the village
		for _ = 1, 10 do
			put(p, "tent")
		end
		put(p, "totem")
		for _ = 1, 20 do
			Island.turn(p, rng)
		end
		local most = math.floor(Island.charm(p) / Tuning.MoveInCharm) + 1
		T.eq(#p.folk, most, "as many as the charm brings")
	end)
	T.it("the first home: a castaway moves in at once; not once anyone lives here", function()
		local p = fresh()
		local rng = Util.newRng(5)
		T.eq(Island.welcome(p, rng), nil, "no bed yet: nobody")
		put(p, "patch")
		put(p, "tent")
		local v = Island.welcome(p, rng)
		T.truthy(v ~= nil and #p.folk == 1, "the tent built: someone moves in now")
		T.truthy(v ~= nil and v.work ~= 0, "and takes the free job")
		T.eq(p.stats.movedIn, 1)
		put(p, "hut")
		T.eq(Island.welcome(p, rng), nil, "a second home: the rest come with the turns and the charm")
		T.eq(#p.folk, 1)
	end)
	T.it("jobs: one villager a building that makes something, swapping; driftlings from a hut, at their knack, two a building", function()
		local p = fresh()
		local a, b = villager(p, 0), villager(p, 0)
		local patch = put(p, "patch")
		local tent = put(p, "tent")
		T.truthy(Island.setWork(p, a.id, patch))
		T.truthy(Island.setWork(p, b.id, patch))
		T.eq(a.work, 0, "swapped out")
		T.eq(b.work, patch)
		T.eq(select(2, Island.setWork(p, a.id, tent)), "bad_payload", "nobody works at a tent")
		T.eq(select(2, Island.setWork(p, 999, patch)), "not_found")
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 70, sp = "mossbun", home = hut, work = 0 })
		table.insert(p.pals, { id = 71, sp = "frondle", home = hut, work = 0 })
		table.insert(p.pals, { id = 72, sp = "hopsprout", home = 0, work = 0 })
		local lumber = put(p, "lumber")
		T.eq(select(2, Island.setHelp(p, 70, lumber)), "bad_payload", "a farm driftling at the lumber camp")
		T.truthy(Island.setHelp(p, 70, patch))
		T.truthy(Island.setHelp(p, 71, patch))
		T.eq(p.pals[1].work, patch, "two at one building")
		T.eq(select(2, Island.setHelp(p, 72, patch)), "bad_payload", "the pen's don't work")
		p.pals[3].home = hut
		T.truthy(Island.setHelp(p, 72, patch))
		T.eq(p.pals[1].work, 0, "a third: the first there goes back to rest")
		T.eq(p.pals[2].work, patch)
		T.truthy(Island.dismiss(p, a.id))
		T.eq(#p.folk, 1)
		T.eq(Island.freeJob(p), lumber, "the lumber camp has nobody")
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
	T.it("homes: the best first, filled in the order the villagers came; comfort makes workers make more", function()
		local p = fresh()
		p.tier = 6
		local tent = put(p, "tent")
		local villa = put(p, "villa")
		local farm = put(p, "patch")
		local a = villager(p, farm)
		local homes = Island.homes(p)
		T.eq(homes["v" .. a.id].uid, villa, "the villa first")
		T.near(homes["v" .. a.id].comfort, Buildings.byId.villa.comfort, 1e-9)
		T.near(Island.rates(p).food, Buildings.byId.patch.rate * (1 + Buildings.byId.villa.comfort) - Tuning.EatFolk, 1e-9)
		-- a home's level adds comfort
		p.plot.placed[2].lvl = 3
		T.near(Island.homes(p)["v" .. a.id].comfort, Buildings.byId.villa.comfort + Tuning.ComfortLvl[3], 1e-9)
		-- the villa full: the tent next
		for _ = 1, Buildings.byId.villa.beds do
			villager(p, 0)
		end
		local last = p.folk[#p.folk]
		T.eq(Island.homes(p)["v" .. last.id].uid, tent)
		-- a driftling's hut: its comfort adds to its help
		local den = put(p, "den")
		local x = { id = 500, sp = "mossbun", home = den, work = farm }
		table.insert(p.pals, x)
		T.near(Island.homes(p).p500.comfort, Buildings.byId.den.comfort, 1e-9)
		T.near(Island.palBoost(p, x, Buildings.byId.den.comfort), Tuning.PalBoost * (1 + Island.palWork(p, x) + Buildings.byId.den.comfort), 1e-9)
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
		villager(p, farm)
		local base = Island.rates(p).food
		put(p, "windmill")
		T.near(Island.boosts(p).farm, 0.1, 1e-9)
		T.near(Island.rates(p).food, (base + Tuning.EatFolk) * 1.1 - Tuning.EatFolk, 1e-9)
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
		for _, id in { "patch", "tent", "flowers", "lumber", "hut", "nest", "bush", "torch" } do
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
		local worker = villager(p, p.plot.placed[1].uid)
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
		T.eq(worker.work, p.plot.placed[1].uid, "the worker keeps their job (the uid stays)")
		-- the third tier too
		T.truthy(Island.expand(p))
		rest = {}
		for _, q in p.plot.placed do
			T.truthy(Plot.fits(p.tier, rest, q.id, q.x, q.z, q.rot), q.id .. " fits the biggest island")
			table.insert(rest, q)
		end
	end)
end
