--!strict
-- The driftlings' surface textures (GAME_DESIGN 6; docs/ARCHITECTURE.md 7). Pure.
--
-- The request (2026-11-14): "Can you use different eyes for each? Also, apply texture to each of them". The world's
-- static surfaces get their texture as the filter bakes them (Render/Shading's patterns, on the global art grid), but a
-- pattern on the screen's grid would slide over a moving model. So a driftling's texture is worked out on the part
-- itself: the pixel renderer finds where on the part a pixel's ray hits (in the part's own frame, so the pattern
-- turns and walks with it), lays that point out flat (`DynTex.uv`: round the part's own axis for a ball or a
-- cylinder) and asks `DynTex.lift` whether the pixel steps one band lighter (+1), darker (-1) or stays (0) on its
-- colour's own ramp, the way the static textures do. The patterns are measured in art px (`px`: studs a pixel), so
-- a mark is one pixel wide at any zoom and the pattern keeps to the pixel grid: strands of fur, rows of scales or
-- feathers, a shell's growth lines, specks and cracks in stone, a wall's courses, bark's grain, a crystal's facets,
-- pores in skin, ice's streaks, velvet's fuzz, a shell's pits, a jelly's bubbles and cooling lava's bright cracks.

local DynTex = {}

DynTex.NAMES = {
	"fur",
	"fluff",
	"feather",
	"scale",
	"shell",
	"stone",
	"brick",
	"bark",
	"crystal",
	"skin",
	"ice",
	"velvet",
	"chitin",
	"jelly",
	"ember",
}
local KIND: { [string]: number } = {}
for i, name in DynTex.NAMES do
	KIND[name] = i
end
DynTex.KIND = KIND

-- Art px per stud from which a driftling wears its texture: below it (the islands, about 8) a one-pixel pattern on a
-- figure 16 px tall would only be noise.
DynTex.MIN_PX_PER_STUD = 12

-- The texture kind's number (0: none) by its name.
function DynTex.kind(name: string?): number
	if name == nil then
		return 0
	end
	return KIND[name] or 0
end

-- h * m modulo 2^32 for whole numbers below 2^32, exact (no product reaches 2^53).
local function mul32(h: number, m: number): number
	local lo = h % 65536
	return (lo * m + ((h - lo) / 65536 * m) % 65536 * 65536) % 4294967296
end

-- A well-mixed number in [0, 1) from whole numbers a, b (any sign, small) and a salt k.
local function hash(a: number, b: number, k: number): number
	local h = (a * 73856093 + b * 19349663 + k * 83492791) % 4294967296
	h = mul32(bit32.bxor(h, bit32.rshift(h, 16)), 0x85EBCA6B)
	h = mul32(bit32.bxor(h, bit32.rshift(h, 13)), 0xC2B2AE35)
	return bit32.bxor(h, bit32.rshift(h, 16)) / 4294967296
end
DynTex.hash = hash

-- A point on a part laid out flat, in studs: (u round the part, v along it). shape "Ball" (round its own Y),
-- "Cylinder" (round its own X, the axis Roblox cylinders run along) or anything else (a box: across and up).
function DynTex.uv(shape: string, x: number, y: number, z: number): (number, number)
	if shape == "Ball" then
		return math.atan2(z, x) * math.sqrt(x * x + z * z), y
	elseif shape == "Cylinder" then
		return math.atan2(z, y) * math.sqrt(y * y + z * z), x
	end
	return x + z, y
end

