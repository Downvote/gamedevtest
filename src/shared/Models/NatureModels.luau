--!strict
-- The trees, plants and rocks of the Nature tab (GAME_DESIGN 4; Data/Buildings). Roblox module (server and client).
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- The view looks from +X +Z and down: the +Z faces show on the left (lit), the +X faces on the right (shaded), so
-- the telling details sit on those sides. Leaves in leaf / leaf_dark sway by themselves; blossom, autumn leaves and
-- snow on branches are marked to sway as well. A tree's crown may reach a little past its footprint, its trunk never.
-- A trunk is smooth (2026-11-13: "make the trunk connected smoothly as well without the stepped boxes"): one column
-- from the ground (on a flat plate of roots at most), or round segments joined by balls where it bends (`tube`),
-- never a stack of steps. Nothing reaches far below the ground: the pictures drawn from a model stand it on its box.
-- (Detailed again for the request of 2026-11-19, "detail all decor more, some having animations": crowns of layered
-- clumps with a lit top, roots, bark and knots on the trunks, chips, moss and lichen on the rocks, and small things at
-- their feet: tufts, pebbles, flowers, fallen leaves. A big canopy part is named "Leaves" or "Blossom" (it drops a leaf
-- or a petal now and then: Controllers/AmbientView), a flower head "Flower", "Bloom" or "Petals" (butterflies come to
-- it), a glowing bit "Sparkle" (it twinkles). Only the big outer clumps carry the canopy name, so one tree never takes
-- all of an island's falling leaves. A few pieces move (Parts.move): the Great Oak's swing, the sunflowers' heads, the
-- starfruit on their stalks, the fireflies over the glow mushrooms, a shard over the crystals, a bubble in the lava.)
local Blocks = require(script.Parent.Blocks)
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

local box, ball, cyl = Parts.box, Parts.ball, Parts.cyl
local V = Vector3.new
local TAU = math.pi * 2

type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"

-- The light comes from the top left of the screen: from above and the +Z side. A highlight sits toward it.
local LIGHT = V(-0.2, 0.85, 0.5).Unit

------------------------------------------------------------------ helpers
-- Any part at `cf` (f's frame).
local function put(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, shape: Shape?, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, shape = shape, name = name, neon = neon, collide = false })
end


-- A square limb from a to b (points in f's frame), t thick.
local function limb(m: Instance, f: CFrame, a: Vector3, b: Vector3, t: number, color: string, name: string?): BasePart
	return put(m, f, CFrame.lookAt((a + b) / 2, b), t, t, (b - a).Magnitude + t * 0.5, color, nil, name or "Branch")
end

-- A round limb (a cylinder) from a to b.
local function stem(m: Instance, f: CFrame, a: Vector3, b: Vector3, dia: number, color: string, name: string?): BasePart
	return put(m, f, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), (b - a).Magnitude + dia * 0.4, dia, dia, color, "Cylinder", name or "Stem")
end

-- A round trunk through `pts` (in f's frame, from the foot up): a cylinder from each point to the next and a ball at
-- each joint as wide as the segment below it, so it bends with no gap and no step; `dias` the segments' widths (on the
-- 1/8-stud grid: an art pixel; exact, so the joints meet), a ball on the last point too when `cap`.
local function tube(m: Instance, f: CFrame, pts: { Vector3 }, dias: { number }, color: string, name: string, cap: boolean?)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = math.max(0.25, math.floor(dias[i] * 8 + 0.5) / 8)
		local seg = put(m, f, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), 1, 1, 1, color, "Cylinder", name)
		seg.Size = Vector3.new((b - a).Magnitude, d, d)
		if i < #pts - 1 or cap then
			local joint = put(m, f, CFrame.new(b), 1, 1, 1, color, "Ball", name)
			joint.Size = Vector3.new(d, d, d)
		end
	end
end

-- A flat blade from a to b (a leaf, a frond, a strand): w wide, its flat side up.
local function blade(m: Instance, f: CFrame, a: Vector3, b: Vector3, w: number, color: string, name: string?): BasePart
	return put(m, f, CFrame.lookAt((a + b) / 2, b), w, 0.25, (b - a).Magnitude, color, nil, name or "Leaf")
end

-- A four-sided cone standing on `base` (its bottom centre): w x w, h tall. Four corner wedges, each with its point
-- over the middle.
local QUARTERS = { { -1, 1, 0 }, { 1, 1, math.pi / 2 }, { 1, -1, math.pi }, { -1, -1, -math.pi / 2 } }
local function cone(m: Instance, f: CFrame, base: CFrame, w: number, h: number, color: string, name: string?, neon: boolean?): { BasePart }
	local q = w / 2
	local out = {}
	for _, s in QUARTERS do
		table.insert(out, put(m, f, base * CFrame.new(s[1] * q / 2, h / 2, s[2] * q / 2) * CFrame.Angles(0, s[3], 0), q, h, q, color, "CornerWedge", name, neon))
	end
	return out
end

-- Paler needles lying on the slope of an upright cone (w wide, h tall, standing on y0 at the origin) at its edge, the
-- new growth where the light reaches: on its +Z face (side 0) or its +X face (side 1), `u` across that face.
local function coneTip(m: Instance, f: CFrame, w: number, y0: number, h: number, side: number, u: number, color: string, name: string): BasePart
	local half = w / 2
	local rim, up, out
	if side == 0 then
		rim, up, out = V(u, y0, half), V(0, h, -half).Unit, V(0, half, h).Unit
	else
		rim, up, out = V(half, y0, u), V(-half, h, 0).Unit, V(h, half, 0).Unit
	end
	local a = rim + up * 0.25 + out * 0.05
	return blade(m, f, a, a + up * 0.5, 0.5, color, name)
end

-- A small seeded random (the same picture every time a piece is built).
local function rand(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

-- A mushroom at (x, z): a stalk h tall, a cap of dia in two steps, white spots on its front.
local function shroom(m: Instance, f: CFrame, x: number, z: number, h: number, dia: number, cap: string, spots: boolean?)
	cyl(m, f, x, h / 2, z, 0.25, h, "cream", "Stalk")
	cyl(m, f, x, h + 0.1, z, dia, 0.25, cap, "Cap")
	if dia >= 0.5 then
		cyl(m, f, x, h + 0.3, z, dia - 0.25, 0.25, cap, "Cap")
	end
	if spots then
		box(m, f, x + dia * 0.28, h + 0.22, z + dia * 0.12, 0.25, 0.25, 0.25, "white", "Spot")
		box(m, f, x - dia * 0.08, h + 0.32, z + dia * 0.3, 0.25, 0.25, 0.25, "white", "Spot")
	end
end

-- A clump of leaves: a dark underside and a lit top (balls).
local function clump(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, top: string, under: string, name: string?): { BasePart }
	local a = ball(m, f, x, y - dia * 0.2, z, dia * 0.85, under, "LeavesUnder")
	local b = ball(m, f, x, y, z, dia, top, name or "Leaves")
	return { a, b }
end

-- A point on a ball of radius r at c toward dir, pushed out by `out` (in, when it is below 0).
local function onBall(c: Vector3, r: number, dir: Vector3, out: number?): Vector3
	return c + dir.Unit * (r + (out or 0))
end

-- A highlight on a clump or a stone (a ball of diameter dia at c): a small paler ball just breaking its surface on the
-- side toward the light.
local function shine(m: Instance, f: CFrame, c: Vector3, dia: number, size: number, color: string, name: string?): BasePart
	local p = onBall(c, dia / 2, LIGHT, -size * 0.3)
	return ball(m, f, p.X, p.Y, p.Z, size, color, name or "Shine")
end

-- Roots flaring from a trunk of radius r (standing on the origin): n of them round it, `a0` turning the ring, each a
-- piece t thick from low on the trunk (y) down to the grass and, when t is more than a quarter, a thin tip running on.
local function roots(m: Instance, f: CFrame, n: number, r: number, reach: number, t: number, color: string, a0: number, y: number?)
	for k = 0, n - 1 do
		local a = a0 + k / n * TAU + (k % 2) * 0.3
		local dx, dz = math.sin(a), math.cos(a)
		local len = reach * (if k % 2 == 0 then 1 else 0.75)
		local top = V(dx * r * 0.5, y or 0.4, dz * r * 0.5)
		local tip = V(dx * (r + len), 0.1, dz * (r + len))
		if t > 0.25 then
			local mid = V(dx * (r + len * 0.4), t / 2 - 0.05, dz * (r + len * 0.4))
			limb(m, f, top, mid, t, color, "Root")
			limb(m, f, mid, tip, 0.25, color, "Root")
		else
			limb(m, f, top, tip, 0.25, color, "Root")
		end
	end
end

-- A streak of paler (or darker) bark on a round trunk of radius r standing on (cx, cz), facing `a` (radians from +Z
-- toward +X), from y0 up to y1.
local function bark(m: Instance, f: CFrame, cx: number, cz: number, r: number, a: number, y0: number, y1: number, color: string)
	Parts.turned(m, f, cx + math.sin(a) * r, (y0 + y1) / 2, cz + math.cos(a) * r, 0.25, y1 - y0, 0.25, a, color, "Bark")
end

-- A knot hole in a round trunk of radius r standing on (cx, cz), facing `a`, at height y: pale bark round a dark hole.
local function knot(m: Instance, f: CFrame, cx: number, cz: number, r: number, a: number, y: number)
	local dx, dz = math.sin(a), math.cos(a)
	Parts.turned(m, f, cx + dx * (r - 0.05), y, cz + dz * (r - 0.05), 0.5, 0.5, 0.25, a, "wood", "KnotRim")
	Parts.turned(m, f, cx + dx * (r + 0.05), y, cz + dz * (r + 0.05), 0.25, 0.25, 0.25, a, "black", "Knot")
end

-- A tuft of grass at (x, z): three blades fanning out of one foot, the middle one tallest (h), in two greens (or the
-- colours given: straw for dry grass).
local function tuft(m: Instance, f: CFrame, x: number, z: number, h: number?, light: string?, dark: string?)
	local hh = h or 0.5
	local a0 = x * 7.3 + z * 3.1
	for k = 0, 2 do
		local len = if k == 1 then hh else math.max(0.25, hh - 0.25)
		local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, a0 + k * 2.1, 0) * CFrame.Angles(if k == 1 then 0.15 else 0.5, 0, 0)
		put(m, f, cf * CFrame.new(0, len / 2, 0), 0.25, len, 0.25, if k == 1 then light or "leaf" else dark or "leaf_dark", nil, "Tuft")
	end
end

-- A small flower at (x, z): a stem h tall and a round head the butterflies come to.
local function flower(m: Instance, f: CFrame, x: number, z: number, h: number, color: string)
	box(m, f, x, h / 2, z, 0.25, h, 0.25, "leaf_dark", "Stem")
	ball(m, f, x, h + 0.08, z, 0.25, color, "Flower")
end

-- A pebble at (x, z): a small flat stone turned by where it lies, w long.
local function pebble(m: Instance, f: CFrame, x: number, z: number, color: string?, w: number?)
	put(m, f, CFrame.new(x, 0.06, z) * CFrame.Angles(0, x * 5.1 + z * 2.3, 0), w or 0.5, 0.25, 0.25, color or "rock", nil, "Pebble")
end

-- A leaf (or a petal, a needle) fallen flat on the grass at (x, z).
local function fallen(m: Instance, f: CFrame, x: number, z: number, color: string, name: string?)
	put(m, f, CFrame.new(x, 0.03, z) * CFrame.Angles(0, x * 4.3 + z * 6.1, 0.12), 0.25, 0.25, 0.5, color, nil, name or "FallenLeaf")
end

-- An acorn at (x, z): a brown nut with its darker cup on top.
local function acorn(m: Instance, f: CFrame, x: number, z: number)
	ball(m, f, x, 0.12, z, 0.25, "wood", "Acorn")
	box(m, f, x, 0.3, z, 0.25, 0.25, 0.25, "wood_dark", "AcornCup")
end

------------------------------------------------------------------ trees
-- Pine Tree (2 x 2): a dark trunk on three roots with a pale streak of bark, four stacked cones of needles narrowing
-- going up, paler new growth lying on each tier's edge where the light reaches, a leader shoot on top; two cones, a
-- small brown mushroom, shed needles and tufts of grass at its foot.
M.pine = function(m, f)
	cyl(m, f, 0, 0.12, 0, 0.75, 0.25, "wood_dark", "Root")
	roots(m, f, 3, 0.25, 0.45, 0.25, "wood_dark", 0.4, 0.35)
	cyl(m, f, 0, 0.85, 0, 0.5, 1.5, "wood_dark", "Trunk")
	bark(m, f, 0, 0, 0.22, 0.6, 0.2, 0.8, "wood")
	local tiers = { { 2.5, 0.85, 1.5 }, { 2.0, 1.75, 1.5 }, { 1.5, 2.65, 1.25 }, { 1.0, 3.45, 1.25 } }
	for i, t in tiers do
		local w, y0, h = t[1], t[2], t[3]
		cone(m, f, CFrame.new(0, y0, 0), w, h, "leaf_dark", "Needles")
		if i < #tiers then
			coneTip(m, f, w, y0, h, 0, -w * 0.22, "leaf", "Needles")
			coneTip(m, f, w, y0, h, 0, w * 0.2, "leaf", "Needles")
			coneTip(m, f, w, y0, h, 1, -w * 0.15, "leaf", "Needles")
		end
	end
	box(m, f, 0, 4.8, 0, 0.25, 0.5, 0.25, "leaf", "Needles")
	-- at its foot
	for _, c in { { 0.75, 0.45, 0.6 }, { -0.5, 0.8, 2.2 } } do
		local cf = CFrame.new(c[1], 0.1, c[2]) * CFrame.Angles(0, c[3], 0)
		put(m, f, cf, 0.25, 0.25, 0.5, "wood", nil, "PineCone")
		put(m, f, cf * CFrame.new(0, 0.04, 0.22), 0.25, 0.25, 0.25, "wood_dark", nil, "PineCone")
	end
	shroom(m, f, 0.3, 0.85, 0.25, 0.5, "wood", false)
	fallen(m, f, 0.85, -0.35, "wood", "Needle")
	fallen(m, f, -0.85, 0.35, "wood", "Needle")
	tuft(m, f, 0.85, 0.85)
	tuft(m, f, -0.15, 0.9, 0.5)
end

-- Oak Tree (3 x 3): a stout trunk on five flaring roots, pale streaks of bark, a knot hole, moss at the foot of the
-- shady side; it forks low into three limbs (a short one off to the left with its own puff of leaves) under a round
-- crown: a dark underside, a ring of clumps in two greens with lit edges, a paler top. Acorns, fallen leaves, tufts
-- and two small flowers in the grass.
M.oak = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	roots(m, f, 5, 0.375, 0.6, 0.5, "wood_dark", 0.5, 0.45)
	cyl(m, f, 0, 1.0, 0, 0.75, 2.0, "wood_dark", "Trunk")
	bark(m, f, 0, 0, 0.36, 0.55, 0.45, 1.5, "wood")
	bark(m, f, 0, 0, 0.36, 1.85, 0.8, 1.85, "wood")
	knot(m, f, 0, 0, 0.375, -0.5, 1.2)
	ball(m, f, 0.34, 0.3, -0.2, 0.5, "moss", "Moss")
	-- the fork: three thick limbs thinning out into the crown, a short one low on the left
	local fork = V(0, 1.75, 0)
	for _, b in { { 0.85, 2.75, 0.5 }, { -0.8, 2.85, -0.3 }, { 0.25, 3.0, -0.85 } } do
		local tip = V(b[1], b[2], b[3])
		local mid = fork:Lerp(tip, 0.45)
		limb(m, f, fork, mid, 0.5, "wood_dark")
		limb(m, f, mid, tip, 0.25, "wood_dark")
	end
	limb(m, f, V(0, 1.35, 0), V(-0.9, 1.85, 0.65), 0.25, "wood_dark")
	ball(m, f, -1.0, 1.95, 0.75, 0.75, "leaf", "LeafClump")
	-- the crown
	ball(m, f, 0, 3.05, 0, 2.25, "leaf_dark", "LeavesUnder")
	ball(m, f, 0, 3.6, 0, 2.5, "leaf", "Leaves")
	for k = 0, 5 do
		local a = k / 6 * TAU + 0.35
		local c = V(math.sin(a) * 0.95, if k % 2 == 0 then 3.15 else 3.55, math.cos(a) * 0.95)
		local col = if k % 2 == 0 then "leaf_dark" else "leaf"
		ball(m, f, c.X, c.Y, c.Z, 1.5, col, if k % 2 == 1 then "Leaves" else "LeafClump")
		shine(m, f, c, 1.5, 0.5, if col == "leaf" then "green" else "leaf")
	end
	for k = 0, 2 do
		local a = k / 3 * TAU + 1.0
		ball(m, f, math.sin(a) * 0.55, 4.2, math.cos(a) * 0.55, 1.5, if k == 1 then "green" else "leaf", "LeafClump")
	end
	local top = V(-0.1, 4.7, 0.05)
	ball(m, f, top.X, top.Y, top.Z, 1.25, "green", "Leaves")
	shine(m, f, top, 1.25, 0.5, "grass")
	-- in the grass
	acorn(m, f, 0.85, 1.0)
	acorn(m, f, -0.45, 1.25)
	fallen(m, f, 1.15, 0.35, "leaf_dark")
	fallen(m, f, -0.85, 1.0, "leaf")
	fallen(m, f, 0.35, 1.3, "bamboo")
	tuft(m, f, 1.2, 1.05)
	tuft(m, f, -1.15, 0.5)
	flower(m, f, 1.3, -0.5, 0.25, "white")
	flower(m, f, -0.15, 1.35, 0.25, "yellow")
