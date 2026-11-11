--!strict
-- The driftlings in 3D (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module (client: MicroModels.driftling builds
-- them for the islands, the islets' stages and the boat).
--
-- The requests (2026-11-11): "alot of the creatures are just simple shapes meshed together. can they be more detailed
-- and look more like the animals /creatures that they are referencing?"; "add more expressive idle and other
-- animations to the creatures, the whole mesh seems to move as one throughout all their animations. you can make
-- different moving parts for creatures to allow for more expressiveness".
--
-- Each body plan (Data/Creatures `shape`) is built from plain parts (Models/Blocks: palette colours, eighth-stud
-- sizes, no meshes), facing +Z with its feet on the ground, in its species' body and accent colours, on a small
-- skeleton: joints with a pivot and a parent (the body, then the head on it, the jaw and the ears on the head, the
-- legs, arms, wings, fins, tail segments, eye stalks, pincers, tendrils and antennae). `animate(thing, time, mood, k,
-- squash)` turns each joint about its pivot for the moment and the mood (the joints' turns compose down the chain:
-- an ear on a head that nods), so a driftling breathes, looks about, blinks, twitches its ears, wags its tail and
-- walks on its own legs, winds up and lunges with its jaw open, recoils when hit and goes limp when knocked out.
-- Moods: "idle" | "walk" | "attack" (k: the blow's progress) | "hurt" | "cheer" | "ko".
-- Eyes ("EyeL", "EyeR") and their shines are "Keep" parts (a hit's white flash leaves them); the eyes blink by size.
local Blocks = require(script.Parent.Blocks)

local DriftModels = {}

export type Joint = { parent: string?, pivot: Vector3, kind: string, side: number, phase: number }
export type Rig = {
	joints: { [string]: Joint },
	order: { string }, -- parents before children
	of: { [string]: string }, -- part name -> its joint
	gait: string, -- "quad" | "biped" | "hop" | "scuttle" | "slither" | "fly"
	world: { [string]: CFrame }, -- each joint's pose now (animate)
}
export type Thing = {
	model: Model,
	parts: { [string]: BasePart },
	rest: { [string]: CFrame },
	sizes: { [string]: Vector3 },
	baseRest: { [string]: CFrame },
	baseSize: { [string]: Vector3 },
	colors: { [string]: Color3 },
	h: number,
	r: number,
	kind: string,
	rig: Rig?,
}

local R = math.rad
local V = Vector3.new

------------------------------------------------------------------ building
local cur: Thing? = nil -- the thing being built
local curJoint = "body" -- the joint new parts go on

local function fine(v: number): number
	return math.max(0.125, math.floor(v * 8 + 0.5) / 8)
end

local function new(shape: string, h: number, r: number, gait: string): Thing
	local m = Blocks.model(nil, "Micro_drift_" .. shape)
	local t: Thing = {
		model = m,
		parts = {},
		rest = {},
		sizes = {},
		baseRest = {},
		baseSize = {},
		colors = {},
		h = h,
		r = r,
		kind = "drift_" .. shape,
		rig = { joints = {}, order = {}, of = {}, gait = gait, world = {} },
	}
	cur = t
	curJoint = "body"
	return t
end

-- A joint (and the one new parts go on from now): its pivot in the thing's space, its parent, what moves it.
local function J(name: string, parent: string?, pivot: Vector3, kind: string, side: number?, phase: number?)
	local t = cur :: Thing
	local rig = t.rig :: Rig
	rig.joints[name] = { parent = parent, pivot = pivot, kind = kind, side = side or 0, phase = phase or 0 }
	table.insert(rig.order, name)
	curJoint = name
end

local function on(name: string)
	curJoint = name
end

-- One part on the current joint: `at` is its centre, `rot` a turn about it.
local function P(name: string, shape: string, size: Vector3, at: Vector3, color: string, rot: CFrame?, neon: boolean?): BasePart
	local t = cur :: Thing
	local n = name
	local i = 2
	while t.parts[n] do
		n = name .. i
		i += 1
	end
	local cf = CFrame.new(at) * (rot or CFrame.identity)
	local shp: any = if shape == "Block" then nil else shape
	local p = Blocks.part(t.model, { size = size, cf = cf, color = color, name = n, shape = shp, collide = false, query = false, neon = neon })
	p.Size = V(fine(size.X), fine(size.Y), fine(size.Z))
	p.CastShadow = false
	t.parts[n] = p
	t.rest[n] = cf
	t.sizes[n] = p.Size
	t.baseRest[n] = cf
	t.baseSize[n] = p.Size
	t.colors[n] = p.Color
	;(t.rig :: Rig).of[n] = curJoint
	return p
end

local function keep(p: BasePart): BasePart
	p:SetAttribute("Keep", true)
	return p
end

-- One eye: a dark oval with a white shine in its upper corner (toward the light: the top left of the picture).
local function eye(name: string, at: Vector3, s: number, color: string?)
	keep(P("Eye" .. name, "Block", V(s, s * 1.25, 0.125), at, color or "black"))
	local h = math.max(0.125, s * 0.4)
	keep(P("Shine" .. name, "Block", V(h, h, 0.125), at + V(-s * 0.2, s * 0.3, 0.07), "white"))
end

-- A pair of eyes on the current joint, `gap` apart, and optionally brows over them.
local function eyes(y: number, z: number, gap: number, s: number, brow: string?)
	eye("L", V(-gap / 2, y, z), s)
	eye("R", V(gap / 2, y, z), s)
	if brow then
		P("BrowL", "Block", V(s + 0.125, 0.125, 0.125), V(-gap / 2, y + s * 0.85, z - 0.02), brow, CFrame.Angles(0, 0, R(-12)))
		P("BrowR", "Block", V(s + 0.125, 0.125, 0.125), V(gap / 2, y + s * 0.85, z - 0.02), brow, CFrame.Angles(0, 0, R(12)))
	end
end

local function cheeks(y: number, z: number, gap: number)
	P("CheekL", "Block", V(0.25, 0.125, 0.125), V(-gap / 2, y, z), "pink")
	P("CheekR", "Block", V(0.25, 0.125, 0.125), V(gap / 2, y, z), "pink")
end

local function mouth(y: number, z: number, w: number?)
	keep(P("Mouth", "Block", V(w or 0.25, 0.125, 0.125), V(0, y, z), "black"))
end

-- Four legs on hips at (±x, y) front (zf) and back (zb): a leg and a paw each, diagonal pairs in step.
local function legs4(x: number, y: number, zf: number, zb: number, w: number, color: string, paw: string, spread: number?)
	local sp = spread or 0
	for _, l in { { n = "FL", s = -1, z = zf, ph = 0 }, { n = "FR", s = 1, z = zf, ph = 0.5 }, { n = "BL", s = -1, z = zb, ph = 0.5 }, { n = "BR", s = 1, z = zb, ph = 0 } } do
		local side, z = l.s, l.z
		J("leg" .. l.n, "body", V(side * x, y, z), "leg", side, l.ph)
		P("Leg" .. l.n, "Block", V(w, y, w), V(side * (x + sp), y / 2, z), color)
		P("Paw" .. l.n, "Block", V(w + 0.125, 0.125, w + 0.125), V(side * (x + sp), 0.06, z + 0.08), paw)
	end
end

------------------------------------------------------------------ the body plans
local PLANS: { [string]: (b: string, a: string) -> Thing } = {}

-- a pebble creature: a faceted rock on stubby feet, moss and a pebble on top, little arms, a cracked face
PLANS.blob = function(b, a)
	local t = new("blob", 1.9, 1, "biped")
	J("body", nil, V(0, 0.35, 0), "body")
	J("head", "body", V(0, 0.35, 0), "head") -- (the whole rock rocks and nods)
	P("Rock", "Ball", V(1.75, 1.5, 1.7), V(0, 0.95, 0), b)
	P("Facet", "Block", V(0.75, 0.5, 0.25), V(0.45, 1.35, 0.7), b, CFrame.Angles(R(-15), R(10), 0))
	P("Facet", "Block", V(0.5, 0.5, 0.25), V(-0.6, 0.7, 0.68), a, CFrame.Angles(0, R(-20), 0))
	P("Facet", "Block", V(0.5, 0.375, 0.5), V(0.75, 0.75, -0.3), a)
	P("Crack", "Block", V(0.125, 0.5, 0.125), V(-0.35, 1.45, 0.82), a)
	P("Crack", "Block", V(0.375, 0.125, 0.125), V(-0.25, 1.25, 0.84), a)
	P("Moss", "Block", V(0.875, 0.25, 0.75), V(0.15, 1.7, -0.05), "leaf")
	P("Moss", "Block", V(0.25, 0.25, 0.25), V(0.42, 1.88, 0.12), "leaf_dark")
	P("Moss", "Block", V(0.25, 0.375, 0.25), V(-0.1, 1.9, -0.25), "leaf")
	P("Pebble", "Block", V(0.375, 0.25, 0.375), V(-0.55, 1.72, -0.2), a)
	eyes(1.12, 0.84, 0.62, 0.3, a)
	mouth(0.82, 0.86, 0.375)
	cheeks(0.92, 0.82, 1.0)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "head", V(side * 0.82, 1.05, 0.15), "arm", side)
		P("Arm" .. s, "Block", V(0.375, 0.5, 0.375), V(side * 0.95, 0.82, 0.2), b)
		P("Hand" .. s, "Block", V(0.375, 0.25, 0.375), V(side * 0.98, 0.55, 0.24), a)
		J("leg" .. s, "body", V(side * 0.42, 0.35, 0.1), "leg", side, if side < 0 then 0 else 0.5)
		P("Foot" .. s, "Block", V(0.5, 0.3, 0.6), V(side * 0.42, 0.15, 0.18), a)
	end
	return t
end

-- a crab: a wide shell, eyes on stalks, two big claws with a hinged upper pincer, three legs a side
PLANS.crab = function(b, a)
	local t = new("crab", 1.6, 1.2, "scuttle")
	J("body", nil, V(0, 0.75, 0), "body")
	P("Shell", "Ball", V(1.9, 0.875, 1.35), V(0, 0.8, 0), b)
	P("ShellTop", "Ball", V(1.4, 0.5, 1.0), V(0, 1.12, -0.05), b)
	P("Rim", "Block", V(1.75, 0.25, 1.25), V(0, 0.62, 0.02), a)
	P("Under", "Block", V(1.25, 0.25, 0.875), V(0, 0.42, 0), "cream")
	P("Spot", "Block", V(0.25, 0.125, 0.25), V(0.4, 1.36, 0.12), "cream")
	P("Spot", "Block", V(0.25, 0.125, 0.25), V(-0.38, 1.34, -0.16), "cream")
	P("Spot", "Block", V(0.125, 0.125, 0.125), V(0.05, 1.38, -0.3), "cream")
	mouth(0.62, 0.68, 0.25)
	cheeks(0.78, 0.66, 0.9)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		on("body")
		J("stalk" .. s, "body", V(side * 0.28, 1.15, 0.42), "stalk", side)
		P("Stalk" .. s, "Block", V(0.125, 0.5, 0.125), V(side * 0.28, 1.4, 0.45), a)
		P("EyeBall" .. s, "Ball", V(0.375, 0.375, 0.375), V(side * 0.28, 1.75, 0.48), "white")
		eye(s, V(side * 0.28, 1.76, 0.64), 0.2)
		J("arm" .. s, "body", V(side * 0.85, 0.82, 0.35), "arm", side)
		P("UpperArm" .. s, "Block", V(0.25, 0.25, 0.5), V(side * 1.0, 0.78, 0.55), a)
		P("Claw" .. s, "Ball", V(0.75, 0.625, 0.75), V(side * 1.22, 0.85, 0.95), b)
		P("ClawLow" .. s, "Block", V(0.25, 0.25, 0.375), V(side * 1.28, 0.72, 1.35), b)
		J("pincer" .. s, "arm" .. s, V(side * 1.25, 1.02, 1.1), "pincer", side)
		P("Pincer" .. s, "Block", V(0.25, 0.25, 0.5), V(side * 1.25, 1.05, 1.38), a)
		for i, z in { 0.2, -0.12, -0.44 } do
			J("leg" .. s .. i, "body", V(side * 0.82, 0.55, z), "leg", side, (i % 2) * 0.5)
			P("Leg" .. s .. i, "Block", V(0.5, 0.125, 0.125), V(side * 1.02, 0.55, z), a, CFrame.Angles(0, 0, side * R(-20)))
			P("Shin" .. s .. i, "Block", V(0.125, 0.5, 0.125), V(side * 1.22, 0.28, z), a)
		end
	end
	return t
end

-- a gull with a fish's fin: a round body, a head with a two-part beak (the lower one opens), folded wings with a
-- white bar and feathered tips, a forked tail, thin legs on webbed feet, a crest and a fin on its back
PLANS.bird = function(b, a)
	local t = new("bird", 2.1, 0.9, "biped")
	J("body", nil, V(0, 0.9, 0), "body")
	P("Body", "Ball", V(1.3, 1.2, 1.5), V(0, 0.95, -0.05), b)
	P("Belly", "Ball", V(0.9, 0.85, 0.375), V(0, 0.85, 0.6), "cream")
	P("Fin", "Wedge", V(0.125, 0.5, 0.625), V(0, 1.55, -0.35), a)
	J("head", "body", V(0, 1.4, 0.3), "head")
	P("Head", "Ball", V(0.95, 0.9, 0.95), V(0, 1.78, 0.42), b)
	P("Cap", "Block", V(0.625, 0.25, 0.5), V(0, 2.15, 0.35), a)
	P("Crest", "Block", V(0.125, 0.5, 0.25), V(0, 2.35, 0.15), a, CFrame.Angles(R(-25), 0, 0))
	P("Crest", "Block", V(0.125, 0.375, 0.25), V(0, 2.3, 0.0), a, CFrame.Angles(R(-45), 0, 0))
	eyes(1.88, 0.84, 0.44, 0.22, a)
	cheeks(1.7, 0.85, 0.62)
	P("Beak", "Wedge", V(0.3, 0.2, 0.5), V(0, 1.74, 1.05), "orange", CFrame.Angles(0, math.pi, 0))
	J("jaw", "head", V(0, 1.64, 0.82), "jaw")
	P("BeakLow", "Block", V(0.25, 0.125, 0.375), V(0, 1.6, 1.02), "orange")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("wing" .. s, "body", V(side * 0.6, 1.35, 0), "wing", side)
		P("Wing" .. s, "Block", V(0.2, 0.625, 1.0), V(side * 0.7, 1.05, -0.05), a)
		P("WingBar" .. s, "Block", V(0.22, 0.125, 0.875), V(side * 0.71, 1.28, -0.05), "white")
		P("WingTip" .. s, "Block", V(0.2, 0.375, 0.5), V(side * 0.72, 0.82, -0.62), a, CFrame.Angles(R(-30), 0, 0))
		J("leg" .. s, "body", V(side * 0.25, 0.45, 0.05), "leg", side, if side < 0 then 0 else 0.5)
		P("Leg" .. s, "Block", V(0.125, 0.375, 0.125), V(side * 0.25, 0.25, 0.05), "orange")
		P("Foot" .. s, "Block", V(0.375, 0.125, 0.5), V(side * 0.25, 0.06, 0.2), "orange")
	end
	J("tail", "body", V(0, 0.95, -0.7), "tail", 0, 1)
	P("Tail", "Wedge", V(0.75, 0.25, 0.625), V(0, 0.95, -1.0), a)
	P("TailFork", "Block", V(0.25, 0.125, 0.25), V(-0.25, 0.9, -1.35), "white")
	P("TailFork", "Block", V(0.25, 0.125, 0.25), V(0.25, 0.9, -1.35), "white")
	return t
end

-- a rabbit: a round body on big hind feet, a head with long ears (pink inside, coloured tips), a muzzle, nose,
-- buck teeth and whiskers, little front paws, a cotton tail, a sprout on top
PLANS.bun = function(b, a)
	local t = new("bun", 2.4, 0.9, "hop")
	J("body", nil, V(0, 0.7, 0), "body")
	P("Body", "Ball", V(1.4, 1.3, 1.45), V(0, 0.8, -0.1), b)
	P("Belly", "Ball", V(0.9, 0.8, 0.3), V(0, 0.75, 0.55), "cream")
	J("head", "body", V(0, 1.3, 0.25), "head")
	P("Head", "Ball", V(1.15, 1.0, 1.0), V(0, 1.6, 0.35), b)
	P("Muzzle", "Ball", V(0.625, 0.375, 0.3), V(0, 1.42, 0.82), "cream")
	P("Nose", "Block", V(0.25, 0.125, 0.125), V(0, 1.55, 0.95), "pink")
	P("Teeth", "Block", V(0.25, 0.125, 0.125), V(0, 1.27, 0.92), "white")
	eyes(1.7, 0.82, 0.5, 0.25)
	cheeks(1.5, 0.82, 0.78)
	P("WhiskL", "Block", V(0.375, 0.125, 0.125), V(-0.45, 1.45, 0.86), "cream", CFrame.Angles(0, 0, R(8)))
	P("WhiskR", "Block", V(0.375, 0.125, 0.125), V(0.45, 1.45, 0.86), "cream", CFrame.Angles(0, 0, R(-8)))
	P("Sprout", "Block", V(0.125, 0.375, 0.125), V(0, 2.15, 0.3), "leaf")
	P("SproutLeaf", "Block", V(0.375, 0.125, 0.25), V(0.14, 2.35, 0.3), "leaf", CFrame.Angles(0, 0, R(20)))
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ear" .. s, "head", V(side * 0.28, 2.0, 0.25), "ear", side)
		P("Ear" .. s, "Block", V(0.3, 0.875, 0.2), V(side * 0.32, 2.4, 0.2), b, CFrame.Angles(0, 0, side * R(-8)))
		P("EarIn" .. s, "Block", V(0.125, 0.625, 0.125), V(side * 0.32, 2.38, 0.3), "pink", CFrame.Angles(0, 0, side * R(-8)))
		P("EarTip" .. s, "Block", V(0.3, 0.2, 0.2), V(side * 0.38, 2.86, 0.2), a, CFrame.Angles(0, 0, side * R(-8)))
		J("arm" .. s, "body", V(side * 0.35, 1.0, 0.5), "arm", side)
		P("Paw" .. s, "Block", V(0.3, 0.3, 0.3), V(side * 0.35, 0.8, 0.62), b)
		J("leg" .. s, "body", V(side * 0.45, 0.4, -0.05), "leg", side, 0)
		P("Thigh" .. s, "Ball", V(0.5, 0.55, 0.75), V(side * 0.5, 0.35, -0.05), b)
		P("Foot" .. s, "Block", V(0.375, 0.2, 0.75), V(side * 0.45, 0.1, 0.22), "cream")
	end
	J("tail", "body", V(0, 0.75, -0.75), "tail", 0, 1)
	P("Tail", "Ball", V(0.5, 0.5, 0.5), V(0, 0.8, -0.86), "white")
	return t
end

-- a gecko: a long low body with a stripe and a spiky crest, a head with a snout, nostrils and a jaw that opens,
-- frills, four splayed legs with toes, a tail in two segments with a coloured tip
PLANS.lizard = function(b, a)
	local t = new("lizard", 1.4, 1.3, "quad")
	J("body", nil, V(0, 0.55, 0), "body")
	P("Body", "Block", V(0.875, 0.625, 1.6), V(0, 0.58, -0.05), b)
	P("Back", "Ball", V(0.875, 0.5, 1.5), V(0, 0.85, -0.05), b)
	P("Belly", "Block", V(0.7, 0.2, 1.3), V(0, 0.32, 0.05), "cream")
	P("Stripe", "Block", V(0.9, 0.125, 0.25), V(0, 0.75, -0.3), a)
	for i = 0, 3 do
		P("Spike", "Block", V(0.125, 0.25 + (i % 2) * 0.125, 0.25), V(0, 1.12, 0.45 - i * 0.4), a)
	end
	J("head", "body", V(0, 0.75, 0.75), "head")
	P("Head", "Block", V(0.8, 0.625, 0.7), V(0, 0.88, 1.05), b)
	P("Snout", "Block", V(0.625, 0.375, 0.5), V(0, 0.82, 1.5), b)
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(-0.18, 0.95, 1.75), "black")
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(0.18, 0.95, 1.75), "black")
	eyes(1.08, 1.3, 0.62, 0.22, a)
	P("FrillL", "Block", V(0.125, 0.5, 0.375), V(-0.45, 1.0, 0.8), a, CFrame.Angles(0, 0, R(20)))
	P("FrillR", "Block", V(0.125, 0.5, 0.375), V(0.45, 1.0, 0.8), a, CFrame.Angles(0, 0, R(-20)))
	J("jaw", "head", V(0, 0.62, 0.9), "jaw")
	P("Jaw", "Block", V(0.55, 0.15, 0.625), V(0, 0.6, 1.32), "cream")
	J("tail1", "body", V(0, 0.6, -0.85), "tail", 0, 1)
	P("Tail1", "Block", V(0.5, 0.375, 0.8), V(0, 0.55, -1.2), b)
	J("tail2", "tail1", V(0, 0.5, -1.6), "tail", 0, 2)
	P("Tail2", "Block", V(0.375, 0.3, 0.7), V(0, 0.45, -1.9), b)
	P("TailTip", "Block", V(0.25, 0.25, 0.4), V(0, 0.42, -2.35), a)
	on("body")
	for _, l in { { n = "FL", s = -1, z = 0.5, ph = 0 }, { n = "FR", s = 1, z = 0.5, ph = 0.5 }, { n = "BL", s = -1, z = -0.55, ph = 0.5 }, { n = "BR", s = 1, z = -0.55, ph = 0 } } do
		local side, z = l.s, l.z
		J("leg" .. l.n, "body", V(side * 0.45, 0.45, z), "leg", side, l.ph)
		P("Leg" .. l.n, "Block", V(0.25, 0.375, 0.25), V(side * 0.6, 0.25, z), b, CFrame.Angles(0, 0, side * R(-15)))
		P("Toe" .. l.n, "Block", V(0.375, 0.125, 0.3), V(side * 0.68, 0.06, z + 0.1), a)
	end
	return t
end

-- an owl: a round body with a pale chevroned belly, a head that turns with pale discs round big eyes, brows, a
-- hooked beak and ear tufts, folded wings with a pale bar, a tail, talons
PLANS.owl = function(b, a)
	local t = new("owl", 2.3, 0.9, "biped")
	J("body", nil, V(0, 0.8, 0), "body")
	P("Body", "Ball", V(1.35, 1.45, 1.2), V(0, 0.95, 0), b)
	P("Belly", "Ball", V(0.9, 1.0, 0.3), V(0, 0.82, 0.5), "sand")
	for i = 0, 2 do
		P("Chevron", "Block", V(0.5, 0.125, 0.125), V(0, 0.55 + i * 0.25, 0.66), a)
	end
	J("head", "body", V(0, 1.45, 0), "head")
	P("Head", "Ball", V(1.25, 1.0, 1.1), V(0, 1.86, 0.05), b)
	P("DiscL", "Ball", V(0.55, 0.55, 0.15), V(-0.27, 1.86, 0.55), "cream")
	P("DiscR", "Ball", V(0.55, 0.55, 0.15), V(0.27, 1.86, 0.55), "cream")
	eyes(1.88, 0.64, 0.54, 0.28, a)
	P("Beak", "Wedge", V(0.2, 0.3, 0.2), V(0, 1.66, 0.66), "orange", CFrame.Angles(math.pi, math.pi, 0))
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ear" .. s, "head", V(side * 0.4, 2.25, 0), "ear", side)
		P("Tuft" .. s, "Block", V(0.25, 0.5, 0.25), V(side * 0.46, 2.45, 0), a, CFrame.Angles(0, 0, side * R(-15)))
		J("wing" .. s, "body", V(side * 0.6, 1.35, 0), "wing", side)
		P("Wing" .. s, "Block", V(0.25, 1.0, 0.875), V(side * 0.72, 0.95, -0.05), a)
		P("WingBar" .. s, "Block", V(0.26, 0.125, 0.625), V(side * 0.73, 1.1, -0.05), "cream")
		J("leg" .. s, "body", V(side * 0.3, 0.3, 0.1), "leg", side, if side < 0 then 0 else 0.5)
		P("Shin" .. s, "Block", V(0.25, 0.25, 0.25), V(side * 0.3, 0.2, 0.1), "cream")
		P("Talon" .. s, "Block", V(0.375, 0.125, 0.375), V(side * 0.3, 0.06, 0.25), "orange")
	end
	J("tail", "body", V(0, 0.5, -0.55), "tail", 0, 1)
	P("Tail", "Wedge", V(0.625, 0.25, 0.375), V(0, 0.45, -0.75), a)
	return t
end

-- a fox pup: a body with fluffy chest and haunches, a head with a snout, nose, a jaw (tongue on it) and tall ears
-- with dark tips, four legs on pale paws, a bushy tail in two parts with a white tip
PLANS.pup = function(b, a)
	local t = new("pup", 2.2, 1.1, "quad")
	J("body", nil, V(0, 0.85, 0), "body")
	P("Body", "Block", V(0.875, 0.75, 1.4), V(0, 0.85, -0.1), b)
	P("Haunch", "Ball", V(0.95, 0.8, 0.9), V(0, 0.85, -0.6), b)
	P("Chest", "Ball", V(0.7, 0.7, 0.4), V(0, 0.85, 0.6), a)
	legs4(0.3, 0.6, 0.4, -0.6, 0.3, b, "cream")
	J("head", "body", V(0, 1.15, 0.55), "head")
	P("Head", "Block", V(0.95, 0.85, 0.85), V(0, 1.5, 0.82), b)
	P("Snout", "Block", V(0.5, 0.375, 0.5), V(0, 1.33, 1.38), a)
	P("Nose", "Block", V(0.25, 0.125, 0.125), V(0, 1.47, 1.63), "black")
	eyes(1.62, 1.26, 0.5, 0.22)
	cheeks(1.4, 1.26, 0.78)
	J("jaw", "head", V(0, 1.2, 1.1), "jaw")
	P("Jaw", "Block", V(0.375, 0.125, 0.4), V(0, 1.12, 1.35), a)
	P("Tongue", "Block", V(0.25, 0.125, 0.25), V(0, 1.12, 1.48), "pink")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ear" .. s, "head", V(side * 0.3, 1.9, 0.75), "ear", side)
		P("Ear" .. s, "Block", V(0.3, 0.5, 0.2), V(side * 0.32, 2.15, 0.75), b, CFrame.Angles(0, 0, side * R(-10)))
		P("EarIn" .. s, "Block", V(0.125, 0.3, 0.125), V(side * 0.32, 2.12, 0.84), "pink", CFrame.Angles(0, 0, side * R(-10)))
		P("EarTip" .. s, "Block", V(0.25, 0.125, 0.2), V(side * 0.37, 2.42, 0.75), "black", CFrame.Angles(0, 0, side * R(-10)))
	end
	J("tail1", "body", V(0, 1.1, -0.8), "tail", 0, 1)
	P("Tail1", "Ball", V(0.5, 0.5, 0.875), V(0, 1.25, -1.15), b)
	J("tail2", "tail1", V(0, 1.35, -1.5), "tail", 0, 2)
	P("Tail2", "Ball", V(0.55, 0.55, 0.7), V(0, 1.5, -1.7), b)
	P("TailTip", "Ball", V(0.45, 0.45, 0.4), V(0, 1.6, -2.05), "white")
	return t
end

-- a mole: a round body with glowing stripes, a head with a pink snout and star nose, tiny eyes, whiskers and a jaw
-- with a tooth, big digging arms with pale claws, small hind feet, a short tail
PLANS.mole = function(b, a)
	local t = new("mole", 1.8, 1.1, "quad")
	J("body", nil, V(0, 0.75, 0), "body")
	P("Body", "Ball", V(1.7, 1.35, 1.9), V(0, 0.8, -0.1), b)
	P("Belly", "Ball", V(1.1, 0.8, 0.4), V(0, 0.65, 0.68), "sand")
	P("Stripe", "Block", V(0.25, 0.125, 1.0), V(0.45, 1.45, -0.25), a, nil, true)
	P("Stripe", "Block", V(0.25, 0.125, 0.75), V(-0.45, 1.4, -0.35), a, nil, true)
	P("Glow", "Block", V(0.5, 0.125, 0.5), V(0, 1.5, -0.6), a, nil, true)
	J("head", "body", V(0, 0.95, 0.6), "head")
	P("Head", "Ball", V(1.0, 0.875, 0.8), V(0, 1.05, 0.75), b)
	P("Snout", "Block", V(0.375, 0.375, 0.5), V(0, 0.95, 1.2), "pink")
	P("Nose", "Ball", V(0.375, 0.375, 0.25), V(0, 1.0, 1.45), "pink")
	eyes(1.25, 1.08, 0.46, 0.15)
	P("WhiskL", "Block", V(0.5, 0.125, 0.125), V(-0.42, 0.95, 1.2), "cream", CFrame.Angles(0, 0, R(10)))
	P("WhiskR", "Block", V(0.5, 0.125, 0.125), V(0.42, 0.95, 1.2), "cream", CFrame.Angles(0, 0, R(-10)))
	J("jaw", "head", V(0, 0.82, 1.0), "jaw")
	P("Jaw", "Block", V(0.3, 0.125, 0.3), V(0, 0.78, 1.2), "pink")
	P("Tooth", "Block", V(0.125, 0.25, 0.125), V(0.1, 0.8, 1.32), "white")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.75, 0.75, 0.5), "arm", side)
		P("Arm" .. s, "Block", V(0.4, 0.375, 0.4), V(side * 0.85, 0.52, 0.7), b)
		P("Palm" .. s, "Block", V(0.55, 0.15, 0.5), V(side * 0.9, 0.32, 0.9), a)
		for i, x in { 0.7, 0.9, 1.1 } do
			P("Talon" .. s .. i, "Block", V(0.125, 0.125, 0.25), V(side * x, 0.3, 1.18), "white")
		end
		J("leg" .. s, "body", V(side * 0.45, 0.4, -0.6), "leg", side, if side < 0 then 0.5 else 0)
		P("Foot" .. s, "Block", V(0.375, 0.2, 0.45), V(side * 0.5, 0.1, -0.5), "pink")
	end
	J("tail", "body", V(0, 0.6, -1.0), "tail", 0, 1)
	P("Tail", "Block", V(0.125, 0.125, 0.4), V(0, 0.55, -1.15), "pink")
	return t
