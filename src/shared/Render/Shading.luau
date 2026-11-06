--!strict
--!native
-- Toon shading, palette LUT, sky, outline and pixel sprites for the pixel layer (ARCHITECTURE 11.3). OWNER: WP8. Pure.
--
-- Colours are 0xRRGGBB numbers; every function that returns a frame colour returns a packed u32 RGBA
-- (R + G*256 + B*65536 + 255*2^24, i.e. little-endian RGBA bytes for EditableImage:WritePixelsBuffer).
--
-- Palette model: the Palette.order colours and the office tiers' theme colours (Palette.themes; see
-- Shading.defaultColors) each get a 3-band toon ramp (1.0 / 0.82 / 0.64, shadows nudged toward ink) and the
-- active mode tint (Palette.modes). Those ramp colours are the targets of the 32x32x32 nearest-colour LUT, so a
-- shaded and tinted surface always lands on a colour of its own ramp instead of drifting into another hue (a
-- green carpet stays green instead of turning grey). The LUT cells are filled lazily on first use.
--
-- Places: the world outside wears the mode tint; inside the shop (Shading.INDOOR, Palette.indoor) the same season
-- lit warmer by the lamps; a pool of window sunlight on the shop floor (Shading.SUNLIT) the indoor tint times
-- Palette.sunlit. toonAt / tone / mixAt / warm / tinted take a place. The bands have no dither: a flat face is one
-- clean band, never a checker field (and a turning head never flickers).
local Palette = require(script.Parent.Parent.Data.Palette)
local Ramp = require(script.Parent.Ramp)

type FrameLike = { W: number, H: number, color: buffer, depth: buffer, id: buffer }

local Shading = {}

local SUN_LEN = math.sqrt(0.45 * 0.45 + 0.8 * 0.8 + 0.35 * 0.35)
local SUN: { x: number, y: number, z: number } = { x = -0.45 / SUN_LEN, y = 0.8 / SUN_LEN, z = 0.35 / SUN_LEN }
Shading.SUN = SUN

local SX, SY, SZ = SUN.x, SUN.y, SUN.z

------------------------------------------------------------------ constants
local BANDS = { 1.0, 0.82, 0.64 }
local BAND_HI = 0.5 -- light value above which a surface is fully lit
local BAND_LO = 0.18 -- light value above which a surface is in the middle band
local HEMI = 0.1 -- sky/ground hint: up-facing surfaces gain light, down-facing lose it
local INK_SHIFT = 0.3 -- darker bands blend (1 - band) * INK_SHIFT toward ink (pixel-art hue shift)
local OUTLINE_DEPTH = 0.75 -- a neighbour must be this much deeper (studs) to draw an ink edge
local LUT_EMPTY = 0xFFFFFFFF -- sentinel for an uncomputed LUT cell (not a valid 24-bit colour)
local ALPHA = 255 * 16777216

-- 4x4 Bayer matrix, normalised to [0, 1)
local BAYER: { number } = {
	0 / 16, 8 / 16, 2 / 16, 10 / 16,
	12 / 16, 4 / 16, 14 / 16, 6 / 16,
	3 / 16, 11 / 16, 1 / 16, 9 / 16,
	15 / 16, 7 / 16, 13 / 16, 5 / 16,
}

local function bayer(x: number, y: number): number
	return BAYER[(y % 4) * 4 + (x % 4) + 1]
end

local function clamp255(v: number): number
	if v < 0 then
		return 0
	elseif v > 255 then
		return 255
	end
	return math.floor(v + 0.5)
end

local INK = Palette.colors.ink or 0x2B1E2E
local INK_R, INK_G, INK_B = bit32.rshift(INK, 16), bit32.band(bit32.rshift(INK, 8), 0xFF), bit32.band(INK, 0xFF)

------------------------------------------------------------------ state
-- Two palette contexts share the base colours: the world's (tinted by the active mode, Shading.setMode) and a fixed
-- "day" one for UI pictures (Snapshot: icons look the same at night and in every season). Each keeps its own ramp
-- targets and lazily filled LUT, so drawing a picture never invalidates the world's LUT.
type Ctx = {
	tintR: number,
	tintG: number,
	tintB: number,
	-- LUT targets (r, g, b components and the packed 0xRRGGBB value)
	targetR: { number },
	targetG: { number },
	targetB: { number },
	targetRGB: { number },
	lut: buffer,
	dirty: boolean,
	-- toon / toonAt / tone results by rgb * 4 + band (cleared with the targets): a band's colour costs a table read
	memo: { [number]: number },
}
local function newCtx(): Ctx
	return {
		tintR = 1,
		tintG = 1,
		tintB = 1,
		targetR = {},
		targetG = {},
		targetB = {},
		targetRGB = {},
		lut = buffer.create(32768 * 4),
		dirty = true,
		memo = {},
	}
end
local baseColors: { number } = {}
local modeName = "day"
local WORLD: Ctx = newCtx()
local DAY: Ctx = newCtx()
-- Places (Shading.toonAt / tone / mixAt): the world outside (WORLD, the mode tint), inside the shop (INDOOR: the
-- mode's warmer lamp-lit tint, Palette.indoor) and a pool of window sunlight on the shop floor (SUNLIT: the indoor
-- tint times Palette.sunlit). Each has its own ramp targets and LUT, like WORLD and DAY.
local INDOOR: Ctx = newCtx()
local SUNLIT: Ctx = newCtx()
Shading.OUTDOOR, Shading.INDOOR, Shading.SUNLIT = 0, 1, 2
local PLACES: { Ctx } = { WORLD, INDOOR, SUNLIT }
local version = 0 -- bumped whenever a colour any context returns may have changed (palette or mode)