end

-- Bare Tree (2 x 2): a crooked grey-brown trunk in four bends on four roots, worn pale patches where the bark has
-- gone, a hollow, shelf fungus up its shady side; forked branches with no leaves reaching out and up, thin twigs at
-- their ends, an old nest in the lowest fork. At its foot a fallen branch, a stone, dry leaves and dry grass.
M.deadtree = function(m, f)
	local p0, p1, p2, p3, p4 = V(0, 0, 0), V(0.15, 1.2, 0.1), V(-0.1, 2.2, 0.05), V(0.1, 3.0, -0.1), V(0.35, 3.7, -0.05)
	roots(m, f, 4, 0.3, 0.5, 0.5, "wood_dark", 0.6, 0.4)
	-- (the crooked trunk one round line through its bends, narrowing as it rises, its foot a little in the ground)
	tube(m, f, { p0 - (p1 - p0) / 9, p1, p2, p3 }, { 0.75, 0.625, 0.5 }, "wood_dark", "Trunk", true)
	limb(m, f, p3, p4, 0.25, "wood_dark")
	limb(m, f, V(0.05, 0.3, 0.33), V(0.12, 0.9, 0.38), 0.25, "rock", "Bare")
	limb(m, f, V(0.38, 1.35, 0.1), V(0.22, 2.0, 0.06), 0.25, "rock", "Bare")
	box(m, f, 0.15, 0.95, 0.3, 0.25, 0.5, 0.25, "black", "Hollow")
	box(m, f, 0.15, 1.3, 0.28, 0.5, 0.25, 0.25, "rock", "HollowRim")
	-- shelf fungus on the shady side
	cyl(m, f, 0.45, 0.6, -0.05, 0.5, 0.25, "cream", "Fungus")
	cyl(m, f, 0.42, 0.85, 0.12, 0.5, 0.25, "sand_dark", "Fungus")
	cyl(m, f, 0.36, 1.6, -0.12, 0.5, 0.25, "cream", "Fungus")
	-- the branches, each bending up at a fork, twigs at their ends
	local function fork(a: Vector3, b: Vector3, c: Vector3, t: number)
		limb(m, f, a, b, t, "wood_dark")
		limb(m, f, b, c, 0.25, "wood_dark")
	end
	fork(p1 + V(0, 0.3, 0), V(0.95, 2.1, 0.45), V(1.05, 2.85, 0.2), 0.5)
	limb(m, f, V(0.95, 2.1, 0.45), V(1.1, 2.25, 0.95), 0.25, "wood_dark")
	fork(p2, V(-0.85, 2.75, -0.15), V(-1.05, 3.4, 0.2), 0.5)
	limb(m, f, V(-0.85, 2.75, -0.15), V(-1.1, 2.85, -0.7), 0.25, "wood_dark")
	fork(p2 + V(0, 0.3, 0), V(0.35, 3.0, 0.85), V(0.15, 3.55, 1.0), 0.25)
	limb(m, f, p3, V(-0.5, 3.65, -0.5), 0.25, "wood_dark")
	limb(m, f, p3 + V(0, 0.15, 0), V(0.8, 3.5, -0.6), 0.25, "wood_dark")
	for _, t in { { 1.05, 2.85, 0.2, 1.05, 3.15, -0.1 }, { -1.05, 3.4, 0.2, -0.9, 3.75, 0.45 }, { 0.15, 3.55, 1.0, 0.35, 3.85, 0.95 }, { 0.35, 3.7, -0.05, 0.55, 4.05, 0.15 }, { 0.35, 3.7, -0.05, 0.15, 4.0, -0.3 } } do
		limb(m, f, V(t[1], t[2], t[3]), V(t[4], t[5], t[6]), 0.25, "wood_dark", "Twig")
	end
	-- an old nest in the lowest fork
	cyl(m, f, 0.1, 2.72, 0.35, 0.75, 0.25, "wood", "Nest")
	cyl(m, f, 0.1, 2.8, 0.35, 0.5, 0.25, "straw", "Nest")
	-- at its foot
	put(m, f, CFrame.new(0.5, 0.08, 0.8) * CFrame.Angles(0, 0.5, 0), 0.75, 0.25, 0.25, "wood_dark", nil, "Fallen")
	put(m, f, CFrame.new(0.72, 0.1, 0.62) * CFrame.Angles(0, -0.6, 0.15), 0.25, 0.25, 0.5, "rock", nil, "Fallen")
	ball(m, f, -0.65, 0.12, 0.55, 0.5, "rock", "Stone")
	pebble(m, f, -0.35, 0.85, "rock_dark", 0.25)
	fallen(m, f, 0.85, 0.15, "wood")
	fallen(m, f, -0.2, 0.75, "orange")
	fallen(m, f, 0.2, -0.85, "straw")
	tuft(m, f, -0.8, 0.85, 0.5, "straw", "sand_dark")
	tuft(m, f, 0.85, -0.45, 0.5, "straw", "sand_dark")
end

-- Birch Tree (2 x 2): two slim white trunks on a dark foot, black marks and bands up them, one leaning out, and a
-- young one beside them; small dark twigs, light clumps of leaves climbing them with darker undersides and sky
-- between, so the white shows; catkins hanging. Tufts, two small flowers and yellowed leaves in the grass.
M.birch = function(m, f)
	cyl(m, f, -0.2, 0.2, -0.2, 0.75, 0.4, "rock_dark", "Root")
	limb(m, f, V(-0.2, 0.3, -0.2), V(-0.65, 0.08, 0.15), 0.25, "rock_dark", "Root")
	limb(m, f, V(-0.2, 0.3, -0.2), V(0.25, 0.08, -0.6), 0.25, "rock_dark", "Root")
	cyl(m, f, -0.2, 2.2, -0.2, 0.5, 4.4, "white", "Trunk")
	local lean0, lean1 = V(0.15, 0.1, 0.05), V(0.75, 3.0, -0.4)
	stem(m, f, lean0, lean1, 0.5, "white", "Trunk")
	-- the marks: small ones on its front and right, full bands across it facing the view
	for k, y in { 0.65, 1.05, 1.5, 1.95, 2.35, 2.8, 3.25, 3.7 } do
		if k % 3 == 0 then
			Parts.turned(m, f, -0.2 + 0.11, y, -0.2 + 0.11, 0.5, 0.25, 0.25, math.pi / 4, "black", "Mark")
		else
			local a = if k % 2 == 0 then 1.25 else 0.25
			Parts.turned(m, f, -0.2 + math.sin(a) * 0.2, y, -0.2 + math.cos(a) * 0.2, 0.25, 0.25, 0.25, a, "black", "Mark")
		end
	end
	for _, t in { 0.2, 0.42, 0.65, 0.85 } do
		local p = lean0:Lerp(lean1, t)
		box(m, f, p.X + 0.12, p.Y, p.Z + 0.12, 0.25, 0.25, 0.25, "black", "Mark")
	end
	-- a young one beside them
	cyl(m, f, 0.55, 0.75, 0.55, 0.25, 1.5, "white", "Trunk")
	box(m, f, 0.6, 0.7, 0.6, 0.25, 0.25, 0.25, "black", "Mark")
	ball(m, f, 0.55, 1.6, 0.55, 0.75, "leaf", "LeafClump")
	ball(m, f, 0.78, 1.3, 0.45, 0.5, "green", "LeafClump")
	-- twigs
	limb(m, f, V(-0.2, 2.6, -0.2), V(-0.75, 3.05, 0.15), 0.25, "black", "Twig")
	limb(m, f, V(-0.2, 3.4, -0.2), V(0.35, 3.75, -0.65), 0.25, "black", "Twig")
	limb(m, f, V(-0.2, 2.1, -0.2), V(-0.55, 2.4, -0.7), 0.25, "black", "Twig")
	limb(m, f, lean0:Lerp(lean1, 0.7), V(0.9, 2.55, 0.1), 0.25, "black", "Twig")
	-- the crown
	local crown: { { any } } = {
		{ -0.7, 3.2, 0.2, 1.0, "green", "Leaves" },
		{ 0.15, 3.85, -0.75, 1.0, "leaf", "LeafClump" },
		{ -0.6, 3.95, -0.35, 1.25, "green", "Leaves" },
		{ 0.25, 4.4, -0.35, 1.25, "leaf", "LeafClump" },
		{ -0.35, 4.8, 0.0, 1.25, "green", "Leaves" },
		{ -0.2, 5.35, -0.25, 0.75, "leaf", "LeafClump" },
		{ 0.72, 3.3, -0.35, 1.0, "green", "LeafClump" },
		{ 0.85, 2.85, 0.15, 0.75, "leaf", "LeafClump" },
		{ 0.45, 3.0, -0.75, 0.75, "green", "LeafClump" },
	}
	for k, c in crown do
		if k == 1 or k == 3 or k == 4 or k == 7 then
			ball(m, f, c[1] + 0.05, c[2] - 0.3, c[3] + 0.05, 0.75, "leaf_dark", "LeavesUnder")
		end
		ball(m, f, c[1], c[2], c[3], c[4], c[5], c[6])
	end
	-- catkins
	for _, c in { { -0.75, 2.6, 0.35 }, { 0.85, 2.35, 0.25 }, { 0.3, 2.55, -0.6 } } do
		box(m, f, c[1], c[2], c[3], 0.25, 0.5, 0.25, "wood", "Catkin")
	end
	-- in the grass
	tuft(m, f, 0.85, -0.3)
	tuft(m, f, -0.75, 0.7)
	flower(m, f, 0.15, 0.85, 0.25, "white")
	flower(m, f, 0.9, 0.9, 0.25, "yellow")
	fallen(m, f, -0.3, 0.45, "bamboo")
	fallen(m, f, 0.5, -0.8, "yellow")
end

-- Cherry Blossom (3 x 3): a dark trunk on four roots, pale bands across its bark, leaning and splitting into five
-- limbs under a wide, low cloud of pink blossom: darker pink under each puff, white catching the light on top, smaller
-- puffs hanging low round its edge and sprays dipping below, single deeper pink and white flowers dotted over its
-- front. Petals fallen all over the grass, tufts and a flat stone.
M.cherry = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	roots(m, f, 4, 0.375, 0.5, 0.5, "wood_dark", 0.3, 0.4)
	local base, split = V(0, 0, 0), V(0.25, 1.6, 0.15)
	stem(m, f, base, split, 0.75, "wood_dark", "Trunk")
	for _, y in { 0.55, 1.05 } do
		local p = base:Lerp(split, y / 1.6)
		Parts.turned(m, f, p.X + 0.14, y, p.Z + 0.14, 0.5, 0.25, 0.25, math.pi / 4, "wood", "Bark")
	end
	local clouds = { V(0.95, 2.95, 0.5), V(-0.95, 3.15, -0.2), V(0.3, 3.35, -0.95), V(-0.4, 3.25, 0.9), V(0.1, 3.75, 0) }
	for k, c in clouds do
		local bend = split + (c - split) * 0.55 + V(0, 0.15, 0)
		limb(m, f, split, bend, if k == 5 then 0.5 else 0.25, "wood_dark")
		limb(m, f, bend, c - V(0, 0.4, 0), 0.25, "wood_dark")
	end
	for k, c in clouds do
		local big = if k == 5 then 1.75 else 1.5
		ball(m, f, c.X + 0.05, c.Y - 0.3, c.Z + 0.05, big * 0.85, "pink", "BlossomUnder")
		ball(m, f, c.X, c.Y, c.Z, big, "cherry", "Blossom")
		local h = c + LIGHT * (big / 2 - 0.12)
		ball(m, f, h.X, h.Y, h.Z, if k == 5 then 0.5 else 0.25, "white", "Blossom")
		-- single flowers dotted over its front, a deeper pink
		for j, d in { V(0.7, 0.2, 0.6), V(-0.3, 0.1, 0.95) } do
			local p = onBall(c, big / 2, d + V(0, 0, (k - 3) * 0.1), -0.06)
			ball(m, f, p.X, p.Y, p.Z, 0.25, if (j + k) % 3 == 0 then "white" else "pink", "Flower")
		end
	end
	-- smaller puffs low round the edge, and sprays dipping below
	for _, c in { { 1.2, 2.55, -0.35 }, { -0.55, 2.6, 1.15 }, { 0.8, 2.65, 1.0 } } do
		ball(m, f, c[1], c[2], c[3], 1.0, "cherry", "BlossomPuff")
	end
	for _, c in { { 1.05, 2.25, 0.65 }, { -0.95, 2.45, -0.05 }, { -0.3, 2.55, 0.95 }, { 0.4, 2.7, -0.95 } } do
		ball(m, f, c[1], c[2], c[3], 0.5, "pink", "Spray")
	end
	-- petals on the grass
	for k, p in { { 1.1, 0.9 }, { -0.9, 1.0 }, { 1.3, -0.4 }, { -0.2, 1.3 }, { 0.6, 1.25 }, { -1.25, 0.3 }, { 0.95, 0.25 }, { 0.2, 0.75 }, { -0.6, 1.35 }, { 1.35, 1.2 } } do
		box(m, f, p[1], 0, p[2], 0.25, 0.25, 0.25, if k % 3 == 0 then "white" elseif k % 2 == 0 then "pink" else "cherry", "Petal")
	end
	tuft(m, f, 1.15, -1.0)
	tuft(m, f, -1.2, 0.95)
	put(m, f, CFrame.new(0.75, 0.05, 1.3) * CFrame.Angles(0, 0.4, 0), 0.5, 0.25, 0.5, "rock", nil, "Stone")
end

-- Maple Tree (3 x 3): a straight trunk on four roots with pale streaks of bark, four limbs spreading under a tall,
-- egg-shaped crown of red and orange, darker underneath and yellow where the sun catches its top; a little heap of
-- fallen leaves at its foot and more scattered round it, tufts of grass.
M.maple = function(m, f)
	cyl(m, f, 0, 0.12, 0, 0.9, 0.25, "wood_dark", "Root")
	roots(m, f, 4, 0.33, 0.5, 0.5, "wood_dark", 0.8, 0.4)
	cyl(m, f, 0, 1.1, 0, 0.65, 2.2, "wood_dark", "Trunk")
	bark(m, f, 0, 0, 0.36, 0.45, 0.4, 1.4, "wood")
	bark(m, f, 0, 0, 0.36, 1.55, 0.7, 1.7, "wood")
	limb(m, f, V(0, 1.8, 0), V(0.75, 2.5, 0.4), 0.25, "wood_dark")
	limb(m, f, V(0, 1.9, 0), V(-0.7, 2.6, 0.25), 0.25, "wood_dark")
	limb(m, f, V(0, 2.0, 0), V(0.3, 2.65, -0.75), 0.25, "wood_dark")
	limb(m, f, V(0, 2.05, 0), V(-0.45, 2.75, -0.6), 0.25, "wood_dark")
	local crown: { { any } } = {
		{ 0.6, 2.65, 0.45, 1.5, "brick", "LeafClump" },
		{ -0.6, 2.7, 0.45, 1.5, "brick", "LeafClump" },
		{ 0.5, 2.75, -0.55, 1.5, "brick", "LeafClump" },
		{ -0.55, 2.8, -0.5, 1.5, "brick", "LeafClump" },
		{ 0, 3.35, 0, 2.25, "maple", "LeafClump" },
		{ 0.8, 3.25, 0.5, 1.5, "orange", "Leaves" },
		{ -0.75, 3.45, 0.6, 1.5, "maple", "Leaves" },
		{ 0.6, 3.65, -0.7, 1.5, "maple", "LeafClump" },
		{ -0.7, 3.75, -0.5, 1.5, "orange", "Leaves" },
		{ 0, 4.25, 0, 1.75, "maple", "LeafClump" },
		{ 0.35, 4.3, 0.45, 1.0, "orange", "LeafClump" },
		{ 0.1, 4.85, 0.1, 1.25, "orange", "Leaves" },
		{ -0.45, 4.05, 0.55, 0.75, "yellow", "LeafClump" },
	}
	for _, c in crown do
		ball(m, f, c[1], c[2], c[3], c[4], c[5], c[6])
	end
	for _, k in { 6, 7, 11, 12 } do
		local c = crown[k]
		shine(m, f, V(c[1], c[2], c[3]), c[4], 0.5, if c[5] == "orange" then "yellow" else "orange")
	end
	-- a little heap of fallen leaves and more scattered round
	for k, l in { { -0.8, 0.03, 1.0, 0.3 }, { -0.6, 0.06, 1.1, 1.4 }, { -0.75, 0.1, 1.2, 2.5 }, { -0.68, 0.16, 1.08, 0.9 } } do
		put(m, f, CFrame.new(l[1], l[2], l[3]) * CFrame.Angles(0, l[4], 0.15), 0.25, 0.25, 0.5, if k == 1 then "brick" elseif k == 2 then "orange" elseif k == 3 then "yellow" else "maple", nil, "FallenLeaf")
	end
	for k, p in { { 1.1, 0.8 }, { 1.25, -0.5 }, { -0.1, 1.35 }, { 0.55, 1.2 }, { -1.2, 0.2 }, { 0.9, 0.1 } } do
		fallen(m, f, p[1], p[2], if k % 3 == 0 then "yellow" elseif k % 3 == 1 then "orange" else "maple")
	end
	tuft(m, f, 1.2, 1.15)
	tuft(m, f, -1.15, -0.6)
