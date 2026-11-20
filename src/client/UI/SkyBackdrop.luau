--!strict
--!native
-- The sky round the floating islands (GAME_DESIGN 2 and 8; docs/ARCHITECTURE.md 10.19): the request of 2026-11-20,
-- "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the island bigger.", then the
-- same day "polish the skybox more. it should be of the same quality as the ones in the egg hatching screen, with day
-- and night cycles with moon and sun rising". Painted pixel by pixel at the world's art grid (each art pixel K x K
-- screen px, like the pixel layer) on a ScreenGui behind the pixel layer: the islands' sky is see-through
-- (CameraController's view `clear`), so they float in front of it. Back to front:
-- * the sky: bands of colour from the top down, each meeting the next in an ordered dither (never a smear); at night
--   stars (single pixels in two strengths and little crosses, coming out one by one as it darkens, the brightest
--   first) and the band of the galaxy slanting across, a darker lane down its middle;
-- * the sun and the moon on their arcs: each rises from behind the sea of clouds on the left, climbs and sets on the
--   right, one flat tone with anti-aliased edges in a halo of dithered rings (the sun's halo wider and warmer near the
--   horizon); the moon has craters and a phase that changes every night (full, gibbous, half and a crescent, waning
--   then waxing; never dark);
-- * far islets floating in the haze (a grass cap over a stony point, a little tree on the bigger ones, faded toward the
--   sky, a 1 px outline) and the sea of clouds along the bottom: three ranges of puffs going brighter toward the front,
--   each puff's top lit from the top left, shaded under it and on the seam where one stands in front of another, a
--   1 px outline along each range's top; it repeats across, drifts slowly and slides a sixteenth of the view's pan;
-- * the clouds: puffy, a row of round puffs each, lit and shaded the same way, outlined a step darker than the sky
--   behind, corners anti-aliased; they drift right and slide an eighth of the pan;
-- * the sky's life: little flocks of birds flapping across by day, stars twinkling and now and then a shooting star at
--   night (whole art px, solid colours).
-- The time of day (`DayLight.skyHour`, the sea's clock round `Tuning.SkyDaySecs`) picks the colours from KEYS (night,
-- the first light, sunrise, morning, day, the afternoon, sunset, dusk), stepped NOTCHES times between two keys; the
-- weather (WX) pulls them toward its own grey, adds clouds, hides the stars and veils the sun and the moon in rain,
-- storm and fog. The shapes are worked out once for a screen size and a weather's clouds (`buildGeo`: a class a
-- pixel); a new notch only colours them again from small tables, a few rows a frame, and uploads the three pictures
-- once done, so the sky never stalls a frame.
--   start(), paint(kind, W, H, hour?) -> (sky, front, clouds)  the three pictures (RGBA, W x H; front and clouds
--       clear where empty), debugState(), debugHour(h?, night?) (hold the sky at an hour: DayLight.debugSky)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local WeatherView = require(script.Parent.Parent.Controllers.WeatherView)
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)

local SkyBackdrop = {}

