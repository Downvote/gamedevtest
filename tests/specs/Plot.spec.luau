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
	T.it("fits: on the island's buildable grass, on the grid, off the plaza and other pieces", function()
		T.truthy(Plot.fits(1, {}, "flowers", 8, 4, 0), "the east lawn")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 18, 5, 0)), "outside", "past the east coast")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 0, 22, 0)), "outside", "on the beach")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8.5, 4, 0)), "outside", "whole studs")
		T.eq(select(2, Plot.fits(1, {}, "flowers", 8, 4, 45)), "outside", "quarter turns")
		T.eq(select(2, Plot.fits(1, {}, "dirtpath", 9, 4, 0)), "outside", "a tile on the even studs")
		T.truthy(Plot.fits(1, {}, "dirtpath", 8, 4, 0))
		T.eq(select(2, Plot.fits(1, {}, "torch", 0, 4, 0)), "blocked", "on the plaza")
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
	T.it("fences: drawn along the even grid lines, apart from the pieces; not through a building, along one is fine", function()
		local p = fresh()
		local ok, data = Plot.fence(p, "picket", { { 8, 4, 0 }, { 10, 4, 0 }, { 12, 4, 90 } })
		T.truthy(ok)
		T.eq(data.placed, 3)
		T.eq(p.wood, 1e6 - 3 * 8, "paid in wood")
		T.eq(select(1, Plot.used(p, "picket")), 3)
		T.eq(select(2, Plot.used(p, "picket")), Plot.fenceLimit(1), "its own limit")
		T.eq(select(1, Plot.used(p, "flowers")), 0, "the pieces don't count fences")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 4, 0)), "overlap", "one fence an edge")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 9, 4, 0)), "outside", "the even grid")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 4, 180)), "outside", "east or south")
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", -2, 4, 0)), "blocked", "not across the plaza")
		-- a building where the fence runs through refused; one beside it fine; a fence through a building refused
		T.eq(select(2, Plot.fits(1, p.plot.placed, "patch", 8, 3, 0)), "overlap", "a fence through it")
		T.truthy(Plot.fits(1, p.plot.placed, "patch", 8, 5, 0), "a fence along its side")
		T.truthy(Plot.place(p, "patch", 8, 5, 0))
		T.eq(select(2, Plot.fits(1, p.plot.placed, "picket", 8, 6, 0)), "overlap", "a fence through a building")
		T.truthy(Plot.fits(1, p.plot.placed, "picket", 8, 8, 0), "along its far side")
		-- another fence over one: swapped, half the old one's price back
		local before = p.wood
		ok, data = Plot.fence(p, "splitrail", { { 8, 4, 0 } })
		T.truthy(ok)
		T.eq(data.swapped, 1)
		T.eq(p.wood, before + math.floor(8 * Tuning.Refund) - 10)
		-- taken down: half back each
		before = p.wood
		ok, data = Plot.unfence(p, { { 8, 4, 0 }, { 12, 4, 90 } })
		T.truthy(ok)
		T.eq(data.removed, 2)
		T.eq(p.wood, before + math.floor(10 * Tuning.Refund) + math.floor(8 * Tuning.Refund))
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
	T.it("a paved yard: decor, plants and fun pieces stand on path tiles; huts, workplaces and water pieces don't", function()
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
		T.truthy(not Plot.onPaths("nest") and not Plot.onPaths("patch") and not Plot.onPaths("lilypads") and not Plot.onPaths("tree"))
		T.truthy(Plot.place(p, "snowman", 9, -7, 0), "a snowman on the snow")
		T.truthy(Plot.place(p, "pine", 11, -5, 0), "a tree in it")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "nest", 8, -8, 0)), "overlap", "no hut on the paving")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "patch", 8, -8, 0)), "overlap", "no farm on it")
		T.eq(select(2, Plot.fits(3, p.plot.placed, "snowman", 9, -7, 0)), "overlap", "two pieces still never share a spot")
		-- paving round decor that stands already; never under a hut
		local q = fresh()
		q.tier = 3
		T.truthy(Plot.place(q, "gnome", 9, -7, 0))
		T.truthy(Plot.place(q, "nest", 13, -8, 0))
		local ok, data = Plot.paint(q, "sandtrail", { { 8, -8 }, { 12, -8 } })
		T.truthy(ok)
		T.eq(data.placed, 1, "under the gnome")
		T.eq(data.skipped, 1, "not under the hut")
		-- taking the paving up leaves the decor where it stands
		T.truthy(Plot.unpaint(q, { { 8, -8 } }, "path"))
		local gnome = false
		for _, x in q.plot.placed do
			gnome = gnome or x.id == "gnome"
		end
		T.truthy(gnome)
	end)
	T.it("paths over paths: another look swapped where it lies (half the old price back), the same look passed over", function()
		local p = fresh()
		p.tier = 2
		T.truthy(Plot.paint(p, "dirtpath", { { 8, 4 }, { 10, 4 } }))
		local before = p.wood
		local ok, data = Plot.paint(p, "stonepath", { { 8, 4 }, { 10, 4 }, { 12, 4 } })
		T.truthy(ok)
		T.eq(data.swapped, 2)
		T.eq(data.placed, 1)
		T.eq(p.wood, before - 3 * 15 + 2 * math.floor(5 * Tuning.Refund))
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
