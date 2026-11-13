-- The tide and the huts (Logic/Tide; GAME_DESIGN 6): a driftling comes in on the tide every second and floats past the
-- island in TideLife seconds, then it's gone, like a conveyor belt; rarer ones come less often, more on a bigger island;
-- taking one in costs shells and a hut's room (every hut full: a swap, the one swapped out sold); a driftling in a hut
-- takes a job of its knack; one with no hut waits for room; the player moves them between huts and sells them.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Tide = require("../../build/luautest/shared/Logic/Tide")
local Island = require("../../build/luautest/shared/Logic/Island")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Util = require("../../build/luautest/shared/Logic/Util")

local function fresh(): any
	local p = Schema.default(0, 7)
	p.shells, p.wood = 1e7, 1e7
	return p
end

-- a piece at the first free spot (Plot.spot from the island's middle)
local function build(p: any, id: string): number
	local x, z, rot = Plot.spot(p.tier, p.plot.placed, id, 8, 4, 0)
	assert(x and z and rot, "room for " .. id)
	local ok, data = Plot.place(p, id, x, z, rot)
	assert(ok, tostring(data))
	return data.uid
end

local function pal(p: any, sp: string, muts: { string }?): any
	return Tide.add(p, sp, muts or {})
end

-- one of a kind on the tide (a drift of a known kind, for the take tests)
local function drift(s: any, p: any, sp: string, muts: { string }?): any
	local d = { id = s.next, sp = sp, muts = muts or {}, cost = Tide.cost(p, sp, muts), at = s.clock, life = Tide.life(p) }
	s.next += 1
	table.insert(s.list, d)
	return d
end

return function()
	T.it("a new island has no tree and two stores: wood to build, shells for driftlings", function()
		local p = Schema.default(0, 1)
		T.eq(#p.plot.placed, 0, "nothing built yet")
		T.eq(p.wood, Tuning.StartWood)
		T.eq(p.shells, Tuning.StartShells)
		T.eq((p :: any).food, nil, "no food")
		T.eq((p :: any).tree, nil, "no tree")
		T.eq(Buildings.byId.tree, nil)
		-- the tips' buildings fit the starting wood (a camp, a patch, a hut)
		local need = 0
		for _, id in { "lumber", "patch", "nest" } do
			need += Buildings.byId[id].wood
			T.eq(Buildings.byId[id].shells, 0, id .. " costs no shells")
		end
		T.truthy(need <= Tuning.StartWood, "the tips' buildings: " .. need)
	end)

	T.it("one comes in every TideSecs and floats past in TideLife, then it's gone; each seen in the Index", function()
		local p = fresh()
		local s = Tide.new(100)
		local rng = Util.newRng(3)
		local came, gone = Tide.step(p, s, Tuning.TideSecs - 0.01, rng)
		T.eq(#came, 0, "not yet")
		came, gone = Tide.step(p, s, 0.02, rng)
		T.eq(#came, 1, "one came")
		T.eq(#gone, 0)
		local first = came[1]
		T.near(first.at, 100 + Tuning.TideSecs, 1e-6, "its clock when it came")
		T.near(first.life, Tuning.TideLife, 1e-9)
		T.eq(p.seen[first.sp], 1, "seen, not had")
		T.near(Tide.along(first, first.at + Tuning.TideLife / 2), 0.5, 1e-9, "halfway along at half its life")
		-- the belt fills: TideLife / TideSecs floating past at once, the first gone once its life is up
		local most, sawFirstGo = 0, false
		for _ = 1, math.ceil(Tuning.TideLife * 3 / 0.25) do
			came, gone = Tide.step(p, s, 0.25, rng)
			most = math.max(most, #s.list)
			for _, id in gone do
				if id == first.id then
					sawFirstGo = true
					T.truthy(s.clock - first.at >= first.life - 1e-6, "not before its life is up")
					T.truthy(s.clock - first.at < first.life + 0.25 + 1e-6, "and right when it is")
				end
			end
			for _, d in s.list do
				T.truthy(s.clock - d.at < d.life, "nobody past the end")
			end
		end
		T.truthy(sawFirstGo, "the first floated off")
		local n = Tuning.TideLife / Tuning.TideSecs
		T.truthy(most >= n - 1 and most <= n + 1, "about TideLife / TideSecs at once: " .. most)
		for i = 2, #s.list do
			T.truthy(s.list[i].id > s.list[i - 1].id and s.list[i].at > s.list[i - 1].at, "the oldest (furthest along) first")
		end
		T.eq(#p.pals, 0, "seeing one isn't having it")
	end)

	T.it("the tide is already running when the player comes, spread all along; a new island gets cheap commons", function()
		local p = Schema.default(0, 9)
		local s = Tide.new(50)
		Tide.start(p, s, Util.newRng(1))
		local n = math.floor(Tuning.TideLife / Tuning.TideSecs)
		T.eq(#s.list, n, "the belt full")
		T.near(s.list[#s.list].at, 50, 1e-9, "the newest just came")
		T.near(s.list[1].at, 50 - (n - 1) * Tuning.TideSecs, 1e-9, "the oldest far along")
		local knacks = {}
		local cheap = 0
		for _, d in s.list do
			local c = Creatures.byId[d.sp]
			if c.rarity == 1 and d.cost <= Tuning.StartShells then
				knacks[c.knack] = true
				cheap += 1
			end
		end
		T.truthy(knacks.wood and knacks.farm, "cheap ones good with wood and at a farm")
		T.truthy(cheap >= n // 3, "every third one at least: " .. cheap)
		-- and they keep coming while nothing is taken in
		local guaranteed = 0
		for _ = 1, 30 do
			local came = Tide.step(p, s, Tuning.TideSecs, Util.newRng(guaranteed + 5))
			for _, d in came do
				local c = Creatures.byId[d.sp]
				if c.rarity == 1 and (c.knack == "wood" or c.knack == "farm") then
					guaranteed += 1
				end
			end
		end
		T.truthy(guaranteed >= 10, "a cheap one with work every few seconds: " .. guaranteed)
		-- an island with driftlings gets the tide as it comes
		local q = fresh()
		pal(q, "pebblit")
		q.stats.taken = 1
		local s2 = Tide.new()
		Tide.start(q, s2, Util.newRng(1))
		T.eq(#s2.list, n)
	end)

	T.it("what drifts in: the kinds open at the island's tier, rarer ones less often, a bigger island luckier", function()
		local p = fresh()
		local rng = Util.newRng(11)
		local open: { [string]: boolean } = {}
		for _, k in Islets.list do
			if k.tier <= 1 then
				for _, sp in k.wild do
					open[sp] = true
				end
			end
		end
		local counts = { 0, 0, 0, 0, 0 }
		for _ = 1, 4000 do
			local sp, muts = Tide.roll(p, rng)
			T.truthy(open[sp], sp .. " is open at tier 1")
			T.truthy(#muts <= Traits.MAX)
			local r = Creatures.byId[sp].rarity
			counts[r] += 1
		end
		T.truthy(counts[1] > counts[2] and counts[2] > counts[3], "rarer ones less often")
		local o1 = Tide.odds(p, 1)
		local o4 = Tide.odds(p, 4)
		T.truthy(o4[1] < o1[1], "a bigger island: fewer commons")
		local sum = 0
		for _, v in o4 do
			sum += v
		end
		T.near(sum, 1, 1e-9)
	end)

	T.it("the huts' tide and luck shares bring them faster and luckier, each capped", function()
		local p = fresh()
		build(p, "lumber")
		build(p, "pier")
		build(p, "patch")
		build(p, "nest")
		local base = Tide.secs(p)
		T.near(base, Tuning.TideSecs, 1e-9)
		local l0 = Tide.luck(p)
		pal(p, "gullfin", { "swift4", "bright4" }) -- its passive's tide share and two big mutations
		T.truthy(Tide.secs(p) < base, "faster")
		T.truthy(Tide.luck(p) > l0, "luckier")
		local tide, luck = Tide.hutFx(p)
		T.truthy(tide <= Tuning.HutTide and luck <= Tuning.HutLuck)
	end)

	T.it("taking one in: its cost in shells, a hut with room, the comfiest first, straight to work", function()
		local p = fresh()
		local s = Tide.new()
		local d = drift(s, p, "pebblit")
		T.eq(select(2, Tide.take(p, s, d.id, 0)), "no_hut", "no hut built")
		build(p, "lumber")
		local nest = build(p, "nest")
		p.shells = d.cost - 1
		T.eq(select(2, Tide.take(p, s, d.id, 0)), "money")
		p.shells = d.cost + 5
		local ok, data = Tide.take(p, s, d.id, 0)
		T.truthy(ok, tostring(data))
		T.eq(p.shells, 5, "paid")
		T.eq(#s.list, 0, "off the tide")
		local x = p.pals[#p.pals]
		T.eq(x.sp, "pebblit")
		T.eq(x.home, nest)
		T.truthy(x.work ~= 0, "at the lumber camp")
		T.eq(p.seen.pebblit, 2)
		T.eq(p.stats.taken, 1)
		T.eq(select(2, Tide.take(p, s, d.id, 0)), "not_found", "gone")
		-- the comfiest hut with room first
		p.tier = 2
		p.shells = 1e7
		local burrow = build(p, "burrow")
		local e = drift(s, p, "clawdle")
		Tide.take(p, s, e.id, 0)
		T.eq(p.pals[#p.pals].home, burrow, "the burrow is comfier")
	end)

	T.it("every hut full: a swap, the one swapped out sold for its price; refusals", function()
		local p = fresh()
		local s = Tide.new()
		build(p, "lumber")
		local nest = build(p, "nest") -- room 2
		local a = pal(p, "pebblit")
		local b = pal(p, "pebblit")
		local d = drift(s, p, "shellback") -- rare, wood
		T.eq(select(2, Tide.take(p, s, d.id, 0)), "full", "no swap named")
		T.eq(select(2, Tide.take(p, s, d.id, 99999)), "bad_payload", "no such driftling")
		local shells = p.shells
		local ok, data = Tide.take(p, s, d.id, a.id)
		T.truthy(ok)
		T.eq(data.sold, Tide.price(a))
		T.eq(p.shells, shells - d.cost + Tide.price(a))
		T.eq(table.find(p.pals, a), nil, "swapped out")
		T.eq(p.pals[#p.pals].home, nest, "in its place")
		T.eq(p.stats.sold, 1)
		T.truthy(table.find(p.pals, b) ~= nil)
	end)

	T.it("the cost: its rarity, its mutations, its cost share and the island's tier", function()
		local p = fresh()
		T.eq(Tide.cost(p, "pebblit", {}), Tuning.TidePrice[1])
		T.eq(Tide.cost(p, "pebblit", { "busy2", "fierce1" }), math.floor(Tuning.TidePrice[1] * (1 + Tuning.SellTier * 3) + 0.5))
		T.truthy(Tide.cost(p, "pebblit", { "sturdy2" }) < Tide.cost(p, "pebblit", { "busy2" }), "Frugal costs less")
		T.truthy(Tide.cost(p, "solwyrm", {}) > Tide.cost(p, "pebblit", {}) * 50, "a legend costs far more")
		p.tier = 3
		T.eq(Tide.cost(p, "pebblit", {}), math.floor(Tuning.TidePrice[1] * Tuning.TideTier[3] + 0.5))
		T.truthy(Tide.cost(p, "pebblit", {}) > Tide.price({ id = 0, sp = "pebblit", home = 0, work = 0 }), "dearer to take than to sell")
	end)

	T.it("a driftling in a hut takes a job of its knack (HelpMax a building); one with no hut doesn't work", function()
		local p = fresh()
		local patch = build(p, "patch")
		build(p, "nest")
		build(p, "nest")
		local list = {}
		for _ = 1, 3 do
			table.insert(list, pal(p, "mossbun")) -- farm
		end
		local at = 0
		for _, x in list do
			if x.work == patch then
				at += 1
			end
		end
		T.eq(at, Tuning.HelpMax, "two at the patch")
		local patch2 = build(p, "patch")
		Tide.fillJobs(p)
		for _, x in list do
			T.truthy(x.home ~= 0 and (x.work == patch or x.work == patch2), "all three at work")
		end
		local q = fresh()
		local x = pal(q, "frondle") -- no hut on q
		T.eq(x.home, 0)
		T.eq(select(1, Island.setHelp(q, x.id, 0)), true, "resting is fine")
	end)

	T.it("rarer ones work faster (RarityWork)", function()
		local p = fresh()
		build(p, "nest")
		build(p, "lumber")
		build(p, "patch")
		local common = pal(p, "pebblit")
		local legend = pal(p, "solwyrm")
		local wc = Island.palBoost(p, common)
		local wl = Island.palBoost(p, legend)
		T.near(wc, Tuning.PalWork * Tuning.RarityWork[1] * (1 + Island.palWork(p, common)), 1e-9)
		T.near(wl, Tuning.PalWork * Tuning.RarityWork[5] * (1 + Island.palWork(p, legend)), 1e-9)
		T.truthy(wl > wc * 3)
	end)

	T.it("moving between huts: a full hut only in a swap; refusals", function()
		local p = fresh()
		build(p, "lumber")
		build(p, "pier")
		build(p, "stall")
		local nest = build(p, "nest")
		local a = pal(p, "pebblit")
		local b = pal(p, "clawdle")
		local nest2 = build(p, "nest")
		local c = pal(p, "gullfin")
		T.eq(a.home, nest)
		T.eq(b.home, nest)
		T.eq(c.home, nest2)
		T.eq(select(2, Tide.house(p, c.id, nest, 0)), "full")
		T.truthy(Tide.house(p, c.id, nest, a.id), "a swap")
		T.eq(c.home, nest)
		T.eq(a.home, nest2)
		T.eq(select(2, Tide.house(p, c.id, 0, 0)), "bad_payload", "no pen to move to")
		T.eq(select(2, Tide.house(p, 99999, nest, 0)), "not_found")
		T.eq(select(2, Tide.house(p, c.id, nest2, b.id)), "bad_payload", "the swap doesn't live there")
	end)

	T.it("selling: shells by rarity and mutations; a hut's room goes to one waiting with no hut", function()
		local p = fresh()
		local x = pal(p, "pebblit", {})
		T.eq(Tide.price(x), Tuning.SellPrice[1])
		local y = pal(p, "pebblit", { "busy2", "fierce1" }) -- tiers 3; Shiny +30% sell
		T.eq(Tide.price(y), math.floor(Tuning.SellPrice[1] * (1 + Tuning.SellTier * 3) * 1.3 + 0.5))
		local shells = p.shells
		local ok, data = Tide.sell(p, x.id)
		T.truthy(ok)
		T.eq(data.shells, Tuning.SellPrice[1])
		T.eq(p.shells, shells + Tuning.SellPrice[1])
		T.eq(p.stats.sold, 1)
		T.eq(select(2, Tide.sell(p, x.id)), "not_found")
		-- a hut's driftling sold: one waiting moves in
		build(p, "lumber")
		local nest = build(p, "nest")
		Tide.settle(p)
		T.eq(y.home, nest)
		local a = pal(p, "clawdle")
		T.eq(a.home, nest)
		local b = pal(p, "conchy")
		T.eq(b.home, 0, "no room")
		T.truthy(Tide.sell(p, a.id))
		T.eq(b.home, nest, "moved in")
	end)

	T.it("a hut cleared away or replaced smaller leaves its driftlings with no hut till there's room", function()
		local p = fresh()
		p.tier = 2
		local burrow = build(p, "burrow") -- room 4
		build(p, "lumber")
		build(p, "lumber")
		local list = {}
		for _ = 1, 4 do
			table.insert(list, pal(p, "pebblit"))
		end
		for _, x in list do
			T.eq(x.home, burrow)
		end
		local i = 0
		for j, q in p.plot.placed do
			if q.uid == burrow then
				i = j
			end
		end
		T.truthy(Plot.replace(p, i, "nest"), "replaced with a hut of room 2")
		local inHut = 0
		for _, x in list do
			if x.home == burrow then
				inHut += 1
			end
		end
		T.eq(inHut, 2, "two stay")
		T.truthy(Plot.store(p, i))
		for _, x in list do
			T.eq(x.home, 0, "no hut")
			T.eq(x.work, 0)
		end
		local nest = build(p, "nest")
		Tide.settle(p)
		local back = 0
		for _, x in list do
			if x.home == nest then
				back += 1
			end
		end
		T.eq(back, 2, "two move into the new hut")
	end)
end
