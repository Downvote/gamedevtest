-- The game on sale (Logic/Live; GAME_DESIGN 6): its curve climbs to a peak and falls to none, wobbles the same way
-- every time for the same seed, and pays its players' coins.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Live = require("../../build/luautest/shared/Logic/Live")

local function game(rate: number): any
	return { id = 1, title = "A", ideas = {}, rate = rate, wins = 0, at = 0, peak = 0, earned = 0 }
end

return function()
	T.it("the shape: from LiveStart up to 1 at LivePeakAt, down to none at the end", function()
		T.near(Live.shape(0), Tuning.LiveStart, 1e-9)
		T.near(Live.shape(Tuning.LivePeakAt), 1, 1e-9)
		T.eq(Live.shape(1), 0)
		local last = -1
		for i = 0, 20 do
			local s = Live.shape(Tuning.LivePeakAt * i / 20)
			T.truthy(s >= last, "climbing")
			last = s
		end
		for i = 1, 20 do
			local s = Live.shape(Tuning.LivePeakAt + (1 - Tuning.LivePeakAt) * i / 20)
			T.truthy(s <= last, "falling")
			last = s
		end
	end)
	T.it("it wobbles: never below the floor, not flat, the same for the same seed", function()
		local lo, hi = math.huge, 0
		for age = 0, Tuning.LiveLife - 1 do
			local w = Live.wobble(5, age, Tuning.LiveLife)
			lo, hi = math.min(lo, w), math.max(hi, w)
			T.eq(w, Live.wobble(5, age, Tuning.LiveLife))
		end
		T.truthy(lo >= Tuning.LiveFloor and hi - lo > 0.15, string.format("%.2f .. %.2f", lo, hi))
		T.truthy(Live.wobble(5, 40, 300) ~= Live.wobble(6, 40, 300), "another seed, another wobble")
	end)
	T.it("a life on sale: players peak near the top of the curve, the coins are the players' earnings", function()
		local l = Live.new(game(20), 9)
		T.eq(l.top, 20 / Tuning.CoinPerPlayer)
		T.eq(Live.phase(l), "rising")
		local sum = 0
		for _ = 1, Tuning.LiveLife do
			sum += (Live.step(l, 1))
		end
		T.truthy(Live.over(l) and Live.phase(l) == "off" and Live.earning(l) == 0)
		T.truthy(l.peak > l.top * 0.7 and l.peak < l.top * 2, string.format("peak %d of %d", l.peak, l.top))
		T.near(l.earned, sum, 1e-6)
		local expect = Live.lifetime(20)
		T.truthy(sum > expect * 0.7 and sum < expect * 1.5, string.format("%.0f vs about %.0f", sum, expect))
	end)
	T.it("steps of any size draw the same curve", function()
		local a, b = Live.new(game(8), 3), Live.new(game(8), 3)
		for _ = 1, 600 do
			Live.step(a, 0.1)
		end
		for _ = 1, 60 do
			Live.step(b, 1)
		end
		T.eq(a.players, b.players)
		T.deepEq(a.samples, b.samples)
		T.near(a.earned, b.earned, b.earned * 0.03)
	end)
end
