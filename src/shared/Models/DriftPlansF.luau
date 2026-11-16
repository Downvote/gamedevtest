--!strict
-- Body plans sculpted on the smooth solids (Models/DriftAnatomy, Models/DriftKit; GAME_DESIGN 6; the request of
-- 2026-11-15: "can you redo all the creatures and eggs and add alot more extra ones with more variation to them?
-- currently, all of them are modelled using blobs, which is unnatural. reference other models online to see how you
-- should model them"). Each plan returns its Thing, facing +Z with its feet on the ground at y 0; `forms` gives each
-- species of these plans its own variation (Data/Creatures id -> the form its plan reads).
local Kit = require(script.Parent.DriftKit)
local A = require(script.Parent.DriftAnatomy)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full
local UP, FWD = A.UP, A.FWD

type Form = { [string]: any }
-- (a mark on a moth's wing: where along it and across it, its size and colours; a band of colour from the root)
type Spot = { u: number, v: number, d: number, c: string, c2: string?, near: boolean? }
type Layer = { k: number, c: string }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

------------------------------------------------------------------ shared pieces
local lerp = A.lerp
-- (a layer laid on another stands this much proud of it: the picture only draws a part over another where it is more
-- than 0.03 studs nearer)
local LIFT = 0.045

local function sn(side: number): string
	return if side < 0 then "L" else "R"
end

-- The point on a mass's surface in the world direction `d` from its middle (an egg's from its equator), and the
-- surface's normal there.
local function surf(m: A.Mass, d: Vector3): (Vector3, Vector3)
	local sy = m.size.Y
	local o = m.c + m.rot.YVector * (sy / 2 - sy * m.split)
	local dl = m.rot:VectorToObjectSpace(d.Unit)
	local hx, hz = m.size.X / 2, m.size.Z / 2
	local hy = if dl.Y >= 0 then sy * m.split else sy * (1 - m.split)
	local s = 1 / math.sqrt((dl.X / hx) ^ 2 + (dl.Y / hy) ^ 2 + (dl.Z / hz) ^ 2)
	local pl = dl * s
	local nl = V(pl.X / (hx * hx), pl.Y / (hy * hy), pl.Z / (hz * hz)).Unit
	return o + m.rot:VectorToWorldSpace(pl), m.rot:VectorToWorldSpace(nl)
end

-- A patch of another colour on a mass (A.patch: a smaller copy pushed out toward `d`), and the ellipsoid it makes
-- (centre and half sizes; for a face drawn on it).
local function capShape(m: A.Mass, d: Vector3, k: Vector3, out: number): (Vector3, Vector3)
	local inner: A.Mass = { c = m.c, size = V(m.size.X * k.X, m.size.Y * k.Y, m.size.Z * k.Z), rot = m.rot, split = m.split }
	local du = d.Unit
	return m.c + du * (A.reach(m, du) - A.reach(inner, du) + out), inner.size / 2
end
local function cap(name: string, m: A.Mass, d: Vector3, k: Vector3, out: number, color: string): (Vector3, Vector3)
	A.patch(name, m, d, k, out, color)
	return capShape(m, d, k, out)
end

-- A bird's foot: three toes forward and one back (A.birdFoot) up close; on the islands the three front toes only.
local function birdFoot(name: string, at: Vector3, len: number, c: string, claw: string?, fwd: Vector3, web: string?)
	if full() then
		A.birdFoot(name, at, len, c, claw, fwd, web)
		return
	end
	local r = math.max(0.035, len * 0.11)
	local base = at + UP * r
	for _, a in { -32, 0, 32 } do
		local d = (CFrame.fromAxisAngle(UP, R(-a))):VectorToWorldSpace(fwd)
		Kit.limb(name .. "Toe", base, base + d * len, r, r * 0.75, c)
	end
	if web then
		Kit.limb(name .. "Web", base + fwd * len * 0.15, base + fwd * len * 0.8, len * 0.22, len * 0.4, web, 0.18, UP)
	end
end

-- A flat pane (a feather, a flipper, a wing's panel, a fin lobe): a tapered limb pressed flat to about `th` studs,
-- its flat side facing `n`.
local function pane(name: string, a: Vector3, b: Vector3, ra: number, rb: number, n: Vector3, color: string, th: number?, detail: boolean?, neon: boolean?): BasePart?
	local big = math.max(ra, rb, 0.03)
	return Kit.limb(name, a, b, ra, rb, color, math.clamp((th or 0.06) / (2 * big), 0.1, 1), n, detail, neon)
end

-- A direction turned `yaw` degrees toward +X and `pitch` degrees up from `d` (about the world's up, then across).
local function turn(d: Vector3, yaw: number, pitch: number): Vector3
	local h = (CFrame.Angles(0, R(yaw), 0)):VectorToWorldSpace(d)
	local across = h:Cross(UP)
	if across.Magnitude < 1e-4 then
		return h
	end
	return (CFrame.fromAxisAngle(across.Unit, R(-pitch))):VectorToWorldSpace(h).Unit
end

-- One flat right triangle (a single wedge): `sharp` its pointed corner, `corner` the square one, `top` the third.
local function wedge(name: string, sharp: Vector3, corner: Vector3, top: Vector3, th: number, color: string, neon: boolean?): BasePart?
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
	return Kit.part(name, "Wedge", V(th, Hs, Ls), CFrame.fromMatrix(sharp + zu * (Ls / 2) + yu * (Hs / 2), yu:Cross(zu), yu, zu), color, neon)
end

-- A flat triangle a, b, c (a membrane's panel): two right wedges meeting along its height onto its longest side.
local function tri(name: string, a: Vector3, b: Vector3, c: Vector3, th: number, color: string, neon: boolean?)
	local ab, ac, bc = (b - a).Magnitude, (c - a).Magnitude, (c - b).Magnitude
	if ab >= ac and ab >= bc then
		a, c = c, a
	elseif ac >= ab and ac >= bc then
		a, b = b, a
	end
	local u = (c - b).Unit
	local d = b + u * (a - b):Dot(u)
	wedge(name, b, d, a, th, color, neon)
	wedge(name, c, d, a, th, color, neon)
end

------------------------------------------------------------------ bird parts (birds, owls, penguins, ducks)
-- A bird's leg on its own joint: the feathered drumstick from the hip down and back to the heel, a bare stretch of
-- shin on a wading bird, the heel (the joint that bends backward), the scaly shank down to the foot, three toes
-- forward and one back (webbed on a swimmer). o: heel (height), r (the thigh's radius), sr (the shank's), thigh (its
-- colour), c (the bare leg's colour), feather (0..1: how far down the drumstick the feathers reach), toe (length),
-- claw, web, out (the foot's step out from under the hip), fluffy (an owl's feathered leg down to the toes).
local function birdLeg(side: number, phase: number, hip: Vector3, o: Form)
	local s = sn(side)
	J("leg" .. s, "body", hip, "leg", side, phase)
	local heelY = o.heel or hip.Y * 0.42
	local r = o.r or 0.12
	local sr = o.sr or math.max(0.045, r * 0.36)
	local out = (o.out or 0.02) * side
	local heel = V(hip.X + out * 0.6, heelY, hip.Z - (o.back or r * 0.5))
	local foot = V(hip.X + out, 0, hip.Z + (o.fwd or 0.04))
	local fk = o.feather or 0.78
	local knee = lerp(hip, heel, fk)
	Kit.limb("Thigh" .. s, hip, knee, r, r * 0.68, o.thigh or o.c)
	if fk < 0.98 then
		Kit.limb("Shin" .. s, knee, heel, sr * 1.05, sr, o.c)
	end
	if o.fluffy then
		-- (feathered right down: a fluffy boot over the shank)
		Kit.limb("Boot" .. s, heel + V(0, 0.02, 0.01), foot + V(0, 0.08, 0.04), r * 0.62, r * 0.55, o.thigh or o.c)
	else
		Kit.limb("Shank" .. s, heel, foot + V(0, 0.05, 0), sr, sr * 0.88, o.c)
	end
	birdFoot("Foot" .. s, foot, o.toe or 0.2, o.toeC or o.c, o.claw, (FWD + V(side * 0.12, 0, 0)).Unit, o.web)
end

-- A wing folded against the flank on its own joint (pivoting at `sh`, the shoulder): the coverts a flat egg lying on
-- the side centred at `cen`, along `axis` (back toward the tail), `n` its outward face; the long flight feathers (the
-- primaries) in a stack past its end, their tips reaching in over the rump (`cross`) so the two wings' tips meet over
-- the tail. o: len, h (the wing's depth), th, c, edge (the primaries' colour), tip (their tips'), bar (a band across
-- the wing), prim (how many primaries), plen (how far they reach past the coverts), pw (their width), point (pointed
-- tips), cross, spots
local function foldWing(side: number, sh: Vector3, cen: Vector3, axis: Vector3, n: Vector3, o: Form)
	local s = sn(side)
	J("wing" .. s, "body", sh, "wing", side)
	local ax = axis.Unit
	local len, h = o.len or 0.8, o.h or 0.5
	local th = o.th or 0.16
	local rot = A.lie(ax, n)
	local up = n:Cross(ax)
	up = (if up.Y < 0 then -up else up).Unit
	local nn = ax:Cross(up)
	nn = (if nn:Dot(n) < 0 then -nn else nn).Unit
	-- the primaries first (under the coverts' tail), longest at the bottom of the stack
	local np = o.prim or 3
	if not full() then
		np = math.min(np, o.primW or 1)
	end
	local plen = o.plen or 0.42
	local pw = o.pw or h * 0.2
	local cross = o.cross or 0.1
	for i = 1, np do
		local u = if np == 1 then 0 else (i - 1) / (np - 1)
		local lay = nn * (LIFT * (np - i) * 0.7)
		local base = cen + ax * (len * (0.05 + 0.12 * u)) + up * (h * (0.12 - 0.24 * u)) + lay
		local reach = len * 0.5 + plen * (1 - 0.2 * u)
		local tip = cen + ax * reach + up * (h * (0.06 - 0.22 * u)) - V(side * cross * (1 - u * 0.4), 0, 0) + lay
		local col = if i == 1 and o.edge1 then o.edge1 else (o.edge or o.c)
		pane("Primary" .. s, base, tip, pw, pw * (if o.point then 0.16 else 0.66), nn, col, 0.07)
		if o.tip and full() then
			pane("PrimaryTip" .. s, lerp(base, tip, 0.6) + nn * 0.025, tip + nn * 0.025, pw * 0.84, pw * (if o.point then 0.18 else 0.68), nn, o.tip, 0.12)
		end
	end
	Kit.egg("Wing" .. s, cen, V(h, len, th), 0.58, o.c, rot)
	if o.bar then
		-- a band across the coverts (a mallard's blue patch, a wing bar): a thin slice of the wing a little proud
		local bc = cen + ax * (len * (o.barAt or 0.12)) - up * h * 0.08 + nn * (th * 0.5 - 0.01)
		Kit.ell("WingBar" .. s, bc, V(h * 0.66, len * 0.24, 0.07), o.bar, rot, not o.barWorld)
		if o.bar2 and full() then
			Kit.ell("WingBar" .. s, bc + ax * len * 0.14 + nn * 0.01, V(h * 0.6, len * 0.06, 0.08), o.bar2, rot)
		end
	end
	if o.spots and full() then
		for i, sp in o.spots :: { { number } } do
			local p = cen + ax * (len * sp[1]) + up * (h * sp[2]) + nn * (th * 0.5 - 0.01)
			Kit.disc("WingSpot" .. s .. i, p, nn, sp[3] or 0.08, 0.05, o.spotC or "cream", true)
		end
	end
	Kit.on("body")
end

-- A crest of feathers on the head (on the head's joint). kind:
--   "tuft"   two or three short feathers swept back off the crown       "peak"   one tall pointed crest swept back
--   "curl"   a quail's topknot: a plume curling forward over the brow    "crown"  thin shafts standing up, a bead each
--   "flame"  tongues of fire licking up and back                        "plume"  two long thin plumes off the nape
--   "fluff"  a little tuft of down
local function crest(hd: A.Head, o: Form)
	Kit.on("head")
	local kind = o.kind
	local c, half = hd.c, hd.half
	local col = o.c
	local L = o.len or half.Y * 1.0
	local top = hd.c + V(0, half.Y * 0.92, -half.Z * 0.1)
	if kind == "tuft" then
		for i, a in { 0, -14, 14 } do
			if i == 1 or full() then
				local base = top + V(a * 0.006, -0.04, 0.04)
				local tip = base + turn(V(0, 0.55, -1).Unit, a * 1.6, 8) * L * (1 - math.abs(a) / 40)
				pane("Crest", base, tip, L * 0.16, L * 0.03, V(1, 0, 0), if i == 1 then col else (o.c2 or col), 0.08)
			end
		end
	elseif kind == "peak" then
		local base = top + V(0, -0.06, 0.12)
		Kit.limbs("Crest", { base, base + V(0, L * 0.62, -L * 0.15), base + V(0, L * 0.85, -L * 0.62) }, { L * 0.24, L * 0.13, L * 0.025 }, col, 2, 0.45, V(1, 0, 0))
	elseif kind == "curl" then
		local base = top + V(0, -0.04, 0.1)
		local pts = { base, base + V(0, L * 0.5, -L * 0.02), base + V(0, L * 0.8, L * 0.22), base + V(0, L * 0.7, L * 0.5) }
		Kit.limbs("Crest", pts, { L * 0.1, L * 0.08, L * 0.1 }, col, if full() then 3 else 2, 0.7, V(1, 0, 0))
		-- (the plume at its end: a teardrop hanging forward over the brow)
		Kit.limb("CrestTip", pts[3] + V(0, 0, L * 0.12), pts[4] + V(0, -L * 0.18, L * 0.12), L * 0.12, L * 0.2, o.c2 or col, 0.6, V(1, 0, 0))
	elseif kind == "crown" then
		local n = if full() then 5 else 3
		for i = 1, n do
			local u = (i - 1) / (n - 1) * 2 - 1
			local base = Kit.onEll(c, half, CFrame.identity, V(u * 0.55, 1, -0.15)) - V(0, 0.05, 0)
			local dir = (V(u * 0.45, 1, -0.28 - math.abs(u) * 0.1)).Unit
			local Li = L * (1 - math.abs(u) * 0.28)
			local tip = base + dir * Li
			Kit.limb("Crest", base, tip, 0.045, 0.03, o.c2 or col)
			Kit.ell("CrestBead", tip, V(1, 1, 0.75) * (L * 0.24), col, A.lie(V(0, 0, 1), dir))
		end
	elseif kind == "flame" then
		-- tongues of fire: each a flat curl that narrows to a point, the long middle one first
		local tongues = { { 0, 1.0 }, { -0.28, 0.72 }, { 0.28, 0.72 }, { -0.12, 0.85 }, { 0.12, 0.85 } }
		local n = if full() then 5 else 2
		for i = 1, n do
			local tg = tongues[if not full() and i == 2 then 4 else i]
			local x, k = tg[1], tg[2]
			local base = top + V(x * half.X * 0.8, -0.08, 0.16 - math.abs(x) * 0.2)
			local Li = L * k
			local pts = { base, base + V(x * 0.3 * Li, Li * 0.5, -Li * 0.12), base + V(x * 0.42 * Li, Li * 0.82, -Li * 0.5), base + V(x * 0.4 * Li, Li * 0.86, -Li * 0.9) }
			local col2 = if i == 1 then col elseif i <= 3 then (o.c2 or col) else (o.c3 or col)
			Kit.limbs("Crest", pts, { L * 0.17 * k, L * 0.12 * k, L * 0.02 }, col2, 2, 0.5, V(1, 0, 0))
		end
	elseif kind == "plume" then
		for i, x in { -0.04, 0.04 } do
			if i == 1 or full() then
				local base = c + V(x, half.Y * 0.4, -half.Z * 0.75)
				Kit.limbs("Plume", { base, base + V(x * 2, -L * 0.1, -L * 0.55), base + V(x * 3, -L * 0.32, -L * (1 - i * 0.1)) }, { 0.06, 0.04, 0.02 }, col, 2)
			end
		end
	elseif kind == "fluff" then
		local base = top + V(0, -0.02, 0.05)
		Kit.ell("Fluff", base + V(0, L * 0.12, 0), V(L * 0.4, L * 0.36, L * 0.4), col)
		Kit.limb("Fluff", base, base + V(0, L * 0.5, -L * 0.12), L * 0.12, L * 0.04, col, nil, nil, true)
		Kit.limb("Fluff", base + V(0.03, 0, 0), base + V(L * 0.2, L * 0.36, -L * 0.18), L * 0.1, L * 0.03, col, nil, nil, true)
	end
	Kit.on("head")
end

------------------------------------------------------------------ the bird
-- A small bird standing: a teardrop of a body with the narrow end at the tail, tipped up at the breast; a round head
-- of its own with the beak in two halves (the lower one drops); folded wings lying along the flanks with the flight
-- feathers crossing over the rump; feathered thighs and thin bare legs with a heel, three toes forward and one back.
-- The form sets the rest: the legs' length, a neck (a heron's S), the beak's length and kind, a crest, the wings'
-- length, the tail (a fan, a swallow's fork, a fish's fin, long plumes or streamers) and the markings.
PLANS.bird = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local legH = (f.legH or 0.36) * S -- how far the belly stands off the ground
	local L, W, T = (f.len or 1.38) * S, (f.wide or 0.98) * S, (f.tall or 0.94) * S
	local pitch = f.pitch or 14
	local neckLen = f.neck or 0
	local hs = (f.head or 0.84) * (if neckLen > 0 then 1 else S)
	local floatY = f.float or 0
	local fly = f.gait == "fly"
	local H = f.h or 2.1
	local t = Kit.new("bird", H, f.r or 0.9, f.gait or "biped")
	local under = f.under or A.under(b)
	local back = f.back or b -- the mantle: the back's colour
	local wingC = f.wing or b
	local beakC = f.beak or "orange"
	local legC = f.legs or "orange"
	local ink = A.ink(b, a)

	local by = legH + T * 0.5 + floatY
	J("body", nil, V(0, by, 0), "body")
	local d = V(0, math.sin(R(pitch)), math.cos(R(pitch)))
	local _, body = A.body("Body", V(0, by, (f.bodyZ or -0.24) * S), d, L, W, T, f.split or 0.6, b)
	-- the breast and belly, paler: a cap on the front and underside
	if under ~= b then
		A.patch("Breast", body, V(0, -0.6, 1), f.breastK or V(0.84, 0.86, 0.84), 0.02, under)
	end
	if back ~= b then
		A.patch("Mantle", body, V(0, 1, -0.3), V(0.78, 0.84, 0.8), 0.02, back)
	end
	if f.throat and f.throatK then
		A.patch("Throat", body, V(0, 0.45, 1), f.throatK, 0.03, f.throat)
	end
	if f.chest then
		-- a round mark on the breast (a sun on a sky bird, a flame on a phoenix)
		local p, nrm = surf(body, V(0, 0.05, 1))
		Kit.ell("ChestMark", p - nrm * 0.02, V(0.36, 0.36, 0.12) * S, f.chest, A.lie(UP, nrm))
		if full() and f.chest2 then
			Kit.ell("ChestMark", p + nrm * 0.03, V(0.2, 0.2, 0.1) * S, f.chest2, A.lie(UP, nrm))
		end
	end
	if f.speckle and full() then
		-- speckles down the back and flanks
		for i, sp in { { 0.6, 0.6, -0.1 }, { -0.6, 0.6, -0.1 }, { 0.35, 0.9, -0.5 }, { -0.35, 0.9, -0.5 }, { 0.75, 0.2, -0.5 }, { -0.75, 0.2, -0.5 }, { 0, 1, 0 }, { 0, 0.8, -0.7 } } do
			local p, nrm = surf(body, V(sp[1], sp[2], sp[3]))
			Kit.disc("Speckle" .. i, p, nrm, 0.08 * S, 0.05, f.speckle, true)
		end
	end
	if f.streaks and full() then
		-- dark streaks down the breast
		for i, sp in { { 0.22, 0.1 }, { -0.22, 0.1 }, { 0.08, -0.25 }, { -0.08, -0.25 }, { 0.36, -0.3 }, { -0.36, -0.3 } } do
			local p, nrm = surf(body, V(sp[1], sp[2], 1))
			Kit.limb("Streak" .. i, p + nrm * 0.03, p + nrm * 0.03 - UP * 0.12 * S, 0.035, 0.025, f.streaks, 0.5, nrm, true)
		end
	end
	if f.dorsal then
		-- a fish's fin standing on the back
		local p0 = surf(body, V(0, 1, 0.1))
		local p1 = surf(body, V(0, 1, -0.7))
		local top = lerp(p0, p1, 0.8) + V(0, 0.36 * S, -0.06 * S)
		pane("Dorsal", p0 - UP * 0.05, top, 0.06, 0.03, V(1, 0, 0), f.dorsal, 0.07)
		pane("Dorsal", lerp(p0, p1, 0.55) - UP * 0.05, top, 0.12, 0.03, V(1, 0, 0), f.dorsal, 0.07)
		if full() then
			Kit.limb("DorsalRay", lerp(p0, p1, 0.35) + V(LIFT, 0, 0), lerp(lerp(p0, p1, 0.35), top, 0.8) + V(LIFT, 0, 0), 0.025, 0.02, "white")
			Kit.limb("DorsalRay", lerp(p0, p1, 0.35) - V(LIFT, 0, 0), lerp(lerp(p0, p1, 0.35), top, 0.8) - V(LIFT, 0, 0), 0.025, 0.02, "white")
		end
	end

	-- the legs
	local legOut = (f.legOut or 0.03) * S
	local hipY = legH + T * 0.24 + floatY
	for _, side in { -1, 1 } do
		local hip = V(side * W * 0.22, hipY, (f.hipZ or -0.12) * S)
		if fly then
			-- (hanging in the air: the legs tucked up under the belly, the toes curled)
			J("leg" .. sn(side), "body", hip, "leg", side, if side < 0 then 0 else 0.5)
			local heel = hip + V(side * 0.03, -0.26, -0.08)
			Kit.limb("Thigh" .. sn(side), hip, lerp(hip, heel, 0.7), 0.1 * S, 0.07 * S, f.thigh or under)
			local foot = heel + V(0, -0.14, 0.08)
			Kit.limb("Shank" .. sn(side), heel, foot, 0.04, 0.035, legC)
			for _, yaw in { -25, 0, 25 } do
				local dd = turn(V(0, -0.5, 1).Unit, yaw, 0)
				Kit.limb("Toe" .. sn(side), foot, foot + dd * 0.12, 0.035, 0.025, legC)
			end
		else
			birdLeg(side, if side < 0 then 0 else 0.5, hip, {
				heel = f.heel or (legH * 0.5 + 0.05),
				r = (f.thighR or 0.12) * S,
				sr = (f.shankR or 0.045) * S,
				thigh = f.thigh or under,
				c = legC,
				feather = f.feather or 0.8,
				toe = (f.toe or 0.2) * S,
				claw = f.claw or A.shade(legC),
				web = f.web,
				out = legOut,
				back = f.heelBack,
				fluffy = f.fluffy,
			})
		end
		Kit.on("body")
	end

	-- the tail, out of the rump
	local tailBase = surf(body, -d) + d * 0.14 * S
	local tu = R(f.tailUp or 20)
	local td = V(0, math.sin(tu), -math.cos(tu))
	local tk = f.tail or "fan"
	local tc = f.tailC or wingC
	J("tail", "body", tailBase, "tail", 0, 1)
	local tl = (f.tailLen or 0.7) * S
	local tw = (f.tailW or 0.14) * S
	local flatN = (UP - td * UP:Dot(td)).Unit
	if tk == "fan" or tk == "notch" then
		local n = if full() then (f.tailN or 5) else 3
		local spread = f.spread or 36
		for i = 1, n do
			local u = (i - 1) / (n - 1) * 2 - 1
			local dd = turn(td, u * spread * 0.5, 0)
			local li = tl * (if tk == "notch" then (1 + math.abs(u) * 0.2) else (1 - math.abs(u) * 0.14))
			local lift = flatN * (LIFT * (1 - math.abs(u)))
			pane("TailFeather", tailBase + lift, tailBase + dd * li + lift, tw * 0.5, tw * (if tk == "notch" then 0.45 else 0.85), flatN, if math.abs(u) > 0.6 and f.tailEdge then f.tailEdge else tc, 0.06)
		end
		if f.tailTip and full() then
			for _, u in { -0.5, 0.5 } do
				local dd = turn(td, u * spread * 0.5, 0)
				pane("TailTip", tailBase + dd * tl * 0.72 + flatN * LIFT * 1.6, tailBase + dd * tl * 0.98 + flatN * LIFT * 1.6, tw * 0.75, tw * 0.85, flatN, f.tailTip, 0.06)
			end
		end
	elseif tk == "fork" then
		-- a swallow's: a short fan in the middle and two long streamers out to the sides
		for _, u in { -1, 0, 1 } do
			if u == 0 or full() then
				local dd = turn(td, u * 8, 0)
				pane("TailFeather", tailBase + flatN * LIFT, tailBase + dd * tl * 0.55 + flatN * LIFT, tw * 0.5, tw * 0.55, flatN, tc, 0.06)
			end
		end
		for _, side in { -1, 1 } do
			local dd = turn(td, side * (f.forkA or 16), 0)
			local tip = tailBase + dd * tl * (f.forkLen or 1.6)
			Kit.limbs("TailStreamer", { tailBase, lerp(tailBase, tip, 0.5) + V(side * 0.03, 0, 0), tip }, { tw * 0.5, tw * 0.32, tw * 0.06 }, f.forkC or tc, 2, 0.45, flatN)
		end
	elseif tk == "fin" then
		-- a fish's tail: a narrow wrist, then two lobes standing up and down, rays across them
		local wrist = tailBase + td * tl * 0.3
		Kit.limb("TailWrist", tailBase, wrist, tw * 0.95, tw * 0.55, b, 0.75, V(1, 0, 0))
		local up = flatN
		local tipU = wrist + td * tl * 0.5 + up * tl * 0.55
		local tipD = wrist + td * tl * 0.55 - up * tl * 0.3
		pane("TailLobe", wrist, tipU, tw * 0.75, tw * 0.25, V(1, 0, 0), tc, 0.08)
		pane("TailLobe", wrist, tipD, tw * 0.75, tw * 0.25, V(1, 0, 0), tc, 0.08)
		pane("TailLobe", wrist, wrist + td * tl * 0.36, tw * 0.8, tw * 0.62, V(1, 0, 0), tc, 0.08)
		if full() then
			for _, k in { 0.25, 0.6 } do
				for _, sx in { -1, 1 } do
					Kit.limb("TailRay", wrist + V(sx * LIFT, 0, 0), lerp(tipU, tipD, k) + V(sx * LIFT, 0, 0), 0.03, 0.02, "white")
				end
			end
		end
	elseif tk == "plumes" or tk == "streamers" then
		-- long plumes: a short fan at the root, then two or three long feathers sweeping back and down, curling up at the
		-- ends (their far halves on a second joint, so they trail)
		for i = 1, (if full() then 5 else 0) do
			local u = (i - 1) / 4 * 2 - 1
			local dd = turn(td, u * 24, 0)
			pane("TailFeather", tailBase + flatN * LIFT * 0.6, tailBase + dd * tl * 0.55, tw * 0.5, tw * 0.75, flatN, tc, 0.06)
		end
		local mids = {}
		local list: { number } = if tk == "plumes" then { -1, 0, 1 } else { -1, 1 }
		for _, u in list do
			local dd = turn(td, u * (if tk == "plumes" then 14 else 10), 6)
			local m = tailBase + dd * tl * 0.7
			table.insert(mids, { u = u, m = m, dd = dd })
			Kit.limb("Plume", tailBase, m, tw * 0.4, tw * 0.32, f.plumeC or tc, 0.5, flatN)
		end
		J("tail2", "tail", mids[1].m - V(mids[1].u * 0.05, 0, 0), "tail", 0, 2)
		for _, q in mids do
			local L2 = tl * (f.plumeLen or 1.3) * (if q.u == 0 then 1.15 else 1)
			local p1 = q.m + q.dd * L2 * 0.45 - UP * L2 * 0.3 + V(q.u * 0.1, 0, 0)
			local p2 = q.m + q.dd * L2 * 0.85 - UP * L2 * 0.22 + V(q.u * 0.2, 0, 0)
			local p3 = p2 + V(q.u * 0.05, L2 * 0.26, -L2 * 0.1)
			if tk == "plumes" then
				Kit.limbs("Plume", { q.m, p1, p2, p3 }, { tw * 0.32, tw * 0.5, tw * 0.2 }, f.plumeC or tc, if full() then 3 else 2, 0.5, flatN)
				Kit.limb("PlumeTip", lerp(p2, p3, 0.2), p3 + V(0, 0.08, -0.04), tw * 0.55, tw * 0.1, f.plumeTip or tc, 0.5, V(1, 0, 0))
			else
				Kit.limbs("Streamer", { q.m, p1, p2 }, { tw * 0.24, tw * 0.2, tw * 0.18 }, f.plumeC or tc, if full() then 3 else 2, 0.4, flatN)
				-- the racket: a round vane at the end
				Kit.ell("StreamerTip", p2 + V(0, 0.06, -0.12), V(tw * 1.5, tw * 2.6, tw * 0.6), f.plumeTip or tc, A.lie(V(0, 0.5, -1), V(q.u, 0, 0)))
			end
		end
		Kit.on("tail")
	elseif tk == "long" then
		-- a long narrow tail (a long-tailed tit's): two feathers side by side, a darker middle
		for _, side in { -1, 1 } do
			local dd = turn(td, side * 3, 0)
			pane("TailFeather", tailBase + V(side * tw * 0.3, 0, 0), tailBase + dd * tl + V(side * tw * 0.3, 0, 0), tw * 0.45, tw * 0.4, flatN, tc, 0.06)
		end
		if f.tailEdge then
			pane("TailMid", tailBase + flatN * LIFT, tailBase + td * tl * 0.95 + flatN * LIFT, tw * 0.3, tw * 0.25, flatN, f.tailEdge, 0.06)
		end
	end
	Kit.on("body")

	-- the wings, folded along the flanks
	for _, side in { -1, 1 } do
		local p, nrm = surf(body, V(side, f.wingUp or 0.3, f.wingFwd or -0.25))
		local sh = surf(body, V(side, 0.55, 0.5))
		local ax = turn(-d, -side * (f.wingIn or 3), -(f.wingDroop or 4))
		local wl = (f.wingLen or 0.92) * S
		local th = 0.16 * S
		foldWing(side, sh, p + nrm * th * 0.15 - ax * wl * 0.06, ax, (nrm + V(side * 0.5, 0, 0)).Unit, {
			len = wl,
			h = (f.wingH or 0.54) * S,
			th = th,
			c = wingC,
			edge = f.prim or wingC,
			edge1 = f.prim1,
			tip = f.primTip,
			bar = f.bar,
			bar2 = f.bar2,
			barAt = f.barAt,
			prim = f.primN or 3,
			primW = f.primW,
			plen = (f.plen or 0.4) * S,
			pw = (f.pw or 0.1) * S,
			point = f.point,
			cross = (f.cross or 0.1) * S,
			spots = f.wingSpots,
			spotC = f.wingSpotC,
		})
	end

	-- the neck (a heron's S), or a short thick one: the head sits on the shoulders
	local chest = surf(body, V(0, 0.75, 1))
	local headParent = "body"
	local hc: Vector3
	if neckLen > 0 then
		J("neck", "body", chest - V(0, 0.1, 0.05), "neck")
		local n0 = chest - V(0, 0.12, 0.06)
		local n1 = n0 + V(0, neckLen * 0.42, neckLen * 0.2)
		local n2 = n0 + V(0, neckLen * 0.66, -neckLen * 0.04)
		local n3 = n0 + V(0, neckLen * 0.98, neckLen * 0.08)
		Kit.limbs("Neck", { n0, n1, n2, n3 }, { 0.2 * S, 0.12 * S, 0.11 * S }, f.neckC or under, if full() then 4 else 2)
		if f.neckStripe and full() then
			Kit.limbs("NeckStripe", { lerp(n0, n1, 0.3) + V(0, 0, 0.13 * S), n1 + V(0, 0, 0.1 * S), lerp(n1, n2, 0.6) + V(0, 0, 0.1 * S) }, { 0.04, 0.03, 0.025 }, f.neckStripe, 3)
		end
		hc = n3 + V(0, hs * 0.3, hs * 0.12)
		headParent = "neck"
	else
		hc = chest + V(0, hs * 0.44 + (f.headUp or 0), -hs * 0.06 + (f.headFwd or 0))
		-- (a short thick neck under the head, so it sits on the shoulders with a waist)
		Kit.limb("Neck", chest - V(0, 0.12, 0.14), hc - V(0, hs * 0.22, hs * 0.14), hs * 0.3, hs * 0.28, f.neckC or b)
		if under ~= b and f.throatUnder ~= false then
			Kit.limb("Throat", chest + V(0, -0.12, 0.08), hc + V(0, -hs * 0.26, hs * 0.12), hs * 0.27, hs * 0.25, f.throat or under, nil, nil, true)
		end
	end
	local hd = A.head({
		c = hc,
		size = V(hs * (f.headW or 1.02), hs * 0.96, hs),
		color = f.headC or b,
		parent = headParent,
		pivot = if neckLen > 0 then hc - V(0, hs * 0.3, hs * 0.1) else chest - V(0, 0.05, 0.1),
		muzzle = "beak",
		beak = beakC,
		mlen = (f.beakLen or 0.3) * (if neckLen > 0 then 1 else S),
		mw = (f.beakW or 0.2) * (if neckLen > 0 then 1 else S),
		mdrop = f.beakDrop or hs * 0.06,
		eye = { R(f.eyeSpread or 38), R(f.eyeLift or 8), (f.eye or 0.26) * hs / 0.82 },
		iris = A.iris(a, "blue"),
		ink = if A.isDark(f.headC or b) then ink else nil,
		blush = f.blush,
		mouth = false,
		-- (its own crest, where it has one)
		face = A.more(if f.crest then { crown = false } else nil, f.faceDetail),
	})
	if f.cheek then
		-- pale cheeks or a face mask
		for _, side in { -1, 1 } do
			local p, nrm = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side * 0.8, -0.35, 0.45))
			Kit.ell("Cheek" .. sn(side), p - nrm * 0.07, V(hs * 0.44, hs * 0.42, hs * 0.24), f.cheek, A.lie(UP, nrm))
		end
	end
	if f.cap then
		-- a cap of another colour over the crown and nape
		A.patch("Cap", hd.mass, V(0, 1, -0.4), V(0.9, 0.8, 0.9), 0.02, f.cap)
	end
	if f.beakSpot and full() then
		Kit.on("jaw")
		local bl = (f.beakLen or 0.3) * S
		for _, side in { -1, 1 } do
			local p = hd.c + V(side * 0.045 * S, -hs * 0.06 - bl * 0.3, hs * 0.5 * 0.55 + bl * 0.62)
			Kit.ell("BeakSpot", p, V(0.07, 0.08, 0.1), f.beakSpot)
		end
		Kit.on("head")
	end
	if f.collar then
		-- a ring round the neck where the head meets the body
		Kit.on("body")
		local p = lerp(chest - V(0, 0.12, 0.1), hc - V(0, hs * 0.2, hs * 0.08), 0.35)
		Kit.limb("Collar", p - V(0, 0.03, 0), p + V(0, 0.04, 0), hs * 0.39, hs * 0.39, f.collar, 0.9, UP)
		Kit.on("head")
	end
	if f.crest then
		crest(hd, { kind = f.crest, c = f.crestC or a, c2 = f.crestC2, c3 = f.crestC3, len = (f.crestLen or 0.45) * (if neckLen > 0 then 1 else S) })
	end
	return t
end

FORMS.gullfin = {
	-- a gull's white with blue wings, a hooked yellow beak with a red spot, webbed feet, a fish's tail and a fin on its back
	wing = "blue",
	prim = "jeans",
	primTip = "night",
	wingSpots = { { 0.95, -0.1, 0.07 } },
	wingSpotC = "white",
	under = "white",
	beak = "yellow",
	beakSpot = "berry_red",
	beakLen = 0.4,
	beakW = 0.22,
	tail = "fin",
	tailC = "blue",
	tailLen = 0.78,
	tailW = 0.17,
	tailUp = 36,
	dorsal = "blue",
	web = "orange",
	toe = 0.22,
	eye = 0.26,
}

FORMS.breezle = {
	-- a swallow: sleek and low, a blue back and cap, a rusty throat, long pointed wings, a deep forked tail
	len = 1.22,
	wide = 0.74,
	tall = 0.76,
	pitch = 18,
	back = "blue",
	wing = "blue",
	prim = "jeans",
	cap = "blue",
	throat = "clay",
	point = true,
	plen = 0.62,
	primN = 3,
	primW = 2,
	cross = 0.16,
	tail = "fork",
	tailC = "blue",
	tailLen = 0.6,
	forkLen = 1.75,
	forkA = 15,
	tailUp = 6,
	legH = 0.34,
	beakLen = 0.18,
	beakW = 0.16,
	legs = "black",
	head = 0.8,
}

FORMS.cirrup = {
	-- a round singing bird: plump as a ball, a forward curling topknot, white cheeks, a short cone of a beak
	len = 1.2,
	wide = 1.08,
	tall = 1.04,
	split = 0.55,
	pitch = 24,
	under = "white",
	cheek = "white",
	crest = "curl",
	crestC = "blue",
	crestC2 = "white",
	crestLen = 0.78,
	beakLen = 0.2,
	beakW = 0.2,
	beak = "slate",
	wing = "blue",
	prim = "blue",
	bar = "white",
	tail = "fan",
	tailC = "blue",
	tailLen = 0.5,
	tailUp = 30,
	legs = "slate",
	head = 0.9,
	headUp = -0.06,
}

FORMS.tidepip = {
	-- a sandpiper: small, long thin legs, a long thin straight beak, a speckled sand back, a white belly
	scale = 0.82,
	legH = 0.78,
	heel = 0.36,
	feather = 0.45,
	pitch = 14,
	under = "white",
	speckle = "sand_dark",
	wing = "sand_dark",
	prim = "wood_dark",
	beak = "black",
	beakLen = 0.62,
	beakW = 0.11,
	beakDrop = 0.02,
	legs = "straw",
	tail = "notch",
	tailC = "sand_dark",
	tailLen = 0.4,
	tailUp = 8,
	head = 0.72,
	h = 1.9,
}

FORMS.ashwing = {
	-- (its face: marks of its own)
	faceDetail = { marks = { freckles = "lava", glow = true } },
	-- a phoenix: a flame of a gold crest, gold-edged wings, long plumes with gold tips, a burning gold breast
	crest = "flame",
	crestC = "gold",
	crestC2 = "orange",
	crestC3 = "yellow",
	crestLen = 0.62,
	under = "orange",
	chest = "gold",
	chest2 = "yellow",
	wing = "berry_red",
	prim = "gold",
	primTip = "orange",
	point = true,
	plen = 0.5,
	tail = "plumes",
	tailC = "berry_red",
	plumeC = "berry_red",
	plumeTip = "gold",
	tailLen = 0.7,
	plumeLen = 1.4,
	tailUp = 10,
	beak = "gold",
	legs = "clay",
	h = 2.4,
}

FORMS.stiltbeak = {
	-- a heron: very long legs, a long S of a neck, a straight dagger of a beak, a black plume off the nape
	legH = 1.3,
	heel = 0.62,
	feather = 0.4,
	thighR = 0.1,
	shankR = 0.05,
	len = 1.0,
	wide = 0.66,
	tall = 0.66,
	pitch = 22,
	neck = 0.8,
	neckC = "white",
	neckStripe = "black",
	under = "white",
	head = 0.62,
	headC = "white",
	cap = "black",
	crest = "plume",
	crestC = "black",
	crestLen = 0.6,
	beak = "yellow",
	beakLen = 0.62,
	beakW = 0.13,
	beakDrop = 0.0,
	wing = "steel",
	prim = "steel_dark",
	tail = "fan",
	tailC = "steel",
	tailLen = 0.34,
	tailUp = 0,
	legs = "yellow",
	toe = 0.28,
	h = 2.9,
	r = 1.0,
}

FORMS.sweepwing = {
	-- a swift: a sleek little torpedo, scythe wings far longer than the body crossing behind it, a short notched tail
	len = 1.5,
	wide = 0.8,
	tall = 0.76,
	pitch = 8,
	legH = 0.3,
	bodyZ = -0.34,
	under = "cream",
	streaks = "wood_dark",
	wing = "wood_dark",
	prim = "wood_dark",
	primTip = "hair_brown",
	point = true,
	wingLen = 0.9,
	wingH = 0.46,
	plen = 1.25,
	primN = 3,
	primW = 2,
	cross = 0.3,
	wingDroop = 2,
	tail = "notch",
	tailC = "wood_dark",
	tailLen = 0.42,
	tailUp = 6,
	beak = "black",
	beakLen = 0.16,
	beakW = 0.17,
	legs = "slate",
	head = 0.74,
	headFwd = 0.06,
	throat = "cream",
}

FORMS.cloudpip = {
	-- a puff of a bird too light to land: a ball of white down, pink cheeks and wing edges, a tiny black beak, a long
	-- narrow tail; it hangs in the air (its feet tucked up, fluttering)
	gait = "fly",
	float = 0.5,
	len = 1.1,
	wide = 1.1,
	tall = 1.06,
	split = 0.52,
	pitch = 20,
	under = "white",
	blush = true,
	crest = "fluff",
	crestC = "white",
	crestLen = 0.32,
	beak = "black",
	beakLen = 0.12,
	beakW = 0.13,
	wing = "white",
	prim = "pink",
	plen = 0.22,
	tail = "long",
	tailC = "white",
	tailEdge = "pink",
	tailLen = 0.8,
	tailW = 0.12,
	tailUp = 12,
	legH = 0.3,
	legs = "pink",
	head = 0.86,
	headUp = -0.14,
	h = 2.2,
}

FORMS.skyherald = {
	-- a sky bird of the dawn: a crown of beaded shafts, gold-edged wings, a sun on its breast and two long gold
	-- streamers with round vanes at the ends
	scale = 1.12,
	crest = "crown",
	crestC = "gold",
	crestC2 = "white",
	crestLen = 0.48,
	under = "white",
	chest = "gold",
	chest2 = "yellow",
	wing = "window",
	prim = "gold",
	primTip = "yellow",
	plen = 0.5,
	primN = 4,
	tail = "streamers",
	tailC = "window",
	plumeC = "gold",
	plumeTip = "gold",
	tailLen = 0.62,
	plumeLen = 1.6,
	tailUp = 12,
	beak = "gold",
	legs = "gold",
	h = 2.7,
	r = 1.1,
}

------------------------------------------------------------------ the owl
-- An owl: a stout upright egg of a body, a broad head sitting right on it, a round facial disc (a heart on a barn owl)
-- ringed by a darker rim with the eyes in it, a short hooked beak, ear tufts on some, big rounded wings folded down the
-- sides, a short tail, feathered legs and big dark talons. The form picks the tufts (feathers, twigs, crystals, a pair
-- of tall swept horns or none), the face's shape, the markings and extras.
PLANS.owl = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local t = Kit.new("owl", f.h or 2.3, f.r or 0.9, "biped")
	local under = f.under or A.under(b)
	local discC = f.disc or under
	local rimC = f.rim or a
	local wingC = f.wing or b
	local legH = (f.legH or 0.26) * S
	local BW, BH, BD = (f.wide or 1.08) * S, (f.tall or 1.12) * S, (f.deep or 0.96) * S
	local by = legH + BH * 0.46
	J("body", nil, V(0, by, 0), "body")
	local _, body = A.body("Body", V(0, by, -0.02), V(0, 1, 0.16).Unit, BH, BW, BD, f.split or 0.44, b)
	-- the pale breast, barred or spotted
	A.patch("Breast", body, V(0, -0.15, 1), V(0.8, 0.84, 0.8), 0.02, under)
	if f.bars and full() then
		for row = 0, 2 do
			local n = if row % 2 == 0 then 3 else 2
			for i = 1, n do
				local x = (i - (n + 1) / 2) * 0.32
				local p, nrm = surf(body, V(x, 0.25 - row * 0.32, 1))
				local right = UP:Cross(nrm).Unit
				for _, sx in { -1, 1 } do
					Kit.limb("Bar", p + nrm * 0.03 + right * sx * 0.07 + UP * 0.03, p + nrm * 0.03 - UP * 0.02, 0.03, 0.025, f.bars, 0.5, nrm)
				end
			end
		end
	end
	if f.bolt then
		-- a lightning bolt down the breast
		local pts = { V(0.08, 0.35, 1), V(-0.12, 0.05, 1), V(0.1, 0, 1), V(-0.08, -0.35, 1) }
		local q: { Vector3 } = {}
		for i, d in pts do
			local p, nrm = surf(body, d)
			q[i] = p + nrm * 0.03
		end
		for i = 1, 3 do
			Kit.limb("Bolt", q[i], q[i + 1], 0.06 - i * 0.008, 0.05 - i * 0.008, f.bolt, 0.4, V(0, 0, 1), nil, f.boltGlow)
		end
	end
	if f.glyphs and full() then
		-- old marks on the breast: a ring, a bar and a little arrow
		local p, nrm = surf(body, V(0, 0.05, 1))
		Kit.disc("Glyph", p + nrm * 0.01, nrm, 0.18, 0.05, f.glyphs, true)
		Kit.disc("Glyph", p + nrm * 0.02, nrm, 0.1, 0.05, under, true)
		local p2, n2 = surf(body, V(0, -0.35, 1))
		local r2 = UP:Cross(n2).Unit
		Kit.limb("Glyph", p2 + n2 * 0.03 - r2 * 0.12, p2 + n2 * 0.03 + r2 * 0.12, 0.03, 0.03, f.glyphs, 0.5, n2)
	end
	if f.shards then
		-- crystal shards growing out of the back
		for i, sd in { { 0, 0.55, -1, 0.42 }, { -0.35, 0.3, -1, 0.3 }, { 0.35, 0.3, -1, 0.3 } } do
			if i == 1 or full() then
				local p, nrm = surf(body, V(sd[1], sd[2], sd[3]))
				local dir = (nrm + V(0, 0.6, 0)).Unit
				Kit.limb("Shard", p - nrm * 0.08, p + dir * sd[4] * S, 0.11 * S, 0.02, f.shards, 0.7, V(1, 0, 0))
			end
		end
	end

	-- the legs: short and feathered, big talons
	for _, side in { -1, 1 } do
		local hip = V(side * BW * 0.22, legH + BH * 0.18, 0.08)
		if f.twigLegs then
			J("leg" .. sn(side), "body", hip, "leg", side, if side < 0 then 0 else 0.5)
			local foot = V(side * BW * 0.24, 0, 0.14)
			Kit.limb("Leg" .. sn(side), hip, foot + V(0, 0.06, 0), 0.07, 0.05, f.twigLegs)
			birdFoot("Foot" .. sn(side), foot, 0.22, f.twigLegs, nil, FWD)
		else
			birdLeg(side, if side < 0 then 0 else 0.5, hip, {
				heel = legH * 0.6 + 0.04,
				r = 0.15 * S,
				thigh = f.legC or under,
				c = f.toes or "orange",
				feather = 1,
				fluffy = true,
				toe = 0.2 * S,
				claw = f.talon or "black",
				out = 0.03,
				fwd = 0.1,
			})
		end
		Kit.on("body")
	end

	-- a short tail under the wings
	local tb = surf(body, V(0, -0.55, -1)) + V(0, 0.06, 0.12)
	J("tail", "body", tb, "tail", 0, 1)
	local td = V(0, -0.35, -1).Unit
	local tn = (UP - td * UP:Dot(td)).Unit
	for i, u in { 0, -1, 1 } do
		if i == 1 or full() then
			local dd = turn(td, u * 18, 0)
			pane("Tail", tb + tn * LIFT * (if u == 0 then 1 else 0), tb + dd * 0.42 * S + tn * LIFT * (if u == 0 then 1 else 0), 0.08 * S, 0.12 * S, tn, f.tailC or wingC, 0.06)
		end
	end
	if f.twigTail then
		for _, u in { -1, 1 } do
			local dd = turn(td, u * 12, -6)
			Kit.limb("Twig", tb, tb + dd * 0.62 * S, 0.04, 0.025, f.twigTail)
		end
	end
	Kit.on("body")

	-- the wings, big and round, folded down the sides
	for _, side in { -1, 1 } do
		local p, nrm = surf(body, V(side, 0.08, -0.2))
		local sh = surf(body, V(side, 0.6, 0.1))
		local ax = V(side * -0.08, -0.8, -0.6).Unit
		local th = 0.18 * S
		foldWing(side, sh, p + nrm * th * 0.18 + V(0, 0.04, 0), ax, (nrm + V(side * 0.4, 0, 0)).Unit, {
			len = (f.wingLen or 0.95) * S,
			h = (f.wingH or 0.66) * S,
			th = th,
			c = wingC,
			edge = f.prim or wingC,
			tip = f.primTip,
			prim = 3,
			plen = 0.22 * S,
			pw = 0.13 * S,
			cross = 0.02,
			bar = f.wingBar,
			barAt = -0.1,
			spots = f.wingSpots or { { -0.2, 0.15, 0.09 }, { 0.05, -0.1, 0.08 }, { 0.25, 0.12, 0.08 }, { -0.05, 0.3, 0.07 } },
			spotC = f.spotC or under,
		})
		if f.bark and full() then
			-- (bark lines down the wing)
			for k = -1, 1 do
				local q = p + nrm * (th * 0.68) + V(0, 0.05 + k * 0.03, 0)
				Kit.limb("Bark" .. sn(side), q + V(0, 0.2, 0.08 + k * 0.12), q + V(0, -0.25, -0.08 + k * 0.12), 0.025, 0.02, f.bark, 0.5, nrm)
			end
		end
	end

	-- the head, broad and round, sitting on the body
	local hs = (f.head or 1.0) * S
	local top = surf(body, V(0, 1, 0.1))
	local hc = top + V(0, hs * 0.28, 0.06)
	J("head", "body", top - V(0, 0.08, 0), "head")
	local hsz = V(hs * (f.headW or 1.04), hs * 0.86, hs * 0.86)
	local hh = hsz / 2
	local _, hm = A.blob("Head", hc, hsz, b)
	local ink = A.ink(b, a)
	-- the facial disc: a dark rim, then the pale face over it (round, or a heart of two lobes), each a flattened copy
	-- of the head pushed out at the front so it curves with it; the eyes sit on the face
	local heart = f.face == "heart"
	local faceD = V(0, -0.06, 1)
	if heart then
		for _, side in { -1, 1 } do
			local d0 = V(side * 0.42, 0.04, 1)
			cap("FaceRim" .. sn(side), hm, d0, V(0.74, 0.92, 0.5), 0, rimC)
			cap("Face" .. sn(side), hm, d0, V(0.66, 0.86, 0.5), 0.045, discC)
		end
		cap("FaceChin", hm, V(0, -0.45, 1), V(0.4, 0.4, 0.6), 0.03, discC)
	else
		cap("FaceRim", hm, faceD, V(0.96, 0.9, 0.5), 0, rimC)
		cap("Face", hm, faceD, V(0.91, 0.86, 0.5), 0.045, discC)
	end
	-- the eyes on the face (the face's surface: the round disc's, or one just as far out across the heart's lobes)
	local fcen, fhalf = capShape(hm, faceD, V(0.91, 0.86, 0.5), if heart then 0.035 else 0.045)
	Kit.faceOn(fcen, fhalf)
	local favg = (fhalf.X + fhalf.Y + fhalf.Z) / 3
	Kit.eyes(fcen, favg, FWD, R(f.eyeSpread or 30), R(6), (f.eye or 0.3) * hs, A.iris(a, "yellow"), if ink ~= "black" then ink else nil)
	if f.blush ~= false then
		Kit.blush(fcen, favg, FWD, R(48), R(24), hs * 0.13)
	end
	Kit.faceOff()
	-- the beak: short, hooked down, between the eyes; the lower half on the jaw
	local br = hc + V(0, -hs * 0.06, hh.Z * 0.9)
	local beakC = f.beak or "orange"
	Kit.limbs("Beak", { br, br + V(0, -hs * 0.06, hs * 0.13), br + V(0, -hs * 0.2, hs * 0.13) }, { hs * 0.08, hs * 0.06, hs * 0.015 }, beakC, 2)
	J("jaw", "head", br - V(0, hs * 0.1, 0), "jaw")
	Kit.limb("BeakLow", br - V(0, hs * 0.1, -0.02), br + V(0, -hs * 0.16, hs * 0.08), hs * 0.05, hs * 0.02, A.shade(beakC))
	Kit.on("head")
	-- the face's details (A.face) on the facial disc, its ear tufts on the crown
	A.face({ color = discC, c = fcen, half = fhalf, ink = ink, more = A.more({ crown = false }, f.faceDetail) })
	if f.crescent then
		-- a crescent moon on the brow
		local q = {}
		for i = 0, 4 do
			local ang = R(-70 + i * 35)
			local dd = V(math.sin(ang) * 0.32, 0.72 + math.cos(ang) * 0.12, 0.62)
			local p, nrm = Kit.onEll(hc, hh, CFrame.identity, dd)
			q[i + 1] = p + nrm * 0.02
		end
		Kit.limbs("Moon", q, { 0.03, 0.07, 0.03 }, f.crescent, if full() then 4 else 2, 0.5, V(0, 0.6, 1).Unit)
	end
	if f.crownSpots and full() then
		for i, d in { V(-0.3, 0.9, 0.3), V(0.3, 0.9, 0.3), V(0, 1, 0.05), V(-0.5, 0.7, -0.1), V(0.5, 0.7, -0.1) } do
			local p, nrm = Kit.onEll(hc, hh, CFrame.identity, d)
			Kit.disc("CrownSpot" .. i, p, nrm, 0.07, 0.05, f.crownSpots, true, nil, nil, 0.01)
		end
	end
	if f.leaf then
		-- a sprig growing from the crown
		local base = hc + V(0.1, hh.Y * 0.9, -0.05)
		Kit.limb("Sprig", base - V(0, 0.05, 0), base + V(0.06, 0.2, 0.02), 0.03, 0.025, f.twig or "wood_dark")
		pane("Leaf", base + V(0.06, 0.18, 0.02), base + V(0.24, 0.3, 0.06), 0.03, 0.08, V(0, 1, 0.4).Unit, f.leaf, 0.05)
	end
	-- the ear tufts
	local tuft = f.tufts
	if tuft then
		for _, side in { -1, 1 } do
			local s = sn(side)
			local base = Kit.onEll(hc, hh, CFrame.identity, V(side * 0.62, 0.78, 0.15)) - V(0, 0.06, 0)
			J("ear" .. s, "head", base, "ear", side)
			local tl = (f.tuftLen or 0.5) * S
			if tuft == "feather" or tuft == "horn" then
				local lean = if tuft == "horn" then V(side * 0.42, 1, -0.55) else V(side * 0.55, 1, -0.2)
				local tip = base + lean.Unit * tl
				pane("Tuft" .. s, base, tip, tl * 0.26, tl * 0.03, V(0, 0.2, 1).Unit, b, 0.08)
				if full() then
					pane("Tuft" .. s, base + V(-side * 0.07, -0.02, 0.06), lerp(base, tip, 0.75) + V(-side * 0.08, 0, 0.06), tl * 0.17, tl * 0.03, V(0, 0.2, 1).Unit, f.tuftC or a, 0.08)
				end
			elseif tuft == "twig" then
				-- a forked stick with a leaf on one tine
				local tip = base + V(side * 0.2, tl, -0.06)
				Kit.limb("Twig" .. s, base, tip, 0.06, 0.03, f.twig or a)
				local fork = lerp(base, tip, 0.55)
				Kit.limb("Twig" .. s, fork, fork + V(side * 0.2, 0.16, 0.02), 0.035, 0.02, f.twig or a)
				if f.leaf then
					pane("TwigLeaf" .. s, tip, tip + V(side * 0.1, 0.12, 0.08), 0.025, 0.07, V(0, 0.3, 1).Unit, f.leaf, 0.05)
				end
			elseif tuft == "crystal" then
				-- faceted points of crystal
				Kit.limb("Crystal" .. s, base - V(0, 0.04, 0), base + V(side * 0.18, tl, -0.06), 0.1, 0.015, f.tuftC or a, 0.7, V(0, 0, 1))
				if full() then
					Kit.limb("Crystal" .. s, base + V(side * 0.08, -0.04, -0.06), base + V(side * 0.34, tl * 0.6, -0.14), 0.07, 0.012, f.tuftC2 or b, 0.7, V(0, 0, 1))
				end
			end
		end
		Kit.on("head")
	end
	return t
end

FORMS.twiggle = {
	-- an owl of sticks and bark: forked twig tufts with leaves, bark lines down its wings, stick legs, a sprig on its
	-- head and twigs poking out of its tail
	tufts = "twig",
	tuftLen = 0.46,
	twig = "wood_dark",
	leaf = "leaf",
	disc = "sand",
	rim = "wood_dark",
	under = "sand",
	wing = "wood_dark",
	bark = "hair_brown",
	wingSpots = {},
	twigLegs = "wood_dark",
	twigTail = "wood_dark",
	beak = "leaf_dark",
	blush = true,
}

FORMS.crystowl = {
	-- a crystal owl: points of crystal for tufts, shards growing out of its back, a pale ice face
	tufts = "crystal",
	tuftLen = 0.56,
	tuftC = "purple",
	tuftC2 = "crystal",
	shards = "purple",
	disc = "ice",
	rim = "purple",
	under = "ice",
	wing = "teal",
	prim = "purple",
	spotC = "ice",
	beak = "purple",
	toes = "purple",
}

FORMS.stormowl = {
	-- a night owl: tall horns swept back, a lightning bolt down its breast, a yellow bar on each wing
	tufts = "horn",
	tuftLen = 0.66,
	tuftC = "slate",
	disc = "slate",
	rim = "black",
	under = "slate",
	bolt = "yellow",
	boltGlow = true,
	wing = "night",
	prim = "black",
	wingBar = "yellow",
	spotC = "slate",
	beak = "yellow",
	toes = "slate",
	talon = "yellow",
	tall = 1.2,
	wide = 1.02,
}

FORMS.glyphowl = {
	-- a barn owl of the dunes: a white heart of a face ringed in gold, no tufts, taller and slimmer, gold marks
	face = "heart",
	disc = "white",
	rim = "gold",
	under = "cream",
	glyphs = "gold",
	wing = "sand_dark",
	prim = "sand_dark",
	wingSpots = { { -0.15, 0.1, 0.1 }, { 0.2, -0.05, 0.08 } },
	spotC = "gold",
	crownSpots = "gold",
	beak = "sand_dark",
	legH = 0.4,
	tall = 1.2,
	wide = 0.96,
	head = 0.98,
	toes = "sand_dark",
	h = 2.4,
}

FORMS.lunowl = {
	-- a snowy owl: round and plump, no tufts, very fluffy feet, a crystal crescent moon on its brow, crystal flecks
	disc = "snow",
	rim = "ice",
	under = "snow",
	crescent = "crystal",
	wing = "white",
	prim = "snow",
	spotC = "crystal",
	wingSpots = { { -0.2, 0.15, 0.08 }, { 0.1, -0.1, 0.07 }, { 0.3, 0.15, 0.07 }, { 0, 0.32, 0.06 }, { -0.35, -0.15, 0.06 } },
	wide = 1.16,
	tall = 1.08,
	head = 1.04,
	beak = "slate",
	toes = "snow",
	talon = "slate",
}

------------------------------------------------------------------ the penguin
-- A penguin: an upright egg of a body, fuller at the bottom, the white front a cap over its belly; a smaller head on
-- top with a short beak; flippers at the sides (on the wing joints, so it flaps them), short legs with big webbed feet
-- and a stubby tail. The form makes a puffin of it too: a big white face and a huge striped beak.
PLANS.penguin = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local t = Kit.new("penguin", f.h or 2.0, f.r or 0.9, "biped")
	local front = f.front or (if A.isDark(b) then "white" else A.under(b))
	local BW, BH, BD = (f.wide or 1.02) * S, (f.tall or 1.42) * S, (f.deep or 0.94) * S
	local legH = 0.14 * S
	local by = legH + BH * 0.46
	J("body", nil, V(0, by, 0), "body")
	local _, body = A.body("Body", V(0, by, -0.02), V(0, 1, f.lean or 0.14).Unit, BH, BW, BD, f.split or 0.43, b)
	A.patch("Front", body, V(0, -0.1, 1), f.frontK or V(0.95, 0.94, 0.62), 0.02, front)
	if f.blaze then
		-- a pale wash on the breast (a chick's)
		A.patch("Blaze", body, V(0, 0.3, 1), 0.5, 0.03, f.blaze)
	end
	-- the legs: short, the feet big and webbed, splayed a little
	for _, side in { -1, 1 } do
		local hip = V(side * BW * 0.22, legH + 0.18 * S, 0.04)
		J("leg" .. sn(side), "body", hip, "leg", side, if side < 0 then 0 else 0.5)
		local foot = V(side * BW * 0.26, 0, 0.14)
		Kit.limb("Leg" .. sn(side), hip, foot + V(0, 0.07, -0.04), 0.1 * S, 0.07 * S, f.legs or "black")
		birdFoot("Foot" .. sn(side), foot, 0.24 * S, f.feet or "orange", nil, (FWD + V(side * 0.3, 0, 0)).Unit, f.feet or "orange")
		Kit.on("body")
	end
	-- the stubby tail
	local tb = surf(body, V(0, -0.65, -1))
	J("tail", "body", tb, "tail", 0, 1)
	pane("Tail", tb - V(0, 0, -0.05), tb + V(0, -0.1, -0.24) * S, 0.12 * S, 0.06 * S, UP, b, 0.07)
	Kit.on("body")
	-- the flippers: flat paddles hanging at the sides, pale underneath
	for _, side in { -1, 1 } do
		local s = sn(side)
		local sh, nrm = surf(body, V(side, 0.45, 0.05))
		J("wing" .. s, "body", sh, "wing", side)
		local tip = sh + V(side * 0.22, -(f.flip or 0.72) * S, -0.08)
		local n = (nrm + V(side * 0.3, 0, 0)).Unit
		pane("Flipper" .. s, sh + n * 0.02, tip + n * 0.04, 0.15 * S, 0.06 * S, n, f.flipC or b, 0.09)
		if full() then
			pane("FlipperIn" .. s, sh + n * 0.02 + V(0, -0.1, 0.04), tip + n * 0.04 + V(-side * 0.02, 0.06, 0.04), 0.11 * S, 0.04 * S, n, front, 0.11)
		end
		Kit.on("body")
	end
	-- the head on top
	local hs = (f.head or 0.82) * S
	local top = surf(body, V(0, 1, 0.12))
	local hc = top + V(0, hs * (f.headUp or 0.12), hs * 0.1)
	local puffin = f.puffin
	local ink = A.ink(b, a)
	local hd = A.head({
		c = hc,
		size = V(hs * 1.02, hs * 0.92, hs * 0.94),
		color = f.headC or b,
		pivot = top - V(0, 0.06, 0),
		muzzle = if puffin then "none" else "beak",
		beak = f.beak or "black",
		mlen = (f.beakLen or 0.26) * S,
		mw = (f.beakW or 0.18) * S,
		mdrop = hs * 0.08,
		eye = { R(f.eyeSpread or 34), R(8), (f.eye or 0.27) * hs / 0.82 },
		iris = A.iris(a, "blue"),
		ink = if A.isDark(f.headC or b) then ink else nil,
		blush = f.blush ~= false,
		mouth = false,
		jaw = not puffin,
		face = A.more(nil, f.faceDetail),
	})
	if f.cap then
		-- a dark cap over the crown and down the nape, the face left pale
		A.patch("Cap", hd.mass, V(0, 1, -0.8), V(f.capK or 0.97, f.capK or 0.97, f.capK or 0.97), 0.015, f.cap)
	end
	if puffin then
		-- the puffin's beak: tall and thin side to side, a dark band at the root, a yellow line, the rest orange
		local br = hd.c + V(0, -hs * 0.08, hd.half.Z * 0.8)
		local bl = (f.beakLen or 0.44) * S
		local tip = br + V(0, -bl * 0.3, bl)
		Kit.limb("Beak", br, tip, hs * 0.24, hs * 0.035, f.beak or "orange", 0.5, V(1, 0, 0))
		Kit.ell("BeakBase", br + V(0, 0.0, hs * 0.02), V(hs * 0.26, hs * 0.5, hs * 0.1), "slate")
		if full() then
			Kit.ell("BeakLine", br + V(0, -0.01, bl * 0.2), V(hs * 0.23, hs * 0.4, 0.06), "yellow")
			Kit.ell("BeakGroove", br + V(0, -bl * 0.1, bl * 0.48), V(hs * 0.16, hs * 0.26, 0.05), "clay")
		end
		J("jaw", "head", br - V(0, hs * 0.14, 0), "jaw")
		Kit.limb("BeakLow", br - V(0, hs * 0.16, -bl * 0.05), br + V(0, -hs * 0.26, bl * 0.72), hs * 0.12, hs * 0.03, f.beak or "orange", 0.5, V(1, 0, 0))
		Kit.on("head")
		-- the grey patch round each eye and the eye's dark line back
		if full() then
			for _, side in { -1, 1 } do
				local p, nrm = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side * 0.9, 0.12, 0.25))
				Kit.limb("EyeLine" .. sn(side), p + nrm * 0.02, p + nrm * 0.02 + V(0, -0.02, -0.16), 0.03, 0.02, "slate", 0.5, nrm)
			end
		end
	end
	if f.tuft then
		crest(hd, { kind = "fluff", c = f.tuft, len = 0.3 * S })
	end
	if f.brow then
		-- yellow brow plumes (a rockhopper's)
		for _, side in { -1, 1 } do
			local p = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side * 0.55, 0.6, 0.55))
			Kit.limbs("Brow" .. sn(side), { p, p + V(side * 0.18, 0.06, -0.12), p + V(side * 0.3, 0.14, -0.3) }, { 0.05, 0.04, 0.015 }, f.brow, 2)
		end
	end
	return t
end

FORMS.slidget = {
	-- a round slate penguin chick: a white front, a white face under a dark cap, a tuft of down on its head, pink feet
	front = "white",
	headC = "white",
	cap = "slate",
	capK = 0.93,
	tuft = "slate",
	beak = "black",
	beakLen = 0.2,
	feet = "pink",
	legs = "slate",
	wide = 1.1,
	tall = 1.34,
	head = 0.86,
	flip = 0.62,
}

FORMS.puffbill = {
	-- a puffin: black with a white face and front, a huge striped orange beak, orange feet, shorter and stouter
	puffin = true,
	headC = "white",
	cap = "black",
	front = "white",
	beak = "orange",
	beakLen = 0.46,
	feet = "orange",
	legs = "orange",
	tall = 1.24,
	wide = 1.0,
	head = 0.9,
	headUp = 0.18,
	lean = 0.24,
	flip = 0.58,
	h = 2.0,
}

------------------------------------------------------------------ the duck
-- A duck: a round boat of a body with a short tail flicked up, a round head on a short neck with a broad flat bill (the
-- lower half drops), folded wings (a coloured patch on a mallard's), short legs with webbed feet. A duckling is all
-- fluff: a bigger head, wing stubs, a tuft of down.
PLANS.duck = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local t = Kit.new("duck", f.h or 1.9, f.r or 0.9, "biped")
	local bodyC = f.bodyC or b
	local headC = f.headC or b
	local under = f.under or bodyC
	local legH = (f.legH or 0.3) * S
	local L, W, T = (f.len or 1.36) * S, (f.wide or 1.0) * S, (f.tall or 0.86) * S
	local by = legH + T * 0.48
	J("body", nil, V(0, by, 0), "body")
	local d = V(0, math.sin(R(f.pitch or 8)), math.cos(R(f.pitch or 8)))
	local _, body = A.body("Body", V(0, by, -0.12 * S), d, L, W, T, f.split or 0.52, bodyC)
	if under ~= bodyC then
		A.patch("Belly", body, V(0, -1, 0.2), V(0.86, 0.86, 0.86), 0.02, under)
	end
	if f.breast then
		A.patch("Breast", body, V(0, 0.2, 1), f.breastK or V(0.7, 0.6, 0.7), 0.03, f.breast)
	end
	-- the legs
	for _, side in { -1, 1 } do
		birdLeg(side, if side < 0 then 0 else 0.5, V(side * W * 0.22, legH + T * 0.22, -0.06 * S), {
			heel = legH * 0.5 + 0.04,
			r = 0.13 * S,
			sr = 0.06 * S,
			thigh = under,
			c = f.legs or "orange",
			feather = 0.85,
			toe = 0.24 * S,
			web = f.legs or "orange",
			out = 0.04,
		})
		Kit.on("body")
	end
	-- the tail: a short point flicked up (a drake's curl over it)
	local tb = surf(body, -d) + d * 0.1
	J("tail", "body", tb, "tail", 0, 1)
	if f.fluffTail then
		Kit.ell("Tail", tb + V(0, 0.1, -0.06), V(0.3, 0.26, 0.3) * S, bodyC)
	else
		local tip = tb + V(0, 0.28, -0.3) * S
		pane("Tail", tb, tip, 0.17 * S, 0.04 * S, V(0, 1, 0.8).Unit, f.tailC or bodyC, 0.1)
		if f.curl then
			local c0 = tb + V(0, 0.18, -0.08) * S
			Kit.limbs("TailCurl", { c0, c0 + V(0, 0.18, -0.02) * S, c0 + V(0, 0.22, 0.12) * S, c0 + V(0, 0.12, 0.14) * S }, { 0.04, 0.035, 0.02 }, f.curl, if full() then 3 else 2)
		end
	end
	Kit.on("body")
	-- the wings
	for _, side in { -1, 1 } do
		local p, nrm = surf(body, V(side, 0.4, -0.25))
		local sh = surf(body, V(side, 0.5, 0.45))
		local ax = turn(V(0, -0.1, -1), -side * 3, -2)
		local th = 0.16 * S
		local stub = f.stub
		foldWing(side, sh, p + nrm * th * 0.15 + (if stub then -ax * 0.1 else V(0, 0, 0)), ax, (nrm + V(side * 0.4, 0, 0)).Unit, {
			len = (if stub then 0.42 else 0.92) * S,
			h = (if stub then 0.34 else 0.5) * S,
			th = th,
			c = f.wing or bodyC,
			edge = f.prim or f.wing or bodyC,
			prim = if stub then 1 else 3,
			primW = 1,
			plen = (if stub then 0.06 else 0.3) * S,
			pw = 0.1 * S,
			cross = 0.08,
			bar = f.bar,
			bar2 = f.bar2,
			barAt = 0.18,
			barWorld = true,
		})
	end
	-- the neck and the head
	local chest = surf(body, V(0, 0.7, 1))
	local hs = (f.head or 0.78) * S
	local hc = chest + V(0, hs * (f.headUp or 0.55), hs * 0.02)
	Kit.limb("Neck", chest - V(0, 0.15, 0.1), hc - V(0, hs * 0.2, hs * 0.08), hs * 0.32, hs * 0.3, f.neckC or headC)
	if f.collar then
		local p = lerp(chest - V(0, 0.15, 0.1), hc - V(0, hs * 0.2, hs * 0.08), 0.42)
		Kit.limb("Collar", p - V(0, 0.025, 0), p + V(0, 0.025, 0), hs * 0.34, hs * 0.34, f.collar, 0.9, UP)
	end
	local hd = A.head({
		c = hc,
		size = V(hs * 0.98, hs * 0.92, hs * 0.96),
		color = headC,
		pivot = chest - V(0, 0.05, 0.08),
		muzzle = "duck",
		beak = f.bill or "orange",
		mlen = (f.billLen or 0.34) * S,
		mw = (f.billW or 0.3) * S,
		mdrop = hs * 0.1,
		eye = { R(40), R(10), (f.eye or 0.26) * hs / 0.78 },
		iris = A.iris(a, "blue"),
		ink = if A.isDark(headC) then A.ink(headC, a) else nil,
		blush = f.blush ~= false,
		mouth = false,
		face = A.more(if f.fluff then { crown = false } else nil, f.faceDetail),
	})
	if f.fluff then
		crest(hd, { kind = "fluff", c = f.fluff, len = 0.34 * S })
		-- (and puffs of down at the cheeks)
		for _, side in { -1, 1 } do
			local p, nrm = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side, -0.3, -0.3))
			Kit.ell("Down" .. sn(side), p - nrm * 0.06, V(hs * 0.3, hs * 0.26, hs * 0.3), headC, nil, true)
		end
	end
	if f.eyeStripe and full() then
		for _, side in { -1, 1 } do
			local p, nrm = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side * 0.85, 0.05, -0.2))
			Kit.limb("EyeStripe" .. sn(side), p + nrm * 0.02 + V(0, 0, 0.12), p + nrm * 0.02 + V(0, -0.02, -0.14), 0.03, 0.025, f.eyeStripe, 0.5, nrm)
		end
	end
	return t
end

FORMS.puddlet = {
	-- a duckling: yellow fluff all over, a big round head with a tuft of down, wing stubs, a fluffy tail
	fluff = "yellow",
	stub = true,
	fluffTail = true,
	bill = "orange",
	billLen = 0.26,
	billW = 0.26,
	head = 0.92,
	headUp = 0.45,
	len = 1.12,
	wide = 0.96,
	tall = 0.86,
	split = 0.5,
	legs = "orange",
	h = 1.8,
}

FORMS.dabbler = {
	-- a mallard drake: a dark green head, a white ring round the neck, a chestnut breast, a sand body, a blue patch on
	-- each wing, a black curl over the tail, a yellow bill
	headC = "leaf_dark",
	neckC = "leaf_dark",
	bodyC = "sand",
	under = "sand_dark",
	collar = "white",
	breast = "clay",
	wing = "rock",
	prim = "rock_dark",
	bar = "blue",
	bar2 = "white",
	tailC = "white",
	curl = "black",
	bill = "yellow",
	billLen = 0.4,
	billW = 0.28,
	head = 0.76,
	headUp = 0.62,
	legs = "orange",
	blush = false,
}

------------------------------------------------------------------ the bat
-- A bat hanging in the air: a furry egg of a body with a ruff at the neck, a fox-like face (a pointed muzzle, a nose,
-- two little fangs), big ears; each wing the bat's hand: an arm bent at the elbow to the wrist, a thumb claw there,
-- three long fingers fanning out from it, the membrane stretched in panels between the fingers and down to the body,
-- its trailing edge scalloped between the finger tips; little legs with hooked toes. The form sets the ears, the
-- wings' size and colours and the marks on them.
PLANS.bat = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local t = Kit.new("bat", f.h or 2.4, f.r or 1.3, "fly")
	local under = f.under or A.under(b)
	local mem = f.mem or a
	local ruffC = f.ruff or under
	J("body", nil, V(0, 1.3, 0), "body")
	local _, body = A.body("Body", V(0, 1.26, -0.02), V(0, 1, 0.25).Unit, 0.96 * S, 0.74 * S, 0.68 * S, 0.56, b)
	A.patch("Chest", body, V(0, 0.1, 1), V(0.78, 0.8, 0.72), 0.02, under)
	Kit.ell("Ruff", V(0, 1.66, 0.04), V(0.74, 0.28, 0.64) * S, ruffC)
	if f.mane then
		-- a shaggy mane over the shoulders
		for i, x in { 0, -0.24, 0.24 } do
			if i == 1 or full() then
				Kit.limb("Mane", V(x, 1.72, -0.12), V(x * 1.3, 1.5, -0.36), 0.15, 0.06, f.mane, 0.7, V(0, 1, -0.5).Unit)
			end
		end
	end
	-- the legs: little and hanging, hooked toes
	for _, side in { -1, 1 } do
		local s = sn(side)
		local hip = V(side * 0.17, 0.95, -0.06)
		J("leg" .. s, "body", hip, "leg", side, if side < 0 then 0 else 0.5)
		local ank = V(side * 0.21, 0.72, -0.04)
		Kit.limb("Leg" .. s, hip, ank, 0.075, 0.05, b)
		for i = -1, 1 do
			if full() then
				local tb = ank + V(i * 0.04 * side, -0.02, 0.02)
				Kit.limb("Toe" .. s, tb, tb + V(i * 0.03 * side, -0.07, 0.06), 0.03, 0.018, f.claw or "black")
			end
		end
		Kit.on("body")
	end
	-- the wings
	local k = (f.span or 1) * S
	for _, side in { -1, 1 } do
		local s = sn(side)
		local function P(x: number, y: number, z: number): Vector3
			return V(side * x, y, z)
		end
		local Sh = P(0.3, 1.5, -0.04)
		local E = P(0.3 + 0.48 * k, 1.68, -0.16)
		local Wr = P(0.3 + 1.0 * k, 1.86, 0.0)
		local F3 = Wr + P(0.95 * k, 0.16 * k, -0.24 * k)
		local F4 = Wr + P(0.85 * k, -0.5 * k, -0.32 * k)
		local F5 = Wr + P(0.36 * k, -0.95 * k, -0.28 * k)
		local Bd = P(0.27, 0.98, -0.08)
		local function dip(p: Vector3, q: Vector3, by: number): Vector3
			local m = lerp(p, q, 0.5)
			return m + (Wr - m) * by
		end
		J("wing" .. s, "body", Sh, "wing", side)
		local inner = f.mem1 or mem
		if full() then
			Kit.limb("Arm" .. s, Sh, E, 0.085, 0.065, b)
			Kit.limb("Arm" .. s, E, Wr, 0.065, 0.05, b)
			tri("Membrane" .. s, Sh, E, Wr, 0.05, inner)
			tri("Membrane" .. s, Sh, E, Bd, 0.05, inner)
			tri("Membrane" .. s, E, Wr, Bd, 0.05, inner)
			local m5 = dip(F5, Bd, f.scallop or 0.2)
			tri("Membrane" .. s, Wr, F5, m5, 0.05, inner)
			tri("Membrane" .. s, Wr, m5, Bd, 0.05, inner)
		else
			Kit.limb("Arm" .. s, Sh, Wr, 0.08, 0.05, b)
			tri("Membrane" .. s, Sh, Wr, Bd, 0.05, inner)
			tri("Membrane" .. s, Wr, F5, Bd, 0.05, inner)
		end
		J("wing" .. s .. "2", "wing" .. s, Wr, "wing", side, 1)
		local outer = f.mem2 or mem
		local tipC = f.mem3 or outer
		for i, tp in { F3, F4, F5 } do
			if i < 3 or full() then
				Kit.limb("Finger" .. s, Wr, tp, 0.045, 0.022, f.bone or b)
			end
		end
		if full() then
			Kit.limb("Thumb" .. s, Wr, Wr + P(0.04, 0.14, 0.08), 0.04, 0.015, f.claw or "black")
			local m45 = dip(F5, F4, f.scallop or 0.2)
			local m34 = dip(F4, F3, f.scallop or 0.2)
			tri("Membrane" .. s, Wr, F5, m45, 0.05, outer)
			tri("Membrane" .. s, Wr, m45, F4, 0.05, outer)
			tri("Membrane" .. s, Wr, F4, m34, 0.05, tipC)
			tri("Membrane" .. s, Wr, m34, F3, 0.05, tipC)
		else
			tri("Membrane" .. s, Wr, F5, F4, 0.05, outer)
			tri("Membrane" .. s, Wr, F4, F3, 0.05, tipC)
		end
		-- the marks on the membrane (thicker than it, so they show from both sides)
		local n = (F3 - Wr):Cross(F5 - Wr).Unit
		if f.glowSpots then
			for i, u in { { 0.5, 0.42 }, { 0.42, 0.62 }, { 0.62, 0.22 } } do
				if i == 1 or full() then
					local p = Wr + (F4 - Wr) * u[1] + (F3 - F4) * u[2] * 0.5
					Kit.disc("GlowSpot" .. s, p - n * 0.07, n, 0.16 - i * 0.02, 0.14, f.glowSpots, false, nil, true)
				end
			end
		end
		if f.moon then
			-- a crescent moon on each wing
			local c0 = Wr + (F4 - Wr) * 0.5
			local up = (F3 - F5).Unit
			local across = n:Cross(up).Unit
			local q = {}
			for i = 0, 4 do
				local ang = R(-80 + i * 40)
				q[i + 1] = c0 + (up * math.cos(ang) * 0.3 + across * math.sin(ang) * 0.3 * side) * k - across * side * 0.08
			end
			Kit.limbs("Moon" .. s, q, { 0.03, 0.08, 0.03 }, f.moon, if full() then 4 else 2, 0.6, n)
		end
		Kit.on("body")
	end
	-- the head
	local hs = (f.head or 0.8) * S
	local hc = V(0, 1.68 + hs * 0.38, 0.1)
	local ink = A.ink(b, a)
	local hd = A.head({
		c = hc,
		size = V(hs * 1.04, hs * 0.92, hs * 0.92),
		color = b,
		pivot = V(0, 1.66, 0.04),
		muzzle = "fox",
		mlen = (f.mlen or 0.26) * S,
		mw = 0.3 * S,
		mdrop = hs * 0.16,
		nose = f.nose or "pink",
		cheeks = f.cheeks,
		eye = { R(30), R(10), (f.eye or 0.27) * hs / 0.8 },
		iris = A.iris(a, "blue"),
		ink = if A.isDark(b) then ink else nil,
		blush = full(),
		fangs = "white",
		whiskers = false,
		face = A.more(nil, f.faceDetail),
	})
	if f.noseLeaf and full() then
		-- a leaf of skin standing up over the nose
		pane("NoseLeaf", hd.nose + V(0, 0.02, -0.01), hd.nose + V(0, 0.16, -0.02), 0.06, 0.03, FWD, f.nose or "pink", 0.05)
	end
	local ek = f.ears or "fox"
	A.ears(hd, {
		kind = ek,
		len = (f.earLen or 0.6) * S,
		w = (f.earW or 0.4) * S,
		at = f.earAt or 0.36,
		back = f.earBack or 8,
		out = f.earOut,
		c = b,
		inner = if full() or ek == "round" then (f.earIn or "pink") else nil,
		tip = if full() then f.earTip else nil,
	})
	if f.earGlow and full() then
		-- (a glowing lining in each ear)
		for _, side in { -1, 1 } do
			local base = Kit.onEll(hd.c, hd.half, CFrame.identity, V(side * 0.6, 0.85, 0.2))
			Kit.on("ear" .. sn(side))
			Kit.ell("EarGlow" .. sn(side), base + V(side * 0.12, 0.2, 0.12), V(0.12, 0.2, 0.06), f.earGlow, A.lie(V(side * 0.3, 1, 0), FWD), nil, true)
		end
		Kit.on("head")
	end
	if f.crest then
		crest(hd, { kind = f.crest, c = f.crestC or a, c2 = f.crestC2, c3 = f.crestC3, len = f.crestLen or 0.4 })
	end
	return t
end

FORMS.scorchwing = {
	-- a volcano bat: flame-orange wings darkening to clay at the body, ears tipped with fire, a flame of a tuft
	mem = "orange",
	mem1 = "clay",
	mem3 = "orange",
	bone = "purple",
	ruff = "orange",
	earTip = "orange",
	earIn = "clay",
	earLen = 0.62,
	crest = "flame",
	crestC = "orange",
	crestC2 = "lava",
	crestC3 = "yellow",
	crestLen = 0.36,
	nose = "black",
}

FORMS.glowbat = {
	-- a cave bat: big round mouse ears lit inside, dark wings with glowing spots, a nose leaf
	ears = "round",
	earW = 0.56,
	earIn = "teal",
	earGlow = "screen_on",
	mem = "slate",
	glowSpots = "screen_on",
	ruff = "slate",
	noseLeaf = true,
	nose = "screen_on",
	under = "slate",
}

FORMS.aurorawing = {
	-- (its face: marks of its own)
	faceDetail = { marks = { freckles = "pink", glow = true } },
	-- a bat of the northern lights: each wing pink at the body through crystal to teal at the tips, long ears swept
	-- back with pink tips, a white ruff
	mem1 = "pink",
	mem2 = "crystal",
	mem3 = "teal",
	ruff = "white",
	ears = "long",
	earLen = 0.72,
	earW = 0.3,
	earBack = 22,
	earOut = 0.35,
	earTip = "pink",
	earIn = "white",
	span = 1.1,
	scale = 1.05,
	h = 2.5,
}

FORMS.moonveil = {
	-- the bat whose wings hide the moon: huge night wings with a pale crescent on each, a shaggy cherry mane, tall ears
	mem = "night",
	mem3 = "black",
	moon = "cherry",
	mane = "cherry",
	ruff = "cherry",
	earIn = "cherry",
	earLen = 0.7,
	earW = 0.38,
	span = 1.14,
	scale = 1.06,
	nose = "cherry",
	h = 2.7,
	r = 1.5,
}

------------------------------------------------------------------ the moth
-- An insect on the wing: a round fuzzy thorax with a ruff of fluff, the abdomen an egg trailing behind, a round head
-- with antennae (feathery, clubbed or short), six thin legs hanging from the thorax, and two pairs of wings: the
-- forewings reaching up and out, the hindwings below, each a fan out from its root. The form gives each its own wing
-- shapes (a moth's broad points, a butterfly's round sails, petals, long tails, a bee's little round panes) and marks.
PLANS.moth = function(b, a, form)
	local f: Form = form or {}
	local S = f.scale or 1
	local t = Kit.new("moth", f.h or 2.4, f.r or 1.4, "fly")
	local wingC = f.wing or a
	J("body", nil, V(0, 1.15, 0), "body")
	local thC = f.thorax or b
	Kit.ell("Thorax", V(0, 1.2, 0.02), V(0.6, 0.58, 0.62) * S * (f.thick or 1), thC)
	-- the abdomen
	local ax = V(0, -(f.droop or 0.42), -1).Unit
	local aL = (f.abLen or 0.96) * S
	local aW = (f.abW or 0.5) * S
	local ac = V(0, 1.16, -0.12) + ax * aL * 0.5
	local arot = A.lie(ax, UP)
	local split = 0.6
	Kit.egg("Abdomen", ac, V(aW, aL, aW), split, f.abC or b, arot)
	-- (its radius along it, for the bands)
	local function radAt(u: number): number
		local y = (u - 0.5) * aL
		local ye = aL / 2 - aL * split
		local hh = if y >= ye then aL * split else aL * (1 - split)
		local q = (y - ye) / hh
		return aW / 2 * math.sqrt(math.max(0, 1 - q * q))
	end
	if f.bands then
		for i, u in f.bands :: { number } do
			if i <= 2 or full() then
				local p = ac + ax * ((u - 0.5) * aL)
				Kit.ell("Band", p, V(radAt(u) * 2 + 0.08, 0.2 * S, radAt(u) * 2 + 0.08), f.bandC or a, arot)
			end
		end
	end
	local tailP = ac + ax * aL * 0.5
	if f.lantern then
		-- a glowing lantern at the tail's end
		Kit.ell("Lantern", tailP - ax * 0.08, V(0.3, 0.3, 0.3) * S, f.lantern, arot, nil, true)
	end
	if f.sting then
		Kit.limb("Sting", tailP - ax * 0.04, tailP + ax * 0.16, 0.05, 0.01, f.sting)
	end
	if f.tailTuft and full() then
		Kit.ell("TailTuft", tailP - ax * 0.02, V(0.16, 0.16, 0.16), f.tailTuft, arot)
	end
	-- the ruff where the head meets the thorax
	Kit.ell("Ruff", V(0, 1.42, 0.2), V(0.64, 0.3, 0.46) * S, f.ruff or a)
	if f.fuzz and full() then
		Kit.ell("Fuzz", V(0, 1.5, -0.08), V(0.3, 0.2, 0.28), f.fuzz)
	end
	-- the legs: three a side, thin, bent at the knee, hanging
	for _, side in { -1, 1 } do
		local s = sn(side)
		J("leg" .. s, "body", V(side * 0.14, 1.02, 0.04), "leg", side, if side < 0 then 0 else 0.5)
		for i = 0, 2 do
			local hip = V(side * 0.14, 1.0, 0.18 - i * 0.16)
			local knee = V(side * (0.34 + i * 0.03), 0.9 - i * 0.02, 0.24 - i * 0.2)
			local foot = V(side * (0.36 + i * 0.05), 0.62, 0.3 - i * 0.28)
			local lc = f.legC or b
			if full() then
				Kit.limb("Leg" .. s, hip, knee, 0.04, 0.03, lc)
				Kit.limb("Leg" .. s, knee, foot, 0.03, 0.018, lc)
			else
				Kit.limb("Leg" .. s, hip, foot, 0.04, 0.025, lc)
			end
		end
		Kit.on("body")
	end
	-- the wings
	local wk = f.wings or "moth"
	for _, side in { -1, 1 } do
		local s = sn(side)
		local sw, tl = R(f.sweep or 22), R(f.tilt or 16)
		local outS = V(side * math.cos(sw), 0, -math.sin(sw))
		local upT = V(0, math.cos(tl), -math.sin(tl))
		local n = outS:Cross(upT).Unit
		if n.Z < 0 then
			n = -n
		end
		local function dir(ang: number): Vector3
			return (outS * math.cos(R(ang)) + upT * math.sin(R(ang))).Unit
		end
		local root = V(side * 0.22, 1.34, -0.02)
		local root2 = V(side * 0.2, 1.2, -0.08) - n * 0.06
		J("wing" .. s, "body", root, "wing", side)
		local FL, FW = (f.foreLen or 1.2) * S, (f.foreW or 0.44) * S
		local HL, HW = (f.hindLen or 0.86) * S, (f.hindW or 0.38) * S
		local fa, ha = f.foreA or 38, f.hindA or -28
		local ftip = root + dir(fa) * FL
		local htip = root2 + dir(ha) * HL
		local rim = f.rim
		local layers = f.layers -- concentric bands from the root (a rainbow)
		local function sail(nm: string, r0: Vector3, tip: Vector3, w: number, col: string, off: number, tip2: Vector3?)
			local o = n * off
			local rk = f.rootK or 0.42
			if rim and full() then
				pane(nm .. "Rim" .. s, r0 - n * 0.03 + o, tip + (tip - r0).Unit * 0.05 - n * 0.03 + o, w * rk + 0.04, w + 0.05, n, rim, 0.05)
				if tip2 then
					pane(nm .. "Rim" .. s, r0 - n * 0.03 + o, tip2 + (tip2 - r0).Unit * 0.05 - n * 0.03 + o, w * rk + 0.04, w * 0.9 + 0.05, n, rim, 0.05)
				end
			end
			pane(nm .. s, r0 + n * 0.02 + o, tip + n * 0.02 + o, w * rk, w, n, col, 0.05)
			if tip2 then
				-- (a second lobe fanned beside it: the wing's outer edge broad, not a spoon)
				pane(nm .. s, r0 + n * 0.02 + o, tip2 + n * 0.02 + o, w * rk, w * 0.9, n, col, 0.05)
			end
			if layers then
				for i, ly in layers :: { Layer } do
					local kk = ly.k
					if i <= 1 or full() then
						local ends: { Vector3 } = { tip }
						if tip2 and full() then
							table.insert(ends, tip2)
						end
						for _, tp0 in ends do
							pane(nm .. "Band" .. s, r0 + o, lerp(r0, tp0, kk) + o, w * rk * kk, w * (0.25 + 0.75 * kk), n, ly.c, 0.12 + i * 0.09)
						end
					end
				end
			end
		end
		-- the hindwing first (behind), then the forewing
		if wk == "petal" then
			-- two rounded petals for each hindwing
			for i, dd in { ha + 12, ha - 18 } do
				if i == 1 or full() then
					sail("Hindwing", root2 - n * 0.02 * i, root2 + dir(dd) * HL * (1 - 0.1 * (i - 1)), HW * 0.85, f.hindC or wingC, -0.04 * i)
				end
			end
		else
			local lobe = if wk == "round" then nil else root2 + dir(ha + (f.hindLobe or 22)) * HL * 0.86
			sail("Hindwing", root2, htip, HW, f.hindC or wingC, -0.04, lobe)
		end
		if f.tails then
			-- long tails trailing from the hindwings
			-- (in the wing's own plane, down from the hindwing's outer end, curving out)
			local t0 = htip + dir(ha - 70) * HW * 0.5 - n * 0.04
			local tEnd = t0 + dir(ha - 58) * (f.tailLen or 0.8) * S - n * 0.04
			local tMid = lerp(t0, tEnd, 0.5) + dir(ha + 30) * 0.08
			Kit.limbs("WingTail" .. s, { t0, tMid, tEnd }, { HW * 0.42, HW * 0.24, 0.035 }, f.tailC or wingC, if full() then 3 else 2, 0.3, n)
			if full() and f.tailTip then
				Kit.ell("WingTailTip" .. s, tEnd, V(0.14, 0.18, 0.14), f.tailTip, nil, nil, f.glow)
			end
		end
		if wk == "moth" then
			-- a moth's forewing: a broad fan and a leading edge out to a pointed apex
			sail("Forewing", root, ftip, FW, wingC, 0, root + dir(fa - 20) * FL * 0.8)
			local apex = root + dir(fa + 10) * FL * 1.08
			pane("ForeEdge" .. s, root + n * 0.05, apex + n * 0.05, 0.06, FW * 0.3, n, wingC, 0.05)
		elseif wk == "butterfly" then
			sail("Forewing", root, ftip, FW, wingC, 0, root + dir(fa - 22) * FL * 0.8)
		else
			sail("Forewing", root, ftip, FW, wingC, 0)
		end
		-- the marks (discs thicker than the wing, so they show from both sides)
		local spots = f.spots
		if spots then
			for i, sp in spots :: { Form } do
				if not sp.near or full() then
					local onFore = (sp.u :: number) > 0
					local r0 = if onFore then root else root2
					local tip = if onFore then ftip else htip
					local u = math.abs(sp.u :: number)
					local across = n:Cross(tip - r0).Unit
					local p = lerp(r0, tip, u) + across * (sp.v :: number) * side * (if onFore then FW else HW)
					local d0 = (sp.d :: number) * S
					Kit.disc("WingSpot" .. s .. i, p - n * 0.09, n, d0, 0.2, sp.c :: string, false, nil, f.glow)
					if sp.c2 then
						Kit.disc("WingSpot" .. s .. i .. "b", p - n * 0.13, n, d0 * 0.5, 0.28, sp.c2 :: string, false, nil, f.glow)
					end
				end
			end
		end
		if f.runes and full() then
			-- old spells: a little triangle and a barred line on each forewing
			local along = (ftip - root).Unit
			local across = n:Cross(along).Unit * side
			local c0 = lerp(root, ftip, 0.6) + n * 0.06
			local tri3 = { c0 + along * 0.13, c0 - along * 0.08 + across * 0.12, c0 - along * 0.08 - across * 0.12 }
			for i = 1, 3 do
				Kit.limb("Rune" .. s, tri3[i], tri3[i % 3 + 1], 0.025, 0.025, f.runes, 0.5, n)
			end
			local c1 = lerp(root, ftip, 0.32) + n * 0.06
			Kit.limb("Rune" .. s, c1 - across * 0.12, c1 + across * 0.12, 0.025, 0.025, f.runes, 0.5, n)
			Kit.limb("Rune" .. s, c1 - along * 0.08, c1 + along * 0.08, 0.025, 0.025, f.runes, 0.5, n)
			local c2 = lerp(root2, htip, 0.6) + n * 0.02
			Kit.disc("Rune" .. s, c2 - n * 0.06, n, 0.14, 0.16, f.runes)
			Kit.disc("Rune" .. s, c2 - n * 0.08, n, 0.07, 0.22, wingC)
		end
		if f.stars then
			-- little four-pointed stars across the wings
			local along = (ftip - root).Unit
			local across = n:Cross(along).Unit * side
			for i, st in { { 0.7, 0.1, 0.2 }, { 0.45, -0.25, 0.14 }, { 0.85, -0.3, 0.12 }, { 0.3, 0.2, 0.1 } } do
				if i == 1 or full() then
					local p = lerp(root, ftip, st[1]) + across * st[2] * FW + n * 0.06
					local r0 = st[3] * S
					Kit.limb("Star" .. s, p - along * r0, p + along * r0, 0.03, 0.03, f.stars, 0.5, n, nil, true)
					Kit.limb("Star" .. s, p - across * r0 * 0.7, p + across * r0 * 0.7, 0.03, 0.03, f.stars, 0.5, n, nil, true)
				end
			end
			local hp = lerp(root2, htip, 0.6) + n * 0.02
			Kit.disc("Star" .. s, hp - n * 0.06, n, 0.1, 0.16, f.stars, true, nil, true)
			-- (the hindwing's star: up close only)
		end
		Kit.on("body")
	end
	-- the head
	local hs = (f.head or 1) * S
	local hc = V(0, 1.6, 0.42)
	J("head", "body", V(0, 1.42, 0.24), "head")
	local hsz = V(0.6, 0.54, 0.52) * hs
	local hh = hsz / 2
	Kit.ell("Head", hc, hsz, f.headC or b)
	Kit.faceOn(hc, hh)
	local ink = A.ink(f.headC or b, a)
	Kit.eyes(hc, (hh.X + hh.Y + hh.Z) / 3, FWD, R(f.eyeSpread or 34), R(6), (f.eye or 0.28) * hs, A.iris(a, "yellow"), if ink ~= "black" then ink else nil)
	Kit.blush(hc, (hh.X + hh.Y + hh.Z) / 3, FWD, R(52), R(18), 0.12 * hs)
	Kit.faceOff()
	local mAt, mN = Kit.onEll(hc, hh, CFrame.identity, V(0, -0.45, 1))
	Kit.mouth(mAt, mN, 0.12 * hs, ink)
	A.face({ color = f.headC or b, c = hc, half = hh, ink = ink, more = A.more(nil, f.faceDetail) })
	-- the antennae
	local ak = f.antennae or "feather"
	for _, side in { -1, 1 } do
		local s = sn(side)
		local base = Kit.onEll(hc, hh, CFrame.identity, V(side * 0.35, 0.85, 0.35))
		J("ant" .. s, "head", base, "antenna", side)
		local antC = f.antC or b
		if ak == "club" then
			local tip = base + V(side * 0.32, 0.62, 0.12) * S
			Kit.limbs("Ant" .. s, { base, lerp(base, tip, 0.5) + V(side * 0.06, 0, 0), tip }, { 0.03, 0.025 }, antC, 2)
			Kit.ell("AntTip" .. s, tip, V(0.11, 0.14, 0.11), f.antTip or antC)
		elseif ak == "short" then
			local elbow = base + V(side * 0.06, 0.24, 0.06)
			Kit.limb("Ant" .. s, base, elbow, 0.035, 0.03, antC)
			Kit.limb("Ant" .. s, elbow, elbow + V(side * 0.16, 0.06, 0.12), 0.03, 0.04, antC)
		else
			-- feathery: a curved stalk with a feather of barbs along it
			local tip = base + V(side * 0.36, 0.56, 0.06) * S
			local mid = lerp(base, tip, 0.5) + V(side * 0.08, 0.04, 0.04)
			Kit.limbs("Ant" .. s, { base, mid, tip }, { 0.03, 0.02 }, antC, 2)
			local nn = V(0, 0.3, 1).Unit
			pane("AntFeather" .. s, lerp(base, mid, 0.4), mid, 0.03, 0.08, nn, f.antTip or antC, 0.05)
			pane("AntFeather" .. s, mid, tip, 0.08, 0.025, nn, f.antTip or antC, 0.05)
		end
		Kit.on("head")
	end
	return t
end

FORMS.bloomoth = {
	-- a pink moth like a flower: pink wings with yellow edges, petal-shaped hindwings, a yellow flower on each
	-- forewing, a fuzzy yellow ruff
	wing = "pink",
	rim = "yellow",
	wings = "petal",
	ruff = "yellow",
	antC = "yellow",
	spots = { { u = 0.6, v = 0.05, d = 0.3, c = "yellow", c2 = "orange" }, { u = 0.75, v = -0.25, d = 0.12, c = "yellow", near = true }, { u = 0.45, v = -0.3, d = 0.12, c = "yellow", near = true }, { u = 0.75, v = 0.35, d = 0.12, c = "yellow", near = true } } :: { Spot },
	fuzz = "yellow",
	tailTuft = "yellow",
}

FORMS.wispwing = {
	-- a glowing moth: long wisps of hindwings, dark wings with lit spots, and a lantern glowing at its tail
	wing = "leaf_dark",
	rim = "screen_on",
	hindLen = 1.15,
	hindW = 0.24,
	hindA = -40,
	foreW = 0.38,
	lantern = "screen_on",
	glow = true,
	spots = { { u = 0.65, v = 0, d = 0.2, c = "screen_on" }, { u = -0.65, v = 0, d = 0.14, c = "screen_on" } } :: { Spot },
	ruff = "leaf_dark",
	antC = "leaf_dark",
	antTip = "screen_on",
	abC = "leaf_dark",
	bands = { 0.35, 0.6 },
	bandC = "screen_on",
}

FORMS.prismoth = {
	-- a butterfly that splits the light: big round wings in rainbow bands, a slender body, clubbed antennae
	wings = "butterfly",
	wing = "purple",
	layers = { { k = 0.82, c = "screen_on" }, { k = 0.6, c = "yellow" }, { k = 0.36, c = "pink" } } :: { Layer },
	foreLen = 1.25,
	foreW = 0.58,
	hindLen = 0.95,
	hindW = 0.5,
	foreA = 44,
	hindA = -22,
	antennae = "club",
	antC = "black",
	antTip = "pink",
	abW = 0.34,
	abLen = 0.9,
	thick = 0.85,
	ruff = "pink",
	legC = "black",
}

FORMS.runemoth = {
	-- a gold moth written over with old purple spells: a purple rim round each wing, runes on them, purple plumes
	wing = "gold",
	rim = "purple",
	runes = "purple",
	ruff = "purple",
	antC = "purple",
	antTip = "purple",
	bands = { 0.3, 0.55, 0.78 },
	bandC = "purple",
	foreW = 0.48,
}

FORMS.starweaver = {
	-- (its face: marks of its own)
	faceDetail = { marks = { star = "crystal", glow = true } },
	-- a moth of the night sky: night wings edged with crystal, stars on them, long tails trailing from the hindwings
	wing = "night",
	rim = "crystal",
	stars = "crystal",
	tails = true,
	hindA = -12,
	tailC = "night",
	tailTip = "crystal",
	glow = false,
	ruff = "crystal",
	antC = "crystal",
	antTip = "crystal",
	scale = 1.14,
	foreW = 0.46,
	hindW = 0.4,
	tailTuft = "crystal",
	h = 2.8,
	r = 1.6,
}

FORMS.bumblet = {
	-- a bumblebee: a round fuzzy yellow body in black bands, a black tail with a sting, little round clear wings held
	-- up, short elbowed antennae
	wings = "round",
	wing = "window",
	rim = "ice",
	foreLen = 0.72,
	foreW = 0.3,
	hindLen = 0.5,
	hindW = 0.22,
	foreA = 58,
	hindA = 30,
	sweep = 40,
	abLen = 0.82,
	abW = 0.72,
	droop = 0.55,
	thick = 1.1,
	bands = { 0.32, 0.6, 0.86 },
	bandC = "black",
	sting = "black",
	ruff = "yellow",
	fuzz = "black",
	antennae = "short",
	antC = "black",
	legC = "black",
	h = 2.1,
	r = 1.0,
}

FORMS.dimwing = {
	-- a slate night moth: broad pointed wings with a big crystal eye on each, small eyes on the hindwings, feathery
	-- antennae, a pale ruff
	wing = "slate",
	rim = "rock_dark",
	spots = { { u = 0.62, v = 0, d = 0.34, c = "crystal", c2 = "night" }, { u = -0.6, v = 0, d = 0.18, c = "crystal", near = true } } :: { Spot },
	ruff = "crystal",
	antC = "slate",
	antTip = "crystal",
	foreW = 0.5,
	tailTuft = "crystal",
}

return { plans = PLANS, forms = FORMS }
