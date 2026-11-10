-- The island's building rules (Logic/Plot; GAME_DESIGN 4): where pieces may stand, placing (paid in shells and wood,
-- the island's tier), moving, clearing away (a refund; never a home or a nest still needed), the piece limit.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Street = require("../../build/luautest/shared/Data/Street")
local Office = require("../../build/luautest/shared/Data/Office")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood = 1e6, 1e6
	return p
end

return function()
	T.it("a quarter turn swaps the footprint", function()
		T.eq(select(1, Plot.footprint("bench", 0)), 3)
		T.eq(select(2, Plot.footprint("bench", 0)), 2)
		T.eq(select(1, Plot.footprint("bench", 90)), 2)
		T.eq(select(2, Plot.footprint("bench", 270)), 3)
	end)
	T.it("fits: on the plot, on the grid, off the office, the footpath, the sign, the mailbox and other pieces", function()
		local plan = Office.plan(1)
		local p = Street.plot(1)
		T.truthy(Plot.fits(1, {}, "flowers", 16, 18, 0), "the east yard")
		T.eq(select(2, Plot.fits(1, {}, "flowers", p.x1 - 2, 18, 0)), "outside", "a stud in from the east edge")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 16, 28, 0)), "outside", "off the pavement")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 16.5, 18, 0)), "outside", "whole studs")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 16, 18, 45)), "outside", "quarter turns")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 0, 0, 0)), "blocked", "in the office")
		local fp = Street.footpath(plan.maxX, plan.maxZ)
		T.eq(select(2, Plot.fits(1, {}, "torch", math.floor(fp.x0), 20, 0)), "blocked", "on the footpath")
		local sx, sz = Street.sign(plan.maxX, plan.maxZ)
		T.eq(select(2, Plot.fits(1, {}, "torch", math.floor(sx), math.floor(sz), 0)), "blocked", "on the sign")
		local placed = { { uid = 1, id = "flowers", x = 16, z = 18, rot = 0 } }
		T.eq(select(2, Plot.fits(1, placed, "torch", 17, 19, 0)), "overlap")
		T.truthy(Plot.fits(1, placed, "torch", 18, 18, 0), "touching is fine")
		T.truthy(Plot.fits(1, placed, "flowers", 17, 19, 0, 1), "moving a piece over its own old place")
		T.eq(select(2, Plot.fits(1, {}, "castle", 16, 18, 0)), "unknown")
	end)
	T.it("place: paid in shells and wood, the tier reached, a uid each, an idle villager put to work", function()
		local p = fresh()
		p.folk = { { id = 50, name = "A", look = p.founder, work = 0, lvl = 1, xp = 0, seed = 1, day = 1 } }
		p.nextId = 51
		local ok, data = Plot.place(p, "pier", 16, 18, 0)
		T.truthy(ok)
		T.eq(p.shells, 1e6 - Buildings.byId.pier.shells)
		T.eq(p.wood, 1e6 - Buildings.byId.pier.wood)
		T.eq(data.uid, 51)
		T.deepEq(p.plot.placed[1], { uid = 51, id = "pier", x = 16, z = 18, rot = 0, lvl = 1 })
		T.eq(p.folk[1].work, 51, "the idle villager works there")
		T.eq(p.stats.built, 1)
		T.eq(select(2, Plot.place(p, "orchard", 16, 22, 0)), "locked", "a tier 2 building")
		p.tier = 2
		T.truthy(Plot.place(p, "orchard", 12, 22, 0))
		p.shells = 10
		T.eq(select(2, Plot.place(p, "hut", 20, 22, 0)), "money")
		p.shells, p.wood = 1e6, 0
		T.eq(select(2, Plot.place(p, "hut", 20, 22, 0)), "wood")
		T.eq(select(2, Plot.place(p, "castle", 20, 22, 0)), "bad_payload")
	end)
	T.it("upgrades: a building that makes something, two levels, paid by its price", function()
		local p = fresh()
		Plot.place(p, "patch", 16, 18, 0)
		Plot.place(p, "tent", 20, 22, 0)
		local before = p.shells
		T.truthy(Plot.upgrade(p, 1))
		T.eq(p.plot.placed[1].lvl, 2)
		T.eq(p.shells, before - Buildings.byId.patch.shells * Tuning.UpgradeCost[2])
		T.truthy(Plot.upgrade(p, 1))
		T.eq(select(2, Plot.upgrade(p, 1)), "max")
		T.eq(select(2, Plot.upgrade(p, 2)), "max", "a tent has no levels")
		p.shells = 0
		Plot.place(p, "torch", 6, 22, 0)
	end)
	T.it("move, clear away (a refund, the workers idle), not a home or a nest still needed, the limit", function()
		local p = fresh()
		T.truthy(Plot.place(p, "torch", 16, 18, 0))
		T.truthy(Plot.place(p, "torch", 18, 18, 0), "as many as fit")
		T.eq(select(2, Plot.place(p, "torch", 16, 18, 0)), "blocked", "on another piece")
		T.truthy(Plot.move(p, 1, 20, 20, 90))
		T.eq(p.plot.placed[1].x, 20)
		T.eq(select(2, Plot.move(p, 1, 0, 0, 0)), "blocked")
		T.eq(select(2, Plot.move(p, 9, 20, 20, 0)), "bad_payload")
		local before = p.shells
		T.truthy(Plot.store(p, 1))
		T.eq(p.shells, before + math.floor(Buildings.byId.torch.shells * Tuning.Refund))
		T.eq(#p.plot.placed, 1)
		T.eq(select(2, Plot.store(p, 5)), "bad_payload")
		-- a tent with its villager in it stays
		T.truthy(Plot.place(p, "tent", 12, 22, 0))
		p.folk = { { id = 90, name = "A", look = p.founder, work = 0, lvl = 1, xp = 0, seed = 1, day = 1 } }
		T.eq(select(2, Plot.store(p, 2)), "no_room")
		T.truthy(Plot.place(p, "patch", 12, 16, 0))
		p.folk[1].work = p.plot.placed[3].uid
		T.truthy(Plot.store(p, 3))
		T.eq(p.folk[1].work, 0, "their workplace gone: idle")
		-- fill to the limit
		local n = #p.plot.placed
		local plot = Street.plot(1)
		for z = plot.z0 + 1, plot.z1 - 2 do
			for x = plot.x0 + 1, plot.x1 - 2 do
				if n < Plot.limit(1) and Plot.place(p, "torch", x, z, 0) then
					n += 1
				end
			end
		end
		T.eq(#p.plot.placed, Plot.limit(1))
		T.eq(select(2, Plot.place(p, "torch", plot.x1 - 3, plot.z1 - 3, 0)), "full")
		T.eq(Plot.limit(3), Tuning.PlotPieces[3])
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
