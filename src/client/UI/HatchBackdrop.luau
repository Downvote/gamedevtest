--!strict
--!native
-- The hatch scene's painted backdrop (UI/HatchScene; GAME_DESIGN 6.2): the request of 2026-11-13, "the egg hatching
-- scene isnt detailed enough. add much much more detail to it, especially the egg. you are allowed to use 2d elements
-- as well for the background". A picture drawn pixel by pixel into one EditableImage at the world's art grid (each art
-- pixel K x K screen px, like the pixel layer), shown on a ScreenGui just behind the pixel layer: the stage's sky is
-- see-through (CameraController Stage.clear), so the floating islet with the nest stands in front of it.
-- Each rarity has its own sky (a cozy sunset for a common egg, a golden afternoon, a blue twilight, a violet night, a
-- deep gold night): the sky in bands with ordered dither between them (never a smear), the sun or the moon lit from the
-- top left with anti-aliased edges, stars (single pixels and little crosses), soft clouds with a 1 px outline, aurora
-- curtains on the two rarest nights, three ranges of hills going darker toward the front, the nearest with round and
-- pointed trees in outline, two little islets floating far off, and a glow round the egg in dithered rings.
--   HatchBackdrop.show(r, ex, ey)   paint rarity r's sky with the egg's glow at art pixel (ex, ey) and show it
--   HatchBackdrop.step(dt)          the sky's life (a layer between the picture and the pixel layer, so the islet hides it):
--                                   little flocks of birds flapping across a day or twilight sky, shooting stars and
--                                   twinkling stars on a night one; all whole art pixels, solid colours
--   HatchBackdrop.hide()            take it away (and free its image)
--   HatchBackdrop.paint(r, W, H, ex, ey) -> buffer   the picture itself (RGBA, W x H)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)

local HatchBackdrop = {}

type Sky = {
	stops: { number }, -- the sky's colours from the top down to the horizon
	horizon: number, -- where the last stop is reached (share of the height)
	body: string, -- "sun" | "crescent" | "moon" | "bigsun"
	bodyC: { number }, -- its fill, its shade (the side away from the light), its spots
	bodyR: number, -- its radius (share of the height)
	stars: number,
	clouds: { number }?, -- fill, shade, outline
	aurora: { number }?,
	hills: { { number } }, -- far to near: fill, rim
	trees: { number }, -- fill, light, outline
	glow: number,
	glowK: number, -- how strong (0 .. 1)
	glowR: number, -- its radius (share of the height)
}

