-- The island's rules (Logic/Island; GAME_DESIGN 3-6): what it makes (wood, and shells from the farms and shops; nothing
-- eats), charm and visitors, the driftlings at work (from their huts, faster the rarer: they do all the work, no
-- villagers), expanding (for wood).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Island = require("../../build/luautest/shared/Logic/Island")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island with nothing on it)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood = 1e6, 1e6
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
	T.it("a new island: its two stores, nothing built but its tree", function()
		local p = Schema.default(0, 1)
		T.eq(p.shells, Tuning.StartShells)
		T.eq(p.wood, Tuning.StartWood)
		T.eq((p :: any).food, nil, "no food")
		T.eq(#p.plot.placed, 1)
		T.eq(p.plot.placed[1].id, "tree")
		local r = Island.rates(p)
		T.eq(r.wood, 0)
		T.eq(r.shells, 0)
		T.eq((r :: any).food, nil)
		T.eq(Island.nests(p), 0)
	end)
	T.it("a building makes its share with no driftling there; each driftling of its knack makes its share, more the rarer", function()
		local p = fresh()
		local uid = put(p, "patch")
		-- (a farm sells what it grows: shells)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Tuning.IdleOutput, 1e-9)
		local hut = put(p, "nest")
		table.insert(p.pals, { id = 99, sp = "mossbun", home = hut, work = uid })
		-- (its share grows with its work share: the mossbun's passive is at farms)
		local share = Island.palWork(p, p.pals[1])
		T.truthy(share > 0, "a farm passive helps at a farm")
		local one = Tuning.PalWork * Tuning.RarityWork[1] * (1 + share)
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one, 1e-9, "one common: its share, no idle share")
		-- a second, rarer one adds its own share, bigger by its rarity
		table.insert(p.pals, { id = 98, sp = "bloomoth", home = hut, work = uid })
		local share2 = Island.palWork(p, p.pals[2])
		local two = one + Tuning.PalWork * Tuning.RarityWork[3] * (1 + share2)
		T.truthy(two - one > one, "a rare one makes more than a common")
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * two, 1e-9)
		-- with no hut: it doesn't work
		p.pals[2].home = 0
		p.pals[2].work = 0
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * one, 1e-9)
		table.remove(p.pals, 2)
		-- a mutation for work makes it a better worker still
		p.pals[1].muts = { "grower3" }
		T.truthy(Island.palWork(p, p.pals[1]) > share, "a farming mutation adds to it")
	end)
	T.it("wood and shops: a camp makes wood, a shop sells to visitors", function()
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
		T.near(r.wood, Buildings.byId.lumber.rate * Island.palBoost(p, w, 0), 1e-9, "the shop takes no wood")
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
	T.it("a turn: what it made, the shells counted as earned", function()
		local p = fresh()
		local hut = put(p, "nest")
		local x = worker(p, "farm", hut, put(p, "patch"))
		worker(p, "wood", hut, put(p, "lumber"))
		local shells, wood, earned = p.shells, p.wood, p.stats.earned
		local r = Island.rates(p)
		Island.step(p, Tuning.TurnSeconds)
		T.near(p.shells, shells + r.shells, 1e-9)
		T.near(p.wood, wood + r.wood, 1e-9)
		T.near(p.stats.earned, earned + r.shells, 1e-9)
		T.truthy(r.shells > 0 and r.wood > 0 and x.work ~= 0)
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
		T.eq(Island.freeJob(p, "fish"), patch2, "no pier: the emptiest farm")
		-- with its effects: where it works fastest when its knack has no room (Traits.workAt)
		local stall = put(p, "stall")
		T.eq(Island.freeJob(p, "fish", { shop = 0.3 }), stall, "a seller's knack for shops")
		T.eq(Island.freeJob(p, "fish", { wood = 0.2 }), lumber, "a woodworker's for wood")
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
	T.it("expanding: its price in wood, then the next, then no more", function()
		local p = fresh()
		T.truthy(Island.expand(p))
		T.eq(p.tier, 2)
		T.eq(p.wood, 1e6 - Tuning.TierCost[2], "wood")
		T.eq(p.shells, 1e6, "no shells")
		p.wood = 0
		T.eq(select(2, Island.expand(p)), "wood")
		p.wood = 1e9
		while p.tier < #Tuning.TierCost do
			T.truthy(Island.expand(p))
		end
		T.eq(p.tier, 20, "twenty tiers: a castaway's cay to Everdrift")
		T.eq(select(2, Island.expand(p)), "max")
	end)
	T.it("the expansions' prices: levels 2 to 10 a bit cheaper than they were, 11 to 20 rising smoothly from there", function()
		-- (the request of 2026-11-14: "allow expansion up to level 20, you can make the previous levels of expansion a
		-- bit cheaper too"; the prices before it)
		local OLD = { 0, 600, 9000, 60000, 160000, 380000, 800000, 1600000, 3000000, 5000000 }
		for t = 2, 10 do
			local k = Tuning.TierCost[t] / OLD[t]
			T.truthy(k >= 0.75 and k <= 0.85, string.format("level %d at %.0f%% of its old price", t, k * 100))
		end
		for t = 11, 20 do
			local k = Tuning.TierCost[t] / Tuning.TierCost[t - 1]
			T.truthy(k > 1.15 and k < 1.6, string.format("level %d at %.2f times the one before", t, k))
		end
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
		T.near(Island.rates(p).shells, Buildings.byId.patch.rate * Island.palBoost(p, x, Buildings.byId.den.comfort), 1e-9)
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
		local base = Island.rates(p).shells
		put(p, "windmill")
		T.near(Island.boosts(p).farm, 0.1, 1e-9)
		T.near(Island.rates(p).shells, base * 1.1, 1e-9)
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
		local wood = p.wood
		local ok, data = Island.expand(p)
		T.truthy(ok)
		T.eq(#p.plot.placed, before, "none lost")
		T.eq(data.cleared, 0)
		T.eq(p.wood, wood - Tuning.TierCost[2], "nothing refunded")
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
