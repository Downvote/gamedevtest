--!strict
-- The driftlings' building kit (Models/DriftModels; GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module (client).
--
-- The request (2026-11-13): "The creatures look blocky and unrealistic. Look at the cakes in the bakery game to
-- reference how detailed they should be". So a driftling is built the way the bakery builds a cake: round pieces on a
-- fine grid (0.05 studs, the bakery's FoodKit fine grid) and many small ones, not boxes. Bodies, necks, limbs, tails,
-- ears and horns are tubes of overlapping balls along a curve with a radius that tapers along it (`tube`); flattened
-- round shapes (a shell, a pad, a cap) are a disc with a ring of balls round its rim (`pillow`); spots, blush, a belly
-- patch, the eyes' parts and stripes are flat discs on the surface (`disc`); leaves, feathers and fins are thin
-- wedges and discs. Eyes (`eye`) are a dark oval with an iris low in it and two shines, and a lid (an arc) that shows
-- when the eye shuts. A closed mouth is a little smile; the open one (`mouth`) shows when the jaw opens.
--
-- Two levels of detail: "full" (the hatch scene, the portraits, close looks: 80 to 200 parts) and "world" (the
-- islands, where a driftling is 15 or 20 art px tall and dozens walk about: the same shapes with fewer, larger balls
-- and no pieces too small to read, 30 to 70 parts). Builders ask `Kit.full()` and pass `detail` to the helpers for the
-- pieces that only a close look shows (fur tufts, toe beads, the second shine, seeds of a spot pattern).
--
-- Every part goes on the current joint of the current thing (`J` makes a joint and makes it current, `on` picks one).
-- Face parts (eyes, lids, shines, irises, mouths, smiles) are made facing out (their local +X along the surface
-- normal) and listed in the thing's `face` table with what they do: "eye" (tucked in when the eye shuts), "lid"
-- (out only while it is shut), "open" (out only while the mouth is open) and "closed" (out only while it is shut);
-- DriftModels.animate tucks a part TUCK studs in along its normal.
local Blocks = require(script.Parent.Blocks)

local Kit = {}

export type Joint = { parent: string?, pivot: Vector3, kind: string, side: number, phase: number }
export type Rig = {
	joints: { [string]: Joint },
	order: { string }, -- parents before children
	of: { [string]: string }, -- part name -> its joint
	gait: string, -- "quad" | "biped" | "hop" | "scuttle" | "slither" | "fly"
	world: { [string]: CFrame }, -- each joint's pose now (animate)
}
export type Thing = {
	model: Model,
	parts: { [string]: BasePart },
	rest: { [string]: CFrame },
	sizes: { [string]: Vector3 },
	baseRest: { [string]: CFrame },
	baseSize: { [string]: Vector3 },
	colors: { [string]: Color3 },
	face: { [string]: string }, -- face part name -> "eye" | "lid" | "open" | "closed"
	h: number,
	r: number,
	kind: string,
	lod: string, -- "full" | "world"
	rig: Rig?,
}

local V = Vector3.new
Kit.R = math.rad
Kit.V = V
Kit.TUCK = 0.14 -- studs a face part sinks in when it is hidden
-- Render/Raster draws a part over another only where it is more than 0.03 studs nearer; a face's layers (the eye on the
-- head, the iris on the eye, the shine on both) each step out by this much, and a ball's size snaps up to 0.05 too
Kit.BIAS = 0.04

local FINE = 0.05
local cur: Thing? = nil -- the thing being built
local curJoint = "body" -- the joint new parts go on
local isFull = true

local function fine(v: number): number
	return math.max(FINE, math.floor(v / FINE + 0.5) * FINE)
end
Kit.fine = fine

function Kit.new(shape: string, h: number, r: number, gait: string): Thing
	local m = Blocks.model(nil, "Micro_drift_" .. shape)
	local t: Thing = {
		model = m,
		parts = {},
		rest = {},
		sizes = {},
		baseRest = {},
		baseSize = {},
		colors = {},
		face = {},
		h = h,
		r = r,
		kind = "drift_" .. shape,
		lod = if isFull then "full" else "world",
		rig = { joints = {}, order = {}, of = {}, gait = gait, world = {} },
	}
	cur = t
	curJoint = "body"
	return t
