-- tests/specs/Smooth.spec.luau: smooth shading across a model's balls (Render/Smooth): a lone ball keeps its own
-- normal, where two balls meet the light runs across the join instead of creasing, a piece lying on the body takes
-- the body's normal and one standing off it keeps its own, an eye or a gem keeps its own, and only balls within reach
-- are asked; the fine normals (Render/Shading) are unit vectors, found back from their own direction, never coarse.
local T = require("../TestKit")
local Smooth = require("../../build/luautest/shared/Render/Smooth")
local Shading = require("../../build/luautest/shared/Render/Shading")

local function dot(ax: number, ay: number, az: number, bx: number, by: number, bz: number): number
	return ax * bx + ay * by + az * bz
end

return function()
	T.it("a lone ball keeps its own normal", function()
		local xs, ys, zs, rs = { 0 }, { 0 }, { 0 }, { 1 }
		local idx = {}
		local n = Smooth.near(xs, ys, zs, rs, 1, 0.6, 0.8, 0, 0, idx)
		T.eq(n, 1)
		local nx, ny, nz = Smooth.normal(xs, ys, zs, rs, idx, n, 0.6, 0.8, 0, 0.6, 0.8, 0, Smooth.ROLE_BALL)
		T.near(nx, 0.6, 1e-6)
		T.near(ny, 0.8, 1e-6)
		T.near(nz, 0, 1e-6)
	end)

	T.it("where two balls meet the light runs across the join", function()
		-- two balls of radius 1, centres 1.2 apart along x: their surfaces cross at x = 0.6, y = 0.8
		local xs, ys, zs, rs = { 0, 1.2 }, { 0, 0 }, { 0, 0 }, { 1, 1 }
		local idx = {}
		local n = Smooth.near(xs, ys, zs, rs, 2, 0.6, 0.8, 0, 0, idx)
		T.eq(n, 2)
		-- (each ball alone would tilt the normal 37 degrees to one side; smooth, it points straight up the join)
		local nx, ny = Smooth.normal(xs, ys, zs, rs, idx, n, 0.6, 0.8, 0, 0.6, 0.8, 0, Smooth.ROLE_BALL)
		T.near(nx, 0, 1e-6)
		T.near(ny, 1, 1e-6)
		-- half way from the first ball's top to the join (its own normal 0.3 across): softened, still its own way round
		local px, py = 0.3, math.sqrt(1 - 0.09)
		n = Smooth.near(xs, ys, zs, rs, 2, px, py, 0, 0, idx)
		local sx = Smooth.normal(xs, ys, zs, rs, idx, n, px, py, 0, px, py, 0, Smooth.ROLE_BALL)
		T.truthy(sx > 0.1 and sx < 0.3, "between its own and the join's: " .. sx)
		-- on its far side, out of the second's reach: its own
		n = Smooth.near(xs, ys, zs, rs, 2, -0.6, 0.8, 0, 0, idx)
		local fx, fy = Smooth.normal(xs, ys, zs, rs, idx, n, -0.6, 0.8, 0, -0.6, 0.8, 0, Smooth.ROLE_BALL)
		T.near(fx, -0.6, 1e-6)
		T.near(fy, 0.8, 1e-6)
	end)

	T.it("a piece lying on the body shades with it; one standing off it keeps its own; an eye keeps its own", function()
		local xs, ys, zs, rs = { 0 }, { 0 }, { 0 }, { 1 }
		local idx = {}
		-- a flat spot at the top of the ball whose own normal points sideways (a disc set a little askew)
		local n = Smooth.near(xs, ys, zs, rs, 1, 0, 1.01, 0, 0, idx)
		local fx, fy = Smooth.normal(xs, ys, zs, rs, idx, n, 0, 1.01, 0, 1, 0, 0, Smooth.ROLE_FOLLOW)
		T.truthy(fy > 0.95 and math.abs(fx) < 0.3, "the body's normal under it: " .. fx .. ", " .. fy)
		-- far off the ball (out of its reach): its own
		n = Smooth.near(xs, ys, zs, rs, 1, 0, 3, 0, 0, idx)
		local ox, oy = Smooth.normal(xs, ys, zs, rs, idx, n, 0, 3, 0, 1, 0, 0, Smooth.ROLE_FOLLOW)
		T.near(ox, 1, 1e-6)
		T.near(oy, 0, 1e-6)
		-- an eye on the body: its own, always
		n = Smooth.near(xs, ys, zs, rs, 1, 0, 1, 0, 0, idx)
		local ex = Smooth.normal(xs, ys, zs, rs, idx, n, 0, 1, 0, 1, 0, 0, Smooth.ROLE_OWN)
		T.eq(ex, 1)
		T.eq(Smooth.role(true, true, false), Smooth.ROLE_OWN)
		T.eq(Smooth.role(true, false, true), Smooth.ROLE_FOLLOW)
		T.eq(Smooth.role(false, false, false), Smooth.ROLE_FOLLOW)
		T.eq(Smooth.role(true, false, false), Smooth.ROLE_BALL)
	end)

	T.it("only balls within reach are asked", function()
		local xs, ys, zs, rs = { 0, 10, 0.3 }, { 0, 0, 0.9 }, { 0, 0, 0 }, { 1, 1, 0.2 }
		local idx = { 9, 9, 9, 9 }
		local n = Smooth.near(xs, ys, zs, rs, 3, 0, 1, 0, 0.2, idx)
		T.eq(n, 2)
		T.eq(idx[1], 1)
		T.eq(idx[2], 3)
		T.eq(idx[3], nil, "the list is cut to what was found")
	end)

	T.it("fine normals: unit vectors over the whole sphere, found back from themselves, never a coarse index", function()
		T.eq(Shading.FINE0, 27)
		for i = 27, 255 do
			local x, y, z = Shading.normalVec(i)
			T.near(math.sqrt(x * x + y * y + z * z), 1, 1e-6)
			T.eq(Shading.fineIndex(x, y, z), i)
		end
		-- (no direction is far from a fine one: a smooth surface steps in small steps)
		local worst = 1
		for k = 0, 199 do
			local a, b = k * 2.399963, 1 - (k + 0.5) / 100
			local r = math.sqrt(math.max(0, 1 - b * b))
			local x, y, z = math.cos(a) * r, b, math.sin(a) * r
			local fx, fy, fz = Shading.normalVec(Shading.fineIndex(x, y, z))
			worst = math.min(worst, dot(x, y, z, fx, fy, fz))
		end
		T.truthy(worst > math.cos(math.rad(12)), "within 12 degrees: " .. math.deg(math.acos(worst)))
		T.truthy(Shading.fineIndex(0, 1, 0) >= 27, "the top is fine too")
	end)
end
