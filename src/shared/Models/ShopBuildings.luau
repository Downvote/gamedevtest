--!strict
-- The island's shops (kind "shop"), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
-- the footprint's centre on the grass (facing +Z before the piece's turn) and the level, and stays inside the
-- footprint. The pieces they share are Models/BuildKit's; the shop fronts' own pieces (striped awnings with a
-- scalloped edge, framed windows, flower boxes, chalk boards, tables and chairs, lanterns, gable roofs with rows of
-- tiles) are below. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.")
--
-- Sizes are whole quarter studs (Blocks snaps them) and faces sit on the eighth-stud grid; a trim stands an eighth
-- proud of what it is on, so no two faces of different colours share a plane. The camera looks from the south-east,
-- so the detail is on the front (+Z), the east side (+X) and the roof, and an awning over a window is short and high
-- so the window still shows under it. The back-left corner (0.6 studs each way) stays clear above half a stud for the
-- upgrade pennant.
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local wedge = K.wedge
local span = K.span

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"
local B: { [string]: Builder } = {}

------------------------------------------------------------------ the shop fronts' pieces

local function part(m: Model, cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: Shape?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = cf, color = color, name = name, shape = shape, neon = neon, collide = false })
end

-- A box turned by `rot` about its centre.
local function tilt(m: Model, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, rot: CFrame, color: string, name: string): BasePart
	return part(m, f * CFrame.new(x, y, z) * rot, w, h, d, color, name)
end

-- A lit ball: a paper lantern, a globe.
local function glowBall(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string): BasePart
	return part(m, f * CFrame.new(x, y, z), dia, dia, dia, color, name, "Ball", true)
end

-- A disc facing +Z (a cylinder lying along Z): a plate on a wall, the sun on a backdrop, a scallop.
local function discZ(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string): BasePart
	return part(m, f * CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), t, dia, dia, color, name, "Cylinder")
end

-- A disc facing +X: a wheel, a round vent.
local function discX(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string): BasePart
	return part(m, f * CFrame.new(x, y, z), t, dia, dia, color, name, "Cylinder")
end

