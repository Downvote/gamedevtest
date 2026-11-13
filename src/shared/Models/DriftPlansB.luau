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

-- Blush on a head of balls.
local function blushOn(balls: { BasePart }, c: Vector3, yaw: number, pitch: number, d: number)
	for _, side in { -1, 1 } do
		local p, n, r = surf(balls, c, dir(side * yaw, pitch))
		Kit.disc("Cheek" .. (if side < 0 then "L" else "R"), p, n, d, 0.05, "pink", false, r)
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
-- a crab: a wide round carapace with small teeth along its front edge and pale spots, eyes on stalks, a smile and
-- blush under them; two big claws held in toward the middle (an upper arm, a wrist with a spine, a fat palm, a fixed
-- finger under and a hinged one over, both toothed on the inside and dark at the tip); three jointed legs a side,
-- dark at their points
PLANS.crab = function(b, a)
	local t = Kit.new("crab", 1.6, 1.2, "scuttle")
	local F = full()
	J("body", nil, V(0, 0.75, 0), "body")
	local SC = V(0, 0.8, -0.04)
	-- (a big ball and one at each side: few big balls shade smooth)
	local shell = {
		Kit.ball("Shell", SC + V(0, 0.02, 0.02), 1.16, b) :: BasePart,
		Kit.ball("Shell", SC + V(-0.46, -0.04, -0.02), 0.82, b) :: BasePart,
		Kit.ball("Shell", SC + V(0.46, -0.04, -0.02), 0.82, b) :: BasePart,
	}
	-- the teeth along the front edge
	for _, side in { -1, 1 } do
		local yaws: { number } = if F then { 34, 52, 70 } else { 40, 66 }
		for _, yaw in yaws do
			local p, n = surf(shell, SC, dir(side * yaw, 4))
			Kit.ball("Tooth", p + n * 0.02, if F then 0.14 else 0.18, b)
		end
	end
	-- spots
	for i, sp in { { 40, 48, 0.2 }, { -46, 42, 0.16 }, { 150, 46, 0.18 }, { -140, 52, 0.14 }, { 100, 30, 0.12 } } do
		local p, n, r = surf(shell, SC, dir(sp[1], sp[2]))
		Kit.disc("Spot", p, n, sp[3], 0.05, "cream", i > 3, r)
	end
	-- the face on the front of the shell
	local m, mn = surf(shell, SC, dir(0, -10))
	Kit.mouth(m + mn * 0.01, mn, 0.2)
	blushOn(shell, SC, 32, -2, 0.18)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local x = side
		Kit.on("body")
		-- an eye on a stalk
		J("stalk" .. s, "body", V(x * 0.28, 1.15, 0.42), "stalk", side)
		local e0, e1 = V(x * 0.22, 1.06, 0.44), V(x * 0.3, 1.46, 0.5)
		if F then
			Kit.tube("Stalk" .. s, { e0, V(x * 0.27, 1.28, 0.49), e1 }, { 0.075, 0.06 }, a, 1.6)
		else
			Kit.rod("Stalk" .. s, e0, e1, 0.13, a)
		end
		local EC = V(x * 0.31, 1.6, 0.52)
		Kit.ball("EyeBulb" .. s, EC, 0.36, b)
		Kit.eye(s, EC, 0.18, dir(x * 14, 6), 0.28, a)
		-- the claw
		J("arm" .. s, "body", V(x * 0.85, 0.82, 0.35), "arm", side)
		local a0, a1, a2 = V(x * 0.7, 0.74, 0.34), V(x * 0.95, 0.8, 0.5), V(x * 1.06, 0.86, 0.68)
		if F then
			Kit.tube("Arm" .. s, { a0, a1, a2 }, { 0.11, 0.1 }, b, 1.4)
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
		blob("Palm" .. s, PC, V(0.24, 0.27, 0.32), b, CFrame.lookAt(Vector3.zero, fw))
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
			local hip = V(x * 0.72, 0.6, z)
			local knee = V(x * 1.06, 0.8, z + fz * 0.6)
			local ankle = V(x * 1.28, 0.42, z + fz * 1.2)
			local tip = V(x * 1.36, 0.03, z + fz * 1.6)
			if F then
				Kit.tube("Leg" .. s .. i, { hip, knee, ankle }, { 0.08, 0.07, 0.055 }, b, 1.6)
				Kit.tube("LegTip" .. s .. i, { ankle, tip }, { 0.055, 0.018 }, a, 2)
			else
				Kit.rod("Leg" .. s .. i, hip, knee, 0.15, b)
				Kit.rod("LegTip" .. s .. i, knee, tip, 0.12, a)
				Kit.ball("Knee" .. s .. i, knee, 0.15, b)
			end
		end
	end
	return t
