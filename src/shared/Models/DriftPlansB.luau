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
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

local lerp = A.lerp

------------------------------------------------------------------ helpers
local function sideName(s: number): string
	return if s < 0 then "L" else "R"
end

-- A frame whose local +Z is `n` (a flat ellipsoid lying on a surface there), its +Y as near `up` as it can.
local function faceTo(n: Vector3, up: Vector3?): CFrame
	local z = n.Unit
	local u = up or UP
	local y = u - z * u:Dot(z)
	y = if y.Magnitude > 1e-4 then y.Unit else (if math.abs(z.Y) < 0.9 then UP else FWD)
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- The point on a mass's surface in the direction `d` from its box's centre, and the normal there (exact for an egg:
-- its two half ellipsoids meet at an equator off the box's middle).
local function surf(m: A.Mass, d: Vector3): (Vector3, Vector3)
	local dl = m.rot:VectorToObjectSpace(d.Unit)
	local ax, az = m.size.X / 2, m.size.Z / 2
	local eq = m.size.Y * (0.5 - m.split)
	local function hit(by: number): number?
		-- |(t*dl - (0, eq, 0)) / (ax, by, az)| = 1, the far root
		local qa = (dl.X / ax) ^ 2 + (dl.Y / by) ^ 2 + (dl.Z / az) ^ 2
		local qb = -2 * dl.Y * eq / (by * by)
		local qc = (eq / by) ^ 2 - 1
		local disc = qb * qb - 4 * qa * qc
		if disc < 0 then
			return nil
		end
		return (-qb + math.sqrt(disc)) / (2 * qa)
	end
	local top, bot = m.size.Y * m.split, m.size.Y * (1 - m.split)
	local t = hit(top)
	local by = top
	if t == nil or t * dl.Y < eq then
		t = hit(bot)
		by = bot
	end
	local tt = t or 0
	local pl = dl * tt
	local nl = V(pl.X / (ax * ax), (pl.Y - eq) / (by * by), pl.Z / (az * az)).Unit
	return m.c + m.rot:VectorToWorldSpace(pl), m.rot:VectorToWorldSpace(nl)
end

-- A flat spot on a mass toward `d` (a fawn's dapple, a star in a fleece): a thin ellipsoid on the surface there.
local function spot(name: string, m: A.Mass, d: Vector3, w: number, color: string, detail: boolean?, neon: boolean?, long: number?)
	local p, n = surf(m, d)
	Kit.ell(name, p - n * 0.01, V(w * (long or 1), w * 0.8, 0.1), color, faceTo(n), detail, neon)
end

-- An ear on its own joint ("earL" / "earR", kind "ear") on the head `h`: its base on the cranium toward `at` (a
-- direction), pointing along `dir`, `len` long and `w` wide, its flat side facing `face`; `inner` a lining colour.
type EarO = { at: Vector3, dir: Vector3, len: number, w: number, c: string, inner: string?, tip: number?, flat: number?, face: Vector3?, tipC: string? }
local function ear(h: A.Head, s: number, o: EarO)
	local base = Kit.onEll(h.c, h.half, CFrame.identity, o.at) - o.at.Unit * o.w * 0.12
	J("ear" .. sideName(s), "head", base, "ear", s)
	local d = o.dir.Unit
	local tipP = base + d * o.len
	local face = o.face or (FWD + V(s * 0.3, 0.2, 0)).Unit
	local tr = o.w * (o.tip or 0.12)
	local flat = o.flat or 0.42
	-- leaf shaped: narrow where it joins the head, widest a third of the way up, then tapering to its tip
	local mid = lerp(base, tipP, 0.36)
	if full() then
		Kit.limb("Ear" .. sideName(s), base, mid, o.w * 0.3, o.w * 0.5, o.c, flat, face)
		Kit.limb("Ear" .. sideName(s), mid, tipP, o.w * 0.5, tr, o.c, flat, face)
	else
		Kit.limb("Ear" .. sideName(s), base, tipP, o.w * 0.44, tr, o.c, flat, face)
	end
	if o.inner then
		local inB = lerp(base, tipP, 0.2) + face * o.w * 0.13
		Kit.limb("EarIn" .. sideName(s), inB, lerp(base, tipP, 0.78) + face * o.w * 0.1, o.w * 0.3, tr * 0.8, o.inner, flat * 0.5, face, true)
	end
	if o.tipC then
		Kit.limb("EarTip" .. sideName(s), lerp(base, tipP, 0.62), tipP + d * 0.02, o.w * 0.28, tr * 1.1, o.tipC, flat * 1.1, face)
	end
end

-- A leg ending in a hoof, on its own joint: `hind` bends forward at the stifle and back at the hock with the cannon
-- bone near upright below it; a foreleg runs down past the elbow to the knee (the wrist) and on to the fetlock. opts:
-- r the leg's radius at the top, c its colour, sock a lower leg colour, hoof the hoof's colour, fw its width, mass the
-- shoulder or haunch's size (nil: made from r), shag a colour for a fur cuff at the knee or hock (a goat's), feather a
-- colour for long hair over the hoof (a horse's), out how far the foot stands out.
type HoofO = { hind: boolean, r: number, c: string, sock: string?, hoof: string, fw: number, mass: Vector3?, massC: string?, shag: string?, feather: string?, out: number?, slim: number?, lite: boolean? }
local function hoofLeg(n: string, s: number, ph: number, hip: Vector3, o: HoofO)
	J("leg" .. n, "body", hip, "leg", s, ph)
	local r = o.r
	local H = hip.Y
	local x = hip.X + s * (o.out or 0.02)
	local z = hip.Z
	local low = o.sock or o.c
	local hh = o.fw * 0.55
	local slim = o.slim or 1
	local fet: Vector3
	if not full() then
		-- (the islands' leg: two limbs and the hoof, a haunch on a hind leg)
		if o.hind then
			if not o.lite then
				Kit.ell(n .. "Haunch", hip + V(0, r * 0.4, -r * 0.3), o.mass or V(r * 2.6, r * 4.4, r * 4), o.massC or o.c, A.lie(V(0, 1, -0.35)))
			end
			local hock = V(x, H * 0.32, z - H * 0.1)
			fet = V(x, hh + r * 0.3, z - H * 0.05)
			Kit.limb("Leg" .. n, hip, hock, r * 1.0, r * 0.5 * slim, o.c)
			Kit.limb("Leg" .. n, hock, fet, r * 0.5 * slim, r * 0.44 * slim, low)
		else
			if o.massC and o.massC ~= o.c and not o.lite then
				Kit.ell(n .. "Shoulder", hip + V(0, r * 0.5, 0), o.mass or V(r * 2.4, r * 4, r * 3), o.massC)
			end
			local knee = V(x, H * 0.3, z - r * 0.1)
			fet = V(x, hh + r * 0.3, z + r * 0.15)
			Kit.limb("Leg" .. n, hip, knee, r * 0.9, r * 0.5 * slim, o.c)
			Kit.limb("Leg" .. n, knee, fet, r * 0.5 * slim, r * 0.44 * slim, low)
		end
	elseif o.hind then
		Kit.ell(n .. "Haunch", hip + V(0, r * 0.4, -r * 0.3), o.mass or V(r * 2.6, r * 4.4, r * 4), o.massC or o.c, A.lie(V(0, 1, -0.35)))
		local stifle = V(x, H * 0.62, z + H * 0.12)
		local hock = V(x, H * 0.32, z - H * 0.12)
		fet = V(x, hh + r * 0.3, z - H * 0.05)
		Kit.limb("Leg" .. n, hip, stifle, r * 1.1, r * 0.72 * slim, o.c)
		Kit.limb("Leg" .. n, stifle, hock, r * 0.72 * slim, r * 0.46 * slim, o.c)
		Kit.limb(if low ~= o.c then "Sock" .. n else "Leg" .. n, hock, fet, r * 0.46 * slim, r * 0.42 * slim, low)
		if o.shag then
			Kit.ell("Shag" .. n, lerp(stifle, hock, 0.55), V(r * 1.9, r * 2.6, r * 2), o.shag, A.lie(hock - stifle))
		end
	else
		Kit.ell(n .. "Shoulder", hip + V(0, r * 0.5, 0), o.mass or V(r * 2.4, r * 4, r * 3), o.massC or o.c)
		local elbow = V(x, H * 0.64, z - r * 0.5)
		local knee = V(x, H * 0.3, z - r * 0.1)
		fet = V(x, hh + r * 0.3, z + r * 0.15)
		Kit.limb("Leg" .. n, hip, elbow, r, r * 0.68 * slim, o.c)
		Kit.limb(if low ~= o.c then "Sock" .. n else "Leg" .. n, elbow, knee, r * 0.62 * slim, r * 0.48 * slim, low)
		Kit.limb(if low ~= o.c then "Sock" .. n else "Leg" .. n, knee, fet, r * 0.48 * slim, r * 0.42 * slim, low)
		if o.shag then
			Kit.ell("Shag" .. n, lerp(hip, elbow, 0.75), V(r * 2.2, r * 2.6, r * 2.2), o.shag)
		end
	end
	local g = V(fet.X, 0, fet.Z + r * 0.12)
	if o.feather and full() then
		-- long hair falling over the hoof (a horse's feathering)
		Kit.limb("Feather" .. n, fet + V(0, r * 0.5, -r * 0.2), g + V(0, hh * 0.7, -o.fw * 0.2), r * 0.5, o.fw * 0.5, o.feather)
	end
	A.hoof("Hoof" .. n, g, o.fw, o.hoof, FWD)
end

-- Antlers (on the head's joint): a main beam each side curving up, out and forward, tines off its front; returns the
-- tips (for leaves, stars, a nest). opts: len, r, c, tines (how many up the beam, 2 or 3), spread, back (how far
-- the beam leans back), fork (true: the beam's end splits in two).
type AntlerO = { len: number, r: number, c: string, tines: number?, spread: number?, back: number?, fork: boolean?, at: number? }
local function antlers(h: A.Head, o: AntlerO): { Vector3 }
	Kit.on("head")
	local tips: { Vector3 } = {}
	local L = o.len
	local sp = o.spread or 1
	local bk = o.back or 1
	for _, s in { -1, 1 } do
		local bd = V(s * (o.at or 0.42), 1, -0.12).Unit
		local base = Kit.onEll(h.c, h.half, CFrame.identity, bd) - bd * o.r * 0.5
		-- the burr: a ring where the antler meets the head
		Kit.ell("Burr", base + bd * o.r * 0.4, V(o.r * 2.6, o.r * 1.4, o.r * 2.6), o.c, A.lie(bd), true)
		-- the beam: up and out in a wide curve, back a little, its end turning up and in
		local beam = {
			base,
			base + V(s * 0.24 * sp, 0.32, -0.12 * bk) * L,
			base + V(s * 0.44 * sp, 0.64, -0.14 * bk) * L,
			base + V(s * 0.46 * sp, 0.96, 0.0) * L,
		}
		Kit.limbs("Antler", beam, { o.r, o.r * 0.75, o.r * 0.42 }, o.c, if full() then 3 else 2)
		-- the brow tine forward over the face, then tines standing up off the beam
		local brow = Kit.curveAt(beam, 0.12)
		local bt = brow + V(s * 0.08, 0.42, 0.9).Unit * L * 0.3
		Kit.limb("Antler", brow, bt, o.r * 0.8, o.r * 0.28, o.c)
		table.insert(tips, bt)
		local n = if full() then (o.tines or 2) else math.min(2, o.tines or 2)
		for i = 1, n - 1 do
			local u = 0.38 + (i - 1) / math.max(1, n - 1) * 0.36
			local p = Kit.curveAt(beam, u)
			local tip = p + V(s * 0.12, 1, 0.3).Unit * L * (0.4 - u * 0.12)
			Kit.limb("Antler", p, tip, o.r * (0.78 - u * 0.3), o.r * 0.26, o.c)
			table.insert(tips, tip)
		end
		local top = beam[4]
		if o.fork and full() then
			local t2 = top + V(s * 0.16, 0.2, -0.14) * L
			Kit.limb("Antler", Kit.curveAt(beam, 0.88), t2, o.r * 0.45, o.r * 0.24, o.c)
			table.insert(tips, t2)
		end
		table.insert(tips, top)
	end
	return tips
end

-- A little four-point star (a starhart's antler tip, a star in a fleece): two crossed thin blades facing `n`.
local function star(name: string, at: Vector3, size: number, color: string, n: Vector3?, detail: boolean?)
	if detail and not full() then
		return
	end
	local nn = (n or (FWD + V(0.6, 0.3, 0))).Unit
	local fr = faceTo(nn)
	local x, y = fr.XVector, fr.YVector
	Kit.limb(name, at - y * size, at + y * size, size * 0.3, size * 0.3, color, 0.45, nn, nil, true)
	Kit.limb(name, at - x * size * 0.8, at + x * size * 0.8, size * 0.28, size * 0.28, color, 0.45, nn, nil, true)
	Kit.ell(name, at, V(size, size, size * 0.6) * 0.7, color, faceTo(nn), nil, true)
end

------------------------------------------------------------------ the deer (fawns, stags, goats, unicorns)
-- A deer: a slim body, chest a little deeper than the hips, high on slender legs that end in neat hooves (the hind leg
-- forward to the stifle, back to the hock, the cannon near upright); a neck rising to a head with a long tapering
-- muzzle and a soft black nose; leaf ears out to the sides with pale insides; a short tail with a white underside. The
-- form adds horns or antlers, a mane, spots, a beard, shaggy fur and the rest.
PLANS.deer = function(b, a, form)
	local f: Form = form or {}
	local hipY = f.leg or 0.92
	local bl, bw, bt = f.len or 1.12, f.wide or 0.58, f.tall or 0.6
	local hs = f.head or 1
	local under = f.under or A.under(b)
	local ink = A.ink(b, a)
	local hoofC = f.hoof or (if A.isDark(b) then "black" else "wood_dark")
	local t = Kit.new("deer", f.h or 2.4, f.r or 1.0, "quad")
	J("body", nil, V(0, hipY, 0), "body")
	local bc = V(0, hipY + bt * 0.22, -0.04)
	local _, body = A.body("Body", bc, V(0, 0.07, 1).Unit, bl, bw, bt, 0.56, b)
	A.patch("Belly", body, V(0, -1, 0.08), V(0.68, 0.84, 0.62), 0.02, under, true)
	if f.rump ~= false then
		A.patch("Rump", body, V(0, 0.15, -1), 0.62, 0.02, under, true)
	end
	if f.hump then
		-- the shoulder hump of a mountain goat
		Kit.ell("Hump", bc + V(0, bt * 0.28, bl * 0.2), V(bw * 0.86, bt * 0.6, bl * 0.5), f.hump)
	end
	-- spots: dapples down the back and flanks (fewer on the islands)
	if f.spots then
		-- (each: how far back along the flank from its middle, how high up it, its size)
		local list = { { 0, 70, 0.12 }, { 20, 52, 0.1 }, { -20, 52, 0.1 }, { 38, 38, 0.09 }, { -38, 38, 0.09 }, { 60, 48, 0.08 }, { -60, 48, 0.08 }, { 0, 60, 0.11 } }
		for i, sp in list do
			for _, s in { -1, 1 } do
				if (i <= 2 or full()) and not (sp[1] == 0 and s < 0) then
					local d = A.dir(s * (90 + (sp[1] - 10) * 1.1), sp[2])
					spot("Spot", body, d, sp[3] * 1.5, f.spots, i > 3, f.glow)
				end
			end
		end
	end
	-- the neck on its own joint, rising from the top of the chest
	local nl = f.neck or 0.55
	local nb = V(0, bc.Y + bt * 0.12, bc.Z + bl * 0.38)
	local nt = nb + V(0, nl * 0.84, nl * 0.46)
	J("neck", "body", nb, "neck")
	local nr = f.neckR or 0.15
	Kit.limb("Neck", nb, nt, nr * 1.25, nr * 0.9, b)
	if f.ruff then
		-- a shaggy ruff down the front of the neck (a stag's, a goat's)
		Kit.limb("Ruff", nb + V(0, -0.02, 0.1), lerp(nb, nt, 0.7) + V(0, 0, 0.1), nr * 1.2, nr * 0.75, f.ruff, 0.8, V(1, 0, 0))
	else
		Kit.limb("Throat", nb + V(0, 0.02, nr * 0.45), lerp(nb, nt, 0.72) + V(0, 0, nr * 0.4), nr * 0.8, nr * 0.55, under, 0.8, V(1, 0, 0), true)
	end
	if f.mane then
		-- the mane: a crest along the top of the neck from the poll to the withers, its locks streaming back off it
		-- and falling over its left side (the side the camera sees), so they show past the head
		local top0, top1 = nt + V(0, 0.22, -0.1), nb + V(0, nr * 1.3, -0.16)
		Kit.limb("Mane", top0, top1, 0.12, 0.13, f.mane, 0.65, V(1, 0, 0))
		local n = if full() then 5 else 2
		for i = 1, n do
			local u = (i - 1) / (n - 1)
			local root = lerp(top0, top1, u) + V(-0.03, 0, 0)
			local tip = root + V(-0.15 - 0.04 * u, -0.12 - 0.12 * u, -0.22 - 0.04 * u)
			Kit.limb("Mane", root, tip, 0.13 - u * 0.01, 0.04, f.mane, 0.55, V(1, 0.3, 0))
		end
		-- and on over the withers
		Kit.limb("Mane", top1, top1 + V(-0.08, -0.08, -0.26), 0.12, 0.04, f.mane, 0.55, V(1, 0.3, 0))
	end
	-- the head
	local hc = nt + V(0, 0.22, 0.16) * hs
	local h = A.head({
		c = hc,
		size = V(0.86, 0.8, 0.82) * hs * (f.headS or V(1, 1, 1)),
		color = b,
		parent = "neck",
		pivot = nt,
		muzzle = "deer",
		mlen = (f.mlen or 0.36) * hs,
		mw = (f.mw or 0.3) * hs,
		mdrop = 0.13 * hs,
		mc = f.muzzleC,
		nose = f.nose or ink,
		eye = { R(f.eyeSpread or 36), R(8), 0.3 * hs },
		iris = A.iris(a, "wood_dark"),
		blush = f.blush ~= false,
		face = A.more(nil, f.faceDetail),
	})
	if f.beard then
		-- a goat's beard hanging from the chin
		Kit.limb("Beard", h.c + V(0, -0.34, 0.36) * hs, h.c + V(0, -0.66, 0.3) * hs, 0.09 * hs, 0.03, f.beard, 0.7, V(1, 0, 0))
	end
	-- ears
	local ek = f.ears or "leaf"
	for _, s in { -1, 1 } do
		if ek == "leaf" then
			ear(h, s, { at = V(s * 0.75, 0.8, -0.25), dir = V(s * 0.85, 0.78, -0.42), len = (f.earLen or 0.46) * hs, w = (f.earW or 0.3) * hs, c = b, inner = f.earIn or "pink", tip = 0.18, face = V(s * 0.25, 0.45, 1) })
		elseif ek == "goat" then
			-- out to the side and a little down
			ear(h, s, { at = V(s * 0.9, 0.5, -0.2), dir = V(s, -0.5, -0.05), len = (f.earLen or 0.3) * hs, w = (f.earW or 0.2) * hs, c = b, inner = f.earIn or "pink", tip = 0.3, face = V(s * 0.1, 0.6, 1) })
		elseif ek == "horse" then
			-- small, upright and pointed
			ear(h, s, { at = V(s * 0.45, 1, -0.2), dir = V(s * 0.25, 1, -0.12), len = (f.earLen or 0.32) * hs, w = (f.earW or 0.18) * hs, c = b, inner = f.earIn or "pink", tip = 0.15, flat = 0.55 })
		end
	end
	Kit.on("head")
	-- horns, antlers and the rest on the head
	local hk = f.horns
	if hk == "spike" then
		-- one horn rising from the brow, nearly upright, ringed with its spiral's ridges up close
		local L, hr = (f.hornLen or 0.6) * hs, (f.hornR or 0.07) * hs
		local base = Kit.onEll(h.c, h.half, CFrame.identity, V(0, 1, 0.5)) - V(0, hr * 0.5, 0)
		local tip = base + V(0, 0.93, 0.36).Unit * L
		Kit.limb("Horn", base, tip, hr, hr * 0.12, f.hornC or a)
		if full() then
			for i = 1, 3 do
				local u = i / 4.4
				local q = lerp(base, tip, u)
				Kit.ell("HornRing", q, V(hr * 2.1, hr * 0.55, hr * 2.1) * (1 - u * 0.85), A.shade(f.hornC or a), A.lie(tip - base))
			end
		end
	elseif hk == "nubs" then
		A.horns(h, { kind = "nubs", len = f.hornLen or 0.18, r = f.hornR or 0.06, at = 0.3, c = f.hornC or a, fwd = 0 })
	elseif hk == "goat" then
		-- curving back over the neck
		for _, s in { -1, 1 } do
			local bd = V(s * 0.28, 1, 0.1).Unit
			local base = Kit.onEll(h.c, h.half, CFrame.identity, bd) - bd * 0.04
			local L = f.hornLen or 0.6
			local hr = f.hornR or 0.085
			local pts = { base, base + V(s * 0.1, 0.36, -0.16) * L, base + V(s * 0.2, 0.56, -0.6) * L, base + V(s * 0.24, 0.36, -1.0) * L }
			Kit.limbs("Horn", pts, { hr, hr * 0.7, hr * 0.15 }, f.hornC or a, 3)
			if full() then
				-- the ridges round the horn's front
				for i = 1, 3 do
					local u = i * 0.16
					local p = Kit.curveAt(pts, u)
					local tg = Kit.curveAt(pts, u + 0.03) - Kit.curveAt(pts, u - 0.03)
					Kit.ell("HornRing", p, V(hr * 2.15, hr * 0.6, hr * 2.15) * (1 - u * 0.6), A.shade(f.hornC or a), A.lie(tg))
				end
			end
		end
	elseif hk == "antler" then
		local tips = antlers(h, { len = f.hornLen or 0.8, r = f.hornR or 0.08, c = f.hornC or a, tines = f.tines, spread = f.spread, fork = f.fork })
		if f.moss then
			-- moss on the antlers, little leaves on the tines, and a nest with an egg in it
			for i, p in tips do
				if full() or i % 2 == 0 then
					Kit.ell("Moss", p - V(0, 0.06, 0), V(0.14, 0.11, 0.14), f.moss)
					local sx = if p.X < 0 then -1 else 1
					Kit.limb("Leaf", p, p + V(sx * 0.13, 0.06, 0.08), 0.05, 0.02, f.leafC or "leaf", 0.4, V(0, 1, 0.3), true)
				end
			end
			if full() then
				for _, s in { -1, 1 } do
					local p = h.top + V(s * 0.28, 0.24, -0.08) * hs
					Kit.ell("Moss", p, V(0.2, 0.12, 0.18), f.moss)
				end
				local nest = h.top + V(-0.42, 0.62, -0.1) * hs
				Kit.ell("Nest", nest, V(0.26, 0.11, 0.24), "straw")
				Kit.egg("NestEgg", nest + V(0, 0.07, 0), V(0.09, 0.12, 0.09), 0.58, "window")
			end
		end
		if f.starTips then
			-- a star on the end of each beam and each top tine
			local half = #tips // 2
			for i, p in tips do
				local last = (i == half or i == #tips)
				if full() and (last or i == half - 1 or i == #tips - 1) then
					star("Star", p + V(0, 0.07, 0), if last then 0.17 else 0.12, f.starTips, nil, false)
				elseif last then
					Kit.ell("Star", p + V(0, 0.05, 0), V(0.16, 0.16, 0.16), f.starTips, nil, nil, true)
				end
			end
		end
	end
	if f.crescent then
		-- a crescent moon standing on the brow
		local c0 = h.c + V(0, h.half.Y * 0.86, h.half.Z * 0.3)
		Kit.limbs("Moon", { c0 + V(0.14, 0.0, 0), c0 + V(0.16, 0.18, 0.01), c0 + V(0.04, 0.32, 0.02), c0 + V(-0.12, 0.3, 0.02) }, { 0.03, 0.075, 0.03 }, f.crescent, 3, 0.55, FWD, nil, true)
	end
	if f.forelock then
		-- a forelock from between the ears, falling forward and to the left over the brow
		Kit.limb("Forelock", h.top + V(0.02, 0.02, -0.12) * hs, h.top + V(-0.14, -0.1, 0.24) * hs, 0.12 * hs, 0.04, f.forelock, 0.5, V(0, 1, 0.4))
		Kit.limb("Forelock", h.top + V(0.04, 0.0, -0.08) * hs, h.top + V(0.06, -0.12, 0.22) * hs, 0.09 * hs, 0.03, f.forelock, 0.5, V(0, 1, 0.4), true)
	end
	-- legs
	local lr = f.legR or 0.095
	local fz, hz = bc.Z + bl * 0.3, bc.Z - bl * 0.32
	local lx = bw * 0.27
	for _, l in { { n = "FL", s = -1, z = fz, ph = 0 }, { n = "FR", s = 1, z = fz, ph = 0.5 }, { n = "BL", s = -1, z = hz, ph = 0.5 }, { n = "BR", s = 1, z = hz, ph = 0 } } do
		local hind = l.z < 0
		hoofLeg(l.n, l.s, l.ph, V(l.s * lx, hipY + 0.05, l.z), {
			hind = hind,
			r = if hind then lr * 1.25 else lr * 1.1,
			c = b,
			sock = f.sock,
			hoof = hoofC,
			fw = f.fw or 0.17,
			shag = f.shag,
			feather = f.feather,
			slim = f.slim,
		})
	end
	-- the tail
	local tb = V(0, bc.Y + bt * 0.22, bc.Z - bl * 0.5)
	local tk = f.tail or "stub"
	J("tail1", "body", tb, "tail", 0, 1)
	if tk == "stub" or tk == "flick" then
		local up = if tk == "flick" then V(0, 0.75, -0.6) else V(0, -0.3, -1)
		local tl = f.tailLen or 0.26
		Kit.limb("Tail", tb, tb + up.Unit * tl, 0.1, 0.07, b, 0.7, V(0, 0.4, 1))
		Kit.limb("TailUnder", tb + V(0, -0.03, -0.02), tb + up.Unit * tl * 0.95 + V(0, -0.03, 0), 0.08, 0.06, under, 0.6, V(0, 0.4, 1), true)
	elseif tk == "horse" or tk == "tuft" then
		-- a dock arching back, then long hair falling in a curve
		local tc = f.tailC or a
		local d1 = tb + V(0, 0.08, -0.22)
		Kit.limb("Tail", tb, d1, 0.09, 0.07, b)
		J("tail2", "tail1", d1, "tail", 0, 2)
		if tk == "horse" then
			Kit.limbs("TailHair", { d1, d1 + V(0, -0.06, -0.22), d1 + V(0, -0.4, -0.32), d1 + V(0.02, -0.72, -0.24) }, { 0.12, 0.13, 0.05 }, tc, 3, 0.6, V(1, 0, 0))
		else
			Kit.limbs("TailHair", { d1, d1 + V(0, 0.02, -0.18), d1 + V(0, -0.14, -0.3) }, { 0.1, 0.12, 0.04 }, tc, 2, 0.7, V(1, 0, 0))
		end
	end
	Kit.on("body")
	if f.cloud then
		-- a little rain cloud over its back, a few drops falling from it
		local c0 = bc + V(0, bt * 0.5 + 0.66, -0.42)
		Kit.ell("Cloud", c0, V(0.62, 0.3, 0.46), f.cloud)
		Kit.ell("Cloud", c0 + V(-0.08, 0.14, 0.04), V(0.36, 0.3, 0.32), f.cloud)
		Kit.ell("Cloud", c0 + V(0.2, 0.08, -0.06), V(0.3, 0.26, 0.28), f.cloud, nil, true)
		Kit.ell("Cloud", c0 + V(-0.26, 0.0, 0.0), V(0.28, 0.22, 0.26), f.cloud, nil, true)
		Kit.egg("Drop", c0 + V(-0.1, -0.3, 0.04), V(0.07, 0.12, 0.07), 0.66, "blue")
		if full() then
			Kit.ell("Cloud", c0 + V(0.06, -0.06, 0.18), V(0.3, 0.18, 0.22), f.cloud)
			for _, p in { V(0.12, -0.38, -0.02), V(-0.24, -0.42, -0.06), V(0.02, -0.52, 0.08) } do
				Kit.egg("Drop", c0 + p, V(0.06, 0.1, 0.06), 0.66, "blue")
			end
		end
	end
	if f.dots and full() then
		-- a few lit dots on the flanks, like a constellation
		for _, s in { -1, 1 } do
			for _, d in { { 100, 30 }, { 130, 12 }, { 80, 8 }, { 115, -5 } } do
				spot("Dot", body, A.dir(s * d[1], d[2]), 0.07, f.dots, true, true)
			end
		end
	end
	return t
end

FORMS.fawnlet = { spots = "cream", earLen = 0.56, earW = 0.34, tail = "stub", neck = 0.5 }
FORMS.mossbuck = { horns = "antler", hornC = "wood", hornLen = 0.68, hornR = 0.1, tines = 2, fork = true, moss = "moss", leafC = "leaf", ruff = "hair_brown", neckR = 0.22, len = 1.24, wide = 0.66, tall = 0.66, h = 2.8, earLen = 0.44 }
FORMS.peakhorn = { style = "goat", horns = "goat", hornC = "steel", hornLen = 0.6, hornR = 0.1, beard = "white", ears = "goat", hump = "white", shag = "white", leg = 0.78, wide = 0.68, tall = 0.66, hoof = "black", ruff = "white", mlen = 0.3, rump = false }
FORMS.prismhorn = { style = "horse", horns = "spike", hornC = "crystal", hornLen = 0.72, hornR = 0.09, mane = "crystal", forelock = "crystal", tail = "horse", tailC = "crystal", ears = "horse", hoof = "crystal", leg = 1.0, neck = 0.62, mlen = 0.4, rump = false }
FORMS.craglet = { style = "goat", horns = "nubs", hornC = "rock", ears = "goat", sock = "rock", hoof = "rock_dark", leg = 0.72, len = 1.0, wide = 0.6, tall = 0.6, head = 1.06, tail = "flick", neck = 0.42, mlen = 0.28 }
FORMS.moonfawn = { hoof = "steel_dark", spots = "crystal", glow = true, crescent = "crystal", earIn = "crystal", earLen = 0.54, earW = 0.32, neck = 0.5, faceDetail = { marks = { spots = "crystal", glow = true } } }
-- Stormstag (ancient, 2026-11-20): a tall stag of storm grey, great white antlers of four tines with lightning yellow
-- at their tips, a white ruff and glowing yellow dots down its back like the flashes in a storm cloud.
FORMS.stormstag = { horns = "antler", hornC = "white", hornLen = 0.9, hornR = 0.075, tines = 4, fork = true, spread = 1.3, starTips = "yellow", glow = true, dots = "yellow", ruff = "white", tail = "tuft", tailC = "white", hoof = "slate", leg = 1.08, neck = 0.68, len = 1.26, h = 3.0, earLen = 0.46, faceDetail = { marks = { blaze = "yellow" } } }
FORMS.silverhoof = { style = "horse", horns = "spike", hornC = "steel", hornLen = 0.36, hornR = 0.065, mane = "steel", forelock = "steel", tail = "tuft", tailC = "steel", earLen = 0.4, hoof = "steel_dark", feather = "steel", leg = 1.08, neck = 0.66, len = 1.2, mlen = 0.42, h = 2.6, slim = 0.9, rump = false, faceDetail = { marks = { blaze = "steel" } } }
FORMS.raindeer = { horns = "antler", hornC = "white", hornLen = 0.62, tines = 2, cloud = "white", earLen = 0.42, faceDetail = { marks = { freckles = "blue" } } }
FORMS.starhart = { horns = "antler", hornC = "crystal", hornLen = 0.84, hornR = 0.065, tines = 3, fork = true, spread = 1.3, starTips = "yellow", dots = "crystal", tail = "tuft", tailC = "crystal", hoof = "crystal", leg = 1.04, neck = 0.66, len = 1.22, h = 2.9, earLen = 0.44, faceDetail = { marks = { star = "white", glow = true } } }

------------------------------------------------------------------ the ram (sheep and lambs)
-- A ram's curled horn on the head (on the head's joint): it rises from the top of the head, curls back, down behind
-- the ear and forward again beside the cheek, getting thinner and moving out from the head as it goes; `turn` how far
-- round it goes (radians), `rho` the curl's size.
local function curlHorn(h: A.Head, s: number, rho: number, r: number, turn: number, c: string, ridge: boolean?)
	Kit.on("head")
	local bd = V(s * 0.5, 0.8, -0.18).Unit
	local base = Kit.onEll(h.c, h.half, CFrame.identity, bd) - bd * r * 0.4
	local a0 = -0.5
	local c0 = base - (UP * math.cos(a0) - FWD * math.sin(a0)) * rho
	local n = 8
	local pts = { base }
	for i = 1, n do
		local u = i / n
		local a = a0 + u * (turn - a0)
		local rr = rho * (1 - 0.42 * u)
		-- (out past the side of the head within the first quarter turn, then a little further as it curls)
		local out = rho * (0.95 * math.min(1, u * 3) + 0.35 * u)
		table.insert(pts, c0 + V(s * out, 0, 0) + (UP * math.cos(a) - FWD * math.sin(a)) * rr)
	end
	Kit.limbs("Horn", pts, { r, r * 0.82, r * 0.55, r * 0.26 }, c, if full() then 7 else 3)
	if ridge and full() then
		for i = 1, 3 do
			local u = i * 0.2
			local p = Kit.curveAt(pts, u)
			local tg = Kit.curveAt(pts, u + 0.03) - Kit.curveAt(pts, u - 0.03)
			Kit.ell("HornRing", p, V(r * 2.1, r * 0.5, r * 2.1) * (1 - u * 0.55), A.shade(c), A.lie(tg))
		end
	end
end

-- A sheep: short bare legs ending in hooves under a body of soft wool, a few big overlapping puffs over a round body
-- (round at the chest, round at the rump, a puff on each flank and two along the back), a wool collar round the neck;
-- a bare face with a short soft muzzle, ears out to the sides under a woolly topknot, a stub of a woolly tail. The
-- form gives horns (small or curled), glowing streaks or stars in the fleece, the face's colour and the size.
PLANS.ram = function(b, a, form)
	local f: Form = form or {}
	local k = f.k or 1
	local legH = (f.leg or 0.6) * k
	local bl, bw, bt = (f.len or 1.1) * k, (f.wide or 0.9) * k, (f.tall or 0.84) * k
	local face = f.face or a
	local ink = A.ink(face, a)
	local t = Kit.new("ram", f.h or 2.0, f.r or 1.0, "quad")
	J("body", nil, V(0, legH + 0.1, 0), "body")
	local bc = V(0, legH + bt * 0.42, -0.02)
	A.body("Body", bc, V(0, 0.04, 1).Unit, bl, bw, bt, 0.52, b)
	-- the fleece: big soft puffs over the body (fewer on the islands)
	type Puff = { at: Vector3, size: Vector3, world: boolean }
	local puffs: { Puff } = {
		{ at = V(0, bt * 0.3, -bl * 0.14), size = V(bw * 0.78, bt * 0.62, bl * 0.56), world = true },
		{ at = V(0, bt * 0.28, bl * 0.18), size = V(bw * 0.8, bt * 0.6, bl * 0.5), world = true },
		{ at = V(-bw * 0.3, -bt * 0.02, -bl * 0.04), size = V(bw * 0.52, bt * 0.78, bl * 0.66), world = false },
		{ at = V(bw * 0.3, -bt * 0.02, -bl * 0.04), size = V(bw * 0.52, bt * 0.78, bl * 0.66), world = false },
		{ at = V(0, -bt * 0.04, bl * 0.36), size = V(bw * 0.76, bt * 0.78, bl * 0.42), world = true },
		{ at = V(0, -bt * 0.02, -bl * 0.4), size = V(bw * 0.76, bt * 0.76, bl * 0.4), world = true },
	}
	local cloud = f.cloudy
	for _, pf in puffs do
		if full() or pf.world then
			Kit.ell("Wool", bc + pf.at, if cloud then pf.size * 1.08 else pf.size, b)
		end
	end
	if cloud then
		-- a cloud's billows: two more round puffs on the shoulders and the hips
		for _, s in { -1, 1 } do
			Kit.ell("Wool", bc + V(s * bw * 0.26, bt * 0.22, bl * 0.2 * s), V(bw * 0.46, bt * 0.5, bl * 0.4), b, nil, true)
		end
	end
	-- glowing streaks or stars in the fleece (on the side the camera sees and on top; fewer on the islands)
	if f.streaks then
		local list = { { -70, 30, 0 }, { -100, 10, 1 }, { -125, 28, 0 }, { -40, 50, 1 }, { 70, 30, 1 }, { 105, 14, 0 }, { 0, 75, 0 }, { 180, 40, 1 } }
		for i, d in list do
			if full() or i <= 2 then
				local p, n = surf({ c = bc + V(0, bt * 0.1, 0), size = V(bw * 1.16, bl * 1.14, bt * 1.12), rot = A.lie(V(0, 0, -1), UP), split = 0.5 }, A.dir(d[1], d[2]))
				local col = if d[3] == 1 then (f.streak2 or f.streaks) else f.streaks
				Kit.ell("Streak", p, V(0.34, 0.08, 0.06), col, faceTo(n, V(0, 0.4, 1)), nil, true)
			end
		end
	end
	if f.stars then
		local list = { { -60, 40 }, { -95, 12 }, { -130, 34 }, { -20, 60 }, { -160, 50 }, { 60, 40 }, { 100, 18 }, { 20, 70 }, { 140, 36 }, { -75, -8 } }
		for i, d in list do
			if full() or i <= 2 then
				local p, n = surf({ c = bc + V(0, bt * 0.1, 0), size = V(bw * 1.16, bl * 1.14, bt * 1.12), rot = A.lie(V(0, 0, -1), UP), split = 0.5 }, A.dir(d[1], d[2]))
				Kit.ell("Star", p, V(0.08, 0.08, 0.06), if i % 3 == 0 then (f.star2 or f.stars) else f.stars, faceTo(n), nil, true)
			end
		end
		if full() then
			star("BigStar", bc + V(-bw * 0.42, bt * 0.48, -bl * 0.05), 0.11, f.stars, V(-1, 0.6, 0.3))
			star("BigStar", bc + V(-bw * 0.1, bt * 0.62, bl * 0.24), 0.09, f.star2 or f.stars, V(-0.4, 1, 0.3))
		end
	end
	-- legs: short and bare under the wool, woolly at the top
	local lx = bw * 0.26
	local fz, hz = bc.Z + bl * 0.28, bc.Z - bl * 0.28
	for _, l in { { n = "FL", s = -1, z = fz, ph = 0 }, { n = "FR", s = 1, z = fz, ph = 0.5 }, { n = "BL", s = -1, z = hz, ph = 0.5 }, { n = "BR", s = 1, z = hz, ph = 0 } } do
		local hind = l.z < 0
		local r = (if hind then 0.11 else 0.1) * k
		hoofLeg(l.n, l.s, l.ph, V(l.s * lx, legH + 0.08 * k, l.z), {
			hind = hind,
			r = r,
			c = face,
			hoof = f.hoof or "black",
			fw = 0.18 * k,
			mass = V(r * 3.4, r * 3.6, r * 3.6),
			massC = b,
			lite = true,
		})
	end
	-- the neck, short, in a wool collar
	local nb = bc + V(0, bt * 0.22, bl * 0.36)
	local hc = nb + V(0, 0.46, 0.38) * k
	J("head", "body", nb + V(0, 0.16, 0.08) * k, "head")
	Kit.limb("Neck", nb, hc - V(0, 0.12, 0.08) * k, 0.2 * k, 0.17 * k, face)
	Kit.on("body")
	Kit.ell("Collar", nb + V(0, 0.04, 0.0) * k, V(bw * 0.68, bt * 0.5, bl * 0.3), b)
	-- the head: a bare face, a short soft muzzle
	local hsz = V(0.62, 0.6, 0.64) * k * (f.headK or 1)
	local h = A.head({
		c = hc,
		size = hsz,
		color = face,
		muzzle = "deer",
		mlen = 0.24 * k,
		mw = 0.34 * k,
		mdrop = 0.12 * k,
		nose = f.nose or (if A.isDark(face) then A.shade(face) else "clay"),
		eye = { R(38), R(6), 0.24 * k },
		iris = A.iris(a, "blue"),
		ink = if A.isDark(face) then ink else nil,
		blush = true,
		-- (a bare face in its wool: tufts of the wool at the cheeks)
		face = A.more({ tex = "fluff", tuft = b }, f.faceDetail),
	})
	-- ears out to the sides, a little down
	for _, s in { -1, 1 } do
		ear(h, s, { at = V(s * 0.9, 0.3, -0.2), dir = V(s, -0.28, -0.18), len = 0.3 * k, w = 0.17 * k, c = face, inner = "pink", tip = 0.3, face = V(s * 0.1, 0.7, 1) })
	end
	Kit.on("head")
	-- the topknot: wool on the crown, down to the brow
	Kit.ell("Topknot", h.c + V(0, hsz.Y * 0.4, -hsz.Z * 0.12), V(hsz.X * 0.82, hsz.Y * 0.46, hsz.Z * 0.72), b)
	Kit.ell("Topknot", h.c + V(0, hsz.Y * 0.4, hsz.Z * 0.14), V(hsz.X * 0.5, hsz.Y * 0.32, hsz.Z * 0.38), b, nil, true)
	if f.forelock then
		-- a forelock swept back by the wind
		Kit.limb("Forelock", h.c + V(0, hsz.Y * 0.5, hsz.Z * 0.14), h.c + V(-0.06, hsz.Y * 0.78, -hsz.Z * 0.4), 0.13 * k, 0.04, b, 0.6, V(1, 0, 0))
	end
	-- horns
	local hk = f.horns
	if hk == "curl" then
		for _, s in { -1, 1 } do
			curlHorn(h, s, (f.rho or 0.22) * k, (f.hornR or 0.1) * k, f.turn or 4.2, f.hornC or a, true)
		end
	elseif hk == "small" then
		for _, s in { -1, 1 } do
			curlHorn(h, s, 0.13 * k, 0.065 * k, 2.2, f.hornC or a)
		end
	end
	-- the tail: a woolly stub
	Kit.on("body")
	local tb = bc + V(0, bt * 0.18, -bl * 0.5)
	J("tail1", "body", tb, "tail", 0, 1)
	Kit.ell("Tail", tb + V(0, -0.02, -0.08) * k, V(0.24, 0.26, 0.22) * k, b)
	Kit.on("body")
	if f.drops and full() then
		-- a loose bit of cloud: a few drops of rain under the belly
		for _, p in { V(-0.12, 0.26, 0.06), V(0.1, 0.18, -0.16) } do
			Kit.egg("Drop", p * k, V(0.06, 0.1, 0.06), 0.66, "blue")
		end
	end
	return t
end

FORMS.puffling = { k = 0.82, h = 1.6, r = 0.9, cloudy = true, leg = 0.56, drops = true, nose = "jeans", hoof = "jeans", headK = 1.2 }
FORMS.glimmerfleece = { horns = "small", hornC = "steel", face = "night", streaks = "screen_on", streak2 = "pink", h = 1.95, faceDetail = { marks = { freckles = "screen_on", glow = true } } }
FORMS.galeram = { horns = "curl", hornC = "rock", face = "cream", forelock = true, rho = 0.24, hornR = 0.11, turn = 4.4, k = 1.06, h = 2.1, nose = "clay" }
FORMS.cosmofleece = { horns = "curl", hornC = "screen_on", face = "night", stars = "white", star2 = "screen_on", rho = 0.2, turn = 3.9, k = 1.04, h = 2.1, faceDetail = { marks = { star = "screen_on", glow = true } } }

------------------------------------------------------------------ the elephant (calves and mammoths)
-- A zigzag lying on a mass (a lightning mark, a glowing crack): through the surface points toward each of `dirs`
-- (yaw, pitch pairs as A.dir takes them), `r` thick, a little proud of the surface.
local function zig(name: string, m: A.Mass, dirs: { { number } }, r: number, color: string, neon: boolean?, detail: boolean?)
	local prev: Vector3? = nil
	local pn = UP
	for _, d in dirs do
		local p, n = surf(m, A.dir(d[1], d[2]))
		local q = p + n * r * 0.3
		if prev then
			Kit.limb(name, prev, q, r, r * 0.85, color, 0.5, (n + pn).Unit, detail, neon)
		end
		prev, pn = q, n
	end
end

-- An elephant calf: a round barrel of a body on four pillar legs with broad round feet and pale toenails; a big round
-- head with a domed brow straight on the shoulders, big flat ears hanging at its sides, a trunk of tapering links that
-- sways on its own two joints, a lower lip under it, a thin tail with a tuft. The form gives tusks, the ears' size,
-- fur (a mammoth's), markings (lightning, glowing cracks) and a raised trunk.
PLANS.elephant = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("elephant", f.h or 2.1, f.r or 1.2, "quad")
	local under = A.shade(b)
	local skinIn = f.earIn or (if A.isDark(b) then "slate" else "pink")
	J("body", nil, V(0, 0.86, 0), "body")
	local bc = V(0, 0.92, -0.18)
	local bl, bw, bt = f.len or 1.16, f.wide or 0.94, f.tall or 0.86
	local _, body = A.body("Body", bc, V(0, 0.06, 1).Unit, bl, bw, bt, 0.5, b)
	if f.fur then
		-- a mammoth's coat: a hump over the shoulders, a long fringe hanging under the belly and flanks
		Kit.ell("Hump", bc + V(0, bt * 0.36, bl * 0.18), V(bw * 0.72, bt * 0.5, bl * 0.46), b)
		local n = if full() then 7 else 2
		for i = 1, n do
			local u = (i - 1) / (n - 1)
			for _, s in { -1, 1 } do
				local yaw = s * (40 + u * 100)
				local p, nn = surf(body, A.dir(yaw, -18))
				local tip = p + V(nn.X * 0.06, -0.26 - 0.04 * math.sin(u * 3.1), nn.Z * 0.04)
				Kit.limb("Fringe", p + V(0, 0.08, 0), tip, 0.13, 0.05, f.fur, 0.6, V(nn.X, 0, nn.Z))
			end
		end
	end
	if f.cracks then
		-- glowing cracks across the hide, as if lit from inside
		zig("Crack", body, { { -60, 30 }, { -75, 14 }, { -66, 2 }, { -84, -12 } }, 0.035, f.cracks, true)
		zig("Crack", body, { { -120, 40 }, { -132, 22 }, { -124, 8 } }, 0.03, f.cracks, true)
		if full() then
			zig("Crack", body, { { 70, 30 }, { 82, 12 }, { 74, -4 } }, 0.03, f.cracks, true, true)
			zig("Crack", body, { { -20, 62 }, { -34, 50 }, { -26, 38 } }, 0.03, f.cracks, true, true)
		end
	end
	if f.bolts then
		-- a lightning bolt down each flank
		for _, s in { -1, 1 } do
			zig("Bolt", body, { { s * 70, 44 }, { s * 92, 20 }, { s * 78, 12 }, { s * 100, -14 } }, 0.06, f.bolts)
		end
	end
	-- legs: pillars on round pads
	for _, l in { { n = "FL", s = -1, z = 0.18, ph = 0 }, { n = "FR", s = 1, z = 0.18, ph = 0.5 }, { n = "BL", s = -1, z = -0.56, ph = 0.5 }, { n = "BR", s = 1, z = -0.56, ph = 0 } } do
		local r = f.legR or 0.18
		A.leg(l.n, l.s, l.ph, V(l.s * bw * 0.3, 0.64, l.z), {
			kind = "post",
			r = r,
			c = b,
			foot = "pad",
			fw = r * 2.25,
			fc = b,
			claw = f.nails or "cream",
			massSize = if f.fur then V(r * 3, r * 3.4, r * 3) else nil,
			massC = b,
		})
		if f.fur then
			-- shaggy hair down the top of the leg
			Kit.limb("LegFur" .. l.n, V(l.s * bw * 0.32, 0.58, l.z), V(l.s * bw * 0.34, 0.32, l.z), r * 1.22, r * 1.2, f.fur, nil, nil, true)
		end
	end
	-- the head, big and round, straight on the shoulders
	local hc = V(0, 1.5, 0.5)
	local hs = f.headS or V(1.04, 0.98, 0.88)
	A.head({
		c = hc,
		size = hs,
		color = b,
		pivot = V(0, 1.2, 0.26),
		muzzle = "none",
		mw = 0.4,
		mlen = 0.2,
		mdrop = 0.34,
		eye = { R(44), R(10), 0.27 },
		iris = A.iris(a, "wood_dark"),
		blush = true,
		mouth = false,
		faceLater = true,
	})
	Kit.on("head")
	-- the brow's dome
	Kit.ell("Brow", hc + V(0, hs.Y * 0.2, hs.Z * 0.06), V(hs.X * 0.82, hs.Y * 0.6, hs.Z * 0.7), b)
	if f.fur then
		Kit.limb("Topknot", hc + V(0, hs.Y * 0.4, -hs.Z * 0.1), hc + V(-0.02, hs.Y * 0.62, hs.Z * 0.1), 0.18, 0.06, f.fur, 0.7, V(1, 0, 0))
	end
	-- the mouth, under the trunk
	Kit.mouth(hc + V(0, -hs.Y * 0.4, hs.Z * 0.4), V(0, -0.5, 1), 0.16, A.ink(b, a), "pink")
	-- the face's details (A.face), the brow's dome left bare
	A.face({ color = b, c = hc, half = hs / 2, more = A.more({ crown = false }, f.faceDetail) })
	-- ears: big flat flaps spread out from the back of the head's sides, the lining facing forward
	local es = f.ear or 1
	for _, s in { -1, 1 } do
		local sn = sideName(s)
		local at = hc + V(s * hs.X * 0.42, hs.Y * 0.1, -hs.Z * 0.18)
		J("ear" .. sn, "head", at, "ear", s)
		local n = V(s * 0.42, 0.06, 1).Unit
		local ew, eh = 0.6 * es, 0.7 * es
		local c0 = at + V(s * ew * 0.42, -eh * 0.18, -0.04)
		local rot = faceTo(n, V(0, 1, 0))
		Kit.ell("Ear" .. sn, c0, V(ew, eh, 0.08), b, rot)
		if full() then
			-- (its root, thick where it leaves the head: up close the blended body runs on into the flap)
			Kit.ell("EarRoot" .. sn, at + V(s * ew * 0.12, -eh * 0.08, 0), V(ew * 0.36, eh * 0.56, 0.26), b, rot)
		end
		Kit.ell("EarIn" .. sn, c0 + n * 0.035 + V(s * ew * 0.04, 0, 0), V(ew * 0.72, eh * 0.72, 0.05), f.earC or skinIn, rot, true)
		local mark = f.bolts or f.cracks
		if mark then
			-- a bolt (or a glowing crack) across the ear
			local x, y = rot.XVector, rot.YVector
			local q = c0 + n * 0.06
			local pts = { q + y * eh * 0.32 - x * ew * 0.1, q + y * eh * 0.06 + x * ew * 0.12 * s, q - y * eh * 0.02 - x * ew * 0.08 * s, q - y * eh * 0.3 + x * ew * 0.1 * s }
			local w = if f.bolts then 0.045 else 0.03
			for i = 1, 3 do
				Kit.limb(if f.bolts then "Bolt" else "Crack", pts[i], pts[i + 1], w, w * 0.9, mark, 0.4, n, true, f.cracks ~= nil)
			end
		end
	end
	Kit.on("head")
	-- tusks
	if f.tusks then
		local tl = f.tuskLen or 1
		for _, s in { -1, 1 } do
			local base = hc + V(s * 0.17, -hs.Y * 0.3, hs.Z * 0.36)
			local pts = if f.tuskCurl
				then { base, base + V(s * 0.12, -0.2, 0.16) * tl, base + V(s * 0.1, -0.22, 0.4) * tl, base + V(-s * 0.04, 0.02, 0.56) * tl }
				else { base, base + V(s * 0.04, -0.16, 0.16) * tl, base + V(s * 0.02, -0.14, 0.34) * tl, base + V(0, 0.0, 0.44) * tl }
			Kit.limbs("Tusk", pts, { 0.075, 0.06, 0.025 }, f.tusks, 3)
		end
	end
	-- the trunk: tapering links on two joints
	local tb = hc + V(0, -hs.Y * 0.16, hs.Z * 0.4)
	local pts: { Vector3 }
	if f.raised then
		-- held up and curling, off to its right so the face still shows
		pts = { tb, tb + V(0.02, -0.12, 0.24), tb + V(0.1, 0.02, 0.44), tb + V(0.2, 0.3, 0.5), tb + V(0.24, 0.54, 0.36) }
	else
		pts = { tb, tb + V(0, -0.1, 0.22), tb + V(0, -0.34, 0.32), tb + V(0, -0.58, 0.32), tb + V(0, -0.7, 0.44) }
	end
	local tr = f.trunkR or 0.13
	J("trunk1", "head", tb, "tendril", 0, 1)
	Kit.limbs("Trunk", { pts[1], pts[2], pts[3] }, { tr, tr * 0.8 }, b, 2)
	if full() then
		-- the rings across its top
		for i = 1, 3 do
			local p = Kit.curveAt(pts, i * 0.16)
			local tg = Kit.curveAt(pts, i * 0.16 + 0.03) - Kit.curveAt(pts, i * 0.16 - 0.03)
			Kit.ell("TrunkRing", p, V(tr * 2.08, 0.05, tr * 2.08) * (1 - i * 0.07), under, A.lie(tg))
		end
	end
	J("trunk2", "trunk1", pts[3], "tendril", 0, 1.5)
	Kit.limbs("Trunk", { pts[3], pts[4], pts[5] }, { tr * 0.8, tr * 0.58 }, b, 2)
	local endD = (pts[5] - pts[4]).Unit
	Kit.ell("TrunkTip", pts[5] + endD * 0.03, V(tr * 1.3, 0.08, tr * 1.3), under, A.lie(endD))
	-- the tail, thin with a tuft
	Kit.on("body")
	local tbase = bc + V(0, bt * 0.12, -bl * 0.48)
	J("tail1", "body", tbase, "tail", 0, 1)
	local t1 = tbase + V(0, -0.24, -0.14)
	Kit.limb("Tail", tbase, t1, 0.05, 0.04, b)
	J("tail2", "tail1", t1, "tail", 0, 2)
	Kit.limb("Tail", t1, t1 + V(0, -0.2, -0.02), 0.04, 0.035, b)
	Kit.ell("TailTuft", t1 + V(0, -0.26, -0.02), V(0.12, 0.18, 0.12), f.tuft or (f.fur or A.shade(b)))
	return t
end

FORMS.obsidusk = { tusks = "orange", cracks = "lava", nails = "orange", earC = "slate", tuft = "orange" }
FORMS.tuskle = { tusks = "white", tuskCurl = true, tuskLen = 1.1, fur = "wood_dark", ear = 0.55, legR = 0.2, h = 2.1, tuft = "wood_dark" }
FORMS.stormphant = { bolts = "yellow", raised = true, ear = 1.4, h = 2.4, nails = "white", tuft = "yellow" }

------------------------------------------------------------------ the griffin
-- A pair of feathered wings raised behind the back (joints "wingL" / "wingR" on the body and "wingL2" / "wingR2" at
-- the wrist), each in a near upright plane facing out (and up by `open` degrees), so its outer face shows: the arm up
-- and back from the shoulder with a panel of coverts below it and the secondaries hanging off it, then the hand
-- sweeping back with the long primaries fanning down and back off it, the outer ones in `edge`. `lift` how high the
-- arm rises (1 high), `span` their length.
local function featherWings(sh: Vector3, span: number, lift: number, open: number, c: string, edge: string?, inner: string?)
	for _, s in { -1, 1 } do
		local sn = sideName(s)
		local p0 = A.mx(sh, s)
		J("wing" .. sn, "body", p0, "wing", s)
		local be = R(open)
		local nrm = V(s * math.cos(be), math.sin(be), 0)
		local up = V(-s * math.sin(be), math.cos(be), 0)
		local back = V(0, 0, -1)
		local wrist = p0 + (up * 0.46 * lift + back * (0.2 + 0.12 * (1 - lift))) * span
		local tipP = wrist + (back * 0.5 - up * 0.08) * span
		Kit.limb("WingArm" .. sn, p0, wrist, 0.11 * span, 0.085 * span, c, 0.6, nrm)
		-- the coverts: a soft panel under the arm
		Kit.limb("Coverts" .. sn, p0 + (back * 0.1 + up * 0.02) * span, wrist + (back * 0.08 - up * 0.14) * span, 0.15 * span, 0.13 * span, inner or c, 0.4, nrm, true)
		-- the secondaries hanging down and back off the arm
		local n2 = if full() then 3 else 1
		for i = 1, n2 do
			local u = if n2 == 1 then 0.6 else 0.2 + (i - 1) / math.max(1, n2 - 1) * 0.7
			local b0 = lerp(p0, wrist, u) + (back * 0.1 - up * 0.08) * span
			Kit.limb("Feather" .. sn, b0, b0 + (back * 0.32 - up * (0.28 + 0.12 * u)) * span, 0.08 * span, 0.055 * span, c, 0.35, nrm)
		end
		J("wing" .. sn .. "2", "wing" .. sn, wrist, "wing", s, 1)
		Kit.limb("WingHand" .. sn, wrist, tipP, 0.085 * span, 0.05 * span, c, 0.6, nrm)
		-- a soft panel under the primaries' roots, so the wing reads as one surface with only the tips apart
		Kit.limb("WingPanel" .. sn, lerp(wrist, tipP, 0.3), lerp(wrist, tipP, 0.45) + (back * 0.3 - up * 0.32) * span, 0.1 * span, 0.2 * span, c, 0.2, nrm, true)
		-- the primaries: long feathers fanning back and down off the hand, longest at the tip
		local n = if full() then 5 else 2
		for i = 1, n do
			local u = (i - 1) / (n - 1)
			local b0 = lerp(wrist, tipP, 0.08 + u * 0.92)
			local L = (0.4 + 0.3 * u) * span
			local d = (back * (0.5 + 0.5 * u) - up * (1 - 0.8 * u)).Unit
			local col = if edge and u > 0.45 then edge else c
			Kit.limb("Primary" .. sn, b0, b0 + d * L, 0.075 * span, 0.045 * span, col, 0.35, nrm)
		end
	end
	Kit.on("body")
end

-- A griffin: an eagle's front and a lion's back. A lion's body (the chest deep, the hips slim) with the front half
-- feathered in the head's colour, a ruff where the neck meets the chest; eagle forelegs (feathered to the wrist, then
-- bare scaly shanks and three talons forward, one back); a lion's hind legs and paws; a long lion's tail with a tuft;
-- an eagle's head on a short neck, the hooked beak, a heavy brow, a crest of feathers swept back; feathered wings
-- raised over the back. The form picks the crest, how the wings are held, a cloud ruff and the colours.
PLANS.griffin = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("griffin", f.h or 2.5, f.r or 1.25, "quad")
	local hcC = f.headC or a -- the head, the chest, the wings
	local beakC = f.beak or "gold"
	local scale = f.scaleC or "yellow"
	local talon = f.talon or "black"
	J("body", nil, V(0, 0.88, 0), "body")
	local bc = V(0, 0.94, -0.12)
	local bl, bw, bt = 1.26, 0.68, 0.66
	local _, body = A.body("Body", bc, V(0, 0.14, 1).Unit, bl, bw, bt, 0.58, b)
	-- the feathered chest: the front of the body in the head's colour, a ruff of feathers at the neck
	A.patch("Chest", body, V(0, -0.1, 1), V(0.96, 0.62, 0.96), 0.03, hcC)
	if f.cloud then
		-- a ruff of soft cloud round the neck
		for i, p in { V(0, 0.18, 0.5), V(-0.24, 0.08, 0.42), V(0.24, 0.08, 0.42), V(-0.16, -0.12, 0.52), V(0.16, -0.12, 0.52), V(0, -0.04, 0.6) } do
			if full() or i <= 3 then
				Kit.ell("Ruff", bc + p, V(0.34, 0.28, 0.3), f.cloud)
			end
		end
	else
		local n = if full() then 5 else 2
		for i = 1, n do
			local u = (i - 1) / (n - 1)
			local x = (-1 + 2 * u) * 0.22
			local p = bc + V(x, 0.2 - math.abs(x) * 0.5, 0.48)
			Kit.limb("Ruff", p, p + V(x * 0.4, -0.3, 0.12), 0.1, 0.03, hcC, 0.45, V(0, 0.2, 1))
		end
	end
	-- eagle forelegs: feathered to the wrist, then a bare scaly shank and a bird's foot
	for _, l in { { n = "FL", s = -1, ph = 0 }, { n = "FR", s = 1, ph = 0.5 } } do
		local s = l.s
		local hip = V(s * 0.22, 0.8, 0.3)
		J("leg" .. l.n, "body", hip, "leg", s, l.ph)
		Kit.ell(l.n .. "Shoulder", hip + V(0, 0.06, 0), V(0.3, 0.4, 0.34), hcC, nil, true)
		local wrist = V(s * 0.25, 0.4, 0.33)
		Kit.limb("Leg" .. l.n, hip, wrist, 0.13, 0.1, hcC)
		-- the feather trousers, ending in a soft frill over the shank
		Kit.ell("Trouser" .. l.n, wrist + V(0, 0.03, 0), V(0.24, 0.15, 0.24), hcC, nil, true)
		local foot = V(s * 0.26, 0, 0.38)
		Kit.limb("Shank" .. l.n, wrist, foot + V(0, 0.06, 0), 0.065, 0.055, scale)
		if full() then
			A.birdFoot("Foot" .. l.n, foot, 0.2, scale, talon, FWD)
		else
			Kit.limb("Foot" .. l.n, foot + V(0, 0.05, -0.04), foot + V(0, 0.04, 0.2), 0.06, 0.05, scale, 0.6, UP)
		end
	end
	-- lion hind legs and paws
	for _, l in { { n = "BL", s = -1, ph = 0.5 }, { n = "BR", s = 1, ph = 0 } } do
		A.leg(l.n, l.s, l.ph, V(l.s * 0.22, 0.82, -0.48), { kind = "hind", r = 0.14, c = b, foot = "paw", fw = 0.24, pad = f.pad or A.shade(b), out = 0.03, mass = full() })
	end
	-- the lion's tail: long and thin, curving down then up, a tuft at its end
	local tb = bc + V(0, bt * 0.2, -bl * 0.52)
	J("tail1", "body", tb, "tail", 0, 1)
	local t1 = tb + V(0, -0.24, -0.34)
	Kit.limbs("Tail", { tb, tb + V(0, -0.12, -0.2), t1 }, { 0.07, 0.055 }, b, 2)
	J("tail2", "tail1", t1, "tail", 0, 2)
	local t2 = t1 + V(0, 0.14, -0.3)
	local t3 = t2 + V(0, 0.28, -0.1)
	Kit.limbs("Tail", { t1, t2, t3 }, { 0.055, 0.045 }, b, 2)
	local tuftC = f.tuft or hcC
	Kit.limb("TailTuft", t3 - V(0, 0.04, 0), t3 + V(0, 0.2, -0.06), 0.1, 0.05, tuftC, 0.8, V(1, 0, 0), true)
	Kit.ell("TailTuft", t3 + V(0, 0.04, 0), V(0.18, 0.2, 0.18), tuftC)
	-- wings
	Kit.on("body")
	featherWings(bc + V(0.24, 0.3, 0.22), f.span or 1, f.lift or 1, f.open or 18, hcC, f.wingTip, f.coverts)
	-- the neck and the head
	local nb = bc + V(0, bt * 0.28, bl * 0.34)
	local nt = nb + V(0, 0.36, 0.2)
	J("neck", "body", nb, "neck")
	Kit.limb("Neck", nb, nt, 0.2, 0.17, hcC)
	local hc = nt + V(0, 0.2, 0.14)
	local hs = V(0.74, 0.72, 0.78)
	A.head({
		c = hc,
		size = hs,
		color = hcC,
		parent = "neck",
		pivot = nt,
		muzzle = "beak",
		beak = beakC,
		mlen = 0.34,
		mw = 0.32,
		mdrop = 0.1,
		eye = { R(40), R(8), 0.27 },
		iris = A.iris(f.iris or "gold", "gold"),
		blush = false,
		-- (its own crest, and its own brows where it has them)
		face = A.more({ crown = false, brows = if f.brow then false else nil }, f.faceDetail),
	})
	Kit.on("head")
	-- the cere where the beak meets the face, and the brow over each eye
	Kit.ell("Cere", hc + V(0, -0.04, hs.Z * 0.42), V(0.3, 0.16, 0.14), f.cere or beakC, nil, true)
	if f.brow then
		for _, s in { -1, 1 } do
			local p = Kit.onEll(hc, hs / 2, CFrame.identity, A.dir(s * 32, 44))
			Kit.limb("Brow", p + V(s * 0.1, 0.05, -0.06), p + V(-s * 0.04, 0.0, 0.05), 0.05, 0.04, f.brow, 0.6, UP, true)
		end
	end
	-- the crest: feathers swept back off the crown
	local ck = f.crest or "swept"
	if ck == "swept" then
		for i, c in { { 0, 0.5, 0.36 }, { -0.12, 0.42, 0.3 }, { 0.12, 0.42, 0.3 }, { 0, 0.28, 0.32 } } do
			if full() or i <= 2 then
				local base = hc + V(c[1] * 0.6, hs.Y * 0.36, -hs.Z * 0.1)
				local tip = base + V(c[1], c[2] * 0.5, -c[3] - 0.08)
				Kit.limb("Crest", base, tip, 0.09, 0.025, if i == 1 then (f.crestTip or hcC) else hcC, 0.4, V(1, 0, 0))
			end
		end
	else
		-- a soft round crest, two short plumes
		for i, x in { -0.08, 0.08 } do
			local base = hc + V(x, hs.Y * 0.4, -hs.Z * 0.12)
			Kit.limb("Crest", base, base + V(x * 0.8, 0.16, -0.18), 0.08, 0.04, if i == 1 then (f.crestTip or hcC) else hcC, 0.5, V(1, 0, 0))
		end
	end
	-- cheek feathers flaring back below the eyes
	if full() then
		for _, s in { -1, 1 } do
			local p = hc + V(s * hs.X * 0.4, -hs.Y * 0.16, -hs.Z * 0.1)
			Kit.limb("Cheek", p, p + V(s * 0.08, -0.06, -0.2), 0.08, 0.025, hcC, 0.45, V(s, 0, 0))
		end
	end
	return t
end

FORMS.stormgriff = { headC = "white", beak = "gold", scaleC = "yellow", talon = "black", crest = "swept", crestTip = "yellow", lift = 1.15, open = 26, span = 1.05, brow = "white", tuft = "white", iris = "gold" }
FORMS.cloudgriff = { headC = "white", beak = "gold", scaleC = "gold", talon = "gold", crest = "round", crestTip = "gold", lift = 0.7, open = 10, span = 1.0, cloud = "white", wingTip = "gold", tuft = "gold", pad = "cream", h = 2.4 }

------------------------------------------------------------------ the drake
-- A pair of membrane wings spread up and out (joints "wingL" / "wingR" on the body and "wingL2" / "wingR2" at the
-- wrist), each in a plane facing forward and out (swept back by `sweep` degrees), so from the front three quarter
-- view both show their faces: the arm out and up to the elbow, the forearm up to the wrist (the wing's highest point,
-- a thumb claw on it), long fingers fanning out and down from the wrist, the membrane stretched between them in flat
-- panels that stop short of the finger tips (the scalloped trailing edge), the last panel back down to the flank.
-- `fingers` 3 or 4, `span` the size, `c` the bones, `mem` the membrane, `claw` the thumb's colour, `edge` the first
-- panel's colour, `tips` a claw on the leading finger.
type BatO = { span: number, lift: number?, sweep: number?, fingers: number?, c: string, mem: string, claw: string, edge: string?, tips: string? }
local function batWings(sh: Vector3, o: BatO)
	local span = o.span
	local lift = o.lift or 1
	for _, s in { -1, 1 } do
		local sn = sideName(s)
		local p0 = A.mx(sh, s)
		J("wing" .. sn, "body", p0, "wing", s)
		local sw = R(o.sweep or 40)
		local nrm = V(s * math.sin(sw), 0.12, math.cos(sw)).Unit
		local up = (UP - nrm * UP:Dot(nrm)).Unit
		local out = up:Cross(nrm)
		if out.X * s < 0 then
			out = -out
		end
		local elbow = p0 + (out * 0.3 + up * 0.22 * lift) * span
		local wrist = elbow + (out * 0.14 + up * 0.3 * lift) * span
		if full() then
			Kit.limb("WingArm" .. sn, p0, elbow, 0.1 * span, 0.075 * span, o.c)
			Kit.limb("WingArm" .. sn, elbow, wrist, 0.075 * span, 0.06 * span, o.c)
		else
			Kit.limb("WingArm" .. sn, p0, wrist, 0.1 * span, 0.065 * span, o.c)
		end
		local flank = p0 + (out * 0.08 - up * 0.3) * span + V(0, 0, -0.3)
		J("wing" .. sn .. "2", "wing" .. sn, wrist, "wing", s, 1)
		-- (the membrane is one skin: each panel's corners ride the arm, the hand or the body, and the rig stretches the
		-- panel between them as the wing beats, so the fan and the panel back to the flank never part: Kit.tri with
		-- joints; the request of 2026-11-18, "scorchwing and other bat type creatures have their wing parts seperated")
		local jA, jH, jB = "wing" .. sn, "wing" .. sn .. "2", "body"
		if not full() then
			-- (the islands' wing: the leading finger, the membrane a flat triangle from the wrist out to the finger
			-- tips, then back down to the flank)
			local t1 = wrist + (out * 0.58 + up * 0.12) * span
			local t3 = wrist + (out * 0.36 - up * 0.66) * span
			Kit.limb("WingFinger" .. sn, wrist, t1, 0.05 * span, 0.03 * span, o.c)
			Kit.tri("WingSkin" .. sn, wrist, lerp(t1, wrist, 0.05), lerp(t3, wrist, 0.05), 0.05, o.mem, nil, jH, jH, jH)
			Kit.on("wing" .. sn)
			Kit.tri("WingSkin" .. sn, wrist, lerp(t3, wrist, 0.05), flank, 0.05, o.mem, nil, jA, jH, jB)
			Kit.tri("WingSkin" .. sn, lerp(elbow, wrist, 0.5), wrist, flank, 0.05, o.mem, nil, jA, jA, jB)
			continue
		end
		local nf = o.fingers or 3
		local dirs: { { number } } = if nf >= 4
			then { { 0.5, 0.2 }, { 0.66, -0.12 }, { 0.6, -0.44 }, { 0.36, -0.7 } }
			else { { 0.56, 0.14 }, { 0.62, -0.28 }, { 0.36, -0.66 } }
		local tips: { Vector3 } = {}
		for i, d in dirs do
			local tip = wrist + (out * d[1] + up * d[2]) * span
			tips[i] = tip
			Kit.limb("WingFinger" .. sn, wrist, tip, 0.05 * span, 0.028 * span, o.c)
			if o.tips and full() and i == 1 then
				Kit.limb("FingerClaw" .. sn, tip, tip + (tip - wrist).Unit * 0.08 * span, 0.035 * span, 0.01, o.tips)
			end
		end
		-- the membrane panels: flat triangles from the wrist to each pair of finger tips, short of the tips (the
		-- scalloped trailing edge), each corner on its bone
		local function short(a0: Vector3, b0: Vector3, apex: Vector3): (Vector3, Vector3)
			local mid = lerp(a0, b0, 0.5)
			return lerp(mid + (a0 - mid) * 0.92, apex, 0.14), lerp(mid + (b0 - mid) * 0.92, apex, 0.14)
		end
		for i = 1, nf - 1 do
			local a1, b1 = short(tips[i], tips[i + 1], wrist)
			Kit.tri("WingSkin" .. sn, wrist, a1, b1, 0.05, if o.edge and i == 1 then o.edge else o.mem, nil, jH, jH, jH)
		end
		Kit.on("wing" .. sn)
		-- the last panel back down to the flank, and the sliver between it and the fan at the wrist
		local apex = lerp(elbow, wrist, 0.4)
		local tn, fl = short(tips[nf], flank, apex)
		Kit.tri("WingSkin" .. sn, tn, fl, apex, 0.05, o.mem, nil, jH, jB, jA)
		Kit.tri("WingSkin" .. sn, wrist, tn, apex, 0.05, o.mem, nil, jA, jH, jA)
		-- the thumb's claw at the wrist, hooked forward
		Kit.limb("Thumb" .. sn, wrist, wrist + (up * 0.08 + nrm * 0.1) * span, 0.045 * span, 0.012, o.claw, nil, nil, true)
	end
	Kit.on("body")
end

-- One spine on the back at `at`, `h` tall, leaning back: "plate" a flat triangle, "flame" a curling tongue of fire with
-- a bright core, "shard" a pair of ice crystals, "bolt" a zigzag of lightning.
local function spine(kind: string, at: Vector3, h: number, color: string, core: string?, detail: boolean?)
	if detail and not full() then
		return
	end
	local back = V(0, 0, -1)
	if not full() then
		-- (the islands' spine: one flat tapering piece)
		Kit.limb("Spine", at - UP * h * 0.1, at + UP * h + back * h * 0.4, h * 0.32, h * 0.04, color, 0.4, V(1, 0, 0))
		return
	end
	if kind == "plate" then
		Kit.blade("Spine", at - UP * h * 0.15, at + UP * h + back * h * 0.45, h * 0.9, 0.07, V(1, 0, 0), color)
	elseif kind == "flame" then
		local tip = at + UP * h + back * h * 0.5
		Kit.limbs("Flame", { at, at + UP * h * 0.5 + back * h * 0.05, tip }, { h * 0.3, h * 0.04 }, color, 2, 0.55, V(1, 0, 0))
		if core and full() then
			Kit.limb("FlameCore", at + UP * h * 0.12, at + UP * h * 0.5 + back * h * 0.12, h * 0.17, h * 0.05, core, 0.5, V(1, 0, 0), nil, true)
		end
	elseif kind == "shard" then
		Kit.limb("Shard", at - UP * h * 0.1, at + UP * h + back * h * 0.25, h * 0.2, 0.025, color, 0.8, V(1, 0, 0))
		if full() then
			Kit.limb("Shard", at, at + UP * h * 0.6 + back * h * 0.5 + V(0.06, 0, 0), h * 0.15, 0.025, core or color, 0.8, V(1, 0, 0))
		end
	elseif kind == "bolt" then
		-- (two strokes: up and back to a corner, then a jag forward and up to the point)
		local p1 = at + UP * h * 0.55 + back * h * 0.42
		local tip = p1 + UP * h * 0.55 - back * h * 0.2
		Kit.limb("Bolt", at - UP * h * 0.1, p1 + back * h * 0.06, h * 0.18, h * 0.12, color, 0.5, V(1, 0, 0))
		Kit.limb("Bolt", p1 - back * h * 0.12, tip, h * 0.15, h * 0.02, color, 0.5, V(1, 0, 0))
	end
end

-- A little dragon: a deep chest and slimmer hips on four strong legs with claws, a belly of pale plates, spines down
-- the back and tail; an S-curved neck with plates down its throat to a horned head with a long snout, nostrils on top,
-- a heavy brow and a jaw with two fangs; membrane wings on long fingers spread up and out; a long tapering tail
-- ending in a spade, a flame, a crystal or a bolt. The form picks the horns, spines, wings, tail tip and extras.
PLANS.drake = function(b, a, form)
	local f: Form = form or {}
	local k = f.k or 1
	local t = Kit.new("drake", f.h or 2.6, f.r or 1.4, "quad")
	local belly = f.belly or "cream"
	local hornC = f.hornC or "cream"
	local spC = f.spineC or a
	local claw = f.claw or "cream"
	J("body", nil, V(0, 0.84, 0), "body")
	local bc = V(0, 0.93, -0.12)
	local bl, bw, bt = 1.3 * k, (f.wide or 0.8) * k, 0.76 * k
	local _, body = A.body("Body", bc, V(0, 0.16, 1).Unit, bl, bw, bt, 0.6, b)
	A.patch("Belly", body, V(0, -1, 0.25), V(0.66, 0.86, 0.7), 0.02, belly)
	if full() then
		-- the belly's plates: pale bands across it
		for i = 1, 3 do
			local p, n = surf(body, V(0, -1, 0.7 - i * 0.38))
			Kit.ell("Plate", p + n * 0.01, V(bw * 0.5, 0.07, 0.09), A.shade(belly), faceTo(n, V(0, 0, 1)))
		end
	end
	-- spines down the back, biggest over the shoulders
	local sk = f.spines or "plate"
	local list = { { 0.42, 0.26 }, { 0.02, 0.28 }, { -0.4, 0.23 }, { -0.78, 0.17 } }
	for i, sp in list do
		local p = surf(body, V(0, 1, sp[1]))
		spine(sk, p - V(0, 0.04, 0), sp[2] * (f.spineK or 1) * k, spC, if i <= 2 then f.core else nil, i == 4 or i == 1)
	end
	-- legs: strong, the hind ones bending at the hock, clawed feet
	for _, l in { { n = "FL", s = -1, z = 0.34, ph = 0 }, { n = "FR", s = 1, z = 0.34, ph = 0.5 }, { n = "BL", s = -1, z = -0.5, ph = 0.5 }, { n = "BR", s = 1, z = -0.5, ph = 0 } } do
		local hind = l.z < 0
		local r = (if hind then 0.16 else 0.145) * k
		local hip = V(l.s * bw * 0.36, 0.72, l.z)
		if full() then
			A.leg(l.n, l.s, l.ph, hip, { kind = if hind then "hind" else "fore", r = r, c = b, foot = "none", fw = 0.26 * k, out = 0.04 })
		else
			-- (the islands' leg: a haunch on a hind leg, two limbs bending at the knee or the hock)
			J("leg" .. l.n, "body", hip, "leg", l.s, l.ph)
			local x = hip.X + l.s * 0.04
			local mid = if hind then V(x, 0.3, hip.Z - r * 0.6) else V(x, 0.4, hip.Z - r * 0.3)
			local low = V(x, 0.12, hip.Z + (if hind then -r * 0.2 else r * 0.1))
			if hind then
				Kit.ell(l.n .. "Haunch", hip + V(0, r * 0.2, -r * 0.1), V(r * 2.4, r * 3.8, r * 3.6), b, A.lie(V(0, 1, -0.35)))
			end
			Kit.limb("Leg" .. l.n, hip, mid, r, r * 0.75, b)
			Kit.limb("Leg" .. l.n, mid, low, r * 0.75, r * 0.7, b)
		end
		-- the foot: one rounded mass, three hooked claws at its front up close
		local g = V(hip.X + l.s * 0.04, 0, hip.Z + (if hind then -r * 0.1 else r * 0.1))
		local fw = 0.27 * k
		Kit.ell("Foot" .. l.n, g + V(0, fw * 0.26, fw * 0.12), V(fw, fw * 0.55, fw * 1.25), b)
		if full() then
			local xs: { number } = if hind then { -0.6, 0.6 } else { -1, 0, 1 }
			for _, x in xs do
				local c0 = g + V(x * fw * 0.3, fw * 0.16, fw * 0.66 - math.abs(x) * fw * 0.08)
				Kit.limb("Claw" .. l.n, c0, c0 + V(x * 0.03, -0.1, 0.08) * k, 0.04 * k, 0.012, claw)
			end
		end
	end
	-- the tail: long, tapering, a little curl up at the end, spines along it, then the tip
	local tb = bc + V(0, bt * 0.1, -bl * 0.46)
	J("tail1", "body", tb, "tail", 0, 1)
	local tm = tb + V(0, -0.34, -0.56) * k
	Kit.limbs("Tail", { tb, tb + V(0, -0.16, -0.3) * k, tm }, { 0.24 * k, 0.15 * k }, b, 2)
	J("tail2", "tail1", tm, "tail", 0, 2)
	-- (the end curls round toward its left, the side the camera sees)
	local te = tm + V(-0.16, -0.06, -0.42) * k
	local tt = te + V(-0.24, 0.12, -0.14) * k
	Kit.limbs("Tail", { tm, te, tt }, { 0.15 * k, 0.06 * k }, b, 2)
	spine(sk, tm + V(0, 0.12, -0.08) * k, 0.13 * k, spC, nil, true)
	local tk = f.tip or "spade"
	local td = (tt - te).Unit
	if tk == "spade" then
		local sz = (f.spade or 0.36) * k
		Kit.blade("Spade", tt - td * sz * 0.15, tt + td * sz, sz * 0.95, 0.06, UP, spC)
		Kit.blade("Spade", tt + td * sz * 0.2, tt - td * sz * 0.45, sz * 0.7, 0.06, UP, spC, true)
	elseif tk == "flame" then
		-- a flame at its end, a bright core inside
		Kit.egg("TailFlame", tt + V(0, 0.18, -0.06) * k, V(0.26, 0.42, 0.26) * k, 0.68, spC, A.lie(V(0, 1, -0.4)), nil, true)
		Kit.egg("TailFlame", tt + V(0, 0.14, -0.02) * k, V(0.14, 0.26, 0.14) * k, 0.66, f.core or "yellow", A.lie(V(0, 1, -0.4)), true, true)
	elseif tk == "crystal" then
		Kit.limb("TailShard", tt - td * 0.04, tt + td * 0.34 * k + V(0, 0.08, 0), 0.1 * k, 0.02, spC, 0.75, V(1, 0, 0))
		Kit.limb("TailShard", tt, tt + V(0, 0.3, -0.12) * k, 0.08 * k, 0.02, spC, 0.75, V(1, 0, 0))
		Kit.limb("TailShard", tt, tt + V(0, -0.2, -0.2) * k, 0.07 * k, 0.02, f.core or spC, 0.75, V(1, 0, 0), true)
	elseif tk == "bolt" then
		local p1 = tt + V(0, 0.18, -0.1) * k
		local p3 = p1 + V(0, 0.32, 0.02) * k
		Kit.limb("TailBolt", tt, p1 + V(0, 0, 0.05) * k, 0.09 * k, 0.07 * k, spC, 0.5, V(1, 0, 0), true)
		Kit.limb("TailBolt", if full() then p1 + V(0, 0, -0.04) * k else tt, p3 + V(0, 0, 0.06) * k, 0.075 * k, 0.015, spC, 0.5, V(1, 0, 0))
	end
	-- wings
	Kit.on("body")
	batWings(bc + V(0.28, 0.32, 0.08), { span = (f.span or 1.1) * k, lift = f.lift, sweep = f.sweep, fingers = f.fingers, c = b, mem = f.mem or a, claw = claw, edge = f.memEdge, tips = f.fingerTips })
	-- the neck: an S curve from the chest up to the head, plates down its throat
	local nb = bc + V(0, bt * 0.3, bl * 0.34)
	local n1 = nb + V(0, 0.3, 0.2) * k
	local nt = n1 + V(0, 0.34, 0.04) * k
	J("neck", "body", nb, "neck")
	Kit.limbs("Neck", { nb, n1, nt }, { 0.25 * k, 0.2 * k, 0.17 * k }, b, 2)
	for _, u in { 0.45 } do
		do
			local c0 = Kit.curveAt({ nb, n1, nt }, u)
			local tg = (Kit.curveAt({ nb, n1, nt }, math.min(1, u + 0.04)) - Kit.curveAt({ nb, n1, nt }, math.max(0, u - 0.04))).Unit
			local fr = V(1, 0, 0):Cross(tg).Unit
			Kit.ell("Throat", c0 + fr * (0.17 - u * 0.04) * k, V(0.24, 0.12, 0.1) * k, belly, faceTo(fr, tg), true)
		end
	end
	if f.neckSpine then
		local c0 = Kit.curveAt({ nb, n1, nt }, 0.4)
		spine(sk, c0 + V(0, 0.12, -0.14) * k, 0.15 * k, spC, nil, true)
	end
	-- the head
	local hc = nt + V(0, 0.18, 0.16) * k
	local hs = V(0.7, 0.62, 0.72) * k * (f.headK or 1)
	local h = A.head({
		c = hc,
		size = hs,
		color = b,
		parent = "neck",
		pivot = nt,
		muzzle = "lizard",
		mlen = 0.4 * k,
		mw = 0.4 * k,
		mh = 0.3 * k,
		mdrop = 0.1 * k,
		eye = { R(38), R(12), 0.28 * k },
		iris = A.iris(a, "yellow"),
		fangs = "white",
		blush = f.blush ~= false,
		tongue = "berry_red",
		-- (its own brow ridges)
		face = A.more(if f.brow == false then nil else { brows = false }, f.faceDetail),
	})
	Kit.on("head")
	-- the brow ridge over each eye
	local browSides: { number } = if f.brow == false then {} else { -1, 1 }
	for _, s in browSides do
		local p = Kit.onEll(hc, hs / 2, CFrame.identity, A.dir(s * 30, 46))
		local bC = f.browC or b
		Kit.limb("Brow", p + V(s * 0.12, 0.06, -0.08) * k, p + V(-s * 0.03, 0.01, 0.06) * k, 0.06 * k, 0.045 * k, bC, 0.6, UP, true)
	end
	-- horns
	local hk = f.horns or "swept"
	local function horn(base: Vector3, pts: { Vector3 }, r: number, c: string)
		local all = { base }
		for _, p in pts do
			table.insert(all, base + p * k)
		end
		Kit.limbs("Horn", all, { r * k, r * 0.6 * k, r * 0.12 * k }, c, if full() then #pts else 1)
	end
	for _, s in { -1, 1 } do
		local bd = V(s * 0.42, 0.9, -0.3).Unit
		local base = Kit.onEll(hc, hs / 2, CFrame.identity, bd) - bd * 0.04
		if hk == "swept" then
			horn(base, { V(s * 0.08, 0.2, -0.14), V(s * 0.14, 0.3, -0.38), V(s * 0.14, 0.32, -0.56) }, 0.08, hornC)
		elseif hk == "crown" then
			-- two great horns curving out, back and up
			horn(base, { V(s * 0.16, 0.2, -0.14), V(s * 0.32, 0.3, -0.36), V(s * 0.36, 0.52, -0.56) }, 0.11, hornC)
			-- and a short spike out from each cheek
			local b2 = Kit.onEll(hc, hs / 2, CFrame.identity, V(s * 0.9, -0.1, -0.3))
			Kit.limb("Horn", b2, b2 + V(s * 0.16, -0.02, -0.12) * k, 0.055 * k, 0.012, hornC, nil, nil, true)
		elseif hk == "icicle" then
			-- long, straight and sharp, raked back
			horn(base, { V(s * 0.12, 0.18, -0.16), V(s * 0.26, 0.3, -0.38), V(s * 0.36, 0.36, -0.56) }, 0.095, hornC)
		elseif hk == "zigzag" then
			-- a jag in each horn like a bolt
			local p1 = base + V(s * 0.06, 0.22, -0.1) * k
			local p2 = p1 + V(s * 0.06, 0.04, -0.18) * k
			local p3 = p2 + V(s * 0.04, 0.26, -0.12) * k
			if full() then
				Kit.limb("Horn", base, p1, 0.08 * k, 0.065 * k, hornC)
				Kit.limb("Horn", p1, p2, 0.065 * k, 0.055 * k, hornC)
				Kit.limb("Horn", p2, p3, 0.055 * k, 0.012, hornC)
			else
				Kit.limb("Horn", base, p3, 0.08 * k, 0.015, hornC)
			end
		end
	end
	if f.noseHorn then
		local p = h.nose + V(0, 0.08, -0.12) * k
		Kit.limb("NoseHorn", p, p + V(0, 0.16, 0.04) * k, 0.06 * k, 0.012, hornC)
	end
	if f.frill then
		-- a frill of icicles fanning back from behind the head
		local n = if full() then 4 else 2
		for i = 1, n do
			local u = (i - 1) / (n - 1)
			local a0 = R(-75 + u * 150)
			local d = V(math.sin(a0) * 0.8, math.cos(a0) * 0.5, -0.7).Unit
			local base = hc + V(math.sin(a0) * hs.X * 0.3, hs.Y * 0.1 + math.cos(a0) * hs.Y * 0.2, -hs.Z * 0.3)
			Kit.limb("Frill", base, base + d * (0.3 - math.abs(u - 0.5) * 0.12) * k, 0.06 * k, 0.012, f.frill, 0.7, V(0, 0, 1))
		end
	elseif f.fins ~= false then
		-- fins for ears, swept back from the sides of the head
		for _, s in { -1, 1 } do
			local base = hc + V(s * hs.X * 0.42, hs.Y * 0.06, -hs.Z * 0.12)
			J("ear" .. sideName(s), "head", base, "ear", s)
			Kit.limb("EarFin" .. sideName(s), base, base + V(s * 0.22, 0.1, -0.2) * k, 0.1 * k, 0.025, f.finC or a, 0.35, V(s * 0.5, 0.3, 0.6))
		end
		Kit.on("head")
	end
	if f.beard then
		-- spikes under the chin, a grumpy old dragon's beard
		for _, s in { -1, 1 } do
			local p = hc + V(s * 0.1, -hs.Y * 0.42, hs.Z * 0.16)
			Kit.limb("Beard", p, p + V(s * 0.06, -0.16, -0.06) * k, 0.05 * k, 0.012, f.beard, 0.7, V(0, 0, 1))
		end
	end
	return t
end

FORMS.pyredrake = { horns = "swept", hornC = "cream", spines = "flame", spineC = "orange", core = "yellow", tip = "flame", mem = "orange", belly = "cream", claw = "cream", finC = "orange", faceDetail = { marks = { freckles = "lava", glow = true } } }
FORMS.pyrelord = { horns = "crown", hornC = "berry_red", spines = "plate", spineC = "berry_red", tip = "spade", spade = 0.52, mem = "berry_red", belly = "cream", noseHorn = true, beard = "berry_red", span = 1.3, fingerTips = "cream", k = 1.1, h = 2.9, r = 1.5, wide = 0.88, spineK = 1.25, brow = false, fins = false, headK = 1.04 }
FORMS.frostdrake = { horns = "icicle", hornC = "ice", spines = "shard", spineC = "ice", core = "white", tip = "crystal", mem = "ice", memEdge = "white", belly = "white", frill = "ice", claw = "white", faceDetail = { marks = { freckles = "white", glow = true } } }
FORMS.thunderdrake = { horns = "zigzag", hornC = "yellow", spines = "bolt", spineC = "yellow", tip = "bolt", mem = "yellow", belly = "cream", claw = "yellow", finC = "yellow", lift = 1.15 }
-- Firstflame (ancient, 2026-11-20): a big old drake of black star stone with lava between its scales, a gold crown of
-- horns, a horn on its nose, flames down its back and at its tail, lava-red wings edged in gold.
FORMS.firstflame = { horns = "crown", hornC = "gold", spines = "flame", spineC = "lava", core = "yellow", tip = "flame", mem = "lava", memEdge = "gold", belly = "black", claw = "gold", fingerTips = "gold", noseHorn = true, span = 1.4, k = 1.14, h = 3.0, r = 1.5, wide = 0.9, spineK = 1.3, headK = 1.05, faceDetail = { marks = { freckles = "lava", glow = true } } }

local _v, _r, _j, _f, _u, _w = V, R, J, full, UP, FWD
return { plans = PLANS, forms = FORMS }
