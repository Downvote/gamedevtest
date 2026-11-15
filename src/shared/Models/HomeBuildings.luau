--!strict
-- The island's huts (kind "nest") and the Hatchery (kind "breed"), from parts (GAME_DESIGN 4; Data/Buildings). Each
-- builder takes the model, the frame at the footprint's centre on the grass (facing +Z before the piece's turn) and the
-- level, and stays inside the footprint. The pieces they share are Models/BuildKit's; the small ones only the homes
-- use (round doors, windows with shutters and flower boxes, lanterns, chimneys with a curl of smoke, roofs with rows of
-- thatch, mushrooms, flowers) are below. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.", then rebuilt for it: every home much busier, its front (+Z) and east
-- (+X) faces and its roof dressed, the side the camera sees. Sizes are whole quarter studs (Blocks snaps them), so a
-- trim sits a few hundredths proud of its wall and never on the same plane. The back-left corner stays low for the
-- upgrade pennant.)
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local wedge = K.wedge
local span = K.span


type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

local TAU = math.pi * 2

-- A part at f * cf (turned or tilted).
local function part(m: Instance, cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: ("Block" | "Wedge" | "Cylinder" | "Ball")?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = cf, color = color, name = name, shape = shape, neon = neon, collide = false })
end

-- A disc facing +Z (a cylinder whose axis runs along Z), t thick.
local function discZ(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string, neon: boolean?): BasePart
	return part(m, f * CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), t, dia, dia, color, name, "Cylinder", neon)
end

-- A disc facing +X.
local function discX(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string, neon: boolean?): BasePart
	return part(m, f * CFrame.new(x, y, z), t, dia, dia, color, name, "Cylinder", neon)
end

