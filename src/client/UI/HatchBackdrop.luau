--!strict
--!native
-- The hatch scene's painted backdrop (UI/HatchScene; GAME_DESIGN 6.2): the request of 2026-11-13, "the egg hatching
-- scene isnt detailed enough. add much much more detail to it, especially the egg. you are allowed to use 2d elements
-- as well for the background". A picture drawn pixel by pixel into one EditableImage at the world's art grid (each art
-- pixel K x K screen px, like the pixel layer), shown on a ScreenGui just behind the pixel layer: the stage's sky is
-- see-through (CameraController Stage.clear), so the egg stands in front of it.
-- Each rarity has its own sky (a cozy sunset for a common egg, a golden afternoon, a blue twilight, a violet night, a
-- deep gold night, and since 2026-11-14 a rose night under two moons for a mythic egg and a deep starry sky with a
-- ringed planet and the band of the galaxy across it for a celestial one; since 2026-11-20 a red dusk under an eclipse
-- ringed with fire for an ancient egg and a dawn of every colour, a ringed white sun, a rainbow and the galaxy fading
-- into the morning, for an eternal one): the sky in bands with ordered dither between
-- them (never a smear), the sun, the moons or the planet in one flat tone with anti-aliased edges, stars (single
-- pixels and little crosses), aurora curtains on the rarest nights, three ranges of grassy hills going darker toward
-- the front (lit caps, patches, blades, tufts; ridges anti-aliased at their steps: see "the land" below) and a glow
-- round the egg in dithered rings. (The clouds, the trees along the nearest hills and the two islets
-- floating far off went on 2026-11-14: "For the hatch screen, remove the trees in the background, and the floating
-- islands as well", then "Remove the clouds in the hatch screen background as well".)
-- Since 2026-11-14 ("Polish the egg opening backgrounds even more, drawing in a base for the eggs to land on", and "add an
-- expanding circle ring that constantly emits below each egg") a round pedestal stands where the egg comes down: its
-- top an ellipse with a lit rim at the back left, an inlaid ring (gems on it from rare up), the egg's dithered shadow,
-- its side lit on the left and shaded on the right with a carved band and the joints of its stones, standing on a
-- fluted column of the same stone that rises from below the picture, a 1 px outline round it all, in each
-- rarity's stone (BASES; since 2026-11-20 the outline is a darker step of the stone beside it, leaning to the base's ink); and the sky's corners a dithered step darker. Since 2026-11-15 ("it seems like the outline gets broken in the pillars. also, it
-- dosent seem like the top part is casting a shadow on the bottom part of the pillar") the outline runs unbroken down
-- the whole shaft (it stopped under the cap), each turn of it on a curve a step of anti-aliasing instead of a doubled
-- pixel, the flutes keep off the shaft's edges, and the cap casts a shadow on the top of the shaft: a band two steps
-- down the shaft's ramp at the lip and one step under it, deeper to the right (the light comes from the top left),
-- stepping at the flutes. Once the egg has landed (`land`) rings of light spread over the pedestal's top
-- from under it, one every RING_EVERY s, each a clean 1 px ellipse stepping from bright to faint as it widens (their
-- own image on the sky's life layer, so the egg stands in front of them).
--   HatchBackdrop.show(r, ex, ey, base?)   paint rarity r's sky with the egg's glow at art pixel (ex, ey) and show it;
--                                   base { x, y, w }: the pedestal's top centre and half width, art px
--   HatchBackdrop.land()            the egg is down: a strong ring now, then rings for as long as the backdrop shows
--   HatchBackdrop.rings() -> number the rings spreading now (sims and previews)
--   HatchBackdrop.step(dt)          the sky's life (a layer between the picture and the pixel layer, so the islet hides it):
--                                   little flocks of birds flapping across a day or twilight sky, shooting stars and
--                                   twinkling stars on a night one; all whole art pixels, solid colours
--   HatchBackdrop.pulse()           one more ring over the pedestal now (a crack, a landing, the hatch)
--   HatchBackdrop.light(l?)         the light behind the egg (UI/HatchScene, every frame; nil: none): its god rays,
--                                   its halo, its shadow while it falls, rings (shockwaves, dust), motes behind it and
--                                   the hush (the sky going dark); drawn on the next `step`, behind the egg and the
--                                   pedestal ("the light behind the egg" below)
--   HatchBackdrop.offset(dx, dy)    the picture and its life layer moved by whole art px (a jolt; 0, 0 back)
--   HatchBackdrop.debugLight()      the god rays lit, whether the halo and the glow show, the hush (sims, previews)
--   HatchBackdrop.hide()            take it away (and free its image)
--   HatchBackdrop.paint(r, W, H, ex, ey, base?) -> buffer   the picture itself (RGBA, W x H)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ScreenSize = require(script.Parent.Parent.Pixel.ScreenSize)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)

local HatchBackdrop = {}

type Sky = {
	stops: { number }, -- the sky's colours from the top down to the horizon
	horizon: number, -- where the last stop is reached (share of the height)
	body: string, -- "sun" | "crescent" | "moon" | "bigsun" | "twomoons" | "planet" | "eclipse" | "halosun"
	bodyC: { number }, -- its fill, the second moon's fill (mythic), its spots or bands (an eclipse: its fire, the dark
	-- disc, its rim; a ringed sun: its fill, its ring, its rays' tips)
	rainbow: boolean?, -- a rainbow arching over the hills (eternal)
	bodyR: number, -- its radius (share of the height)
	stars: number,
	milky: number?, -- the galaxy's band of light across the sky (its colour), thick with stars
	ring: { number }?, -- the planet's ring: lit, shade
	twinkle: { number }?, -- the twinkling stars' colours (on screen, `step`), and how many there are with them
	aurora: { number }?,
	hills: { { number } }, -- far to near: fill, rim
	glow: number,
	glowK: number, -- how strong (0 .. 1)
	glowR: number, -- its radius (share of the height)
}

local SKIES: { Sky } = {
	-- a cozy sunset
	{
		stops = { 0x7D72BE, 0xAA7DB8, 0xD98BA8, 0xF2A38D, 0xF8C690, 0xFBE1AE },
		horizon = 0.72,
		body = "sun",
		bodyC = { 0xFFEFB4, 0xFFCF7A, 0xFFB86A },
		bodyR = 0.12,
		stars = 0,
		aurora = nil,
		hills = { { 0xC995AC, 0xDDA9B9 }, { 0x9C7AA0, 0xB08DB2 }, { 0x6E5A86, 0x82709A } },
		glow = 0xFFF2CC,
		glowK = 0.45,
		glowR = 0.3,
	},
	-- a golden afternoon
	{
		stops = { 0x6CC0D5, 0x90D2D1, 0xB5DEC5, 0xDBE8B9, 0xF4E7BD, 0xFAEFD2 },
		horizon = 0.72,
		body = "sun",
		bodyC = { 0xFFFBE0, 0xFFE9A6, 0xFFE09A },
		bodyR = 0.08,
		stars = 0,
		aurora = nil,
		hills = { { 0xA4D8B0, 0xBEE4C2 }, { 0x7CBE8E, 0x96CEA2 }, { 0x58A070, 0x6CB282 } },
		glow = 0xE4FFC2,
		glowK = 0.5,
		glowR = 0.34,
	},
	-- a blue twilight
	{
		stops = { 0x1C2A56, 0x27396F, 0x36508D, 0x516CAD, 0x7E8EC6, 0xB4B8DA },
		horizon = 0.74,
		body = "crescent",
		bodyC = { 0xF7F3DC, 0xDCD6B8, 0xD0C8A6 },
		bodyR = 0.085,
		stars = 70,
		aurora = nil,
		hills = { { 0x5064A0, 0x6277B2 }, { 0x3B4D84, 0x4B5E96 }, { 0x293762, 0x354574 } },
		glow = 0xC4E8FF,
		glowK = 0.6,
		glowR = 0.4,
	},
	-- a violet night
	{
		stops = { 0x140D2E, 0x22174A, 0x372564, 0x553482, 0x8551A0, 0xC27FB8 },
		horizon = 0.76,
		body = "moon",
		bodyC = { 0xF8ECF4, 0xDCC6E0, 0xCDB2D4 },
		bodyR = 0.1,
		stars = 140,
		aurora = { 0x86E6C8, 0xF2A2D6 },
		hills = { { 0x5C3F84, 0x6C4F96 }, { 0x45306A, 0x553E7C }, { 0x2E2050, 0x3A2A60 } },
		glow = 0xF2C0FF,
		glowK = 0.68,
		glowR = 0.46,
	},
	-- a deep gold night
	{
		stops = { 0x180E2C, 0x32194A, 0x5C2653, 0x964151, 0xD26B4E, 0xF6A758 },
		horizon = 0.78,
		body = "bigsun",
		bodyC = { 0xFFEFA2, 0xFFCB5C, 0xFFB046 },
		bodyR = 0.16,
		stars = 110,
		aurora = { 0xFFD878, 0xFF9C6A },
		hills = { { 0x8C4C5C, 0xA05E68 }, { 0x62334F, 0x74405C }, { 0x3C1E3E, 0x4A284A } },
		glow = 0xFFEAA6,
		glowK = 0.8,
		glowR = 0.55,
	},
	-- a rose night under two moons (mythic)
	{
		stops = { 0x1A0A26, 0x34113F, 0x581B58, 0x87286B, 0xC0457E, 0xF27F9E },
		horizon = 0.78,
		body = "twomoons",
		bodyC = { 0xFFF0F4, 0xF2C8D8, 0xE4AEC6 },
		bodyR = 0.13,
		stars = 170,
		twinkle = { 0xFFFFFF, 0xFFC8E4, 0xFF9CCB },
		aurora = { 0xFF8CC6, 0xFFD2A8 },
		hills = { { 0x8A3A6E, 0x9E4C80 }, { 0x63285A, 0x76346A }, { 0x3E1640, 0x4C1E4E } },
		glow = 0xFFC6E2,
		glowK = 0.84,
		glowR = 0.58,
	},
	-- the deep starry sky: a ringed planet, the band of the galaxy (celestial)
	{
		stops = { 0x060820, 0x0C1238, 0x141F54, 0x1D3270, 0x29508A, 0x4C8EA8 },
		horizon = 0.78,
		body = "planet",
		bodyC = { 0xC9F2FF, 0x84C0E6, 0xA2DCF6 },
		bodyR = 0.1,
		stars = 260,
		milky = 0xB6C8FF,
		ring = { 0xFFF0C8, 0xC8B49A },
		twinkle = { 0xFFFFFF, 0xC4F6FF, 0xFFF0B0, 0xF8C4FF },
		aurora = { 0x8CF2E8, 0xC6A8FF },
		hills = { { 0x2C4C86, 0x3A5E98 }, { 0x1E3668, 0x2A447A }, { 0x12224A, 0x1A2E5A } },
		glow = 0xD6F6FF,
		glowK = 0.9,
		glowR = 0.62,
	},
	-- a red dusk of the first days under an eclipse, its ring of fire, curtains of ember light (ancient: the request of
	-- 2026-11-20, "make more higher tier eggs, about 2 more tiers")
	{
		stops = { 0x14060A, 0x2C0A10, 0x4E1214, 0x7A2216, 0xB2421C, 0xE8782E },
		horizon = 0.78,
		body = "eclipse",
		bodyC = { 0xFFB45A, 0x1A0A0E, 0xFFF0C0 },
		bodyR = 0.12,
		stars = 150,
		twinkle = { 0xFFF0C0, 0xFFC45A, 0xFF8A3A },
		aurora = { 0xFF6A2E, 0xFFB24A },
		hills = { { 0x5A1C1C, 0x6E2622 }, { 0x3E1216, 0x50181A }, { 0x24080C, 0x320C10 } },
		glow = 0xFFC88A,
		glowK = 0.92,
		glowR = 0.64,
	},
	-- a dawn of every colour: a white sun with a ring of light round it, a rainbow arching over the hills, the band of
	-- the galaxy fading into the morning and curtains of light (eternal)
	{
		stops = { 0x0C0A2A, 0x1C1650, 0x34247A, 0x5E3A9E, 0xA45CB8, 0xF2A6C8 },
		horizon = 0.78,
		body = "halosun",
		bodyC = { 0xFFFBEA, 0xFFE6A0, 0xFFD6F4 },
		bodyR = 0.085,
		stars = 220,
		milky = 0xFFE0FA,
		rainbow = true,
		twinkle = { 0xFFFFFF, 0xFFC0E8, 0xC8F4FF, 0xFFF0A8, 0xC8FFC8 },
		aurora = { 0x9CF2D2, 0xFFA8E6 },
		hills = { { 0x7A4A9C, 0x8E5CAE }, { 0x56347E, 0x684292 }, { 0x34205A, 0x42286A } },
		glow = 0xFFF0FF,
		glowK = 0.95,
		glowR = 0.66,
	},
}

-- Each rarity's pedestal (`paint`'s base): its top, the top's lit rim, its side lit, plain and shaded, the carved band
-- and the inlaid ring, the gems, the ink (the dark its shading leans to, and its outline a little), the flowers along
-- the bottom, the rings' light.
type Base = { top: number, topLit: number, sideLit: number, side: number, sideDark: number, trim: number, gem: number, ink: number, flower: number, ring: number }
local BASES: { Base } = {
	-- warm sandstone under the sunset
	{ top = 0xD9B89E, topLit = 0xF0D6BA, sideLit = 0xC79E8A, side = 0xB08878, sideDark = 0x8C6A68, trim = 0x7E5C62, gem = 0xFFD08A, ink = 0x3A2A3E, flower = 0xFFE3A8, ring = 0xFFF4D6 },
	-- mossy stone in the afternoon
	{ top = 0xA2CE8E, topLit = 0xC2E6A6, sideLit = 0xBFB09A, side = 0xA89A86, sideDark = 0x847868, trim = 0x6E8E60, gem = 0xFFF2A8, ink = 0x2C3A30, flower = 0xFFF6C0, ring = 0xF4FFD8 },
	-- pale blue stone at twilight
	{ top = 0xB6CAE8, topLit = 0xD8E6FA, sideLit = 0xA4B8DC, side = 0x8EA2CA, sideDark = 0x6C7EAA, trim = 0x5A6A9A, gem = 0xBFF6FF, ink = 0x1C2240, flower = 0xD6F0FF, ring = 0xDFF8FF },
	-- violet stone with pink runes
	{ top = 0xA88ECC, topLit = 0xC6AAE4, sideLit = 0x947CBE, side = 0x7E68AA, sideDark = 0x5E4C88, trim = 0xE89CCC, gem = 0xFFBCE8, ink = 0x1C1430, flower = 0xFFB0DA, ring = 0xFFD6F2 },
	-- cream marble trimmed with gold
	{ top = 0xECE0C8, topLit = 0xFCF4E2, sideLit = 0xDECCAA, side = 0xC8B696, sideDark = 0xA2906E, trim = 0xF2C24E, gem = 0xFFE88C, ink = 0x2E2216, flower = 0xFFE07A, ring = 0xFFF2B4 },
	-- rose quartz, pearl trim
	{ top = 0xEEB4C8, topLit = 0xFAD4E0, sideLit = 0xDC9EB8, side = 0xC88AA6, sideDark = 0xA46C8A, trim = 0xFFF0F6, gem = 0xFFFFFF, ink = 0x3A1E30, flower = 0xFFD0E0, ring = 0xFFE8F2 },
	-- dark starstone with cyan inlay
	{ top = 0x3C4E88, topLit = 0x566AAA, sideLit = 0x32427C, side = 0x28366C, sideDark = 0x1A2452, trim = 0x80E8F2, gem = 0xD8F8FF, ink = 0x060A1E, flower = 0x9CF0FF, ring = 0xC8FAFF },
	-- black stone with lava in its inlay and sparks in the stone (ancient)
	{ top = 0x40303A, topLit = 0x5C4650, sideLit = 0x382830, side = 0x2C1E26, sideDark = 0x1C1218, trim = 0xFF7A32, gem = 0xFFD27A, ink = 0x0C0608, flower = 0xFF9A4A, ring = 0xFFC48A },
	-- pearl marble with an orchid inlay, white gems and flecks of colour (eternal)
	{ top = 0xEEE6F6, topLit = 0xFFFFFF, sideLit = 0xDCD0EC, side = 0xC6B8DA, sideDark = 0xA090BC, trim = 0xE68CFF, gem = 0xFFFFFF, ink = 0x22183A, flower = 0xFFC8F4, ring = 0xFFF2FF },
}

