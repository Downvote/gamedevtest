--!strict
-- An islet's 3D stage (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.8): a little diorama, themed by the islet (a beach,
-- a meadow, a volcano's sands, a snowfield, the sea floor; the older themed rooms are kept), built from parts far
-- from the islands (Z = 9000) and shown full screen
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
--   t, speed, action, k), stage.puff(pos, kind, n?, color?) (3D bits from a pool), stage.rival(look, delay) (a rival
--   founder for a party round, posed the same way), stage.lift() (the founder and the rivals drop in),
--   stage.step(t, dt) (every frame: the bits and the stage's ambient life: birds, flames, steam, bats...), stage.close()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
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

-- Another chibi on the stage (a villager in the party): their own look, posed like the player's.
export type Rival = {
	rig: CharacterModels.Rig,
	pose: (u: number, v: number, y: number, yaw: number, t: number, speed: number, action: string, k: number?) -> (),
	hide: () -> (),
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
	puff: (pos: Vector3, kind: string, n: number?, color: string?) -> (), -- 3D bits (PUFFS: dust spark debris confetti...)
	rival: (look: Types.Look, delay: number) -> Rival, -- a rival founder (drops in `delay` s after the founder)
	lift: () -> (), -- the curtain lifted: the founder drops in
	step: (t: number, dt: number) -> (), -- every frame: the bits and the stage's ambient life
	ready: () -> boolean,
	close: () -> (),
}

local ORIGIN = Vector3.new(0, 0, 9000)
local HALF = 12 -- the room's floor: 24 x 24 studs
local FLOOR = 0.5 -- the floor slab's top over the ground
-- where an islet's tall landmark stands (the volcano, the snowy peak, a big tree): on its left shore, beside the
-- floor and clear of the top bar (room space)
local VOLCANO = { x = -21, z = 13 }
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
			local p = Blocks.part(folder, { size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)), cf = CFrame.new(ORIGIN + Vector3.new(cx, cy, cz)), color = color, neon = neon })
			-- the sea round an islet's set moves like the islands' (the pixel filter's water)
			if color == "water" then
				p:SetAttribute("PixelWater", 1)
			elseif color == "shallow" then
				p:SetAttribute("PixelWater", 2)
			elseif color == "foam" then
				p:SetAttribute("PixelWater", 3)
			end
			return p
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
	b.box(-11.25, FLOOR + 4, -10.25, -10.75, FLOOR + 4.75, -9.75, "white") -- a mug of coffee on the cabinet
	b.box(-10.75, FLOOR + 4.25, -10.125, -10.5, FLOOR + 4.5, -9.875, "white")
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

------------------------------------------------------------------ the islets' sets (GAME_DESIGN 7)
-- Cells in room space (x .. x + 1, z .. z + 1) where `test` holds, merged into rectangles (greedy).
local function blobRects(test: (x: number, z: number) -> boolean, x0: number, x1: number, z0: number, z1: number): { { number } }
	local used: { [number]: boolean } = {}
	local out: { { number } } = {}
	local function key(x: number, z: number): number
		return (x + 512) * 2048 + (z + 512)
	end
	local function free(x: number, z: number): boolean
		return test(x, z) and not used[key(x, z)]
	end
	for z = z0, z1 do
		local x = x0
		while x <= x1 do
			if free(x, z) then
				local xe = x
				while xe + 1 <= x1 and free(xe + 1, z) do
					xe += 1
				end
				local ze = z
				while ze + 1 <= z1 do
					local ok = true
					for xx = x, xe do
						if not free(xx, ze + 1) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					ze += 1
				end
				for zz = z, ze do
					for xx = x, xe do
						used[key(xx, zz)] = true
					end
				end
				table.insert(out, { x, z, xe + 1, ze + 1 })
				x = xe + 1
			else
				x += 1
			end
		end
	end
	return out
end

-- An islet round the stage's floor on the open sea: its land, a beach, wet sand, foam and the shallows, each a
-- little lower than the one inside it (the sea animates: Data/Street's layers, the pixel filter's water).
local function shore(b: Builder, land: string, beach: string, wob: number)
	local R = HALF + 5
	local function dist(x: number, z: number): number
		local cx, cz = x + 0.5, z + 0.5
		local ang = math.atan2(cz, cx)
		local w = 1 + 0.08 * math.sin(2 * ang + wob) + 0.06 * math.sin(3 * ang + wob * 2) + 0.04 * math.sin(5 * ang + 1)
		local r = math.max(math.abs(cx), math.abs(cz)) * 0.6 + math.sqrt(cx * cx + cz * cz) * 0.4
		return r - R * w
	end
	local layers = {
		{ d = 7.5, top = 0.05, color = "shallow" },
		{ d = 4.5, top = 0.12, color = "foam" },
		{ d = 3.5, top = 0.25, color = "sand_dark" },
		{ d = 2.5, top = 0.35, color = beach },
		{ d = 0, top = FLOOR - 0.06, color = land },
	}
	for _, l in layers do
		for _, r in blobRects(function(x, z)
			return dist(x, z) <= l.d
		end, -34, 33, -34, 33) do
			b.box(r[1], 0, r[2], r[3], l.top, r[4], l.color)
		end
	end
end

-- A palm on a stage (room space x, z), leaning toward `lean` (radians about Y).
local function stagePalm(b: Builder, x: number, z: number, s: number, lean: number)
	local dx, dz = math.cos(lean), math.sin(lean)
	local px, pz = x, z
	for k = 0, 5 do
		px += dx * 0.12 * k * s
		pz += dz * 0.12 * k * s
		local w = (0.45 - k * 0.03) * s
		b.box(px - w, FLOOR + k * 0.9 * s, pz - w, px + w, FLOOR + (k + 1) * 0.9 * s, pz + w, if k % 2 == 0 then "wood" else "wood_dark")
	end
	local top = FLOOR + 5.6 * s
	b.box(px - 0.6 * s, top - 0.2, pz - 0.6 * s, px + 0.6 * s, top + 0.35, pz + 0.6 * s, "leaf_dark")
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local len = 2.6 * s
		local fx0, fx1 = px + math.min(0, d[1] * len), px + math.max(0, d[1] * len)
		local fz0, fz1 = pz + math.min(0, d[2] * len), pz + math.max(0, d[2] * len)
		if d[1] == 0 then
			fx0, fx1 = px - 0.45 * s, px + 0.45 * s
		else
			fz0, fz1 = pz - 0.45 * s, pz + 0.45 * s
		end
		b.box(fx0, top - 0.35, fz0, fx1, top, fz1, if k % 2 == 0 then "leaf" else "leaf_dark")
	end
	for _, d in { { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } } do
		b.box(px + d[1] * 1.2 * s - 0.4, top - 0.55, pz + d[2] * 1.2 * s - 0.4, px + d[1] * 1.2 * s + 0.4, top - 0.25, pz + d[2] * 1.2 * s + 0.4, "leaf")
	end
	b.ball(px + 0.35, top - 0.4, pz + 0.2, 0.5, "wood_dark")
	b.ball(px - 0.25, top - 0.45, pz - 0.3, 0.45, "wood_dark")
end

local function stageRocks(b: Builder, x: number, z: number, s: number, y: number?)
	local y0 = y or FLOOR - 0.2
	b.box(x - 0.8 * s, y0, z - 0.6 * s, x + 0.8 * s, y0 + 1.1 * s, z + 0.6 * s, "rock")
	b.box(x - 0.5 * s, y0 + 1.1 * s, z - 0.3 * s, x + 0.4 * s, y0 + 1.4 * s, z + 0.4 * s, "rock")
	b.box(x + 0.8 * s, y0, z + 0.1 * s, x + 1.4 * s, y0 + 0.55 * s, z + 0.7 * s, "rock_dark")
	b.box(x - 1.3 * s, y0, z - 0.5 * s, x - 0.8 * s, y0 + 0.4 * s, z, "rock_dark")
end

local function starfish(b: Builder, x: number, z: number, color: string?)
	local c = color or "orange"
	b.box(x - 0.45, FLOOR, z - 0.12, x + 0.45, FLOOR + 0.1, z + 0.12, c)
	b.box(x - 0.12, FLOOR, z - 0.45, x + 0.12, FLOOR + 0.1, z + 0.45, c)
end

-- Pebble Beach: a sandy islet, two palms leaning out, a treasure chest with spilled coins, tide pools ringed with
-- pebbles, rocks, an upturned rowboat, starfish and shells, driftwood.
SETS.loot = function(b)
	room(b, { ground = "water", a = "sand" })
	shore(b, "sand", "sand", 0.4)
	stagePalm(b, -HALF - 3, -5, 1, math.rad(-150))
	stagePalm(b, 20, -2, 0.9, math.rad(-30))
	stagePalm(b, -HALF + 4, -HALF - 2, 0.85, math.rad(-110))
	-- the chest: a wooden box with gold bands and a lock, its lid open, coins spilling
	b.box(HALF - 5, FLOOR, -HALF + 1, HALF - 2, FLOOR + 1.4, -HALF + 3, "wood_dark")
	b.box(HALF - 5.1, FLOOR + 0.3, -HALF + 0.95, HALF - 1.9, FLOOR + 0.5, -HALF + 3.05, "gold")
	b.box(HALF - 5, FLOOR + 1.4, -HALF + 0.6, HALF - 2, FLOOR + 2.6, -HALF + 1, "wood")
	b.box(HALF - 3.75, FLOOR + 0.8, -HALF + 2.95, HALF - 3.25, FLOOR + 1.2, -HALF + 3.1, "gold")
	b.box(HALF - 4.6, FLOOR + 1.4, -HALF + 1.4, HALF - 2.4, FLOOR + 1.55, -HALF + 2.6, "gold", true)
	for _, c in { { -4, 3.6 }, { -3.2, 4.1 }, { -2.5, 3.5 }, { -4.6, 4.3 } } do
		b.box(HALF + c[1] - 0.2, FLOOR, -HALF + c[2] - 0.2, HALF + c[1] + 0.2, FLOOR + 0.1, -HALF + c[2] + 0.2, "gold")
	end
	-- tide pools: a ring of pebbles round a little pool
	for _, tp in { { -HALF + 3, HALF - 3 }, { HALF - 3, 2 } } do
		b.box(tp[1] - 1.5, FLOOR - 0.05, tp[2] - 1.0, tp[1] + 1.5, FLOOR + 0.02, tp[2] + 1.0, "shallow")
		for k = 0, 7 do
			local ang = k * math.pi / 4
			local px, pz = tp[1] + math.cos(ang) * 1.6, tp[2] + math.sin(ang) * 1.1
			b.box(px - 0.25, FLOOR, pz - 0.2, px + 0.25, FLOOR + 0.3, pz + 0.2, if k % 2 == 0 then "rock" else "rock_dark")
		end
	end
	stageRocks(b, HALF + 2, -HALF + 6, 1.2, 0.1)
	stageRocks(b, -HALF - 3, 4, 0.9, 0.1)
	-- an upturned rowboat half in the sand
	b.box(-HALF + 1, FLOOR, -3, -HALF + 2.5, FLOOR + 0.9, 1.5, "berry_red")
	b.box(-HALF + 0.9, FLOOR + 0.9, -2.9, -HALF + 2.6, FLOOR + 1.1, 1.4, "wood")
	b.box(-HALF + 1.6, FLOOR + 1.1, -2.9, -HALF + 1.9, FLOOR + 1.25, 1.4, "wood_dark")
	starfish(b, 3, -HALF + 2)
	starfish(b, -6, HALF - 1.5, "pink")
	b.box(6, FLOOR, HALF - 2, 6.5, FLOOR + 0.15, HALF - 1.6, "pink")
	b.box(-2, FLOOR, -HALF + 1.2, -1.6, FLOOR + 0.15, -HALF + 1.5, "cream")
	b.box(HALF - 9, FLOOR, -HALF + 0.8, HALF - 6.5, FLOOR + 0.35, -HALF + 1.3, "wood")
end

-- Coral Deep: the sea floor (the water above shimmers): corals in pink, purple and orange, anemones, swaying kelp,
-- a sunken anchor on its chain, clams with glowing pearls, a sea fan.
SETS.fish = function(b)
	room(b, { ground = "water", a = "sand", b = "sand_dark", tile = 4 })
	local function coral(x: number, z: number, c: string, s: number)
		b.box(x - 0.25, FLOOR, z - 0.25, x + 0.25, FLOOR + 2 * s, z + 0.25, c)
		b.box(x - 1.0 * s, FLOOR + 1.0 * s, z - 0.2, x - 0.25, FLOOR + 1.3 * s, z + 0.2, c)
		b.box(x - 1.0 * s, FLOOR + 1.3 * s, z - 0.2, x - 0.7 * s, FLOOR + 2.2 * s, z + 0.2, c)
		b.box(x + 0.25, FLOOR + 1.4 * s, z - 0.2, x + 0.9 * s, FLOOR + 1.7 * s, z + 0.2, c)
		b.box(x + 0.6 * s, FLOOR + 1.7 * s, z - 0.2, x + 0.9 * s, FLOOR + 2.6 * s, z + 0.2, c)
		b.ball(x, FLOOR + 2 * s + 0.2, z, 0.5, "white")
	end
	coral(-HALF + 2, -HALF + 3, "pink", 1.2)
	coral(-HALF + 6, -HALF + 1.5, "purple", 1)
	coral(HALF - 3, -HALF + 2, "orange", 1.1)
	coral(-HALF + 1.5, 5, "berry_red", 0.9)
	for i = 0, 6 do
		local sx = -HALF + 1 + i * 3.5
		for k = 0, 2 + (i % 3) do
			b.box(-HALF + 0.4 + (k % 2) * 0.25, FLOOR + k * 0.8, sx, -HALF + 0.9 + (k % 2) * 0.25, FLOOR + (k + 1) * 0.8, sx + 0.5, if k % 2 == 0 then "leaf" else "leaf_dark")
		end
		for k = 0, 1 + ((i + 1) % 3) do
			b.box(sx + (k % 2) * 0.25, FLOOR + k * 0.8, -HALF + 0.4, sx + 0.5 + (k % 2) * 0.25, FLOOR + (k + 1) * 0.8, -HALF + 0.9, if k % 2 == 0 then "leaf_dark" else "leaf")
		end
	end
	-- anemones: a stalk and a crown of tendrils
	local anemones: { { x: number, z: number, c: string } } = { { x = 4, z = -HALF + 3, c = "pink" }, { x = -3, z = -HALF + 2, c = "yellow" }, { x = HALF - 2, z = 4, c = "purple" } }
	for _, an in anemones do
		local x, z = an.x, an.z
		b.box(x - 0.4, FLOOR, z - 0.4, x + 0.4, FLOOR + 0.6, z + 0.4, "cream")
		for k = 0, 5 do
			local ang = k * math.pi / 3
			b.box(x + math.cos(ang) * 0.35 - 0.1, FLOOR + 0.6, z + math.sin(ang) * 0.35 - 0.1, x + math.cos(ang) * 0.35 + 0.1, FLOOR + 1.1, z + math.sin(ang) * 0.35 + 0.1, an.c)
		end
	end
	-- the anchor and its chain
	b.box(HALF - 4.25, FLOOR, -HALF + 6, HALF - 3.75, FLOOR + 3, -HALF + 6.5, "steel_dark")
	b.box(HALF - 5.5, FLOOR, -HALF + 5.9, HALF - 2.5, FLOOR + 0.5, -HALF + 6.6, "steel_dark")
	b.box(HALF - 5.75, FLOOR + 0.5, -HALF + 5.9, HALF - 5.25, FLOOR + 1.2, -HALF + 6.6, "steel_dark")
	b.box(HALF - 2.75, FLOOR + 0.5, -HALF + 5.9, HALF - 2.25, FLOOR + 1.2, -HALF + 6.6, "steel_dark")
	b.box(HALF - 4.75, FLOOR + 3, -HALF + 5.75, HALF - 3.25, FLOOR + 3.5, -HALF + 6.75, "steel_dark")
	for k = 0, 4 do
		b.box(HALF - 4.1 + k * 0.6, FLOOR + 3.6 + k * 0.5, -HALF + 6, HALF - 3.7 + k * 0.6, FLOOR + 4.0 + k * 0.5, -HALF + 6.5, "steel")
	end
	-- clams with pearls
	for _, c in { { -HALF + 3, HALF - 3 }, { 2, HALF - 1.5 } } do
		b.box(c[1] - 0.8, FLOOR, c[2] - 0.6, c[1] + 0.8, FLOOR + 0.4, c[2] + 0.6, "purple")
		b.box(c[1] - 0.8, FLOOR + 0.4, c[2] - 0.9, c[1] + 0.8, FLOOR + 1.1, c[2] - 0.5, "purple")
		b.ball(c[1], FLOOR + 0.6, c[2], 0.5, "white", true)
	end
end

-- Frostcap: a snowy islet in an icy sea: snowbanks, a peak behind, snowy pines, ice crystals, a frozen pond,
-- snow mounds and icicled rocks.
SETS.frost = function(b)
	room(b, { ground = "water", a = "white", b = "window", tile = 6 })
	shore(b, "white", "window", 1.3)
	b.box(-HALF - 3, 0, -HALF - 3, HALF + 3, 0.75, -HALF, "white")
	b.box(-HALF - 3, 0, -HALF, -HALF, 0.75, HALF + 3, "white")
	-- the snowy peak on the islet's left shore (in view beside the floor)
	local px, pz = VOLCANO.x, VOLCANO.z
	b.box(px - 4, 0, pz - 4, px + 4, 3, pz + 4, "steel")
	b.box(px - 3, 3, pz - 3, px + 3, 5, pz + 3, "steel")
	b.box(px - 3.2, 4.4, pz - 3.2, px + 3.2, 5.2, pz + 3.2, "white")
	b.box(px - 2, 5.2, pz - 2, px + 2, 6.4, pz + 2, "white")
	b.box(px - 1, 6.4, pz - 1, px + 1, 7, pz + 1, "white")
	-- snow run down its faces toward the viewer, a dark crag
	b.box(px + 3, 3.4, pz - 1.5, px + 3.2, 5, pz + 0.5, "white")
	b.box(px + 3.9, 1.6, pz - 1.2, px + 4.15, 3, pz + 0.2, "white")
	b.box(px - 0.5, 3.6, pz + 3, px + 1.5, 5, pz + 3.2, "white")
	b.box(px + 0.2, 1.8, pz + 3.9, px + 1.2, 3, pz + 4.15, "white")
	b.box(px + 4, 0, pz + 1.5, px + 4.6, 1.5, pz + 3, "steel_dark")
	for _, t in { { 20, -2, 1 }, { -17, 4, 0.9 }, { 5, -17, 1 }, { 15, -19, 0.8 }, { -HALF - 1, -HALF + 6, 0.7 } } do
		local x, z, k = t[1], t[2], t[3]
		b.box(x - 0.5 * k, 0, z - 0.5 * k, x + 0.5 * k, 2 * k, z + 0.5 * k, "wood_dark")
		for i = 0, 2 do
			local r = (2.25 - i * 0.6) * k
			local y = (1.75 + i * 1.5) * k
			b.box(x - r, y, z - r, x + r, y + 1.25 * k, z + r, "leaf_dark")
			b.box(x - r + 0.25, y + 1.25 * k, z - r + 0.25, x + r - 0.25, y + 1.5 * k, z + r - 0.25, "white")
		end
	end
	-- ice crystals: glowing shards in clusters
	for _, c in { { HALF - 3, -HALF + 3 }, { -HALF + 3, 2 } } do
		b.box(c[1] - 0.3, FLOOR, c[2] - 0.3, c[1] + 0.3, FLOOR + 2.2, c[2] + 0.3, "screen_on", true)
		b.box(c[1] + 0.4, FLOOR, c[2] - 0.1, c[1] + 0.8, FLOOR + 1.3, c[2] + 0.3, "window", true)
		b.box(c[1] - 0.9, FLOOR, c[2] + 0.1, c[1] - 0.5, FLOOR + 1.0, c[2] + 0.5, "window", true)
	end
	-- the frozen pond with a crack, snow mounds, a rock with icicles
	b.box(-HALF + 2, FLOOR, HALF - 7, -HALF + 7, FLOOR + 0.125, HALF - 2, "screen_on")
	b.box(-HALF + 3, FLOOR + 0.125, HALF - 6, -HALF + 4, FLOOR + 0.2, HALF - 5, "white")
	b.box(-HALF + 4, FLOOR + 0.125, HALF - 5, -HALF + 6, FLOOR + 0.16, HALF - 4.8, "window")
	for _, mnd in { { 2, -HALF + 2, 1.2 }, { HALF - 2, 6, 0.9 }, { -4, HALF - 1.5, 0.8 } } do
		b.ball(mnd[1], FLOOR, mnd[2], 2 * mnd[3], "white")
	end
	stageRocks(b, HALF + 1.5, -HALF + 8, 1, 0.1)
	for k = 0, 2 do
		b.box(HALF + 0.7 + k * 0.5, 0.6, -HALF + 7.6, HALF + 0.9 + k * 0.5, 1.2, -HALF + 7.8, "window")
	end
end

-- Mossgrove: a green islet of ferns and mossy stones: tall trees, a fallen mossy log, red-capped mushrooms, flowers,
-- a stepping-stone path.
SETS.leap = function(b)
	room(b, { ground = "water", a = "grass", b = "grass_dark", tile = 4 })
	shore(b, "grass_dark", "sand", 2.2)
	tree(b, -19, 13, 1.2)
	tree(b, 20, -2, 0.9)
	tree(b, -18, 2, 1)
	tree(b, 4, -18, 1)
	tree(b, 16, -20, 0.9)
	tree(b, -HALF - 2, -HALF + 5, 0.8)
	for k = 0, 7 do
		local x = -HALF + 1.5 + k * 3
		b.box(x - 0.6, FLOOR, -0.6 + (k % 2) * 0.4, x + 0.6, FLOOR + 0.1, 0.6 + (k % 2) * 0.4, "pavement")
	end
	-- ferns: fans of leaves
	for _, fe in { { -HALF + 2, -HALF + 2 }, { HALF - 2, -HALF + 2 }, { -HALF + 1.5, HALF - 3 }, { 5, -HALF + 1.5 } } do
		local x, z = fe[1], fe[2]
		for k = 0, 4 do
			local ang = -math.pi / 2 + (k - 2) * 0.5
			local fx, fz = x + math.cos(ang) * 0.8, z + math.sin(ang) * 0.8
			b.box(fx - 0.25, FLOOR, fz - 0.25, fx + 0.25, FLOOR + 1.2 + (k % 2) * 0.3, fz + 0.25, if k % 2 == 0 then "leaf" else "leaf_dark")
		end
	end
	-- mossy stones, a fallen log
	stageRocks(b, -HALF + 4, -HALF + 5, 0.8)
	b.box(-HALF + 3.6, FLOOR + 0.9, -HALF + 4.6, -HALF + 4.6, FLOOR + 1.1, -HALF + 5.4, "leaf_dark")
	b.box(HALF - 7, FLOOR, -HALF + 1, HALF - 2, FLOOR + 1, -HALF + 2, "wood_dark")
	b.box(HALF - 6.5, FLOOR + 1, -HALF + 1.1, HALF - 3, FLOOR + 1.2, -HALF + 1.9, "leaf")
	b.box(HALF - 2.2, FLOOR, -HALF + 0.9, HALF - 1.9, FLOOR + 1.0, -HALF + 2.1, "sand")
	-- mushrooms and flowers
	for _, mu in { { -HALF + 6, -HALF + 1.5, 1 }, { -HALF + 1.5, -4, 0.8 }, { HALF - 1.5, -6, 1.1 } } do
		local x, z, k = mu[1], mu[2], mu[3]
		b.box(x - 0.2 * k, FLOOR, z - 0.2 * k, x + 0.2 * k, FLOOR + 0.8 * k, z + 0.2 * k, "cream")
		b.box(x - 0.6 * k, FLOOR + 0.8 * k, z - 0.6 * k, x + 0.6 * k, FLOOR + 1.15 * k, z + 0.6 * k, "berry_red")
		b.box(x - 0.15, FLOOR + 1.15 * k, z - 0.15, x + 0.15, FLOOR + 1.2 * k, z + 0.15, "white")
	end
	for k = 0, 5 do
		local x, z = -HALF + 1 + k * 1.3, HALF - 1 - (k % 2) * 0.8
		b.box(x - 0.08, FLOOR, z - 0.08, x + 0.08, FLOOR + 0.5, z + 0.08, "leaf")
		b.box(x - 0.2, FLOOR + 0.5, z - 0.2, x + 0.2, FLOOR + 0.75, z + 0.2, if k % 2 == 0 then "yellow" else "purple")
	end
end

-- Cinder Rock: a volcanic islet of dark sand: the smoking volcano with a glowing crater, lava cracks across the
-- ground's edges, obsidian rocks, charred stumps, steaming vents.
SETS.dino = function(b)
	room(b, { ground = "water", a = "sand", b = "sand_dark", tile = 4 })
	shore(b, "rock_dark", "black", 3.1)
	-- the volcano on the islet's left shore (in view beside the floor): two stepped cones, a black rim round a
	-- glowing crater, lava running down the two faces toward the viewer
	local vx, vz = VOLCANO.x, VOLCANO.z
	b.box(vx - 4, 0, vz - 4, vx + 4, 3, vz + 4, "rock_dark")
	b.box(vx - 3, 3, vz - 3, vx + 3, 5, vz + 3, "rock_dark")
	b.box(vx - 2, 5, vz - 2, vx + 2, 6.5, vz + 2, "rock")
	b.box(vx - 2.25, 6.5, vz - 2.25, vx + 2.25, 6.9, vz + 2.25, "black")
	b.box(vx - 1.25, 6.6, vz - 1.25, vx + 1.25, 7, vz + 1.25, "orange", true)
	b.box(vx - 0.5, 7, vz - 0.5, vx + 0.5, 7.1, vz + 0.5, "yellow", true)
	b.box(vx + 1.9, 4.5, vz - 0.75, vx + 2.15, 6.5, vz, "orange", true)
	b.box(vx + 2.9, 2.5, vz - 0.9, vx + 3.15, 5, vz + 0.1, "orange", true)
	b.box(vx + 3.9, 0, vz - 1, vx + 4.15, 3, vz + 0.25, "orange", true)
	b.box(vx + 0.25, 4.8, vz + 1.9, vx + 0.75, 6.5, vz + 2.15, "orange", true)
	b.box(vx + 0.1, 2.2, vz + 2.9, vx + 0.9, 5, vz + 3.15, "orange", true)
	b.box(vx, 0, vz + 3.9, vx + 1, 3, vz + 4.15, "orange", true)
	-- boulders at its foot
	b.box(vx + 4, 0, vz - 3, vx + 5, 0.8, vz - 2, "black")
	b.box(vx - 1.5, 0, vz + 4, vx - 0.5, 0.6, vz + 5, "rock")
	b.box(8, 0, -24, 14, 3, -18, "rock_dark")
	b.box(9, 3, -23, 13, 4, -19, "rock_dark")
	-- lava cracks at the floor's back edges
	for k = 0, 3 do
		local x = -HALF + 1 + k * 6
		b.box(x, FLOOR - 0.02, -HALF + 0.3, x + 2.5, FLOOR + 0.04, -HALF + 0.6, "orange", true)
		b.box(-HALF + 0.3, FLOOR - 0.02, x, -HALF + 0.6, FLOOR + 0.04, x + 2, "orange", true)
	end
	-- obsidian rocks and charred stumps
	for _, ob in { { HALF - 3, -HALF + 3 }, { -HALF + 2, HALF - 4 } } do
		b.box(ob[1] - 0.6, FLOOR, ob[2] - 0.5, ob[1] + 0.6, FLOOR + 1.6, ob[2] + 0.5, "black")
		b.box(ob[1] + 0.6, FLOOR, ob[2] - 0.2, ob[1] + 1.1, FLOOR + 0.9, ob[2] + 0.4, "purple")
	end
	for _, st in { { -HALF + 2, -HALF + 2 }, { 4, -HALF + 1.5 } } do
		b.box(st[1] - 0.4, FLOOR, st[2] - 0.4, st[1] + 0.4, FLOOR + 1.2, st[2] + 0.4, "black")
		b.box(st[1] - 0.15, FLOOR + 1.2, st[2] - 0.15, st[1] + 0.15, FLOOR + 1.5, st[2] + 0.15, "orange", true)
	end
	-- a steaming vent
	b.box(HALF - 2.5, FLOOR, 2, HALF - 1.5, FLOOR + 0.3, 3, "rock_dark")
	b.box(HALF - 2.2, FLOOR + 0.3, 2.3, HALF - 1.8, FLOOR + 0.35, 2.7, "orange", true)
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

------------------------------------------------------------------ 3D bits (one pooled model, a part a bit)
-- Each kind: how many, its colours, its speeds out and up, gravity, life, size, glow, whether it bounces on the floor,
-- grows (steam, smoke) or sways (petals, bubbles). The bits stay world-aligned cubes (clean iso edges).
type PuffSpec = { n: number, colors: { string }, out: { number }, up: { number }, grav: number, life: { number }, size: { number }, neon: boolean?, bounce: boolean?, grow: boolean?, sway: number? }
local PUFFS: { [string]: PuffSpec } = {
	dust = { n = 6, colors = { "white", "plastic" }, out = { 2.5, 4.5 }, up = { 1.5, 3.5 }, grav = 9, life = { 0.3, 0.5 }, size = { 0.5, 0.75 }, grow = true },
	spark = { n = 8, colors = { "yellow", "white", "gold" }, out = { 6, 11 }, up = { 2, 7 }, grav = 8, life = { 0.2, 0.4 }, size = { 0.25, 0.4 }, neon = true },
	debris = { n = 8, colors = { "wood" }, out = { 3, 7 }, up = { 5, 10 }, grav = 32, life = { 0.6, 0.9 }, size = { 0.35, 0.6 }, bounce = true },
	confetti = { n = 18, colors = { "berry_red", "yellow", "blue", "green", "pink", "white" }, out = { 3, 7 }, up = { 9, 15 }, grav = 14, life = { 1.0, 1.6 }, size = { 0.25, 0.4 }, bounce = true },
	steam = { n = 1, colors = { "white", "plastic" }, out = { 0, 0.4 }, up = { 1.5, 2.5 }, grav = -0.6, life = { 0.8, 1.2 }, size = { 0.35, 0.5 }, grow = true, sway = 0.6 },
	smoke = { n = 1, colors = { "steel", "steel_dark" }, out = { 0, 0.6 }, up = { 1.5, 2.5 }, grav = -0.4, life = { 1.4, 2.0 }, size = { 0.8, 1.2 }, grow = true, sway = 0.8 },
	bubble = { n = 1, colors = { "window", "white" }, out = { 0, 0.3 }, up = { 2, 3 }, grav = -0.5, life = { 1.6, 2.4 }, size = { 0.25, 0.4 }, sway = 1.2 },
	petal = { n = 1, colors = { "pink", "white" }, out = { 0.5, 1 }, up = { -1.5, -1 }, grav = 0, life = { 3.5, 4.5 }, size = { 0.25, 0.3 }, sway = 1.6 },
	ember = { n = 1, colors = { "orange", "yellow" }, out = { 0, 0.4 }, up = { 1.5, 3 }, grav = -0.5, life = { 0.5, 0.9 }, size = { 0.25, 0.25 }, neon = true, sway = 0.5 },
	twinkle = { n = 1, colors = { "yellow", "white", "purple" }, out = { 0, 0.3 }, up = { 0.3, 0.8 }, grav = 0, life = { 0.8, 1.2 }, size = { 0.25, 0.35 }, neon = true, sway = 0.4 },
	splash = { n = 8, colors = { "water", "window", "white" }, out = { 2, 4 }, up = { 4, 7 }, grav = 26, life = { 0.4, 0.6 }, size = { 0.25, 0.4 }, bounce = true },
	snow = { n = 1, colors = { "white", "white", "window" }, out = { 0.2, 0.6 }, up = { -1.8, -1.2 }, grav = 0, life = { 4.5, 5.5 }, size = { 0.25, 0.25 }, sway = 1.0 },
	heal = { n = 6, colors = { "green", "white", "leaf" }, out = { 0.5, 1.5 }, up = { 2, 4 }, grav = -1, life = { 0.6, 0.9 }, size = { 0.25, 0.35 }, neon = true, sway = 0.6 },
	heart = { n = 8, colors = { "pink", "berry_red", "white" }, out = { 1, 3 }, up = { 3, 6 }, grav = 4, life = { 0.7, 1.1 }, size = { 0.25, 0.4 }, neon = true, sway = 0.8 },
}
local POOL = 56

local function rnd(r: { number }): number
	return r[1] + (r[2] - r[1]) * math.random()
end

type Bit = { p: BasePart, pos: Vector3, vel: Vector3, life: number, age: number, size: number, grav: number, bounce: boolean, grow: boolean, sway: number, ph: number }

-- room space (world-aligned x, z from the floor's middle; y over the floor's top)
local function atXZ(x: number, z: number, y: number): Vector3
	return ORIGIN + Vector3.new(x, FLOOR + y, z)
end

-- A bird's, bat's or butterfly's wings beat: up a moment, then down.
local function flap(t: Thing, cf: CFrame, phase: number)
	MicroModels.place(t, cf)
	local up = if phase % 1 < 0.5 then 0.3 else -0.15
	for _, n in { "WingL", "WingR" } do
		local w = t.parts[n]
		if w then
			w.CFrame = cf * t.rest[n] * CFrame.new(0, up, 0)
		end
	end
end

local function recolorThing(t: Thing, color: string)
	for _, p in t.parts do
		p.Color = Blocks.color(color)
	end
	PixelRenderer.refreshDynamic(t.model)
end

------------------------------------------------------------------ the stages' ambient life
-- Per variant: what moves on the stage while the game plays (built when the stage opens; update(t, dt) every frame).
type Ambient = (st: Stage) -> (t: number, dt: number) -> ()
local AMBIENT: { [string]: Ambient } = {}

-- A bird (or bat) flying a loop over the stage: centre (room x, z), radius, height, period, colour.
local function circler(st: Stage, kind: string, color: string, x: number, z: number, r: number, h: number, period: number, ph: number): (t: number) -> ()
	local b = st.spawn(kind, { color = color, alt = if color == "black" then "black" else "orange" })
	return function(t: number)
		local a = (t / period + ph) * math.pi * 2
		local px, pz = x + math.cos(a) * r, z + math.sin(a) * r
		local cf = CFrame.lookAt(atXZ(px, pz, h + math.sin(t * 2 + ph) * 0.4), atXZ(x + math.cos(a + 0.2) * r, z + math.sin(a + 0.2) * r, h))
		flap(b, cf, t * (if kind == "butterfly" then 5 else 3) + ph)
	end
end

-- A butterfly wandering over the floor.
local function wanderer(st: Stage, color: string, x: number, z: number, ph: number): (t: number) -> ()
	local b = st.spawn("butterfly", { color = color }, 0.3)
	return function(t: number)
		local px = x + math.sin(t * 0.9 + ph) * 5
		local pz = z + math.sin(t * 0.6 + ph * 2) * 4
		local nx = x + math.sin((t + 0.1) * 0.9 + ph) * 5
		local nz = z + math.sin((t + 0.1) * 0.6 + ph * 2) * 4
		local h = 2.2 + math.sin(t * 3 + ph) * 0.5
		flap(b, CFrame.lookAt(atXZ(px, pz, h), atXZ(nx, nz, h)), t * 6 + ph)
	end
end

-- A light blinking at a world point.
local function blinker(st: Stage, at: Vector3, color: string, period: number, ph: number): (t: number) -> ()
	local l = st.spawn("light", { color = color })
	MicroModels.place(l, CFrame.new(at))
	return function(t: number)
		MicroModels.show(l, ((t / period + ph) % 1) < 0.5)
	end
end

-- A flame flickering over a torch or a candle (room space).
local function flicker(st: Stage, x: number, z: number, y: number, ph: number): (t: number) -> ()
	local f = st.spawn("flame")
	return function(t: number)
		local k = math.floor(t * 12 + ph) % 3
		MicroModels.scale(f, Vector3.new(1, 0.8 + k * 0.2, 1))
		MicroModels.place(f, CFrame.new(atXZ(x, z, y)))
		if math.random() < 0.03 then
			st.puff(atXZ(x, z, y + 0.8), "ember")
		end
	end
end

-- Every `every` seconds a bit of `kind` from a room point (steam, smoke, bubbles...).
local function emitter(st: Stage, kind: string, at: () -> Vector3, every: number): (t: number) -> ()
	local nextAt = 0
	return function(t: number)
		if t >= nextAt then
			nextAt = t + every * (0.7 + 0.6 * math.random())
			st.puff(at(), kind)
		end
	end
end

local function all(list: { (t: number) -> () }): (t: number, dt: number) -> ()
	return function(t: number, _dt: number)
		for _, f in list do
			f(t)
		end
	end
end

AMBIENT.blocks = function(st)
	return all({
		blinker(st, ORIGIN + Vector3.new(-18, 15.5, -27), "berry_red", 1.2, 0),
		blinker(st, ORIGIN + Vector3.new(0, 11.5, -27), "berry_red", 1.2, 0.5),
		blinker(st, ORIGIN + Vector3.new(-27, 14, -6), "yellow", 2.0, 0.3),
		circler(st, "bird", "steel", -6, -6, 16, 13, 9, 0),
	})
end

AMBIENT.race = function(st)
	return all({ circler(st, "bird", "white", 0, 0, 18, 11, 8, 0.4) })
end

AMBIENT.flip = function(st)
	return all({ emitter(st, "steam", function()
		return atXZ(math.random() - 0.5, math.random() - 0.5, 4.1)
	end, 0.18) })
end

AMBIENT.kick = function(st)
	local flags: { Thing } = {}
	local spots = { { -HALF - 7, -8 }, { -HALF - 7, 4 }, { -4, -HALF - 7 }, { 8, -HALF - 7 } }
	for i, sp in spots do
		local f = st.spawn("flag")
		flags[i] = f
		local _ = sp
	end
	return function(t: number, _dt: number)
		for i, f in flags do
			local sp = spots[i]
			MicroModels.scale(f, Vector3.new(1, 1, 1))
			MicroModels.place(f, CFrame.new(ORIGIN + Vector3.new(sp[1], 5, sp[2])))
			local cloth = f.parts.Cloth
			if cloth then
				local wave = math.floor(t * 6 + i) % 2
				cloth.Size = Vector3.new(1.25, 0.75 - wave * 0.25, 0.25)
			end
		end
	end
end

AMBIENT.strike = function(st)
	return all({
		flicker(st, -HALF + 0.5, -3.75, 4.25 - FLOOR + 0.6, 0),
		flicker(st, -HALF + 0.5, 6.25, 4.25 - FLOOR + 0.6, 1),
		flicker(st, 4.25, -HALF + 0.5, 4.25 - FLOOR + 0.6, 2),
	})
end

AMBIENT.pet = function(st)
	local yarn = st.spawn("yarn", nil, 0.5)
	return function(t: number, _dt: number)
		local x = math.sin(t * 0.8) * 5
		MicroModels.place(yarn, CFrame.new(atXZ(x, -7, 0)) * CFrame.Angles(0, 0, -x * 0.8))
	end
end

AMBIENT.space = function(st)
	local ufo = st.spawn("ufo")
	local twinkles = {}
	for i = 1, 6 do
		table.insert(twinkles, blinker(st, ORIGIN + Vector3.new(-30 + i * 9, 0.6, -24 + (i % 3) * 3), "white", 1.5 + i * 0.2, i * 0.37))
	end
	return function(t: number, _dt: number)
		for _, f in twinkles do
			f(t)
		end
		MicroModels.place(ufo, CFrame.new(ORIGIN + Vector3.new(-26 + math.sin(t * 0.5) * 4, 8 + math.sin(t * 2) * 0.6, -14)))
		ufo.parts.Light.Transparency = if math.floor(t * 4) % 2 == 0 then 0 else 1
	end
end

AMBIENT.water = function(st)
	return all({ wanderer(st, "yellow", -4, -4, 0), wanderer(st, "pink", 5, 3, 2), circler(st, "bird", "white", 0, 0, 20, 10, 10, 0.2) })
end

AMBIENT.zombie = function(st)
	return all({
		circler(st, "bird", "black", -4, -6, 7, 8, 4, 0),
		circler(st, "bird", "black", 5, -2, 6, 9.5, 5, 0.5),
		emitter(st, "smoke", function()
			return atXZ(-HALF - 2 + math.random() * 4, -8 + math.random() * 16, 0.3)
		end, 0.5),
	})
end

AMBIENT.match = function(st)
	local ball = st.spawn("ball", nil, 0.8)
	recolorThing(ball, "berry_red")
	return function(t: number, _dt: number)
		local k = (t * 1.6) % 1
		local y = 3.5 * 4 * k * (1 - k)
		MicroModels.scale(ball, if y < 0.2 then Vector3.new(1.2, 0.75, 1.2) else Vector3.one)
		MicroModels.place(ball, CFrame.new(atXZ(8, -9, y)))
	end
end

AMBIENT.answer = function(st)
	local plane = st.spawn("plane", nil, 0.4)
	return function(t: number, _dt: number)
		local k = (t / 5) % 1
		local u = -16 + 32 * k
		local p = st.at(u, -4 + math.sin(k * math.pi * 2) * 2, 5 + math.sin(k * math.pi * 4) * 0.8)
		local q = st.at(u + 1, -4 + math.sin((k + 0.03) * math.pi * 2) * 2, 5)
		MicroModels.place(plane, CFrame.lookAt(p, q))
	end
end

AMBIENT.count = function(st)
	local flags: { Thing } = {}
	for i, at in { { 6.5, -7 }, { -7, 7 } } do
		local f = st.spawn("flag", nil, 0.4)
		MicroModels.scale(f, Vector3.one * 0.7)
		MicroModels.place(f, CFrame.new(atXZ(at[1], at[2], 0.25)))
		flags[i] = f
	end
	return function(t: number, _dt: number)
		for i, f in flags do
			local cloth = f.parts.Cloth
			if cloth then
				cloth.Size = Vector3.new(0.875, if math.floor(t * 6 + i) % 2 == 0 then 0.5 else 0.375, 0.175)
			end
		end
	end
end

AMBIENT.spot = function(st)
	return all({ emitter(st, "steam", function()
		return atXZ(-11, -10, 4.9)
	end, 0.35) })
end

AMBIENT.cast = function(st)
	local book = st.spawn("book", nil, 0.5)
	local sparkle = emitter(st, "twinkle", function()
		return atXZ(-10 + math.random() * 20, -10 + math.random() * 20, 1 + math.random() * 4)
	end, 0.12)
	return function(t: number, _dt: number)
		sparkle(t)
		MicroModels.place(book, CFrame.new(atXZ(-6, 6, 3 + math.sin(t * 2) * 0.4)) * CFrame.Angles(0, t * 0.6, 0))
	end
end

AMBIENT.program = function(st)
	local drone = st.spawn("drone", nil, 0.6)
	local list = {}
	for i, c in { "screen_code", "berry_red", "yellow", "screen_on" } do
		table.insert(list, blinker(st, atXZ(6.75 + i, -9.85, 0.75 + (i % 2) * 0.5), c, 0.6 + i * 0.25, i * 0.3))
	end
	return function(t: number, _dt: number)
		for _, f in list do
			f(t)
		end
		local p = atXZ(math.sin(t * 0.7) * 6, -6 + math.cos(t * 0.5) * 2, 6 + math.sin(t * 3) * 0.3)
		flap(drone, CFrame.new(p) * CFrame.Angles(0, t, 0), t * 10)
	end
end

AMBIENT.simon = function(st)
	-- stage lights sweeping the back of the floor (purple and pink: never the pads' colours)
	local spots: { Thing } = {}
	local colors = { "purple", "pink", "purple", "pink" }
	for i = 1, 3 do
		spots[i] = st.spawn("spot", { color = colors[i] })
	end
	return function(t: number, _dt: number)
		for i, sp in spots do
			local a = t * 0.8 + i * 2.1
			MicroModels.place(sp, CFrame.new(atXZ(-7 + math.cos(a) * 3, -7 + math.sin(a * 1.3) * 3, 0)))
			sp.parts.Tile.Color = Blocks.color(colors[(math.floor(t * 2) + i) % #colors + 1])
		end
		for _, sp in spots do
			PixelRenderer.refreshDynamic(sp.model)
		end
	end
end

AMBIENT.loot = function(st)
	return all({
		circler(st, "bird", "white", -6, -6, 12, 9, 7, 0),
		emitter(st, "twinkle", function()
			return atXZ(8.5 + math.random() * 2 - 1, -10 + math.random() - 0.5, 2.4)
		end, 0.4),
	})
end

AMBIENT.fish = function(st)
	local crab = st.spawn("crab", nil, 0.6)
	local bubbles = emitter(st, "bubble", function()
		local i = math.random(0, 6)
		return atXZ(-HALF + 0.75, -HALF + 1 + i * 3.5, 1 + math.random() * 2)
	end, 0.25)
	return function(t: number, _dt: number)
		bubbles(t)
		local x = math.sin(t * 0.6) * 7
		MicroModels.place(crab, CFrame.new(atXZ(x, -9, 0)) * CFrame.new(0, if math.floor(t * 8) % 2 == 0 then 0.05 else 0, 0))
	end
end

AMBIENT.frost = function(st)
	return all({
		emitter(st, "snow", function()
			return st.at(-16 + math.random() * 32, -14 + math.random() * 22, 11)
		end, 0.12),
		circler(st, "bird", "white", -6, -6, 15, 12, 10, 0.3),
	})
end

AMBIENT.leap = function(st)
	return all({ wanderer(st, "yellow", -5, -6, 0), wanderer(st, "blue", 6, 6, 1.5), circler(st, "bird", "white", -4, -4, 16, 12, 9, 0.6) })
end

AMBIENT.dino = function(st)
	return all({
		circler(st, "bird", "hair_brown", VOLCANO.x, VOLCANO.z, 7, 12, 7, 0),
		emitter(st, "smoke", function()
			return ORIGIN + Vector3.new(VOLCANO.x + math.random() * 2 - 1, 10.5, VOLCANO.z + math.random() * 2 - 1)
		end, 0.3),
	})
end

AMBIENT.beat = function(st)
	local tiles: { Thing } = {}
	local colors = { "yellow", "screen_on", "pink", "purple", "screen_code" }
	local cells = { { -10, -10 }, { -10, -2 }, { -10, 6 }, { -2, -10 }, { 6, -10 } }
	for i = 1, #cells do
		tiles[i] = st.spawn("spot", { color = colors[i] })
	end
	return function(t: number, _dt: number)
		local beat = math.floor(t * 2)
		for i, tl in tiles do
			local c = cells[(i + beat) % #cells + 1]
			MicroModels.place(tl, CFrame.new(atXZ(c[1], c[2], 0)))
			tl.parts.Tile.Color = Blocks.color(colors[(i + beat * 2) % #colors + 1])
			PixelRenderer.refreshDynamic(tl.model)
		end
	end
end

AMBIENT.fruit = function(st)
	return all({ emitter(st, "petal", function()
		return st.at(-14 + math.random() * 28, -10 + math.random() * 14, 10)
	end, 0.25) })
end

AMBIENT.ghost = function(st)
	return all({
		flicker(st, -HALF + 0.75, -7.75, 1.6, 0),
		flicker(st, -HALF + 0.75, 4.25, 1.6, 1.3),
		emitter(st, "twinkle", function()
			return atXZ(-10 + math.random() * 20, -10 + math.random() * 20, 0.5 + math.random() * 3)
		end, 0.5),
	})
end

AMBIENT.tower = function(st)
	return all({ circler(st, "bird", "white", 0, -4, 14, 14, 8, 0.1) })
end

local current: Stage? = nil

-- `margins`: art px kept clear at the top and bottom of the screen for the overlay (default 22 and 20).
function MicroStage.open(variant: string, margins: { top: number, bottom: number }?): Stage
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

	-- the pool of 3D bits
	local pool = Blocks.model(nil, "MicroPuffs")
	local bits: { Bit } = {}
	local idle = uv(0, 0, -3)
	for i = 1, POOL do
		local p = Blocks.part(pool, { size = Vector3.one * 0.5, cf = CFrame.new(idle), color = "white", collide = false, query = false, transparency = 1, name = "Bit" .. i })
		p.CastShadow = false
		bits[i] = { p = p, pos = idle, vel = Vector3.zero, life = 0, age = 1, size = 0.5, grav = 0, bounce = false, grow = false, sway = 0, ph = 0 }
	end
	pool.Parent = dyn
	PixelRenderer.registerDynamic(pool)
	local cursor = 0
	local poolDirty = false
	local liftAt: number? = nil
	local landed = false
	local ENTRY_H = 8
	local function register(t: Thing, shadow: number?)
		if shadow and shadow > 0 then
			t.model:SetAttribute("PixelShadow", shadow)
			t.model:SetAttribute("PixelGroundY", groundY)
		end
		t.model.Parent = dyn
		PixelRenderer.registerDynamic(t.model)
		table.insert(things, t)
	end

	local rivals: { CharacterModels.Rig } = {}
	local ambient: ((t: number, dt: number) -> ())? = nil
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
			-- the entrance: high above until the curtain lifts, then a drop and a puff of dust on landing
			local entry = ENTRY_H
			local la = liftAt
			if la then
				local e = math.clamp((os.clock() - la) / 0.32, 0, 1)
				entry = ENTRY_H * (1 - e) * (1 - e)
				if e >= 1 and not landed then
					landed = true
					st.puff(uv(u, v, 0.2), "dust", 10)
					Audio.play("pop", { pitch = 0.75 })
				end
			end
			local act = if entry > 0.05 then "jump" else action
			CharacterModels.poseAction(rig, CFrame.new(uv(u, v, y + entry)) * CFrame.Angles(0, yaw, 0), t, speed, act, k)
			local hand = rig.parts.HandR
			if avatar.held and hand then
				MicroModels.place(avatar.held :: Thing, hand.CFrame * CFrame.new(0, -0.1, 0))
			end
			local head = rig.parts.Head
			if avatar.hat and head then
				MicroModels.place(avatar.hat :: Thing, head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.2, 0))
			end
		end,
		puff = function(pos: Vector3, kind: string, n: number?, color: string?)
			local spec = PUFFS[kind] or PUFFS.dust
			for i = 1, n or spec.n do
				cursor = cursor % POOL + 1
				local b = bits[cursor]
				local a = math.random() * math.pi * 2
				local out = rnd(spec.out)
				b.pos = pos
				b.vel = Vector3.new(math.cos(a) * out, rnd(spec.up), math.sin(a) * out)
				b.life = rnd(spec.life)
				b.age = 0
				b.size = rnd(spec.size)
				b.grav = spec.grav
				b.bounce = spec.bounce == true
				b.grow = spec.grow == true
				b.sway = spec.sway or 0
				b.ph = math.random() * 6
				b.p.Color = Blocks.color(color or spec.colors[(i - 1) % #spec.colors + 1])
				b.p.Material = if spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
				b.p.Transparency = 0
			end
			poolDirty = true
		end,
		rival = function(look: Types.Look, delay: number): Rival
			local rr = CharacterModels.buildStanding(look, "MicroRival", #rivals + 2)
			rr.model:SetAttribute("PixelShadow", 1.4)
			rr.model:SetAttribute("PixelGroundY", groundY)
			rr.model.Parent = dyn
			PixelRenderer.registerDynamic(rr.model)
			table.insert(rivals, rr)
			local down = false
			return {
				rig = rr,
				pose = function(u: number, v: number, y: number, yaw: number, t: number, speed: number, action: string, k: number?)
					local entry = ENTRY_H
					local la = liftAt
					if la then
						local e = math.clamp((os.clock() - la - delay) / 0.32, 0, 1)
						entry = ENTRY_H * (1 - e) * (1 - e)
						if e >= 1 and not down then
							down = true
							st.puff(uv(u, v, 0.2), "dust", 6)
						end
					end
					local act = if entry > 0.05 then "jump" else action
					CharacterModels.poseAction(rr, CFrame.new(uv(u, v, y + entry)) * CFrame.Angles(0, yaw, 0), t, speed, act, k)
				end,
				hide = function()
					CharacterModels.poseAction(rr, CFrame.new(uv(0, 0, -60)), 0, 0, "stand")
				end,
			}
		end,
		lift = function()
			if liftAt == nil then
				liftAt = os.clock()
			end
		end,
		step = function(t: number, dt: number)
			local floorY = groundY
			for _, b in bits do
				if b.age < b.life then
					b.age += dt
					if b.age >= b.life then
						b.p.Transparency = 1
						b.p.CFrame = CFrame.new(idle)
					else
						b.vel += Vector3.new(0, -b.grav * dt, 0)
						local sway = if b.sway > 0 then Vector3.new(math.sin(b.age * 5 + b.ph), 0, math.cos(b.age * 4 + b.ph)) * b.sway * dt else Vector3.zero
						b.pos += b.vel * dt + sway
						if b.bounce and b.pos.Y < floorY + b.size / 2 then
							b.pos = Vector3.new(b.pos.X, floorY + b.size / 2, b.pos.Z)
							b.vel = Vector3.new(b.vel.X * 0.55, -b.vel.Y * 0.35, b.vel.Z * 0.55)
						end
						local k = b.age / b.life
						local sz = if b.grow then b.size * (0.6 + 0.9 * k) * math.min(1, (1 - k) / 0.3) else b.size * math.min(1, (1 - k) / 0.4)
						sz = math.max(0.12, sz)
						b.p.Size = Vector3.one * sz
						b.p.CFrame = CFrame.new(b.pos)
					end
				end
			end
			if poolDirty then
				poolDirty = false
				PixelRenderer.refreshDynamic(pool)
			end
			local amb = ambient
			if amb then
				amb(t, dt)
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
			for _, rr in rivals do
				PixelRenderer.unregisterDynamic(rr.model)
				rr.model:Destroy()
			end
			table.clear(rivals)
			PixelRenderer.unregisterDynamic(pool)
			pool:Destroy()
			folder:Destroy()
			PixelRenderer.setOffset(0, 0)
			if current == st then
				current = nil
				CameraController.setStage(nil)
			end
		end,
	}
	st.pose(0, 2, 0, MicroStage.FACE_VIEWER, 0, 0, "stand")
	local build = AMBIENT[variant]
	ambient = if build then build(st) else nil

	-- the camera frames the room: its floor, the walls' tops, a little over the floor's front
	local pts: { number } = {}
	local wallTop = math.max(b.h, 3) + FLOOR
	for _, c in { { -HALF - 1, 0, -HALF - 1 }, { HALF + 1, 0, -HALF - 1 }, { -HALF - 1, 0, HALF + 1 }, { HALF + 1, 0, HALF + 1 }, { -HALF - 1, wallTop, -HALF - 1 }, { HALF + 1, wallTop, -HALF - 1 }, { -HALF - 1, wallTop, HALF + 1 } } do
		table.insert(pts, ORIGIN.X + c[1])
		table.insert(pts, ORIGIN.Y + c[2])
		table.insert(pts, ORIGIN.Z + c[3])
	end
	current = st
	CameraController.setStage({ name = variant, origin = ORIGIN, pts = pts, top = if margins then margins.top else 22, bottom = if margins then margins.bottom else 20 })
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
