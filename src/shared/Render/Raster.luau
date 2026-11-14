--!strict
--!native
-- Orthographic rasteriser for the pixel layer: the 2:1 pixel-art view and its world-anchored art grid, the framing
-- (the shop's outline as big as it fits clear of the HUD), projection, pick rays, boxes, spheres and floor shadows
-- (ARCHITECTURE 11.2, REWORK2 1.1-1.2). OWNER: WP8. Pure.
--
-- Conventions
-- * cf12 = { CFrame:GetComponents() } = { x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 }.
--   Columns: right R = (R00, R10, R20), up U = (R01, R11, R21), look L = -(R02, R12, R22).
-- * The view is orthographic: a centre C (world) and a view height viewH (studs from the top to the bottom of the
--   full screen). s = fullY / viewH is the scale in full-screen px per stud. A world point P lands on full-screen px
--   x = fullX/2 + ((P - C).R) s, y = fullY/2 - ((P - C).U) s, at depth (P - C).L + back.
-- * Every pixel casts its own parallel ray: origin C + R (x - fullX/2)/s - U (y - fullY/2)/s - L back, direction L.
--   Depth is the distance along that ray (== RaycastResult.Distance of a ray cast from that origin along L), so
--   analytic objects depth-test exactly against the raycast static bake.
-- * The art grid (one pixel size for the whole game): K whole screen px per art pixel (Raster.pixelScale). The layer
--   is W x H = ceil(fullX/K) x ceil(fullY/K) art pixels anchored at the full screen's top-left corner (ScreenInsets
--   None space, offX = offY = 0): layer pixel i spans full-screen x in [i*K, (i+1)*K), so it may overscan the right
--   and bottom edges by less than K px and never sits on a fractional offset. UI on the same grid places things at
--   whole multiples of K from the full screen's top-left. Pixel (i, j) is sampled at its centre. Buffer index of
--   pixel (i, j) is j*W + i.
-- * The world-anchored grid (Raster.Grid, Raster.gridCam): the camera's yaw is 45 and its pitch 30 (2:1 dimetric),
--   so a stud along world x or z is a art px across and a/2 art px down, and a vertical stud a*sqrt(1.5) px up. The
--   global art pixel of a world point is G = (phX + (P.R) q, phY - (P.U) q) with q = a sqrt 2; a camera pan is a
--   whole number of art pixels (px, py), the global pixel at the layer's top-left, so layer pixel (i, j) is global
--   pixel (i + px, j + py) and shows exactly what it shows at any other pan. The scale a is a whole or half number
--   (Raster.gridScale) and the phase (phX, phY) keeps every edge of the 1/80-stud build lattice off the pixel centres
--   (Raster.gridPhase), so ground edges raster as clean 2-1-2-1 steps and vertical edges as straight columns, the
--   same everywhere on screen. Cams carry their pan as gx, gy (zero for Raster.cam) and the ray origin of global
--   pixel (0, 0) (gox, goy, goz): Raster.origin computes a pixel's ray from its global index, so one global pixel
--   gets the very same ray at any pan.
--   Patterns that must not crawl when the view pans (dither, the shadow checker, dotted rims) use global coordinates.
-- * Solids: Block (drawBox), Ball (drawSphere), Cylinder (along the part's X axis, diameter min(Y, Z); drawCylinder),
--   Wedge and CornerWedge (convex plane sets from Raster.planes; drawConvex); Raster.drawPart picks one by shape name.
--   A part that covers no pixel centre (smaller than an art pixel) still draws the pixel under its centre. With a
--   `mix` function a part is see-through: it blends into what is drawn and keeps the depth and id behind it.

export type Cam = {
	-- basis: right, up, look (unit, orthonormal)
	rx: number,
	ry: number,
	rz: number,
	ux: number,
	uy: number,
	uz: number,
	lx: number,
	ly: number,
	lz: number,
	-- view centre (world), view height (studs), scale (full-screen px per stud), ray start behind the centre
	cx: number,
	cy: number,
	cz: number,
	viewH: number,
	s: number,
	back: number,
	-- layer
	W: number,
	H: number,
	K: number,
	fullX: number,
	fullY: number,
	offX: number,
	offY: number,
	-- ray origin through the centre of layer pixel (0, 0), and the origin step per layer pixel in i and in j
	ox: number,
	oy: number,
	oz: number,
	ix: number,
	iy: number,
	iz: number,
	jx: number,
	jy: number,
	jz: number,
	-- the global art pixel of layer pixel (0, 0) (the pan; 0, 0 for Raster.cam) and the ray origin through the centre
	-- of global pixel (0, 0): Raster.origin(i, j) = go + (i + gx) * (ix, iy, iz) + (j + gy) * (jx, jy, jz)
	gx: number,
	gy: number,
	gox: number,
	goy: number,
	goz: number,
	-- depth test: a new surface must be this much nearer (studs) than what is already there
	bias: number,
}
-- a screen rect in full-screen px (ScreenInsets None space): x0..x1 left to right, y0..y1 top to bottom
export type Rect = { x0: number, y0: number, x1: number, y1: number }
-- The world-anchored art grid of a view (see Conventions): scale a (whole art px per stud along a ground axis), q =
-- art px per stud along the screen axes, the phase (phX, phY) where the world origin lands, l = the view plane's
-- position along the look vector (C.L; rays start at l - back), and the pan (px, py): the global art pixel at the
-- layer's top-left (whole numbers).
export type Grid = { a: number, q: number, phX: number, phY: number, l: number, px: number, py: number }
-- (t: the hit's distance along the pixel's ray, from Raster.origin(cam, x, y), where the solid knows it: a textured
-- shade finds the point on the part with it; a uniform shade never gets it)
export type Shade = (rgb: number, nx: number, ny: number, nz: number, x: number, y: number, t: number?) -> number
export type Mix = (over: number, under: number) -> number
-- color u32 RGBA little-endian (R + G*256 + B*65536 + 255*2^24), depth f32 (ray distance), id u16
export type Frame = { W: number, H: number, color: buffer, depth: buffer, id: buffer }

local Raster = {}

local FAR = 1e30 -- empty-frame depth
local NEAR = 0.05 -- geometry closer than this to the ray plane counts as behind it
local DEPTH_BIAS = 0.03 -- a new surface must be this much nearer than what is already there
local EDGE_EPS = 1e-4 -- face-bounds tolerance (studs), keeps shared edges watertight
local SHADOW_TOL = 0.75 -- a shadow only darkens pixels whose visible surface lies on the shadow plane
local FIT_MIN = 0.35 -- the fit never shrinks the shop below this share of its bare-screen size, whatever the HUD covers
local FIT_TOL = 1e-4 -- the fit's scale is found to this share of the bare-screen scale (well under a px)
local FIT_EPS = 1e-6 -- px: an outline that just touches a block's margin or the screen's counts as clear
local T_EPS = 1e-4 -- convex / cylinder hits: entry may exceed exit by this much (studs), keeps shared edges closed

------------------------------------------------------------------ view
-- Components of CFrame.lookAt(Vector3.zero, look) for the fixed camera (world up +Y), as cf12 at the origin.
-- back = (sin yaw cos pitch, sin pitch, cos yaw cos pitch) points from the scene toward the viewer; look = -back.
function Raster.rotation(yawDeg: number, pitchDeg: number): { number }
	local yaw, pitch = math.rad(yawDeg), math.rad(pitchDeg)
	local bx, by, bz = math.sin(yaw) * math.cos(pitch), math.sin(pitch), math.cos(yaw) * math.cos(pitch)
	-- right = up x back (normalised), up' = back x right
	local rl = math.sqrt(bz * bz + bx * bx)
	local rx, ry, rz = 1, 0, 0
	if rl > 1e-9 then
		rx, rz = bz / rl, -bx / rl
	end
	local ux, uy, uz = by * rz - bz * ry, bz * rx - bx * rz, bx * ry - by * rx
	return { 0, 0, 0, rx, ux, bx, ry, uy, by, rz, uz, bz }
end

-- The art pixel size K (whole screen px per art pixel) of a full screen fullX x fullY px (docs/REWORK2.md 1.3):
-- minK plus one for every entry of `sides` that the screen's short side exceeds, at least ceil(short side /
-- maxShort) (a quality tier's cap on the art px across the short side), and at least what keeps the layer within
-- maxImage px on both sides (the EditableImage limit).
function Raster.pixelScale(fullX: number, fullY: number, minK: number, sides: { number }, maxShort: number?, maxImage: number?): number
	local fx, fy = math.max(1, fullX), math.max(1, fullY)
	local short = math.min(fx, fy)
	local k = math.max(1, math.floor(minK))
	for _, side in sides do
		if short > side then
			k += 1
		end
	end
	if maxShort ~= nil and maxShort > 0 then
		k = math.max(k, math.ceil(short / maxShort - 1e-9))
	end
	if maxImage ~= nil and maxImage > 0 then
		k = math.max(k, math.ceil(fx / maxImage - 1e-9), math.ceil(fy / maxImage - 1e-9))
	end
	return k
end

-- Convex hull of flat x, y pairs (Andrew's monotone chain): flat x, y pairs in counter-clockwise order for a y-up
-- frame (every point inside lies left of each edge: cross > 0), repeated and collinear points left out. Fewer than 3
-- points come back as they are.
function Raster.hull(xy: { number }): { number }
	local n = #xy // 2
	if n < 3 then
		return table.clone(xy)
	end
	local idx: { number } = table.create(n)
	for i = 1, n do
		idx[i] = i
	end
	table.sort(idx, function(a: number, b: number): boolean
		local ax, bx = xy[a * 2 - 1], xy[b * 2 - 1]
		if ax ~= bx then
			return ax < bx
		end
		return xy[a * 2] < xy[b * 2]
	end)
	local hx: { number }, hy: { number } = table.create(2 * n), table.create(2 * n)
	local k = 0
	local function add(i: number, floor: number)
		local x, y = xy[i * 2 - 1], xy[i * 2]
		while k >= floor and (hx[k] - hx[k - 1]) * (y - hy[k - 1]) - (hy[k] - hy[k - 1]) * (x - hx[k - 1]) <= 0 do
			k -= 1
		end
		k += 1
		hx[k], hy[k] = x, y
	end
	for j = 1, n do
		add(idx[j], 2)
	end
	local lower = k + 1
	for j = n - 1, 1, -1 do
		add(idx[j], lower)
	end
	local out: { number } = table.create(2 * (k - 1))
	for i = 1, k - 1 do -- the last point is the first again
		out[i * 2 - 1], out[i * 2] = hx[i], hy[i]
	end
	return out
end

-- The framing's outline and blocks (Raster.fit, Raster.place), nil without points: the outline's box on the screen
-- axes (centre aMid, bMid and size w, h, studs), the world box of the points (the view plane's depth), the screen
-- (fx, fy, p = the pad as used), sHi = the bare-screen scale (px per stud) and place(s, best): where the outline's box
-- centre may go at scale s (full-screen px), the clear placement nearest the screen centre (best) or the first found,
-- nil if none.
type Framing = {
	aMid: number,
	bMid: number,
	w: number,
	h: number,
	fx: number,
	fy: number,
	sHi: number,
	bx: number,
	by: number,
	bz: number,
	place: (s: number, best: boolean) -> (number?, number?),
}

-- rot12: the camera rotation (cf12; position ignored). pts: flat x, y, z world points whose convex hull on screen is
-- the shop's outline (the corners of Layout.OUTLINE's boxes, plot origin included). blocks: screen rects (full-screen
-- px, ScreenInsets None space) the outline has to stay off: the HUD's blocks and Roblox's own buttons. pad: px kept
-- free between the outline and the screen edges and around every block (lawn may lie under a block).
local function framing(rot12: { number }, fullX: number, fullY: number, blocks: { Rect }, pad: number, pts: { number }): Framing?
	local rx, ry, rz = rot12[4], rot12[7], rot12[10]
	local ux, uy, uz = rot12[5], rot12[8], rot12[11]
	local fx, fy = math.max(1, fullX), math.max(1, fullY)
	local n = #pts // 3
	if n == 0 then
		return nil
	end
	-- the outline: the points' hull on the screen axes (studs, x right, y down)
	local xy: { number } = table.create(2 * n)
	local xMin, xMax, yMin, yMax, zMin, zMax = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for i = 1, n do
		local x, y, z = pts[i * 3 - 2], pts[i * 3 - 1], pts[i * 3]
		xy[i * 2 - 1] = x * rx + y * ry + z * rz
		xy[i * 2] = -(x * ux + y * uy + z * uz)
		xMin, xMax = math.min(xMin, x), math.max(xMax, x)
		yMin, yMax = math.min(yMin, y), math.max(yMax, y)
		zMin, zMax = math.min(zMin, z), math.max(zMax, z)
	end
	local hull = Raster.hull(xy)
	local m = #hull // 2
	local aMin, aMax, bMin, bMax = math.huge, -math.huge, math.huge, -math.huge
	for i = 1, m do
		aMin, aMax = math.min(aMin, hull[i * 2 - 1]), math.max(aMax, hull[i * 2 - 1])
		bMin, bMax = math.min(bMin, hull[i * 2]), math.max(bMax, hull[i * 2])
	end
	local aMid, bMid = (aMin + aMax) / 2, (bMin + bMax) / 2
	local w, h = math.max(aMax - aMin, 1e-6), math.max(bMax - bMin, 1e-6)
	-- the outline about its box centre
	local px: { number }, py: { number } = table.create(m), table.create(m)
	for i = 1, m do
		px[i], py[i] = hull[i * 2 - 1] - aMid, hull[i * 2] - bMid
	end
	local p = math.clamp(pad, 0, math.min(fx, fy) / 4)
	local sHi = math.min((fx - 2 * p) / w, (fy - 2 * p) / h) -- the bare-screen scale (px per stud)
	-- the blocks, grown by the pad
	local bl: { number } = {}
	for _, r in blocks do
		local x0, y0, x1, y1 = r.x0, r.y0, r.x1, r.y1
		if x0 == x0 and y0 == y0 and x1 == x1 and y1 == y1 and x1 > x0 and y1 > y0 then
			table.insert(bl, x0 - p)
			table.insert(bl, y0 - p)
			table.insert(bl, x1 + p)
			table.insert(bl, y1 + p)
		end
	end
	local cx0, cy0 = fx / 2, fy / 2

	-- Where the outline's box centre may go at scale s: the screen leaves the rect T, and each block forbids the
	-- inside of its Minkowski sum with the mirrored outline (a convex polygon). The clear region's point nearest the
	-- screen centre is the centre clamped into T, the centre's foot on a boundary edge or a corner where two boundary
	-- edges cross, so those are the candidates. Returns the nearest clear one (best) or the first found, nil if none.
	local function place(s: number, best: boolean): (number?, number?)
		local tx0, tx1 = p + s * w / 2, fx - p - s * w / 2
		local ty0, ty1 = p + s * h / 2, fy - p - s * h / 2
		if tx0 > tx1 then
			tx0 = (tx0 + tx1) / 2
			tx1 = tx0
		end
		if ty0 > ty1 then
			ty0 = (ty0 + ty1) / 2
			ty1 = ty0
		end
		-- obstacles: unit inward edge normals (nx, ny, d: inside where nx*x + ny*y > d) and their box
		local oN: { { number } } = {}
		local oBox: { number } = {}
		-- boundary segments (flat x0, y0, x1, y1): T's sides, then every obstacle edge that reaches T
		local seg: { number } = { tx0, ty0, tx1, ty0, tx1, ty0, tx1, ty1, tx1, ty1, tx0, ty1, tx0, ty1, tx0, ty0 }
		local verts: { number } = { tx0, ty0, tx1, ty0, tx1, ty1, tx0, ty1 }
		local hw, hh = s * w / 2, s * h / 2
		for k = 1, #bl, 4 do
			local x0, y0, x1, y1 = bl[k], bl[k + 1], bl[k + 2], bl[k + 3]
			-- the sum's box; a sum that misses T forbids nothing on screen
			if x0 - hw < tx1 - FIT_EPS and x1 + hw > tx0 + FIT_EPS and y0 - hh < ty1 - FIT_EPS and y1 + hh > ty0 + FIT_EPS then
				local corners = { x0, y0, x1, y0, x1, y1, x0, y1 }
				local sum: { number } = table.create(8 * m)
				for c = 1, 7, 2 do
					for j = 1, m do
						table.insert(sum, corners[c] - s * px[j])
						table.insert(sum, corners[c + 1] - s * py[j])
					end
				end
				local poly = Raster.hull(sum)
				local q = #poly // 2
				local nrm: { number } = table.create(3 * q)
				for i = 1, q do
					local ax, ay = poly[i * 2 - 1], poly[i * 2]
					local j = i % q + 1
					local bx, by = poly[j * 2 - 1], poly[j * 2]
					local ex, ey = bx - ax, by - ay
					local len = math.sqrt(ex * ex + ey * ey)
					if len > 1e-12 then
						-- left of the edge (counter-clockwise hull) is inside
						local nx, ny = -ey / len, ex / len
						table.insert(nrm, nx)
						table.insert(nrm, ny)
						table.insert(nrm, nx * ax + ny * ay)
					end
					if math.max(ax, bx) >= tx0 - FIT_EPS and math.min(ax, bx) <= tx1 + FIT_EPS and math.max(ay, by) >= ty0 - FIT_EPS and math.min(ay, by) <= ty1 + FIT_EPS then
						table.insert(seg, ax)
						table.insert(seg, ay)
						table.insert(seg, bx)
						table.insert(seg, by)
						table.insert(verts, ax)
						table.insert(verts, ay)
					end
				end
				table.insert(oN, nrm)
				table.insert(oBox, x0 - hw)
				table.insert(oBox, y0 - hh)
				table.insert(oBox, x1 + hw)
				table.insert(oBox, y1 + hh)
			end
		end
		local function clear(x: number, y: number): boolean
			if x < tx0 - FIT_EPS or x > tx1 + FIT_EPS or y < ty0 - FIT_EPS or y > ty1 + FIT_EPS then
				return false
			end
			for o, nrm in oN do
				local b = o * 4
				if x > oBox[b - 3] + FIT_EPS and x < oBox[b - 1] - FIT_EPS and y > oBox[b - 2] + FIT_EPS and y < oBox[b] - FIT_EPS then
					local inside = true
					for e = 1, #nrm, 3 do
						if nrm[e] * x + nrm[e + 1] * y - nrm[e + 2] <= FIT_EPS then
							inside = false
							break
						end
					end
					if inside then
						return false
					end
				end
			end
			return true
		end
		local bestX: number?, bestY: number?, bestD = nil, nil, math.huge
		-- true: stop looking
		local function try(x: number, y: number): boolean
			if not clear(x, y) then
				return false
			end
			local dx, dy = x - cx0, y - cy0
			local d = dx * dx + dy * dy
			if d < bestD then
				bestX, bestY, bestD = x, y, d
			end
			return not best
		end
		-- the centre clamped into T is the best point of T: when it is clear nothing beats it
		local ccx, ccy = math.clamp(cx0, tx0, tx1), math.clamp(cy0, ty0, ty1)
		if clear(ccx, ccy) then
			return ccx, ccy
		end
		for i = 1, #verts, 2 do
			if try(verts[i], verts[i + 1]) then
				return bestX, bestY
			end
		end
		local ns = #seg
		if best then
			for i = 1, ns, 4 do
				local ax, ay = seg[i], seg[i + 1]
				local ex, ey = seg[i + 2] - ax, seg[i + 3] - ay
				local l2 = ex * ex + ey * ey
				if l2 > 1e-18 then
					local t = math.clamp(((cx0 - ax) * ex + (cy0 - ay) * ey) / l2, 0, 1)
					try(ax + ex * t, ay + ey * t)
				end
			end
		end
		for i = 1, ns - 4, 4 do
			local ax, ay = seg[i], seg[i + 1]
			local rx2, ry2 = seg[i + 2] - ax, seg[i + 3] - ay
			for j = i + 4, ns, 4 do
				local bx, by = seg[j], seg[j + 1]
				local sx2, sy2 = seg[j + 2] - bx, seg[j + 3] - by
				local den = rx2 * sy2 - ry2 * sx2
				if math.abs(den) > 1e-12 then
					local qx, qy = bx - ax, by - ay
					local t = (qx * sy2 - qy * sx2) / den
					local u = (qx * ry2 - qy * rx2) / den
					if t >= -1e-9 and t <= 1 + 1e-9 and u >= -1e-9 and u <= 1 + 1e-9 then
						if try(ax + rx2 * t, ay + ry2 * t) then
							return bestX, bestY
						end
					end
				end
			end
		end
		return bestX, bestY
	end

	return {
		aMid = aMid,
		bMid = bMid,
		w = w,
		h = h,
		fx = fx,
		fy = fy,
		sHi = sHi,
		bx = (xMin + xMax) / 2,
		by = (yMin + yMax) / 2,
		bz = (zMin + zMax) / 2,
		place = place,
	}
end

-- The one framing (REWORK2 1.2): the shop as big as it fits on screen clear of the HUD (arguments: see framing).
-- The outline is scaled up uniformly as far as it goes with all of it on screen and off every block (lawn may lie
-- under a block); of the placements at that size the one whose outline box sits nearest the screen centre wins.
-- When the blocks leave no room even at FIT_MIN of the bare-screen size, they are ignored and the outline is centred
-- at that size. Returns the view centre (x, y, z; at the depth of the points' centre) and the view height (studs
-- from the top to the bottom of the full screen).
function Raster.fit(
	rot12: { number },
	fullX: number,
	fullY: number,
	blocks: { Rect },
	pad: number,
	pts: { number }
): (number, number, number, number)
	local F = framing(rot12, fullX, fullY, blocks, pad, pts)
	if F == nil then
		return 0, 0, 0, 1
	end
	local rx, ry, rz = rot12[4], rot12[7], rot12[10]
	local ux, uy, uz = rot12[5], rot12[8], rot12[11]
	local lx, ly, lz = -rot12[6], -rot12[9], -rot12[12]
	local fx, fy, sHi, place = F.fx, F.fy, F.sHi, F.place
	local cx0, cy0 = fx / 2, fy / 2
	local s = sHi
	local tx: number?, ty: number? = place(sHi, true)
	if tx == nil then
		local lo, hi = sHi * FIT_MIN, sHi
		if place(lo, false) == nil then
			-- the blocks leave no room: ignore them, centred
			s, tx, ty = lo, cx0, cy0
		else
			while hi - lo > FIT_TOL * sHi do
				local mid = (lo + hi) / 2
				if place(mid, false) ~= nil then
					lo = mid
				else
					hi = mid
				end
			end
			s = lo
			tx, ty = place(lo, true)
		end
	end
	local sx, sy = tx or cx0, ty or cy0
	s = math.max(s, 1e-9)
	local viewH = fy / s
	-- the outline box's centre (aMid, bMid) lands on (sx, sy)
	local uC = F.aMid - (sx - fx / 2) / s
	local vC = (sy - fy / 2) / s - F.bMid
	local l = F.bx * lx + F.by * ly + F.bz * lz
	return rx * uC + ux * vC + lx * l, ry * uC + uy * vC + ly * l, rz * uC + uz * vC + lz * l, viewH
end

-- Where the outline's box centre goes at a given scale s (full-screen px per stud, at most the bare-screen scale):
-- the clear placement nearest the screen centre (full-screen px; the centre itself when the outline fits there),
-- the same rules as Raster.fit's (arguments: see framing); nil when no placement at s keeps the outline on screen and
-- off every block. CameraController's Whole bakery view tries its clean scales with it (REWORK2 1.2).
function Raster.place(rot12: { number }, fullX: number, fullY: number, blocks: { Rect }, pad: number, pts: { number }, s: number): (number?, number?)
	local F = framing(rot12, fullX, fullY, blocks, pad, pts)
	if F == nil or not (s > 0) then
		return nil, nil
	end
	return F.place(s, true)
end

-- The orthographic camera of one layer. cf12: rotation and, as its position, the view centre C.
function Raster.cam(cf12: { number }, viewH: number, fullX: number, fullY: number, K: number, back: number): Cam
	local fx = math.max(1, fullX)
	local fy = math.max(1, fullY)
	local k = math.max(1, K)
	local W = math.ceil(fx / k)
	local H = math.ceil(fy / k)
	local vh = math.max(viewH, 1e-3)
	local s = fy / vh
	local offX, offY = 0, 0 -- the layer starts at the full screen's top-left: the art grid has no fractional offset
	local rx, ry, rz = cf12[4], cf12[7], cf12[10]
	local ux, uy, uz = cf12[5], cf12[8], cf12[11]
	local lx, ly, lz = -cf12[6], -cf12[9], -cf12[12]
	local cx, cy, cz = cf12[1], cf12[2], cf12[3]
	-- origin through the centre of pixel (0, 0)
	local a = (0.5 * k - offX - fx / 2) / s
	local b = (0.5 * k - offY - fy / 2) / s
	local step = k / s
	local ox, oy, oz = cx + rx * a - ux * b - lx * back, cy + ry * a - uy * b - ly * back, cz + rz * a - uz * b - lz * back
	return {
		rx = rx,
		ry = ry,
		rz = rz,
		ux = ux,
		uy = uy,
		uz = uz,
		lx = lx,
		ly = ly,
		lz = lz,
		cx = cx,
		cy = cy,
		cz = cz,
		viewH = vh,
		s = s,
		back = back,
		W = W,
		H = H,
		K = k,
		fullX = fx,
		fullY = fy,
		offX = offX,
		offY = offY,
		ox = ox,
		oy = oy,
		oz = oz,
		ix = rx * step,
		iy = ry * step,
		iz = rz * step,
		jx = -ux * step,
		jy = -uy * step,
		jz = -uz * step,
		gx = 0,
		gy = 0,
		gox = ox,
		goy = oy,
		goz = oz,
		bias = DEPTH_BIAS,
	}
end

------------------------------------------------------------------ the world-anchored 2:1 grid
-- Part edges and plot origins lie on this grid (studs): plot origins are whole studs and the shop's parts sit on
-- 1/8, 1/16 (trims) and 1/20 or 1/40 stud (the floor's tiles, decor), all multiples of 1/80.
local BUILD_STEP = 1 / 80
local PHASE_STEPS = 256 -- the phase search tries multiples of 1/256 art px
local phaseCache: { [number]: { number } } = {}

-- The phase of the global art grid for scale a (art px per stud along a ground axis): where the world origin lands
-- (phX, phY in [0, 1)), chosen so the edges of the build grid (BUILD_STEP) stay as far as they can from the pixel
-- centres. At pitch 30 a ground point (x, 0, z) lands at G = (phX + a(x - z), phY + a(x + z)/2): a vertical edge is
-- the column G.x, a ground edge along x the 2:1 line G.y - G.x/2 = phY - phX/2 + a z, along z G.y + G.x/2 = phY +
-- phX/2 + a x. Pixel centres sit at G.x = n + 1/2 and on the 2:1 lines whose constant is 1/4 mod 1/2, so a vertical
-- edge must stay off n + 1/2 and a ground edge off 1/4 + n/2 (there the pixels along it would round either way and
-- its steps come out ragged). The clearance this leaves (px, perpendicular to the edge) is about 0.045 for a = 16,
-- 0.03 to 0.04 for a = 8 and 10, 0.015 for a = 4, 0.0075 for other even a, 0.004 for odd a and for the odd multiples
-- of 1.25 (1.25, 3.75, 6.25, 8.75: the build grid's offsets fall on 1/64 px): above the float error of a ray (under
-- 1e-3 px). Returns phX, phY and that clearance. Edges at other heights fall where they fall: the exact 2:1 slope
-- still gives them perfectly regular steps unless one happens to run within float error of a row of centres. Exact
-- for every multiple of 1/4 (their offsets repeat within 4 studs).
function Raster.gridPhase(a: number): (number, number, number)
	local hit = phaseCache[a]
	if hit then
		return hit[1], hit[2], hit[3]
	end
	-- the offsets a * k / 80 (mod 1) the build grid produces, over 4 studs (a whole period for a quarter step)
	local offs: { number } = {}
	local seen: { [number]: boolean } = {}
	for k = 0, 319 do
		local f = (a * k * BUILD_STEP) % 1
		local key = math.floor(f * 65536 + 0.5) % 65536
		if not seen[key] then
			seen[key] = true
			table.insert(offs, f)
		end
	end
	local function dist(v: number, period: number, target: number): number
		local d = (v - target) % period
		return math.min(d, period - d)
	end
	local diagK = 2 / math.sqrt(5) -- a y distance from a 2:1 line, measured perpendicular to it
	local bestX, bestY, best = 0, 0, -1
	for ix = 0, PHASE_STEPS - 1 do
		local phX = ix / PHASE_STEPS
		local mv = math.huge
		for _, f in offs do
			mv = math.min(mv, dist(phX + f, 1, 0.5))
		end
		if mv > best then
			for iy = 0, PHASE_STEPS - 1 do
				local phY = iy / PHASE_STEPS
				local m = mv
				for _, f in offs do
					m = math.min(m, diagK * dist(phY - phX / 2 + f, 0.5, 0.25), diagK * dist(phY + phX / 2 + f, 0.5, 0.25))
					if m <= best then
						break
					end
				end
				if m > best + 1e-12 then
					bestX, bestY, best = phX, phY, m
				end
			end
		end
	end
	phaseCache[a] = { bestX, bestY, best }
	return bestX, bestY, best
end

-- The grid scale for a view: `fit` art px per stud is what fits (Raster.fit's scale, divided by K and sqrt 2), `zoom`
-- how much closer to go. With `even` (the Close view): an even whole number (0.5-stud features are whole pixels), the
-- one nearest fit * zoom by ratio, at least 2. Without (the whole bakery): the largest multiple of 1/4 up to fit * zoom
-- whose grid phase keeps the build grid's edges at least MIN_CLEAR px off the pixel centres, at least 1, so the view
-- never shows less than asked. That is a whole number or a multiple of 1.25 (1.25, 2.5, 3.75, 6.25, 7.5 ...); other
-- quarter steps (1.5, 2.25, 3.5 ...) put the build grid's edges on a finer lattice than MIN_CLEAR allows (they are
-- skipped by its size: an edge can stay at most half a lattice step off the centres). A step down loses less than one
-- art px per stud.
local MIN_CLEAR = 0.0035
function Raster.gridScale(fit: number, zoom: number, even: boolean): number
	local want = math.max(1e-6, fit * zoom)
	if not even then
		local n = math.floor(want * 4 + 1e-9)
		while n > 4 do
			-- the build grid's edges land on multiples of 1 / (320 / gcd(n, 320)) px: too fine a lattice cannot clear
			local g, r = n, 320
			while r ~= 0 do
				g, r = r, g % r
			end
			if 0.5 * g / 320 >= MIN_CLEAR then
				local _, _, clear = Raster.gridPhase(n / 4)
				if clear >= MIN_CLEAR then
					return n / 4
				end
			end
			n -= 1
		end
		return 1
	end
	local lo = math.max(2, 2 * math.floor(want / 2))
	local hi = lo + 2
	return if want <= lo or math.log(want / lo) <= math.log(hi / want) then lo else hi
end

-- One axis of the Close view's follow (CameraController, REWORK2 1.2), in art px: the pan p (a whole number: the
-- global pixel at the screen's left or top edge, so a point at global coordinate g shows at g - p) that moves least
-- from `cur` under these rules, most important first: the baker at global `pos` shows between screen coordinates
-- vis0 and vis1; the focus at `fpos` (if any) between f0 and f1; the pan stays in [lo, hi] (nothing beyond the shop's
-- outline; lo > hi: the outline is narrower than the screen, so the middle of the two); the baker shows in the dead
-- zone dz0 .. dz1. A rule that cannot hold with the ones before it gets as close as they allow (so a camera the
-- outline holds stays at the outline's end, and a far focus is approached as far as the baker stays visible).
function Raster.followAxis(
	cur: number,
	pos: number,
	dz0: number,
	dz1: number,
	vis0: number,
	vis1: number,
	lo: number,
	hi: number,
	fpos: number?,
	f0: number?,
	f1: number?
): number
	local i0, i1 = pos - vis1, pos - vis0
	-- keep [c0, c1] within what is left; when they miss each other, go to the end nearest it
	local function narrow(c0: number, c1: number)
		local n0, n1 = math.max(i0, c0), math.min(i1, c1)
		if n0 <= n1 then
			i0, i1 = n0, n1
		elseif c1 < i0 then
			i1 = i0
		else
			i0 = i1
		end
	end
	if fpos ~= nil and f0 ~= nil and f1 ~= nil then
		narrow(fpos - f1, fpos - f0)
	end
	if lo > hi then
		local m = (lo + hi) / 2
		narrow(m, m)
	else
		narrow(lo, hi)
	end
	narrow(pos - dz1, pos - dz0)
	local w0, w1 = math.ceil(i0 - 1e-9), math.floor(i1 + 1e-9)
	if w0 > w1 then
		return math.floor((i0 + i1) / 2 + 0.5)
	end
	return math.clamp(math.floor(cur + 0.5), w0, w1)
end

-- The global art pixel coordinates (float) of world point (x, y, z) on grid g: pixel (gi, gj) covers [gi, gi + 1) x
-- [gj, gj + 1); its centre is (gi + 0.5, gj + 0.5). Independent of the pan.
function Raster.gridPoint(rot12: { number }, g: Grid, x: number, y: number, z: number): (number, number)
	local q = g.q
	return g.phX + (x * rot12[4] + y * rot12[7] + z * rot12[10]) * q, g.phY - (x * rot12[5] + y * rot12[8] + z * rot12[11]) * q
end

-- The view centre (world) of grid g on a full screen fullX x fullY px at K px per art pixel: the point at the screen's
-- centre on the view plane. With the view height fullY / (K q) it is the view CameraController shows.
function Raster.gridCenter(rot12: { number }, g: Grid, fullX: number, fullY: number, K: number): (number, number, number)
	local q = math.max(g.q, 1e-9)
	local k = math.max(1, K)
	local u = (g.px + math.max(1, fullX) / (2 * k) - g.phX) / q
	local v = (g.phY - g.py - math.max(1, fullY) / (2 * k)) / q
	local l = g.l
	return rot12[4] * u + rot12[5] * v - rot12[6] * l, rot12[7] * u + rot12[8] * v - rot12[9] * l, rot12[10] * u + rot12[11] * v - rot12[12] * l
end

-- The orthographic camera of a grid view (rot12: the rotation; position ignored): layer pixel (i, j) is global pixel
-- (i + g.px, j + g.py) and its ray is the one of that global pixel at any pan (Raster.origin). project, boxRect and the
-- draw functions work as with Raster.cam; W, H, K and the top-left art grid are the same.
function Raster.gridCam(rot12: { number }, g: Grid, fullX: number, fullY: number, K: number, back: number): Cam
	local q = math.max(g.q, 1e-9)
	local cx, cy, cz = Raster.gridCenter(rot12, g, fullX, fullY, K)
	local c = Raster.cam({ cx, cy, cz, table.unpack(rot12, 4, 12) }, math.max(1, fullY) / (math.max(1, K) * q), fullX, fullY, K, back)
	local rx, ry, rz = rot12[4], rot12[7], rot12[10]
	local ux, uy, uz = rot12[5], rot12[8], rot12[11]
	local lx, ly, lz = -rot12[6], -rot12[9], -rot12[12]
	-- global pixel (0, 0): u = (0.5 - phX) / q along R, v = (phY - 0.5) / q along U, l - back along L
	local u, v, w = (0.5 - g.phX) / q, (g.phY - 0.5) / q, g.l - back
	local gox, goy, goz = rx * u + ux * v + lx * w, ry * u + uy * v + ly * w, rz * u + uz * v + lz * w
	c.ix, c.iy, c.iz = rx / q, ry / q, rz / q
	c.jx, c.jy, c.jz = -ux / q, -uy / q, -uz / q
	c.gx, c.gy = g.px, g.py
	c.gox, c.goy, c.goz = gox, goy, goz
	c.ox = gox + g.px * c.ix + g.py * c.jx
	c.oy = goy + g.px * c.iy + g.py * c.jy
	c.oz = goz + g.px * c.iz + g.py * c.jz
	return c
end

function Raster.newFrame(W: number, H: number): Frame
	local n = W * H
	local color = buffer.create(n * 4)
	local depth = buffer.create(n * 4)
	local id = buffer.create(n * 2)
	local opaque = 255 * 16777216
	for i = 0, n - 1 do
		buffer.writeu32(color, i * 4, opaque)
		buffer.writef32(depth, i * 4, FAR)
	end
	return { W = W, H = H, color = color, depth = depth, id = id }
end

-- The camera of a w x h window of the layer whose pixel (0, 0) is layer pixel (x0, y0): everything drawn with it into
-- a w x h frame lands exactly where the full camera would put it, shifted by (-x0, -y0) and clipped to the window
-- (a scratch drawing of one model, e.g. PixelRenderer's silhouette mask for the player's rim).
function Raster.window(cam: Cam, x0: number, y0: number, w: number, h: number): Cam
	local c = table.clone(cam)
	c.W, c.H = w, h
	c.offX, c.offY = cam.offX - x0 * cam.K, cam.offY - y0 * cam.K
	c.ox = cam.ox + x0 * cam.ix + y0 * cam.jx
	c.oy = cam.oy + x0 * cam.iy + y0 * cam.jy
	c.oz = cam.oz + x0 * cam.iz + y0 * cam.jz
	c.gx, c.gy = cam.gx + x0, cam.gy + y0
	return c
end

-- World point -> layer pixel coordinates (float; pixel i covers [i, i+1)) and depth along the rays.
-- depth <= 0 means the point is behind the ray plane (no ray of this camera reaches it).
function Raster.project(cam: Cam, x: number, y: number, z: number): (number, number, number)
	local qx, qy, qz = x - cam.cx, y - cam.cy, z - cam.cz
	local a = qx * cam.rx + qy * cam.ry + qz * cam.rz
	local b = qx * cam.ux + qy * cam.uy + qz * cam.uz
	local d = qx * cam.lx + qy * cam.ly + qz * cam.lz + cam.back
	local sx = cam.fullX / 2 + a * cam.s
	local sy = cam.fullY / 2 - b * cam.s
	return (sx + cam.offX) / cam.K, (sy + cam.offY) / cam.K, d
end

-- Ray origin through layer coordinates (i, j) (the centre of pixel (i, j) for whole numbers). Direction: the look
-- vector (cam.lx, cam.ly, cam.lz). Computed from the global pixel (i + gx, j + gy), so a grid cam gives one global
-- pixel the very same ray at every pan.
function Raster.origin(cam: Cam, i: number, j: number): (number, number, number)
	local gi, gj = i + cam.gx, j + cam.gy
	return cam.gox + gi * cam.ix + gj * cam.jx, cam.goy + gi * cam.iy + gj * cam.jy, cam.goz + gi * cam.iz + gj * cam.jz
end

-- Ray origin through full-screen px (x, y) (ScreenInsets None space).
function Raster.screenOrigin(cam: Cam, x: number, y: number): (number, number, number)
	local a = (x - cam.fullX / 2) / cam.s
	local b = (y - cam.fullY / 2) / cam.s
	return cam.cx + cam.rx * a - cam.ux * b - cam.lx * cam.back,
		cam.cy + cam.ry * a - cam.uy * b - cam.ly * cam.back,
		cam.cz + cam.rz * a - cam.uz * b - cam.lz * cam.back
end

-- Integer pixel range whose centres can fall inside [minX, maxX] x [minY, maxY] (layer coordinates),
-- clipped to the layer. Returns nil when empty.
local function clipRect(cam: Cam, minX: number, minY: number, maxX: number, maxY: number): (number?, number?, number?, number?)
	local x0 = math.max(0, math.ceil(minX - 0.5))
	local y0 = math.max(0, math.ceil(minY - 0.5))
	local x1 = math.min(cam.W - 1, math.floor(maxX - 0.5))
	local y1 = math.min(cam.H - 1, math.floor(maxY - 0.5))
	if x0 > x1 or y0 > y1 then
		return nil, nil, nil, nil
	end
	return x0, y0, x1, y1
end

-- Screen rect of an oriented box: inclusive pixel rect x0, y0, x1, y1 of the pixels whose centres may be
-- covered, clipped to the layer; all nil when off-screen or (partly) behind the ray plane.
-- (The projection is affine, so the 8 corners' extremes are the centre's projection plus or minus the summed
-- magnitudes of the projected half axes: no corner loop, which matters where scripts run interpreted.)
function Raster.boxRect(cam: Cam, cf12: { number }, sx: number, sy: number, sz: number): (number?, number?, number?, number?)
	local hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
	local ax, ay, az = cf12[4] * hx, cf12[7] * hx, cf12[10] * hx
	local bx, by, bz = cf12[5] * hy, cf12[8] * hy, cf12[11] * hy
	local ex, ey, ez = cf12[6] * hz, cf12[9] * hz, cf12[12] * hz
	local rx, ry, rz, ux, uy, uz, lx, ly, lz = cam.rx, cam.ry, cam.rz, cam.ux, cam.uy, cam.uz, cam.lx, cam.ly, cam.lz
	local px, py, d = Raster.project(cam, cf12[1], cf12[2], cf12[3])
	local spanD = math.abs(ax * lx + ay * ly + az * lz) + math.abs(bx * lx + by * ly + bz * lz) + math.abs(ex * lx + ey * ly + ez * lz)
	if d - spanD <= NEAR then
		return nil, nil, nil, nil
	end
	local k = cam.s / cam.K
	local spanX = (math.abs(ax * rx + ay * ry + az * rz) + math.abs(bx * rx + by * ry + bz * rz) + math.abs(ex * rx + ey * ry + ez * rz)) * k
	local spanY = (math.abs(ax * ux + ay * uy + az * uz) + math.abs(bx * ux + by * uy + bz * uz) + math.abs(ex * ux + ey * uy + ez * uz)) * k
	return clipRect(cam, px - spanX, py - spanY, px + spanX, py + spanY)
end

------------------------------------------------------------------ boxes
-- Shade functions whose colour depends on the albedo and the normal only (not on the pixel): a flat face is shaded
-- once instead of per pixel (Raster.markUniform).
local uniform: { [Shade]: boolean } = {}
function Raster.markUniform(shade: Shade)
	uniform[shade] = true
end

-- Where on a row of a face its coordinate (u or v) can lie within [-l, l]: with parallel rays it is linear in the
-- pixel indices, a + i d on row j with a = a0 + j aj, so the bounding i are linear in j too. Returns, for
-- i = lo + j k and i = hi + j k, (lo, hi, k), or nil when d is about 0 (the coordinate is fixed along a row).
local function spanOf(a0: number, aj: number, d: number, l: number): (number?, number, number)
	if d > 1e-12 or d < -1e-12 then
		local inv = 1 / d
		local p, q = (-l - a0) * inv, (l - a0) * inv
		if p < q then
			return p, q, -aj * inv
		end
		return q, p, -aj * inv
	end
	return nil, 0, 0
end

-- Fill one face: centre (fx, fy, fz), outward unit normal (nx, ny, nz), in-plane unit axes e1/e2 with half sizes
-- hu/hv, over the pixel rect x0..x1, y0..y1 (its screen rect, clipped; every corner in front of the ray plane).
-- With parallel rays the hit distance t and the face coordinates u, v are linear in the pixel indices, so each row
-- visits only the run of pixels the face covers and each pixel costs an addition and a depth test (where scripts
-- run interpreted, as on Roblox's clients, the per-pixel tests cost more than the arithmetic). Returns the number of
-- pixels written.
local function fillFace(
	f: Frame,
	cam: Cam,
	fx: number,
	fy: number,
	fz: number,
	nx: number,
	ny: number,
	nz: number,
	e1x: number,
	e1y: number,
	e1z: number,
	hu: number,
	e2x: number,
	e2y: number,
	e2z: number,
	hv: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?,
	x0: number,
	y0: number,
	x1: number,
	y1: number
): number
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local inv = 1 / (nx * lx + ny * ly + nz * lz)
	local W = f.W
	local color, depth, ids = f.color, f.depth, f.id
	local bias = cam.bias
	local cix, ciy, ciz, cjx, cjy, cjz = cam.ix, cam.iy, cam.iz, cam.jx, cam.jy, cam.jz
	-- origin of pixel (0, 0) relative to the face centre
	local qx, qy, qz = cam.ox - fx, cam.oy - fy, cam.oz - fz
	-- t(i, j) = -n.(O(i, j) - Fc) / den
	local t00 = -(nx * qx + ny * qy + nz * qz) * inv
	local ti = -(nx * cix + ny * ciy + nz * ciz) * inv
	local tj = -(nx * cjx + ny * cjy + nz * cjz) * inv
	-- u(i, j) = (O(i, j) - Fc + t L).e1, likewise v with e2
	local le1 = lx * e1x + ly * e1y + lz * e1z
	local le2 = lx * e2x + ly * e2y + lz * e2z
	local u00 = qx * e1x + qy * e1y + qz * e1z + t00 * le1
	local ui = cix * e1x + ciy * e1y + ciz * e1z + ti * le1
	local uj = cjx * e1x + cjy * e1y + cjz * e1z + tj * le1
	local v00 = qx * e2x + qy * e2y + qz * e2z + t00 * le2
	local vi = cix * e2x + ciy * e2y + ciz * e2z + ti * le2
	local vj = cjx * e2x + cjy * e2y + cjz * e2z + tj * le2
	local lu, lv = hu + EDGE_EPS, hv + EDGE_EPS
	local uLo, uHi, uK = spanOf(u00, uj, ui, lu)
	local vLo, vHi, vK = spanOf(v00, vj, vi, lv)
	local c0: number? = if uniform[shade] then shade(rgb, nx, ny, nz, x0, y0) else nil
	local fast = c0 ~= nil and mix == nil
	local n = 0
	for j = y0, y1 do
		local uA, vA = u00 + j * uj, v00 + j * vj
		-- the run of pixels where u and v lie on the face, from the bounds' estimate; then each end checked with the
		-- exact test, moved inward where it fails and outward while the next pixel passes, so the run is the exact one
		-- (it is one run: u and v are linear in i) and the estimate's rounding never matters (t > 0 holds wherever u, v
		-- do: every corner is in front of the ray plane)
		local ia, ib = x0, x1
		if uLo then
			local a, b = math.ceil(uLo + j * uK), math.floor(uHi + j * uK)
			if a > ia then
				ia = a
			end
			if b < ib then
				ib = b
			end
		elseif uA > lu or uA < -lu then
			continue
		end
		if vLo then
			local a, b = math.ceil(vLo + j * vK), math.floor(vHi + j * vK)
			if a > ia then
				ia = a
			end
			if b < ib then
				ib = b
			end
		elseif vA > lv or vA < -lv then
			continue
		end
		if ia <= ib then
			local u, v = uA + ia * ui, vA + ia * vi
			if u <= lu and u >= -lu and v <= lv and v >= -lv then
				-- passes: the pixel before it may pass too
				while ia > x0 do
					u, v = uA + (ia - 1) * ui, vA + (ia - 1) * vi
					if u <= lu and u >= -lu and v <= lv and v >= -lv then
						ia -= 1
					else
						break
					end
				end
			else
				repeat
					ia += 1
					u, v = uA + ia * ui, vA + ia * vi
				until ia > ib or (u <= lu and u >= -lu and v <= lv and v >= -lv)
			end
		end
		if ia > ib then
			-- the estimate may miss a run of a pixel or two: look for it beside the estimate
			local found = false
			local lo, hi = math.max(x0, ib - 1), math.min(x1, ia + 1)
			for i = lo, hi do
				local u, v = uA + i * ui, vA + i * vi
				if u <= lu and u >= -lu and v <= lv and v >= -lv then
					ia, ib = i, i
					found = true
					while ib < x1 do
						u, v = uA + (ib + 1) * ui, vA + (ib + 1) * vi
						if u <= lu and u >= -lu and v <= lv and v >= -lv then
							ib += 1
						else
							break
						end
					end
					break
				end
			end
			if not found then
				continue
			end
		else
			local u, v = uA + ib * ui, vA + ib * vi
			if u <= lu and u >= -lu and v <= lv and v >= -lv then
				while ib < x1 do
					u, v = uA + (ib + 1) * ui, vA + (ib + 1) * vi
					if u <= lu and u >= -lu and v <= lv and v >= -lv then
						ib += 1
					else
						break
					end
				end
			else
				repeat
					ib -= 1
					u, v = uA + ib * ui, vA + ib * vi
				until ib < ia or (u <= lu and u >= -lu and v <= lv and v >= -lv)
				if ib < ia then
					continue
				end
			end
		end
		local row = j * W
		local t = t00 + j * tj + ia * ti
		if fast then
			-- an opaque face of one colour (the common case): depth test and write
			local c = c0 :: number
			local o = (row + ia) * 4
			for _ = ia, ib do
				if t + bias < buffer.readf32(depth, o) then
					buffer.writeu32(color, o, c)
					buffer.writef32(depth, o, t)
					buffer.writeu16(ids, o * 0.5, id)
					n += 1
				end
				t += ti
				o += 4
			end
		else
			for i = ia, ib do
				local idx = row + i
				local o = idx * 4
				if t + bias < buffer.readf32(depth, o) then
					local c = c0 or shade(rgb, nx, ny, nz, i, j, t)
					if mix then
						buffer.writeu32(color, o, mix(c, buffer.readu32(color, o)))
					else
						buffer.writeu32(color, o, c)
						buffer.writef32(depth, o, t)
						buffer.writeu16(ids, idx * 2, id)
					end
					n += 1
				end
				t += ti
			end
		end
	end
	return n
end

-- Rasterise an oriented box (centre/orientation cf12, full sizes sx, sy, sz): every face that faces the viewer
-- (at most 3) is intersected per pixel ray and depth-tested. The box's centre and its three half axes are projected
-- once (the projection is affine): a face's screen rect is its centre's projection plus or minus the other two
-- projected half axes, and a face with a corner behind the ray plane is skipped. Returns the number of pixels
-- written.
function Raster.drawBox(
	f: Frame,
	cam: Cam,
	cf12: { number },
	sx: number,
	sy: number,
	sz: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?
): number
	local cx, cy, cz = cf12[1], cf12[2], cf12[3]
	-- unit axes (columns) and half sizes
	local ax, ay, az, ha = cf12[4], cf12[7], cf12[10], sx * 0.5
	local bx, by, bz, hb = cf12[5], cf12[8], cf12[11], sy * 0.5
	local ex, ey, ez, he = cf12[6], cf12[9], cf12[12], sz * 0.5
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	-- the face whose outward normal points against the look vector is the visible one of each pair
	local da = ax * lx + ay * ly + az * lz
	local db = bx * lx + by * ly + bz * lz
	local de = ex * lx + ey * ly + ez * lz
	local visA, visB, visE = da > 1e-9 or da < -1e-9, db > 1e-9 or db < -1e-9, de > 1e-9 or de < -1e-9
	if not (visA or visB or visE) then
		return 0
	end
	-- the projected centre and half axes (layer px x, y and depth)
	local pcx, pcy, pd = Raster.project(cam, cx, cy, cz)
	local k = cam.s / cam.K
	local rx, ry, rz, ux, uy, uz = cam.rx, cam.ry, cam.rz, cam.ux, cam.uy, cam.uz
	local aX, aY, aD = (ax * rx + ay * ry + az * rz) * ha * k, -(ax * ux + ay * uy + az * uz) * ha * k, da * ha
	local bX, bY, bD = (bx * rx + by * ry + bz * rz) * hb * k, -(bx * ux + by * uy + bz * uz) * hb * k, db * hb
	local eX, eY, eD = (ex * rx + ey * ry + ez * rz) * he * k, -(ex * ux + ey * uy + ez * uz) * he * k, de * he
	local absAX, absAY, absAD = math.abs(aX), math.abs(aY), math.abs(aD)
	local absBX, absBY, absBD = math.abs(bX), math.abs(bY), math.abs(bD)
	local absEX, absEY, absED = math.abs(eX), math.abs(eY), math.abs(eD)
	local n = 0
	if visA then
		local s = if da < 0 then 1 else -1
		local fx, fy, fd = pcx + aX * s, pcy + aY * s, pd + aD * s
		if fd - absBD - absED > NEAR then
			local x0, y0, x1, y1 = clipRect(cam, fx - absBX - absEX, fy - absBY - absEY, fx + absBX + absEX, fy + absBY + absEY)
			if x0 and y0 and x1 and y1 then
				n += fillFace(f, cam, cx + ax * ha * s, cy + ay * ha * s, cz + az * ha * s, ax * s, ay * s, az * s,
					bx, by, bz, hb, ex, ey, ez, he, rgb, id, shade, mix, x0, y0, x1, y1)
			end
		end
	end
	if visB then
		local s = if db < 0 then 1 else -1
		local fx, fy, fd = pcx + bX * s, pcy + bY * s, pd + bD * s
		if fd - absAD - absED > NEAR then
			local x0, y0, x1, y1 = clipRect(cam, fx - absAX - absEX, fy - absAY - absEY, fx + absAX + absEX, fy + absAY + absEY)
			if x0 and y0 and x1 and y1 then
				n += fillFace(f, cam, cx + bx * hb * s, cy + by * hb * s, cz + bz * hb * s, bx * s, by * s, bz * s,
					ax, ay, az, ha, ex, ey, ez, he, rgb, id, shade, mix, x0, y0, x1, y1)
			end
		end
	end
	if visE then
		local s = if de < 0 then 1 else -1
		local fx, fy, fd = pcx + eX * s, pcy + eY * s, pd + eD * s
		if fd - absAD - absBD > NEAR then
			local x0, y0, x1, y1 = clipRect(cam, fx - absAX - absBX, fy - absAY - absBY, fx + absAX + absBX, fy + absAY + absBY)
			if x0 and y0 and x1 and y1 then
				n += fillFace(f, cam, cx + ex * he * s, cy + ey * he * s, cz + ez * he * s, ex * s, ey * s, ez * s,
					ax, ay, az, ha, bx, by, bz, hb, rgb, id, shade, mix, x0, y0, x1, y1)
			end
		end
	end
	return n
end

------------------------------------------------------------------ spheres
-- Returns the number of pixels written.
function Raster.drawSphere(
	f: Frame,
	cam: Cam,
	cx: number,
	cy: number,
	cz: number,
	r: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?
): number
	if r <= 0 then
		return 0
	end
	local px, py, d = Raster.project(cam, cx, cy, cz)
	if d - r <= NEAR then
		return 0
	end
	-- the silhouette is a circle of radius r * s full-screen px
	local rr = r * cam.s / cam.K + 1
	local x0, y0, x1, y1 = clipRect(cam, px - rr, py - rr, px + rr, py + rr)
	if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
		return 0
	end
	local W = f.W
	local color, depth, ids = f.color, f.depth, f.id
	local bias = cam.bias
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local ix, iy, iz, jx, jy, jz = cam.ix, cam.iy, cam.iz, cam.jx, cam.jy, cam.jz
	local r2 = r * r
	local invR = 1 / r
	local n = 0
	for j = y0, y1 do
		local row = j * W
		-- q = O(i, j) - S
		local qx = cam.ox - cx + j * jx + x0 * ix
		local qy = cam.oy - cy + j * jy + x0 * iy
		local qz = cam.oz - cz + j * jz + x0 * iz
		for i = x0, x1 do
			local b = qx * lx + qy * ly + qz * lz
			local disc = b * b - (qx * qx + qy * qy + qz * qz - r2)
			if disc >= 0 then
				local t = -b - math.sqrt(disc)
				local idx = row + i
				local o = idx * 4
				if t > 0 and t < buffer.readf32(depth, o) - bias then
					local nx = (qx + t * lx) * invR
					local ny = (qy + t * ly) * invR
					local nz = (qz + t * lz) * invR
					local c = shade(rgb, nx, ny, nz, i, j, t)
					if mix then
						buffer.writeu32(color, o, mix(c, buffer.readu32(color, o)))
					else
						buffer.writeu32(color, o, c)
						buffer.writef32(depth, o, t)
						buffer.writeu16(ids, idx * 2, id)
					end
					n += 1
				end
			end
			qx += ix
			qy += iy
			qz += iz
		end
	end
	return n
end

------------------------------------------------------------------ cylinders
-- A Roblox cylinder: its axis is the part's X axis (length sx), its diameter min(sy, sz). Per pixel ray: the
-- infinite cylinder's entry/exit (a quadratic) intersected with the slab between the two caps; the hit is the
-- later entry (side or cap). Returns the number of pixels written.
function Raster.drawCylinder(
	f: Frame,
	cam: Cam,
	cf12: { number },
	sx: number,
	sy: number,
	sz: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?
): number
	local h = sx * 0.5
	local r = math.min(sy, sz) * 0.5
	if h <= 0 or r <= 0 then
		return 0
	end
	local x0, y0, x1, y1 = Raster.boxRect(cam, cf12, sx, 2 * r, 2 * r)
	if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
		return 0
	end
	local cx, cy, cz = cf12[1], cf12[2], cf12[3]
	local ax, ay, az = cf12[4], cf12[7], cf12[10]
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local ix, iy, iz, jx, jy, jz = cam.ix, cam.iy, cam.iz, cam.jx, cam.jy, cam.jz
	local la = lx * ax + ly * ay + lz * az
	local A = 1 - la * la
	local r2 = r * r
	local invR = 1 / r
	local capS = if la < 0 then 1 else -1 -- the cap the rays enter through has normal capS * axis
	local W = f.W
	local color, depth, ids = f.color, f.depth, f.id
	local bias = cam.bias
	local n = 0
	-- along a row the ray offset q moves by the camera's i vector, so the side's discriminant is a quadratic in the
	-- column: only the columns between its roots (and one more each side) can hit the side or a cap
	local Ia = ix * ax + iy * ay + iz * az
	local Ib = ix * lx + iy * ly + iz * lz - Ia * la
	local c2 = Ib * Ib - A * (ix * ix + iy * iy + iz * iz - Ia * Ia)
	local trim = A > 1e-9 and c2 < -1e-12
	for j = y0, y1 do
		local row = j * W
		local qx = cam.ox - cx + j * jx + x0 * ix
		local qy = cam.oy - cy + j * jy + x0 * iy
		local qz = cam.oz - cz + j * jz + x0 * iz
		local i0, i1 = x0, x1
		if trim then
			local qa0 = qx * ax + qy * ay + qz * az
			local b0 = qx * lx + qy * ly + qz * lz - qa0 * la
			local c1 = b0 * Ib - A * (qx * ix + qy * iy + qz * iz - qa0 * Ia)
			local c0 = b0 * b0 - A * (qx * qx + qy * qy + qz * qz - qa0 * qa0 - r2)
			local d = c1 * c1 - c2 * c0
			if d < -1e-9 * (c1 * c1 + math.abs(c2 * c0)) then
				continue -- the row misses the cylinder
			end
			local sq = math.sqrt(math.max(d, 0))
			-- (c2 < 0: the roots in order)
			local s0, s1 = (-c1 + sq) / c2, (-c1 - sq) / c2
			i0 = math.max(x0, x0 + math.floor(s0) - 1)
			i1 = math.min(x1, x0 + math.ceil(s1) + 1)
			if i0 > i1 then
				continue
			end
			-- (q stepped column by column as the full row does, so every pixel's ray is the same to the last bit)
			for _ = x0 + 1, i0 do
				qx += ix
				qy += iy
				qz += iz
			end
		end
		for i = i0, i1 do
			local qa = qx * ax + qy * ay + qz * az
			local perp2 = qx * qx + qy * qy + qz * qz - qa * qa
			local tIn, tOut = -math.huge, math.huge
			local ok = true
			if A > 1e-9 then
				local b = qx * lx + qy * ly + qz * lz - qa * la
				local disc = b * b - A * (perp2 - r2)
				if disc < 0 then
					ok = false
				else
					local sq = math.sqrt(disc)
					tIn, tOut = (-b - sq) / A, (-b + sq) / A
				end
			elseif perp2 > r2 then
				ok = false -- along the axis, outside the radius
			end
			if ok then
				local sIn, sOut = -math.huge, math.huge
				if la > 1e-9 or la < -1e-9 then
					local s1, s2 = (-h - qa) / la, (h - qa) / la
					if s1 < s2 then
						sIn, sOut = s1, s2
					else
						sIn, sOut = s2, s1
					end
				elseif qa > h or qa < -h then
					ok = false
				end
				local t = if tIn > sIn then tIn else sIn
				if ok and t > 0 and t <= math.min(tOut, sOut) + T_EPS then
					local idx = row + i
					local o = idx * 4
					if t < buffer.readf32(depth, o) - bias then
						local nx, ny, nz
						if tIn >= sIn then
							local px, py, pz = qx + t * lx, qy + t * ly, qz + t * lz
							local pa = px * ax + py * ay + pz * az
							nx, ny, nz = (px - pa * ax) * invR, (py - pa * ay) * invR, (pz - pa * az) * invR
						else
							nx, ny, nz = ax * capS, ay * capS, az * capS
						end
						local c = shade(rgb, nx, ny, nz, i, j, t)
						if mix then
							buffer.writeu32(color, o, mix(c, buffer.readu32(color, o)))
						else
							buffer.writeu32(color, o, c)
							buffer.writef32(depth, o, t)
							buffer.writeu16(ids, idx * 2, id)
						end
						n += 1
					end
				end
			end
			qx += ix
			qy += iy
			qz += iz
		end
	end
	return n
end

------------------------------------------------------------------ convex solids (wedges)
-- World planes (flat nx, ny, nz, d per plane; inside where n.P <= d, unit outward normals) of a part shape:
-- * "Wedge" (Roblox WedgePart): the high edge at the back (+Z), the slope facing the front (-Z) and up.
-- * "CornerWedge" (CornerWedgePart): a pyramid on the bottom face with its apex above the +X/-Z bottom corner
--   (the right and front faces are upright triangles, the two slopes face left and back). The same assumption as
--   the preview tool's ray caster; the static bake uses the engine's raycasts, so only the analytic layers
--   (dynamic parts, Snapshot) depend on it.
-- * anything else: the 6 faces of the box.
function Raster.planes(shape: string, cf12: { number }, sx: number, sy: number, sz: number): { number }
	local hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
	local loc: { number }
	if shape == "Wedge" then
		local l = math.max(1e-9, math.sqrt(hz * hz + hy * hy))
		loc = { 1, 0, 0, hx, -1, 0, 0, hx, 0, -1, 0, hy, 0, 0, 1, hz, 0, hz / l, -hy / l, 0 }
	elseif shape == "CornerWedge" then
		local la = math.max(1e-9, math.sqrt(hy * hy + hx * hx))
		local lb = math.max(1e-9, math.sqrt(hz * hz + hy * hy))
		loc = { 0, -1, 0, hy, 1, 0, 0, hx, 0, 0, -1, hz, -hy / la, hx / la, 0, 0, 0, hz / lb, hy / lb, 0 }
	else
		loc = { 1, 0, 0, hx, -1, 0, 0, hx, 0, 1, 0, hy, 0, -1, 0, hy, 0, 0, 1, hz, 0, 0, -1, hz }
	end
	local cx, cy, cz = cf12[1], cf12[2], cf12[3]
	local out = table.create(#loc, 0)
	for k = 1, #loc, 4 do
		local a, b, c = loc[k], loc[k + 1], loc[k + 2]
		local nx = cf12[4] * a + cf12[5] * b + cf12[6] * c
		local ny = cf12[7] * a + cf12[8] * b + cf12[9] * c
		local nz = cf12[10] * a + cf12[11] * b + cf12[12] * c
		out[k], out[k + 1], out[k + 2], out[k + 3] = nx, ny, nz, loc[k + 3] + nx * cx + ny * cy + nz * cz
	end
	return out
end

-- Rasterise a convex solid given by `planes` (Raster.planes) whose bounding box is (cf12, sx, sy, sz). Per pixel ray:
-- the latest entry over the planes that face the viewer against the earliest exit over the others (all linear in
-- the pixel indices). Returns the number of pixels written.
function Raster.drawConvex(
	f: Frame,
	cam: Cam,
	planes: { number },
	cf12: { number },
	sx: number,
	sy: number,
	sz: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?
): number
	local x0, y0, x1, y1 = Raster.boxRect(cam, cf12, sx, sy, sz)
	if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
		return 0
	end
	local np = #planes // 4
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	-- per plane k: v(i, j) = a0 + i * ai + j * aj is the hit distance (kind -1 entering, 1 leaving) or, for a plane
	-- parallel to the rays (kind 0), how far inside it the ray runs
	local A0, AI, AJ, KIND = table.create(np, 0), table.create(np, 0), table.create(np, 0), table.create(np, 0)
	for k = 1, np do
		local nx, ny, nz, d = planes[k * 4 - 3], planes[k * 4 - 2], planes[k * 4 - 1], planes[k * 4]
		local den = nx * lx + ny * ly + nz * lz
		local num0 = d - (nx * cam.ox + ny * cam.oy + nz * cam.oz)
		local numI = -(nx * cam.ix + ny * cam.iy + nz * cam.iz)
		local numJ = -(nx * cam.jx + ny * cam.jy + nz * cam.jz)
		if den < -1e-9 or den > 1e-9 then
			KIND[k] = if den < 0 then -1 else 1
			A0[k], AI[k], AJ[k] = num0 / den, numI / den, numJ / den
		else
			KIND[k] = 0
			A0[k], AI[k], AJ[k] = num0, numI, numJ
		end
	end
	local W = f.W
	local color, depth, ids = f.color, f.depth, f.id
	local bias = cam.bias
	local n = 0
	for j = y0, y1 do
		local row = j * W
		for i = x0, x1 do
			local tIn, tOut, best = -math.huge, math.huge, 0
			local inside = true
			for k = 1, np do
				local v = A0[k] + i * AI[k] + j * AJ[k]
				local kind = KIND[k]
				if kind < 0 then
					if v > tIn then
						tIn, best = v, k
					end
				elseif kind > 0 then
					if v < tOut then
						tOut = v
					end
				elseif v < -EDGE_EPS then
					inside = false
					break
				end
			end
			if inside and best > 0 and tIn > 0 and tIn <= tOut + T_EPS then
				local idx = row + i
				local o = idx * 4
				if tIn < buffer.readf32(depth, o) - bias then
					local b = best * 4
					local c = shade(rgb, planes[b - 3], planes[b - 2], planes[b - 1], i, j, tIn)
					if mix then
						buffer.writeu32(color, o, mix(c, buffer.readu32(color, o)))
					else
						buffer.writeu32(color, o, c)
						buffer.writef32(depth, o, tIn)
						buffer.writeu16(ids, idx * 2, id)
					end
					n += 1
				end
			end
		end
	end
	return n
end

------------------------------------------------------------------ any part
-- A part smaller than an art pixel (its box spans under 2 px both ways and covers no pixel centre) draws the pixel
-- under its centre, lit from above, depth-tested at its nearest point.
local function dot(f: Frame, cam: Cam, cf12: { number }, sx: number, sy: number, sz: number, rgb: number, id: number, shade: Shade, mix: Mix?): number
	local cx, cy, cz = cf12[1], cf12[2], cf12[3]
	local hx, hy, hz = sx * 0.5, sy * 0.5, sz * 0.5
	-- the box's screen extent: its centre's projection plus or minus the projected half axes (the projection is affine)
	local px, py, d = Raster.project(cam, cx, cy, cz)
	local k = cam.s / cam.K
	local rx, ry, rz, ux, uy, uz = cam.rx, cam.ry, cam.rz, cam.ux, cam.uy, cam.uz
	local spanX = (math.abs(cf12[4] * rx + cf12[7] * ry + cf12[10] * rz) * hx + math.abs(cf12[5] * rx + cf12[8] * ry + cf12[11] * rz) * hy
		+ math.abs(cf12[6] * rx + cf12[9] * ry + cf12[12] * rz) * hz) * k
	if spanX >= 1 then
		return 0 -- big enough to cover pixel centres: drawing nothing means it is hidden
	end
	local spanY = (math.abs(cf12[4] * ux + cf12[7] * uy + cf12[10] * uz) * hx + math.abs(cf12[5] * ux + cf12[8] * uy + cf12[11] * uz) * hy
		+ math.abs(cf12[6] * ux + cf12[9] * uy + cf12[12] * uz) * hz) * k
	if spanY >= 1 then
		return 0
	end
	local minX, maxX, minY, maxY = px - spanX, px + spanX, py - spanY, py + spanY
	if math.ceil(minX - 0.5) <= math.floor(maxX - 0.5) and math.ceil(minY - 0.5) <= math.floor(maxY - 0.5) then
		return 0 -- it covers a pixel centre (and was hidden there)
	end
	local i, j = math.floor(px), math.floor(py)
	if i < 0 or j < 0 or i >= f.W or j >= f.H then
		return 0
	end
	local t = d - math.min(hx, hy, hz)
	if t <= NEAR then
		return 0
	end
	local idx = j * f.W + i
	local o = idx * 4
	if t >= buffer.readf32(f.depth, o) - cam.bias then
		return 0
	end
	local c = shade(rgb, 0, 1, 0, i, j)
	if mix then
		buffer.writeu32(f.color, o, mix(c, buffer.readu32(f.color, o)))
	else
		buffer.writeu32(f.color, o, c)
		buffer.writef32(f.depth, o, t)
		buffer.writeu16(f.id, idx * 2, id)
	end
	return 1
end

-- Draw one part by its shape name: "Block", "Ball" (diameter min(sx, sy, sz)), "Cylinder", "Wedge",
-- "CornerWedge" (anything else draws as a Block). With `mix` the part is see-through (blends into the colour and
-- keeps the depth and id behind it). Sub-pixel parts draw one pixel (see dot). Returns the pixels written.
function Raster.drawPart(
	f: Frame,
	cam: Cam,
	shape: string,
	cf12: { number },
	sx: number,
	sy: number,
	sz: number,
	rgb: number,
	id: number,
	shade: Shade,
	mix: Mix?
): number
	local n: number
	if shape == "Ball" then
		n = Raster.drawSphere(f, cam, cf12[1], cf12[2], cf12[3], math.min(sx, sy, sz) * 0.5, rgb, id, shade, mix)
	elseif shape == "Cylinder" then
		n = Raster.drawCylinder(f, cam, cf12, sx, sy, sz, rgb, id, shade, mix)
	elseif shape == "Wedge" or shape == "CornerWedge" then
		n = Raster.drawConvex(f, cam, Raster.planes(shape, cf12, sx, sy, sz), cf12, sx, sy, sz, rgb, id, shade, mix)
	else
		n = Raster.drawBox(f, cam, cf12, sx, sy, sz, rgb, id, shade, mix)
	end
	if n == 0 then
		n = dot(f, cam, cf12, sx, sy, sz, rgb, id, shade, mix)
	end
	return n
end

------------------------------------------------------------------ shadows
-- floor(v * keep) for v = 0..255, per darkening factor (a few strengths are in use)
local darkTables: { [number]: { [number]: number } } = {}
local function darkTable(keep: number): { [number]: number }
	local t = darkTables[keep]
	if t == nil then
		t = {}
		for v = 0, 255 do
			t[v] = math.floor(v * keep)
		end
		darkTables[keep] = t
	end
	return t
end

-- Screen rect (inclusive, clipped) of the ellipse (radii rx, rz) on the horizontal plane at height y around (x, z);
-- all nil when off-screen or behind the ray plane.
function Raster.shadowRect(cam: Cam, x: number, y: number, z: number, rx: number, rz: number): (number?, number?, number?, number?)
	local px, py, d = Raster.project(cam, x, y, z)
	if d - math.abs(rx * cam.lx) - math.abs(rz * cam.lz) <= NEAR then
		return nil, nil, nil, nil
	end
	local k = cam.s / cam.K
	local spanX = (math.abs(rx * cam.rx) + math.abs(rz * cam.rz)) * k
	local spanY = (math.abs(rx * cam.ux) + math.abs(rz * cam.uz)) * k
	return clipRect(cam, px - spanX, py - spanY, px + spanX, py + spanY)
end

-- Darken the ellipse (radii rx, rz) on the horizontal plane at height y around (x, z), but only where the
-- visible surface actually lies on that plane (so shadows never paint over objects in front of them).
-- strength in [0, 1] is the darkening factor. The ellipse is solid to its edge (a checker-dithered rim read as a
-- jagged, noisy edge at pixel-art scale).
function Raster.drawShadow(f: Frame, cam: Cam, x: number, y: number, z: number, rx: number, rz: number, strength: number)
	if rx <= 0 or rz <= 0 or strength <= 0 then
		return
	end
	local ly = cam.ly
	if ly > -1e-9 and ly < 1e-9 then
		return -- the rays run parallel to the plane
	end
	local x0, y0, x1, y1 = Raster.shadowRect(cam, x, y, z, rx, rz)
	if x0 == nil or y0 == nil or x1 == nil or y1 == nil then
		return
	end
	local keep = 1 - math.clamp(strength, 0, 1)
	local dark = darkTable(keep)
	local W = f.W
	local color, depth = f.color, f.depth
	local invRx, invRz = 1 / rx, 1 / rz
	local invLy = 1 / ly
	local lx, lz = cam.lx, cam.lz
	local cox, coy, coz = cam.ox, cam.oy, cam.oz
	local cix, ciy, ciz = cam.ix, cam.iy, cam.iz
	local cjx, cjy, cjz = cam.jx, cam.jy, cam.jz
	-- along a row the hit point on the plane moves by a fixed step: (ux, uz) and t step linearly in i
	local tI = -ciy * invLy
	local uxI, uzI = (cix + tI * lx) * invRx, (ciz + tI * lz) * invRz
	for j = y0, y1 do
		local row = j * W
		-- the ray of pixel (x0, j) meets the plane at t = (y - O.y) / L.y
		local ox = cox + x0 * cix + j * cjx
		local oy = coy + x0 * ciy + j * cjy
		local oz = coz + x0 * ciz + j * cjz
		local t = (y - oy) * invLy
		local ux, uz = (ox + t * lx - x) * invRx, (oz + t * lz - z) * invRz
		for i = x0, x1 do
			if t > 0 and ux * ux + uz * uz <= 1 then
				local o = (row + i) * 4
				local dd = buffer.readf32(depth, o) - t
				if dd <= SHADOW_TOL and dd >= -SHADOW_TOL then
					local c = buffer.readu32(color, o)
					buffer.writeu32(
						color,
						o,
						dark[bit32.band(c, 0xFF)] + dark[bit32.band(bit32.rshift(c, 8), 0xFF)] * 256 + dark[bit32.band(bit32.rshift(c, 16), 0xFF)] * 65536 + 0xFF000000
					)
				end
			end
			t += tI
			ux += uxI
			uz += uzI
		end
	end
end

return Raster
