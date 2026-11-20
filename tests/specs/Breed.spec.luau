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
	p.shells = 1e6
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
		local rare: { [number]: { string } } = { [6] = {}, [7] = {}, [8] = {}, [9] = {} }
		for _, d in Creatures.list do
			if rare[d.rarity] then
				table.insert(rare[d.rarity], d.id)
			end
		end
		T.truthy(Creatures.byId[Breed.child(rare[6][1], rare[6][2])].rarity >= 5, "two mythic ones: a legend or better")
		T.eq(Creatures.byId[Breed.child(rare[7][1], rare[7][2])].rarity, 7, "two celestial ones: a celestial one")
		-- (the two past Celestial, 2026-11-20: never rarer than the commoner parent)
		for _, a in rare[8] do
			for _, b in rare[9] do
				local c = Creatures.byId[Breed.child(a, b)]
				T.truthy(c.rarity <= 8, a .. " x " .. b .. ": no rarer than the ancient one")
			end
		end
		T.truthy(#rare[8] >= 4 and #rare[9] >= 4, "four or more of each")
		local eternal = Creatures.byId[Breed.child(rare[9][1], rare[9][2])].rarity
		T.truthy(eternal >= 5 and eternal <= 9, "two eternal ones: a legend or better")
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
	T.it("inheriting (2026-11-19): decided, the best tiers of both parents, a shared family a tier up, at most four", function()
		-- (the request: "In hatchery, show the resultant mutation combination the pet will have. Always take the highest
		-- tier mutations to combine with each other if possible")
		local m = Breed.inherit({ "fierce2", "lazy" }, { "fierce1", "grower3" })
		T.deepEq(m, { "fierce3", "grower3" }, "the shared family one above the better (2 -> 3), the other parent's own kept, a lone flaw left behind")
		T.deepEq(Breed.inherit({ "fierce2", "lazy" }, { "fierce1", "grower3" }), m, "the same every time")
		T.deepEq(Breed.inherit({ "frail" }, { "frail" }), { "sturdy1" }, "a shared flaw: its family's first tier")
		T.deepEq(Breed.inherit({ "busy4" }, { "busy4" }), { "busy4" }, "never past tier 4")
		T.deepEq(Breed.inherit({ "golden5" }, { "golden5" }), { "golden5" }, "a wondrous one stays itself")
		-- (the fabled tier, 2026-11-20: a family of one tier too, passed on before anything else)
		T.deepEq(Breed.inherit({ "crown6" }, { "crown6" }), { "crown6" }, "a fabled one stays itself")
		T.deepEq(Breed.inherit({ "busy4", "golden5", "fierce4", "armor4" }, { "crown6" }), { "crown6", "golden5", "armor4", "busy4" }, "the fabled one first, then the wondrous one, then the fours")
		-- the highest tiers first, at most four
		local best = Breed.inherit({ "fierce4", "sturdy1", "armor2", "bright1" }, { "golden5", "busy3", "grower1", "chopper2" })
		T.eq(#best, Traits.MAX)
		T.deepEq(best, { "golden5", "fierce4", "busy3", "armor2" }, "the wondrous one, then 4, 3 and the better 2")
		local tiers: { number } = {}
		for _, id in best do
			table.insert(tiers, Traits.byId[id].tier)
		end
		for k = 2, #tiers do
			T.truthy(tiers[k] <= tiers[k - 1], "highest first")
		end
		T.deepEq(Breed.inherit(nil, nil), {})
		T.deepEq(Traits.clean(best), best, "a clean list")
	end)
	T.it("the preview: what a pair makes, its mutations, price and turns; the huts' Hatchery shares shorten it", function()
		local p = fresh()
		local a = friend(p, "clawdle", { "fierce2" })
		local b = friend(p, "gullfin", { "fierce2", "grower1" })
		local pv = Breed.preview(p, a, b) :: any
		T.truthy(pv ~= nil)
		T.eq(pv.sp, Breed.child("clawdle", "gullfin", p.tier))
		T.deepEq(pv.muts, { "fierce3", "grower1" })
		local price, turns = Breed.cost(pv.sp)
		T.eq(pv.price, price)
		T.eq(pv.turns, turns, "nobody in a hut: the plain turns")
		T.eq(Breed.preview(p, a, a), nil, "not one with itself")
		T.eq(Breed.preview(p, a, 777), nil)
		-- a driftling in a hut with a Hatchery share (2026-11-19: "mutations that decrease hatchery time, with
		-- diminishing returns if stacked")
		local hut = put(p, "nest")
		for _, x in p.pals do
			x.home = hut
			x.muts = { "grower4" } -- Egg Keeper: 30% sooner
		end
		local _, t2 = Breed.cost(pv.sp, p)
		T.eq(t2, math.max(1, math.ceil(turns * 0.7 * 0.7 - 1e-9)), "two of them: 30% off, then 30% of what is left")
		T.truthy(t2 < turns)
	end)
	T.it("laying an egg: a Hatchery with none, two of the island's own, the feast paid", function()
		local p = fresh()
		local a = friend(p, "clawdle", { "fierce2" })
		local b = friend(p, "gullfin", { "fierce2", "grower1" })
		T.eq(select(2, Breed.start(p, 999, a, b)), "not_found", "no Hatchery")
		local farm = put(p, "patch")
		T.eq(select(2, Breed.start(p, farm, a, b)), "not_found", "a farm is no Hatchery")
		local h = put(p, "hatchery")
		T.eq(select(2, Breed.start(p, h, a, a)), "bad_payload", "the same one twice")
		T.eq(select(2, Breed.start(p, h, a, 777)), "not_found", "a driftling not here")
		local sp = Breed.child("clawdle", "gullfin", p.tier)
		local feast, turns = Breed.cost(sp, p)
		p.shells = feast - 1
		T.eq(select(2, Breed.start(p, h, a, b)), "money")
		p.shells = feast + 5
		local ok, egg = Breed.start(p, h, a, b)
		T.truthy(ok)
		T.eq(p.shells, 5, "the feast paid in shells")
		T.eq(egg.sp, sp)
		T.eq(egg.left, turns)
		T.deepEq(egg.muts, { "fierce3", "grower1" }, "what the preview showed: the shared one a tier up, the other kept")
		T.eq(#p.eggs, 1)
		T.eq(select(2, Breed.start(p, h, a, b)), "egg", "one egg a Hatchery")
		-- a rarer egg takes a bigger feast and more turns
		T.truthy(Tuning.BreedShells[5] > Tuning.BreedShells[1] and Tuning.BreedTurns[5] > Tuning.BreedTurns[1])
		-- not cleared away while it holds the egg
		local i = #p.plot.placed
		T.eq(select(2, Plot.store(p, i)), "egg")
	end)
	T.it("hatching: the turns count down; it hatches into a hut with room, or waits with no hut (in the Index)", function()
		local p = fresh()

		local a = friend(p, "mossbun")
		local b = friend(p, "mossbun")
		local h = put(p, "hatchery")
		local before = #p.pals
		local _, egg = Breed.start(p, h, a, b)
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

		local a = friend(p, "clawdle")
		local b = friend(p, "gullfin")
		local h = put(p, "hatchery")
		local _, egg = Breed.start(p, h, a, b)
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
		T.deepEq(q.eggs[1].muts, { "bright3" }, "a Leafy mutation is Lucky now")
		T.truthy(q.eggs[1].left <= Tuning.BreedTurns[5])
		T.deepEq(Schema.reconcile({ eggs = "x" }, 0, 1).eggs, {})
	end)
end
