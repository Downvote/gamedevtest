-- The content tables agree with each other and with Tuning (GAME_DESIGN 4, 5, 9).
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Buildings = require("../../build/luautest/shared/Data/Buildings")
local Creatures = require("../../build/luautest/shared/Data/Creatures")
local Traits = require("../../build/luautest/shared/Data/Traits")
local Islets = require("../../build/luautest/shared/Data/Islets")
local Office = require("../../build/luautest/shared/Data/Office")
local Palette = require("../../build/luautest/shared/Data/Palette")
local Looks = require("../../build/luautest/shared/Data/Looks")
local Street = require("../../build/luautest/shared/Data/Street")
local DynTex = require("../../build/luautest/shared/Render/DynTex")
return function()
	T.it("every driftling has its own eyes and a texture", function()
		local eyes: { [string]: boolean } = {}
		for _, e in Creatures.EYES do
			eyes[e] = true
		end
		local byPlan: { [string]: { [string]: string } } = {}
		for _, d in Creatures.list do
			T.truthy(eyes[d.eye], d.id .. ": eye style " .. tostring(d.eye))
			T.truthy(d.iris == nil or Palette.colors[d.iris] ~= nil, d.id .. ": iris " .. tostring(d.iris))
			T.truthy(DynTex.kind(d.tex) > 0, d.id .. ": texture " .. tostring(d.tex))
			T.truthy(d.tex2 == nil or DynTex.kind(d.tex2) > 0, d.id .. ": accent texture " .. tostring(d.tex2))
			local plan = byPlan[d.shape] or {}
			byPlan[d.shape] = plan
			T.truthy(plan[d.eye] == nil, d.id .. " shares its eyes (" .. d.eye .. ") with " .. tostring(plan[d.eye]))
			plan[d.eye] = d.id
		end
	end)

	local function color(k: string): boolean
		return Palette.ui[k] ~= nil or Palette.colors[k] ~= nil or Palette.axis[k] ~= nil
	end
	T.it("buildings: unique ids, prices, footprints, kinds, what each makes", function()
		local seen = {}
		local kinds = { farm = true, wood = true, shop = true, nest = true, breed = true, gen = true, path = true, water = true, fence = true, decor = true, tree = true }
		local tabs = { work = true, nest = true, path = true, water = true, fence = true, nature = true, decor = true, fun = true }
		local feels = { wood = true, stone = true, plant = true, water = true, metal = true, magic = true, sand = true, snow = true, cloth = true, fire = true }
		for _, d in Buildings.list do
			T.truthy(not seen[d.id] and string.match(d.id, "^%w+$") ~= nil, d.id)
			seen[d.id] = true
			T.truthy(kinds[d.kind], d.id .. " kind")
			-- (every piece is paid for in wood: "make wood the main resource for building/expanding")
			-- (the Tree of Life is never bought: no price, no tier a player reaches)
			local tree = d.kind == "tree"
			-- (a fence is a 2-stud length along a grid line: 2 x 0; paths and water are 2 x 2 tiles)
			local fence = d.kind == "fence"
			local foot = if fence then d.w == 2 and d.d == 0 else d.w >= 1 and d.d >= 1 and d.w == math.floor(d.w) and d.d == math.floor(d.d)
			T.truthy(d.shells == 0 and (d.wood > 0) ~= tree and foot, d.id .. " price and footprint")
			if d.kind == "path" or d.kind == "water" then
				T.truthy(d.w == 2 and d.d == 2, d.id .. " a 2 x 2 tile")
			end
			T.truthy(tree or tabs[d.tab], d.id .. " tab")
			T.truthy(feels[d.feel], d.id .. " feel")
			T.truthy(d.water == "" or d.water == "over" or d.water == "on", d.id .. " water")
			T.truthy(d.water == "" or d.kind == "decor", d.id .. " only decor stands over water")
			T.truthy(d.kind ~= "decor" or d.sub ~= "", d.id .. " a row in its tab")
			T.truthy(tree or (d.tier >= 1 and d.tier <= #Office.plans), d.id .. " tier")
			local makes = d.kind == "farm" or d.kind == "wood" or d.kind == "shop"
			T.truthy(makes == (d.rate > 0), d.id .. " rate")
			T.truthy(makes == (d.knack ~= ""), d.id .. " knack")
			T.truthy((d.kind == "nest") == (d.slots > 0), d.id .. " huts have room")
			T.truthy(d.kind ~= "decor" or d.charm > 0, d.id .. " decor brings charm")
			T.truthy((d.kind == "gen") == (d.boost ~= "" and d.boostBy > 0), d.id .. " a boost building boosts")
			T.truthy(d.boost == "" or d.boost == "farm" or d.boost == "fish" or d.boost == "wood" or d.boost == "shop" or d.boost == "all", d.id .. " boost knack")
			T.truthy(d.comfort == 0 or d.kind == "nest", d.id .. " comfort is a hut's")
			T.truthy(d.kind ~= "path" or (d.w == 2 and d.d == 2), d.id .. " a path is a 2 x 2 tile")
		end
		T.eq(Buildings.byId.tree.kind, "tree", "the Tree of Life: every island's")
		T.truthy(seen.patch and seen.nest and seen.lumber and seen.stall, "the first buildings")
		T.eq(Buildings.byId.tent, nil, "no homes: no villagers")
		for _, id in { "patch", "nest", "lumber", "stall" } do
			T.eq(Buildings.byId[id].tier, 1, id .. " from the start")
		end
	end)
	T.it("driftlings: unique ids, a kind each, a make-up, knacks a building has, colours", function()
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
			T.truthy(knacks[d.knack], d.id .. " knack " .. d.knack)
			T.truthy(color(d.body) and color(d.accent), d.id .. " colours")
			-- its rarity, its passive (named, effects Data/Traits knows) and its breeding rank
			T.truthy(d.rarity >= 1 and d.rarity <= Traits.RMAX, d.id .. " rarity")
			T.truthy(#d.passive.name > 0 and next(d.passive.fx) ~= nil, d.id .. " passive")
			for k, v in d.passive.fx do
				-- (costing less is the good way; charm in whole points)
				local good = if k == "cost" then v < 0 and v > -1 elseif k == "charm" then v >= 1 and v == math.floor(v) else v > 0 and v < 1
				T.truthy(table.find(Traits.KEYS, k) ~= nil and good, d.id .. " passive effect " .. k)
			end
			T.truthy(d.power > 0, d.id .. " power")
		end
		-- each kind: at least five, a common one and a rarer one
		for i in Islets.list do
			T.truthy((perIslet[i] or 0) >= 5, "five or more driftlings on islet " .. i .. ": " .. tostring(perIslet[i]))
			local lo, hi = 9, 0
			for _, d in Creatures.list do
				if d.islet == i then
					lo, hi = math.min(lo, d.rarity), math.max(hi, d.rarity)
				end
			end
			T.truthy(lo == 1 and hi >= 3, "islet " .. i .. ": commons and rarer ones")
		end
		-- every passive is its own
		local names: { [string]: boolean } = {}
		for _, d in Creatures.list do
			T.truthy(not names[d.passive.name], "a passive of its own: " .. d.passive.name)
			names[d.passive.name] = true
		end
	end)
	T.it("kinds of land: their own driftlings, the tree growing them from a tier of the island, a colour", function()
		local opened: { [number]: number } = {}
		for i, d in Islets.list do
			T.eq(d.id, i)
			T.truthy(#d.wild >= 5, d.name .. " roster")
			for _, sp in d.wild do
				T.truthy(Creatures.byId[sp] ~= nil and Creatures.byId[sp].islet == i, d.name .. " " .. sp)
			end
			T.truthy(color(d.color), d.name .. " colour")
			T.truthy(#d.plural > 0 and #d.blurb > 0, d.name .. " words")
			-- (up to the last island, tier 20: the kinds past the capital open from tier 11)
			T.truthy(d.tier >= 1 and d.tier <= math.max(#Office.plans, 20), d.name .. " tier")
			opened[d.tier] = (opened[d.tier] or 0) + 1
		end
		T.truthy((opened[1] or 0) >= 2, "two kinds from the start")
		-- (the first six tiers each bring a kind; the four past them bring land, better eggs and decor sets)
		for t = 2, 6 do
			T.truthy((opened[t] or 0) >= 1, "each expansion brings a kind: tier " .. t)
		end
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
	T.it("an island only gains land as it grows: every cell buildable at a tier is buildable at the next", function()
		for tier = 1, #Office.plans - 1 do
			local r = Street.plot(tier)
			local lost = 0
			for z = r.z0, r.z1 do
				for x = r.x0, r.x1 do
					if Street.buildable(tier, x, z) and not Street.buildable(tier + 1, x, z) then
						lost += 1
					end
				end
			end
			T.eq(lost, 0, "cells lost going to tier " .. (tier + 1))
		end
	end)
	T.it("the sea: islands alone inside their lots, growing by tier, the plaza and the spawn on the grass, the sign on the beach", function()
		T.eq(Street.MAX, Tuning.MaxPlots)
		local lot = Street.LOT
		local prevCells = 0
		for tier = 1, #Office.plans do
			local p = Street.plot(tier)
			T.truthy(p.x0 > lot.x0 + 4 and p.x1 < lot.x1 - 4 and p.z0 > lot.z0 and p.z1 < lot.z1 - 4, "island " .. tier .. " inside its lot, water all round")
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
			-- the plaza and the spawn are on the grass; the sign stands on the south beach
			local pl = Street.PLAZA
			for z = pl.z0, pl.z1 - 1 do
				for x = pl.x0, pl.x1 - 1 do
					T.truthy(Street.layer(tier, x, z) == Street.GRASS, string.format("plaza on the grass at %d,%d (tier %d)", x, z, tier))
				end
			end
			local sx, sz = Street.spawn()
			T.truthy(Street.layer(tier, sx, sz) == Street.GRASS and sz >= pl.z0 and sz < pl.z1, "the spawn is on the plaza's grass (tier " .. tier .. ")")
			local gx, gz = Street.sign(tier)
			T.truthy(Street.layer(tier, math.floor(gx), math.floor(gz)) == Street.SAND and gz > pl.z1, "the sign on the south beach (tier " .. tier .. ")")
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
		-- no docks: the lots meet the open sea; the water lies under the grass; the seabed the founders swim on is under
		-- the water and a step below the wet sand
		T.truthy(Street.LOT.z1 == Street.SEA.z0)
		T.eq((Street :: any).BOARD, nil, "no boardwalk")
		T.eq((Street :: any).pier, nil, "no pier")
		T.truthy(Street.SEABED_Y < Street.WATER_Y and Street.WET_Y - Street.SEABED_Y < 1.5, "the seabed: under the water, a step from the wet sand")
		T.eq(Street.plotAt(Street.origin(2), Street.SEA.z0 + 10), 2, "the sea south of a lot is that lot's")
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
