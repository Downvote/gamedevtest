--!strict
-- Body plans built with the kit (Models/DriftKit; Models/DriftModels uses them over its old ones): the pebble
-- creature and the rabbit. Each returns its Thing; a plan faces +Z with its feet on the ground at y 0.
local Kit = require(script.Parent.DriftKit)

local V = Vector3.new
local R = math.rad
local J, P = Kit.J, Kit.P
local full = Kit.full

local PLANS: { [string]: (b: string, a: string) -> Kit.Thing } = {}

local UP = V(0, 1, 0)
local FWD = V(0, 0, 1)

-- A direction from forward: turned `yaw` degrees to the creature's left (-) or right (+) and `pitch` up (+) or down.
local function dir(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(-pitch), 0, 0)):VectorToWorldSpace(FWD)
end

-- a pebble creature: a smooth rounded stone, lumpy, flecked and cracked, a cushion of moss on top with a sprout and a
-- loose pebble in it, big eyes, a small smile and blush, stubby arms with round hands, round feet with toes
PLANS.blob = function(b, a)
	local t = Kit.new("blob", 1.9, 1, "biped")
	J("body", nil, V(0, 0.35, 0), "body")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("leg" .. s, "body", V(side * 0.4, 0.3, 0.1), "leg", side, if side < 0 then 0 else 0.5)
		Kit.ovoid("Foot" .. s, V(side * 0.42, 0.13, 0.2), V(0.24, 0.13, 0.3), a)
		Kit.toes("Toe" .. s, V(side * 0.42, 0.1, 0.42), 0.3, 0.11, 3, a)
	end
	J("head", "body", V(0, 0.35, 0), "head") -- (the whole stone rocks and nods)
	local C = V(0, 0.95, 0)
	local HR = 0.74
	Kit.ovoid("Rock", C, V(0.85, 0.74, 0.8), b)
	-- lumps break the round outline into a stone's
	Kit.ball("Lump", C + V(-0.36, 0.3, -0.24), 0.86, b)
	Kit.ball("Lump", C + V(0.42, -0.22, -0.3), 0.8, b)
	Kit.ball("Lump", C + V(0.18, 0.4, -0.38), 0.62, b, true)
	-- flecks of another stone, and a crack running down from the top
	for i, f in { { -38, 30, 0.22 }, { 52, -8, 0.18 }, { -60, -20, 0.14 }, { 30, 48, 0.12 }, { -18, -42, 0.1 } } do
		local d = dir(f[1], f[2])
		local at, n = Kit.onBall(C, HR, d)
		Kit.disc("Fleck", at, n, f[3], 0.05, a, i > 2, HR)
	end
	if full() then
		local c1, n1 = Kit.onBall(C, HR + 0.01, dir(-34, 52))
		local c2 = Kit.onBall(C, HR + 0.01, dir(-26, 38))
		local c3 = Kit.onBall(C, HR + 0.01, dir(-36, 26))
		Kit.rod("Crack", c1, c2, 0.06, a, true)
		Kit.rod("Crack", c2, c3, 0.06, a, true)
		local _ = n1
	end
	-- the moss on top: a cushion, tufts round it, a sprout with two leaves and a pebble half in it
	local top = C + V(0.05, HR - 0.08, -0.08)
	Kit.pillow("Moss", top, 0.42, 0.2, UP, "leaf")
	Kit.tuft("MossTuft", top + V(-0.3, 0.06, 0.12), 0.13, "leaf_dark", nil, false)
	Kit.tuft("MossTuft", top + V(0.28, 0.05, -0.16), 0.12, "leaf", nil, true)
	Kit.tuft("MossTuft", top + V(0.08, 0.08, 0.3), 0.1, "leaf_dark", nil, true)
	Kit.rod("Stem", top + V(0.06, 0.08, 0), top + V(0.1, 0.42, 0.02), 0.06, "leaf_dark")
	Kit.blade("Leaf", top + V(0.1, 0.4, 0.02), top + V(0.38, 0.52, 0.06), 0.16, 0.05, V(0, 1, 0.2), "leaf")
	Kit.blade("Leaf", top + V(0.1, 0.38, 0.02), top + V(-0.16, 0.54, 0.0), 0.13, 0.05, V(0, 1, 0.2), "leaf", true)
	Kit.ball("Pebble", top + V(-0.24, 0.1, -0.16), 0.24, a)
	-- the face
	Kit.eyes(C, HR, FWD, R(22), R(4), 0.32, a)
	local m, mn = Kit.onBall(C, HR, dir(0, -20))
	Kit.mouth(m, mn, 0.22)
	Kit.blush(C, HR, FWD, R(40), R(12), 0.2)
	-- stubby arms with round hands
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "head", V(side * 0.7, 0.95, 0.15), "arm", side)
		Kit.tube("Arm" .. s, { V(side * 0.72, 0.92, 0.14), V(side * 0.9, 0.72, 0.24) }, { 0.15, 0.12 }, b)
		Kit.ball("Hand" .. s, V(side * 0.94, 0.6, 0.28), 0.26, a)
		Kit.ball("Thumb" .. s, V(side * 0.86, 0.66, 0.38), 0.12, a, true)
	end
	return t
end

