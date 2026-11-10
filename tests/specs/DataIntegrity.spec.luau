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
	T.it("kinds of island: their own driftlings, opening at growing levels from 1, words for names, a stage, a colour", function()
		for i, d in Islets.list do
			T.eq(d.id, i)
			T.eq(#d.wild, 3)
			for _, sp in d.wild do
				T.truthy(Creatures.byId[sp] ~= nil and Creatures.byId[sp].islet == i, d.name .. " " .. sp)
			end
			T.truthy(#d.first >= 6 and #d.last >= 6, d.name .. " words")
			for _, w in { table.unpack(d.first), table.unpack(d.last) } do
				T.truthy(string.match(w, "^%u%l+$") ~= nil, d.name .. " word " .. w)
			end
			T.truthy(color(d.color), d.name .. " colour")
			T.truthy(#d.stage > 0 and #d.plural > 0, d.name .. " stage")
			if i == 1 then
				T.eq(d.lvl, 1, "beaches from the start")
			else
				T.truthy(d.lvl > Islets.list[i - 1].lvl, d.name .. " opens later")
			end
		end
		T.truthy(#Islets.titles >= 6)
	end)
	T.it("island tiers: a name per tier, as many as the expansions and the piece limits", function()
		T.truthy(#Office.plans >= 1)
		T.eq(#Office.plans, #Tuning.TierCost)
		T.eq(#Office.plans, #Tuning.PlotPieces)
		for i, plan in Office.plans do
			T.eq(plan.tier, i)
			T.truthy(#plan.name > 0)
		end
	end)
	T.it("looks: palette keys", function()
		for _, list in { Looks.skin, Looks.hair, Looks.shirt } do
			for _, k in list do
				T.truthy(Palette.colors[k] ~= nil, k)
			end
		end
	end)
	T.it("the sea: islands inside their lots, growing by tier, the plaza and the path on the grass, the jetty to the boardwalk", function()
		T.eq(Street.MAX, Tuning.MaxPlots)
		local lot = Street.LOT
		local prevCells = 0
		for tier = 1, #Office.plans do
			local p = Street.plot(tier)
			T.truthy(p.x0 > lot.x0 + 4 and p.x1 < lot.x1 - 4 and p.z0 > lot.z0 and p.z1 < Street.BOARD.z0 - 4, "island " .. tier .. " inside its lot, water before the boardwalk")
			local cells = 0
			for z = p.z0, p.z1 do
				for x = p.x0, p.x1 do
					if Street.buildable(tier, x, z) then
						cells += 1
						T.truthy(Street.layer(tier, x, z) == Street.GRASS, "buildable is grass")
					end
				end
			end
			T.truthy(cells > prevCells + 200, string.format("island %d grows: %d buildable cells", tier, cells))
			prevCells = cells
			-- the plaza and the start of the path are on the grass; the path reaches the shore, the jetty the boardwalk
			local pl = Street.PLAZA
			for z = pl.z0, pl.z1 - 1 do
				for x = pl.x0, pl.x1 - 1 do
					T.truthy(Street.layer(tier, x, z) == Street.GRASS, string.format("plaza on the grass at %d,%d (tier %d)", x, z, tier))
				end
			end
			local jt = Street.jetty(tier)
			T.truthy(jt.z0 > pl.z1 and jt.z1 == Street.BOARD.z0 and Street.walkable(tier, 0, jt.z0), "the jetty starts on the sand (tier " .. tier .. ")")
			local sx, sz = Street.spawn()
			T.truthy(Street.layer(tier, sx, sz) == Street.GRASS, "the spawn is on the grass (tier " .. tier .. ")")
			-- the coast's layers go outward in order along any ray from the centre
			local c = Street.CENTER
			for k = 0, 15 do
				local ang = k * math.pi / 8
				local last = 1
				for d = 0, 60 do
					local l = Street.layer(tier, math.floor(c.x + math.cos(ang) * d), math.floor(c.z + math.sin(ang) * d))
					local rank = if l == Street.SEA_CELL then 6 else l
					T.truthy(rank >= last - 1, "layers outward")
					last = math.max(last, rank)
				end
			end
		end
		local sx = Street.sign()
		local mx = Street.mailbox()
		local jt = Street.jetty(1)
		T.truthy(sx + 1.5 < jt.x0 and mx - 0.75 > jt.x1, "sign and mailbox either side of the jetty")
		-- the boardwalk meets the sea; the pier runs from the boardwalk out over it; the water lies under the grass
		T.truthy(Street.BOARD.z1 == Street.SEA.z0 and Street.LOT.z1 == Street.BOARD.z0)
		local pier = Street.pier()
		T.truthy(pier.z0 == Street.BOARD.z1 and pier.z1 < Street.SEA.z1)
		T.truthy(Street.WATER_Y < Street.SHALLOW_Y and Street.SHALLOW_Y < Street.FOAM_Y and Street.FOAM_Y < Street.WET_Y and Street.WET_Y < Street.SAND_Y and Street.SAND_Y < Street.LAWN_Y)
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
