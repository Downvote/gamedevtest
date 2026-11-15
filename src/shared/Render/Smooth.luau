--!strict
--!native
-- Smooth shading across a model's balls (the request of 2026-11-14: "egg and creature models look blotchy due to how
-- they are detailed using balls and other small shapes. Could you smoothen these blotches out or detail them so they
-- look more natural?", then "This is also the case for the tree of life"). Pure.
--
-- An egg, a driftling or the Tree of Life is many overlapping balls. Lit one by one, each ball shows its own rings
-- of light and shade, so a body reads as a heap of blotches and every place two balls meet is a crease. A model
-- marked smooth (its "PixelSmooth" attribute) is lit as one surface instead: at a point on it, every ball within
-- reach leans the normal toward its own outward direction, the nearer its surface the more (a weight falling to 0 at
-- REACH times its radius), so where balls meet the light runs on across the join, and down a chain of balls (a tail,
-- a leg, a branch of leaves) it follows the chain's own curve. Flat pieces lying on the body (spots, blush, a belly
-- patch, an egg's marks) take the body's normal under them, so they shade with it like paint (`follow`). Parts marked
-- "PixelOwn" (eyes, gems, glowing bits) keep their own.
--   Smooth.ROLE_NONE, ROLE_BALL, ROLE_FOLLOW, ROLE_OWN
--   Smooth.role(isBall, own, follow) -> number
--   Smooth.normal(xs, ys, zs, rs, idx, n, px, py, pz, ox, oy, oz, role) -> (nx, ny, nz)
--       the smooth normal at (px, py, pz) from the balls listed in idx[1..n] (centres xs/ys/zs, radii rs), the part's
--       own normal (ox, oy, oz) and its role
--   Smooth.near(xs, ys, zs, rs, count, cx, cy, cz, R, out) -> number
--       the balls (1..count) whose reach comes within R of (cx, cy, cz), into out; how many
-- A piece lying on a smooth solid (Render/Raster.drawSolid: an ellipsoid, an egg, a cut egg; the request of 2026-11-15,
-- "currently, all of them are modelled using blobs") takes that solid's normal under it the same way (a spot on a
-- body, a freckle on an egg's shell):
--   Smooth.packSolid(S, k, cf12, sx, sy, sz, kind, prm)   the k-th solid (0-based) into S (SOLID_STRIDE numbers each)
--   Smooth.onSolids(S, idx, n, px, py, pz) -> (nx, ny, nz, w)   the normal of the nearest of the solids listed in
--       idx[1..n] (1-based) at (px, py, pz) and how much it holds there (1 on its surface, 0 SOLID_REACH studs off it)
local Smooth = {}

Smooth.ROLE_NONE = 0
Smooth.ROLE_BALL = 1 -- a ball of the body: leans the normal, and is lit by the smooth normal
Smooth.ROLE_FOLLOW = 2 -- a flat piece on the body: lit by the body's normal under it, leans nothing
Smooth.ROLE_OWN = 3 -- its own normal (eyes, gems, lights)

-- How far past a ball's surface it still leans the normal, as a share of its radius (half: the light runs on across
-- a join, but a ball keeps its own roundness away from it).
Smooth.REACH = 0.5

function Smooth.role(isBall: boolean, own: boolean, follow: boolean): number
	if own then
		return Smooth.ROLE_OWN
	elseif follow or not isBall then
		return Smooth.ROLE_FOLLOW
	end
	return Smooth.ROLE_BALL
end

function Smooth.near(xs: { number }, ys: { number }, zs: { number }, rs: { number }, count: number, cx: number, cy: number, cz: number, R: number, out: { number }): number
	local n = 0
	local reach = Smooth.REACH
	for i = 1, count do
		local r = rs[i]
		local lim = R + r * (1 + reach)
		local dx, dy, dz = xs[i] - cx, ys[i] - cy, zs[i] - cz
		if dx * dx + dy * dy + dz * dz <= lim * lim then
			n += 1
			out[n] = i
		end
	end
	for k = n + 1, #out do
		out[k] = nil
	end
	return n
end

