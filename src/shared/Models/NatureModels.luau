--!strict
-- The trees, plants and rocks of the Nature tab (GAME_DESIGN 4; Data/Buildings). Roblox module (server and client).
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- The view looks from +X +Z and down: the +Z faces show on the left (lit), the +X faces on the right (shaded), so
-- the telling details sit on those sides. Leaves in leaf / leaf_dark sway by themselves; blossom, autumn leaves and
-- snow on branches are marked to sway as well. A tree's crown may reach a little past its footprint, its trunk never.
-- A trunk is smooth (2026-11-13: "make the trunk connected smoothly as well without the stepped boxes"): one column
-- from the ground (on a flat plate of roots at most), or round segments joined by balls where it bends (`tube`),
-- never a stack of steps. Nothing reaches far below the ground: the pictures drawn from a model stand it on its box.
local Blocks = require(script.Parent.Blocks)
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

local box, ball, cyl = Parts.box, Parts.ball, Parts.cyl

type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"

------------------------------------------------------------------ helpers
-- Any part at `cf` (f's frame).
local function put(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, shape: Shape?, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, shape = shape, name = name, neon = neon, collide = false })
end

-- Marks a part to sway in the wind the way the leaves do.
local function sway(p: BasePart): BasePart
	p:SetAttribute("PixelWind", 1)
	return p
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
local function clump(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, top: string, under: string): { BasePart }
	local a = ball(m, f, x, y - dia * 0.2, z, dia * 0.85, under, "LeavesUnder")
	local b = ball(m, f, x, y, z, dia, top, "Leaves")
	return { a, b }
end

------------------------------------------------------------------ trees
-- Pine Tree (2 x 2): a dark trunk under four stacked green cones, narrower going up; cones on the grass.
M.pine = function(m, f)
	cyl(m, f, 0, 0.12, 0, 0.75, 0.25, "wood_dark", "Root")
	cyl(m, f, 0, 0.85, 0, 0.5, 1.5, "wood_dark", "Trunk")
	for _, t in { { 2.5, 0.85, 1.5 }, { 2.0, 1.75, 1.5 }, { 1.5, 2.65, 1.25 }, { 1.0, 3.45, 1.25 } } do
		cone(m, f, CFrame.new(0, t[2], 0), t[1], t[3], "leaf_dark", "Needles")
	end
	ball(m, f, 0.7, 0.12, 0.6, 0.25, "wood", "PineCone")
	ball(m, f, -0.35, 0.12, 0.85, 0.25, "wood", "PineCone")
end

-- Oak Tree (3 x 3): a stout trunk on a flare of roots, three limbs, a round crown of leaf clumps, a knot hole.
M.oak = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	for _, a in { 0.5, 2.2, 3.9, 5.3 } do
		put(m, f, CFrame.new(math.sin(a) * 0.5, 0.15, math.cos(a) * 0.5) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(18), 0, 0), 0.3, 0.3, 0.75, "wood_dark", nil, "Root")
	end
	cyl(m, f, 0, 1.25, 0, 0.75, 2.5, "wood_dark", "Trunk")
	box(m, f, 0.1, 1.1, 0.32, 0.25, 0.25, 0.25, "black", "Knot")
	limb(m, f, Vector3.new(0, 1.9, 0), Vector3.new(0.9, 2.7, 0.45), 0.3, "wood_dark")
	limb(m, f, Vector3.new(0, 2.0, 0), Vector3.new(-0.8, 2.8, -0.3), 0.3, "wood_dark")
	limb(m, f, Vector3.new(0, 2.2, 0), Vector3.new(0.25, 2.9, -0.85), 0.3, "wood_dark")
	ball(m, f, 0, 2.95, 0, 2.25, "leaf_dark", "LeavesUnder")
	ball(m, f, 0, 3.45, 0, 2.5, "leaf", "Leaves")
	ball(m, f, 0.95, 3.0, 0.55, 1.5, "leaf_dark", "Leaves")
	ball(m, f, -0.6, 3.15, 0.95, 1.5, "leaf", "Leaves")
	ball(m, f, 0.7, 3.5, -0.8, 1.5, "leaf", "Leaves")
	ball(m, f, -0.95, 3.6, -0.4, 1.5, "leaf_dark", "Leaves")
	ball(m, f, 0.5, 3.95, 0.55, 1.25, "leaf", "Leaves")
	ball(m, f, -0.2, 4.4, -0.1, 1.5, "leaf", "Leaves")
end

-- Bare Tree (2 x 2): a crooked trunk in four bends, forked branches reaching out with no leaves, a hollow, a fallen
-- branch and a stone at its foot.
M.deadtree = function(m, f)
	local p0, p1, p2, p3, p4 = Vector3.new(0, 0, 0), Vector3.new(0.15, 1.2, 0.1), Vector3.new(-0.1, 2.2, 0.05), Vector3.new(0.1, 3.0, -0.1), Vector3.new(0.35, 3.7, -0.05)
	for _, a in { 0.6, 2.4, 4.2 } do
		limb(m, f, Vector3.new(0, 0.4, 0), Vector3.new(math.sin(a) * 0.7, 0.05, math.cos(a) * 0.7), 0.35, "wood_dark", "Root")
	end
	-- (the crooked trunk one round line through its bends, narrowing as it rises, its foot a little in the ground)
	tube(m, f, { p0 - (p1 - p0) / 9, p1, p2, p3 }, { 0.75, 0.625, 0.5 }, "wood_dark", "Trunk", true)
	limb(m, f, p3, p4, 0.25, "wood_dark")
	box(m, f, 0.15, 0.95, 0.3, 0.25, 0.5, 0.25, "black", "Hollow")
	-- the branches, each bending up at a fork
	local function fork(a: Vector3, b: Vector3, c: Vector3, t: number)
		limb(m, f, a, b, t, "wood_dark")
		limb(m, f, b, c, 0.25, "wood_dark")
	end
	fork(p1 + Vector3.new(0, 0.3, 0), Vector3.new(0.95, 2.1, 0.45), Vector3.new(1.05, 2.85, 0.2), 0.35)
	limb(m, f, Vector3.new(0.95, 2.1, 0.45), Vector3.new(1.1, 2.25, 1.0), 0.25, "wood_dark")
	fork(p2, Vector3.new(-0.85, 2.75, -0.15), Vector3.new(-1.05, 3.4, 0.2), 0.35)
	limb(m, f, Vector3.new(-0.85, 2.75, -0.15), Vector3.new(-1.1, 2.85, -0.7), 0.25, "wood_dark")
	fork(p2 + Vector3.new(0, 0.3, 0), Vector3.new(0.35, 3.0, 0.85), Vector3.new(0.15, 3.55, 1.05), 0.3)
	limb(m, f, p3, Vector3.new(-0.5, 3.65, -0.5), 0.25, "wood_dark")
	limb(m, f, p3 + Vector3.new(0, 0.15, 0), Vector3.new(0.8, 3.5, -0.6), 0.25, "wood_dark")
	-- a fallen branch and a stone
	put(m, f, CFrame.new(0.5, 0.08, 0.8) * CFrame.Angles(0, 0.5, 0), 0.75, 0.25, 0.25, "wood_dark", nil, "Fallen")
	ball(m, f, -0.65, 0.12, 0.55, 0.5, "rock", "Stone")
end