end

-- a bat: a furry round body with a ruff, a head with huge ears, a pink nose and fangs on a jaw, wings in two
-- segments (bones and membrane: the outer one bends on), little feet hanging, a tuft
PLANS.bat = function(b, a)
	local t = new("bat", 2.4, 1.3, "fly")
	J("body", nil, V(0, 1.3, 0), "body")
	P("Body", "Ball", V(1.05, 1.1, 0.95), V(0, 1.3, 0), b)
	P("Belly", "Ball", V(0.6, 0.7, 0.25), V(0, 1.2, 0.42), "cream")
	P("Ruff", "Block", V(0.625, 0.25, 0.375), V(0, 1.72, 0.2), b)
	J("head", "body", V(0, 1.55, 0.1), "head")
	P("Head", "Ball", V(0.9, 0.8, 0.8), V(0, 1.88, 0.12), b)
	P("Tuft", "Block", V(0.375, 0.25, 0.25), V(0, 2.28, 0.05), b)
	P("Nose", "Block", V(0.25, 0.125, 0.125), V(0, 1.8, 0.52), "pink")
	eyes(1.95, 0.48, 0.4, 0.2)
	J("jaw", "head", V(0, 1.66, 0.35), "jaw")
	keep(P("Mouth", "Block", V(0.25, 0.125, 0.125), V(0, 1.66, 0.48), "black"))
	P("Fang", "Block", V(0.125, 0.2, 0.125), V(-0.1, 1.56, 0.47), "white")
	P("Fang", "Block", V(0.125, 0.2, 0.125), V(0.1, 1.56, 0.47), "white")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ear" .. s, "head", V(side * 0.25, 2.15, 0.05), "ear", side)
		P("Ear" .. s, "Block", V(0.3, 0.625, 0.2), V(side * 0.34, 2.45, 0.05), b, CFrame.Angles(0, 0, side * R(-15)))
		P("EarIn" .. s, "Block", V(0.125, 0.4, 0.125), V(side * 0.34, 2.43, 0.13), a, CFrame.Angles(0, 0, side * R(-15)))
		J("wing" .. s, "body", V(side * 0.45, 1.45, -0.05), "wing", side)
		P("WingBone" .. s, "Block", V(0.875, 0.125, 0.125), V(side * 0.9, 1.65, -0.05), b)
		P("Wing" .. s, "Block", V(0.875, 0.7, 0.125), V(side * 0.95, 1.3, -0.07), a)
		J("wing" .. s .. "2", "wing" .. s, V(side * 1.35, 1.62, -0.05), "wing", side, 1)
		P("WingTip" .. s, "Block", V(0.625, 0.625, 0.125), V(side * 1.65, 1.35, -0.07), a)
		P("Finger" .. s, "Block", V(0.125, 0.75, 0.125), V(side * 1.38, 1.3, -0.03), b)
		P("Finger" .. s, "Block", V(0.125, 0.625, 0.125), V(side * 1.8, 1.35, -0.03), b)
		P("Hook" .. s, "Block", V(0.125, 0.25, 0.125), V(side * 1.35, 1.78, -0.03), "cream")
		J("leg" .. s, "body", V(side * 0.2, 0.9, 0), "leg", side, if side < 0 then 0 else 0.5)
		P("Foot" .. s, "Block", V(0.2, 0.3, 0.2), V(side * 0.2, 0.72, 0), a)
	end
	return t
