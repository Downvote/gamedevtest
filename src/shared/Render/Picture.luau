--!strict
--!native
-- Pixel-art pictures of part assemblies (the engine of Pixel/Snapshot): the world's look drawn analytically with
-- Raster's solids, into a small RGBA picture with a transparent background (ARCHITECTURE 11.10). OWNER: WP8. Pure.
--
-- Same look as the world: Shading.toon (3 bands, Bayer dither at band edges, sky/ground hint, palette LUT), sun
-- shadows cast inside the model, 1 px ink outline. Colours come from the fixed day palette (Shading's `day`
-- context), so a picture does not change with the world's night or season tint.
--
-- Use
--   local solids = { Picture.solid("Cylinder", cf12, sx, sy, sz, 0xRRGGBB, glow, alpha), ... }
--   local cams = Picture.fit({ rot12 }, solids, W, H, pad, scale?)  -- one orthographic camera per rotation
--   local job = Picture.new(solids, cams[1], { outline = "outer", shadows = true })
--   repeat until Picture.step(job, os.clock() + budget)             -- time-sliced; true when done
--   job.pixels                                                      -- W * H * 4 bytes, packed RGBA (R low byte)
-- Steps of a job: (1) opaque solids into a G-buffer (depth, id, albedo, exact normal), (2) per row: sun visibility
-- (one shadow ray per lit pixel against every other solid, bounding-sphere culled) and toon shading, (3) see-through
-- solids blended on top (Shading.blend), (4) the ink outline: inner edges where the depth steps by more than
-- `edge` art px, and the silhouette either outside the model ("outer", the icon look: background pixels next to the
-- model turn ink, so nothing of the model is lost) or on its rim ("inner", the world's way) or not at all ("none").
local Raster = require(script.Parent.Raster)
local Shading = require(script.Parent.Shading)

export type Solid = {
	shape: string, -- "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge" (anything else is a Block)
	cf: { number }, -- cf12: position and rotation
	sx: number,
	sy: number,
	sz: number,
	rgb: number, -- albedo 0xRRGGBB
	glow: boolean, -- Neon: emissive (always the lit band, never shadowed)
	alpha: number, -- opacity (1 - Transparency): 1 opaque, below 1 see-through
	-- derived: bounding sphere and, for convex shapes, the world planes
	bx: number,
	by: number,
	bz: number,
	br: number,
	planes: { number }?,
}

export type Options = {
	outline: string?, -- "outer" (default) | "inner" | "none"
	shadows: boolean?, -- sun shadows inside the model (default true)
	edge: number?, -- inner ink edges where the depth steps by more than this many art px (default 3)
}

export type Job = {
	W: number,
	H: number,
	cam: Raster.Cam,
	solids: { Solid },
	opaque: { number }, -- indices into solids
	clear: { number }, -- see-through ones
	outline: string,
	shadows: boolean,
	edgeTol: number, -- studs
	frame: Raster.Frame,
	albedo: buffer, -- u32 0xRRGGBB (+ GLOW flag)
	normal: buffer, -- 3 x f32 per pixel
	phase: number, -- 1 opaque, 2 shade, 3 see-through, 4 outline, 5 done
	cursor: number,
	pixels: buffer, -- the result (frame.color), valid once done
	done: boolean,
	shadowGrid: ShadowGrid?, -- phase 2's shadow candidates (made when it starts)
	lastBlock: number, -- the solid that shaded the last shadowed pixel (tried first: neighbours share their shade)
}

-- The opaque solids that can shade (not glowing), binned across the sun: seen down the sun's direction each one's
-- bounding sphere is a disc, and only a solid whose disc holds a point can block that point's shadow ray, so the
-- point's cell lists every solid that might (in drawing order; `blocks` still decides).
export type ShadowGrid = {
	u0: number,
	v0: number,
	inv: number, -- cells per stud
	n: number, -- n x n cells
	cells: { { number } },
	top: { [number]: number }, -- each solid's highest point (studs; a wedge's box): one wholly below a point cannot shade it
}

local Picture = {}

