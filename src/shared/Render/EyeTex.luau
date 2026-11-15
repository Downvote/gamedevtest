--!strict
--!native
-- The driftlings' eyes, painted pixel by pixel on a smooth eyeball (Models/DriftKit.eye; GAME_DESIGN 6). Pure.
--
-- The request (2026-11-15): "these, are nice, but the eyes still do not look detailed or accurate and are mostly just
-- simple discs". An eye is now one eyeball (a smooth solid set into the head, Render/Raster.drawSolid) that the pixel
-- filter paints as it draws it, the way a modeller paints an eye texture onto a sphere: a white or dark eyeball, an iris
-- with a darker ring round its edge and a lighter lower half where the light comes through, a pupil shaped to the
-- animal (round, a cat's or a lizard's upright slit, a goat's or a toad's level bar), catchlights where the light from
-- the top left meets it, a dark rim where the eye sits in its lid, and the lids themselves (a sleepy eye's heavy upper
-- lid, a fierce one's slanting down to the middle, a happy one shut in an arch, the lid of a blink). Each feature is a
-- shape measured on the eye's face and covered by how much of the pixel lies inside it, so the edges are smoothed
-- with an in-between tone (anti-aliased), never jagged, at whatever size the eye is drawn.
--
-- The eye's face: u across (-1 .. 1, +u the eye frame's +X: the driftling's right), v up (-1 .. 1); the visible eyeball
-- is the disc within about 0.9 (its edge sinks into the head). A layer is a palette colour, a lift (-1 a band darker,
-- 0, +1 a band lighter on its ramp: Render/Shading.toonAt) and whether it glows (a catchlight, a lit eye: the lit band
-- whatever the light).
--   EyeTex.STYLE[name] -> code (Data/Creatures.EYES' twenty styles and "closed", the shut lid of a blink)
--   EyeTex.sample(code, u, v, side, ppu, iris, dark, lid, white)
--       -> (rgb1, lift1, glow1, rgb2, lift2, glow2, k)
--       the pixel at (u, v) on an eye (side -1 left, 1 right; ppu pixels to one unit of u or v; colours 0xRRGGBB): its
--       colour layer, and an edge layer over it covering k (0 .. 1) of the pixel (k 0: none)
local EyeTex = {}

local STYLE: { [string]: number } = {
	sparkle = 1,
	lashes = 2,
	button = 3,
	bead = 4,
	dot = 5,
	star = 6,
	heart = 7,
	round = 8,
	wide = 9,
	specs = 10,
	slit = 11,
	bar = 12,
	ringed = 13,
	sleepy = 14,
	fierce = 15,
	happy = 16,
	glow = 17,
	gem = 18,
	visor = 19,
	compound = 20,
	closed = 21,
}
EyeTex.STYLE = STYLE

local sqrt, abs, max, min, floor = math.sqrt, math.abs, math.max, math.min, math.floor

-- The layers being stacked for the pixel: the colour under (a) and one edge over it (b, covering k).
local A_RGB, A_LIFT, A_GLOW = 0, 0, false
local B_RGB, B_LIFT, B_GLOW, K = 0, 0, false, 0
local PPU = 8

-- Paint a layer whose shape's signed distance at the pixel is sd (units of u and v; below 0 inside).
local function paint(sd: number, rgb: number, lift: number, glow: boolean)
	local cov = 0.5 - sd * PPU
	if cov <= 0 then
		return
	end
	if cov >= 1 then
		A_RGB, A_LIFT, A_GLOW = rgb, lift, glow
		K = 0
		return
	end
	-- (an edge: if one is already showing, the nearer of the two colours under it settles as the base first)
	if K > 0 and K >= 0.5 then
		A_RGB, A_LIFT, A_GLOW = B_RGB, B_LIFT, B_GLOW
	end
	B_RGB, B_LIFT, B_GLOW, K = rgb, lift, glow, cov
end

local function circle(u: number, v: number, cx: number, cy: number, r: number): number
	local du, dv = u - cx, v - cy
	return sqrt(du * du + dv * dv) - r
end

-- (an ellipse's signed distance, close enough near its edge: the level over the gradient)
local function ellipse(u: number, v: number, cx: number, cy: number, ax: number, ay: number): number
	local du, dv = (u - cx) / ax, (v - cy) / ay
	local l = sqrt(du * du + dv * dv)
	if l < 1e-6 then
		return -min(ax, ay)
	end
	local gx, gy = du / ax, dv / ay
	return (l - 1) * l / sqrt(gx * gx + gy * gy)
end

-- the two catchlights: a big one up toward the light (the top left) and a small one low on the other side
local function shines(u: number, v: number, white: number, big: number, small: number, bx: number?, by: number?)
	local x, y = bx or -0.3, by or 0.32
	if PPU >= 2 then
		paint(circle(u, v, x, y, big), white, 0, true)
	end
	if PPU >= 4 and small > 0 then
		paint(circle(u, v, -x * 0.95, -y * 1.05, small), white, 0, true)
	end
end

-- the dark rim where the eyeball sits in its lids (an outline round the eye, a pixel and a bit wide at any size),
-- heavier along the top where the upper lid's lashes are
EyeTex.EDGE = 0.9 -- where the eyeball meets the head, as a share of its radius (Models/DriftKit sets its bulge so)
local function rim(u: number, v: number, dark: number)
	if PPU < 3 then
		return -- (an eye a few pixels across: the head's own outline is its rim)
	end
	local r = sqrt(u * u + v * v)
	local w = min(1.15 / PPU, 0.22)
	local top = if v > 0 then v / max(r, 1e-6) else 0
	paint(EyeTex.EDGE - w * (1 + 1.3 * top * top) - r, dark, -1, false)
end

-- an upper lid of the body colour down to `edge(u)`, a dark lash line just under its edge
local function upperLid(u: number, v: number, edge: number, lid: number, dark: number)
	paint(edge - 0.12 - v, dark, -1, false)
	paint(edge - v, lid, 0, false)
end

-- the shut lid: the body colour, a dark line across it bowing down (a content shut eye) or up (`up`: a happy arch)
local function shut(u: number, v: number, lid: number, dark: number, up: boolean)
	A_RGB, A_LIFT, A_GLOW, K = lid, 0, false, 0
	local c = if up then 0.32 - 0.62 * u * u else -0.28 + 0.5 * u * u
	local sd = max(abs(v - c) - 0.1, abs(u) - 0.74)
	paint(sd, dark, -1, false)
end

-- the hexagonal cells of a compound eye: the distance to the nearest cell's middle
local function hexCell(u: number, v: number, s: number): number
	-- (two offset rectangular lattices of centres; the nearer of the two)
	local w, h = s, s * 0.866
	local function near(ox: number, oy: number): number
		local cx = floor((u - ox) / w + 0.5) * w + ox
		local cy = floor((v - oy) / (2 * h) + 0.5) * (2 * h) + oy
		local du, dv = u - cx, v - cy
		return sqrt(du * du + dv * dv)
	end
	return min(near(0, 0), near(w / 2, h))
end

-- The dark, glossy eye of a cute creature: a dark eyeball, the iris showing as a band of colour low in it, lighter at
-- the bottom where the light comes through, a darker pupil, two catchlights.
local function darkEye(u: number, v: number, iris: number, dark: number, white: number)
	A_RGB, A_LIFT, A_GLOW, K = dark, 0, false, 0
	paint(circle(u, v, 0, -0.18, 0.6), iris, 0, false)
	paint(circle(u, v, 0, -0.4, 0.3), iris, 1, false)
	-- (the top of the iris in the lid's shadow, so the colour reads as a crescent low in the eye)
	paint(circle(u, v, 0, 0.36, 0.56), dark, 0, false)
	paint(circle(u, v, 0, -0.08, 0.24), dark, -1, false)
end

function EyeTex.sample(code: number, u: number, v: number, side: number, ppu: number, iris: number, dark: number, lid: number, white: number): (number, number, boolean, number, number, boolean, number)
	PPU = max(1, ppu)
	A_RGB, A_LIFT, A_GLOW = dark, 0, false
	B_RGB, B_LIFT, B_GLOW, K = dark, 0, false, 0
	local tiny = PPU < 3 -- (an eye only a few pixels across: its main colour and one catchlight)
	if code == 21 then
		shut(u, v, lid, dark, false)
	elseif code == 16 then
		shut(u, v, lid, dark, true)
	elseif code == 1 or code == 2 or code == 6 or code == 7 or code == 14 or code == 15 then
		if tiny then
			A_RGB = dark
			shines(u, v, white, 0.3, 0)
		else
			darkEye(u, v, iris, dark, white)
			if code == 6 then
				-- a four-pointed star of light in the eye, a small catchlight beside it
				local du, dv = abs(u + 0.06), abs(v - 0.02)
				local s = (du ^ 0.55 + dv ^ 0.55) ^ (1 / 0.55)
				paint(s - 0.5, white, 0, true)
				paint(circle(u, v, 0.3, -0.36, 0.09), white, 0, true)
			elseif code == 7 then
				-- a heart of light in the eye, a small catchlight above it
				local x, y = (u + 0.02) / 0.42, (v + 0.02) / 0.42
				local hy = y + 0.35
				local heart = (x * x + hy * hy - 0.4) ^ 3 - x * x * hy * hy * hy
				paint(if heart < 0 then -0.05 else 0.05, white, 0, true)
				paint(circle(u, v, -0.3, 0.36, 0.13), white, 0, true)
			else
				shines(u, v, white, 0.22, 0.1)
			end
			rim(u, v, dark)
			if code == 14 then
				upperLid(u, v, 0.14 + 0.12 * u * u, lid, dark)
			elseif code == 15 then
				-- slanting down toward the middle of the face (the inner side is -side)
				upperLid(u, v, 0.5 + 0.42 * u * side, lid, dark)
			end
		end
	elseif code == 3 or code == 4 or code == 5 then
		-- a glossy bead: dark, a ring of deep colour round the pupil where the light gets in, a softer reflection of the
		-- ground low in it, a catchlight
		A_RGB = dark
		if not tiny and code ~= 5 then
			paint(circle(u, v, 0, -0.06, 0.62), dark, 1, false)
			paint(circle(u, v, 0, -0.02, 0.44), dark, -1, false)
			paint(max(circle(u, v, 0.05, -0.36, 0.42), -circle(u, v, 0.05, -0.1, 0.5)), iris, 1, false)
		end
		if code == 5 then
			shines(u, v, white, 0.24, 0)
		else
			shines(u, v, white, if code == 3 then 0.26 else 0.24, 0.08)
		end
	elseif code == 8 or code == 9 or code == 10 then
		-- a cartoon eye: the white, the lid's shadow over its top, the iris with its darker ring and lighter lower half,
		-- the pupil, the catchlights, the rim
		-- (the white keeps bright, glossy, whatever the light; only the lid's shadow over its top is lit by the light)
		A_RGB, A_LIFT, A_GLOW = white, 0, true
		if not tiny then
			paint(0.5 - v, white, -1, false)
		end
		local wide = code == 9
		local ir = if wide then 0.36 else 0.52
		local iy = if wide then -0.16 else -0.06
		paint(circle(u, v, 0, iy, ir), iris, -1, false)
		if not tiny then
			paint(circle(u, v, 0, iy, ir - 0.08), iris, 0, false)
			paint(circle(u, v, 0, iy - ir * 0.42, ir * 0.55), iris, 1, false)
		end
		paint(circle(u, v, 0, iy, ir * 0.46), dark, -1, false)
		shines(u, v, white, if wide then 0.12 else 0.14, 0.06, -0.2, iy + 0.24)
		rim(u, v, dark)
	elseif code == 11 or code == 12 then
		-- a cat's, a lizard's or a goat's eye: all iris, darker under the lid and round its edge, lighter low down, the
		-- slit or the bar of the pupil
		A_RGB, A_LIFT = iris, 0
		if not tiny then
			paint(0.5 - v, iris, -1, false)
			paint(circle(u, v, 0, -0.48, 0.46), iris, 1, false)
			paint(0.7 - sqrt(u * u + v * v), iris, -1, false)
		end
		if code == 11 then
			paint(ellipse(u, v, 0, 0, 0.14, 0.68), dark, -1, false)
		else
			paint(ellipse(u, v, 0, -0.02, 0.6, 0.15), dark, -1, false)
		end
		shines(u, v, white, 0.13, 0.06, -0.32, 0.34)
		rim(u, v, dark)
	elseif code == 13 then
		-- a bird's or an owl's eye: a broad iris almost filling it, a darker ring round it, a big round pupil
		A_RGB = dark
		paint(circle(u, v, 0, 0, 0.72), iris, -1, false)
		if not tiny then
			paint(circle(u, v, 0, 0, 0.62), iris, 0, false)
			paint(circle(u, v, 0, -0.3, 0.34), iris, 1, false)
		end
		paint(circle(u, v, 0, 0, 0.34), dark, -1, false)
		shines(u, v, white, 0.15, 0.07, -0.24, 0.27)
		rim(u, v, dark)
	elseif code == 17 then
		-- an eye that glows: lit in the iris colour with a white core, a dark rim
		A_RGB, A_GLOW = iris, true
		paint(circle(u, v, -0.06, 0.06, 0.36), white, 0, true)
		rim(u, v, dark)
	elseif code == 18 then
		-- a cut gem: a diamond of the iris colour on dark, its four facets lit from the top left, a table in its middle
		A_RGB = dark
		local du, dv = u, v + 0.02
		local d = abs(du) + abs(dv)
		local lift = if du <= 0 and dv >= 0 then 1 elseif du > 0 and dv < 0 then -1 else 0
		paint((d - 0.64) * 0.7, iris, lift, false)
		paint((d - 0.24) * 0.7, iris, 1, false)
		if not tiny then
			paint(circle(u, v, -0.18, 0.24, 0.07), white, 0, true)
		end
		rim(u, v, dark)
	elseif code == 19 then
		-- a lit slot across a dark eye
		A_RGB = dark
		local sd = max(abs(u) - 0.8, abs(v) - 0.2)
		paint(sd, iris, 0, true)
		paint(max(abs(u) - 0.72, abs(v) - 0.07), white, 0, true)
	elseif code == 20 then
		-- a compound eye: a dark dome of little round cells, each catching a glint of the iris colour
		A_RGB = dark
		if not tiny then
			local cd = hexCell(u, v, 0.3)
			paint(cd - 0.1, dark, 1, false)
			paint(cd - 0.05, iris, 0, false)
		end
		shines(u, v, white, 0.18, 0, -0.32, 0.3)
	else
		A_RGB = dark
		shines(u, v, white, 0.24, 0.08)
	end
	return A_RGB, A_LIFT, A_GLOW, B_RGB, B_LIFT, B_GLOW, K
end

return EyeTex