end

-- a yeti: a big furry body with shoulder tufts and a pale belly, a head with a coloured face, horns, brows and a
-- toothy mouth on a jaw, long arms with big hands, short legs on wide feet
PLANS.yeti = function(b, a)
	local t = new("yeti", 2.6, 1.2, "biped")
	J("body", nil, V(0, 1.0, 0), "body")
	P("Body", "Ball", V(1.8, 1.8, 1.6), V(0, 1.15, 0), b)
	P("Belly", "Ball", V(1.0, 0.9, 0.3), V(0, 0.95, 0.72), "cream")
	P("Fur", "Block", V(0.375, 0.375, 0.375), V(-0.75, 1.9, 0), b)
	P("Fur", "Block", V(0.375, 0.375, 0.375), V(0.75, 1.9, 0), b)
	P("Snow", "Block", V(0.5, 0.125, 0.375), V(-0.5, 0.6, 0.75), "window")
	J("head", "body", V(0, 1.6, 0.2), "head")
	P("Head", "Ball", V(1.2, 1.0, 1.0), V(0, 2.02, 0.25), b)
	P("Face", "Block", V(0.875, 0.625, 0.2), V(0, 1.92, 0.72), a)
	P("Tuft", "Block", V(0.5, 0.375, 0.5), V(0.15, 2.48, 0.15), b)
	eyes(2.02, 0.84, 0.42, 0.2, b)
	P("HornL", "Block", V(0.2, 0.45, 0.2), V(-0.42, 2.55, 0.15), a, CFrame.Angles(0, 0, R(25)))
	P("HornR", "Block", V(0.2, 0.45, 0.2), V(0.42, 2.55, 0.15), a, CFrame.Angles(0, 0, R(-25)))
	J("jaw", "head", V(0, 1.78, 0.5), "jaw")
	keep(P("Mouth", "Block", V(0.4, 0.125, 0.125), V(0, 1.72, 0.84), "black"))
	P("Tooth", "Block", V(0.125, 0.125, 0.125), V(-0.15, 1.8, 0.86), "white")
	P("Tooth", "Block", V(0.125, 0.125, 0.125), V(0.15, 1.8, 0.86), "white")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.9, 1.6, 0.05), "arm", side)
		P("Arm" .. s, "Block", V(0.45, 1.0, 0.45), V(side * 1.05, 1.12, 0.1), b)
		P("Hand" .. s, "Block", V(0.5, 0.375, 0.5), V(side * 1.08, 0.5, 0.15), a)
		J("leg" .. s, "body", V(side * 0.45, 0.45, 0), "leg", side, if side < 0 then 0 else 0.5)
		P("Leg" .. s, "Block", V(0.5, 0.45, 0.5), V(side * 0.45, 0.25, 0.05), b)
		P("Foot" .. s, "Block", V(0.55, 0.15, 0.625), V(side * 0.45, 0.07, 0.15), a)
	end
	return t
