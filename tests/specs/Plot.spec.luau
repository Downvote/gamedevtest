-- The plot's rules (Logic/Plot; GAME_DESIGN 13): where decor may stand, buying once, placing copies, moving, storing,
-- the piece limit, and the pieces a bigger office covers going back in the box.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Street = require("../../build/luautest/shared/Data/Street")
local Office = require("../../build/luautest/shared/Data/Office")
local Decor = require("../../build/luautest/shared/Data/Decor")

local function fresh(): any
	local p = Schema.default(0, 1)
	p.money = 1e6
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
		T.eq(select(2, Plot.fits(1, {}, "gnome", math.floor(fp.x0), 20, 0)), "blocked", "on the footpath")
		local sx, sz = Street.sign(plan.maxX, plan.maxZ)
		T.eq(select(2, Plot.fits(1, {}, "gnome", math.floor(sx), math.floor(sz), 0)), "blocked", "on the sign")
		local placed = { { id = "flowers", x = 16, z = 18, rot = 0 } }
		T.eq(select(2, Plot.fits(1, placed, "gnome", 17, 19, 0)), "overlap")
		T.truthy(Plot.fits(1, placed, "gnome", 18, 18, 0), "touching is fine")
		T.truthy(Plot.fits(1, placed, "flowers", 17, 19, 0, 1), "moving a piece over its own old place")
		T.eq(select(2, Plot.fits(1, {}, "castle", 16, 18, 0)), "unknown")
	end)
	T.it("buy once: money, fans, the office it needs", function()
		local p = fresh()
		local ok, data = Plot.buy(p, "oak")
		T.truthy(ok)
		T.eq(data.fans, Decor.byId.oak.fans)
		T.eq(p.money, 1e6 - Decor.byId.oak.price)
		T.eq(p.fans, Decor.byId.oak.fans)
		T.eq(select(2, Plot.buy(p, "oak")), "max", "only once")
		T.eq(select(2, Plot.buy(p, "fountain")), "locked", "the Loft's")
		p.money = 10
		T.eq(select(2, Plot.buy(p, "bench")), "money")
		T.eq(select(2, Plot.buy(p, "castle")), "bad_payload")
	end)
	T.it("place copies, move, store, the limit", function()
		local p = fresh()
		T.eq(select(2, Plot.place(p, "gnome", 16, 18, 0)), "locked", "not owned")
		Plot.buy(p, "gnome")
		T.truthy(Plot.place(p, "gnome", 16, 18, 0))
		T.truthy(Plot.place(p, "gnome", 18, 18, 0), "a second copy, free")
		T.eq(select(2, Plot.place(p, "gnome", 16, 18, 0)), "blocked", "on another piece")
		T.truthy(Plot.move(p, 1, 20, 20, 90))
		T.deepEq(p.plot.placed[1], { id = "gnome", x = 20, z = 20, rot = 90 })
		T.eq(select(2, Plot.move(p, 1, 0, 0, 0)), "blocked")
		T.eq(select(2, Plot.move(p, 9, 20, 20, 0)), "bad_payload")
		T.truthy(Plot.store(p, 1))
		T.eq(#p.plot.placed, 1)
		T.eq(p.plot.placed[1].x, 18)
		T.eq(select(2, Plot.store(p, 5)), "bad_payload")
		-- fill to the limit
		local n = #p.plot.placed
		local plot = Street.plot(1)
		for z = plot.z0 + 1, plot.z1 - 2 do
			for x = plot.x0 + 1, plot.x1 - 2 do
				if n < Plot.limit(1) and Plot.place(p, "gnome", x, z, 0) then
					n += 1
				end
			end
		end
		T.eq(#p.plot.placed, Plot.limit(1))
		T.eq(select(2, Plot.place(p, "gnome", plot.x1 - 3, plot.z1 - 3, 0)), "full")
		T.eq(Plot.limit(3), Tuning.PlotPieces[3])
	end)
	T.it("a bigger office puts the pieces it covers back in the box", function()
		local p = fresh()
		Plot.buy(p, "gnome")
		local plan1 = Office.plan(1)
		-- right against the tier 1 room's east side: inside the tier 2 room
		T.truthy(Plot.place(p, "gnome", plan1.maxX + 1, 0, 0))
		T.truthy(Plot.place(p, "gnome", 20, 22, 0))
		p.office = 2
		T.eq(Plot.clean(p), 1)
		T.eq(#p.plot.placed, 1)
		T.eq(p.plot.placed[1].x, 20)
		T.truthy(p.plot.owned.gnome, "still owned")
	end)
	T.it("every piece fits somewhere on the plot of the office it needs", function()
		for _, d in Decor.list do
			local plot = Street.plot(d.office)
			local found = false
			for z = plot.z0, plot.z1 do
				for x = plot.x0, plot.x1 do
					if Plot.fits(d.office, {}, d.id, x, z, 0) then
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
