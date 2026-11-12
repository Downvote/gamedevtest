-- What makes one driftling unlike another (Data/Traits; GAME_DESIGN 6): the mutations' tiers, a roll's rules (no
-- family twice, at most three, rarer kinds rolling better), the sums, the work shares and cleaning a save's list.
local T = require("../TestKit")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Util = require("../../build/luautest/shared/Logic/Util")

return function()
	T.it("ten families of four tiers and the flaws; a higher tier gives more", function()
		T.eq(#Traits.families, 10)
		for _, f in Traits.families do
			for tier = 1, 4 do
				local m = Traits.byId[f.family .. tier]
				T.truthy(m ~= nil and m.tier == tier and m.fx[f.key] ~= nil, f.family .. tier)
				if tier > 1 then
					T.truthy(math.abs(m.fx[f.key]) > math.abs(Traits.byId[f.family .. (tier - 1)].fx[f.key]), "tier " .. tier .. " beats " .. (tier - 1))
				end
			end
		end
		local flaws = 0
		for _, m in Traits.list do
			if m.tier == 0 then
				flaws += 1
				for k, v in m.fx do
					-- (eating more is the flaw; less of anything else)
					T.truthy(if k == "eat" then v > 0 else v < 0, m.id .. " is a flaw")
				end
			end
		end
		T.truthy(flaws >= 3)
		T.eq(Traits.at("sturdy", 9), "sturdy4", "clamped to 4")
		T.eq(Traits.at("sturdy", 0), "sturdy1")
	end)
	T.it("a roll: up to three, no family twice, only known ids", function()
		local rng = Util.newRng(3)
		local counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
		for _ = 1, 3000 do
			local muts = Traits.roll(rng, rng:int(1, 5))
			T.truthy(#muts <= 3)
			counts[#muts] += 1
			local fam: { [string]: boolean } = {}
			for _, id in muts do
				local m = Traits.byId[id]
				T.truthy(m ~= nil, id)
				T.truthy(not fam[m.family], "a family once")
				fam[m.family] = true
			end
		end
		for n = 0, 3 do
			T.truthy(counts[n] > 0, n .. " mutations happen")
		end
		T.truthy(counts[1] > counts[3], "one is commoner than three")
	end)
	T.it("a rarer kind rolls better: more of the top tiers, fewer flaws", function()
		local function tally(rarity: number): (number, number)
			local rng = Util.newRng(11)
			local top, flaws = 0, 0
			for _ = 1, 4000 do
				for _, id in Traits.roll(rng, rarity) do
					local t = Traits.byId[id].tier
					if t >= 3 then
						top += 1
					elseif t == 0 then
						flaws += 1
					end
				end
			end
			return top, flaws
		end
		local top1, flaws1 = tally(1)
		local top5, flaws5 = tally(5)
		T.truthy(top5 > top1 * 1.3, "legends roll more tier 3 and 4")
		T.truthy(flaws5 < flaws1, "and fewer flaws")
	end)
	T.it("sums: the passive and the mutations together; work at a knack", function()
		local fx = Traits.sum({ eat = -0.1, farm = 0.15 }, { "sturdy2", "grower1", "lazy", "nope" })
		T.near(fx.eat, -0.4, 1e-9)
		T.near(fx.farm, 0.27, 1e-9)
		T.near(fx.work, -0.15, 1e-9)
		T.near(Traits.workAt(fx, "farm"), 0.12, 1e-9)
		T.near(Traits.workAt(fx, "wood"), -0.15, 1e-9)
		T.eq(Traits.workAt({ work = -3 }, "farm"), -0.5, "never below -50%")
		T.eq(Traits.describe({ eat = -0.3, farm = 0.27 }), "+27% at farms, eats 30% less")
		T.eq(Traits.describe({ work = -0.15 }), "-15% work")
		T.eq(Traits.describe({ charm = 2, sell = 0.7, tree = 0.08, luck = 0.1 }), "+70% sell price, +2 charm, +8% tree speed, +10% tree luck")
		T.eq(Traits.describe({}), "")
	end)
	T.it("cleaning a save's list: known ids, a family once, at most four", function()
		T.deepEq(Traits.clean({ "swift2", "swift4", "x", 5, "lazy", "busy1", "fierce1", "armor3", "bright1" }), { "swift2", "lazy", "fierce1", "armor3" }, "Lazy and Diligent: one family")
		T.eq(Traits.byId.frail.blurb, "eats 25% more")
		T.eq(Traits.byId.sturdy2.blurb, "eats 30% less")
		T.eq(Traits.byId.fierce3.name, "Golden")
		T.eq(Traits.byId.bright1.blurb, "+5% tree luck")
		T.deepEq(Traits.clean(nil), {})
		T.deepEq(Traits.clean("sturdy1"), {})
	end)
end
