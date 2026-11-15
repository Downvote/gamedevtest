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

-- a pebble creature: a smooth rounded stone, lumpy, flecked, cracked and spotted with pale lichen, a cushion of moss on
-- top spilling down its back with a sprout, a loose pebble, a tiny mushroom and a flower in it, big eyes, a small smile
-- and blush, stubby arms with round hands and three fingers, round feet with toes
PLANS.blob = function(b, a)
	local t = Kit.new("blob", 1.9, 1, "biped")
	local F = full()
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
	Kit.ball("Lump", C + V(-0.46, -0.32, 0.06), 0.66, b, true)
	-- flecks of another stone, and a crack running down from the top and forking
	for i, f in { { -38, 30, 0.22 }, { 52, -8, 0.18 }, { -60, -20, 0.14 }, { 30, 48, 0.12 }, { -18, -42, 0.1 }, { 70, 22, 0.1 }, { -72, 8, 0.08 } } do
		local d = dir(f[1], f[2])
		local at, n = Kit.onBall(C, HR, d)
		Kit.disc("Fleck", at, n, f[3], 0.05, a, i > 2, HR)
	end
	if F then
		local c1 = Kit.onBall(C, HR + 0.01, dir(-34, 52))
		local c2 = Kit.onBall(C, HR + 0.01, dir(-26, 38))
		local c3 = Kit.onBall(C, HR + 0.01, dir(-36, 26))
		local c4 = Kit.onBall(C, HR + 0.01, dir(-16, 30))
		Kit.rod("Crack", c1, c2, 0.06, a, true)
		Kit.rod("Crack", c2, c3, 0.06, a, true)
		Kit.rod("Crack", c2, c4, 0.05, a, true)
	end
	-- the moss on top: a cushion, tufts round it, a spill of it down the back, a sprout with two leaves, a pebble half
	-- in it, a tiny mushroom and a flower
	local top = C + V(0.05, HR - 0.08, -0.08)
	Kit.pillow("Moss", top, 0.42, 0.2, UP, "leaf")
	Kit.tuft("MossTuft", top + V(-0.3, 0.06, 0.12), 0.13, "leaf_dark", nil, false)
	Kit.tuft("MossTuft", top + V(0.28, 0.05, -0.16), 0.12, "leaf", nil, true)
	Kit.tuft("MossTuft", top + V(0.08, 0.08, 0.3), 0.1, "leaf_dark", nil, true)
	-- (each patch set on the stone's surface, down its back and side, smaller as it goes; on the islands the two
	-- biggest)
	for i, q in { { -112, 52, 0.3 }, { -128, 36, 0.24 }, { -96, 36, 0.2 }, { -140, 50, 0.22 }, { -116, 22, 0.14 } } do
		local d = dir(q[1], q[2])
		Kit.ball("MossSpill", C + d * (HR + 0.02), q[3], if i % 2 == 0 then "leaf_dark" else "leaf", i > 2)
	end
	-- the mushroom: a pale stem and a red cap (with two white spots on it up close)
	local mb = top + V(0.3, 0.06, 0.08)
	Kit.rod("Mushroom", mb, mb + V(0.02, 0.16, 0), 0.07, "cream")
	Kit.ball("MushroomCap", mb + V(0.02, 0.18, 0), 0.16, "berry_red")
	if F then
		-- pale lichen on the stone: a round patch with a few small ones by it
		for _, q in { { -52, 28, 0.16 }, { -64, 36, 0.07 }, { -46, 40, 0.06 }, { 58, 14, 0.13 }, { 66, 22, 0.06 } } do
			local at, n = Kit.onBall(C, HR, dir(q[1], q[2]))
			Kit.disc("Lichen", at, n, q[3], 0.05, "cream", true, HR, nil, 0.02)
		end
		-- the mushroom cap's spots
		Kit.ball("MushroomSpot", mb + V(-0.03, 0.24, 0.04), 0.05, "white")
		Kit.ball("MushroomSpot", mb + V(0.07, 0.22, 0.05), 0.05, "white")
		-- the flower: five white petals round a yellow middle
		local fc = top + V(-0.2, 0.13, 0.22)
		for k = 0, 4 do
			local ang = k / 5 * 2 * math.pi
			Kit.ball("Flower", fc + V(math.cos(ang) * 0.05, 0, math.sin(ang) * 0.05), 0.06, "white")
		end
		Kit.ball("FlowerMid", fc + V(0, 0.02, 0), 0.05, "yellow")
	end
	Kit.rod("Stem", top + V(0.06, 0.08, 0), top + V(0.1, 0.42, 0.02), 0.06, "leaf_dark")
	Kit.blade("Leaf", top + V(0.1, 0.4, 0.02), top + V(0.38, 0.52, 0.06), 0.16, 0.05, V(0, 1, 0.2), "leaf")
	Kit.blade("Leaf", top + V(0.1, 0.38, 0.02), top + V(-0.16, 0.54, 0.0), 0.13, 0.05, V(0, 1, 0.2), "leaf", true)
	Kit.ball("Pebble", top + V(-0.24, 0.1, -0.16), 0.24, a)
	-- the face
	Kit.eyes(C, HR, FWD, R(22), R(4), 0.32, a)
	local m, mn = Kit.onBall(C, HR, dir(0, -20))
	Kit.mouth(m, mn, 0.22)
	Kit.blush(C, HR, FWD, R(40), R(12), 0.2)
	-- stubby arms with round hands, three fingers on each
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "head", V(side * 0.7, 0.95, 0.15), "arm", side)
		Kit.tube("Arm" .. s, { V(side * 0.72, 0.92, 0.14), V(side * 0.9, 0.72, 0.24) }, { 0.15, 0.12 }, b)
		local hc = V(side * 0.94, 0.6, 0.28)
		Kit.ball("Hand" .. s, hc, 0.26, a)
		if F then
			for k, q in { V(side * -0.07, -0.02, 0.12), V(side * 0.01, -0.09, 0.12), V(side * 0.08, -0.07, 0.07) } do
				Kit.ball("Finger" .. s, hc + q, if k == 1 then 0.12 else 0.11, a)
			end
		end
	end
	return t
