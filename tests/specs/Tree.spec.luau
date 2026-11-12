-- The Tree of Life and its pen (Logic/Tree; GAME_DESIGN 6): every island has a tree; it grows a driftling every few
-- seconds into the pen, which never fills (past PenKeep the least useful is sold); luck makes the rarer ones
-- likelier, speed makes it quicker; the pen sends its best driftlings into the huts with room (the comfiest first) and
-- they take a job of their knack; the player moves them between huts and the pen (a full hut only in a swap), sells
-- them, and upgrades the tree.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Tree = require("../../build/luautest/shared/Logic/Tree")
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
	p.shells, p.wood, p.food = 1e7, 1e6, 1000
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
	local x = Tree.add(p, sp, muts or {})
	return x
end

return function()
	T.it("a new island has its Tree of Life on the grass, off the piece count", function()
		local p = Schema.default(0, 1)
		local q = Tree.piece(p)
		T.truthy(q ~= nil, "the tree")
		if q then
			T.truthy(Plot.fits(p.tier, {}, q.id, q.x, q.z, q.rot), "on the grass, off the plaza and path")
		end
		T.eq(select(1, Plot.used(p, "flowers")), 0, "the tree doesn't count")
		T.deepEq(p.tree, { luck = 1, speed = 1, t = 0 })
		T.truthy(Buildings.byId.tree.w >= 6 and Buildings.byId.tree.d >= 6, "a grand tree")
	end)

	T.it("the tree is moved like a piece but never bought, cleared away or replaced", function()
		local p = fresh()
		local q = Tree.piece(p) :: any
		local i = table.find(p.plot.placed, q) :: number
		T.eq(select(2, Plot.store(p, i)), "fixed")
		T.eq(select(2, Plot.place(p, "tree", 6, 4, 0)), "bad_payload")
		T.eq(#Plot.replacements(q, 6), 0)
		T.eq(select(2, Plot.replace(p, i, "nest")), "bad_payload")
		local x, z, rot = Plot.spot(p.tier, p.plot.placed, "tree", 6, 4, 0)
		T.truthy(x ~= nil)
		local placed = table.clone(p.plot.placed)
		table.remove(placed, i)
		local mx, mz, mr = Plot.spot(p.tier, placed, "tree", q.x + 3, q.z + 2, 0)
		if mx and mz and mr and (mx ~= q.x or mz ~= q.z) then
			T.truthy(Plot.move(p, i, mx, mz, mr), "moved")
		end
	end)

	T.it("it grows a driftling every TreeSecs into the pen, which never fills; past PenKeep the least useful is sold", function()
		local p = fresh()
		local rng = Util.newRng(3)
		local secs = Tree.secs(p)
		T.eq(secs, Tuning.TreeSecs[1])
		local grown = Tree.step(p, secs - 0.01, rng)
		T.eq(#grown, 0, "not yet")
		grown = Tree.step(p, 0.02, rng)
		T.eq(#grown, 1, "one")
		local x = grown[1]
		T.eq(x.home, 0, "in the pen")
		T.eq(x.work, 0)
		T.eq(p.seen[x.sp], 2, "in the Index")
		T.eq(p.stats.grown, 1)
		-- it never stops
		for _ = 1, 100 do
			Tree.step(p, secs, rng)
		end
		T.eq(Tree.inPen(p), 101, "no room limit")
		T.truthy(p.tree.t < secs)
		-- past PenKeep: the least useful the player didn't keep there go, sold
		local kept = p.pals[1]
		kept.held = 1
		local legend = { id = p.nextId, sp = "solwyrm", home = 0, work = 0, muts = {} }
		p.nextId += 1
		table.insert(p.pals, legend)
		while Tree.inPen(p) < Tuning.PenKeep do
			Tree.step(p, secs, rng)
		end
		local shells, sold = p.shells, p.stats.sold
		local _, _, got = Tree.step(p, secs * 3, rng)
		T.eq(Tree.inPen(p), Tuning.PenKeep, "back to PenKeep")
		T.truthy(got > 0 and p.shells == shells + got and p.stats.sold == sold + 3, "three sold for shells")
		T.truthy(table.find(p.pals, kept) ~= nil, "the kept one stays")
		T.truthy(table.find(p.pals, legend) ~= nil, "the best stays")
	end)

	T.it("what grows: the kinds open at the island's tier, rarer ones less often, and luck makes them likelier", function()
		for tier = 1, 6 do
			local p = fresh()
			p.tier = tier
			local open: { [string]: boolean } = {}
			for _, k in Islets.list do
				if k.tier <= tier then
					for _, sp in k.wild do
						open[sp] = true
					end
				end
			end
			local rng = Util.newRng(tier * 31)
			for _ = 1, 300 do
				local sp, muts = Tree.roll(p, rng)
				T.truthy(open[sp], sp .. " open at tier " .. tier)
				T.truthy(#muts <= Traits.MAX)
			end
		end
		-- odds add to one; a rarity the open kinds lack (a legend at tier 1) gives its share to the next commoner
		local p = fresh()
		local odds = Tree.odds(p)
		local sum = 0
		for _, v in odds do
			sum += v
		end
		T.near(sum, 1, 1e-9)
		T.eq(odds[5], 0, "no legends at tier 1")
		T.truthy(odds[1] > odds[2] and odds[2] > odds[3] and odds[3] > odds[4], "rarer is rarer")
		local base = odds[4]
		p.tree.luck = 5
		T.truthy(Tree.odds(p)[4] > base, "luck makes epics likelier")
		T.truthy(Tree.odds(p, 10)[4] > Tree.odds(p)[4], "the preview of a higher level")
		-- many rolls follow the odds
		p.tree.luck = 1
		p.tier = 6
		local counts = { 0, 0, 0, 0, 0 }
		local rng = Util.newRng(99)
		local n = 20000
		for _ = 1, n do
			local sp = Tree.roll(p, rng)
			local r = Creatures.byId[sp].rarity
			counts[r] += 1
		end
		local o = Tree.odds(p)
		for r = 1, 5 do
			T.near(counts[r] / n, o[r], 0.015, "rarity " .. r)
		end
	end)

	T.it("speed makes it quicker, the huts' Leafy driftlings too (up to HutTree)", function()
		local p = fresh()
		p.tree.speed = 4
		T.eq(Tree.secs(p), Tuning.TreeSecs[4])
		build(p, "nest")
		build(p, "pier") -- (somewhere for a fishing driftling to work)
		local x = pal(p, "breezle", { "swift4" }) -- Tailwind: tree +6%, Evergreen +22%
		Tree.settle(p)
		T.truthy(x.home ~= 0, "in the hut")
		T.near(Tree.secs(p), Tuning.TreeSecs[4] / (1 + 0.06 + 0.22), 1e-9)
		-- capped
		for _ = 1, 10 do
			local hut = build(p, "nest")
			local y = pal(p, "breezle", { "swift4" })
			y.home = hut
		end
		T.near(Tree.secs(p), Tuning.TreeSecs[4] / (1 + Tuning.HutTree), 1e-9)
	end)

	T.it("the pen sends its best into the huts with room (the comfiest first); held ones stay", function()
		local p = fresh()
		p.tier = 2
		local a = pal(p, "pebblit") -- common
		local b = pal(p, "shellback") -- rare
		local c = pal(p, "gullfin") -- uncommon
		build(p, "lumber") -- (somewhere to work for each)
		build(p, "pier")
		build(p, "patch")
		local nest = build(p, "nest") -- room 2
		local moved = Tree.settle(p)
		T.eq(#moved, 2)
		T.eq(b.home, nest, "the rare first")
		T.eq(c.home, nest, "then the uncommon")
		T.eq(a.home, 0, "the common waits")
		local burrow = build(p, "burrow") -- comfort 5%
		local d = pal(p, "sunsprite") -- epic
		Tree.settle(p)
		T.eq(d.home, burrow, "the comfiest hut first")
		T.eq(a.home, burrow, "and the common fills in")
		-- held: the player put it in the pen
		local e = pal(p, "conchy")
		e.held = 1
		Tree.settle(p)
		T.eq(e.home, 0, "a held one stays in the pen")
	end)

	T.it("a driftling in a hut takes a job of its knack (HelpMax a building); the pen's don't work or eat", function()
		local p = fresh()
		local patch = build(p, "patch")
		build(p, "nest")
		build(p, "nest")
		local list = {}
		for _ = 1, 3 do
			table.insert(list, pal(p, "mossbun")) -- farm
		end
		Tree.settle(p)
		local at = 0
		for _, x in list do
			if x.work == patch then
				at += 1
			end
		end
		T.eq(at, Tuning.HelpMax, "two at the patch")
		local waiting = 0
		for _, x in list do
			if x.home == 0 then
				waiting += 1
			end
		end
		T.eq(waiting, 1, "the third waits in the pen: nowhere to work")
		-- a second patch: it moves in and works there
		local patch2 = build(p, "patch")
		Tree.settle(p)
		for _, x in list do
			T.truthy(x.home ~= 0 and (x.work == patch or x.work == patch2), "all three at work")
		end
		-- the pen's: no work, no food
		local q = pal(p, "frondle")
		q.held = 1
		local before = Island.rates(p).eaten
		local n = #p.pals
		T.eq(Island.rates(p).eaten, before)
		T.eq(select(1, Island.setHelp(p, q.id, patch)), false, "the pen's don't work")
		T.eq(#p.pals, n)
	end)

	T.it("rarer ones work faster (RarityWork)", function()
		local p = fresh()
		build(p, "nest")
		build(p, "lumber")
		build(p, "patch")
		local common = pal(p, "pebblit")
		local legend = pal(p, "solwyrm")
		Tree.settle(p)
		local wc = Island.palBoost(p, common)
		local wl = Island.palBoost(p, legend)
		T.near(wc, Tuning.PalWork * Tuning.RarityWork[1] * (1 + Island.palWork(p, common)), 1e-9)
		T.near(wl, Tuning.PalWork * Tuning.RarityWork[5] * (1 + Island.palWork(p, legend)), 1e-9)
		T.truthy(wl > wc * 3)
	end)

	T.it("moving: to a hut or the pen (always room there); a full hut only in a swap; refusals", function()
		local p = fresh()
		build(p, "lumber")
		build(p, "pier")
		build(p, "stall")
		local nest = build(p, "nest")
		local a = pal(p, "pebblit")
		local b = pal(p, "clawdle")
		local c = pal(p, "gullfin")
		Tree.settle(p)
		T.eq(c.home, nest)
		T.eq(a.home == nest or b.home == nest, true)
		local out = if a.home == 0 then a else b
		local inn = if a.home == 0 then b else a
		T.eq(select(2, Tree.house(p, out.id, nest, 0)), "full", "a full hut")
		T.truthy(Tree.house(p, out.id, nest, inn.id), "a swap")
		T.eq(out.home, nest)
		T.eq(inn.home, 0)
		T.eq(inn.held, 1, "swapped out: stays in the pen")
		T.eq(select(2, Tree.house(p, inn.id, nest, 99999)), "bad_payload", "a swap that doesn't live there")
		T.eq(select(2, Tree.house(p, 99999, nest, 0)), "not_found")
		T.eq(select(2, Tree.house(p, out.id, (Tree.piece(p) :: any).uid, 0)), "bad_payload", "not a hut")
		-- to the pen: held; the hut's room fills from the pen's best that isn't held
		local d = pal(p, "conchy")
		T.truthy(Tree.house(p, c.id, 0, 0))
		T.eq(c.home, 0)
		T.eq(c.held, 1)
		T.eq(c.work, 0)
		T.eq(d.home, nest, "the room it left filled from the pen")
		-- back into a hut: no longer held
		local burrow = build(p, "nest")
		T.truthy(Tree.house(p, c.id, burrow, 0))
		T.eq(c.held, nil)
		-- a crowded pen still takes one
		for _ = 1, 30 do
			local x = pal(p, "pebblit")
			x.held = 1
		end
		T.truthy(Tree.house(p, c.id, 0, 0), "the pen has room")
		T.eq(c.home, 0)
	end)

	T.it("selling: shells by rarity and mutations; the pen's commons at once; a hut's place refilled", function()
		local p = fresh()
		local x = pal(p, "pebblit", {})
		T.eq(Tree.price(x), Tuning.SellPrice[1])
		local y = pal(p, "pebblit", { "busy2", "fierce1" }) -- tiers 3; Shiny +30% sell
		T.eq(Tree.price(y), math.floor(Tuning.SellPrice[1] * (1 + Tuning.SellTier * 3) * 1.3 + 0.5))
		local z = pal(p, "solwyrm", {})
		T.truthy(Tree.price(z) > Tree.price(y) * 50, "a legend is worth far more")
		local shells = p.shells
		local ok, data = Tree.sell(p, x.id)
		T.truthy(ok)
		T.eq(data.shells, Tuning.SellPrice[1])
		T.eq(p.shells, shells + Tuning.SellPrice[1])
		T.eq(p.stats.sold, 1)
		T.eq(select(2, Tree.sell(p, x.id)), "not_found")
		-- the pen's commons
		for _ = 1, 3 do
			pal(p, "clawdle")
		end
		local ok2, d2 = Tree.sellPen(p, 1)
		T.truthy(ok2)
		T.eq(d2.sold, 4, "every common in the pen (y too)")
		T.truthy(z.home == 0 and table.find(p.pals, z) ~= nil, "not the legend")
		T.eq(select(2, Tree.sellPen(p, 1)), "not_found", "none left")
		-- a hut's driftling sold: the pen's best moves in
		build(p, "pier")
		build(p, "patch")
		build(p, "stall")
		local nest = build(p, "nest")
		local a = pal(p, "gullfin")
		Tree.settle(p)
		T.eq(a.home, nest)
		T.eq(z.home, nest)
		local b = pal(p, "conchy")
		T.truthy(Tree.sell(p, a.id))
		T.eq(b.home, nest, "moved in")
	end)

	T.it("upgrades: luck and speed a level each, priced; max at the top", function()
		local p = fresh()
		for what, list in { luck = Tuning.TreeLuckCost, speed = Tuning.TreeSpeedCost } do
			for lv = 2, #list do
				local shells, wood = p.shells, p.wood
				local ok, data = Tree.upgrade(p, what)
				T.truthy(ok, what .. " " .. lv)
				T.eq(data.level, lv)
				T.eq(p.shells, shells - list[lv].shells)
				T.eq(p.wood, wood - list[lv].wood)
			end
			T.eq(select(2, Tree.upgrade(p, what)), "max")
			T.eq(Tree.upgradeCost(p, what), nil)
		end
		local q = Schema.default(0, 2)
		q.shells = 0
		T.eq(select(2, Tree.upgrade(q, "luck")), "money")
		q.shells = 1e6
		q.wood = 0
		T.eq(select(2, Tree.upgrade(q, "speed")), "wood")
		T.eq(select(2, Tree.upgrade(q, "size")), "bad_payload")
		-- more luck: mutations roll as a rarer one
		T.truthy(Tuning.TreeMutLuck >= 1)
	end)

	T.it("a hut cleared away or replaced smaller sends its driftlings back to the pen", function()
		local p = fresh()
		p.tier = 2
		local burrow = build(p, "burrow") -- room 4
		build(p, "lumber")
		build(p, "lumber")
		local list = {}
		for _ = 1, 4 do
			table.insert(list, pal(p, "pebblit"))
		end
		Tree.settle(p)
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
			T.eq(x.home, 0, "all in the pen")
			T.eq(x.work, 0)
		end
	end)

	T.it("an older island built full makes room for its tree", function()
		local p = Schema.default(0, 5)
		-- take the tree away and fill the grass with flower beds
		local ti = table.find(p.plot.placed, Tree.piece(p)) :: number
		table.remove(p.plot.placed, ti)
		local placed = 0
		for z = -10, 24 do
			for x = -20, 20 do
				if Plot.fits(p.tier, p.plot.placed, "flowers", x, z, 0) then
					table.insert(p.plot.placed, { uid = p.nextId, id = "flowers", x = x, z = z, rot = 0, lvl = 1 })
					p.nextId += 1
					placed += 1
				end
			end
		end
		T.truthy(placed > 10)
		local shells = p.shells
		local q = Tree.plant(p)
		T.truthy(q ~= nil, "planted")
		T.truthy(p.shells > shells, "the cleared pieces' price back")
	end)
end
