-- The studio's rules (Logic/Studio; GAME_DESIGN 3-7): a new idea, making a game, its minigames, the launch, the
-- upgrades, the founder's look.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Studio = require("../../build/luautest/shared/Logic/Studio")
local Ideas = require("../../build/luautest/shared/Logic/Ideas")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Util = require("../../build/luautest/shared/Logic/Util")

local function fresh(): any
	return Schema.default(0, 1)
end

local function board(p: any, list: { string })
	p.ideas = {}
	for _, id in list do
		table.insert(p.ideas, { id = id, mod = "plain" })
	end
end

return function()
	T.it("a new studio: no coins, an idea team, an empty board", function()
		local p = fresh()
		T.eq(p.coins, Tuning.StartCoins)
		T.eq(#p.team, Tuning.TeamSize)
		T.eq(#p.ideas, 0)
		T.eq(p.live, nil)
		T.eq(p.tut, 1)
	end)
	T.it("a new idea: on the board, in the Index, the stats", function()
		local p = fresh()
		local rng = Util.newRng(3)
		local r = Studio.rollIdea(p, rng)
		T.eq(r.slot, 1)
		T.eq(#p.ideas, 1)
		T.eq(p.found[Ideas.key(r.card)], 1)
		T.truthy(r.first)
		T.eq(p.stats.rolls, 1)
		T.eq(p.stats.best, r.oneIn)
		T.eq(r.tier, Ideas.tierOf(r.oneIn))
		for _ = 1, 40 do
			Studio.rollIdea(p, rng)
		end
		T.eq(#p.ideas, Tuning.BoardSize, "the board holds BoardSize")
		T.eq(p.stats.rolls, 41)
	end)
	T.it("make: three different board ideas leave the board for the project", function()
		local p = fresh()
		board(p, { "action", "puzzle", "space", "animals" })
		T.eq(select(2, Studio.make(p, 1, 1, 2, 0)), "bad_payload", "twice the same")
		T.eq(select(2, Studio.make(p, 1, 2, 5, 0)), "bad_payload", "not on the board")
		local ok, proj = Studio.make(p, 4, 1, 3, 9)
		T.truthy(ok)
		T.eq(#p.ideas, 1)
		T.eq(p.ideas[1].id, "puzzle")
		T.eq(proj.ideas[1].id, "animals")
		T.eq(proj.ideas[2].id, "action")
		T.eq(proj.ideas[3].id, "space")
		T.deepEq(proj.won, { -1, -1, -1 })
		T.eq(p.tut, 2)
		T.eq(select(2, Studio.make(p, 1, 1, 1, 0)), "busy", "one game at a time")
	end)
	T.it("results: the best one counts; launch once all three are played", function()
		local p = fresh()
		board(p, { "action", "puzzle", "space" })
		Studio.make(p, 1, 2, 3, 0)
		T.eq(select(2, Studio.launch(p, 0)), "not_built")
		Studio.result(p, 1, true)
		Studio.result(p, 1, false)
		T.eq(p.project.won[1], 1, "a retry never loses a win")
		Studio.result(p, 2, false)
		T.eq(select(2, Studio.launch(p, 0)), "not_built", "one still unplayed")
		Studio.result(p, 3, false)
		Studio.result(p, 3, true)
		local cards = p.project.ideas
		local ok, game = Studio.launch(p, 1234)
		T.truthy(ok)
		T.eq(game.wins, 2)
		T.near(game.rate, Ideas.rate(cards, 2), 1e-9)
		T.eq(p.live.id, game.id, "on sale")
		T.near(p.live.top, game.rate / Tuning.CoinPerPlayer, 1e-6)
		T.eq(p.project, nil)
		T.eq(#p.games, 1)
		T.eq(p.stats.games, 1)
		T.eq(game.at, 1234)
		T.eq(p.tut, 3)
		T.eq(select(2, Studio.result(p, 1, true)), "no_project")
		T.eq(select(2, Studio.launch(p, 0)), "no_project")
	end)
	T.it("the list keeps the newest games; only the newest sells", function()
		local p = fresh()
		for _ = 1, Tuning.GamesKept + 5 do
			board(p, { "action", "puzzle", "space" })
			Studio.make(p, 1, 2, 3, 0)
			for i = 1, 3 do
				Studio.result(p, i, true)
			end
			Studio.launch(p, 0, 5)
		end
		T.eq(#p.games, Tuning.GamesKept)
		T.eq(p.live.id, p.games[#p.games].id)
	end)
	T.it("on sale: it earns from its players, peaks, leaves the shops; making the next takes it off", function()
		local p = fresh()
		board(p, { "action", "puzzle", "space" })
		Studio.make(p, 1, 2, 3, 0)
		for i = 1, 3 do
			Studio.result(p, i, true)
		end
		Studio.launch(p, 0, 77)
		local l = p.live
		local total, ended, endedAt = 0, false, 0
		for t = 1, Tuning.LiveLife + 10 do
			local c, e = Studio.sell(p, 1)
			total += c
			if e then
				ended, endedAt = true, t
			end
		end
		T.truthy(ended and endedAt == Tuning.LiveLife, "it leaves the shops at the end of its life")
		T.eq(l.players, 0)
		T.near(l.earned, total, 1e-6)
		T.eq(p.games[1].earned, math.floor(total + 0.5), "its record keeps its coins")
		T.eq(p.games[1].peak, l.peak)
		T.truthy(l.peak > l.samples[1], "its players climbed from the launch")
		T.eq(#l.samples, Tuning.LiveLife / Tuning.LiveSampleSec + 1)
		T.eq(l.samples[#l.samples], 0)
		T.eq(select(1, Studio.sell(p, 1)), 0, "off sale: nothing more")
		-- the next game, made while this one sells, takes it off
		board(p, { "action", "puzzle", "space" })
		Studio.make(p, 1, 2, 3, 0)
		for i = 1, 3 do
			Studio.result(p, i, false)
		end
		Studio.launch(p, 10, 3)
		for _ = 1, 30 do
			Studio.sell(p, 1)
		end
		local earned = p.live.earned
		board(p, { "action", "puzzle", "space" })
		Studio.make(p, 1, 2, 3, 0)
		T.eq(p.live, nil, "making a game takes the one on sale off")
		T.eq(p.games[2].earned, math.floor(earned), "it keeps what it made")
		T.eq(select(1, Studio.sell(p, 1)), 0)
	end)
	T.it("upgrades: prices grow, coins spent, speed stops at the floor", function()
		local p = fresh()
		T.eq(select(2, Studio.buyUpgrade(p, "speed")), "money")
		p.coins = 1e12
		local c0 = Studio.upgradeCost("speed", 0)
		T.truthy(Studio.buyUpgrade(p, "speed"))
		T.eq(p.coins, 1e12 - c0)
		T.eq(p.upgrades.speed, 1)
		T.truthy(Studio.upgradeCost("speed", 1) > c0)
		T.truthy(Studio.buyUpgrade(p, "luck"))
		T.eq(p.upgrades.luck, 1)
		T.near(Studio.luck(p), 1 + Tuning.LuckStep, 1e-9)
		T.eq(select(2, Studio.buyUpgrade(p, "wings")), "bad_payload")
		local guard = 0
		while Studio.buyUpgrade(p, "speed") and guard < 500 do
			guard += 1
		end
		T.eq(Studio.rollEvery(p), Tuning.RollMin)
		T.eq(select(2, Studio.buyUpgrade(p, "speed")), "max")
	end)
	T.it("earning, the founder's look", function()
		local p = fresh()
		Studio.earn(p, 50)
		T.eq(p.coins, Tuning.StartCoins + 50)
		T.eq(p.stats.earned, 50)
		T.truthy(Studio.setFounder(p, 2, 3, 4, 5))
		T.deepEq(p.founder, { skin = 2, hair = 3, style = 4, shirt = 5 })
		T.eq(select(2, Studio.setFounder(p, 9, 1, 1, 1)), "bad_payload")
	end)
end
