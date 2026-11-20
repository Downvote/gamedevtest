--!strict
-- The floating islands from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server:
-- PlotService builds each plot's island as players come and go, and a little islet on each free plot).
--   land(parent, origin, tier)    an occupied plot: the island at its tier (Data/Street's coast: the lawn in two tones,
--                                 the earth lip under its edge, the rock stepping in and down under that, stones and
--                                 roots hanging, tufts and flowers on the grass's rim, never where a building may stand),
--                                 an invisible wall just past the grass, and the island's sign on its south rim (its
--                                 board named "SignBoard"); built in chunks (landPlan, landChunk, landSign) so an
--                                 expansion changes only the chunks along the edge
--   emptyLot(parent, origin)      an unclaimed plot: a little islet with a sign
-- The request of 2026-11-20: "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the
-- island bigger." (the sea, the beaches, the swimming and the boats went with it; UI/SkyBackdrop paints the sky). The
-- layers are whole-stud cells merged into as few boxes as they make (greedy rectangles). Their outlines are bevelled
-- (the request of 2026-11-13: "could you bevel these to make them smoother, with rounded corners?"): every notch of a
-- layer's stairs is half filled by a flat triangle (a wedge on its side) and a square corner cut back, so each edge runs
-- straight, on a diagonal or along the grid, and turns in 45 degree steps (`bevelled`). The wall and the parts that
-- keep a bevel's cut corner solid are invisible and in the "Bounds" collision group (the pixel filter's rays pass
-- through them).
local Street = require(script.Parent.Parent.Data.Street)
local Blocks = require(script.Parent.Blocks)

local StreetModels = {}

local WALL_H = 14 -- the wall round an island's grass: far over a jump (Tuning.JumpHeight)

type Rect = Street.Rect

