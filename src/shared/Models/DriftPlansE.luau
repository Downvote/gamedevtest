--!strict
-- Body plans sculpted on the smooth solids (Models/DriftAnatomy, Models/DriftKit; GAME_DESIGN 6; the request of
-- 2026-11-15: "can you redo all the creatures and eggs and add alot more extra ones with more variation to them?
-- currently, all of them are modelled using blobs, which is unnatural. reference other models online to see how you
-- should model them"). Each plan returns its Thing, facing +Z with its feet on the ground at y 0; `forms` gives each
-- species of these plans its own variation (Data/Creatures id -> the form its plan reads).
--
-- This module: the sea and the woods' soft ones. The seal (a seal pup, a cloud whale), the fish, the manta ray, the
-- seahorse, the octopus and the squid, the jellyfish, the mushroom folk and the sprites (little fairies). The
-- swimmers use the "fly" gait: they hover and swim through the air.
local Kit = require(script.Parent.DriftKit)
local A = require(script.Parent.DriftAnatomy)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full
local UP, FWD = A.UP, A.FWD
local lerp = A.lerp
local ID = CFrame.identity

type Form = { [string]: any }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

------------------------------------------------------------------ shared helpers
-- A mass lying along Z (a fish's head or body, a whale): `c` the centre of its widest slice, `hx` and `hy` that
-- slice's half width and half height, `front` and `back` how far it reaches forward and back from there.
type Ax = { c: Vector3, hx: number, hy: number, front: number, back: number }

-- The half width and half height of an Ax mass's slice at z.
local function axAt(m: Ax, z: number): (number, number)
	local d = z - m.c.Z
	local L = if d >= 0 then m.front else m.back
	local k = 1 - (d / L) ^ 2
	if k <= 0 then
		return 0, 0
	end
	k = math.sqrt(k)
	return m.hx * k, m.hy * k
end

-- The point on an Ax mass's surface at z, `ang` degrees round from the top toward +X (90 the right side, 180 the
-- belly), and the outward direction there (near enough for spots and fins).
local function axOn(m: Ax, z: number, ang: number): (Vector3, Vector3)
	local hx, hy = axAt(m, z)
	local a = R(ang)
	local p = V(m.c.X + math.sin(a) * hx, m.c.Y + math.cos(a) * hy, z)
	local n = V(math.sin(a) / math.max(hx, 0.05), math.cos(a) / math.max(hy, 0.05), 0)
	return p, if n.Magnitude > 1e-5 then n.Unit else UP
end

-- An egg-bodied Ax mass: an egg lying along Z (its narrow end back), like A.body, returned as an Ax (its equator, its
-- half sizes, its reach either way) for bands and fins.
local function axBody(name: string, c: Vector3, len: number, wide: number, tall: number, split: number, color: string): Ax
	A.body(name, c, FWD, len, wide, tall, split, color)
	local zEq = c.Z - len * (0.5 - split)
	return { c = V(c.X, c.Y, zEq), hx = wide / 2, hy = tall / 2, front = len * (1 - split), back = len * split }
end

-- An ellipsoid lying along Z as an Ax.
local function axEll(name: string, c: Vector3, size: Vector3, color: string, detail: boolean?): Ax
	Kit.ell(name, c, size, color, nil, detail)
	return { c = c, hx = size.X / 2, hy = size.Y / 2, front = size.Z / 2, back = size.Z / 2 }
end

-- The point on an egg (centre c of its box, full size, `split` as Kit.egg, turned by rot) in the direction `d` from
-- its equator's centre, and the outward normal there.
local function eggOn(c: Vector3, size: Vector3, split: number, rot: CFrame, d: Vector3): (Vector3, Vector3)
	local ye = size.Y / 2 - size.Y * split
	local e = c + rot:VectorToWorldSpace(V(0, ye, 0))
	local dl = rot:VectorToObjectSpace(d.Unit)
	local hy = if dl.Y >= 0 then size.Y * split else size.Y * (1 - split)
	return Kit.onEll(e, V(size.X / 2, hy, size.Z / 2), rot, d)
end

-- A band of colour round an Ax mass at z (a clownfish's stripe), about `w` wide, standing `out` proud: a thin slab
-- across the mass a little bigger than its slice there, so only its edge shows, curved with the body.
local function band(name: string, m: Ax, z: number, w: number, out: number, color: string, detail: boolean?)
	local hx, hy = axAt(m, z)
	if hx <= 0 then
		return
	end
	local H = (hx + hy) / 2
	local q = H / (H + out)
	local T = (w / 2) / math.sqrt(math.max(0.05, 1 - q * q))
	Kit.ell(name, V(m.c.X, m.c.Y, z), V(2 * (hx + out), 2 * (hy + out), 2 * T), color, nil, detail)
end

-- A fin: a flattened tapered limb from `a` (radius ra) to `b` (rb), `th` thick, its flat side facing `n`; with `rim`
-- (up close) a thin edge of that colour round it, a step bigger and half as thick, so it shows only at the edge.
local function fin(name: string, a: Vector3, b: Vector3, ra: number, rb: number, c: string, n: Vector3, th: number?, rim: string?, neon: boolean?, detail: boolean?)
	if detail and not full() then
		return
	end
	local Rm = math.max(ra, rb)
	-- (thick enough that the thin rim stays behind its faces: the picture draws a part over another only where it is
	-- more than 0.03 studs nearer)
	local thick = th or (if rim and full() then 0.13 else 0.1)
	if rim and full() then
		local d = (b - a).Unit
		Kit.limb(name .. "Rim", a, b + d * 0.035, ra + 0.035, rb + 0.035, rim, 0.05 / (2 * (Rm + 0.035)), n, nil, neon)
	end
	Kit.limb(name, a, b, ra, rb, c, thick / (2 * Rm), n, nil, neon)
end

-- The face on an ellipsoid head (centre c, half sizes `half`): the species' own eyes (Kit.eyes), then blush.
local function eyesOn(c: Vector3, half: Vector3, spreadA: number, lift: number, d: number, iris: string?, blush: number?, dark: string?)
	Kit.faceOn(c, half)
	local avg = (half.X + half.Y + half.Z) / 3
	Kit.eyes(c, avg, FWD, spreadA, lift, d, iris, dark)
	if blush then
		Kit.blush(c, avg, FWD, spreadA + R(16), R(16), blush)
	end
	Kit.faceOff()
end

-- A mouth on an ellipsoid head, in the direction `dir` from its centre.
local function mouthOn(c: Vector3, half: Vector3, dir: Vector3, w: number, dark: string?, tongue: string?)
	local at, n = Kit.onEll(c, half, ID, dir)
	Kit.mouth(at, n, w, dark, tongue)
end

-- A round marking on a curved surface (a spot, a freckle): a flat ellipsoid centred on the surface point `p` with its
-- thin side along the normal `n`, standing `out` proud, so its edge sinks into the surface instead of lifting off it.
local function dot(name: string, p: Vector3, n: Vector3, d: number, color: string, out: number?, neon: boolean?, detail: boolean?)
	local o = out or 0.045
	Kit.ell(name, p, V(d, 2 * o, d), color, A.lie(n), detail, neon)
end

-- Points spread evenly over a ball (a golden spiral), as unit directions.
local function spread(n: number): { Vector3 }
	local out = {}
	for i = 0, n - 1 do
		local y = 1 - 2 * (i + 0.5) / n
		local r = math.sqrt(1 - y * y)
		local th = i * 2.399963
		table.insert(out, V(math.cos(th) * r, y, math.sin(th) * r))
	end
	return out
end

-- A tiny four-point twinkle (a star mark) at `at` facing `n`, `l` across, lit (up close only).
local function twinkle(name: string, at: Vector3, n: Vector3, l: number, color: string)
	local nn = n.Unit
	local r = UP:Cross(nn)
	r = if r.Magnitude > 1e-4 then r.Unit else V(1, 0, 0)
	local u = nn:Cross(r).Unit
	Kit.rod(name, at - r * l / 2, at + r * l / 2, 0.05, color, true, true)
	Kit.rod(name, at - u * l / 2, at + u * l / 2, 0.05, color, true, true)
end

------------------------------------------------------------------ the seal (and the cloud whale)
-- A seal pup lying on its belly: a plump body tapering from a raised chest to its hips, a pale belly, a big round head
-- with whisker pads, a black nose, whiskers and big eyes, front flippers that paddle (kind "fin": a short arm and a
-- broad paddle with little claws) and the hind flippers fanned out behind like a tail fluke (two "tail" joints).
local function sealPup(b: string, a: string, f: Form): Kit.Thing
	local t = Kit.new("seal", f.h or 1.45, f.r or 1.2, "slither")
	local under: string = f.under or a
	local spotC: string = f.spotC or A.shade(b)
	J("body", nil, V(0, 0.5, 0), "body")
	local _, body = A.body("Body", V(0, 0.44, -0.14), V(0, 0.26, 1).Unit, 1.4, 0.88, 0.72, 0.6, b)
	A.patch("Belly", body, V(0, -1, 0.25), V(0.8, 0.88, 0.7), 0.02, under)
	A.patch("Chest", body, V(0, -0.2, 1), V(0.7, 0.6, 0.64), 0.02, under)
	-- a few soft spots on its back
	for i, q in { { 10, 70, 0.16 }, { -40, 60, 0.13 }, { 150, 55, 0.15 }, { -140, 50, 0.12 }, { 100, 40, 0.1 } } do
		if i <= 3 or full() then
			local d = A.dir(q[1], q[2])
			dot("Spot", A.on(body, d), d, q[3], spotC, 0.04)
		end
	end
	-- the front flippers: flat paddles from the shoulders, out and back along the sides
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local sh = V(side * 0.32, 0.32, 0.3)
		J("fin" .. s, "body", sh, "fin", side)
		local tip = sh + V(side * 0.3, -0.22, -0.06)
		Kit.limb("Flipper" .. s, sh, tip, 0.13, 0.14, b, 0.42, V(side * 0.45, 1, 0).Unit)
		if full() then
			for k = -1, 1 do
				Kit.ell("Claw" .. s, tip + V(side * 0.08, 0.05, k * 0.06), V(0.05, 0.04, 0.05), f.clawC or A.shade(b))
			end
		end
	end
	-- the hips and the hind flippers fanned out behind
	Kit.on("body")
	J("tail1", "body", V(0, 0.3, -0.62), "tail", 0, 1)
	Kit.limb("Hips", V(0, 0.32, -0.58), V(0, 0.22, -0.92), 0.24, 0.13, b)
	J("tail2", "tail1", V(0, 0.22, -0.9), "tail", 0, 2)
	for _, side in { -1, 1 } do
		local r0 = V(side * 0.05, 0.2, -0.92)
		local tip = r0 + V(side * 0.32, -0.02, -0.3)
		Kit.limb("HindFlipper", r0, tip, 0.08, 0.2, b, 0.3, V(-side * 0.25, 1, 0).Unit)
		if full() then
			Kit.limb("FlipperWeb", lerp(r0, tip, 0.35) + UP * 0.05, tip + UP * 0.04 - (tip - r0).Unit * 0.06, 0.03, 0.025, spotC)
		end
	end
	-- the head
	Kit.on("body")
	local h = A.head({
		c = V(0, 0.98, 0.54),
		size = V(0.86, 0.8, 0.78),
		color = b,
		pivot = V(0, 0.78, 0.4),
		muzzle = "cat",
		mlen = 0.18,
		mw = 0.44,
		mc = under,
		nose = "black",
		eye = { R(27), R(14), 0.28 },
		blush = true,
		whiskers = false,
		-- (its own brow spots)
		face = A.more({ brows = false }, f.faceDetail),
	})
	-- short whiskers from the pads
	if full() then
		for _, side in { -1, 1 } do
			for _, ang in { -8, 10 } do
				local base = h.nose + V(side * 0.14, -0.08, -0.06)
				local d = (CFrame.Angles(0, 0, side * R(ang)) * CFrame.Angles(0, side * R(-30), 0)):VectorToWorldSpace(V(side, 0, 0))
				Kit.rod("Whisker", base, base + d * 0.22, 0.05, "white", true)
			end
		end
	end
	-- brow spots over the eyes, and ear holes
	if full() then
		for _, side in { -1, 1 } do
			local p, n = Kit.onEll(h.c, h.half, ID, A.dir(side * 26, 42))
			dot("Brow", p, n, 0.09, spotC, 0.04)
			local q, qn = Kit.onEll(h.c, h.half, ID, A.dir(side * 84, 14))
			dot("EarHole", q, qn, 0.07, "black", 0.04)
		end
	end
	return t
end

-- A cloud whale swimming through the air (gait "fly"): a big blunt head (its own joint) with a long smile and throat
-- grooves on its pale chin, the body tapering behind it to the tail stock and broad flukes (two "tail" joints), long
-- pale flippers (kind "fin"), a blowhole with a little cloud puffing out of it, and stars on its back.
local function cloudWhale(b: string, a: string, f: Form): Kit.Thing
	local cy = 1.15
	local t = Kit.new("seal", f.h or 2.5, f.r or 1.5, "fly")
	local under: string = f.under or a
	J("body", nil, V(0, cy, 0), "body")
	local hz = 0.5
	local hs = V(1.18, 1.06, 1.2)
	local zEq = hz - 0.22
	local bl, bw, bt = 2.1, 1.06, 0.98
	local split = 0.68
	local bc = V(0, cy, zEq + bl * (0.5 - split))
	local body = axBody("Body", bc, bl, bw, bt, split, b)
	Kit.egg("Belly", bc - UP * bt * 0.14, V(bw * 0.86, bl * 0.94, bt * 0.8), split, under, A.lie(-FWD, UP))
	local tailZ = zEq - bl * split
	-- stars on its back
	for i, q in { { -0.12, -14, 0.14 }, { -0.5, 22, 0.12 }, { -0.82, -26, 0.11 }, { -0.3, 50, 0.09 }, { -0.62, -58, 0.09 } } do
		if i <= 3 or full() then
			local p, n = axOn(body, zEq + q[1], q[2])
			dot("Star", p, n, q[3], f.starC or "yellow", 0.045, true)
		end
	end
	-- the flippers
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local root = V(side * bw * 0.4, cy - bt * 0.26, zEq + 0.02)
		J("fin" .. s, "body", root, "fin", side)
		local tip = root + V(side * 0.46, -0.22, -0.36)
		Kit.limb("Flipper" .. s, root, tip, 0.14, 0.07, f.finC or under, 0.36, V(side * 0.4, 1, 0).Unit)
	end
	-- the tail stock and the flukes
	Kit.on("body")
	J("tail1", "body", V(0, cy + 0.02, tailZ + 0.42), "tail", 0, 1)
	local t0, t1 = V(0, cy + 0.02, tailZ + 0.42), V(0, cy + 0.1, tailZ - 0.06)
	Kit.limb("TailStock", t0, t1, 0.24, 0.11, b, 0.8, V(1, 0, 0))
	J("tail2", "tail1", t1, "tail", 0, 2)
	for _, side in { -1, 1 } do
		local tip = t1 + V(side * 0.52, 0.06, -0.24)
		Kit.limb("Fluke", t1 - FWD * 0.02, tip, 0.13, 0.07, b, 0.32, V(0, 1, 0.15).Unit)
		Kit.limb("FlukeTrail", t1 - FWD * 0.12, tip - FWD * 0.04, 0.08, 0.06, b, 0.4, UP)
	end
	-- the head
	Kit.on("body")
	J("head", "body", V(0, cy, hz - 0.3), "head")
	local hc = V(0, cy + 0.02, hz)
	local half = hs / 2
	local head = axEll("Head", hc, hs, b)
	Kit.ell("Chin", hc + V(0, -hs.Y * 0.2, 0.02), V(hs.X * 0.86, hs.Y * 0.62, hs.Z * 0.92), under)
	-- throat grooves on the chin
	if full() then
		for _, x in { -0.18, -0.06, 0.06, 0.18 } do
			local pts = {}
			for _, z in { 0.3, 0.05, -0.2 } do
				local zz = hc.Z + z
				local _hx, hy = axAt(head, zz)
				table.insert(pts, V(x, hc.Y - hy * 0.86 - 0.01, zz))
			end
			Kit.limbs("Groove", pts, { 0.026 }, f.grooveC or "ice", 2)
		end
	end
	local e: { number } = f.eye or { 30, 6, 0.28 }
	eyesOn(hc, half, R(e[1]), R(e[2]), e[3], f.iris, 0.15)
	-- the long smile along each side of the head
	for _, side in { -1, 1 } do
		local pts = {}
		for _, ang in { 8, 30, 52, 70 } do
			local d = A.dir(side * ang, -22 + ang * 0.1)
			local p, n = Kit.onEll(hc, half, ID, d)
			table.insert(pts, p + n * 0.015)
		end
		Kit.limbs("Smile", pts, { 0.03 }, "black", if full() then 3 else 1)
	end
	mouthOn(hc, half, V(0, -0.38, 1), 0.2)
	-- the face's details (A.face), the blowhole on its crown
	A.face({ color = b, c = hc, half = half, under = under, more = A.more({ crown = false }, f.faceDetail) })
	-- the blowhole and its little cloud
	local bh = Kit.onEll(hc, half, ID, V(0, 1, -0.2))
	Kit.ell("Blowhole", bh, V(0.12, 0.06, 0.08), A.shade(b))
	Kit.limbs("Spout", { bh, bh + V(0.02, 0.22, 0.0), bh + V(-0.02, 0.4, 0.02) }, { 0.04, 0.06 }, f.spout or "white", 2)
	local cc = bh + V(0, 0.5, 0.02)
	for i, q in { { 0, 0, 0, 0.3 }, { 0.17, -0.04, 0.02, 0.22 }, { -0.16, -0.04, 0.0, 0.22 }, { 0.04, 0.1, -0.06, 0.2 } } do
		if i <= 3 or full() then
			Kit.ell("Cloud", cc + V(q[1], q[2], q[3]), V(q[4], q[4] * 0.78, q[4] * 0.9), f.spout or "white")
		end
	end
	return t
end

PLANS.seal = function(b, a, form)
	local f: Form = form or {}
	if f.whale then
		return cloudWhale(b, a, f)
	end
	return sealPup(b, a, f)
end

-- Floe: a window-blue seal pup with a white belly and muzzle, soft blue spots, whiskers and big button eyes.
FORMS.floe = {
	under = "white",
}
-- Cloudwhale: a celestial whale of ice blue swimming through the clouds, a white chin with grooves, white flippers, a
-- little cloud puffing from its blowhole and stars on its back.
FORMS.cloudwhale = { style = "whale",
	whale = true,
	under = "white",
	finC = "white",
}
-- Nightwhale (eternal, 2026-11-20): a whale the blue of the night sky swimming between the stars, a grey chin, glowing
-- flippers and glowing marks on its skin.
FORMS.nightwhale = { style = "whale",
	whale = true,
	under = "slate",
	finC = "screen_on",
}

------------------------------------------------------------------ the fish
-- A little fish swimming through the air: a big round head (the chibi part) with the body tapering out behind it to
-- a slim tail stock, a tail fin, a dorsal fin along the back, an anal fin under the tail, two pectoral fins by the
-- gills that paddle (kind "fin"), big eyes and a small mouth. Forms add a pufferfish's spines and lips, a clownfish's
-- bands, an anglerfish's lure and toothy jaw, or long glowing veil fins.
PLANS.fish = function(b, a, form)
	local f: Form = form or {}
	local cy: number = f.cy or 1.1
	local t = Kit.new("fish", f.h or 1.8, f.r or 1.0, "fly")
	local under: string = f.under or A.under(b)
	local finC: string = f.fin or a
	local rim: string? = f.rim
	local glow: boolean = f.glow == true
	local hs: Vector3 = f.head or V(0.84, 0.86, 0.84)
	local hz: number = f.hz or 0.16
	local hc = V(0, cy + 0.02, hz)
	local half = hs / 2
	J("body", nil, V(0, cy, 0), "body")
	-- the body: an egg behind the head, its blunt end inside it, tapering to the tail stock
	local bl: number = f.blen or 1.2
	local bw: number = f.bwide or 0.54
	local bt: number = f.btall or 0.66
	local split = 0.66
	local zEq: number = f.bz or (hz - 0.18)
	local bc = V(0, cy, zEq + bl * (0.5 - split))
	local body = axBody("Body", bc, bl, bw, bt, split, b)
	local tailZ = zEq - bl * split
	-- the belly: a pale keel along the underside
	if under ~= b then
		Kit.egg("Belly", bc - UP * bt * 0.12, V(bw * 0.86, bl * 0.94, bt * 0.84), split, under, A.lie(-FWD, UP))
	end
	-- the dorsal fin along the back, the anal fin under the tail
	local dk: string = f.dorsal or "sail"
	local topY = cy + bt / 2
	if dk == "sail" or dk == "low" then
		-- a sail: the leading edge rising from the back to a rounded peak, the trailing edge falling back to the body
		local k = if dk == "sail" then 1 else 0.6
		local apex = V(0, topY + 0.2 * k, zEq - 0.26)
		fin("Dorsal", V(0, topY - 0.1, zEq + 0.12), apex, 0.12, 0.07, finC, V(1, 0, 0), nil, rim)
		fin("Dorsal", apex, V(0, topY - 0.12, zEq - 0.5), 0.07, 0.12, finC, V(1, 0, 0), nil, rim)
	elseif dk == "veil" then
		local pts = { V(0, topY - 0.06, zEq + 0.06), V(0, topY + 0.16, zEq - 0.2), V(0, topY + 0.24, zEq - 0.55), V(0, topY + 0.14, zEq - 0.9) }
		Kit.limbs("Dorsal", pts, { 0.1, 0.14, 0.1, 0.03 }, finC, if full() then 3 else 4, 0.3, V(1, 0, 0), nil, glow)
	end
	if f.anal ~= false then
		fin("Anal", V(0, cy - bt * 0.4, zEq - 0.3), V(0, cy - bt * 0.5 - 0.12, zEq - 0.52), 0.1, 0.05, finC, V(1, 0, 0), nil, rim, glow)
	end
	-- the tail stock and the tail fin
	J("tail1", "body", V(0, cy, tailZ + 0.3), "tail", 0, 1)
	Kit.limb("TailStock", V(0, cy, tailZ + 0.3), V(0, cy, tailZ + 0.02), 0.15, 0.1, b, 0.62, V(1, 0, 0))
	J("tail2", "tail1", V(0, cy, tailZ + 0.04), "tail", 0, 2)
	local tk: string = f.tail or "fan"
	local tb = V(0, cy, tailZ + 0.04)
	local tl: number = f.tlen or 0.42
	if tk == "fan" then
		-- a rounded fan: three lobes side by side, widening to round ends
		for i, ang in { 32, 0, -32 } do
			local d = V(0, math.sin(R(ang)), -math.cos(R(ang)))
			fin("TailFin", tb, tb + d * tl * (if i == 2 then 0.86 else 1), 0.07, 0.17, finC, V(1, 0, 0), nil, rim, glow)
		end
	elseif tk == "fork" then
		for _, ang in { 38, -34 } do
			local d = V(0, math.sin(R(ang)), -math.cos(R(ang)))
			fin("TailFin", tb, tb + d * tl * 1.15, 0.12, 0.04, finC, V(1, 0, 0), nil, rim, glow)
		end
		fin("TailFin", tb, tb - FWD * tl * 0.4, 0.11, 0.08, finC, V(1, 0, 0), nil, nil, glow)
	elseif tk == "veil" then
		-- long flowing lobes that trail down and back like ribbons
		for _, s in { 1, -1 } do
			local pts = { tb, tb + V(0, s * 0.18, -0.25), tb + V(0, s * 0.22 - 0.12, -0.6), tb + V(0, s * 0.12 - 0.36, -0.9) }
			Kit.limbs("TailVeil", pts, { 0.06, 0.15, 0.12, 0.04 }, finC, if full() then 3 else 4, 0.3, V(1, 0, 0), nil, glow)
		end
	end
	-- the pectoral fins, paddling
	local pl: number = f.plen or 0.3
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local root = V(side * (bw * 0.42), cy - bt * 0.16, zEq - 0.02)
		J("fin" .. s, "body", root, "fin", side)
		local n = V(side * 0.45, 1, 0.1).Unit
		if f.longFins then
			local pts = { root, root + V(side * 0.22, -0.08, -0.12), root + V(side * 0.34, -0.26, -0.36), root + V(side * 0.36, -0.46, -0.52) }
			Kit.limbs("Pectoral" .. s, pts, { 0.05, 0.11, 0.08, 0.03 }, finC, if full() then 3 else 4, 0.3, n, nil, glow)
		else
			fin("Pectoral" .. s, root, root + V(side * pl * 0.8, -pl * 0.42, -pl * 0.62), 0.07, 0.12, finC, n, nil, rim, glow)
		end
	end
	Kit.on("body")
	-- the head
	J("head", "body", V(0, cy, hz - hs.Z * 0.2), "head")
	local head = axEll("Head", hc, hs, b)
	if under ~= b then
		-- a pale chin and throat
		Kit.ell("Chin", hc + V(0, -hs.Y * 0.2, hs.Z * 0.04), V(hs.X * 0.82, hs.Y * 0.62, hs.Z * 0.9), under)
	end
	local e: { number } = f.eye or { 28, 12, 0.28 }
	eyesOn(hc, half, R(e[1]), R(e[2]), e[3], f.iris, f.blush, f.ink)
	-- the gill line: a soft arc behind each eye up close
	if full() and f.gill ~= false then
		for _, side in { -1, 1 } do
			local pts = {}
			for _, ang in { 40, 75, 110, 140 } do
				local p, n = axOn(head, hc.Z - hs.Z * 0.22, side * ang)
				table.insert(pts, p + n * 0.012)
			end
			Kit.limbs("Gill", pts, { 0.03 }, f.gillC or A.shade(b), 2)
		end
	end
	-- forms: what makes each fish its own
	if f.bands then
		-- a clownfish's bands, each a white stripe edged in black (the first on the head, the rest on the body)
		for i, z in f.bands :: { number } do
			local w = if i == 1 then 0.2 else 0.17
			local m = if i == 1 then head else body
			Kit.on(if i == 1 then "head" else "body")
			if f.bandEdge then
				band("BandEdge", m, z, w + 0.07, 0.025, f.bandEdge, true)
			end
			band("Band", m, z, w, 0.065, f.bandC or "white")
		end
		Kit.on("head")
	end
	if f.spines then
		-- a pufferfish's short spines all over, out of the face and off the belly; fewer, bigger ones on the islands
		local dirs = spread(if full() then 46 else 16)
		for _, d in dirs do
			if d.Z < 0.62 and d.Y > -0.55 then
				local p, n = Kit.onEll(hc, half, ID, d)
				local L = if full() then 0.12 else 0.17
				Kit.limb("Spine", p - n * 0.04, p + n * L, if full() then 0.05 else 0.075, 0.015, f.spineC or a)
			end
		end
	end
	if f.lips then
		-- puckered lips: a little round pout, the mouth on its front
		local at, n = Kit.onEll(hc, half, ID, V(0, -0.2, 1))
		Kit.ell("Lips", at + n * 0.03, V(0.28, 0.2, 0.2), f.lips, A.lie(n, UP))
		Kit.mouth(at + n * 0.12, n, 0.13, "black")
	elseif f.grin then
		-- an anglerfish's grin: a wide dark mouth right across the front with needle teeth hanging over it, and the
		-- lower jaw jutting out under it on its own joint, its fangs standing up in front of the upper lip
		local at, n = Kit.onEll(hc, half, ID, V(0, -0.36, 1))
		Kit.ell("Gape", at - n * 0.02, V(hs.X * 0.72, 0.16, 0.2), "black", A.lie(V(1, 0, 0), n))
		if full() then
			for i = -2, 2 do
				local q, qn = Kit.onEll(hc, half, ID, V(i * 0.2, -0.26, 1))
				Kit.limb("Tooth", q + qn * 0.02, q + qn * 0.04 - UP * 0.07, 0.045, 0.01, "white")
			end
		end
		J("jaw", "head", hc + V(0, -hs.Y * 0.22, -hs.Z * 0.1), "jaw")
		local jc = hc + V(0, -hs.Y * 0.34, hs.Z * 0.18)
		local js = V(hs.X * 0.82, hs.Y * 0.36, hs.Z * 0.78)
		Kit.ell("Jaw", jc, js, b)
		local nTeeth = if full() then 4 else 2
		for i = 1, nTeeth do
			local u = -1 + 2 * (i - 1) / math.max(1, nTeeth - 1)
			local q = Kit.onEll(jc, js / 2, ID, V(u * 0.62, 0.55, 0.8))
			Kit.limb("Fang", q - UP * 0.03, q + V(0, 0.08, 0.01), 0.05, 0.012, "white")
		end
		Kit.on("head")
	else
		mouthOn(hc, half, V(0, -0.32, 1), f.mouthW or 0.15, f.ink)
	end
	-- the face's details (A.face): a fish's soft brows, no scales on its crown
	A.face({ color = b, c = hc, half = half, ink = f.ink, under = under, more = A.more({ brows = "soft", crown = false }, f.faceDetail) })
	if f.lure then
		-- the lamp: a stalk curving up and forward from the brow, a glowing bulb at its end, bobbing (kind "antenna")
		local base = Kit.onEll(hc, half, ID, V(0, 1, 0.35))
		J("lure", "head", base, "antenna")
		local pts = { base - V(0, 0.04, 0), base + V(0, 0.4, -0.02), base + V(0, 0.6, 0.24), base + V(0, 0.5, 0.5) }
		Kit.limbs("Lure", pts, { 0.045, 0.03 }, f.stalk or b, if full() then 3 else 2)
		local tip = pts[4] + V(0, -0.1, 0.03)
		Kit.ell("LureBulb", tip, V(0.22, 0.22, 0.22), f.lure, nil, nil, true)
		Kit.ell("LureCore", tip + V(-0.03, 0.04, 0.06), V(0.08, 0.08, 0.08), "white", nil, true, true)
		Kit.on("head")
	end
	if f.stars then
		-- tiny lit stars on its back and sides, like a little piece of the night sky
		Kit.on("body")
		for i, s in { { -0.06, 20, 0.1 }, { -0.3, -25, 0.09 }, { -0.5, 40, 0.08 }, { -0.18, 75, 0.07 }, { -0.36, -70, 0.07 } } do
			if i <= 3 or full() then
				local p = axOn(body, zEq + s[1], s[2])
				Kit.ell("Star", p, V(s[3], s[3], s[3]), f.starC or "white", nil, nil, true)
			end
		end
		Kit.on("head")
		local p, n = Kit.onEll(hc, half, ID, V(0.2, 0.9, -0.2))
		twinkle("Twinkle", p + n * 0.04, n, 0.12, f.starC or "white")
	end
	if f.lamps then
		-- a row of small glowing dots along each flank
		Kit.on("body")
		for _, side in { -1, 1 } do
			for i, z in { 0.0, -0.18, -0.36 } do
				if i <= 2 or full() then
					local p = axOn(body, zEq + z, side * 112)
					Kit.ell("Lamp", p, V(0.07, 0.07, 0.07), f.lampC or a, nil, nil, true)
				end
			end
		end
	end
	Kit.on("head")
	return t
end

-- Puffpod: a pufferfish, nearly a ball (the head is all of it), short orange spines everywhere but the face, little
-- fins, a stubby fan tail and a puckered pout.
FORMS.puffpod = {
	h = 1.75,
	cy = 1.0,
	head = V(1.08, 1.04, 1.06),
	hz = 0.06,
	blen = 0.82,
	bwide = 0.5,
	btall = 0.56,
	tlen = 0.3,
	plen = 0.24,
	dorsal = "low",
	spines = true,
	lips = "orange",
	gill = false,
	eye = { 26, 14, 0.32 },
	blush = 0.16,
}
-- Stripefin: a clownfish, orange with three white bands edged in black, round black-tipped fins.
FORMS.stripefin = {
	bands = { 0.1, -0.3, -0.66 },
	bandEdge = "black",
	fin = "orange",
	rim = "black",
	dorsal = "sail",
	tail = "fan",
	gill = false,
	eye = { 28, 12, 0.28 },
	blush = 0.14,
}
-- Lumenfin: an anglerfish of the deep, a big dark head with a jutting jaw full of needle teeth, a lit lamp on a stalk
-- over its brow, small dark fins and a row of tiny lights down each flank.
FORMS.lumenfin = {
	h = 2.2,
	head = V(0.96, 0.92, 0.92),
	hz = 0.12,
	blen = 1.0,
	bwide = 0.5,
	btall = 0.58,
	under = "slate",
	fin = "night",
	rim = "slate",
	dorsal = "low",
	tail = "fan",
	tlen = 0.34,
	grin = true,
	lure = "yellow",
	stalk = "slate",
	gill = false,
	eye = { 24, 20, 0.26 },
}
-- Starfin: a slim night fish with long flowing glowing fins (a veil tail, a tall trailing dorsal, ribbon pectorals)
-- and little stars on its back.
FORMS.starfin = {
	-- (its face: marks of its own)
	faceDetail = { marks = { freckles = "screen_on", glow = true } },
	h = 2.0,
	cy = 1.2,
	head = V(0.74, 0.78, 0.76),
	blen = 1.3,
	bwide = 0.48,
	btall = 0.62,
	under = "slate",
	fin = "screen_on",
	glow = true,
	dorsal = "veil",
	tail = "veil",
	longFins = true,
	stars = true,
	gill = false,
	eye = { 30, 12, 0.26 },
}

------------------------------------------------------------------ the ray
-- A manta ray gliding through the air: a flat body with a low hump, broad wing fins that sweep back to a point and
-- flap (kind "wing", an outer segment each with a spring), a pale belly, two head fins rolled like little horns either
-- side of a wide mouth, eyes on the front of the head, small fins by the tail and a thin whip of a tail.
PLANS.ray = function(b, a, form)
	local f: Form = form or {}
	local cy: number = f.cy or 1.2
	local t = Kit.new("ray", f.h or 1.55, f.r or 1.15, "fly")
	local under: string = f.under or A.under(b)
	local span: number = f.span or 1.12
	local sweep: number = f.sweep or 0.34
	local tipR: number = f.tipR or 0.05
	local edge: string? = f.edge
	J("body", nil, V(0, cy, 0), "body")
	local bs = V(0.84, 0.36, 1.04)
	Kit.ell("Body", V(0, cy, -0.02), bs, b)
	Kit.ell("Belly", V(0, cy - 0.05, -0.02), V(bs.X * 0.94, bs.Y * 0.8, bs.Z * 0.94), under)
	-- the wings: an inner panel from the body's side and an outer one to the tip, thick at the root, thin at the tip;
	-- the belly colour a step lower underneath (with `edge`, a step wider too, so it shows round the edge)
	local function panel(name: string, p0: Vector3, p1: Vector3, r0: number, r1: number)
		local th = 0.15
		local Rm = math.max(r0, r1)
		local grow = if edge then 0.04 else 0
		Kit.limb(name .. "Under", p0 - UP * 0.05, p1 - UP * 0.05 + (p1 - p0).Unit * grow, r0 + grow, r1 + grow, edge or under, th / (2 * (Rm + grow)), UP)
		Kit.limb(name, p0, p1, r0, r1, b, th / (2 * Rm), UP)
	end
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local root = V(side * 0.18, cy, 0.0)
		J("wing" .. s, "body", V(side * 0.3, cy, 0.0), "wing", side)
		local mid = V(side * span * 0.6, cy + 0.03, -sweep * 0.3)
		local midR: number = f.midR or 0.25
		panel("Wing" .. s, root, mid, 0.44, midR)
		-- the markings on the wing's top
		if f.spots then
			for i, sp in f.spots :: { { number } } do
				if i <= 3 or full() then
					local p = lerp(root, mid, sp[1]) + V(0, 0, sp[2])
					local r = 0.44 + (midR - 0.44) * sp[1]
					local lat = math.abs(sp[2]) / r
					local y = r * (0.15 / 0.88) * math.sqrt(math.max(0.05, 1 - lat * lat))
					Kit.disc("Spot" .. s, V(side * math.abs(p.X), cy + y, p.Z), UP, sp[3], 0.05, f.spotC or a, nil, nil, nil, 0.04)
				end
			end
		end
		if f.chevron then
			-- a pale shoulder patch, like a manta's
			Kit.ell("Chevron" .. s, V(side * 0.36, cy + 0.06, 0.06), V(0.4, 0.1, 0.26), f.chevron, CFrame.Angles(0, side * R(28), 0))
		end
		J("wing" .. s .. "2", "wing" .. s, mid, "wing", side, 1)
		local tip = V(side * span, cy + 0.08, -sweep)
		panel("WingTip" .. s, mid, tip, midR, tipR)
		if f.spots and full() then
			for _, sp in f.spotsTip or {} :: { { number } } do
				local p = lerp(mid, tip, sp[1]) + V(0, 0, sp[2])
				local r = midR + (tipR - midR) * sp[1]
				local y = r * (0.15 / (2 * midR))
				Kit.disc("Spot" .. s, V(side * math.abs(p.X), p.Y + y, p.Z), UP, sp[3], 0.05, f.spotC or a, nil, nil, nil, 0.04)
			end
		end
	end
	Kit.on("body")
	-- the small fins by the tail and a low dorsal fin at its root
	for _, side in { -1, 1 } do
		Kit.limb("Pelvic", V(side * 0.16, cy - 0.02, -0.38), V(side * 0.3, cy - 0.04, -0.6), 0.09, 0.05, b, 0.45, UP)
	end
	Kit.limb("Dorsal", V(0, cy + 0.08, -0.36), V(0, cy + 0.18, -0.52), 0.07, 0.03, b, 0.45, V(1, 0, 0))
	-- the tail
	local tl: number = f.tail or 1.2
	J("tail1", "body", V(0, cy, -0.46), "tail", 0, 1)
	local t0, t1, t2 = V(0, cy, -0.44), V(0, cy - 0.02, -0.46 - tl * 0.45), V(0, cy - 0.08, -0.46 - tl)
	Kit.limb("Tail", t0, t1, 0.07, 0.04, b)
	J("tail2", "tail1", t1, "tail", 0, 2)
	Kit.limb("Tail", t1, t2, 0.04, 0.015, f.tailTip or b)
	-- the head: the front of the body, with the face and the rolled head fins
	Kit.on("body")
	J("head", "body", V(0, cy, 0.22), "head")
	local hc = V(0, cy + 0.03, 0.4)
	local hs: Vector3 = f.head or V(0.66, 0.42, 0.5)
	Kit.ell("Head", hc, hs, b)
	Kit.ell("Chin", hc + V(0, -0.06, 0.0), V(hs.X * 0.92, hs.Y * 0.7, hs.Z * 0.96), under)
	local hf: number = f.hornLen or 1
	for _, side in { -1, 1 } do
		local p0 = hc + V(side * hs.X * 0.36, -0.02, hs.Z * 0.24)
		-- (rolled up: short horns pointing forward, curling in at the tips)
		local pts = { p0, p0 + V(side * 0.05, 0.03, 0.14) * hf, p0 + V(side * 0.02, 0.04, 0.26) * hf, p0 + V(-side * 0.05, 0.01, 0.32) * hf }
		Kit.limbs("HeadFin", pts, { 0.075, 0.06, 0.03 }, f.hornC or b, if full() then 3 else 2, 0.75, V(1, 0, 0))
	end
	local e: { number } = f.eye or { 34, 34, 0.22 }
	eyesOn(hc, hs / 2, R(e[1]), R(e[2]), e[3], f.iris, f.blush)
	mouthOn(hc, hs / 2, V(0, -0.3, 1), f.mouthW or 0.26)
	A.face({ color = b, c = hc, half = hs / 2, under = under, more = A.more(nil, f.faceDetail) })
	return t
end

-- Duneray: a sand coloured ray scattered with blue spots, its wings swept back to sharp points for speed, short head
-- fins and a long whip of a tail.
FORMS.duneray = {
	span = 1.16,
	sweep = 0.46,
	midR = 0.22,
	tipR = 0.03,
	tail = 1.5,
	hornLen = 0.75,
	spots = { { 0.62, -0.04, 0.16 }, { 0.85, 0.05, 0.12 }, { 0.45, 0.1, 0.12 }, { 0.6, -0.18, 0.1 }, { 0.3, -0.24, 0.09 } },
	spotsTip = { { 0.3, -0.02, 0.1 }, { 0.6, -0.03, 0.07 } },
	spotC = "blue",
	eye = { 34, 36, 0.22 },
}
-- Reefray: a big blue blanket of a ray, broad rounded wings with a white edge and belly, white shoulder patches, big
-- curled head fins and a short tail.
FORMS.reefray = {
	h = 1.6,
	span = 1.2,
	sweep = 0.22,
	midR = 0.3,
	tipR = 0.1,
	tail = 0.8,
	hornLen = 1.2,
	edge = "white",
	under = "white",
	chevron = "white",
	eye = { 34, 34, 0.22 },
	blush = 0.12,
}

------------------------------------------------------------------ the seahorse
-- An upright seahorse bobbing in the air: a pot-bellied trunk with a pale ridged belly plate, a neck bending forward
-- into a horse-like head with a long tube of a snout, a coronet on top, a little back fin that flutters (kind "fin"),
-- tiny fins behind the head, and a tail that tapers down and curls forward into a spiral (two "tail" joints). Forms
-- hang trailing kelp fronds on it or grow coral nubs.
PLANS.seahorse = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("seahorse", f.h or 2.3, f.r or 0.9, "fly")
	local belly: string = f.belly or a
	J("body", nil, V(0, 1.1, 0), "body")
	-- the trunk: an egg standing on its narrow end, leaning a little forward at the top
	local tc = V(0, 1.12, 0.0)
	local down = V(0, -1, -0.12).Unit
	local trot = A.lie(down, FWD)
	local tsz = V(0.6, 0.9, 0.62)
	Kit.egg("Trunk", tc, tsz, 0.56, b, trot)
	-- the belly: a column of overlapping plates down its front, each lower edge a ridge
	local nr = if full() then 5 else 3
	for i = 1, nr do
		local u = (i - 1) / (nr - 1)
		local d = V(0, 0.42 - 0.95 * u, 1).Unit
		local p, n = eggOn(tc, tsz, 0.56, trot, d)
		local w = tsz.X * (0.74 - 0.28 * u * u)
		local x = V(1, 0, 0)
		local y = n:Cross(x).Unit
		Kit.ell("Belly", p, V(w, 0.24 - 0.04 * u, 0.12), belly, CFrame.fromMatrix(Vector3.zero, x, y, n))
	end
	-- the neck, bending forward into the head
	Kit.limbs("Neck", { V(0, 1.4, -0.06), V(0, 1.58, -0.04), V(0, 1.7, 0.06) }, { 0.22, 0.19 }, b, 2)
	-- the back fin, fluttering
	J("finD", "body", V(0, 1.12, -0.28), "fin", 0)
	local fb = V(0, 1.12, -0.26)
	for i, ang in { 40, 10, -20 } do
		local d = V(0, math.sin(R(ang)), -math.cos(R(ang)))
		fin("BackFin", fb + V(0, (i - 2) * 0.08, 0), fb + V(0, (i - 2) * 0.08, 0) + d * 0.26, 0.05, 0.08, f.finC or a, V(1, 0, 0), 0.08, nil, f.glow)
	end
	Kit.on("body")
	-- the tail: down from the trunk, then curling forward and up into a spiral
	J("tail1", "body", V(0, 0.8, -0.05), "tail", 0, 1)
	local cr: number = f.curl or 0.2
	local p2 = V(0, 0.38, -0.04)
	Kit.limbs("Tail", { V(0, 0.84, -0.04), V(0, 0.6, -0.1), p2 }, { 0.17, 0.12 }, b, 2)
	J("tail2", "tail1", p2, "tail", 0, 2)
	local C = p2 + V(0, 0, cr)
	local pts = { p2 }
	local turns: number = f.turns or 1.75
	local n = 7
	for i = 1, n do
		local th = i / n * turns * math.pi
		local r = cr * (1 - 0.6 * i / n)
		table.insert(pts, C + V(0, -math.sin(th) * r, -math.cos(th) * r))
	end
	Kit.limbs("Tail", pts, { 0.12, 0.09, 0.06, 0.035 }, b, if full() then 6 else 3)
	-- the head
	Kit.on("body")
	J("head", "body", V(0, 1.6, 0.0), "head")
	local hc = V(0, 1.86, 0.12)
	local hs = V(0.5, 0.5, 0.56)
	Kit.ell("Head", hc, hs, b)
	-- the snout: a long tube forward and down, the mouth at its end
	local s0, s1 = hc + V(0, -0.08, 0.16), hc + V(0, -0.24, 0.58)
	Kit.limb("Snout", s0, s1, 0.12, 0.07, b)
	local sd = (s1 - s0).Unit
	Kit.ell("SnoutTip", s1 + sd * 0.04, V(0.16, 0.16, 0.08), f.tip or A.shade(b), A.lie(V(0, 1, 0):Cross(sd).Unit:Cross(sd), sd))
	Kit.mouth(s1 + sd * 0.09, sd, 0.08, "black")
	-- a pale cheek
	Kit.ell("Cheek", hc + V(0, -0.1, 0.06), V(hs.X * 0.9, hs.Y * 0.6, hs.Z * 0.8), f.cheek or b)
	local e: { number } = f.eye or { 36, 10, 0.2 }
	eyesOn(hc, hs / 2, R(e[1]), R(e[2]), e[3], f.iris, f.blush)
	-- the face's details (A.face), its coronet on the crown
	A.face({ color = b, c = hc, half = hs / 2, more = A.more({ crown = false }, f.faceDetail) })
	-- the tiny fins behind the head
	for _, side in { -1, 1 } do
		local sname = if side < 0 then "L" else "R"
		Kit.on("head")
		local root = hc + V(side * 0.19, -0.14, -0.16)
		J("fin" .. sname, "head", root, "fin", side)
		for _, ang in { 20, -25 } do
			local d = V(side * 0.5, math.sin(R(ang)), -0.8).Unit
			fin("Pectoral" .. sname, root, root + d * 0.12, 0.035, 0.055, f.finC or a, V(side, 0.1, 0.6).Unit, 0.06, nil, f.glow)
		end
	end
	Kit.on("head")
	-- the coronet: a little crown of knobs on top
	local top = hc + V(0, hs.Y * 0.44, -0.04)
	if f.crown == "coral" then
		-- coral nubs: branching orange twigs with round tips
		for i, c in { { 0, 0, 1 }, { -1, 1, 0.8 }, { 1, 1, 0.8 } } do
			local base = top + V(c[1] * 0.1, -0.02, -c[2] * 0.06)
			local tip = base + V(c[1] * 0.12, 0.26 * c[3], -0.04)
			Kit.limb("Coral", base, tip, 0.06, 0.045, a)
			Kit.ell("CoralTip", tip, V(0.11, 0.11, 0.11), a)
			if full() and i == 1 then
				local mid = lerp(base, tip, 0.5)
				Kit.limb("Coral", mid, mid + V(0.1, 0.1, 0.04), 0.04, 0.035, a)
				Kit.ell("CoralTip", mid + V(0.1, 0.1, 0.04), V(0.09, 0.09, 0.09), a)
			end
		end
	else
		for i = -1, 1 do
			local base = top + V(i * 0.07, 0, -math.abs(i) * 0.05)
			Kit.limb("Crown", base, base + V(i * 0.04, 0.14, -0.04), 0.05, 0.025, f.crownC or b)
		end
	end
	-- forms: kelp fronds trailing from the head, the back and the tail
	if f.fronds then
		local fc: string = f.fronds
		local fc2: string = f.fronds2 or A.shade(fc)
		-- a frond: a long wavy ribbon, wide in the middle, trailing back and drooping at its end
		local function frond(base: Vector3, dir: Vector3, len: number, c: string, sideN: Vector3)
			local d = dir.Unit
			local q1 = base + d * len * 0.35 + V(0, 0.03, 0)
			local q2 = base + d * len * 0.7 + V(0, -len * 0.12, 0) + sideN * 0.04
			local q3 = base + d * len + V(0, -len * 0.4, 0)
			Kit.limbs("Frond", { base, q1, q2, q3 }, { 0.035, 0.09, 0.07, 0.02 }, c, if full() then 3 else 2, 0.3, sideN)
		end
		Kit.on("head")
		frond(top + V(0, 0, -0.02), V(0, 0.7, -1), 0.7, fc, V(1, 0, 0))
		frond(top + V(0.08, -0.04, -0.04), V(0.7, 0.4, -1), 0.56, fc2, V(1, 0, 0.5).Unit)
		frond(top + V(-0.08, -0.04, -0.04), V(-0.7, 0.4, -1), 0.56, fc2, V(1, 0, -0.5).Unit)
		Kit.on("body")
		frond(V(0.2, 1.3, -0.14), V(0.9, 0.3, -1), 0.6, fc, V(1, 0, 0.7).Unit)
		frond(V(-0.2, 1.24, -0.16), V(-0.9, 0.3, -1), 0.56, fc2, V(1, 0, -0.7).Unit)
		if full() then
			frond(V(0.18, 0.96, -0.2), V(0.8, 0, -1), 0.5, fc2, V(1, 0, 0.7).Unit)
			Kit.on("tail1")
			frond(V(-0.1, 0.62, -0.14), V(-0.8, 0, -1), 0.44, fc, V(1, 0, -0.7).Unit)
		end
	end
	if f.nubs then
		-- coral nubs along its back
		Kit.on("body")
		for i, y in { 1.36, 1.14, 0.92 } do
			if i <= 2 or full() then
				local base = V(0, y, -0.25 - (1.36 - y) * 0.05)
				local tip = base + V(0, 0.08, -0.16)
				Kit.limb("Nub", base, tip, 0.065, 0.045, f.nubs)
				Kit.ell("NubTip", tip, V(0.1, 0.1, 0.1), f.nubs)
			end
		end
	end
	Kit.on("head")
	return t
end

-- Kelphorse: a coral seahorse with a cream belly, green kelp fronds trailing from its crown, its back and its tail.
FORMS.kelphorse = {
	fronds = "leaf",
	fronds2 = "moss",
	cheek = "coral",
	eye = { 36, 10, 0.2 },
	blush = 0.1,
}
-- Coralcurl: a pink seahorse with a crown of orange coral and coral nubs down its back, its tail curled big and
-- tight.
FORMS.coralcurl = {
	crown = "coral",
	nubs = "orange",
	belly = "cherry",
	curl = 0.24,
	turns = 2.1,
	finC = "orange",
	ridge = "pink",
	eye = { 36, 10, 0.2 },
}

------------------------------------------------------------------ the octopus (and the squid)
-- An octopus floating in the air: a soft mantle (the head, its own joint, so it looks about) over a short ring where
-- the arms meet, big eyes low on the mantle's front, a little mouth, and eight arms in two segments each (kind
-- "tendril") that reach out and down and curl up at their tips, suckers on the curls up close. Forms make it a squid
-- (a pointed mantle with fins at its tip, shorter arms and two long tentacles with clubbed ends) or give it long
-- curling arms.
PLANS.octo = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("octo", f.h or 2.3, f.r or 1.1, "fly")
	local reach: number = f.reach or 1
	local hubY = 1.0
	J("body", nil, V(0, hubY, 0), "body")
	-- the ring where the arms meet
	Kit.ell("Hub", V(0, hubY, 0), V(0.74, 0.4, 0.74), b)
	-- the arms
	local n = 8
	local sucker = f.suckers
	for k = 1, n do
		Kit.on("body")
		local th = R((k - 0.5) * 360 / n)
		local out = V(math.sin(th), 0, math.cos(th))
		local side = if out.X < -0.1 then -1 elseif out.X > 0.1 then 1 else 0
		local root = V(0, hubY - 0.04, 0) + out * 0.26
		-- (the front arms a little shorter and more tucked, so they never hide the face)
		local L = reach * (if out.Z > 0.5 then 0.82 else 1)
		local drop = math.min(0.86, hubY - 0.1)
		local p1 = root + out * 0.24 * L + V(0, -0.22, 0)
		local p2 = root + out * 0.42 * L + V(0, -drop * 0.62, 0)
		local p3 = root + out * 0.6 * L + V(0, -drop * 0.92, 0)
		local p4 = root + out * 0.82 * L + V(0, -drop * 0.84, 0)
		local p5 = root + out * 0.86 * L + V(0, -drop * 0.62, 0)
		J("tendril" .. k, "body", root, "tendril", side, k)
		Kit.limbs("Arm" .. k, { root, p1, p2 }, { 0.13, 0.095 }, b, 2)
		J("tendril" .. k .. "b", "tendril" .. k, p2, "tendril", side, k + 0.5)
		if full() then
			Kit.limbs("Arm" .. k, { p2, p3, p4, p5 }, { 0.095, 0.06, 0.03 }, b, 3)
		else
			Kit.limb("Arm" .. k, p2, p4, 0.095, 0.04, b)
		end
		if sucker and full() then
			-- suckers along the underside of the curl
			for _, u in { 0.3, 0.55 } do
				local q = Kit.curveAt({ p2, p3, p4, p5 }, u)
				local r = 0.095 + (0.03 - 0.095) * u
				Kit.ell("Sucker" .. k, q - UP * r * 0.75 + out * 0.01, V(r * 0.9, r * 0.5, r * 0.9), sucker)
			end
		end
	end
	if f.tentacles then
		-- the squid's two long tentacles, from the front, each ending in a flat club
		for _, side in { -1, 1 } do
			Kit.on("body")
			local root = V(side * 0.12, hubY - 0.1, 0.2)
			local q1 = root + V(side * 0.12, -0.36, 0.22)
			local q2 = root + V(side * 0.18, -0.7, 0.32)
			local q3 = root + V(side * 0.2, -0.86, 0.5)
			J("tendril" .. (if side < 0 then 9 else 10), "body", root, "tendril", side, 9.3 + side)
			Kit.limbs("Tentacle", { root, q1, q2, q3 }, { 0.07, 0.05, 0.045 }, b, 3)
			Kit.ell("Club", q3 + V(0, 0.02, 0.08), V(0.16, 0.1, 0.26), f.clubC or b, A.lie(V(0, 0.2, 1)))
		end
	end
	-- the mantle: the head, on its own joint
	Kit.on("body")
	J("head", "body", V(0, hubY + 0.06, 0), "head")
	local ms: Vector3 = f.mantle or V(1.0, 1.06, 0.96)
	local split: number = f.split or 0.58
	local back: number = f.lean or 12
	local up = (CFrame.Angles(R(-back), 0, 0)):VectorToWorldSpace(UP)
	local mc = V(0, hubY + ms.Y * (1 - split) + 0.04, 0) + up * ms.Y * 0.08 - FWD * 0.02
	local mrot = A.lie(up, FWD)
	Kit.egg("Mantle", mc, ms, split, b, mrot)
	-- the face: on the mantle's lower half
	local ye = ms.Y / 2 - ms.Y * split
	local fc = mc + mrot:VectorToWorldSpace(V(0, ye, 0))
	local fh = V(ms.X / 2, ms.Y * (1 - split), ms.Z / 2)
	Kit.faceOn(fc, fh, mrot)
	local e: { number } = f.eye or { 26, 2, 0.32 }
	local avg = (fh.X + fh.Y + fh.Z) / 3
	Kit.eyes(fc, avg, FWD, R(e[1]), R(e[2]), e[3], f.iris)
	if f.blush then
		Kit.blush(fc, avg, FWD, R(e[1] + 16), R(18), f.blush)
	end
	Kit.faceOff()
	local at, nrm = Kit.onEll(fc, fh, mrot, V(0, -0.5, 1))
	Kit.mouth(at, nrm, 0.14)
	A.face({ color = b, c = fc, half = fh, rot = mrot, more = A.more(nil, f.faceDetail) })
	-- spots on the mantle
	if f.spots then
		for i, sp in f.spots :: { { number } } do
			if i <= 3 or full() then
				local d = A.dir(sp[1], sp[2])
				local q, qn = Kit.onEll(mc + mrot:VectorToWorldSpace(V(0, ye, 0)), V(ms.X / 2, ms.Y * split, ms.Z / 2), mrot, d)
				dot("Spot", q, qn, sp[3], f.spotC or a)
			end
		end
	end
	if f.fins then
		-- the squid's fins: two flaps either side of the mantle's tip, flapping (kind "fin")
		local tip = mc + up * ms.Y * (split - 0.12)
		for _, side in { -1, 1 } do
			local sname = if side < 0 then "L" else "R"
			Kit.on("head")
			local root = tip + V(side * ms.X * 0.16, -0.12, 0)
			J("fin" .. sname, "head", root, "fin", side)
			fin("Fin" .. sname, root - V(0, 0.08, 0), root + V(side * 0.34, 0.2, -0.04), 0.22, 0.04, f.finC or b, FWD, 0.1)
		end
	end
	Kit.on("head")
	return t
end

-- Squidge: a pink squid, a pointed mantle with fins at its tip, purple spots, short arms and two long clubbed
-- tentacles.
FORMS.squidge = {
	h = 2.5,
	mantle = V(0.88, 1.12, 0.86),
	split = 0.66,
	lean = 6,
	reach = 0.86,
	tentacles = true,
	clubC = "purple",
	fins = true,
	finC = "pink",
	spots = { { 0, 40, 0.12 }, { -40, 55, 0.1 }, { 45, 50, 0.1 }, { 150, 40, 0.12 }, { -130, 30, 0.1 }, { 20, 75, 0.09 } },
	spotC = "purple",
	eye = { 28, 4, 0.32 },
	blush = 0.16,
}
-- Tidegrip: a purple octopus, a big round mantle leaning back, long arms that curl right round with pink suckers on
-- the curls.
FORMS.tidegrip = {
	h = 2.3,
	mantle = V(1.06, 1.08, 1.0),
	split = 0.56,
	lean = 16,
	reach = 1.25,
	suckers = "pink",
	spots = { { 30, 50, 0.13 }, { -35, 40, 0.11 }, { 0, 72, 0.12 }, { 170, 40, 0.13 }, { 110, 20, 0.1 } },
	spotC = "pink",
	eye = { 26, 2, 0.3 },
}

------------------------------------------------------------------ the jellyfish
-- A jellyfish drifting in the air: a smooth bell (an egg, round on top, flat underneath) with a frilled rim of soft
-- scallops, a face on its front, four frilly oral arms hanging from the middle of its underside and long thin
-- tentacles trailing from the rim (kind "tendril": six of two segments, as the old jelly had, and the oral arms).
-- Forms add glowing rings and freckles, or a cloud puff of a top with raindrops on the tentacle tips.
PLANS.jelly = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("jelly", f.h or 2.5, f.r or 1.0, "fly")
	local bw: number = f.bw or 1.5
	local bh: number = f.bh or 1.15
	local split: number = f.split or 0.7
	local top: number = f.top or 2.38
	local rimC: string = f.rim or a
	local armC: string = f.arm or a
	local tenC: string = f.tent or b
	J("body", nil, V(0, top - bh * 0.6, 0), "body")
	local bc = V(0, top - bh / 2, 0)
	Kit.egg("Bell", bc, V(bw, bh, bw), split, b)
	local eqY = bc.Y + bh / 2 - bh * split
	local botY = eqY - bh * (1 - split)
	local hTop = bh * split
	local half = V(bw / 2, hTop, bw / 2)
	local ec = V(0, eqY, 0)
	-- the frilled rim: soft scallops all round the margin, tipped a little out and down
	local nsc = if full() then 12 else 7
	for i = 0, nsc - 1 do
		local th = (i + 0.5) / nsc * 2 * math.pi
		local out = V(math.sin(th), 0, math.cos(th))
		local tan = V(math.cos(th), 0, -math.sin(th))
		local p = ec + out * (bw * 0.46) - UP * (bh * (1 - split) * 0.5 + 0.05)
		local n = (out - UP * 0.3).Unit
		local y = n:Cross(tan).Unit
		Kit.ell("Scallop", p, V(2 * math.pi * bw * 0.46 / nsc * 1.06, 0.34, 0.09), rimC, CFrame.fromMatrix(Vector3.zero, tan, y, n))
	end
	-- the oral arms: frilly ribbons from the middle, ruffled along both edges
	for i, q in { { 0.12, 0.1 }, { -0.12, 0.1 }, { 0.12, -0.1 }, { -0.12, -0.1 } } do
		Kit.on("body")
		local root = V(q[1], botY + 0.06, q[2])
		local out = V(q[1], 0, q[2]).Unit
		local L: number = f.armLen or 0.8
		J("tendril" .. (6 + i), "body", root, "tendril", if q[1] < 0 then -1 else 1, 6 + i)
		local w = if i % 2 == 0 then 0.06 else -0.06
		local pts = { root, root + out * 0.1 + V(w, -L * 0.35, 0), root + out * 0.16 + V(-w, -L * 0.7, w), root + out * 0.18 + V(w * 0.5, -L, 0) }
		local rn = V(out.Z, 0, -out.X)
		Kit.limbs("OralArm", pts, { 0.09, 0.11, 0.08, 0.04 }, armC, if full() then 3 else 1, 0.45, rn)
		if full() then
			for k = 1, 4 do
				local u = (k - 0.5) / 4
				local c = Kit.curveAt(pts, u)
				local sd = if k % 2 == 0 then 1 else -1
				Kit.ell("Frill", c + rn * sd * 0.07 * (1 - u * 0.4), V(0.12, 0.14, 0.12) * (1 - u * 0.35), armC)
			end
		end
	end
	-- the tentacles: long and thin from the rim, in two segments that sway, each wavy and a little different
	local nt = 6
	local tl: number = f.tentLen or 1.0
	for i = 1, nt do
		Kit.on("body")
		local th = R((i - 0.5) * 360 / nt + 30)
		local out = V(math.sin(th), 0, math.cos(th))
		local root = ec + out * (bw * 0.38) - UP * (bh * (1 - split) * 0.7)
		local side = if out.X < -0.1 then -1 elseif out.X > 0.1 then 1 else 0
		local L = tl * (0.8 + 0.2 * ((i * 7) % 3) / 2)
		local wv = V(out.Z, 0, -out.X) * (if i % 2 == 0 then 0.07 else -0.07)
		local m = root + out * 0.08 + V(0, -L * 0.5, 0)
		local e = root + out * 0.14 + wv * 0.6 + V(0, -L, 0)
		J("tendril" .. i, "body", root, "tendril", side, i)
		local r0 = if full() then 0.04 else 0.055
		Kit.limbs("Tentacle" .. i, { root, root + out * 0.05 + wv + V(0, -L * 0.25, 0), m }, { r0, r0 * 0.85 }, tenC, if full() then 2 else 1)
		J("tendril" .. i .. "b", "tendril" .. i, m, "tendril", side, i + 0.5)
		Kit.limbs("Tentacle" .. i, { m, m - wv + out * 0.03 + V(0, -L * 0.25, 0), e, e + out * 0.06 - wv * 0.8 + V(0, 0.08, 0) }, { r0 * 0.85, r0 * 0.5 }, tenC, if full() then 3 else 1)
		if f.drops and (full() or i % 2 == 1) then
			-- a raindrop hanging below the tip
			Kit.egg("Drop", e + V(0, -0.1, 0), V(0.13, 0.18, 0.13), 0.62, f.drops, nil, nil, f.dropGlow)
		end
	end
	Kit.on("body")
	-- the face, on the front of the bell
	local e: { number } = f.eye or { 26, 14, 0.32 }
	Kit.faceOn(ec, half)
	local avg = (half.X + half.Y + half.Z) / 3
	Kit.eyes(ec, avg, FWD, R(e[1]), R(e[2]), e[3], f.iris)
	if full() then
		Kit.blush(ec, avg, FWD, R(e[1] + 18), R(-2), 0.16)
	end
	Kit.faceOff()
	mouthOn(ec, half, V(0, 0.02, 1), 0.16)
	A.face({ color = b, c = ec, half = half, more = A.more(nil, f.faceDetail) })
	-- forms
	if f.rings then
		-- four rings showing through the top of the bell, like a moon jelly's
		for k = 0, 3 do
			local d = A.dir(45 + 90 * k, 72)
			local p, n = Kit.onEll(ec, half, ID, d)
			dot("Ring", p, n, 0.26, f.rings, 0.03)
			dot("RingIn", p, n, 0.12, b, 0.075, nil, true)
		end
	end
	if f.freckles then
		-- soft glowing freckles
		for i, q in { { 40, 30, 0.1 }, { -36, 38, 0.08 }, { 150, 30, 0.09 }, { -130, 24, 0.08 }, { 95, 55, 0.07 }, { -80, 60, 0.07 } } do
			if i <= 3 or full() then
				local p, n = Kit.onEll(ec, half, ID, A.dir(q[1], q[2]))
				dot("Freckle", p, n, q[3], f.freckles, 0.045, true)
			end
		end
	end
	if f.cloud then
		-- a cloud puff of a top: a few soft lobes round the crown of the bell
		local cc = ec + UP * hTop * 0.82
		for i, q in { { 0, 0.16, 0.0, 0.72 }, { 0.32, 0.0, 0.08, 0.56 }, { -0.32, 0.0, 0.06, 0.56 }, { 0.1, -0.02, -0.3, 0.5 }, { -0.12, 0.02, 0.3, 0.46 } } do
			if i <= 3 or full() then
				Kit.ell("Cloud", cc + V(q[1], q[2], q[3]), V(q[4], q[4] * 0.72, q[4] * 0.9), f.cloud)
			end
		end
	end
	return t
end

-- Lumajelly: a pink jelly with a tall round bell, a purple frilled rim, purple oral arms, four rings on top and soft
-- glowing freckles.
FORMS.lumajelly = {
	bh = 1.22,
	split = 0.72,
	rings = "purple",
	freckles = "cherry",
	tent = "pink",
	eye = { 26, 14, 0.32 },
}
-- Cloudjelly: a white jelly with a wide flat bell and a cloud puff on top, a pink rim and pink oral arms, and a
-- raindrop on the tip of every tentacle.
FORMS.cloudjelly = {
	bw = 1.64,
	bh = 0.98,
	split = 0.66,
	top = 2.2,
	cloud = "white",
	drops = "shallow",
	tentLen = 1.0,
	armLen = 0.6,
	eye = { 26, 16, 0.32 },
}

------------------------------------------------------------------ the mushroom folk
-- A little mushroom person: a stout stem for a body (an egg, wider at the bottom) with the face on its front, short
-- legs on round feet, little arms, and a big cap with spots on its own joint (so it tips and nods), a ring of gills
-- under it. Forms pick the cap's shape (a round bun, a tall bell), glowing spots, a frilled collar round the stem, a
-- baby cap sprouting, drifting spores.
PLANS.shroom = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("shroom", f.h or 2.1, f.r or 0.95, "biped")
	local stem: string = f.stem or A.under(b)
	local sh: number = f.stemH or 1.0
	local sw: number = f.stemW or 0.86
	J("body", nil, V(0, 0.7, 0), "body")
	-- the stem
	local sc = V(0, 0.22 + sh / 2, 0)
	local split = 0.55
	Kit.egg("Stem", sc, V(sw, sh, sw * 0.93), split, stem)
	local eqY = sc.Y + sh / 2 - sh * split
	local fcen = V(0, eqY, 0)
	local fhalf = V(sw / 2, sh * split, sw * 0.93 / 2)
	local topY = sc.Y + sh / 2
	-- legs and round feet
	for _, side in { -1, 1 } do
		A.leg(if side < 0 then "L" else "R", side, if side < 0 then 0 else 0.5, V(side * 0.2, 0.34, 0.02), {
			kind = "post",
			r = 0.12,
			foot = "pad",
			fw = 0.28,
			c = stem,
			fc = f.feet or stem,
			mass = false,
			out = 0.03,
		})
	end
	-- arms
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local sh0 = V(side * (sw * 0.42), eqY + 0.16, 0.02)
		J("arm" .. s, "body", sh0, "arm", side)
		local hand = sh0 + V(side * 0.18, -0.28, 0.1)
		Kit.limb("Arm" .. s, sh0, hand, 0.085, 0.07, stem)
		Kit.ell("Hand" .. s, hand + V(side * 0.01, -0.04, 0.01), V(0.16, 0.16, 0.16), stem)
	end
	Kit.on("body")
	-- the face on the stem
	local e: { number } = f.eye or { 24, 22, 0.24 }
	eyesOn(fcen, fhalf, R(e[1]), R(e[2]), e[3], f.iris, f.blush or 0.15)
	mouthOn(fcen, fhalf, V(0, 0.05, 1), 0.15)
	-- the face's details (A.face): the face is on the stem, bare, under the cap
	A.face({ color = stem, c = fcen, half = fhalf, more = A.more({ tex = "skin", brows = "soft", crown = false }, f.faceDetail) })
	if f.collar then
		-- a frilled collar (the ring a mushroom's veil leaves) round the top of the stem
		local cy = topY - 0.22
		local n = if full() then 10 else 6
		for i = 0, n - 1 do
			local th = (i + 0.5) / n * 2 * math.pi
			local out = V(math.sin(th), 0, math.cos(th))
			local tan = V(math.cos(th), 0, -math.sin(th))
			local k = math.clamp((cy - eqY) / (sh * split), 0, 0.95)
			local r = (sw / 2) * math.sqrt(1 - k * k) + 0.04
			local nn = (out - UP * 0.45).Unit
			local y = nn:Cross(tan).Unit
			if out.Z < 0.7 then
				Kit.ell("Collar", V(0, cy, 0) + out * r - UP * 0.04, V(2 * math.pi * r / n * 1.2, 0.2, 0.07), f.collar, CFrame.fromMatrix(Vector3.zero, tan, y, nn))
			end
		end
	end
	-- the cap, on its own joint
	J("head", "body", V(0, topY - 0.08, 0), "head")
	local cw: number = f.capW or 1.62
	local ch: number = f.capH or 0.86
	local cs: number = f.capSplit or 0.74
	local under = ch * (1 - cs)
	local capBot = topY - 0.06
	local cc = V(0, capBot + ch / 2, -0.02)
	Kit.egg("Cap", cc, V(cw, ch, cw * 0.95), cs, b)
	local ceq = V(0, capBot + under, -0.02)
	local chalf = V(cw / 2, ch * cs, cw * 0.95 / 2)
	-- the gills: a paler ring under the cap's rim
	Kit.ell("Gills", ceq - UP * (under * 0.5), V(cw * 0.94, under * 1.1, cw * 0.89), f.gills or A.shade(stem), nil, nil, f.gillGlow)
	-- spots on the cap
	for i, sp in (f.spots or { { 0, 34, 0.3 }, { 70, 40, 0.24 }, { -65, 42, 0.22 }, { 160, 52, 0.26 }, { -130, 55, 0.22 }, { 20, 78, 0.22 } }) :: { { number } } do
		if i <= 4 or full() then
			local p, n = Kit.onEll(ceq, chalf, ID, A.dir(sp[1], sp[2]))
			dot("CapSpot", p, n, sp[3], f.spotC or a, 0.04, f.spotGlow)
		end
	end
	if f.baby then
		-- a baby cap sprouting from the side of the big one
		local p, n = Kit.onEll(ceq, chalf, ID, A.dir(62, 26))
		local q = p + n * 0.04
		Kit.limb("BabyStem", p - n * 0.06, q, 0.07, 0.06, stem)
		Kit.egg("BabyCap", q + n * 0.08, V(0.36, 0.24, 0.36), 0.7, b, A.lie(n))
	end
	if f.spores and full() then
		-- spores drifting up round it, lit
		for _, q in { V(0.86, 1.5, 0.3), V(-0.8, 1.2, 0.4), V(0.6, 2.2, -0.2), V(-0.5, 2.3, 0.3) } do
			Kit.ell("Spore", q, V(0.07, 0.07, 0.07), f.spores, nil, true, true)
		end
	end
	if f.moon then
		-- a little crescent moon on the front of the cap
		local p, n = Kit.onEll(ceq, chalf, ID, A.dir(0, 30))
		dot("Moon", p, n, 0.26, f.moon, 0.05, true)
		dot("MoonBite", p + (UP * 0.06 + V(0.06, 0, 0)), n, 0.2, b, 0.09)
	end
	return t
end

-- Spored: a short stout mushroom with a round purple cap dotted with glowing spots, a cream stem and a few spores
-- drifting round it.
FORMS.spored = {
	spotC = "screen_on",
	spotGlow = true,
	spores = "screen_on",
	eye = { 24, 22, 0.22 },
}
-- Moonshroom: a tall mushroom with a crystal bell of a cap that glows underneath, white glowing spots and a crescent
-- moon on it, a frilled collar round its white stem and a baby cap sprouting from the side.
FORMS.moonshroom = {
	h = 2.7,
	stemH = 1.08,
	stemW = 0.8,
	capW = 1.32,
	capH = 1.5,
	capSplit = 0.86,
	gills = "crystal",
	gillGlow = true,
	spots = { { 70, 25, 0.18 }, { -60, 30, 0.16 }, { 150, 30, 0.2 }, { -150, 40, 0.18 }, { 30, 62, 0.16 } },
	spotC = "white",
	spotGlow = true,
	collar = "white",
	baby = true,
	moon = "yellow",
	eye = { 24, 22, 0.24 },
}

------------------------------------------------------------------ the sprite
-- A little fairy hovering on insect wings: a big round head (most of its height) with pointed ears and a face, a small
-- tapering body in a skirt, thin arms with round hands, thin legs that dangle with pointed feet, and two pairs of
-- wings that flap (kind "wing"). Forms pick the wings (a butterfly's, a dragonfly's, round ones), the skirt (petals,
-- icicles, a soft glowing hem) and the head: a crown of sun rays, spiky ice hair with horns and an imp's tail, or a
-- flame of light for hair and a tiny hatchet.
PLANS.sprite = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("sprite", f.h or 2.3, f.r or 0.9, "fly")
	local skin: string = f.skin or b
	J("body", nil, V(0, 1.0, 0), "body")
	-- the body: a small egg, fuller at the shoulders, tapering to the hips
	local tc = V(0, 0.98, 0)
	Kit.egg("Torso", tc, V(0.42, 0.52, 0.36), 0.42, skin)
	-- the skirt round its hips
	local sk: string = f.skirt or "petal"
	local skc: string = f.skirtC or a
	local nsk = if full() then 7 else 4
	for i = 0, nsk - 1 do
		local th = (i + 0.5) / nsk * 2 * math.pi
		local out = V(math.sin(th), 0, math.cos(th))
		local base = V(0, 0.86, 0) + out * 0.13
		if sk == "petal" then
			local tip = base + out * 0.22 + V(0, -0.22, 0)
			fin("Petal", base, tip, 0.1, 0.05, skc, (out + UP * 0.8).Unit, 0.06)
		elseif sk == "icicle" then
			local L = 0.22 + 0.08 * (i % 2)
			Kit.limb("Icicle", base + UP * 0.04, base + out * 0.08 + V(0, -L, 0), 0.07, 0.012, skc)
		else
			-- a soft hem, lit, flickering out like a little flame
			local L = 0.18 + 0.06 * (i % 2)
			Kit.limb("Hem", base + UP * 0.04, base + out * 0.12 + V(0, -L, 0), 0.08, 0.025, skc, nil, nil, nil, f.hemGlow)
		end
	end
	if f.gem then
		Kit.ell("Gem", tc + V(0, 0.06, 0.17), V(0.12, 0.12, 0.08), f.gem, nil, true, true)
	end
	-- the legs, dangling, pointed feet
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local hip = V(side * 0.09, 0.8, 0)
		J("leg" .. s, "body", hip, "leg", side, if side < 0 then 0 else 0.5)
		local knee = hip + V(side * 0.02, -0.2, 0.03)
		local ankle = hip + V(side * 0.03, -0.38, 0.0)
		if full() then
			Kit.limb("Leg" .. s, hip, knee, 0.06, 0.05, skin)
			Kit.limb("Leg" .. s, knee, ankle, 0.05, 0.045, f.legC or skin)
		else
			Kit.limb("Leg" .. s, hip, ankle, 0.06, 0.05, f.legC or skin)
		end
		Kit.limb("Foot" .. s, ankle + V(0, -0.02, -0.02), ankle + V(side * 0.01, -0.05, 0.14), 0.055, 0.025, f.footC or skc)
	end
	-- the arms
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local sh = V(side * 0.18, 1.12, 0.02)
		J("arm" .. s, "body", sh, "arm", side)
		local elbow = sh + V(side * 0.1, -0.14, 0.03)
		local hand = sh + V(side * 0.14, -0.28, 0.08)
		if full() then
			Kit.limb("Arm" .. s, sh, elbow, 0.055, 0.045, skin)
			Kit.limb("Arm" .. s, elbow, hand, 0.045, 0.04, skin)
		else
			Kit.limb("Arm" .. s, sh, hand, 0.055, 0.045, skin)
		end
		Kit.ell("Hand" .. s, hand + V(0, -0.03, 0.01), V(0.11, 0.11, 0.11), skin)
		if f.hatchet and side > 0 then
			-- a tiny hatchet, held up
			local h0 = hand + V(0.02, -0.1, 0.0)
			local h1 = hand + V(0.0, 0.28, 0.06)
			Kit.limb("Handle", h0, h1, 0.035, 0.03, "wood")
			Kit.limb("AxeHead", h1 + V(0, -0.02, -0.04), h1 + V(0, -0.08, 0.16), 0.06, 0.11, "steel", 0.4, V(1, 0, 0))
		end
	end
	-- the wings: two pairs from the shoulder blades, out and up
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("body")
		local root = V(side * 0.08, 1.14, -0.15)
		J("wing" .. s, "body", root, "wing", side)
		local wk: string = f.wings or "butterfly"
		local wc: string = f.wingC or "white"
		local rimC: string? = f.wingRim
		-- (leaning back, their fronts turned up to the light)
		local nrm = V(0, 0.5, 0.86).Unit
		local function pane(name: string, ang: number, L: number, w: number, c: string, pointed: boolean)
			local d = (CFrame.fromAxisAngle(nrm, R(ang) * side)):VectorToWorldSpace(V(side, 0, 0))
			local z = nrm - d * nrm:Dot(d)
			z = z.Unit
			local y = z:Cross(d)
			local rot = CFrame.fromMatrix(Vector3.zero, d, y, z)
			if pointed then
				-- a long narrow pane that tapers to a point (a dragonfly's)
				if rimC and full() then
					Kit.limb(name .. "Rim", root - z * 0.04, root + d * (L + 0.06) - z * 0.04, w * 0.5 + 0.05, 0.05, rimC, 0.05 / (w + 0.1), z)
				end
				Kit.limb(name, root, root + d * L, w * 0.5, 0.03, c, 0.05 / w, z, nil, f.wingGlow)
			else
				if rimC and full() then
					Kit.ell(name .. "Rim", root + d * L * 0.5 - z * 0.04, V(L + 0.1, w + 0.1, 0.05), rimC, rot)
				end
				Kit.ell(name, root + d * L * 0.5, V(L, w, 0.05), c, rot, nil, f.wingGlow)
			end
			return root + d * L * 0.62, z
		end
		if wk == "butterfly" then
			local c1, z1 = pane("Wing" .. s, 40, 0.96, 0.58, wc, false)
			pane("WingLow" .. s, -22, 0.66, 0.42, wc, false)
			if f.wingSpot then
				dot("WingSpot" .. s, c1, z1, 0.18, f.wingSpot, 0.075, f.spotGlow)
			end
		elseif wk == "dragonfly" then
			pane("Wing" .. s, 30, 1.0, 0.24, wc, true)
			pane("WingLow" .. s, 2, 0.84, 0.22, wc, true)
		else
			pane("Wing" .. s, 44, 0.78, 0.5, wc, false)
			pane("WingLow" .. s, -16, 0.52, 0.36, wc, false)
		end
	end
	-- the head
	Kit.on("body")
	J("head", "body", V(0, 1.22, 0.0), "head")
	local hs: Vector3 = f.head or V(0.86, 0.8, 0.78)
	local hc = V(0, 1.24 + hs.Y * 0.47, 0.04)
	local half = hs / 2
	Kit.ell("Head", hc, hs, skin)
	local e: { number } = f.eye or { 27, 0, 0.28 }
	eyesOn(hc, half, R(e[1]), R(e[2]), e[3], f.iris, if full() then 0.14 else nil, f.ink)
	mouthOn(hc, half, V(0, -0.42, 1), 0.15, f.ink)
	A.face({ color = skin, c = hc, half = half, ink = f.ink, more = A.more(nil, f.faceDetail) })
	-- pointed ears out to the sides
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		Kit.on("head")
		local base = Kit.onEll(hc, half, ID, V(side, 0.08, -0.05)) - V(side * 0.06, 0, 0)
		J("ear" .. s, "head", base, "ear", side)
		local tip = base + V(side * 0.3, 0.16, -0.08)
		Kit.limb("Ear" .. s, base, tip, 0.1, 0.02, f.earC or skin, 0.45, (FWD + V(side * 0.3, 0, 0)).Unit)
	end
	Kit.on("head")
	local hair: string = f.hair or "rays"
	if hair == "rays" then
		-- a sun's crown: rays round the head, long and short in turn, the long ones lit at the tip
		local back = hc + V(0, 0.02, -0.14)
		local tilt = CFrame.Angles(R(-16), 0, 0)
		local nray = if full() then 9 else 5
		for i = 0, nray - 1 do
			local ang = R(-112 + 224 * i / (nray - 1))
			local d = tilt:VectorToWorldSpace(V(math.sin(ang), math.cos(ang), 0))
			local long = i % 2 == 0
			local r0 = (half.X + half.Y) / 2
			local tip = back + d * (r0 + (if long then 0.32 else 0.18))
			Kit.limb("Ray", back + d * (r0 - 0.12), tip, if long then 0.1 else 0.08, 0.025, f.rayC or a, 0.6, FWD, nil, f.rayGlow)
		end
		-- a tuft of hair on top
		Kit.ell("Hair", hc + V(0, hs.Y * 0.32, -0.04), V(hs.X * 0.78, hs.Y * 0.46, hs.Z * 0.8), f.hairC or b, nil, true)
	elseif hair == "spikes" then
		-- spiky frost for hair, swept up and back, and two small horns
		for i, q in { { 0, 1, -0.2, 0.36 }, { 0.5, 0.9, -0.35, 0.3 }, { -0.5, 0.9, -0.35, 0.3 }, { 0.25, 0.7, -0.7, 0.26 }, { -0.25, 0.7, -0.7, 0.26 }, { 0, 0.5, -0.9, 0.24 } } do
			if i <= 4 or full() then
				local d = V(q[1], q[2], q[3]).Unit
				local p = Kit.onEll(hc, half, ID, d)
				Kit.limb("Spike", p - d * 0.1, p + d * q[4] + V(0, 0.04, -0.04), 0.1, 0.015, f.hairC or a)
			end
		end
		for _, side in { -1, 1 } do
			local p = Kit.onEll(hc, half, ID, V(side * 0.55, 0.8, 0.25))
			Kit.limbs("Horn", { p, p + V(side * 0.06, 0.12, 0.0), p + V(side * 0.1, 0.18, -0.08) }, { 0.06, 0.02 }, f.hornC or a, 2)
		end
	elseif hair == "flame" then
		-- a flame of light for hair: tongues of it licking up off the crown, the tallest in the middle curling back at
		-- its tip, all lit, with a bright core low in front
		local base = hc + V(0, hs.Y * 0.34, -0.04)
		local fc: string = f.hairC or a
		for i, q in { { 0, 1, -0.28, 0.38, 0.66 }, { 0.62, 1, -0.2, 0.24, 0.42 }, { -0.62, 1, -0.2, 0.24, 0.44 }, { 0.2, 1, -0.9, 0.26, 0.46 }, { -0.25, 1, -0.85, 0.22, 0.38 } } do
			if i <= 3 or full() then
				local d = V(q[1], q[2], q[3]).Unit
				local at = base + V(q[1] * 0.16, 0, q[3] * 0.1)
				Kit.egg("Flame", at + d * q[5] * 0.42, V(q[4], q[5], q[4] * 0.9), 0.76, fc, A.lie(d), nil, true)
			end
		end
		local tip = base + V(0, 0.58, -0.18)
		Kit.limbs("FlameTip", { tip, tip + V(0, 0.1, -0.08), tip + V(0, 0.08, -0.2) }, { 0.06, 0.02 }, fc, 2, nil, nil, nil, true)
		Kit.ell("FlameCore", base + V(0, 0.12, 0.14), V(0.24, 0.26, 0.16), f.coreC or "screen_on", nil, nil, true)
	end
	if f.tail then
		-- an imp's thin tail, curling up behind, a spade at its tip
		Kit.on("body")
		J("tail1", "body", V(0, 0.84, -0.14), "tail", 0, 1)
		local p0, p1, p2 = V(0, 0.84, -0.14), V(0.04, 0.66, -0.34), V(0.1, 0.72, -0.52)
		Kit.limbs("Tail", { p0, p1, p2 }, { 0.05, 0.035 }, skin, 2)
		J("tail2", "tail1", p2, "tail", 0, 2)
		local p3 = p2 + V(0.04, 0.16, -0.08)
		Kit.limb("Tail", p2, p3, 0.035, 0.03, skin)
		local d = (p3 - p2).Unit
		Kit.limb("Spade", p3, p3 + d * 0.16, 0.1, 0.02, f.tail, 0.4, V(1, 0, 0))
	end
	Kit.on("head")
	return t
end

-- Sunsprite: a gold fairy with a crown of lit sun rays, white butterfly wings with yellow rims and a sunny spot, a skirt of
-- yellow petals and a gem glowing on its chest.
FORMS.sunsprite = {
	h = 2.4,
	wings = "butterfly",
	wingC = "white",
	wingRim = "yellow",
	wingSpot = "yellow",
	skirt = "petal",
	skirtC = "yellow",
	hair = "rays",
	rayC = "yellow",
	rayGlow = true,
	hairC = "orange",
	gem = "yellow",
	eye = { 27, 0, 0.28 },
}
-- Frostling: an ice imp, spiky white frost for hair, two little horns, narrow dragonfly wings like panes of ice, a
-- fringe of icicles for a skirt and a thin tail with a spade tip.
FORMS.frostling = {
	h = 2.3,
	wings = "dragonfly",
	wingC = "white",
	wingRim = "ice",
	skirt = "icicle",
	skirtC = "white",
	hair = "spikes",
	hairC = "white",
	hornC = "white",
	tail = "white",
	eye = { 27, 2, 0.27 },
}
-- Wispkin: a crystal wisp with a flame of light for hair, small round wings, a soft lit hem and a tiny hatchet.
FORMS.wispkin = {
	h = 2.7,
	wings = "round",
	wingC = "white",
	wingRim = "crystal",
	skirt = "hem",
	skirtC = "white",
	hemGlow = true,
	hair = "flame",
	hairC = "white",
	hatchet = true,
	eye = { 27, 0, 0.28 },
}

return { plans = PLANS, forms = FORMS }
