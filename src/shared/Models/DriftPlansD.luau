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
-- lays each half wedge with its tall end toward the point it is given as the tip: a Roblox wedge is tall at its back,
-- +Z, and Raster draws it so. So it is given the other way round here.)
local function blade(name: string, base: Vector3, tip: Vector3, w: number, th: number, normal: Vector3, color: string, detail: boolean?): BasePart?
	return Kit.blade(name, tip, base, w, th, normal, color, detail)
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

-- Fur in rows on a ball: tufts (small balls bulging well out of it) at the pitches in `rows` (degrees), `count`
-- round each from yaw `y0` to `y1`, every other row turned half a step so they sit like shingles.
local function shag(name: string, c: Vector3, r: number, rows: { { number } }, d: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	for ri, row in rows do
		local pitch, count, y0, y1 = row[1], row[2], row[3], row[4]
		for i = 0, count - 1 do
			local f = if count == 1 then 0.5 else i / (count - 1)
			if y1 - y0 >= 359 then
				f = (i + (if ri % 2 == 0 then 0.5 else 0)) / count
			end
			local yaw = y0 + (y1 - y0) * f
			local p = c + dir(yaw, pitch) * (r - d * 0.12)
			Kit.ball(name, p, d, color)
		end
	end
end

-- Locks of long fur hanging from a ball: at pitch `pitch`, `count` round it from yaw `y0` to `y1`, each a short tube
-- running down the surface and a little out, thick at the root and pointed at the end.
local function locks(name: string, c: Vector3, r: number, pitch: number, count: number, y0: number, y1: number, len: number, thick: number, color: string, detail: boolean?)
	if detail and not full() then
		return
	end
	for i = 0, count - 1 do
		local f = if y1 - y0 >= 359 then i / count else (if count == 1 then 0.5 else i / (count - 1))
		local yaw = y0 + (y1 - y0) * f
		local n = dir(yaw, pitch)
		local down = dir(yaw, pitch - 90)
		local p0 = c + n * (r - thick * 0.4)
		if full() then
			Kit.tube(name, { p0, p0 + down * len + n * (thick * 0.5) }, { thick, thick * 0.3 }, color, 3)
		else
			-- (on the islands a lock is one ball, hanging a little)
			Kit.ball(name, p0 + down * len * 0.3, thick * 2, color)
		end
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
	-- the crest: little spines along the spine, the tallest at the shoulders
	for i = 0, 5 do
		local u = 0.12 + i * 0.16
		local base = surf(BP, BR, u, 0, -0.03)
		local hgt = 0.12 + 0.05 * math.sin(i / 5 * math.pi)
		blade("Crest", base, base + V(0, hgt, -0.07), 0.13, 0.05, V(1, 0, 0), a, true)
	end
	-- the head: a broad round skull, full jowls, a round snout with nostrils, the cream chin on the jaw
	J("head", "body", V(0, 0.68, 0.66), "head")
	local HC = V(0, 0.86, 0.98)
	local HR = 0.4
	Kit.ball("Head", HC, 2 * HR, b)
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
				Kit.ball("Pad" .. l.n, tip, 0.12, a, true)
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
-- a fox pup: a chubby body on round haunches, a fluffy cream chest ruff, a big head with a cream lower face and cheek
-- fluff, a long pointed muzzle with cream whisker pads and a black nose, big flat ears with dark tips and cream
-- insides, short legs in socks of the accent with toe beads, and a big bushy tail, fat in the middle and tipped in the
-- accent
PLANS.pup = function(b, a)
	local t = Kit.new("pup", 2.2, 1.1, "quad")
	J("body", nil, V(0, 0.85, 0), "body")
	local BP = { V(0, 0.82, -0.42), V(0, 0.86, -0.08), V(0, 0.94, 0.26) }
	local BR = { 0.4, 0.37, 0.4 }
	sausage("Body", BP, BR, b)
	-- the chest ruff
	Kit.tuft("Ruff", V(0, 0.96, 0.62), 0.2, "cream", nil, false)
	Kit.tuft("Ruff", V(-0.18, 1.1, 0.56), 0.15, "cream", 3, true)
	Kit.tuft("Ruff", V(0.18, 1.1, 0.56), 0.15, "cream", 3, true)
	Kit.tuft("Ruff", V(0, 0.74, 0.58), 0.17, "cream", 3, false)
	-- four short legs in socks, round paws with toe beads; round haunches over the hind ones
	for _, l in { { n = "FL", s = -1, z = 0.3, ph = 0 }, { n = "FR", s = 1, z = 0.3, ph = 0.5 }, { n = "BL", s = -1, z = -0.44, ph = 0.5 }, { n = "BR", s = 1, z = -0.44, ph = 0 } } do
		local s, z = l.s, l.z
		J("leg" .. l.n, "body", V(s * 0.22, 0.6, z), "leg", s, l.ph)
		local hind = z < 0
		local zf = z + (if hind then 0.02 else 0.04)
		if hind then
			Kit.ball("Haunch" .. l.n, V(s * 0.22, 0.7, z - 0.02), 0.52, b)
		end
		if not full() then
			Kit.tube("Leg" .. l.n, { V(s * 0.23, if hind then 0.6 else 0.72, z), V(s * 0.25, 0.22, zf) }, { 0.15, 0.13 }, b)
		elseif hind then
			Kit.tube("Leg" .. l.n, { V(s * 0.24, 0.56, z), V(s * 0.25, 0.32, z - 0.05), V(s * 0.25, 0.16, z + 0.02) }, { 0.15, 0.13, 0.12 }, b)
		else
			Kit.tube("Leg" .. l.n, { V(s * 0.22, 0.72, z), V(s * 0.24, 0.42, z + 0.02), V(s * 0.25, 0.16, z + 0.04) }, { 0.16, 0.13, 0.12 }, b)
		end
		if full() then
			Kit.tube("Sock" .. l.n, { V(s * 0.25, 0.32, zf - (if hind then 0.05 else 0.01)), V(s * 0.25, 0.17, zf) }, { 0.145, 0.14 }, a)
		end
		Kit.ball("Paw" .. l.n, V(s * 0.25, 0.12, zf + 0.06), 0.28, a)
		Kit.toes("Toe" .. l.n, V(s * 0.25, 0.08, zf + 0.17), 0.17, 0.1, 3, a)
	end
	-- the tail: a big brush, thin at the root, fat in the middle, sweeping back and up to a soft point in the accent,
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
	end
	-- the head
	J("head", "body", V(0, 1.18, 0.48), "head")
	local HC = V(0, 1.56, 0.66)
	local HR = 0.475
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.tuft("Crown", HC + V(0, HR - 0.04, 0), 0.1, b, 3, true)
	-- the cream lower face, a point of fluff back from each cheek
	Kit.ball("Jowls", HC + V(0, -0.24, 0.16), 0.66, "cream")
	for _, side in { -1, 1 } do
		Kit.tube("CheekFluff", { HC + V(side * 0.3, -0.26, 0.04), HC + V(side * 0.5, -0.36, -0.12) }, { 0.12, 0.035 }, "cream", nil, true)
		Kit.tube("CheekFluff", { HC + V(side * 0.26, -0.36, 0.06), HC + V(side * 0.4, -0.48, -0.08) }, { 0.09, 0.03 }, "cream", nil, true)
	end
	-- the long pointed muzzle, cream whisker pads under its end, the black nose on its tip
	sausage("Muzzle", { HC + V(0, -0.04, 0.32), HC + V(0, -0.14, 0.72) }, { 0.19, 0.1 }, b, if full() then 0.5 else 1.2)
	Kit.ball("Pad", HC + V(-0.065, -0.22, 0.62), 0.17, "cream")
	Kit.ball("Pad", HC + V(0.065, -0.22, 0.62), 0.17, "cream")
	Kit.ball("Nose", HC + V(0, -0.11, 0.82), 0.15, "black")
	Kit.mouth(HC + V(0, -0.3, 0.64), V(0, -0.5, 1), 0.14, nil, "pink")
	eyes(HC, HR, FWD, R(30), R(12), 0.29, irisOf(a, "blue"))
	Kit.blush(HC, HR + 0.02, FWD, R(50), R(4), 0.15)
	J("jaw", "head", V(0, 1.3, 1.0), "jaw")
	Kit.ball("Chin", HC + V(0, -0.33, 0.52), 0.2, "cream")
	-- big ears: flat triangles with round rims, dark tips, cream insides with a tuft at the base
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local B = HC + V(side * 0.25, 0.3, -0.06)
		local T = HC + V(side * 0.5, 0.94, -0.14)
		J("ear" .. s, "head", B, "ear", side)
		if full() then
			local up = (T - B).Unit
			local n = V(side * 0.3, 0.1, 1).Unit
			n = (n - up * n:Dot(up)).Unit
			local across = up:Cross(n).Unit
			local w = 0.5
			local function mix(p: Vector3, q: Vector3, u: number): Vector3
				return p + (q - p) * u
			end
			for _, k in { -1, 1 } do
				local base = B + across * k * w / 2
				Kit.tube("EarRim" .. s, { base, mix(base, T, 0.7) }, { 0.08, 0.055 }, b)
				Kit.tube("EarTip" .. s, { mix(base, T, 0.66), T }, { 0.065, 0.04 }, "black")
			end
			blade("Ear" .. s, B, T, w, 0.1, n, b)
			blade("EarTip" .. s, mix(B, T, 0.64), T, w * 0.38, 0.16, n, "black")
			blade("EarIn" .. s, B + n * 0.08 + up * 0.02, mix(B, T, 0.62) + n * 0.08, w * 0.7, 0.05, n, "cream")
			Kit.tuft("EarFluff" .. s, B + n * 0.1 + up * 0.08, 0.09, "cream", 3, true)
		else
			Kit.tube("Ear" .. s, { B, T }, { 0.21, 0.04 }, b, 2)
			Kit.ball("EarTip" .. s, T + (B - T) * 0.2, 0.12, "black")
		end
	end
	return t
end

------------------------------------------------------------------ the mole
-- a mole: a fat velvety pear of a body with a pale belly and fur partings down its back (glowing cracks on a hot one),
-- a round head with a cowlick, a pink snout ending in a star of little beads, whiskers, beady eyes, buck teeth, big
-- spade hands turned out with long claws (glowing on a hot one), small pink hind feet, a short pink tail
PLANS.mole = function(b, a)
	local t = Kit.new("mole", 1.8, 1.1, "quad")
	local hot = b == "black" or b == "basalt"
	J("body", nil, V(0, 0.75, 0), "body")
	local BP = { V(0, 0.64, -0.52), V(0, 0.72, -0.14), V(0, 0.76, 0.2) }
	local BR = { 0.46, 0.56, 0.5 }
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
	-- the head, its cowlick, the snout and the star nose
	J("head", "body", V(0, 0.92, 0.5), "head")
	local HC = V(0, 0.96, 0.66)
	local HR = 0.45
	Kit.ball("Head", HC, 2 * HR, b)
	Kit.tuft("Cowlick", HC + V(0.02, HR - 0.03, -0.04), 0.1, b, 4, true)
	Kit.tube("Snout", { HC + V(0, -0.1, 0.32), HC + V(0, -0.13, 0.6) }, { 0.16, 0.12 }, "pink")
	local tip = HC + V(0, -0.13, 0.7)
	if full() then
		for i = 0, 10 do
			local ang = i / 11 * 2 * math.pi
			Kit.ball("Star", tip + V(math.cos(ang) * 0.12, math.sin(ang) * 0.12, -0.02), 0.08, "pink")
		end
		Kit.ball("NoseTip", tip + V(0, 0, 0.02), 0.13, "coral")
	else
		Kit.ball("NoseTip", tip, 0.2, "pink")
	end
	Kit.whiskers(HC + V(0, -0.12, 0.52), 0.26, "cream")
	eyes(HC, HR, FWD, R(34), R(20), 0.22, irisOf(a, "gold"))
	Kit.blush(HC, HR + 0.02, FWD, R(54), R(2), 0.15)
	local mz = HC + V(0, -0.27, 0.52)
	Kit.mouth(mz, V(0, -0.5, 1), 0.14)
	Kit.P("Tooth", "Block", V(0.06, 0.09, 0.05), mz + V(-0.035, -0.06, 0.02), "white")
	Kit.P("Tooth", "Block", V(0.06, 0.09, 0.05), mz + V(0.035, -0.06, 0.02), "white")
	J("jaw", "head", V(0, 0.76, 1.0), "jaw")
	Kit.ball("Chin", HC + V(0, -0.3, 0.4), 0.2, a)
	-- the spade hands: round pink palms turned out, finger beads, long claws
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.52, 0.7, 0.42), "arm", side)
		Kit.tube("Arm" .. s, { V(side * 0.46, 0.72, 0.36), V(side * 0.7, 0.5, 0.54) }, { 0.19, 0.16 }, b)
		local palm = V(side * 0.8, 0.4, 0.64)
		Kit.ball("Palm" .. s, palm, 0.38, "pink")
		local hf = V(side * 0.55, -0.15, 1).Unit
		for i, yaw in { -40, -14, 12, 38 } do
			if full() or i ~= 2 then
				local d = (CFrame.Angles(0, R(yaw), 0)):VectorToWorldSpace(hf)
				local bead = palm + d * 0.17
				Kit.ball("Finger" .. s, bead, 0.13, "pink", true)
				blade("Claw" .. s, bead + d * 0.02, bead + d * 0.28 + V(0, -0.06, 0), 0.09, 0.05, V(0, 1, 0.2), a)
			end
		end
		if hot then
			-- (the claws glow: a hot bead at each one's root)
			for _, yaw in { -27, 25 } do
				local d = (CFrame.Angles(0, R(yaw), 0)):VectorToWorldSpace(hf)
				Kit.ball("Ember" .. s, palm + d * 0.2 + V(0, 0.02, 0), 0.07, a, true, true)
			end
		end
		-- small hind feet peeking out under the body
		J("leg" .. s, "body", V(side * 0.42, 0.4, -0.5), "leg", side, if side < 0 then 0.5 else 0)
		Kit.ball("Foot" .. s, V(side * 0.36, 0.1, -0.42), 0.22, "pink")
		Kit.ball("Foot" .. s, V(side * 0.38, 0.08, -0.28), 0.17, "pink")
		Kit.toes("Toe" .. s, V(side * 0.38, 0.06, -0.22), 0.12, 0.07, 3, "pink")
	end
	J("tail", "body", V(0, 0.58, -0.92), "tail", 0, 1)
	Kit.tube("Tail", { V(0, 0.56, -0.9), V(0, 0.5, -1.12), V(0, 0.54, -1.26) }, { 0.07, 0.05, 0.04 }, "pink")
	return t
end

------------------------------------------------------------------ the yeti
-- a yeti: a big round body in rows of shaggy fur with a fringe at its hem, a big round head with a mane and a fringe
-- round a smooth face of the accent, a button nose, little tusks on a jaw, two curled ringed horns, long furry arms
-- with big round hands (fingers, a thumb, a palm pad), short legs on big feet with toe pads
PLANS.yeti = function(b, a)
	local t = Kit.new("yeti", 2.6, 1.2, "biped")
	J("body", nil, V(0, 1.0, 0), "body")
	local BC = V(0, 1.1, 0)
	local BRad = 0.7
	local TC = V(0, 0.88, 0.1)
	local TR = 0.65
	Kit.ball("Body", BC, 2 * BRad, b)
	Kit.ball("Tummy", TC, 2 * TR, b)
	-- shaggy fur: rows of tufts round the body (fewer, bigger ones on the islands' yeti), a fringe at the hem
	if full() then
		shag("Fur", BC, BRad, { { 40, 8, 0, 360 }, { 14, 10, 0, 360 } }, 0.28, b)
		locks("Fur", BC, BRad, -6, 11, 0, 360, 0.26, 0.13, b)
		locks("Fur", TC, TR, -30, 12, 15, 375, 0.24, 0.13, b)
	else
		shag("Fur", BC, BRad, { { 30, 4, 45, 405 } }, 0.38, b)
		locks("Fur", BC, BRad, -8, 5, 0, 360, 0.3, 0.18, b)
		locks("Fur", TC, TR, -32, 5, 36, 396, 0.26, 0.17, b)
	end
	-- the head: a big round skull, a mane, a fringe over the smooth face of the accent
	J("head", "body", V(0, 1.62, 0.18), "head")
	local HC = V(0, 2.1, 0.26)
	local HR = 0.525
	Kit.ball("Head", HC, 2 * HR, b)
	local FC = HC + V(0, -0.1, 0.24)
	local FR = 0.4
	Kit.ball("Face", FC, 2 * FR, a)
	if full() then
		shag("Mane", HC, HR, { { 58, 5, 0, 360 }, { 26, 6, 72, 288 }, { -6, 4, 110, 250 } }, 0.28, b)
		for i, yaw in { -42, -15, 15, 42 } do
			Kit.ball("Fringe", HC + dir(yaw, 36 - math.abs(yaw) * 0.25) * (HR - 0.03), if i == 2 or i == 3 then 0.28 else 0.24, b)
		end
	else
		shag("Mane", HC, HR, { { 40, 4, 45, 405 } }, 0.36, b)
		Kit.ball("Fringe", HC + dir(0, 36) * (HR - 0.05), 0.36, b)
	end
	eyes(FC, FR, FWD, R(30), R(14), 0.27, irisOf(a, "blue"))
	Kit.blush(FC, FR + 0.02, FWD, R(50), R(12), 0.14)
	Kit.ball("Nose", Kit.onBall(FC, FR, dir(0, -4)), 0.14, shade(a))
	local m, mn = Kit.onBall(FC, FR, dir(0, -30))
	Kit.mouth(m, mn, 0.25)
	-- the horns: curled up and out, ringed
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local hp = { HC + V(side * 0.32, 0.32, -0.06), HC + V(side * 0.56, 0.42, -0.06), HC + V(side * 0.66, 0.66, 0.02), HC + V(side * 0.57, 0.82, 0.08) }
		local hr = { 0.11, 0.085, 0.06, 0.03 }
		if full() then
			Kit.tube("Horn" .. s, hp, hr, a)
		else
			Kit.tube("Horn" .. s, { hp[1], hp[3] }, { 0.11, 0.06 }, a)
		end
		if full() then
			for _, u in { 0.3, 0.55 } do
				local c = Kit.curveAt(hp, u)
				Kit.disc("HornRing" .. s, c, Kit.curveAt(hp, u + 0.03) - Kit.curveAt(hp, u - 0.03), 2 * lerpList(hr, u) + 0.05, 0.05, shade(a), true)
			end
		end
	end
	-- the jaw: a round chin with two little tusks
	J("jaw", "head", V(0, 1.84, 0.5), "jaw")
	Kit.ball("Chin", FC + V(0, -0.3, 0.1), 0.32, a)
	for _, side in { -1, 1 } do
		local base = FC + V(side * 0.12, -0.22, 0.29)
		blade("Tusk", base, base + V(side * 0.02, 0.12, 0.02), 0.075, 0.05, V(0, 0, 1), "white", true)
	end
	-- long furry arms and big round hands
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.82, 1.48, 0.05), "arm", side)
		local ap = { V(side * 0.78, 1.48, 0.04), V(side * 1.0, 1.1, 0.1), V(side * 1.08, 0.82, 0.16) }
		Kit.tube("Arm" .. s, if full() then ap else { ap[1], ap[3] }, { 0.25, 0.22, 0.2 }, b)
		Kit.ball("Shoulder" .. s, V(side * 0.8, 1.54, 0.02), 0.44, b, true)
		for i, u in { 0.3, 0.7 } do
			local at = Kit.curveAt(ap, u) + V(side * 0.15, 0.02, -0.06 + i * 0.03)
			Kit.ball("ArmFur" .. s, at, 0.25, b, true)
		end
		local hand = V(side * 1.1, 0.64, 0.22)
		Kit.ball("Hand" .. s, hand, 0.46, b)
		for i, yaw in { -24, 0, 24 } do
			local d = dir(yaw - side * 10, -40)
			Kit.ball("Finger" .. s, hand + d * 0.2, 0.18, b, i ~= 2)
		end
		Kit.ball("Thumb" .. s, hand + V(-side * 0.18, 0.06, 0.12), 0.17, b, true)
		patch("Palm" .. s, hand, 0.23, V(-side * 0.6, -0.1, 1), 0.22, a)
		-- short legs on big feet
		J("leg" .. s, "body", V(side * 0.4, 0.48, 0), "leg", side, if side < 0 then 0 else 0.5)
		Kit.tube("Leg" .. s, { V(side * 0.38, 0.56, 0), V(side * 0.42, 0.22, 0.06) }, { 0.25, 0.23 }, b)
		Kit.ball("Heel" .. s, V(side * 0.42, 0.17, 0.04), 0.34, b)
		Kit.ball("Foot" .. s, V(side * 0.44, 0.15, 0.26), 0.3, b)
		Kit.toes("Toe" .. s, V(side * 0.44, 0.1, 0.38), 0.24, 0.13, 3, a)
	end
	return t
