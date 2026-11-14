--!strict
-- What a founder wears (GAME_DESIGN 14.1; Data/Cosmetics): every piece built from a few parts on the founder's rig
-- (Models/CharacterModels), island things of our own design. Roblox-free data: Vector3, CFrame and palette keys only.
--   CosmeticModels.parts(id) -> { Spec }   the piece's parts, each on a bone of the standing rig ("head": moves with the
--                                          head, "body": with the torso, "hand": with the right forearm), `at` in the
--                                          standing rig's own space (its feet at the origin, facing +Z), `rot` turning it
--   CosmeticModels.top(id) -> Recolor?     a top's colours for the shirt it is worn over (the torso, the sleeves, the
--                                          collar and buttons) and the shirt's parts it hides (the belt under a coat)
--   CosmeticModels.covers(id) -> string?   what a hat hides of the hair: "top" (what sticks up: spikes, a bun, curls, a
--                                          mohawk) or "hood" (all of it but the fringe)
-- Anchors (the standing rig, before Tuning.FounderScale): the head's middle (0, 3.125, 0), its front at z 0.625 and the
-- top of the hair at y 4.05; the torso's middle (0, 1.875, 0), its front at z 0.375 and its back at -0.375; the right
-- hand's middle (0.8125, 1.39, 0), the arm hanging down at the side.
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)

local CosmeticModels = {}

export type Spec = {
	name: string,
	size: Vector3,
	at: Vector3,
	color: string,
	shape: ("Block" | "Ball" | "Cylinder" | "Wedge")?,
	rot: CFrame?,
	bone: string,
	neon: boolean?,
}
export type Recolor = { torso: string?, arms: string?, trim: string?, hide: { string }? }

local HEAD = Vector3.new(0, 3.125, 0)
local BODY = Vector3.new(0, 1.875, 0)
local HAND = Vector3.new(0.8125, 1.39, 0)
local V = Vector3.new
local R = math.rad
local UP = CFrame.Angles(0, 0, R(90)) -- a cylinder standing up (Roblox cylinders run along X)
local FACE = CFrame.Angles(0, R(90), 0) -- a cylinder facing the front (a disc in the XY plane)

type Builder = { list: { Spec }, n: number }

local function add(b: Builder, bone: string, origin: Vector3, size: Vector3, at: Vector3, color: string, shape: string?, rot: CFrame?, neon: boolean?)
	b.n += 1
	table.insert(b.list, { name = "Wear" .. b.n, size = size, at = origin + at, color = color, shape = shape :: any, rot = rot, bone = bone, neon = neon })
end