function Smooth.normal(
	xs: { number },
	ys: { number },
	zs: { number },
	rs: { number },
	idx: { number },
	n: number,
	px: number,
	py: number,
	pz: number,
	ox: number,
	oy: number,
	oz: number,
	role: number
): (number, number, number)
	if role == Smooth.ROLE_OWN or role == Smooth.ROLE_NONE or n == 0 then
		return ox, oy, oz
	end
	local sx, sy, sz, wsum = 0, 0, 0, 0
	local reach = Smooth.REACH
	for k = 1, n do
		local i = idx[k]
		local dx, dy, dz = px - xs[i], py - ys[i], pz - zs[i]
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		if dist > 1e-6 then
			local r = rs[i]
			local d = dist - r
			local lim = r * reach
			if d < lim then
				local w = if d <= 0 then 1 else 1 - d / lim
				w *= w
				sx += w * dx / dist
				sy += w * dy / dist
				sz += w * dz / dist
				wsum += w
			end
		end
	end
	if wsum <= 1e-6 then
		return ox, oy, oz
	end
	if role == Smooth.ROLE_FOLLOW then
		-- (a piece on the body: the body's normal where it lies on it, its own where it stands off it)
		local a = math.min(1, wsum)
		local len = math.sqrt(sx * sx + sy * sy + sz * sz)
		if len <= 1e-6 then
			return ox, oy, oz
		end
		sx, sy, sz = ox * (1 - a) + sx / len * a, oy * (1 - a) + sy / len * a, oz * (1 - a) + sz / len * a
	end
	local len = math.sqrt(sx * sx + sy * sy + sz * sz)
	if len <= 1e-6 then
		return ox, oy, oz
	end
	return sx / len, sy / len, sz / len
end

------------------------------------------------------------------ pieces on smooth solids
Smooth.SOLID_STRIDE = 18
Smooth.SOLID_REACH = 0.12 -- studs off a solid's surface a piece still takes its normal (fading out by then)

-- kind: 1 an ellipsoid, 2 an egg (prm its split), 4 and 5 the halves of a cut egg (prm packed: Render/Raster)
function Smooth.packSolid(S: { number }, k: number, cf12: { number }, sx: number, sy: number, sz: number, kind: number, prm: number?)
	local o = k * Smooth.SOLID_STRIDE
	S[o + 1], S[o + 2], S[o + 3] = cf12[1], cf12[2], cf12[3]
	for i = 4, 12 do
		S[o + i] = cf12[i]
	end
	local hy = sy * 0.5
	local ibTop, ibBot, ye = 1 / hy, 1 / hy, 0
	if kind == 2 or kind == 4 or kind == 5 then
		local packed = prm or 0.5
		if kind ~= 2 then
			packed -= math.floor(packed / 10) * 10
		end
		local f = math.clamp(packed, 0.2, 0.8)
		ibTop, ibBot, ye = 1 / (sy * f), 1 / (sy * (1 - f)), hy - sy * f
	end
	S[o + 13] = 2 / sx
	S[o + 14] = ibTop
	S[o + 15] = 2 / sz
	S[o + 16] = ye
	S[o + 17] = ibBot
	S[o + 18] = math.max(sx, sy, sz) * 0.5 -- (its reach, for picking the ones near a piece)
end

function Smooth.onSolids(S: { number }, idx: { number }, n: number, px: number, py: number, pz: number): (number, number, number, number)
	local best = math.huge
	local bx, by, bz = 0, 1, 0
	local stride = Smooth.SOLID_STRIDE
	for j = 1, n do
		local o = (idx[j] - 1) * stride
		local dx, dy, dz = px - S[o + 1], py - S[o + 2], pz - S[o + 3]
		-- in its frame (its axes are the columns of the rotation)
		local lx = dx * S[o + 4] + dy * S[o + 7] + dz * S[o + 10]
		local ly = dx * S[o + 5] + dy * S[o + 8] + dz * S[o + 11] - S[o + 16]
		local lz = dx * S[o + 6] + dy * S[o + 9] + dz * S[o + 12]
		local ia, ic = S[o + 13], S[o + 15]
		local ib = if ly >= 0 then S[o + 14] else S[o + 17]
		local qx, qy, qz = lx * ia, ly * ib, lz * ic
		local sl = math.sqrt(qx * qx + qy * qy + qz * qz)
		local gx, gy, gz = lx * ia * ia, ly * ib * ib, lz * ic * ic
		local gl = math.sqrt(gx * gx + gy * gy + gz * gz)
		if gl > 1e-9 and sl > 1e-9 then
			-- (how far off its surface: the level's step over the gradient's length)
			local dist = math.abs(sl - 1) * sl / gl
			if dist < best then
				best = dist
				local wx = S[o + 4] * gx + S[o + 5] * gy + S[o + 6] * gz
				local wy = S[o + 7] * gx + S[o + 8] * gy + S[o + 9] * gz
				local wz = S[o + 10] * gx + S[o + 11] * gy + S[o + 12] * gz
				local l = math.sqrt(wx * wx + wy * wy + wz * wz)
				bx, by, bz = wx / l, wy / l, wz / l
			end
		end
	end
	if best == math.huge then
		return 0, 1, 0, 0
	end
	local w = 1 - math.clamp(best / Smooth.SOLID_REACH, 0, 1)
	return bx, by, bz, w
end

return Smooth