local DRIFT = 1.6 -- s a pixel the clouds drift right
local SEA_DRIFT = 6 -- s a pixel the sea of clouds and the far islets drift right
local PARALLAX = 1 / 8 -- of the view's pan the clouds slide with
local FAR_PARALLAX = 1 / 16 -- and the sea of clouds
local NOTCHES = 10 -- colour steps between two keys
local SUNRISE, SUNSET = 0.23, 0.77 -- (the sky's hour the sun's middle crosses the horizon)
local HORIZON = 0.77 -- (share of the height: the sun's or the moon's middle when it rises or sets, half behind the sea of clouds)
local BANDS_TO = 0.84 -- (share of the height: the sky's last colour from here down)
local ROW_PIXELS = 25000 -- pixels coloured a frame while a new notch is painted (about 4 ms on a desktop)

------------------------------------------------------------------ colours
local BAYER: { number } = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function bay(x: number, y: number): number
	return (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16
end

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16) % 256, bit32.rshift(c, 8) % 256, c % 256
end

local function byte(v: number): number
	return math.clamp(math.floor(v + 0.5), 0, 255)
end

local function mix(a: number, b: number, k: number): number
	local ar, ag, ab = rgb(a)
	local br, bg, bb = rgb(b)
	return byte(ar + (br - ar) * k) * 65536 + byte(ag + (bg - ag) * k) * 256 + byte(ab + (bb - ab) * k)
end

-- a colour lit by another (each channel times the other's share of 255)
local function lit(c: number, by: number): number
	local r, g, b = rgb(c)
	local lr, lg, lb = rgb(by)
	return byte(r * lr / 255) * 65536 + byte(g * lg / 255) * 256 + byte(b * lb / 255)
end

local function lum(c: number): number
	local r, g, b = rgb(c)
	return 0.3 * r + 0.59 * g + 0.11 * b
end

-- a 0xRRGGBB colour as the image's RGBA bytes (little-endian u32), opaque or at alpha a (0 .. 1)
local function packed(c: number, a: number?): number
	local r, g, b = rgb(c)
	return r + g * 256 + b * 65536 + byte((a or 1) * 255) * 16777216
end

local function hash(n: number): number
	local x = math.floor(n) % 2147483647
	x = (x * 1103515245 + 12345) % 2147483648
	x = (x * 1103515245 + 12345) % 2147483648
	return x / 2147483648
end

------------------------------------------------------------------ the time of day
type Key = {
	name: string,
	h: number, -- the sky's hour it is reached
	stops: { number }, -- the sky's six colours from the top down
	lit: number, -- the clouds: the lit tops, the body, the shade, the ink their outlines lean toward
	body: number,
	shade: number,
	ink: number,
	light: number, -- the light on the far islets (each channel times this)
	stars: number, -- how much of the night shows (0 .. 1): the stars, the galaxy
}

local NIGHT: Key = {
	name = "night",
	h = 0,
	stops = { 0x161A40, 0x1C224E, 0x242C5E, 0x2E386E, 0x3A4680, 0x4A5690 },
	lit = 0x8E98CC,
	body = 0x66709E,
	shade = 0x4C5582,
	ink = 0x0E1230,
	light = 0x6670A8,
	stars = 1,
}
local FIRST_LIGHT: Key = {
	name = "firstlight",
	h = 0,
	stops = { 0x1E2250, 0x2A2E64, 0x3C3C7A, 0x52498C, 0x70589C, 0x9468A8 },
	lit = 0xA89CCC,
	body = 0x7A70A6,
	shade = 0x5A5488,
	ink = 0x161838,
	light = 0x7E78B0,
	stars = 0.75,
}
local SUNUP: Key = {
	name = "sunrise",
	h = 0,
	stops = { 0x4456A0, 0x6466B0, 0x9078BA, 0xC888B8, 0xF2A2A2, 0xFFCB92 },
	lit = 0xFFE4C8,
	body = 0xF4C0C4,
	shade = 0xBC98BC,
	ink = 0x4C3C70,
	light = 0xFFD2BE,
	stars = 0.12,
}
local MORNING: Key = {
	name = "morning",
	h = 0,
	stops = { 0x62AAE4, 0x78B8EB, 0x90C6F0, 0xAAD3F3, 0xC8E1F2, 0xE8ECEA },
	lit = 0xFFFFFF,
	body = 0xF6F4F6,
	shade = 0xD8DAEC,
	ink = 0x3E5A8C,
	light = 0xFFF6EE,
	stars = 0,
}
local DAY: Key = {
	name = "day",
	h = 0,
	stops = { 0x6DB7EA, 0x80C3EF, 0x94CFF4, 0xA8DAF7, 0xBDE4FA, 0xD3EEFB },
	lit = 0xFFFFFF,
	body = 0xF1F8FE,
	shade = 0xCFE2F3,
	ink = 0x3A5E8C,
	light = 0xFFFFFF,
	stars = 0,
}
local AFTERNOON: Key = {
	name = "afternoon",
	h = 0,
	stops = { 0x6AB0E2, 0x82BCE8, 0x9DC8EA, 0xBAD4E8, 0xDADCDC, 0xF4E4CA },
	lit = 0xFFFBF0,
	body = 0xF8EFE8,
	shade = 0xDDD3DE,
	ink = 0x485A86,
	light = 0xFFF4E4,
	stars = 0,
}
local SUNDOWN: Key = {
	name = "sunset",
	h = 0,
	stops = { 0x4C549A, 0x7060AA, 0xA66CB0, 0xDA7AA2, 0xF89C88, 0xFFC47C },
	lit = 0xFFD8A6,
	body = 0xF2AAAA,
	shade = 0xAA7EA8,
	ink = 0x40305E,
	light = 0xFFC8B0,
	stars = 0.08,
}
local DUSK: Key = {
	name = "dusk",
	h = 0,
	stops = { 0x252A5E, 0x313672, 0x444284, 0x5C4E94, 0x7C5CA0, 0x9E6EA8 },
	lit = 0xB8A0CC,
	body = 0x8274AA,
	shade = 0x5E5688,
	ink = 0x1A1A3A,
	light = 0x8A80B4,
	stars = 0.6,
}

local function key(h: number, k: Key): Key
	return { name = k.name, h = h, stops = k.stops, lit = k.lit, body = k.body, shade = k.shade, ink = k.ink, light = k.light, stars = k.stars }
end

local KEYS: { Key } = {
	key(0, NIGHT),
	key(0.15, NIGHT),
	key(0.2, FIRST_LIGHT),
	key(0.235, SUNUP),
	key(0.29, MORNING),
	key(0.36, DAY),
	key(0.64, DAY),
	key(0.71, AFTERNOON),
	key(0.765, SUNDOWN),
	key(0.8, DUSK),
	key(0.86, NIGHT),
	key(1, NIGHT),
}

------------------------------------------------------------------ the weather
type Wx = {
	tint: number, -- the grey it pulls every colour toward (at the colour's own lightness)
	k: number, -- how far
	dark: number, -- that grey's lightness times this
	clouds: number, -- clouds for every 100,000 px
	veil: number, -- how veiled the sun and the moon are (their transparency)
	fade: number, -- how much further the far islets and the far clouds fade into the sky
}
local CLEAR: Wx = { tint = 0xFFFFFF, k = 0, dark = 1, clouds = 6, veil = 0, fade = 0 }
local WX: { [string]: Wx } = {
	sunny = CLEAR,
	blossom = CLEAR,
	leaves = CLEAR,
	breezy = { tint = 0xFFFFFF, k = 0, dark = 1, clouds = 8, veil = 0, fade = 0 },
	rain = { tint = 0x8C9AAE, k = 0.55, dark = 0.9, clouds = 10, veil = 0.55, fade = 0.1 },
	storm = { tint = 0x58627C, k = 0.72, dark = 0.72, clouds = 13, veil = 0.85, fade = 0.15 },
	fog = { tint = 0xC6D0DA, k = 0.62, dark = 1.08, clouds = 5, veil = 0.6, fade = 0.25 },
	snow = { tint = 0xBCCCDE, k = 0.45, dark = 1.04, clouds = 8, veil = 0.4, fade = 0.1 },
	haze = { tint = 0xEED8B0, k = 0.3, dark = 1, clouds = 4, veil = 0.15, fade = 0.1 },
}

local function weathered(c: number, wx: Wx): number
	if wx.k <= 0 then
		return c
	end
	local tr, tg, tb = rgb(wx.tint)
	local s = math.max(1, lum(c)) / math.max(1, lum(wx.tint)) * wx.dark
	return mix(c, byte(tr * s) * 65536 + byte(tg * s) * 256 + byte(tb * s), wx.k)
end

type Pal = {
	key: string, -- the weather and the notch: a new key paints again
	stops: { number },
	lit: number,
	body: number,
	shade: number,
	ink: number,
	light: number,
	stars: number,
	wx: Wx,
}

-- The colours at the sky's hour h in a weather, stepped to the notch.
local function paletteAt(h: number, kind: string): Pal
	local wx = WX[kind] or CLEAR
	h = h % 1
	local i = 1
	while i < #KEYS - 1 and KEYS[i + 1].h <= h do
		i += 1
	end
	local a, b = KEYS[i], KEYS[i + 1]
	local n = math.floor((h - a.h) / math.max(1e-6, b.h - a.h) * NOTCHES + 0.5)
	if a.stops == b.stops then
		n = 0
	end
	if n >= NOTCHES then
		a, n, i = b, 0, i + 1
	end
	local f = n / NOTCHES
	local stops = table.create(6, 0)
	for s = 1, 6 do
		stops[s] = weathered(mix(a.stops[s], b.stops[s], f), wx)
	end
	return {
		-- (a key held over a stretch, night or day, is one notch whichever segment it is in)
		key = string.format("%s:%s:%d", kind, if a.stops == b.stops then a.name else a.name .. ">" .. b.name, n),
		stops = stops,
		lit = weathered(mix(a.lit, b.lit, f), wx),
		body = weathered(mix(a.body, b.body, f), wx),
		shade = weathered(mix(a.shade, b.shade, f), wx),
		ink = weathered(mix(a.ink, b.ink, f), wx),
		light = weathered(mix(a.light, b.light, f), wx),
		stars = (a.stars + (b.stars - a.stars) * f) * math.max(0, 1 - wx.k * 1.5),
		wx = wx,
	}
end

-- The sky's band rows: at row y the stop above (0-based) and how far toward the next (the dither's share).
local function bandOf(y: number, H: number): (number, number)
	local t = math.clamp(y / math.max(1, H * BANDS_TO), 0, 1) * 5
	if t >= 5 then
		return 4, 1
	end
	local i = math.min(4, math.floor(t))
	return i, math.clamp((t - i - 0.3) / 0.4, 0, 1)
end
-- the sky's mean colour at row y (what an outline or a far thing blends into)
local function meanAt(pal: Pal, y: number, H: number): number
	local i, k = bandOf(y, H)
	return mix(pal.stops[i + 1], pal.stops[i + 2], k)
end

------------------------------------------------------------------ the shapes (once a screen size, the clouds once a weather)
-- The sky's class a pixel: the band (bits 0-2, 0 .. 5), the galaxy's strength (bits 3-4, 0 .. 3), a star (bits 5-7:
-- 1 dim, 2 bright, 3 brightest, 4 a cross's arm) and the star's threshold (`thr`: it shows once the night's 0 .. 255
-- passes it).
-- The front's: 0 clear; 1 .. 60 islet j's (j - 1) * 12 + (1 grass lit, 2 grass, 3 grass shade, 4 earth, 5 rock lit,
-- 6 rock, 7 rock shade, 8 bark, 9 falling water, 10 leaves lit, 11 leaves, 12 outline); 64 + range * 16 + (1 lit, 2 body, 3 shade, 4 deep: the
-- sea of clouds' tones; 5 .. 8 its outline beside a pixel of tone 1 .. 4; 9 an outline's corner over the sky).
-- The clouds': 0 clear, 1 .. 4 the tones, 5 .. 8 the outline beside a pixel of tone 1 .. 4, 9 a corner over the sky.
type Geo = {
	W: number,
	H: number,
	sky: buffer,
	thr: buffer,
	front: buffer,
	isles: { { number } }, -- { cx, cy, w, fade } each
}
type CloudGeo = { W: number, H: number, clouds: number, cloud: buffer }

-- the far islets' colours before the light, the weather and the haze: grass lit, grass, grass shade, earth, rock lit,
-- rock, rock shade, bark, falling water, leaves lit, leaves
local ISLE: { number } = { 0xC4F0A4, 0x96D480, 0x6CAE6A, 0x9A6E56, 0xBCB0BC, 0x948A9E, 0x6C6480, 0x7A5440, 0xE8F8FF, 0x7CC870, 0x52A060 }
local ISLE_TONES = 12
local MILKY = 0xC8D2FF
local SEA_FADE: { number } = { 0.5, 0.25, 0 } -- how far each range of the sea of clouds fades into the sky, far to near
local RANGES: { { number } } = { { 0.775, 0.05 }, { 0.845, 0.07 }, { 0.915, 0.1 } } -- base (share of H), puff step

local function skyShapes(g: Geo)
	local W, H = g.W, g.H
	local sky, thr = g.sky, g.thr
	for y = 0, H - 1 do
		local i, k = bandOf(y, H)
		local row = y * W
		for x = 0, W - 1 do
			buffer.writeu8(sky, row + x, if k > bay(x, y) then i + 1 else i)
		end
	end
	-- the galaxy: a broad band slanting up to the right, brightest along its spine, a lane of dust down its middle
	local bw = H * 0.11
	local function spine(x: number): number
		return H * (0.66 - 0.55 * x / W) + math.sin(x * 0.025) * H * 0.035
	end
	for y = 0, math.floor(H * 0.78) do
		for x = 0, W - 1 do
			local d = math.abs(y + 0.5 - spine(x + 0.5)) / bw
			if d < 1 then
				local k = (1 - d) ^ 1.3 * (0.75 + 0.25 * math.sin(x * 0.09 + y * 0.05))
				if d < 0.16 and math.sin(x * 0.05) > -0.3 then
					k *= 0.45
				end
				local lvl = math.min(3, math.floor(k * 3 + bay(x, y)))
				if lvl > 0 then
					local i = y * W + x
					buffer.writeu8(sky, i, bit32.bor(buffer.readu8(sky, i), lvl * 8))
				end
			end
		end
	end
	local function star(x: number, y: number, level: number, t: number)
		if x < 0 or y < 0 or x >= W or y >= H then
			return
		end
		local i = y * W + x
		local cur = buffer.readu8(sky, i)
		if level == 4 and cur >= 32 then
			return
		end
		buffer.writeu8(sky, i, bit32.band(cur, 31) + level * 32)
		buffer.writeu8(thr, i, math.clamp(math.floor(t), 0, 254))
	end
	local n = math.max(60, math.floor(W * H / 1000))
	for s = 1, n do
		local x = math.floor(hash(s * 7 + 3) * W)
		local y = math.floor(hash(s * 13 + 5) ^ 1.15 * H * 0.74)
		local b = hash(s * 3 + 11)
		local base = hash(s * 17 + 2) * 150
		if b > 0.9 then
			star(x, y, 3, base * 0.4)
			star(x + 1, y, 4, base * 0.4 + 30)
			star(x - 1, y, 4, base * 0.4 + 30)
			star(x, y + 1, 4, base * 0.4 + 30)
			star(x, y - 1, 4, base * 0.4 + 30)
		elseif b > 0.55 then
			star(x, y, 2, 40 + base * 0.8)
		else
			star(x, y, 1, 80 + base)
		end
	end
	-- (thick with faint stars along the galaxy)
	for s = 1, math.floor(120 * W / 640) do
		local x = math.floor(hash(s * 23 + 9) * W)
		local off = (hash(s * 37 + 1) + hash(s * 41 + 2) - 1) * bw * 0.9
		star(x, math.floor(spine(x + 0.5) + off), if hash(s * 5) > 0.7 then 2 else 1, 100 + hash(s * 29) * 120)
	end
end

------------------------------------------------------------------ lumps of cloud
-- Clouds are lumps: the front halves of ellipsoids { cx, cy, rx, ry, z } (z how far toward the eye). At each pixel the
-- surface nearest the eye wins and is lit by the sun at the top left (Lambert), then stepped into four tones (lit,
-- body, shade, deep) with a narrow ordered dither where two meet, so a cloud reads as round soft heaps with no line
-- drawn inside it.
local LX, LY, LZ = -0.45, -0.65, 0.61
local CUTS: { number } = { 0.6, 0.22, -0.15 }
local SEAM = 0.05

local function toneOf(v: number, x: number, y: number): number
	for t = 1, 3 do
		local c = CUTS[t]
		if v > c + SEAM then
			return t
		elseif v > c - SEAM then
			return if (v - (c - SEAM)) / (2 * SEAM) > bay(x, y) then t else t + 1
		end
	end
	return 4
end

-- The lumps into a field: for each pixel (keyOf names it) inside one, the light on the surface nearest the eye.
local function lumpsInto(lumps: { { number } }, H: number, keyOf: (number, number) -> number, vs: { [number]: number })
	local hs: { [number]: number } = {}
	for _, l in lumps do
		local cx, cy, rx, ry, z = l[1], l[2], l[3], l[4], l[5]
		for y = math.max(0, math.floor(cy - ry)), math.min(H - 1, math.ceil(cy + ry)) do
			local dy = (y + 0.5 - cy) / ry
			local dy2 = dy * dy
			if dy2 < 1 then
				local span = rx * math.sqrt(1 - dy2)
				for x = math.floor(cx - span - 1), math.ceil(cx + span) do
					local dx = (x + 0.5 - cx) / rx
					local q = dx * dx + dy2
					if q < 1 then
						local s = math.sqrt(1 - q)
						local h = z + s * ry
						local k = keyOf(x, y)
						local cur = hs[k]
						if cur == nil or h > cur then
							hs[k] = h
							vs[k] = dx * LX + dy * LY + s * LZ
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ the far islets
-- A far islet into the front (class base (j - 1) * 10), every part on whole pixels, across the picture's edge coming in
-- on the other side: a grass top (an ellipse seen from above, lit at the top left, a darker rim bending over its front
-- edge with tufts hanging here and there), an earth lip under the rim with a pebble or two, the rock under it narrowing
-- to a jagged point (lit on the left, shaded on the right, a darker line every few rows for its layers), roots and
-- little stones hanging under it, a tree or a bush on top, on the bigger ones a thread of water falling off the front
-- and thinning into spray; a 1 px outline round all of it.
local function islet(g: Geo, j: number, cx: number, cy: number, w: number, seed: number)
	local W, H = g.W, g.H
	local mask: { [number]: number } = {}
	local function key(x: number, y: number): number
		return y * W + (x % W)
	end
	local function set(x: number, y: number, v: number)
		if y >= 0 and y < H then
			mask[key(x, y)] = v
		end
	end
	local function has(x: number, y: number): boolean
		return y >= 0 and y < H and mask[key(x, y)] ~= nil
	end
	local function rnd(n: number): number
		return hash(seed * 131 + n)
	end
	local a = w / 2
	local b = math.max(3, math.floor(w * 0.2 + 0.5))
	local depth = math.floor(w * 0.75)
	-- the rock first (the top and the lip are laid over it): a main point under the middle and, on the bigger ones, one
	-- or two shorter points beside it, each lit on its left and shaded on its right, broken lines of its layers
	local cones: { { number } } = { { cx, depth, a } }
	if w >= 20 then
		table.insert(cones, { cx - a * (0.4 + rnd(2) * 0.15), depth * (0.45 + rnd(3) * 0.2), a * 0.5 })
	end
	if w >= 28 then
		table.insert(cones, { cx + a * (0.38 + rnd(4) * 0.15), depth * (0.35 + rnd(11) * 0.2), a * 0.45 })
	end
	local strata = 3 + math.floor(rnd(1) * 2)
	local tip = cy + b + depth
	for ci, c in cones do
		local ccx, cd, ca = c[1], c[2], c[3]
		local ctip = cy + b + cd
		for y = cy, math.floor(ctip) do
			local f = (y - cy) / math.max(1, ctip - cy)
			local half = ca * (1 - f) ^ 1.15 + (rnd(10 + y + ci * 50) - 0.5) * 1.4 + (if f > 0.25 and rnd(40 + y // 2 + ci * 50) > 0.82 then -1 else 0)
			local lean = (rnd(70 + y // 3 + ci * 50) - 0.5) * 1.2 * f -- (the point wanders a little)
			if half >= 0.5 then
				for x = math.floor(ccx + lean - half + 0.5), math.floor(ccx + lean + half - 0.5) do
					if has(x, y) then
						continue
					end
					local rel = (x + 0.5 - ccx - lean) / math.max(1, half)
					local t = 6
					if rel < -0.4 then
						t = 5
					elseif rel < -0.25 then
						t = if bay(x, y) < (-0.25 - rel) / 0.15 then 5 else 6
					elseif rel > 0.42 then
						t = 7
					elseif rel > 0.27 then
						t = if bay(x, y) < (rel - 0.27) / 0.15 then 7 else 6
					end
					if (y - cy) % strata == 0 and y > cy + b and t < 7 and rel > -0.6 and rnd(600 + y * 7 + x // 3) > 0.4 then
						t += 1 -- (a layer's line, broken)
					end
					set(x, y, t)
				end
			end
		end
	end
	-- the grass top: an ellipse lit at the top left, its front rim a step darker
	for y = cy - b, cy + b do
		local dy = (y + 0.5 - cy) / b
		if math.abs(dy) < 1 then
			local half = a * math.sqrt(1 - dy * dy)
			for x = math.floor(cx - half + 0.5), math.floor(cx + half - 0.5) do
				local nx = (x + 0.5 - cx) / a
				local v = -nx * 0.55 - dy * 0.85
				local t = 2
				if v > 0.34 then
					t = 1
				elseif v > 0.18 then
					t = if bay(x, y) < (v - 0.18) / 0.16 then 1 else 2
				elseif v < -0.75 then
					t = 3
				end
				if dy > 0 and nx * nx + dy * dy > 0.72 then
					t = 3
				end
				set(x, y, t)
			end
		end
	end
	-- the lip under the front rim: tufts of grass hanging over it, then two rows of earth with a pebble now and then
	for x = math.floor(cx - a + 1), math.floor(cx + a - 1) do
		local nx = (x + 0.5 - cx) / a
		local e = math.floor(cy + b * math.sqrt(math.max(0, 1 - nx * nx)) + 0.5)
		local drip = if rnd(200 + x) > 0.62 then 1 else 0
		for y = e, e + drip - 1 do
			set(x, y, 3)
		end
		for y = e + drip, e + 1 + drip do
			set(x, y, if rnd(300 + x * 7 + y) > 0.9 then 6 else 4)
		end
	end
	-- a few flowers in the grass
	for k = 1, math.floor(w / 8) do
		local fx = math.floor(cx + (rnd(700 + k) - 0.5) * a * 1.4)
		local fy = math.floor(cy + (rnd(710 + k) - 0.5) * b * 1.2)
		local m = mask[key(fx, fy)]
		if m == 1 or m == 2 then
			set(fx, fy, 9)
		end
	end
	-- roots and little stones hanging below
	for k = 1, math.max(1, math.floor(w / 9)) do
		local x = math.floor(cx + (rnd(400 + k) - 0.5) * a * 1.2)
		local y0 = cy + b + 2
		while has(x, y0) and y0 < tip do
			y0 += 1
		end
		for y = y0, y0 + 1 + math.floor(rnd(410 + k) * 3) do
			set(x, y, 8)
		end
	end
	for k = 1, 1 + math.floor(rnd(5) * 2) do
		local sx = math.floor(cx + (rnd(500 + k) - 0.5) * a * 0.9)
		local sy = tip + 3 + math.floor(rnd(510 + k) * 5) + k * 2
		local sw = 1 + math.floor(rnd(520 + k) * 2)
		for dx = 0, sw do
			set(sx + dx, sy, if dx == 0 then 5 else 6)
		end
		set(sx + math.floor(sw / 2), sy + 1, 7)
	end
	-- on top: a tree (a trunk, a round crown lit at the top left) on the bigger islets, else a bush
	local function crown(tx: number, ty: number, r: number)
		for dy = -r, r do
			for dx = -r, r do
				local d2 = dx * dx + dy * dy
				if d2 <= r * r + r * 0.6 then
					local v = (-dx * 0.6 - dy * 0.8) / math.max(1, r)
					set(tx + dx, ty + dy, if v > 0.35 then 10 elseif v < -0.45 or (dy > 0 and d2 > r * r - r) then 3 else 11)
				end
			end
		end
	end
	if w >= 22 then
		local tx = math.floor(cx - a * (0.15 + rnd(6) * 0.35))
		local ty = cy - math.floor(b * 0.2)
		local r = math.max(2, math.floor(w / 10))
		for y = ty - r - 1, ty do
			set(tx, y, 8)
		end
		crown(tx, ty - r - 2, r)
		if w >= 30 then
			crown(math.floor(cx + a * 0.4), cy - 1, math.max(1, r - 2))
		end
	else
		crown(math.floor(cx + (rnd(7) - 0.5) * a * 0.6), cy - 1, 1)
	end
	-- water falling off the front of the bigger ones, thinning into spray below the rock
	if w >= 26 and rnd(8) > 0.4 then
		local fx = math.floor(cx + a * (0.15 + rnd(9) * 0.3))
		local fy = math.floor(cy + b * math.sqrt(math.max(0, 1 - ((fx + 0.5 - cx) / a) ^ 2)) + 0.5) - 1
		local len = depth + 4
		for y = fy, fy + len do
			local thin = y > fy + len - 6
			if not thin or (y + fx) % 2 == 0 then
				set(fx, y, 9)
			end
			if y < fy + len * 0.6 then
				set(fx + 1, y, 9)
			end
		end
	end
	local base = (j - 1) * ISLE_TONES
	for i, v in mask do
		buffer.writeu8(g.front, i, base + v)
	end
	for i in mask do
		local x, y = i % W, i // W
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local ny = y + d[2]
			if ny >= 0 and ny < H then
				local ni = ny * W + ((x + d[1]) % W)
				if mask[ni] == nil and buffer.readu8(g.front, ni) == 0 then
					buffer.writeu8(g.front, ni, base + ISLE_TONES)
				end
			end
		end
	end
end

------------------------------------------------------------------ the sea of clouds
-- Three ranges of lumps along the bottom, far to near, each repeating across exactly (a whole number of lumps a
-- width) so the picture tiles: big lumps in a row, smaller ones heaped on some of them, solid below; each range darker
-- toward its foot, a 1 px outline along its top in a darker step of the tone beside it, its corners anti-aliased.
local function seaShapes(g: Geo)
	local W, H = g.W, g.H
	local front = g.front
	for r = 0, 2 do
		local spec = RANGES[r + 1]
		local base = H * spec[1]
		local n = math.max(3, math.floor(W / math.max(8, H * spec[2]) + 0.5))
		local sp = W / n
		local lumps: { { number } } = {}
		for i = 0, n - 1 do
			local s = r * 97 + i * 13 + 7
			local rx = sp * (0.55 + hash(s) * 0.5)
			local ry = rx * (0.62 + hash(s + 3) * 0.16)
			local cx = (i + 0.5) * sp + (hash(s + 1) - 0.5) * sp * 0.45
			local cy = base + ry * 0.35 + (hash(s + 2) - 0.4) * sp * 0.3
			local z = hash(s + 4) * ry * 0.4
			table.insert(lumps, { cx, cy, rx, ry, z })
			if hash(s + 5) > 0.45 then
				local rx2 = rx * (0.4 + hash(s + 6) * 0.2)
				table.insert(lumps, { cx + (hash(s + 7) - 0.5) * rx * 0.9, cy - ry * 0.62, rx2, rx2 * 0.78, z + ry * 0.7 })
			end
		end
		local flat = base + sp * 0.5
		local vs: { [number]: number } = {}
		lumpsInto(lumps, H, function(x: number, y: number): number
			return y * W + (x % W)
		end, vs)
		local cls = 64 + r * 16
		local own: { [number]: number } = {}
		local y0 = H
		for k in vs do
			y0 = math.min(y0, k // W)
		end
		for y = y0, H - 1 do
			for x = 0, W - 1 do
				local i = y * W + x
				local v = vs[i]
				if v ~= nil or y >= flat then
					local t = if v then toneOf(v, x, y) else 3
					if y > flat + sp * 0.3 then
						t = math.max(t, if r == 2 and y > flat + sp * 0.75 then 4 else 3)
					elseif y > flat then
						t = math.max(t, 2)
					end
					own[i] = t
					buffer.writeu8(front, i, cls + t)
				end
			end
		end
		-- the outline along the range's top (and the corners), over the sky or a farther range
		local function at(x: number, y: number): number?
			if y < 0 or y >= H then
				return nil
			end
			return own[y * W + (x % W)]
		end
		for y = math.max(0, y0 - 1), math.min(H - 1, math.ceil(flat) + 1) do
			for x = 0, W - 1 do
				local i = y * W + x
				if own[i] then
					continue
				end
				local t = at(x, y + 1) or at(x - 1, y) or at(x + 1, y) or at(x, y - 1)
				if t then
					buffer.writeu8(front, i, cls + 4 + t)
				elseif (at(x - 1, y + 1) or at(x + 1, y + 1)) and buffer.readu8(front, i) == 0 then
					buffer.writeu8(front, i, cls + 9)
				end
			end
		end
	end
end

------------------------------------------------------------------ the drifting clouds
-- One cloud into the clouds' picture (repeating across): its lumps over a flat bottom at `base` (the bottom rows a
-- step darker), its outline a darker step of the tone beside it, its corners anti-aliased over the sky.
local function cloud(cg: CloudGeo, lumps: { { number } }, base: number)
	local W, H = cg.W, cg.H
	local vs: { [number]: number } = {}
	local function key(x: number, y: number): number
		return y * 65536 + (x + 32768)
	end
	lumpsInto(lumps, H, key, vs)
	local own: { [number]: number } = {}
	for k, v in vs do
		local y = k // 65536
		if y <= base then
			local x = k % 65536 - 32768
			local t = toneOf(v, x, y)
			if y >= base - 1 then
				t = math.max(t, 3)
			elseif y >= base - 3 then
				t = math.max(t, 2)
			end
			own[k] = t
		end
	end
	local buf = cg.cloud
	for k, t in own do
		local y, x = k // 65536, k % 65536 - 32768
		buffer.writeu8(buf, y * W + (x % W), t)
	end
	local edge: { [number]: boolean } = {}
	for k, t in own do
		local y, x = k // 65536, k % 65536 - 32768
		for _, d in { { 0, -1 }, { -1, 0 }, { 1, 0 }, { 0, 1 } } do
			local nx, ny = x + d[1], y + d[2]
			local nk = key(nx, ny)
			if ny >= 0 and ny < H and own[nk] == nil and not edge[nk] then
				edge[nk] = true
				buffer.writeu8(buf, ny * W + (nx % W), 4 + t)
			end
		end
	end
	for k in own do
		local y, x = k // 65536, k % 65536 - 32768
		for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local nx, ny = x + d[1], y + d[2]
			local nk = key(nx, ny)
			if ny >= 0 and ny < H and own[nk] == nil and not edge[nk] then
				local i = ny * W + (nx % W)
				if buffer.readu8(buf, i) == 0 then
					edge[nk] = true
					buffer.writeu8(buf, i, 9)
				end
			end
		end
	end
end

local function buildGeo(W: number, H: number): Geo
	local g: Geo = {
		W = W,
		H = H,
		sky = buffer.create(W * H),
		thr = buffer.create(W * H),
		front = buffer.create(W * H),
		isles = {},
	}
	skyShapes(g)
	-- the far islets: the same places in every weather (a fixed seed), apart from one another, above the sea of
	-- clouds; the smaller ones farther off, so fainter
	local count = math.clamp(math.floor(W * H / 60000 + 0.5), 3, 5)
	local tries = 0
	while #g.isles < count and tries < 60 do
		tries += 1
		local s = tries * 7 + 3
		local w = 18 + math.floor(hash(s) * 24)
		local cx = math.floor(w / 2 + 4 + hash(s + 1) * (W - w - 8))
		local cy = math.floor(H * 0.18 + hash(s + 2) * H * 0.36)
		local ok = true
		for _, q in g.isles do
			if math.abs(q[1] - cx) < (q[3] + w) * 0.7 + 10 and math.abs(q[2] - cy) < (q[3] + w) * 0.8 + 8 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(g.isles, { cx, cy, w, 0.42 - (w - 18) / 24 * 0.22 })
			islet(g, #g.isles, cx, cy, w, s)
		end
	end
	seaShapes(g)
	return g
end

-- The drifting clouds for a weather's count: the farther (higher) first, so a nearer one stands in front.
local function buildClouds(W: number, H: number, clouds: number): CloudGeo
	local cg: CloudGeo = { W = W, H = H, clouds = clouds, cloud = buffer.create(W * H) }
	local many = math.max(3, math.floor(W * H / 100000 * clouds + 0.5))
	local list: { { number } } = {}
	for k = 1, many do
		local s = k * 13 + 101
		table.insert(list, { hash(s) * W, math.floor(H * 0.1 + hash(s + 1) * H * 0.54), s })
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	for _, c in list do
		local s = c[3]
		local cx, base = c[1], c[2]
		local scale = 0.7 + (base / H) * 0.55
		local lumps: { { number } } = {}
		local np = 4 + math.floor(hash(s + 2) * 4)
		local span = (26 + hash(s + 3) * 44) * scale
		for p = 1, np do
			local u = (p - 1) / (np - 1) - 0.5
			local rx = (6 + 10 * (1 - math.abs(u) * 1.5) + hash(s + 10 + p) * 4) * scale
			local ry = rx * (0.7 + hash(s + 40 + p) * 0.14)
			local ly = base - ry * 0.4 - (1 - math.abs(u) * 2) * ry * 0.3 - hash(s + 30 + p) * 2 * scale
			table.insert(lumps, { cx + u * span + (hash(s + 20 + p) - 0.5) * 4, ly, rx, ry, (ly - base) * 0.3 })
		end
		-- (a few small heaps on the bigger lumps' tops: the cauliflower edge)
		local big = #lumps
		for q = 1, 1 + math.floor(hash(s + 5) * 3) do
			local l = lumps[1 + math.floor(hash(s + 60 + q) * big) % big]
			local rx = l[3] * (0.38 + hash(s + 70 + q) * 0.18)
			table.insert(lumps, { l[1] + (hash(s + 80 + q) - 0.5) * l[3] * 0.9, l[2] - l[4] * 0.66, rx, rx * 0.8, l[5] + l[4] * 0.72 })
		end
		cloud(cg, lumps, base)
	end
	return cg
end

------------------------------------------------------------------ colouring (a notch)
type Job = {
	pal: Pal,
	y: number, -- the next row to colour
	sky: buffer,
	front: buffer,
	cloud: buffer,
	lutSky: { number },
	lutFront: { number },
	lutCloud: { number },
	rowCorner: { number }, -- an outline's corner over the sky at each row
	amt: number, -- the night's 0 .. 255 (a star shows once this passes its threshold)
}

-- a group's four tones (lit, body, shade, deep) and their outlines into a table at `at` (1 .. 4, then 5 .. 8)
local function tones(lut: { number }, at: number, litC: number, body: number, shade: number, ink: number)
	local deep = mix(shade, ink, 0.2)
	local four = { litC, body, shade, deep }
	for t = 1, 4 do
		lut[at + t + 1] = packed(four[t])
		lut[at + 4 + t + 1] = packed(mix(four[t], ink, 0.34))
	end
end

local function newJob(pal: Pal, g: Geo, cg: CloudGeo): Job
	local W, H = g.W, g.H
	local night = pal.stars
	local lutSky = table.create(256, 0)
	local glow = math.min(1, night * 1.4)
	for st = 0, 4 do
		for mk = 0, 3 do
			for band = 0, 5 do
				local c = pal.stops[band + 1]
				if mk > 0 then
					c = mix(c, MILKY, mk * 0.12 * night)
				end
				if st == 1 then
					c = mix(c, 0xFFFFFF, 0.42 * glow)
				elseif st == 2 then
					c = mix(c, 0xFFFFFF, 0.8 * glow)
				elseif st == 3 then
					c = mix(c, 0xFFFFFF, glow)
				elseif st == 4 then
					c = mix(c, 0xFFFFFF, 0.48 * glow)
				end
				lutSky[band + mk * 8 + st * 32 + 1] = packed(c)
			end
		end
	end
	local rowCorner = table.create(H, 0)
	for y = 0, H - 1 do
		rowCorner[y + 1] = packed(mix(meanAt(pal, y, H), pal.ink, 0.15))
	end
	local lutFront = table.create(256, 0)
	local wx = pal.wx
	for j, isle in g.isles do
		local back = meanAt(pal, isle[2], H)
		local fade = math.min(0.9, isle[4] + wx.fade)
		local base = (j - 1) * ISLE_TONES
		for v = 1, ISLE_TONES - 1 do
			lutFront[base + v + 1] = packed(mix(weathered(lit(ISLE[v], pal.light), wx), back, fade))
		end
		lutFront[base + ISLE_TONES + 1] = packed(mix(mix(weathered(lit(ISLE[7], pal.light), wx), back, fade), pal.ink, 0.4))
	end
	local bottom = pal.stops[6]
	for r = 0, 2 do
		local f = math.min(0.85, SEA_FADE[r + 1] + wx.fade * 0.5)
		tones(lutFront, 64 + r * 16, mix(pal.lit, bottom, f), mix(pal.body, bottom, f), mix(pal.shade, bottom, f), mix(pal.ink, bottom, f * 0.5))
	end
	local lutCloud = table.create(10, 0)
	tones(lutCloud, 0, pal.lit, pal.body, pal.shade, pal.ink)
	return {
		pal = pal,
		y = 0,
		sky = buffer.create(W * H * 4),
		front = buffer.create(W * H * 4),
		cloud = buffer.create(cg.W * cg.H * 4),
		lutSky = lutSky,
		lutFront = lutFront,
		lutCloud = lutCloud,
		rowCorner = rowCorner,
		amt = math.floor(night * 255),
	}
end

-- Rows y0 .. y1 of the three pictures in the job's colours.
local function colourRows(job: Job, g: Geo, cg: CloudGeo, y0: number, y1: number)
	local W = g.W
	local amt = job.amt
	local lutSky, lutFront, lutCloud = job.lutSky, job.lutFront, job.lutCloud
	local gs, gt, gf, gc = g.sky, g.thr, g.front, cg.cloud
	local os_, of, oc = job.sky, job.front, job.cloud
	for y = y0, y1 do
		local rc = job.rowCorner[y + 1]
		local row = y * W
		for x = 0, W - 1 do
			local i = row + x
			local c = buffer.readu8(gs, i)
			if c >= 32 and buffer.readu8(gt, i) >= amt then
				c = bit32.band(c, 31)
			end
			buffer.writeu32(os_, i * 4, lutSky[c + 1])
			local f = buffer.readu8(gf, i)
			if f ~= 0 then
				buffer.writeu32(of, i * 4, if f >= 64 and (f - 64) % 16 == 9 then rc else lutFront[f + 1])
			end
			local cl = buffer.readu8(gc, i)
			if cl ~= 0 then
				buffer.writeu32(oc, i * 4, if cl == 9 then rc else lutCloud[cl + 1])
			end
		end
	end
	job.y = y1 + 1
end

-- The three pictures for a weather (Data/Weather id) at W x H art px and the sky's hour (now when nil): RGBA buffers,
-- the front's and the clouds' empty pixels clear.
function SkyBackdrop.paint(kind: string, W: number, H: number, hour: number?): (buffer, buffer, buffer)
	local wx = WX[kind] or CLEAR
	local g, cg = buildGeo(W, H), buildClouds(W, H, wx.clouds)
	local job = newJob(paletteAt(hour or DayLight.skyHour(), kind), g, cg)
	colourRows(job, g, cg, 0, H - 1)
	return job.sky, job.front, job.cloud
end

------------------------------------------------------------------ the sun and the moon
local MOON_BITE: { number } = { 0, 1.45, 0.95, 0.55, -0.55, -0.95, -1.45, 0 } -- the shadow's offset each night (0: full)
local CRATERS: { { number } } = { { -0.3, -0.2, 0.22 }, { 0.25, 0.3, 0.17 }, { 0.35, -0.35, 0.12 } }

-- A body's picture (RGBA, S x S, its middle at S / 2): a flat disc with anti-aliased edges over a halo of dithered
-- rings. The sun: low 0 .. 1 (near the horizon: a wider, warmer glow); the moon: phase 1 .. 8.
local function paintBody(isSun: boolean, r: number, low: number, phase: number): (buffer, number)
	local reach = if isSun then 2.1 + 1.4 * low else 2
	local S = 2 * math.ceil(r * reach) + 3
	local mid = S / 2
	local fill = if isSun then mix(0xFFF7DA, 0xFFC97E, low) else 0xF6F2DE
	local halo = if isSun then mix(0xFFF0BE, 0xFFAA6A, low) else 0xC9D6FF
	local levels = if isSun then 2 + math.floor(low * 1.99) else 2
	local stepA = if isSun then 0.15 else 0.09
	local bite = if isSun then 0 else MOON_BITE[((phase - 1) % 8) + 1]
	local buf = buffer.create(S * S * 4)
	for y = 0, S - 1 do
		for x = 0, S - 1 do
			local dx, dy = x + 0.5 - mid, y + 0.5 - mid
			local d = math.sqrt(dx * dx + dy * dy)
			local cover = math.clamp(r + 0.5 - d, 0, 1)
			if bite ~= 0 then
				local d2 = math.sqrt((dx - bite * r) ^ 2 + (dy + r * 0.12) ^ 2)
				cover = math.min(cover, math.clamp(d2 - r * 0.98 + 0.5, 0, 1))
			end
			local af = if cover >= 0.75 then 1 elseif cover >= 0.25 then 0.5 else 0
			local ah = 0
			local q = d / r
			if q > 0.9 and q < reach then
				local k = (reach - q) / (reach - 1)
				ah = math.min(0.5, math.max(0, math.floor(k * levels + bay(x, y))) * stepA)
			end
			local col = fill
			if not isSun and af > 0 then
				for _, cr in CRATERS do
					if (dx / r - cr[1]) ^ 2 + (dy / r - cr[2]) ^ 2 < cr[3] * cr[3] then
						col = 0xDCD5BE
					end
				end
			end
			local a = af + ah * (1 - af)
			if a > 0 then
				local c = if af >= 1 then col else mix(halo, col, af / a)
				buffer.writeu32(buf, (y * S + x) * 4, packed(c, a))
			end
		end
	end
	return buf, S
end

-- Where a body is at u (0 rising, 0.5 its height, 1 setting) on a W x H sky: its middle, art px.
local function arc(u: number, W: number, H: number, r: number): (number, number)
	local hy = H * HORIZON
	local top = H * 0.14
	local s = math.sin(math.pi * math.clamp(u, -0.12, 1.12))
	return W * (0.1 + 0.8 * u), hy - (hy - top) * s
end

------------------------------------------------------------------ on screen
type Body = { label: ImageLabel?, image: EditableImage?, key: string, S: number, x: number, y: number, shown: boolean }
type Bird = { x: number, y: number, vx: number, ph: number, px: { Frame } }
type Twinkle = { f: Frame, ph: number, rate: number }
type Streak = { x: number, y: number, age: number, px: { Frame } }

local gui: ScreenGui? = nil
local skyLabel: ImageLabel? = nil
local frontLabels: { ImageLabel } = {}
local cloudLabels: { ImageLabel } = {}
local lifeLayer: Frame? = nil
local skyImage: EditableImage? = nil
local frontImage: EditableImage? = nil
local cloudImage: EditableImage? = nil
local geo: Geo? = nil
local cgeo: CloudGeo? = nil
local job: Job? = nil
local sun: Body = { key = "", S = 0, x = 0, y = 0, shown = false }
local moon: Body = { key = "", S = 0, x = 0, y = 0, shown = false }
local birds: { Bird } = {}
local twinkles: { Twinkle } = {}
local streak: Streak? = nil
local streakAt, birdsAt = 0, 0
local lifeClock = 0
local shown = { kind = "", key = "", W = 0, H = 0, K = 0, off = -1, seaOff = -1, paints = 0, geos = 0, stars = 0, ink = 0x3A5E8C }
local started = false

local function label(parent: Instance, name: string, z: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.ZIndex = z
	l.Parent = parent
	return l
end

local function ensureGui(): ScreenGui
	local g = gui
	if g then
		return g
	end
	local ng = Instance.new("ScreenGui")
	ng.Name = "SkyBackdrop"
	ng.IgnoreGuiInset = true
	ng.ScreenInsets = Enum.ScreenInsets.None
	ng.DisplayOrder = Tuning.PixelDisplayOrder - 3 -- (behind the hatch scene's backdrop and the pixel layer)
	ng.ResetOnSpawn = false
	skyLabel = label(ng, "Sky", 1)
	local sl, ml = label(ng, "Sun", 2), label(ng, "Moon", 2)
	sl.Visible, ml.Visible = false, false
	sun.label, moon.label = sl, ml
	frontLabels = { label(ng, "FarA", 3), label(ng, "FarB", 3) }
	cloudLabels = { label(ng, "CloudsA", 4), label(ng, "CloudsB", 4) }
	local lay = Instance.new("Frame")
	lay.Name = "Life"
	lay.BackgroundTransparency = 1
	lay.BorderSizePixel = 0
	lay.Size = UDim2.fromScale(1, 1)
	lay.ZIndex = 5
	lay.Parent = ng
	lifeLayer = lay
	ng.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = ng
	return ng
end

local function sized(im: EditableImage?, W: number, H: number, who: string): EditableImage?
	if im and im.Size.X == W and im.Size.Y == H then
		return im
	end
	if im then
		im:Destroy()
	end
	return ImageMemory.create(W, H, who)
end

-- A finished notch on screen: the three pictures uploaded at once.
local function finish(j: Job, g: Geo)
	local si, fi, ci = skyImage, frontImage, cloudImage
	if si == nil or fi == nil or ci == nil then
		return
	end
	local size = Vector2.new(g.W, g.H)
	pcall(function()
		(si :: EditableImage):WritePixelsBuffer(Vector2.zero, size, j.sky);
		(fi :: EditableImage):WritePixelsBuffer(Vector2.zero, size, j.front);
		(ci :: EditableImage):WritePixelsBuffer(Vector2.zero, size, j.cloud)
	end)
	shown.key = j.pal.key
	shown.stars = j.pal.stars
	shown.ink = j.pal.ink
	shown.paints += 1
end

-- New shapes for a screen size: the images sized, the labels laid out, the notch painted now.
local function rebuild(W: number, H: number, K: number, clouds: number, pal: Pal)
	ensureGui()
	skyImage = sized(skyImage, W, H, "sky")
	frontImage = sized(frontImage, W, H, "sky far")
	cloudImage = sized(cloudImage, W, H, "sky clouds")
	local si, fi, ci = skyImage, frontImage, cloudImage
	if si == nil or fi == nil or ci == nil then
		return
	end
	local g, cg = buildGeo(W, H), buildClouds(W, H, clouds)
	geo, cgeo = g, cg
	shown.geos += 1
	local sl = skyLabel :: ImageLabel
	sl.ImageContent = Content.fromObject(si)
	sl.Size = UDim2.fromOffset(W * K, H * K)
	for _, l in frontLabels do
		l.ImageContent = Content.fromObject(fi)
		l.Size = UDim2.fromOffset(W * K, H * K)
	end
	for _, l in cloudLabels do
		l.ImageContent = Content.fromObject(ci)
		l.Size = UDim2.fromOffset(W * K, H * K)
	end
	shown.W, shown.H, shown.K, shown.off, shown.seaOff = W, H, K, -1, -1
	sun.key, moon.key = "", ""
	local j = newJob(pal, g, cg)
	colourRows(j, g, cg, 0, H - 1)
	finish(j, g)
	job = nil
end

-- The sun or the moon at u on its arc (hidden when it is well below the horizon), its picture painted again when its
-- colour or phase moves on.
local function placeBody(b: Body, isSun: boolean, u: number, phase: number, veil: number, W: number, H: number, K: number)
	local l = b.label
	if l == nil then
		return
	end
	if u < -0.06 or u > 1.06 then
		if b.shown then
			l.Visible = false
			b.shown = false
		end
		return
	end
	local r = math.clamp(math.floor(H * 0.05), 6, 16)
	if not isSun then
		r = math.max(5, math.floor(r * 0.85))
	end
	local low = 0
	if isSun then
		low = math.floor(math.clamp(1 - math.sin(math.pi * math.clamp(u, 0, 1)) / 0.5, 0, 1) * 5 + 0.5) / 5
	end
	local k = string.format("%d:%.1f:%d", r, low, phase)
	if k ~= b.key then
		local buf, S = paintBody(isSun, r, low, phase)
		local im = b.image
		if im == nil or b.S ~= S then
			if im then
				im:Destroy()
			end
			im = ImageMemory.create(S, S, if isSun then "sky sun" else "sky moon")
			b.image = im
			if im then
				l.ImageContent = Content.fromObject(im)
			end
		end
		if im == nil then
			return
		end
		pcall(function()
			(im :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(S, S), buf)
		end)
		b.key, b.S = k, S
		l.Size = UDim2.fromOffset(S * K, S * K)
		b.x = -1e9
	end
	local cx, cy = arc(u, W, H, r)
	local x, y = math.floor(cx - b.S / 2 + 0.5), math.floor(cy - b.S / 2 + 0.5)
	if x ~= b.x or y ~= b.y then
		b.x, b.y = x, y
		l.Position = UDim2.fromOffset(x * K, y * K)
	end
	l.ImageTransparency = veil
	if not b.shown then
		l.Visible = true
		b.shown = true
	end
end

-- The sky's life: one pixel (K x K screen px) of a solid colour.
local function pixel(c: number): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.fromRGB(rgb(c))
	f.Size = UDim2.fromOffset(shown.K, shown.K)
	f.ZIndex = 5
	f.Parent = lifeLayer
	return f
end
local function put(f: Frame, x: number, y: number)
	f.Position = UDim2.fromOffset(math.floor(x) * shown.K, math.floor(y) * shown.K)
end
local WINGS: { { { number } } } = {
	{ { 0, 0 }, { 4, 0 }, { 1, 1 }, { 3, 1 }, { 2, 2 } },
	{ { 0, 1 }, { 1, 1 }, { 3, 1 }, { 4, 1 }, { 2, 2 } },
}
local TAIL: { number } = { 0xFFFFFF, 0xE6E4FF, 0xB9B6E8, 0x8C88C6, 0x6A649E }

local function clearLife()
	for _, b in birds do
		for _, f in b.px do
			f:Destroy()
		end
	end
	table.clear(birds)
	for _, t in twinkles do
		t.f:Destroy()
	end
	table.clear(twinkles)
	local st = streak
	if st then
		for _, f in st.px do
			f:Destroy()
		end
	end
	streak = nil
end

local function stepLife(dt: number, W: number, H: number, wx: Wx)
	if lifeLayer == nil then
		return
	end
	lifeClock += dt
	local night = shown.stars
	-- twinkling stars: a few bright pixels that come and go once the night is well in
	if #twinkles == 0 then
		for i = 1, 16 do
			local f = pixel(if i % 3 == 0 then 0xFFF4C8 else 0xFFFFFF)
			put(f, hash(i * 41 + 3) * W, hash(i * 59 + 1) * H * 0.55)
			f.Visible = false
			table.insert(twinkles, { f = f, ph = hash(i * 7) * 6.28, rate = 1.5 + hash(i * 13) * 2.5 })
		end
	end
	for i, tw in twinkles do
		tw.f.Visible = night > 0.35 + (i % 4) * 0.12 and math.sin(lifeClock * tw.rate + tw.ph) > -0.2
	end
	-- a shooting star now and then on a clear night: a bright head and a tail fading in steps
	local st = streak
	if st == nil and night > 0.6 and lifeClock >= streakAt then
		local px: { Frame } = {}
		for _, c in TAIL do
			table.insert(px, pixel(c))
		end
		streak = { x = W * (0.3 + math.random() * 0.6), y = H * (0.04 + math.random() * 0.2), age = 0, px = px }
		streakAt = lifeClock + 5 + math.random() * 8
	elseif st then
		st.age += dt
		local hx, hy = st.x - st.age * 90, st.y + st.age * 45
		for i, f in st.px do
			put(f, hx + (i - 1) * 2, hy - (i - 1))
		end
		if st.age >= 0.7 then
			for _, f in st.px do
				f:Destroy()
			end
			streak = nil
		end
	end
	-- birds: a little flock now and then by day, flapping across the upper sky
	if #birds == 0 and night < 0.2 and wx.k < 0.6 and lifeClock >= birdsAt then
		birdsAt = lifeClock + 18 + math.random() * 22
		local fromLeft = math.random() < 0.5
		local y0 = H * (0.1 + math.random() * 0.3)
		for k = 1, math.random(2, 5) do
			local dx = (k - 1) * 7 + math.random(0, 3)
			local dy = (if k % 2 == 0 then 1 else -1) * math.floor(k / 2) * 3
			local px: { Frame } = {}
			for _ = 1, 5 do
				table.insert(px, pixel(shown.ink))
			end
			table.insert(birds, { x = if fromLeft then -6 - dx else W + dx, y = y0 + dy, vx = (if fromLeft then 1 else -1) * (12 + math.random() * 4), ph = math.random() * 6.28, px = px })
		end
	end
	local keep: { Bird } = {}
	for _, b in birds do
		b.x += b.vx * dt
		b.y += math.sin(lifeClock * 1.3 + b.ph) * dt * 2
		if b.x < -14 or b.x > W + 14 then
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
end

local function step(dt: number)
	-- (only behind the pixel filter's picture: in the classic style, or with no picture at all, the world itself shows
	-- and a screen-wide sky would hide it)
	local gg = gui
	if not PixelRenderer.isActive() then
		if gg and gg.Enabled then
			gg.Enabled = false
		end
		return
	elseif gg and not gg.Enabled then
		gg.Enabled = true
	end
	local K = math.max(1, math.floor(PixelRenderer.pixelScale()))
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local W, H = math.max(1, math.ceil(vp.X / K)), math.max(1, math.ceil(vp.Y / K))
	local kind = WeatherView.kind()
	local wx = WX[kind] or CLEAR
	local hour = DayLight.skyHour()
	local pal = paletteAt(hour, kind)
	local g = geo
	if g == nil or g.W ~= W or g.H ~= H or K ~= shown.K then
		if K ~= shown.K then
			clearLife()
		end
		rebuild(W, H, K, wx.clouds, pal)
		g = geo
		shown.kind = kind
	end
	local cg = cgeo
	if g == nil or cg == nil or shown.paints == 0 then
		return
	end
	-- another weather's clouds: their shapes now, shown with the next notch (the weather is in its key)
	if cg.clouds ~= wx.clouds then
		cg = buildClouds(W, H, wx.clouds)
		cgeo = cg
		job = nil
		shown.geos += 1
	end
	-- a new notch: coloured a few rows a frame, shown once whole
	if pal.key ~= shown.key then
		local cur = job
		local j: Job = if cur ~= nil and cur.pal.key == pal.key then cur else newJob(pal, g, cg)
		job = j
		local rows = math.max(8, math.floor(ROW_PIXELS / g.W))
		colourRows(j, g, cg, j.y, math.min(g.H - 1, j.y + rows - 1))
		if j.y >= g.H then
			finish(j, g)
			job = nil
			shown.kind = kind
		end
	end
	-- the sun and the moon
	local day = SUNSET - SUNRISE
	placeBody(sun, true, (hour - SUNRISE) / day, 0, wx.veil, W, H, K)
	placeBody(moon, false, ((hour - SUNSET) % 1) / (1 - day), (DayLight.skyNight() % 8) + 1, wx.veil, W, H, K)
	-- the clouds and the far things drifting, sliding with the view
	local panX = CameraController.pan()
	local now = os.clock()
	local off = math.floor(now / DRIFT - panX * PARALLAX) % W
	if off ~= shown.off then
		shown.off = off
		local a, b = cloudLabels[1], cloudLabels[2]
		if a and b then
			a.Position = UDim2.fromOffset((off - W) * K, 0)
			b.Position = UDim2.fromOffset(off * K, 0)
		end
	end
	local seaOff = math.floor(now / SEA_DRIFT - panX * FAR_PARALLAX) % W
	if seaOff ~= shown.seaOff then
		shown.seaOff = seaOff
		local a, b = frontLabels[1], frontLabels[2]
		if a and b then
			a.Position = UDim2.fromOffset((seaOff - W) * K, 0)
			b.Position = UDim2.fromOffset(seaOff * K, 0)
		end
	end
	stepLife(dt, W, H, wx)
end

function SkyBackdrop.start()
	if started then
		return
	end
	started = true
	step(0)
	RunService.Heartbeat:Connect(step)
end

-- What the sky's work costs at W x H (previews, with their own clock): the shapes, a weather's clouds and one notch,
-- in ms.
function SkyBackdrop.debugTimes(W: number, H: number, clock: (() -> number)?): (number, number, number)
	local now = clock or os.clock
	local t0 = now()
	local g = buildGeo(W, H)
	local t1 = now()
	local cg = buildClouds(W, H, CLEAR.clouds)
	local t2 = now()
	local j = newJob(paletteAt(0.5, "sunny"), g, cg)
	colourRows(j, g, cg, 0, H - 1)
	local t3 = now()
	return (t1 - t0) * 1000, (t2 - t1) * 1000, (t3 - t2) * 1000
end

-- Hold the sky at an hour and a night (the moon's phase) for the previews and sims; nil: the clock again.
function SkyBackdrop.debugHour(h: number?, night: number?)
	DayLight.debugSky(h, night)
end

export type DebugState = {
	on: boolean,
	kind: string,
	key: string,
	W: number,
	H: number,
	paints: number,
	geos: number,
	pending: boolean,
	off: number,
	seaOff: number,
	hour: number,
	stars: number,
	sun: boolean,
	sunX: number,
	sunY: number,
	moon: boolean,
	moonX: number,
	moonY: number,
	birds: number,
	twinkles: number,
	streak: boolean,
}

-- What shows now (previews and sims): whether it shows (only behind the pixel filter), the weather and notch painted, the picture's size, how many notches were
-- painted and shapes built, a notch under way, the clouds' and the far things' offsets, the hour, how much of the
-- night shows, the sun and the moon (shown, their top left in art px), the birds, twinkles and a shooting star.
function SkyBackdrop.debugState(): DebugState
	local tw = 0
	for _, t in twinkles do
		if t.f.Visible then
			tw += 1
		end
	end
	local g = gui
	return {
		on = g ~= nil and g.Enabled,
		kind = shown.kind,
		key = shown.key,
		W = shown.W,
		H = shown.H,
		paints = shown.paints,
		geos = shown.geos,
		pending = job ~= nil,
		off = shown.off,
		seaOff = shown.seaOff,
		hour = DayLight.skyHour(),
		stars = shown.stars,
		sun = sun.shown,
		sunX = sun.x,
		sunY = sun.y,
		moon = moon.shown,
		moonX = moon.x,
		moonY = moon.y,
		birds = #birds,
		twinkles = tw,
		streak = streak ~= nil,
	}
end

return SkyBackdrop
