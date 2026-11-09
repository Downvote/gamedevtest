--!strict
-- The microgames' things in 3D (GAME_DESIGN 5; docs/ARCHITECTURE.md 6, 10.8). Roblox module (client: UI/MicroStage
-- builds them on a stage; the pixel filter draws them with the world's toon bands, palette and 1 px ink outline).
-- Every thing is a few plain parts (Models/Blocks: palette colours, 0.25-stud grid, no meshes), built round its own
-- origin: the middle of its footprint on the ground, facing +Z. `place(thing, cf)` puts its parts at cf times their
-- rest offsets every frame; `size` is its rough height (a shadow's radius, a tap target's size).
--   MicroModels.build(kind, opts?) -> Thing     kinds: see BUILD below
--   MicroModels.place(thing, cf), MicroModels.scale(thing, k) (squash: its built sizes and offsets times k)
--   MicroModels.recolor(thing, color) (every part but the "Keep" ones; a flash is recolor(thing, "white"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ = ReplicatedStorage

local Blocks = require(script.Parent.Blocks)

local MicroModels = {}

export type Thing = {
	model: Model,
	parts: { [string]: BasePart },
	rest: { [string]: CFrame },
	sizes: { [string]: Vector3 },
	baseRest: { [string]: CFrame },
	baseSize: { [string]: Vector3 },
	colors: { [string]: Color3 },
	h: number, -- its height (studs)
	r: number, -- its footprint's radius (studs)
	kind: string,
}

export type Opts = { color: string?, alt: string?, flag: boolean? }

local function new(kind: string, h: number, r: number): Thing
	local m = Blocks.model(nil, "Micro_" .. kind)
	return { model = m, parts = {}, rest = {}, sizes = {}, baseRest = {}, baseSize = {}, colors = {}, h = h, r = r, kind = kind }
end

-- One part: `at` is its centre in the thing's space, `rot` an extra turn about that centre.
local function add(t: Thing, name: string, shape: string, size: Vector3, at: Vector3, color: string, rot: CFrame?, neon: boolean?): BasePart
	local cf = CFrame.new(at) * (rot or CFrame.identity)
	local shp: any = if shape == "Block" then nil else shape
	local p = Blocks.part(t.model, { size = size, cf = cf, color = color, name = name, shape = shp, collide = false, query = false, neon = neon })
	p.CastShadow = false
	t.parts[name] = p
	t.rest[name] = cf
	t.sizes[name] = p.Size
	t.baseRest[name] = cf
	t.baseSize[name] = p.Size
	t.colors[name] = p.Color
	return p
end

-- An upright cylinder (Roblox cylinders run along X).
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local BUILD: { [string]: (opts: Opts) -> Thing } = {}

------------------------------------------------------------------ falling, flying and popping things
BUILD.crate = function(_o)
	local t = new("crate", 2.5, 1.5)
	add(t, "Body", "Block", Vector3.new(2.5, 2.5, 2.5), Vector3.new(0, 1.25, 0), "berry_red")
	add(t, "BandA", "Block", Vector3.new(2.75, 0.5, 2.75), Vector3.new(0, 0.5, 0), "wood_dark")
	add(t, "BandB", "Block", Vector3.new(2.75, 0.5, 2.75), Vector3.new(0, 2.0, 0), "wood_dark")
	return t
end

BUILD.cone = function(_o)
	local t = new("cone", 2.5, 1.2)
	add(t, "Base", "Block", Vector3.new(2.25, 0.25, 2.25), Vector3.new(0, 0.125, 0), "black")
	add(t, "Low", "Block", Vector3.new(1.5, 0.75, 1.5), Vector3.new(0, 0.625, 0), "orange")
	add(t, "Band", "Block", Vector3.new(1.25, 0.5, 1.25), Vector3.new(0, 1.25, 0), "white")
	add(t, "Top", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, 1.875, 0), "orange")
	return t
end

BUILD.coin = function(_o)
	local t = new("coin", 2, 0.9)
	add(t, "Disc", "Cylinder", Vector3.new(0.5, 1.75, 1.75), Vector3.new(0, 1, 0), "gold")
	add(t, "Mark", "Block", Vector3.new(0.75, 0.75, 0.25), Vector3.new(0, 1, 0.25), "yellow")
	return t
end

BUILD.bomb = function(_o)
	local t = new("bomb", 2.5, 1)
	add(t, "Body", "Ball", Vector3.new(1.75, 1.75, 1.75), Vector3.new(0, 0.875, 0), "black")
	add(t, "Cap", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 1.85, 0), "steel_dark")
	add(t, "Fuse", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0.125, 2.2, 0), "wood")
	add(t, "Spark", "Ball", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0.25, 2.55, 0), "yellow", nil, true)
	return t
end

BUILD.fish = function(_o)
	local t = new("fish", 1.25, 1.2)
	add(t, "Body", "Block", Vector3.new(0.75, 1.0, 1.75), Vector3.new(0, 0.625, 0), "orange")
	add(t, "Belly", "Block", Vector3.new(0.5, 0.25, 1.25), Vector3.new(0, 0.125, 0.125), "cream")
	add(t, "Tail", "Wedge", Vector3.new(0.25, 1.0, 0.75), Vector3.new(0, 0.625, -1.25), "orange", CFrame.Angles(0, math.pi, 0))
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0.4, 0.75, 0.55), "black")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(-0.4, 0.75, 0.55), "black")
	return t