------------------------------------------------------------------ colours
local BAYER: { number } = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function bay(x: number, y: number): number
	return (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16
end

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16) % 256, bit32.rshift(c, 8) % 256, c % 256
end

local function mix(a: number, b: number, k: number): number
	local ar, ag, ab = rgb(a)
	local br, bg, bb = rgb(b)
	local r = math.floor(ar + (br - ar) * k + 0.5)
	local g = math.floor(ag + (bg - ag) * k + 0.5)
	local bl = math.floor(ab + (bb - ab) * k + 0.5)
	return r * 65536 + g * 256 + bl
end

-- a 0xRRGGBB colour as the image's RGBA bytes (little-endian u32, opaque)
local function packed(c: number): number
	local r, g, b = rgb(c)
	return r + g * 256 + b * 65536 + 255 * 16777216
end

local function hash(n: number): number
	local x = math.floor(n) % 2147483647
	x = (x * 1103515245 + 12345) % 2147483648
	x = (x * 1103515245 + 12345) % 2147483648
	return x / 2147483648
end

-- a well-mixed number for a pixel (x, y): no lines across the picture, as a plain sum of the two would draw
local function hash2(x: number, y: number): number
	return hash(x * 92821 + math.floor(hash(y * 7 + 13) * 1000003))
end

-- a lattice point's value for the smooth noise below (seed, a, b), kept in `cache` (the noise asks each point often)
local function lattice(cache: { [number]: number }, seed: number, a: number, b: number): number
	local key = (a + 4096) * 8192 + (b + 4096)
	local h = cache[key]
	if h == nil then
		h = hash2(a * 3 + seed * 1013 + 50000, b * 5 + seed * 331 + 50000)
		cache[key] = h
	end
	return h
end

-- smooth value noise (0 .. 1) at (u, v): soft blobs about one unit across, for the grass's patches and clumps
local function vnoise(u: number, v: number, seed: number, cache: { [number]: number }): number
	local xi, yi = math.floor(u), math.floor(v)
	local fx, fy = u - xi, v - yi
	fx = fx * fx * (3 - 2 * fx)
	fy = fy * fy * (3 - 2 * fy)
	local a, b = lattice(cache, seed, xi, yi), lattice(cache, seed, xi + 1, yi)
	local c, d = lattice(cache, seed, xi, yi + 1), lattice(cache, seed, xi + 1, yi + 1)
	local top = a + (b - a) * fx
	return top + (c + (d - c) * fx - top) * fy
end

------------------------------------------------------------------ painting
-- The picture as 0xRRGGBB per pixel in a plain array (painted layer over layer), packed into RGBA at the end.
type BaseAt = { x: number, y: number, w: number }
-- the last picture painted (0xRRGGBB per pixel, row by row) and its pedestal's pixels (1 the top, 2 the side and the
-- shaft, 3 its outline): the light behind the egg blends over the one and keeps off the other
local skyPx: { number }? = nil
local pedMask: buffer? = nil