end

-- a seal: a plump body with a pale belly and spots, a head with a muzzle, nose, whiskers and brow spots and a jaw,
-- front flippers, a tail with two flukes
PLANS.seal = function(b, a)
	local t = new("seal", 1.6, 1.2, "slither")
	J("body", nil, V(0, 0.5, 0), "body")
	P("Body", "Ball", V(1.15, 0.95, 1.9), V(0, 0.5, -0.15), b)
	P("Belly", "Ball", V(0.8, 0.6, 1.3), V(0, 0.38, 0.15), a)
	P("Spot", "Block", V(0.3, 0.125, 0.3), V(0.3, 0.95, -0.4), a)
	P("Spot", "Block", V(0.25, 0.125, 0.25), V(-0.3, 0.93, -0.7), a)
	J("head", "body", V(0, 0.8, 0.55), "head")
	P("Head", "Ball", V(1.0, 0.95, 0.95), V(0, 1.15, 0.75), b)
	P("Muzzle", "Ball", V(0.55, 0.375, 0.375), V(0, 1.0, 1.18), a)
	P("Nose", "Block", V(0.25, 0.125, 0.125), V(0, 1.1, 1.34), "black")
	eyes(1.3, 1.18, 0.44, 0.22)
	P("BrowL", "Block", V(0.125, 0.125, 0.125), V(-0.24, 1.52, 1.1), a)
	P("BrowR", "Block", V(0.125, 0.125, 0.125), V(0.24, 1.52, 1.1), a)
	P("WhiskL", "Block", V(0.5, 0.125, 0.125), V(-0.38, 1.02, 1.3), "black", CFrame.Angles(0, 0, R(8)))
	P("WhiskR", "Block", V(0.5, 0.125, 0.125), V(0.38, 1.02, 1.3), "black", CFrame.Angles(0, 0, R(-8)))
	J("jaw", "head", V(0, 0.92, 1.0), "jaw")
	keep(P("Mouth", "Block", V(0.25, 0.125, 0.125), V(0, 0.9, 1.3), "black"))
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("fin" .. s, "body", V(side * 0.55, 0.45, 0.45), "fin", side)
		P("Flipper" .. s, "Block", V(0.55, 0.15, 0.4), V(side * 0.8, 0.2, 0.55), a, CFrame.Angles(0, side * R(-20), 0))
	end
	J("tail", "body", V(0, 0.4, -0.95), "tail", 0, 1)
	P("Tail", "Ball", V(0.7, 0.5, 0.7), V(0, 0.3, -1.2), b)
	P("FlukeL", "Block", V(0.45, 0.125, 0.375), V(-0.3, 0.12, -1.6), a, CFrame.Angles(0, R(20), 0))
	P("FlukeR", "Block", V(0.45, 0.125, 0.375), V(0.3, 0.12, -1.6), a, CFrame.Angles(0, R(-20), 0))
	return t
