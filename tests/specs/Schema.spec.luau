-- The save (Logic/Schema; docs/ARCHITECTURE.md 7.6): a new island, a played profile surviving a round trip, garbage,
-- the old saves (versions 1 to 4: the studios) loading into the island with the founder kept.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Island = require("../../build/luautest/shared/Logic/Island")
local Util = require("../../build/luautest/shared/Logic/Util")

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
	Plot.upgrade(p, 2)
	local rng = Util.newRng(3)
	Island.turn(p, rng)
	Island.newDay(p)
	table.insert(p.pals, { id = p.nextId, sp = "pebblit", lvl = 3, xp = 5, work = p.plot.placed[4].uid })
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
	end)
	T.it("reconcile keeps a played profile as it is", function()
		local p = played()
		T.truthy(#p.plot.placed == 4 and #p.folk == 1 and #p.pals == 1)
		T.truthy(p.folk[1].work ~= 0, "the villager works")
		local back = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(back, p)
	end)
	T.it("reconcile turns garbage into a valid profile", function()
		for _, raw in { nil, 5, "x", {}, { v = 5, shells = 0 / 0, food = -5, tier = 99, folk = "no", pals = { { sp = "dragon" }, 7 }, plot = { placed = { { uid = 1, id = "castle", x = 0, z = 0, rot = 0 }, 3 } }, seen = { pebblit = 9, x = 1 }, islets = -3 } } :: { any } do
			local p = Schema.reconcile(raw, 1000, 3)
			T.truthy(p.shells == p.shells and p.shells >= 0, "shells")
			T.truthy(p.food >= 0)
			T.truthy(p.tier >= 1 and p.tier <= 3)
			T.eq(#p.plot.placed, 0)
			T.eq(#p.pals, 0)
			T.truthy(p.islets >= 0 and p.islets == math.floor(p.islets))
			T.truthy(p.seen.x == nil)
		end
	end)
	T.it("jobs only where they make sense; ids unique; nextId past every id", function()
		local p = played()
		local raw = roundTrip(p)
		raw.folk[1].work = 424242
		raw.pals[1].work = raw.plot.placed[2].uid -- a wood driftling at the patch
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
		T.eq(#p.plot.placed, 0)
		T.eq(p.tut, 1, "the tips start over")
		T.eq(p.coins, nil)
		T.eq(p.games, nil)
	end)
	T.it("a version 5 save: its tip moves to the same tip of the six", function()
		for old, new in { [0] = 0, [1] = 1, [2] = 2, [3] = 5, [4] = 6 } do
			local p = Schema.reconcile({ v = 5, shells = 10, tier = 1, tut = old }, 2000, 9) :: any
			T.eq(p.v, Schema.VERSION)
			T.eq(p.tut, new, "tip " .. old)
			T.truthy(p.sea >= 1 and p.boat == 1 and #p.chart == 0, "the sea chart: its own sea, the first boat")
		end
		local q = Schema.reconcile({ v = 6, sea = 77, boat = 99, chart = { 3, 3, 0, 500, "x", 7, 1.5 } }, 2000, 9) :: any
		T.eq(q.sea, 77)
		T.eq(q.boat, #Tuning.BoatRadius, "a boat past the top: the top")
		T.deepEq(q.chart, { 3, 7 }, "only islands of the chart, each once")
	end)
	T.it("a version 1 save loads too", function()
		local p = Schema.reconcile({ v = 1, money = 5, staff = {} }, 2000, 9)
		T.eq(p.v, Schema.VERSION)
		T.truthy(type(p.founder) == "table" and p.founder.skin >= 1)
	end)
end
