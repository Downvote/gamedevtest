--!strict
-- The sea from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server: PlotService builds
-- every plot's water at start and each plot's island as players come and go).
--   road(parent, origin)          a plot's water: its lot's and the open sea's, and the invisible seabed under it
--                                 (every plot, occupied or not)
--   land(parent, origin, tier)    an occupied plot: the island (Data/Street's coast: grass in two tones, the sand
--                                 beach, the wet sand at the waterline, a ring of foam, the light shallows), the plaza
--                                 with its campfire, log seats and flag, the island's sign on its south beach (its
--                                 board named "SignBoard"), palms, rocks, shells, starfish, driftwood, seaweed and
--                                 flowers round the coast (never where a building may stand)
--   emptyLot(parent, origin)      an unclaimed plot: open water and a little sandbar with a palm and a sign
--   ends(parent)                  the sea at both ends of the row and the invisible walls round the world
-- The island's layers are whole-stud cells merged into as few boxes as they make (greedy rectangles), each layer a
-- little lower than the one inside it, so the coast steps down to the sea. Their outlines are bevelled (the request of
-- 2026-11-13: "could you bevel these to make them smoother, with rounded corners?"): every notch of a layer's stairs is
-- half filled by a flat triangle (a wedge on its side) and a square corner cut back, so each edge runs straight, on a
-- diagonal or along the grid, and turns in 45 degree steps (`bevelled`; the plaza's ring of sand too). The palms'
-- trunks are smooth curves of round segments joined by balls. The sea, the shallows and the foam carry a
-- "PixelWater" attribute (1, 2, 3): the pixel filter animates them. There are no docks: each island stands alone in
-- the sea (the request of 2026-11-13: "remove the docks area, it should just be an island. players can swim around
-- in water to reach other player islands"). The water lets the founders through to the seabed (Street.SEABED_Y), an
-- invisible floor under the whole sea, and an invisible shelf under the foam is the step up to the wet sand, so they
-- swim off any beach and climb out on any other. The seabed, the shelves and the world's walls are invisible and in
-- the "Bounds" collision group (the pixel filter's rays pass through them).
local Street = require(script.Parent.Parent.Data.Street)
local Util = require(script.Parent.Parent.Logic.Util)
local Types = require(script.Parent.Parent.Types)
local Blocks = require(script.Parent.Blocks)

local StreetModels = {}

local WALL_H = 40 -- the world's edge: far over a jump (Tuning.JumpHeight)

type Rect = Street.Rect
type Rng = Types.Rng

local function box(parent: Instance, frame: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(parent, { size = Vector3.new(w, h, d), cf = frame * CFrame.new(x, y, z), color = color, name = name, neon = neon })
end

-- A box by its top: x0..x1, z0..z1 plot-local, its top at `top`, `h` deep.
local function slab(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, h: number, color: string, name: string): BasePart
	return box(parent, o, (x0 + x1) / 2, top - h / 2, (z0 + z1) / 2, x1 - x0, h, z1 - z0, color, name)
end

local function ball(parent: Instance, frame: CFrame, x: number, y: number, z: number, dia: number, color: string): BasePart
	return Blocks.part(parent, { size = Vector3.new(dia, dia, dia), cf = frame * CFrame.new(x, y, z), color = color, shape = "Ball" })
end

-- Water (animated by the pixel filter: kind 1 the sea, 2 the shallows, 3 the foam): the founders swim through it.
local function water(p: BasePart, kind: number): BasePart
	p:SetAttribute("PixelWater", kind)
	p.CanCollide = false
	return p
end

-- An invisible floor (plot-local x0..x1, z0..z1, its top at `top`): the seabed the founders swim on, or the shelf under
-- the foam that steps up to the wet sand. Never in the pixel filter's rays ("Bounds").
local function floor(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, name: string)
	local f = Blocks.part(parent, {
		size = Vector3.new(math.max(0.5, x1 - x0), 1, math.max(0.5, z1 - z0)),
		cf = o * CFrame.new((x0 + x1) / 2, top - 0.5, (z0 + z1) / 2),
		color = "white",
		name = name,
		transparency = 1,
		query = false,
	})
	f.CastShadow = false
	f.CollisionGroup = "Bounds"
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

-- A layer as drawn: its top and depth (as `slab` takes them), its parts' name, a colour a label, the PixelWater kind
-- of a water layer, and whether the founders stand on it.
type Level = { top: number, h: number, name: string, colors: { string }, kind: number?, solid: boolean }

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
	if lv.kind then
		water(p, lv.kind)
	end
	return p
end

-- A layer over the cells of b, bevelled: the cells wholly its own merged into boxes (greedy), the bevelled ones as
-- triangles, and a run of half cells along a diagonal as one big triangle where every cell it covers past the run is
-- the layer's own in the same label. The founders walk and swim as they did on the cells: a filled notch never
-- collides, a cell of a solid layer still wholly covered (in two tones) does, and one cut back keeps an invisible part
-- where it stood (out of the pixel filter's rays, like the shelf).
local function bevelled(m: Instance, o: CFrame, b: Rect, lv: Level, lab: (x: number, z: number) -> number)
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
					if lv.kind then
						water(p, lv.kind)
					end
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
			if lv.kind then
				water(p, lv.kind)
			end
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
-- A palm's trunk: one smooth curve from its foot up into the crown at (tx, ty) (f's frame; upright at the foot, leaning
-- out through the middle, upright again under the crown), round segments joined end to end with a ball at each joint
-- as wide as the segment below it, so it bends with no gap and no step. The rings of its bark in two woods in turn,
-- narrowing a little going up from w0 (widths on the 1/8-stud grid: an art pixel; DecorModels' Palm Tree the same).
local function palmTrunk(m: Instance, f: CFrame, tx: number, ty: number, w0: number)
	local n = 6
	local pts: { Vector3 } = {}
	for j = 0, n do
		local t = j / n
		table.insert(pts, Vector3.new(tx * (3 * t * t - 2 * t * t * t), ty * t, 0))
	end
	for i = 1, n do
		local a, b = pts[i], pts[i + 1]
		local d = math.max(0.25, math.floor(w0 * (1 - (i - 1) * 0.055) * 8 + 0.5) / 8)
		local color = if i % 2 == 1 then "wood" else "wood_dark"
		local seg = Blocks.part(m, { size = Vector3.new(1, 1, 1), cf = f * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color = color, shape = "Cylinder", name = "Trunk" })
		seg.Size = Vector3.new((b - a).Magnitude, d, d) -- (exact: the joints meet)
		if i < n then
			local joint = Blocks.part(m, { size = Vector3.new(1, 1, 1), cf = f * CFrame.new(b), color = color, shape = "Ball", name = "Trunk" })
			joint.Size = Vector3.new(d, d, d)
		end
	end
end

local function palm(parent: Instance, at: CFrame, s: number, lean: number?)
	local m = Blocks.model(nil, "Palm")
	local f = at * CFrame.Angles(0, lean or 0, 0)
	-- the crown 1.8 studs out (at s 1) and 5.4 up, the trunk's top reaching into it
	local x = 1.8 * s
	local top = 5.4 * s
	palmTrunk(m, f, x, top - 0.1 * s, 0.75 * s)
	ball(m, f, x + 0.25, top - 0.55, 0.3, 0.55 * s, "wood_dark")
	ball(m, f, x - 0.2, top - 0.6, -0.25, 0.5 * s, "wood_dark")
	box(m, f, x, top, 0, 1.25 * s, 0.5 * s, 1.25 * s, "leaf_dark", "Crown")
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } } do
		local long = k <= 4
		local len = (if long then 2.75 else 2) * s
		local cx, cz = x + d[1] * len / 2, d[2] * len / 2
		local frond = Blocks.part(m, {
			size = Vector3.new(len, 0.35 * s, 0.9 * s),
			cf = f * CFrame.new(cx, top - 0.15 - (if long then 0.35 else 0.1) * s, cz) * CFrame.Angles(0, math.atan2(-d[2], d[1]), math.rad(if long then -12 else -6)),
			color = if k % 2 == 0 then "leaf" else "leaf_dark",
			name = "Frond",
		})
		local _ = frond
	end
	m.Parent = parent
end

-- A rock cluster half in the water: a big stone and a couple of smaller ones round it.
local function rocks(parent: Instance, at: CFrame, s: number, rng: Rng)
	local m = Blocks.model(nil, "Rocks")
	box(m, at, 0, 0.35 * s, 0, 1.5 * s, 1.0 * s, 1.25 * s, "rock", "Stone")
	box(m, at, 0.1 * s, 0.9 * s, -0.05 * s, 1.0 * s, 0.25 * s, 0.75 * s, "rock", "Stone")
	for k = 1, rng:int(1, 3) do
		local a = rng:next() * math.pi * 2
		local r = (1.0 + rng:next() * 0.4) * s
		box(m, at, math.cos(a) * r, 0.15 * s, math.sin(a) * r, (0.5 + rng:next() * 0.5) * s, (0.4 + rng:next() * 0.3) * s, (0.5 + rng:next() * 0.4) * s, if k % 2 == 0 then "rock" else "rock_dark", "Stone")
	end
	m.Parent = parent
end

local function shell(parent: Instance, at: CFrame, kind: number)
	if kind == 1 then
		-- a starfish: two crossed bars
		box(parent, at, 0, 0.06, 0, 0.9, 0.12, 0.25, "orange", "Starfish")
		box(parent, at * CFrame.Angles(0, math.rad(72), 0), 0, 0.06, 0, 0.9, 0.12, 0.25, "orange", "Starfish")
	elseif kind == 2 then
		box(parent, at, 0, 0.08, 0, 0.5, 0.16, 0.4, "pink", "Shell")
		box(parent, at, 0, 0.18, -0.05, 0.25, 0.08, 0.25, "cream", "Shell")
	else
		box(parent, at, 0, 0.08, 0, 0.4, 0.16, 0.4, "cream", "Shell")
	end
end

local function driftwood(parent: Instance, at: CFrame)
	box(parent, at, 0, 0.18, 0, 2.5, 0.35, 0.4, "wood", "Driftwood")
	box(parent, at, 0.9, 0.2, 0.3, 0.75, 0.25, 0.25, "wood_dark", "Branch")
end

local function seaweed(parent: Instance, at: CFrame)
	box(parent, at, 0, 0.05, 0, 0.75, 0.1, 0.25, "leaf_dark", "Seaweed")
	box(parent, at, 0.25, 0.05, 0.25, 0.25, 0.1, 0.5, "leaf_dark", "Seaweed")
end

local function tuft(parent: Instance, at: CFrame, flower: string?)
	box(parent, at, -0.1, 0.25, 0, 0.125, 0.5, 0.125, "leaf_dark", "Blade")
	box(parent, at, 0.12, 0.2, 0.08, 0.125, 0.4, 0.125, "leaf", "Blade")
	box(parent, at, 0, 0.3, -0.12, 0.125, 0.6, 0.125, "leaf_dark", "Blade")
	if flower then
		box(parent, at, 0, 0.7, -0.12, 0.25, 0.25, 0.25, flower, "Bloom")
	end
end

------------------------------------------------------------------ a plot's water
function StreetModels.road(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Road")
	local o = CFrame.new(origin)
	local x0, x1 = Street.LOT.x0, Street.LOT.x1
	-- the water: the lot's and the open sea's (animated by the pixel filter), far past the world's walls
	water(slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water"), 1)
	-- the seabed under it, as far as the world's walls
	floor(m, o, x0, Street.LOT.z0, x1, Street.SEA.z1, Street.SEABED_Y, "Seabed")
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the coast
-- An island's layers from a cell source: layer(x, z) (Street's codes) and dist(x, z) (the coast distance at the
-- cell's centre), over the cells of b. Grass in two tones (a darker rim and darker patches), the sand beach, the wet
-- sand, the foam, the shallows; each a step lower than the one inside it and running on under it (the foam too, hidden
-- under the wet sand), each bevelled (`bevelled`). Cells past b are only looked at, so a layer cut off at b's edge (a
-- neighbour's water) ends there straight.
local function coast(m: Instance, o: CFrame, b: Rect, layer: (x: number, z: number) -> number, dist: (x: number, z: number) -> number)
	local key = Street.cellKey
	-- a cell's height among the layers: 5 the grass, 4 the sand, 3 the wet sand, 2 the foam, 1 the shallows, 0 the sea
	local RANK = { [Street.GRASS] = 5, [Street.SAND] = 4, [Street.WET] = 3, [Street.FOAM] = 2, [Street.SHALLOW] = 1 }
	local ranks: { [number]: number } = {}
	local function rank(x: number, z: number): number
		local k = key(x, z)
		local r = ranks[k]
		if r == nil then
			r = RANK[layer(x, z)] or 0
			ranks[k] = r
		end
		return r
	end
	local function from(r: number): (x: number, z: number) -> number
		return function(x: number, z: number): number
			return if rank(x, z) >= r then 1 else 0
		end
	end
	-- the grass's tone: 2 dark along its rim (every cell with something else round it among them, so a bevel at the
	-- coast is all one tone) and in patches, 1 light elsewhere
	local tones: { [number]: number } = {}
	local function tone(x: number, z: number): number
		if rank(x, z) < 5 then
			return 0
		end
		local k = key(x, z)
		local t = tones[k]
		if t == nil then
			local dark = dist(x, z) > -0.9
			for dz = -1, 1 do
				for dx = -1, 1 do
					dark = dark or rank(x + dx, z + dz) < 5
				end
			end
			if not dark then
				local n = math.sin(x * 0.31 + z * 0.17) + math.sin(x * 0.11 - z * 0.29 + 1.3) + math.sin(z * 0.43 + 2.1) * 0.4
				dark = n > 1.05
			end
			t = if dark then 2 else 1
			tones[k] = t
		end
		return t
	end
	bevelled(m, o, b, { top = Street.SHALLOW_Y, h = 0.5, name = "Shallows", colors = { "shallow" }, kind = 2, solid = false }, from(1))
	bevelled(m, o, b, { top = Street.FOAM_Y, h = 0.2, name = "Foam", colors = { "foam" }, kind = 3, solid = false }, from(2))
	-- (the step out of the sea under the foam's own cells: halfway from the seabed up to the wet sand)
	for _, r in greedy(b, function(x, z)
		return rank(x, z) == 2
	end) do
		floor(m, o, r.x0, r.z0, r.x1, r.z1, (Street.SEABED_Y + Street.WET_Y) / 2, "Shelf")
	end
	bevelled(m, o, b, { top = Street.WET_Y, h = 0.9, name = "WetSand", colors = { "sand_dark" }, solid = true }, from(3))
	bevelled(m, o, b, { top = Street.SAND_Y, h = 0.15, name = "Beach", colors = { "sand" }, solid = true }, from(4))
	bevelled(m, o, b, { top = Street.LAWN_Y, h = 0.12, name = "Lawn", colors = { "grass", "grass_dark" }, solid = true }, tone)
end

------------------------------------------------------------------ an island
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

-- The plaza round the campfire: a ring of sand on the grass, a ring of stones round the fire's logs and flames, three
-- log seats, a flagpole with the island's pennant and two torches.
local function plaza(m: Instance, o: CFrame)
	local c = Street.CENTER
	local function inRing(x: number, z: number): boolean
		local dx, dz = x + 0.5 - c.x, z + 0.5 - c.z
		return dx * dx + dz * dz <= 12.5
	end
	bevelled(m, o, { x0 = c.x - 5, z0 = c.z - 5, x1 = c.x + 4, z1 = c.z + 4 }, { top = Street.LAWN_Y + 0.04, h = 0.1, name = "PlazaSand", colors = { "sand_dark" }, solid = true }, function(x, z)
		return if inRing(x, z) then 1 else 0
	end)
	local at = o * CFrame.new(c.x, Street.LAWN_Y + 0.04, c.z)
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(m, at, math.cos(a) * 1.25, 0.2, math.sin(a) * 1.25, 0.6, 0.4, 0.6, if k % 2 == 0 then "rock" else "rock_dark", "FireStone")
	end
	box(m, at * CFrame.Angles(0, math.rad(30), 0), 0, 0.2, 0, 1.6, 0.35, 0.35, "wood_dark", "Log")
	box(m, at * CFrame.Angles(0, math.rad(-40), 0), 0, 0.3, 0, 1.6, 0.35, 0.35, "wood", "Log")
	box(m, at, 0, 0.65, 0, 0.75, 0.6, 0.75, "orange", "Flame", true)
	box(m, at, 0, 1.1, 0, 0.4, 0.5, 0.4, "yellow", "Flame", true)
	box(m, at, 0.2, 0.9, -0.2, 0.25, 0.3, 0.25, "berry_red", "Ember", true)
	for _, s in { { -2.75, 0.5, 90 }, { 2.75, 0.25, 90 }, { 0, -2.75, 0 } } do
		box(m, at * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0), 0, 0.3, 0, 2.2, 0.55, 0.6, "wood", "Seat")
		box(m, at * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0), 0, 0.45, 0, 2.25, 0.1, 0.4, "wood_dark", "Bark")
	end
	-- the flagpole and its pennant
	box(m, at, 3, 2.5, -3, 0.25, 5, 0.25, "wood_dark", "FlagPole")
	ball(m, at, 3, 5.1, -3, 0.4, "gold")
	box(m, at, 3, 4.4, -2.1, 0.1, 1, 1.75, "berry_red", "Pennant")
	box(m, at, 3, 4.4, -1.5, 0.1, 0.5, 0.5, "white", "Mark")
	-- two tiki torches at the plaza's south edge
	for _, tx in { -2.5, 2.5 } do
		local tf = o * CFrame.new(tx, Street.LAWN_Y, Street.PLAZA.z1 - 0.5)
		box(m, tf, 0, 1.1, 0, 0.25, 2.2, 0.25, "wood_dark", "TorchPole")
		box(m, tf, 0, 2.3, 0, 0.5, 0.35, 0.5, "wood", "TorchCup")
		box(m, tf, 0, 2.6, 0, 0.3, 0.35, 0.3, "orange", "TorchFlame", true)
	end
end

-- Things round the coast, never on a cell a building may use: palms at the grass's edge, rocks in the shallows,
-- shells and starfish on the beach, driftwood, seaweed on the wet sand, tufts and flowers on the grass's rim.
local function scatter(m: Instance, o: CFrame, tier: number, b: Rect, rng: Rng)
	local cells: { [number]: { { x: number, z: number } } } = { {}, {}, {}, {}, {} }
	local rim: { { x: number, z: number } } = {}
	local sx, sz = Street.sign(tier)
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			local l = Street.layer(tier, x, z)
			-- (clear round the island's sign)
			local nearSign = math.abs(x + 0.5 - sx) < 3 and math.abs(z + 0.5 - sz) < 2.5
			if l ~= Street.SEA_CELL and not nearSign then
				table.insert(cells[l], { x = x, z = z })
				if l == Street.GRASS and not Street.buildable(tier, x, z) then
					table.insert(rim, { x = x, z = z })
				end
			end
		end
	end
	-- (the sign's spot taken first, wide: no palm leans in front of it)
	local taken: { { x: number, z: number, r: number } } = { { x = sx, z = sz, r = 5 } }
	local function clear(x: number, z: number, r: number): boolean
		for _, t in taken do
			if (t.x - x) ^ 2 + (t.z - z) ^ 2 < (t.r + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function pick(list: { { x: number, z: number } }, n: number, r: number, fn: (x: number, z: number) -> ())
		local done, tries = 0, 0
		while done < n and tries < n * 12 and #list > 0 do
			tries += 1
			local c = list[rng:int(1, #list)]
			local x, z = c.x + 0.5, c.z + 0.5
			if clear(x, z, r) then
				table.insert(taken, { x = x, z = z, r = r })
				fn(x, z)
				done += 1
			end
		end
	end
	local isle = Street.isle(tier)
	-- palms on the sand at the grass's edge, leaning out to sea
	local palmsAt: { { x: number, z: number } } = {}
	for _, c in cells[Street.SAND] do
		if Street.cellDist(tier, c.x, c.z) < 1.2 then
			table.insert(palmsAt, c)
		end
	end
	pick(palmsAt, 3 + tier * 2, 4, function(x, z)
		local lean = math.atan2(-(z - isle.cz), x - isle.cx)
		palm(m, o * CFrame.new(x, Street.SAND_Y, z), 0.9 + rng:next() * 0.3, lean)
	end)
	pick(cells[Street.SHALLOW], 3 + tier * 2, 2.5, function(x, z)
		rocks(m, o * CFrame.new(x, Street.SHALLOW_Y - 0.2, z) * CFrame.Angles(0, rng:next() * 6, 0), 0.8 + rng:next() * 0.6, rng)
	end)
	pick(cells[Street.FOAM], 2 + tier, 2, function(x, z)
		rocks(m, o * CFrame.new(x, Street.FOAM_Y - 0.25, z) * CFrame.Angles(0, rng:next() * 6, 0), 0.6 + rng:next() * 0.3, rng)
	end)
	pick(cells[Street.SAND], 6 + tier * 4, 1, function(x, z)
		shell(m, o * CFrame.new(x, Street.SAND_Y, z) * CFrame.Angles(0, rng:next() * 6, 0), rng:int(1, 3))
	end)
	pick(cells[Street.SAND], 1 + tier, 2.5, function(x, z)
		driftwood(m, o * CFrame.new(x, Street.SAND_Y, z) * CFrame.Angles(0, rng:next() * 6, 0))
	end)
	pick(cells[Street.WET], 4 + tier * 3, 1, function(x, z)
		seaweed(m, o * CFrame.new(x, Street.WET_Y, z) * CFrame.Angles(0, rng:next() * 6, 0))
	end)
	local blooms = { "pink", "yellow", "white", "purple", "berry_red" }
	pick(rim, 10 + tier * 6, 0.9, function(x, z)
		tuft(m, o * CFrame.new(x, Street.LAWN_Y, z), if rng:chance(0.45) then blooms[rng:int(1, #blooms)] else nil)
	end)
end

function StreetModels.land(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, "Land")
	local o = CFrame.new(origin)
	local b = Street.cellBounds(tier)
	local lot = Street.LOT
	-- the cells inside the lot (a neighbour's water is theirs)
	local cb = { x0 = math.max(b.x0, lot.x0), z0 = math.max(b.z0, lot.z0), x1 = math.min(b.x1, lot.x1 - 1), z1 = math.min(b.z1, lot.z1 - 1) }
	coast(m, o, cb, function(x, z)
		return Street.layer(tier, x, z)
	end, function(x, z)
		return Street.cellDist(tier, x, z)
	end)
	local rng = Util.newRng(tier * 7919 + 13)
	plaza(m, o)
	scatter(m, o, tier, cb, rng)
	-- the island's sign on its south beach (tapped: the island's card; its name floats over it)
	local sx, sz = Street.sign(tier)
	sign(m, o * CFrame.new(sx, Street.SAND_Y, sz), "island")
	Blocks.windy(m) -- palms and tufts sway, the plaza's pennant ripples
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an unclaimed plot
function StreetModels.emptyLot(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "EmptyLot")
	local o = CFrame.new(origin)
	-- a little sandbar (a wobbly oval of sand, its foam and shallows)
	local cx, cz, rx, rz = 0, 12, 6, 3.5
	local function dist(x: number, z: number): number
		local dx, dz = x + 0.5 - cx, z + 0.5 - cz
		local a = math.atan2(dz, dx)
		local er = 1 / math.sqrt((math.cos(a) / rx) ^ 2 + (math.sin(a) / rz) ^ 2)
		return math.sqrt(dx * dx + dz * dz) - er * (1 + 0.1 * math.sin(3 * a + 1)) - 0.01
	end
	local function layer(x: number, z: number): number
		local d = dist(x, z)
		-- no grass on a sandbar: what would be grass is sand
		local l = Street.layerAt(d)
		return if l == Street.GRASS then Street.SAND else l
	end
	coast(m, o, { x0 = -16, z0 = 0, x1 = 15, z1 = 24 }, layer, dist)
	palm(m, o * CFrame.new(-2.5, Street.SAND_Y, 12), 1, 2.6)
	sign(m, o * CFrame.new(1.5, Street.SAND_Y, 13.5), "empty")
	rocks(m, o * CFrame.new(5, Street.SHALLOW_Y - 0.2, 10), 0.9, Util.newRng(3))
	shell(m, o * CFrame.new(3, Street.SAND_Y, 11.5), 1)
	shell(m, o * CFrame.new(-0.5, Street.SAND_Y, 13.8), 2)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the sea's ends and the world's walls
-- The sea past the row's ends (the seabed under it as far as the walls), a sandbar with a palm beyond each wall, and
-- the invisible walls round the world.
function StreetModels.ends(parent: Instance): Model
	local m = Blocks.model(nil, "StreetEnds")
	local b = Street.bounds()
	local o = CFrame.new()
	local first = Street.origin(1) + Street.LOT.x0
	local last = Street.origin(Street.MAX) + Street.LOT.x1
	for _, e in { { b.x0, first }, { last, b.x1 } } do
		local west = e[1] == b.x0
		local x0 = if west then e[1] - Street.END_FAR else e[1]
		local x1 = if west then e[2] else e[2] + Street.END_FAR
		water(slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water"), 1)
		-- the seabed from the row's end to the world's wall
		local bx0 = if west then b.x0 else last
		local bx1 = if west then first else b.x1
		floor(m, o, bx0, Street.LOT.z0, bx1, Street.SEA.z1, Street.SEABED_Y, "Seabed")
		local hx = if west then b.x0 + 1 else b.x1 - 1
		local sx = if west then hx - 12 else hx + 12
		local function dist(x: number, z: number): number
			local dx, dz = x + 0.5 - sx, z + 0.5 - 6
			return math.sqrt((dx / 1.6) ^ 2 + dz * dz) - 3
		end
		local function layer(x: number, z: number): number
			local l = Street.layerAt(dist(x, z))
			return if l == Street.GRASS then Street.SAND else l
		end
		coast(m, o, { x0 = math.floor(sx) - 16, z0 = -8, x1 = math.floor(sx) + 15, z1 = 20 }, layer, dist)
		palm(m, o * CFrame.new(sx, Street.SAND_Y, 6), 1.2, if west then 3.1 else 0)
	end
	-- the world's outer walls
	local function outer(wx0: number, z0: number, wx1: number, z1: number)
		local w = Blocks.part(m, {
			size = Vector3.new(math.max(1, wx1 - wx0), WALL_H, math.max(1, z1 - z0)),
			cf = CFrame.new((wx0 + wx1) / 2, WALL_H / 2 - 1, (z0 + z1) / 2),
			color = "white",
			name = "Bound",
			transparency = 1,
			query = false,
		})
		w.CastShadow = false
		w.CollisionGroup = "Bounds"
	end
	outer(b.x0 - 1, b.z0 - 1, b.x1 + 1, b.z0)
	outer(b.x0 - 1, b.z1, b.x1 + 1, b.z1 + 1)
	outer(b.x0 - 1, b.z0, b.x0, b.z1)
	outer(b.x1, b.z0, b.x1 + 1, b.z1)
	m.Parent = parent
	return m
end

return StreetModels
