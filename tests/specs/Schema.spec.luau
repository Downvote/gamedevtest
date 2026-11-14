-- The save (Logic/Schema; docs/ARCHITECTURE.md 7.6): a new island, a played profile surviving a round trip, garbage,
-- the old saves (versions 1 to 4: the studios) loading into the island with the founder kept, a save from before the
-- Tree of Life (version 9: the wild places and the fights) coming in with its driftlings in huts, and a save from the
-- Tree of Life's days (version 11) losing its pen (sold) and its food, and a save from the tide (version 12) getting
-- its Tree of Life back with eggs to lay.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Island = require("../../build/luautest/shared/Logic/Island")
local Util = require("../../build/luautest/shared/Logic/Util")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- the pieces built (not the tree: every island has it)
local function built(p: any): { any }
	local out = {}
	for _, q in p.plot.placed do
		if Buildings.byId[q.id] and q.id ~= "tree" then
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

-- a played island: buildings, a driftling at work in its hut and one resting there
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
	p.shells = 1e5
	place(p, "stall")
	place(p, "patch")
	place(p, "nest")
	place(p, "lumber")
	built(p)[2].lvl = 2 -- (a level from before upgrades were taken out: kept)
	Island.newDay(p)
	table.insert(p.pals, { id = p.nextId, sp = "pebblit", home = built(p)[3].uid, work = built(p)[4].uid, muts = { "sturdy2", "lazy" } })
	p.nextId += 1
	table.insert(p.pals, { id = p.nextId, sp = "clawdle", home = built(p)[3].uid, work = 0, muts = {} })
	p.nextId += 1
	p.seen.pebblit = 2
	p.seen.clawdle = 2
	p.seen.gullfin = 1 -- (drifted by, not had)
	p.stats.best = 1
	p.stats.taken = 2
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
		T.eq((p :: any).tree, nil, "no tree levels")
		T.deepEq(p.clutch, { left = 0, list = {}, next = 1 }, "its first eggs laid when the player arrives")
		T.eq((p :: any).food, nil, "no food")
		T.eq((p :: any).wood, nil, "no wood: one store")
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
			T.eq((p :: any).wood, nil, "no wood")
			T.eq((p :: any).food, nil)
			T.truthy(p.tier >= 1 and p.tier <= #Tuning.TierCost)
			T.eq(#built(p), 0)
			T.eq(treeCount(p), 1)
			T.eq(#p.pals, 0)
			T.eq((p :: any).tree, nil)
			T.truthy(p.seen.x == nil)
		end
	end)
	T.it("jobs only where they make sense; ids unique; nextId past every id", function()
		local p = played()
		local raw = roundTrip(p)
		raw.pals[1].work = built(raw)[2].uid -- a wood driftling at the patch: fine, any driftling works anywhere
		raw.pals[2].work = built(raw)[3].uid -- a hut is no job
		table.insert(raw.pals, roundTrip(raw.pals[2])) -- the same id twice
		raw.nextId = 1
		local back = Schema.reconcile(raw, 1, 1)
		T.eq(back.pals[1].work, built(raw)[2].uid, "kept at the patch")
		T.eq(back.pals[2].work, 0)
		T.eq(#back.pals, 2, "the same id once")
		-- a hut that isn't there, or a hut over its room: no hut
		local raw2 = roundTrip(played())
		raw2.pals[1].home = 99999
		local b2 = Schema.reconcile(raw2, 1, 1)
		T.eq(b2.pals[1].home, built(b2)[3].uid, "a stray hut: none, then it moves into the hut with room")
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
		T.eq(treeCount(p), 1, "a tree")
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
	T.it("a version 8 save: the boat and the chart go; what was built stays", function()
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
	T.it("a version 9 save (the wild places and the fights): they go; the yard's price back; huts, the rest sold; the tips and quests", function()
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
		local shells = raw.shells
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
		T.truthy(p.shells >= shells + 450 + 50 and p.wood == nil, "the yard's price back (its wood as shells)")
		T.eq(p.folk, nil, "no villagers")
		T.eq(p.pals[1].home, nest, "the first two in the nest, as before")
		T.eq(p.pals[2].home, nest)
		T.eq(#p.pals, 2, "the third went to the pen, and the pen was sold")
		T.eq(p.stats.sold, 1)
		T.eq(p.pals[1].work, built(p0)[4].uid, "a helper keeps its job")
		T.eq(p.pals[1].lvl, nil)
		T.eq(p.tut, 4, "the sailing tips: the hut's")
		T.eq(p.quest, 1, "the questline starts again")
		T.eq(p.stats.taken, 7, "befriended counts as taken in")
		T.eq(p.stats.best, 4, "the sunsprite: epic")
		T.eq(p.stats.battles, nil)
		T.eq(p.tree, nil)
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
		local shells = raw.shells
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.folk, nil, "no villagers")
		T.eq(p.stats.movedIn, nil)
		for _, q in p.plot.placed do
			T.truthy(q.id ~= "tent" and q.id ~= "villa", "no homes")
		end
		T.eq(#built(p), 4, "the rest stays")
		T.eq(p.shells, shells + 30 + 20000 + 2000, "the homes' price back (their wood as shells)")
		T.eq(p.wood, nil)
		T.eq(p.tut, 5, "one step back")
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
			-- (a nest for the two: a save's driftlings with no hut went to the pen, and the pen was sold at version 12)
			return { v = 6, sea = 5, plot = { placed = { { uid = 50, id = "nest", x = 6, z = 4, rot = 0 } } }, pals = { { id = 9, sp = "pebblit", lvl = 2, xp = 0, work = 0 }, { id = 10, sp = "solwyrm", lvl = 30, xp = 0, work = 0 } } }
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
		local NEST = { placed = { { uid = 50, id = "nest", x = 6, z = 4, rot = 0 } } }
		local c = Schema.reconcile({ v = 7, plot = NEST, pals = { { id = 4, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = { "fierce2", "nope", "fierce4", 7, "swift1", "bright3", "busy1", "sturdy1" } } } }, 2000, 9) :: any
		-- (swift1, a Leafy one, is Lucky now: bright, already there, so it goes)
		T.deepEq(c.pals[1].muts, { "fierce2", "bright1", "busy1", "sturdy1" })
		local d = Schema.reconcile({ v = 7, plot = NEST, pals = { { id = 4, sp = "pebblit", lvl = 1, xp = 0, work = 0, muts = "x" } } }, 2000, 9) :: any
		T.deepEq(d.pals[1].muts, {}, "garbage: none")
	end)
	T.it("a version 11 save (the Tree of Life): the tree, its levels and its food go; the pen is sold; grown counts as taken", function()
		local Tree = require("../../build/luautest/shared/Logic/Tree")
		local p0 = played()
		local raw = roundTrip(p0)
		raw.v = 11
		raw.food = 345
		raw.tree = { luck = 6, speed = 4, t = 2 }
		raw.stats.grown = 812
		raw.stats.taken = nil
		raw.stats.sold = 3
		table.insert(raw.plot.placed, { uid = 7201, id = "tree", x = -3, z = -4, rot = 0, lvl = 1 })
		-- the pen: two waiting (one kept there by the player)
		table.insert(raw.pals, { id = 7301, sp = "gullfin", home = 0, work = 0, muts = { "fierce1" } })
		table.insert(raw.pals, { id = 7302, sp = "solwyrm", home = 0, work = 0, muts = {}, held = 1 })
		local price = Tree.price({ id = 0, sp = "gullfin", home = 0, work = 0, muts = { "fierce1" } }) + Tree.price({ id = 0, sp = "solwyrm", home = 0, work = 0, muts = {} })
		local shells, earned = raw.shells, raw.stats.earned
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.tree, nil, "no tree")
		T.eq(p.food, nil, "no food")
		T.eq(treeCount(p), 1, "a new tree (the old one and its levels went with the tide; the eggs brought it back)")
		T.eq(#built(p), 4, "the rest stays")
		T.eq(#p.pals, 2, "the huts' driftlings stay")
		T.eq(p.shells, shells + price, "the pen sold for its price")
		T.eq(p.stats.sold, 3 + 2)
		T.eq(p.stats.earned, earned + price)
		T.eq(p.stats.taken, 812, "the tree's count as taken in")
		T.eq(p.stats.grown, nil)
		for _, x in p.pals do
			T.eq(x.held, nil, "no holds")
		end
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
	end)
	T.it("a version 12 save (the tide): the Tree of Life comes back, its eggs laid when the player arrives", function()
		local p0 = played()
		local raw = roundTrip(p0)
		raw.v = 12
		raw.clutch = nil
		local keep = {}
		for _, q in raw.plot.placed do
			if q.id ~= "tree" then
				table.insert(keep, q)
			end
		end
		raw.plot.placed = keep
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(treeCount(p), 1, "the tree is back")
		T.eq(#built(p), 4, "what was built stays")
		T.eq(#p.pals, 2)
		T.deepEq(p.clutch, { left = 0, list = {}, next = 1 }, "eggs to lay at once")
		-- an island built full: the pieces nearest the tree's spot make room, their price back
		local full = roundTrip(p0)
		full.v = 12
		full.plot.placed = {}
		full.shells = 0
		local uid = 100
		local r = Street.plot(1)
		for z = r.z0 - r.z0 % 2, r.z1, 2 do
			for x = r.x0 - r.x0 % 2, r.x1, 2 do
				if Plot.fits(1, full.plot.placed, "stonepath", x, z, 0) and #full.plot.placed < Plot.pathLimit(1) then
					uid += 1
					table.insert(full.plot.placed, { uid = uid, id = "stonepath", x = x, z = z, rot = 0, lvl = 1 })
				end
			end
		end
		full.pals = {}
		local q = Schema.reconcile(full, 2000, 9) :: any
		T.eq(treeCount(q), 1, "room made for the tree")
		T.truthy(q.shells > 0, "the paths it took up paid back")
		-- a saved lot of eggs is kept as it was (leaving and coming back lays no new one)
		local p2 = roundTrip(p)
		p2.clutch = { left = 77, list = { { id = 3, r = 2 }, { id = 4, r = 9 }, { id = 4, r = 1 }, "x" }, next = 2 }
		local q2 = Schema.reconcile(p2, 2000, 9) :: any
		T.deepEq(q2.clutch, { left = 77, list = { { id = 3, r = 2 }, { id = 4, r = Traits.RMAX } }, next = 5 }, "cleaned: a rarity in range, ids once, next past them")
	end)
	T.it("a version 14 save (two stores): its wood is added to its shells, one for one, and the wood goes", function()
		-- (the request of 2026-11-14: "make shells the main currency ... remove wood as a currency")
		local raw = roundTrip(played())
		raw.v = 14
		raw.shells = 1234
		raw.wood = 5678
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.shells, 1234 + 5678, "the wood folded in")
		T.eq(p.wood, nil, "no wood")
		T.eq(#built(p), 4, "what was built stays")
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
		-- garbage wood adds nothing, and never spoils the shells
		for _, w in { 0 / 0, -50, "x", math.huge } :: { any } do
			local bad = roundTrip(played())
			bad.v = 14
			bad.shells = 300
			bad.wood = w
			local q = Schema.reconcile(bad, 2000, 9) :: any
			T.truthy(q.shells == q.shells and q.shells >= 300 and q.shells <= 1e12, "shells kept: " .. tostring(w))
			T.eq(q.wood, nil)
		end
	end)
	T.it("a version 13 save: the old one-piece fence and hedge come up with their price back; drawn pieces checked", function()
		local raw = roundTrip(played())
		raw.v = 13
		local s0 = raw.shells
		table.insert(raw.plot.placed, { uid = 900, id = "fence", x = 9, z = 4, rot = 0, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 901, id = "hedge", x = 6, z = -4, rot = 90, lvl = 1 })
		-- a fence length off the even grid, one turned the wrong way, and good ones (a fence, water, a path far north)
		table.insert(raw.plot.placed, { uid = 902, id = "picket", x = 3, z = 4, rot = 0, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 903, id = "picket", x = 4, z = 4, rot = 180, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 904, id = "picket", x = 8, z = -8, rot = 90, lvl = 1 })
		table.insert(raw.plot.placed, { uid = 905, id = "stream", x = 10, z = -8, rot = 0, lvl = 1 })
		raw.tier = 10
		table.insert(raw.plot.placed, { uid = 906, id = "dirtpath", x = 0, z = -100, rot = 0, lvl = 1 })
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		local has: { [number]: boolean } = {}
		for _, q in p.plot.placed do
			has[q.uid] = true
		end
		T.truthy(not has[900] and not has[901], "the old fence and hedge are gone")
		T.eq(p.shells, s0 + 25 + 120, "their whole price back (in wood then, shells now)")
		T.truthy(not has[902] and not has[903], "a fence off the grid or turned wrong")
		T.truthy(has[904] and has[905], "a fence length and a water tile kept")
		T.truthy(has[906], "the biggest island's far north")
	end)
	T.it("a version 1 save loads too", function()
		local p = Schema.reconcile({ v = 1, money = 5, staff = {} }, 2000, 9)
		T.eq(p.v, Schema.VERSION)
		T.truthy(type(p.founder) == "table" and p.founder.skin >= 1)
	end)
end