-- (each piece's builder: h adds a part on the head, d on the body, r in the hand)
type Put = (size: Vector3, at: Vector3, color: string, shape: string?, rot: CFrame?, neon: boolean?) -> ()
type Make = (h: Put, d: Put, r: Put) -> ()

local MAKE: { [string]: Make } = {}
local TOPS: { [string]: Recolor } = {}
local COVERS: { [string]: string } = {}

------------------------------------------------------------------ hats (the top of the hair at y +0.925 from the head)
MAKE.strawhat = function(h)
	h(V(0.125, 2.5, 2.5), V(0, 0.98, -0.05), "straw", "Cylinder", UP)
	h(V(0.5, 1.45, 1.45), V(0, 1.25, -0.05), "straw", "Cylinder", UP)
	h(V(0.125, 1.5, 1.5), V(0, 1.1, -0.05), "berry_red", "Cylinder", UP)
end
COVERS.strawhat = "top"
MAKE.buckethat = function(h)
	h(V(0.125, 2.2, 2.2), V(0, 0.9, -0.05), "moss", "Cylinder", UP)
	h(V(0.625, 1.8, 1.8), V(0, 1.25, -0.05), "moss", "Cylinder", UP)
	h(V(0.125, 1.82, 1.82), V(0, 1.05, -0.05), "swamp", "Cylinder", UP)
end
COVERS.buckethat = "top"
MAKE.bandana = function(h)
	h(V(1.875, 0.375, 1.625), V(0, 0.6, -0.05), "berry_red")
	h(V(1.875, 0.125, 1.625), V(0, 0.72, -0.05), "white")
	h(V(0.375, 0.375, 0.25), V(0, 0.55, -0.95), "berry_red")
	h(V(0.25, 0.5, 0.125), V(0.15, 0.2, -1.0), "berry_red", nil, CFrame.Angles(0, 0, R(-20)))
end
MAKE.beanie = function(h)
	-- (a knit block over the whole cap, a round crown, the cuff, a pompom)
	h(V(1.95, 0.625, 1.75), V(0, 0.85, -0.05), "orange")
	h(V(1.9, 0.75, 1.7), V(0, 1.15, -0.05), "orange", "Ball")
	h(V(2.0, 0.375, 1.8), V(0, 0.55, -0.05), "cream")
	h(V(0.5, 0.5, 0.5), V(0, 1.55, -0.05), "white", "Ball")
end
COVERS.beanie = "top"
MAKE.sunvisor = function(h)
	h(V(1.875, 0.25, 1.625), V(0, 0.6, -0.05), "white")
	h(V(1.375, 0.125, 0.625), V(0, 0.55, 0.95), "yellow")
end
MAKE.flowercrown = function(h)
	h(V(1.875, 0.125, 1.625), V(0, 0.98, -0.05), "leaf")
	local spots: { { x: number, z: number, c: string } } = {
		{ x = -0.6, z = 0.45, c = "pink" },
		{ x = 0, z = 0.72, c = "yellow" },
		{ x = 0.6, z = 0.45, c = "white" },
		{ x = -0.82, z = -0.25, c = "cherry" },
		{ x = 0.82, z = -0.25, c = "pink" },
		{ x = 0, z = -0.8, c = "yellow" },
	}
	for _, s in spots do
		h(V(0.375, 0.375, 0.375), V(s.x, 1.08, s.z), s.c, "Ball")
	end
end
MAKE.captaincap = function(h)
	h(V(1.75, 0.5, 1.625), V(0, 1.2, -0.05), "white")
	h(V(1.8, 0.25, 1.68), V(0, 0.98, -0.05), "night")
	h(V(1.375, 0.125, 0.5), V(0, 0.9, 0.95), "night")
	h(V(0.375, 0.25, 0.125), V(0, 1.15, 0.79), "gold")
end
COVERS.captaincap = "top"
MAKE.leafhat = function(h)
	h(V(1.75, 0.125, 2.25), V(0, 1.05, 0), "leaf", nil, CFrame.Angles(R(-10), 0, 0))
	h(V(0.125, 0.15, 2.0), V(0, 1.13, 0), "leaf_dark", nil, CFrame.Angles(R(-10), 0, 0))
	h(V(0.125, 0.5, 0.125), V(0, 1.3, -1.15), "wood")
end
COVERS.leafhat = "top"
MAKE.shellcap = function(h)
	h(V(1.75, 1.0, 1.625), V(0, 1.0, -0.05), "cream", "Ball")
	-- (the ridges follow the dome: flat rounds a little proud of it)
	for k = -1, 1 do
		h(V(0.2, 1.0, 1.6), V(k * 0.42, 1.02, -0.05), "coral", "Ball")
	end
end
COVERS.shellcap = "top"
MAKE.tricorn = function(h)
	h(V(0.6, 1.45, 1.45), V(0, 1.3, -0.05), "black", "Cylinder", UP)
	h(V(1.75, 0.5, 0.125), V(0, 1.15, 0.85), "black", nil, CFrame.Angles(R(-20), 0, 0))
	h(V(0.125, 0.5, 1.75), V(0.9, 1.15, -0.2), "black", nil, CFrame.Angles(0, 0, R(-20)))
	h(V(0.125, 0.5, 1.75), V(-0.9, 1.15, -0.2), "black", nil, CFrame.Angles(0, 0, R(20)))
	h(V(1.8, 0.125, 0.15), V(0, 1.4, 0.92), "gold", nil, CFrame.Angles(R(-20), 0, 0))
end
COVERS.tricorn = "top"
MAKE.froghood = function(h)
	h(V(2.0, 0.5, 1.75), V(0, 1.05, -0.1), "green")
	h(V(0.25, 1.25, 1.6), V(0.95, 0.35, -0.15), "green")
	h(V(0.25, 1.25, 1.6), V(-0.95, 0.35, -0.15), "green")
	h(V(2.0, 1.375, 0.3), V(0, 0.4, -0.9), "green")
	h(V(0.55, 0.55, 0.55), V(-0.45, 1.4, 0.35), "white", "Ball")
	h(V(0.55, 0.55, 0.55), V(0.45, 1.4, 0.35), "white", "Ball")
	h(V(0.25, 0.25, 0.25), V(-0.45, 1.42, 0.58), "black", "Ball")
	h(V(0.25, 0.25, 0.25), V(0.45, 1.42, 0.58), "black", "Ball")
end
COVERS.froghood = "hood"
MAKE.coconuthelm = function(h)
	h(V(1.95, 1.25, 1.75), V(0, 0.95, -0.05), "wood_dark", "Ball")
	h(V(1.97, 0.125, 1.77), V(0, 0.55, -0.05), "cream")
	h(V(0.25, 0.25, 0.25), V(-0.3, 1.45, 0.45), "black", "Ball")
	h(V(0.25, 0.25, 0.25), V(0.3, 1.45, 0.45), "black", "Ball")
end
COVERS.coconuthelm = "top"
MAKE.wizardhat = function(h)
	h(V(0.125, 2.4, 2.4), V(0, 0.98, -0.05), "purple", "Cylinder", UP)
	h(V(0.6, 1.45, 1.45), V(0, 1.3, -0.05), "purple", "Cylinder", UP)
	h(V(0.6, 1.0, 1.0), V(0, 1.85, -0.1), "purple", "Cylinder", UP)
	h(V(0.5, 0.6, 0.6), V(0.1, 2.35, -0.2), "purple", "Cylinder", UP * CFrame.Angles(R(-15), 0, 0))
	h(V(0.375, 0.375, 0.375), V(0.25, 2.65, -0.25), "yellow", "Ball", nil, true)
	h(V(0.25, 0.25, 0.125), V(-0.3, 1.35, 0.68), "gold")
	h(V(0.25, 0.25, 0.125), V(0.35, 1.7, 0.45), "gold")
end
COVERS.wizardhat = "top"
MAKE.halo = function(h)
	for k = 0, 5 do
		local a = k * math.pi / 3
		-- (each piece along the ring: its long side on the circle's tangent)
		h(V(0.6, 0.125, 0.2), V(math.sin(a) * 0.62, 1.55, -0.05 + math.cos(a) * 0.62), "yellow", nil, CFrame.Angles(0, a, 0), true)
	end
end
MAKE.fishbowl = function(h)
	h(V(0.75, 1.3, 1.3), V(0, 1.35, -0.05), "window", "Cylinder", UP)
	h(V(0.125, 1.32, 1.32), V(0, 1.55, -0.05), "water", "Cylinder", UP)
	h(V(0.5, 0.25, 0.15), V(0.1, 1.3, 0.6), "orange")
	h(V(0.125, 1.4, 1.4), V(0, 1.0, -0.05), "steel", "Cylinder", UP)
end
COVERS.fishbowl = "top"
MAKE.eggshellcap = function(h)
	h(V(1.95, 1.3, 1.75), V(0, 1.0, -0.05), "cream", "Ball")
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		h(V(0.375, 0.375, 0.375), V(math.sin(a) * 0.82, 0.55, -0.05 + math.cos(a) * 0.72), "cream", nil, CFrame.Angles(0, a, R(45)))
	end
	h(V(0.25, 0.25, 0.125), V(-0.35, 1.3, 0.75), "cherry")
	h(V(0.25, 0.25, 0.125), V(0.45, 1.05, 0.72), "cherry")
end
COVERS.eggshellcap = "top"
MAKE.explorerhat = function(h)
	h(V(0.125, 2.3, 2.3), V(0, 0.98, -0.05), "sand", "Cylinder", UP)
	h(V(1.8, 1.0, 1.625), V(0, 1.25, -0.05), "sand", "Ball")
	h(V(0.15, 1.75, 1.75), V(0, 1.1, -0.05), "wood_dark", "Cylinder", UP)
end
COVERS.explorerhat = "top"
MAKE.driftears = function(h)
	h(V(1.875, 0.125, 0.25), V(0, 0.98, 0.15), "pink")
	for _, sx in { -1, 1 } do
		h(V(0.45, 0.75, 0.25), V(sx * 0.55, 1.4, 0.05), "teal", nil, CFrame.Angles(0, 0, R(-sx * 12)))
		h(V(0.25, 0.45, 0.125), V(sx * 0.55, 1.4, 0.18), "pink", nil, CFrame.Angles(0, 0, R(-sx * 12)))
	end
end
MAKE.tidecrown = function(h)
	h(V(0.375, 1.65, 1.65), V(0, 1.1, -0.05), "teal", "Cylinder", UP)
	for k = 0, 4 do
		local a = k * 2 * math.pi / 5
		h(V(0.3, 0.5, 0.2), V(math.sin(a) * 0.72, 1.45, -0.05 + math.cos(a) * 0.72), "foam", nil, CFrame.Angles(0, a, R(20)))
	end
	h(V(0.3, 0.3, 0.3), V(0, 1.15, 0.82), "white", "Ball")
end
COVERS.tidecrown = "top"
MAKE.goldcrown = function(h)
	h(V(0.45, 1.55, 1.55), V(0, 1.15, -0.05), "gold", "Cylinder", UP)
	for k = 0, 4 do
		local a = k * 2 * math.pi / 5
		h(V(0.25, 0.5, 0.25), V(math.sin(a) * 0.66, 1.55, -0.05 + math.cos(a) * 0.66), "gold", nil, CFrame.Angles(0, a, 0))
		h(V(0.2, 0.2, 0.2), V(math.sin(a) * 0.66, 1.85, -0.05 + math.cos(a) * 0.66), "yellow", "Ball")
	end
	h(V(0.3, 0.3, 0.125), V(0, 1.15, 0.78), "berry_red", "Ball")
end
COVERS.goldcrown = "top"

------------------------------------------------------------------ the face (its front at z +0.625, the eyes at y +0.025)
MAKE.sunglasses = function(h)
	h(V(0.55, 0.375, 0.125), V(-0.37, 0.05, 0.69), "night")
	h(V(0.55, 0.375, 0.125), V(0.37, 0.05, 0.69), "night")
	h(V(0.25, 0.125, 0.125), V(0, 0.15, 0.69), "black")
	h(V(0.125, 0.125, 0.75), V(-0.76, 0.1, 0.35), "black")
	h(V(0.125, 0.125, 0.75), V(0.76, 0.1, 0.35), "black")
end
MAKE.roundglasses = function(h)
	for _, sx in { -1, 1 } do
		h(V(0.125, 0.5, 0.5), V(sx * 0.37, 0.05, 0.68), "wood_dark", "Cylinder", FACE)
		h(V(0.125, 0.375, 0.375), V(sx * 0.37, 0.05, 0.71), "window", "Cylinder", FACE)
	end
	h(V(0.25, 0.125, 0.125), V(0, 0.08, 0.69), "wood_dark")
end
MAKE.rosycheeks = function(h)
	h(V(0.375, 0.25, 0.125), V(-0.5, -0.24, 0.67), "coral")
	h(V(0.375, 0.25, 0.125), V(0.5, -0.24, 0.67), "coral")
	h(V(0.125, 0.125, 0.125), V(-0.56, -0.2, 0.72), "white")
	h(V(0.125, 0.125, 0.125), V(0.44, -0.2, 0.72), "white")
end
MAKE.snorkel = function(h)
	h(V(1.375, 0.625, 0.125), V(0, 0.08, 0.68), "teal")
	h(V(1.125, 0.4, 0.125), V(0, 0.08, 0.72), "window")
	h(V(0.15, 1.25, 0.15), V(0.86, 0.45, 0.35), "orange")
	h(V(0.25, 0.25, 0.25), V(0.86, 1.1, 0.35), "orange")
	h(V(0.125, 0.25, 1.25), V(-0.8, 0.08, 0.05), "teal")
end
MAKE.eyepatch = function(h)
	h(V(0.45, 0.4, 0.125), V(0.37, 0.05, 0.69), "black")
	h(V(1.75, 0.125, 0.125), V(0, 0.28, 0.66), "black", nil, CFrame.Angles(0, 0, R(-18)))
	h(V(0.125, 0.125, 1.25), V(-0.79, 0.52, 0.05), "black")
end
MAKE.moustache = function(h)
	h(V(0.5, 0.15, 0.125), V(0, -0.24, 0.7), "wood_dark")
	h(V(0.25, 0.25, 0.125), V(-0.36, -0.2, 0.69), "wood_dark", "Ball")
	h(V(0.25, 0.25, 0.125), V(0.36, -0.2, 0.69), "wood_dark", "Ball")
end
MAKE.monocle = function(h)
	h(V(0.125, 0.5, 0.5), V(0.37, 0.05, 0.69), "gold", "Cylinder", FACE)
	h(V(0.125, 0.375, 0.375), V(0.37, 0.05, 0.72), "window", "Cylinder", FACE)
	h(V(0.0625, 0.7, 0.0625), V(0.55, -0.35, 0.7), "gold")
end
MAKE.heartshades = function(h)
	for _, sx in { -1, 1 } do
		h(V(0.25, 0.25, 0.125), V(sx * 0.37 - 0.1, 0.1, 0.69), "pink", "Ball")
		h(V(0.25, 0.25, 0.125), V(sx * 0.37 + 0.1, 0.1, 0.69), "pink", "Ball")
		h(V(0.3, 0.3, 0.125), V(sx * 0.37, -0.05, 0.69), "pink", nil, CFrame.Angles(0, 0, R(45)))
	end
	h(V(0.25, 0.0625, 0.125), V(0, 0.12, 0.69), "black")
end
MAKE.stargoggles = function(h)
	h(V(1.6, 0.25, 1.375), V(0, 0.08, -0.05), "black")
	for _, sx in { -1, 1 } do
		h(V(0.25, 0.55, 0.55), V(sx * 0.37, 0.08, 0.69), "gold", "Cylinder", FACE)
		h(V(0.125, 0.4, 0.4), V(sx * 0.37, 0.08, 0.8), "crystal", "Cylinder", FACE)
	end
end
MAKE.leafpaint = function(h)
	for _, sx in { -1, 1 } do
		h(V(0.375, 0.125, 0.0625), V(sx * 0.5, -0.14, 0.645), "leaf")
		h(V(0.375, 0.125, 0.0625), V(sx * 0.5, -0.32, 0.645), "leaf")
	end
	h(V(0.125, 0.125, 0.0625), V(0, 0.32, 0.645), "leaf")
end
MAKE.glowvisor = function(h)
	h(V(1.55, 0.3, 0.15), V(0, 0.06, 0.69), "screen_on", nil, nil, true)
	h(V(0.125, 0.375, 0.75), V(0.8, 0.06, 0.35), "steel")
	h(V(0.125, 0.375, 0.75), V(-0.8, 0.06, 0.35), "steel")
end
MAKE.goldshades = function(h)
	for _, sx in { -1, 1 } do
		h(V(0.625, 0.45, 0.0625), V(sx * 0.37, 0.05, 0.66), "gold")
		h(V(0.5, 0.33, 0.125), V(sx * 0.37, 0.05, 0.7), "night")
		h(V(0.125, 0.125, 0.75), V(sx * 0.76, 0.12, 0.35), "gold")
	end
	h(V(0.25, 0.125, 0.125), V(0, 0.15, 0.69), "gold")
end

------------------------------------------------------------------ round the neck (the top of the torso at y +0.625)
-- a ring of `n` round beads round the neck
local function ring(d: Put, n: number, size: number, colors: { string }, y: number)
	for k = 0, n - 1 do
		local a = (k + 0.5) * 2 * math.pi / n
		d(V(size, size, size), V(math.sin(a) * 0.66, y, math.cos(a) * 0.43), colors[k % #colors + 1], "Ball")
	end
end
-- a cord hanging in a V from the shoulders down to a pendant at (0, y)
local function cord(d: Put, y: number, color: string)
	d(V(0.0625, 0.5, 0.0625), V(-0.2, y + 0.3, 0.41), color, nil, CFrame.Angles(0, 0, R(-35)))
	d(V(0.0625, 0.5, 0.0625), V(0.2, y + 0.3, 0.41), color, nil, CFrame.Angles(0, 0, R(35)))
end
MAKE.lei = function(_, d)
	ring(d, 8, 0.35, { "pink", "yellow", "coral", "white" }, 0.6)
end
MAKE.scarf = function(_, d)
	d(V(1.4, 0.3, 0.875), V(0, 0.6, 0), "berry_red")
	d(V(1.42, 0.1, 0.89), V(0, 0.6, 0), "white")
	d(V(0.3, 0.75, 0.125), V(0.32, 0.2, 0.44), "berry_red")
	d(V(0.3, 0.1, 0.13), V(0.32, 0.05, 0.45), "white")
end
MAKE.shellnecklace = function(_, d)
	cord(d, 0.1, "wood_dark")
	d(V(0.3, 0.3, 0.15), V(0, 0.08, 0.44), "cream", "Ball")
	d(V(0.125, 0.25, 0.1), V(0, 0.08, 0.52), "coral")
end
MAKE.whistle = function(_, d)
	cord(d, 0.05, "berry_red")
	d(V(0.3, 0.15, 0.15), V(0.05, 0.02, 0.45), "yellow")
	d(V(0.125, 0.15, 0.15), V(-0.15, 0.02, 0.45), "steel")
end
MAKE.bowtie = function(_, d)
	d(V(0.3, 0.25, 0.125), V(-0.17, 0.55, 0.43), "berry_red", nil, CFrame.Angles(0, 0, R(10)))
	d(V(0.3, 0.25, 0.125), V(0.17, 0.55, 0.43), "berry_red", nil, CFrame.Angles(0, 0, R(-10)))
	d(V(0.125, 0.15, 0.15), V(0, 0.55, 0.45), "cherry")
end
MAKE.bell = function(_, d)
	d(V(1.35, 0.15, 0.85), V(0, 0.58, 0), "berry_red")
	d(V(0.375, 0.375, 0.375), V(0, 0.38, 0.47), "gold", "Ball")
	d(V(0.125, 0.125, 0.125), V(0, 0.25, 0.6), "wood_dark")
end
MAKE.medal = function(_, d)
	d(V(0.15, 0.5, 0.0625), V(-0.12, 0.35, 0.41), "blue", nil, CFrame.Angles(0, 0, R(-20)))
	d(V(0.15, 0.5, 0.0625), V(0.12, 0.35, 0.41), "blue", nil, CFrame.Angles(0, 0, R(20)))
	d(V(0.125, 0.45, 0.45), V(0, 0.02, 0.44), "gold", "Cylinder", FACE)
	d(V(0.125, 0.2, 0.2), V(0, 0.02, 0.5), "yellow", nil, CFrame.Angles(0, 0, R(45)))
end
MAKE.anchorpendant = function(_, d)
	cord(d, 0.1, "steel_dark")
	d(V(0.1, 0.45, 0.1), V(0, -0.02, 0.45), "steel")
	d(V(0.35, 0.08, 0.1), V(0, 0.12, 0.45), "steel")
	d(V(0.45, 0.1, 0.1), V(0, -0.22, 0.45), "steel")
	d(V(0.15, 0.15, 0.1), V(0, 0.22, 0.45), "steel", "Ball")
end
MAKE.pearls = function(_, d)
	ring(d, 10, 0.22, { "white", "cream" }, 0.6)
end
MAKE.crystalamulet = function(_, d)
	cord(d, 0.08, "gold")
	d(V(0.35, 0.35, 0.1), V(0, 0.02, 0.44), "gold", nil, CFrame.Angles(0, 0, R(45)))
	d(V(0.25, 0.25, 0.15), V(0, 0.02, 0.47), "crystal", nil, CFrame.Angles(0, 0, R(45)), true)
end
MAKE.feathercollar = function(_, d)
	for k = 0, 5 do
		local a = (k + 0.5) * 2 * math.pi / 6
		d(V(0.3, 0.125, 0.6), V(math.sin(a) * 0.7, 0.62, math.cos(a) * 0.48), if k % 2 == 0 then "teal" else "white", nil, CFrame.Angles(0, a, 0) * CFrame.Angles(R(-25), 0, 0))
	end
end
MAKE.goldchain = function(_, d)
	d(V(1.375, 0.15, 0.875), V(0, 0.6, 0), "gold")
	cord(d, 0.05, "gold")
	d(V(0.125, 0.45, 0.45), V(0, -0.02, 0.45), "gold", "Cylinder", FACE)
	d(V(0.125, 0.25, 0.25), V(0, -0.02, 0.5), "berry_red", "Ball")
end

------------------------------------------------------------------ on the back (its back at z -0.375)
MAKE.backpack = function(_, d)
	d(V(0.9, 1.0, 0.5), V(0, 0.05, -0.62), "orange")
	d(V(0.625, 0.4, 0.15), V(0, -0.15, -0.93), "yellow")
	d(V(0.92, 0.3, 0.52), V(0, 0.45, -0.62), "berry_red")
	d(V(0.15, 0.15, 0.8), V(-0.35, 0.65, 0), "wood_dark")
	d(V(0.15, 0.15, 0.8), V(0.35, 0.65, 0), "wood_dark")
end
MAKE.surfboard = function(_, d)
	local tilt = CFrame.Angles(0, 0, R(18))
	d(V(0.6, 2.5, 0.15), V(0.1, 0.25, -0.5), "coral", nil, tilt)
	d(V(0.15, 2.5, 0.16), V(0.1, 0.25, -0.5), "white", nil, tilt)
	d(V(0.6, 0.6, 0.15), V(-0.3, 1.45, -0.5), "coral", "Ball", tilt)
end
MAKE.shellpack = function(_, d)
	d(V(1.25, 1.25, 0.6), V(0, 0.05, -0.62), "cream", "Ball")
	for k = -1, 1 do
		d(V(0.15, 1.15, 0.62), V(k * 0.35, 0.08, -0.66), "coral")
	end
	d(V(0.15, 0.15, 0.8), V(-0.35, 0.65, 0), "wood")
	d(V(0.15, 0.15, 0.8), V(0.35, 0.65, 0), "wood")
end
MAKE.redcape = function(_, d)
	d(V(1.3, 1.75, 0.125), V(0, -0.2, -0.47), "berry_red", nil, CFrame.Angles(R(8), 0, 0))
	d(V(1.35, 0.15, 0.85), V(0, 0.6, -0.02), "berry_red")
	d(V(0.25, 0.25, 0.125), V(0, 0.55, 0.43), "gold", "Ball")
end
MAKE.butterflywings = function(_, d)
	for _, sx in { -1, 1 } do
		d(V(0.9, 0.8, 0.1), V(sx * 0.6, 0.45, -0.52), "pink", nil, CFrame.Angles(0, R(sx * 20), R(-sx * 10)))
		d(V(0.6, 0.55, 0.1), V(sx * 0.48, -0.2, -0.52), "yellow", nil, CFrame.Angles(0, R(sx * 20), R(sx * 15)))
		d(V(0.25, 0.25, 0.12), V(sx * 0.7, 0.5, -0.55), "white", "Ball")
	end
end
MAKE.kite = function(_, d)
	d(V(1.0, 1.0, 0.1), V(0.25, 1.1, -0.6), "teal", nil, CFrame.Angles(0, 0, R(45)))
	d(V(0.06, 1.4, 0.12), V(0.25, 1.1, -0.66), "wood", nil, CFrame.Angles(0, 0, R(0)))
	d(V(1.4, 0.06, 0.12), V(0.25, 1.1, -0.66), "wood")
	for k = 1, 3 do
		d(V(0.25, 0.15, 0.1), V(0.25 + k * 0.12, 0.35 - k * 0.32, -0.6), if k % 2 == 0 then "yellow" else "berry_red")
	end
end
MAKE.turtleshell = function(_, d)
	d(V(1.4, 1.5, 0.7), V(0, 0, -0.52), "moss", "Ball")
	d(V(0.5, 0.45, 0.15), V(0, 0.2, -0.85), "swamp")
	d(V(0.35, 0.35, 0.15), V(-0.35, -0.3, -0.8), "swamp")
	d(V(0.35, 0.35, 0.15), V(0.35, -0.3, -0.8), "swamp")
	d(V(1.45, 0.125, 0.75), V(0, -0.6, -0.5), "cream")
end
MAKE.leafwings = function(_, d)
	for _, sx in { -1, 1 } do
		d(V(0.7, 1.4, 0.1), V(sx * 0.55, 0.3, -0.52), "leaf", nil, CFrame.Angles(0, R(sx * 15), R(-sx * 30)))
		d(V(0.1, 1.3, 0.12), V(sx * 0.55, 0.3, -0.54), "leaf_dark", nil, CFrame.Angles(0, R(sx * 15), R(-sx * 30)))
	end
end
MAKE.featherwings = function(_, d)
	for _, sx in { -1, 1 } do
		d(V(1.0, 0.7, 0.125), V(sx * 0.7, 0.45, -0.52), "white", nil, CFrame.Angles(0, R(sx * 15), R(-sx * 15)))
		d(V(0.8, 0.5, 0.125), V(sx * 0.65, -0.05, -0.5), "white", nil, CFrame.Angles(0, R(sx * 15), R(-sx * 5)))
		d(V(0.5, 0.35, 0.13), V(sx * 1.15, 0.65, -0.56), "cream", nil, CFrame.Angles(0, R(sx * 15), R(-sx * 30)))
	end
end
MAKE.rocketpack = function(_, d)
	for _, sx in { -1, 1 } do
		d(V(1.0, 0.55, 0.55), V(sx * 0.3, 0.05, -0.65), "wood_dark", "Cylinder", UP)
		d(V(0.375, 0.375, 0.375), V(sx * 0.3, -0.6, -0.65), "orange", "Ball", nil, true)
		d(V(0.25, 0.25, 0.25), V(sx * 0.3, -0.85, -0.65), "yellow", "Ball", nil, true)
	end
	d(V(0.6, 0.2, 0.3), V(0, 0.3, -0.55), "steel")
end
MAKE.eggbasket = function(_, d)
	d(V(1.0, 0.6, 0.6), V(0, -0.2, -0.7), "straw")
	d(V(1.05, 0.125, 0.65), V(0, 0.1, -0.7), "wood")
	d(V(0.375, 0.45, 0.375), V(-0.28, 0.25, -0.7), "cherry", "Ball")
	d(V(0.375, 0.45, 0.375), V(0.05, 0.3, -0.72), "shallow", "Ball")
	d(V(0.375, 0.45, 0.375), V(0.33, 0.22, -0.68), "yellow", "Ball")
	d(V(0.15, 0.15, 0.8), V(0.35, 0.65, -0.05), "wood")
end
MAKE.drakewings = function(_, d)
	for _, sx in { -1, 1 } do
		d(V(1.3, 0.15, 0.15), V(sx * 0.75, 0.75, -0.52), "night", nil, CFrame.Angles(0, R(sx * 15), R(sx * 25)))
		d(V(1.0, 0.8, 0.1), V(sx * 0.75, 0.25, -0.52), "purple", "Wedge", CFrame.Angles(0, R(90 + sx * 15), 0))
		d(V(0.15, 0.35, 0.15), V(sx * 1.35, 0.95, -0.55), "night")
	end
end
MAKE.starcape = function(_, d)
	d(V(1.3, 1.75, 0.125), V(0, -0.2, -0.47), "night", nil, CFrame.Angles(R(8), 0, 0))
	d(V(1.35, 0.15, 0.85), V(0, 0.6, -0.02), "night")
	d(V(0.25, 0.25, 0.125), V(0, 0.55, 0.43), "gold", "Ball")
	d(V(0.15, 0.15, 0.13), V(-0.3, 0.1, -0.56), "yellow", nil, nil, true)
	d(V(0.15, 0.15, 0.13), V(0.25, -0.35, -0.6), "yellow", nil, nil, true)
	d(V(0.15, 0.15, 0.13), V(-0.15, -0.75, -0.65), "yellow", nil, nil, true)
end
MAKE.royalcape = function(_, d)
	d(V(1.4, 1.875, 0.125), V(0, -0.25, -0.48), "berry_red", nil, CFrame.Angles(R(8), 0, 0))
	d(V(1.45, 0.3, 0.9), V(0, 0.6, -0.02), "white")
	d(V(0.125, 0.125, 0.125), V(-0.3, 0.62, 0.46), "black")
	d(V(0.125, 0.125, 0.125), V(0.3, 0.62, 0.46), "black")
	d(V(0.25, 0.25, 0.125), V(0, 0.5, 0.46), "gold", "Ball")
end

------------------------------------------------------------------ in the hand (the right hand's middle, the arm down)
MAKE.bugnet = function(_, _, r)
	r(V(0.125, 1.75, 0.125), V(0, 0.55, 0.1), "wood")
	r(V(0.125, 0.8, 0.8), V(0, 1.75, 0.1), "white", "Cylinder")
	r(V(0.5, 0.6, 0.6), V(0.25, 1.65, 0.1), "cream", "Ball")
end
MAKE.shovel = function(_, _, r)
	r(V(0.125, 1.25, 0.125), V(0, 0.25, 0.1), "wood")
	r(V(0.45, 0.5, 0.1), V(0, -0.55, 0.1), "teal")
	r(V(0.375, 0.125, 0.125), V(0, 0.9, 0.1), "teal")
end
MAKE.icecream = function(_, _, r)
	r(V(0.3, 0.5, 0.3), V(0, 0.4, 0.15), "straw", nil, CFrame.Angles(0, R(45), 0))
	r(V(0.5, 0.5, 0.5), V(0, 0.75, 0.15), "pink", "Ball")
	r(V(0.2, 0.2, 0.2), V(0, 1.02, 0.15), "berry_red", "Ball")
end
MAKE.lantern = function(_, _, r)
	r(V(0.1, 1.0, 0.1), V(0, 0.55, 0.1), "wood")
	r(V(0.6, 0.7, 0.6), V(0, 1.35, 0.1), "berry_red", "Ball", nil, true)
	r(V(0.3, 0.1, 0.3), V(0, 1.72, 0.1), "black")
	r(V(0.3, 0.1, 0.3), V(0, 0.98, 0.1), "black")
end
MAKE.umbrella = function(_, _, r)
	-- (held up over the head)
	r(V(0.1, 3.9, 0.1), V(0, 1.75, 0.05), "wood")
	r(V(0.3, 1.9, 1.9), V(0, 3.65, 0.05), "coral", "Cylinder", UP)
	r(V(0.1, 1.95, 1.95), V(0, 3.5, 0.05), "cherry", "Cylinder", UP)
	r(V(0.2, 0.2, 0.2), V(0, 3.85, 0.05), "wood", "Ball")
end
MAKE.fishingrod = function(_, _, r)
	local tilt = CFrame.Angles(R(-25), 0, 0)
	r(V(0.1, 2.3, 0.1), V(0, 1.0, 0.5), "wood_dark", nil, tilt)
	r(V(0.2, 0.2, 0.15), V(0.1, 0.1, 0.2), "steel")
	r(V(0.0625, 1.2, 0.0625), V(0, 1.55, 1.0), "white")
	r(V(0.25, 0.25, 0.25), V(0, 0.95, 1.0), "berry_red", "Ball")
end
MAKE.balloon = function(_, _, r)
	-- (floating up past the head)
	r(V(0.0625, 2.9, 0.0625), V(0, 1.55, 0.05), "white")
	r(V(0.8, 0.95, 0.8), V(0, 3.45, 0.05), "berry_red", "Ball")
	r(V(0.15, 0.15, 0.15), V(0, 2.95, 0.05), "berry_red")
end
MAKE.ukulele = function(_, _, r)
	r(V(0.15, 0.9, 0.1), V(0, 0.3, 0.2), "wood_dark")
	r(V(0.55, 0.65, 0.2), V(0, -0.45, 0.2), "wood", "Ball")
	r(V(0.15, 0.15, 0.21), V(0, -0.35, 0.2), "black", "Ball")
	r(V(0.2, 0.2, 0.12), V(0, 0.8, 0.2), "wood_dark")
end
MAKE.starwand = function(_, _, r)
	r(V(0.1, 1.1, 0.1), V(0, 0.45, 0.1), "white")
	for k = 0, 2 do
		r(V(0.5, 0.15, 0.1), V(0, 1.1, 0.1), "yellow", nil, CFrame.Angles(0, 0, R(k * 60)), true)
	end
	r(V(0.2, 0.2, 0.2), V(0, 1.1, 0.15), "white", "Ball", nil, true)
end
MAKE.tikitorch = function(_, _, r)
	r(V(0.2, 1.9, 0.2), V(0, 0.65, 0.1), "bamboo")
	r(V(0.375, 0.3, 0.375), V(0, 1.7, 0.1), "wood_dark")
	r(V(0.375, 0.45, 0.375), V(0, 2.0, 0.1), "orange", "Ball", nil, true)
	r(V(0.2, 0.3, 0.2), V(0, 2.25, 0.1), "yellow", "Ball", nil, true)
end
MAKE.trident = function(_, _, r)
	r(V(0.125, 2.4, 0.125), V(0, 0.9, 0.1), "gold")
	r(V(0.625, 0.1, 0.1), V(0, 2.05, 0.1), "gold")
	for k = -1, 1 do
		r(V(0.1, 0.5, 0.1), V(k * 0.26, 2.3, 0.1), "gold")
	end
end
MAKE.scepter = function(_, _, r)
	r(V(0.125, 1.5, 0.125), V(0, 0.55, 0.1), "gold")
	r(V(0.45, 0.4, 0.3), V(0, 1.45, 0.1), "cream", "Ball")
	r(V(0.25, 0.25, 0.25), V(0, 1.45, 0.25), "berry_red", "Ball")
	r(V(0.3, 0.1, 0.3), V(0, 1.22, 0.1), "gold")
end

------------------------------------------------------------------ tops over the shirt
MAKE.sailor = function(_, d)
	d(V(1.35, 0.3, 0.85), V(0, 0.55, 0), "blue")
	d(V(1.37, 0.07, 0.87), V(0, 0.45, 0), "white")
	d(V(0.25, 0.2, 0.125), V(-0.12, 0.3, 0.42), "berry_red", nil, CFrame.Angles(0, 0, R(15)))
	d(V(0.25, 0.2, 0.125), V(0.12, 0.3, 0.42), "berry_red", nil, CFrame.Angles(0, 0, R(-15)))
end
TOPS.sailor = { torso = "white", arms = "white", trim = "blue" }
MAKE.stripes = function(_, d)
	for _, y in { -0.35, 0, 0.35 } do
		d(V(1.27, 0.15, 0.77), V(0, y, 0), "blue")
	end
end
TOPS.stripes = { torso = "white", arms = "white", trim = "blue" }
MAKE.flowershirt = function(_, d)
	local spots: { { x: number, y: number, c: string } } = {
		{ x = -0.35, y = 0.3, c = "pink" },
		{ x = 0.25, y = 0.4, c = "yellow" },
		{ x = -0.15, y = -0.2, c = "white" },
		{ x = 0.35, y = -0.3, c = "pink" },
	}
	for _, s in spots do
		d(V(0.25, 0.25, 0.0625), V(s.x, s.y, 0.4), s.c)
	end
	d(V(0.0625, 0.25, 0.25), V(0.64, 0.1, 0.05), "yellow")
end
TOPS.flowershirt = { torso = "teal", arms = "teal", trim = "white" }
MAKE.overalls = function(_, d)
	d(V(0.875, 0.625, 0.0625), V(0, -0.2, 0.41), "jeans")
	d(V(0.15, 0.6, 0.0625), V(-0.35, 0.3, 0.41), "jeans")
	d(V(0.15, 0.6, 0.0625), V(0.35, 0.3, 0.41), "jeans")
	d(V(1.27, 0.5, 0.77), V(0, -0.4, 0), "jeans")
	d(V(0.125, 0.125, 0.125), V(-0.35, 0.1, 0.44), "gold")
	d(V(0.125, 0.125, 0.125), V(0.35, 0.1, 0.44), "gold")
end
TOPS.overalls = { hide = { "Belt", "Buckle", "ButtonB" } }
MAKE.fishingvest = function(_, d)
	d(V(0.45, 1.0, 0.0625), V(-0.38, 0.0, 0.41), "moss")
	d(V(0.45, 1.0, 0.0625), V(0.38, 0.0, 0.41), "moss")
	d(V(1.27, 1.0, 0.0625), V(0, 0.0, -0.41), "moss")
	d(V(0.3, 0.25, 0.0625), V(-0.38, -0.15, 0.45), "swamp")
	d(V(0.3, 0.25, 0.0625), V(0.38, -0.15, 0.45), "swamp")
end
MAKE.hoodie = function(_, d)
	d(V(1.0, 0.6, 0.4), V(0, 0.6, -0.45), "purple")
	d(V(0.75, 0.3, 0.0625), V(0, -0.35, 0.41), "purple")
	d(V(0.0625, 0.35, 0.0625), V(-0.15, 0.4, 0.42), "white")
	d(V(0.0625, 0.35, 0.0625), V(0.15, 0.4, 0.42), "white")
end
TOPS.hoodie = { torso = "purple", arms = "purple", trim = "purple", hide = { "Collar", "ButtonA", "ButtonB" } }
MAKE.raincoat = function(_, d)
	d(V(1.375, 0.5, 0.875), V(0, -0.75, 0), "yellow")
	for _, y in { 0.3, 0, -0.3, -0.6 } do
		d(V(0.125, 0.125, 0.125), V(0, y, 0.42), "black")
	end
end
TOPS.raincoat = { torso = "yellow", arms = "yellow", trim = "yellow", hide = { "Belt", "Buckle", "ButtonA", "ButtonB" } }
MAKE.tuxedo = function(_, d)
	d(V(0.4, 0.9, 0.0625), V(0, 0.1, 0.4), "white")
	d(V(0.25, 0.2, 0.125), V(-0.12, 0.5, 0.43), "black")
	d(V(0.25, 0.2, 0.125), V(0.12, 0.5, 0.43), "black")
	d(V(0.125, 0.125, 0.125), V(0, 0.1, 0.44), "black")
end
TOPS.tuxedo = { torso = "black", arms = "black", trim = "white", hide = { "ButtonA", "ButtonB" } }
MAKE.starrobe = function(_, d)
	d(V(1.4, 0.8, 0.9), V(0, -0.85, 0), "night")
	d(V(0.2, 0.2, 0.0625), V(-0.3, 0.2, 0.4), "yellow", nil, nil, true)
	d(V(0.2, 0.2, 0.0625), V(0.3, -0.25, 0.4), "yellow", nil, nil, true)
	d(V(0.2, 0.2, 0.0625), V(-0.2, -0.95, 0.46), "yellow", nil, nil, true)
	d(V(1.42, 0.125, 0.92), V(0, -1.2, 0), "gold")
end
TOPS.starrobe = { torso = "night", arms = "night", trim = "gold", hide = { "Belt", "Buckle", "ButtonA", "ButtonB" } }
MAKE.lifevest = function(_, d)
	d(V(0.5, 0.9, 0.15), V(-0.34, 0.05, 0.42), "orange")
	d(V(0.5, 0.9, 0.15), V(0.34, 0.05, 0.42), "orange")
	d(V(1.3, 0.9, 0.15), V(0, 0.05, -0.42), "orange")
	d(V(1.4, 0.125, 0.9), V(0, -0.15, 0), "black")
	d(V(1.4, 0.125, 0.9), V(0, 0.25, 0), "black")
	d(V(0.15, 0.6, 0.1), V(-0.34, 0.1, 0.5), "white")
end
MAKE.explorershirt = function(_, d)
	d(V(0.35, 0.3, 0.0625), V(-0.3, 0.2, 0.41), "sand_dark")
	d(V(0.35, 0.3, 0.0625), V(0.3, 0.2, 0.41), "sand_dark")
	d(V(0.4, 0.1, 0.1), V(-0.3, 0.38, 0.42), "wood_dark")
	d(V(0.4, 0.1, 0.1), V(0.3, 0.38, 0.42), "wood_dark")
end
TOPS.explorershirt = { torso = "sand", arms = "sand", trim = "sand_dark" }
MAKE.tiderobe = function(_, d)
	d(V(1.4, 0.8, 0.9), V(0, -0.85, 0), "teal")
	d(V(1.42, 0.15, 0.92), V(0, -1.2, 0), "foam")
	d(V(0.2, 1.4, 0.1), V(0, 0.0, 0.42), "gold", nil, CFrame.Angles(0, 0, R(35)))
end
TOPS.tiderobe = { torso = "teal", arms = "teal", trim = "foam", hide = { "Belt", "Buckle", "ButtonA", "ButtonB" } }
MAKE.goldjacket = function(_, d)
	d(V(0.35, 0.9, 0.0625), V(0, 0.1, 0.4), "white")
	d(V(0.2, 0.8, 0.07), V(-0.27, 0.15, 0.41), "black", nil, CFrame.Angles(0, 0, R(-10)))
	d(V(0.2, 0.8, 0.07), V(0.27, 0.15, 0.41), "black", nil, CFrame.Angles(0, 0, R(10)))
	d(V(0.125, 0.125, 0.125), V(0, -0.3, 0.44), "black")
end
TOPS.goldjacket = { torso = "gold", arms = "gold", trim = "black", hide = { "ButtonA", "ButtonB" } }

-- every piece in Data/Cosmetics has its model (the DataIntegrity spec checks it too)
for _, c in Cosmetics.list do
	assert(MAKE[c.id] ~= nil, "CosmeticModels: no model for " .. c.id)
end

local cache: { [string]: { Spec } } = {}

function CosmeticModels.parts(id: string): { Spec }
	local got = cache[id]
	if got then
		return got
	end
	local make = MAKE[id]
	local b: Builder = { list = {}, n = 0 }
	if make then
		make(function(size, at, color, shape, rot, neon)
			add(b, "head", HEAD, size, at, color, shape, rot, neon)
		end, function(size, at, color, shape, rot, neon)
			add(b, "body", BODY, size, at, color, shape, rot, neon)
		end, function(size, at, color, shape, rot, neon)
			add(b, "hand", HAND, size, at, color, shape, rot, neon)
		end)
	end
	-- (the part names carry the piece's id: two pieces' parts never share a name on one rig)
	for _, sp in b.list do
		sp.name = id .. "_" .. sp.name
	end
	cache[id] = b.list
	return b.list
end

function CosmeticModels.top(id: string): Recolor?
	return TOPS[id]
end

function CosmeticModels.covers(id: string): string?
	return COVERS[id]
end

-- The anchors, for the rigs that place these elsewhere (the seated rig moves the head and body ones by its own offset).
CosmeticModels.HEAD = HEAD
CosmeticModels.BODY = BODY
CosmeticModels.HAND = HAND

return CosmeticModels