end

BUILD.jelly = function(_o)
	local t = new("jelly", 2, 1)
	add(t, "Dome", "Ball", Vector3.new(1.75, 1.25, 1.75), Vector3.new(0, 1.5, 0), "pink")
	add(t, "TentA", "Block", Vector3.new(0.25, 1.0, 0.25), Vector3.new(-0.5, 0.5, 0), "purple")
	add(t, "TentB", "Block", Vector3.new(0.25, 1.0, 0.25), Vector3.new(0.5, 0.5, 0), "purple")
	add(t, "TentC", "Block", Vector3.new(0.25, 1.0, 0.25), Vector3.new(0, 0.5, 0.5), "purple")
	return t
end

BUILD.alien = function(_o)
	local t = new("alien", 2.75, 1)
	add(t, "Body", "Block", Vector3.new(1.25, 1.25, 1.0), Vector3.new(0, 0.625, 0), "green")
	add(t, "Head", "Block", Vector3.new(1.75, 1.25, 1.5), Vector3.new(0, 1.875, 0), "green")
	add(t, "EyeL", "Block", Vector3.new(0.5, 0.5, 0.25), Vector3.new(-0.4, 2.0, 0.75), "black")
	add(t, "EyeR", "Block", Vector3.new(0.5, 0.5, 0.25), Vector3.new(0.4, 2.0, 0.75), "black")
	add(t, "AntL", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(-0.5, 2.75, 0), "leaf_dark")
	add(t, "AntR", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0.5, 2.75, 0), "leaf_dark")
	return t
end

BUILD.rocket = function(_o)
	local t = new("rocket", 3, 1)
	add(t, "Body", "Block", Vector3.new(1.0, 2.0, 1.0), Vector3.new(0, 1.25, 0), "white")
	add(t, "Nose", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 2.5, 0), "berry_red")
	add(t, "Window", "Block", Vector3.new(0.5, 0.5, 0.25), Vector3.new(0, 1.6, 0.5), "screen_on")
	add(t, "FinL", "Block", Vector3.new(0.5, 0.75, 0.25), Vector3.new(-0.7, 0.4, 0), "berry_red")
	add(t, "FinR", "Block", Vector3.new(0.5, 0.75, 0.25), Vector3.new(0.7, 0.4, 0), "berry_red")
	return t
end

BUILD.sprout = function(_o)
	local t = new("sprout", 2.25, 0.9)
	add(t, "Pot", "Block", Vector3.new(1.25, 1.0, 1.25), Vector3.new(0, 0.5, 0), "pot")
	add(t, "Soil", "Block", Vector3.new(1.0, 0.25, 1.0), Vector3.new(0, 1.0, 0), "wood_dark")
	add(t, "Stem", "Block", Vector3.new(0.25, 0.75, 0.25), Vector3.new(0, 1.5, 0), "grass_dark")
	add(t, "LeafL", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(-0.3, 1.75, 0), "grass_dark")
	add(t, "LeafR", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(0.3, 2.0, 0), "grass_dark")
	return t
end

BUILD.flower = function(_o)
	local t = new("flower", 2.75, 0.9)
	add(t, "Pot", "Block", Vector3.new(1.25, 1.0, 1.25), Vector3.new(0, 0.5, 0), "pot")
	add(t, "Stem", "Block", Vector3.new(0.25, 1.0, 0.25), Vector3.new(0, 1.5, 0), "leaf")
	add(t, "Petals", "Block", Vector3.new(1.25, 0.5, 1.25), Vector3.new(0, 2.25, 0), "yellow")
	add(t, "Middle", "Block", Vector3.new(0.5, 0.75, 0.5), Vector3.new(0, 2.3, 0), "berry_red")
	add(t, "Leaf", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(0.3, 1.5, 0), "leaf")
	return t
end

BUILD.zombie = function(_o)
	local t = new("zombie", 3.25, 1)
	add(t, "Torso", "Block", Vector3.new(1.25, 1.25, 0.75), Vector3.new(0, 0.625, 0), "steel_dark")
	add(t, "Head", "Block", Vector3.new(1.5, 1.25, 1.25), Vector3.new(0, 1.875, 0), "green")
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(-0.35, 2.0, 0.625), "berry_red")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0.35, 2.0, 0.625), "berry_red")
	add(t, "ArmL", "Block", Vector3.new(0.375, 0.375, 1.25), Vector3.new(-0.8, 1.0, 0.5), "green")
	add(t, "ArmR", "Block", Vector3.new(0.375, 0.375, 1.25), Vector3.new(0.8, 1.0, 0.5), "green")
	add(t, "Hair", "Block", Vector3.new(1.5, 0.25, 1.25), Vector3.new(0, 2.6, 0), "leaf_dark")
	return t
end

BUILD.kid = function(_o)
	local t = new("kid", 2.75, 0.8)
	add(t, "Legs", "Block", Vector3.new(0.75, 0.75, 0.5), Vector3.new(0, 0.375, 0), "jeans")
	add(t, "Shirt", "Block", Vector3.new(1.0, 0.75, 0.625), Vector3.new(0, 1.125, 0), "yellow")
	add(t, "Head", "Block", Vector3.new(1.0, 1.0, 1.0), Vector3.new(0, 2.0, 0), "skin2")
	add(t, "Hair", "Block", Vector3.new(1.125, 0.375, 1.125), Vector3.new(0, 2.55, -0.05), "hair_brown")
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(-0.25, 2.05, 0.5), "black")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0.25, 2.05, 0.5), "black")
	return t
