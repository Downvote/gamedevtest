--!strict
--!native
-- The hatch scene's painted backdrop (UI/HatchScene; GAME_DESIGN 6.2): the request of 2026-11-13, "the egg hatching
-- scene isnt detailed enough. add much much more detail to it, especially the egg. you are allowed to use 2d elements
-- as well for the background". A picture drawn pixel by pixel into one EditableImage at the world's art grid (each art
-- pixel K x K screen px, like the pixel layer), shown on a ScreenGui just behind the pixel layer: the stage's sky is
-- see-through (CameraController Stage.clear), so the egg stands in front of it.
-- Each rarity has its own sky (a cozy sunset for a common egg, a golden afternoon, a blue twilight, a violet night, a
-- deep gold night, and since 2026-11-14 a rose night under two moons for a mythic egg and a deep starry sky with a
-- ringed planet and the band of the galaxy across it for a celestial one): the sky in bands with ordered dither between
-- them (never a smear), the sun, the moons or the planet lit from the top left with anti-aliased edges, stars (single
-- pixels and little crosses), aurora curtains on the rarest nights, three ranges of hills going darker toward the
-- front and a glow round the egg in dithered rings. (The clouds, the trees along the nearest hills and the two islets
-- floating far off went on 2026-11-14: "For the hatch screen, remove the trees in the background, and the floating
-- islands as well", then "Remove the clouds in the hatch screen background as well".)
-- Since 2026-11-14 ("Polish the egg opening backgrounds even more, drawing in a base for the eggs to land on", and "add an
-- expanding circle ring that constantly emits below each egg") a round pedestal stands where the egg comes down: its
-- top an ellipse with a lit rim at the back left, an inlaid ring (gems on it from rare up), the egg's dithered shadow,
-- its side lit on the left and shaded on the right with a carved band and the joints of its stones, standing on a
-- fluted column of the same stone that rises from below the picture, a 1 px ink outline round it all, in each
-- rarity's stone (BASES); tufts of grass and little flowers along the bottom, and
-- the corners a dithered step darker. Once the egg has landed (`land`) rings of light spread over the pedestal's top
-- from under it, one every RING_EVERY s, each a clean 1 px ellipse stepping from bright to faint as it widens (their
-- own image on the sky's life layer, so the egg stands in front of them).
--   HatchBackdrop.show(r, ex, ey, base?)   paint rarity r's sky with the egg's glow at art pixel (ex, ey) and show it;
--                                   base { x, y, w }: the pedestal's top centre and half width, art px
--   HatchBackdrop.land()            the egg is down: a strong ring now, then rings for as long as the backdrop shows
--   HatchBackdrop.rings() -> number the rings spreading now (sims and previews)
--   HatchBackdrop.step(dt)          the sky's life (a layer between the picture and the pixel layer, so the islet hides it):
--                                   little flocks of birds flapping across a day or twilight sky, shooting stars and
--                                   twinkling stars on a night one; all whole art pixels, solid colours
--   HatchBackdrop.hide()            take it away (and free its image)
--   HatchBackdrop.paint(r, W, H, ex, ey, base?) -> buffer   the picture itself (RGBA, W x H)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)

local HatchBackdrop = {}

type Sky = {
	stops: { number }, -- the sky's colours from the top down to the horizon
	horizon: number, -- where the last stop is reached (share of the height)
	body: string, -- "sun" | "crescent" | "moon" | "bigsun" | "twomoons" | "planet"
	bodyC: { number }, -- its fill, its shade (the side away from the light), its spots
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
}

-- Each rarity's pedestal (`paint`'s base): its top, the top's lit rim, its side lit, plain and shaded, the carved band
-- and the inlaid ring, the gems, the ink, the flowers along the bottom, the rings' light.
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

------------------------------------------------------------------ painting
-- The picture as 0xRRGGBB per pixel in a plain array (painted layer over layer), packed into RGBA at the end.
type BaseAt = { x: number, y: number, w: number }

function HatchBackdrop.paint(r: number, W: number, H: number, ex: number, ey: number, ped: BaseAt?): buffer
	local sky = SKIES[math.clamp(r, 1, #SKIES)]
	local px: { number } = table.create(W * H, 0)
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
	for y = 0, H - 1 do
		local t = math.clamp(y / hy, 0, 1) * (#stops - 1)
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
	-- the sun or the moon, up and to the left: lit from the top left, a darker side away from it, anti-aliased edges
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
				local shade = (dx + dy) / br > 0.55
				local c = if shade then bc[2] else bc[1]
				if sky.body == "moon" or sky.body == "twomoons" then
					-- craters: three soft spots
					for _, cr in { { -0.3, -0.2, 0.22 }, { 0.25, 0.3, 0.17 }, { 0.35, -0.35, 0.12 } } do
						if (dx / br - cr[1]) ^ 2 + (dy / br - cr[2]) ^ 2 < cr[3] * cr[3] then
							c = bc[3]
						end
					end
				elseif sky.body == "sun" and r == 1 then
					-- a sunset's bands across its lower half
					local v = dy / br
					if v > 0.15 and (math.floor((v - 0.15) * 9) % 2 == 1) then
						c = bc[3]
					end
				elseif sky.body == "bigsun" then
					local v = dy / br
					if v > -0.05 and (math.floor((v + 0.05) * 7) % 2 == 1) then
						c = bc[3]
					end
				elseif sky.body == "planet" then
					-- soft bands of cloud across it, wavy
					local v = dy / br + math.sin(dx / br * 3) * 0.06
					if math.floor((v + 1) * 3.5) % 2 == 1 and not shade then
						c = bc[3]
					end
				end
				set(x, y, if cover >= 0.75 then c elseif cover >= 0.25 then mix(get(x, y), c, 0.5) else get(x, y))
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
					local c = if (dx + dy) / mr > 0.5 then bc[3] else bc[2]
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
	-- three ranges of hills, far to near, each a wavy ridge with a lit rim (no trees along the nearest since 2026-11-14)
	for li, hl in sky.hills do
		local base = hy - H * 0.13 + li * H * 0.075
		local amp = H * (0.05 - li * 0.008)
		local function ridge(x: number): number
			return base - amp * (0.6 + 0.4 * math.sin(x * (0.011 + li * 0.004) + li * 2.3)) - amp * 0.5 * math.sin(x * (0.031 + li * 0.006) + li)
		end
		for x = 0, W - 1 do
			local top = math.floor(ridge(x + 0.5))
			for y = math.max(0, top), H - 1 do
				px[y * W + x + 1] = if y == top then hl[2] else hl[1]
			end
		end
	end
	-- the foreground: tufts of grass along the bottom (three blades, the middle tallest, the left one lit), a little
	-- flower on some
	local near = sky.hills[#sky.hills]
	local B = BASES[math.clamp(r, 1, #BASES)]
	local bladeLit, blade = mix(near[2], 0xFFFFFF, 0.12), mix(near[1], near[2], 0.5)
	for i = 1, math.floor(W / 6) do
		local x = math.floor(hash(i * 71 + r * 5) * W)
		local y = H - 1 - math.floor(hash(i * 83 + 3) * H * 0.08)
		local tall = 2 + math.floor(hash(i * 97 + 1) * 3)
		for k = -1, 1 do
			local hgt = if k == 0 then tall else tall - 1
			for j = 0, hgt - 1 do
				set(x + k * 2 + (if j == hgt - 1 and k ~= 0 then k else 0), y - j, if k < 0 then bladeLit else blade)
			end
		end
		if hash(i * 13 + 7) < 0.3 then
			set(x, y - tall, B.flower)
		end
	end
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
		local colTop = math.floor(cy + sh)
		for y = colTop, H - 1 do
			local fade = math.clamp((y - colTop) / math.max(1, H - colTop), 0, 1)
			for x = math.floor(cx - cw), math.ceil(cx + cw) do
				if inColumn(x + 0.5, y + 0.5) then
					local dx = (x + 0.5 - cx) / cw
					local c = if dx < -0.4 then colLit elseif dx > 0.35 then colDark else col
					if (x - math.floor(cx)) % 4 == 0 then
						c = mix(c, B.ink, 0.22) -- (its fluting)
					end
					local lvl = math.floor(fade * 2 + bay(x, y) - 0.3)
					if lvl > 0 then
						c = mix(c, B.ink, 0.1 * lvl)
					end
					set(x, y, c)
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
						elseif r == 7 and hash2(x, y) > 0.95 then
							c = B.gem -- (stars in the starstone)
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
		-- the ink outline round the whole of it
		local edge: { number } = {}
		for y = math.floor(cy - ry) - 2, math.ceil(cy + ry + sh) + 2 do
			for x = math.floor(cx - bw) - 2, math.ceil(cx + bw) + 2 do
				if not inBase(x + 0.5, y + 0.5) and (inBase(x + 1.5, y + 0.5) or inBase(x - 0.5, y + 0.5) or inBase(x + 0.5, y + 1.5) or inBase(x + 0.5, y - 0.5)) then
					table.insert(edge, x)
					table.insert(edge, y)
				end
			end
		end
		for i = 1, #edge, 2 do
			set(edge[i], edge[i + 1], B.ink)
		end
		-- tufts of grass on the top's rim at the back, a little flower in each
		for k = 1, 2 do
			local a = if k == 1 then math.pi * 1.18 else math.pi * 1.72
			local fx = math.floor(cx + math.cos(a) * bw * 0.9)
			local fy = math.floor(cy + math.sin(a) * ry * 0.9)
			for j = 0, 1 do
				set(fx - 1, fy - j, bladeLit)
				set(fx + 1, fy - j, blade)
			end
			set(fx, fy - 2, bladeLit)
			set(fx, fy - 3, B.flower)
		end
	end
	-- the corners a dithered step or two darker, framing the egg
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
local lifeK = 1
local lifeW, lifeH = 0, 0
local lifeR = 1
local birds: { Bird } = {}
local streak: Streak? = nil
local streakAt = 0
local twinkles: { Twinkle } = {}
local lifeClock = 0
local INK: { number } = { 0x6E4E78, 0x4F7A6A, 0x1F2A4C, 0, 0, 0, 0 } -- the birds' colour by rarity (none on the nights)
local newLife: (r: number, W: number, H: number, K: number) -> ()

local ringBase: BaseAt? = nil
local makeRings: (r: number, K: number) -> ()

function HatchBackdrop.show(r: number, ex: number, ey: number, base: BaseAt?)
	local K = math.max(1, math.floor(PixelRenderer.pixelScale()))
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
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
		l.Parent = ng
		ng.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui, label = ng, l
		g = ng
	end
	local l = label :: ImageLabel
	l.ImageContent = Content.fromObject(im)
	l.Size = UDim2.fromOffset(W * K, H * K)
	l.Position = UDim2.fromOffset(0, 0)
	if g then
		g.Enabled = true
	end
	newLife(r, W, H, K)
	makeRings(r, K)
end

local function pixel(parent: Instance, c: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(rgb(c))
	f.Size = UDim2.fromOffset(lifeK, lifeK)
	f.Parent = parent
	return f
end

local function put(f: Frame, x: number, y: number)
	f.Position = UDim2.fromOffset(math.floor(x) * lifeK, math.floor(y) * lifeK)
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
	l.Size = UDim2.fromOffset(w * K, h * K)
	l.Position = UDim2.fromOffset((math.floor(base.x) - math.floor(w / 2)) * K, (math.floor(base.y) - math.floor(h / 2)) * K)
	l.Parent = g
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

function HatchBackdrop.rings(): number
	return #ringBorn
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
	local im = image
	if im then
		im:Destroy()
	end
	gui, label, image = nil, nil, nil
end

return HatchBackdrop