-- a rabbit: a pear-round body on big haunches, a cream belly and chest ruff, a chubby head with puffed cheeks, a
-- muzzle with whisker pads, a pink nose, buck teeth and whiskers, long ears (pink inside, tipped in the accent), little
-- front paws, long hind feet with toe beads, a cotton tail, a sprout on top
PLANS.bun = function(b, a)
	local t = Kit.new("bun", 2.4, 0.9, "hop")
	J("body", nil, V(0, 0.7, 0), "body")
	local BC = V(0, 0.78, -0.12)
	Kit.ovoid("Body", BC, V(0.56, 0.6, 0.66), b)
	-- (the belly bulges out of the body clearly: two round surfaces nearly flush would flicker against each other)
	Kit.ball("Belly", V(0, 0.7, 0.3), 0.74, "cream")
	Kit.tuft("Ruff", V(0, 1.12, 0.28), 0.18, "cream", nil, false)
	-- the head
	J("head", "body", V(0, 1.25, 0.2), "head")
	local HC = V(0, 1.6, 0.3)
	local HR = 0.5
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.ball("Cheek", HC + V(-0.28, -0.16, 0.12), 0.5, b)
	Kit.ball("Cheek", HC + V(0.28, -0.16, 0.12), 0.5, b)
	Kit.ball("Brow", HC + V(0, 0.18, -0.06), 0.8, b, true)
	-- the muzzle: two whisker pads, the nose over them, the teeth under
	local mz = HC + V(0, -0.14, 0.42)
	Kit.ball("Pad", mz + V(-0.09, 0, 0), 0.24, "cream")
	Kit.ball("Pad", mz + V(0.09, 0, 0), 0.24, "cream")
	Kit.ball("Nose", mz + V(0, 0.1, 0.08), 0.13, "pink")
	P("Tooth", "Block", V(0.07, 0.1, 0.05), mz + V(-0.04, -0.13, 0.08), "white")
	P("Tooth", "Block", V(0.07, 0.1, 0.05), mz + V(0.04, -0.13, 0.08), "white")
	Kit.mouth(mz + V(0, -0.08, 0.1), V(0, -0.3, 1), 0.16)
	Kit.whiskers(mz + V(0, 0.02, 0.06), 0.34, "white")
	Kit.eyes(HC, HR, FWD, R(30), R(8), 0.26, a)
	Kit.blush(HC, HR + 0.02, FWD, R(48), R(14), 0.16)
	-- a sprout on top
	Kit.rod("Sprout", HC + V(0, HR - 0.04, -0.04), HC + V(0.02, HR + 0.26, 0), 0.06, "leaf_dark")
	Kit.blade("SproutLeaf", HC + V(0.02, HR + 0.24, 0), HC + V(0.26, HR + 0.36, 0.04), 0.14, 0.05, V(0, 1, 0.3), "leaf")
	Kit.blade("SproutLeaf", HC + V(0.02, HR + 0.22, 0), HC + V(-0.2, HR + 0.34, 0.02), 0.12, 0.05, V(0, 1, 0.3), "leaf", true)
	-- the ears: long tubes with a slight curve back and out, pink inside, the tips in the accent
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ear" .. s, "head", V(side * 0.2, 1.98, 0.22), "ear", side)
		local e0 = V(side * 0.2, 1.96, 0.22)
		local e1 = V(side * 0.28, 2.36, 0.16)
		local e2 = V(side * 0.36, 2.74, 0.04)
		Kit.tube("Ear" .. s, { e0, e1, e2 }, { 0.13, 0.13, 0.09 }, b)
		-- (a flat strip just in front of the ear, clear of its round surface)
		Kit.strip("EarIn" .. s, { e0 + V(0, 0.12, 0.15), e1 + V(0, 0, 0.15), e2 + V(0, -0.12, 0.11) }, { 0.13, 0.12, 0.06 }, V(side * 0.15, 0, 1), "pink")
		Kit.ball("EarTip" .. s, e2 + V(side * 0.01, 0.06, 0), 0.17, a)
	end
	-- little front paws held up at the chest
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.3, 1.0, 0.4), "arm", side)
		Kit.tube("Arm" .. s, { V(side * 0.3, 1.0, 0.36), V(side * 0.26, 0.78, 0.52) }, { 0.12, 0.1 }, b)
		Kit.ball("Paw" .. s, V(side * 0.25, 0.7, 0.56), 0.2, "cream")
		Kit.toes("Finger" .. s, V(side * 0.25, 0.66, 0.6), 0.14, 0.07, 3, "cream")
	end
	-- the haunches and the long hind feet
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("leg" .. s, "body", V(side * 0.42, 0.42, -0.1), "leg", side, 0)
		Kit.ball("Thigh" .. s, V(side * 0.42, 0.46, -0.18), 0.66, b)
		Kit.tube("Foot" .. s, { V(side * 0.4, 0.1, -0.22), V(side * 0.42, 0.09, 0.32) }, { 0.12, 0.11 }, "cream")
		Kit.toes("Toe" .. s, V(side * 0.42, 0.08, 0.4), 0.2, 0.09, 3, "cream")
	end
	-- the cotton tail
	J("tail", "body", V(0, 0.7, -0.72), "tail", 0, 1)
	Kit.tuft("Tail", V(0, 0.72, -0.82), 0.2, "white", nil, false)
	return t
end

return PLANS