function HatchBackdrop.paint(r: number, W: number, H: number, ex: number, ey: number, ped: BaseAt?): buffer
	local sky = SKIES[math.clamp(r, 1, #SKIES)]
	local px: { number } = table.create(W * H, 0)
	skyPx, pedMask = px, nil
	local function get(x: number, y: number): number
		return px[math.clamp(y, 0, H - 1) * W + math.clamp(x, 0, W - 1) + 1]
	end
	local function set(x: number, y: number, c: number)
		if x >= 0 and y >= 0 and x < W and y < H then
			px[y * W + x + 1] = c
		end
	end
	-- the sky: solid bands, each meeting the next in a short dithered seam
	local stops = sky.stops
	local hy = sky.horizon * H
	-- range li's ridge (far to near) at x: a wavy line, art px down from the top
	local function ridgeOf(li: number, x: number): number
		local base = hy - H * 0.13 + li * H * 0.075
		local amp = H * (0.05 - li * 0.008)
		return base - amp * (0.6 + 0.4 * math.sin(x * (0.011 + li * 0.004) + li * 2.3)) - amp * 0.5 * math.sin(x * (0.031 + li * 0.006) + li)
	end
	-- (the sky reaches its horizon colour a little above the far range's highest crest, so no dithered seam lies along
	-- a ridge: it read as the hills' anti-aliasing in the wrong colour)
	local crest = hy
	for x = 0, W - 1 do
		crest = math.min(crest, ridgeOf(1, x + 0.5))
	end
	local hyS = math.max(H * 0.3, math.min(hy, crest - 3))
	for y = 0, H - 1 do
		local t = math.clamp(y / hyS, 0, 1) * (#stops - 1)
		local i = math.min(#stops - 1, math.floor(t))
		local f = t - i
		local k = math.clamp((f - 0.3) / 0.4, 0, 1)
		local a, b = stops[i + 1], stops[math.min(#stops, i + 2)]
		local row = y * W
		for x = 0, W - 1 do
			px[row + x + 1] = if k > bay(x, y) then b else a
		end
	end
	-- the galaxy (the celestial sky): a broad band of light slanting up across it, brightest along its spine, in
	-- dithered steps, a darker lane of dust down its middle, thick with stars
	local milky = sky.milky
	local function spine(x: number): number
		return H * 0.5 - x * 0.42 + math.sin(x * 0.03) * H * 0.03
	end
	if milky then
		local bw = H * 0.16
		for y = 0, math.floor(hy) do
			for x = 0, W - 1 do
				local d = math.abs(y + 0.5 - spine(x + 0.5)) / bw
				if d < 1 then
					local k = (1 - d) ^ 1.3 * (0.75 + 0.25 * math.sin(x * 0.09 + y * 0.05))
					if d < 0.16 and math.sin(x * 0.05) > -0.3 then
						k *= 0.45 -- (the lane of dust)
					end
					local lvl = math.floor(k * 3 + bay(x, y))
					if lvl > 0 then
						set(x, y, mix(get(x, y), milky, lvl * 0.13))
					end
				end
			end
		end
		for i = 1, 140 do
			local x = math.floor(hash(i * 23 + 9) * W)
			local off = (hash(i * 37 + 1) + hash(i * 41 + 2) - 1) * H * 0.14
			local y = math.floor(spine(x + 0.5) + off)
			if y >= 0 and y < hy then
				set(x, y, mix(get(x, y), 0xFFFFFF, if hash(i * 5) > 0.6 then 0.9 else 0.5))
			end
		end
	end
	-- aurora curtains (the rarest nights): wavy ribbons hanging in streaks, fading at their edges in dither
	local au = sky.aurora
	if au then
		for band = 1, 2 do
			local col = au[band]
			local base = H * (0.12 + 0.1 * band)
			for x = 0, W - 1 do
				local cy = base + math.sin(x * 0.021 + band * 1.7) * H * 0.06 + math.sin(x * 0.007 + band) * H * 0.04
				local streak = 0.55 + 0.45 * math.sin(x * 0.31 + band * 2.1) * math.sin(x * 0.077)
				local th = H * 0.07 * (0.7 + 0.3 * streak)
				for y = math.max(0, math.floor(cy - th * 1.6)), math.min(H - 1, math.floor(cy + th * 0.6)) do
					local d = (y - cy) / th
					local k = if d < 0 then 1 + d / 1.6 else 1 - d / 0.6
					k = math.clamp(k * streak, 0, 1) * 0.7
					local lvl = math.floor(k * 3 + bay(x, y))
					if lvl > 0 then
						set(x, y, mix(get(x, y), col, lvl / 4))
					end
				end
			end
		end
	end
	-- stars: single pixels in two brightnesses, now and then a little cross with a bright middle
	for i = 1, sky.stars do
		local x = math.floor(hash(i * 7 + r) * W)
		local y = math.floor(hash(i * 13 + 5) * hy * 0.8)
		local bright = hash(i * 3 + 11)
		local base = get(x, y)
		if bright > 0.88 then
			set(x, y, 0xFFFFFF)
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				set(x + d[1], y + d[2], mix(get(math.clamp(x + d[1], 0, W - 1), math.clamp(y + d[2], 0, H - 1)), 0xFFFFFF, 0.5))
			end
		else
			set(x, y, mix(base, 0xFFFFFF, if bright > 0.5 then 0.85 else 0.45))
		end
	end
	-- a rainbow arching over the hills (the eternal dawn, 2026-11-20): six bands from violet inside to red outside,
	-- each a few px wide, laid over the sky in dithered steps and fading out toward its feet
	if sky.rainbow then
		local rcx, rcy = W * 0.5, hy + H * 0.1
		local r0, bw = H * 0.58, math.max(2, H * 0.02)
		local RB = { 0xFF6A7A, 0xFFA24A, 0xFFE06A, 0x7EE07A, 0x6AB8FF, 0xB48CFF }
		for y = 0, math.floor(hy) do
			for x = 0, W - 1 do
				local d = math.sqrt((x + 0.5 - rcx) ^ 2 + (y + 0.5 - rcy) ^ 2)
				local i = math.floor((d - r0) / bw)
				if i >= 0 and i < #RB then
					local k = 0.62 * math.clamp((rcy - y) / (H * 0.3), 0, 1)
					local lvl = math.floor(k * 3 + bay(x, y))
					if lvl > 0 then
						set(x, y, mix(get(x, y), RB[#RB - i], lvl / 4))
					end
				end
			end
		end
	end
	-- the sun or the moon, up and to the left: one flat tone with anti-aliased edges (no darker band down its far side,
	-- and the sunset's sun no stripes across its foot: the request of 2026-11-14, "for these, remove the dark diagonal
	-- band. also, remove the line at the bottom of the sun for the common one")
	local bc = sky.bodyC
	local bx, by, br = W * 0.2, H * 0.24, H * sky.bodyR
	if sky.body == "bigsun" then
		bx, by = W * 0.5, hy - H * 0.06
	elseif sky.body == "sun" and r == 1 then
		bx, by = W * 0.24, hy - H * 0.14
	end
	-- (a soft halo round it first: two dithered rings)
	for y = math.max(0, math.floor(by - br * 2.2)), math.min(H - 1, math.ceil(by + br * 2.2)) do
		for x = math.max(0, math.floor(bx - br * 2.2)), math.min(W - 1, math.ceil(bx + br * 2.2)) do
			local d = math.sqrt((x + 0.5 - bx) ^ 2 + (y + 0.5 - by) ^ 2) / br
			if d > 1 and d < 2.2 then
				local k = (2.2 - d) / 1.2
				local lvl = math.floor(k * 2 + bay(x, y))
				if lvl > 0 then
					set(x, y, mix(get(x, y), bc[1], lvl * 0.18))
				end
			end
		end
	end
	-- (an eclipse: tongues of fire round the dark disc, longer here and shorter there, in dithered steps)
	if sky.body == "eclipse" then
		for y = math.max(0, math.floor(by - br * 2.2)), math.min(H - 1, math.ceil(by + br * 2.2)) do
			for x = math.max(0, math.floor(bx - br * 2.2)), math.min(W - 1, math.ceil(bx + br * 2.2)) do
				local dx, dy = x + 0.5 - bx, y + 0.5 - by
				local d = math.sqrt(dx * dx + dy * dy) / br
				if d > 1 and d < 2.1 then
					local a = math.atan2(dy, dx)
					local reach = 1.25 + 0.75 * (0.5 + 0.5 * math.sin(a * 5 + 0.7)) * (0.55 + 0.45 * math.sin(a * 3 - 1.1))
					if d < reach then
						local k = 1 - (d - 1) / (reach - 1)
						local lvl = math.floor(k * 3 + bay(x, y))
						if lvl > 0 then
							set(x, y, mix(get(x, y), bc[1], math.min(1, lvl * 0.26)))
						end
					end
				end
			end
		end
	end
	for y = math.max(0, math.floor(by - br - 1)), math.min(H - 1, math.ceil(by + br + 1)) do
		for x = math.max(0, math.floor(bx - br - 1)), math.min(W - 1, math.ceil(bx + br + 1)) do
			local dx, dy = x + 0.5 - bx, y + 0.5 - by
			local d = math.sqrt(dx * dx + dy * dy)
			local cover = math.clamp(br + 0.5 - d, 0, 1)
			if sky.body == "crescent" then
				-- (the dark of the moon: a second disc down and to the right takes a bite)
				local d2 = math.sqrt((dx - br * 0.45) ^ 2 + (dy + br * 0.1) ^ 2)
				cover = math.min(cover, math.clamp(d2 - br * 0.85 + 0.5, 0, 1))
			end
			if cover > 0 then
				local c = bc[1]
				if sky.body == "moon" or sky.body == "twomoons" then
					-- craters: three soft spots
					for _, cr in { { -0.3, -0.2, 0.22 }, { 0.25, 0.3, 0.17 }, { 0.35, -0.35, 0.12 } } do
						if (dx / br - cr[1]) ^ 2 + (dy / br - cr[2]) ^ 2 < cr[3] * cr[3] then
							c = bc[3]
						end
					end
				elseif sky.body == "bigsun" then
					local v = dy / br
					if v > -0.05 and (math.floor((v + 0.05) * 7) % 2 == 1) then
						c = bc[3]
					end
				elseif sky.body == "planet" then
					-- soft bands of cloud across it, wavy
					local v = dy / br + math.sin(dx / br * 3) * 0.06
					if math.floor((v + 1) * 3.5) % 2 == 1 then
						c = bc[3]
					end
				elseif sky.body == "eclipse" then
					-- the dark disc, a thin bright rim round it
					c = if d > br - 1.3 then bc[3] else bc[2]
				end
				set(x, y, if cover >= 0.75 then c elseif cover >= 0.25 then mix(get(x, y), c, 0.5) else get(x, y))
			end
		end
	end
	-- the ringed sun (the eternal dawn): a ring of light round it a little way out, four long rays crossing through it
	-- and four shorter ones on the slant, each one pixel wide, fading in dithered steps toward its tip
	if sky.body == "halosun" then
		local rr = br * 1.7
		for y = math.max(0, math.floor(by - rr - 2)), math.min(H - 1, math.ceil(by + rr + 2)) do
			for x = math.max(0, math.floor(bx - rr - 2)), math.min(W - 1, math.ceil(bx + rr + 2)) do
				local d = math.sqrt((x + 0.5 - bx) ^ 2 + (y + 0.5 - by) ^ 2)
				local cover = math.clamp(0.9 - math.abs(d - rr), 0, 1)
				if cover > 0 then
					set(x, y, mix(get(x, y), bc[2], if cover >= 0.6 then 0.85 else 0.45))
				end
			end
		end
		for _, ray in { { 1, 0, 3.8, bc[1] }, { -1, 0, 3.8, bc[1] }, { 0, 1, 3.2, bc[1] }, { 0, -1, 3.8, bc[1] }, { 1, 1, 2.2, bc[3] }, { -1, 1, 2.2, bc[3] }, { 1, -1, 2.2, bc[3] }, { -1, -1, 2.2, bc[3] } } do
			local len = math.floor(br * ray[3])
			for t = math.floor(br + 1), len do
				local x, y = math.floor(bx + ray[1] * t), math.floor(by + ray[2] * t)
				local k = 1 - (t - br) / (len - br + 1)
				local lvl = math.floor(k * 3 + bay(x, y))
				if lvl > 0 then
					set(x, y, mix(get(x, y), ray[4], lvl * 0.28))
				end
			end
		end
	end
	-- the second, smaller moon (mythic), up and to the right of the first, lit the same way
	if sky.body == "twomoons" then
		local mx, my, mr = W * 0.36, H * 0.11, br * 0.42
		for y = math.max(0, math.floor(my - mr - 1)), math.min(H - 1, math.ceil(my + mr + 1)) do
			for x = math.max(0, math.floor(mx - mr - 1)), math.min(W - 1, math.ceil(mx + mr + 1)) do
				local dx, dy = x + 0.5 - mx, y + 0.5 - my
				local cover = math.clamp(mr + 0.5 - math.sqrt(dx * dx + dy * dy), 0, 1)
				if cover > 0 then
					local c = bc[2]
					set(x, y, if cover >= 0.75 then c elseif cover >= 0.25 then mix(get(x, y), c, 0.5) else get(x, y))
				end
			end
		end
	end
	-- the planet's ring (celestial): a tilted ellipse round it, behind it above and in front of it below, a gap in it
	local ring = sky.ring
	if sky.body == "planet" and ring then
		local tilt = -0.32
		local ca, sa = math.cos(tilt), math.sin(tilt)
		local ra, rb = br * 2.05, br * 0.55
		for y = math.max(0, math.floor(by - ra)), math.min(H - 1, math.ceil(by + ra)) do
			for x = math.max(0, math.floor(bx - ra)), math.min(W - 1, math.ceil(bx + ra)) do
				local dx, dy = x + 0.5 - bx, y + 0.5 - by
				local u, v = dx * ca + dy * sa, -dx * sa + dy * ca
				local e = math.sqrt((u / ra) ^ 2 + (v / rb) ^ 2)
				local onBody = dx * dx + dy * dy <= br * br
				if e > 0.74 and e < 1 and (v > 0 or not onBody) and not (e > 0.86 and e < 0.89) then
					local c = if u > br * 0.6 then ring[2] else ring[1]
					local edge = math.min(e - 0.74, 1 - e) * ra
					set(x, y, if edge >= 0.6 then c else mix(get(x, y), c, 0.5))
				end
			end
		end
	end
	-- the gold night's sun: long beams fanning up out of it
	if sky.body == "bigsun" then
		for y = 0, math.floor(by) do
			for x = 0, W - 1 do
				local a = math.atan2(by - y, x + 0.5 - bx)
				local d = math.sqrt((x + 0.5 - bx) ^ 2 + (by - y) ^ 2)
				if d > br * 1.2 and math.sin(a * 14) > 0.55 then
					local k = math.clamp(1 - d / (H * 0.9), 0, 1)
					local lvl = math.floor(k * 2.4 + bay(x, y))
					if lvl > 0 then
						set(x, y, mix(get(x, y), bc[1], lvl * 0.14))
					end
				end
			end
		end
	end
	-- (no clouds since 2026-11-14: "Remove the clouds in the hatch screen background as well")
	-- the glow round the egg: rings of its light over the sky, dithered from one to the next
	local gr = H * sky.glowR
	for y = math.max(0, math.floor(ey - gr)), math.min(H - 1, math.ceil(ey + gr)) do
		for x = math.max(0, math.floor(ex - gr)), math.min(W - 1, math.ceil(ex + gr)) do
			local d = math.sqrt((x + 0.5 - ex) ^ 2 + (y + 0.5 - ey) ^ 2) / gr
			if d < 1 then
				local lvl = math.floor((1 - d) ^ 1.4 * 4 + bay(x, y))
				if lvl > 0 then
					set(x, y, mix(get(x, y), sky.glow, math.min(4, lvl) / 4 * sky.glowK))
				end
			end
		end
	end
	-- (no islets floating far off since 2026-11-14: "For the hatch screen, remove the trees in the background, and the
	-- floating islands as well")
	-- the corners a dithered step or two darker, framing the egg: the sky's only (the land darkens toward its corners
	-- in its own tones, below)
	for y = 0, H - 1 do
		local vy = (y + 0.5) / H - 0.5
		for x = 0, W - 1 do
			local vx = (x + 0.5) / W - 0.5
			local d = vx * vx * 1.6 + vy * vy * 2.2
			if d > 0.32 then
				local lvl = math.floor(math.clamp((d - 0.32) / 0.22, 0, 1) * 2 + bay(x, y))
				if lvl > 0 then
					px[y * W + x + 1] = mix(px[y * W + x + 1], 0x000000, 0.08 * lvl)
				end
			end
		end
	end
	-- the land: three ranges of hills, far to near (the request of 2026-11-19: "the landscape's grass across all
	-- rarities is too even. also, the landscape's anti aliasing dosent match the color much, and is banded").
	-- Each range has a ramp of five tones from its own colours, the darker ones leaning to the sky's deep hue and the
	-- lightest to the egg's glow. Its ridge has no rim line: where the ridge steps down a pixel, the end of the run
	-- below carries the run above on for one to four pixels, each mixed from the very colour behind it toward the
	-- hill's (a pixel artist's anti-aliasing: only at the steps, never a band along the edge). The slopes facing the
	-- light (up and to the left) carry a lit cap that thickens and thins with the slope, the far sides a darker one.
	-- Over that, the grass: patches a tone lighter or darker (soft noise, wider toward the front, lone pixels cleaned
	-- away), blades gathered in clumps that grow taller toward the front, tufts of three in the nearest grass (the left
	-- blade lit, the right in shade) with a few flowers in the rarity's colour, and the nearest grass a tone or two
	-- darker toward the bottom corners. Only what shows is worked out: a range stops where the next one covers it.
	local B = BASES[math.clamp(r, 1, #BASES)]
	local nHills = #sky.hills
	local deep, warm = stops[1], sky.glow
	local topsOf: { { number } } = {}
	for li = 1, nHills do
		local t = table.create(W, 0)
		for x = 0, W - 1 do
			t[x + 1] = math.floor(ridgeOf(li, x + 0.5) + 0.5)
		end
		topsOf[li] = t
	end
	for li, hl in sky.hills do
		local tops = topsOf[li]
		local nextTops: { number }? = topsOf[li + 1]
		local isNear = li == nHills
		local lowest = if li == 1 then 2 else 1
		local highest = if isNear then 5 else 4
		local fill, lit = hl[1], hl[2]
		local ramp = { mix(fill, deep, 0.42), mix(fill, deep, 0.2), fill, lit, mix(lit, warm, 0.25) }
		local minTop = H
		for x = 1, W do
			minTop = math.min(minTop, tops[x])
		end
		minTop = math.max(0, minTop)
		local rows = H - minTop
		if rows <= 0 then
			continue
		end
		local seed = r * 17 + li * 5
		local cacheA: { [number]: number }, cacheB: { [number]: number } = {}, {}
		local cacheC: { [number]: number }, cacheD: { [number]: number } = {}, {}
		-- how deep each column's lit cap and its shaded cap reach under its top
		local capW: { number } = table.create(W, 0)
		local darkW: { number } = table.create(W, 0)
		local capT = H * (0.018 + 0.007 * li)
		for x = 0, W - 1 do
			local slope = (ridgeOf(li, x + 1.5) - ridgeOf(li, x - 0.5)) / 2
			local wob = 0.7 + 0.6 * vnoise(x / 19, li * 3.1, seed + 7, cacheC)
			-- (whole pixels down from the column's top, and none thinner than two: a cap a pixel thick came and went
			-- from one column to the next along the ridge, a dashed line)
			local cw = math.floor(math.clamp(0.45 - slope * 5, 0, 1) * capT * wob + 0.5)
			local dw = math.floor(math.clamp(slope * 5 - 0.3, 0, 1) * capT * 0.8 * wob + 0.5)
			capW[x + 1] = if cw >= 2 then cw else 0
			darkW[x + 1] = if dw >= 2 then dw else 0
		end
		-- the tones (ramp index; 0 where this range doesn't show)
		local tone = buffer.create(W * rows)
		local sx, sy = 26, 7
		for y = minTop, H - 1 do
			local k = 0.6 + 1.1 * (y - minTop) / math.max(1, rows) -- how near the ground is here
			local v = (y - minTop) / (sy * k)
			local vy = (y + 0.5) / H - 0.5
			for x = 0, W - 1 do
				if y < tops[x + 1] or (nextTops and y >= nextTops[x + 1]) then
					continue
				end
				local dy = y - tops[x + 1]
				local b = 3
				if dy < capW[x + 1] then
					b = 4
				elseif dy < darkW[x + 1] then
					b = 2
				end
				local u = (x - W / 2) / (sx * k)
				local n = vnoise(u, v, seed, cacheA) * 0.75 + vnoise(u * 2, v * 2, seed + 1, cacheB) * 0.25
				if n < 0.33 then
					b -= 1
				elseif n > 0.68 then
					b += 1
				end
				if isNear then
					local vx = (x + 0.5) / W - 0.5
					local d = vx * vx * 1.6 + vy * vy * 2.2 + (n - 0.5) * 0.25
					if d > 0.9 then
						b -= 2
					elseif d > 0.64 then
						b -= 1
					end
				end
				buffer.writeu8(tone, (y - minTop) * W + x, math.clamp(b, lowest, highest))
			end
		end
		local function toneAt(x: number, y: number): number
			if x < 0 or x >= W or y < minTop or y >= H then
				return 0
			end
			return buffer.readu8(tone, (y - minTop) * W + x)
		end
		-- (lone pixels go: one unlike all of its neighbours, three or four of them alike, takes theirs; and so does a
		-- pixel between two alike above and below, so no patch thins to a one pixel streak)
		for y = minTop, H - 1 do
			for x = 0, W - 1 do
				local c = toneAt(x, y)
				local upT, dnT = toneAt(x, y - 1), toneAt(x, y + 1)
				if c > 0 and upT > 0 and upT == dnT and upT ~= c then
					buffer.writeu8(tone, (y - minTop) * W + x, upT)
				elseif c > 0 then
					local lT, rT = toneAt(x - 1, y), toneAt(x + 1, y)
					if lT ~= c and rT ~= c and upT ~= c and dnT ~= c then
						-- (all four unlike it: it takes the tone that three or four of them share)
						local other = if lT > 0 then lT else rT
						local seen, alike = 0, 0
						for k = 1, 4 do
							local nb = if k == 1 then lT elseif k == 2 then rT elseif k == 3 then upT else dnT
							if nb > 0 then
								seen += 1
								if nb == other then
									alike += 1
								end
							end
						end
						if other > 0 and seen >= 3 and alike == seen then
							buffer.writeu8(tone, (y - minTop) * W + x, other)
						end
					end
				end
			end
		end
		for y = minTop, H - 1 do
			local row = y * W
			for x = 0, W - 1 do
				local c = toneAt(x, y)
				if c > 0 then
					px[row + x + 1] = ramp[c]
				end
			end
		end
		-- the ridge's anti-aliasing: at each step down a pixel, the run above carries on over the end of the run below
		-- for n pixels (half the run, one to four), mixed from what lies behind toward the hill, a step at a time
		local function aa(x: number, y: number, c: number, a: number)
			if y >= 0 and y < H and x >= 0 and x < W and not (nextTops and y >= nextTops[x + 1]) then
				set(x, y, mix(get(x, y), c, a))
			end
		end
		local x0 = 0
		while x0 < W do
			local t = tops[x0 + 1]
			local x1 = x0
			while x1 + 1 < W and tops[x1 + 2] == t do
				x1 += 1
			end
			local n = math.clamp((x1 - x0 + 1) // 2, 1, 4)
			if x0 > 0 and tops[x0] == t - 1 then
				local c = ramp[math.max(1, toneAt(x0 - 1, t - 1))]
				for k = 0, n - 1 do
					aa(x0 + k, t - 1, c, (n - k) / (n + 1))
				end
			end
			if x1 < W - 1 and tops[x1 + 2] == t - 1 then
				local c = ramp[math.max(1, toneAt(x1 + 1, t - 1))]
				for k = 0, n - 1 do
					aa(x1 - k, t - 1, c, (n - k) / (n + 1))
				end
			end
			x0 = x1 + 1
		end
		-- blades of grass, gathered in clumps, taller toward the front; tufts and flowers in the nearest grass
		local function blade(x: number, y: number, h: number, lean: number, c: number)
			for j = 0, h - 1 do
				local bx = x + (if j == h - 1 and h >= 2 then lean else 0)
				if toneAt(bx, y - j) > 0 then
					set(bx, y - j, c)
				end
			end
		end
		local count = if isNear then math.floor(W * 1.2) elseif li == 1 then math.floor(W * 0.15) else math.floor(W * 0.3)
		for i = 1, count do
			local x = math.floor(hash(i * 31 + seed * 7) * W)
			local y = minTop + math.floor(hash(i * 57 + seed * 3) * rows)
			local b = toneAt(x, y)
			if b == 0 or vnoise(x / 9, y / 4, seed + 11, cacheD) < 0.45 then
				continue
			end
			local p = (y - minTop) / math.max(1, rows)
			if isNear then
				local h = 1 + math.floor(p * 3 + hash(i * 13 + 1) * 1.5)
				if p > 0.35 and hash(i * 19 + 2) < 0.55 then
					blade(x, y, h, 0, ramp[math.min(5, b + 1)])
					blade(x - 1, y, h - 1, -1, ramp[math.min(5, b + 2)])
					blade(x + 1, y, h - 1, 1, ramp[math.max(1, b - 1)])
					if hash(i * 23 + 5) < 0.18 then
						set(x, y - h, B.flower)
						if p > 0.7 and toneAt(x, y - h - 1) > 0 then
							set(x, y - h - 1, mix(B.flower, 0xFFFFFF, 0.45))
						end
					end
				else
					blade(x, y, h, if hash(i * 29 + 4) < 0.5 then -1 else 1, ramp[math.min(5, b + 1)])
				end
			else
				local h = 1 + math.floor(hash(i * 13 + 1) * 1.6)
				blade(x, y, h, 0, ramp[math.min(highest, b + 1)])
			end
		end
	end
	-- (the pedestal's own tufts, on its top's rim, in the nearest grass's tones)
	local nearHl = sky.hills[nHills]
	local bladeLit, bladeC = mix(nearHl[2], 0xFFFFFF, 0.12), mix(nearHl[1], nearHl[2], 0.5)
	-- the pedestal the egg lands on
	if ped then
		local cx, cy, bw = ped.x, ped.y, math.max(8, ped.w)
		local ry = bw * 0.42
		local sh = math.max(5, math.floor(bw * 0.34 + 0.5))
		local function inTop(x: number, y: number): boolean
			return ((x - cx) / bw) ^ 2 + ((y - cy) / ry) ^ 2 <= 1
		end
		-- (it stands on a column of the same stone rising from below the picture: fluted, lit on the left, a step
		-- darker toward the foot)
		local cw = bw * 0.58
		local function inColumn(x: number, y: number): boolean
			return math.abs(x - cx) <= cw and y >= cy + sh and y < H + 2
		end
		local function inBase(x: number, y: number): boolean
			local dx = (x - cx) / bw
			if math.abs(dx) > 1 then
				return false
			end
			local e = ry * math.sqrt(1 - dx * dx)
			return (y >= cy - e and y <= cy + e + sh) or inColumn(x, y)
		end
		local colLit, col, colDark = mix(B.sideLit, B.ink, 0.12), mix(B.side, B.ink, 0.18), mix(B.sideDark, B.ink, 0.25)
		local colDeep = mix(B.sideDark, B.ink, 0.42)
		local colTop = math.floor(cy + sh)
		-- (its first and last columns: no flute there, so the side's ink line stays one pixel wide)
		local cx0, cx1 = math.ceil(cx - cw - 0.5), math.floor(cx + cw - 0.5)
		-- the shaft's stone at (x, y), `shade` steps down its ramp (lit, plain, dark, deep): the cap's shadow is one or
		-- two steps
		local ramp = { colLit, col, colDark, colDeep }
		local function shaft(x: number, y: number, shade: number): number
			local dx = (x + 0.5 - cx) / cw
			local t = (if dx < -0.4 then 1 elseif dx > 0.35 then 3 else 2) + shade
			local c = ramp[math.min(4, t)]
			if t > 4 then
				c = mix(c, B.ink, 0.2)
			end
			if (x - math.floor(cx)) % 4 == 0 and x > cx0 and x < cx1 then
				c = mix(c, B.ink, 0.22) -- (its fluting)
			end
			local fade = math.clamp((y - colTop) / math.max(1, H - colTop), 0, 1)
			local lvl = math.floor(fade * 2 + bay(x, y) - 0.3)
			if lvl > 0 then
				c = mix(c, B.ink, 0.1 * lvl)
			end
			return c
		end
		for y = colTop, H - 1 do
			for x = cx0, cx1 do
				if inColumn(x + 0.5, y + 0.5) then
					set(x, y, shaft(x, y, 0))
				end
			end
		end
		-- the side: lit on the left, shaded on the right, a carved band round it, the stones' joints set over each other
		local x0c = math.floor(cx)
		for x = math.floor(cx - bw), math.ceil(cx + bw) do
			local dx = (x + 0.5 - cx) / bw
			if math.abs(dx) <= 1 then
				local yTop = cy + ry * math.sqrt(1 - dx * dx)
				for y = math.floor(yTop), math.ceil(yTop + sh) do
					if inBase(x + 0.5, y + 0.5) and not inTop(x + 0.5, y + 0.5) then
						local v = (y + 0.5 - yTop) / sh
						local c = if dx < -0.5 then B.sideLit elseif dx > 0.45 then B.sideDark else B.side
						if v > 0.68 and v < 0.84 then
							c = if dx > 0.45 then mix(B.trim, B.sideDark, 0.5) else mix(B.trim, c, 0.25)
						elseif v <= 0.68 and (x - x0c) % 9 == 0 then
							c = mix(c, B.ink, 0.3)
						elseif r >= 7 and hash2(x, y) > 0.95 then
							c = B.gem -- (stars in the starstone, sparks in the black stone, flecks in the pearl)
						end
						set(x, y, c)
					end
				end
			end
		end
		-- the top: its stone, a lit rim at the back left and a darker lip at the front right, an inlaid ring, the egg's
		-- shadow just down and to the right of the middle
		for y = math.floor(cy - ry) - 1, math.ceil(cy + ry) + 1 do
			for x = math.floor(cx - bw) - 1, math.ceil(cx + bw) + 1 do
				local dx, dy = (x + 0.5 - cx) / bw, (y + 0.5 - cy) / ry
				local d = math.sqrt(dx * dx + dy * dy)
				if d <= 1 then
					local c = B.top
					if d > 0.86 then
						if dx + dy * 0.6 < -0.25 then
							c = B.topLit
						elseif dx + dy * 0.6 > 0.45 then
							c = B.sideLit
						end
					elseif d > 0.64 and d < 0.64 + 1.6 / bw then
						c = B.trim
					end
					local sd = ((x + 0.5 - (cx + bw * 0.08)) / (bw * 0.44)) ^ 2 + ((y + 0.5 - (cy + ry * 0.1)) / (ry * 0.42)) ^ 2
					if sd < 1 then
						local lvl = math.floor((1 - sd) * 2 + bay(x, y))
						if lvl > 0 then
							c = mix(c, 0x000000, 0.12 * lvl)
						end
					end
					set(x, y, c)
				end
			end
		end
		-- gems on the inlaid ring, from rare up: at its left, right, front and back
		if r >= 3 then
			for k = 0, 3 do
				local a = k * math.pi / 2
				local gx, gy2 = math.floor(cx + math.cos(a) * bw * 0.66), math.floor(cy + math.sin(a) * ry * 0.66)
				set(gx, gy2, B.gem)
				set(gx + 1, gy2, mix(B.gem, B.trim, 0.5))
			end
		end
		-- the cap's shadow on the shaft under it (the user's report of 2026-11-15: "it dosent seem like the top part is
		-- casting a shadow on the bottom part of the pillar"): a band right under the cap's lip, its first row two steps
		-- down the shaft's ramp and the rest one step, lit from the top left so it is shallow at the left and deeper to
		-- the right (2 to 5 px), its depth stepping at the flutes
		for x = cx0, cx1 do
			local dx = (x + 0.5 - cx) / bw
			local lip = math.floor(cy + ry * math.sqrt(math.max(0, 1 - dx * dx)) + sh - 0.5)
			local fl = math.floor((x - cx0) / 4) * 4
			local depth = math.max(2, math.floor(sh * (0.22 + 0.23 * fl / math.max(1, cx1 - cx0)) + 0.5))
			for k = 1, depth do
				local y = lip + k
				if inColumn(x + 0.5, y + 0.5) then
					set(x, y, shaft(x, y, if k == 1 then 2 else 1))
				end
			end
		end
		-- the outline round the whole of it, the cap and the shaft down past the picture's foot (the user's report
		-- of 2026-11-15: "it seems like the outline gets broken in the pillars": the shaft had none below the cap): the
		-- pixels just outside it (4-neighbours, so convex corners come out cut). Where the line turns on a curve, the
		-- elbow (the line on two sides of it, the stone on the other two) is a step of anti-aliasing instead, the stone
		-- next to it a step toward the line, so the line runs on diagonally with no doubled pixels.
		local mask = buffer.create(W * H) -- 1 the top, 2 the side and the shaft, 3 the outline (kept: `pedMask`)
		local ex0, ex1 = math.max(0, math.floor(cx - bw) - 2), math.min(W - 1, math.ceil(cx + bw) + 2)
		local ey0 = math.max(0, math.floor(cy - ry) - 2)
		for y = ey0, H - 1 do
			for x = ex0, ex1 do
				if inBase(x + 0.5, y + 0.5) then
					buffer.writeu8(mask, y * W + x, if inTop(x + 0.5, y + 0.5) then 1 else 2)
				end
			end
		end
		local function m(x: number, y: number): number
			if x < 0 or y < 0 or x >= W or y >= H then
				return 0
			end
			return buffer.readu8(mask, y * W + x)
		end
		local edge: { number } = {}
		for y = ey0, H - 1 do
			for x = ex0, ex1 do
				if m(x, y) == 0 and (m(x + 1, y) == 1 or m(x + 1, y) == 2 or m(x - 1, y) == 1 or m(x - 1, y) == 2 or m(x, y + 1) == 1 or m(x, y + 1) == 2 or m(x, y - 1) == 1 or m(x, y - 1) == 2) then
					table.insert(edge, x)
					table.insert(edge, y)
				end
			end
		end
		for i = 1, #edge, 2 do
			buffer.writeu8(mask, edge[i + 1] * W + edge[i], 3)
		end
		local function stone(x: number, y: number): boolean
			local v = m(x, y)
			return v == 1 or v == 2
		end
		local elbows: { number } = {}
		for i = 1, #edge, 2 do
			local x, y = edge[i], edge[i + 1]
			for _, d in { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } } do
				-- (the line to one side and above or below; the stone on the other side and the other way)
				if m(x - d[1], y) == 3 and m(x, y - d[2]) == 3 and stone(x + d[1], y) and stone(x, y + d[2]) then
					table.insert(elbows, x)
					table.insert(elbows, y)
					table.insert(elbows, get(x + d[1], y))
					break
				end
			end
		end
		-- (selective outlining, the request of 2026-11-20: "For outlines everywhere, no longer use pure black, but a
		-- darker version of suitable neighbouring pixels instead": each pixel of the line a darker step of the stone
		-- beside it, the commonest of its 4-neighbours there and the darker on a tie, leaning to the base's ink by the
		-- step Render/Shading's inkOf takes; an elbow halfway between its stone and that line)
		local kr, kg, kb = rgb(B.ink)
		local function selInk(c: number): number
			local r, g, b = rgb(c)
			return math.floor(r * 0.45 + kr * 0.3 + 0.5) * 65536 + math.floor(g * 0.45 + kg * 0.3 + 0.5) * 256 + math.floor(b * 0.45 + kb * 0.3 + 0.5)
		end
		local function lum(c: number): number
			local r, g, b = rgb(c)
			return r * 0.3 + g * 0.59 + b * 0.11
		end
		local lineC: { number } = {}
		for i = 1, #edge, 2 do
			local x, y = edge[i], edge[i + 1]
			local beside: { number } = {}
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				if stone(x + d[1], y + d[2]) then
					table.insert(beside, get(x + d[1], y + d[2]))
				end
			end
			local best, bestN = beside[1], 0
			for _, c in beside do
				local n = 0
				for _, c2 in beside do
					if c2 == c then
						n += 1
					end
				end
				if n > bestN or (n == bestN and lum(c) < lum(best)) then
					best, bestN = c, n
				end
			end
			lineC[(i + 1) // 2] = if best then selInk(best) else B.ink
		end
		for i = 1, #edge, 2 do
			set(edge[i], edge[i + 1], lineC[(i + 1) // 2])
		end
		for i = 1, #elbows, 3 do
			set(elbows[i], elbows[i + 1], mix(elbows[i + 2], selInk(elbows[i + 2]), 0.5))
			buffer.writeu8(mask, elbows[i + 1] * W + elbows[i], 2)
		end
		pedMask = mask
		-- tufts of grass on the top's rim at the back, a little flower in each
		for k = 1, 2 do
			local a = if k == 1 then math.pi * 1.18 else math.pi * 1.72
			local fx = math.floor(cx + math.cos(a) * bw * 0.9)
			local fy = math.floor(cy + math.sin(a) * ry * 0.9)
			for j = 0, 1 do
				set(fx - 1, fy - j, bladeLit)
				set(fx + 1, fy - j, bladeC)
			end
			set(fx, fy - 2, bladeLit)
			set(fx, fy - 3, B.flower)
		end
	end
	-- packed
	local out = buffer.create(W * H * 4)
	local cache: { [number]: number } = {}
	for i = 1, W * H do
		local c = px[i]
		local p = cache[c]
		if p == nil then
			p = packed(c)
			cache[c] = p
		end
		buffer.writeu32(out, (i - 1) * 4, p)
	end
	return out
end

------------------------------------------------------------------ on screen
local gui: ScreenGui? = nil
local label: ImageLabel? = nil
local image: EditableImage? = nil

-- the sky's life: its own ScreenGui between the painted sky and the pixel layer, pixels as K x K frames
type Bird = { x: number, y: number, vx: number, ph: number, px: { Frame } }
type Streak = { x: number, y: number, age: number, px: { Frame } }
type Twinkle = { f: Frame, ph: number, rate: number }
local life: ScreenGui? = nil
local layer: Frame? = nil -- everything on the life layer, in one frame (`offset` moves it with the picture)
local lifeK = 1
local lifeW, lifeH = 0, 0
local lifeR = 1
local birds: { Bird } = {}
local streak: Streak? = nil
local streakAt = 0
local twinkles: { Twinkle } = {}
local lifeClock = 0
local INK: { number } = { 0x6E4E78, 0x4F7A6A, 0x1F2A4C, 0, 0, 0, 0, 0, 0 } -- the birds' colour by rarity (none on the nights)
local newLife: (r: number, W: number, H: number, K: number) -> ()

local ringBase: BaseAt? = nil
local makeRings: (r: number, K: number) -> ()
local makeLight: (W: number, H: number, K: number) -> ()
local backs: { Frame } = {} -- behind the picture, its top and bottom colours (shown at the edge while it jolts)

function HatchBackdrop.show(r: number, ex: number, ey: number, base: BaseAt?)
	local K = math.max(1, PixelRenderer.pixelScale())
	-- (the whole screen, a notched phone's margins too: Pixel/ScreenSize)
	local vp = ScreenSize.full()
	local W, H = math.ceil(vp.X / K), math.ceil(vp.Y / K)
	local im = image
	if im == nil or im.Size.X ~= W or im.Size.Y ~= H then
		if im then
			im:Destroy()
		end
		im = ImageMemory.create(W, H, "hatch")
		image = im
	end
	if im == nil then
		return
	end
	ringBase = base
	local buf = HatchBackdrop.paint(r, W, H, ex, ey, base)
	pcall(function()
		(im :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), buf)
	end)
	local g = gui
	if g == nil then
		local ng = Instance.new("ScreenGui")
		ng.Name = "HatchBackdrop"
		ng.IgnoreGuiInset = true
		ng.ScreenInsets = Enum.ScreenInsets.None
		ng.DisplayOrder = Tuning.PixelDisplayOrder - 2
		ng.ResetOnSpawn = false
		local l = Instance.new("ImageLabel")
		l.Name = "Image"
		l.BackgroundTransparency = 1
		l.BorderSizePixel = 0
		l.ResampleMode = Enum.ResamplerMode.Pixelated
		-- (sized in art px and scaled by K: Roblox keeps an Offset whole, so W * K units given as an offset lost its
		-- fraction when K was fitted to a screen scaled by 125%; the life layer below works the same way)
		local sc = Instance.new("UIScale")
		sc.Name = "PixelSize"
		sc.Parent = l
		l.Parent = ng
		ng.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui, label = ng, l
		g = ng
	end
	local l = label :: ImageLabel
	l.ImageContent = Content.fromObject(im)
	l.Size = UDim2.fromOffset(W, H)
	l.Position = UDim2.fromOffset(0, 0)
	local lsc = l:FindFirstChildOfClass("UIScale")
	if lsc then
		lsc.Scale = K
	end
	l.ZIndex = 2
	-- (behind it, the sky's top colour over its upper half and the nearest hills' under the lower, a step darker as the
	-- corners are: what shows along an edge while the picture jolts by a few px)
	local sky = SKIES[math.clamp(r, 1, #SKIES)]
	for i = 1, 2 do
		local old: Frame? = backs[i]
		local b: Frame
		if old and old.Parent ~= nil then
			b = old
		else
			b = Instance.new("Frame")
			b.Name = "Back"
			b.BorderSizePixel = 0
			b.ZIndex = 1
			b.Parent = g
			backs[i] = b
		end
		b.BackgroundColor3 = Color3.fromRGB(rgb(mix(if i == 1 then sky.stops[1] else sky.hills[#sky.hills][1], 0x000000, 0.16)))
		b.Size = UDim2.new(1, 0, 0.5, 0)
		b.Position = UDim2.fromScale(0, if i == 1 then 0 else 0.5)
	end
	if g then
		g.Enabled = true
	end
	newLife(r, W, H, K)
	makeRings(r, K)
	makeLight(W, H, K)
end

local function pixel(parent: Instance, c: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(rgb(c))
	f.Size = UDim2.fromOffset(1, 1)
	f.ZIndex = 5
	f.Parent = layer or parent
	return f
end

local function put(f: Frame, x: number, y: number)
	f.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

-- A bird's two wing beats (5 x 3 art px): wings up in a V, then level.
local WINGS: { { { number } } } = {
	{ { 0, 0 }, { 4, 0 }, { 1, 1 }, { 3, 1 }, { 2, 2 } },
	{ { 0, 1 }, { 1, 1 }, { 3, 1 }, { 4, 1 }, { 2, 2 } },
}

newLife = function(r: number, W: number, H: number, K: number)
	local old = life
	if old then
		old:Destroy()
	end
	table.clear(birds)
	table.clear(twinkles)
	streak = nil
	lifeK, lifeW, lifeH, lifeR = K, W, H, r
	local g = Instance.new("ScreenGui")
	g.Name = "HatchSky"
	g.IgnoreGuiInset = true
	g.ScreenInsets = Enum.ScreenInsets.None
	g.DisplayOrder = Tuning.PixelDisplayOrder - 1
	g.ResetOnSpawn = false
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	life = g
	local lay = Instance.new("Frame")
	lay.Name = "Layer"
	lay.BackgroundTransparency = 1
	lay.BorderSizePixel = 0
	lay.Size = UDim2.fromOffset(W, H)
	local lsc = Instance.new("UIScale")
	lsc.Scale = K
	lsc.Parent = lay
	lay.Parent = g
	layer = lay
	local sky = SKIES[math.clamp(r, 1, #SKIES)]
	-- twinkling stars: a few bright pixels that come and go (more of them, in their own colours, on the two rarest)
	if sky.stars > 0 then
		local tc = sky.twinkle or { 0xFFF4C8, 0xFFFFFF, 0xFFFFFF }
		for i = 1, if sky.twinkle then 10 + #tc * 6 else 14 do
			local f = pixel(g, tc[(i % #tc) + 1])
			put(f, hash(i * 41 + 3) * W, hash(i * 59 + 1) * H * 0.5)
			table.insert(twinkles, { f = f, ph = hash(i * 7) * 6.28, rate = 1.5 + hash(i * 13) * 2.5 })
		end
	end
end

------------------------------------------------------------------ the rings over the pedestal
local RING_EVERY = 0.85 -- seconds between two rings
local RING_LIFE = 1.7 -- seconds a ring takes to spread to the pedestal's rim
local ringImg: EditableImage? = nil
local ringBuf: buffer? = nil
local ringW, ringH = 0, 0
local ringCols: { number } = {}
local ringBorn: { number } = {}
local ringOn = false
local ringNext = 0
local ringDirty = false

makeRings = function(r: number, K: number)
	local base = ringBase
	local g = life
	if base == nil or g == nil then
		return
	end
	local B = BASES[math.clamp(r, 1, #BASES)]
	-- (bright, then a step toward the stone, then nearly the stone: a ring fades as it widens)
	ringCols = { packed(B.ring), packed(mix(B.ring, B.top, 0.45)), packed(mix(B.ring, B.top, 0.75)) }
	local bw = math.max(8, base.w)
	local w, h = math.ceil(bw * 2) + 4, math.ceil(bw * 0.84) + 4
	local im = ringImg
	if im == nil or im.Size.X ~= w or im.Size.Y ~= h then
		if im then
			im:Destroy()
		end
		im = ImageMemory.create(w, h, "hatch rings")
		ringImg = im
		ringBuf = buffer.create(w * h * 4)
	end
	if im == nil then
		return
	end
	ringW, ringH = w, h
	local l = Instance.new("ImageLabel")
	l.Name = "Rings"
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.ImageContent = Content.fromObject(im)
	l.Size = UDim2.fromOffset(w, h)
	l.Position = UDim2.fromOffset(math.floor(base.x) - math.floor(w / 2), math.floor(base.y) - math.floor(h / 2))
	l.ZIndex = 6
	l.Parent = layer or g
	ringDirty = true
end

-- One clean 1 px ellipse (the midpoint way: no doubled pixels, no gaps), centred in the ring image.
local function ellipse(buf: buffer, a: number, b: number, col: number)
	local cx, cy = math.floor(ringW / 2), math.floor(ringH / 2)
	local function plot(x: number, y: number)
		for _, p in { { cx + x, cy + y }, { cx - x, cy + y }, { cx + x, cy - y }, { cx - x, cy - y } } do
			if p[1] >= 0 and p[2] >= 0 and p[1] < ringW and p[2] < ringH then
				buffer.writeu32(buf, (p[2] * ringW + p[1]) * 4, col)
			end
		end
	end
	if a < 1 or b < 1 then
		return
	end
	local a2, b2 = a * a, b * b
	local x, y = 0, b
	local dx, dy = 0, 2 * a2 * y
	local d1 = b2 - a2 * b + 0.25 * a2
	while dx < dy do
		plot(x, y)
		x += 1
		dx += 2 * b2
		if d1 < 0 then
			d1 += dx + b2
		else
			y -= 1
			dy -= 2 * a2
			d1 += dx - dy + b2
		end
	end
	local d2 = b2 * (x + 0.5) ^ 2 + a2 * (y - 1) ^ 2 - a2 * b2
	while y >= 0 do
		plot(x, y)
		y -= 1
		dy -= 2 * a2
		if d2 > 0 then
			d2 += a2 - dy
		else
			x += 1
			dx += 2 * b2
			d2 += dx - dy + a2
		end
	end
end

-- The rings now: each spreads from the egg's width to the pedestal's rim (easing out), bright, then fainter, then gone.
local function drawRings()
	local im, buf, base = ringImg, ringBuf, ringBase
	if im == nil or buf == nil or base == nil then
		return
	end
	buffer.fill(buf, 0, 0)
	local bw = math.max(8, base.w)
	local r0, r1 = bw * 0.5, bw * 0.97
	local keep: { number } = {}
	for _, born in ringBorn do
		local u = (lifeClock - born) / RING_LIFE
		if u < 1 then
			table.insert(keep, born)
			local rad = r0 + (r1 - r0) * (1 - (1 - u) * (1 - u))
			local col = if u < 0.35 then ringCols[1] elseif u < 0.7 then ringCols[2] else ringCols[3]
			ellipse(buf, math.floor(rad + 0.5), math.floor(rad * 0.42 + 0.5), col)
		end
	end
	ringBorn = keep
	pcall(function()
		im:WritePixelsBuffer(Vector2.zero, Vector2.new(ringW, ringH), buf)
	end)
end

function HatchBackdrop.land()
	ringOn = true
	table.insert(ringBorn, lifeClock)
	ringNext = lifeClock + RING_EVERY
	ringDirty = true
end

-- One more ring over the pedestal now, between the steady ones (a crack, a landing, the hatch).
function HatchBackdrop.pulse()
	if #ringBorn < 8 then
		table.insert(ringBorn, lifeClock)
		ringDirty = true
	end
end

function HatchBackdrop.rings(): number
	return #ringBorn
end

------------------------------------------------------------------ the light behind the egg (UI/HatchScene)
-- Three images of their own on the life layer, over the hush and under the twinkles and the rings, so the egg (the
-- pixel layer) and the pedestal's rings stand in front of them; all whole art pixels of solid colour, blended over the
-- painted sky in dithered steps the way the gold night's sun throws its beams. Each is drawn again only where and when
-- it changes, as cheaply as it can be, since this runs on every client:
--   the god rays (`Light.levels`, `lens`, `cols`): a fan of soft beams laid out round the egg's middle (`layFan`), the
--     long ones and the short ones taking turns, each a thin wedge kept off the pedestal. The pixels a beam covers are
--     listed once, nearest first, with how strong it is there (fading out along it, softer toward its edges) and their
--     dither threshold, so a beam growing out or drawing in touches only the pixels between its old reach and its new
--     one, and is drawn whole again only when its brightness or its colour changes a step. No beam ever turns (that is
--     what would cost): they pulse, grow out, fade and change colour.
--   the halo (`halo`, `haloK`): dithered rings of the egg's light round its middle, drawn again when its radius moves
--     a few px or its strength a step.
--   the glow: its shadow on the pedestal's top while it falls, clean 1 px rings (a shockwave, a ring of dust: each
--     with a fainter ring just inside it, its anti-aliasing) and motes passing behind the egg; drawn again (at most 30
--     times a second) in the box it covers. The halo and the glow keep off the pedestal's outline.
--   the hush: the sky darkened toward the night colour under the light (a sheet over the painted sky).
export type Ring = { x: number, y: number, r: number, flat: number, k: number, col: number }
export type Light = {
	x: number, -- the egg's middle at rest on the screen (art px): the fan's and the halo's centre
	y: number,
	rays: number, -- beams in the fan (0: none)
	reach: number, -- the long ones' length (art px)
	levels: { number }, -- each beam: how bright (0 .. 1), how far out it reaches now (0 .. 1), its colour (0xRRGGBB)
	lens: { number },
	cols: { number },
	halo: number, -- the glow round the egg: radius (art px), strength (0 .. 1), colour
	haloK: number,
	haloCol: number,
	shadow: { number }?, -- its shadow on the pedestal: x, y, half width, strength
	rings: { Ring },
	motes: { number }, -- x, y, colour, ... (behind the egg)
	hush: number, -- 0 .. 1
}
-- a beam: its pixels nearest first (u32 index; u32 strength, how far along, dither threshold, a byte each), `cut[q]`
-- how many of them lie within q twentieths of its length, its box, and what it was last drawn with
type Beam = { pix: buffer, info: buffer, count: number, cut: { number }, box: { number }, lv: number, rc: number, col: number }
type Fan = { x: number, y: number, n: number, reach: number, beams: { Beam } }

local HUSH = 0x2E2A52 -- (Palette's night)
local HUSH_MAX = 0.55 -- how dark the sky goes at hush 1
local HALO_STEP = 3 -- px the halo's radius moves before it is drawn again
local lightW, lightH = 0, 0
local raysImg: EditableImage? = nil
local raysBuf: buffer? = nil
local haloImg: EditableImage? = nil
local haloBuf: buffer? = nil
local glowImg: EditableImage? = nil
local glowBuf: buffer? = nil
local hushFrame: Frame? = nil
local fan: Fan? = nil
local lightNow: Light? = nil
local glowBox = { 0, 0, -1, -1 } -- what the glow covered when last drawn
local haloBox = { 0, 0, -1, -1 }
local haloKey = ""
local glowAt = -1
local raysBlank = true
-- (1 - d) ^ 1.5 by d squared, in 256 steps: the halo's fall-off without a root or a power a pixel
local FALL_OFF: { number } = {}
for i = 0, 256 do
	FALL_OFF[i + 1] = (1 - math.sqrt(math.min(1, i / 256))) ^ 1.5
end

local function newImageLabel(name: string, im: EditableImage, z: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.ImageContent = Content.fromObject(im)
	l.Size = UDim2.fromOffset(lightW, lightH)
	l.ZIndex = z
	l.Parent = layer
	return l
end

-- Up a region of a W x H RGBA buffer into its image (the rows copied out: an image takes a buffer of the region's
-- own size).
local function upload(im: EditableImage, buf: buffer, x0: number, y0: number, x1: number, y1: number)
	local ax, ay = math.max(0, x0), math.max(0, y0)
	local bx, by = math.min(lightW - 1, x1), math.min(lightH - 1, y1)
	if bx < ax or by < ay then
		return
	end
	local w, h = bx - ax + 1, by - ay + 1
	local out = buffer.create(w * h * 4)
	for y = 0, h - 1 do
		buffer.copy(out, y * w * 4, buf, ((ay + y) * lightW + ax) * 4, w * 4)
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.new(ax, ay), Vector2.new(w, h), out)
	end)
end

-- Clear a box of a buffer (rows of zeros).
local function clearBox(buf: buffer, b: { number })
	for y = math.max(0, b[2]), math.min(lightH - 1, b[4]) do
		local x0 = math.max(0, b[1])
		local w = math.min(lightW - 1, b[3]) - x0 + 1
		if w > 0 then
			buffer.fill(buf, (y * lightW + x0) * 4, 0, w * 4)
		end
	end
end

makeLight = function(W: number, H: number, K: number)
	if layer == nil then
		return
	end
	if raysImg == nil or lightW ~= W or lightH ~= H then
		for _, im in { raysImg, haloImg, glowImg } do
			if im then
				im:Destroy()
			end
		end
		raysImg, haloImg, glowImg = ImageMemory.create(W, H, "hatch light"), ImageMemory.create(W, H, "hatch light"), ImageMemory.create(W, H, "hatch light")
		raysBuf, haloBuf, glowBuf = buffer.create(W * H * 4), buffer.create(W * H * 4), buffer.create(W * H * 4)
	end
	lightW, lightH = W, H
	local ri, hi, gi, rb, hb, gb = raysImg, haloImg, glowImg, raysBuf, haloBuf, glowBuf
	if ri == nil or hi == nil or gi == nil or rb == nil or hb == nil or gb == nil then
		return
	end
	-- (a new picture: the light starts again from nothing over it)
	local imgs: { EditableImage } = { ri, hi, gi }
	for i, buf in { rb, hb, gb } do
		buffer.fill(buf, 0, 0)
		upload(imgs[i], buf, 0, 0, W - 1, H - 1)
	end
	fan, glowBox, haloBox, haloKey, glowAt, raysBlank = nil, { 0, 0, -1, -1 }, { 0, 0, -1, -1 }, "", -1, true
	local hf = Instance.new("Frame")
	hf.Name = "Hush"
	hf.BorderSizePixel = 0
	hf.BackgroundColor3 = Color3.fromRGB(rgb(HUSH))
	hf.BackgroundTransparency = 1
	hf.Size = UDim2.fromScale(1, 1)
	hf.ZIndex = 1
	hf.Parent = layer
	hushFrame = hf
	newImageLabel("Rays", ri, 2)
	newImageLabel("Halo", hi, 3)
	newImageLabel("Glow", gi, 4)
	local _ = K
end

local function freeLight()
	for _, im in { raysImg, haloImg, glowImg } do
		if im then
			im:Destroy()
		end
	end
	raysImg, haloImg, glowImg, raysBuf, haloBuf, glowBuf, hushFrame, fan, lightNow = nil, nil, nil, nil, nil, nil, nil, nil, nil
	lightW, lightH = 0, 0
end

-- The fan's beams round (cx, cy): n of them, the long ones `reach` px, every other one shorter, each the pixels of a
-- thin wedge (row by row between its edges) off the pedestal and inside the picture, nearest first.
local function layFan(cx: number, cy: number, n: number, reach: number): Fan
	local W, H = lightW, lightH
	local mask = pedMask
	local spread = math.pi / n * 0.42 -- (each beam's half angle: the beams take 42% of the way round)
	local ts = math.tan(spread)
	local f: Fan = { x = cx, y = cy, n = n, reach = reach, beams = {} }
	for i = 1, n do
		local a = -math.pi / 2 + (i - 1) * math.pi * 2 / n
		local len = reach * (if i % 2 == 1 then 1 else 0.64)
		local ca, sa = math.cos(a), math.sin(a)
		local far = len / math.cos(spread)
		local tri = { cx, cy, cx + far * math.cos(a - spread), cy + far * math.sin(a - spread), cx + far * math.cos(a + spread), cy + far * math.sin(a + spread) }
		local y0 = math.max(0, math.floor(math.min(tri[2], tri[4], tri[6])))
		local y1 = math.min(H - 1, math.ceil(math.max(tri[2], tri[4], tri[6])))
		local idx: { number } = {}
		local inf: { number } = {}
		local qs: { number } = {}
		local bx0, by0, bx1, by1 = W, H, -1, -1
		for y = y0, y1 do
			local yc = y + 0.5
			local lo, hi = math.huge, -math.huge
			for e = 0, 2 do
				local ax, ay = tri[e * 2 + 1], tri[e * 2 + 2]
				local o = (e + 1) % 3
				local qx, qy = tri[o * 2 + 1], tri[o * 2 + 2]
				if (yc - ay) * (yc - qy) <= 0 and ay ~= qy then
					local x = ax + (yc - ay) * (qx - ax) / (qy - ay)
					lo, hi = math.min(lo, x), math.max(hi, x)
				end
			end
			if hi >= lo then
				for x = math.max(0, math.floor(lo)), math.min(W - 1, math.floor(hi)) do
					local dx, dy = x + 0.5 - cx, yc - cy
					local along = dx * ca + dy * sa
					if along > 4 and along < len and (mask == nil or buffer.readu8(mask, y * W + x) == 0) then
						local perp = math.abs(-dx * sa + dy * ca)
						local soft = math.min(1, (1 - perp / (along * ts)) * 2.2)
						local k = (1 - along / len) ^ 1.25 * soft
						if k > 0.01 then
							local q = math.floor(along / len * 255)
							table.insert(idx, y * W + x)
							table.insert(inf, math.floor(k * 255) + q * 256 + math.floor(bay(x, y) * 255) * 65536)
							table.insert(qs, q)
							bx0, by0, bx1, by1 = math.min(bx0, x), math.min(by0, y), math.max(bx1, x), math.max(by1, y)
						end
					end
				end
			end
		end
		-- nearest first (a count of each distance, then each pixel into its place: no sort)
		local cnt = #idx
		local at = table.create(257, 0)
		for _, q in qs do
			at[q + 2] += 1
		end
		for q = 2, 257 do
			at[q] += at[q - 1]
		end
		local pb, ib = buffer.create(cnt * 4), buffer.create(cnt * 4)
		for j = 1, cnt do
			local q = qs[j] + 1
			local o = at[q]
			at[q] = o + 1
			buffer.writeu32(pb, o * 4, idx[j])
			buffer.writeu32(ib, o * 4, inf[j])
		end
		-- (cut[s + 1]: the pixels within s twentieths of the beam's length)
		local cut: { number } = table.create(21, 0)
		local count = table.create(256, 0)
		for _, q in qs do
			count[q + 1] += 1
		end
		local run, q = 0, 0
		for st = 0, 20 do
			while q <= 255 and q <= st / 20 * 255 do
				run += count[q + 1]
				q += 1
			end
			cut[st + 1] = run
		end
		f.beams[i] = { pix = pb, info = ib, count = cnt, cut = cut, box = { bx0, by0, bx1, by1 }, lv = 0, rc = 0, col = -1 }
	end
	return f
end

-- Pixels j0 .. j1 - 1 of a beam drawn at brightness lvl in colour col (lvl 0: cleared).
local function beamPixels(b: Beam, j0: number, j1: number, lvl: number, col: number)
	local buf, sky = raysBuf, skyPx
	if buf == nil or sky == nil then
		return
	end
	local pb, ib = b.pix, b.info
	local cr, cg, cb = rgb(col)
	for j = j0, j1 - 1 do
		local p = buffer.readu32(pb, j * 4)
		local out = 0
		if lvl > 0 then
			local v = buffer.readu32(ib, j * 4)
			local step = math.min(4, math.floor(lvl * (v % 256) / 255 * 4 + bit32.rshift(v, 16) / 255))
			if step > 0 then
				local bg = sky[p + 1]
				local a = step * 0.15
				local r0, g0, b0 = bit32.rshift(bg, 16), bit32.band(bit32.rshift(bg, 8), 255), bit32.band(bg, 255)
				out = math.floor(r0 + (cr - r0) * a + 0.5) + math.floor(g0 + (cg - g0) * a + 0.5) * 256 + math.floor(b0 + (cb - b0) * a + 0.5) * 65536 + 4278190080
			end
		end
		buffer.writeu32(buf, p * 4, out)
	end
end

local function drawRays(l: Light?)
	local im, buf = raysImg, raysBuf
	if im == nil or buf == nil then
		return
	end
	local n = if l then l.rays else 0
	if n <= 0 or l == nil then
		if not raysBlank then
			buffer.fill(buf, 0, 0)
			upload(im, buf, 0, 0, lightW - 1, lightH - 1)
			raysBlank, fan = true, nil
		end
		return
	end
	local x, y, reach = math.floor(l.x), math.floor(l.y), math.floor(l.reach)
	local old = fan
	local f: Fan
	if old and old.n == n and old.x == x and old.y == y and old.reach == reach then
		f = old
	else
		buffer.fill(buf, 0, 0)
		f = layFan(x, y, n, reach)
		fan = f
		upload(im, buf, 0, 0, lightW - 1, lightH - 1)
	end
	local x0, y0, x1, y1 = lightW, lightH, -1, -1
	for i, b in f.beams do
		-- (in steps: an eighth of its brightness, a twentieth of its length)
		local lv = math.floor(math.clamp(l.levels[i] or 0, 0, 1) * 8 + 0.5)
		local rc = if lv == 0 then 0 else math.floor(math.clamp(l.lens[i] or 0, 0, 1) * 20 + 0.5)
		local col = l.cols[i] or 0xFFFFFF
		if lv ~= b.lv or col ~= b.col then
			-- (brighter, dimmer or another colour: the whole beam again, out to its reach, the rest cleared)
			beamPixels(b, 0, b.cut[rc + 1], lv / 8, col)
			beamPixels(b, b.cut[rc + 1], b.cut[math.max(rc, b.rc) + 1], 0, col)
		elseif rc > b.rc then
			beamPixels(b, b.cut[b.rc + 1], b.cut[rc + 1], lv / 8, col)
		elseif rc < b.rc then
			beamPixels(b, b.cut[rc + 1], b.cut[b.rc + 1], 0, col)
		else
			continue
		end
		b.lv, b.rc, b.col = lv, rc, col
		local bx = b.box
		x0, y0, x1, y1 = math.min(x0, bx[1]), math.min(y0, bx[2]), math.max(x1, bx[3]), math.max(y1, bx[4])
	end
	if x1 >= x0 then
		raysBlank = false
		upload(im, buf, x0, y0, x1, y1)
	end
end

-- The halo, when its radius has moved HALO_STEP px or its strength an eighth (dithered rings of its colour over the
-- sky and the pedestal's top).
local function drawHalo(l: Light?)
	local im, buf, sky = haloImg, haloBuf, skyPx
	if im == nil or buf == nil or sky == nil then
		return
	end
	local hr = if l then math.floor(l.halo / HALO_STEP + 0.5) * HALO_STEP else 0
	local hk = if l then math.floor(math.clamp(l.haloK, 0, 1) * 8 + 0.5) else 0
	if hr < 2 or hk == 0 or l == nil then
		hr, hk = 0, 0
	end
	local hx, hy = if l then math.floor(l.x) else 0, if l then math.floor(l.y) else 0
	local key = string.format("%d %d %d %d %d", hr, hk, hx, hy, if l then l.haloCol else 0)
	if key == haloKey then
		return
	end
	haloKey = key
	local ob = haloBox
	clearBox(buf, ob)
	local nb = { 0, 0, -1, -1 }
	if hr > 0 and l then
		local W, H = lightW, lightH
		local mask = pedMask
		local cr, cg, cb = rgb(l.haloCol)
		local k3 = hk / 8 * 3
		local r2 = hr * hr
		nb = { math.max(0, hx - hr), math.max(0, hy - hr), math.min(W - 1, hx + hr), math.min(H - 1, hy + hr) }
		for y = nb[2], nb[4] do
			local dy = y + 0.5 - hy
			for x = nb[1], nb[3] do
				local dx = x + 0.5 - hx
				local d2 = (dx * dx + dy * dy) / r2
				if d2 < 1 then
					local i = y * W + x
					if mask == nil or buffer.readu8(mask, i) <= 1 then
						local step = math.min(3, math.floor(k3 * FALL_OFF[math.floor(d2 * 256) + 1] + bay(x, y)))
						if step > 0 then
							local bg = sky[i + 1]
							local a = step * 0.13
							local r0, g0, b0 = bit32.rshift(bg, 16), bit32.band(bit32.rshift(bg, 8), 255), bit32.band(bg, 255)
							buffer.writeu32(buf, i * 4, math.floor(r0 + (cr - r0) * a + 0.5) + math.floor(g0 + (cg - g0) * a + 0.5) * 256 + math.floor(b0 + (cb - b0) * a + 0.5) * 65536 + 4278190080)
						end
					end
				end
			end
		end
	end
	haloBox = nb
	upload(im, buf, math.min(ob[1], nb[1]), math.min(ob[2], nb[2]), math.max(ob[3], nb[3]), math.max(ob[4], nb[4]))
end

local function drawGlow(l: Light?)
	local im, buf, sky = glowImg, glowBuf, skyPx
	if im == nil or buf == nil or sky == nil then
		return
	end
	local W, H = lightW, lightH
	local mask = pedMask
	local hush = if l then math.clamp(l.hush, 0, 1) * HUSH_MAX else 0
	local ob = glowBox
	clearBox(buf, ob)
	local nb = { W, H, -1, -1 }
	-- a pixel blended toward colour c by a (over the sky as the hush leaves it); `keep` the pedestal's parts it may cover
	local function blend(x: number, y: number, c: number, a: number, keep: number)
		if x < 0 or y < 0 or x >= W or y >= H then
			return
		end
		local i = y * W + x
		if mask then
			local m = buffer.readu8(mask, i)
			if m > keep then
				return
			end
		end
		local bg = sky[i + 1]
		if hush > 0 then
			bg = mix(bg, HUSH, hush)
		end
		buffer.writeu32(buf, i * 4, packed(mix(bg, c, a)))
		nb[1], nb[2], nb[3], nb[4] = math.min(nb[1], x), math.min(nb[2], y), math.max(nb[3], x), math.max(nb[4], y)
	end
	if l then
		-- its shadow on the pedestal's top, growing as it comes down
		local sh = l.shadow
		if sh and sh[3] >= 1 and sh[4] > 0 then
			local sx, sy, sw = sh[1], sh[2], sh[3]
			local sv = sw * 0.42
			for y = math.floor(sy - sv), math.ceil(sy + sv) do
				for x = math.floor(sx - sw), math.ceil(sx + sw) do
					local d = ((x + 0.5 - sx) / sw) ^ 2 + ((y + 0.5 - sy) / sv) ^ 2
					if d < 1 and x >= 0 and y >= 0 and x < W and y < H and (mask == nil or buffer.readu8(mask, y * W + x) == 1) then
						local step = math.min(2, math.floor(sh[4] * (1 - d) * 2 + bay(x, y)))
						if step > 0 then
							blend(x, y, 0x2B1E2E, step * 0.16, 1)
						end
					end
				end
			end
		end
		-- the rings: a clean 1 px ellipse (the midpoint way) and a fainter one a pixel inside it
		for _, rg in l.rings do
			for pass = 0, 1 do
				local a = math.floor(rg.r + 0.5) - pass
				local b = math.floor(rg.r * rg.flat + 0.5) - pass
				local k = math.floor(rg.k * (if pass == 0 then 1 else 0.5) * 5 + 0.5) / 5
				if a >= 1 and b >= 1 and k > 0 then
					local cx, cy = math.floor(rg.x), math.floor(rg.y)
					local function plot(px: number, py: number)
						blend(cx + px, cy + py, rg.col, k, 2)
						blend(cx - px, cy + py, rg.col, k, 2)
						if py ~= 0 then
							blend(cx + px, cy - py, rg.col, k, 2)
							blend(cx - px, cy - py, rg.col, k, 2)
						end
					end
					local a2, b2 = a * a, b * b
					local x, y = 0, b
					local dx, dy = 0, 2 * a2 * y
					local d1 = b2 - a2 * b + 0.25 * a2
					while dx < dy do
						plot(x, y)
						x += 1
						dx += 2 * b2
						if d1 < 0 then
							d1 += dx + b2
						else
							y -= 1
							dy -= 2 * a2
							d1 += dx - dy + b2
						end
					end
					local d2 = b2 * (x + 0.5) ^ 2 + a2 * (y - 1) ^ 2 - a2 * b2
					while y >= 0 do
						plot(x, y)
						y -= 1
						dy -= 2 * a2
						if d2 > 0 then
							d2 += a2 - dy
						else
							x += 1
							dx += 2 * b2
							d2 += dx - dy + a2
						end
					end
				end
			end
		end
		-- motes behind the egg: single pixels of their colour
		local mo = l.motes
		for i = 1, #mo - 2, 3 do
			blend(math.floor(mo[i]), math.floor(mo[i + 1]), mo[i + 2], 0.9, 1)
		end
	end
	glowBox = nb
	upload(im, buf, math.min(ob[1], nb[1]), math.min(ob[2], nb[2]), math.max(ob[3], nb[3]), math.max(ob[4], nb[4]))
end

-- The light behind the egg now (nil: none); drawn on the next step.
function HatchBackdrop.light(l: Light?)
	lightNow = l
end

local function drawLight()
	if raysImg == nil then
		return
	end
	local l = lightNow
	local hf = hushFrame
	if hf then
		hf.BackgroundTransparency = 1 - (if l then math.clamp(l.hush, 0, 1) * HUSH_MAX else 0)
	end
	drawRays(l)
	drawHalo(l)
	-- (the glow at most 30 times a second, and once more to clear it when it has gone)
	local busy = l ~= nil and (l.shadow ~= nil or #l.rings > 0 or #l.motes > 0)
	if (busy or glowBox[3] >= glowBox[1]) and lifeClock - glowAt >= 1 / 30 then
		glowAt = lifeClock
		drawGlow(if busy then l else nil)
	end
end

-- The picture and its light moved by whole art px (a jolt), 0, 0 puts them back.
function HatchBackdrop.offset(dx: number, dy: number)
	local K = lifeK
	local pos = UDim2.fromOffset(math.floor(dx + 0.5) * K, math.floor(dy + 0.5) * K)
	local l = label
	if l then
		l.Position = pos
	end
	local lay = layer
	if lay then
		lay.Position = pos
	end
end

-- Sims and previews: the beams lit now, whether the halo and the glow show, the hush.
function HatchBackdrop.debugLight(): { beams: number, halo: boolean, glow: boolean, hush: number }
	local n = 0
	local f = fan
	if f then
		for _, b in f.beams do
			if b.lv > 0 and b.rc > 0 then
				n += 1
			end
		end
	end
	local l = lightNow
	return { beams = n, halo = haloBox[3] >= haloBox[1], glow = glowBox[3] >= glowBox[1], hush = if l then l.hush else 0 }
end

local function newBird(x: number, y: number, vx: number, ph: number): Bird
	local g = life :: ScreenGui
	local px: { Frame } = {}
	for _ = 1, 5 do
		table.insert(px, pixel(g, INK[lifeR]))
	end
	return { x = x, y = y, vx = vx, ph = ph, px = px }
end

function HatchBackdrop.step(dt: number)
	local g = life
	if g == nil then
		return
	end
	lifeClock += dt
	local W, H = lifeW, lifeH
	-- birds: a little flock now and then, flapping across the upper sky (day and twilight)
	if INK[lifeR] ~= 0 and #birds == 0 and math.random() < dt * 0.6 then
		local fromLeft = math.random() < 0.5
		local y0 = H * (0.12 + math.random() * 0.25)
		local n = math.random(2, 5)
		for k = 1, n do
			local dx = (k - 1) * 7 + math.random(0, 3)
			local dy = (if k % 2 == 0 then 1 else -1) * math.floor(k / 2) * 3
			table.insert(birds, newBird(if fromLeft then -6 - dx else W + dx, y0 + dy, (if fromLeft then 1 else -1) * (14 + math.random() * 4), math.random() * 6.28))
		end
	end
	local keep: { Bird } = {}
	for _, b in birds do
		b.x += b.vx * dt
		b.y += math.sin(lifeClock * 1.3 + b.ph) * dt * 2
		if b.x < -12 or b.x > W + 12 then
			for _, f in b.px do
				f:Destroy()
			end
			continue
		end
		local beat = WINGS[(math.floor(lifeClock * 6 + b.ph) % 2) + 1]
		for i, d in beat do
			put(b.px[i], b.x + d[1], b.y + d[2])
		end
		table.insert(keep, b)
	end
	birds = keep
	-- a shooting star now and then on the night skies: a bright head and a tail fading in steps
	if lifeR >= 3 then
		local st = streak
		if st == nil and lifeClock >= streakAt then
			local tail = { 0xFFFFFF, 0xE6E4FF, 0xB9B6E8, 0x8C88C6, 0x6A649E }
			local px: { Frame } = {}
			for _, c in tail do
				table.insert(px, pixel(g, c))
			end
			streak = { x = W * (0.3 + math.random() * 0.6), y = H * (0.04 + math.random() * 0.15), age = 0, px = px }
			streakAt = lifeClock + 2.5 + math.random() * 4
		elseif st then
			st.age += dt
			local hx, hy = st.x - st.age * 90, st.y + st.age * 45
			for i, f in st.px do
				put(f, hx + (i - 1) * 2, hy - (i - 1))
				f.Visible = st.age < 0.7
			end
			if st.age >= 0.7 then
				for _, f in st.px do
					f:Destroy()
				end
				streak = nil
			end
		end
	end
	for _, tw in twinkles do
		tw.f.Visible = math.sin(lifeClock * tw.rate + tw.ph) > -0.2
	end
	-- the rings over the pedestal, once the egg is down
	if ringOn and lifeClock >= ringNext then
		table.insert(ringBorn, lifeClock)
		ringNext = lifeClock + RING_EVERY
	end
	if #ringBorn > 0 or ringDirty then
		ringDirty = #ringBorn > 0
		drawRings()
	end
	drawLight()
end

function HatchBackdrop.hide()
	local g = gui
	if g then
		g:Destroy()
	end
	local lg = life
	if lg then
		lg:Destroy()
	end
	life = nil
	table.clear(birds)
	table.clear(twinkles)
	streak = nil
	ringOn, ringNext, ringDirty = false, 0, false
	table.clear(ringBorn)
	local ri = ringImg
	if ri then
		ri:Destroy()
	end
	ringImg, ringBuf, ringBase = nil, nil, nil
	freeLight()
	for _, b in backs do
		b:Destroy()
	end
	table.clear(backs)
	layer = nil
	local im = image
	if im then
		im:Destroy()
	end
	gui, label, image = nil, nil, nil
end

return HatchBackdrop