end

-- The level of detail of the next things built (DriftModels.build sets it).
function Kit.setFull(on: boolean)
	isFull = on
end

-- Whether the thing being built is the full one (close looks), not the islands' lighter one.
function Kit.full(): boolean
	return isFull
end

-- Done building: the thing, and the builder let go.
function Kit.finish(): Thing
	local t = cur :: Thing
	cur = nil
	return t
end

-- A joint (and the one new parts go on from now): its pivot in the thing's space, its parent, what moves it.
function Kit.J(name: string, parent: string?, pivot: Vector3, kind: string, side: number?, phase: number?)
	local t = cur :: Thing
	local rig = t.rig :: Rig
	rig.joints[name] = { parent = parent, pivot = pivot, kind = kind, side = side or 0, phase = phase or 0 }
	table.insert(rig.order, name)
	curJoint = name
end

function Kit.on(name: string)
	curJoint = name
end

-- One part on the current joint: `cf` its centre and turn, sizes on the fine grid (a Ball's diameter is its smallest
-- side, a Cylinder runs along its X). Names repeat with a number (Toe, Toe2, Toe3).
function Kit.part(name: string, shape: string, size: Vector3, cf: CFrame, color: string, neon: boolean?): BasePart
	local t = cur :: Thing
	local n = name
	local i = 2
	while t.parts[n] do
		n = name .. i
		i += 1
	end
	local shp: any = if shape == "Block" then nil else shape
	local p = Blocks.part(t.model, { size = size, cf = cf, color = color, name = n, shape = shp, collide = false, query = false, neon = neon })
	if shape == "Ball" then
		local d = fine(math.min(size.X, size.Y, size.Z))
		p.Size = V(d, d, d)
	else
		p.Size = V(fine(size.X), fine(size.Y), fine(size.Z))
	end
	p.CastShadow = false
	t.parts[n] = p
	t.rest[n] = cf
	t.sizes[n] = p.Size
	t.baseRest[n] = cf
	t.baseSize[n] = p.Size
	t.colors[n] = p.Color
	;(t.rig :: Rig).of[n] = curJoint
	return p
end

-- The old form: a part centred at `at`, turned by `rot` about its centre.
function Kit.P(name: string, shape: string, size: Vector3, at: Vector3, color: string, rot: CFrame?, neon: boolean?): BasePart
	return Kit.part(name, shape, size, CFrame.new(at) * (rot or CFrame.identity), color, neon)
end