-- Birch Tree (2 x 2): two slim white trunks with dark marks, one leaning out, small dark twigs, clumps of light
-- leaves climbing them with sky between, so the white shows.
M.birch = function(m, f)
	cyl(m, f, -0.2, 0.2, -0.2, 0.75, 0.4, "rock_dark", "Root")
	cyl(m, f, -0.2, 2.2, -0.2, 0.5, 4.4, "white", "Trunk")
	local lean0, lean1 = Vector3.new(0.15, 0.1, 0.05), Vector3.new(0.75, 3.0, -0.4)
	stem(m, f, lean0, lean1, 0.5, "white", "Trunk")
	for k, y in { 0.7, 1.4, 2.3, 3.1, 3.7 } do
		local side = k % 2 == 0
		box(m, f, -0.2 + (if side then 0.17 else 0.04), y, -0.2 + (if side then 0.04 else 0.17), 0.25, 0.25, 0.25, "black", "Mark")
	end
	for _, t in { 0.25, 0.5, 0.75 } do
		local p = lean0:Lerp(lean1, t)
		box(m, f, p.X + 0.12, p.Y, p.Z + 0.12, 0.25, 0.25, 0.25, "black", "Mark")
	end
	limb(m, f, Vector3.new(-0.2, 2.6, -0.2), Vector3.new(-0.75, 3.05, 0.15), 0.25, "black", "Twig")
	limb(m, f, Vector3.new(-0.2, 3.4, -0.2), Vector3.new(0.35, 3.75, -0.65), 0.25, "black", "Twig")
	local crown: { { any } } = {
		{ -0.8, 3.2, 0.25, 1.0, "green" },
		{ 0.15, 3.85, -0.8, 1.0, "leaf" },
		{ -0.75, 3.95, -0.35, 1.25, "green" },
		{ 0.25, 4.4, -0.35, 1.25, "leaf" },
		{ -0.35, 4.8, 0.0, 1.25, "green" },
		{ -0.2, 5.35, -0.25, 0.75, "leaf" },
		{ 0.85, 3.3, -0.35, 1.0, "green" },
		{ 1.0, 2.9, 0.1, 0.75, "leaf" },
		{ 0.45, 3.0, -0.75, 0.75, "green" },
	}
	for _, c in crown do
		sway(ball(m, f, c[1], c[2], c[3], c[4], c[5], "Leaves"))
	end
end

-- Cherry Blossom (3 x 3): a dark trunk that leans and splits into five limbs under a wide, low cloud of pink
-- blossom with white highlights; petals fallen on the grass.
M.cherry = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	local base, split = Vector3.new(0, 0, 0), Vector3.new(0.25, 1.6, 0.15)
	stem(m, f, base, split, 0.75, "wood_dark", "Trunk")
	local clouds = { Vector3.new(1.05, 2.95, 0.5), Vector3.new(-1.0, 3.15, -0.2), Vector3.new(0.3, 3.35, -0.95), Vector3.new(-0.4, 3.25, 0.9), Vector3.new(0.1, 3.75, 0) }
	for k, c in clouds do
		local bend = split + (c - split) * 0.55 + Vector3.new(0, 0.15, 0)
		limb(m, f, split, bend, if k == 5 then 0.4 else 0.35, "wood_dark")
		limb(m, f, bend, c - Vector3.new(0, 0.4, 0), 0.25, "wood_dark")
	end
	local light = Vector3.new(-0.2, 0.85, 0.5).Unit
	for k, c in clouds do
		local big = if k == 5 then 1.75 else 1.5
		sway(ball(m, f, c.X + 0.05, c.Y - 0.3, c.Z + 0.05, big * 0.85, "pink", "BlossomUnder"))
		sway(ball(m, f, c.X, c.Y, c.Z, big, "cherry", "Blossom"))
		local h = c + light * (big / 2 - 0.12)
		sway(ball(m, f, h.X, h.Y, h.Z, if k == 5 then 0.5 else 0.25, "white", "Blossom"))
	end
	for k, p in { { 1.1, 0.9 }, { -0.9, 1.0 }, { 1.3, -0.4 }, { -0.2, 1.3 }, { 0.6, 1.25 }, { -1.25, 0.3 } } do
		box(m, f, p[1], 0, p[2], 0.25, 0.25, 0.25, if k % 2 == 0 then "pink" else "cherry", "Petal")
	end
end

-- Maple Tree (3 x 3): a straight trunk under a tall, egg-shaped crown of red and orange, darker underneath; leaves
-- fallen round its foot.
M.maple = function(m, f)
	cyl(m, f, 0, 0.12, 0, 0.9, 0.25, "wood_dark", "Root")
	cyl(m, f, 0, 1.1, 0, 0.65, 2.2, "wood_dark", "Trunk")
	limb(m, f, Vector3.new(0, 1.8, 0), Vector3.new(0.75, 2.5, 0.4), 0.3, "wood_dark")
	limb(m, f, Vector3.new(0, 1.9, 0), Vector3.new(-0.7, 2.6, 0.25), 0.3, "wood_dark")
	local crown: { { any } } = {
		{ 0.6, 2.65, 0.45, 1.5, "brick" },
		{ -0.6, 2.7, 0.45, 1.5, "brick" },
		{ 0.5, 2.75, -0.55, 1.5, "brick" },
		{ -0.55, 2.8, -0.5, 1.5, "brick" },
		{ 0, 3.35, 0, 2.25, "maple" },
		{ 0.8, 3.25, 0.5, 1.5, "orange" },
		{ -0.75, 3.45, 0.6, 1.5, "maple" },
		{ 0.6, 3.65, -0.7, 1.5, "maple" },
		{ -0.7, 3.75, -0.5, 1.5, "orange" },
		{ 0, 4.25, 0, 1.75, "maple" },
		{ 0.35, 4.3, 0.45, 1.0, "orange" },
		{ 0.1, 4.85, 0.1, 1.25, "orange" },
		{ -0.45, 4.05, 0.55, 0.75, "yellow" },
	}
	for _, c in crown do
		sway(ball(m, f, c[1], c[2], c[3], c[4], c[5], "Leaves"))
	end
	for k, p in { { 1.1, 0.8 }, { -0.8, 1.1 }, { 1.25, -0.5 }, { -0.1, 1.35 }, { 0.55, 1.2 }, { -1.2, 0.2 }, { 0.9, 0.1 } } do
		box(m, f, p[1], 0, p[2], 0.25, 0.25, 0.25, if k % 3 == 0 then "yellow" elseif k % 3 == 1 then "orange" else "maple", "FallenLeaf")
	end
end

-- Jungle Tree (3 x 3): a tall pale trunk on flared buttress roots, a broad crown of huge drooping leaves with a few
-- shorter ones standing up in the middle, vines hanging from the leaves, two of them in flower.
M.jungletree = function(m, f)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.3
		local dx, dz = math.sin(a), math.cos(a)
		Parts.wedge(m, f, dx * 0.75, 0.75, dz * 0.75, 0.25, 1.5, 1.0, "wood_dark", math.atan2(-dx, -dz), "Buttress")
	end
	cyl(m, f, 0, 2.4, 0, 0.75, 4.8, "wood", "Trunk")
	cyl(m, f, 0, 2.0, 0, 0.8, 0.25, "wood_dark", "Ring")
	cyl(m, f, 0, 3.4, 0, 0.8, 0.25, "wood_dark", "Ring")
	box(m, f, 0.25, 2.6, 0.28, 0.25, 0.75, 0.25, "moss", "Moss")
	box(m, f, -0.28, 1.4, 0.25, 0.25, 0.5, 0.25, "moss", "Moss")
	local top = Vector3.new(0, 4.85, 0)
	ball(m, f, 0, 4.8, 0, 1.25, "leaf_dark", "Heart")
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + 0.2
		local dx, dz = math.sin(a), math.cos(a)
		local mid = top + Vector3.new(dx * 1.0, 0.05, dz * 1.0)
		blade(m, f, top + Vector3.new(dx * 0.3, 0, dz * 0.3), mid, 1.0, if k % 2 == 0 then "leaf" else "leaf_dark", "BigLeaf")
		blade(m, f, mid, top + Vector3.new(dx * 1.9, -0.6, dz * 1.9), 0.75, if k % 2 == 0 then "leaf" else "leaf_dark", "BigLeaf")
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + 0.7
		blade(m, f, top + Vector3.new(0, 0.2, 0), top + Vector3.new(math.sin(a) * 0.95, 0.85, math.cos(a) * 0.95), 0.75, "leaf", "BigLeaf")
	end
	-- vines from under the leaves, two in flower
	for k, v in { { 1.45, 0.45, 2.25 }, { 0.3, 1.45, 1.75 }, { -1.2, 0.85, 1.5 }, { 1.05, -1.0, 1.75 }, { -0.7, -1.2, 1.25 }, { 0.95, 1.05, 1.25 } } do
		local y = 4.35 - v[3] / 2
		sway(box(m, f, v[1], y, v[2], 0.25, v[3], 0.25, if k % 2 == 0 then "moss" else "leaf_dark", "Vine"))
		if k <= 2 then
			sway(box(m, f, v[1], y - v[3] / 2 + 0.1, v[2] + 0.05, 0.25, 0.25, 0.25, if k == 1 then "pink" else "orange", "Flower"))
		end
	end
