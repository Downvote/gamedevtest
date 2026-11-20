-- What makes one driftling unlike another (Data/Traits; GAME_DESIGN 6): the mutations' tiers, a roll's rules (no
-- family twice, at most three, rarer kinds rolling better), the sums, the work shares and cleaning a save's list.
local T = require("../TestKit")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Palette = require("../../build/luautest/shared/Data/Palette")
local Util = require("../../build/luautest/shared/Logic/Util")

return function()
	T.it("nine rarities (Mythic and Celestial past Legendary, 2026-11-14; Ancient and Eternal past them, 2026-11-20), each table by rarity as long, rarer is dearer and faster", function()
		T.eq(Traits.RMAX, 9)
		T.eq(#Traits.RARITY, Traits.RMAX)
		T.eq(Traits.RARITY[6].name, "Mythic")
		T.eq(Traits.RARITY[7].name, "Celestial")
		T.eq(Traits.RARITY[8].name, "Ancient")
		T.eq(Traits.RARITY[9].name, "Eternal")
		for r, rd in Traits.RARITY do
			T.truthy(Palette.ui[rd.color] ~= nil or Palette.colors[rd.color] ~= nil, rd.name .. ": a colour")
			if r > 1 then
				T.truthy(rd.weight < Traits.RARITY[r - 1].weight, rd.name .. " rarer than " .. Traits.RARITY[r - 1].name)
			end
		end
		-- (much rarer than legendary: a mythic egg's weight a sixtieth of a legendary one's, a celestial one a tenth of that)
		T.truthy(Traits.RARITY[6].weight * 20 <= Traits.RARITY[5].weight and Traits.RARITY[7].weight * 5 <= Traits.RARITY[6].weight, "far rarer")
		-- (an ancient egg's weight under a thirtieth of a celestial one's, an eternal one's a fortieth of that: "much rarer")
		T.truthy(Traits.RARITY[8].weight * 30 <= Traits.RARITY[7].weight and Traits.RARITY[9].weight * 40 <= Traits.RARITY[8].weight, "much rarer still")
		-- (the colours are their own: no two rarities share one)
		local cols: { [string]: boolean } = {}
		for _, rd in Traits.RARITY do
			T.truthy(not cols[rd.color], rd.name .. ": a colour of its own")
			cols[rd.color] = true
		end
		for name, t in { RarityWork = Tuning.RarityWork, EggPrice = Tuning.EggPrice, SellPrice = Tuning.SellPrice, BreedShells = Tuning.BreedShells, BreedTurns = Tuning.BreedTurns, ShopWeight = Tuning.ShopWeight, CosmeticPrice = Tuning.CosmeticPrice } do
			T.eq(#t, Traits.RMAX, name .. ": one a rarity")
			for r = 2, #t do
				if name == "ShopWeight" then
					T.truthy(t[r] < t[r - 1], name .. " shrinks with the rarity at " .. r)
				else
					T.truthy(t[r] > t[r - 1], name .. " grows with the rarity at " .. r)
				end
			end
		end
		T.eq(#Tuning.EggUp, Traits.RMAX - 1, "EggUp: a step from each rarity but the rarest")
		local rng = Util.newRng(5)
		for _, r in { 6, 7, 8, 9, 99 } do
			for _ = 1, 50 do
				local muts = Traits.roll(rng, r)
				T.truthy(#muts <= Traits.MAX and #Traits.clean(muts) == #muts, "a clean roll at rarity " .. r)
			end
		end
	end)

	T.it("eight families of four tiers and the flaws; a higher tier gives more", function()
		-- (the Angler family went with fishing on 2026-11-14, the Leafy family with the tree's shorter waits the same day:
		-- below)
		T.eq(#Traits.families, 8)
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
					-- (costing more is the flaw; less of anything else)
					T.truthy(if k == "cost" then v > 0 else v < 0, m.id .. " is a flaw")
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
	T.it("sums: the passive and the mutations together; work is one share everywhere (2026-11-19)", function()
		local fx = Traits.sum({ cost = -0.1, work = 0.15 }, { "sturdy2", "busy1", "grower1", "lazy", "nope" })
		T.near(fx.cost, -0.4, 1e-9)
		-- (a Lazy one and a Busy one are one family: clean keeps the first, sum takes the list as given)
		T.near(fx.work, 0.15 + 0.12 - 0.15, 1e-9)
		T.near(fx.hatch, 0.06, 1e-9, "the Grower family shortens the Hatchery now")
		T.near(Traits.work(fx), 0.12, 1e-9)
		T.eq(Traits.work({ work = -3 }), -0.5, "never below -50%")
		T.eq((Traits :: any).workAt, nil, "no work at a knack")
		T.eq(Traits.describe({ cost = -0.3, work = 0.27 }), "+27% work, eggs cost 30% less")
		T.eq(Traits.describe({ work = -0.15 }), "-15% work")
		T.eq(Traits.describe({ charm = 2, sell = 0.7, luck = 0.1 }), "+2 charm, +10% egg luck, +70% sell price")
		T.eq(Traits.describe({ hatch = 0.12, boost = 0.2, charmPct = 0.08 }), "Hatchery 12% faster, +20% boost buildings, +8% charm")
		T.eq(Traits.describe({ eggs = 1, all = 0.15 }), "+15% all coins, +1 egg per lot")
		-- (nothing brings the tree's eggs sooner any more, and farms, wood and shops are no kinds of work now)
		T.eq(Traits.describe({ tree = 0.08, farm = 0.2 }), "")
		T.eq(Traits.describe({}), "")
	end)
	T.it("the request of 2026-11-19: the kinds of work's families give Hatchery time, boost buildings and charm shares", function()
		T.eq(Traits.byId.grower1.fx.hatch, 0.06)
		T.eq(Traits.byId.chopper2.fx.boost, 0.12)
		T.eq(Traits.byId.trader3.fx.charmPct, 0.14)
		T.eq(Traits.byId.armor2.fx.charm, 2, "flat charm kept")
		for _, f in Traits.weather do
			T.truthy(f.key ~= "farm" and f.key ~= "wood" and f.key ~= "shop", f.family .. " no kind of work")
		end
		for _, m in Traits.list do
			for k in m.fx do
				T.truthy(table.find(Traits.KEYS, k) ~= nil, m.id .. ": " .. k .. " a known effect")
			end
		end
	end)
	T.it("the wondrous mutations (tier 5): each its own family and effect, very seldom rolled, more for rarer kinds", function()
		T.eq(Traits.TOP, 6, "the fabled tier above it since 2026-11-20")
		T.truthy(#Traits.wonders >= 5)
		local keys: { [string]: boolean } = {}
		for _, w in Traits.wonders do
			local m = Traits.byId[w.family .. "5"]
			T.truthy(m ~= nil and m.tier == 5 and m.name == w.name, w.family .. "5")
			T.eq(Traits.at(w.family, 2), m.id, "one tier: its own")
			T.truthy(Traits.TIER_COLOR[5] ~= nil and Traits.TIER_NAME[5] == "Wondrous")
			for k in m.fx do
				keys[k] = true
			end
		end
		-- (effects nothing at tiers 1 to 4 gives)
		for _, k in { "all", "aura", "eggs", "skip", "away" } do
			T.truthy(keys[k], "a wondrous " .. k)
			for _, f in Traits.families do
				T.truthy(f.key ~= k, f.family .. " never gives " .. k)
			end
		end
		local function share(r: number): number
			local rng, n, all = Util.newRng(77), 0, 0
			for _ = 1, 40000 do
				for _, id in Traits.roll(rng, r) do
					all += 1
					if Traits.byId[id].tier == 5 then
						n += 1
					end
				end
			end
			return n / math.max(1, all)
		end
		local common, legend = share(1), share(5)
		T.truthy(common > 0 and common < 0.006, string.format("a common one's mutation is wondrous %.4f of the time", common))
		T.truthy(legend > common * 2 and legend < 0.02, string.format("a legend's %.4f", legend))
		T.deepEq(Traits.clean({ "golden5", "busy4", "golden5" }), { "golden5", "busy4" }, "a family once")
	end)
	T.it("the fabled mutations (tier 6, 2026-11-20): the strongest and rarest, each its own family, stronger than the wondrous ones", function()
		-- (the request: "add another tier of mutations, which are the strongest and rarest")
		T.truthy(#Traits.fabled >= 4)
		T.truthy(Traits.TIER_COLOR[6] ~= nil and Traits.TIER_NAME[6] == "Fabled")
		T.truthy(Palette.ui[Traits.TIER_COLOR[6]] ~= nil, "its colour")
		-- the strongest wondrous effect of each key, to beat
		local best5: { [string]: number } = {}
		for _, w in Traits.wonders do
			for k, v in w.fx do
				best5[k] = math.max(best5[k] or 0, v)
			end
		end
		local fams: { [string]: boolean } = {}
		for _, f in Traits.fabled do
			local m = Traits.byId[f.family .. "6"]
			T.truthy(m ~= nil and m.tier == 6 and m.name == f.name, f.family .. "6")
			T.truthy(not fams[f.family] and Traits.byId[f.family .. "5"] == nil and Traits.byId[f.family .. "1"] == nil, f.family .. ": a family of its own")
			fams[f.family] = true
			T.eq(Traits.at(f.family, 1), m.id, "one tier: its own")
			T.eq(Traits.at(f.family, 9), m.id)
			-- stronger: its main effect (one the wondrous tier gives) beats every wondrous one's, each within the caps
			local beats = false
			for k, v in m.fx do
				T.truthy(v > 0, m.id .. " " .. k .. " helps")
				if best5[k] and v > best5[k] + 1e-9 then
					beats = true
				end
				local cap = Tuning.IsleCap[k]
				T.truthy(cap == nil or v <= cap, m.id .. " " .. k .. " within the island's cap")
			end
			T.truthy(beats, m.id .. " beats every wondrous one at its effect")
			T.truthy(m.blurb ~= "", m.id .. " says what it does")
		end
		local function share(r: number): number
			local rng, n, all = Util.newRng(91), 0, 0
			for _ = 1, 60000 do
				for _, id in Traits.roll(rng, r) do
					all += 1
					if Traits.byId[id].tier == 6 then
						n += 1
					end
				end
			end
			return n / math.max(1, all)
		end
		local common, eternal = share(1), share(Traits.RMAX)
		T.truthy(common < 0.001, string.format("a common one's mutation is fabled %.5f of the time", common))
		T.truthy(eternal > common * 3 and eternal < 0.006, string.format("an eternal one's %.5f", eternal))
		T.deepEq(Traits.clean({ "crown6", "golden5", "crown6", "busy4" }), { "crown6", "golden5", "busy4" }, "a family once")
	end)
	T.it("cleaning a save's list: known ids, a family once, at most four", function()
		-- (a saved Leafy one is Lucky of the same tier since 2026-11-14)
		T.deepEq(Traits.clean({ "swift2", "swift4", "x", 5, "lazy", "busy1", "fierce1", "armor3", "bright1" }), { "bright2", "lazy", "fierce1", "armor3" }, "Lazy and Diligent: one family")
		T.eq(Traits.byId.frail.blurb, "eggs cost 25% more")
		T.eq(Traits.byId.sturdy2.blurb, "eggs cost 30% less")
		T.eq(Traits.byId.fierce3.name, "Golden")
		T.eq(Traits.byId.bright1.blurb, "+5% egg luck")
		-- a saved Angler (fishing, then farms; one kind of work since 2026-11-19) becomes Busy of its tier, once a family
		T.deepEq(Traits.clean({ "angler2", "grower1" }), { "busy2", "grower1" }, "an Angler is Busy now")
		T.deepEq(Traits.clean({ "busy1", "angler3", "lazy" }), { "busy1" }, "never the family twice")
		T.eq(Traits.byId.angler1, nil, "no new Anglers")
		for _, k in Traits.KEYS do
			T.truthy(k ~= "fish", "no fishing share")
		end
		T.deepEq(Traits.clean(nil), {})
		T.deepEq(Traits.clean("sturdy1"), {})
	end)
end
