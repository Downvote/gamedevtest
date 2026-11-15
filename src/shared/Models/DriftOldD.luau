--!strict
-- Body plans built with the kit (Models/DriftKit; Models/DriftModels uses them over its old ones): the gecko, the fox
-- pup, the mole, the yeti, the seal and the golem. Each returns its Thing; a plan faces +Z with its feet on the ground
-- at y 0. The joints keep the old plans' names, kinds, parents, sides and phases, so every mood still moves them.
local Kit = require(script.Parent.DriftKit)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full

local PLANS: { [string]: (b: string, a: string) -> Kit.Thing } = {}

local UP = V(0, 1, 0)
local FWD = V(0, 0, 1)

-- A direction from forward: turned `yaw` degrees toward +X (the "R" side) or -X (the "L" side), and `pitch` up (+) or
-- down.
local function dir(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(-pitch), 0, 0)):VectorToWorldSpace(FWD)
end

-- The darker shade of a colour, for spots, cracks, bark and scales in the body's own colour.
local SHADE: { [string]: string } = {
	leaf = "leaf_dark",
	green = "leaf_dark",
	moss = "leaf_dark",
	grass = "grass_dark",
	sand = "sand_dark",
	cream = "sand",
	wood = "wood_dark",
	wood_dark = "hair_brown",
	rock = "rock_dark",
	rock_dark = "basalt",
	steel = "steel_dark",
	window = "ice",
	ice = "blue",
	white = "window",
	snow = "ice",
	shallow = "teal",
	orange = "clay",
	gold = "orange",
	yellow = "gold",
	black = "slate",
	blue = "jeans",
	purple = "night",
	pink = "coral",
}
local function shade(c: string): string
	return SHADE[c] or c
end

-- A colour that reads on a dark eye: an iris in the accent unless the accent is too dark or too pale for it.
local function irisOf(a: string, fallback: string): string
	if a == "white" or a == "cream" or a == "snow" or a == "black" or a == "wood_dark" or a == "rock_dark" or a == "basalt" then
		return fallback
	end
	return a
end

-- A value along a list spread evenly over 0..1.
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

-- A fat round body along a curve (a gecko's, a seal's): balls along it as big as `radii` says (spread over the curve's
-- own parameter, as Kit.tube does), each about `gap` of its radius from the next, so its sides read smooth with no
-- rings where a tube's links would meet. `surf` below finds a point on it.
local function sausage(name: string, pts: { Vector3 }, radii: { number }, color: string, gap: number?)
	local N = 48
	local k = gap or (if full() then 0.45 else 0.85)
	-- how many balls it takes: the length over the spacing, summed along it
	local count = 0
	local us: { number } = { 0 }
	local prev = Kit.curveAt(pts, 0)
	local sums: { number } = { 0 }
	for i = 1, N do
		local u = i / N
		local q = Kit.curveAt(pts, u)
		local r = lerpList(radii, (i - 0.5) / N)
		count += (q - prev).Magnitude / math.max(0.05, r * k)
		sums[i + 1] = count
		us[i + 1] = u
		prev = q
	end
	local n = math.max(1, math.ceil(count))
	local j = 1
	for i = 0, n do
		local want = count * i / n
		while j < N and sums[j + 1] < want do
			j += 1
		end
		local seg = sums[j + 1] - sums[j]
		local s = if seg > 0 then (want - sums[j]) / seg else 0
		local u = us[j] + (us[j + 1] - us[j]) * math.clamp(s, 0, 1)
		Kit.ball(name, Kit.curveAt(pts, u), 2 * lerpList(radii, u), color)
	end
end

-- The point on a round body along a curve (a sausage or a tube) at `u`, turned `ang` degrees round it from the top
-- (+ toward +X), and the way out there.
local function surf(pts: { Vector3 }, radii: { number }, u: number, ang: number, lift: number?): (Vector3, Vector3)
	local c = Kit.curveAt(pts, u)
	local t = Kit.curveAt(pts, math.min(1, u + 0.02)) - Kit.curveAt(pts, math.max(0, u - 0.02))
	t = if t.Magnitude > 1e-5 then t.Unit else FWD
	local up = UP - t * UP:Dot(t)
	up = if up.Magnitude > 1e-5 then up.Unit else V(0, 0, 1)
	local side = up:Cross(t).Unit
	if side.X < 0 then
		side = -side
	end
	local n = up * math.cos(R(ang)) + side * math.sin(R(ang))
	return c + n * (lerpList(radii, u) + (lift or 0)), n
end

-- A flat patch (a spot, a pad, a face mark) on a ball (centre c, radius r) toward `d`: a disc clear of the surface,
-- its rim just off it. (Raster draws a part over another only where it is more than 0.03 studs nearer, so a patch
-- lying closer than that loses to the ball wherever the ball is drawn after it.)
local function patch(name: string, c: Vector3, r: number, d: Vector3, size: number, color: string, detail: boolean?, neon: boolean?): BasePart?
	local n = d.Unit
	return Kit.disc(name, c + n * (r + 0.02), n, size, 0.05, color, detail, r, neon)
end

-- A flat pointed blade (a leaf, a claw, a spine, an ear's flat) from its wide `base` to its point at `tip`. (Kit.blade
-- lays each half wedge with its tall end, +Z, toward the base: a Roblox wedge is tall at its back and Raster draws it
-- so. This used to hand it the two ends the other way round, which made every blade here widest at its point.)
local function blade(name: string, base: Vector3, tip: Vector3, w: number, th: number, normal: Vector3, color: string, detail: boolean?): BasePart?
	return Kit.blade(name, base, tip, w, th, normal, color, detail)
end

-- A pair of eyes on a head ball (Kit.eyes) set out a little from its surface: Raster draws a part over another only
-- where it is more than 0.03 studs nearer (DEPTH_BIAS), so an eye's dark oval lying closer than that to the head
-- would lose its middle to the head and show as a ring.
local function eyes(hc: Vector3, hr: number, d: Vector3, spread: number, lift: number, size: number, iris: string?, dark: string?)
	Kit.eyes(hc, hr + 0.02, d, spread, lift, size, iris, dark)
end

-- A flat patch on a body along a curve: as `patch`, the disc's back on the surface where it is flat along the curve.
local function spot(name: string, pts: { Vector3 }, radii: { number }, u: number, ang: number, size: number, color: string, detail: boolean?, neon: boolean?): BasePart?
	local at, n = surf(pts, radii, u, ang, 0.02)
	return Kit.disc(name, at, n, size, 0.05, color, detail, nil, neon)
end

-- A line on a ball's surface (a crack, a seam, a bark furrow): short rods through the directions `dirs`, just off the
-- surface, with a bead at each bend so it reads as one line.
local function seam(name: string, c: Vector3, r: number, dirs: { Vector3 }, w: number, color: string, detail: boolean?, neon: boolean?)
	if detail and not full() then
		return
	end
	local prev: Vector3? = nil
	for i, d in dirs do
		local p = c + d.Unit * (r + 0.005)
		if prev then
			Kit.rod(name, prev, p, w, color, false, neon)
		end
		if i > 1 and i < #dirs and full() then
			Kit.ball(name, p, w, color, false, neon)
		end
		prev = p
	end
end

