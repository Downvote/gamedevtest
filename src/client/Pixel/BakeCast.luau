--!strict
--!native
-- One orthographic pixel ray of the static bake (ARCHITECTURE 11.6, REWORK2 1.3). OWNER: WP8.
-- Shared by PixelRenderer (main thread) and BakeWorker (Actors, in parallel): it only calls workspace:Raycast and
-- reads part properties, which are both safe in parallel.
--
-- Progressive passes: pass 1 casts one ray per 4x4 block, pass 2 one per 2x2 block, pass 3 every pixel, over a rect
-- of global art pixels (the layer at the camera's pan; Raster.gridCam). The blocks sit on the global grid (a pass's
-- first block starts at a multiple of 4), so the result does not depend on the pan. A pass enumerates the samples of
-- its grid row by row (BakeCast.sample) and skips the ones an earlier pass already cast. Sun visibility is cast once
-- per 2x2 block, at its anchor (the global even-even pixel, always a pass 1 or pass 2 sample); the other three
-- pixels of the block ask for it with LIT_UNKNOWN and the main thread copies it when they show the same part and
-- normal, or casts their own shadow ray when they do not. All coordinates here are global (they may be negative).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shading = require(ReplicatedStorage.Shared.Render.Shading)

local BakeCast = {}

BakeCast.STEPS = { 4, 2, 1 } -- block size of each pass
BakeCast.LIT_UNKNOWN = 255 -- "faces the sun, visibility not cast yet"
BakeCast.SKY_NORMAL = 13 -- normal index stored for a miss (decodes as up)
BakeCast.SHADOW_RAY = 120 -- sun visibility ray length (studs)
BakeCast.MAX_HOPS = 4 -- hops past invisible and see-through parts per pixel ray
BakeCast.CLEAR_MIN = 0.05 -- parts at this Transparency or more are looked through (below 0.95 they tint)
BakeCast.INVISIBLE = 0.95 -- parts at this Transparency or more are not drawn at all

-- Shadow modes for cast(): no test (lit), test now, or defer to the 2x2 block's top-left pixel.
BakeCast.SHADOW_OFF = 0
BakeCast.SHADOW_TEST = 1
BakeCast.SHADOW_DEFER = 2

local MAX_HOPS = BakeCast.MAX_HOPS
local CLEAR_MIN = BakeCast.CLEAR_MIN
local INVISIBLE = BakeCast.INVISIBLE
local SHADOW_RAY = BakeCast.SHADOW_RAY
local LIT_UNKNOWN = BakeCast.LIT_UNKNOWN

-- Was sample (x, y) (global px) already cast by an earlier pass?
function BakeCast.skip(pass: number, x: number, y: number): boolean
	if pass == 2 then
		return x % 4 == 0 and y % 4 == 0
	elseif pass == 3 then
		return x % 2 == 0 and y % 2 == 0
	end
	return false
end

-- Shadow mode for sample (x, y) (global px) of a bake pass: the 2x2 anchor tests, the others defer to it.
function BakeCast.shadowMode(shadows: boolean, x: number, y: number): number
	if not shadows then
		return BakeCast.SHADOW_OFF
	elseif x % 2 == 0 and y % 2 == 0 then
		return BakeCast.SHADOW_TEST
	end
	return BakeCast.SHADOW_DEFER
end

-- Sample k of a pass with step `st` over the global rect rx0..rx1 x ry0..ry1, whose sample grid (gx samples a row)
-- starts at (ox, oy): the global pixel it casts, its shadow mode and its block's top-left (bx, by); the pixel is nil
-- when the sample casts nothing (an earlier pass's sample, or beyond the rect). A block that starts left of or above
-- the rect casts at its first pixel inside it instead, with its own shadow ray: a stand-in that a later pass replaces.
function BakeCast.sample(
	pass: number,
	k: number,
	gx: number,
	st: number,
	ox: number,
	oy: number,
	rx0: number,
	ry0: number,
	rx1: number,
	ry1: number,
	shadows: boolean
): (number?, number, number, number, number)
	local bx, by = ox + (k % gx) * st, oy + (k // gx) * st
	local x, y = math.max(bx, rx0), math.max(by, ry0)
	if x > rx1 or y > ry1 then
		return nil, 0, 0, bx, by
	end
	if x == bx and y == by then
		if BakeCast.skip(pass, x, y) then
			return nil, 0, 0, bx, by
		end
		return x, y, BakeCast.shadowMode(shadows, x, y), bx, by
	end
	return x, y, if shadows then BakeCast.SHADOW_TEST else BakeCast.SHADOW_OFF, bx, by
end

-- Cast one pixel ray from `origin` along the unit `dir` for `far` studs. Parts at Transparency >= 0.95 that are
-- still queryable are looked through; see-through parts (0.05 <= Transparency < 0.95) are looked through as well
-- and the first one is returned as the tint (the caller blends its colour over what is behind). A see-through part
-- with nothing behind it (or past the last hop) is the hit itself. Returns the hit part (nil = sky), the depth along
-- the ray, the quantised normal index, the sun visibility (0 in shadow, 1 lit, LIT_UNKNOWN when deferred), the
-- number of rays cast and the tint part (nil when none).
function BakeCast.cast(
	params: RaycastParams,
	origin: Vector3,
	dir: Vector3,
	far: number,
	shadow: number,
	sun: Vector3
): (BasePart?, number, number, number, number, BasePart?)
	local res = workspace:Raycast(origin, dir * far, params)
	local rays = 1
	local travelled = 0
	local hops = 0
	local tint: BasePart? = nil
	local tintRes: RaycastResult? = nil
	local tintAt = 0
	while res ~= nil do
		local tr = res.Instance.Transparency
		if tr < CLEAR_MIN then
			break
		end
		if tr < INVISIBLE and tint == nil then
			tint, tintRes, tintAt = res.Instance, res, travelled
		end
		if hops >= MAX_HOPS then
			res = nil
			break
		end
		travelled += res.Distance + 0.02
		hops += 1
		if travelled >= far then
			res = nil
			break
		end
		res = workspace:Raycast(origin + dir * travelled, dir * (far - travelled), params)
		rays += 1
	end
	if res == nil and tintRes ~= nil then
		-- nothing opaque behind the see-through part: it is what this pixel shows
		res, travelled, tint = tintRes, tintAt, nil
	end
	if res == nil then
		return nil, far, BakeCast.SKY_NORMAL, 1, rays, nil
	end
	local n = res.Normal
	local ni = Shading.normalIndex(n.X, n.Y, n.Z)
	local lit = 1
	if shadow ~= BakeCast.SHADOW_OFF and n:Dot(sun) > 0 then
		if shadow == BakeCast.SHADOW_TEST then
			rays += 1
			lit = if workspace:Raycast(res.Position + n * 0.05, sun * SHADOW_RAY, params) then 0 else 1
		else
			lit = LIT_UNKNOWN
		end
	end
	return res.Instance, travelled + res.Distance, ni, lit, rays, tint
end

-- Sun visibility of a surface point (0 in shadow, 1 lit).
function BakeCast.sunVisible(params: RaycastParams, pos: Vector3, normal: Vector3, sun: Vector3): number
	return if workspace:Raycast(pos + normal * 0.05, sun * SHADOW_RAY, params) then 0 else 1
end

return BakeCast
