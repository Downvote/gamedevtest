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

------------------------------------------------------------------ bits the plans share
-- The four legs of a quadruped: name, side, hind or fore, phase in the stride.
local QUAD = {
	{ n = "FL", s = -1, hind = false, ph = 0 },
	{ n = "FR", s = 1, hind = false, ph = 0.5 },
	{ n = "BL", s = -1, hind = true, ph = 0.5 },
	{ n = "BR", s = 1, hind = true, ph = 0 },
}

local function lerp(a: Vector3, b: Vector3, u: number): Vector3
	return a + (b - a) * u
end

-- A radius `u` of the way along a list of them (spread evenly).
local function radiusAt(radii: { number }, u: number): number
	local n = #radii
	if n == 1 then
		return radii[1]
	end
	local x = math.clamp(u, 0, 1) * (n - 1)
	local i = math.min(math.floor(x), n - 2)
	return radii[i + 1] + (radii[i + 2] - radii[i + 1]) * (x - i)
end

-- Points along a curve in the middle plane going back from `root`: `n` steps over `len`, its slope going from `a0` to
-- `a1` (radians above level, backward; past 90 degrees it curls forward over the back).
local function arc(root: Vector3, len: number, a0: number, a1: number, n: number): { Vector3 }
	local pts = { root }
	local p = root
	for i = 1, n do
		local a = a0 + (a1 - a0) * (i - 0.5) / n
		p += V(0, math.sin(a), -math.cos(a)) * (len / n)
		table.insert(pts, p)
	end
	return pts
end

-- A tail along the smooth curve through `pts` (the root first) on two joints, "tail1" at the root and "tail2" halfway,
-- in `n` tapered links (half as many on the islands), its radius going through `radii`; `colorAt` picks each link's
-- colour from its number and how far along it sits (0 the root, 1 the tip). Returns the tip and the way it points;
-- the current joint stays "tail2", so a tuft or a flame added next rides on the tip.
local function tail(pts: { Vector3 }, radii: { number }, n: number, colorAt: (i: number, u: number) -> string, flat: number?, flatN: Vector3?): (Vector3, Vector3)
	local links = if full() then n else math.max(2, math.ceil(n / 2))
	J("tail1", "body", pts[1], "tail", 0, 1)
	local half = math.ceil(links / 2)
	local prev = pts[1]
	local before = prev
	for i = 1, links do
		local u0, u1 = (i - 1) / links, i / links
		if i == half + 1 then
			J("tail2", "tail1", prev, "tail", 0, 2)
		end
		local q = Kit.curveAt(pts, u1)
		local c = colorAt(i, (u0 + u1) / 2)
		Kit.limb("Tail", prev, q, radiusAt(radii, u0), radiusAt(radii, u1), c, flat, flatN)
		before = prev
		prev = q
	end
	return prev, (prev - before).Unit
end

-- A lock of fur, a flame or a spike: a cone from `root` along `dir`, `len` long, `w` across at the root, flattened
-- (its thin side toward `flatN`) unless `flat` is 1.
local function lock(name: string, root: Vector3, dir: Vector3, len: number, w: number, c: string, flatN: Vector3?, flat: number?, detail: boolean?, neon: boolean?)
	Kit.limb(name, root, root + dir.Unit * len, w, w * 0.12, c, flat or 0.55, flatN, detail, neon)
end