end

BUILD.fruit = function(_o)
	local t = new("fruit", 2, 1)
	add(t, "Body", "Ball", Vector3.new(1.75, 1.75, 1.75), Vector3.new(0, 0.875, 0), "leaf")
	add(t, "Stripe", "Block", Vector3.new(0.25, 1.5, 1.75), Vector3.new(0, 0.875, 0), "leaf_dark")
	add(t, "Stem", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0, 1.9, 0), "wood_dark")
	return t
end

-- half a melon flying off a cut: red inside, green rind
BUILD.half = function(_o)
	local t = new("half", 1.25, 1)
	add(t, "Rind", "Block", Vector3.new(1.5, 0.5, 1.5), Vector3.new(0, 0.25, 0), "leaf_dark")
	add(t, "Flesh", "Block", Vector3.new(1.25, 0.25, 1.25), Vector3.new(0, 0.625, 0), "berry_red")
	add(t, "Seed", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0.25, 0.8, 0.1), "black")
	return t
end

BUILD.rock = function(_o)
	local t = new("rock", 1.75, 1.3)
	add(t, "Big", "Block", Vector3.new(2.0, 1.25, 1.75), Vector3.new(0, 0.625, 0), "steel")
	add(t, "Top", "Block", Vector3.new(1.25, 0.5, 1.25), Vector3.new(-0.2, 1.5, 0), "steel")
	add(t, "Chip", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0.85, 0.375, 0.5), "steel_dark")
	return t
end

BUILD.cactus = function(_o)
	local t = new("cactus", 3, 1)
	add(t, "Trunk", "Block", Vector3.new(0.75, 3.0, 0.75), Vector3.new(0, 1.5, 0), "leaf")
	add(t, "ArmL", "Block", Vector3.new(0.75, 0.5, 0.5), Vector3.new(-0.7, 1.4, 0), "leaf")
	add(t, "ArmLU", "Block", Vector3.new(0.5, 0.75, 0.5), Vector3.new(-0.95, 1.9, 0), "leaf")
	add(t, "ArmR", "Block", Vector3.new(0.75, 0.5, 0.5), Vector3.new(0.7, 1.9, 0), "leaf")
	add(t, "ArmRU", "Block", Vector3.new(0.5, 0.75, 0.5), Vector3.new(0.95, 2.4, 0), "leaf")
	add(t, "Bloom", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 3.125, 0), "pink")
	return t
end

BUILD.cat = function(_o)
	local t = new("cat", 2.75, 1.5)
	add(t, "Body", "Block", Vector3.new(1.75, 1.25, 2.25), Vector3.new(0, 0.625, -0.2), "orange")
	add(t, "Head", "Block", Vector3.new(1.75, 1.5, 1.5), Vector3.new(0, 1.75, 0.6), "orange")
	add(t, "EarL", "Block", Vector3.new(0.5, 0.5, 0.375), Vector3.new(-0.6, 2.7, 0.6), "orange")
	add(t, "EarR", "Block", Vector3.new(0.5, 0.5, 0.375), Vector3.new(0.6, 2.7, 0.6), "orange")
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.375, 0.25), Vector3.new(-0.4, 1.85, 1.35), "black")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.375, 0.25), Vector3.new(0.4, 1.85, 1.35), "black")
	add(t, "Nose", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0, 1.5, 1.4), "pink")
	add(t, "Tail", "Block", Vector3.new(0.375, 1.5, 0.375), Vector3.new(0.5, 1.2, -1.3), "orange")
	return t
end

BUILD.slime = function(_o)
	local t = new("slime", 2.25, 1.4)
	add(t, "Body", "Ball", Vector3.new(2.5, 2.0, 2.5), Vector3.new(0, 1.0, 0), "green")
	add(t, "Shine", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(-0.5, 1.75, 0.75), "white")
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(-0.4, 1.1, 1.15), "black")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0.4, 1.1, 1.15), "black")
	return t
end

BUILD.ghost = function(_o)
	local t = new("ghost", 4.5, 1.6)
	add(t, "Body", "Block", Vector3.new(2.5, 2.5, 2.0), Vector3.new(0, 1.75, 0), "white")
	add(t, "Head", "Ball", Vector3.new(2.5, 2.25, 2.25), Vector3.new(0, 3.0, 0), "white")
	add(t, "SkirtL", "Block", Vector3.new(0.75, 0.5, 2.0), Vector3.new(-0.875, 0.25, 0), "white")
	add(t, "SkirtR", "Block", Vector3.new(0.75, 0.5, 2.0), Vector3.new(0.875, 0.25, 0), "white")
	local l = add(t, "EyeL", "Block", Vector3.new(0.5, 0.75, 0.25), Vector3.new(-0.5, 3.0, 1.1), "black")
	local r = add(t, "EyeR", "Block", Vector3.new(0.5, 0.75, 0.25), Vector3.new(0.5, 3.0, 1.1), "black")
	add(t, "Mouth", "Block", Vector3.new(0.75, 0.5, 0.25), Vector3.new(0, 2.25, 1.05), "black")
	l:SetAttribute("Keep", true)
	r:SetAttribute("Keep", true)
	return t
end

