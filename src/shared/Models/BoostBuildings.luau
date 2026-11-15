--!strict
-- The island's boost buildings (kind "gen": every building of a knack makes more), from parts (GAME_DESIGN 4;
-- Data/Buildings). Each builder takes the model, the frame at the footprint's centre on the grass (facing +Z before
-- the piece's turn) and the level, and stays inside the footprint. The pieces they share are Models/BuildKit's; the
-- few below (a pitched roof of slabs, windows, doors, lanterns, crates, barrels) are this module's own.
-- Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.")
-- Every size is a whole number of quarter studs (Blocks snaps them) and trims stand an eighth or a sixteenth proud of
-- the face they are on, so no two faces share a plane. The camera looks down from the south-east, so the detail is on
-- the front (+Z), the east side (+X) and the roofs, and nothing worth seeing hides under a deep eave. The back-left
-- corner stays low for the upgrade pennant.
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local log = K.log
local wedge = K.wedge
local sack = K.sack
local streetLamp = K.streetLamp

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"
local B: { [string]: Builder } = {}

local HALF_PI = math.pi / 2

------------------------------------------------------------------ this module's pieces

-- A part at `cf` in f (turned any way).
local function at(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: Shape?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, name = name, shape = shape, neon = neon, collide = false })
end

-- A disc facing the front: a cylinder along Z, `dia` across and `t` thick.
local function disc(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string): BasePart
	return at(m, f, CFrame.new(x, y, z) * CFrame.Angles(0, HALF_PI, 0), t, dia, dia, color, name, "Cylinder")
end

-- The frame of a face looking east (+X) at (x, z): its +Z is the world's +X, its +X the world's -Z. The front-face
-- pieces below put in it land on the east side.
local function east(f: CFrame, x: number, z: number): CFrame
	return f * CFrame.new(x, 0, z) * CFrame.Angles(0, HALF_PI, 0)
end

-- A pitched roof along X in f: two slabs a quarter stud thick from a ridge at (0, yr, 0) down a slope of k (rise over
-- run), `fl` studs long toward +Z (the side the camera sees) and `bl` toward -Z (none when 0), `w` wide; rows of
-- `course` across the front slab every half stud; a ridge cap of `cap` (birds sit on it); a fascia of `trim` along the
-- front eave and, on a roof long enough to carry them, a verge of it up each end of each slab.
local function pitched(m: Instance, f: CFrame, yr: number, w: number, k: number, fl: number, bl: number, color: string, course: string?, cap: string?, trim: string, verge: boolean?)
	local th = math.atan(k)
	local c, s = math.cos(th), math.sin(th)
	for _, side in { 1, -1 } do
		local len = if side == 1 then fl else bl
		if len > 0 then
			-- the slab's top face runs from the ridge down; its middle is half its thickness under that face
			local mz, my = side * c * len / 2, yr - s * len / 2
			local turn = CFrame.Angles(side * th, 0, 0)
			at(m, f, CFrame.new(0, my - c * 0.125, mz - side * s * 0.125) * turn, w, 0.25, len, color, "RoofSlab")
			if verge then
				for _, sx in { -1, 1 } do
					at(m, f, CFrame.new(sx * (w / 2 - 0.0625), my - c * 0.0625, mz - side * s * 0.0625) * turn, 0.25, 0.25, len, trim, "Verge")
				end
			end
		end
	end
	if course then
		local t = 0.375
		while t <= fl - 0.125 do
			at(m, f, CFrame.new(0, yr - s * t - c * 0.0625, c * t - s * 0.0625) * CFrame.Angles(th, 0, 0), if verge then w - 0.5 else w, 0.25, 0.25, course, "Shingles")
			t += 0.5
		end
	end
	if cap then
		box(m, f, 0, yr, 0, w, 0.25, 0.25, cap, "Ridge")
	end
	box(m, f, 0, yr - s * fl - 0.125, c * fl - 0.125, w, 0.25, 0.25, trim, "Fascia")
end

-- The ridge height for a pitched roof whose gable (see `gable`) rises h over a half depth of hd from y0.
local function ridgeOver(y0: number, hd: number, h: number): number
	return y0 + h + 0.25 / math.cos(math.atan(h / hd))
end

-- The gable ends' fill under a pitched roof along X in f: two wedges of `color`, `w` long and centred at x, rising
-- `h` from y0 to a ridge at z 0, `d` deep in all (a whole number of half studs, so each wedge stays on the grid).
local function gable(m: Instance, f: CFrame, x: number, y0: number, w: number, d: number, h: number, color: string)
	wedge(m, f, x, y0 + h / 2, d / 4, w, h, d / 2, color, math.pi, "Gable")
	wedge(m, f, x, y0 + h / 2, -d / 4, w, h, d / 2, color, 0, "Gable")
end

-- A window in a face looking front whose surface is at z: a frame of `frame`, the glass, a bar down the middle when
-- it is wide enough and across when it is tall enough; shutters of `shut` either side when given; under it a sill, or
-- nothing when `under` is "none", or a box of flowers when `under` names their colour.
local function win(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, frame: string, shut: string?, under: string?)
	box(m, f, x, y, z + 0.0625, w + 0.25, h + 0.25, 0.25, frame, "WindowFrame")
	box(m, f, x, y, z + 0.125, w, h, 0.25, "window", "Glass")
	if w >= 0.75 then
		box(m, f, x, y, z + 0.1875, 0.25, h, 0.25, frame, "Bar")
	end
	if h >= 0.75 then
		box(m, f, x, y, z + 0.15625, w, 0.25, 0.25, frame, "Bar")
	end
	if shut then
		for _, sx in { -1, 1 } do
			box(m, f, x + sx * (w / 2 + 0.25), y, z + 0.0625, 0.25, h + 0.25, 0.25, shut, "Shutter")
		end
	end
	local y0 = y - h / 2 - 0.25
	if under == "none" then
		return
	elseif under then
		box(m, f, x, y0, z + 0.3125, w + 0.25, 0.25, 0.25, "wood", "FlowerBox")
		local n = math.floor((w + 0.25) / 0.25 + 0.5)
		for i = 0, n - 1 do
			local bx = x - (w + 0.25) / 2 + 0.125 + i * 0.25
			ball(m, f, bx, y0 + 0.1875, z + 0.3125, 0.25, if i % 2 == 0 then "leaf" else under, if i % 2 == 0 then "Leaf" else "Flower")
		end
	else
		box(m, f, x, y0, z + 0.1875, w + 0.5, 0.25, 0.25, frame, "Sill")
	end
end

-- A door in a face looking front whose surface is at z, its foot at y0: a frame of `frame` with its lintel, the door
-- of `color`, a brass knob.
local function doorway(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, h: number, color: string, frame: string)
	box(m, f, x, y0 + (h + 0.25) / 2, z + 0.0625, w + 0.25, h + 0.25, 0.25, frame, "DoorFrame")
	box(m, f, x, y0 + h / 2, z + 0.125, w, h, 0.25, color, "Door")
	ball(m, f, x + w / 2 - 0.125, y0 + h / 2, z + 0.25, 0.25, "gold", "Knob")
end

