-- tests/specs/Raster.spec.luau (WP8): the 2:1 orthographic camera (rotation, the pixel scale rule, the convex hull and
-- the HUD-aware outline fit, projection and its inverse ray, the top-left art grid; the world-anchored grid: exact 2:1
-- slopes, scale and phase snapping, pans that keep every global pixel's ray, clean steps and outlines on 2:1 edges, the
-- Close view's follow rules), box / sphere / cylinder / wedge / corner wedge coverage with exact depth (checked against
-- independent ray intersections), sub-pixel dots, see-through blending, depth testing, floor shadows; and
-- Render/Picture (Snapshot's engine).
local T = require("../TestKit")
local Raster = require("../../build/luautest/shared/Render/Raster")
local Picture = require("../../build/luautest/shared/Render/Picture")
local Shading = require("../../build/luautest/shared/Render/Shading")
local Tuning = require("../../build/luautest/shared/Config/Tuning")

local ISO_PITCH = Tuning.CamPitch -- the live camera: 30 degrees (2:1 dimetric)
-- Fixture framing: the shop's outline boxes (OUTLINE) with a test pad in screen px (the live pad is
-- Tuning.CamPad art px; the live blocks are the HUD's)
local PAD, BACK = 12, 150
-- the live pixel scale rule (Tuning.PixelScaleMin / PixelScaleSides, PixelTiers h, the EditableImage limit)
local K_MIN, K_SIDES, MAX_IMAGE = 2, { 820, 1250, 1700, 2100 }, 1024
local H_LOW, H_MEDIUM, H_HIGH = 270, 400, 540

local function constShade(color: number)
	return function(_rgb: number, _nx: number, _ny: number, _nz: number, _x: number, _y: number): number
		return color
	end
end

-- cf12 with the iso rotation and the given position (the view centre)
local function isoCf(x: number, y: number, z: number): { number }
	local c = Raster.rotation(45, ISO_PITCH)
	c[1], c[2], c[3] = x, y, z
	return c
end

local function cfYaw(x: number, y: number, z: number, yaw: number): { number }
	-- CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0) components
	local c, s = math.cos(yaw), math.sin(yaw)
	return { x, y, z, c, 0, s, 0, 1, 0, -s, 0, c }
end

-- Fixture: the outline boxes of a 44 x 34 stud room with two back walls and half walls at the front (the framing
-- numbers below are worked out for these boxes)
type OBox = { min: { x: number, y: number, z: number }, max: { x: number, y: number, z: number } }
local function B(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): OBox
	return { min = { x = x0, y = y0, z = z0 }, max = { x = x1, y = y1, z = z1 } }
end
local OUTLINE: { OBox } = {
	B(-22, -0.5, -17, 22, 0, 17), -- floor slab
	B(-22.5, 0, -17.5, 22.5, 8, -16.5), -- north wall
	B(-22.5, 0, -16.5, -21.5, 8, 17.5), -- west wall
	B(-23.25, 8, -18.25, 22.5, 8.5, -16.25), -- north crown
	B(-23.25, 8, -16.25, -21.25, 8.5, 17.5), -- west crown
	B(-21.5, 0, 16.375, 22.5, 2.5, 17.625), -- south half wall
	B(21.375, 0, -16.5, 22.625, 2.5, 16.5), -- east half wall
	B(-21.5, -0.25, 17.5, 22.5, 0.25, 17.75), -- south plinth
	B(22.5, -0.25, -16.5, 22.75, 0.25, 16.5), -- east plinth
	B(-10.75, 0, 16.125, -5.25, 4.25, 17.875), -- door posts
	B(-10, -0.5, 17, -6, 0, 18.5), -- door step
}

-- the corners of the OUTLINE fixture's boxes on a plot at (ox, 0, oz), flat x, y, z
local function outlinePts(ox: number, oz: number): { number }
	local pts = {}
	for _, b in OUTLINE do
		for _, x in { b.min.x, b.max.x } do
			for _, y in { b.min.y, b.max.y } do
				for _, z in { b.min.z, b.max.z } do
					table.insert(pts, ox + x)
					table.insert(pts, y)
					table.insert(pts, oz + z)
				end
			end
		end
	end
	return pts
end

-- Slab-method ray / oriented box intersection in box-local space. Returns t (or nil) and the minimum
-- distance of the hit point to the hit face's border (edge ambiguity), for an origin outside the box.
local function rayBox(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number, cf: { number }, size: { number }): (number?, number)
	local axes = { { cf[4], cf[7], cf[10] }, { cf[5], cf[8], cf[11] }, { cf[6], cf[9], cf[12] } }
	local qx, qy, qz = ox - cf[1], oy - cf[2], oz - cf[3]
	local tmin, tmax = -math.huge, math.huge
	local o, d = {}, {}
	for k = 1, 3 do
		local a = axes[k]
		o[k] = qx * a[1] + qy * a[2] + qz * a[3]
		d[k] = dx * a[1] + dy * a[2] + dz * a[3]
		local h = size[k] / 2
		if math.abs(d[k]) < 1e-12 then
			if math.abs(o[k]) > h then
				return nil, math.abs(o[k]) - h -- parallel to that slab and outside it
			end
		else
			local t1, t2 = (-h - o[k]) / d[k], (h - o[k]) / d[k]
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			tmin = math.max(tmin, t1)
			tmax = math.min(tmax, t2)
		end
	end
	if tmin > tmax or tmin <= 0 then
		-- report how close the ray came to grazing the box, to skip edge-ambiguous pixels
		return nil, math.abs(tmin - tmax)
	end
	local border = math.huge
	for k = 1, 3 do
		local p = o[k] + tmin * d[k]
		local gap = size[k] / 2 - math.abs(p)
		if gap > 1e-6 then
			border = math.min(border, gap)
		end
	end
	return tmin, border
end

-- a small iso camera looking at the origin: 320 x 180 full-screen px, K = 2, 12 studs tall
local function smallCam(): Raster.Cam
	return Raster.cam(isoCf(0, 1, 0), 12, 320, 180, 2, BACK)
end