BUILD.ball = function(_o)
	local t = new("ball", 1.5, 0.8)
	add(t, "Ball", "Ball", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 0.75, 0), "white")
	add(t, "PatchA", "Block", Vector3.new(0.5, 0.5, 0.25), Vector3.new(0, 0.85, 0.65), "black")
	add(t, "PatchB", "Block", Vector3.new(0.25, 0.5, 0.5), Vector3.new(0.65, 0.6, 0), "black")
	return t
end

BUILD.pancake = function(_o)
	local t = new("pancake", 0.5, 1.1)
	add(t, "Cake", "Cylinder", Vector3.new(0.5, 2.0, 2.0), Vector3.new(0, 0.25, 0), "rug", UPRIGHT)
	add(t, "Butter", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 0.6, 0), "yellow")
	return t
end

BUILD.pan = function(_o)
	local t = new("pan", 0.75, 1.5)
	add(t, "Pan", "Cylinder", Vector3.new(0.5, 2.75, 2.75), Vector3.new(0, 0.25, 0), "black", UPRIGHT)
	add(t, "Handle", "Block", Vector3.new(2.0, 0.25, 0.5), Vector3.new(2.25, 0.35, 0), "wood_dark")
	return t
end

BUILD.basket = function(_o)
	local t = new("basket", 1, 1.2)
	add(t, "Floor", "Block", Vector3.new(2.0, 0.25, 1.5), Vector3.new(0, 0.125, 0), "wood_dark")
	add(t, "Front", "Block", Vector3.new(2.0, 1.0, 0.25), Vector3.new(0, 0.5, 0.625), "wood")
	add(t, "Back", "Block", Vector3.new(2.0, 1.0, 0.25), Vector3.new(0, 0.5, -0.625), "wood")
	add(t, "Left", "Block", Vector3.new(0.25, 1.0, 1.5), Vector3.new(-0.875, 0.5, 0), "wood")
	add(t, "Right", "Block", Vector3.new(0.25, 1.0, 1.5), Vector3.new(0.875, 0.5, 0), "wood")
	return t
end

BUILD.soldier = function(o)
	local t = new("soldier", 2.25, 0.6)
	add(t, "Legs", "Block", Vector3.new(0.75, 0.75, 0.5), Vector3.new(0, 0.375, 0), "black")
	add(t, "Coat", "Block", Vector3.new(0.75, 0.75, 0.5), Vector3.new(0, 1.125, 0), o.color or "berry_red")
	add(t, "Head", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 1.75, 0), "skin2")
	add(t, "Hat", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 2.25, 0), "black")
	return t
end

-- Spot it's suspects: a coat, a hat with a band, a face (opts.color the coat, opts.alt the band)
BUILD.suspect = function(o)
	local t = new("suspect", 2.75, 0.7)
	add(t, "Coat", "Block", Vector3.new(1.0, 1.25, 0.75), Vector3.new(0, 0.625, 0), o.color or "wood")
	add(t, "Head", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, 1.625, 0), "skin2")
	add(t, "Brim", "Block", Vector3.new(1.25, 0.25, 1.25), Vector3.new(0, 2.125, 0), o.alt or "wood_dark")
	add(t, "Crown", "Block", Vector3.new(0.75, 0.5, 0.75), Vector3.new(0, 2.5, 0), o.alt or "wood_dark")
	add(t, "Band", "Block", Vector3.new(0.875, 0.25, 0.875), Vector3.new(0, 2.375, 0), o.color or "wood")
	return t
end

BUILD.gem = function(o)
	local t = new("gem", 1.25, 0.6)
	add(t, "Gem", "Block", Vector3.new(0.875, 0.875, 0.875), Vector3.new(0, 0.6, 0), o.color or "pink", CFrame.Angles(0, math.rad(45), math.rad(45)), true)
	return t
end

BUILD.orb = function(_o)
	local t = new("orb", 1, 0.5)
	add(t, "Orb", "Ball", Vector3.new(1.0, 1.0, 1.0), Vector3.new(0, 0.5, 0), "purple", nil, true)
	return t
end

BUILD.star = function(_o)
	local t = new("star", 0.75, 0.4)
	add(t, "Star", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.4, 0), "gold", CFrame.Angles(0, math.rad(45), math.rad(45)), true)
	return t
end

BUILD.flag = function(_o)
	local t = new("flag", 3, 0.5)
	add(t, "Pole", "Block", Vector3.new(0.25, 3.0, 0.25), Vector3.new(0, 1.5, 0), "steel")
	add(t, "Cloth", "Block", Vector3.new(1.25, 0.75, 0.25), Vector3.new(0.7, 2.5, 0), "berry_red")
	add(t, "Foot", "Block", Vector3.new(0.75, 0.25, 0.75), Vector3.new(0, 0.125, 0), "steel_dark")
	return t
end

-- Simon's pads (opts.color): a slab that glows when lit (MicroStage sets Neon)
BUILD.pad = function(o)
	local t = new("pad", 0.5, 1.6)
	add(t, "Slab", "Block", Vector3.new(2.75, 0.5, 2.75), Vector3.new(0, 0.25, 0), o.color or "blue")
	return t
end

