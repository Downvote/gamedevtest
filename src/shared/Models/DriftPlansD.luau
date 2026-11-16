--!strict
-- Body plans sculpted on the smooth solids (Models/DriftAnatomy, Models/DriftKit; GAME_DESIGN 6; the request of
-- 2026-11-15: "can you redo all the creatures and eggs and add alot more extra ones with more variation to them?
-- currently, all of them are modelled using blobs, which is unnatural. reference other models online to see how you
-- should model them"). Each plan returns its Thing, facing +Z with its feet on the ground at y 0; `forms` gives each
-- species of these plans its own variation (Data/Creatures id -> the form its plan reads).
--
-- This module: the lizard, the frog, the crab, the beetle, the snail and the wyrm.
local Kit = require(script.Parent.DriftKit)
local A = require(script.Parent.DriftAnatomy)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full
local UP, FWD = A.UP, A.FWD

type Form = { [string]: any }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

------------------------------------------------------------------ helpers
local lerp = A.lerp

-- The point on a mass's surface in the direction `d` from its centre, and the normal there (an egg's two halves each
-- an ellipsoid of their own, joined at the equator).
local function surf(m: A.Mass, d: Vector3): (Vector3, Vector3)
	local hx, hz = m.size.X / 2, m.size.Z / 2
	local eq = m.rot:VectorToWorldSpace(V(0, m.size.Y * (0.5 - m.split), 0))
	local dl = m.rot:VectorToObjectSpace(d.Unit)
	local hy = if dl.Y >= 0 then m.size.Y * m.split else m.size.Y * (1 - m.split)
	local s = 1 / math.sqrt((dl.X / hx) ^ 2 + (dl.Y / hy) ^ 2 + (dl.Z / hz) ^ 2)
	local pl = dl * s
	local nl = V(pl.X / (hx * hx), pl.Y / (hy * hy), pl.Z / (hz * hz)).Unit
	return m.c + eq + m.rot:VectorToWorldSpace(pl), m.rot:VectorToWorldSpace(nl)
end

-- A spot on a mass: a flat round ellipsoid `d` across lying on the surface in the direction `dir` (its thin side
-- along the normal), standing `out` proud at its middle.
local function spot(name: string, m: A.Mass, dir: Vector3, d: number, color: string, detail: boolean?, neon: boolean?, out: number?, long: number?)
	if detail and not full() then
		return
	end
	local p, n = surf(m, dir)
	local th = math.max(0.1, d * 0.3)
	local rot = A.lie(n, if math.abs(n.Y) < 0.9 then UP else FWD)
	Kit.ell(name, p + n * ((out or 0.03) - th / 2), V(d, th, d * (long or 1)), color, rot, nil, neon)
end

-- A direction from a mass's middle: `yaw` degrees round from its top toward +X (side), `along` how far toward its front
-- (+1) or back (-1).
local function onTop(along: number, yaw: number): Vector3
	return V(math.sin(R(yaw)), math.cos(R(yaw)), along).Unit
end

-- A small pointed cone (a spine, a tooth, a horn tip, a crystal) from `base` to `tip`.
local function cone(name: string, base: Vector3, tip: Vector3, r: number, color: string, detail: boolean?, neon: boolean?)
	Kit.limb(name, base, tip, r, math.max(0.025, r * 0.18), color, nil, nil, detail, neon)
end

-- A curve's tangent at u.
local function tangent(pts: { Vector3 }, u: number): Vector3
	local d = Kit.curveAt(pts, math.min(1, u + 0.02)) - Kit.curveAt(pts, math.max(0, u - 0.02))
	return if d.Magnitude > 1e-5 then d.Unit else FWD
end

-- A list of numbers read at u (0..1, spread evenly).
local function lerpList(xs: { number }, u: number): number
	local k = #xs
	if k == 1 then
		return xs[1]
	end
	local f = math.clamp(u, 0, 1) * (k - 1)
	local i = math.min(math.floor(f), k - 2)
	local s = f - i
	return xs[i + 1] + (xs[i + 2] - xs[i + 1]) * s
end

-- The square-to-the-curve "up" at u (UP made square to the tangent).
local function upAt(pts: { Vector3 }, u: number): Vector3
	local tg = tangent(pts, u)
	local up = UP - tg * UP:Dot(tg)
	return if up.Magnitude > 1e-4 then up.Unit else V(0, 0, 1)
end

-- Blush on the cheeks, up close only (on the islands it is a pixel or two that only muddies the face).
local function blush(hc: Vector3, hr: number, dir: Vector3, spread: number, drop: number, d: number, color: string?)
	if full() then
		Kit.blush(hc, hr, dir, spread, drop, d, color)
	end
end

-- The two sides' names.
local function sideName(side: number): string
	return if side < 0 then "L" else "R"
end

------------------------------------------------------------------ the lizard (gecko, skink, axolotl, chameleon, croc)
-- A real lizard sprawls: the upper arm and thigh go out sideways from the body, the elbow points back and the knee
-- forward, the forearm and shin come down to hands and feet set wide, fingers fanned flat. A long low egg of a body
-- (the chest a little deeper than the hips), a broad head with a short round snout and big eyes high on its sides, a
-- grin running back along each side of the mouth, a tail thick at the root that tapers and lies along the ground in a
-- lazy S. Chibi: the head nearly as wide as the body, the legs short and thick.