-- The frame of the east wall whose face is at x: its +Z is the world's +X, its +X the world's -Z (a world z of zc is
-- an x of -zc on it), so the front's helpers dress the side the same way.
local function east(f: CFrame, x: number): CFrame
	return f * CFrame.new(x, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
end

-- A point on a ball of radius r at c, toward (dx, dy, dz), pushed out by `out`.
local function onBall(c: Vector3, r: number, dx: number, dy: number, dz: number, out: number?): Vector3
	return c + Vector3.new(dx, dy, dz).Unit * (r + (out or 0))
end

-- A driftling's round door in a wall whose face is at z (frame g): a frame ring, the door with a seam down it, a brass
-- knob, sitting on y0.
local function roundDoor(m: Instance, g: CFrame, x: number, y0: number, z: number, dia: number, color: string, seam: string, frame: string)
	local cy = y0 + dia / 2 + 0.125
	discZ(m, g, x, cy, z, dia + 0.25, 0.25, frame, "DoorFrame")
	discZ(m, g, x, cy, z + 0.06, dia, 0.25, color, "Door")
	if dia < 0.5 then
		return
	end
	box(m, g, x, cy, z + 0.09, 0.25, dia - 0.25, 0.25, seam, "Seam")
	if dia >= 1.25 then
		for _, s in { -1, 1 } do
			box(m, g, x + s * dia / 4, cy, z + 0.09, 0.25, dia - 0.5, 0.25, seam, "Seam")
		end
	end
	ball(m, g, x + dia * 0.25 + 0.06, cy, z + 0.16, 0.25, "gold", "Knob")
end

-- A window in a wall whose face is at z (frame g): a frame, the glass with a glint in its top left corner, a bar
-- down a wide one, a sill; shutters either side if given a colour, a flower box under it if given blooms.
local function window(m: Instance, g: CFrame, x: number, y: number, z: number, w: number, h: number, frame: string, shutter: string?, blooms: { string }?)
	box(m, g, x, y, z, w + 0.25, h + 0.25, 0.25, frame, "WindowFrame")
	box(m, g, x, y, z + 0.03, w, h, 0.25, "window", "Glass")
	if w >= 0.75 then
		box(m, g, x, y, z + 0.06, 0.25, h, 0.25, frame, "Bar")
		box(m, g, x - w / 2 + 0.125, y + h / 2 - 0.125, z + 0.06, 0.25, 0.25, 0.25, "white", "Glint")
	end
	box(m, g, x, y - h / 2 - 0.125, z + 0.125, w + 0.5, 0.25, 0.25, frame, "Sill")
	if shutter then
		for _, s in { -1, 1 } do
			box(m, g, x + s * (w / 2 + 0.25), y, z + 0.06, 0.25, h + 0.25, 0.25, shutter, "Shutter")
		end
	end
	if blooms then
		box(m, g, x, y - h / 2 - 0.375, z + 0.19, w + 0.25, 0.25, 0.25, "wood", "FlowerBox")
		local n = #blooms
		for i, c in blooms do
			ball(m, g, x - (w + 0.25) / 2 + (i - 0.5) * (w + 0.25) / n, y - h / 2 - 0.2, z + 0.25, 0.25, c, "Bloom")
		end
	end
end

-- A round window in a wall whose face is at z (frame g): a ring, the glass, a cross of bars.
local function porthole(m: Instance, g: CFrame, x: number, y: number, z: number, dia: number, ring: string)
	discZ(m, g, x, y, z, dia + 0.25, 0.25, ring, "WindowRing")
	discZ(m, g, x, y, z + 0.03, dia, 0.25, "window", "Glass")
	if dia >= 0.75 then
		box(m, g, x, y, z + 0.06, 0.25, dia, 0.25, ring, "Bar")
	end
end

-- A lantern hanging at (x, y, z): a dark cap over a lit glass (y is the glass's middle); a small one's cap is no wider
-- than its glass.
local function lantern(m: Instance, f: CFrame, x: number, y: number, z: number, small: boolean?)
	local c = if small then 0.25 else 0.5
	box(m, f, x, y + 0.375, z, c, 0.25, c, "black", "LanternCap")
	box(m, f, x, y, z, 0.25, 0.5, 0.25, "yellow", "Lantern", true)
end

-- A chimney standing on y0, h tall: the stack, a cap, a curl of smoke drifting east.
local function chimney(m: Instance, f: CFrame, x: number, y0: number, z: number, h: number, color: string, puffs: number?)
	box(m, f, x, y0 + h / 2, z, 0.5, h, 0.5, color, "Chimney")
	box(m, f, x, y0 + h, z, 0.75, 0.25, 0.75, "rock", "ChimneyCap")
	local top = y0 + h + 0.125
	local curl = { { 0.0, 0.25, 0.0, 0.25 }, { 0.2, 0.5, 0.06, 0.5 }, { 0.5, 0.75, 0.0, 0.25 } }
	for k = 1, puffs or 3 do
		local c = curl[k]
		ball(m, f, x + c[1], top + c[2], z + c[3], c[4], "white", "Smoke")
	end
end

-- A gable roof along X in frame g over a w x d box whose top is at y, h tall at the ridge, `over` past the walls: two
-- wedges, rows of thatch or shingles across the front slope a little proud of it, a ridge on top and a fringe along
-- the front eave. W and D (w, d plus twice `over`) want to be whole half studs.
local function gable(m: Instance, g: CFrame, y: number, w: number, d: number, h: number, over: number, color: string, row: string, ridge: string)
	local W, D = w + over * 2, d + over * 2
	wedge(m, g, 0, y + h / 2, -D / 4, W, h, D / 2, color, 0, "Roof")
	wedge(m, g, 0, y + h / 2, D / 4, W, h, D / 2, color, math.pi, "Roof")
	local a = math.atan2(h, D / 2)
	local L = math.sqrt(h * h + D * D / 4)
	local s = 0.5
	while s < L - 0.2 do
		part(m, g * CFrame.new(0, y + h - s * math.sin(a) - 0.075 * math.cos(a), s * math.cos(a) - 0.075 * math.sin(a)) * CFrame.Angles(a, 0, 0), W + 0.25, 0.25, 0.25, row, "RoofRow")
		s += 0.5
	end
	box(m, g, 0, y + h - 0.03, 0, W + 0.25, 0.25, 0.5, ridge, "Ridge")
	box(m, g, 0, y - 0.06, D / 2 - 0.125, W + 0.25, 0.25, 0.25, row, "Eave")
end

-- A mushroom on y: a pale stalk, a cap with a brim and a white spot.
local function shroom(m: Instance, f: CFrame, x: number, y: number, z: number, color: string, big: boolean?)
	local sh = if big then 0.5 else 0.25
	local d = if big then 0.75 else 0.5
	box(m, f, x, y + sh / 2, z, 0.25, sh, 0.25, "cream", "Stalk")
	cyl(m, f, x, y + sh + 0.06, z, d, 0.25, color, "Cap")
	ball(m, f, x, y + sh + 0.12, z, d, color, "Cap")
	ball(m, f, x + d * 0.15, y + sh + 0.12 + d * 0.3, z + d * 0.2, 0.25, "white", "Spot")
end

-- A flower on y: a stem and its bloom.
local function flower(m: Instance, f: CFrame, x: number, y: number, z: number, color: string)
	box(m, f, x, y + 0.125, z, 0.25, 0.25, 0.25, "leaf", "Stem")
	ball(m, f, x, y + 0.31, z, 0.25, color, "Bloom")
end

-- A tuft of grass on y: two blades leaning apart.
local function tuft(m: Instance, f: CFrame, x: number, y: number, z: number)
	part(m, f * CFrame.new(x - 0.06, y + 0.2, z) * CFrame.Angles(0.2, 0, 0.3), 0.25, 0.5, 0.25, "leaf", "Grass")
	part(m, f * CFrame.new(x + 0.06, y + 0.2, z + 0.03) * CFrame.Angles(-0.2, 0, -0.3), 0.25, 0.5, 0.25, "leaf_dark", "Grass")
end

-- A flat stepping stone set in the ground at y.
local function stone(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?)
	cyl(m, f, x, y - 0.06, z, dia, 0.25, color or "pavement", "SteppingStone")
end

-- A ground pad w x d whose top is at `top`.
local function pad(m: Instance, f: CFrame, w: number, d: number, top: number, color: string, name: string?)
	box(m, f, 0, top - 0.125, 0, w, 0.25, d, color, name or "Lawn")
end

-- Driftling Hut (2 x 2): a deep nest woven of straw in three rows that cross, on a ring of pebbles, lined with soft
-- felt; two speckled eggs in it, twigs and a feather poking out, a plank ramp up to the rim, a name board on a post
-- with a lantern hanging off it, flowers and loose straw round it.
B.nest = function(m, f)
	local cx, cz = 0.2, 0.2
	local function at(r: number, a: number, y: number): CFrame
		return f * CFrame.new(cx + math.cos(a) * r, y, cz + math.sin(a) * r) * CFrame.Angles(0, -a - math.pi / 2, 0)
	end
	local pebbles = { "rock", "rock_dark", "pavement" }
	for i = 0, 9 do
		local a = i / 10 * TAU + 0.3
		part(m, at(0.62, a, 0), 0.5, 0.25, 0.25, pebbles[i % 3 + 1], "Pebble")
	end
	cyl(m, f, cx, 0.3, cz, 1.0, 0.5, "sand_dark", "Core")
	cyl(m, f, cx, 0.575, cz, 1.0, 0.25, "cream", "Lining")
	-- three rows of straw, crossing each other like a weave, the top one rolled out a little into a rim
	for i = 0, 11 do
		local a = i / 12 * TAU
		part(m, at(0.55, a, 0.25) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.35 else -0.35), 0.5, 0.25, 0.25, "sand_dark", "Straw")
		local b = a + TAU / 24
		part(m, at(0.58, b, 0.48) * CFrame.Angles(0, 0, if i % 2 == 0 then -0.35 else 0.35), 0.5, 0.25, 0.25, "straw", "Straw")
	end
	for i = 0, 13 do
		local a = i / 14 * TAU
		part(m, at(0.6, a, 0.7) * CFrame.Angles(-0.3, 0, 0), 0.5, 0.25, 0.25, if i % 2 == 0 then "straw" else "sand_dark", "Rim")
	end
	-- the eggs, a speckle on each
	ball(m, f, cx - 0.15, 0.88, cz - 0.05, 0.5, "cream", "Egg")
	ball(m, f, cx - 0.04, 0.98, cz + 0.1, 0.25, "blue", "Speckle")
	ball(m, f, cx + 0.2, 0.85, cz + 0.2, 0.5, "cherry", "Egg")
	ball(m, f, cx + 0.35, 0.9, cz + 0.32, 0.25, "berry_red", "Speckle")
	-- twigs and a feather poking out
	for _, t in { { 0.35, 0.3 }, { 2.8, 0.45 }, { 5.1, 0.35 } } do
		part(m, at(0.5, t[1], t[2]) * CFrame.Angles(0.7, 0, 0), 0.25, 0.25, 0.5, "wood_dark", "Twig")
	end
	part(m, f * CFrame.new(0.62, 0.8, 0.0) * CFrame.Angles(0.25, 0.5, 0.35), 0.25, 0.25, 0.75, "white", "Feather")
	-- a plank ramp up to the rim with two cleats
	local a0, a1 = Vector3.new(0.15, 0.1, 0.8), Vector3.new(0.15, 0.72, 0.52)
	span(m, f, a0, a1, 0.5, 0.25, "wood", "Ramp")
	local dir = (a1 - a0).Unit
	local up = Vector3.new(0, -dir.Z, dir.Y)
	for _, t in { 0.3, 0.7 } do
		local c = a0 + (a1 - a0) * t + up * 0.13
		span(m, f, c - dir * 0.125, c + dir * 0.125, 0.5, 0.25, "wood_dark", "Cleat")
	end
	-- the name board, the lantern hanging off its post
	box(m, f, -0.7, 0.5, 0.55, 0.25, 1.0, 0.25, "wood_dark", "SignPost")
	box(m, f, -0.7, 0.55, 0.7, 0.5, 0.5, 0.25, "wood", "Sign")
	box(m, f, -0.67, 0.55, 0.74, 0.25, 0.25, 0.25, "wood_dark", "Carving")
	box(m, f, -0.57, 0.94, 0.58, 0.5, 0.25, 0.25, "wood_dark", "Hook")
	lantern(m, f, -0.47, 0.6, 0.62, true)
	-- flowers and loose straw
	for _, p in { { x = -0.15, z = 0.85, c = "pink" }, { x = -0.85, z = 0.05, c = "yellow" }, { x = 0.85, z = 0.8, c = "white" }, { x = 0.6, z = -0.8, c = "pink" } } do
		flower(m, f, p.x, 0, p.z, p.c)
	end
	part(m, f * CFrame.new(-0.4, 0, 0.2) * CFrame.Angles(0, 0.6, 0), 0.5, 0.25, 0.25, "straw", "LooseStraw")
	part(m, f * CFrame.new(0.55, 0, 0.75) * CFrame.Angles(0, -0.4, 0), 0.5, 0.25, 0.25, "sand_dark", "LooseStraw")
end

-- Cozy Burrow (3 x 3): a grassy hill with clover on it and a round stone porch poking out of it, the round teal door
-- in a wooden ring inside it, a step, grass hanging over the porch; a round window on a bump of the hill with a flower
-- box under it, a lantern on a post, a brick chimney with a curl of smoke; a mailbox on the east side, a carrot patch,
-- mushrooms and stepping stones in the yard.
B.burrow = function(m, f)
	pad(m, f, 3, 3, 0.125, "grass_dark")
	ball(m, f, 0.1, -0.2, -0.1, 2.75, "grass", "Mound")
	ball(m, f, 0.25, 0.55, -0.35, 1.75, "grass", "Mound")
	ball(m, f, 0.35, 1.2, -0.4, 0.75, "moss", "Clover")
	ball(m, f, -0.45, 0.85, -0.2, 0.5, "moss", "Clover")
	-- the stone porch and the door
	discZ(m, f, 0, 0.75, 0.9, 1.75, 0.75, "rock", "Porch")
	for k = 0, 4 do
		local a = math.pi * (0.1 + k * 0.2)
		discZ(m, f, math.cos(a) * 0.75, 0.75 + math.sin(a) * 0.75, 0.94, 0.25, 0.25, if k % 2 == 0 then "pavement" else "rock_dark", "PorchStone")
	end
	roundDoor(m, f, 0, 0.125, 1.2, 1.0, "teal", "swamp", "wood_dark")
	box(m, f, 0, 0.125, 1.35, 1.0, 0.25, 0.25, "rock", "Step")
	for k, x in { -0.45, 0.0, 0.45 } do
		ball(m, f, x, 1.62, 0.65 + (k % 2) * 0.1, 0.5, if k == 2 then "moss" else "grass", "Overhang")
	end
	-- the round window, its flower box, the lantern post
	ball(m, f, 0.95, 0.6, 0.55, 1.0, "grass", "Mound")
	porthole(m, f, 0.95, 0.7, 0.95, 0.5, "wood_dark")
	box(m, f, 0.95, 0.26, 1.15, 0.75, 0.25, 0.25, "wood", "FlowerBox")
	for k, c in { "pink", "yellow", "pink" } do
		ball(m, f, 0.7 + (k - 1) * 0.25, 0.42, 1.18, 0.25, c, "Bloom")
	end
	box(m, f, -0.9, 0.5, 1.0, 0.25, 1.0, 0.25, "wood_dark", "LampPost")
	box(m, f, -0.78, 1.06, 1.03, 0.5, 0.25, 0.25, "wood_dark", "LampArm")
	lantern(m, f, -0.65, 0.6, 1.0)
	-- the chimney on the hill
	chimney(m, f, 0.6, 1.1, -0.5, 0.5, "brick", 1)
	for k, d in { { -0.3, 1, 0.1 }, { 0.4, 0.9, -0.3 }, { -0.6, 0.7, -0.4 } } do
		local p = onBall(Vector3.new(0.1, -0.2, -0.1), 1.375, d[1], d[2], d[3], 0.05)
		ball(m, f, p.X, p.Y, p.Z, 0.25, ({ "white", "yellow", "pink" })[k], "Bloom")
	end
	-- the yard: a mailbox, a carrot patch, mushrooms, stepping stones
	box(m, f, 1.25, 0.5, 0.45, 0.25, 0.75, 0.25, "wood_dark", "MailPost")
	box(m, f, 1.25, 1.0, 0.45, 0.5, 0.25, 0.5, "blue", "Mailbox")
	box(m, f, 1.28, 1.06, 0.25, 0.25, 0.25, 0.25, "berry_red", "MailFlag")
	box(m, f, -1.2, 0.19, 1.05, 0.5, 0.25, 0.75, "wood_dark", "Soil")
	for k = 0, 1 do
		box(m, f, -1.2, 0.25, 0.85 + k * 0.4, 0.25, 0.25, 0.25, "orange", "Carrot")
		box(m, f, -1.2 + k * 0.06, 0.5, 0.85 + k * 0.4, 0.25, 0.25, 0.25, "leaf", "CarrotTop")
	end
	shroom(m, f, -1.05, 0.125, 0.3, "berry_red", true)
	shroom(m, f, -0.75, 0.125, 0.15, "berry_red")
	stone(m, f, 0.6, 0.125, 1.22, 0.5)
	stone(m, f, 1.1, 0.125, 1.1, 0.25, "rock")
	stone(m, f, -0.55, 0.125, 1.35, 0.25)
	flower(m, f, -0.7, 0.125, 1.3, "yellow")
	tuft(m, f, -1.2, 0.125, -0.3)
	tuft(m, f, 1.15, 0.125, 1.2)
end

-- Driftling Den (3 x 3): a heap of mossy boulders with ferns on top, a round mouth in front ringed with arch stones,
-- beds of straw and a pillow inside it and a mat at the door; a little fire in a ring of stones with a log bench by
-- it, firewood stacked by the west side with its cut ends out, mushrooms and a sign.
B.den = function(m, f)
	pad(m, f, 3, 3, 0.125, "grass_dark")
	local rock = Vector3.new(0.2, 0.5, -0.2)
	ball(m, f, rock.X, rock.Y, rock.Z, 2.5, "rock", "Rock")
	ball(m, f, 0.45, 1.6, -0.45, 1.5, "rock_dark", "Rock")
	ball(m, f, -0.45, 1.25, -0.35, 1.25, "rock", "Rock")
	ball(m, f, 0.95, 0.5, -0.9, 1.0, "rock_dark", "Rock")
	-- moss and ferns on top
	ball(m, f, 0.4, 2.2, -0.45, 1.0, "moss", "Moss")
	ball(m, f, -0.35, 1.75, -0.3, 0.75, "moss", "Moss")
	for _, d in { { 0.6, 0.7, 0.3 }, { -0.4, 0.8, 0.3 } } do
		local p = onBall(rock, 1.25, d[1], d[2], d[3], -0.1)
		ball(m, f, p.X, p.Y, p.Z, 0.5, "moss", "Moss")
	end
	for k = 0, 4 do
		local a = k / 5 * TAU
		part(m, f * CFrame.new(0.4 + math.cos(a) * 0.3, 2.75, -0.45 + math.sin(a) * 0.3) * CFrame.Angles(0, -a, 0.6), 0.75, 0.25, 0.25, if k % 2 == 0 then "leaf" else "leaf_dark", "Fern")
	end
	-- the mouth, its arch stones, the beds inside, the mat
	discZ(m, f, 0.15, 0.75, 0.95, 1.25, 0.25, "black", "Mouth")
	for k = 0, 6 do
		local a = math.pi * (k / 6)
		part(m, f * CFrame.new(0.15 + math.cos(a) * 0.72, 0.75 + math.sin(a) * 0.72, 1.0) * CFrame.Angles(0, 0, a + math.pi / 2), 0.5, 0.25, 0.25, if k % 2 == 0 then "pavement" else "rock_dark", "ArchStone")
	end
	box(m, f, 0.15, 0.25, 1.06, 1.0, 0.25, 0.25, "straw", "Bed")
	box(m, f, -0.1, 0.5, 1.03, 0.5, 0.25, 0.25, "sand_dark", "Bed")
	ball(m, f, 0.45, 0.45, 1.06, 0.25, "cherry", "Pillow")
	box(m, f, 0.15, 0.06, 1.3, 0.75, 0.25, 0.25, "rug", "Mat")
	-- the fire and the log bench
	for k = 0, 5 do
		local a = k / 6 * TAU
		ball(m, f, 1.0 + math.cos(a) * 0.3, 0.19, 0.65 + math.sin(a) * 0.3, 0.25, if k % 2 == 0 then "rock" else "rock_dark", "FireStone")
	end
	part(m, f * CFrame.new(1.0, 0.25, 0.65) * CFrame.Angles(0, 0.5, 0), 0.5, 0.25, 0.25, "wood_dark", "Firewood")
	part(m, f * CFrame.new(1.0, 0.25, 0.65) * CFrame.Angles(0, -0.6, 0), 0.5, 0.25, 0.25, "wood", "Firewood")
	box(m, f, 1.0, 0.44, 0.65, 0.25, 0.25, 0.25, "orange", "Flame", true)
	box(m, f, 1.03, 0.62, 0.68, 0.25, 0.25, 0.25, "yellow", "Flame", true)
	part(m, f * CFrame.new(0.9, 0.375, 1.25), 0.75, 0.5, 0.5, "wood_dark", "Bench", "Cylinder")
	discX(m, f, 1.2, 0.375, 1.25, 0.25, 0.25, "sand_dark", "LogEnd")
	-- firewood stacked by the west side, its cut ends out
	for _, l in { { 0.375, 0.35 }, { 0.375, 0.85 }, { 0.8, 0.6 } } do
		part(m, f * CFrame.new(-1.1, l[1], l[2]), 0.5, 0.5, 0.5, "wood_dark", "Log", "Cylinder")
		discX(m, f, -0.94, l[1], l[2], 0.25, 0.25, "sand_dark", "LogEnd")
	end
	-- mushrooms, the sign
	shroom(m, f, -0.6, 0.125, 1.25, "purple")
	shroom(m, f, 1.25, 0.125, 0.05, "pink")
	box(m, f, -1.15, 0.5, 1.2, 0.25, 0.75, 0.25, "wood_dark", "SignPost")
	box(m, f, -1.1, 0.85, 1.3, 0.75, 0.25, 0.25, "wood", "Sign")
	box(m, f, -1.07, 0.82, 1.33, 0.25, 0.25, 0.25, "wood_dark", "Carving")
	flower(m, f, 0.65, 0.125, 1.3, "pink")
	tuft(m, f, 1.15, 0.125, 1.2)
	tuft(m, f, -0.3, 0.125, 1.2)
end



-- A round nest pod on a floor at y: a woven drum with two bands, a round door facing +Z, a cone of thatch in rows and
-- a finial.
local function pod(m: Instance, f: CFrame, x: number, y: number, z: number, door: string)
	cyl(m, f, x, y + 0.375, z, 1.0, 0.75, "straw", "Pod")
	cyl(m, f, x, y + 0.125, z, 1.25, 0.25, "sand_dark", "PodBand")
	roundDoor(m, f, x, y + 0.06, z + 0.44, 0.25, door, door, "wood_dark")
	local d, yy = 1.5, y + 0.875
	local k = 0
	while d > 0.3 do
		cyl(m, f, x, yy, z, d, 0.25, if k % 2 == 0 then "straw" else "sand_dark", "Thatch")
		yy += 0.25
		d -= 0.25
		k += 1
	end
	box(m, f, x, yy + 0.06, z, 0.25, 0.25, 0.25, "wood_dark", "Finial")
end

-- Treetop Roost (4 x 4): a great tree with a round deck of planks halfway up on braces, a railing round its front
-- with lanterns on two posts, two nest pods on the deck with round doors and cones of thatch, a rope ladder up to it,
-- the crown high over them with two boughs; a tiny door in the trunk with a name board over it, roots, a basket of
-- fruit, a mailbox, mushrooms and grass at the foot.
B.roost = function(m, f)
	pad(m, f, 4, 4, 0.125, "grass_dark")
	K.tube(m, f, { Vector3.new(0, 0, 0), Vector3.new(0.05, 1.5, 0), Vector3.new(-0.05, 3.0, 0.05), Vector3.new(0, 4.75, 0) }, function(i: number): number
		return 1.0 - (i - 1) * 0.125
	end, function(): string
		return "wood_dark"
	end, "Trunk")
	for k = 0, 4 do
		local a = k / 5 * TAU + 0.4
		part(m, f * CFrame.new(math.cos(a) * 0.65, 0.2, math.sin(a) * 0.65) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -0.35), 0.75, 0.5, 0.5, "wood_dark", "Root")
	end
	roundDoor(m, f, 0, 0.0, 0.42, 0.5, "wood", "sand_dark", "wood")
	box(m, f, 0, 1.15, 0.5, 0.75, 0.25, 0.25, "wood", "NameBoard")
	-- the deck, its braces and railing
	for k = 0, 3 do
		local a = k / 4 * TAU + math.pi / 4
		span(m, f, Vector3.new(math.cos(a) * 0.4, 1.0, math.sin(a) * 0.4), Vector3.new(math.cos(a) * 1.2, 1.85, math.sin(a) * 1.2), 0.25, 0.25, "wood_dark", "Brace")
	end
	cyl(m, f, 0, 1.95, 0, 3.25, 0.25, "wood_dark", "DeckRim")
	cyl(m, f, 0, 2.0, 0, 3.0, 0.25, "wood", "Deck")
	local posts = { -50, -20, 10, 40, 70, 110, 140 }
	local pts: { Vector3 } = {}
	for _, deg in posts do
		local a = math.rad(deg)
		local p = Vector3.new(math.cos(a) * 1.4, 2.375, math.sin(a) * 1.4)
		table.insert(pts, p)
		box(m, f, p.X, p.Y, p.Z, 0.25, 0.5, 0.25, "wood_dark", "RailPost")
	end
	for i = 1, #pts - 1 do
		if posts[i] ~= 70 then
			span(m, f, pts[i] + Vector3.new(0, 0.3, 0), pts[i + 1] + Vector3.new(0, 0.3, 0), 0.25, 0.25, "wood", "Rail")
		end
	end
	for _, i in { 3, 6 } do
		lantern(m, f, pts[i].X, pts[i].Y + 0.5, pts[i].Z, true)
	end
	-- the two pods
	pod(m, f, 0.55, 2.125, 0.45, "berry_red")
	pod(m, f, -0.75, 2.125, -0.35, "blue")
	-- the rope ladder up the front
	for _, x in { 0.1, 0.6 } do
		box(m, f, x, 1.125, 1.7, 0.25, 2.25, 0.25, "sand_dark", "LadderRope")
	end
	for k = 0, 4 do
		box(m, f, 0.35, 0.3 + k * 0.4, 1.73, 0.5, 0.25, 0.25, "wood", "Rung")
	end
	-- the crown
	ball(m, f, 0, 5.6, -0.1, 3.25, "leaf_dark", "Crown")
	ball(m, f, -1.0, 5.2, 0.4, 1.75, "leaf", "Crown")
	ball(m, f, 1.0, 5.7, -0.5, 1.75, "leaf", "Crown")
	ball(m, f, 0.3, 6.3, 0.4, 1.5, "leaf", "Crown")
	ball(m, f, -0.4, 4.9, -0.9, 1.5, "leaf", "Crown")
	ball(m, f, 0.85, 5.0, 0.75, 1.25, "leaf_dark", "Crown")
	-- boughs out under the crown, a basket of fruit and a mailbox at the foot
	box(m, f, 0.9, 4.4, -0.15, 1.25, 0.25, 0.25, "wood_dark", "Bough")
	box(m, f, -0.85, 4.5, 0.35, 1.0, 0.25, 0.25, "wood_dark", "Bough")
	cyl(m, f, -1.05, 0.375, 1.4, 0.75, 0.5, "wood", "Basket")
	cyl(m, f, -1.05, 0.56, 1.4, 0.75, 0.25, "wood_dark", "BasketRim")
	ball(m, f, -1.15, 0.72, 1.35, 0.25, "orange", "Fruit")
	ball(m, f, -0.9, 0.72, 1.45, 0.25, "berry_red", "Fruit")
	box(m, f, 1.35, 0.5, 1.3, 0.25, 0.75, 0.25, "wood_dark", "MailPost")
	box(m, f, 1.35, 1.0, 1.3, 0.5, 0.25, 0.5, "green", "Mailbox")
	box(m, f, 1.38, 1.06, 1.1, 0.25, 0.25, 0.25, "berry_red", "MailFlag")
	-- the foot of the tree
	shroom(m, f, -0.85, 0.125, 0.55, "purple")
	shroom(m, f, 0.85, 0.125, -0.75, "berry_red", true)
	tuft(m, f, 1.1, 0.125, 1.05)
	tuft(m, f, -1.6, 0.125, -0.2)
	stone(m, f, 0.35, 0.125, 2.1 - 0.35, 0.5)
