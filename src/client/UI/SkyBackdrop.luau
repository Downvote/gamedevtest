--!strict
--!native
-- The sky round the floating islands (GAME_DESIGN 2 and 8; docs/ARCHITECTURE.md 10.19): the requests of 2026-11-20,
-- "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the island bigger.", "polish the
-- skybox more. it should be of the same quality as the ones in the egg hatching screen, with day and night cycles with
-- moon and sun rising", then with two reference pictures "no need to make the clouds so detailed with outlines, just
-- simple shapes and color is enough. make variations to them as well", "same with the floating islands, they should be
-- sillouhetted instead" and "make the sea of clouds a more fluffy connected mass of clouds that arent just circles.
-- Remove the clouds that appear in the background". Painted pixel by pixel at the world's art grid (each art pixel
-- K x K screen px, like the pixel layer) on a ScreenGui behind the pixel layer: the islands' sky is see-through
-- (CameraController's view `clear`), so they float in front of it. Back to front:
-- * the sky: bands of colour from the top down, each blending into the next in a wide ordered dither; at night stars
--   (single pixels in two strengths and little blue, gold or white crosses, coming out one by one as it darkens, the
--   brightest first) and the band of the galaxy slanting across, a lane of dust down its middle;
-- * the sun and the moon on their arcs: each rises from behind the sea of clouds on the left, climbs and sets on the
--   right, one flat tone with anti-aliased edges in a halo of dithered rings (the sun a big pale disc near the
--   horizon); the moon has craters and a phase that changes every night (full, gibbous, half and a crescent, waning
--   then waxing; never dark);
-- * far islets as silhouettes in the haze and the sea of clouds along the bottom: five ridges of billowing cloud, each
--   one flat colour, the farther ones fainter; it repeats across, drifts slowly and slides a sixteenth of the view's
--   pan (no clouds drift across the sky since the request above);
-- * the sky's life: little flocks of birds flapping across by day, stars twinkling and now and then a shooting star at
--   night (whole art px, solid colours).
-- The time of day (`DayLight.skyHour`, the sea's clock round `Tuning.SkyDaySecs`) picks the colours from the day's keys
-- (night, the first light, sunrise, morning, day, the afternoon, sunset, dusk; the night, dawn and sunset in one of
-- three VARIANTS a day), stepped NOTCHES times between two keys; the weather (WX) pulls them toward its own grey, hides
-- the stars and veils the sun and the moon in rain, storm and fog. The shapes are worked out once for a screen size
-- (`buildGeo`: a class a pixel); a new notch only colours them again from small tables, a few rows a frame, and uploads
-- the two pictures once done, so the sky never stalls a frame.
--   start(), paint(kind, W, H, hour?, variant?) -> (sky, front)  the two pictures (RGBA, W x H; the front clear where
--       empty), debugState(), debugHour(h?, night?) (hold the sky at an hour: DayLight.debugSky), debugTimes(W, H, clock?)
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

local SEA_DRIFT = 6 -- s a pixel the sea of clouds and the far islets drift right
local FAR_PARALLAX = 1 / 16 -- of the view's pan the sea of clouds and the far islets slide with
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
	lit: number, -- the clouds: the rim along their tops, their body, their underside, and the hour's dark (`ink`:
	body: number, -- the far islets lean toward it, the birds are drawn in it)
	shade: number,
	ink: number,
	light: number, -- (kept for the far islets' light)
	stars: number, -- how much of the night shows (0 .. 1): the stars, the galaxy
}

local function K(name: string, stops: { number }, litC: number, body: number, shade: number, ink: number, light: number, stars: number): Key
	return { name = name, h = 0, stops = stops, lit = litC, body = body, shade = shade, ink = ink, light = light, stars = stars }
end

-- the day's own keys, the same every day (so a day's variation can change at noon without a jump)
local MORNING = K("morning", { 0x62AAE4, 0x78B8EB, 0x90C6F0, 0xAAD3F3, 0xC8E1F2, 0xE8ECEA }, 0xFFFFFF, 0xF2F2F6, 0xD6D8EA, 0x3E5A8C, 0xFFF6EE, 0)
local DAY = K("day", { 0x6DB7EA, 0x80C3EF, 0x94CFF4, 0xA8DAF7, 0xBDE4FA, 0xD3EEFB }, 0xFFFFFF, 0xEEF5FD, 0xCADDF0, 0x3A5E8C, 0xFFFFFF, 0)
local AFTERNOON = K("afternoon", { 0x6AB0E2, 0x82BCE8, 0x9DC8EA, 0xBAD4E8, 0xDADCDC, 0xF4E4CA }, 0xFFFDF4, 0xF6ECE6, 0xDDD0DA, 0x485A86, 0xFFF4E4, 0)

