-- A well decorated town on an island of any tier, for the preview scenario "showcase=<tier>" and the game's thumbnails
-- (the request of 2026-11-19: "could you make an example of a well decorated town across all expansions?", then of
-- 2026-11-21: "could you make a better decorated island? with different sections dedicated to different decor types
-- and areas, ponds, etc, and better looking paths"). A planner, not a list, kept to the game's own rules
-- (Logic/Plot.fits for every piece, tile and fence; the piece, tile and fence limits, the huts' room, the places at
-- work and the Hatcheries, as Plot.place counts them).
--
-- The plan, from the Tree of Life out:
-- * The paths: a paved ring round the tree (flower beds at its corners, seats facing the tree, lamps); the avenue up
--   and down the island's middle, two light slabs wide between cobble edges, a hedge along each side broken where the
--   areas open onto it, lamps every ten studs; narrow flagstone walks across between the bands of areas.
-- * The areas, a band of them north and south of the ring and one each side of it, every area its own kind:
--     the village (two rows of huts of mixed kinds, every front toward the camera, one on a lane, a tree and flowers
--       between each two, a green at the lane's end), the market (the shops, the boosts and a Hatchery along a
--       cobble lane, carts and crates between, string lights), the farms (the fields fenced, hay and a barrow; the
--       wood camps among pines),
--     the lake (an oval pond with a path round it, a bridge across, lily pads, lotus, ducks, reeds and a boat by a
--       dock, willows and cherries round it, a gazebo and benches facing the water),
--     the flower garden (a hedge round it, gravel walks crossing at a fountain, each bed one kind of flower,
--       topiaries at the beds' corners, arches at the gates, a birdbath and beehives),
--     the zen garden (a bamboo fence, raked sand with a rock garden, a basin and lanterns on it, a koi pond, bonsai
--       and cherries), the fairy grove (a mossy path between giant mushrooms, a ring of them, lanterns, a wishing
--       well), the playground (a sandy yard of swings and slides, picnic tables round it) and the woods (trees on a
--       jittered grid, a clearing with a fire pit and log seats).
-- * The beach along the south shore once the open ground reaches it, and trees on the lawn left over round the rim.
-- The huts and workplaces go only in their areas (the island needn't be full to its room); every other area is
-- built with what the tier has unlocked, and an area the tier can't furnish becomes woods.
--   (env) -> plan(prof) -> stats
return function(env)
	local Plot, Buildings, Street = env.Plot, env.Buildings, env.Street
	local log = env.log or function(...) end

	return function(prof)
		local tier = prof.tier
		local placed = prof.plot.placed
		local L = {
			piece = Plot.limit(tier),
			tile = Plot.pathLimit(tier),
			fence = Plot.fenceLimit(tier),
			house = Plot.housingLimit(tier),
			work = Plot.workLimit(tier),
			hatch = Plot.hatcheryLimit(tier),
		}
		local used = { piece = 0, tile = 0, fence = 0, house = 0, work = 0, hatch = 0 }
		local tally: { [string]: number } = {}
		-- (the cells under paving and water: nothing but an area's own decor goes on them, so the paths stay clear)
		local paved: { [number]: boolean } = {}
		local yardOk = false
		local function cell(x: number, z: number): number
			return (x + 512) * 4096 + (z + 2048)
		end

		local function def(id: string)
			return Buildings.byId[id]
		end
		local function have(id: string?): boolean
			if id == nil then
				return false
			end
			local d = def(id)
			return d ~= nil and d.tier <= tier
		end
		-- the last of a list this tier has (lists go from the plainest to the finest)
		local function best(list: { string }): string?
			local out = nil
			for _, id in list do
				if have(id) then
					out = id
				end
			end
			return out
		end
		-- the first of a list this tier has (lists in order of preference)
		local function first(list: { string }): string?
			for _, id in list do
				if have(id) then
					return id
				end
			end
			return nil
		end
		local function avail(list: { string }): { string }
			local out = {}
			for _, id in list do
				if have(id) then
					table.insert(out, id)
				end
			end
			return out
		end

		-- Put a piece down if the game would let it: unlocked, within every limit, and Plot.fits.
		local function add(id: string?, x: number, z: number, rot: number?): boolean
			if id == nil or not have(id) then
				return false
			end
			local d = def(id)
			local r = rot or 0
			local g = Plot.group(id)
			if g == "tile" and used.tile >= L.tile then
				return false
			elseif g == "fence" and used.fence >= L.fence then
				return false
			elseif g == "piece" and used.piece >= L.piece then
				return false
			end
			if d.kind == "nest" and used.house + d.slots > L.house then
				return false
			end
			if (d.jobs or 0) > 0 and used.work + d.jobs > L.work then
				return false
			end
			if d.kind == "breed" and used.hatch >= L.hatch then
				return false
			end
			local rect = Plot.rect(id, x, z, r)
			if g == "piece" and not yardOk and d.sub ~= "float" and d.sub ~= "bridge" then
				for cz = rect.z0, rect.z1 - 1 do
					for cx = rect.x0, rect.x1 - 1 do
						if paved[cell(cx, cz)] then
							return false
						end
					end
				end
			end
			if not Plot.fits(tier, placed, id, x, z, r) then
				return false
			end
			if g == "tile" then
				for cz = rect.z0, rect.z1 - 1 do
					for cx = rect.x0, rect.x1 - 1 do
						paved[cell(cx, cz)] = true
					end
				end
			end
			table.insert(placed, { uid = prof.nextId, id = id, x = x, z = z, rot = r, lvl = 1 })
			prof.nextId += 1
			used[g] = (used[g] or 0) + 1
			if d.kind == "nest" then
				used.house += d.slots
			end
			used.work += d.jobs or 0
			if d.kind == "breed" then
				used.hatch += 1
			end
			tally[d.kind] = (tally[d.kind] or 0) + 1
			return true
		end
		-- Try a few spots near (x, z) (a stud each way) for a piece that is fussy about where it fits.
		local function near(id: string?, x: number, z: number, rot: number?): boolean
			for _, o in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
				if add(id, x + o[1], z + o[2], rot) then
					return true
				end
			end
			return false
		end

		local seed = tier * 7919 + 17
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n
		end
		local k = 0
		local function pick(list: { string }): string?
			if #list == 0 then
				return nil
			end
			k += 1
			return list[(k - 1) % #list + 1]
		end
		local function even(v: number): number
			return v - v % 2
		end

		-- The open ground: its rows' east and west ends (buildable cells), its north and south ends.
		local zN, zS = 99, -99
		local rowX0: { [number]: number } = {}
		local rowX1: { [number]: number } = {}
		for z = -260, 200 do
			for x = -60, 60 do
				if Street.buildable(tier, x, z) then
					rowX0[z] = math.min(rowX0[z] or 999, x)
					rowX1[z] = math.max(rowX1[z] or -999, x)
					zN = math.min(zN, z)
					zS = math.max(zS, z + 1)
				end
			end
		end

		------------------------------------------------------------------ what this tier has
		local SLAB = first({ "flagstone", "sandstone", "stonepath", "gravel", "dirtpath" })
		local EDGE = first({ "cobble", "stonepath", "gravel", "dirtpath" })
		local WALK = first({ "flagstone", "stonepath", "gravel", "dirtpath" })
		local GRAVEL = first({ "gravel", "dirtpath" })
		local MOSS = first({ "mossstone", "meadow", "gravel", "dirtpath" })
		local LAMP = best({ "torch", "lamppost", "streetlamp" })
		local SLAMP = best({ "torch", "gardenlights", "lamppost" })
		local HEDGE = first({ "hedgerow", "picket" })
		local WATER = first({ "lilypond", "lagoon", "stream" })
		local BRIDGE = best({ "plankbridge", "ropebridge", "stonebridge", "moonbridge" })
		local FLOATS = avail({ "lilypads", "lotus", "duckfloat", "reeds", "waterlanterns", "lilypads", "lotus" })
		local SMALLTREES = avail({ "birch", "pine" })
		local BIGTREES = avail({ "oak", "cherry", "maple", "bigoak", "starfruit", "redwood" })
		local LAKETREES = avail({ "willow", "cherry", "birch", "oak" })
		local FLOWERS = avail({ "flowers", "tulips", "lavender", "rosebush", "sunflowers" })
		local SEATS = avail({ "parkbench", "bench", "stonebench" })
		local SMALLS = avail({ "birdbath", "gnome", "beehive", "sundial", "fern", "mushrooms" })

		------------------------------------------------------------------ path helpers
		local function tile(id: string?, x: number, z: number): boolean
			return add(id, even(x), even(z), 0)
		end
		local function tileRow(id: string?, z: number, x0: number, x1: number)
			for x = even(x0), x1, 2 do
				add(id, x, even(z), 0)
			end
		end
		local function tileCol(id: string?, x: number, z0: number, z1: number)
			for z = even(z0), z1, 2 do
				add(id, even(x), z, 0)
			end
		end
		local function tileRect(id: string?, x0: number, z0: number, x1: number, z1: number)
			for z = even(z0), z1 - 2, 2 do
				for x = even(x0), x1 - 2, 2 do
					add(id, x, z, 0)
				end
			end
		end
		-- a fence round a rect on the even grid lines, a gap of `gap` studs in the middle of each side named in `gates`
		local function fenceRun(id: string?, x0: number, z0: number, x1: number, z1: number, gates: { [string]: boolean }?, gap: number?)
			x0, z0, x1, z1 = even(x0), even(z0), x1 + x1 % 2, z1 + z1 % 2
			local g = gap or 2
			local mx, mz = even((x0 + x1) // 2), even((z0 + z1) // 2)
			local function open(side: string, v: number, m: number): boolean
				return gates ~= nil and gates[side] == true and v >= m - g // 2 and v < m + g // 2
			end
			for x = x0, x1 - 2, 2 do
				if not open("n", x, mx) then
					add(id, x, z0, 0)
				end
				if not open("s", x, mx) then
					add(id, x, z1, 0)
				end
			end
			for z = z0, z1 - 2, 2 do
				if not open("w", z, mz) then
					add(id, x0, z, 90)
				end
				if not open("e", z, mz) then
					add(id, x1, z, 90)
				end
			end
		end

		------------------------------------------------------------------ the tree's ring
		local tr = { x0 = -4, z0 = 2, x1 = 4, z1 = 10 }
		for _, q in placed do
			if def(q.id) and def(q.id).kind == "tree" then
				tr = Plot.rect(q.id, q.x, q.z, q.rot)
			end
		end
		local rx0, rx1 = even(tr.x0 - 4), tr.x1 + 2 + (tr.x1 % 2)
		local rz0, rz1 = even(tr.z0 - 4), tr.z1 + 2 + (tr.z1 % 2)
		-- (the ring two slabs wide round the tree, its outer row the cobble edge)
		tileRect(SLAB, rx0 + 2, rz0 + 2, rx1, rz0 + 4)
		tileRect(SLAB, rx0 + 2, rz1 - 4, rx1, rz1 - 2)
		tileRect(SLAB, rx0 + 2, rz0 + 4, rx0 + 4, rz1 - 4)
		tileRect(SLAB, rx1 - 4, rz0 + 4, rx1 - 2, rz1 - 4)
		tileRow(EDGE, rz0, rx0, rx1)
		tileRow(EDGE, rz1 - 2, rx0, rx1)
		tileCol(EDGE, rx0, rz0, rz1 - 2)
		tileCol(EDGE, rx1, rz0, rz1 - 2)
		local plazaX0, plazaX1, plazaZ0, plazaZ1 = rx0, rx1 + 2, rz0, rz1

		------------------------------------------------------------------ the avenue
		-- two slabs wide (x -2 and 0) between cobble edges (x -4 and 2), up from the ring and down from it
		local function avenue(z0: number, z1: number)
			tileCol(SLAB, -2, z0, z1)
			tileCol(SLAB, 0, z0, z1)
			tileCol(EDGE, -4, z0, z1)
			tileCol(EDGE, 2, z0, z1)
		end
		avenue(zN, rz0 - 2)
		avenue(rz1, zS)

		------------------------------------------------------------------ the bands of areas
		type Area = { x0: number, x1: number, z0: number, z1: number, name: string, kind: string? }
		local areas: { Area } = {}
		local function area(x0: number, x1: number, z0: number, z1: number, name: string)
			local mid = (z0 + z1) // 2
			if rowX0[mid] == nil then
				return
			end
			x0, x1 = math.max(x0, rowX0[mid] + 1), math.min(x1, rowX1[mid])
			if x1 - x0 >= 10 and z1 - z0 >= 10 then
				table.insert(areas, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, name = name })
			end
		end
		-- the walks across between the bands, every BAND studs north and south of the ring
		local BAND = 22
		local walks: { number } = {}
		-- the core: either side of the ring
		area(-60, plazaX0 - 2, plazaZ0, plazaZ1, "core west")
		area(plazaX1 + 2, 60, plazaZ0, plazaZ1, "core east")
		local z = plazaZ0 - 2
		local band = 0
		while z - 10 > zN do
			band += 1
			table.insert(walks, z)
			local z0 = math.max(zN, z - BAND)
			area(-60, -6, z0, z, "north " .. band .. " west")
			area(5, 60, z0, z, "north " .. band .. " east")
			z = z0 - 2
		end
		z = plazaZ1 + 2
		band = 0
		while z + 10 < zS do
			band += 1
			table.insert(walks, z - 2)
			local z1 = math.min(zS, z + BAND)
			area(-60, -6, z, z1, "south " .. band .. " west")
			area(5, 60, z, z1, "south " .. band .. " east")
			z = z1 + 2
		end
		for _, wz in walks do
			tileRow(WALK, wz, -44, -6)
			tileRow(WALK, wz, 4, 44)
		end

		------------------------------------------------------------------ the huts and the workplaces
		local huts = {}
		for _, d in Buildings.list do
			if d.kind == "nest" and d.tier <= tier then
				table.insert(huts, d)
			end
		end
		table.sort(huts, function(a, b)
			return a.slots > b.slots
		end)
		local works = { farm = {}, wood = {}, shop = {} }
		for _, d in Buildings.list do
			if d.kind == "work" and d.tier <= tier and works[d.act] then
				table.insert(works[d.act], d)
			end
		end
		for _, l in works do
			table.sort(l, function(a, b)
				return a.jobs > b.jobs
			end)
		end
		local boosts = {}
		for _, d in Buildings.list do
			if d.kind == "gen" and d.tier <= tier then
				table.insert(boosts, d.id)
			end
		end

		-- A row of buildings with their fronts on z = zFront: facing south (rot 0, the row north of the line) or north
		-- (rot 180, the row south of it). `nextId` gives the next one (nil: the row ends); `between(x0, x1, zBack,
		-- zFront)` fills each gap. Returns how many went down.
		local function row(a: Area, zFront: number, south: boolean, nextId: () -> string?, gap: number, between: ((number, number, number, number) -> ())?): number
			local x = a.x0 + 1
			local n, misses, lastEnd = 0, 0, nil
			while x < a.x1 - 2 and misses < 10 do
				local id = nextId()
				if id == nil then
					break
				end
				local d = def(id)
				local zTop = if south then zFront - d.d else zFront
				local done = false
				for dx = 0, 2 do
					if add(id, x + dx, zTop, if south then 0 else 180) then
						if lastEnd and between and x + dx - lastEnd >= 2 then
							between(lastEnd, x + dx, zTop, zTop + d.d)
						end
						lastEnd = x + dx + d.w
						x = lastEnd + gap
						n += 1
						done = true
						misses = 0
						break
					end
				end
				if not done then
					x += 1
					misses += 1
				end
			end
			return n
		end

		------------------------------------------------------------------ the areas
		local B: { [string]: (Area) -> boolean } = {}

		-- the village: two rows of huts facing a lane, a tree and flowers between each two, a green at the lane's end
		local hutTurn = 0
		B.village = function(a: Area): boolean
			if #huts == 0 then
				return false
			end
			local top = math.min(3, #huts)
			local function nextHut(): string?
				for _ = 1, top do
					hutTurn += 1
					local d = huts[(hutTurn - 1) % top + 1]
					if used.house + d.slots <= L.house then
						return d.id
					end
				end
				for _, d in huts do
					if used.house + d.slots <= L.house then
						return d.id
					end
				end
				return nil
			end
			local zl = even((a.z0 + a.z1) // 2)
			tileRow(GRAVEL, zl, a.x0 + 2, a.x1 - 8)
			local function garden(x0: number, x1: number, zb: number, zf: number)
				add(pick(SMALLTREES), x0, zb, 0)
				add(pick(FLOWERS), x0, zf - 2, 0)
			end
			-- (both rows face south, toward the camera: the first onto the lane, the second onto the walk at the area's edge)
			local n = row(a, zl - 1, true, nextHut, 2, garden) + row(a, a.z1 - 1, true, nextHut, 2, garden)
			-- the green at the lane's east end: a big tree, a bench, a lamp, flowers
			local gx = a.x1 - 7
			near(pick(BIGTREES), gx, zl - 2, 0)
			near(pick(SEATS), gx, zl + 2, 0)
			near(SLAMP, gx - 1, zl, 0)
			near(pick(FLOWERS), gx + 3, zl + 2, 0)
			for x = a.x0 + 3, a.x1 - 10, 6 do
				add(SLAMP, x, zl + 2, 0)
			end
			return n > 0
		end

		-- the market: the shops, the boosts and a Hatchery along a cobble lane, carts and crates between, string lights
		local actTurn = 0
		local function nextWork(acts: { string }): () -> string?
			local queue: { string } = {}
			for i = #boosts, 1, -1 do
				if (tally["gen_" .. boosts[i]] or 0) == 0 then
					table.insert(queue, boosts[i])
					tally["gen_" .. boosts[i]] = 1
					if #queue >= 2 then
						break
					end
				end
			end
			if used.hatch < L.hatch then
				table.insert(queue, 1, "hatchery")
			end
			return function(): string?
				if #queue > 0 then
					return table.remove(queue, 1)
				end
				for _ = 1, #acts do
					actTurn += 1
					local act = acts[(actTurn - 1) % #acts + 1]
					for _, d in works[act] do
						if used.work + d.jobs <= L.work then
							return d.id
						end
					end
				end
				return nil
			end
		end
		B.market = function(a: Area): boolean
			local zl = even((a.z0 + a.z1) // 2)
			tileRow(EDGE, zl, a.x0 + 1, a.x1 - 2)
			local STUFF = avail({ "cart", "barrels", "crates", "haybale", "wheelbarrow" })
			local function stalls(x0: number, x1: number, zb: number, zf: number)
				add(pick(STUFF), x0, if zf <= zl then zf - 2 else zb + 1, 0)
			end
			local nw = nextWork({ "shop", "shop", "farm" })
			local n = row(a, zl - 1, true, nw, 2, stalls) + row(a, a.z1 - 1, true, nw, 2, stalls)
			for x = a.x0 + 2, a.x1 - 4, 8 do
				add(best({ "stringlights" }), x, zl - 1, 0)
				add(SLAMP, x + 4, zl + 2, 0)
			end
			return n > 0
		end

		-- the farms: the fields fenced round, open at the front; the wood camps among pines at the back
		local FARMFENCE = first({ "splitrail", "wattle", "picket" })
		B.farm = function(a: Area): boolean
			local zl = even((a.z0 + a.z1) // 2)
			tileRow(first({ "dirtpath", "gravel" }), zl, a.x0 + 1, a.x1 - 2)
			local fields = {}
			local nf = nextWork({ "farm" })
			local function note(x0: number, x1: number, zb: number, zf: number)
				add(best({ "haybale", "wheelbarrow" }), x0, zf - 2, 0)
			end
			local x = a.x0 + 2
			local n = 0
			-- (the fields north of the lane, each fenced)
			while x < a.x1 - 4 do
				local id = nf()
				if id == nil then
					break
				end
				local d = def(id)
				local zTop = zl - 2 - d.d
				if add(id, x, zTop, 0) then
					table.insert(fields, { x = x, z = zTop, w = d.w, d = d.d })
					x += d.w + 3
					n += 1
				else
					x += 1
				end
			end
			for _, f in fields do
				fenceRun(FARMFENCE, f.x - 1, f.z - 1, f.x + f.w + 1, f.z + f.d + 1, { s = true })
			end
			-- (the wood camps south of the lane among pines)
			local nwd = nextWork({ "wood" })
			local function pines(x0: number, x1: number, zb: number, zf: number)
				add(pick(SMALLTREES), x0, zb + 1, 0)
			end
			n += row(a, a.z1 - 1, true, nwd, 3, pines)
			for xx = a.x0 + 1, a.x1 - 3, 3 do
				add(first({ "pine", "birch" }), xx, zl + 3, 0)
			end
			return n > 0
		end

		-- the lake: an oval pond, a path round it, a bridge across, floats, a dock and a boat; willows, a gazebo, benches
		B.lake = function(a: Area): boolean
			if WATER == nil then
				return false
			end
			local cx, cz = (a.x0 + a.x1) / 2, (a.z0 + a.z1) / 2
			local rx, rz = (a.x1 - a.x0) / 2 - 5, (a.z1 - a.z0) / 2 - 4
			if rx < 4 or rz < 3 then
				return false
			end
			local function inside(x: number, z: number, s: number): boolean
				local u, v = (x + 1 - cx) / (rx * s), (z + 1 - cz) / (rz * s)
				return u * u + v * v <= 1
			end
			local water = {}
			for zz = even(a.z0), a.z1, 2 do
				for xx = even(a.x0), a.x1, 2 do
					if inside(xx, zz, 1) and add(WATER, xx, zz, 0) then
						table.insert(water, { x = xx, z = zz })
					end
				end
			end
			if #water < 6 then
				return #water > 0
			end
			-- the path round it: the ring of tiles just outside the water
			for zz = even(a.z0), a.z1, 2 do
				for xx = even(a.x0), a.x1, 2 do
					if not inside(xx, zz, 1) and inside(xx, zz, 1 + 2.6 / math.min(rx, rz)) then
						add(GRAVEL, xx, zz, 0)
					end
				end
			end
			-- the bridge across the middle, north to south
			local bx = even(math.floor(cx)) - 1
			local bridged = false
			for dz = -3, 3 do
				if add(BRIDGE, bx, math.floor(cz) - 3 + dz, 0) then
					bridged = true
					break
				end
			end
			-- floats on the water away from the bridge, a dock and a boat on the east shore
			table.sort(water, function(p, q)
				return math.abs(p.x - cx) > math.abs(q.x - cx)
			end)
			local nfl = 0
			for _, w in water do
				if nfl >= 9 then
					break
				end
				if math.abs(w.x + 1 - cx) > 3 and (w.x + w.z) % 4 == 0 then
					if add(pick(FLOATS), w.x, w.z, 0) then
						nfl += 1
					end
				end
			end
			for _, w in water do
				if w.x + 1 > cx + rx - 4 and add("rowboat", w.x, w.z - 1, 0) then
					break
				end
			end
			near("dock", even(math.floor(cx + rx)) - 2, even(math.floor(cz)) - 1, 0)
			-- round it: willows and cherries at the corners, benches facing the water, a gazebo, lamps, flowers
			local ox, oz = rx + 3, rz + 2.5
			for i = 0, 7 do
				local ang = i / 8 * math.pi * 2 + 0.3
				local tx, tz = math.floor(cx + math.cos(ang) * ox) - 2, math.floor(cz + math.sin(ang) * oz) - 2
				if i % 2 == 0 then
					near(pick(LAKETREES), tx, tz, 0)
				elseif i == 1 then
					near(first({ "gazebo", "pavilion", "bandstand" }), tx - 1, tz - 1, 0)
				else
					near(pick(SEATS), tx, tz, 0)
				end
			end
			for i = 0, 3 do
				local ang = i / 4 * math.pi * 2 + 1.1
				near(SLAMP, math.floor(cx + math.cos(ang) * (rx + 1.5)), math.floor(cz + math.sin(ang) * (rz + 1.5)), 0)
				near(pick(FLOWERS), math.floor(cx + math.cos(ang + 0.4) * (rx + 2)), math.floor(cz + math.sin(ang + 0.4) * (rz + 2)), 0)
			end
			return bridged or nfl > 0
		end

		-- the flower garden: a hedge round it, gravel walks crossing at a fountain, a kind of flower to each bed
		B.flowers = function(a: Area): boolean
			if #FLOWERS < 2 then
				return false
			end
			local x0, x1, z0, z1 = even(a.x0 + 1), a.x1 - 2, even(a.z0 + 1), a.z1 - 1
			x1, z1 = x1 - x1 % 2, z1 - z1 % 2
			local mx, mz = even((x0 + x1) // 2), even((z0 + z1) // 2)
			fenceRun(HEDGE, x0, z0, x1, z1, { n = true, s = true, w = true, e = true }, 2)
			tileCol(GRAVEL, mx, z0, z1 - 2)
			tileRow(GRAVEL, mz, x0, x1 - 2)
			-- the middle: a fountain on a square of slabs
			local fount = first({ "fountain", "crystalfountain", "smallfountain", "birdbath" })
			local fd = if fount then def(fount) else nil
			if fd then
				local hw = math.max(2, even(fd.w + 3) // 2)
				for zz = mz - hw, mz + hw, 2 do
					for xx = mx - hw, mx + hw, 2 do
						add(SLAB, xx, zz, 0)
					end
				end
				yardOk = true
				add(fount, mx + 1 - fd.w // 2, mz + 1 - fd.d // 2, 0)
				yardOk = false
			end
			-- the beds: a quarter each, filled with one flower in rows a stud apart
			local beds = {
				{ x0 = x0 + 1, x1 = mx - 1, z0 = z0 + 1, z1 = mz - 1 },
				{ x0 = mx + 2, x1 = x1 - 1, z0 = z0 + 1, z1 = mz - 1 },
				{ x0 = x0 + 1, x1 = mx - 1, z0 = mz + 2, z1 = z1 - 1 },
				{ x0 = mx + 2, x1 = x1 - 1, z0 = mz + 2, z1 = z1 - 1 },
			}
			local kinds = { FLOWERS[1], FLOWERS[math.min(2, #FLOWERS)], FLOWERS[math.min(3, #FLOWERS)], FLOWERS[math.min(4, #FLOWERS)] }
			local n = 0
			for i, b in beds do
				local id = kinds[i]
				local d = def(id)
				for zz = b.z0, b.z1 - d.d, d.d + 1 do
					for xx = b.x0, b.x1 - d.w, d.w + 1 do
						if add(id, xx, zz, 0) then
							n += 1
						end
					end
				end
				-- a topiary at the bed's corner by the fountain, a small thing at its outer corner
				near(first({ "topiary", "bush" }), if i % 2 == 1 then b.x1 - 2 else b.x0, if i <= 2 then b.z1 - 2 else b.z0, 0)
				near(pick(SMALLS), if i % 2 == 1 then b.x0 else b.x1 - 1, if i <= 2 then b.z0 else b.z1 - 1, 0)
			end
			-- arches at the gates, a bench by each
			near(first({ "flowerarch", "trellis" }), mx - 1, z0 - 2, 0)
			near(first({ "flowerarch", "trellis" }), mx - 1, z1 + 1, 0)
			near(pick(SEATS), x0 + 2, z1 + 1, 0)
			near(pick(SEATS), x1 - 5, z0 - 2, 0)
			return n > 4
		end

		-- the zen garden: a bamboo fence, raked sand with stones and lanterns on it, a koi pond, bonsai, cherries
		B.zen = function(a: Area): boolean
			local raked = first({ "raked", "sandtrail", "gravel" })
			local ZEN = avail({ "rockgarden", "zenbasin", "stonelantern", "bonsai", "windchime", "stonelantern", "lanterntower", "bambooscreen" })
			if #ZEN < 3 then
				return false
			end
			local x0, x1, z0, z1 = even(a.x0 + 1), a.x1 - 2, even(a.z0 + 1), a.z1 - 1
			x1, z1 = x1 - x1 % 2, z1 - z1 % 2
			fenceRun(first({ "bamboofence", "hedgerow" }), x0, z0, x1, z1, { s = true, w = true }, 2)
			-- the raked yard in the west half, its stones and lanterns on it
			local yx1 = even((x0 + x1) // 2 + 2)
			tileRect(raked, x0 + 2, z0 + 2, yx1, z1 - 2)
			yardOk = true
			local n = 0
			local i = 0
			for zz = z0 + 3, z1 - 4, 4 do
				for x = x0 + 3 + (if (zz // 4) % 2 == 0 then 0 else 2), yx1 - 3, 5 do
					i += 1
					if add(ZEN[(i - 1) % #ZEN + 1], x, zz, 0) then
						n += 1
					end
				end
			end
			yardOk = false
			-- the east half: a koi pond, cherries, bonsai, paper lanterns
			near(first({ "koipond", "smallfountain" }), yx1 + 3, z0 + 3, 0)
			for zz2 = z0 + 2, z1 - 4, 5 do
				near(first({ "cherry", "maple" }), x1 - 4, zz2, 0)
			end
			near(first({ "paperlanterns", "stringlights" }), yx1 + 2, z1 - 3, 0)
			near(first({ "bonsai", "fern" }), yx1 + 7, z0 + 4, 0)
			near(first({ "bonsai", "fern" }), yx1 + 3, z1 - 5, 0)
			return n >= 2
		end

		-- the fairy grove: a mossy path winding between giant mushrooms, a ring of them, lanterns, a wishing well
		B.fairy = function(a: Area): boolean
			local FAIRY = avail({ "giantshroom", "mushroomring", "fairylantern", "wishingwell", "moonstone", "crystalarch", "glowshroom", "crystals" })
			if #FAIRY < 3 then
				return false
			end
			-- the path: a slow S across the grove, a tile at a time
			local cz = (a.z0 + a.z1) / 2
			for xx = even(a.x0 + 1), a.x1 - 2, 2 do
				local t = (xx - a.x0) / math.max(1, a.x1 - a.x0)
				tile(MOSS, xx, math.floor(cz + math.sin(t * math.pi * 2) * (a.z1 - a.z0) * 0.22))
			end
			local n = 0
			for zz = a.z0 + 1, a.z1 - 3, 4 do
				for xx = a.x0 + 1, a.x1 - 3, 4 do
					local id = FAIRY[(xx // 4 + zz // 4) % #FAIRY + 1]
					if add(id, xx + rnd(2), zz + rnd(2), 0) then
						n += 1
					elseif add(first({ "birch", "glowshroom" }), xx, zz, 0) then
						n += 1
					end
				end
			end
			return n >= 3
		end

		-- the playground: a sandy yard of swings and slides, picnic tables and benches round it
		B.play = function(a: Area): boolean
			local PLAY = avail({ "swing", "slide", "seesaw", "sandbox", "carousel", "trampoline", "climbframe" })
			if #PLAY < 3 then
				return false
			end
			local x0, x1, z0, z1 = even(a.x0 + 2), a.x1 - 3, even(a.z0 + 2), a.z1 - 3
			x1, z1 = x1 - x1 % 2, z1 - z1 % 2
			local sand = first({ "sandtrail", "gravel" })
			tileRect(sand, x0, z0, x1, z1)
			yardOk = true
			local x, zz, n = x0 + 1, z0 + 1, 0
			for _, id in PLAY do
				local d = def(id)
				if x + d.w > x1 - 1 then
					x = x0 + 1
					zz += 5
				end
				if zz + d.d > z1 - 1 then
					break
				end
				if add(id, x, zz, 0) then
					n += 1
				end
				x += d.w + 2
			end
			yardOk = false
			for xx = x0, x1 - 4, 6 do
				near(first({ "picnic", "bench", "parkbench" }), xx, z1 + 1, 0)
				near(pick(BIGTREES), xx + 1, z0 - 4, 0)
			end
			return n >= 2
		end

		-- the woods: trees on a jittered grid, a clearing with a fire pit and log seats, ferns and rocks
		B.woods = function(a: Area): boolean
			local cx, cz = even((a.x0 + a.x1) // 2), even((a.z0 + a.z1) // 2)
			near(first({ "firepit", "logseats" }), cx, cz, 0)
			near(first({ "logseats", "stonebench" }), cx - 3, cz, 0)
			near(first({ "logseats", "stonebench" }), cx + 3, cz, 0)
			local TREES = avail({ "pine", "oak", "birch", "pine", "maple", "bigoak" })
			local UNDER = avail({ "fern", "mushrooms", "mossrock", "boulder", "tallgrass", "bush" })
			local n = 0
			for zz = a.z0 + 1, a.z1 - 3, 4 do
				for xx = a.x0 + 1, a.x1 - 3, 4 do
					if math.abs(xx - cx) + math.abs(zz - cz) > 6 then
						if add(pick(TREES), xx + rnd(2), zz + rnd(2), 0) then
							n += 1
						else
							add(pick(UNDER), xx + 1, zz + 1, 0)
						end
					end
				end
			end
			return n > 0
		end

		------------------------------------------------------------------ which area goes where
		-- the core first (the flower garden west of the ring, the market east of it), then the bands outward, each
		-- band's west and east areas from a list, so every kind of area turns up once before any comes again
		table.sort(areas, function(p, q)
			local dp = math.abs((p.z0 + p.z1) / 2 - (tr.z0 + tr.z1) / 2)
			local dq = math.abs((q.z0 + q.z1) / 2 - (tr.z0 + tr.z1) / 2)
			if dp ~= dq then
				return dp < dq
			end
			return p.x0 < q.x0
		end)
		local ORDER = { "flowers", "market", "lake", "village", "zen", "farm", "fairy", "play", "woods", "village", "lake", "market" }
		local nextKind = 0
		for _, a in areas do
			nextKind += 1
			local want = ORDER[(nextKind - 1) % #ORDER + 1]
			local built = B[want](a)
			if not built then
				-- (this tier can't furnish that kind: woods instead)
				want = "woods"
				B.woods(a)
			end
			a.kind = want
		end

		------------------------------------------------------------------ along the paths
		-- the ring: flower beds at its corners, seats facing the tree, lamps, a signpost
		add(LAMP, rx0 - 1, rz0 - 1, 0)
		add(LAMP, rx1 + 2, rz0 - 1, 0)
		add(LAMP, rx0 - 1, rz1, 0)
		add(LAMP, rx1 + 2, rz1, 0)
		near(pick(FLOWERS), rx0 - 3, rz0 + 2, 0)
		near(pick(FLOWERS), rx1 + 3, rz0 + 2, 0)
		near(pick(FLOWERS), rx0 - 3, rz1 - 4, 0)
		near(pick(FLOWERS), rx1 + 3, rz1 - 4, 0)
		near(best({ "signpost", "noticeboard" }), 4, rz0 - 3, 0)
		-- the avenue: a hedge along each side (broken every 8 studs where the areas open onto it), a lamp every 10
		for zz = even(zN), zS - 2, 2 do
			local open = (zz // 2) % 4 == 0
			local inRing = zz >= rz0 - 2 and zz < rz1
			if not open and not inRing then
				add(HEDGE, -4, zz, 90)
				add(HEDGE, 4, zz, 90)
			end
		end
		local n = 0
		for zz = rz0 - 6, zN + 1, -10 do
			n += 1
			add(LAMP, if n % 2 == 0 then -6 else 5, zz, 0)
		end
		for zz = rz1 + 4, zS - 2, 10 do
			n += 1
			add(LAMP, if n % 2 == 0 then -6 else 5, zz, 0)
		end
		-- the walks: a small lamp every 12 studs on their north side
		for _, wz in walks do
			for x = -40, 40, 12 do
				if math.abs(x) > 8 then
					add(SLAMP, x, wz - 1, 0)
				end
			end
		end

		------------------------------------------------------------------ the beach and the rim
		local BEACH = avail({ "umbrella", "deckchair", "sandcastle", "surfboards", "coconuts", "shellpile", "lifeguard" })
		local bx = 0
		for _, side in (if Street.layer(tier, 0, zS + 2) ~= Street.GRASS then { -1, 1 } else {}) :: { number } do
			for x = 8, 34, 3 do
				local id = BEACH[(bx % math.max(1, #BEACH)) + 1]
				for zz = zS - 2, zS - 4, -1 do
					if add(id, side * x - (if side < 0 then 2 else 0), zz, 0) then
						bx += 1
						break
					end
				end
			end
		end
		-- trees and bushes on the lawn left round the rim (outside every area), until the island holds most of its pieces
		-- (the formal areas keep their own layout; the village, market, farms, lake and woods take more planting)
		local LOOSE = { village = true, market = true, farm = true, lake = true, woods = true }
		local function claimed(x: number, zz: number): boolean
			for _, a in areas do
				if x >= a.x0 - 1 and x < a.x1 + 1 and zz >= a.z0 - 1 and zz < a.z1 + 1 then
					return not LOOSE[a.kind or ""]
				end
			end
			return false
		end
		local ROCKS = avail({ "boulder", "rockpile", "mossrock" })
		local PLANTS = avail({ "fern", "tallgrass", "bush", "berrybush" })
		local goal = math.floor(L.piece * 0.85)
		for zz = zS - 3, zN + 1, -3 do
			for xx = -44, 44, 3 do
				if used.piece >= goal then
					break
				end
				local x, z2 = xx + rnd(2), zz + rnd(2)
				if not claimed(x, z2) then
					local kind = rnd(5)
					if kind == 0 then
						add(pick(BIGTREES), x, z2, 0)
					elseif kind == 1 then
						if add(pick(PLANTS), x, z2, 0) then
							add(pick(ROCKS), x + 2, z2 + 1, 0)
						end
					elseif kind == 2 then
						add(pick(SMALLTREES), x, z2, 0)
					else
						-- (flowers and small things, a stud from the paths and the buildings)
						if not add(pick(FLOWERS), x, z2, 0) then
							add(pick(SMALLS), x, z2, 0)
						end
					end
				end
			end
		end

		local kindsUsed: { string } = {}
		for _, a in areas do
			table.insert(kindsUsed, a.name .. ": " .. tostring(a.kind))
		end
		log(
			"showcase: tier %d, %d areas (%s); pieces %d of %d, tiles %d of %d, fences %d of %d; room %d of %d, places at work %d of %d, Hatcheries %d of %d",
			tier,
			#areas,
			table.concat(kindsUsed, ", "),
			used.piece,
			L.piece,
			used.tile,
			L.tile,
			used.fence,
			L.fence,
			used.house,
			L.house,
			used.work,
			L.work,
			used.hatch,
			L.hatch
		)
		return { used = used, limits = L, zN = zN, zS = zS }
	end
end
