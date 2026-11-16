--!strict
-- The driftlings' anatomy (GAME_DESIGN 6; docs/ARCHITECTURE.md 6): the body parts every body plan is sculpted from,
-- on the kit's smooth solids (Models/DriftKit: `ell`, `egg`, `limb`, `limbs`). Roblox module (client).
--
-- The request (2026-11-15): "can you redo all the creatures and eggs and add alot more extra ones with more variation
-- to them? currently, all of them are modelled using blobs, which is unnatural. reference other models online to see
-- how you should model them". The way modellers block out a creature (GAME_DESIGN 6 has the references): the skeleton
-- first, then the masses on it. An egg-shaped body (the chest deeper than the hips), a head that is its own form with a
-- muzzle, a nose and a jaw; legs that come out of a shoulder or a haunch, taper, and bend where the animal's do (a
-- dog's foreleg straight down to a wrist, its hind leg forward to the knee and back to a hock, a bird's thin leg with
-- a heel and three toes forward and one back); paws, hooves, claws and webbed feet; tails that taper to the tip. A
-- creature with a big head and short limbs reads as young and friendly (the head a third to a half of its height).
-- Each piece is one smooth solid or a short chain of them, so the outline is clean and the joins read as joins.
--
-- Space: a plan faces +Z with its feet on the ground at y 0; +X is its right ("R", side 1), -X its left ("L", -1).
-- Every builder puts its parts on the joint it makes (or the current one) and returns what the next piece needs.
local Kit = require(script.Parent.DriftKit)

local A = {}

local V = Vector3.new
local R = math.rad
local UP = V(0, 1, 0)
local FWD = V(0, 0, 1)
A.UP, A.FWD = UP, FWD

local function full(): boolean
	return Kit.full()
end
A.full = full

------------------------------------------------------------------ directions and turns
-- A direction from forward: turned `yaw` degrees toward +X and `pitch` degrees up.
function A.dir(yaw: number, pitch: number): Vector3
	return (CFrame.Angles(0, R(yaw), 0) * CFrame.Angles(R(-pitch), 0, 0)):VectorToWorldSpace(FWD)
end

-- The turn whose local +Y points along `d` (an egg or a limb-like ellipsoid lying that way); `up` picks its roll (its
-- local +Z goes as near `up` as it can).
function A.lie(d: Vector3, up: Vector3?): CFrame
	local y = d.Unit
	local u = up or (if math.abs(y.Y) < 0.95 then UP else FWD)
	local z = u - y * u:Dot(y)
	z = if z.Magnitude > 1e-5 then z.Unit else (if math.abs(y.X) < 0.9 then V(1, 0, 0) else FWD)
	local x = y:Cross(z)
	return CFrame.fromMatrix(Vector3.zero, x, y, z)
end

-- Mirror a point to the other side (x flipped).
function A.mx(p: Vector3, side: number): Vector3
	return V(p.X * side, p.Y, p.Z)
end

local function lerp(a: Vector3, b: Vector3, u: number): Vector3
	return a + (b - a) * u
end
A.lerp = lerp

