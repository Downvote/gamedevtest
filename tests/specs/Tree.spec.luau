-- The Tree of Life, its eggs and the huts (Logic/Tree; GAME_DESIGN 6): every island has its tree; it lays
-- EggCount[tier] eggs round its roots every EggSecs (the ones left go); a bigger island lays more and better eggs;
-- hatching one costs shells and a hut's room (every hut full: a swap, the one swapped out sold); what hatches takes a
-- job of its knack; one with no hut waits for room; the player moves them between huts and sells them.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Tree = require("../../build/luautest/shared/Logic/Tree")
local Island = require("../../build/luautest/shared/Logic/Island")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Quests = require("../../build/luautest/shared/Data/Quests")
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
	return Tree.add(p, sp, muts or {})
end

-- an egg of a rarity under the tree (for the hatch tests)
local function egg(p: any, r: number): any
	local e = { id = p.clutch.next, r = r }
	p.clutch.next += 1
	table.insert(p.clutch.list, e)
	return e
end

return function()
	T.it("a new island has its Tree of Life and two stores: wood to build, shells for eggs", function()
		local p = Schema.default(0, 1)
		T.eq(#p.plot.placed, 1, "only the tree")
		T.eq(p.plot.placed[1].id, Tree.ID)
		T.truthy(Tree.piece(p) ~= nil)
		T.eq(p.wood, Tuning.StartWood)
		T.eq(p.shells, Tuning.StartShells)
		T.eq((p :: any).food, nil, "no food")
		T.eq(#p.clutch.list, 0, "its first eggs come the moment the player arrives")
		T.eq(p.clutch.left, 0)
		-- the tips' buildings fit the starting wood (a camp, a patch, a hut)
		local need = 0
		for _, id in { "lumber", "patch", "nest" } do
			need += Buildings.byId[id].wood
			T.eq(Buildings.byId[id].shells, 0, id .. " costs no shells")
		end
		T.truthy(need <= Tuning.StartWood, "the tips' buildings: " .. need)
	end)

	T.it("the tree lays EggCount eggs every EggSecs, the ones left going; each one's price", function()
		local p = fresh()
		local rng = Util.newRng(3)
		local laid = Tree.step(p, 0.1, rng)
		T.truthy(laid ~= nil, "a new island's first lot at once")
		T.eq(#p.clutch.list, Tuning.EggCount[1])
		T.near(p.clutch.left, Tuning.EggSecs, 1e-9)
		local ids = {}
		for _, e in p.clutch.list do
			T.truthy(e.r >= 1 and e.r <= 5)
			T.truthy(not ids[e.id], "ids unique")
			ids[e.id] = true
		end
		-- one hatched or not, the next lot replaces them all
		T.eq(Tree.step(p, Tuning.EggSecs - 1, rng), nil, "not yet")
		local before = p.clutch.list[1].id
		laid = Tree.step(p, 1.01, rng)
		T.truthy(laid ~= nil and #laid == Tuning.EggCount[1], "a new lot")
		T.eq(#p.clutch.list, Tuning.EggCount[1], "the old ones gone")
		for _, e in p.clutch.list do
			T.truthy(e.id > before, "all new")
		end
		-- the view: each with its price on this island
		local v = Tree.view(p)
		for i, e in v do
			T.eq(e.cost, Tree.cost(p, p.clutch.list[i].r))
		end
		T.eq(#p.pals, 0, "laying isn't hatching")
	end)

	T.it("a bigger island lays more eggs and better ones; growing lays the extra at once", function()
		local p = fresh()
		local rng = Util.newRng(5)
		Tree.lay(p, rng)
		T.eq(#p.clutch.list, Tuning.EggCount[1])
		p.tier = 3
		local more = Tree.fill(p, rng)
		T.eq(#more, Tuning.EggCount[3] - Tuning.EggCount[1], "the extra ones")
		T.eq(#p.clutch.list, Tuning.EggCount[3])
		for t = 2, 6 do
			T.truthy(Tuning.EggCount[t] > Tuning.EggCount[t - 1], "more each tier")
			local lo, hi = Tree.odds(p, t - 1), Tree.odds(p, t)
			T.truthy(hi[1] < lo[1], "fewer commons on tier " .. t)
		end
		local o1, o6 = Tree.odds(p, 1), Tree.odds(p, 6)
		T.truthy(o6[4] + o6[5] > (o1[4] + o1[5]) * 3, "far more epics and legends on the biggest island")
	end)

	T.it("a new island's first lot has two cheap commons; its first two hatches are good with wood and at a farm", function()
		local p = Schema.default(0, 9)
		Tree.step(p, 0.1, Util.newRng(1))
		local commons = 0
		for _, e in p.clutch.list do
			if e.r == 1 then
				commons += 1
				T.truthy(Tree.cost(p, 1) <= Tuning.StartShells, "affordable at the start")
			end
		end
		T.truthy(commons >= 2, "two commons at least: " .. commons)
		build(p, "lumber")
		build(p, "patch")
		build(p, "nest")
		p.shells = 1e6
		local knacks = {}
		for k = 1, 2 do
			local e = egg(p, 1)
			local ok, data = Tree.hatch(p, e.id, 0, Util.newRng(k))
			T.truthy(ok, tostring(data))
			T.eq(data.hr, 1, "the tips' first two never turn rarer")
			table.insert(knacks, Creatures.byId[data.sp].knack)
		end
		T.eq(knacks[1], "wood")
		T.eq(knacks[2], "farm")
	end)

	-- (the request of 2026-11-14: "also, while the rare one quest is active or any rarity related quests, make it such
	-- that an egg of that rarity will always spawn in the tree of life.")
	T.it("a quest asking for a rarity always finds an egg of it under the tree; nothing changes without one", function()
		-- an island past the tips, its rarity quests in Data/Quests (a "best" goal)
		local function island(quest: number, tier: number): any
			local p = fresh()
			p.tut, p.quest, p.tier = 0, quest, tier
			p.stats.taken, p.stats.best = 3, 1
			pal(p, Creatures.list[1].id)
			p.stats.best = 1
			return p
		end
		local lowest = function(r: number): number
			for t = 1, #Tuning.EggCount do
				if #Tree.pool(t)[r] > 0 then
					return t
				end
			end
			return 0
		end
		local asked = 0
		local plain = 0
		for qi, q in Quests.list do
			if q.goal.kind ~= "best" then
				plain = if plain == 0 then qi else plain
				continue
			end
			asked += 1
			local r = q.goal.n
			local tier = lowest(r)
			T.truthy(tier > 0, q.id .. ": some tier hatches its rarity")
			local p = island(qi, tier)
			T.eq(Tree.wanted(p), r, q.id .. " wants rarity " .. r)
			-- every lot laid holds one, at that rarity's price, the lot no bigger
			for seed = 1, 60 do
				Tree.lay(p, Util.newRng(seed))
				T.eq(#p.clutch.list, Tree.count(tier), "the lot's size")
				local has = false
				for i, e in p.clutch.list do
					if e.r == r then
						has = true
						T.eq(Tree.view(p)[i].cost, Tree.cost(p, r), "its rarity's price")
					end
				end
				T.truthy(has, q.id .. ": an egg of rarity " .. r .. " (seed " .. seed .. ")")
			end
			-- met: no more help; the tips on: none either
			p.stats.best = r
			T.eq(Tree.wanted(p), 0, q.id .. " met")
			p.stats.best = 1
			p.tut = 3
			T.eq(Tree.wanted(p), 0, "not while the tips are on")
		end
		T.truthy(asked >= 3, "the uncommon, rare and epic quests: " .. asked)
		-- without such a quest the lot is the plain roll; with one, at most one egg differs: the commonest, turned
		local rareQ = 0
		for qi, q in Quests.list do
			if q.goal.kind == "best" and q.goal.n == 3 then
				rareQ = qi
			end
		end
		local tier = lowest(3)
		local turnedSome = false
		for seed = 1, 120 do
			local a, b = island(plain, tier), island(rareQ, tier)
			T.eq(Tree.wanted(a), 0, "a quest that asks for no rarity")
			Tree.lay(a, Util.newRng(seed))
			Tree.lay(b, Util.newRng(seed))
			local hadRare, low = false, 9
			for _, e in a.clutch.list do
				hadRare = hadRare or e.r == 3
				low = math.min(low, e.r)
			end
			local diff = 0
			for i, e in a.clutch.list do
				local f = b.clutch.list[i]
				T.eq(f.id, e.id, "the same eggs")
				if f.r ~= e.r then
					diff += 1
					T.truthy(not hadRare, "only when none was there")
					T.eq(e.r, low, "the commonest one turned")
					T.eq(f.r, 3)
					turnedSome = true
				end
			end
			T.truthy(diff <= 1, "one egg at most")
		end
		T.truthy(turnedSome, "some lots needed the turn")
		-- a quest coming up mid-lot: the commonest egg there (the first laid of those) turns at once, keeping its id
		local p = island(plain, tier)
		local seed = 1
		repeat
			Tree.lay(p, Util.newRng(seed))
			seed += 1
			local any = false
			for _, e in p.clutch.list do
				any = any or e.r >= 3
			end
		until not any
		T.eq(Tree.ensure(p), nil, "nothing to do without the quest")
		local low, first = 9, nil
		for _, e in p.clutch.list do
			if e.r < low then
				low, first = e.r, e
			end
		end
		local ids = {}
		for _, e in p.clutch.list do
			table.insert(ids, e.id)
		end
		p.quest = rareQ
		local turned = Tree.ensure(p)
		T.truthy(turned ~= nil and turned == first, "the commonest, first laid")
		T.eq((turned :: any).r, 3)
		for i, e in p.clutch.list do
			T.eq(e.id, ids[i], "ids and places kept")
		end
		T.eq(Tree.ensure(p), nil, "once is enough")
		-- hatched: the quest is met, the next lot is the plain roll again
		build(p, "nest")
		p.shells = 1e7
		local ok, data = Tree.hatch(p, (turned :: any).id, 0, Util.newRng(9))
		T.truthy(ok, tostring(data))
		T.truthy(data.hr >= 3)
		T.eq(Tree.wanted(p), 0, "the rare one had")
		-- an egg already rarer than asked is left alone
		local q = island(rareQ, tier)
		table.clear(q.clutch.list)
		egg(q, 5)
		egg(q, 4)
		T.eq(Tree.ensure(q), nil, "every egg rarer: nothing turns")
		T.eq(q.clutch.list[1].r, 5)
		-- a new island's first lot keeps its two commons
		local n = Schema.default(0, 9)
		n.tut, n.quest = 0, rareQ
		Tree.step(n, 0.1, Util.newRng(1))
		local commons = 0
		for _, e in n.clutch.list do
			if e.r == 1 then
				commons += 1
			end
		end
		T.truthy(commons >= 2, "the first lot's commons")
	end)

	-- (the request of 2026-11-13: "eggs having a chance to skip to the next rarity during the cutscene")
	T.it("mythic and celestial eggs: only once the kinds past the capital are open, dearer than legendary, never risen to early", function()
		local p = fresh()
		p.tier = 10
		local pool10 = Tree.pool(10)
		T.truthy(#pool10 == Traits.RMAX and #pool10[6] == 0 and #pool10[7] == 0, "none up to tier 10")
		local odds = Tree.odds(p)
		local sum = 0
		for _, o in odds do
			sum += o
		end
		T.truthy(#odds == Traits.RMAX and odds[6] == 0 and odds[7] == 0 and math.abs(sum - 1) < 1e-9, "tier 10: their shares go to legendary")
		T.truthy(#Tree.pool(11)[6] > 0 and #Tree.pool(11)[7] == 0, "tier 11: the moonwoods' mythic one, no celestial yet")
		T.truthy(#Tree.pool(14)[7] > 0, "tier 14: the cloudtops' celestial one")
		T.truthy(#Tree.pool(17)[6] >= 3 and #Tree.pool(17)[7] >= 3, "tier 17: three of each")
		local o17 = Tree.odds(p, 17)
		T.truthy(o17[7] > 0 and o17[7] < o17[6] and o17[6] < o17[5], "tier 17: celestial rarer than mythic, mythic than legendary")
		T.truthy(Tree.cost(p, 7) > Tree.cost(p, 6) and Tree.cost(p, 6) > Tree.cost(p, 5), "dearer by rarity")
		local always = { next = function(): number return 0 end, int = function(_, a: number): number return a end } :: any
		T.eq(Tree.rise(p, always, 5), 5, "a sure climb stops at legendary on a tier 10 island")
		-- a mythic or celestial egg on an island without their kinds hatches as the next commoner one
		local sp = Tree.roll(p, Util.newRng(3), 7)
		T.eq(Creatures.byId[sp].rarity, 5)
	end)
	T.it("an egg may turn rarer as it hatches: EggUp a step, on while the rolls hold, never past the open kinds", function()
		local p = fresh()
		local always = { next = function(): number return 0 end, int = function(_, a: number): number return a end } :: any
		local never = { next = function(): number return 0.999 end, int = function(_, a: number): number return a end } :: any
		-- (a new island has no legendary kind open: a sure climb stops at epic)
		T.eq(Tree.rise(p, always, 1), 4)
		T.eq(Tree.rise(p, never, 2), 2)
		p.tier = 10
		T.eq(Tree.rise(p, always, 3), 5)
		T.eq(Tree.rise(p, always, 5), 5)
		local rng = Util.newRng(21)
		local up, n = 0, 4000
		for _ = 1, n do
			if Tree.rise(p, rng, 1) > 1 then
				up += 1
			end
		end
		T.truthy(math.abs(up / n - Tuning.EggUp[1]) < 0.02, "about EggUp[1] of commons turn rarer: " .. up / n)
		-- the hatch says what it was laid as and what it hatched as; what hatched is of that rarity
		build(p, "lumber")
		build(p, "patch")
		for _ = 1, 4 do
			build(p, "nest")
		end
		p.stats.taken = 5
		local rose = 0
		for k = 1, 60 do
			local e = egg(p, 2)
			local ok, data = Tree.hatch(p, e.id, 0, Util.newRng(100 + k))
			if not ok then
				break
			end
			T.eq(data.r, 2)
			T.truthy(data.hr >= 2 and data.hr <= 5)
			T.eq(Creatures.byId[data.sp].rarity, data.hr, "it hatches the rarity it rose to")
			if data.hr > 2 then
				rose += 1
			end
		end
		T.truthy(rose < 20, "most stay as laid: " .. rose)
	end)

	T.it("what hatches: the kinds open at the island's tier of the egg's rarity; rarer eggs less often", function()
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
		for r = 1, 4 do
			for _ = 1, 40 do
				local sp, muts = Tree.roll(p, rng, r)
				T.truthy(open[sp], sp .. " is open at tier 1")
				T.truthy(#muts <= Traits.MAX)
				T.eq(Creatures.byId[sp].rarity, r, "the egg's rarity")
			end
		end
		-- (no legendary kind is open on a new island: a legendary egg there hatches the next commoner rarity)
		local sp5 = Tree.roll(p, rng, 5)
		T.truthy(open[sp5] and Creatures.byId[sp5].rarity < 5)
		local counts = { 0, 0, 0, 0, 0 }
		for _ = 1, 600 do
			p.clutch.list = {}
			Tree.lay(p, rng)
			for _, e in p.clutch.list do
				counts[e.r] += 1
			end
		end
		T.truthy(counts[1] > counts[2] and counts[2] > counts[3], "rarer eggs less often")
		local o1 = Tree.odds(p, 1)
		local o4 = Tree.odds(p, 4)
		T.truthy(o4[1] < o1[1], "a bigger island: fewer commons")
		local sum = 0
		for _, v in o4 do
			sum += v
		end
		T.near(sum, 1, 1e-9)
	end)

	T.it("the huts' tree, luck and cost shares: eggs sooner, luckier and cheaper, each capped", function()
		local p = fresh()
		build(p, "lumber")
		build(p, "pier")
		build(p, "patch")
		build(p, "nest")
		local base = Tree.secs(p)
		T.near(base, Tuning.EggSecs, 1e-9)
		local l0 = Tree.luck(p)
		local c0 = Tree.cost(p, 3)
		pal(p, "gullfin", { "swift4", "bright4", "sturdy4" }) -- its passive's tree share and three big mutations
		T.truthy(Tree.secs(p) < base, "sooner")
		T.truthy(Tree.luck(p) > l0, "luckier")
		T.truthy(Tree.cost(p, 3) < c0, "cheaper")
		local tree, luck, cost = Tree.hutFx(p)
		T.truthy(tree <= Tuning.HutTree and luck <= Tuning.HutLuck and cost <= Tuning.HutCost)
		T.eq(Tree.cost(p, 3), math.max(1, math.floor(Tuning.EggPrice[3] * (1 - cost) + 0.5)))
	end)

	T.it("hatching an egg: its cost in shells, a hut with room, the comfiest first, straight to work", function()
		local p = fresh()
		p.stats.taken = 5 -- (past the new island's first two)
		local e = egg(p, 1)
		local rng = Util.newRng(4)
		T.eq(select(2, Tree.hatch(p, e.id, 0, rng)), "no_hut", "no hut built")
		build(p, "lumber")
		build(p, "pier")
		build(p, "patch")
		build(p, "stall")
		local nest = build(p, "nest")
		local cost = Tree.cost(p, 1)
		p.shells = cost - 1
		T.eq(select(2, Tree.hatch(p, e.id, 0, rng)), "money")
		p.shells = cost + 5
		local ok, data = Tree.hatch(p, e.id, 0, rng)
		T.truthy(ok, tostring(data))
		T.eq(p.shells, 5, "paid")
		T.eq(#p.clutch.list, 0, "the egg is gone")
		local x = p.pals[#p.pals]
		T.eq(x.sp, data.sp)
		T.eq(data.r, 1, "laid a common")
		T.eq(Creatures.byId[x.sp].rarity, data.hr, "what hatched has the rarity the egg hatched as (Tree.rise)")
		T.eq(x.home, nest)
		T.truthy(x.work ~= 0, "at work")
		T.eq(p.seen[x.sp], 2)
		T.eq(p.stats.taken, 6)
		T.eq(data.egg, e.id)
		T.eq(select(2, Tree.hatch(p, e.id, 0, rng)), "not_found", "gone")
		-- the comfiest hut with room first
		p.tier = 2
		p.shells = 1e7
		local burrow = build(p, "burrow")
		local f = egg(p, 2)
		Tree.hatch(p, f.id, 0, rng)
		T.eq(p.pals[#p.pals].home, burrow, "the burrow is comfier")
	end)

	T.it("a kind never had before hatches as new (the scene's \"New!\"); a second of it doesn't", function()
		-- (the request of 2026-11-14: "there should a tip saying \"New!\" If the creature caught is new")
		local p = fresh()
		p.stats.taken = 5
		build(p, "nest")
		build(p, "nest")
		local rng = Util.newRng(11)
		local e = egg(p, 1)
		local ok, data = Tree.hatch(p, e.id, 0, rng)
		T.truthy(ok, tostring(data))
		T.eq(data.new, true, "the first of its kind")
		local sp = data.sp
		-- the same kind again: every common kind had, so whatever hatches has been had
		for _, d in Creatures.list do
			p.seen[d.id] = 2
		end
		local f = egg(p, 1)
		local ok2, data2 = Tree.hatch(p, f.id, 0, rng)
		T.truthy(ok2, tostring(data2))
		T.eq(data2.new, false, "had before: not new")
		-- met in the Index (seen 1) but never had: still new
		for _, d in Creatures.list do
			p.seen[d.id] = 1
		end
		p.seen[sp] = 1
		local g = egg(p, 1)
		local ok3, data3 = Tree.hatch(p, g.id, 0, rng)
		T.truthy(ok3, tostring(data3))
		T.eq(data3.new, true, "only seen, never had: new")
		T.eq(p.seen[data3.sp], 2, "had now")
	end)

	T.it("every hut full: a swap, the one swapped out sold for its price; refusals", function()
		local p = fresh()
		p.stats.taken = 5
		build(p, "lumber")
		local nest = build(p, "nest") -- room 2
		local a = pal(p, "pebblit")
		local b = pal(p, "pebblit")
		local e = egg(p, 3)
		local rng = Util.newRng(8)
		T.eq(select(2, Tree.hatch(p, e.id, 0, rng)), "full", "no swap named")
		T.eq(select(2, Tree.hatch(p, e.id, 99999, rng)), "bad_payload", "no such driftling")
		local shells = p.shells
		local cost = Tree.cost(p, 3)
		local ok, data = Tree.hatch(p, e.id, a.id, rng)
		T.truthy(ok)
		T.eq(data.sold, Tree.price(a))
		T.eq(p.shells, shells - cost + Tree.price(a))
		T.eq(table.find(p.pals, a), nil, "swapped out")
		T.eq(p.pals[#p.pals].home, nest, "in its place")
		T.eq(p.stats.sold, 1)
		T.truthy(table.find(p.pals, b) ~= nil)
	end)

	T.it("an egg's cost: its rarity and the island's tier", function()
		local p = fresh()
		T.eq(Tree.cost(p, 1), Tuning.EggPrice[1])
		T.truthy(Tree.cost(p, 5) > Tree.cost(p, 1) * 50, "a legendary egg costs far more")
		p.tier = 3
		T.eq(Tree.cost(p, 1), math.floor(Tuning.EggPrice[1] * Tuning.EggTier[3] + 0.5))
		T.truthy(Tree.cost(p, 1) > Tree.price({ id = 0, sp = "pebblit", home = 0, work = 0 }), "dearer to hatch than to sell")
	end)

	T.it("the tree: planted on a new island, never bought, cleared away or replaced, outside the piece limit", function()
		local p = Schema.default(0, 3)
		local q = Tree.piece(p) :: any
		T.truthy(q ~= nil)
		local i = table.find(p.plot.placed, q) :: number
		T.eq(select(2, Plot.store(p, i)), "fixed")
		T.eq(select(2, Plot.place(p, Tree.ID, 0, 0, 0)), "bad_payload")
		T.eq(#Plot.replacements(q, 6), 0)
		local used = Plot.used(p, "patch")
		T.eq(used, 0, "the tree doesn't count")
		-- an older save with no tree gets one
		p.plot.placed = {}
		T.truthy(Tree.plant(p) ~= nil and Tree.piece(p) ~= nil)
		for t = 1, 6 do
			T.eq(Tree.stage(t), Tuning.TreeStage[t])
		end
	end)

	T.it("a driftling in a hut takes a job, its knack's first (HelpMax a building); one with no hut doesn't work", function()
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
		local resting = 0
		for _, x in list do
			resting += if x.work == 0 then 1 else 0
		end
		T.eq(resting, #list - Tuning.HelpMax, "the third rests: no other workplace")
		local camp = build(p, "lumber")
		Tree.fillJobs(p)
		local atCamp = 0
		for _, x in list do
			atCamp += if x.work == camp then 1 else 0
		end
		T.eq(atCamp, #list - Tuning.HelpMax, "a farm driftling with no farm place takes the lumber camp")
		for _, x in list do
			if x.work == camp then
				x.work = 0
			end
		end
		local patch2 = build(p, "patch")
		Tree.fillJobs(p)
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
		T.eq(select(2, Tree.house(p, c.id, nest, 0)), "full")
		T.truthy(Tree.house(p, c.id, nest, a.id), "a swap")
		T.eq(c.home, nest)
		T.eq(a.home, nest2)
		T.eq(select(2, Tree.house(p, c.id, 0, 0)), "bad_payload", "no pen to move to")
		T.eq(select(2, Tree.house(p, 99999, nest, 0)), "not_found")
		T.eq(select(2, Tree.house(p, c.id, nest2, b.id)), "bad_payload", "the swap doesn't live there")
	end)

	T.it("selling: shells by rarity and mutations; a hut's room goes to one waiting with no hut", function()
		local p = fresh()
		local x = pal(p, "pebblit", {})
		T.eq(Tree.price(x), Tuning.SellPrice[1])
		local y = pal(p, "pebblit", { "busy2", "fierce1" }) -- tiers 3; Shiny +30% sell
		T.eq(Tree.price(y), math.floor(Tuning.SellPrice[1] * (1 + Tuning.SellTier * 3) * 1.3 + 0.5))
		local shells = p.shells
		local ok, data = Tree.sell(p, x.id)
		T.truthy(ok)
		T.eq(data.shells, Tuning.SellPrice[1])
		T.eq(p.shells, shells + Tuning.SellPrice[1])
		T.eq(p.stats.sold, 1)
		T.eq(select(2, Tree.sell(p, x.id)), "not_found")
		-- a hut's driftling sold: one waiting moves in
		build(p, "lumber")
		local nest = build(p, "nest")
		Tree.settle(p)
		T.eq(y.home, nest)
		local a = pal(p, "clawdle")
		T.eq(a.home, nest)
		local b = pal(p, "conchy")
		T.eq(b.home, 0, "no room")
		T.truthy(Tree.sell(p, a.id))
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
		Tree.settle(p)
		local back = 0
		for _, x in list do
			if x.home == nest then
				back += 1
			end
		end
		T.eq(back, 2, "two move into the new hut")
	end)
end