-- A lantern on a face looking front whose surface is at z: an iron bracket on the wall and the lamp hung under it.
local function lantern(m: Instance, f: CFrame, x: number, y: number, z: number)
	box(m, f, x, y + 0.25, z + 0.125, 0.25, 0.25, 0.25, "black", "LampArm")
	box(m, f, x, y, z + 0.1875, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
end

-- A clump of flowers on the ground at (x, y, z): a round bush and two blooms on its front.
local function bloomBush(m: Instance, f: CFrame, x: number, y: number, z: number, a: string, b: string)
	ball(m, f, x, y + 0.25, z, 0.5, "leaf", "Bush")
	ball(m, f, x - 0.125, y + 0.4375, z + 0.125, 0.25, a, "Flower")
	ball(m, f, x + 0.125, y + 0.375, z + 0.1875, 0.25, b, "Flower")
end

-- A crate of s on (x, y, z): a dark frame and lighter boards on its front, east side and lid.
local function crate(m: Instance, f: CFrame, x: number, y: number, z: number, s: number, frame: string?, boards: string?)
	local fr, bd = frame or "wood_dark", boards or "wood"
	box(m, f, x, y + s / 2, z, s, s, s, fr, "Crate")
	box(m, f, x, y + s / 2, z + s / 2 - 0.0625, s - 0.25, s - 0.25, 0.25, bd, "Boards")
	box(m, f, x + s / 2 - 0.0625, y + s / 2, z, 0.25, s - 0.25, s - 0.25, bd, "Boards")
	box(m, f, x, y + s - 0.0625, z, s - 0.25, 0.25, s - 0.25, bd, "Boards")
end

-- A barrel on (x, y, z): staves of `color` with a dark hoop round its middle, three quarters of a stud tall.
local function keg(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?)
	cyl(m, f, x, y + 0.125, z, dia, 0.25, color or "wood", "Barrel")
	cyl(m, f, x, y + 0.375, z, dia, 0.25, "steel_dark", "Hoop")
	cyl(m, f, x, y + 0.625, z, dia, 0.25, color or "wood", "Barrel")
end

------------------------------------------------------------------ the buildings

-- Tool Shed (2 x 2): a plank shed on a stone plinth in a yard of packed earth, its gable to the front: a green door
-- with a little window, a lucky horseshoe over it and a lantern under the tie beam, a tin roof in rows with a stove
-- pipe that smokes and a gold knob, a sign of two crossed axes hung out from the corner on an iron bracket. A board on
-- the east wall holds a saw and a hammer over three paint pots on the plinth; a grindstone with its crank, a pile of
-- split logs and a rake stand on the west side.
B.toolshed = function(m, f)
	box(m, f, 0, 0, 0, 2, 0.25, 2, "sand_dark", "Footing")
	box(m, f, 0.25, 0.25, -0.25, 1.25, 0.25, 1.5, "rock", "Plinth")
	box(m, f, 0.25, 0.0625, 0.875, 0.5, 0.25, 0.25, "rock_dark", "SteppingStone")
	-- plank walls, dark corner posts, the tie beam across the front
	box(m, f, 0.25, 0.875, -0.25, 1, 1, 1.25, "wood", "Walls")
	for _, p in { { -0.1875, 0.3125 }, { 0.6875, 0.3125 }, { 0.6875, -0.8125 } } do
		box(m, f, p[1], 0.875, p[2], 0.25, 1, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0.25, 1.375, 0.5, 1.25, 0.25, 0.25, "wood_dark", "Beam")
	-- the roof runs front to back: its east slope (the one the camera sees) in rows of tin
	local g = f * CFrame.new(0.25, 0, -0.125) * CFrame.Angles(0, HALF_PI, 0)
	gable(m, g, 0.125, 1.375, 1.25, 1, 0.5, "wood")
	pitched(m, g, ridgeOver(1.375, 0.5, 0.5), 1.5, 1, 1, 0.75, "steel", "steel_dark", "steel_dark", "wood_dark")
	ball(m, f, 0.25, 2.375, 0.5, 0.25, "gold", "Finial")
	box(m, f, 0.5, 2, -0.625, 0.25, 0.5, 0.25, "steel_dark", "StovePipe")
	box(m, f, 0.5, 2.375, -0.625, 0.25, 0.25, 0.25, "black", "Chimney")
	-- the door, its step and the lantern
	doorway(m, f, 0.25, 0.375, 0.375, 0.5, 0.75, "green", "wood_dark")
	box(m, f, 0.25, 0.9375, 0.5625, 0.25, 0.25, 0.25, "window", "Glass")
	box(m, f, 0.25, 0.5, 0.5625, 0.5, 0.25, 0.25, "teal", "Batten")
	box(m, f, 0.25, 0.125, 0.625, 0.75, 0.25, 0.25, "rock", "Step")
	box(m, f, 0.75, 1.125, 0.5625, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
	box(m, f, 0.25, 1.375, 0.6875, 0.25, 0.25, 0.25, "gold", "Horseshoe")
	-- the sign hung out from the front corner: two axes crossed on a cream board
	box(m, f, -0.5, 1.6875, 0.3125, 0.5, 0.25, 0.25, "black", "SignArm")
	box(m, f, -0.625, 1.25, 0.3125, 0.5, 0.75, 0.25, "cream", "Sign")
	for k, sx in { -1, 1 } do
		local z = 0.3125 + k * 0.0625
		at(m, f, CFrame.new(-0.625, 1.1875, z) * CFrame.Angles(0, 0, sx * math.rad(40)), 0.25, 0.5, 0.25, "wood_dark", "SignHandle")
		box(m, f, -0.625 - sx * 0.125, 1.375, z + 0.0625, 0.25, 0.25, 0.25, "steel", "SignHead")
	end
	-- the east wall's tool board: a saw along the top, a hammer under it; paint pots on the plinth below
	box(m, f, 0.75, 1, -0.25, 0.25, 0.75, 0.75, "wood_dark", "ToolBoard")
	box(m, f, 0.875, 1.125, -0.375, 0.25, 0.25, 0.5, "steel", "SawBlade")
	box(m, f, 0.875, 1.125, 0, 0.25, 0.25, 0.25, "wood", "SawHandle")
	box(m, f, 0.875, 0.875, -0.375, 0.25, 0.25, 0.5, "steel_dark", "HammerHead")
	box(m, f, 0.875, 0.625, -0.375, 0.25, 0.25, 0.25, "berry_red", "HammerHandle")
	for k, c in { "berry_red", "blue", "yellow" } do
		cyl(m, f, 0.875, 0.5, -0.75 + k * 0.25, 0.25, 0.25, c, "PaintPot")
	end
	for k, p in { { 0.875, -0.75 }, { -0.875, 0.875 }, { 0.875, 0.25 } } do
		ball(m, f, p[1], 0.125, p[2], 0.25, "leaf", "Tuft")
		ball(m, f, p[1], 0.25, p[2], 0.25, if k == 2 then "yellow" else "pink", "Flower")
	end
	-- the grindstone on its stand, the crank on the side the camera sees
	box(m, f, -0.625, 0.25, 0.625, 0.5, 0.25, 0.5, "wood_dark", "Stand")
	log(m, f, -0.625, 0.625, 0.625, 0.75, 0.25, "wood_dark", "Axle")
	log(m, f, -0.625, 0.625, 0.625, 0.25, 0.5, "rock", "Grindstone")
	box(m, f, -0.125, 0.5, 0.625, 0.25, 0.25, 0.25, "wood", "Crank")
	box(m, f, -0.125, 0.75, 0.6875, 0.25, 0.25, 0.25, "black", "CrankHandle")
	cyl(m, f, -0.125, 0.25, 0.875, 0.25, 0.25, "steel", "Bucket")
	-- split logs against the west wall, their ends to the front, a rake leaning on them
	for k, p in { { -0.875, 0.25 }, { -0.625, 0.25 }, { -0.875, 0.5 }, { -0.625, 0.5 }, { -0.875, 0.75 }, { -0.625, 0.75 } } do
		disc(m, f, p[1], p[2], 0, 0.25, 0.5, if (k + (k - 1) // 2) % 2 == 0 then "wood" else "sand_dark", "Log")
	end
	at(m, f, CFrame.new(-0.4375, 0.75, 0.0625) * CFrame.Angles(math.rad(-15), 0, 0), 0.25, 1.25, 0.25, "wood", "RakeHandle")
	box(m, f, -0.4375, 1.375, -0.0625, 0.5, 0.25, 0.25, "steel_dark", "RakeHead")
end

-- Windmill (3 x 3): a white tower mill on a stone base with a wooden stage round its waist, a timber cap with a red
-- roof in rows, the shaft out of its cream front gable and four sails on it, each a white cloth with cream laths
-- across it on a dark stock. A door with a lantern and a step, windows (the east one with teal shutters and a box of
-- flowers), sacks of flour by the door, a spare millstone against the east side, flowers at its foot.
-- (The sails turn in the client, Controllers/Spinners: only the parts named SailArm and Sail turn, about the hub at
-- (0, 3.4, 0.9).)
B.windmill = function(m, f)
	box(m, f, 0, 0, 0, 3, 0.25, 3, "grass_dark", "Footing")
	box(m, f, 0, 0.0625, 1.25, 0.75, 0.25, 0.5, "pavement", "Path")
	-- the tower: stone plinth and base, the stage, the white tower, the cap's curb
	cyl(m, f, 0, 0.25, -0.25, 2, 0.25, "rock_dark", "Plinth")
	cyl(m, f, 0, 0.875, -0.25, 1.75, 1, "rock", "Base")
	cyl(m, f, 0, 1.5, -0.25, 2, 0.25, "wood", "Stage")
	cyl(m, f, 0, 2.25, -0.25, 1.5, 1.25, "white", "Tower")
	cyl(m, f, 0, 3, -0.25, 1.75, 0.25, "wood_dark", "Curb")
	-- the cap: a little gabled roof running front to back, the shaft out of its cream front gable
	local g = f * CFrame.new(0, 0, -0.0625) * CFrame.Angles(0, HALF_PI, 0)
	gable(m, g, 0.125, 3.125, 1.25, 1.5, 0.75, "cream")
	pitched(m, g, ridgeOver(3.125, 0.75, 0.75), 1.5, 1, 1.25, 1.25, "berry_red", "clay", "wood_dark", "wood_dark")
	ball(m, f, 0, 4.5, 0.5, 0.25, "gold", "Finial")
	disc(m, f, 0, 3.4, 0.625, 0.25, 0.25, "wood_dark", "Shaft")
	box(m, f, 0, 3.4, 0.75, 0.25, 0.25, 0.25, "wood_dark", "Hub")
	disc(m, f, 0, 3.4, 1.25, 0.5, 0.25, "steel_dark", "HubCap")
	-- four sails: the stock, the cloth in front of it and three laths across the cloth
	for k = 0, 3 do
		local a = k * HALF_PI + math.pi / 4
		local ca, sa = math.cos(a), math.sin(a)
		local turn = CFrame.Angles(0, 0, a - HALF_PI)
		at(m, f, CFrame.new(ca * 1, 3.4 + sa * 1, 0.9375) * turn, 0.25, 2, 0.25, "wood_dark", "SailArm")
		at(m, f, CFrame.new(ca * 1.125, 3.4 + sa * 1.125, 1) * turn, 0.5, 1.5, 0.25, "white", "Sail")
		for _, r in { 0.625, 1.125, 1.625 } do
			at(m, f, CFrame.new(ca * r, 3.4 + sa * r, 1.0625) * turn, 0.5, 0.25, 0.25, "cream", "Sail")
		end
	end
	-- the door in the stone base, its step and lantern
	doorway(m, f, 0, 0.375, 0.625, 0.5, 0.75, "wood", "wood_dark")
	box(m, f, 0, 0.25, 0.9375, 0.75, 0.25, 0.25, "rock", "Step")
	lantern(m, f, 0.625, 1, 0.375)
	-- windows: the tower's front and east, a small one in the base
	win(m, f, 0, 2.25, 0.5, 0.25, 0.5, "wood_dark", nil, "none")
	win(m, east(f, 0.75, -0.25), 0, 2.25, 0, 0.25, 0.5, "wood_dark", "teal", "pink")
	win(m, east(f, 0.875, -0.25), 0, 0.875, 0, 0.25, 0.25, "wood_dark")
	-- sacks of flour, the spare millstone, flowers
	sack(m, f, -1.125, 0.125, 1.125, "white")
	sack(m, f, -0.625, 0.125, 1.125, "cream")
	sack(m, f, -0.875, 0.625, 1.125, "cream")
	log(m, f, 1.25, 0.5, 0.5, 0.25, 0.75, "rock", "Millstone")
	log(m, f, 1.3125, 0.5, 0.5, 0.25, 0.25, "rock_dark", "MillstoneEye")
	bloomBush(m, f, 0.875, 0.125, 0.875, "pink", "yellow")
	bloomBush(m, f, -1.125, 0.125, 0.25, "yellow", "white")
end

-- Smokehouse (3 x 3): a dark plank house on a stone foundation under a slate roof in rows, a stone chimney through
-- the front slope and a louvred vent on the ridge, both smoking. Five fish hang from a pole along the front wall over
-- barrels, a salt crate and a basket of the catch; the door is round the east side with a lantern on the corner post,
-- and a pile of logs waits by it with the block they are split on, an axe in it.
B.smokehouse = function(m, f)
	box(m, f, 0, 0, 0, 3, 0.25, 3, "rock", "Footing")
	box(m, f, -0.25, 0.25, -0.125, 2.25, 0.25, 1.75, "rock_dark", "Foundation")
	box(m, f, -0.25, 1.125, -0.125, 2, 1.5, 1.5, "wood_dark", "Walls")
	for _, p in { { -1.1875, 0.5625 }, { 0.6875, 0.5625 }, { 0.6875, -0.8125 } } do
		box(m, f, p[1], 1.125, p[2], 0.25, 1.5, 0.25, "wood", "Post")
	end
	box(m, f, -0.25, 1.75, 0.5625, 1.5, 0.25, 0.25, "wood", "Plate")
	-- the roof along the house, its gable ends in the same dark boards
	local g = f * CFrame.new(-0.25, 0, -0.125)
	gable(m, g, 0, 1.875, 2, 1.5, 0.75, "wood_dark")
	local yr = ridgeOver(1.875, 0.75, 0.75)
	pitched(m, g, yr, 2.25, 1, 1.25, 1, "rock_dark", "slate", "rock_dark", "wood", true)
	-- the chimney up through the front slope, the vent on the ridge
	box(m, f, 0.25, 2.5, 0.25, 0.5, 1.25, 0.5, "rock", "ChimneyStack")
	box(m, f, 0.25, 3.25, 0.25, 0.75, 0.25, 0.75, "rock_dark", "Chimney")
	box(m, f, -0.75, yr + 0.375, -0.125, 0.5, 0.5, 0.5, "wood_dark", "Vent")
	box(m, f, -0.75, yr + 0.375, 0.0625, 0.25, 0.25, 0.25, "black", "Louvre")
	box(m, f, -0.5625, yr + 0.375, -0.125, 0.25, 0.25, 0.25, "black", "Louvre")
	-- the catch on its pole along the front wall
	for _, x in { -1, 0.5 } do
		box(m, f, x, 1.625, 0.75, 0.25, 0.25, 0.25, "black", "Bracket")
	end
	box(m, f, -0.25, 1.625, 0.875, 1.75, 0.25, 0.25, "wood", "Pole")
	local fish = { { "steel", "steel_dark" }, { "gold", "orange" }, { "white", "steel" } }
	for k = 0, 4 do
		local c = fish[k % 3 + 1]
		local x = -1 + k * 0.375
		box(m, f, x, 1.25, 0.875, 0.25, 0.5, 0.25, c[1], "Fish")
		box(m, f, x, 0.875, 0.875, 0.25, 0.25, 0.25, c[2], "FishTail")
	end
	-- a barrel, the salt crate and a basket of fish under them
	keg(m, f, -1.125, 0.125, 1.25, 0.5)
	crate(m, f, -0.5, 0.125, 1.1875, 0.5)
	box(m, f, -0.5, 0.75, 1.1875, 0.25, 0.25, 0.25, "white", "Salt")
	box(m, f, 0.125, 0.25, 1.25, 0.5, 0.25, 0.5, "straw", "Basket")
	box(m, f, 0.0625, 0.4375, 1.1875, 0.25, 0.25, 0.25, "steel", "Fish")
	box(m, f, 0.25, 0.4375, 1.3125, 0.25, 0.25, 0.25, "gold", "Fish")
	-- the door round the east side, a lantern beside it, a vent window in the gable
	local e = east(f, 0.75, -0.125)
	doorway(m, e, 0.0625, 0.375, 0, 0.5, 1, "wood", "black")
	box(m, f, 1, 0.25, -0.1875, 0.25, 0.25, 0.75, "rock", "Step")
	lantern(m, east(f, 0.75, 0.3125), 0, 1.375, 0)
	win(m, e, 0, 2.1875, 0, 0.25, 0.25, "wood", nil, "none")
	-- logs for the fire, their ends to the front, and the block they are split on with its axe
	for k, p in { { 1, 0.25 }, { 1.25, 0.25 }, { 1, 0.5 }, { 1.25, 0.5 }, { 1.125, 0.75 } } do
		disc(m, f, p[1], p[2], 0.8125, 0.25, 0.5, if k % 2 == 0 then "wood" else "sand_dark", "Log")
	end
	cyl(m, f, 0.625, 0.25, 1.25, 0.5, 0.25, "wood", "Block")
	at(m, f, CFrame.new(0.6875, 0.5625, 1.25) * CFrame.Angles(0, 0, math.rad(-30)), 0.25, 0.5, 0.25, "wood_dark", "AxeHandle")
	box(m, f, 0.5625, 0.4375, 1.25, 0.25, 0.25, 0.25, "steel", "AxeHead")
end

-- Market Hall (4 x 3): an open hall of stone columns on a raised floor under a long green roof in rows with cream
-- verges, a little bell cote on its ridge. Two stalls stand at the front under striped awnings, fruit on the left and
-- bunches of flowers on the right; a sign of an apple and a fish hangs over the way in between them, with a lantern
-- on each corner column, baskets of the same out on the paving. Inside, crates (apples on the top one), a sack and
-- barrels; a potted bush by the front corner and a round window in the east gable.
B.market = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 3, "pavement", "Footing")
	box(m, f, 0, 0.25, 0.125, 3.75, 0.25, 2.25, "rock", "Floor")
	box(m, f, 0, 0.125, 1.375, 1, 0.25, 0.25, "rock", "Step")
	-- the columns (bases and capitals on the two rows the camera sees), the beams on them
	for _, x in { -1.5, -0.5, 0.5, 1.5 } do
		for _, z in { -0.75, 0.75 } do
			if z > 0 or x > 1 then
				box(m, f, x, 1.25, z, 0.25, 1.25, 0.25, "cream", "Column")
				box(m, f, x, 0.5, z, 0.5, 0.25, 0.5, "pavement", "ColumnBase")
				box(m, f, x, 2, z, 0.5, 0.25, 0.5, "pavement", "Capital")
			else
				box(m, f, x, 1.25, z, 0.25, 1.75, 0.25, "cream", "Column")
			end
		end
	end
	for _, z in { -0.75, 0.75 } do
		box(m, f, 0, 2.25, z, 3.5, 0.25, 0.25, "wood_dark", "Beam")
	end
	for _, x in { -1.5, 1.5 } do
		box(m, f, x, 2.25, 0, 0.25, 0.25, 1.75, "wood_dark", "Beam")
		gable(m, f, x, 2.375, 0.25, 1.5, 0.75, "cream")
	end
	local yr = ridgeOver(2.375, 0.75, 0.75)
	pitched(m, f, yr, 3.75, 1, 1.5, 1, "green", "grass_dark", "wood_dark", "cream", true)
	-- the bell cote on the ridge: two white posts under a little green gable, the bell between them
	for _, x in { -0.375, 0.375 } do
		box(m, f, x, yr + 0.25, 0, 0.25, 0.75, 0.25, "white", "BellPost")
	end
	wedge(m, f, 0, yr + 0.75, -0.125, 1, 0.25, 0.25, "green", 0, "BellRoof")
	wedge(m, f, 0, yr + 0.75, 0.125, 1, 0.25, 0.25, "green", math.pi, "BellRoof")
	ball(m, f, 0, yr + 0.375, 0, 0.5, "gold", "Bell")
	log(m, f, 1.6875, 2.75, 0, 0.25, 0.5, "wood_dark", "RoundWindow")
	log(m, f, 1.75, 2.75, 0, 0.25, 0.25, "window", "Glass")
	-- the sign over the way in: an apple and a fish on a cream board; a lantern on each corner column
	box(m, f, 0, 1.875, 1.125, 0.75, 0.5, 0.25, "cream", "Sign")
	ball(m, f, -0.1875, 1.875, 1.3125, 0.25, "berry_red", "SignApple")
	box(m, f, 0.1875, 1.875, 1.3125, 0.25, 0.25, 0.25, "steel", "SignFish")
	for _, x in { -1.5, 1.5 } do
		lantern(m, f, x, 1.625, 0.875)
	end
	-- the two stalls: striped awnings out over counters of fruit and of flowers
	local stalls = { { x = -1, a = "berry_red", goods = { "berry_red", "orange", "yellow" } }, { x = 1, a = "blue", goods = { "pink", "yellow", "purple" } } }
	for _, st in stalls do
		for i = -1, 1 do
			local x = st.x + i * 0.25
			local c = if i == 0 then "white" else st.a
			at(m, f, CFrame.new(x, 1.75, 1.09) * CFrame.Angles(math.rad(30), 0, 0), 0.25, 0.25, 0.5, c, "Awning")
			box(m, f, x, 1.5, 1.3125, 0.25, 0.25, 0.25, c, "Flap")
		end
		box(m, f, st.x, 0.625, 1.125, 0.75, 0.5, 0.25, "wood", "Counter")
		for i, g in st.goods do
			local x = st.x + (i - 2) * 0.25
			ball(m, f, x, 1, 1.125, 0.25, g, if st.x < 0 then "Fruit" else "Flower")
		end
		box(m, f, st.x, 0.25, 1.375, 0.5, 0.25, 0.25, "straw", "Basket")
		for i = 1, 2 do
			ball(m, f, st.x + (i - 1.5) * 0.25, 0.4375, 1.375, 0.25, st.goods[i * 2 - 1], if st.x < 0 then "Fruit" else "Flower")
		end
	end
	-- inside: crates (apples on the top one) and a sack on the left, barrels on the right; a potted bush by the corner
	crate(m, f, -1, 0.375, 0, 0.5)
	crate(m, f, -1, 0.875, 0, 0.5)
	sack(m, f, -0.375, 0.375, -0.25, "sand_dark")
	keg(m, f, 0.625, 0.375, 0, 0.5)
	keg(m, f, 1.125, 0.375, -0.25, 0.5)
	for _, x in { -1.125, -0.875 } do
		ball(m, f, x, 1.4375, 0, 0.25, "berry_red", "Fruit")
	end
	box(m, f, -1.75, 0.5, 1.125, 0.25, 0.25, 0.25, "pot", "Pot")
	ball(m, f, -1.75, 0.875, 1.125, 0.5, "leaf", "Bush")
end

-- Water Tower (3 x 3): a round tank of wooden staves with three iron hoops and a stepped blue roof under a weather
-- vane, on a round deck with a railing, on four legs on stone footings with a girt round them and a cross of braces
-- above it. A ladder climbs the front to the deck; a pipe with a red valve wheel comes down to a trough of water. A
-- barrel, a bucket and flowers stand round.
B.watertower = function(m, f)
	for _, x in { -0.75, 0.75 } do
		for _, z in { -0.75, 0.75 } do
			box(m, f, x, 0.125, z, 0.5, 0.25, 0.5, "rock", "Footing")
			box(m, f, x, 1.5, z, 0.25, 2.75, 0.25, "wood_dark", "Leg")
		end
	end
	-- girts round the legs, a cross of braces above them on the two sides the camera sees
	box(m, f, 0, 1.375, 0.8125, 1.75, 0.25, 0.25, "wood", "Girt")
	box(m, f, 0.8125, 1.375, 0, 0.25, 0.25, 1.75, "wood", "Girt")
	box(m, f, 0, 1.375, -0.8125, 1.75, 0.25, 0.25, "wood", "Girt")
	box(m, f, -0.8125, 1.375, 0, 0.25, 0.25, 1.75, "wood", "Girt")
	local slant = math.atan(1.25 / 1.5)
	for k, sgn in { 1, -1 } do
		local o = 0.875 + (k - 1) * 0.0625
		at(m, f, CFrame.new(0, 2.0625, o) * CFrame.Angles(0, 0, sgn * slant), 2, 0.25, 0.25, "wood", "Brace")
		at(m, f, CFrame.new(o, 2.0625, 0) * CFrame.Angles(sgn * slant, 0, 0), 0.25, 0.25, 2, "wood", "Brace")
	end
	-- the deck and its railing round the front and east
	cyl(m, f, 0, 3, 0, 2.5, 0.25, "wood_dark", "Deck")
	local posts: { Vector3 } = {}
	for _, deg in { -45, 0, 45, 90, 135 } do
		local a = math.rad(deg)
		local p = Vector3.new(math.sin(a) * 1.125, 0, math.cos(a) * 1.125)
		table.insert(posts, p)
		box(m, f, p.X, 3.375, p.Z, 0.25, 0.5, 0.25, "wood", "RailPost")
	end
	for i = 1, #posts - 1 do
		local a, b = posts[i], posts[i + 1]
		local mid = (a + b) / 2
		at(m, f, CFrame.lookAt(Vector3.new(mid.X, 3.5, mid.Z), Vector3.new(b.X, 3.5, b.Z)), 0.25, 0.25, 0.75, "wood", "Rail")
	end
	-- the tank: staves, hoops, the stepped roof and its vane
	cyl(m, f, 0, 4, 0, 2, 1.75, "wood", "Tank")
	for _, deg in { -22.5, 22.5, 67.5, 112.5 } do
		local a = math.rad(deg)
		at(m, f, CFrame.new(math.sin(a) * 1, 4, math.cos(a) * 1) * CFrame.Angles(0, a, 0), 0.25, 1.75, 0.25, "wood_dark", "Stave")
	end
	for _, y in { 3.75, 4.25, 4.75 } do
		cyl(m, f, 0, y, 0, 2.25, 0.25, "steel_dark", "Hoop")
	end
	for k, dia in { 2.5, 2, 1.5, 1, 0.5 } do
		cyl(m, f, 0, 4.875 + k * 0.25 - 0.125, 0, dia, 0.25, if k % 2 == 1 then "blue" else "hair_blue", "Roof")
	end
	box(m, f, 0, 6.25, 0, 0.25, 0.25, 0.25, "black", "VanePost")
	box(m, f, 0.125, 6.5, 0, 0.5, 0.25, 0.25, "black", "Vane")
	-- the ladder up the front to the deck
	for _, x in { 0.25, 0.75 } do
		box(m, f, x, 1.75, 1.375, 0.25, 3.25, 0.25, "steel_dark", "LadderRail")
	end
	for k = 1, 6 do
		box(m, f, 0.5, k * 0.5, 1.3125, 0.75, 0.25, 0.25, "steel", "Rung")
	end
	-- the pipe down to the trough, its valve wheel
	box(m, f, -0.375, 2, 1, 0.25, 2.25, 0.25, "steel", "Pipe")
	box(m, f, -0.375, 0.875, 1.1875, 0.25, 0.25, 0.5, "steel", "Spout")
	disc(m, f, -0.375, 1.5, 1.1875, 0.5, 0.25, "berry_red", "Valve")
	box(m, f, -0.375, 0.375, 1.25, 1, 0.5, 0.5, "wood", "Trough")
	box(m, f, -0.375, 0.5625, 1.25, 0.75, 0.25, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	-- a barrel, a bucket, flowers
	keg(m, f, 1.1875, 0.125, -1.1875, 0.5)
	cyl(m, f, 1.25, 0.25, 0.3125, 0.25, 0.25, "steel", "Bucket")
	bloomBush(m, f, -1.125, 0.125, 1.125, "pink", "yellow")
end

-- Town Hall (5 x 4): a hall of warm sand-coloured stone with white quoins and cornice under a slate roof in rows. A
-- portico of four white columns on a stylobate up two steps carries a pediment with a clock in it; behind them a
-- double door and two small windows. Slim tall windows with flower boxes either side, two more round the east side,
-- a round window in the east gable. A bell tower rises from the ridge with a clock, a bell in its east opening, a
-- teal dome and a flag. Street lamps flank the steps and flowering bushes stand at the front corners.
B.townhall = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 4, "pavement", "Footing")
	box(m, f, 0, 0.25, -0.25, 4.25, 0.25, 2.25, "rock", "Plinth")
	box(m, f, 0, 1.5, -0.25, 4, 2.25, 2, "sand", "Walls")
	box(m, f, 0, 2.5, -0.25, 4.25, 0.25, 2.25, "white", "Cornice")
	-- quoins up the three corners the camera sees
	for _, c in { { -2, 0.6875 }, { 2, 0.6875 }, { 2, -1.1875 } } do
		for _, y in { 0.625, 1.125, 1.625, 2.125 } do
			box(m, f, c[1], y, c[2], 0.25, 0.25, 0.25, "white", "Quoin")
		end
	end
	-- the main roof, its gables in the walls' stone
	local g = f * CFrame.new(0, 0, -0.25)
	gable(m, g, 0, 2.625, 4, 2, 0.75, "sand")
	local yr = ridgeOver(2.625, 1, 0.75)
	pitched(m, g, yr, 4.5, 0.75, 1.5, 1.25, "slate", "steel_dark", "white", "white", true)
	log(m, f, 2.0625, 3, -0.25, 0.25, 0.5, "white", "RoundWindow")
	log(m, f, 2.125, 3, -0.25, 0.25, 0.25, "window", "Glass")
	-- the portico: stylobate, steps, columns, entablature, the pediment and its roof running back into the main one
	box(m, f, 0, 0.5, 1.125, 2.75, 0.25, 0.75, "white", "Stylobate")
	box(m, f, 0, 0.375, 1.625, 2.5, 0.25, 0.25, "white", "Step")
	box(m, f, 0, 0.125, 1.875, 2.5, 0.25, 0.25, "white", "Step")
	for _, x in { -1.125, -0.375, 0.375, 1.125 } do
		box(m, f, x, 0.75, 1.25, 0.5, 0.25, 0.5, "white", "ColumnBase")
		box(m, f, x, 1.5, 1.25, 0.25, 1.25, 0.25, "white", "Column")
		box(m, f, x, 2.25, 1.25, 0.5, 0.25, 0.5, "white", "Capital")
	end
	box(m, f, 0, 2.5, 1.125, 2.75, 0.25, 0.75, "white", "Entablature")
	local gp = f * CFrame.new(0, 0, 0.625) * CFrame.Angles(0, HALF_PI, 0)
	gable(m, gp, -0.5, 2.625, 0.75, 2.5, 0.75, "white")
	pitched(m, gp, ridgeOver(2.625, 1.25, 0.75), 2, 0.6, 1.5, 1.5, "slate", "steel_dark", "white", "white")
	disc(m, f, 0, 2.9375, 1.5, 0.75, 0.25, "gold", "ClockRim")
	disc(m, f, 0, 2.9375, 1.5625, 0.5, 0.25, "white", "ClockFace")
	box(m, f, 0, 3, 1.625, 0.25, 0.25, 0.25, "black", "ClockHand")
	-- the double door and the two small windows behind the columns
	doorway(m, f, 0, 0.625, 0.75, 0.75, 1.25, "wood_dark", "white")
	box(m, f, 0, 1.25, 0.9375, 0.25, 1.25, 0.25, "wood", "DoorJoin")
	for _, x in { -0.75, 0.75 } do
		win(m, f, x, 1.375, 0.75, 0.25, 0.75, "white", nil, "none")
	end
	-- tall windows with flower boxes either side, two more round the east side
	for _, x in { -1.625, 1.625 } do
		win(m, f, x, 1.5, 0.75, 0.25, 1, "white", nil, "pink")
		box(m, f, x, 2.1875, 0.875, 0.5, 0.25, 0.25, "white", "WindowHead")
	end
	for _, z in { -0.6875, 0.1875 } do
		win(m, east(f, 2, z), 0, 1.5, 0, 0.5, 1, "white", nil, "yellow")
	end
	-- the bell tower
	box(m, f, 0, 3.625, -0.25, 1, 2, 1, "sand", "Tower")
	box(m, f, 0, 4.75, -0.25, 1.25, 0.25, 1.25, "white", "TowerCornice")
	ball(m, f, 0, 5.125, -0.25, 1, "teal", "Dome")
	disc(m, f, 0, 4, 0.25, 0.75, 0.25, "gold", "ClockRim")
	disc(m, f, 0, 4, 0.3125, 0.5, 0.25, "white", "ClockFace")
	box(m, f, 0.0625, 4.0625, 0.375, 0.25, 0.25, 0.25, "black", "ClockHand")
	box(m, f, 0.5, 4, -0.25, 0.25, 0.75, 0.5, "black", "BelfryOpening")
	ball(m, f, 0.625, 3.9375, -0.25, 0.25, "gold", "Bell")
	box(m, f, 0, 5.875, -0.25, 0.25, 0.75, 0.25, "steel_dark", "FlagPole")
	wedge(m, f, 0.375, 6, -0.25, 0.5, 0.5, 0.25, "berry_red", HALF_PI, "Flag")
	-- lamps by the steps, flowering bushes at the front corners
	streetLamp(m, f, -1.625, 1.625)
	streetLamp(m, f, 1.625, 1.625)
	for _, x in { -2.125, 2.125 } do
		bloomBush(m, f, x, 0.125, 1.25, "pink", "white")
	end
end

-- Sun Beacon (3 x 3): a white tower on two steps with a gold band, a red door and slim blue-framed windows, a white
-- gallery on a gold rim round a lantern room that glows between its corner posts, a stepped gold cap, and on top the
-- sun: a gold disc with a glowing face and eight rays. Small suns on the tower's front and the base's east side,
-- orange banners by the door, a gold stone at the foot of the steps, lamps at the front corners, flowers in pots.
B.beacon = function(m, f)
	box(m, f, 0, 0.125, 0, 3, 0.25, 3, "white", "Step")
	box(m, f, 0, 0.375, 0, 2.5, 0.25, 2.5, "cream", "Step")
	box(m, f, 0, 0.875, 0, 1.5, 0.75, 1.5, "white", "Base")
	box(m, f, 0, 1.375, 0, 1.75, 0.25, 1.75, "gold", "Band")
	box(m, f, 0, 2.5, 0, 1, 2, 1, "white", "Tower")
	-- the door, the windows, the small sun on the front
	doorway(m, f, 0, 0.5, 0.75, 0.5, 0.75, "berry_red", "wood_dark")
	box(m, f, 0, 0.25, 1.375, 0.5, 0.25, 0.25, "gold", "PathStone")
	for _, x in { -0.5625, 0.5625 } do
		box(m, f, x, 1, 0.8125, 0.25, 0.5, 0.25, "orange", "FlagBanner")
	end
	win(m, f, 0, 2, 0.5, 0.25, 0.5, "blue", nil, "none")
	disc(m, f, 0, 3, 0.5625, 0.5, 0.25, "gold", "SunMark")
	ball(m, f, 0, 3, 0.6875, 0.25, "yellow", "SunMark").Material = Enum.Material.Neon
	for _, y in { 2, 3 } do
		win(m, east(f, 0.5, 0), 0, y, 0, 0.25, 0.5, "blue", nil, "none")
	end
	log(m, f, 0.8125, 0.875, 0, 0.25, 0.5, "gold", "SunMark")
	log(m, f, 0.9375, 0.875, 0, 0.25, 0.25, "yellow", "SunMark").Material = Enum.Material.Neon
	-- the gallery with a post at each corner, the lantern room glowing between its corner posts
	box(m, f, 0, 3.625, 0, 1.75, 0.25, 1.75, "white", "Gallery")
	box(m, f, 0, 3.375, 0, 1.25, 0.25, 1.25, "gold", "GalleryRim")
	for _, p in { { -0.75, 0.75 }, { 0.75, 0.75 }, { 0.75, -0.75 } } do
		box(m, f, p[1], 3.875, p[2], 0.25, 0.25, 0.25, "gold", "RailPost")
	end
	box(m, f, 0, 4.25, 0, 1, 1, 1, "yellow", "LanternLight", true)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(m, f, sx * 0.5, 4.25, sz * 0.5, 0.25, 1, 0.25, "white", "LanternPost")
		end
	end
	-- the cap and the sun
	box(m, f, 0, 4.875, 0, 1.25, 0.25, 1.25, "gold", "Cap")
	box(m, f, 0, 5.125, 0, 0.75, 0.25, 0.75, "gold", "Cap")
	box(m, f, 0, 5.375, 0, 0.25, 0.25, 0.25, "gold", "Spire")
	disc(m, f, 0, 6, 0, 1.25, 0.25, "gold", "Disc")
	ball(m, f, 0, 6, 0.125, 0.75, "yellow", "Sun").Material = Enum.Material.Neon
	for k = 0, 7 do
		local a = k * math.pi / 4
		at(m, f, CFrame.new(math.cos(a) * 0.875, 6 + math.sin(a) * 0.875, 0) * CFrame.Angles(0, 0, a - HALF_PI), 0.25, 0.5, 0.25, "gold", "Ray")
	end
	-- lamps at the front corners, flowers in pots
	for _, x in { -1, 1 } do
		box(m, f, x, 0.875, 1, 0.25, 0.75, 0.25, "white", "LampPost")
		box(m, f, x, 1.375, 1, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
		box(m, f, x, 1.625, 1, 0.25, 0.25, 0.25, "gold", "LampCap")
	end
	for _, p in { { -1, 0 }, { 1, -0.5 }, { 0.5, -1 } } do
		box(m, f, p[1], 0.625, p[2], 0.5, 0.25, 0.5, "pot", "Planter")
		bloomBush(m, f, p[1], 0.75, p[2], "yellow", "orange")
	end
end

-- Seed Vault (3 x 3): a grassy mound rising behind its stone front, flowers and stones on it, a seedling growing on
-- top and an air vent on its east side. In its front a slate wall between two buttresses under a dark lintel with a
-- keystone, snow along the top and icicles hanging from it, two frosty lamps; in the wall a round steel door with
-- bolts round its rim and a valve wheel. Seed sacks on one side, a crate of seed packets on the other, rows of
-- sprouts either side of the stepping stone, a watering can.
B.seedvault = function(m, f)
	box(m, f, 0, 0, 0, 3, 0.25, 3, "grass_dark", "Lawn")
	ball(m, f, 0, -0.125, -0.25, 2.5, "grass", "Mound")
	ball(m, f, 0.625, 0.125, -0.625, 1.5, "grass", "Mound")
	ball(m, f, -0.625, 0, 0, 1.25, "grass", "Mound")
	ball(m, f, 0.125, 0.875, -0.375, 1.5, "grass", "Mound")
	-- on the mound: the seedling, the air vent, flowers and stones
	box(m, f, 0.125, 1.75, -0.375, 0.25, 0.5, 0.25, "leaf_dark", "Sprout")
	ball(m, f, -0.125, 2, -0.375, 0.5, "leaf", "Leaf")
	ball(m, f, 0.375, 2.125, -0.375, 0.5, "leaf", "Leaf")
	cyl(m, f, 1, 1, -0.75, 0.25, 0.5, "steel", "AirVent")
	cyl(m, f, 1, 1.375, -0.75, 0.5, 0.25, "steel_dark", "AirVentCap")
	for k, p in { { -0.75, 0.75, 0.25 }, { -0.375, 1, 0.125 }, { 0.875, 0.6875, 0.125 } } do
		ball(m, f, p[1], p[2], p[3], 0.25, ({ "pink", "yellow", "white" })[k], "Flower")
	end
	ball(m, f, -0.625, 0.875, -0.375, 0.5, "rock", "Stone")
	-- the stone front: the wall, a few lighter blocks, buttresses, the lintel and keystone
	box(m, f, 0, 0.75, 0.75, 2, 1.25, 0.5, "slate", "Face")
	for _, p in { { -0.75, 0.375 }, { 0.75, 0.625 }, { -0.625, 1.125 }, { 0.75, 1.125 } } do
		box(m, f, p[1], p[2], 1, 0.25, 0.25, 0.25, "rock", "Block")
	end
	for _, x in { -1.125, 1.125 } do
		wedge(m, f, x, 0.75, 0.75, 0.5, 1.25, 0.5, "rock_dark", math.pi, "Buttress")
	end
	box(m, f, 0, 1.5, 0.875, 2.5, 0.25, 0.75, "rock_dark", "Lintel")
	box(m, f, 0, 1.625, 1.125, 0.5, 0.5, 0.25, "rock", "Keystone")
	box(m, f, 0, 1.6875, 0.75, 2.25, 0.25, 0.5, "snow", "Snow")
	for _, x in { -0.875, -0.5, 0.5, 0.875 } do
		box(m, f, x, 1.25, 1.125, 0.25, 0.25, 0.25, "ice", "Icicle")
	end
	for _, x in { -0.75, 0.75 } do
		box(m, f, x, 1.5, 1.3125, 0.25, 0.25, 0.25, "ice", "Frost", true)
	end
	-- the round steel door: its rim and bolts, the door, the valve wheel
	disc(m, f, 0, 0.75, 1, 1.25, 0.25, "steel_dark", "DoorRim")
	disc(m, f, 0, 0.75, 1.0625, 1, 0.25, "steel", "Hatch")
	for k = 0, 5 do
		local a = k * math.pi / 3 + math.pi / 6
		ball(m, f, math.sin(a) * 0.5625, 0.75 + math.cos(a) * 0.5625, 1.125, 0.25, "steel_dark", "Bolt")
	end
	for k, a in { math.pi / 4, -math.pi / 4 } do
		at(m, f, CFrame.new(0, 0.75, 1.1875 + k * 0.0625) * CFrame.Angles(0, 0, a), 0.75, 0.25, 0.25, "steel_dark", "Wheel")
	end
	ball(m, f, 0, 0.75, 1.375, 0.25, "gold", "WheelHub")
	-- the stepping stone, rows of sprouts either side, seed and a watering can by the door
	box(m, f, 0, 0.0625, 1.375, 0.5, 0.25, 0.25, "rock", "SteppingStone")
	for _, x in { -0.75, -0.5, 0.5, 0.75 } do
		box(m, f, x, 0.25, 1.375, 0.25, 0.25, 0.25, "sand_dark", "Soil")
		ball(m, f, x, 0.4375, 1.375, 0.25, "leaf", "Sprout")
	end
	sack(m, f, -1.125, 0.125, 1.1875, "cream")
	sack(m, f, -1.25, 0.125, 0.25, "sand_dark")
	ball(m, f, -0.875, 0.1875, 1.375, 0.25, "gold", "Seed")
	crate(m, f, 1.125, 0.125, 0.25, 0.5)
	box(m, f, 1.0625, 0.6875, 0.1875, 0.25, 0.25, 0.25, "pink", "SeedPacket")
	box(m, f, 1.25, 0.6875, 0.3125, 0.25, 0.25, 0.25, "yellow", "SeedPacket")
	cyl(m, f, 0.25, 0.25, 1.125, 0.25, 0.25, "teal", "WateringCan")
	box(m, f, 0.375, 0.3125, 1.125, 0.25, 0.25, 0.25, "teal", "WateringSpout")
end

-- Carpenters' Hall (4 x 3): a hall with a stone ground floor and a cream upper floor framed in dark timber, under a
-- steep roof of wooden shingles with a brick chimney through its front slope. Below: a green door, a lantern and a
-- small window with a planter under it; above: two windows with flower boxes, and the guild's sign, a saw and a hammer
-- crossed on a cream board, hung out from the corner on an iron bracket. Round the east side, the workshop's double
-- door below, a window above and a little one in the gable. The yard has a workbench with a vice, a plane and a saw on
-- it, a sawhorse with a log being cut out front, and stacks of planks by the front corner and the bench.
B.guildhall = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 3, "rock", "Footing")
	-- the stone ground floor, the beam at the floor line, the cream upper floor and its corner posts
	box(m, f, -0.5, 0.75, -0.125, 2.5, 1.25, 1.5, "pavement", "Walls")
	box(m, f, -0.5, 1.875, -0.125, 2.5, 1, 1.5, "cream", "UpperWalls")
	box(m, f, -0.5, 1.4375, 0.6875, 2.75, 0.25, 0.25, "wood_dark", "FloorBeam")
	box(m, f, 0.8125, 1.4375, -0.125, 0.25, 0.25, 1.75, "wood_dark", "FloorBeam")
	for _, p in { { -1.6875, 0.5625 }, { 0.6875, 0.5625 }, { 0.6875, -0.8125 } } do
		box(m, f, p[1], 1.875, p[2], 0.25, 1, 0.25, "wood_dark", "Post")
	end
	-- the steep shingled roof, its gables in the upper floor's cream, a little window in the east one
	local g = f * CFrame.new(-0.5, 0, -0.125)
	gable(m, g, 0, 2.375, 2.5, 1.5, 1, "cream")
	local yr = ridgeOver(2.375, 0.75, 1)
	pitched(m, g, yr, 2.75, 4 / 3, 1.5, 1, "wood_dark", "wood", "wood", "wood", true)
	win(m, east(f, 0.75, -0.125), 0, 2.875, 0, 0.25, 0.25, "wood_dark", nil, "none")
	box(m, f, -1.375, 3.25, 0.125, 0.5, 1.75, 0.5, "brick", "ChimneyStack")
	box(m, f, -1.375, 4.25, 0.125, 0.75, 0.25, 0.75, "rock_dark", "Chimney")
	-- the front below: the door, its step and lantern, a small window with a planter
	doorway(m, f, -0.5, 0.125, 0.625, 0.5, 0.75, "green", "wood_dark")
	box(m, f, -0.5, 0.125, 0.9375, 0.75, 0.25, 0.25, "rock_dark", "Step")
	lantern(m, f, 0.0625, 0.875, 0.625)
	win(m, f, -1.25, 0.75, 0.625, 0.25, 0.5, "wood_dark", nil, "pink")
	-- the front above: two windows with flower boxes; the guild's sign hung out from the corner on an iron bracket
	for _, x in { -1.125, 0 } do
		win(m, f, x, 1.875, 0.625, 0.25, 0.5, "wood_dark", nil, "yellow")
	end
	box(m, f, 1, 2.1875, 0.6875, 0.5, 0.25, 0.25, "black", "SignArm")
	box(m, f, 1.0625, 1.8125, 0.6875, 0.5, 0.5, 0.25, "cream", "Sign")
	at(m, f, CFrame.new(1.0625, 1.8125, 0.75) * CFrame.Angles(0, 0, math.rad(45)), 0.25, 0.5, 0.25, "steel", "SignSaw")
	at(m, f, CFrame.new(1.0625, 1.8125, 0.8125) * CFrame.Angles(0, 0, math.rad(-45)), 0.25, 0.5, 0.25, "wood", "SignHammer")
	box(m, f, 1.1875, 1.9375, 0.875, 0.25, 0.25, 0.25, "steel_dark", "SignHammerHead")
	-- the east side: the workshop's double door below, a window above
	local e = east(f, 0.75, -0.125)
	doorway(m, e, 0, 0.125, 0, 0.75, 0.75, "wood", "wood_dark")
	box(m, f, 0.9375, 0.5, -0.125, 0.25, 0.75, 0.25, "wood_dark", "DoorJoin")
	win(m, e, 0, 1.875, 0, 0.25, 0.5, "wood_dark")
	-- the workbench with its vice and tools
	box(m, f, 1.4375, 0.75, -0.75, 0.5, 0.25, 1, "wood", "Bench")
	for _, z in { -1.125, -0.375 } do
		box(m, f, 1.4375, 0.375, z, 0.5, 0.5, 0.25, "wood_dark", "BenchLeg")
	end
	box(m, f, 1.4375, 1, -0.25, 0.25, 0.25, 0.25, "steel_dark", "Vice")
	box(m, f, 1.375, 1, -0.75, 0.25, 0.25, 0.5, "wood_dark", "Plane")
	box(m, f, 1.5625, 0.9375, -1, 0.25, 0.25, 0.5, "steel", "Saw")
	-- the sawhorse and its log out front, the planks by the front corner and by the bench
	for _, x in { 0.125, 0.875 } do
		box(m, f, x, 0.375, 1.375, 0.25, 0.5, 0.25, "wood_dark", "Sawhorse")
	end
	log(m, f, 0.5, 0.75, 1.375, 1.25, 0.25, "wood", "Log")
	box(m, f, 0.75, 1, 1.375, 0.25, 0.25, 0.25, "steel", "Saw")
	for k = 0, 2 do
		box(m, f, -1.5, 0.25 + k * 0.25, 1.25, 0.75, 0.25, 0.5, if k % 2 == 0 then "wood" else "sand_dark", "Planks")
	end
	for k = 0, 1 do
		box(m, f, 1.5, 0.25 + k * 0.25, 0.625, 0.5, 0.25, 0.5, if k % 2 == 0 then "sand_dark" else "wood", "Planks")
	end
end

-- Trade Hall (4 x 4): a brick hall with cream quoins and cornice and a balustrade along the front of its flat roof,
-- three tall arched doorways in cream surrounds with keystones (the middle one open with a lamp lit inside, the others
-- with teal doors), lanterns between them and two arched windows round the east side. On the roof, a sign with a ship
-- on it and flags of far ports on three poles. A hoist over the east door lowers a crate; out front, a balance, crates
-- with coloured marks, sacks and barrels.
B.tradehall = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 4, "pavement", "Footing")
	box(m, f, 0, 0.25, -0.25, 3.75, 0.25, 2.25, "rock_dark", "Plinth")
	box(m, f, 0, 1.5, -0.25, 3.5, 2.25, 2, "brick", "Walls")
	box(m, f, 0, 2.625, -0.25, 3.75, 0.25, 2.25, "cream", "Cornice")
	for _, c in { { -1.75, 0.6875 }, { 1.75, 0.6875 }, { 1.75, -1.1875 } } do
		for _, y in { 0.625, 1.125, 1.625, 2.125 } do
			box(m, f, c[1], y, c[2], 0.25, 0.25, 0.25, "cream", "Quoin")
		end
	end
	-- the flat roof, its parapet and the balustrade along the front
	box(m, f, 0, 2.8125, -0.25, 3.5, 0.25, 2, "rock_dark", "Roof")
	box(m, f, 0, 3, -1.1875, 3.5, 0.5, 0.25, "cream", "Parapet")
	box(m, f, 1.6875, 3, -0.25, 0.25, 0.5, 2, "cream", "Parapet")
	box(m, f, -1.6875, 3, -0.25, 0.25, 0.5, 2, "cream", "Parapet")
	box(m, f, 0, 3.125, 0.6875, 3.5, 0.25, 0.25, "cream", "Balustrade")
	for k = 0, 6 do
		box(m, f, -1.5 + k * 0.5, 2.875, 0.6875, 0.25, 0.25, 0.25, "cream", "Baluster")
	end
	-- the three doorways: a cream surround with a round arch, the door (or the dark way in), a keystone
	for k, x in { -1.125, 0, 1.125 } do
		box(m, f, x, 1, 0.8125, 0.75, 1.25, 0.25, "cream", "Surround")
		disc(m, f, x, 1.625, 0.8125, 0.75, 0.25, "cream", "Arch")
		local c = if k == 2 then "black" else "teal"
		box(m, f, x, 1, 0.875, 0.5, 1.25, 0.25, c, "Door")
		disc(m, f, x, 1.625, 0.875, 0.5, 0.25, c, "DoorArch")
		box(m, f, x, 2.0625, 0.875, 0.25, 0.375, 0.25, "gold", "Keystone")
	end
	box(m, f, 0, 1.5, 0.9375, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
	for _, x in { -0.5625, 0.5625 } do
		lantern(m, f, x, 1.375, 0.75)
	end
	for _, z in { -0.625, 0.125 } do
		local e = east(f, 1.75, z)
		box(m, e, 0, 1.25, 0.0625, 0.75, 1, 0.25, "cream", "Surround")
		disc(m, e, 0, 1.75, 0.0625, 0.75, 0.25, "cream", "Arch")
		box(m, e, 0, 1.25, 0.125, 0.5, 1, 0.25, "window", "Glass")
		disc(m, e, 0, 1.75, 0.125, 0.5, 0.25, "window", "Glass")
	end
	-- the sign on the roof's front and the flags behind it
	box(m, f, 0, 3.5, 0.5, 1.25, 0.5, 0.25, "cream", "Sign")
	box(m, f, 0, 3.375, 0.6875, 0.75, 0.25, 0.25, "wood", "SignShip")
	box(m, f, 0, 3.625, 0.6875, 0.25, 0.25, 0.25, "white", "SignSail")
	for k, x in { -1.25, 0, 1.25 } do
		box(m, f, x, 3.5, -0.875, 0.25, 1.25, 0.25, "steel_dark", "FlagPole")
		wedge(m, f, x + 0.375, 3.875, -0.875, 0.5, 0.5, 0.25, ({ "teal", "orange", "purple" })[k], HALF_PI, "Flag")
	end
	-- the hoist over the east door and its crate
	box(m, f, 1.125, 2.4375, 1.125, 0.25, 0.25, 0.75, "wood_dark", "HoistBeam")
	box(m, f, 1.125, 2.1875, 1.375, 0.25, 0.25, 0.25, "black", "Pulley")
	box(m, f, 1.125, 1.8125, 1.375, 0.25, 0.5, 0.25, "sand_dark", "Rope")
	crate(m, f, 1.125, 1.0625, 1.375, 0.5)
	-- out front: the balance, crates, sacks and barrels
	box(m, f, -0.375, 0.5, 1.5, 0.25, 0.75, 0.25, "wood_dark", "BalancePost")
	box(m, f, -0.375, 0.9375, 1.5, 1, 0.25, 0.25, "gold", "BalanceBeam")
	for _, dx in { -0.375, 0.375 } do
		cyl(m, f, -0.375 + dx, 0.75, 1.5, 0.5, 0.25, "gold", "BalancePan")
	end
	crate(m, f, -1.5, 0.125, 1.25, 0.5)
	crate(m, f, -1.5, 0.625, 1.25, 0.5)
	crate(m, f, -1, 0.125, 1.5, 0.5)
	box(m, f, -1.5, 0.375, 1.5625, 0.25, 0.25, 0.25, "teal", "Mark")
	box(m, f, -1, 0.375, 1.8125, 0.25, 0.25, 0.25, "orange", "Mark")
	sack(m, f, 0.375, 0.125, 1.5, "sand_dark")
	sack(m, f, 0.75, 0.125, 1.75, "cream")
	keg(m, f, 1.5, 0.125, 1.375, 0.5)
end

-- Tide Bell (3 x 3): two white pillars banded in teal with shells on them and lanterns, on two steps, carrying a beam
-- and a teal roof in rows with a gold ridge and gold knobs at its ends. A big gold bell hangs between them on a black
-- yoke, a rope with a red tassel under it. Strings of shells hang from the roof's front corners. In front, a pool of
-- water in a white rim with glowing crests on it; shells and starfish on the steps and pots of coral at the back.
B.tidebell = function(m, f)
	box(m, f, 0, 0.125, 0, 3, 0.25, 3, "white", "Step")
	box(m, f, 0, 0.375, -0.125, 2.5, 0.25, 2.25, "cream", "Step")
	-- the pool in front, its crests of light
	box(m, f, 0, 0.375, 1.25, 2, 0.25, 0.5, "white", "PoolRim")
	box(m, f, 0, 0.4375, 1.25, 1.75, 0.25, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	for k, x in { -0.625, -0.125, 0.375, 0.75 } do
		box(m, f, x, 0.5625 + (k % 2) * 0.0625, 1.25, 0.25, 0.25, 0.25, "shallow", "Wave", true)
	end
	-- the pillars
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 0.625, 0, 0.75, 0.25, 0.75, "teal", "Base")
		box(m, f, x, 2, 0, 0.5, 2.5, 0.5, "white", "Pillar")
		for _, y in { 1.375, 2.625 } do
			box(m, f, x, y, 0, 0.75, 0.25, 0.75, "teal", "Band")
		end
		box(m, f, x, 3.375, 0, 0.75, 0.25, 0.75, "teal", "Capital")
		ball(m, f, x, 2, 0.25, 0.25, "coral", "Shell")
		lantern(m, f, x, 3, 0.25)
	end
	-- the beam, its roof, the gold ridge and knobs
	box(m, f, 0, 3.625, 0, 2.5, 0.25, 0.75, "white", "Beam")
	for _, x in { -1.125, 1.125 } do
		gable(m, f * CFrame.new(x, 0, 0), 0, 3.75, 0.25, 1, 0.25, "white")
	end
	local yr = 3.75 + 0.25 / math.cos(math.atan(0.75)) + 0.75 * 0.375
	pitched(m, f, yr, 2.75, 0.75, 1.25, 1, "teal", "water", "gold", "white", true)
	for _, x in { -1.375, 1.375 } do
		ball(m, f, x, yr + 0.125, 0, 0.25, "gold", "Knob")
	end
	-- the bell, its yoke, clapper and rope
	box(m, f, 0, 3.25, 0, 0.25, 0.5, 0.25, "black", "Yoke")
	cyl(m, f, 0, 2.875, 0, 0.5, 0.25, "gold", "Bell")
	cyl(m, f, 0, 2.625, 0, 0.75, 0.25, "gold", "Bell")
	cyl(m, f, 0, 2.375, 0, 1, 0.25, "gold", "Bell")
	cyl(m, f, 0, 2.125, 0, 1, 0.25, "orange", "BellBand")
	cyl(m, f, 0, 1.875, 0, 1.25, 0.25, "gold", "Lip")
	ball(m, f, 0, 1.625, 0, 0.25, "steel_dark", "Clapper")
	box(m, f, 0, 1.25, 0, 0.25, 0.5, 0.25, "sand_dark", "Rope")
	ball(m, f, 0, 0.875, 0, 0.25, "berry_red", "Tassel")
	-- strings of shells from the front corners of the roof
	for _, x in { -1.25, 1.25 } do
		for k, c in { "pink", "white", "coral" } do
			ball(m, f, x, 3.375 - k * 0.25, 0.875, 0.25, c, "Shell")
		end
	end
	-- shells and starfish on the steps, pots of coral at the back
	for _, p in { { x = -1.125, z = 0.75, c = "pink" }, { x = 1.125, z = 0.75, c = "white" }, { x = -0.375, z = 0.875, c = "coral" } } do
		ball(m, f, p.x, 0.5625, p.z, 0.25, p.c, "Shell")
	end
	for k, a in { 0, HALF_PI } do
		at(m, f, CFrame.new(0.5, 0.5625 + k * 0.0625, 0.875) * CFrame.Angles(0, a + math.pi / 4, 0), 0.5, 0.25, 0.25, "coral", "Starfish")
	end
	for _, x in { -0.5, 0.5 } do
		box(m, f, x, 0.625, -0.875, 0.5, 0.25, 0.5, "pot", "Pot")
		ball(m, f, x - 0.125, 0.875, -0.875, 0.25, "coral", "Coral")
		ball(m, f, x + 0.125, 1, -0.875, 0.25, "pink", "Coral")
	end
end


return B