local GLOW = 0x1000000
local FAR = 1e30
local BG_DEPTH = -1e9 -- the background, for the outer outline: nearer than everything, so its edge pixels ink
local SHADOW_LEN = 60 -- studs
local SHADOW_LIFT = 0.02 -- shadow rays start this far off the surface
local HIT_EPS = 1e-3
local BIAS = 0.003 -- depth-test bias (studs); pictures are small, so much finer than the world's
local CHECK = 1 -- solids / rows between clock checks (a shaded row of a 96 px picture can take a millisecond)
local SUN = Shading.SUN
local SX, SY, SZ = SUN.x, SUN.y, SUN.z
-- two unit vectors across the sun (with it, an orthonormal frame): a point's place seen down the sun
local UX, UY, UZ, VX, VY, VZ
do
	local ax, ay, az = 0, 0, 1
	if math.abs(SZ) > 0.9 then
		ax, ay, az = 1, 0, 0
	end
	local cx, cy, cz = SY * az - SZ * ay, SZ * ax - SX * az, SX * ay - SY * ax
	local l = math.sqrt(cx * cx + cy * cy + cz * cz)
	UX, UY, UZ = cx / l, cy / l, cz / l
	VX, VY, VZ = SY * UZ - SZ * UY, SZ * UX - SX * UZ, SX * UY - SY * UX
end
local GRID_N = 12 -- shadow grid cells a side

------------------------------------------------------------------ solids
-- The Raster.drawPart shape of a part from its ClassName and, for a Part, its Shape enum name (WedgePart and
-- CornerWedgePart, Part shapes Ball / Cylinder / Wedge / CornerWedge; everything else, MeshParts and unions too,
-- draws as its box).
function Picture.shape(className: string, partType: string?): string
	if className == "WedgePart" then
		return "Wedge"
	elseif className == "CornerWedgePart" then
		return "CornerWedge"
	elseif partType == "Ball" or partType == "Cylinder" or partType == "Wedge" or partType == "CornerWedge" then
		return partType
	end
	return "Block"
end

-- One part of a picture. alpha (default 1) is 1 - Transparency.
function Picture.solid(shape: string, cf12: { number }, sx: number, sy: number, sz: number, rgb: number, glow: boolean?, alpha: number?): Solid
	local s: Solid = {
		shape = shape,
		cf = cf12,
		sx = sx,
		sy = sy,
		sz = sz,
		rgb = rgb,
		glow = glow == true,
		alpha = math.clamp(alpha or 1, 0, 1),
		bx = cf12[1],
		by = cf12[2],
		bz = cf12[3],
		br = 0.5 * math.sqrt(sx * sx + sy * sy + sz * sz),
		planes = nil,
	}
	if shape == "Ball" then
		s.br = 0.5 * math.min(sx, sy, sz)
	elseif shape ~= "Cylinder" then
		s.planes = Raster.planes(shape, cf12, sx, sy, sz)
	end
	return s
end

-- The solid's extent along the unit direction (ex, ey, ez): the centre's coordinate and the half width (exact for
-- balls, cylinders and boxes; a wedge uses its box).
local function extent(s: Solid, ex: number, ey: number, ez: number): (number, number)
	local c = s.cf
	local mid = c[1] * ex + c[2] * ey + c[3] * ez
	if s.shape == "Ball" then
		return mid, s.br
	end
	local ax = c[4] * ex + c[7] * ey + c[10] * ez
	if s.shape == "Cylinder" then
		local r = math.min(s.sy, s.sz) * 0.5
		return mid, s.sx * 0.5 * math.abs(ax) + r * math.sqrt(math.max(0, 1 - ax * ax))
	end
	local ay = c[5] * ex + c[8] * ey + c[11] * ez
	local az = c[6] * ex + c[9] * ey + c[12] * ez
	return mid, 0.5 * (s.sx * math.abs(ax) + s.sy * math.abs(ay) + s.sz * math.abs(az))
end