-- c * band, nudged toward ink for the darker bands, then the context's tint. Returns r, g, b (floats).
local function rampTint(ctx: Ctx, r: number, g: number, b: number, band: number): (number, number, number)
	local w = (1 - band) * INK_SHIFT
	local k = band * (1 - w)
	return (r * k + INK_R * w) * ctx.tintR, (g * k + INK_G * w) * ctx.tintG, (b * k + INK_B * w) * ctx.tintB
end

local function rebuildTargets(ctx: Ctx)
	local targetR, targetG, targetB, targetRGB = ctx.targetR, ctx.targetG, ctx.targetB, ctx.targetRGB
	table.clear(targetR)
	table.clear(targetG)
	table.clear(targetB)
	table.clear(targetRGB)
	for _, c in baseColors do
		local r, g, b = bit32.rshift(c, 16), bit32.band(bit32.rshift(c, 8), 0xFF), bit32.band(c, 0xFF)
		for _, band in BANDS do
			local tr, tg, tb = rampTint(ctx, r, g, b, band)
			local cr, cg, cb = clamp255(tr), clamp255(tg), clamp255(tb)
			table.insert(targetR, cr)
			table.insert(targetG, cg)
			table.insert(targetB, cb)
			table.insert(targetRGB, cr * 65536 + cg * 256 + cb)
		end
	end
	buffer.fill(ctx.lut, 0, 0xFF)
	table.clear(ctx.memo)
	ctx.dirty = false
end

-- redmean colour distance (cheap perceptual approximation)
local function nearest(ctx: Ctx, r: number, g: number, b: number): number
	local targetR, targetG, targetB, targetRGB = ctx.targetR, ctx.targetG, ctx.targetB, ctx.targetRGB
	local best, bestD = 0, math.huge
	for i = 1, #targetRGB do
		local dr, dg, db = r - targetR[i], g - targetG[i], b - targetB[i]
		local rm = (r + targetR[i]) * 0.5
		local d = (2 + rm / 256) * dr * dr + 4 * dg * dg + (2 + (255 - rm) / 256) * db * db
		if d < bestD then
			bestD = d
			best = targetRGB[i]
		end
	end
	return best
end

-- nearest palette colour for float components (0..255), via the context's lazily filled 32^3 LUT
local function lutRGB(ctx: Ctx, r: number, g: number, b: number): number
	if ctx.dirty then
		rebuildTargets(ctx)
	end
	local qr, qg, qb = clamp255(r), clamp255(g), clamp255(b)
	local cell = bit32.rshift(qr, 3) * 1024 + bit32.rshift(qg, 3) * 32 + bit32.rshift(qb, 3)
	local lut = ctx.lut
	local v = buffer.readu32(lut, cell * 4)
	if v == LUT_EMPTY then
		-- nearest to the cell centre, so the answer is the same for every colour in the cell
		v = nearest(ctx, bit32.band(qr, 0xF8) + 4, bit32.band(qg, 0xF8) + 4, bit32.band(qb, 0xF8) + 4)
		buffer.writeu32(lut, cell * 4, v)
	end
	return v
end

local function packRGB(rgb: number): number
	return bit32.rshift(rgb, 16) + bit32.band(rgb, 0xFF00) + bit32.band(rgb, 0xFF) * 65536 + ALPHA
end

------------------------------------------------------------------ API
function Shading.pack(r: number, g: number, b: number): number
	return clamp255(r) + clamp255(g) * 256 + clamp255(b) * 65536 + ALPHA
end

-- The renderer's LUT base colours: Palette.order, then every Palette.themes colour (the office tiers' floors and
-- walls) that is not already in it (themes in name order, keys in name order), so the list is the same on every
-- client.
function Shading.defaultColors(): { number }
	local out: { number } = {}
	local seen: { [number]: boolean } = {}
	local function add(c: number?)
		if type(c) == "number" and not seen[c] then
			seen[c] = true
			table.insert(out, c)
		end
	end
	for _, key in Palette.order do
		add(Palette.colors[key])
	end
	local themeNames: { string } = {}
	for name in Palette.themes do
		table.insert(themeNames, name)
	end
	table.sort(themeNames)
	for _, name in themeNames do
		local overrides = Palette.themes[name]
		local keys: { string } = {}
		for k in overrides do
			table.insert(keys, k)
		end
		table.sort(keys)
		for _, k in keys do
			add(overrides[k])
		end
	end
	return out
end

-- LUT base colours (0xRRGGBB), normally Shading.defaultColors(). The LUT is rebuilt lazily on the next lookup.
function Shading.setPalette(colors: { number })
	table.clear(baseColors)
	for _, c in colors do
		if type(c) == "number" and c >= 0 and c <= 0xFFFFFF then
			table.insert(baseColors, math.floor(c))
		end
	end
	if #baseColors == 0 then
		table.insert(baseColors, 0x000000)
		table.insert(baseColors, 0xFFFFFF)
	end
	WORLD.dirty = true
	DAY.dirty = true
	INDOOR.dirty = true
	SUNLIT.dirty = true
	version += 1
