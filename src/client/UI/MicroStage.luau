--!strict
-- A microgame's 3D stage (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): a little diorama room, themed by the idea (a
-- kitchen, a dungeon, a beach, a graveyard...), built from parts far from the street (Z = 9000) and shown full screen
-- by the pixel filter like the office: the same orthographic 2:1 camera, toon bands, palette, sun shadows and 1 px ink
-- outline. The player's own founder (their look) stands in it and plays; the things that move are dynamic models the
-- renderer draws every tick, with blob shadows on the floor.
--
-- Stage space: (u, v, y) studs from the middle of the room's floor: u to the screen's right, v toward the viewer
-- (down the screen), y up from the floor's top. The room is world-aligned (its floor a diamond on screen, its two back
-- walls along the far edges), so everything sits on the iso grid with clean 2:1 edges.
--   MicroStage.open(variant) -> Stage      (builds the set, takes the camera: Stage.ready() once its picture is baked)
--   stage.at(u, v, y) -> Vector3, stage.spawn(kind, opts?, shadow?) -> Thing, stage.place(thing, u, v, y, yaw?, tilt?),
--   stage.adopt(thing, shadow?), stage.refresh(thing),
--   stage.remove(thing), stage.flash(thing, seconds?), stage.glow(thing, on), stage.screen(pos) -> (x, y, on) (UI px on
--   the Stage canvas), stage.hold(kind?) (a thing in the founder's right hand), stage.hat(kind?), stage.pose(u, v, y, yaw,
--   t, speed, action, k), stage.close()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local AvatarView = require(script.Parent.Parent.Controllers.AvatarView)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)

local MicroStage = {}

export type Thing = MicroModels.Thing

export type Avatar = {
	rig: CharacterModels.Rig,
	held: Thing?,
	hat: Thing?,
}

export type Stage = {
	variant: string,
	floor: number, -- the floor's top (world Y)
	half: number, -- the floor's half size (studs, world-aligned)
	avatar: Avatar,
	at: (u: number, v: number, y: number) -> Vector3,
	spawn: (kind: string, opts: MicroModels.Opts?, shadow: number?) -> Thing,
	adopt: (t: Thing, shadow: number?) -> Thing, -- a thing built elsewhere (MicroModels.slab) on the stage
	refresh: (t: Thing) -> (), -- after its parts' colours or materials changed
	place: (t: Thing, u: number, v: number, y: number, yaw: number?, tilt: CFrame?) -> (),
	remove: (t: Thing) -> (),
	flash: (t: Thing, seconds: number?) -> (),
	glow: (t: Thing, on: boolean) -> (),
	screen: (pos: Vector3) -> (number, number, boolean),
	hold: (kind: string?) -> Thing?,
	hat: (kind: string?) -> Thing?,
	pose: (u: number, v: number, y: number, yaw: number, t: number, speed: number, action: string, k: number?) -> (),
	ready: () -> boolean,
	close: () -> (),
}

local ORIGIN = Vector3.new(0, 0, 9000)
local HALF = 12 -- the room's floor: 24 x 24 studs
local FLOOR = 0.5 -- the floor slab's top over the ground
local WALL_T = 0.5

-- the ground's screen-right (u) and toward-the-viewer (v) directions
local ROT = Raster.rotation(Tuning.CamYaw, Tuning.CamPitch)
local U_DIR = Vector3.new(ROT[4], 0, ROT[10]).Unit
local V_DIR = Vector3.new(ROT[6], 0, ROT[12]).Unit
-- yaws (radians) that turn a thing's +Z front toward the viewer, to the screen's right, to its left
MicroStage.FACE_VIEWER = math.atan2(V_DIR.X, V_DIR.Z)
MicroStage.FACE_RIGHT = math.atan2(U_DIR.X, U_DIR.Z)
MicroStage.FACE_LEFT = math.atan2(-U_DIR.X, -U_DIR.Z)
MicroStage.FACE_AWAY = math.atan2(-V_DIR.X, -V_DIR.Z)
MicroStage.U_DIR = U_DIR
MicroStage.V_DIR = V_DIR
-- the whack holes (every whack set digs all twelve; an easier game uses the first columns and the front rows)
MicroStage.HOLE_U = { -9, -4.5, 0, 4.5 }
MicroStage.HOLE_V = { -3.5, 0.5, 4.5 }
-- the robot's board: 7 x 5 pads 3 studs apart (u, v), the middle one at (0, 1)
MicroStage.BOARD = { cols = 7, rows = 5, step = 3, v0 = 1 }
MicroStage.TOWER = { u = 0, v = 1, base = 1 } -- the building site's base slab (its top: y = base)
MicroStage.GOAL_V = -8

local function uv(u: number, v: number, y: number): Vector3
	return ORIGIN + U_DIR * u + V_DIR * v + Vector3.new(0, FLOOR + y, 0)
end

------------------------------------------------------------------ the set (static: baked)
type Builder = {
	folder: Folder,
	box: (x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: string, neon: boolean?) -> BasePart,
	prop: (kind: string, u: number, v: number, y: number?, yaw: number?, opts: MicroModels.Opts?) -> (),
	ball: (x: number, y: number, z: number, d: number, color: string, neon: boolean?) -> (),
	h: number, -- the walls' height (0: none)
}

