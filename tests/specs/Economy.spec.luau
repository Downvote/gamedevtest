-- Whole sessions through Logic/Studio (the server's own rules) by a sensible player (tests/Career.luau): the pacing
-- stays inside the bounds GAME_DESIGN 10 promises. Print a session with: luau tests/career.luau -a <seed> [minutes]
-- [skill] (after the check has built build/luautest).
local T = require("../TestKit")
local Career = require("../Career")

local SEEDS = { 1, 2, 3, 4 }
local MINUTES = 180

return function()
	local runs = {}
	for _, seed in SEEDS do
		runs[seed] = Career.play(seed, MINUTES * 60)
	end
	local function at(r: any, minute: number): any
		return r.timeline[minute // 10]
	end
	T.it("the first minutes: a game launched and an upgrade bought within 4 minutes", function()
		for seed, r in runs do
			T.truthy(r.firstGame and r.firstGame <= 240, "seed " .. seed .. ": first game at " .. tostring(r.firstGame))
			T.truthy(r.firstUpgrade and r.firstUpgrade <= 240, "seed " .. seed .. ": first upgrade at " .. tostring(r.firstUpgrade))
		end
	end)
	T.it("finds: a Rare within 10 minutes, an Epic within 30, no Mythic in the first hour", function()
		for seed, r in runs do
			T.truthy(r.firstTier[3] and r.firstTier[3] <= 600, "seed " .. seed .. ": Rare at " .. tostring(r.firstTier[3]))
			T.truthy(r.firstTier[4] and r.firstTier[4] <= 1800, "seed " .. seed .. ": Epic at " .. tostring(r.firstTier[4]))
			T.truthy(r.firstTier[6] == nil or r.firstTier[6] > 3600, "seed " .. seed .. ": Mythic at " .. tostring(r.firstTier[6]))
		end
	end)
	T.it("upgrades: twelve to eighteen levels each in the first hour, a few more by the third", function()
		for seed, r in runs do
			local h1, h3 = at(r, 60), at(r, 180)
			T.truthy(h1.speed >= 12 and h1.speed <= 18 and h1.luck >= 12 and h1.luck <= 18, string.format("seed %d: hour 1 speed %d luck %d", seed, h1.speed, h1.luck))
			T.truthy(h3.speed > h1.speed and h3.luck > h1.luck, "seed " .. seed .. ": still climbing")
			T.truthy(h3.speed <= 22 and h3.luck <= 22, string.format("seed %d: hour 3 speed %d luck %d", seed, h3.speed, h3.luck))
		end
	end)
	T.it("no runaway: the next upgrade takes 5 to 60 minutes of income by hour 3, the income grows slower than x6", function()
		for seed, r in runs do
			local h1, h3 = at(r, 60), at(r, 180)
			T.truthy(h3.wait >= 300 and h3.wait <= 3600, string.format("seed %d: wait %.0f s", seed, h3.wait))
			T.truthy(h3.rate < h1.rate * 6, string.format("seed %d: %.0f -> %.0f a second", seed, h1.rate, h3.rate))
			T.truthy(r.profile.coins == r.profile.coins and r.profile.coins < 1e12, "seed " .. seed .. ": finite")
		end
	end)
	T.it("the minigames pay: winning them all earns about twice as much as losing them all", function()
		local good = Career.play(1, 30 * 60, { skill = 1, retries = 0 })
		local bad = Career.play(1, 30 * 60, { skill = 0, retries = 0 })
		local ratio = good.profile.stats.earned / bad.profile.stats.earned
		T.truthy(ratio >= 1.4 and ratio <= 2.8, string.format("x%.2f", ratio))
	end)
	T.it("one game sells at a time: each one rises, peaks and leaves the shops", function()
		for seed, r in runs do
			local g = r.profile.games
			T.truthy(#g >= 20, "seed " .. seed .. ": " .. #g .. " games")
			local old = g[#g - 1]
			T.truthy(old.peak > 0 and old.earned > 0, string.format("seed %d: an old game's peak %d, coins %d", seed, old.peak, old.earned))
		end
	end)
end