end

-- a rabbit: a pear-round body on big haunches, a cream belly running up into a chest ruff, a chubby head with puffed
-- cheeks and tufts of fur at them, a muzzle with whisker pads, a pink nose, buck teeth and whiskers, long ears (pink
-- inside, tipped in the accent, the left one bent over at the tip), a tuft between them, little front paws, long hind
-- feet with toe beads and pink pads, a cotton tail, a sprout on top
PLANS.bun = function(b, a)
	local t = Kit.new("bun", 2.4, 0.9, "hop")
	local F = full()
	J("body", nil, V(0, 0.7, 0), "body")
	local BC = V(0, 0.76, -0.12)
	Kit.ovoid("Body", BC, V(0.56, 0.57, 0.64), b)
	-- (the belly bulges out of the body clearly: two round surfaces nearly flush would flicker against each other)
	Kit.ball("Belly", V(0, 0.7, 0.3), 0.76, "cream")
	Kit.ball("Belly", V(0, 0.96, 0.3), 0.5, "cream", true)
	Kit.tuft("Ruff", V(0, 1.12, 0.3), 0.18, "cream", nil, false)
	-- the head
	J("head", "body", V(0, 1.25, 0.2), "head")
	local HC = V(0, 1.6, 0.3)
	local HR = 0.53
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.ball("Cheek", HC + V(-0.3, -0.17, 0.12), 0.54, b)
	Kit.ball("Cheek", HC + V(0.3, -0.17, 0.12), 0.54, b)
	Kit.ball("Brow", HC + V(0, 0.18, -0.06), 0.8, b, true)
	-- tufts of fur sticking out at the cheeks, and one between the ears
	if F then
		for _, side in { -1, 1 } do
			Kit.ball("CheekFur", HC + V(side * 0.54, -0.2, 0.06), 0.17, b)
			Kit.ball("CheekFur", HC + V(side * 0.62, -0.24, 0.04), 0.11, b)
			Kit.ball("CheekFur", HC + V(side * 0.52, -0.32, 0.1), 0.13, b)
		end
		Kit.tuft("Forelock", HC + V(0.04, HR - 0.02, 0.1), 0.09, b, 3)
	end
	-- the muzzle: two whisker pads, the nose over them, the teeth under
	local mz = HC + V(0, -0.15, 0.45)
	Kit.ball("Pad", mz + V(-0.09, 0, 0), 0.24, "cream")
	Kit.ball("Pad", mz + V(0.09, 0, 0), 0.24, "cream")
	Kit.ball("Chin", mz + V(0, -0.16, -0.08), 0.22, "cream", true)
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
	-- the ears: long tubes with a slight curve back and out, pink inside, the tips in the accent; the left one bends
	-- over forward and out near its tip
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local bent = side < 0
		J("ear" .. s, "head", V(side * 0.2, 1.98, 0.22), "ear", side)
		local e0 = V(side * 0.2, 1.96, 0.22)
		local e1 = V(side * 0.28, 2.36, 0.16)
		local e2 = if bent then V(side * 0.42, 2.62, 0.16) else V(side * 0.36, 2.74, 0.04)
		local pts = { e0, e1, e2 }
		if bent then
			table.insert(pts, V(side * 0.54, 2.66, 0.3))
		end
		Kit.tube("Ear" .. s, pts, if bent then { 0.13, 0.13, 0.11, 0.08 } else { 0.13, 0.13, 0.09 }, b)
		-- the inside: a flat pink blade along the ear's front, just clear of its round surface (wide low, pointed at the
		-- top), in two pieces that follow the ear's lean
		local f0 = V(side * 0.02, 0, 1).Unit
		local f1 = (V(side * 0.03, 0.25, 1)).Unit
		if bent then
			Kit.blade("EarIn" .. s, e0 + V(0, 0.06, 0) + f0 * 0.19, e2 + V(0, -0.1, 0) + f1 * 0.16, 0.16, 0.05, f0 + f1, "pink")
		else
			Kit.blade("EarIn" .. s, e0 + V(0, 0.06, 0) + f0 * 0.19, e2 + V(0, -0.06, 0) + f1 * 0.15, 0.16, 0.05, f0 + f1, "pink")
		end
		local tipAt = if bent then pts[4] + V(side * 0.03, 0, 0.03) else e2 + V(side * 0.01, 0.06, 0)
		Kit.ball("EarTip" .. s, tipAt, 0.17, a)
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
		Kit.ball("Thigh" .. s, V(side * 0.43, 0.48, -0.16), 0.7, b)
		Kit.tube("Foot" .. s, { V(side * 0.4, 0.1, -0.22), V(side * 0.42, 0.09, 0.32) }, { 0.12, 0.11 }, "cream")
		Kit.toes("Toe" .. s, V(side * 0.42, 0.08, 0.4), 0.2, 0.09, 3, "cream")
		-- the pads on the sole, pink, showing at the heel and under the toes
		if F then
			Kit.ball("Pad" .. s, V(side * 0.41, 0.07, -0.22), 0.12, "pink")
			Kit.ball("Pad" .. s, V(side * 0.42, 0.04, 0.26), 0.1, "pink")
		end
	end
	-- the cotton tail
	J("tail", "body", V(0, 0.7, -0.72), "tail", 0, 1)
	Kit.tuft("Tail", V(0, 0.72, -0.82), 0.2, "white", nil, false)
	return t
end

return PLANS