end

-- Jungle Tree (3 x 3): a tall pale trunk on flared buttress roots running out over the grass, dark rings, moss and a
-- vine climbing it, a red-flowered plant growing in its bark; a broad crown of huge drooping leaves, each with a
-- paler rib down it, a few shorter ones standing up in the middle; vines hanging from the leaves, two of them in
-- flower. A fern, a fallen leaf and tufts at its foot.
M.jungletree = function(m, f)
	for k = 0, 4 do
		local a = k / 5 * TAU + 0.3
		local dx, dz = math.sin(a), math.cos(a)
		Parts.wedge(m, f, dx * 0.75, 0.75, dz * 0.75, 0.25, 1.5, 1.0, "wood_dark", math.atan2(-dx, -dz), "Buttress")
		limb(m, f, V(dx * 1.1, 0.12, dz * 1.1), V(dx * 1.4, 0.08, dz * 1.4), 0.25, "wood_dark", "Root")
	end
	cyl(m, f, 0, 2.4, 0, 0.75, 4.8, "wood", "Trunk")
	cyl(m, f, 0, 2.0, 0, 0.8, 0.25, "wood_dark", "Ring")
	cyl(m, f, 0, 3.4, 0, 0.8, 0.25, "wood_dark", "Ring")
	box(m, f, 0.25, 2.6, 0.28, 0.25, 0.75, 0.25, "moss", "Moss")
	box(m, f, -0.28, 1.4, 0.25, 0.25, 0.5, 0.25, "moss", "Moss")
	-- a vine climbing the right side, two leaves off it
	limb(m, f, V(0.35, 0.3, 0.12), V(0.33, 1.9, -0.2), 0.25, "leaf_dark", "Vine")
	box(m, f, 0.48, 0.9, 0.0, 0.25, 0.25, 0.25, "leaf", "VineLeaf")
	box(m, f, 0.45, 1.5, -0.2, 0.25, 0.25, 0.25, "leaf", "VineLeaf")
	-- a plant growing in the bark, in flower
	local bro = V(-0.15, 2.95, 0.35)
	for _, d in { { -0.35, 0.3, 0.2 }, { 0.15, 0.35, 0.3 }, { -0.1, 0.4, -0.05 } } do
		blade(m, f, bro, bro + V(d[1], d[2], d[3]), 0.25, "leaf", "BarkPlant")
	end
	ball(m, f, bro.X - 0.02, bro.Y + 0.2, bro.Z + 0.12, 0.25, "berry_red", "Flower")
	-- the crown
	local top = V(0, 4.85, 0)
	ball(m, f, 0, 4.8, 0, 1.25, "leaf_dark", "Heart")
	for k = 0, 7 do
		local a = k / 8 * TAU + 0.2
		local dx, dz = math.sin(a), math.cos(a)
		local mid = top + V(dx * 1.0, 0.05, dz * 1.0)
		local tip = top + V(dx * 1.55, -0.6, dz * 1.55)
		local col = if k % 2 == 0 then "leaf" else "leaf_dark"
		blade(m, f, top + V(dx * 0.3, 0, dz * 0.3), mid, 1.0, col, "BigLeaf")
		blade(m, f, mid, tip, 0.75, col, "BigLeaf")
		local up = V(0, 0.12, 0)
		blade(m, f, mid + up, tip + up, 0.25, if col == "leaf" then "green" else "leaf", "Rib")
	end
	for k = 0, 3 do
		local a = k / 4 * TAU + 0.7
		blade(m, f, top + V(0, 0.2, 0), top + V(math.sin(a) * 0.95, 0.85, math.cos(a) * 0.95), 0.75, "leaf", "BigLeaf")
	end
	-- vines from under the leaves, two in flower
	for k, v in { { 1.45, 0.45, 2.25 }, { 0.3, 1.45, 1.75 }, { -1.2, 0.85, 1.5 }, { 1.05, -1.0, 1.75 }, { -0.7, -1.2, 1.25 }, { 0.95, 1.05, 1.25 } } do
		local y = 4.35 - v[3] / 2
		box(m, f, v[1], y, v[2], 0.25, v[3], 0.25, if k % 2 == 0 then "moss" else "leaf_dark", "Vine")
		if k <= 2 then
			box(m, f, v[1], y - v[3] / 2 + 0.1, v[2] + 0.05, 0.25, 0.25, 0.25, if k == 1 then "pink" else "orange", "Flower")
		end
	end
	-- at its foot
	for _, d in { { -0.45, 0.45, 0.2 }, { 0.1, 0.5, 0.45 }, { 0.4, 0.35, 0.1 } } do
		blade(m, f, V(-0.65, 0.1, 1.15), V(-0.65 + d[1], d[2], 1.15 + d[3]), 0.5, "leaf_dark", "Fern")
	end
	put(m, f, CFrame.new(1.05, 0.03, -0.25) * CFrame.Angles(0, 0.6, 0.08), 0.5, 0.25, 0.75, "leaf_dark", nil, "FallenLeaf")
	tuft(m, f, 1.1, 1.0)
	tuft(m, f, 0.4, 1.35)
end

-- Willow (4 x 4): a short thick trunk on five flaring roots, gnarled and streaked, five limbs under a low, lumpy dome
-- lit on top, and a curtain of long strands of different lengths hanging from it nearly to the grass, some ending in
-- paler tips, an inner ring of shorter ones behind, gaps where the trunk shows. Tufts, flowers and a stone at its
-- corners.
M.willow = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.25, 0.25, "wood_dark", "Root")
	roots(m, f, 5, 0.45, 0.65, 0.5, "wood_dark", 0.2, 0.5)
	cyl(m, f, 0, 1.15, 0, 0.9, 2.3, "wood_dark", "Trunk")
	ball(m, f, 0.32, 0.8, 0.3, 0.5, "wood_dark", "Gnarl")
	ball(m, f, -0.35, 1.6, 0.28, 0.5, "wood_dark", "Gnarl")
	bark(m, f, 0, 0, 0.47, 0.75, 0.4, 2.0, "wood")
	bark(m, f, 0, 0, 0.47, 1.5, 0.9, 2.2, "wood")
	for _, b in { { 0.9, 3.0, 0.5 }, { -0.8, 3.1, 0.4 }, { 0.2, 3.2, -0.9 }, { -0.6, 3.2, -0.7 }, { 0.9, 3.15, -0.4 } } do
		limb(m, f, V(0, 2.0, 0), V(b[1], b[2], b[3]), 0.5, "wood_dark")
	end
	ball(m, f, 0, 3.55, 0, 2.75, "leaf", "Leaves")
	ball(m, f, 0.3, 4.35, -0.25, 1.75, "leaf", "Leaves")
	for k = 0, 5 do
		local a = k / 6 * TAU + 0.25
		local c = V(math.sin(a) * 1.05, if k % 2 == 0 then 3.15 else 3.4, math.cos(a) * 1.05)
		ball(m, f, c.X, c.Y, c.Z, 1.75, if k % 2 == 0 then "leaf_dark" else "leaf", "LeafClump")
		if k % 2 == 1 or k == 0 then
			shine(m, f, c, 1.75, 0.5, "green")
		end
	end
	ball(m, f, -0.2, 4.6, 0.15, 1.0, "green", "LeafClump")
	shine(m, f, V(0.3, 4.35, -0.25), 1.75, 0.5, "grass")
	-- the curtain: long strands round the outside, paler tips on some, a shorter ring inside
	local lens = { 3.0, 2.25, 2.75, 2.0, 2.5 }
	for k = 0, 13 do
		local a = k / 14 * TAU + 0.1
		local len = lens[k % 5 + 1]
		Parts.turned(m, f, math.sin(a) * 1.7, 3.4 - len / 2, math.cos(a) * 1.7, 0.5, len, 0.25, a, if k % 2 == 0 then "leaf" else "leaf_dark", "Strand")
		if len <= 2.75 and k % 2 == 1 then
			Parts.turned(m, f, math.sin(a) * 1.72, 3.4 - len - 0.2, math.cos(a) * 1.72, 0.25, 0.5, 0.25, a, "green", "StrandTip")
		end
	end
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * TAU + 0.1
		Parts.turned(m, f, math.sin(a) * 1.3, 2.5, math.cos(a) * 1.3, 0.5, 1.75, 0.25, a, "leaf_dark", "Strand")
	end
	-- at its corners, outside the curtain
	tuft(m, f, 1.6, 1.65)
	tuft(m, f, -1.6, 1.7)
	tuft(m, f, 1.75, -1.5)
	flower(m, f, 1.75, 1.15, 0.25, "white")
	flower(m, f, 1.15, 1.8, 0.25, "pink")
	flower(m, f, -1.8, 1.25, 0.25, "yellow")
	put(m, f, CFrame.new(1.65, 0.08, 1.65) * CFrame.Angles(0, 0.7, 0), 0.5, 0.25, 0.5, "rock", nil, "Stone")
	pebble(m, f, -1.25, 1.7, "rock_dark")
end

-- Great Oak (5 x 5): a huge gnarled trunk on wide roots, ridges of pale bark, a hollow, shelf fungus on the shady
-- side; thick limbs reaching out to a broad crown of leaf clumps with sky between them, lit paler on the highest ones.
-- A rope swing on a low limb out to the left sways back and forth. Moss on the roots, mushrooms, acorns, fallen
-- leaves, a fern, tufts and flowers round its foot.
M.bigoak = function(m, f)
	cyl(m, f, 0, 0, 0, 3.0, 0.25, "moss", "Moss")
	for k = 0, 6 do
		local a = k / 7 * TAU + 0.2
		local dx, dz = math.sin(a), math.cos(a)
		put(m, f, CFrame.new(dx * 1.05, 0.32, dz * 1.05) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(16), 0, 0), 0.75, 0.5, 1.5, if k % 2 == 0 then "wood_dark" else "wood", nil, "Root")
		put(m, f, CFrame.new(dx * 1.85, 0.14, dz * 1.85) * CFrame.Angles(0, a + 0.2, 0) * CFrame.Angles(math.rad(8), 0, 0), 0.5, 0.25, 1.0, "wood_dark", nil, "Root")
		if k % 3 == 1 then
			put(m, f, CFrame.new(dx * 1.1, 0.55, dz * 1.1) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(16), 0, 0), 0.75, 0.25, 0.75, "moss", nil, "Moss")
		end
	end
	-- (the trunk one column from the ground, its foot in the roots)
	cyl(m, f, 0, 1.74, 0, 1.5, 3.48, "wood_dark", "Trunk")
	ball(m, f, 0.5, 1.4, 0.45, 1.0, "wood_dark", "Gnarl")
	ball(m, f, -0.45, 2.5, 0.5, 0.75, "wood_dark", "Gnarl")
	ball(m, f, 0.62, 2.9, -0.3, 0.75, "wood_dark", "Gnarl")
	for _, b in { { 0.55, 0.5, 2.9 }, { 1.05, 1.1, 3.2 }, { 1.45, 0.4, 2.3 }, { -0.75, 0.5, 1.5 }, { -0.6, 2.5, 3.3 } } do
		bark(m, f, 0, 0, 0.72, b[1], b[2], b[3], "wood")
	end
	box(m, f, -0.15, 1.8, 0.72, 0.75, 1.0, 0.25, "wood", "HollowRim")
	box(m, f, -0.15, 1.75, 0.78, 0.5, 0.75, 0.25, "black", "Hollow")
	cyl(m, f, 0.78, 1.1, -0.28, 0.5, 0.25, "cream", "Fungus")
	cyl(m, f, 0.8, 1.35, -0.05, 0.5, 0.25, "sand_dark", "Fungus")
	-- the limbs out to the clumps of the crown: a ring of seven, three higher in, one on top
	local trunkTop = V(0, 3.3, 0)
	local clumps: { Vector3 } = { V(0, 6.4, 0) }
	for k = 0, 6 do
		local a = k / 7 * TAU + 0.45
		local r = if k % 2 == 0 then 1.9 else 1.75
		table.insert(clumps, V(math.sin(a) * r, if k % 2 == 0 then 4.7 else 5.2, math.cos(a) * r))
	end
	for k = 0, 2 do
		local a = k / 3 * TAU + 1.2
		table.insert(clumps, V(math.sin(a) * 1.0, 5.8, math.cos(a) * 1.0))
	end
	for k, c in clumps do
		if k <= 8 then
			local bend = V(c.X * 0.5, trunkTop.Y + 0.35 + (c.Y - trunkTop.Y) * 0.25, c.Z * 0.5)
			limb(m, f, trunkTop, bend, if k == 1 then 0.75 else 0.5, if k % 2 == 0 then "wood" else "wood_dark")
			limb(m, f, bend, c - V(0, 0.5, 0), 0.5, "wood_dark")
		end
	end
	for k, c in clumps do
		local big = if k == 1 then 2.5 elseif k <= 8 then 2.0 else 1.75
		clump(m, f, c.X, c.Y, c.Z, big, "leaf", "leaf_dark", if k <= 8 then "Leaves" else "LeafClump")
		if k <= 8 then
			ball(m, f, c.X + 0.2, c.Y + big * 0.32, c.Z - 0.1, big * 0.6, if k % 2 == 0 then "leaf_dark" else "leaf", "LeafClump")
		end
		if k == 1 or k >= 9 then
			shine(m, f, c, big, 0.75, "green")
		end
	end
	-- the rope swing on a low limb out to the left, the limb turning to run across the view so both ropes show; the
	-- ropes and the seat swing together toward the view and back (Parts.move)
	limb(m, f, V(-0.2, 3.0, 0.6), V(-0.6, 3.5, 1.85), 0.5, "wood_dark")
	limb(m, f, V(-0.6, 3.5, 1.85), V(0.75, 3.6, 1.9), 0.5, "wood_dark")
	local hub = V(0.1, 3.5, 1.9)
	for _, x in { -0.25, 0.45 } do
		Parts.move(box(m, f, x, 2.15, 1.9, 0.25, 2.75, 0.25, "straw", "Rope"), "swing", hub, "X", 1.5, 0.2, 0)
	end
	Parts.move(box(m, f, 0.1, 0.8, 1.9, 1.0, 0.25, 0.5, "wood", "Seat"), "swing", hub, "X", 1.5, 0.2, 0)
	-- round its foot
	shroom(m, f, 1.35, 0.95, 0.25, 0.5, "berry_red", false)
	shroom(m, f, -1.25, 1.1, 0.25, 0.5, "orange", false)
	acorn(m, f, 1.3, 1.55)
	acorn(m, f, 1.9, 0.75)
	for k, p in { { 2.05, 0.4 }, { -1.0, 2.05 }, { 1.55, -1.6 }, { 0.95, 2.25 } } do
		fallen(m, f, p[1], p[2], if k % 2 == 0 then "leaf" else "leaf_dark")
	end
	for _, d in { { -0.4, 0.45, 0.15 }, { 0.1, 0.5, 0.4 }, { 0.4, 0.35, 0.05 } } do
		blade(m, f, V(-1.0, 0.1, 2.15), V(-1.0 + d[1], d[2], 2.15 + d[3]), 0.5, "leaf_dark", "Fern")
	end
	tuft(m, f, 2.1, 1.4)
	tuft(m, f, -1.95, 1.3)
	tuft(m, f, 2.2, -1.0)
	flower(m, f, 1.45, 2.05, 0.25, "white")
	flower(m, f, 2.3, 0.25, 0.25, "yellow")
	flower(m, f, -1.55, 1.95, 0.25, "pink")
end

