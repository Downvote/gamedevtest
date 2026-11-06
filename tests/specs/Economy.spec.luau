-- Whole careers through Logic/Studio (the server's own rules) by a sensible player (tests/Career.luau): the economy
-- stays inside the bounds GAME_DESIGN promises. Print a career with: luau tests/career.luau -a <seed> (after the
-- check has built build/luautest).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Career = require("../Career")

local SEEDS = { 1, 2, 3, 4, 5, 6 }
local YEARS = 10

return function()
	local runs, played = {}, {}
	for _, seed in SEEDS do
		runs[seed] = Career.play(seed, YEARS)
		played[seed] = Career.play(seed, YEARS, nil, 80)
	end
	T.it("the first year: a few games out, the studio still afloat", function()
		for seed, r in runs do
			local y1 = r.yearly[1]
			T.truthy(y1.games >= 2, "seed " .. seed .. ": two or more games in year 1")
			T.truthy(y1.avg >= 15 and y1.avg <= 28, "seed " .. seed .. ": first reviews middling, got " .. y1.avg)
			T.truthy(y1.money > 0, "seed " .. seed .. ": in the black after year 1")
		end
	end)
	T.it("offices: the Loft in years 2-4, the Studio Floor by year 6", function()
		for seed, r in runs do
			local loft, studio = 99, 99
			for _, row in r.yearly do
				if row.office >= 2 then
					loft = math.min(loft, row.year)
				end
				if row.office >= 3 then
					studio = math.min(studio, row.year)
				end
			end
			T.truthy(loft >= 2 and loft <= 4, "seed " .. seed .. ": Loft in year " .. loft)
			T.truthy(studio <= 6, "seed " .. seed .. ": Studio Floor in year " .. studio)
		end
	end)
	T.it("reviews climb as the studio grows, and a Hall of Fame game comes", function()
		for seed, r in runs do
			local late = r.yearly[YEARS].avg
			if late == 0 then
				late = r.yearly[YEARS - 1].avg
			end
			T.truthy(late >= r.yearly[1].avg + 5, "seed " .. seed .. ": better games later")
			T.truthy(r.profile.stats.hof >= 1, "seed " .. seed .. ": a Hall of Fame game")
			T.truthy(r.profile.stats.best <= 40)
		end
	end)
	T.it("no runaway: fans grow, but not exponentially", function()
		for seed, r in runs do
			for i = 2, #r.yearly do
				local a, b = r.yearly[i - 1].fans, r.yearly[i].fans
				T.truthy(b >= a, "seed " .. seed .. ": fans never shrink")
				if a > 50000 then
					T.truthy(b < a * 2.5, string.format("seed %d: fans at most x2.5 a year (year %d: %d -> %d)", seed, i, a, b))
				end
			end
			T.truthy(r.profile.fans < 1e8 and r.profile.money == r.profile.money, "seed " .. seed .. ": finite")
		end
	end)
	T.it("minigames (GAME_DESIGN 14): a player who plays them well makes better games, still inside the bounds", function()
		local sumA, sumB, n = 0, 0, 0
		for seed, r in played do
			local base = runs[seed]
			T.truthy(r.yearly[1].money > 0, "seed " .. seed .. ": afloat after year 1")
			T.truthy(r.yearly[1].avg <= 30, "seed " .. seed .. ": first reviews still modest, got " .. r.yearly[1].avg)
			T.truthy(r.profile.stats.best <= 40)
			for i = 2, #r.yearly do
				local a, b = r.yearly[i - 1].fans, r.yearly[i].fans
				if a > 50000 then
					T.truthy(b < a * 2.5, string.format("seed %d: fans at most x2.5 a year (year %d)", seed, i))
				end
			end
			for i = 1, 3 do
				sumA += base.yearly[i].avg
				sumB += r.yearly[i].avg
				n += 1
			end
		end
		T.truthy(sumB / n >= sumA / n + 1, string.format("better early reviews: %.1f vs %.1f", sumB / n, sumA / n))
		T.truthy(sumB / n <= sumA / n + 6, string.format("but not a different game: %.1f vs %.1f", sumB / n, sumA / n))
	end)
	T.it("the safety net: a broke studio can still start a small Home PC game", function()
		local p = runs[1].profile
		p.project = nil
		p.money = -5000
		local Studio = require("../../build/luautest/shared/Logic/Studio")
		local ok, err = Studio.start(p, { genre = "action", topic = "space", platform = "phone", size = "small", focus = "fun", seed = 1 })
		T.eq(ok, false)
		T.eq(err, "money")
		ok = Studio.start(p, { genre = "action", topic = "space", platform = Tuning.RescuePlatform, size = Tuning.RescueSize, focus = "fun", seed = 1 })
		T.truthy(ok)
		T.eq(p.money, -5000, "for free")
	end)
end