-- Scallops (scales, feathers, fluff, chitin's rims): cells `w` wide and `h` tall, every other row shifted half a cell,
-- each cell's lower rim drawn as a shallow arc one pixel thick.
local function scallop(iu: number, iv: number, w: number, h: number, seed: number, skip: number): boolean
	local row = iv // h
	local shift = if row % 2 == 0 then 0 else w // 2
	local col = (iu + shift) // w
	if skip > 0 and hash(col, row, seed) < skip then
		return false
	end
	local lu = (iu + shift) - col * w
	local lv = iv - row * h
	if lv == h - 1 then
		return lu > 0 and lu < w - 1
	end
	if lv == h - 2 then
		return lu == 0 or lu == w - 1
	end
	return false
end

-- How far a driftling's texture mark steps toward the next band (Shading.toonAt's `soft`): half way, a gentle tone
-- of its colour rather than a whole band (the request of 2026-11-14: "make the noise textures across everything more
-- less contrast with whatever material they are on").
DynTex.SOFT = 0.5

-- Whether the pixel at (u, v) (studs on the part, from DynTex.uv) steps lighter (+1), darker (-1) or not (0) for
-- texture `kind` (DynTex.KIND), with `px` studs a pixel and `seed` (a whole number) keeping two parts' patterns apart.
function DynTex.lift(kind: number, u: number, v: number, px: number, seed: number): number
	if kind <= 0 or px <= 0 then
		return 0
	end
	local iu = math.floor(u / px + seed * 7.13)
	local iv = math.floor(v / px + seed * 3.71)
	if kind == 1 then
		-- fur: short strands two pixels long in cells 3 wide and 4 tall (rows shifted), a light tip now and then
		local col = iu // 3
		local shift = (col % 2) * 2
		local row = (iv + shift) // 4
		local h = hash(col, row, 11)
		local lu, lv = iu - col * 3, (iv + shift) - row * 4
		local sx = math.floor(h * 3)
		if lu == sx then
			if (lv == 1 or lv == 2) and (h * 7.31) % 1 < 0.62 then
				return -1
			end
			if lv == 0 and (h * 13.7) % 1 > 0.86 then
				return 1
			end
		end
		return 0
	elseif kind == 2 then
		-- fluff: small round scallops, a few cells left plain
		return if scallop(iu, iv, 5, 4, 12, 0.25) then -1 else 0
	elseif kind == 3 then
		-- feathers: wide shallow scallops in rows, a light edge above each now and then
		if scallop(iu, iv, 7, 4, 13, 0) then
			return -1
		end
		return if scallop(iu, iv + 1, 7, 4, 13, 0.85) then 1 else 0
	elseif kind == 4 then
		-- scales: tight scallops
		return if scallop(iu, iv, 5, 4, 14, 0) then -1 else 0
	elseif kind == 5 then
		-- shell: wavy growth lines every 4 px, a lighter line just above some
		local wave = math.floor(1.5 * math.sin(iu / 7 + hash(iu // 14, 0, 15) * 3))
		local k = (iv + wave) % 4
		if k == 0 then
			return -1
		end
		if k == 1 and hash(iu // 5, (iv + wave) // 4, 16) > 0.6 then
			return 1
		end
		return 0
	elseif kind == 6 then
		-- stone: lone specks, dark and light; a short crack in a few 9 px cells
		local h = hash(iu, iv, 17)
		if h < 0.05 then
			return -1
		elseif h > 0.97 then
			return 1
		end
		local cu, cv = iu // 9, iv // 9
		if hash(cu, cv, 18) < 0.18 then
			local lu, lv = iu - cu * 9, iv - cv * 9
			local slope = if hash(cu, cv, 19) < 0.5 then 1 else -1
			local off = math.floor(hash(cu, cv, 20) * 3)
			if lu >= 2 and lu <= 6 and lv == 4 + off + slope * ((lu - 2) // 2) then
				return -1
			end
		end
		return 0
	elseif kind == 7 then
		-- brick: courses 4 px tall, bricks 8 wide set half a brick over each row, the mortar a pale line
		local row = iv // 4
		local shift = (row % 2) * 4
		if iv % 4 == 0 or (iu + shift) % 8 == 0 then
			return 1
		end
		return if hash(iu, iv, 21) < 0.03 then -1 else 0
	elseif kind == 8 then
		-- bark: grain running along the part, each line wavering and broken in places
		local col = iu // 5
		local wob = math.floor(1.4 * math.sin(iv / 5 + hash(col, 0, 22) * 6.28))
		if (iu + wob) % 5 == 0 and hash(col, iv // 6, 23) > 0.2 then
			return -1
		end
		return if hash(iu, iv, 24) > 0.985 then 1 else 0
	elseif kind == 9 then
		-- crystal: facet lines on the slant in some cells, a glint here and there
		local cu, cv = iu // 7, iv // 7
		if (iu + iv) % 7 == 0 and hash(cu, cv, 25) < 0.65 then
			return -1
		end
		if (iu - iv) % 9 == 0 and hash(cu, cv, 26) < 0.35 then
			return 1
		end
		return if hash(iu, iv, 27) > 0.985 then 1 else 0
	elseif kind == 10 then
		-- skin: a pore in some 3 px cells, a soft light fleck in fewer
		local cu, cv = iu // 3, iv // 3
		local h = hash(cu, cv, 28)
		local lu, lv = iu - cu * 3, iv - cv * 3
		local pu, pv = math.floor(h * 3), math.floor((h * 9.7) % 1 * 3)
		if lu == pu and lv == pv then
			if h < 0.3 then
				return -1
			elseif h > 0.88 then
				return 1
			end
		end
		return 0
	elseif kind == 11 then
		-- ice: pale streaks on the slant, broken; a dark speck rarely
		if (iu - iv) % 8 == 0 and hash(iu // 4, iv // 4, 29) < 0.55 then
			return 1
		end
		return if hash(iu, iv, 30) < 0.02 then -1 else 0
	elseif kind == 12 then
		-- velvet: fine fuzz, one light pixel and one dark in some 3 px cells
		local cu, cv = iu // 3, iv // 3
		local h = hash(cu, cv, 31)
		local lu, lv = iu - cu * 3, iv - cv * 3
		if lu == 0 and lv == 0 and h < 0.45 then
			return 1
		end
		if lu == 2 and lv == 1 and h > 0.7 then
			return -1
		end
		return 0
	elseif kind == 13 then
		-- chitin: small pits in shifted 4 px cells, each with a light rim pixel above it
		local row = iv // 4
		local shift = (row % 2) * 2
		local col = (iu + shift) // 4
		local lu, lv = (iu + shift) - col * 4, iv - row * 4
		if hash(col, row, 32) < 0.6 then
			if lu == 1 and lv == 2 then
				return -1
			end
			if lu == 1 and lv == 1 then
				return 1
			end
		end
		return 0
	elseif kind == 14 then
		-- jelly: little bubbles, rings of light 3 px across in some 6 px cells
		local cu, cv = iu // 6, iv // 6
		if hash(cu, cv, 33) < 0.4 then
			local lu, lv = iu - cu * 6, iv - cv * 6
			local du, dv = lu - 2, lv - 2
			if (du == 0 and (dv == -1 or dv == 1)) or (dv == 0 and (du == -1 or du == 1)) then
				return 1
			end
		end
		return 0
	elseif kind == 15 then
		-- ember: cooled crust with bright cracks: light lines on the slant in some cells, dark specks between
		local cu, cv = iu // 6, iv // 6
		if hash(cu, cv, 34) < 0.45 then
			local lu, lv = iu - cu * 6, iv - cv * 6
			if lu == lv or lu + lv == 5 then
				return 1
			end
		end
		return if hash(iu, iv, 35) < 0.05 then -1 else 0
	end
	return 0
end

return DynTex
