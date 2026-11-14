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

return Smooth