end

------------------------------------------------------------------ the snail
-- a snail: a long soft foot with a pointed tail and bumps along its back, a shell coiling up to a point (each turn
-- thinner, knobs along the last one's shoulder, a lip round its mouth), a round head with a smile and blush, two short
-- feelers, the eyes on two long stalks
PLANS.snail = function(b, a)
	local t = Kit.new("snail", 2.0, 1.1, "slither")
	local F = full()
	J("body", nil, V(0, 0.3, 0), "body")
	Kit.tube("Foot", { V(0, 0.08, -1.06), V(0, 0.18, -0.68), V(0, 0.24, -0.15), V(0, 0.26, 0.35), V(0, 0.36, 0.72) }, { 0.06, 0.2, 0.3, 0.3, 0.27 }, b)
	if F then
		for i, z in { -0.62, -0.8, -0.94 } do
			Kit.ball("Bump", V(0, 0.3 - i * 0.06, z), 0.08, b)
		end
		for _, q in { V(-0.08, 0.6, 0.62), V(0.09, 0.57, 0.56), V(0, 0.64, 0.7) } do
			Kit.ball("Bump", q, 0.07, b)
		end
	end
	-- the shell: coiling up from its mouth (low at the front) round a spire leaning back, thinner each turn, each turn
	-- sitting on the one below it
	J("shell", "body", V(0, 0.55, -0.25), "shell")
	local lean = R(26)
	local ax = V(0, math.cos(lean), -math.sin(lean))
	local e1 = V(1, 0, 0)
	local e2 = e1:Cross(ax)
	local B0 = V(0, 0.56, -0.3)
	local W, r0, rho0 = 1.9, 0.36, 0.3
	local H = rho0 * (W + 1) / (W - 1) * 0.8 -- (each turn sunk a little into the one below: surfaces just touching flicker)
	local turns = if F then 2.6 else 2.2
	local function coil(u: number): (Vector3, number)
		local g = W ^ -u
		local th = math.pi / 2 + u * 2 * math.pi
		return B0 + ax * (H * (1 - g)) + (e1 * math.cos(th) + e2 * math.sin(th)) * (r0 * g), rho0 * g
	end
	-- (a chain of balls a little apart, as the bakery pipes cream: the dips between them are the shell's growth lines.
	-- A tube bent this sharply shows its links' flat ends on the outside of each bend.)
	local gap = if F then 0.5 else 0.85
	local prev = coil(0)
	local run = 0
	Kit.ball("Shell", prev, 2 * rho0, a)
	for i = 1, 400 do
		local u = turns * i / 400
		local p, r = coil(u)
		run += (p - prev).Magnitude
		prev = p
		if run >= gap * r then
			Kit.ball("Shell", p, 2 * r, a)
			run = 0
		end
	end
	local tip, tr = coil(turns)
	Kit.ball("ShellTip", tip + ax * tr * 0.6, tr * 2.2, a)
	if F then
		-- knobs along the shoulder of the last turn, as a conch has
		for k = 1, 7 do
			local u = 0.12 + k * 0.11
			local p, r = coil(u)
			local th = math.pi / 2 + u * 2 * math.pi
			local outw = e1 * math.cos(th) + e2 * math.sin(th)
			Kit.ball("ShellKnob", p + (outw * 0.62 + ax * 0.78).Unit * r * 0.92, 0.14, a)
		end
		-- the lip round the shell's mouth
		local p0, r0m = coil(0)
		local p1 = coil(0.02)
		local tdir = (p1 - p0).Unit
		local q1 = tdir:Cross(UP).Unit
		local q2 = q1:Cross(tdir).Unit
		for k = 0, 7 do
			local ang = k / 8 * 2 * math.pi
			Kit.ball("ShellLip", p0 + (q1 * math.cos(ang) + q2 * math.sin(ang)) * r0m * 0.92, 0.12, a)
		end
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
		Kit.ball("FeelerTip", f1, 0.09, b, true)
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
-- a turtle: a domed shell with the seams of its plates drawn on it in the body's colour and a scalloped rim, a head
-- on a short neck with puffed cheeks, a round snout, nostrils, a smile and a lower beak that drops, four stumpy legs
-- with scales and claws, a pointed tail
PLANS.turtle = function(b, a)
	local t = Kit.new("turtle", 1.7, 1.2, "quad")
	local F = full()
	J("body", nil, V(0, 0.6, 0), "body")
	local SC = V(0, 0.74, -0.08)
	local SH = V(0.84, 0.48, 0.96)
	local shell = blob("Shell", SC, SH, a)
	-- the rim
	local nr = if F then 18 else 8
	for i = 0, nr - 1 do
		local ang = i / nr * 2 * math.pi
		Kit.ball("Rim", SC + V(math.sin(ang) * SH.X * 0.98, -0.08, math.cos(ang) * SH.Z * 0.98), if F then 0.3 else 0.38, a)
	end
	-- the seams between its plates: a row of plates down the middle, three a side, a ring of small ones round the rim
	-- (points across the shell from above, -1 to 1, laid on its surface)
	local function onTop(u: number, v: number): Vector3
		local y = math.sqrt(math.max(0, 1 - u * u - v * v))
		local p, n = surf(shell, SC, V(u * SH.X, y * SH.Y, v * SH.Z))
		return p + n * 0.03
	end
	-- (in short rods, so none cuts into the shell between its ends)
	local function seam(uv: { number })
		local pts: { Vector3 } = {}
		for i = 1, #uv - 2, 2 do
			local u0, v0, u1, v1 = uv[i], uv[i + 1], uv[i + 2], uv[i + 3]
			local k = math.max(1, math.ceil(math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2) / (if F then 0.3 else 0.45)))
			for j = (if i == 1 then 0 else 1), k do
				table.insert(pts, onTop(u0 + (u1 - u0) * j / k, v0 + (v1 - v0) * j / k))
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
	else
		-- (on the islands the middle row alone)
		for _, x in { -1, 1 } do
			seam({ x * 0.17, 0.8, x * 0.26, 0.3, x * 0.26, -0.3, x * 0.17, -0.8 })
		end
	end
	-- the head
	J("head", "body", V(0, 0.7, 0.95), "head")
	limb("Neck", { V(0, 0.62, 0.6), V(0, 0.74, 0.92), V(0, 0.88, 1.1) }, { 0.21, 0.19 }, b, 1.3)
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
	local m, mn = surf(head, HC, dir(0, -20))
	Kit.mouth(m, mn, 0.24)
	-- the lower beak, a lip round the bottom of the snout that drops when the mouth opens
	J("jaw", "head", V(0, 0.8, 1.16), "jaw")
	local lip: { Vector3 } = {}
	for _, yaw in { -52, -26, 0, 26, 52 } do
		local p, n = surf(head, HC, dir(yaw, -38 + 8 * math.abs(yaw) / 52))
		table.insert(lip, p + n * 0.02)
	end
	if F then
		Kit.tube("Beak", lip, { 0.07, 0.085, 0.07 }, a)
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
		Kit.ball("Foot" .. l.n, foot + V(0, -0.02, 0.05), 0.36, b)
		Kit.toes("Claw" .. l.n, foot + V(0, -0.08, 0.18), 0.22, 0.09, 3, "cream")
		Kit.disc("Scale" .. l.n, mid + V(x * 0.06, 0.04, 0.17), V(x * 0.3, 0.2, 1), 0.1, 0.05, a, true, 0.18)
	end
	J("tail", "body", V(0, 0.5, -1.1), "tail", 0, 1)
	limb("Tail", { V(0, 0.52, -0.95), V(0, 0.44, -1.2), V(0.03, 0.3, -1.38) }, { 0.13, 0.08, 0.03 }, b, 1.3)
	return t
end

------------------------------------------------------------------ the frog
-- a frog: a squat body sloping up to the front with a pale belly, spots and warts; a wide flat head with big eyes on
-- domes, ear discs, nostrils and a mouth from cheek to cheek, a lower jaw with a pale throat that drops open; thin
-- front legs on four splayed fingers with round pads; folded hind legs (a fat thigh, the shin back along it, a long
-- foot) on webbed toes
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
	Kit.ball("MouthIn", V(0, 0.76, 0.48), 0.36, "berry_red")
	J("jaw", "head", V(0, 0.75, 0.3), "jaw")
	if F then
		Kit.tube("Jaw", { V(-0.4, 0.7, 0.28), V(-0.22, 0.66, 0.56), V(0.22, 0.66, 0.56), V(0.4, 0.7, 0.28) }, { 0.13 }, b)
	else
		Kit.rod("Jaw", V(-0.3, 0.67, 0.5), V(0.3, 0.67, 0.5), 0.26, b)
	end
	Kit.ball("Throat", V(0, 0.6, 0.44), 0.42, "cream")
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
				Kit.ball("FingerPad" .. s, tip, 0.1, a)
			end
		else
			Kit.ball("Hand" .. s, wr + V(0, -0.02, 0.05), 0.2, b)
		end
		-- a folded hind leg: the thigh forward, the shin back along it, the long foot forward again on the ground
		J("leg" .. s, "body", V(side * 0.6, 0.45, -0.35), "leg", side, 0)
		local hip, knee, ankle = V(side * 0.36, 0.5, -0.5), V(side * 0.74, 0.42, -0.02), V(side * 0.66, 0.12, -0.5)
		if F then
			Kit.tube("Thigh" .. s, { hip, (hip + knee) / 2 + V(side * 0.05, 0.06, 0), knee }, { 0.26, 0.22, 0.15 }, b, 1.2)
		else
			Kit.tube("Thigh" .. s, { hip, knee }, { 0.25, 0.16 }, b)
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
				Kit.ball("ToePad" .. s, tip, 0.1, a)
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
-- a jellyfish: a round bell that flares at its margin, a scalloped edge, four rings showing through its top, glowing
-- freckles, a face; six tendrils in two segments (the front three frilled arms, the back three thin and wavy)
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
		Kit.ball("Margin", V(math.sin(ang) * 0.6, 1.42, math.cos(ang) * 0.6), 0.44, b)
	end
	local ns = if F then 16 else 10
	for i = 0, ns - 1 do
		local ang = i / ns * 2 * math.pi
		Kit.ball("Scallop", V(math.sin(ang) * 0.74, 1.24, math.cos(ang) * 0.74), if F then 0.24 else 0.3, a)
	end
	for k = 0, 3 do
		local d = dir(45 + 90 * k, 56)
		local p = C + d * BR
		Kit.disc("Ring", p, d, 0.32, 0.05, a, false, BR)
		Kit.disc("RingIn", p + d * 0.02, d, 0.14, 0.05, b, true, BR)
	end
	for i, f in { { 40, 30, 0.1 }, { -36, 38, 0.08 }, { 70, 10, 0.07 }, { -64, 16, 0.09 }, { 10, 70, 0.07 } } do
		local d = dir(f[1], f[2])
		Kit.disc("Freckle", C + d * BR, d, f[3], 0.05, "white", i > 2, BR, true)
	end
	Kit.eyes(C, BR, FWD, R(22), R(2), 0.3, a)
	local m, mn = Kit.onBall(C, BR, dir(0, -15))
	Kit.mouth(m, mn, 0.2)
	Kit.blush(C, BR, FWD, R(40), R(8), 0.18)
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
				Kit.ball("Frill" .. i, q1 + V(-w * 1.2, 0.08, 0), 0.12, b)
				Kit.ball("Frill" .. i, q1 + V(w * 1.2, -0.12, 0.02), 0.11, b)
			end
		else
			Kit.rod("Tendril" .. i, q0, q2, r0 * 2, col)
		end
		J("tendril" .. i .. "b", "tendril" .. i, V(x, 0.58, z), "tendril", 0, i + 0.5)
		local q3, q4 = V(x - w, 0.36, z), V(x + w * 0.4, 0.16, z + 0.02)
		if F then
			Kit.tube("TendrilEnd" .. i, { q2, q3, q4 }, { r0 * 0.8, r0 * 0.4 }, col, 1.4)
			if front then
				Kit.ball("Frill" .. i, q3 + V(w * 1.1, 0.04, 0), 0.1, b)
			end
		else
			Kit.rod("TendrilEnd" .. i, q2, q4, r0 * 1.4, col)
		end
		Kit.ball("TendrilTip" .. i, q4, r0 * 1.3, a, true)
	end
	return t
end

------------------------------------------------------------------ the sprite
-- a sprite: a small round body trailing off into a curl of light, a collar of petals, a glowing gem on its chest; a
-- big round head with a face, pointed ears and a halo of rays with lit tips; two pairs of thin wings with glowing
-- spots; little arms; sparkles about it
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
	Kit.ball("Gem", TC + V(0, 0.02, 0.25), 0.14, a, false, true)
	local np = if F then 6 else 4
	for i = 0, np - 1 do
		local d = dir((i + 0.5) / np * 360, -40)
		local base = V(0, 1.32, 0) + V(d.X, 0, d.Z) * 0.18
		Kit.blade("Petal", base, base + d * 0.34, 0.2, 0.05, UP, a)
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
		J("arm" .. s, "body", V(side * 0.26, 1.26, 0.04), "arm", side)
		limb("Arm" .. s, { V(side * 0.24, 1.24, 0.04), V(side * 0.4, 1.06, 0.1), V(side * 0.42, 0.9, 0.18) }, { 0.075, 0.06, 0.055 }, b, 1.4)
		Kit.ball("Hand" .. s, V(side * 0.43, 0.86, 0.2), 0.15, b)
	end
	return t
end

return PLANS