end

-- a sprite: a glowing gem body floating over a point, a crystal crown, little wings, shard arms, sparkles
PLANS.sprite = function(b, a)
	local t = new("sprite", 2.4, 0.9, "fly")
	J("body", nil, V(0, 1.3, 0), "body")
	P("Core", "Block", V(0.875, 0.875, 0.875), V(0, 1.28, 0), b, CFrame.Angles(0, R(45), 0), true)
	P("Point", "Block", V(0.45, 0.5, 0.45), V(0, 0.62, 0), b, CFrame.Angles(0, R(45), 0), true)
	P("Belt", "Block", V(0.9, 0.125, 0.9), V(0, 1.02, 0), a, CFrame.Angles(0, R(45), 0))
	eyes(1.38, 0.64, 0.36, 0.2)
	mouth(1.15, 0.64, 0.25)
	P("Sparkle", "Block", V(0.125, 0.125, 0.125), V(0.9, 1.6, 0.2), "white", nil, true)
	P("Sparkle", "Block", V(0.125, 0.125, 0.125), V(-0.85, 1.6, -0.2), "white", nil, true)
	P("Sparkle", "Block", V(0.125, 0.125, 0.125), V(0.3, 2.45, 0.1), "white", nil, true)
	J("head", "body", V(0, 1.7, 0), "head")
	P("Crown", "Block", V(0.5, 0.5, 0.5), V(0, 2.02, 0), a, CFrame.Angles(R(45), 0, R(45)), true)
	P("CrownTip", "Block", V(0.2, 0.375, 0.2), V(-0.3, 2.2, 0), a, CFrame.Angles(0, 0, R(30)), true)
	P("CrownTip", "Block", V(0.2, 0.375, 0.2), V(0.3, 2.2, 0), a, CFrame.Angles(0, 0, R(-30)), true)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("wing" .. s, "body", V(side * 0.35, 1.45, -0.2), "wing", side)
		P("Wing" .. s, "Block", V(0.75, 0.625, 0.125), V(side * 0.72, 1.62, -0.25), "white", CFrame.Angles(0, 0, side * R(20)))
		P("WingLow" .. s, "Block", V(0.5, 0.375, 0.125), V(side * 0.6, 1.15, -0.25), a, CFrame.Angles(0, 0, side * R(-15)))
		J("arm" .. s, "body", V(side * 0.45, 1.35, 0), "arm", side)
		P("Shard" .. s, "Block", V(0.25, 0.55, 0.25), V(side * 0.75, 1.15, 0.05), a, nil, true)
	end
	return t
end

-- a jellyfish: a glowing bell with a top and a scalloped rim, a face and freckles, six tendrils in two segments
PLANS.jelly = function(b, a)
	local t = new("jelly", 2.6, 1, "fly")
	J("body", nil, V(0, 1.5, 0), "body")
	P("Bell", "Ball", V(1.8, 1.35, 1.8), V(0, 1.85, 0), b, nil, true)
	P("BellTop", "Ball", V(1.1, 0.625, 1.1), V(0, 2.4, 0), b, nil, true)
	for i = 0, 7 do
		local ang = i / 8 * math.pi * 2
		P("Scallop", "Block", V(0.45, 0.25, 0.25), V(math.sin(ang) * 0.82, 1.2, math.cos(ang) * 0.82), a, CFrame.Angles(0, ang, 0))
	end
	eyes(1.85, 0.88, 0.55, 0.22)
	mouth(1.6, 0.9, 0.25)
	cheeks(1.68, 0.86, 0.85)
	P("Freckle", "Block", V(0.25, 0.25, 0.125), V(0.45, 2.25, 0.8), "white", nil, true)
	P("Freckle", "Block", V(0.125, 0.125, 0.125), V(-0.5, 2.35, 0.76), "white", nil, true)
	for i, p in { { -0.5, 0.3 }, { 0, 0.45 }, { 0.5, 0.3 }, { -0.45, -0.35 }, { 0.05, -0.45 }, { 0.5, -0.3 } } do
		local x, z = p[1], p[2]
		J("tendril" .. i, "body", V(x, 1.2, z), "tendril", 0, i)
		P("Tendril" .. i, "Block", V(0.2, 0.6, 0.2), V(x, 0.88, z), a)
		J("tendril" .. i .. "b", "tendril" .. i, V(x, 0.58, z), "tendril", 0, i + 0.5)
		P("TendrilEnd" .. i, "Block", V(0.125, 0.5, 0.125), V(x, 0.33, z), a)
	end
	return t
end

-- a sea serpent: two coils of its body, a neck with a pale throat, a head with a snout, horns, a glowing crest,
-- brows and a toothed jaw, fins along its back, a tail with a fin
PLANS.wyrm = function(b, a)
	local t = new("wyrm", 2.9, 1.6, "slither")
	J("body", nil, V(0, 0.5, -0.6), "body")
	P("Coil", "Ball", V(1.2, 0.95, 1.2), V(0.55, 0.5, -1.1), b)
	P("Coil", "Ball", V(1.3, 1.05, 1.3), V(-0.35, 0.6, -0.3), b)
	P("CoilBelly", "Block", V(0.875, 0.5, 0.2), V(-0.35, 0.55, 0.35), a)
	J("fin", "body", V(-0.35, 1.05, -0.3), "fin", 0)
	P("BackFin", "Block", V(0.125, 0.5, 0.625), V(-0.35, 1.3, -0.35), a, nil, true)
	J("tail1", "body", V(0.9, 0.45, -1.5), "tail", 0, 1)
	P("Tail1", "Block", V(0.45, 0.375, 0.875), V(1.15, 0.35, -1.9), b)
	J("tail2", "tail1", V(1.2, 0.3, -2.3), "tail", 0, 2)
	P("TailFin", "Block", V(0.75, 0.125, 0.5), V(1.25, 0.3, -2.5), a, CFrame.Angles(0, R(30), 0))
	J("neck", "body", V(0, 0.9, 0.3), "neck")
	P("Neck", "Block", V(0.75, 1.3, 0.75), V(0, 1.4, 0.55), b)
	P("Throat", "Block", V(0.55, 1.0, 0.2), V(0, 1.35, 0.92), a)
	J("head", "neck", V(0, 2.0, 0.75), "head")
	P("Head", "Block", V(1.0, 0.75, 1.1), V(0, 2.3, 0.95), b)
	P("Snout", "Block", V(0.75, 0.5, 0.625), V(0, 2.2, 1.6), b)
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(-0.2, 2.42, 1.88), "black")
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(0.2, 2.42, 1.88), "black")
	eyes(2.45, 1.47, 0.62, 0.22, a)
	P("HornL", "Block", V(0.2, 0.5, 0.2), V(-0.35, 2.8, 0.6), "white", CFrame.Angles(R(-30), 0, R(15)))
	P("HornR", "Block", V(0.2, 0.5, 0.2), V(0.35, 2.8, 0.6), "white", CFrame.Angles(R(-30), 0, R(-15)))
	P("Crest", "Block", V(0.125, 0.5, 0.75), V(0, 2.85, 0.85), a, nil, true)
	J("jaw", "head", V(0, 2.0, 1.1), "jaw")
	P("Jaw", "Block", V(0.7, 0.25, 0.875), V(0, 1.9, 1.5), a)
	P("Tooth", "Block", V(0.125, 0.2, 0.125), V(-0.22, 2.06, 1.84), "white")
	P("Tooth", "Block", V(0.125, 0.2, 0.125), V(0.22, 2.06, 1.84), "white")
	return t
