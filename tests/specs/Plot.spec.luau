-- The island's building rules (Logic/Plot; GAME_DESIGN 4): where pieces may stand, placing (paid in shells since 2026-11-14,
-- the island's tier), moving, clearing away (into the inventory since 2026-11-14; never a home or a nest still needed),
-- the piece limit, the inventory and Remove all.
local T = require("../TestKit")
local Tuning = require("../../build/luautest/shared/Config/Tuning")
local Plot = require("../../build/luautest/shared/Logic/Plot")
local Schema = require("../../build/luautest/shared/Logic/Schema")
local Street = require("../../build/luautest/shared/Data/Street")
local Buildings = require("../../build/luautest/shared/Data/Buildings")

-- (an island with no pieces on it: the building rules on their own)
local function fresh(): any
	local p = Schema.default(0, 1)
	p.shells = 1e6
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
	T.it("the dark over the land not open yet: from the open ground's edge to the beach, retreating tier by tier", function()
		-- (the request of 2026-11-20: "Remove the rocks and make it a gradient dark filter instead, with the darkness
		-- retreating as it expands")
		local c = Street.CENTER
		T.eq(Street.darkness(1, c.x, c.z), 0, "the island's heart is lit")
		local land = Street.cellBounds(1)
		local deep, lit, beach = 0, 0, 0
		for z = land.z0, land.z1 do
			for x = land.x0, land.x1 do
				local d = Street.darkness(1, x + 0.5, z + 0.5)
				T.truthy(d >= 0 and d <= 1, "in range")
				local l = Street.layer(1, x, z)
				if Street.buildable(1, x, z) then
					T.truthy(d < 0.2, string.format("open ground barely dark at %d,%d (%.2f)", x, z, d))
					lit += 1
				end
				if l ~= Street.GRASS then
					-- (a hair at most where the grass ends: the radii are kept in direction bins)
					T.truthy(d < 0.03, string.format("no dark past the grass at %d,%d (%.3f)", x, z, d))
					beach += 1
				elseif Street.openDist(1, x, z) > Street.DARK_RAMP + 1 and Street.cellDist(1, x, z) < -Street.DARK_COAST - 1 then
					T.truthy(d == 1, string.format("deep in the dark at %d,%d (%.2f)", x, z, d))
					deep += 1
				end
				T.truthy(Street.walkable(1, x, z) == (l == Street.GRASS or l == Street.SAND or l == Street.WET), "walked on anywhere on the island")
			end
		end
		T.truthy(deep > 1000 and lit > 100 and beach > 500, string.format("%d deep, %d lit, %d past the grass", deep, lit, beach))
		-- a point in the dark gets lighter (never darker) as the island grows, and at the top tier none is left
		for _, pt in { { 30, 6 }, { 0, -30 }, { -40, 20 }, { 50, 6 } } do
			local last = 2
			for tier = 1, Street.TOP do
				local d = Street.darkness(tier, pt[1], pt[2])
				T.truthy(d <= last + 1e-9, string.format("(%d, %d) lighter at tier %d", pt[1], pt[2], tier))
				last = d
			end
			T.eq(last, 0, "all lit at the top tier")
		end
		-- the radii the pixel filter keeps agree with openDist (the distance from the heart less the open radius)
		for _, pt in { { 10, 3 }, { -20, 30 }, { 33, -12 } } do
			local b, rho = Street.darkBin(pt[1] + 0.5, pt[2] + 0.5)
			T.near(rho - Street.openRadii(5)[b], Street.openDist(5, pt[1], pt[2]), 0.6, "a bin's radius")
		end
		T.truthy(not Plot.fits(1, {}, "torch", 30, 6, 0), "nothing built in the dark")
	end)
	-- (the request of 2026-11-14: "make the first snack stall in the tutorial free")
	T.it("the tips' snack stall: free while the tips ask for a shop, full price before and after", function()
		local p = fresh()
		local full = Buildings.byId.stall.shells
		p.tut = Plot.TIP_SHOP - 1
		T.eq(Plot.price(p, "stall"), full, "before its step")
		p.tut = Plot.TIP_SHOP
		T.eq(Plot.price(p, "stall"), 0, "on its step")
		T.eq(Plot.price(p, "cafe"), Buildings.byId.cafe.shells, "only the stall")
		local sh = p.shells
		local x, z = spot(p, "stall")
		local ok = Plot.place(p, "stall", x, z, 0)
		T.truthy(ok, "placed")
		T.eq(p.shells, sh, "paid nothing")
		p.tut = Plot.TIP_SHOP + 1
		T.eq(Plot.price(p, "stall"), full, "after it")
	end)

	T.it("a quarter turn swaps the footprint", function()
		T.eq(select(1, Plot.footprint("bench", 0)), 3)
		T.eq(select(2, Plot.footprint("bench", 0)), 2)
		T.eq(select(1, Plot.footprint("bench", 90)), 2)
		T.eq(select(2, Plot.footprint("bench", 270)), 3)
	end)
	T.it("fits: on the island's buildable grass, on the grid, off the tree and other pieces", function()
		T.truthy(Plot.fits(1, {}, "flowers", 8, 4, 0), "the east lawn")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 18, 5, 0)), "outside", "past the east coast")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 0, 22, 0)), "outside", "on the beach")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8.5, 4, 0)), "outside", "whole studs")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8, 4, 45)), "outside", "quarter turns")
		T.eq(select(2, Plot.fits(1, {}, "dirtpath", 9, 4, 0)), "outside", "a tile on the even studs")
		T.truthy(Plot.fits(1, {}, "dirtpath", 8, 4, 0))
		T.truthy(Plot.fits(1, {}, "torch", 0, 4, 0), "the middle is the island's own: no plaza since 2026-11-20")
		local tree = { { uid = 9, id = "tree", x = -4, z = 2, rot = 0, lvl = 1 } }
		T.eq(select(2, Plot.fits(1, tree, "torch", 0, 4, 0)), "overlap", "not on the Tree of Life in the middle")
		T.truthy(Plot.fits(1, {}, "torch", 0, 12, 0), "where the path to the jetty ran: the island's to build on now")
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
	T.it("place: paid in shells, the tier reached, a uid each", function()
		local p = fresh()
		p.nextId = 51
		local ok, data = Plot.place(p, "pier", 8, 4, 0)
		T.truthy(ok)
		T.eq(p.shells, 1e6 - Buildings.byId.pier.shells)
		T.eq((p :: any).wood, nil, "no wood")
		T.eq(data.uid, 51)
		T.deepEq(p.plot.placed[1], { uid = 51, id = "pier", x = 8, z = 4, rot = 0, lvl = 1 })
		T.eq(p.stats.built, 1)
		local ox, oz = spot(p, "orchard")
		T.eq(select(2, Plot.place(p, "orchard", ox, oz, 0)), "locked", "a tier 2 building")
		p.tier = 2
		ox, oz = spot(p, "orchard")
		T.truthy(Plot.place(p, "orchard", ox, oz, 0))
		local hx, hz = spot(p, "burrow")
		p.shells = 10
		T.eq(select(2, Plot.place(p, "burrow", hx, hz, 0)), "money")
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
		-- (a spot with room for the bigger burrow too: the open ground's first row is rock round its corners)
		local x, z = spot(p, "burrow")
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
		local before = p.shells
		local ok = Plot.replace(p, 1, "burrow")
		T.truthy(ok, "a burrow where the hut stood")
		T.eq(p.plot.placed[1].id, "burrow")
		T.eq(p.plot.placed[1].uid, uid, "its uid stays")
		T.eq(p.shells, before - (Buildings.byId.burrow.shells - math.floor(Buildings.byId.nest.shells * Tuning.Refund)))
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
	T.it("drawing paths: a line or a box of tiles in one go, passing over cells that don't fit, while room and shells last", function()
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
		-- a line of six cells, one of them out in the dark (passed over)
		local line = { free[1], free[2], free[3], free[4], free[5], { 40, 6 } }
		local shells0 = p.shells
		local ok, out = Plot.paint(p, "dirtpath", line)
		T.truthy(ok, "a line goes down")
		T.eq(out.placed + out.skipped, 6, "every cell placed or passed over")
		T.eq(p.shells, shells0 - out.placed * Buildings.byId.dirtpath.shells, "paid a tile at a time")
		local n0 = #p.plot.placed
		-- the same line again: every cell taken now
		T.eq(select(2, Plot.paint(p, "dirtpath", line)), "blocked")
		T.eq(#p.plot.placed, n0, "nothing laid twice")
		-- a box, paid until the shells run out
		p.shells = Buildings.byId.dirtpath.shells * 3
		local box = { free[6], free[7], free[8], free[9], free[10] }
		local ok2, out2 = Plot.paint(p, "dirtpath", box)
		T.truthy(ok2)
		T.eq(out2.placed, 3, "three tiles' worth of shells, three tiles")
		T.eq(select(2, Plot.paint(p, "dirtpath", { free[11] })), "money")
		-- not a path, too many cells, a locked path
		T.eq(select(2, Plot.paint(p, "patch", line)), "bad_payload")
		local many = {}
		for k = 1, Plot.PAINT_MAX + 1 do
			table.insert(many, { 0, 0 })
		end
		T.eq(select(2, Plot.paint(p, "dirtpath", many)), "bad_payload")
		p.shells = 1e6
		T.eq(select(2, Plot.paint(p, "marblewalk", line)), "locked")
		-- the cells round trip through their request string
		local back = Plot.cells(Plot.cellString(box))
		T.eq(#back, #box)
		T.eq(back[3][1], box[3][1])
		T.eq(back[3][2], box[3][2])
	end)
	T.it("erasing paths: every tile under the cells comes up into the inventory; other pieces stay", function()
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
		local shells0 = p.shells
		local ok, res = Plot.unpaint(p, cells)
		T.truthy(ok)
		T.eq(res.removed, out.placed, "every tile laid comes up")
		T.eq(#p.plot.placed, before - out.placed)
		T.eq(p.shells, shells0, "nothing paid back")
		T.eq(Plot.held(p, "dirtpath"), out.placed, "each tile into the inventory")
		T.eq(p.plot.placed[1].id, "patch", "the patch stays")
		T.eq(select(2, Plot.unpaint(p, cells)), "not_found")
		T.eq(select(2, Plot.unpaint(p, { { x, z } })), "not_found", "a building is never erased")
	end)
	T.it("move, clear away (into the inventory, the workers idle), not a home or a nest still needed, the limit", function()
		local p = fresh()
		T.truthy(Plot.place(p, "torch", 8, 4, 0))
		T.truthy(Plot.place(p, "torch", 10, 4, 0), "as many as fit")
		T.eq(select(2, Plot.place(p, "torch", 8, 4, 0)), "blocked", "on another piece")
		T.truthy(Plot.move(p, 1, 8, 8, 90))
		T.eq(p.plot.placed[1].z, 8)
		T.truthy(not (Plot.move(p, 1, 40, 6, 0)), "not out into the dark")
		T.eq(select(2, Plot.move(p, 9, 8, 8, 0)), "bad_payload")
		local before = p.shells
		local okS, dataS = Plot.store(p, 1)
		T.truthy(okS and dataS.id == "torch")
		T.eq(p.shells, before, "nothing paid back")
		T.eq(Plot.held(p, "torch"), 1, "the torch waits in the inventory")
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
	T.it("refit tries each piece against its neighbours alone and finds the same overlaps as against all of them", function()
		local p = fresh()
		p.tier = 6
		-- a crowded island: pieces laid in rows, a fence through one, two stacked on one spot and a tile under a hut
		local placed: { any } = {}
		local uid = 0
		local function put(id: string, x: number, z: number, rot: number)
			uid += 1
			table.insert(placed, { uid = uid, id = id, x = x, z = z, rot = rot, lvl = 1 })
		end
		local b = Street.plot(p.tier)
		for z = b.z0 + 2, b.z1 - 3, 3 do
			for x = b.x0 + 2, b.x1 - 3, 3 do
				if Street.buildable(p.tier, x, z) and Street.buildable(p.tier, x + 1, z + 1) then
					put("torch", x, z, 0)
				end
			end
		end
		local n0 = #placed
		local q = placed[n0 // 2]
		put("torch", q.x, q.z, 0) -- stacked on another
		put("picket", q.x - q.x % 2, q.z - q.z % 2 + 2, 0)
		p.plot.placed = placed
		p.nextId = uid + 1
		-- the old rule, every piece against every one kept before it
		local kept, homeless = {}, 0
		for _, o in placed do
			if Plot.fits(p.tier, kept, o.id, o.x, o.z, o.rot) then
				table.insert(kept, o)
			else
				homeless += 1
			end
		end
		T.truthy(homeless >= 1, "the stacked torch at least")
		local moved, cleared = Plot.refit(p)
		T.eq(moved + cleared, homeless, "the same pieces made room")
		-- and an island already in order is left as it is
		local before = #p.plot.placed
		T.eq(select(1, Plot.refit(p)) + select(2, Plot.refit(p)), 0)
		T.eq(#p.plot.placed, before)
	end)
	T.it("fences: drawn along the even grid lines, apart from the pieces; not through a building, along one is fine", function()
		local p = fresh()
		local ok, data = Plot.fence(p, "picket", { { 8, 4, 0 }, { 10, 4, 0 }, { 12, 4, 90 } })
		T.truthy(ok)
		T.eq(data.placed, 3)
		local pk, sr = Buildings.byId.picket.shells, Buildings.byId.splitrail.shells
		T.eq(p.shells, 1e6 - 3 * pk, "paid in shells")
		T.eq(select(1, Plot.used(p, "picket")), 3)
		T.eq(select(2, Plot.used(p, "picket")), Plot.fenceLimit(1), "its own limit")
		T.eq(select(1, Plot.used(p, "flowers")), 0, "the pieces don't count fences")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 4, 0)), "overlap", "one fence an edge")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 9, 4, 0)), "outside", "the even grid")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 4, 180)), "outside", "east or south")
		T.truthy(Plot.fits(1, p.plot.placed, "picket", -2, 4, 0), "across the middle: no plaza there now")
		-- a building where the fence runs through refused; one beside it fine; a fence through a building refused
		T.eq(select(2, Plot.fits(1, p.plot.placed, "patch", 8, 3, 0)), "overlap", "a fence through it")
		T.truthy(Plot.fits(1, p.plot.placed, "patch", 8, 5, 0), "a fence along its side")
		T.truthy(Plot.place(p, "patch", 8, 5, 0))
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 6, 0)), "overlap", "a fence through a building")
		T.truthy(Plot.fits(1, p.plot.placed, "picket", 8, 8, 0), "along its far side")
		-- another fence over one: swapped, the old length into the inventory
		local before = p.shells
		ok, data = Plot.fence(p, "splitrail", { { 8, 4, 0 } })
		T.truthy(ok)
		T.eq(data.swapped, 1)
		T.eq(p.shells, before - sr)
		T.eq(Plot.held(p, "picket"), 1)
		-- taken down: each into the inventory
		before = p.shells
		ok, data = Plot.unfence(p, { { 8, 4, 0 }, { 12, 4, 90 } })
		T.truthy(ok)
		T.eq(data.removed, 2)
		T.eq(p.shells, before)
		T.truthy(Plot.held(p, "splitrail") == 1 and Plot.held(p, "picket") == 2, "both lengths waiting")
		-- the inventory's lengths go up again for nothing
		before = p.shells
		ok, data = Plot.fence(p, "picket", { { 8, 4, 0 } })
		T.truthy(ok and data.placed == 1 and p.shells == before and Plot.held(p, "picket") == 1, "a length from the inventory, free")
		T.eq(pk > 0, true)
		T.eq(select(2, Plot.unfence(p, { { 30, 30, 0 } })), "not_found")
		T.eq(select(2, Plot.fence(p, "crystalfence", { { 0, -6, 0 } })), "locked")
		T.eq(select(2, Plot.fence(p, "dirtpath", { { 0, -6, 0 } })), "bad_payload")
	end)
	T.it("water: tiles drawn like paths; pieces stay off it, a bridge goes over it, lily pads only on it", function()
		local p = fresh()
		p.tier = 3
		local cells = { { 8, -8 }, { 10, -8 }, { 12, -8 }, { 8, -6 }, { 10, -6 }, { 12, -6 } }
		local ok, data = Plot.paint(p, "stream", cells)
		T.truthy(ok)
		T.eq(data.placed, 6)
		T.eq(select(1, Plot.used(p, "dirtpath")), 6, "water and paths count together")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "flowers", 8, -8, 0)), "overlap", "no flower bed in the river")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "dirtpath", 8, -8, 0)), "overlap", "no path on the water")
		T.truthy(Plot.fits(3, p.plot.placed, "lilypads", 10, -8, 0), "lily pads on water")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "lilypads", 14, -8, 0)), "outside", "lily pads off the water")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "lilypads", 13, -7, 0)), "outside", "wholly on water")
		T.truthy(Plot.fits(3, p.plot.placed, "plankbridge", 10, -10, 0), "a bridge across the stream, its ends on grass")
		T.truthy(Plot.place(p, "lilypads", 10, -8, 0))
		T.truthy(Plot.place(p, "plankbridge", 12, -10, 0))
		T.eq(select(2, Plot.fits(3, p.plot.placed, "steppingstones", 10, -8, 0)), "overlap", "one floating thing a place")
		-- another water over water: swapped where it lies
		ok, data = Plot.paint(p, "river", { { 8, -8 } })
		T.truthy(ok)
		T.eq(data.swapped, 1)
		-- erasing paths leaves the water; erasing water takes what floats on it too
		T.eq(select(2, Plot.unpaint(p, { { 10, -8 } }, "path")), "not_found")
		ok, data = Plot.unpaint(p, { { 10, -8 } }, "water")
		T.truthy(ok)
		T.eq(data.removed, 1)
		T.eq(data.floated, 1, "the lily pads came up with it")
		for _, q in p.plot.placed do
			T.truthy(q.id ~= "lilypads", "no lily pads on the grass")
		end
	end)
	T.it("a paved yard: decor, plants, fun pieces, huts and workplaces stand on path tiles; the tree and water pieces don't", function()
		-- (the request of 2026-11-14: "make it such that paths can be put below buildings, and buildings can be put on to
		-- paths")
		local p = fresh()
		p.tier = 3
		local cells = {}
		for z = -8, -4, 2 do
			for x = 8, 12, 2 do
				table.insert(cells, { x, z })
			end
		end
		T.truthy(Plot.paint(p, "snowpath", cells))
		T.truthy(Plot.onPaths("snowman") and Plot.onPaths("pine") and Plot.onPaths("parkbench"))
		T.truthy(Plot.onPaths("nest") and Plot.onPaths("patch"), "huts and workplaces too")
		T.truthy(not Plot.onPaths("lilypads") and not Plot.onPaths("tree") and not Plot.onPaths("picket") and not Plot.onPaths("stream"))
		T.truthy(Plot.place(p, "snowman", 9, -7, 0), "a snowman on the snow")
		T.truthy(Plot.place(p, "pine", 11, -5, 0), "a tree in it")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "snowman", 9, -7, 0)), "overlap", "two pieces still never share a spot")
		local hutOn = fresh()
		hutOn.tier = 3
		T.truthy(Plot.paint(hutOn, "snowpath", cells))
		T.truthy(Plot.fits(3, hutOn.plot.placed, "nest", 8, -8, 0), "a hut on the paving")
		T.truthy(Plot.fits(3, hutOn.plot.placed, "patch", 8, -8, 0), "a farm on it")
		-- paving round and under what stands already: decor and a hut alike
		local q = fresh()
		q.tier = 3
		T.truthy(Plot.place(q, "gnome", 9, -7, 0))
		T.truthy(Plot.place(q, "nest", 13, -8, 0))
		local ok, data = Plot.paint(q, "sandtrail", { { 8, -8 }, { 12, -8 } })
		T.truthy(ok)
		T.eq(data.placed, 2, "under the gnome and under the hut")
		-- taking the paving up leaves the decor where it stands
		T.truthy(Plot.unpaint(q, { { 8, -8 } }, "path"))
		local gnome = false
		for _, x in q.plot.placed do
			gnome = gnome or x.id == "gnome"
		end
		T.truthy(gnome)
	end)
	T.it("paths over paths: another look swapped where it lies (the old into the inventory), the same look passed over", function()
		local p = fresh()
		p.tier = 2
		T.truthy(Plot.paint(p, "dirtpath", { { 8, 4 }, { 10, 4 } }))
		local before = p.shells
		local ok, data = Plot.paint(p, "stonepath", { { 8, 4 }, { 10, 4 }, { 12, 4 } })
		T.truthy(ok)
		T.eq(data.swapped, 2)
		T.eq(data.placed, 1)
		T.eq(p.shells, before - 3 * Buildings.byId.stonepath.shells)
		T.eq(Plot.held(p, "dirtpath"), 2, "the old tiles into the inventory")
		ok, data = Plot.paint(p, "stonepath", { { 8, 4 } })
		T.eq(ok, false, "nothing changed")
		T.eq(select(2, Plot.paint(p, "stream", { { 8, 4 } })), "blocked", "water doesn't swap a path")
	end)
	T.it("replacing decor: from its own row (a tree for a tree); drawn pieces aren't replaced", function()
		local p = fresh()
		p.tier = 10
		local reps = Plot.replacements({ uid = 1, id = "oak", x = 0, z = 0, rot = 0, lvl = 1 }, 10)
		T.truthy(#reps > 3)
		for _, id in reps do
			T.eq(Buildings.byId[id].sub, "trees", id)
		end
		T.eq(#Plot.replacements({ uid = 1, id = "picket", x = 0, z = 0, rot = 0, lvl = 1 }, 10), 0)
		T.eq(#Plot.replacements({ uid = 1, id = "stream", x = 0, z = 0, rot = 0, lvl = 1 }, 10), 0)
		-- the server keeps to the same rows: a gnome can't be swapped for a snowman, nor a path for a stream
		local x, z = spot(p, "gnome")
		T.truthy(Plot.place(p, "gnome", x, z, 0))
		local i = #p.plot.placed
		T.eq(select(2, Plot.replace(p, i, "snowman")), "bad_payload", "another row")
		T.truthy(Plot.replace(p, i, "birdbath"), "the same row")
		local px, pz = spot(p, "dirtpath")
		T.truthy(Plot.paint(p, "dirtpath", { { px, pz } }))
		T.eq(select(2, Plot.replace(p, #p.plot.placed, "gravel")), "bad_payload", "drawn pieces are drawn over instead")
	end)
	T.it("every piece fits somewhere on the smallest island", function()
		for _, d in Buildings.list do
			-- (a piece that floats needs water: Plot's water test)
			if d.water == "on" then
				continue
			end
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
	T.it("housing: the huts' room together under the island's limit, however many huts; a bigger island allows more", function()
		-- (the request of 2026-11-14: "instead of a hut (building) limit per expansion, make it such that the limit of
		-- driftling housing is the limit, such that you can have 2 driftling huts in the place of a cozy burrow at the cost
		-- of comfort")
		local p = fresh()
		for t = 2, #Tuning.HousingLimit do
			T.truthy(Tuning.HousingLimit[t] > Tuning.HousingLimit[t - 1], "more room each level")
		end
		T.eq(#Tuning.HousingLimit, #Tuning.TierCost, "a limit for every tier")
		local limit = Plot.housingLimit(1)
		T.truthy(limit >= 4, "the tips' hut and the questline's second fit")
		local nest = Buildings.byId.nest.slots
		for _ = 1, limit // nest do
			local x, z = spot(p, "nest")
			T.truthy((Plot.place(p, "nest", x, z, 0)))
		end
		T.eq(Plot.housing(p.plot.placed), limit)
		local x, z = spot(p, "nest")
		T.eq(select(2, Plot.place(p, "nest", x, z, 0)), "huts", "one hut past the room")
		local shells = p.shells
		local px, pz = spot(p, "patch")
		T.truthy((Plot.place(p, "patch", px, pz, 0)), "other buildings still go up")
		T.truthy(p.shells < shells)
		-- a bigger island: a Cozy Burrow, or two Driftling Huts in its place (the same room, no comfort)
		p.tier = 2
		local room = Plot.housingLimit(2) - Plot.housing(p.plot.placed)
		T.eq(Buildings.byId.burrow.slots, 4 * nest, "a burrow holds four huts' driftlings")
		T.truthy(Buildings.byId.burrow.comfort > Buildings.byId.nest.comfort, "with more comfort")
		while room >= nest do
			local hx, hz = spot(p, "nest")
			T.truthy((Plot.place(p, "nest", hx, hz, 0)), "a small hut while there's room")
			room -= nest
		end
		T.eq(Plot.housing(p.plot.placed), Plot.housingLimit(2), "the room full of small huts")
		T.truthy(Plot.huts(p.plot.placed) > Tuning.HousingLimit[2] // Buildings.byId.burrow.slots, "more huts than burrows would take")
		local hx, hz = spot(p, "burrow")
		T.eq(select(2, Plot.place(p, "burrow", hx, hz, 0)), "huts", "no room for a burrow")
		local at = 0
		for i, q in p.plot.placed do
			if q.id == "nest" then
				at = i
			end
		end
		T.eq(select(2, Plot.replace(p, at, "burrow")), "huts", "a bigger hut needs the room for the difference")
		-- four huts down, a burrow up: the same room, more comfort
		for _ = 1, Buildings.byId.burrow.slots // nest do
			for i = #p.plot.placed, 1, -1 do
				if p.plot.placed[i].id == "nest" then
					Plot.store(p, i)
					break
				end
			end
		end
		hx, hz = spot(p, "burrow")
		T.truthy((Plot.place(p, "burrow", hx, hz, 0)), "a burrow where four huts stood")
		T.eq(Plot.housing(p.plot.placed), Plot.housingLimit(2), "the same room")
		-- a smaller hut always replaces a bigger one
		local bi = 0
		for i, q in p.plot.placed do
			if q.id == "burrow" then
				bi = i
			end
		end
		T.truthy((Plot.replace(p, bi, "nest")), "smaller is always fine")
	end)
	T.it("after an expansion, two of the newest huts and two of the newest workplaces fill what it adds", function()
		-- (the request of 2026-11-19: "after an expansion, buff huts and work buildings such that buying 2 huts and 2
		-- work buildings of the highest tier is enough to fill the cap, assuming you also maxxed out the caps before
		-- expanding")
		local function newest(t: number, kind: string, field: string): (string?, number)
			local id, best, bestTier = nil, 0, 0
			for _, d in Buildings.list do
				local v = (d :: any)[field] :: number
				if d.kind == kind and d.tier <= t and (d.tier > bestTier or (d.tier == bestTier and v > best)) then
					id, best, bestTier = d.id, v, d.tier
				end
			end
			return id, best
		end
		for t = 2, #Tuning.HousingLimit do
			local hut, slots = newest(t, "nest", "slots")
			local work, jobs = newest(t, "work", "jobs")
			local grew = Plot.housingLimit(t) - Plot.housingLimit(t - 1)
			T.eq(2 * slots, grew, string.format("tier %d: two %s fill the %d more room", t, tostring(hut), grew))
			T.eq(2 * jobs, Plot.workLimit(t) - Plot.workLimit(t - 1), string.format("tier %d: two %s fill the %d more places", t, tostring(work), grew))
			-- (the newest is the biggest there: never a smaller hut or workplace for a later tier)
			for _, d in Buildings.list do
				if d.tier <= t and d.kind == "nest" then
					T.truthy(d.slots <= slots, string.format("tier %d: %s no bigger than %s", t, d.id, tostring(hut)))
				elseif d.tier <= t and d.kind == "work" then
					T.truthy(d.jobs <= jobs, string.format("tier %d: %s no bigger than %s", t, d.id, tostring(work)))
				end
			end
		end
		-- played through: an island at its tier's caps grows, two of each go up and both caps are full again
		local p = fresh()
		p.shells = 1e12
		local function full(t: number)
			p.tier = t
			local _, slots = newest(t, "nest", "slots")
			local _, jobs = newest(t, "work", "jobs")
			for _ = 1, 2 do
				local hut = newest(t, "nest", "slots") :: string
				local work = newest(t, "work", "jobs") :: string
				local hx, hz = spot(p, hut)
				T.truthy((Plot.place(p, hut, hx, hz, 0)), string.format("tier %d: a %s fits", t, hut))
				local wx, wz = spot(p, work)
				T.truthy((Plot.place(p, work, wx, wz, 0)), string.format("tier %d: a %s fits", t, work))
			end
			T.eq(Plot.housing(p.plot.placed), Plot.housingLimit(t), string.format("tier %d: the huts full (%d a hut)", t, slots))
			T.eq(Plot.work(p.plot.placed), Plot.workLimit(t), string.format("tier %d: the workplaces full (%d a workplace)", t, jobs))
		end
		-- (the first island filled with its own, then each of the next few tiers by two and two)
		for _ = 1, Plot.housingLimit(1) // Buildings.byId.nest.slots do
			local hx, hz = spot(p, "nest")
			Plot.place(p, "nest", hx, hz, 0)
		end
		for _ = 1, Plot.workLimit(1) // Buildings.byId.patch.jobs do
			local x, z = spot(p, "patch")
			Plot.place(p, "patch", x, z, 0)
		end
		for t = 2, 5 do
			full(t)
		end
	end)
	T.it("the work cap: workplaces take more driftlings, their places together within the driftling limit", function()
		-- (the request of 2026-11-18: "increase the capacity of work buildings by alot, in turn, make a cap for the amount
		-- of work spaces possible in each island expansion. it should match the number of max driftlings possible for
		-- each expansion")
		local most = 0
		for _, d in Buildings.list do
			local works = d.kind == "work"
			T.eq(d.jobs > 0, works, d.id .. ": places only at a workplace")
			if works then
				T.eq(d.jobs, Tuning.WorkRoom[d.tier], d.id .. ": its tier's room")
				most = math.max(most, d.jobs)
			end
		end
		T.eq(Buildings.byId.patch.jobs, 2, "the first island's workplaces keep 2")
		T.truthy(most >= 16 * Buildings.byId.patch.jobs // 2, "the biggest take many more (16 times the old 2)")
		T.eq(#Tuning.WorkRoom, #Tuning.TierCost, "a room for every tier")
		for t = 1, #Tuning.HousingLimit do
			T.eq(Plot.workLimit(t), Plot.housingLimit(t), "tier " .. t .. ": the cap is the driftling limit")
			-- (the first island's 2-place workplaces fill any cap to the last place)
			T.eq(Plot.workLimit(t) % Buildings.byId.patch.jobs, 0, "tier " .. t .. ": filled exactly")
		end
		T.truthy(Buildings.byId.lumber.jobs + Buildings.byId.patch.jobs + Buildings.byId.stall.jobs <= Plot.workLimit(1), "the tips' camp, patch and stall fit on the first island")
		-- the first island: patches up to the cap, then no more workplaces; huts still go up
		local p = fresh()
		local cap = Plot.workLimit(1)
		for _ = 1, cap // Buildings.byId.patch.jobs do
			local x, z = spot(p, "patch")
			T.truthy((Plot.place(p, "patch", x, z, 0)))
		end
		T.eq(Plot.work(p.plot.placed), cap, "every place the island may have")
		local x, z = spot(p, "lumber")
		local shells = p.shells
		T.eq(select(2, Plot.place(p, "lumber", x, z, 0)), "work", "one workplace past the cap")
		T.eq(p.shells, shells, "nothing paid")
		local nx, nz = spot(p, "nest")
		T.truthy((Plot.place(p, "nest", nx, nz, 0)), "a hut still goes up")
		-- a bigger island: an orchard takes 8; Replace needs the room for the difference
		p.tier = 2
		local room = Plot.workLimit(2) - Plot.work(p.plot.placed)
		local orchard = Buildings.byId.orchard.jobs
		T.truthy(orchard >= 3 * Buildings.byId.patch.jobs, "an orchard takes three patches' driftlings")
		while room >= orchard do
			local ox, oz = spot(p, "orchard")
			T.truthy((Plot.place(p, "orchard", ox, oz, 0)), "an orchard while there's room")
			room -= orchard
		end
		while room >= Buildings.byId.patch.jobs do
			local ox, oz = spot(p, "patch")
			T.truthy((Plot.place(p, "patch", ox, oz, 0)))
			room -= Buildings.byId.patch.jobs
		end
		T.eq(Plot.work(p.plot.placed), Plot.workLimit(2), "the cap full")
		local pi, oi = 0, 0
		for i, q in p.plot.placed do
			if q.id == "patch" then
				pi = i
			elseif q.id == "orchard" then
				oi = i
			end
		end
		T.eq(select(2, Plot.replace(p, pi, "orchard")), "work", "a bigger workplace needs the room for the difference")
		-- a smaller one always: its first workers stay, the rest rest
		local ouid = p.plot.placed[oi].uid
		for k = 1, orchard do
			table.insert(p.pals, { id = 9000 + k, sp = "mossbun", home = 1, work = ouid, muts = {} })
		end
		T.truthy((Plot.replace(p, oi, "patch")), "smaller is always fine")
		local still = 0
		for _, x in p.pals do
			still += if x.work == ouid then 1 else 0
		end
		T.eq(still, Buildings.byId.patch.jobs, "the patch keeps its first two workers")
		-- two patches put away, then there's room for the orchard again
		for _ = 1, 2 do
			for i = #p.plot.placed, 1, -1 do
				if p.plot.placed[i].id == "patch" and p.plot.placed[i].uid ~= ouid then
					Plot.store(p, i)
					break
				end
			end
		end
		T.truthy((Plot.replace(p, (function()
			for i, q in p.plot.placed do
				if q.uid == ouid then
					return i
				end
			end
			return 0
		end)(), "orchard")), "back to an orchard once there's room")
	end)
	T.it("Hatcheries: one where they open, more on bigger islands", function()
		-- (the request of 2026-11-14: "there should also be a hatchery limit per expansion. the first expansion where you
		-- unlock hatcheries, make the limit 1")
		local open = Buildings.byId.hatchery.tier
		T.eq(Plot.hatcheryLimit(open), 1, "one on the first level they open at")
		T.eq(Plot.hatcheryLimit(open - 1), 0)
		T.eq(#Tuning.HatcheryLimit, #Tuning.TierCost)
		for t = 2, #Tuning.HatcheryLimit do
			T.truthy(Tuning.HatcheryLimit[t] >= Tuning.HatcheryLimit[t - 1], "never fewer on a bigger island")
		end
		T.truthy(Plot.hatcheryLimit(#Tuning.TierCost) > 1, "more later")
		local p = fresh()
		p.tier = open
		local x, z = spot(p, "hatchery")
		T.truthy((Plot.place(p, "hatchery", x, z, 0)))
		x, z = spot(p, "hatchery")
		T.eq(select(2, Plot.place(p, "hatchery", x, z, 0)), "hatcheries", "a second one waits for a bigger island")
		while Plot.hatcheryLimit(p.tier) < 2 do
			p.tier += 1
		end
		x, z = spot(p, "hatchery")
		T.truthy((Plot.place(p, "hatchery", x, z, 0)), "a bigger island: a second one")
		T.eq(Plot.hatcheries(p.plot.placed), 2)
	end)
	T.it("boost buildings: two of each at most, on every island; an older save's third stays", function()
		-- (the request of 2026-11-20: "make the max of each boosts building to be 2")
		T.eq(Plot.boostLimit(), 2)
		T.eq(Tuning.BoostEach, 2)
		local boosts = 0
		for _, d in Buildings.list do
			if d.kind == "gen" then
				boosts += 1
				T.truthy(Plot.isBoost(d.id), d.id)
			end
		end
		T.truthy(boosts >= 8, "every boost building is one")
		T.truthy(not Plot.isBoost("patch") and not Plot.isBoost("hatchery") and not Plot.isBoost("nest"), "nothing else")
		local p = fresh()
		p.tier = #Tuning.TierCost
		for k = 1, 2 do
			local x, z = spot(p, "windmill")
			T.truthy((Plot.place(p, "windmill", x, z, 0)), "windmill " .. k)
		end
		T.eq(Plot.boosts(p.plot.placed, "windmill"), 2)
		T.truthy(Plot.boostFull(p.plot.placed, "windmill"))
		local n0, s0 = #p.plot.placed, p.shells
		local x, z = spot(p, "windmill")
		T.eq(select(2, Plot.place(p, "windmill", x, z, 0)), "boosts", "a third windmill is refused")
		T.truthy(#p.plot.placed == n0 and p.shells == s0, "nothing placed, nothing paid")
		-- another boost building still goes up, two of it
		for k = 1, 2 do
			x, z = spot(p, "smokehouse")
			T.truthy((Plot.place(p, "smokehouse", x, z, 0)), "smokehouse " .. k)
		end
		x, z = spot(p, "smokehouse")
		T.eq(select(2, Plot.place(p, "smokehouse", x, z, 0)), "boosts")
		-- a smokehouse can't become a third windmill; a windmill put away comes back down only while there's room
		local si = 0
		for i, q in p.plot.placed do
			if q.id == "smokehouse" then
				si = i
			end
		end
		T.eq(select(2, Plot.replace(p, si, "windmill")), "boosts", "no third windmill by replacing")
		T.truthy((Plot.replace(p, si, "toolshed")), "a tool shed in its place is fine")
		local wi = 0
		for i, q in p.plot.placed do
			if q.id == "windmill" then
				wi = i
			end
		end
		T.truthy((Plot.store(p, wi)), "a windmill into the inventory")
		T.eq(Plot.held(p, "windmill"), 1)
		x, z = spot(p, "windmill")
		local ok, data = Plot.place(p, "windmill", x, z, 0)
		T.truthy(ok and data.free, "back down from the inventory: room for a second again")
		-- an older save with three keeps them (nothing is ever taken away), and builds no fourth
		local raw = Schema.default(0, 1)
		raw.tier = 6
		raw.plot.placed = {}
		for k = 1, 3 do
			local q = { uid = 500 + k, id = "windmill", x = 0, z = 0, rot = 0, lvl = 1 }
			q.x, q.z = spot(raw, "windmill")
			table.insert(raw.plot.placed, q)
		end
		local old = Schema.reconcile(raw, 0, 1)
		T.eq(Plot.boosts(old.plot.placed, "windmill"), 3, "an older save's three windmills stay")
		old.shells = 1e9
		x, z = spot(old, "windmill")
		T.eq(select(2, Plot.place(old, "windmill", x, z, 0)), "boosts", "and it builds no fourth")
	end)
	T.it("the inventory: taken away into it, down again for nothing, Remove all, sold for a share", function()
		-- (the request of 2026-11-14: "also, add an inventory system to build mode, players can remove buildings to put
		-- them in their inventory. add a button to remove all buildings, remove all path/water etc, and a tool to quick
		-- remove buildings and paths")
		local p = fresh()
		p.tier = 3
		T.eq(next(Schema.default(0, 1).inv), nil, "a new island's inventory is empty")
		local x, z = spot(p, "patch")
		T.truthy(Plot.place(p, "patch", x, z, 0))
		T.truthy(Plot.store(p, #p.plot.placed))
		T.eq(Plot.held(p, "patch"), 1)
		-- placing one that waits there: free, and it leaves the inventory
		local before = p.shells
		local ok, data = Plot.place(p, "patch", x, z, 0)
		T.truthy(ok and data.free == true, "from the inventory")
		T.eq(p.shells, before, "for nothing")
		T.eq(Plot.held(p, "patch"), 0)
		local x2, z2 = spot(p, "patch")
		ok, data = Plot.place(p, "patch", x2, z2, 0)
		T.truthy(ok and data.free == false and p.shells == before - Buildings.byId.patch.shells, "none left: paid as ever")
		-- the limits still hold for a free one
		p.inv.nest = 99
		local room = Plot.housingLimit(p.tier)
		local placedHuts = 0
		while Plot.housing(p.plot.placed) + Buildings.byId.nest.slots <= room do
			local hx, hz = spot(p, "nest")
			T.truthy((Plot.place(p, "nest", hx, hz, 0)))
			placedHuts += 1
		end
		local hx, hz = spot(p, "nest")
		T.eq(select(2, Plot.place(p, "nest", hx, hz, 0)), "huts", "the housing limit still holds")
		T.eq(Plot.held(p, "nest"), 99 - placedHuts)
		-- paths from the inventory first, then paid
		p.inv.dirtpath = 1
		before = p.shells
		local cells = {}
		local r = Street.plot(p.tier)
		for zz = r.z0 - r.z0 % 2, r.z1, 2 do
			for xx = r.x0 - r.x0 % 2, r.x1, 2 do
				if #cells < 2 and Plot.fits(p.tier, p.plot.placed, "dirtpath", xx, zz, 0) then
					table.insert(cells, { xx, zz })
				end
			end
		end
		ok, data = Plot.paint(p, "dirtpath", cells)
		T.truthy(ok and data.placed == 2)
		T.eq(p.shells, before - Buildings.byId.dirtpath.shells, "one tile free, one paid")
		T.eq(Plot.held(p, "dirtpath"), 0)
		-- Remove all: every building and decor (never the tree), then every tile, into the inventory
		local tree = 0
		for _, q in p.plot.placed do
			if Plot.isFixed(q.id) then
				tree += 1
			end
		end
		local pieces = 0
		for _, q in p.plot.placed do
			if Plot.group(q.id) == "piece" then
				pieces += 1
			end
		end
		ok, data = Plot.clear(p, "pieces")
		T.truthy(ok and data.removed == pieces, "every piece taken away")
		T.eq(Plot.held(p, "nest"), 99, "the huts back in the inventory")
		ok, data = Plot.clear(p, "tiles")
		T.truthy(ok and data.removed == 2 and Plot.held(p, "dirtpath") == 2, "the tiles too")
		local left = 0
		for _, q in p.plot.placed do
			left += 1
			T.truthy(Plot.isFixed(q.id), "only the tree stays")
		end
		T.eq(left, tree)
		T.eq(select(2, Plot.clear(p, "fences")), "not_found", "no fences to take")
		T.eq(select(2, Plot.clear(p, "everything")), "bad_payload")
		-- a Hatchery warming an egg stays where it is
		local bx, bz = spot(p, "hatchery")
		T.truthy(Plot.place(p, "hatchery", bx, bz, 0))
		local hq = p.plot.placed[#p.plot.placed]
		p.eggs = { { uid = hq.uid, a = 1, b = 2, sp = "mossbun", muts = {}, left = 3 } }
		local okC = Plot.clear(p, "pieces")
		T.eq(okC, false, "only the warm Hatchery: nothing to take")
		p.eggs = {}
		-- selling what waits: a share of the price each, the rest kept
		before = p.shells
		ok, data = Plot.sellHeld(p, "nest", 4)
		T.truthy(ok and data.sold == 4 and data.shells == 4 * math.floor(Buildings.byId.nest.shells * Tuning.Refund))
		T.eq(p.shells, before + data.shells)
		T.eq(Plot.held(p, "nest"), 95)
		ok, data = Plot.sellHeld(p, "dirtpath", 50)
		T.truthy(ok and data.sold == 2 and Plot.held(p, "dirtpath") == 0, "no more than there are")
		T.eq(select(2, Plot.sellHeld(p, "dirtpath", 1)), "not_found")
		T.eq(select(2, Plot.sellHeld(p, "nope", 1)), "bad_payload")
		-- a save's inventory cleaned: known placeable pieces, whole counts
		local inv = Plot.cleanInv({ patch = 3.7, tree = 2, nope = 1, nest = -1, torch = 1e9, [5] = 2 })
		T.truthy(inv.patch == 3 and inv.tree == nil and inv.nope == nil and inv.nest == nil and inv.torch == Plot.INV_MAX, "cleaned")
		local loaded = Schema.reconcile({ v = Schema.VERSION, inv = { patch = 2, tree = 1 } }, 0, 1)
		T.truthy(loaded.inv.patch == 2 and loaded.inv.tree == nil, "a save's inventory kept, cleaned")
	end)
end