-- Snowy Pine (2 x 2): four broad green tiers bowed low, each wearing a cap of snow with a green fringe below it and
-- lumps of snow sitting on its edge, icicles under the lowest, a ball of snow on its tip; a drift at its foot with a
-- mound, a pine cone, a frosty tuft and a bird's tracks in it.
M.snowpine = function(m, f)
	cyl(m, f, 0, 0, 0, 2.0, 0.25, "snow", "Drift")
	cyl(m, f, 0, 0.7, 0, 0.5, 1.4, "wood_dark", "Trunk")
	local tiers = { { 2.5, 0.75, 0.75 }, { 2.0, 1.5, 0.75 }, { 1.5, 2.25, 0.75 }, { 1.0, 3.0, 0.75 } }
	for i, t in tiers do
		local w, y0, h = t[1], t[2], t[3]
		cone(m, f, CFrame.new(0, y0, 0), w, h, "leaf_dark", "Needles")
		-- the snow: a smaller cone of about the same slope just over the needles, the green fringe below its edge
		local ws = w - 0.5
		local hs = math.max(0.25, math.floor(h * ws / w * 4 + 0.5) / 4)
		local ys = y0 + h * (1 - ws / w) + 0.05
		if i == #tiers then
			ys = math.max(ys, y0 + h + 0.1 - hs)
		end
		cone(m, f, CFrame.new(0, ys, 0), ws, hs, "snow", "Snow")
		-- lumps of snow on the edge, where the view sees it
		if i < #tiers then
			ball(m, f, -ws * 0.3, ys + 0.1, ws / 2, 0.5, "snow", "Snow")
			ball(m, f, ws / 2, ys + 0.1, ws * 0.1, 0.5, "snow", "Snow")
		end
	end
	ball(m, f, 0, 3.85, 0, 0.5, "snow", "Snow")
	box(m, f, 0.35, 0.55, 1.08, 0.25, 0.5, 0.25, "ice", "Icicle")
	box(m, f, -0.4, 0.62, 1.08, 0.25, 0.25, 0.25, "ice", "Icicle")
	box(m, f, 1.08, 0.55, -0.3, 0.25, 0.5, 0.25, "ice", "Icicle")
	-- the drift at its foot
	box(m, f, 0.75, 0.0, 0.7, 0.5, 0.25, 0.5, "snow", "Drift")
	ball(m, f, -0.65, 0.15, 0.7, 0.5, "snow", "Drift")
	put(m, f, CFrame.new(0.85, 0.15, -0.2) * CFrame.Angles(0, 0.8, 0), 0.25, 0.25, 0.5, "wood", nil, "PineCone")
	tuft(m, f, 0.25, 0.9, 0.5, "leaf_dark", "swamp")
	for _, p in { { 0.55, 0.35 }, { 0.35, 0.6 }, { 0.6, 0.8 } } do
		box(m, f, p[1], 0.02, p[2], 0.25, 0.25, 0.25, "ice", "Track")
	end
end

-- Starfruit Tree (3 x 3): a smooth leaning trunk on four roots, three limbs under round clumps of leaves (three big,
-- three small, a paler top), glowing gold star-shaped fruit hanging under them on short stalks, four of them swaying
-- (Parts.move) and three twinkling; a few fallen stars glowing in the grass, tufts and a flower.
M.starfruit = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	roots(m, f, 4, 0.25, 0.5, 0.25, "wood", 0.5, 0.35)
	tube(m, f, { V(0, 0, 0), V(0.1, 0.9, 0), V(-0.15, 1.8, -0.1), V(0, 2.4, 0) }, { 0.5, 0.5, 0.375 }, "wood", "Trunk")
	box(m, f, 0.12, 0.55, 0.22, 0.25, 0.25, 0.25, "wood_dark", "Bark")
	box(m, f, 0.2, 1.2, 0.05, 0.25, 0.25, 0.25, "wood_dark", "Bark")
	limb(m, f, V(-0.1, 1.9, -0.05), V(-0.6, 2.35, 0.25), 0.25, "wood")
	limb(m, f, V(-0.05, 2.1, -0.05), V(0.65, 2.45, -0.3), 0.25, "wood")
	limb(m, f, V(0, 2.3, 0), V(0.4, 2.6, 0.55), 0.25, "wood")
	for k, c in { { 0, 2.9, 0, 1.75 }, { -0.7, 2.5, 0.3, 1.25 }, { 0.75, 2.6, -0.35, 1.25 } } do
		clump(m, f, c[1], c[2], c[3], c[4], if k == 1 then "leaf" else "green", "leaf_dark")
		shine(m, f, V(c[1], c[2], c[3]), c[4], 0.5, if k == 1 then "green" else "grass")
	end
	for _, c in ({ { 0.45, 2.65, 0.6, "leaf" }, { -0.45, 3.4, -0.45, "leaf" }, { 0.1, 3.65, 0.15, "green" } } :: { { any } }) do
		ball(m, f, c[1], c[2], c[3], 1.0, c[4], "LeafClump")
	end
	-- the fruit: a cross of two glowing bars on a stalk; four of them swing on their stalks
	for k, s in { { -0.6, 1.75, 0.75 }, { 0.5, 1.85, 0.65 }, { 0.95, 1.9, -0.15 }, { -0.95, 1.85, 0.05 }, { 0.15, 2.0, 0.95 } } do
		local x, y, z = s[1], s[2], s[3]
		local bits = {
			box(m, f, x, y + 0.35, z, 0.25, 0.5, 0.25, "wood_dark", "FruitStalk"),
			Parts.turned(m, f, x, y, z, 0.25, 0.75, 0.25, math.pi / 4, "gold", if k <= 3 then "Sparkle" else "Fruit", true),
			Parts.turned(m, f, x, y, z, 0.75, 0.25, 0.25, math.pi / 4, "yellow", "Fruit", true),
		}
		if k <= 4 then
			for _, p in bits do
				Parts.move(p, "swing", V(x, y + 0.55, z), if k % 2 == 0 then "X" else "Z", 1.2 + k * 0.1, 0.15, k * 1.4)
			end
		end
	end
	-- fallen stars in the grass
	for _, s in { { 0.95, 0.95, 0.3 }, { -1.05, 0.65, -0.4 }, { 0.3, 1.05, 1.1 } } do
		local cf = CFrame.new(s[1], 0.04, s[2]) * CFrame.Angles(0, s[3], 0)
		put(m, f, cf, 0.75, 0.25, 0.25, "gold", nil, "Fallen", true)
		put(m, f, cf, 0.25, 0.25, 0.75, "yellow", nil, "Fallen", true)
	end
	tuft(m, f, 1.15, 0.4)
	tuft(m, f, -0.5, 1.25)
	flower(m, f, 1.2, -0.8, 0.25, "white")
end

-- Redwood (4 x 4): a very tall straight red trunk on six great flaring roots, deep furrows of paler and darker bark
-- running up it, an old burn hollow at its foot; short dark branches all the way up, each ending in a clump of
-- needles with a paler tip, and a narrow crown of dark green cones at the top with new growth on their edges and a
-- leader shoot. Ferns round its foot, moss on the roots and a mossy fallen log with two small mushrooms on it.
M.redwood = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.75, 0.25, "wood_dark", "Root")
	roots(m, f, 6, 0.6, 0.8, 0.5, "brick", 0.6, 0.9)
	tube(m, f, { V(0, 0, 0), V(0, 3.0, 0), V(0, 6.0, 0), V(0, 9.0, 0) }, { 1.25, 1.0, 0.75 }, "brick", "Trunk")
	for _, b in ({ { 0.25, 0.62, 0.4, 2.8, "clay" }, { 0.8, 0.62, 0.8, 2.6, "wood_dark" }, { 1.45, 0.62, 0.5, 2.2, "clay" }, { 0.55, 0.5, 3.2, 5.6, "clay" }, { 1.2, 0.5, 3.6, 5.2, "wood_dark" }, { 0.85, 0.375, 6.3, 8.2, "clay" } } :: { { any } }) do
		bark(m, f, 0, 0, b[2], b[1], b[3], b[4], b[5])
	end
	Parts.turned(m, f, math.sin(-0.35) * 0.55, 0.62, math.cos(-0.35) * 0.55, 0.75, 1.0, 0.25, -0.35, "wood_dark", "HollowRim")
	Parts.turned(m, f, math.sin(-0.35) * 0.62, 0.55, math.cos(-0.35) * 0.62, 0.5, 0.75, 0.25, -0.35, "black", "Hollow")
	-- branches up the trunk
	for k = 0, 6 do
		local a = k * 2.4 + 0.3
		local y = 3.4 + k * 0.5
		local dx, dz = math.sin(a), math.cos(a)
		limb(m, f, V(0, y, 0), V(dx * 1.1, y + 0.3, dz * 1.1), 0.25, "wood_dark", "Branch")
		ball(m, f, dx * 1.25, y + 0.4, dz * 1.25, 0.75, if k % 2 == 0 then "leaf_dark" else "swamp", "Needles")
		ball(m, f, dx * 1.25 + LIGHT.X * 0.25, y + 0.6, dz * 1.25 + LIGHT.Z * 0.25, 0.5, "leaf", "Needles")
	end
	-- the crown
	local tiers = { { 2.5, 6.6, 1.5 }, { 2.0, 7.6, 1.5 }, { 1.5, 8.6, 1.25 }, { 1.0, 9.5, 1.0 } }
	for i, t in tiers do
		cone(m, f, CFrame.new(0, t[2], 0), t[1], t[3], "leaf_dark", "Needles")
		if i < #tiers then
			coneTip(m, f, t[1], t[2], t[3], 0, -t[1] * 0.2, "leaf", "Needles")
			coneTip(m, f, t[1], t[2], t[3], 1, t[1] * 0.1, "leaf", "Needles")
		end
	end
	box(m, f, 0, 10.6, 0, 0.25, 0.5, 0.25, "leaf", "Needles")
	-- round its foot: ferns, moss, a fallen log
	for _, c in { { 1.4, 1.1 }, { -1.3, 0.75 }, { 1.45, -0.8 } } do
		for j, d in { { -0.45, 0.45, 0.15 }, { 0.1, 0.55, 0.45 }, { 0.45, 0.4, -0.05 } } do
			blade(m, f, V(c[1], 0.1, c[2]), V(c[1] + d[1] * 0.9, d[2], c[2] + d[3] * 0.9), 0.5, if j == 2 then "leaf" else "leaf_dark", "Fern")
		end
	end
	ball(m, f, 0.55, 0.45, 0.8, 0.5, "moss", "Moss")
	ball(m, f, 0.95, 0.35, -0.35, 0.5, "moss", "Moss")
	Parts.log(m, f, -0.95, 0.25, 1.7, 1.5, 0.5, "wood_dark")
	Parts.log(m, f, -0.15, 0.25, 1.7, 0.25, 0.5, "wood", "LogEnd")
	box(m, f, -1.05, 0.5, 1.7, 1.0, 0.25, 0.25, "moss", "Moss")
	for _, x in { -0.55, -1.45 } do
		box(m, f, x, 0.6, 1.7, 0.25, 0.25, 0.25, "cream", "Stalk")
		cyl(m, f, x, 0.75, 1.7, 0.5, 0.25, if x > -1 then "orange" else "wood", "Cap")
	end
	tuft(m, f, 1.75, 0.35)
end

------------------------------------------------------------------ plants
-- Fern (1 x 1): seven fronds rising out of a dark heart on a patch of soil, long and short in turn, each an arch of
-- three pieces: a dark stalk, a wide middle and a paler tip drooping out low, so the plant is a star of points; two
-- young fronds still curled up in the middle.
M.fern = function(m, f)
	cyl(m, f, 0, 0.02, 0, 0.75, 0.25, "wood_dark", "Soil")
	ball(m, f, 0, 0.15, 0, 0.5, "leaf_dark", "Heart")
	for k = 0, 6 do
		local a = k / 7 * TAU + 0.3
		local dx, dz = math.sin(a), math.cos(a)
		local r = if k % 2 == 0 then 1 else 0.75
		local p0 = V(dx * 0.05, 0.15, dz * 0.05)
		local p1 = V(dx * 0.2 * r, 0.7 * r, dz * 0.2 * r)
		local p2 = V(dx * 0.42 * r, 0.75 * r, dz * 0.42 * r)
		local p3 = V(dx * 0.62 * r, 0.3, dz * 0.62 * r)
		blade(m, f, p0, p1, 0.25, "leaf_dark", "Frond")
		blade(m, f, p1, p2, 0.5, if k % 2 == 0 then "leaf" else "leaf_dark", "Frond")
		blade(m, f, p2, p3, 0.25, if k % 2 == 0 then "green" else "leaf", "Frond")
	end
	for _, c in { { 0.08, -0.05, 0.75 }, { -0.1, 0.1, 0.6 } } do
		box(m, f, c[1], c[3] / 2 + 0.1, c[2], 0.25, c[3], 0.25, "leaf_dark", "Fiddle")
		ball(m, f, c[1] + 0.06, c[3] + 0.15, c[2] + 0.06, 0.25, "green", "Fiddle")
	end
end

-- Tall Grass (2 x 2): five clumps of long thin blades fanning out over the patch in three greens, pale seed heads on
-- the tallest, two small flowers down among them.
M.tallgrass = function(m, f)
	local r = rand(7)
	local colors = { "leaf_dark", "leaf", "green", "leaf", "leaf_dark", "green" }
	for ci, c in { { -0.5, -0.45, 1.0, 7 }, { 0.5, -0.35, 0.85, 6 }, { -0.35, 0.5, 0.8, 6 }, { 0.5, 0.55, 0.7, 6 }, { 0.05, 0.05, 0.6, 4 } } do
		for k = 1, c[4] do
			local a = (k + r() * 0.6) / c[4] * TAU
			local h = (0.8 + r() * 0.7) * c[3]
			local cf = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.2 + r() * 0.3, 0, 0)
			put(m, f, cf * CFrame.new(0, h / 2, 0), 0.25, h, 0.25, colors[(k + ci) % 6 + 1], nil, "Blade")
			if (k == 2 or k == 5) and h > 0.7 then
				put(m, f, cf * CFrame.new(0, h + 0.2, 0), 0.25, 0.5, 0.25, if k == 2 then "straw" else "bamboo", nil, "Seed")
			end
		end
	end
	flower(m, f, 0.85, 0.15, 0.5, "white")
	flower(m, f, -0.05, 0.85, 0.25, "yellow")
end

-- Berry Bush (2 x 2): a low, wide mound of leaf clumps, darkest at the bottom and paler at the top where the light
-- reaches, single leaves poking out of its edge, red berries in twos and threes all over its front; a basket of
-- picked ones with a handle, two dropped on the grass, a tuft.
M.berrybush = function(m, f)
	local clumps: { { any } } = {
		{ 0, 0.55, 0, 1.5, "leaf_dark" },
		{ 0.5, 0.45, 0.45, 1.0, "leaf_dark" },
		{ -0.45, 0.6, 0.4, 1.0, "leaf" },
		{ 0.45, 0.75, -0.4, 1.0, "leaf" },
		{ -0.45, 0.55, -0.45, 1.0, "leaf_dark" },
		{ 0, 1.0, 0.05, 1.0, "leaf" },
		{ 0.15, 0.35, 0.6, 0.75, "leaf" },
		{ 0.65, 0.4, 0.0, 0.75, "leaf" },
		{ -0.2, 1.25, -0.2, 0.75, "green" },
	}
	for _, c in clumps do
		ball(m, f, c[1], c[2], c[3], c[4], c[5], "Bush")
	end
	for _, k in { 3, 6, 7 } do
		local c = clumps[k]
		shine(m, f, V(c[1], c[2], c[3]), c[4], 0.5, "green")
	end
	for _, l in { { -0.9, 0.35, 0.3 }, { 0.3, 0.3, 0.92 }, { 0.92, 0.45, -0.35 }, { -0.6, 0.85, 0.75 } } do
		local tip = V(l[1], l[2], l[3])
		blade(m, f, tip * 0.6 + V(0, 0.1, 0), tip, 0.5, "leaf_dark", "Leaf")
	end
	-- berries on the front of the clumps
	local spots = { { 1, 0.3, 0.5, 0.8 }, { 1, 0.7, 0.3, 0.45 }, { 2, 0.6, 0.2, 0.6 }, { 2, 0.3, 0.5, 0.8 }, { 3, 0.1, 0.4, 0.8 }, { 3, -0.3, 0.6, 0.6 }, { 4, 0.8, 0.4, 0.2 }, { 4, 0.6, 0.7, -0.1 }, { 6, 0.4, 0.6, 0.5 }, { 6, -0.2, 0.7, 0.6 }, { 5, 0.2, 0.3, 0.9 }, { 7, 0.5, 0.4, 0.7 }, { 8, 0.8, 0.5, 0.2 }, { 9, 0.2, 0.8, 0.5 } }
	for i, s in spots do
		local c = clumps[s[1]]
		local p = onBall(V(c[1], c[2], c[3]), c[4] / 2, V(s[2], s[3], s[4]), -0.05)
		ball(m, f, p.X, p.Y, p.Z, 0.25, if i % 4 == 0 then "brick" else "berry_red", "Berry")
	end
	-- a basket of picked berries
	box(m, f, 0.65, 0.13, 0.65, 0.5, 0.25, 0.5, "straw", "Basket")
	for _, s in { -1, 1 } do
		box(m, f, 0.65 + s * 0.2, 0.42, 0.65 - s * 0.2, 0.25, 0.5, 0.25, "wood", "Handle")
	end
	Parts.turned(m, f, 0.65, 0.7, 0.65, 0.75, 0.25, 0.25, -math.pi / 4, "wood", "Handle")
	for _, b in { { 0.58, 0.58 }, { 0.73, 0.68 }, { 0.63, 0.78 } } do
		ball(m, f, b[1], 0.3, b[2], 0.25, "berry_red", "Berry")
	end
	ball(m, f, 0.3, 0.1, 0.92, 0.25, "berry_red", "Berry")
	ball(m, f, 0.95, 0.1, 0.3, 0.25, "brick", "Berry")
	tuft(m, f, -0.72, 0.72)
