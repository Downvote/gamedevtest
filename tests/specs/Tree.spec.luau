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
	p.shells = 1e7
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
	T.it("a new island has its Tree of Life and one store: shells to build and for eggs", function()
		local p = Schema.default(0, 1)
		T.eq(#p.plot.placed, 1, "only the tree")
		T.eq(p.plot.placed[1].id, Tree.ID)
		T.truthy(Tree.piece(p) ~= nil)
		T.eq((p :: any).wood, nil, "no wood: one store since 2026-11-14")
		T.eq(p.shells, Tuning.StartShells)
		T.eq((p :: any).food, nil, "no food")
		T.eq(#p.clutch.list, 0, "its first eggs come the moment the player arrives")
		T.eq(p.clutch.left, 0)
		-- the tips' buildings (a camp, a patch, a hut, a stall) and a few first eggs fit the starting shells
		local need = 0
		for _, id in { "lumber", "patch", "nest", "stall" } do
			need += Buildings.byId[id].shells
		end
		T.truthy(need + 4 * Tuning.EggPrice[1] * Tuning.EggTier[1] <= Tuning.StartShells, "the tips' buildings: " .. need)
		-- (and the first hut filled with a rare and a common, so no tip waits on shells: "give the player more shells
		-- so every task is completable at the start without needing to wait", 2026-11-14)
		local eggs = (Tuning.EggPrice[3] + Tuning.EggPrice[1]) * Tuning.EggTier[1]
		T.truthy(need + eggs <= Tuning.StartShells, string.format("the tips' buildings %d and a rare and a common egg %d", need, eggs))
	end)

	T.it("no lean any more (2026-11-19): the island's work buildings tip nothing", function()
		local p = fresh()
		p.tier = 2
		build(p, "lumber")
		build(p, "lumber")
		T.eq((Tree :: any).lean, nil, "gone with the kinds of work")
		-- (a roll is the plain one whatever is built)
		local q = fresh()
		q.tier = 2
		local a, b = Util.newRng(21), Util.newRng(21)
		for _ = 1, 50 do
			local _, m1 = Tree.roll(p, a, 3)
			local _, m2 = Tree.roll(q, b, 3)
			T.deepEq(m1, m2)
		end
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
		for k = 1, 2 do
			local e = egg(p, 1)
			local ok, data = Tree.hatch(p, e.id, 0, Util.newRng(k))
			T.truthy(ok, tostring(data))
			T.eq(data.hr, 1, "the tips' first two never turn rarer")
			T.eq(Creatures.byId[data.sp].rarity, 1)
		end
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
		-- an egg already rarer than asked is left alone; with nothing to turn, the tree lays one of that rarity
		local q = island(rareQ, tier)
		table.clear(q.clutch.list)
		egg(q, 5)
		egg(q, 4)
		local next0 = q.clutch.next
		local laid = Tree.ensure(q)
		T.eq(q.clutch.list[1].r, 5, "the rarer ones stay")
		T.eq(q.clutch.list[2].r, 4)
		T.truthy(laid ~= nil and laid.r == 3 and laid.id == next0, "every egg rarer: a rare one laid")
		T.eq(#q.clutch.list, 3)
		T.eq(q.clutch.next, next0 + 1)
		T.eq(Tree.ensure(q), nil, "once is enough")
		-- the lot hatched out (the bug report of 2026-11-16: "the tree dosent have the rare egg in this quest"): the
		-- empty tree lays one, in the season now
		table.clear(q.clutch.list)
		local e = Tree.ensure(q, { season = "autumn" } :: any)
		T.truthy(e ~= nil and e.r == 3 and e.ss == "autumn", "an empty tree lays the quest's egg")
		T.eq(#q.clutch.list, 1)
		T.eq(Tree.ensure(q), nil)
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
	T.it("every egg on every island (2026-11-19): a rarity no open kind has comes very seldom; dearer by rarity", function()
		local p = fresh()
		p.tier = 10
		local pool10 = Tree.pool(10)
		T.truthy(#pool10 == Traits.RMAX and #pool10[6] == 0 and #pool10[7] == 0, "no mythic or celestial kind open up to tier 10")
		local odds = Tree.odds(p)
		local sum = 0
		for _, o in odds do
			sum += o
		end
		T.truthy(#odds == Traits.RMAX and odds[6] > 0 and odds[7] > 0 and math.abs(sum - 1) < 1e-9, "tier 10: mythic and celestial eggs can come")
		T.truthy(odds[6] < odds[5] * 0.01 and odds[7] < odds[6], "very seldom: under a hundredth of the legendary ones")
		-- (their weight is EggEarly of what it would be with their kinds open)
		local q = fresh()
		q.tier = 10
		local o11 = Tree.odds(q, 11)
		T.truthy(o11[6] > odds[6] * 5, "tier 11 opens the moonwoods: mythic eggs far less rare")
		T.truthy(#Tree.pool(11)[6] > 0 and #Tree.pool(11)[7] == 0, "tier 11: the moonwoods' mythic one, no celestial yet")
		T.truthy(#Tree.pool(17)[6] >= 3 and #Tree.pool(17)[7] >= 3, "tier 17: three of each")
		local o17 = Tree.odds(p, 17)
		T.truthy(o17[7] > 0 and o17[7] < o17[6] and o17[6] < o17[5], "tier 17: celestial rarer than mythic, mythic than legendary")
		T.truthy(Tree.cost(p, 7) > Tree.cost(p, 6) and Tree.cost(p, 6) > Tree.cost(p, 5), "dearer by rarity")
		-- a new island lays them too, rarer still
		local n = fresh()
		local o1 = Tree.odds(n)
		T.truthy(o1[5] > 0 and o1[6] > 0 and o1[7] > 0 and o1[6] < 1e-4, string.format("tier 1: legendary %.5f, mythic %.6f", o1[5], o1[6]))
		-- a mythic or celestial egg on an island without their kinds hatches one of them all the same
		local sp = Tree.roll(p, Util.newRng(3), 7)
		T.eq(Creatures.byId[sp].rarity, 7)
		local sp6 = Tree.roll(n, Util.newRng(4), 6)
		T.eq(Creatures.byId[sp6].rarity, 6)
		-- (the two past Celestial, 2026-11-20: "make more higher tier eggs, about 2 more tiers") the ancient ones live
		-- on the cloudtops and the starfalls, the eternal ones on the starfalls
		T.truthy(#Tree.pool(13)[8] == 0 and #Tree.pool(14)[8] >= 1 and #Tree.pool(17)[8] >= 4, "ancient kinds from tier 14, four or more by tier 17")
		T.truthy(#Tree.pool(16)[9] == 0 and #Tree.pool(17)[9] >= 4, "eternal kinds from tier 17, four or more")
		-- (never laid more often than a commoner rarity, at any tier)
		for t = 1, #Tuning.EggLuck do
			local q2 = fresh()
			q2.tier = t
			local o = Tree.odds(q2)
			for r = 6, Traits.RMAX do
				T.truthy(o[r] < o[r - 1], string.format("tier %d: rarity %d rarer than %d", t, r, r - 1))
			end
		end
		local top = fresh()
		top.tier = #Tuning.EggLuck
		local o20 = Tree.odds(top)
		T.truthy(o20[8] > 0 and o20[8] < o20[7] * 0.3 and o20[9] > 0 and o20[9] < o20[8] * 0.3, string.format("Everdrift: celestial %.4f, ancient %.5f, eternal %.6f", o20[7], o20[8], o20[9]))
		T.truthy(1 / o20[8] > 200 and 1 / o20[8] < 500 and 1 / o20[9] > 1200 and 1 / o20[9] < 4000, string.format("Everdrift: an ancient egg one in %.0f, an eternal one one in %.0f", 1 / o20[8], 1 / o20[9]))
		T.truthy(Tree.cost(p, 9) > Tree.cost(p, 8) and Tree.cost(p, 8) > Tree.cost(p, 7), "dearer still")
		for _, r in { 8, 9 } do
			local spr = Tree.roll(n, Util.newRng(5 + r), r)
			T.eq(Creatures.byId[spr].rarity, r, "a new island's egg of rarity " .. r .. " hatches one of them")
		end
	end)
	T.it("an egg may turn rarer as it hatches: EggUp a step (and the huts' skip share), on while the rolls hold", function()
		local p = fresh()
		local always = { next = function(): number return 0 end, int = function(_, a: number): number return a end } :: any
		local never = { next = function(): number return 0.999 end, int = function(_, a: number): number return a end } :: any
		-- (every rarity hatches on every island since 2026-11-19: a sure climb goes to the top)
		T.eq(Tree.rise(p, always, 1), Traits.RMAX)
		T.eq(Tree.rise(p, never, 2), 2)
		p.tier = 10
		T.eq(Tree.rise(p, always, 5), Traits.RMAX)
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
			T.truthy(data.hr >= 2 and data.hr <= Traits.RMAX)
			T.eq(Creatures.byId[data.sp].rarity, data.hr, "it hatches the rarity it rose to")
			if data.hr > 2 then
				rose += 1
			end
		end
		T.truthy(rose < 20, "most stay as laid: " .. rose)
	end)

	T.it("what hatches: mostly the kinds open at the island's tier, now and then a far one (FarKind); rarer eggs less often", function()
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
		local far, all = 0, 0
		for r = 1, 4 do
			for _ = 1, 400 do
				local sp, muts = Tree.roll(p, rng, r)
				all += 1
				if not open[sp] then
					far += 1
				end
				T.truthy(#muts <= Traits.MAX)
				T.eq(Creatures.byId[sp].rarity, r, "the egg's rarity")
			end
		end
		T.truthy(far > 0 and far / all < Tuning.FarKind * 2, string.format("a far kind now and then: %d of %d", far, all))
		-- (no legendary kind is open on a new island: a legendary egg there hatches a legendary one from further away)
		local sp5 = Tree.roll(p, rng, 5)
		T.truthy(not open[sp5] and Creatures.byId[sp5].rarity == 5)
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

	T.it("the huts' luck and cost shares: eggs luckier and cheaper, each capped; the tree's 6 minutes never shorter", function()
		local p = fresh()
		build(p, "lumber")
		build(p, "pier")
		build(p, "patch")
		build(p, "nest")
		local base = Tree.secs(p)
		T.near(base, Tuning.EggSecs, 1e-9)
		local l0 = Tree.luck(p)
		local c0 = Tree.cost(p, 3)
		pal(p, "gullfin", { "swift4", "bright4", "sturdy4" }) -- its passive (once a tree share, egg luck now) and three big mutations
		T.eq(Tree.secs(p), Tuning.EggSecs, "the tree keeps its time (the request of 2026-11-14)")
		T.eq(Tuning.EggSecs, 360, "six minutes (the request of 2026-11-17)")
		T.truthy(Tree.luck(p) > l0, "luckier")
		T.truthy(Tree.cost(p, 3) < c0, "cheaper")
		local luck, cost = Tree.hutFx(p)
		T.truthy(luck <= Tuning.IsleCap.luck and cost <= Tuning.IsleCap.cost)
		-- only the Quick Tree pass makes it five
		p.passes.QuickTree = true
		T.eq(Tree.secs(p), Tuning.EggSecsPass)
		T.eq(Tuning.EggSecsPass, 180, "three minutes with the pass")
		p.passes.QuickTree = nil
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

	T.it("a bulk hatch takes every egg of a rarity or rarer, the rarest first, as far as the coins and huts go", function()
		-- (the request of 2026-11-22: "make a bulk open eggs button, where you open all eggs at once in the tree",
		-- "selecting as in: bulk buy over a certain rarity")
		local p = fresh()
		p.stats.taken = 5
		p.tier = 2
		build(p, "burrow") -- (room for 8)
		local rng = Util.newRng(21)
		local c1, c2 = egg(p, 1), egg(p, 1)
		local u = egg(p, 2)
		local r = egg(p, 3)
		T.deepEq(Tree.atLeast(p.clutch.list, 2), { r.id, u.id }, "uncommon and up, the rarest first")
		T.eq(#Tree.atLeast(p.clutch.list, 1), 4, "every egg from the lowest")
		T.eq(#Tree.atLeast(p.clutch.list, 4), 0, "none that rare")
		-- the plan: two of them for their prices
		local ids = Tree.atLeast(p.clutch.list, 2)
		local plan = Tree.bulkPlan(p, ids, false)
		T.eq(plan.n, 2)
		T.eq(plan.cost, Tree.cost(p, 3) + Tree.cost(p, 2))
		T.eq(plan.short + plan.room, 0)
		local before = p.shells
		local pals0 = #p.pals
		local ok, data = Tree.bulk(p, ids, false, rng)
		T.truthy(ok, tostring(data))
		T.eq(#data.list, 2, "both hatched")
		T.eq(data.list[1].egg, r.id, "the rare one first")
		T.eq(data.list[2].egg, u.id)
		T.eq(before - p.shells, data.cost, "paid what they cost")
		T.eq(#p.pals, pals0 + 2)
		T.eq(#p.clutch.list, 2, "the commons stay")
		T.eq(p.clutch.list[1].id, c1.id)
		T.eq(p.clutch.list[2].id, c2.id)
		T.eq(select(2, Tree.bulk(p, {}, false, rng)), "not_found", "nothing to hatch")
		T.eq(select(2, Tree.bulk(p, ids, false, rng)), "not_found", "those are gone")
		-- the coins: one left for want of them, the cheaper ones still hatch
		local e = egg(p, 3)
		p.shells = Tree.cost(p, 1) * 2 + 1
		plan = Tree.bulkPlan(p, Tree.atLeast(p.clutch.list, 1), false)
		T.eq(plan.n, 2)
		T.eq(plan.short, 1)
		ok, data = Tree.bulk(p, Tree.atLeast(p.clutch.list, 1), false, rng)
		T.truthy(ok, tostring(data))
		T.eq(#data.list, 2, "the two commons")
		T.eq(data.short, 1, "the rare one left")
		T.eq(data.why, "money")
		T.eq(p.clutch.list[1].id, e.id)
		-- the huts: the rest stay once they are full
		p.shells = 1e7
		local free = Tree.room(p)
		for _ = 1, free + 2 do
			egg(p, 1)
		end
		plan = Tree.bulkPlan(p, Tree.atLeast(p.clutch.list, 1), false)
		T.eq(plan.n, free)
		T.eq(plan.room, 3)
		ok, data = Tree.bulk(p, Tree.atLeast(p.clutch.list, 1), false, rng)
		T.truthy(ok, tostring(data))
		T.eq(#data.list, free)
		T.eq(data.room, 3)
		T.eq(data.why, "full")
		T.eq(Tree.room(p), 0)
		T.eq(select(2, Tree.bulk(p, Tree.atLeast(p.clutch.list, 1), false, rng)), "full", "every hut full: none")
		T.eq(#p.clutch.list, 3, "nothing paid, nothing gone")
	end)

	T.it("a bulk hatch of the bag's eggs costs nothing", function()
		local p = fresh()
		p.stats.taken = 5
		build(p, "nest")
		build(p, "nest")
		local rng = Util.newRng(5)
		Tree.bagAdd(p, 1)
		local b = Tree.bagAdd(p, 4) :: any
		Tree.bagAdd(p, 2)
		local before = p.shells
		local ok, data = Tree.bulk(p, Tree.atLeast(p.bag, 2), true, rng)
		T.truthy(ok, tostring(data))
		T.eq(#data.list, 2)
		T.eq(data.list[1].egg, b.id, "the epic first")
		T.eq(data.list[1].bag, true)
		T.eq(data.cost, 0)
		T.eq(p.shells, before, "free")
		T.eq(#p.bag, 1, "the common one stays")
		T.eq(Tree.bulkPlan(p, Tree.atLeast(p.bag, 1), true).n, 1)
	end)

	T.it("Auto Hatch: with the pass, a new lot's eggs at the floor or rarer hatch by themselves", function()
		-- (the request of 2026-11-22: "make an auto buy gamepass, which lets you auto buy eggs that appear above a
		-- rarity of your choosing")
		local p = fresh()
		T.eq(p.settings.auto, 0, "off on a new island")
		T.eq(select(2, Tree.setAuto(p, 3)), "locked", "the pass first")
		T.truthy(Tree.setAuto(p, 0), "off is always allowed")
		p.passes.AutoHatch = true
		T.truthy(Tree.setAuto(p, 3))
		T.eq(p.settings.auto, 3)
		T.eq(select(2, Tree.setAuto(p, Traits.RMAX + 1)), "bad_payload")
		T.eq(select(2, Tree.setAuto(p, 1.5)), "bad_payload")
		local laid = { { id = 1, r = 1 }, { id = 2, r = 3 }, { id = 3, r = 5 }, { id = 4, r = 2 } }
		T.deepEq(Tree.autoIds(p, laid :: any), { 3, 2 }, "the rare and the legendary, the rarest first")
		p.passes.AutoHatch = nil
		T.eq(#Tree.autoIds(p, laid :: any), 0, "the pass gone: none")
		p.passes.AutoHatch = true
		p.settings.auto = 0
		T.eq(#Tree.autoIds(p, laid :: any), 0, "off: none")
		-- an old save comes in with it off
		local raw = Schema.default(0, 3) :: any
		raw.settings.auto = nil
		raw.v = 26
		local back = Schema.reconcile(Schema.migrate(raw), 0, 3)
		T.eq(back.settings.auto, 0)
		raw = Schema.default(0, 3) :: any
		raw.settings.auto = 4
		T.eq(Schema.reconcile(raw, 0, 3).settings.auto, 4, "kept")
		raw.settings.auto = 99
		T.eq(Schema.reconcile(raw, 0, 3).settings.auto, Traits.RMAX, "clamped")
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

	T.it("a driftling in a hut takes a job, the best with room (its jobs a building: a patch's 2); one with no hut doesn't work", function()
		local p = fresh()
		local patch = build(p, "patch")
		build(p, "nest")
		build(p, "nest")
		local list = {}
		for _ = 1, 3 do
			table.insert(list, pal(p, "mossbun"))
		end
		local at = 0
		for _, x in list do
			if x.work == patch then
				at += 1
			end
		end
		local room = Buildings.byId.patch.jobs
		T.eq(at, room, "two at the patch")
		local resting = 0
		for _, x in list do
			resting += if x.work == 0 then 1 else 0
		end
		T.eq(resting, #list - room, "the third rests: no other workplace")
		local camp = build(p, "lumber")
		Tree.fillJobs(p)
		local atCamp = 0
		for _, x in list do
			atCamp += if x.work == camp then 1 else 0
		end
		T.eq(atCamp, #list - room, "the patch full: the lumber camp")
		for _, x in list do
			if x.work == camp then
				x.work = 0
			end
		end
		build(p, "patch")
		Tree.fillJobs(p)
		for _, x in list do
			T.truthy(x.home ~= 0 and (x.work == patch or x.work == camp), "all three at work: as good a place, the first built")
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
		-- a driftling the player put to work by hand keeps that place through a move (its work was cleared while the
		-- pin stayed, which reads as resting by hand: it rested for good; the server review of 2026-11-19)
		local stall = 0
		for _, q in p.plot.placed do
			if q.id == "stall" then
				stall = q.uid
			end
		end
		T.truthy(Island.setHelp(p, c.id, stall))
		T.truthy(c.pin == true and c.work == stall)
		local room = build(p, "nest")
		T.truthy(Tree.house(p, c.id, room, 0))
		T.truthy(c.home == room and c.pin == true and c.work == stall, "moved, still at its picked place")
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
