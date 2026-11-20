-- A well decorated town on an island of any tier, for the preview scenario "showcase=<tier>" (the request of
-- 2026-11-19: "could you make an example of a well decorated town across all expansions?"). A planner, not a list:
-- the same streets and districts on every island, each filled with what that tier has unlocked and kept to the game's
-- own rules (Logic/Plot.fits for every piece, tile and fence; the piece, tile and fence limits, the huts' room, the
-- places at work and the Hatcheries, as Plot.place counts them).
--
-- The plan, from the plaza out north and south (the open ground grows round the plaza: since 2026-11-20 every tier's
-- is a ring round the island's heart, the rocks past it):
-- * The Tree of Life framed by a path round it and the plaza; a main avenue north from it up the island's middle,
--   cross streets every 20 studs east to west, each a paving of its tier (dirt, cobble, brick, marble).
-- * The blocks between them, nearest the plaza first, are districts: huts (in rows facing the street, a front garden
--   and a tree between each two, a lane between two rows), work (farms fenced in, the wood camps among pines, the
--   shops by the avenue, the boost buildings and the Hatcheries among them), parks (a pond with its floats and a
--   bridge, a path round it, trees, benches and lamps, or a fountain square with flower beds) and themed yards (a
--   paving and a fence in the theme's style round its decor, its plants outside).
-- * Lamps along the avenue and the streets, a few benches, bins and signposts.
-- Functional buildings first (the huts to the island's room, the workplaces to its places at work), then the parks
-- and yards, then the gardens and the street things, while the piece limit lasts.
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
		-- (the cells under paving: nothing but a yard's own decor goes on them, so the roads stay clear)
		local paved: { [number]: boolean } = {}
		local yardOk = false
		local function cell(x: number, z: number): number
			return (x + 512) * 4096 + (z + 2048)
		end

		local function def(id: string)
			return Buildings.byId[id]
		end
		local function have(id: string): boolean
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
			if g == "piece" and not yardOk then
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
			if d.kind == "path" then
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
		local function full(): boolean
			return used.piece >= L.piece
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

		-- The pavings and the street things of this tier.
		local AVENUE = best({ "dirtpath", "cobble", "brickroad", "marblewalk" })
		if tier >= 2 and tier <= 3 then
			AVENUE = "cobble"
		end
		local STREET = best({ "gravel", "stonepath", "flagstone" })
		if tier >= 5 then
			STREET = "brickroad"
		end
		local LANE = best({ "dirtpath", "flagstone" })
		local PARKPATH = best({ "gravel", "meadow" })
		local LAMP = best({ "torch", "lamppost", "streetlamp" })
		local SLAMP = best({ "torch", "lamppost" })
		local GLAMP = best({ "gardenlights", "candles" }) or LAMP
		local HEDGE = best({ "picket", "hedgerow" })
		local FARMFENCE = best({ "splitrail", "wattle" }) or "picket"
		local PARKFENCE = best({ "picket", "stonewall", "ironrail" })
		local WATER = best({ "stream", "lilypond" })
		if tier >= 4 then
			WATER = "lagoon"
		end
		local BRIDGE = best({ "plankbridge", "ropebridge", "stonebridge", "moonbridge" })
		local FLOATS = avail({ "lilypads", "duckfloat", "lotus", "waterlanterns", "reeds" })
		local SMALLTREES = avail({ "pine", "birch" })
		local BIGTREES = avail({ "oak", "cherry", "maple", "willow", "bigoak", "starfruit", "redwood" })
		local FLOWERS = avail({ "flowers", "tulips", "lavender", "rosebush", "sunflowers", "berrybush" })
		local SMALLS = avail({ "gnome", "birdbath", "beehive", "sundial", "mushrooms", "fern" })
		local SEATS = avail({ "bench", "parkbench", "stonebench", "logseats" })

		local k = 0
		local function pick(list: { string }): string?
			if #list == 0 then
				return nil
			end
			k += 1
			return list[(k - 1) % #list + 1]
		end

		------------------------------------------------------------------ the streets
		local function tileRow(id: string?, z: number, x0: number, x1: number)
			for x = x0 - x0 % 2, x1, 2 do
				add(id, x, z, 0)
			end
		end
		local function tileCol(id: string?, x: number, z0: number, z1: number)
			for z = z0 - z0 % 2, z1, 2 do
				add(id, x, z, 0)
			end
		end
		-- (the tree's ring, round wherever the tree stands: on the first island it can't stand behind the campfire)
		local tr = { x0 = -4, z0 = -6, x1 = 4, z1 = 2 }
		for _, q in placed do
			if def(q.id) and def(q.id).kind == "tree" then
				tr = Plot.rect(q.id, q.x, q.z, q.rot)
			end
		end
		local rx0, rx1 = tr.x0 - 2 - (tr.x0 % 2), tr.x1 + (tr.x1 % 2)
		local rz0, rz1 = tr.z0 - 2 - (tr.z0 % 2), math.max(tr.z1, Street.PLAZA.z1)
		tileCol(STREET, rx0, rz0, rz1)
		tileCol(STREET, rx1, rz0, rz1)
		tileRow(STREET, rz0, rx0, rx1)
		-- the avenue, up the middle and down from the plaza
		tileCol(AVENUE, -2, zN, -10)
		tileCol(AVENUE, 0, zN, -10)
		tileCol(AVENUE, -2, Street.PLAZA.z1 + 2, zS)
		tileCol(AVENUE, 0, Street.PLAZA.z1 + 2, zS)
		-- the cross streets, every 20 studs north of the tree and south of the plaza
		local streets: { number } = {}
		local z = -8
		while z > zN + 4 do
			table.insert(streets, z)
			if z ~= -8 then
				tileRow(STREET, z, -40, -3)
				tileRow(STREET, z, 2, 40)
			else
				tileRow(STREET, z, -40, -7)
				tileRow(STREET, z, 6, 40)
			end
			z -= 20
		end
		local southStreets: { number } = {}
		z = 26
		while z < zS - 4 do
			table.insert(southStreets, z)
			tileRow(STREET, z, -40, -3)
			tileRow(STREET, z, 2, 40)
			z += 20
		end

		------------------------------------------------------------------ the blocks
		type Block = { x0: number, x1: number, z0: number, z1: number, side: string, band: number }
		local blocks: { Block } = {}
		local function block(x0: number, x1: number, z0: number, z1: number, side: string, band: number)
			if z1 - z0 >= 6 then
				-- (the island's width at the block's middle: the coast curves, and every piece is checked anyway)
				local mid = (z0 + z1) // 2
				if rowX0[mid] == nil then
					return
				end
				x0, x1 = math.max(x0, rowX0[mid]), math.min(x1, rowX1[mid] + 1)
				if x1 - x0 >= 6 then
					table.insert(blocks, { x0 = x0, x1 = x1, z0 = z0, z1 = z1, side = side, band = band })
				end
			end
		end
		-- the old town round the plaza (between the first streets north and south)
		local core0 = if #streets > 0 then -6 else zN
		local core1 = if #southStreets > 0 then southStreets[1] - 1 else zS - 1
		block(-60, Street.PLAZA.x0 - 1, core0, core1, "west", 0)
		block(Street.PLAZA.x1 + 2, 60, core0, core1, "east", 0)
		for i, sz in streets do
			local north = streets[i + 1]
			local z0 = if north then north + 2 else zN
			block(-60, -4, z0, sz, "west", i)
			block(4, 60, z0, sz, "east", i)
		end
		for i, sz in southStreets do
			local south = southStreets[i + 1]
			local z1 = if south then south - 1 else zS - 1
			block(-60, -4, sz + 2, z1, "west", i)
			block(4, 60, sz + 2, z1, "east", i)
		end

		------------------------------------------------------------------ what goes where
		-- the best two huts, the workplaces of each kind of work (the most places first), the boosts
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

		-- A row of buildings along a block's south side, fronts to the street (rot 0): `pickNext` gives the next
		-- one (nil: the row ends); the gaps between them get `between(x, z0, z1)`. Returns the deepest building's depth.
		local function row(b: Block, zFront: number, pickNext: () -> string?, gap: number, between: ((number, number, number) -> ())?, placedAt: ((string, number, number) -> ())?): number
			local x = b.x0 + 1
			local deepest = 0
			local lastEnd = nil
			local misses = 0
			if b.x1 - b.x0 < 16 then
				gap = 2
			end
			while x < b.x1 - 1 and misses < 14 do
				local id = pickNext()
				if id == nil then
					break
				end
				local d = def(id)
				local zTop = zFront - d.d
				local done = false
				for dx = 0, 2 do
					if add(id, x + dx, zTop, 0) then
						if lastEnd and between then
							between(lastEnd, x + dx, zTop)
						end
						if placedAt then
							placedAt(id, x + dx, zTop)
						end
						lastEnd = x + dx + d.w
						x = x + dx + d.w + gap
						deepest = math.max(deepest, d.d)
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
			return deepest
		end

		-- Rows down a block from its street, a lane in front of each after the first, while the block has room.
		local function rows(b: Block, pickNext: () -> string?, gap: number, between: ((number, number, number) -> ())?, placedAt: ((string, number, number) -> ())?)
			local zFront = b.z1 - 2
			local empty = 0
			while zFront - 3 > b.z0 and empty < 4 do
				local d = row(b, zFront, pickNext, gap, between, placedAt)
				if d == 0 then
					-- (nothing fit here: the tree, the coast; a little further up)
					empty += 1
					zFront -= 3
					continue
				end
				empty = 0
				local zl = zFront - d - 3
				zl -= zl % 2
				if zl - 3 <= b.z0 then
					break
				end
				tileRow(LANE, zl, b.x0 + 1, b.x1 - 3)
				zFront = zl - 1
			end
		end

		-- between two huts: a tree at the back, flowers at the front
		local function gardenGap(xa: number, xb: number, zTop: number)
			local w = xb - xa
			if w >= 2 then
				add(pick(SMALLTREES), xa, zTop, 0)
				add(pick(FLOWERS), xa, zTop + 3, 0)
			end
		end
		local function fenceRun(id: string?, x0: number, z0: number, x1: number, z1: number, gapAt: number?)
			-- a fence round the rect (even grid lines), a gap of 2 at x = gapAt on its south side
			x0, z0 = x0 - x0 % 2, z0 - z0 % 2
			x1, z1 = x1 + x1 % 2, z1 + z1 % 2
			for x = x0, x1 - 2, 2 do
				add(id, x, z0, 0)
				if gapAt == nil or x < gapAt - 1 or x > gapAt then
					add(id, x, z1, 0)
				end
			end
			for zz = z0, z1 - 2, 2 do
				add(id, x0, zz, 90)
				add(id, x1, zz, 90)
			end
		end

		local function districtHouses(b: Block)
			local function nextHut(): string?
				for _, d in huts do
					if used.house + d.slots <= L.house then
						return d.id
					end
				end
				return nil
			end
			rows(b, nextHut, 3, gardenGap)
		end

		local actTurn = 0
		local function districtWork(b: Block)
			-- the boosts and a Hatchery first, then the workplaces round the kinds of work
			local queue: { string } = {}
			local function nextWork(): string?
				if #queue > 0 then
					return table.remove(queue, 1)
				end
				for _ = 1, 3 do
					actTurn += 1
					local act = ({ "farm", "wood", "shop" })[(actTurn - 1) % 3 + 1]
					for _, d in works[act] do
						if used.work + d.jobs <= L.work then
							return d.id
						end
					end
				end
				return nil
			end
			for i = #boosts, 1, -1 do
				if (tally["gen_" .. boosts[i]] or 0) == 0 then
					table.insert(queue, boosts[i])
					tally["gen_" .. boosts[i]] = 1
					break
				end
			end
			if used.hatch < L.hatch then
				table.insert(queue, 1, "hatchery")
			end
			local function workGap(xa: number, xb: number, zTop: number)
				if xb - xa >= 2 then
					add(pick(SMALLTREES), xa, zTop, 0)
					add(best({ "barrels", "crates", "haybale", "cart" }), xa, zTop + 3, 0)
				end
			end
			local farms = {}
			local function note(id: string, x: number, zTop: number)
				local d = def(id)
				if d.act == "farm" then
					table.insert(farms, { x = x, z = zTop, w = d.w, d = d.d })
				end
			end
			rows(b, nextWork, 3, workGap, note)
			-- (a farm's field fenced round, open at its front)
			for _, f in farms do
				fenceRun(FARMFENCE, f.x - 1, f.z - 1, f.x + f.w + 1, f.z + f.d + 1, f.x + f.w // 2)
			end
		end

		local parkTurn = 0
		local PLAY = avail({ "sandbox", "swing", "seesaw", "slide", "carousel", "climbframe", "trampoline" })
		local PAVILION = best({ "gazebo", "bandstand" })
		local function districtPark(b: Block)
			parkTurn += 1
			local bw = b.x1 - b.x0
			local cx = (b.x0 + b.x1) // 2
			cx -= cx % 2
			-- the south half: a pond with a path round it, or a fountain square
			local pz0 = b.z1 - 10
			pz0 -= pz0 % 2
			if parkTurn % 2 == 1 or not have("fountain") then
				local hw = math.clamp((bw // 2 - 6) // 2 * 2, 4, 6)
				for x = cx - hw, cx + hw - 2, 2 do
					for zz = pz0, pz0 + 2, 2 do
						add(WATER, x, zz, 0)
					end
				end
				add(BRIDGE, cx - 1, pz0 - 1, 0)
				local fx = cx - hw
				for _, id in FLOATS do
					if fx + 2 > cx - 1 and fx < cx + 1 then
						fx = cx + 1
					end
					if add(id, fx, pz0 + (if fx % 4 == 0 then 0 else 2), 0) then
						fx += 2
					end
				end
				add("rowboat", cx + hw - 2, pz0, 0)
				tileRow(PARKPATH, pz0 - 2, cx - hw - 2, cx + hw)
				tileRow(PARKPATH, pz0 + 4, cx - hw - 2, cx + hw)
				tileCol(PARKPATH, cx - hw - 2, pz0, pz0 + 2)
				tileCol(PARKPATH, cx + hw, pz0, pz0 + 2)
				add(pick(SEATS), cx - hw, pz0 + 7, 0)
				add(pick(SEATS), cx + 2, pz0 + 7, 0)
				add(SLAMP, cx - hw - 3, pz0 + 5, 0)
				add(SLAMP, cx + hw + 2, pz0 - 3, 0)
			else
				local SQ = best({ "flagstone", "checker", "marblewalk" }) or STREET
				for x = cx - 6, cx + 4, 2 do
					for zz = pz0 - 2, pz0 + 6, 2 do
						add(SQ, x, zz, 0)
					end
				end
				yardOk = true
				add(best({ "fountain", "crystalfountain" }), cx - 2, pz0, 0)
				add(pick(FLOWERS), cx - 6, pz0 - 2, 0)
				add(pick(FLOWERS), cx + 4, pz0 - 2, 0)
				add(pick(SEATS), cx - 6, pz0 + 6, 0)
				add(pick(SEATS), cx + 3, pz0 + 6, 0)
				yardOk = false
				add(SLAMP, cx - 7, pz0 + 8, 0)
				add(SLAMP, cx + 6, pz0 + 8, 0)
			end
			-- the north half: a playground on one side, a pavilion or a statue on the other
			local nz = b.z0 + 2
			local x = b.x0 + 2
			for i, id in PLAY do
				if i > 4 then
					break
				end
				local d = def(id)
				if add(id, x, nz + (4 - d.d), 0) then
					x += d.w + 1
				end
			end
			add(PAVILION, b.x1 - 7, nz, 0)
			add(best({ "statue", "goldstatue", "colossus", "moonwell" }), cx - 1, nz, 0)
			-- trees round the edges, flowers along the front
			for xx = b.x0, b.x1 - 3, 4 do
				add(pick(BIGTREES), xx, b.z0 - 1, 0)
			end
			for zz = b.z0 + 4, b.z1 - 4, 4 do
				add(pick(BIGTREES), b.x0, zz, 0)
				add(pick(BIGTREES), b.x1 - 3, zz, 0)
			end
			for xx = b.x0 + 3, b.x1 - 3, 3 do
				add(pick(FLOWERS), xx, b.z1 - 2, 0)
			end
		end

		-- the themes: their pieces, paving, fence and the plants outside
		local THEMES = {
			{ sub = "beach", pave = "sandtrail", fence = "driftwood", plants = { "palm", "coconuts" } },
			{ sub = "garden", pave = "meadow", fence = "hedgerow", plants = { "rosebush", "lavender", "topiary" } },
			{ sub = "farm", pave = "dirtpath", fence = "wattle", plants = { "sunflowers", "pumpkins" } },
			{ sub = "harbour", pave = "plankwalk", fence = "ropefence", plants = { "palm" } },
			{ sub = "town", pave = "checker", fence = "ironrail", plants = { "maple", "flowers" } },
			{ sub = "zen", pave = "raked", fence = "bamboofence", plants = { "cherry", "bonsai" } },
			{ sub = "autumn", pave = "leafpath", fence = "palisade", plants = { "maple", "pumpkins" } },
			{ sub = "jungle", pave = "mossstone", fence = "bamboofence", plants = { "jungletree", "monstera", "fern" } },
			{ sub = "frost", pave = "snowpath", fence = "icewall", plants = { "snowpine", "snowrock" } },
			{ sub = "desert", pave = "terracotta", fence = "adobe", plants = { "cactus", "bigcactus", "sandrock" } },
			{ sub = "fairy", pave = "mossstone", fence = "crystalfence", plants = { "giantshroom", "glowshroom", "mushrooms" } },
			{ sub = "volcano", pave = "basalt", fence = "stonewall", plants = { "lavarock", "basaltcols", "deadtree" } },
		}
		local themeQueue = {}
		for _, t in THEMES do
			local pieces = {}
			for _, d in Buildings.list do
				if d.kind == "decor" and d.sub == t.sub and d.tier <= tier and d.tab == "decor" then
					table.insert(pieces, d)
				end
			end
			if #pieces >= 3 then
				table.sort(pieces, function(a, b)
					return a.w * a.d > b.w * b.d
				end)
				table.insert(themeQueue, { t = t, pieces = pieces })
			end
		end
		local themeTurn = 0
		local function districtTheme(b: Block): boolean
			themeTurn += 1
			local th = themeQueue[(themeTurn - 1) % #themeQueue + 1]
			if th == nil then
				return false
			end
			local t = th.t
			local pave = if have(t.pave) then t.pave else LANE
			local fence = if have(t.fence) then t.fence else HEDGE
			-- the yard: the block less a margin, on the even grid
			local x0, x1 = b.x0 + 3, b.x1 - 3
			local z0, z1 = b.z0 + 3, b.z1 - 3
			x0, z0 = x0 + x0 % 2, z0 + z0 % 2
			x1, z1 = x1 - x1 % 2, z1 - z1 % 2
			for x = x0, x1 - 2, 2 do
				for zz = z0, z1 - 2, 2 do
					add(pave, x, zz, 0)
				end
			end
			fenceRun(fence, x0, z0, x1, z1, (x0 + x1) // 2)
			yardOk = true
			-- the pieces: the biggest at the back middle, the rest in rows from the back, a stud apart
			local cx = (x0 + x1) // 2
			local first = th.pieces[1]
			add(first.id, cx - first.w // 2, z0 + 1, 0)
			local x, zz, rowD = x0 + 1, z0 + 1, 0
			local n = 0
			local list = table.clone(th.pieces)
			table.remove(list, 1)
			-- (the small ones twice: a yard looks lived in)
			for _, d in th.pieces do
				if d.w * d.d <= 2 then
					table.insert(list, d)
				end
			end
			for _, d in list do
				local tries = 0
				while tries < 40 do
					tries += 1
					if x + d.w > x1 - 1 then
						x = x0 + 1
						zz += math.max(rowD, 1) + 1
						rowD = 0
					end
					if zz + d.d > z1 - 1 then
						break
					end
					if add(d.id, x, zz, 0) then
						x += d.w + 1
						rowD = math.max(rowD, d.d)
						n += 1
						break
					end
					x += 1
				end
			end
			yardOk = false
			-- its plants outside the fence, along the block's sides
			local plants = avail(t.plants)
			if #plants > 0 then
				for zz2 = b.z0 + 1, b.z1 - 3, 4 do
					add(plants[(zz2 // 4) % #plants + 1], b.x0, zz2, 0)
					add(plants[(zz2 // 4 + 1) % #plants + 1], b.x1 - 3, zz2, 0)
				end
			end
			return true
		end

		------------------------------------------------------------------ the districts, nearest the plaza first
		table.sort(blocks, function(a, b)
			if a.band ~= b.band then
				return a.band < b.band
			end
			return a.side < b.side
		end)
		local PATTERN = { "houses", "work", "park", "houses", "theme", "work", "park", "theme" }
		local pat = 0
		local kinds: { [Block]: string } = {}
		for _, b in blocks do
			local want: string
			if b.band == 0 then
				want = if b.side == "west" then "houses" else "work"
			else
				pat += 1
				want = PATTERN[(pat - 1) % #PATTERN + 1]
				-- (room and places at work still to give: those first, once the island has parks to show)
				local houseLeft = used.house < L.house
				local workLeft = used.work < L.work
				if want == "park" or want == "theme" then
					if b.band > 2 and houseLeft and pat % 2 == 0 then
						want = "houses"
					elseif b.band > 2 and workLeft and pat % 2 == 1 then
						want = "work"
					end
				elseif want == "houses" and not houseLeft then
					want = if workLeft then "work" else "park"
				elseif want == "work" and not workLeft then
					want = if houseLeft then "houses" else "theme"
				end
				if want == "theme" and #themeQueue == 0 then
					want = "park"
				end
			end
			kinds[b] = want
			if want == "houses" then
				districtHouses(b)
			elseif want == "work" then
				districtWork(b)
			end
		end
		-- any huts or workplaces still owed (a small island's blocks are cut up by the tree and the coast): wherever they
		-- fit, nearest the plaza first
		local spots: { { x: number, z: number } } = {}
		for zz = zS - 1, zN, -1 do
			for xx = -34, 34 do
				if Street.buildable(tier, xx, zz) then
					table.insert(spots, { x = xx, z = zz })
				end
			end
		end
		table.sort(spots, function(a, b)
			return math.abs(a.x) + math.abs(a.z - 6) < math.abs(b.x) + math.abs(b.z - 6)
		end)
		local function owed(list: { any }, room: () -> boolean)
			for _, d in list do
				local tries = 0
				while room() and tries < 40 do
					tries += 1
					local placedOne = false
					for _, sp in spots do
						if add(d.id, sp.x, sp.z, 0) then
							placedOne = true
							break
						end
					end
					if not placedOne then
						break
					end
				end
			end
		end
		owed(huts, function()
			return used.house < L.house
		end)
		local allWork = {}
		for _, act in { "farm", "wood", "shop" } do
			for _, d in works[act] do
				table.insert(allWork, d)
			end
		end
		table.sort(allWork, function(a, b)
			return a.jobs > b.jobs
		end)
		owed(allWork, function()
			return used.work < L.work
		end)

		-- the parks and yards once every building has its place
		for _, b in blocks do
			if kinds[b] == "park" then
				districtPark(b)
			elseif kinds[b] == "theme" then
				districtTheme(b)
			end
		end

		------------------------------------------------------------------ round the plaza and along the streets
		-- the tree's ring: lamps at its corners, flower beds and seats facing the plaza
		add(LAMP, -7, -10, 0)
		add(LAMP, 6, -10, 0)
		add(LAMP, -7, 9, 0)
		add(LAMP, 6, 9, 0)
		add(pick(FLOWERS), -9, -4, 0)
		add(pick(FLOWERS), 7, -4, 0)
		add(best({ "signpost", "noticeboard" }), 2, -11, 0)
		-- the avenue: a lamp every 10 studs, side to side, a bin, a postbox or a bench now and then
		local n = 0
		for zz = -14, zN + 1, -10 do
			n += 1
			add(LAMP, if n % 2 == 0 then -3 else 2, zz, 0)
			if n % 3 == 0 then
				add(best({ "bin", "postbox" }), if n % 2 == 0 then 2 else -3, zz - 4, 0)
			elseif n % 3 == 1 then
				add(best({ "parkbench", "stonebench" }), if n % 2 == 0 then 2 else -3, zz - 6, 90)
			end
		end
		for zz = 16, zS - 2, 10 do
			n += 1
			add(LAMP, if n % 2 == 0 then -3 else 2, zz, 0)
		end
		-- the streets: a smaller lamp every 14 studs on their side away from the plaza
		for _, sz in streets do
			for x = -38, 38, 14 do
				if math.abs(x) > 8 then
					add(SLAMP, x, sz - 1, 0)
				end
			end
		end
		for _, sz in southStreets do
			for x = -38, 38, 14 do
				if math.abs(x) > 8 then
					add(SLAMP, x, sz + 2, 0)
				end
			end
		end
		-- the gardens: flowers by the huts' doors and small things in the corners, while there's room
		for _, b in blocks do
			if kinds[b] == "houses" and not full() then
				for x = b.x0 + 1, b.x1 - 2, 5 do
					add(pick(SMALLS), x, b.z1 - 2, 0)
				end
			end
		end

		-- the seafront: beach things on the south shore either side of the avenue, once the open ground reaches it
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

		-- the planting: clusters on the open lawn (a big tree with flowers at its foot, a bush and a rock, a small
		-- tree and a fern), on a jittered grid, until the island holds about 80% of its pieces
		local seed = tier * 7919 + 17
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n
		end
		local ROCKS = avail({ "boulder", "rockpile", "mossrock", "sandrock", "crystals" })
		local PLANTS = avail({ "fern", "tallgrass", "mushrooms", "bush", "berrybush" })
		local goal = math.floor(L.piece * 0.8)
		for zz = zS - 5, zN + 1, -4 do
			for xx = -34, 34, 4 do
				if used.piece >= goal then
					break
				end
				local x, z2 = xx + rnd(2), zz + rnd(2)
				local kind = rnd(4)
				local done = false
				if kind == 0 then
					done = add(pick(BIGTREES), x, z2, 0)
					if done then
						add(pick(FLOWERS), x + 3, z2 + 1, 0)
					end
				elseif kind == 1 then
					done = add(pick(PLANTS), x, z2, 0)
					if done then
						add(pick(ROCKS), x + 2, z2 + 1, 0)
					end
				elseif kind == 2 then
					done = add(pick(SMALLTREES), x, z2, 0)
					if done then
						add(pick(PLANTS), x - 1, z2 + 2, 0)
					end
				end
				-- (no room for that: flowers, then a fern)
				if not done and not add(pick(FLOWERS), x, z2, 0) then
					add(best({ "fern", "mushrooms" }), x + 1, z2 + 1, 0)
				end
			end
		end

		local nTrees = 0
		for _, q in placed do
			local d = def(q.id)
			if d and d.tab == "nature" then
				nTrees += 1
			end
		end
		local kindsUsed: { [string]: number } = {}
		for _, b in blocks do
			kindsUsed[kinds[b]] = (kindsUsed[kinds[b]] or 0) + 1
		end
		log(
			"showcase: tier %d, %d blocks (%d huts, %d work, %d parks, %d yards); pieces %d of %d, tiles %d of %d, fences %d of %d; room %d of %d, places at work %d of %d, Hatcheries %d of %d; %d plants",
			tier,
			#blocks,
			kindsUsed.houses or 0,
			kindsUsed.work or 0,
			kindsUsed.park or 0,
			kindsUsed.theme or 0,
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
			L.hatch,
			nTrees
		)
		return { used = used, limits = L, zN = zN, zS = zS }
	end
end