return function()
	T.it("2:1 rotation: CFrame.lookAt axes of yaw 45, pitch 30", function()
		T.eq(Tuning.CamPitch, 30, "the live pitch")
		T.eq(Tuning.CamYaw, 45, "the live yaw")
		local c = Raster.rotation(45, 30)
		local r2, c30 = 1 / math.sqrt(2), math.cos(math.rad(30))
		-- right (1, 0, -1)/sqrt 2, up (-sin 30, sqrt 2 cos 30, -sin 30)/sqrt 2, back (cos 30, sqrt 2 sin 30, cos 30)/sqrt 2
		T.near(c[4], r2, 1e-12)
		T.near(c[7], 0, 1e-12)
		T.near(c[10], -r2, 1e-12)
		T.near(c[5], -0.5 * r2, 1e-12)
		T.near(c[8], c30, 1e-12)
		T.near(c[11], -0.5 * r2, 1e-12)
		T.near(c[6], c30 * r2, 1e-12)
		T.near(c[9], 0.5, 1e-12)
		T.near(c[12], c30 * r2, 1e-12)
		-- the old true isometric pitch still gives the (1, 1, 1)/sqrt 3 view
		local iso = Raster.rotation(45, math.deg(math.atan(1 / math.sqrt(2))))
		T.near(iso[6], 1 / math.sqrt(3), 1e-12)
		T.near(iso[9], 1 / math.sqrt(3), 1e-12)
	end)

	T.it("floor edges run at an exact 2:1 slope, verticals stay vertical, equal lengths stay equal", function()
		local cam = Raster.cam(isoCf(0, 0, 0), 20, 1920, 1080, 1, BACK)
		local x0, y0 = Raster.project(cam, 0, 0, 0)
		local xa, ya = Raster.project(cam, 4, 0, 0) -- east
		local xb, yb = Raster.project(cam, 0, 0, 4) -- south
		local xc, yc = Raster.project(cam, 0, 4, 0) -- up
		T.near((ya - y0) / (xa - x0), 0.5, 1e-12, "x axis goes right 2 for every 1 down")
		T.near((yb - y0) / (x0 - xb), 0.5, 1e-12, "z axis goes left 2 for every 1 down")
		T.near(xc, x0, 1e-9, "verticals stay vertical")
		T.truthy(yc < y0, "up is up")
		T.near((y0 - yc) / (xa - x0), math.sqrt(1.5), 1e-12, "a stud up is sqrt 1.5 times a stud east across")
		local la = math.sqrt((xa - x0) ^ 2 + (ya - y0) ^ 2)
		local lb = math.sqrt((xb - x0) ^ 2 + (yb - y0) ^ 2)
		T.near(la, lb, 1e-9, "x and z foreshorten alike")
	end)

	T.it("cam geometry: the art grid starts at the top-left corner, overscan below K", function()
		local cam = Raster.cam(isoCf(3, 2, 1), 10, 200, 100, 7, BACK)
		T.eq(cam.W, 29)
		T.eq(cam.H, 15)
		T.eq(cam.offX, 0, "no fractional offset")
		T.eq(cam.offY, 0)
		T.truthy(cam.W * 7 - 200 < 7 and cam.H * 7 - 100 < 7, "overscan under one art pixel")
		T.near(cam.s, 10, 1e-9, "100 px over 10 studs")
		T.near(cam.bias, 0.03, 1e-12, "world depth bias")
		-- the view centre lands on the full-screen centre at depth `back`
		local px, py, d = Raster.project(cam, 3, 2, 1)
		T.near(px * 7, 100, 1e-9)
		T.near(py * 7, 50, 1e-9)
		T.near(d, BACK, 1e-9)
		-- art pixel (i, j) covers full-screen [iK, (i+1)K): its ray passes through the screen point (i + 0.5) K
		local ox, oy, oz = Raster.origin(cam, 4, 6)
		local sx, sy, sz = Raster.screenOrigin(cam, 4.5 * 7, 6.5 * 7)
		T.near(ox, sx, 1e-9)
		T.near(oy, sy, 1e-9)
		T.near(oz, sz, 1e-9)
	end)

	T.it("pixel scale: one size per screen, tiers only coarsen it", function()
		local function k(w: number, h: number, cap: number?): number
			return Raster.pixelScale(w, h, K_MIN, K_SIDES, cap, MAX_IMAGE)
		end
		-- the screen rule (no tier cap)
		T.eq(k(844, 390), 2, "landscape phone")
		T.eq(k(390, 844), 2, "portrait phone: the short side decides")
		T.eq(k(1024, 768), 2, "tablet 4:3")
		T.eq(k(1366, 768), 2, "laptop 768p")
		T.eq(k(1440, 900), 3, "900p")
		T.eq(k(1920, 1080), 3, "1080p")
		T.eq(k(2560, 1440), 4, "1440p")
		T.eq(k(3840, 2160), 6, "4K")
		-- medium and high never change it on these screens
		for _, sz in { { 844, 390 }, { 390, 844 }, { 1024, 768 }, { 1366, 768 }, { 1920, 1080 }, { 2560, 1080 }, { 2560, 1440 }, { 3440, 1440 }, { 3840, 2160 } } do
			T.eq(k(sz[1], sz[2], H_MEDIUM), k(sz[1], sz[2]), "medium " .. sz[1] .. "x" .. sz[2])
			T.eq(k(sz[1], sz[2], H_HIGH), k(sz[1], sz[2]), "high " .. sz[1] .. "x" .. sz[2])
		end
		-- low coarsens big screens only (phones keep K 2 so the UI fits)
		T.eq(k(844, 390, H_LOW), 2, "low phone")
		T.eq(k(1920, 1080, H_LOW), 4, "low 1080p")
		T.eq(k(1366, 768, H_LOW), 3, "low laptop")
		-- the EditableImage limit
		T.eq(k(5120, 1440, H_MEDIUM), 5, "32:9 at 1440 needs K 5 to stay within 1024 px")
		for _, sz in { { 844, 390 }, { 1920, 1080 }, { 5120, 1440 }, { 7680, 4320 } } do
			local kk = k(sz[1], sz[2], H_LOW)
			T.truthy(math.ceil(sz[1] / kk) <= MAX_IMAGE and math.ceil(sz[2] / kk) <= MAX_IMAGE, "layer within the image limit")
		end
		T.eq(Raster.pixelScale(100, 100, 2, {}, nil, nil), 2, "minimum")
	end)

	T.it("project and the pixel ray are inverse, with depth = distance along the ray", function()
		local cam = Raster.cam(isoCf(-770, 0.5, 2), 27.3, 1920, 1080, 3, BACK)
		for j = 0, cam.H - 1, 37 do
			for i = 0, cam.W - 1, 53 do
				local ox, oy, oz = Raster.origin(cam, i, j)
				-- the origin itself sits on the ray plane: depth 0, on the pixel centre
				local px, py, d0 = Raster.project(cam, ox, oy, oz)
				T.near(px, i + 0.5, 1e-6, "x")
				T.near(py, j + 0.5, 1e-6, "y")
				T.near(d0, 0, 1e-6, "on the plane")
				for _, t in { 10, 150, 333 } do
					local qx, qy, qz = Raster.project(cam, ox + cam.lx * t, oy + cam.ly * t, oz + cam.lz * t)
					T.near(qx, i + 0.5, 1e-6)
					T.near(qy, j + 0.5, 1e-6)
					T.near(qz, t, 1e-6, "depth is the ray distance")
				end
				-- the full-screen form gives the same origin
				local sx, sy = (i + 0.5) * cam.K - cam.offX, (j + 0.5) * cam.K - cam.offY
				local ax, ay, az = Raster.screenOrigin(cam, sx, sy)
				T.near(ax, ox, 1e-6)
				T.near(ay, oy, 1e-6)
				T.near(az, oz, 1e-6)
			end
		end
		-- every ray runs along the look vector, which points down and away from the viewer
		local c30 = math.cos(math.rad(30)) / math.sqrt(2)
		T.near(cam.lx, -c30, 1e-9)
		T.near(cam.ly, -0.5, 1e-9)
		T.near(cam.lz, -c30, 1e-9)
	end)

	------------------------------------------------------------------ the world-anchored 2:1 grid
	local ROT30 = Raster.rotation(45, 30)
	local function grid(a: number, px: number, py: number): Raster.Grid
		local phX, phY = Raster.gridPhase(a)
		return { a = a, q = a * math.sqrt(2), phX = phX, phY = phY, l = -300, px = px, py = py }
	end
	local function frac(v: number, period: number, target: number): number
		local d = (v - target) % period
		return math.min(d, period - d)
	end

	T.it("grid phase: every edge of the 1/80-stud build grid keeps off the pixel centres", function()
		for a = 1, 16 do
			local phX, phY, m = Raster.gridPhase(a)
			T.truthy(phX >= 0 and phX < 1 and phY >= 0 and phY < 1, "phase in [0, 1)")
			local want = if a % 16 == 0 then 0.044 elseif a % 8 == 0 or a % 10 == 0 then 0.03 elseif a % 4 == 0 then 0.015 elseif a % 2 == 0 then 0.0075 else 0.0038
			T.truthy(m >= want, string.format("a %d: clearance %.4f >= %.4f", a, m, want))
			-- brute force over the grid's corners on the floor (and a plot origin far from the world's): 1/8, 1/16,
			-- 1/20 and 1/40 stud all sit on 1/80
			local worst = math.huge
			for k = 0, 95 do
				for n = 0, 95 do
					local x, z = -770 + k / 80, 3 + n / 80
					local gx, gy = phX + a * (x - z), phY + a * (x + z) / 2
					worst = math.min(worst, frac(gx, 1, 0.5)) -- a vertical edge against the centre column n + 1/2
					-- the 2:1 lines through the point against the ones through pixel centres (1/4 mod 1/2)
					worst = math.min(worst, frac(gy - gx / 2, 0.5, 0.25) * 2 / math.sqrt(5), frac(gy + gx / 2, 0.5, 0.25) * 2 / math.sqrt(5))
				end
			end
			T.truthy(worst >= m - 1e-9, string.format("a %d: brute force %.4f >= %.4f", a, worst, m))
			-- the same numbers come back (cached)
			local x2, y2, m2 = Raster.gridPhase(a)
			T.eq(x2, phX)
			T.eq(y2, phY)
			T.eq(m2, m)
		end
		local x16, y16 = Raster.gridPhase(16)
		T.eq(x16, 0, "a = 16: the build grid's vertical edges land on pixel boundaries or mid-pixel quarters")
		T.eq(y16, 0)
	end)

	T.it("grid phase: the odd multiples of 1.25 keep the build grid as clear as odd whole numbers (over a full period)", function()
		for _, a in { 1.25, 3.75, 6.25, 8.75 } do
			local phX, phY, m = Raster.gridPhase(a)
			T.truthy(m >= 0.0038, string.format("a %g: clearance %.4f", a, m))
			-- a * k / 80 repeats every 64 k (4/5 stud): brute force over more than a period both ways
			local worst = math.huge
			for k = 0, 140 do
				for n = 0, 140 do
					local x, z = -770 + k / 80, 3 + n / 80
					local gx, gy = phX + a * (x - z), phY + a * (x + z) / 2
					worst = math.min(worst, frac(gx, 1, 0.5))
					worst = math.min(worst, frac(gy - gx / 2, 0.5, 0.25) * 2 / math.sqrt(5), frac(gy + gx / 2, 0.5, 0.25) * 2 / math.sqrt(5))
				end
			end
			T.truthy(worst >= m - 1e-9, string.format("a %g: brute force %.4f >= %.4f", a, worst, m))
		end
		-- other quarter steps put the build grid's edges on a finer lattice: no phase clears them
		for _, a in { 1.5, 2.25, 3.5, 5.75, 6.5 } do
			local _, _, m = Raster.gridPhase(a)
			T.truthy(m < 0.0035, string.format("a %g: clearance %.4f stays under MIN_CLEAR", a, m))
		end
	end)

	T.it("grid scale: Close takes the even scale nearest zoom x fit, Whole the clean quarter step up to the fit", function()
		-- the live devices (fit = Raster.fit's art px per ground stud): desktop, laptop, tablet, phone, portrait
		T.eq(Raster.gridScale(6.41, 1.5, true), 10, "desktop 1080p: 1.56x")
		T.eq(Raster.gridScale(6.89, 1.5, true), 10, "laptop: 1.45x")
		T.eq(Raster.gridScale(5.47, 1.5, true), 8, "tablet: 1.46x")
		T.eq(Raster.gridScale(2.52, 1.5, true), 4, "phone: 1.59x")
		T.eq(Raster.gridScale(2.29, 1.5, true), 4, "portrait: 1.74x")
		T.eq(Raster.gridScale(6.41, 1, false), 6.25, "whole bakery desktop: 6.25 keeps the build grid clear")
		T.eq(Raster.gridScale(6.2, 1, false), 6, "6.2: 6")
		T.eq(Raster.gridScale(2.29, 1, false), 2, "whole bakery portrait: 2.25 does not, 2")
		T.eq(Raster.gridScale(2.52, 1, false), 2.5, "whole bakery phone: 2.5 keeps the build grid clear")
		T.eq(Raster.gridScale(5.97, 1, false), 5, "5.75 and 5.5 do not (5.5's phase leaves 0.0017 px): 5")
		T.eq(Raster.gridScale(3.7, 1, false), 3, "3.5 does not either: 3")
		T.eq(Raster.gridScale(3.8, 1, false), 3.75, "3.75 does")
		T.eq(Raster.gridScale(7.3, 1, false), 7, "7.25 does not: 7")
		T.eq(Raster.gridScale(0.4, 1, false), 1, "never below 1")
		T.eq(Raster.gridScale(0.4, 1.5, true), 2, "never below 2 when even")
		T.eq(Raster.gridScale(6, 1, false), 6, "exactly a whole number")
		for fit = 1, 12, 0.37 do
			local a = Raster.gridScale(fit, 1.5, true)
			T.eq(a % 2, 0, "even")
			T.truthy(math.abs(math.log(a / (fit * 1.5))) <= math.log((a + 2) / a) + 1e-9, "the nearest even by ratio")
			local w = Raster.gridScale(fit, 1, false)
			local _, _, clear = Raster.gridPhase(w)
			T.truthy(w <= fit + 1e-9 and w + 1 > fit and (w * 4) % 1 == 0, "a quarter step up to the fit, less than one below it")
			T.truthy(clear >= 0.0035, "its phase keeps the build grid clear")
		end
	end)

	T.it("grid cam: a pan moves the picture by whole art px and keeps every global pixel's own ray", function()
		local K, fx, fy = 2, 1280, 720
		local g1 = grid(8, -6001, -2999)
		local g2 = grid(8, -6001 + 37, -2999 - 11)
		local c1 = Raster.gridCam(ROT30, g1, fx, fy, K, BACK)
		local c2 = Raster.gridCam(ROT30, g2, fx, fy, K, BACK)
		T.eq(c1.W, 640)
		T.eq(c1.H, 360)
		T.eq(c1.gx, -6001)
		T.eq(c2.gy, -2999 - 11)
		T.near(c1.s, K * 8 * math.sqrt(2), 1e-9, "screen px per stud")
		for _, ij in { { 0, 0 }, { 37, 0 }, { 100, 200 }, { 639, 359 }, { 400, 11 } } do
			local i, j = ij[1], ij[2]
			local ax, ay, az = Raster.origin(c1, i, j)
			local bx, by, bz = Raster.origin(c2, i - 37, j + 11)
			T.truthy(ax == bx and ay == by and az == bz, "the same global pixel has the very same ray at both pans")
			-- the incremental origin agrees with it
			T.near(c1.ox + i * c1.ix + j * c1.jx, ax, 1e-9)
			-- and the pixel's ray goes through its centre
			local px, py, d = Raster.project(c1, ax, ay, az)
			T.near(px, i + 0.5, 1e-6)
			T.near(py, j + 0.5, 1e-6)
			T.near(d, 0, 1e-6)
		end
		for _, p in { { -770, 0, 3 }, { -760.25, 3.5, -7.75 }, { -790, 8.5, 17.5 } } do
			local x1, y1, d1 = Raster.project(c1, p[1], p[2], p[3])
			local x2, y2, d2 = Raster.project(c2, p[1], p[2], p[3])
			T.near(x1 - x2, 37, 1e-6, "the picture moves by the pan")
			T.near(y1 - y2, -11, 1e-6)
			T.near(d1, d2, 1e-9, "depth does not change with the pan")
			local gx, gy = Raster.gridPoint(ROT30, g1, p[1], p[2], p[3])
			T.near(gx, x1 + g1.px, 1e-6, "gridPoint is the global pixel")
			T.near(gy, y1 + g1.py, 1e-6)
		end
		-- the view centre is at the screen centre, CamRayBack along the rays
		local cx, cy, cz = Raster.gridCenter(ROT30, g1, fx, fy, K)
		local sx, sy, sd = Raster.project(c1, cx, cy, cz)
		T.near(sx, fx / (2 * K), 1e-6)
		T.near(sy, fy / (2 * K), 1e-6)
		T.near(sd, BACK, 1e-6)
		-- the world origin lands on the phase
		local ox, oy = Raster.gridPoint(ROT30, g1, 0, 0, 0)
		T.near(ox, g1.phX, 1e-12)
		T.near(oy, g1.phY, 1e-12)
		-- a window keeps the global pixels too
		local w = Raster.window(c1, 13, 7, 20, 10)
		local wx, wy, wz = Raster.origin(w, 0, 0)
		local ex, ey, ez = Raster.origin(c1, 13, 7)
		T.truthy(wx == ex and wy == ey and wz == ez, "window pixel (0, 0) is layer pixel (13, 7)")
	end)

	T.it("2:1 edges: a box on the build grid rasters as clean steps with a 1 px ink line, the same wherever it stands", function()
		local function shoot(a: number, bx: number, bz: number): (Raster.Frame, Raster.Cam)
			-- a 160 x 120 art px layer (K 1) looking at the box; the floor far below so every top edge gets ink
			local g = grid(a, 0, 0)
			local gx, gy = Raster.gridPoint(ROT30, g, bx, 0, bz)
			g.px, g.py = math.floor(gx) - 80, math.floor(gy) - 60
			local cam = Raster.gridCam(ROT30, g, 160, 120, 1, BACK)
			local f = Raster.newFrame(cam.W, cam.H)
			Raster.drawBox(f, cam, { bx, -20, bz, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 200, 1, 200, 0, 2, constShade(0xFF808080))
			Raster.drawBox(f, cam, { bx + 1.5, 1.625, bz + 1, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 3, 1.25, 2, 0, 1, constShade(0xFFFFFFFF))
			return f, cam
		end
		local function mask(f: Raster.Frame, x0: number, y0: number): { [number]: boolean }
			local m = {}
			for j = 0, f.H - 1 do
				for i = 0, f.W - 1 do
					if buffer.readu16(f.id, (j * f.W + i) * 2) == 1 then
						m[(j + y0) * 100000 + (i + x0)] = true
					end
				end
			end
			return m
		end
		for _, a in { 4, 6, 8, 10 } do
			local f, cam = shoot(a, -770, 3)
			-- the top boundary of each column: on the top face's two back edges it steps one row every two columns
			local top: { [number]: number } = {}
			local cols = {}
			for i = 0, f.W - 1 do
				for j = 0, f.H - 1 do
					if buffer.readu16(f.id, (j * f.W + i) * 2) == 1 then
						top[i] = j
						table.insert(cols, i)
						break
					end
				end
			end
			T.truthy(#cols > 4 * a, "a " .. a .. ": the box is on screen")
			-- the back corner (the topmost column) splits the two 2:1 edges
			local peak, peakRow = cols[1], math.huge
			for _, i in cols do
				if top[i] < peakRow then
					peak, peakRow = i, top[i]
				end
			end
			local bad = 0
			for _, i in cols do
				local i2 = i + 2
				if top[i2] ~= nil and i2 < peak - 1 and i > cols[1] then
					if top[i2] - top[i] ~= -1 then
						bad += 1
					end
				elseif top[i2] ~= nil and i > peak + 1 and i2 < cols[#cols] then
					if top[i2] - top[i] ~= 1 then
						bad += 1
					end
				end
			end
			T.eq(bad, 0, "a " .. a .. ": both back edges climb exactly one row every two columns (2-2-2 steps)")
			-- the ink line: one pixel a column on the edge itself, 8-connected, never doubled
			Shading.outline(f, 0, 0, f.W - 1, f.H - 1)
			local INK = Shading.pack(0x2B, 0x1E, 0x2E)
			local gaps, doubled = 0, 0
			for _, i in cols do
				local j = top[i]
				if buffer.readu32(f.color, (j * f.W + i) * 4) ~= INK then
					gaps += 1
				end
				if j + 1 < f.H and buffer.readu16(f.id, ((j + 1) * f.W + i) * 2) == 1 and buffer.readu32(f.color, ((j + 1) * f.W + i) * 4) == INK and i ~= cols[1] and i ~= cols[#cols] then
					-- a second ink pixel under the edge one: only where the outline turns down a vertical side
					local left, right = top[i - 1], top[i + 1]
					if left ~= nil and right ~= nil and math.abs(left - j) <= 1 and math.abs(right - j) <= 1 then
						doubled += 1
					end
				end
			end
			T.eq(gaps, 0, "a " .. a .. ": the ink runs along the whole top edge")
			T.eq(doubled, 0, "a " .. a .. ": 1 px line weight along the 2:1 edges")
			-- moved along the build grid by a whole number of pixels: exactly the same picture, shifted
			local step = if a % 8 == 0 then 0.25 elseif a % 4 == 0 then 0.5 else 1
			for _, d in { { step, 0 }, { 0, step }, { 3, -2 } } do
				local f2, cam2 = shoot(a, -770 + d[1], 3 + d[2])
				local m1 = mask(f, cam.gx, cam.gy)
				local m2 = mask(f2, cam2.gx, cam2.gy)
				local sx, sy = a * (d[1] - d[2]), a * (d[1] + d[2]) / 2
				T.eq(sx % 1, 0, "whole px across")
				T.eq(sy % 1, 0, "whole px down")
				local miss = 0
				local n = 0
				for key in m1 do
					n += 1
					local y, x = key // 100000, key % 100000
					if not m2[(y + sy) * 100000 + (x + sx)] then
						miss += 1
					end
				end
				for _ in m2 do
					n -= 1
				end
				T.eq(miss, 0, string.format("a %d moved %g, %g studs: the same pixels", a, d[1], d[2]))
				T.eq(n, 0, "and no more")
			end
		end
	end)

	T.it("follow: the baker stays visible, the focus comes into view, the outline holds the camera, then the dead zone", function()
		-- screen 0..640; dead zone 200..440; visible 77..563; the outline's pans 0..1000
		local function f(cur: number, pos: number, fpos: number?): number
			return Raster.followAxis(cur, pos, 200, 440, 77, 563, 0, 1000, fpos, 115, 525)
		end
		T.eq(f(500, 800), 500, "in the dead zone: still")
		T.eq(f(500, 1000), 560, "past its right side: the least move that brings it back (1000 - 440)")
		T.eq(f(500, 650), 450, "past its left side")
		T.eq(f(500, 1500), 1000, "the outline holds the camera at its end: the baker leaves the dead zone")
		T.eq(f(1000, 1550), 1000, "still held, the baker still visible (1550 - 1000 = 550 < 563)")
		T.eq(f(1000, 1600), 1037, "past the visible edge: the camera follows as little as keeps it visible (1600 - 563)")
		T.eq(f(0, 40), -37, "by the outline's left end: 37 px of lawn keep the baker CamVisible from the edge")
		T.eq(f(0, -100), -177, "the baker out on the lawn: just visible (-100 - 77)")
		-- a focus that fits with the baker comes into view (the least move); one that does not, as near as the baker
		-- stays visible
		T.eq(f(500, 800, 1100), 575, "the focus at 1100 needs a pan of 575..985, the baker in the dead zone 360..600: 575")
		T.eq(f(500, 800, 1500), 723, "a far focus (975..1385): as far toward it as the baker stays visible (800 - 77)")
		-- an outline narrower than the screen: centred
		T.eq(Raster.followAxis(0, 300, 200, 440, 77, 563, 50, -30, nil, nil, nil), 10, "narrow outline: the middle (50 - 30) / 2")
	end)

	T.it("boxRect", function()
		local cam = smallCam()
		local x0, y0, x1, y1 = Raster.boxRect(cam, { 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.5, 0.5, 0.5)
		-- the box sits on the view centre: its rect straddles the layer centre (80, 45)
		T.truthy(x0 and y0 and x1 and y1, "on screen")
		local a, b, c, d = x0 :: number, y0 :: number, x1 :: number, y1 :: number
		T.truthy(a <= 80 and c >= 79 and b <= 45 and d >= 44, "around the centre")
		T.truthy(c - a <= 6 and d - b <= 6, "small")
		local off = Raster.boxRect(cam, { 500, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 2, 2, 2)
		T.eq(off, nil, "off-screen")
		-- 300 studs toward the viewer is behind the ray plane
		local behind = Raster.boxRect(cam, { 173, 174, 173, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 2, 2, 2)
		T.eq(behind, nil, "behind the ray plane")
	end)

	T.it("box covers the expected pixels with exact depth", function()
		local cam = smallCam()
		local cases = {
			{ cf = { 0.3, 1.2, -0.5, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, size = { 3, 2, 4 } }, -- axis aligned: three faces
			{ cf = cfYaw(-1.5, 1.5, 1, math.rad(35)), size = { 2.5, 3, 1.5 } }, -- turned
			{ cf = { 1, 2, -1, 0.8, -0.6, 0, 0.6, 0.8, 0, 0, 0, 1 }, size = { 1, 1.5, 2 } }, -- rolled about Z
			{ cf = cfYaw(2, 0.5, 2, math.rad(45)), size = { 2, 1, 2 } }, -- a side seen exactly edge-on
		}
		for ci, case in cases do
			local f = Raster.newFrame(cam.W, cam.H)
			Raster.drawBox(f, cam, case.cf, case.size[1], case.size[2], case.size[3], 0xABCDEF, 7, constShade(0xFF112233))
			local covered, checked = 0, 0
			for j = 0, cam.H - 1 do
				for i = 0, cam.W - 1 do
					local idx = j * cam.W + i
					local ox, oy, oz = Raster.origin(cam, i, j)
					local t, border = rayBox(ox, oy, oz, cam.lx, cam.ly, cam.lz, case.cf, case.size)
					local id = buffer.readu16(f.id, idx * 2)
					if border > 1e-3 then -- skip pixels whose ray grazes an edge
						checked += 1
						if t then
							covered += 1
							T.eq(id, 7, "case " .. ci .. " pixel " .. idx .. " covered")
							T.near(buffer.readf32(f.depth, idx * 4), t, 1e-3, "case " .. ci .. " depth")
							T.eq(buffer.readu32(f.color, idx * 4), 0xFF112233)
						else
							T.eq(id, 0, "case " .. ci .. " pixel " .. idx .. " empty")
							T.truthy(buffer.readf32(f.depth, idx * 4) > 1e20, "untouched depth")
						end
					end
				end
			end
			T.truthy(covered > 30, "case " .. ci .. " draws something (" .. covered .. ")")
			T.truthy(checked > cam.W * cam.H * 0.95, "few ambiguous pixels")
		end
	end)

	T.it("depth test between boxes", function()
		local cam = smallCam()
		local near = { 0.6, 1.6, 0.6, 1, 0, 0, 0, 1, 0, 0, 0, 1 } -- toward the viewer along (1, 1, 1)
		local far = { -1, 0, -1, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
		local centre = math.floor(cam.H / 2) * cam.W + math.floor(cam.W / 2)
		local f = Raster.newFrame(cam.W, cam.H)
		Raster.drawBox(f, cam, near, 1, 1, 1, 0, 1, constShade(1))
		Raster.drawBox(f, cam, far, 4, 4, 4, 0, 2, constShade(2))
		T.eq(buffer.readu16(f.id, centre * 2), 1, "far box drawn later stays hidden")
		local g = Raster.newFrame(cam.W, cam.H)
		Raster.drawBox(g, cam, far, 4, 4, 4, 0, 2, constShade(2))
		Raster.drawBox(g, cam, near, 1, 1, 1, 0, 1, constShade(1))
		T.eq(buffer.readu16(g.id, centre * 2), 1, "near box drawn later wins")
		-- frames are identical regardless of draw order
		for i = 0, cam.W * cam.H - 1 do
			T.eq(buffer.readu16(f.id, i * 2), buffer.readu16(g.id, i * 2))
		end
	end)

	T.it("sphere coverage and depth", function()
		local cam = smallCam()
		local cx, cy, cz, r = 0.7, 0.6, -0.4, 1.3
		local f = Raster.newFrame(cam.W, cam.H)
		local seenNy = -2
		Raster.drawSphere(f, cam, cx, cy, cz, r, 0, 9, function(_rgb, nx, ny, nz, _x, _y)
			T.near(nx * nx + ny * ny + nz * nz, 1, 1e-3, "unit normal")
			seenNy = math.max(seenNy, ny)
			return 5
		end)
		local covered = 0
		for j = 0, cam.H - 1 do
			for i = 0, cam.W - 1 do
				local idx = j * cam.W + i
				local ox, oy, oz = Raster.origin(cam, i, j)
				local qx, qy, qz = ox - cx, oy - cy, oz - cz
				local b = qx * cam.lx + qy * cam.ly + qz * cam.lz
				local disc = b * b - (qx * qx + qy * qy + qz * qz - r * r)
				if math.abs(disc) > 1e-3 then
					if disc > 0 then
						covered += 1
						T.eq(buffer.readu16(f.id, idx * 2), 9)
						T.near(buffer.readf32(f.depth, idx * 4), -b - math.sqrt(disc), 1e-3)
					else
						T.eq(buffer.readu16(f.id, idx * 2), 0)
					end
				end
			end
		end
		-- an orthographic sphere is a disc of radius r * s screen px: pi (r s / K)^2 layer px
		local disc = math.pi * (r * cam.s / cam.K) ^ 2
		T.truthy(math.abs(covered - disc) < disc * 0.1, "disc area " .. covered .. " vs " .. disc)
		T.truthy(seenNy > 0.8, "top of the sphere seen")
	end)

	T.it("floor shadow darkens only the floor under the ellipse", function()
		local cam = smallCam()
		local W, H = cam.W, cam.H
		local f = Raster.newFrame(W, H)
		local white = 0xFFC8C8C8
		-- fake static bake: floor plane y = 0 everywhere; one pixel has an object in front
		for j = 0, H - 1 do
			for i = 0, W - 1 do
				local idx = j * W + i
				local _, oy = Raster.origin(cam, i, j)
				buffer.writeu32(f.color, idx * 4, white)
				buffer.writef32(f.depth, idx * 4, -oy / cam.ly)
			end
		end
		local px, py = Raster.project(cam, 0, 0, 0)
		local cxp, cyp = math.floor(px), math.floor(py)
		local blocker = cyp * W + cxp
		buffer.writef32(f.depth, blocker * 4, buffer.readf32(f.depth, blocker * 4) - 3)
		Raster.drawShadow(f, cam, 0, 0, 0, 1.5, 1.5, 0.5)
		local rx0, ry0, rx1, ry1 = Raster.shadowRect(cam, 0, 0, 0, 1.5, 1.5)
		T.truthy(rx0 and ry0 and rx1 and ry1, "shadow rect on screen")
		local dark = 0
		for j = 0, H - 1 do
			for i = 0, W - 1 do
				local idx = j * W + i
				local c = buffer.readu32(f.color, idx * 4)
				if c ~= white then
					dark += 1
					T.eq(bit32.rshift(c, 24), 255, "opaque")
					T.eq(bit32.band(c, 0xFF), math.floor(0xC8 * 0.5), "darkened by strength")
					T.truthy(i >= (rx0 :: number) and i <= (rx1 :: number) and j >= (ry0 :: number) and j <= (ry1 :: number), "inside its rect")
					-- the darkened point lies inside the ellipse on the floor
					local ox, oy, oz = Raster.origin(cam, i, j)
					local t = -oy / cam.ly
					local hx, hz = ox + cam.lx * t, oz + cam.lz * t
					T.truthy(hx * hx + hz * hz <= 1.5 * 1.5 + 0.05, "inside")
				end
			end
		end
		T.truthy(dark > 10, "shadow drawn (" .. dark .. ")")
		-- solid to the edge: every floor pixel inside the ellipse is darkened (no dithered holes), the blocker excepted
		local holes = 0
		for j = 0, H - 1 do
			for i = 0, W - 1 do
				local idx = j * W + i
				local ox, oy, oz = Raster.origin(cam, i, j)
				local t = -oy / cam.ly
				local hx, hz = ox + cam.lx * t, oz + cam.lz * t
				if idx ~= blocker and hx * hx + hz * hz <= 1.5 * 1.5 - 0.05 and buffer.readu32(f.color, idx * 4) == white then
					holes += 1
				end
			end
		end
		T.eq(holes, 0, "no undarkened pixel inside the shadow")
		T.eq(buffer.readu32(f.color, blocker * 4), white, "object in front is not shadowed")
	end)

	T.it("hull: convex, counter-clockwise, inner and collinear points left out", function()
		-- a 4 x 2 rectangle with points inside, on its edges and repeated
		local h = Raster.hull({ 0, 0, 4, 0, 4, 2, 0, 2, 2, 1, 2, 0, 4, 1, 1, 1, 0, 0, 4, 2 })
		T.eq(#h, 8, "four corners")
		local seen = {}
		for i = 1, #h, 2 do
			seen[h[i] .. "," .. h[i + 1]] = true
		end
		T.truthy(seen["0,0"] and seen["4,0"] and seen["4,2"] and seen["0,2"], "the corners")
		-- counter-clockwise (y up): every point lies left of every edge
		local n = #h // 2
		for i = 1, n do
			local j = i % n + 1
			local ex, ey = h[j * 2 - 1] - h[i * 2 - 1], h[j * 2] - h[i * 2]
			T.truthy(ex * (1 - h[i * 2]) - ey * (2 - h[i * 2 - 1]) > 0, "the inside is left of edge " .. i)
		end
		T.eq(#Raster.hull({ 1, 2, 3, 4 }), 4, "two points come back as they are")
	end)

	-- REWORK2 1.2: the one framing of the shop, its outline as big as it fits clear of the HUD
	local ROT = Raster.rotation(45, ISO_PITCH)
	type Box = { number } -- x0, y0, x1, y1 (full-screen px)
	local function rects(list: { Box }): { Raster.Rect }
		local out = {}
		for _, r in list do
			table.insert(out, { x0 = r[1], y0 = r[2], x1 = r[3], y1 = r[4] })
		end
		return out
	end
	-- the outline (hull of the projected points) on screen, flat x, y, for a fitted view (K 1: layer px = screen px)
	local function outlineOn(W: number, H: number, ox: number, oz: number, blocks: { Box }, pad: number): ({ number }, Raster.Cam)
		local pts = outlinePts(ox, oz)
		local cx, cy, cz, viewH = Raster.fit(ROT, W, H, rects(blocks), pad, pts)
		local cam = Raster.cam(isoCf(cx, cy, cz), viewH, W, H, 1, BACK)
		local xy = {}
		for i = 1, #pts, 3 do
			local px, py, d = Raster.project(cam, pts[i], pts[i + 1], pts[i + 2])
			T.truthy(d > 0, "in front of the ray plane")
			table.insert(xy, px)
			table.insert(xy, py)
		end
		return Raster.hull(xy), cam
	end
	local function extent(poly: { number }): (number, number, number, number)
		local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
		for i = 1, #poly, 2 do
			x0, x1 = math.min(x0, poly[i]), math.max(x1, poly[i])
			y0, y1 = math.min(y0, poly[i + 1]), math.max(y1, poly[i + 1])
		end
		return x0, x1, y0, y1
	end
	-- separating axes: does the convex polygon reach into the open rect?
	local function overlaps(poly: { number }, r: Box): boolean
		local corners = { r[1], r[2], r[3], r[2], r[3], r[4], r[1], r[4] }
		local axes = { 1, 0, 0, 1 }
		local n = #poly // 2
		for i = 1, n do
			local j = i % n + 1
			table.insert(axes, poly[i * 2] - poly[j * 2])
			table.insert(axes, poly[j * 2 - 1] - poly[i * 2 - 1])
		end
		for a = 1, #axes, 2 do
			local ax, ay = axes[a], axes[a + 1]
			local l = math.sqrt(ax * ax + ay * ay)
			if l > 1e-12 then
				ax, ay = ax / l, ay / l
				local p0, p1, r0, r1 = math.huge, -math.huge, math.huge, -math.huge
				for i = 1, #poly, 2 do
					local d = poly[i] * ax + poly[i + 1] * ay
					p0, p1 = math.min(p0, d), math.max(p1, d)
				end
				for i = 1, 8, 2 do
					local d = corners[i] * ax + corners[i + 1] * ay
					r0, r1 = math.min(r0, d), math.max(r1, d)
				end
				if p1 <= r0 + 1e-6 or r1 <= p0 + 1e-6 then
					return false
				end
			end
		end
		return true
	end
	local function grown(r: Box, p: number): Box
		return { r[1] - p, r[2] - p, r[3] + p, r[4] + p }
	end
	-- the outline at scale k about its box centre, moved so that centre sits at (x, y)
	local function scaled(poly: { number }, k: number, x: number, y: number): { number }
		local x0, x1, y0, y1 = extent(poly)
		local mx, my = (x0 + x1) / 2, (y0 + y1) / 2
		local out = {}
		for i = 1, #poly, 2 do
			table.insert(out, x + (poly[i] - mx) * k)
			table.insert(out, y + (poly[i + 1] - my) * k)
		end
		return out
	end
	local function clearOf(poly: { number }, W: number, H: number, blocks: { Box }, pad: number): boolean
		local x0, x1, y0, y1 = extent(poly)
		if x0 < pad - 1e-6 or x1 > W - pad + 1e-6 or y0 < pad - 1e-6 or y1 > H - pad + 1e-6 then
			return false
		end
		for _, r in blocks do
			if overlaps(poly, grown(r, pad)) then
				return false
			end
		end
		return true
	end

	-- HUD layouts like the live ones (Roblox's button, stats, rail cards, menu row, command bar, touch controls)
	local DESKTOP: { Box } = { { 0, 0, 58, 58 }, { 12, 70, 300, 124 }, { 12, 130, 474, 176 }, { 12, 184, 420, 270 }, { 12, 280, 357, 322 }, { 1413, 70, 1908, 112 }, { 12, 990, 486, 1068 } }
	local PHONE: { Box } = { { 0, 0, 58, 58 }, { 8, 66, 200, 100 }, { 8, 108, 316, 136 }, { 8, 142, 280, 200 }, { 370, 66, 836, 112 }, { 8, 328, 324, 382 }, { 749, 300, 819, 370 }, { 25, 300, 95, 370 } }
	local TABLET: { Box } = { { 0, 0, 58, 58 }, { 8, 66, 200, 100 }, { 8, 108, 316, 136 }, { 8, 142, 280, 200 }, { 550, 66, 1016, 112 }, { 8, 700, 324, 760 }, { 854, 558, 974, 678 }, { 60, 558, 180, 678 } }
	local PORTRAIT: { Box } = { { 0, 0, 58, 58 }, { 8, 66, 200, 100 }, { 8, 104, 382, 156 }, { 8, 160, 250, 300 }, { 8, 720, 324, 836 }, { 295, 734, 365, 804 } }

	T.it("fit: the whole outline on screen and off every block, on every screen shape", function()
		local cases = {
			{ 1920, 1080, DESKTOP },
			{ 1366, 768, { { 0, 0, 58, 58 }, { 8, 66, 200, 100 }, { 8, 104, 320, 150 }, { 960, 66, 1358, 96 }, { 8, 700, 330, 760 } } },
			{ 1024, 768, TABLET },
			{ 844, 390, PHONE },
			{ 390, 844, PORTRAIT },
			{ 2560, 1080, DESKTOP },
			{ 1920, 1080, {} },
		}
		for _, c in cases do
			local W, H, blocks = c[1], c[2], c[3]
			local tag = W .. "x" .. H .. "/" .. #blocks
			local poly = outlineOn(W, H, -770, 0, blocks, PAD)
			T.truthy(clearOf(poly, W, H, blocks, PAD), tag .. ": on screen, PAD clear of every block")
			-- as big as it gets: at 1% more, no placement on a 4 px grid is clear (and at 3% less one is)
			local x0, x1, y0, y1 = extent(poly)
			local function anyClear(k: number): boolean
				local hw, hh = (x1 - x0) * k / 2, (y1 - y0) * k / 2
				for y = PAD + hh, H - PAD - hh + 1e-9, 4 do
					for x = PAD + hw, W - PAD - hw + 1e-9, 4 do
						if clearOf(scaled(poly, k, x, y), W, H, blocks, PAD) then
							return true
						end
					end
				end
				return false
			end
			if W * H < 1e6 then -- the grid search is slow on big screens
				T.truthy(not anyClear(1.01), tag .. ": nothing bigger fits")
				T.truthy(anyClear(0.97), tag .. ": the grid search finds a smaller one")
			end
			-- it touches something on two sides at least (else it could grow)
			local touching = 0
			if x0 < PAD + 0.5 then
				touching += 1
			end
			if x1 > W - PAD - 0.5 then
				touching += 1
			end
			if y0 < PAD + 0.5 then
				touching += 1
			end
			if y1 > H - PAD - 0.5 then
				touching += 1
			end
			for _, r in blocks do
				if overlaps(poly, grown(r, PAD + 0.5)) then
					touching += 1
				end
			end
			T.truthy(touching >= 2, tag .. ": held by two sides or blocks at least, got " .. touching)
		end
	end)

	T.it("fit: the bare screen centres the outline and fills the height; the plot does not matter", function()
		local W, H = 1920, 1080
		local poly, cam = outlineOn(W, H, -770, 0, {}, PAD)
		local x0, x1, y0, y1 = extent(poly)
		-- the outline is 57.63 x 36.48 studs (1.58:1) at pitch 30: 16:9 is wider, the height decides
		T.near(y1 - y0, H - 2 * PAD, 1e-6, "height fill")
		T.near((x0 + x1) / 2, W / 2, 1e-6, "centred across")
		T.near((y0 + y1) / 2, H / 2, 1e-6, "centred down")
		-- from the north crown's top corner (x + z = -41.5, y 8.5) to the south plinth's bottom (x + z = 40.25, y -0.25)
		local sp, cp = math.sin(math.rad(ISO_PITCH)), math.cos(math.rad(ISO_PITCH))
		T.near((y1 - y0) / cam.s, (41.5 + 40.25) * sp / math.sqrt(2) + (8.5 + 0.25) * cp, 1e-6, "outline height in studs")
		T.near((x1 - x0) / cam.s, 2 * 40.75 / math.sqrt(2), 1e-6, "outline width in studs")
		-- the view centre's depth is the outline boxes' centre's (rays start CamRayBack before it)
		local pts = outlinePts(-770, 0)
		local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
		for i = 1, #pts, 3 do
			for k = 1, 3 do
				lo[k], hi[k] = math.min(lo[k], pts[i + k - 1]), math.max(hi[k], pts[i + k - 1])
			end
		end
		local _, _, d = Raster.project(cam, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2, (lo[3] + hi[3]) / 2)
		T.near(d, BACK, 1e-6, "centre depth")
		-- another plot: the same picture
		local other = outlineOn(W, H, 770, 0, DESKTOP, PAD)
		local same = outlineOn(W, H, -770, 0, DESKTOP, PAD)
		for i = 1, #same do
			T.near(other[i], same[i], 1e-6, "plot-independent")
		end
	end)

	T.it("fit: blocks in the corners zoom the shop in past its box; centred among equal fits", function()
		local W, H = 1920, 1080
		-- the old rule: the outline's box inside the screen minus full-width strips under the top row and over the
		-- command bar
		local poly = outlineOn(W, H, 0, 0, DESKTOP, PAD)
		local _, _, y0, y1 = extent(poly)
		local boxH = (990 - 2 * PAD) - (124 + 0) -- the strips' gap
		T.truthy(y1 - y0 > boxH * 1.15, "at least 15% bigger than the strips allow")
		-- a block only on the left edge's middle: the free placements at the biggest size are a range; the one
		-- nearest the centre wins
		local side = outlineOn(2560, 1080, 0, 0, { { 0, 500, 120, 560 } }, PAD)
		local x0, x1 = extent(side)
		T.near((x0 + x1) / 2, 2560 / 2, 1e-6, "centred when the block does not get in the way")
	end)

	T.it("fit: small HUD changes move the shop a little; no room at all falls back to a centred minimum", function()
		local W, H = 844, 390
		local a = outlineOn(W, H, 0, 0, PHONE, PAD)
		local moved = table.clone(PHONE)
		moved[4] = { 8, 142, 281, 201 } -- the rail card one px bigger
		local b = outlineOn(W, H, 0, 0, moved, PAD)
		local worst = 0
		for i = 1, #a do
			worst = math.max(worst, math.abs(a[i] - b[i]))
		end
		T.truthy(worst < 3, "a one px change moves the outline by under 3 px, got " .. worst)
		-- blocks over the whole screen: FIT_MIN (35%) of the bare-screen size, centred, on screen
		local bare = outlineOn(W, H, 0, 0, {}, PAD)
		local full = outlineOn(W, H, 0, 0, { { 0, 0, W, H } }, PAD)
		local _, _, by0, by1 = extent(bare)
		local x0, x1, y0, y1 = extent(full)
		T.near(y1 - y0, (by1 - by0) * 0.35, 1e-3, "35% of the bare-screen size")
		T.near((x0 + x1) / 2, W / 2, 1e-6, "centred")
		T.truthy(x0 >= 0 and x1 <= W and y0 >= 0 and y1 <= H, "on screen")
	end)

	T.it("place: at a given scale, the clear spot nearest the screen centre (the centre itself when it is clear)", function()
		for _, c in { { 844, 390, PHONE }, { 1024, 768, TABLET }, { 1920, 1080, DESKTOP } } do
			local W, H, blocks = c[1], c[2], c[3]
			local tag = W .. "x" .. H
			local pts = outlinePts(-770, 0)
			local poly, cam = outlineOn(W, H, -770, 0, blocks, PAD)
			local x0, x1, y0, y1 = extent(poly)
			-- at the fit's own scale: where the fit put it
			local fx, fy = Raster.place(ROT, W, H, rects(blocks), PAD, pts, cam.s)
			T.truthy(fx ~= nil and math.abs(fx - (x0 + x1) / 2) < 1e-3 and math.abs((fy :: number) - (y0 + y1) / 2) < 1e-3, tag .. ": the fit's placement at the fit's scale")
			-- smaller: clear, and no clear spot on a 2 px grid nearer the centre (by more than the grid's step)
			for _, k in { 0.9, 0.75, 0.6 } do
				local x, y = Raster.place(ROT, W, H, rects(blocks), PAD, pts, cam.s * k)
				T.truthy(x ~= nil and y ~= nil, tag .. ": a placement at " .. k)
				local px, py = x :: number, y :: number
				T.truthy(clearOf(scaled(poly, k, px, py), W, H, blocks, PAD - 1e-3), tag .. ": clear at " .. k)
				local d = math.sqrt((px - W / 2) ^ 2 + (py - H / 2) ^ 2)
				if d < 1e-6 then
					T.near(px, W / 2, 1e-9, tag .. ": exactly centred at " .. k)
					T.near(py, H / 2, 1e-9)
				elseif W * H < 1e6 then
					local r = math.ceil(d)
					for gy = H / 2 - r, H / 2 + r, 2 do
						for gx = W / 2 - r, W / 2 + r, 2 do
							local dg = math.sqrt((gx - W / 2) ^ 2 + (gy - H / 2) ^ 2)
							if dg < d - 2.9 and clearOf(scaled(poly, k, gx, gy), W, H, blocks, PAD) then
								T.truthy(false, string.format("%s at %g: %g,%g is clear and nearer the centre than %.1f,%.1f", tag, k, gx, gy, px, py))
							end
						end
					end
				end
			end
		end
		-- the bare screen: the centre at any scale it fits; blocks everywhere: nowhere
		local pts = outlinePts(0, 0)
		local _, cam = outlineOn(1366, 768, 0, 0, {}, PAD)
		local x, y = Raster.place(ROT, 1366, 768, {}, PAD, pts, cam.s * 0.83)
		T.truthy(x == 1366 / 2 and y == 768 / 2, "bare screen: centred")
		T.eq(Raster.place(ROT, 1366, 768, rects({ { 0, 0, 1366, 768 } }), PAD, pts, cam.s * 0.5), nil, "no room: nil")
	end)

	------------------------------------------------------------------ solids
	-- Independent ray / convex polyhedron intersection: the planes come from the solid's corner points (cross
	-- products), not from Raster.planes. Returns t (or nil) and how deep inside the faces' borders the hit lies.
	local function rayPoly(o: { number }, d: { number }, faces: { { { number } } }): (number?, number)
		local tIn, tOut = -math.huge, math.huge
		local planes = {}
		for _, f in faces do
			local a, b, c = f[1], f[2], f[3]
			local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
			local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
			local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
			local l = math.sqrt(nx * nx + ny * ny + nz * nz)
			nx, ny, nz = nx / l, ny / l, nz / l
			table.insert(planes, { nx, ny, nz, nx * a[1] + ny * a[2] + nz * a[3] })
		end
		for _, p in planes do
			local den = p[1] * d[1] + p[2] * d[2] + p[3] * d[3]
			local num = p[4] - (p[1] * o[1] + p[2] * o[2] + p[3] * o[3])
			if math.abs(den) < 1e-12 then
				if num < 0 then
					return nil, 1
				end
			else
				local t = num / den
				if den < 0 then
					tIn = math.max(tIn, t)
				else
					tOut = math.min(tOut, t)
				end
			end
		end
		if tIn > tOut or tIn <= 0 then
			return nil, math.abs(tIn - tOut)
		end
		-- distance of the hit to the nearest other plane (edge ambiguity)
		local hx, hy, hz = o[1] + d[1] * tIn, o[2] + d[2] * tIn, o[3] + d[3] * tIn
		local border = math.huge
		for _, p in planes do
			local gap = p[4] - (p[1] * hx + p[2] * hy + p[3] * hz)
			if gap > 1e-7 then
				border = math.min(border, gap)
			end
		end
		return tIn, border
	end

	-- world point of local (x, y, z) under cf12
	local function wpt(cf: { number }, x: number, y: number, z: number): { number }
		return { cf[1] + cf[4] * x + cf[5] * y + cf[6] * z, cf[2] + cf[7] * x + cf[8] * y + cf[9] * z, cf[3] + cf[10] * x + cf[11] * y + cf[12] * z }
	end

	-- faces (3 points each, counter-clockwise seen from outside) of the Roblox wedge and the corner wedge
	local function wedgeFaces(cf: { number }, sx: number, sy: number, sz: number, corner: boolean): { { { number } } }
		local hx, hy, hz = sx / 2, sy / 2, sz / 2
		local function P(x: number, y: number, z: number): { number }
			return wpt(cf, x * hx, y * hy, z * hz)
		end
		if not corner then
			-- bottom, back (+Z), right, left, slope from the front bottom edge to the back top edge
			return {
				{ P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1) },
				{ P(-1, -1, 1), P(1, -1, 1), P(1, 1, 1) },
				{ P(1, -1, -1), P(1, 1, 1), P(1, -1, 1) },
				{ P(-1, -1, -1), P(-1, -1, 1), P(-1, 1, 1) },
				{ P(-1, -1, -1), P(-1, 1, 1), P(1, 1, 1) },
			}
		end
		-- apex above the +X / -Z bottom corner: bottom, right (+X), front (-Z), left slope, back slope
		local apex = P(1, 1, -1)
		return {
			{ P(-1, -1, -1), P(1, -1, -1), P(1, -1, 1) },
			{ P(1, -1, -1), apex, P(1, -1, 1) },
			{ P(-1, -1, -1), apex, P(1, -1, -1) },
			{ P(-1, -1, -1), P(-1, -1, 1), apex },
			{ P(-1, -1, 1), P(1, -1, 1), apex },
		}
	end

	local function checkCoverage(tag: string, f: Raster.Frame, cam: Raster.Cam, id: number, hit: (o: { number }) -> (number?, number))
		local covered, checked = 0, 0
		for j = 0, cam.H - 1 do
			for i = 0, cam.W - 1 do
				local idx = j * cam.W + i
				local ox, oy, oz = Raster.origin(cam, i, j)
				local t, border = hit({ ox, oy, oz })
				if border > 1e-3 then
					checked += 1
					local got = buffer.readu16(f.id, idx * 2)
					if t then
						covered += 1
						T.eq(got, id, tag .. " pixel " .. idx .. " covered")
						T.near(buffer.readf32(f.depth, idx * 4), t, 2e-3, tag .. " depth")
					else
						T.eq(got, 0, tag .. " pixel " .. idx .. " empty")
					end
				end
			end
		end
		T.truthy(covered > 30, tag .. " draws something (" .. covered .. ")")
		T.truthy(checked > cam.W * cam.H * 0.95, tag .. ": few ambiguous pixels")
	end

	T.it("wedge and corner wedge cover the expected pixels with exact depth", function()
		local cam = smallCam()
		local cases = {
			{ cf = { 0.3, 1.2, -0.5, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, size = { 3, 2, 4 } },
			{ cf = cfYaw(-1.5, 1.5, 1, math.rad(150)), size = { 2.5, 3, 1.5 } },
			{ cf = { 1, 2, -1, 0.8, -0.6, 0, 0.6, 0.8, 0, 0, 0, 1 }, size = { 1, 1.5, 2 } },
			{ cf = cfYaw(0, 1, 0, math.rad(-100)), size = { 4, 1, 2 } },
		}
		for ci, case in cases do
			for _, corner in { false, true } do
				local shape = if corner then "CornerWedge" else "Wedge"
				local f = Raster.newFrame(cam.W, cam.H)
				Raster.drawPart(f, cam, shape, case.cf, case.size[1], case.size[2], case.size[3], 0xABCDEF, 5, constShade(0xFF445566))
				local faces = wedgeFaces(case.cf, case.size[1], case.size[2], case.size[3], corner)
				checkCoverage(shape .. " " .. ci, f, cam, 5, function(o)
					return rayPoly(o, { cam.lx, cam.ly, cam.lz }, faces)
				end)
			end
		end
	end)

	T.it("Raster.planes of a Block are its six faces", function()
		local cf = cfYaw(1, 2, 3, math.rad(30))
		local pl = Raster.planes("Block", cf, 2, 4, 6)
		T.eq(#pl, 24)
		-- the centre is inside every plane by the half size along that plane's axis
		for k = 1, 24, 4 do
			local inside = pl[k + 3] - (pl[k] * 1 + pl[k + 1] * 2 + pl[k + 2] * 3)
			T.truthy(math.abs(inside - 1) < 1e-9 or math.abs(inside - 2) < 1e-9 or math.abs(inside - 3) < 1e-9, "half size")
			T.near(pl[k] ^ 2 + pl[k + 1] ^ 2 + pl[k + 2] ^ 2, 1, 1e-9, "unit normal")
		end
	end)

	T.it("cylinder: axis along X, diameter min(Y, Z), exact depth and normals", function()
		local cam = smallCam()
		local cases = {
			{ cf = { 0.2, 1, -0.3, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, size = { 3, 2, 2.5 } }, -- lying along X
			{ cf = { -1, 1.5, 1, 0, -1, 0, 1, 0, 0, 0, 0, 1 }, size = { 2, 3, 3 } }, -- upright (Blocks.cylY)
			{ cf = cfYaw(1.5, 0.5, -1, math.rad(60)), size = { 4, 1.5, 1 } },
			{ cf = { 0, 1, 0, 0.6, 0, -0.8, 0, 1, 0, 0.8, 0, 0.6 }, size = { 0.5, 3, 3 } }, -- a flat disc
		}
		for ci, case in cases do
			local f = Raster.newFrame(cam.W, cam.H)
			local cf, sx = case.cf, case.size[1]
			local r = math.min(case.size[2], case.size[3]) / 2
			local ax, ay, az = cf[4], cf[7], cf[10]
			Raster.drawPart(f, cam, "Cylinder", cf, case.size[1], case.size[2], case.size[3], 0, 3, function(_rgb, nx, ny, nz, _x, _y)
				T.near(nx * nx + ny * ny + nz * nz, 1, 1e-3, "unit normal")
				return 1
			end)
			-- independent ray / capped cylinder: the quadratic in plain form plus the two cap discs
			local function cylHit(o: { number }, rr: number, hh: number): number?
				local dx, dy, dz = cam.lx, cam.ly, cam.lz
				local qx, qy, qz = o[1] - cf[1], o[2] - cf[2], o[3] - cf[3]
				local qa, da = qx * ax + qy * ay + qz * az, dx * ax + dy * ay + dz * az
				local px, py, pz = qx - qa * ax, qy - qa * ay, qz - qa * az
				local ex, ey, ez = dx - da * ax, dy - da * ay, dz - da * az
				local A, B, C = ex * ex + ey * ey + ez * ez, 2 * (px * ex + py * ey + pz * ez), px * px + py * py + pz * pz - rr * rr
				local best: number? = nil
				local function take(t: number)
					if t > 0 and (best == nil or t < (best :: number)) then
						best = t
					end
				end
				if A > 1e-12 then
					local disc = B * B - 4 * A * C
					if disc >= 0 then
						for _, t in { (-B - math.sqrt(disc)) / (2 * A), (-B + math.sqrt(disc)) / (2 * A) } do
							if math.abs(qa + t * da) <= hh then
								take(t)
							end
						end
					end
				end
				if math.abs(da) > 1e-12 then
					for _, side in { -1, 1 } do
						local t = (side * hh - qa) / da
						local hx, hy, hz = px + t * ex, py + t * ey, pz + t * ez
						if hx * hx + hy * hy + hz * hz <= rr * rr then
							take(t)
						end
					end
				end
				return best
			end
			checkCoverage("cylinder " .. ci, f, cam, 3, function(o)
				-- a pixel whose ray changes its answer when the solid shrinks or grows by 1e-3 grazes an edge
				local inner, outer = cylHit(o, r - 1e-3, sx / 2 - 1e-3), cylHit(o, r + 1e-3, sx / 2 + 1e-3)
				return cylHit(o, r, sx / 2), if (inner == nil) == (outer == nil) then 1 else 0
			end)
		end
	end)

	T.it("parts smaller than an art pixel keep one pixel; hidden ones do not", function()
		local cam = smallCam()
		local f = Raster.newFrame(cam.W, cam.H)
		local n = Raster.drawPart(f, cam, "Ball", { 0.31, 1.07, -0.2, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.05, 0.05, 0.05, 0, 4, constShade(9))
		T.eq(n, 1, "one pixel")
		local px, py = Raster.project(cam, 0.31, 1.07, -0.2)
		local idx = math.floor(py) * cam.W + math.floor(px)
		T.eq(buffer.readu16(f.id, idx * 2), 4, "under its centre")
		-- behind a big box it stays hidden
		local g = Raster.newFrame(cam.W, cam.H)
		Raster.drawBox(g, cam, { 1, 2, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 2, 2, 2, 0, 1, constShade(1))
		T.eq(Raster.drawPart(g, cam, "Block", { 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.04, 0.04, 0.04, 0, 2, constShade(2)), 0, "hidden")
	end)

	T.it("see-through parts blend into the colour and keep the depth and id behind", function()
		local cam = smallCam()
		local f = Raster.newFrame(cam.W, cam.H)
		Raster.drawBox(f, cam, { 0, 1, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 2, 2, 2, 0, 1, constShade(0xFF000010))
		local centre = math.floor(cam.H / 2) * cam.W + math.floor(cam.W / 2)
		local d0 = buffer.readf32(f.depth, centre * 4)
		local n = Raster.drawPart(f, cam, "Ball", { 0.8, 1.8, 0.8, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 1.5, 1.5, 1.5, 0, 2, constShade(0xFF000020), function(over: number, under: number): number
			return under + bit32.band(over, 0xFF) * 256
		end)
		T.truthy(n > 0, "drawn")
		T.eq(buffer.readu32(f.color, centre * 4), 0xFF002010, "mixed with what is behind")
		T.eq(buffer.readu16(f.id, centre * 2), 1, "id behind kept")
		T.near(buffer.readf32(f.depth, centre * 4), d0, 1e-9, "depth behind kept")
	end)

	------------------------------------------------------------------ pictures (Snapshot)
	local INK = Shading.pack(0x2B, 0x1E, 0x2E)
	local function alphaAt(px: buffer, W: number, x: number, y: number): number
		return bit32.rshift(buffer.readu32(px, (y * W + x) * 4), 24)
	end

	T.it("picture: a fitted model on a transparent background with an outer ink outline", function()
		local rot = Raster.rotation(45, ISO_PITCH)
		local solids = {
			Picture.solid("Cylinder", { 0, 0.5, 0, 0, -1, 0, 1, 0, 0, 0, 0, 1 }, 1, 2, 2, 0xF2A7C3),
			Picture.solid("Ball", { 0, 1.2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.5, 0.5, 0.5, 0xE0303A),
		}
		local W, H = 24, 24
		local cam = Picture.fit({ rot }, solids, W, H, 1)[1]
		T.eq(cam.W, W)
		T.eq(cam.H, H)
		local px = Picture.render(solids, cam)
		T.eq(buffer.len(px), W * H * 4)
		T.eq(alphaAt(px, W, 0, 0), 0, "corner transparent")
		T.eq(alphaAt(px, W, W - 1, H - 1), 0, "corner transparent")
		local ink, opaque, minX, maxX, minY, maxY = 0, 0, W, -1, H, -1
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				local c = buffer.readu32(px, (y * W + x) * 4)
				local a = bit32.rshift(c, 24)
				T.truthy(a == 0 or a == 255, "no half-transparent pixels on an opaque model")
				if a == 255 then
					opaque += 1
					minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x), math.min(minY, y), math.max(maxY, y)
					if c == INK then
						ink += 1
					end
				end
			end
		end
		T.truthy(opaque > 150, "the model fills the picture (" .. opaque .. ")")
		T.truthy(minX >= 0 and minY >= 0 and maxX <= W - 1 and maxY <= H - 1, "inside")
		T.truthy(maxX - minX >= W - 3 or maxY - minY >= H - 3, "fits the picture (pad 1 + outline)")
		T.truthy(ink >= 30, "outline drawn (" .. ink .. ")")
		-- every opaque pixel on the picture's silhouette is ink (the outline is outside the model)
		for y = 0, H - 1 do
			for x = 0, W - 1 do
				if alphaAt(px, W, x, y) == 255 then
					local edge = x == 0 or y == 0 or x == W - 1 or y == H - 1 or alphaAt(px, W, x - 1, y) == 0 or alphaAt(px, W, x + 1, y) == 0 or alphaAt(px, W, x, y - 1) == 0 or alphaAt(px, W, x, y + 1) == 0
					if edge then
						T.eq(buffer.readu32(px, (y * W + x) * 4), INK, "silhouette pixel " .. x .. "," .. y .. " is ink")
					end
				end
			end
		end
	end)

	T.it("picture: sun shadows inside the model, day palette whatever the world's mode", function()
		local rot = Raster.rotation(45, ISO_PITCH)
		-- a slab with a tall block on it: the block shades part of the slab's top
		local solids = {
			Picture.solid("Block", { 0, 0.25, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 4, 0.5, 4, 0xF6E7C8),
			Picture.solid("Block", { 0.6, 1.5, -0.4, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.8, 2, 0.8, 0x8A5A44),
		}
		local cam = Picture.fit({ rot }, solids, 32, 32, 1)[1]
		local lit = Picture.render(solids, cam, { shadows = true })
		local flat = Picture.render(solids, cam, { shadows = false })
		local diff = 0
		for i = 0, 32 * 32 - 1 do
			if buffer.readu32(lit, i * 4) ~= buffer.readu32(flat, i * 4) then
				diff += 1
			end
		end
		T.truthy(diff >= 5, "the block casts a shadow (" .. diff .. " pixels)")
		Shading.setMode("night")
		local night = Picture.render(solids, cam, { shadows = true })
		Shading.setMode("day")
		for i = 0, 32 * 32 - 1 do
			T.eq(buffer.readu32(night, i * 4), buffer.readu32(lit, i * 4), "pictures ignore the world's tint")
		end
	end)

	T.it("picture: a turntable shares one scale and turns about the box centre", function()
		local solids = {
			Picture.solid("Block", { 0, 0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 3, 1, 1, 0xF2A7C3),
			Picture.solid("Wedge", { 0, 1.25, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 1, 0.5, 1, 0xE0303A),
		}
		local rots = {}
		for k = 0, 7 do
			table.insert(rots, Raster.rotation(45 - 45 * k, ISO_PITCH))
		end
		local cams = Picture.fit(rots, solids, 32, 32, 1)
		T.eq(#cams, 8)
		for _, c in cams do
			T.near(c.s, cams[1].s, 1e-9, "same scale")
			-- the box centre (0, 0.75, 0) lands on the picture centre
			local x, y = Raster.project(c, 0, 0.75, 0)
			T.near(x, 16, 1e-6)
			T.near(y, 16, 1e-6)
			-- and every corner stays inside the picture
			for _, p in { { -1.5, 0, -0.5 }, { 1.5, 1.5, 0.5 }, { 1.5, 0, -0.5 }, { -1.5, 1.5, 0.5 } } do
				local qx, qy = Raster.project(c, p[1], p[2], p[3])
				T.truthy(qx >= 1 - 1e-6 and qx <= 31 + 1e-6 and qy >= 1 - 1e-6 and qy <= 31 + 1e-6, "inside the pad")
			end
		end
		-- a fixed scale overrides the fit
		local fixed = Picture.fit({ rots[1] }, solids, 32, 32, 1, 5)
		T.near(fixed[1].s, 5, 1e-9)
		-- an anchor puts the world origin at that art px in every view, whatever the model's box
		local taller = table.clone(solids)
		table.insert(taller, Picture.solid("Block", { 0, 3, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 0.5, 2, 0.5, 0xFFFFFF))
		for _, set in { solids, taller } do
			for _, c in Picture.fit(rots, set, 32, 48, 1, 5, { 16, 40 }) do
				local x, y = Raster.project(c, 0, 0, 0)
				T.near(x, 16, 1e-6, "anchored x")
				T.near(y, 40, 1e-6, "anchored y")
				T.near(c.s, 5, 1e-9)
			end
		end
		-- without a fixed scale the anchor is ignored (the fit centres the model)
		local fit = Picture.fit({ rots[1] }, solids, 32, 32, 1, nil, { 0, 0 })[1]
		local fx, fy = Raster.project(fit, 0, 0, 0)
		T.truthy(fx > 4 and fy > 4, "fit, not anchored")
		T.eq(Picture.shape("WedgePart", nil), "Wedge")
		T.eq(Picture.shape("Part", "Cylinder"), "Cylinder")
		T.eq(Picture.shape("MeshPart", nil), "Block")
	end)

	T.it("picture: see-through parts blend, glass alone keeps a see-through edge", function()
		local rot = Raster.rotation(45, ISO_PITCH)
		local solids = {
			Picture.solid("Block", { 0, 0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 1, 1, 1, 0xE0303A),
			Picture.solid("Ball", { 0, 0.9, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }, 2.2, 2.2, 2.2, 0xFFFFFF, false, 0.4),
		}
		local cam = Picture.fit({ rot }, solids, 32, 32, 1)[1]
		local px = Picture.render(solids, cam, { outline = "none" })
		local half = 0
		for i = 0, 32 * 32 - 1 do
			local a = bit32.rshift(buffer.readu32(px, i * 4), 24)
			if a > 0 and a < 255 then
				half += 1
			end
		end
		T.truthy(half > 20, "glass over the background stays see-through (" .. half .. ")")
	end)
end
