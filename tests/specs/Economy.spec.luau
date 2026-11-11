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
	T.it("the first minutes: a villager within 3 minutes, a driftling friend within 15", function()
		for seed, r in runs do
			T.truthy(r.first.villager and r.first.villager <= 180, "seed " .. seed .. ": villager at " .. tostring(r.first.villager))
			T.truthy(r.first.driftling and r.first.driftling <= 900, "seed " .. seed .. ": driftling at " .. tostring(r.first.driftling))
		end
	end)
	T.it("the islands: a guardian within 15 minutes; one of level 5 within 45, 10 within 90, 16 within 150", function()
		local by = { [1] = 900, [5] = 2700, [10] = 5400, [16] = 9000 }
		for seed, r in runs do
			for lvl, limit in by do
				local at1 = r.first["guardian" .. lvl]
				T.truthy(at1 and at1 <= limit, string.format("seed %d: a level %d guardian at %s", seed, lvl, tostring(at1)))
			end
			T.truthy(r.first.guardian23 == nil or r.first.guardian23 > 6000, "seed " .. seed .. ": the reefs are a long-term goal (past 100 minutes)")
		end
	end)
	T.it("the island grows: tier 2 within 45 minutes, tier 3 within 90; a village of villagers and friends", function()
		for seed, r in runs do
			T.truthy(r.first.tier2 and r.first.tier2 <= 2700, "seed " .. seed .. ": tier 2 at " .. tostring(r.first.tier2))
			T.truthy(r.first.tier3 and r.first.tier3 <= 5400, "seed " .. seed .. ": tier 3 at " .. tostring(r.first.tier3))
			local h1 = at(r, 60)
			T.truthy(h1.folk >= 8 and h1.pals >= 8, string.format("seed %d: hour 1 %d villagers %d driftlings", seed, h1.folk, h1.pals))
		end
	end)
	T.it("the town (tier 4) and beyond are long-term goals: never before 100 minutes", function()
		for seed, r in runs do
			T.truthy(r.first.tier4 == nil or r.first.tier4 > 6000, "seed " .. seed .. ": tier 4 at " .. tostring(r.first.tier4))
			T.truthy(r.first.tier5 == nil, "seed " .. seed .. ": no city in three hours")
		end
	end)
	T.it("nobody starves for long; the stores stay finite", function()
		for seed, r in runs do
			for _, row in r.timeline do
				T.truthy(row.foodRate > -40 or row.food > 50, string.format("seed %d at %dmin: food %d, %+.0f a day", seed, row.t // 60, row.food, row.foodRate))
			end
			local p = r.profile
			T.truthy(p.shells == p.shells and p.shells < 1e12 and p.wood < 1e12, "finite")
		end
	end)
end
