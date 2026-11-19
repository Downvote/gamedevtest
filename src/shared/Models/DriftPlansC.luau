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
local lerp = A.lerp

type Form = { [string]: any }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

------------------------------------------------------------------ shared bits
-- (Data/Palette's "chalk" is a dark board green, so a chalk body takes a light ink like the other dark ones)
local function dark(c: string): boolean
	return A.isDark(c) or c == "chalk"
end

local function inkOf(b: string, a: string): string
	if dark(b) then
		return if dark(a) then "white" else a
	end
	return "black"
end

-- A unit direction leaning `out` degrees toward side `side` and `back` degrees back from straight up.
local function upLean(side: number, out: number, back: number): Vector3
	return V(side * math.sin(R(out)), math.cos(R(out)), -math.sin(R(back))).Unit
end

-- A frame whose local +Y is the surface normal `n` and local +Z lies along the surface toward `along`: a plate, a scute
-- or a spot laid flat on a body (its size's Y is its thickness).
local function flatOn(n: Vector3, along: Vector3?): CFrame
	return A.lie(n, along or FWD)
end

-- A tiny shine (a highlight on a gem, a pearl or a crystal: the full thing only), lit on its own.
local function shine(name: string, at: Vector3, d: number)
	local p = Kit.ell(name, at, V(d, d, d), "white", nil, true)
	if p then
		p:SetAttribute("PixelOwn", true)
	end
end

------------------------------------------------------------------ the bun (rabbits and hares)
-- A rabbit sitting up: an egg of a body leaning forward with its round end low at the back, big haunches folded along
-- its sides on long flat hind feet, small straight forelegs down to little paws in front, a puff of a tail, a big
-- round head with whisker pads, a pink nose, buck teeth and long ears (pale insides). A hare stands taller on longer
-- legs. Forms: ears (`ear` "up" | "bent" | "half" | "lop" | "crystal", `elen`, `ew`, `splay`, `etip`, `einner`,
-- `moss`), `hare`, `wide`, `under`, `feet`, `cheeks`, `ruff`, `tailc`, `sprout`, `gem`, `star`, `sparkles`, `h`.
type EarO = { kind: string, len: number, w: number, c: string, inner: string?, tip: string?, splay: number, back: number, moss: string? }

local function bunEar(h: A.Head, side: number, o: EarO)
	local s = if side < 0 then "L" else "R"
	local kind = o.kind
	-- the base high on the cranium, a little apart from the other
	local at = if kind == "lop" then 34 else 20
	local baseDir = (CFrame.Angles(0, 0, -side * R(at)) * CFrame.Angles(R(-8), 0, 0)):VectorToWorldSpace(UP)
	local base = Kit.onEll(h.c, h.half, CFrame.identity, baseDir) - baseDir * o.w * 0.25
	J("ear" .. s, "head", base, "ear", side)
	local L, w = o.len, o.w
	local flat = 0.42
	local face = (FWD + V(side * 0.3, 0, 0)).Unit
	local pts: { Vector3 }
	local radii: { number }
	if kind == "lop" then
		-- folded over at the crown and hanging close down the side of the head to the cheek
		local hx, hy = h.half.X, h.half.Y
		pts = { base, h.c + V(side * hx * 0.84, hy * 0.7, -0.02), h.c + V(side * (hx + w * 0.22), -hy * 0.1, 0.04), h.c + V(side * (hx + w * 0.14), -hy * 1.0, 0.12) }
		radii = { w * 0.36, w * 0.5, w * 0.56 }
		face = V(side, 0.1, 0.25).Unit
	elseif kind == "crystal" then
		-- two crystals for an ear: a tall shard and a short one leaning out of its foot
		local up = upLean(side, o.splay, o.back)
		local tip = base + up * L
		Kit.limb("Ear" .. s, base, tip, w * 0.5, w * 0.08, o.c, 0.8, face)
		local up2 = upLean(side, o.splay + 26, o.back - 8)
		Kit.limb("Ear" .. s, base + up * L * 0.08, base + up2 * L * 0.5, w * 0.34, w * 0.06, o.c, 0.8, face)
		if o.inner then
			-- the light inside the crystal: a paler core up its front face
			Kit.limb("EarIn" .. s, base + up * L * 0.16 + face * w * 0.2, base + up * L * 0.7 + face * w * 0.16, w * 0.2, w * 0.05, o.inner, 0.5, face, true)
		end
		shine("EarShine" .. s, base + up * L * 0.45 + face * w * 0.3 - V(side * w * 0.12, 0, 0), 0.06)
		return
	else
		local up = upLean(side, o.splay, o.back)
		local mid = base + up * L * 0.5
		local up2 = (up + V(0, 0, -0.12)).Unit
		if kind == "bent" then
			-- soft: the top third droops back and out
			up2 = (up + V(side * 0.4, -0.12, -0.55)).Unit
			pts = { base, mid, mid + up * L * 0.16, mid + up * L * 0.16 + up2 * L * 0.32 }
			radii = { w * 0.46, w * 0.56, w * 0.52, w * 0.34 }
		elseif kind == "half" and side < 0 then
			-- one ear stands, the other folds over halfway
			up2 = V(side * 0.7, -0.2, 0.5).Unit
			pts = { base, mid + up * L * 0.1, mid + up * L * 0.1 + up2 * L * 0.38 }
			radii = { w * 0.48, w * 0.55, w * 0.32 }
		else
			pts = { base, mid, mid + up2 * L * 0.5 }
			radii = { w * 0.48, w * 0.56, w * 0.3 }
		end
	end
	Kit.limbs("Ear" .. s, pts, radii, o.c, #pts - 1, flat, face)
	-- the pale inside on the front of the lower part, set out past the ear's front
	if o.inner and kind ~= "lop" then
		local a0, a1 = pts[1], pts[2]
		local b1 = if #pts >= 3 then lerp(pts[2], pts[3], 0.6) else pts[2]
		local th = w * 0.56 * flat * 0.5
		local off = face * (th - w * 0.3 * 0.3 * 0.5 + 0.04)
		Kit.limb("EarIn" .. s, a0 + (a1 - a0) * 0.18 + off, a1 + off, w * 0.26, w * 0.3, o.inner, 0.3, face)
		Kit.limb("EarIn" .. s, a1 + off, b1 + off, w * 0.3, w * 0.16, o.inner, 0.3, face, true)
	elseif o.inner and kind == "lop" then
		-- (a lop's inside shows a little at the fold)
		Kit.limb("EarIn" .. s, lerp(pts[2], pts[3], 0.2) + face * w * 0.18, lerp(pts[3], pts[4], 0.5) + face * w * 0.18, w * 0.3, w * 0.22, o.inner, 0.3, face, true)
	end
	if o.tip then
		-- (a tip of another colour: a sleeve over the ear's end, clear of its surface all round)
		local n = #pts
		local r0 = radii[#radii]
		local r1 = (radii[#radii] + (radii[#radii - 1] or r0)) * 0.5
		local rt0, rt1 = r1 + 0.04, r0 + 0.035
		Kit.limb("EarTip" .. s, lerp(pts[n - 1], pts[n], 0.5), pts[n] + (pts[n] - pts[n - 1]).Unit * 0.02, rt0, rt1, o.tip, (r1 * flat + 0.035) / rt0, face)
	end
	if o.moss and full() then
		-- soft lumps of moss up the back of the ear
		for i, u in { 0.25, 0.55, 0.8 } do
			local n = #pts
			local p = Kit.curveAt(pts, u)
			local k = math.clamp(math.floor(u * (n - 1)) + 1, 1, n - 1)
			local along = (pts[k + 1] - pts[k]).Unit
			local back = -face - along * (-face):Dot(along)
			Kit.ell("Moss" .. s, p + back.Unit * w * 0.14 + V(side * w * 0.12, 0, 0), V(w * 0.5, w * 0.44, w * 0.4) * (1 - i * 0.12), o.moss)
		end
	end
end

PLANS.bun = function(b, a, form)
	local f: Form = form or {}
	local hare = f.hare == true
	local lift = if hare then 0.14 else 0
	local t = Kit.new("bun", f.h or 2.4, 0.9, "hop")
	local under = f.under or A.under(b)
	local feet = f.feet or under
	local ink = f.ink or inkOf(b, a)
	local wide = f.wide or 0.94
	J("body", nil, V(0, 0.6 + lift, 0), "body")
	-- the body: a round egg leaning forward, its fat end low at the back, the chest high at the front
	local bd = (if hare then V(0, 0.6, 0.8) else V(0, 0.72, 0.7)).Unit
	local _, body = A.body("Body", V(0, 0.54 + lift, -0.08), bd, if hare then 1.12 else 1.02, wide, if hare then 0.78 else 0.9, 0.42, b)
	A.patch("Belly", body, V(0, -0.1, 1), V(0.74, 0.86, 0.72), 0.02, under)
	if f.ruff then
		-- a fluffy ruff round the front of the neck
		for i, x in { -0.22, 0, 0.22 } do
			Kit.ell("Ruff", V(x, 0.86 + lift - math.abs(x) * 0.35, 0.36 - math.abs(x) * 0.3), V(0.36, 0.32, 0.32) * (if i == 2 then 1.15 else 1), f.ruff)
		end
	end
	-- the forelegs: short and straight down from the chest to little paws on the ground in front
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local sh = V(side * 0.2, 0.62 + lift, 0.3)
		J("arm" .. s, "body", sh, "arm", side)
		local paw = V(side * 0.18, 0, if hare then 0.52 else 0.46)
		Kit.limb("Arm" .. s, sh, paw + UP * 0.1, 0.11, 0.085, b)
		A.paw("Hand" .. s, paw, 0.19, feet, FWD, nil, 3)
	end
	-- the hind legs: a big round haunch folded along the side, the long flat foot under it, heel at the back
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local hip = V(side * 0.32, 0.4 + lift, -0.18)
		J("leg" .. s, "body", hip, "leg", side, 0)
		local hc = V(side * 0.37, 0.36 + lift * 0.8, -0.14)
		Kit.ell("Haunch" .. s, hc, V(0.42, 0.64, 0.82), b, A.lie(V(0, 0.45, 1)))
		local heel = V(side * 0.37, 0.09, -0.42)
		local toe = V(side * 0.39, 0.08, if hare then 0.36 else 0.3)
		if hare then
			-- (a hare's shin shows between the haunch and the heel)
			Kit.limb("Shin" .. s, hc + V(0, -0.1, -0.22), heel + UP * 0.04, 0.12, 0.1, b)
		end
		Kit.limb("Foot" .. s, heel, toe, 0.11, 0.095, feet, 0.6, UP)
		if full() then
			for i = -1, 1 do
				Kit.ell("Toe" .. s, toe + V(i * 0.065, -0.01, 0.06 - math.abs(i) * 0.03), V(0.085, 0.085, 0.1), feet)
			end
		end
	end
	-- the tail: a round puff
	A.tail(V(0, 0.4 + lift, -0.54), { kind = "puff", r = f.tailr or 0.16, c = b, tip = f.tailc or under })
	-- the head: big and round, the head of a young one
	local hc = V(0, 1.22 + lift, 0.3)
	local hs = V(1.0, 0.88, 0.88)
	local mw = 0.4
	local h = A.head({
		c = hc,
		size = hs,
		color = b,
		pivot = V(0, 0.92 + lift, 0.2),
		muzzle = "cat",
		mlen = 0.16,
		mw = mw,
		mc = f.muzzle or under,
		nose = f.nose or "pink",
		cheeks = f.cheeks,
		eye = { R(33), R(6), 0.3 },
		iris = A.iris(a, "blue"),
		blush = true,
		ink = ink,
		whiskers = false,
		face = A.more(if f.gem then { crown = false } else nil, f.faceDetail),
	})
	-- buck teeth under the nose
	if full() then
		local root = hc + V(0, -hs.Y * 0.16, hs.Z * 0.5 * 0.55)
		local pr = mw * 0.34
		local m = root + V(0, -pr * 0.55, 0.16 * 0.45 + pr * 0.85)
		for _, side in { -1, 1 } do
			Kit.ell("Tooth", m + V(side * 0.03, -0.075, -0.01), V(0.055, 0.085, 0.045), "white")
		end
	end
	if f.star then
		-- a star for a nose: five lit points round a lit middle
		local n0 = h.nose + V(0, 0.01, 0.03)
		Kit.ell("Star", n0, V(0.1, 0.1, 0.07), f.star, nil, nil, true)
		for i = 0, 4 do
			local ang = i / 5 * math.pi * 2
			local d = V(math.sin(ang), math.cos(ang), 0)
			Kit.limb("Star", n0 + d * 0.03, n0 + d * 0.13 + FWD * 0.01, 0.04, 0.012, f.star, 0.6, FWD, true, true)
		end
	end
	if f.gem then
		-- a crystal growing out of the brow
		local g0 = Kit.onEll(hc, h.half, CFrame.identity, V(0, 0.75, 0.66))
		Kit.limb("Gem", g0 - V(0, 0.04, 0.02), g0 + V(0, 0.18, 0.05), 0.08, 0.015, f.gem, 0.8, FWD)
		shine("GemShine", g0 + V(-0.025, 0.06, 0.07), 0.05)
	end
	if f.sprout then
		-- a sprout between the ears
		local s0 = Kit.onEll(hc, h.half, CFrame.identity, V(0, 1, 0.12))
		Kit.limb("Sprout", s0 - UP * 0.04, s0 + V(0.02, 0.2, 0.02), 0.035, 0.025, "leaf_dark")
		Kit.limb("SproutLeaf", s0 + V(0.02, 0.18, 0.02), s0 + V(0.2, 0.3, 0.06), 0.06, 0.025, f.sprout, 0.35, V(0, 1, 0.3))
		Kit.limb("SproutLeaf", s0 + V(0.02, 0.17, 0.02), s0 + V(-0.16, 0.27, 0.04), 0.05, 0.02, f.sprout, 0.35, V(0, 1, 0.3), true)
	end
	-- the ears
	for _, side in { -1, 1 } do
		bunEar(h, side, {
			kind = f.ear or "up",
			len = f.elen or 0.82,
			w = f.ew or 0.3,
			c = f.ec or b,
			inner = f.einner or "pink",
			tip = f.etip,
			splay = f.splay or 8,
			back = f.eback or 10,
			moss = f.moss,
		})
	end
	Kit.on("body")
	if f.sparkles and full() then
		-- little lit specks in its fur
		for _, p in { V(-0.42, 0.72, -0.1), V(0.34, 0.5, -0.36), V(-0.22, 0.42, -0.48), V(0.42, 0.8, 0.0) } do
			Kit.ell("Speck", p + V(0, lift, 0), V(0.06, 0.06, 0.06), f.sparkles, nil, nil, true)
		end
	end
	return t
end

FORMS.mossbun = { ear = "bent", ec = "moss", ew = 0.36, elen = 0.86, etip = "leaf_dark", einner = "leaf", under = "cream", sprout = "leaf" }
FORMS.cloudbun = { ear = "up", elen = 0.6, ew = 0.32, splay = 22, einner = "window", etip = "window", cheeks = "white", ruff = "white", wide = 0.94, tailr = 0.2, under = "white" }
FORMS.duskbun = { ear = "lop", ew = 0.34, einner = "crystal", etip = "crystal", under = "steel", gem = "crystal", wide = 0.9 }
FORMS.amethare = { ear = "crystal", elen = 0.86, ew = 0.24, splay = 16, eback = 6, ec = "crystal", einner = "white", hare = true, under = "white", wide = 0.78 }
FORMS.windhare = { ear = "up", elen = 1.04, ew = 0.26, splay = 4, eback = 22, etip = "black", hare = true, under = "white", wide = 0.76, h = 2.6 }
FORMS.twinkbun = { ear = "half", einner = "night", etip = "yellow", star = "yellow", sparkles = "yellow", under = "slate", nose = "yellow" }

------------------------------------------------------------------ the mole
-- A mole: a fat velvet pear of a body low on the ground with no neck to speak of, the head running on into a long
-- pointed pink snout, tiny eyes, huge spade hands turned out to the sides (broad pink palms, long claws), small pink
-- hind feet and a short pink tail. Forms: `under`, `claw` (and `hot` to light them), `tuft` (a cowlick), `crust` (rock
-- plates on its back with lit cracks between them, `glow` their colour), `craters` (lit pits on its back), `star` (the
-- ring of fleshy rays round the nose), `snout`, `nose`, `big`.

-- A thin seam over a mass's surface through the directions `dirs` from its centre (a crack, a parting in the fur).
local function seam(name: string, m: A.Mass, dirs: { Vector3 }, r: number, color: string, neon: boolean?, detail: boolean?)
	local pts: { Vector3 } = {}
	for _, d in dirs do
		table.insert(pts, A.on(m, d) + d.Unit * 0.01)
	end
	for i = 1, #pts - 1 do
		Kit.limb(name, pts[i], pts[i + 1], r, r, color, nil, nil, detail, neon)
	end
end

PLANS.mole = function(b, a, form)
	local f: Form = form or {}
	local k = f.big or 1
	local t = Kit.new("mole", 1.6 * k, 1.1, "quad")
	local under = f.under or A.under(b)
	local skin = f.snout or "pink"
	local claw = f.claw or "cream"
	local hot = f.hot == true
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	J("body", nil, P(0, 0.55, 0), "body")
	-- the body: a pear lying low, its fat round end at the back
	local _, body = A.body("Body", P(0, 0.48, -0.28), V(0, 0.12, 1).Unit, 1.3 * k, 1.02 * k, 0.88 * k, 0.42, b)
	A.patch("Belly", body, V(0, -1, 0.3), V(0.8, 0.82, 0.8), 0.02, under)
	if f.crust then
		-- plates of cooled rock over its back, the fire showing in the cracks between them
		for i, p in { { 0, 0.92, -0.3, 0.56, 0.46, 18 }, { -0.28, 0.82, 0.05, 0.46, 0.4, -24 }, { 0.3, 0.84, 0.0, 0.44, 0.38, 28 }, { 0.02, 0.84, -0.66, 0.46, 0.34, 8 } } do
			local d = (P(p[1], p[2], p[3]) - body.c).Unit
			local at = A.on(body, d) - d * 0.06 * k
			local rot = flatOn(d, (CFrame.Angles(0, R(p[6]), 0)):VectorToWorldSpace(FWD))
			Kit.ell("Crust", at, V(p[4], 0.16, p[5]) * k, f.crust, rot, i == 4)
		end
		local g = f.glow or a
		seam("Crack", body, { V(-0.1, 1, -0.05), V(0.05, 1, 0.25), V(-0.05, 0.8, 0.5) }, 0.03 * k, g, true)
		seam("Crack", body, { V(-0.6, 0.8, -0.2), V(-0.35, 1, 0.05), V(-0.1, 1, -0.05), V(0.3, 1, 0.0), V(0.62, 0.8, -0.15) }, 0.03 * k, g, true)
		seam("Crack", body, { V(-0.3, 0.9, -0.55), V(0, 1, -0.4), V(0.32, 0.9, -0.55) }, 0.03 * k, g, true, true)
	end
	if f.craters then
		-- pits in its back, each with a lit speck at the bottom
		for i, p in { { 0.1, 1, -0.2, 0.3 }, { -0.42, 0.85, 0.1, 0.22 }, { 0.45, 0.8, -0.45, 0.24 }, { -0.25, 0.9, -0.6, 0.18 }, { 0.3, 0.95, 0.3, 0.16 } } do
			local d = V(p[1], p[2], p[3]).Unit
			local at = A.on(body, d)
			local rot = flatOn(d)
			local dd = p[4] * k
			if i <= 2 or full() then
				Kit.ell("Crater", at - d * 0.03, V(dd, 0.1, dd), f.craters, rot)
				Kit.ell("CraterGlow", at + d * 0.02, V(dd * 0.45, 0.08, dd * 0.45), f.glow or a, rot, nil, true)
			end
		end
	end
	-- the head: big and round on the front of the body, the long snout pointing on forward and a little up
	local hc = P(0, 0.8, 0.62)
	local hs = V(0.88, 0.78, 0.76) * k
	local ink = inkOf(b, a)
	local h = A.head({
		c = hc,
		size = hs,
		color = b,
		pivot = P(0, 0.6, 0.32),
		muzzle = "none",
		mlen = 0.24 * k,
		mw = 0.3 * k,
		mdrop = 0.16 * k,
		mc = b,
		eye = { R(32), R(10), 0.21 * k },
		iris = A.iris(a, "gold"),
		ink = ink,
		blush = true,
		faceLater = true,
	})
	local root = hc + V(0, -0.14 * k, hs.Z * 0.36)
	local tipP = root + V(0, 0.03, 0.4) * k
	Kit.limb("Snout", root, tipP, 0.16 * k, 0.075 * k, skin, 0.85, UP)
	if full() then
		-- wrinkles across the snout
		for _, u in { 0.35, 0.6 } do
			local c0 = lerp(root, tipP, u)
			local r0 = (0.16 + (0.075 - 0.16) * u) * k
			Kit.limb("Wrinkle", c0 - FWD * 0.012, c0 + FWD * 0.012, r0 + 0.03, r0 + 0.03, f.wrinkle or "coral", 0.85, UP)
		end
	end
	local nose = tipP + FWD * 0.06 * k
	Kit.ell("Nose", nose, V(0.15, 0.12, 0.1) * k, f.nose or "coral")
	if full() then
		for _, side in { -1, 1 } do
			Kit.ell("Nostril", nose + V(side * 0.03, 0.0, 0.05) * k, V(0.04, 0.05, 0.03), "black")
		end
	end
	Kit.mouth(root + V(0, -0.14, 0.1) * k, V(0, -0.45, 1), 0.15 * k, ink)
	-- the face's details (A.face): whisker dots along the snout
	A.face({
		color = b,
		c = hc,
		half = h.half,
		ink = ink,
		muzzle = "snout",
		snout = { a = root, b = tipP, ra = 0.16 * k, rb = 0.075 * k, flat = 0.85 },
		padC = A.markC(skin),
		more = A.more(if f.tuft then { crown = false } else nil, f.faceDetail),
	})
	if f.star then
		-- the star: a ring of fleshy rays round the end of the nose
		local cnt = if full() then 10 else 5
		for i = 0, cnt - 1 do
			local ang = i / cnt * math.pi * 2 + 0.3
			local d = V(math.cos(ang), math.sin(ang), 0.35).Unit
			Kit.limb("StarRay", nose + d * 0.05 * k, nose + d * 0.19 * k, 0.045 * k, 0.03 * k, f.star)
		end
	end
	if f.tuft then
		-- a cowlick of fur on top
		local top = Kit.onEll(hc, h.half, CFrame.identity, V(0, 1, -0.2))
		for i, d in { V(-0.2, 1, 0.4), V(0.05, 1, 0.1), V(0.3, 0.9, -0.2) } do
			Kit.limb("Tuft", top - UP * 0.04, top + d.Unit * (0.16 - i * 0.02) * k, 0.06 * k, 0.015, b, 0.6, FWD)
		end
	end
	-- the spade hands: a short thick arm, the broad palm turned out to the side, long claws along its front edge
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", P(side * 0.38, 0.42, 0.36), "arm", side)
		local sh = P(side * 0.34, 0.45, 0.34)
		local wr = P(side * 0.58, 0.26, 0.6)
		Kit.limb("Arm" .. s, sh, wr, 0.17 * k, 0.14 * k, b)
		local n = V(side * 0.85, 0.2, 0.5).Unit
		local pc = P(side * 0.68, 0.22, 0.74)
		Kit.ell("Palm" .. s, pc, V(0.46, 0.12, 0.42) * k, skin, A.lie(n, UP))
		local pf = (FWD - n * FWD:Dot(n)).Unit
		local pu = n:Cross(pf).Unit * side
		local fan: { number } = if full() then { -1, -0.5, 0, 0.5, 1 } else { -0.8, 0, 0.8 }
		for _, u in fan do
			local base = pc + pf * 0.16 * k + pu * u * 0.15 * k
			local tip = base + (pf * 0.22 - UP * 0.08 + n * 0.02 + pu * u * 0.04) * k
			Kit.limb("Claw" .. s, base, tip, 0.05 * k, 0.014 * k, claw, 0.7, n, nil, hot)
		end
		-- the small hind feet under the back end
		J("leg" .. s, "body", P(side * 0.34, 0.3, -0.56), "leg", side, if side < 0 then 0.5 else 0)
		local heel = P(side * 0.36, 0.07, -0.68)
		local toe = P(side * 0.4, 0.06, -0.44)
		Kit.limb("Leg" .. s, P(side * 0.34, 0.3, -0.56), heel + UP * 0.06, 0.14 * k, 0.1 * k, b)
		Kit.limb("Foot" .. s, heel, toe, 0.09 * k, 0.085 * k, skin, 0.6, UP)
		if full() then
			for i = -1, 1 do
				local c0 = toe + V(i * 0.05, 0, 0.04) * k
				Kit.limb("FootClaw" .. s, c0, c0 + V(i * 0.02, -0.02, 0.08) * k, 0.025 * k, 0.01, claw, nil, nil, nil, hot)
			end
		end
	end
	-- the short tail
	J("tail1", "body", P(0, 0.42, -0.8), "tail", 0, 1)
	Kit.limb("Tail", P(0, 0.42, -0.78), P(0, 0.54, -1.04), 0.07 * k, 0.035 * k, f.tailc or skin)
	return t
end

FORMS.mudmole = { under = "sand", tuft = true }
FORMS.magmole = { under = "basalt", crust = "rock_dark", glow = "orange", claw = "orange", hot = true, snout = "clay", nose = "orange", tailc = "clay" }
FORMS.cratermole = { under = "slate", craters = "black", glow = "screen_on", star = "pink", claw = "steel", big = 1.14 }

------------------------------------------------------------------ the hedgehog
-- A hedgehog: a round low body with a pale belly, a coat of spines over its back and sides that starts in a hood over
-- the brow, a pointed face with a little nose, small round ears, tiny legs. The spines are short tapered cones in rings
-- round the body, swept back. Forms: `face`, `spine` (and `mantle` under them), `tip` (pale or lit tips, `hot` to
-- light them), `quill` "spine" | "crystal" | "flame", `apple`, `h`.
PLANS.hedgehog = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("hedgehog", f.h or 1.45, 1.0, "quad")
	local face = f.face or b
	local spine = f.spine or a
	local quill = f.quill or "spine"
	local ink = f.ink or inkOf(face, a)
	J("body", nil, V(0, 0.44, 0), "body")
	-- the body: a round low loaf, the pale belly under it
	local _, body = A.blob("Body", V(0, 0.46, -0.06), V(1.08, 0.8, 1.2), b)
	A.patch("Belly", body, V(0, -1, 0.4), 0.82, 0.02, face)
	-- the coat: a mantle over the back and sides with the spines standing out of it
	local mc = V(0, 0.54, -0.16)
	local mh = V(0.6, 0.46, 0.66)
	Kit.ell("Mantle", mc, mh * 2, f.mantle or spine)
	local rings: { { number } }
	if full() then
		rings = { { 38, 60, 5 }, { 66, 96, 7 }, { 96, 112, 8 }, { 126, 104, 7 }, { 154, 80, 5 } }
	else
		rings = { { 46, 60, 3 }, { 88, 100, 5 }, { 136, 90, 4 } }
	end
	if quill == "flame" and full() then
		rings = { { 40, 60, 4 }, { 70, 96, 6 }, { 102, 110, 7 }, { 134, 100, 6 }, { 160, 70, 3 } }
	elseif quill == "crystal" then
		rings = if full() then { { 44, 60, 3 }, { 80, 100, 5 }, { 118, 100, 5 }, { 152, 70, 3 } } else { { 56, 60, 3 }, { 104, 96, 4 }, { 150, 60, 2 } }
	end
	local L0 = (f.len or 0.34) * (if full() then 1 else 1.2)
	local r0 = if full() then 0.075 else 0.1
	for ri, ring in rings do
		local phi, spread, n = R(ring[1]), ring[2], ring[3]
		for i = 1, n do
			local psi = if n == 1 then 0 else R(-spread + 2 * spread * (i - 1) / (n - 1))
			-- (staggered: every other ring turned half a step)
			if ri % 2 == 0 and n > 1 then
				psi += R(spread / (n - 1)) * 0.5 * (if i % 2 == 0 then 1 else -1)
			end
			local d = V(math.sin(phi) * math.sin(psi), math.sin(phi) * math.cos(psi), math.cos(phi))
			local base, nrm = Kit.onEll(mc, mh, CFrame.identity, d)
			if quill == "crystal" then
				-- a crystal: a thick shard pointing out and up, a pale core up close
				local dir = (nrm + V(0, 0.55, -0.35)).Unit
				local L = (if full() then 0.42 else 0.5) * (1 + 0.25 * math.cos(psi)) * (if i % 2 == 0 then 0.85 else 1)
				local col = if (i + ri) % 3 == 0 then (f.tip or spine) else spine
				Kit.limb("Quill", base - nrm * 0.05, base + dir * L, 0.11, 0.03, col, 0.85, nrm:Cross(dir))
				if full() and (i + ri) % 2 == 0 then
					shine("QuillShine", base + dir * L * 0.45 + nrm * 0.06, 0.05)
				end
			else
				local dir = (nrm + V(0, 0.1, -0.95)).Unit
				local L = L0 * (if quill == "flame" then (1 + 0.6 * math.cos(psi) * math.sin(phi)) else 1) * (if (i + ri) % 2 == 0 then 0.9 else 1)
				local tip = base + dir * L
				local lit = f.hot and not full() and (i + ri) % 2 == 0
				Kit.limb("Quill", base - nrm * 0.04, tip, r0, 0.018, if lit then f.tip else spine, nil, nil, nil, lit)
				if f.tip and full() and (quill == "flame" or (i + ri) % 2 == 0) then
					-- (a sleeve over the spine's end, clear of it all round)
					local u = 0.58
					Kit.limb("QuillTip", lerp(base, tip, u), tip + dir * 0.03, r0 + (0.018 - r0) * u + 0.03, 0.04, f.tip, nil, nil, nil, f.hot)
				end
			end
		end
	end
	if f.apple then
		-- an apple stuck on its spines
		local ap = Kit.onEll(mc, mh, CFrame.identity, V(-0.45, 0.85, -0.2)) + V(0, 0.08, 0)
		Kit.ell("Apple", ap, V(0.36, 0.32, 0.36), f.apple)
		Kit.limb("AppleStem", ap + V(0, 0.12, 0), ap + V(0.02, 0.23, 0.01), 0.025, 0.02, "wood_dark", nil, nil, true)
		Kit.limb("AppleLeaf", ap + V(0.02, 0.2, 0.01), ap + V(0.15, 0.26, 0.04), 0.05, 0.015, "leaf", 0.35, V(0, 1, 0.3))
		shine("AppleShine", ap + V(-0.08, 0.07, 0.11), 0.07)
	end
	-- the legs: short, the paws peeking out under the body
	for _, l in { { n = "FL", s = -1, z = 0.3, ph = 0 }, { n = "FR", s = 1, z = 0.3, ph = 0.5 }, { n = "BL", s = -1, z = -0.4, ph = 0.5 }, { n = "BR", s = 1, z = -0.4, ph = 0 } } do
		local hip = V(l.s * 0.3, 0.26, l.z)
		J("leg" .. l.n, "body", hip, "leg", l.s, l.ph)
		local foot = V(l.s * 0.34, 0, l.z + 0.04)
		Kit.limb("Leg" .. l.n, hip, foot + UP * 0.08, 0.1, 0.08, face)
		Kit.ell("Paw" .. l.n, foot + V(0, 0.05, 0.05), V(0.16, 0.1, 0.2), face)
		if full() then
			A.claws("Claw" .. l.n, foot + V(0, 0.03, 0.14), 0.14, 0.06, "black", FWD, 3)
		end
	end
	-- a stub of a tail
	J("tail1", "body", V(0, 0.32, -0.68), "tail", 0, 1)
	Kit.ell("Tail", V(0, 0.32, -0.72), V(0.14, 0.12, 0.16), face)
	-- the head: a pointed face under the hood of spines
	local h = A.head({
		c = V(0, 0.52, 0.5),
		size = V(0.66, 0.58, 0.6),
		color = face,
		pivot = V(0, 0.42, 0.26),
		muzzle = "fox",
		mlen = 0.32,
		mw = 0.26,
		mdrop = 0.06,
		mc = f.muzzle or face,
		nose = ink,
		eye = { R(34), R(12), 0.2 },
		iris = A.iris(a, "gold"),
		ink = ink,
		blush = true,
		face = A.more(nil, f.faceDetail),
	})
	A.ears(h, { kind = "round", w = 0.17, at = 0.5, back = 20, c = face, inner = f.inner or "pink" })
	return t
end

FORMS.quartzle = { quill = "crystal", spine = "purple", tip = "crystal", mantle = "purple", inner = "crystal" }
FORMS.burrowby = { face = "cream", spine = "wood_dark", tip = "cream", mantle = "wood_dark", apple = "berry_red", muzzle = "cream", len = 0.27 }
FORMS.emberquill = { quill = "flame", spine = "basalt", mantle = "basalt", tip = "orange", hot = true, face = "rock_dark", faceDetail = { marks = { freckles = "lava", glow = true } } }

------------------------------------------------------------------ the armadillo
-- An armadillo: a soft body under a shell of plates (a front shield, bands across the middle that ride over each
-- other, a rear shield), a small pointed head with a plate on top and tall ears, short legs with big front claws, a
-- tapering tail in rings of armour. Forms: `skin`, `plate`, `seam`, `bands`, `round` (a rounder, pebble shell),
-- `tail` (its length), `moss` (and `sprout`), `shine`, `flecks`, `ear`, `h`.
PLANS.armadillo = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("armadillo", f.h or 1.5, 1.0, "quad")
	local skin = f.skin or a
	local plate = f.plate or b
	local seamC = f.seam or A.shade(plate)
	local ink = f.ink or inkOf(skin, a)
	local round = f.round == true
	J("body", nil, V(0, 0.5, 0), "body")
	-- the soft body under the shell
	A.body("Body", V(0, 0.44, -0.04), FWD, 1.24, 0.78, 0.62, 0.5, skin)
	-- the shell: a dark under-shell, the front and rear shields, the bands between
	local cc = V(0, 0.58, -0.08)
	local ch = if round then V(0.56, 0.48, 0.66) else V(0.5, 0.42, 0.74)
	Kit.ell("ShellUnder", cc, ch * 2 * 0.95, seamC)
	local zs = ch.Z * 0.56
	Kit.ell("ShieldF", cc + V(0, 0.0, zs), V(ch.X * 2.04, ch.Y * 2.02, ch.Z * 0.96), plate)
	Kit.ell("ShieldB", cc + V(0, 0.0, -zs), V(ch.X * 2.04, ch.Y * 2.02, ch.Z * 0.96), plate)
	local nb = f.bands or 5
	local span = ch.Z * 0.96
	for i = 1, nb do
		local z = cc.Z + span * 0.5 - span * (i - 0.5) / nb
		local q = math.sqrt(math.max(0.1, 1 - ((z - cc.Z) / ch.Z) ^ 2))
		local th = span / nb * 1.15
		Kit.ell("Band", V(0, cc.Y + 0.01, z), V(ch.X * 2 * q * 1.1, ch.Y * 2 * q * 1.1, th), plate, CFrame.Angles(R(-6), 0, 0))
	end
	if f.shine and full() then
		-- shine on the plates, and little flecks of fire in them
		for _, p in { V(-0.2, 0.95, 0.35), V(-0.1, 1, -0.1), V(0.15, 0.95, -0.45) } do
			shine("PlateShine", A.on({ c = cc, size = ch * 2.1, rot = CFrame.identity, split = 0.5 }, p) + V(0, 0.01, 0), 0.07)
		end
	end
	if f.flecks and full() then
		for i, p in { V(0.35, 0.85, 0.3), V(-0.42, 0.7, -0.15), V(0.3, 0.9, -0.3), V(-0.15, 0.95, 0.5), V(0.5, 0.6, 0.05) } do
			local col = f.flecks[(i - 1) % #f.flecks + 1]
			local d = p.Unit
			local at = A.on({ c = cc, size = ch * 2.12, rot = CFrame.identity, split = 0.5 }, d)
			Kit.ell("Fleck", at, V(0.08, 0.03, 0.08), col, flatOn(d), nil, false)
		end
	end
	if f.moss then
		-- a cushion of moss on top with a sprout
		local top = cc + V(0, ch.Y * 1.0, -0.05)
		Kit.ell("Moss", top, V(0.42, 0.14, 0.4), f.moss)
		if full() then
			Kit.ell("Moss", top + V(0.12, 0.03, 0.08), V(0.18, 0.1, 0.16), A.shade(f.moss))
		end
		if f.sprout then
			Kit.limb("Sprout", top, top + V(0.02, 0.22, 0.02), 0.03, 0.025, "leaf_dark")
			Kit.limb("SproutLeaf", top + V(0.02, 0.2, 0.02), top + V(0.18, 0.3, 0.06), 0.06, 0.02, f.sprout, 0.35, V(0, 1, 0.3))
			Kit.limb("SproutLeaf", top + V(0.02, 0.19, 0.02), top + V(-0.14, 0.27, 0.04), 0.05, 0.02, f.sprout, 0.35, V(0, 1, 0.3))
		end
	end
	-- the legs: short, the front feet with big digging claws
	for _, l in { { n = "FL", s = -1, z = 0.36, ph = 0 }, { n = "FR", s = 1, z = 0.36, ph = 0.5 }, { n = "BL", s = -1, z = -0.4, ph = 0.5 }, { n = "BR", s = 1, z = -0.4, ph = 0 } } do
		local front = l.z > 0
		A.leg(l.n, l.s, l.ph, V(l.s * 0.27, 0.34, l.z), {
			kind = "post",
			r = 0.1,
			c = skin,
			foot = "pad",
			fw = 0.2,
			claw = if front then (f.claw or "cream") else nil,
			mass = false,
			out = 0.05,
		})
		if front and full() then
			A.claws("BigClaw" .. l.n, V(l.s * 0.32, 0.06, l.z + 0.12), 0.18, 0.1, f.claw or "cream", FWD, 3)
		end
	end
	Kit.on("body")
	-- the tail: tapering, in rings of armour
	local tl = f.tail or 0.75
	local t0 = V(0, 0.46, cc.Z - ch.Z * 0.85)
	local t1 = t0 + V(0, -0.1, -tl * 0.5)
	local t2 = t1 + V(0, -0.14, -tl * 0.5)
	J("tail1", "body", t0, "tail", 0, 1)
	Kit.limb("Tail", t0, t1, 0.13, 0.08, plate)
	if full() and tl > 0.5 then
		for _, u in { 0.35, 0.75 } do
			local c0 = lerp(t0, t1, u)
			Kit.limb("TailRing", c0 - (t1 - t0).Unit * 0.02, c0 + (t1 - t0).Unit * 0.02, 0.13 - 0.05 * u + 0.03, 0.13 - 0.05 * u + 0.03, seamC)
		end
	end
	J("tail2", "tail1", t1, "tail", 0, 2)
	Kit.limb("Tail", t1, t2, 0.08, 0.025, plate)
	-- the head: small and pointed, a plate over the top, tall ears
	local h = A.head({
		c = V(0, 0.56, 0.72),
		size = V(0.5, 0.46, 0.5),
		color = skin,
		pivot = V(0, 0.5, 0.5),
		muzzle = "fox",
		mlen = 0.36,
		mw = 0.22,
		mdrop = 0.08,
		nose = ink,
		eye = { R(38), R(10), 0.18 },
		iris = A.iris(a, "blue"),
		ink = ink,
		blush = true,
		-- (the plate on top of its head in place of a crown)
		face = A.more({ crown = false }, f.faceDetail),
	})
	Kit.ell("HeadPlate", h.top + V(0, -0.06, -0.02), V(0.38, 0.14, 0.4), plate, CFrame.Angles(R(-10), 0, 0))
	A.ears(h, { kind = "fox", len = f.ear or 0.3, w = 0.17, at = 0.4, back = 22, c = skin, inner = "pink" })
	return t
end

FORMS.pebblit = { plate = "steel", skin = "steel_dark", seam = "steel_dark", bands = 3, round = true, tail = 0.4, moss = "moss", sprout = "leaf" }
FORMS.opalback = { plate = "pink", skin = "cream", seam = "coral", bands = 6, tail = 0.95, shine = true, flecks = { "screen_on", "yellow", "crystal" }, ear = 0.38 }

------------------------------------------------------------------ the turtle (tortoises and sea turtles)
-- A tortoise: a high domed shell of raised plates (a row down the middle, a row each side, a rim of small ones round
-- the edge) over a pale belly plate, pillar legs on round pad feet with blunt nails, a head on a short neck with a wide
-- mouth and a little hooked beak, a short pointed tail. A sea turtle has a lower, longer shell and flippers: long
-- front ones like wings, short paddles behind. Forms: `sea`, `shell`, `seam`, `belly`, `beak`, `big`, `keels`, `moss`,
-- `saw`, `stars` (and `glow`), `pearl`, `cloud`, `reef`, `temple`, `head`, `h`.

-- The dome: a mass whose top half is the shell (an egg standing up, its short bottom half hidden under the rim).
type Dome = { m: A.Mass, E: Vector3, H: Vector3 }
local function domePoint(d: Dome, u: number, v: number): (Vector3, Vector3)
	-- the point on the dome over (u, v) across it from above (-1..1 each way), and the normal there
	local w = math.sqrt(math.max(0, 1 - u * u - v * v))
	local q = V(u * d.H.X, w * d.H.Y, v * d.H.Z)
	local n = V(q.X / (d.H.X * d.H.X), q.Y / (d.H.Y * d.H.Y), q.Z / (d.H.Z * d.H.Z)).Unit
	return d.E + q, n
end

PLANS.turtle = function(b, a, form)
	local f: Form = form or {}
	local sea = f.sea == true
	local k = f.big or 1
	local t = Kit.new("turtle", (f.h or (if sea then 1.5 else 1.7)) * k, 1.2, "quad")
	local shellC = f.shell or a
	local seamC = f.seam or A.shade(shellC)
	local belly = f.belly or "cream"
	local ink = f.ink or inkOf(b, a)
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	J("body", nil, P(0, 0.6, 0), "body")
	-- the shell: the dome in the seams' colour, raised plates over it, the rim, the belly plate under
	local E = P(0, if sea then 0.36 else 0.48, -0.06)
	local H = (if sea then V(0.8, 0.5, 1.02) else V(0.78, 0.72, 0.9)) * k
	local bot = 0.14 * k
	local size = V(H.X * 2, H.Y + bot, H.Z * 2)
	local split = H.Y / (H.Y + bot)
	local dc = E + V(0, (H.Y - bot) / 2, 0)
	Kit.egg("Shell", dc, size, split, seamC)
	local dome: Dome = { m = { c = dc, size = size, rot = CFrame.identity, split = split }, E = E, H = H }
	Kit.ell("Plastron", E + V(0, -bot * 0.55, 0.02), V(H.X * 1.7, bot * 1.1, H.Z * 1.8), belly)
	-- the rim: the edge plates, flaring out a little
	Kit.ell("Rim", E + V(0, 0.02, 0), V(H.X * 2.1, 0.16 * k, H.Z * 2.1), shellC)
	if f.saw then
		-- a snapper's saw-toothed back edge
		local teeth: { number } = if full() then { -0.6, -0.3, 0, 0.3, 0.6 } else { -0.45, 0, 0.45 }
		for _, u in teeth do
			local p0 = E + V(u * H.X * 0.9, 0.0, -H.Z * math.sqrt(1 - u * u * 0.8) * 1.0)
			Kit.limb("Saw", p0, p0 + V(u * 0.08, -0.02, -0.14) * k, 0.07 * k, 0.015, shellC, 0.5, UP)
		end
	end
	-- the plates: a row of three down the middle, three each side, each a flat plate lying on the dome with the
	-- darker seams showing between them
	local plates: { { number } } = {
		{ 0, 0.5, 0.44, 0.4 }, { 0, -0.02, 0.46, 0.42 }, { 0, -0.54, 0.42, 0.38 },
		{ -0.58, 0.34, 0.4, 0.4 }, { -0.66, -0.12, 0.4, 0.4 }, { -0.54, -0.58, 0.36, 0.34 },
		{ 0.58, 0.34, 0.4, 0.4 }, { 0.66, -0.12, 0.4, 0.4 }, { 0.54, -0.58, 0.36, 0.34 },
	}
	for i, pl in plates do
		local pt, nrm = domePoint(dome, pl[1] * 0.8, pl[2] * 0.8)
		local along = (V(0, 0, 1) - nrm * nrm.Z).Unit
		local th = 0.1 * k
		local sz = V(pl[3] * H.X / 0.78, th, pl[4] * H.Z / 0.9) * 1.22
		Kit.ell("Scute", pt - nrm * 0.012 * k, sz, shellC, flatOn(nrm, along))
		if f.stars then
			-- a star on the plate: a lit middle and rays out over it to its edge
			local top = pt + nrm * (th * 0.5 + 0.02)
			Kit.ell("StarMid", top, V(0.11, 0.05, 0.11) * k, f.stars, flatOn(nrm), nil, f.glow)
			if full() then
				local e1 = nrm:Cross(along).Unit
				local nr = if i <= 3 then 5 else 4
				for j = 0, nr - 1 do
					local ang = j / nr * math.pi * 2 + 0.3
					local q = top + (e1 * math.cos(ang) * sz.X + along * math.sin(ang) * sz.Z) * 0.36 - nrm * 0.02
					Kit.limb("StarRay", top, q, 0.026, 0.022, f.stars)
				end
			end
		end
		if f.keels and pl[1] == 0 then
			-- a keel down the middle: a blunt point standing up out of each plate
			local top = pt + nrm * th * 0.3
			Kit.limb("Keel", top - nrm * 0.04, top + (nrm + V(0, 0, -0.6)).Unit * 0.16 * k, 0.09 * k, 0.02, shellC, 0.5, V(1, 0, 0))
		end
	end
	if full() and not f.stars then
		-- the small plates round the lower edge of the dome
		for j = 0, 13 do
			local ang = (j + 0.5) / 14 * math.pi * 2
			local pt, nrm = domePoint(dome, math.sin(ang) * 0.93, math.cos(ang) * 0.93)
			local along = (V(0, 1, 0) - nrm * nrm.Y).Unit
			Kit.ell("Marginal", pt - nrm * 0.01 * k, V(0.3 * k, 0.08 * k, 0.2 * k), shellC, flatOn(nrm, along))
		end
	end
	if f.moss then
		-- moss on the shell: soft cushions in its dips and a few tufts
		for i, m in { { -0.35, 0.15, 0.3 }, { 0.42, -0.3, 0.26 }, { -0.1, -0.62, 0.2 }, { 0.2, 0.55, 0.18 } } do
			local pt, nrm = domePoint(dome, m[1], m[2])
			if i <= 2 or full() then
				Kit.ell("Moss", pt + nrm * 0.07 * k, V(m[3], 0.14, m[3] * 0.9) * k, if i % 2 == 0 then A.shade(f.moss) else f.moss, flatOn(nrm))
			end
		end
	end
	if f.pearl then
		-- a pearl in a little open clam on top
		local pt, nrm = domePoint(dome, 0, 0.05)
		Kit.ell("Clam", pt + nrm * 0.04, V(0.36, 0.08, 0.3) * k, f.clam or "cherry", flatOn(nrm))
		if full() then
			Kit.ell("ClamLid", pt + V(0, 0.16, -0.12) * k, V(0.34, 0.06, 0.26) * k, f.clam or "cherry", CFrame.Angles(R(-60), 0, 0))
		end
		Kit.ell("Pearl", pt + nrm * 0.18 * k, V(0.3, 0.3, 0.3) * k, f.pearl)
		shine("PearlShine", pt + nrm * 0.24 * k + V(-0.06, 0.04, 0.08) * k, 0.07)
	end
	if f.cloud then
		-- a little cloud riding over its back, and a farm on the cloud: a field in rows, a barn, a tree
		local cb = E + V(0, H.Y + 0.22 * k, -0.04 * k)
		for i, c in { { 0, 0, 0, 0.9, 0.42, 0.8 }, { -0.36, -0.06, 0.12, 0.5, 0.34, 0.5 }, { 0.38, -0.04, -0.1, 0.52, 0.36, 0.52 }, { 0.06, -0.08, 0.38, 0.46, 0.3, 0.4 }, { -0.1, -0.06, -0.4, 0.46, 0.3, 0.42 } } do
			if i <= 3 or full() then
				Kit.ell("Cloud", cb + V(c[1], c[2], c[3]) * k, V(c[4], c[5], c[6]) * k, f.cloud)
			end
		end
		local fieldTop = cb + V(0, 0.2, 0) * k
		Kit.ell("Field", fieldTop, V(0.6, 0.06, 0.5) * k, "grass")
		if full() then
			for _, x in { -0.16, 0, 0.16 } do
				Kit.limb("Crop", fieldTop + V(x, 0.03, -0.16) * k, fieldTop + V(x, 0.03, 0.06) * k, 0.03 * k, 0.03 * k, "straw")
			end
		end
		-- the barn: a red block under a white gable roof
		local bb = fieldTop + V(0.16, 0.08, 0.14) * k
		Kit.part("Barn", "Block", V(0.18, 0.14, 0.16) * k, CFrame.new(bb), "berry_red")
		for _, side in { -1, 1 } do
			Kit.part("BarnRoof", "Block", V(0.13, 0.03, 0.2) * k, CFrame.new(bb + V(side * 0.045, 0.1, 0) * k) * CFrame.Angles(0, 0, -side * R(38)), "white")
		end
		local tb = fieldTop + V(-0.18, 0, 0.12) * k
		Kit.limb("TreeTrunk", tb, tb + V(0, 0.16, 0) * k, 0.03 * k, 0.025 * k, "wood_dark")
		Kit.ell("TreeTop", tb + V(0, 0.22, 0) * k, V(0.2, 0.2, 0.2) * k, "leaf")
	end
	if f.reef then
		-- a reef on its shell: branching coral, a strand of weed, a starfish, and two little fish swimming over it
		local function coral(u: number, v: number, hgt: number, col: string)
			local pt, nrm = domePoint(dome, u, v)
			local top = pt + (nrm + UP).Unit * hgt * k
			Kit.limb("Coral", pt - nrm * 0.03, top, 0.07 * k, 0.04 * k, col)
			local mid = lerp(pt, top, 0.45)
			Kit.limb("Coral", mid, mid + V(0.14, 0.12, 0.04) * k, 0.045 * k, 0.03 * k, col)
			Kit.limb("Coral", mid + (top - mid) * 0.3, mid + V(-0.12, 0.2, -0.04) * k, 0.04 * k, 0.03 * k, col, nil, nil, true)
		end
		coral(-0.25, 0.2, 0.36, f.reef)
		coral(0.35, -0.25, 0.3, f.reef2 or "coral")
		local wp, wn = domePoint(dome, 0.05, -0.55)
		Kit.limbs("Weed", { wp, wp + (wn + UP).Unit * 0.2 * k + V(0.04, 0, 0), wp + (wn + UP).Unit * 0.36 * k - V(0.03, 0, 0) }, { 0.04 * k, 0.02 * k }, "leaf_dark", 2, 0.5, FWD)
		if full() then
			local sp, sn = domePoint(dome, -0.6, -0.35)
			for j = 0, 4 do
				local ang = j / 5 * math.pi * 2
				local e1 = sn:Cross(FWD).Unit
				local e2 = sn:Cross(e1).Unit
				Kit.limb("Starfish", sp + sn * 0.03, sp + sn * 0.03 + (e1 * math.cos(ang) + e2 * math.sin(ang)) * 0.12 * k, 0.04 * k, 0.015, "yellow", 0.5, sn)
			end
		end
		local fish: { { p: Vector3, c: string } } = { { p = V(0.45, 0.38, 0.3), c = "orange" }, { p = V(-0.4, 0.5, -0.2), c = "yellow" } }
		for i, fp in fish do
			if i == 1 or full() then
				local c0 = E + V(fp.p.X, H.Y / k + fp.p.Y, fp.p.Z) * k
				local col = fp.c
				Kit.egg("Fish", c0, V(0.14, 0.3, 0.2) * k, 0.4, col, A.lie(V(-1, 0, -0.3), UP))
				Kit.limb("FishTail", c0 - V(1, 0, 0.3).Unit * 0.14 * k, c0 - V(1, 0, 0.3).Unit * 0.26 * k, 0.035 * k, 0.09 * k, col, 0.3, V(0, 0, 1))
			end
		end
	end
	if f.temple then
		-- a little temple on its back: two steps, four pillars round a small hall with a dark door, a beam over them,
		-- a gable roof
		local g = f.temple
		local base = E + V(0, H.Y - 0.05 * k, -0.04 * k)
		local function block(name: string, c: Vector3, sz: Vector3, col: string)
			Kit.part(name, "Block", sz * k, CFrame.new(c), col)
		end
		block("TempleStep", base + V(0, 0.03, 0) * k, V(0.66, 0.08, 0.6), g)
		if full() then
			block("TempleStep", base + V(0, 0.1, 0) * k, V(0.56, 0.06, 0.5), g)
		end
		local fl = base + V(0, 0.13, 0) * k
		block("TempleHall", fl + V(0, 0.12, -0.03) * k, V(0.28, 0.24, 0.26), f.hall or g)
		Kit.part("TempleDoor", "Block", V(0.1, 0.15, 0.05) * k, CFrame.new(fl + V(0, 0.08, 0.11) * k), "black")
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			local p0 = fl + V(c[1] * 0.21, 0, c[2] * 0.18) * k
			Kit.limb("Pillar", p0, p0 + UP * 0.26 * k, 0.035 * k, 0.035 * k, g, nil, nil, true)
		end
		block("TempleBeam", fl + V(0, 0.28, 0) * k, V(0.56, 0.05, 0.5), g)
		for _, side in { -1, 1 } do
			-- (each half of the roof a wedge, its tall end at the ridge)
			local cf = CFrame.new(fl + V(side * 0.15, 0.39, 0) * k) * CFrame.Angles(0, -side * R(90), 0)
			Kit.part("TempleRoof", "Wedge", V(0.56, 0.17, 0.3) * k, cf, g)
		end
		Kit.ell("TempleLamp", fl + V(0, 0.18, 0.2) * k, V(0.06, 0.08, 0.06) * k, "yellow", nil, true, true)
	end
	-- the legs: pillars on pad feet, or flippers
	for _, l in { { n = "FL", s = -1, z = 0.5, ph = 0 }, { n = "FR", s = 1, z = 0.5, ph = 0.5 }, { n = "BL", s = -1, z = -0.52, ph = 0.5 }, { n = "BR", s = 1, z = -0.52, ph = 0 } } do
		local side = l.s
		Kit.on("body")
		if sea then
			local front = l.z > 0
			local sh = P(side * 0.46, 0.3, if front then 0.5 else -0.6)
			J("leg" .. l.n, "body", sh, "leg", side, l.ph)
			if front then
				-- a long flipper like a wing, swept back
				local el = P(side * 0.9, 0.18, 0.62)
				local tip = P(side * 1.3, 0.06, 0.34)
				Kit.limbs("Flipper" .. l.n, { sh, el, tip }, { 0.15 * k, 0.15 * k, 0.05 * k }, b, 2, 0.3, UP)
				if full() then
					Kit.ell("FlipperSpot" .. l.n, lerp(sh, el, 0.6) + V(0, 0.04, 0) * k, V(0.12, 0.04, 0.1) * k, seamC)
					Kit.ell("FlipperSpot" .. l.n, lerp(el, tip, 0.4) + V(0, 0.035, 0) * k, V(0.1, 0.04, 0.08) * k, seamC)
				end
			else
				local tip = P(side * 0.7, 0.06, -0.92)
				Kit.limb("Flipper" .. l.n, sh, tip, 0.13 * k, 0.09 * k, b, 0.35, UP)
				Kit.ell("Paddle" .. l.n, tip + V(side * 0.03, 0, -0.05) * k, V(0.28, 0.08, 0.26) * k, b)
			end
		else
			A.leg(l.n, side, l.ph, P(side * 0.48, 0.42, l.z), {
				kind = "post",
				r = 0.15 * k,
				c = b,
				foot = "pad",
				fw = 0.3 * k,
				claw = f.nails or "cream",
				mass = false,
				out = 0.08 * k,
			})
			if full() then
				-- scales down the front of the leg
				Kit.ell("LegScale" .. l.n, P(side * 0.56, 0.24, l.z + 0.13), V(0.12, 0.1, 0.05) * k, A.shade(b))
			end
		end
	end
	Kit.on("body")
	-- the tail
	J("tail1", "body", P(0, 0.34, -0.86), "tail", 0, 1)
	Kit.limb("Tail", P(0, 0.38, -0.84), P(0, 0.26, -1.12 - (if f.saw then 0.16 else 0)), 0.1 * k, 0.025, b)
	if f.saw and full() then
		for _, u in { 0.3, 0.6 } do
			local p0 = lerp(P(0, 0.34, -0.84), P(0, 0.24, -1.28), u)
			Kit.limb("TailRidge", p0, p0 + V(0, 0.1, -0.04) * k, 0.04 * k, 0.012, A.shade(b))
		end
	end
	-- the head on a short neck: a wide mouth and a little hooked beak
	local hs = (f.head or V(0.66, 0.6, 0.66)) * k
	local hc = if sea then P(0, 0.66, 1.26) else P(0, 0.94, 1.14)
	A.head({
		c = hc,
		size = hs,
		color = b,
		pivot = if sea then P(0, 0.44, 0.78) else P(0, 0.6, 0.7),
		muzzle = "frog",
		mdrop = hs.Y * 0.1,
		eye = { R(38), R(12), 0.23 * k },
		iris = A.iris(a, "gold"),
		ink = ink,
		blush = true,
		face = A.more(nil, f.faceDetail),
	})
	Kit.limb("Neck", (if sea then P(0, 0.4, 0.66) else P(0, 0.56, 0.62)), hc - V(0, hs.Y * 0.22, hs.Z * 0.22), 0.21 * k, 0.19 * k, b)
	Kit.ell("Throat", hc + V(0, -hs.Y * 0.32, hs.Z * 0.08), V(hs.X * 0.7, hs.Y * 0.4, hs.Z * 0.6), if belly == "white" then "white" else A.under(b), nil, true)
	local bk = f.beak or A.shade(b)
	local bl = if f.hook then 1.6 else 1
	local b0 = hc + V(0, -hs.Y * 0.06, hs.Z * 0.42)
	Kit.limb("Beak", b0, b0 + V(0, -0.08 * bl, 0.1 * bl) * k, 0.07 * k * bl, 0.02 * k, bk, 0.7, V(1, 0, 0))
	if f.hook then
		-- a snapper's big hooked beak: the hook over the lower jaw
		Kit.limb("BeakHook", b0 + V(0, -0.08, 0.14) * k, b0 + V(0, -0.2, 0.12) * k, 0.05 * k, 0.015, bk, 0.7, V(1, 0, 0))
	end
	return t
end

FORMS.shellback = { shell = "sand", seam = "sand_dark" }
FORMS.pearlback = { style = "seaturtle", sea = true, shell = "pink", seam = "coral", belly = "white", pearl = "white", clam = "cherry" }
FORMS.skyshell = { style = "seaturtle", sea = true, shell = "blue", seam = "jeans", belly = "white", cloud = "white", big = 1.12 }
FORMS.snapmoss = { shell = "rock", seam = "basalt", keels = true, saw = true, moss = "leaf", hook = true, head = V(0.66, 0.56, 0.66), beak = "basalt", nails = "basalt" }
FORMS.elderreef = { style = "seaturtle", sea = true, shell = "teal", seam = "swamp", reef = "pink", reef2 = "coral", big = 1.15 }
FORMS.templeback = { shell = "wood_dark", seam = "hair_brown", temple = "gold", big = 1.2 }
FORMS.starshell = { shell = "black", seam = "night", stars = "yellow", glow = true, belly = "slate", big = 1.1 }

------------------------------------------------------------------ the golem
-- A golem: a big chest and shoulders, a small head sunk between them, long heavy arms with big fists, short stout
-- legs. Each kind is made of what it is: basalt in six-sided columns with fire showing between them, ice in rough
-- blocks under caps of snow, a carved stone guard in squared blocks with gold trim and a visor, a tree with a trunk
-- for a body, roots for legs, branches for arms and a crown of leaves (or of crystals) over a face in its bark.
-- Forms: `kind` "basalt" | "ice" | "guard" | "tree", and for trees `crown` "leaf" | "crystal", `beard`, `blossom`.

-- A box lit on its own faces (a cut stone, a slab, an ice block): `cf` its centre and turn.
local function slab(name: string, cf: CFrame, size: Vector3, color: string, detail: boolean?, neon: boolean?): BasePart?
	if detail and not full() then
		return nil
	end
	local p = Kit.part(name, "Block", size, cf, color, neon)
	p:SetAttribute("PixelOwn", true)
	return p
end

-- A box from `a` to `b` (its local Y along the way), `w` wide and `d` deep, turned `roll` degrees about its length.
local function beam(name: string, a: Vector3, b: Vector3, w: number, d: number, color: string, roll: number?, detail: boolean?): BasePart?
	local ax = b - a
	local cf = CFrame.new((a + b) / 2) * A.lie(ax.Unit, FWD) * CFrame.Angles(0, R(roll or 0), 0)
	return slab(name, cf, V(w, ax.Magnitude, d), color, detail)
end

-- A six-sided column of basalt from `a` to `b`, `s` the length of a side: three boxes turned 60 degrees apart about
-- its length (together exactly a hexagonal prism; one plain box on the islands' lighter level).
local function hexCol(name: string, a: Vector3, b: Vector3, s: number, color: string, twist: number?, detail: boolean?)
	if detail and not full() then
		return
	end
	local ax = b - a
	local base = CFrame.new((a + b) / 2) * A.lie(ax.Unit, FWD) * CFrame.Angles(0, R(twist or 0), 0)
	if full() then
		for i = 0, 2 do
			slab(name, base * CFrame.Angles(0, R(60 * i), 0), V(s, ax.Magnitude, s * math.sqrt(3)), color)
		end
	else
		slab(name, base, V(s * 1.8, ax.Magnitude, s * 1.75), color)
	end
end

-- Eyes and a mouth on a flat face (a block's, a column's): the face's plane through `fc`, facing forward. The eyes sit
-- `sx` apart from the middle and `sy` up; (a big ball just behind the face stands in for its surface).
local function flatFace(fc: Vector3, eyeD: number, sx: number, sy: number, iris: string?, ink: string, mouthW: number, mouthY: number, blush: boolean?)
	local R0 = 3
	local c = fc - FWD * R0
	Kit.faceOn(c, V(R0, R0, R0))
	Kit.eyes(c, R0, FWD, math.asin(sx / R0), math.asin(sy / R0), eyeD, iris, if ink ~= "black" then ink else nil)
	if blush then
		Kit.blush(c, R0, FWD, math.asin((sx + eyeD * 0.7) / R0), math.asin((-sy * 0.4 + 0.06) / R0), eyeD * 0.55)
	end
	Kit.faceOff()
	if mouthW > 0 then
		Kit.mouth(fc + V(0, mouthY, 0.01), FWD, mouthW, ink)
	end
end

-- The details of a golem's face (A.face) on the face it was given: no crown on a block's or a column's front. A flat
-- face's eyes sit on flatFace's big stand-in ball, and A.face sizes brows and cheek marks by the head they sit on, so
-- on a flat face they came out a ball's size: the brows floated as two lines over the head. A flat face has neither.
local function golemFace(color: string, f: Form, more: A.FaceMore?)
	A.face({ color = color, more = A.more(A.more({ crown = false, brows = false, cheeks = false }, more), f.faceDetail) })
end

local function basaltGolem(b: string, a: string, f: Form): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local glow = f.glow or a
	J("body", nil, V(0, 1.0, 0), "body")
	-- the chest: columns of basalt standing together, flat tops at different heights, a molten core between them
	hexCol("Column", V(0, 0.62, -0.12), V(0, 1.84, -0.12), 0.34, b, 0)
	hexCol("Column", V(-0.3, 0.64, 0.12), V(-0.3, 1.64, 0.12), 0.3, b, 8)
	hexCol("Column", V(0.3, 0.64, 0.12), V(0.3, 1.72, 0.12), 0.3, b, -6)
	hexCol("Column", V(-0.36, 0.68, -0.28), V(-0.36, 1.5, -0.28), 0.25, b, 20, true)
	hexCol("Column", V(0.36, 0.68, -0.28), V(0.36, 1.56, -0.28), 0.25, b, -14, true)
	Kit.ell("Core", V(0, 1.22, 0.24), V(0.26, 0.5, 0.2), glow, nil, nil, true)
	-- cracks glowing down the front faces of the columns
	for _, side in { -1, 1 } do
		local z = 0.12 + 0.3 * math.sqrt(3) / 2 + 0.012
		local x = side * 0.3
		local pts = { V(x + side * 0.06, 1.5, z), V(x - side * 0.04, 1.3, z), V(x + side * 0.05, 1.08, z), V(x - side * 0.02, 0.86, z) }
		for i = 1, #pts - 1 do
			Kit.limb("Crack", pts[i], pts[i + 1], 0.025, 0.025, glow, nil, nil, i == 3, true)
		end
	end
	-- the head: a short column sunk between the shoulders, a broken bit of one on top
	J("head", "body", V(0, 1.72, 0.08), "head")
	local hs = 0.46
	hexCol("Head", V(0, 1.74, 0.06), V(0, 2.24, 0.06), hs, b, 0)
	hexCol("HeadChip", V(0.12, 2.2, -0.02), V(0.2, 2.44, -0.08), 0.13, b, 15)
	local fz = 0.06 + hs * math.sqrt(3) / 2 + 0.01
	flatFace(V(0, 2.02, fz), 0.18, 0.125, 0.04, "yellow", glow, 0.16, -0.14)
	golemFace(b, f)
	if full() then
		Kit.limb("Crack", V(0.2, 2.22, fz), V(0.15, 2.12, fz), 0.022, 0.022, glow, nil, nil, nil, true)
	end
	-- the arms: column pieces down to a big fist, the fire in the joints
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.74, 1.55, 0), "arm", side)
		hexCol("Shoulder" .. s, V(side * 0.66, 1.42, -0.02), V(side * 0.76, 1.78, -0.04), 0.22, b, 10)
		local el = V(side * 0.88, 1.06, 0.03)
		local wr = V(side * 0.92, 0.62, 0.1)
		hexCol("Arm" .. s, V(side * 0.72, 1.5, 0), el, 0.16, b, 0)
		Kit.ell("Elbow" .. s, el, V(0.2, 0.16, 0.2), glow, nil, nil, true)
		hexCol("Forearm" .. s, el, wr, 0.19, b, 25)
		hexCol("Fist" .. s, V(side * 0.93, 0.66, 0.11), V(side * 0.95, 0.3, 0.13), 0.25, b, -10)
		if full() then
			Kit.limb("Crack" .. s, V(side * 0.95, 0.56, 0.35), V(side * 0.93, 0.42, 0.35), 0.022, 0.022, glow, nil, nil, nil, true)
		end
		-- the legs: short thick columns on a slab of a foot
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		hexCol("Leg" .. s, V(side * 0.34, 0.66, 0.02), V(side * 0.35, 0.16, 0.04), 0.21, b, 0)
		slab("Foot" .. s, CFrame.new(side * 0.35, 0.09, 0.1) * CFrame.Angles(0, R(side * 6), 0), V(0.42, 0.18, 0.54), b)
	end
	return t
end

local function iceGolem(b: string, a: string, f: Form): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local snow = f.snow or a
	local deep = f.deep or "ice"
	local ink = f.ink or "black"
	J("body", nil, V(0, 1.0, 0), "body")
	-- the chest: a big rough block of ice on a smaller one, chunks jutting out at the shoulders
	slab("Chest", CFrame.new(0, 1.26, -0.04) * CFrame.Angles(R(5), R(8), R(-4)), V(1.04, 0.92, 0.78), b)
	slab("Waist", CFrame.new(0.02, 0.8, 0) * CFrame.Angles(R(-3), R(-12), R(3)), V(0.8, 0.44, 0.62), deep)
	slab("Chunk", CFrame.new(-0.3, 1.5, -0.32) * CFrame.Angles(R(18), R(30), R(10)), V(0.36, 0.34, 0.32), deep, true)
	-- a lean of snow on top, and shine on the faces
	Kit.ell("Snow", V(-0.06, 1.72, -0.06), V(0.8, 0.16, 0.6), snow)
	if full() then
		slab("Shine", CFrame.new(-0.24, 1.32, 0.36) * CFrame.Angles(R(5), R(8), R(-30)), V(0.05, 0.4, 0.03), "white")
		slab("Shine", CFrame.new(-0.12, 1.2, 0.36) * CFrame.Angles(R(5), R(8), R(-30)), V(0.04, 0.22, 0.03), "white")
		-- a crack of deeper blue inside
		slab("Crack", CFrame.new(0.22, 1.12, 0.35) * CFrame.Angles(R(5), R(8), R(24)), V(0.04, 0.36, 0.03), "blue")
	end
	-- the head: a smaller block set down between the shoulders, a cap of snow
	J("head", "body", V(0, 1.72, 0.08), "head")
	local hcf = CFrame.new(0, 1.98, 0.14) * CFrame.Angles(0, R(5), R(3))
	slab("Head", hcf, V(0.56, 0.5, 0.5), b)
	Kit.ell("HeadSnow", V(0.02, 2.26, 0.12), V(0.6, 0.14, 0.52), snow)
	flatFace(V(0, 1.98, 0.14 + 0.26), 0.21, 0.14, 0.04, nil, ink, 0.16, -0.14, true)
	golemFace(b, f)
	if full() then
		for i, x in { -0.18, 0.04, 0.2 } do
			Kit.limb("Icicle", V(x, 1.74, 0.36), V(x, 1.6 - (i % 2) * 0.06, 0.37), 0.04, 0.012, snow)
		end
	end
	-- the arms: rough blocks, a big square fist, icicles hanging off them
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.74, 1.55, 0), "arm", side)
		slab("Shoulder" .. s, CFrame.new(side * 0.62, 1.6, -0.02) * CFrame.Angles(R(10), R(side * 20), R(-side * 14)), V(0.5, 0.42, 0.52), deep)
		Kit.ell("ShoulderSnow" .. s, V(side * 0.64, 1.84, -0.02), V(0.44, 0.12, 0.42), snow)
		local el = V(side * 0.86, 1.06, 0.04)
		local wr = V(side * 0.92, 0.64, 0.1)
		beam("Arm" .. s, V(side * 0.74, 1.46, 0), el, 0.32, 0.32, b, side * 12)
		beam("Forearm" .. s, el, wr, 0.38, 0.36, b, -side * 8)
		slab("Fist" .. s, CFrame.new(side * 0.95, 0.42, 0.14) * CFrame.Angles(R(6), R(side * 14), R(side * 5)), V(0.46, 0.42, 0.44), deep)
		if full() then
			Kit.limb("Icicle" .. s, V(side * 1.0, 0.98, 0.04), V(side * 1.01, 0.76, 0.05), 0.05, 0.014, snow)
			Kit.limb("Icicle" .. s, V(side * 0.9, 0.98, 0.18), V(side * 0.9, 0.84, 0.19), 0.04, 0.012, snow)
		end
		-- the legs: short blocks on broad feet
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		beam("Leg" .. s, V(side * 0.33, 0.66, 0.02), V(side * 0.35, 0.14, 0.04), 0.38, 0.4, b, side * 6)
		slab("Foot" .. s, CFrame.new(side * 0.35, 0.09, 0.08) * CFrame.Angles(0, R(side * 8), 0), V(0.44, 0.18, 0.54), deep)
	end
	return t
end

local function guardGolem(b: string, a: string, f: Form): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local trim = f.trim or a
	local dk = f.dark or A.shade(b)
	J("body", nil, V(0, 1.0, 0), "body")
	-- the chest: squared stone, broad at the top; a gold rim along its top, a gold belt, a gold seal with a keyhole
	slab("Chest", CFrame.new(0, 1.38, 0), V(1.0, 0.7, 0.64), b)
	slab("Waist", CFrame.new(0, 0.86, 0), V(0.72, 0.4, 0.52), b)
	slab("ChestRim", CFrame.new(0, 1.74, 0), V(1.04, 0.07, 0.68), trim)
	slab("Belt", CFrame.new(0, 1.02, 0), V(0.78, 0.1, 0.58), trim)
	Kit.ell("Seal", V(0, 1.38, 0.33), V(0.3, 0.3, 0.07), trim)
	Kit.ell("Keyhole", V(0, 1.41, 0.37), V(0.08, 0.08, 0.04), "black")
	slab("Keyhole", CFrame.new(0, 1.34, 0.365), V(0.04, 0.1, 0.03), "black")
	if full() then
		-- old cracks in the stone, moss on one shoulder
		Kit.limb("Crack", V(-0.42, 1.62, 0.325), V(-0.3, 1.5, 0.325), 0.02, 0.02, dk)
		Kit.limb("Crack", V(-0.3, 1.5, 0.325), V(-0.34, 1.36, 0.325), 0.02, 0.02, dk)
		Kit.limb("Crack", V(0.28, 1.14, 0.325), V(0.38, 1.24, 0.325), 0.02, 0.02, dk)
	end
	-- the head: a squared helmet with a gold crest, the visor across it
	J("head", "body", V(0, 1.72, 0.08), "head")
	slab("Head", CFrame.new(0, 1.98, 0.08), V(0.58, 0.5, 0.52), b)
	slab("Crest", CFrame.new(0, 2.29, 0.04), V(0.07, 0.16, 0.52), trim)
	slab("Crest", CFrame.new(0, 2.39, -0.02), V(0.06, 0.08, 0.36), trim, true)
	slab("VisorBand", CFrame.new(0, 2.0, 0.345), V(0.54, 0.16, 0.03), dk)
	flatFace(V(0, 2.0, 0.36), 0.2, 0.14, 0, nil, "black", 0, 0)
	golemFace(b, f)
	if full() then
		-- an old crack down the helmet's brow over the visor, a chip knocked out beside it
		Kit.limb("HelmCrack", V(0.17, 2.2, 0.36), V(0.12, 2.14, 0.36), 0.022, 0.022, dk)
		Kit.limb("HelmCrack", V(0.12, 2.14, 0.36), V(0.15, 2.09, 0.36), 0.022, 0.022, dk)
		Kit.ell("HelmChip", V(-0.19, 2.17, 0.355), V(0.06, 0.05, 0.05), dk)
	end
	slab("Chin", CFrame.new(0, 1.8, 0.3), V(0.3, 0.08, 0.06), trim, true)
	-- the arms: a pauldron with a gold edge at each shoulder, squared arms with gold cuffs, square fists
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.74, 1.55, 0), "arm", side)
		local pcf = CFrame.new(side * 0.66, 1.66, 0) * CFrame.Angles(0, 0, R(-side * 14))
		slab("Pauldron" .. s, pcf, V(0.46, 0.28, 0.54), b)
		slab("PauldronRim" .. s, pcf * CFrame.new(side * 0.02, -0.15, 0), V(0.5, 0.06, 0.58), trim)
		if side < 0 then
			Kit.ell("Moss" .. s, (pcf * CFrame.new(0, 0.15, -0.04)).Position, V(0.32, 0.1, 0.36), f.moss or "moss")
		end
		local el = V(side * 0.86, 1.1, 0.02)
		local wr = V(side * 0.9, 0.66, 0.08)
		beam("Arm" .. s, V(side * 0.76, 1.5, 0), el, 0.28, 0.3, b)
		beam("Forearm" .. s, el, wr, 0.34, 0.34, b)
		beam("Cuff" .. s, lerp(el, wr, 0.62), lerp(el, wr, 0.78), 0.38, 0.38, trim)
		slab("Fist" .. s, CFrame.new(side * 0.92, 0.44, 0.1), V(0.42, 0.4, 0.42), b)
		-- the legs: square columns on squared feet
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		beam("Leg" .. s, V(side * 0.33, 0.68, 0.02), V(side * 0.34, 0.14, 0.03), 0.34, 0.38, b)
		slab("Foot" .. s, CFrame.new(side * 0.34, 0.09, 0.08), V(0.42, 0.18, 0.52), b)
		slab("FootRim" .. s, CFrame.new(side * 0.34, 0.2, 0.08), V(0.44, 0.05, 0.54), trim, true)
	end
	return t
end

local function treeGolem(b: string, a: string, f: Form): Kit.Thing
	local t = Kit.new("golem", f.h or 2.7, 1.3, "biped")
	local bark = f.bark or A.shade(b)
	local crystal = f.crown == "crystal"
	local leaf = f.leaf or a
	local ink = f.ink or inkOf(b, a)
	J("body", nil, V(0, 1.0, 0), "body")
	-- the trunk: wide at the foot and narrowing up, ridges of bark up it, a knot hole
	local tb, tt = V(0, 0.5, 0), V(0, 1.7, 0.02)
	Kit.limb("Trunk", tb, tt, 0.5, 0.42, b)
	if full() then
		for i, ang in { -70, -30, 12, 50, 100, 150 } do
			local d = A.dir(ang, 0)
			local w = if i % 2 == 0 then 0.04 else -0.04
			Kit.limbs("Bark", { tb + d * 0.47 + UP * 0.12, lerp(tb, tt, 0.5) + d * 0.47 + V(w, 0, 0), tt + d * 0.41 - UP * 0.06 }, { 0.05, 0.04 }, bark, 2)
		end
		local kc = lerp(tb, tt, 0.45) + A.dir(-28, 0) * 0.46
		Kit.ell("Knot", kc, V(0.2, 0.26, 0.08), bark, A.lie(A.dir(-28, 0), UP))
		Kit.ell("KnotHole", kc + A.dir(-28, 0) * 0.03, V(0.11, 0.16, 0.06), "black", A.lie(A.dir(-28, 0), UP))
		if not crystal then
			-- a toadstool on the trunk
			local mp = lerp(tb, tt, 0.25) + A.dir(40, 0) * 0.48
			Kit.limb("Toadstool", mp, mp + V(0.04, 0.08, 0.04), 0.035, 0.03, "cream")
			Kit.ell("ToadstoolCap", mp + V(0.05, 0.11, 0.05), V(0.18, 0.08, 0.18), "berry_red")
		end
	end
	-- the arms: branches out of the shoulders and down, twig fingers, a sprig at the elbow
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.74, 1.55, 0), "arm", side)
		local sh, el, hd = V(side * 0.36, 1.5, 0), V(side * 0.8, 1.3, 0.04), V(side * 0.94, 0.86, 0.12)
		Kit.limbs("Branch" .. s, { sh, el, hd }, { 0.18, 0.14, 0.11 }, b, 2)
		for i, d in { V(side * 0.3, -1, 0.5), V(side * 0.05, -1, 0.7), V(side * -0.25, -0.9, 0.6) } do
			Kit.limb("Twig" .. s, hd, hd + d.Unit * (0.26 - i * 0.02), 0.07, 0.03, b)
		end
		local sp = lerp(sh, el, 0.75)
		local st = sp + V(side * 0.18, 0.34, -0.02)
		Kit.limb("Sprig" .. s, sp, st, 0.06, 0.03, b)
		if crystal then
			Kit.limb("SprigGem" .. s, st - V(0, 0.04, 0), st + V(side * 0.04, 0.2, 0), 0.07, 0.015, leaf, 0.8, FWD)
		else
			Kit.ell("Leaf" .. s, st + V(side * 0.08, 0.04, 0), V(0.22, 0.06, 0.14), leaf, CFrame.Angles(0, 0, R(side * 30)))
			Kit.ell("Leaf" .. s, st + V(-side * 0.04, 0.06, 0.04), V(0.16, 0.05, 0.11), A.shade(leaf), CFrame.Angles(0, 0, R(-side * 25)), true)
		end
		-- the legs: a thick root down to the ground, smaller roots spreading out over it
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		local hip, foot = V(side * 0.26, 0.62, 0.02), V(side * 0.4, 0.08, 0.1)
		Kit.limb("Root" .. s, hip, foot, 0.22, 0.14, b)
		for i, d in { V(side * 0.2, 0, 1), V(side, 0, 0.2), V(side * 0.4, 0, -0.9) } do
			if i <= 2 or full() then
				Kit.limb("RootToe" .. s, foot + V(0, 0.02, 0), foot + d.Unit * 0.32 - V(0, 0.04, 0), 0.11, 0.035, b, 0.7, UP)
			end
		end
	end
	-- the head: the top of the trunk with the face in its bark, the crown over it
	J("head", "body", V(0, 1.72, 0.08), "head")
	local hc = V(0, 1.84, 0.04)
	Kit.limb("TrunkTop", V(0, 1.62, 0.02), V(0, 2.04, 0.0), 0.43, 0.4, b)
	Kit.faceOn(hc, V(0.42, 0.6, 0.42))
	Kit.eyes(hc, 0.44, FWD, R(30), R(4), 0.26, A.iris(a, "gold"), if ink ~= "black" then ink else nil)
	Kit.blush(hc, 0.44, FWD, R(48), R(14), 0.14)
	Kit.faceOff()
	local front = Kit.onEll(hc, V(0.42, 0.6, 0.42), CFrame.identity, A.dir(0, -16))
	Kit.mouth(front, V(0, -0.2, 1), 0.18, ink)
	-- a brow of bark over the eyes, a knot of a nose
	local bp = Kit.onEll(hc, V(0.42, 0.6, 0.42), CFrame.identity, A.dir(0, 22))
	Kit.limbs("Brow", { bp + V(-0.26, -0.04, -0.06), bp + V(0, 0.02, 0.02), bp + V(0.26, -0.04, -0.06) }, { 0.045, 0.055, 0.045 }, bark, 2, 0.7, FWD)
	Kit.ell("Nose", Kit.onEll(hc, V(0.42, 0.6, 0.42), CFrame.identity, A.dir(0, -2)), V(0.1, 0.09, 0.1), bark)
	-- (its own brow of bark; a round face, so the bark's grain on its cheeks)
	golemFace(b, f, { cheeks = true })
	if f.beard then
		-- a long beard of pale lichen
		for i, x in { -0.14, 0, 0.14 } do
			local p0 = front + V(x, -0.08, -0.02)
			Kit.limbs("Beard", { p0, p0 + V(x * 0.3, -0.16, 0.06), p0 + V(x * 0.5 + (i - 2) * 0.03, -0.32 + math.abs(x) * 0.5, 0.05) }, { 0.07, 0.05, 0.015 }, f.beard, 2, 0.6, FWD)
		end
	end
	-- the crown
	local ct = if crystal then V(0, 2.3, -0.04) else V(0, 2.5, -0.22)
	if crystal then
		-- crystals growing out of the top of the trunk, the moonlight caught in two of them
		Kit.ell("CrownBase", ct + V(0, -0.2, 0), V(0.86, 0.26, 0.8), b)
		local gems: { { number } } = { { 0, 1, 0, 0.82 }, { -0.6, 0.8, 0.1, 0.62 }, { 0.6, 0.85, 0, 0.64 }, { -0.25, 0.9, -0.55, 0.58 }, { 0.35, 0.9, -0.5, 0.56 }, { 0.2, 0.85, 0.5, 0.44 }, { -0.4, 0.8, 0.45, 0.42 } }
		for i, g in gems do
			if i <= 5 or full() then
				local d = V(g[1], g[2], g[3]).Unit
				local base = ct + V(g[1], 0, g[3]) * 0.3 - UP * 0.12
				Kit.limb("Crystal", base, base + d * g[4], 0.16, 0.03, if i % 3 == 0 then (f.leaf2 or "white") else leaf, 0.85, d:Cross(UP).Magnitude > 0.1 and d:Cross(UP).Unit or FWD)
				if full() and i <= 4 then
					shine("CrystalShine", base + d * g[4] * 0.45 + V(-0.04, 0, 0.06), 0.05)
				end
			end
		end
		for _, p in { V(-0.32, 2.3, 0.3), V(0.36, 2.42, 0.18) } do
			Kit.ell("Moonfruit", p, V(0.11, 0.11, 0.11), f.fruit or "white", nil, true, true)
		end
	else
		-- leaves in big soft clumps, darker underneath, a few blossoms
		Kit.ell("Crown", ct, V(1.3, 0.62, 1.1), leaf)
		Kit.ell("Crown", ct + V(-0.54, -0.1, 0.0), V(0.66, 0.5, 0.66), A.shade(leaf))
		Kit.ell("Crown", ct + V(0.56, -0.08, -0.04), V(0.66, 0.5, 0.64), A.shade(leaf))
		Kit.ell("Crown", ct + V(0.08, 0.26, -0.08), V(0.78, 0.42, 0.7), leaf)
		Kit.ell("Crown", ct + V(0, -0.08, -0.48), V(0.8, 0.5, 0.56), A.shade(leaf), nil, true)
		if f.blossom and full() then
			for _, p in { V(-0.36, 0.2, 0.42), V(0.3, 0.3, 0.38), V(0.1, 0.44, 0.1), V(-0.52, 0.04, -0.1), V(0.6, 0.06, 0.24) } do
				Kit.ell("Blossom", ct + p, V(0.1, 0.1, 0.1), f.blossom)
			end
		end
	end
	return t
end

PLANS.golem = function(b, a, form)
	local f: Form = form or {}
	local kind = f.kind
	if not kind then
		-- (a plan built in plain colours picks its kind from them)
		if b == "wood" or b == "wood_dark" or b == "steel" then
			kind = "tree"
		elseif b == "window" or b == "ice" or b == "snow" or b == "white" then
			kind = "ice"
		elseif (b == "black" or b == "basalt") and (a == "orange" or a == "lava") then
			kind = "basalt"
		else
			kind = "guard"
		end
	end
	if kind == "basalt" then
		return basaltGolem(b, a, f)
	elseif kind == "ice" then
		return iceGolem(b, a, f)
	elseif kind == "tree" then
		return treeGolem(b, a, f)
	end
	return guardGolem(b, a, f)
end

FORMS.elderbark = { style = "treant", kind = "tree", crown = "leaf", leaf = "leaf", blossom = "pink", faceDetail = { marks = { freckles = "moss" } } }
FORMS.basaltor = { kind = "basalt", glow = "orange" }
FORMS.glacior = { kind = "ice", snow = "white", deep = "ice" }
FORMS.sentinel = { kind = "guard", trim = "gold", dark = "rock_dark", moss = "moss" }
FORMS.silverbark = { style = "treant", kind = "tree", crown = "crystal", leaf = "crystal", leaf2 = "white", beard = "white", fruit = "white", h = 2.8, faceDetail = { marks = { freckles = "crystal", glow = true } } }

return { plans = PLANS, forms = FORMS }