end

-- Willow (4 x 4): a short thick trunk under a low, lumpy dome, and a curtain of long strands of different lengths
-- hanging from it nearly to the grass, an inner ring of shorter ones behind, gaps where the trunk shows.
M.willow = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.25, 0.25, "wood_dark", "Root")
	cyl(m, f, 0, 1.15, 0, 0.9, 2.3, "wood_dark", "Trunk")
	limb(m, f, Vector3.new(0, 2.0, 0), Vector3.new(0.9, 3.0, 0.5), 0.35, "wood_dark")
	limb(m, f, Vector3.new(0, 2.1, 0), Vector3.new(-0.8, 3.1, 0.4), 0.35, "wood_dark")
	limb(m, f, Vector3.new(0, 2.2, 0), Vector3.new(0.2, 3.2, -0.9), 0.35, "wood_dark")
	ball(m, f, 0, 3.55, 0, 2.75, "leaf", "Leaves")
	ball(m, f, 0.3, 4.35, -0.25, 1.75, "leaf", "Leaves")
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2 + 0.25
		ball(m, f, math.sin(a) * 1.05, if k % 2 == 0 then 3.15 else 3.4, math.cos(a) * 1.05, 1.75, if k % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
	end
	local lens = { 3.0, 2.25, 2.75, 2.0, 2.5 }
	for k = 0, 13 do
		local a = k / 14 * math.pi * 2 + 0.1
		local len = lens[k % 5 + 1]
		Parts.turned(m, f, math.sin(a) * 1.7, 3.4 - len / 2, math.cos(a) * 1.7, 0.5, len, 0.25, a, if k % 2 == 0 then "leaf" else "leaf_dark", "Strand")
	end
	for k = 0, 7 do
		local a = (k + 0.5) / 8 * math.pi * 2 + 0.1
		Parts.turned(m, f, math.sin(a) * 1.3, 2.5, math.cos(a) * 1.3, 0.5, 1.75, 0.25, a, "leaf_dark", "Strand")
	end
end

-- Great Oak (5 x 5): a huge gnarled trunk on wide roots, thick limbs reaching out to a broad crown of leaf clumps with
-- sky between them, a rope swing on a low limb, moss on the roots, a hollow, mushrooms at its foot.
M.bigoak = function(m, f)
	cyl(m, f, 0, 0, 0, 3.0, 0.25, "moss", "Moss")
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + 0.2
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
	for _, r in { { 0.73, 0.1 }, { 0.2, 0.71 }, { 0.6, 0.45 } } do
		box(m, f, r[1], 2.1, r[2], 0.25, 2.25, 0.25, "wood", "Bark")
	end
	box(m, f, -0.15, 1.8, 0.72, 0.75, 1.0, 0.25, "wood", "HollowRim")
	box(m, f, -0.15, 1.75, 0.78, 0.5, 0.75, 0.25, "black", "Hollow")
	-- the limbs out to the clumps of the crown: a ring of seven, three higher in, one on top
	local trunkTop = Vector3.new(0, 3.3, 0)
	local clumps: { Vector3 } = { Vector3.new(0, 6.4, 0) }
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + 0.45
		local r = if k % 2 == 0 then 2.1 else 1.85
		table.insert(clumps, Vector3.new(math.sin(a) * r, if k % 2 == 0 then 4.7 else 5.2, math.cos(a) * r))
	end
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + 1.2
		table.insert(clumps, Vector3.new(math.sin(a) * 1.0, 5.8, math.cos(a) * 1.0))
	end
	for k, c in clumps do
		if k <= 8 then
			local bend = Vector3.new(c.X * 0.5, trunkTop.Y + 0.35 + (c.Y - trunkTop.Y) * 0.25, c.Z * 0.5)
			limb(m, f, trunkTop, bend, if k == 1 then 0.75 else 0.6, if k % 2 == 0 then "wood" else "wood_dark")
			limb(m, f, bend, c - Vector3.new(0, 0.5, 0), 0.4, "wood_dark")
		end
	end
	for k, c in clumps do
		local big = if k == 1 then 2.5 elseif k <= 8 then 2.0 else 1.75
		clump(m, f, c.X, c.Y, c.Z, big, "leaf", "leaf_dark")
		if k <= 8 then
			ball(m, f, c.X + 0.2, c.Y + big * 0.32, c.Z - 0.1, big * 0.6, if k % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
		end
	end
	-- the rope swing on a low limb out to the left
	limb(m, f, Vector3.new(0.05, 3.1, 0.5), Vector3.new(0.2, 3.9, 2.3), 0.4, "wood_dark")
	box(m, f, 0.18, 2.3, 1.35, 0.25, 3.0, 0.25, "straw", "Rope")
	box(m, f, 0.2, 2.35, 2.05, 0.25, 3.0, 0.25, "straw", "Rope")
	box(m, f, 0.18, 0.75, 1.7, 0.5, 0.25, 1.0, "wood", "Seat")
	-- mushrooms among the roots
	shroom(m, f, 1.35, 0.95, 0.25, 0.5, "berry_red", false)
	shroom(m, f, -1.25, 1.1, 0.25, 0.5, "orange", false)
end

-- Snowy Pine (2 x 2): four broad green tiers bowed low, each wearing a cap of snow with a green fringe below it, a
-- drift at its foot.
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
		for _, p in cone(m, f, CFrame.new(0, ys, 0), ws, hs, "snow", "Snow") do
			sway(p)
		end
	end
	box(m, f, 0.75, 0.0, 0.7, 0.5, 0.25, 0.5, "snow", "Drift")
end

-- Fern (1 x 1): seven fronds rising out of a dark heart in tall arches and drooping at the tips.
M.fern = function(m, f)
	ball(m, f, 0, 0.15, 0, 0.5, "leaf_dark", "Heart")
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2 + 0.3
		local dx, dz = math.sin(a), math.cos(a)
		local reach = if k % 2 == 0 then 1 else 0.8
		local mid = Vector3.new(dx * 0.25 * reach, 0.8 * reach, dz * 0.25 * reach)
		blade(m, f, Vector3.new(dx * 0.05, 0.15, dz * 0.05), mid, 0.25, "leaf_dark", "Frond")
		blade(m, f, mid, Vector3.new(dx * 0.45 * reach, 0.5 * reach, dz * 0.45 * reach), 0.25, "leaf", "Frond")
	end
end

-- Tall Grass (2 x 2): four clumps of long thin blades fanning out over the patch, darker at the heart, seed heads on
-- the tallest.
M.tallgrass = function(m, f)
	local r = rand(7)
	local colors = { "leaf_dark", "leaf", "green", "leaf", "leaf_dark", "green" }
	for ci, c in { { -0.5, -0.45, 1.0 }, { 0.5, -0.35, 0.85 }, { -0.35, 0.5, 0.8 }, { 0.5, 0.55, 0.7 } } do
		for k = 1, 6 do
			local a = (k + r() * 0.6) / 6 * math.pi * 2
			local h = (0.8 + r() * 0.7) * c[3]
			local cf = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.2 + r() * 0.3, 0, 0)
			sway(put(m, f, cf * CFrame.new(0, h / 2, 0), 0.25, h, 0.25, colors[(k + ci) % 6 + 1], nil, "Blade"))
			if k == 2 and ci ~= 4 then
				sway(put(m, f, cf * CFrame.new(0, h + 0.2, 0), 0.25, 0.5, 0.25, "straw", nil, "Seed"))
			end
		end
	end
end

-- Berry Bush (2 x 2): a low, wide mound of dark leaves, red berries in twos and threes all over its front, a basket
-- of picked ones.
M.berrybush = function(m, f)
	local clumps: { { any } } = { { 0, 0.6, 0, 1.5, "leaf_dark" }, { 0.5, 0.5, 0.45, 1.0, "leaf_dark" }, { -0.45, 0.6, 0.4, 1.0, "leaf" }, { 0.45, 0.75, -0.4, 1.0, "leaf" }, { -0.45, 0.55, -0.45, 1.0, "leaf_dark" }, { 0, 1.0, 0.05, 1.0, "leaf" } }
	for _, c in clumps do
		ball(m, f, c[1], c[2], c[3], c[4], c[5], "Bush")
	end
	-- berries on the front of the clumps
	local spots = { { 1, 0.3, 0.5, 0.8 }, { 1, 0.7, 0.3, 0.45 }, { 2, 0.6, 0.2, 0.6 }, { 3, 0.1, 0.4, 0.8 }, { 3, 0.6, 0.1, 0.7 }, { 4, 0.8, 0.4, 0.2 }, { 6, 0.4, 0.6, 0.5 }, { 6, -0.2, 0.7, 0.6 }, { 5, 0.2, 0.3, 0.9 } }
	for i, s in spots do
		local c = clumps[s[1]]
		local dir = Vector3.new(s[2], s[3], s[4]).Unit
		local p = Vector3.new(c[1], c[2], c[3]) + dir * (c[4] / 2 - 0.05)
		ball(m, f, p.X, p.Y, p.Z, 0.25, if i % 4 == 0 then "brick" else "berry_red", "Berry")
	end
	box(m, f, 0.72, 0.15, 0.72, 0.5, 0.3, 0.5, "straw", "Basket")
	box(m, f, 0.72, 0.3, 0.72, 0.25, 0.25, 0.25, "berry_red", "Berry")
end

-- Tulip Row (2 x 1): a strip of dark soil, six tulips in red, yellow and pink on green stems in a row, each a cup with
-- two pointed petals, leaves at their feet.
M.tulips = function(m, f)
	box(m, f, 0, 0.02, 0, 1.9, 0.25, 0.75, "wood_dark", "Soil")
	local colors = { "berry_red", "yellow", "pink" }
	local across = Vector3.new(0.707, 0, -0.707)
	for k = 0, 5 do
		local x = -0.6 + k * 0.24
		local z = if k % 2 == 0 then -0.08 else 0.08
		local h = if k % 2 == 1 then 0.7 else 0.55
		local c = colors[k % 3 + 1]
		box(m, f, x, 0.15 + h / 2, z, 0.25, h, 0.25, "leaf", "Stem")
		sway(Parts.turned(m, f, x, 0.25 + h, z, 0.5, 0.25, 0.5, math.pi / 4, c, "Tulip"))
		for _, s in { -1, 1 } do
			local p = Vector3.new(x, 0.45 + h, z) + across * (s * 0.14)
			sway(box(m, f, p.X, p.Y, p.Z, 0.25, 0.25, 0.25, c, "Petal"))
		end
		if k % 2 == 0 then
			put(m, f, CFrame.new(x + 0.12, 0.3, z + 0.15) * CFrame.Angles(0.5, 0.3, 0), 0.25, 0.5, 0.25, "leaf_dark", nil, "Leaf")
		end
	end
end

-- Mushrooms (1 x 1): three toadstools of different sizes standing apart, two red with white spots, one brown, a blade
-- of grass between them.
M.mushrooms = function(m, f)
	shroom(m, f, -0.12, -0.12, 0.6, 0.75, "berry_red", true)
	shroom(m, f, 0.25, -0.2, 0.4, 0.5, "berry_red", false)
	box(m, f, 0.31, 0.62, -0.13, 0.25, 0.25, 0.25, "white", "Spot")
	shroom(m, f, -0.22, 0.25, 0.25, 0.5, "wood", false)
	put(m, f, CFrame.new(0.25, 0.2, 0.3) * CFrame.Angles(0.25, 0.9, 0), 0.25, 0.5, 0.25, "leaf", nil, "Blade")
	put(m, f, CFrame.new(0.05, 0.15, 0.4) * CFrame.Angles(-0.3, 0.3, 0.2), 0.25, 0.25, 0.25, "leaf_dark", nil, "Blade")
end

-- Rose Bush (2 x 2): an upright bush of dark leaves, round red roses with deeper hearts on its front, a bud or two.
M.rosebush = function(m, f)
	local clumps: { { any } } = { { 0, 0.7, 0, 1.25, "leaf_dark" }, { 0.4, 0.6, 0.4, 1.0, "leaf_dark" }, { -0.4, 0.85, 0.25, 1.0, "leaf" }, { 0.3, 1.1, -0.25, 1.0, "leaf" }, { -0.35, 0.55, -0.4, 1.0, "leaf_dark" }, { 0, 1.4, 0, 0.75, "leaf_dark" } }
	for _, c in clumps do
		ball(m, f, c[1], c[2], c[3], c[4], c[5], "Bush")
	end
	for _, r in { { 2, 0.4, 0.4, 0.8 }, { 3, -0.3, 0.6, 0.7 }, { 4, 0.6, 0.5, 0.2 }, { 1, 0.1, 0.1, 1.0 }, { 6, 0.3, 0.9, 0.4 } } do
		local c = clumps[r[1]]
		local p = Vector3.new(c[1], c[2], c[3]) + Vector3.new(r[2], r[3], r[4]).Unit * (c[4] / 2)
		ball(m, f, p.X, p.Y, p.Z, 0.5, "berry_red", "Rose")
		box(m, f, p.X + 0.05, p.Y + 0.15, p.Z + 0.05, 0.25, 0.25, 0.25, "brick", "RoseHeart")
	end
	box(m, f, -0.1, 1.85, 0.1, 0.25, 0.25, 0.25, "berry_red", "Bud")
	box(m, f, 0.75, 1.25, -0.3, 0.25, 0.25, 0.25, "berry_red", "Bud")
end

-- Sunflowers (2 x 2): three tall stalks with leaves, big yellow heads with brown middles turned up to the sun.
M.sunflowers = function(m, f)
	local face = Vector3.new(0.3, 0.9, 1).Unit
	for k, s in { { -0.45, -0.45, 2.25 }, { 0.65, -0.25, 1.85 }, { -0.25, 0.65, 1.5 } } do
		local x, z, h = s[1], s[2], s[3]
		sway(cyl(m, f, x, h / 2, z, 0.25, h, "leaf_dark", "Stalk"))
		blade(m, f, Vector3.new(x, h * 0.45, z), Vector3.new(x + 0.35, h * 0.38, z - 0.15), 0.5, "leaf", "Leaf")
		blade(m, f, Vector3.new(x, h * 0.65, z), Vector3.new(x - 0.2, h * 0.6, z + 0.35), 0.5, "leaf_dark", "Leaf")
		local head = Vector3.new(x, h, z)
		local cf = CFrame.lookAt(head, head + face) * CFrame.Angles(0, math.pi / 2, 0)
		sway(put(m, f, cf, 0.25, if k == 1 then 1.0 else 0.75, if k == 1 then 1.0 else 0.75, "yellow", "Cylinder", "Petals"))
		sway(put(m, f, cf * CFrame.new(0.1, 0, 0), 0.25, 0.5, 0.5, "wood_dark", "Cylinder", "Seeds"))
	end
	blade(m, f, Vector3.new(0.1, 0.15, 0.1), Vector3.new(0.7, 0.05, 0.6), 0.5, "leaf_dark", "Leaf")
end

-- Lavender (2 x 1): three soft grey-green mounds, each with a few green stems leaning out, topped with purple spikes,
-- paler at the tips.
M.lavender = function(m, f)
	for k, x in { -0.55, 0, 0.55 } do
		local z = if k == 2 then -0.05 else 0.05
		ball(m, f, x, 0.12, z, 0.5, "moss", "Mound")
		for j = 0, 2 do
			local a = j / 3 * math.pi * 2 + k * 0.9
			local cf = CFrame.new(x + math.sin(a) * 0.12, 0.15, z + math.cos(a) * 0.12) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.3, 0, 0)
			sway(put(m, f, cf * CFrame.new(0, 0.25, 0), 0.25, 0.5, 0.25, "moss", nil, "LavenderStem"))
			sway(put(m, f, cf * CFrame.new(0, 0.7, 0), 0.25, 0.5, 0.25, "purple", nil, "Spike"))
			if j ~= 1 then
				sway(put(m, f, cf * CFrame.new(0, 1.0, 0), 0.25, 0.25, 0.25, "crystal", nil, "SpikeTip"))
			end
		end
	end
