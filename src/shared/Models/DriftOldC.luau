--!strict
-- Body plans built with the kit (Models/DriftKit; Models/DriftModels uses them over its old ones): the gull, the owl,
-- the bat, the moth, the drake and the sea serpent. Each returns its Thing; a plan faces +Z with its feet on the ground
-- at y 0. The joints keep the old plans' names, kinds, parents, sides and phases, so every animation still works.
--
-- Flat pieces (feathers, membranes, fins, wings) follow three rules learned from the picture. The creatures are drawn
-- part by part in the order they were made, and a part only covers what is already there when it is 0.03 studs
-- nearer, so two flat parts that touch in one plane leave a dotted line where they meet (the first one's thin edge).
-- So a flat shape is one part where it can be (a wedge is a right triangle, a disc, a block); flat parts that overlap
-- are layered at least 0.08 apart (the top one's edge then reads as a clean line, a feather's edge); and where two
-- must meet in one plane, a rod made before them covers the join (a finger bone, a vein, a feather's shaft, a fin ray).
-- Patterns on a flat part (eye spots, bands) are discs thicker than it, centred on it, made before it: they show on
-- both sides. Thicker by enough once both snap to the fine grid: a disc 0.12 thick snaps to 0.1, and its face then
-- stands only 0.025 off a 0.05 wedge's, too little to cover it (0.15 or more over a 0.05 part).
--
-- The request (2026-11-15): "can you also do the same with creature and egg models?" (after the buildings, the Tree of
-- Life and the palms were rebuilt in much more detail, the bakery's way). Each plan got more of what makes its animal:
-- the moth's wings are fans with veins running out from the root, the bat's and the drake's membranes are notched
-- between the finger tips, the drake and the serpent have rows of flat spikes and the serpent has bands round its
-- coils. What reads at a driftling's size is a clear shape and a pattern in its two colours; rows of tiny feathers or
-- beads in a third colour read as noise, or as a string of pearls, so they are left out. On the islands each plan keeps
-- about its old part count (a spike is one wedge).
local Kit = require(script.Parent.DriftKit)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full

local PLANS: { [string]: (b: string, a: string) -> Kit.Thing } = {}

local UP = V(0, 1, 0)
local FWD = V(0, 0, 1)
-- The picture draws a part over another only where it is more than 0.03 studs nearer: a layer laid on another (a
-- spot on a body, the mouth's tongue on the mouth) stands out by this much more, the way the kit's face parts do.
local LIFT = 0.04

-- A direction from forward: turned `yaw` degrees to the creature's left (-) or right (+) and `pitch` up (+) or down.
local function dir(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(-pitch), 0, 0)):VectorToWorldSpace(FWD)
end

-- x mirrored to a side (-1 or 1)
local function M(side: number, x: number, y: number, z: number): Vector3
	return V(side * x, y, z)
end

local function sideName(side: number): string
	return if side < 0 then "L" else "R"
end

-- One flat right triangle (a single wedge, so no join shows inside it): `sharp` its pointed corner, `corner` the
-- right-angled one, `top` the third (corner -> top is turned square to sharp -> corner).
local function wedge(name: string, sharp: Vector3, corner: Vector3, top: Vector3, th: number, color: string, detail: boolean?): BasePart?
	if detail and not full() then
		return nil
	end
	local z = corner - sharp
	local L = z.Magnitude
	if L < 0.03 then
		return nil
	end
	local zu = z.Unit
	local yv = top - corner
	yv -= zu * yv:Dot(zu)
	local H = yv.Magnitude
	if H < 0.03 then
		return nil
	end
	local yu = yv.Unit
	local Ls, Hs = Kit.fine(L), Kit.fine(H)
	return Kit.part(name, "Wedge", V(th, Hs, Ls), CFrame.fromMatrix(sharp + zu * (Ls / 2) + yu * (Hs / 2), yu:Cross(zu), yu, zu), color)
end

-- A disc centred on `at` facing `n` (a pattern on a flat part: thicker than it, so it shows on both sides).
local function flat(name: string, at: Vector3, n: Vector3, d: number, th: number, color: string, detail: boolean?, neon: boolean?): BasePart?
	if detail and not full() then
		return nil
	end
	return Kit.part(name, "Cylinder", V(th, d, d), Kit.along(at, n), color, neon)
end

-- A pointed feather (or spike, fin lobe): a shaft first (it covers the blade's middle join), then the blade, `w` wide
-- at its base and pointed at its tip, its flat side facing `normal`. `shaft` colours the shaft (the blade's by default).
local function quill(name: string, base: Vector3, tip: Vector3, w: number, normal: Vector3, color: string, shaft: string?, detail: boolean?)
	if detail and not full() then
		return
	end
	if full() then
		local d = tip - base
		Kit.rod(name .. "Shaft", base, base + d * 0.86, 0.08, shaft or color)
	end
	Kit.blade(name, base, tip, w, 0.05, normal, color)
end

-- A row of small balls along the curve through `pts` (a feather edge, a ruff, a bead of scales), `d` across, `n` of
-- them on the full thing and `nw` on the islands' one (0: none there).
local function beads(name: string, pts: { Vector3 }, d: number, color: string, n: number, nw: number)
	local k = if full() then n else nw
	for i = 0, k - 1 do
		local u = if k == 1 then 0.5 else i / (k - 1)
		Kit.ball(name, Kit.curveAt(pts, u), d * (if full() then 1 else 1.25), color)
	end
end

-- An open mouth inside a beak or a snout: a dark disc and a tongue, out only while the mouth is open (a face part the
-- way Kit.mouth makes them).
local function gape(t: Kit.Thing, at: Vector3, n: Vector3, w: number, tongue: string?)
	local up = V(0, 1, 0)
	local nn = n.Unit
	local right = up:Cross(nn)
	right = if right.Magnitude > 1e-4 then right.Unit else V(1, 0, 0)
	local upv = nn:Cross(right).Unit
	local p = Kit.disc("Mouth", at + nn * LIFT, nn, w, 0.05, "black")
	if p then
		t.face[p.Name] = "open"
		Kit.keep(p)
	end
	if full() then
		local q = Kit.disc("MouthTongue", at - upv * w * 0.16 + nn * (2 * LIFT), nn, w * 0.55, 0.05, tongue or "berry_red")
		if q then
			t.face[q.Name] = "open"
			Kit.keep(q)
		end
	end
end

-- A flat triangle a, b, c: two right wedges meeting along the height onto its longest side, a vein (a rod made
-- first, `vein` its colour) covering that join on the full thing.
local function tri(name: string, a: Vector3, b: Vector3, c: Vector3, th: number, color: string, vein: string?)
	local ab, ac, bc = (b - a).Magnitude, (c - a).Magnitude, (c - b).Magnitude
	if ab >= ac and ab >= bc then
		a, c = c, a
	elseif ac >= ab and ac >= bc then
		a, b = b, a
	end
	local u = (c - b).Unit
	local d = b + u * (a - b):Dot(u)
	if vein and full() then
		Kit.rod(name .. "Vein", a, d, 0.07, vein)
	end
	wedge(name, b, d, a, th, color)
	wedge(name, c, d, a, th, color)
end

-- The membrane between two fingers from the wrist `w` (to `tipA` and `tipB`): one right triangle along finger B and
-- across to finger A, which it meets `reach` of the way to A's tip (so the fingers cover both its inner edges and B's
-- tip stands out past its trailing edge, the way a bat's wing scallops between its fingers).
local function web(name: string, w: Vector3, tipA: Vector3, tipB: Vector3, reach: number, color: string)
	local uA, uB = (tipA - w).Unit, (tipB - w).Unit
	local c = math.max(0.2, uA:Dot(uB))
	local p = math.min(reach * (tipA - w).Magnitude * c, 0.94 * (tipB - w).Magnitude)
	wedge(name, w, w + uB * p, w + uA * (p / c), 0.05, color)
end

-- A cone (a spike, a horn's tip, a claw, a tooth): a tube from `base` to `tip`, `r` wide at its base. On the islands
-- (`ball` set) a single ball at its base instead.
local function cone(name: string, base: Vector3, tip: Vector3, r: number, color: string, ball: boolean?)
	if full() or not ball then
		Kit.tube(name, { base, tip }, { r, math.max(0.02, r * 0.18) }, color)
	else
		Kit.ball(name, base + (tip - base) * 0.3, r * 2.2, color)
	end
end

-- A straight thin limb from `a` to `b` (a finger, a toe, a leg, a horn's stalk): a tube narrowing from `r0` to `r1`
-- on the full thing (`step` sets its links: Kit.tube never makes them shorter than 0.3 studs, so a long thin tube is
-- many parts), a single rod on the islands. With `rod` set, a rod with a ball at its end on the full thing too.
local function limb(name: string, a: Vector3, b: Vector3, r0: number, r1: number, color: string, step: number?, rod: boolean?)
	if not full() then
		Kit.rod(name, a, b, r0 + r1, color)
	elseif rod then
		Kit.rod(name, a, b, r0 + r1, color)
		Kit.ball(name, b, 2 * r1 + 0.02, color)
	else
		Kit.tube(name, { a, b }, { r0, r1 }, color, step)
	end
end

-- A curved tube on the full thing, its ends joined by one link on the islands (`step` for the full one).
local function bend(name: string, pts: { Vector3 }, radii: { number }, color: string, step: number?)
	if full() then
		Kit.tube(name, pts, radii, color, step)
	else
		Kit.tube(name, { pts[1], pts[#pts] }, { radii[1], radii[#radii] }, color, 4)
	end
end

-- A dorsal spike (a spine, a scale ridge, a fin's point): one flat right triangle standing on the line from `f0` to
-- `f1` with its point over `f1` at height `h` along `up`, `th` thick so it keeps a pixel side on. One part.
local function spike(name: string, f0: Vector3, f1: Vector3, h: number, up: Vector3, th: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	local zu = (f1 - f0).Unit
	local yv = up - zu * up:Dot(zu)
	yv = if yv.Magnitude > 1e-4 then yv.Unit else V(0, 1, 0)
	wedge(name, f0, f1, f1 + yv * h, th, color)
end

-- A smooth tube along the curve through `pts` that narrows from radii[1] to radii[#radii] (a serpent's body, an ear):
-- links about `link` studs long (twice that on the islands), and at each joint a ball exactly as wide as the thicker
-- link beside it, so the end of that link is capped round. (Kit.tube's joint balls are a little thinner than its
-- links, so where a tube narrows the end of each thicker link shows as a ring.) The balls show a little round each
-- joint, so the edges of the light and shade step along it like rows of scales.
local function smooth(name: string, pts: { Vector3 }, radii: { number }, color: string, link: number)
	local N = 40
	local acc = { 0 }
	local prev = Kit.curveAt(pts, 0)
	for i = 1, N do
		local q = Kit.curveAt(pts, i / N)
		acc[i + 1] = acc[i] + (q - prev).Magnitude
		prev = q
	end
	local total = acc[N + 1]
	local function uAt(l: number): number
		for i = 1, N do
			if acc[i + 1] >= l then
				local seg = acc[i + 1] - acc[i]
				return (i - 1 + (if seg > 0 then (l - acc[i]) / seg else 0)) / N
			end
		end
		return 1
	end
	local function radiusAt(u: number): number
		local k = #radii
		if k == 1 then
			return radii[1]
		end
		local f = math.clamp(u, 0, 1) * (k - 1)
		local i = math.min(math.floor(f), k - 2)
		return radii[i + 1] + (radii[i + 2] - radii[i + 1]) * (f - i)
	end
	local n = math.max(1, math.ceil(total / (link * (if full() then 1 else 2))))
	local q: { Vector3 } = {}
	local r: { number } = {}
	for i = 0, n do
		local u = uAt(total * i / n)
		q[i + 1] = Kit.curveAt(pts, u)
		r[i + 1] = radiusAt(u)
	end
	local dc: { number } = {}
	for i = 1, n do
		dc[i] = Kit.fine(r[i] + r[i + 1])
	end
	-- (the balls first: a part only covers what is drawn before it where it is clearly nearer, so a link's end, flush
	-- with the ball, stays under it)
	for i = 1, n + 1 do
		local d = math.max(dc[i - 1] or 0, dc[i] or 0)
		if i == 1 or i == n + 1 then
			d = math.max(d, Kit.fine(2 * r[i]))
		end
		Kit.part(name, "Ball", V(d, d, d), CFrame.new(q[i]), color)
	end
	for i = 1, n do
		local a, b = q[i], q[i + 1]
		Kit.part(name, "Cylinder", V((b - a).Magnitude, dc[i], dc[i]), Kit.along((a + b) / 2, b - a), color)
	end
end

-- An upright fin (a dorsal fin, a crest, a tail fin): one right triangle from its front foot `f0` back to `f1` and up
-- to `top` over it, with `rays` fin rays (rods made first, `rayColor`) from its foot out past its leading edge.
local function sail(name: string, f0: Vector3, f1: Vector3, top: Vector3, rays: number, color: string, rayColor: string)
	local zu = (f1 - f0).Unit
	local yv = top - f1
	yv -= zu * yv:Dot(zu)
	local tp = f1 + yv
	if full() then
		for i = 1, rays do
			local u = (i - 0.5) / rays
			local b0 = f0:Lerp(f1, 0.1 + u * 0.75)
			local e = b0 + (f0:Lerp(tp, 0.3 + u * 0.7) - b0) * 1.12
			Kit.rod(name .. "Ray", b0, e, 0.07, rayColor)
			Kit.ball(name .. "RayTip", e, 0.09, rayColor)
		end
	end
	wedge(name, f0, f1, tp, 0.05, color)
end

-- A moth's wing as a fan of right triangles from its root (one wedge each, every other one a layer out; the lines
-- between them run straight out from the root, with a vein along each on the full thing the way a moth's veins run). `rays` are the angles of the
-- lines (degrees in the plane of `ex` and `ey`, in order round the wing); each triangle lies between two neighbours
-- with its square corner on the one `sq` names (1: the first of the two, 2: the second) at `reach` from the root, its
-- outer edge square to that line out to the other line, so the outer edge bows out where the reaches grow toward the
-- middle. Made first (patterns on the wing, so they show on both sides): `spots` (discs thicker than the wing, `size`
-- times the wing's mean reach across, centred at `spotAt`: an angle and a share of the reach), the veins (`vein`)
-- and a pale line along the outer edge (`rim`). Returns the spots' centre.
local function fan(name: string, root: Vector3, ex: Vector3, ey: Vector3, rays: { number }, sq: { number }, reach: { number }, color: string, vein: string, spots: { { col: string, size: number } }, spotAt: { number }, rim: string?): Vector3
	local n = ex:Cross(ey).Unit
	local function P(ang: number, dist: number): Vector3
		return root + (ex * math.cos(R(ang)) + ey * math.sin(R(ang))) * dist
	end
	local mean = 0
	for _, d in reach do
		mean += d
	end
	mean /= #reach
	local C = P(spotAt[1], spotAt[2] * mean)
	for i, sp in spots do
		if i == 1 or full() then
			flat(name .. "Spot", C, n, mean * sp.size, 0.12 + 0.07 * (#spots - i + 1), sp.col)
		end
	end
	-- each triangle's square corner and far corner, and how far the wing reaches along each line
	local tris = {}
	local far: { number } = table.create(#rays, 0)
	for k = 1, #rays - 1 do
		local i0, i1 = k, k + 1
		if sq[k] == 2 then
			i0, i1 = i1, i0
		end
		local d = reach[k]
		local d1 = d / math.cos(R(math.abs(rays[i1] - rays[i0])))
		far[i0], far[i1] = math.max(far[i0], d), math.max(far[i1], d1)
		table.insert(tris, { P(rays[i0], d), P(rays[i1], d1) })
	end
	if full() then
		-- (the veins: along every line out from the root, nearly as far as the wing reaches there)
		for k = 1, #rays do
			Kit.rod(name .. "Vein", root, P(rays[k], far[k] * 0.96), 0.07, vein)
		end
		if rim then
			-- (a ball at each end of each stretch, so the corners where the pale edge turns are round)
			for _, tr in tris do
				Kit.rod(name .. "Rim", tr[1], tr[2], 0.08, rim)
				Kit.ball(name .. "Rim", tr[1], 0.1, rim)
				Kit.ball(name .. "Rim", tr[2], 0.1, rim)
			end
		end
	end
	-- (every other one a layer out, so neighbours never touch in one plane and no dotted join shows where no vein
	-- covers it, on the islands)
	for k, tr in tris do
		local o = n * (if k % 2 == 0 then 0.08 else 0)
		wedge(name, root + o, tr[1] + o, tr[2] + o, 0.05, color)
	end
	return C
end

------------------------------------------------------------------ the gull
-- a gull with a fish's fin: a round body tipped up at the chest, a pale breast from the chin down, a mantle in the
-- accent (a gull's grey back); a round head with full cheeks, big eyes, a crest of three plumes, a hooked beak in two
-- parts with a red spot near the tip of the lower part (it opens) and a fish's three gill slits behind each cheek;
-- plump folded wings with a scalloped edge and black pointed primaries with white spots crossing over the tail; a
-- fish's dorsal fin with rays on its back; a forked tail with fin rays under two covert feathers; feathered thighs,
-- thin legs with a knobbly ankle, webbed feet with three toes, claws and a hind toe
PLANS.bird = function(b, a)
	local t = Kit.new("bird", 2.1, 0.9, "biped")
	J("body", nil, V(0, 0.9, 0), "body")
	local BC = V(0, 1.0, -0.06)
	-- the fin first (its leading edge sloping back to an upright trailing edge), then the body it stands on
	local fin0, fin1, finTop = V(0, 1.56, 0.06), V(0, 1.52, -0.66), V(0, 2.16, -0.66)
	sail("Fin", fin0, fin1, finTop, 3, a, "white")
	Kit.ovoid("Body", BC, V(0.6, 0.58, 0.74), b, CFrame.Angles(R(-14), 0, 0))
	-- the chest and the mantle bulge clear of the body
	Kit.ball("Chest", V(0, 0.9, 0.26), 0.98, "cream")
	-- (and up the throat to the chin, so the pale breast runs from the beak to the belly)
	Kit.ball("Throat", V(0, 1.3, 0.38), 0.6, "cream")
	Kit.ball("Mantle", V(0, 1.22, -0.28), 0.9, a)

	-- the head
	J("head", "body", V(0, 1.4, 0.3), "head")
	local HC = V(0, 1.84, 0.4)
	local HR = 0.45
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.ball("Cheek", HC + V(-0.2, -0.17, 0.12), 0.5, b, true)
	Kit.ball("Cheek", HC + V(0.2, -0.17, 0.12), 0.5, b, true)
	-- the crest: three plumes swept back
	for i, c in { { 0, 0.4, 0.14, 0.0, 0.66, -0.38 }, { -0.09, 0.38, 0.06, -0.15, 0.5, -0.46 }, { 0.09, 0.38, 0.06, 0.15, 0.5, -0.46 } } do
		if i == 1 or full() then
			local p0 = HC + V(c[1], c[2], c[3])
			local p2 = HC + V(c[4], c[5], c[6])
			local mid = (p0 + p2) / 2 + V(0, 0.14, 0.02)
			bend("Crest", { p0, mid, p2 }, { 0.075, 0.06, 0.035 }, a, 1.6)
		end
	end
	Kit.eyes(HC, HR, FWD, R(34), R(6), 0.26, a)
	Kit.blush(HC, HR, FWD, R(52), R(16), 0.15)
	-- the fish's gill slits: three short curved strokes behind each cheek
	if full() then
		for _, side in { -1, 1 } do
			for k = 1, 3 do
				local yaw = side * (100 + k * 15)
				local p0 = Kit.onBall(HC, HR + 0.035, dir(yaw, -2 - k * 2))
				local p1 = Kit.onBall(HC, HR + 0.035, dir(yaw + side * 4, -24 - k * 3))
				local p2 = Kit.onBall(HC, HR + 0.035, dir(yaw, -44 - k * 2))
				Kit.rod("Gill", p0, p1, 0.05, a)
				Kit.rod("Gill", p1, p2, 0.05, a)
			end
		end
	end
	-- the upper beak, hooked, with its nostrils; a red inside shows when the lower part drops
	local beak0 = HC + V(0, -0.08, 0.36)
	if full() then
		Kit.tube("Beak", { beak0, HC + V(0, -0.06, 0.7), HC + V(0, -0.1, 0.9), HC + V(0, -0.2, 0.98) }, { 0.13, 0.085, 0.06, 0.045 }, "yellow")
	else
		Kit.tube("Beak", { beak0, HC + V(0, -0.1, 0.92) }, { 0.13, 0.06 }, "yellow", 4)
	end
	if full() then
		for _, side in { -1, 1 } do
			Kit.disc("Nostril", HC + V(side * 0.1, 0.0, 0.6), V(side, 0.5, 0.2), 0.06, 0.05, "black")
		end
	end
	Kit.ball("Gape", HC + V(0, -0.15, 0.42), 0.16, "berry_red")
	J("jaw", "head", V(0, 1.64, 0.82), "jaw")
	-- (the lower half sits well up inside the upper one: two round surfaces that only touch flicker)
	if full() then
		Kit.tube("BeakLow", { HC + V(0, -0.19, 0.42), HC + V(0, -0.17, 0.66), HC + V(0, -0.15, 0.84) }, { 0.085, 0.065, 0.045 }, "yellow")
		for _, side in { -1, 1 } do
			Kit.disc("BeakSpot", HC + V(side * 0.07, -0.19, 0.76), V(side, -0.4, 0), 0.09, 0.05, "berry_red")
		end
	else
		Kit.tube("BeakLow", { HC + V(0, -0.19, 0.42), HC + V(0, -0.15, 0.82) }, { 0.085, 0.05 }, "yellow", 4)
	end

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- a folded wing: black primaries over the tail (made first), the plump wing (the coverts) with its scalloped edge
		J("wing" .. s, "body", M(side, 0.6, 1.35, 0), "wing", side)
		local wn = V(side * 0.75, 0.66, 0).Unit
		for k = 1, (if full() then 3 else 2) do
			local o = (3 - k) * 0.08
			local base = M(side, 0.38, 1.02 - k * 0.05, -0.4 + k * 0.02) + wn * o
			local tip = M(side, 0.08 + k * 0.05, 1.04 - k * 0.07, -1.36 + k * 0.1) + wn * o
			if full() then
				-- (the mirror: a white spot near the tip)
				flat("WingSpot" .. s, tip:Lerp(base, 0.24), wn, 0.12, 0.13, "white")
			end
			quill("Primary" .. s, base, tip, 0.22, wn, "black")
		end
		Kit.tube("Wing" .. s, { M(side, 0.44, 1.2, 0.12), M(side, 0.5, 1.08, -0.25), M(side, 0.44, 0.98, -0.58) }, { 0.27, 0.25, 0.17 }, a)
		beads("WingEdge" .. s, { M(side, 0.6, 0.98, 0.1), M(side, 0.64, 0.88, -0.22), M(side, 0.54, 0.84, -0.54) }, 0.18, a, 6, 0)
		-- the legs: feathered thighs, thin legs, webbed feet
		J("leg" .. s, "body", M(side, 0.25, 0.45, 0.05), "leg", side, if side < 0 then 0 else 0.5)
		local ank = M(side, 0.27, 0.08, 0.08)
		local toes = {}
		for i, ang in { -38, 0, 38 } do
			local d = (CFrame.Angles(0, R(ang * side), 0)):VectorToWorldSpace(V(0, 0, 1))
			toes[i] = ank + d * (if i == 2 then 0.3 else 0.25) + V(0, -0.03, 0)
		end
		if full() then
			for i = 1, 3 do
				Kit.ball("Claw" .. s, toes[i] + (toes[i] - ank).Unit * 0.04 + V(0, -0.005, 0), 0.07, "black")
				Kit.rod("Toe" .. s, ank, toes[i], 0.09, "orange")
			end
			-- the webs between the toes: one right triangle each, along a toe and recessed from the tips
			for i = 1, 2 do
				local c = ank + V(0, -0.025, 0)
				local p = c + (toes[i] + V(0, -0.025, 0) - c) * 0.8
				local q = c + (toes[i + 1] + V(0, -0.025, 0) - c) * 0.8
				wedge("Web" .. s, c, p, q, 0.05, "orange")
			end
			Kit.ball("HindToe" .. s, ank + V(0, -0.02, -0.08), 0.08, "orange")
			Kit.ball("Ankle" .. s, ank + V(0, 0.04, 0), 0.13, "orange")
		else
			for i = 1, 3, 2 do
				Kit.rod("Toe" .. s, ank, toes[i], 0.1, "orange")
			end
		end
		bend("Leg" .. s, { M(side, 0.26, 0.46, 0.04), M(side, 0.27, 0.27, 0.07), ank }, { 0.06, 0.055, 0.05 }, "orange")
		Kit.ball("Thigh" .. s, M(side, 0.27, 0.5, 0.02), 0.34, b)
		Kit.tuft("Trouser" .. s, M(side, 0.28, 0.4, 0.06), 0.1, b, 4, true)
	end

	-- the tail: a stub, two covert feathers over it and a fork of two lobes with fin rays
	J("tail", "body", V(0, 0.95, -0.7), "tail", 0, 1)
	local tb = V(0, 0.9, -0.84)
	for _, side in { -1, 1 } do
		-- a lobe: a right triangle, its inner edge from the base to the tip, its base edge square to that and out
		-- into the body (the right lobe a layer above the left where they cross)
		local lift = V(0, if side > 0 then 0.08 else 0, 0)
		local tip = M(side, 0.36, 0.98, -1.42)
		local inner = (tip - tb).Unit
		local perp = V(side * math.abs(inner.Z), 0, math.abs(inner.X)).Unit
		local top = tb + lift + perp * 0.34
		if full() then
			for _, u in { 0.3, 0.62 } do
				local e = tip:Lerp(top, u)
				Kit.rod("TailRay", tb + lift + V(0, 0, -0.04), tb + lift + (e - tb - lift) * 0.92, 0.06, "white")
			end
		end
		wedge("TailLobe", tip, tb + lift, top, 0.05, a)
	end
	if full() then
		for _, side in { -1, 1 } do
			local up = V(side * 0.25, 1, 0.15).Unit
			local o = up * (if side > 0 then 0.08 else 0)
			Kit.blade("TailCovert", M(side, 0.06, 1.2, -0.66) + o, M(side, 0.16, 1.07, -1.12) + o, 0.2, 0.05, up, a)
		end
	end
	Kit.tube("TailBase", { V(0, 0.98, -0.6), V(0, 0.92, -0.9) }, { 0.2, 0.15 }, b)
	return t
end

------------------------------------------------------------------ the owl
-- an owl: an upright egg of a body with a pale breast barred with four rows of chevrons; a broad head with two round
-- facial discs, each ringed with a rim of feathers, big eyes, fluff at the back of the cheeks, a small hooked beak and
-- ear tufts (a plume with a pointed feather either side); pale spots on the crown; folded wings with rows of pale
-- spots, a scalloped edge and rounded primaries; a short rounded tail; fluffy feathered legs and three orange toes with
-- black talons
PLANS.owl = function(b, a)
	local t = Kit.new("owl", 2.3, 0.9, "biped")
	J("body", nil, V(0, 0.8, 0), "body")
	local BC = V(0, 0.92, -0.02)
	-- the chevrons first (strokes just clear of the breast), then the breast and the body
	local belC, belR = V(0, 0.84, 0.2), 0.5
	if full() then
		for row = 0, 3 do
			local n = if row % 2 == 0 then 3 else 2
			for i = 1, n do
				local yaw = (i - (n + 1) / 2) * 26
				local pitch = 14 - row * 19
				local tip = belC + dir(yaw, pitch - 7) * (belR + 0.035)
				for _, sx in { -1, 1 } do
					Kit.rod("Chevron", belC + dir(yaw + sx * 9, pitch) * (belR + 0.035), tip, 0.06, a)
				end
			end
		end
	end
	Kit.ball("Breast", belC, 2 * belR, "cream")
	Kit.ovoid("Body", BC, V(0.62, 0.68, 0.58), b)
	Kit.tuft("Ruff", V(0, 1.36, 0.36), 0.13, "cream", nil, true)
	-- pale spots across the back
	for i, c in { { 160, 30 }, { 200, 30 }, { 180, 10 }, { 145, 5 }, { 215, 5 }, { 180, 45 } } do
		local at, n = Kit.onBall(BC, 0.575 + LIFT, dir(c[1], c[2]))
		Kit.disc("BackSpot", at, n, if i <= 3 then 0.12 else 0.1, 0.05, "cream", i > 3, 0.575 + LIFT)
	end

	-- the head
	J("head", "body", V(0, 1.45, 0), "head")
	local HC = V(0, 1.88, 0.04)
	Kit.ovoid("Head", HC, V(0.66, 0.55, 0.57), b)
	local HB = 0.55 -- (the head's two balls: radius, snapped, and x)
	local HX = 0.11
	-- pale spots on the crown
	for i, c in { { -30, 62 }, { 10, 70 }, { 40, 58 }, { -60, 40 }, { 70, 38 } } do
		local d = dir(c[1], c[2])
		local ctr = HC + V(if c[1] < 0 then -HX else HX, 0, 0)
		local at, n = Kit.onBall(ctr, HB + LIFT, d)
		Kit.disc("CrownSpot", at, n, if i <= 3 then 0.1 else 0.08, 0.05, "cream", true, HB + LIFT)
	end
	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- a facial disc: a pale ball bulging from the head, a rim of feathers where it meets it, the eye on it
		local hb = HC + V(side * HX, 0, 0)
		local dd = dir(side * 22, 2)
		local rF = 0.32
		local Fc = hb + dd * (HB - rF + 0.1)
		local cdist = (Fc - hb).Magnitude
		local xr = (cdist * cdist + HB * HB - rF * rF) / (2 * cdist)
		local rr = math.sqrt(HB * HB - xr * xr) + 0.03
		local rc = hb + dd * xr
		local e1 = dd:Cross(UP).Unit
		local e2 = e1:Cross(dd).Unit
		-- (the rim: overlapping balls round the outer three quarters, where the two discs do not meet)
		local nRing = if full() then 16 else 8
		for i = 0, nRing - 1 do
			local ang = i / nRing * 2 * math.pi
			local off = e1 * math.cos(ang) + e2 * math.sin(ang)
			if off:Dot(V(side, 0, 0)) > -0.5 or off.Y > 0.6 then
				Kit.ball("Rim" .. s, rc + off * rr, if full() then 0.14 else 0.17, a)
			end
		end
		Kit.ball("Disc" .. s, Fc, 2 * rF, "cream")
		Kit.eye(s, Fc, rF, dd, 0.3, "yellow")
		-- fluff sticking out at the back of the cheek
		Kit.tuft("CheekFluff" .. s, HC + M(side, 0.6, -0.26, -0.1), 0.1, b, 4, true)
		local ca, cn = Kit.onBall(Fc, rF + LIFT, dir(side * 40, -30))
		Kit.disc("Cheek" .. s, ca, cn, 0.14, 0.05, "pink", false, rF + LIFT)
	end
	-- the beak, hooked, and the mouth under it
	if full() then
		Kit.tube("Beak", { HC + V(0, 0.0, 0.52), HC + V(0, -0.13, 0.7), HC + V(0, -0.26, 0.68) }, { 0.09, 0.06, 0.03 }, "orange")
	else
		Kit.tube("Beak", { HC + V(0, 0.0, 0.52), HC + V(0, -0.2, 0.7) }, { 0.09, 0.04 }, "orange", 4)
	end
	local ma, mn = Kit.onBall(HC, HB, dir(0, -34))
	gape(t, ma, mn, 0.14)

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- the ear tufts: a plume with a pointed feather either side
		J("ear" .. s, "head", M(side, 0.4, 2.25, 0), "ear", side)
		-- (two pointed feathers of the accent's either side of the plume, facing forward and a little in)
		local tf = V(side * -0.3, 0.1, 1).Unit
		quill("TuftFeather" .. s, M(side, 0.28, 2.22, 0.12), M(side, 0.42, 2.64, 0.1), 0.17, tf, a, a, true)
		quill("TuftFeather" .. s, M(side, 0.46, 2.18, -0.12), M(side, 0.8, 2.48, -0.22), 0.17, tf, a, a, true)
		bend("Tuft" .. s, { M(side, 0.36, 2.2, 0.0), M(side, 0.5, 2.5, -0.04), M(side, 0.64, 2.72, -0.12) }, { 0.15, 0.1, 0.035 }, b, 1.5)
	end

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- a folded wing: rounded primaries at its lower end (layered), the wing, its spots and scalloped edge
		J("wing" .. s, "body", M(side, 0.6, 1.35, 0), "wing", side)
		local pn = V(side * 0.9, -0.1, -0.42).Unit
		for k = 1, (if full() then 3 else 2) do
			Kit.part("Primary" .. s, "Cylinder", V(0.05, 0.3, 0.3), Kit.along(M(side, 0.5, 0.64 - k * 0.09, -0.24 - k * 0.07) - pn * ((k - 1) * 0.08), pn), a)
		end
		local w0, w1, w2 = M(side, 0.5, 1.34, 0.02), M(side, 0.57, 0.98, -0.1), M(side, 0.5, 0.62, -0.2)
		if full() then
			-- (the spots: discs just clear of the wing, made first)
			for i, u in { 0.22, 0.42, 0.62, 0.32, 0.52 } do
				local c = Kit.curveAt({ w0, w1, w2 }, u)
				local n = V(side, if i <= 3 then 0.25 else -0.3, if i <= 3 then 0.2 else -0.1).Unit
				Kit.disc("WingSpot" .. s, c + n * 0.29, n, 0.1, 0.05, "cream", false, 0.29)
			end
		end
		Kit.tube("Wing" .. s, { w0, w1, w2 }, { 0.27, 0.27, 0.18 }, a)
		beads("WingEdge" .. s, { M(side, 0.6, 1.18, -0.2), M(side, 0.6, 0.92, -0.3), M(side, 0.5, 0.66, -0.36) }, 0.17, a, 5, 0)
		-- the legs: feathered, three toes with talons
		J("leg" .. s, "body", M(side, 0.3, 0.3, 0.1), "leg", side, if side < 0 then 0 else 0.5)
		local ank = M(side, 0.27, 0.09, 0.2)
		for i, ang in { -32, 0, 32 } do
			if full() or i ~= 2 then
				local d = (CFrame.Angles(0, R(ang * side), 0)):VectorToWorldSpace(V(0, 0, 1))
				local tip = ank + d * 0.2 + V(0, -0.03, 0)
				Kit.ball("Talon" .. s, tip + d * 0.04 + V(0, -0.01, 0), 0.08, "black", true)
				Kit.rod("Toe" .. s, ank, tip, 0.1, "orange")
			end
		end
		Kit.ball("HindToe" .. s, ank + V(0, -0.03, -0.1), 0.09, "orange", true)
		Kit.ball("Leg" .. s, M(side, 0.27, 0.28, 0.12), 0.38, "cream")
		Kit.tuft("LegFluff" .. s, M(side, 0.28, 0.2, 0.2), 0.1, "cream", 4, true)
	end

	-- a short rounded tail under the wings (layered feathers, the middle one on top)
	J("tail", "body", V(0, 0.5, -0.55), "tail", 0, 1)
	local tn = V(0, 0.45, -1).Unit
	local tx: { number } = if full() then { 0, -0.16, 0.16 } else { 0 }
	for i, x in tx do
		Kit.part("Tail", "Cylinder", V(0.05, 0.32, 0.32), Kit.along(V(x, 0.42 - math.abs(x) * 0.3, -0.66) - tn * ((i - 1) * 0.08), tn), a)
	end
	return t
end

------------------------------------------------------------------ the bat
-- a bat: a round furry body with a pale chest, a collar of fluff and tufts at the shoulders; a round head with puffed
-- cheeks, a muzzle with a pink nose, a nose leaf and nostrils, big eyes, a smile with two fangs over a chin that
-- drops, huge pointed ears pink inside with a tragus standing in each, a tuft on top; wings of bone and membrane: an
-- arm to the wrist with a thumb claw, three knuckled fingers fanning from it, the membrane in panels between them,
-- each notched between the finger tips, veins where its panels meet; little legs with clawed toes
PLANS.bat = function(b, a)
	local t = Kit.new("bat", 2.4, 1.3, "fly")
	J("body", nil, V(0, 1.3, 0), "body")
	Kit.ovoid("Body", V(0, 1.28, -0.02), V(0.46, 0.52, 0.42), b)
	Kit.ball("Chest", V(0, 1.22, 0.2), 0.62, "cream")
	-- fur tufts at the shoulders, where the wings meet the body
	for _, side in { -1, 1 } do
		Kit.tuft("Shoulder", M(side, 0.33, 1.56, 0.0), 0.09, b, 4, true)
	end
	local nRuff = if full() then 9 else 5
	for i = 0, nRuff - 1 do
		local ang = (i / (nRuff - 1) - 0.5) * math.pi * 1.3
		Kit.ball("Ruff", V(math.sin(ang) * 0.34, 1.58 - math.abs(math.sin(ang)) * 0.04, 0.04 + math.cos(ang) * 0.28), if full() then 0.24 else 0.3, "cream")
	end

	-- the head
	J("head", "body", V(0, 1.55, 0.1), "head")
	local HC = V(0, 1.92, 0.12)
	local HR = 0.425
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.ball("Cheek", HC + V(-0.22, -0.2, 0.1), 0.42, b)
	Kit.ball("Cheek", HC + V(0.22, -0.2, 0.1), 0.42, b)
	Kit.tuft("Tuft", HC + V(0, 0.4, -0.02), 0.12, b, nil, true)
	local MZ = HC + V(0, -0.12, 0.34)
	Kit.ball("Muzzle", MZ, 0.35, b)
	Kit.ball("Nose", MZ + V(0, 0.06, 0.16), 0.14, "pink")
	-- the nose leaf: a small pointed flap standing up over the nose
	if full() then
		Kit.blade("NoseLeaf", MZ + V(0, 0.1, 0.17), MZ + V(0, 0.26, 0.13), 0.13, 0.05, V(0, 0.15, 1), "pink")
	end
	if full() then
		for _, side in { -1, 1 } do
			Kit.disc("Nostril", MZ + V(side * 0.03, 0.06, 0.25), V(side * 0.3, 0.1, 1), 0.04, 0.05, "black")
		end
	end
	Kit.eyes(HC, HR, FWD, R(30), R(12), 0.26, a)
	Kit.blush(HC, HR, FWD, R(50), R(16), 0.15)
	local ma, mn = Kit.onBall(MZ, 0.175, V(0, -0.5, 0.87))
	Kit.mouth(ma, mn, 0.16)
	for _, side in { -1, 1 } do
		if full() then
			cone("Fang", MZ + V(side * 0.055, -0.1, 0.12), MZ + V(side * 0.06, -0.2, 0.13), 0.035, "white")
		end
	end
	J("jaw", "head", V(0, 1.66, 0.35), "jaw")
	Kit.ball("Chin", MZ + V(0, -0.14, 0.02), 0.24, b)

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- an ear: a tall cone, pink inside
		J("ear" .. s, "head", M(side, 0.25, 2.15, 0.05), "ear", side)
		-- (many short links: a tube that narrows fast steps down at each joint)
		-- (the inside first: a pink blade lying just clear of the ear's front, a ridge down its middle)
		local e0, e2 = M(side, 0.22, 2.16, 0.06), M(side, 0.42, 2.8, -0.02)
		local front = V(side * 0.25, -0.12, 1).Unit
		local in0, in1 = e0 + V(0, 0.08, 0) + front * 0.21, e0:Lerp(e2, 0.86) + front * 0.07
		if full() then
			Kit.rod("EarRidge" .. s, in0, in0:Lerp(in1, 0.8), 0.07, "pink")
		end
		Kit.blade("EarIn" .. s, in0, in1, 0.27, 0.05, front, "pink")
		-- the tragus: a little pointed flap standing in front of the ear's opening
		if full() then
			local tg0 = e0 + front * 0.24 + V(0, 0.02, 0)
			Kit.blade("Tragus" .. s, tg0, tg0 + V(-side * 0.02, 0.2, 0.02), 0.1, 0.05, front, b)
		end
		if full() then
			smooth("Ear" .. s, { e0, M(side, 0.33, 2.48, 0.03), e2 }, { 0.19, 0.12, 0.03 }, b, 0.17)
		else
			Kit.tube("Ear" .. s, { e0, e2 }, { 0.19, 0.04 }, b, 4)
		end

		-- the wing: arm, membrane panels, fingers
		J("wing" .. s, "body", M(side, 0.45, 1.45, -0.05), "wing", side)
		local z = -0.06
		local S, E, W = M(side, 0.34, 1.52, z), M(side, 0.82, 1.64, z), M(side, 1.32, 1.66, z)
		local H = M(side, 0.3, 1.0, z)
		local T3, T4, T5 = M(side, 2.2, 1.95, z), M(side, 2.02, 1.2, z), M(side, 1.52, 0.86, z)
		if full() then
			Kit.tube("Arm" .. s, { S, E, W }, { 0.1, 0.075, 0.065 }, b, 1.8)
		else
			Kit.rod("Arm" .. s, S, W, 0.16, b)
		end
		if full() then
			Kit.rod("Vein" .. s, H, W, 0.07, b)
		end
		local u5 = (T5 - W).Unit
		local P5 = W + u5 * (H - W):Dot(u5)
		wedge("Membrane" .. s, H, P5, W, 0.05, a)
		tri("Membrane" .. s, W, H, S, 0.05, a, b)
		J("wing" .. s .. "2", "wing" .. s, M(side, 1.35, 1.62, -0.05), "wing", side, 1)
		for _, tp in { T3, T4, T5 } do
			limb("Finger" .. s, W, tp, 0.045, 0.035, b, nil, true)
			-- (a knuckle halfway along)
			Kit.ball("Knuckle" .. s, W:Lerp(tp, 0.5), 0.11, b, true)
		end
		cone("Thumb" .. s, W + V(0, 0.02, 0), W + M(side, 0.04, 0.17, 0.06), 0.05, "cream", true)
		-- (each panel two right triangles, one along each finger, the second a layer behind: their trailing edges
		-- cross in a notch between the finger tips)
		local back = V(0, 0, -0.08)
		web("Membrane" .. s, W, T3, T4, 0.95, a)
		web("Membrane" .. s, W + back, T4 + back, T3 + back, 0.95, a)
		web("Membrane" .. s, W, T4, T5, 0.95, a)
		web("Membrane" .. s, W + back, T5 + back, T4 + back, 0.95, a)

		-- a little leg with clawed toes
		J("leg" .. s, "body", M(side, 0.2, 0.9, 0), "leg", side, if side < 0 then 0 else 0.5)
		limb("Leg" .. s, M(side, 0.18, 0.96, -0.04), M(side, 0.21, 0.76, -0.02), 0.07, 0.055, b, 2)
		for i = -1, 1 do
			Kit.ball("Toe" .. s, M(side, 0.21 + i * 0.05, 0.71, 0.03), 0.08, b, i ~= 0)
			Kit.ball("Claw" .. s, M(side, 0.21 + i * 0.05, 0.66, 0.06), 0.05, "black", true)
		end
	end
	return t
end

------------------------------------------------------------------ the moth
-- a moth: a round fuzzy thorax with a collar of fluff and tufts on its back; a banded abdomen of four rings tapering
-- back to a fuzzy tip; six thin legs bent at the knee; a round head with big eyes, a small smile, blush and a tuft of
-- fuzz; feathery antennae (a curved stalk with seven fine barbs both sides and a club at the tip); two pairs of wings
-- in the accent, each a fan with veins running out from its root and a pale edge: the forewing reaching up and out with
-- an eye spot (a ring, a dark pupil and a shine both sides), the hindwing a rounder fan below and a layer behind with a
-- smaller dark spot
PLANS.moth = function(b, a)
	local t = Kit.new("moth", 2.4, 1.4, "fly")
	J("body", nil, V(0, 1.1, 0), "body")
	Kit.ball("Thorax", V(0, 1.24, 0.06), 0.82, b)
	-- the abdomen, ringed in the two colours, tapering back and down
	local segs = { { c = V(0, 1.0, -0.34), d = 0.64, col = b }, { c = V(0, 0.88, -0.56), d = 0.52, col = a }, { c = V(0, 0.8, -0.74), d = 0.4, col = b }, { c = V(0, 0.75, -0.87), d = 0.24, col = a } }
	for i, sg in segs do
		if i <= 3 or full() then
			Kit.ball("Abdomen", sg.c, sg.d, sg.col)
		end
	end
	-- the collar: a ring of fluff round the front of the thorax, tufts on its back
	local nCol = if full() then 9 else 5
	for i = 0, nCol - 1 do
		local ang = (i / (nCol - 1) - 0.5) * math.pi * 1.25
		Kit.ball("Collar", V(math.sin(ang) * 0.32, 1.5 - math.abs(math.sin(ang)) * 0.06, 0.12 + math.cos(ang) * 0.24), if full() then 0.22 else 0.28, a)
	end
	Kit.tuft("Fuzz", V(0, 1.6, -0.08), 0.12, b, nil, true)
	Kit.tuft("Fuzz", V(0, 1.3, -0.3), 0.11, b, nil, true)
	Kit.tuft("TailFuzz", V(0, 0.72, -0.98), 0.08, a, 4, true)
	-- six thin legs hanging under the thorax, bent at the knee
	if full() then
		for _, side in { -1, 1 } do
			for k = 0, 2 do
				local knee = M(side, 0.3 + k * 0.03, 0.88, 0.26 - k * 0.2)
				Kit.rod("Leg", M(side, 0.14, 0.98, 0.2 - k * 0.16), knee, 0.08, b)
				Kit.rod("Leg", knee, M(side, 0.34 + k * 0.04, 0.62, 0.34 - k * 0.3), 0.06, b)
			end
		end
	end

	-- the head
	J("head", "body", V(0, 1.4, 0.4), "head")
	local HC = V(0, 1.64, 0.5)
	local HR = 0.35
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.tuft("Forelock", HC + V(0, 0.3, -0.02), 0.1, a, nil, true)
	Kit.eyes(HC, HR, FWD, R(30), R(6), 0.26, a)
	Kit.blush(HC, HR, FWD, R(52), R(18), 0.13)
	local ma, mn = Kit.onBall(HC, HR, dir(0, -26))
	Kit.mouth(ma, mn, 0.12)

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- a feathery antenna: barbs both sides of a curved stalk (made first), the stalk, a club at its tip
		J("ant" .. s, "head", M(side, 0.15, 1.9, 0.6), "antenna", side)
		local stalk = { M(side, 0.1, 1.88, 0.62), M(side, 0.24, 2.2, 0.72), M(side, 0.44, 2.42, 0.64) }
		if full() then
			for i = 1, 7 do
				local u = 0.22 + (i - 1) * 0.12
				local p = Kit.curveAt(stalk, u)
				local tg = (Kit.curveAt(stalk, math.min(1, u + 0.03)) - Kit.curveAt(stalk, u - 0.03)).Unit
				local sv = tg:Cross(FWD).Unit
				local L = 0.2 - (i - 1) * 0.022
				for _, k in { -1, 1 } do
					Kit.rod("Barb" .. s, p, p + sv * (k * L) + tg * 0.05, 0.05, a)
				end
			end
		end
		if full() then
			Kit.tube("Ant" .. s, stalk, { 0.035, 0.03, 0.025 }, b)
		else
			Kit.rod("Ant" .. s, stalk[1], stalk[3], 0.07, b)
		end
		Kit.ball("AntTip" .. s, stalk[3], 0.1, a)

		-- the wings, swept back a little, the hindwing a layer behind the forewing: two fans with veins and a pale edge, an
		-- eye spot (a ring, a dark pupil, a shine either side) on the forewing and a dark spot on the hindwing
		J("wing" .. s, "body", M(side, 0.3, 1.35, 0), "wing", side)
		local ex = V(side * math.cos(R(20)), 0, -math.sin(R(20)))
		local ey = V(0, math.cos(R(14)), -math.sin(R(14)))
		local n = ex:Cross(ey).Unit
		local root = M(side, 0.24, 1.44, -0.02)
		-- (the forewing reaching furthest up and out, its outer edge bowing out; the hindwing a rounder fan below)
		local C = fan("Forewing" .. s, root, ex, ey, { 62, 41, 18, -5 }, { 1, 2, 2 }, { 1.32, 1.3, 1.2 }, a, b, { { col = "black", size = 0.26 }, { col = b, size = 0.5 } }, { 36, 0.62 }, "cream")
		if full() then
			for _, k in { -1, 1 } do
				Kit.ball("SpotShine" .. s, C + ey * 0.05 - ex * 0.04 + n * (k * 0.13), 0.06, "white")
			end
		end
		fan("Hindwing" .. s, M(side, 0.22, 1.26, -0.06) - n * 0.1, ex, ey, { -12, -36, -60, -84 }, { 1, 1, 2 }, { 0.8, 0.88, 0.86 }, a, b, { { col = "black", size = 0.3 } }, { -54, 0.55 }, "cream")
	end
	return t
end

------------------------------------------------------------------ the drake
-- a baby dragon on four bent legs: a round body with a row of cream belly plates and spots on its flanks, a row of flat
-- spikes down its back between two dotted stripes; chunky legs with round feet and three cream claws each; a neck with
-- throat plates and a crest of spikes up to a round head with a snout (nostrils on top, two teeth over a smile), big
-- eyes, horns that curve back and taper, fins for ears, a little spike at each cheek and a spike at the back of the
-- head; a lower jaw that drops; wings of bone and membrane (an arm with a thumb claw, three fingers, the membrane
-- notched between them); a tail in two parts with a spike on each, ending in a flat spade
PLANS.drake = function(b, a)
	local t = Kit.new("drake", 2.6, 1.4, "quad")
	J("body", nil, V(0, 0.9, 0), "body")
	local BC = V(0, 0.98, -0.12)
	-- spots on the flanks (discs made first, clear of the body), then the body
	if full() then
		for _, side in { -1, 1 } do
			for _, c in { { 78, 34, 0.15 }, { 104, 14, 0.12 }, { 124, 40, 0.1 } } do
				local at, nn = Kit.onBall(BC, 0.525 + LIFT, dir(side * c[1], c[2]))
				Kit.disc("Spot", at, nn, c[3], 0.05, a, false, 0.525 + LIFT)
			end
			-- and a dotted stripe either side of the spines, one spot on each of the body's three balls
			for _, c in { { 0.24, 0.5, 0.17 }, { 0, 0.525, 0.18 }, { -0.24, 0.5, 0.15 } } do
				local ctr = BC + CFrame.Angles(R(-6), 0, 0):VectorToWorldSpace(V(0, 0, c[1]))
				local at, nn = Kit.onBall(ctr, c[2] + LIFT, dir(side * 90, 60))
				Kit.disc("Stripe", at, nn, c[3], 0.05, a, false, c[2] + LIFT)
			end
		end
	end
	Kit.ovoid("Body", BC, V(0.56, 0.52, 0.76), b, CFrame.Angles(R(-6), 0, 0))
	-- the belly plates: cream pads bulging along its underside
	for i, c in { { 0, 0.9, 0.42, 0.56 }, { 0, 0.68, 0.2, 0.5 }, { 0, 0.6, -0.12, 0.5 }, { 0, 0.62, -0.44, 0.46 } } do
		if full() or i == 1 then
			Kit.ball("Plate", V(c[1], c[2], c[3]), c[4], "cream")
		end
	end
	-- spines down the back: a row of flat spikes leaning back, the biggest over the shoulders (front foot z, its
	-- height on the back, how tall; every other one on the islands)
	for i, c in { { 0.42, 1.33, 0.2 }, { 0.2, 1.4, 0.27 }, { -0.04, 1.42, 0.27 }, { -0.28, 1.39, 0.23 }, { -0.5, 1.3, 0.18 } } do
		if full() or i % 2 == 0 then
			spike("Spine", V(0, c[2], c[1]), V(0, c[2] - 0.02, c[1] - 0.2), c[3], UP, 0.1, a)
		end
	end
	-- four legs: a thigh, the leg, a round foot, claws
	for _, l in { { n = "FL", s = -1, z = 0.4, ph = 0 }, { n = "FR", s = 1, z = 0.4, ph = 0.5 }, { n = "BL", s = -1, z = -0.55, ph = 0.5 }, { n = "BR", s = 1, z = -0.55, ph = 0 } } do
		local side, z = l.s, l.z
		local back = z < 0
		J("leg" .. l.n, "body", V(side * 0.35, 0.7, z), "leg", side, l.ph)
		if full() then
			for k = -1, 1 do
				Kit.ball("Claw" .. l.n, M(side, 0.38 + k * 0.085, 0.06, z + 0.25 - math.abs(k) * 0.03), 0.09, "cream")
			end
		end
		Kit.ball("Foot" .. l.n, M(side, 0.38, 0.13, z + 0.1), 0.32, b)
		if full() then
			-- (a hind leg bends forward at the knee and back at the hock, a foreleg back at the elbow)
			local pts = if back
				then { M(side, 0.36, 0.72, z - 0.02), M(side, 0.38, 0.46, z + 0.1), M(side, 0.39, 0.28, z - 0.03), M(side, 0.38, 0.17, z + 0.08) }
				else { M(side, 0.36, 0.7, z), M(side, 0.38, 0.45, z - 0.04), M(side, 0.39, 0.27, z + 0.03), M(side, 0.38, 0.17, z + 0.08) }
			Kit.tube("Leg" .. l.n, pts, { 0.16, 0.14, 0.12, 0.12 }, b)
		else
			Kit.rod("Leg" .. l.n, M(side, 0.36, 0.7, z), M(side, 0.38, 0.16, z + 0.08), 0.27, b)
		end
		Kit.ball("Thigh" .. l.n, M(side, 0.34, 0.74, z - (if back then 0.04 else 0)), if back then 0.5 else 0.4, b, not back)
	end

	-- the head on its neck
	J("head", "body", V(0, 1.25, 0.6), "head")
	Kit.tube("Neck", if full() then { V(0, 1.1, 0.36), V(0, 1.46, 0.66), V(0, 1.78, 0.86) } else { V(0, 1.1, 0.36), V(0, 1.78, 0.86) }, { 0.28, 0.23, 0.22 }, b)
	-- throat plates down the front of the neck, each bulging a little so the cream band's edges are scalloped
	local neckPts = { V(0, 1.1, 0.36), V(0, 1.46, 0.66), V(0, 1.78, 0.86) }
	for i, u in { 0.1, 0.34, 0.58, 0.82 } do
		if full() or i == 2 then
			local c = Kit.curveAt(neckPts, u)
			local tg = (Kit.curveAt(neckPts, math.min(1, u + 0.03)) - Kit.curveAt(neckPts, math.max(0, u - 0.03))).Unit
			local fr = V(1, 0, 0):Cross(tg).Unit
			Kit.ball("Throat", c + fr * (0.25 - u * 0.05), if full() then 0.24 else 0.3, "cream")
		end
	end
	-- the crest down the back of the neck and head: spikes standing out square to the neck
	if full() then
		for _, c in { { 1.36, 0.4 }, { 1.58, 0.56 } } do
			local nb = V(0, 0.6, -0.8)
			local f0 = V(0, c[1], c[2]) + nb * 0.14
			spike("Crest", f0, f0 + V(0, -0.12, -0.16), 0.16, nb, 0.1, a)
		end
	end
	local HC = V(0, 1.98, 0.98)
	local HR = 0.425
	spike("Crest", HC + V(0, 0.36, -0.12), HC + V(0, 0.28, -0.38), 0.24, V(0, 1, -0.3), 0.1, a)
	Kit.ball("Head", HC, 2 * HR, b)
	local SN1 = HC + V(0, -0.12, 0.62)
	Kit.tube("Snout", { HC + V(0, -0.12, 0.22), SN1 }, { 0.24, 0.2 }, b)
	for _, side in { -1, 1 } do
		local at, nn = Kit.onBall(SN1, 0.2 + LIFT, dir(side * 22, 58))
		Kit.disc("Nostril", at, nn, 0.06, 0.05, "black", true, 0.2 + LIFT)
	end
	Kit.eyes(HC, HR, FWD, R(34), R(16), 0.28, a)
	Kit.blush(HC, HR, FWD, R(54), R(8), 0.15)
	local ma, mn = Kit.onBall(SN1, 0.2, V(0, -0.45, 0.89))
	Kit.mouth(ma, mn, 0.2)
	for _, side in { -1, 1 } do
		local s = sideName(side)
		if full() then
			cone("Tooth", SN1 + M(side, 0.08, -0.13, 0.12), SN1 + M(side, 0.085, -0.23, 0.13), 0.035, "white")
		end
		if full() then
			Kit.tube("Horn" .. s, { HC + M(side, 0.18, 0.28, -0.1), HC + M(side, 0.3, 0.5, -0.3), HC + M(side, 0.32, 0.58, -0.6) }, { 0.1, 0.07, 0.025 }, "cream", 1.4)
		else
			Kit.rod("Horn" .. s, HC + M(side, 0.18, 0.28, -0.1), HC + M(side, 0.31, 0.56, -0.5), 0.14, "cream")
		end
		quill("EarFin" .. s, HC + M(side, 0.34, 0.08, -0.12), HC + M(side, 0.62, 0.2, -0.44), 0.26, V(side, 0.25, 0.45), a, a, true)
		-- a little spike at the back of each cheek, pointing back and out
		spike("CheekSpike", HC + M(side, 0.3, -0.18, 0.02), HC + M(side, 0.36, -0.2, -0.22), 0.13, V(side, -0.4, 0), 0.08, a, true)
	end
	J("jaw", "head", V(0, 1.72, 1.15), "jaw")
	Kit.ball("Tongue", V(0, 1.8, 1.34), 0.14, "berry_red", true)
	Kit.tube("Jaw", { V(0, 1.72, 1.1), V(0, 1.7, 1.52) }, { 0.17, 0.14 }, b)

	for _, side in { -1, 1 } do
		local s = sideName(side)
		-- a wing: the arm, the membrane panels, fingers and a thumb claw
		J("wing" .. s, "body", M(side, 0.4, 1.4, -0.1), "wing", side)
		local z = -0.12
		local S, E, W = M(side, 0.3, 1.4, z), M(side, 0.76, 1.64, z), M(side, 1.22, 1.68, z)
		local H = M(side, 0.3, 1.12, z)
		local T1, T2, T3 = M(side, 1.82, 2.04, z), M(side, 1.78, 1.42, z), M(side, 1.36, 1.14, z)
		if full() then
			Kit.tube("Arm" .. s, { S, E, W }, { 0.11, 0.08, 0.07 }, b, 1.8)
		else
			Kit.rod("Arm" .. s, S, W, 0.17, b)
		end
		if full() then
			Kit.rod("Vein" .. s, H, W, 0.07, b)
		end
		local u3 = (T3 - W).Unit
		wedge("Membrane" .. s, H, W + u3 * (H - W):Dot(u3), W, 0.05, a)
		tri("Membrane" .. s, W, H, S, 0.05, a, b)
		J("wing" .. s .. "2", "wing" .. s, M(side, 1.25, 1.65, -0.1), "wing", side, 1)
		for _, tp in { T1, T2, T3 } do
			limb("Finger" .. s, W, tp, 0.05, 0.035, b, nil, true)
		end
		if full() then
			cone("Thumb" .. s, W + V(0, 0.02, 0), W + M(side, 0.03, 0.18, 0.06), 0.055, "cream")
		end
		web("Membrane" .. s, W, T1, T2, 0.95, a)
		web("Membrane" .. s, W, T2, T3, 0.95, a)
		if full() then
			-- (a second triangle along the other finger, a layer behind: the panel's edge notched between the tips)
			local back = V(0, 0, -0.08)
			web("Membrane" .. s, W + back, T2 + back, T1 + back, 0.95, a)
			web("Membrane" .. s, W + back, T3 + back, T2 + back, 0.95, a)
		end
	end

	-- the tail: two parts with spines, a spade at its end
	J("tail1", "body", V(0, 0.85, -0.9), "tail", 0, 1)
	bend("Tail", { V(0, 0.94, -0.66), V(0, 0.8, -1.1), V(0, 0.68, -1.6) }, { 0.32, 0.24, 0.17 }, b)
	spike("TailSpine", V(0, 1.12, -0.86), V(0, 1.03, -1.06), 0.17, UP, 0.1, a)
	spike("TailSpine", V(0, 0.96, -1.24), V(0, 0.89, -1.42), 0.14, UP, 0.08, a, true)
	J("tail2", "tail1", V(0, 0.7, -1.6), "tail", 0, 2)
	spike("TailSpine", V(0, 0.8, -1.62), V(0, 0.75, -1.8), 0.11, UP, 0.08, a, true)
	if full() then
		Kit.rod("SpadeRib", V(0, 0.56, -2.18), V(0, 0.56, -2.62), 0.08, b)
	end
	for _, side in { -1, 1 } do
		wedge("Spade", V(0, 0.56, -2.66), V(0, 0.56, -2.24), M(side, 0.26, 0.56, -2.24), 0.05, a)
	end
	if full() then
		Kit.tube("TailTip", { V(0, 0.68, -1.58), V(0, 0.6, -1.95), V(0, 0.56, -2.22) }, { 0.17, 0.12, 0.08 }, b)
	else
		Kit.rod("TailTip", V(0, 0.68, -1.58), V(0, 0.56, -2.22), 0.24, b)
	end
	return t
end

------------------------------------------------------------------ the sea serpent
-- a sea serpent: a long smooth body tapering to its tail, arched in a hump with a finned frill on top and pale belly
-- scales under it, spots and a ridge of flat spikes down its back, bands of the accent round its coils and tail; a tail
-- fin with rays; a neck rising in a curve with pale throat scales down its front, a mane of spikes down its back and a
-- swept fin either side of its base; a round head with a snout (nostrils, two teeth over a smile), big eyes, short
-- horns swept back, a finned crest, long whiskers and three gill plumes each side; a pale lower jaw that drops
PLANS.wyrm = function(b, a)
	local t = Kit.new("wyrm", 2.9, 1.6, "slither")
	J("body", nil, V(0, 0.5, -0.6), "body")
	local body = { V(0, 0.42, 0.32), V(-0.42, 0.66, 0.12), V(-0.62, 0.95, -0.22), V(-0.46, 0.66, -0.66), V(0.02, 0.41, -0.95), V(0.56, 0.39, -1.2), V(0.9, 0.38, -1.5) }
	local br = { 0.42, 0.41, 0.4, 0.39, 0.38, 0.37, 0.36 }
	-- spots down the back (discs made first, clear of it)
	if full() then
		for _, u in { 0.08, 0.27, 0.6, 0.76, 0.92 } do
			local p = Kit.curveAt(body, u)
			local r = 0.42 - u * 0.06
			local tg = (Kit.curveAt(body, math.min(1, u + 0.02)) - Kit.curveAt(body, math.max(0, u - 0.02))).Unit
			local up = (UP - tg * UP:Dot(tg)).Unit
			Kit.disc("Spot", p + up * (r + LIFT), up, 0.16, 0.05, a, false, r + LIFT)
		end
	end
	smooth("Body", body, br, b, 0.32)
	-- bands of the accent round the coils, each a short ring a little wider than the body there
	if full() then
		for _, u in { 0.52, 0.66, 0.8, 0.94 } do
			local p = Kit.curveAt(body, u)
			local tg = (Kit.curveAt(body, math.min(1, u + 0.02)) - Kit.curveAt(body, math.max(0, u - 0.02))).Unit
			local d = 2 * (0.42 - u * 0.06) + 0.12
			Kit.part("Band", "Cylinder", V(0.14, d, d), Kit.along(p, tg), a)
		end
	end
	-- a ridge of flat spikes along the top of the coils, the frill standing in for them over the hump (every other
	-- one on the islands)
	for i, u in { 0.05, 0.14, 0.52, 0.62, 0.72, 0.82, 0.92 } do
		if full() or i % 2 == 0 then
			local p0, p1 = Kit.curveAt(body, u), Kit.curveAt(body, u + 0.045)
			local tg = (p1 - p0).Unit
			local up = (UP - tg * UP:Dot(tg)).Unit
			local r = 0.42 - u * 0.06
			spike("Ridge", p0 + up * (r - 0.05), p1 + up * (r - 0.06), 0.26 - u * 0.08, up, 0.1, a)
		end
	end
	-- pale scales under the hump
	for i, u in { 0.24, 0.34, 0.44 } do
		if full() or i == 2 then
			local p = Kit.curveAt(body, u)
			Kit.ball("Belly", p + V(0, -0.27, 0.02), 0.32, a)
		end
	end
	-- the frill on the hump
	J("fin", "body", V(-0.35, 1.05, -0.3), "fin", 0)
	sail("Frill", V(-0.6, 1.3, 0.04), V(-0.6, 1.28, -0.46), V(-0.6, 1.78, -0.46), 3, a, b)

	-- the tail
	J("tail1", "body", V(0.9, 0.45, -1.5), "tail", 0, 1)
	smooth("Tail", { V(0.9, 0.38, -1.5), V(1.12, 0.33, -1.92), V(1.2, 0.3, -2.3) }, { 0.36, 0.31, 0.26 }, b, 0.3)
	if full() then
		local tp, tq = V(1.06, 0.345, -1.8), V(1.15, 0.32, -2.06)
		Kit.part("Band", "Cylinder", V(0.14, 0.76, 0.76), Kit.along((tp + tq) / 2, tq - tp), a)
	end
	spike("Ridge", V(1.0, 0.68, -1.68), V(1.08, 0.64, -1.88), 0.13, UP, 0.08, a, true)
	spike("Ridge", V(1.14, 0.6, -2.04), V(1.18, 0.56, -2.22), 0.11, UP, 0.08, a, true)
	J("tail2", "tail1", V(1.2, 0.3, -2.3), "tail", 0, 2)
	sail("TailFin", V(1.14, 0.42, -2.6), V(0.9, 0.3, -3.06), V(0.9, 0.95, -3.06), 3, a, b)
	smooth("TailTip", { V(1.2, 0.3, -2.3), V(1.14, 0.28, -2.66), V(0.98, 0.26, -2.92) }, { 0.26, 0.19, 0.13 }, b, 0.24)

	-- the neck, pale scales down its front
	J("neck", "body", V(0, 0.9, 0.3), "neck")
	local neck = { V(0, 0.42, 0.32), V(0, 0.98, 0.4), V(0, 1.5, 0.5), V(0, 1.86, 0.66), V(0, 2.02, 0.8) }
	local nr = { 0.42, 0.36, 0.32, 0.3, 0.3 }
	smooth("Neck", neck, nr, b, 0.3)
	-- a mane of spikes down the back of the neck, pointing back
	if full() then
		for _, u in { 0.4, 0.56, 0.72 } do
			local p0, p1 = Kit.curveAt(neck, u + 0.06), Kit.curveAt(neck, u)
			local tg = (p1 - p0).Unit
			local bk = V(1, 0, 0):Cross(tg).Unit
			local r = 0.42 - u * 0.13
			spike("Mane", p0 + bk * (r - 0.05), p1 + bk * (r - 0.05), 0.16, bk, 0.08, a)
		end
	end
	-- fins at the base of the neck, swept back
	for _, side in { -1, 1 } do
		local f0 = M(side, 0.3, 0.86, 0.46)
		if full() then
			Kit.rod("FinRay", f0, f0 + M(side, 0.26, -0.1, -0.34), 0.06, b)
		end
		wedge("PecFin", f0 + M(side, 0.3, -0.16, -0.4), f0, f0 + M(side, 0.06, -0.3, -0.06), 0.05, a)
	end
	for i, u in { 0.16, 0.32, 0.48, 0.64, 0.8 } do
		if full() or i % 2 == 0 then
			local p = Kit.curveAt(neck, u)
			local tg = (Kit.curveAt(neck, u + 0.02) - Kit.curveAt(neck, u - 0.02)).Unit
			local f = V(1, 0, 0):Cross(tg).Unit
			local r = 0.42 - u * 0.13
			Kit.ball("Throat", p + f * (r - 0.1), 0.34, a)
		end
	end

	-- the head
	J("head", "neck", V(0, 2.0, 0.75), "head")
	local HC = V(0, 2.3, 0.92)
	local HR = 0.45
	sail("Crest", HC + V(0, 0.38, 0.12), HC + V(0, 0.3, -0.3), HC + V(0, 0.76, -0.3), 3, a, b)
	Kit.ball("Head", HC, 2 * HR, b)
	local SN1 = HC + V(0, -0.13, 0.64)
	Kit.tube("Snout", { HC + V(0, -0.1, 0.24), SN1 }, { 0.25, 0.2 }, b)
	for _, side in { -1, 1 } do
		local at, nn = Kit.onBall(SN1, 0.2 + LIFT, dir(side * 24, 42))
		Kit.disc("Nostril", at, nn, 0.07, 0.05, "black", false, 0.2 + LIFT)
	end
	Kit.eyes(HC, HR, FWD, R(36), R(16), 0.28, a)
	Kit.blush(HC, HR, FWD, R(56), R(8), 0.15)
	local ma, mn = Kit.onBall(SN1, 0.2, V(0, -0.45, 0.89))
	Kit.mouth(ma, mn, 0.2)
	for _, side in { -1, 1 } do
		local s = sideName(side)
		if full() then
			cone("Tooth", SN1 + M(side, 0.08, -0.14, 0.13), SN1 + M(side, 0.085, -0.24, 0.14), 0.035, "white")
		end
		bend("Horn" .. s, { HC + M(side, 0.2, 0.3, -0.12), HC + M(side, 0.3, 0.48, -0.36), HC + M(side, 0.3, 0.52, -0.58) }, { 0.08, 0.055, 0.02 }, "cream")
		Kit.tube("Barbel" .. s, { SN1 + M(side, 0.17, -0.02, 0.0), SN1 + M(side, 0.36, -0.06, -0.08), SN1 + M(side, 0.56, -0.24, -0.22), SN1 + M(side, 0.64, -0.48, -0.3) }, { 0.035, 0.03, 0.024, 0.018 }, a, nil, true)
		for k, tp in { V(0.6, 0.14, -0.36), V(0.66, -0.06, -0.38), V(0.58, -0.26, -0.32) } do
			if full() or k == 2 then
				limb("Gill" .. s, HC + M(side, 0.34, -0.08, -0.12), HC + M(side, tp.X, tp.Y, tp.Z), 0.065, 0.03, a, 2)
			end
		end
	end
	J("jaw", "head", V(0, 2.0, 1.1), "jaw")
	Kit.ball("Tongue", V(0, 2.08, 1.32), 0.14, "berry_red", true)
	Kit.tube("Jaw", { V(0, 1.96, 1.08), V(0, 1.94, 1.5) }, { 0.17, 0.13 }, a)
	return t
end

return PLANS