-- The extent of all solids along a direction: min and max.
local function span(solids: { Solid }, ex: number, ey: number, ez: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, s in solids do
		local mid, half = extent(s, ex, ey, ez)
		lo, hi = math.min(lo, mid - half), math.max(hi, mid + half)
	end
	return lo, hi
end

------------------------------------------------------------------ framing
-- Orthographic cameras that frame the solids in a W x H picture with `pad` art px free on every side, one per
-- rotation in `rots` (cf12 rotations, position ignored). One rotation: the model's projected silhouette box is
-- centred and fills the picture. Several (a turntable): every view shares one scale and centres the solids'
-- world box centre, so the model turns in place without changing size. `scale` (art px per stud) fixes the size
-- instead of fitting. `anchor` ({x, y} art px from the picture's top-left corner; with `scale` only) is where the
-- world origin lands in every view instead of centring: pictures of different models at one scale and anchor line
-- up (a character's feet stay put whatever it wears).
function Picture.fit(rots: { { number } }, solids: { Solid }, W: number, H: number, pad: number, scale: number?, anchor: { number }?): { Raster.Cam }
	local cams: { Raster.Cam } = {}
	if #solids == 0 then
		for _, r in rots do
			local c = table.clone(r)
			c[1], c[2], c[3] = 0, 0, 0
			table.insert(cams, Raster.cam(c, H, W, H, 1, 1))
		end
		return cams
	end
	local x0, x1 = span(solids, 1, 0, 0)
	local y0, y1 = span(solids, 0, 1, 0)
	local z0, z1 = span(solids, 0, 0, 1)
	local bx, by, bz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
	local halfW, halfH = math.max(0.5, W / 2 - pad), math.max(0.5, H / 2 - pad)
	-- per rotation: the centre (along R, U, L) and the scale that fits
	local centres: { { number } } = {}
	local fitScale = math.huge
	for _, r in rots do
		local rx, ry, rz = r[4], r[7], r[10]
		local ux, uy, uz = r[5], r[8], r[11]
		local lx, ly, lz = -r[6], -r[9], -r[12]
		local uMin, uMax = span(solids, rx, ry, rz)
		local vMin, vMax = span(solids, ux, uy, uz)
		local uC, vC
		if #rots == 1 then
			uC, vC = (uMin + uMax) / 2, (vMin + vMax) / 2
		else
			uC, vC = bx * rx + by * ry + bz * rz, bx * ux + by * uy + bz * uz
		end
		local du = math.max(uMax - uC, uC - uMin, 1e-6)
		local dv = math.max(vMax - vC, vC - vMin, 1e-6)
		fitScale = math.min(fitScale, halfW / du, halfH / dv)
		table.insert(centres, { uC, vC, bx * lx + by * ly + bz * lz })
	end
	local fixed = scale ~= nil and scale > 0
	local s = if fixed then scale :: number else fitScale
	for k, r in rots do
		local rx, ry, rz = r[4], r[7], r[10]
		local ux, uy, uz = r[5], r[8], r[11]
		local lx, ly, lz = -r[6], -r[9], -r[12]
		local uC, vC, lC = centres[k][1], centres[k][2], centres[k][3]
		if anchor ~= nil and fixed then
			-- the origin projects to (W / 2 - uC * s, H / 2 + vC * s)
			uC, vC = (W / 2 - anchor[1]) / s, (anchor[2] - H / 2) / s
		end
		local cx, cy, cz = rx * uC + ux * vC + lx * lC, ry * uC + uy * vC + ly * lC, rz * uC + uz * vC + lz * lC
		-- rays start in front of every solid
		local lMin = span(solids, lx, ly, lz)
		local c = table.clone(r)
		c[1], c[2], c[3] = cx, cy, cz
		local cam = Raster.cam(c, H / s, W, H, 1, math.max(0, lC - lMin) + 1)
		cam.bias = BIAS
		table.insert(cams, cam)
	end
	return cams
end

------------------------------------------------------------------ shadow rays
-- Does the ray o + t d (unit d, 0 < t < len) pass through solid s?
local function blocks(s: Solid, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, len: number): boolean
	-- bounding sphere
	local wx, wy, wz = s.bx - ox, s.by - oy, s.bz - oz
	local proj = wx * dx + wy * dy + wz * dz
	local br = s.br
	if proj < -br or proj > len + br then
		return false
	end
	if wx * wx + wy * wy + wz * wz - proj * proj > br * br then
		return false
	end
	if s.shape == "Ball" then
		local qx, qy, qz = -wx, -wy, -wz
		local b = qx * dx + qy * dy + qz * dz
		local disc = b * b - (qx * qx + qy * qy + qz * qz - br * br)
		if disc < 0 then
			return false
		end
		local sq = math.sqrt(disc)
		return -b + sq > HIT_EPS and -b - sq < len
	end
	local planes = s.planes
	if planes then
		local tIn, tOut = 0, len
		for k = 1, #planes, 4 do
			local nx, ny, nz = planes[k], planes[k + 1], planes[k + 2]
			local den = nx * dx + ny * dy + nz * dz
			local num = planes[k + 3] - (nx * ox + ny * oy + nz * oz)
			if den > -1e-12 and den < 1e-12 then
				if num < 0 then
					return false
				end
			else
				local t = num / den
				if den < 0 then
					if t > tIn then
						tIn = t
					end
				elseif t < tOut then
					tOut = t
				end
				if tIn > tOut then
					return false
				end
			end
		end
		return tOut > HIT_EPS
	end
	-- cylinder along the part's X axis
	local c = s.cf
	local ax, ay, az = c[4], c[7], c[10]
	local h, r = s.sx * 0.5, math.min(s.sy, s.sz) * 0.5
	local qx, qy, qz = -wx, -wy, -wz
	local qa = qx * ax + qy * ay + qz * az
	local da = dx * ax + dy * ay + dz * az
	local tIn, tOut = 0, len
	if da > 1e-12 or da < -1e-12 then
		local s1, s2 = (-h - qa) / da, (h - qa) / da
		if s1 > s2 then
			s1, s2 = s2, s1
		end
		tIn, tOut = math.max(tIn, s1), math.min(tOut, s2)
	elseif qa > h or qa < -h then
		return false
	end
	local A = 1 - da * da
	local perp2 = qx * qx + qy * qy + qz * qz - qa * qa
	if A > 1e-12 then
		local b = qx * dx + qy * dy + qz * dz - qa * da
		local disc = b * b - A * (perp2 - r * r)
		if disc < 0 then
			return false
		end
		local sq = math.sqrt(disc)
		tIn, tOut = math.max(tIn, (-b - sq) / A), math.min(tOut, (-b + sq) / A)
	elseif perp2 > r * r then
		return false
	end
	return tIn <= tOut and tOut > HIT_EPS
end

------------------------------------------------------------------ job
function Picture.new(solids: { Solid }, cam: Raster.Cam, opts: Options?): Job
	local o: Options = opts or {}
	local W, H = cam.W, cam.H
	local n = W * H
	local depth = buffer.create(n * 4)
	for i = 0, n - 1 do
		buffer.writef32(depth, i * 4, FAR)
	end
	local frame: Raster.Frame = { W = W, H = H, color = buffer.create(n * 4), depth = depth, id = buffer.create(n * 2) }
	local opaque, clear = {}, {}
	for i, s in solids do
		if s.alpha >= 0.999 then
			table.insert(opaque, i)
		elseif s.alpha > 0.05 then
			table.insert(clear, i)
		end
	end
	local edge = o.edge or 3
	return {
		W = W,
		H = H,
		cam = cam,
		solids = solids,
		opaque = opaque,
		clear = clear,
		outline = o.outline or "outer",
		shadows = o.shadows ~= false,
		edgeTol = math.clamp(edge / math.max(cam.s, 1e-6), 0.05, 0.75),
		frame = frame,
		albedo = buffer.create(n * 4),
		normal = buffer.create(n * 12),
		phase = 1,
		cursor = 1,
		pixels = frame.color,
		done = false,
		shadowGrid = nil,
		lastBlock = 0,
	}
end

-- Phase 1: one opaque solid into the G-buffer (colour is written in phase 2).
local function rasterSolid(job: Job, k: number)
	local s = job.solids[k]
	local W = job.W
	local albedo, normal = job.albedo, job.normal
	local flag = if s.glow then GLOW else 0
	local function capture(rgb: number, nx: number, ny: number, nz: number, x: number, y: number): number
		local idx = y * W + x
		buffer.writeu32(albedo, idx * 4, rgb + flag)
		buffer.writef32(normal, idx * 12, nx)
		buffer.writef32(normal, idx * 12 + 4, ny)
		buffer.writef32(normal, idx * 12 + 8, nz)
		return 0
	end
	Raster.drawPart(job.frame, job.cam, s.shape, s.cf, s.sx, s.sy, s.sz, s.rgb, k, capture)
end

-- The job's ShadowGrid (margins a little wider than the discs, so rounding never drops a solid that blocks).
local function shadowGrid(job: Job): ShadowGrid
	local solids = job.solids
	local u0, v0, u1, v1 = math.huge, math.huge, -math.huge, -math.huge
	local boxes: { { number } } = {}
	local top: { [number]: number } = {}
	for _, k in job.opaque do
		local s = solids[k]
		if not s.glow then
			local mid, half = extent(s, 0, 1, 0)
			top[k] = math.min(s.by + s.br, mid + half + 1e-4)
			local cu = s.bx * UX + s.by * UY + s.bz * UZ
			local cv = s.bx * VX + s.by * VY + s.bz * VZ
			local r = s.br * 1.001 + 1e-3
			table.insert(boxes, { k, cu - r, cv - r, cu + r, cv + r })
			u0, v0 = math.min(u0, cu - r), math.min(v0, cv - r)
			u1, v1 = math.max(u1, cu + r), math.max(v1, cv + r)
		end
	end
	local n = GRID_N
	local inv = n / math.max(u1 - u0, v1 - v0, 1e-6)
	local cells: { { number } } = table.create(n * n)
	for i = 1, n * n do
		cells[i] = {}
	end
	for _, b in boxes do
		local a0 = math.clamp(math.floor((b[2] - u0) * inv), 0, n - 1)
		local a1 = math.clamp(math.floor((b[4] - u0) * inv), 0, n - 1)
		local c0 = math.clamp(math.floor((b[3] - v0) * inv), 0, n - 1)
		local c1 = math.clamp(math.floor((b[5] - v0) * inv), 0, n - 1)
		for cv = c0, c1 do
			for cu = a0, a1 do
				table.insert(cells[cv * n + cu + 1], b[1])
			end
		end
	end
	return { u0 = u0, v0 = v0, inv = inv, n = n, cells = cells, top = top }
end

-- Phase 2: sun visibility and toon shading of row y.
local function shadeRow(job: Job, y: number)
	local f = job.frame
	local W, cam = job.W, job.cam
	local color, depth, ids = f.color, f.depth, f.id
	local albedo, normal = job.albedo, job.normal
	local solids = job.solids
	local grid = job.shadowGrid
	if grid == nil and job.shadows then
		grid = shadowGrid(job)
		job.shadowGrid = grid
	end
	local gu0, gv0, ginv, gn = 0, 0, 0, 0
	local cells: { { number } } = {}
	local top: { [number]: number } = {}
	if grid then
		gu0, gv0, ginv, gn, cells, top = grid.u0, grid.v0, grid.inv, grid.n, grid.cells, grid.top
	end
	local gox, goy, goz = cam.gox, cam.goy, cam.goz
	local ix, iy, iz, jx, jy, jz = cam.ix, cam.iy, cam.iz, cam.jx, cam.jy, cam.jz
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local gj = y + cam.gy
	local gx = cam.gx
	for x = 0, W - 1 do
		local idx = y * W + x
		local id = buffer.readu16(ids, idx * 2)
		if id > 0 then
			local a = buffer.readu32(albedo, idx * 4)
			local nx = buffer.readf32(normal, idx * 12)
			local ny = buffer.readf32(normal, idx * 12 + 4)
			local nz = buffer.readf32(normal, idx * 12 + 8)
			local lit = 1
			if a >= GLOW then
				lit = 2
			elseif grid and nx * SX + ny * SY + nz * SZ > 0 then
				local t = buffer.readf32(depth, idx * 4)
				-- (Raster.origin)
				local gi = x + gx
				local ox, oy, oz = gox + gi * ix + gj * jx, goy + gi * iy + gj * jy, goz + gi * iz + gj * jz
				local px = ox + lx * t + nx * SHADOW_LIFT
				local py = oy + ly * t + ny * SHADOW_LIFT
				local pz = oz + lz * t + nz * SHADOW_LIFT
				local cu = math.floor((px * UX + py * UY + pz * UZ - gu0) * ginv)
				local cv = math.floor((px * VX + py * VY + pz * VZ - gv0) * ginv)
				if cu >= 0 and cu < gn and cv >= 0 and cv < gn then
					local last = job.lastBlock
					if last ~= id and last > 0 and top[last] > py and blocks(solids[last], px, py, pz, SX, SY, SZ, SHADOW_LEN) then
						lit = 0
					else
						for _, k in cells[cv * gn + cu + 1] do
							-- the sun is above: a solid wholly below the point cannot shade it
							if k ~= id and k ~= last and top[k] > py and blocks(solids[k], px, py, pz, SX, SY, SZ, SHADOW_LEN) then
								lit = 0
								job.lastBlock = k
								break
							end
						end
					end
				end
			end
			buffer.writeu32(color, idx * 4, Shading.toon(bit32.band(a, 0xFFFFFF), nx, ny, nz, lit, x, y, true))
		end
	end
end

local function shadeLit(rgb: number, nx: number, ny: number, nz: number, x: number, y: number): number
	return Shading.toon(rgb, nx, ny, nz, 1, x, y, true)
end
local function shadeGlow(rgb: number, nx: number, ny: number, nz: number, x: number, y: number): number
	return Shading.toon(rgb, nx, ny, nz, 2, x, y, true)
end

-- Phase 3: one see-through solid blended on top (keeps the depth and id behind it).
local function clearSolid(job: Job, k: number)
	local s = job.solids[k]
	local a = s.alpha
	local function mix(over: number, under: number): number
		return Shading.blend(over, under, a, true)
	end
	Raster.drawPart(job.frame, job.cam, s.shape, s.cf, s.sx, s.sy, s.sz, s.rgb, 0, if s.glow then shadeGlow else shadeLit, mix)
end

-- Phase 4: ink.
local function outline(job: Job)
	if job.outline == "none" then
		return
	end
	local f = job.frame
	local W, H = job.W, job.H
	if job.outline == "outer" then
		local depth, ids = f.depth, f.id
		for i = 0, W * H - 1 do
			if buffer.readu16(ids, i * 2) == 0 then
				buffer.writef32(depth, i * 4, BG_DEPTH)
			end
		end
	end
	Shading.outline(f, 0, 0, W - 1, H - 1, nil, job.edgeTol)
end

-- Work on the job until os.clock() reaches `deadline` (at least a little each call). Returns true when done.
function Picture.step(job: Job, deadline: number): boolean
	local guard = 0
	while not job.done do
		guard += 1
		if job.phase == 1 then
			local k = job.opaque[job.cursor]
			if k == nil then
				job.phase, job.cursor = 2, 0
			else
				rasterSolid(job, k)
				job.cursor += 1
			end
		elseif job.phase == 2 then
			if job.cursor >= job.H then
				job.phase, job.cursor = 3, 1
			else
				shadeRow(job, job.cursor)
				job.cursor += 1
			end
		elseif job.phase == 3 then
			local k = job.clear[job.cursor]
			if k == nil then
				job.phase = 4
			else
				clearSolid(job, k)
				job.cursor += 1
			end
		else
			outline(job)
			job.phase = 5
			job.done = true
		end
		if guard % CHECK == 0 and os.clock() >= deadline then
			break
		end
	end
	return job.done
end

-- Draw a whole picture at once (specs, tools).
function Picture.render(solids: { Solid }, cam: Raster.Cam, opts: Options?): buffer
	local job = Picture.new(solids, cam, opts)
	while not Picture.step(job, math.huge) do
	end
	return job.pixels
end

return Picture
