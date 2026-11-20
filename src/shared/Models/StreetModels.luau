--!strict
-- The floating islands from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server:
-- PlotService builds each plot's island as players come and go, and a little islet on each free plot).
--   land(parent, origin, tier)    an occupied plot: the island at its tier (Data/Street's coast), top down: the lawn in
--                                 two tones; grass hanging over the earth lip in ragged teeth; the lip, warm soil with
--                                 pale stones in it; seven rings of rock stepping in and down toward a point, each
--                                 ring's edge wobbling round the island, light warm stone at the top to dusky violet
--                                 at the bottom with dark cracks and, deep down, crystal; roots and leafy vines under
--                                 the lip, stones hanging under every ring (drips, spikes, spires with crystal tips);
--                                 tufts, flat stones and small bushes on the grass's rim, never where a building may
--                                 stand. An invisible wall just past the grass, and the island's sign on its south rim
--                                 (its board named "SignBoard"); built in chunks (landPlan, landChunk, landSign) so an
--                                 expansion changes only the chunks along the edge
--   emptyLot(parent, origin)      an unclaimed plot: a little islet built the same way, with a sign
-- The request of 2026-11-20: "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the
-- island bigger." (the sea, the beaches, the swimming and the boats went with it; UI/SkyBackdrop paints the sky), then
-- "also, detail and polish the edges and the bottom of the island more" (the teeth, the soil's stones, the wobbling
-- rings in the new cliff colours, the crystal, the vines, the hanging stones' three sizes, the rim's stones and
-- bushes). The layers are whole-stud cells merged into as few boxes as they make (greedy rectangles). Their outlines
-- are bevelled (the request of 2026-11-13: "could you bevel these to make them smoother, with rounded corners?"):
-- every notch of a layer's stairs is half filled by a flat triangle (a wedge on its side) and a square corner cut
-- back, so each edge runs straight, on a diagonal or along the grid, and turns in 45 degree steps (`bevelled`). The
-- lip and the rock are skins one cell thick on the side the view sees (`shell`). The wall and the parts that keep a
-- bevel's cut corner solid are invisible and in the "Bounds" collision group (the pixel filter's rays pass through
-- them). Nothing under the grass collides, and none of the small things do.
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
-- of them (nil: the cell is wholly its own). With `airOnly` (a shell: the lip and the rock, whose labels are colours
-- on a face, not shapes) the outline is bevelled as the whole region's, whatever the labels inside it: a notch is
-- filled with the label of a side beside it, a jutting corner cut back to nothing, and two labels meet square.
local function quarters(x: number, z: number, lab: (x: number, z: number) -> number, airOnly: boolean?): (number, { number }?)
	local l = lab(x, z)
	local n, e, s, w = lab(x, z - 1), lab(x + 1, z), lab(x, z + 1), lab(x - 1, z)
	if airOnly then
		local r = l ~= 0
		if (n ~= 0) == r and (e ~= 0) == r and (s ~= 0) == r and (w ~= 0) == r then
			return l, nil
		end
		local side = { n, e, s, w }
		local q: { number }? = nil
		for _, c in CORNER do
			local kx, kz, qa, qb = c[1], c[2], c[3], c[4]
			local ia, ib = side[qa] ~= 0, side[qb] ~= 0
			if ia == ib and ia ~= r then
				local sa, sb = SIDE[qa], SIDE[qb]
				if
					ia
					or (
						(lab(x + kx, z + kz) ~= 0) ~= r
						and (lab(x + 2 * sa[1] - kx, z + 2 * sa[2] - kz) ~= 0) ~= r
						and (lab(x + 2 * sb[1] - kx, z + 2 * sb[2] - kz) ~= 0) ~= r
					)
				then
					local t = q or { l, l, l, l }
					local fill = if ia then side[qa] else 0
					t[qa], t[qb] = fill, fill
					q = t
				end
			end
		end
		return l, q
	end
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
-- stood (out of the pixel filter's rays: "Bounds"). With `shell` (the lip and the rock under the grass) only the cells
-- that show are drawn: one whose neighbours east, south and south-east are all in the layer has no face toward the
-- view (it looks from the south-east and above: Tuning.CamYaw, CamPitch) and sits under the layers above, so it is
-- left out. That is the whole north-west side of the island and everything behind the outer face, so what is drawn is
-- a skin one cell thick round the south and east, the side the view sees.
local function bevelled(m: Instance, o: CFrame, b: Rect, lv: Level, lab: (x: number, z: number) -> number, shell: boolean?)
	local key = Street.cellKey
	local full: { [number]: { [number]: boolean } } = {}
	-- (every whole cell by label, the hidden ones of a shell too: a diagonal's big triangle may cover them)
	local own: { [number]: { [number]: boolean } } = {}
	local cut: { [number]: boolean } = {}
	local anyCut = false
	-- the half cells (a cell split on a diagonal, a label each side or one side empty) by the corner of their right
	-- angle: x, z, the corner, the label, 1 if it collides (joined into runs below)
	local halves: { { [number]: { number } } } = { {}, {}, {}, {} }
	local list: { { number } } = {}
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			local l, q = quarters(x, z, lab, shell)
			local hidden = shell and lab(x + 1, z) ~= 0 and lab(x, z + 1) ~= 0 and lab(x + 1, z + 1) ~= 0
			if q == nil then
				if l ~= 0 then
					local all = own[l] or {}
					own[l] = all
					all[key(x, z)] = true
					if not hidden then
						local set = full[l] or {}
						full[l] = set
						set[key(x, z)] = true
					end
				end
				continue
			end
			if hidden then
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
		local mine = own[label] or {}
		local i0 = 0
		while same(i0) do
			local n = 1
			while same(i0 + n) do
				-- one size bigger covers a new column (corner east) or row (corner west) of the square
				local ok = true
				for i = 0, n - 1 do
					local u, v = if kx == 1 then n else i, if kx == 1 then i else n
					if not mine[key(x + i0 + u, z + (i0 + v) * dz)] then
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

-- A length on the quarter-stud grid parts snap to (at least a quarter).
local function q(v: number): number
	return math.max(0.25, math.floor(v * 4 + 0.5) / 4)
end

-- The small things are scenery: nothing in them collides or stops a founder's feet.
local function deco(parent: Instance, at: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string): BasePart
	return Blocks.part(parent, { size = Vector3.new(w, h, d), cf = at * CFrame.new(x, y, z), color = color, name = name, collide = false })
end

local BLOOMS = { "pink", "yellow", "white", "purple", "berry_red" }

local function tuft(parent: Instance, at: CFrame, flower: string?)
	deco(parent, at, -0.1, 0.25, 0, 0.125, 0.5, 0.125, "leaf_dark", "Blade")
	deco(parent, at, 0.12, 0.2, 0.08, 0.125, 0.4, 0.125, "leaf", "Blade")
	deco(parent, at, 0, 0.3, -0.12, 0.125, 0.6, 0.125, "leaf_dark", "Blade")
	if flower then
		deco(parent, at, 0, 0.7, -0.12, 0.25, 0.25, 0.25, flower, "Bloom")
	end
end

-- A flat stone on the grass by the rim, and now and then a smaller one beside it.
local function pebble(parent: Instance, at: CFrame, h: number)
	deco(parent, at, 0, 0.125, 0, 0.75, 0.25, 0.5, if h < 0.5 then "cliff" else "cliff_dark", "Pebble")
	if h > 0.55 then
		deco(parent, at, 0.5, 0.125, 0.375, 0.5, 0.25, 0.25, "cliff", "Pebble")
	end
end

-- A small round bush on the rim: two crossed dark slabs for a body with its corners left out, a lit crown toward
-- the top left, and a flower on some.
local function bush(parent: Instance, at: CFrame, h: number, bloom: string)
	deco(parent, at, 0, 0.375, 0, 1, 0.75, 0.5, "leaf_dark", "Bush")
	deco(parent, at, 0, 0.375, 0, 0.5, 0.75, 1, "leaf_dark", "Bush")
	deco(parent, at, -0.125, 0.875, -0.125, 0.75, 0.25, 0.75, "leaf", "Bush")
	if h > 0.4 then
		deco(parent, at, 0.375, 0.625, 0.125, 0.25, 0.25, 0.25, bloom, "BushBloom")
	end
end

-- A root hanging from under the earth lip: a strand winding down in steps, a quarter stud aside at each, dark brown
-- and darker toward its tip; a long one puts out a short side root at its first bend.
local function root(parent: Instance, at: CFrame, len: number, h: number)
	local shares: { number } = if len > 2.25 then { 0.4, 0.35, 0.25 } else { 0.55, 0.45 }
	local dx = if h < 0.5 then 0.25 else -0.25
	local y, ox, oz = 0, 0, 0
	for i, share in shares do
		local seg = q(len * share)
		deco(parent, at, ox, y - seg / 2, oz, 0.25, seg, 0.25, if i == 1 then "wood_dark" else "choco_dark", "Root")
		y -= seg
		if i == 1 and #shares == 3 and h > 0.3 then
			-- the side root: out a step, then down
			deco(parent, at, ox - dx * 2, y + 0.125, oz, 0.5, 0.25, 0.25, "wood_dark", "Root")
			deco(parent, at, ox - dx * 3, y - 0.25, oz, 0.25, 0.5, 0.25, "choco_dark", "Root")
		end
		if i % 2 == 1 then
			ox += dx
		else
			oz += 0.25
		end
	end
end

-- A vine hanging from under the lip: a stem with a leaf every stud, out to one side and then the
-- other as the view sees it (along +X -Z), lit leaves on the left, darker on the right, a tuft of leaves at its end
-- and on some a flower.
local function vine(parent: Instance, at: CFrame, len: number, h: number, bloom: string)
	local L = q(len)
	deco(parent, at, 0, -L / 2, 0, 0.25, L, 0.25, "leaf_dark", "Vine")
	local side = if h < 0.5 then 1 else -1
	local y = -0.5 - (if h > 0.3 and h < 0.7 then 0.25 else 0)
	while y > -L + 0.5 do
		deco(parent, at, side * 0.375, y, -side * 0.375, 0.5, 0.25, 0.5, if side < 0 then "leaf" else "leaf_dark", "VineLeaf")
		side = -side
		y -= 1
	end
	deco(parent, at, 0, -L - 0.125, 0, 0.5, 0.5, 0.5, "leaf", "VineLeaf")
	if h > 0.45 then
		deco(parent, at, 0.125, -L - 0.5, 0.125, 0.25, 0.25, 0.25, bloom, "VineBloom")
	end
end

-- A stone hanging under a ring of rock, from `at` (the ring's underside, a cell's middle) down: blocks narrowing to a
-- point, each a quarter stud off the last. `size` 1 a drip (two blocks), 2 a spike (three), 3 a spire (three, longer
-- and wider, and on some crystals at its tip); in the ring's colours `cols` (lit, body, dark).
local function hanger(parent: Instance, at: CFrame, len: number, h: number, size: number, cols: { string })
	local m = Blocks.model(nil, "Hanger")
	local widths: { number }, shares: { number }
	if size == 1 then
		widths, shares = { 1, 0.5 }, { 0.65, 0.35 }
	elseif size == 2 then
		widths, shares = { 1.5, 1, 0.5 }, { 0.45, 0.33, 0.22 }
	else
		widths, shares = if h > 0.5 then { 2, 1, 0.5 } else { 1.5, 1, 0.5 }, { 0.42, 0.34, 0.24 }
	end
	local dx = if h < 0.5 then 0.25 else -0.25
	local y, ox, oz = 0, 0, 0
	for i, w in widths do
		local seg = q(len * shares[i])
		local col = if i == 1 then cols[1] elseif i == #widths then cols[3] else cols[2]
		deco(m, at, ox, y - seg / 2, oz, w, seg, w, col, "Stone")
		y -= seg
		if i % 2 == 1 then
			ox += dx
		else
			oz -= 0.25
		end
	end
	if size == 3 and h > 0.7 then
		-- crystals at the tip: a tall violet one and a small pale one beside it
		deco(m, at, ox, y - 0.375, oz, 0.5, 0.75, 0.5, "crystal", "Crystal")
		deco(m, at, ox + 0.375, y - 0.125, oz + 0.25, 0.25, 0.5, 0.25, "ice", "Crystal")
	end
	m.Parent = parent
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
-- A floating island from its coast distance by cell (`dist`: negative on the grass), top down (the request of
-- 2026-11-20, "also, detail and polish the edges and the bottom of the island more"):
-- * the lawn, grass in two tones (a darker rim and darker patches) over the whole grass;
-- * the grass hanging over the earth lip in teeth: under the lawn's edge, cell by cell, none, one, two or three bands
--   of grass half a stud each (`toothOf`), so the edge is ragged, never a ruled line;
-- * the earth lip, warm soil down to LIP_BOT with pale stones and redder streaks in it;
-- * the rock in RINGS, each further in and further down than the one above, so the underside narrows toward a point
--   (a small island runs out of width first: its point is shallower). Each ring's outer edge wobbles in and out round
--   the island (`cutsOf`: two slow waves and a little jitter a cell, always at least half a stud in from the ring
--   above), so the ledges are uneven. Its stone is light and warm near the top and a dusky violet at the bottom, here
--   and there a cell of a darker stone, dark cracks a cell wide and, on the two deepest rings, crystal in the stone;
-- * hanging things (`scatterIn`): roots and leafy vines under the lip, stones under every ring (drips under the upper
--   rings, spikes under the middle ones, spires under the deepest with crystals at some tips), and on the grass's rim
--   tufts, flat stones and small bushes, never where a building may stand.
-- Every outline is bevelled (`bevelled`); the lip and the rock are skins one cell thick, drawn only where the view
-- sees them (`shell`). Every height is on the quarter-stud grid parts snap to (Blocks.part).
local LAWN_H = 0.5
local LIP_TOP = Street.LAWN_Y - LAWN_H
local TOOTH_H = 0.5
local TEETH = 3
local SOIL_H = 1.5
local LIP_BOT = LIP_TOP - TEETH * TOOTH_H - SOIL_H
-- the rock's rings: inset (studs in from the grass's edge, before the wobble), height, colours (its stone, a darker
-- stone in single cells, its cracks), crystal in its stone
type Ring = { inset: number, h: number, cols: { string }, crystal: boolean, top: number, bot: number }
local RINGS: { Ring } = {
	{ inset = 1.25, h = 2, cols = { "cliff", "cliff_dark", "cliff_deep" }, crystal = false, top = 0, bot = 0 },
	{ inset = 2.75, h = 2, cols = { "cliff", "cliff_dark", "cliff_deep" }, crystal = false, top = 0, bot = 0 },
	{ inset = 4.25, h = 1.75, cols = { "cliff_dark", "cliff", "cliff_deep" }, crystal = false, top = 0, bot = 0 },
	{ inset = 5.75, h = 1.75, cols = { "cliff_dark", "cliff_deep", "cliff_base" }, crystal = false, top = 0, bot = 0 },
	{ inset = 7.5, h = 1.75, cols = { "cliff_deep", "cliff_dark", "cliff_base" }, crystal = false, top = 0, bot = 0 },
	{ inset = 9.25, h = 1.5, cols = { "cliff_deep", "cliff_base", "basalt" }, crystal = true, top = 0, bot = 0 },
	{ inset = 11.25, h = 1.5, cols = { "cliff_base", "cliff_deep", "basalt" }, crystal = true, top = 0, bot = 0 },
}
do
	local y = LIP_BOT
	for _, r in RINGS do
		r.top, r.bot = y, y - r.h
		y -= r.h
	end
end
-- the cuts a cell's rings are read by: each ring's outer edge, and the inner edge of the band its deepest stones
-- hang in
local NCUT = #RINGS + 1
StreetModels.LIP_BOT = LIP_BOT
StreetModels.BOTTOM = RINGS[#RINGS].bot

-- The rings' outer edges at cell (x, z) as coast distances (a cell at or under one is in that ring): each ring's inset
-- moved by two slow waves (up to about 0.55 studs) and a jitter (0.15 studs either way), never less than half a stud in from
-- the ring above; and last, two studs in from the deepest ring's. Plot-local, the same on every tier (the chunks'
-- signatures read them: `cellCode`).
local cutCache: { [number]: { number } } = {}
local function cutsOf(x: number, z: number): { number }
	local k0 = Street.cellKey(x, z)
	local c = cutCache[k0]
	if c then
		return c
	end
	local out = table.create(NCUT, 0)
	local prev = -0.25
	for k, r in RINGS do
		local w = math.sin(x * 0.37 + z * 0.21 + k * 1.7) * 0.6 + math.sin(x * 0.13 - z * 0.41 + k * 2.9) * 0.4
		local cut = -(r.inset + w * 0.55 + (hash01(x, z, 200 + k) - 0.5) * 0.3)
		cut = math.min(cut, prev - 0.5)
		out[k] = cut
		prev = cut
	end
	out[NCUT] = prev - 2
	cutCache[k0] = out
	return out
end

-- How many bands of grass hang over the lip at an edge cell: 0 .. TEETH, from a hash and two slow waves (runs of long
-- and short teeth).
local function toothOf(x: number, z: number): number
	local v = hash01(x, z, 11) + 0.22 * math.sin(x * 0.61 + z * 0.47) + 0.12 * math.sin(x * 0.23 - z * 0.71)
	return if v < 0.1 then 0 elseif v < 0.5 then 1 elseif v < 0.82 then 2 else 3
end

-- A cell's coast distance, kept for one build (the layers read each cell many times).
local function cached(dist: (x: number, z: number) -> number): (x: number, z: number) -> number
	local memo: { [number]: number } = {}
	local key = Street.cellKey
	return function(x: number, z: number): number
		local k = key(x, z)
		local v = memo[k]
		if v == nil then
			v = dist(x, z)
			memo[k] = v
		end
		return v
	end
end

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
	-- the grass's teeth over the lip: band j is grass where an edge cell's teeth reach it, soil elsewhere
	for j = 1, TEETH do
		bevelled(m, o, b, { top = LIP_TOP - (j - 1) * TOOTH_H, h = TOOTH_H, name = "Lip", colors = { "chocolate", "grass_dark" }, solid = false }, function(x, z)
			local d = dist(x, z)
			if d > 0 then
				return 0
			end
			return if d > -1 and toothOf(x, z) >= j then 2 else 1
		end, true)
	end
	-- the soil: pale stones and redder streaks in it
	bevelled(m, o, b, { top = LIP_TOP - TEETH * TOOTH_H, h = SOIL_H, name = "Lip", colors = { "chocolate", "cliff", "cliff_dark", "hair_brown" }, solid = false }, function(x, z)
		if dist(x, z) > 0 then
			return 0
		end
		local h = hash01(x, z, 17)
		return if h < 0.12 then 2 elseif h < 0.18 then 3 elseif patch(x, z, 3, 1.15) then 4 else 1
	end, true)
	-- the rock: each ring in its stone, with dark cracks a cell wide and, on the deepest, crystal in it
	for k, r in RINGS do
		local cols = r.cols
		bevelled(m, o, b, { top = r.top, h = r.h, name = "Rock", colors = { cols[1], cols[2], cols[3], "crystal" }, solid = false }, function(x, z)
			if dist(x, z) > cutsOf(x, z)[k] then
				return 0
			end
			local h = hash01(x, z, 300 + k)
			return if h < 0.08 then 3 elseif r.crystal and h < 0.11 then 4 elseif h < 0.2 then 2 else 1
		end, true)
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

-- The island's small things, never on a cell a building may use. Each kind is picked in its own block of the grid
-- (BLOCK cells a side, a whole number of them to a chunk's side): the block's cell with the lowest hash among those
-- the kind may use, kept when a second hash is under the kind's share, so a chunk's things depend on its own cells and
-- their neighbours alone and a part of the island an expansion leaves as it was keeps the same things in the same
-- places. The kinds: on the grass's rim (studs 0 .. 0.95 in) tufts, flat stones and bushes; on the ledge under the
-- lip (between the grass's edge and the first ring's) roots and vines; under each ring, between its edge and the
-- next ring's (the deepest: two studs in), its stones. What hangs is placed only where the view sees it: the cell
-- south-east of it is out from under the ring below as well.
type ScatterKind = { id: string, salt: number, p: number, block: number, ring: number }
local SCATTER: { ScatterKind } = {
	{ id = "tuft", salt = 79, p = 0.22, block = 2, ring = 0 },
	{ id = "pebble", salt = 83, p = 0.5, block = 4, ring = 0 },
	{ id = "bush", salt = 89, p = 0.6, block = 8, ring = 0 },
	{ id = "root", salt = 31, p = 0.35, block = 2, ring = 0 },
	{ id = "vine", salt = 37, p = 0.45, block = 4, ring = 0 },
}
for k = 1, #RINGS do
	table.insert(SCATTER, { id = "hanger", salt = 47 + k * 6, p = if k <= 3 then 0.4 elseif k == 4 then 0.5 else 0.35, block = 4, ring = k })
end

local function scatterIn(m: Instance, o: CFrame, b: Rect, dist: (x: number, z: number) -> number, sx: number?, sz: number?)
	local lawnY = Street.LAWN_Y
	-- (may a kind use cell (x, z))
	local function fits(k: ScatterKind, x: number, z: number): boolean
		local d = dist(x, z)
		if k.id == "tuft" or k.id == "pebble" or k.id == "bush" then
			return d <= 0 and d > -0.95
		elseif k.id == "root" or k.id == "vine" then
			return d <= 0 and d > cutsOf(x, z)[1] and dist(x + 1, z + 1) > cutsOf(x + 1, z + 1)[1]
		end
		local c = cutsOf(x, z)
		return d <= c[k.ring] and d > c[k.ring + 1] and dist(x + 1, z + 1) > cutsOf(x + 1, z + 1)[k.ring + 1]
	end
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
						-- (clear round the island's sign: nothing in front of it)
						if sx and sz and math.abs(x + 0.5 - sx) < 3 and math.abs(z + 0.5 - sz) < 3 then
							continue
						end
						if not fits(k, x, z) then
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
				local h3 = hash01(x, z, k.salt + 3)
				local bloom = BLOOMS[1 + math.floor(hash01(x, z, k.salt + 4) * #BLOOMS)]
				if k.id == "tuft" then
					tuft(m, o * CFrame.new(px, lawnY, pz), if h2 < 0.45 then bloom else nil)
				elseif k.id == "pebble" then
					pebble(m, o * CFrame.new(px, lawnY, pz), h2)
				elseif k.id == "bush" then
					bush(m, o * CFrame.new(px, lawnY, pz), h2, bloom)
				elseif k.id == "root" then
					root(m, o * CFrame.new(px, LIP_BOT, pz), 0.75 + h2 * 2.5, h3)
				elseif k.id == "vine" then
					vine(m, o * CFrame.new(px, LIP_BOT + 0.25, pz), 2 + h2 * 4, h3, bloom)
				else
					local r = RINGS[k.ring]
					local size = if k.ring <= 3 then 1 elseif k.ring == 4 then 2 else 3
					local len = if size == 1 then 0.75 + h2 * 0.75 elseif size == 2 then 1.75 + h2 * 2 else 3 + h2 * 4
					hanger(m, o * CFrame.new(px, r.bot, pz), len, h3, size, r.cols)
				end
			end
		end
	end
end

------------------------------------------------------------------ the land in chunks
-- The island's land is built in chunks of CHUNK x CHUNK cells (plot-local, on a grid from the plot's origin), each a
-- model of its own named for what it holds: Chunk_<cx>_<cz>_<signature>, the signature a hash of the band of the coast
-- distance (which side of every threshold the drawing compares it with it lies on: the static BANDS and the cell's
-- own ring cuts, `cutsOf`) of every cell in it and LAND_MARGIN cells round it (its bevels, its skin and what hangs
-- read two cells out), and of the sign's place when it is near. A cell further in than the deepest stones' band
-- reads the same on every tier, so an expansion changes only the chunks along the island's edge, old and new:
-- the server builds those ahead (PlotService), every client draws them ahead (the pixel filter's pre-cast), and the
-- swap moves them in (the request of 2026-11-19: "Expansion is very slow and laggy, especially at higher levels").
-- The sign is a model of its own. Splitting the ground at a chunk's edge draws no line: the pixel filter inks only
-- where the depth jumps.
StreetModels.CHUNK = 8
local LAND_MARGIN = 3

export type LandChunk = { name: string, rect: Rect }
export type LandPlan = { chunks: { LandChunk }, sign: string, walls: string }

-- The coast distances the drawing reads every cell by (the grass's edge, the rim's tones, the teeth's edge cells, the
-- rim's small things), deepest last; with each cell's own ring cuts (`cutsOf`), every threshold a cell is compared
-- with.
local BANDS: { number } = { 0, -0.9, -0.95, -1 }

-- A cell's code for the signature: 0 the open air, else 1 + how many of its thresholds its coast distance is at or
-- under (the static bands and its ring cuts: the count says which side of every one of them it is on).
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
	for _, t in cutsOf(x, z) do
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
	local dist = cached(function(x: number, z: number): number
		return Street.cellDist(tier, x, z)
	end)
	layers(m, o, c.rect, dist)
	local sx, sz = Street.sign(tier)
	scatterIn(m, o, c.rect, dist, sx, sz)
	Blocks.windy(m) -- the tufts, bushes and vines sway
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
	local dist = cached(function(x: number, z: number): number
		local dx, dz = x + 0.5 - cx, z + 0.5 - cz
		local a = math.atan2(dz, dx)
		local er = 1 / math.sqrt((math.cos(a) / rx) ^ 2 + (math.sin(a) / rz) ^ 2)
		return math.sqrt(dx * dx + dz * dz) - er * (1 + 0.1 * math.sin(3 * a + 1)) - 0.01
	end)
	local b = { x0 = cx - 10, z0 = cz - 9, x1 = cx + 9, z1 = cz + 8 }
	layers(m, o, b, dist)
	scatterIn(m, o, b, dist, 0.5, cz + 2.5)
	sign(m, o * CFrame.new(0.5, Street.LAWN_Y, cz + 2.5), "empty")
	Blocks.windy(m)
	m.Parent = parent
	return m
end

return StreetModels