end

-- Pumpkin Patch (2 x 2): three fat ribbed pumpkins of three sizes with stalks, big leaves and a vine between them.
M.pumpkins = function(m, f)
	local across = CFrame.Angles(0, math.pi / 4, 0) -- the lobes spread across the view
	local function pumpkin(x: number, z: number, s: number)
		local c = CFrame.new(x, 0.36 * s, z) * across
		put(m, f, c * CFrame.new(0.24 * s, -0.04, 0), 0.5 * s, 0.5 * s, 0.5 * s, "maple", "Ball", "Pumpkin")
		put(m, f, c * CFrame.new(-0.24 * s, -0.04, 0), 0.5 * s, 0.5 * s, 0.5 * s, "maple", "Ball", "Pumpkin")
		put(m, f, c, 0.75 * s, 0.75 * s, 0.75 * s, "orange", "Ball", "Pumpkin")
		put(m, f, c * CFrame.new(0.05, 0.4 * s, 0) * CFrame.Angles(0, 0, 0.3), 0.25, 0.25, 0.25, "leaf_dark", nil, "PumpkinStalk")
	end
	for k, l in { { 0.5, 0.65, 0.4 }, { -0.8, 0.15, 1.6 }, { -0.1, -0.2, 2.6 }, { 0.75, -0.75, 3.5 }, { -0.35, -0.75, 5.0 } } do
		put(m, f, CFrame.new(l[1], 0.05, l[2]) * CFrame.Angles(0, l[3], 0.1), 0.75, 0.25, 0.5, if k % 2 == 0 then "leaf" else "leaf_dark", nil, "Leaf")
	end
	limb(m, f, Vector3.new(-0.3, 0.08, -0.35), Vector3.new(0.45, 0.08, -0.5), 0.25, "leaf_dark", "Vine")
	limb(m, f, Vector3.new(-0.3, 0.08, -0.35), Vector3.new(-0.6, 0.08, 0.45), 0.25, "leaf_dark", "Vine")
	pumpkin(0.2, 0.25, 1.33)
	pumpkin(0.55, -0.55, 1.0)
	pumpkin(-0.6, 0.45, 0.67)