end

-- a snail: a long foot, a spiral shell (rings on both sides), a head with a smile and eyes on two stalks, feelers
PLANS.snail = function(b, a)
	local t = new("snail", 2.0, 1.1, "slither")
	J("body", nil, V(0, 0.3, 0), "body")
	P("Foot", "Block", V(0.875, 0.45, 2.0), V(0, 0.25, 0.05), b)
	P("Skirt", "Block", V(0.95, 0.125, 2.1), V(0, 0.06, 0.05), b)
	J("shell", "body", V(0, 0.55, -0.25), "shell")
	P("Shell", "Ball", V(1.35, 1.45, 1.35), V(0, 1.2, -0.3), a)
	for _, side in { -1, 1 } do
		P("Spiral", "Ball", V(0.2, 0.875, 0.875), V(side * 0.62, 1.22, -0.3), b)
		P("Spiral", "Ball", V(0.15, 0.5, 0.5), V(side * 0.72, 1.25, -0.28), a)
		P("Spiral", "Ball", V(0.125, 0.25, 0.25), V(side * 0.78, 1.27, -0.26), b)
	end
	J("head", "body", V(0, 0.5, 0.85), "head")
	P("Head", "Ball", V(0.75, 0.75, 0.75), V(0, 0.75, 1.0), b)
	mouth(0.66, 1.36, 0.25)
	cheeks(0.76, 1.32, 0.5)
	P("Feeler", "Block", V(0.125, 0.25, 0.125), V(-0.15, 0.9, 1.3), b)
	P("Feeler", "Block", V(0.125, 0.25, 0.125), V(0.15, 0.9, 1.3), b)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("stalk" .. s, "head", V(side * 0.18, 1.0, 1.05), "stalk", side)
		P("Stalk" .. s, "Block", V(0.125, 0.625, 0.125), V(side * 0.2, 1.3, 1.08), b)
		P("EyeBall" .. s, "Ball", V(0.3, 0.3, 0.3), V(side * 0.2, 1.65, 1.1), b)
		eye(s, V(side * 0.2, 1.66, 1.24), 0.2)
	end
	return t
end

-- a turtle: a domed shell with a ring of plates round a middle one and a rim, a pale belly plate, a head on a neck
-- with a beak and a jaw, four flippered legs with pale claws, a stubby tail
PLANS.turtle = function(b, a)
	local t = new("turtle", 1.7, 1.2, "quad")
	J("body", nil, V(0, 0.6, 0), "body")
	P("Shell", "Ball", V(1.9, 1.2, 2.1), V(0, 0.95, -0.05), a)
	P("Rim", "Block", V(1.75, 0.25, 1.95), V(0, 0.5, -0.05), b)
	P("Plastron", "Block", V(1.375, 0.25, 1.6), V(0, 0.38, 0), "cream")
	P("Plate", "Block", V(0.625, 0.125, 0.625), V(0, 1.56, -0.05), b)
	for _, p in { { -0.55, 1.36, 0.35 }, { 0.55, 1.36, 0.35 }, { -0.55, 1.36, -0.45 }, { 0.55, 1.36, -0.45 }, { 0, 1.4, 0.62 }, { 0, 1.4, -0.75 } } do
		P("Plate", "Block", V(0.45, 0.125, 0.45), V(p[1], p[2], p[3]), b)
	end
	J("head", "body", V(0, 0.7, 0.95), "head")
	P("Neck", "Block", V(0.5, 0.45, 0.5), V(0, 0.7, 1.12), b)
	P("Head", "Ball", V(0.8, 0.7, 0.875), V(0, 0.86, 1.45), b)
	eyes(0.98, 1.8, 0.42, 0.2)
	cheeks(0.82, 1.82, 0.56)
	P("Beak", "Wedge", V(0.375, 0.2, 0.25), V(0, 0.82, 1.92), a, CFrame.Angles(0, math.pi, 0))
	J("jaw", "head", V(0, 0.68, 1.6), "jaw")
	P("Jaw", "Block", V(0.375, 0.125, 0.3), V(0, 0.66, 1.8), b)
	for _, l in { { n = "FL", s = -1, z = 0.6, ph = 0 }, { n = "FR", s = 1, z = 0.6, ph = 0.5 }, { n = "BL", s = -1, z = -0.65, ph = 0.5 }, { n = "BR", s = 1, z = -0.65, ph = 0 } } do
		local side, z = l.s, l.z
		J("leg" .. l.n, "body", V(side * 0.6, 0.45, z), "leg", side, l.ph)
		P("Leg" .. l.n, "Block", V(0.45, 0.375, 0.5), V(side * 0.78, 0.22, z + 0.1), b)
		P("Claw" .. l.n, "Block", V(0.375, 0.125, 0.2), V(side * 0.82, 0.07, z + 0.38), "cream")
	end
	J("tail", "body", V(0, 0.5, -1.1), "tail", 0, 1)
	P("Tail", "Wedge", V(0.25, 0.2, 0.4), V(0, 0.42, -1.3), b)
	return t
end

-- a frog: a squat body with a pale belly and spots, a wide head with eyes bulging on top, a mouth line and a lower
-- jaw that drops, front arms on splayed hands, folded hind legs on long webbed feet
PLANS.frog = function(b, a)
	local t = new("frog", 1.6, 1.1, "hop")
	J("body", nil, V(0, 0.5, 0), "body")
	P("Body", "Ball", V(1.6, 0.95, 1.5), V(0, 0.6, -0.1), b)
	P("Belly", "Ball", V(1.1, 0.6, 0.4), V(0, 0.48, 0.55), "cream")
	P("Spot", "Block", V(0.3, 0.125, 0.3), V(-0.35, 1.05, -0.3), a)
	P("Spot", "Block", V(0.25, 0.125, 0.25), V(0.4, 1.0, -0.45), a)
	P("Spot", "Block", V(0.25, 0.125, 0.25), V(0.05, 1.08, -0.6), a)
	J("head", "body", V(0, 0.75, 0.4), "head")
	P("Head", "Ball", V(1.5, 0.75, 1.0), V(0, 0.95, 0.45), b)
	P("BumpL", "Ball", V(0.55, 0.55, 0.55), V(-0.45, 1.32, 0.55), b)
	P("BumpR", "Ball", V(0.55, 0.55, 0.55), V(0.45, 1.32, 0.55), b)
	eye("L", V(-0.45, 1.36, 0.82), 0.25)
	eye("R", V(0.45, 1.36, 0.82), 0.25)
	keep(P("Lip", "Block", V(1.0, 0.125, 0.125), V(0, 0.8, 0.95), "black"))
	cheeks(0.92, 0.92, 1.1)
	J("jaw", "head", V(0, 0.75, 0.3), "jaw")
	P("Jaw", "Block", V(1.1, 0.2, 0.75), V(0, 0.68, 0.62), b)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.55, 0.45, 0.5), "arm", side)
		P("Arm" .. s, "Block", V(0.25, 0.375, 0.25), V(side * 0.6, 0.25, 0.65), b)
		P("Hand" .. s, "Block", V(0.4, 0.125, 0.375), V(side * 0.65, 0.06, 0.8), a)
		J("leg" .. s, "body", V(side * 0.6, 0.45, -0.35), "leg", side, 0)
		P("Thigh" .. s, "Ball", V(0.6, 0.5, 0.8), V(side * 0.75, 0.35, -0.35), b)
		P("Foot" .. s, "Block", V(0.5, 0.125, 0.625), V(side * 0.82, 0.06, 0.05), a)
	end
	return t
end

