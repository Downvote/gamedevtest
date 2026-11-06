local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Dev = require("../../build/luautest/shared/Logic/Dev")
local Crew = require("../../build/luautest/shared/Logic/Crew")
local Util = require("../../build/luautest/shared/Logic/Util")
local Genres = require("../../build/luautest/shared/Data/Genres")
local Topics = require("../../build/luautest/shared/Data/Topics")

local function staff(n: number, skill: number): { any }
	local out = {}
	for i = 1, n do
		local sk = { code = skill, design = skill, art = skill, sound = skill }
		table.insert(out, { id = i, name = "D" .. i, skills = sk, energy = 100, salary = Crew.salary(sk), look = {}, desk = i, trained = 0 })
	end
	return out
end

return function()
	T.it("matches", function()
		T.eq(Dev.match("puzzle", "animals"), "great")
		T.eq(Dev.match("puzzle", "cooking"), "good")
		T.eq(Dev.match("puzzle", "zombies"), "poor")
		T.eq(Dev.match("puzzle", "pirates"), "okay")
		T.eq(Dev.match("nope", "space"), "okay")
	end)
	T.it("titles walk every word pair and sequels count up", function()
		local seen = {}
		for seed = 0, 24 do
			seen[Dev.title("puzzle", "space", seed)] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		T.eq(n, 25)
		T.eq(Dev.title("puzzle", "space", 0), "Galaxy Blocks")
		T.eq(Dev.title("puzzle", "space", 25), "Galaxy Blocks")
		local rel = { { title = "Galaxy Blocks" }, { title = "Galaxy Blocks 2" } } :: any
		T.eq(Dev.sequelTitle("Galaxy Blocks", rel), "Galaxy Blocks 3")
		T.eq(Dev.sequelTitle("Star Blocks", rel), "Star Blocks")
	end)
	T.it("platforms on sale by year", function()
		local function ids(year: number): string
			local out = {}
			for _, p in Dev.platformsIn(year) do
				table.insert(out, p.id)
			end
			return table.concat(out, ",")
		end
		T.eq(ids(1), "pc,pocket")
		T.eq(ids(3), "pc,pocket,bytebox")
		T.eq(ids(11), "pc,bytebox,phone,orbit")
		T.eq(ids(15), "pc,phone,orbit,cloud")
	end)
	T.it("a build fills the four scores, counts the weeks and turns to polish", function()
		local p = Dev.newProject("puzzle", "space", "pc", "small", "fun", "Galaxy Blocks", 0)
		local crew = staff(2, 20)
		local rng = Util.newRng(3)
		for w = 1, Tuning.Sizes.small.weeks do
			T.eq(p.phase, "build")
			local pops, rp = Dev.workWeek(p, crew, rng)
			T.eq(#pops, 2)
			T.truthy(rp >= 2)
			T.eq(p.weeksDone, w)
		end
		T.eq(p.phase, "polish")
		T.truthy(p.scores.fun > p.scores.ideas * 1.15, "the focus shows")
		T.truthy(p.scores.graphics > 0 and p.scores.sound > 0)
		-- polish fixes bugs and adds a little
		p.bugs = 20
		local fun = p.scores.fun
		Dev.workWeek(p, crew, rng)
		T.eq(p.bugs, 20 - 2 * (Tuning.FixBase + 20 // Tuning.FixCode))
		T.truthy(p.scores.fun > fun and p.scores.fun < fun + 20)
	end)
	T.it("tired developers do half the work", function()
		local a = Dev.newProject("puzzle", "space", "pc", "small", "fun", "A", 0)
		local b = Dev.newProject("puzzle", "space", "pc", "small", "fun", "B", 0)
		local fresh, tired = staff(1, 40), staff(1, 40)
		tired[1].energy = 0
		Dev.workWeek(a, fresh, Util.newRng(9))
		Dev.workWeek(b, tired, Util.newRng(9))
		T.near(b.scores.graphics / a.scores.graphics, Tuning.TiredRate, 0.05)
	end)
	T.it("review scores: Q = E is 5.5, more is better, never past 1..10", function()
		T.near(Dev.baseScore(500, 500), 5.5, 1e-9)
		T.truthy(Dev.baseScore(1000, 500) > Dev.baseScore(500, 500))
		T.truthy(Dev.baseScore(1e9, 500) <= 10 and Dev.baseScore(0, 500) == 1)
		local rng = Util.newRng(11)
		for _, fun in { 0, 100, 400, 2000, 50000 } do
			local p = Dev.newProject("puzzle", "animals", "pc", "small", "fun", "X", 0)
			p.scores = { fun = fun, ideas = fun, graphics = fun, sound = fun }
			p.phase = "polish"
			local reviews, total, m = Dev.reviews(p, 1, {}, rng)
			T.eq(#reviews, 4)
			T.eq(m, "great")
			local sum = 0
			for _, v in reviews do
				T.truthy(v >= 1 and v <= 10 and v == math.floor(v))
				sum += v
			end
			T.eq(total, sum)
		end
	end)
	T.it("quality: match, platform love, novelty and bugs", function()
		local p = Dev.newProject("puzzle", "animals", "pocket", "small", "fun", "X", 0)
		p.scores = { fun = 100, ideas = 100, graphics = 100, sound = 100 }
		local raw = 100 * (1 + 0.8 + 0.8 + 0.6)
		local q = Dev.quality(p, {})
		T.near(q, raw * 1.3 * 1.1, 1e-6, "great match, loved on the Pocket Pal")
		local again = Dev.quality(p, { { genre = "puzzle", topic = "animals" } } :: any)
		T.near(again, q * Tuning.NoveltyMult, 1e-6, "the same pair again")
		p.bugs = 4
		T.near(Dev.quality(p, {}), q - 4 * Tuning.BugPenalty, 1e-6)
	end)
	T.it("critics expect more every year and of bigger games", function()
		T.truthy(Dev.expectation("small", 5) > Dev.expectation("small", 1))
		T.truthy(Dev.expectation("large", 1) > Dev.expectation("medium", 1))
	end)
	T.it("sales: a better game sells more and longer, and leaves the shelves", function()
		local lo, dlo = Dev.salesPlan(20, 0, "pc", "small")
		local hi, dhi = Dev.salesPlan(32, 0, "pc", "small")
		T.truthy(hi > lo * 2 and dhi > dlo)
		local p = Dev.newProject("puzzle", "animals", "pc", "small", "fun", "X", 0)
		local r = Dev.release(p, 1, 10, { 6, 6, 6, 6 }, 24, "great", 0)
		T.eq(r.peak, math.floor(Tuning.SalesBase * (6 / Tuning.SalesPivot) ^ Tuning.SalesPower + 0.5))
		local weeks, total = 0, 0
		while r.onSale and weeks < 100 do
			local c, m = Dev.salesWeek(r)
			total += c
			weeks += 1
			T.truthy(m == math.floor(c * Tuning.Sizes.small.price * Tuning.StudioCut + 0.5))
		end
		T.truthy(not r.onSale and weeks <= Tuning.SalesMaxWeeks)
		T.eq(r.copies, total)
	end)
	T.it("awards pick the year's best game", function()
		local rel = { { title = "A", total = 30, week = 10 }, { title = "B", total = 35, week = 40 }, { title = "C", total = 40, week = 50 } } :: any
		local kind, best = Dev.award(rel, 1, 48)
		T.eq(kind, "goty")
		T.eq((best :: any).title, "B")
		local k2 = Dev.award({ { title = "A", total = 29, week = 1 } } :: any, 1, 48)
		T.eq(k2, "pick")
		T.eq(Dev.award({ { title = "A", total = 10, week = 1 } } :: any, 1, 48), nil)
	end)
	T.it("research costs by tier", function()
		T.eq(Dev.genreCost("action"), 0)
		T.eq(Dev.genreCost("horror"), Tuning.GenreRp[3])
		T.eq(Dev.topicCost("robots"), Tuning.TopicRp[2])
		T.truthy(#Genres.list > 0 and #Topics.list > 0)
	end)
end