end

-- Tulip Row (2 x 1): a strip of dark soil edged with stones along its front, six tulips in red, yellow and pink on
-- green stems in a row, each a cup with two pointed petals and a long leaf at its foot, two buds still closed.
M.tulips = function(m, f)
	box(m, f, 0, 0.02, 0, 1.9, 0.25, 0.75, "wood_dark", "Soil")
	for k, s in ({ { -0.75, 0.5, "rock" }, { -0.3, 0.25, "pavement" }, { 0.1, 0.5, "rock" }, { 0.6, 0.25, "rock_dark" }, { 0.85, 0.25, "pavement" } } :: { { any } }) do
		Parts.turned(m, f, s[1], 0.06, 0.33, s[2], 0.25, 0.25, (k % 3 - 1) * 0.15, s[3], "EdgeStone")
	end
	local colors = { "berry_red", "yellow", "pink" }
	local across = V(0.707, 0, -0.707)
	for k = 0, 5 do
		local x = -0.6 + k * 0.24
		local z = if k % 2 == 0 then -0.08 else 0.08
		local h = if k % 2 == 1 then 0.7 else 0.55
		local c = colors[k % 3 + 1]
		box(m, f, x, 0.15 + h / 2, z, 0.25, h, 0.25, "leaf", "Stem")
		Parts.turned(m, f, x, 0.25 + h, z, 0.5, 0.25, 0.5, math.pi / 4, c, "Bloom")
		for _, s in { -1, 1 } do
			local p = V(x, 0.45 + h, z) + across * (s * 0.14)
			box(m, f, p.X, p.Y, p.Z, 0.25, 0.25, 0.25, c, "Petals")
		end
		local side = if k % 2 == 0 then 1 else -1
		put(m, f, CFrame.new(x + 0.12 * side, 0.3, z + 0.15) * CFrame.Angles(0.5, 0.3 * side, 0), 0.25, 0.5, 0.25, if k % 2 == 0 then "leaf_dark" else "leaf", nil, "Leaf")
	end
	for _, b in ({ { 0.85, -0.15, "pink" }, { -0.85, 0.1, "berry_red" } } :: { { any } }) do
		box(m, f, b[1], 0.3, b[2], 0.25, 0.5, 0.25, "leaf", "Stem")
		box(m, f, b[1], 0.6, b[2], 0.25, 0.25, 0.25, b[3], "Bud")
	end
end

-- Mushrooms (1 x 1): three toadstools of different sizes standing apart on a patch of moss, two red with white
-- spots and one brown, pale gills under their caps and a ring on the big one's stalk; a tiny one coming up, a leaf,
-- a pebble and a tuft between them.
M.mushrooms = function(m, f)
	cyl(m, f, 0, 0.0, 0, 0.75, 0.25, "moss", "Moss")
	-- the big one
	cyl(m, f, -0.12, 0.6, -0.12, 0.5, 0.25, "sand_dark", "Gills")
	shroom(m, f, -0.12, -0.12, 0.6, 0.75, "berry_red", true)
	cyl(m, f, -0.12, 0.38, -0.12, 0.5, 0.25, "white", "Ring")
	box(m, f, -0.35, 0.72, -0.05, 0.25, 0.25, 0.25, "white", "Spot")
	-- the middle one
	cyl(m, f, 0.25, 0.42, -0.2, 0.25, 0.25, "sand_dark", "Gills")
	shroom(m, f, 0.25, -0.2, 0.4, 0.5, "berry_red", false)
	box(m, f, 0.31, 0.62, -0.13, 0.25, 0.25, 0.25, "white", "Spot")
	box(m, f, 0.15, 0.72, -0.1, 0.25, 0.25, 0.25, "white", "Spot")
	-- the brown one, and a tiny one coming up
	shroom(m, f, -0.22, 0.25, 0.25, 0.5, "wood", false)
	cyl(m, f, -0.22, 0.28, 0.25, 0.25, 0.25, "sand_dark", "Gills")
	shroom(m, f, 0.2, 0.25, 0.25, 0.25, "berry_red", false)
	-- between them
	put(m, f, CFrame.new(0.22, 0.2, 0.27) * CFrame.Angles(0.25, 0.9, 0), 0.25, 0.5, 0.25, "leaf", nil, "Blade")
	put(m, f, CFrame.new(0.35, 0.15, 0.15) * CFrame.Angles(-0.3, 0.3, 0.2), 0.25, 0.25, 0.25, "leaf_dark", nil, "Blade")
	fallen(m, f, 0.0, 0.25, "orange")
	pebble(m, f, -0.3, -0.3, "rock", 0.25)
end

-- Rose Bush (2 x 2): an upright bush of dark leaf clumps in a ring of mulch, paler where the light reaches, single
-- leaves at its edge, two thorny canes reaching up out of the top; round red roses with deeper hearts on its front and
-- at the cane tips, a few closed buds, petals dropped on the mulch.
M.rosebush = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.75, 0.25, "wood_dark", "Mulch")
	local clumps: { { any } } = {
		{ 0, 0.7, 0, 1.25, "leaf_dark" },
		{ 0.4, 0.55, 0.4, 1.0, "leaf_dark" },
		{ -0.4, 0.8, 0.25, 1.0, "leaf" },
		{ 0.3, 1.05, -0.25, 1.0, "leaf" },
		{ -0.35, 0.5, -0.4, 1.0, "leaf_dark" },
		{ 0, 1.4, 0, 0.75, "leaf_dark" },
		{ 0.55, 0.45, -0.3, 0.75, "leaf" },
		{ -0.15, 0.4, 0.6, 0.75, "leaf" },
	}
	for _, c in clumps do
		ball(m, f, c[1], c[2], c[3], c[4], c[5], "Bush")
	end
	for _, k in { 3, 4, 8 } do
		local c = clumps[k]
		shine(m, f, V(c[1], c[2], c[3]), c[4], 0.5, "green")
	end
	for _, l in { { -0.9, 0.5, 0.35 }, { 0.85, 0.35, 0.45 }, { 0.2, 0.3, 0.9 } } do
		local tip = V(l[1], l[2], l[3])
		blade(m, f, tip * 0.6 + V(0, 0.1, 0), tip, 0.5, "leaf_dark", "Leaf")
	end
	-- two canes with thorns, a rose at each tip
	local canes = { { V(0.1, 1.3, 0.1), V(0.4, 2.0, 0.3) }, { V(-0.2, 1.25, -0.1), V(-0.6, 1.8, 0.05) } }
	for _, c in canes do
		limb(m, f, c[1], c[2], 0.25, "wood_dark", "Cane")
		local t = c[1]:Lerp(c[2], 0.55)
		box(m, f, t.X + 0.12, t.Y, t.Z + 0.1, 0.25, 0.25, 0.25, "wood_dark", "Thorn")
		ball(m, f, c[2].X, c[2].Y + 0.12, c[2].Z, 0.5, "berry_red", "Bloom")
		box(m, f, c[2].X + 0.05, c[2].Y + 0.27, c[2].Z + 0.05, 0.25, 0.25, 0.25, "brick", "FlowerHeart")
	end
	-- roses on the front of the clumps
	for _, r in { { 2, 0.4, 0.4, 0.8 }, { 3, -0.3, 0.6, 0.7 }, { 4, 0.6, 0.5, 0.2 }, { 1, 0.1, 0.1, 1.0 }, { 6, 0.3, 0.9, 0.4 }, { 7, 0.8, 0.3, 0.3 }, { 8, -0.3, 0.3, 0.9 } } do
		local c = clumps[r[1]]
		local p = onBall(V(c[1], c[2], c[3]), c[4] / 2, V(r[2], r[3], r[4]))
		ball(m, f, p.X, p.Y, p.Z, 0.5, "berry_red", "Bloom")
		box(m, f, p.X + 0.05, p.Y + 0.15, p.Z + 0.05, 0.25, 0.25, 0.25, "brick", "FlowerHeart")
	end
	box(m, f, -0.1, 1.85, 0.1, 0.25, 0.25, 0.25, "berry_red", "Bud")
	box(m, f, 0.75, 1.0, -0.3, 0.25, 0.25, 0.25, "berry_red", "Bud")
	box(m, f, -0.75, 1.0, -0.15, 0.25, 0.25, 0.25, "berry_red", "Bud")
	for _, p in { { 0.6, 0.75 }, { -0.55, 0.7 }, { 0.82, 0.1 } } do
		box(m, f, p[1], 0.06, p[2], 0.25, 0.25, 0.25, "berry_red", "Petal")
	end
end

-- Sunflowers (2 x 2): three tall stalks, each on its own patch of soil with three leaves up it, big heads turned up to
-- the sun (yellow petals, a gold ring, a brown seed middle) nodding slowly on their necks (Parts.move); a short young
-- one still in bud, a tuft and two fallen petals.
M.sunflowers = function(m, f)
	local face = V(0.3, 0.9, 1).Unit
	for k, s in { { -0.45, -0.45, 2.25, 1.25 }, { 0.6, -0.25, 1.85, 1.0 }, { -0.25, 0.6, 1.5, 1.0 } } do
		local x, z, h, d = s[1], s[2], s[3], s[4]
		cyl(m, f, x, 0.02, z, 0.5, 0.25, "wood_dark", "Soil")
		cyl(m, f, x, h / 2, z, 0.25, h, "leaf_dark", "Stalk")
		blade(m, f, V(x, h * 0.3, z), V(x + 0.4, h * 0.25, z + 0.1), 0.5, "leaf", "Leaf")
		blade(m, f, V(x, h * 0.5, z), V(x - 0.2, h * 0.45, z + 0.38), 0.5, "leaf_dark", "Leaf")
		blade(m, f, V(x, h * 0.7, z), V(x + 0.25, h * 0.66, z - 0.3), 0.5, "leaf", "Leaf")
		-- the head, nodding on its neck
		local head = V(x, h, z)
		local cf = CFrame.lookAt(head, head + face) * CFrame.Angles(0, math.pi / 2, 0)
		local hub, phase = V(x, h - 0.3, z), k * 1.9
		local function nod(p: BasePart)
			Parts.move(p, "swing", hub, "X", 1.1, 0.12, phase)
		end
		nod(put(m, f, cf * CFrame.new(-0.06, 0, 0), 0.25, d, d, "yellow", "Cylinder", "Petals"))
		nod(put(m, f, cf * CFrame.new(-0.01, 0, 0), 0.25, d - 0.25, d - 0.25, "gold", "Cylinder", "Petals"))
		nod(put(m, f, cf * CFrame.new(0.06, 0, 0), 0.25, d - 0.5, d - 0.5, "wood_dark", "Cylinder", "Seeds"))
		if d >= 1.25 then
			nod(put(m, f, cf * CFrame.new(0.1, 0, 0), 0.25, 0.25, 0.25, "wood", "Cylinder", "Seeds"))
		end
	end
	-- a young one still in bud
	cyl(m, f, 0.6, 0.5, 0.6, 0.25, 1.0, "leaf_dark", "Stalk")
	blade(m, f, V(0.6, 0.45, 0.6), V(0.85, 0.4, 0.75), 0.5, "leaf", "Leaf")
	ball(m, f, 0.6, 1.05, 0.6, 0.5, "leaf", "Bud")
	box(m, f, 0.6, 1.25, 0.6, 0.25, 0.25, 0.25, "yellow", "Bloom")
	-- at their feet
	tuft(m, f, 0.85, 0.05)
	fallen(m, f, 0.15, 0.75, "yellow", "Petal")
	fallen(m, f, -0.75, 0.3, "gold", "Petal")
end

-- Lavender (2 x 1): a strip of soil, three soft grey-green mounds, each with one tall stem standing up in the middle
-- and three fanning out round it, long bare green stems so the purple spikes on top stand apart, paler at the tips; a
-- few florets fallen on the soil.
M.lavender = function(m, f)
	box(m, f, 0, 0.02, 0, 1.75, 0.25, 0.75, "wood_dark", "Soil")
	for k, x in { -0.5, 0, 0.5 } do
		local z = if k == 2 then -0.05 else 0.05
		ball(m, f, x, 0.2, z, 0.75, "swamp", "Mound")
		ball(m, f, x - 0.05, 0.25, z + 0.08, 0.5, "moss", "Mound")
		for j = 0, 3 do
			local a = j / 3 * TAU + k * 0.9
			local tilt = if j == 3 then 0.05 else 0.38
			local len = if j == 3 then 1.0 else 0.75
			local cf = CFrame.new(x + (if j == 3 then 0 else math.sin(a) * 0.1), 0.2, z + (if j == 3 then 0 else math.cos(a) * 0.1)) * CFrame.Angles(0, a, 0) * CFrame.Angles(tilt, 0, 0)
			put(m, f, cf * CFrame.new(0, len / 2, 0), 0.25, len, 0.25, "moss", nil, "LavenderStem")
			put(m, f, cf * CFrame.new(0, len + 0.25, 0), 0.25, 0.5, 0.25, "purple", nil, "Bloom")
			if j ~= 1 then
				put(m, f, cf * CFrame.new(0, len + 0.55, 0), 0.25, 0.25, 0.25, "crystal", nil, "SpikeTip")
			end
		end
	end
	box(m, f, -0.3, 0.06, 0.3, 0.25, 0.25, 0.25, "purple", "Floret")
	box(m, f, 0.75, 0.06, 0.28, 0.25, 0.25, 0.25, "crystal", "Floret")
end