-- One sprawled leg (its own joint "leg" .. n). o: r (the top's radius), out (how far the elbow or knee stands out from
-- the hip), c, toes, pads (a toe pad colour), claw (a claw colour), mitten (a chameleon's two-way grip), web (webbed
-- hind toes), hind (true for a hind leg), tall (true: standing more under the body, a chameleon's), fl (toe length)
local function sprawlLeg(n: string, side: number, ph: number, hip: Vector3, o: Form)
	J("leg" .. n, "body", hip, "leg", side, ph)
	local r: number = o.r or 0.1
	local out: number = o.out or 0.22
	local c: string = o.c
	local hind = o.hind == true
	local tall = o.tall == true
	-- the elbow points back, the knee forward; a tall stance keeps them under the body
	local elbow = V(hip.X + side * out * (if tall then 0.5 else 1), hip.Y * (if tall then 0.6 else 0.78), hip.Z + (if hind then r * 1.1 else -r * 0.6))
	local wrist = V(elbow.X + side * out * (if tall then 0.12 else 0.25), r * 0.95, elbow.Z + (if hind then -r * 1.3 else r * 1.1))
	Kit.limb("Leg" .. n, hip, elbow, r * 1.25, r * 0.95, c)
	Kit.limb("Leg" .. n, elbow, wrist, r * 0.95, r * 0.8, c)
	-- the hand flat on the ground, the fingers fanned (the hands forward and out, the feet out and a little back)
	local fd = if hind then V(side * 0.85, 0, -0.25).Unit else V(side * 0.45, 0, 1).Unit
	if tall then
		fd = V(side * 0.15, 0, if hind then -1 else 1).Unit
	end
	local palm = V(wrist.X, r * 0.42, wrist.Z) + fd * r * 0.45
	local pr = r * 1.2
	Kit.ell("Palm" .. n, palm, V(pr * 2, r * 0.9, pr * 2.1), c, A.lie(UP, fd))
	if o.mitten then
		-- a chameleon's foot: two bundles of toes gripping opposite ways, like a mitten
		if not full() then
			return
		end
		for _, s in { -1, 1 } do
			local d = (CFrame.fromAxisAngle(UP, R(40 * s))):VectorToWorldSpace(fd)
			Kit.limb("Toe" .. n, palm + UP * 0.01, palm + d * r * 2.2 + UP * 0.01, r * 0.6, r * 0.45, c)
		end
		return
	end
	if not full() then
		return
	end
	local k: number = o.toes or 5
	local fl: number = o.fl or r * 1.5
	local fan: number = o.fan or 56
	for i = 1, k do
		local ang = (-1 + 2 * (i - 1) / math.max(1, k - 1)) * fan
		local d = (CFrame.fromAxisAngle(UP, R(-ang))):VectorToWorldSpace(fd)
		local len = fl * (1 - math.abs(ang) / fan * 0.25)
		local b0 = palm + d * pr * 0.6
		local tip = b0 + d * len
		Kit.limb("Toe" .. n, b0, tip, r * 0.4, r * 0.34, c)
		if o.pads then
			Kit.ell("ToePad" .. n, tip, V(r * 1.0, r * 0.6, r * 1.0), o.pads, A.lie(UP, d))
		elseif o.claw then
			Kit.limb("Claw" .. n, tip, tip + d * r * 0.65 - UP * r * 0.2, r * 0.28, r * 0.08, o.claw)
		end
	end
	if o.web then
		Kit.limb("Web" .. n, palm, palm + fd * fl * 1.2, pr * 0.8, fl * 0.62, o.web, 0.2, UP)
	end
end

-- A gecko's head (on the "head" joint, with its jaw): an egg lying forward, wide at the jowls and narrowing to a round
-- snout; big eyes high on its sides; a grin from the snout's tip back along each side; nostrils; a pale chin on the jaw
-- that drops when the mouth opens. W, L, H its width, length and height; split how long its front end is (0.5 round).
local function lizHead(hc: Vector3, W: number, L: number, H: number, split: number, b: string, a: string, f: Form, ink: string, under: string): A.Mass
	-- (held a little up, so the face shows)
	local tilt: number = f.tilt or 14
	local fwd = A.dir(0, tilt)
	local rot = A.lie(fwd, UP)
	Kit.egg("Head", hc, V(W, L, H), split, b, rot)
	local m: A.Mass = { c = hc, size = V(W, L, H), rot = rot, split = split }
	local eq = hc + fwd * L * (0.5 - split)
	local fr = L * split
	-- the chin on the jaw, under the snout
	J("jaw", "head", eq + V(0, -H * 0.22, -fr * 0.2), "jaw")
	Kit.ell("Chin", eq + V(0, -H * 0.27, fr * 0.32), V(W * 0.64, H * 0.34, fr * 1.0), f.chin or b, rot)
	Kit.on("head")
	-- the eyes high on the head's front corners, the blush below and in front of them
	local e: { number } = f.eye or { R(34), R(26), 0.32 }
	Kit.faceOn(eq, V(W / 2, fr, H / 2), rot)
	local avg = (W / 2 + fr + H / 2) / 3
	if not f.noEyes then
		Kit.eyes(eq, avg, fwd, e[1], e[2], e[3], A.iris(a, "gold"), if ink ~= "black" then ink else nil)
	end
	if f.blush ~= false then
		blush(eq, avg, fwd, e[1] * 1.15, R(4), W * 0.16)
	end
	Kit.faceOff()
	-- the grin: the smile at the snout's tip, carried back along each side as a thin line
	local mp, mn = surf(m, A.dir(0, tilt - 30))
	Kit.mouth(mp, mn, W * (f.grin or 0.3), ink)
	if full() then
		for _, side in { -1, 1 } do
			local pts: { Vector3 } = {}
			local reach: number = f.grinBack or 60
			for i = 0, 3 do
				local yaw = 16 + i / 3 * (reach - 16)
				local p, n = surf(m, A.dir(side * yaw, tilt - 27 + i * 4))
				table.insert(pts, p + n * 0.012)
			end
			Kit.limbs("Lip", pts, { 0.03, 0.025 }, ink, 3)
		end
		for _, side in { -1, 1 } do
			local p, n = surf(m, A.dir(side * 9, tilt + 8))
			Kit.ell("Nostril", p + n * 0.005, V(0.06, 0.05, 0.06), A.shade(b), A.lie(n))
		end
	end
	return m
end

PLANS.lizard = function(b, a, form)
	local f: Form = form or {}
	local big: number = f.big or 1
	local t = Kit.new("lizard", 1.4 * big, 1.3 * big, "quad")
	local ink = A.ink(b, a)
	local under: string = f.under or A.under(b)
	local len: number = (f.len or 1.15) * big
	local wide: number = (f.wide or 0.7) * big
	local tall: number = (f.tall or 0.5) * big
	local by: number = (f.y or 0.4) * big
	local legR: number = (f.legR or 0.1) * big
	J("body", nil, V(0, by, 0), "body")
	local _, body = A.body("Body", V(0, by, 0), V(0, f.arch or 0.06, 1).Unit, len, wide, tall, f.split or 0.55, b)
	A.patch("Belly", body, V(0, -1, 0.05), V(0.82, 0.88, 0.7), 0.02, under)
	-- the back's markings
	local back: string = f.back or "spots"
	if back == "spots" then
		for i, s in { { 0.3, -24, 0.27 }, { 0.05, 34, 0.24 }, { -0.25, -12, 0.28 }, { -0.5, 30, 0.2 }, { 0.5, 20, 0.17 }, { -0.05, -58, 0.16 }, { -0.35, 62, 0.15 } } do
			spot("Spot", body, onTop(s[1], s[2]), s[3] * big, a, i > 4, nil, 0.035)
		end
	elseif back == "stripes" then
		-- two dark stripes down the back from the neck to the hips: long narrow caps of the body
		for _, side in { -1, 1 } do
			A.patch("Stripe", body, V(side * 0.55, 1, 0), V(0.22, 0.94, 0.5), 0.02, a)
		end
	elseif back == "trail" then
		-- a row of little lit dots down the spine, the way its tail's glow trails behind it
		local k = if full() then 4 else 2
		for i = 0, k - 1 do
			local u = 0.45 - i * (1.0 / math.max(1, k - 1))
			spot("Glint", body, onTop(u, 0), 0.13 - i * 0.012, a, nil, true, 0.04)
		end
	elseif back == "scutes" then
		-- a croc's armour: two rows of raised keels down the back, a lower row either side
		local k = if full() then 6 else 3
		for i = 0, k - 1 do
			local u = 0.6 - i * (1.35 / (k - 1))
			for _, side in { -1, 1 } do
				local p, n = surf(body, onTop(u, side * 16))
				Kit.ell("Scute", p + n * 0.025, V(0.13, 0.11, 0.17) * big, A.shade(b), A.lie(n, FWD))
			end
		end
		if full() then
			for i = 0, 2 do
				local u = 0.4 - i * 0.4
				for _, side in { -1, 1 } do
					local p, n = surf(body, onTop(u, side * 46))
					Kit.ell("Scute", p + n * 0.02, V(0.1, 0.09, 0.13) * big, A.shade(b), A.lie(n, FWD))
				end
			end
		end
	end
	if f.stripe then
		-- a band of the accent along each flank (a chameleon's)
		for _, side in { -1, 1 } do
			local pts: { Vector3 } = {}
			for i = 0, 5 do
				local p, n = surf(body, V(side, 0.05, 0.75 - i * 0.3))
				table.insert(pts, p + n * 0.01)
			end
			Kit.limbs("FlankBand", pts, { 0.06, 0.075, 0.05 }, f.stripe, if full() then 5 else 3, 0.5, V(side, 0, 0))
		end
	end
	if f.crest and full() then
		-- a row of little bumps down the spine, tallest at the shoulders
		local k = 7
		for i = 0, k - 1 do
			local u = 0.6 - i * (1.25 / (k - 1))
			local p, n = surf(body, onTop(u, 0))
			local hgt = (0.05 + 0.04 * math.sin((1 - i / (k - 1)) * math.pi * 0.8)) * (if full() then 1 else 1.4)
			Kit.ell("Crest", p + n * hgt * 0.3, V(0.07, hgt * 1.6, 0.1) * (if full() then 1 else 1.3), f.crest, A.lie(n, FWD))
		end
	end
	if f.fin then
		-- an axolotl's fin: a soft frill from the middle of the back on down the tail
		local pts: { Vector3 } = {}
		for i = 0, 3 do
			local p, n = surf(body, onTop(0.1 - i * 0.33, 0))
			table.insert(pts, p + n * (0.02 + math.sin(i / 3 * math.pi) * 0.05))
		end
		Kit.limbs("BackFin", pts, { 0.04, 0.09, 0.08 }, f.fin, 3, 0.3, V(1, 0, 0))
	end
	-- the neck, and the legs
	local hc: Vector3 = (f.hc or V(0, 0.66, 0.84)) * big
	local hs: Vector3 = (f.hs or V(0.86, 0.82, 0.56)) * big -- width, length, height
	local nb = V(0, by + 0.04 * big, len * 0.28)
	local nt = V(0, hc.Y - hs.Z * 0.12, hc.Z - hs.Y * 0.25)
	Kit.limb("Neck", nb, nt, math.min(wide, tall) * 0.42, math.min(hs.X, hs.Z) * 0.42, b)
	for _, l in { { n = "FL", s = -1, ph = 0, h = false }, { n = "FR", s = 1, ph = 0.5, h = false }, { n = "BL", s = -1, ph = 0.5, h = true }, { n = "BR", s = 1, ph = 0, h = true } } do
		local z = if l.h then -len * 0.28 else len * 0.28
		local hip = V(l.s * wide * 0.34, by - tall * 0.12, z)
		Kit.on("body")
		sprawlLeg(l.n, l.s, l.ph, hip, {
			r = legR * (if l.h then 1.1 else 1),
			out = (f.out or 0.22) * big,
			c = b,
			hind = l.h,
			tall = f.tallLegs,
			toes = if l.h then (f.toes or 5) else (f.ftoes or f.toes or 5),
			pads = if f.pads then a else nil,
			claw = f.claw,
			mitten = f.mitten,
			web = if l.h then f.web else nil,
			fl = if f.fl then f.fl * big else nil,
			fan = f.fan,
		})
	end
	-- the tail
	Kit.on("body")
	local tk: string = f.tail or "gecko"
	local tl: number = (f.tailLen or 1.0) * big
	local tr: number = (f.tailR or 0.22) * big
	local t0 = V(0, by - tall * 0.02, -len * 0.36)
	J("tail1", "body", t0, "tail", 0, 1)
	if tk == "curl" then
		-- a chameleon's tail: back, then rolled down and under in a spiral that winds in on itself
		local pts = { t0, t0 + V(0, 0.05, -0.42) * tl, t0 + V(0, 0.0, -0.8) * tl }
		Kit.limbs("Tail", pts, { tr, tr * 0.75 }, b, 2)
		local mid = pts[3]
		J("tail2", "tail1", mid, "tail", 0, 2)
		local rad0: number = (f.curlR or 0.26) * tl
		local sc = mid + V(0, -rad0, -0.04)
		local sp: { Vector3 } = { mid }
		local k = 10
		for i = 1, k do
			local ang = i / k * math.pi * 2.3
			local rad = rad0 * (1 - i / k * 0.7)
			table.insert(sp, sc + V(0, math.cos(ang) * rad, -math.sin(ang) * rad))
		end
		Kit.limbs("Tail", sp, { tr * 0.75, tr * 0.55, tr * 0.38, tr * 0.28 }, b, if full() then 8 else 4)
	else
		-- a curve along the ground in a lazy S
		local sway: number = f.sway or 0.18
		local drop = by - tr * 0.85
		local pts = {
			t0,
			t0 + V(sway * 0.25, -drop * 0.55, -0.36 * tl),
			t0 + V(sway * 0.8, -drop * 0.92, -0.72 * tl),
		}
		local tail2 = {
			pts[3],
			t0 + V(sway * 0.95, -drop, -1.06 * tl),
			t0 + V(sway * 0.3, -drop * 0.98, -1.38 * tl),
			t0 + V(-sway * 0.5, -drop * 0.94, -1.62 * tl),
		}
		local rr: { number } = if tk == "whip" then { tr, tr * 0.58 } else { tr, tr * 0.7 }
		local flat = if tk == "paddle" or tk == "croc" then 0.62 else nil
		Kit.limbs("Tail", pts, rr, b, 2, flat, V(1, 0, 0))
		if tk == "croc" and full() then
			-- the croc's crest: two rows of keels on the tail's root
			for _, u in { 0.3, 0.7 } do
				local p, up = Kit.curveAt(pts, u), upAt(pts, u)
				local rad = lerpList(rr, u)
				for _, s in { -1, 1 } do
					local q = p + up * rad * 0.62 + V(s * rad * 0.3, 0, 0)
					Kit.ell("TailKeel", q, V(0.1, 0.11, 0.15) * big, A.shade(b), A.lie(up, FWD))
				end
			end
		end
		if tk == "paddle" then
			-- the paddle: a thin fin along the top of the tail's root
			Kit.limbs("TailFin", { pts[1] + UP * tr * 0.8, pts[2] + UP * tr * 1.15, pts[3] + UP * tr * 1.1 }, { 0.04, 0.09, 0.1 }, f.fin or a, 2, 0.3, V(1, 0, 0))
		end
		J("tail2", "tail1", pts[3], "tail", 0, 2)
		local r2 = rr[2]
		if tk == "leaf" then
			-- a leaf-tailed gecko's: the tail narrows, then spreads into a flat leaf with a midrib and veins
			Kit.limbs("Tail", { tail2[1], tail2[2] }, { r2, r2 * 0.62 }, b, 1)
			local ld = (tail2[4] - tail2[2]).Unit
			local ll = (tail2[4] - tail2[2]).Magnitude * 1.3
			local lc = tail2[2] + ld * ll * 0.48 + UP * 0.03
			local lrot = A.lie(ld, UP) * CFrame.Angles(0, R(10), 0)
			Kit.egg("TailLeaf", lc, V(0.66 * tl, ll, 0.1), 0.6, b, lrot)
			if full() then
				Kit.limb("TailRib", tail2[2] + UP * 0.06, lc + ld * ll * 0.42 + UP * 0.06, 0.03, 0.025, a)
				for _, s in { -1, 1 } do
					for _, u in { 0.2, 0.5 } do
						local p = tail2[2] + ld * ll * u + UP * 0.07
						local side = UP:Cross(ld).Unit * s
						Kit.limb("TailVein", p, p + side * 0.18 * tl + ld * 0.12, 0.025, 0.025, a)
					end
				end
			end
		elseif tk == "glow" then
			-- the tail lights up toward its end: a lit band, then a lit tip like a comet's head
			Kit.limbs("Tail", { tail2[1], tail2[2], tail2[3] }, { r2, r2 * 0.72 }, b, 2)
			local tg = (tail2[4] - tail2[3]).Unit
			Kit.limb("TailGlow", tail2[3], tail2[4], r2 * 0.72, r2 * 0.95, a, nil, nil, nil, true)
			Kit.egg("TailComet", tail2[4] + tg * 0.08 * big, V(0.26, 0.36, 0.26) * big, 0.64, a, A.lie(tg), nil, true)
			if full() then
				local p = Kit.curveAt(tail2, 0.3)
				local tg2 = tangent(tail2, 0.3)
				local rad = lerpList({ r2, r2 * 0.72 }, 0.3 / 0.66)
				Kit.limb("TailBand", p - tg2 * 0.035, p + tg2 * 0.035, rad + 0.03, rad + 0.03, a, nil, nil, nil, true)
			end
		elseif tk == "paddle" then
			Kit.limbs("Tail", tail2, { r2, r2 * 0.4 }, b, 3, 0.62, V(1, 0, 0))
			Kit.limbs("TailFin", { tail2[1] + UP * r2 * 1.15, tail2[2] + UP * r2 * 1.3, tail2[3] + UP * r2 * 1.05, tail2[4] + UP * 0.02 }, { 0.12, 0.13, 0.09, 0.03 }, f.fin or a, 3, 0.3, V(1, 0, 0))
		else
			Kit.limbs("Tail", tail2, { r2, r2 * (if tk == "whip" then 0.22 else 0.3) }, b, 3, flat, V(1, 0, 0))
			if tk == "croc" then
				-- (the keels join into one row down the tail)
				for i, u in { 0.12, 0.38, 0.62, 0.86 } do
					if full() then
						local p, up = Kit.curveAt(tail2, u), upAt(tail2, u)
						local rad = r2 * (1 - u * 0.68)
						Kit.ell("TailKeel", p + up * rad * 0.62, V(0.07, 0.13, 0.15) * big * (1 - u * 0.4), A.shade(b), A.lie(up, tangent(tail2, u)))
					end
				end
			end
		end
	end
	-- the head
	Kit.on("body")
	local kind: string = f.head or "gecko"
	local hpivot = lerp(nb, nt, 0.6)
	if kind == "chameleon" then
		-- a chameleon's head: a narrow skull with a casque rising to a point at the back, eyes in turrets
		J("head", "body", hpivot, "head")
		local m = lizHead(hc, hs.X, hs.Y, hs.Z, 0.62, b, a, { noEyes = true, blush = false, grin = 0.3, grinBack = 54, tilt = 4 }, ink, under)
		-- the casque: a flat egg of skull up and back from the brow, its rim in the accent
		local cd = V(0, 0.8, -0.6).Unit
		local cc = hc + V(0, hs.Z * 0.42, -hs.Y * 0.16)
		local cl = hs.Z * 1.3
		Kit.egg("Casque", cc, V(hs.X * 0.42, cl, hs.Y * 0.62), 0.7, b, A.lie(cd, FWD))
		local peak = cc + cd * cl * 0.3
		Kit.limbs("CasqueRim", { hc + V(0, hs.Z * 0.45, hs.Y * 0.2), cc + V(0, hs.Z * 0.12, hs.Y * 0.12) + cd * cl * 0.05, peak }, { 0.035, 0.045, 0.04 }, a, 2)
		-- the turrets: round cones on each side of the skull, the eye looking out of the tip
		for _, side in { -1, 1 } do
			local s = sideName(side)
			local td = V(side * 0.62, 0.36, 0.7).Unit
			local tw = hs.X * 0.6
			local ps = surf(m, td)
			local tc = ps - td * tw * 0.22
			local trot = A.lie(td, UP)
			Kit.egg("Turret" .. s, tc, V(tw, tw * 1.1, tw), 0.6, b, trot)
			Kit.faceOn(tc - td * tw * 0.11, V(tw / 2, tw * 0.66, tw / 2), trot)
			Kit.eye(s, tc, tw * 0.55, td, tw * 0.58, A.iris(a, "gold"))
			Kit.faceOff()
		end
		Kit.on("head")
		return t
	elseif kind == "croc" then
		local h = A.head({
			c = hc,
			size = V(hs.X, hs.Z, hs.Y),
			color = b,
			pivot = hpivot,
			muzzle = "lizard",
			mlen = (f.mlen or 0.7) * big,
			mw = (f.mw or 0.46) * big,
			mdrop = (f.mdrop or 0.08) * big,
			eye = f.eye or { R(32), R(34), 0.24 },
			iris = A.iris(a, "gold"),
			ink = ink,
			blush = false,
			tongue = "pink",
		})
		-- a croc's grin: a row of teeth showing along the upper jaw
		local root = hc + V(0, -(f.mdrop or 0.08) * big, hs.Y * 0.5 * 0.55)
		local mlen: number = (f.mlen or 0.7) * big
		local mw: number = (f.mw or 0.46) * big
		local tip = root + V(0, -mlen * 0.02, mlen)
		local k = if full() then 5 else 2
		for _, side in { -1, 1 } do
			for i = 1, k do
				local u = 0.2 + (i - 1) / math.max(1, k - 1) * 0.68
				local w = mw * 0.5 * (1 - u * 0.3)
				local p = lerp(root, tip, u) + V(side * w * 0.84, -w * 0.36, 0)
				local L = (if i == 2 then 0.12 else 0.085) * big * (if full() then 1 else 1.3)
				cone("Tooth", p, p - UP * L + V(side * 0.012, 0, 0), 0.035 * big * (if full() then 1 else 1.4), "white")
			end
		end
		-- the nose's knob and the brows' bumps, standing above the flat skull as a croc's do
		Kit.ell("NoseKnob", tip + V(0, mw * 0.18, mw * 0.06), V(mw * 0.55, mw * 0.32, mw * 0.42), b)
		local _ = h
		return t
	end
	J("head", "body", hpivot, "head")
	local m = lizHead(hc, hs.X, hs.Y, hs.Z, f.hsplit or 0.58, b, a, f, ink, under)
	if f.gills then
		-- an axolotl's gills: three feathery stalks fanning up and back from behind each cheek
		for _, side in { -1, 1 } do
			local root = hc + V(side * hs.X * 0.38, hs.Z * 0.12, -hs.Y * 0.18)
			for i, d in { V(side * 0.5, 0.9, -0.35), V(side * 0.85, 0.5, -0.4), V(side * 0.95, 0.05, -0.45) } do
				local L = (0.46 - math.abs(i - 2) * 0.04) * big
				local du = d.Unit
				local tip = root + du * L
				local across = du:Cross(FWD)
				across = if across.Magnitude > 1e-3 then across.Unit else UP
				Kit.limb("Gill", root, tip, 0.08 * big, 0.075 * big, f.gills)
				if full() then
					-- the feathery fringe: soft round fronds along the stalk's upper edge, growing toward its tip
					for k = 1, 3 do
						local p = lerp(root, tip, 0.3 + k * 0.22) + UP * 0.05 * big
						local fs = (0.1 + k * 0.02) * big
						Kit.ell("GillFrond", p, V(fs, fs * 0.8, fs), f.gillTip or f.gills)
					end
				end
			end
		end
	end
	if f.headFins then
		-- swept-back fins off the back of the head, tipped in the accent
		for _, side in { -1, 1 } do
			for i, d in { V(side * 0.35, 0.6, -0.75), V(side * 0.75, 0.2, -0.7) } do
				if not full() and i == 2 then
					break
				end
				local root = hc + V(side * hs.X * 0.26, hs.Z * 0.2, -hs.Y * 0.22)
				local du = d.Unit
				local tip = root + du * (0.38 - i * 0.08) * big
				local fn = du:Cross(FWD)
				Kit.limb("HeadFin", root, tip, 0.1, 0.04, b, 0.75, fn)
				Kit.limb("HeadFinTip", lerp(root, tip, 0.55), tip + du * 0.02, 0.07, 0.035, a, 0.8, fn)
			end
		end
	end
	if f.spotsHead then
		for i, d in { V(-0.35, 1, -0.4), V(0.4, 1, -0.1), V(0, 1, -0.9) } do
			spot("HeadSpot", m, d, 0.15 * big, a, i == 3, nil, 0.03)
		end
	end
	return t
end

FORMS.frondle = { back = "spots", pads = true, tail = "leaf", tailLen = 1.0, spotsHead = true, under = "cream", eye = { R(28), R(26), 0.28 } }
FORMS.reedle = { len = 1.4, wide = 0.5, tall = 0.4, y = 0.34, legR = 0.075, out = 0.24, back = "stripes", tail = "whip", tailLen = 1.45, tailR = 0.16, hs = V(0.62, 0.84, 0.46), hc = V(0, 0.58, 0.96), hsplit = 0.62, eye = { R(36), R(24), 0.24 }, fl = 0.18, claw = "wood_dark", sway = 0.3, grinBack = 56 }
FORMS.cometail = { back = "trail", tail = "glow", tailLen = 1.05, headFins = true, claw = "jeans", eye = { R(34), R(24), 0.34 } }
FORMS.gillo = { len = 1.1, wide = 0.72, tall = 0.52, y = 0.38, legR = 0.085, out = 0.18, back = "none", tail = "paddle", tailLen = 0.9, tailR = 0.2, fin = "cherry", hs = V(1.04, 0.72, 0.52), hc = V(0, 0.64, 0.8), hsplit = 0.5, eye = { R(34), R(22), 0.32 }, tilt = 18, gills = "coral", gillTip = "coral", toes = 4, ftoes = 4, fl = 0.12, under = "cherry", grin = 0.42, grinBack = 46 }
FORMS.vinegeck = { len = 1.0, wide = 0.46, tall = 0.66, y = 0.52, arch = 0.14, split = 0.5, legR = 0.08, out = 0.16, tallLegs = true, mitten = true, back = "none", crest = "gold", stripe = "gold", tail = "curl", tailLen = 1.0, tailR = 0.14, curlR = 0.25, head = "chameleon", hs = V(0.54, 0.74, 0.54), hc = V(0, 0.9, 0.72) }
FORMS.grinmire = { big = 1.1, len = 1.5, wide = 0.78, tall = 0.46, y = 0.34, legR = 0.105, out = 0.22, back = "scutes", tail = "croc", tailLen = 1.3, tailR = 0.24, head = "croc", hs = V(0.7, 0.62, 0.46), hc = V(0, 0.54, 0.95), mlen = 0.72, mw = 0.46, mdrop = 0.06, eye = { R(30), R(34), 0.24 }, claw = "sand_dark", toes = 3, ftoes = 3, fan = 44, under = "sand" }

------------------------------------------------------------------ the frog (tree frog, mud frog, toad)
-- A real frog sits: the rump on the ground and the body sloping up to the shoulders, no neck, a wide flat head with
-- the eyes bulging up on top, a mouth that runs right round the front of the head, a pale throat; the hind legs big
-- and folded in a Z along each flank (the thigh forward to the knee, the shin back, the long webbed foot forward again
-- on the ground), the forelegs small and straight, propping up the front on splayed fingers.
PLANS.frog = function(b, a, form)
	local f: Form = form or {}
	local big: number = f.big or 1
	local t = Kit.new("frog", 1.4 * big, 1.1 * big, "hop")
	local ink = A.ink(b, a)
	local under: string = f.under or A.under(b)
	local wide: number = (f.wide or 0.92) * big
	local toad = f.toad == true
	J("body", nil, V(0, 0.4 * big, 0), "body")
	-- the body: an egg from the low rump up to the shoulders, broad at the hips
	local _, body = A.body("Body", V(0, 0.42, -0.12) * big, V(0, f.slope or 0.5, 1).Unit, (f.len or 1.0) * big, wide, (f.tall or 0.7) * big, 0.44, b)
	A.patch("Belly", body, V(0, -0.7, 1), V(0.8, 0.86, 0.8), 0.02, under)
	-- the head: wide and flat, its eyes in domes on top
	local hc = V(0, 0.7, 0.36) * big
	local hs = V(wide * 1.08, 0.46 * big, 0.76 * big)
	J("head", "body", V(0, 0.6, 0.1) * big, "head")
	local _, head = A.blob("Head", hc, hs, b)
	-- the lower jaw on the jaw joint, under the head's front, its pale throat underneath
	J("jaw", "head", V(0, 0.56, 0.02) * big, "jaw")
	local jc = hc + V(0, -0.17, 0.05) * big
	local js = V(hs.X * 0.9, 0.26 * big, hs.Z * 0.86)
	local _, jaw = A.blob("Jaw", jc, js, b)
	A.patch("Throat", jaw, V(0, -1, 0.2), V(0.84, 0.8, 0.86), 0.015, under)
	if f.sac then
		-- a mud frog's song: the throat blown out into a pale bubble
		Kit.ell("Sac", hc + V(0, -0.24, 0.28) * big, V(0.44, 0.32, 0.38) * big, f.sac)
	end
	if f.icicles then
		-- icicles hanging from the chin
		for i, x in { -0.18, 0, 0.17 } do
			if not full() and i ~= 2 then
				continue
			end
			local p = hc + V(x, -0.28, 0.28 - math.abs(x) * 0.4) * big
			cone("Icicle", p + UP * 0.04, p - UP * (if i == 2 then 0.2 else 0.14) * big, 0.05 * big, f.icicles)
		end
	end
	Kit.on("head")
	-- the mouth: a line right round the front of the head, the smile in the middle
	local mp, mn = surf(head, V(0, -0.42, 1))
	Kit.mouth(mp + mn * 0.01, mn, hs.X * 0.3, ink)
	if full() then
		local pts: { Vector3 } = {}
		for i = -3, 3 do
			local yaw = i * 22
			local p, n = surf(head, A.dir(yaw, -20 + math.abs(i) * 3))
			table.insert(pts, p + n * 0.012)
		end
		Kit.limbs("Lip", pts, { 0.03 }, ink, 6)
		for _, side in { -1, 1 } do
			local p, n = surf(head, A.dir(side * 10, 8))
			Kit.ell("Nostril", p + n * 0.005, V(0.06, 0.05, 0.06), A.shade(b), A.lie(n))
		end
	end
	-- the eyes, each in a dome bulging up from the top of the head
	local dr: number = (f.dome or 0.4) * big
	for _, side in { -1, 1 } do
		local s = sideName(side)
		local dc = hc + V(side * hs.X * 0.27, hs.Y * 0.42, hs.Z * 0.08)
		Kit.ell("Dome" .. s, dc, V(dr, dr * 0.92, dr), b)
		Kit.faceOn(dc, V(dr / 2, dr * 0.46, dr / 2))
		Kit.eye(s, dc, dr / 2, V(side * 0.55, 0.42, 0.72).Unit, dr * (f.eyeD or 0.78), A.iris(a, "gold"), if ink ~= "black" then ink else nil)
		Kit.faceOff()
		if f.brow then
			-- a toad's heavy brow over the dome
			Kit.ell("Brow" .. s, dc + V(side * 0.03, dr * 0.3, -dr * 0.22), V(dr * 0.9, dr * 0.34, dr * 0.6), f.brow)
		end
		-- the eardrum behind the eye
		if full() and not toad then
			local p, n = surf(head, V(side * 0.95, 0.35, -0.25))
			Kit.ell("Tympanum" .. s, p + n * 0.01, V(0.2, 0.05, 0.2) * big * (f.ear or 1), f.earC or A.shade(b), A.lie(n))
		end
	end
	if f.blush ~= false then
		Kit.faceOn(hc, hs / 2)
		blush(hc, (hs.X + hs.Y + hs.Z) / 6, FWD, R(40), R(10), 0.17 * big)
		Kit.faceOff()
	end
	if f.sprout then
		-- a sprout from between the eyes: a little stem, two leaves, a bud
		local base = hc + V(0, hs.Y * 0.45, -hs.Z * 0.12)
		local top = base + V(0.02, 0.28, -0.04) * big
		Kit.limb("Stem", base, top, 0.05, 0.04, f.stem or "leaf_dark")
		for _, side in { -1, 1 } do
			local d = V(side * 0.85, 0.4, 0.15).Unit
			Kit.egg("Leaf", top + d * 0.15 * big, V(0.2, 0.34, 0.1) * big, 0.6, f.sprout, A.lie(d, V(0, 1, 0.5)))
			if full() then
				Kit.limb("LeafVein", top + d * 0.04, top + d * 0.26 * big + UP * 0.03, 0.025, 0.025, f.stem or "leaf_dark")
			end
		end
		if f.bud then
			Kit.ell("Bud", top + UP * 0.04, V(0.12, 0.13, 0.12) * big, f.bud)
		end
	end
	if toad and f.glands then
		-- a toad's glands: big oval lumps behind the eyes
		for _, side in { -1, 1 } do
			local p, n = surf(head, V(side * 0.75, 0.5, -0.75))
			Kit.ell("Gland", p + n * 0.02, V(0.22, 0.17, 0.34) * big, b, A.lie(n, FWD))
		end
	end
	-- the back: spots, warts or frost
	Kit.on("body")
	local marks: { { number } } = { { 0.15, -30, 0.22 }, { -0.15, 28, 0.2 }, { -0.45, -14, 0.18 }, { 0.35, 22, 0.15 }, { -0.25, -62, 0.14 }, { -0.6, 48, 0.13 } }
	if f.spots then
		for i, m in marks do
			spot("Spot", body, onTop(m[1], m[2]), m[3] * big, f.spots, i > 3, nil, 0.03)
		end
	end
	if f.warts then
		-- warts over the back and the rump, the bigger ones lit like embers
		local k = if full() then 9 else 4
		for i = 1, k do
			local u = -0.15 - (i - 1) * (0.75 / (k - 1))
			local yaw = (((i * 53) % 150) - 75) * (if full() then 1 else 0.6)
			local p, n = surf(body, onTop(u, yaw))
			local lit = (i % 2 == 1) and f.warts ~= true
			local d = (if lit then 0.15 else 0.12) * big * (if full() then 1 else 1.3)
			Kit.ell("Wart", p + n * 0.01, V(d, d * 0.65, d), b, A.lie(n))
			if lit then
				Kit.ell("Ember", p + n * (0.02 + d * 0.3), V(d * 0.6, 0.05, d * 0.6), f.warts, A.lie(n), nil, true)
			end
		end
	end
	if f.frost then
		-- frost: little ice crystals standing up along the back
		local k = if full() then 5 else 3
		for i = 1, k do
			local u = 0.35 - (i - 1) * (0.9 / (k - 1))
			for _, side in { -1, 1 } do
				if full() or side == (if i % 2 == 0 then 1 else -1) then
					local p, n = surf(body, onTop(u, side * 26))
					cone("Frost", p - n * 0.02, p + (n + UP * 0.4).Unit * (0.14 - math.abs(u) * 0.06) * big, 0.05 * big, f.frost)
				end
			end
		end
	end
	if f.ridge then
		-- the folds of skin down each side of the back
		for _, side in { -1, 1 } do
			A.patch("Ridge", body, V(side * 0.62, 1, -0.1), V(0.2, 0.9, 0.5), 0.025, f.ridge, true)
		end
	end
	-- the forelegs: short and straight, the hands turned in a little on splayed fingers
	for _, side in { -1, 1 } do
		local s = sideName(side)
		Kit.on("body")
		local sh = V(side * 0.3, 0.42, 0.32) * big
		J("arm" .. s, "body", sh, "arm", side)
		local el = V(side * 0.42, 0.22, 0.34) * big
		local wr = V(side * 0.42, 0.07, 0.5) * big
		local r: number = (f.armR or 0.09) * big
		Kit.limb("Arm" .. s, sh, el, r * 1.15, r, b)
		Kit.limb("Arm" .. s, el, wr, r, r * 0.85, b)
		local fd = V(-side * 0.25, 0, 1).Unit
		Kit.ell("Hand" .. s, wr + V(0, -0.02, 0.03), V(r * 2.4, r * 0.9, r * 2.2), b, A.lie(UP, fd))
		if full() then
			for i, ang in { -48, -14, 18, 50 } do
				local d = (CFrame.fromAxisAngle(UP, R(-ang))):VectorToWorldSpace(fd)
				local b0 = wr + V(0, -0.03, 0.03) + d * r * 0.8
				local tip = b0 + d * r * (if i == 2 or i == 3 then 1.8 else 1.4)
				Kit.limb("Finger" .. s, b0, tip, r * 0.38, r * 0.32, b)
				if f.pads then
					Kit.ell("Pad" .. s, tip, V(r * 1.0, r * 0.6, r * 1.0), f.pads)
				end
			end
		end
	end
	-- the hind legs folded along the flanks: thigh forward, shin back, the long foot forward on the ground
	for _, side in { -1, 1 } do
		local s = sideName(side)
		Kit.on("body")
		local hip = V(side * 0.32, 0.32, -0.32) * big
		J("leg" .. s, "body", hip, "leg", side, 0)
		local r: number = (f.legR or 0.21) * big
		local knee = V(side * 0.6, 0.28, 0.08) * big
		local ankle = V(side * 0.54, 0.09, -0.34) * big
		Kit.limb("Thigh" .. s, hip, knee, r * 1.1, r * 0.72, b)
		Kit.limb("Shin" .. s, knee, ankle, r * 0.66, r * 0.42, b)
		if f.warts and f.warts ~= true and full() then
			for _, u in { 0.35, 0.7 } do
				local c = lerp(hip, knee, u) + V(side * r * 0.75, r * 0.55, 0)
				Kit.ell("Ember" .. s, c, V(0.08, 0.06, 0.08) * big, f.warts, nil, nil, true)
			end
		end
		if f.bands and full() then
			-- bands across the thigh and the shin, as many frogs have
			local function band(p0: Vector3, p1: Vector3, u: number, rad: number)
				local c = lerp(p0, p1, u)
				local ax = (p1 - p0).Unit
				Kit.limb("Band" .. s, c - ax * 0.035, c + ax * 0.035, rad + 0.02, rad + 0.02, f.bands)
			end
			band(hip, knee, 0.45, r * 0.95)
			band(knee, ankle, 0.5, r * 0.56)
		end
		-- the foot: forward from the ankle, the toes spreading into a web
		local fd = V(side * 0.35, 0, 1).Unit
		local heel = ankle + V(0, -0.04, 0.04) * big
		local ball = heel + fd * 0.3 * big
		Kit.limb("Foot" .. s, heel, ball, r * 0.4, r * 0.32, b)
		if full() then
			for i, ang in { -36, -10, 14, 40 } do
				local d = (CFrame.fromAxisAngle(UP, R(-ang))):VectorToWorldSpace(fd)
				local tip = ball + d * (if i == 2 or i == 3 then 0.24 else 0.18) * big
				Kit.limb("Toe" .. s, ball, tip, r * 0.22, r * 0.18, b)
				if f.pads then
					Kit.ell("ToePad" .. s, tip, V(0.1, 0.06, 0.1) * big, f.pads)
				end
			end
			Kit.limb("Web" .. s, ball - fd * 0.02, ball + fd * 0.16 * big, 0.06 * big, 0.17 * big, f.web or b, 0.22, UP)
		else
			Kit.limb("Web" .. s, ball - fd * 0.02, ball + fd * 0.14 * big, 0.07 * big, 0.15 * big, b, 0.4, UP)
		end
	end
	return t
end

FORMS.hopsprout = { pads = "pink", sprout = "grass", stem = "leaf_dark", bud = "pink", bands = "leaf_dark", under = "cream" }
FORMS.murkle = { big = 1.06, wide = 1.0, tall = 0.66, sac = "sand", spots = "sand_dark", ridge = "sand_dark", ear = 1.4, earC = "sand", under = "sand", eyeD = 0.72 }
FORMS.cindertoad = { toad = true, wide = 0.96, tall = 0.76, slope = 0.62, warts = "orange", glands = true, dome = 0.42, eyeD = 0.95, blush = false, under = "rock" }
FORMS.icetoad = { toad = true, wide = 0.94, spots = "white", frost = "ice", icicles = "ice", brow = "white", under = "white", web = "ice" }

------------------------------------------------------------------ the crab (shore crab, box crab, spider crab, hermit)
-- A real crab: a wide flattened carapace, broadest toward the front where a row of teeth runs along its edge, a pale
-- underside; two eyes on short stalks from the front of the shell; two big claws held up in front (the arm out to the
-- side, the wrist turning in, a swollen palm, a fixed finger underneath and the hinged one over it); four pairs of
-- walking legs that arch up from the shell's sides to a knee above it and come down to pointed tips on the ground.

-- A claw on its joints ("arm" .. s and "pincer" .. s): from the shoulder at `sh`, held forward and turned in. k scales
-- it; c its colour, tip the fingers' tips' colour.
local function crabClaw(side: number, sh: Vector3, k: number, c: string, tip: string, lift: number?)
	local s = sideName(side)
	J("arm" .. s, "body", sh, "arm", side)
	local up = lift or 0
	local elbow = sh + V(side * 0.3, 0.04 + up * 0.5, 0.18) * k
	local wrist = elbow + V(-side * 0.02, 0.06 + up * 0.5, 0.2) * k
	if full() then
		Kit.limb("Arm" .. s, sh, elbow, 0.085 * k, 0.075 * k, c)
		Kit.limb("Arm" .. s, elbow, wrist, 0.075 * k, 0.085 * k, c)
	else
		Kit.limb("Arm" .. s, sh, wrist, 0.085 * k, 0.085 * k, c)
	end
	-- the palm: swollen, pointing forward and in
	local cd = V(-side * 0.4, 0.06, 1).Unit
	local pc = wrist + cd * 0.15 * k
	Kit.egg("Palm" .. s, pc, V(0.24, 0.36, 0.28) * k, 0.55, c, A.lie(cd, UP))
	if full() then
		-- knuckles along its top
		for i = 0, 1 do
			Kit.ell("Knuckle" .. s, pc + cd * (0.02 + i * 0.1) * k + UP * 0.12 * k, V(0.08, 0.06, 0.08) * k, c)
		end
	end
	-- the fixed finger underneath, curving in at the tip
	local in1 = V(-side * 0.04, 0, 0) * k
	local f0, f1 = pc + cd * 0.14 * k - UP * 0.06 * k, pc + cd * 0.36 * k - UP * 0.04 * k + in1
	Kit.limb("Finger" .. s, f0, f1, 0.07 * k, 0.045 * k, c)
	Kit.limb("FingerTip" .. s, f1, f1 + cd * 0.1 * k + UP * 0.02 * k + in1, 0.045 * k, 0.02 * k, tip, nil, nil, true)
	-- the hinged finger over it, on its own joint
	J("pincer" .. s, "arm" .. s, pc + cd * 0.12 * k + UP * 0.08 * k, "pincer", side)
	local d0, d1 = pc + cd * 0.12 * k + UP * 0.08 * k, pc + cd * 0.36 * k + UP * 0.07 * k + in1
	Kit.limb("Pincer" .. s, d0, d1, 0.065 * k, 0.045 * k, c)
	Kit.limb("PincerTip" .. s, d1, d1 + cd * 0.1 * k - UP * 0.04 * k + in1, 0.045 * k, 0.02 * k, tip, nil, nil, true)
	Kit.on("body")
end

-- A walking leg on its joint: from `base` (on the shell's side) up and out to the knee, down to the ankle, a pointed
-- tip on the ground; dz how far it leans forward (+) or back (-), reach how far out it goes.
local function crabLeg(name: string, side: number, ph: number, base: Vector3, dz: number, reach: number, r: number, c: string, tip: string, knee: number?)
	J(name, "body", base, "leg", side, ph)
	local kh = knee or 0.2
	local k0 = base + V(side * reach * 0.5, kh, dz * 0.45)
	local an = base + V(side * reach * 0.86, kh * 0.2 - base.Y * 0.45, dz * 0.82)
	local tp = V(base.X + side * reach, 0.02, base.Z + dz)
	Kit.limb("Leg" .. name, base, k0, r, r * 0.85, c)
	if full() then
		Kit.limb("Shin" .. name, k0, an, r * 0.85, r * 0.7, c)
		Kit.limb("LegTip" .. name, an, tp, r * 0.7, r * 0.3, tip)
	else
		Kit.limb("Shin" .. name, k0, tp, r * 0.85, r * 0.35, c)
	end
	Kit.on("body")
end

-- A coin: a flat disc of gold with a raised rim and a stamped middle.
local function coin(at: Vector3, n: Vector3, d: number, c: string)
	Kit.part("Coin", "Cylinder", V(0.06, d, d), Kit.along(at, n), c)
	if full() then
		Kit.part("CoinFace", "Cylinder", V(0.05, d * 0.6, d * 0.6), Kit.along(at + n * 0.03, n), A.shade(c))
	end
end

-- A four-point star: two thin crossed blades and a lit middle (a bit of fallen star).
local function star(at: Vector3, n: Vector3, d: number, c: string)
	local right = n:Cross(UP)
	right = if right.Magnitude > 1e-3 then right.Unit else V(1, 0, 0)
	local up = right:Cross(n).Unit
	Kit.limb("Star", at - right * d * 0.5, at + right * d * 0.5, 0.035, 0.035, c, nil, nil, nil, true)
	Kit.limb("Star", at - up * d * 0.5, at + up * d * 0.5, 0.035, 0.035, c, nil, nil, nil, true)
	Kit.ell("StarCore", at + n * 0.02, V(d * 0.4, d * 0.4, d * 0.4), "white", nil, nil, true)
end

PLANS.crab = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("crab", 1.5, 1.2, "scuttle")
	local ink = A.ink(b, a)
	local tip: string = f.tip or a
	local legC: string = f.legC or b
	J("body", nil, V(0, 0.6, 0), "body")
	if f.hermit then
		-- a hermit crab living in a broken brick: the brick on its back, the crab's front poking out of the open end
		local bc = V(0, 0.52, -0.22)
		local brot = CFrame.Angles(R(-8), R(6), R(3))
		Kit.part("Brick", "Block", V(0.92, 0.62, 1.02), CFrame.new(bc) * brot, b)
		-- the broken corner: a chipped step at its back top, a crack, a loose chip
		Kit.part("BrickChip", "Block", V(0.42, 0.2, 0.34), CFrame.new(bc) * brot * CFrame.new(-0.28, 0.33, -0.36) * CFrame.Angles(R(12), R(20), R(-8)), A.shade(b))
		-- old mortar along its top and down one side
		Kit.ell("Mortar", (CFrame.new(bc) * brot * CFrame.new(0.2, 0.31, 0.14)).Position, V(0.46, 0.06, 0.3), a, brot)
		if full() then
			Kit.ell("Mortar", (CFrame.new(bc) * brot * CFrame.new(-0.47, 0.06, 0.2)).Position, V(0.07, 0.36, 0.44), a, brot)
			Kit.ell("Mortar", (CFrame.new(bc) * brot * CFrame.new(0.36, 0.33, -0.3)).Position, V(0.18, 0.06, 0.16), a, brot)
			Kit.part("Crack", "Block", V(0.05, 0.36, 0.05), CFrame.new(bc) * brot * CFrame.new(-0.2, 0.04, 0.515) * CFrame.Angles(0, 0, R(18)), A.shade(b))
		end
		-- the dark hole in the front where it lives
		local hole = (CFrame.new(bc) * brot * CFrame.new(0, -0.02, 0.5)).Position
		Kit.ell("Hole", hole, V(0.62, 0.42, 0.12), "basalt", brot)
		-- the crab's head end, poking out of the hole
		local hc = hole + V(0, -0.04, 0.12)
		local _, head = A.blob("Head", hc, V(0.5, 0.34, 0.36), a)
		local mp, mn = surf(head, V(0, -0.3, 1))
		Kit.mouth(mp + mn * 0.01, mn, 0.16, ink)
		Kit.faceOn(hc, V(0.25, 0.17, 0.18))
		blush(hc, 0.2, FWD, R(36), R(8), 0.12)
		Kit.faceOff()
		for _, side in { -1, 1 } do
			local s = sideName(side)
			J("stalk" .. s, "body", hc + V(side * 0.1, 0.12, 0.06), "stalk", side)
			local s0, s1 = hc + V(side * 0.1, 0.1, 0.08), hc + V(side * 0.16, 0.4, 0.16)
			Kit.limb("Stalk" .. s, s0, s1, 0.055, 0.05, a)
			local ec = s1 + V(side * 0.01, 0.1, 0.02)
			Kit.ell("EyeBulb" .. s, ec, V(0.26, 0.28, 0.26), a)
			Kit.faceOn(ec, V(0.13, 0.14, 0.13))
			Kit.eye(s, ec, 0.13, V(side * 0.3, 0.2, 1).Unit, 0.22, A.iris(f.iris or "sand", "gold"))
			Kit.faceOff()
			Kit.on("body")
		end
		-- the claws: the right one much the bigger, as a hermit crab's is
		crabClaw(-1, hc + V(-0.18, -0.08, 0.04), 0.78, a, f.tip or "sand_dark", 0.05)
		crabClaw(1, hc + V(0.18, -0.08, 0.04), 1.12, a, f.tip or "sand_dark", 0.1)
		-- two pairs of walking legs out of the hole, the rest of it tucked in the brick
		for i = 1, 2 do
			for _, side in { -1, 1 } do
				local base = hc + V(side * 0.2, -0.1, -0.02 - (i - 1) * 0.12)
				local ph = ((i + (if side > 0 then 1 else 0)) % 2) * 0.5
				crabLeg("leg" .. sideName(side) .. i, side, ph, base, 0.16 - (i - 1) * 0.3, 0.5, 0.08, a, f.tip or "sand_dark", 0.14)
			end
		end
		return t
	end
	-- the carapace: wide, flattened, broadest toward the front
	local W: number = f.W or 1.42
	local L: number = f.L or 1.0
	local H: number = f.H or 0.46
	local sc = V(0, f.y or 0.62, -0.05)
	local srot = A.lie(-FWD, UP)
	Kit.egg("Shell", sc, V(W, L, H), f.split or 0.58, b, srot)
	local shell: A.Mass = { c = sc, size = V(W, L, H), rot = srot, split = f.split or 0.58 }
	Kit.ell("Under", sc + V(0, -H * 0.24, 0.02), V(W * 0.8, H * 0.5, L * 0.78), f.under or "cream")
	-- the teeth along the front edge
	if f.teeth ~= false and full() then
		for _, side in { -1, 1 } do
			local yaws: { number } = { 34, 50, 66 }
			for i, yaw in yaws do
				local p, n = surf(shell, A.dir(side * yaw, 4))
				local tl = (if f.teeth == "spiky" then 0.16 else 0.1) * (1 - (i - 1) * 0.15)
				cone("Tooth", p - n * 0.04, p + (n + FWD * 0.3).Unit * tl, 0.06, b)
			end
		end
	end
	-- spots
	if f.spots then
		for i, sp in { { -0.2, -40, 0.18 }, { 0.15, 36, 0.15 }, { -0.5, 20, 0.16 }, { 0.1, -10, 0.12 }, { -0.35, 60, 0.11 } } do
			spot("Spot", shell, onTop(sp[1], sp[2]), sp[3], f.spots, i > 3, nil, 0.025)
		end
	end
	-- the face on the front of the shell
	local mp, mn = surf(shell, V(0, -0.25, 1))
	Kit.mouth(mp + mn * 0.01, mn, 0.2, ink)
	Kit.faceOn(shell.c, V(W / 2, H / 2, L * (1 - shell.split)))
	blush(shell.c, (W + H + L) / 6, FWD, R(22), R(8), 0.15)
	Kit.faceOff()
	-- the eyes on their stalks
	local stalkH: number = f.stalk or 0.24
	for _, side in { -1, 1 } do
		local s = sideName(side)
		local p0 = surf(shell, V(side * 0.18, 0.55, 1))
		J("stalk" .. s, "body", p0, "stalk", side)
		local p1 = p0 + V(side * 0.05, stalkH, 0.04)
		Kit.limb("Stalk" .. s, p0 - V(0, 0.04, 0), p1, 0.065, 0.055, f.stalkC or b)
		local ec = p1 + V(side * 0.01, 0.11, 0.02)
		local er: number = f.eyeR or 0.15
		Kit.ell("EyeBulb" .. s, ec, V(er * 2, er * 2.1, er * 2), b)
		Kit.faceOn(ec, V(er, er * 1.05, er))
		Kit.eye(s, ec, er, V(side * 0.3, 0.25, 1).Unit, er * 1.7, A.iris(a, "gold"), if ink ~= "black" then ink else nil)
		Kit.faceOff()
		Kit.on("body")
	end
	-- the claws
	local ck: number = f.claw or 1
	for _, side in { -1, 1 } do
		local sh = surf(shell, V(side * 0.85, -0.3, 0.6)) - V(side * 0.06, 0, 0)
		crabClaw(side, sh, ck, b, tip, f.lift)
	end
	-- the walking legs
	local n = if full() then 4 else 3
	local reach: number = f.reach or 0.5
	local lr: number = f.legR or 0.075
	for i = 1, n do
		local u = (i - 1) / (n - 1)
		for _, side in { -1, 1 } do
			local z = 0.16 - u * 0.56
			local base = surf(shell, V(side, -0.25, z * 1.2)) - V(side * 0.08, 0, 0)
			local dz = 0.18 - u * 0.48
			local ph = ((i + (if side > 0 then 1 else 0)) % 2) * 0.5
			crabLeg("leg" .. sideName(side) .. i, side, ph, base, dz, reach * (1 - math.abs(u - 0.4) * 0.15), lr, legC, tip, f.knee)
		end
	end
	-- what it wears on its back
	if f.crown then
		-- a coral crown it grew: branching coral standing up from the top of its shell
		local top = surf(shell, V(0, 1, -0.15))
		local branches: { { number } } = if full() then { { 0, 0.48, 0 }, { -0.2, 0.38, -18 }, { 0.21, 0.4, 16 }, { -0.1, 0.3, 40 }, { 0.12, 0.28, -40 } } else { { 0, 0.48, 0 }, { -0.2, 0.38, -18 }, { 0.21, 0.4, 16 } }
		for i, br in branches do
			local b0 = top + V(br[1], -0.03, br[1] * 0.3 - 0.06)
			local d = (V(br[1] * 2.4, 1, math.sin(R(br[3])) * 0.4)).Unit
			local b1 = b0 + d * br[2]
			Kit.limb("Coral", b0, b1, 0.08, 0.06, f.crown)
			Kit.ell("CoralTip", b1, V(0.13, 0.13, 0.13), f.crown)
			if i <= 3 and full() then
				local side = if br[1] < 0 then -1 elseif br[1] > 0 then 1 else (if i % 2 == 0 then -1 else 1)
				local m = lerp(b0, b1, 0.5)
				local b2 = m + V(side * 0.16, 0.13, 0.02)
				Kit.limb("Coral", m, b2, 0.055, 0.045, f.crown)
				Kit.ell("CoralTip", b2, V(0.1, 0.1, 0.1), f.crown, nil, true)
			end
		end
	end
	if f.coins then
		-- old coins stuck all over its shell
		for i, cn in { { -0.1, -22, 0.3 }, { 0.22, 30, 0.28 }, { -0.45, 26, 0.26 }, { -0.4, -50, 0.24 }, { 0.05, 62, 0.22 } } do
			if full() or i <= 3 then
				local p, nn = surf(shell, onTop(cn[1], cn[2]))
				local tilt = (nn + V(math.sin(i * 2.1) * 0.2, 0, math.cos(i * 1.7) * 0.18)).Unit
				coin(p + nn * 0.035, tilt, cn[3], f.coins)
			end
		end
	end
	if f.stars then
		-- bits of fallen star it has picked out of the sand and stuck on its shell
		for i, st in { { -0.15, -24, 0.34 }, { 0.25, 30, 0.28 }, { -0.5, 22, 0.26 }, { 0.1, 70, 0.2 } } do
			if full() or i <= 2 then
				local p, nn = surf(shell, onTop(st[1], st[2]))
				star(p + nn * 0.04, nn, st[3], f.stars)
			end
		end
	end
	return t
end

FORMS.clawdle = { claw = 1.32, lift = 0.12, teeth = "spiky", spots = "cream" }
FORMS.coralcrab = { claw = 0.9, crown = "orange", spots = "cherry", W = 1.36 }
FORMS.relicrab = { W = 1.2, L = 1.0, H = 0.62, split = 0.52, y = 0.66, claw = 1.0, coins = "gold", teeth = false, tip = "wood_dark", legC = "sand_dark" }
FORMS.glimmite = { W = 1.04, L = 0.94, H = 0.52, split = 0.5, y = 0.66, claw = 0.9, reach = 0.68, legR = 0.06, knee = 0.32, stalk = 0.2, stars = "screen_on", teeth = false, tip = "night", spots = "steel" }
FORMS.rubblet = { hermit = true, iris = "sand" }

------------------------------------------------------------------ the beetle (ground beetle, geode beetle, scarab, rhino)
-- A real beetle in three parts: the head (eyes on its sides, mandibles or a horn at the front, two antennae), the
-- pronotum (the shield behind the head) and the domed back, which is the two hard wing cases meeting in a line down the
-- middle. Six jointed legs come from under the middle part: each thigh goes out and up to a knee, the shin comes down,
-- a little foot of a few segments ends in two hooks. The front legs reach forward, the middle ones out, the hind ones
-- back. Chibi: the head big, the shell a high round dome.
PLANS.beetle = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("beetle", 1.4, 1.1, "scuttle")
	local ink = A.ink(b, a)
	local legC: string = f.legC or b
	J("body", nil, V(0, 0.48, 0), "body")
	-- the wing cases: two domed halves meeting down the middle, rounded at the back
	local ey: number = f.ey or 0.5
	local el: number = f.el or 1.02
	local ew: number = f.ew or 0.5
	local eh: number = f.eh or 0.62
	local ec = V(0, ey, -0.22)
	local halves: { A.Mass } = {}
	for _, side in { -1, 1 } do
		local rot = CFrame.Angles(0, 0, R(-side * 8))
		if f.rim then
			-- (a rim of the accent showing round each case's edge)
			Kit.ell("Rim", ec + V(side * ew * 0.41, -0.035, -0.01), V(ew * 1.035, eh * 0.9, el * 1.03), f.rim, rot)
		end
		local _, m = A.blob("Case", ec + V(side * ew * 0.4, 0, 0), V(ew, eh, el), b, rot)
		table.insert(halves, m)
	end
	-- the line where they meet, and the belly under them
	if full() then
		local seam: { Vector3 } = {}
		for i = 0, 4 do
			local u = -0.85 + i * 0.4
			local p = surf(halves[1], V(0.45, 1, u))
			table.insert(seam, V(0, p.Y + 0.005, p.Z))
		end
		Kit.limbs("Seam", seam, { 0.03 }, f.seam or A.shade(b), 4)
	end
	Kit.ell("Belly", ec + V(0, -eh * 0.28, 0.05), V(ew * 1.5, eh * 0.4, el * 0.86), f.belly or A.shade(b))
	-- the pronotum: a wide shield in front of the wing cases
	local pc = V(0, ey + 0.04, 0.34)
	local ps: Vector3 = f.ps or V(0.82, 0.44, 0.44)
	if f.rim and full() then
		Kit.ell("PronotumRim", pc + V(0, -0.025, 0), ps * V(1.04, 0.88, 1.03), f.rim)
	end
	local _, pron = A.blob("Pronotum", pc, ps, b)
	-- the head on its joint
	local hc: Vector3 = f.hc or V(0, ey + 0.1, 0.72)
	local hs: Vector3 = f.hs or V(0.76, 0.62, 0.58)
	J("head", "body", pc + V(0, -0.06, 0.12), "head")
	local _, head = A.blob("Head", hc, hs, b)
	-- the jaw: a little chin under the face
	J("jaw", "head", hc + V(0, -hs.Y * 0.25, 0), "jaw")
	Kit.ell("Chin", hc + V(0, -hs.Y * 0.36, hs.Z * 0.2), V(hs.X * 0.5, hs.Y * 0.3, hs.Z * 0.5), b)
	Kit.on("head")
	-- the face
	Kit.faceOn(hc, hs / 2)
	local avg = (hs.X + hs.Y + hs.Z) / 6
	local e: { number } = f.eye or { R(42), R(14), 0.28 }
	Kit.eyes(hc, avg, FWD, e[1], e[2], e[3], A.iris(a, "gold"), if ink ~= "black" then ink else nil)
	if f.blush ~= false then
		blush(hc, avg, FWD, R(38), R(18), 0.14)
	end
	Kit.faceOff()
	local mp, mn = surf(head, V(0, -0.45, 1))
	Kit.mouth(mp + mn * 0.01, mn, 0.17, ink)
	-- what the head carries at the front
	local front = f.front or "mandibles"
	if front == "mandibles" then
		for _, side in { -1, 1 } do
			local m0 = hc + V(side * hs.X * 0.28, -hs.Y * 0.28, hs.Z * 0.36)
			local m1 = m0 + V(side * 0.12, -0.02, 0.16)
			local m2 = m1 + V(-side * 0.13, 0, 0.08)
			Kit.limb("Mandible", m0, m1, 0.065, 0.05, f.mandC or A.shade(b))
			Kit.limb("Mandible", m1, m2, 0.05, 0.025, f.mandC or A.shade(b))
		end
	elseif front == "horn" then
		-- a rhinoceros beetle's horn: up from the snout and curving back, a smaller one off the pronotum
		local h0 = hc + V(0, hs.Y * 0.36, hs.Z * 0.1)
		Kit.limbs("Horn", { h0, h0 + V(0, 0.16, 0.16), h0 + V(0, 0.34, 0.24), h0 + V(0, 0.46, 0.16) }, { 0.1, 0.075, 0.04 }, f.hornC or b, 3)
		Kit.ell("HornTip", h0 + V(0, 0.47, 0.15), V(0.09, 0.09, 0.09), f.hornTip or f.hornC or b, nil, nil, f.hornTip ~= nil)
		local p0 = surf(pron, V(0, 1, 0.6))
		Kit.on("body")
		Kit.limbs("Horn2", { p0 - V(0, 0.04, 0), p0 + V(0, 0.14, 0.1), p0 + V(0, 0.18, 0.24) }, { 0.08, 0.05, 0.025 }, f.hornC or b, 2)
		Kit.on("head")
	elseif front == "shovel" then
		-- a scarab's shovel: a flat toothed plate round the front of the head
		Kit.ell("Shovel", hc + V(0, hs.Y * 0.05, hs.Z * 0.32), V(hs.X * 0.92, 0.07, hs.Z * 0.5), f.rim or b)
		for i = -2, 2 do
			if full() or i % 2 == 0 then
				local d = A.dir(i * 22, 0)
				local p = hc + V(0, hs.Y * 0.05, 0) + d * hs.Z * 0.56 + V(d.X * hs.X * 0.18, 0, 0)
				cone("ShovelTooth", p - d * 0.03, p + d * 0.08, 0.04, f.rim or b)
			end
		end
	end
	-- the antennae
	for _, side in { -1, 1 } do
		local s = sideName(side)
		local a0 = hc + V(side * hs.X * 0.3, hs.Y * 0.2, hs.Z * 0.3)
		J("antenna" .. s, "head", a0, "antenna", side)
		local a1 = a0 + V(side * 0.12, 0.2, 0.1)
		local a2 = a1 + V(side * 0.14, 0.06, 0.16)
		if full() then
			Kit.limb("Antenna" .. s, a0, a1, 0.035, 0.03, f.antC or A.shade(b))
			Kit.limb("Antenna" .. s, a1, a2, 0.03, 0.03, f.antC or A.shade(b))
		else
			Kit.limb("Antenna" .. s, a0, a2, 0.04, 0.035, f.antC or A.shade(b))
		end
		if f.club == "fan" then
			-- a scarab's club: a little fan of leaves
			for i = -1, 1 do
				if full() or i == 0 then
					local d = (a2 - a1).Unit
					Kit.ell("AntennaClub" .. s, a2 + d * 0.04 + V(0, i * 0.05, 0), V(0.1, if full() then 0.05 else 0.1, 0.12), f.clubC or f.antC or A.shade(b), A.lie(d, UP))
				end
			end
		else
			Kit.ell("AntennaClub" .. s, a2 + (a2 - a1).Unit * 0.03, V(0.09, 0.09, 0.12), f.clubC or f.antC or A.shade(b), A.lie((a2 - a1).Unit), nil, f.clubGlow)
		end
		Kit.on("head")
	end
	-- the legs: three each side from under the pronotum and the front of the wing cases
	Kit.on("body")
	local lr: number = f.legR or 0.06
	for i = 1, 3 do
		for _, side in { -1, 1 } do
			local s = sideName(side)
			local z = 0.36 - (i - 1) * 0.26
			local base = V(side * 0.26, ey - eh * 0.22, z)
			local ph = ((i + (if side > 0 then 1 else 0)) % 2) * 0.5
			J("leg" .. s .. i, "body", base, "leg", side, ph)
			local dz = ({ 0.3, 0.02, -0.34 })[i]
			local knee = base + V(side * 0.22, 0.07, dz * 0.35)
			local ankle = V(base.X + side * 0.38, 0.08, base.Z + dz * 0.72)
			local footT = V(base.X + side * 0.46, 0.03, base.Z + dz * 1.0)
			Kit.limb("Leg" .. s .. i, base, knee, lr * 1.25, lr, legC)
			if full() then
				Kit.limb("Shin" .. s .. i, knee, ankle, lr, lr * 0.75, legC)
				Kit.limb("Foot" .. s .. i, ankle, footT, lr * 0.65, lr * 0.5, legC)
			else
				Kit.limb("Shin" .. s .. i, knee, footT, lr * 1.1, lr * 0.8, legC)
			end
			if full() then
				local d = (footT - ankle).Unit
				for _, h in { -1, 1 } do
					local across = UP:Cross(d).Unit * h
					Kit.limb("Hook" .. s .. i, footT, footT + d * 0.05 + across * 0.04, 0.025, 0.025, A.shade(legC))
				end
			end
			Kit.on("body")
		end
	end
	-- what it carries on its back
	local top = surf(halves[1], V(0.4, 1, -0.1))
	top = V(0, top.Y, top.Z)
	if f.coal then
		-- a hot coal: a lumpy black stone glowing orange in its cracks
		local cc = top + V(0, 0.14, -0.06)
		local _, coal = A.blob("Coal", cc, V(0.52, 0.34, 0.46), f.coal, CFrame.Angles(R(8), R(25), R(-6)))
		local _, lump = A.blob("Coal", cc + V(0.1, 0.12, -0.08), V(0.3, 0.24, 0.3), f.coal, CFrame.Angles(R(-20), R(40), R(10)))
		-- the glow: hot patches showing through it, brightest on top
		spot("Ember", coal, V(-0.4, 1, 0.5), 0.22, a, nil, true, 0.055)
		spot("Ember", lump, V(0.2, 1, 0.3), 0.16, a, nil, true, 0.055)
		if full() then
			spot("Ember", coal, V(-0.9, 0.3, 0.6), 0.13, a, nil, true, 0.05)
			spot("Ember", coal, V(0.7, 0.4, 0.9), 0.12, a, nil, true, 0.05)
			spot("Ember", coal, V(-0.3, 0.5, -1), 0.12, a, nil, true, 0.05)
		end
	end
	if f.geode then
		-- the wing cases split open down the middle like a geode, crystals growing out of the crack
		local shards: { { number } } = { { -0.45, 0.4, 10, 0.14 }, { -0.12, 0.46, -12, 0.15 }, { 0.2, 0.32, 16, 0.12 }, { -0.78, 0.3, -8, 0.12 }, { 0.02, 0.28, 34, 0.09 }, { -0.3, 0.26, -36, 0.1 }, { -0.6, 0.22, 30, 0.08 } }
		Kit.limbs("GeodeLining", { surf(halves[1], V(0.3, 1, 0.5)) * V(0, 1, 1) + V(0, -0.02, 0), surf(halves[1], V(0.3, 1, -0.3)) * V(0, 1, 1), surf(halves[1], V(0.3, 1, -0.9)) * V(0, 1, 1) + V(0, -0.04, 0) }, { 0.09, 0.11, 0.07 }, f.geode, 2)
		for i, sh in shards do
			if full() or i <= 3 then
				local p = surf(halves[1], V(0.25, 1, sh[1]))
				p = V(0, p.Y - 0.04, p.Z)
				local d = (V(math.sin(R(sh[3])), 1, sh[1] * 0.2)).Unit
				Kit.limb("Crystal", p, p + d * sh[2], sh[4], 0.025, f.geode)
			end
		end
	end
	if f.ball then
		-- the ball of dust it rolls about, held behind by its back legs
		local br: number = f.ballR or 0.36
		local bc = V(0.14, br, -1.2)
		Kit.ell("DustBall", bc, V(br * 2, br * 2, br * 2), f.ball)
		if full() then
			for i, d in { V(-0.6, 0.6, 0.3), V(0.5, 0.8, -0.2), V(0.1, 0.3, 0.9), V(-0.3, 0.9, -0.5) } do
				local p = bc + d.Unit * br
				Kit.ell("DustLump", p, V(0.12, 0.08, 0.12) * (1 + (i % 2) * 0.3), A.shade(f.ball), A.lie(d))
			end
		end
	end
	if f.glowSpots then
		-- glowing spots on the wing cases
		for i, sp in { { 0.15, 40, 0.16 }, { -0.25, 55, 0.18 }, { -0.6, 35, 0.14 }, { 0.3, 70, 0.11 }, { -0.4, 80, 0.12 } } do
			if full() or i <= 3 then
				for k, side in { -1, 1 } do
					local m = halves[k]
					spot("GlowSpot", m, onTop(sp[1], side * sp[2] * 0.6), sp[3], f.glowSpots, nil, true, 0.03)
				end
			end
		end
	end
	if f.spots then
		for i, sp in { { 0.1, 30, 0.16 }, { -0.4, 50, 0.15 }, { -0.75, 20, 0.12 } } do
			for k, side in { -1, 1 } do
				spot("Spot", halves[k], onTop(sp[1], side * sp[2] * 0.6), sp[3], f.spots, i == 3, nil, 0.03)
			end
		end
	end
	return t
end

FORMS.smoulderbug = { coal = "basalt", legC = "black", mandC = "orange", antC = "slate", clubC = "orange", clubGlow = true, seam = "slate", belly = "basalt" }
FORMS.shardbug = { geode = "crystal", front = "mandibles", mandC = "night", antC = "night", eh = 0.58, ew = 0.52, seam = "night" }
FORMS.scarabit = { rim = "gold", front = "shovel", ball = "rock", ballR = 0.32, club = "fan", clubC = "gold", antC = "jeans", legC = "jeans", seam = "gold", belly = "jeans", eh = 0.56 }
FORMS.craterbug = { front = "horn", glowSpots = "screen_on", legC = "black", antC = "slate", clubC = "screen_on", clubGlow = true, seam = "black", belly = "black", hornC = "screen_on", hornTip = "screen_on" }

------------------------------------------------------------------ the snail (garden snail, ramshorn, conch)
-- A real snail: one long soft foot, flat underneath with a paler skirt along its edge, tapering to a point behind;
-- at the front it rises into the head, which carries two long eye stalks and two short feelers under them; the shell
-- sits on its back over the middle, a tube that coils round on itself, each turn smaller than the last, winding in to
-- the tip (the spire). The opening is low at the front, where the body goes in.

-- A coiled shell: a logarithmic spiral of tapering limbs. C the coil's middle, ax the way the spire points, s0 where
-- the opening is (from C), rho0 / r0 the first turn's radius and the tube's, q how much each turn shrinks, turns,
-- hgt how far the spire rises along ax. Returns points along the outer turn for decoration (position, tube radius,
-- outward direction).
type ShellPt = { p: Vector3, r: number, out: Vector3, u: number }
local function coil(C: Vector3, ax: Vector3, s0: Vector3, rho0: number, r0: number, q: number, turns: number, hgt: number, color: string, flat: number, stripe: string?): { ShellPt }
	local axu = ax.Unit
	local e1 = (s0 - axu * s0:Dot(axu)).Unit
	local e2 = e1:Cross(axu)
	local k = -math.log(q) / (2 * math.pi)
	local per = if full() then 8 else 4
	local n = math.max(3, math.floor(turns * per + 0.5))
	local total = turns * 2 * math.pi
	local pts: { ShellPt } = {}
	for i = 0, n do
		local phi = total * i / n
		local g = math.exp(-k * phi)
		local d = e1 * math.cos(phi) + e2 * math.sin(phi)
		local p = C + d * rho0 * g + axu * hgt * (1 - g)
		table.insert(pts, { p = p, r = r0 * g, out = d, u = i / n })
	end
	for i = 1, n do
		local p0, p1 = pts[i], pts[i + 1]
		local mid = (p0.out + p1.out).Unit
		Kit.limb("Shell", p0.p, p1.p, p0.r, math.max(0.03, p1.r), color, flat, mid)
	end
	if stripe then
		-- a band painted along the middle of each turn's face, on the spire's side (and the other, up close), so the
		-- coil reads as a coil
		for _, sgn in (if full() then { 1, -1 } else { 1 }) :: { number } do
			local line: { Vector3 } = {}
			local m = math.floor(n * (if sgn > 0 then 0.92 else 0.5))
			for i = 1, m do
				local sp = pts[i]
				table.insert(line, sp.p + axu * sgn * sp.r * 0.9 + sp.out * sp.r * 0.15)
			end
			local step = if full() then 1 else 2
			for i = 1, #line - step, step do
				local w = math.max(0.03, pts[i].r * 0.22)
				Kit.limb("ShellStripe", line[i], line[i + step], w, math.max(0.03, pts[i + step].r * 0.22), stripe)
			end
		end
	end
	-- the tip of the spire
	local last = pts[n + 1]
	Kit.ell("ShellTip", last.p, V(1, 1, 1) * math.max(0.06, last.r * 2), color)
	return pts
end

PLANS.snail = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("snail", 1.8, 1.1, "slither")
	local ink = A.ink(b, a)
	local skirtC: string = f.skirt or A.under(b)
	J("body", nil, V(0, 0.3, 0), "body")
	-- the foot: a flattened tube from the pointed tail to the neck, its pale skirt along the ground
	local foot = { V(0, 0.07, -0.98), V(0, 0.14, -0.58), V(0, 0.18, -0.12), V(0, 0.21, 0.3) }
	Kit.limbs("Foot", foot, { 0.06, 0.22, 0.27, 0.26 }, b, 3, 0.66, UP)
	Kit.ell("Skirt", V(0, 0.06, -0.24), V(0.66, 0.1, 1.36), skirtC)
	if full() then
		-- a wet shine along the top of the tail
		Kit.ell("Wet", V(-0.06, 0.25, -0.56), V(0.08, 0.04, 0.22), "white", A.lie(V(0, 0.3, 1)))
	end
	-- the head, rising from the front of the foot
	local hc = V(0, 0.6, 0.62)
	local hs = V(0.54, 0.5, 0.5)
	Kit.limb("Neck", V(0, 0.2, 0.26), V(0, 0.48, 0.56), 0.26, 0.24, b)
	J("head", "body", V(0, 0.42, 0.48), "head")
	local _, head = A.blob("Head", hc, hs, b)
	local mp, mn = surf(head, V(0, -0.35, 1))
	Kit.mouth(mp + mn * 0.01, mn, 0.18, ink)
	Kit.faceOn(hc, hs / 2)
	blush(hc, (hs.X + hs.Y + hs.Z) / 6, FWD, R(38), R(10), 0.14)
	Kit.faceOff()
	-- the feelers: short, from the front of the face, angled down and out
	for _, side in { -1, 1 } do
		local f0 = surf(head, V(side * 0.4, -0.1, 1))
		local f1 = f0 + V(side * 0.1, -0.06, 0.16)
		Kit.limb("Feeler", f0, f1, 0.05, 0.04, b)
		Kit.ell("FeelerTip", f1, V(0.09, 0.09, 0.09), f.tip or b, nil, true)
	end
	-- the eye stalks
	for _, side in { -1, 1 } do
		local s = sideName(side)
		local s0 = surf(head, V(side * 0.35, 0.9, 0.3))
		J("stalk" .. s, "head", s0, "stalk", side)
		local s1 = s0 + V(side * 0.08, 0.24, 0.04)
		local s2 = s1 + V(side * 0.04, 0.22, 0.0)
		Kit.limbs("Stalk" .. s, { s0, s1, s2 }, { 0.065, 0.05 }, b, 2)
		local ec = s2 + V(side * 0.01, 0.1, 0.02)
		Kit.ell("EyeBulb" .. s, ec, V(0.27, 0.28, 0.27), b)
		Kit.faceOn(ec, V(0.135, 0.14, 0.135))
		Kit.eye(s, ec, 0.135, V(side * 0.3, 0.2, 1).Unit, 0.22, A.iris(a, "gold"), if ink ~= "black" then ink else nil)
		Kit.faceOff()
		Kit.on("head")
	end
	-- the shell on its own joint
	Kit.on("body")
	J("shell", "body", V(0, 0.42, -0.26), "shell")
	local kind: string = f.shell or "round"
	local sc: string = f.shellC or a
	local pts: { ShellPt }
	local stripe: string? = f.stripe or A.shade(sc)
	if kind == "conch" then
		-- a tall spire rising up and back, its turns stacked like a whelk's
		pts = coil(V(0, 0.6, -0.3), V(-0.3, 0.78, -0.55), V(0, -0.6, 0.8), 0.32, 0.27, 0.55, 2.4, 0.6, sc, 0.86, stripe)
	elseif kind == "flat" then
		-- a ramshorn's: flat and round, the turns side by side
		pts = coil(V(0, 0.72, -0.3), V(-0.85, 0.5, 0), V(0, -0.75, 0.66), 0.38, 0.21, 0.28, 2.2, 0.06, sc, 0.8, stripe)
	else
		pts = coil(V(0, 0.78, -0.3), V(-0.72, 0.6, 0), V(0, -0.75, 0.66), 0.39, 0.25, 0.27, 2.1, 0.16, sc, 0.82, stripe)
	end
	local function at(u: number): ShellPt
		local i = math.clamp(math.floor(u * (#pts - 1) + 0.5) + 1, 1, #pts)
		return pts[i]
	end
	-- the way the coil runs at u
	local function along(u: number): Vector3
		local i = math.clamp(math.floor(u * (#pts - 1) + 0.5) + 1, 1, #pts - 1)
		return (pts[i + 1].p - pts[i].p).Unit
	end
	if f.bands then
		-- coloured bands round the turns, like a candy snail's
		local us: { number } = if full() then { 0.06, 0.16, 0.26, 0.36, 0.46 } else { 0.12, 0.32 }
		for _, u in us do
			local sp = at(u)
			local tg = along(u)
			Kit.limb("ShellBand", sp.p - tg * 0.03, sp.p + tg * 0.03, sp.r * 1.06, sp.r * 1.06, f.bands, 0.86, sp.out)
		end
	end
	if f.moss then
		-- moss on top of the shell, and a fern growing out of it
		for i, u in { 0.38, 0.5, 0.62 } do
			local sp = at(u)
			Kit.ell("Moss", sp.p + sp.out * sp.r * 0.75, V(0.26, 0.14, 0.24) * (1 - (i - 1) * 0.15), f.moss, A.lie(sp.out))
		end
		if full() then
			local sp = at(0.5)
			local base = sp.p + sp.out * sp.r * 0.9
			for _, d in { V(-0.4, 1, 0.3), V(0.35, 1, -0.2), V(0, 1, 0.6) } do
				Kit.limb("Fern", base, base + d.Unit * 0.24, 0.045, 0.03, f.fern or "leaf")
			end
		end
	end
	if f.crystals then
		-- crystals growing out of the shell's turns, the biggest on top
		for i, c in { { 0.4, 0.34, 0.12 }, { 0.5, 0.42, 0.14 }, { 0.6, 0.32, 0.12 }, { 0.3, 0.24, 0.1 }, { 0.72, 0.22, 0.09 }, { 0.2, 0.2, 0.08 } } do
			if full() or i <= 3 then
				local sp = at(c[1])
				local d = (sp.out + V((i % 2) * 0.3 - 0.15, 0.2, 0)).Unit
				local base = sp.p + sp.out * sp.r * 0.6
				Kit.limb("Crystal", base, base + d * c[2], c[3], 0.025, f.crystals)
			end
		end
	end
	if f.shop then
		-- a tiny shop: a striped awning over a little door in the shell's side, a sign on a post on top
		local sp = at(0.1)
		local side = -1
		local wall = sp.p + V(side * sp.r * 0.7, 0.08, -0.02)
		Kit.ell("Door", wall + V(side * 0.03, -0.05, 0), V(0.06, 0.22, 0.18), f.door or "wood_dark")
		for i = -1, 1 do
			local c = wall + V(side * 0.03, 0.14, i * 0.075)
			local o = c + V(side * 0.16, -0.08, 0)
			Kit.limb("Awning", c, o, 0.045, 0.045, if i == 0 then "white" else f.shop, 0.5, V(-side * 0.5, 1, 0))
		end
		local top = at(0.32)
		local p0 = top.p + top.out * top.r * 0.8
		Kit.limb("SignPost", p0, p0 + V(0, 0.2, 0), 0.03, 0.03, "wood_dark")
		Kit.part("Sign", "Block", V(0.3, 0.18, 0.05), CFrame.new(p0 + V(0, 0.28, 0)) * CFrame.Angles(0, R(-30), 0), "wood")
		if full() then
			Kit.part("SignCoin", "Cylinder", V(0.05, 0.1, 0.1), Kit.along(p0 + V(0, 0.28, 0) + V(0.012, 0, 0.022), V(0.5, 0, 0.87)), "gold")
		end
	end
	if full() then
		-- a shine on the shell's top
		local sp = at(0.3)
		Kit.ell("Gloss", sp.p + sp.out * sp.r * 0.98 + V(-0.03, 0, 0), V(0.08, 0.05, 0.14), "white", A.lie(sp.out))
	end
	Kit.on("body")
	if f.trail then
		-- the trail it leaves: little sprouts coming up behind its tail
		for i, q in { V(-0.12, 0, -1.18), V(0.1, 0, -1.34) } do
			if full() or i == 1 then
				for _, d in { V(-0.4, 1, 0), V(0.4, 1, 0.1) } do
					Kit.egg("Sprout", q + d.Unit * 0.08 + UP * 0.02, V(0.07, 0.16, 0.05), 0.6, f.trail, A.lie(d))
				end
			end
		end
	end
	return t
end

FORMS.conchy = { shell = "round", shellC = "cream", stripe = "pink", bands = "pink", shop = "berry_red", skirt = "cherry", tip = "cherry" }
FORMS.bogsnail = { shell = "flat", shellC = "green", moss = "leaf_dark", fern = "leaf", trail = "grass", skirt = "slate" }
FORMS.gemsnail = { shell = "round", crystals = "crystal", skirt = "crystal", tip = "screen_on" }

------------------------------------------------------------------ the wyrm (an eastern serpent dragon)
-- A long sinuous body with no wings, lying in a loop on the ground with a hump where it lifts clear, the neck rising
-- out of the loop in an S to a big dragon's head: a blunt snout with a wide nose and nostrils on top, long whiskers
-- trailing from the upper lip, brows over the eyes, horns or fins on the head, a mane down the back of the neck, a
-- row of spines along the back, pale plates down the throat and the tail tapering to a tuft or a fin.

-- A tuft of hair: a few flattened tapering locks fanning from `at` toward `d` (a mane, a beard, a tail's end).
local function tuft(name: string, at: Vector3, d: Vector3, len: number, w: number, n: number, spread: number, c: string, flatN: Vector3?)
	local du = d.Unit
	local side = du:Cross(UP)
	side = if side.Magnitude > 1e-3 then side.Unit else V(1, 0, 0)
	if not full() then
		-- (one broad lock on the islands)
		n = 1
		w *= 1.3
	end
	for i = 1, n do
		local s = if n == 1 then 0 else -1 + 2 * (i - 1) / (n - 1)
		local dd = (du + side * s * spread).Unit
		local L = len * (1 - math.abs(s) * 0.25)
		Kit.limb(name, at, at + dd * L, w, w * 0.25, c, 0.55, flatN or UP)
	end
end

PLANS.wyrm = function(b, a, form)
	local f: Form = form or {}
	local big: number = f.big or 1
	local t = Kit.new("wyrm", 2.6 * big, 1.5 * big, "slither")
	local ink = A.ink(b, a)
	local under: string = f.under or a
	local spineC: string = f.spine or a
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * big
	end
	J("body", nil, P(0, 0.5, -0.6), "body")
	-- the loop on the ground: from under the neck round to the right, up over a hump at the back, down the left side
	local body = { P(0, 0.3, 0.32), P(0.5, 0.29, 0.12), P(0.74, 0.3, -0.38), P(0.5, 0.56, -0.86), P(-0.06, 0.7, -1.02), P(-0.58, 0.44, -0.78), P(-0.76, 0.29, -0.26) }
	local br = { 0.33, 0.32, 0.31, 0.3, 0.29, 0.28 }
	for i = 1, #br do
		br[i] *= big
	end
	-- (on the islands Kit.limbs halves the links: 12 there still puts a joint on every point of the loop)
	Kit.limbs("Body", body, br, b, if full() then 8 else 12)
	-- the spines along the top of the back
	local nsp = if full() then 7 else 2
	for i = 1, nsp do
		local u = 0.08 + (i - 1) / (nsp - 1) * 0.86
		local p, up = Kit.curveAt(body, u), upAt(body, u)
		local tg = tangent(body, u)
		local rad = lerpList(br, u)
		local hgt = (f.spineH or 0.16) * big * (if full() then 1 else 1.3)
		Kit.limb("Spine", p + up * rad * 0.8, p + up * (rad + hgt) - tg * hgt * 0.5, 0.075 * big, 0.025, spineC, 0.8, tg:Cross(up))
	end
	if f.moss then
		-- moss growing on its back, it lies so still
		for i, u in { 0.2, 0.52, 0.85 } do
			if full() or i == 2 then
				local p, up = Kit.curveAt(body, u), upAt(body, u)
				local tg = tangent(body, u)
				local side = tg:Cross(up).Unit * (if i % 2 == 0 then -1 else 1)
				local d = (up + side * 0.7).Unit
				Kit.ell("Moss", p + d * lerpList(br, u) * 0.9, V(0.26, 0.1, 0.3) * big, f.moss, A.lie(d, tg))
			end
		end
	end
	if f.lights then
		-- lights down each flank, the way deep fish glow
		for i = 1, (if full() then 6 else 3) do
			local u = 0.06 + (i - 1) * (if full() then 0.17 else 0.34)
			local p = Kit.curveAt(body, u)
			local tg = tangent(body, u)
			local out = tg:Cross(UP).Unit * -1
			local d = (out + UP * 0.35).Unit
			Kit.ell("Light", p + d * lerpList(br, u) * 0.96, V(0.13, 0.13, 0.13) * big * (if full() then 1 else 1.3), f.lights, nil, nil, true)
		end
	end
	if f.stars then
		-- gold star specks scattered over its back
		for i = 1, (if full() then 8 else 2) do
			local u = (i - 0.5) / (if full() then 8 else 2)
			local p, up = Kit.curveAt(body, u), upAt(body, u)
			local tg = tangent(body, u)
			local side = tg:Cross(up).Unit * (if i % 2 == 0 then -0.6 else 0.6)
			local d = (up + side).Unit
			Kit.ell("Speck", p + d * lerpList(br, u) * 0.97, V(0.08, 0.08, 0.08) * big * (if full() then 1 else 1.3), f.stars, nil, nil, i % 3 == 0)
		end
	end
	-- the fin on the hump (its own joint)
	local hump = Kit.curveAt(body, 0.62)
	J("fin", "body", hump, "fin", 0)
	local finK: string = f.fin or "spines"
	local hu, htg = upAt(body, 0.62), tangent(body, 0.62)
	local hr = lerpList(br, 0.62)
	if finK == "sail" then
		-- a tall sail of skin held up by rays
		local base0, base1 = Kit.curveAt(body, 0.5), Kit.curveAt(body, 0.74)
		local u0, u1 = upAt(body, 0.5), upAt(body, 0.74)
		local top = hump + hu * (hr + 0.5 * big) - htg * 0.1
		local fn = htg:Cross(hu).Unit
		Kit.limb("Sail", base0 + u0 * hr * 0.8, top, 0.08 * big, 0.06 * big, f.finC or a, 0.25, fn)
		Kit.limb("Sail", top, base1 + u1 * hr * 0.8, 0.06 * big, 0.08 * big, f.finC or a, 0.25, fn)
		Kit.limb("Sail", base0 + u0 * hr * 0.85, base1 + u1 * hr * 0.85, 0.2 * big, 0.2 * big, f.finC or a, 0.2, fn)
		Kit.limb("Sail", lerp(base0, base1, 0.5) + hu * hr, top - hu * 0.12 * big, 0.2 * big, 0.12 * big, f.finC or a, 0.2, fn)
		if full() then
			for _, u in { 0.3, 0.7 } do
				local bp = lerp(base0 + u0 * hr, base1 + u1 * hr, u)
				Kit.limb("SailRay", bp, lerp(bp, top, 0.85), 0.03, 0.025, b)
			end
		end
	else
		-- a tuft of the mane on the hump
		tuft("HumpMane", hump + hu * hr * 0.8, hu - htg * 0.8, 0.36 * big, 0.08 * big, if full() then 3 else 2, 0.5, f.mane or a, htg:Cross(hu))
	end
	-- the tail: on along the left side, tapering, curling up at the end
	Kit.on("body")
	local t0 = body[7]
	J("tail1", "body", t0, "tail", 0, 1)
	local tail1 = { t0, P(-0.86, 0.25, 0.2), P(-0.98, 0.23, 0.5) }
	Kit.limbs("Tail", tail1, { 0.28 * big, 0.2 * big }, b, 2)
	if full() then
		local p, up = Kit.curveAt(tail1, 0.5), upAt(tail1, 0.5)
		local tg = tangent(tail1, 0.5)
		Kit.limb("Spine", p + up * 0.2 * big, p + up * 0.32 * big - tg * 0.06, 0.06 * big, 0.025, spineC, 0.45, tg:Cross(up))
	end
	J("tail2", "tail1", tail1[3], "tail", 0, 2)
	local tail2 = { tail1[3], P(-0.98, 0.22, 0.78), P(-0.86, 0.3, 0.98), P(-0.72, 0.46, 1.0) }
	Kit.limbs("Tail", tail2, { 0.2 * big, 0.08 * big }, b, if full() then 3 else 2)
	local tip = tail2[4]
	local tipD = (tail2[4] - tail2[3]).Unit
	local tailK: string = f.tailEnd or "tuft"
	if tailK == "tuft" then
		tuft("TailTuft", tip - tipD * 0.06, tipD + UP * 0.4, 0.34 * big, 0.08 * big, if full() then 3 else 2, 0.55, f.mane or a)
	elseif tailK == "fluke" then
		local fn = tipD:Cross(UP).Unit
		for _, sgn in { -1, 1 } do
			Kit.limb("TailFin", tip - tipD * 0.05, tip + (tipD + UP * sgn * 0.9).Unit * 0.36 * big, 0.08 * big, 0.12 * big, f.finC or a, 0.25, fn)
		end
	elseif tailK == "glow" then
		Kit.egg("TailLure", tip + tipD * 0.08 * big, V(0.2, 0.28, 0.2) * big, 0.6, f.glow or a, A.lie(tipD), nil, true)
	elseif tailK == "flame" then
		for i, d in { V(0, 1, 0.1), V(-0.4, 0.8, 0.3), V(0.4, 0.8, -0.1) } do
			local L = (0.36 - (i - 1) * 0.08) * big
			Kit.egg("TailFlame", tip + d.Unit * L * 0.45, V(0.14, L, 0.14) * big, 0.66, if i == 1 then (f.flame or a) else (f.flame2 or f.flame or a), A.lie(d))
		end
	end
	-- the neck, rising out of the loop in an S, pale plates down its front
	Kit.on("body")
	J("neck", "body", P(0, 0.62, 0.42), "neck")
	local neck = { P(0, 0.3, 0.32), P(0, 0.86, 0.5), P(0, 1.34, 0.38), P(0, 1.72, 0.5), P(0, 1.92, 0.68) }
	local nr = { 0.33 * big, 0.28 * big, 0.25 * big, 0.24 * big }
	Kit.limbs("Neck", neck, nr, b, if full() then 4 else 8)
	for _, u in { 0.15, 0.35, 0.55, 0.75 } do
		if full() then
			local p, tg = Kit.curveAt(neck, u), tangent(neck, u)
			local fr = FWD - tg * FWD:Dot(tg)
			fr = fr.Unit
			local rad = lerpList(nr, u)
			Kit.ell("Throat", p + fr * rad * 0.62, V(rad * 1.5, rad * 0.62, rad * 0.9), under, A.lie(tg, fr))
		end
	end
	-- the mane down the back of the neck
	for _, u in { 0.3, 0.55, 0.8 } do
		if full() then
			local p, tg = Kit.curveAt(neck, u), tangent(neck, u)
			local bk = -(FWD - tg * FWD:Dot(tg)).Unit
			local rad = lerpList(nr, u)
			tuft("Mane", p + bk * rad * 0.7, bk - tg * 0.5, (0.3 + u * 0.1) * big, 0.075 * big, if full() then 2 else 1, 0.6, f.mane or a, V(1, 0, 0))
		end
	end
	-- small arms near the base of the neck, or fins
	local limbsK: string = f.arms or "arms"
	for _, side in { -1, 1 } do
		local s = sideName(side)
		local sh = P(side * 0.22, 0.76, 0.5)
		if limbsK == "arms" then
			local el = sh + P(side * 0.2, -0.1, 0.12)
			local wr = el + P(-side * 0.02, -0.12, 0.18)
			Kit.limb("Arm" .. s, sh, el, 0.085 * big, 0.07 * big, b)
			Kit.limb("Arm" .. s, el, wr, 0.07 * big, 0.065 * big, b, nil, nil, true)
			Kit.ell("Hand" .. s, wr + P(0, -0.02, 0.03), V(0.16, 0.12, 0.16) * big, b, nil, true)
			if full() then
				for k = -1, 1 do
					local d = A.dir(k * 30 - side * 10, -30)
					local c0 = wr + P(0, -0.03, 0.05) + d * 0.04
					Kit.limb("Claw" .. s, c0, c0 + d * 0.1 * big, 0.03, 0.025, f.claw or under)
				end
			end
		elseif limbsK == "fins" then
			local d = V(side * 0.9, -0.2, -0.45).Unit
			Kit.limb("PecFin" .. s, sh, sh + d * 0.38 * big, 0.07 * big, 0.12 * big, f.finC or a, 0.25, V(0, 1, 0.3))
		end
	end
	if f.pearl then
		-- a glowing pearl held in its right hand
		Kit.ell("Pearl", P(0.4, 0.5, 0.92), V(0.22, 0.22, 0.22) * big, f.pearl, nil, nil, true)
	end
	-- the head
	local hc = P(0, 2.16, 0.84)
	local hs = V(0.78, 0.66, 0.72) * big
	J("head", "neck", P(0, 1.92, 0.7), "head")
	local _, head = A.blob("Head", hc, hs, b)
	-- the snout: blunt and a little boxy, a wide nose pad on its end with the nostrils on top
	local s0 = hc + V(0, -hs.Y * 0.14, hs.Z * 0.3)
	local s1 = hc + V(0, -hs.Y * 0.18, hs.Z * 0.3 + (f.snout or 0.42) * big)
	Kit.limb("Snout", s0, s1, 0.24 * big, 0.21 * big, b, 0.82, UP)
	local nose = s1 + V(0, 0.07, 0.08) * big
	Kit.ell("NosePad", nose, V(0.42, 0.22, 0.26) * big, b, nil, true)
	if full() then
		for _, side in { -1, 1 } do
			Kit.ell("Nostril", nose + V(side * 0.1, 0.09, 0.05) * big, V(0.08, 0.05, 0.07) * big, A.shade(b), A.lie(V(side * 0.3, 1, 0.5)))
		end
	end
	-- brows over the eyes
	for _, side in (if full() then { -1, 1 } else {}) :: { number } do
		local d = A.dir(side * 30, 44)
		local p, n = surf(head, d)
		Kit.ell("Brow", p + n * 0.02 + V(0, 0.02, -0.02) * big, V(0.24, 0.1, 0.14) * big, f.brow or b, A.lie(n, V(-side, 0.4, 0)))
	end
	-- the jaw under the snout
	J("jaw", "head", hc + V(0, -hs.Y * 0.3, hs.Z * 0.1), "jaw")
	Kit.limb("Jaw", hc + V(0, -hs.Y * 0.34, hs.Z * 0.18), s1 + V(0, -0.15, -0.02) * big, 0.17 * big, 0.13 * big, under, 0.6, UP)
	if f.beard then
		tuft("Beard", hc + V(0, -hs.Y * 0.44, hs.Z * 0.32), V(0, -1, -0.15), 0.3 * big, 0.08 * big, if full() then 3 else 2, 0.35, f.beard, V(0, 0, 1))
	end
	Kit.on("head")
	if f.fangs then
		for _, side in { -1, 1 } do
			local p = s1 + V(side * 0.14, -0.12, 0.02) * big
			cone("Fang", p, p - UP * 0.12 * big, 0.04 * big, "white")
		end
	end
	-- the eyes and the mouth
	Kit.faceOn(hc, hs / 2)
	local avg = (hs.X + hs.Y + hs.Z) / 6
	local e: { number } = f.eye or { R(30), R(16), 0.26 * big }
	Kit.eyes(hc, avg, FWD, e[1], e[2], e[3], A.iris(a, "gold"), if ink ~= "black" then ink else nil)
	blush(hc, avg, FWD, R(50), R(14), 0.14 * big)
	Kit.faceOff()
	Kit.mouth(s1 + V(0, -0.12, 0.17) * big, V(0, -0.2, 1), 0.2 * big, ink)
	-- the whiskers, trailing from the upper lip
	local wl: number = (f.whisker or 1) * big
	for _, side in { -1, 1 } do
		local w0 = s1 + V(side * 0.2, -0.02, 0.06) * big
		local droop: number = f.droop or 0
		local pts = { w0, w0 + V(side * 0.22, 0.02 - droop * 0.1, -0.02) * wl, w0 + V(side * 0.44, -0.1 - droop * 0.2, -0.16) * wl, w0 + V(side * 0.56, -0.3 - droop * 0.35, -0.3) * wl }
		-- (a hair's breadth on the islands: up close only)
		Kit.limbs("Whisker", pts, { 0.04 * big, 0.025 }, f.whiskerC or a, 3, nil, nil, true)
	end
	-- what grows on its head
	local horns: string = f.horns or "drake"
	local hcol: string = f.hornC or a
	if horns == "antler" then
		-- antlers like a stag's, branching up and back
		local k: number = (f.antler or 1) * big
		for _, side in { -1, 1 } do
			local h0 = surf(head, V(side * 0.4, 1, -0.4))
			local main = { h0, h0 + V(side * 0.18, 0.22, -0.08) * k, h0 + V(side * 0.38, 0.4, -0.24) * k, h0 + V(side * 0.52, 0.5, -0.46) * k }
			Kit.limbs("Antler", main, { 0.07 * big, 0.04 * big }, hcol, if full() then 3 else 2)
			-- tines off the top of each beam, up and a little forward
			for i, u in { 0.38, 0.72 } do
				if full() or i == 1 then
					local p = Kit.curveAt(main, u)
					Kit.limb("Antler", p, p + V(side * 0.02, 0.26, 0.06) * k * (1 - i * 0.2), 0.045 * big, 0.025, hcol)
				end
			end
		end
	elseif horns == "gnarl" then
		-- short gnarled horns, knobbly like old roots
		for _, side in { -1, 1 } do
			local h0 = surf(head, V(side * 0.45, 1, -0.4))
			local pts = { h0, h0 + V(side * 0.12, 0.18, -0.08) * big, h0 + V(side * 0.08, 0.3, -0.22) * big, h0 + V(side * 0.18, 0.38, -0.32) * big }
			Kit.limbs("Horn", pts, { 0.08 * big, 0.04 * big }, hcol, if full() then 3 else 2)
			if full() then
				local p = Kit.curveAt(pts, 0.4)
				Kit.limb("Horn", p, p + V(side * 0.12, 0.08, 0.04) * big, 0.04 * big, 0.025, hcol)
			end
		end
	elseif horns == "drake" then
		for _, side in { -1, 1 } do
			local h0 = surf(head, V(side * 0.42, 1, -0.45))
			Kit.limbs("Horn", { h0, h0 + V(side * 0.1, 0.18, -0.2) * big, h0 + V(side * 0.14, 0.24, -0.5) * big }, { 0.08 * big, 0.025 }, hcol, 2)
		end
	elseif horns == "fins" then
		-- fins like a sea dragon's in place of ears, fanned and webbed
		for _, side in { -1, 1 } do
			local h0 = surf(head, V(side, 0.35, -0.35))
			for i, d in { V(side * 0.6, 0.8, -0.5), V(side * 0.9, 0.3, -0.6), V(side * 0.8, -0.2, -0.6) } do
				if not full() and i == 3 then
					break
				end
				local L = (0.36 - math.abs(i - 1.5) * 0.04) * big
				Kit.limb("EarFin", h0, h0 + d.Unit * L, 0.06 * big, 0.1 * big, f.finC or a, 0.22, V(0, 0, 1))
			end
		end
		Kit.limb("HeadFin", surf(head, V(0, 1, 0.3)), surf(head, V(0, 1, -0.6)) + V(0, 0.24, -0.1) * big, 0.05 * big, 0.12 * big, f.finC or a, 0.22, V(1, 0, 0))
	end
	-- the mane behind the head
	tuft("Mane", surf(head, V(0, 0.4, -1)), V(0, 0.1, -1), 0.38 * big, 0.09 * big, if full() then 3 else 2, 0.7, f.mane or a, V(0, 1, -0.2))
	if f.lure then
		-- a lure on a stalk from its brow, lit at the end like a deep fish's
		local l0 = surf(head, V(0, 1, 0.2))
		local pts = { l0, l0 + V(0, 0.34, 0.12) * big, l0 + V(0, 0.42, 0.52) * big, l0 + V(0, 0.2, 0.96) * big }
		Kit.limbs("LureStalk", pts, { 0.045 * big, 0.035 }, f.lureStalk or b, if full() then 3 else 2)
		Kit.ell("Lure", pts[4] + V(0, -0.08, 0.02) * big, V(0.2, 0.22, 0.2) * big, f.lure, nil, nil, true)
		if full() then
			Kit.ell("LureCore", pts[4] + V(-0.03, -0.06, 0.08) * big, V(0.08, 0.08, 0.08) * big, "white", nil, nil, true)
		end
	end
	if f.sun then
		-- a crest like the sun behind its head: a ring of rays round a disc
		local sc = hc + V(0, hs.Y * 0.2, -hs.Z * 0.5)
		local fn = V(0, 0.3, 1).Unit
		local right = V(1, 0, 0)
		local up = right:Cross(fn).Unit * -1
		if up.Y < 0 then
			up = -up
		end
		local dr = 0.42 * big
		Kit.ell("SunDisc", sc, V(dr * 2, 0.08, dr * 2), f.sunC or a, A.lie(fn, UP))
		local nr2 = if full() then 12 else 6
		for i = 1, nr2 do
			local ang = (i - 0.5) / nr2 * math.pi * 2
			local d = right * math.cos(ang) + up * math.sin(ang)
			if d.Y > -0.4 then
				local L = (if i % 2 == 1 then 0.34 else 0.24) * big
				Kit.limb("SunRay", sc + d * dr * 0.8 - fn * 0.03, sc + d * (dr + L) - fn * 0.03, 0.08 * big, 0.025, if i % 2 == 1 then (f.sun :: string) else (f.sun2 or f.sun), 0.4, fn)
			end
		end
	end
	if f.gem then
		local p, n = surf(head, V(0, 0.75, 0.75))
		Kit.ell("Gem", p + n * 0.02, V(0.13, 0.08, 0.13) * big, f.gem, A.lie(n))
	end
	return t
end

FORMS.mirewyrm = { horns = "gnarl", hornC = "wood", beard = "moss", mane = "moss", moss = "moss", brow = "yellow", droop = 1, whisker = 1.15, whiskerC = "yellow", eye = { R(30), R(14), 0.26 } }
FORMS.tidewyrm = { horns = "fins", fin = "sail", arms = "fins", tailEnd = "fluke", mane = "screen_on", whisker = 0.7, under = "white", finC = "screen_on" }
FORMS.abyssmaw = { horns = "drake", lure = "crystal", lureStalk = "purple", lights = "crystal", fangs = true, tailEnd = "glow", glow = "purple", arms = "none", spine = "purple", spineH = 0.24, mane = "purple", under = "slate" }
FORMS.solwyrm = { horns = "drake", hornC = "white", sun = "orange", sun2 = "yellow", sunC = "white", mane = "white", tailEnd = "flame", flame = "yellow", flame2 = "orange", gem = "berry_red", under = "white", claw = "white" }
FORMS.novawyrm = { big = 1.1, horns = "antler", antler = 1.2, hornC = "gold", stars = "gold", pearl = "white", mane = "gold", whisker = 1.3, whiskerC = "gold", under = "gold", claw = "gold" }

local _v, _r, _j, _f, _u, _w = V, R, J, full, UP, FWD
return { plans = PLANS, forms = FORMS }