-- Match's shapes (opts.flag: which one): a cube, a ball, a drum, a wedge, a tower, a cross
BUILD.shape = function(o)
	local t = new("shape", 1.75, 1)
	local c = o.color or "blue"
	local k = o.alt or "cube"
	if k == "ball" then
		add(t, "A", "Ball", Vector3.new(1.75, 1.75, 1.75), Vector3.new(0, 0.875, 0), c)
	elseif k == "drum" then
		add(t, "A", "Cylinder", Vector3.new(1.5, 1.75, 1.75), Vector3.new(0, 0.75, 0), c, UPRIGHT)
	elseif k == "wedge" then
		add(t, "A", "Wedge", Vector3.new(1.75, 1.75, 1.75), Vector3.new(0, 0.875, 0), c)
	elseif k == "tower" then
		add(t, "A", "Block", Vector3.new(1.0, 2.25, 1.0), Vector3.new(0, 1.125, 0), c)
		add(t, "B", "Block", Vector3.new(1.5, 0.5, 1.5), Vector3.new(0, 0.25, 0), c)
	elseif k == "cross" then
		add(t, "A", "Block", Vector3.new(0.75, 1.75, 0.75), Vector3.new(0, 0.875, 0), c)
		add(t, "B", "Block", Vector3.new(1.75, 0.75, 0.75), Vector3.new(0, 0.875, 0), c)
	else
		add(t, "A", "Block", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 0.75, 0), c)
	end
	return t
end
MicroModels.SHAPES = { "cube", "ball", "drum", "wedge", "tower", "cross" }

BUILD.kart = function(o)
	local t = new("kart", 1.5, 1.8)
	add(t, "Body", "Block", Vector3.new(2.5, 0.75, 3.25), Vector3.new(0, 0.75, 0), o.color or "berry_red")
	add(t, "Nose", "Block", Vector3.new(2.0, 0.5, 0.75), Vector3.new(0, 0.6, 1.9), "white")
	add(t, "Seat", "Block", Vector3.new(1.75, 1.0, 0.5), Vector3.new(0, 1.4, -1.25), "black")
	add(t, "WheelFL", "Block", Vector3.new(0.5, 0.75, 0.75), Vector3.new(-1.4, 0.375, 1.1), "black")
	add(t, "WheelFR", "Block", Vector3.new(0.5, 0.75, 0.75), Vector3.new(1.4, 0.375, 1.1), "black")
	add(t, "WheelBL", "Block", Vector3.new(0.5, 0.75, 0.75), Vector3.new(-1.4, 0.375, -1.1), "black")
	add(t, "WheelBR", "Block", Vector3.new(0.5, 0.75, 0.75), Vector3.new(1.4, 0.375, -1.1), "black")
	return t
end

BUILD.goal = function(_o)
	local t = new("goal", 4.5, 4)
	add(t, "PostL", "Block", Vector3.new(0.5, 4.0, 0.5), Vector3.new(-3.75, 2.0, 0), "white")
	add(t, "PostR", "Block", Vector3.new(0.5, 4.0, 0.5), Vector3.new(3.75, 2.0, 0), "white")
	add(t, "Bar", "Block", Vector3.new(8.0, 0.5, 0.5), Vector3.new(0, 4.25, 0), "white")
	add(t, "Net", "Block", Vector3.new(7.0, 3.75, 0.25), Vector3.new(0, 1.9, -2.0), "plastic")
	add(t, "Roof", "Block", Vector3.new(7.0, 0.25, 2.0), Vector3.new(0, 3.9, -1.0), "plastic")
	add(t, "SideL", "Block", Vector3.new(0.25, 3.75, 2.0), Vector3.new(-3.5, 1.9, -1.0), "plastic")
	add(t, "SideR", "Block", Vector3.new(0.25, 3.75, 2.0), Vector3.new(3.5, 1.9, -1.0), "plastic")
	return t
end

BUILD.pedestal = function(_o)
	local t = new("pedestal", 1.25, 1)
	add(t, "Column", "Block", Vector3.new(1.5, 1.0, 1.5), Vector3.new(0, 0.5, 0), "white")
	add(t, "Top", "Block", Vector3.new(2.0, 0.25, 2.0), Vector3.new(0, 1.125, 0), "plastic_dark")
	return t
end

-- Racing's lane marks and the runners' ground specks: parts spaced along +Z (placed facing the viewer: down the screen)
BUILD.dashes = function(_o)
	local t = new("dashes", 0.1, 0.3)
	for i = -2, 2 do
		add(t, "D" .. (i + 3), "Block", Vector3.new(0.5, 0.25, 2.0), Vector3.new(0, 0.05, i * 6), "white")
	end
	return t
end

BUILD.specks = function(o)
	local t = new("specks", 0.1, 0.3)
	for i = -3, 3 do
		add(t, "S" .. (i + 4), "Block", Vector3.new(0.25, 0.25, if i % 2 == 0 then 0.5 else 0.25), Vector3.new((i * 7) % 3 - 1, 0.1, i * 4), o.color or "wood_dark")
	end
	return t
end

-- Rhythm's lanes: a dotted strip of tiles along +Z
BUILD.lane = function(o)
	local t = new("lane", 0.1, 0.5)
	for i = -4, 3 do
		add(t, "T" .. (i + 5), "Block", Vector3.new(1.75, 0.25, 1.75), Vector3.new(0, 0.05, i * 2.5), o.color or "plastic_dark")
	end
	return t
end