-- Pumpkin Patch (2 x 2): three fat pumpkins of three sizes (the two big ones ribbed with darker grooves) with stalks
-- and curled leaves, the biggest on a bed of straw; big leaves, a vine with curling tendrils, a gold flower, a small
-- green one not yet ripe, a tuft.
M.pumpkins = function(m, f)
	local across = CFrame.Angles(0, math.pi / 4, 0) -- the lobes spread across the view
	put(m, f, CFrame.new(0.2, 0.02, 0.25) * CFrame.Angles(0, 0.3, 0), 1.0, 0.25, 0.75, "straw", nil, "Straw")
	put(m, f, CFrame.new(-0.1, 0.03, 0.6) * CFrame.Angles(0, -0.5, 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
	local function pumpkin(x: number, z: number, s: number, ribs: boolean)
		local c = CFrame.new(x, 0.36 * s, z) * across
		put(m, f, c * CFrame.new(0.24 * s, -0.04, 0), 0.5 * s, 0.5 * s, 0.5 * s, "maple", "Ball", "Pumpkin")
		put(m, f, c * CFrame.new(-0.24 * s, -0.04, 0), 0.5 * s, 0.5 * s, 0.5 * s, "maple", "Ball", "Pumpkin")
		put(m, f, c, 0.75 * s, 0.75 * s, 0.75 * s, "orange", "Ball", "Pumpkin")
		if ribs then
			for _, side in { -1, 1 } do
				put(m, f, c * CFrame.new(side * 0.15 * s, 0.02, 0.29 * s), 0.25, 0.5 * s, 0.25, "maple", nil, "Groove")
			end
		end
		put(m, f, c * CFrame.new(0.05, 0.4 * s, 0) * CFrame.Angles(0, 0, 0.3), 0.25, 0.25, 0.25, "leaf_dark", nil, "PumpkinStalk")
		put(m, f, c * CFrame.new(-0.12, 0.38 * s, 0.08) * CFrame.Angles(0.2, 0.4, 0), 0.25, 0.25, 0.5, "leaf", nil, "Leaf")
	end
	for k, l in { { 0.5, 0.6, 0.4 }, { -0.7, 0.15, 1.6 }, { -0.1, -0.2, 2.6 }, { 0.65, -0.55, 3.5 }, { -0.35, -0.55, 5.0 }, { 0.6, 0.1, 2.2 } } do
		put(m, f, CFrame.new(l[1], 0.05, l[2]) * CFrame.Angles(0, l[3], 0.1), 0.75, 0.25, 0.5, if k % 2 == 0 then "leaf" else "leaf_dark", nil, "Leaf")
	end
	limb(m, f, V(-0.3, 0.08, -0.35), V(0.45, 0.08, -0.5), 0.25, "leaf_dark", "Vine")
	limb(m, f, V(-0.3, 0.08, -0.35), V(-0.6, 0.08, 0.45), 0.25, "leaf_dark", "Vine")
	limb(m, f, V(-0.6, 0.08, 0.45), V(-0.85, 0.08, 0.85), 0.25, "leaf_dark", "Vine")
	box(m, f, -0.85, 0.2, 0.85, 0.25, 0.25, 0.25, "leaf", "Tendril")
	box(m, f, 0.5, 0.2, -0.6, 0.25, 0.25, 0.25, "leaf", "Tendril")
	Parts.turned(m, f, -0.62, 0.2, 0.55, 0.5, 0.25, 0.5, math.pi / 4, "gold", "Flower")
	box(m, f, -0.62, 0.3, 0.55, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	ball(m, f, 0.8, 0.22, 0.55, 0.5, "moss", "Pumpkin")
	box(m, f, 0.8, 0.5, 0.55, 0.25, 0.25, 0.25, "leaf_dark", "PumpkinStalk")
	pumpkin(0.2, 0.25, 1.33, true)
	pumpkin(0.55, -0.55, 1.0, true)
	pumpkin(-0.6, 0.45, 0.67, false)
	tuft(m, f, 0.68, 0.72)
end

-- Cactus (1 x 1): a round barrel cactus with ribs and pale spines on a patch of sand with a ripple in it, one pink
-- flower open on top and a bud beside it, a pup at its side with a spine of its own; pebbles and a dry tuft.
M.cactus = function(m, f)
	box(m, f, 0, 0.02, 0, 0.9, 0.25, 0.9, "sand", "Sand")
	box(m, f, 0.2, 0.06, 0.32, 0.5, 0.25, 0.25, "sand_dark", "Ripple")
	cyl(m, f, 0, 0.5, 0, 0.75, 1.0, "green", "Cactus")
	ball(m, f, 0, 1.0, 0, 0.75, "green", "Cactus")
	for _, a in { -0.35, 0.3, 0.95, 1.6, 2.25 } do
		put(m, f, CFrame.new(math.sin(a) * 0.3, 0.7, math.cos(a) * 0.3) * CFrame.Angles(0, a, 0), 0.25, 1.0, 0.25, "moss", nil, "Rib")
	end
	-- (spines: pale dots just breaking the skin between the ribs)
	for _, s in { { 0.62, 1.0 }, { 1.27, 0.55 }, { -0.02, 0.35 }, { 1.92, 0.8 }, { 0.62, 0.4 } } do
		local a = s[1]
		Parts.turned(m, f, math.sin(a) * 0.34, s[2], math.cos(a) * 0.34, 0.25, 0.25, 0.25, a, "cream", "Spine")
	end
	box(m, f, 0, 1.4, 0, 0.5, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0, 1.4, 0, 0.25, 0.25, 0.5, "pink", "Flower")
	box(m, f, 0, 1.5, 0, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	box(m, f, 0.22, 1.3, -0.15, 0.25, 0.25, 0.25, "cherry", "Bud")
	ball(m, f, 0.25, 0.2, -0.25, 0.5, "green", "Pup")
	box(m, f, 0.38, 0.32, -0.12, 0.25, 0.25, 0.25, "cream", "Spine")
	pebble(m, f, -0.3, 0.3, "rock", 0.25)
	pebble(m, f, 0.3, 0.05, "clay", 0.25)
	tuft(m, f, -0.25, -0.25, 0.5, "straw", "sand_dark")
end

-- Big Leaf Plant (2 x 2): five huge leaves held out on long stalks of different heights from a dark heart in a patch
-- of soil, so they sit in layers with gaps between, each split into three fingers with a paler rib down the middle
-- one; a new leaf still rolled up rising out of the middle, two brown air roots reaching down to the ground, pebbles
-- and a tuft.
M.monstera = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.0, 0.25, "wood_dark", "Soil")
	ball(m, f, 0, 0.15, 0, 0.75, "leaf_dark", "Heart")
	local heights = { 1.75, 1.0, 1.45, 0.75, 1.25 }
	for k = 0, 4 do
		local a = k / 5 * TAU + 0.6
		local dx, dz = math.sin(a), math.cos(a)
		local hgt = heights[k + 1]
		local droop = 0.15 + hgt * 0.2
		local tip = V(dx * 0.45, hgt, dz * 0.45)
		stem(m, f, V(0, 0.15, 0), tip, 0.25, "leaf_dark", "Stalk")
		for j = -1, 1 do
			local b = a + j * 0.3
			local e = tip + V(math.sin(b) * 0.62, -droop - math.abs(j) * 0.1, math.cos(b) * 0.62)
			blade(m, f, tip, e, 0.5, if j == 0 then "leaf_dark" else "leaf", "BigLeaf")
			if j == 0 then
				blade(m, f, tip + V(0, 0.1, 0), e + V(0, 0.1, 0), 0.25, "leaf", "Rib")
			end
		end
	end
	-- a new leaf still rolled up
	stem(m, f, V(0, 0.15, 0), V(-0.1, 1.55, 0.1), 0.25, "leaf_dark", "Stalk")
	stem(m, f, V(-0.1, 1.55, 0.1), V(-0.15, 2.1, 0.15), 0.25, "green", "NewLeaf")
	-- air roots down to the ground
	limb(m, f, V(0.2, 0.55, 0.2), V(0.5, 0.06, 0.55), 0.25, "wood", "AirRoot")
	limb(m, f, V(0.25, 0.7, -0.1), V(0.7, 0.06, -0.2), 0.25, "wood", "AirRoot")
	pebble(m, f, -0.6, 0.65)
	pebble(m, f, 0.85, 0.75, "rock_dark", 0.25)
	tuft(m, f, -0.75, -0.65)
end

-- Tall Cactus (2 x 2): a tall ribbed column with two ribbed arms raised either side, pale spines, a nesting hole up
-- its front, a pink flower on top and one on an arm; a small barrel cactus in flower, rocks, a ripple in the sand and
-- a dry tuft at its foot.
M.bigcactus = function(m, f)
	box(m, f, 0, 0.02, 0, 1.75, 0.25, 1.75, "sand", "Sand")
	put(m, f, CFrame.new(0.35, 0.06, 0.6) * CFrame.Angles(0, -0.5, 0), 1.0, 0.25, 0.25, "sand_dark", nil, "Ripple")
	cyl(m, f, 0, 1.4, 0, 0.75, 2.8, "green", "Cactus")
	ball(m, f, 0, 2.8, 0, 0.75, "green", "Cactus")
	for _, a in { math.pi / 4, math.pi / 4 + 0.6, math.pi / 4 - 0.6, math.pi / 4 + 1.2 } do
		put(m, f, CFrame.new(math.sin(a) * 0.3, 1.5, math.cos(a) * 0.3) * CFrame.Angles(0, a, 0), 0.25, 2.5, 0.25, "moss", nil, "Rib")
	end
	-- the arms: out across the view, then up
	local across = V(1, 0, -1).Unit
	for k, s in { { 1, 1.2, 0.9 }, { -1, 1.6, 0.75 } } do
		local out = across * s[1]
		local elbow = out * 0.65 + V(0, s[2], 0)
		stem(m, f, V(0, s[2], 0), elbow, 0.5, "green", "Arm")
		stem(m, f, elbow, elbow + V(0, s[3], 0), 0.5, "green", "Arm")
		ball(m, f, elbow.X, elbow.Y + s[3], elbow.Z, 0.5, "green", "Arm")
		box(m, f, elbow.X + 0.12, elbow.Y + s[3] * 0.5, elbow.Z + 0.12, 0.25, s[3], 0.25, "moss", "Rib")
		if k == 1 then
			box(m, f, elbow.X, elbow.Y + s[3] + 0.25, elbow.Z, 0.25, 0.25, 0.25, "pink", "Flower")
			box(m, f, elbow.X, elbow.Y + s[3] + 0.35, elbow.Z, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
		end
	end
	box(m, f, 0, 3.2, 0, 0.5, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0, 3.2, 0, 0.25, 0.25, 0.5, "pink", "Flower")
	box(m, f, 0, 3.28, 0, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	for _, s in { { 0.48, 2.2 }, { 1.08, 1.0 }, { 1.68, 0.6 }, { -0.2, 1.75 }, { 1.08, 2.45 }, { 0.48, 1.3 } } do
		local a = s[1]
		Parts.turned(m, f, math.sin(a) * 0.34, s[2], math.cos(a) * 0.34, 0.25, 0.25, 0.25, a, "cream", "Spine")
	end
	Parts.turned(m, f, -0.12, 2.05, 0.35, 0.25, 0.5, 0.25, -0.3, "black", "NestHole")
	-- a small barrel cactus in flower
	ball(m, f, -0.55, 0.25, 0.6, 0.5, "green", "Cactus")
	box(m, f, -0.5, 0.25, 0.75, 0.25, 0.25, 0.25, "moss", "Rib")
	box(m, f, -0.55, 0.5, 0.6, 0.25, 0.25, 0.25, "pink", "Flower")
	-- rocks and dry grass
	put(m, f, CFrame.new(0.65, 0.15, -0.55) * CFrame.Angles(0, 0.4, 0.1), 0.5, 0.5, 0.5, "clay", nil, "Rock")
	put(m, f, CFrame.new(-0.65, 0.1, -0.2) * CFrame.Angles(0, -0.3, 0), 0.5, 0.25, 0.25, "sand_dark", nil, "Rock")
	pebble(m, f, 0.75, 0.15, "clay", 0.25)
	tuft(m, f, 0.65, 0.75, 0.5, "straw", "sand_dark")
end

-- Giant Mushroom (2 x 2): a thick pale stalk on a round foot, a shadowy streak down it and a two-tier skirt; a broad
-- red cap with a domed top and white spots of two sizes, pale gills in rings under its rim; three small ones, tufts
-- and a fallen leaf round it on a bed of moss.
M.giantshroom = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.75, 0.25, "moss", "Moss")
	ball(m, f, 0, 0.3, 0, 1.0, "cream", "Bulb")
	cyl(m, f, 0, 0.9, 0, 0.75, 1.5, "cream", "Stalk")
	box(m, f, 0.2, 0.8, 0.27, 0.25, 0.75, 0.25, "sand", "StalkLine")
	cyl(m, f, 0, 1.2, 0, 1.0, 0.25, "white", "Skirt")
	cyl(m, f, 0, 1.05, 0, 1.25, 0.25, "cream", "Skirt")
	cyl(m, f, 0, 1.5, 0, 1.25, 0.25, "sand", "Gills")
	cyl(m, f, 0, 1.62, 0, 2.0, 0.25, "sand_dark", "Gills")
	cyl(m, f, 0, 1.85, 0, 2.25, 0.5, "berry_red", "Cap")
	cyl(m, f, 0, 2.2, 0, 1.75, 0.25, "berry_red", "Cap")
	local dome = V(0, 2.3, 0)
	ball(m, f, dome.X, dome.Y, dome.Z, 1.5, "berry_red", "Cap")
	for _, s in { { -0.3, 0.8, 0.5, 0.5 }, { 0.5, 0.7, 0.35, 0.5 }, { 0.1, 0.95, -0.2, 0.5 }, { 0.6, 0.5, -0.45, 0.25 }, { -0.55, 0.6, -0.1, 0.25 } } do
		local p = onBall(dome, 0.75, V(s[1], s[2], s[3]), -s[4] * 0.36)
		ball(m, f, p.X, p.Y, p.Z, s[4], "white", "Spot")
	end
	for _, s in { { 0.35, 1.9, 0.5 }, { 1.0, 1.95, 0.3 }, { -0.4, 1.85, 0.75 }, { 1.2, 1.85, 0.25 } } do
		local a = s[1]
		ball(m, f, math.sin(a) * (1.125 - s[3] * 0.3), s[2], math.cos(a) * (1.125 - s[3] * 0.3), s[3], "white", "Spot")
	end
	-- small ones round its foot
	shroom(m, f, 0.7, 0.75, 0.25, 0.5, "berry_red", false)
	shroom(m, f, -0.75, 0.5, 0.25, 0.25, "berry_red", false)
	shroom(m, f, 0.8, -0.35, 0.5, 0.5, "berry_red", true)
	tuft(m, f, -0.35, 0.85)
	tuft(m, f, 0.75, 0.3)
	fallen(m, f, -0.75, -0.2, "orange")
end

-- Bonsai (1 x 1): a shallow clay tray on little feet with a paler lip, dark soil, moss and a stone in it with gravel
-- round it, a twisted trunk with a root gripping the stone, holding flat pads of leaves in tiers (each dark under and
-- paler on top), one each side, one on top and a small one low at the back.
M.bonsai = function(m, f)
	box(m, f, -0.25, 0.06, 0, 0.25, 0.25, 0.5, "wood_dark", "Foot")
	box(m, f, 0.25, 0.06, 0, 0.25, 0.25, 0.5, "wood_dark", "Foot")
	box(m, f, 0, 0.25, 0, 0.9, 0.25, 0.75, "clay", "Tray")
	box(m, f, 0, 0.42, 0.37, 0.9, 0.25, 0.25, "pot", "TrayLip")
	box(m, f, 0.45, 0.42, 0, 0.25, 0.25, 0.75, "pot", "TrayLip")
	box(m, f, 0, 0.35, 0, 0.75, 0.25, 0.5, "wood_dark", "Soil")
	box(m, f, 0.12, 0.43, 0.1, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, -0.12, 0.43, -0.15, 0.25, 0.25, 0.25, "moss", "Moss")
	ball(m, f, -0.25, 0.5, 0.12, 0.25, "rock", "Stone")
	box(m, f, -0.3, 0.42, -0.12, 0.25, 0.25, 0.25, "pavement", "Gravel")
	box(m, f, 0.3, 0.42, 0.18, 0.25, 0.25, 0.25, "pavement", "Gravel")
	local a, b, c, d = V(0, 0.4, 0), V(0.2, 0.7, -0.1), V(-0.1, 1.0, 0.05), V(0.05, 1.25, 0)
	tube(m, f, { a, b, c, d }, { 0.25, 0.25, 0.25 }, "wood_dark", "Trunk", true)
	limb(m, f, V(0, 0.5, 0), V(-0.22, 0.5, 0.12), 0.25, "wood_dark", "Root")
	limb(m, f, b, V(-0.2, 0.85, 0.25), 0.25, "wood_dark")
	limb(m, f, c, V(0.22, 1.05, -0.24), 0.25, "wood_dark")
	limb(m, f, b, V(0.05, 0.8, -0.3), 0.25, "wood_dark")
	for _, p in ({ { -0.22, 0.9, 0.27, 0.75, "leaf" }, { 0.24, 1.1, -0.26, 0.75, "green" }, { 0.05, 1.33, 0, 1.0, "green" }, { 0.05, 0.85, -0.32, 0.5, "leaf" } } :: { { any } }) do
		cyl(m, f, p[1], p[2], p[3], p[4], 0.25, "leaf_dark", "Pad")
		cyl(m, f, p[1] - 0.03, p[2] + 0.12, p[3] + 0.03, p[4] - 0.25, 0.25, p[5], "Pad")
	end
end

-- Glow Mushrooms (1 x 1): a clump of pale stalks with glowing blue caps (the biggest twinkles) on a bed of dark moss,
-- tiny glowing buttons and specks of light in it, a mossy lump and a tuft; two fireflies hover over them, rising and
-- falling (Parts.move).
M.glowshroom = function(m, f)
	cyl(m, f, 0, 0, 0, 1.0, 0.25, "swamp", "Moss")
	ball(m, f, 0.22, 0.12, 0.25, 0.5, "leaf_dark", "Moss")
	for k, s in { { -0.12, -0.12, 0.75, 0.75 }, { 0.25, -0.2, 0.5, 0.5 }, { -0.25, 0.22, 0.4, 0.5 }, { 0.2, 0.28, 0.25, 0.25 } } do
		local x, z, h, d = s[1], s[2], s[3], s[4]
		cyl(m, f, x, h / 2, z, 0.25, h, "ice", "Stalk")
		cyl(m, f, x, h + 0.05, z, d, 0.25, "blue", "CapRim")
		cyl(m, f, x, h + 0.2, z, math.max(0.25, d - 0.25), 0.25, "screen_on", if k == 1 then "Sparkle" else "Cap", true)
	end
	for _, b in { { 0.36, 0.33 }, { -0.36, -0.1 } } do
		box(m, f, b[1], 0.15, b[2], 0.25, 0.25, 0.25, "ice", "Stalk")
		Parts.glow(m, f, b[1], 0.3, b[2], 0.25, 0.25, 0.25, "screen_on", "Cap")
	end
	Parts.glow(m, f, 0.4, 0.05, 0.05, 0.25, 0.25, 0.25, "screen_on", "Speck")
	Parts.glow(m, f, -0.4, 0.05, -0.35, 0.25, 0.25, 0.25, "screen_on", "Speck")
	tuft(m, f, -0.25, 0.3, 0.5, "leaf_dark", "swamp")
	for k, p in { { 0.36, 1.45, 0.3 }, { -0.36, 1.7, -0.1 } } do
		local fly = Parts.glow(m, f, p[1], p[2], p[3], 0.25, 0.25, 0.25, "yellow", "Firefly")
		Parts.move(fly, "bob", V(p[1], p[2], p[3]), "Y", 1.4 + k * 0.3, 0.2, k * 2.1)
	end
end

-- Glass Flowers (1 x 1): three tall stems on a mound of dark moss, a glass leaf on each and two at the foot, five
-- clear petals round each flower, a glowing heart in each that twinkles; a glass shard and two glassy blades of grass.
M.glassflowers = function(m, f)
	cyl(m, f, 0, 0.02, 0, 0.75, 0.25, "leaf_dark", "Moss")
	blade(m, f, V(0, 0.12, 0), V(0.35, 0.3, 0.2), 0.25, "ice", "GlassLeaf")
	blade(m, f, V(0, 0.12, 0), V(-0.3, 0.35, 0.18), 0.25, "ice", "GlassLeaf")
	for k, c in ({ { -0.2, 0.9, -0.1, "ice" }, { 0.2, 0.7, 0.1, "crystal" }, { 0.0, 1.1, 0.25, "ice" } } :: { { any } }) do
		local foot, head = V(c[1] * 0.4, 0.1, c[3] * 0.4), V(c[1], c[2], c[3])
		stem(m, f, foot, head, 0.25, "leaf", "Stem")
		local mid = foot:Lerp(head, 0.5)
		blade(m, f, mid, mid + V(if k == 2 then 0.25 else -0.2, 0.15, 0.15), 0.25, "ice", "GlassLeaf")
		for j = 0, 4 do
			local a = j * TAU / 5 + k
			put(m, f, CFrame.new(c[1] + math.sin(a) * 0.15, c[2] + 0.05, c[3] + math.cos(a) * 0.15) * CFrame.Angles(0, a, 0.5), 0.25, 0.25, 0.25, if j % 2 == 0 then c[4] else "white", nil, "Petals")
		end
		box(m, f, c[1], c[2] + 0.12, c[3], 0.25, 0.25, 0.25, "white", "Sparkle", true)
	end
	put(m, f, CFrame.new(0.25, 0.2, -0.25) * CFrame.Angles(0.2, math.pi / 4, 0.15), 0.25, 0.5, 0.25, "crystal", nil, "Shard")
	put(m, f, CFrame.new(0.35, 0.2, 0.32) * CFrame.Angles(0.3, 0.5, 0), 0.25, 0.5, 0.25, "ice", nil, "GlassBlade")
	put(m, f, CFrame.new(-0.28, 0.2, -0.2) * CFrame.Angles(-0.3, 0.9, 0), 0.25, 0.5, 0.25, "ice", nil, "GlassBlade")
end

------------------------------------------------------------------ rocks
-- Boulder (2 x 2): one big round rock sunk a little in the grass, a darker lump low on its shady side, worn pale on its
-- lit top, a crack across its front, spots of lichen; chips broken off at its foot, moss on its shady side, pebbles,
-- tufts and a flower beside it.
M.boulder = function(m, f)
	local c = V(0, 0.62, 0)
	cyl(m, f, 0, 0.05, 0, 1.75, 0.25, "rock_dark", "Base")
	ball(m, f, c.X, c.Y, c.Z, 1.75, "rock", "Boulder")
	ball(m, f, -0.25, 0.75, -0.3, 1.25, "rock", "Boulder")
	ball(m, f, 0.5, 0.42, -0.4, 1.0, "rock_dark", "Boulder")
	shine(m, f, c, 1.75, 0.75, "pavement", "Facet")
	local p = onBall(c, 0.875, V(0.45, 0.85, 0.1), -0.15)
	ball(m, f, p.X, p.Y, p.Z, 0.5, "pavement", "Facet")
	shine(m, f, V(-0.25, 0.75, -0.3), 1.25, 0.5, "pavement", "Facet")
	-- a crack across the front
	local k1, k2, k3 = onBall(c, 0.875, V(-0.1, 0.55, 0.85), -0.04), onBall(c, 0.875, V(0.25, 0.25, 0.95), -0.04), onBall(c, 0.875, V(0.15, -0.1, 0.98), -0.04)
	limb(m, f, k1, k2, 0.25, "rock_dark", "Crack")
	limb(m, f, k2, k3, 0.25, "rock_dark", "Crack")
	limb(m, f, k2, onBall(c, 0.875, V(0.6, 0.25, 0.75), -0.04), 0.25, "rock_dark", "Crack")
	for _, l in ({ { 0.5, 0.75, 0.45, "bamboo" }, { -0.55, 0.5, 0.65, "moss" }, { 0.8, 0.45, 0.05, "bamboo" } } :: { { any } }) do
		local q = onBall(c, 0.875, V(l[1], l[2], l[3]), -0.05)
		box(m, f, q.X, q.Y, q.Z, 0.25, 0.25, 0.25, l[4], "Lichen")
	end
	-- at its foot
	put(m, f, CFrame.new(0.6, 0.18, 0.5) * CFrame.Angles(0.15, 0.6, -0.2), 0.5, 0.5, 0.5, "rock", nil, "Chip")
	put(m, f, CFrame.new(-0.55, 0.12, 0.78) * CFrame.Angles(-0.1, -0.3, 0.1), 0.5, 0.25, 0.25, "rock_dark", nil, "Chip")
	ball(m, f, 0.75, 0.15, -0.65, 0.5, "moss", "Moss")
	pebble(m, f, 0.72, -0.05)
	pebble(m, f, 0.25, 0.8, "rock_dark")
	pebble(m, f, 0.8, 0.75, "rock", 0.25)
	pebble(m, f, -0.8, 0.3, "rock_dark", 0.25)
	tuft(m, f, -0.7, 0.62)
	tuft(m, f, 0.78, 0.38)
	flower(m, f, -0.25, 0.85, 0.25, "yellow")
end

-- Rock Pile (2 x 2): a heap of round stones in three greys, big ones at the bottom, smaller on top, paler where the
-- light falls; broken flat slabs with sharp faces leaning on it, moss in its gaps, pebbles, tufts and a flower round
-- it.
M.rockpile = function(m, f)
	local stones: { { any } } = {
		{ -0.45, 0.3, -0.4, 0.75, "rock" },
		{ 0.4, 0.3, -0.4, 0.75, "rock_dark" },
		{ -0.45, 0.25, 0.35, 0.75, "rock_dark" },
		{ 0.0, 0.2, 0.7, 0.5, "rock" },
		{ 0.75, 0.2, 0.0, 0.5, "rock" },
		{ -0.1, 0.65, -0.15, 0.75, "pavement" },
		{ 0.3, 0.6, 0.15, 0.5, "rock" },
		{ -0.35, 0.62, 0.15, 0.5, "rock" },
		{ 0.0, 1.0, 0.0, 0.5, "rock_dark" },
	}
	for _, s in stones do
		ball(m, f, s[1], s[2], s[3], s[4], s[5], "Stone")
	end
	for _, k in { 7, 8, 9 } do
		local s = stones[k]
		shine(m, f, V(s[1], s[2], s[3]), s[4], 0.25, if s[5] == "rock_dark" then "rock" else "pavement")
	end
	put(m, f, CFrame.new(0.5, 0.22, 0.48) * CFrame.Angles(0.1, 0.5, 0.35), 0.75, 0.25, 0.5, "pavement", nil, "Slab")
	put(m, f, CFrame.new(-0.6, 0.2, -0.05) * CFrame.Angles(0, -0.4, -0.5), 0.5, 0.25, 0.5, "rock", nil, "Slab")
	put(m, f, CFrame.new(0.15, 0.85, 0.35) * CFrame.Angles(0.3, 0.8, 0.2), 0.5, 0.25, 0.25, "rock_dark", nil, "Slab")
	ball(m, f, 0.05, 0.4, -0.65, 0.5, "moss", "Moss")
	ball(m, f, -0.2, 0.35, 0.6, 0.25, "moss", "Moss")
	pebble(m, f, 0.75, -0.7)
	pebble(m, f, -0.66, 0.66, "rock_dark")
	pebble(m, f, 0.5, 0.8, "rock", 0.25)
	pebble(m, f, 0.82, 0.45, "pavement", 0.25)
	pebble(m, f, -0.5, 0.82, "rock", 0.25)
	tuft(m, f, 0.75, 0.75)
	tuft(m, f, -0.75, 0.42)
	flower(m, f, 0.25, 0.85, 0.25, "white")
end

-- Mossy Rock (2 x 2): a big rough rock, half block and half round, a thick coat of moss over its top with lumps in it
-- and drips of it down its shady side, lichen and a crack on its front; a chip and a small stone at its foot, a fern,
-- a mushroom, a flower, pebbles and a tuft beside it.
M.mossrock = function(m, f)
	local a = CFrame.new(0.05, 0.4, 0.05) * CFrame.Angles(0.05, 0.3, -0.05)
	put(m, f, a, 1.5, 0.9, 1.25, "rock", nil, "Rock")
	put(m, f, a * CFrame.new(0, 0.5, 0), 1.25, 0.25, 1.0, "moss", nil, "Moss")
	ball(m, f, -0.1, 0.95, 0.25, 0.5, "moss", "Moss")
	ball(m, f, 0.35, 0.92, -0.05, 0.5, "grass", "Moss")
	for _, d in { { -0.35, 0.75 }, { 0.0, 0.5 }, { 0.3, 0.75 } } do
		put(m, f, a * CFrame.new(0.74, 0.5 - d[2] / 2, d[1]), 0.25, d[2], 0.25, "moss", nil, "Moss")
	end
	put(m, f, a * CFrame.new(-0.35, 0.1, 0.63), 0.25, 0.25, 0.25, "bamboo", nil, "Lichen")
	put(m, f, a * CFrame.new(0.4, -0.15, 0.63), 0.25, 0.25, 0.25, "bamboo", nil, "Lichen")
	put(m, f, a * CFrame.new(0.05, 0.05, 0.63) * CFrame.Angles(0, 0, 0.9), 0.5, 0.25, 0.25, "rock_dark", nil, "Crack")
	ball(m, f, -0.35, 0.8, -0.35, 1.25, "rock_dark", "Rock")
	ball(m, f, -0.35, 1.0, -0.35, 1.0, "moss", "Moss")
	shine(m, f, V(-0.35, 1.0, -0.35), 1.0, 0.5, "grass", "Moss")
	put(m, f, CFrame.new(0.6, 0.15, 0.6) * CFrame.Angles(0, 0.7, 0.1), 0.5, 0.25, 0.5, "rock_dark", nil, "Rock")
	put(m, f, CFrame.new(-0.2, 0.1, 0.75) * CFrame.Angles(0.2, -0.4, 0.3), 0.5, 0.25, 0.25, "rock", nil, "Chip")
	for k = 0, 3 do
		local ang = k / 4 * TAU + 0.4
		blade(m, f, V(-0.6, 0.1, 0.6), V(-0.6 + math.sin(ang) * 0.25, 0.45, 0.6 + math.cos(ang) * 0.25), 0.25, if k % 2 == 0 then "leaf" else "leaf_dark", "Frond")
	end
	shroom(m, f, 0.85, 0.2, 0.25, 0.25, "wood", false)
	flower(m, f, 0.3, 0.82, 0.25, "white")
	pebble(m, f, 0.75, -0.6)
	pebble(m, f, -0.8, 0.15, "rock_dark", 0.25)
	pebble(m, f, 0.05, 0.82, "rock", 0.25)
	tuft(m, f, 0.78, 0.75)
end

-- Desert Rock (2 x 2): a small arch of red rock worn through by the wind, banded in three reds with paler streaks,
-- the underside of the arch worn darker, holes in it and stepped chips on top; sand drifted against its feet, loose
-- rocks and pebbles, a tiny cactus in flower and a dry tuft.
M.sandrock = function(m, f)
	local a = CFrame.Angles(0, math.pi / 4, 0) -- the arch spans across the view
	for _, s in { -1, 1 } do
		put(m, f, a * CFrame.new(s * 0.62, 0.12, 0), 0.75, 0.25, 0.75, "brick", nil, "Rock")
		put(m, f, a * CFrame.new(s * 0.6, 0.5, 0), 0.5, 0.75, 0.75, "clay", nil, "Rock")
		put(m, f, a * CFrame.new(s * 0.55, 1.0, 0.02), 0.5, 0.25, 0.75, "sand_dark", nil, "Rock")
		put(m, f, a * CFrame.new(s * 0.6, 0.62, 0.36), 0.5, 0.25, 0.25, "sand_dark", nil, "Band")
	end
	put(m, f, a * CFrame.new(0, 1.3, 0), 1.75, 0.5, 0.75, "clay", nil, "Rock")
	put(m, f, a * CFrame.new(0, 1.1, 0), 0.75, 0.25, 0.5, "brick", nil, "Worn")
	put(m, f, a * CFrame.new(0.05, 1.62, -0.02), 1.5, 0.25, 0.75, "brick", nil, "Rock")
	put(m, f, a * CFrame.new(-0.1, 1.82, 0), 1.0, 0.25, 0.5, "clay", nil, "Rock")
	put(m, f, a * CFrame.new(-0.3, 1.36, 0.36), 0.75, 0.25, 0.25, "sand", nil, "Band")
	for _, h in { -0.55, 0.45 } do
		put(m, f, a * CFrame.new(h, 1.3, 0.36), 0.25, 0.25, 0.25, "brick", nil, "Hole")
	end
	put(m, f, a * CFrame.new(0.35, 1.95, 0.1) * CFrame.Angles(0, 0.3, 0), 0.5, 0.25, 0.25, "clay", nil, "Chip")
	put(m, f, a * CFrame.new(-0.4, 2.0, -0.05), 0.25, 0.25, 0.25, "sand_dark", nil, "Chip")
	-- sand against its feet
	put(m, f, a * CFrame.new(-0.62, 0.06, 0.35), 0.75, 0.25, 0.25, "sand", nil, "Drift")
	ball(m, f, 0.6, 0.1, 0.15, 0.5, "sand_dark", "Drift")
	put(m, f, CFrame.new(0.65, 0.2, -0.45) * CFrame.Angles(0, -0.3, 0.1), 0.5, 0.5, 0.5, "clay", nil, "Rock")
	pebble(m, f, -0.45, 0.8, "brick", 0.25)
	pebble(m, f, 0.75, 0.5, "clay")
	pebble(m, f, 0.3, 0.82, "sand_dark", 0.25)
	-- a tiny cactus and a dry tuft
	cyl(m, f, -0.75, 0.25, 0.3, 0.25, 0.5, "green", "Cactus")
	box(m, f, -0.75, 0.55, 0.3, 0.25, 0.25, 0.25, "pink", "Flower")
	tuft(m, f, 0.7, 0.75, 0.5, "straw", "sand_dark")
end

-- Crystal Cluster (2 x 2): six purple crystals of different heights leaning out of a dark rock with rough chunks at its
-- foot, faceted in two shades, a pale streak of light down three of them (the biggest glowing and twinkling); small
-- points coming up round it, glowing shards and pebbles at their feet, a shard floating over them, rising and falling
-- (Parts.move).
local function crystal(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, color: string, neon: boolean?)
	put(m, f, cf * CFrame.new(0, h / 2, 0), w, h, w, color, nil, "Crystal", neon)
	cone(m, f, cf * CFrame.new(0, h, 0), w, w, color, "CrystalTip", neon)
end
M.crystals = function(m, f)
	cyl(m, f, 0, 0.18, 0, 1.25, 0.5, "rock_dark", "Rock")
	ball(m, f, -0.05, 0.35, -0.05, 1.0, "rock_dark", "Rock")
	put(m, f, CFrame.new(0.55, 0.2, 0.35) * CFrame.Angles(0.2, 0.7, 0.1), 0.75, 0.5, 0.5, "rock", nil, "Rock")
	put(m, f, CFrame.new(-0.55, 0.15, 0.45) * CFrame.Angles(-0.1, -0.4, 0.15), 0.5, 0.5, 0.5, "rock_dark", nil, "Rock")
	local list: { { any } } = {
		{ 0, 0, 0, 0, 0, 0.75, 1.5, "crystal" },
		{ -0.4, 0.1, 0.1, 0.35, 0.2, 0.5, 1.0, "purple" },
		{ 0.35, 0.1, -0.1, -0.15, -0.25, 0.5, 1.25, "crystal" },
		{ 0.15, 0.1, 0.25, 0.15, 0.15, 0.5, 0.75, "purple" },
		{ -0.3, 0.1, -0.35, -0.3, 0.3, 0.5, 0.75, "crystal" },
		{ 0.42, 0.05, 0.32, 0.15, -0.3, 0.5, 0.5, "purple" },
	}
	for k, c in list do
		local cf = CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(c[4], math.pi / 4, c[5])
		crystal(m, f, cf, c[6], c[7], c[8])
		-- a streak of light down the face turned to the view
		if k == 1 then
			put(m, f, cf * CFrame.new(-0.12, c[7] * 0.55, c[6] / 2), 0.25, c[7] * 0.6, 0.25, "white", nil, "Sparkle", true)
		elseif k == 2 or k == 3 then
			put(m, f, cf * CFrame.new(-0.06, c[7] * 0.55, c[6] / 2), 0.25, c[7] * 0.5, 0.25, if k == 2 then "crystal" else "white", nil, "Shine")
		end
	end
	for _, s in ({ { -0.75, 0.15, 0.3, 0.2, "purple" }, { 0.75, -0.45, -0.25, 0.3, "crystal" }, { 0.05, 0.8, 0.2, -0.3, "purple" } } :: { { any } }) do
		put(m, f, CFrame.new(s[1], 0.15, s[2]) * CFrame.Angles(s[3], math.pi / 4, s[4]), 0.25, 0.5, 0.25, s[5], nil, "Point")
	end
	for _, s in { { 0.6, -0.35, 0.4 }, { -0.55, 0.55, -0.5 }, { 0.15, 0.75, 0.3 } } do
		put(m, f, CFrame.new(s[1], 0.2, s[2]) * CFrame.Angles(s[3], math.pi / 4, 0), 0.25, 0.5, 0.25, "crystal", nil, "Shard", true)
	end
	pebble(m, f, 0.72, 0.72, "rock_dark")
	pebble(m, f, -0.8, -0.2, "rock", 0.25)
	local fl = put(m, f, CFrame.new(0.45, 1.75, 0.55) * CFrame.Angles(0, math.pi / 4, 0), 0.25, 0.5, 0.25, "crystal", nil, "Sparkle", true)
	Parts.move(fl, "bob", V(0.45, 1.75, 0.55), "Y", 1.3, 0.15, 0)
end

-- Snowy Rock (2 x 2): a blue-grey rock with a smaller one on top, paler chips on its front, each under a thick cap of
-- snow drooping over the front edges in lumps, icicles of different lengths; snow drifted on the grass with a snowball,
-- a frosty tuft and a bird's tracks in it, pebbles.
M.snowrock = function(m, f)
	local a = CFrame.new(-0.05, 0.4, -0.05) * CFrame.Angles(0, 0.25, 0.04)
	put(m, f, a, 1.5, 0.9, 1.25, "slate", nil, "Rock")
	put(m, f, a * CFrame.new(-0.35, -0.1, 0.63) * CFrame.Angles(0, 0, 0.3), 0.5, 0.25, 0.25, "steel_dark", nil, "Chip")
	put(m, f, a * CFrame.new(0.76, -0.15, 0.2), 0.25, 0.25, 0.5, "steel_dark", nil, "Chip")
	put(m, f, a * CFrame.new(0.2, -0.05, 0.63) * CFrame.Angles(0, 0, -0.7), 0.5, 0.25, 0.25, "basalt", nil, "Crack")
	put(m, f, a * CFrame.new(0, 0.55, 0), 1.5, 0.25, 1.25, "snow", nil, "Snow")
	put(m, f, a * CFrame.new(0.6, 0.38, 0.2), 0.5, 0.25, 0.75, "snow", nil, "Snow")
	put(m, f, a * CFrame.new(-0.2, 0.35, 0.55), 0.75, 0.25, 0.25, "snow", nil, "Snow")
	for _, l in { { -0.55, 0.62 }, { 0.15, 0.6 }, { 0.72, -0.3 } } do
		local p = a * CFrame.new(l[1], 0.5, l[2])
		ball(m, f, p.X, p.Y, p.Z, 0.5, "snow", "Snow")
	end
	-- icicles under the snow's front edge and its right edge
	for _, i in { { 0.5, 0.6, 0.5 }, { -0.4, 0.6, 0.25 }, { 0.76, -0.2, 0.25 }, { 0.76, 0.45, 0.5 } } do
		put(m, f, a * CFrame.new(i[1], 0.3 - i[3] / 2, i[2]), 0.25, i[3], 0.25, "ice", nil, "Icicle")
	end
	local b = CFrame.new(-0.3, 1.05, -0.3) * CFrame.Angles(0.05, -0.4, 0)
	put(m, f, b, 0.75, 0.5, 0.75, "rock_dark", nil, "Rock")
	put(m, f, b * CFrame.new(0, 0.35, 0), 0.75, 0.25, 0.75, "snow", nil, "Snow")
	ball(m, f, -0.3, 1.5, -0.3, 0.5, "snow", "Snow")
	-- snow on the grass
	box(m, f, 0.6, 0.0, 0.7, 0.75, 0.25, 0.5, "snow", "Drift")
	box(m, f, -0.7, 0.0, 0.6, 0.5, 0.25, 0.5, "snow", "Drift")
	ball(m, f, 0.72, 0.12, 0.3, 0.5, "snow", "Drift")
	ball(m, f, -0.45, 0.18, 0.85, 0.25, "snow", "Snowball")
	for _, p in { { 0.35, 0.72 }, { 0.58, 0.58 }, { 0.82, 0.72 } } do
		box(m, f, p[1], 0.02, p[2], 0.25, 0.25, 0.25, "ice", "Track")
	end
	tuft(m, f, 0.75, -0.6, 0.5, "leaf_dark", "swamp")
	pebble(m, f, -0.8, 0.15, "slate", 0.25)
	pebble(m, f, 0.2, 0.82, "rock_dark", 0.25)
end

-- Basalt Columns (2 x 2): seven six-sided pillars of black rock packed together, tallest at the back, their worn tops
-- paler and stepped on the tall ones, moss on two of the low ones and rain lying on another; lichen on their faces,
-- broken pieces lying at the front, a fern and a tuft in the gaps, pebbles.
local function column(m: Instance, f: CFrame, x: number, z: number, h: number, color: string)
	for k = 0, 2 do
		Parts.turned(m, f, x, h / 2, z, 0.5, h, 0.75, k * math.pi / 3, color, "Column")
	end
	cyl(m, f, x, h + 0.02, z, 0.75, 0.25, "steel_dark", "ColumnTop")
end
M.basaltcols = function(m, f)
	local s = 0.6
	column(m, f, 0, 0, 1.75, "basalt")
	cyl(m, f, 0, 2.02, 0, 0.5, 0.25, "slate", "ColumnTop")
	local cols = { { -0.866, -0.5, 1.5 }, { 0, -1, 2.25 }, { 0.866, -0.5, 1.25 }, { -0.866, 0.5, 1.0 }, { 0, 1, 0.5 }, { 0.866, 0.5, 0.75 } }
	for k, c in cols do
		local x, z, h = c[1] * s, c[2] * s, c[3]
		column(m, f, x, z, h, if k % 2 == 0 then "slate" else "basalt")
		if h >= 1.5 then
			cyl(m, f, x, h + 0.27, z, 0.5, 0.25, "slate", "ColumnTop")
		elseif h <= 0.75 then
			cyl(m, f, x - 0.05, h + 0.2, z + 0.05, 0.5, 0.25, "moss", "Moss")
		elseif h == 1.25 then
			Parts.water(m, f, x, h + 0.16, z, 0.5, 0.5)
		end
	end
	box(m, f, -0.35, 0.6, 0.62, 0.25, 0.25, 0.25, "bamboo", "Lichen")
	box(m, f, 0.75, 0.4, 0.35, 0.25, 0.25, 0.25, "bamboo", "Lichen")
	-- broken pieces at the front
	put(m, f, CFrame.new(0.65, 0.15, 0.7) * CFrame.Angles(0, 0.4, 0), 0.5, 0.25, 0.25, "basalt", nil, "Shard")
	put(m, f, CFrame.new(0.1, 0.2, 0.62) * CFrame.Angles(0, -0.5, math.pi / 2), 0.5, 0.75, 0.5, "basalt", nil, "Shard")
	put(m, f, CFrame.new(0.65, 0.12, 0.05) * CFrame.Angles(0, 1.0, math.pi / 2), 0.25, 0.5, 0.5, "slate", nil, "Shard")
	for j, d in { { -0.3, 0.45, 0.1 }, { 0.1, 0.5, 0.35 }, { 0.3, 0.35, -0.05 } } do
		blade(m, f, V(-0.6, 0.1, 0.6), V(-0.6 + d[1], d[2], 0.6 + d[3] * 0.6), 0.25, if j == 2 then "leaf" else "leaf_dark", "Fern")
	end
	tuft(m, f, 0.5, 0.78)
	pebble(m, f, -0.3, 0.82, "basalt", 0.25)
	pebble(m, f, 0.75, -0.55, "slate")
end

-- Lava Rock (2 x 2): black rocks with a darker crust, glowing cracks across their fronts, a pool of lava on top with a
-- bubble rising and falling in it (Parts.move) and sparks coming off it, a trickle spilling over its front edge; a
-- vent on the top rock smoking; a scorched patch, embers and grey ash round it.
M.lavarock = function(m, f)
	put(m, f, CFrame.new(0.4, 0.0, 0.4) * CFrame.Angles(0, 0.4, 0), 1.0, 0.25, 0.5, "basalt", nil, "Scorch")
	local a = CFrame.new(-0.1, 0.45, -0.1) * CFrame.Angles(0.06, 0.35, -0.05)
	put(m, f, a, 1.5, 1.0, 1.25, "basalt", nil, "Rock")
	local b = CFrame.new(0.5, 0.25, 0.5) * CFrame.Angles(-0.1, -0.4, 0.1)
	put(m, f, b, 0.75, 0.5, 0.75, "basalt", nil, "Rock")
	local c = CFrame.new(-0.3, 1.05, -0.3) * CFrame.Angles(0.08, 1.0, 0.05)
	put(m, f, c, 0.75, 0.5, 0.75, "basalt", nil, "Rock")
	put(m, f, CFrame.new(-0.62, 0.15, 0.55) * CFrame.Angles(0.1, 0.6, 0.2), 0.5, 0.25, 0.5, "basalt", nil, "Rock")
	-- the crust, darker and lumpy
	put(m, f, a * CFrame.new(-0.5, 0.52, -0.3), 0.5, 0.25, 0.5, "black", nil, "Crust")
	put(m, f, b * CFrame.new(0.1, 0.27, -0.1), 0.5, 0.25, 0.25, "black", nil, "Crust")
	-- cracks on a's front (+Z) and right (+X) faces, and on b's front and c's side
	put(m, f, a * CFrame.new(-0.2, 0.05, 0.55) * CFrame.Angles(0, 0, 0.5), 0.75, 0.25, 0.25, "lava", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.25, -0.2, 0.55), 0.25, 0.5, 0.25, "lava", nil, "Crack", true)
	put(m, f, a * CFrame.new(-0.55, -0.3, 0.55) * CFrame.Angles(0, 0, -0.6), 0.25, 0.25, 0.25, "orange", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.68, 0.05, -0.2) * CFrame.Angles(0.6, 0, 0), 0.25, 0.25, 0.75, "lava", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.68, -0.3, 0.3) * CFrame.Angles(-0.5, 0, 0), 0.25, 0.25, 0.5, "orange", nil, "Crack", true)
	put(m, f, b * CFrame.new(0.05, 0.05, 0.3), 0.25, 0.25, 0.25, "orange", nil, "Crack", true)
	put(m, f, b * CFrame.new(0.3, -0.1, 0.05), 0.25, 0.25, 0.25, "lava", nil, "Crack", true)
	put(m, f, c * CFrame.new(0.3, 0.0, 0.1), 0.25, 0.25, 0.25, "lava", nil, "Crack", true)
	-- the pool on top, and its spill down the front into a puddle
	put(m, f, a * CFrame.new(0.25, 0.42, 0.2), 0.5, 0.25, 0.5, "lava", nil, "Pool", true)
	put(m, f, a * CFrame.new(0.25, 0.45, 0.2), 0.25, 0.25, 0.25, "yellow", nil, "Flame", true)
	put(m, f, a * CFrame.new(0.3, 0.32, 0.55), 0.25, 0.5, 0.25, "lava", nil, "Spill", true)
	local pool = (a * CFrame.new(0.15, 0.62, 0.25)).Position
	Parts.move(put(m, f, CFrame.new(pool), 0.25, 0.25, 0.25, "yellow", "Ball", "Bubble", true), "bob", pool, "Y", 2.0, 0.08, 0)
	-- the vent on the top rock
	put(m, f, c * CFrame.new(0.1, 0.3, 0.1), 0.25, 0.25, 0.25, "black", nil, "Smoke")
	-- embers and ash on the grass
	Parts.glow(m, f, 0.85, 0.02, -0.4, 0.25, 0.25, 0.25, "orange", "Ember")
	Parts.glow(m, f, -0.75, 0.02, 0.85, 0.25, 0.25, 0.25, "lava", "Ember")
	Parts.glow(m, f, 0.9, 0.02, 0.85, 0.25, 0.25, 0.25, "orange", "Ember")
	pebble(m, f, -0.8, 0.2, "rock_dark", 0.25)
	pebble(m, f, 0.78, 0.15, "rock_dark")
	pebble(m, f, 0.35, 0.82, "rock", 0.25)
	pebble(m, f, -0.3, 0.78, "rock")
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor"; the Starfruit Tree and the Redwood are
-- with the trees above)