-- Boxes in world-aligned room space (x, z from the floor's middle, y from the ground).
local function builder(folder: Folder): Builder
	local b: Builder
	b = {
		folder = folder,
		h = 0,
		box = function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, color: string, neon: boolean?): BasePart
			local cx, cy, cz = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
			return Blocks.part(folder, { size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), cf = CFrame.new(ORIGIN + Vector3.new(cx, cy, cz)), color = color, neon = neon })
		end,
		prop = function(kind: string, u: number, v: number, y: number?, yaw: number?, opts: MicroModels.Opts?)
			local t = MicroModels.build(kind, opts)
			MicroModels.place(t, CFrame.new(uv(u, v, y or 0)) * CFrame.Angles(0, yaw or 0, 0))
			for _, p in t.parts do
				p.CanQuery = true
				p.CastShadow = true
			end
			t.model.Parent = folder
		end,
		ball = function(x: number, y: number, z: number, d: number, color: string, neon: boolean?)
			Blocks.part(folder, { size = Vector3.new(d, d, d), cf = CFrame.new(ORIGIN + Vector3.new(x, y, z)), color = color, shape = "Ball", neon = neon })
		end,
	}
	return b
end

-- The room: the ground all round, the floor (one colour or a checker of two), the back walls (along x = -HALF, the
-- screen's upper left, and z = -HALF, its upper right) with a trim along their foot.
type RoomSpec = { ground: string, a: string, b: string?, tile: number?, wall: string?, wallH: number?, trim: string? }
local function room(b: Builder, r: RoomSpec)
	b.box(-110, -1, -110, 110, 0, 110, r.ground)
	local tile = r.tile or 4
	if r.b then
		local n = math.floor(2 * HALF / tile)
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				local x0, z0 = -HALF + i * tile, -HALF + j * tile
				b.box(x0, 0, z0, x0 + tile, FLOOR, z0 + tile, if (i + j) % 2 == 0 then r.a else r.b :: string)
			end
		end
	else
		b.box(-HALF, 0, -HALF, HALF, FLOOR, HALF, r.a)
	end
	if r.wall then
		local h = r.wallH or 7
		b.h = h
		b.box(-HALF - WALL_T, 0, -HALF - WALL_T, -HALF, h, HALF, r.wall)
		b.box(-HALF, 0, -HALF - WALL_T, HALF, h, -HALF, r.wall)
		if r.trim then
			b.box(-HALF, FLOOR, -HALF, -HALF + 0.25, FLOOR + 0.5, HALF, r.trim)
			b.box(-HALF, FLOOR, -HALF, HALF, FLOOR + 0.5, -HALF + 0.25, r.trim)
			b.box(-HALF - WALL_T, h, -HALF - WALL_T, -HALF + 0.25, h + 0.25, HALF, r.trim)
			b.box(-HALF, h, -HALF - WALL_T, HALF, h + 0.25, -HALF + 0.25, r.trim)
		end
	end
end

-- A low fence round the room's back (outdoor sets), posts every 3 studs.
local function fence(b: Builder, color: string)
	for i = 0, 8 do
		local s = -HALF + i * 3
		b.box(-HALF - 0.5, FLOOR, s - 0.25, -HALF, FLOOR + 1.5, s + 0.25, color)
		b.box(s - 0.25, FLOOR, -HALF - 0.5, s + 0.25, FLOOR + 1.5, -HALF, color)
	end
	b.box(-HALF - 0.5, FLOOR + 0.75, -HALF, -HALF, FLOOR + 1.25, HALF, color)
	b.box(-HALF, FLOOR + 0.75, -HALF - 0.5, HALF, FLOOR + 1.25, -HALF, color)
end

-- A window on the left wall (z from z0, y from y0) or the right wall (x from x0): a frame, sky, a cross of bars.
local function windowL(b: Builder, z0: number, y0: number, w: number, h: number)
	local x = -HALF
	b.box(x, y0, z0, x + 0.25, y0 + h, z0 + w, "wood_dark")
	b.box(x + 0.25, y0 + 0.25, z0 + 0.25, x + 0.375, y0 + h - 0.25, z0 + w - 0.25, "window")
	b.box(x + 0.25, y0 + h / 2 - 0.125, z0, x + 0.5, y0 + h / 2 + 0.125, z0 + w, "wood_dark")
end
local function windowR(b: Builder, x0: number, y0: number, w: number, h: number)
	local z = -HALF
	b.box(x0, y0, z, x0 + w, y0 + h, z + 0.25, "wood_dark")
	b.box(x0 + 0.25, y0 + 0.25, z + 0.25, x0 + w - 0.25, y0 + h - 0.25, z + 0.375, "window")
	b.box(x0 + w / 2 - 0.125, y0, z + 0.25, x0 + w / 2 + 0.125, y0 + h, z + 0.5, "wood_dark")
end

-- A tree: a trunk and two tiers of leaves.
local function tree(b: Builder, x: number, z: number, s: number)
	b.box(x - 0.5 * s, 0, z - 0.5 * s, x + 0.5 * s, 3 * s, z + 0.5 * s, "wood_dark")
	b.box(x - 2 * s, 2.5 * s, z - 2 * s, x + 2 * s, 4.5 * s, z + 2 * s, "leaf_dark")
	b.box(x - 1.25 * s, 4.5 * s, z - 1.25 * s, x + 1.25 * s, 6 * s, z + 1.25 * s, "leaf")
end

-- A square box centred on a point of stage space (u, v), world-aligned.
local function boxAt(b: Builder, u: number, v: number, half: number, y0: number, y1: number, color: string, neon: boolean?)
	local p = U_DIR * u + V_DIR * v
	b.box(p.X - half, FLOOR + y0, p.Z - half, p.X + half, FLOOR + y1, p.Z + half, color, neon)
end

-- The twelve whack holes: a raised rim and the dark hole in it.
local function holes(b: Builder, rim: string)
	for _, u in MicroStage.HOLE_U do
		for _, v in MicroStage.HOLE_V do
			boxAt(b, u, v, 1.375, 0, 0.25, rim)
			boxAt(b, u, v, 1.0, 0.25, 0.3, "black")
		end
	end
end

local SETS: { [string]: (b: Builder) -> () } = {}

SETS.blocks = function(b) -- Action: a rooftop at night
	room(b, { ground = "night", a = "steel", b = "steel_dark", tile = 4, wall = "steel_dark", wallH = 1.5, trim = "berry_red" })
	for i = 0, 5 do
		local x = -30 + i * 9
		local h = 8 + (i * 7) % 9
		b.box(x, 0, -30, x + 6, h, -24, "sky_night")
		for wy = 2, h - 2, 3 do
			b.box(x + 1, wy, -24, x + 2, wy + 1, -23.75, "yellow", true)
			b.box(x + 4, wy, -24, x + 5, wy + 1, -23.75, "yellow", (wy % 2) == 0)
		end
		b.box(-30, 0, x, -24, h - 2, x + 6, "sky_night")
		b.box(-24, 3, x + 2, -23.75, 4, x + 3, "yellow", true)
	end
	b.box(-HALF + 1, FLOOR, -HALF + 1, -HALF + 3, FLOOR + 2, -HALF + 3, "steel_dark")
	b.box(HALF - 4, FLOOR, -HALF + 1, HALF - 1, FLOOR + 1, -HALF + 2, "plastic_dark")
end

SETS.race = function(b) -- Racing: a road down the screen through the grass, red and white kerbs
	b.box(-110, -1, -110, 110, 0, 110, "grass")
	-- the road: world-aligned tiles whose middles lie within 10 studs of the screen's vertical through the middle
	local tile = 2
	for i = -16, 15 do
		for j = -16, 15 do
			local x, z = (i + 0.5) * tile, (j + 0.5) * tile
			local p = ORIGIN + Vector3.new(x, 0, z) - ORIGIN
			local u = p:Dot(U_DIR)
			local v = p:Dot(V_DIR)
			if math.abs(v) <= 26 and math.abs(u) <= 11 then
				local edge = math.abs(u) > 9.6
				local c = if edge then (if (i + j) % 2 == 0 then "berry_red" else "white") else "road"
				b.box(x - tile / 2, 0, z - tile / 2, x + tile / 2, FLOOR, z + tile / 2, c)
			end
		end
	end
	tree(b, -18, -6, 1)
	tree(b, -6, -18, 1)
	tree(b, 14, -2, 0.8)
	tree(b, -2, 14, 0.8)
end

SETS.flip = function(b) -- Cooking: a kitchen
	room(b, { ground = "wood_dark", a = "floor_a", b = "floor_b", tile = 3, wall = "wall", wallH = 8, trim = "wall_trim" })
	-- counters along both back walls, a window, a shelf of jars
	b.box(-HALF, FLOOR, -HALF, -HALF + 2.5, FLOOR + 3, HALF - 8, "wood")
	b.box(-HALF, FLOOR + 3, -HALF, -HALF + 2.75, FLOOR + 3.25, HALF - 8, "desk")
	b.box(-HALF + 2.5, FLOOR, -HALF, HALF - 6, FLOOR + 3, -HALF + 2.5, "wood")
	b.box(-HALF + 2.5, FLOOR + 3, -HALF, HALF - 6, FLOOR + 3.25, -HALF + 2.75, "desk")
	windowR(b, 0, 4.5, 6, 3)
	b.box(-HALF, 5.5, -2, -HALF + 1, 5.75, 6, "wood_dark")
	for i, c in { "berry_red", "green", "yellow", "purple" } do
		b.box(-HALF + 0.25, 5.75, -2 + (i - 1) * 2 + 0.25, -HALF + 0.75, 6.75 + (i % 2) * 0.25, -2 + (i - 1) * 2 + 1.25, c)
	end
	-- the stove in the middle
	b.box(-2, FLOOR, -2, 2, FLOOR + 3, 2, "steel")
	b.box(-2, FLOOR + 3, -2, 2, FLOOR + 3.25, 2, "black")
	b.box(-1.5, FLOOR + 1, 2, -0.5, FLOOR + 2, 2.25, "steel_dark")
	b.box(0.5, FLOOR + 1, 2, 1.5, FLOOR + 2, 2.25, "steel_dark")
	b.box(2, FLOOR + 1, -1.5, 2.25, FLOOR + 2, 1.5, "steel_dark")
end

SETS.kick = function(b) -- Sports: a pitch with a crowd behind the boards
	room(b, { ground = "grass_dark", a = "grass", b = "grass_dark", tile = 4, wall = "berry_red", wallH = 1.5, trim = "white" })
	-- stands with a crowd behind the boards
	for row = 0, 2 do
		local y = row * 1.5
		b.box(-HALF - 3 - row * 2, 0, -HALF - 3 - row * 2, -HALF - 1 - row * 2, y + 2, HALF, "steel_dark")
		b.box(-HALF - 3 - row * 2, 0, -HALF - 3 - row * 2, HALF, y + 2, -HALF - 1 - row * 2, "steel_dark")
		for k = 0, 11 do
			local c = ({ "berry_red", "yellow", "blue", "white", "orange", "green" })[(k + row) % 6 + 1]
			local s = -HALF + k * 2
			b.box(-HALF - 2.5 - row * 2, y + 2, s, -HALF - 1.75 - row * 2, y + 2.75, s + 0.75, c)
			b.box(s, y + 2, -HALF - 2.5 - row * 2, s + 0.75, y + 2.75, -HALF - 1.75 - row * 2, c)
		end
	end
	b.prop("goal", 0, MicroStage.GOAL_V, 0, MicroStage.FACE_VIEWER)
end

SETS.strike = function(b) -- RPG: a dungeon
	room(b, { ground = "black", a = "steel_dark", b = "plastic_dark", tile = 3, wall = "steel_dark", wallH = 8, trim = "black" })
	for i = 0, 5 do
		for j = 0, 2 do
			local s = -HALF + 1 + i * 4 + (j % 2) * 2
			b.box(-HALF, 1.5 + j * 2.25, s, -HALF + 0.125, 2.5 + j * 2.25, s + 2, "plastic_dark")
			b.box(s, 1.5 + j * 2.25, -HALF, s + 2, 2.5 + j * 2.25, -HALF + 0.125, "plastic_dark")
		end
	end
	-- torches
	for _, z in { -4, 6 } do
		b.box(-HALF, 4, z, -HALF + 0.75, 4.25, z + 0.5, "wood_dark")
		b.box(-HALF + 0.25, 4.25, z, -HALF + 0.75, 5, z + 0.5, "orange", true)
	end
	b.box(4, 4, -HALF, 4.5, 4.25, -HALF + 0.75, "wood_dark")
	b.box(4, 4.25, -HALF + 0.25, 4.5, 5, -HALF + 0.75, "orange", true)
	b.box(-HALF + 1, FLOOR, -HALF + 1, -HALF + 3, FLOOR + 2, -HALF + 2.5, "wood_dark")
	b.box(-HALF + 1, FLOOR + 2, -HALF + 1, -HALF + 3, FLOOR + 2.25, -HALF + 2.5, "gold")
end

SETS.pet = function(b) -- Animals: a cosy living room
	room(b, { ground = "wood_dark", a = "wood", wall = "pink", wallH = 7, trim = "white" })
	b.box(-5, FLOOR, -3, 5, FLOOR + 0.125, 5, "sofa")
	b.box(-HALF, FLOOR, -8, -HALF + 2.5, FLOOR + 2, 2, "rug")
	b.box(-HALF, FLOOR + 2, -8, -HALF + 1, FLOOR + 4, 2, "rug")
	windowR(b, -2, 3, 6, 3)
	b.box(HALF - 4, FLOOR, -HALF, HALF - 1, FLOOR + 3, -HALF + 1.5, "wood")
	b.box(HALF - 3.5, FLOOR + 3, -HALF + 0.25, HALF - 2.5, FLOOR + 4.5, -HALF + 1.25, "leaf")
end

SETS.space = function(b) -- Space: a deck among the stars
	room(b, { ground = "black", a = "night", b = "sky_night", tile = 4 })
	for i = 1, 40 do
		local x = ((i * 37) % 200) - 100
		local z = ((i * 61) % 200) - 100
		if math.abs(x) > HALF + 2 or math.abs(z) > HALF + 2 then
			b.box(x, 0, z, x + 0.5, 0.25, z + 0.5, if i % 3 == 0 then "screen_on" else "white", true)
		end
	end
	holes(b, "purple")
	b.ball(-20, 6, -26, 9, "purple")
	b.ball(-23, 7.5, -27, 3, "pink")
	b.box(-HALF - 0.5, FLOOR, -HALF, -HALF, FLOOR + 0.5, HALF, "screen_on", true)
	b.box(-HALF, FLOOR, -HALF - 0.5, HALF, FLOOR + 0.5, -HALF, "screen_on", true)
end

SETS.water = function(b) -- Farming: a field of soil rows
	room(b, { ground = "grass", a = "wood_dark" })
	for i = 0, 5 do
		local z = -HALF + 1 + i * 4
		b.box(-HALF, FLOOR, z, HALF, FLOOR + 0.25, z + 2, "hair_brown")
	end
	holes(b, "hair_brown")
	fence(b, "wood")
	tree(b, -18, 4, 1)
	b.box(-20, 0, -20, -14, 5, -14, "berry_red")
	b.box(-20, 5, -20, -14, 6, -14, "white")
end

SETS.zombie = function(b) -- Zombies: a graveyard at night
	room(b, { ground = "night", a = "grass_dark", b = "leaf_dark", tile = 4 })
	holes(b, "steel")
	fence(b, "black")
	for i = 0, 3 do
		local s = -HALF + 2 + i * 6
		b.box(-HALF - 3, 0, s, -HALF - 2, 2.5, s + 2, "steel")
		b.box(s, 0, -HALF - 3, s + 2, 2.5 + (i % 2) * 0.5, -HALF - 2, "steel")
	end
	b.ball(-26, 12, -26, 5, "cream", true)
	tree(b, -18, 14, 0.9)
end

SETS.match = function(b) -- Puzzle: a playroom
	room(b, { ground = "wood_dark", a = "floor_a", b = "blue", tile = 3, wall = "white", wallH = 7, trim = "blue" })
	b.box(-HALF, FLOOR, -6, -HALF + 2, FLOOR + 2, -2, "yellow")
	b.box(-HALF, FLOOR + 2, -5.5, -HALF + 1.5, FLOOR + 3.5, -3, "berry_red")
	b.box(2, FLOOR, -HALF, 6, FLOOR + 2, -HALF + 2, "green")
	b.box(2.5, FLOOR + 2, -HALF, 4.5, FLOOR + 4, -HALF + 1.5, "purple")
	windowL(b, 2, 3, 5, 3)
end

SETS.answer = function(b) -- School: a classroom with a chalkboard
	room(b, { ground = "wood_dark", a = "wood", b = "desk", tile = 3, wall = "cream", wallH = 8, trim = "wood_dark" })
	b.box(-8, 2.5, -HALF, 8, 7, -HALF + 0.25, "wood_dark")
	b.box(-7.75, 2.75, -HALF + 0.25, 7.75, 6.75, -HALF + 0.375, "chalk")
	b.box(-7.75, 2.5, -HALF + 0.25, 7.75, 2.75, -HALF + 0.75, "wood")
	windowL(b, -6, 3, 5, 3.5)
	windowL(b, 2, 3, 5, 3.5)
	for _, x in { -6, 0, 6 } do
		b.box(x - 1.5, FLOOR, 6, x + 1.5, FLOOR + 1.75, 7.5, "wood")
	end
end

SETS.count = function(b) -- Strategy: a war table's map
	room(b, { ground = "wood_dark", a = "sand", wall = "wood_dark", wallH = 6, trim = "gold" })
	-- a river and woods on the map
	for i = 0, 11 do
		local x = -HALF + i * 2
		local z = -2 + math.floor(math.sin(i * 0.8) * 2)
		b.box(x, FLOOR, z, x + 2, FLOOR + 0.125, z + 2, "water")
	end
	b.box(4, FLOOR, -9, 9, FLOOR + 0.25, -5, "leaf_dark")
	b.box(-9, FLOOR, 5, -5, FLOOR + 0.25, 9, "leaf_dark")
	b.box(-HALF, 4, -4, -HALF + 0.25, 6, 4, "paper")
end

SETS.spot = function(b) -- Detectives: an office with a desk lamp
	room(b, { ground = "black", a = "wood_dark", b = "hair_brown", tile = 3, wall = "cream", wallH = 7, trim = "wood_dark" })
	b.box(-HALF, FLOOR, -HALF, -HALF + 2, FLOOR + 4, -HALF + 4, "steel_dark")
	for k = 0, 2 do
		b.box(-HALF + 2, FLOOR + 0.5 + k * 1.25, -HALF + 0.5, -HALF + 2.125, FLOOR + 1.25 + k * 1.25, -HALF + 3.5, "steel")
	end
	windowR(b, 0, 3, 6, 3)
	b.box(-HALF, 4, 2, -HALF + 0.25, 6, 6, "paper")
	b.box(-HALF + 0.25, 4.5, 2.5, -HALF + 0.375, 5.5, 3.5, "berry_red")
end

SETS.cast = function(b) -- Fantasy: a wizard's tower room
	room(b, { ground = "night", a = "purple", b = "night", tile = 4, wall = "night", wallH = 8, trim = "gold" })
	b.box(-HALF, FLOOR, -8, -HALF + 2, FLOOR + 6, 0, "wood_dark")
	for k = 0, 3 do
		for i = 0, 3 do
			b.box(-HALF + 1.75, FLOOR + 0.5 + k * 1.5, -7.5 + i * 2, -HALF + 2, FLOOR + 1.5 + k * 1.5, -6.5 + i * 2, ({ "berry_red", "blue", "green", "gold" })[(i + k) % 4 + 1])
		end
	end
	for _, x in { -4, 4 } do
		b.box(x, FLOOR, -HALF + 0.5, x + 0.75, FLOOR + 1.5, -HALF + 1.25, "cream")
		b.box(x + 0.25, FLOOR + 1.5, -HALF + 0.75, x + 0.5, FLOOR + 2, -HALF + 1, "yellow", true)
	end
	windowR(b, -1, 4, 4, 3)
end

SETS.program = function(b) -- Robots: a lab of circuit boards
	room(b, { ground = "black", a = "steel_dark", b = "screen_off", tile = 4, wall = "screen_off", wallH = 7, trim = "steel" })
	for i = 0, 4 do
		local s = -HALF + 1 + i * 5
		b.box(-HALF, 2 + (i % 3), s, -HALF + 0.25, 2.25 + (i % 3), s + 3, "screen_code", true)
		b.box(s, 2 + ((i + 1) % 3), -HALF, s + 3, 2.25 + ((i + 1) % 3), -HALF + 0.25, "screen_code", true)
	end
	b.box(HALF - 5, FLOOR, -HALF, HALF - 1, FLOOR + 3, -HALF + 2, "steel")
	b.box(HALF - 4.5, FLOOR + 1.5, -HALF + 2, HALF - 1.5, FLOOR + 2.5, -HALF + 2.125, "screen_on", true)
	-- the board the robot walks
	local bd = MicroStage.BOARD
	for c = 1, bd.cols do
		for r = 1, bd.rows do
			local u = (c - (bd.cols + 1) / 2) * bd.step
			local v = bd.v0 + (r - (bd.rows + 1) / 2) * bd.step
			boxAt(b, u, v, 1.0, 0, 0.25, if (c + r) % 2 == 0 then "steel" else "plastic")
		end
	end
end

SETS.simon = function(b) -- Music: a stage with curtains
	room(b, { ground = "black", a = "wood_dark", b = "wood", tile = 3, wall = "berry_red", wallH = 8, trim = "gold" })
	for i = 0, 11 do
		local s = -HALF + i * 2
		b.box(-HALF, 0, s, -HALF + 0.375, 8, s + 0.5, "sofa")
		b.box(s, 0, -HALF, s + 0.5, 8, -HALF + 0.375, "sofa")
	end
	for _, x in { -HALF + 1, HALF - 3 } do
		b.box(x, FLOOR, -HALF + 0.5, x + 2, FLOOR + 3, -HALF + 2, "black")
		b.box(x + 0.5, FLOOR + 1, -HALF + 2, x + 1.5, FLOOR + 2, -HALF + 2.125, "steel_dark")
	end
end

SETS.loot = function(b) -- Pirates: a beach, a palm and a chest
	room(b, { ground = "water", a = "sand" })
	b.box(-HALF - 3, 0, -HALF - 3, HALF + 3, 0.25, -HALF, "sand_dark")
	b.box(-HALF - 3, 0, -HALF, -HALF, 0.25, HALF + 3, "sand_dark")
	-- a palm
	for k = 0, 4 do
		b.box(-HALF + 1 + k * 0.25, FLOOR + k * 1.25, -HALF + 1, -HALF + 2 + k * 0.25, FLOOR + (k + 1) * 1.25, -HALF + 2, "wood")
	end
	b.box(-HALF - 1, 6.5, -HALF - 1, -HALF + 5, 7.25, -HALF + 4, "leaf")
	b.box(-HALF + 0.5, 7.25, -HALF + 0.5, -HALF + 3.5, 7.75, -HALF + 2.5, "leaf_dark")
	-- a treasure chest
	b.box(HALF - 5, FLOOR, -HALF + 1, HALF - 2, FLOOR + 1.5, -HALF + 3, "wood_dark")
	b.box(HALF - 5, FLOOR + 1.5, -HALF + 1, HALF - 2, FLOOR + 2.25, -HALF + 3, "gold")
end

SETS.fish = function(b) -- Ocean: the sea floor
	room(b, { ground = "water", a = "sand", b = "sand_dark", tile = 4 })
	for i = 0, 6 do
		local s = -HALF + 1 + i * 3.5
		b.box(-HALF + 0.5, FLOOR, s, -HALF + 1, FLOOR + 2 + (i % 3), s + 0.5, "leaf")
		b.box(s, FLOOR, -HALF + 0.5, s + 0.5, FLOOR + 1.5 + ((i + 1) % 3), -HALF + 1, "leaf_dark")
	end
	b.box(HALF - 4, FLOOR, -HALF + 1, HALF - 1, FLOOR + 1.5, -HALF + 3, "steel")
	b.box(-HALF + 2, FLOOR, HALF - 4, -HALF + 4, FLOOR + 1, HALF - 2, "pink")
end

SETS.leap = function(b) -- Adventure: a path over the meadow
	room(b, { ground = "grass_dark", a = "grass", b = "grass_dark", tile = 4 })
	tree(b, -16, -16, 1.2)
	tree(b, -18, 2, 1)
	tree(b, 4, -18, 1)
	tree(b, 16, -20, 0.9)
	b.box(-HALF, FLOOR, -1, HALF, FLOOR + 0.125, 1, "pavement")
end

SETS.dino = function(b) -- Dinosaurs: a desert with a volcano
	room(b, { ground = "sand_dark", a = "sand", b = "sand_dark", tile = 4 })
	b.box(-30, 0, -30, -16, 6, -16, "hair_brown")
	b.box(-27, 6, -27, -19, 10, -19, "hair_brown")
	b.box(-25, 10, -25, -21, 10.5, -21, "orange", true)
	b.box(8, 0, -24, 14, 3, -18, "hair_brown")
	b.box(-HALF, FLOOR, -1, HALF, FLOOR + 0.125, 1, "sand_dark")
end

SETS.beat = function(b) -- Rhythm: a disco floor
	room(b, { ground = "black", a = "purple", b = "pink", tile = 4, wall = "black", wallH = 7, trim = "purple" })
	for i = 0, 5 do
		for j = 0, 5 do
			if (i * 5 + j * 3) % 7 == 0 then
				local x0, z0 = -HALF + i * 4, -HALF + j * 4
				b.box(x0, 0, z0, x0 + 4, FLOOR + 0.01, z0 + 4, ({ "yellow", "screen_on", "pink" })[(i + j) % 3 + 1], true)
			end
		end
	end
	for _, s in { -HALF + 1, HALF - 4 } do
		b.box(-HALF, FLOOR, s, -HALF + 2, FLOOR + 4, s + 3, "black")
		b.box(-HALF + 2, FLOOR + 1, s + 0.75, -HALF + 2.125, FLOOR + 2.5, s + 2.25, "steel_dark")
	end
end

SETS.fruit = function(b) -- Ninjas: a dojo
	room(b, { ground = "wood_dark", a = "rug", b = "desk", tile = 4, wall = "paper", wallH = 7, trim = "wood_dark" })
	for i = 0, 6 do
		local s = -HALF + i * 4
		b.box(-HALF, 0, s, -HALF + 0.25, 7, s + 0.25, "wood_dark")
		b.box(s, 0, -HALF, s + 0.25, 7, -HALF + 0.25, "wood_dark")
	end
	b.box(-HALF, 3.5, -HALF, -HALF + 0.25, 3.75, HALF, "wood_dark")
	b.box(-HALF, 3.5, -HALF, HALF, 3.75, -HALF + 0.25, "wood_dark")
	for k = 0, 2 do
		b.box(HALF - 2 + k * 0.5, FLOOR, -HALF + 1, HALF - 1.5 + k * 0.5, FLOOR + 5 - k, -HALF + 1.5, "leaf")
	end
end

SETS.ghost = function(b) -- Horror: a haunted hall with a door
	room(b, { ground = "black", a = "wood_dark", b = "hair_brown", tile = 3, wall = "night", wallH = 8, trim = "purple" })
	-- the door at the hall's right end (on the right wall)
	b.box(HALF - 5, FLOOR, -HALF, HALF - 1, FLOOR + 6, -HALF + 0.25, "wood_dark")
	b.box(HALF - 4.5, FLOOR, -HALF + 0.25, HALF - 1.5, FLOOR + 5.5, -HALF + 0.5, "wood")
	b.box(HALF - 2.25, FLOOR + 2.5, -HALF + 0.5, HALF - 1.75, FLOOR + 3, -HALF + 0.75, "gold")
	-- a painting and candles
	b.box(-HALF, 3.5, -4, -HALF + 0.25, 6.5, 0, "gold")
	b.box(-HALF + 0.25, 3.75, -3.75, -HALF + 0.375, 6.25, -0.25, "sky_night")
	for _, z in { -8, 4 } do
		b.box(-HALF + 0.5, FLOOR, z, -HALF + 1, FLOOR + 1.5, z + 0.5, "cream")
		b.box(-HALF + 0.625, FLOOR + 1.5, z + 0.125, -HALF + 0.875, FLOOR + 2, z + 0.375, "orange", true)
	end
end

SETS.tower = function(b) -- Simulation: a building site
	room(b, { ground = "grass", a = "pavement", b = "steel", tile = 4 })
	fence(b, "orange")
	-- the crane's mast and jib
	b.box(-HALF - 3, 0, -HALF - 3, -HALF - 1, 16, -HALF - 1, "yellow")
	b.box(-HALF - 3, 16, -HALF - 3, 8, 17, -HALF - 1, "yellow")
	b.box(-HALF - 3, 17, -HALF - 3, -HALF - 1, 18, -HALF - 1, "steel_dark")
	tree(b, 18, -10, 1)
	tree(b, -10, 18, 1)
	-- the base the floors stand on
	local tw = MicroStage.TOWER
	boxAt(b, tw.u, tw.v, 2.5, 0, tw.base, "steel_dark")
	b.h = 10 -- the camera keeps room above for a tall tower
end

------------------------------------------------------------------ the stage
local function dynFolder(): Instance
	local f = workspace:FindFirstChild("PixelDynamic")
	if f then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
end

local current: Stage? = nil

function MicroStage.open(variant: string): Stage
	if current then
		(current :: Stage).close()
	end
	local folder = Instance.new("Folder")
	folder.Name = "MicroStage"
	local b = builder(folder)
	local fn = SETS[variant] or SETS.blocks
	fn(b)
	folder.Parent = workspace
	local things: { Thing } = {}
	local dyn = dynFolder()
	local groundY = ORIGIN.Y + FLOOR

	-- the player's founder
	local look = AvatarView.lookOf(Players.LocalPlayer)
	local rig = CharacterModels.buildStanding(look, "MicroAvatar", 1)
	rig.model:SetAttribute("PixelShadow", 1.4)
	rig.model:SetAttribute("PixelGroundY", groundY)
	rig.model.Parent = dyn
	PixelRenderer.registerDynamic(rig.model)
	local avatar: Avatar = { rig = rig, held = nil, hat = nil }

	local function register(t: Thing, shadow: number?)
		if shadow and shadow > 0 then
			t.model:SetAttribute("PixelShadow", shadow)
			t.model:SetAttribute("PixelGroundY", groundY)
		end
		t.model.Parent = dyn
		PixelRenderer.registerDynamic(t.model)
		table.insert(things, t)
	end

	local st: Stage
	st = {
		variant = variant,
		floor = groundY,
		half = HALF,
		avatar = avatar,
		at = uv,
		spawn = function(kind: string, opts: MicroModels.Opts?, shadow: number?): Thing
			local t = MicroModels.build(kind, opts)
			MicroModels.place(t, CFrame.new(uv(0, 0, -50)))
			register(t, shadow)
			return t
		end,
		adopt = function(t: Thing, shadow: number?): Thing
			MicroModels.place(t, CFrame.new(uv(0, 0, -50)))
			register(t, shadow)
			return t
		end,
		refresh = function(t: Thing)
			PixelRenderer.refreshDynamic(t.model)
		end,
		place = function(t: Thing, u: number, v: number, y: number, yaw: number?, tilt: CFrame?)
			MicroModels.place(t, CFrame.new(uv(u, v, y)) * CFrame.Angles(0, yaw or 0, 0) * (tilt or CFrame.identity))
		end,
		remove = function(t: Thing)
			PixelRenderer.unregisterDynamic(t.model)
			t.model:Destroy()
			local i = table.find(things, t)
			if i then
				table.remove(things, i)
			end
		end,
		flash = function(t: Thing, seconds: number?)
			MicroModels.recolor(t, "white")
			PixelRenderer.refreshDynamic(t.model)
			task.delay(seconds or 0.1, function()
				if t.model.Parent then
					MicroModels.recolor(t, nil)
					PixelRenderer.refreshDynamic(t.model)
				end
			end)
		end,
		glow = function(t: Thing, on: boolean)
			for _, p in t.parts do
				p.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
			PixelRenderer.refreshDynamic(t.model)
		end,
		screen = function(pos: Vector3): (number, number, boolean)
			local i, j, on = PixelRenderer.projectPixel(pos)
			return i, j, on
		end,
		hold = function(kind: string?): Thing?
			if avatar.held then
				st.remove(avatar.held :: Thing)
				avatar.held = nil
			end
			if kind then
				local t = st.spawn(kind)
				avatar.held = t
			end
			return avatar.held
		end,
		hat = function(kind: string?): Thing?
			if avatar.hat then
				st.remove(avatar.hat :: Thing)
				avatar.hat = nil
			end
			if kind then
				avatar.hat = st.spawn(kind)
			end
			return avatar.hat
		end,
		pose = function(u: number, v: number, y: number, yaw: number, t: number, speed: number, action: string, k: number?)
			CharacterModels.poseAction(rig, CFrame.new(uv(u, v, y)) * CFrame.Angles(0, yaw, 0), t, speed, action, k)
			local hand = rig.parts.HandR
			if avatar.held and hand then
				MicroModels.place(avatar.held :: Thing, hand.CFrame * CFrame.new(0, -0.1, 0))
			end
			local head = rig.parts.Head
			if avatar.hat and head then
				MicroModels.place(avatar.hat :: Thing, head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0))
			end
		end,
		ready = function(): boolean
			return CameraController.view().stage and PixelRenderer.ready()
		end,
		close = function()
			for i = #things, 1, -1 do
				local t = things[i]
				PixelRenderer.unregisterDynamic(t.model)
				t.model:Destroy()
			end
			table.clear(things)
			PixelRenderer.unregisterDynamic(rig.model)
			rig.model:Destroy()
			folder:Destroy()
			PixelRenderer.setOffset(0, 0)
			if current == st then
				current = nil
				CameraController.setStage(nil)
			end
		end,
	}
	st.pose(0, 2, 0, MicroStage.FACE_VIEWER, 0, 0, "stand")

	-- the camera frames the room: its floor, the walls' tops, a little over the floor's front
	local pts: { number } = {}
	local wallTop = math.max(b.h, 3) + FLOOR
	for _, c in { { -HALF - 1, 0, -HALF - 1 }, { HALF + 1, 0, -HALF - 1 }, { -HALF - 1, 0, HALF + 1 }, { HALF + 1, 0, HALF + 1 }, { -HALF - 1, wallTop, -HALF - 1 }, { HALF + 1, wallTop, -HALF - 1 }, { -HALF - 1, wallTop, HALF + 1 } } do
		table.insert(pts, ORIGIN.X + c[1])
		table.insert(pts, ORIGIN.Y + c[2])
		table.insert(pts, ORIGIN.Z + c[3])
	end
	current = st
	CameraController.setStage({ name = variant, origin = ORIGIN, pts = pts, top = 22, bottom = 20 })
	return st
end

-- The stage up now, if any.
function MicroStage.current(): Stage?
	return current
end

function MicroStage.has(variant: string): boolean
	return SETS[variant] ~= nil
end

return MicroStage