-- a moth: a fuzzy thorax with a pale ruff and a banded abdomen, a head with feathery antennae, two pairs of wings
-- with eye spots and pale edges, little legs
PLANS.moth = function(b, a)
	local t = new("moth", 2.4, 1.4, "fly")
	J("body", nil, V(0, 1.1, 0), "body")
	P("Thorax", "Ball", V(0.8, 0.8, 0.8), V(0, 1.2, 0.1), b)
	P("Ruff", "Ball", V(0.875, 0.375, 0.625), V(0, 1.5, 0.22), "cream")
	P("Abdomen", "Ball", V(0.625, 0.625, 1.0), V(0, 0.95, -0.55), b)
	P("Band", "Block", V(0.65, 0.125, 0.2), V(0, 0.98, -0.45), a)
	P("Band", "Block", V(0.55, 0.125, 0.2), V(0, 0.92, -0.78), a)
	P("Leg", "Block", V(0.125, 0.3, 0.125), V(-0.2, 0.72, 0.25), b)
	P("Leg", "Block", V(0.125, 0.3, 0.125), V(0.2, 0.72, 0.25), b)
	J("head", "body", V(0, 1.4, 0.4), "head")
	P("Head", "Ball", V(0.7, 0.625, 0.625), V(0, 1.66, 0.55), b)
	eyes(1.7, 0.84, 0.36, 0.22)
	mouth(1.52, 0.85, 0.125)
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("ant" .. s, "head", V(side * 0.15, 1.9, 0.6), "antenna", side)
		P("Ant" .. s, "Block", V(0.125, 0.625, 0.125), V(side * 0.22, 2.16, 0.65), b, CFrame.Angles(R(-15), 0, side * R(-15)))
		P("AntFeather" .. s, "Block", V(0.3, 0.375, 0.125), V(side * 0.32, 2.4, 0.6), a, CFrame.Angles(0, 0, side * R(-15)))
		J("wing" .. s, "body", V(side * 0.3, 1.35, 0), "wing", side)
		P("Wing" .. s, "Block", V(0.875, 0.875, 0.125), V(side * 0.75, 1.5, -0.05), a)
		P("WingEdge" .. s, "Block", V(0.875, 0.125, 0.15), V(side * 0.75, 1.92, -0.05), "cream")
		P("WingSpot" .. s, "Block", V(0.375, 0.375, 0.15), V(side * 0.85, 1.55, -0.05), b)
		P("WingDot" .. s, "Block", V(0.125, 0.125, 0.16), V(side * 0.85, 1.55, -0.05), "white")
		P("WingLow" .. s, "Block", V(0.625, 0.55, 0.125), V(side * 0.6, 0.9, -0.15), a)
	end
	return t
end

-- a golem: a blocky stone torso with a chest plate, a glowing gem core and runes, a belt, a head with a heavy brow,
-- glowing slit eyes and a mouth line, big shoulders and arms with fists, short legs on wide feet
PLANS.golem = function(b, a)
	local t = new("golem", 2.6, 1.3, "biped")
	J("body", nil, V(0, 1.0, 0), "body")
	P("Torso", "Block", V(1.4, 1.1, 1.0), V(0, 1.15, 0), b)
	P("ChestPlate", "Block", V(1.0, 0.625, 0.15), V(0, 1.25, 0.55), a)
	P("Core", "Ball", V(0.45, 0.45, 0.2), V(0, 1.22, 0.64), a, nil, true)
	P("Belt", "Block", V(1.45, 0.25, 1.05), V(0, 0.65, 0), a)
	P("Rune", "Block", V(0.125, 0.375, 0.125), V(0.45, 1.4, 0.52), a, nil, true)
	P("Rune", "Block", V(0.25, 0.125, 0.125), V(-0.45, 0.95, 0.52), a, nil, true)
	P("Moss", "Block", V(0.5, 0.125, 0.5), V(-0.35, 1.75, -0.2), "leaf")
	J("head", "body", V(0, 1.7, 0), "head")
	P("Head", "Block", V(0.875, 0.625, 0.8), V(0, 2.0, 0.05), b)
	P("Brow", "Block", V(0.95, 0.2, 0.25), V(0, 2.25, 0.38), a)
	keep(P("EyeL", "Block", V(0.25, 0.15, 0.125), V(-0.22, 2.05, 0.46), a, nil, true))
	keep(P("EyeR", "Block", V(0.25, 0.15, 0.125), V(0.22, 2.05, 0.46), a, nil, true))
	keep(P("Mouth", "Block", V(0.375, 0.125, 0.125), V(0, 1.82, 0.46), "black"))
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("arm" .. s, "body", V(side * 0.75, 1.55, 0), "arm", side)
		P("Shoulder" .. s, "Block", V(0.625, 0.5, 0.625), V(side * 0.95, 1.55, 0), a)
		P("Arm" .. s, "Block", V(0.5, 0.75, 0.5), V(side * 1.0, 1.0, 0.05), b)
		P("Fist" .. s, "Block", V(0.625, 0.5, 0.625), V(side * 1.02, 0.5, 0.1), a)
		J("leg" .. s, "body", V(side * 0.35, 0.55, 0), "leg", side, if side < 0 then 0 else 0.5)
		P("Leg" .. s, "Block", V(0.5, 0.45, 0.55), V(side * 0.38, 0.3, 0), b)
		P("Foot" .. s, "Block", V(0.625, 0.2, 0.75), V(side * 0.38, 0.1, 0.1), a)
	end
	return t
end

-- a drake: a body with a pale belly and spikes down its back, a neck and head with a snout, nostrils, horns swept
-- back, brows and a toothed jaw, wings in two segments (a bone with a claw, membrane), a tail in two parts ending in
-- a spade, four legs on pale claws
PLANS.drake = function(b, a)
	local t = new("drake", 2.6, 1.4, "quad")
	J("body", nil, V(0, 0.9, 0), "body")
	P("Body", "Ball", V(1.2, 1.0, 1.7), V(0, 0.95, -0.1), b)
	P("Belly", "Ball", V(0.8, 0.7, 1.2), V(0, 0.75, 0.15), "cream")
	for i = 0, 2 do
		P("Spike", "Block", V(0.125, 0.3, 0.3), V(0, 1.48, 0.3 - i * 0.4), a, CFrame.Angles(R(-30), 0, 0))
	end
	legs4(0.35, 0.7, 0.4, -0.55, 0.3, b, "cream")
	J("head", "body", V(0, 1.25, 0.6), "head")
	P("Neck", "Block", V(0.55, 0.7, 0.55), V(0, 1.45, 0.75), b)
	P("Head", "Block", V(0.8, 0.625, 0.8), V(0, 1.95, 0.95), b)
	P("Snout", "Block", V(0.625, 0.4, 0.55), V(0, 1.85, 1.5), b)
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(-0.16, 2.0, 1.76), "black")
	P("Nostril", "Block", V(0.125, 0.125, 0.125), V(0.16, 2.0, 1.76), "black")
	eyes(2.08, 1.36, 0.5, 0.22, a)
	P("HornL", "Block", V(0.15, 0.5, 0.15), V(-0.28, 2.4, 0.72), a, CFrame.Angles(R(-35), 0, R(10)))
	P("HornR", "Block", V(0.15, 0.5, 0.15), V(0.28, 2.4, 0.72), a, CFrame.Angles(R(-35), 0, R(-10)))
	J("jaw", "head", V(0, 1.72, 1.15), "jaw")
	P("Jaw", "Block", V(0.5, 0.2, 0.625), V(0, 1.65, 1.45), a)
	P("Tooth", "Block", V(0.125, 0.125, 0.125), V(-0.18, 1.78, 1.72), "white")
	P("Tooth", "Block", V(0.125, 0.125, 0.125), V(0.18, 1.78, 1.72), "white")
	for _, side in { -1, 1 } do
		local s = if side < 0 then "L" else "R"
		J("wing" .. s, "body", V(side * 0.4, 1.4, -0.1), "wing", side)
		P("WingBone" .. s, "Block", V(0.875, 0.15, 0.15), V(side * 0.8, 1.65, -0.1), b)
		P("Wing" .. s, "Block", V(0.875, 0.75, 0.125), V(side * 0.85, 1.3, -0.2), a)
		J("wing" .. s .. "2", "wing" .. s, V(side * 1.25, 1.65, -0.1), "wing", side, 1)
		P("WingTip" .. s, "Block", V(0.7, 0.625, 0.125), V(side * 1.6, 1.4, -0.2), a)
		P("WingClaw" .. s, "Block", V(0.125, 0.25, 0.125), V(side * 1.25, 1.8, -0.1), "cream")
	end
	J("tail1", "body", V(0, 0.85, -0.9), "tail", 0, 1)
	P("Tail1", "Block", V(0.45, 0.4, 0.8), V(0, 0.75, -1.25), b)
	J("tail2", "tail1", V(0, 0.7, -1.6), "tail", 0, 2)
	P("Tail2", "Block", V(0.3, 0.3, 0.7), V(0, 0.62, -1.9), b)
	P("TailSpade", "Block", V(0.45, 0.125, 0.45), V(0, 0.62, -2.35), a, CFrame.Angles(0, R(45), 0))
	return t
end

------------------------------------------------------------------ build
function DriftModels.has(shape: string): boolean
	return PLANS[shape] ~= nil
end

function DriftModels.build(shape: string, body: string, accent: string): Thing
	local fn = PLANS[shape] or PLANS.blob
	local t = fn(body, accent)
	cur = nil
	return t
end

------------------------------------------------------------------ animate
local function wave(x: number): number
	return math.sin(x)
