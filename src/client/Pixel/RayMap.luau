--!strict
--!native
-- Which static parts the pixel rays can meet, block by block (docs/ARCHITECTURE.md 11.6). For every 2x2 block of the
-- global art grid in a window round the island in view it keeps the part that can come nearest the camera there, how
-- near, and how near the next one can come, so PixelRenderer can skip rays it already knows the answer to (the request
-- of 2026-11-21, "Cast fewer main rays"):
--   * a block no part reaches is sky: its pixels need no ray at all;
--   * a pixel whose 2x2 anchors all met the same flat face of one of its block's two nearest parts, where no other part
--     of the block can come as near as that face is at the pixel (the other of the two may, if the pixel's own ray
--     misses its box: PixelRenderer tests that), shows that face too, at the depth between the anchors' (a part's face
--     is convex, so the pixel's ray crosses it inside the face, and nothing else is in front). The parts under a lawn
--     reach its blocks on the screen but stay behind it, so the lawn is answered all the same.
-- A part's outline is its box's eight corners projected onto the grid, the hexagon round them grown by MARGIN_FLAT art
-- px for a block or a wedge, MARGIN_ROUND for any other shape;
-- a block counts it when the outline reaches the square its four pixel centres span (a ray goes through a pixel's
-- centre: Raster.origin). How near it comes over a row of blocks is the least depth (along the view, from the ray
-- plane, as PixelRenderer's depths are) of its box between the row's top and bottom (grown the same), less NEAR_EPS,
-- in 1/32 studs rounded down. The parts under the watched root count whatever they look like (see-through, hidden,
-- CanQuery off: more counted is only fewer rays saved); the invisible walls ("Bounds", "StagedBounds") do not, no
-- pixel ray meets them (PlotService). Nothing else is there for the rays to meet: PixelRenderer's filter keeps out the
-- moving models and the founders, and the next island waits in a collision group no pixel ray meets.
-- The map is kept in chunks of CB x CB blocks, each with the list of the parts that reach it (a block names its two
-- nearest parts by their places in that list) and five u16 a block: 10 bytes a block, about 5 MB over a whole top-tier
-- island at the default View. A part that comes adds itself to the blocks it reaches; one that goes leaves the chunks it reached
-- to be worked out again from the parts still listed there (its outline worked out once more: a static part does not
-- move), and the map is not ready meanwhile, so it answers nothing.
--   RayMap.new(marginFlat, marginRound)  a map of its own (the camera's, the sun's), with the API below
--   map.watch(root)                      follow the parts under root (workspace.Plots) as they come and go
--   map.setView(rot12, q, phX, phY, l0, x0, y0, x1, y1)  the grid (Raster.gridPoint's), the ray plane (the depth
--                                        of a point is its distance along the view past l0) and the window (global art
--                                        px, inclusive) to keep; a change starts the map again
--   map.step(deadline, clock): boolean  work until clock() passes the deadline; true when anything was done
--   map.ready(): boolean              whether every part is in for the current view
--   map.at(gx, gy): (p1, p2, d2, d3, flat1, flat2, d1)  for the block holding global px (gx, gy): its nearest part p1
--                                        (false when no part reaches it, the sky; nil when nothing can be said: outside
--                                        the window, the map not ready), the next nearest p2 (nil: none), how near p2
--                                        and the third come (studs; math.huge when there is none), and whether p1 and
--                                        p2 have flat faces (a block or a wedge, not part of a model lit smooth:
--                                        Pixel/SmoothParts), and how near p1 comes
--   map.skyTo(gx, gy, gx1): number     the last global x in gx .. gx1 on row gy up to which every block is sky (gx - 1
--                                        when gx's block is not, or nothing can be said): runs of sky filled at once, no
--                                        pixel looked at one by one (the request of 2026-11-23, "a deeper rework of the
--                                        renderer")
--   map.debugState()                  parts, chunks, queued, ready
local SmoothParts = require(script.Parent.SmoothParts)

local RayMap = {}

export type Map = {
	onAdd: ((p: BasePart) -> any)?, -- (called with each part the map takes in)
	watch: (r: Instance) -> (),
	setView: (rot12: { number }, q: number, phX: number, phY: number, l0: number, x0: number, y0: number, x1: number, y1: number) -> (),
	step: (deadline: number, clock: () -> number) -> boolean,
	ready: () -> boolean,
	at: (gx: number, gy: number) -> (BasePart | false | nil, BasePart?, number, number, boolean, boolean, number),
	skyTo: (gx: number, gy: number, gx1: number) -> number,
	debugState: () -> { parts: number, chunks: number, queued: number, ready: boolean },
}

local CB = 32 -- blocks along a chunk's side (64 art px)
local NEAR_EPS = 0.02 -- studs taken off how near a part comes (the rays' rounding)
local DQ = 32 -- depth steps a stud
local NONE = 65535

type Chunk = {
	k: buffer, -- u16 a block: the nearest part's place in `parts` (0: none)
	k2: buffer, -- u16 a block: the next nearest part's place (0: none)
	d1: buffer, -- u16 a block: how near the nearest comes (1/32 studs; NONE: no part)
	d2: buffer, -- u16 a block: how near the next one comes
	d3: buffer, -- u16 a block: how near the third comes
	parts: { BasePart }, -- the parts that reach the chunk
	flat: { boolean }, -- whether each has flat faces
}

-- The zonogon (the outline of a box's three axes added up) round centre (cx, cy) with the half axes (ax, ay), (bx, by),
-- (ex, ey), into xs, ys: its six corners counter-clockwise.
local function zono(xs: { number }, ys: { number }, cx: number, cy: number, ax: number, ay: number, bx: number, by: number, ex: number, ey: number)
	-- (each axis turned to point down, or right when level, then in order of angle: the outline walks each in turn)
	if ay < 0 or (ay == 0 and ax < 0) then
		ax, ay = -ax, -ay
	end
	if by < 0 or (by == 0 and bx < 0) then
		bx, by = -bx, -by
	end
	if ey < 0 or (ey == 0 and ex < 0) then
		ex, ey = -ex, -ey
	end
	local aa, ab, ae = math.atan2(ay, ax), math.atan2(by, bx), math.atan2(ey, ex)
	if aa > ab then
		ax, ay, bx, by, aa, ab = bx, by, ax, ay, ab, aa
	end
	if ab > ae then
		bx, by, ex, ey, ab, ae = ex, ey, bx, by, ae, ab
	end
	if aa > ab then
		ax, ay, bx, by = bx, by, ax, ay
	end
	local px, py = cx - ax - bx - ex, cy - ay - by - ey
	xs[1], ys[1] = px, py
	px, py = px + 2 * ax, py + 2 * ay
	xs[2], ys[2] = px, py
	px, py = px + 2 * bx, py + 2 * by
	xs[3], ys[3] = px, py
	px, py = px + 2 * ex, py + 2 * ey
	xs[4], ys[4] = px, py
	px, py = px - 2 * ax, py - 2 * ay
	xs[5], ys[5] = px, py
	px, py = px - 2 * bx, py - 2 * by
	xs[6], ys[6] = px, py
end

-- The x range of a zonogon (xs, ys) between rows ya and yb (math.huge, -math.huge when it misses them).
local function slab(xs: { number }, ys: { number }, ya: number, yb: number): (number, number)
	local xa, xb = math.huge, -math.huge
	for i = 1, 6 do
		local j = if i == 6 then 1 else i + 1
		local x1, y1, x2, y2 = xs[i], ys[i], xs[j], ys[j]
		if math.max(y1, y2) >= ya and math.min(y1, y2) <= yb then
			if y1 == y2 then
				xa, xb = math.min(xa, x1, x2), math.max(xb, x1, x2)
			else
				local d = y2 - y1
				local t0, t1 = (ya - y1) / d, (yb - y1) / d
				if t0 > t1 then
					t0, t1 = t1, t0
				end
				t0, t1 = math.max(0, t0), math.min(1, t1)
				local xs0, xe = x1 + (x2 - x1) * t0, x1 + (x2 - x1) * t1
				xa, xb = math.min(xa, xs0, xe), math.max(xb, xs0, xe)
			end
		end
	end
	return xa, xb
end

-- A map of its own: an outline grows by marginFlat art px for a block or a wedge and marginRound for any other shape
-- (the camera's map: a block's or a wedge's edge is where Roblox's ray meets it to a few thousandths of a pixel, a round
-- part's single-precision test can stray a hair past its edge, Pixel/BakeCast; the sun's map: half a block and more,
-- since its rays start anywhere in a block, not at a pixel's centre).
function RayMap.new(marginFlat: number, marginRound: number): Map
	local MARGIN_FLAT, MARGIN_ROUND = marginFlat, marginRound
	local MARGIN = MARGIN_ROUND
	local M = {}
	local chunks: { [number]: Chunk } = {}
	local chunkN = 0
	local dirty: { [number]: boolean } = {}
	local dirtyN = 0
	local partN = 0
	local addQ: { BasePart } = {}
	local addSet: { [BasePart]: boolean } = {}
	local remQ: { BasePart } = {}
	local remSet: { [BasePart]: boolean } = {}
	local addHead, remHead = 1, 1
	local root: Instance? = nil
	local rot: { number }? = nil
	local gq, gphX, gphY, gl0 = 1, 0, 0, 0
	local wx0, wy0, wx1, wy1 = 0, 0, -1, -1 -- the window in blocks (inclusive)
	local viewKey = ""

	-- (the outline on the grid, x and y; the box against the screen's rows, depth and y)
	local hx: { number } = table.create(6, 0)
	local hy: { number } = table.create(6, 0)
	local dx: { number } = table.create(6, 0)
	local dy: { number } = table.create(6, 0)

	-- Part p's outline into hx, hy and its depth by row into dx (depth), dy (row), grown by `margin` (MARGIN, for rowOf);
	-- the block rows r0 .. r1 it reaches in the window (r0 > r1: none).
	local function outline(p: BasePart, margin: number): (number, number)
		MARGIN = margin
		local R = rot :: { number }
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
		local size = p.Size
		local a4, a7, a10 = R[4] * gq, R[7] * gq, R[10] * gq
		local b5, b8, b11 = -R[5] * gq, -R[8] * gq, -R[11] * gq
		local l6, l9, l12 = -R[6], -R[9], -R[12]
		local cx = gphX + x * a4 + y * a7 + z * a10
		local cy = gphY + x * b5 + y * b8 + z * b11
		local cd = x * l6 + y * l9 + z * l12 - gl0
		local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
		-- the box's half axes: on the grid, and in depth
		local ux, uy, ud = (r00 * a4 + r10 * a7 + r20 * a10) * sx, (r00 * b5 + r10 * b8 + r20 * b11) * sx, (r00 * l6 + r10 * l9 + r20 * l12) * sx
		local vx, vy, vd = (r01 * a4 + r11 * a7 + r21 * a10) * sy, (r01 * b5 + r11 * b8 + r21 * b11) * sy, (r01 * l6 + r11 * l9 + r21 * l12) * sy
		local wx, wy, wd = (r02 * a4 + r12 * a7 + r22 * a10) * sz, (r02 * b5 + r12 * b8 + r22 * b11) * sz, (r02 * l6 + r12 * l9 + r22 * l12) * sz
		zono(hx, hy, cx, cy, ux, uy, vx, vy, wx, wy)
		zono(dx, dy, cd, cy, ud, uy, vd, vy, wd, wy)
		local ex = math.abs(ux) + math.abs(vx) + math.abs(wx)
		local ey = math.abs(uy) + math.abs(vy) + math.abs(wy)
		if math.floor((cx + ex + MARGIN - 0.5) / 2) < wx0 or math.ceil((cx - ex - MARGIN - 1.5) / 2) > wx1 then
			return 1, 0
		end
		-- (block row r: centres at 2r + 0.5 and 2r + 1.5)
		return math.max(wy0, math.ceil((cy - ey - MARGIN - 1.5) / 2)), math.min(wy1, math.floor((cy + ey + MARGIN - 0.5) / 2))
	end

	-- The block columns the outline reaches in block row r (c0 > c1: none) and how near the box comes there (1/32 studs).
	local function rowOf(r: number): (number, number, number)
		local ya, yb = 2 * r + 0.5 - MARGIN, 2 * r + 1.5 + MARGIN
		local xa, xb = slab(hx, hy, ya, yb)
		local c0 = math.max(wx0, math.ceil((xa - MARGIN - 1.5) / 2))
		local c1 = math.min(wx1, math.floor((xb + MARGIN - 0.5) / 2))
		if c0 > c1 then
			return 1, 0, 0
		end
		local dmin = slab(dx, dy, ya, yb)
		return c0, c1, math.clamp(math.floor((dmin - NEAR_EPS) * DQ), 0, NONE - 1)
	end

	local function chunkAt(ck: number): Chunk
		local c = chunks[ck]
		if c then
			return c
		end
		local d1, d2, d3 = buffer.create(CB * CB * 2), buffer.create(CB * CB * 2), buffer.create(CB * CB * 2)
		buffer.fill(d1, 0, 255)
		buffer.fill(d2, 0, 255)
		buffer.fill(d3, 0, 255)
		local nc: Chunk = { k = buffer.create(CB * CB * 2), k2 = buffer.create(CB * CB * 2), d1 = d1, d2 = d2, d3 = d3, parts = {}, flat = {} }
		chunks[ck] = nc
		chunkN += 1
		return nc
	end

	-- Put the part at place k of chunk c into the chunk's blocks of row r, columns c0 .. c1 (the chunk at block (bx0, by0)).
	local function put(c: Chunk, k: number, near: number, r: number, c0: number, c1: number, bx0: number, by0: number)
		local kb, kb2, b1, b2, b3 = c.k, c.k2, c.d1, c.d2, c.d3
		local base = (r - by0) * CB - bx0
		for col = c0, c1 do
			local i = (base + col) * 2
			local o1 = buffer.readu16(b1, i)
			if near < o1 then
				buffer.writeu16(b3, i, buffer.readu16(b2, i))
				buffer.writeu16(b2, i, o1)
				buffer.writeu16(kb2, i, buffer.readu16(kb, i))
				buffer.writeu16(b1, i, near)
				buffer.writeu16(kb, i, k)
			else
				local o2 = buffer.readu16(b2, i)
				if near < o2 then
					buffer.writeu16(b3, i, o2)
					buffer.writeu16(b2, i, near)
					buffer.writeu16(kb2, i, k)
				elseif near < buffer.readu16(b3, i) then
					buffer.writeu16(b3, i, near)
				end
			end
		end
	end

	-- (a block or a wedge: no two faces a ray can see share a normal index (Render/Shading.normalIndex), they stand at
	-- least a right angle apart. Not a corner wedge: its two slopes can be nearly level and meet in a ridge.)
	local function isFlat(p: BasePart): boolean
		local shaped = p:IsA("WedgePart") or (p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Block)
		return shaped and SmoothParts.model(p) == nil
	end

	local function counts(p: BasePart): boolean
		local g = p.CollisionGroup
		return g ~= "Bounds" and g ~= "StagedBounds"
	end

	-- Add part p to every block it reaches (listed in each chunk it reaches).
	local function add(p: BasePart)
		if not counts(p) then
			return
		end
		local hook = (M :: any).onAdd
		if hook then
			hook(p)
		end
		local flat = isFlat(p)
		local r0, r1 = outline(p, if flat then MARGIN_FLAT else MARGIN_ROUND)
		local placed: { [number]: number } = {} -- chunk -> the part's place in its list
		for r = r0, r1 do
			local c0, c1, near = rowOf(r)
			local cy = r // CB
			local col = c0
			while col <= c1 do
				local cx = col // CB
				local ce = math.min(c1, cx * CB + CB - 1)
				local ck = (cx + 32768) * 65536 + (cy + 32768)
				local c = chunkAt(ck)
				local k = placed[ck]
				if k == nil then
					table.insert(c.parts, p)
					k = #c.parts
					c.flat[k :: number] = flat
					placed[ck] = k :: number
				end
				put(c, k :: number, near, r, col, ce, cx * CB, cy * CB)
				col = ce + 1
			end
		end
		if next(placed) then
			partN += 1
		end
	end

	-- Take part p off the map: the chunks it was listed in are worked out again (RayMap.step).
	local function remove(p: BasePart)
		if not counts(p) then
			return
		end
		-- (looked for in every chunk the wider outline reaches: a part that left its model may no longer read as it did)
		local r0, r1 = outline(p, MARGIN_ROUND)
		local found = false
		local seen: { [number]: boolean } = {}
		for r = r0, r1 do
			local c0, c1 = rowOf(r)
			if c0 <= c1 then
				local cy = r // CB
				for cx = c0 // CB, c1 // CB do
					local ck = (cx + 32768) * 65536 + (cy + 32768)
					if not seen[ck] then
						seen[ck] = true
						local c = chunks[ck]
						if c then
							local list, flats = c.parts, c.flat
							for i = #list, 1, -1 do
								if list[i] == p then
									-- (the last one takes its place: the chunk is worked out again, so its blocks' places with it)
									local n = #list
									list[i], flats[i] = list[n], flats[n]
									list[n] = nil :: any
									flats[n] = nil :: any
									found = true
									if not dirty[ck] then
										dirty[ck] = true
										dirtyN += 1
									end
									break
								end
							end
						end
					end
				end
			end
		end
		if found then
			partN -= 1
		end
	end

	-- Work chunk ck out again from the parts still listed in it (none: the chunk goes, all sky).
	local function redo(ck: number)
		local c = chunks[ck]
		if c == nil then
			return
		end
		if #c.parts == 0 then
			chunks[ck] = nil
			chunkN -= 1
			return
		end
		buffer.fill(c.k, 0, 0)
		buffer.fill(c.k2, 0, 0)
		buffer.fill(c.d1, 0, 255)
		buffer.fill(c.d2, 0, 255)
		buffer.fill(c.d3, 0, 255)
		local cx, cy = ck // 65536 - 32768, ck % 65536 - 32768
		local bx0, by0 = cx * CB, cy * CB
		for k, p in c.parts do
			local r0, r1 = outline(p, if c.flat[k] then MARGIN_FLAT else MARGIN_ROUND)
			for r = math.max(r0, by0), math.min(r1, by0 + CB - 1) do
				local c0, c1, near = rowOf(r)
				c0, c1 = math.max(c0, bx0), math.min(c1, bx0 + CB - 1)
				if c0 <= c1 then
					put(c, k, near, r, c0, c1, bx0, by0)
				end
			end
		end
	end

	-- Start the map again: every part under the root queued.
	local function restart()
		table.clear(chunks)
		chunkN = 0
		table.clear(dirty)
		dirtyN = 0
		partN = 0
		addQ, remQ = {}, {}
		table.clear(addSet)
		table.clear(remSet)
		addHead, remHead = 1, 1
		local r = root
		if r then
			for _, d in r:GetDescendants() do
				if d:IsA("BasePart") then
					addSet[d] = true
					table.insert(addQ, d)
				end
			end
		end
	end

	function M.watch(r: Instance)
		root = r
		r.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("BasePart") and not addSet[d] then
				addSet[d] = true
				table.insert(addQ, d)
			end
		end)
		r.DescendantRemoving:Connect(function(d: Instance)
			if d:IsA("BasePart") and not remSet[d] then
				remSet[d] = true
				table.insert(remQ, d)
			end
		end)
		if rot then
			restart()
		end
	end

	function M.setView(rot12: { number }, q: number, phX: number, phY: number, l0: number, x0: number, y0: number, x1: number, y1: number)
		local bx0, by0 = math.floor(x0 / 2), math.floor(y0 / 2)
		local bx1, by1 = math.floor(x1 / 2), math.floor(y1 / 2)
		local key = string.format("%.6f|%.6f|%.6f|%.4f|%d|%d|%d|%d", q, phX, phY, l0, bx0, by0, bx1, by1)
		if key == viewKey and rot then
			-- (the same turn of the view, whatever table holds it: a map starts again only when it must)
			local same = true
			for i = 4, 12 do
				if math.abs((rot :: { number })[i] - rot12[i]) > 1e-9 then
					same = false
					break
				end
			end
			if same then
				return
			end
		end
		viewKey = key
		rot = rot12
		gq, gphX, gphY, gl0 = q, phX, phY, l0
		wx0, wy0, wx1, wy1 = bx0, by0, bx1, by1
		restart()
	end

	function M.step(deadline: number, clock: () -> number): boolean
		if rot == nil or (remHead > #remQ and addHead > #addQ and dirtyN == 0) then
			return false
		end
		local r = root
		local n = 0
		-- the parts that went first (one that went and came back is taken off, then put on again below)
		while remHead <= #remQ do
			n += 1
			if n % 8 == 0 and clock() > deadline then
				return true
			end
			local p = remQ[remHead]
			remQ[remHead] = nil :: any
			remHead += 1
			remSet[p] = nil
			remove(p)
		end
		remQ, remHead = {}, 1
		while addHead <= #addQ do
			n += 1
			if n % 8 == 0 and clock() > deadline then
				return true
			end
			local p = addQ[addHead]
			addQ[addHead] = nil :: any
			addHead += 1
			addSet[p] = nil
			if r and p:IsDescendantOf(r) then
				add(p)
			end
		end
		addQ, addHead = {}, 1
		-- (the chunks the parts that went had reached, worked out again)
		for ck in dirty do
			if clock() > deadline then
				return true
			end
			dirty[ck] = nil
			dirtyN -= 1
			redo(ck)
		end
		return true
	end

	function M.ready(): boolean
		return rot ~= nil and root ~= nil and remHead > #remQ and addHead > #addQ and dirtyN == 0
	end

	function M.at(gx: number, gy: number): (BasePart | false | nil, BasePart?, number, number, boolean, boolean, number)
		-- (nothing is known before the root is watched: an empty map would call every block sky)
		if rot == nil or root == nil or remHead <= #remQ or addHead <= #addQ or dirtyN > 0 then
			return nil, nil, 0, 0, false, false, 0
		end
		local bx, by = gx // 2, gy // 2
		if bx < wx0 or bx > wx1 or by < wy0 or by > wy1 then
			return nil, nil, 0, 0, false, false, 0
		end
		local cx, cy = bx // CB, by // CB
		local c = chunks[(cx + 32768) * 65536 + (cy + 32768)]
		if c == nil then
			return false, nil, 0, 0, false, false, 0
		end
		local i = ((by - cy * CB) * CB + bx - cx * CB) * 2
		local k = buffer.readu16(c.k, i)
		if k == 0 then
			return false, nil, 0, 0, false, false, 0
		end
		local k2 = buffer.readu16(c.k2, i)
		local d2, d3 = buffer.readu16(c.d2, i), buffer.readu16(c.d3, i)
		return c.parts[k], if k2 == 0 then nil else c.parts[k2], if d2 == NONE then math.huge else d2 / DQ, if d3 == NONE then math.huge else d3 / DQ, c.flat[k], k2 ~= 0 and c.flat[k2], buffer.readu16(c.d1, i) / DQ
	end

	function M.skyTo(gx: number, gy: number, gx1: number): number
		if rot == nil or root == nil or remHead <= #remQ or addHead <= #addQ or dirtyN > 0 then
			return gx - 1
		end
		local by = gy // 2
		if by < wy0 or by > wy1 then
			return gx - 1
		end
		local cy = by // CB
		local x = gx
		while x <= gx1 do
			local bx = x // 2
			if bx < wx0 or bx > wx1 then
				break
			end
			local cx = bx // CB
			local c = chunks[(cx + 32768) * 65536 + (cy + 32768)]
			if c == nil then
				-- (no part reaches this chunk at all: sky to its end, or to the window's, past which nothing is known)
				x = math.min((cx + 1) * CB, wx1 + 1) * 2
			else
				if buffer.readu16(c.k, ((by - cy * CB) * CB + bx - cx * CB) * 2) ~= 0 then
					break
				end
				x = (bx + 1) * 2
			end
		end
		return math.min(x - 1, gx1)
	end

	function M.debugState(): { parts: number, chunks: number, queued: number, ready: boolean }
		return { parts = partN, chunks = chunkN, queued = (#addQ - addHead + 1) + (#remQ - remHead + 1) + dirtyN, ready = M.ready() }
	end

	return (M :: any) :: Map
end

return RayMap