local function box(parent: Instance, frame: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(parent, { size = Vector3.new(w, h, d), cf = frame * CFrame.new(x, y, z), color = color, name = name, neon = neon })
end

-- A box by its top: x0..x1, z0..z1 plot-local, its top at `top`, `h` deep.
local function slab(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, h: number, color: string, name: string): BasePart
	return box(parent, o, (x0 + x1) / 2, top - h / 2, (z0 + z1) / 2, x1 - x0, h, z1 - z0, color, name)
end

------------------------------------------------------------------ cells to boxes
-- The cells `want` says yes to within b (inclusive cell coords), merged into rectangles (x0, z0, x1, z1 in studs:
-- the cells x0 .. x1 - 1, z0 .. z1 - 1), row by row.
local function sweep(b: Rect, want: (x: number, z: number) -> boolean): { Rect }
	local used: { [number]: boolean } = {}
	local out: { Rect } = {}
	local key = Street.cellKey
	local function free(x: number, z: number): boolean
		return want(x, z) and not used[key(x, z)]
	end
	for z = b.z0, b.z1 do
		local x = b.x0
		while x <= b.x1 do
			if free(x, z) then
				local x1 = x
				while x1 + 1 <= b.x1 and free(x1 + 1, z) do
					x1 += 1
				end
				local z1 = z
				while z1 + 1 <= b.z1 do
					local ok = true
					for xx = x, x1 do
						if not free(xx, z1 + 1) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					z1 += 1
				end
				for zz = z, z1 do
					for xx = x, x1 do
						used[key(xx, zz)] = true
					end
				end
				table.insert(out, { x0 = x, z0 = z, x1 = x1 + 1, z1 = z1 + 1 })
				x = x1 + 1
			else
				x += 1
			end
		end
	end
	return out
end

-- The same, row by row or column by column, whichever makes fewer rectangles.
local function greedy(b: Rect, want: (x: number, z: number) -> boolean): { Rect }
	local rows = sweep(b, want)
	local cols = sweep({ x0 = b.z0, z0 = b.x0, x1 = b.z1, z1 = b.x1 }, function(x: number, z: number): boolean
		return want(z, x)
	end)
	if #cols >= #rows then
		return rows
	end
	local out: { Rect } = {}
	for _, r in cols do
		table.insert(out, { x0 = r.z0, z0 = r.x0, x1 = r.z1, z1 = r.x1 })
	end
	return out
end
------------------------------------------------------------------ bevelled outlines
-- Each layer is a region of whole-stud cells, its outline bevelled so the coast reads round, not as stairs (the
-- request of 2026-11-13). A cell is four quarters (the triangles between its centre and its sides: 1 north (-z),
-- 2 east (+x), 3 south (+z), 4 west (-x)), a corner's half the two quarters either side of it. Where both sides of a
-- cell's corner border another label, its half at that corner takes that label: a cell outside a region with the
-- region on two sides of a corner (a notch in the stairs) is half filled, so the stairs' inner corners become
-- diagonals and a 45 degree staircase one straight line; a cell of a region with the outside on two sides of a corner
-- (a jutting corner) is cut back to its other half, but only where no notch beside it is filled (a square corner
-- with a straight run either side), so a bevel never zigzags. Labels are numbers: 0 nothing, a higher one fills a
-- notch of a lower one, a lower one cuts a corner of a higher one.
local SIDE = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
-- the corners NE, SE, SW, NW: kx, kz and the quarters either side
local CORNER = { { 1, -1, 1, 2 }, { 1, 1, 2, 3 }, { -1, 1, 3, 4 }, { -1, -1, 4, 1 } }
-- the turn of a flat wedge whose right angle sits in that corner (see `flat`)
local TURN = { math.pi / 2, 0, -math.pi / 2, math.pi }
-- a quarter drawn alone: the two half-stud squares along its side (offsets from the cell's corner), each holding a
-- small triangle with its right angle at the side's middle (that square's corner)
local SUBQ = {
	{ { 0, 0, 1 }, { 0.5, 0, 4 } },
	{ { 0.5, 0, 2 }, { 0.5, 0.5, 1 } },
	{ { 0, 0.5, 2 }, { 0.5, 0.5, 3 } },
	{ { 0, 0, 3 }, { 0, 0.5, 4 } },
}

-- A layer as drawn: its top and depth (as `slab` takes them), its parts' name, a colour a label, and whether the
-- founders stand on it.
type Level = { top: number, h: number, name: string, colors: { string }, solid: boolean }

-- Cell (x, z) under `lab` (the labels by cell): its own label, and its four quarters' labels when a bevel changes any
-- of them (nil: the cell is wholly its own).
local function quarters(x: number, z: number, lab: (x: number, z: number) -> number): (number, { number }?)
	local l = lab(x, z)
	local n, e, s, w = lab(x, z - 1), lab(x + 1, z), lab(x, z + 1), lab(x - 1, z)
	if n == l and e == l and s == l and w == l then
		return l, nil
	end
	local side = { n, e, s, w }
	local q: { number }? = nil
	for _, c in CORNER do
		local kx, kz, qa, qb = c[1], c[2], c[3], c[4]
		local la = side[qa]
		if la ~= l and la == side[qb] then
			-- a notch is filled; a jutting corner is cut unless this cell's own label fills a notch beside it (the cell
			-- across the corner, or past either side, is its label)
			local sa, sb = SIDE[qa], SIDE[qb]
			if
				la > l
				or (
					lab(x + kx, z + kz) ~= l
					and lab(x + 2 * sa[1] - kx, z + 2 * sa[2] - kz) ~= l
					and lab(x + 2 * sb[1] - kx, z + 2 * sb[2] - kz) ~= l
				)
			then
				local t = q or { l, l, l, l }
				t[qa], t[qb] = la, la
				q = t
			end
		end
	end
	return l, q
end

