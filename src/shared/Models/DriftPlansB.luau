--!strict
-- Body plans built with the kit (Models/DriftKit; Models/DriftModels uses them over its old ones): the crab, the
-- snail, the turtle, the frog, the jellyfish and the sprite. Each returns its Thing; a plan faces +Z with its feet on
-- the ground at y 0 (the jellyfish and the sprite float over it). The joints are the old plans' (their names, kinds,
-- parents, sides and phases), so every mood moves them as it did.
local Kit = require(script.Parent.DriftKit)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full

local PLANS: { [string]: (b: string, a: string) -> Kit.Thing } = {}

local UP = V(0, 1, 0)
local FWD = V(0, 0, 1)

-- A direction from forward: turned `yaw` degrees toward -x (-) or +x (+) and `pitch` up (+) or down (-).
local function dir(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(-pitch), 0, 0)):VectorToWorldSpace(FWD)
end

-- Where a ray from `o` along `d` leaves a body made of balls (the parts in `balls`): the point, the normal there and
-- the radius of the ball it leaves by. Spots, seams and faces go on the body as built: a body of balls is not quite
-- the ellipsoid it was asked to be (a little inside it here, a little outside there).
local function surf(balls: { BasePart }, o: Vector3, d: Vector3): (Vector3, Vector3, number)
	local u = d.Unit
	local best, bc, br = -1, o, 0.5
	for _, p in balls do
		local c = p.Position
		local r = p.Size.X / 2
		local oc = o - c
		local bq = oc:Dot(u)
		local disc = bq * bq - (oc:Dot(oc) - r * r)
		if disc >= 0 then
			local tt = -bq + math.sqrt(disc)
			if tt > best then
				best, bc, br = tt, c, r
			end
		end
	end
	if best < 0 then
		return o, u, br
	end
	local hit = o + u * best
	return hit, (hit - bc).Unit, br
end

