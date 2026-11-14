-- The Hatchery (Logic/Breed; GAME_DESIGN 6.1): what a pair hatches, what it inherits, laying an egg (its rules and
-- refusals), the turns to a hatching into a hut with room, and a Hatchery kept while it holds an egg.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Breed = require("../../build/luautest/shared/Logic/Breed")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Util = require("../../build/luautest/shared/Logic/Util")

local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood = 1e6, 1e6
	p.tier = 3
	return p
end

local function put(p: any, id: string): number
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = 0, z = 0, rot = 0, lvl = 1 })
	return uid
end

local function friend(p: any, sp: string, muts: { string }?): number
	local id = p.nextId
	p.nextId += 1
	table.insert(p.pals, { id = id, sp = sp, home = 0, work = 0, muts = muts or {} })
	return id
end

return function()
	T.it("what hatches: a pair of one kind its kind; else the kind nearest their average power; a legend from legends only, a mythic or celestial one from its own", function()
		T.eq(Breed.child("clawdle", "clawdle"), "clawdle")
		T.eq(Breed.child("solwyrm", "solwyrm"), "solwyrm")
		local legends: { string } = {}
		for _, d in Creatures.list do
			if d.rarity == 5 then
				table.insert(legends, d.id)
			end
		end
		T.truthy(#legends >= 2)
		for _, a in Creatures.list do
			for _, b in Creatures.list do
				local c = Breed.child(a.id, b.id)
				local d = Creatures.byId[c]
				T.truthy(d ~= nil, a.id .. " x " .. b.id)
				-- (legendary and up: no rarer than the commoner parent)
				local top = math.max(4, math.min(a.rarity, b.rarity))
				if a.id ~= b.id then
					T.truthy(d.rarity <= top, a.id .. " x " .. b.id .. ": no rarer than the commoner parent")
					-- nearest the average
					local avg = (a.power + b.power) / 2
					for _, o in Creatures.list do
						if o.rarity <= top then
							T.truthy(math.abs(d.power - avg) <= math.abs(o.power - avg) + 1e-9, c .. " nearest for " .. a.id .. " x " .. b.id)
						end
					end
				end
				T.eq(c, Breed.child(b.id, a.id), "either way round")
			end
		end
		T.eq(Creatures.byId[Breed.child(legends[1], legends[2])].rarity, 5, "two legends: a legend")
		local rare: { [number]: { string } } = { [6] = {}, [7] = {} }
		for _, d in Creatures.list do
			if rare[d.rarity] then
				table.insert(rare[d.rarity], d.id)
			end
		end
		T.truthy(Creatures.byId[Breed.child(rare[6][1], rare[6][2])].rarity >= 5, "two mythic ones: a legend or better")
		T.eq(Creatures.byId[Breed.child(rare[7][1], rare[7][2])].rarity, 7, "two celestial ones: a celestial one")
	end)
	T.it("with the island's tier: only the kinds of land open there hatch, or the parents' own", function()
		for _, a in Creatures.list do
			for _, b in Creatures.list do
				local c = Breed.child(a.id, b.id, 3)
				local kind = Islets.list[Creatures.byId[c].islet]
				T.truthy(kind.tier <= 3 or c == a.id or c == b.id, a.id .. " x " .. b.id .. " at tier 3: " .. c)
			end
		end
	end)
	T.it("inheriting: one both carry always passes on (the better tier, sometimes one better); one only a parent carries about half the time", function()
		local rng = Util.newRng(8)
		local both, up, single, new = 0, 0, 0, 0
		local N = 3000
		for _ = 1, N do
			local m = Breed.inherit({ "fierce2", "lazy" }, { "fierce1", "angler3" }, rng)
			T.truthy(#m <= Traits.MAX)
			T.deepEq(Traits.clean(m), m, "a clean list")
			local fam: { [string]: string } = {}
			for _, id in m do
				fam[Traits.byId[id].family] = id
			end
			T.truthy(fam.fierce == "fierce2" or fam.fierce == "fierce3", "the shared family: the better tier or one better")
			both += 1
			if fam.fierce == "fierce3" then
				up += 1
			end
			if fam.busy == "lazy" then
				single += 1
			end
			for f in fam do
				if f ~= "fierce" and f ~= "busy" and f ~= "angler" then
					new += 1
				end
			end
		end
		T.eq(both, N)
		T.near(up / N, Tuning.BreedTierUp, 0.04, "a tier up now and then")
		T.near(single / N, Tuning.BreedKeep, 0.04, "a single parent's about half the time")
		T.near(new / N, Tuning.BreedNew, 0.03, "a new one of its own now and then")
		-- a shared flaw: the flaw, or its family's first tier
		for _ = 1, 200 do
			local m = Breed.inherit({ "frail" }, { "frail" }, rng)
			T.truthy(m[1] == "frail" or m[1] == "sturdy1" or Traits.byId[m[1]].tier >= 1, "frail or Sturdy")
			T.truthy(table.find(m, "frail") or table.find(m, "sturdy1"), "the family passes on")
		end
		-- the best four of many
		for _ = 1, 200 do
			local m = Breed.inherit({ "fierce4", "swift4", "sturdy4", "armor4" }, { "bright4", "busy4", "grower4", "angler4" }, rng)
			T.eq(#m <= 4, true)
		end
		T.deepEq(Breed.inherit(nil, nil, Util.newRng(1)) ~= nil, true)
	end)
	T.it("laying an egg: a Hatchery with none, two of the island's own, the feast paid", function()
		local p = fresh()
		local rng = Util.newRng(3)
		local a = friend(p, "clawdle", { "fierce2" })
		local b = friend(p, "gullfin", { "fierce2", "angler1" })
		T.eq(select(2, Breed.start(p, 999, a, b, rng)), "not_found", "no Hatchery")
		local farm = put(p, "patch")
		T.eq(select(2, Breed.start(p, farm, a, b, rng)), "not_found", "a farm is no Hatchery")
		local h = put(p, "hatchery")
		T.eq(select(2, Breed.start(p, h, a, a, rng)), "bad_payload", "the same one twice")
		T.eq(select(2, Breed.start(p, h, a, 777, rng)), "not_found", "a driftling not here")
		local sp = Breed.child("clawdle", "gullfin")
		local feast, turns = Breed.cost(sp)
		p.shells = feast - 1
		T.eq(select(2, Breed.start(p, h, a, b, rng)), "money")
		p.shells = feast + 5
		local ok, egg = Breed.start(p, h, a, b, rng)
		T.truthy(ok)
		T.eq(p.shells, 5, "the feast paid in shells")
		T.eq(egg.sp, sp)
		T.eq(egg.left, turns)
		T.truthy(table.find(egg.muts, "fierce2") or table.find(egg.muts, "fierce3"), "the shared mutation passes on")
		T.eq(#p.eggs, 1)
		T.eq(select(2, Breed.start(p, h, a, b, rng)), "egg", "one egg a Hatchery")
		-- a rarer egg takes a bigger feast and more turns
		T.truthy(Tuning.BreedShells[5] > Tuning.BreedShells[1] and Tuning.BreedTurns[5] > Tuning.BreedTurns[1])
		-- not cleared away while it holds the egg
		local i = #p.plot.placed
		T.eq(select(2, Plot.store(p, i)), "egg")
	end)
	T.it("hatching: the turns count down; it hatches into a hut with room, or waits with no hut (in the Index)", function()
		local p = fresh()
		local rng = Util.newRng(4)
		local a = friend(p, "mossbun")
		local b = friend(p, "mossbun")
		local h = put(p, "hatchery")
		local before = #p.pals
		local _, egg = Breed.start(p, h, a, b, rng)
		T.eq(egg.sp, "mossbun")
		for _ = 1, egg.left - 1 do
			T.eq(#Breed.turn(p), 0)
		end
		p.seen.mossbun = 2
		local born, newKinds = Breed.turn(p)
		T.eq(#born, 1, "it hatches")
		T.eq(born[1].sp, "mossbun")
		T.eq(#newKinds, 0, "a kind had before: nothing new")
		T.eq(born[1].home, 0, "no hut on this island: it waits")
		T.eq(#p.pals, before + 1)
		T.eq(p.seen.mossbun, 2)
		T.eq(p.stats.hatched, 1)
		T.eq(#p.eggs, 0)
		T.truthy(born[1].id ~= a and born[1].id ~= b and born[1].id < p.nextId, "an id of its own")
		-- the Hatchery free again: cleared away now
		local i = 0
		for k, q in p.plot.placed do
			if q.uid == h then
				i = k
			end
		end
		T.truthy(Plot.store(p, i))
	end)
	T.it("a Hatchery's hatchling of a kind never had is named as new (the notice's \"New!\")", function()
		local p = fresh()
		local rng = Util.newRng(5)
		local a = friend(p, "clawdle")
		local b = friend(p, "gullfin")
		local h = put(p, "hatchery")
		local _, egg = Breed.start(p, h, a, b, rng)
		p.seen[egg.sp] = 1 -- (met in the Index, never had)
		egg.left = 1
		local born, newKinds = Breed.turn(p)
		T.eq(#born, 1)
		T.eq(#newKinds, 1, "one new kind")
		T.eq(newKinds[1], egg.sp)
		T.eq(p.seen[egg.sp], 2, "had now")
	end)
	T.it("the save: eggs at Hatcheries still standing, one each, kinds that exist, clean mutations, turns in range", function()
		local p = fresh()
		local h = put(p, "hatchery")
		local raw: any = table.clone(p)
		raw.eggs = {
			{ uid = h, a = 1, b = 2, sp = "glacior", muts = { "swift3", "nope" }, left = 99 },
			{ uid = h, a = 1, b = 2, sp = "pebblit", muts = {}, left = 1 }, -- a second at the same Hatchery
			{ uid = 4040, a = 1, b = 2, sp = "pebblit", muts = {}, left = 1 }, -- no Hatchery there
			{ uid = h, sp = "dragon" },
			"x",
		}
		local q = Schema.reconcile(raw, 0, 1)
		T.eq(#q.eggs, 1)
		T.eq(q.eggs[1].sp, "glacior")
		T.deepEq(q.eggs[1].muts, { "swift3" })
		T.truthy(q.eggs[1].left <= Tuning.BreedTurns[5])
		T.deepEq(Schema.reconcile({ eggs = "x" }, 0, 1).eggs, {})
	end)
end
