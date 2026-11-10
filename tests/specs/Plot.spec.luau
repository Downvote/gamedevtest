-- The island's building rules (Logic/Plot; GAME_DESIGN 4): where pieces may stand, placing (paid in shells and wood,
-- the island's tier), moving, clearing away (a refund; never a home or a nest still needed), the piece limit.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Street = require("../../build/luautest/shared/Data/Street")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood = 1e6, 1e6
	return p
end

-- The first spot (scanning the island's grass) where `id` fits among the profile's pieces.
local function spot(p: any, id: string): (number, number)
	local r = Street.plot(p.tier)
	for z = r.z0, r.z1 do
		for x = r.x0, r.x1 do
			if Plot.fits(p.tier, p.plot.placed, id, x, z, 0) then
				return x, z
			end
		end
	end
	return 0, 0
end

return function()
	T.it("a quarter turn swaps the footprint", function()
		T.eq(select(1, Plot.footprint("bench", 0)), 3)
		T.eq(select(2, Plot.footprint("bench", 0)), 2)
		T.eq(select(1, Plot.footprint("bench", 90)), 2)
		T.eq(select(2, Plot.footprint("bench", 270)), 3)
	end)
	T.it("fits: on the island's buildable grass, on the grid, off the plaza, the path and other pieces", function()
		T.truthy(Plot.fits(1, {}, "flowers", 8, 4, 0), "the east lawn")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 18, 5, 0)), "outside", "past the east coast")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 0, 22, 0)), "outside", "on the beach")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8.5, 4, 0)), "outside", "whole studs")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8, 4, 45)), "outside", "quarter turns")
		T.eq(select(2, Plot.fits(1, {}, "torch", 0, 4, 0)), "blocked", "on the plaza")
		T.eq(select(2, Plot.fits(1, {}, "torch", 0, 12, 0)), "blocked", "on the path")
		local placed = { { uid = 1, id = "flowers", x = 8, z = 4, rot = 0, lvl = 1 } }
		T.eq(select(2, Plot.fits(1, placed, "torch", 9, 5, 0)), "overlap")
		T.truthy(Plot.fits(1, placed, "torch", 10, 4, 0), "touching is fine")
		T.truthy(Plot.fits(1, placed, "flowers", 9, 5, 0, 1), "moving a piece over its own old place")
		T.eq(select(2, Plot.fits(1, {}, "castle", 8, 4, 0)), "unknown")
		-- every cell a piece covers is buildable grass
		for _, d in Buildings.list do
			local r = Street.plot(1)
			for z = r.z0, r.z1 do
				for x = r.x0, r.x1 do
					if Plot.fits(1, {}, d.id, x, z, 0) then
						local w, dd = Plot.footprint(d.id, 0)
						for cz = z, z + dd - 1 do
							for cx = x, x + w - 1 do
								T.truthy(Street.layer(1, cx, cz) == Street.GRASS and Street.buildable(1, cx, cz), d.id .. " on grass")
							end
						end
					end
				end
			end
		end
	end)
	T.it("place: paid in shells and wood, the tier reached, a uid each, an idle villager put to work", function()
		local p = fresh()
		p.folk = { { id = 50, name = "A", look = p.founder, work = 0, lvl = 1, xp = 0, seed = 1, day = 1 } }
		p.nextId = 51
		local ok, data = Plot.place(p, "pier", 8, 4, 0)
		T.truthy(ok)
		T.eq(p.shells, 1e6 - Buildings.byId.pier.shells)
		T.eq(p.wood, 1e6 - Buildings.byId.pier.wood)
		T.eq(data.uid, 51)
		T.deepEq(p.plot.placed[1], { uid = 51, id = "pier", x = 8, z = 4, rot = 0, lvl = 1 })
		T.eq(p.folk[1].work, 51, "the idle villager works there")
		T.eq(p.stats.built, 1)
		local ox, oz = spot(p, "orchard")
		T.eq(select(2, Plot.place(p, "orchard", ox, oz, 0)), "locked", "a tier 2 building")
		p.tier = 2
		ox, oz = spot(p, "orchard")
		T.truthy(Plot.place(p, "orchard", ox, oz, 0))
		local hx, hz = spot(p, "hut")
		p.shells = 10
		T.eq(select(2, Plot.place(p, "hut", hx, hz, 0)), "money")
		p.shells, p.wood = 1e6, 0
		T.eq(select(2, Plot.place(p, "hut", hx, hz, 0)), "wood")
		T.eq(select(2, Plot.place(p, "castle", hx, hz, 0)), "bad_payload")
	end)
	T.it("upgrades: a building that makes something, two levels, paid by its price", function()
		local p = fresh()
		local x, z = spot(p, "patch")
		Plot.place(p, "patch", x, z, 0)
		x, z = spot(p, "tent")
		Plot.place(p, "tent", x, z, 0)
		local before = p.shells
		T.truthy(Plot.upgrade(p, 1))
		T.eq(p.plot.placed[1].lvl, 2)
		T.eq(p.shells, before - Buildings.byId.patch.shells * Tuning.UpgradeCost[2])
		T.truthy(Plot.upgrade(p, 1))
		T.eq(select(2, Plot.upgrade(p, 1)), "max")
		T.eq(select(2, Plot.upgrade(p, 2)), "max", "a tent has no levels")
	end)
	T.it("move, clear away (a refund, the workers idle), not a home or a nest still needed, the limit", function()
		local p = fresh()
		T.truthy(Plot.place(p, "torch", 8, 4, 0))
		T.truthy(Plot.place(p, "torch", 10, 4, 0), "as many as fit")
		T.eq(select(2, Plot.place(p, "torch", 8, 4, 0)), "blocked", "on another piece")
		T.truthy(Plot.move(p, 1, 8, 8, 90))
		T.eq(p.plot.placed[1].z, 8)
		T.eq(select(2, Plot.move(p, 1, 0, 4, 0)), "blocked", "not onto the plaza")
		T.eq(select(2, Plot.move(p, 9, 8, 8, 0)), "bad_payload")
		local before = p.shells
		T.truthy(Plot.store(p, 1))
		T.eq(p.shells, before + math.floor(Buildings.byId.torch.shells * Tuning.Refund))
		T.eq(#p.plot.placed, 1)
		T.eq(select(2, Plot.store(p, 5)), "bad_payload")
		-- a tent with its villager in it stays
		local tx, tz = spot(p, "tent")
		T.truthy(Plot.place(p, "tent", tx, tz, 0))
		p.folk = { { id = 90, name = "A", look = p.founder, work = 0, lvl = 1, xp = 0, seed = 1, day = 1 } }
		T.eq(select(2, Plot.store(p, 2)), "no_room")
		local px, pz = spot(p, "patch")
		T.truthy(Plot.place(p, "patch", px, pz, 0))
		p.folk[1].work = p.plot.placed[3].uid
		T.truthy(Plot.store(p, 3))
		T.eq(p.folk[1].work, 0, "their workplace gone: idle")
		-- fill to the limit
		local n = #p.plot.placed
		local plot = Street.plot(1)
		for z = plot.z0, plot.z1 do
			for x = plot.x0, plot.x1 do
				if n < Plot.limit(1) and Plot.place(p, "torch", x, z, 0) then
					n += 1
				end
			end
		end
		T.eq(#p.plot.placed, Plot.limit(1))
		local fx, fz = spot(p, "torch")
		T.eq(select(2, Plot.place(p, "torch", fx, fz, 0)), "full")
		T.eq(Plot.limit(3), Tuning.PlotPieces[3])
	end)
	T.it("refit: a piece off the coast (an older island's shape) moves to the nearest free spot, else its price back", function()
		local p = fresh()
		p.plot.placed = {
			{ uid = 5, id = "patch", x = 30, z = 4, rot = 0, lvl = 2 },
			{ uid = 6, id = "torch", x = 8, z = 4, rot = 0, lvl = 1 },
		}
		p.nextId = 7
		local moved, cleared = Plot.refit(p)
		T.eq(moved, 1)
		T.eq(cleared, 0)
		T.eq(#p.plot.placed, 2)
		local q = p.plot.placed[1]
		T.truthy(Plot.fits(1, { p.plot.placed[2] }, q.id, q.x, q.z, q.rot), "it fits now")
		T.truthy(q.x > 8, "toward where it was")
		T.eq(q.lvl, 2, "its level kept")
	end)
	T.it("every piece fits somewhere on the smallest island", function()
		for _, d in Buildings.list do
			local plot = Street.plot(1)
			local found = false
			for z = plot.z0, plot.z1 do
				for x = plot.x0, plot.x1 do
					if Plot.fits(1, {}, d.id, x, z, 0) then
						found = true
						break
					end
				end
				if found then
					break
				end
			end
			T.truthy(found, d.id)
		end
	end)
end