-- An egg-round body (an ellipsoid, half sizes `half`, turned by `rot`): balls along its longest axis as Kit.ovoid
-- lays them, but three abreast where it is wide, the middle one as tall as the body (two alone leave a groove down
-- its back). `step` scales the gap between them along it. (Fewer, bigger balls shade smoother: more rows only make
-- the light's bands ragged.)
local function blob(name: string, c: Vector3, half: Vector3, color: string, rot: CFrame?, detail: boolean?, step: number?): { BasePart }
	local out: { BasePart } = {}
	if detail and not full() then
		return out
	end
	local R0 = rot or CFrame.identity
	local axes = { { v = V(1, 0, 0), l = half.X }, { v = V(0, 1, 0), l = half.Y }, { v = V(0, 0, 1), l = half.Z } }
	table.sort(axes, function(p, q)
		return p.l > q.l
	end)
	local A, B, C = axes[1], axes[2], axes[3]
	local reach = math.max(0, A.l - C.l)
	local spacing = C.l * (if full() then 0.7 else 1.05) * (step or 1)
	local n = if reach < 0.02 then 0 else math.max(1, math.ceil(2 * reach / spacing))
	for i = 0, n do
		local s = if n > 0 then -1 + 2 * i / n else 0
		local along = s * reach
		local f = math.sqrt(math.max(0.05, 1 - (along / A.l) ^ 2))
		local rc = C.l * f
		local side = (B.l - C.l) * f
		local offs: { number } = if side > rc * 0.3 then { 0, side, -side } else { 0 }
		for _, off in offs do
			local p = A.v * along + B.v * off
			table.insert(out, Kit.part(name, "Ball", V(2 * rc, 2 * rc, 2 * rc), CFrame.new(c + R0:VectorToWorldSpace(p)), color))
		end
	end
	return out
end

-- A pair of eyes on a head of balls (seen from `c`), `yaw` either side of forward and `pitch` up.
local function eyesOn(balls: { BasePart }, c: Vector3, yaw: number, pitch: number, d: number, iris: string?)
	for _, side in { -1, 1 } do
		local p, n, r = surf(balls, c, dir(side * yaw, pitch))
		Kit.eye(if side < 0 then "L" else "R", p - n * r, r, n, d, iris)
	end
end

-- Blush on a head of balls (set a little out: a body of many balls is not quite round under it, and a disc sunk into it
-- shows only as a ring).
local function blushOn(balls: { BasePart }, c: Vector3, yaw: number, pitch: number, d: number)
	for _, side in { -1, 1 } do
		local p, n, r = surf(balls, c, dir(side * yaw, pitch))
		Kit.disc("Cheek" .. (if side < 0 then "L" else "R"), p, n, d, 0.05, "pink", false, r, nil, 0.05)
	end
end

-- A thin line through points (a mouth's seam, a vein): rods end to end.
local function line(name: string, pts: { Vector3 }, d: number, color: string, detail: boolean?)
	for i = 1, #pts - 1 do
		Kit.rod(name, pts[i], pts[i + 1], d, color, detail)
	end
end

-- A limb (a leg, an arm, a neck, a tail): a smooth tube through `pts` up close; on the islands one rod from end to
-- end as thick as the tube on average, which reads the same at that size.
local function limb(name: string, pts: { Vector3 }, radii: { number }, color: string, step: number?)
	if full() then
		Kit.tube(name, pts, radii, color, step)
		return
	end
	local r = 0
	for _, x in radii do
		r += x
	end
	Kit.rod(name, pts[1], pts[#pts], 2 * r / #radii, color)
end

-- A thin membrane (a wing, a fin) through points, as wide as `widths` says along it: a few round discs, each a step
-- in front of the one before (discs flush in one plane flicker against each other in the picture). Returns how far in
-- front of the points its last disc lies.
local function membrane(name: string, pts: { Vector3 }, widths: { number }, normal: Vector3, color: string, n: number): number
	local nn = normal.Unit
	for i = 0, n - 1 do
		local u = if n > 1 then i / (n - 1) else 0.5
		local f = u * (#widths - 1)
		local k = math.min(math.floor(f), #widths - 2)
		local w = widths[k + 1] + (widths[k + 2] - widths[k + 1]) * (f - k)
		Kit.disc(name, Kit.curveAt(pts, u) + nn * (0.03 * i), nn, w, 0.05, color)
	end
	return 0.03 * (n - 1) + 0.05
end

------------------------------------------------------------------ the crab
-- a crab: a wide, low carapace (wider than long, a little flat on top) with small teeth along its front edge, pale
-- spots and a pale underside showing under its rim; eyes on stalks with a knob between them, a smile and blush under
-- them; two big claws held in toward the middle (an upper arm, a wrist with a spine, a fat palm with knuckles along its
-- top and spots on its side, a fixed finger under and a hinged one over, both toothed on the inside and dark at the
-- tip); three jointed legs a side, knobbed at the knee and dark at their points
PLANS.crab = function(b, a)
	local t = Kit.new("crab", 1.6, 1.2, "scuttle")
	local F = full()
	J("body", nil, V(0, 0.75, 0), "body")
	local SC = V(0, 0.8, -0.04)
	local SH = V(0.8, 0.38, 0.56)
	-- (three balls abreast down its length: one smooth surface; on the islands fewer, bigger ones)
	local shell = blob("Shell", SC, SH, b, nil, nil, if F then 1 else 1.5)
	-- the pale underside, its edge showing under the rim all round
	Kit.disc("Under", SC + V(0, -0.34, 0.02), UP, 1.04, 0.14, "cream")
	-- the teeth along the front edge
	for _, side in { -1, 1 } do
		local yaws: { number } = if F then { 36, 50, 64, 78 } else { 42, 68 }
		for i, yaw in yaws do
			local p, n = surf(shell, SC, dir(side * yaw, 2))
			Kit.ball("Tooth", p + n * 0.02, if not F then 0.18 elseif i == 4 then 0.12 else 0.14, b)
		end
	end
	-- two knobs on the brow between the eye stalks
	if F then
		for _, side in { -1, 1 } do
			local p, n = surf(shell, SC, dir(side * 8, 26))
			Kit.ball("Brow", p + n * 0.01, 0.13, b)
		end
	end
	-- spots
	for i, sp in { { 40, 52, 0.2 }, { -46, 46, 0.16 }, { 150, 50, 0.18 }, { -140, 56, 0.14 }, { 100, 34, 0.12 }, { -96, 40, 0.1 }, { 176, 64, 0.1 } } do
		local p, n, r = surf(shell, SC, dir(sp[1], sp[2]))
		Kit.disc("Spot", p, n, sp[3], 0.05, "cream", i > 3, r)
	end
	-- the face on the front of the shell, and the little mouth plates under it
	local m, mn = surf(shell, SC, dir(0, -4))
	Kit.mouth(m + mn * 0.01, mn, 0.2)
	-- (the blush beside the smile, clear of the teeth: a tooth on it leaves only a ring of pink)
	blushOn(shell, SC, 19, 4, 0.17)
	if F then
		for _, side in { -1, 1 } do
			local p, n = surf(shell, SC, dir(side * 7, -34))
			Kit.ball("MouthPlate", p + n * 0.02, 0.13, "cream")
		end
	end
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local x = side
		Kit.on("body")
		-- an eye on a stalk
		J("stalk" .. s, "body", V(x * 0.28, 1.15, 0.42), "stalk", side)
		local e0, e1 = V(x * 0.22, 1.02, 0.42), V(x * 0.3, 1.46, 0.5)
		if F then
			Kit.tube("Stalk" .. s, { e0, V(x * 0.27, 1.26, 0.49), e1 }, { 0.075, 0.06 }, a, 1.6)
			Kit.ball("StalkRing" .. s, V(x * 0.295, 1.42, 0.5), 0.15, b)
		else
			Kit.rod("Stalk" .. s, e0, e1, 0.13, a)
		end
		local EC = V(x * 0.31, 1.6, 0.52)
		Kit.ball("EyeBulb" .. s, EC, 0.36, b)
		Kit.eye(s, EC, 0.18, dir(x * 14, 6), 0.28, a)
		-- the claw
		J("arm" .. s, "body", V(x * 0.85, 0.82, 0.35), "arm", side)
		local a0, a1, a2 = V(x * 0.62, 0.74, 0.3), V(x * 0.92, 0.8, 0.5), V(x * 1.06, 0.86, 0.68)
		if F then
			Kit.tube("Arm" .. s, { a0, a1, a2 }, { 0.12, 0.1 }, b, 1.4)
			Kit.ball("Elbow" .. s, a1 + V(x * 0.02, 0.04, 0), 0.2, b)
		else
			Kit.rod("Arm" .. s, a0, a2, 0.2, b)
		end
		-- the hand, turned in toward the middle as a crab holds it: a fat palm, the fixed finger under and the hinged
		-- one over it, open a little, toothed on the inside and dark at the tips
		local W0 = V(x * 1.06, 0.88, 0.76)
		local fw = dir(-x * 32, 4)
		local out = UP:Cross(fw).Unit * x
		if out.X * x < 0 then
			out = -out
		end
		local function H(along: number, up: number, outward: number): Vector3
			return W0 + fw * along + UP * up + out * outward
		end
		Kit.ball("Wrist" .. s, W0, 0.27, b)
		Kit.ball("WristSpine" .. s, W0 + V(0, 0.12, 0) + out * 0.04, 0.1, a, true)
		local PC = H(0.24, 0.05, 0)
		local palm = blob("Palm" .. s, PC, V(0.25, 0.28, 0.33), b, CFrame.lookAt(Vector3.zero, fw))
		if F then
			-- knuckles along the palm's top and a few spots on its outer side
			for k = 0, 2 do
				Kit.ball("Knuckle" .. s, H(0.1 + k * 0.13, 0.3 - k * 0.01, 0.02), 0.11, b)
			end
			for k, q in { { 0.14, 0.12 }, { 0.3, 0.02 }, { 0.2, -0.1 } } do
				local p, n, r = surf(palm, PC, out + fw * (q[1] - 0.22) * 2 + UP * q[2] * 2)
				Kit.disc("ClawSpot" .. s, p, n, if k == 1 then 0.1 else 0.08, 0.05, a, true, r)
			end
		end
		local f0, f1, f2 = H(0.46, -0.1, 0), H(0.7, -0.12, 0), H(0.92, 0.0, 0)
		if F then
			Kit.tube("Finger" .. s, { f0, f1 }, { 0.13, 0.09 }, b)
			Kit.tube("FingerTip" .. s, { f1, f2 }, { 0.09, 0.035 }, a)
			for k = 1, 3 do
				Kit.ball("Serration" .. s, H(0.5 + k * 0.1, -0.02 - k * 0.01, 0), 0.08, "cream", true)
			end
		else
			Kit.rod("Finger" .. s, f0, f2, 0.16, b)
		end
		J("pincer" .. s, "arm" .. s, H(0.38, 0.16, 0), "pincer", side)
		local d0, d1, d2 = H(0.4, 0.16, 0), H(0.66, 0.24, 0), H(0.9, 0.18, 0)
		if F then
			Kit.tube("Pincer" .. s, { d0, d1 }, { 0.12, 0.085 }, b)
			Kit.tube("PincerTip" .. s, { d1, d2 }, { 0.085, 0.035 }, a)
			for k = 1, 3 do
				Kit.ball("Serration" .. s, H(0.48 + k * 0.1, 0.13 + k * 0.025, 0), 0.08, "cream", true)
			end
		else
			Kit.rod("Pincer" .. s, d0, d2, 0.16, b)
		end
		-- three legs: out and up to the knee, down to a point
		for i, z in { 0.2, -0.12, -0.44 } do
			Kit.on("body")
			J("leg" .. s .. i, "body", V(x * 0.82, 0.55, z), "leg", side, (i % 2) * 0.5)
			local fz = ({ 0.12, 0, -0.14 })[i]
			local hip = V(x * 0.7, 0.62, z)
			local knee = V(x * 1.06, 0.82, z + fz * 0.6)
			local ankle = V(x * 1.28, 0.42, z + fz * 1.2)
			local tip = V(x * 1.36, 0.03, z + fz * 1.6)
			if F then
				Kit.tube("Leg" .. s .. i, { hip, knee }, { 0.085, 0.075 }, b, 1.6)
				Kit.ball("Knee" .. s .. i, knee, 0.17, b)
				Kit.tube("Shin" .. s .. i, { knee, ankle }, { 0.075, 0.06 }, b, 1.6)
				Kit.ball("Ankle" .. s .. i, ankle, 0.13, a)
				Kit.tube("LegTip" .. s .. i, { ankle, tip }, { 0.055, 0.018 }, a, 2)
			else
				Kit.rod("Leg" .. s .. i, hip, knee, 0.15, b)
				Kit.rod("LegTip" .. s .. i, knee, tip, 0.12, a)
			end
		end
	end
	return t
end

------------------------------------------------------------------ the snail
-- a snail: a long soft foot with a pointed tail, bumps and a wet shine along its back and a pale frilled skirt along
-- the ground; a round shell standing on its back, its sides flat with the coil drawn on them (each turn a ring in the
-- shell's colour inside a band of the body's, smaller and pushed round a little more each time, so it winds in to a
-- point), a shine on its top; a round head with a smile and blush, two short feelers, the eyes on two long stalks
PLANS.snail = function(b, a)
	local t = Kit.new("snail", 2.0, 1.1, "slither")
	local F = full()
	J("body", nil, V(0, 0.3, 0), "body")
	Kit.tube("Foot", { V(0, 0.08, -1.06), V(0, 0.18, -0.68), V(0, 0.24, -0.15), V(0, 0.26, 0.35), V(0, 0.36, 0.72) }, { 0.06, 0.2, 0.3, 0.3, 0.27 }, b)
	-- the skirt: a pale frilled edge along each side of the foot where it meets the ground (along the foot's side at
	-- that height), thicker and thinner in turn
	for _, side in { -1, 1 } do
		local pts = { V(side * 0.12, 0.07, -0.86), V(side * 0.22, 0.06, -0.5), V(side * 0.275, 0.06, -0.1), V(side * 0.27, 0.06, 0.26), V(side * 0.22, 0.08, 0.5) }
		if F then
			Kit.tube("Skirt", pts, { 0.04, 0.075, 0.055, 0.075, 0.055, 0.075, 0.045 }, "cream", 0.6)
		else
			Kit.rod("Skirt", pts[2], V(side * 0.25, 0.06, 0.26), 0.14, "cream")
		end
	end
	if F then
		for i, z in { -0.62, -0.8, -0.94 } do
			Kit.ball("Bump", V(0, 0.3 - i * 0.06, z), 0.08, b)
		end
		-- a wet shine along the top of the foot, in front of the shell and toward the tail
		for _, q in { { 0.32, 0.56, 0.1 }, { 0.42, 0.57, 0.06 }, { -0.5, 0.42, 0.07 } } do
			local c = V(0, q[2], q[1])
			local n = V(0, 1, 0.25).Unit
			Kit.disc("Wet", c + V(-0.06, 0, 0), n, q[3], 0.05, "white", true, 0.3, nil, 0.02)
		end
		for _, q in { V(-0.08, 0.6, 0.62), V(0.09, 0.57, 0.56), V(0, 0.64, 0.7) } do
			Kit.ball("Bump", q, 0.07, b)
		end
	end
	-- the shell: a thick round disc on edge with a ring of balls round its rim (round in outline, flat on its sides),
	-- sitting a little into the foot
	J("shell", "body", V(0, 0.55, -0.25), "shell")
	local SC = V(0, 0.98, -0.34)
	local SR, SW = 0.56, 0.52 -- its radius, and how thick it is side to side
	local inner = SR - SW / 2
	Kit.part("Shell", "Cylinder", V(SW, 2 * inner, 2 * inner), CFrame.new(SC), a)
	local nrim = if F then 11 else 7
	for i = 0, nrim - 1 do
		local ang = i / nrim * 2 * math.pi
		Kit.ball("ShellRim", SC + V(0, math.sin(ang), math.cos(ang)) * inner, SW, a)
	end
	-- the coil on each flat side: a disc in the body's colour, then one in the shell's colour a little smaller and set
	-- off toward one side so the band shows as a crescent, and so on inward, each step turned on round the centre and a
	-- step further out (the picture draws a part over another only where it is clearly nearer)
	local rings: { number } = if F then { 0.3, 0.255, 0.19, 0.15, 0.095, 0.06 } else { 0.3, 0.24, 0.13 }
	for _, side in { -1, 1 } do
		local nrm = V(side, 0, 0)
		local c = SC + nrm * (SW / 2)
		local ang = R(200)
		for k, r in rings do
			if k > 1 then
				local prev = rings[k - 1]
				c += V(0, math.sin(ang), math.cos(ang)) * (prev - r) * 0.9
				ang += R(150)
			end
			Kit.disc("Coil", c, nrm, 2 * r, 0.05, if k % 2 == 1 then b else a, false, nil, nil, (k - 1) * 0.045)
		end
	end
	-- a shine on the shell's top, toward the front
	if F then
		local d = V(0, 0.8, 0.6).Unit
		Kit.disc("Gloss", SC + d * SR, d, 0.12, 0.05, "white", true, SW / 2, nil, 0.01)
		Kit.disc("Gloss", SC + V(0.0, 0.62, 0.78).Unit * SR + V(0, -0.02, 0.04), d, 0.07, 0.05, "white", true, SW / 2, nil, 0.01)
	end
	-- the head
	J("head", "body", V(0, 0.5, 0.85), "head")
	local HC = V(0, 0.66, 0.98)
	local HR = 0.3
	Kit.ball("Head", HC, 2 * HR, b)
	local m, mn = Kit.onBall(HC, HR, dir(0, -18))
	Kit.mouth(m, mn, 0.18)
	Kit.blush(HC, HR, FWD, R(44), R(12), 0.14)
	for _, side in { -1, 1 } do
		local f0 = HC + dir(side * 24, -14) * (HR - 0.04)
		local f1 = f0 + V(side * 0.07, -0.08, 0.2)
		Kit.tube("Feeler", { f0, f1 }, { 0.05, 0.035 }, b, nil, true)
		Kit.ball("FeelerTip", f1, 0.09, a, true)
	end
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("stalk" .. s, "head", V(side * 0.18, 1.0, 1.05), "stalk", side)
		local s0, s1, s2 = V(side * 0.12, 0.86, 1.0), V(side * 0.2, 1.22, 1.06), V(side * 0.27, 1.5, 1.04)
		if F then
			Kit.tube("Stalk" .. s, { s0, s1, s2 }, { 0.075, 0.06, 0.055 }, b, 1.5)
		else
			Kit.rod("Stalk" .. s, s0, s2, 0.12, b)
		end
		local EC = V(side * 0.28, 1.62, 1.06)
		Kit.ball("EyeBulb" .. s, EC, 0.32, b)
		Kit.eye(s, EC, 0.16, dir(side * 12, 4), 0.26, a)
	end
	return t
end

------------------------------------------------------------------ the turtle
-- a turtle: a domed shell with the seams of its plates drawn on it in the body's colour (a ring of small plates round
-- the rim, the middle row's plates with their first growth ring), a scalloped rim and a pale belly plate under it; a
-- head on a short neck with a pale throat, puffed cheeks, a round snout with a little hooked beak, nostrils, a smile
-- and a lower beak that drops with a pale chin; four stumpy legs with scales and claws, a pointed tail
PLANS.turtle = function(b, a)
	local t = Kit.new("turtle", 1.7, 1.2, "quad")
	local F = full()
	J("body", nil, V(0, 0.6, 0), "body")
	local SC = V(0, 0.76, -0.08)
	local SH = V(0.84, 0.47, 0.96)
	local shell = blob("Shell", SC, SH, a)
	-- the belly plate, its edge showing under the rim
	Kit.disc("Plastron", V(0, 0.4, 0.04), UP, 1.46, 0.14, "cream", true)
	-- the rim
	local nr = if F then 18 else 8
	for i = 0, nr - 1 do
		local ang = i / nr * 2 * math.pi
		Kit.ball("Rim", SC + V(math.sin(ang) * SH.X * 0.98, -0.08, math.cos(ang) * SH.Z * 0.98), if F then 0.3 else 0.38, a)
	end
	-- the seams between its plates: a row of plates down the middle, three a side, a ring of small ones round the rim
	-- (points across the shell from above, -1 to 1, laid on its surface)
	local function onTop(u: number, v: number, lift: number?): (Vector3, Vector3)
		local y = math.sqrt(math.max(0, 1 - u * u - v * v))
		local p, n = surf(shell, SC, V(u * SH.X, y * SH.Y, v * SH.Z))
		return p + n * (lift or 0.03), n
	end
	-- (in short rods, so none cuts into the shell between its ends)
	local function seam(uv: { number })
		local pts: { Vector3 } = {}
		for i = 1, #uv - 2, 2 do
			local u0, v0, u1, v1 = uv[i], uv[i + 1], uv[i + 2], uv[i + 3]
			local k = math.max(1, math.ceil(math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2) / (if F then 0.3 else 0.45)))
			for j = (if i == 1 then 0 else 1), k do
				table.insert(pts, (onTop(u0 + (u1 - u0) * j / k, v0 + (v1 - v0) * j / k)))
			end
		end
		line("Seam", pts, 0.06, b)
	end
	if F then
		local ring: { number } = {}
		for i = 0, 14 do
			local ang = i / 14 * 2 * math.pi
			table.insert(ring, math.sin(ang) * 0.84)
			table.insert(ring, math.cos(ang) * 0.84)
		end
		seam(ring)
		for _, x in { -1, 1 } do
			seam({ x * 0.17, 0.8, x * 0.26, 0.56, x * 0.17, 0.32, x * 0.26, 0.06, x * 0.17, -0.2, x * 0.26, -0.46, x * 0.17, -0.8 })
			seam({ x * 0.26, 0.56, x * 0.48, 0.6, x * 0.62, 0.58 })
			seam({ x * 0.26, 0.06, x * 0.56, 0.05, x * 0.84, 0.02 })
			seam({ x * 0.26, -0.46, x * 0.48, -0.52, x * 0.62, -0.58 })
		end
		seam({ -0.17, 0.32, 0.17, 0.32 })
		seam({ -0.17, -0.2, 0.17, -0.2 })
		-- the rim's small plates: a short seam out from each corner of the ring to the edge
		for i = 0, 13 do
			local ang = i / 14 * 2 * math.pi
			seam({ math.sin(ang) * 0.84, math.cos(ang) * 0.84, math.sin(ang) * 0.99, math.cos(ang) * 0.99 })
		end
		-- a small ring of the body's colour in the middle of each of the middle row's plates, its first growth
		for _, v in { 0.58, 0.06, -0.5 } do
			local c, cn = onTop(0, v, 0.0)
			Kit.disc("Growth", c, cn, 0.16, 0.05, b, true, SH.Y)
			Kit.disc("GrowthIn", c, cn, 0.08, 0.05, a, true, SH.Y, nil, 0.04)
		end
	else
		-- (on the islands the middle row alone)
		for _, x in { -1, 1 } do
			seam({ x * 0.17, 0.8, x * 0.26, 0.3, x * 0.26, -0.3, x * 0.17, -0.8 })
		end
		seam({ -0.26, 0.3, 0.26, 0.3 })
		seam({ -0.26, -0.3, 0.26, -0.3 })
	end
	-- the head
	J("head", "body", V(0, 0.7, 0.95), "head")
	limb("Neck", { V(0, 0.62, 0.6), V(0, 0.74, 0.92), V(0, 0.88, 1.1) }, { 0.21, 0.19 }, b, 1.3)
	Kit.ball("Throat", V(0, 0.72, 1.04), 0.26, "cream", true)
	local HC = V(0, 0.98, 1.3)
	local HH = V(0.34, 0.31, 0.38)
	local head = blob("Head", HC, HH, b)
	Kit.ball("CheekPuff", V(-0.18, 0.88, 1.38), 0.34, b, true)
	Kit.ball("CheekPuff", V(0.18, 0.88, 1.38), 0.34, b, true)
	eyesOn(head, HC, 34, 14, 0.24, a)
	blushOn(head, HC, 50, -10, 0.14)
	for _, side in { -1, 1 } do
		local p, n = surf(head, HC, dir(side * 9, 12))
		Kit.ball("Nostril", p + n * 0.01, 0.06, "black", true)
	end
	-- scales on the top of the head
	for _, q in { { -16, 50, 0.12 }, { 16, 50, 0.12 }, { 0, 66, 0.14 } } do
		local p, n, r = surf(head, HC, dir(q[1], q[2]))
		Kit.disc("HeadScale", p, n, q[3], 0.05, a, true, r, nil, 0.02)
	end
	-- the little hook of the upper beak over the smile
	local bt, btn = surf(head, HC, dir(0, -4))
	Kit.ball("BeakTip", bt + btn * 0.01, if F then 0.12 else 0.14, a)
	local m, mn = surf(head, HC, dir(0, -20))
	Kit.mouth(m, mn, 0.24)
	-- the lower beak, a lip round the bottom of the snout that drops when the mouth opens, a pale chin behind it
	J("jaw", "head", V(0, 0.8, 1.16), "jaw")
	local lip: { Vector3 } = {}
	for _, yaw in { -52, -26, 0, 26, 52 } do
		local p, n = surf(head, HC, dir(yaw, -38 + 8 * math.abs(yaw) / 52))
		table.insert(lip, p + n * 0.02)
	end
	if F then
		Kit.tube("Beak", lip, { 0.07, 0.085, 0.07 }, a)
		local c, cn, cr = surf(head, HC, dir(0, -62))
		Kit.disc("Chin", c, cn, 0.22, 0.05, "cream", true, cr, nil, 0.02)
	else
		Kit.rod("Beak", lip[2], lip[4], 0.16, a)
	end
	-- legs
	for _, l in { { n = "FL", s = -1, z = 0.6, ph = 0 }, { n = "FR", s = 1, z = 0.6, ph = 0.5 }, { n = "BL", s = -1, z = -0.65, ph = 0.5 }, { n = "BR", s = 1, z = -0.65, ph = 0 } } do
		local x, z = l.s, l.z
		local fz = if z > 0 then 0.1 else -0.08
		Kit.on("body")
		J("leg" .. l.n, "body", V(x * 0.6, 0.45, z), "leg", x, l.ph)
		local top, mid, foot = V(x * 0.56, 0.46, z), V(x * 0.72, 0.28, z + fz * 0.6), V(x * 0.8, 0.14, z + fz)
		if F then
			Kit.tube("Leg" .. l.n, { top, mid, foot }, { 0.2, 0.18, 0.17 }, b, 1.4)
		else
			Kit.tube("Leg" .. l.n, { top, foot }, { 0.2, 0.17 }, b)
		end
		Kit.ball("Foot" .. l.n, foot + V(0, -0.02, 0.05), 0.38, b)
		Kit.toes("Claw" .. l.n, foot + V(0, -0.08, 0.2), 0.24, 0.1, 3, "cream")
		-- scales down the front of the leg
		Kit.disc("Scale" .. l.n, mid + V(x * 0.06, 0.04, 0.17), V(x * 0.3, 0.2, 1), 0.11, 0.05, a, true, 0.18, nil, 0.01)
		Kit.disc("Scale" .. l.n, top:Lerp(mid, 0.4) + V(x * 0.1, 0.02, 0.17), V(x * 0.4, 0.3, 1), 0.09, 0.05, a, true, 0.19, nil, 0.01)
		Kit.disc("Scale" .. l.n, mid:Lerp(foot, 0.6) + V(x * 0.03, 0, 0.17), V(x * 0.2, 0.1, 1), 0.08, 0.05, a, true, 0.17, nil, 0.01)
	end
	J("tail", "body", V(0, 0.5, -1.1), "tail", 0, 1)
	limb("Tail", { V(0, 0.52, -0.95), V(0, 0.44, -1.2), V(0.03, 0.3, -1.38) }, { 0.13, 0.08, 0.03 }, b, 1.3)
	return t
end

------------------------------------------------------------------ the frog
-- a frog: a squat body sloping up to the front with a pale belly, spots and warts; a wide flat head with big eyes on
-- domes, ear discs, nostrils and a mouth from cheek to cheek, a lower jaw with a pale throat that drops open; thin
-- front legs on four splayed fingers with round pads; folded hind legs (a fat thigh, the shin back along it, a long
-- foot, bands across them in the accent) on webbed toes
PLANS.frog = function(b, a)
	local t = Kit.new("frog", 1.6, 1.1, "hop")
	local F = full()
	J("body", nil, V(0, 0.5, 0), "body")
	local BC = V(0, 0.54, -0.16)
	local BH = V(0.52, 0.4, 0.56)
	local tilt = CFrame.Angles(R(-18), 0, 0)
	local body = blob("Body", BC, BH, b, tilt)
	Kit.ball("Belly", V(0, 0.44, 0.18), 0.72, "cream")
	for i, sp in { { 150, 40, 0.2 }, { -140, 48, 0.16 }, { 112, 26, 0.14 }, { -104, 30, 0.15 }, { 180, 64, 0.12 } } do
		local p, n, r = surf(body, BC, dir(sp[1], sp[2]))
		Kit.disc("Spot", p, n, sp[3], 0.05, a, i > 3, r)
	end
	for _, sp in { { 128, 52 }, { -120, 38 }, { 160, 24 }, { -162, 56 } } do
		local p = surf(body, BC, dir(sp[1], sp[2]))
		Kit.ball("Wart", p, 0.09, b, true)
	end
	-- the head
	J("head", "body", V(0, 0.75, 0.4), "head")
	local HC = V(0, 0.9, 0.36)
	local HH = V(0.54, 0.24, 0.4)
	local head = blob("Head", HC, HH, b, nil, nil, if F then 1 else 1.5)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local EC = V(side * 0.3, 1.12, 0.46)
		Kit.ball("EyeDome" .. s, EC, 0.46, b)
		Kit.eye(s, EC, 0.23, dir(side * 30, 14), 0.3, "gold")
		local p, n, r = surf(head, HC, dir(side * 80, 12))
		Kit.disc("Tympanum" .. s, p, n, 0.2, 0.05, a, true, r)
		local q, qn = surf(head, HC, dir(side * 9, 22))
		Kit.ball("Nostril", q + qn * 0.01, 0.06, "black", true)
	end
	blushOn(head, HC, 52, -6, 0.16)
	local hs, hn, hr = surf(head, HC, dir(0, 70))
	Kit.disc("HeadSpot", hs, hn, 0.12, 0.05, a, true, hr)
	-- the mouth: a seam from cheek to cheek, turned up at the ends
	local sm: { Vector3 } = {}
	local yaws: { number } = if F then { -76, -60, -42, -21, 0, 21, 42, 60, 76 } else { -70, -35, 0, 35, 70 }
	for _, yaw in yaws do
		local k = math.abs(yaw) / 76
		local p, n = surf(head, HC, dir(yaw, -26 + 14 * k * k))
		table.insert(sm, p + n * 0.03)
	end
	line("Lip", sm, 0.05, "black")
	-- a pale stripe along the upper lip, just over the seam
	if F then
		local up: { Vector3 } = {}
		for i, yaw in yaws do
			if i > 1 and i < #yaws then
				local k = math.abs(yaw) / 76
				local p, n = surf(head, HC, dir(yaw, -19 + 14 * k * k))
				table.insert(up, p + n * 0.03)
			end
		end
		line("LipStripe", up, 0.05, "cream")
	end
	Kit.ball("MouthIn", V(0, 0.76, 0.48), 0.36, "berry_red")
	J("jaw", "head", V(0, 0.75, 0.3), "jaw")
	if F then
		Kit.tube("Jaw", { V(-0.4, 0.7, 0.28), V(-0.22, 0.66, 0.56), V(0.22, 0.66, 0.56), V(0.4, 0.7, 0.28) }, { 0.13 }, b)
	else
		Kit.rod("Jaw", V(-0.3, 0.67, 0.5), V(0.3, 0.67, 0.5), 0.26, b)
	end
	-- the throat sac, a pale balloon under the jaw
	Kit.ball("Throat", V(0, 0.59, 0.46), 0.48, "cream")
	Kit.ball("Tongue", V(0, 0.72, 0.5), 0.2, "pink", true)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		-- a front leg on four splayed fingers
		Kit.on("body")
		J("arm" .. s, "body", V(side * 0.55, 0.45, 0.5), "arm", side)
		local sh, el, wr = V(side * 0.4, 0.44, 0.38), V(side * 0.54, 0.24, 0.46), V(side * 0.56, 0.08, 0.6)
		limb("Arm" .. s, { sh, el, wr }, { 0.11, 0.09, 0.075 }, b, 1.4)
		if F then
			for i, yaw in { -34, -8, 18, 44 } do
				local tip = wr + V(0, -0.03, 0) + dir(side * yaw, -5) * (if i == 2 or i == 3 then 0.2 else 0.16)
				Kit.rod("Finger" .. s, wr + V(0, -0.03, 0), tip, 0.06, b)
				Kit.ball("FingerPad" .. s, tip, 0.11, a)
			end
		else
			Kit.ball("Hand" .. s, wr + V(0, -0.02, 0.05), 0.2, b)
		end
		-- a folded hind leg: the thigh forward, the shin back along it, the long foot forward again on the ground
		J("leg" .. s, "body", V(side * 0.6, 0.45, -0.35), "leg", side, 0)
		local hip, knee, ankle = V(side * 0.36, 0.5, -0.5), V(side * 0.74, 0.42, -0.02), V(side * 0.66, 0.12, -0.5)
		if F then
			local thigh = { hip, (hip + knee) / 2 + V(side * 0.05, 0.06, 0), knee }
			Kit.tube("Thigh" .. s, thigh, { 0.26, 0.22, 0.15 }, b, 1.2)
			-- bands across the thigh and the shin in the accent, as many frogs have: a ring round the leg a little
			-- wider than it
			for _, q in { { 0.42, 0.226 }, { 0.72, 0.19 } } do
				local u = q[1]
				local c = Kit.curveAt(thigh, u)
				local ax = Kit.curveAt(thigh, u + 0.04) - Kit.curveAt(thigh, u - 0.04)
				Kit.disc("Band" .. s, c - ax.Unit * 0.025, ax, 2 * q[2] + 0.05, 0.05, a)
			end
			local sc = knee:Lerp(ankle, 0.5)
			Kit.disc("Band" .. s, sc - (ankle - knee).Unit * 0.025, ankle - knee, 0.27, 0.05, a)
		else
			Kit.tube("Thigh" .. s, { hip, knee }, { 0.25, 0.16 }, b)
			Kit.disc("Band" .. s, hip:Lerp(knee, 0.6), knee - hip, 0.44, 0.05, a)
		end
		limb("Shin" .. s, { knee, ankle }, { 0.13, 0.09 }, b, 1.3)
		local toe0 = V(side * 0.82, 0.07, -0.12)
		limb("Foot" .. s, { ankle + V(0, -0.04, 0), toe0 }, { 0.08, 0.07 }, b)
		if F then
			local tips: { Vector3 } = {}
			for i, yaw in { -12, 8, 28, 50 } do
				local len = ({ 0.2, 0.27, 0.25, 0.18 })[i]
				local tip = toe0 + V(0, -0.01, 0) + dir(side * yaw, 0) * len
				tips[i] = tip
				Kit.rod("Toe" .. s, toe0, tip, 0.055, b)
				Kit.ball("ToePad" .. s, tip, 0.11, a)
			end
			for i = 1, 3 do
				local p, q = toe0:Lerp(tips[i], 0.78), toe0:Lerp(tips[i + 1], 0.78)
				Kit.blade("Web" .. s, (p + q) / 2 + V(0, -0.02, 0), toe0 + V(0, -0.02, 0), (p - q).Magnitude, 0.05, UP, b)
			end
		else
			Kit.ball("Toes" .. s, toe0 + V(side * 0.06, -0.02, 0.1), 0.2, a)
		end
	end
	return t
end

------------------------------------------------------------------ the jellyfish
-- a jellyfish: a round bell that flares at its margin, a frilled edge of big and small scallops with a fringe of fine
-- tentacles under it, four rings showing through its top, glowing freckles, a face; six tendrils in two segments (the
-- front three ruffled ribbons in the accent, the back three thin and wavy)
PLANS.jelly = function(b, a)
	local t = Kit.new("jelly", 2.6, 1, "fly")
	local F = full()
	J("body", nil, V(0, 1.5, 0), "body")
	local C = V(0, 1.84, 0)
	local BR = 0.78
	Kit.ball("Bell", C, 2 * BR, b)
	local nm = if F then 10 else 7
	for i = 0, nm - 1 do
		local ang = (i + 0.5) / nm * 2 * math.pi
		Kit.ball("Margin", V(math.sin(ang) * 0.64, 1.42, math.cos(ang) * 0.64), 0.48, b)
	end
	-- the frilled edge: big scallops and small ones between them, a little lower (full); the fringe hangs from the
	-- small ones
	local ns = if F then 16 else 10
	for i = 0, ns - 1 do
		local ang = i / ns * 2 * math.pi
		local small = F and i % 2 == 1
		local r = if small then 0.82 else 0.8
		Kit.ball("Scallop", V(math.sin(ang) * r, if small then 1.2 else 1.23, math.cos(ang) * r), if not F then 0.3 elseif small then 0.17 else 0.26, a)
		if small then
			local p0 = V(math.sin(ang) * 0.8, 1.14, math.cos(ang) * 0.8)
			local sway = V(math.cos(ang), 0, -math.sin(ang)) * (if i % 4 == 1 then 0.05 else -0.05)
			Kit.rod("Fringe", p0, p0 + V(0, -0.3 - (i % 4) * 0.03, 0) + sway + V(math.sin(ang), 0, math.cos(ang)) * 0.04, 0.05, b)
		end
	end
	for k = 0, 3 do
		local d = dir(45 + 90 * k, 56)
		local p = C + d * BR
		Kit.disc("Ring", p, d, 0.32, 0.05, a, false, BR)
		Kit.disc("RingIn", p + d * 0.02, d, 0.14, 0.05, b, true, BR)
	end
	for i, f in { { 40, 30, 0.1 }, { -36, 38, 0.08 }, { 70, 10, 0.07 }, { -64, 16, 0.09 }, { 10, 70, 0.07 }, { 116, 40, 0.08 }, { -120, 26, 0.07 } } do
		local d = dir(f[1], f[2])
		Kit.disc("Freckle", C + d * BR, d, f[3], 0.05, "white", i > 2, BR, true)
	end
	Kit.eyes(C, BR, FWD, R(22), R(2), 0.3, a)
	local m, mn = Kit.onBall(C, BR, dir(0, -15))
	Kit.mouth(m, mn, 0.2)
	Kit.blush(C, BR, FWD, R(40), R(8), 0.18)
	-- a ruffle on a ribbon: a small round flap standing off it, turned a little each time
	local function ruffle(name: string, at: Vector3, out: Vector3, k: number)
		local n = (out + V(0, 0.5 * (if k % 2 == 0 then 1 else -1), 0)).Unit
		Kit.disc(name, at + out * 0.05, n, 0.17, 0.05, b)
	end
	for i, p in { { -0.5, 0.3 }, { 0, 0.45 }, { 0.5, 0.3 }, { -0.45, -0.35 }, { 0.05, -0.45 }, { 0.5, -0.3 } } do
		local x, z = p[1], p[2]
		local front = i <= 3
		local col = if front then a else b
		local w = if i % 2 == 0 then 0.07 else -0.07
		Kit.on("body")
		J("tendril" .. i, "body", V(x, 1.2, z), "tendril", 0, i)
		local q0, q1, q2 = V(x, 1.3, z), V(x + w, 0.94, z + w * 0.5), V(x, 0.58, z)
		local r0 = if front then 0.09 else 0.06
		if F then
			Kit.tube("Tendril" .. i, { q0, q1, q2 }, { r0, r0 * 0.8 }, col, 1.4)
			if front then
				-- ruffles down both edges of the ribbon
				local side = V(1, 0, 0)
				ruffle("Frill" .. i, q0:Lerp(q1, 0.55), side, 0)
				ruffle("Frill" .. i, q0:Lerp(q1, 0.75), -side, 1)
				ruffle("Frill" .. i, q1:Lerp(q2, 0.25), side, 2)
				ruffle("Frill" .. i, q1:Lerp(q2, 0.55), -side, 3)
			end
		else
			Kit.rod("Tendril" .. i, q0, q2, r0 * 2, col)
		end
		J("tendril" .. i .. "b", "tendril" .. i, V(x, 0.58, z), "tendril", 0, i + 0.5)
		local q3, q4 = V(x - w, 0.36, z), V(x + w * 0.4, 0.16, z + 0.02)
		if F then
			Kit.tube("TendrilEnd" .. i, { q2, q3, q4 }, { r0 * 0.8, r0 * 0.4 }, col, 1.4)
			if front then
				ruffle("Frill" .. i, q2:Lerp(q3, 0.4), V(1, 0, 0), 4)
				ruffle("Frill" .. i, q3:Lerp(q4, 0.2), V(-1, 0, 0), 5)
			end
		else
			Kit.rod("TendrilEnd" .. i, q2, q4, r0 * 1.4, col)
		end
		Kit.ball("TendrilTip" .. i, q4, r0 * 1.3, a, true)
	end
	return t
end

------------------------------------------------------------------ the sprite
-- a sprite: a small round body trailing off into a curl of light, a skirt of petals round its waist (long ones in the
-- accent and short ones of its own colour between them), a glowing gem on its chest; a big round head with a face,
-- pointed ears and a halo of rays with lit tips; two pairs of thin wings, each with a vein of its own colour down its
-- middle and a glowing spot; little arms; sparkles about it
PLANS.sprite = function(b, a)
	local t = Kit.new("sprite", 2.4, 0.9, "fly")
	local F = full()
	J("body", nil, V(0, 1.3, 0), "body")
	local TC = V(0, 1.12, 0)
	Kit.ball("Torso", TC, 0.56, b)
	if F then
		Kit.tube("Wisp", { V(0, 1.0, -0.02), V(0.05, 0.78, -0.06), V(0.0, 0.58, -0.1), V(-0.14, 0.5, -0.06), V(-0.18, 0.6, 0.02) }, { 0.23, 0.16, 0.1, 0.06, 0.03 }, b)
	else
		Kit.tube("Wisp", { V(0, 1.0, -0.02), V(0.03, 0.68, -0.08), V(-0.14, 0.52, -0.06) }, { 0.23, 0.13, 0.05 }, b)
	end
	Kit.ball("Gem", TC + V(0, 0.04, 0.25), 0.14, a, false, true)
	-- the skirt of petals round the waist, pointing down and out like an upside-down flower: long ones in the accent
	-- from under the body's middle, short ones of its own colour between them a little higher
	local np = if F then 6 else 4
	for i = 0, np - 1 do
		local d = dir((i + 0.5) / np * 360, -42)
		local base = TC + V(0, -0.12, 0) + V(d.X, 0, d.Z) * 0.2
		Kit.blade("Petal", base, base + d * 0.42, 0.26, 0.05, (UP + d * 0.4).Unit, a)
		if F then
			local d2 = dir((i + 1) / np * 360, -30)
			local b2 = TC + V(0, -0.04, 0) + V(d2.X, 0, d2.Z) * 0.22
			Kit.blade("PetalIn", b2, b2 + d2 * 0.26, 0.18, 0.05, (UP + d2 * 0.4).Unit, b)
		end
	end
	if F then
		for _, sp in { { c = V(0.66, 1.72, 0.12), l = 0.2 }, { c = V(-0.6, 0.86, 0.22), l = 0.16 } } do
			local c, l = sp.c, sp.l
			Kit.rod("Sparkle", c - V(l / 2, 0, 0), c + V(l / 2, 0, 0), 0.05, "white", true, true)
			Kit.rod("Sparkle", c - V(0, l / 2, 0), c + V(0, l / 2, 0), 0.05, "white", true, true)
		end
		Kit.ball("Glint", V(-0.7, 1.95, -0.1), 0.07, "white", true, true)
		Kit.ball("Glint", V(0.5, 0.62, 0.1), 0.06, "white", true, true)
	end
	-- the head
	J("head", "body", V(0, 1.5, 0), "head")
	local HC = V(0, 1.84, 0.02)
	local HR = 0.44
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.eyes(HC, HR, FWD, R(25), R(2), 0.28, a)
	local m, mn = Kit.onBall(HC, HR, dir(0, -22))
	Kit.mouth(m, mn, 0.2)
	Kit.blush(HC, HR, FWD, R(44), R(16), 0.15)
	for _, side in { -1, 1 } do
		local e0 = HC + dir(side * 82, 6) * (HR - 0.06)
		limb("Ear", { e0, e0 + V(side * 0.26, 0.1, -0.06) }, { 0.1, 0.02 }, b)
	end
	-- a halo of rays round the back of the head, long and short in turn, glowing at the tips
	local back = HC + V(0, 0.02, -0.12)
	local tiltC = CFrame.Angles(R(-14), 0, 0)
	local nray = 7
	for i = 0, nray - 1 do
		local ang = R(-114 + 228 * i / (nray - 1))
		local d = tiltC:VectorToWorldSpace(V(math.sin(ang), math.cos(ang), 0))
		local long = i % 2 == 0
		local tip = back + d * (HR + (if long then 0.24 else 0.14))
		limb("Ray", { back + d * (HR - 0.12), tip }, { if long then 0.14 else 0.12, 0.05 }, a)
		if long then
			Kit.ball("RayTip", tip, 0.08, "white", true, true)
		end
	end
	-- wings and arms
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		J("wing" .. s, "body", V(side * 0.35, 1.45, -0.2), "wing", side)
		local root = V(side * 0.14, 1.3, -0.22)
		local span = V(side, 0, -0.5).Unit
		local upv = V(0, 0.86, -0.5).Unit
		local nrm = span:Cross(upv).Unit
		if nrm.Z < 0 then
			nrm = -nrm
		end
		local up0, up1, up2 = root + span * 0.1 + upv * 0.08, root + span * 0.36 + upv * 0.3, root + span * 0.6 + upv * 0.56
		local f1 = membrane("Wing" .. s, { up0, up1, up2 }, { 0.14, 0.4, 0.3, 0.12 }, nrm, "white", if F then 6 else 3)
		local lo0, lo1, lo2 = root + span * 0.08 - upv * 0.06, root + span * 0.26 - upv * 0.2, root + span * 0.4 - upv * 0.36
		local f2 = membrane("WingLow" .. s, { lo0, lo1, lo2 }, { 0.12, 0.28, 0.2, 0.08 }, nrm, "white", if F then 5 else 2)
		Kit.disc("WingSpot" .. s, up2 - (up2 - up1) * 0.25 + nrm * f1, nrm, 0.1, 0.05, a, true, nil, true)
		Kit.disc("WingSpot" .. s, lo2 - (lo2 - lo1) * 0.3 + nrm * f2, nrm, 0.08, 0.05, a, true, nil, true)
		if F then
			-- a vein of its own colour down the middle of each wing, on its front face
			line("WingVein" .. s, { up0 + nrm * f1, up1 + nrm * f1, up2 - (up2 - up1) * 0.45 + nrm * f1 }, 0.05, b)
			line("WingVein" .. s, { lo0 + nrm * f2, lo1 + nrm * f2, lo2 - (lo2 - lo1) * 0.5 + nrm * f2 }, 0.05, b)
		end
		J("arm" .. s, "body", V(side * 0.26, 1.26, 0.04), "arm", side)
		limb("Arm" .. s, { V(side * 0.24, 1.24, 0.04), V(side * 0.4, 1.06, 0.1), V(side * 0.42, 0.9, 0.18) }, { 0.075, 0.06, 0.055 }, b, 1.4)
		Kit.ball("Hand" .. s, V(side * 0.43, 0.86, 0.2), 0.15, b)
	end
	return t
end

return PLANS
