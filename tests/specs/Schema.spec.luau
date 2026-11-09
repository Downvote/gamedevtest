-- The save (Logic/Schema; docs/ARCHITECTURE.md 7.6): a new studio, a played profile surviving a round trip, garbage,
-- the old saves (version 1 and 2: the old studio) loading into the idea loop, the plot kept to what fits.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Studio = require("../../build/luautest/shared/Logic/Studio")
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

-- a played profile: ideas rolled, two games launched, one in the works, upgrades, decor
local function played(): any
	local p = Schema.default(1000, 7)
	local rng = Util.newRng(1)
	for g = 1, 3 do
		for _ = 1, 5 do
			Studio.rollIdea(p, rng)
		end
		Studio.make(p, 1, 2, 3, g)
		Studio.result(p, 1, true)
		Studio.result(p, 2, g % 2 == 0)
		if g < 3 then
			Studio.result(p, 3, true)
			Studio.launch(p, 1000 + g)
		end
	end
	p.coins = 5000
	Studio.buyUpgrade(p, "speed")
	Studio.buyUpgrade(p, "luck")
	p.plot.owned.gnome = true
	table.insert(p.plot.placed, { id = "gnome", x = 16, z = 18, rot = 0 })
	return p
end

return function()
	T.it("a new studio", function()
		local p = Schema.default(1000, 42)
		T.eq(p.v, Schema.VERSION)
		T.eq(p.coins, Tuning.StartCoins)
		T.eq(#p.team, Tuning.TeamSize)
		T.eq(p.team[1].desk, 1)
		T.eq(p.team[3].desk, 3)
		T.eq(p.office, 1)
		T.eq(p.project, nil)
		T.eq(p.tut, 1)
		T.deepEq(Schema.default(1, 5).team, Schema.default(1, 5).team, "the same seed, the same team")
	end)
	T.it("reconcile keeps a played profile as it is", function()
		local p = played()
		T.truthy(p.project ~= nil and #p.games == 2 and p.upgrades.speed == 1)
		local back = Schema.reconcile(roundTrip(p), 2000, 9)
		T.deepEq(back, p)
	end)
	T.it("reconcile turns garbage into a valid profile", function()
		for _, raw in { nil, 5, "x", {}, { coins = 0 / 0, team = "no", office = 99, ideas = { 1, { id = "chess", mod = "plain" }, { id = "action", mod = "plain" } }, found = { ["action|plain"] = -3, ["x|y"] = 2, ["space|turbo"] = 4 }, rate = 1 / 0, upgrades = { speed = -1, luck = "x" }, project = { ideas = { { id = "action", mod = "plain" } } }, games = { { ideas = {} }, 7 } } } :: { any } do
			local p = Schema.reconcile(raw, 1000, 3)
			T.truthy(p.coins == p.coins and p.coins >= 0, "coins")
			T.eq(p.live, nil)
			T.truthy(#p.team >= 1)
			T.truthy(p.office >= 1 and p.office <= 3)
			T.truthy(p.upgrades.speed >= 0 and p.upgrades.luck >= 0)
			T.eq(p.project, nil, "a project needs three valid ideas")
			for _, c in p.ideas do
				T.truthy(c.id ~= "chess")
			end
			T.eq(p.found["x|y"], nil)
			T.eq(p.found["action|plain"], nil)
			T.eq(#p.games, 0)
		end
		local p = Schema.reconcile({ found = { ["space|turbo"] = 4 } }, 1, 1)
		T.eq(p.found["space|turbo"], 4)
	end)
	T.it("the board holds BoardSize, the team its desks, the income never below the listed games'", function()
		local p = Schema.default(1, 1) :: any
		for _ = 1, 20 do
			table.insert(p.ideas, { id = "action", mod = "plain" })
		end
		for i = 1, 6 do
			table.insert(p.team, { id = 10 + i, name = "X", look = p.team[1].look, desk = 1 })
		end
		p.games = { { id = 1, title = "A", ideas = { { id = "music", mod = "cosmic" }, { id = "music", mod = "cosmic" }, { id = "music", mod = "cosmic" } }, rate = 1, wins = 3, at = 0, peak = 5, earned = 9 } }
		local back = Schema.reconcile(roundTrip(p), 1, 1)
		T.eq(#back.ideas, Tuning.BoardSize)
		T.eq(#back.team, Tuning.TeamSize)
		local seen = {}
		for _, m in back.team do
			T.truthy(m.desk >= 1 and not seen[m.desk])
			seen[m.desk] = true
		end
		T.truthy(back.games[1].rate > 1, "a game's rate is worked out again from its ideas")
	end)
	T.it("the game on sale: kept mid-curve through a round trip, dropped when its game is not listed", function()
		local p = played()
		Studio.result(p, 3, true)
		Studio.launch(p, 5000, 11)
		for _ = 1, 47 do
			Studio.sell(p, 1)
		end
		local back = Schema.reconcile(roundTrip(p), 6000, 9)
		T.deepEq(back.live, p.live)
		local raw = roundTrip(p)
		raw.live.id = 999
		T.eq(Schema.reconcile(raw, 6000, 9).live, nil)
		raw = roundTrip(p)
		raw.live.age = 1 / 0
		raw.live.samples = { -4, "x", 7 }
		local odd = Schema.reconcile(raw, 6000, 9).live
		T.truthy(odd ~= nil and odd.age == 0 and odd.samples[1] == 0 and odd.samples[3] == 7)
	end)
	T.it("a version 3 save: the newest game goes on sale afresh, the old modifiers take their new names", function()
		local cards = { { id = "action", mod = "tiny" }, { id = "puzzle", mod = "shaky" }, { id = "space", mod = "haunted" } }
		local old = {
			v = 3,
			coins = 50,
			rate = 999,
			ideas = { { id = "ninjas", mod = "glitched" }, { id = "music", mod = "cosmic" } },
			found = { ["ninjas|glitched"] = 2, ["ninjas|frenzy"] = 1, ["action|tiny"] = 3 },
			games = { { id = 1, title = "A", ideas = cards, rate = 5, wins = 1, at = 10 }, { id = 2, title = "B", ideas = cards, rate = 5, wins = 3, at = 20 } },
			nextGame = 3,
		}
		local p = Schema.reconcile(old, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.rate, nil)
		T.eq(p.live.id, 2)
		T.eq(p.live.age, 0)
		T.deepEq(p.ideas[1], { id = "ninjas", mod = "frenzy" })
		T.eq(p.found["ninjas|frenzy"], 3, "found counts merge")
		T.eq(p.found["action|icy"], 3)
		T.eq(p.found["action|tiny"], nil)
		T.eq(p.games[1].ideas[1].mod, "icy")
		T.eq(p.games[1].ideas[2].mod, "crowded")
		T.eq(p.games[1].ideas[3].mod, "shrinking")
		T.eq(p.games[1].peak, 0)
	end)
	T.it("a version 2 save (the old studio) loads into the idea loop: founder, decor, office and crew kept", function()
		local old = {
			v = 2,
			money = 123456,
			fans = 999,
			rp = 40,
			week = 300,
			office = 2,
			staff = {
				{ id = 1, name = "Ada Byte", look = { skin = 2, hair = 3, style = 1, shirt = 4 }, desk = 2, skills = { code = 40 } },
				{ id = 2, name = "Bo Pixel", look = { skin = 1, hair = 1, style = 2, shirt = 1 }, desk = 1 },
			},
			releases = { { title = "Old Game" } },
			project = { title = "Galaxy Blocks", genre = "puzzle" },
			genres = { action = true },
			stats = { games = 9, best = 33 },
			founder = { skin = 3, hair = 2, style = 4, shirt = 6 },
			plot = { owned = { gnome = true, fountain = true }, placed = { { id = "gnome", x = 16, z = 18, rot = 0 } } },
			settings = { pixel = "low" },
			tut = 0,
		}
		local p = Schema.reconcile(old, 2000, 9) :: any
		T.eq(p.v, Schema.VERSION)
		T.eq(p.coins, Tuning.StartCoins)
		T.eq(p.office, 2)
		T.eq(#p.team, 2)
		T.eq(p.team[1].name, "Ada Byte")
		T.eq(p.team[1].desk, 2)
		T.deepEq(p.founder, { skin = 3, hair = 2, style = 4, shirt = 6 })
		T.truthy(p.plot.owned.gnome and p.plot.owned.fountain)
		T.eq(#p.plot.placed, 1)
		T.eq(p.settings.pixel, "low")
		T.eq(p.project, nil)
		T.eq(p.stats.games, 0)
		T.eq(p.tut, 1, "the tips start over for the new loop")
		T.eq(p.money, nil)
		T.eq(p.staff, nil)
	end)
	T.it("a version 1 save (before the street) loads too", function()
		local p = Schema.reconcile({ v = 1, money = 5, office = 1, staff = {} }, 2000, 9)
		T.eq(p.v, Schema.VERSION)
		T.truthy(type(p.founder) == "table" and p.founder.skin >= 1)
		T.eq(#p.team, Tuning.TeamSize)
	end)
	T.it("the plot keeps only owned decor that fits, up to the limit", function()
		local p = Schema.default(1, 1) :: any
		p.plot = {
			owned = { gnome = true, castle = true, bench = "yes" },
			placed = {
				{ id = "gnome", x = 16, z = 18, rot = 0 },
				{ id = "gnome", x = 16, z = 18, rot = 0 }, -- on the first
				{ id = "gnome", x = 0, z = 0, rot = 0 }, -- in the office
				{ id = "bench", x = 10, z = 20, rot = 0 }, -- not owned
				{ id = "gnome", x = 18, z = 18, rot = 45 }, -- not a quarter turn
			},
		}
		local back = Schema.reconcile(roundTrip(p), 1, 1)
		T.truthy(back.plot.owned.gnome and back.plot.owned.castle == nil and back.plot.owned.bench == nil)
		T.eq(#back.plot.placed, 1)
	end)
end