end

-- The joints' turns for the moment, then every part's rest pose (times the squash `sc`), and the eyes' and mouth's
-- sizes. `time` in seconds (already offset per driftling), `k` 0..1 an attack's progress.
function DriftModels.animate(t: Thing, time: number, mood: string, k: number?, sc: Vector3)
	local rig = t.rig
	if rig == nil then
		return
	end
	local kk = math.clamp(k or 0, 0, 1)
	local fight = mood == "attack"
	local lunge = if fight then math.sin(kk * math.pi) else 0
	local windup = fight and kk < 0.02
	local cheer = mood == "cheer"
	local walk = mood == "walk"
	local hurt = mood == "hurt"
	local ko = mood == "ko"
	local excited = fight or cheer
	local gait = rig.gait
	local fly = gait == "fly"
	local step = time * 9 -- the walk's beat
	local blink = (time % 3.4) < 0.12
	-- now and then the head turns to look about, holds, and comes back
	local lookPhase = time % 6
	local look = if lookPhase < 1.6 then math.sin(lookPhase / 1.6 * math.pi) * (if math.floor(time / 6) % 2 == 0 then 1 else -1) else 0
	local world = rig.world
	for _, name in rig.order do
		local j = rig.joints[name]
		local side, ph = j.side, j.phase
		local rx, ry, rz = 0, 0, 0
		local tx, ty, tz = 0, 0, 0
		local kind = j.kind
		if kind == "body" then
			if fly then
				ty = 0.15 * wave(time * 2.2) + (if excited then 0.1 * wave(time * 9) else 0)
			else
				ty = 0.04 * wave(time * 2.4)
			end
			rz = R(2) * wave(time * 1.1)
			if walk then
				if gait == "hop" then
					local up = math.max(0, wave(step))
					ty += 0.3 * up
					rx = R(-10) * up
				elseif gait == "slither" then
					rz = R(6) * wave(step * 0.6)
					ty = 0
				else
					ty += 0.08 * math.abs(wave(step))
					rx = R(6)
				end
			end
			if fight then
				-- (the battle screen leans and squashes the whole thing too: the body adds only a little)
				rx = if windup then R(-8) else R(8) * lunge
				tz = 0.15 * lunge
			elseif hurt then
				rx = R(-16)
				rz = R(6) * wave(time * 40)
			elseif cheer then
				rx = R(-8)
				ry = R(10) * wave(time * 10)
			end
		elseif kind == "head" or kind == "neck" then
			local amp = if kind == "neck" then 0.5 else 1
			ry = R(14) * look * amp
			rx = R(4) * wave(time * 1.3 + 0.5) * amp
			if walk then
				rx = R(6) * wave(step * 2) * amp
				ry = 0
			end
			if fight then
				rx = (if windup then R(-12) else R(12) * lunge) * amp
				ry = 0
				tz = 0.18 * lunge * amp
			elseif hurt then
				rx = R(-24) * amp
				ry = R(16) * amp
			elseif cheer then
				rx = R(-16) * amp
				rz = R(10) * wave(time * 10) * amp
				ry = 0
			elseif ko then
				rx = R(30) * amp
				rz = R(15) * amp
				ry = 0
			end
		elseif kind == "jaw" then
			local open = 0
			if fight then
				open = if windup then R(10) else R(30) * lunge
			elseif cheer then
				open = R(14) + R(12) * wave(time * 10)
			elseif hurt then
				open = R(30)
			elseif ko then
				open = R(10)
			else
				-- a yawn now and then
				local yp = time % 9
				open = if yp < 0.7 then R(20) * math.sin(yp / 0.7 * math.pi) else 0
			end
			rx = open
		elseif kind == "ear" then
			local twitch = (time + side * 0.7) % 2.6 < 0.15
			local a = 0
			if hurt or ko then
				a = R(40)
			elseif cheer then
				a = R(10) * wave(time * 12)
			elseif twitch then
				a = R(18)
			elseif walk then
				a = R(6) * wave(step * 2)
			end
			rz = -side * a
		elseif kind == "arm" then
			local swing = R(6) * wave(time * 2 + side)
			if walk then
				swing = R(25) * wave(step + (if side > 0 then math.pi else 0))
			end
			rx = swing
			if fight then
				rx = if windup then R(30) else R(-110) * lunge
			elseif cheer then
				rx = R(-150)
				rz = -side * R(15) * wave(time * 10)
			elseif hurt then
				rx = R(-60) + R(10) * wave(time * 30)
				rz = -side * R(25)
			elseif ko then
				rx = R(-20)
			end
		elseif kind == "leg" then
			if walk then
				if gait == "hop" then
					rx = R(-35) * math.max(0, wave(step))
				elseif gait == "scuttle" then
					local s = wave(step * 1.5 + ph * math.pi * 2)
					rz = side * R(14) * s
					ty = 0.06 * math.max(0, s)
				else
					local s = wave(step + ph * math.pi * 2)
					rx = R(28) * s
					ty = 0.08 * math.max(0, s)
				end
			elseif fly then
				rx = R(10) * wave(time * 3 + side)
			elseif cheer then
				ty = 0.1 * math.max(0, wave(time * 16 + ph * math.pi * 2))
			elseif fight then
				rx = R(-10) * lunge
			elseif ko then
				rx = R(20)
			end
		elseif kind == "tail" then
			local amp, f = R(10), 3
			if walk then
				amp, f = R(20), 9
			end
			if excited then
				amp, f = R(30), 16
			end
			-- (each segment adds to the one before: the later ones swing less, so the tip doesn't whip round)
			local seg = if ph >= 2 then 0.5 else 1
			ry = amp * seg * wave(time * f - ph * 0.8)
			if fight then
				rx = R(10) * lunge * seg
			elseif hurt then
				rx = R(-12) * seg
			elseif ko then
				ry = 0
				rx = R(-10)
			end
		elseif kind == "wing" then
			local flap
			local wseg = if ph >= 1 then 0.6 else 1 -- (the outer segment of a wing bends on a little more)
			if fly then
				flap = R(if excited then 40 else 28) * wseg * wave(time * (if excited then 20 else 11) - ph * 0.6)
			elseif excited then
				flap = R(35) * wseg * wave(time * 20 - ph * 0.6)
			elseif walk then
				flap = R(10) * wave(step)
			else
				flap = R(6) * wave(time * 3 - ph * 0.6)
			end
			if hurt then
				flap = R(35)
			elseif ko then
				flap = R(-20)
			end
			rz = side * flap
		elseif kind == "fin" then
			local a = if excited then R(25) * wave(time * 14) elseif walk then R(20) * wave(step) else R(6) * wave(time * 2.5)
			if side ~= 0 then
				rz = side * a
			else
				ry = a
			end
		elseif kind == "stalk" then
			rz = side * R(9) * wave(time * 2.3 + side)
			if hurt then
				rx = R(-30)
			elseif cheer then
				rz = side * R(18) * wave(time * 12)
			elseif ko then
				rx = R(40)
			end
		elseif kind == "pincer" then
			local open = R(14) * math.max(0, wave(time * 2.4 + side))
			if fight then
				open = R(50) * lunge
			elseif cheer then
				open = R(30) * math.abs(wave(time * 12))
			elseif hurt then
				open = R(30)
			end
			rx = -open
		elseif kind == "tendril" then
			local amp = (if excited then R(22) else R(12)) * (if ph % 1 > 0 then 0.6 else 1)
			rx = amp * wave(time * 3 + ph)
			rz = R(6) * wave(time * 2 + ph * 1.7)
			if ko then
				rx = R(30)
			end
		elseif kind == "antenna" then
			rx = R(10) * wave(time * 4 + side)
			if cheer then
				rx = R(20) * wave(time * 14 + side)
			elseif hurt then
				rx = R(25)
			end
		end
		local base = if j.parent then world[j.parent :: string] or CFrame.identity else CFrame.identity
		local pv = j.pivot
		world[name] = base * CFrame.new(pv.X + tx, pv.Y + ty, pv.Z + tz) * CFrame.fromEulerAnglesXYZ(rx, ry, rz) * CFrame.new(-pv)
	end
	local shut = blink or hurt or ko
	local open = fight or hurt or cheer
	for name, p in t.parts do
		local r0 = t.baseRest[name]
		if shut and string.sub(name, 1, 5) == "Shine" then
			-- (a shut eye hides its shine: tucked behind it)
			r0 = r0 * CFrame.new(0, 0, -0.25)
		end
		local w = world[rig.of[name] or "body"] or CFrame.identity
		local rr = w * r0
		t.rest[name] = CFrame.new(rr.Position * sc) * rr.Rotation
		if name == "EyeL" or name == "EyeR" then
			local s = t.baseSize[name]
			local sz = V(s.X * sc.X, (if shut then 0.125 else s.Y) * sc.Y, s.Z * sc.Z)
			if p.Size ~= sz then
				p.Size = sz
			end
		elseif name == "Mouth" then
			local s = t.baseSize[name]
			local sz = V(s.X * sc.X, (if open then math.max(0.25, s.Y * 2.5) else s.Y) * sc.Y, s.Z * sc.Z)
			if p.Size ~= sz then
				p.Size = sz
			end
		end
	end
end

return DriftModels