-- A part only the full thing has (nil on the islands' one).
function Kit.D(name: string, shape: string, size: Vector3, at: Vector3, color: string, rot: CFrame?, neon: boolean?): BasePart?
	if not isFull then
		return nil
	end
	return Kit.P(name, shape, size, at, color, rot, neon)
end

function Kit.keep(p: BasePart): BasePart
	p:SetAttribute("Keep", true)
	return p
end

-- A frame at `at` whose +X points along `dir` (a Cylinder made in it lies along dir; a disc faces it).
local function along(at: Vector3, dir: Vector3): CFrame
	local d = if dir.Magnitude > 1e-6 then dir.Unit else V(0, 0, 1)
	local up = if math.abs(d.Y) > 0.98 then V(0, 0, 1) else V(0, 1, 0)
	return CFrame.lookAt(at, at + d, up) * CFrame.Angles(0, math.pi / 2, 0)
end
Kit.along = along

-- A ball of diameter d at `at` (`detail`: the full thing only).
function Kit.ball(name: string, at: Vector3, d: number, color: string, detail: boolean?, neon: boolean?): BasePart?
	if detail and not isFull then
		return nil
	end
	return Kit.part(name, "Ball", V(d, d, d), CFrame.new(at), color, neon)
end

-- A flat disc of diameter d and thickness th facing `normal` at `at` (a spot, blush, an eye's part). On a ball of
-- radius `onR` it sinks in by the curve's sag so its rim lies on the surface, not in the air.
-- `lift` sets it that much further out (the picture draws a part over another only where it is more than
-- Kit.BIAS nearer: a face's layers each step out by more than that).
function Kit.disc(name: string, at: Vector3, normal: Vector3, d: number, th: number, color: string, detail: boolean?, onR: number?, neon: boolean?, lift: number?): BasePart?
	if detail and not isFull then
		return nil
	end
	local n = if normal.Magnitude > 1e-6 then normal.Unit else V(0, 0, 1)
	local sag = 0
	if onR and onR > d / 2 then
		sag = onR - math.sqrt(onR * onR - (d / 2) ^ 2)
	end
	local c = at + n * (th / 2 - sag * 0.8 + (lift or 0))
	return Kit.part(name, "Cylinder", V(th, d, d), along(c, n), color, neon)
end

-- A rod (cylinder) of diameter d from a to b.
function Kit.rod(name: string, a: Vector3, b: Vector3, d: number, color: string, detail: boolean?, neon: boolean?): BasePart?
	if detail and not isFull then
		return nil
	end
	local len = (b - a).Magnitude
	if len < 1e-4 then
		return nil
	end
	return Kit.part(name, "Cylinder", V(len, d, d), along((a + b) / 2, b - a), color, neon)
end

-- A flat pointed blade (a leaf, a feather, a fin, a spike, a claw) from `base` to `tip`: a triangle `w` wide at the
-- base and `th` thick, its flat side facing `normal`. Two mirrored half wedges (a Wedge is full height at its +Z end
-- and nothing at its -Z end, in Roblox and in Render/Raster): each lies with its square edge along the blade's middle
-- line, its +Z toward the base.
function Kit.blade(name: string, base: Vector3, tip: Vector3, w: number, th: number, normal: Vector3, color: string, detail: boolean?): BasePart?
	if detail and not isFull then
		return nil
	end
	local d = tip - base
	local len = d.Magnitude
	if len < 1e-4 then
		return nil
	end
	local fwd = d.Unit
	local n = normal - fwd * normal:Dot(fwd)
	n = if n.Magnitude > 1e-6 then n.Unit else V(0, 1, 0)
	local across = fwd:Cross(n)
	local mid = (base + tip) / 2
	local first: BasePart? = nil
	for _, s in { 1, -1 } do
		local y = across * s
		-- (X along the normal, Y out from the middle line, Z toward the base: X x Y = Z, so X flips with s)
		local cf = CFrame.fromMatrix(mid + y * (w / 4), -n * s, y, -fwd)
		local p = Kit.part(name, "Wedge", V(th, w / 2, len), cf, color)
		first = first or p
	end
	return first
end

-- Catmull-Rom point on the curve through pts at u in [0, 1] (by segment).
local function curveAt(pts: { Vector3 }, u: number): Vector3
	local n = #pts
	if n == 1 then
		return pts[1]
	end
	local f = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(math.floor(f), n - 2)
	local s = f - i
	local p1, p2 = pts[i + 1], pts[i + 2]
	local p0 = pts[i] or (p1 * 2 - p2)
	local p3 = pts[i + 3] or (p2 * 2 - p1)
	local s2, s3 = s * s, s * s * s
	return 0.5 * ((2 * p1) + (-p0 + p2) * s + (2 * p0 - 5 * p1 + 4 * p2 - p3) * s2 + (-p0 + 3 * p1 - 3 * p2 + p3) * s3)
end
Kit.curveAt = curveAt

-- A smooth tube along the curve through `pts` (a limb, a neck, a tail, an ear, a horn), its radius going from radii[1]
-- to radii[#radii] (spread evenly along it, one or more): a capsule chain, cylinders between points on the curve with a
-- ball at every joint, so its sides are smooth and its bends and ends round. More, shorter links on the full thing.
-- `step` scales the link length; `detail`: the full thing only. Returns the parts, joints and links.
function Kit.tube(name: string, pts: { Vector3 }, radii: { number }, color: string, step: number?, detail: boolean?, neon: boolean?): { BasePart }
	local out: { BasePart } = {}
	if detail and not isFull then
		return out
	end
	-- the curve's length, sampled
	local N = 32
	local acc = { 0 }
	local prev = curveAt(pts, 0)
	for i = 1, N do
		local q = curveAt(pts, i / N)
		acc[i + 1] = acc[i] + (q - prev).Magnitude
		prev = q
	end
	local total = acc[N + 1]
	local function radiusAt(u: number): number
		local k = #radii
		if k == 1 then
			return radii[1]
		end
		local f = math.clamp(u, 0, 1) * (k - 1)
		local i = math.min(math.floor(f), k - 2)
		local s = f - i
		return radii[i + 1] + (radii[i + 2] - radii[i + 1]) * s
	end
	local function uAtLen(l: number): number
		for i = 1, N do
			if acc[i + 1] >= l then
				local seg = acc[i + 1] - acc[i]
				local s = if seg > 0 then (l - acc[i]) / seg else 0
				return (i - 1 + s) / N
			end
		end
		return 1
	end
	local avg = 0
	for _, r in radii do
		avg += r
	end
	avg /= #radii
	-- links about this long (at least 0.3 studs: a thin tube in many links shows its joints), no fewer than the curve's
	-- own segments
	local link = math.max(0.3, avg * (if isFull then 2.6 else 4)) * (step or 1)
	local n = math.clamp(math.ceil(total / math.max(FINE, link)), math.max(1, #pts - 1), if isFull then 8 else 4)
	local q: { Vector3 } = {}
	local r: { number } = {}
	for i = 0, n do
		local u = uAtLen(total * i / n)
		q[i + 1] = curveAt(pts, u)
		r[i + 1] = radiusAt(u)
	end
	for i = 1, n + 1 do
		-- the ends round in full; a joint's ball a little thinner than its links, so it fills the bend's outer side
		-- without lying flush along them (two surfaces flush flicker against each other in the picture)
		local d = 2 * r[i] * (if i == 1 or i == n + 1 then 1 else 0.86)
		table.insert(out, Kit.part(name, "Ball", V(d, d, d), CFrame.new(q[i]), color, neon))
		if i <= n then
			local a, b = q[i], q[i + 1]
			local len = (b - a).Magnitude
			if len > FINE * 0.5 then
				local dc = r[i] + r[i + 1]
				table.insert(out, Kit.part(name, "Cylinder", V(len, dc, dc), along((a + b) / 2, b - a), color, neon))
			end
		end
	end
	return out
end

-- A flat strip along the curve through `pts` facing `normal` (the inside of an ear, a stripe, a belly's band, a
-- membrane's edge): overlapping discs as wide as `widths` says along it (spread evenly), all in one plane-ish.
function Kit.strip(name: string, pts: { Vector3 }, widths: { number }, normal: Vector3, color: string, detail: boolean?): { BasePart }
	local out: { BasePart } = {}
	if detail and not isFull then
		return out
	end
	local k = #widths
	local function widthAt(u: number): number
		if k == 1 then
			return widths[1]
		end
		local f = math.clamp(u, 0, 1) * (k - 1)
		local i = math.min(math.floor(f), k - 2)
		local s = f - i
		return widths[i + 1] + (widths[i + 2] - widths[i + 1]) * s
	end
	local total = 0
	local prev = curveAt(pts, 0)
	for i = 1, 16 do
		local q = curveAt(pts, i / 16)
		total += (q - prev).Magnitude
		prev = q
	end
	local avgW = 0
	for _, w in widths do
		avgW += w
	end
	avgW /= k
	local n = math.max(1, math.ceil(total / (avgW * (if isFull then 0.45 else 0.8))))
	for i = 0, n do
		local u = i / n
		local p = Kit.disc(name, curveAt(pts, u), normal, widthAt(u), 0.05, color)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- A flat strip lying on the front of a tube (the inside of an ear, a stripe down a tail): along the tube's centre curve
-- `pts` (radii `radii`, as given to `tube`), each disc set out past the tube's surface toward `normal` (taken square to
-- the tube at that point, so a leaning or bending tube keeps the strip clear of it), `widths` across.
function Kit.stripOn(name: string, pts: { Vector3 }, radii: { number }, widths: { number }, normal: Vector3, color: string, detail: boolean?): { BasePart }
	local out: { BasePart } = {}
	if detail and not isFull then
		return out
	end
	local function lerpList(list: { number }, u: number): number
		local k = #list
		if k == 1 then
			return list[1]
		end
		local f = math.clamp(u, 0, 1) * (k - 1)
		local i = math.min(math.floor(f), k - 2)
		local s = f - i
		return list[i + 1] + (list[i + 2] - list[i + 1]) * s
	end
	local total = 0
	local prev = curveAt(pts, 0)
	for i = 1, 16 do
		local q = curveAt(pts, i / 16)
		total += (q - prev).Magnitude
		prev = q
	end
	local avgW = 0
	for _, w in widths do
		avgW += w
	end
	avgW /= #widths
	local n = math.max(1, math.ceil(total / (avgW * (if isFull then 0.45 else 0.8))))
	local nn = normal.Unit
	for i = 0, n do
		local u = i / n
		local c = curveAt(pts, u)
		local tan = curveAt(pts, math.min(1, u + 0.02)) - curveAt(pts, math.max(0, u - 0.02))
		tan = if tan.Magnitude > 1e-5 then tan.Unit else V(0, 1, 0)
		local front = nn - tan * nn:Dot(tan)
		front = if front.Magnitude > 1e-5 then front.Unit else nn
		local w = lerpList(widths, u)
		-- (past the surface by the disc's own sag over the round tube, plus a little: never cut into it)
		local r = lerpList(radii, u)
		local sag = if r > w / 2 then r - math.sqrt(r * r - (w / 2) ^ 2) else r
		local p = Kit.disc(name, c + front * (r - sag + 0.03), front, w, 0.05, color)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- A flattened round shape (a shell, a cap, a pad, a face): a disc `h` thick with a ring of balls round its rim, so its
-- edge is round; `R` its radius, `up` the way it faces. Returns the disc.
function Kit.pillow(name: string, center: Vector3, R: number, h: number, up: Vector3, color: string, detail: boolean?): BasePart?
	if detail and not isFull then
		return nil
	end
	local u = up.Unit
	local inner = math.max(FINE, R - h / 2)
	local disc = Kit.part(name, "Cylinder", V(h, 2 * inner, 2 * inner), along(center, u), color)
	local a = if math.abs(u.Y) > 0.9 then V(1, 0, 0) else V(0, 1, 0)
	local e1 = (a - u * a:Dot(u)).Unit
	local e2 = u:Cross(e1)
	local n = math.max(6, math.ceil(2 * math.pi * inner / (h * (if isFull then 0.45 else 0.8))))
	for i = 0, n - 1 do
		local ang = i / n * 2 * math.pi
		local p = center + (e1 * math.cos(ang) + e2 * math.sin(ang)) * inner
		Kit.part(name .. "Rim", "Ball", V(h, h, h), CFrame.new(p), color)
	end
	return disc
end

-- An egg-round body (an ellipsoid with half sizes `half`, turned by `rot` about `center`): balls along its longest
-- axis, two or three side by side where it is much wider than deep, each slice's balls as big as the ellipsoid there.
function Kit.ovoid(name: string, center: Vector3, half: Vector3, color: string, rot: CFrame?, detail: boolean?): { BasePart }
	local out: { BasePart } = {}
	if detail and not isFull then
		return out
	end
	local R0 = rot or CFrame.identity
	-- the axes by length: a (longest), b, c (shortest)
	local axes = { { v = V(1, 0, 0), l = half.X }, { v = V(0, 1, 0), l = half.Y }, { v = V(0, 0, 1), l = half.Z } }
	table.sort(axes, function(p, q)
		return p.l > q.l
	end)
	local A, B, C = axes[1], axes[2], axes[3]
	-- across the middle axis: as many rows as it takes to span it with balls of the shortest's size
	local rows = if B.l > C.l * 1.35 then (if B.l > C.l * 2.2 then 3 else 2) else 1
	local reach = math.max(0, A.l - C.l) -- the end balls' centres stop short of the tip by about their radius
	local spacing = C.l * (if isFull then 0.55 else 0.9)
	local n = math.max(1, math.ceil(2 * reach / spacing))
	for i = 0, n do
		local s = if n > 0 then -1 + 2 * i / n else 0
		local along = s * reach
		local f = math.sqrt(math.max(0.05, 1 - (along / A.l) ^ 2))
		local rc = C.l * f -- this slice's depth radius
		local rb = B.l * f -- and width
		for j = 1, rows do
			local off = if rows == 1 then 0 else (-1 + 2 * (j - 1) / (rows - 1)) * math.max(0, rb - rc)
			local r = rc
			if rows == 1 then
				r = math.min(rb, rc)
			end
			local p = A.v * along + B.v * off
			local b = Kit.part(name, "Ball", V(2 * r, 2 * r, 2 * r), CFrame.new(center + R0:VectorToWorldSpace(p)), color)
			table.insert(out, b)
		end
	end
	return out
end

-- The point on a ball (centre c, radius r) in the direction `dir`, and the normal there.
function Kit.onBall(c: Vector3, r: number, dir: Vector3): (Vector3, Vector3)
	local d = dir.Unit
	return c + d * r, d
end

------------------------------------------------------------------ the face
local function facePart(kind: string, p: BasePart?)
	if p then
		local t = cur :: Thing
		t.face[p.Name] = kind
		Kit.keep(p)
	end
end

-- One eye (side "L" or "R") on a head ball (centre `hc`, radius `hr`) looking out along `dir` from its centre: a dark
-- oval `d` across (two discs, taller than wide), the iris (`iris` colour) low in it, a big shine up toward the light
-- (the picture's top left) and a small one under it, and the shut eye's lid: a curve of small balls.
function Kit.eye(side: string, hc: Vector3, hr: number, dir: Vector3, d: number, iris: string?, dark: string?)
	local at, n = Kit.onBall(hc, hr, dir)
	-- the frame on the surface: right (screen-ish x) and up
	local up0 = V(0, 1, 0)
	local right = up0:Cross(n)
	right = if right.Magnitude > 1e-4 then right.Unit else V(1, 0, 0)
	local up = n:Cross(right).Unit
	local th = 0.05
	local col = dark or "black"
	local B = Kit.BIAS
	facePart("eye", Kit.disc("Eye" .. side, at + up * d * 0.12, n, d * 0.92, th, col, false, hr, nil, B))
	facePart("eye", Kit.disc("Eye" .. side, at - up * d * 0.14, n, d * 0.92, th, col, false, hr, nil, B))
	if iris and isFull then
		facePart("eye", Kit.disc("Iris" .. side, at - up * d * 0.2, n, d * 0.5, th, iris, true, hr, nil, 2 * B))
	end
	-- the shines: up and toward the light (the light comes from the screen's top left: -right on the left eye too)
	facePart("eye", Kit.disc("Shine" .. side, at + up * d * 0.2 - right * d * 0.16, n, math.max(0.1, d * 0.36), th, "white", false, hr, nil, 3 * B))
	facePart("eye", Kit.disc("Shine" .. side, at - up * d * 0.22 + right * d * 0.18, n, math.max(0.05, d * 0.16), th, "white", true, hr, nil, 3 * B))
	-- the lid: an arc bowing down (a content shut eye), hidden in the head until it shuts
	local m = if isFull then 3 else 2
	for i = 0, m - 1 do
		local s = if m == 1 then 0 else -1 + 2 * i / (m - 1)
		local p = at + right * s * d * 0.36 - up * (1 - s * s) * d * 0.12 + n * (Kit.BIAS + 0.02)
		local b = Kit.part("Lid" .. side, "Ball", V(d * 0.24, d * 0.24, d * 0.24), along(p, n), col)
		facePart("lid", b)
	end
end

-- A pair of eyes on a head ball, `spread` radians apart either side of `dir` (looking forward), tilted up by `lift`.
function Kit.eyes(hc: Vector3, hr: number, dir: Vector3, spread: number, lift: number, d: number, iris: string?, dark: string?)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local dd = (CFrame.Angles(0, side * spread, 0) * CFrame.Angles(-lift, 0, 0)):VectorToWorldSpace(dir.Unit)
		Kit.eye(s, hc, hr, dd, d, iris, dark)
	end
end

-- Blush: a pink disc on each cheek.
function Kit.blush(hc: Vector3, hr: number, dir: Vector3, spread: number, drop: number, d: number, color: string?)
	for _, side in { -1, 1 } do
		local dd = (CFrame.Angles(0, side * spread, 0) * CFrame.Angles(drop, 0, 0)):VectorToWorldSpace(dir.Unit)
		local at, n = Kit.onBall(hc, hr, dd)
		Kit.disc("Cheek" .. (if side < 0 then "L" else "R"), at, n, d, 0.05, color or "pink", false, hr, nil, Kit.BIAS)
	end
end

-- The mouth at `at` facing `n`, `w` wide: a small smile (two short dark rods meeting in a soft V), and the open mouth
-- (a dark oval with a tongue in it) hidden until the mouth opens.
function Kit.mouth(at: Vector3, n: Vector3, w: number, dark: string?, tongue: string?)
	local col = dark or "black"
	local nn = n.Unit
	local right = V(0, 1, 0):Cross(nn)
	right = if right.Magnitude > 1e-4 then right.Unit else V(1, 0, 0)
	local up = nn:Cross(right).Unit
	local th = math.max(0.05, w * 0.18)
	local mid = at - up * w * 0.08 + nn * (Kit.BIAS + 0.02)
	for _, side in { -1, 1 } do
		local a = mid + right * side * w * 0.5 + up * w * 0.12
		facePart("closed", Kit.rod("Smile", a, mid, th, col))
	end
	if isFull then
		facePart("open", Kit.disc("Mouth", at - up * w * 0.1, nn, w * 0.75, 0.05, col, false, nil, nil, Kit.BIAS))
		facePart("open", Kit.disc("MouthTongue", at - up * w * 0.22, nn, w * 0.42, 0.05, tongue or "berry_red", false, nil, nil, 2 * Kit.BIAS))
	else
		facePart("open", Kit.disc("Mouth", at - up * w * 0.1, nn, w * 0.6, 0.05, col, false, nil, nil, Kit.BIAS))
	end
end

-- Whiskers: thin pale rods fanning out from the muzzle (full only).
function Kit.whiskers(at: Vector3, len: number, color: string?)
	if not isFull then
		return
	end
	for _, side in { -1, 1 } do
		for i, a in { -12, 6 } do
			local dir = (CFrame.Angles(0, 0, side * Kit.R(a)) * CFrame.Angles(0, side * Kit.R(-20), 0)):VectorToWorldSpace(V(side, 0, 0))
			local base = at + V(side * 0.06, (i - 1.5) * 0.05, 0)
			Kit.rod("Whisker", base, base + dir * len, 0.05, color or "cream", true)
		end
	end
end

-- A row of toe beads at the front of a paw (centre `at`, `w` wide, facing +Z by `fwd`).
function Kit.toes(name: string, at: Vector3, w: number, d: number, n: number, color: string, fwd: Vector3?)
	if not isFull then
		return
	end
	local f = (fwd or V(0, 0, 1)).Unit
	local right = V(0, 1, 0):Cross(f).Unit
	for i = 0, n - 1 do
		local s = if n == 1 then 0 else -1 + 2 * i / (n - 1)
		Kit.ball(name, at + right * s * w * 0.5 + f * (1 - math.abs(s) * 0.3) * d * 0.3, d, color, true)
	end
end

-- A fluffy tuft: a few small balls round `at` (fur at a cheek, a tail's end, a chest ruff), `r` its size.
function Kit.tuft(name: string, at: Vector3, r: number, color: string, n: number?, detail: boolean?)
	if detail and not isFull then
		return
	end
	local k = n or (if isFull then 5 else 2)
	Kit.ball(name, at, r * 1.3, color)
	for i = 1, k - 1 do
		local a = i / (k - 1) * 2 * math.pi + 0.4
		local p = at + V(math.cos(a) * r * 0.55, math.sin(a * 1.7) * r * 0.35, math.sin(a) * r * 0.55)
		Kit.ball(name, p, r * 0.85, color, true)
	end
end

return Kit
