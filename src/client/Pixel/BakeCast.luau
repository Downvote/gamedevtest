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
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local BakeCast = {}

BakeCast.STEPS = { 4, 2, 1 } -- block size of each pass
BakeCast.LIT_UNKNOWN = 255 -- "faces the sun, visibility not cast yet"
BakeCast.SKY_NORMAL = 13 -- normal index stored for a miss (decodes as up)
BakeCast.SHADOW_RAY = 120 -- sun visibility ray length (studs)
BakeCast.MAX_HOPS = 4 -- hops past invisible and see-through parts per pixel ray
BakeCast.CLEAR_MIN = 0.05 -- parts at this Transparency or more are looked through (below 0.95 they tint)
BakeCast.INVISIBLE = 0.95 -- parts at this Transparency or more are not drawn at all
-- Nothing static stands higher than this (studs): a pixel ray starts where it comes down through it, not at the ray
-- plane hundreds of studs up. Roblox tests a ray against a ball in single precision, and from 500 studs off the test
-- of whether it grazes a ball a quarter of a stud across was no better than the ball's own size: the edges of the
-- Tree of Life's fruit, blossom and vine flowers came out as a fuzz of loose pixels and its strands' joints as a
-- speckle (the reports of 2026-11-20, "the tree is the only thing that has this problem", "the fruits seem to be
-- affected the most"; the preview harness worked in doubles and never showed it: its "f32:" scenarios do). From
-- here the error is a tenth of what it was and less: at most a hair of a pixel.
BakeCast.RAY_TOP = Tuning.PixelRayTop

-- Shadow modes for cast(): no test (lit), test now, or defer to the 2x2 block's top-left pixel.
BakeCast.SHADOW_OFF = 0
BakeCast.SHADOW_TEST = 1
BakeCast.SHADOW_DEFER = 2

local MAX_HOPS = BakeCast.MAX_HOPS
local CLEAR_MIN = BakeCast.CLEAR_MIN
local INVISIBLE = BakeCast.INVISIBLE
local SHADOW_RAY = BakeCast.SHADOW_RAY
local LIT_UNKNOWN = BakeCast.LIT_UNKNOWN
local RAY_TOP = BakeCast.RAY_TOP

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
-- number of rays cast, the tint part (nil when none) and whether the face hit faces the sun (false when the shadow
-- mode is SHADOW_OFF: not asked).
function BakeCast.cast(
	params: RaycastParams,
	origin: Vector3,
	dir: Vector3,
	far: number,
	shadow: number,
	sun: Vector3
): (BasePart?, number, number, number, number, BasePart?, boolean)
	-- (start where the ray comes down through RAY_TOP: the depth still counts from the ray plane)
	local t0 = 0
	if dir.Y < -1e-3 and origin.Y > RAY_TOP then
		t0 = math.min(far, (origin.Y - RAY_TOP) / -dir.Y)
	end
	local res = workspace:Raycast(if t0 > 0 then origin + dir * t0 else origin, dir * (far - t0), params)
	if res == nil then
		return nil, far, BakeCast.SKY_NORMAL, 1, 1, nil, false
	end
	-- (each of a result's properties read once: every read crosses into the engine)
	local hit = res.Instance :: BasePart
	local dist = res.Distance
	local rays = 1
	local travelled = t0
	local tint: BasePart? = nil
	local tintRes: RaycastResult? = nil
	local tintAt, tintDist = 0, 0
	local tr = hit.Transparency
	if tr >= CLEAR_MIN then
		local hops = 0
		while true do
			if tr < INVISIBLE and tint == nil then
				tint, tintRes, tintAt, tintDist = hit, res, travelled, dist
			end
			if hops >= MAX_HOPS then
				res = nil
				break
			end
			travelled += dist + 0.02
			hops += 1
			if travelled >= far then
				res = nil
				break
			end
			res = workspace:Raycast(origin + dir * travelled, dir * (far - travelled), params)
			rays += 1
			if res == nil then
				break
			end
			hit, dist = res.Instance :: BasePart, res.Distance
			tr = hit.Transparency
			if tr < CLEAR_MIN then
				break
			end
		end
		if res == nil then
			if tintRes == nil then
				return nil, far, BakeCast.SKY_NORMAL, 1, rays, nil, false
			end
			-- nothing opaque behind the see-through part: it is what this pixel shows
			res, hit, dist, travelled, tint = tintRes, tint :: BasePart, tintDist, tintAt, nil
		end
	end
	local r = res :: RaycastResult
	local n = r.Normal
	local ni = Shading.normalIndex(n.X, n.Y, n.Z)
	local lit = 1
	local face = false
	if shadow ~= BakeCast.SHADOW_OFF and n:Dot(sun) > 0 then
		face = true
		if shadow == BakeCast.SHADOW_TEST then
			rays += 1
			lit = if workspace:Raycast(r.Position + n * 0.05, sun * SHADOW_RAY, params) then 0 else 1
		else
			lit = LIT_UNKNOWN
		end
	end
	return hit, travelled + dist, ni, lit, rays, tint, face
end

-- Sun visibility of a surface point (0 in shadow, 1 lit).
function BakeCast.sunVisible(params: RaycastParams, pos: Vector3, normal: Vector3, sun: Vector3): number
	return if workspace:Raycast(pos + normal * 0.05, sun * SHADOW_RAY, params) then 0 else 1
end

return BakeCast