-- A flat right triangle of a layer in the square x0 .. x0 + s, z0 .. z0 + s (plot-local), its right angle in corner
-- k (CORNER's order), its legs along the square's sides there: a wedge on its side, its length upright as deep as the
-- layer. The same top and depth as the layer's boxes, so the two meet with no seam.
local function flat(parent: Instance, o: CFrame, lv: Level, x0: number, z0: number, s: number, k: number, label: number, solid: boolean): BasePart
	local p = Blocks.part(parent, {
		size = Vector3.new(lv.h, s, s),
		cf = o * CFrame.new(x0 + s / 2, lv.top - lv.h / 2, z0 + s / 2) * CFrame.Angles(0, TURN[k], 0) * CFrame.Angles(0, 0, math.pi / 2),
		color = lv.colors[label],
		shape = "Wedge",
		name = lv.name,
		collide = solid,
	})
	return p
end

-- A layer over the cells of b, bevelled: the cells wholly its own merged into boxes (greedy), the bevelled ones as
-- triangles, and a run of half cells along a diagonal as one big triangle where every cell it covers past the run is
-- the layer's own in the same label. The founders walk as they did on the cells: a filled notch never collides, a
-- cell of a solid layer still wholly covered (in two tones) does, and one cut back keeps an invisible part where it
-- stood (out of the pixel filter's rays: "Bounds"). With `keep`, only the cells it says yes to are drawn: a ring along
-- the outline (the lip, the rock under the edge), its outline bevelled as the whole region's, so it meets the layer
-- above with no seam, and nothing under the island's middle, where no ray ever reaches.
local function bevelled(m: Instance, o: CFrame, b: Rect, lv: Level, lab: (x: number, z: number) -> number, keep: ((x: number, z: number) -> boolean)?)
	local key = Street.cellKey
	local full: { [number]: { [number]: boolean } } = {}
	local cut: { [number]: boolean } = {}
	local anyCut = false
	-- the half cells (a cell split on a diagonal, a label each side or one side empty) by the corner of their right
	-- angle: x, z, the corner, the label, 1 if it collides (joined into runs below)
	local halves: { { [number]: { number } } } = { {}, {}, {}, {} }
	local list: { { number } } = {}
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			if keep and not keep(x, z) then
				continue
			end
			local l, q = quarters(x, z, lab)
			if q == nil then
				if l ~= 0 then
					local set = full[l] or {}
					full[l] = set
					set[key(x, z)] = true
				end
				continue
			end
			-- (a cell of the layer still wholly covered keeps its collision; one cut back stands on an invisible part)
			local whole = l ~= 0 and q[1] ~= 0 and q[2] ~= 0 and q[3] ~= 0 and q[4] ~= 0
			local solid = lv.solid and whole
			if l ~= 0 and lv.solid and not whole then
				cut[key(x, z)] = true
				anyCut = true
			end
			local split = 0
			for k, c in CORNER do
				local qa, qb = c[3], c[4]
				local qc = qb % 4 + 1
				if q[qa] == q[qb] and q[qc] == q[qc % 4 + 1] and q[qa] ~= q[qc] then
					split = k
					break
				end
			end
			if split ~= 0 then
				local opp = (split + 1) % 4 + 1
				for _, h in { { split, q[CORNER[split][3]] }, { opp, q[CORNER[opp][3]] } } do
					if h[2] ~= 0 then
						local rec = { x, z, h[1], h[2], if solid then 1 else 0 }
						halves[h[1]][key(x, z)] = rec
						table.insert(list, rec)
					end
				end
				continue
			end
			for label = 1, #lv.colors do
				local n = (if q[1] == label then 1 else 0) + (if q[2] == label then 1 else 0) + (if q[3] == label then 1 else 0) + (if q[4] == label then 1 else 0)
				if n == 4 then
					local p = slab(m, o, x, z, x + 1, z + 1, lv.top, lv.h, lv.colors[label], lv.name)
					p.CanCollide = solid
				elseif n > 0 then
					-- the halves it fills whole, then any quarter left as two small triangles
					local done = { false, false, false, false }
					for k, c in CORNER do
						if q[c[3]] == label and q[c[4]] == label then
							flat(m, o, lv, x, z, 1, k, label, solid)
							done[c[3]], done[c[4]] = true, true
						end
					end
					for i = 1, 4 do
						if q[i] == label and not done[i] then
							for _, sq in SUBQ[i] do
								flat(m, o, lv, x + sq[1], z + sq[2], 0.5, sq[3], label, solid)
							end
						end
					end
				end
			end
		end
	end
	-- The half cells along a diagonal (a chain: each a step east and a step in z from the last, the same corner, label
	-- and collision), from each chain's first: as big a triangle as covers only the chain and the layer's own whole
	-- cells in that label (the square's cells on the corner's side of the chain), then on from where it stopped.
	for _, rec in list do
		local x, z, k, label, solid = rec[1], rec[2], rec[3], rec[4], rec[5]
		local kx, kz = CORNER[k][1], CORNER[k][2]
		local dz = -kx * kz -- (the chain's step in z for a step east)
		local chain = halves[k]
		local function same(i: number): boolean
			local r = chain[key(x + i, z + i * dz)]
			return r ~= nil and r[4] == label and r[5] == solid
		end
		if same(-1) then
			continue
		end
		local own = full[label] or {}
		local i0 = 0
		while same(i0) do
			local n = 1
			while same(i0 + n) do
				-- one size bigger covers a new column (corner east) or row (corner west) of the square
				local ok = true
				for i = 0, n - 1 do
					local u, v = if kx == 1 then n else i, if kx == 1 then i else n
					if not own[key(x + i0 + u, z + (i0 + v) * dz)] then
						ok = false
						break
					end
				end
				if not ok then
					break
				end
				n += 1
			end
			flat(m, o, lv, x + i0, if dz == 1 then z + i0 else z - i0 - n + 1, n, k, label, solid == 1)
			i0 += n
		end
	end
	for label, set in full do
		for _, r in greedy(b, function(x, z)
			return set[key(x, z)] == true
		end) do
			local p = slab(m, o, r.x0, r.z0, r.x1, r.z1, lv.top, lv.h, lv.colors[label], lv.name)
			p.CanCollide = lv.solid
		end
	end
	if anyCut then
		for _, r in greedy(b, function(x, z)
			return cut[key(x, z)] == true
		end) do
			local f = Blocks.part(m, {
				size = Vector3.new(r.x1 - r.x0, lv.h, r.z1 - r.z0),
				cf = o * CFrame.new((r.x0 + r.x1) / 2, lv.top - lv.h / 2, (r.z0 + r.z1) / 2),
				color = "white",
				name = lv.name,
				transparency = 1,
				query = false,
			})
			f.CastShadow = false
			f.CollisionGroup = "Bounds"
		end
	end
end

------------------------------------------------------------------ small things
-- A number in [0, 1) from a cell and a salt, the same every time (no random state).
local function hash01(x: number, z: number, salt: number): number
	local h = (x * 73856093 + z * 19349663 + salt * 83492791) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 13))
	local lo, hi = h % 65536, h // 65536
	h = (lo * 1274126177 + ((hi * 1274126177) % 65536) * 65536) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Soft patches over the cells (a few sines): above `cut`, a patch.
local function patch(x: number, z: number, salt: number, cut: number): boolean
	local n = math.sin(x * 0.31 + z * 0.17 + salt) + math.sin(x * 0.11 - z * 0.29 + 1.3 + salt * 0.7) + math.sin(z * 0.43 + 2.1 + salt * 1.3) * 0.4
	return n > cut
end

local function tuft(parent: Instance, at: CFrame, flower: string?)
	box(parent, at, -0.1, 0.25, 0, 0.125, 0.5, 0.125, "leaf_dark", "Blade")
	box(parent, at, 0.12, 0.2, 0.08, 0.125, 0.4, 0.125, "leaf", "Blade")
	box(parent, at, 0, 0.3, -0.12, 0.125, 0.6, 0.125, "leaf_dark", "Blade")
	if flower then
		box(parent, at, 0, 0.7, -0.12, 0.25, 0.25, 0.25, flower, "Bloom")
	end
end

-- A length on the quarter-stud grid parts snap to (at least a quarter).
local function q(v: number): number
	return math.max(0.25, math.floor(v * 4 + 0.5) / 4)
end

-- A stone hanging under the island: three blocks narrowing down to a point, each a little off the last, `len` long
-- from `at` (the rock's underside) down.
local function hanger(parent: Instance, at: CFrame, len: number, h: number)
	local m = Blocks.model(nil, "Hanger")
	local a, b, c = q(len * 0.42), q(len * 0.33), q(len * 0.25)
	local ox = (h - 0.5) * 0.25
	box(m, at, 0, -a / 2, 0, 1.5, a, 1.5, "rock_dark", "Stone")
	box(m, at, ox, -a - b / 2, 0.125, 1, b, 1, if h < 0.5 then "slate" else "rock_dark", "Stone")
	box(m, at, ox * 2, -a - b - c / 2, 0.25, 0.5, c, 0.5, "slate", "Stone")
	if h > 0.6 then
		-- (moss on the top block's side)
		box(m, at, -0.25, -0.35, 0.65, 0.75, 0.5, 0.25, "moss", "Moss")
	end
	m.Parent = parent
end

-- A root hanging from under the earth lip: a thin strand, bending once.
local function root(parent: Instance, at: CFrame, len: number, h: number)
	local a = q(len * 0.6)
	local b = q(len - a)
	box(parent, at, 0, -a / 2, 0, 0.25, a, 0.25, if h < 0.5 then "hair_brown" else "wood_dark", "Root")
	box(parent, at, 0.125, -a - b / 2, 0.125, 0.25, b, 0.25, "wood_dark", "Root")
end

local function sign(m: Instance, at: CFrame, words: string?)
	local s = Blocks.model(nil, "PlotSign")
	box(s, at, -1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	box(s, at, 1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	local board = box(s, at, 0, 2.05, 0.1, 2.75, 1.25, 0.25, "wood", "SignBoard")
	if words then
		board:SetAttribute("Words", words)
	end
	box(s, at, 0, 2.05, 0.2, 2.25, 0.75, 0.25, "paper", "Face")
	box(s, at, 0, 2.75, 0.1, 3, 0.15, 0.4, "wood_dark", "Top")
	s.Parent = m
end

------------------------------------------------------------------ the island's layers
-- A floating island from its coast distance by cell (`dist`: negative on the grass), top down: the lawn (grass in two
-- tones: a darker rim and darker patches) on the whole grass; under its edge the earth lip, a ring LIP_W wide down to
-- LIP_BOT; under that the rock in STRATA, each a ring further in and further down than the one above, so the island's
-- underside steps in toward the middle; every outline bevelled (`bevelled`). Under the island's middle there is
-- nothing: a ray from the view never gets there (it meets the lawn, or a ring's outer face, or passes under the lowest
-- ring). Stones hang under the lowest ring, roots under the lip, tufts and flowers on the grass's rim.
-- (every height on the quarter-stud grid parts snap to: Blocks.part)
local LAWN_H = 0.5
local LIP_W = 2
local LIP_BOT = -3.25
type Stratum = { inset: number, w: number, top: number, bot: number, colors: { string } }
local STRATA: { Stratum } = {
	{ inset = 1.5, w = 2.25, top = LIP_BOT, bot = -5.5, colors = { "rock", "rock_dark" } },
	{ inset = 3, w = 2.25, top = -5.5, bot = -8, colors = { "rock", "rock_dark" } },
	{ inset = 4.75, w = 2.5, top = -8, bot = -10.25, colors = { "rock_dark", "rock" } },
	{ inset = 6.75, w = 2.5, top = -10.25, bot = -12.25, colors = { "rock_dark", "slate" } },
}
StreetModels.LIP_BOT = LIP_BOT
StreetModels.BOTTOM = STRATA[#STRATA].bot

local function layers(m: Instance, o: CFrame, b: Rect, dist: (x: number, z: number) -> number)
	local lawnY = Street.LAWN_Y
	-- the lawn's tone: 2 dark along its rim (every cell with the air round it among them, so a bevel at the edge is all
	-- one tone) and in patches, 1 light elsewhere
	local function lawn(x: number, z: number): number
		local d = dist(x, z)
		if d > 0 then
			return 0
		end
		local dark = d > -0.9
		if not dark then
			for dz = -1, 1 do
				for dx = -1, 1 do
					dark = dark or dist(x + dx, z + dz) > 0
				end
			end
		end
		if not dark then
			dark = patch(x, z, 0, 1.05)
		end
		return if dark then 2 else 1
	end
	bevelled(m, o, b, { top = lawnY, h = LAWN_H, name = "Lawn", colors = { "grass", "grass_dark" }, solid = true }, lawn)
	-- the earth lip: warm brown with darker streaks
	bevelled(m, o, b, { top = lawnY - LAWN_H, h = lawnY - LAWN_H - LIP_BOT, name = "Lip", colors = { "chocolate", "hair_brown" }, solid = false }, function(x, z)
		if dist(x, z) > 0 then
			return 0
		end
		return if patch(x, z, 3, 1.15) then 2 else 1
	end, function(x, z)
		return dist(x, z) > -LIP_W
	end)
	for k, st in STRATA do
		bevelled(m, o, b, { top = st.top, h = st.top - st.bot, name = "Rock", colors = st.colors, solid = false }, function(x, z)
			if dist(x, z) > -st.inset then
				return 0
			end
			return if patch(x, z, 5 + k, 1.0) then 2 else 1
		end, function(x, z)
			return dist(x, z) > -(st.inset + st.w)
		end)
	end
end

-- The invisible wall round the grass: the cells just past its edge, far over a jump ("Bounds": the pixel filter's
-- rays pass through it).
local function walls(m: Instance, o: CFrame, b: Rect, dist: (x: number, z: number) -> number)
	for _, r in greedy(b, function(x: number, z: number): boolean
		local d = dist(x, z)
		return d > 0 and d <= Street.WALL
	end) do
		local w = Blocks.part(m, {
			size = Vector3.new(r.x1 - r.x0, WALL_H, r.z1 - r.z0),
			cf = o * CFrame.new((r.x0 + r.x1) / 2, Street.LAWN_Y - 1 + WALL_H / 2, (r.z0 + r.z1) / 2),
			color = "white",
			name = "Bound",
			transparency = 1,
			query = false,
		})
		w.CastShadow = false
		w.CollisionGroup = "Bounds"
	end
end

-- The island's small things, never on a cell a building may use: tufts and flowers on the grass's rim, roots under
-- the lip's overhang, stones hanging under the lowest ring of rock. Each is picked in its own block of the grid
-- (BLOCK cells a side, the chunks' size a whole number of them): the block's cell with the lowest hash among those of
-- its kind's band, kept when a second hash is under the kind's share, so a chunk's things depend on its own cells
-- alone and a part of the island an expansion leaves as it was keeps the same things in the same places.
type ScatterKind = { id: string, salt: number, p: number, block: number, lo: number, hi: number }
local SCATTER: { ScatterKind } = {
	{ id = "tuft", salt = 79, p = 0.22, block = 2, lo = -0.95, hi = 0 },
	{ id = "root", salt = 31, p = 0.3, block = 2, lo = -1.4, hi = 0 },
	{ id = "hanger", salt = 47, p = 0.55, block = 4, lo = -(STRATA[#STRATA].inset + 1.5), hi = -STRATA[#STRATA].inset },
}

local function scatterIn(m: Instance, o: CFrame, b: Rect, dist: (x: number, z: number) -> number, sx: number?, sz: number?)
	local blooms = { "pink", "yellow", "white", "purple", "berry_red" }
	local lawnY = Street.LAWN_Y
	for _, k in SCATTER do
		local B = k.block
		for bz = b.z0 // B, b.z1 // B do
			for bx = b.x0 // B, b.x1 // B do
				local best, bestX, bestZ = math.huge, 0, 0
				for z = bz * B, bz * B + B - 1 do
					for x = bx * B, bx * B + B - 1 do
						if x < b.x0 or x > b.x1 or z < b.z0 or z > b.z1 then
							continue
						end
						local d = dist(x, z)
						if d <= k.lo or d > k.hi then
							continue
						end
						-- (clear round the island's sign: nothing in front of it)
						if sx and sz and math.abs(x + 0.5 - sx) < 3 and math.abs(z + 0.5 - sz) < 3 then
							continue
						end
						local h = hash01(x, z, k.salt)
						if h < best then
							best, bestX, bestZ = h, x, z
						end
					end
				end
				if best == math.huge or hash01(bestX, bestZ, k.salt + 1) >= k.p then
					continue
				end
				local x, z = bestX, bestZ
				local px, pz = x + 0.5, z + 0.5
				local h2 = hash01(x, z, k.salt + 2)
				if k.id == "tuft" then
					local bloom = if h2 < 0.45 then blooms[1 + math.floor(hash01(x, z, k.salt + 3) * #blooms)] else nil
					tuft(m, o * CFrame.new(px, lawnY, pz), bloom)
				elseif k.id == "root" then
					root(m, o * CFrame.new(px, LIP_BOT, pz), 0.5 + h2 * 0.9, hash01(x, z, k.salt + 3))
				else
					hanger(m, o * CFrame.new(px, STRATA[#STRATA].bot, pz), 2 + h2 * 4, hash01(x, z, k.salt + 3))
				end
			end
		end
	end
end

------------------------------------------------------------------ the land in chunks
-- The island's land is built in chunks of CHUNK x CHUNK cells (plot-local, on a grid from the plot's origin), each a
-- model of its own named for what it holds: Chunk_<cx>_<cz>_<signature>, the signature a hash of the band of the coast
-- distance (the thresholds every layer, ring and wall reads) of every cell in it and LAND_MARGIN cells round it (its
-- bevels read two cells out), and of the sign's place when it is near. A cell further in than the lowest ring's inner
-- edge reads the same on every tier, so an expansion changes only the chunks along the island's edge, old and new:
-- the server builds those ahead (PlotService), every client draws them ahead (the pixel filter's pre-cast), and the
-- swap moves them in (the request of 2026-11-19: "Expansion is very slow and laggy, especially at higher levels").
-- The sign is a model of its own. Splitting the ground at a chunk's edge draws no line: the pixel filter inks only
-- where the depth jumps.
StreetModels.CHUNK = 8
local LAND_MARGIN = 3

export type LandChunk = { name: string, rect: Rect }
export type LandPlan = { chunks: { LandChunk }, sign: string, walls: string }

-- The coast distances the drawing reads a cell by (each layer's, each ring's inner edge, the rim, the wall), deepest
-- last.
local BANDS: { number } = { Street.WALL, 0, -0.9, -0.95, -1, -1.2, -LIP_W }
for _, st in STRATA do
	table.insert(BANDS, -st.inset)
	table.insert(BANDS, -(st.inset + st.w))
end
table.insert(BANDS, -(STRATA[#STRATA].inset + 1.5))

-- A cell's code for the signature: 0 the open air, else which of the bands its coast distance is in.
local function cellCode(tier: number, x: number, z: number): number
	local d = Street.cellDist(tier, x, z)
	if d > Street.WALL then
		return 0
	end
	local c = 1
	for _, t in BANDS do
		if d <= t then
			c += 1
		end
	end
	return c
end

-- The lot's cells.
local function lotCells(): Rect
	local lot = Street.LOT
	return { x0 = math.ceil(lot.x0), z0 = math.ceil(lot.z0), x1 = math.floor(lot.x1) - 1, z1 = math.floor(lot.z1) - 1 }
end

-- The island's sign's name at a tier (by its place on the south rim).
function StreetModels.signName(tier: number): string
	local sx, sz = Street.sign(tier)
	return string.format("Sign_%d_%d", math.floor(sx * 2), math.floor(sz * 2))
end

-- The wall's model's name at a tier.
function StreetModels.wallsName(tier: number): string
	return "Walls_" .. math.clamp(math.floor(tier), 1, Street.TOP)
end

-- The island's chunks at a tier (those with any of it in them), named for what they hold, its sign's name and its
-- wall's.
function StreetModels.landPlan(tier: number): LandPlan
	local CH = StreetModels.CHUNK
	local lc = lotCells()
	local b = Street.cellBounds(tier)
	local x0, z0 = math.max(b.x0, lc.x0), math.max(b.z0, lc.z0)
	local x1, z1 = math.min(b.x1, lc.x1), math.min(b.z1, lc.z1)
	local sx, sz = Street.sign(tier)
	local M = LAND_MARGIN
	local P1, P2 = 67108859, 67108837
	local out: { LandChunk } = {}
	for cz = z0 // CH, z1 // CH do
		for cx = x0 // CH, x1 // CH do
			local r = { x0 = math.max(cx * CH, lc.x0), z0 = math.max(cz * CH, lc.z0), x1 = math.min(cx * CH + CH - 1, lc.x1), z1 = math.min(cz * CH + CH - 1, lc.z1) }
			local any = false
			local h1, h2 = 7, 11
			for z = r.z0 - M, r.z1 + M do
				for x = r.x0 - M, r.x1 + M do
					local c = cellCode(tier, x, z)
					if c ~= 0 and x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
						any = true
					end
					h1 = (h1 * 31 + c + 1) % P1
					h2 = (h2 * 37 + c + 3) % P2
				end
			end
			if not any then
				continue
			end
			-- (the sign's place, where its clearing reaches the chunk's things)
			if sx > r.x0 - 4 and sx < r.x1 + 5 and sz > r.z0 - 4 and sz < r.z1 + 5 then
				h1 = (h1 * 31 + math.floor(sx * 2) + 4096) % P1
				h2 = (h2 * 37 + math.floor(sz * 2) + 4096) % P2
			end
			table.insert(out, { name = string.format("Chunk_%d_%d_%07x%07x", cx, cz, h1, h2), rect = r })
		end
	end
	return { chunks = out, sign = StreetModels.signName(tier), walls = StreetModels.wallsName(tier) }
end

-- One chunk of the tier's land (StreetModels.landPlan's): its layers and its small things, into parent.
function StreetModels.landChunk(parent: Instance, origin: Vector3, tier: number, c: LandChunk): Model
	local m = Blocks.model(nil, c.name)
	local o = CFrame.new(origin)
	local function dist(x: number, z: number): number
		return Street.cellDist(tier, x, z)
	end
	layers(m, o, c.rect, dist)
	local sx, sz = Street.sign(tier)
	scatterIn(m, o, c.rect, dist, sx, sz)
	Blocks.windy(m) -- the tufts sway
	m.Parent = parent
	return m
end

-- The wall round the tier's grass, all of it in one model of its own (Walls_<tier>): out of the chunks, so a chunk's
-- box (what the pixel filter draws again or ahead when the chunk comes or goes) stays as small as what shows of it;
-- the wall itself is never drawn.
function StreetModels.landWalls(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, StreetModels.wallsName(tier))
	walls(m, CFrame.new(origin), Street.cellBounds(tier), function(x: number, z: number): number
		return Street.cellDist(tier, x, z)
	end)
	m.Parent = parent
	return m
end

-- The island's sign on its south rim (tapped: the island's card; its name floats over it), named by its place.
function StreetModels.landSign(parent: Instance, origin: Vector3, tier: number): Model
	local sx, sz = Street.sign(tier)
	local m = Blocks.model(nil, StreetModels.signName(tier))
	sign(m, CFrame.new(origin) * CFrame.new(sx, Street.LAWN_Y, sz), "island")
	m.Parent = parent
	return m
end

-- The whole island at a tier: every chunk of its land, its wall and the sign, under one model "Land".
function StreetModels.land(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, "Land")
	for _, c in StreetModels.landPlan(tier).chunks do
		StreetModels.landChunk(m, origin, tier, c)
	end
	StreetModels.landWalls(m, origin, tier)
	StreetModels.landSign(m, origin, tier)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an unclaimed plot
-- A little islet floating where an island will be, built as the islands are, with a sign.
function StreetModels.emptyLot(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "EmptyLot")
	local o = CFrame.new(origin)
	local cx, cz, rx, rz = Street.CENTER.x, Street.CENTER.z, 7, 5.5
	local function dist(x: number, z: number): number
		local dx, dz = x + 0.5 - cx, z + 0.5 - cz
		local a = math.atan2(dz, dx)
		local er = 1 / math.sqrt((math.cos(a) / rx) ^ 2 + (math.sin(a) / rz) ^ 2)
		return math.sqrt(dx * dx + dz * dz) - er * (1 + 0.1 * math.sin(3 * a + 1)) - 0.01
	end
	local b = { x0 = cx - 10, z0 = cz - 9, x1 = cx + 9, z1 = cz + 8 }
	layers(m, o, b, dist)
	scatterIn(m, o, b, dist, 0.5, cz + 2.5)
	sign(m, o * CFrame.new(0.5, Street.LAWN_Y, cz + 2.5), "empty")
	Blocks.windy(m)
	m.Parent = parent
	return m
end

return StreetModels