end

-- Cactus (1 x 1): a round barrel cactus with ribs and a few pale spines, one pink flower on top, a pup at its side,
-- on a patch of sand.
M.cactus = function(m, f)
	box(m, f, 0, 0.02, 0, 0.9, 0.25, 0.9, "sand", "Sand")
	cyl(m, f, 0, 0.5, 0, 0.75, 1.0, "green", "Cactus")
	ball(m, f, 0, 1.0, 0, 0.75, "green", "Cactus")
	for _, a in { 0.3, math.pi / 4 + 0.05, 1.25 } do
		put(m, f, CFrame.new(math.sin(a) * 0.3, 0.7, math.cos(a) * 0.3) * CFrame.Angles(0, a, 0), 0.25, 1.0, 0.25, "moss", nil, "Rib")
	end
	for _, s in { { 0.2, 1.05, 0.3 }, { 0.38, 0.55, 0.05 }, { 0.05, 0.35, 0.4 } } do
		box(m, f, s[1], s[2], s[3], 0.25, 0.25, 0.25, "cream", "Spine")
	end
	box(m, f, 0, 1.4, 0, 0.5, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0, 1.4, 0, 0.25, 0.25, 0.5, "pink", "Flower")
	box(m, f, 0, 1.5, 0, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	ball(m, f, 0.25, 0.2, -0.25, 0.5, "green", "Pup")
	ball(m, f, -0.3, 0.1, 0.35, 0.25, "rock", "Pebble")
end

-- Big Leaf Plant (2 x 2): five huge leaves held up on long stalks and bowing out, each split into three fingers.
M.monstera = function(m, f)
	ball(m, f, 0, 0.15, 0, 0.75, "leaf_dark", "Heart")
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.6
		local dx, dz = math.sin(a), math.cos(a)
		local hgt = if k % 2 == 0 then 1.6 else 1.25
		local tip = Vector3.new(dx * 0.35, hgt, dz * 0.35)
		stem(m, f, Vector3.new(0, 0.15, 0), tip, 0.25, "leaf_dark", "Stalk")
		for j = -1, 1 do
			local b = a + j * 0.35
			blade(m, f, tip, Vector3.new(dx * 0.35 + math.sin(b) * 0.75, hgt - 0.5 - math.abs(j) * 0.1, dz * 0.35 + math.cos(b) * 0.75), 0.5, if j == 0 then "leaf_dark" else "leaf", "Leaf")
		end
	end
end

-- Tall Cactus (2 x 2): a tall ribbed column with two arms raised either side, a pink flower on top, rocks and sand at
-- its foot.
M.bigcactus = function(m, f)
	box(m, f, 0, 0.02, 0, 1.75, 0.25, 1.75, "sand", "Sand")
	cyl(m, f, 0, 1.4, 0, 0.75, 2.8, "green", "Cactus")
	ball(m, f, 0, 2.8, 0, 0.75, "green", "Cactus")
	for _, a in { math.pi / 4, math.pi / 4 + 0.6, math.pi / 4 - 0.6 } do
		put(m, f, CFrame.new(math.sin(a) * 0.3, 1.5, math.cos(a) * 0.3) * CFrame.Angles(0, a, 0), 0.25, 2.5, 0.25, "moss", nil, "Rib")
	end
	-- the arms: out across the view, then up
	local across = Vector3.new(1, 0, -1).Unit
	for k, s in { { 1, 1.2, 0.9 }, { -1, 1.6, 0.75 } } do
		local out = across * s[1]
		local elbow = out * 0.65 + Vector3.new(0, s[2], 0)
		stem(m, f, Vector3.new(0, s[2], 0), elbow, 0.5, "green", "Arm")
		stem(m, f, elbow, elbow + Vector3.new(0, s[3], 0), 0.5, "green", "Arm")
		ball(m, f, elbow.X, elbow.Y + s[3], elbow.Z, 0.5, "green", "Arm")
		if k == 1 then
			box(m, f, elbow.X, elbow.Y + s[3] + 0.25, elbow.Z, 0.25, 0.25, 0.25, "pink", "Flower")
		end
	end
	box(m, f, 0, 3.2, 0, 0.5, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0, 3.2, 0, 0.25, 0.25, 0.5, "pink", "Flower")
	box(m, f, 0, 3.28, 0, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	box(m, f, 0.3, 2.2, 0.25, 0.25, 0.25, 0.25, "cream", "Spine")
	box(m, f, 0.05, 1.0, 0.4, 0.25, 0.25, 0.25, "cream", "Spine")
	put(m, f, CFrame.new(0.65, 0.15, -0.55) * CFrame.Angles(0, 0.4, 0.1), 0.5, 0.5, 0.5, "clay", nil, "Rock")
	put(m, f, CFrame.new(-0.65, 0.1, 0.55) * CFrame.Angles(0, -0.3, 0), 0.5, 0.25, 0.25, "sand_dark", nil, "Rock")
end

-- Giant Mushroom (2 x 2): a thick pale stalk with a skirt, a broad red cap with a domed top and white spots, gills
-- under its rim, two small ones at its foot.
M.giantshroom = function(m, f)
	ball(m, f, 0, 0.3, 0, 1.0, "cream", "Bulb")
	cyl(m, f, 0, 0.9, 0, 0.75, 1.5, "cream", "Stalk")
	cyl(m, f, 0, 1.2, 0, 1.0, 0.25, "white", "Skirt")
	cyl(m, f, 0, 1.62, 0, 2.0, 0.25, "sand_dark", "Gills")
	cyl(m, f, 0, 1.85, 0, 2.25, 0.5, "berry_red", "Cap")
	cyl(m, f, 0, 2.2, 0, 1.75, 0.25, "berry_red", "Cap")
	ball(m, f, 0, 2.3, 0, 1.5, "berry_red", "Cap")
	for _, s in { { 0.85, 2.0, 0.45, 0.5 }, { 0.2, 2.15, 0.85, 0.5 }, { 0.5, 2.6, 0.2, 0.5 }, { -0.4, 2.65, 0.35, 0.25 }, { 0.75, 2.05, -0.5, 0.25 }, { -0.75, 2.05, 0.8, 0.25 } } do
		box(m, f, s[1], s[2], s[3], s[4], 0.25, s[4], "white", "Spot")
	end
	shroom(m, f, 0.7, 0.75, 0.25, 0.5, "berry_red", false)
	shroom(m, f, -0.75, 0.5, 0.25, 0.25, "berry_red", false)
end

-- Bonsai (1 x 1): a shallow clay tray on little feet, moss and a stone in it, a twisted trunk holding three flat pads
-- of leaves in tiers, one each side and one on top.
M.bonsai = function(m, f)
	box(m, f, -0.25, 0.06, 0, 0.25, 0.25, 0.5, "wood_dark", "Foot")
	box(m, f, 0.25, 0.06, 0, 0.25, 0.25, 0.5, "wood_dark", "Foot")
	box(m, f, 0, 0.25, 0, 0.9, 0.25, 0.75, "clay", "Tray")
	box(m, f, 0, 0.35, 0, 0.75, 0.25, 0.5, "wood_dark", "Soil")
	box(m, f, 0.2, 0.43, 0.12, 0.5, 0.25, 0.25, "moss", "Moss")
	ball(m, f, -0.28, 0.5, 0.15, 0.25, "rock", "Stone")
	local a, b, c, d = Vector3.new(0, 0.4, 0), Vector3.new(0.2, 0.7, -0.1), Vector3.new(-0.1, 1.0, 0.05), Vector3.new(0.05, 1.25, 0)
	tube(m, f, { a, b, c, d }, { 0.25, 0.25, 0.25 }, "wood_dark", "Trunk", true)
	limb(m, f, b, Vector3.new(-0.2, 0.85, 0.25), 0.25, "wood_dark")
	limb(m, f, c, Vector3.new(0.22, 1.05, -0.24), 0.25, "wood_dark")
	cyl(m, f, -0.22, 0.95, 0.27, 0.5, 0.25, "leaf_dark", "Pad")
	cyl(m, f, 0.24, 1.15, -0.26, 0.5, 0.25, "leaf", "Pad")
	cyl(m, f, 0.05, 1.38, 0, 0.75, 0.25, "leaf", "Pad")
end

-- Glow Mushrooms (1 x 1): a clump of pale stalks with glowing blue caps on a bed of dark moss, specks of light in it.
M.glowshroom = function(m, f)
	cyl(m, f, 0, 0, 0, 1.0, 0.25, "swamp", "Moss")
	for _, s in { { -0.12, -0.12, 0.75, 0.75 }, { 0.25, -0.2, 0.5, 0.5 }, { -0.25, 0.22, 0.4, 0.5 }, { 0.2, 0.28, 0.25, 0.25 } } do
		local x, z, h, d = s[1], s[2], s[3], s[4]
		cyl(m, f, x, h / 2, z, 0.25, h, "ice", "Stalk")
		cyl(m, f, x, h + 0.05, z, d, 0.25, "blue", "CapRim")
		cyl(m, f, x, h + 0.2, z, math.max(0.25, d - 0.25), 0.25, "screen_on", "Cap", true)
	end
	Parts.glow(m, f, 0.4, 0.05, 0.05, 0.25, 0.25, 0.25, "screen_on", "Speck")
	Parts.glow(m, f, -0.4, 0.05, -0.35, 0.25, 0.25, 0.25, "screen_on", "Speck")
end

-- Boulder (2 x 2): one big round rock sunk a little in the grass, pebbles and a tuft beside it.
M.boulder = function(m, f)
	ball(m, f, 0, 0.62, 0, 1.75, "rock", "Boulder")
	ball(m, f, -0.25, 0.75, -0.3, 1.25, "rock", "Boulder")
	cyl(m, f, 0, 0.05, 0, 1.75, 0.25, "rock_dark", "Base")
	ball(m, f, 0.9, 0.1, -0.45, 0.25, "rock_dark", "Pebble")
	ball(m, f, -0.5, 0.1, 0.9, 0.25, "rock", "Pebble")
	put(m, f, CFrame.new(-0.75, 0.2, 0.55) * CFrame.Angles(0.3, 0.6, 0), 0.25, 0.5, 0.25, "leaf", nil, "Blade")
	put(m, f, CFrame.new(-0.6, 0.15, 0.7) * CFrame.Angles(-0.3, 0.2, 0.2), 0.25, 0.5, 0.25, "leaf_dark", nil, "Blade")
end

-- Rock Pile (2 x 2): a heap of round stones in three greys, big ones at the bottom, smaller on top.
M.rockpile = function(m, f)
	local stones: { { any } } = {
		{ -0.45, 0.3, -0.4, 0.75, "rock" },
		{ 0.4, 0.3, -0.4, 0.75, "rock_dark" },
		{ -0.45, 0.25, 0.35, 0.75, "rock_dark" },
		{ 0.45, 0.22, 0.4, 0.5, "pavement" },
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
	ball(m, f, 0.85, 0.1, -0.7, 0.25, "rock", "Pebble")
	ball(m, f, -0.8, 0.1, 0.8, 0.25, "rock_dark", "Pebble")
end

-- Mossy Rock (2 x 2): a big rough rock, half block and half round, a thick coat of moss over its top and down its
-- shady side, a small stone and a fern beside it.
M.mossrock = function(m, f)
	local a = CFrame.new(0.05, 0.4, 0.05) * CFrame.Angles(0.05, 0.3, -0.05)
	put(m, f, a, 1.5, 0.9, 1.25, "rock", nil, "Rock")
	put(m, f, a * CFrame.new(0, 0.5, 0), 1.25, 0.25, 1.0, "moss", nil, "Moss")
	put(m, f, a * CFrame.new(0.68, 0.15, -0.1), 0.25, 0.75, 0.75, "moss", nil, "Moss")
	ball(m, f, -0.35, 0.8, -0.35, 1.25, "rock_dark", "Rock")
	ball(m, f, -0.35, 1.0, -0.35, 1.0, "moss", "Moss")
	put(m, f, CFrame.new(0.65, 0.15, 0.7) * CFrame.Angles(0, 0.7, 0.1), 0.5, 0.25, 0.5, "rock_dark", nil, "Rock")
	for k = 0, 3 do
		local ang = k / 4 * math.pi * 2 + 0.4
		blade(m, f, Vector3.new(-0.7, 0.1, 0.7), Vector3.new(-0.7 + math.sin(ang) * 0.3, 0.4, 0.7 + math.cos(ang) * 0.3), 0.25, "leaf", "Frond")
	end
end

-- Desert Rock (2 x 2): a small arch of red rock worn through by the wind, banded in three reds, a loose rock by it.
M.sandrock = function(m, f)
	local a = CFrame.new(-0.1, 0, -0.1) * CFrame.Angles(0, math.pi / 4, 0) -- the arch spans across the view
	for _, s in { -1, 1 } do
		put(m, f, a * CFrame.new(s * 0.62, 0.12, 0), 0.75, 0.25, 1.0, "brick", nil, "Rock")
		put(m, f, a * CFrame.new(s * 0.6, 0.5, 0), 0.5, 0.75, 0.75, "clay", nil, "Rock")
		put(m, f, a * CFrame.new(s * 0.55, 1.0, 0.02), 0.5, 0.25, 0.75, "sand_dark", nil, "Rock")
	end
	put(m, f, a * CFrame.new(0, 1.3, 0), 1.75, 0.5, 0.75, "clay", nil, "Rock")
	put(m, f, a * CFrame.new(0.05, 1.62, -0.02), 1.5, 0.25, 0.75, "brick", nil, "Rock")
	put(m, f, a * CFrame.new(-0.1, 1.82, 0), 1.0, 0.25, 0.5, "clay", nil, "Rock")
	put(m, f, CFrame.new(0.65, 0.2, -0.45) * CFrame.Angles(0, -0.3, 0.1), 0.5, 0.5, 0.5, "clay", nil, "Rock")
	box(m, f, -0.45, 0.05, 0.8, 0.25, 0.25, 0.25, "brick", "Pebble")
end

-- Crystal Cluster (2 x 2): six purple crystals of different heights leaning out of a dark rock, faceted in two
-- shades, and small glowing shards at their feet.
local function crystal(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, color: string, neon: boolean?)
	put(m, f, cf * CFrame.new(0, h / 2, 0), w, h, w, color, nil, "Crystal", neon)
	cone(m, f, cf * CFrame.new(0, h, 0), w, w, color, "CrystalTip", neon)
end
M.crystals = function(m, f)
	ball(m, f, 0, 0.1, 0, 1.5, "rock_dark", "Rock")
	local list: { { any } } = {
		{ 0, 0, 0, 0, 0, 0.75, 1.5, "crystal" },
		{ -0.4, 0.1, 0.1, 0.35, 0.2, 0.5, 1.0, "purple" },
		{ 0.35, 0.1, -0.1, -0.15, -0.35, 0.5, 1.25, "crystal" },
		{ 0.15, 0.1, 0.4, 0.4, 0.15, 0.5, 0.75, "purple" },
		{ -0.3, 0.1, -0.35, -0.3, 0.3, 0.5, 0.75, "crystal" },
		{ 0.5, 0.05, 0.4, 0.3, -0.45, 0.5, 0.5, "purple" },
	}
	for _, c in list do
		local cf = CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(c[4], math.pi / 4, c[5])
		crystal(m, f, cf, c[6], c[7], c[8])
	end
	for _, s in { { 0.6, -0.35, 0.4 }, { -0.55, 0.55, -0.5 }, { 0.15, 0.75, 0.3 } } do
		put(m, f, CFrame.new(s[1], 0.2, s[2]) * CFrame.Angles(s[3], math.pi / 4, 0), 0.25, 0.5, 0.25, "crystal", nil, "Shard", true)
	end
end

-- Snowy Rock (2 x 2): a blue-grey rock with a smaller one on top, each under a thick cap of snow drooping over the
-- front edges, icicles, snow on the grass.
M.snowrock = function(m, f)
	local a = CFrame.new(-0.05, 0.4, -0.05) * CFrame.Angles(0, 0.25, 0.04)
	put(m, f, a, 1.5, 0.9, 1.25, "slate", nil, "Rock")
	put(m, f, a * CFrame.new(0, 0.55, 0), 1.5, 0.25, 1.25, "snow", nil, "Snow")
	put(m, f, a * CFrame.new(0.6, 0.38, 0.2), 0.5, 0.25, 0.75, "snow", nil, "Snow")
	put(m, f, a * CFrame.new(-0.2, 0.35, 0.55), 0.75, 0.25, 0.25, "snow", nil, "Snow")
	put(m, f, a * CFrame.new(0.5, 0.15, 0.6), 0.25, 0.25, 0.25, "ice", nil, "Icicle")
	put(m, f, a * CFrame.new(0.76, 0.15, -0.2), 0.25, 0.25, 0.25, "ice", nil, "Icicle")
	local b = CFrame.new(-0.3, 1.05, -0.3) * CFrame.Angles(0.05, -0.4, 0)
	put(m, f, b, 0.75, 0.5, 0.75, "rock_dark", nil, "Rock")
	put(m, f, b * CFrame.new(0, 0.35, 0), 0.75, 0.25, 0.75, "snow", nil, "Snow")
	ball(m, f, -0.3, 1.5, -0.3, 0.5, "snow", "Snow")
	box(m, f, 0.65, 0.0, 0.7, 0.75, 0.25, 0.5, "snow", "Drift")
	box(m, f, -0.7, 0.0, 0.6, 0.5, 0.25, 0.5, "snow", "Drift")
end

-- Basalt Columns (2 x 2): seven six-sided pillars of black rock packed together, tallest at the back, their worn tops
-- paler, a broken piece at the front.
local function column(m: Instance, f: CFrame, x: number, z: number, h: number, color: string)
	for k = 0, 2 do
		Parts.turned(m, f, x, h / 2, z, 0.5, h, 0.75, k * math.pi / 3, color, "Column")
	end
	cyl(m, f, x, h + 0.02, z, 0.75, 0.25, "steel_dark", "ColumnTop")
end
M.basaltcols = function(m, f)
	local s = 0.68
	column(m, f, 0, 0, 1.75, "basalt")
	for k, c in { { -0.866, -0.5, 1.5 }, { 0, -1, 2.25 }, { 0.866, -0.5, 1.25 }, { -0.866, 0.5, 1.0 }, { 0, 1, 0.5 }, { 0.866, 0.5, 0.75 } } do
		column(m, f, c[1] * s, c[2] * s, c[3], if k % 2 == 0 then "slate" else "basalt")
	end
	put(m, f, CFrame.new(0.75, 0.12, 0.8) * CFrame.Angles(0, 0.4, 0), 0.5, 0.25, 0.25, "basalt", nil, "Shard")
end

-- Lava Rock (2 x 2): a black rock, glowing cracks across its front, a pool of lava on top, embers on the grass.
M.lavarock = function(m, f)
	local a = CFrame.new(-0.1, 0.45, -0.1) * CFrame.Angles(0.06, 0.35, -0.05)
	put(m, f, a, 1.5, 1.0, 1.25, "basalt", nil, "Rock")
	local b = CFrame.new(0.5, 0.25, 0.5) * CFrame.Angles(-0.1, -0.4, 0.1)
	put(m, f, b, 0.75, 0.5, 0.75, "basalt", nil, "Rock")
	local c = CFrame.new(-0.3, 1.05, -0.3) * CFrame.Angles(0.08, 1.0, 0.05)
	put(m, f, c, 0.75, 0.5, 0.75, "basalt", nil, "Rock")
	-- cracks on a's front (+Z) and right (+X) faces, and on b's front
	put(m, f, a * CFrame.new(-0.2, 0.05, 0.55) * CFrame.Angles(0, 0, 0.5), 0.75, 0.25, 0.25, "lava", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.25, -0.2, 0.55), 0.25, 0.5, 0.25, "lava", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.68, 0.05, -0.2) * CFrame.Angles(0.6, 0, 0), 0.25, 0.25, 0.75, "lava", nil, "Crack", true)
	put(m, f, b * CFrame.new(0.05, 0.05, 0.3), 0.25, 0.25, 0.25, "orange", nil, "Crack", true)
	put(m, f, a * CFrame.new(0.25, 0.42, 0.2), 0.5, 0.25, 0.5, "lava", nil, "Pool", true)
	put(m, f, a * CFrame.new(0.25, 0.45, 0.2), 0.25, 0.25, 0.25, "yellow", nil, "Pool", true)
	Parts.glow(m, f, 0.85, 0.02, -0.4, 0.25, 0.25, 0.25, "orange", "Ember")
	Parts.glow(m, f, -0.75, 0.02, 0.7, 0.25, 0.25, 0.25, "lava", "Ember")
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor")

-- Starfruit Tree (3 x 3): a smooth leaning trunk under three round clumps of leaves, gold star-shaped fruit hanging
-- under them (a cross of two small bars), a few fallen on the grass.
M.starfruit = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "wood_dark", "Root")
	tube(m, f, { Vector3.new(0, 0, 0), Vector3.new(0.1, 0.9, 0), Vector3.new(-0.15, 1.8, -0.1), Vector3.new(0, 2.4, 0) }, { 0.5, 0.5, 0.375 }, "wood", "Trunk")
	for k, c in { { 0, 2.9, 0, 1.75 }, { -0.7, 2.5, 0.3, 1.25 }, { 0.75, 2.6, -0.35, 1.25 } } do
		for _, p in clump(m, f, c[1], c[2], c[3], c[4], if k == 1 then "leaf" else "green", "leaf_dark") do
			sway(p)
		end
	end
	for k, s in { { -0.6, 1.9, 0.7 }, { 0.5, 2.0, 0.55 }, { 0.9, 2.05, -0.2 }, { -0.95, 1.95, -0.2 }, { 0.1, 2.15, 0.85 } } do
		box(m, f, s[1], s[2], s[3], 0.25, 0.5, 0.25, "gold", "Fruit", true)
		box(m, f, s[1], s[2], s[3], 0.5, 0.25, 0.25, "yellow", "Fruit", true)
	end
	box(m, f, 0.9, 0.05, 0.95, 0.5, 0.25, 0.25, "gold", "Fallen")
	box(m, f, -1.0, 0.05, 0.6, 0.25, 0.25, 0.5, "yellow", "Fallen")