------------------------------------------------------------------ the stages' ambient life (UI/MicroStage)
-- birds and bats: a body and two wings ("WingL", "WingR": MicroStage flaps them)
BUILD.bird = function(o)
	local t = new("bird", 0.6, 0.6)
	local c = o.color or "white"
	add(t, "Body", "Block", Vector3.new(0.5, 0.5, 1.0), Vector3.new(0, 0.25, 0), c)
	add(t, "Head", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.5, 0.6), c)
	add(t, "Beak", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0, 0.45, 0.95), o.alt or "orange")
	add(t, "WingL", "Block", Vector3.new(1.0, 0.25, 0.5), Vector3.new(-0.7, 0.4, 0), c)
	add(t, "WingR", "Block", Vector3.new(1.0, 0.25, 0.5), Vector3.new(0.7, 0.4, 0), c)
	return t
end

BUILD.butterfly = function(o)
	local t = new("butterfly", 0.4, 0.4)
	add(t, "Body", "Block", Vector3.new(0.25, 0.25, 0.5), Vector3.new(0, 0.15, 0), "black")
	add(t, "WingL", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(-0.35, 0.2, 0), o.color or "yellow")
	add(t, "WingR", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0.35, 0.2, 0), o.color or "yellow")
	return t
end

BUILD.ufo = function(_o)
	local t = new("ufo", 1.5, 2)
	add(t, "Disc", "Block", Vector3.new(3.5, 0.5, 3.5), Vector3.new(0, 0.5, 0), "steel")
	add(t, "Dome", "Ball", Vector3.new(1.75, 1.25, 1.75), Vector3.new(0, 1.1, 0), "screen_on")
	add(t, "Light", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 0.125, 0), "screen_code", nil, true)
	return t
end

-- a small light that blinks (MicroStage toggles it) and a flame that flickers
BUILD.light = function(o)
	local t = new("light", 0.5, 0.25)
	add(t, "Light", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.25, 0), o.color or "berry_red", nil, true)
	return t
end

BUILD.flame = function(_o)
	local t = new("flame", 1, 0.3)
	add(t, "Outer", "Block", Vector3.new(0.5, 0.75, 0.5), Vector3.new(0, 0.375, 0), "orange", nil, true)
	add(t, "Core", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0, 0.3, 0.15), "yellow", nil, true)
	return t
end

BUILD.yarn = function(_o)
	local t = new("yarn", 1, 0.5)
	add(t, "Ball", "Ball", Vector3.new(1.0, 1.0, 1.0), Vector3.new(0, 0.5, 0), "pink")
	add(t, "Wrap", "Block", Vector3.new(1.05, 0.25, 0.25), Vector3.new(0, 0.6, 0), "berry_red")
	add(t, "Thread", "Block", Vector3.new(0.25, 0.25, 1.5), Vector3.new(0.3, 0.1, -1.0), "pink")
	return t
end

BUILD.plane = function(_o)
	local t = new("plane", 0.5, 0.6)
	add(t, "WingL", "Wedge", Vector3.new(0.5, 0.25, 1.25), Vector3.new(-0.3, 0.2, 0), "white")
	add(t, "WingR", "Wedge", Vector3.new(0.5, 0.25, 1.25), Vector3.new(0.3, 0.2, 0), "white")
	add(t, "Keel", "Block", Vector3.new(0.25, 0.25, 1.0), Vector3.new(0, 0.05, -0.1), "paper")
	return t
end

BUILD.book = function(_o)
	local t = new("book", 0.5, 0.6)
	add(t, "Cover", "Block", Vector3.new(1.25, 0.25, 1.0), Vector3.new(0, 0.125, 0), "berry_red")
	add(t, "Pages", "Block", Vector3.new(1.0, 0.25, 0.875), Vector3.new(0, 0.3, 0), "paper")
	return t
end

BUILD.drone = function(_o)
	local t = new("drone", 0.75, 1)
	add(t, "Body", "Block", Vector3.new(1.0, 0.5, 1.0), Vector3.new(0, 0.25, 0), "steel_dark")
	add(t, "Eye", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0, 0.25, 0.55), "screen_code", nil, true)
	add(t, "WingL", "Block", Vector3.new(0.75, 0.25, 0.25), Vector3.new(-0.85, 0.5, 0), "steel")
	add(t, "WingR", "Block", Vector3.new(0.75, 0.25, 0.25), Vector3.new(0.85, 0.5, 0), "steel")
	return t
end

BUILD.crab = function(_o)
	local t = new("crab", 0.75, 0.7)
	add(t, "Shell", "Block", Vector3.new(1.25, 0.5, 0.75), Vector3.new(0, 0.375, 0), "berry_red")
	add(t, "ClawL", "Block", Vector3.new(0.375, 0.375, 0.375), Vector3.new(-0.8, 0.45, 0.35), "berry_red")
	add(t, "ClawR", "Block", Vector3.new(0.375, 0.375, 0.375), Vector3.new(0.8, 0.45, 0.35), "berry_red")
	add(t, "EyeL", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(-0.25, 0.75, 0.25), "black")
	add(t, "EyeR", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0.25, 0.75, 0.25), "black")
	return t
end