local SKIES: { Sky } = {
	-- a cozy sunset
	{
		stops = { 0x948CC6, 0xB694C1, 0xDB9DB3, 0xF0B099, 0xF5CD9A, 0xF8E3AE },
		horizon = 0.72,
		body = "sun",
		bodyC = { 0xF9ECBA, 0xF6D292, 0xF5C187 },
		bodyR = 0.12,
		stars = 0,
		clouds = { 0xFADAC1, 0xF0B2AD, 0xBE8CA1 },
		aurora = nil,
		hills = { { 0xCFA5B8, 0xDFB4C1 }, { 0xAC92AF, 0xBBA0BD }, { 0x7A6891, 0x988BAA } },
		trees = { 0x695B86, 0x8879A2, 0x4A4168 },
		glow = 0xFBF0D0,
		glowK = 0.45,
		glowR = 0.3,
	},
	-- a golden afternoon
	{
		stops = { 0x86C7D9, 0xA0D6D6, 0xBADFCA, 0xD7E9BD, 0xF0ECBE, 0xF8F1D1 },
		horizon = 0.72,
		body = "sun",
		bodyC = { 0xFDF9E2, 0xF9E7B1, 0xF8E0A8 },
		bodyR = 0.08,
		stars = 0,
		clouds = { 0xFFFFFF, 0xDAEDE9, 0x9AC0C9 },
		aurora = nil,
		hills = { { 0xB4D6B0, 0xC7E1BA }, { 0x98C195, 0xAAD0A0 }, { 0x7AAA7F, 0x8AB78C } },
		trees = { 0x5A9166, 0x7CAC7F, 0x436E55 },
		glow = 0xE3FAC7,
		glowK = 0.5,
		glowR = 0.34,
	},
	-- a blue twilight
	{
		stops = { 0x30437B, 0x394F8A, 0x45619D, 0x6F88BA, 0x8DA3CE, 0xB3C5E1 },
		horizon = 0.74,
		body = "crescent",
		bodyC = { 0xF6F2DD, 0xDED8BF, 0xD4CEB2 },
		bodyR = 0.085,
		stars = 70,
		clouds = { 0x8697C3, 0x7081B0, 0x3A4B87 },
		aurora = nil,
		hills = { { 0x6D81B3, 0x7E91BD }, { 0x4B5F96, 0x586CA0 }, { 0x3D4F80, 0x475A8B } },
		trees = { 0x374A75, 0x405382, 0x283862 },
		glow = 0xC8E7FB,
		glowK = 0.6,
		glowR = 0.4,
	},
	-- a violet night
	{
		stops = { 0x302362, 0x3C2C74, 0x4E3983, 0x674696, 0x9C70B2, 0xC995C1 },
		horizon = 0.76,
		body = "moon",
		bodyC = { 0xF8ECF4, 0xDDCAE0, 0xD1BBD7 },
		bodyR = 0.1,
		stars = 140,
		clouds = nil,
		aurora = { 0x99E6CE, 0xF0ADD8 },
		hills = { { 0x6D5094, 0x785D9F }, { 0x5B4484, 0x67508E }, { 0x483674, 0x513F7E } },
		trees = { 0x41316B, 0x4B397B, 0x32225B },
		glow = 0xEFC5FA,
		glowK = 0.68,
		glowR = 0.46,
	},
	-- a deep gold night
	{
		stops = { 0x37255F, 0x4E2F72, 0x7A3B70, 0xA0505D, 0xD4866E, 0xF1B373 },
		horizon = 0.78,
		body = "bigsun",
		bodyC = { 0xF8ECAE, 0xF4CF7D, 0xF3BA6E },
		bodyR = 0.16,
		stars = 110,
		clouds = nil,
		aurora = { 0xF6D991, 0xF5AC87 },
		hills = { { 0x985B6A, 0xAF7D85 }, { 0x7C4867, 0x88526F }, { 0x623765, 0x6C406C } },
		trees = { 0x592E5F, 0x633966, 0x482054 },
		glow = 0xF9E8B1,
		glowK = 0.8,
		glowR = 0.55,
	},
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

------------------------------------------------------------------ painting
-- The picture as 0xRRGGBB per pixel in a plain array (painted layer over layer), packed into RGBA at the end.
function HatchBackdrop.paint(r: number, W: number, H: number, ex: number, ey: number): buffer
	local sky = SKIES[math.clamp(r, 1, 5)]
	local px: { number } = table.create(W * H, 0)
	local function get(x: number, y: number): number
		return px[y * W + x + 1]
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
				if sky.body == "moon" then
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
				end
				set(x, y, if cover >= 0.75 then c elseif cover >= 0.25 then mix(get(x, y), c, 0.5) else get(x, y))
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
	-- clouds: soft heaps of round puffs, a flat underside in shade, lit at the top left, a 1 px outline
	local cl = sky.clouds
	if cl then
		for i = 1, 5 do
			local cx = hash(i * 17 + r * 3) * W
			local cy = H * (0.1 + hash(i * 29 + 7) * 0.35)
			if math.abs(cx - bx) < br * 2.4 and math.abs(cy - by) < br * 2 then
				continue
			end
			local w = H * (0.1 + hash(i * 31) * 0.1)
			local puffs: { { number } } = {}
			for k = 0, 4 do
				local u = k / 4
				table.insert(puffs, { cx - w + u * 2 * w, cy - math.sin(u * math.pi) * w * 0.35, w * (0.32 + math.sin(u * math.pi) * 0.22) })
			end
			local function inside(x: number, y: number): boolean
				if y > cy + w * 0.12 then
					return false
				end
				for _, pf in puffs do
					if (x - pf[1]) ^ 2 + (y - pf[2]) ^ 2 <= pf[3] * pf[3] then
						return true
					end
				end
				return false
			end
			local x0, x1 = math.floor(cx - w * 1.6), math.ceil(cx + w * 1.6)
			local y0, y1 = math.floor(cy - w * 1.2), math.ceil(cy + w * 0.3)
			for y = y0, y1 do
				for x = x0, x1 do
					local here = inside(x + 0.5, y + 0.5)
					if here then
						local lit = not inside(x - 0.5, y - 0.5)
						local low = y + 0.5 > cy - w * 0.08
						set(x, y, if lit then mix(cl[1], 0xFFFFFF, 0.4) elseif low then cl[2] else cl[1])
					elseif inside(x + 1.5, y + 0.5) or inside(x - 0.5, y + 0.5) or inside(x + 0.5, y + 1.5) or inside(x + 0.5, y - 0.5) then
						set(x, y, cl[3])
					end
				end
			end
		end
	end
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
	-- two little islets floating far off, either side: a grassy top, a rocky cone under it, a tree, a 1 px outline
	local far = sky.hills[1]
	for i = 1, 2 do
		local ix = if i == 1 then W * 0.12 else W * 0.86
		local iy = H * (0.36 + 0.06 * i)
		local iw = H * (0.07 - 0.012 * i)
		local function isle(x: number, y: number): number
			local dx = (x - ix) / iw
			if math.abs(dx) > 1 then
				return 0
			end
			local top = iy - (1 - dx * dx) * iw * 0.18
			local bottom = iy + (1 - math.abs(dx)) * iw * 0.9
			if y >= top and y < iy + 1 then
				return 1
			elseif y >= iy + 1 and y <= bottom then
				return 2
			end
			return 0
		end
		for y = math.floor(iy - iw), math.ceil(iy + iw) do
			for x = math.floor(ix - iw - 1), math.ceil(ix + iw + 1) do
				local k = isle(x + 0.5, y + 0.5)
				if k == 1 then
					set(x, y, far[2])
				elseif k == 2 then
					set(x, y, if (x + 0.5 - ix) > 0 then mix(far[1], 0x000000, 0.15) else far[1])
				elseif isle(x + 1.5, y + 0.5) ~= 0 or isle(x - 0.5, y + 0.5) ~= 0 or isle(x + 0.5, y + 1.5) ~= 0 or isle(x + 0.5, y - 0.5) ~= 0 then
					set(x, y, mix(far[1], 0x000000, 0.35))
				end
			end
		end
		-- (a little round tree on it)
		local tx, ty, tr = ix - iw * 0.2, iy - iw * 0.4, math.max(2, iw * 0.22)
		for y = math.floor(ty - tr - 1), math.ceil(ty + iw * 0.3) do
			for x = math.floor(tx - tr - 1), math.ceil(tx + tr + 1) do
				local d = math.sqrt((x + 0.5 - tx) ^ 2 + (y + 0.5 - ty) ^ 2)
				if d <= tr then
					set(x, y, if (x + 0.5 - tx) + (y + 0.5 - ty) < -tr * 0.3 then far[2] else mix(far[1], 0x000000, 0.1))
				elseif d <= tr + 1 then
					set(x, y, mix(far[1], 0x000000, 0.35))
				elseif math.abs(x + 0.5 - tx) < 1 and y > ty and y < iy then
					set(x, y, mix(far[1], 0x000000, 0.35))
				end
			end
		end
	end
	-- three ranges of hills, far to near, each a wavy ridge with a lit rim; trees along the nearest
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
		if li == #sky.hills then
			local tc = sky.trees
			local x = 4
			while x < W do
				local pointed = hash(x * 5 + r) < 0.35
				local tr = 3 + math.floor(hash(x * 11) * 4)
				local foot = ridge(x + 0.5)
				local ty = foot - tr - 1
				for y = math.floor(ty - tr * (if pointed then 1.6 else 1) - 1), math.ceil(foot) do
					for xx = x - tr - 1, x + tr + 1 do
						local inside = false
						local lit = false
						if pointed then
							local h = tr * 2.6
							local apex = ty - tr * 1.6
							local v = (y + 0.5 - apex) / h
							inside = v >= 0 and v <= 1 and math.abs(xx + 0.5 - x) <= v * tr
							lit = inside and (xx + 0.5 - x) < -v * tr * 0.3
						else
							local d = math.sqrt((xx + 0.5 - x) ^ 2 + (y + 0.5 - ty) ^ 2)
							inside = d <= tr
							lit = inside and (xx + 0.5 - x) + (y + 0.5 - ty) < -tr * 0.4
						end
						if inside then
							set(xx, y, if lit then tc[2] else tc[1])
						end
					end
				end
				-- (the outline: tree pixels next to anything else)
				x += tr * 2 + 1 + math.floor(hash(x * 3) * 5)
			end
			-- an ink edge round the trees and the ridge (pixels of the tree colours next to the sky or the hills behind)
			local nearTop: { number } = {}
			for xx = 0, W - 1 do
				nearTop[xx] = math.floor(ridge(xx + 0.5))
			end
			local outline: { number } = {}
			for y = 1, H - 2 do
				for xx = 1, W - 2 do
					local c = px[y * W + xx + 1]
					if c ~= tc[1] and c ~= tc[2] and y < nearTop[xx] then
						for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
							local n = px[(y + d[2]) * W + xx + d[1] + 1]
							if n == tc[1] or n == tc[2] then
								table.insert(outline, y * W + xx + 1)
								break
							end
						end
					end
				end
			end
			for _, i in outline do
				px[i] = tc[3]
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
local INK: { number } = { 0x7E5E88, 0x5F897A, 0x364471, 0, 0 } -- the birds' colour by rarity (none on the two nights)
local newLife: (r: number, W: number, H: number, K: number) -> ()

function HatchBackdrop.show(r: number, ex: number, ey: number)
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
	local buf = HatchBackdrop.paint(r, W, H, ex, ey)
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
	local sky = SKIES[math.clamp(r, 1, 5)]
	-- twinkling stars: a few bright pixels that come and go
	if sky.stars > 0 then
		for i = 1, 14 do
			local f = pixel(g, if i % 3 == 0 then 0xFFF4C8 else 0xFFFFFF)
			put(f, hash(i * 41 + 3) * W, hash(i * 59 + 1) * H * 0.5)
			table.insert(twinkles, { f = f, ph = hash(i * 7) * 6.28, rate = 1.5 + hash(i * 13) * 2.5 })
		end
	end
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
	local im = image
	if im then
		im:Destroy()
	end
	gui, label, image = nil, nil, nil
end

return HatchBackdrop