end

-- Spring Grotto (4 x 4): a stone arch of piled boulders with moss and ferns on its lintel, a waterfall pouring from it
-- into a round warm pool ringed with stones, steam over the water, lily pads; a bamboo pipe trickling in from the east
-- pillar, a plank deck with a bucket and towels drying on a rack, a stone lantern and stepping stones at the front.
B.grotto = function(m, f)
	pad(m, f, 4, 4, 0.125, "rock", "Floor")
	for _, s in { { -1.3, 0.3 }, { -0.4, 1.7 }, { 1.65, -0.2 }, { -1.65, -0.7 } } do
		box(m, f, s[1], 0.09, s[2], 0.5, 0.25, 0.5, "pavement", "Flagstone")
	end
	-- the arch: two pillars of boulders, a lintel, the dark cave behind
	box(m, f, 0.2, 1.0, -1.55, 1.75, 1.75, 0.25, "rock_dark", "Cave")
	ball(m, f, -0.8, 0.625, -1.1, 1.25, "rock", "Boulder")
	ball(m, f, -0.85, 1.5, -1.15, 1.0, "rock_dark", "Boulder")
	ball(m, f, 1.25, 0.75, -1.15, 1.5, "rock", "Boulder")
	ball(m, f, 1.2, 1.7, -1.2, 1.0, "rock_dark", "Boulder")
	box(m, f, 0.2, 2.3, -1.2, 2.75, 0.75, 1.0, "rock", "Lintel")
	box(m, f, 0.2, 2.75, -1.2, 2.5, 0.25, 0.75, "moss", "Moss")
	box(m, f, -0.3, 1.94, -0.62, 0.5, 0.25, 0.25, "rock_dark", "LintelStone")
	box(m, f, 1.0, 1.94, -0.62, 0.75, 0.25, 0.25, "rock_dark", "LintelStone")
	for k = 0, 4 do
		local a = k / 5 * TAU
		part(m, f * CFrame.new(0.2 + (k - 2) * 0.55, 3.0, -1.2 + math.sin(a) * 0.15) * CFrame.Angles(0, a, if k % 2 == 0 then 0.6 else -0.6), 0.75, 0.25, 0.25, if k % 2 == 0 then "leaf" else "leaf_dark", "Fern")
	end
	for _, v in { { -0.6, 2.0 }, { 1.3, 1.75 } } do
		box(m, f, v[1], v[2] - 0.25, -0.67, 0.25, 0.75, 0.25, "leaf", "Vine")
	end
	-- the waterfall (streaks run down it) and its foam
	box(m, f, 0.2, 1.05, -0.65, 0.75, 1.75, 0.25, "shallow", "Falls"):SetAttribute("PixelWater", 4)
	cyl(m, f, 0.2, 0.3, -0.45, 1.0, 0.25, "foam", "Ripple"):SetAttribute("PixelWater", 3)
	-- the pool, its stones, steam and lily pads
	cyl(m, f, 0.2, 0.19, 0.25, 2.75, 0.25, "rock_dark", "PoolRim")
	cyl(m, f, 0.2, 0.22, 0.25, 2.25, 0.25, "shallow", "Pool"):SetAttribute("PixelWater", 2)
	for k = 0, 9 do
		local a = math.rad(-30 + k * 22)
		ball(m, f, 0.2 + math.cos(a) * 1.3, 0.3, 0.25 + math.sin(a) * 1.3, 0.5, ({ "rock", "pavement", "rock_dark" })[k % 3 + 1], "RimStone")
	end
	for _, s in { { -0.35, 0.65 }, { 0.7, 0.2 }, { 0.15, 1.0 } } do
		ball(m, f, s[1], 0.65, s[2], 0.25, "white", "Steam")
		ball(m, f, s[1] + 0.12, 0.9, s[2] - 0.06, 0.25, "white", "Steam")
		ball(m, f, s[1] + 0.03, 1.15, s[2] - 0.12, 0.25, "white", "Steam")
	end
	for _, l in { { -0.55, 0.15 }, { 0.75, 0.85 } } do
		cyl(m, f, l[1], 0.3, l[2], 0.5, 0.25, "leaf", "LilyPad")
	end
	ball(m, f, -0.5, 0.45, 0.2, 0.25, "pink", "Lily")
	-- the bamboo pipe from the east pillar and its trickle
	span(m, f, Vector3.new(1.45, 1.05, -0.5), Vector3.new(1.0, 0.95, -0.2), 0.25, 0.25, "bamboo", "Bamboo")
	box(m, f, 0.95, 0.65, -0.15, 0.25, 0.5, 0.25, "shallow", "Trickle"):SetAttribute("PixelWater", 4)
	-- the deck: planks, a bucket, towels on a rack
	box(m, f, 1.35, 0.25, 1.35, 1.25, 0.25, 1.25, "wood", "Deck")
	for _, x in { 1.1, 1.6 } do
		box(m, f, x, 0.28, 1.35, 0.25, 0.25, 1.0, "wood_dark", "Plank")
	end
	for _, z in { 0.95, 1.55 } do
		box(m, f, 1.85, 0.875, z, 0.25, 1.0, 0.25, "wood_dark", "RackPost")
	end
	box(m, f, 1.82, 1.3, 1.25, 0.25, 0.25, 0.75, "wood_dark", "RackBar")
	box(m, f, 1.88, 0.95, 1.12, 0.25, 0.5, 0.25, "pink", "Towel")
	box(m, f, 1.88, 1.0, 1.4, 0.25, 0.5, 0.25, "white", "Towel")
	cyl(m, f, 1.05, 0.625, 1.7, 0.5, 0.5, "wood", "Bucket")
	cyl(m, f, 1.05, 0.69, 1.7, 0.5, 0.25, "wood_dark", "BucketBand")
	-- the stone lantern and the stepping stones
	box(m, f, -1.4, 0.25, 1.4, 0.75, 0.25, 0.75, "pavement", "LanternBase")
	box(m, f, -1.4, 0.625, 1.4, 0.25, 0.5, 0.25, "pavement", "LanternPost")
	box(m, f, -1.4, 1.125, 1.4, 0.5, 0.5, 0.5, "pavement", "LanternBox")
	box(m, f, -1.4, 1.125, 1.565, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, -1.235, 1.1, 1.4, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, -1.4, 1.5, 1.4, 0.75, 0.25, 0.75, "rock_dark", "LanternRoof")
	box(m, f, -1.4, 1.69, 1.4, 0.25, 0.25, 0.25, "rock_dark", "LanternTop")
	for _, s in { { -0.6, 1.72 }, { 0.15, 1.75 } } do
		stone(m, f, s[1], 0.125, s[2], 0.5)
	end
	tuft(m, f, -1.65, 0.125, 0.75)
	tuft(m, f, 1.75, 0.125, 0.45)