end

-- Redwood (4 x 4): a very tall straight red trunk, its roots flaring at the foot, short dark branches all the way up
-- and a narrow crown of dark green cones at the top, ferns round its foot.
M.redwood = function(m, f)
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.6
		limb(m, f, Vector3.new(math.sin(a) * 0.45, 0.45, math.cos(a) * 0.45), Vector3.new(math.sin(a) * 1.2, 0.1, math.cos(a) * 1.2), 0.5, "brick", "Root")
	end
	tube(m, f, { Vector3.new(0, 0, 0), Vector3.new(0, 2.5, 0), Vector3.new(0, 5.0, 0), Vector3.new(0, 7.5, 0) }, { 1.25, 1.0, 0.75 }, "brick", "Trunk")
	for k = 0, 5 do
		local a = k * 2.4
		local y = 3.0 + k * 0.7
		limb(m, f, Vector3.new(0, y, 0), Vector3.new(math.sin(a) * 1.1, y + 0.3, math.cos(a) * 1.1), 0.25, "wood_dark", "Branch")
		sway(ball(m, f, math.sin(a) * 1.2, y + 0.35, math.cos(a) * 1.2, 0.75, if k % 2 == 0 then "leaf_dark" else "swamp", "Needles"))
	end
	for _, t in { { 2.5, 6.0, 1.5 }, { 2.0, 7.0, 1.5 }, { 1.5, 8.0, 1.25 }, { 1.0, 8.9, 1.0 } } do
		for _, p in cone(m, f, CFrame.new(0, t[2], 0), t[1], t[3], "leaf_dark", "Needles") do
			sway(p)
		end
	end
	for _, c in { { 1.3, 1.2 }, { -1.4, 0.9 }, { 0.9, -1.4 } } do
		sway(blade(m, f, Vector3.new(c[1], 0.15, c[2]), Vector3.new(c[1] * 1.3, 0.45, c[2] * 1.3), 0.5, "leaf", "Fern"))
	end
