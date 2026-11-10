-- The content tables agree with each other and with Tuning (GAME_DESIGN 4, 5, 9).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Office = require("../../build/luautest/shared/Data/Office")
local Palette = require("../../build/luautest/shared/Data/Palette")
local Looks = require("../../build/luautest/shared/Data/Looks")
local Street = require("../../build/luautest/shared/Data/Street")
return function()
	local function color(k: string): boolean
		return Palette.ui[k] ~= nil or Palette.colors[k] ~= nil or Palette.axis[k] ~= nil
	end
	T.it("buildings: unique ids, prices, footprints, kinds, what each makes", function()
		local seen = {}
		local kinds = { food = true, wood = true, shop = true, home = true, nest = true, train = true, decor = true }
		for _, d in Buildings.list do
			T.truthy(not seen[d.id] and string.match(d.id, "^%w+$") ~= nil, d.id)
			seen[d.id] = true
			T.truthy(kinds[d.kind], d.id .. " kind")
			T.truthy(d.shells > 0 and d.wood >= 0 and d.w >= 1 and d.d >= 1 and d.w == math.floor(d.w) and d.d == math.floor(d.d), d.id .. " price and footprint")
			T.truthy(d.tier >= 1 and d.tier <= #Office.plans, d.id .. " tier")
			local makes = d.kind == "food" or d.kind == "wood" or d.kind == "shop"
			T.truthy(makes == (d.rate > 0), d.id .. " rate")
			T.truthy(makes == (d.job ~= "" and d.knack ~= ""), d.id .. " job and knack")
			T.truthy((d.kind == "shop") == (d.eats > 0), d.id .. " a shop eats food")
			T.truthy((d.kind == "home") == (d.beds > 0) and (d.kind == "nest") == (d.slots > 0), d.id .. " beds and nests")
			T.truthy(d.kind ~= "decor" or d.charm > 0, d.id .. " decor brings charm")
		end
		T.truthy(seen.patch and seen.tent and seen.nest and seen.lumber and seen.stall, "the first buildings")
		for _, id in { "patch", "tent", "nest", "lumber", "stall" } do
			T.eq(Buildings.byId[id].tier, 1, id .. " from the start")
		end
	end)
	T.it("driftlings: unique ids, an islet each, stats, skills, knacks a building has, colours", function()
		local seen = {}
		local knacks: { [string]: boolean } = {}
		for _, b in Buildings.list do
			if b.knack ~= "" then
				knacks[b.knack] = true
			end
		end
		local perIslet: { [number]: number } = {}
		for _, d in Creatures.list do
			T.truthy(not seen[d.id] and string.match(d.id, "^%w+$") ~= nil, d.id)
			seen[d.id] = true
			T.truthy(Islets.list[d.islet] ~= nil, d.id .. " islet")
			perIslet[d.islet] = (perIslet[d.islet] or 0) + 1
			T.truthy(d.hp > 0 and d.atk > 0 and d.def > 0 and d.spd > 0, d.id .. " stats")
			T.truthy(Creatures.skills[d.skill] ~= nil and d.skill ~= "rally", d.id .. " skill")
			T.truthy(knacks[d.knack], d.id .. " knack " .. d.knack)
			T.truthy(d.trust > 0 and d.trust < 1, d.id .. " trust")
			T.truthy(color(d.body) and color(d.accent), d.id .. " colours")
		end
		for i in Islets.list do
			T.eq(perIslet[i], 3, "three driftlings on islet " .. i)
		end
	end)
	T.it("islets: a path from the landing to the guardian, its own driftlings, growing levels and rewards", function()
		for i, d in Islets.list do
			T.eq(d.id, i)
			T.eq(d.nodes[1], "start")
			T.eq(d.nodes[#d.nodes], "boss")
			for k, n in d.nodes do
				T.truthy(n == "start" or n == "loot" or n == "chest" or n == "wild" or n == "rest" or n == "boss", d.name .. " node " .. k)
			end
			for _, sp in d.wild do
				T.truthy(Creatures.byId[sp] ~= nil and Creatures.byId[sp].islet == i, d.name .. " " .. sp)
			end
			T.truthy(Creatures.byId[d.boss] ~= nil and Creatures.byId[d.boss].islet == i, d.name .. " guardian")
			T.truthy(color(d.color), d.name .. " colour")
			if i > 1 then
				local q = Islets.list[i - 1]
				T.truthy(d.lvl > q.lvl and d.reward > q.reward and d.loot.shells > q.loot.shells, d.name .. " harder and richer")
			end
		end
	end)
	T.it("lodges: a plan per tier, everything inside the room", function()
		T.truthy(#Office.plans >= 1)
		T.eq(#Office.plans, #Tuning.TierCost)
		T.eq(#Office.plans, #Tuning.PlotPieces)
		for i, plan in Office.plans do
			T.eq(plan.tier, i)
			T.truthy(Palette.themes[plan.theme] ~= nil, plan.name .. " theme")
			local hw, hd = Office.DESK_W / 2, Office.DESK_D / 2
			for k, a in plan.desks do
				T.truthy(a.x - hw >= plan.minX and a.x + hw <= plan.maxX and a.z - Office.SEAT_BACK - 0.8 >= plan.minZ and a.z + hd <= plan.maxZ, plan.name .. " desk " .. k .. " inside")
				for j, b in plan.desks do
					if j > k then
						local apart = math.abs(a.x - b.x) >= Office.DESK_W + 0.5 or math.abs(a.z - b.z) >= Office.DESK_D + Office.SEAT_BACK + 0.9
						T.truthy(apart, plan.name .. " desks " .. k .. " and " .. j .. " apart")
					end
				end
			end
			for _, p in plan.props do
				T.truthy(p.x >= plan.minX and p.x <= plan.maxX and p.z >= plan.minZ and p.z <= plan.maxZ, plan.name .. " " .. p.kind .. " inside")
			end
			T.truthy(#Office.outlinePts(i, 0, 0) == #plan.OUTLINE * 24)
		end
	end)
	T.it("looks: palette keys", function()
		for _, list in { Looks.skin, Looks.hair, Looks.shirt } do
			for _, k in list do
				T.truthy(Palette.colors[k] ~= nil, k)
			end
		end
	end)
	T.it("the sea: islands inside their lots, the lodge on its island, the door's path to the boardwalk", function()
		T.eq(Street.MAX, Tuning.MaxPlots)
		local lot = Street.LOT
		for tier = 1, #Office.plans do
			local p = Street.plot(tier)
			local plan = Office.plan(tier)
			T.truthy(p.x0 >= lot.x0 and p.x1 <= lot.x1 and p.z0 >= lot.z0 and p.z1 <= lot.z1, "plot " .. tier .. " inside the lot")
			T.truthy(p.z1 == Street.BOARD.z0, "island " .. tier .. " runs down to the boardwalk")
			T.truthy(plan.minX - Office.WALL_T > p.x0 and plan.maxX < p.x1 and plan.minZ - Office.WALL_T > p.z0 and plan.maxZ < p.z1, "office " .. tier .. " on its plot")
			if tier > 1 then
				local q = Street.plot(tier - 1)
				T.truthy(p.x0 <= q.x0 and p.x1 >= q.x1 and p.z0 <= q.z0, "plot " .. tier .. " grows")
			end
			local fp = Street.footpath(plan.maxX, plan.maxZ)
			T.truthy(fp.z0 == plan.maxZ and fp.z1 == Street.BOARD.z0 and fp.x0 > plan.minX and fp.x1 < plan.maxX, "path " .. tier)
			local sx = Street.sign(plan.maxX, plan.maxZ)
			local mx = Street.mailbox(plan.maxX, plan.maxZ)
			T.truthy(sx - 1.5 > p.x0 and mx + 0.75 < p.x1, "sign and mailbox on plot " .. tier)
		end
		-- the boardwalk meets the sea; the pier runs from the boardwalk out over it; the water lies under the grass
		T.truthy(Street.BOARD.z1 == Street.SEA.z0 and Street.LOT.z1 == Street.BOARD.z0)
		local pier = Street.pier()
		T.truthy(pier.z0 == Street.BOARD.z1 and pier.z1 < Street.SEA.z1)
		T.truthy(Street.WATER_Y < Street.SAND_Y and Street.SAND_Y < Street.LAWN_Y)
		-- neighbouring lots meet edge to edge, plot origins in a row centred on x = 0
		local a = Street.origin(1)
		local b = Street.origin(2)
		T.eq(b - a, Street.SPACING)
		T.eq(lot.x1 - lot.x0, Street.SPACING)
		T.eq(Street.origin(1) + Street.origin(Street.MAX), 0)
		for i = 1, Street.MAX do
			local ox, oz = Street.origin(i)
			T.eq(Street.plotAt(ox + 1, oz + 1), i)
		end
		T.eq(Street.plotAt(0, 200), 0)
	end)
end
