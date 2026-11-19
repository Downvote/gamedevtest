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
-- trunks are smooth curves of round segments with a ring at each joint. The sea, the shallows and the foam carry a
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
-- A palm's trunk: one smooth curve from its foot up into the crown at (tx, ty) (f's frame), leaning out from the foot
-- and coming upright under the crown. Round `Trunk` segments joined end to end, with a dark ring at each joint a little
-- wider than the bark (the scars old fronds leave), so it bends with no gap and no step; it swells a little low down
-- and narrows going up (widths on the 1/8-stud grid: an art pixel; lengths exact, so the joints meet). Its foot
-- spreads into the sand. DecorModels' Palm Tree is built the same way.
local TRUNK_W = { 1.17, 1, 1, 0.95, 0.88, 0.82, 0.77 } -- (each segment's width from the foot up, a share of w0)
local function palmTrunk(m: Instance, f: CFrame, tx: number, ty: number, w0: number)
	local n = #TRUNK_W
	local pts: { Vector3 } = {}
	for j = 0, n do
		local t = j / n
		table.insert(pts, Vector3.new(tx * (t + t * t - t * t * t), ty * t, 0))
	end
	for i = 1, n do
		local a, b = pts[i], pts[i + 1]
		local d = math.max(0.25, math.floor(w0 * TRUNK_W[i] * 8 + 0.5) / 8)
		local seg = Blocks.part(m, { size = Vector3.one, cf = f * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color = "wood", shape = "Cylinder", name = "Trunk" })
		seg.Size = Vector3.new((b - a).Magnitude, d, d) -- (exact: the joints meet)
		if i < n then
			-- (the ring: a thin round band across the joint, turned halfway between the two segments, so it closes the
			-- bend too)
			local c = pts[i + 2]
			local ring = Blocks.part(m, { size = Vector3.one, cf = f * CFrame.lookAt(b, b + (b - a).Unit + (c - b).Unit) * CFrame.Angles(0, math.pi / 2, 0), color = "wood_dark", shape = "Cylinder", name = "Trunk" })
			ring.Size = Vector3.new(0.19, d + 0.125, d + 0.125)
		end
	end
	-- the foot, spreading into the sand
	local foot = Blocks.part(m, { size = Vector3.one, cf = f * CFrame.new(0.04, -0.1, 0), color = "wood", shape = "Ball", name = "Trunk" })
	local fd = math.floor(w0 * 1.45 * 8 + 0.5) / 8
	foot.Size = Vector3.new(fd, fd, fd)
end

-- One palm frond from the crown's heart c (f's frame) out toward yaw `a` (radians about Y; 0 is +X): its midrib in
-- segments that rise, arch over and droop, each { length, pitch in degrees, width, fold }. A fold (1) is a pair of
-- leaflet blades hanging `hang` degrees either side of the midrib, the way a frond folds like a roof, swept a little
-- toward the tip so the pair's outer corners stand out (the frond's edge goes in teeth, leaflets); otherwise (0) one
-- blade: the bare stalk near the heart, the tip. Lengths and widths times s; each blade a little longer than its
-- segment so the bends close.
local SWEEP = math.rad(16)
local function frond(m: Instance, f: CFrame, c: Vector3, a: number, segs: { { number } }, s: number, hang: number, color: string)
	local dir = Vector3.new(math.cos(a), 0, -math.sin(a))
	local h = math.rad(hang)
	local p = c
	for _, sg in segs do
		local len = sg[1] * s
		local pitch = math.rad(sg[2])
		local hw = math.max(0.25, Blocks.snap(sg[3] * s))
		local q = p + dir * (math.cos(pitch) * len) + Vector3.new(0, math.sin(pitch) * len, 0)
		local cf = f * CFrame.lookAt((p + q) / 2, q)
		local L = Blocks.snap(len + 0.25)
		local size = Vector3.new(hw, 0.25, L)
		if sg[4] == 1 then
			for _, side in { 1, -1 } do
				-- (turned about the corner at the midrib's start, so the pair stays closed there)
				local cfh = cf * CFrame.new(0, 0, L / 2) * CFrame.Angles(0, 0, -side * h) * CFrame.Angles(0, side * SWEEP, 0) * CFrame.new(side * hw / 2, 0, -L / 2)
				Blocks.part(m, { size = size, cf = cfh, color = color, name = "Frond", collide = false })
			end
		else
			Blocks.part(m, { size = size, cf = cf, color = color, name = "Frond", collide = false })
		end
		p = q
	end
end

-- The fronds' shapes: two folds of leaflets and the tip. The upper ones rise and arch, the lower ones droop.
local FROND_UP = { { 1, 28, 0.5, 1 }, { 1, 0, 0.5, 1 }, { 0.75, -38, 0.5, 0 } }
local FROND_LOW = { { 0.9, 8, 0.5, 1 }, { 1, -24, 0.5, 1 }, { 0.75, -58, 0.5, 0 } }
local FROND_YOUNG = { { 0.85, 66, 0.25, 0 } }
local FROND_DEAD = { { 0.45, -40, 0.25, 0 }, { 0.9, -78, 0.5, 1 } }

-- The yaw (about f's Y, 0 along its +X) that faces the view: the camera looks from +X +Z (Tuning.CamYaw 45) and never
-- turns, so a palm keeps a gap between two fronds on that side, its coconuts and dead fronds hanging there in sight.
local function viewYaw(f: CFrame): number
	local v = f:VectorToObjectSpace(Vector3.new(1, 0, 1))
	return math.atan2(-v.Z, v.X)
end

-- A palm on the shore: the crown 1.8 studs out (at s 1, leaning toward +X after `lean`) and 5.4 up. Seven fronds round
-- the heart in two greens (the upper ones lighter), two young ones spearing up from the middle, a dead one or two
-- hanging under them, a fibrous boot where the fronds join the trunk, and a bunch of coconuts.
local function palm(parent: Instance, at: CFrame, s: number, lean: number?)
	local m = Blocks.model(nil, "Palm")
	local f = at * CFrame.Angles(0, lean or 0, 0)
	local x = 1.8 * s
	local top = 5.4 * s
	-- (a number from the palm's place: which fronds rise, its dead fronds and nuts)
	local pp = at.Position
	local hsh = (math.floor(pp.X * 3 + 0.5) * 7919 + math.floor(pp.Z * 3 + 0.5) * 104729) % 360
	palmTrunk(m, f, x, top - 0.15 * s, 0.75 * s)
	local heart = Vector3.new(x, top, 0)
	local boot = ball(m, f, x, top - 0.3 * s, 0, 0.75 * s, "hair_brown")
	boot.Name = "Boot"
	local core = ball(m, f, x, top + 0.05 * s, 0, 0.5 * s, "leaf_dark")
	core.Name = "Heart"
	core.CanCollide = false
	local va = viewYaw(f)
	local turn = ((hsh % 7) - 3) * 0.06 -- (each crown turned a little its own way, the gap still in view)
	for k = 0, 6 do
		local a = va + turn + (k + 0.5) * math.pi * 2 / 7 + (((hsh + k * 37) % 5) - 2) * 0.05
		-- (the two either side of the gap rise, so the nuts under them stay in sight)
		local up = k % 2 == 0
		local s2 = s * (0.92 + ((hsh + k * 53) % 4) * 0.05)
		frond(m, f, heart + Vector3.new(math.cos(a), 0, -math.sin(a)) * 0.15 * s, a, if up then FROND_UP else FROND_LOW, s2, if up then 28 else 36, if up then "leaf" else "leaf_dark")
	end
	-- the young fronds, still furled, spearing up
	for k = 0, 1 do
		frond(m, f, heart + Vector3.new(0, 0.1 * s, 0), va + 0.9 + k * math.pi, FROND_YOUNG, s, 0, "leaf")
	end
	-- dead fronds hanging under the crown (one or two), folded shut, their tips near the trunk
	for k = 0, if hsh % 3 == 0 then 0 else 1 do
		local a = va + (if k == 0 then 1.6 else -1.7)
		frond(m, f, heart + Vector3.new(math.cos(a) * 0.2 * s, -0.3 * s, -math.sin(a) * 0.2 * s), a, FROND_DEAD, s, 62, if k == 0 then "straw" else "wood")
	end
	-- the coconuts, green and brown, hanging in a bunch under the heart on the side in view (one behind)
	for k = 0, 3 do
		local a = va + turn + ({ -0.5, 0, 0.5, math.pi })[k + 1]
		local r = 0.48 * s
		local nut = ball(m, f, x + math.cos(a) * r, top - (if k == 1 then 0.8 else 0.6) * s, -math.sin(a) * r, 0.5, if k == 1 or k == 3 then "wood_dark" else "bamboo")
		nut.Name = "Coconut"
		nut.CanCollide = false
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

-- The plaza round the campfire: a ring of sand on the grass and in its middle the fire pit, a ring of stones of all
-- sizes (two greys, some mossy) round a bed of ash, the charcoal glowing with embers, four logs crossed with a stick
-- over them and their flames (WorldView puts a flickering flame and its smoke over the middle: `fireOn`), a kettle
-- warming on a stone at the back and a marshmallow toasting on a stick. Round it three log benches (round logs with
-- their tops planed flat, cut ends showing their rings, a knot, a cushion, a folded blanket, mugs), a stack of
-- firewood, a chopping stump with its axe, a bucket, a stump stool with a cushion on a woven mat; the flagpole on its
-- cairn with the island's pennant, and two tiki torches. The south side stays open toward the island's sign, where
-- the founder appears.
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
	-- (the sand's top here: Blocks snaps its 0.1 deep slabs to 0.25, so it stands at LAWN_Y + 0.115)
	local SAND = 0.075
	-- a part in the plaza's frame (`cf` relative to the fire's middle); the small things never collide
	local function part(cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: ("Cylinder" | "Ball")?, neon: boolean?, solid: boolean?): BasePart
		return Blocks.part(m, { size = Vector3.new(w, h, d), cf = at * cf, color = color, name = name, shape = shape, neon = neon, collide = solid == true })
	end
	-- an upright round slab (dia across, h high) centred at (x, y, z)
	local function disc(x: number, y: number, z: number, dia: number, h: number, color: string, name: string, solid: boolean?): BasePart
		return part(CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2), h, dia, dia, color, name, "Cylinder", nil, solid)
	end
	-- a round rod (a log, a stick) from a to b, dia thick, a quarter longer so it ends past both points
	local function rod(a: Vector3, b: Vector3, dia: number, color: string, name: string, solid: boolean?): BasePart
		return part(CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), (b - a).Magnitude + 0.25, dia, dia, color, name, "Cylinder", nil, solid)
	end
	-- a cut end on the rod a -> b at its b end: pale wood a step proud of the bark, a darker ring a step prouder
	local function cutEnd(a: Vector3, b: Vector3, dia: number)
		local u = (b - a).Unit
		local e = b + u * 0.125
		local spin = CFrame.Angles(0, math.pi / 2, 0)
		part(CFrame.lookAt(e - u * 0.0625, e) * spin, 0.25, dia - 0.25, dia - 0.25, "sand_dark", "LogEnd", "Cylinder")
		if dia >= 0.75 then
			part(CFrame.lookAt(e, e + u) * spin, 0.25, 0.25, 0.25, "wood", "LogRing", "Cylinder")
		end
	end

	------------------------------------------------------------------ the fire pit
	-- the bed of ash, the charcoal, the embers glowing in it
	disc(0, 0.0625, 0, 2.25, 0.25, "pavement", "Ash")
	disc(0.05, 0.125, -0.05, 1.25, 0.25, "rock_dark", "Charcoal")
	local EMBERS: { { x: number, z: number, c: string } } = {
		{ x = 0.5, z = 0.2, c = "lava" },
		{ x = -0.3, z = 0.45, c = "berry_red" },
		{ x = -0.45, z = -0.25, c = "orange" },
		{ x = 0.2, z = -0.5, c = "lava" },
		{ x = 0.55, z = -0.15, c = "berry_red" },
	}
	for _, e in EMBERS do
		part(CFrame.new(e.x, 0.25, e.z), 0.25, 0.25, 0.25, e.c, "Ember", nil, true)
	end
	-- the ring of stones: at an angle (degrees), of a kind (1 round, 2 flat and round, 3 a block), a size, a height, a
	-- grey, mossy or not
	local STONES: { { a: number, k: number, s: number, h: number, c: string, moss: boolean } } = {
		{ a = 0, k = 2, s = 0.75, h = 0.5, c = "rock", moss = true },
		{ a = 34, k = 1, s = 0.5, h = 0, c = "rock_dark", moss = false },
		{ a = 63, k = 3, s = 0.75, h = 0.5, c = "rock", moss = false },
		{ a = 96, k = 1, s = 0.75, h = 0, c = "rock", moss = false },
		{ a = 128, k = 2, s = 0.5, h = 0.5, c = "rock_dark", moss = false },
		{ a = 160, k = 3, s = 0.5, h = 0.5, c = "rock", moss = true },
		{ a = 194, k = 1, s = 0.75, h = 0, c = "rock_dark", moss = false },
		{ a = 226, k = 2, s = 0.75, h = 0.25, c = "rock", moss = false },
		{ a = 258, k = 3, s = 0.75, h = 0.5, c = "rock_dark", moss = false },
		{ a = 290, k = 1, s = 0.5, h = 0, c = "rock", moss = true },
		{ a = 323, k = 2, s = 0.75, h = 0.5, c = "rock_dark", moss = false },
	}
	for _, st in STONES do
		local a = math.rad(st.a)
		local x, z = math.cos(a) * 1.3, math.sin(a) * 1.3
		local kind, size, h, grey = st.k, st.s, st.h, st.c
		local top
		if kind == 1 then
			-- (a round stone a third sunk in the sand)
			part(CFrame.new(x, SAND + size * 0.2, z), size, size, size, grey, "FireStone", "Ball", nil, true)
			top = SAND + size * 0.7
		elseif kind == 2 then
			disc(x, SAND + h / 2 - 0.05, z, size, h, grey, "FireStone", true)
			top = SAND + h - 0.05
		else
			part(CFrame.new(x, SAND + h / 2 - 0.05, z) * CFrame.Angles(0, -a, 0.15), size, h, 0.5, grey, "FireStone", nil, nil, true)
			top = SAND + h - 0.02
		end
		if st.moss then
			if kind == 1 then
				part(CFrame.new(x * 0.97, top - 0.14, z * 0.97), 0.5, 0.5, 0.5, "moss", "Moss", "Ball")
			else
				disc(x, top - 0.0625, z, 0.5, 0.25, "moss", "Moss")
			end
		end
	end
	-- four logs crossed in the middle (an X from the view), rising a little to where they burn, their outer ends cut,
	-- and a stick across them
	for k = 0, 3 do
		local a = k * math.pi / 2
		local u = Vector3.new(math.cos(a), 0, math.sin(a))
		local foot, tip = u * 0.95 + Vector3.new(0, 0.4, 0), u * 0.1 + Vector3.new(0, 0.55, 0)
		rod(tip, foot, 0.5, if k % 2 == 0 then "wood_dark" else "hair_brown", "Log", true)
		cutEnd(tip, foot, 0.5)
	end
	rod(Vector3.new(-0.55, 0.62, 0.45), Vector3.new(0.5, 0.7, -0.4), 0.25, "wood", "Log")
	-- the flames: a glowing bed on the logs, tongues round it in yellow and red-orange showing either side of the
	-- flickering flame that stands in the middle, a hot yellow heart
	part(CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(45), 0), 0.75, 0.25, 0.75, "lava", "Flame", nil, true)
	local TONGUES: { { a: number, r: number, h: number, c: string } } = {
		{ a = 70, r = 0.38, h = 0.5, c = "yellow" },
		{ a = 160, r = 0.4, h = 0.75, c = "orange" },
		{ a = 250, r = 0.36, h = 0.5, c = "lava" },
		{ a = 340, r = 0.4, h = 0.75, c = "orange" },
		{ a = 20, r = 0.3, h = 0.5, c = "yellow" },
	}
	for _, t in TONGUES do
		local a = math.rad(t.a)
		local x, z = math.cos(a) * t.r, math.sin(a) * t.r
		part(CFrame.new(x, 0.55 + t.h / 2, z) * CFrame.Angles(z * 0.5, 0, -x * 0.5), 0.25, t.h, 0.25, t.c, "Flame", nil, true)
	end
	part(CFrame.new(0, 0.8, 0), 0.25, 0.5, 0.25, "yellow", "Flame", nil, true)
	-- a kettle warming on the flat stone at the back of the ring: its body, lid and knob, spout and handle
	do
		local ka = math.rad(226)
		local kx, kz = math.cos(ka) * 1.3, math.sin(ka) * 1.3
		local ky = SAND + 0.2 -- (the stone's top)
		disc(kx, ky + 0.25, kz, 0.5, 0.5, "black", "Kettle")
		disc(kx, ky + 0.5, kz, 0.75, 0.25, "steel_dark", "KettleLid")
		part(CFrame.new(kx, ky + 0.7, kz), 0.25, 0.25, 0.25, "steel", "KettleKnob", "Ball")
		part(CFrame.new(kx + 0.32, ky + 0.38, kz + 0.32) * CFrame.Angles(0, math.rad(-45), math.rad(35)), 0.5, 0.25, 0.25, "black", "KettleSpout")
		part(CFrame.new(kx - 0.05, ky + 0.85, kz - 0.05) * CFrame.Angles(0, math.rad(45), 0), 0.75, 0.25, 0.25, "steel_dark", "KettleHandle")
	end
	-- a stick propped on a stone on the west side (clear of the fire's front), a marshmallow toasting on it
	do
		local a = math.rad(158)
		local u = Vector3.new(math.cos(a), 0, math.sin(a))
		local base, tip = u * 2.0 + Vector3.new(0, SAND + 0.12, 0), u * 0.65 + Vector3.new(0, 0.9, 0)
		rod(base, tip, 0.25, "wood", "Stick")
		part(CFrame.lookAt(tip, tip + (tip - base)) * CFrame.new(0, 0, -0.15), 0.25, 0.25, 0.25, "cream", "Marshmallow")
	end

	------------------------------------------------------------------ the seats
	-- a log bench along its frame's X, `len` long: a round log on the sand, its top planed flat, its cut ends showing
	-- their rings, a knot and a patch of moss on its bark
	local function bench(f: CFrame, len: number)
		local function at2(x: number, y: number, z: number): Vector3
			return (f * CFrame.new(x, y, z)).Position
		end
		local ya = SAND + 0.3
		part(f * CFrame.new(0, ya, 0), len, 0.75, 0.75, "wood_dark", "Seat", "Cylinder", nil, true)
		part(f * CFrame.new(0, ya + 0.35, 0), len - 0.5, 0.25, 0.5, "wood", "SeatTop", nil, nil, true)
		for _, sx in { 1, -1 } do
			-- (cutEnd works from a rod's points, a quarter inside its ends)
			cutEnd(at2(0, ya, 0), at2(sx * (len / 2 - 0.125), ya, 0), 0.75)
		end
		part(f * CFrame.new(len * 0.2, ya + 0.05, 0.4) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.25, 0.25, "wood", "Knot", "Cylinder")
		part(f * CFrame.new(-len * 0.3, ya + 0.2, -0.3) * CFrame.Angles(0.7, 0, 0), 0.5, 0.25, 0.25, "moss", "Moss")
	end
	local west = CFrame.new(-2.75, 0, 0.5) * CFrame.Angles(0, math.pi / 2, 0)
	local east = CFrame.new(2.75, 0, 0.25) * CFrame.Angles(0, math.pi / 2, 0)
	local north = CFrame.new(0, 0, -2.75)
	bench(west, 2.25)
	bench(east, 2)
	bench(north, 2.25)
	local seat = SAND + 0.775 -- (a bench's planed top)
	-- on the benches: a folded blanket and a mug on the west one, a cushion on the north one, two mugs on the east one
	part(west * CFrame.new(-0.5, seat + 0.125, 0), 0.75, 0.25, 0.75, "berry_red", "Blanket")
	part(west * CFrame.new(-0.5, seat + 0.1875, 0), 0.25, 0.25, 1, "cream", "BlanketStripe")
	disc((west * CFrame.new(0.55, 0, 0.05)).Position.X, seat + 0.125, (west * CFrame.new(0.55, 0, 0.05)).Position.Z, 0.25, 0.25, "white", "Mug")
	part(north * CFrame.new(-0.45, seat + 0.125, 0) * CFrame.Angles(0, 0.3, 0), 0.75, 0.25, 0.5, "cherry", "Cushion")
	for _, mz in { -0.35, 0.05 } do
		local p = (east * CFrame.new(mz, 0, 0.05)).Position
		disc(p.X, seat + 0.125, p.Z, 0.25, 0.25, if mz < 0 then "blue" else "pot", "Mug")
	end
	-- a little stack of firewood north-east between two benches, its cut ends toward the view
	-- (each log: across the stack, its row, its wood)
	local WOOD: { { z: number, row: number, c: string } } = {
		{ z = -0.25, row = 0, c = "wood_dark" },
		{ z = 0.25, row = 0, c = "hair_brown" },
		{ z = 0, row = 1, c = "wood_dark" },
	}
	for _, l in WOOD do
		local z = -1.95 + l.z
		local y = SAND + 0.25 + l.row * 0.42
		local a, b = Vector3.new(1.75, y, z), Vector3.new(2.5, y, z)
		rod(a, b, 0.5, l.c, "Firewood", true)
		cutEnd(a, b, 0.5)
	end
	-- the chopping stump, north-west, its axe stuck in it
	disc(-2.05, SAND + 0.2, -2.05, 0.75, 0.5, "wood_dark", "Stump", true)
	disc(-2.05, SAND + 0.4, -2.05, 0.5, 0.25, "sand_dark", "StumpTop")
	part(CFrame.new(-2, SAND + 0.85, -2) * CFrame.Angles(0, 0.6, 0.5), 0.25, 0.75, 0.25, "wood", "AxeHandle")
	part(CFrame.new(-2.1, SAND + 0.55, -2.07) * CFrame.Angles(0, 0.6, 0), 0.25, 0.25, 0.5, "steel", "AxeHead")
	-- a tin bucket of water, south-east
	disc(2.3, SAND + 0.2, 1.95, 0.5, 0.5, "steel", "Bucket", true)
	disc(2.3, SAND + 0.375, 1.95, 0.25, 0.25, "water", "BucketWater")
	part(CFrame.new(2.3, SAND + 0.6, 1.95) * CFrame.Angles(0, 0.8, 0), 0.5, 0.25, 0.25, "steel_dark", "BucketHandle")
	-- a stump stool with a cushion, south-west, and a woven mat under it (three stripes side by side)
	-- (the bark, the cut top a little proud of it, the cushion on that: no two sides of one width overlap)
	disc(-2.2, SAND + 0.2, 2.2, 0.75, 0.5, "wood_dark", "Stool", true)
	disc(-2.2, SAND + 0.425, 2.2, 0.5, 0.25, "sand_dark", "StoolTop")
	disc(-2.2, SAND + 0.675, 2.2, 0.75, 0.25, "sofa", "StoolCushion")
	for k, col in { "straw", "berry_red", "straw" } do
		part(CFrame.new(-2.2, SAND + 0.05, 2.2) * CFrame.Angles(0, math.rad(45), 0) * CFrame.new((k - 2) * 0.25, 0, 0), 0.25, 0.25, 1.25, col, "Mat")
	end

	------------------------------------------------------------------ the flag and the torches
	-- the flagpole on a little cairn, its gold knob, the island's pennant and its mark (a step proud both sides)
	part(CFrame.new(3, 2.5, -3), 0.25, 5, 0.25, "wood_dark", "FlagPole", nil, nil, true)
	part(CFrame.new(3, 5.1, -3), 0.5, 0.5, 0.5, "gold", "PoleKnob", "Ball")
	for k, r in { { 2.7, -2.75, 0.5 }, { 3.25, -2.7, 0.5 }, { 3.05, -3.3, 0.75 } } do
		part(CFrame.new(r[1], SAND + 0.05, r[2]), r[3], r[3], r[3], if k == 2 then "rock_dark" else "rock", "Cairn", "Ball")
	end
	-- the flag itself (the request of 2026-11-17: "make the flag look like an actual flag"; it was a red slab a
	-- quarter stud thick with a white cube through it): thin cloth hung from just under the knob, from the pole's face
	-- out to the south, in four panels turned a little each way so the light picks out its folds, the free end hanging a
	-- touch lower; red with a white band through the middle. Named Pennant..., so the wind ripples it (Blocks.windy).
	local FOLD = { 0, 0.16, 0, 0.16, 0.04 } -- each fold line's step out from the cloth's plane (studs, +X)
	local PANEL = 0.42
	for k = 1, 4 do
		local a = Vector3.new(3 + FOLD[k], 4.45 - 0.035 * (k - 1), -2.875 + PANEL * (k - 1))
		local b = Vector3.new(3 + FOLD[k + 1], 4.45 - 0.035 * k, -2.875 + PANEL * k)
		local mid = (a + b) / 2
		local face = CFrame.lookAt(mid, Vector3.new(b.X, mid.Y, b.Z))
		local len = Vector2.new(b.X - a.X, b.Z - a.Z).Magnitude + 0.02 -- (a hair over, so the panels meet)
		part(face * CFrame.new(0, 0.32, 0), 0.12, 0.36, len, "berry_red", "Pennant")
		part(face, 0.12, 0.28, len, "white", "PennantBand")
		part(face * CFrame.new(0, -0.32, 0), 0.12, 0.36, len, "berry_red", "Pennant")
	end
	-- two tiki torches at the plaza's south edge: a pole bound with straw, a carved cup, a flame
	for _, tx in { -2.5, 2.5 } do
		local tf = o * CFrame.new(tx, Street.LAWN_Y, Street.PLAZA.z1 - 0.5)
		box(m, tf, 0, 0.95, 0, 0.25, 2, 0.25, "wood_dark", "TorchPole")
		for _, y in { 0.6, 1.45 } do
			Blocks.part(m, { size = Vector3.new(0.5, 0.25, 0.5), cf = tf * CFrame.new(0, y, 0), color = "straw", name = "TorchBinding", collide = false })
		end
		box(m, tf, 0, 2, 0, 0.5, 0.5, 0.5, "wood", "TorchCup")
		Blocks.part(m, { size = Vector3.new(0.75, 0.25, 0.75), cf = tf * CFrame.new(0, 2.25, 0), color = "wood_dark", name = "TorchRim", collide = false })
		Blocks.part(m, { size = Vector3.new(0.5, 0.5, 0.5), cf = tf * CFrame.new(0, 2.45, 0), color = "orange", name = "TorchFlame", neon = true, collide = false })
		Blocks.part(m, { size = Vector3.new(0.25, 0.25, 0.25), cf = tf * CFrame.new(0.03, 2.7, 0.03), color = "yellow", name = "TorchFlame", neon = true, collide = false })
	end
end

-- Things round the coast, never on a cell a building may use: palms at the grass's edge, rocks in the shallows,
-- shells and starfish on the beach, driftwood, seaweed on the wet sand, tufts and flowers on the grass's rim. Each
-- cell decides for itself from a hash of where it is (no sequence of random draws across the island), so a part of
-- the island that a bigger tier leaves as it was gets the same things in the same places: the land is built in
-- chunks and an expansion keeps every chunk that comes out the same (`StreetModels.landPlan`). A cell holds one of a
-- kind when its hash for that kind is under the kind's share and is the lowest among the kind's cells within `gap`
-- studs of it (so they never crowd).
type ScatterKind = { id: string, salt: number, p: number, gap: number }
local SCATTER: { ScatterKind } = {
	{ id = "palm", salt = 11, p = 0.16, gap = 5 },
	{ id = "rock", salt = 23, p = 0.045, gap = 5 },
	{ id = "foamrock", salt = 37, p = 0.05, gap = 4 },
	{ id = "shell", salt = 41, p = 0.09, gap = 2 },
	{ id = "drift", salt = 53, p = 0.02, gap = 5 },
	{ id = "weed", salt = 67, p = 0.16, gap = 2 },
	{ id = "tuft", salt = 79, p = 0.4, gap = 1.8 },
}
local SCATTER_REACH = 5 -- the widest gap: how far round a cell its things depend on the cells

-- A number in [0, 1) from a cell and a salt, the same every time (no random state).
local function hash01(x: number, z: number, salt: number): number
	local h = (x * 73856093 + z * 19349663 + salt * 83492791) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 13))
	local lo, hi = h % 65536, h // 65536
	h = (lo * 1274126177 + ((hi * 1274126177) % 65536) * 65536) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Whether cell (x, z) of the tier's island may hold one of kind k (its layer and coast distance; never by the sign).
local function scatterOk(k: ScatterKind, tier: number, x: number, z: number, sx: number, sz: number): boolean
	local cx, cz = x + 0.5 - sx, z + 0.5 - sz
	-- (clear round the island's sign, wide: no palm leans in front of it)
	if (math.abs(cx) < 3 and math.abs(cz) < 2.5) or cx * cx + cz * cz < (5 + k.gap / 2) ^ 2 then
		return false
	end
	local l = Street.layer(tier, x, z)
	local id = k.id
	if id == "palm" then
		return l == Street.SAND and Street.cellDist(tier, x, z) < 1.2
	elseif id == "rock" then
		return l == Street.SHALLOW
	elseif id == "foamrock" then
		return l == Street.FOAM
	elseif id == "shell" or id == "drift" then
		return l == Street.SAND
	elseif id == "weed" then
		return l == Street.WET
	end
	return l == Street.GRASS and not Street.buildable(tier, x, z)
end

-- The way out to sea from cell (x, z) (radians, as a palm leans): down the layers round it, grass to sea.
local SEA_RANK = { [Street.GRASS] = 5, [Street.SAND] = 4, [Street.WET] = 3, [Street.FOAM] = 2, [Street.SHALLOW] = 1 }
local function seaward(tier: number, x: number, z: number): number
	local gx, gz = 0, 0
	for dz = -1, 1 do
		for dx = -1, 1 do
			local r = SEA_RANK[Street.layer(tier, x + dx, z + dz)] or 0
			gx -= r * dx
			gz -= r * dz
		end
	end
	if gx == 0 and gz == 0 then
		return hash01(x, z, 5) * math.pi * 2
	end
	return math.atan2(-gz, gx)
end

-- The coast's things on the cells of rect b (whole studs, plot-local), from the cells round it too.
local function scatterIn(m: Instance, o: CFrame, tier: number, b: Rect)
	local sx, sz = Street.sign(tier)
	local key = Street.cellKey
	local blooms = { "pink", "yellow", "white", "purple", "berry_red" }
	for _, k in SCATTER do
		local g = math.ceil(k.gap)
		local cand: { [number]: number } = {}
		for z = b.z0 - g, b.z1 + g do
			for x = b.x0 - g, b.x1 + g do
				local h = hash01(x, z, k.salt)
				if h < k.p and scatterOk(k, tier, x, z, sx, sz) then
					cand[key(x, z)] = h
				end
			end
		end
		local g2 = k.gap * k.gap
		for z = b.z0, b.z1 do
			for x = b.x0, b.x1 do
				local h = cand[key(x, z)]
				if h == nil then
					continue
				end
				local lowest = true
				for dz = -g, g do
					for dx = -g, g do
						if (dx ~= 0 or dz ~= 0) and dx * dx + dz * dz < g2 then
							local other = cand[key(x + dx, z + dz)]
							if other and (other < h or (other == h and (dz < 0 or (dz == 0 and dx < 0)))) then
								lowest = false
							end
						end
					end
				end
				if not lowest then
					continue
				end
				local px, pz = x + 0.5, z + 0.5
				local turn = hash01(x, z, k.salt + 1) * 6
				local id = k.id
				if id == "palm" then
					palm(m, o * CFrame.new(px, Street.SAND_Y, pz), 0.9 + hash01(x, z, k.salt + 2) * 0.3, seaward(tier, x, z))
				elseif id == "rock" then
					rocks(m, o * CFrame.new(px, Street.SHALLOW_Y - 0.2, pz) * CFrame.Angles(0, turn, 0), 0.8 + hash01(x, z, k.salt + 2) * 0.6, Util.newRng(math.floor(hash01(x, z, k.salt + 3) * 2147483647)))
				elseif id == "foamrock" then
					rocks(m, o * CFrame.new(px, Street.FOAM_Y - 0.25, pz) * CFrame.Angles(0, turn, 0), 0.6 + hash01(x, z, k.salt + 2) * 0.3, Util.newRng(math.floor(hash01(x, z, k.salt + 3) * 2147483647)))
				elseif id == "shell" then
					shell(m, o * CFrame.new(px, Street.SAND_Y, pz) * CFrame.Angles(0, turn, 0), 1 + math.floor(hash01(x, z, k.salt + 2) * 3))
				elseif id == "drift" then
					driftwood(m, o * CFrame.new(px, Street.SAND_Y, pz) * CFrame.Angles(0, turn, 0))
				elseif id == "weed" then
					seaweed(m, o * CFrame.new(px, Street.WET_Y, pz) * CFrame.Angles(0, turn, 0))
				else
					local bloom = if hash01(x, z, k.salt + 2) < 0.45 then blooms[1 + math.floor(hash01(x, z, k.salt + 3) * #blooms)] else nil
					tuft(m, o * CFrame.new(px, Street.LAWN_Y, pz), bloom)
				end
			end
		end
	end
end

------------------------------------------------------------------ the land in chunks
-- The island's land is built in chunks of CHUNK x CHUNK cells (plot-local, on a grid from the plot's origin), each a
-- model of its own named for what it holds: Chunk_<cx>_<cz>_<signature>, the signature a hash of the layer and
-- coast-distance band of every cell in it and LAND_MARGIN cells round it (all its bevels, tones and scatter read), and
-- of the sign's place when it is near. A bigger tier leaves most of the island as it was (Street.coast: an island only
-- gains land), so most of its chunks come out with the same names, and the server keeps those (PlotService.build): an
-- expansion builds, sends and re-draws only the chunks that changed (the request of 2026-11-19: "Expansion is very
-- slow and laggy, especially at higher levels. Is it possible to optimize and speed it up?"). The plaza and the sign
-- are children of their own. Splitting the ground at a chunk's edge draws no line: the pixel filter inks only where
-- the depth jumps.
StreetModels.CHUNK = 16
local LAND_MARGIN = SCATTER_REACH + 1

export type LandChunk = { name: string, rect: Rect }
export type LandPlan = { chunks: { LandChunk }, sign: string }

-- A cell's code for the signature: 0 the open sea, else its layer and which side of the coast distances read it is.
local function cellCode(tier: number, x: number, z: number): number
	local l = Street.layer(tier, x, z)
	if l == Street.SEA_CELL then
		return 0
	end
	local d = Street.cellDist(tier, x, z)
	return l * 8 + (if d <= -1 then 1 else 0) + (if d > -0.9 then 2 else 0) + (if d < 1.2 then 4 else 0)
end

-- The lot's cells (a neighbour's water is theirs).
local function lotCells(): Rect
	local lot = Street.LOT
	return { x0 = math.ceil(lot.x0), z0 = math.ceil(lot.z0), x1 = math.floor(lot.x1) - 1, z1 = math.floor(lot.z1) - 1 }
end

-- The island's sign's name at a tier (by its place on the south beach).
function StreetModels.signName(tier: number): string
	local sx, sz = Street.sign(tier)
	return string.format("Sign_%d_%d", math.floor(sx * 2), math.floor(sz * 2))
end

-- The island's chunks at a tier (those with any of it in them), named for what they hold, and its sign's name.
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
			if sx > r.x0 - M - 8 and sx < r.x1 + M + 8 and sz > r.z0 - M - 8 and sz < r.z1 + M + 8 then
				h1 = (h1 * 31 + math.floor(sx * 2) + 4096) % P1
				h2 = (h2 * 37 + math.floor(sz * 2) + 4096) % P2
			end
			table.insert(out, { name = string.format("Chunk_%d_%d_%07x%07x", cx, cz, h1, h2), rect = r })
		end
	end
	return { chunks = out, sign = StreetModels.signName(tier) }
end

-- One chunk of the tier's land (StreetModels.landPlan's): its coast and the coast's things, into parent.
function StreetModels.landChunk(parent: Instance, origin: Vector3, tier: number, c: LandChunk): Model
	local m = Blocks.model(nil, c.name)
	local o = CFrame.new(origin)
	coast(m, o, c.rect, function(x, z)
		return Street.layer(tier, x, z)
	end, function(x, z)
		return Street.cellDist(tier, x, z)
	end)
	scatterIn(m, o, tier, c.rect)
	Blocks.windy(m) -- palms and tufts sway
	m.Parent = parent
	return m
end

-- The plaza round the campfire (the same on every tier).
function StreetModels.landPlaza(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Plaza")
	plaza(m, CFrame.new(origin))
	Blocks.windy(m) -- the plaza's pennant ripples
	m.Parent = parent
	return m
end

-- The island's sign on its south beach (tapped: the island's card; its name floats over it), named by its place.
function StreetModels.landSign(parent: Instance, origin: Vector3, tier: number): Model
	local sx, sz = Street.sign(tier)
	local m = Blocks.model(nil, StreetModels.signName(tier))
	sign(m, CFrame.new(origin) * CFrame.new(sx, Street.SAND_Y, sz), "island")
	m.Parent = parent
	return m
end

-- The whole island at a tier: every chunk of its land, the plaza and the sign, under one model "Land".
function StreetModels.land(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, "Land")
	for _, c in StreetModels.landPlan(tier).chunks do
		StreetModels.landChunk(m, origin, tier, c)
	end
	StreetModels.landPlaza(m, origin)
	StreetModels.landSign(m, origin, tier)
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