-- The street's cars (Controllers/StreetLife): a body, a cabin with windows, wheels, lights (opts.color the paint)
BUILD.car = function(o)
	local t = new("car", 2.5, 2.4)
	local c = o.color or "berry_red"
	add(t, "Body", "Block", Vector3.new(2.5, 1.0, 4.5), Vector3.new(0, 0.85, 0), c)
	add(t, "Cabin", "Block", Vector3.new(2.25, 1.0, 2.5), Vector3.new(0, 1.85, -0.25), c)
	add(t, "Front", "Block", Vector3.new(2.0, 0.75, 0.25), Vector3.new(0, 1.85, 1.05), "window")
	add(t, "SideL", "Block", Vector3.new(0.25, 0.75, 1.75), Vector3.new(-1.05, 1.85, -0.25), "window")
	add(t, "SideR", "Block", Vector3.new(0.25, 0.75, 1.75), Vector3.new(1.05, 1.85, -0.25), "window")
	add(t, "LampL", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(-0.8, 0.95, 2.2), "yellow", nil, true)
	add(t, "LampR", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(0.8, 0.95, 2.2), "yellow", nil, true)
	add(t, "TailL", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(-0.8, 0.95, -2.2), "berry_red", nil, true)
	add(t, "TailR", "Block", Vector3.new(0.5, 0.25, 0.25), Vector3.new(0.8, 0.95, -2.2), "berry_red", nil, true)
	for i, w in { { -1.2, 1.4 }, { 1.2, 1.4 }, { -1.2, -1.4 }, { 1.2, -1.4 } } do
		add(t, "Wheel" .. i, "Block", Vector3.new(0.5, 0.75, 0.75), Vector3.new(w[1], 0.375, w[2]), "black")
	end
	return t
end

-- Disco and stage light on the floor: a flat glowing tile (opts.color)
BUILD.spot = function(o)
	local t = new("spot", 0.1, 1.4)
	add(t, "Tile", "Block", Vector3.new(2.5, 0.25, 2.5), Vector3.new(0, 0.05, 0), o.color or "yellow", nil, true)
	return t
end

------------------------------------------------------------------ the party rounds' things (UI/MicroArena)
-- an arrow flying along +Z, at a jumpable height
BUILD.arrow = function(o)
	local t = new("arrow", 1, 0.6)
	add(t, "Shaft", "Block", Vector3.new(0.25, 0.25, 2.25), Vector3.new(0, 0.75, 0), "wood")
	add(t, "Head", "Block", Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 0.75, 1.25), "steel", CFrame.Angles(0, math.rad(45), 0))
	add(t, "Fletch", "Block", Vector3.new(0.75, 0.25, 0.5), Vector3.new(0, 0.75, -1.0), o.color or "berry_red")
	return t
end

-- a throwing star spinning flat (MicroArena turns it)
BUILD.shuriken = function(_o)
	local t = new("shuriken", 1, 0.8)
	add(t, "A", "Block", Vector3.new(1.75, 0.25, 0.5), Vector3.new(0, 0.75, 0), "steel")
	add(t, "B", "Block", Vector3.new(0.5, 0.25, 1.75), Vector3.new(0, 0.75, 0), "steel")
	add(t, "Hub", "Block", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.75, 0), "steel_dark")
	return t
end

-- a meteor: a rock on fire
BUILD.meteor = function(_o)
	local t = new("meteor", 2, 1.1)
	add(t, "Rock", "Ball", Vector3.new(1.75, 1.75, 1.75), Vector3.new(0, 0.875, 0), "steel_dark")
	add(t, "Lump", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0.5, 1.25, 0.25), "steel")
	add(t, "Fire", "Ball", Vector3.new(1.25, 1.25, 1.25), Vector3.new(-0.25, 1.75, -0.25), "orange", nil, true)
	add(t, "Tip", "Ball", Vector3.new(0.75, 0.75, 0.75), Vector3.new(-0.5, 2.4, -0.5), "yellow", nil, true)
	return t
end

-- a ring on the floor (opts.color, neon): twelve short bars round a radius of 2.5 studs
BUILD.ring = function(o)
	local t = new("ring", 0.25, 2.5)
	for i = 1, 12 do
		local a = (i - 0.5) / 12 * math.pi * 2
		add(t, "R" .. i, "Block", Vector3.new(1.25, 0.25, 0.5), Vector3.new(math.cos(a) * 2.5, 0.15, math.sin(a) * 2.5), o.color or "yellow", CFrame.Angles(0, -a + math.pi / 2, 0), true)
	end
	return t
end

-- the pivot a sweeping beam turns round
BUILD.pillar = function(o)
	local t = new("pillar", 2, 1)
	add(t, "Base", "Cylinder", Vector3.new(0.5, 2.25, 2.25), Vector3.new(0, 0.25, 0), "steel_dark", UPRIGHT)
	add(t, "Post", "Cylinder", Vector3.new(1.5, 1.5, 1.5), Vector3.new(0, 1.25, 0), o.color or "steel", UPRIGHT)
	add(t, "Cap", "Ball", Vector3.new(1, 1, 1), Vector3.new(0, 2.1, 0), o.alt or "yellow", nil, true)
	return t
end

------------------------------------------------------------------ what the avatar holds (origin: the hand)
BUILD.hat = function(_o)
	local t = new("hat", 1.75, 1)
	add(t, "Brim", "Block", Vector3.new(2.0, 0.25, 2.0), Vector3.new(0, 0.125, 0), "purple")
	add(t, "Low", "Block", Vector3.new(1.25, 0.75, 1.25), Vector3.new(0, 0.625, 0), "purple")
	add(t, "High", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0.1, 1.25, 0), "purple")
	add(t, "Star", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0, 0.75, 0.65), "gold")
	return t
end

