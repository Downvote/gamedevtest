-- The save (Logic/Schema; docs/ARCHITECTURE.md 7.6): a new island, a played profile surviving a round trip, garbage,
-- the old saves (versions 1 to 4: the studios) loading into the island with the founder kept, and a save from before
-- the Tree of Life (version 9: the wild places and the fights) coming in with its driftlings in huts and the pen.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Island = require("../../build/luautest/shared/Logic/Island")
local Util = require("../../build/luautest/shared/Logic/Util")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- the pieces built (not the Tree of Life, every island's: Logic/Tree)
local function built(p: any): { any }
	local out = {}
	for _, q in p.plot.placed do
		if Buildings.byId[q.id] and Buildings.byId[q.id].kind ~= "tree" then
			table.insert(out, q)
		end
	end
	return out
end
local function treeCount(p: any): number
	local n = 0
	for _, q in p.plot.placed do
		if q.id == "tree" then
			n += 1
		end
	end
	return n
end

-- a JSON-like round trip (what a DataStore keeps): numbers, strings, booleans and tables only
local function roundTrip(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = roundTrip(x)
	end
	return out
end

-- a played island: buildings, a driftling at work in its hut, one kept in the pen, the tree's levels
local Street = require("../../build/luautest/shared/Data/Street")
local function place(p: any, id: string)
	local r = Street.plot(p.tier)
	for z = r.z0 + 1, r.z1 - 2 do
		for x = r.x0 + 1, r.x1 - 2 do
			if Plot.fits(p.tier, p.plot.placed, id, x, z, 0) then
				assert(Plot.place(p, id, x, z, 0))
				return
			end
		end
	end
	error("no room for " .. id)
end
local function played(): any
	local p = Schema.default(1000, 7)
	p.shells, p.wood = 1e5, 1e5
	place(p, "stall")
	place(p, "patch")
	place(p, "nest")
	place(p, "lumber")
	built(p)[2].lvl = 2 -- (a level from before upgrades were taken out: kept)
	Island.newDay(p)
	table.insert(p.pals, { id = p.nextId, sp = "pebblit", home = built(p)[3].uid, work = built(p)[4].uid, muts = { "sturdy2", "lazy" } })
	p.nextId += 1
	table.insert(p.pals, { id = p.nextId, sp = "clawdle", home = 0, work = 0, muts = {}, held = 1 })
	p.nextId += 1
	p.seen.pebblit = 2
	p.seen.clawdle = 2
	p.tree = { luck = 3, speed = 2, t = 4.5 }
	p.stats.best = 1
	return p
end

return function()
	T.it("a new island", function()
		local p = Schema.default(1000, 42)
		T.eq(p.v, Schema.VERSION)
		T.eq(p.shells, Tuning.StartShells)
		T.eq(p.tier, 1)
		T.eq(p.tut, 1)
		T.eq((p :: any).folk, nil, "no villagers")
		T.deepEq(Schema.default(1, 5).founder, Schema.default(1, 5).founder, "the same seed, the same founder")
		T.eq(#built(p), 0, "nothing built")
		T.eq(treeCount(p), 1, "its Tree of Life")
		T.deepEq(p.tree, { luck = 1, speed = 1, t = 0 })
		T.deepEq(Schema.default(1, 5).plot.placed, Schema.default(1, 5).plot.placed, "the same place every time")
	end)
	T.it("reconcile keeps a played profile as it is", function()
		local p = played()
		T.truthy(#built(p) == 4 and treeCount(p) == 1 and #p.pals == 2)
		T.truthy(p.pals[1].work ~= 0, "the driftling works")
		local back = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(back, p)
	end)
	T.it("reconcile turns garbage into a valid profile", function()
		for _, raw in { nil, 5, "x", {}, { v = 5, shells = 0 / 0, food = -5, tier = 99, folk = "no", pals = { { sp = "dragon" }, 7 }, plot = { placed = { { uid = 1, id = "castle", x = 0, z = 0, rot = 0 }, 3 } }, seen = { pebblit = 9, x = 1 }, tree = { luck = 99, speed = -4, t = 0 / 0 } } } :: { any } do
			local p = Schema.reconcile(raw, 1000, 3)
			T.truthy(p.shells == p.shells and p.shells >= 0, "shells")
			T.truthy(p.food >= 0)
			T.truthy(p.tier >= 1 and p.tier <= #Tuning.TierCost)
			T.eq(#built(p), 0)
			T.eq(treeCount(p), 1, "its tree")
			T.eq(#p.pals, 0)
			T.truthy(p.tree.luck >= 1 and p.tree.luck <= #Tuning.TreeLuckCost and p.tree.speed >= 1 and p.tree.speed <= #Tuning.TreeSpeedCost)
			T.truthy(p.tree.t == p.tree.t and p.tree.t >= 0)
			T.truthy(p.seen.x == nil)
		end
	end)
	T.it("jobs only where they make sense; ids unique; nextId past every id", function()
		local p = played()
		local raw = roundTrip(p)
		raw.pals[1].work = built(raw)[2].uid -- a wood driftling at the patch
		raw.pals[2].work = built(raw)[3].uid -- the pen's don't work
		table.insert(raw.pals, roundTrip(raw.pals[2])) -- the same id twice
		raw.nextId = 1
		local back = Schema.reconcile(raw, 1, 1)
		T.eq(back.pals[1].work, 0)
		T.eq(back.pals[2].work, 0)
		T.eq(#back.pals, 2, "the same id once")
		-- a hut that isn't there, or a hut over its room: the pen
		local raw2 = roundTrip(played())
		raw2.pals[1].home = 99999
		local b2 = Schema.reconcile(raw2, 1, 1)
		T.eq(b2.pals[1].home, built(b2)[3].uid, "a stray hut: the pen, then the pen sends it to the hut with room")
		local raw3 = roundTrip(played())
		for k = 1, 4 do
			table.insert(raw3.pals, { id = 900 + k, sp = "pebblit", home = built(raw3)[3].uid, work = 0, muts = {} })
		end
		local b3 = Schema.reconcile(raw3, 1, 1)
		local inHut = 0
		for _, x in b3.pals do
			if x.home ~= 0 then
				inHut += 1
			end
		end
		T.eq(inHut, Buildings.byId.nest.slots, "no more than the hut's room")
		local top = 0
		for _, q in back.plot.placed do
			top = math.max(top, q.uid)
		end
		for _, x in back.pals do
			top = math.max(top, x.id)
		end
		T.truthy(back.nextId > top)
	end)
	T.it("a version 4 save (the studio) loads as a new island: the founder and the settings kept", function()
		local old = {
			v = 4,
			coins = 123456,
			ideas = { { id = "action", mod = "plain" } },
			games = { { id = 1, title = "Old Game" } },
			live = { id = 1 },
			upgrades = { speed = 9, luck = 9 },
			team = { { id = 1, name = "Ada" } },
			office = 3,
			plot = { owned = { gnome = true }, placed = { { id = "gnome", x = 16, z = 18, rot = 0 } } },
			founder = { skin = 3, hair = 2, style = 4, shirt = 6 },
			settings = { pixel = "low" },
			tut = 0,
		}
		local p = Schema.reconcile(old, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.shells, Tuning.StartShells)
		T.eq(p.tier, 1)
		T.deepEq(p.founder, { skin = 3, hair = 2, style = 4, shirt = 6 })
		T.eq(p.settings.pixel, "low")
		T.eq(p.settings.music, "on", "music on by default")
		T.eq((Schema.reconcile({ v = Schema.VERSION, settings = { pixel = "low", music = "off" } }, 2000, 9) :: any).settings.music, "off", "music off kept")
		T.eq((Schema.reconcile({ v = Schema.VERSION, settings = { music = 7 } }, 2000, 9) :: any).settings.music, "on", "a bad value: on")
		T.eq(#built(p), 0)
		T.eq(treeCount(p), 1, "a new island's tree")
		T.eq(p.tut, 1, "the tips start over")
		T.eq(p.coins, nil)
		T.eq(p.games, nil)
	end)
	T.it("a version 5 save: its tip moves to the same tip (the old sailing tips: the hut's)", function()
		for old, new in { [0] = 0, [1] = 1, [2] = 2, [3] = 4, [4] = 4 } do
			local p = Schema.reconcile({ v = 5, shells = 10, tier = 1, tut = old }, 2000, 9) :: any
			T.eq(p.v, Schema.VERSION)
			T.eq(p.tut, new, "tip " .. old)
		end
	end)
	T.it("a version 8 save: the boat and the chart go; what was built stays; a tree comes up", function()
		local raw = roundTrip(played())
		raw.v = 8
		raw.tier = 2
		raw.sea = 77
		raw.boat = 4
		raw.chart = { 3, 7 }
		raw.islets = 2
		raw.tree = nil
		local keep = {}
		for _, q in raw.plot.placed do
			if q.id ~= "tree" then
				table.insert(keep, q)
			end
		end
		raw.plot.placed = keep
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.boat, nil, "no boat")
		T.eq(p.chart, nil, "no chart")
		T.eq(p.islets, nil)
		T.eq(p.sea, nil)
		T.eq(treeCount(p), 1)
		T.eq(#built(p), 4, "what was built stays")
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
	end)
	T.it("a version 9 save (the wild places and the fights): they go; the yard's price back; huts then the pen; the tips and quests", function()
		local p0 = played()
		local raw = roundTrip(p0)
		raw.v = 9
		raw.tree = nil
		raw.cap = { lvl = 9, xp = 3 }
		raw.pouch = 3
		raw.islets = 2
		raw.sea = 55
		raw.wilds = 1
		raw.tut = 6
		raw.quest = 14
		raw.stats.befriended = 7
		raw.stats.battles = 40
		raw.stats.skills = 3
		raw.stats.grown = nil
		raw.stats.sold = nil
		raw.stats.best = nil
		local keep = {}
		for _, q in raw.plot.placed do
			if q.id ~= "tree" then
				table.insert(keep, q)
			end
		end
		raw.plot.placed = keep
		-- its wild places, a yard, villagers and driftlings with levels, the nest's (room 2) three driftlings
		local nest = built(p0)[3].uid
		table.insert(raw.plot.placed, { uid = 7001, id = "wild_tidepool", x = 6, z = 0, rot = 0, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 7002, id = "done_tallgrass", x = -8, z = 0, rot = 0, lvl = 3 })
		table.insert(raw.plot.placed, { uid = 7003, id = "yard", x = 8, z = 6, rot = 0, lvl = 1 })
		raw.folk = { { id = 6001, name = "Ada", look = raw.founder, work = 0, day = 1, lvl = 7, xp = 4, seed = 12 } }
		raw.pals = {
			{ id = 8001, sp = "pebblit", lvl = 9, xp = 1, work = built(p0)[4].uid, muts = { "sturdy2" } },
			{ id = 8002, sp = "sunsprite", lvl = 3, xp = 0, work = 0, muts = {} },
			{ id = 8003, sp = "mossbun", lvl = 2, xp = 0, work = 0, muts = {} },
		}
		local shells, wood = raw.shells, raw.wood
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		for _, k in { "cap", "pouch", "islets", "sea", "wilds" } do
			T.eq(p[k], nil, k .. " gone")
		end
		for _, q in p.plot.placed do
			T.truthy(Buildings.byId[q.id] ~= nil, q.id .. " a known piece")
			T.truthy(q.id ~= "yard", "no yard")
		end
		T.eq(treeCount(p), 1, "a tree")
		T.truthy(p.shells >= shells + 450 and p.wood >= wood + 50, "the yard's price back")
		T.eq(p.folk, nil, "no villagers")
		T.eq(p.pals[1].home, nest, "the first two in the nest, as before")
		T.eq(p.pals[2].home, nest)
		T.eq(p.pals[3].home, 0, "the third in the pen")
		T.eq(p.pals[1].work, built(p0)[4].uid, "a helper keeps its job")
		T.eq(p.pals[1].lvl, nil)
		T.eq(p.tut, 4, "the sailing tips: the hut's")
		T.eq(p.quest, 1, "the questline starts again")
		T.eq(p.stats.grown, 7, "befriended counts as grown")
		T.eq(p.stats.best, 4, "the sunsprite: epic")
		T.eq(p.stats.battles, nil)
		T.deepEq(p.tree, { luck = 1, speed = 1, t = 0 })
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
	end)
	T.it("a version 10 save (with villagers): they go, every home comes down with its whole price back, the tips step back", function()
		local p0 = played()
		local raw = roundTrip(p0)
		raw.v = 10
		raw.folk = {
			{ id = 6001, name = "Ada", look = raw.founder, work = built(p0)[2].uid, day = 1 },
			{ id = 6002, name = "Ravi", look = raw.founder, work = 0, day = 3 },
		}
		raw.stats.movedIn = 2
		raw.tut = 6
		table.insert(raw.plot.placed, { uid = 7101, id = "tent", x = 9, z = 8, rot = 0, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 7102, id = "villa", x = -9, z = 8, rot = 0, lvl = 2 })
		local shells, wood = raw.shells, raw.wood
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.folk, nil, "no villagers")
		T.eq(p.stats.movedIn, nil)
		for _, q in p.plot.placed do
			T.truthy(q.id ~= "tent" and q.id ~= "villa", "no homes")
		end
		T.eq(#built(p), 4, "the rest stays")
		T.eq(p.shells, shells + 30 + 20000, "the homes' price back")
		T.eq(p.wood, wood + 2000)
		T.eq(p.tut, 5, "the tree's tip, one step back")
		T.eq(#p.pals, 2, "the driftlings stay")
		T.eq(p.pals[1].work, built(p0)[4].uid, "at work as before")
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
		for old, new in { [4] = 4, [5] = 4, [7] = 6, [0] = 0 } do
			T.eq((Schema.reconcile({ v = 10, tut = old }, 2000, 9) :: any).tut, new, "tip " .. old)
		end
	end)
	T.it("a version 6 save: each driftling rolls its mutations once, the same every load; a later save keeps its own", function()
		local raw = function(): any
			return { v = 6, sea = 5, pals = { { id = 9, sp = "pebblit", lvl = 2, xp = 0, work = 0 }, { id = 10, sp = "solwyrm", lvl = 30, xp = 0, work = 0 } } }
		end
		local a = Schema.reconcile(raw(), 2000, 9) :: any
		local b = Schema.reconcile(raw(), 2000, 9) :: any
		T.eq(#a.pals, 2)
		for i, x in a.pals do
			T.truthy(type(x.muts) == "table" and #x.muts <= Traits.MAX, "a list of mutations")
			T.deepEq(x.muts, b.pals[i].muts, "the same roll every load")
			for _, id in x.muts do
				T.truthy(Traits.byId[id] ~= nil, id)
			end
		end
		-- a version 7 save's own list: kept, cleaned (unknown ids, a family twice, past MAX)
		local c = Schema.reconcile({ v = 7, pals = { { id = 4, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = { "fierce2", "nope", "fierce4", 7, "swift1", "bright3", "busy1", "sturdy1" } } } }, 2000, 9) :: any
		T.deepEq(c.pals[1].muts, { "fierce2", "swift1", "bright3", "busy1" })
		local d = Schema.reconcile({ v = 7, pals = { { id = 4, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = "x" } } }, 2000, 9) :: any
		T.deepEq(d.pals[1].muts, {}, "garbage: none")
	end)
	T.it("a version 1 save loads too", function()
		local p = Schema.reconcile({ v = 1, money = 5, staff = {} }, 2000, 9)
		T.eq(p.v, Schema.VERSION)
		T.truthy(type(p.founder) == "table" and p.founder.skin >= 1)
	end)
end