-- The night, the first light, sunrise, sunset and dusk come in three variations, one a day (the request of 2026-11-20
-- with a city's night under purple cloud banks and a desert's sunset: "use these landscapes as reference ... make
-- variations to them as well"): { night, first light, sunrise, sunset, dusk }.
local VARIANTS: { { Key } } = {
	-- a deep blue night under purple banks lit magenta at their rims; a peach dawn; a rose and gold sunset
	{
		K("night1", { 0x060920, 0x0B1132, 0x11194A, 0x192364, 0x242C80, 0x343698 }, 0xA048C0, 0x4C2C8E, 0x30205E, 0x08061A, 0x5A5CA8, 1),
		K("first1", { 0x0E1440, 0x1A1E58, 0x2C2A70, 0x463486, 0x6A4496, 0x9058A0 }, 0xC070C0, 0x6A4A9A, 0x48367A, 0x120E30, 0x7468A8, 0.7),
		K("sunrise1", { 0x5E70B8, 0x8A84C0, 0xBE94BC, 0xEAA6AC, 0xF8C0A0, 0xFDDCA8 }, 0xFFF0D8, 0xFAD4C4, 0xD8A8B8, 0x5A4A7A, 0xFFD8C4, 0.1),
		K("sunset1", { 0xE46A8C, 0xEE8486, 0xF5A07E, 0xF9BA7E, 0xFBCF8A, 0xFCE0A2 }, 0xFFF2C8, 0xFAD8A2, 0xF0B282, 0x8A4A5A, 0xFFD0A8, 0.05),
		K("dusk1", { 0x1E1C52, 0x30286C, 0x4A3484, 0x6A3E94, 0x92489C, 0xB85A9C }, 0xC864B4, 0x6A3E94, 0x46306E, 0x140E2C, 0x8A70AA, 0.55),
	},
	-- a lavender night under blue-grey banks; a lilac dawn; a pink and violet sunset
	{
		K("night2", { 0x141838, 0x1A2048, 0x222A5A, 0x2C366C, 0x38447E, 0x48548E }, 0x8E98CC, 0x5C6698, 0x424A7A, 0x0E1230, 0x6670A8, 1),
		K("first2", { 0x1E2250, 0x2A2E64, 0x3C3C7A, 0x52498C, 0x70589C, 0x9468A8 }, 0xA89CCC, 0x7A70A6, 0x5A5488, 0x161838, 0x7E78B0, 0.75),
		K("sunrise2", { 0x4456A0, 0x6466B0, 0x9078BA, 0xC888B8, 0xF2A2A2, 0xFFCB92 }, 0xFFE4C8, 0xF4C0C4, 0xBC98BC, 0x4C3C70, 0xFFD2BE, 0.12),
		K("sunset2", { 0x4C549A, 0x7060AA, 0xA66CB0, 0xDA7AA2, 0xF89C88, 0xFFC47C }, 0xFFD8A6, 0xF2AAAA, 0xB880A8, 0x40305E, 0xFFC8B0, 0.08),
		K("dusk2", { 0x252A5E, 0x313672, 0x444284, 0x5C4E94, 0x7C5CA0, 0x9E6EA8 }, 0xB8A0CC, 0x8274AA, 0x5E5688, 0x1A1A3A, 0x8A80B4, 0.6),
	},
	-- a sea-blue night under slate banks; a golden dawn; an ember-red sunset
	{
		K("night3", { 0x08142A, 0x0C1C38, 0x122848, 0x18345A, 0x20426C, 0x2C527C }, 0x5A8CB0, 0x2C4C70, 0x1E3452, 0x060E1C, 0x5A7898, 1),
		K("first3", { 0x142446, 0x22345A, 0x3A4A6E, 0x5C607C, 0x8A7A84, 0xB49488 }, 0xD8B0A0, 0x8A7A8C, 0x5E5A74, 0x14182C, 0x8A8498, 0.65),
		K("sunrise3", { 0x7898C8, 0xA0A8C8, 0xCCB4BC, 0xF0BCA4, 0xFCC88C, 0xFFDC90 }, 0xFFF4DC, 0xFFE0C0, 0xE8BCA4, 0x5C5470, 0xFFE0C4, 0.08),
		K("sunset3", { 0x5A3C7E, 0x8A4A86, 0xC4587C, 0xEC6E62, 0xF8925A, 0xFFB862 }, 0xFFC890, 0xF49478, 0xC46A72, 0x4A2440, 0xFFB898, 0.08),
		K("dusk3", { 0x1A2040, 0x262C56, 0x3A3466, 0x563C70, 0x7A4672, 0xA05470 }, 0xC07090, 0x6A4470, 0x463454, 0x12102A, 0x8A7096, 0.6),
	},
}

local function key(h: number, k: Key): Key
	return { name = k.name, h = h, stops = k.stops, lit = k.lit, body = k.body, shade = k.shade, ink = k.ink, light = k.light, stars = k.stars }
end

local keysCache: { [number]: { Key } } = {}
-- The keys through a day of variation v (1 .. #VARIANTS).
local function keysOf(v: number): { Key }
	local got = keysCache[v]
	if got then
		return got
	end
	local s = VARIANTS[((v - 1) % #VARIANTS) + 1]
	local night, first, up, down, dusk = s[1], s[2], s[3], s[4], s[5]
	local list = {
		key(0, night),
		key(0.15, night),
		key(0.2, first),
		key(0.235, up),
		key(0.29, MORNING),
		key(0.36, DAY),
		key(0.64, DAY),
		key(0.71, AFTERNOON),
		key(0.765, down),
		key(0.8, dusk),
		key(0.86, night),
		key(1, night),
	}
	keysCache[v] = list
	return list
end

-- Today's variation: the night's count (DayLight.skyNight, which turns at noon, in the day's own colours).
local function variantNow(): number
	return (DayLight.skyNight() % #VARIANTS) + 1
end

------------------------------------------------------------------ the weather
type Wx = {
	tint: number, -- the grey it pulls every colour toward (at the colour's own lightness)
	k: number, -- how far
	dark: number, -- that grey's lightness times this
	veil: number, -- how veiled the sun and the moon are (their transparency)
	fade: number, -- how much further the far islets and the far ridges of cloud fade into the sky
}
local CLEAR: Wx = { tint = 0xFFFFFF, k = 0, dark = 1, veil = 0, fade = 0 }
local WX: { [string]: Wx } = {
	sunny = CLEAR,
	blossom = CLEAR,
	leaves = CLEAR,
	breezy = { tint = 0xFFFFFF, k = 0, dark = 1, veil = 0, fade = 0 },
	rain = { tint = 0x8C9AAE, k = 0.55, dark = 0.9, veil = 0.55, fade = 0.1 },
	storm = { tint = 0x58627C, k = 0.72, dark = 0.72, veil = 0.85, fade = 0.15 },
	fog = { tint = 0xC6D0DA, k = 0.62, dark = 1.08, veil = 0.6, fade = 0.25 },
	snow = { tint = 0xBCCCDE, k = 0.45, dark = 1.04, veil = 0.4, fade = 0.1 },
	haze = { tint = 0xEED8B0, k = 0.3, dark = 1, veil = 0.15, fade = 0.1 },
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

-- The colours at the sky's hour h in a weather on a day of variation v, stepped to the notch.
local function paletteAt(h: number, kind: string, v: number): Pal
	local wx = WX[kind] or CLEAR
	local keys = keysOf(v)
	h = h % 1
	local i = 1
	while i < #keys - 1 and keys[i + 1].h <= h do
		i += 1
	end
	local a, b = keys[i], keys[i + 1]
	local n = math.floor((h - a.h) / math.max(1e-6, b.h - a.h) * NOTCHES + 0.5)
	if a.stops == b.stops then
		n = 0
	end
	if n >= NOTCHES then
		a, n = b, 0
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

-- The sky's band rows: at row y the stop above (0-based) and how far toward the next (the dither's share: most of
-- each band blends into the next in an ordered dither, like a pixel artist's sky).
local function bandOf(y: number, H: number): (number, number)
	local t = math.clamp(y / math.max(1, H * BANDS_TO), 0, 1) * 5
	if t >= 5 then
		return 4, 1
	end
	local i = math.min(4, math.floor(t))
	return i, math.clamp((t - i - 0.2) / 0.6, 0, 1) -- (a wide ordered dither between two bands)
end
-- the sky's mean colour at row y (what an outline or a far thing blends into)
local function meanAt(pal: Pal, y: number, H: number): number
	local i, k = bandOf(y, H)
	return mix(pal.stops[i + 1], pal.stops[i + 2], k)
end

------------------------------------------------------------------ the shapes (once a screen size)
-- The sky's class a pixel: the band (bits 0-2, 0 .. 5), the galaxy's strength (bits 3-4, 0 .. 3), a star (bits 5-7:
-- 1 dim, 2 bright, 3 a cross's white middle, 4 its white arm, 5 a blue arm, 6 a warm arm, 7 a warm middle) and the
-- star's threshold (`thr`: it shows once the night's 0 .. 255 passes it).
-- The front's: 0 clear; 1 .. 10 islet j's silhouette, (j - 1) * 2 + (1 its body, 2 the rim along its top);
-- 64 + ridge * 8 + 2: the sea of clouds (one flat colour a ridge).
type Geo = {
	W: number,
	H: number,
	sky: buffer,
	thr: buffer,
	front: buffer,
	isles: { { number } }, -- { cx, cy, w, depth (how far it leans toward the hour's dark) } each
}

local MILKY = 0xC8D2FF
local SEA_LAYERS = 5 -- the sea of clouds' ridges
local SEA_BASE: { number } = { 0.79, 0.83, 0.875, 0.92, 0.975 } -- each ridge's foot line (share of H), far to near

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
				-- (the lane of dust down its middle, fading in and out along it, never a hard edge)
				k *= 1 - 0.55 * math.clamp(1 - d / 0.22, 0, 1) * math.clamp((math.sin(x * 0.05) + 0.3) / 0.6, 0, 1)
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
		if level >= 4 and level <= 6 and cur >= 32 then
			return -- (an arm never covers another star)
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
			-- a little cross: blue, warm (a pale gold middle, red arms) or white
			local c = hash(s * 19 + 4)
			local mid, arm = 3, 4
			if c < 0.45 then
				arm = 5
			elseif c < 0.75 then
				mid, arm = 7, 6
			end
			star(x, y, mid, base * 0.4)
			star(x + 1, y, arm, base * 0.4 + 30)
			star(x - 1, y, arm, base * 0.4 + 30)
			star(x, y + 1, arm, base * 0.4 + 30)
			star(x, y - 1, arm, base * 0.4 + 30)
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

------------------------------------------------------------------ the far islets
-- A far islet as a silhouette in the haze (the request of 2026-11-20: "same with the floating islands, they should be
-- sillouhetted instead"), into the front (class (j - 1) * 2 + 1 its body, + 2 the rim along its top): a flat grass top
-- with small trees on one-pixel trunks along it (now and then a pine), a two-row cliff under its edge, a round belly
-- narrowing to a ragged point with short points hanging under it, and a few stones floating below; across the
-- picture's edge it comes in on the other side. One colour, the sky's at its height leaning toward the hour's dark
-- (the bigger, nearer ones more), its top edge a step lighter.
local function islet(g: Geo, j: number, cx: number, cy: number, w: number, seed: number)
	local W, H = g.W, g.H
	local mask: { [number]: boolean } = {}
	local function set(x: number, y: number)
		if y >= 0 and y < H then
			mask[y * W + (x % W)] = true
		end
	end
	local function rnd(n: number): number
		return hash(seed * 131 + n)
	end
	local a = w / 2
	local depth = math.floor(w * 0.45)
	-- the grass top: a flat line two rows deep, its ends rounded; under it the edge's cliff, two rows a pixel in
	for y = cy - 1, cy + 2 do
		local inset = if y == cy - 1 then 1.5 elseif y >= cy + 1 then 1 else 0
		for x = math.floor(cx - a + inset + 0.5), math.floor(cx + a - inset - 0.5) do
			set(x, y)
		end
	end
	-- the belly: rounder than a cone, narrowing to a ragged point, with a short point or two hanging under its edge
	local bot = cy + 3 + depth
	for y = cy + 3, bot do
		local f = (y - cy - 3) / math.max(1, depth)
		local half = (a - 1) * (1 - f) ^ 0.75 + (rnd(10 + y) - 0.5) * 2 - (if rnd(90 + y // 2) > 0.8 then 1 else 0)
		local lean = (rnd(70 + y // 3) - 0.5) * 1.5 * f
		if half >= 0.5 then
			for x = math.floor(cx + lean - half + 0.5), math.floor(cx + lean + half - 0.5) do
				set(x, y)
			end
		end
	end
	for k = 1, 1 + math.floor(w / 16) do
		local px = math.floor(cx + (rnd(80 + k) - 0.5) * a * 1.1)
		local y = cy + 3
		while mask[y * W + (px % W)] and y < bot + 1 do
			y += 1
		end
		for d = 0, 1 + math.floor(rnd(85 + k) * 4) do
			set(px, y + d)
			if d < 2 then
				set(px + 1, y + d)
			end
		end
	end
	-- trees on top: small round crowns on one-pixel trunks, apart from one another, now and then a pine
	local n = 1 + math.floor(w / 12)
	for k = 1, n do
		local tx = math.floor(cx - a + 3 + (k - 0.5 + (rnd(20 + k) - 0.5) * 0.6) / n * (w - 6))
		local r = math.max(1, math.floor(w / 14 + rnd(30 + k) * 1.5))
		local trunk = 1 + math.floor(rnd(35 + k) * 2)
		set(tx, cy - 2)
		for d = 1, trunk do
			set(tx, cy - 1 - d)
		end
		local foot = cy - 2 - trunk
		if w >= 18 and rnd(40 + k) > 0.65 then
			local ht = r * 3 + 1
			for dy = 0, ht do
				local hw = math.floor(dy / ht * (r + 0.5) + 0.5)
				for dx = -hw, hw do
					set(tx + dx, foot - ht + dy)
				end
			end
		else
			for dy = -r, r do
				for dx = -r, r do
					if dx * dx + dy * dy <= r * r + r * 0.5 then
						set(tx + dx, foot - r + dy)
					end
				end
			end
		end
	end
	-- stones floating below
	local tip = bot
	for k = 1, 1 + math.floor(rnd(5) * 2.5) do
		local sx = math.floor(cx + (rnd(500 + k) - 0.5) * a)
		local sy = tip + 2 + math.floor(rnd(510 + k) * 5) + k * 2
		local sw = 1 + math.floor(rnd(520 + k) * 2)
		for dx = 0, sw do
			set(sx + dx, sy)
		end
		if sw >= 2 then
			set(sx + 1, sy + 1)
		end
	end
	local base = (j - 1) * 2
	for i in mask do
		buffer.writeu8(g.front, i, base + (if i >= W and not mask[i - W] then 2 else 1))
	end
end

------------------------------------------------------------------ the sea of clouds
-- The sea of clouds (the request of 2026-11-20: "make the sea of clouds a more fluffy connected mass of clouds that
-- arent just circles"): SEA_LAYERS ridges of cloud along the bottom, far to near, each one connected mass whose top
-- edge billows: a slow swell, rounded domes of every width and squash meeting in soft notches, smaller domes heaped on
-- them, so it puffs like a cumulus instead of running in rows of circles. Every lobe wraps round the picture's width,
-- so the picture tiles. Each ridge is one flat colour, in even steps from the farthest (the clouds' shade sunk into
-- the sky) to the nearest (between the clouds' body and their lit tone).
local function seaShapes(g: Geo)
	local W, H = g.W, g.H
	local front = g.front
	for l = 0, SEA_LAYERS - 1 do
		local base = H * SEA_BASE[l + 1]
		-- the ridge's height above its base at each column: a slow swell, then rounded domes of every width and squash
		-- (the highest at each column wins, so they meet in soft notches like a cumulus), then smaller domes heaped on
		-- top of those for the fluffy edge
		local swell = table.create(W, 0)
		local big = table.create(W, 0)
		local small = table.create(W, 0)
		local function spread(into: { number }, count: number, wMin: number, wMax: number, aMin: number, aMax: number, seed: number, dome: boolean, phase: number?)
			for i = 1, count do
				local c = (i - 1 + (phase or 0) + (hash(seed + i * 3) - 0.5) * 0.7) / count * W
				local w = (wMin + hash(seed + i * 3 + 1) * (wMax - wMin)) * H
				local a = if dome then w * (aMin + hash(seed + i * 3 + 2) * (aMax - aMin)) else (aMin + hash(seed + i * 3 + 2) * (aMax - aMin)) * H
				for xx = math.floor(c - w), math.ceil(c + w) do
					local t = (xx + 0.5 - c) / w
					if t > -1 and t < 1 then
						local x = xx % W + 1
						if dome then
							into[x] = math.max(into[x], a * math.sqrt(1 - t * t))
						else
							into[x] += a * (1 - t * t) ^ 2
						end
					end
				end
			end
		end
		local s0 = 400 + l * 97
		local k = 0.6 + 0.25 * l -- (nearer ridges, bigger billows)
		spread(swell, math.max(3, math.floor(W / (H * 0.3) + 0.5)), 0.12, 0.25, 0.005, 0.02, s0, false)
		local nBig = math.max(5, math.floor(W / (H * 0.085 * k) + 0.5))
		spread(big, nBig, 0.05 * k, 0.1 * k, 0.8, 1, s0 + 1000, true)
		-- (a second row of lower billows between the big ones: the notches' bottoms stay rounded and never cut deep)
		local mid = table.create(W, 0)
		spread(mid, nBig, 0.03 * k, 0.05 * k, 0.55, 0.75, s0 + 3000, true, 0.5)
		spread(small, math.max(8, math.floor(W / (H * 0.034 * k) + 0.5)), 0.015 * k, 0.03 * k, 0.8, 1, s0 + 2000, true)
		-- (and a floor at three tenths of the nearest peak, so no notch cuts down to the ridge's foot)
		local reach = math.max(2, math.floor(H * 0.045 * k))
		local hgt = table.create(W, 0)
		for x = 1, W do
			local peak = 0
			for d = -reach, reach do
				peak = math.max(peak, big[((x - 1 + d) % W) + 1])
			end
			hgt[x] = swell[x] + math.max(big[x], mid[x], small[x] * 0.6 + big[x] * 0.85, peak * 0.3)
		end
		local top = table.create(W, 0)
		local y0 = H
		for x = 0, W - 1 do
			local t = math.floor(base - hgt[x + 1] + 0.5)
			top[x + 1] = t
			y0 = math.min(y0, t)
		end
		y0 = math.max(0, y0)
		-- (one flat colour a ridge: no edge along its top and no shading under it since the requests of 2026-11-20, "no
		-- need to make the outlines on top of each layer" and "remove the dark shading at the bottom of the sea of
		-- clouds"; the ridges part by their fade alone)
		local v = 64 + l * 8 + 2
		for x = 0, W - 1 do
			for y = math.max(0, top[x + 1]), H - 1 do
				buffer.writeu8(front, y * W + x, v)
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
	-- clouds; the bigger ones nearer, so darker
	local count = math.clamp(math.floor(W * H / 60000 + 0.5), 3, 5)
	local tries = 0
	while #g.isles < count and tries < 60 do
		tries += 1
		local s = tries * 7 + 3
		local w = 16 + math.floor(hash(s) * 26)
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
			table.insert(g.isles, { cx, cy, w, 0.16 + (w - 16) / 26 * 0.16 })
			islet(g, #g.isles, cx, cy, w, s)
		end
	end
	seaShapes(g)
	return g
end

------------------------------------------------------------------ colouring (a notch)
type Job = {
	pal: Pal,
	y: number, -- the next row to colour
	sky: buffer,
	front: buffer,
	lutSky: { number },
	lutFront: { number },
	amt: number, -- the night's 0 .. 255 (a star shows once this passes its threshold)
}

local function newJob(pal: Pal, g: Geo): Job
	local W, H = g.W, g.H
	local night = pal.stars
	local lutSky = table.create(256, 0)
	local glow = math.min(1, night * 1.4)
	for st = 0, 7 do
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
				elseif st == 5 then
					c = mix(c, 0x5A78FF, 0.75 * glow)
				elseif st == 6 then
					c = mix(c, 0xFF6A3C, 0.7 * glow)
				elseif st == 7 then
					c = mix(c, 0xFFE6A0, glow)
				end
				lutSky[band + mk * 8 + st * 32 + 1] = packed(c)
			end
		end
	end
	local lutFront = table.create(256, 0)
	local wx = pal.wx
	for j, isle in g.isles do
		local back = meanAt(pal, isle[2], H)
		local body = mix(back, pal.ink, isle[4] * (1 - wx.fade))
		lutFront[(j - 1) * 2 + 1 + 1] = packed(body)
		lutFront[(j - 1) * 2 + 2 + 1] = packed(mix(body, pal.lit, 0.3))
	end
	local bottom = pal.stops[6]
	-- the ridges, back to front: the farthest the clouds' shade sunk well into the sky's lower colours, the nearest
	-- between their body and their lit tone, the ones between in even steps, so each stands apart from the one behind
	-- it (the request of 2026-11-20: "Increase the contrast between cloud sea layers")
	local far = mix(mix(pal.shade, pal.stops[4], 0.45), bottom, math.min(0.6, 0.2 + wx.fade))
	local near = mix(pal.body, pal.lit, 0.6)
	for r = 0, SEA_LAYERS - 1 do
		lutFront[64 + r * 8 + 2 + 1] = packed(mix(far, near, r / (SEA_LAYERS - 1)))
	end
	return {
		pal = pal,
		y = 0,
		sky = buffer.create(W * H * 4),
		front = buffer.create(W * H * 4),
		lutSky = lutSky,
		lutFront = lutFront,
		amt = math.floor(night * 255),
	}
end

-- Rows y0 .. y1 of the three pictures in the job's colours.
local function colourRows(job: Job, g: Geo, y0: number, y1: number)
	local W = g.W
	local amt = job.amt
	local lutSky, lutFront = job.lutSky, job.lutFront
	local gs, gt, gf = g.sky, g.thr, g.front
	local os_, of = job.sky, job.front
	for y = y0, y1 do
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
				buffer.writeu32(of, i * 4, lutFront[f + 1])
			end
		end
	end
	job.y = y1 + 1
end

-- The two pictures for a weather (Data/Weather id) at W x H art px, the sky's hour (now when nil) and a day's variation
-- (today's when nil): RGBA buffers, the front's empty pixels clear.
function SkyBackdrop.paint(kind: string, W: number, H: number, hour: number?, variant: number?): (buffer, buffer)
	local g = buildGeo(W, H)
	local job = newJob(paletteAt(hour or DayLight.skyHour(), kind, variant or variantNow()), g)
	colourRows(job, g, 0, H - 1)
	return job.sky, job.front
end

------------------------------------------------------------------ the sun and the moon
local MOON_BITE: { number } = { 0, 1.45, 0.95, 0.55, -0.55, -0.95, -1.45, 0 } -- the shadow's offset each night (0: full)
local CRATERS: { { number } } = { { -0.3, -0.2, 0.22 }, { 0.25, 0.3, 0.17 }, { 0.35, -0.35, 0.12 } }

-- A body's picture (RGBA, S x S, its middle at S / 2): a flat disc with anti-aliased edges over a halo of dithered
-- rings. The sun: low 0 .. 1 (near the horizon: bigger, a wider and warmer glow; a pale cream disc like a painted
-- sunset's); the moon: phase 1 .. 8.
local function paintBody(isSun: boolean, r: number, low: number, phase: number): (buffer, number)
	local reach = if isSun then 1.9 + 0.9 * low else 2
	local S = 2 * math.ceil(r * reach) + 3
	local mid = S / 2
	local fill = if isSun then mix(0xFFF9E2, 0xFFF0C4, low) else 0xF6F2DE
	local halo = if isSun then mix(0xFFF4CC, 0xFFC890, low) else 0xC9D6FF
	local levels = if isSun then 1 + math.floor(low * 1.99) else 2
	local stepA = if isSun then 0.13 else 0.09
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
-- (everything is laid out in art pixels on this frame, its UIScale the pixel size K: Roblox keeps an Offset whole, so
-- W * K units given as an offset lost its fraction when K was fitted to a screen scaled by 125%)
local canvas: Frame? = nil
local canvasScale: UIScale? = nil
local skyLabel: ImageLabel? = nil
local frontLabels: { ImageLabel } = {}
local lifeLayer: Frame? = nil
local skyImage: EditableImage? = nil
local frontImage: EditableImage? = nil
local geo: Geo? = nil
local job: Job? = nil
local sun: Body = { key = "", S = 0, x = 0, y = 0, shown = false }
local moon: Body = { key = "", S = 0, x = 0, y = 0, shown = false }
local birds: { Bird } = {}
local twinkles: { Twinkle } = {}
local streak: Streak? = nil
local streakAt, birdsAt = 0, 0
local lifeClock = 0
local shown = { kind = "", key = "", W = 0, H = 0, K = 0, seaOff = -1, paints = 0, geos = 0, stars = 0, ink = 0x3A5E8C }
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
	local cv = Instance.new("Frame")
	cv.Name = "Canvas"
	cv.BackgroundTransparency = 1
	cv.BorderSizePixel = 0
	cv.Size = UDim2.fromOffset(1, 1)
	cv.Parent = ng
	local sc = Instance.new("UIScale")
	sc.Scale = 1
	sc.Parent = cv
	canvas, canvasScale = cv, sc
	skyLabel = label(cv, "Sky", 1)
	local sl, ml = label(cv, "Sun", 2), label(cv, "Moon", 2)
	sl.Visible, ml.Visible = false, false
	sun.label, moon.label = sl, ml
	frontLabels = { label(cv, "FarA", 3), label(cv, "FarB", 3) }
	local lay = Instance.new("Frame")
	lay.Name = "Life"
	lay.BackgroundTransparency = 1
	lay.BorderSizePixel = 0
	lay.Size = UDim2.fromScale(1, 1)
	lay.ZIndex = 5
	lay.Parent = cv
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

-- A finished notch on screen: the two pictures uploaded at once.
local function finish(j: Job, g: Geo)
	local si, fi = skyImage, frontImage
	if si == nil or fi == nil then
		return
	end
	local size = Vector2.new(g.W, g.H)
	pcall(function()
		(si :: EditableImage):WritePixelsBuffer(Vector2.zero, size, j.sky);
		(fi :: EditableImage):WritePixelsBuffer(Vector2.zero, size, j.front)
	end)
	shown.key = j.pal.key
	shown.stars = j.pal.stars
	shown.ink = j.pal.ink
	shown.paints += 1
end

-- New shapes for a screen size: the images sized, the labels laid out, the notch painted now.
local function rebuild(W: number, H: number, K: number, pal: Pal)
	ensureGui()
	skyImage = sized(skyImage, W, H, "sky")
	frontImage = sized(frontImage, W, H, "sky far")
	local si, fi = skyImage, frontImage
	if si == nil or fi == nil then
		return
	end
	local g = buildGeo(W, H)
	geo = g
	shown.geos += 1
	local cv, sc = canvas :: Frame, canvasScale :: UIScale
	cv.Size = UDim2.fromOffset(W, H)
	sc.Scale = K
	local sl = skyLabel :: ImageLabel
	sl.ImageContent = Content.fromObject(si)
	sl.Size = UDim2.fromOffset(W, H)
	for _, l in frontLabels do
		l.ImageContent = Content.fromObject(fi)
		l.Size = UDim2.fromOffset(W, H)
	end
	shown.W, shown.H, shown.K, shown.seaOff = W, H, K, -1
	sun.key, moon.key = "", ""
	local j = newJob(pal, g)
	colourRows(j, g, 0, H - 1)
	finish(j, g)
	job = nil
end

-- The sun or the moon at u on its arc (hidden when it is well below the horizon), its picture painted again when its
-- colour or phase moves on.
local function placeBody(b: Body, isSun: boolean, u: number, phase: number, veil: number, W: number, H: number)
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
		r = math.floor(r * (1 + 0.9 * low) + 0.5) -- (bigger as it nears the sea of clouds)
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
		l.Size = UDim2.fromOffset(S, S)
		b.x = -1e9
	end
	local cx, cy = arc(u, W, H, r)
	local x, y = math.floor(cx - b.S / 2 + 0.5), math.floor(cy - b.S / 2 + 0.5)
	if x ~= b.x or y ~= b.y then
		b.x, b.y = x, y
		l.Position = UDim2.fromOffset(x, y)
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
	f.Size = UDim2.fromOffset(1, 1)
	f.ZIndex = 5
	f.Parent = lifeLayer
	return f
end
local function put(f: Frame, x: number, y: number)
	f.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
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
	local K = math.max(1, PixelRenderer.pixelScale())
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local W, H = math.max(1, math.ceil(vp.X / K)), math.max(1, math.ceil(vp.Y / K))
	local kind = WeatherView.kind()
	local wx = WX[kind] or CLEAR
	local hour = DayLight.skyHour()
	local pal = paletteAt(hour, kind, variantNow())
	local g = geo
	if g == nil or g.W ~= W or g.H ~= H or K ~= shown.K then
		if K ~= shown.K then
			clearLife()
		end
		rebuild(W, H, K, pal)
		g = geo
		shown.kind = kind
	end
	if g == nil or shown.paints == 0 then
		return
	end
	-- a new notch: coloured a few rows a frame, shown once whole
	if pal.key ~= shown.key then
		local cur = job
		local j: Job = if cur ~= nil and cur.pal.key == pal.key then cur else newJob(pal, g)
		job = j
		local rows = math.max(8, math.floor(ROW_PIXELS / g.W))
		colourRows(j, g, j.y, math.min(g.H - 1, j.y + rows - 1))
		if j.y >= g.H then
			finish(j, g)
			job = nil
			shown.kind = kind
		end
	end
	-- the sun and the moon
	local day = SUNSET - SUNRISE
	placeBody(sun, true, (hour - SUNRISE) / day, 0, wx.veil, W, H)
	placeBody(moon, false, ((hour - SUNSET) % 1) / (1 - day), (DayLight.skyNight() % 8) + 1, wx.veil, W, H)
	-- the sea of clouds and the far islets drifting, sliding with the view
	local panX = CameraController.pan()
	local now = os.clock()
	local seaOff = math.floor(now / SEA_DRIFT - panX * FAR_PARALLAX) % W
	if seaOff ~= shown.seaOff then
		shown.seaOff = seaOff
		local a, b = frontLabels[1], frontLabels[2]
		if a and b then
			a.Position = UDim2.fromOffset(seaOff - W, 0)
			b.Position = UDim2.fromOffset(seaOff, 0)
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

-- What the sky's work costs at W x H (previews, with their own clock): the shapes and one notch, in ms.
function SkyBackdrop.debugTimes(W: number, H: number, clock: (() -> number)?): (number, number)
	local now = clock or os.clock
	local t0 = now()
	local g = buildGeo(W, H)
	local t1 = now()
	local j = newJob(paletteAt(0.5, "sunny", 1), g)
	colourRows(j, g, 0, H - 1)
	local t2 = now()
	return (t1 - t0) * 1000, (t2 - t1) * 1000
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
-- painted and shapes built, a notch under way, the far things' offset, the hour, how much of the
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
