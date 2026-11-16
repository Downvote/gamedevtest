--!strict
--!native
-- The pan cache (docs/ARCHITECTURE.md 9): the static picture's cast pixels kept by the world's art grid, so a strip a
-- pan uncovers that was on screen before comes back by a copy instead of being cast again. The request of
-- 2026-11-16: "is there any way to optimize the camera movement? it is still very laggy when moving around".
--
-- The view is orthographic and pans by whole art px, so a static pixel at a global art px (gx, gy) is the same
-- wherever the view stands: PixelRenderer's scroll only shifts its buffers. This keeps what scrolls off the layer in
-- tiles of TILE x TILE global art px, each channel the cast writes (the shade without ink, albedo, depth, normal, sun,
-- part id, the share flag, the water's class and phase) in its own plane, a byte a pixel saying it is good. The ink
-- and the contact shade are drawn again over a strip, so they are not kept.
--
-- PixelRenderer drops the tiles under every rect it queues for a re-cast (on screen or off it), and clears the lot
-- for a new bake, a growth, a tier or a stage. At most `max` tiles are kept; past that the one used longest ago goes.
local PanCache = {}

PanCache.TILE = 32
local TILE = PanCache.TILE
local N = TILE * TILE

-- The layer's static buffers, as PixelRenderer's Surf has them.
export type Bufs = {
	W: number,
	H: number,
	sShade: buffer,
	sAlbedo: buffer,
	sDepth: buffer,
	sNormal: buffer,
	sLit: buffer,
	sId: buffer,
	sShare: buffer,
	sWClass: buffer,
	sWave: buffer,
}
-- (the pixel's bytes in each plane; a tile's planes one after another)
local NAMES = { "sShade", "sAlbedo", "sDepth", "sNormal", "sLit", "sId", "sShare", "sWClass", "sWave" }
local BYTES = { 4, 4, 4, 1, 1, 2, 1, 1, 1 }
local PLANE: { number } = {}
local STRIDE = 0
for i, b in BYTES do
	PLANE[i] = STRIDE * N
	STRIDE += b
end
PanCache.BYTES_A_PIXEL = STRIDE + 1

type Tile = { px: buffer, ok: buffer, used: number }

local tiles: { [number]: Tile } = {}
local count = 0
local stamp = 0
local maxTiles = 768
-- (what a preview reads: strips' pixels copied back and cast, tiles saved and dropped)
local stats = { loaded = 0, missed = 0, saved = 0, dropped = 0, evicted = 0 }

local function keyOf(tx: number, ty: number): number
	return (tx + 32768) * 65536 + (ty + 32768)
end

function PanCache.setMax(n: number)
	maxTiles = math.max(16, math.floor(n))
end

function PanCache.clear()
	if count > 0 then
		stats.dropped += count
	end
	table.clear(tiles)
	count = 0
end

function PanCache.size(): number
	return count
end

function PanCache.stats(): { loaded: number, missed: number, saved: number, dropped: number, evicted: number, tiles: number }
	local out = { loaded = stats.loaded, missed = stats.missed, saved = stats.saved, dropped = stats.dropped, evicted = stats.evicted, tiles = count }
	stats.loaded, stats.missed, stats.saved, stats.dropped, stats.evicted = 0, 0, 0, 0, 0
	return out
end

local function evictOne()
	local worst, worstKey = math.huge, nil
	for k, t in tiles do
		if t.used < worst then
			worst, worstKey = t.used, k
		end
	end
	if worstKey then
		tiles[worstKey] = nil
		count -= 1
		stats.evicted += 1
	end
end

local function tileAt(tx: number, ty: number, make: boolean): Tile?
	local k = keyOf(tx, ty)
	local t = tiles[k]
	if t == nil and make then
		if count >= maxTiles then
			evictOne()
		end
		t = { px = buffer.create(N * STRIDE), ok = buffer.create(N), used = 0 }
		tiles[k] = t
		count += 1
	end
	stamp += 1
	if t then
		t.used = stamp
	end
	return t
end

-- Keep the layer rect (x0, y0)..(x1, y1) (inclusive, layer px) of a layer whose pixel (0, 0) is the global art px
-- (gx0, gy0).
function PanCache.save(b: Bufs, gx0: number, gy0: number, x0: number, y0: number, x1: number, y1: number)
	x0, y0 = math.max(0, x0), math.max(0, y0)
	x1, y1 = math.min(b.W - 1, x1), math.min(b.H - 1, y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local W = b.W
	local bufs: { buffer } = {}
	for i, name in NAMES do
		bufs[i] = (b :: any)[name]
	end
	local tx0, tx1 = (gx0 + x0) // TILE, (gx0 + x1) // TILE
	local ty0, ty1 = (gy0 + y0) // TILE, (gy0 + y1) // TILE
	for ty = ty0, ty1 do
		local ry0 = math.max(y0, ty * TILE - gy0)
		local ry1 = math.min(y1, ty * TILE + TILE - 1 - gy0)
		for tx = tx0, tx1 do
			local rx0 = math.max(x0, tx * TILE - gx0)
			local rx1 = math.min(x1, tx * TILE + TILE - 1 - gx0)
			local t = tileAt(tx, ty, true) :: Tile
			local len = rx1 - rx0 + 1
			local lx = rx0 + gx0 - tx * TILE
			for y = ry0, ry1 do
				local ly = y + gy0 - ty * TILE
				local ti = ly * TILE + lx
				local li = y * W + rx0
				for c = 1, #BYTES do
					local e = BYTES[c]
					buffer.copy(t.px, PLANE[c] + ti * e, bufs[c], li * e, len * e)
				end
				buffer.fill(t.ok, ti, 1, len)
			end
			stats.saved += len * (ry1 - ry0 + 1)
		end
	end
end

-- Put the kept pixels back into the layer rect (x0, y0)..(x1, y1), which lies in one tile (`split`). True when every
-- one of them was kept (and is now in the layer); false leaves the layer as it was, for the caller to cast.
function PanCache.load(b: Bufs, gx0: number, gy0: number, x0: number, y0: number, x1: number, y1: number): boolean
	local tx, ty = (gx0 + x0) // TILE, (gy0 + y0) // TILE
	local len = x1 - x0 + 1
	local t = tileAt(tx, ty, false)
	if t == nil then
		stats.missed += len * (y1 - y0 + 1)
		return false
	end
	local lx = x0 + gx0 - tx * TILE
	for y = y0, y1 do
		local ti = (y + gy0 - ty * TILE) * TILE + lx
		for i = ti, ti + len - 1 do
			if buffer.readu8(t.ok, i) == 0 then
				stats.missed += len * (y1 - y0 + 1)
				return false
			end
		end
	end
	local W = b.W
	for c, name in NAMES do
		local e = BYTES[c]
		local dst = (b :: any)[name] :: buffer
		for y = y0, y1 do
			local ti = (y + gy0 - ty * TILE) * TILE + lx
			buffer.copy(dst, (y * W + x0) * e, t.px, PLANE[c] + ti * e, len * e)
		end
	end
	stats.loaded += len * (y1 - y0 + 1)
	return true
end

-- A layer rect cut along the tiles' edges (each piece lies in one tile).
function PanCache.split(gx0: number, gy0: number, x0: number, y0: number, x1: number, y1: number): { { x0: number, y0: number, x1: number, y1: number } }
	local out = {}
	if x0 > x1 or y0 > y1 then
		return out
	end
	for ty = (gy0 + y0) // TILE, (gy0 + y1) // TILE do
		local ry0 = math.max(y0, ty * TILE - gy0)
		local ry1 = math.min(y1, ty * TILE + TILE - 1 - gy0)
		for tx = (gx0 + x0) // TILE, (gx0 + x1) // TILE do
			local rx0 = math.max(x0, tx * TILE - gx0)
			local rx1 = math.min(x1, tx * TILE + TILE - 1 - gx0)
			table.insert(out, { x0 = rx0, y0 = ry0, x1 = rx1, y1 = ry1 })
		end
	end
	return out
end

-- Forget the tiles under a global art px rect (inclusive): what it covers is cast again.
function PanCache.drop(gx0: number, gy0: number, gx1: number, gy1: number)
	if count == 0 or gx0 > gx1 or gy0 > gy1 then
		return
	end
	for ty = gy0 // TILE, gy1 // TILE do
		for tx = gx0 // TILE, gx1 // TILE do
			local k = keyOf(tx, ty)
			if tiles[k] then
				tiles[k] = nil
				count -= 1
				stats.dropped += 1
			end
		end
	end
end

return PanCache