end

-- Driftling Palace (5 x 5): a pink hall on a cream plinth under a purple dome with a gold crown, a band and a spire;
-- round doors of three sizes in front, a balcony over the big one, windows with shutters and flower boxes; three
-- white towers with blue and teal onion domes, flags on top and banners down their sides; a moat along the front with
-- a white bridge, two gold lamps, topiaries in planters with flowers at the front corners.
B.palace = function(m, f)
	-- the plinth and the moat
	box(m, f, 0, 0.125, -0.375, 5, 0.25, 4.25, "cream", "Plinth")
	box(m, f, 0, 0.06, 2.0, 5, 0.25, 0.5, "shallow", "Moat"):SetAttribute("PixelWater", 2)
	box(m, f, 0, 0.125, 2.375, 5, 0.25, 0.25, "pavement", "MoatLip")
	box(m, f, 0, 0.31, 2.0, 1.25, 0.25, 0.75, "white", "Bridge")
	for _, x in { -0.5, 0.5 } do
		box(m, f, x, 0.56, 2.0, 0.25, 0.25, 0.75, "pink", "BridgeRail")
	end
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 0.625, 1.6, 0.25, 0.75, 0.25, "gold", "LampPost")
		box(m, f, x, 1.125, 1.6, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
		box(m, f, x, 1.375, 1.6, 0.5, 0.25, 0.5, "gold", "LampCap")
	end
	-- the hall
	box(m, f, 0, 1.25, -0.5, 2.75, 2.0, 2.5, "pink", "Hall")
	box(m, f, 0, 0.375, -0.5, 3.0, 0.25, 2.75, "white", "HallBase")
	box(m, f, 0, 2.25, -0.5, 3.0, 0.25, 2.75, "white", "Cornice")
	for k = 0, 4 do
		ball(m, f, -1.0 + k * 0.5, 2.06, 0.85, 0.25, "white", "Scallop")
	end
	-- the dome, its drum, band, crown and spire
	cyl(m, f, 0, 2.5, -0.5, 2.25, 0.25, "white", "Drum")
	ball(m, f, 0, 2.6, -0.5, 2.5, "purple", "Dome")
	cyl(m, f, 0, 2.75, -0.5, 2.5, 0.25, "gold", "DomeBand")
	cyl(m, f, 0, 3.9, -0.5, 0.75, 0.25, "gold", "Crown")
	for k = 0, 4 do
		local a = k / 5 * TAU + math.pi / 2
		ball(m, f, math.cos(a) * 0.3, 4.12, -0.5 + math.sin(a) * 0.3, 0.25, "gold", "CrownPoint")
	end
	ball(m, f, 0, 3.97, -0.12, 0.25, "berry_red", "Gem")
	box(m, f, 0, 4.25, -0.5, 0.25, 0.5, 0.25, "gold", "Spire")
	ball(m, f, 0, 4.6, -0.5, 0.25, "gold", "Finial")
	-- the doors of three sizes, the balcony, the windows
	roundDoor(m, f, 0, 0.25, 0.75, 1.25, "wood", "wood_dark", "gold")
	roundDoor(m, f, -0.9, 0.25, 0.75, 0.5, "berry_red", "brick", "white")
	roundDoor(m, f, 0.95, 0.25, 0.75, 0.25, "blue", "blue", "white")
	box(m, f, 0, 0.35, 1.15, 1.25, 0.25, 0.75, "pavement", "Step")
	box(m, f, 0, 1.94, 1.0, 1.5, 0.25, 0.5, "white", "Balcony")
	for k = 0, 4 do
		box(m, f, -0.6 + k * 0.3, 2.19, 1.13, 0.25, 0.25, 0.25, "white", "Baluster")
	end
	window(m, f, -0.95, 1.6, 0.75, 0.5, 0.5, "white", "purple", { "pink", "yellow" })
	window(m, f, 0.95, 1.6, 0.75, 0.5, 0.5, "white", "purple", { "yellow", "pink" })
	local side = east(f, 1.375)
	window(m, side, 0.0, 1.35, 0, 0.5, 0.75, "white", "purple", { "pink", "white", "pink" })
	window(m, side, 1.25, 1.35, 0, 0.5, 0.75, "white", "purple")
	-- the towers
	local function tower(x: number, z: number, h: number, dome: string, faceX: boolean)
		cyl(m, f, x, 0.25 + h / 2, z, 1.0, h, "white", "Tower")
		cyl(m, f, x, 0.375, z, 1.25, 0.25, "pink", "TowerBand")
		cyl(m, f, x, 0.25 + h, z, 1.25, 0.25, "pink", "TowerBand")
		ball(m, f, x, 0.5 + h + 0.4, z, 1.25, dome, "OnionDome")
		box(m, f, x, 0.5 + h + 1.1, z, 0.25, 0.5, 0.25, "gold", "FlagPole")
		wedge(m, f, x + 0.35, 0.5 + h + 1.2, z, 0.5, 0.25, 0.25, "berry_red", math.pi / 2, "Flag")
		if faceX then
			box(m, f, x + 0.47, 0.25 + h * 0.65, z, 0.25, 0.5, 0.25, "window", "TowerWindow")
			box(m, f, x + 0.5, 0.25 + h * 0.35, z, 0.25, 0.75, 0.5, "berry_red", "FlagBanner")
		else
			box(m, f, x, 0.25 + h * 0.65, z + 0.47, 0.25, 0.5, 0.25, "window", "TowerWindow")
			box(m, f, x, 0.25 + h * 0.35, z + 0.5, 0.5, 0.75, 0.25, "berry_red", "FlagBanner")
		end
	end
	tower(-1.85, 0.8, 2.25, "blue", false)
	tower(1.85, 0.8, 2.25, "blue", false)
	tower(1.85, -1.6, 2.75, "teal", true)
	-- the garden: topiaries in planters with flowers round them
	for _, x in { -1.85, 1.85 } do
		box(m, f, x, 0.44, 1.6, 0.5, 0.25, 0.5, "pot", "Planter")
		ball(m, f, x, 0.9, 1.6, 0.75, "leaf", "Topiary")
		ball(m, f, x - 0.35, 0.4, 1.55, 0.25, "pink", "Bloom")
		ball(m, f, x + 0.35, 0.4, 1.65, 0.25, "yellow", "Bloom")
	end

end

-- The frame on a round wall of radius r round (cx, cz), facing out at angle a (0 is +X, pi / 2 is +Z): its +Z points
-- out, its z = 0 is on the wall.
local function around(f: CFrame, cx: number, cz: number, r: number, a: number): CFrame
	return f * CFrame.new(cx + math.cos(a) * r, 0, cz + math.sin(a) * r) * CFrame.Angles(0, math.pi / 2 - a, 0)
end

-- A lifebuoy hung on a wall whose face is at z (frame g): a red ring with four white bands.
local function lifebuoy(m: Instance, g: CFrame, x: number, y: number, z: number)
	discZ(m, g, x, y, z + 0.06, 0.75, 0.25, "berry_red", "Lifebuoy")
	discZ(m, g, x, y, z + 0.09, 0.25, 0.25, "wood", "LifebuoyHole")
	for _, d in { { 0.25, 0 }, { -0.25, 0 }, { 0, 0.25 }, { 0, -0.25 } } do
		box(m, g, x + d[1], y + d[2], z + 0.1, 0.25, 0.25, 0.25, "white", "LifebuoyBand")
	end
end

-- Lighthouse Loft (5 x 5): a red and white striped tower of bunks on a ring of rocks, round windows climbing it toward
-- the camera, a round door with a step and a coil of rope, a gallery with a railing, the lamp lit inside its cage under
-- a red dome; beside it a cream cottage with a teal shingle roof, a chimney, a door, windows with shutters and a flower
-- box, a lifebuoy on its east wall; a stack of crates, blankets on a washing line, a sandy path and flowers.
B.loft = function(m, f)
	pad(m, f, 5, 5, 0.125, "grass_dark")
	local tx, tz = -0.6, -0.6
	-- the rocks and the tower
	cyl(m, f, tx, 0.31, tz, 2.75, 0.5, "rock", "Base")
	for k, b in { { 30, 0.75 }, { 75, 0.5 }, { 140, 0.75 }, { 330, 0.5 } } do
		local a = math.rad(b[1])
		ball(m, f, tx + math.cos(a) * 1.35, 0.25, tz + math.sin(a) * 1.35, b[2], if k % 2 == 0 then "rock_dark" else "rock", "Rock")
	end
	for i = 0, 4 do
		cyl(m, f, tx, 0.94 + i * 0.75, tz, 2.25, 0.75, if i % 2 == 0 then "white" else "berry_red", "Tower")
	end
	cyl(m, f, tx, 4.56, tz, 2.0, 0.5, "white", "Tower")
	for k, w in { { 75, 1.75 }, { 25, 2.5 }, { 70, 3.25 }, { 20, 4.0 } } do
		local g = around(f, tx, tz, 1.125, math.rad(w[1]))
		porthole(m, g, 0, w[2], 0, 0.5, if k % 2 == 0 then "slate" else "white")
	end
	roundDoor(m, f, tx, 0.56, tz + 1.125, 0.75, "teal", "water", "white")
	box(m, f, tx, 0.56, tz + 1.4, 1.0, 0.25, 0.5, "rock", "Step")
	cyl(m, f, tx - 0.85, 0.69, tz + 1.35, 0.75, 0.25, "sand_dark", "Rope")
	cyl(m, f, tx - 0.85, 0.75, tz + 1.35, 0.25, 0.25, "wood_dark", "RopeCore")
	-- the gallery and its railing
	cyl(m, f, tx, 4.94, tz, 2.75, 0.25, "steel_dark", "Gallery")
	local rail: { Vector3 } = {}
	for k = 0, 9 do
		local a = k / 10 * TAU
		local p = Vector3.new(tx + math.cos(a) * 1.25, 5.25, tz + math.sin(a) * 1.25)
		table.insert(rail, p)
		box(m, f, p.X, p.Y, p.Z, 0.25, 0.5, 0.25, "steel_dark", "RailPost")
	end
	for k = 1, 10 do
		local a, b = rail[k], rail[k % 10 + 1]
		span(m, f, a + Vector3.new(0, 0.25, 0), b + Vector3.new(0, 0.25, 0), 0.25, 0.25, "steel_dark", "Rail")
	end
	-- the lamp in its cage, the cap and the dome
	cyl(m, f, tx, 5.44, tz, 1.25, 0.75, "yellow", "Lamp").Material = Enum.Material.Neon
	for k = 0, 5 do
		local a = k / 6 * TAU + 0.3
		box(m, f, tx + math.cos(a) * 0.6, 5.44, tz + math.sin(a) * 0.6, 0.25, 0.75, 0.25, "steel_dark", "Mullion")
	end
	cyl(m, f, tx, 5.94, tz, 1.75, 0.25, "steel_dark", "LampCap")
	ball(m, f, tx, 6.06, tz, 1.25, "berry_red", "Dome")
	ball(m, f, tx, 6.75, tz, 0.25, "gold", "Vent")
	-- the cottage
	local cx, cz = 1.1, 0.8
	box(m, f, cx, 0.875, cz, 2.0, 1.5, 2.0, "cream", "Walls")
	box(m, f, cx, 0.25, cz, 2.25, 0.25, 2.25, "rock", "Band")
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		box(m, f, cx + c[1] * 1.03, 0.75, cz + c[2] * 1.03, 0.25, 1.25, 0.25, "wood_dark", "Corner")
	end
	gable(m, f * CFrame.new(cx, 0, cz), 1.625, 2.0, 2.0, 1.0, 0.25, "teal", "water", "wood_dark")
	chimney(m, f, cx + 0.6, 2.0, cz - 0.55, 0.75, "brick")
	roundDoor(m, f, cx + 0.45, 0.375, cz + 1.0, 0.75, "teal", "water", "wood_dark")
	box(m, f, cx + 0.45, 0.31, cz + 1.25, 0.75, 0.25, 0.25, "rock", "Step")
	window(m, f, cx - 0.45, 1.2, cz + 1.0, 0.5, 0.5, "wood_dark", "teal", { "pink", "yellow" })
	local side = east(f, cx + 1.0)
	window(m, side, -(cz + 0.35), 1.2, 0, 0.5, 0.5, "wood_dark", "teal")
	lifebuoy(m, side, -(cz - 0.4), 1.1, 0)
	-- crates, a barrel, the washing line, flowers, the path
	box(m, f, -0.25, 0.375, 1.4, 0.5, 0.5, 0.5, "wood", "Crate")
	box(m, f, -0.25, 0.375, 1.9, 0.5, 0.5, 0.5, "desk", "Crate")
	box(m, f, -0.25, 0.875, 1.65, 0.5, 0.5, 0.5, "wood_dark", "Crate")
	for _, x in { -2.2, -0.9 } do
		box(m, f, x, 0.75, 1.95, 0.25, 1.25, 0.25, "wood_dark", "LinePost")

	end
	box(m, f, -1.55, 1.19, 1.92, 1.25, 0.25, 0.25, "cream", "Line")
	for k, c in { "pink", "blue", "yellow" } do
		box(m, f, -1.95 + (k - 1) * 0.4, 0.94, 1.98, 0.25, 0.5, 0.25, c, "Blanket")
	end
	for _, s in { { -0.55, 1.15 }, { -0.4, 1.8 }, { 0.35, 2.2 } } do
		stone(m, f, s[1], 0.125, s[2], 0.5, "sand")
	end
	for _, p in { { x = -2.2, z = 0.6, c = "pink" }, { x = 0.6, z = 2.2, c = "yellow" }, { x = 2.3, z = 2.15, c = "white" } } do
		flower(m, f, p.x, 0.125, p.z, p.c)
	end
end

-- Coral Manor (5 x 5): a pink and coral house in a U round a courtyard; a white-rimmed warm pool in the middle with a
-- shell fountain trickling into it, steam, a lounger either side and a parasol; flat roofs with round white scallops
-- along their edges, round doors of three sizes and a balcony on the back wing, windows with teal shutters and flower
-- boxes on the walls that face the camera; coral towers with pink domes at the back right and front left, a low white
-- wall in front with shell-topped gate posts, coral growing on it, palms in pots by the gate.
B.coralmanor = function(m, f)
	pad(m, f, 5, 5, 0.125, "sand", "Footing")
	box(m, f, 0, 0.06, 0.375, 2.25, 0.25, 2.75, "cherry", "Court")
	-- the back wing
	box(m, f, 0.25, 1.125, -1.625, 4.0, 2.0, 1.25, "coral", "BackWing")
	box(m, f, 0.25, 0.25, -1.625, 4.25, 0.25, 1.5, "white", "Band")
	box(m, f, 0.25, 2.19, -1.625, 4.25, 0.25, 1.5, "pink", "Roof")
	for k = 0, 7 do
		ball(m, f, -1.5 + k * 0.5, 2.4, -0.94, 0.5, if k % 2 == 0 then "white" else "coral", "Scallop")
	end
	-- the side wings
	for _, s in { -1, 1 } do
		local x = s * 1.6
		box(m, f, x, 0.875, 0.25, 1.0, 1.5, 2.5, "pink", "Wing")
		box(m, f, x, 0.31, 0.375, 1.25, 0.25, 2.75, "white", "Band")
		box(m, f, x, 1.69, 0.25, 1.25, 0.25, 2.75, "coral", "Roof")
		for k = 0, 2 do
			ball(m, f, x, 1.88, -0.5 + k * 0.75, 0.5, if k % 2 == 0 then "white" else "pink", "Scallop")
		end
		if s > 0 then
			window(m, f, x, 1.0, 1.5, 0.5, 0.5, "white", "teal", { "pink", "yellow" })
		end
	end
	-- the walls facing the camera: the left wing's court side, the right wing's east side, the back wing's front
	local lw = east(f, -1.1)
	window(m, lw, 0.5, 1.0, 0, 0.5, 0.5, "white", "teal")
	roundDoor(m, lw, -0.5, 0.125, 0, 0.5, "teal", "water", "white")
	local rw = east(f, 2.1)
	window(m, rw, -0.85, 1.0, 0, 0.5, 0.5, "white", "teal", { "white", "pink" })
	window(m, rw, 0.6, 1.0, 0, 0.5, 0.5, "white", "teal", { "pink", "white" })
	for i, x in { -1.0, 0.25, 1.5 } do
		local dia = ({ 0.5, 0.75, 0.25 })[i]
		roundDoor(m, f, x, 0.125, -1.0, dia, ({ "teal", "wood", "blue" })[i], ({ "water", "wood_dark", "jeans" })[i], "white")
		window(m, f, x, 1.7, -1.0, 0.5, 0.5, "white", "teal", if i == 2 then nil else { "pink", "yellow" })
	end
	box(m, f, 0.25, 1.375, -0.75, 1.5, 0.25, 0.5, "white", "Balcony")
	for k = 0, 4 do
		box(m, f, -0.35 + k * 0.3, 1.625, -0.62, 0.25, 0.25, 0.25, "white", "Baluster")
	end
	-- the towers
	for k, t in { { 1.85, -1.85, 3.0 }, { -1.85, 1.85, 2.25 } } do
		cyl(m, f, t[1], 0.125 + t[3] / 2, t[2], 1.0, t[3], "coral", "Tower")
		cyl(m, f, t[1], t[3] - 0.06, t[2], 1.25, 0.25, "white", "TowerBand")
		ball(m, f, t[1], t[3] + 0.4, t[2], 1.0, "pink", "TowerTop")
		ball(m, f, t[1], t[3] + 0.94, t[2], 0.25, "gold", "Finial")
		if k == 1 then
			box(m, f, t[1] + 0.47, t[3] * 0.6, t[2], 0.25, 0.5, 0.25, "window", "TowerWindow")
		else
			box(m, f, t[1], t[3] * 0.6, t[2] + 0.47, 0.25, 0.5, 0.25, "window", "TowerWindow")
		end
	end
	-- the pool, the fountain, steam, loungers, the parasol
	box(m, f, 0, 0.25, 0.35, 1.25, 0.25, 1.75, "white", "PoolRim")
	box(m, f, 0, 0.31, 0.35, 0.75, 0.25, 1.25, "shallow", "Pool"):SetAttribute("PixelWater", 2)
	for k = 0, 2 do
		part(m, f * CFrame.new(-0.25 + k * 0.25, 0.6, -0.35) * CFrame.Angles(0, 0, (k - 1) * 0.5), 0.25, 0.75, 0.25, if k == 1 then "pink" else "cream", "Shell")
	end
	box(m, f, 0.03, 0.5, -0.12, 0.25, 0.5, 0.25, "shallow", "Spout"):SetAttribute("PixelWater", 4)
	ball(m, f, -0.2, 0.7, 0.45, 0.25, "white", "Steam")
	ball(m, f, -0.1, 0.95, 0.4, 0.25, "white", "Steam")
	ball(m, f, 0.3, 0.75, 0.65, 0.25, "white", "Steam")
	for _, x in { -0.85, 0.85 } do
		box(m, f, x, 0.35, 0.45, 0.5, 0.25, 1.0, "white", "Lounger")
		part(m, f * CFrame.new(x, 0.5, -0.05) * CFrame.Angles(-0.6, 0, 0), 0.5, 0.5, 0.25, "white", "LoungerBack")
		box(m, f, x, 0.37, 0.55, 0.25, 0.25, 0.25, if x < 0 then "teal" else "yellow", "Towel")
	end
	box(m, f, 0.95, 0.94, 1.15, 0.25, 1.5, 0.25, "white", "ParasolPole")
	cyl(m, f, 0.95, 1.69, 1.15, 1.25, 0.25, "teal", "Parasol")
	cyl(m, f, 0.95, 1.81, 1.15, 0.75, 0.25, "white", "Parasol")
	-- the front wall, the gate, coral and potted palms
	for _, s in { -1, 1 } do
		box(m, f, s * 1.75, 0.5, 2.25, 1.0, 0.75, 0.25, "white", "FrontWall")
		box(m, f, s * 0.95, 0.625, 2.2, 0.5, 1.0, 0.5, "white", "GatePost")
		ball(m, f, s * 0.95, 1.25, 2.2, 0.5, "cream", "Shell")
		box(m, f, s * 0.95, 1.31, 2.35, 0.25, 0.25, 0.25, "pink", "ShellLip")
		box(m, f, s * 2.0, 1.0, 2.22, 0.25, 0.25, 0.25, "coral", "Coral")
		box(m, f, s * 1.8, 1.06, 2.28, 0.25, 0.5, 0.25, "coral", "Coral")
		box(m, f, s * 1.55, 0.94, 2.2, 0.25, 0.25, 0.25, "pink", "Coral")
		box(m, f, s * 0.95, 0.44, 1.65, 0.5, 0.5, 0.5, "pot", "PalmPot")
		box(m, f, s * 0.95, 0.94, 1.65, 0.25, 0.5, 0.25, "wood", "PalmTrunk")
		for k = 0, 3 do
			local a = k / 4 * TAU + 0.4
			part(m, f * CFrame.new(s * 0.95 + math.cos(a) * 0.3, 1.25, 1.65 + math.sin(a) * 0.3) * CFrame.Angles(0, -a, -0.5), 0.75, 0.25, 0.25, if k % 2 == 0 then "leaf" else "leaf_dark", "PalmLeaf")
		end
	end
	box(m, f, 0, 0.19, 2.2, 1.25, 0.25, 0.5, "pavement", "GateStep")
end

-- A cone of rings narrowing up from y (a tower's roof), a gold finial and a flag on top; returns the top.
local function cone(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, band: string?): number
	local d, yy, k = dia, y, 0
	while d > 0.3 do
		cyl(m, f, x, yy + 0.125, z, d, 0.25, if band and k % 2 == 1 then band else color, "Spire")
		yy += 0.25
		d -= 0.25
		k += 1
	end
	ball(m, f, x, yy + 0.1, z, 0.25, "gold", "Finial")
	return yy + 0.25
end

-- A flag on a pole standing on y at (x, z), flying east.
local function flag(m: Instance, f: CFrame, x: number, y: number, z: number, color: string)
	box(m, f, x, y + 0.375, z, 0.25, 0.75, 0.25, "gold", "FlagPole")
	wedge(m, f, x + 0.35, y + 0.6, z, 0.5, 0.25, 0.25, color, math.pi / 2, "Flag")
end

-- A puff of cloud: a big ball and two smaller ones beside it, white and pale blue.
local function cloud(m: Instance, f: CFrame, x: number, y: number, z: number, s: number)
	ball(m, f, x, y, z, s, "white", "Cloud")
	ball(m, f, x + s * 0.45, y - s * 0.15, z + s * 0.2, s * 0.6, "ice", "Cloud")
	ball(m, f, x - s * 0.45, y - s * 0.1, z + s * 0.15, s * 0.6, "snow", "Cloud")
end

-- Cloud Keep (6 x 5): a white keep with battlements, a pale blue band and a blue cornice, a turret on its roof with a
-- blue cone and a flag; two round side towers with ice-blue bands, blue cones and flags, joined to the keep by stone
-- bridges with blue rails; puffs of cloud round the towers' middles and the keep's foot; a big round door and a small
-- one in front with lanterns by them, windows with blue shutters and flower boxes, a balcony with a banner under it, a
-- banner down the east wall, a little rainbow over a cloud in the front-left corner.
B.cloudkeep = function(m, f)
	pad(m, f, 6, 5, 0.125, "grass_dark")
	box(m, f, 0, 0.06, 0.6, 2.0, 0.25, 3.75, "pavement", "Court")
	-- the keep
	local kz = -0.6
	box(m, f, 0, 1.625, kz, 2.5, 3.0, 2.5, "white", "Keep")
	box(m, f, 0, 0.25, kz, 2.75, 0.25, 2.75, "slate", "Band")
	box(m, f, 0, 1.69, kz, 2.75, 0.25, 2.75, "ice", "Band")
	box(m, f, 0, 3.19, kz, 2.75, 0.25, 2.75, "blue", "Cornice")
	for _, t in { -0.75, 0, 0.75 } do
		box(m, f, t, 3.5, kz + 1.2, 0.5, 0.5, 0.25, "white", "Merlon")
		box(m, f, 1.2, 3.5, kz - t, 0.25, 0.5, 0.5, "white", "Merlon")
		box(m, f, t, 3.5, kz - 1.2, 0.5, 0.5, 0.25, "white", "Merlon")
		box(m, f, -1.2, 3.5, kz + t, 0.25, 0.5, 0.5, "white", "Merlon")
	end
	-- the turret on the roof
	cyl(m, f, 0.2, 3.94, kz - 0.2, 1.25, 1.25, "white", "Turret")
	cyl(m, f, 0.2, 4.5, kz - 0.2, 1.5, 0.25, "ice", "TurretBand")
	local top = cone(m, f, 0.2, 4.56, kz - 0.2, 1.5, "blue", "jeans")
	flag(m, f, 0.2, top, kz - 0.2, "yellow")
	box(m, f, 0.2, 3.94, kz + 0.47, 0.25, 0.5, 0.25, "window", "TurretWindow")
	-- the doors, the lanterns, the windows, the balcony and the banners
	roundDoor(m, f, -0.35, 0.25, kz + 1.25, 1.0, "blue", "jeans", "ice")
	roundDoor(m, f, 0.75, 0.25, kz + 1.25, 0.5, "blue", "jeans", "ice")
	box(m, f, -0.35, 0.31, kz + 1.6, 1.25, 0.25, 0.5, "slate", "Step")
	for _, x in { -1.05, 0.35 } do
		box(m, f, x, 1.6, kz + 1.45, 0.25, 0.25, 0.5, "steel_dark", "Bracket")
		lantern(m, f, x + 0.03, 1.25, kz + 1.7, true)
	end
	window(m, f, -0.65, 2.4, kz + 1.25, 0.5, 0.5, "white", "blue", { "white", "blue" })
	window(m, f, 0.6, 2.4, kz + 1.25, 0.5, 0.5, "white", "blue")
	box(m, f, 0.62, 1.94, kz + 1.6, 1.0, 0.25, 0.5, "white", "Balcony")
	box(m, f, 0.6, 1.56, kz + 1.6, 0.5, 0.5, 0.25, "blue", "FlagBanner")
	local side = east(f, 1.25)
	window(m, side, -kz - 0.55, 2.4, 0, 0.5, 0.5, "white", "blue", { "white", "blue" })
	box(m, f, 1.31, 1.25, kz - 0.6, 0.25, 1.0, 0.5, "blue", "FlagBanner")
	box(m, f, 1.34, 1.75, kz - 0.6, 0.25, 0.25, 0.75, "gold", "BannerRod")
	-- the side towers and their bridges
	for _, s in { -1, 1 } do
		local x, z = s * 2.2, -0.4
		cyl(m, f, x, 1.875, z, 1.25, 3.5, "white", "Tower")
		for _, y in { 0.31, 1.75, 3.5 } do
			cyl(m, f, x, y, z, 1.5, 0.25, "ice", "TowerBand")
		end
		local tt = cone(m, f, x, 3.625, z, 1.5, "blue", "jeans")
		flag(m, f, x, tt, z, "berry_red")
		for _, w in { { 60, 1.1 }, { 30, 2.6 } } do
			local g = around(f, x, z, 0.625, math.rad(if s > 0 then w[1] - 30 else w[1] + 20))
			box(m, g, 0, w[2], 0, 0.25, 0.5, 0.25, "window", "TowerWindow")
			box(m, g, 0, w[2] + 0.31, 0.03, 0.5, 0.25, 0.25, "blue", "WindowHood")
		end
		box(m, f, s * 1.6, 2.69, z, 0.75, 0.25, 0.75, "white", "Bridge")
		box(m, f, s * 1.6, 2.94, z + 0.31, 0.75, 0.25, 0.25, "blue", "BridgeRail")
	end
	-- clouds round the towers and the keep's foot
	for _, s in { -1, 1 } do
		cloud(m, f, s * 2.2 + 0.2, 1.45, 0.05, 0.75)
		cloud(m, f, s * 2.2 - 0.25 * s, 1.25, -0.85, 0.75)
	end
	cloud(m, f, -1.5, 0.45, 0.9, 0.75)
	cloud(m, f, 1.6, 0.4, 1.1, 0.75)
	cloud(m, f, 1.0, 3.35, -1.85, 1.0)
	-- the rainbow over its cloud
	local bows = { "berry_red", "yellow", "blue" }
	for b, c in bows do
		local r = 0.9 - (b - 1) * 0.25
		for k = 0, 4 do
			local a = math.pi * (k + 0.5) / 5
			part(m, f * CFrame.new(-1.95 + math.cos(a) * r, 0.3 + math.sin(a) * r, 1.95) * CFrame.Angles(0, 0, a + math.pi / 2), 0.5, 0.25, 0.25, c, "Rainbow")
		end
	end
	cloud(m, f, -1.25, 0.3, 2.0, 0.5)
	cloud(m, f, -2.6, 0.3, 2.0, 0.5)
end

-- Driftling Citadel (6 x 6): a cream wall with battlements round a paved court, arrow slits on its outer faces; a
-- gatehouse in front with an arched gate, the portcullis up, a gold crest and banners either side; three corner
-- towers with crenellated tops, teal cones and flags (the back-left corner a low flower bed); the great hall in the
-- middle with a gold band under a teal dome with a gold spire, a porch of two columns under a teal gable, round doors,
-- windows with flower boxes, a banner down its east side; a fountain in the court, lamps by the gate, garden beds with
-- little trees and flowers, a bench.
B.citadel = function(m, f)
	pad(m, f, 6, 6, 0.25, "rock", "Footing")
	box(m, f, 0, 0.19, 0.25, 4.75, 0.25, 4.5, "pavement", "Court")
	-- the walls, with battlements; the back-left corner left open and low
	local function wall(x: number, z: number, w: number, d: number)
		box(m, f, x, 0.875, z, w, 1.25, d, "cream", "Wall")
		local long = math.max(w, d)
		local n = math.floor(long / 0.5)
		for k = 0, n - 1, 2 do
			local t = -long / 2 + 0.25 + k * 0.5
			box(m, f, x + (if w > d then t else 0), 1.625, z + (if w > d then 0 else t), 0.25, 0.25, 0.25, "sand", "Merlon")
		end
	end
	wall(0.25, -2.75, 4.5, 0.5)
	wall(-2.75, 0.25, 0.5, 4.5)
	wall(2.7, 0, 0.5, 4.5)
	wall(-1.75, 2.7, 1.5, 0.5)
	wall(1.75, 2.7, 1.5, 0.5)
	for _, t in { -1.6, 1.6 } do
		box(m, f, t, 1.0, 2.855, 0.25, 0.5, 0.25, "black", "Slit")
		box(m, f, 2.855, 1.0, t * 0.625, 0.25, 0.5, 0.25, "black", "Slit")
	end
	-- the gatehouse
	box(m, f, 0, 1.125, 2.5, 2.0, 1.75, 0.75, "cream", "Gatehouse")
	for k = 0, 3 do
		box(m, f, -0.75 + k * 0.5, 2.125, 2.75, 0.25, 0.25, 0.25, "sand", "Merlon")
	end
	discZ(m, f, 0, 1.0, 2.8, 1.0, 0.25, "black", "Arch")
	box(m, f, 0, 0.625, 2.8, 1.0, 0.75, 0.25, "black", "Gate")
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 1.25, 2.85, 0.25, 0.5, 0.25, "steel_dark", "Portcullis")
	end
	box(m, f, 0, 1.31, 2.87, 0.75, 0.25, 0.25, "steel_dark", "Portcullis")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.7, 1.3, 2.86, 0.25, 0.75, 0.25, "berry_red", "FlagBanner")
		box(m, f, s * 0.75, 1.75, 2.88, 0.25, 0.25, 0.25, "gold", "BannerRod")
	end
	discZ(m, f, 0, 1.75, 2.84, 0.5, 0.25, "gold", "Crest")
	discZ(m, f, 0, 1.75, 2.87, 0.25, 0.25, "berry_red", "Crest")
	-- the corner towers
	for _, c in { { -2.35, 2.35 }, { 2.35, 2.35 }, { 2.35, -2.35 } } do
		cyl(m, f, c[1], 1.375, c[2], 1.0, 2.25, "cream", "Tower")
		cyl(m, f, c[1], 0.375, c[2], 1.25, 0.25, "rock", "TowerBase")
		cyl(m, f, c[1], 2.625, c[2], 1.25, 0.25, "sand", "TowerTop")
		for k = 0, 3 do
			local a = k / 4 * TAU + math.pi / 4
			box(m, f, c[1] + math.cos(a) * 0.45, 2.875, c[2] + math.sin(a) * 0.45, 0.25, 0.25, 0.25, "sand", "Merlon")
		end
		local t = cone(m, f, c[1], 2.75, c[2], 1.0, "teal")
		flag(m, f, c[1], t, c[2], "berry_red")
		box(m, around(f, c[1], c[2], 0.5, math.pi / 4), 0, 1.75, 0, 0.25, 0.5, 0.25, "black", "Slit")
	end
	-- the back-left corner's low flower bed
	box(m, f, -2.6, 0.31, -2.6, 0.75, 0.25, 0.75, "wood_dark", "Bed")
	for k, c in { "pink", "yellow", "white" } do
		ball(m, f, -2.8 + k * 0.15, 0.37, -2.75 + k * 0.12, 0.25, c, "Bloom")
	end
	-- the great hall, its dome and spire
	local hz = -1.4
	box(m, f, 0, 1.5, hz, 3.0, 2.5, 2.25, "white", "Hall")
	box(m, f, 0, 0.375, hz, 3.25, 0.25, 2.5, "sand", "Band")
	box(m, f, 0, 2.44, hz, 3.25, 0.25, 2.5, "gold", "Band")
	cyl(m, f, 0, 3.0, hz, 2.0, 0.5, "white", "Drum")
	ball(m, f, 0, 3.25, hz, 2.25, "teal", "Dome")
	cyl(m, f, 0, 3.35, hz, 2.25, 0.25, "gold", "DomeBand")
	box(m, f, 0, 4.5, hz, 0.25, 0.75, 0.25, "gold", "Spire")
	ball(m, f, 0, 5.0, hz, 0.5, "gold", "Finial")
	-- the porch, the round window, the doors, the windows, the banners
	local fz = hz + 1.125
	for _, x in { -0.65, 0.65 } do
		cyl(m, f, x, 1.25, fz + 0.55, 0.5, 1.75, "white", "Column")
		box(m, f, x, 0.44, fz + 0.55, 0.5, 0.25, 0.5, "sand", "ColumnBase")
	end
	box(m, f, 0, 2.19, fz + 0.5, 1.75, 0.25, 1.0, "white", "Lintel")
	wedge(m, f, -0.375, 2.565, fz + 0.5, 1.0, 0.5, 0.75, "teal", math.pi / 2, "Pediment")
	wedge(m, f, 0.375, 2.565, fz + 0.5, 1.0, 0.5, 0.75, "teal", -math.pi / 2, "Pediment")
	ball(m, f, 0, 2.5, fz + 1.0, 0.25, "gold", "Crest")
	roundDoor(m, f, 0, 0.375, fz, 1.0, "wood", "wood_dark", "gold")
	box(m, f, 0, 0.375, fz + 0.75, 0.75, 0.25, 0.75, "sand", "Step")
	for _, x in { -1.0, 1.0 } do
		window(m, f, x, 1.85, fz, 0.5, 0.5, "gold", nil, { "pink", "yellow" })
		roundDoor(m, f, x, 0.375, fz, 0.5, "wood", "wood_dark", "gold")
	end
	local side = east(f, 1.5)
	window(m, side, -hz - 0.5, 2.0, 0, 0.5, 0.75, "gold", "teal")
	box(m, f, 1.56, 1.75, hz - 0.6, 0.25, 1.25, 0.5, "berry_red", "FlagBanner")
	box(m, f, 1.59, 2.4, hz - 0.6, 0.25, 0.25, 0.75, "gold", "BannerRod")
	-- the court: the fountain, lamps along the path, garden beds, a bench
	box(m, f, 0, 0.25, 1.95, 0.75, 0.25, 1.0, "sand", "Path")
	cyl(m, f, 0, 0.44, 1.5, 1.0, 0.25, "rock", "FountainRim")
	cyl(m, f, 0, 0.5, 1.5, 0.75, 0.25, "shallow", "Fountain"):SetAttribute("PixelWater", 2)
	cyl(m, f, 0, 0.75, 1.5, 0.25, 0.5, "rock", "FountainStem")
	cyl(m, f, 0, 1.0, 1.5, 0.5, 0.25, "rock", "FountainBowl")
	box(m, f, 0, 1.19, 1.5, 0.25, 0.5, 0.25, "white", "Jet")
	for _, p in { { -0.7, 1.95 }, { 0.7, 1.95 } } do
		box(m, f, p[1], 0.94, p[2], 0.25, 1.25, 0.25, "steel_dark", "LampPost")
		box(m, f, p[1], 1.69, p[2], 0.25, 0.25, 0.25, "yellow", "LampLight", true)
		box(m, f, p[1], 1.94, p[2], 0.5, 0.25, 0.5, "steel_dark", "LampCap")
	end
	for _, b in { { -1.8, 1.5 }, { 1.8, 1.5 }, { -2.0, -0.6 }, { 2.0, -0.6 } } do
		box(m, f, b[1], 0.44, b[2], 0.75, 0.25, 0.75, "wood_dark", "Bed")
		box(m, f, b[1], 0.75, b[2], 0.25, 0.5, 0.25, "wood", "TreeTrunk")
		ball(m, f, b[1], 1.25, b[2], 0.75, "leaf", "TreeCrown")
		ball(m, f, b[1] - 0.3, 0.62, b[2] + 0.3, 0.25, "pink", "Bloom")
		ball(m, f, b[1] + 0.3, 0.62, b[2] + 0.25, 0.25, "yellow", "Bloom")
	end
	box(m, f, 1.0, 0.56, 0.75, 0.75, 0.25, 0.25, "wood", "BenchSeat")
	box(m, f, 1.0, 0.81, 0.62, 0.75, 0.25, 0.25, "wood", "BenchBack")
