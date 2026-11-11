-- The save (Logic/Schema; docs/ARCHITECTURE.md 7.6): a new island, a played profile surviving a round trip, garbage,
-- the old saves (versions 1 to 4: the studios) loading into the island with the founder kept.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Island = require("../../build/luautest/shared/Logic/Island")
local Util = require("../../build/luautest/shared/Logic/Util")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- the pieces built (not the wild places, which come up by themselves: Logic/Sites)
local function built(p: any): { any }
	local out = {}
	for _, q in p.plot.placed do
		if Buildings.byId[q.id] and Buildings.byId[q.id].kind ~= "site" then
			table.insert(out, q)
		end
	end
	return out
end
local function wildCount(p: any): number
	local n = 0
	for _, q in p.plot.placed do
		if Buildings.byId[q.id] and Buildings.byId[q.id].kind == "site" then
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

-- a played island: buildings, villagers working, a driftling helping, an island charted
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
	place(p, "tent")
	place(p, "patch")
	place(p, "nest")
	place(p, "lumber")
	built(p)[2].lvl = 2 -- (a level from before upgrades were taken out: kept)
	local rng = Util.newRng(3)
	Island.turn(p, rng)
	Island.newDay(p)
	table.insert(p.pals, { id = p.nextId, sp = "pebblit", lvl = 3, xp = 5, work = built(p)[4].uid, muts = { "sturdy2", "lazy" } })
	p.nextId += 1
	p.seen.pebblit = 2
	p.seen.clawdle = 1
	p.islets = 1
	p.cap = { lvl = 4, xp = 10 }
	return p
end

return function()
	T.it("a new island", function()
		local p = Schema.default(1000, 42)
		T.eq(p.v, Schema.VERSION)
		T.eq(p.shells, Tuning.StartShells)
		T.eq(p.tier, 1)
		T.eq(p.tut, 1)
		T.eq(#p.folk, 0)
		T.deepEq(Schema.default(1, 5).founder, Schema.default(1, 5).founder, "the same seed, the same founder")
		T.eq(#built(p), 0, "nothing built")
		T.eq(wildCount(p), 2, "its first wild places")
		T.eq(p.wilds, 1)
		T.deepEq(Schema.default(1, 5).plot.placed, Schema.default(1, 5).plot.placed, "the same seed, the same places")
	end)
	T.it("reconcile keeps a played profile as it is", function()
		local p = played()
		T.truthy(#built(p) == 4 and wildCount(p) == 2 and #p.folk == 1 and #p.pals == 1)
		T.truthy(p.folk[1].work ~= 0, "the villager works")
		local back = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(back, p)
	end)
	T.it("reconcile turns garbage into a valid profile", function()
		for _, raw in { nil, 5, "x", {}, { v = 5, shells = 0 / 0, food = -5, tier = 99, folk = "no", pals = { { sp = "dragon" }, 7 }, plot = { placed = { { uid = 1, id = "castle", x = 0, z = 0, rot = 0 }, 3 } }, seen = { pebblit = 9, x = 1 }, islets = -3 } } :: { any } do
			local p = Schema.reconcile(raw, 1000, 3)
			T.truthy(p.shells == p.shells and p.shells >= 0, "shells")
			T.truthy(p.food >= 0)
			T.truthy(p.tier >= 1 and p.tier <= #Tuning.TierCost)
			T.eq(#built(p), 0)
			T.eq(p.wilds, p.tier, "its wild places up")
			T.eq(#p.pals, 0)
			T.truthy(p.islets >= 0 and p.islets == math.floor(p.islets))
			T.truthy(p.seen.x == nil)
		end
	end)
	T.it("jobs only where they make sense; ids unique; nextId past every id", function()
		local p = played()
		local raw = roundTrip(p)
		raw.folk[1].work = 424242
		raw.pals[1].work = built(raw)[2].uid -- a wood driftling at the patch
		table.insert(raw.folk, roundTrip(raw.folk[1])) -- the same id twice
		raw.nextId = 1
		local back = Schema.reconcile(raw, 1, 1)
		T.eq(back.folk[1].work, 0)
		T.eq(back.pals[1].work, 0)
		T.eq(#back.folk, 1)
		local top = 0
		for _, q in back.plot.placed do
			top = math.max(top, q.uid)
		end
		for _, v in back.folk do
			top = math.max(top, v.id)
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
		T.eq(wildCount(p), 2, "a new island's wild places")
		T.eq(p.tut, 1, "the tips start over")
		T.eq(p.coins, nil)
		T.eq(p.games, nil)
	end)
	T.it("a version 5 save: its tip moves to the same tip of the six", function()
		for old, new in { [0] = 0, [1] = 1, [2] = 2, [3] = 5, [4] = 6 } do
			local p = Schema.reconcile({ v = 5, shells = 10, tier = 1, tut = old }, 2000, 9) :: any
			T.eq(p.v, Schema.VERSION)
			T.eq(p.tut, new, "tip " .. old)
			T.truthy(p.sea >= 1 and p.wilds == 1, "its own seed; its wild places up")
		end
	end)
	T.it("a version 8 save: the boat and the chart go, its islands charted count as places cleared, its wild places come up", function()
		local raw = roundTrip(played())
		raw.v = 8
		raw.tier = 2
		raw.sea = 77
		raw.boat = 4
		raw.chart = { 3, 7 }
		raw.islets = 2
		raw.wilds = nil
		-- (an older save had no wild places)
		local keep = {}
		for _, q in raw.plot.placed do
			if not string.find(q.id, "^wild_") and not string.find(q.id, "^done_") then
				table.insert(keep, q)
			end
		end
		raw.plot.placed = keep
		local p = Schema.reconcile(raw, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.boat, nil, "no boat")
		T.eq(p.chart, nil, "no chart")
		T.eq(p.islets, 2, "the islands charted kept (their charm)")
		T.eq(p.sea, 77)
		T.eq(p.wilds, 2, "both tiers' wild places")
		T.eq(wildCount(p), 5, "two from the first tier, three from the second")
		T.eq(#built(p), 4, "what was built stays")
		local again = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(again, p, "and stays put on the next load")
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
