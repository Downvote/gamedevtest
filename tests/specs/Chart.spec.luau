-- The sea chart (Logic/Chart; GAME_DESIGN 7): every player's islands round their home, the same every time; the
-- level by distance; the boat's range and its upgrades; setting sail only within range; the first charting pays the
-- whole reward and later trips half.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Chart = require("../../build/luautest/shared/Logic/Chart")
local Expedition = require("../../build/luautest/shared/Logic/Expedition")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Util = require("../../build/luautest/shared/Logic/Util")

local function fresh(seed: number?): any
	local p = Schema.default(0, seed or 1)
	p.food = 500
	return p
end

return function()
	T.it("a sea: its islands the same every time, spread out, nearest first, a few in the first boat's range", function()
		for seed = 1, 20 do
			local sea = seed * 7777
			local a = Chart.islands(sea)
			T.eq(#a, Tuning.ChartIslands)
			T.deepEq(a, Chart.islands(sea))
			local near = 0
			for i, c in a do
				T.eq(c.id, i)
				T.truthy(c.dist >= Tuning.ChartMinDist - 1e-6 and c.dist <= Tuning.ChartMaxDist + 1e-6, "in the chart")
				T.truthy(math.abs(math.sqrt(c.x * c.x + c.y * c.y) - c.dist) < 1e-6)
				if i > 1 then
					T.truthy(c.dist >= a[i - 1].dist, "nearest first")
				end
				for j = i + 1, #a do
					local d = a[j]
					T.truthy((c.x - d.x) ^ 2 + (c.y - d.y) ^ 2 >= Tuning.ChartSpacing ^ 2 - 1e-6, "apart")
				end
				T.eq(c.lvl, Chart.levelAt(c.dist))
				if c.dist <= Chart.radius(1) then
					near += 1
				end
			end
			T.truthy(near >= Tuning.ChartNear, "islands for the first boat: " .. near)
		end
		T.truthy(Chart.islands(1)[5].x ~= Chart.islands(2)[5].x, "another sea, other islands")
	end)
	T.it("levels: 1 near home, growing outward; what an island holds is its own", function()
		T.eq(Chart.levelAt(Tuning.ChartMinDist), 1)
		T.truthy(Chart.levelAt(Tuning.ChartMaxDist) >= 23, "reefs at the edge")
		local prev = 0
		for d = Tuning.ChartMinDist, Tuning.ChartMaxDist, 0.5 do
			T.truthy(Chart.levelAt(d) >= prev)
			prev = Chart.levelAt(d)
		end
		local sea = 4242
		for id = 1, Tuning.ChartIslands do
			local isle = Chart.isle(sea, id) :: any
			T.eq(isle.id, id)
			T.eq(isle.lvl, Chart.islands(sea)[id].lvl)
			T.deepEq(isle, Chart.isle(sea, id))
			T.truthy(Islets.list[isle.kind].lvl <= isle.lvl)
		end
		T.eq(Chart.isle(sea, 0), nil)
		T.eq(Chart.isle(sea, Tuning.ChartIslands + 1), nil)
	end)
	T.it("the boat: a range by level, upgrades for shells and wood, none past the top", function()
		local p = fresh()
		T.eq(p.boat, 1)
		for lv = 2, #Tuning.BoatRadius do
			T.truthy(Chart.radius(lv) > Chart.radius(lv - 1), "a bigger range")
		end
		T.truthy(Chart.radius(#Tuning.BoatRadius) >= Tuning.ChartMaxDist, "the last reaches the edge")
		local cost = Chart.boatCost(1) :: any
		p.shells, p.wood = cost.shells - 1, cost.wood
		T.eq(select(2, Chart.upgradeBoat(p)), "money")
		p.shells, p.wood = cost.shells, cost.wood - 1
		T.eq(select(2, Chart.upgradeBoat(p)), "wood")
		p.shells, p.wood = cost.shells + 5, cost.wood + 7
		local ok, data = Chart.upgradeBoat(p)
		T.truthy(ok)
		T.eq(p.boat, 2)
		T.eq(data.radius, Chart.radius(2))
		T.eq(p.shells, 5)
		T.eq(p.wood, 7)
		p.boat = #Tuning.BoatRadius
		p.shells, p.wood = 1e9, 1e9
		T.eq(select(2, Chart.upgradeBoat(p)), "max")
	end)
	T.it("setting sail: an island on the chart and in range; it is that island", function()
		local p = fresh(3)
		T.eq(select(2, Chart.sail(p, 0, {})), "bad_payload")
		T.eq(select(2, Chart.sail(p, Tuning.ChartIslands + 1, {})), "bad_payload")
		local far = Chart.islands(p.sea)[Tuning.ChartIslands]
		T.eq(select(2, Chart.sail(p, far.id, {})), "far")
		p.boat = #Tuning.BoatRadius
		local ok, e = Chart.sail(p, far.id, {})
		T.truthy(ok)
		T.deepEq(e.isle, Chart.isle(p.sea, far.id))
		p.boat = 1
		local near = Chart.islands(p.sea)[1]
		T.truthy(Chart.reachable(p, near.id))
	end)
	T.it("charting: the first time the whole reward and on the chart, later trips half, counted once", function()
		local p = fresh(5)
		p.cap.lvl = 30
		local rng = Util.newRng(3)
		local function trip(): (any, number)
			local _, e = Chart.sail(p, 1, {})
			local reward = 0
			while e.node < #e.nodes and not e.over do
				Expedition.next(p, e, rng)
				local guard = 0
				while e.battle and guard < 60 do
					guard += 1
					local _, data = Expedition.act(p, e, "fight", "", rng)
					if data and data.reward then
						reward = data.reward
					end
				end
			end
			return e, reward
		end
		local e1, r1 = trip()
		T.eq(e1.over, "won")
		T.truthy(Chart.charted(p, 1))
		T.eq(p.islets, 1)
		T.truthy(e1.loot.shells >= e1.isle.reward)
		Expedition.home(p, e1)
		T.eq(r1, e1.isle.reward)
		local e2, r2 = trip()
		T.eq(e2.over, "won")
		T.eq(p.islets, 1, "counted once")
		T.eq(#p.chart, 1)
		T.eq(r2, math.floor(e1.isle.reward / 2), "half the second time")
	end)
end
