-- Whole sessions through the island's own rules by a sensible player (tests/Career.luau): the pacing stays inside the
-- bounds GAME_DESIGN 10 promises. Print a session with: luau tests/career.luau -a <seed> [minutes] (after the check
-- has built build/luautest).
local T = require("../TestKit")
local Career = require("../Career")

local SEEDS = { 1, 2, 3 }
local MINUTES = 180

return function()
	local runs = {}
	for _, seed in SEEDS do
		runs[seed] = Career.play(seed, MINUTES * 60)
	end
	local function at(r: any, minute: number): any
		return r.timeline[minute // 10]
	end
	T.it("the first minutes: a driftling at work within 3 minutes, a rare one within 20", function()
		for seed, r in runs do
			T.truthy(r.first.helper and r.first.helper <= 180, "seed " .. seed .. ": a driftling at work at " .. tostring(r.first.helper))
			T.truthy(r.first.rarity3 and r.first.rarity3 <= 1200, "seed " .. seed .. ": a rare one at " .. tostring(r.first.rarity3))
		end
	end)
	T.it("the eggs: a dozen hatched by half an hour, an epic within two hours", function()
		for seed, r in runs do
			local row = at(r, 30)
			T.truthy(row.taken >= 12, string.format("seed %d: %d taken in by 30 minutes", seed, row.taken))
			T.truthy(r.first.rarity4 and r.first.rarity4 <= 7200, "seed " .. seed .. ": an epic at " .. tostring(r.first.rarity4))
		end
	end)
	T.it("selling driftlings helps but the island earns: under two thirds of the shells over three hours", function()
		for seed, r in runs do
			local p = r.profile
			T.truthy(r.sold < p.stats.earned * 0.67, string.format("seed %d: sold %d of %d", seed, r.sold, p.stats.earned))
		end
	end)
	T.it("the island grows: tier 2 within 25 minutes, tier 3 within 50; a dozen driftlings in huts at an hour", function()
		for seed, r in runs do
			T.truthy(r.first.tier2 and r.first.tier2 <= 1500, "seed " .. seed .. ": tier 2 at " .. tostring(r.first.tier2))
			T.truthy(r.first.tier3 and r.first.tier3 <= 3000, "seed " .. seed .. ": tier 3 at " .. tostring(r.first.tier3))
			local h1 = at(r, 60)
			T.truthy(h1.pals >= 12, string.format("seed %d: hour 1 %d driftlings in huts", seed, h1.pals))
		end
	end)
	T.it("the town (tier 4) and beyond are long-term goals: not before an hour, a city not before two, no capital in three", function()
		for seed, r in runs do
			T.truthy(r.first.tier4 == nil or r.first.tier4 > 3600, "seed " .. seed .. ": tier 4 at " .. tostring(r.first.tier4))
			T.truthy(r.first.tier5 == nil or r.first.tier5 > 7200, "seed " .. seed .. ": tier 5 at " .. tostring(r.first.tier5))
			T.truthy(r.first.tier6 == nil, "seed " .. seed .. ": no capital in three hours")
		end
	end)
	T.it("both stores make and get spent; they stay finite", function()
		for seed, r in runs do
			for _, row in r.timeline do
				T.truthy(row.woodRate > 0 and row.shellRate > 0, string.format("seed %d at %dmin: wood %+.0f, shells %+.0f a turn", seed, row.t // 60, row.woodRate, row.shellRate))
			end
			local p = r.profile
			T.truthy(p.shells == p.shells and p.shells < 1e12 and p.wood < 1e12, "finite")
			T.eq((p :: any).food, nil, "no food")
		end
	end)
end
