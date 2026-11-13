-- The island's building rules (Logic/Plot; GAME_DESIGN 4): where pieces may stand, placing (paid in wood,
-- the island's tier), moving, clearing away (a refund; never a home or a nest still needed), the piece limit.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Street = require("../../build/luautest/shared/Data/Street")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island with no pieces on it: the building rules on their own)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells, p.wood = 1e6, 1e6
	p.plot.placed = {}
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
	T.it("place: paid in wood, the tier reached, a uid each", function()
		local p = fresh()
		p.nextId = 51
		local ok, data = Plot.place(p, "pier", 8, 4, 0)
		T.truthy(ok)
		T.eq(p.shells, 1e6, "no shells")
		T.eq(p.wood, 1e6 - Buildings.byId.pier.wood)
		T.eq(data.uid, 51)
		T.deepEq(p.plot.placed[1], { uid = 51, id = "pier", x = 8, z = 4, rot = 0, lvl = 1 })
		T.eq(p.stats.built, 1)
		local ox, oz = spot(p, "orchard")
		T.eq(select(2, Plot.place(p, "orchard", ox, oz, 0)), "locked", "a tier 2 building")
		p.tier = 2
		ox, oz = spot(p, "orchard")
		T.truthy(Plot.place(p, "orchard", ox, oz, 0))
		local hx, hz = spot(p, "burrow")
		p.shells, p.wood = 1e6, 10
		T.eq(select(2, Plot.place(p, "burrow", hx, hz, 0)), "wood")
		T.eq(select(2, Plot.place(p, "castle", hx, hz, 0)), "bad_payload")
		T.eq(select(2, Plot.place(p, "tent", hx, hz, 0)), "bad_payload", "no homes any more")
	end)
	T.it("no upgrades: the rules have none to buy (a level from an older save still counts)", function()
		T.eq((Plot :: any).upgrade, nil, "no Plot.upgrade")
		T.eq((Plot :: any).upgradeCost, nil, "no price for a next level")
	end)
	T.it("replacing: another of its kind where it stands, paying the difference less the old one's refund; its uid kept", function()
		local p = fresh()
		p.tier = 2
		local x, z = spot(p, "nest")
		Plot.place(p, "nest", x, z, 0)
		local uid = p.plot.placed[1].uid
		T.deepEq(Plot.replacements(p.plot.placed[1], 1), {}, "tier 1: no other hut")
		T.truthy(table.find(Plot.replacements(p.plot.placed[1], 2), "burrow"))
		T.eq(select(2, Plot.replace(p, 1, "patch")), "bad_payload", "another kind")
		T.eq(select(2, Plot.replace(p, 1, "nest")), "bad_payload", "the same piece")
		T.eq(select(2, Plot.replace(p, 1, "den")), "locked")
		-- a bigger footprint that runs into another piece: blocked
		local q = p.plot.placed[1]
		Plot.place(p, "torch", q.x + 2, q.z, 0)
		T.eq(select(2, Plot.replace(p, 1, "burrow")), "blocked")
		Plot.store(p, #p.plot.placed)
		local before = p.wood
		local ok = Plot.replace(p, 1, "burrow")
		T.truthy(ok, "a burrow where the hut stood")
		T.eq(p.plot.placed[1].id, "burrow")
		T.eq(p.plot.placed[1].uid, uid, "its uid stays")
		T.eq(p.wood, before - (Buildings.byId.burrow.wood - math.floor(Buildings.byId.nest.wood * Tuning.Refund)))
		-- a farm for an orchard keeps its driftling (the patch where an orchard would fit)
		local fx, fz = spot(p, "orchard")
		Plot.place(p, "patch", fx, fz, 0)
		local farm = p.plot.placed[#p.plot.placed]
		local v = { id = 500, sp = "mossbun", home = uid, work = farm.uid }
		table.insert(p.pals, v)
		T.truthy(Plot.replace(p, #p.plot.placed, "orchard"), "an orchard where the patch stood")
		T.eq(p.plot.placed[#p.plot.placed].id, "orchard")
		T.eq(v.work, farm.uid, "its farmer works on in the orchard")
	end)
	T.it("paths: tiles apart from the piece limit, with a limit of their own", function()
		local p = fresh()
		T.truthy(Plot.isPath("dirtpath") and not Plot.isPath("patch"))
		local n = 0
		for z = -6, 20, 2 do
			for x = -16, 16, 2 do
				if Plot.place(p, "dirtpath", x, z, 0) then
					n += 1
				end
			end
		end
		T.eq(n, Plot.pathLimit(1), "as many paths as the limit")
		local used, most = Plot.used(p, "patch")
		T.eq(used, 0, "no piece used up")
		T.eq(most, Plot.limit(1))
		T.eq(select(2, Plot.place(p, "dirtpath", 30, 30, 0)), "full")
	end)
	T.it("drawing paths: a line or a box of tiles in one go, passing over cells that don't fit, while room and wood last", function()
		local p = fresh()
		-- the even cells a path tile fits on, scanning the island
		local free = {}
		local r = Street.plot(p.tier)
		for z = r.z0 - r.z0 % 2, r.z1, 2 do
			for x = r.x0 - r.x0 % 2, r.x1, 2 do
				if Plot.fits(p.tier, p.plot.placed, "dirtpath", x, z, 0) then
					table.insert(free, { x, z })
				end
			end
		end
		T.truthy(#free >= 12, "room for a dozen tiles")
		-- a line of six cells, one of them over the plaza (passed over)
		local line = { free[1], free[2], free[3], free[4], free[5], { Street.PLAZA.x0, Street.PLAZA.z0 } }
		local wood0 = p.wood
		local ok, out = Plot.paint(p, "dirtpath", line)
		T.truthy(ok, "a line goes down")
		T.eq(out.placed + out.skipped, 6, "every cell placed or passed over")
		T.eq(p.wood, wood0 - out.placed * Buildings.byId.dirtpath.wood, "paid a tile at a time")
		local n0 = #p.plot.placed
		-- the same line again: every cell taken now
		T.eq(select(2, Plot.paint(p, "dirtpath", line)), "blocked")
		T.eq(#p.plot.placed, n0, "nothing laid twice")
		-- a box, paid until the wood runs out
		p.wood = Buildings.byId.dirtpath.wood * 3
		local box = { free[6], free[7], free[8], free[9], free[10] }
		local ok2, out2 = Plot.paint(p, "dirtpath", box)
		T.truthy(ok2)
		T.eq(out2.placed, 3, "three tiles' worth of wood, three tiles")
		T.eq(select(2, Plot.paint(p, "dirtpath", { free[11] })), "wood")
		-- not a path, too many cells, a locked path
		T.eq(select(2, Plot.paint(p, "patch", line)), "bad_payload")
		local many = {}
		for k = 1, Plot.PAINT_MAX + 1 do
			table.insert(many, { 0, 0 })
		end
		T.eq(select(2, Plot.paint(p, "dirtpath", many)), "bad_payload")
		p.wood = 1e6
		T.eq(select(2, Plot.paint(p, "marblewalk", line)), "locked")
		-- the cells round trip through their request string
		local back = Plot.cells(Plot.cellString(box))
		T.eq(#back, #box)
		T.eq(back[3][1], box[3][1])
		T.eq(back[3][2], box[3][2])
	end)
	T.it("erasing paths: every tile under the cells comes up with half its price back; other pieces stay", function()
		local p = fresh()
		local x, z = spot(p, "patch")
		Plot.place(p, "patch", x, z, 0)
		local cells = {}
		local r = Street.plot(p.tier)
		for z = r.z0 - r.z0 % 2, r.z1, 2 do
			for xx = r.x0 - r.x0 % 2, r.x1, 2 do
				if #cells < 4 and Plot.fits(p.tier, p.plot.placed, "dirtpath", xx, z, 0) then
					table.insert(cells, { xx, z })
				end
			end
		end
		local _, out = Plot.paint(p, "dirtpath", cells)
		T.eq(out.placed, 4)
		local before = #p.plot.placed
		local wood0 = p.wood
		local ok, res = Plot.unpaint(p, cells)
		T.truthy(ok)
		T.eq(res.removed, out.placed, "every tile laid comes up")
		T.eq(#p.plot.placed, before - out.placed)
		T.eq(p.wood, wood0 + out.placed * math.floor(Buildings.byId.dirtpath.wood * Tuning.Refund), "half back each")
		T.eq(p.plot.placed[1].id, "patch", "the patch stays")
		T.eq(select(2, Plot.unpaint(p, cells)), "not_found")
		T.eq(select(2, Plot.unpaint(p, { { x, z } })), "not_found", "a building is never erased")
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
		local before = p.wood
		T.truthy(Plot.store(p, 1))
		T.eq(p.wood, before + math.floor(Buildings.byId.torch.wood * Tuning.Refund))
		T.eq(#p.plot.placed, 1)
		T.eq(select(2, Plot.store(p, 5)), "bad_payload")
		-- a hut cleared away: its driftlings left with no hut; a workplace gone: they rest
		local tx, tz = spot(p, "nest")
		T.truthy(Plot.place(p, "nest", tx, tz, 0))
		local px, pz = spot(p, "patch")
		T.truthy(Plot.place(p, "patch", px, pz, 0))
		local w = { id = 90, sp = "mossbun", home = p.plot.placed[2].uid, work = p.plot.placed[3].uid }
		table.insert(p.pals, w)
		T.truthy(Plot.store(p, 3))
		T.eq(w.work, 0, "its workplace gone: resting")
		T.truthy(Plot.store(p, 2))
		T.eq(w.home, 0, "its hut gone: no hut")
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
	T.it("huts: no more than the island's limit for its level; a bigger island allows more; Replace still works", function()
		local p = fresh()
		for t = 2, #Tuning.HutLimit do
			T.truthy(Tuning.HutLimit[t] > Tuning.HutLimit[t - 1], "more huts each level")
		end
		local limit = Plot.hutLimit(1)
		T.truthy(limit >= 2, "the tips' hut and the questline's second fit")
		for _ = 1, limit do
			local x, z = spot(p, "nest")
			T.truthy((Plot.place(p, "nest", x, z, 0)))
		end
		T.eq(Plot.huts(p.plot.placed), limit)
		local x, z = spot(p, "nest")
		T.eq(select(2, Plot.place(p, "nest", x, z, 0)), "huts", "one past the limit")
		local wood = p.wood
		local px, pz = spot(p, "patch")
		T.truthy((Plot.place(p, "patch", px, pz, 0)), "other buildings still go up")
		T.truthy(p.wood < wood)
		-- a bigger island: room for more, and a small hut replaced with a bigger one at the limit
		p.tier = 2
		for _ = limit + 1, Plot.hutLimit(2) do
			local hx, hz = spot(p, "nest")
			T.truthy((Plot.place(p, "nest", hx, hz, 0)))
		end
		local hx, hz = spot(p, "burrow")
		T.eq(select(2, Plot.place(p, "burrow", hx, hz, 0)), "huts")
		local at = 0
		for i, q in p.plot.placed do
			if q.id == "nest" then
				at = i
			end
		end
		local ok = Plot.replace(p, at, "burrow")
		T.truthy(ok, "Replace with a bigger hut")
		T.eq(Plot.huts(p.plot.placed), Plot.hutLimit(2), "the same count")
	end)
end