end

-- Hatchery (4 x 4): a warm nursery at the back with cream walls on a stone band, dark corner posts and a thatched roof
-- in rows with moss on it, a chimney with a curl of smoke, a round red door, a round window glowing warm with a flower
-- box, a board with an egg on it over the door, a shuttered window on the east side; in front a big nest of straw
-- holding three speckled eggs of the rarities' colours, a heat lamp leaning over it, a lantern on a stump, baskets of
-- eggs, an incubator with a glowing round window and a thermometer, a sack of feed, a bit of picket fence, a stepping
-- stone and flowers.
B.hatchery = function(m, f)
	pad(m, f, 4, 4, 0.125, "sand_dark", "Footing")
	-- the nursery
	local nx, nz = 0.25, -1.0
	box(m, f, nx, 1.0, nz, 2.5, 1.75, 1.75, "cream", "Walls")
	box(m, f, nx, 0.25, nz, 2.75, 0.25, 2.0, "rock", "Band")
	for _, c in { { -1, 0.905 }, { 1, 0.905 }, { 1, -0.75 } } do
		box(m, f, nx + c[1] * 1.28, 0.875, nz + c[2], 0.25, 1.5, 0.25, "wood_dark", "Corner")
	end
	gable(m, f * CFrame.new(nx, 0, nz), 1.875, 2.5, 1.75, 1.25, 0.125, "straw", "sand_dark", "wood_dark")
	ball(m, f, nx - 0.6, 2.35, nz + 0.5, 0.5, "moss", "Moss")
	chimney(m, f, nx + 0.95, 2.4, nz - 0.5, 0.75, "brick")
	-- the front: the door, the glowing window and its flower box, the board with an egg
	local fz = nz + 0.875
	roundDoor(m, f, -0.4, 0.125, fz, 0.75, "berry_red", "brick", "wood_dark")
	box(m, f, -0.4, 0.19, fz + 0.125, 0.75, 0.25, 0.25, "rock", "Step")
	discZ(m, f, 0.95, 1.05, fz, 1.0, 0.25, "wood_dark", "WindowRing")
	discZ(m, f, 0.95, 1.05, fz + 0.03, 0.75, 0.25, "yellow", "WindowGlow", true)
	box(m, f, 0.95, 1.05, fz + 0.06, 0.25, 0.75, 0.25, "wood_dark", "Bar")
	box(m, f, 0.95, 1.05, fz + 0.08, 0.75, 0.25, 0.25, "wood_dark", "Bar")
	box(m, f, 0.95, 0.44, fz + 0.19, 0.75, 0.25, 0.25, "wood", "FlowerBox")
	for k, c in { "pink", "yellow", "pink" } do
		ball(m, f, 0.7 + (k - 1) * 0.25, 0.6, fz + 0.25, 0.25, c, "Bloom")
	end
	box(m, f, -0.4, 1.45, fz - 0.06, 1.0, 0.5, 0.25, "wood", "Board")
	box(m, f, -0.4, 1.45, fz - 0.03, 0.75, 0.25, 0.25, "cream", "Board")
	ball(m, f, -0.4, 1.45, fz + 0.06, 0.25, "cherry", "BoardEgg")
	window(m, east(f, nx + 1.25), -nz, 1.1, 0, 0.5, 0.5, "wood_dark", "berry_red", { "pink", "yellow" })
	-- the big nest and its eggs
	local cx, cz = 0.15, 1.0
	local function at(r: number, a: number, y: number): CFrame
		return f * CFrame.new(cx + math.cos(a) * r, y, cz + math.sin(a) * r) * CFrame.Angles(0, -a - math.pi / 2, 0)
	end
	cyl(m, f, cx, 0.3, cz, 1.5, 0.5, "sand_dark", "Core")
	cyl(m, f, cx, 0.5, cz, 1.25, 0.25, "cream", "Lining")
	for i = 0, 13 do
		local a = i / 14 * TAU
		part(m, at(0.72, a, 0.25) * CFrame.Angles(0, 0, if i % 2 == 0 then 0.35 else -0.35), 0.5, 0.25, 0.25, if i % 2 == 0 then "sand_dark" else "straw", "Straw")
	end
	for i = 0, 15 do
		local a = i / 16 * TAU + 0.2
		part(m, at(0.78, a, 0.5) * CFrame.Angles(-0.3, 0, 0), 0.5, 0.25, 0.25, if i % 2 == 0 then "straw" else "sand_dark", "Rim")
	end
	local eggs = {
		{ c = Vector3.new(-0.12, 0.92, 0.9), d = 0.75, shell = "cream", dot = "green" },
		{ c = Vector3.new(0.45, 0.9, 0.8), d = 0.75, shell = "window", dot = "purple" },
		{ c = Vector3.new(0.25, 0.8, 1.4), d = 0.5, shell = "yellow", dot = "orange" },
	}
	for _, e in eggs do
		local c = e.c
		ball(m, f, c.X, c.Y, c.Z, e.d, e.shell, "Egg")
		for _, d in { Vector3.new(0.3, 0.6, 0.75), Vector3.new(0.85, 0.1, 0.5) } do
			local p = c + d.Unit * (e.d / 2 - 0.06)
			ball(m, f, p.X, p.Y, p.Z, 0.25, e.dot, "Speckle")
		end
	end
	-- the heat lamp leaning over the nest from the west, a warm lamp on a post to the east
	box(m, f, -1.05, 1.0, 0.75, 0.25, 1.75, 0.25, "steel_dark", "LampPole")
	box(m, f, -0.8, 1.81, 0.85, 0.75, 0.25, 0.25, "steel_dark", "LampArm")
	box(m, f, -0.45, 1.69, 0.95, 0.5, 0.25, 0.5, "steel", "LampHood")
	box(m, f, -0.45, 1.5, 0.95, 0.25, 0.25, 0.25, "orange", "LampGlow", true)
	cyl(m, f, 1.7, 0.25, 1.15, 0.5, 0.25, "wood_dark", "Stump")
	lantern(m, f, 1.7, 0.62, 1.15, true)
	-- baskets of eggs, the incubator, the sack, the fence, stones and flowers
	for _, b in { { x = -1.5, z = 1.05, a = "pink", b = "blue" }, { x = 1.45, z = 0.4, a = "yellow", b = "white" } } do
		cyl(m, f, b.x, 0.375, b.z, 0.75, 0.5, "wood", "Basket")
		cyl(m, f, b.x, 0.56, b.z, 1.0, 0.25, "wood_dark", "BasketRim")
		ball(m, f, b.x - 0.12, 0.69, b.z + 0.05, 0.25, b.a, "Egg")
		ball(m, f, b.x + 0.12, 0.72, b.z - 0.05, 0.25, b.b, "Egg")
	end
	box(m, f, -1.5, 0.5, -0.6, 0.75, 0.75, 0.75, "desk", "Incubator")
	box(m, f, -1.5, 0.94, -0.6, 1.0, 0.25, 1.0, "wood_dark", "IncubatorLid")
	discZ(m, f, -1.5, 0.5, -0.22, 0.5, 0.25, "wood_dark", "IncubatorRing")
	discZ(m, f, -1.5, 0.5, -0.19, 0.25, 0.25, "orange", "IncubatorGlow", true)
	box(m, f, -1.09, 0.5, -0.6, 0.25, 0.5, 0.25, "white", "Thermometer")
	box(m, f, -1.06, 0.375, -0.57, 0.25, 0.25, 0.25, "berry_red", "Thermometer")
	K.sack(m, f, -1.55, 0.125, 0.15, "sand")
	for k = 0, 3 do
		box(m, f, -1.85 + k * 0.4, 0.375, 1.85, 0.25, 0.5, 0.25, "white", "Picket")
	end
	box(m, f, -1.25, 0.44, 1.88, 1.5, 0.25, 0.25, "white", "FenceRail")
	stone(m, f, -0.8, 0.125, 0.4, 0.5)
	for _, p in { { x = -0.1, z = 1.8, c = "white" }, { x = -0.95, z = 0.2, c = "yellow" }, { x = 0.9, z = 1.8, c = "pink" } } do
		flower(m, f, p.x, 0.125, p.z, p.c)
	end
end

return B
