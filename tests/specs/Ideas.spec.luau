-- The idea team's rolls (Logic/Ideas; GAME_DESIGN 4): the odds rule and luck, the combined 1 in N, tiers, values,
-- difficulty, the board when full, titles.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Ideas = require("../../build/luautest/shared/Logic/Ideas")
local Util = require("../../build/luautest/shared/Logic/Util")
local IdeasData = require("../../build/luautest/shared/Data/Ideas")
local Modifiers = require("../../build/luautest/shared/Data/Modifiers")

local function sum(t: { number }): number
	local s = 0
	for _, v in t do
		s += v
	end
	return s
end

return function()
	T.it("chances sum to 1; Rare and rarer roll at luck / odds, Uncommon at 1 / odds", function()
		for _, luck in { 1, 2, 5, 50, 1e6 } do
			T.near(sum(Ideas.ideaChances(luck)), 1, 1e-9, "ideas at x" .. luck)
			T.near(sum(Ideas.modChances(luck)), 1, 1e-9, "modifiers at x" .. luck)
		end
		local c1, c3 = Ideas.ideaChances(1), Ideas.ideaChances(3)
		for i, d in IdeasData.list do
			T.truthy(c1[i] > 0, d.id .. " can roll")
			if d.odds >= Tuning.RareOdds then
				T.near(c1[i], 1 / d.odds, 1e-12, d.id .. " at x1")
				T.near(c3[i], 3 / d.odds, 1e-12, d.id .. " at x3")
			elseif d.odds >= Tuning.CommonOdds then
				T.near(c3[i], 1 / d.odds, 1e-12, d.id .. " luck leaves Uncommon alone")
			end
		end
		-- the commons' shown odds are about right at luck x1
		for i, d in IdeasData.list do
			if d.odds < Tuning.CommonOdds then
				T.truthy(math.abs(1 / c1[i] - d.odds) <= 1, d.id .. string.format(" 1 in %.1f", 1 / c1[i]))
			end
		end
		local m1 = Ideas.modChances(1)
		for i, m in Modifiers.list do
			if i > 1 then
				T.near(m1[i], 1 / m.odds, 1e-12, m.id)
			end
		end
	end)
	T.it("past the floor the lucky ones are scaled down: the commons keep their share", function()
		local c = Ideas.ideaChances(1e6)
		local com = 0
		for i, d in IdeasData.list do
			if d.odds < Tuning.CommonOdds then
				com += c[i]
			end
		end
		T.near(com, Tuning.CommonFloor, 1e-9)
		-- and the rarest still leads by its odds
		T.truthy(c[#c] < c[#c - 1])
	end)
	T.it("rolls follow the chances (100,000 seeded rolls)", function()
		local rng = Util.newRng(42)
		local n = 100000
		local ideas, mods = {}, {}
		for _ = 1, n do
			local card = Ideas.roll(rng, 1)
			ideas[card.id] = (ideas[card.id] or 0) + 1
			mods[card.mod] = (mods[card.mod] or 0) + 1
		end
		local c = Ideas.ideaChances(1)
		for i, d in IdeasData.list do
			local want = c[i] * n
			if want >= 200 then
				T.truthy(math.abs((ideas[d.id] or 0) - want) < want * 0.12, d.id)
			end
		end
		T.truthy(math.abs((mods.plain or 0) / n - Ideas.modChances(1)[1]) < 0.01, "plain")
		T.truthy((mods.turbo or 0) / n > 0.17 and (mods.turbo or 0) / n < 0.23, "turbo about 1 in 5")
	end)
	T.it("1 in N, tiers, names", function()
		T.eq(Ideas.oneIn({ id = "action", mod = "plain" }), 7)
		T.eq(Ideas.oneIn({ id = "music", mod = "cosmic" }), 6000 * 1000)
		T.eq(Ideas.tierOf(1), 1)
		T.eq(Ideas.tierOf(Tuning.TierOneIn[1]), 2)
		T.eq(Ideas.tierOf(1e9), #Tuning.TierNames)
		T.eq(Ideas.tierName(Ideas.tier({ id = "simulation", mod = "plain" })), "Epic")
		T.eq(Ideas.tierName(Ideas.tier({ id = "simulation", mod = "crowded" })), "Legendary")
		T.eq(Ideas.tierName(Ideas.tier({ id = "music", mod = "cosmic" })), "Mythic")
		T.eq(Ideas.name({ id = "ninjas", mod = "frenzy" }), "Frenzy Ninjas")
		T.eq(Ideas.name({ id = "ninjas", mod = "plain" }), "Ninjas")
	end)
	T.it("values: rarer ideas and modifiers earn more", function()
		local plain = Ideas.value({ id = "action", mod = "plain" })
		T.near(plain, Tuning.IdeaValue * 7 ^ Tuning.IdeaValuePow, 1e-9)
		T.truthy(Ideas.value({ id = "music", mod = "plain" }) > Ideas.value({ id = "rpg", mod = "plain" }))
		T.near(Ideas.value({ id = "action", mod = "shrinking" }), plain * Modifiers.byId.shrinking.mult, 1e-9)
		local three = { { id = "action", mod = "plain" }, { id = "puzzle", mod = "plain" }, { id = "space", mod = "plain" } }
		local base = Ideas.rate(three, 0)
		T.near(Ideas.rate(three, 3), base * 2, 1e-9, "three wins double it")
		T.near(Ideas.rate(three, 1), base * (1 + Tuning.WinBoost), 1e-9, "each win adds a third")
	end)
	T.it("difficulty: the tier, plus the reuse step, capped", function()
		T.eq(Ideas.difficulty({ id = "action", mod = "plain" }), 1)
		T.eq(Ideas.difficulty({ id = "space", mod = "plain" }), Ideas.tier({ id = "space", mod = "plain" }) + 1, "reusing Action's bombs: a step harder")
		T.eq(Ideas.difficulty({ id = "simulation", mod = "cosmic" }), Tuning.DiffMax)
		T.truthy(Ideas.difficulty({ id = "action", mod = "shrinking" }) > Ideas.difficulty({ id = "action", mod = "plain" }), "a rarer modifier: harder")
	end)
	T.it("speed and luck by level", function()
		T.eq(Ideas.rollEvery(0), Tuning.RollBase)
		T.truthy(Ideas.rollEvery(5) < Ideas.rollEvery(4))
		T.eq(Ideas.rollEvery(500), Tuning.RollMin)
		T.eq(Ideas.luck(0), 1)
		T.near(Ideas.luck(5), 1 + 5 * Tuning.LuckStep, 1e-9)
	end)
	T.it("the board: room first, then a rarer idea takes the commonest one's place", function()
		local board = {}
		for i = 1, Tuning.BoardSize do
			local slot = Ideas.place(board, { id = if i == 3 then "action" else "puzzle", mod = "plain" })
			T.eq(slot, i)
		end
		T.eq(select(1, Ideas.place(board, { id = "action", mod = "plain" })), 0, "not rarer than the commonest: dropped")
		local slot, old = Ideas.place(board, { id = "rpg", mod = "plain" })
		T.eq(slot, 3, "the action (1 in 7) goes")
		T.eq(old and old.id, "action")
		T.eq(#board, Tuning.BoardSize)
	end)
	T.it("titles: a word per idea, themes before genres, seeded", function()
		local cards = { { id = "puzzle", mod = "plain" }, { id = "space", mod = "plain" }, { id = "pirates", mod = "turbo" } }
		local t = Ideas.title(cards, 5)
		T.eq(Ideas.title(cards, 5), t)
		local words = string.split(t, " ")
		T.eq(#words, 3)
		T.truthy(table.find(IdeasData.byId.puzzle.words, words[3]) ~= nil, "the genre's word last: " .. t)
	end)
	T.it("valid cards", function()
		T.truthy(Ideas.valid({ id = "action", mod = "plain" }))
		T.truthy(not Ideas.valid({ id = "action", mod = "golden" }))
		T.truthy(not Ideas.valid({ id = "chess", mod = "plain" }))
		T.truthy(not Ideas.valid("action"))
	end)
end