BUILD.sword = function(_o)
	local t = new("sword", 2.5, 0.3)
	add(t, "Blade", "Block", Vector3.new(0.25, 2.0, 0.25), Vector3.new(0, 1.35, 0), "white")
	add(t, "Guard", "Block", Vector3.new(0.75, 0.25, 0.25), Vector3.new(0, 0.3, 0), "gold")
	add(t, "Grip", "Block", Vector3.new(0.25, 0.5, 0.25), Vector3.new(0, 0, 0), "wood_dark")
	return t
end

BUILD.hammer = function(_o)
	local t = new("hammer", 2, 0.5)
	add(t, "Grip", "Block", Vector3.new(0.25, 1.5, 0.25), Vector3.new(0, 0.6, 0), "wood")
	add(t, "Head", "Block", Vector3.new(1.0, 0.5, 0.5), Vector3.new(0, 1.4, 0), "steel_dark")
	return t
end

BUILD.can = function(_o)
	local t = new("can", 1, 0.5)
	add(t, "Can", "Block", Vector3.new(0.75, 0.75, 0.75), Vector3.new(0, 0.2, 0.2), "blue")
	add(t, "Spout", "Block", Vector3.new(0.25, 0.25, 0.75), Vector3.new(0, 0.35, 0.8), "blue")
	return t
end

BUILD.blaster = function(_o)
	local t = new("blaster", 0.75, 0.5)
	add(t, "Body", "Block", Vector3.new(0.5, 0.5, 1.0), Vector3.new(0, 0.1, 0.3), "steel")
	add(t, "Tip", "Block", Vector3.new(0.25, 0.25, 0.25), Vector3.new(0, 0.1, 0.9), "screen_code", nil, true)
	return t
end

------------------------------------------------------------------ API
-- A plain box of any size (the stack's floors and their cut-off pieces, a laser's beam), its origin the middle of its
-- bottom face; `band` puts a row of lit windows round it.
function MicroModels.slab(size: Vector3, color: string, band: string?, neon: boolean?): Thing
	local t = new("slab", size.Y, math.max(size.X, size.Z) / 2)
	add(t, "Body", "Block", size, Vector3.new(0, size.Y / 2, 0), color, nil, neon)
	if band and size.Y >= 0.75 then
		add(t, "Band", "Block", Vector3.new(size.X + 0.05, 0.25, size.Z + 0.05), Vector3.new(0, size.Y / 2, 0), band)
	end
	return t
end

-- A floor of n x n tiles in one thing (the party rounds' tiles): parts "T1" .. "Tn*n" row by row, `step` studs
-- apart, each `size` wide and `h` high, centred on the origin. A tile moves with t.rest and recolours by its part.
function MicroModels.grid(n: number, step: number, size: number, h: number, color: string): Thing
	local t = new("grid", h, n * step / 2)
	for r = 1, n do
		for c = 1, n do
			local x = (c - (n + 1) / 2) * step
			local z = (r - (n + 1) / 2) * step
			add(t, "T" .. ((r - 1) * n + c), "Block", Vector3.new(size, h, size), Vector3.new(x, h / 2, z), color)
		end
	end
	return t
end

-- A ring of n bars round `radius` on the floor, alternating colours a and b (a ring to stay in, a kerb).
function MicroModels.hoop(radius: number, n: number, a: string, b: string, neon: boolean?): Thing
	local t = new("hoop", 0.5, radius)
	local len = radius * 2 * math.pi / n + 0.1
	for i = 1, n do
		local an = (i - 0.5) / n * math.pi * 2
		add(t, "H" .. i, "Block", Vector3.new(len, 0.5, 0.75), Vector3.new(math.cos(an) * radius, 0.25, math.sin(an) * radius), if i % 2 == 0 then b else a, CFrame.Angles(0, -an + math.pi / 2, 0), neon)
	end
	return t
end

function MicroModels.build(kind: string, opts: Opts?): Thing
	local fn = BUILD[kind]
	if fn == nil then
		error("MicroModels: no thing " .. kind)
	end
	return fn(opts or {})
end

function MicroModels.has(kind: string): boolean
	return BUILD[kind] ~= nil
end

function MicroModels.place(t: Thing, cf: CFrame)
	for name, p in t.parts do
		p.CFrame = cf * t.rest[name]
	end
end

-- Its built sizes and offsets times k about the origin (a squash and stretch: k per axis; Vector3.one: as built).
function MicroModels.scale(t: Thing, k: Vector3)
	for name, p in t.parts do
		local r = t.baseRest[name]
		local s = t.baseSize[name]
		local sz = Vector3.new(math.max(0.05, s.X * k.X), math.max(0.05, s.Y * k.Y), math.max(0.05, s.Z * k.Z))
		if p.Size ~= sz then
			p.Size = sz
		end
		t.sizes[name] = sz
		t.rest[name] = CFrame.new(r.Position * k) * r.Rotation
	end
end

-- Every part (but the "Keep" ones) in one colour, or back to its own (nil).
function MicroModels.recolor(t: Thing, color: string?)
	for name, p in t.parts do
		if color == nil then
			p.Color = t.colors[name]
		elseif p:GetAttribute("Keep") ~= true then
			p.Color = Blocks.color(color)
		end
	end
end

-- Hidden things are not drawn (the pixel filter skips fully transparent parts).
function MicroModels.show(t: Thing, on: boolean)
	for _, p in t.parts do
		p.Transparency = if on then 0 else 1
	end
end

return MicroModels