------------------------------------------------------------------ colours
-- The darker shade of a palette colour (spots, stripes, a paw's pads, the far side of a marking).
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
	berry_red = "clay",
	screen_on = "teal",
	crystal = "purple",
	slate = "night",
	night = "black",
	basalt = "black",
	chalk = "basalt", -- (the palette's chalk is a dark board green, not white)
	cherry = "berry_red",
	coral = "clay",
}
function A.shade(c: string): string
	return SHADE[c] or c
end

-- A colour that reads on a dark body (a dark creature's nose, claws and ear tips take the accent instead of black).
local DARK: { [string]: boolean } = { black = true, basalt = true, night = true, slate = true, wood_dark = true, rock_dark = true, hair_brown = true }
function A.isDark(c: string): boolean
	return DARK[c] == true
end
-- A pale colour (a white creature's markings and pads take a darker tone).
local PALE: { [string]: boolean } = { white = true, cream = true, snow = true, window = true, ice = true }
function A.isPale(c: string): boolean
	return PALE[c] == true
end
-- The ink of the face and the claws: black, or the accent on a dark body.
function A.ink(b: string, a: string): string
	if A.isDark(b) then
		return if A.isDark(a) then "white" else a
	end
	return "black"
end
-- A paler underside for a body colour (a belly, a muzzle, a chest): cream, or white on a cream body.
function A.under(b: string): string
	if b == "cream" or b == "sand" or b == "white" or b == "snow" then
		return "white"
	elseif A.isDark(b) then
		return "slate"
	end
	return "cream"
end
-- An iris that shows on a dark eye: the accent unless it is too dark or too pale.
function A.iris(a: string, fallback: string): string
	if A.isDark(a) or a == "white" or a == "cream" or a == "snow" then
		return fallback
	end
	return a
end

------------------------------------------------------------------ masses
-- A body: an egg lying along `d` (unit, from the hips toward the chest), centred at `c`, `len` long, `wide` across and
-- `tall` high; `split` above 0.5 makes the hips end longer and narrower than the chest (a dog, a fox, a cat), below
-- 0.5 the other way (a pear-shaped mole, a seal's hips), 0.5 even. Returns the part and its frame for patches.
export type Mass = { c: Vector3, size: Vector3, rot: CFrame, split: number }
function A.body(name: string, c: Vector3, d: Vector3, len: number, wide: number, tall: number, split: number, color: string): (BasePart?, Mass)
	-- (the egg's local +Y runs to its narrow end: the hips, back along -d; its local +Z up)
	local rot = A.lie(-d, UP)
	local size = V(wide, len, tall)
	local p = Kit.egg(name, c, size, split, color, rot)
	return p, { c = c, size = size, rot = rot, split = split }
end

-- An ellipsoid mass (a head, a cheek, a haunch, a muzzle's end), returned as a Mass too.
function A.blob(name: string, c: Vector3, size: Vector3, color: string, rot: CFrame?, detail: boolean?): (BasePart?, Mass)
	local p = Kit.ell(name, c, size, color, rot, detail)
	return p, { c = c, size = size, rot = rot or CFrame.identity, split = 0.5 }
end

-- How far the surface of a mass lies from its centre in the world direction `d`.
local function reach(m: Mass, d: Vector3): number
	local dl = m.rot:VectorToObjectSpace(d.Unit)
	local hx, hz = m.size.X / 2, m.size.Z / 2
	local hy = if dl.Y >= 0 then m.size.Y * m.split else m.size.Y * (1 - m.split)
	-- (an egg's equator sits off its box's middle: the reach is from the equator, close enough for patches)
	return 1 / math.sqrt((dl.X / hx) ^ 2 + (dl.Y / hy) ^ 2 + (dl.Z / hz) ^ 2)
end
A.reach = reach

-- The point on a mass's surface in the direction `d` from its centre.
function A.on(m: Mass, d: Vector3): Vector3
	return m.c + d.Unit * reach(m, d)
end

-- A patch of another colour on a mass (a belly, a chest blaze, a face mask, a saddle): a smaller copy of it (`shrink`
-- of its size) pushed out toward `d` until it stands `out` studs proud there, so only a cap of it shows, curved with the
-- body. The bigger `shrink`, the bigger the patch.
function A.patch(name: string, m: Mass, d: Vector3, shrink: number | Vector3, out: number, color: string, detail: boolean?): BasePart?
	local k = if typeof(shrink) == "Vector3" then shrink else V(shrink, shrink, shrink)
	local size = V(m.size.X * k.X, m.size.Y * k.Y, m.size.Z * k.Z)
	local inner: Mass = { c = m.c, size = size, rot = m.rot, split = m.split }
	local du = d.Unit
	local off = reach(m, du) - reach(inner, du) + out
	local c = m.c + du * off
	if m.split ~= 0.5 then
		return Kit.egg(name, c, size, m.split, color, m.rot, detail)
	end
	return Kit.ell(name, c, size, color, m.rot, detail)
end

------------------------------------------------------------------ feet
-- A paw: a rounded pad of a foot at `at` (its sole on the ground there), `w` wide, toes forward along `fwd`, with toe
-- bumps up close and a pad colour underneath that shows at the front.
function A.paw(name: string, at: Vector3, w: number, c: string, fwd: Vector3?, padC: string?, toes: number?)
	local f = (fwd or FWD).Unit
	local rot = A.lie(f, UP)
	local h = w * 0.62
	Kit.ell(name, at + UP * h * 0.5 + f * w * 0.08, V(w, w * 1.25, h), c, rot)
	if full() then
		local right = UP:Cross(f).Unit
		local n = toes or 3
		for i = 0, n - 1 do
			local s = if n == 1 then 0 else -1 + 2 * i / (n - 1)
			Kit.ell(name .. "Toe", at + UP * h * 0.38 + f * (w * 0.55 - math.abs(s) * w * 0.12) + right * s * w * 0.3, V(w * 0.34, w * 0.34, h * 0.62), c, rot)
		end
		if padC then
			Kit.ell(name .. "Pad", at + UP * h * 0.2 + f * w * 0.18, V(w * 0.62, w * 0.7, h * 0.3), padC, rot)
		end
	end
end

-- A hoof: a short rounded block of horn at `at`, `w` wide, a little cleft at the front up close.
function A.hoof(name: string, at: Vector3, w: number, c: string, fwd: Vector3?)
	local f = (fwd or FWD).Unit
	local rot = A.lie(UP, f)
	local h = w * 0.7
	Kit.limb(name, at + UP * h * 0.3, at + UP * h * 0.75, w * 0.5, w * 0.42, c)
	if full() then
		-- the cleft: two toes' fronts either side of a dark line
		local right = UP:Cross(f).Unit
		for _, s in { -1, 1 } do
			Kit.ell(name .. "Toe", at + UP * h * 0.32 + f * w * 0.26 + right * s * w * 0.17, V(w * 0.42, h * 0.62, w * 0.42), c, rot)
		end
	end
end

-- Claws: `n` short curved points from the front of a foot at `at`, along `fwd`, `len` long.
function A.claws(name: string, at: Vector3, w: number, len: number, c: string, fwd: Vector3?, n: number?)
	local f = (fwd or FWD).Unit
	local right = UP:Cross(f).Unit
	local k = n or 3
	for i = 0, k - 1 do
		local s = if k == 1 then 0 else -1 + 2 * i / (k - 1)
		local base = at + right * s * w * 0.32
		Kit.limb(name, base, base + f * len - UP * len * 0.35 + right * s * len * 0.2, len * 0.22, len * 0.06, c, nil, nil, true)
	end
end

-- A bird's foot: three toes forward and one back (the hallux), thin, ending in claws, at `at` on the ground.
function A.birdFoot(name: string, at: Vector3, len: number, c: string, clawC: string?, fwd: Vector3?, webC: string?)
	local f = (fwd or FWD).Unit
	local right = UP:Cross(f).Unit
	local r = math.max(0.035, len * 0.11)
	local base = at + UP * r
	for _, a in { -32, 0, 32 } do
		local d = (CFrame.fromAxisAngle(UP, R(-a))):VectorToWorldSpace(f)
		local tip = base + d * len
		Kit.limb(name .. "Toe", base, tip, r, r * 0.75, c)
		if clawC and full() then
			Kit.limb(name .. "Claw", tip, tip + d * len * 0.28 - UP * r * 0.8, r * 0.7, r * 0.25, clawC)
		end
	end
	Kit.limb(name .. "Toe", base, base - f * len * 0.45, r, r * 0.7, c)
	if webC then
		-- (a duck's: the web between the front toes, a flat fan)
		Kit.limb(name .. "Web", base + f * len * 0.15, base + f * len * 0.8, len * 0.22, len * 0.4, webC, 0.18, UP)
	end
	local _ = right
end

------------------------------------------------------------------ legs
-- One leg on its own joint ("leg" .. n, kind "leg", its side and its phase in the stride), hanging from `hip` (a point
-- inside the body's side) to the ground. opts:
--   kind  "fore": a shoulder, down to an elbow just behind, straight down to the wrist, a foot (a dog's foreleg)
--         "hind": a haunch, the thigh forward to the knee, the shin back to the hock, down to the foot (digitigrade)
--         "post": a pillar, a little wider at the foot (a bear's, an elephant's, a turtle's)
--         "bird": a feathered thigh tucked under the body, a thin bare shank from the heel, a bird's foot
--         "frog": a big folded hind leg (thigh, shin folded under it, a long foot forward)
--   r     the leg's radius at the top (default 0.14), foot "paw" | "hoof" | "claw" | "pad" | "bird" | "web" | "none",
--   fw    the foot's width, c the leg's colour, fc the foot's (default c), sock a colour for the lower leg,
--   pad   the paw's pad colour, mass true (default) to round the top into a shoulder or haunch (`massC` its colour),
--   out   how far the foot stands out from under the hip (studs, + away from the middle), fwd the way the foot points,
--   toes  how many toes, claw a claw colour (a "claw" foot's, or a "bird" foot's)
export type LegOpts = {
	kind: string?,
	r: number?,
	foot: string?,
	fw: number?,
	c: string,
	fc: string?,
	sock: string?,
	pad: string?,
	mass: boolean?,
	massC: string?,
	massSize: Vector3?,
	out: number?,
	fwd: Vector3?,
	toes: number?,
	claw: string?,
	web: string?,
	parent: string?,
}
function A.leg(n: string, side: number, phase: number, hip: Vector3, o: LegOpts)
	Kit.J("leg" .. n, o.parent or "body", hip, "leg", side, phase)
	local kind = o.kind or "fore"
	local r = o.r or 0.14
	local c = o.c
	local fc = o.fc or c
	local low = o.sock or c
	local out = (o.out or 0.02) * side
	local f = (o.fwd or FWD).Unit
	local H = hip.Y
	local fw = o.fw or r * 2.1
	local foot = o.foot or "paw"
	local footH = if foot == "hoof" then fw * 0.55 elseif foot == "bird" or foot == "web" then 0.03 else fw * 0.42
	local ground = V(hip.X + out, 0, hip.Z)
	if kind == "fore" then
		if o.mass ~= false then
			local ms = o.massSize or V(r * 2.3, r * 3.6, r * 2.8)
			Kit.ell(n .. "Shoulder", hip + UP * r * 0.4, ms, o.massC or c)
		end
		local elbow = V(hip.X + out * 0.4, H * 0.5, hip.Z - r * 0.35)
		local wrist = V(ground.X, footH + r * 0.15, ground.Z + r * 0.1)
		Kit.limb("Leg" .. n, hip, elbow, r, r * 0.8, c)
		if full() and low ~= c then
			local mid = lerp(elbow, wrist, 0.4)
			Kit.limb("Leg" .. n, elbow, mid, r * 0.8, r * 0.74, c)
			Kit.limb("Sock" .. n, mid, wrist, r * 0.76, r * 0.72, low)
		else
			Kit.limb("Leg" .. n, elbow, wrist, r * 0.8, r * 0.7, low)
		end
		ground = V(wrist.X, 0, wrist.Z)
	elseif kind == "hind" then
		if o.mass ~= false then
			local ms = o.massSize or V(r * 2.4, r * 3.8, r * 3.6)
			Kit.ell(n .. "Haunch", hip + UP * r * 0.2 - FWD * r * 0.1, ms, o.massC or c, A.lie(V(0, 1, -0.35)))
		end
		local knee = V(hip.X + out * 0.4, H * 0.55, hip.Z + r * 0.9)
		local hock = V(hip.X + out * 0.8, H * 0.28, hip.Z - r * 0.7)
		local ankle = V(ground.X, footH + r * 0.1, ground.Z - r * 0.2)
		Kit.limb("Leg" .. n, hip, knee, r * 1.05, r * 0.78, c)
		Kit.limb("Leg" .. n, knee, hock, r * 0.78, r * 0.6, c)
		Kit.limb(if low ~= c then "Sock" .. n else "Leg" .. n, hock, ankle, r * 0.6, r * 0.62, low)
		ground = V(ankle.X, 0, ankle.Z + r * 0.1)
	elseif kind == "post" then
		if o.mass ~= false then
			Kit.ell(n .. "Top", hip + UP * r * 0.3, o.massSize or V(r * 2.4, r * 2.6, r * 2.6), o.massC or c)
		end
		local foot0 = V(ground.X, footH + r * 0.3, ground.Z)
		Kit.limb("Leg" .. n, hip, foot0, r, r * 1.08, low)
		ground = V(foot0.X, 0, foot0.Z)
	elseif kind == "bird" then
		-- the drumstick, feathered, tucked under the body; the bare shank from the heel to the foot
		local heel = V(hip.X + out * 0.5, H * 0.42, hip.Z - r * 0.4)
		if o.mass ~= false then
			Kit.limb("Thigh" .. n, hip, lerp(hip, heel, 0.7), r * 1.3, r * 0.8, o.massC or c)
		end
		local sr = math.max(0.04, r * 0.36)
		Kit.limb("Shank" .. n, heel, V(ground.X, 0.06, ground.Z + 0.02), sr, sr * 0.9, fc)
		ground = V(ground.X, 0, ground.Z + 0.02)
	elseif kind == "frog" then
		-- folded: the thigh out and forward, the shin folded back under it, the long foot forward on the ground
		local knee = V(hip.X + side * r * 1.6, H * 0.7, hip.Z + r * 1.2)
		local ankle = V(hip.X + side * r * 1.4, r * 0.55, hip.Z - r * 1.0)
		Kit.limb("Thigh" .. n, hip, knee, r * 1.25, r * 0.9, c)
		Kit.limb("Leg" .. n, knee, ankle, r * 0.85, r * 0.55, c)
		ground = V(ankle.X, 0, ankle.Z + r * 0.4)
		f = (f + V(side * 0.35, 0, 0)).Unit
	end
	if foot == "paw" then
		A.paw("Paw" .. n, ground, fw, fc, f, o.pad, o.toes)
	elseif foot == "hoof" then
		A.hoof("Hoof" .. n, ground, fw, fc, f)
	elseif foot == "claw" then
		A.paw("Paw" .. n, ground, fw, fc, f, nil, o.toes)
		if full() then
			A.claws("Claw" .. n, ground + UP * fw * 0.2 + f * fw * 0.62, fw, fw * 0.4, o.claw or "cream", f, o.toes)
		end
	elseif foot == "pad" then
		-- a broad round sole (a bear's, an elephant's, a turtle's), toenails at the front up close
		Kit.ell("Foot" .. n, ground + UP * fw * 0.22 + f * fw * 0.06, V(fw * 1.05, fw * 0.44, fw * 1.15), fc)
		if full() and o.claw then
			local right = UP:Cross(f).Unit
			for _, s in { -1, 0, 1 } do
				Kit.ell("Nail" .. n, ground + UP * fw * 0.16 + f * fw * 0.5 + right * s * fw * 0.28, V(fw * 0.22, fw * 0.18, fw * 0.2), o.claw)
			end
		end
	elseif foot == "bird" then
		A.birdFoot("Foot" .. n, ground, fw, fc, o.claw, f)
	elseif foot == "web" then
		A.birdFoot("Foot" .. n, ground, fw, fc, nil, f, o.web or fc)
	elseif foot == "frog" then
		-- a long foot with spread toes ending in round pads
		local right = UP:Cross(f).Unit
		local base = ground + UP * 0.05
		for _, a in { -28, 0, 28 } do
			local d = (CFrame.fromAxisAngle(UP, R(-a))):VectorToWorldSpace(f)
			local tip = base + d * fw
			Kit.limb("Toe" .. n, base, tip, fw * 0.14, fw * 0.1, fc)
			Kit.ell("ToePad" .. n, tip + UP * 0.02, V(fw * 0.26, fw * 0.16, fw * 0.26), fc)
		end
		local _ = right
	end
end

------------------------------------------------------------------ the face's details
-- The request (2026-11-16): "Detail the faces of the creatures even more. Add more details based on the shape and
-- details of the creature's bodies. No need to detail that much outside of the egg hatching screen." So on the full
-- thing (the hatch scene, the portraits, close looks) a face gets the small marks an artist adds once the eyes and the
-- mouth are in, led by what its body is covered in (Kit.look's texture) and by its muzzle:
--   brows   a soft arc a shade off the head's colour over each eye, shaped by the eye's style (high over a round or
--           wide eye, level over a sleepy or a lit one, clear of a pair of spectacles; none where the style brings its
--           own, a fierce eye, or has no room, a visor); a bird's is a pale stripe sweeping back, a reptile's a ridge of
--           scale, a stone or bark
--           creature's a heavy ridge, an icy one's frost, a moth's or a sprite's a few soft tufts, an insect's the edge
--           of the plate over its face
--   muzzle  the line from a mammal's nose down to its mouth, whisker dots on the pads of a cat's muzzle and along a
--           mole's snout, a beak's nostrils, the line between its halves and its paler tip, scales along a lizard's lip
--   cheeks  tufts of fur or fluff, the edges of a bird's feathers or a fish's scales, a moth's fuzz, freckles on bare
--           skin, glowing freckles on an ember creature, frost on an icy one, the grain of bark, pits in an insect's
--           plates, a crack down a stone cheek
--   crown   a little crest of feathers, a plate of scale, a gem, a leaf, a crack and a chip, a star of frost, a shine
--           on a jelly, a glint on an insect's head and its mandibles
--   marks   a species' own (FaceMore.marks: a blaze, a star, glowing spots or freckles, lines drawn out from the eyes)
-- Each mark is thinner than the blend's 0.07 studs across (Models/DriftModels: drawn crisp over the body, never
-- merged into it) and stands about 0.04 studs proud of the head (the picture draws a part over another only where it
-- is more than 0.03 nearer, Render/Raster), so it shows whatever order the parts are drawn in; tufts and crests are
-- thicker and run on from the head like clay. The islands' lighter level gets none of it.
local LIFT = 0.04

-- What a plan can ask of the face's details (A.head's `face`, or A.face's own): brows a kind ("soft" "high" "level"
-- "keen" "pale" "scales" "ridge" "frost" "fuzz" "none") or false, browC their colour, cheeks / crown / muzzle false to
-- leave those out, mandibles false when the plan has its own, tuft the colour of cheek tufts, tex the texture to dress
-- the face for (when its face is not its body's: a sheep's bare face, a mushroom's stem), marks a species' own:
-- { blaze = colour, star = colour, spots = colour, freckles = colour, kohl = colour, glow = true (lit), crack = colour,
-- gem = colour, leaf = colour }.
export type FaceMore = {
	brows: (string | boolean)?,
	browC: string?,
	cheeks: boolean?,
	crown: boolean?,
	muzzle: boolean?,
	mandibles: boolean?,
	tuft: string?,
	tex: string?,
	marks: { [string]: any }?,
}

-- A plan's wishes for its face's details with its species' own (a form's `faceDetail`) laid over them.
function A.more(plan: FaceMore?, species: any): FaceMore?
	if species == nil then
		return plan
	end
	local m: any = table.clone(plan or {})
	for k, v in species do
		m[k] = v
	end
	return m
end

-- The face's details on the head's surface (the ellipsoid at `c`, half sizes `half`, turned by `rot`; when not given,
-- the one the eyes went on), after Kit.eyes and Kit.mouth (their record: Kit.faceRec). `color` is the face's colour
-- round the eyes; lip a line of points from the nose down to the mouth (already set out from the muzzle); pads the
-- whisker pads to dot; snout a long muzzle (its axis from a to b, radii ra to rb, squashed by flat in its height) for
-- whisker dots or a grin; beak a bird's beak (root, tip, its width at the root, its colour, duck for a flat bill).
export type FaceOpts = {
	color: string,
	c: Vector3?,
	half: Vector3?,
	rot: CFrame?,
	accent: string?,
	under: string?,
	ink: string?,
	muzzle: string?,
	lip: { Vector3 }?,
	pads: { { c: Vector3, half: Vector3 } }?,
	padC: string?,
	tuft: string?,
	snout: { a: Vector3, b: Vector3, ra: number, rb: number, flat: number }?,
	beak: { root: Vector3, tip: Vector3, w: number, color: string, duck: boolean? }?,
	eyeSurf: boolean?,
	more: FaceMore?,
}

-- A lighter tone of a dark colour (a dark line would not show on a dark head).
local LIGHTER: { [string]: string } = {
	black = "slate",
	basalt = "slate",
	night = "slate",
	slate = "steel_dark",
	wood_dark = "wood",
	rock_dark = "rock",
	hair_brown = "wood",
	leaf_dark = "leaf",
	chalk = "leaf_dark",
}
-- The tone a brow or a mark takes on a face of colour c: a shade darker, or lighter on a dark face; a little stronger
-- than A.shade on the pale ones, where the shade is nearly the colour itself.
local MARK: { [string]: string } = { window = "ice", ice = "blue", snow = "steel", white = "steel", cream = "sand_dark", sand = "sand_dark", yellow = "gold", screen_on = "teal", shallow = "teal", cherry = "pink", crystal = "purple", pink = "coral" }
function A.markC(c: string): string
	if A.isDark(c) then
		return LIGHTER[c] or "slate"
	end
	return MARK[c] or A.shade(c)
end

-- The brow's three points by shape: inner, middle, outer, each up (a share of the eye's height above its middle) and
-- out (a share of its width, + away from the middle of the face).
local BROW_SHAPE: { [string]: { number } } = {
	soft = { 0.58, -0.3, 0.68, 0.04, 0.58, 0.38 },
	high = { 0.66, -0.28, 0.8, 0.04, 0.66, 0.38 },
	level = { 0.6, -0.3, 0.62, 0.02, 0.58, 0.34 },
	keen = { 0.54, -0.32, 0.62, 0.0, 0.62, 0.38 },
	pale = { 0.62, -0.24, 0.68, 0.3, 0.58, 0.84 },
	specs = { 0.84, -0.28, 0.96, 0.04, 0.84, 0.38 },
}
-- The brow each eye style takes (none: the style brings its own, a fierce one's, or has no room for one, a visor).
local STYLE_BROW: { [string]: string } = {
	sparkle = "soft",
	lashes = "soft",
	star = "soft",
	heart = "high",
	button = "soft",
	bead = "soft",
	dot = "soft",
	round = "high",
	wide = "high",
	happy = "high",
	sleepy = "level",
	slit = "keen",
	bar = "keen",
	ringed = "keen",
	compound = "level",
	glow = "level",
	gem = "soft",
	specs = "specs",
}
-- The brow each texture takes in place of a plain arc.
local TEX_BROW: { [string]: string } = {
	feather = "pale",
	scale = "scales",
	shell = "ridge",
	stone = "ridge",
	brick = "ridge",
	bark = "ridge",
	ice = "frost",
	velvet = "fuzz",
	chitin = "none",
}

function A.face(o: FaceOpts)
	local rec = Kit.faceRec()
	Kit.faceClear()
	if not full() then
		return
	end
	local more: FaceMore = o.more or {}
	local eyes = rec.eyes
	local look = Kit.look()
	local tex = more.tex or look.tex or "skin"
	local col = o.color
	local acc = o.accent or look.accent or col
	local under = o.under or A.under(col)
	local ink = o.ink or A.ink(col, acc)
	local markC = more.browC or A.markC(col)
	local marks: { [string]: any } = more.marks or {}
	local back = Kit.joint()
	-- the surface: the head's own, or the one the eyes went on
	local S: { c: Vector3, half: Vector3, rot: CFrame }
	if o.c and o.half then
		S = { c = o.c, half = o.half, rot = o.rot or CFrame.identity }
	elseif eyes[1] and eyes[1].ell then
		local e = eyes[1].ell :: any
		S = { c = e.c, half = e.half, rot = e.rot }
	elseif eyes[1] then
		local r = eyes[1].hr
		S = { c = eyes[1].hc, half = V(r, r, r), rot = CFrame.identity }
	else
		return
	end
	local function onS(p: Vector3, out: number): (Vector3, Vector3)
		local q, n = Kit.onEll(S.c, S.half, S.rot, p - S.c)
		return q + n * out, n
	end
	-- a point near an eye on the surface that eye sits on (a frog's dome, a stalk's bulb), unless the plan says the
	-- head's own is truer (eyeSurf false: eyes set on a surface standing off the head)
	local function onE(e: Kit.EyeRec, p: Vector3, out: number): (Vector3, Vector3)
		if o.eyeSurf == false then
			return onS(p, out)
		end
		local el = e.ell
		if el then
			local q, n = Kit.onEll(el.c, el.half, el.rot, p - el.c)
			return q + n * out, n
		end
		local d = p - e.hc
		local n = if d.Magnitude > 1e-5 then d.Unit else e.n
		return e.hc + n * (e.hr + out), n
	end
	-- the face's frame: forward between the eyes, up, and right
	local f, u = FWD, UP
	if #eyes >= 2 then
		local ns, us = Vector3.zero, Vector3.zero
		for _, e in eyes do
			ns += e.n
			us += e.up
		end
		f = if ns.Magnitude > 1e-4 then ns.Unit else FWD
		local uu = us - f * us:Dot(f)
		u = if uu.Magnitude > 1e-4 then uu.Unit else UP
	end
	local r = u:Cross(f)
	-- a direction from the head's middle: turned `yaw` degrees toward its right and `pitch` up from forward
	local function dirF(yaw: number, pitch: number): Vector3
		return (CFrame.fromAxisAngle(u, R(yaw)) * CFrame.fromAxisAngle(r, R(-pitch))):VectorToWorldSpace(f)
	end
	local hs = (S.half.X + S.half.Y + S.half.Z) / 3 -- the head's size, as a radius
	-- a small flat mark lying on the head at p (`w` across, `l` along `along`; near the eye `e`, on its surface)
	local function dot(name: string, p: Vector3, w: number, l: number, color: string, along: Vector3?, neon: boolean?, e: Kit.EyeRec?)
		local q, n
		if e then
			q, n = onE(e, p, LIFT)
		else
			q, n = onS(p, LIFT)
		end
		local a = along or u
		Kit.ell(name, q, V(w, 0.035, l), color, A.lie(n, a), nil, neon)
	end
	-- a line of marks lying on the head through `pts` (each set out LIFT), radii along it, flattened against the head
	local function line(name: string, pts: { Vector3 }, radii: { number }, color: string, flat: number?, neon: boolean?, e: Kit.EyeRec?)
		local q: { Vector3 } = {}
		local ns: { Vector3 } = {}
		for i, p in pts do
			if e then
				q[i], ns[i] = onE(e, p, LIFT)
			else
				q[i], ns[i] = onS(p, LIFT)
			end
		end
		for i = 1, #q - 1 do
			local ra, rb = radii[math.min(i, #radii)], radii[math.min(i + 1, #radii)]
			Kit.limb(name, q[i], q[i + 1], ra, rb, color, flat or 0.6, (ns[i] + ns[i + 1]).Unit, nil, neon)
		end
	end

	------------------------------------------------ brows
	if more.brows ~= false then
		for _, e in eyes do
			Kit.on(e.joint)
			local sb = STYLE_BROW[e.style]
			if sb == nil then
				continue
			end
			local kind: string = if type(more.brows) == "string" then more.brows else (TEX_BROW[tex] or sb)
			if (kind == "pale" and A.isPale(col)) or (sb == "specs" and kind ~= "none") then
				-- (over spectacles the brow keeps clear of the rims: the spectacles' own shape)
				kind = sb
			end
			if kind == "none" then
				continue
			end
			local shape = BROW_SHAPE[kind] or BROW_SHAPE[sb] or BROW_SHAPE.soft
			-- (a small eye still gets a brow that reads: measured on at least a modest eye)
			local w, h = math.max(e.w, hs * 0.42), math.max(e.h, hs * 0.42)
			local function at(up: number, out: number): Vector3
				return e.at + e.up * h * up + e.outer * w * out
			end
			local p1, p2, p3 = at(shape[1], shape[2]), at(shape[3], shape[4]), at(shape[5], shape[6])
			if kind == "scales" then
				-- a ridge of scale over the eye, its middle one standing out
				line("Brow", { p1, p2, p3 }, { 0.025, 0.028, 0.025 }, markC, 0.6, nil, e)
				dot("BrowScale", p2 + e.up * h * 0.1, 0.05, 0.065, markC, p3 - p1, nil, e)
			elseif kind == "fuzz" then
				-- soft tufts in a row over the eye
				for _, p in { p1, p2, p3 } do
					local q, n = onE(e, p, LIFT * 0.6)
					Kit.ell("BrowFuzz", q, V(0.065, 0.065, 0.065), if A.isDark(col) then markC else under, A.lie(n))
				end
			elseif kind == "ridge" then
				line("Brow", { p1, p2, p3 }, { 0.03, 0.034, 0.026 }, markC, 0.6, nil, e)
			elseif kind == "frost" then
				line("Brow", { p1, p2, p3 }, { 0.026, 0.03, 0.025 }, "white", 0.6, nil, e)
			elseif kind == "pale" then
				line("Brow", { p1, p2, p3 }, { 0.025, 0.028, 0.025 }, if A.isPale(under) and not A.isPale(col) then under else markC, 0.6, nil, e)
			else
				line("Brow", { p1, p2, p3 }, { 0.025, 0.028, 0.025 }, markC, 0.6, nil, e)
			end
		end
	end

	------------------------------------------------ the muzzle
	local mouth = rec.mouth
	if more.muzzle ~= false then
		if o.lip and #o.lip >= 2 then
			Kit.on(if mouth then mouth.joint else back)
			local q: { Vector3 } = o.lip
			for i = 1, #q - 1 do
				Kit.limb("Lip", q[i], q[i + 1], 0.025, 0.025, ink, 0.7, f)
			end
		end
		Kit.on(back)
		local dc = o.padC or markC
		if o.pads then
			-- whisker dots: three in a row on each pad
			-- (a pad is an ellipsoid lying square to the plan's axes)
			for _, pad in o.pads do
				local s = if pad.c.X < S.c.X then -1 else 1
				for _, d in { V(0.42, 0.18, 0.88), V(0.6, -0.02, 0.8), V(0.38, -0.22, 0.9) } do
					local dd = V(d.X * s, d.Y, d.Z).Unit
					local hh = pad.half
					local p = pad.c + V(dd.X * hh.X, dd.Y * hh.Y, dd.Z * hh.Z) / math.sqrt(dd.X * dd.X + dd.Y * dd.Y + dd.Z * dd.Z)
					local nn = V(dd.X / hh.X, dd.Y / hh.Y, dd.Z / hh.Z).Unit
					Kit.ell("WhiskerDot", p + nn * 0.03, V(0.045, 0.045, 0.045), dc)
				end
			end
		end
		local sn = o.snout
		if sn then
			local ax = sn.b - sn.a
			local side0 = r - ax.Unit * r:Dot(ax.Unit)
			local sideV = if side0.Magnitude > 1e-4 then side0.Unit else r
			local upV = ax.Unit:Cross(sideV)
			if upV:Dot(u) < 0 then
				upV = -upV
			end
			local function onSnout(t: number, ang: number, s: number, out: number): Vector3
				local c0 = sn.a + ax * t
				local rr = sn.ra + (sn.rb - sn.ra) * t
				local a = R(ang)
				return c0 + sideV * s * rr * math.cos(a) * (1 + out / rr) + upV * rr * sn.flat * math.sin(a) * (1 + out / (rr * sn.flat))
			end
			if o.muzzle == "lizard" then
				-- the scales along a reptile's upper lip: two a side
				for _, s in { -1, 1 } do
					for _, t in { 0.4, 0.7 } do
						local q = onSnout(t, -12, s, LIFT)
						Kit.ell("LipScale", q, V(0.05, 0.035, 0.06), markC, A.lie(sideV * s, ax.Unit))
					end
				end
			elseif o.muzzle == "snout" then
				-- whisker dots along a long snout (a mole's)
				for _, s in { -1, 1 } do
					for _, tp in { { 0.6, 18 }, { 0.72, 6 }, { 0.6, -8 } } do
						Kit.ell("WhiskerDot", onSnout(tp[1], tp[2], s, 0.03), V(0.045, 0.045, 0.045), dc)
					end
				end
			end
		end
		local bk = o.beak
		if bk then
			-- a beak's nostrils near its root on top, the line between its two halves, a paler tip
			local ax = bk.tip - bk.root
			local L = ax.Magnitude
			local fw = ax.Unit
			local sv = r - fw * r:Dot(fw)
			sv = if sv.Magnitude > 1e-4 then sv.Unit else r
			local uv = fw:Cross(sv)
			if uv:Dot(u) < 0 then
				uv = -uv
			end
			local bw = bk.w
			local nc = A.shade(A.shade(bk.color))
			for _, s in { -1, 1 } do
				if bk.duck then
					local p = bk.root + fw * L * 0.28 + uv * bw * 0.2 + sv * s * bw * 0.2
					Kit.ell("Nostril", p, V(0.05, 0.035, 0.07), nc, A.lie(uv, fw))
				else
					local rr = bw * 0.5 * (1 - 0.22 * 0.88)
					local p = bk.root + fw * L * 0.22 + uv * rr * 0.62 + sv * s * rr * 0.5
					Kit.ell("Nostril", p, V(0.05, 0.035, 0.06), nc, A.lie((uv + sv * s * 0.6).Unit, fw))
					-- the gape: from the corner of the mouth by the face along the beak's side
					local g1 = bk.root + sv * s * bw * 0.47 - uv * bw * 0.16
					local g2 = bk.root + fw * L * 0.42 + sv * s * bw * 0.3 - uv * bw * 0.16
					Kit.limb("Gape", g1, g2, 0.025, 0.025, A.shade(nc), 0.7, sv * s)
				end
			end
			if not bk.duck then
				Kit.ell("BeakTip", bk.tip - fw * 0.03 + uv * 0.01, V(0.07, 0.06, 0.08), if A.isPale(bk.color) then A.shade(bk.color) else "cream", A.lie(fw, uv))
			end
		end
	end

	------------------------------------------------ cheeks
	Kit.on(back)
	if more.cheeks ~= false and #eyes >= 2 then
		for _, e in eyes do
			local w, h = math.max(e.w, hs * 0.42), math.max(e.h, hs * 0.42)
			local s = if e.outer:Dot(r) < 0 then -1 else 1
			-- (an eye on a stalk or in a dome: its cheek is on the head, under where the eye stands)
			local el = e.ell
			local apart = el ~= nil and (el.c - S.c).Magnitude > hs * 0.3
			local ce: Kit.EyeRec? = if apart then nil else e
			local cheekAt = function(x: number, y: number): Vector3
				if ce then
					return ce.at - ce.up * h * y + ce.outer * w * x
				end
				return S.c + dirF(s * (30 + x * 30), -8 - y * 12) * hs
			end
			Kit.on(if apart then back else e.joint)
			if tex == "fur" or tex == "fluff" then
				-- tufts standing out from the side of the face below the eye, sweeping back and down
				local tc: string = more.tuft or o.tuft or col
				local fl = tex == "fluff"
				local n = if fl then 3 else 2
				for i = 1, n do
					local root = onS(S.c + dirF(s * (62 + i * 7), -10 - i * 12) * hs, -0.03)
					local d = (r * s * 1.0 - u * (0.35 + i * 0.25) - f * 0.45).Unit
					local len = hs * (if fl then 0.3 else 0.36) * (1 - (i - 1) * 0.15)
					local wd = hs * (if fl then 0.13 else 0.11)
					Kit.limb("CheekTuft", root, root + d * len, wd, wd * (if fl then 0.5 else 0.15), tc, 0.6, f)
				end
			elseif tex == "feather" or tex == "scale" then
				-- the edges of two small feathers (or scales) on the cheek, below and behind the eye
				for i, x in { 0.05, 0.42 } do
					local c0 = cheekAt(x, 0.7 + i * 0.06)
					line("Scallop", { c0 - u * 0.02 - r * s * 0.05, c0 - u * 0.045, c0 - u * 0.02 + r * s * 0.05 }, { 0.025 }, markC, 0.5, nil, ce)
				end
			elseif tex == "chitin" then
				-- two little pits in the plate of the cheek
				dot("Pit", cheekAt(0.0, 0.7), 0.045, 0.045, markC, nil, nil, ce)
				dot("Pit", cheekAt(0.4, 0.82), 0.045, 0.045, markC, nil, nil, ce)
			elseif (tex == "stone" or tex == "shell" or tex == "brick") and s > 0 then
				-- a crack running down one cheek
				line("Crack", { cheekAt(0.3, 0.55), cheekAt(0.18, 0.75), cheekAt(0.32, 0.95) }, { 0.025 }, marks.crack or A.shade(markC), 0.5, nil, ce)
			elseif tex == "velvet" then
				-- a soft puff of fuzz at the cheek
				local q, n = onS(S.c + dirF(s * 58, -18) * hs, 0.0)
				Kit.ell("CheekFuzz", q, V(hs * 0.24, hs * 0.2, hs * 0.2), if A.isDark(col) then markC else under, A.lie(n))
			end
			-- (freckles spaced so each stays its own dot, never running into a smudge)
			local FRECKLES = { { -0.3, 0.72 }, { 0.1, 0.86 }, { 0.5, 0.72 } }
			if marks.freckles and tex ~= "skin" and tex ~= "ember" and tex ~= "jelly" then
				for _, q in FRECKLES do
					dot("Freckle", cheekAt(q[1], q[2]), 0.045, 0.045, marks.freckles, nil, marks.glow == true, ce)
				end
			end
			if tex == "skin" or tex == "ember" or tex == "jelly" then
				-- freckles in a short row under the eye (lit on an ember creature)
				local fc = if tex == "ember" then "lava" else (marks.freckles or markC)
				for _, q in FRECKLES do
					dot("Freckle", cheekAt(q[1], q[2]), 0.045, 0.045, fc, nil, tex == "ember" or (marks.glow == true and marks.freckles ~= nil), ce)
				end
			elseif tex == "ice" then
				-- a glint of frost on the cheek
				dot("Frost", cheekAt(0.3, 0.7), 0.05, 0.05, "white", nil, true, ce)
				dot("Frost", cheekAt(0.54, 0.54), 0.035, 0.035, "white", nil, true, ce)
			elseif tex == "bark" then
				-- the grain of the bark running down the cheek
				line("Grain", { cheekAt(0.1, 0.62), cheekAt(0.16, 0.82), cheekAt(0.1, 1.02) }, { 0.025 }, markC, 0.5, nil, ce)
			end
		end
	end

	------------------------------------------------ the crown of the head
	Kit.on(if eyes[1] then eyes[1].joint else back)
	if more.crown ~= false then
		local top = function(yaw: number, pitch: number, out: number): (Vector3, Vector3)
			return onS(S.c + dirF(yaw, pitch) * hs, out)
		end
		if tex == "feather" then
			-- a little crest of feathers swept back off the crown
			for i, yp in { { 0, 70 }, { -9, 64 }, { 9, 64 } } do
				local p, n = top(yp[1], yp[2], -0.04)
				local d = (n * 0.9 - f * 0.7 + r * yp[1] / 25).Unit
				Kit.limb("Crest", p, p + d * hs * (if i == 1 then 0.42 else 0.3), hs * 0.08, 0.025, if i == 1 then acc else col, 0.45, r)
			end
		elseif tex == "scale" then
			-- a broad plate in the middle of the brow
			dot("CrownScale", S.c + dirF(0, 50) * hs, 0.065, 0.1, markC, u)
		elseif tex == "shell" or tex == "stone" or tex == "brick" then
			-- a crack across the brow and a chip out of it
			local cc: string = marks.crack or A.shade(markC)
			line("Crack", { S.c + dirF(14, 72) * hs, S.c + dirF(6, 58) * hs, S.c + dirF(14, 48) * hs, S.c + dirF(9, 38) * hs }, { 0.025 }, cc, 0.5)
			dot("Chip", S.c + dirF(-20, 60) * hs, 0.06, 0.05, cc)
		elseif tex == "crystal" then
			-- a little cut gem set in the brow, its glint at the top left
			local p, n = top(0, 44, LIFT)
			Kit.ell("Gem", p, V(0.12, 0.05, 0.15), marks.gem or acc, A.lie(n, u))
			Kit.ell("GemGlint", p + n * 0.03 + u * 0.03 - r * 0.025, V(0.04, 0.04, 0.04), "white", nil, nil, true)
		elseif tex == "bark" then
			-- a sprout of leaves from the brow
			local p, n = top(-10, 64, -0.02)
			local tip = p + (n + f * 0.2).Unit * hs * 0.2
			Kit.limb("Sprout", p, tip, 0.025, 0.025, "leaf_dark")
			for _, s in { -1, 1 } do
				Kit.limb("SproutLeaf", tip, tip + (r * s + u * 0.5 + f * 0.2).Unit * hs * 0.22, 0.05, 0.025, marks.leaf or "leaf", 0.4, (u - r * s * 0.3 + f).Unit)
			end
		elseif tex == "ice" then
			-- a little star of frost on the brow
			local p, n = top(0, 52, LIFT)
			for _, a in { 0, 90 } do
				local d = (CFrame.fromAxisAngle(n, R(a + 45))):VectorToWorldSpace(u)
				Kit.limb("Frost", p - d * 0.06, p + d * 0.06, 0.025, 0.025, "white", 0.5, n, nil, true)
			end
		elseif tex == "jelly" then
			-- a gloss over the top left of the head
			line("Shine", { S.c + dirF(-38, 30) * hs, S.c + dirF(-30, 46) * hs, S.c + dirF(-14, 56) * hs }, { 0.025, 0.03, 0.025 }, "white", 0.6, true)
			dot("Shine", S.c + dirF(-44, 18) * hs, 0.04, 0.04, "white", nil, true)
		elseif tex == "chitin" then
			-- the edge of the plate over an insect's face: one arc over both eyes (or, with its eyes on stalks, over
			-- the mouth), standing in for brows
			local pts: { Vector3 } = {}
			local near = #eyes >= 2 and eyes[1].ell ~= nil and ((eyes[1].ell :: any).c - S.c).Magnitude <= hs * 0.3
			if near and more.brows ~= false then
				local eL, eR = eyes[1], eyes[2]
				if eL.outer:Dot(r) > 0 then
					eL, eR = eR, eL
				end
				local function over(e: Kit.EyeRec, up: number, out: number): Vector3
					local h = math.max(e.h, hs * 0.42)
					return e.at + e.up * h * up + e.outer * math.max(e.w, hs * 0.42) * out
				end
				pts = { over(eL, 0.3, 0.52), over(eL, 0.62, 0.05), S.c + dirF(0, 44) * hs, over(eR, 0.62, 0.05), over(eR, 0.3, 0.52) }
			elseif not near then
				pts = { S.c + dirF(-24, 6) * hs, S.c + dirF(0, 14) * hs, S.c + dirF(24, 6) * hs }
			end
			if #pts > 0 then
				local q: { Vector3 } = {}
				for i, p in pts do
					q[i] = onS(p, LIFT)
				end
				Kit.limbs("Plate", q, { 0.025 }, markC, #q - 1, 0.5, f)
			end
			-- a glint on the shell of its head, at the top left where the light falls
			dot("Glint", S.c + dirF(-34, 58) * hs, 0.05, 0.05, "white")
			if mouth and more.mandibles ~= false then
				-- and two little mandibles at the mouth's corners
				Kit.on(mouth.joint)
				for _, s in { -1, 1 } do
					local a0 = mouth.mid + mouth.right * s * mouth.w * 0.62 + mouth.n * 0.02
					local a1 = a0 + mouth.n * 0.06 - mouth.up * 0.07 - mouth.right * s * 0.05
					Kit.limb("Mandible", a0, a1, 0.03, 0.025, A.shade(acc))
				end
			end
		end
	end

	------------------------------------------------ the species' own marks
	Kit.on(if eyes[1] then eyes[1].joint else back)
	local glow = marks.glow == true
	if marks.blaze then
		-- a stripe down the middle of the brow toward the nose
		line("Blaze", { S.c + dirF(0, 64) * hs, S.c + dirF(0, 40) * hs, S.c + dirF(0, 14) * hs }, { 0.034, 0.04, 0.03 }, marks.blaze, 0.5, glow)
	end
	if marks.star then
		-- a four pointed star on the brow
		local p, n = onS(S.c + dirF(0, 50) * hs, LIFT)
		for _, a in { 0, 90 } do
			local d = (CFrame.fromAxisAngle(n, R(a))):VectorToWorldSpace(u)
			Kit.limb("Star", p - d * 0.08, p + d * 0.08, 0.025, 0.025, marks.star, 0.5, n, nil, glow)
		end
		Kit.ell("Star", p + n * 0.01, V(0.06, 0.035, 0.06), marks.star, A.lie(n), nil, glow)
	end
	if marks.kohl then
		-- a line drawn out from the outer corner of each eye, as on an old carving of a cat
		for _, e in eyes do
			Kit.on(e.joint)
			local w, h = math.max(e.w, hs * 0.42), math.max(e.h, hs * 0.42)
			line("Kohl", { e.at + e.outer * w * 0.42 - e.up * h * 0.02, e.at + e.outer * w * 0.7 - e.up * h * 0.1, e.at + e.outer * w * 0.86 - e.up * h * 0.02 }, { 0.026, 0.025 }, marks.kohl, 0.5, nil, e)
		end
		Kit.on(if eyes[1] then eyes[1].joint else back)
	end
	if marks.spots then
		-- spots over the brow (lit, a moon fawn's)
		for i, yp in { { -20, 56 }, { 18, 62 }, { 2, 74 } } do
			dot("Spot", S.c + dirF(yp[1], yp[2]) * hs, 0.065 - i * 0.004, 0.065 - i * 0.004, marks.spots, nil, glow)
		end
	end
	Kit.on(back)
end

------------------------------------------------------------------ the head
-- The head on its own joint ("head", on `parent`, default "body", pivoting at `pivot`): a cranium (an ellipsoid at `c`,
-- `size` across), the muzzle, the nose, the jaw (its own joint), the eyes on the cranium (Kit.faceOn), blush and the
-- mouth. opts:
--   muzzle  "fox" (long and pointed), "dog" (shorter and square), "cat" (short, two puffy whisker pads), "bear"
--           (short and round), "deer" (long, tapering, a soft nose), "pig" (a short snout with a flat disc),
--           "beak" (a bird's, `beak` its colour), "duck" (a broad flat bill), "lizard" (long and flat), "frog" (a
--           wide flat face), "none"
--   mlen    the muzzle's length (studs), mw its width, mc its colour (default the head's), nose the nose's colour
--   eye     { spread, lift, d, iris? } (radians, radians, studs); tilt how far the eyes look down the muzzle
--   cheeks  a colour for puffed cheek fur, blush true for pink cheeks, mouth true (default) for a mouth
--   face    what the face's details should leave out or add (A.face, FaceMore); faceLater true when the plan adds
--           its own nose or mouth after and calls A.face itself
-- Returns the head's frame for ears, horns and crests: { c, half, top, front, nose }.
export type HeadOpts = {
	c: Vector3,
	size: Vector3,
	color: string,
	pivot: Vector3?,
	parent: string?,
	muzzle: string?,
	mlen: number?,
	mw: number?,
	mh: number?,
	mc: string?,
	mdrop: number?,
	nose: string?,
	beak: string?,
	eye: { number }?,
	iris: string?,
	ink: string?,
	cheeks: string?,
	blush: boolean?,
	mouth: boolean?,
	tongue: string?,
	jaw: boolean?,
	fangs: string?,
	whiskers: boolean?,
	face: FaceMore?,
	faceLater: boolean?,
}
export type Head = { c: Vector3, half: Vector3, top: Vector3, front: Vector3, nose: Vector3, mass: Mass }
function A.head(o: HeadOpts): Head
	local c, size, col = o.c, o.size, o.color
	Kit.J("head", o.parent or "body", o.pivot or (c - UP * size.Y * 0.4 - FWD * size.Z * 0.15), "head")
	local half = size / 2
	local _, mass = A.blob("Head", c, size, col)
	local ink = o.ink or "black"
	local kind = o.muzzle or "dog"
	local mlen = o.mlen or size.Z * 0.42
	local mw = o.mw or size.X * 0.42
	local mh = o.mh or mw * 0.8
	local mc = o.mc or col
	local drop = o.mdrop or size.Y * 0.16
	-- where the muzzle leaves the face: low on the front of the cranium
	local root = c + V(0, -drop, half.Z * 0.55)
	local nose = c + V(0, -drop, half.Z)
	local mouthAt: Vector3? = nil
	local mouthN = V(0, -0.35, 1)
	local mouthW = mw * 0.7
	-- (what the face's details need to know of the muzzle: A.face)
	local fo: FaceOpts = { color = col, ink = ink, muzzle = kind, more = o.face }
	local lipTop: { Vector3 }? = nil -- the line from the nose down, before the mouth's middle ends it
	if kind == "fox" or kind == "dog" or kind == "deer" or kind == "lizard" then
		local taper = if kind == "fox" then 0.42 elseif kind == "deer" then 0.6 elseif kind == "lizard" then 0.7 else 0.78
		local flat = if kind == "lizard" then 0.55 elseif kind == "dog" then 0.85 else 0.8
		local dip = if kind == "deer" then 0.06 else 0.02
		local tip = root + V(0, -mlen * dip - (if kind == "fox" then mh * 0.12 else 0), mlen)
		Kit.limb("Muzzle", root, tip, mw * 0.5, mw * 0.5 * taper, mc, flat, UP)
		nose = tip + FWD * mw * 0.5 * taper * 0.8 + UP * mh * 0.12
		fo.snout = { a = root, b = tip, ra = mw * 0.5, rb = mw * 0.5 * taper, flat = flat }
		fo.padC = A.markC(mc)
		if kind ~= "lizard" then
			-- (down the front of the muzzle's end from under the nose)
			local rt = mw * 0.5 * taper
			local ns = if kind == "deer" then 1.15 else 1
			lipTop = { nose - UP * mw * 0.13 * ns + FWD * mw * 0.05, tip + (FWD * 0.75 - UP * flat * 0.66).Unit * (rt + 0.035) }
		end
		if kind ~= "lizard" then
			Kit.ell("Nose", nose, V(mw * 0.42, mw * 0.3, mw * 0.3) * (if kind == "deer" then 1.15 else 1), o.nose or ink)
			if full() then
				Kit.ell("NoseShine", nose + V(-mw * 0.06, mw * 0.08, mw * 0.06), V(0.05, 0.05, 0.05), "white")
			end
		else
			-- (a lizard's nostrils: two dots on top of the snout's end)
			for _, s in { -1, 1 } do
				Kit.ell("Nostril", tip + V(s * mw * 0.13, mh * 0.2, mw * 0.08), V(0.06, 0.05, 0.06), A.shade(mc), nil, true)
			end
		end
		mouthAt = lerp(root, tip, 0.72) + V(0, -mh * 0.42, 0)
		mouthW = mw * (if kind == "fox" then 0.5 else 0.7)
		if o.whiskers and full() then
			for _, s in { -1, 1 } do
				for _, a in { -10, 8 } do
					local base = lerp(root, tip, 0.65) + V(s * mw * 0.32, 0, 0)
					Kit.rod("Whisker", base, base + (CFrame.Angles(0, 0, s * R(a)) * CFrame.Angles(0, s * R(-25), 0)):VectorToWorldSpace(V(s, 0, 0)) * mw * 0.9, 0.05, "cream", true)
				end
			end
		end
	elseif kind == "cat" or kind == "bear" then
		-- a short muzzle: two round whisker pads side by side, the nose on top where they meet, a small chin
		local pr = mw * (if kind == "cat" then 0.34 else 0.42)
		for _, s in { -1, 1 } do
			Kit.ell("MuzzlePad", root + V(s * pr * 0.72, -pr * 0.15, mlen * 0.45), V(pr * 2, pr * 1.6, pr * 1.8), mc)
		end
		Kit.ell("Chin", root + V(0, -pr * 0.95, mlen * 0.3), V(pr * 1.4, pr * 1.0, pr * 1.3), mc, nil, true)
		nose = root + V(0, pr * 0.55, mlen * 0.45 + pr * 0.8)
		Kit.ell("Nose", nose, V(pr * 1.05, pr * 0.62, pr * 0.6), o.nose or (if kind == "cat" then "pink" else ink))
		fo.pads = {}
		for _, s in { -1, 1 } do
			table.insert(fo.pads :: any, { c = root + V(s * pr * 0.72, -pr * 0.15, mlen * 0.45), half = V(pr, pr * 0.8, pr * 0.9) })
		end
		fo.padC = A.markC(mc)
		lipTop = { nose - UP * pr * 0.26 + FWD * pr * 0.1 }
		if full() then
			Kit.ell("NoseShine", nose + V(-pr * 0.15, pr * 0.2, pr * 0.2), V(0.05, 0.05, 0.05), "white")
		end
		mouthAt = root + V(0, -pr * 0.55, mlen * 0.45 + pr * 0.85)
		mouthW = pr * 1.3
		if (o.whiskers ~= false) and full() and kind == "cat" then
			for _, s in { -1, 1 } do
				for _, a in { -12, 0, 12 } do
					local base = root + V(s * pr * 1.5, -pr * 0.1, mlen * 0.45 + pr * 0.3)
					Kit.rod("Whisker", base, base + (CFrame.Angles(0, 0, s * R(a)) * CFrame.Angles(0, s * R(-15), 0)):VectorToWorldSpace(V(s, 0, 0)) * mw * 1.0, 0.05, "white", true)
				end
			end
		end
	elseif kind == "pig" then
		local tip = root + V(0, 0, mlen)
		Kit.limb("Muzzle", root, tip, mw * 0.5, mw * 0.48, mc, 0.85, UP)
		nose = tip + FWD * mw * 0.42
		Kit.ell("Snout", nose, V(mw * 0.9, mw * 0.72, mw * 0.24), o.nose or "pink")
		if full() then
			for _, s in { -1, 1 } do
				Kit.ell("Nostril", nose + V(s * mw * 0.16, 0, mw * 0.1), V(mw * 0.16, mw * 0.24, 0.05), "clay")
			end
		end
		mouthAt = tip + V(0, -mw * 0.42, 0)
		mouthW = mw * 0.6
	elseif kind == "beak" or kind == "duck" then
		local bc = o.beak or "orange"
		if kind == "beak" then
			-- a cone from the face to a point, the upper half hooked down a little at the tip
			local tip = root + V(0, -mlen * 0.25, mlen)
			Kit.limb("Beak", root, tip, mw * 0.5, mw * 0.06, bc, 0.85, UP)
			if full() then
				Kit.limb("BeakHook", lerp(root, tip, 0.65) + UP * mw * 0.08, tip - UP * mw * 0.08 + FWD * mw * 0.04, mw * 0.18, mw * 0.05, bc)
			end
			nose = tip
			fo.beak = { root = root, tip = tip, w = mw, color = bc }
		else
			-- a broad flat bill: wide, flat, round at the end, a nail at its tip
			local tip = root + V(0, -mlen * 0.1, mlen)
			Kit.limb("Bill", root, tip, mw * 0.5, mw * 0.55, bc, 0.36, UP)
			if full() then
				Kit.ell("BillNail", tip + FWD * mw * 0.45 + UP * mw * 0.08, V(mw * 0.3, mw * 0.12, mw * 0.2), A.shade(bc))
			end
			nose = tip
			fo.beak = { root = root, tip = tip, w = mw, color = bc, duck = true }
		end
	elseif kind == "frog" then
		-- a wide flat face, its mouth a long line right across
		nose = c + V(0, -drop, half.Z)
		mouthAt = c + V(0, -half.Y * 0.4, half.Z * 0.92)
		mouthW = size.X * 0.55
		if full() then
			for _, s in { -1, 1 } do
				Kit.ell("Nostril", c + V(s * size.X * 0.12, half.Y * 0.05, half.Z * 0.97), V(0.06, 0.05, 0.05), A.shade(col))
			end
		end
	end
	-- the jaw: a chin under the muzzle that drops when the mouth opens
	if o.jaw ~= false then
		local jawAt = if mouthAt then mouthAt - UP * 0.04 else root - UP * mh * 0.4
		Kit.J("jaw", "head", jawAt + V(0, 0.02, -mlen * 0.5), "jaw")
		if kind ~= "beak" and kind ~= "duck" and kind ~= "frog" and kind ~= "cat" and kind ~= "bear" then
			Kit.limb("Jaw", root - UP * mh * 0.32 - FWD * mlen * 0.05, (mouthAt or root) - UP * mh * 0.08 + FWD * mlen * 0.05, mw * 0.36, mw * 0.24, o.cheeks or mc, 0.7, UP)
		elseif kind == "beak" then
			Kit.limb("BeakLow", root - UP * mw * 0.18, root + V(0, -mlen * 0.3, mlen * 0.72), mw * 0.36, mw * 0.05, A.shade(o.beak or "orange"), 0.7, UP)
		elseif kind == "duck" then
			Kit.limb("BillLow", root - UP * mw * 0.16, root + V(0, -mlen * 0.16, mlen * 0.9), mw * 0.42, mw * 0.46, A.shade(o.beak or "orange"), 0.3, UP)
		end
		if o.fangs and full() and mouthAt then
			for _, s in { -1, 1 } do
				local at = mouthAt + V(s * mouthW * 0.32, 0.02, 0.02)
				Kit.limb("Fang", at, at - UP * 0.1, 0.035, 0.012, o.fangs)
			end
		end
		Kit.on("head")
	end
	-- cheek fur
	if o.cheeks then
		for _, s in { -1, 1 } do
			Kit.ell("CheekFur", c + V(s * half.X * 0.62, -half.Y * 0.38, half.Z * 0.18), V(size.X * 0.42, size.Y * 0.4, size.Z * 0.5), o.cheeks)
		end
	end
	-- the eyes on the cranium's front, then the mouth
	Kit.faceOn(c, half)
	local e = o.eye or { R(30), R(10), size.Y * 0.36 }
	Kit.eyes(c, (half.X + half.Y + half.Z) / 3, FWD, e[1], e[2], e[3], o.iris, if ink ~= "black" then ink else nil)
	if o.blush then
		Kit.blush(c, (half.X + half.Y + half.Z) / 3, FWD, R(48), R(14), size.X * 0.2)
	end
	Kit.faceOff()
	if o.mouth ~= false and mouthAt then
		Kit.on("head")
		Kit.mouth(mouthAt, mouthN, mouthW, ink, o.tongue or "pink")
	end
	Kit.on("head")
	-- the face's details, up close
	local m = Kit.faceRec().mouth
	if lipTop and m then
		local pts = table.clone(lipTop)
		table.insert(pts, m.mid + m.up * 0.02)
		fo.lip = pts
	end
	fo.c, fo.half = c, half
	fo.under = o.cheeks
	fo.tuft = o.cheeks
	if not o.faceLater then
		A.face(fo)
	end
	Kit.on("head")
	return { c = c, half = half, top = c + UP * half.Y, front = c + FWD * half.Z, nose = nose, mass = mass }
end

------------------------------------------------------------------ ears
-- A pair of ears on the head (each its own joint "earL" / "earR", kind "ear"): opts.kind
--   "fox"    tall and pointed, a pale inside, a dark tip        "cat"    smaller triangles, a pink inside
--   "round"  a bear's or a mouse's: round discs on top            "long"   a rabbit's: tall, narrow, upright
--   "droop"  a puppy's: hanging down the sides                   "leaf"   a deer's: out to the sides, pointed
--   "tuft"   an owl's or a lynx's: a feathered point              "fin"    a frill of skin (an axolotl's, a fish's)
--   "big"    an elephant's or a fennec's: very large and round
-- len the ear's length, w its width, at (0..1, default 0.3) how far out from the top middle they sit, back how far they
-- lean back (degrees), c the colour, inner the inside's colour, tip a tip colour.
export type EarOpts = { kind: string, len: number?, w: number?, at: number?, back: number?, out: number?, c: string, inner: string?, tip: string? }
function A.ears(h: Head, o: EarOpts)
	local kind = o.kind
	local half = h.half
	local len = o.len or half.Y * 1.1
	local w = o.w or len * 0.6
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		-- the base on the cranium, up and out
		local yaw = (o.at or 0.3) * 90
		local baseDir = (CFrame.Angles(0, 0, -side * R(yaw)) * CFrame.Angles(R(-(o.back or 8)), 0, 0)):VectorToWorldSpace(UP)
		local base = Kit.onEll(h.c, half, CFrame.identity, baseDir) - baseDir * w * 0.15
		Kit.J("ear" .. s, "head", base, "ear", side)
		if Kit.full() and kind ~= "tuft" then
			-- the ear's root, thick where it grows from the head, so up close the blended body runs from the head
			-- into the ear (Render/Raster.drawBlend) instead of a flat flap stuck on
			Kit.ell("EarRoot" .. s, base, V(w * 0.6, w * 0.55, w * 0.5), o.c)
		end
		local outward = V(side, 0, 0)
		local dirUp: Vector3
		if kind == "droop" then
			dirUp = (V(side * 0.5, -1, 0.1)).Unit
		elseif kind == "leaf" then
			dirUp = (V(side * 1, 0.35, -0.15)).Unit
		elseif kind == "big" then
			dirUp = (V(side * 0.9, 0.5, -0.2)).Unit
		elseif kind == "fin" then
			dirUp = (V(side * 0.9, 0.3, -0.5)).Unit
		else
			local out = o.out or (if kind == "long" then 0.12 else 0.35)
			dirUp = (baseDir + outward * out + V(0, 0, -math.sin(R(o.back or 8)) * 0.6)).Unit
		end
		local tipP = base + dirUp * len
		-- the flat side faces forward (and out a little)
		local face = (FWD + outward * 0.35).Unit
		if kind == "droop" then
			face = (outward + FWD * 0.2).Unit
		elseif kind == "leaf" or kind == "big" then
			face = (FWD + UP * 0.4).Unit
		end
		if kind == "round" or kind == "big" then
			local d = if kind == "big" then len else w
			Kit.limb("Ear" .. s, base, base + dirUp * d * 0.5, d * 0.5, d * 0.5, o.c, 0.32, face)
			if o.inner then
				Kit.limb("EarIn" .. s, base + dirUp * d * 0.08 + face * d * 0.07, base + dirUp * d * 0.45 + face * d * 0.07, d * 0.34, d * 0.34, o.inner, 0.2, face)
			end
		elseif kind == "tuft" then
			Kit.limb("Ear" .. s, base, tipP, w * 0.5, w * 0.06, o.c, 0.5, face)
			if full() then
				Kit.limb("Ear" .. s, lerp(base, tipP, 0.2) + outward * w * 0.15, tipP + outward * len * 0.18 - UP * len * 0.1, w * 0.3, w * 0.04, o.tip or o.c, 0.5, face)
			end
		elseif kind == "fin" then
			-- a frill: three soft points fanning back
			for i, a in { -20, 0, 22 } do
				local d = (CFrame.fromAxisAngle(face, R(a) * side)):VectorToWorldSpace(dirUp)
				Kit.limb("Ear" .. s, base, base + d * len * (1 - math.abs(i - 2) * 0.18), w * 0.24, w * 0.08, if i == 2 then (o.tip or o.c) else o.c, 0.45, face)
			end
		else
			-- a pointed ear: wide at the base, tapering to a point; the inside a step in front; a tip of another colour
			local tipR = if kind == "long" then w * 0.3 else w * 0.07
			local flat = if kind == "long" then 0.42 else 0.5
			Kit.limb("Ear" .. s, base, tipP, w * 0.5, tipR, o.c, flat, face)
			if o.inner and kind ~= "droop" then
				local inB = base + dirUp * len * 0.12 + face * w * 0.14
				Kit.limb("EarIn" .. s, inB, lerp(base, tipP, 0.82) + face * w * 0.1, w * 0.33, tipR * 0.7, o.inner, flat * 0.55, face)
			end
			if o.tip then
				-- (a sleeve over the ear's top: it shows only where it stands more than the pixel filter's depth bias, about
				-- 0.03 studs, proud of the ear, across its flat side too)
				local r0 = w * 0.5 + (tipR - w * 0.5) * 0.6
				local m = 0.04
				local rs0, rs1 = r0 + m, tipR + m
				local fs = math.min(1, (r0 * flat + m) / rs0)
				Kit.limb("EarTip" .. s, lerp(base, tipP, 0.6), tipP + dirUp * 0.02, rs0, rs1, o.tip, fs, face)
			end
		end
	end
	Kit.on("head")
end

------------------------------------------------------------------ horns
-- A pair of horns on the head (on the head's joint): opts.kind
--   "nubs"   two short rounded knobs (a fawn's, a giraffe's)       "spike"  one straight spiral horn in the middle
--   "goat"   curving back                                         "ram"    curling round beside the head
--   "antler" branching up and out                                 "drake"  swept back, a dragon's
--   "stag"   (antler, bigger)
-- len the horn's length, r its radius at the base, c its colour, at (0..1) how far out from the middle.
export type HornOpts = { kind: string, len: number?, r: number?, at: number?, c: string, fwd: number? }
function A.horns(h: Head, o: HornOpts)
	Kit.on("head")
	local half = h.half
	local len = o.len or half.Y * 1.1
	local r = o.r or len * 0.18
	if o.kind == "spike" then
		local base = Kit.onEll(h.c, half, CFrame.identity, V(0, 1, 0.55)) - V(0, r * 0.4, 0)
		local tip = base + V(0, len * 0.86, len * 0.5)
		Kit.limb("Horn", base, tip, r, r * 0.12, o.c)
		if full() then
			-- the spiral's ridges: thin rings up the horn
			for i = 1, 3 do
				local u = i / 4.2
				Kit.limb("HornRing", lerp(base, tip, u) - (tip - base).Unit * 0.02, lerp(base, tip, u) + (tip - base).Unit * 0.02, r * (1 - u * 0.88) * 1.12, r * (1 - u * 0.88) * 1.05, A.shade(o.c))
			end
		end
		return
	end
	for _, side in { -1, 1 } do
		local at = o.at or 0.32
		local bd = (CFrame.Angles(0, 0, -side * R(at * 90)) * CFrame.Angles(R(-(o.fwd or 10)), 0, 0)):VectorToWorldSpace(UP)
		local base = Kit.onEll(h.c, half, CFrame.identity, bd) - bd * r * 0.4
		local out = V(side, 0, 0)
		if o.kind == "nubs" then
			Kit.limb("Horn", base, base + bd * len * 0.5, r, r * 0.9, o.c)
			Kit.ell("HornTip", base + bd * len * 0.55, V(r, r, r) * 2.1, o.c)
		elseif o.kind == "goat" then
			Kit.limbs("Horn", { base, base + V(side * len * 0.12, len * 0.55, -len * 0.2), base + V(side * len * 0.22, len * 0.78, -len * 0.62), base + V(side * len * 0.24, len * 0.62, -len * 0.95) }, { r, r * 0.6, r * 0.12 }, o.c, 3)
		elseif o.kind == "ram" then
			-- a curl: up, back, down round the side of the head and forward
			local c0 = base + out * len * 0.32 - FWD * len * 0.2
			local pts = { base }
			for i = 1, 6 do
				local a = i / 6 * math.pi * 1.55
				table.insert(pts, c0 + out * (len * 0.12 * i / 6) + UP * math.cos(a) * len * 0.42 - FWD * math.sin(a) * len * 0.42 + (UP * len * 0.0))
			end
			Kit.limbs("Horn", pts, { r, r * 0.85, r * 0.6, r * 0.3 }, o.c, if full() then 6 else 3)
		elseif o.kind == "antler" or o.kind == "stag" then
			local k = if o.kind == "stag" then 1.35 else 1
			local main = { base, base + V(side * len * 0.3, len * 0.5, -len * 0.05) * k, base + V(side * len * 0.55, len * 0.95, -len * 0.18) * k }
			Kit.limbs("Antler", main, { r, r * 0.7, r * 0.3 }, o.c, 2)
			-- tines forward and up
			for i, u in { 0.45, 0.8 } do
				local p = Kit.curveAt(main, u)
				local tip = p + V(side * len * 0.06, len * 0.32, len * 0.18) * k * (1 - i * 0.15)
				Kit.limb("Antler", p, tip, r * (0.7 - u * 0.3), r * 0.15, o.c)
			end
			Kit.limb("Antler", main[3], main[3] + V(-side * len * 0.12, len * 0.22, 0.02) * k, r * 0.3, r * 0.12, o.c, nil, nil, true)
		elseif o.kind == "drake" then
			Kit.limbs("Horn", { base, base + V(side * len * 0.18, len * 0.45, -len * 0.4), base + V(side * len * 0.26, len * 0.6, -len * 0.95) }, { r, r * 0.55, r * 0.08 }, o.c, 2)
		end
	end
end

------------------------------------------------------------------ tails
-- A tail from `base` (just inside the rump), two joints ("tail1", "tail2": kind "tail", their order down it), opts.kind
--   "brush"  a fox's: thin at the root, full in the middle, a tip of `tip` colour, sweeping back and up
--   "whip"   a cat's or a lizard's: long and thin, curling up at the end           "stub"   a bear's or a deer's
--   "puff"   a rabbit's: a round tuft                                              "curl"   a pig's or a pug's
--   "flat"   a beaver's: a paddle                                                  "fluke"  a whale's or a seal's
--   "plume"  a bird's: a fan of long feathers                                      "club"   an ankylosaur's: a knob
--   "lizard" thick at the root, long, tapering, lying low
-- len its length, r its radius at the root, c its colour, tip a tip colour, up (degrees) how far it rises.
export type TailOpts = { kind: string, len: number?, r: number?, c: string, tip: string?, up: number?, curl: number?, parent: string? }
function A.tail(base: Vector3, o: TailOpts)
	local kind = o.kind
	local len = o.len or 1.0
	local r = o.r or 0.12
	local up = R(o.up or 30)
	local c = o.c
	Kit.J("tail1", o.parent or "body", base, "tail", 0, 1)
	if kind == "stub" then
		Kit.ell("Tail", base + V(0, r * 0.3, -r * 0.6), V(r * 2.2, r * 2.4, r * 2.2), c)
		if o.tip then
			Kit.ell("TailTip", base + V(0, -r * 0.2, -r * 1.1), V(r * 1.4, r * 1.3, r * 1.2), o.tip, nil, true)
		end
		return
	elseif kind == "puff" then
		Kit.ell("Tail", base + V(0, r * 0.4, -r * 0.6), V(r * 2.8, r * 2.6, r * 2.6), o.tip or c)
		return
	end
	local d1 = V(0, math.sin(up), -math.cos(up))
	if kind == "curl" then
		local pts = { base }
		local cc = base - FWD * r * 2.2 + UP * r * 1.2
		for i = 1, 6 do
			local a = i / 6 * math.pi * 1.7
			table.insert(pts, cc + V(math.sin(a) * r * 0.5, -math.cos(a) * r * 1.1, -math.sin(a) * r * 1.1))
		end
		Kit.limbs("Tail", pts, { r, r * 0.6 }, c, if full() then 5 else 3)
		return
	end
	local mid = base + d1 * len * 0.5
	local curlUp = o.curl or 0
	-- the second half bends on up by `curl` degrees as it goes: walked in small steps so it curves smoothly
	local function after(_p: Vector3, u: number): Vector3
		local q = mid
		local steps = math.max(1, math.ceil(u * 8))
		for i = 1, steps do
			local a = up + R(curlUp) * ((i - 0.5) / steps) * u
			q += V(0, math.sin(a), -math.cos(a)) * (len * 0.5 * u / steps)
		end
		return q
	end
	local tipP = after(mid, 1)
	if kind == "brush" then
		Kit.limbs("Tail", { base, lerp(base, mid, 0.5) + UP * 0.02, mid }, { r * 0.7, r * 1.6 }, c, 2)
		Kit.J("tail2", "tail1", mid, "tail", 0, 2)
		local tip1 = after(mid, 0.55)
		Kit.limb("Tail", mid, tip1, r * 1.6, r * 1.5, c)
		Kit.limb(if o.tip then "TailTip" else "Tail", tip1, tipP, r * 1.5, r * 0.25, o.tip or c)
	elseif kind == "whip" or kind == "lizard" then
		local r0 = if kind == "lizard" then r * 1.6 else r
		Kit.limbs("Tail", { base, lerp(base, mid, 0.5), mid }, { r0, r0 * 0.75 }, c, 2)
		Kit.J("tail2", "tail1", mid, "tail", 0, 2)
		local tip0 = after(mid, 0.35)
		local tip1 = after(mid, 0.7)
		Kit.limb("Tail", mid, tip0, r0 * 0.75, r0 * 0.62, c)
		Kit.limb("Tail", tip0, tip1, r0 * 0.62, r0 * 0.48, c)
		Kit.limb(if o.tip then "TailTip" else "Tail", tip1, tipP, r0 * 0.48, r0 * 0.2, o.tip or c)
	elseif kind == "flat" or kind == "fluke" then
		Kit.limb("Tail", base, mid, r, r * 0.8, c)
		Kit.J("tail2", "tail1", mid, "tail", 0, 2)
		if kind == "flat" then
			Kit.limb("TailPaddle", mid, tipP, r * 1.7, r * 1.4, o.tip or c, 0.3, V(0, math.cos(up), math.sin(up)))
		else
			for _, s in { -1, 1 } do
				Kit.limb("TailFluke", mid, tipP + V(s * len * 0.3, 0, len * 0.05), r * 0.8, r * 0.3, o.tip or c, 0.28, V(0, 1, 0))
			end
		end
	elseif kind == "plume" then
		Kit.ell("TailRoot", base, V(r * 2.4, r * 1.6, r * 2.4), c)
		Kit.J("tail2", "tail1", base, "tail", 0, 2)
		local n = if full() then 5 else 3
		for i = 1, n do
			local yaw = (-1 + 2 * (i - 1) / (n - 1)) * 28
			local d = (CFrame.Angles(0, R(yaw), 0)):VectorToWorldSpace(d1)
			local L = len * (1 - math.abs(yaw) / 28 * 0.2)
			local col = if o.tip and (i % 2 == 0) then o.tip else c
			Kit.limb("TailFeather", base, base + d * L, r * 0.5, r * 0.9, col, 0.26, V(0, math.cos(up), math.sin(up)))
		end
	elseif kind == "club" then
		Kit.limbs("Tail", { base, mid }, { r, r * 0.7 }, c, 1)
		Kit.J("tail2", "tail1", mid, "tail", 0, 2)
		Kit.limb("Tail", mid, tipP, r * 0.7, r * 0.5, c)
		Kit.ell("TailClub", tipP, V(r * 3, r * 2.2, r * 2.6), o.tip or c)
	end
end

------------------------------------------------------------------ wings
-- A pair of wings (joints "wingL" / "wingR" on the body, kind "wing", and an outer segment "wingL2" / "wingR2" when
-- `fold` is false): opts.kind
--   "bird"    feathered: a rounded arm with a row of long flight feathers off its back edge
--   "bat"     a membrane between long fingers (a bat's, a dragon's)
--   "insect"  two pairs of thin rounded panes (a moth's, a sprite's, a bee's)
-- at the shoulder (the right one; the left is mirrored), span the wing's length out from it, c its colour, edge the
-- feathers' or the membrane's colour, fold true to lie folded along the body (a bird on the ground), spread up (deg).
export type WingOpts = { kind: string, at: Vector3, span: number, c: string, edge: string?, fold: boolean?, up: number?, chord: number? }
function A.wings(o: WingOpts)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		local sh = A.mx(o.at, side)
		Kit.J("wing" .. s, "body", sh, "wing", side)
		local span = o.span
		local chord = o.chord or span * 0.45
		local upA = R(o.up or 20)
		local out = V(side * math.cos(upA), math.sin(upA), 0)
		if o.kind == "bird" then
			if o.fold then
				-- folded against the side (`at` on the body's surface at the shoulder): the wing a long flat oval laid
				-- along the flank, sloping down to the back, its long flight feathers crossing past the rump
				local th = chord * 0.34
				local slope = A.lie(V(0, -0.32, -1), V(side, 0.15, 0))
				local wc = sh + V(side * th * 0.25, -chord * 0.14, -span * 0.32)
				Kit.ell("Wing" .. s, wc, V(chord * 0.92, span * 0.78, th), o.c, slope)
				local tipP = sh + V(side * th * 0.1, -chord * 0.42, -span * 0.98)
				local n = if full() then 3 else 2
				for i = 1, n do
					local u = (i - 1) / math.max(1, n - 1)
					local b0 = wc + V(side * th * 0.2, -chord * (0.1 + u * 0.16), -span * 0.12)
					Kit.limb("Feather" .. s, b0, tipP - UP * chord * u * 0.12 + V(0, 0, span * 0.06 * u), chord * 0.2, chord * 0.06, if i == 1 then o.c else (o.edge or o.c), 0.3, V(side, 0.15, 0))
				end
			else
				local elbow = sh + out * span * 0.45 - FWD * chord * 0.05
				Kit.limb("Wing" .. s, sh, elbow, chord * 0.28, chord * 0.22, o.c, 0.4, UP)
				Kit.J("wing" .. s .. "2", "wing" .. s, elbow, "wing", side, 1)
				local tipP = elbow + out * span * 0.55 - FWD * chord * 0.2
				Kit.limb("Wing" .. s, elbow, tipP, chord * 0.22, chord * 0.1, o.c, 0.4, UP)
				local n = if full() then 6 else 3
				for i = 1, n do
					local u = (i - 1) / (n - 1)
					local b0 = lerp(sh + out * span * 0.15, tipP, u)
					local len2 = chord * (0.9 - u * 0.35)
					Kit.limb("Feather" .. s, b0, b0 - FWD * len2 + out * len2 * u * 0.5, chord * 0.14, chord * 0.12, if u > 0.6 then (o.edge or o.c) else o.c, 0.25, UP)
				end
			end
		elseif o.kind == "bat" then
			local elbow = sh + out * span * 0.38 + FWD * chord * 0.12
			Kit.limb("WingArm" .. s, sh, elbow, chord * 0.12, chord * 0.08, o.c)
			Kit.J("wing" .. s .. "2", "wing" .. s, elbow, "wing", side, 1)
			local hand = elbow + out * span * 0.12
			local mem = o.edge or A.shade(o.c)
			-- three fingers fanning back from the hand; a membrane panel between each pair
			local tips = {}
			for i, a in { 18, -10, -42 } do
				local d = (CFrame.fromAxisAngle(UP, R(a) * side)):VectorToWorldSpace(out)
				local tip = hand + d * span * (0.62 - i * 0.06) - UP * chord * 0.05 * i
				tips[i] = tip
				Kit.limb("WingFinger" .. s, hand, tip, chord * 0.07, chord * 0.03, o.c)
			end
			local prev = sh - FWD * chord * 0.55 - UP * chord * 0.1
			for i = 1, 3 do
				local a, b = prev, tips[i]
				local mid = lerp(a, b, 0.5)
				local c0 = lerp(hand, mid, 0.55)
				-- the membrane: a flat ellipsoid spanning the hand, the finger tip and the panel before it
				local across = (b - a)
				local fwdIn = (hand - mid)
				local n = across:Cross(fwdIn)
				n = if n.Magnitude > 1e-5 then n.Unit else UP
				local rot = CFrame.fromMatrix(Vector3.zero, across.Unit, n:Cross(across.Unit), n)
				Kit.ell("WingSkin" .. s, c0, V(across.Magnitude * 0.98, fwdIn.Magnitude * 1.5, 0.06), mem, rot)
				prev = b
			end
		elseif o.kind == "insect" then
			-- the forewing and the hindwing: thin rounded panes, a darker rim up close
			for i, w in { { a = 18, l = 1, k = 0.5 }, { a = -28, l = 0.72, k = 0.42 } } do
				local d = (CFrame.fromAxisAngle(V(0, 0, 1), R(w.a) * side) * CFrame.fromAxisAngle(UP, R(-10 - i * 14) * side)):VectorToWorldSpace(V(side, 0, 0))
				local L = span * w.l
				local c0 = sh + d * L * 0.5
				local n = (V(0, 0, 1) + V(0, 0.35, 0)):Cross(d)
				n = d:Cross(UP)
				local wy = L * w.k
				local rot = CFrame.fromMatrix(Vector3.zero, d, UP - d * UP:Dot(d), d:Cross(UP - d * UP:Dot(d)).Unit)
				local _ = n
				if o.edge and full() then
					Kit.ell("WingRim" .. s, c0, V(L * 1.04, wy * 1.08, 0.05), o.edge, rot)
				end
				Kit.ell("Wing" .. s, c0 + rot.ZVector * 0.03, V(L, wy, 0.05), o.c, rot)
			end
		end
	end
	Kit.on("body")
end

return A