end

------------------------------------------------------------------ the seal
-- a seal: a smooth body tapering from a raised chest to its hips, a pale chest, spots, a round head with big dark eyes,
-- brow spots, round whisker pads with whisker dots, a black nose, whiskers and a chin on a jaw, front flippers with
-- little claws, two hind flippers fanned out behind
PLANS.seal = function(b, a)
	local t = Kit.new("seal", 1.6, 1.2, "slither")
	local dots = if b == "window" or b == "white" or b == "snow" or b == "ice" then "blue" else shade(b)
	J("body", nil, V(0, 0.5, 0), "body")
	local BP = { V(0, 0.7, 0.36), V(0, 0.52, -0.2), V(0, 0.36, -0.72), V(0, 0.26, -1.02) }
	local BR = { 0.46, 0.48, 0.34, 0.2 }
	sausage("Body", BP, BR, b)
	Kit.ball("Chest", V(0, 0.56, 0.56), 0.62, a)
	-- spots on the back and upper sides: low domes, so they stay round where they reach the outline
	for _, s in { { 0.24, -18, 0.2 }, { 0.3, 30, 0.15 }, { 0.44, -40, 0.15 }, { 0.48, 8, 0.2 }, { 0.6, 36, 0.14 }, { 0.66, -20, 0.16 }, { 0.8, 6, 0.13 } } do
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
	end
	Kit.blush(HC, HR + 0.02, FWD, R(52), R(12), 0.15)
	-- the muzzle: two round whisker pads with dots, the nose over them
	for _, side in { -1, 1 } do
		local pc = HC + V(side * 0.09, -0.12, 0.38)
		Kit.ball("Pad", pc, 0.26, a)
		if full() then
			for _, d in { dir(side * 30, 10), dir(side * 48, -4), dir(side * 26, -16) } do
				patch("Dot", pc, 0.13, d, 0.05, dots, true)
			end
		end
	end
	Kit.ball("Nose", HC + V(0, -0.03, 0.45), 0.15, "black")
	Kit.mouth(HC + V(0, -0.24, 0.44), V(0, -0.4, 1), 0.14)
	Kit.whiskers(HC + V(0, -0.14, 0.42), 0.24, "white")
	J("jaw", "head", V(0, 0.94, 0.88), "jaw")
	Kit.ball("Chin", HC + V(0, -0.27, 0.35), 0.18, a)
	-- the front flippers: a short arm, then a flat paddle with three claws
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("fin" .. s, "body", V(side * 0.42, 0.45, 0.42), "fin", side)
		Kit.tube("Flipper" .. s, { V(side * 0.36, 0.5, 0.4), V(side * 0.58, 0.2, 0.5) }, { 0.15, 0.1 }, b)
		local fp = { V(side * 0.58, 0.16, 0.5), V(side * 0.72, 0.1, 0.58), V(side * 0.84, 0.07, 0.66) }
		local fn = V(side * 0.3, 1, 0).Unit
		Kit.strip("FlipperPad" .. s, fp, { 0.22, 0.24, 0.15 }, fn, b)
		if full() then
			for k = -1, 1 do
				local c = fp[3] + V(-side * 0.02, 0.05, -0.04) + V(side * 0.02, 0, 0.06) * k + V(-0.05, 0, 0.03) * k * side
				Kit.ball("Claw" .. s, c, 0.05, dots, true)
			end
		end
	end
	-- the hind flippers fanned out behind: a fleshy root, a flat fan, a ray down each
	J("tail", "body", V(0, 0.32, -0.95), "tail", 0, 1)
	Kit.tube("Tail", { V(0, 0.27, -0.98), V(0, 0.2, -1.2) }, { 0.17, 0.12 }, b)
	for _, side in { -1, 1 } do
		local fp = { V(side * 0.05, 0.17, -1.2), V(side * 0.2, 0.13, -1.42), V(side * 0.34, 0.14, -1.58) }
		Kit.tube("FlukeRoot", { fp[1], fp[2] }, { 0.09, 0.06 }, b)
		Kit.strip("Fluke", fp, { 0.18, 0.3, 0.34 }, V(-side * 0.15, 1, 0), b)
		if full() then
			Kit.rod("FlukeRay", fp[2] + V(0, 0.05, 0), fp[3] + V(side * 0.02, 0.04, 0.06), 0.05, shade(b), true)
			Kit.rod("FlukeRay", fp[2] + V(0, 0.05, 0), fp[3] + V(side * 0.04, 0.04, -0.06), 0.05, shade(b), true)
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
		elseif icy then
			Kit.ball("Snow" .. s, sh + V(0, 0.14, 0), 0.5, snow)
			Kit.tube("Crystal" .. s, { sh + V(side * 0.12, 0.2, -0.08), sh + V(side * 0.3, 0.5, -0.14) }, { 0.12, 0.03 }, snow, 2)
			Kit.tube("Crystal" .. s, { sh + V(side * 0.02, 0.24, -0.14), sh + V(side * 0.04, 0.46, -0.3) }, { 0.09, 0.025 }, snow, 2, true)
			Kit.tube("Icicle" .. s, { fa + V(side * 0.14, -0.06, 0.12), fa + V(side * 0.15, -0.28, 0.13) }, { 0.045, 0.025 }, snow, nil, true)
		else
			Kit.ball("ShoulderMoss" .. s, sh + V(0, 0.16, 0), 0.46, green, side > 0)
			Kit.tuft("ShoulderMoss" .. s, sh + V(side * 0.06, 0.3, 0.06), 0.1, shade(green), 3, true)
			-- a guard's cuff on the forearm
			Kit.disc("Cuff" .. s, fa + V(0, -0.02, 0), V(side * 0.2, 1, 0), 0.56, 0.1, a)
		end
		-- stubby legs on round feet with toe stones
		J("leg" .. s, "body", V(side * 0.36, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		Kit.ball("Leg" .. s, V(side * 0.36, 0.42, 0.02), 0.48, b)
		Kit.ball("Heel" .. s, V(side * 0.38, 0.17, 0.04), 0.34, b)
		Kit.ball("Foot" .. s, V(side * 0.38, 0.15, 0.24), 0.3, b)
		Kit.toes("Toe" .. s, V(side * 0.38, 0.1, 0.36), 0.24, 0.13, 3, b)
	end
	return t
end

-- a tree golem: a stout trunk with raised bark ridges, a knot hole with a toadstool by it and moss, a round head of wood
-- under a bushy crown of leaves, the face carved in it, branch arms with leaves and twig fingers, root feet
local function woodGolem(b: string, a: string): Kit.Thing
	local t = Kit.new("golem", 2.6, 1.3, "biped")
	local bark = shade(b)
	local leaf = if a == "leaf" or a == "leaf_dark" or a == "moss" or a == "green" then a else "leaf"
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
	local mp, mpn = trunkAt(0.28, -34, 0)
	Kit.rod("ToadstoolStem", mp - mpn * 0.02, mp + V(0, 0.1, 0) + mpn * 0.06, 0.07, "cream", true)
	Kit.disc("Toadstool", mp + V(0, 0.12, 0) + mpn * 0.07, UP, 0.2, 0.07, "berry_red", true)
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
	for i, l in { { -0.42, 0.06, 0.2 }, { 0.44, 0.1, 0.12 }, { -0.1, 0.36, 0.1 }, { 0.2, 0.3, -0.3 } } do
		local base = CT + V(l[1] * 0.6, l[2] * 0.6, l[3] * 0.6)
		blade("Leaf", base, CT + V(l[1], l[2], l[3]) * 1.25, 0.16, 0.05, V(0, 1, 0.2), leaf, i > 2 or not full())
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
		local wrist = V(side * 1.0, 0.62, 0.15)
		Kit.ball("Fist" .. s, wrist, 0.36, b)
		for _, d in { dir(-side * 24, -56), dir(side * 4, -72), dir(side * 32, -56) } do
			if full() then
				Kit.tube("Twig" .. s, { wrist + d * 0.12, wrist + d * 0.3, wrist + d * 0.4 + V(0, 0.02, 0.06) }, { 0.065, 0.05, 0.035 }, b)
			else
				Kit.ball("Twig" .. s, wrist + d * 0.22, 0.13, b)
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
	end
	return t
end

PLANS.golem = function(b, a)
	if b == "wood" or b == "wood_dark" then
		return woodGolem(b, a)
	end
	return stoneGolem(b, a)
end

return PLANS