end

-- Palette.modes key ("day", "night", "spring", ...). Unknown keys fall back to "day". Also sets the indoor tint
-- (Palette.indoor, else the mode's own) and the sunlit one (indoor times Palette.sunlit).
function Shading.setMode(mode: string)
	local m = Palette.modes[mode]
	if m == nil then
		mode = "day"
		m = Palette.modes.day
	end
	modeName = mode
	if m then
		WORLD.tintR, WORLD.tintG, WORLD.tintB = m.r, m.g, m.b
	else
		WORLD.tintR, WORLD.tintG, WORLD.tintB = 1, 1, 1
	end
	local inside = Palette.indoor[mode] or m
	if inside then
		INDOOR.tintR, INDOOR.tintG, INDOOR.tintB = inside.r, inside.g, inside.b
	else
		INDOOR.tintR, INDOOR.tintG, INDOOR.tintB = WORLD.tintR, WORLD.tintG, WORLD.tintB
	end
	local sun = Palette.sunlit
	SUNLIT.tintR, SUNLIT.tintG, SUNLIT.tintB = INDOOR.tintR * sun.r, INDOOR.tintG * sun.g, INDOOR.tintB * sun.b
	WORLD.dirty = true
	INDOOR.dirty = true
	SUNLIT.dirty = true
	version += 1
end

-- The active mode's name (Shading.setMode).
function Shading.mode(): string
	return modeName
end

-- A number that changes whenever the palette or the mode changes (colours cached from tone / toonAt are stale).
function Shading.version(): number
	return version
end

function Shading.lut(rgb: number): number
	return lutRGB(WORLD, bit32.rshift(rgb, 16), bit32.band(bit32.rshift(rgb, 8), 0xFF), bit32.band(rgb, 0xFF))
end

-- See-through surfaces: packed colour `over` at opacity `a` (0..1, i.e. 1 - Transparency) on top of packed colour
-- `under`, snapped to the palette (alpha 255; the world's mode-tinted one, or the fixed day one with `day`). Over a
-- transparent pixel (alpha < 128, a Snapshot's background) the result is `over` with alpha a * 255, so glass keeps
-- its see-through edge on any UI behind it.
function Shading.blend(over: number, under: number, a: number, day: boolean?): number
	local k = math.clamp(a, 0, 1)
	if bit32.rshift(under, 24) < 128 then
		return bit32.band(over, 0xFFFFFF) + math.floor(k * 255 + 0.5) * 16777216
	end
	local r = bit32.band(over, 0xFF) * k + bit32.band(under, 0xFF) * (1 - k)
	local g = bit32.band(bit32.rshift(over, 8), 0xFF) * k + bit32.band(bit32.rshift(under, 8), 0xFF) * (1 - k)
	local b = bit32.band(bit32.rshift(over, 16), 0xFF) * k + bit32.band(bit32.rshift(under, 16), 0xFF) * (1 - k)
	return packRGB(lutRGB(if day then DAY else WORLD, r, g, b))
end

-- Toon shade a surface of albedo `rgb` with unit normal n at pixel (x, y) (global art pixels in the renderer; the
-- bands have no dither, so the result does not depend on x, y: they stay in the signature for callers).
-- lit: shadow factor in [0, 1] (0 = in a cast shadow); a value above 1 marks an emissive surface (no shading).
-- Returns a packed u32 RGBA colour on the active palette (the world's mode-tinted one, or with `day` the fixed day
-- palette that UI pictures use).
function Shading.toon(rgb: number, nx: number, ny: number, nz: number, lit: number, x: number, y: number, day: boolean?): number
	local bi: number
	if lit > 1 then
		bi = 1
	else
		local d = nx * SX + ny * SY + nz * SZ
		if d < 0 then
			d = 0
		end
		-- no dither at the band edges: a flat face is one clean band (a face whose light sits on an edge would turn
		-- into a checker field, and a turning head would flicker), a curved one gets crisp band edges
		local v = d * lit + HEMI * ny
		bi = if v > BAND_HI then 1 elseif v > BAND_LO then 2 else 3
	end
	local ctx = if day then DAY else WORLD
	if ctx.dirty then
		rebuildTargets(ctx)
	end
	-- (a band's colour once per context: Ctx.memo, as Shading.toonAt)
	local key = rgb * 4 + bi
	local hit = ctx.memo[key]
	if hit then
		return hit
	end
	local r, g, b = bit32.rshift(rgb, 16), bit32.band(bit32.rshift(rgb, 8), 0xFF), bit32.band(rgb, 0xFF)
	local tr, tg, tb = rampTint(ctx, r, g, b, BANDS[bi])
	local c = packRGB(lutRGB(ctx, tr, tg, tb))
	ctx.memo[key] = c
	return c
end

-- Shading.toon in a place (Shading.OUTDOOR, INDOOR or SUNLIT: its own tint and LUT). `lift` > 0 raises the band one
-- step (a pixel seen through a shaft of window light, a metal's specular streak); a lit pixel that is lifted turns
-- sunlit instead. `lift` < 0 lowers it one step (wood grain, a glass body), at most to the shade band.
function Shading.toonAt(rgb: number, nx: number, ny: number, nz: number, lit: number, x: number, y: number, place: number, lift: number): number
	local bi: number
	if lit > 1 then
		bi = 1
	else
		local d = nx * SX + ny * SY + nz * SZ
		if d < 0 then
			d = 0
		end
		local v = d * lit + HEMI * ny
		bi = if v > BAND_HI then 1 elseif v > BAND_LO then 2 else 3
	end
	local ctx = PLACES[place + 1] or WORLD
	if lift > 0 and lit <= 1 then
		if bi == 1 then
			ctx = SUNLIT
		else
			bi -= 1
		end
	elseif lift < 0 and lit <= 1 then
		bi = math.min(3, bi + 1) -- a material's darker streak (wood grain, the glass body)
	end
	if ctx.dirty then
		rebuildTargets(ctx)
	end
	local key = rgb * 4 + bi
	local hit = ctx.memo[key]
	if hit then
		return hit
	end
	local r, g, b = bit32.rshift(rgb, 16), bit32.band(bit32.rshift(rgb, 8), 0xFF), bit32.band(rgb, 0xFF)
	local tr, tg, tb = rampTint(ctx, r, g, b, BANDS[bi])
	local c = packRGB(lutRGB(ctx, tr, tg, tb))
	ctx.memo[key] = c
	return c
end

-- The packed colour of `rgb` (0xRRGGBB) on toon band 1 (lit), 2 (half) or 3 (shade) in a place (default outdoors),
-- as a lit surface of that colour would show: the pixel layer's effect sprites shade with it, so they wear the
-- world's own ramps and the season's tint.
function Shading.tone(rgb: number, band: number, place: number?): number
	local ctx = PLACES[(place or 0) + 1] or WORLD
	local bi = math.clamp(band, 1, 3)
	if ctx.dirty then
		rebuildTargets(ctx)
	end
	local key = rgb * 4 + bi
	local hit = ctx.memo[key]
	if hit then
		return hit
	end
	local r, g, b = bit32.rshift(rgb, 16), bit32.band(bit32.rshift(rgb, 8), 0xFF), bit32.band(rgb, 0xFF)
	local tr, tg, tb = rampTint(ctx, r, g, b, BANDS[bi])
	local c = packRGB(lutRGB(ctx, tr, tg, tb))
	ctx.memo[key] = c
	return c
end

-- Colour `rgb` (0xRRGGBB) times a place's tint, packed (no LUT): effect sprites keep their hand-picked hue-shifted
-- ramps (Render/Ramp) and still wear the season or the lamp light like the world round them.
function Shading.tinted(rgb: number, place: number?): number
	local ctx = PLACES[(place or 0) + 1] or WORLD
	return Shading.pack(bit32.rshift(rgb, 16) * ctx.tintR, bit32.band(bit32.rshift(rgb, 8), 0xFF) * ctx.tintG, bit32.band(rgb, 0xFF) * ctx.tintB)
end

-- Shading.blend in a place: packed `over` at opacity a (0..1) on packed `under`, snapped to that place's palette.
function Shading.mixAt(over: number, under: number, a: number, place: number): number
	local k = math.clamp(a, 0, 1)
	local r = bit32.band(over, 0xFF) * k + bit32.band(under, 0xFF) * (1 - k)
	local g = bit32.band(bit32.rshift(over, 8), 0xFF) * k + bit32.band(bit32.rshift(under, 8), 0xFF) * (1 - k)
	local b = bit32.band(bit32.rshift(over, 16), 0xFF) * k + bit32.band(bit32.rshift(under, 16), 0xFF) * (1 - k)
	return packRGB(lutRGB(PLACES[place + 1] or WORLD, r, g, b))
end

-- Packed colour `c` warmed by lamp light: mixed a share k (0..1) toward a warm white and snapped to a place's
-- palette (a lamp's glow on what is round it).
local WARM_R, WARM_G, WARM_B = 255, 226, 160
function Shading.warm(c: number, k: number, place: number): number
	local r = bit32.band(c, 0xFF)
	local g = bit32.band(bit32.rshift(c, 8), 0xFF)
	local b = bit32.band(bit32.rshift(c, 16), 0xFF)
	return packRGB(lutRGB(PLACES[place + 1] or WORLD, r + (WARM_R - r) * k, g + (WARM_G - g) * k, b + (WARM_B - b) * k))
end

-- Sky colour for a ray miss at pixel (x, y) of a gradient H pixels tall (y from its top): a dithered 3-step vertical
-- gradient. The renderer passes global art pixels (y from a point fixed on its plot), so the sky does not crawl as the
-- view pans.
function Shading.sky(x: number, y: number, H: number): number
	local base = if modeName == "night" then (Palette.colors.sky_night or 0x1F2552) else (Palette.colors.sky_day or 0x9FD8F2)
	local r, g, b = bit32.rshift(base, 16), bit32.band(bit32.rshift(base, 8), 0xFF), bit32.band(base, 0xFF)
	local t = (if H > 0 then y / H else 0) + (bayer(x, y) - 0.5) * 0.25
	local lift = if t < 0.34 then 0 elseif t < 0.67 then 0.18 else 0.36
	r, g, b = r + (255 - r) * lift, g + (255 - g) * lift, b + (255 - b) * lift
	return packRGB(lutRGB(WORLD, r * WORLD.tintR, g * WORLD.tintG, b * WORLD.tintB))
end

-- Ink the pixels of the rect (inclusive, clipped) whose 4-neighbour has a different id and is more than
-- `depthTol` studs deeper (default OUTLINE_DEPTH, 0.75; Snapshot passes the same step in art px for its scale).
-- Only colour is written; depth and id are read. With `base` (a colour buffer of the same layout, the unoutlined
-- shading) every other pixel of the rect is reset to its base colour, so re-outlining a region also removes ink
-- that no longer belongs there. Each neighbouring pair is compared once (a row pass, then a column pass): of two
-- pixels with different ids, the nearer one is inked when the other lies more than the step behind it.
function Shading.outline(f: FrameLike, x0: number, y0: number, x1: number, y1: number, base: buffer?, depthTol: number?)
	local W, H = f.W, f.H
	if x0 < 0 then
		x0 = 0
	end
	if y0 < 0 then
		y0 = 0
	end
	if x1 > W - 1 then
		x1 = W - 1
	end
	if y1 > H - 1 then
		y1 = H - 1
	end
	if x0 > x1 or y0 > y1 then
		return
	end
	local color, depth, ids = f.color, f.depth, f.id
	local ink = packRGB(INK)
	local tol = depthTol or OUTLINE_DEPTH
	if base then
		for y = y0, y1 do
			local o = (y * W + x0) * 4
			buffer.copy(color, o, base, o, (x1 - x0 + 1) * 4)
		end
	end
	-- Each neighbouring pair once: (x, x + 1) along the rows of the rect (the pixel either side of it included) and
	-- (y, y + 1) down its columns (the row above and below included). One sweep visits a pixel's right and lower
	-- neighbours together, carrying the ids it has read (where scripts run interpreted, the loop and the reads cost
	-- more than the tests).
	local ha, hb = math.max(x0 - 1, 0), math.min(x1, W - 2) -- the row pairs (x, x + 1) with x in ha..hb
	local va, vb = math.max(y0 - 1, 0), math.min(y1, H - 2) -- the column pairs (y, y + 1) with y in va..vb
	for y = va, y1 do
		local row = y * W
		local doRow = y >= y0
		local doCol = y <= vb
		if doRow and doCol then
			-- the pixel left of the rect: its row pair only
			if ha < x0 then
				local a = row + ha
				local idA, idB = buffer.readu16(ids, a * 2), buffer.readu16(ids, (a + 1) * 2)
				if idB ~= idA and buffer.readf32(depth, a * 4) > buffer.readf32(depth, (a + 1) * 4) + tol then
					buffer.writeu32(color, (a + 1) * 4, ink)
				end
			end
			local a = row + x0
			local idA = buffer.readu16(ids, a * 2)
			for x = x0, x1 do
				a = row + x
				local dA: number? = nil
				-- the row pair (x, x + 1)
				if x <= hb then
					local idB = buffer.readu16(ids, (a + 1) * 2)
					if idB ~= idA then
						local da, db = buffer.readf32(depth, a * 4), buffer.readf32(depth, (a + 1) * 4)
						dA = da
						if db > da + tol then
							buffer.writeu32(color, a * 4, ink)
						end
						if da > db + tol and x < x1 then
							buffer.writeu32(color, (a + 1) * 4, ink)
						end
					end
					-- the column pair (y, y + 1)
					local idD = buffer.readu16(ids, (a + W) * 2)
					if idD ~= idA then
						local da = dA or buffer.readf32(depth, a * 4)
						local dd = buffer.readf32(depth, (a + W) * 4)
						if dd > da + tol then
							buffer.writeu32(color, a * 4, ink)
						end
						if da > dd + tol and y < y1 then
							buffer.writeu32(color, (a + W) * 4, ink)
						end
					end
					idA = idB
				else
					local idD = buffer.readu16(ids, (a + W) * 2)
					if idD ~= idA then
						local da, dd = buffer.readf32(depth, a * 4), buffer.readf32(depth, (a + W) * 4)
						if dd > da + tol then
							buffer.writeu32(color, a * 4, ink)
						end
						if da > dd + tol and y < y1 then
							buffer.writeu32(color, (a + W) * 4, ink)
						end
					end
				end
			end
		elseif doRow then
			-- the rect's last row at the frame's bottom edge: row pairs only
			local idA = buffer.readu16(ids, (row + ha) * 2)
			for x = ha, hb do
				local a = row + x
				local idB = buffer.readu16(ids, (a + 1) * 2)
				if idB ~= idA then
					local da, db = buffer.readf32(depth, a * 4), buffer.readf32(depth, (a + 1) * 4)
					if db > da + tol and x >= x0 then
						buffer.writeu32(color, a * 4, ink)
					end
					if da > db + tol and x < x1 then
						buffer.writeu32(color, (a + 1) * 4, ink)
					end
				end
				idA = idB
			end
		elseif doCol then
			-- the row above the rect: its column pairs only (the lower pixel of each is the rect's)
			for x = x0, x1 do
				local a = row + x
				local idA, idD = buffer.readu16(ids, a * 2), buffer.readu16(ids, (a + W) * 2)
				if idD ~= idA and buffer.readf32(depth, a * 4) > buffer.readf32(depth, (a + W) * 4) + tol then
					buffer.writeu32(color, (a + W) * 4, ink)
				end
			end
		end
	end
end

-- Shading.outline over a model's rows only: row y of the frame (y0..y1) holds the model's pixels between rowMin[y] and
-- rowMax[y] (nil where it has none; a superset is fine). Ink can only change where a pair of neighbours includes one of
-- its pixels (elsewhere the frame shows the static layer, whose ink is baked in, or another model already outlined),
-- so only those pairs are visited: (x, x + 1) along each row with x in rowMin - 1 .. rowMax, and (y, y + 1) down the
-- columns either row covers. The same pairs ink the same way as Shading.outline over the model's rect would.
function Shading.outlineRows(f: FrameLike, rowMin: { [number]: number }, rowMax: { [number]: number }, y0: number, y1: number, depthTol: number?)
	local W, H = f.W, f.H
	local color, depth, ids = f.color, f.depth, f.id
	local ink = packRGB(INK)
	local tol = depthTol or OUTLINE_DEPTH
	if y0 < 0 then
		y0 = 0
	end
	if y1 > H - 1 then
		y1 = H - 1
	end
	for y = math.max(y0 - 1, 0), y1 do
		local row = y * W
		local mn, mx = rowMin[y], rowMax[y]
		if mn and mx then
			-- the row pairs (x, x + 1) with a pixel of the model
			local ha, hb = math.max(mn - 1, 0), math.min(mx, W - 2)
			if ha <= hb then
				local idA = buffer.readu16(ids, (row + ha) * 2)
				for x = ha, hb do
					local a = row + x
					local idB = buffer.readu16(ids, (a + 1) * 2)
					if idB ~= idA then
						local da, db = buffer.readf32(depth, a * 4), buffer.readf32(depth, (a + 1) * 4)
						if db > da + tol then
							buffer.writeu32(color, a * 4, ink)
						elseif da > db + tol then
							buffer.writeu32(color, (a + 1) * 4, ink)
						end
					end
					idA = idB
				end
			end
		end
		-- the column pairs (y, y + 1) where either row has the model
		if y < H - 1 then
			local mn2, mx2 = rowMin[y + 1], rowMax[y + 1]
			local lo, hi = mn, mx
			if mn2 and mx2 then
				lo = if lo then math.min(lo, mn2) else mn2
				hi = if hi then math.max(hi :: number, mx2) else mx2
			end
			if lo and hi then
				for x = math.max(lo, 0), math.min(hi, W - 1) do
					local a = row + x
					local idA, idD = buffer.readu16(ids, a * 2), buffer.readu16(ids, (a + W) * 2)
					if idD ~= idA then
						local da, dd = buffer.readf32(depth, a * 4), buffer.readf32(depth, (a + W) * 4)
						if dd > da + tol then
							buffer.writeu32(color, a * 4, ink)
						elseif da > dd + tol then
							buffer.writeu32(color, (a + W) * 4, ink)
						end
					end
				end
			end
		end
	end
end

-- The 1 px rim of one model's whole silhouette, drawn over f in place of its ink edge (the player's "you are here"
-- outline). `mask` is a frame-shaped window (mask.W x mask.H) whose pixel (0, 0) is pixel (ox, oy) of f: its id is
-- non-zero where the model covers the pixel, drawn alone (nothing hides it there), and its depth is the model's own
-- ray distance. The rim is every covered mask pixel with an uncovered 4-neighbour: the model's own edge pixels, where
-- its ink outline runs (one pixel per column along a 2:1 edge, one per row along a vertical one). Pixels outside the
-- window but inside f count as uncovered; pixels outside f make no rim (a model cut off by the edge of the picture
-- gets no line along that edge). A rim pixel takes colour `vis` (0xRRGGBB) where f shows the model itself, or `hid`
-- where f shows something more than `tol` studs (default 0.05) nearer: that part of the model is hidden behind it, so
-- its rim is an x-ray outline, with `dotted` on every other pixel along the line only, so it reads as behind: a pixel
-- whose uncovered neighbour is above or below (a flat or 2:1 stretch) by its column, one whose open side is left or
-- right (an upright stretch) by its row, so the dots keep one rhythm, one on, one off, along every edge. The rhythm is
-- counted on the global grid (gx, gy: the global art pixel of f's pixel (0, 0); default 0, 0), so it does not crawl as
-- the view pans. Only colour is written, clipped to f. Returns the rim pixels drawn.
local RIM_TOL = 0.05
function Shading.rim(f: FrameLike, mask: FrameLike, ox: number, oy: number, vis: number, hid: number, tol: number?, dotted: boolean?, gx: number?, gy: number?): number
	local mw, mh = mask.W, mask.H
	local W, H = f.W, f.H
	local mid, mdepth = mask.id, mask.depth
	local color, depth = f.color, f.depth
	local cv, ch = packRGB(vis), packRGB(hid)
	local lim = tol or RIM_TOL
	local px, py = gx or 0, gy or 0
	local n = 0
	for y = 0, mh - 1 do
		local fy = oy + y
		if fy < 0 or fy >= H then
			continue
		end
		for x = 0, mw - 1 do
			local fx = ox + x
			local i = y * mw + x
			if fx < 0 or fx >= W or buffer.readu16(mid, i * 2) == 0 then
				continue
			end
			-- a 4-neighbour uncovered: in the window, its id; outside it, whether it is still inside f. openV: above or
			-- below, openH: left or right
			local openH = if x > 0 then buffer.readu16(mid, (i - 1) * 2) == 0 else fx > 0
			if not openH then
				openH = if x < mw - 1 then buffer.readu16(mid, (i + 1) * 2) == 0 else fx < W - 1
			end
			local openV = if y > 0 then buffer.readu16(mid, (i - mw) * 2) == 0 else fy > 0
			if not openV then
				openV = if y < mh - 1 then buffer.readu16(mid, (i + mw) * 2) == 0 else fy < H - 1
			end
			if openH or openV then
				local o = (fy * W + fx) * 4
				if buffer.readf32(depth, o) >= buffer.readf32(mdepth, i * 4) - lim then
					buffer.writeu32(color, o, cv)
					n += 1
				elseif not dotted or (if openV then (fx + px) % 2 == 0 else (fy + py) % 2 == 0) then
					buffer.writeu32(color, o, ch)
					n += 1
				end
			end
		end
	end
	return n
end

------------------------------------------------------------------ quantised normals
-- The static G-buffer stores normals as one of 27 directions: index = (qx+1)*9 + (qy+1)*3 + (qz+1) with each
-- component quantised to -1, 0 or 1 (13, the zero vector, is never produced; it decodes as up).
local NX: { number } = {}
local NY: { number } = {}
local NZ: { number } = {}
for i = 0, 26 do
	local qx, qy, qz = i // 9 - 1, (i // 3) % 3 - 1, i % 3 - 1
	local len = math.sqrt(qx * qx + qy * qy + qz * qz)
	if len == 0 then
		NX[i + 1], NY[i + 1], NZ[i + 1] = 0, 1, 0
	else
		NX[i + 1], NY[i + 1], NZ[i + 1] = qx / len, qy / len, qz / len
	end
end

local function quant(c: number): number
	return if c > 0.38 then 2 elseif c < -0.38 then 0 else 1
end

-- Quantised index (0..26) of a unit normal.
function Shading.normalIndex(x: number, y: number, z: number): number
	local qx, qy, qz = quant(x), quant(y), quant(z)
	if qx == 1 and qy == 1 and qz == 1 then
		local ax, ay, az = math.abs(x), math.abs(y), math.abs(z)
		if ax >= ay and ax >= az then
			qx = if x >= 0 then 2 else 0
		elseif ay >= az then
			qy = if y >= 0 then 2 else 0
		else
			qz = if z >= 0 then 2 else 0
		end
	end
	return qx * 9 + qy * 3 + qz
end

-- Unit direction of a quantised normal index.
function Shading.normalVec(index: number): (number, number, number)
	local k = math.clamp(math.floor(index), 0, 26) + 1
	return NX[k], NY[k], NZ[k]
end

------------------------------------------------------------------ sprites
-- Code-defined pixel sprites. Each frame is a list of equal-length rows; '.' is transparent, other
-- characters map to palette keys (CHAR_KEYS) or to a tone of a palette colour's hue-shifted ramp (CHAR_TONES,
-- Render/Ramp: the one ramp the UI's sprites use too; light from the top left). They float over the scene, so they
-- wear no ink inside: only an outer outline (the coin) or a coloured edge. Frames animate with `tick`.
type SpriteFrame = { w: number, h: number, px: { number } } -- px: flat triples (dx, dy, packed colour)
type SpriteDef = { frames: { SpriteFrame }, bob: { number }? }

local CHAR_KEYS: { [string]: string } = {
	k = "ink",
	y = "gold",
	Y = "yellow",
	w = "white",
	r = "berry_red",
	p = "pink",
	P = "wall_trim",
	o = "orange",
	b = "blue",
	g = "green",
	u = "purple",
	s = "sky_day",
	c = "cream",
}

-- char -> { palette key, ramp tone (1 dark, 2 shadow, 3 base, 4 light) }
local CHAR_TONES: { [string]: { any } } = {
	["1"] = { "gold", 1 }, ["2"] = { "gold", 2 }, ["3"] = { "gold", 3 }, ["4"] = { "gold", 4 },
	R = { "berry_red", 1 }, Q = { "berry_red", 2 }, q = { "berry_red", 4 },
	e = { "sky_night", 3 }, n = { "pink", 2 }, m = { "pink", 4 }, Z = { "yellow", 2 },
}

local function toneOf(ch: string): number?
	local t = CHAR_TONES[ch]
	if t == nil then
		return nil
	end
	return Ramp.hex(Palette.colors[t[1]] or 0xFF00FF)[t[2]]
end

local function compileFrame(rows: { string }): SpriteFrame
	local px: { number } = {}
	local h = #rows
	local w = 0
	for dy, row in rows do
		w = math.max(w, #row)
		for dx = 1, #row do
			local ch = string.sub(row, dx, dx)
			if ch ~= "." then
				local key = CHAR_KEYS[ch]
				local rgb = toneOf(ch) or (if key then (Palette.colors[key] or 0xFF00FF) else 0xFF00FF)
				table.insert(px, dx - 1)
				table.insert(px, dy - 1)
				table.insert(px, packRGB(rgb))
			end
		end
	end
	return { w = w, h = h, px = px }
end

local function def(frames: { { string } }, bob: { number }?): SpriteDef
	local out: { SpriteFrame } = {}
	for _, rows in frames do
		table.insert(out, compileFrame(rows))
	end
	return { frames = out, bob = bob }
end

local SPRITES: { [string]: SpriteDef } = {
	coin = def({
		{ "..kkk..", ".k443k.", "k4w233k", "k42422k", "k33342k", ".k322k.", "..kkk.." },
		{ "...k...", "..k4k..", ".k4w3k.", ".k422k.", ".k342k.", "..k3k..", "...k..." },
		{ "...k...", "..k4k..", "..k4k..", "..kwk..", "..k3k..", "..k3k..", "...k..." }, -- edge on: a thin rounded rim
		{ "...k...", "..k4k..", ".k433k.", ".k3w2k.", ".k322k.", "..k3k..", "...k..." },
	}),
	sparkle = def({
		{ "..Y..", "..w..", "YwYwZ", "..w..", "..Z.." },
		{ ".....", ".w.Y.", "..Y..", ".Y.Z.", "....." },
		{ ".....", "..w..", ".wYZ.", "..Z..", "....." },
	}),
	star = def({
		{ "...4...", "..434..", "4443332", ".43332.", "..332..", ".32.22.", ".2...1." },
		{ "...4...", "..4w3..", "444w332", ".4www2.", "..332..", ".32.22.", ".2...1." },
	}),
	ghost = def({
		{ "..www..", ".wwwww.", ".wewew.", ".wwwww.", ".wwwwc.", ".wwwcc.", ".w.c.c." },
		{ "..www..", ".wwwww.", ".wewew.", ".wwwww.", ".wwwwc.", ".wwwcc.", "w.w.c.c" },
	}, { 0, -1 }),
	petal = def({
		{ ".mp..", "mppn.", ".pPn.", "..n..", "....." },
		{ "..mp.", ".mppn", ".ppP.", "..n..", "....." },
	}, { 0, 1 }),
	heart = def({
		{ ".qr.rr.", "qrwrrrQ", "rwrrrrQ", "rrrrrQQ", ".rrrQQ.", "..rQR..", "...R..." },
		{ ".......", "..q.r..", ".qwrrQ.", ".rrrQQ.", "..rQR..", "...R...", "......." },
	}),
	-- the "make" puff over a shelf when cakes appear on it (the Fx keeps its historic name "perfect")
	perfect = def({
		{ ".........", ".........", ".........", "....w....", "...wcw...", "....w....", ".........", ".........", "........." },
		{ ".........", ".........", "...www...", "..wwcww..", "..wcccw..", "..wwcww..", "...www...", ".........", "........." },
		{ ".........", "..Y...Y..", "...www...", "..wcccw..", ".wwcpcww.", "..wcccw..", "...www...", "..Y...Y..", "........." },
		{ "Y.......Y", "....w....", "..w...w..", ".........", ".w..p..w.", ".........", "..w...w..", "....w....", "Y.......Y" },
	}, { 0, 0, -1, -1 }),
}
SPRITES.make = SPRITES.perfect

-- Draw sprite `kind` centred on layer pixel (x, y), each sprite pixel `scale` x `scale` layer pixels (1 by
-- default: the renderer draws sprites 1:1 on the art grid, so they match the UI's pixel sprites). Colour only (sprites
-- float above the scene). Unknown kinds are ignored.
function Shading.sprite(f: FrameLike, kind: string, x: number, y: number, tick: number, scale: number?)
	local sd = SPRITES[kind]
	if sd == nil then
		return
	end
	local k = math.max(1, math.floor(scale or 1))
	local n = #sd.frames
	local fi = (math.floor(tick) % n) + 1
	local fr = sd.frames[fi]
	local bob = sd.bob
	local oy = if bob then (bob[fi] or 0) else 0
	local left = math.floor(x) - math.floor(fr.w / 2) * k
	local top = math.floor(y) - math.floor(fr.h / 2) * k + oy * k
	local W, H, color = f.W, f.H, f.color
	local px = fr.px
	for i = 1, #px, 3 do
		local c = px[i + 2]
		local bx, by = left + px[i] * k, top + px[i + 1] * k
		for dy = 0, k - 1 do
			local sy = by + dy
			if sy >= 0 and sy < H then
				for dx = 0, k - 1 do
					local sx = bx + dx
					if sx >= 0 and sx < W then
						buffer.writeu32(color, (sy * W + sx) * 4, c)
					end
				end
			end
		end
	end
end

-- Half extents (layer px, before scaling) of the largest frame of sprite `kind`, for dirty-rect bookkeeping;
-- 0, 0 for unknown kinds.
function Shading.spriteExtent(kind: string): (number, number)
	local sd = SPRITES[kind]
	if sd == nil then
		return 0, 0
	end
	local w, h = 0, 0
	for _, fr in sd.frames do
		w = math.max(w, fr.w)
		h = math.max(h, fr.h)
	end
	local bob = 0
	local bobs = sd.bob
	if bobs then
		for _, b in bobs do
			bob = math.max(bob, math.abs(b))
		end
	end
	return math.ceil(w / 2) + 1, math.ceil(h / 2) + bob + 1
end

------------------------------------------------------------------ defaults
Shading.setPalette(Shading.defaultColors())
Shading.setMode("day")

return Shading