-- A plate `len` long hung by its back edge (the top face's edge, at x, y, z), sloping down toward +Z by `deg`.
local function slab(m: Model, f: CFrame, x: number, y: number, z: number, w: number, len: number, deg: number, color: string, name: string): BasePart
	return part(m, f * CFrame.new(x, y, z) * CFrame.Angles(math.rad(deg), 0, 0) * CFrame.new(0, -0.125, len / 2), w, 0.25, len, color, name)
end

-- A pennant flying east from a pole at x: a thin wedge `len` long and `h` tall, its tall edge on the pole.
local function flag(m: Model, f: CFrame, x: number, y: number, z: number, len: number, h: number, color: string)
	wedge(m, f, x + len / 2, y, z, 0.25, h, len, color, -math.pi / 2, "Flag")
end

-- A striped awning hung on a wall facing +Z (face at z) from x0 to x1 in half-stud stripes: its back edge at y, sloping
-- `deg` down over `len`, a half disc under every stripe for the scalloped edge.
local function awning(m: Model, f: CFrame, x0: number, x1: number, y: number, z: number, len: number, deg: number, a: string, b: string)
	local r = math.rad(deg)
	local ez, ey = z + len * math.cos(r), y - len * math.sin(r)
	local n = math.floor((x1 - x0) / 0.5 + 0.5)
	for i = 0, n - 1 do
		local x = x0 + 0.25 + i * 0.5
		local c = if i % 2 == 0 then a else b
		slab(m, f, x, y, z, 0.5, len, deg, c, "Awning")
		discZ(m, f, x, ey - 0.25, ez, 0.5, 0.25, c, "Scallop")
	end
end

-- A gable roof along X over walls w x d (whole half studs) whose top is at y, centred on cx, cz: pitched at 45 degrees
-- with eaves a quarter stud past the walls, rows of tiles stepping down the front slope (every other row `tile`),
-- a ridge cap, the east gable in `gable` inside a border of the roof, a round vent in it.
type Roof = { roof: string, tile: string, ridge: string, gable: string, vent: string? }
local function gable(m: Model, f: CFrame, cx: number, y: number, cz: number, w: number, d: number, r: Roof)
	local W, D = w + 0.5, d + 0.5
	local h = D / 2
	wedge(m, f, cx, y + h / 2, cz - D / 4, W, h, D / 2, r.roof, 0, "Roof")
	wedge(m, f, cx, y + h / 2, cz + D / 4, W, h, D / 2, r.roof, math.pi, "Roof")
	local k = 0
	local s = 0.25
	while s <= D / 2 + 0.001 do
		box(m, f, cx, y + h - s, cz + s, W - 0.25, 0.25, 0.25, if k % 2 == 1 then r.tile else r.roof, "Tiles")
		s += 0.25
		k += 1
	end
	box(m, f, cx, y + h, cz, W + 0.25, 0.25, 0.5, r.ridge, "Ridge")
	local g = h - 0.25
	wedge(m, f, cx + W / 2, y + g / 2, cz - g / 2, 0.25, g, g, r.gable, 0, "Gable")
	wedge(m, f, cx + W / 2, y + g / 2, cz + g / 2, 0.25, g, g, r.gable, math.pi, "Gable")
	if r.vent then
		discX(m, f, cx + W / 2 + 0.125, y + math.floor(g * 4) / 8 + 0.125, cz, 0.5, 0.25, r.vent, "Vent")
	end
end

-- A window in a wall facing +Z (face at z), centred at x, y: a frame, the glass standing an eighth out of it, a cross
-- of bars when `cross`, a sill unless `noSill`.
local function win(m: Model, f: CFrame, x: number, y: number, z: number, w: number, h: number, frame: string, cross: boolean?, noSill: boolean?)
	box(m, f, x, y, z, w + 0.25, h + 0.25, 0.25, frame, "WindowFrame")
	box(m, f, x, y, z + 0.125, w, h, 0.25, "window", "Glass")
	if cross then
		box(m, f, x, y, z + 0.375, 0.25, h, 0.25, frame, "Bar")
		box(m, f, x, y, z + 0.375, w, 0.25, 0.25, frame, "Bar")
	end
	if not noSill then
		box(m, f, x, y - h / 2 - 0.125, z + 0.25, w + 0.5, 0.25, 0.5, frame, "Sill")
	end
end

-- The same in a wall facing +X (face at x).
local function winX(m: Model, f: CFrame, x: number, y: number, z: number, d: number, h: number, frame: string, noSill: boolean?)
	box(m, f, x, y, z, 0.25, h + 0.25, d + 0.25, frame, "WindowFrame")
	box(m, f, x + 0.125, y, z, 0.25, h, d, "window", "Glass")
	if not noSill then
		box(m, f, x + 0.25, y - h / 2 - 0.125, z, 0.5, 0.25, d + 0.5, frame, "Sill")
	end
end

-- A flower box on a wall facing +Z whose top is at y: the box, a row of leaves, a bloom every half stud.
local function flowerBox(m: Model, f: CFrame, x: number, y: number, z: number, w: number, blooms: { string })
	box(m, f, x, y - 0.125, z + 0.25, w, 0.25, 0.5, "wood", "FlowerBox")
	box(m, f, x, y + 0.125, z + 0.25, w - 0.5, 0.25, 0.25, "leaf", "Leaves")
	local n = #blooms
	for i, c in blooms do
		ball(m, f, x - (n - 1) * 0.25 + (i - 1) * 0.5, y + 0.25, z + 0.375, 0.25, c, "Bloom")
	end
end

-- The same on a wall facing +X.
local function flowerBoxX(m: Model, f: CFrame, x: number, y: number, z: number, d: number, blooms: { string })
	box(m, f, x + 0.25, y - 0.125, z, 0.5, 0.25, d, "wood", "FlowerBox")
	box(m, f, x + 0.25, y + 0.125, z, 0.25, 0.25, d - 0.5, "leaf", "Leaves")
	local n = #blooms
	for i, c in blooms do
		ball(m, f, x + 0.375, y + 0.25, z - (n - 1) * 0.25 + (i - 1) * 0.5, 0.25, c, "Bloom")
	end
end

-- A door in a wall facing +Z (face at z), its foot at y0: a frame, the door, a pane of glass in it, a brass knob.
local function door(m: Model, f: CFrame, x: number, y0: number, z: number, w: number, h: number, frame: string, color: string)
	box(m, f, x, y0 + (h + 0.25) / 2, z, w + 0.25, h + 0.25, 0.25, frame, "DoorFrame")
	box(m, f, x, y0 + h / 2, z + 0.125, w, h, 0.25, color, "Door")
	box(m, f, x, y0 + h - 0.5, z + 0.25, w - 0.5, 0.5, 0.25, "window", "DoorGlass")
	ball(m, f, x + w / 2 - 0.125, y0 + h / 2 - 0.125, z + 0.25, 0.25, "gold", "Knob")
end

-- A lantern hanging from y: a dark cap and the light under it.
local function lantern(m: Model, f: CFrame, x: number, y: number, z: number, color: string)
	box(m, f, x, y - 0.125, z, 0.25, 0.25, 0.25, "black", "LanternCap")
	box(m, f, x, y - 0.375, z, 0.25, 0.25, 0.25, color, "Lantern", true)
end

-- A lamp on a wall facing +Z (face at z): an arm out from it at y and a lantern hanging from its end.
local function wallLamp(m: Model, f: CFrame, x: number, y: number, z: number)
	box(m, f, x, y, z + 0.25, 0.25, 0.25, 0.5, "black", "LampArm")
	lantern(m, f, x, y - 0.125, z + 0.375, "yellow")
end

-- Lights strung from a to b (points in f), sagging `sag` in the middle: n bulbs, the colours in turn.
local function bulbs(m: Model, f: CFrame, a: Vector3, b: Vector3, n: number, sag: number, colors: { string })
	for i = 1, n do
		local t = i / (n + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		box(m, f, p.X, p.Y, p.Z, 0.25, 0.25, 0.25, colors[(i - 1) % #colors + 1], "Bulb", true)
	end
end

-- An A-frame chalk board standing at x, z (its foot at y0), facing +Z: the frame, the board, two marks of chalk, the
-- back leg.
local function menuBoard(m: Model, f: CFrame, x: number, y0: number, z: number, a: string, b: string)
	local front = f * CFrame.new(x, y0 + 0.5, z + 0.125) * CFrame.Angles(-0.2, 0, 0)
	part(m, front, 0.75, 1.0, 0.25, "wood", "MenuBoard")
	part(m, front * CFrame.new(0, 0, 0.125), 0.5, 0.75, 0.25, "chalk", "MenuBoard")
	part(m, front * CFrame.new(-0.125, 0.125, 0.25), 0.25, 0.25, 0.25, a, "Chalk")
	part(m, front * CFrame.new(0.125, -0.125, 0.25), 0.25, 0.25, 0.25, b, "Chalk")
	part(m, f * CFrame.new(x, y0 + 0.5, z - 0.125) * CFrame.Angles(0.2, 0, 0), 0.75, 1.0, 0.25, "wood_dark", "MenuBoard")
end

-- A potted plant at x, z (foot at y0): a clay pot with a rim, a ball of leaves, a bloom.
local function potPlant(m: Model, f: CFrame, x: number, y0: number, z: number, bloom: string?)
	box(m, f, x, y0 + 0.25, z, 0.5, 0.5, 0.5, "pot", "Pot")
	ball(m, f, x, y0 + 0.75, z, 0.5, "leaf", "Plant")
	if bloom then
		ball(m, f, x + 0.125, y0 + 1.0, z + 0.125, 0.25, bloom, "Bloom")
	end
end

-- A chair at x, z (foot at y0) with its back toward bx, bz (one of them 1 or -1, the other 0).
local function chair(m: Model, f: CFrame, x: number, y0: number, z: number, bx: number, bz: number, color: string)
	box(m, f, x, y0 + 0.25, z, 0.25, 0.5, 0.25, "wood_dark", "ChairLeg")
	box(m, f, x, y0 + 0.5, z, 0.5, 0.25, 0.5, color, "Seat")
	box(m, f, x + bx * 0.125, y0 + 0.875, z + bz * 0.125, if bx ~= 0 then 0.25 else 0.5, 0.5, if bx ~= 0 then 0.5 else 0.25, color, "ChairBack")
end

-- A round table at x, z (foot at y0): a stem and the top.
local function roundTable(m: Model, f: CFrame, x: number, y0: number, z: number, dia: number, top: string)
	box(m, f, x, y0 + 0.375, z, 0.25, 0.75, 0.25, "steel_dark", "TableLeg")
	cyl(m, f, x, y0 + 0.875, z, dia, 0.25, top, "Table")
end

-- A parasol over x, z: a pole from y0 to y1 and a canopy of rings narrowing up, the two colours in turn.
local function parasol(m: Model, f: CFrame, x: number, z: number, y0: number, y1: number, dia: number, a: string, b: string)
	box(m, f, x, (y0 + y1) / 2, z, 0.25, y1 - y0, 0.25, "white", "ParasolPole")
	local d, y, k = dia, y1, 0
	while d > 0.3 do
		cyl(m, f, x, y + 0.125, z, d, 0.25, if k % 2 == 0 then a else b, "Parasol")
		d -= 0.5
		y += 0.25
		k += 1
	end
	ball(m, f, x, y + 0.125, z, 0.25, "gold", "Finial")
end

-- A post with a lit lantern on top at x, z, from y0 to y1: a stone foot, the post, the light, its cap (the post and
-- the cap black unless `metal` says otherwise).
local function lampPost(m: Model, f: CFrame, x: number, z: number, y0: number, y1: number, color: string?, metal: string?)
	box(m, f, x, y0 + 0.125, z, 0.5, 0.25, 0.5, "rock_dark", "LampBase")
	box(m, f, x, (y0 + y1 - 0.25) / 2, z, 0.25, y1 - y0 - 0.75, 0.25, metal or "black", "LampPost")
	box(m, f, x, y1 - 0.375, z, 0.25, 0.25, 0.25, color or "yellow", "LampLight", true)
	box(m, f, x, y1 - 0.125, z, 0.5, 0.25, 0.5, metal or "black", "LampCap")
end

------------------------------------------------------------------ the shops

-- Snack Stall (3 x 2): a plank deck under a wooden counter with dark battens, a chalk price board and a cream top,
-- four posts and a red and white striped awning with a scalloped edge, a sign board on the back beam with a fruit on
-- it and a flag at each end; on the counter a crate heaped with oranges and apples with a price tag, two fish on ice,
-- a bell, a jug of lemonade and two cups; bananas and a lantern hung on the front posts, two stools in front.
B.stall = function(m, f)
	box(m, f, 0, 0.125, 0, 2.75, 0.25, 1.75, "wood_dark", "Deck")
	-- the counter
	box(m, f, 0, 0.625, 0.125, 2.5, 0.75, 0.5, "wood", "Counter")
	for _, x in { -1.0, -0.5, 0 } do
		box(m, f, x, 0.625, 0.375, 0.25, 0.5, 0.25, "wood_dark", "Batten")
	end
	box(m, f, 0.75, 0.625, 0.5, 1.0, 0.75, 0.25, "wood", "PriceBoard")
	box(m, f, 0.75, 0.625, 0.625, 0.75, 0.5, 0.25, "chalk", "PriceBoard")
	box(m, f, 0.75, 0.625, 0.75, 0.5, 0.25, 0.25, "white", "Chalk")
	box(m, f, 0, 1.125, 0.125, 2.75, 0.25, 0.75, "cream", "Top")
	-- the posts, the back beam, the awning
	for _, x in { -1.375, 1.375 } do
		box(m, f, x, 1.625, -0.25, 0.25, 2.75, 0.25, "wood_dark", "Post")
		box(m, f, x, 1.5, 0.5, 0.25, 2.5, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0, 3.125, -0.25, 3.0, 0.25, 0.25, "wood_dark", "Beam")
	awning(m, f, -1.5, 1.5, 3.25, -0.125, 1.0, 30, "berry_red", "white")
	-- the sign on the beam
	box(m, f, 0, 3.625, -0.25, 1.75, 0.75, 0.25, "wood_dark", "Sign")
	box(m, f, 0, 3.625, -0.125, 1.5, 0.5, 0.25, "cream", "SignFace")
	ball(m, f, -0.5, 3.625, 0, 0.25, "orange", "SignFruit")
	box(m, f, 0.25, 3.625, 0, 0.75, 0.25, 0.25, "berry_red", "Letters")
	for _, x in { -0.75, 0.75 } do
		box(m, f, x, 4.25, -0.25, 0.25, 0.5, 0.25, "wood_dark", "FlagPole")
		flag(m, f, x + 0.125, 4.375, -0.25, 0.5, 0.25, if x < 0 then "yellow" else "teal")
	end
	-- the goods
	box(m, f, -0.875, 1.375, 0.125, 0.75, 0.25, 0.5, "wood_dark", "Crate")
	box(m, f, -0.875, 1.375, 0.5, 0.25, 0.25, 0.25, "cream", "PriceTag")
	for i, x in { -1.125, -0.875, -0.625 } do
		ball(m, f, x, 1.625, 0, 0.25, if i == 2 then "green" else "berry_red", "Fruit")
		ball(m, f, x, 1.625, 0.25, 0.25, "orange", "Fruit")
	end
	ball(m, f, -0.875, 1.875, 0.125, 0.25, "orange", "Fruit")
	box(m, f, 0, 1.375, 0.125, 0.75, 0.25, 0.5, "ice", "Ice")
	box(m, f, -0.125, 1.625, 0, 0.5, 0.25, 0.25, "blue", "Fish")
	box(m, f, 0.25, 1.625, 0, 0.25, 0.25, 0.25, "teal", "Tail")
	box(m, f, 0.125, 1.625, 0.25, 0.5, 0.25, 0.25, "blue", "Fish")
	box(m, f, -0.25, 1.625, 0.25, 0.25, 0.25, 0.25, "teal", "Tail")
	ball(m, f, 0.5, 1.375, 0.375, 0.25, "gold", "Bell")
	cyl(m, f, 0.875, 1.5, 0, 0.5, 0.5, "yellow", "Jug")
	cyl(m, f, 0.875, 1.875, 0, 0.5, 0.25, "white", "Lid")
	box(m, f, 0.875, 1.375, 0.375, 0.25, 0.25, 0.25, "steel", "Tap")
	cyl(m, f, 1.25, 1.375, 0.25, 0.25, 0.25, "pink", "Cup")
	cyl(m, f, 1.25, 1.375, -0.125, 0.25, 0.25, "orange", "Cup")
	-- hung on the front posts: bananas, a lantern
	box(m, f, -1.375, 2.0, 0.75, 0.25, 0.5, 0.25, "yellow", "Bananas")
	lantern(m, f, 1.375, 2.25, 0.75, "yellow")
	-- in front: two stools
	for _, x in { -0.75, 0 } do
		box(m, f, x, 0.5, 0.75, 0.25, 0.5, 0.25, "steel_dark", "StoolLeg")
		cyl(m, f, x, 0.875, 0.75, 0.5, 0.25, "berry_red", "Stool")
	end
end

-- Beach Cafe (4 x 3): a cream cafe on a stone plinth with an orange tiled gable roof and a big coffee cup on a saucer
-- on the ridge; a window with a flower box and a teal door under a short blue and white awning, a window with a
-- flower box and blue shutters on the side; a boardwalk terrace in front with a table under an orange parasol,
-- another table for two with a cup and a slice of cake, a chalk board by the door.
B.cafe = function(m, f)
	box(m, f, 0, 0.125, -0.625, 4.0, 0.25, 1.75, "rock", "Plinth")
	for i = 0, 4 do
		box(m, f, 0, 0.125, 0.375 + i * 0.25, 4.0, 0.25, 0.25, if i % 2 == 0 then "floor_a" else "floor_b", "Boards")
	end
	-- the walls
	box(m, f, 0.25, 1.25, -0.5, 2.5, 2.0, 1.5, "cream", "Walls")
	box(m, f, 0.25, 0.375, -0.5, 2.75, 0.25, 1.75, "teal", "Band")
	-- the front: the window and its flower box, the door, the awning
	win(m, f, -0.25, 1.375, 0.25, 1.0, 1.0, "white", true, true)
	flowerBox(m, f, -0.25, 0.75, 0.25, 1.25, { "pink", "yellow", "pink" })
	door(m, f, 0.875, 0.5, 0.25, 0.75, 1.25, "white", "teal")
	awning(m, f, -1.0, 1.5, 2.25, 0.25, 0.5, 25, "blue", "white")
	-- the east side: a window with a flower box and shutters
	winX(m, f, 1.5, 1.25, -0.5, 0.75, 0.75, "white", true)
	flowerBoxX(m, f, 1.5, 0.75, -0.5, 1.0, { "yellow", "pink" })
	box(m, f, 1.625, 1.25, -1.125, 0.25, 1.0, 0.25, "blue", "Shutter")
	box(m, f, 1.625, 1.25, 0.125, 0.25, 1.0, 0.25, "blue", "Shutter")
	-- the roof and the cup on it
	gable(m, f, 0.25, 2.25, -0.5, 2.5, 1.5, { roof = "orange", tile = "clay", ridge = "clay", gable = "cream", vent = "teal" })
	cyl(m, f, 0.75, 3.5, -0.5, 1.0, 0.25, "teal", "Saucer")
	cyl(m, f, 0.75, 3.875, -0.5, 0.75, 0.75, "white", "Cup")
	cyl(m, f, 0.75, 4.25, -0.5, 0.5, 0.25, "wood_dark", "Coffee")
	box(m, f, 1.25, 3.875, -0.5, 0.25, 0.5, 0.25, "white", "Handle")
	-- the terrace: a table under the parasol, a table for two, a chalk board, a plant
	roundTable(m, f, -1.375, 0.25, 0.875, 0.75, "white")
	chair(m, f, -1.375, 0.25, 0.25, 0, -1, "orange")
	chair(m, f, -1.375, 0.25, 1.25, 0, 1, "orange")
	cyl(m, f, -1.5, 1.25, 0.75, 0.25, 0.25, "pink", "Cup")
	parasol(m, f, -1.375, 0.875, 1.25, 2.5, 1.25, "orange", "white")
	roundTable(m, f, 0.125, 0.25, 1.0, 0.75, "white")
	chair(m, f, -0.5, 0.25, 1.0, -1, 0, "wood")
	chair(m, f, 0.75, 0.25, 1.0, 1, 0, "wood")
	cyl(m, f, 0, 1.25, 1.0, 0.25, 0.25, "wood_dark", "Cup")
	cyl(m, f, 0.25, 1.25, 1.125, 0.25, 0.25, "pink", "Cake")
	menuBoard(m, f, 1.625, 0.25, 0.75, "white", "yellow")
end

-- Seaside Inn (5 x 4): two storeys under a red tiled gable roof with two dormers and a chimney. Below, white plaster on
-- a stone foot, a red door between two lamps, two windows with flower boxes; above, a cream timber frame with three
-- windows (shutters on the outer two) and a balcony on two posts with a white rail and pots of flowers along it. A
-- hanging sign with a wave on it at the corner, shuttered windows on the side, a bench, a pot and a barrel.
B.inn = function(m, f)
	box(m, f, 0, 0.125, 0, 5.0, 0.25, 4.0, "rock", "Footing")
	-- the ground floor
	box(m, f, 0, 1.25, 0, 4.0, 2.0, 2.0, "wall", "Walls")
	box(m, f, 0, 0.375, 0, 4.25, 0.25, 2.25, "rock_dark", "Band")
	win(m, f, -1.25, 1.25, 1.0, 0.75, 0.75, "wood_dark", false, true)
	flowerBox(m, f, -1.25, 0.75, 1.0, 1.0, { "pink", "yellow" })
	win(m, f, 1.25, 1.25, 1.0, 0.75, 0.75, "wood_dark", false, true)
	flowerBox(m, f, 1.25, 0.75, 1.0, 1.0, { "yellow", "pink" })
	door(m, f, 0, 0.5, 1.0, 0.75, 1.25, "wood_dark", "berry_red")
	for _, x in { -0.625, 0.625 } do
		wallLamp(m, f, x, 1.75, 1.0)
	end
	-- the upper floor: a timber frame
	box(m, f, 0, 3.125, 0, 4.0, 1.25, 2.0, "cream", "Upper")
	box(m, f, 0, 2.375, 0, 4.25, 0.25, 2.25, "wood_dark", "FloorBeam")
	for _, p in { { -2.0, 1.0 }, { 2.0, 1.0 }, { 2.0, -1.0 } } do
		box(m, f, p[1], 3.125, p[2], 0.25, 1.75, 0.25, "wood_dark", "CornerPost")
	end
	box(m, f, 0, 3.875, 0, 4.25, 0.25, 2.25, "wood_dark", "TopBeam")
	for _, x in { -1.25, 0, 1.25 } do
		win(m, f, x, 3.125, 1.0, 0.5, 0.75, "wood_dark", false, true)
	end
	for _, x in { -1.75, -0.75, 0.75, 1.75 } do
		box(m, f, x, 3.125, 1.125, 0.25, 0.75, 0.25, "teal", "Shutter")
	end
	-- the balcony
	box(m, f, 0, 2.375, 1.5, 3.75, 0.25, 0.75, "wood", "Balcony")
	for _, x in { -1.75, 1.75 } do
		box(m, f, x, 1.25, 1.625, 0.25, 2.0, 0.25, "wood_dark", "BalconyPost")
		box(m, f, x, 2.875, 1.5, 0.25, 0.25, 0.25, "white", "Rail")
	end
	box(m, f, 0, 2.875, 1.75, 3.75, 0.25, 0.25, "white", "Rail")
	for k = 0, 6 do
		box(m, f, -1.5 + k * 0.5, 2.625, 1.75, 0.25, 0.25, 0.25, "white", "Baluster")
	end
	for i, x in { -1.25, 0, 1.25 } do
		box(m, f, x, 3.125, 1.75, 0.25, 0.25, 0.25, "pot", "Pot")
		ball(m, f, x, 3.375, 1.75, 0.25, if i == 2 then "yellow" else "pink", "Bloom")
	end
	-- the east side: shuttered windows
	winX(m, f, 2.0, 1.25, 0, 0.75, 0.75, "wood_dark")
	box(m, f, 2.125, 1.25, -0.75, 0.25, 1.0, 0.25, "berry_red", "Shutter")
	box(m, f, 2.125, 1.25, 0.75, 0.25, 1.0, 0.25, "berry_red", "Shutter")
	winX(m, f, 2.0, 3.125, 0, 0.5, 0.75, "wood_dark", true)
	-- the roof: tiles, two dormers, a chimney
	gable(m, f, 0, 4.0, 0, 4.0, 2.0, { roof = "berry_red", tile = "brick", ridge = "brick", gable = "cream", vent = "wood_dark" })
	for _, x in { -1.0, 0.5 } do
		box(m, f, x, 4.625, 0.625, 0.75, 0.75, 0.75, "cream", "Dormer")
		box(m, f, x, 4.625, 1.0, 0.5, 0.5, 0.25, "window", "DormerGlass")
		wedge(m, f, x - 0.25, 5.25, 0.625, 1.0, 0.5, 0.5, "berry_red", math.pi / 2, "DormerRoof")
		wedge(m, f, x + 0.25, 5.25, 0.625, 1.0, 0.5, 0.5, "berry_red", -math.pi / 2, "DormerRoof")
	end
	box(m, f, 1.375, 5.375, -0.5, 0.5, 1.75, 0.5, "rock", "Chimney")
	box(m, f, 1.375, 6.375, -0.5, 0.75, 0.25, 0.75, "rock_dark", "ChimneyCap")
	cyl(m, f, 1.375, 6.625, -0.5, 0.25, 0.25, "clay", "ChimneyPot")
	-- the sign at the corner
	box(m, f, 2.125, 2.125, 1.375, 0.25, 0.25, 1.0, "black", "SignArm")
	box(m, f, 2.125, 1.625, 1.5, 0.25, 0.75, 0.75, "wood_dark", "Sign")
	box(m, f, 2.25, 1.625, 1.5, 0.25, 0.5, 0.5, "cream", "SignFace")
	box(m, f, 2.375, 1.625, 1.5, 0.25, 0.25, 0.25, "teal", "SignWave")
	-- out front: a bench, a pot, a barrel
	box(m, f, -1.0, 0.625, 1.75, 1.0, 0.25, 0.5, "wood", "Bench")
	box(m, f, -1.0, 1.0, 1.625, 1.0, 0.5, 0.25, "wood", "BenchBack")
	for _, x in { -1.375, -0.625 } do
		box(m, f, x, 0.375, 1.875, 0.25, 0.25, 0.25, "wood_dark", "BenchLeg")
	end
	potPlant(m, f, 0.625, 0.25, 1.75, "yellow")
	cyl(m, f, 1.25, 0.75, 1.625, 0.5, 1.0, "wood", "Barrel")
	cyl(m, f, 1.25, 1.0, 1.625, 0.75, 0.25, "steel_dark", "Hoop")
	cyl(m, f, 1.25, 0.5, 1.625, 0.75, 0.25, "steel_dark", "Hoop")
end

-- Bakery (4 x 3): a brick shop with cream corner stones and a false front with a round crest over the sign (a loaf
-- between two words), a short red and white striped awning, a white display case of loaves, buns and a cake lit from
-- behind, a door with a glass pane and an "open" card, a little sign with a bun on it hung at the corner; on the flat
-- roof a stone chimney and a hatch, on the east side a window with a flower box, a chalk menu and a bench with a
-- basket of bread; flour sacks and a barrel of baguettes out front.
B.bakery = function(m, f)
	box(m, f, 0, 0.125, 0, 4.0, 0.25, 3.0, "rock", "Footing")
	box(m, f, 0, 1.5, 0, 3.0, 2.5, 1.75, "brick", "Walls")
	box(m, f, 0, 0.375, 0, 3.25, 0.25, 2.0, "rock_dark", "Band")
	for _, p in { { -1.5, 0.875 }, { 1.5, 0.875 }, { 1.5, -0.875 } } do
		box(m, f, p[1], 1.5, p[2], 0.25, 2.0, 0.25, "cream", "Quoin")
	end
	-- the false front, its crest and its sign
	box(m, f, 0, 3.125, 0.75, 3.0, 0.75, 0.25, "brick", "FalseFront")
	box(m, f, 0, 3.625, 0.75, 3.25, 0.25, 0.5, "cream", "Coping")
	discZ(m, f, 0, 3.75, 0.625, 1.5, 0.25, "cream", "Crest")
	discZ(m, f, 0, 3.75, 0.75, 1.0, 0.25, "brick", "Crest")
	box(m, f, 0, 4.0, 1.0, 0.5, 0.25, 0.25, "sand_dark", "CrestLoaf")
	ball(m, f, 0, 4.625, 0.625, 0.25, "gold", "Finial")
	box(m, f, 0, 3.125, 1.0, 2.5, 0.5, 0.25, "cream", "Sign")
	box(m, f, 0, 3.125, 1.125, 0.5, 0.25, 0.25, "sand_dark", "SignLoaf")
	box(m, f, -0.75, 3.125, 1.125, 0.75, 0.25, 0.25, "wood_dark", "Letters")
	box(m, f, 0.75, 3.125, 1.125, 0.75, 0.25, 0.25, "wood_dark", "Letters")
	-- the awning
	awning(m, f, -1.5, 1.5, 2.625, 0.875, 0.5, 25, "berry_red", "white")
	-- the display case
	box(m, f, -0.5, 1.0, 1.0, 1.5, 0.5, 0.25, "window", "CaseGlass")
	box(m, f, -0.5, 1.375, 1.0, 1.25, 0.25, 0.25, "yellow", "CaseLight", true)
	box(m, f, -0.5, 1.625, 1.125, 1.75, 0.25, 0.5, "white", "CaseTop")
	box(m, f, -0.5, 0.625, 1.125, 1.75, 0.25, 0.5, "white", "CaseSill")
	box(m, f, -1.25, 1.125, 1.125, 0.25, 0.75, 0.5, "white", "CaseSide")
	box(m, f, 0.25, 1.125, 1.125, 0.25, 0.75, 0.5, "white", "CaseSide")
	box(m, f, -0.5, 1.125, 1.25, 1.25, 0.25, 0.25, "wood", "CaseShelf")
	box(m, f, -0.875, 0.875, 1.25, 0.5, 0.25, 0.25, "sand_dark", "Loaf")
	ball(m, f, -0.5, 0.875, 1.25, 0.25, "orange", "Bun")
	box(m, f, -0.125, 0.875, 1.25, 0.5, 0.25, 0.25, "wood", "Loaf")
	ball(m, f, -1.0, 1.375, 1.25, 0.25, "orange", "Bun")
	ball(m, f, -0.75, 1.375, 1.25, 0.25, "sand_dark", "Bun")
	cyl(m, f, -0.25, 1.375, 1.25, 0.5, 0.25, "pink", "Cake")
	-- the door, the corner sign
	door(m, f, 0.875, 0.5, 0.875, 0.75, 1.5, "white", "wood_dark")
	box(m, f, 0.75, 1.0, 1.125, 0.5, 0.25, 0.25, "cream", "OpenCard")
	box(m, f, 1.75, 2.375, 1.125, 0.5, 0.25, 0.25, "black", "SignArm")
	box(m, f, 1.75, 2.0, 1.125, 0.5, 0.5, 0.25, "wood_dark", "CornerSign")
	ball(m, f, 1.75, 2.0, 1.25, 0.25, "orange", "SignBun")
	-- the roof: flat, a chimney, a hatch
	box(m, f, 0, 2.875, -0.125, 3.0, 0.25, 1.5, "rock_dark", "Roof")
	box(m, f, 0, 3.125, -0.75, 3.0, 0.25, 0.25, "brick", "Parapet")
	box(m, f, 1.375, 3.125, 0, 0.25, 0.25, 1.25, "brick", "Parapet")
	box(m, f, 0.75, 3.625, -0.25, 0.5, 1.25, 0.5, "rock", "Chimney")
	box(m, f, 0.75, 4.375, -0.25, 0.75, 0.25, 0.75, "rock_dark", "ChimneyCap")
	cyl(m, f, 0.75, 4.625, -0.25, 0.25, 0.25, "clay", "ChimneyPot")
	box(m, f, -0.75, 3.125, -0.25, 0.75, 0.25, 0.5, "wood", "Hatch")
	-- the east side: a window with a flower box, a chalk menu, a bench with a basket of bread
	winX(m, f, 1.5, 1.5, 0.25, 0.75, 0.75, "white", true)
	flowerBoxX(m, f, 1.5, 1.0, 0.25, 1.0, { "pink", "yellow" })
	box(m, f, 1.625, 1.75, -0.5, 0.25, 0.75, 0.5, "wood", "WallMenu")
	box(m, f, 1.75, 1.75, -0.5, 0.25, 0.5, 0.25, "chalk", "WallMenu")
	box(m, f, 1.75, 0.625, -0.5, 0.5, 0.25, 0.5, "wood", "Bench")
	box(m, f, 1.75, 0.375, -0.5, 0.25, 0.25, 0.25, "wood_dark", "BenchLeg")
	box(m, f, 1.75, 0.875, -0.5, 0.25, 0.25, 0.5, "wood_dark", "Basket")
	ball(m, f, 1.75, 1.125, -0.625, 0.25, "sand_dark", "Bun")
	ball(m, f, 1.75, 1.125, -0.375, 0.25, "orange", "Bun")
	-- out front: flour sacks, a barrel of baguettes
	for _, z in { 0.375, 1.125 } do
		box(m, f, -1.75, 0.5, z, 0.5, 0.5, 0.5, "paper", "Sack")
		box(m, f, -1.75, 0.875, z, 0.25, 0.25, 0.25, "sand_dark", "Tie")
	end
	cyl(m, f, 1.75, 0.5, 1.25, 0.5, 0.5, "wood", "Barrel")
	for i, p in { { 1.625, 1.125 }, { 1.875, 1.25 }, { 1.75, 1.375 } } do
		box(m, f, p[1], 0.875 + i * 0.125, p[2], 0.25, 0.75, 0.25, "sand_dark", "Baguette")
	end
end

-- Grand Bazaar (5 x 4): a tiled court with a border, three stalls along the back under scalloped awnings in their own
-- stripes, each with a striped cloth over its counter and its goods (pots and vases, mounds of spice in bowls, bolts
-- of cloth); urns on the ground, carpets on a rack, a rug with a low table, cushions, a teapot and a
-- cup, open sacks of spice, tall jars and a brass lamp with a string of lights to it from the rack.
B.bazaar = function(m, f)
	-- the court
	box(m, f, 0, 0.125, 0, 4.5, 0.25, 3.5, "floor_a", "Court")
	box(m, f, 0, 0.125, -1.875, 5.0, 0.25, 0.25, "sand_dark", "CourtEdge")
	box(m, f, 0, 0.125, 1.875, 5.0, 0.25, 0.25, "sand_dark", "CourtEdge")
	box(m, f, -2.375, 0.125, 0, 0.25, 0.25, 3.5, "sand_dark", "CourtEdge")
	box(m, f, 2.375, 0.125, 0, 0.25, 0.25, 3.5, "sand_dark", "CourtEdge")
	-- the three stalls
	local stripes = { { "orange", "yellow" }, { "purple", "white" }, { "teal", "white" } }
	for i, x in { -1.625, 0, 1.625 } do
		box(m, f, x, 0.5, -0.875, 1.25, 0.5, 0.5, "wood", "Counter")
		box(m, f, x, 0.875, -0.875, 1.5, 0.25, 0.75, "wood_dark", "Top")
		box(m, f, x, 0.5, -0.5, 1.0, 0.5, 0.25, stripes[i][1], "Cloth")
		box(m, f, x, 0.5, -0.375, 0.5, 0.25, 0.25, stripes[i][2], "ClothStripe")
		for _, dx in { -0.625, 0.625 } do
			box(m, f, x + dx, 1.5, -1.25, 0.25, 2.5, 0.25, "wood_dark", "Pole")
		end
		awning(m, f, x - 0.75, x + 0.75, 2.75, -1.125, 0.75, 30, stripes[i][1], stripes[i][2])
	end
	-- the goods: pots and vases, spice, cloth
	cyl(m, f, -2.0, 1.25, -0.875, 0.5, 0.5, "clay", "Vase")
	ball(m, f, -1.5, 1.25, -0.875, 0.5, "blue", "Vase")
	cyl(m, f, -1.5, 1.625, -0.875, 0.25, 0.25, "blue", "VaseNeck")
	cyl(m, f, -1.125, 1.125, -0.75, 0.25, 0.25, "teal", "Cup")
	for j, c in { "orange", "berry_red", "yellow" } do
		local x = -0.5 + (j - 1) * 0.5
		cyl(m, f, x, 1.125, -0.875, 0.5, 0.25, "wood", "Bowl")
		ball(m, f, x, 1.25, -0.875, 0.5, c, "Spice")
	end
	for j, c in { "berry_red", "blue", "yellow", "green" } do
		box(m, f, 1.25 + (j - 1) * 0.25, 1.125, -0.875, 0.25, 0.25, 0.5, c, "Cloth")
	end
	box(m, f, 1.625, 1.375, -0.875, 0.75, 0.25, 0.5, "purple", "Cloth")
	-- urns on the ground before the potter's stall
	cyl(m, f, -1.75, 0.625, -0.125, 0.5, 0.75, "clay", "Urn")
	cyl(m, f, -1.75, 1.125, -0.125, 0.25, 0.25, "clay", "UrnNeck")
	cyl(m, f, -1.25, 0.5, -0.125, 0.5, 0.5, "teal", "Urn")
	-- the carpets on their rack along the west side
	for _, z in { -0.25, 1.5 } do
		box(m, f, -2.25, 1.125, z, 0.25, 1.75, 0.25, "wood_dark", "RackPost")
	end
	box(m, f, -2.25, 2.125, 0.625, 0.25, 0.25, 2.0, "wood_dark", "RackBar")
	for i, c in { "berry_red", "purple", "rug" } do
		local z = -0.375 + i * 0.5
		box(m, f, -2.125, 1.375, z, 0.25, 1.25, 0.5, c, "Carpet")
		box(m, f, -2.0, 1.375, z, 0.25, 0.75, 0.25, if i == 3 then "berry_red" else "rug", "CarpetStripe")
	end
	-- the rug with a low table, cushions, a teapot and a cup
	box(m, f, -0.25, 0.375, 0.75, 1.75, 0.25, 1.25, "berry_red", "Rug")
	box(m, f, -0.25, 0.5, 0.75, 1.25, 0.25, 0.75, "rug", "RugInner")
	box(m, f, -0.25, 0.875, 0.75, 0.75, 0.25, 0.5, "wood_dark", "LowTable")
	box(m, f, -0.25, 0.75, 0.75, 0.25, 0.25, 0.25, "wood_dark", "LowTableLeg")
	cyl(m, f, -0.375, 1.125, 0.75, 0.25, 0.25, "gold", "Teapot")
	cyl(m, f, -0.125, 1.125, 0.875, 0.25, 0.25, "white", "Cup")
	box(m, f, -1.0, 0.75, 0.75, 0.5, 0.25, 0.5, "purple", "Cushion")
	box(m, f, 0.5, 0.75, 0.75, 0.5, 0.25, 0.5, "teal", "Cushion")
	-- sacks of spice and tall jars
	for i, c in { "orange", "yellow", "berry_red" } do
		local x = 1.0 + (i - 1) * 0.5
		box(m, f, x, 0.5, 0.375, 0.5, 0.5, 0.5, "sand", "Sack")
		ball(m, f, x, 0.75, 0.375, 0.5, c, "Spice")
	end
	cyl(m, f, -1.625, 0.75, 1.375, 0.5, 1.0, "clay", "Jar")
	cyl(m, f, -1.625, 1.375, 1.375, 0.25, 0.25, "clay", "JarNeck")
	cyl(m, f, 1.625, 0.625, 1.25, 0.5, 0.75, "teal", "Jar")
	cyl(m, f, 1.625, 1.125, 1.25, 0.25, 0.25, "teal", "JarNeck")
	-- a brass lamp and the lights from the carpet rack to it
	lampPost(m, f, 2.0, 1.625, 0.25, 2.75, "orange", "wood_dark")
	bulbs(m, f, Vector3.new(-2.25, 2.25, 1.5), Vector3.new(2.0, 2.5, 1.625), 7, 0.25, { "yellow", "orange", "pink" })
end

-- Grand Hotel (5 x 5): five floors of cream stone. A lobby with a glass door in a gold frame, windows under blue and
-- white awnings and a red canopy out over the steps on gold poles with the name on it; four floors above with a pink
-- band at each floor, four windows a floor, two on the side, balconies with gold rails and flowers on two floors and
-- a blue and white awning along the top one; white corner stones, a tall red sign down the corner, a cornice, a sign on
-- the roof with lights along it, two loungers, a parasol, pots and a flag up there. Shrubs in white planters, a red
-- carpet and a lamp either side.
B.hotel = function(m, f)
	box(m, f, 0, 0.125, 0, 5.0, 0.25, 5.0, "pavement", "Footing")
	box(m, f, 0, 3.5, -0.25, 4.0, 6.5, 3.0, "cream", "Walls")
	box(m, f, 0, 0.375, -0.25, 4.25, 0.25, 3.25, "rock_dark", "Band")
	-- the lobby
	box(m, f, 0, 1.0, 1.375, 1.25, 1.5, 0.25, "gold", "DoorFrame")
	box(m, f, 0, 0.875, 1.5, 1.0, 1.25, 0.25, "window", "DoorGlass")
	box(m, f, 0, 0.875, 1.625, 0.25, 1.0, 0.25, "gold", "DoorBar")
	for _, x in { -1.375, 1.375 } do
		win(m, f, x, 1.125, 1.25, 0.75, 0.75, "white", true)
		awning(m, f, x - 0.5, x + 0.5, 1.875, 1.375, 0.5, 30, "blue", "white")
	end
	-- the canopy over the steps
	box(m, f, 0, 1.875, 1.75, 1.5, 0.25, 1.0, "berry_red", "Canopy")
	box(m, f, 0, 2.25, 2.125, 1.5, 0.5, 0.25, "gold", "CanopySign")
	box(m, f, 0, 2.25, 2.25, 1.0, 0.25, 0.25, "berry_red", "Letters")
	for _, x in { -0.625, 0.625 } do
		box(m, f, x, 1.0, 2.125, 0.25, 1.5, 0.25, "gold", "CanopyPole")
	end
	box(m, f, 0, 0.375, 2.125, 1.0, 0.25, 0.75, "berry_red", "Carpet")
	-- the four floors above
	for i = 1, 4 do
		local y0 = 1.75 + (i - 1) * 1.25
		box(m, f, 0, y0, 1.25, 3.75, 0.25, 0.25, "wall_trim", "FloorBand")
		box(m, f, 2.0, y0, -0.25, 0.25, 0.25, 2.75, "wall_trim", "FloorBand")
		for _, x in { -1.5, -0.5, 0.5, 1.5 } do
			win(m, f, x, y0 + 0.625, 1.25, 0.5, 0.75, "white", false, true)
		end
		for _, z in { -1.0, 0.25 } do
			winX(m, f, 2.0, y0 + 0.625, z, 0.5, 0.75, "white", true)
		end
		if i % 2 == 0 then
			for _, x in { -1.0, 1.0 } do
				box(m, f, x, y0, 1.625, 1.5, 0.25, 0.5, "white", "Balcony")
				box(m, f, x, y0 + 0.5, 1.75, 1.5, 0.25, 0.25, "gold", "BalconyRail")
				for _, dx in { -0.625, 0.625 } do
					box(m, f, x + dx, y0 + 0.25, 1.75, 0.25, 0.25, 0.25, "gold", "Baluster")
				end
				ball(m, f, x, y0 + 0.75, 1.75, 0.25, if x < 0 then "pink" else "berry_red", "Bloom")
			end
		end
	end
	awning(m, f, -1.75, 1.75, 6.75, 1.25, 0.5, 30, "blue", "white")
	-- the corners and the tall sign
	for _, x in { -2.0, 2.0 } do
		box(m, f, x, 3.5, 1.25, 0.25, 6.0, 0.25, "white", "Quoin")
	end
	box(m, f, 2.125, 4.25, 1.625, 0.25, 2.5, 0.5, "berry_red", "TallSign")
	for k = 0, 3 do
		box(m, f, 2.25, 5.125 - k * 0.5, 1.625, 0.25, 0.25, 0.25, "gold", "TallSignLetter")
	end
	-- the cornice, the roof, the sign, the flag
	box(m, f, 0, 6.875, -0.25, 4.5, 0.25, 3.25, "white", "Cornice")
	box(m, f, 0, 7.125, -0.25, 4.0, 0.25, 3.0, "rock_dark", "Roof")
	box(m, f, 0, 7.375, 1.125, 4.0, 0.25, 0.25, "white", "Parapet")
	box(m, f, 1.875, 7.375, -0.25, 0.25, 0.25, 2.5, "white", "Parapet")
	box(m, f, -0.25, 7.875, 0.5, 2.5, 0.75, 0.25, "berry_red", "RoofSign")
	box(m, f, -0.25, 7.875, 0.625, 2.0, 0.25, 0.25, "gold", "RoofLetters")
	for k = 0, 4 do
		box(m, f, -1.25 + k * 0.5, 8.375, 0.5, 0.25, 0.25, 0.25, "yellow", "SignBulb", true)
	end
	for _, x in { -1.25, 0.75 } do
		box(m, f, x, 7.375, 0.375, 0.25, 0.25, 0.25, "steel_dark", "SignLeg")
	end
	box(m, f, 1.25, 8.0, -1.0, 0.25, 1.5, 0.25, "steel_dark", "FlagPole")
	flag(m, f, 1.375, 8.375, -1.0, 0.75, 0.5, "berry_red")
	ball(m, f, 1.25, 8.875, -1.0, 0.25, "gold", "Knob")
	-- up on the roof: two loungers, a parasol, pots
	for _, x in { 0.625, 1.25 } do
		box(m, f, x, 7.375, -0.25, 0.5, 0.25, 0.75, "white", "Lounger")
		tilt(m, f, x, 7.625, -0.625, 0.5, 0.5, 0.25, CFrame.Angles(-0.4, 0, 0), "blue", "LoungerBack")
	end
	parasol(m, f, -0.375, -0.875, 7.25, 8.25, 1.25, "berry_red", "white")
	potPlant(m, f, -1.5, 7.25, -1.25, "pink")
	potPlant(m, f, -1.5, 7.25, -0.5)
	-- by the steps: shrubs in planters, lamps
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 0.5, 1.75, 0.5, 0.5, 0.5, "white", "Planter")
		ball(m, f, x, 1.125, 1.75, 0.75, "leaf", "Shrub")
		ball(m, f, x, 1.625, 1.75, 0.5, "leaf_dark", "Shrub")
	end
	lampPost(m, f, -2.0, 2.0, 0.25, 2.5)
	lampPost(m, f, 2.0, 2.0, 0.25, 2.5)
end

-- Night Market (5 x 4): a dark street with three food stalls along the back (noodles in a steaming pot, skewers on
-- glowing coals, jars of sweets), each under a striped cloth roof with a valance and two round paper lanterns; a long
-- table with stools, bowls and a little lamp, a cooler of drinks, a food cart with a sign, a striped umbrella and a
-- pot; two posts with paper lanterns on top at the front, a red banner hung from one.
B.nightmarket = function(m, f)
	box(m, f, 0, 0.125, 0, 5.0, 0.25, 4.0, "road", "Street")
	-- the stalls
	local roofs = { "berry_red", "teal", "purple" }
	for k, x in { -1.625, 0, 1.625 } do
		box(m, f, x, 0.625, -0.875, 1.25, 0.75, 0.5, "wood", "Counter")
		box(m, f, x, 1.125, -0.875, 1.25, 0.25, 0.75, "wood_dark", "Top")
		box(m, f, x, 0.625, -0.5, 1.0, 0.5, 0.25, roofs[k], "Cloth")
		for _, dx in { -0.625, 0.625 } do
			box(m, f, x + dx, 1.5, -1.25, 0.25, 2.5, 0.25, "black", "Post")
		end
		for j = -1, 1 do
			box(m, f, x + j * 0.5, 2.875, -0.75, 0.5, 0.25, 1.25, if j == 0 then "white" else roofs[k], "ClothRoof")
		end
		box(m, f, x, 2.625, -0.25, 1.5, 0.25, 0.25, roofs[k], "Valance")
		box(m, f, x, 2.5, -0.125, 0.25, 0.25, 0.25, "gold", "ValanceMark")
		for _, dx in { -0.5, 0.5 } do
			glowBall(m, f, x + dx, 2.25, -0.25, 0.5, if k == 2 then "orange" else "berry_red", "PaperLantern")
		end
	end
	-- noodles, skewers, sweets
	cyl(m, f, -1.875, 1.5, -0.875, 0.5, 0.5, "steel", "Pot")
	ball(m, f, -1.875, 1.875, -0.875, 0.25, "white", "Steam")
	ball(m, f, -1.75, 2.125, -0.875, 0.25, "white", "Steam")
	for _, x in { -1.375, -1.125 } do
		cyl(m, f, x, 1.375, -0.75, 0.25, 0.25, "white", "Bowl")
	end
	box(m, f, 0, 1.375, -0.875, 1.0, 0.25, 0.5, "black", "Grill")
	box(m, f, 0, 1.625, -0.875, 0.75, 0.25, 0.25, "orange", "Coals", true)
	for j = 0, 2 do
		box(m, f, -0.25 + j * 0.25, 1.875, -0.875, 0.25, 0.25, 0.5, if j == 1 then "berry_red" else "wood", "Skewer")
	end
	for j, c in { "pink", "yellow", "green" } do
		local x = 1.25 + (j - 1) * 0.375
		cyl(m, f, x, 1.5, -0.875, 0.25, 0.5, c, "Jar")
		cyl(m, f, x, 1.875, -0.875, 0.25, 0.25, "white", "JarLid")
	end
	-- the long table, stools, bowls, a lamp
	box(m, f, -0.875, 0.875, 0.375, 1.5, 0.25, 0.5, "wood", "Table")
	for _, x in { -1.375, -0.375 } do
		box(m, f, x, 0.5, 0.375, 0.25, 0.5, 0.25, "wood_dark", "TableLeg")
		cyl(m, f, x, 0.5, 0.875, 0.5, 0.5, "berry_red", "Stool")
		cyl(m, f, x, 0.5, -0.125, 0.5, 0.5, "berry_red", "Stool")
	end
	cyl(m, f, -1.125, 1.125, 0.375, 0.25, 0.25, "white", "Bowl")
	cyl(m, f, -0.625, 1.125, 0.375, 0.25, 0.25, "white", "Bowl")
	box(m, f, -0.875, 1.125, 0.375, 0.25, 0.25, 0.25, "yellow", "TableLamp", true)
	-- a cooler of drinks
	box(m, f, 0.25, 0.5, 1.5, 0.75, 0.5, 0.5, "blue", "Cooler")
	box(m, f, 0.25, 0.875, 1.5, 0.75, 0.25, 0.5, "white", "CoolerLid")
	for j, c in { "green", "orange" } do
		box(m, f, 0.125 + (j - 1) * 0.25, 1.125, 1.5, 0.25, 0.25, 0.25, c, "Bottle")
	end
	-- the food cart
	box(m, f, 1.375, 0.875, 0.5, 1.25, 0.75, 0.75, "teal", "Cart")
	box(m, f, 1.375, 1.375, 0.5, 1.5, 0.25, 1.0, "white", "CartTop")
	box(m, f, 1.375, 0.875, 1.0, 0.75, 0.5, 0.25, "cream", "CartSign")
	box(m, f, 1.375, 0.875, 1.125, 0.5, 0.25, 0.25, "berry_red", "Letters")
	box(m, f, 0.625, 0.5, 0.5, 0.25, 0.5, 0.25, "black", "CartLeg")
	discX(m, f, 2.125, 0.625, 0.5, 0.75, 0.25, "black", "Wheel")
	discX(m, f, 2.25, 0.625, 0.5, 0.25, 0.25, "steel", "Hub")
	cyl(m, f, 1.0, 1.75, 0.5, 0.5, 0.5, "steel", "Pot")
	cyl(m, f, 1.0, 2.125, 0.5, 0.5, 0.25, "steel_dark", "Lid")
	parasol(m, f, 1.625, 0.5, 1.5, 2.25, 1.25, "berry_red", "white")
	-- the lantern posts at the front and the banner
	for _, x in { -2.125, 2.125 } do
		box(m, f, x, 0.375, 1.625, 0.5, 0.25, 0.5, "black", "PostFoot")
		box(m, f, x, 1.375, 1.625, 0.25, 1.75, 0.25, "black", "LanternPost")
		glowBall(m, f, x, 2.5, 1.625, 0.5, if x < 0 then "berry_red" else "orange", "PaperLantern")
		box(m, f, x, 2.875, 1.625, 0.25, 0.25, 0.25, "gold", "LanternCap")
	end
	box(m, f, -1.625, 2.125, 1.625, 0.75, 0.25, 0.25, "black", "BannerArm")
	box(m, f, -1.5, 1.375, 1.625, 0.5, 1.25, 0.25, "berry_red", "FlagBanner")
	box(m, f, -1.5, 1.5, 1.75, 0.25, 0.5, 0.25, "gold", "FlagBannerMark")
end

-- Seaside Theatre (5 x 5): a stage house with a temple front: a gold-edged pediment with a star and gold balls on its
-- corners under a red tiled roof, white columns with gold tops, a gold frame round the stage opening with bulbs along
-- it, red curtains tied back under a scalloped valance; on the stage a painted backdrop of sky, sea, sun and a cloud, a
-- prop palm and a chest. An apron with footlights and a step, red benches in two rows either side of a gold carpet, a
-- ticket booth with its board, posters on the side, a lamp and a flag.
B.theatre = function(m, f)
	box(m, f, 0, 0.125, 0, 5.0, 0.25, 5.0, "pavement", "Footing")
	-- the stage house: the back wall, the piers, the lintel, the stage floor
	box(m, f, 0, 2.0, -1.75, 4.0, 3.5, 0.25, "cream", "BackWall")
	for _, x in { -1.75, 1.75 } do
		box(m, f, x, 2.0, -0.625, 0.5, 3.5, 2.0, "cream", "Pier")
	end
	box(m, f, 0, 3.375, -0.625, 3.0, 0.75, 2.0, "cream", "Lintel")
	box(m, f, 0, 0.5, -0.625, 3.0, 0.5, 2.0, "wood", "Stage")
	box(m, f, 0, 3.875, -0.75, 4.0, 0.25, 2.25, "white", "Cornice")
	-- the backdrop and the props
	box(m, f, 0, 1.875, -0.75, 3.0, 2.25, 0.25, "sky_day", "Backdrop")
	box(m, f, 0, 1.0, -0.625, 2.75, 0.5, 0.25, "water", "BackdropSea")
	box(m, f, 0, 1.375, -0.625, 2.75, 0.25, 0.25, "shallow", "BackdropWave")
	discZ(m, f, 0.5, 1.875, -0.5, 0.75, 0.25, "yellow", "BackdropSun")
	box(m, f, -0.75, 2.25, -0.5, 0.75, 0.25, 0.25, "white", "BackdropCloud")
	box(m, f, -0.875, 1.25, -0.25, 0.25, 1.0, 0.25, "wood", "PropTrunk")
	box(m, f, -0.875, 1.875, -0.25, 0.75, 0.25, 0.5, "leaf", "PropLeaves")
	box(m, f, 0.375, 0.875, -0.25, 0.5, 0.25, 0.25, "wood", "PropChest")
	box(m, f, 0.375, 1.125, -0.25, 0.5, 0.25, 0.25, "gold", "PropChestLid")
	-- the curtains and the valance
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 1.875, 0.25, 0.5, 2.25, 0.25, "berry_red", "Curtain")
		box(m, f, x, 1.375, 0.5, 0.5, 0.25, 0.25, "gold", "TieBack")
	end
	box(m, f, 0, 2.875, 0.375, 3.0, 0.25, 0.25, "berry_red", "Valance")
	for k = 0, 3 do
		discZ(m, f, -0.75 + k * 0.5, 2.75, 0.25, 0.5, 0.25, if k % 2 == 0 then "gold" else "berry_red", "Scallop")
	end
	-- the gold frame and its bulbs
	box(m, f, 0, 3.125, 0.5, 3.5, 0.25, 0.25, "gold", "Frame")
	for _, x in { -1.625, 1.625 } do
		box(m, f, x, 1.875, 0.5, 0.25, 2.25, 0.25, "gold", "Frame")
		for k = 0, 2 do
			box(m, f, x, 1.25 + k * 0.625, 0.75, 0.25, 0.25, 0.25, "yellow", "Bulb", true)
		end
	end
	for k = 0, 6 do
		box(m, f, -1.5 + k * 0.5, 3.125, 0.75, 0.25, 0.25, 0.25, "yellow", "Bulb", true)
	end
	-- the columns and the beam on them
	for _, x in { -2.125, 2.125 } do
		box(m, f, x, 0.375, 0.625, 0.5, 0.25, 0.5, "white", "ColumnBase")
		cyl(m, f, x, 2.0, 0.625, 0.5, 3.0, "white", "Column")
		box(m, f, x, 3.625, 0.625, 0.75, 0.25, 0.5, "gold", "Capital")
	end
	box(m, f, 0, 3.875, 0.625, 5.0, 0.25, 0.5, "white", "Entablature")
	-- the roof and the pediment
	wedge(m, f, -1.0, 4.5, -0.625, 2.5, 1.0, 2.0, "berry_red", math.pi / 2, "Roof")
	wedge(m, f, 1.0, 4.5, -0.625, 2.5, 1.0, 2.0, "berry_red", -math.pi / 2, "Roof")
	for k = 0, 3 do
		box(m, f, 2.0 - k * 0.5, 4.0 + k * 0.25, -0.625, 0.5, 0.25, 2.25, if k % 2 == 1 then "brick" else "berry_red", "Tiles")
	end
	box(m, f, 0, 5.0, -0.625, 0.5, 0.25, 2.75, "brick", "Ridge")
	wedge(m, f, -1.0, 4.5, 0.75, 0.25, 1.0, 2.0, "gold", math.pi / 2, "Pediment")
	wedge(m, f, 1.0, 4.5, 0.75, 0.25, 1.0, 2.0, "gold", -math.pi / 2, "Pediment")
	wedge(m, f, -0.75, 4.375, 0.875, 0.25, 0.75, 1.5, "cream", math.pi / 2, "Pediment")
	wedge(m, f, 0.75, 4.375, 0.875, 0.25, 0.75, 1.5, "cream", -math.pi / 2, "Pediment")
	discZ(m, f, 0, 4.375, 1.0, 0.5, 0.25, "gold", "Star")
	for _, x in { -2.125, 2.125 } do
		ball(m, f, x, 4.125, 0.75, 0.25, "gold", "Acroterion")
	end
	box(m, f, 0, 5.375, -1.25, 0.25, 0.5, 0.25, "steel_dark", "FlagPole")
	flag(m, f, 0.125, 5.5, -1.25, 0.5, 0.25, "yellow")
	-- the apron: footlights, a step
	box(m, f, 0, 0.5, 0.625, 3.0, 0.5, 0.5, "wood_dark", "Apron")
	for k = 0, 4 do
		box(m, f, -1.0 + k * 0.5, 0.875, 0.75, 0.25, 0.25, 0.25, "yellow", "Footlight", true)
	end
	box(m, f, 0, 0.375, 1.0, 1.0, 0.25, 0.25, "rock", "Step")
	-- the benches either side of the carpet
	box(m, f, 0, 0.375, 1.875, 0.5, 0.25, 1.25, "rug", "Carpet")
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 0.625, 1.5, 1.25, 0.25, 0.5, "berry_red", "Bench")
		box(m, f, x, 1.0, 1.875, 1.25, 0.5, 0.25, "berry_red", "BenchBack")
		box(m, f, x, 0.625, 2.25, 1.25, 0.25, 0.5, "berry_red", "Bench")
		for _, z in { 1.5, 2.25 } do
			box(m, f, x, 0.375, z, 0.25, 0.25, 0.25, "wood_dark", "BenchLeg")
		end
	end
	-- the ticket booth, posters, a lamp
	box(m, f, 2.0, 1.0, 1.75, 0.75, 1.5, 0.75, "berry_red", "Booth")
	box(m, f, 2.0, 1.875, 1.75, 1.0, 0.25, 1.0, "gold", "BoothRoof")
	box(m, f, 2.0, 1.25, 2.125, 0.5, 0.5, 0.25, "window", "BoothWindow")
	box(m, f, 2.0, 2.25, 1.75, 0.75, 0.5, 0.25, "cream", "BoothBoard")
	box(m, f, 2.0, 2.25, 1.875, 0.5, 0.25, 0.25, "berry_red", "Letters")
	for i, z in { -1.125, -0.25 } do
		box(m, f, 2.125, 2.125, z, 0.25, 1.0, 0.75, "wood_dark", "PosterFrame")
		box(m, f, 2.25, 2.125, z, 0.25, 0.75, 0.5, if i == 1 then "orange" else "teal", "Poster")
	end
	lampPost(m, f, -2.125, 2.125, 0.25, 2.5)
end

-- Sky Tram (5 x 5): a station of white walls and a glass front with a door on a dark band, plants either side; on it a
-- teal deck with a white rail, a sign board, a little cabin with a flag and the cable's wheel; a steel pylon at the
-- back with braces, its sign, a head with two flags and a red wheel on top, the cable between them and a red and
-- white car with windows all round hanging half way; a flower box under the side window, a ticket booth under a
-- striped awning with a map board on its side, a bench and lamps.
B.skytram = function(m, f)
	box(m, f, 0, 0.125, 0, 5.0, 0.25, 5.0, "pavement", "Footing")
	-- the station
	box(m, f, -1.0, 1.125, 0.75, 2.5, 1.75, 2.0, "white", "Walls")
	box(m, f, -1.0, 0.375, 0.75, 2.75, 0.25, 2.25, "rock_dark", "Band")
	box(m, f, -1.0, 1.125, 1.75, 2.0, 1.0, 0.25, "window", "Glass")
	for _, x in { -1.5, -0.5 } do
		box(m, f, x, 1.25, 1.875, 0.25, 1.25, 0.25, "teal", "Mullion")
	end
	box(m, f, -1.0, 1.75, 1.875, 0.75, 0.25, 0.25, "teal", "DoorHead")
	for _, x in { -1.125, -0.875 } do
		box(m, f, x, 1.0, 2.0, 0.25, 0.25, 0.25, "gold", "Handle")
	end
	box(m, f, -1.0, 0.5, 1.875, 2.25, 0.25, 0.25, "teal", "Sill")
	winX(m, f, 0.25, 1.125, 0.75, 1.25, 0.75, "teal", true)
	flowerBoxX(m, f, 0.25, 0.625, 0.75, 1.5, { "pink", "yellow", "pink" })
	potPlant(m, f, -1.75, 0.25, 2.25, "pink")
	potPlant(m, f, -0.25, 0.25, 2.25, "yellow")
	box(m, f, -1.0, 2.125, 0.75, 2.75, 0.25, 2.25, "teal", "Deck")
	box(m, f, -1.0, 2.125, 2.0, 1.75, 0.5, 0.25, "white", "SignBoard")
	box(m, f, -1.0, 2.125, 2.125, 1.25, 0.25, 0.25, "berry_red", "Letters")
	for _, x in { -1.75, -1.25, -0.75, -0.25 } do
		box(m, f, x, 2.5, 1.75, 0.25, 0.5, 0.25, "white", "Baluster")
	end
	box(m, f, -1.0, 2.875, 1.75, 2.5, 0.25, 0.25, "white", "Rail")
	-- the cabin on the deck
	box(m, f, -1.75, 2.75, -0.125, 0.75, 1.0, 0.75, "white", "Cabin")
	box(m, f, -1.75, 2.75, 0.25, 0.5, 0.5, 0.25, "window", "CabinWindow")
	box(m, f, -1.75, 3.375, -0.125, 1.0, 0.25, 1.0, "teal", "CabinRoof")
	box(m, f, -1.75, 3.75, -0.125, 0.25, 0.5, 0.25, "steel_dark", "FlagPole")
	flag(m, f, -1.625, 3.875, -0.125, 0.5, 0.25, "berry_red")
	-- the wheel on the deck
	cyl(m, f, -0.75, 2.375, 0.75, 1.5, 0.25, "steel_dark", "Wheel")
	cyl(m, f, -0.75, 2.625, 0.75, 0.5, 0.25, "berry_red", "Hub")
	-- the pylon
	for _, p in { { 1.375, -1.375 }, { 2.125, -1.375 }, { 1.375, -2.125 }, { 2.125, -2.125 } } do
		box(m, f, p[1], 3.125, p[2], 0.25, 5.75, 0.25, "steel", "Leg")
	end
	for _, y in { 1.25, 2.75, 4.25 } do
		box(m, f, 1.75, y, -1.375, 0.5, 0.25, 0.25, "steel_dark", "Brace")
		box(m, f, 2.125, y, -1.75, 0.25, 0.25, 0.5, "steel_dark", "Brace")
	end
	for _, y in { 2.0, 3.5 } do
		tilt(m, f, 1.75, y, -1.375, 0.25, 1.5, 0.25, CFrame.Angles(0, 0, 0.45), "steel_dark", "Brace")
		tilt(m, f, 2.125, y, -1.75, 0.25, 1.5, 0.25, CFrame.Angles(0.45, 0, 0), "steel_dark", "Brace")
	end
	box(m, f, 1.75, 3.875, -1.125, 1.0, 0.75, 0.25, "white", "PylonSign")
	box(m, f, 1.75, 3.875, -0.875, 0.75, 0.25, 0.25, "berry_red", "Letters")
	box(m, f, 1.75, 6.125, -1.75, 1.25, 0.25, 1.25, "steel_dark", "Head")
	discX(m, f, 1.75, 6.5, -1.75, 0.75, 0.25, "berry_red", "Sheave")
	for _, z in { -2.25, -1.25 } do
		box(m, f, 1.25, 6.5, z, 0.25, 0.5, 0.25, "steel_dark", "FlagPole")
		flag(m, f, 1.375, 6.625, z, 0.5, 0.25, if z < -2 then "yellow" else "berry_red")
	end
	-- the cable and the car
	local a, b = Vector3.new(-0.75, 2.625, 0.75), Vector3.new(1.75, 6.5, -1.75)
	span(m, f, a, b, 0.25, 0.25, "black", "Cable")
	local c = a:Lerp(b, 0.55)
	box(m, f, c.X, c.Y - 0.375, c.Z, 0.25, 0.5, 0.25, "steel_dark", "Hanger")
	box(m, f, c.X, c.Y - 0.75, c.Z, 1.0, 0.25, 0.75, "white", "CarRoof")
	box(m, f, c.X, c.Y - 1.125, c.Z, 1.0, 0.5, 0.75, "window", "CarWindows")
	box(m, f, c.X, c.Y - 1.125, c.Z, 0.25, 0.5, 1.0, "berry_red", "CarPillar")
	box(m, f, c.X, c.Y - 1.5, c.Z, 1.0, 0.25, 0.75, "berry_red", "Car")
	-- the ticket booth and its map board, a bench, lamps
	box(m, f, 1.375, 1.0, 1.25, 1.0, 1.5, 0.75, "berry_red", "Booth")
	box(m, f, 1.375, 1.125, 1.625, 0.5, 0.5, 0.25, "window", "BoothWindow")
	box(m, f, 1.375, 1.875, 1.25, 1.25, 0.25, 1.0, "white", "BoothRoof")
	awning(m, f, 0.875, 1.875, 1.75, 1.625, 0.5, 25, "berry_red", "white")
	box(m, f, 2.0, 1.25, 1.125, 0.25, 0.75, 0.75, "wood_dark", "MapBoard")
	box(m, f, 2.125, 1.25, 1.125, 0.25, 0.5, 0.5, "teal", "Map")
	box(m, f, 2.25, 1.25, 1.125, 0.25, 0.25, 0.25, "green", "MapIsland")
	box(m, f, 0.375, 0.625, -1.5, 1.25, 0.25, 0.5, "wood", "Bench")
	box(m, f, 0.375, 1.0, -1.625, 1.25, 0.5, 0.25, "wood", "BenchBack")
	for _, x in { -0.125, 0.875 } do
		box(m, f, x, 0.375, -1.5, 0.25, 0.25, 0.25, "wood_dark", "BenchLeg")
	end
	lampPost(m, f, 2.125, 0.25, 0.25, 2.5)
	lampPost(m, f, -2.25, 2.25, 0.25, 2.5)
end

return B