-- Geode (2 x 2): a plain grey rock split in two and opened toward the view like a book: the back half standing, leaning
-- back, its hollow facing out; the front half lying on the grass, its hollow facing up. Each is rough and lumpy
-- outside, with a pale band of agate round a purple lining and crystal points growing out of it, a glow in the back
-- half that twinkles; purple chips, bits of rock and a tuft round it.
M.geode = function(m, f)
	local g = CFrame.Angles(0, math.pi / 4, 0) -- its +Z faces the view
	-- the back half: a round rock with its cut face turned out (discs facing +Z on its front)
	local b = g * CFrame.new(0, 0.75, -0.15) * CFrame.Angles(-0.3, 0, 0)
	local face = CFrame.Angles(0, math.pi / 2, 0) -- (a cylinder's axis along +Z)
	put(m, f, b * CFrame.new(0, 0, -0.4), 1.25, 1.25, 1.25, "rock", "Ball", "Shell")
	put(m, f, b * CFrame.new(0.42, 0.35, -0.25), 0.5, 0.5, 0.5, "rock_dark", "Ball", "Shell")
	put(m, f, b * CFrame.new(-0.45, -0.3, -0.2), 0.5, 0.5, 0.5, "rock_dark", "Ball", "Shell")
	put(m, f, b * CFrame.new(0, 0, 0.2) * face, 0.25, 1.0, 1.0, "cream", "Cylinder", "Agate")
	put(m, f, b * CFrame.new(0, 0, 0.26) * face, 0.25, 0.75, 0.75, "purple", "Cylinder", "Lining")
	put(m, f, b * CFrame.new(0.05, -0.05, 0.35), 0.5, 0.25, 0.25, "crystal", nil, "Sparkle", true)
	for k, c in ({ { -0.18, 0.18, 0.5, "crystal" }, { 0.2, 0.15, 0.25, "purple" }, { 0.05, -0.15, 0.25, "crystal" }, { -0.2, -0.12, 0.25, "purple" } } :: { { any } }) do
		local tilt = if k % 2 == 0 then 0.15 else -0.15
		crystal(m, f, b * CFrame.new(c[1], c[2], 0.35) * CFrame.Angles(math.pi / 2 - 0.25, 0, tilt) * CFrame.Angles(0, math.pi / 4, 0), 0.25, c[3], c[4])
	end
	-- the front half: lying on the grass, its cut face up
	local h = g * CFrame.new(0, 0, 0.55)
	cyl(m, f, h.X, 0.1, h.Z, 1.0, 0.25, "rock", "Shell")
	put(m, f, h * CFrame.new(0.35, 0.12, 0.15), 0.5, 0.5, 0.5, "rock_dark", "Ball", "Shell")
	put(m, f, h * CFrame.new(-0.35, 0.12, 0.05), 0.5, 0.5, 0.5, "rock", "Ball", "Shell")
	cyl(m, f, h.X, 0.25, h.Z, 0.75, 0.25, "cream", "Agate")
	cyl(m, f, h.X, 0.31, h.Z, 0.5, 0.25, "purple", "Lining")
	for k, c in ({ { -0.12, 0.05, 0.5, "crystal" }, { 0.15, -0.05, 0.25, "purple" }, { 0.05, 0.18, 0.25, "purple" } } :: { { any } }) do
		crystal(m, f, h * CFrame.new(c[1], 0.38, c[2]) * CFrame.Angles(0.25, math.pi / 4, if k == 1 then 0.2 else -0.15), 0.25, c[3], c[4])
	end
	-- round it
	box(m, f, 0.7, 0.05, 0.75, 0.25, 0.25, 0.25, "purple", "Chip")
	box(m, f, -0.35, 0.05, 0.85, 0.25, 0.25, 0.25, "crystal", "Chip")
	pebble(m, f, 0.72, -0.6)
	pebble(m, f, -0.8, 0.6, "rock_dark", 0.25)
	tuft(m, f, 0.75, 0.3)
end

return M