-- A soft lock of fur (a ruff, a fluffy chest, a puff's rim): like `lock` but its end rounded, not pointed.
local function fluff(name: string, root: Vector3, dir: Vector3, len: number, w: number, c: string, flatN: Vector3?, detail: boolean?)
	Kit.limb(name, root, root + dir.Unit * len, w, w * 0.42, c, 0.62, flatN, detail)
end

-- Whiskers, up close: `n` thin rods a side fanning out from either side of `at` (the middle of the muzzle's pads),
-- `spread` apart from the middle, `len` long.
local function whiskers(at: Vector3, spread: number, len: number, c: string, n: number?)
	if not full() then
		return
	end
	local m = n or 2
	for _, s in { -1, 1 } do
		for i = 1, m do
			local u = if m == 1 then 0 else (i - 1) / (m - 1) - 0.5
			local base = at + V(s * spread, -u * 0.06, 0)
			local d = (CFrame.Angles(0, 0, s * R(-u * 26)) * CFrame.Angles(0, s * R(8), 0)):VectorToWorldSpace(V(s, 0, 0))
			Kit.rod("Whisker", base, base + d * len, 0.05, c, true)
		end
	end
end

-- A little cloud: a flat-bottomed puff with two rounder ones on top (a sky fox's tail, a cloud bear's back).
local function cloud(name: string, at: Vector3, s: number, c: string, top: string?, detail: boolean?)
	Kit.ell(name, at, V(s * 1.6, s * 0.8, s * 1.2), c, nil, detail)
	Kit.ell(name, at + V(-s * 0.4, s * 0.32, s * 0.05), V(s * 0.95, s * 0.9, s * 0.9), top or c, nil, detail)
	Kit.ell(name, at + V(s * 0.36, s * 0.4, -s * 0.06), V(s * 1.05, s, s), top or c, nil, true)
end

-- A sparkle: three thin spindles crossed, so it reads as a star from any side.
local function sparkle(name: string, at: Vector3, s: number, c: string, neon: boolean?)
	local w = math.max(0.05, s * 0.22)
	Kit.ell(name, at, V(w, s, w), c, nil, nil, neon)
	Kit.ell(name, at, V(s * 0.8, w, w), c, nil, nil, neon)
	Kit.ell(name, at, V(w, w, s * 0.8), c, nil, true, neon)
end

-- A flat mark lying on a mass's surface toward `d`: `s` its size (across, thickness, up along the surface).
local function spot(name: string, m: A.Mass, d: Vector3, s: Vector3, c: string, neon: boolean?, detail: boolean?)
	local n = d.Unit
	Kit.ell(name, A.on(m, n), s, c, A.lie(n), detail, neon)
end

-- Where an ear made by A.ears with these numbers has its base and its tip, and the way it points (for tufts and
-- earrings on the ear's joint).
local function earAt(h: A.Head, side: number, at: number, back: number, w: number, len: number, out: number): (Vector3, Vector3, Vector3)
	local baseDir = (CFrame.Angles(0, 0, -side * R(at * 90)) * CFrame.Angles(R(-back), 0, 0)):VectorToWorldSpace(UP)
	local base = Kit.onEll(h.c, h.half, CFrame.identity, baseDir) - baseDir * w * 0.15
	local d = (baseDir + V(side * out, 0, 0) + V(0, 0, -math.sin(R(back)) * 0.6)).Unit
	return base, base + d * len, d
end

------------------------------------------------------------------ the pup (fox, wolf)
-- A young fox: a deep chest and slimmer hips, a big head with a long pointed muzzle and a black nose, tall pointed
-- ears with pale insides and dark tips, a pale bib, slim forelegs straight down to round paws, hind legs bending at
-- the hock, dark socks, a big brush of a tail with a pale tip. The form changes the size, the legs, the ears, the tail
-- and its tip (a flame, a cloud, a trail of stars), a ruff, glowing markings.
PLANS.pup = function(b, a, form)
	local f: Form = form or {}
	local k: number = f.k or 1
	local lk: number = f.legs or 1
	local wk: number = f.bulk or 1
	local hk: number = f.head or 1
	local lg: number = f.long or 1
	local lift = 0.84 * k * (lk - 1)
	local zf = (lg - 1) * 0.6
	local zb = (lg - 1) * 0.7
	local function P(x: number, y: number, z: number): Vector3
		return V(x * k, y * k + lift, z * k)
	end
	local t = Kit.new("pup", f.h or (2.2 * k + lift), f.r or 1.1 * k, "quad")
	local ink = A.ink(b, a)
	local under: string = f.under or A.under(b)
	local sock: string = f.sock or (if A.isDark(b) then a else "black")
	J("body", nil, P(0, 0.85, 0), "body")
	local _, body = A.body("Body", P(0, 0.92, -0.04 + (zf - zb) * 0.5), V(0, 0.12, 1).Unit, 1.32 * k * lg, 0.74 * k * wk, 0.7 * k * wk, 0.56, b)
	-- the bib and belly: a pale cap on the chest's front and underside
	A.patch("Bib", body, V(0, -0.35, 1), 0.86, 0.03, under)
	A.patch("Belly", body, V(0, -1, 0.15), V(0.72, 0.8, 0.7), 0.02, under, true)
	-- the neck, rising from the top of the chest
	local neckB = P(0, 1.3, 0.6 + zf)
	Kit.limb("Neck", P(0, 1.02, 0.42 + zf), neckB, 0.27 * k * wk, 0.23 * k * wk, b)
	if f.ruff then
		-- a thick ruff: a collar of fur round the neck, soft locks of it over the chest and back over the shoulders
		local rk: number = f.ruff * k
		local rc: string = f.ruffC or b
		local c0 = P(0, 1.2, 0.52 + zf)
		Kit.ell("Ruff", c0, V(0.92, 0.78, 0.74) * rk, rc, A.lie(V(0, 1, 0.7)))
		for _, sx in { -1, 0, 1 } do
			if full() then
				fluff("Ruff", c0 + V(sx * 0.2, -0.14, 0.22) * rk, V(sx * 0.35, -1, 0.3), 0.3 * rk, 0.15 * rk, rc, FWD)
			end
		end
		for _, s in { -1, 1 } do
			fluff("Ruff", c0 + V(s * 0.36, 0.02, 0) * rk, V(s * 0.7, -0.45, -0.6), 0.32 * rk, 0.16 * rk, rc, V(s, 0.3, 0))
			if full() then
				fluff("Ruff", c0 + V(s * 0.28, 0.26, -0.1) * rk, V(s * 0.6, 0, -0.8), 0.3 * rk, 0.14 * rk, rc, V(s, 0.5, 0))
			end
		end
	end
	-- legs: forelegs from the shoulders, hind legs from the haunches
	for _, l in QUAD do
		local z = if l.hind then -0.42 - zb else 0.36 + zf
		A.leg(l.n, l.s, l.ph, V(l.s * 0.22 * k * wk, 0.84 * k * lk, z * k), {
			kind = if l.hind then "hind" else "fore",
			mass = full(),
			r = (if l.hind then 0.13 else 0.115) * k * (f.legR or 1),
			c = b,
			sock = sock,
			fc = f.paw or sock,
			fw = 0.24 * k * (f.paws or 1),
			pad = f.pad or "pink",
			out = 0.02 * k,
		})
	end
	Kit.on("body")
	-- the tail: a slim root, then the brush, one long smooth oval of fur ending in a point of another colour
	local tr: number = (f.tailR or 0.17) * k
	local tl: number = (f.tailLen or 1.3) * k
	local tipC: string = f.tipC or under
	local up = R(f.tailUp or 24)
	local root = P(0, 1.0, -0.66 - zb)
	local d1 = V(0, math.sin(up), -math.cos(up))
	local a2 = up + R(f.curl or 40) * 0.6
	local dir = V(0, math.sin(a2), -math.cos(a2))
	local p1 = root + d1 * tl * 0.2
	J("tail1", "body", root, "tail", 0, 1)
	Kit.limb("Tail", root, p1, tr * 0.55, tr * 0.85, b)
	J("tail2", "tail1", p1, "tail", 0, 2)
	local L = tl * 0.84
	local trot = A.lie(dir)
	local tsz = V(tr * 3.1, L, tr * 3.0)
	local tc = p1 + dir * (L * 0.5 - tr * 0.7)
	Kit.egg("Tail", tc, tsz, 0.5, b, trot)
	-- the tip: an oval over the end of the brush, a little fuller than it, so the tip reads as a fluffy end of another
	-- colour (the picture draws a part over another only where it stands well clear of it)
	local tk: number = f.tipK or 0.62
	Kit.egg("TailTip", tc + dir * L * (0.53 - tk * 0.5), V(tsz.X * 1.06, L * tk, tsz.Z * 1.06), 0.5, tipC, trot)
	local tip = tc + dir * L * 0.5
	Kit.limb("TailTip", tip - dir * 0.16 * k, tip + dir * 0.1 * k, tr * 0.95, 0.02, tipC, nil, nil, true)
	local tpts = { root, p1, tc, tip }
	local side = UP:Cross(dir).Unit
	if f.tail == "flame" then
		-- the tip flickers up into tongues of flame
		local sides: { number } = if full() then { -1, 1 } else { 1 }
		for _, s in sides do
			lock("Flame", tip - dir * 0.34 * k + side * s * 0.1 * k, dir + UP * 0.25 + side * s * 0.7, 0.38 * k, 0.11 * k, tipC, nil, 1)
		end
		lock("Flame", tip - dir * 0.1 * k, dir + UP * 0.3, 0.3 * k, 0.09 * k, tipC, nil, 1)
	elseif f.tail == "cloud" then
		cloud("Cloud", tip - dir * 0.12 * k, 0.28 * k, tipC)
	elseif f.tail == "stars" then
		-- a trail of stars: sparkles of a shrinking size off the end of the tail and along it
		sparkle("Star", tip + dir * 0.22 * k + side * 0.06 * k, 0.42 * k, "white", true)
		if full() then
			sparkle("Star", Kit.curveAt(tpts, 0.8) + side * 0.34 * k + UP * 0.06 * k, 0.34 * k, "yellow", true)
			sparkle("Star", Kit.curveAt(tpts, 0.62) - side * 0.36 * k + UP * 0.04 * k, 0.26 * k, "white", true)
		end
	end
	Kit.on("body")
	if f.crystal then
		-- glowing crystal streaks down the shoulders
		for _, s in { -1, 1 } do
			spot("Mark", body, V(s, 0.55, 0.5), V(0.08, 0.05, 0.4) * k, a, true, true)
		end
	end
	-- the head
	local mlen: number = (f.mlen or 0.46) * k * hk
	local hsz: Vector3 = f.headS or V(1.02, 0.9, 0.9)
	local h = A.head({
		c = P(0, 1.66, 0.76 + zf),
		size = hsz * k * hk,
		color = b,
		pivot = neckB,
		muzzle = f.muzzle or "fox",
		mlen = mlen,
		mw = (f.mw or 0.36) * k * hk,
		mdrop = 0.15 * k * hk,
		nose = f.nose or ink,
		cheeks = if full() then under else nil,
		eye = { R(22), R(8), (f.eye or 0.28) * k * hk },
		iris = A.iris(a, "blue"),
		blush = f.blush ~= false and full(),
		whiskers = false,
		-- (its own dots of colour over the eyes in place of brows)
		face = A.more(if f.brows then { brows = false } else nil, f.faceDetail),
	})
	-- the pale underside of the muzzle
	local hs = k * hk
	Kit.limb("MuzzleUnder", h.c + V(0, -0.24 * hs, 0.3 * hs), h.c + V(0, -0.26 * hs, 0.3 * hs + mlen * 0.78), 0.13 * hs, 0.07 * hs, under, 0.7, UP, true)
	if f.crystal then
		-- a long diamond up the brow and a streak on each cheek, glowing
		spot("Mark", h.mass, V(0, 0.62, 0.78), V(0.1, 0.05, 0.36) * k, a, true)
		for _, s in { -1, 1 } do
			spot("Mark", h.mass, V(s, 0.02, 0.5), V(0.26, 0.05, 0.07) * k, a, true, true)
		end
	end
	if f.brows then
		-- two dots of colour over the eyes
		for _, s in { -1, 1 } do
			spot("Brow", h.mass, V(s * 0.34, 0.6, 0.76), V(0.11, 0.05, 0.08) * k, f.brows)
		end
	end
	local e: Form = f.ears or {}
	local earTip: string? = if f.earTip == false then nil else (f.earTip or sock)
	A.ears(h, {
		kind = e.kind or "fox",
		len = (e.len or 0.56) * hs,
		w = (e.w or 0.36) * hs,
		at = e.at or 0.36,
		back = e.back or 6,
		out = e.out,
		c = b,
		inner = if full() then (f.earIn or under) else nil,
		tip = if earTip == b then nil else earTip,
	})
	return t
end

-- Emberpup: the plain young fox, its tail tip a yellow flame.
FORMS.emberpup = { tail = "flame", tipC = "yellow", tipK = 0.7, faceDetail = { marks = { freckles = "yellow", glow = true } } }
-- Skyfox: white cloud socks and bib, a cloud at the tail's tip.
FORMS.skyfox = { tail = "cloud", tipC = "white", under = "white", sock = "white", earTip = "jeans", tipK = 0.62, faceDetail = { marks = { blaze = "white" } } }
-- Novafox: a purple tail tip trailing stars.
FORMS.novafox = { tail = "stars", tipC = "purple", sock = "orange", earTip = "purple", tailLen = 1.4, curl = 50, faceDetail = { marks = { star = "white", glow = true } } }
-- Hushpup: long, low and sleek, ears laid back, a slim tail, big soft crystal paws and two dots over the eyes.
FORMS.hushpup = { long = 1.1, bulk = 0.86, legs = 1.04, sock = "black", paw = "crystal", paws = 1.3, pad = "pink", tailR = 0.13, tailLen = 1.45, tailUp = 10, curl = 24, tipC = "crystal", tipK = 0.62, brows = "crystal", earTip = false, ears = { len = 0.52, w = 0.34, back = 22 } }
-- Sandkit: a fennec, small with huge ears and a black tail tip.
FORMS.sandkit = { k = 0.84, head = 1.12, sock = "sand", tipC = "black", tipK = 0.62, earTip = false, h = 2.35, ears = { len = 0.86, w = 0.58, at = 0.36, back = 4 } }
-- Rimekit: an arctic fox, chunky and fluffy, short round ears, a soft ruff and a thick tail.
FORMS.rimekit = { bulk = 1.2, legs = 0.85, ruff = 1, sock = "white", earIn = "ice", earTip = false, tailR = 0.23, tailLen = 1.2, tipC = "white", ears = { kind = "long", len = 0.32, w = 0.34, at = 0.36, out = 0.4 } }
-- Moonhowl: a wolf, bigger, long-legged, a heavy slate ruff, a longer head and muzzle, glowing crystal markings.
FORMS.moonhowl = { k = 1.16, legs = 1.22, ruff = 1.15, ruffC = "slate", muzzle = "dog", mlen = 0.52, mw = 0.38, headS = V(0.96, 0.86, 0.98), eye = 0.25, blush = false, sock = "night", tipC = "slate", tipK = 0.62, tailUp = 4, curl = 22, tailLen = 1.4, crystal = true, earTip = false, ears = { len = 0.5, w = 0.4, at = 0.34, back = 8 } }

------------------------------------------------------------------ the cat (cat, lynx, lion)
-- A cat: a long lithe body, its chest a little deeper than its hips, a round head with a short muzzle of two puffy
-- whisker pads, a small pink nose and whiskers, triangular ears set wide, slim legs (the forelegs straight, the hind
-- ones bending at the hock) on small round paws, a long tail held up and curling at the tip. The form gives a lynx its
-- ear tufts, cheek ruffs and bobtail, a lion its mane and tail tuft, a kitten its big head.
PLANS.cat = function(b, a, form)
	local f: Form = form or {}
	local k: number = f.k or 1
	local lk: number = f.legs or 1
	local wk: number = f.bulk or 1
	local hk: number = f.head or 1
	local lg: number = f.long or 1
	local ny: number = f.neck or 0
	local lift = 0.68 * k * (lk - 1)
	local zf = (lg - 1) * 0.6
	local zb = (lg - 1) * 0.7
	local function P(x: number, y: number, z: number): Vector3
		return V(x * k, y * k + lift, z * k)
	end
	local t = Kit.new("cat", f.h or ((1.95 + ny) * k + lift), f.r or 1.05 * k, "quad")
	local under: string = f.under or A.under(b)
	local sock: string = f.sock or b
	local pad: string = f.pad or (if A.isDark(b) then a else "pink")
	J("body", nil, P(0, 0.74, 0), "body")
	local _, body = A.body("Body", P(0, 0.8, -0.06 + (zf - zb) * 0.5), V(0, 0.06, 1).Unit, 1.26 * k * lg, 0.6 * k * wk, 0.6 * k * wk, 0.54, b)
	A.patch("Chest", body, V(0, -0.4, 1), 0.84, 0.03, under)
	A.patch("Belly", body, V(0, -1, 0.1), V(0.7, 0.82, 0.7), 0.02, under, true)
	local neckA, neckB = P(0, 0.9, 0.38 + zf), P(0, 1.14 + ny, 0.54 + zf)
	Kit.limb("Neck", neckA, neckB, 0.23 * k * wk, 0.2 * k * wk, b)
	if f.collar then
		-- a broad gold collar round the neck, a drop hanging at its front
		local nd = (neckB - neckA).Unit
		local cc = lerp(neckA, neckB, 0.42)
		Kit.ell("Collar", cc, V(0.5, 0.11, 0.5) * k, f.collar, A.lie(nd))
		local front = (FWD - nd * FWD:Dot(nd)).Unit
		Kit.ell("Drop", cc + front * 0.24 * k - nd * 0.08 * k, V(0.12, 0.15, 0.07) * k, f.collar, nil, true)
	end
	if f.chestRuff then
		-- a fluffy bib of fur on the chest
		local c0 = P(0, 0.96, 0.52 + zf)
		Kit.ell("Ruff", c0, V(0.62, 0.58, 0.46) * k, under, A.lie(V(0, 1, 0.6)))
		for _, sx in { -1, 0, 1 } do
			if sx == 0 or full() then
				fluff("Ruff", c0 + V(sx * 0.15, -0.14, 0.14) * k, V(sx * 0.35, -1, 0.35), 0.24 * k, 0.13 * k, under, FWD)
			end
		end
	end
	if f.galaxy then
		-- galaxies in its fur: glowing spots on the back and flanks, tiny stars between them up close
		for i, d in { V(0.75, 0.6, 0.25), V(-0.78, 0.5, -0.1), V(0.55, 0.8, -0.45), V(-0.5, 0.8, 0.4), V(0.85, 0.2, -0.3), V(-0.85, 0.25, 0.35) } do
			if i <= 2 or full() then
				spot("Galaxy", body, d, V(0.17, 0.05, 0.13) * k * (1.1 - i * 0.06), f.galaxy, true)
			end
		end
		if full() then
			for _, d in { V(0.7, 0.7, -0.05), V(-0.7, 0.68, 0.15), V(0.3, 0.95, 0.15) } do
				sparkle("Star", A.on(body, d) + d.Unit * 0.03, 0.12 * k, "white", true)
			end
		end
	end
	-- slim legs: the forelegs straight down under the shoulders, the hind legs bending back at the hock
	for _, l in QUAD do
		local z = if l.hind then -0.42 - zb else 0.34 + zf
		A.leg(l.n, l.s, l.ph, V(l.s * 0.17 * k * wk, 0.68 * k * lk, z * k), {
			kind = if l.hind then "hind" else "fore",
			mass = full(),
			r = (if l.hind then 0.12 else 0.1) * k * (f.legR or 1),
			c = b,
			sock = sock,
			fc = f.paw or sock,
			fw = 0.22 * k * (f.paws or 1),
			pad = pad,
			out = 0.01 * k,
		})
	end
	Kit.on("body")
	-- the tail
	local tk: string = f.tail or "long"
	local tipC: string? = f.tipC
	local tipAt: number = f.tipAt or 0.78
	local function col(_i: number, u: number): string
		return if tipC and u > tipAt then tipC else b
	end
	local root = P(0, 0.9, -0.6 - zb)
	local tip, dir
	if tk == "long" then
		tip, dir = tail(arc(root, 1.5 * k, R(25), R(150), 4), { 0.09 * k, 0.085 * k, 0.075 * k, 0.065 * k }, 6, col)
	elseif tk == "kitten" then
		tip, dir = tail(arc(root, 0.8 * k, R(60), R(100), 3), { 0.1 * k, 0.09 * k, 0.075 * k }, 3, col)
	elseif tk == "bob" then
		tip, dir = tail(arc(root, 0.38 * k, R(35), R(60), 2), { 0.13 * k, 0.14 * k, 0.09 * k }, 2, col)
	else
		-- a lion's: hanging in a low curve, rising to the tuft
		tip, dir = tail({ root, root + V(0, -0.16, -0.36) * k, root + V(0, -0.26, -0.7) * k, root + V(0, -0.12, -1.0) * k, root + V(0, 0.1, -1.14) * k }, { 0.09 * k, 0.08 * k, 0.07 * k }, 4, col)
	end
	if f.tuft == "flame" then
		local sides: { number } = if full() then { -1, 0, 1 } else { 0 }
		for _, s in sides do
			lock("TailFlame", tip - dir * 0.06 * k, dir + V(s * 0.6, 0.8, 0), (if s == 0 then 0.36 else 0.26) * k, 0.1 * k, if s == 0 then a else "yellow", nil, 1)
		end
	elseif f.tuft then
		Kit.egg("TailTuft", tip + dir * 0.08 * k, V(0.24, 0.36, 0.24) * k, 0.62, f.tuft, A.lie(dir))
	end
	if f.tailStar then
		sparkle("Star", tip + dir * 0.14 * k, 0.3 * k, f.tailStar, true)
	end
	if f.ember then
		-- the tip glows like a coal
		Kit.ell("Ember", tip + dir * 0.02 * k, V(0.12, 0.12, 0.12) * k, "lava", nil, nil, true)
	end
	Kit.on("body")
	-- the head
	local s1 = k * hk
	local hc = P(0, 1.44 + ny, 0.68 + zf)
	local hs = V(1.0, 0.88, 0.84) * s1
	local mlen, mw, mdrop = 0.22 * s1, 0.42 * s1, 0.15 * s1
	local h = A.head({
		c = hc,
		size = hs,
		color = b,
		pivot = neckB,
		muzzle = "cat",
		mlen = mlen,
		mw = mw,
		mdrop = mdrop,
		mc = f.mc or b,
		nose = f.nose,
		eye = { R(24), R(6), 0.29 * s1 },
		iris = A.iris(a, "green"),
		blush = f.blush ~= false and full(),
		cheeks = f.cheeks,
		ink = if A.isDark(b) then a else nil,
		whiskers = false,
		-- (a lynx's own cheek ruffs in place of the tufts)
		face = A.more(if f.ruffs then { cheeks = false } else nil, f.faceDetail),
	})
	-- whiskers from the pads (A.head's muzzle "cat": the pads either side of `mroot`)
	local pr = mw * 0.34
	local mroot = hc + V(0, -mdrop, hs.Z * 0.275)
	whiskers(mroot + V(0, -pr * 0.1, mlen * 0.45 + pr * 0.5), pr * 1.3, 0.24 * s1, f.whiskerC or "white")
	if f.ruffs then
		-- cheek ruffs: pointed locks of fur standing out from the sides of the face
		for _, s in { -1, 1 } do
			for i = 1, f.ruffs do
				if (i == 1 and f.ruffs > 1) or full() then
					lock("Ruff", hc + V(s * hs.X * 0.42, -hs.Y * (0.08 + i * 0.13), -hs.Z * 0.06), V(s, -0.55 - i * 0.15, -0.3), 0.28 * s1, 0.13 * s1, f.ruffC or b, FWD)
				end
			end
		end
	end
	local mc: string = f.maneC or a
	if f.mane == "puff" then
		-- a dandelion clock of a mane: a round puff behind the head, its rim in soft tufts, a seed or two blowing off
		local c0 = hc + V(0, 0.02, -0.42) * s1
		local ms = V(1.42, 1.38, 0.7) * s1
		Kit.ell("Mane", c0, ms, mc)
		local n = if full() then 12 else 4
		for i = 0, n - 1 do
			local ang = i / n * math.pi * 2 + 0.26
			local dd = V(math.cos(ang), math.sin(ang), 0)
			fluff("Seed", c0 + V(dd.X * ms.X * 0.43, dd.Y * ms.Y * 0.43, 0), dd + V(0, 0, -0.2), 0.14 * s1, 0.1 * s1, mc, FWD)
		end
		if full() then
			for i, p in { V(0.9, 0.5, -0.66), V(1.16, 0.86, -0.96) } do
				local at = hc + p * s1
				local sz = (1 - i * 0.25) * s1
				Kit.limb("SeedStalk", at - V(0.08, 0.1, 0) * sz, at, 0.025 * sz, 0.02 * sz, "cream")
				Kit.ell("SeedPuff", at + V(0.02, 0.03, 0) * sz, V(0.16, 0.12, 0.16) * sz, mc)
			end
		end
	elseif f.mane == "flame" then
		-- a mane of fire: a ring of flame points leaning up and back, red outside, yellow inside
		local c0 = hc + V(0, 0.02, -0.38) * s1
		Kit.ell("Mane", c0, V(1.2, 1.16, 0.52) * s1, mc)
		local n = if full() then 10 else 4
		for i = 0, n - 1 do
			local ang = (i + 0.5) / n * math.pi * 2 - math.pi / 2
			local dd = V(math.cos(ang), math.sin(ang), 0)
			lock("Flame", c0 + V(dd.X * 0.48, dd.Y * 0.46, 0) * s1, dd + V(0, 0.7, -0.4), 0.5 * s1, 0.16 * s1, mc, FWD)
			if full() then
				local ang2 = ang + math.pi / n
				local d2 = V(math.cos(ang2), math.sin(ang2), 0)
				lock("Flame", c0 + V(d2.X * 0.46, d2.Y * 0.44, 0.12) * s1, d2 + V(0, 0.6, -0.2), 0.34 * s1, 0.09 * s1, "yellow", FWD)
			end
		end
	elseif f.mane == "full" then
		-- a full mane: a great ruff round the head, soft locks falling from its rim, a bib of it down the chest
		local c0 = hc + V(0, -0.06, -0.36) * s1
		local ms = V(1.56, 1.5, 0.66) * s1
		Kit.ell("Mane", c0, ms, mc)
		Kit.egg("ManeBib", hc + V(0, -0.52, -0.22) * s1, V(0.82, 0.74, 0.56) * s1, 0.62, mc, CFrame.Angles(math.pi, 0, 0))
		local n = if full() then 7 else 4
		for i = 0, n - 1 do
			local ang = R(-30 + i * 240 / (n - 1))
			local dd = V(math.cos(ang), math.sin(ang), 0)
			fluff("Mane", c0 + V(dd.X * ms.X * 0.38, dd.Y * ms.Y * 0.38, -ms.Z * 0.1), dd + V(0, -0.8, -0.9), 0.3 * s1, 0.22 * s1, if i % 2 == 1 then A.shade(mc) else mc, FWD)
		end
	end
	local e: Form = f.ears or {}
	local ek: string = e.kind or "cat"
	local elen: number = (e.len or 0.44) * s1
	local ew: number = (e.w or 0.42) * s1
	local eat: number = e.at or 0.42
	local eback: number = e.back or 4
	A.ears(h, { kind = ek, len = elen, w = ew, at = eat, back = eback, c = b, inner = if full() then (f.earIn or (if ek == "round" then under else "pink")) else nil, tip = f.earTip })
	if f.tufts or f.earrings then
		for _, s in { -1, 1 } do
			local base, tp, du = earAt(h, s, eat, eback, ew, elen, 0.35)
			Kit.on("ear" .. (if s < 0 then "L" else "R"))
			if f.tufts then
				-- a lynx's tuft: a long thin point standing off the tip
				Kit.limb("Tuft", tp - du * 0.05 * s1, tp + (du + V(s * 0.12, 0.15, -0.1)).Unit * 0.28 * s1, 0.055 * s1, 0.015 * s1, f.tufts, nil, nil, nil, f.tuftNeon)
			end
			if f.earrings then
				-- a gold hoop hanging from the outer edge of the ear's base
				Kit.ell("Earring", base + V(s * ew * 0.52, -0.12 * s1, 0.06 * s1), V(0.07, 0.18, 0.16) * s1, f.earrings, nil, true)
			end
		end
		Kit.on("head")
	end
	return t
end

-- Nebulynx: a big long-legged lynx, glowing tufts, cheek ruffs, galaxy spots and a star at its tail's tip.
FORMS.nebulynx = { k = 1.12, legs = 1.14, tufts = "screen_on", tuftNeon = true, ruffs = 1, galaxy = "screen_on", tail = "long", tipC = "night", tailStar = "screen_on", ears = { len = 0.5, w = 0.42 }, faceDetail = { marks = { freckles = "screen_on", glow = true } } }
-- Cinderkit: a black kitten, big-headed, orange paws and ear insides, its short tail tipped with a glowing coal.
FORMS.cinderkit = { k = 0.86, head = 1.14, legs = 0.9, sock = "orange", paw = "orange", pad = "yellow", earIn = "orange", tail = "kitten", tipC = "orange", tipAt = 0.6, ember = true, mc = "basalt" }
-- Thistlemane: a lion cub, round ears in a white dandelion puff of a mane, a white tail tuft.
FORMS.thistlemane = { style = "lion", k = 0.92, head = 1.08, mane = "puff", maneC = "white", tail = "lion", tuft = "white", mc = "cream", ears = { kind = "round", w = 0.28, at = 0.4 } }
-- Blazemane: a lion whose mane and tail tuft are fire.
FORMS.blazemane = { style = "lion", k = 1.06, mane = "flame", maneC = "berry_red", tail = "lion", tuft = "flame", mc = "cream", ears = { kind = "round", w = 0.26, at = 0.42 }, faceDetail = { marks = { blaze = "yellow" } } }
-- Frostlynx: chunky and fluffy, big paws, white cheek ruffs and a chest ruff, tufts, a bobtail.
FORMS.frostlynx = { bulk = 1.18, paws = 1.45, legR = 1.2, tufts = "white", ruffs = 2, ruffC = "white", chestRuff = true, under = "white", tail = "bob", tipC = "white", tipAt = 0.5, mc = "white", faceDetail = { marks = { freckles = "white" } } }
-- Tombcat: slim and tall, huge upright ears, a gold collar and gold earrings, a long thin tail.
FORMS.tombcat = { bulk = 0.84, long = 1.06, legs = 1.2, head = 0.94, collar = "gold", earrings = "gold", tail = "long", ears = { len = 0.66, w = 0.44, at = 0.34, back = 2 }, faceDetail = { marks = { kohl = "black" } } }
-- Gildmane: a regal lion, head held high in a full sand mane, a sand tail tuft.
FORMS.gildmane = { style = "lion", k = 1.14, legs = 1.1, neck = 0.1, mane = "full", maneC = "sand", tail = "lion", tuft = "sand", mc = "cream", ears = { kind = "round", w = 0.26, at = 0.42 } }

------------------------------------------------------------------ the bear
-- A bear cub: a heavy round body low to the ground with a hump over the shoulders, a big round head with a short
-- snout of a paler colour and a black nose, round ears, short thick post legs on broad padded feet with little claws,
-- a stub of a tail.
PLANS.bear = function(b, a, form)
	local f: Form = form or {}
	local k: number = f.k or 1
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	local t = Kit.new("bear", f.h or 2.0 * k, 1.2 * k, "quad")
	local ink = A.ink(b, a)
	local under: string = f.under or A.under(b)
	J("body", nil, P(0, 0.72, 0), "body")
	local _, body = A.body("Body", P(0, 0.78, -0.08), V(0, 0.1, 1).Unit, 1.32 * k, 0.98 * k, 0.88 * k, 0.47, b)
	-- the hump of muscle over the shoulders
	Kit.ell("Hump", P(0, 1.06, 0.16), V(0.78, 0.48, 0.6) * k, b)
	A.patch("Belly", body, V(0, -1, 0.2), V(0.78, 0.82, 0.76), 0.02, under, true)
	Kit.limb("Neck", P(0, 0.92, 0.4), P(0, 1.1, 0.58), 0.34 * k, 0.3 * k, b)
	if f.moon then
		-- a crescent moon on the chest, glowing
		local cn = V(0, 0.05, 1).Unit
		local c0 = A.on(body, cn) + cn * 0.02 * k
		local pts = {}
		for i = 0, 4 do
			local ang = R(105 + i * 37)
			local p = c0 + V(math.cos(ang) * 0.2, math.sin(ang) * 0.22, 0) * k
			table.insert(pts, p)
		end
		Kit.limbs("Moon", pts, { 0.035 * k, 0.085 * k, 0.035 * k }, f.moon, 4, 0.4, cn, nil, true)
	end
	if f.clouds then
		-- storm clouds riding on its back: grey bellies, white tops
		cloud("Cloud", P(0.06, 1.26, 0.18), 0.28 * k, f.clouds, b)
		if full() then
			cloud("Cloud", P(-0.1, 1.14, -0.46), 0.24 * k, f.clouds, b)
		end
	end
	if f.stars then
		-- tiny crystal stars on the back and shoulders
		for i, d in { V(0.62, 0.7, 0.3), V(-0.65, 0.66, 0.1), V(0.3, 0.9, -0.3) } do
			if i == 1 or full() then
				sparkle("Star", A.on(body, d) + d.Unit * 0.03, 0.18 * k, f.stars, true)
			end
		end
	end
	-- legs: short thick posts on broad round feet
	for _, l in QUAD do
		A.leg(l.n, l.s, l.ph, P(l.s * 0.3, 0.52, if l.hind then -0.44 else 0.36), {
			kind = "post",
			mass = full(),
			r = 0.17 * k,
			c = b,
			foot = "pad",
			fw = 0.38 * k,
			claw = f.claw or (if A.isDark(b) then a else "cream"),
			massSize = V(0.46, 0.5, 0.52) * k,
		})
	end
	Kit.on("body")
	A.tail(P(0, 0.86, -0.76), { kind = if f.puffTail then "puff" else "stub", r = 0.13 * k, c = b })
	Kit.on("body")
	local h = A.head({
		c = P(0, 1.38, 0.76),
		size = V(1.08, 0.96, 0.92) * k,
		color = b,
		pivot = P(0, 1.1, 0.58),
		muzzle = "dog",
		mlen = 0.24 * k,
		mw = 0.46 * k,
		mh = 0.34 * k,
		mdrop = 0.18 * k,
		mc = f.mc or under,
		nose = f.nose or ink,
		eye = { R(25), R(12), 0.26 * k },
		iris = A.iris(a, "wood"),
		blush = full(),
		ink = if A.isDark(b) then a else nil,
		face = A.more(nil, f.faceDetail),
	})
	A.ears(h, { kind = "round", w = 0.34 * k, at = 0.48, back = 8, c = b, inner = if full() then (f.earIn or under) else nil })
	if f.headCloud then
		cloud("Cloud", h.top + V(0.04, 0.0, -0.08) * k, 0.2 * k, f.headCloud, b, true)
	end
	if f.cap then
		-- a nightcap: a soft cone flopping over to one side, a white bobble on its end
		local base = h.top + V(0, -0.1, -0.04) * k
		local pts = { base, base + P(0.02, 0.24, -0.06), base + P(0.18, 0.38, -0.16), base + P(0.4, 0.24, -0.2) }
		if full() then
			Kit.rod("CapBand", base - UP * 0.02 * k, base + UP * 0.08 * k, 0.56 * k, "white")
		end
		Kit.limbs("Cap", pts, { 0.26 * k, 0.15 * k, 0.05 * k }, f.cap, 3)
		Kit.ell("Bobble", pts[4] + P(0.04, -0.06, 0), V(0.2, 0.2, 0.2) * k, "white")
	end
	return t
end

-- Billowbear: big and white, storm clouds with slate bellies riding its back, a puff of a tail, slate nose and claws.
FORMS.billowbear = { k = 1.2, h = 2.5, clouds = "slate", headCloud = "slate", puffTail = true, nose = "slate", claw = "slate", earIn = "slate", mc = "white" }
-- Duskbear: night blue, a glowing crescent moon on its chest, crystal stars on its back, a nightcap for the winter.
FORMS.duskbear = { k = 0.96, moon = "crystal", stars = "crystal", cap = "crystal", earIn = "crystal" }

------------------------------------------------------------------ the otter (otter, weasel)
-- An otter: a long low body, short legs, a thick tail tapering to a point and lying low, a flat broad head on a thick
-- neck, small round ears low on the sides, a wide muzzle of whisker pads with a big dark nose and whiskers.
-- A sea otter sitting up: a pear of a body leaning back a little, short legs on big flat feet, the forepaws held to
-- the chest round a shell, a big round head with a pale face, a thick tail lying flat on the ground behind.
local function seaOtter(b: string, a: string, f: Form): Kit.Thing
	local k: number = f.k or 1
	local hk: number = f.head or 1
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	local t = Kit.new("otter", f.h or 1.9 * k, 1.0 * k, "biped")
	local face: string = f.headC or b
	J("body", nil, P(0, 0.7, 0), "body")
	local bc, bs = P(0, 0.72, -0.04), V(0.78, 0.98, 0.66) * k * (f.bulk or 1)
	local brot = CFrame.Angles(R(-8), 0, 0)
	Kit.egg("Body", bc, bs, 0.55, b, brot)
	local torso: A.Mass = { c = bc, size = bs, rot = brot, split = 0.55 }
	A.patch("Belly", torso, V(0, -0.1, 1), V(0.84, 0.86, 0.84), 0.02, A.shade(face))
	-- the shell, held to the chest
	local n = V(0, 0.35, 1).Unit
	local srot = A.lie(n)
	local sc = A.on(torso, V(0, 0.15, 1)) + n * 0.06 * k
	local across, upward = srot.XVector, srot.ZVector
	Kit.ell("Shell", sc, V(0.44, 0.08, 0.38) * k, f.shell or "pink", srot)
	local hinge = sc - upward * 0.18 * k + n * 0.02 * k
	if full() then
		for _, s in { -0.7, 0, 0.7 } do
			Kit.limb("ShellRib", hinge, sc + upward * 0.16 * k + across * s * 0.16 * k + n * 0.04 * k, 0.025 * k, 0.035 * k, A.shade(f.shell or "pink"))
		end
	end
	Kit.ell("Hinge", hinge, V(0.14, 0.08, 0.08) * k, A.shade(f.shell or "pink"), srot)
	-- short legs: a round haunch, the shin, a big flat foot
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("leg" .. nm, "body", P(s * 0.22, 0.4, -0.04), "leg", s, if s < 0 then 0 else 0.5)
		Kit.ell("Haunch" .. nm, P(s * 0.24, 0.36, -0.02), V(0.34, 0.4, 0.44) * k, b)
		Kit.limb("Leg" .. nm, P(s * 0.25, 0.3, 0.06), P(s * 0.27, 0.1, 0.06), 0.11 * k, 0.09 * k, b)
		Kit.limb("Foot" .. nm, P(s * 0.27, 0.06, 0.02), P(s * 0.31, 0.05, 0.3), 0.08 * k, 0.12 * k, b, 0.5, UP)
		if full() then
			for _, dx in { -0.07, 0, 0.07 } do
				Kit.ell("Toe" .. nm, P(s * 0.31 + dx, 0.05, 0.38), V(0.07, 0.06, 0.07) * k, A.shade(b))
			end
		end
	end
	-- the arms: down from the shoulder, the forearm folded in, the paws on the shell's rim
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("arm" .. nm, "body", P(s * 0.28, 1.02, 0.06), "arm", s)
		local sh, el = P(s * 0.29, 1.0, 0.06), P(s * 0.34, 0.78, 0.16)
		local paw = sc + across * s * 0.2 * k + upward * 0.04 * k + n * 0.06 * k
		Kit.limb("Arm" .. nm, sh, el, 0.11 * k, 0.09 * k, b)
		Kit.limb("Arm" .. nm, el, paw, 0.09 * k, 0.08 * k, b)
		Kit.ell("Paw" .. nm, paw, V(0.15, 0.14, 0.13) * k, b)
	end
	Kit.on("body")
	-- the tail: thick, flat, lying on the ground behind
	local tr: number = (f.tailR or 0.2) * k
	tail({ P(0, 0.36, -0.3), P(0, 0.16, -0.66), P(0, 0.11, -1.0), P(0, 0.13, -1.26) }, { tr, tr * 0.8, tr * 0.45, tr * 0.12 }, 3, function()
		return b
	end, 0.55, UP)
	Kit.on("body")
	-- the head: big and round on a short neck, the face pale
	Kit.limb("Neck", P(0, 1.04, 0), P(0, 1.18, 0.04), 0.3 * k, 0.28 * k, b)
	local s1 = k * hk
	local hc = P(0, 1.44, 0.08)
	local hs = V(0.94, 0.8, 0.82) * s1
	local mlen, mw, mdrop = 0.2 * s1, 0.48 * s1, 0.12 * s1
	local h = A.head({
		c = hc,
		size = hs,
		color = face,
		pivot = P(0, 1.16, 0.02),
		muzzle = "cat",
		mlen = mlen,
		mw = mw,
		mdrop = mdrop,
		mc = face,
		nose = "black",
		eye = { R(26), R(10), 0.25 * s1 },
		iris = A.iris(a, "wood_dark"),
		blush = full(),
		whiskers = false,
		face = A.more(nil, f.faceDetail),
	})
	local pr = mw * 0.34
	whiskers(hc + V(0, -mdrop - pr * 0.1, hs.Z * 0.275 + mlen * 0.45 + pr * 0.5), pr * 1.3, 0.2 * s1, "white")
	A.ears(h, { kind = "round", w = 0.17 * s1, at = 0.6, back = 12, c = b, inner = if full() then A.shade(b) else nil })
	return t
end

PLANS.otter = function(b, a, form)
	local f: Form = form or {}
	if f.sit then
		return seaOtter(b, a, f)
	end
	local k: number = f.k or 1
	local wk: number = f.bulk or 1
	local lg: number = f.long or 1
	local hk: number = f.head or 1
	local rear = f.rear == true
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	local t = Kit.new("otter", f.h or (if rear then 1.75 else 1.55) * k, 1.2 * k, "quad")
	local under: string = f.under or A.under(b)
	local zf = (lg - 1) * 0.75
	-- (a sea otter stands with its chest raised, so the shell it holds shows under its chin)
	local up = if rear then 0.12 else 0
	J("body", nil, P(0, 0.6, 0), "body")
	local _, body = A.body("Body", P(0, 0.62 + up * 0.5, -0.1), V(0, if rear then 0.34 else (f.arch or 0.05), 1).Unit, 1.6 * k * lg, 0.62 * k * wk, 0.56 * k * wk, 0.5, b)
	A.patch("Belly", body, V(0, -1, 0.3), V(0.74, 0.86, 0.7), 0.02, under)
	local neckB = P(0, 0.92 + up * 2, 0.82 + zf - up)
	Kit.limb("Neck", P(0, 0.68 + up, 0.55 + zf - up * 0.5), neckB, 0.26 * k * wk, 0.23 * k * wk, f.throat or b)
	if f.shell then
		-- a scallop shell held to its chest: a fan of ribs on a little hinge
		local n = V(0, 0.4, 1).Unit
		local rot = A.lie(n)
		local sc = A.on(body, n) + n * 0.04 * k
		local across, upward = rot.XVector, rot.ZVector
		Kit.ell("Shell", sc, V(0.42, 0.08, 0.36) * k, f.shell, rot)
		local hinge = sc - upward * 0.17 * k + n * 0.02 * k
		if full() then
			for _, s in { -0.7, 0, 0.7 } do
				Kit.limb("ShellRib", hinge, sc + upward * 0.15 * k + across * s * 0.15 * k + n * 0.04 * k, 0.025 * k, 0.035 * k, A.shade(f.shell))
			end
		end
		Kit.ell("Hinge", hinge, V(0.14, 0.08, 0.08) * k, A.shade(f.shell), rot)
	end
	if f.clouds then
		cloud("Cloud", P(0, 0.92, -0.12), 0.22 * k, f.clouds, nil)
	end
	-- short legs: forelegs under the chest, hind legs bending at the hock
	for _, l in QUAD do
		local z = if l.hind then -0.56 * lg else 0.46 + zf - up
		A.leg(l.n, l.s, l.ph, P(l.s * 0.2 * wk, if l.hind then 0.5 else 0.5 + up * 1.2, z), {
			kind = if l.hind then "hind" else "fore",
			r = (if l.hind then 0.11 else 0.1) * k,
			c = b,
			sock = f.sock,
			fc = f.sock or b,
			fw = 0.22 * k,
			pad = A.shade(f.sock or b),
			out = 0.03 * k,
		})
	end
	Kit.on("body")
	-- the tail: thick at the root, flattened a little, tapering to a point
	local tr: number = (f.tailR or 0.2) * k
	local r0 = P(0, 0.6, -0.82 * lg)
	local tip, dir = tail({ r0, r0 + P(0, -0.12, -0.38), r0 + P(0, -0.22, -0.74), r0 + P(0, -0.22, -1.04), r0 + P(0, -0.14, -1.3) }, { tr, tr * 0.85, tr * 0.6, tr * 0.32, tr * 0.12 }, 4, function(_i, u)
		return if f.tipC and u > 0.75 then f.tipC else b
	end, 0.78, UP)
	if f.tailCloud then
		cloud("Cloud", tip + dir * 0.06 * k + V(0, 0.04, 0) * k, 0.2 * k, f.tailCloud)
	end
	Kit.on("body")
	local s1 = k * hk
	local hc = P(0, 1.06 + up * 2.4, 1.02 + zf - up * 1.4)
	local hs = V(0.86, 0.64, 0.74) * s1
	local mk: string = f.muzzle or "cat"
	local mlen, mw, mdrop = (f.mlen or 0.2) * s1, 0.46 * s1, 0.1 * s1
	local h = A.head({
		c = hc,
		size = hs,
		color = f.headC or b,
		pivot = neckB,
		muzzle = mk,
		mlen = mlen,
		mw = mw,
		mdrop = mdrop,
		mc = f.mc or f.headC or b,
		nose = f.nose or "black",
		cheeks = f.cheeks,
		eye = { R(28), R(12), 0.24 * s1 },
		iris = A.iris(a, "wood_dark"),
		blush = full(),
		whiskers = false,
		face = A.more(nil, f.faceDetail),
	})
	local mroot = hc + V(0, -mdrop, hs.Z * 0.275)
	if mk == "cat" then
		local pr = mw * 0.34
		whiskers(mroot + V(0, -pr * 0.1, mlen * 0.45 + pr * 0.5), pr * 1.3, 0.2 * s1, f.whiskerC or "white")
	else
		whiskers(mroot + V(0, -0.02 * s1, mlen * 0.6), mw * 0.3, 0.18 * s1, f.whiskerC or "white")
	end
	A.ears(h, { kind = "round", w = 0.17 * s1, at = 0.62, back = 14, c = b, inner = if full() then A.shade(b) else nil })
	if f.headCloud then
		cloud("Cloud", h.top + V(0, 0.0, -0.08) * k, 0.14 * k, f.headCloud, nil, true)
	end
	return t
end

-- Kelpup: a sea otter sitting up, a cream head on a brown body, holding a pink shell to its chest.
FORMS.kelpup = { style = "seaotter", sit = true, headC = "cream", shell = "pink" }
-- Slinkit: a mink, long and slim, small-headed with a pointed muzzle, a cream throat, a thin tail.
FORMS.slinkit = { bulk = 0.78, long = 1.18, head = 0.86, arch = -0.1, muzzle = "fox", mlen = 0.22, throat = "cream", under = "cream", tailR = 0.13, h = 1.4 }
-- Gustotter: pale and fluffy, white cheeks, clouds on its back, head and tail.
FORMS.gustotter = { bulk = 1.12, under = "white", cheeks = "white", mc = "white", clouds = "white", tailCloud = "white", headCloud = "white", tailR = 0.22 }

------------------------------------------------------------------ the monkey (lemur)
-- A lemur standing up: a pear of a body, short bent legs on long hand-like feet, long arms hanging nearly to the
-- ground, a round head with a pale face, dark rings round big round eyes and a dark pointed muzzle, furry ears set
-- out to the sides, and a long tail rising behind in an S, ringed.
PLANS.monkey = function(b, a, form)
	local f: Form = form or {}
	local k: number = f.k or 1
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	local t = Kit.new("monkey", f.h or 2.3 * k, 1.0 * k, "biped")
	local face: string = f.face or a
	local dark: string = f.dark or "basalt"
	J("body", nil, P(0, 0.86, 0), "body")
	local bc, bs = P(0, 0.92, -0.02), V(0.8, 0.86, 0.66) * k
	local brot = CFrame.Angles(R(8), 0, 0)
	Kit.egg("Body", bc, bs, 0.56, b, brot)
	local torso: A.Mass = { c = bc, size = bs, rot = brot, split = 0.56 }
	A.patch("Belly", torso, V(0, -0.15, 1), V(0.86, 0.86, 0.86), 0.03, face)
	-- legs: a round haunch, the thigh forward to a bent knee, the shin back down, a long dark foot
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("leg" .. nm, "body", P(s * 0.22, 0.58, -0.02), "leg", s, if s < 0 then 0 else 0.5)
		Kit.ell("Haunch" .. nm, P(s * 0.23, 0.56, -0.04), V(0.36, 0.4, 0.42) * k, b, nil, true)
		if full() then
			Kit.limb("Leg" .. nm, P(s * 0.24, 0.52, 0), P(s * 0.26, 0.3, 0.12), 0.15 * k, 0.12 * k, b)
			Kit.limb("Leg" .. nm, P(s * 0.26, 0.3, 0.12), P(s * 0.27, 0.1, -0.02), 0.12 * k, 0.09 * k, b)
		else
			Kit.limb("Leg" .. nm, P(s * 0.24, 0.52, 0), P(s * 0.27, 0.1, 0.02), 0.16 * k, 0.1 * k, b)
		end
		Kit.limb("Foot" .. nm, P(s * 0.27, 0.06, -0.06), P(s * 0.3, 0.06, 0.2), 0.08 * k, 0.095 * k, dark, 0.6, UP)
		if full() then
			for _, yaw in { -16, 10 } do
				local d = A.dir(s * (yaw + 8), 0)
				Kit.limb("Toe" .. nm, P(s * 0.3, 0.05, 0.2), P(s * 0.3, 0.04, 0.2) + d * 0.1 * k, 0.04 * k, 0.035 * k, dark)
			end
		end
	end
	-- long arms hanging down at the sides, dark hands
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("arm" .. nm, "body", P(s * 0.32, 1.2, 0.02), "arm", s)
		Kit.ell("Shoulder" .. nm, P(s * 0.33, 1.2, 0), V(0.28, 0.3, 0.28) * k, b, nil, true)
		if full() then
			Kit.limb("Arm" .. nm, P(s * 0.35, 1.2, 0.02), P(s * 0.5, 0.86, 0.04), 0.12 * k, 0.1 * k, b)
			Kit.limb("Arm" .. nm, P(s * 0.5, 0.86, 0.04), P(s * 0.53, 0.52, 0.14), 0.1 * k, 0.085 * k, b)
		else
			Kit.limb("Arm" .. nm, P(s * 0.35, 1.2, 0.02), P(s * 0.53, 0.52, 0.14), 0.12 * k, 0.085 * k, b)
		end
		local hand = P(s * 0.53, 0.42, 0.16)
		Kit.ell("Hand" .. nm, hand, V(0.19, 0.21, 0.17) * k, dark)
		if full() then
			for _, dx in { -0.045, 0.035 } do
				Kit.limb("Finger" .. nm, hand + V(s * dx, -0.05, 0.04) * k, hand + V(s * dx * 1.4, -0.16, 0.06) * k, 0.035 * k, 0.03 * k, dark)
			end
			Kit.limb("Thumb" .. nm, hand + V(-s * 0.06, 0, 0.05) * k, hand + V(-s * 0.09, -0.06, 0.12) * k, 0.035 * k, 0.03 * k, dark)
		end
	end
	Kit.on("body")
	-- the tail: rising behind in a long S, ringed
	local ring: string = f.ring or a
	tail({ P(0, 0.64, -0.28), P(0, 0.56, -0.64), P(0, 0.84, -1.02), P(0, 1.38, -1.12), P(0, 1.9, -0.98), P(0, 2.16, -0.66) }, { 0.09 * k, 0.11 * k, 0.11 * k, 0.1 * k, 0.07 * k }, 12, function(i, u)
		return if u > 0.08 and i % 2 == 0 then ring else b
	end)
	Kit.on("body")
	-- the head: built by hand, so the eyes sit on the dark rings over the pale face
	J("head", "body", P(0, 1.3, 0.04), "head")
	local hc, hs = P(0, 1.7, 0.1), V(1.0, 0.86, 0.84) * k
	local _, hm = A.blob("Head", hc, hs, b)
	A.patch("Face", hm, V(0, -0.15, 1), V(0.9, 0.88, 0.9), 0.03, face)
	for _, s in { -1, 1 } do
		spot("EyeRing", hm, A.dir(s * 23, 6), V(0.32, 0.16, 0.32) * k, dark)
	end
	-- the muzzle: dark, short and pointed, a black nose at its tip
	local root = hc + P(0, -0.15, 0.32)
	local tip = root + P(0, -0.04, 0.24)
	Kit.limb("Muzzle", root, tip, 0.16 * k, 0.075 * k, dark, 0.85, UP)
	Kit.ell("Nose", tip + P(0, 0.02, 0.05), V(0.13, 0.09, 0.09) * k, "black")
	if full() then
		Kit.ell("NoseShine", tip + P(-0.02, 0.05, 0.08), V(0.05, 0.05, 0.05), "white")
	end
	J("jaw", "head", root + P(0, -0.08, 0), "jaw")
	Kit.limb("Jaw", root + P(0, -0.07, -0.02), tip + P(0, -0.07, -0.06), 0.08 * k, 0.05 * k, face, 0.7, UP)
	Kit.on("head")
	Kit.faceOn(hc, hs / 2 + V(0.1, 0.1, 0.1))
	Kit.eyes(hc, (hs.X + hs.Y + hs.Z) / 6, FWD, R(23), R(6), 0.28 * k, "gold")
	Kit.faceOff()
	Kit.mouth(lerp(root, tip, 0.6) + P(0, -0.08, 0), V(0, -0.35, 1), 0.13 * k, "black")
	-- the face's details (A.face): fluffy cheeks of the coat's colour, whisker dots along the dark muzzle; no brows
	-- over the dark rings
	A.face({
		color = face,
		c = hc,
		half = hs / 2,
		eyeSurf = false,
		tuft = b,
		muzzle = "snout",
		snout = { a = root, b = tip, ra = 0.16 * k, rb = 0.075 * k, flat = 0.85 },
		padC = A.markC(dark),
		more = A.more({ brows = false }, f.faceDetail),
	})
	local h: A.Head = { c = hc, half = hs / 2, top = hc + UP * hs.Y / 2, front = hc + FWD * hs.Z / 2, nose = tip, mass = hm }
	A.ears(h, { kind = "fox", len = 0.36 * k, w = 0.32 * k, at = 0.56, back = 12, c = b, inner = if full() then face else nil })
	if f.hat then
		-- a stolen straw hat, too small and set at a tilt: a wide flat brim, a low crown, a band
		local tilt = CFrame.Angles(R(-8), 0, R(-14))
		local hb = h.top + P(-0.06, -0.03, 0.02)
		Kit.ell("HatBrim", hb, V(0.72, 0.05, 0.66) * k, f.hat, tilt)
		local hu = tilt:VectorToWorldSpace(UP)
		Kit.rod("Hat", hb, hb + hu * 0.16 * k, 0.38 * k, f.hat)
		Kit.rod("HatBand", hb + hu * 0.02 * k, hb + hu * 0.07 * k, 0.42 * k, f.band or "berry_red")
	end
	return t
end

-- Ruinape: a grey lemur, its long tail ringed in white, wearing a straw hat it stole.
FORMS.ruinape = { hat = "straw", band = "berry_red" }

------------------------------------------------------------------ the yeti
-- A yeti: a big shaggy body broad at the chest, a round head sunk into the shoulders with a smooth face of the accent
-- colour under a fringe, little tusks on the chin, long arms ending in big round hands with palms of the accent
-- colour, short thick legs on big flat feet, locks of fur hanging in a ragged hem.
PLANS.yeti = function(b, a, form)
	local f: Form = form or {}
	local k: number = f.k or 1
	local ak: number = f.arms or 1
	local function P(x: number, y: number, z: number): Vector3
		return V(x, y, z) * k
	end
	local t = Kit.new("yeti", f.h or 2.6 * k, 1.2 * k, "biped")
	local face: string = f.face or a
	J("body", nil, P(0, 1.0, 0), "body")
	local bc = P(0, 1.08, 0)
	local bs = (f.torso or V(1.36, 1.3, 1.12)) * k
	local split: number = f.split or 0.46
	Kit.egg("Body", bc, bs, split, b)
	if f.chest then
		-- a shaggy chest of the accent colour: locks hanging from under the chin
		local c0 = P(0, 1.3, 0.36)
		Kit.ell("Chest", c0, V(0.84, 0.56, 0.46) * k, f.chest, A.lie(V(0, 1, 0.4)))
		for i, x in { -0.26, 0, 0.26, -0.13, 0.13 } do
			if i == 2 or full() then
				local y = if i <= 3 then 0 else 0.1
				fluff("Chest", c0 + V(x, -0.12 + y, 0.12 + y * 0.3) * k, V(x * 0.6, -1, 0.3), (0.38 - math.abs(x) * 0.3) * k, 0.15 * k, f.chest, FWD)
			end
		end
	end
	-- the fur: locks in a ragged hem round the bottom and over the shoulders and back
	local hem = if full() then 10 else 4
	for i = 0, hem - 1 do
		local yaw = -162 + i * 324 / (hem - 1)
		local d = A.dir(yaw, -38)
		local root, n = Kit.onEll(bc, bs / 2, CFrame.identity, d)
		lock("Hem", root - n * 0.06 * k, n * 0.4 - UP, 0.3 * k, 0.15 * k, if f.frost and i % 2 == 1 then f.frost else b, V(n.X, 0, n.Z))
	end
	if full() then
		for _, yaw in { -120, -160, 160, 120 } do
			local d = A.dir(yaw, 20)
			local root, n = Kit.onEll(bc, bs / 2, CFrame.identity, d)
			lock("Fur", root - n * 0.06 * k, n * 0.5 - UP, 0.32 * k, 0.15 * k, b, V(n.X, 0, n.Z))
		end
	end
	-- the head, sunk into the shoulders, the face a smooth patch of the accent colour
	J("head", "body", P(0, 1.62, 0.15), "head")
	local hc, hs = P(0, 2.0, 0.26), (f.headS or V(1.08, 1.0, 0.98)) * k
	local _, hm = A.blob("Head", hc, hs, b)
	A.patch("Face", hm, V(0, 0.06, 1), V(0.84, 0.8, 0.86), 0.05, face)
	-- (the eyes, the blush and the mouth sit just over the face patch)
	local fh = hs / 2 + V(0.06, 0.06, 0.06)
	local fr = (fh.X + fh.Y + fh.Z) / 3
	-- the fringe: locks hanging over the brow
	local fringe: { number } = if full() then { -0.2, 0, 0.2 } else { -0.12, 0.12 }
	for _, x in fringe do
		local root = Kit.onEll(hc, hs / 2, CFrame.identity, V(x * 1.6, 1, 0.5))
		lock("Fringe", root - V(0, 0.04, 0) * k, V(x * 0.8, -0.6, 0.7), (0.22 - math.abs(x) * 0.2) * k, 0.13 * k, b, V(0, 0.6, 1))
	end
	if f.cowlick then
		local root = hc + V(0, hs.Y * 0.44, -0.02 * k)
		Kit.limbs("Cowlick", { root, root + P(0.02, 0.16, 0.04), root + P(0.12, 0.26, -0.02) }, { 0.1 * k, 0.07 * k, 0.02 * k }, b, 2)
		if full() then
			lock("Cowlick", root + P(-0.04, 0, -0.02), V(-0.5, 1, -0.4), 0.2 * k, 0.07 * k, b, nil, 1)
		end
	end
	-- the eyes and the nose on the face
	Kit.faceOn(hc, fh)
	Kit.eyes(hc, fr, FWD, R(25), R(16), 0.25 * k, A.iris(f.iris or a, "blue"))
	Kit.blush(hc, fr, FWD, R(44), R(4), 0.13 * k)
	Kit.faceOff()
	local np = Kit.onEll(hc, fh, CFrame.identity, A.dir(0, -2))
	Kit.ell("Nose", np, V(0.17, 0.11, 0.12) * k, A.shade(face))
	if full() then
		Kit.ell("NoseShine", np + P(-0.03, 0.03, 0.05), V(0.05, 0.05, 0.05), "white")
	end
	-- the jaw: a round chin with two little tusks
	local m, mn = Kit.onEll(hc, fh, CFrame.identity, A.dir(0, -22))
	J("jaw", "head", m - mn * 0.12 * k, "jaw")
	Kit.ell("Chin", m - mn * 0.06 * k - UP * 0.06 * k, V(0.34, 0.2, 0.24) * k, face)
	if full() then
		for _, s in { -1, 1 } do
			local base = m + V(s * 0.12, -0.02, 0.02) * k
			Kit.limb("Tusk", base, base + P(s * 0.02, 0.12, 0.03), 0.04 * k, 0.012 * k, "white")
		end
	end
	Kit.on("head")
	Kit.mouth(m, mn, 0.22 * k, A.ink(face, b))
	-- the face's details (A.face): brows on the face, the line from the nose down to the mouth, tufts of the coat at
	-- the cheeks
	local mr = Kit.faceRec().mouth
	A.face({
		color = face,
		c = hc,
		half = fh,
		ink = A.ink(face, b),
		tuft = b,
		lip = if mr then { np - UP * 0.06 * k + FWD * 0.03 * k, mr.mid + mr.up * 0.02 } else nil,
		more = A.more(if f.crown then { crown = false } else nil, f.faceDetail),
	})
	if f.crown then
		-- a crown of ice: a band round the brow and points of ice standing up from it, the middle one tallest
		local pts: { Vector3 } = {}
		for i = -3, 3 do
			local p = Kit.onEll(hc, hs / 2, CFrame.identity, A.dir(i * 24, 38))
			table.insert(pts, p)
		end
		Kit.limbs("Crown", pts, { 0.06 * k }, f.crown, 6, nil, nil, true)
		for i = -2, 2 do
			if i % 2 == 0 or full() then
				local base, n = Kit.onEll(hc, hs / 2, CFrame.identity, A.dir(i * 24, 42))
				local len = (0.5 - math.abs(i) * 0.1) * k
				lock("Ice", base, n + UP * 1.4, len, (0.1 - math.abs(i) * 0.01) * k, if i == 0 then (f.gem or f.crown) else f.crown, nil, 1, nil, i == 0)
			end
		end
	end
	if f.horns then
		for _, s in { -1, 1 } do
			local base, n = Kit.onEll(hc, hs / 2, CFrame.identity, A.dir(s * 60, 40))
			Kit.limb("Horn", base, base + (n + UP).Unit * 0.16 * k, 0.08 * k, 0.06 * k, f.horns)
		end
	end
	-- long arms: a round shoulder, the arm hanging out and down, a big round hand with a palm of the accent colour
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("arm" .. nm, "body", P(s * 0.66, 1.46, 0.04), "arm", s)
		local sh = P(s * 0.68, 1.46, 0.04)
		local el = sh + V(s * 0.26, -0.4 * ak, 0.06) * k
		local wr = el + V(s * 0.08, -0.36 * ak, 0.08) * k
		Kit.ell("Shoulder" .. nm, sh + P(0, 0.04, -0.02), V(0.5, 0.5, 0.5) * k, b, nil, true)
		Kit.limb("Arm" .. nm, sh, el, 0.22 * k, 0.19 * k, b)
		Kit.limb("Arm" .. nm, el, wr, 0.19 * k, 0.17 * k, b)
		if full() then
			lock("ArmFur" .. nm, el + V(s * 0.12, 0.02, -0.08) * k, V(s * 0.6, -0.7, -0.3), 0.24 * k, 0.12 * k, b, V(s, 0, 0))
		end
		local hand = wr + P(s * 0.02, -0.14, 0.04)
		Kit.ell("Hand" .. nm, hand, V(0.4, 0.42, 0.38) * k, b)
		Kit.ell("Palm" .. nm, hand + P(-s * 0.1, -0.02, 0.1), V(0.14, 0.26, 0.22) * k, face, CFrame.Angles(0, R(-s * 45), 0), true)
		if full() then
			for _, yaw in { -26, 0, 26 } do
				local d = A.dir(yaw - s * 12, -45)
				Kit.ell("Finger" .. nm, hand + d * 0.18 * k, V(0.15, 0.15, 0.15) * k, b)
			end
			Kit.ell("Thumb" .. nm, hand + P(-s * 0.17, 0.06, 0.1), V(0.14, 0.16, 0.14) * k, b)
		end
		if f.snow then
			-- snow piled on the shoulder
			Kit.ell("Snow" .. nm, sh + P(0, 0.24, -0.02), V(0.42, 0.14, 0.4) * k, f.snow)
		end
	end
	-- short thick legs on big flat feet with toe pads
	for _, s in { -1, 1 } do
		local nm = if s < 0 then "L" else "R"
		J("leg" .. nm, "body", P(s * 0.38, 0.5, 0), "leg", s, if s < 0 then 0 else 0.5)
		Kit.limb("Leg" .. nm, P(s * 0.38, 0.58, 0), P(s * 0.42, 0.2, 0.04), 0.26 * k, 0.23 * k, b)
		Kit.ell("Foot" .. nm, P(s * 0.43, 0.13, 0.14), V(0.44, 0.26, 0.62) * k, b)
		if full() then
			for _, dx in { -0.12, 0, 0.12 } do
				Kit.ell("Toe" .. nm, P(s * 0.43 + dx, 0.1, 0.42), V(0.12, 0.1, 0.1) * k, face)
			end
		end
	end
	return t
end

-- Snowpuff: small and round as a snowball, a big head, a blue face and palms, a cowlick.
FORMS.snowpuff = { k = 0.76, h = 2.05, torso = V(1.42, 1.36, 1.24), split = 0.5, arms = 0.8, cowlick = true, headS = V(1.18, 1.08, 1.04) }
-- Frostcrown: big and gold, a white face, palms and shaggy chest, long arms, snow on its shoulders and a crown of ice.
FORMS.frostcrown = { k = 1.08, h = 2.95, arms = 1.15, chest = "white", crown = "ice", gem = "screen_on", snow = "snow", frost = "white", iris = "blue" }

return { plans = PLANS, forms = FORMS }