-- One lock of long fur on a ball (centre `c`, radius `r`) toward `n`: from just inside the surface it runs `len` down
-- the surface and flares out, thick at the root and pointed at the end, so a row of them makes a ragged edge (on the
-- islands a flat pointed blade, two parts).
local function lock(name: string, c: Vector3, r: number, n: Vector3, len: number, thick: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	local nn = n.Unit
	local down = V(0, -1, 0) + nn * nn.Y
	down = if down.Magnitude > 1e-3 then down.Unit else nn
	local root = c + nn * (r - thick * 0.5)
	local tip = root + down * len + nn * (thick * 1.1 + len * 0.22)
	if full() then
		-- (a round root, so it grows out of the body, and a flat point)
		Kit.ball(name, root + down * (thick * 0.3), thick * 1.7, color)
		blade(name, root + down * (thick * 0.4), tip, thick * 2.1, thick * 0.8, nn, color)
	else
		blade(name, root, tip, thick * 2.4, thick * 0.9, nn, color)
	end
end

-- A thick flat paddle along a curve (a flipper, a fluke): overlapping discs `th` thick facing `normal`, as wide as
-- `widths` says along it (spread evenly), so it reads as a pad with a round edge.
local function paddle(name: string, pts: { Vector3 }, widths: { number }, normal: Vector3, th: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	local nn = normal.Unit
	local total = 0
	local prev = Kit.curveAt(pts, 0)
	for i = 1, 16 do
		local q = Kit.curveAt(pts, i / 16)
		total += (q - prev).Magnitude
		prev = q
	end
	local avgW = 0
	for _, w in widths do
		avgW += w
	end
	avgW /= #widths
	local n = math.max(1, math.ceil(total / (avgW * (if full() then 0.45 else 0.8))))
	for i = 0, n do
		local u = i / n
		Kit.disc(name, Kit.curveAt(pts, u) - nn * (th / 2), nn, lerpList(widths, u), th, color)
	end
end

-- Tufts of fur bulging out of a round body along a curve (a back's ridge, a haunch): a ball `d` across at each of `us`,
-- turned `angs` degrees round from the top, sunk a third into the body, so it reads as a bump of fur.
local function shagLine(name: string, pts: { Vector3 }, radii: { number }, us: { number }, angs: { number }, d: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	for i, u in us do
		Kit.ball(name, (surf(pts, radii, u, angs[i] or 0, -d * 0.3)), d, color)
	end
end

------------------------------------------------------------------ the gecko
-- a gecko: a long low body with raised spots, a crest of little spines and beaded scales down its sides, a broad head
-- with big eyes, a wide smile, nostrils and a fan of throat skin, a jaw that opens, four splayed legs on toes that
-- end in round sticky pads, and a long tail with bands that curls up at the end like a fern
PLANS.lizard = function(b, a)
	local t = Kit.new("lizard", 1.4, 1.3, "quad")
	local ink = shade(b)
	J("body", nil, V(0, 0.5, 0), "body")
	local BP = { V(0, 0.5, -0.78), V(0, 0.57, -0.3), V(0, 0.6, 0.18), V(0, 0.64, 0.56) }
	local BR = { 0.25, 0.33, 0.32, 0.27 }
	sausage("Body", BP, BR, b)
	-- the pale edge of the belly along the bottom of each flank: a row of cream scales (up close)
	if full() then
		for i = 0, 5 do
			for _, side in { -1, 1 } do
				spot("BellyScale", BP, BR, 0.14 + i * 0.14, side * (108 - (i % 2) * 5), 0.12, "cream", true)
			end
		end
	end
	-- raised spots down the back and its sides (the accent), little scale beads lower down (the body's shade)
	for _, s in { { 0.12, 0, 0.2 }, { 0.36, -38, 0.16 }, { 0.38, 40, 0.15 }, { 0.6, 0, 0.18 }, { 0.82, -30, 0.13 }, { 0.84, 34, 0.12 } } do
		spot("Spot", BP, BR, s[1], s[2], s[3], a, s[3] < 0.15)
	end
	if full() then
		for i = 0, 5 do
			for _, side in { -1, 1 } do
				local u = 0.1 + i * 0.15
				local at = surf(BP, BR, u, side * (66 + (i % 2) * 14), -0.01)
				Kit.ball("Scale", at, 0.08, ink, true)
			end
		end
	end
	-- the crest: spines along the spine, leaning back, the tallest over the shoulders (three bigger ones on the
	-- islands, so the outline still says lizard)
	for i = 0, 7 do
		local u = 0.06 + i * 0.125
		local base = surf(BP, BR, u, 0, -0.04)
		local hgt = 0.13 + 0.07 * math.sin((7 - i) / 7 * math.pi * 0.9)
		if full() then
			blade("Crest", base, base + V(0, hgt, -0.08), 0.14, 0.05, V(1, 0, 0), a)
		elseif i % 2 == 1 and i < 7 then
			blade("Crest", base, base + V(0, hgt + 0.04, -0.1), 0.2, 0.06, V(1, 0, 0), a)
		end
	end
	-- the head: a broad round skull, full jowls, a round snout with nostrils, the cream chin on the jaw
	J("head", "body", V(0, 0.68, 0.66), "head")
	local HC = V(0, 0.86, 0.98)
	local HR = 0.4
	Kit.ball("Head", HC, 2 * HR, b)
	-- ridges over the eyes, so they sit in sockets as a gecko's do, and two little spines at the back of the head
	for _, side in { -1, 1 } do
		Kit.ball("Brow", HC + dir(side * 42, 40) * (HR - 0.07), 0.22, b, true)
	end
	for i = 0, 1 do
		local base = HC + dir(0, 60 - i * 34) * (HR - 0.03) + V(0, 0, -0.06 * i)
		blade("Crest", base, base + V(0, 0.1 - i * 0.02, -0.06), 0.11, 0.05, V(1, 0, 0), a, true)
	end
	Kit.ball("Jowl", HC + V(-0.22, -0.12, -0.02), 0.48, b)
	Kit.ball("Jowl", HC + V(0.22, -0.12, -0.02), 0.48, b)
	local SC = HC + V(0, -0.1, 0.32)
	local SR = 0.25
	Kit.ball("Snout", SC, 2 * SR, b)
	for _, side in { -1, 1 } do
		local at = Kit.onBall(SC, SR, dir(side * 18, 26))
		Kit.ball("Nostril", at, 0.06, ink, true)
	end
	eyes(HC, HR, FWD, R(40), R(18), 0.33, irisOf(a, "gold"))
	local m, mn = Kit.onBall(SC, SR, dir(0, -22))
	Kit.mouth(m, mn, 0.28)
	Kit.blush(HC, HR + 0.02, FWD, R(58), R(20), 0.14)
	-- the dewlap: a fan of throat skin in the accent, edged with beads
	Kit.disc("Dewlap", HC + V(0, -0.4, 0.04), V(1, 0, 0), 0.3, 0.05, a)
	if full() then
		for i = 0, 3 do
			local ang = R(-150 + i * 40)
			Kit.ball("DewlapBead", HC + V(0, -0.4 + math.sin(ang) * 0.14, 0.04 + math.cos(ang) * 0.14), 0.07, a, true)
		end
	end
	J("jaw", "head", V(0, 0.66, 0.9), "jaw")
	Kit.ball("Chin", V(0, 0.62, 1.22), 0.32, "cream")
	Kit.ball("Chin", V(0, 0.63, 1.04), 0.34, "cream", true)
	-- four splayed legs: out from the hip, down at the elbow, toes fanned flat ending in round pads
	for _, l in { { n = "FL", s = -1, z = 0.38, ph = 0 }, { n = "FR", s = 1, z = 0.38, ph = 0.5 }, { n = "BL", s = -1, z = -0.52, ph = 0.5 }, { n = "BR", s = 1, z = -0.52, ph = 0 } } do
		local s, z = l.s, l.z
		J("leg" .. l.n, "body", V(s * 0.3, 0.5, z), "leg", s, l.ph)
		local back = if z < 0 then -1 else 1
		if full() then
			Kit.tube("Leg" .. l.n, { V(s * 0.24, 0.52, z), V(s * 0.54, 0.44, z + 0.04 * back), V(s * 0.6, 0.12, z + 0.1 * back) }, { 0.15, 0.12, 0.1 }, b)
		else
			Kit.tube("Leg" .. l.n, { V(s * 0.3, 0.5, z), V(s * 0.6, 0.12, z + 0.1 * back) }, { 0.15, 0.11 }, b)
		end
		local palm = V(s * 0.62, 0.08, z + 0.12 * back)
		Kit.ball("Palm" .. l.n, palm, if full() then 0.2 else 0.24, b)
		if full() then
			for i, yaw in { -60, -22, 16, 54 } do
				local d = dir(s * yaw + (if back < 0 then s * 20 else 0), 0)
				d = V(d.X, 0, d.Z * back)
				local tip = palm + d * (0.19 + (if i == 2 or i == 3 then 0.03 else 0)) + V(0, -0.02, 0)
				Kit.rod("Toe" .. l.n, palm, tip, 0.07, b, true)
				Kit.ball("Pad" .. l.n, tip, 0.13, a, true)
			end
		end
	end
	-- the tail: thick at the hips, banded, its tip curling up like a fern's
	J("tail1", "body", V(0, 0.5, -0.78), "tail", 0, 1)
	local T1 = { V(0, 0.5, -0.7), V(0, 0.44, -1.06), V(0, 0.37, -1.42) }
	local T1R = { 0.22, 0.18, 0.145 }
	Kit.tube("Tail1", T1, T1R, b)
	local bands: { number } = if full() then { 0.4, 0.85 } else { 0.6 }
	for _, u in bands do
		local at, n = surf(T1, T1R, u, 0, 0)
		local c = at - n * lerpList(T1R, u)
		local tng = Kit.curveAt(T1, u + 0.02) - Kit.curveAt(T1, u - 0.02)
		Kit.disc("Band", c, tng, 2 * lerpList(T1R, u) + 0.04, 0.07, a)
	end
	for i = 0, 1 do
		local base = surf(T1, T1R, 0.25 + i * 0.4, 0, -0.03)
		blade("Crest", base, base + V(0, 0.1, -0.07), 0.11, 0.05, V(1, 0, 0), a, true)
	end
	J("tail2", "tail1", V(0, 0.37, -1.42), "tail", 0, 2)
	local T2 = { V(0, 0.37, -1.42), V(0, 0.33, -1.74), V(0, 0.36, -2.04) }
	local T2R = { 0.145, 0.125, 0.105 }
	Kit.tube("Tail2", T2, T2R, b)
	local tb = surf(T2, T2R, 0.25, 0, -0.03)
	blade("Crest", tb, tb + V(0, 0.08, -0.06), 0.1, 0.05, V(1, 0, 0), a, true)
	local at2, n2 = surf(T2, T2R, 0.55, 0, 0)
	Kit.disc("Band", at2 - n2 * lerpList(T2R, 0.55), Kit.curveAt(T2, 0.57) - Kit.curveAt(T2, 0.53), 2 * lerpList(T2R, 0.55) + 0.04, 0.07, a)
	if full() then
		Kit.tube("Curl", { V(0, 0.36, -2.04), V(0, 0.45, -2.3), V(0, 0.66, -2.38), V(0, 0.82, -2.24), V(0, 0.78, -2.06) }, { 0.105, 0.09, 0.075, 0.06, 0.05 }, b, 0.6)
		Kit.ball("CurlTip", V(0, 0.76, -2.04), 0.1, a)
	else
		Kit.tube("Curl", { V(0, 0.36, -2.04), V(0, 0.56, -2.36), V(0, 0.8, -2.2) }, { 0.105, 0.075, 0.055 }, b)
		Kit.ball("CurlTip", V(0, 0.8, -2.2), 0.13, a)
	end
	return t
end

------------------------------------------------------------------ the fox pup
-- a fox pup: a chubby body on round haunches with a soft fluffy back, a cream chest ruff, a big head with a cream
-- lower face and pointed cheek fluff, a pointed muzzle with cream whisker pads and a shiny black nose, big cupped ears
-- (round cones, so they read from every side) with cream insides, dark tips and a little flick of fur
-- at the point, short legs in socks of the accent with toe beads and pink pads, and a big bushy tail, fat in the middle
-- and tipped in the accent in a soft flame
PLANS.pup = function(b, a)
	local t = Kit.new("pup", 2.2, 1.1, "quad")
	-- (a dark pup's ear tips and nose shine take the accent: black on black would be lost)
	local dark = b == "black" or b == "basalt" or b == "night"
	local tipC = if dark then a else "black"
	J("body", nil, V(0, 0.85, 0), "body")
	local BP = { V(0, 0.82, -0.42), V(0, 0.86, -0.08), V(0, 0.94, 0.26) }
	local BR = { 0.41, 0.38, 0.41 }
	sausage("Body", BP, BR, b)
	-- a soft ridge of fluff along the back and over the haunches, so the outline looks furry
	shagLine("BackFluff", BP, BR, { 0.08, 0.3, 0.52 }, { -18, 16, -12 }, 0.2, b, true)
	-- the chest ruff
	Kit.tuft("Ruff", V(0, 0.96, 0.62), 0.2, "cream", nil, false)
	Kit.tuft("Ruff", V(-0.18, 1.1, 0.56), 0.15, "cream", 3, true)
	Kit.tuft("Ruff", V(0.18, 1.1, 0.56), 0.15, "cream", 3, true)
	Kit.tuft("Ruff", V(0, 0.74, 0.58), 0.17, "cream", 3, false)
	-- four short legs in socks, round paws with toe beads and a pink pad; round haunches over the hind ones
	for _, l in { { n = "FL", s = -1, z = 0.3, ph = 0 }, { n = "FR", s = 1, z = 0.3, ph = 0.5 }, { n = "BL", s = -1, z = -0.44, ph = 0.5 }, { n = "BR", s = 1, z = -0.44, ph = 0 } } do
		local s, z = l.s, l.z
		J("leg" .. l.n, "body", V(s * 0.22, 0.6, z), "leg", s, l.ph)
		local hind = z < 0
		local zf = z + (if hind then 0.02 else 0.04)
		if hind then
			Kit.ball("Haunch" .. l.n, V(s * 0.22, 0.7, z - 0.02), 0.54, b)
			Kit.ball("HaunchFluff" .. l.n, V(s * 0.3, 0.6, z - 0.2), 0.22, b, true)
		end
		if not full() then
			Kit.tube("Leg" .. l.n, { V(s * 0.23, if hind then 0.6 else 0.72, z), V(s * 0.25, 0.22, zf) }, { 0.16, 0.14 }, b)
		elseif hind then
			Kit.tube("Leg" .. l.n, { V(s * 0.24, 0.56, z), V(s * 0.25, 0.32, z - 0.05), V(s * 0.25, 0.16, z + 0.02) }, { 0.16, 0.135, 0.125 }, b)
		else
			Kit.tube("Leg" .. l.n, { V(s * 0.22, 0.72, z), V(s * 0.24, 0.42, z + 0.02), V(s * 0.25, 0.16, z + 0.04) }, { 0.17, 0.135, 0.125 }, b)
		end
		if full() then
			Kit.tube("Sock" .. l.n, { V(s * 0.25, 0.33, zf - (if hind then 0.05 else 0.01)), V(s * 0.25, 0.17, zf) }, { 0.165, 0.16 }, a)
			-- (a ruffled top to the sock)
			for _, k in { -1, 1 } do
				Kit.ball("SockFluff" .. l.n, V(s * 0.25 + k * 0.08, 0.33, zf + (if hind then -0.05 else 0) + 0.05), 0.12, a, true)
			end
		end
		Kit.ball("Paw" .. l.n, V(s * 0.25, 0.12, zf + 0.06), 0.3, a)
		Kit.toes("Toe" .. l.n, V(s * 0.25, 0.08, zf + 0.18), 0.18, 0.1, 3, a)
		patch("Pad" .. l.n, V(s * 0.25, 0.12, zf + 0.06), 0.15, V(0, -0.5, -1), 0.13, "pink", true)
	end
	-- the tail: a big brush, thin at the root, fat in the middle, sweeping back and up to a soft flame of the accent,
	-- fluffed all along its sides
	J("tail1", "body", V(0, 0.9, -0.7), "tail", 0, 1)
	local T1 = { V(0, 0.9, -0.64), V(0.02, 0.9, -0.92), V(0.06, 0.98, -1.18) }
	local T1R = { 0.13, 0.22, 0.3 }
	sausage("Tail1", T1, T1R, b, if full() then 0.5 else 1)
	J("tail2", "tail1", V(0.06, 0.98, -1.18), "tail", 0, 2)
	local T2 = { V(0.06, 0.98, -1.18), V(0.14, 1.12, -1.44), V(0.24, 1.32, -1.6), V(0.32, 1.5, -1.64) }
	local T2R = { 0.3, 0.34, 0.31, 0.25 }
	sausage("Tail2", T2, T2R, b, if full() then 0.5 else 1)
	sausage("TailTip", { V(0.3, 1.46, -1.64), V(0.38, 1.64, -1.62), V(0.44, 1.8, -1.52) }, { 0.28, 0.2, 0.06 }, a, if full() then 0.5 else 1)
	if full() then
		Kit.on("tail1")
		for _, ang in { -80, 80 } do
			Kit.ball("TailFluff", surf(T1, T1R, 0.85, ang, -0.06), 0.2, b)
		end
		Kit.on("tail2")
		for i, u in { 0.25, 0.5, 0.75 } do
			for _, ang in { -84, 84 } do
				Kit.ball("TailFluff", surf(T2, T2R, u, ang + (i - 2) * 10, -0.07), 0.22, b)
			end
		end
		Kit.ball("TailFluff", surf(T2, T2R, 0.45, 0, -0.07), 0.22, b)
		for _, ang in { -90, 90 } do
			Kit.ball("TailTipFluff", V(0.36, 1.6, -1.63) + dir(ang, 10) * 0.17, 0.18, a)
		end
		-- the flame at the end: three soft licks of the accent curling up
		for _, c in { { -0.1, 1.74, -1.6 }, { 0.12, 1.78, -1.5 }, { 0.02, 1.88, -1.56 } } do
			local base = V(0.4 + c[1] * 0.4, c[2] - 0.12, c[3])
			Kit.tube("TailFlame", { base, V(0.42 + c[1], c[2], c[3]) }, { 0.08, 0.025 }, a, 2, true)
		end
	end
	-- the head
	J("head", "body", V(0, 1.18, 0.48), "head")
	local HC = V(0, 1.56, 0.66)
	local HR = 0.48
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.tuft("Crown", HC + V(0, HR - 0.04, -0.02), 0.1, b, 3, true)
	-- the cream lower face, pointed fluff swept back from each cheek
	Kit.ball("Jowls", HC + V(0, -0.24, 0.16), 0.66, "cream")
	for _, side in { -1, 1 } do
		Kit.ball("Cheek", HC + V(side * 0.3, -0.2, 0.06), 0.36, "cream")
		Kit.tube("CheekFluff", { HC + V(side * 0.34, -0.24, 0.0), HC + V(side * 0.58, -0.36, -0.14) }, { 0.12, 0.03 }, "cream", nil, true)
		Kit.tube("CheekFluff", { HC + V(side * 0.3, -0.36, 0.04), HC + V(side * 0.46, -0.52, -0.1) }, { 0.1, 0.03 }, "cream", nil, true)
	end
	-- the pointed muzzle, cream whisker pads under its end, the black nose on its tip with a shine
	sausage("Muzzle", { HC + V(0, -0.04, 0.32), HC + V(0, -0.14, 0.72) }, { 0.19, 0.1 }, b, if full() then 0.5 else 1.2)
	Kit.ball("Pad", HC + V(-0.065, -0.22, 0.62), 0.17, "cream")
	Kit.ball("Pad", HC + V(0.065, -0.22, 0.62), 0.17, "cream")
	local NC = HC + V(0, -0.11, 0.82)
	Kit.ball("Nose", NC, 0.16, "black")
	if full() then
		Kit.ball("NoseShine", NC + V(-0.03, 0.05, 0.03), 0.05, if dark then a else "white")
		for _, side in { -1, 1 } do
			patch("Freckle", HC + V(side * 0.065, -0.22, 0.62), 0.085, V(side * 0.6, 0.2, 1), 0.05, "black", true)
		end
	end
	Kit.mouth(HC + V(0, -0.3, 0.64), V(0, -0.5, 1), 0.14, nil, "pink")
	eyes(HC, HR, FWD, R(30), R(12), 0.3, irisOf(a, "blue"))
	Kit.blush(HC, HR + 0.02, FWD, R(50), R(4), 0.15)
	J("jaw", "head", V(0, 1.3, 1.0), "jaw")
	Kit.ball("Chin", HC + V(0, -0.33, 0.52), 0.2, "cream")
	-- big cupped ears: two cones side by side (a broad round cone), a cream inside with a tuft at its base, a dark
	-- tip with a flick of fur at the point
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local B = HC + V(side * 0.24, 0.3, -0.06)
		local T = HC + V(side * 0.5, 0.94, -0.12)
		J("ear" .. s, "head", B, "ear", side)
		local up = (T - B).Unit
		local n = V(side * 0.3, 0.1, 1).Unit
		n = (n - up * n:Dot(up)).Unit
		local across = up:Cross(n).Unit
		local function mix(p: Vector3, q: Vector3, u: number): Vector3
			return p + (q - p) * u
		end
		if full() then
			for _, k in { -1, 1 } do
				local base = B + across * k * 0.09 - n * 0.02
				Kit.tube("Ear" .. s, { base, mix(base, T, 0.5) + across * k * 0.02, T }, { 0.15, 0.1, 0.035 }, b, 0.8)
				-- (the tip stands a clear step proud of the ear, so the two colours never meet in one surface)
				Kit.tube("EarTip" .. s, { mix(base, T, 0.58), T + up * 0.03 }, { 0.13, 0.07 }, tipC, 0.8)
			end
			-- the cream inside: three discs down the front of the cone, each just clear of it
			for _, e in { { 0.16, 0.21 }, { 0.36, 0.17 }, { 0.54, 0.11 } } do
				local u = e[1]
				local r = lerpList({ 0.15, 0.1, 0.035 }, u)
				local o = lerpList({ 0.09, 0.065, 0 }, u)
				local front = math.sqrt(math.max(0, r * r - o * o)) - 0.02 * (1 - u)
				Kit.disc("EarIn" .. s, mix(B, T, u) + n * (front - 0.01), n, e[2], 0.05, "cream")
			end
			Kit.tuft("EarFluff" .. s, B + n * 0.12 + up * 0.1, 0.08, "cream", 3, true)
			Kit.tube("EarFlick" .. s, { T - up * 0.02, T + up * 0.1 - n * 0.03 + across * side * 0.02 }, { 0.04, 0.02 }, tipC, 2, true)
		else
			-- (on the islands: a thick pointed blade on a round base, and a dark tip)
			Kit.ball("Ear" .. s, B + up * 0.1, 0.36, b)
			blade("Ear" .. s, B + up * 0.06, T, 0.38, 0.16, n, b)
			Kit.ball("EarTip" .. s, mix(B, T, 0.86), 0.12, tipC)
		end
	end
	return t
end

------------------------------------------------------------------ the mole
-- a mole: a fat velvety pear of a body with a pale belly and fur partings down its back (glowing cracks on a hot one),
-- no neck: the body runs on into a smaller head with a cowlick and on into a long pink snout with wrinkles, ending in
-- the star (a ring of fleshy rays round a coral tip with two nostrils), whiskers, beady eyes, buck teeth; big spade
-- hands turned out, broad pink palms with long curved claws (glowing on a hot one), small pink hind feet with claw
-- beads, a short pink tail with a tuft
PLANS.mole = function(b, a)
	local t = Kit.new("mole", 1.8, 1.1, "quad")
	local hot = b == "black" or b == "basalt"
	J("body", nil, V(0, 0.75, 0), "body")
	local BP = { V(0, 0.62, -0.54), V(0, 0.73, -0.16), V(0, 0.76, 0.2) }
	local BR = { 0.46, 0.57, 0.5 }
	sausage("Body", BP, BR, b)
	Kit.ball("Belly", V(0, 0.5, 0.36), 0.76, a)
	-- fur partings over the back (cracks glowing in the accent on a hot one)
	for i, u in { 0.28, 0.52, 0.76 } do
		local pts: { Vector3 } = {}
		for k = -2, 2 do
			local p = surf(BP, BR, u - math.abs(k) * 0.05 + i * 0.01, k * 16, 0.005)
			table.insert(pts, p)
		end
		for k = 1, #pts - 1 do
			Kit.rod("Parting", pts[k], pts[k + 1], if hot then 0.07 else 0.06, if hot then a else shade(b), not hot, hot)
		end
	end
	-- (a hot one has a few more cracks down its flanks, glowing)
	if hot and full() then
		for _, side in { -1, 1 } do
			local p1 = surf(BP, BR, 0.36, side * 70, 0.005)
			local p2 = surf(BP, BR, 0.46, side * 84, 0.005)
			local p3 = surf(BP, BR, 0.52, side * 100, 0.005)
			Kit.rod("Parting", p1, p2, 0.06, a, false, true)
			Kit.rod("Parting", p2, p3, 0.06, a, false, true)
		end
	end
	-- the head: smaller than the body and set low and forward, so the body tapers into it; the cowlick on top
	J("head", "body", V(0, 0.92, 0.5), "head")
	local HC = V(0, 0.95, 0.72)
	local HR = 0.42
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.ball("Cheek", HC + V(-0.18, -0.12, -0.1), 0.5, b, true)
	Kit.ball("Cheek", HC + V(0.18, -0.12, -0.1), 0.5, b, true)
	Kit.tuft("Cowlick", HC + V(0.02, HR - 0.03, -0.06), 0.1, b, 4, true)
	-- the snout: long and pink, a little upturned, with wrinkles across it
	local SP = { HC + V(0, -0.08, 0.3), HC + V(0, -0.12, 0.5), HC + V(0, -0.1, 0.64) }
	local SR = { 0.15, 0.12, 0.11 }
	Kit.tube("Snout", SP, SR, "pink")
	if full() then
		for _, u in { 0.35, 0.6 } do
			local c = Kit.curveAt(SP, u)
			Kit.disc("Wrinkle", c, Kit.curveAt(SP, u + 0.03) - Kit.curveAt(SP, u - 0.03), 2 * lerpList(SR, u) + 0.04, 0.05, "coral", true)
		end
	end
	-- the star: fleshy rays fanned round the tip (a pink disc behind them on the islands)
	local tip = HC + V(0, -0.1, 0.72)
	if full() then
		for i = 0, 10 do
			local ang = i / 11 * 2 * math.pi + 0.15
			local d = V(math.cos(ang), math.sin(ang), 0.25).Unit
			Kit.rod("Star", tip + d * 0.05, tip + d * 0.18, 0.06, "pink")
			Kit.ball("Star", tip + d * 0.19, 0.08, "pink")
		end
		Kit.ball("NoseTip", tip + V(0, 0, 0.03), 0.14, "coral")
		for _, side in { -1, 1 } do
			Kit.ball("Nostril", tip + V(side * 0.035, 0.01, 0.09), 0.05, "black", true)
		end
	else
		Kit.disc("Star", tip, FWD, 0.36, 0.06, "pink")
		Kit.ball("NoseTip", tip + V(0, 0, 0.04), 0.16, "coral")
	end
	Kit.whiskers(HC + V(0, -0.1, 0.56), 0.28, "cream")
	eyes(HC, HR, FWD, R(36), R(20), 0.22, irisOf(a, "gold"))
	Kit.blush(HC, HR + 0.02, FWD, R(56), R(2), 0.15)
	local mz = HC + V(0, -0.26, 0.5)
	Kit.mouth(mz, V(0, -0.5, 1), 0.14)
	Kit.P("Tooth", "Block", V(0.06, 0.1, 0.05), mz + V(-0.035, -0.065, 0.02), "white")
	Kit.P("Tooth", "Block", V(0.06, 0.1, 0.05), mz + V(0.035, -0.065, 0.02), "white")
	J("jaw", "head", V(0, 0.76, 1.0), "jaw")
	Kit.ball("Chin", HC + V(0, -0.3, 0.38), 0.2, a)
	-- the spade hands: a short thick arm, a broad pink palm turned out, finger pads and long claws curving down
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.52, 0.7, 0.42), "arm", side)
		Kit.tube("Arm" .. s, { V(side * 0.46, 0.72, 0.36), V(side * 0.7, 0.5, 0.54) }, { 0.2, 0.16 }, b)
		Kit.ball("Wrist" .. s, V(side * 0.7, 0.5, 0.54), 0.3, b, true)
		local palm = V(side * 0.8, 0.4, 0.64)
		-- (the palm a broad pad turned out; the fingers fan forward and out, flat, so their claws show from above)
		local hf = V(side * 0.55, -0.12, 1).Unit
		Kit.ball("Palm" .. s, palm, 0.38, "pink")
		Kit.ball("Palm" .. s, palm + V(side * 0.06, 0.04, 0.06), 0.3, "pink", true)
		local fan: { number } = if full() then { -44, -22, 0, 22, 44 } else { -36, 0, 36 }
		for _, yaw in fan do
			local d = CFrame.Angles(0, R(yaw), 0):VectorToWorldSpace(hf)
			local bead = palm + d * 0.17
			Kit.ball("Finger" .. s, bead, 0.13, "pink", true)
			blade("Claw" .. s, bead + d * 0.02, bead + d * 0.32 + V(0, -0.07, 0), 0.11, 0.05, V(0, 1, 0.2), a)
		end
		if hot then
			-- (the claws glow: a hot bead at each one's root)
			for _, yaw in { -27, 25 } do
				local d = CFrame.Angles(0, R(yaw), 0):VectorToWorldSpace(hf)
				Kit.ball("Ember" .. s, palm + d * 0.2 + V(0, 0.02, 0), 0.07, a, true, true)
			end
		end
		-- small hind feet peeking out under the body, little claws at their toes
		J("leg" .. s, "body", V(side * 0.42, 0.4, -0.5), "leg", side, if side < 0 then 0.5 else 0)
		Kit.ball("Foot" .. s, V(side * 0.36, 0.1, -0.42), 0.22, "pink")
		Kit.ball("Foot" .. s, V(side * 0.38, 0.08, -0.28), 0.17, "pink")
		Kit.toes("Toe" .. s, V(side * 0.38, 0.06, -0.22), 0.12, 0.07, 3, "pink")
		Kit.toes("FootClaw" .. s, V(side * 0.38, 0.05, -0.18), 0.12, 0.05, 3, a)
	end
	J("tail", "body", V(0, 0.58, -0.92), "tail", 0, 1)
	Kit.tube("Tail", { V(0, 0.56, -0.9), V(0, 0.5, -1.12), V(0, 0.54, -1.26) }, { 0.07, 0.05, 0.04 }, "pink")
	Kit.tuft("TailTuft", V(0, 0.55, -1.29), 0.05, "pink", 3, true)
	return t
end

------------------------------------------------------------------ the yeti
-- a yeti: a big round body with a smooth front and long pointed locks of fur in tiers down its sides and back, a
-- ragged fringe round its hem, a ruff over the shoulders; a big round head with a cowlick, a fringe falling over a
-- smooth face of the accent, cheek fur, a button nose with a shine, little tusks on a jaw, two big curled horns with
-- rings; long arms with locks hanging from the elbows and big round hands (fingers, a thumb, a palm pad); short legs
-- in shaggy boots on big flat feet with toe pads
PLANS.yeti = function(b, a)
	local t = Kit.new("yeti", 2.6, 1.2, "biped")
	J("body", nil, V(0, 1.0, 0), "body")
	local BC = V(0, 1.1, 0)
	local BRad = 0.7
	local TC = V(0, 0.88, 0.1)
	local TR = 0.65
	Kit.ball("Body", BC, 2 * BRad, b)
	Kit.ball("Tummy", TC, 2 * TR, b)
	-- the fur: the front stays smooth (a calm shape reads better than a heap of lumps); the locks hang in tiers down
	-- the sides and back, the longest in a ragged fringe round the hem
	if full() then
		for _, yaw in { -150, -110, 110, 150, 180 } do
			lock("Ruff", BC, BRad, dir(yaw, 46), 0.32, 0.13, b)
		end
		for _, yaw in { -64, -104, -144, 64, 104, 144, 180 } do
			lock("Fur", BC, BRad, dir(yaw, 6), 0.36, 0.14, b)
		end
		for i = 0, 11 do
			lock("Hem", TC, TR, dir(-165 + i * 30, -36), 0.34, 0.13, b)
		end
	else
		for _, yaw in { -80, 80 } do
			lock("Fur", BC, BRad, dir(yaw, 6), 0.36, 0.15, b)
		end
		for i = 0, 5 do
			lock("Hem", TC, TR, dir(-150 + i * 60, -36), 0.34, 0.15, b)
		end
	end
	-- the head: a big round skull, a cowlick, a fringe over the smooth face of the accent, fur at the cheeks
	J("head", "body", V(0, 1.62, 0.18), "head")
	local HC = V(0, 2.1, 0.26)
	local HR = 0.525
	Kit.ball("Head", HC, 2 * HR, b)
	local FC = HC + V(0, -0.1, 0.24)
	local FR = 0.4
	Kit.ball("Face", FC, 2 * FR, a)
	if full() then
		for i, yaw in { -40, -14, 12, 38 } do
			lock("Fringe", HC, HR, dir(yaw, 36 - math.abs(yaw) * 0.2), if i == 2 or i == 3 then 0.24 else 0.2, 0.11, b)
		end
		for _, yaw in { -74, -104, 74, 104, 150, -150 } do
			lock("Mane", HC, HR, dir(yaw, -6), 0.26, 0.12, b)
		end
		for i, c in { { 0, 0.26, -0.1 }, { -0.12, 0.2, -0.14 }, { 0.12, 0.22, -0.16 } } do
			local root = HC + dir(c[1] * 100, 72) * (HR - 0.06)
			Kit.tube("Cowlick", { root, root + V(c[1], c[2], c[3]) }, { if i == 1 then 0.11 else 0.09, 0.025 }, b, 3)
		end
	else
		for _, yaw in { -20, 20 } do
			lock("Fringe", HC, HR, dir(yaw, 34), 0.24, 0.13, b)
		end
		local root = HC + dir(0, 72) * (HR - 0.06)
		blade("Cowlick", root, root + V(0, 0.24, -0.12), 0.2, 0.1, FWD, b)
	end
	eyes(FC, FR, FWD, R(30), R(14), 0.27, irisOf(a, "blue"))
	Kit.blush(FC, FR + 0.02, FWD, R(50), R(12), 0.14)
	local nose = Kit.onBall(FC, FR, dir(0, -4))
	Kit.ball("Nose", nose, 0.15, shade(a))
	Kit.ball("NoseShine", nose + V(-0.03, 0.04, 0.05), 0.05, "white", true)
	local m, mn = Kit.onBall(FC, FR, dir(0, -30))
	Kit.mouth(m, mn, 0.25)
	-- the horns: big, curling up and out and a little forward, ringed
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local hp = { HC + V(side * 0.32, 0.3, -0.06), HC + V(side * 0.6, 0.38, -0.06), HC + V(side * 0.74, 0.62, 0.02), HC + V(side * 0.64, 0.82, 0.1) }
		local hr = { 0.125, 0.095, 0.065, 0.03 }
		if full() then
			Kit.tube("Horn" .. s, hp, hr, a)
			for _, u in { 0.22, 0.42, 0.62 } do
				local c = Kit.curveAt(hp, u)
				Kit.disc("HornRing" .. s, c, Kit.curveAt(hp, u + 0.03) - Kit.curveAt(hp, u - 0.03), 2 * lerpList(hr, u) + 0.05, 0.05, shade(a), true)
			end
		else
			Kit.tube("Horn" .. s, { hp[1], hp[3], hp[4] }, { 0.12, 0.065, 0.035 }, a, 1.6)
		end
	end
	-- the jaw: a round chin with two little tusks
	J("jaw", "head", V(0, 1.84, 0.5), "jaw")
	Kit.ball("Chin", FC + V(0, -0.3, 0.1), 0.32, a)
	for _, side in { -1, 1 } do
		local base = FC + V(side * 0.12, -0.22, 0.29)
		blade("Tusk", base, base + V(side * 0.02, 0.13, 0.02), 0.08, 0.05, V(0, 0, 1), "white", true)
	end
	-- long arms, locks hanging from their backs, and big round hands
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.82, 1.48, 0.05), "arm", side)
		local ap = { V(side * 0.78, 1.48, 0.04), V(side * 1.0, 1.1, 0.1), V(side * 1.08, 0.82, 0.16) }
		Kit.tube("Arm" .. s, if full() then ap else { ap[1], ap[3] }, { 0.25, 0.22, 0.2 }, b)
		Kit.ball("Shoulder" .. s, V(side * 0.8, 1.54, 0.02), 0.46, b, true)
		if full() then
			for i, u in { 0.25, 0.55, 0.85 } do
				local c = Kit.curveAt(ap, u)
				lock("ArmFur" .. s, c, 0.2, V(side * 0.8, 0.1, -0.5 + i * 0.12), 0.26, 0.11, b)
			end
		end
		local hand = V(side * 1.1, 0.64, 0.22)
		Kit.ball("Hand" .. s, hand, 0.46, b)
		for i, yaw in { -24, 0, 24 } do
			local d = dir(yaw - side * 10, -40)
			Kit.ball("Finger" .. s, hand + d * 0.2, 0.18, b, i ~= 2)
		end
		Kit.ball("Thumb" .. s, hand + V(-side * 0.18, 0.06, 0.12), 0.17, b, true)
		patch("Palm" .. s, hand, 0.23, V(-side * 0.6, -0.1, 1), 0.22, a)
		-- short legs in shaggy boots on big flat feet
		J("leg" .. s, "body", V(side * 0.4, 0.48, 0), "leg", side, if side < 0 then 0 else 0.5)
		Kit.tube("Leg" .. s, { V(side * 0.38, 0.56, 0), V(side * 0.42, 0.22, 0.06) }, { 0.25, 0.23 }, b)
		if full() then
			for _, yaw in { side * 20, side * 80, side * 140 } do
				lock("Boot" .. s, V(side * 0.42, 0.34, 0.04), 0.22, dir(yaw, 0), 0.2, 0.1, b)
			end
		end
		Kit.ball("Heel" .. s, V(side * 0.42, 0.17, 0.02), 0.36, b)
		Kit.ball("Foot" .. s, V(side * 0.44, 0.15, 0.26), 0.32, b)
		Kit.toes("Toe" .. s, V(side * 0.44, 0.1, 0.4), 0.26, 0.14, 3, a)
	end
	return t
end

------------------------------------------------------------------ the seal
-- a seal pup: a plump smooth body tapering from a raised chest to its hips, a pale chest, spots, a round head with big
-- dark eyes, ear holes, brow whiskers and brow spots, round whisker pads with whisker dots, a shiny black nose, long
-- whiskers and a chin on a jaw; front flippers as broad thick paddles with a darker edge and little claws; two hind
-- flippers fanned out behind, each a paddle with rays and a scalloped edge
PLANS.seal = function(b, a)
	local t = Kit.new("seal", 1.6, 1.2, "slither")
	local pale = b == "window" or b == "white" or b == "snow" or b == "ice"
	local dots = if pale then "blue" else shade(b)
	-- (a pale seal's flipper edges and claws take a soft grey-blue; a darker one its own shade)
	local edge = if pale then "ice" else shade(b)
	J("body", nil, V(0, 0.5, 0), "body")
	local BP = { V(0, 0.7, 0.36), V(0, 0.52, -0.2), V(0, 0.36, -0.72), V(0, 0.26, -1.02) }
	local BR = { 0.47, 0.49, 0.35, 0.2 }
	sausage("Body", BP, BR, b)
	Kit.ball("Chest", V(0, 0.56, 0.56), 0.64, a)
	Kit.ball("Chest", V(0, 0.4, 0.38), 0.56, a, true)
	-- spots on the back and upper sides: low domes, so they stay round where they reach the outline
	for _, s in { { 0.24, -18, 0.2 }, { 0.3, 30, 0.15 }, { 0.44, -40, 0.15 }, { 0.48, 8, 0.2 }, { 0.6, 36, 0.14 }, { 0.66, -20, 0.16 }, { 0.8, 6, 0.13 }, { 0.38, 58, 0.1 }, { 0.56, -60, 0.1 } } do
		local at, n = surf(BP, BR, s[1], s[2], 0)
		Kit.ball("Spot", at - n * (s[3] / 2 - 0.04), s[3], dots, s[3] < 0.15)
	end
	-- the head
	J("head", "body", V(0, 0.88, 0.5), "head")
	local HC = V(0, 1.12, 0.62)
	local HR = 0.45
	Kit.ball("Head", HC, 2 * HR, b)
	eyes(HC, HR, FWD, R(32), R(12), 0.31, nil)
	for _, side in { -1, 1 } do
		patch("Brow", HC, HR, dir(side * 26, 40), 0.09, dots, true)
		-- an ear hole well back on each side, and a brow whisker over each eye
		patch("EarHole", HC, HR, dir(side * 84, 14), 0.07, "black", true)
		if full() then
			local w0 = Kit.onBall(HC, HR + 0.01, dir(side * 30, 44))
			Kit.rod("BrowWhisker", w0, w0 + V(side * 0.14, 0.12, 0.04), 0.05, "white")
		end
	end
	Kit.blush(HC, HR + 0.02, FWD, R(52), R(12), 0.15)
	-- the muzzle: two round whisker pads with dots, the nose over them
	for _, side in { -1, 1 } do
		local pc = HC + V(side * 0.09, -0.12, 0.38)
		Kit.ball("Pad", pc, 0.27, a)
		if full() then
			for _, d in { dir(side * 30, 10), dir(side * 48, -4), dir(side * 26, -16), dir(side * 60, 8) } do
				patch("Dot", pc, 0.135, d, 0.05, dots, true)
			end
		end
	end
	local NC = HC + V(0, -0.03, 0.46)
	Kit.ball("Nose", NC, 0.16, "black")
	Kit.ball("NoseShine", NC + V(-0.03, 0.04, 0.05), 0.05, "white", true)
	Kit.mouth(HC + V(0, -0.24, 0.44), V(0, -0.4, 1), 0.14)
	Kit.whiskers(HC + V(0, -0.14, 0.42), 0.34, "white")
	Kit.whiskers(HC + V(0, -0.1, 0.4), 0.28, "white")
	J("jaw", "head", V(0, 0.94, 0.88), "jaw")
	Kit.ball("Chin", HC + V(0, -0.27, 0.35), 0.18, a)
	-- the front flippers: a short thick arm, then a broad paddle with a darker rim and three claws
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("fin" .. s, "body", V(side * 0.42, 0.45, 0.42), "fin", side)
		Kit.tube("Flipper" .. s, { V(side * 0.36, 0.46, 0.42), V(side * 0.52, 0.22, 0.5) }, { 0.17, 0.13 }, b)
		local fp = { V(side * 0.53, 0.15, 0.52), V(side * 0.68, 0.1, 0.64), V(side * 0.8, 0.08, 0.8) }
		local fn = V(side * 0.3, 1, 0).Unit
		paddle("FlipperPad" .. s, fp, { 0.27, 0.31, 0.21 }, fn, 0.1, b)
		if full() then
			-- (the rim: a row of beads round its far edge, a shade darker)
			for _, u in { 0.55, 0.78, 0.96 } do
				local c = Kit.curveAt(fp, u)
				local tng = (Kit.curveAt(fp, math.min(1, u + 0.05)) - Kit.curveAt(fp, math.max(0, u - 0.05))).Unit
				local w = lerpList({ 0.27, 0.31, 0.21 }, u)
				for _, k in { -1, 1 } do
					local across = tng:Cross(fn).Unit * k
					Kit.ball("FlipperRim" .. s, c + across * (w * 0.45) + fn * 0.01, 0.09, edge, true)
				end
			end
			for k = -1, 1 do
				local c = fp[3] + V(0, 0.07, 0.02) + V(side * 0.06, 0, -0.02) * k
				Kit.ball("Claw" .. s, c, 0.06, dots, true)
			end
		end
	end
	-- the hind flippers fanned out behind: a fleshy root, a broad fan with rays and a scalloped edge
	J("tail", "body", V(0, 0.32, -0.95), "tail", 0, 1)
	Kit.tube("Tail", { V(0, 0.27, -0.98), V(0, 0.2, -1.2) }, { 0.18, 0.12 }, b)
	Kit.tube("TailNub", { V(0, 0.22, -1.18), V(0, 0.22, -1.36) }, { 0.08, 0.04 }, b, 2, true)
	for _, side in { -1, 1 } do
		-- (each fan tipped up on its inner edge, so it shows its shape from the side as well as from above)
		local fp = { V(side * 0.05, 0.18, -1.2), V(side * 0.22, 0.17, -1.4), V(side * 0.4, 0.22, -1.56) }
		local fn = V(-side * 0.7, 1, 0)
		Kit.tube("FlukeRoot", { fp[1], fp[2] }, { 0.1, 0.07 }, b)
		-- (the fan: one flat triangle, narrow at the root and wide at the end, so it shows no seams)
		blade("Fluke", fp[3] + (fp[3] - fp[1]).Unit * 0.04, fp[1] + (fp[2] - fp[1]) * 0.3, 0.42, 0.08, fn, b)
		if full() then
			Kit.rod("FlukeRay", fp[2] + V(0, 0.06, 0), fp[3] + V(side * 0.02, 0.05, 0.08), 0.05, edge, true)
			Kit.rod("FlukeRay", fp[2] + V(0, 0.06, 0), fp[3] + V(side * 0.05, 0.05, -0.06), 0.05, edge, true)
			-- the scalloped trailing edge: three soft lobes at the end of the fan
			for k = -1, 1 do
				Kit.ball("FlukeLobe", fp[3] + V(side * (0.1 + 0.05 * k), 0.0, -0.1 * k - 0.06), 0.13, b, true)
			end
		end
	end
	return t
end

------------------------------------------------------------------ the golem
-- a stone golem: rounded stones heaped into a hunched body, a broad chest of three stones over a narrower waist, a
-- head stone sunk between big shoulder stones under a heavy brow, big eyes and a smile in it, long arms of stones
-- ending in big fists with knuckles and a thumb, stubby legs on round feet with toe stones, flecks of another stone
-- all over. What grows on it goes by its colour: moss and a sprout on an old one (with a guard's emblem, a keyhole and
-- cuffs in the accent), glowing seams and a glowing core on a hot one, snow domes, icicles and ice crystals on an icy
-- one
local function stoneGolem(b: string, a: string): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local icy = b == "window" or b == "ice" or b == "snow" or b == "white"
	local hot = (a == "orange" or a == "lava") and not icy
	local old = not hot and not icy
	local green = if a == "leaf" or a == "leaf_dark" or a == "moss" or a == "green" then a else "moss"
	local line = if hot then a elseif icy then "blue" else shade(b)
	local fleck = if icy then "ice" else shade(b)
	local snow = if icy then a else "white"
	local lw = if hot then 0.08 else 0.06
	-- flecks of another stone on a stone (only a close look shows them)
	local function flecks(c: Vector3, r: number, list: { { number } })
		for _, f in list do
			patch("Fleck", c, r, dir(f[1], f[2]), f[3], fleck, true)
		end
	end
	J("body", nil, V(0, 1.0, 0), "body")
	-- the chest: three stones side by side, a waist under it
	local CC = V(0, 1.36, -0.02)
	local CR = 0.5
	Kit.ball("Chest", CC, 2 * CR, b)
	Kit.ball("Chest", CC + V(-0.26, -0.02, -0.04), 0.9, b)
	Kit.ball("Chest", CC + V(0.26, -0.02, -0.04), 0.9, b)
	Kit.ball("Waist", V(0, 0.86, 0.02), 0.92, b)
	Kit.ball("Lump", V(0.22, 1.02, -0.3), 0.6, b, true)
	-- a ring of smaller stones where the chest sits on the waist, so it reads as stones stacked up
	if full() then
		for i, yaw in { -104, -62, -22, 20, 60, 102 } do
			-- (on a hot one every other small stone is an ember glowing between the big ones)
			local ember = hot and i % 2 == 1
			Kit.ball("Pebble", V(0, 1.0, 0.02) + dir(yaw, 0) * (if ember then 0.44 else 0.46), if i % 2 == 0 then 0.2 else 0.15, if ember then a else b, false, ember)
		end
	end
	flecks(CC, CR, { { -30, 20, 0.16 }, { 24, -16, 0.12 }, { -8, -36, 0.1 }, { 40, 24, 0.09 } })
	flecks(V(0, 0.86, 0.02), 0.46, { { 30, -10, 0.12 }, { -36, -30, 0.1 } })
	if hot then
		-- the hot core: a glowing stone set in the chest, seams running out of it
		local cn = dir(0, -6)
		Kit.ball("Core", CC + cn * (CR - 0.08), 0.32, a, false, true)
		seam("Seam", CC, CR, { dir(-14, 6), dir(-30, 18), dir(-26, 34) }, lw, a, false, true)
		seam("Seam", CC, CR, { dir(16, -14), dir(32, -24), dir(28, -40) }, lw, a, true, true)
		seam("Seam", V(0, 0.86, 0.02), 0.46, { dir(-20, 4), dir(-12, -20), dir(-24, -38) }, lw, a, false, true)
	else
		seam("Crack", CC, CR, { dir(-40, 40), dir(-32, 28), dir(-38, 14), dir(-30, 2) }, lw, line, false)
		seam("Crack", V(0, 0.86, 0.02), 0.46, { dir(30, 0), dir(40, -14), dir(34, -28) }, lw, line, true)
	end
	if old then
		-- an old guard's emblem: a round plate in the accent with a keyhole
		local cn = dir(0, -10)
		local cc = CC + cn * CR
		patch("Emblem", CC, CR, cn, 0.3, a)
		patch("Keyhole", CC, CR + 0.05, cn + V(0, 0.08, 0), 0.1, "black")
		Kit.rod("Keyhole", cc + cn * 0.09 + V(0, -0.01, 0), cc + cn * 0.09 + V(0, -0.1, 0), 0.05, "black")
	elseif icy then
		-- crystals of ice standing out of the back and the shoulders
		for i, s in { { -0.3, 0.2, -0.3, 0.42 }, { 0.02, 0.3, -0.36, 0.5 }, { 0.32, 0.18, -0.28, 0.38 }, { -0.12, 0.08, -0.46, 0.3 } } do
			local base = CC + V(s[1], s[2], s[3])
			local tip = base + V(s[1] * 0.5, s[4], -0.16)
			Kit.tube("Crystal", { base, tip }, { 0.13, 0.03 }, snow, 2, i == 4)
		end
	end
	-- the head: a round stone sunk between the shoulders, a heavy brow, the face
	J("head", "body", V(0, 1.72, 0.08), "head")
	local HC = V(0, 2.0, 0.2)
	local HR = 0.45
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.tube("Brow", { HC + dir(-36, 22) * (HR + 0.01), HC + dir(0, 27) * (HR + 0.05), HC + dir(36, 22) * (HR + 0.01) }, { 0.08, 0.1, 0.08 }, b)
	-- a heavy jaw stone under the face, and a small stone at each cheek
	Kit.ball("Jaw", HC + V(0, -0.3, 0.06), 0.42, b)
	for _, side in { -1, 1 } do
		Kit.ball("CheekStone", HC + V(side * 0.34, -0.12, 0.08), 0.24, b, true)
	end
	-- (a hot one's eyes and smile are its fire showing through: dark eyes would be lost on its dark stone)
	eyes(HC, HR, FWD, R(26), R(2), 0.28, if hot then "yellow" else irisOf(a, "blue"), if hot then a else nil)
	local m, mn = Kit.onBall(HC, HR, dir(0, -28))
	Kit.mouth(m, mn, 0.22, if hot then a else nil)
	Kit.blush(HC, HR + 0.02, FWD, R(48), R(14), 0.14)
	flecks(HC, HR, { { 40, 44, 0.12 }, { -50, -10, 0.1 } })
	if hot then
		seam("Seam", HC, HR, { dir(30, 56), dir(40, 40), dir(34, 28) }, lw, a, true, true)
	else
		seam("Crack", HC, HR, { dir(28, 54), dir(36, 40), dir(30, 28) }, lw, line, true)
	end
	-- on top: a moss cushion with a sprout on an old one, a dome of snow and icicles on an icy one
	local top = HC + V(0, HR - 0.08, -0.04)
	if old then
		Kit.ball("Moss", top + V(0, -0.1, 0), 0.6, green)
		Kit.tuft("Moss", top + V(-0.18, 0.06, 0.1), 0.12, shade(green), 3, true)
		Kit.tuft("Moss", top + V(0.2, 0.04, -0.08), 0.1, green, 3, true)
		-- (little white flowers in the moss)
		for _, f in { { -0.22, 0.1, 0.16 }, { 0.16, 0.08, 0.18 }, { -0.04, 0.14, -0.22 } } do
			Kit.ball("Flower", top + V(f[1], f[2], f[3]), 0.09, "white", true)
			Kit.ball("FlowerEye", top + V(f[1], f[2] + 0.03, f[3]), 0.05, "yellow", true)
		end
		Kit.rod("Stem", top + V(0.04, 0.12, 0), top + V(0.08, 0.42, 0.02), 0.06, "leaf_dark")
		blade("Leaf", top + V(0.08, 0.4, 0.02), top + V(0.36, 0.52, 0.06), 0.16, 0.05, V(0, 1, 0.2), "leaf")
		blade("Leaf", top + V(0.08, 0.38, 0.02), top + V(-0.18, 0.54, 0.0), 0.14, 0.05, V(0, 1, 0.2), "leaf", true)
	elseif icy then
		Kit.ball("Snow", top + V(0, -0.12, 0), 0.66, snow)
		Kit.ball("Snow", top + V(-0.16, -0.04, 0.06), 0.3, snow, true)
		Kit.tube("Crystal", { top + V(0.12, 0.1, -0.04), top + V(0.24, 0.42, -0.1) }, { 0.1, 0.025 }, snow, 2)
		for i, yaw in { -36, -8, 26 } do
			local p = HC + dir(yaw, 24) * (HR + 0.04)
			Kit.tube("Icicle", { p, p + V(0, -0.2 - (i % 2) * 0.06, 0.03) }, { 0.05, 0.025 }, snow, nil, true)
		end
	end
	-- the arms: a big shoulder stone, a small upper arm, a long forearm of two stones, a big fist
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.74, 1.55, 0), "arm", side)
		local sh = V(side * 0.76, 1.56, -0.04)
		Kit.ball("Shoulder" .. s, sh, 0.66, b)
		-- (a flatter cap stone on top of the shoulder stone)
		Kit.ball("ShoulderCap" .. s, sh + V(side * 0.05, 0.24, -0.02), 0.36, b)
		flecks(sh, 0.33, { { side * 70, 30, 0.12 }, { side * 40, -10, 0.09 } })
		Kit.ball("Arm" .. s, V(side * 0.88, 1.22, 0.04), 0.4, b)
		local fa = V(side * 0.94, 0.92, 0.1)
		Kit.ball("Forearm" .. s, fa, 0.5, b)
		Kit.ball("Forearm" .. s, V(side * 0.92, 0.76, 0.12), 0.46, b, true)
		local fist = V(side * 0.96, 0.5, 0.16)
		Kit.ball("Fist" .. s, fist, 0.58, b)
		for i, yaw in { -26, 0, 26 } do
			Kit.ball("Knuckle" .. s, fist + dir(yaw - side * 12, -4) * 0.27, 0.17, b, i == 2)
		end
		Kit.ball("Thumb" .. s, fist + V(-side * 0.22, 0.08, 0.14), 0.18, b, true)
		flecks(fist, 0.29, { { side * 60, 20, 0.1 } })
		if hot then
			seam("Seam" .. s, fa, 0.25, { dir(side * 70, 34), dir(side * 60, 4), dir(side * 74, -24) }, lw, a, false, true)
			-- the fire showing through cracks in the fist and the shoulder too
			seam("Seam" .. s, fist, 0.29, { dir(side * 40, 40), dir(side * 20, 12), dir(side * 34, -14) }, lw, a, true, true)
			seam("Seam" .. s, sh, 0.33, { dir(side * 30, 50), dir(side * 60, 30), dir(side * 56, 6) }, lw, a, true, true)
		elseif icy then
			Kit.ball("Snow" .. s, sh + V(0, 0.14, 0), 0.5, snow)
			Kit.tube("Crystal" .. s, { sh + V(side * 0.12, 0.2, -0.08), sh + V(side * 0.3, 0.5, -0.14) }, { 0.12, 0.03 }, snow, 2)
			Kit.tube("Crystal" .. s, { sh + V(side * 0.02, 0.24, -0.14), sh + V(side * 0.04, 0.46, -0.3) }, { 0.09, 0.025 }, snow, 2, true)
			Kit.tube("Icicle" .. s, { fa + V(side * 0.14, -0.06, 0.12), fa + V(side * 0.15, -0.28, 0.13) }, { 0.045, 0.025 }, snow, nil, true)
			-- (frost on the knuckles)
			Kit.ball("Frost" .. s, fist + V(0, 0.2, 0.08), 0.3, snow, true)
		else
			Kit.ball("ShoulderMoss" .. s, sh + V(0, 0.16, 0), 0.46, green, side > 0)
			Kit.tuft("ShoulderMoss" .. s, sh + V(side * 0.06, 0.3, 0.06), 0.1, shade(green), 3, true)
			-- a guard's cuff on the forearm, and old marks cut in the upper arm in the accent
			Kit.disc("Cuff" .. s, fa + V(0, -0.02, 0), V(side * 0.2, 1, 0), 0.56, 0.1, a)
			seam("Rune" .. s, V(side * 0.88, 1.22, 0.04), 0.2, { dir(side * 50, 30), dir(side * 30, 0), dir(side * 50, -30) }, 0.05, a, true)
			if side < 0 and full() then
				-- a vine hanging from the shoulder moss down the arm, with leaves
				local vp = { sh + V(side * 0.1, 0.12, 0.2), sh + V(side * 0.2, -0.16, 0.24), V(side * 0.98, 1.04, 0.28) }
				Kit.tube("Vine" .. s, vp, { 0.035, 0.03, 0.025 }, "leaf_dark", 1.4)
				for i, u in { 0.35, 0.75 } do
					local c = Kit.curveAt(vp, u)
					blade("VineLeaf" .. s, c, c + V(side * 0.12, 0.02, 0.06 * (if i == 1 then 1 else -1)), 0.09, 0.05, V(0, 0.4, 1), green)
				end
			end
		end
		-- stubby legs on round feet with toe stones
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		Kit.ball("Leg" .. s, V(side * 0.36, 0.42, 0.02), 0.48, b)
		Kit.ball("Knee" .. s, V(side * 0.38, 0.46, 0.2), 0.26, b, true)
		if full() then
			local foot = V(side * 0.38, 0.15, 0.24)
			if hot then
				seam("Seam" .. s, V(side * 0.36, 0.42, 0.02), 0.24, { dir(side * 30, 30), dir(side * 10, 4), dir(side * 26, -24) }, lw, a, false, true)
			elseif icy then
				Kit.ball("SnowToe" .. s, foot + V(0, 0.1, 0.02), 0.22, snow)
			else
				-- moss creeping up one knee, a tuft of grass at the other foot
				if side < 0 then
					Kit.ball("KneeMoss" .. s, V(side * 0.4, 0.56, 0.22), 0.18, green)
				else
					for i, yaw in { -30, 0, 30 } do
						local base = foot + V(side * 0.14, -0.08, -0.04)
						blade("Grass" .. s, base, base + dir(yaw + side * 40, 70) * (0.16 + (i % 2) * 0.05), 0.05, 0.05, FWD, green)
					end
				end
			end
		end
		Kit.ball("Heel" .. s, V(side * 0.38, 0.17, 0.04), 0.34, b)
		Kit.ball("Foot" .. s, V(side * 0.38, 0.15, 0.24), 0.3, b)
		Kit.toes("Toe" .. s, V(side * 0.38, 0.1, 0.36), 0.24, 0.13, 3, b)
	end
	return t
end

-- a tree golem: a stout trunk with raised bark ridges, a knot hole with a toadstool by it and moss, a round head of wood
-- under a bushy crown of leaves with blossoms in it and vines hanging from it, the face carved in it, branch arms with
-- bark rings, leaves and twig fingers, root feet with two little toadstools by them. A silver one (Silverbark, "the
-- oldest tree in the wood") grows leaves of its accent, glowing fruit in its crown and glowing sap at its knot hole.
local function woodGolem(b: string, a: string): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local bark = shade(b)
	local moon = b == "steel"
	local leaf = if a == "leaf" or a == "leaf_dark" or a == "moss" or a == "green" or moon then a else "leaf"
	J("body", nil, V(0, 1.0, 0), "body")
	-- (a straight trunk: a point on it is its height `u` up and `ang` degrees round from the front)
	local TP = { V(0, 0.5, 0.02), V(0, 1.1, 0.02), V(0, 1.66, 0.02) }
	local TR = { 0.62, 0.54, 0.56 }
	local function trunkAt(u: number, ang: number, lift: number): (Vector3, Vector3)
		local n = dir(ang, 0)
		return Kit.curveAt(TP, u) + n * (lerpList(TR, u) + lift), n
	end
	sausage("Trunk", TP, TR, b)
	-- raised bark ridges up the trunk, a little wavy
	if full() then
		for i, ang in { -112, -70, -28, 14, 56, 98 } do
			local pts: { Vector3 } = {}
			for k = 0, 2 do
				local wave = (if k == 1 then 6 else 0) * (if i % 2 == 0 then 1 else -1)
				table.insert(pts, (trunkAt(0.04 + k * 0.42, ang + wave, -0.025)))
			end
			Kit.tube("Bark", pts, { 0.055, 0.045 }, bark, 2.2)
		end
	end
	-- the knot hole, a toadstool by it, moss on the shoulders of the trunk
	local kc, kn = trunkAt(0.42, 20, 0)
	Kit.disc("Knot", kc + kn * 0.02, kn, 0.3, 0.05, bark)
	Kit.disc("KnotHole", kc + kn * 0.06, kn, 0.17, 0.05, "black")
	if moon then
		-- (sap glowing at the knot hole's lip, one drop running down)
		Kit.ball("Sap", kc + kn * 0.1 + V(0.03, -0.07, 0), 0.08, a, false, true)
		Kit.ball("Sap", kc + kn * 0.06 + V(0.04, -0.2, 0), 0.06, a, true, true)
	end
	local mp, mpn = trunkAt(0.28, -34, 0)
	Kit.rod("ToadstoolStem", mp - mpn * 0.02, mp + V(0, 0.1, 0) + mpn * 0.06, 0.07, "cream", true)
	Kit.disc("Toadstool", mp + V(0, 0.12, 0) + mpn * 0.07, UP, 0.2, 0.07, if moon then a else "berry_red", true)
	Kit.ball("ToadstoolSpot", mp + V(0, 0.17, 0) + mpn * 0.07, 0.05, "white", true)
	for _, side in { -1, 1 } do
		local p = trunkAt(0.95, side * 40, -0.1)
		Kit.ball("Moss", p, 0.36, leaf)
		Kit.tuft("Moss", p + V(side * 0.12, 0.08, 0.06), 0.09, shade(leaf), 3, true)
	end
	-- the head: a round knob of wood, the face carved in it, a bushy crown of leaves
	J("head", "body", V(0, 1.72, 0.08), "head")
	local HC = V(0, 2.02, 0.16)
	local HR = 0.45
	Kit.ball("Head", HC, 2 * HR, b)
	local bp = { HC + dir(-36, 22) * (HR + 0.01), HC + dir(0, 27) * (HR + 0.04), HC + dir(36, 22) * (HR + 0.01) }
	Kit.tube("Brow", if full() then bp else { bp[1], bp[3] }, { 0.07, 0.08, 0.07 }, bark)
	eyes(HC, HR, FWD, R(26), R(2), 0.28, irisOf(a, "leaf"))
	local m, mn = Kit.onBall(HC, HR, dir(0, -28))
	Kit.mouth(m, mn, 0.22)
	Kit.blush(HC, HR + 0.02, FWD, R(48), R(14), 0.14)
	seam("Grain", HC, HR, { dir(46, 40), dir(52, 20), dir(48, 0) }, 0.05, bark, true)
	seam("Grain", HC, HR, { dir(-50, 36), dir(-56, 16) }, 0.05, bark, true)
	-- the crown: round clumps of leaves, darker underneath, a few single leaves standing out
	local CT = HC + V(0, HR + 0.08, -0.06)
	Kit.ball("Crown", CT, 0.62, leaf)
	for i, c in { { -0.3, -0.06, 0.08, 0.44 }, { 0.3, -0.04, 0.04, 0.44 }, { 0.02, -0.06, -0.3, 0.46 }, { -0.16, 0.1, -0.2, 0.36 }, { 0.18, 0.12, -0.18, 0.34 }, { 0.04, 0.16, 0.18, 0.3 } } do
		Kit.ball("Crown", CT + V(c[1], c[2], c[3]), c[4], if i <= 3 then shade(leaf) else leaf, i > 3)
	end
	for i, c in { { -0.36, 0.06, -0.14, 0.34 }, { 0.34, 0.08, -0.12, 0.32 }, { -0.2, 0.0, 0.26, 0.3 } } do
		Kit.ball("Crown", CT + V(c[1], c[2], c[3]), c[4], if i == 2 then shade(leaf) else leaf, true)
	end
	for i, l in { { -0.42, 0.06, 0.2 }, { 0.44, 0.1, 0.12 }, { -0.1, 0.36, 0.1 }, { 0.2, 0.3, -0.3 } } do
		local base = CT + V(l[1] * 0.6, l[2] * 0.6, l[3] * 0.6)
		blade("Leaf", base, CT + V(l[1], l[2], l[3]) * 1.25, 0.16, 0.05, V(0, 1, 0.2), leaf, i > 2 or not full())
	end
	-- blossoms in the crown (glowing fruit on a silver one), and two vines hanging from its sides
	if full() then
		for _, f in { { -0.24, 0.24, 0.16 }, { 0.26, 0.18, 0.12 }, { 0.06, 0.32, -0.12 } } do
			local p = CT + V(f[1], f[2], f[3])
			if moon then
				Kit.ball("Fruit", p, 0.1, a, false, true)
			else
				Kit.ball("Blossom", p, 0.11, "white")
				Kit.ball("BlossomEye", p + V(0, 0.04, 0.02), 0.05, "yellow")
			end
		end
		for _, side in { -1, 1 } do
			local v0 = CT + V(side * 0.42, -0.14, -0.06)
			local vp = { v0, v0 + V(side * 0.06, -0.22, 0.04), v0 + V(side * 0.02, -0.42, 0.06) }
			Kit.tube("Vine", vp, { 0.035, 0.03, 0.025 }, shade(leaf), 1.4)
			blade("VineLeaf", vp[3], vp[3] + V(side * 0.1, -0.06, 0.06), 0.09, 0.05, V(0, 0.3, 1), leaf)
		end
	end
	-- branch arms: a bough out of the shoulder, a leafy twig at the elbow, twig fingers
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.6, 1.55, 0), "arm", side)
		local ap = { V(side * 0.5, 1.56, 0), V(side * 0.84, 1.36, 0.02), V(side * 0.98, 1.0, 0.08), V(side * 1.0, 0.68, 0.14) }
		Kit.tube("Arm" .. s, if full() then ap else { ap[1], ap[2], ap[4] }, { 0.22, 0.19, 0.16, 0.15 }, b)
		Kit.tube("ArmTwig" .. s, { V(side * 0.92, 1.24, 0.04), V(side * 1.12, 1.4, 0.06), V(side * 1.2, 1.56, 0.04) }, { 0.06, 0.045, 0.035 }, b, nil, true)
		blade("ArmLeaf" .. s, V(side * 1.2, 1.54, 0.04), V(side * 1.44, 1.66, 0.1), 0.18, 0.05, V(0, 1, 0.3), leaf, true)
		blade("ArmLeaf" .. s, V(side * 1.18, 1.5, 0.04), V(side * 1.26, 1.74, -0.12), 0.16, 0.05, V(1, 0.3, 0), shade(leaf), true)
		-- (rings in the bark of the bough)
		for _, u in { 0.3, 0.62 } do
			local c = Kit.curveAt(ap, u)
			Kit.disc("BarkRing" .. s, c, Kit.curveAt(ap, u + 0.03) - Kit.curveAt(ap, u - 0.03), 2 * lerpList({ 0.22, 0.19, 0.16, 0.15 }, u) + 0.05, 0.05, bark, true)
		end
		local wrist = V(side * 1.0, 0.62, 0.15)
		Kit.ball("Fist" .. s, wrist, 0.36, b)
		for i, d in { dir(-side * 24, -56), dir(side * 4, -72), dir(side * 32, -56) } do
			if full() then
				Kit.tube("Twig" .. s, { wrist + d * 0.12, wrist + d * 0.3, wrist + d * 0.4 + V(0, 0.02, 0.06) }, { 0.065, 0.05, 0.035 }, b)
			elseif i ~= 2 then
				Kit.ball("Twig" .. s, wrist + d * 0.22, 0.14, b)
			end
		end
		-- root legs: a stump on roots spreading over the ground
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		Kit.tube("Leg" .. s, { V(side * 0.34, 0.52, 0.02), V(side * 0.38, 0.18, 0.06) }, { 0.22, 0.21 }, b)
		for i, yaw in { side * 14, side * 80, -side * 40 } do
			local d = dir(yaw, 0)
			local f = V(side * 0.38, 0.13, 0.06)
			Kit.tube("Root" .. s, { f + d * 0.1, f + d * 0.4 + V(0, -0.08, 0) }, { 0.12, 0.045 }, b, 1.4, i > 1)
		end
		if side < 0 and full() then
			-- two little toadstools growing on the outer root
			local f, d = V(side * 0.38, 0.13, 0.06), dir(side * 80, 0)
			for i, st in { { 0.2, 0.06, 0.16 }, { 0.32, -0.05, 0.11 } } do
				local base = f + d * st[1] + V(0, 0.1 - st[1] * 0.2, st[2])
				local hgt = 0.1 + st[3] * 0.6
				Kit.rod("RootStool", base, base + V(0, hgt, 0), 0.05 + (if i == 1 then 0.02 else 0), "cream")
				Kit.disc("RootStool", base + V(0, hgt - 0.01, 0), UP, st[3] + 0.06, 0.06, if moon then a else "berry_red")
			end
		end
	end
	return t
end

PLANS.golem = function(b, a)
	-- (a silver tree, Silverbark, is a tree golem too)
	if b == "wood" or b == "wood_dark" or b == "steel" then
		return woodGolem(b, a)
	end
	return stoneGolem(b, a)
end

return PLANS