end

-- Glass Flowers (1 x 1): three tall stems with clear petals that catch the light, a glowing heart in each.
M.glassflowers = function(m, f)
	box(m, f, 0, 0.05, 0, 0.75, 0.25, 0.75, "leaf_dark", "Leaves")
	for k, c in ({ { -0.2, 0.9, -0.1, "ice" }, { 0.2, 0.7, 0.1, "crystal" }, { 0.0, 1.1, 0.25, "ice" } } :: { { any } }) do
		stem(m, f, Vector3.new(c[1] * 0.4, 0.1, c[3] * 0.4), Vector3.new(c[1], c[2], c[3]), 0.25, "leaf", "Stem")
		for j = 0, 3 do
			local a = j * math.pi / 2 + k
			put(m, f, CFrame.new(c[1] + math.sin(a) * 0.15, c[2] + 0.05, c[3] + math.cos(a) * 0.15) * CFrame.Angles(0, a, 0.5), 0.25, 0.25, 0.25, c[4], nil, "Petal")
		end
		box(m, f, c[1], c[2] + 0.12, c[3], 0.25, 0.25, 0.25, "white", "Heart", true)
	end
end

-- Geode (2 x 2): a plain grey rock split down the middle, the two halves leaning apart, the inside lined with purple
-- crystal points, a glow in the hollow.
M.geode = function(m, f)
	for _, s in { -1, 1 } do
		local a = CFrame.new(s * 0.4, 0.55, 0) * CFrame.Angles(0, 0, s * 0.25)
		put(m, f, a, 0.5, 1.0, 1.25, "rock", nil, "Shell")
		put(m, f, a * CFrame.new(s * 0.25, 0, 0), 0.25, 0.75, 1.0, "rock_dark", nil, "Shell")
		for k = 0, 2 do
			crystal(m, f, a * CFrame.new(-s * 0.3, -0.3 + k * 0.3, -0.3 + k * 0.25) * CFrame.Angles(0, math.pi / 4, -s * 1.2), 0.25, 0.25 + (k % 2) * 0.25, if k % 2 == 0 then "purple" else "crystal")
		end
	end
	put(m, f, CFrame.new(0, 0.2, 0), 0.5, 0.25, 0.75, "crystal", nil, "Glow", true)
	box(m, f, 0.7, 0.05, 0.75, 0.25, 0.25, 0.25, "purple", "Chip")
end

return M
