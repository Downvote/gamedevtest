--!strict
-- The island's buildings and decor from parts (GAME_DESIGN 4; Data/Buildings). Roblox module (server: PlotService
-- builds the placed pieces; client: Build mode's ghost). `build(id, at, lvl?)`: a model standing on `at` (the
-- footprint's centre on the grass, already turned by the piece's rot), facing +Z before the turn, within its
-- footprint (Data/Buildings' w x d). Each is detailed in the pixel filter's scale: a footing on the grass, framed
-- windows and doors, roofs with eaves and a ridge, and the small things of its trade (crates, barrels, sacks, tools,
-- pots). An upgraded building (lvl 2, 3) flies a pennant (a gold one at 3) and gains a lantern by its door (lvl 3).
-- Pieces do not collide (the founder walks through them, never stuck behind one).
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local tube = K.tube
local wedge = K.wedge
local window = K.window
local door = K.door
local pot = K.pot
local footing = K.footing
local streetLamp = K.streetLamp
local pennant = K.pennant
local Buildings = require(script.Parent.Parent.Data.Buildings)

-- footprints by id (the pennant's corner), and kinds
local FOOT: { [string]: { number } } = {}
local KIND: { [string]: string } = {}
for _, d in Buildings.list do
	FOOT[d.id] = { d.w, d.d }
	KIND[d.id] = d.kind
end

local DecorModels = {}

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()


local B: { [string]: Builder } = {}

------------------------------------------------------------------ food


------------------------------------------------------------------ wood


------------------------------------------------------------------ shops


------------------------------------------------------------------ decor
-- (Reworked for the request of 2026-11-19: "detail all decor more, some having animations, as much as in the bakery
-- game and as much as the work/hut/ main buildings". The small shapes the decor shares are just below. Sizes are whole
-- quarter studs (Blocks snaps them), so a trim stands a few hundredths proud of what it is on, never on its plane; the
-- front (+Z) and east (+X) faces, the ones the camera sees, carry the most; the back-left corner stays low for the
-- upgrade pennant. A part marked with K.move moves on the island (Controllers/Spinners); a part named Flame, Spray,
-- Sparkle, Mug or Teapot gives off sparks, spray, a twinkle or steam (Controllers/AmbientView), and one named Bloom,
-- Petals or FlowerHeart draws the butterflies.)
local V = Vector3.new
local TAU = math.pi * 2
local move = K.move
local span = K.span

-- A part at f * cf (turned or tilted), of any shape.
local function at(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: ("Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball")?, neon: boolean?): BasePart
	return Blocks.part(m, { size = V(w, h, d), cf = f * cf, color = color, name = name, shape = shape, neon = neon, collide = false })
end

-- A disc facing +Z (a cylinder whose axis runs along Z) at (x, y, z), t thick.
local function discZ(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string, neon: boolean?): BasePart
	return at(m, f, CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), t, dia, dia, color, name, "Cylinder", neon)
end

-- A disc facing +X.
local function discX(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, t: number, color: string, name: string, neon: boolean?): BasePart
	return at(m, f, CFrame.new(x, y, z), t, dia, dia, color, name, "Cylinder", neon)
end

-- A square bar w thick from a to b (points in f): a leg on a slant, a rope, a rail.
local function bar(m: Instance, f: CFrame, a: Vector3, b: Vector3, w: number, color: string, name: string, neon: boolean?): BasePart
	local d = b - a
	local up = if math.abs(d.Unit.Y) > 0.99 then V(0, 0, 1) else V(0, 1, 0)
	return at(m, f, CFrame.lookAt((a + b) / 2, b, up), w, w, d.Magnitude, color, name, nil, neon)
end

-- A point on a ball of diameter dia at c, toward (dx, dy, dz), pushed out by `out`.
local function onBall(c: Vector3, dia: number, dx: number, dy: number, dz: number, out: number?): Vector3
	return c + V(dx, dy, dz).Unit * (dia / 2 + (out or 0))
end

-- n blocks w x h x d on a circle of radius r round (x, z) at height y, each facing out (d along the radius, w along
-- the circle), the first a0 round from +Z toward +X. Returns them.
local function ringOf(m: Instance, f: CFrame, x: number, y: number, z: number, r: number, n: number, w: number, h: number, d: number, color: string, name: string, a0: number?): { BasePart }
	local out = {}
	for k = 0, n - 1 do
		local a = (a0 or 0) + k * TAU / n
		table.insert(out, at(m, f, CFrame.new(x + math.sin(a) * r, y, z + math.cos(a) * r) * CFrame.Angles(0, a, 0), w, h, d, color, name))
	end
	return out
end

-- A flower standing on y: a stem and its head (the butterflies come to it).
local function flower(m: Instance, f: CFrame, x: number, y: number, z: number, color: string, tall: boolean?)
	local h = if tall then 0.5 else 0.25
	box(m, f, x, y + h / 2, z, 0.25, h, 0.25, "leaf", "Stem")
	ball(m, f, x, y + h + 0.06, z, 0.25, color, "Bloom")
end

-- A tuft of grass on y: two blades leaning apart.
local function tuft(m: Instance, f: CFrame, x: number, y: number, z: number)
	at(m, f, CFrame.new(x - 0.06, y + 0.2, z) * CFrame.Angles(0.2, 0, 0.3), 0.25, 0.5, 0.25, "leaf", "Grass")
	at(m, f, CFrame.new(x + 0.06, y + 0.2, z + 0.03) * CFrame.Angles(-0.2, 0, -0.3), 0.25, 0.5, 0.25, "leaf_dark", "Grass")
end

-- A lantern at (x, y, z), y the glass's middle: a dark cap over a lit glass (a small one's cap no wider than it).
local function lantern(m: Instance, f: CFrame, x: number, y: number, z: number, small: boolean?)
	local c = if small then 0.25 else 0.5
	box(m, f, x, y + 0.375, z, c, 0.25, c, "black", "LanternCap")
	box(m, f, x, y, z, 0.25, 0.5, 0.25, "yellow", "Lantern", true)
end

-- A crystal: a square prism w x h x w standing on cf (its foot, any tilt) that narrows to its point a quarter stud a
-- step (the last a longer needle), the way a gem's point reads in pixels. Returns its parts.
local function crystal(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, color: string, neon: boolean?, name: string?): { BasePart }
	local out = { at(m, f, cf * CFrame.new(0, h / 2, 0), w, h, w, color, name or "Crystal", nil, neon) }
	local y, s = h, w - 0.25
	while s >= 0.25 do
		local tall = if s < 0.5 and w <= 0.5 then 0.75 else 0.5
		table.insert(out, at(m, f, cf * CFrame.new(0, y + tall / 2 - 0.05, 0), s, tall, s, color, "Point", nil, neon))
		y += 0.375
		s -= 0.25
	end
	return out
end

-- Marks every part of a list to move together (K.move).
local function moveAll(ps: { BasePart }, kind: string, hub: Vector3, axis: string, speed: number, amp: number?, phase: number?)
	for _, p in ps do
		move(p, kind, hub, axis, speed, amp, phase)
	end
end

-- Flower Bed (2 x 2): a raised bed edged with a long stone a side in two greys and darker corner blocks standing a
-- little higher, dark soil heaped in three rows; lupin spires at the back (purple, blue, pink, each with a pale tip and
-- a leaf at its foot), tulips in the middle with a leaf each, daisies at the front (white with a yellow heart) over
-- rosettes of leaves; a trowel left on the east edging.
B.flowers = function(m, f)
	for k = 0, 3 do
		local g = f * CFrame.Angles(0, k * math.pi / 2, 0)
		box(m, g, 0, 0.25, 0.875, 1.5, 0.5, 0.25, if k % 2 == 0 then "rock" else "pavement", "Border")
		box(m, g, 0.875, 0.31, 0.875, 0.25, 0.75, 0.25, "rock_dark", "Corner")
	end
	box(m, f, 0, 0.125, 0, 1.5, 0.5, 1.5, "hair_brown", "Soil")
	for _, z in { -0.45, 0, 0.45 } do
		box(m, f, 0, 0.4, z, 1.5, 0.25, 0.25, "wood_dark", "Row")
	end
	-- the back row: lupins, a wide spire stepping in to a pale tip
	local lupins = { { "purple", "pink" }, { "blue", "white" }, { "pink", "cherry" } }
	for i, c in lupins do
		local x = (i - 2) * 0.45
		box(m, f, x, 0.6, -0.45, 0.25, 0.5, 0.25, "leaf", "Stem")
		box(m, f, x, 1.0, -0.45, 0.5, 0.5, 0.5, c[1], "Bloom")
		box(m, f, x, 1.4, -0.45, 0.25, 0.5, 0.25, c[1], "Bloom")
		box(m, f, x, 1.72, -0.45, 0.25, 0.25, 0.25, c[2], "Bloom")
		at(m, f, CFrame.new(x + 0.2, 0.62, -0.3) * CFrame.Angles(0, 0, -0.6), 0.25, 0.5, 0.25, "leaf_dark", "Leaf")
	end
	-- the middle row: tulips, a cup on a stem and a leaf
	for i, c in { "berry_red", "yellow", "orange" } do
		local x = (i - 2) * 0.45 + 0.08
		box(m, f, x, 0.65, 0, 0.25, 0.5, 0.25, "leaf", "Stem")
		ball(m, f, x, 0.98, 0, 0.5, c, "Petals")
		at(m, f, CFrame.new(x - 0.17, 0.65, 0.06) * CFrame.Angles(0, 0, 0.5), 0.25, 0.5, 0.25, "leaf_dark", "Leaf")
	end
	-- the front row: daisies over rosettes of leaves
	for i, c in { "white", "cherry", "white" } do
		local x = (i - 2) * 0.45 - 0.04
		box(m, f, x, 0.55, 0.45, 0.5, 0.25, 0.5, "leaf_dark", "Rosette")
		ball(m, f, x, 0.8, 0.45, 0.5, c, "Petals")
		box(m, f, x + 0.04, 0.92, 0.6, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	end
	-- a trowel left on the edging
	box(m, f, 0.875, 0.6, 0.2, 0.25, 0.25, 0.5, "wood", "Handle")
	box(m, f, 0.875, 0.6, -0.25, 0.25, 0.25, 0.5, "steel", "Trowel")
end

-- Round Bush (2 x 2): a mound of leafy clumps on a ring of dark mulch: dark clumps low and round the back, lighter ones
-- piled over them (the light finds their tops), little tufts poking out of the outline and dark pockets between the
-- clumps; red berries in clusters and a few white flowers on the sides the camera sees, a twig sticking out, two stones
-- at its foot.
B.bush = function(m, f)
	cyl(m, f, 0, 0.06, 0, 1.75, 0.25, "grass_dark", "Mulch")
	for _, c in { { -0.45, 0.5, -0.4, 1.0 }, { 0.45, 0.5, -0.4, 1.0 }, { -0.45, 0.5, 0.35, 1.0 }, { 0.45, 0.45, 0.4, 1.0 }, { 0, 0.6, 0, 1.25 } } do
		ball(m, f, c[1], c[2], c[3], c[4], "leaf_dark", "Bush")
	end
	local clumps = { { 0, 1.05, -0.05, 1.25 }, { -0.35, 0.95, 0.3, 1.0 }, { 0.35, 0.92, 0.32, 1.0 }, { 0.32, 1.02, -0.35, 1.0 }, { -0.38, 1.08, -0.3, 1.0 }, { 0.05, 1.55, 0.05, 0.75 } }
	for _, c in clumps do
		ball(m, f, c[1], c[2], c[3], c[4], "leaf", "Leaves")
	end
	for _, c in { { -0.78, 0.85, 0.05 }, { 0.75, 1.1, -0.1 }, { 0.2, 1.85, -0.15 }, { -0.25, 1.7, 0.3 } } do
		ball(m, f, c[1], c[2], c[3], 0.5, "leaf", "Bush")
	end
	-- dark pockets between the lit clumps
	ball(m, f, 0.0, 0.85, 0.62, 0.5, "leaf_dark", "Bush")
	ball(m, f, 0.62, 0.75, 0.0, 0.5, "leaf_dark", "Bush")
	-- berries in threes, white flowers on top
	local c2 = V(clumps[2][1], clumps[2][2], clumps[2][3])
	local c3 = V(clumps[3][1], clumps[3][2], clumps[3][3])
	for _, b in { onBall(c2, 1.0, -0.3, 0.1, 1), onBall(c2, 1.0, -0.6, -0.2, 0.8), onBall(c2, 1.0, 0.0, -0.3, 1), onBall(c3, 1.0, 1, 0.2, 0.6), onBall(c3, 1.0, 0.8, -0.2, 0.9), onBall(V(0.45, 0.45, 0.4), 1.0, 0.6, 0.1, 1), onBall(V(0.45, 0.45, 0.4), 1.0, 0.9, -0.2, 0.7) } do
		ball(m, f, b.X, b.Y, b.Z, 0.25, "berry_red", "Berry")
	end
	for _, b in { onBall(V(0.05, 1.55, 0.05), 0.75, -0.3, 1, 0.4), onBall(V(0, 1.05, -0.05), 1.25, 0.7, 0.8, 0.3), onBall(c2, 1.0, -0.4, 0.9, 0.5) } do
		ball(m, f, b.X, b.Y, b.Z, 0.25, "white", "Bloom")
	end
	at(m, f, CFrame.new(-0.62, 1.5, -0.25) * CFrame.Angles(0.2, 0, 0.7), 0.25, 0.5, 0.25, "wood_dark", "Twig")
	ball(m, f, 0.72, 0.12, 0.72, 0.5, "rock", "Stone")
	ball(m, f, 0.4, 0.08, 0.85, 0.25, "rock_dark", "Stone")
end

-- Tiki Torch (1 x 1): a bamboo pole on a ring of stones with a tuft of grass, bound with cord in two places, a carved
-- face near the top (a heavy brow, white eyes, a nose, a grin with a gap), a neck and a woven cup with a dark rim, its
-- flame (sparks fly off it) leaning in the breeze.
B.torch = function(m, f)
	ball(m, f, -0.25, 0.1, 0.2, 0.5, "rock", "Stone")
	ball(m, f, 0.22, 0.08, 0.25, 0.5, "rock_dark", "Stone")
	ball(m, f, 0.2, 0.06, -0.25, 0.25, "rock", "Stone")
	tuft(m, f, -0.24, 0, -0.25)
	box(m, f, 0, 0.5, 0, 0.25, 1.0, 0.25, "sand_dark", "Pole")
	for _, y in { 0.35, 0.8 } do
		box(m, f, 0, y, 0, 0.5, 0.25, 0.5, "straw", "Binding")
	end
	box(m, f, 0.2, 0.62, 0.12, 0.25, 0.25, 0.25, "straw", "Cord")
	-- the carved head
	box(m, f, 0, 1.5, 0, 0.75, 1.0, 0.5, "wood", "Carving")
	box(m, f, 0, 1.88, 0.06, 0.75, 0.25, 0.5, "wood_dark", "Brow")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.19, 1.65, 0.2, 0.25, 0.25, 0.25, "cream", "Eye")
	end
	box(m, f, 0, 1.43, 0.25, 0.25, 0.25, 0.25, "wood_dark", "Nose")
	box(m, f, 0, 1.18, 0.2, 0.5, 0.25, 0.25, "cream", "Grin")
	box(m, f, 0.06, 1.18, 0.26, 0.25, 0.25, 0.25, "wood_dark", "Gap")
	-- the cup and its flame (the flame sways a little on the breeze)
	box(m, f, 0, 2.12, 0, 0.5, 0.25, 0.5, "wood_dark", "Neck")
	box(m, f, 0, 2.43, 0, 0.75, 0.5, 0.75, "straw", "Cup")
	box(m, f, 0, 2.43, 0.32, 0.25, 0.5, 0.25, "sand_dark", "Weave")
	box(m, f, 0.32, 2.43, 0, 0.25, 0.5, 0.25, "sand_dark", "Weave")
	box(m, f, 0, 2.75, 0, 1.0, 0.25, 1.0, "wood_dark", "Rim")
	local hub = V(0, 2.8, 0)
	for _, p in { box(m, f, 0, 3.0, 0, 0.5, 0.5, 0.5, "orange", "Flame", true), box(m, f, 0.06, 3.3, 0.06, 0.25, 0.5, 0.25, "yellow", "Tip", true), box(m, f, -0.19, 3.1, 0, 0.25, 0.25, 0.25, "orange", "Lick", true) } do
		move(p, "swing", hub, "Z", 2.2, 0.2)
	end
end

-- Shell Pile (2 x 2): a low drift of sand with a darker wet edge; a heap of scallops leaning on each other (each a fan
-- with a ridge and a dark hinge) among round shells; a big pink conch on its side with spikes and its coral mouth; an
-- open clam with a pearl in it that glints; a starfish; a sand dollar with its mark; seaweed and a stick of bleached
-- driftwood.
B.shellpile = function(m, f)
	cyl(m, f, 0, 0.0, 0, 2.0, 0.25, "sand_dark", "Sand")
	cyl(m, f, 0.05, 0.1, -0.05, 1.5, 0.25, "sand", "Sand")
	-- scallops: a fan tipped up toward the view, a ridge down it, a dark hinge at its foot
	local function scallop(cf: CFrame, color: string, rib: string)
		at(m, f, cf * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.75, 0.75, color, "Shell", "Cylinder")
		at(m, f, cf * CFrame.new(0, 0.05, 0.08), 0.25, 0.5, 0.25, rib, "Rib")
		at(m, f, cf * CFrame.new(0, -0.33, 0.06), 0.25, 0.25, 0.25, "wood", "Hinge")
	end
	scallop(CFrame.new(-0.55, 0.5, -0.3) * CFrame.Angles(-0.6, 0.35, 0), "pink", "cherry")
	scallop(CFrame.new(-0.05, 0.5, -0.45) * CFrame.Angles(-0.7, -0.2, 0), "cream", "sand_dark")
	scallop(CFrame.new(-0.32, 0.78, -0.42) * CFrame.Angles(-0.9, 0.1, 0), "orange", "coral")
	ball(m, f, -0.62, 0.3, 0.12, 0.5, "coral", "Shell")
	ball(m, f, 0.12, 0.3, -0.12, 0.5, "white", "Shell")
	ball(m, f, -0.3, 0.28, 0.0, 0.5, "pink", "Shell")
	-- the conch: a body narrowing to its tip, spikes on its whorl, its mouth
	local c = V(0.2, 0.4, 0.45)
	local d = V(0.94, 0.2, -0.28).Unit
	ball(m, f, c.X, c.Y, c.Z, 0.75, "pink", "Conch")
	local q = c + d * 0.42
	ball(m, f, q.X, q.Y, q.Z, 0.5, "pink", "Conch")
	local t = c + d * 0.68
	ball(m, f, t.X, t.Y, t.Z, 0.25, "cream", "Tip")
	box(m, f, c.X - 0.1, c.Y + 0.33, c.Z - 0.05, 0.25, 0.25, 0.25, "cream", "Spike")
	box(m, f, q.X, q.Y + 0.25, q.Z, 0.25, 0.25, 0.25, "cream", "Spike")
	at(m, f, CFrame.new(c.X - 0.15, c.Y - 0.05, c.Z + 0.3) * CFrame.Angles(0, -0.3, 0.4), 0.5, 0.25, 0.25, "coral", "Mouth")
	-- the open clam and its pearl
	local cl = V(0.55, 0.32, -0.2)
	cyl(m, f, cl.X, cl.Y, cl.Z, 0.75, 0.25, "cream", "Clam")
	at(m, f, CFrame.new(cl.X, cl.Y + 0.1, cl.Z - 0.375) * CFrame.Angles(-2.1, 0, 0) * CFrame.new(0, 0, 0.375) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 0.75, 0.75, "sand_dark", "Clam", "Cylinder")
	ball(m, f, cl.X, cl.Y + 0.2, cl.Z + 0.05, 0.25, "white", "Sparkle")
	-- a starfish, a sand dollar
	local sx, sz = -0.42, 0.48
	for k = 0, 4 do
		local a = k * TAU / 5 + 0.3
		at(m, f, CFrame.new(sx + math.sin(a) * 0.22, 0.27, sz + math.cos(a) * 0.22) * CFrame.Angles(0, a, 0), 0.25, 0.25, 0.5, "orange", "Starfish")
	end
	cyl(m, f, 0.65, 0.2, 0.68, 0.5, 0.25, "cream", "SandDollar")
	box(m, f, 0.65, 0.25, 0.68, 0.25, 0.25, 0.25, "sand_dark", "Mark")
	-- seaweed, driftwood
	at(m, f, CFrame.new(-0.1, 0.22, 0.66) * CFrame.Angles(0, 1.1, 0), 0.25, 0.25, 0.75, "swamp", "Seaweed")
	at(m, f, CFrame.new(0.25, 0.2, 0.72) * CFrame.Angles(0, -0.7, 0), 0.25, 0.25, 0.5, "teal", "Seaweed")
	K.log(m, f, 0.25, 0.2, -0.86, 1.0, 0.25, "pavement", "Driftwood")
	box(m, f, 0.55, 0.32, -0.86, 0.25, 0.25, 0.25, "rock", "Knot")
end

-- Palm Tree (3 x 3): StreetModels' shore palm, a little fuller. A ringed trunk leaning out from its foot in one smooth
-- curve and coming upright under the crown (round segments, a thin dark ring at each joint), a fibrous boot, eight
-- fronds that rise, arch and droop (each a fold of toothed leaflet blades, the upper ones lighter), two young ones
-- spearing up, two dead ones hanging, a bunch of coconuts; at its foot a mound of sand with a fallen coconut, a split
-- one and a tuft of beach grass, a little crab and a cockle shell.
B.palm = function(m, f)
	local x = 1.5
	local top = 5.4
	local function part(cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: ("Cylinder" | "Ball")?): BasePart
		return Blocks.part(m, { size = Vector3.new(w, h, d), cf = cf, color = color, name = name, shape = shape, collide = false })
	end
	-- the mound of sand, a wide low ring and a smaller one on it
	part(f * CFrame.new(0, 0.0625, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 2.5, 2.5, "sand_dark", "Mound", "Cylinder")
	part(f * CFrame.new(0.1, 0.1875, 0) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 1.5, 1.5, "sand", "Mound", "Cylinder")
	-- the trunk (widths on the 1/8-stud grid, lengths exact: the joints meet)
	local widths = { 0.82, 0.7, 0.7, 0.66, 0.62, 0.57, 0.54 }
	local pts: { Vector3 } = {}
	for j = 1, #widths + 1 do
		local t = (j - 1) / #widths
		table.insert(pts, Vector3.new(x * (t + t * t - t * t * t), (top - 0.15) * t, 0))
	end
	for i, w in widths do
		local a, b = pts[i], pts[i + 1]
		local d = math.floor(w * 8 + 0.5) / 8
		part(f * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), 1, 1, 1, "wood", "Trunk", "Cylinder").Size = Vector3.new((b - a).Magnitude, d, d)
		if i < #widths then
			local c = pts[i + 2]
			part(f * CFrame.lookAt(b, b + (b - a).Unit + (c - b).Unit) * CFrame.Angles(0, math.pi / 2, 0), 1, 1, 1, "wood_dark", "Trunk", "Cylinder").Size = Vector3.new(0.19, d + 0.125, d + 0.125)
		end
	end
	part(f * CFrame.new(0.04, 0.15, 0), 1, 1, 1, "wood", "Trunk", "Ball") -- (the foot)
	-- a frond from p toward yaw a: segments { length, pitch, width, fold }; a fold (1) is two leaflet blades hanging
	-- `hang` degrees either side of the midrib, swept toward the tip (the edge goes in teeth), else (0) one blade
	local sweep = math.rad(16)
	local function frond(p: Vector3, a: number, segs: { { number } }, hang: number, color: string)
		local dir = Vector3.new(math.cos(a), 0, -math.sin(a))
		local hr = math.rad(hang)
		for _, sg in segs do
			local pitch = math.rad(sg[2])
			local hw = sg[3]
			local q = p + dir * (math.cos(pitch) * sg[1]) + Vector3.new(0, math.sin(pitch) * sg[1], 0)
			local cf = f * CFrame.lookAt((p + q) / 2, q)
			local L = Blocks.snap(sg[1] + 0.25)
			if sg[4] == 1 then
				for _, side in { 1, -1 } do
					part(cf * CFrame.new(0, 0, L / 2) * CFrame.Angles(0, 0, -side * hr) * CFrame.Angles(0, side * sweep, 0) * CFrame.new(side * hw / 2, 0, -L / 2), hw, 0.25, L, color, "Frond")
				end
			else
				part(cf, hw, 0.25, L, color, "Frond")
			end
			p = q
		end
	end
	local heart = Vector3.new(x, top, 0)
	ball(m, f, x, top - 0.3, 0, 0.75, "hair_brown", "Boot")
	ball(m, f, x, top + 0.05, 0, 0.5, "leaf_dark", "Heart")
	-- (the camera looks from +X +Z and never turns: a gap between two rising fronds faces it, the coconuts and the dead
	-- fronds hanging there in sight)
	local v = f:VectorToObjectSpace(Vector3.new(1, 0, 1))
	local va = math.atan2(-v.Z, v.X)
	for k = 0, 7 do
		local a = va + (k + 0.5) * math.pi / 4
		local up = k % 2 == 0 or k == 7
		frond(heart + Vector3.new(math.cos(a), 0, -math.sin(a)) * 0.15, a, if up then { { 1, 28, 0.5, 1 }, { 1, 0, 0.5, 1 }, { 0.75, -38, 0.5, 0 } } else { { 0.9, 8, 0.5, 1 }, { 1, -24, 0.5, 1 }, { 0.75, -58, 0.5, 0 } }, if up then 28 else 36, if up then "leaf" else "leaf_dark")
	end
	for k = 0, 1 do
		frond(heart + Vector3.new(0, 0.1, 0), va + 0.9 + k * math.pi, { { 0.85, 66, 0.25, 0 } }, 0, "leaf")
	end
	for k = 0, 1 do
		local a = va + (if k == 0 then 1.6 else -1.7)
		frond(heart + Vector3.new(math.cos(a) * 0.2, -0.3, -math.sin(a) * 0.2), a, { { 0.45, -40, 0.25, 0 }, { 0.9, -78, 0.5, 1 } }, 62, if k == 0 then "straw" else "wood")
	end
	for k = 0, 4 do
		local a = va + ({ -0.6, -0.2, 0.2, 0.6, math.pi })[k + 1]
		ball(m, f, x + math.cos(a) * 0.48, top - (if k % 2 == 1 then 0.8 else 0.6), -math.sin(a) * 0.48, 0.5, if k % 2 == 1 then "wood_dark" else "bamboo", "Coconut")
	end
	-- at its foot: a fallen coconut, a split one showing its white, beach grass, a crab, a cockle shell
	ball(m, f, -0.45, 0.42, 0.55, 0.5, "wood_dark", "Coconut")
	part(f * CFrame.new(0.75, 0.25, 0.55) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 0.5, 0.5, "wood_dark", "Husk", "Cylinder")
	part(f * CFrame.new(0.75, 0.3125, 0.55) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 0.25, 0.25, "cream", "Flesh", "Cylinder")
	for k, b in { { -0.85, -0.45, 0.5, 0.2 }, { -0.7, -0.6, 0.75, -0.25 }, { -0.95, -0.7, 0.5, 0.35 } } do
		part(f * CFrame.new(b[1], 0.2 + b[3] / 2, b[2]) * CFrame.Angles(b[4], 0, b[4] * 0.6), 0.25, b[3], 0.25, if k == 2 then "leaf_dark" else "leaf", "Blade")
	end
	box(m, f, 0.05, 0.28, 1.1, 0.5, 0.25, 0.25, "coral", "Crab")
	for _, s in { -1, 1 } do
		box(m, f, 0.05 + s * 0.3, 0.28, 1.22, 0.25, 0.25, 0.25, "maple", "Claw")
	end
	box(m, f, -0.95, 0.22, 0.35, 0.25, 0.25, 0.25, "cherry", "Shell")
end

-- Bench (3 x 2): a garden bench on a patch of gravel: three seat slats and three back slats of warm wood on a dark
-- frame (a straight front leg, a back leg leaning back, a seat rail and an arm with a round end at each side, a
-- stretcher low between them), a top rail with a carved crest; a teal cushion with a cream stripe, an open book on the
-- seat, a mug of tea steaming on the arm; a pot of yellow flowers beside it, tufts and pebbles round it.
B.bench = function(m, f)
	local cx = -0.4
	box(m, f, -0.25, 0.02, 0, 2.5, 0.25, 1.5, "pavement", "Gravel")
	box(m, f, -0.95, 0.12, 0.62, 0.25, 0.25, 0.25, "rock", "Pebble")
	box(m, f, 0.3, 0.12, -0.6, 0.25, 0.25, 0.25, "rock_dark", "Pebble")
	for _, z in { -0.25, 0.08, 0.41 } do
		box(m, f, cx, 0.75, z, 2.0, 0.25, 0.25, "wood", "Slat")
	end
	for k, y in { 1.05, 1.35, 1.65 } do
		at(m, f, CFrame.new(cx, y, -0.5 - k * 0.03) * CFrame.Angles(-0.1, 0, 0), 2.0, 0.25, 0.25, "wood", "Slat")
	end
	box(m, f, cx, 1.92, -0.6, 2.0, 0.25, 0.25, "wood_dark", "TopRail")
	box(m, f, cx, 2.14, -0.6, 0.75, 0.25, 0.25, "wood", "Crest")
	for _, s in { -1, 1 } do
		local x = cx + s * 0.9
		box(m, f, x, 0.55, 0.42, 0.25, 1.1, 0.25, "wood_dark", "Leg")
		bar(m, f, V(x, 0, -0.38), V(x, 2.0, -0.6), 0.25, "wood_dark", "BackLeg")
		box(m, f, x, 0.5, 0.0, 0.25, 0.25, 1.0, "wood_dark", "SeatRail")
		box(m, f, x, 1.15, -0.02, 0.25, 0.25, 1.0, "wood_dark", "Arm")
		ball(m, f, x, 1.17, 0.48, 0.5, "wood", "ArmEnd")
	end
	box(m, f, cx, 0.25, 0.02, 1.75, 0.25, 0.25, "wood_dark", "Stretcher")
	box(m, f, cx - 0.45, 0.92, 0.08, 0.75, 0.25, 0.75, "teal", "Cushion")
	box(m, f, cx - 0.45, 0.95, 0.08, 0.25, 0.25, 0.75, "cream", "Stripe")
	box(m, f, cx + 0.5, 0.88, 0.1, 0.75, 0.25, 0.5, "berry_red", "Book")
	box(m, f, cx + 0.5, 0.94, 0.1, 0.5, 0.25, 0.25, "paper", "Pages")
	box(m, f, cx + 0.9, 1.4, 0.22, 0.25, 0.25, 0.25, "white", "Mug")
	-- a pot of flowers beside it
	box(m, f, 1.1, 0.25, 0, 0.5, 0.5, 0.5, "pot", "Pot")
	box(m, f, 1.1, 0.5, 0, 0.75, 0.25, 0.75, "clay", "Rim")
	box(m, f, 1.1, 0.56, 0, 0.5, 0.25, 0.5, "hair_brown", "Soil")
	ball(m, f, 1.1, 0.95, -0.05, 0.75, "leaf", "Plant")
	ball(m, f, 1.22, 0.78, 0.18, 0.5, "leaf_dark", "Plant")
	for _, b in { { 0.95, 1.25, 0.1 }, { 1.3, 1.1, 0.05 }, { 1.12, 0.98, 0.32 } } do
		ball(m, f, b[1], b[2], b[3], 0.25, "yellow", "Bloom")
	end
	tuft(m, f, -1.3, 0, 0.8)
	tuft(m, f, 0.75, 0, -0.8)
end

-- Hammock (4 x 2): two timber posts on A-frame feet with rope wound round them; from each a rope to a spreader bar, a
-- cloth of red and cream stripes sagging between with a pillow and a blue book on it, the lot rocking gently on its
-- ropes; a lantern hanging off the east post, a stump beside it with a coconut drink and a straw, sandals left on the
-- grass, tufts at the feet.
B.hammock = function(m, f)
	local hubY = 1.85 -- where the ropes are tied: the line the hammock rocks round
	for _, s in { -1, 1 } do
		local x = s * 1.75
		box(m, f, x, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
		box(m, f, x, 2.125, 0, 0.5, 0.25, 0.5, "wood", "Cap")
		box(m, f, x, 0.125, 0, 0.25, 0.25, 1.5, "wood_dark", "Foot")
		for _, z in { -0.6, 0.6 } do
			bar(m, f, V(x, 0.2, z), V(x, 0.95, 0), 0.25, "wood", "Brace")
		end
		box(m, f, x, hubY, 0, 0.5, 0.25, 0.5, "straw", "Lashing")
	end
	-- the hammock, rocking round the line between the lashings
	local hub = V(0, hubY, 0)
	local x0, yEnd = 1.25, 1.35
	local function sag(x: number): number
		local t = x / x0
		return yEnd - 0.55 * (1 - t * t)
	end
	local sway: { BasePart } = {}
	for _, s in { -1, 1 } do
		table.insert(sway, bar(m, f, V(s * 1.6, hubY, 0), V(s * x0, yEnd + 0.1, 0), 0.25, "straw", "Rope"))
		table.insert(sway, box(m, f, s * x0, yEnd, 0, 0.25, 0.25, 1.0, "wood", "Spreader"))
	end
	for k = 0, 5 do
		local xa, xb = -x0 + k * 2 * x0 / 6, -x0 + (k + 1) * 2 * x0 / 6
		table.insert(sway, span(m, f, V(xa, sag(xa), 0), V(xb, sag(xb), 0), 1.0, 0.25, if k % 2 == 0 then "berry_red" else "cream", "Cloth"))
	end
	table.insert(sway, box(m, f, -0.82, sag(-0.82) + 0.22, 0, 0.5, 0.25, 0.75, "white", "Pillow"))
	table.insert(sway, at(m, f, CFrame.new(0.35, sag(0.35) + 0.2, 0.12) * CFrame.Angles(0, 0.3, 0), 0.5, 0.25, 0.25, "blue", "Book"))
	moveAll(sway, "swing", hub, "X", 1.3, 0.12)
	-- a lantern off the east post
	box(m, f, 1.75, 1.6, 0.3, 0.25, 0.25, 0.5, "steel_dark", "Hook")
	lantern(m, f, 1.75, 1.2, 0.5, true)
	-- a stump with a drink, sandals, tufts
	cyl(m, f, 1.15, 0.25, 0.62, 0.75, 0.5, "wood", "Stump")
	cyl(m, f, 1.15, 0.31, 0.62, 0.5, 0.5, "sand_dark", "Rings")
	ball(m, f, 1.15, 0.72, 0.62, 0.5, "wood_dark", "Coconut")
	at(m, f, CFrame.new(1.25, 1.0, 0.6) * CFrame.Angles(0, 0, -0.35), 0.25, 0.5, 0.25, "pink", "Straw")
	at(m, f, CFrame.new(-0.45, 0.06, 0.7) * CFrame.Angles(0, 0.3, 0), 0.25, 0.25, 0.5, "maple", "Sandal")
	at(m, f, CFrame.new(-0.15, 0.06, 0.72) * CFrame.Angles(0, -0.15, 0), 0.25, 0.25, 0.5, "maple", "Sandal")
	tuft(m, f, -1.4, 0, 0.85)
	tuft(m, f, 1.45, 0, -0.85)
end

-- Picnic Table (4 x 3): two wide planks over a dark bed on A-frames of crossed legs, a cross rail at each end carrying
-- the two benches; a red and white checked cloth hanging over the front edge; a striped parasol at the back with a
-- fringe; a basket with a woven band, a lid tipped open, a handle and a cloth peeking out; plates with a slice of melon
-- and a sandwich, two cups, a jug of lemonade, a teapot steaming; a napkin left on a bench, tufts under it.
B.picnic = function(m, f)
	box(m, f, 0, 0.94, 0, 3.5, 0.25, 1.25, "wood_dark", "Bed")
	for _, z in { -0.33, 0.33 } do
		box(m, f, 0, 1.06, z, 3.5, 0.25, 0.5, "wood", "Plank")
	end
	for _, x in { -1.35, 1.35 } do
		for _, s in { -1, 1 } do
			bar(m, f, V(x, 0, s * 1.0), V(x, 0.9, -s * 0.15), 0.25, "wood_dark", "Leg")
		end
		box(m, f, x, 0.4, 0, 0.25, 0.25, 2.75, "wood_dark", "Rail")
	end
	for _, z in { -1.1, 1.1 } do
		box(m, f, 0, 0.6, z, 3.5, 0.25, 0.5, "wood", "Bench")
	end
	-- the cloth, checked, and its hem over the front edge
	for i = 0, 2 do
		for j = 0, 1 do
			box(m, f, -1.0 + i * 0.5, 1.21, -0.25 + j * 0.5, 0.5, 0.25, 0.5, if (i + j) % 2 == 0 then "berry_red" else "white", "Cloth")
		end
		box(m, f, -1.0 + i * 0.5, 1.0, 0.68, 0.5, 0.5, 0.25, if i % 2 == 0 then "white" else "berry_red", "Hem")
	end
	-- the parasol
	local px, pz = 1.0, -0.4
	box(m, f, px, 1.85, pz, 0.25, 2.0, 0.25, "white", "Pole")
	for k, d in { 2.0, 1.5, 1.0, 0.5 } do
		cyl(m, f, px, 2.6 + (k - 1) * 0.25, pz, d, 0.25, if k % 2 == 1 then "berry_red" else "white", "Parasol")
	end
	ball(m, f, px, 3.5, pz, 0.25, "gold", "Knob")
	ringOf(m, f, px, 2.38, pz, 0.88, 8, 0.25, 0.25, 0.25, "white", "Fringe", math.pi / 8)
	-- the basket
	local bx = -1.35
	box(m, f, bx, 1.44, 0, 0.75, 0.5, 0.5, "wood", "Basket")
	box(m, f, bx, 1.45, 0, 1.0, 0.25, 0.75, "wood_dark", "Weave")
	at(m, f, CFrame.new(bx, 1.78, -0.32) * CFrame.Angles(-0.9, 0, 0), 0.75, 0.25, 0.25, "sand_dark", "Lid")
	for _, x in { bx - 0.25, bx + 0.25 } do
		box(m, f, x, 1.88, 0, 0.25, 0.5, 0.25, "wood_dark", "Handle")
	end
	box(m, f, bx, 2.1, 0, 0.75, 0.25, 0.25, "wood_dark", "Handle")
	box(m, f, bx + 0.15, 1.72, 0.15, 0.25, 0.25, 0.25, "berry_red", "Napkin")
	-- plates, food, cups, a jug, the teapot
	cyl(m, f, -0.6, 1.38, 0.25, 0.5, 0.25, "white", "Plate")
	cyl(m, f, 0.05, 1.38, -0.25, 0.5, 0.25, "white", "Plate")
	box(m, f, -0.6, 1.5, 0.3, 0.5, 0.25, 0.25, "berry_red", "Melon")
	box(m, f, -0.6, 1.5, 0.18, 0.5, 0.25, 0.25, "green", "Rind")
	box(m, f, 0.05, 1.5, -0.25, 0.5, 0.25, 0.25, "cream", "Bread")
	box(m, f, 0.05, 1.52, -0.19, 0.5, 0.25, 0.25, "leaf", "Lettuce")
	cyl(m, f, -0.1, 1.58, 0.35, 0.25, 0.5, "blue", "Cup")
	cyl(m, f, 0.5, 1.58, 0.35, 0.25, 0.5, "yellow", "Cup")
	cyl(m, f, -0.6, 1.58, -0.3, 0.5, 0.5, "yellow", "Jug")
	cyl(m, f, -0.6, 1.9, -0.3, 0.5, 0.25, "white", "JugRim")
	box(m, f, -0.82, 1.62, -0.3, 0.25, 0.25, 0.25, "white", "JugHandle")
	ball(m, f, 1.4, 1.45, 0.25, 0.5, "pink", "Teapot")
	box(m, f, 1.4, 1.72, 0.25, 0.25, 0.25, 0.25, "white", "Lid")
	at(m, f, CFrame.new(1.12, 1.52, 0.25) * CFrame.Angles(0, 0, 0.6), 0.25, 0.25, 0.25, "white", "Spout")
	box(m, f, 0.9, 0.75, -1.15, 0.5, 0.25, 0.5, "paper", "Napkin")
	tuft(m, f, -0.4, 0, 0.0)
	tuft(m, f, 0.75, 0, 0.3)
end

-- Totem Pole (2 x 2): four carved blocks on a stone plinth with tufts of grass, dark wooden bands between them, a face
-- on each: round cream eyes, a yellow nose and a grin (red), an owl with white eyes, carved brows and a beak (yellow),
-- a fish with yellow eyes, a round pink mouth and gills on its sides (blue), a sleeper with leaf ears (green); a bird
-- on top with spread two-tone wings, a crest, white eyes and a beak.
B.totem = function(m, f)
	box(m, f, 0, 0.125, 0, 1.75, 0.25, 1.75, "rock", "Base")
	box(m, f, 0, 0.375, 0, 1.5, 0.25, 1.5, "rock_dark", "Plinth")
	tuft(m, f, 0.75, 0.25, 0.78)
	tuft(m, f, -0.78, 0.25, 0.75)
	local cols = { "berry_red", "yellow", "blue", "green" }
	local zf = 0.66 -- just proud of a block's face
	for i = 0, 3 do
		local y0 = 0.5 + i
		box(m, f, 0, y0 + 0.5, 0, 1.25, 1.0, 1.25, cols[i + 1], "Block")
		box(m, f, 0, y0 + 1.0, 0, 1.5, 0.25, 1.5, "wood_dark", "Band")
		if i == 0 then
			for _, s in { -1, 1 } do
				discZ(m, f, s * 0.3, y0 + 0.62, zf, 0.5, 0.25, "cream", "Eye")
				box(m, f, s * 0.3, y0 + 0.6, zf + 0.06, 0.25, 0.25, 0.25, "black", "Pupil")
			end
			box(m, f, 0, y0 + 0.38, zf + 0.06, 0.25, 0.5, 0.25, "yellow", "Nose")
			box(m, f, 0, y0 + 0.15, zf, 0.75, 0.25, 0.25, "cream", "Grin")
		elseif i == 1 then
			for _, s in { -1, 1 } do
				discZ(m, f, s * 0.3, y0 + 0.55, zf, 0.5, 0.25, "white", "Eye")
				box(m, f, s * 0.3, y0 + 0.55, zf + 0.06, 0.25, 0.25, 0.25, "black", "Pupil")
				at(m, f, CFrame.new(s * 0.3, y0 + 0.86, zf) * CFrame.Angles(0, 0, -s * 0.3), 0.5, 0.25, 0.25, "wood", "Brow")
			end
			box(m, f, 0, y0 + 0.28, zf + 0.06, 0.25, 0.5, 0.25, "orange", "Beak")
		elseif i == 2 then
			for _, s in { -1, 1 } do
				discZ(m, f, s * 0.3, y0 + 0.62, zf, 0.5, 0.25, "yellow", "Eye")
				box(m, f, s * 0.3, y0 + 0.6, zf + 0.06, 0.25, 0.25, 0.25, "black", "Pupil")
				box(m, f, s * 0.69, y0 + 0.5, 0, 0.25, 0.5, 0.5, "teal", "Gill")
			end
			discZ(m, f, 0, y0 + 0.25, zf, 0.5, 0.25, "pink", "Mouth")
		else
			for _, s in { -1, 1 } do
				box(m, f, s * 0.3, y0 + 0.6, zf, 0.5, 0.25, 0.25, "wood_dark", "Lid")
				at(m, f, CFrame.new(s * 0.72, y0 + 0.6, 0) * CFrame.Angles(0, 0, -s * 0.35), 0.25, 0.75, 0.5, "moss", "Ear")
			end
			box(m, f, 0, y0 + 0.4, zf + 0.06, 0.25, 0.25, 0.25, "yellow", "Nose")
			box(m, f, 0, y0 + 0.18, zf, 0.5, 0.25, 0.25, "berry_red", "Mouth")
		end
	end
	-- the bird on top
	box(m, f, 0, 4.95, 0, 0.75, 0.75, 0.75, "berry_red", "Bird")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.2, 5.1, 0.4, 0.25, 0.25, 0.25, "white", "Eye")
		at(m, f, CFrame.new(s * 0.6, 5.05, 0) * CFrame.Angles(0, 0, s * 0.25), 0.5, 0.5, 0.25, "orange", "Wing")
		at(m, f, CFrame.new(s * 0.86, 5.2, 0) * CFrame.Angles(0, 0, s * 0.25), 0.25, 0.5, 0.25, "yellow", "Feather")
	end
	box(m, f, 0, 4.88, 0.52, 0.25, 0.25, 0.5, "yellow", "Beak")
	box(m, f, 0, 5.45, -0.12, 0.25, 0.5, 0.25, "purple", "Crest")
end

-- Fountain (5 x 5): a round basin on square paving, a darker kerb at its foot, carved piers round its wall and a raised
-- rim of pale stones round the water with a shell spout on each side throwing an arc of water in; in the middle a
-- pedestal, a shaft, a wide bowl brimming with water that runs down over its edge in four places, a smaller shaft and
-- bowl over it pouring into the first, a finial and a jet with spray at its top and drops round it; lily pads (one in
-- flower), coins, a little white duck bobbing; a planter with a shrub in flower in three corners.
B.fountain = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.25, 5, "pavement", "Paving")
	cyl(m, f, 0, 0.09, 0, 4.75, 0.25, "rock_dark", "Kerb")
	cyl(m, f, 0, 0.5, 0, 4.5, 0.75, "rock", "Basin")
	ringOf(m, f, 0, 0.5, 0, 2.27, 8, 0.25, 0.75, 0.25, "rock_dark", "Pier", math.pi / 8)
	ringOf(m, f, 0, 0.98, 0, 2.1, 12, 1.25, 0.25, 0.5, "pavement", "Rim")
	cyl(m, f, 0, 0.85, 0, 4.0, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	-- a shell spout on the rim at each side, an arc of water from it
	for k = 0, 3 do
		local a = k * math.pi / 2
		local sa, ca = math.sin(a), math.cos(a)
		at(m, f, CFrame.new(sa * 2.05, 1.3, ca * 2.05) * CFrame.Angles(0, a + math.pi / 2, 0), 0.25, 0.5, 0.5, "cream", "Spout", "Cylinder")
		box(m, f, sa * 1.75, 1.3, ca * 1.75, 0.25, 0.25, 0.25, "shallow", "Arc"):SetAttribute("PixelWater", 2)
		box(m, f, sa * 1.5, 1.1, ca * 1.5, 0.25, 0.25, 0.25, "shallow", "Arc"):SetAttribute("PixelWater", 2)
	end
	-- the tiers
	cyl(m, f, 0, 0.9, 0, 1.5, 0.5, "rock", "Pedestal")
	cyl(m, f, 0, 1.5, 0, 0.75, 0.75, "pavement", "Shaft")
	cyl(m, f, 0, 1.85, 0, 1.5, 0.25, "rock", "Bowl")
	cyl(m, f, 0, 2.05, 0, 2.5, 0.25, "pavement", "Bowl")
	cyl(m, f, 0, 2.15, 0, 2.0, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	for k = 0, 3 do
		local a = math.pi / 4 + k * math.pi / 2
		at(m, f, CFrame.new(math.sin(a) * 1.35, 1.55, math.cos(a) * 1.35) * CFrame.Angles(0, a, 0), 0.5, 1.25, 0.25, "shallow", "Fall"):SetAttribute("PixelWater", 4)
	end
	cyl(m, f, 0, 2.6, 0, 0.5, 0.75, "pavement", "Shaft")
	cyl(m, f, 0, 2.95, 0, 0.75, 0.25, "rock", "Bowl")
	cyl(m, f, 0, 3.1, 0, 1.5, 0.25, "pavement", "Bowl")
	cyl(m, f, 0, 3.2, 0, 1.25, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	for _, a in { 0, math.pi / 2 } do
		at(m, f, CFrame.new(math.sin(a) * 0.85, 2.7, math.cos(a) * 0.85) * CFrame.Angles(0, a, 0), 0.5, 1.0, 0.25, "shallow", "Fall"):SetAttribute("PixelWater", 4)
	end
	ball(m, f, 0, 3.45, 0, 0.5, "pavement", "Finial")
	box(m, f, 0, 3.72, 0, 0.25, 0.25, 0.25, "steel", "Nozzle")
	box(m, f, 0, 4.0, 0, 0.25, 0.75, 0.25, "foam", "Jet"):SetAttribute("PixelWater", 2)
	ball(m, f, 0, 4.45, 0, 0.5, "foam", "Spray"):SetAttribute("PixelWater", 2)
	for _, c in { { 0.35, 4.1, 0.15 }, { -0.3, 3.9, 0.25 }, { 0.15, 3.8, -0.38 } } do
		box(m, f, c[1], c[2], c[3], 0.25, 0.25, 0.25, "shallow", "Drop"):SetAttribute("PixelWater", 2)
	end
	-- on the water
	for _, p in { { 1.05, -1.2 }, { -1.35, 0.55 }, { -0.55, 1.55 } } do
		cyl(m, f, p[1], 1.0, p[2], 0.5, 0.25, "leaf", "LilyPad")
	end
	ball(m, f, -0.5, 1.15, 1.58, 0.25, "pink", "Bloom")
	box(m, f, -0.9, 0.98, -1.1, 0.25, 0.25, 0.25, "gold", "Coin")
	box(m, f, 1.5, 0.98, 0.3, 0.25, 0.25, 0.25, "gold", "Coin")
	box(m, f, 0.45, 0.98, -1.6, 0.25, 0.25, 0.25, "gold", "Coin")
	local dx, dz = 0.55, 1.45
	local duck = V(dx, 1.1, dz)
	for _, p in { ball(m, f, dx, 1.1, dz, 0.5, "white", "Duck"), ball(m, f, dx + 0.2, 1.38, dz, 0.25, "white", "Duck"), box(m, f, dx + 0.38, 1.35, dz, 0.25, 0.25, 0.25, "orange", "Beak") } do
		move(p, "bob", duck, "Z", 1.5, 0.06)
	end
	-- planters in three corners (the back-left one stays clear)
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		local x, z = c[1] * 2.1, c[2] * 2.1
		box(m, f, x, 0.4, z, 0.5, 0.5, 0.5, "rock", "Planter")
		box(m, f, x, 0.65, z, 0.75, 0.25, 0.75, "pavement", "PlanterRim")
		ball(m, f, x, 1.05, z, 0.75, "leaf", "Shrub")
		ball(m, f, x + 0.15, 0.9, z + 0.18, 0.5, "leaf_dark", "Shrub")
		ball(m, f, x - 0.15, 1.3, z + 0.12, 0.25, "pink", "Bloom")
		ball(m, f, x + 0.2, 1.15, z - 0.1, 0.25, "white", "Bloom")
	end
end

-- Lighthouse (4 x 4): a round tower in five red and white bands narrowing as they climb, on a paved round plinth with a
-- stone ring at its foot; an arched door with a keystone, a knob and a step, a lantern by it, windows with sills up the
-- front and the east side, a red and white lifebuoy on a peg; a gallery on brackets with a black railing; an open lamp
-- room on four white posts where two glowing lenses turn round the light; a stepped red cap with a gold knob and a
-- weathervane that swings with the wind; an anchor leaning on the plinth, a coil of rope, a barrel and a crate,
-- boulders and grass round it.
B.lighthouse = function(m, f)
	cyl(m, f, 0, 0.125, 0, 4.0, 0.25, "rock", "Ring")
	cyl(m, f, 0, 0.25, 0, 3.5, 0.5, "pavement", "Plinth")
	ball(m, f, -1.6, 0.3, 0.35, 0.75, "rock_dark", "Boulder")
	ball(m, f, -1.6, 0.22, -0.3, 0.5, "rock", "Boulder")
	ball(m, f, 1.6, 0.28, -0.1, 0.75, "rock", "Boulder")
	tuft(m, f, 1.55, 0, 0.75)
	tuft(m, f, -1.0, 0, 1.6)
	-- the tower
	for i = 0, 4 do
		cyl(m, f, 0, 0.5 + 1.25 * i + 0.625, 0, 2.5 - 0.25 * i, 1.25, if i % 2 == 0 then "white" else "berry_red", "Tower")
	end
	-- windows: front on the second and fourth bands, east on the third
	for _, w in { { 0, 2.5, 1.125 }, { math.pi / 2, 3.75, 1.0 }, { 0, 5.0, 0.875 } } do
		local g = f * CFrame.Angles(0, w[1], 0)
		box(m, g, 0, w[2], w[3] - 0.06, 0.5, 0.75, 0.25, "wood_dark", "WindowFrame")
		box(m, g, 0, w[2] + 0.05, w[3], 0.25, 0.5, 0.25, "window", "Glass")
		box(m, g, 0, w[2] - 0.45, w[3] + 0.03, 0.75, 0.25, 0.25, "white", "Sill")
	end
	-- the door
	door(m, f * CFrame.new(0, 0.5, 0), 0, 1.15, 0.75, 1.25, "wood_dark")
	box(m, f, 0, 1.95, 1.2, 0.5, 0.25, 0.25, "pavement", "Keystone")
	box(m, f, 0.75, 1.92, 1.12, 0.25, 0.25, 0.25, "steel_dark", "Bracket")
	lantern(m, f, 0.75, 1.55, 1.2, true)
	-- the lifebuoy on its peg
	local bg = f * CFrame.Angles(0, 1.15, 0)
	box(m, bg, 0, 2.05, 1.28, 0.25, 0.25, 0.25, "steel_dark", "Peg")
	discZ(m, bg, 0, 1.55, 1.3, 0.75, 0.25, "berry_red", "Buoy")
	box(m, bg, 0, 1.55, 1.36, 0.75, 0.25, 0.25, "white", "BuoyBand")
	box(m, bg, 0, 1.55, 1.36, 0.25, 0.75, 0.25, "white", "BuoyBand")
	-- the gallery and its railing
	ringOf(m, f, 0, 6.6, 0, 0.95, 4, 0.25, 0.5, 0.5, "white", "Bracket", math.pi / 4)
	cyl(m, f, 0, 6.875, 0, 3.0, 0.25, "steel_dark", "Gallery")
	for k = 0, 7 do
		local a, b = k * TAU / 8, (k + 1) * TAU / 8
		local p = V(math.sin(a) * 1.35, 7.25, math.cos(a) * 1.35)
		box(m, f, p.X, 7.25, p.Z, 0.25, 0.5, 0.25, "black", "RailPost")
		bar(m, f, V(p.X, 7.5, p.Z), V(math.sin(b) * 1.35, 7.5, math.cos(b) * 1.35), 0.25, "black", "Rail")
	end
	-- the lamp room: four posts round two glowing lenses that turn round the light
	cyl(m, f, 0, 7.125, 0, 1.5, 0.25, "berry_red", "LampBase")
	ringOf(m, f, 0, 7.75, 0, 0.75, 4, 0.25, 1.0, 0.25, "white", "Mullion", math.pi / 4)
	local hub = V(0, 7.75, 0)
	for _, p in { box(m, f, 0, 7.75, 0, 0.25, 1.0, 0.25, "steel_dark", "Spindle"), box(m, f, 0, 7.75, 0.3, 0.5, 0.5, 0.25, "yellow", "Lens", true), box(m, f, 0, 7.75, -0.3, 0.5, 0.5, 0.25, "yellow", "Lens", true) } do
		move(p, "spin", hub, "Y", 1.2)
	end
	-- the cap, its knob and the weathervane
	for k, d in { 2.0, 1.5, 1.0, 0.5 } do
		cyl(m, f, 0, 8.375 + (k - 1) * 0.25, 0, d, 0.25, "berry_red", "Cap")
	end
	ball(m, f, 0, 9.4, 0, 0.5, "gold", "Knob")
	box(m, f, 0, 9.9, 0, 0.25, 0.75, 0.25, "steel_dark", "VaneRod")
	local vane = V(0, 10.1, 0)
	move(box(m, f, 0.1, 10.1, 0, 1.0, 0.25, 0.25, "black", "Vane"), "swing", vane, "Y", 0.6, 0.3)
	move(box(m, f, -0.35, 10.2, 0, 0.25, 0.5, 0.25, "black", "VaneTail"), "swing", vane, "Y", 0.6, 0.3)
	-- on the plinth: an anchor, a coil of rope, a barrel and a crate
	local ag = f * CFrame.new(-1.15, 0.5, 1.15) * CFrame.Angles(0, -0.8, 0) * CFrame.Angles(-0.3, 0, 0)
	box(m, ag, 0, 0.6, 0, 0.25, 1.0, 0.25, "steel_dark", "Anchor")
	ball(m, ag, 0, 1.2, 0, 0.5, "steel_dark", "AnchorRing")
	box(m, ag, 0, 0.9, 0, 0.75, 0.25, 0.25, "wood_dark", "Stock")
	for _, s in { -1, 1 } do
		at(m, ag, CFrame.new(s * 0.25, 0.25, 0) * CFrame.Angles(0, 0, s * 0.8), 0.25, 0.5, 0.25, "steel_dark", "Arm")
		box(m, ag, s * 0.42, 0.42, 0, 0.25, 0.25, 0.25, "steel", "Fluke")
	end
	cyl(m, f, 1.1, 0.625, 1.15, 0.75, 0.25, "straw", "Rope")
	cyl(m, f, 1.1, 0.69, 1.15, 0.5, 0.25, "sand_dark", "Rope")
	box(m, f, 1.1, 0.75, 1.15, 0.25, 0.25, 0.25, "wood_dark", "RopeEnd")
	cyl(m, f, 0.85, 0.875, -1.3, 0.5, 0.75, "wood", "Barrel")
	cyl(m, f, 0.85, 0.875, -1.3, 0.75, 0.25, "steel_dark", "Hoop")
	box(m, f, 1.4, 0.75, -0.6, 0.5, 0.5, 0.5, "wood", "Crate")
	box(m, f, 1.4, 0.75, -0.6, 0.75, 0.25, 0.75, "wood_dark", "Strap")
end

-- Guardian Statue (3 x 3): an original guardian of the islets in gold on a carved plinth: two steps, a moulded base,
-- white corner pilasters, a cornice and a white slab; a gold plaque with its line of letters on the front, a gold
-- medallion with a blue boss on the east. The guardian: clawed feet, a round body with a pale belly, a teal sash with a
-- gem at the shoulder and a teal cape behind, a round head with a muzzle, dark eyes, tall ears with orange insides and
-- a circlet with a gem; one arm holds up a glinting pearl, the other a staff topped with a shell. Braziers burn at
-- three corners of the slab, a gold band under its cornice, waves carved under the plaque, ivy up a back corner;
-- flowers, coins, fruit and two lit candles left on the bottom step, moss in its corners.
B.statue = function(m, f)
	box(m, f, 0, 0.125, 0, 3.0, 0.25, 3.0, "rock", "Step")
	box(m, f, 0, 0.375, 0, 2.5, 0.25, 2.5, "pavement", "Step")
	box(m, f, 0, 1.125, 0, 1.75, 1.25, 1.75, "steel", "Plinth")
	box(m, f, 0, 0.625, 0, 2.0, 0.25, 2.0, "steel_dark", "Base")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, f, c[1] * 0.85, 1.25, c[2] * 0.85, 0.25, 1.0, 0.25, "white", "Pilaster")
	end
	box(m, f, 0, 1.625, 0, 2.0, 0.25, 2.0, "gold", "Band")
	box(m, f, 0, 1.875, 0, 2.0, 0.25, 2.0, "steel_dark", "Cornice")
	box(m, f, 0, 2.125, 0, 1.75, 0.25, 1.75, "white", "Slab")
	box(m, f, 0, 1.25, 0.9, 1.0, 0.5, 0.25, "gold", "Plaque")
	box(m, f, 0, 1.25, 0.96, 0.5, 0.25, 0.25, "wood_dark", "Letters")
	for k, x in { -0.3, 0, 0.3 } do
		box(m, f, x, 0.875, 0.9, 0.25, 0.25, 0.25, if k == 2 then "teal" else "blue", "Wave")
	end
	discX(m, f, 0.92, 1.12, 0, 0.75, 0.25, "gold", "Medallion")
	discX(m, f, 0.98, 1.12, 0, 0.25, 0.25, "blue", "Boss")
	box(m, f, 1.0, 1.1, -0.85, 0.25, 0.75, 0.25, "leaf", "Ivy")
	box(m, f, 0.95, 1.4, -1.0, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	ball(m, f, 1.05, 1.35, -0.75, 0.25, "white", "Bloom")
	-- braziers on three corners of the slab
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		local x, z = c[1] * 0.72, c[2] * 0.72
		box(m, f, x, 2.35, z, 0.25, 0.25, 0.25, "steel_dark", "BrazierFoot")
		cyl(m, f, x, 2.5, z, 0.5, 0.25, "gold", "Brazier")
		box(m, f, x, 2.75, z, 0.25, 0.5, 0.25, "orange", "Flame", true)
		box(m, f, x + 0.04, 3.0, z + 0.04, 0.25, 0.25, 0.25, "yellow", "Tip", true)
	end
	-- the guardian, standing on the slab (2.25)
	for _, s in { -1, 1 } do
		box(m, f, s * 0.3, 2.375, 0.12, 0.5, 0.25, 0.75, "gold", "Foot")
		for _, c in { -0.12, 0.12 } do
			box(m, f, s * 0.3 + c, 2.375, 0.52, 0.25, 0.25, 0.25, "yellow", "Claw")
		end
		ball(m, f, s * 0.3, 2.78, -0.05, 0.75, "gold", "Thigh")
	end
	ball(m, f, 0, 3.5, -0.1, 1.5, "gold", "Body")
	ball(m, f, 0, 3.35, 0.3, 1.0, "yellow", "Belly")
	at(m, f, CFrame.new(0.05, 3.85, 0.5) * CFrame.Angles(0, 0, 0.75), 0.25, 1.25, 0.25, "teal", "Sash")
	ball(m, f, -0.38, 4.15, 0.42, 0.25, "crystal", "Sparkle")
	at(m, f, CFrame.new(0, 3.3, -0.82) * CFrame.Angles(0.12, 0, 0), 1.25, 1.75, 0.25, "teal", "Cape")
	ball(m, f, 0, 4.75, 0.05, 1.25, "gold", "Head")
	ball(m, f, 0, 4.55, 0.6, 0.5, "yellow", "Muzzle")
	box(m, f, 0, 4.7, 0.82, 0.25, 0.25, 0.25, "wood_dark", "Nose")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.25, 4.92, 0.55, 0.25, 0.25, 0.25, "night", "Eye")
		at(m, f, CFrame.new(s * 0.42, 5.6, 0) * CFrame.Angles(0, 0, -s * 0.25), 0.25, 1.0, 0.5, "gold", "Ear")
		at(m, f, CFrame.new(s * 0.42, 5.55, 0.12) * CFrame.Angles(0, 0, -s * 0.25), 0.25, 0.75, 0.25, "orange", "EarIn")
	end
	cyl(m, f, 0, 5.2, 0.05, 1.0, 0.25, "yellow", "Circlet")
	box(m, f, 0, 5.2, 0.55, 0.25, 0.25, 0.25, "crystal", "Sparkle")
	-- the arm that holds up the pearl
	ball(m, f, 0.68, 4.05, 0, 0.5, "gold", "Shoulder")
	bar(m, f, V(0.72, 4.1, 0), V(0.95, 4.9, 0.1), 0.5, "gold", "Arm")
	ball(m, f, 0.95, 5.05, 0.1, 0.5, "yellow", "Paw")
	ball(m, f, 0.95, 5.55, 0.1, 0.75, "pink", "Sparkle")
	box(m, f, 0.83, 5.68, 0.32, 0.25, 0.25, 0.25, "white", "Shine")
	-- the arm with the staff
	ball(m, f, -0.68, 4.05, 0, 0.5, "gold", "Shoulder")
	bar(m, f, V(-0.72, 3.95, 0), V(-0.96, 3.25, 0.22), 0.5, "gold", "Arm")
	ball(m, f, -0.98, 3.1, 0.25, 0.5, "yellow", "Paw")
	box(m, f, -0.98, 3.6, 0.25, 0.25, 2.75, 0.25, "wood_dark", "Staff")
	discZ(m, f, -0.98, 5.1, 0.25, 0.75, 0.25, "cream", "Shell")
	box(m, f, -0.98, 5.05, 0.31, 0.25, 0.5, 0.25, "sand_dark", "Rib")
	-- flowers, coins, fruit and two candles left on the bottom step, moss in its corners
	flower(m, f, -0.85, 0.25, 1.35, "pink")
	flower(m, f, -0.6, 0.25, 1.38, "white")
	for _, x in { -0.25, 0.0 } do
		box(m, f, x, 0.31, 1.35, 0.25, 0.25, 0.25, "gold", "Coin")
	end
	ball(m, f, 0.32, 0.36, 1.36, 0.25, "berry_red", "Fruit")
	ball(m, f, 0.52, 0.36, 1.38, 0.25, "orange", "Fruit")
	for _, x in { 0.8, 1.05 } do
		box(m, f, x, 0.5, 1.36, 0.25, 0.5, 0.25, "cream", "Candle")
		box(m, f, x, 0.85, 1.36, 0.25, 0.25, 0.25, "yellow", "Flame", true)
	end
	box(m, f, 1.35, 0.3, 1.25, 0.25, 0.25, 0.5, "moss", "Moss")
	box(m, f, -1.25, 0.3, 1.35, 0.5, 0.25, 0.25, "moss", "Moss")
end


------------------------------------------------------------------ the town and the city (GAME_DESIGN 4.1)


------------------------------------------------------------------ boosts


------------------------------------------------------------------ paths (2 x 2 tiles, flush with the grass)
B.dirtpath = function(m, f)
	box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand_dark", "Path")
	box(m, f, -0.5, 0.05, 0.4, 0.15, 0.04, 0.12, "rock", "Pebble")
	box(m, f, 0.6, 0.05, -0.5, 0.12, 0.04, 0.12, "rock_dark", "Pebble")
end
B.stonepath = function(m, f)
	box(m, f, 0, 0.02, 0, 2, 0.04, 2, "sand", "Path")
	for _, s in { { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } } do
		box(m, f, s[1], 0.05, s[2], 0.85, 0.06, 0.85, if (s[1] + s[2]) == 0 then "rock_dark" else "rock", "Stone")
	end
end
B.brickroad = function(m, f)
	-- red bricks in a running bond: a slab, two mortar courses, the joints staggered course to course
	box(m, f, 0, 0.03, 0, 2, 0.06, 2, "berry_red", "Road")
	for _, z in { -0.34, 0.33 } do
		box(m, f, 0, 0.065, z, 2, 0.01, 0.06, "rock_dark", "Mortar")
	end
	for _, j in { { -0.5, -0.67 }, { 0.5, -0.67 }, { 0, 0 }, { -0.5, 0.67 }, { 0.5, 0.67 } } do
		box(m, f, j[1], 0.065, j[2], 0.06, 0.01, 0.6, "rock_dark", "Joint")
	end
end
B.marblewalk = function(m, f)
	box(m, f, 0, 0.03, 0, 2, 0.06, 2, "white", "Marble")
	box(m, f, 0, 0.07, 0, 1.9, 0.02, 0.08, "gold", "Inlay")
	box(m, f, 0, 0.07, 0, 0.08, 0.02, 1.9, "gold", "Inlay")
	box(m, f, 0, 0.08, 0, 0.3, 0.02, 0.3, "chalk", "Star")
end

------------------------------------------------------------------ town decor
B.fence = function(m, f)
	for k = 0, 4 do
		box(m, f, -0.8 + k * 0.4, 0.35, 0, 0.12, 0.7, 0.08, "white", "Picket")
		wedge(m, f, -0.8 + k * 0.4, 0.76, 0, 0.12, 0.12, 0.08, "white", 0, "Point")
	end
	box(m, f, 0, 0.5, 0, 1.9, 0.08, 0.06, "white", "Rail")
	box(m, f, 0, 0.22, 0, 1.9, 0.08, 0.06, "white", "Rail")
end

-- Sandcastle (2 x 2): a castle patted out of wet sand on a round patch of beach: a keep with merlons along its front
-- and east walls, four round towers moulded from a bucket (each with a lip round its top), a taller middle tower with a
-- red flag on a stick, dark slit windows, a gate of driftwood under an arch, shells pressed into the wall; a moat of
-- seawater in front with a plank across it to the gate, a red bucket turned out upside down and a blue spade stuck in
-- the sand.
B.sandcastle = function(m, f)
	cyl(m, f, 0, 0.0, 0, 2.0, 0.25, "sand", "Beach")
	local cz = -0.15
	box(m, f, 0, 0.5, cz, 1.0, 0.75, 1.0, "sand", "Keep")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.2, 1.0, cz + 0.375, 0.25, 0.25, 0.25, "sand_dark", "Merlon")
		box(m, f, 0.375, 1.0, cz + s * 0.2, 0.25, 0.25, 0.25, "sand_dark", "Merlon")
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = c[1] * 0.45, cz + c[2] * 0.45
		cyl(m, f, x, 0.5, z, 0.5, 0.75, "sand_dark", "Tower")
		cyl(m, f, x, 1.0, z, 0.75, 0.25, "sand", "Lip")
	end
	cyl(m, f, 0, 1.125, cz, 0.5, 0.5, "sand_dark", "Tower")
	cyl(m, f, 0, 1.45, cz, 0.75, 0.25, "sand", "Lip")
	box(m, f, 0, 1.9, cz, 0.25, 0.75, 0.25, "wood_dark", "Stick")
	box(m, f, 0.25, 2.12, cz, 0.5, 0.25, 0.25, "berry_red", "Flag")
	-- windows, the gate, shells in the wall
	for _, s in { -1, 1 } do
		box(m, f, s * 0.45, 0.62, cz + 0.68, 0.25, 0.25, 0.25, "hair_brown", "Window")
	end
	box(m, f, 0, 1.15, cz + 0.2, 0.25, 0.25, 0.25, "hair_brown", "Window")
	box(m, f, 0, 0.38, cz + 0.47, 0.5, 0.5, 0.25, "wood_dark", "Gate")
	box(m, f, 0, 0.72, cz + 0.47, 0.75, 0.25, 0.25, "sand_dark", "Arch")
	ball(m, f, 0.22, 0.55, cz + 0.52, 0.25, "pink", "Shell")
	ball(m, f, 0.52, 0.5, cz - 0.05, 0.25, "white", "Shell")
	-- the moat and its plank, the bucket and the spade
	box(m, f, -0.25, 0.03, 0.82, 1.0, 0.25, 0.25, "shallow", "Moat"):SetAttribute("PixelWater", 2)
	box(m, f, 0, 0.18, 0.62, 0.5, 0.25, 0.75, "wood", "Plank")
	cyl(m, f, 0.7, 0.375, 0.74, 0.5, 0.5, "berry_red", "Bucket")
	cyl(m, f, 0.7, 0.66, 0.74, 0.25, 0.25, "yellow", "BucketBase")
	local sp = f * CFrame.new(-0.74, 0, 0.6) * CFrame.Angles(0.2, 0, -0.15)
	box(m, sp, 0, 0.2, 0, 0.5, 0.25, 0.25, "teal", "Spade")
	box(m, sp, 0, 0.6, 0, 0.25, 0.75, 0.25, "blue", "SpadeHandle")
	box(m, sp, 0, 1.0, 0, 0.5, 0.25, 0.25, "blue", "Grip")
end

-- Rock Garden (2 x 2): a frame of dark timber round pale raked gravel: lines raked across its front, rings raked round
-- a big stone of two greys with moss on its shoulder and round a cairn of three flat stones, a smaller pale stone, a
-- mossy hummock, a little pine in the back corner, a bamboo rake left on the frame.
B.rockgarden = function(m, f)
	for k = 0, 3 do
		local g = f * CFrame.Angles(0, k * math.pi / 2, 0)
		box(m, g, -0.125, 0.19, 0.875, 1.75, 0.25, 0.25, "wood_dark", "Frame")
	end
	box(m, f, 0, 0.08, 0, 1.75, 0.25, 1.75, "sand", "Gravel")
	for _, z in { 0.38, 0.62 } do
		box(m, f, -0.38, 0.16, z, 0.75, 0.25, 0.25, "sand_dark", "Rake")
	end
	ringOf(m, f, -0.2, 0.16, -0.2, 0.4, 8, 0.5, 0.25, 0.25, "sand_dark", "Rake")
	ringOf(m, f, 0.35, 0.16, 0.35, 0.28, 6, 0.5, 0.25, 0.25, "sand_dark", "Rake")
	-- the big stone, the small one, the cairn
	ball(m, f, -0.2, 0.38, -0.2, 0.75, "rock", "Stone")
	ball(m, f, -0.05, 0.3, -0.03, 0.5, "rock_dark", "Stone")
	ball(m, f, -0.3, 0.68, -0.27, 0.5, "rock", "Stone")
	box(m, f, -0.4, 0.8, -0.2, 0.5, 0.25, 0.25, "moss", "Moss")
	ball(m, f, 0.12, 0.22, 0.02, 0.25, "pavement", "Stone")
	cyl(m, f, 0.35, 0.28, 0.35, 0.5, 0.25, "rock_dark", "Cairn")
	cyl(m, f, 0.35, 0.5, 0.35, 0.5, 0.25, "rock", "Cairn")
	ball(m, f, 0.35, 0.7, 0.35, 0.25, "pavement", "Cairn")
	ball(m, f, -0.5, 0.15, 0.08, 0.5, "moss", "Moss")
	-- a little pine in the back corner
	at(m, f, CFrame.new(0.5, 0.45, -0.5) * CFrame.Angles(0, 0, 0.2), 0.25, 0.5, 0.25, "wood_dark", "Trunk")
	ball(m, f, 0.5, 0.75, -0.5, 0.5, "leaf_dark", "Pine")
	ball(m, f, 0.42, 1.05, -0.48, 0.5, "leaf", "Pine")
	ball(m, f, 0.62, 0.95, -0.55, 0.25, "leaf_dark", "Pine")
	-- a bamboo rake left on the frame
	box(m, f, -0.2, 0.42, 0.875, 1.0, 0.25, 0.25, "bamboo", "RakeHandle")
	box(m, f, 0.4, 0.42, 0.75, 0.25, 0.25, 0.5, "straw", "RakeHead")
end

B.hedge = function(m, f)
	box(m, f, 0, 0.45, 0, 2.9, 0.9, 0.8, "leaf_dark", "Hedge")
	box(m, f, 0, 0.92, 0, 2.7, 0.12, 0.6, "leaf", "Top")
	for _, x in { -1.0, 0.2, 1.1 } do
		box(m, f, x, 0.6, 0.41, 0.12, 0.12, 0.04, "pink", "Flower")
	end
end

-- Lamp Post (1 x 1): a garden lamp on a square paving stone: a stepped iron base, the post with two collars, a tall
-- lantern of lit glass with a bar down its front on a tray under a stepped cap with a gold finial; an arm with a brace
-- holding out a hanging basket of leaves and flowers that sways on its hook; a flower and a tuft at its foot.
B.lamppost = function(m, f)
	local px, pz = -0.12, 0 -- (the post stands west of the middle: the basket hangs off its east side)
	box(m, f, 0, 0.0, 0, 1.0, 0.25, 1.0, "pavement", "Paving")
	box(m, f, px, 0.19, pz, 0.75, 0.25, 0.75, "black", "LampBase")
	box(m, f, px, 0.44, pz, 0.5, 0.25, 0.5, "steel_dark", "LampBase")
	box(m, f, px, 1.5, pz, 0.25, 2.0, 0.25, "steel_dark", "LampPost")
	for _, y in { 0.9, 2.25 } do
		box(m, f, px, y, pz, 0.5, 0.25, 0.5, "black", "Collar")
	end
	box(m, f, px, 2.6, pz, 0.75, 0.25, 0.75, "steel_dark", "LampTray")
	box(m, f, px, 3.1, pz, 0.5, 0.75, 0.5, "yellow", "LampLight", true)
	box(m, f, px, 3.1, pz + 0.2, 0.25, 0.75, 0.25, "black", "LampBar")
	box(m, f, px, 3.6, pz, 0.75, 0.25, 0.75, "steel_dark", "LampCap")
	box(m, f, px, 3.85, pz, 0.25, 0.25, 0.25, "black", "LampCap")
	ball(m, f, px, 4.05, pz, 0.25, "gold", "Finial")
	-- the arm and the hanging basket (it sways on its hook)
	local hx, hy = 0.25, 2.0
	box(m, f, 0.07, hy, 0, 0.5, 0.25, 0.25, "black", "Arm")
	bar(m, f, V(px, 1.7, 0), V(0.1, 1.95, 0), 0.25, "black", "Brace")
	local hub = V(hx, hy, 0)
	moveAll({
		box(m, f, hx, 1.82, 0, 0.25, 0.25, 0.25, "steel_dark", "Chain"),
		cyl(m, f, hx, 1.5, 0, 0.5, 0.25, "wood", "Basket"),
		cyl(m, f, hx, 1.3, 0, 0.25, 0.25, "wood_dark", "Basket"),
		ball(m, f, hx, 1.68, 0, 0.5, "leaf", "Plant"),
		box(m, f, hx + 0.1, 1.3, 0.15, 0.25, 0.5, 0.25, "leaf_dark", "Trail"),
		ball(m, f, hx - 0.1, 1.82, 0.15, 0.25, "pink", "Bloom"),
		ball(m, f, hx + 0.12, 1.75, -0.1, 0.25, "white", "Bloom"),
	}, "swing", hub, "X", 1.6, 0.14)
	flower(m, f, 0.3, 0.125, -0.32, "purple")
	tuft(m, f, -0.26, 0.1, 0.28)
end

-- Street Lamp (1 x 1): a tall iron lamp of the town on a square stone: a black base, a plinth with a gold plate, a
-- column with two collars, a crossbar on two scrolled brackets with a lantern standing on each end (the lit glass, a
-- cap and a gold knob), a gold finial and knob on top; a red banner with a gold fringe on a bracket at the front, two
-- street signs (blue and green) pointing two ways.
B.streetlamp = function(m, f)
	box(m, f, 0, 0.0, 0, 1.0, 0.25, 1.0, "rock", "Paving")
	box(m, f, 0, 0.25, 0, 0.75, 0.25, 0.75, "black", "LampBase")
	box(m, f, 0, 0.62, 0, 0.5, 0.5, 0.5, "steel_dark", "Plinth")
	box(m, f, 0, 0.62, 0.22, 0.25, 0.25, 0.25, "gold", "Plate")
	box(m, f, 0, 1.8, 0, 0.25, 1.75, 0.25, "steel_dark", "LampPost")
	for _, y in { 1.0, 2.3 } do
		box(m, f, 0, y, 0, 0.5, 0.25, 0.5, "black", "Collar")
	end
	box(m, f, 0, 2.6, 0, 1.0, 0.25, 0.25, "black", "LampArm")
	for _, s in { -1, 1 } do
		bar(m, f, V(s * 0.1, 2.15, 0), V(s * 0.36, 2.5, 0), 0.25, "steel_dark", "Scroll")
		box(m, f, s * 0.33, 2.98, 0, 0.25, 0.5, 0.25, "yellow", "LampLight", true)
		box(m, f, s * 0.33, 3.35, 0, 0.5, 0.25, 0.5, "black", "LampCap")
		ball(m, f, s * 0.33, 3.55, 0, 0.25, "gold", "Knob")
	end
	box(m, f, 0, 3.2, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 3.55, 0, 0.25, "gold", "Knob")
	-- the banner and the signs
	box(m, f, 0, 2.05, 0.25, 0.25, 0.25, 0.5, "black", "Bracket")
	box(m, f, 0, 1.6, 0.38, 0.25, 0.75, 0.25, "berry_red", "FlagBanner")
	box(m, f, 0, 1.17, 0.38, 0.25, 0.25, 0.25, "gold", "FlagFringe")
	box(m, f, 0.25, 1.4, 0, 0.5, 0.25, 0.25, "blue", "Sign")
	box(m, f, -0.25, 1.15, 0, 0.5, 0.25, 0.25, "green", "Sign")
end

-- Flower Arch (3 x 1): a white trellis arch over a path: on each side a planter box of soil holding two posts with
-- rungs between them, a low round arch of white slats over the top; roses and leaves climbing both sides and over the
-- top, trails of green hanging from it, and a little wooden sign with a pink heart hanging under its crown, swinging on
-- two strings.
B.flowerarch = function(m, f)
	local spring = 2.25 -- the arch springs here
	for _, s in { -1, 1 } do
		local x = s * 1.1
		box(m, f, x, 0.25, 0, 0.75, 0.5, 0.75, "wood", "Planter")
		box(m, f, x, 0.5, 0, 0.75, 0.25, 0.75, "wood_dark", "PlanterRim")
		box(m, f, x, 0.56, 0, 0.5, 0.25, 0.5, "hair_brown", "Soil")
		for _, z in { -0.25, 0.25 } do
			box(m, f, x, 1.375, z, 0.25, 1.75, 0.25, "white", "Post")
		end
		for _, y in { 1.0, 1.5, 2.0 } do
			box(m, f, x, y, 0, 0.25, 0.25, 0.25, "white", "Rung")
		end
	end
	-- the arch: slats along a low half ellipse
	local function archAt(a: number): Vector3
		return V(-math.cos(a) * 1.1, spring + math.sin(a) * 0.6, 0)
	end
	for k = 0, 7 do
		local p, q = archAt(k * math.pi / 8), archAt((k + 1) * math.pi / 8)
		at(m, f, CFrame.lookAt((p + q) / 2, q), 0.75, 0.25, (q - p).Magnitude + 0.15, "white", "Arch")
	end
	-- the sign hanging under the crown (it swings on its strings)
	local hub = V(0, spring + 0.5, 0)
	moveAll({
		box(m, f, -0.25, spring + 0.25, 0, 0.25, 0.5, 0.25, "straw", "String"),
		box(m, f, 0.25, spring + 0.25, 0, 0.25, 0.5, 0.25, "straw", "String"),
		box(m, f, 0, spring - 0.12, 0, 0.75, 0.5, 0.25, "wood", "Sign"),
		box(m, f, -0.12, spring - 0.06, 0.08, 0.25, 0.25, 0.25, "pink", "Heart"),
		box(m, f, 0.12, spring - 0.06, 0.08, 0.25, 0.25, 0.25, "pink", "Heart"),
		box(m, f, 0, spring - 0.2, 0.1, 0.25, 0.25, 0.25, "pink", "Heart"),
	}, "swing", hub, "X", 1.4, 0.15)
	-- the climbing roses
	local blooms = { "pink", "berry_red", "white" }
	for _, s in { -1, 1 } do
		for k, y in { 0.95, 1.55, 2.1 } do
			ball(m, f, s * 1.1, y, 0.2, 0.5, if k % 2 == 1 then "leaf" else "leaf_dark", "Vine")
			ball(m, f, s * (1.1 - 0.15), y + 0.15, 0.32, 0.25, blooms[(k + (if s > 0 then 1 else 0)) % 3 + 1], "Bloom")
		end
	end
	for k = 1, 5 do
		local p = archAt(k * math.pi / 6)
		ball(m, f, p.X, p.Y + 0.12, 0.15, 0.5, if k % 2 == 0 then "leaf_dark" else "leaf", "Vine")
		ball(m, f, p.X + 0.12, p.Y + 0.3, 0.28, 0.25, blooms[k % 3 + 1], "Bloom")
	end
	for _, x in { -0.62, 0.62 } do
		local y = archAt(math.acos(-x / 1.1)).Y
		box(m, f, x, y - 0.4, 0.25, 0.25, 0.75, 0.25, "leaf", "Trail")
		ball(m, f, x, y - 0.75, 0.3, 0.25, "pink", "Bloom")
	end
end

-- Gazebo (4 x 4): an eight-sided garden house on a round deck of planks (a darker edge round it) on a stone ring, a
-- stone step at the front: eight white posts with gold capitals, a white railing with a baluster in every side but the
-- open front; a white eave with a scalloped cream trim under it and a teal roof rising in bands (two of them white) to
-- a gold finial; a lantern hanging over the doorway that sways a little; inside a round table with a vase of flowers
-- and two steaming teacups, a cushioned bench round the back; a pot of flowers either side of the step.
B.gazebo = function(m, f)
	cyl(m, f, 0, 0.125, 0, 4.0, 0.25, "rock", "Ring")
	cyl(m, f, 0, 0.25, 0, 3.75, 0.5, "wood_dark", "Deck")
	cyl(m, f, 0, 0.44, 0, 3.5, 0.25, "wood", "Floor")
	box(m, f, 0, 0.19, 1.875, 1.25, 0.25, 0.25, "rock", "Step")
	local r = 1.55
	local posts: { Vector3 } = {}
	for k = 0, 7 do
		local a = (k + 0.5) * TAU / 8
		local p = V(math.sin(a) * r, 0, math.cos(a) * r)
		table.insert(posts, p)
		box(m, f, p.X, 1.56, p.Z, 0.25, 2.0, 0.25, "white", "Post")
		box(m, f, p.X, 2.5, p.Z, 0.5, 0.25, 0.5, "gold", "Capital")
	end
	for k = 1, 7 do
		local a, b = posts[k], posts[k + 1]
		bar(m, f, V(a.X, 1.3, a.Z), V(b.X, 1.3, b.Z), 0.25, "white", "Rail")
		local mid = (a + b) / 2
		box(m, f, mid.X, 0.94, mid.Z, 0.25, 0.75, 0.25, "cream", "Baluster")
	end
	-- the eave, its scalloped trim, the roof
	cyl(m, f, 0, 2.75, 0, 4.0, 0.25, "white", "Eave")
	ringOf(m, f, 0, 2.5, 0, 1.82, 12, 0.25, 0.25, 0.25, "cream", "Scallop", math.pi / 12)
	local bands = { 3.75, 3.25, 2.75, 2.25, 1.75, 1.25, 0.75 }
	for k, d in bands do
		cyl(m, f, 0, 3.0 + (k - 1) * 0.25, 0, d, 0.25, if k == 3 or k == 6 then "white" else "teal", "Roof")
	end
	box(m, f, 0, 4.85, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 5.15, 0, 0.5, "gold", "Knob")
	-- the lantern over the doorway
	local hub = V(0, 2.62, 1.35)
	moveAll({
		box(m, f, 0, 2.5, 1.35, 0.25, 0.25, 0.25, "steel_dark", "Chain"),
		box(m, f, 0, 2.3, 1.35, 0.5, 0.25, 0.5, "black", "LanternCap"),
		box(m, f, 0, 1.97, 1.35, 0.25, 0.5, 0.25, "yellow", "Lantern", true),
	}, "swing", hub, "X", 1.2, 0.1)
	-- inside: the table, a vase of flowers, teacups, the bench round the back
	cyl(m, f, 0, 0.69, 0, 0.5, 0.25, "wood_dark", "TableFoot")
	box(m, f, 0, 1.0, 0, 0.25, 0.5, 0.25, "wood_dark", "TableLeg")
	cyl(m, f, 0, 1.31, 0, 1.0, 0.25, "wood", "Table")
	box(m, f, -0.1, 1.56, -0.1, 0.25, 0.25, 0.25, "pink", "Vase")
	ball(m, f, -0.1, 1.78, -0.1, 0.25, "yellow", "Bloom")
	ball(m, f, 0.05, 1.86, -0.2, 0.25, "white", "Bloom")
	box(m, f, 0.25, 1.5, 0.15, 0.25, 0.25, 0.25, "white", "Mug")
	box(m, f, -0.3, 1.5, 0.22, 0.25, 0.25, 0.25, "white", "Mug")
	for k = -1, 1 do
		local a = math.pi + k * 0.62
		local g = f * CFrame.new(math.sin(a) * 1.15, 0, math.cos(a) * 1.15) * CFrame.Angles(0, a, 0)
		box(m, g, 0, 0.81, 0, 0.75, 0.5, 0.5, "wood", "Bench")
		box(m, g, 0, 1.05, 0.03, 0.5, 0.25, 0.5, if k == 0 then "berry_red" else "pink", "Cushion")
	end
	-- pots of flowers either side of the step
	for _, s in { -1, 1 } do
		local x, z = s * 1.5, 1.5
		box(m, f, x, 0.25, z, 0.5, 0.5, 0.5, "clay", "Pot")
		box(m, f, x, 0.5, z, 0.75, 0.25, 0.75, "pot", "PotRim")
		ball(m, f, x, 0.85, z, 0.75, "leaf", "Plant")
		ball(m, f, x - 0.15, 1.15, z + 0.12, 0.25, "purple", "Bloom")
		ball(m, f, x + 0.18, 1.0, z + 0.2, 0.25, "white", "Bloom")
	end
end

-- Topiary (2 x 2): a box tree clipped into two balls and a little bird, in a white planter on four dark feet with cream
-- corner posts, a teal band and a cream rim; dark soil, the trunk with a pink bow on it; each ball dark with a lighter
-- patch where the light finds its top; the bird with its head up and its tail cocked; pebbles round its feet and a pair
-- of shears left on the rim.
B.topiary = function(m, f)
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, f, c[1] * 0.5, 0.06, c[2] * 0.5, 0.25, 0.25, 0.25, "wood_dark", "Foot")
		box(m, f, c[1] * 0.6, 0.5, c[2] * 0.6, 0.25, 0.75, 0.25, "cream", "Corner")
	end
	box(m, f, 0, 0.5, 0, 1.25, 0.75, 1.25, "white", "Planter")
	box(m, f, 0, 0.35, 0, 1.5, 0.25, 1.5, "teal", "Band")
	box(m, f, 0, 0.9, 0, 1.5, 0.25, 1.5, "cream", "Rim")
	box(m, f, 0, 1.0, 0, 1.0, 0.25, 1.0, "hair_brown", "Soil")
	box(m, f, 0, 1.25, 0, 0.25, 0.5, 0.25, "wood_dark", "Trunk")
	box(m, f, 0, 1.3, 0.15, 0.5, 0.25, 0.25, "pink", "Bow")
	-- the balls, dark with a lit patch on the top left
	local low, high = V(0, 2.0, 0), V(0, 3.25, 0)
	ball(m, f, low.X, low.Y, low.Z, 1.25, "leaf_dark", "Clipped")
	local l1 = onBall(low, 1.25, -0.5, 0.75, 0.45, -0.32)
	ball(m, f, l1.X, l1.Y, l1.Z, 0.75, "leaf", "Clipped")
	box(m, f, 0, 2.69, 0, 0.25, 0.25, 0.25, "wood_dark", "Trunk")
	ball(m, f, high.X, high.Y, high.Z, 1.0, "leaf_dark", "Clipped")
	local l2 = onBall(high, 1.0, -0.5, 0.75, 0.45, -0.22)
	ball(m, f, l2.X, l2.Y, l2.Z, 0.5, "leaf", "Clipped")
	-- the bird on top
	ball(m, f, 0, 3.97, 0, 0.75, "leaf", "Bird")
	ball(m, f, 0.05, 4.37, 0.28, 0.5, "leaf", "Bird")
	box(m, f, 0.05, 4.35, 0.58, 0.25, 0.25, 0.25, "leaf_dark", "Beak")
	at(m, f, CFrame.new(0, 4.2, -0.4) * CFrame.Angles(0.7, 0, 0), 0.25, 0.25, 0.5, "leaf_dark", "Tail")
	-- pebbles, the shears
	for k, c in { { 0.85, 0.3 }, { 0.3, 0.85 }, { -0.85, 0.55 }, { 0.82, -0.5 } } do
		box(m, f, c[1], 0.08, c[2], 0.25, 0.25, 0.25, if k % 2 == 0 then "rock" else "pavement", "Pebble")
	end
	for _, s in { -1, 1 } do
		at(m, f, CFrame.new(0.42, 1.08, 0.62) * CFrame.Angles(0, s * 0.4, 0), 0.25, 0.25, 0.5, "steel", "Blade")
		box(m, f, 0.42 + s * 0.15, 1.08, 0.36, 0.25, 0.25, 0.25, "berry_red", "Grip")
	end
end

-- Bandstand (4 x 4): a round white stage on a stone ring with dark vents in its side and a step at the front, a floor
-- of planks; eight slender white posts with gold capitals, a railing with a baluster in every side but the open front;
-- a white eave hung with diamond bunting in four colours; a red roof rising in bands with two white stripes to a gold
-- finial and knob; the band's things on the floor: an upright piano with a sheet of music and its stool, a drum with
-- crossed sticks, a cymbal on a stand, two music stands.
B.bandstand = function(m, f)
	cyl(m, f, 0, 0.125, 0, 4.0, 0.25, "rock", "Ring")
	cyl(m, f, 0, 0.375, 0, 3.75, 0.75, "white", "Stage")
	for _, a in { -1.2, -0.6, 0.6, 1.2 } do
		at(m, f, CFrame.new(math.sin(a) * 1.85, 0.42, math.cos(a) * 1.85) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.pi / 4), 0.25, 0.25, 0.25, "rock_dark", "Vent")
	end
	box(m, f, 0, 0.25, 1.75, 1.25, 0.5, 0.5, "pavement", "Step")
	cyl(m, f, 0, 0.76, 0, 3.25, 0.25, "wood", "Floor")
	local r = 1.45
	local posts: { Vector3 } = {}
	for k = 0, 7 do
		local a = (k + 0.5) * TAU / 8
		local p = V(math.sin(a) * r, 0, math.cos(a) * r)
		table.insert(posts, p)
		box(m, f, p.X, 1.76, p.Z, 0.25, 1.75, 0.25, "white", "Post")
		box(m, f, p.X, 2.62, p.Z, 0.5, 0.25, 0.5, "gold", "Capital")
	end
	for k = 1, 7 do
		local a, b = posts[k], posts[k + 1]
		bar(m, f, V(a.X, 1.4, a.Z), V(b.X, 1.4, b.Z), 0.25, "white", "Rail")
		local mid = (a + b) / 2
		box(m, f, mid.X, 1.12, mid.Z, 0.25, 0.5, 0.25, "white", "Baluster")
	end
	cyl(m, f, 0, 2.875, 0, 3.75, 0.25, "white", "Eave")
	local flags = { "yellow", "teal", "pink", "purple" }
	for k = 0, 7 do
		local a = k * TAU / 8
		at(m, f, CFrame.new(math.sin(a) * 1.62, 2.55, math.cos(a) * 1.62) * CFrame.Angles(0, a, 0) * CFrame.Angles(0, 0, math.pi / 4), 0.5, 0.5, 0.25, flags[k % 4 + 1], "FlagBunting")
	end
	local roof = { 4.0, 3.25, 2.75, 2.25, 1.75, 1.25, 0.75 }
	for k, d in roof do
		cyl(m, f, 0, 3.125 + (k - 1) * 0.25, 0, d, 0.25, if k == 2 or k == 5 then "white" else "berry_red", "Roof")
	end
	box(m, f, 0, 5.0, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 5.3, 0, 0.5, "gold", "Knob")
	-- the piano and its stool
	box(m, f, -0.35, 1.26, -0.6, 1.0, 0.75, 0.5, "black", "Piano")
	box(m, f, -0.35, 1.2, -0.28, 1.0, 0.25, 0.25, "white", "Keys")
	box(m, f, -0.35, 1.7, -0.5, 0.5, 0.25, 0.25, "paper", "Music")
	box(m, f, -0.35, 1.0, 0.1, 0.25, 0.25, 0.25, "black", "StoolLeg")
	cyl(m, f, -0.35, 1.2, 0.1, 0.5, 0.25, "berry_red", "Stool")
	-- the drum, the cymbal
	cyl(m, f, 0.6, 1.135, -0.4, 0.75, 0.5, "blue", "Drum")
	cyl(m, f, 0.6, 1.41, -0.4, 0.75, 0.25, "white", "DrumHead")
	for _, s in { -1, 1 } do
		at(m, f, CFrame.new(0.6, 1.58, -0.4) * CFrame.Angles(0, s * 0.6, 0), 0.25, 0.25, 0.5, "wood", "Stick")
	end
	box(m, f, 0.95, 1.26, 0.0, 0.25, 0.75, 0.25, "steel_dark", "Stand")
	cyl(m, f, 0.95, 1.7, 0.0, 0.5, 0.25, "gold", "Cymbal")
	-- music stands
	for _, c in { { 0.3, 0.65 }, { -0.75, 0.5 } } do
		box(m, f, c[1], 1.26, c[2], 0.25, 0.75, 0.25, "steel_dark", "Stand")
		at(m, f, CFrame.new(c[1], 1.78, c[2]) * CFrame.Angles(-0.4, 0, 0), 0.5, 0.5, 0.25, "white", "Music")
	end
end

-- Clock Tower (3 x 3): a cream tower on a stone footing and step, pale corner stones up its edges, stone bands at its
-- foot and its middle; an arched door with a keystone, a lantern either side and a box of flowers either side of the
-- step; windows with sills on the front and the east; a clock stage between two cornices with a clock on the front and
-- the east (a gold rim, a white face, black hands that turn slowly); an open belfry on four pillars with a bell
-- swinging gently on its beam; a stepped spire in two blues on a gold eave, a gold finial and knob, a weathervane that
-- swings with the wind.
B.clocktower = function(m, f)
	box(m, f, 0, 0.125, 0, 3.0, 0.25, 3.0, "rock", "Footing")
	box(m, f, 0, 0.375, 0, 2.5, 0.25, 2.5, "pavement", "Step")
	box(m, f, 0, 2.5, 0, 2.0, 4.0, 2.0, "cream", "Tower")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, f, c[1] * 0.95, 2.625, c[2] * 0.95, 0.25, 3.75, 0.25, "pavement", "Quoin")
	end
	box(m, f, 0, 0.625, 0, 2.25, 0.25, 2.25, "rock", "Band")
	box(m, f, 0, 2.625, 0, 2.25, 0.25, 2.25, "rock", "Band")
	-- the door, its lanterns, boxes of flowers
	box(m, f, 0, 1.375, 1.0, 1.0, 1.25, 0.25, "wood_dark", "DoorFrame")
	box(m, f, 0, 1.25, 1.06, 0.75, 1.0, 0.25, "wood", "Door")
	box(m, f, 0.2, 1.3, 1.12, 0.25, 0.25, 0.25, "gold", "Knob")
	box(m, f, 0, 2.12, 1.03, 1.25, 0.25, 0.25, "rock", "Arch")
	box(m, f, 0, 2.2, 1.09, 0.25, 0.5, 0.25, "pavement", "Keystone")
	for _, s in { -1, 1 } do
		lantern(m, f, s * 0.68, 1.6, 1.12, true)
		box(m, f, s * 0.8, 0.375, 1.375, 0.75, 0.25, 0.25, "wood", "FlowerBox")
		ball(m, f, s * 0.8 - 0.15, 0.6, 1.38, 0.25, "berry_red", "Bloom")
		ball(m, f, s * 0.8 + 0.15, 0.6, 1.38, 0.25, "yellow", "Bloom")
		ball(m, f, s * 0.8, 0.55, 1.35, 0.25, "leaf", "Leaf")
	end
	-- windows: the front over the door, the east low and high
	for _, w in { { 0, 3.6 }, { math.pi / 2, 1.6 }, { math.pi / 2, 3.6 } } do
		window(m, f * CFrame.Angles(0, w[1], 0), 0, w[2], 0.95, 0.5, 0.75)
	end
	-- the clock stage and its two faces
	box(m, f, 0, 5.375, 0, 2.25, 1.75, 2.25, "wall", "ClockStage")
	box(m, f, 0, 4.5, 0, 2.5, 0.25, 2.5, "rock", "Cornice")
	box(m, f, 0, 6.25, 0, 2.5, 0.25, 2.5, "rock", "Cornice")
	local cy = 5.375
	for _, turn in { 0, math.pi / 2 } do
		local g = f * CFrame.Angles(0, turn, 0)
		discZ(m, g, 0, cy, 1.06, 1.5, 0.25, "gold", "ClockRim")
		discZ(m, g, 0, cy, 1.12, 1.25, 0.25, "white", "ClockFace")
		-- (the hands turn round the face's axis: Z on the front, X on the east; clockwise, slowly)
		local axis = if turn == 0 then "Z" else "X"
		local function hubAt(z: number): Vector3
			return if turn == 0 then V(0, cy, z) else V(z, cy, 0)
		end
		move(box(m, g, 0.15, cy, 1.3, 0.5, 0.25, 0.25, "black", "HourHand"), "spin", hubAt(1.3), axis, -0.05)
		move(box(m, g, 0, cy + 0.2, 1.36, 0.25, 0.5, 0.25, "black", "MinuteHand"), "spin", hubAt(1.36), axis, -0.15)
	end
	-- the belfry and its bell
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, f, c[1] * 0.85, 7.0, c[2] * 0.85, 0.25, 1.25, 0.25, "cream", "Pillar")
	end
	for _, turn in { 0, math.pi / 2 } do
		local g = f * CFrame.Angles(0, turn, 0)
		for _, s in { -1, 1 } do
			box(m, g, s * 0.6, 7.5, 0.85, 0.25, 0.25, 0.25, "cream", "ArchStone")
		end
	end
	box(m, f, 0, 7.75, 0, 2.25, 0.25, 2.25, "rock", "Lintel")
	K.log(m, f, 0, 7.5, 0, 1.75, 0.25, "wood_dark", "Beam")
	local bell = V(0, 7.5, 0)
	moveAll({
		box(m, f, 0, 7.3, 0, 0.25, 0.25, 0.25, "gold", "BellCrown"),
		cyl(m, f, 0, 7.1, 0, 0.75, 0.5, "gold", "Bell"),
		cyl(m, f, 0, 6.75, 0, 1.0, 0.25, "gold", "BellLip"),
		ball(m, f, 0, 6.58, 0, 0.25, "steel_dark", "Clapper"),
	}, "swing", bell, "X", 1.2, 0.15)
	-- the spire, its finial and the weathervane
	box(m, f, 0, 8.0, 0, 2.5, 0.25, 2.5, "gold", "Eave")
	for k, w in { 2.25, 1.75, 1.25, 0.75 } do
		box(m, f, 0, 8.375 + (k - 1) * 0.5, 0, w, 0.5, w, if k % 2 == 1 then "blue" else "slate", "Roof")
	end
	box(m, f, 0, 10.25, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 10.55, 0, 0.5, "gold", "Knob")
	local vane = V(0, 10.95, 0)
	move(box(m, f, 0.1, 10.95, 0, 1.0, 0.25, 0.25, "black", "Vane"), "swing", vane, "Y", 0.5, 0.3)
	move(box(m, f, -0.35, 11.05, 0, 0.25, 0.5, 0.25, "black", "VaneTail"), "swing", vane, "Y", 0.5, 0.3)
end

-- Canal Bridge (4 x 3): a stone-edged canal crossed by a little town bridge: a hump of paving slabs in two greys over a
-- low arch of brick with a pale keystone each side, a stone pier at each corner, the front two with lanterns, white
-- railings with a top rail along both sides, a box of flowers hung on each railing; a red rowboat with a seat and an
-- oar moored in the canal, bobbing; a mooring post on the near bank, lily pads with a flower.
B.canal = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.25, 3, "rock", "Bank")
	box(m, f, 0, 0.1, 0, 4, 0.25, 1.75, "water", "Canal"):SetAttribute("PixelWater", 2)
	for _, z in { -1.0, 1.0 } do
		box(m, f, 0, 0.2, z, 4, 0.25, 0.25, "rock_dark", "Edge")
	end
	-- the deck: seven slabs stepping over the hump (its height at z: the old planks')
	local function deckY(z: number): number
		return 0.55 - math.abs(z) / 1.2 * 0.35
	end
	for k = 0, 6 do
		local z = (k - 3) / 3 * 1.2
		box(m, f, 0, deckY(z), z, 1.5, 0.25, 0.5, if k % 2 == 0 then "pavement" else "rock", "Deck")
	end
	-- the brick arch under each side, a keystone in its middle
	for _, x in { -0.8, 0.8 } do
		for k = 0, 2 do
			local za, zb = -1.2 + k * 0.8, -1.2 + (k + 1) * 0.8
			span(m, f, V(x, deckY(za) - 0.2, za), V(x, deckY(zb) - 0.2, zb), 0.25, 0.25, "brick", "Arch")
		end
		box(m, f, x * 1.05, 0.38, 0, 0.25, 0.5, 0.25, "pavement", "Keystone")
	end
	-- the corner piers (lanterns on the front two), the railings, the flower boxes
	for _, s in { -1, 1 } do
		for _, t in { -1, 1 } do
			box(m, f, s * 0.875, 0.55, t * 1.25, 0.5, 0.75, 0.5, "rock", "Pier")
			box(m, f, s * 0.875, 1.05, t * 1.25, 0.5, 0.25, 0.5, "pavement", "PierCap")
			if t > 0 then
				lantern(m, f, s * 0.875, 1.42, 1.25, true)
			end
		end
		local x = s * 0.7
		local tops: { Vector3 } = { V(x, deckY(1.0) + 0.6, -1.0) }
		for _, z in { -0.6, 0, 0.6 } do
			box(m, f, x, deckY(z) + 0.36, z, 0.25, 0.5, 0.25, "white", "RailPost")
			table.insert(tops, V(x, deckY(z) + 0.6, z))
		end
		table.insert(tops, V(x, deckY(1.0) + 0.6, 1.0))
		for k = 1, #tops - 1 do
			bar(m, f, tops[k], tops[k + 1], 0.25, "white", "Rail")
		end
		box(m, f, s * 0.95, deckY(0) + 0.3, 0, 0.25, 0.25, 0.75, "wood", "FlowerBox")
		for _, z in { -0.25, 0, 0.25 } do
			ball(m, f, s * 0.95, deckY(0) + 0.48, z, 0.25, if z == 0 then "yellow" else "pink", "Bloom")
		end
	end
	-- the rowboat, bobbing at its mooring
	local bx, bz = 1.5, -0.3
	moveAll({
		box(m, f, bx, 0.25, bz, 1.0, 0.25, 0.5, "berry_red", "Boat"),
		box(m, f, bx, 0.31, bz, 0.75, 0.25, 0.25, "wood", "BoatFloor"),
		box(m, f, bx, 0.4, bz, 0.25, 0.25, 0.5, "wood_dark", "Seat"),
		at(m, f, CFrame.new(bx - 0.1, 0.42, bz + 0.05) * CFrame.Angles(0, 0.5, 0), 1.0, 0.25, 0.25, "wood", "Oar"),
	}, "bob", V(bx, 0.25, bz), "X", 1.2, 0.05)
	box(m, f, 1.45, 0.55, 1.12, 0.25, 0.75, 0.25, "wood_dark", "MooringPost")
	box(m, f, 1.45, 0.75, 1.12, 0.5, 0.25, 0.5, "straw", "Rope")
	for _, p in { { -1.4, -0.3 }, { -1.7, 0.4 } } do
		cyl(m, f, p[1], 0.24, p[2], 0.5, 0.25, "leaf", "LilyPad")
	end
	ball(m, f, -1.7, 0.38, 0.4, 0.25, "pink", "Bloom")
end

-- Grand Arch (5 x 2): a triumphal arch: two white piers on stone plinths with a cream course low on them and cream
-- imposts, red banners with gold fringes hung on their fronts and cream pilasters on their backs; a round arch of white
-- and cream stones with a gold keystone, white spandrels with gold rosettes, a row of dentils under the cornice front
-- and back; an attic between two white cornices with a gold plaque and its line of letters, garlands of leaves and
-- flowers either side of it; a gold star with a glinting gem on top, a flag either side; lanterns under the arch on the
-- piers' inner faces, paving through it, ivy at the piers' feet.
B.grandarch = function(m, f)
	for _, s in { -1, 1 } do
		local x = s * 1.85
		box(m, f, x, 0.25, 0, 1.25, 0.5, 1.75, "rock", "Plinth")
		box(m, f, x, 2.25, 0, 1.0, 3.5, 1.5, "white", "Pier")
		box(m, f, x, 4.0, 0, 1.25, 0.25, 1.75, "cream", "Impost")
		box(m, f, x, 1.0, 0, 1.25, 0.25, 1.75, "cream", "Course")
		-- a banner on the front, a pilaster on the back
		box(m, f, x, 3.6, 0.88, 0.75, 0.25, 0.25, "gold", "BannerRod")
		box(m, f, x, 2.5, 0.85, 0.5, 2.0, 0.25, "berry_red", "FlagBanner")
		box(m, f, x, 1.4, 0.85, 0.5, 0.25, 0.25, "gold", "FlagFringe")
		box(m, f, x, 2.25, -0.82, 0.5, 3.0, 0.25, "cream", "Pilaster")
		box(m, f, x, 0.62, -0.85, 0.75, 0.25, 0.25, "rock", "PilasterBase")
		box(m, f, x, 3.75, -0.85, 0.75, 0.25, 0.25, "gold", "PilasterCap")
		-- the spandrel over the pier, a rosette on it, the fill toward the crown
		box(m, f, x, 5.0, 0, 1.0, 1.75, 1.25, "white", "Spandrel")
		discZ(m, f, x, 5.0, 0.66, 0.5, 0.25, "gold", "Rosette")
		box(m, f, s * 1.0, 5.5, 0, 0.75, 0.75, 1.25, "white", "Spandrel")
		-- a lantern on the inner face, ivy at the foot
		box(m, f, s * 1.22, 3.3, 0, 0.25, 0.25, 0.25, "black", "Bracket")
		lantern(m, f, s * 1.12, 2.95, 0, true)
		box(m, f, s * 2.37, 0.9, 0.55, 0.25, 0.75, 0.25, "moss", "Ivy")
	end
	-- the arch
	for k = 0, 8 do
		local a = math.pi * (k + 0.5) / 9
		if k == 4 then
			at(m, f, CFrame.new(-math.cos(a) * 1.7, 4.125 + math.sin(a) * 1.7, 0), 0.75, 0.75, 1.5, "gold", "Keystone")
		else
			at(m, f, CFrame.new(-math.cos(a) * 1.6, 4.125 + math.sin(a) * 1.6, 0) * CFrame.Angles(0, 0, math.pi / 2 - a), 0.75, 0.5, 1.25, if k % 2 == 0 then "white" else "cream", "Voussoir")
		end
	end
	-- the attic, its plaque and garlands
	box(m, f, 0, 5.875, 0, 5.0, 0.25, 1.75, "white", "Cornice")
	for _, x in { -2.0, -1.5, -1.0, -0.5, 0.5, 1.0, 1.5, 2.0 } do
		for _, z in { -0.75, 0.75 } do
			box(m, f, x, 5.62, z, 0.25, 0.25, 0.5, "cream", "Dentil")
		end
	end
	box(m, f, 0, 6.5, 0, 4.75, 1.0, 1.5, "cream", "Attic")
	box(m, f, 0, 7.125, 0, 5.0, 0.25, 1.75, "white", "Cornice")
	box(m, f, 0, 6.5, 0.78, 2.0, 0.5, 0.25, "gold", "Plaque")
	box(m, f, 0, 6.5, 0.84, 1.25, 0.25, 0.25, "wood_dark", "Letters")
	for _, s in { -1, 1 } do
		for k, p in { { 2.1, 6.62 }, { 1.62, 6.25 }, { 1.18, 6.6 } } do
			ball(m, f, s * p[1], p[2], 0.72, 0.5, if k == 2 then "leaf_dark" else "leaf", "Garland")
		end
		ball(m, f, s * 1.62, 6.2, 0.86, 0.25, "pink", "Bloom")
		ball(m, f, s * 1.95, 6.5, 0.86, 0.25, "white", "Bloom")
		-- the flags
		box(m, f, s * 2.25, 8.125, 0, 0.25, 1.75, 0.25, "steel_dark", "FlagPole")
		ball(m, f, s * 2.25, 9.1, 0, 0.25, "gold", "Knob")
		box(m, f, s * 1.9, 8.6, 0, 0.5, 0.5, 0.25, "berry_red", "Flag")
	end
	-- the star on top
	box(m, f, 0, 7.375, 0, 1.0, 0.25, 0.75, "gold", "Pedestal")
	box(m, f, 0, 8.0, 0, 0.75, 0.75, 0.25, "gold", "Star")
	at(m, f, CFrame.new(0, 8.0, 0.03) * CFrame.Angles(0, 0, math.pi / 4), 0.75, 0.75, 0.25, "yellow", "Star")
	box(m, f, 0, 8.0, 0.2, 0.25, 0.25, 0.25, "crystal", "Sparkle")
	-- paving through the arch
	for _, x in { -0.85, 0, 0.85 } do
		box(m, f, x, 0.02, 0, 0.75, 0.25, 1.5, "pavement", "Paving")
	end
end

-- Observatory (4 x 4): a round cream drum on a stone footing and base band, white pilasters round it, a blue frieze and
-- a stone cornice, stone bases under the pilasters; a steel dome with a dark band at its foot and a gold knob, its open
-- slit and a brass telescope poking out of it, the two turning slowly to and fro; a blue door in a white frame under a
-- lintel, two steps, a lantern either side, arched windows; a brass telescope on a tripod, a framed board of the night
-- sky with its stars on an easel, a street lamp, pots and flowers by the door.
B.observatory = function(m, f)
	footing(m, f, 4, 4, "rock", 0.25)
	local cz = -0.2
	local c = V(0, 3.125, cz) -- the dome's middle
	cyl(m, f, 0, 0.5, cz, 3.25, 0.5, "rock", "Band")
	cyl(m, f, 0, 1.75, cz, 3.0, 2.25, "cream", "Drum")
	for k = 1, 7 do
		local a = k * TAU / 8
		at(m, f, CFrame.new(math.sin(a) * 1.5, 1.75, cz + math.cos(a) * 1.5) * CFrame.Angles(0, a, 0), 0.25, 2.0, 0.25, "white", "Pilaster")
		at(m, f, CFrame.new(math.sin(a) * 1.52, 0.875, cz + math.cos(a) * 1.52) * CFrame.Angles(0, a, 0), 0.5, 0.25, 0.25, "rock", "PilasterBase")
	end
	cyl(m, f, 0, 2.75, cz, 3.25, 0.25, "blue", "Frieze")
	cyl(m, f, 0, 3.0, cz, 3.5, 0.25, "rock", "Cornice")
	ball(m, f, c.X, c.Y, c.Z, 3.0, "steel", "Dome")
	cyl(m, f, 0, 3.25, cz, 3.25, 0.25, "steel_dark", "DomeBand")
	ball(m, f, 0, 4.65, cz, 0.5, "gold", "Knob")
	-- the slit and the telescope, turning slowly to and fro together
	local turning: { BasePart } = {}
	for _, e in { 30, 58 } do
		table.insert(turning, at(m, f, CFrame.new(c) * CFrame.Angles(-math.rad(e), 0, 0) * CFrame.new(0, 0, 1.45), 0.5, 0.75, 0.25, "night", "Slit"))
	end
	local tel = CFrame.new(c) * CFrame.Angles(-math.rad(40), 0, 0)
	table.insert(turning, at(m, f, tel * CFrame.new(0, 0, 1.6) * CFrame.Angles(0, math.pi / 2, 0), 1.5, 0.5, 0.5, "gold", "Telescope", "Cylinder"))
	table.insert(turning, at(m, f, tel * CFrame.new(0, 0, 2.2) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.75, 0.75, "wood_dark", "DewCap", "Cylinder"))
	table.insert(turning, at(m, f, tel * CFrame.new(0, 0, 2.3) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.5, 0.5, "night", "Lens", "Cylinder"))
	moveAll(turning, "swing", c, "Y", 0.6, 0.3)
	-- the door, its steps and lanterns
	local fz = cz + 1.5
	box(m, f, 0, 1.375, fz - 0.03, 1.0, 1.5, 0.25, "white", "DoorFrame")
	box(m, f, 0, 1.25, fz + 0.03, 0.75, 1.25, 0.25, "blue", "Door")
	box(m, f, 0.2, 1.25, fz + 0.09, 0.25, 0.25, 0.25, "gold", "Knob")
	box(m, f, 0, 2.25, fz + 0.06, 1.25, 0.25, 0.5, "white", "Lintel")
	box(m, f, 0, 0.375, fz + 0.4, 1.25, 0.25, 0.5, "pavement", "Step")
	box(m, f, 0, 0.62, fz + 0.15, 1.0, 0.25, 0.5, "pavement", "Step")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.7, 2.0, fz - 0.12, 0.25, 0.25, 0.25, "black", "Bracket")
		lantern(m, f, s * 0.7, 1.65, fz - 0.05, true)
	end
	-- arched windows round the drum
	for _, a in { -1.18, 1.18, 1.96 } do
		local g = f * CFrame.new(0, 0, cz) * CFrame.Angles(0, a, 0)
		box(m, g, 0, 1.75, 1.47, 0.5, 1.0, 0.25, "white", "WindowFrame")
		box(m, g, 0, 1.75, 1.53, 0.25, 0.75, 0.25, "window", "Glass")
		box(m, g, 0, 1.15, 1.53, 0.75, 0.25, 0.25, "rock", "Sill")
		box(m, g, 0, 2.35, 1.5, 0.75, 0.25, 0.25, "white", "WindowHead")
	end
	-- a telescope on a tripod, the star board on its easel, a lamp, flowers
	local tp = V(1.5, 0.25, 1.5)
	for k = 0, 2 do
		local a = k * TAU / 3 + 0.4
		bar(m, f, tp + V(math.sin(a) * 0.3, 0, math.cos(a) * 0.3), tp + V(0, 0.75, 0), 0.25, "wood", "Leg")
	end
	at(m, f, CFrame.new(1.5, 1.2, 1.45) * CFrame.Angles(0.5, 0.6, 0), 0.25, 0.25, 0.75, "gold", "Scope")
	box(m, f, 1.4, 1.05, 1.62, 0.25, 0.25, 0.25, "wood_dark", "Eyepiece")
	for _, s in { -1, 1 } do
		bar(m, f, V(-1.5 + s * 0.3, 0.25, 1.55), V(-1.5 + s * 0.15, 1.5, 1.35), 0.25, "wood", "Easel")
	end
	local board = f * CFrame.new(-1.5, 1.15, 1.48) * CFrame.Angles(-0.2, 0, 0)
	box(m, board, 0, 0, -0.06, 1.0, 1.0, 0.25, "wood", "BoardFrame")
	box(m, board, 0, 0, 0, 0.75, 0.75, 0.25, "night", "StarBoard")
	box(m, board, -0.2, 0.15, 0.06, 0.25, 0.25, 0.25, "yellow", "Star", true)
	box(m, board, 0.2, -0.12, 0.06, 0.25, 0.25, 0.25, "white", "Star", true)
	box(m, board, 0.12, 0.22, 0.06, 0.25, 0.25, 0.25, "yellow", "Star", true)
	streetLamp(m, f, 1.65, -1.65)
	pot(m, f, -0.95, 0.25, 1.55, "purple")
	pot(m, f, 0.95, 0.25, 1.55, "yellow")
	flower(m, f, -0.8, 0.25, 1.88, "pink")
	flower(m, f, 0.8, 0.25, 1.88, "white")
end

-- Crystal Fountain (5 x 5): a round white basin on white paving with a gold kerb round its foot, crystals set in its
-- wall and a gold rim of stones round the water, a crystal on the rim at each side throwing an arc of water in; in the
-- middle a white plinth ringed in gold with five crystals leaning out of it in purple, lilac and pink and a great
-- glowing pink crystal that glints, water running down its face and a jet with spray at its point; three crystal shards
-- floating over the water, rising and falling; crystal lotuses and coins on the water; a pylon in three corners: a
-- white block, a gold cap and a glowing crystal.
B.crystalfountain = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.25, 5, "white", "Paving")
	cyl(m, f, 0, 0.09, 0, 4.75, 0.25, "gold", "Kerb")
	cyl(m, f, 0, 0.4, 0, 4.5, 0.5, "white", "Basin")
	ringOf(m, f, 0, 0.4, 0, 2.27, 8, 0.25, 0.25, 0.25, "crystal", "Gem", math.pi / 8)
	ringOf(m, f, 0, 0.75, 0, 2.1, 12, 1.25, 0.25, 0.5, "gold", "Rim")
	cyl(m, f, 0, 0.7, 0, 4.0, 0.25, "shallow", "Water"):SetAttribute("PixelWater", 2)
	-- a crystal on the rim at each side, an arc of water from it
	for k = 0, 3 do
		local a = k * math.pi / 2
		local sa, ca = math.sin(a), math.cos(a)
		crystal(m, f, CFrame.new(sa * 2.1, 0.875, ca * 2.1), 0.5, 0.5, if k % 2 == 0 then "purple" else "crystal")
		box(m, f, sa * 1.75, 1.15, ca * 1.75, 0.25, 0.25, 0.25, "shallow", "Arc"):SetAttribute("PixelWater", 2)
		box(m, f, sa * 1.5, 0.95, ca * 1.5, 0.25, 0.25, 0.25, "shallow", "Arc"):SetAttribute("PixelWater", 2)
	end
	-- the plinth and its crystals
	cyl(m, f, 0, 0.8, 0, 1.5, 0.5, "white", "Plinth")
	cyl(m, f, 0, 0.95, 0, 1.75, 0.25, "gold", "PlinthRing")
	local cols = { "purple", "crystal", "pink" }
	for k = 1, 5 do
		local a = k * TAU / 6
		crystal(m, f, CFrame.new(math.sin(a) * 0.5, 1.0, math.cos(a) * 0.5) * CFrame.Angles(0, a, 0) * CFrame.Angles(0.35, 0, 0), 0.5, 0.75 + (k % 2) * 0.5, cols[k % 3 + 1])
	end
	crystal(m, f, CFrame.new(0, 1.0, 0), 0.75, 2.0, "pink", true, "Sparkle")
	box(m, f, 0, 2.0, 0.45, 0.5, 1.5, 0.25, "shallow", "Sheet"):SetAttribute("PixelWater", 4)
	box(m, f, 0, 4.1, 0, 0.25, 0.5, 0.25, "foam", "Jet"):SetAttribute("PixelWater", 2)
	ball(m, f, 0, 4.5, 0, 0.5, "foam", "Spray"):SetAttribute("PixelWater", 2)
	-- the floating shards (each rises and falls on its own)
	for k = 0, 2 do
		local a = k * TAU / 3 + 0.8
		local p = V(math.sin(a) * 1.3, 2.2 + k * 0.25, math.cos(a) * 1.3)
		move(at(m, f, CFrame.new(p) * CFrame.Angles(0, math.pi / 4, 0), 0.25, 0.5, 0.25, "crystal", "Sparkle", nil, true), "bob", p, "Y", 1.2, 0.12, k * 2.1)
	end
	-- lotuses and coins on the water
	for _, p in { { 1.2, -1.0 }, { -1.3, 0.8 } } do
		cyl(m, f, p[1], 0.8, p[2], 0.5, 0.25, "teal", "LilyPad")
		ball(m, f, p[1], 0.95, p[2], 0.25, "pink", "Bloom")
	end
	for _, p in { { 1.5, 1.0 }, { -1.3, -1.2 }, { 1.0, -1.6 } } do
		box(m, f, p[1], 0.83, p[2], 0.25, 0.25, 0.25, "gold", "Coin")
	end
	-- the pylons
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		local x, z = c[1] * 2.1, c[2] * 2.1
		box(m, f, x, 0.4, z, 0.5, 0.5, 0.5, "white", "Pylon")
		box(m, f, x, 0.75, z, 0.75, 0.25, 0.75, "gold", "PylonCap")
		crystal(m, f, CFrame.new(x, 0.875, z), 0.5, 0.75, "crystal", true, "Sparkle")
	end
end

-- Sun Spire (3 x 3): a stepped white spire on a cream step and a white plinth with a gold cornice, a gold orb on each
-- of its corners and a sun on each side (a gold disc, a glowing heart); five tiers in white and cream with gold bands,
-- buttresses at its foot, glowing marks up all four faces; at its top a glowing sun that glints on a gold rod, a gold
-- halo behind it and a ring of gold rays turning slowly round it, a finial over it; four crystals floating round the
-- spire, rising and falling; a lamp in three corners, flowers on the bottom step.
B.sunspire = function(m, f)
	box(m, f, 0, 0.125, 0, 3.0, 0.25, 3.0, "rock", "Step")
	box(m, f, 0, 0.375, 0, 2.5, 0.25, 2.5, "cream", "Step")
	box(m, f, 0, 0.875, 0, 2.0, 0.75, 2.0, "white", "Plinth")
	box(m, f, 0, 1.25, 0, 2.25, 0.25, 2.25, "gold", "Cornice")
	for k = 0, 3 do
		local g = f * CFrame.Angles(0, k * math.pi / 2, 0)
		discZ(m, g, 0, 0.85, 1.03, 0.5, 0.25, "gold", "Sun")
		box(m, g, 0, 0.85, 1.1, 0.25, 0.25, 0.25, "yellow", "SunHeart", true)
		ball(m, g, 1.0, 1.45, 1.0, 0.25, "gold", "Orb")
	end
	-- the tiers, their bands, buttresses at the foot, glowing marks
	for i = 0, 4 do
		local w = 1.5 - 0.25 * i
		local y0 = 1.375 + 1.25 * i
		box(m, f, 0, y0 + 0.625, 0, w, 1.25, w, if i % 2 == 0 then "white" else "cream", "Spire")
		box(m, f, 0, y0 + 1.25, 0, w + 0.25, 0.25, w + 0.25, "gold", "Band")
		if i <= 2 then
			for k = 0, 3 do
				box(m, f * CFrame.Angles(0, k * math.pi / 2, 0), 0, y0 + 0.6, w / 2 - 0.06, 0.25, 0.5, 0.25, "yellow", "Glyph", true)
			end
		end
	end
	for _, b in { { 0, 1.0, math.pi }, { 1.0, 0, -math.pi / 2 }, { 0, -1.0, 0 }, { -1.0, 0, math.pi / 2 } } do
		wedge(m, f, b[1], 1.75, b[2], 0.5, 0.75, 0.5, "cream", b[3], "Buttress")
	end
	-- the sun at the top, its halo and the turning rays
	local sy = 8.85
	box(m, f, 0, 8.0, 0, 0.25, 0.75, 0.25, "gold", "Rod")
	ball(m, f, 0, sy, 0, 0.75, "yellow", "Sparkle").Material = Enum.Material.Neon
	discZ(m, f, 0, sy, -0.25, 1.25, 0.25, "gold", "Halo")
	local hub = V(0, sy, 0.25)
	for k = 0, 7 do
		local a = k * TAU / 8
		move(at(m, f, CFrame.new(math.sin(a) * 0.75, sy + math.cos(a) * 0.75, 0.25) * CFrame.Angles(0, 0, -a), 0.25, 0.5, 0.25, if k % 2 == 0 then "gold" else "orange", "Ray"), "spin", hub, "Z", 0.4)
	end
	box(m, f, 0, sy + 0.75, 0, 0.25, 0.75, 0.25, "gold", "Finial")
	ball(m, f, 0, sy + 1.25, 0, 0.25, "gold", "Knob")
	-- the floating crystals
	for k, c in { { 1, 1, 4.0 }, { 1, -1, 5.0 }, { -1, 1, 4.6 }, { -1, -1, 5.6 } } do
		local p = V(c[1] * 0.95, c[3], c[2] * 0.95)
		move(at(m, f, CFrame.new(p) * CFrame.Angles(0, math.pi / 4, 0), 0.25, 0.5, 0.25, "crystal", "Sparkle", nil, true), "bob", p, "Y", 1.2, 0.1, k * 1.6)
	end
	-- lamps in three corners, flowers on the bottom step
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 } } do
		local x, z = c[1] * 1.35, c[2] * 1.35
		box(m, f, x, 0.625, z, 0.25, 0.75, 0.25, "white", "LampPost")
		box(m, f, x, 1.25, z, 0.25, 0.5, 0.25, "yellow", "Lamp", true)
		ball(m, f, x, 1.6, z, 0.25, "gold", "LampCap")
	end
	for k, x in { -0.75, -0.45, 0.5 } do
		flower(m, f, x, 0.25, 1.38, if k == 2 then "white" else "yellow")
	end
end

-- Founder Monument (4 x 4): the island's founder in bronze on a cream pedestal: three steps, a white base moulding,
-- corner pilasters and a cornice, a white slab; a gold plaque with two lines of letters on the front, a little ship on
-- the waves carved on the east, a wreath with red flowers leaning on the front. The founder: boots, a long coat with a
-- belt and buckle, lapels, a button and a flared skirt, a scarf blowing, a bearded face, a captain's hat with a band
-- and a badge; one arm raised high with a spyglass to the sea, the other bringing a rolled map down; the coat's tail
-- behind. A little driftling in paler bronze sits at the founder's feet under the map. A flag on a tall pole at the
-- back, a lamp at the front corners, flowers on the bottom step.
B.monument = function(m, f)
	box(m, f, 0, 0.125, 0, 4.0, 0.25, 4.0, "rock", "Step")
	box(m, f, 0, 0.375, 0, 3.5, 0.25, 3.5, "pavement", "Step")
	box(m, f, 0, 0.625, 0, 3.0, 0.25, 3.0, "white", "Step")
	box(m, f, 0, 1.625, 0, 2.0, 1.75, 2.0, "cream", "Pedestal")
	box(m, f, 0, 0.875, 0, 2.25, 0.25, 2.25, "white", "Base")
	box(m, f, 0, 2.5, 0, 2.25, 0.25, 2.25, "white", "Cornice")
	box(m, f, 0, 2.75, 0, 2.0, 0.25, 2.0, "white", "Slab")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		box(m, f, c[1] * 0.95, 1.625, c[2] * 0.95, 0.25, 1.5, 0.25, "white", "Pilaster")
	end
	box(m, f, 0, 1.6, 1.05, 1.25, 0.75, 0.25, "gold", "Plaque")
	box(m, f, 0, 1.72, 1.11, 0.75, 0.25, 0.25, "wood_dark", "Letters")
	box(m, f, 0, 1.47, 1.11, 0.5, 0.25, 0.25, "wood_dark", "Letters")
	box(m, f, 1.06, 1.45, 0, 0.25, 0.25, 0.75, "wood", "Ship")
	box(m, f, 1.06, 1.75, 0, 0.25, 0.5, 0.25, "paper", "Sail")
	box(m, f, 1.09, 1.2, 0, 0.25, 0.25, 1.0, "blue", "Waves")
	-- the wreath leaning on the front
	discZ(m, f, 0, 1.0, 1.25, 0.75, 0.25, "leaf_dark", "Wreath")
	discZ(m, f, 0, 1.0, 1.31, 0.25, 0.25, "cream", "WreathHole")
	for _, p in { { -0.22, 1.18 }, { 0.22, 1.18 }, { 0, 0.72 } } do
		ball(m, f, p[1], p[2], 1.36, 0.25, "berry_red", "Bloom")
	end
	-- the founder, on the slab (2.875)
	for _, s in { -1, 1 } do
		box(m, f, s * 0.25, 3.125, 0.05, 0.5, 0.5, 0.75, "wood_dark", "Boot")
		box(m, f, s * 0.25, 3.75, 0, 0.5, 0.75, 0.5, "straw", "Leg")
		ball(m, f, s * 0.62, 5.1, 0, 0.5, "gold", "Shoulder")
		at(m, f, CFrame.new(s * 0.2, 4.85, 0.36) * CFrame.Angles(0, 0, s * 0.3), 0.25, 0.75, 0.25, "yellow", "Lapel")
	end
	box(m, f, 0, 4.0, -0.05, 1.25, 0.5, 0.75, "gold", "Coat")
	box(m, f, 0, 4.75, 0, 1.0, 1.0, 0.75, "gold", "Coat")
	box(m, f, 0, 4.4, 0, 1.25, 0.25, 1.0, "wood_dark", "Belt")
	box(m, f, 0, 4.4, 0.53, 0.25, 0.25, 0.25, "yellow", "Buckle")
	box(m, f, 0, 4.7, 0.42, 0.25, 0.25, 0.25, "wood_dark", "Button")
	box(m, f, 0, 5.3, 0, 0.75, 0.25, 1.0, "orange", "Scarf")
	at(m, f, CFrame.new(-0.25, 5.0, 0.42) * CFrame.Angles(0, 0, 0.3), 0.25, 0.5, 0.25, "orange", "Scarf")
	box(m, f, 0, 5.75, 0, 0.75, 0.75, 0.75, "yellow", "Head")
	box(m, f, 0, 5.5, 0.4, 0.5, 0.25, 0.25, "gold", "Beard")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.17, 5.82, 0.38, 0.25, 0.25, 0.25, "wood_dark", "Eye")
	end
	box(m, f, 0, 6.2, 0, 1.25, 0.25, 1.0, "gold", "HatBrim")
	box(m, f, 0, 6.55, 0, 0.75, 0.5, 0.75, "gold", "Hat")
	box(m, f, 0, 6.45, 0, 1.0, 0.25, 1.0, "wood_dark", "HatBand")
	box(m, f, 0, 6.65, 0.42, 0.25, 0.25, 0.25, "yellow", "Badge")
	-- the arm raised high with the spyglass, looking out to sea
	bar(m, f, V(0.68, 5.15, 0.05), V(1.0, 5.85, 0.35), 0.5, "gold", "Arm")
	ball(m, f, 1.05, 5.98, 0.42, 0.25, "yellow", "Hand")
	local d = V(0.5, 0.45, 0.75).Unit
	local hand = V(1.05, 5.98, 0.42)
	at(m, f, CFrame.lookAt(hand + d * 0.3, hand + d) * CFrame.Angles(0, math.pi / 2, 0), 0.5, 0.25, 0.25, "gold", "Spyglass", "Cylinder")
	at(m, f, CFrame.lookAt(hand + d * 0.7, hand + d * 2) * CFrame.Angles(0, math.pi / 2, 0), 0.5, 0.5, 0.5, "yellow", "Spyglass", "Cylinder")
	-- the arm bringing the rolled map down by the little driftling
	bar(m, f, V(-0.68, 5.05, 0.05), V(-0.8, 4.35, 0.45), 0.5, "gold", "Arm")
	ball(m, f, -0.82, 4.22, 0.55, 0.25, "yellow", "Hand")
	K.log(m, f, -0.82, 4.12, 0.62, 0.75, 0.25, "paper", "Map")
	at(m, f, CFrame.new(0, 4.3, -0.5) * CFrame.Angles(0.2, 0, 0), 1.0, 1.25, 0.25, "gold", "CoatTail")
	-- the little driftling at its feet, in a paler bronze
	ball(m, f, -0.62, 3.22, 0.7, 0.75, "yellow", "Pal")
	for _, s in { -1, 1 } do
		box(m, f, -0.62 + s * 0.17, 3.67, 0.64, 0.25, 0.5, 0.25, "orange", "PalEar")
		box(m, f, -0.62 + s * 0.12, 3.3, 1.0, 0.25, 0.25, 0.25, "wood_dark", "PalEye")
	end
	-- the flag at the back, lamps at the front corners, flowers on the bottom step
	box(m, f, 1.7, 2.5, -1.7, 0.25, 5.0, 0.25, "steel_dark", "FlagPole")
	ball(m, f, 1.7, 5.1, -1.7, 0.5, "gold", "Knob")
	box(m, f, 1.2, 4.4, -1.7, 1.0, 0.75, 0.25, "berry_red", "Flag")
	box(m, f, 1.2, 4.4, -1.64, 1.0, 0.25, 0.25, "cream", "FlagStripe")
	for _, s in { -1, 1 } do
		local x, z = s * 1.7, 1.7
		box(m, f, x, 0.25, z, 0.5, 0.5, 0.5, "rock", "LampBase")
		box(m, f, x, 1.125, z, 0.25, 1.25, 0.25, "steel_dark", "LampPost")
		box(m, f, x, 2.0, z, 0.5, 0.5, 0.5, "yellow", "Lamp", true)
		box(m, f, x, 2.375, z, 0.5, 0.25, 0.5, "black", "LampCap")
		ball(m, f, x, 2.6, z, 0.25, "gold", "Knob")
	end
	for k, x in { -1.15, -0.9, 0.95, 1.2 } do
		flower(m, f, x, 0.25, 1.88, if k % 2 == 0 then "white" else "pink")
	end
end


------------------------------------------------------------------ the islands past Driftling Haven (GAME_DESIGN 4.1)
-- The request of 2026-11-14: "allow expansion up to level 20, you can make the previous levels of expansion a bit
-- cheaper too. add decor, huts, work buildings ... and other details as required for this". Our own designs, each a
-- step up from the city's: taller, more of its trade on show, a light or two.


------------------------------------------------------------------ the Tree of Life (GAME_DESIGN 6; Logic/Tree)
-- Tree of Life (8 x 8; `lvl` its stage, 1 .. 6, Logic/Tree.stage: it grows grander with the island: from the second
-- stage a taller trunk, a crown climbing and spreading wider, blossom, fruit and lanterns; from
-- the third eight clouds round the crown and four over them and three fruit a cloud; from the fourth a crown in full
-- blossom, gold caps on the stones, a ring of light over it and a second ring of light on the
-- ground; on the islands past Driftling Haven (the request of 2026-11-14: "allow expansion up to level 20 ... and other
-- details as required for this") the fifth adds a lantern under every limb, a second ring of light over the crown and
-- three stones floating round the trunk, and the sixth gold leaves in the crown, a third
-- ring of light on the ground and low standing stones with gold caps in the lawn's corners). The request
-- (2026-11-12): "make the tree of life more like a tree of life, reference references for it, make it look bigger and
-- more grand". After the old pictures of a world tree (our own design): a great trunk of three strands braided round
-- each other, wide roots that spread over the ground the way the limbs spread overhead (as above, so below), a ring
-- of standing stones round its foot (the circle of life), a glowing hollow at the front (`Pod`), long limbs holding
-- out clouds of leaves with sky between them, aerial roots and blossom hanging from them, gold fruit glowing under them, a ring of light on the ground, and twinkles of light on its fruit. Round the
-- ring of light a wide mossy lawn where its eggs lie (2026-11-13: "it now spawns eggs around it"): they are the
-- client's (Controllers/EggView), on a circle DecorModels.EGG_RING studs from its middle. DecorModels.HOLLOW: the
-- hollow's foot in the model's own frame.
-- Rebuilt in more detail on 2026-11-15 ("can you also rebuild the tree of life", after every building was reworked
-- the bakery's way): bark with knots and moss on it; roots flaring from high on the
-- trunk, the big ones dipping into the ground and coming up again past the stones, with rootlets; stones with moss and
-- lichen; a bigger glowing doorway in an arched frame, with a step and a lantern either side; a bird house on the
-- trunk; leaf clouds of more puffs in three greens, lit on top and dark underneath; vines that sway as they hang, with
-- flowers; mushrooms, flowers and fallen blossom among the roots. The eggs' ring (3 to 3.9 studs out, all
-- the way round: the eggs lie on the south and east whichever way the tree is turned) stays clear of anything that
-- stands up off the lawn; only the ring of light lies flat on it.
-- Its edges cleaned on 2026-11-20 ("the tree has alot of jaggied outlines, and stray pixels around the outline,
-- especially near the fruits"): no motes or fireflies cast as parts, blossom set into the clouds' faces, every fruit on
-- its own stalk clear of the leaves, and the camera's side worked out in the tree's own frame so a turned tree keeps
-- its knots and lit leaves in view (GAME_DESIGN 6). The glowing marks on its bark, its keystone and its stones went the
-- same day ("there are strange blue rectangles as well", "on the tree": cyan blocks with no shape to them).
DecorModels.HOLLOW = Vector3.new(0, 0, 1.25)
DecorModels.EGG_RING = 3.45
-- (the side the camera sees, on the ground: the view looks down from the south-east; in the world's frame)
local CAM_W = Vector3.new(1, 0, 1).Unit
-- (toward the sun, Render/Shading's: the lit side of a cloud of leaves)
local SUN_W = Vector3.new(-0.45, 0.8, 0.35).Unit
B.tree = function(m, f, stage)
	local s = math.clamp(stage or 1, 1, 6)
	-- the camera's side, the screen's right and the sun in the tree's own frame, so a tree turned on its lot keeps its
	-- marks, knots and lit leaves on the side the camera sees (they stayed where an unturned tree has them)
	local TREE_CAM = f:VectorToObjectSpace(CAM_W)
	local TREE_SUN = f:VectorToObjectSpace(SUN_W)
	-- what each stage adds (the ground, the stones and the roots stay inside the eggs' ring; the trunk rises, the
	-- crown climbs and spreads, and the light and fruit grow with it)
	local hs = ({ 1, 1.18, 1.36, 1.55, 1.68, 1.8 })[s] -- the top cloud's height
	local ys = ({ 1, 1.1, 1.2, 1.3, 1.37, 1.44 })[s] -- the limbs' and the ring of clouds' height (the crown spreads more than it climbs)
	local rs = ({ 1, 1.15, 1.32, 1.5, 1.58, 1.66 })[s] -- the crown's spread
	local ts = ({ 1, 1.1, 1.2, 1.3, 1.36, 1.42 })[s] -- the trunk's girth
	local cs = ({ 1, 1.1, 1.2, 1.3, 1.36, 1.42 })[s] -- each leaf cloud's size
	local function part(size: Vector3, cf: CFrame, color: string, name: string, neon: boolean?): BasePart
		return Blocks.part(m, { size = size, cf = f * cf, color = color, name = name, neon = neon, collide = false })
	end
	local function knob(p: Vector3, dia: number, color: string, name: string): BasePart
		return ball(m, f, p.X, p.Y, p.Z, dia, color, name)
	end
	-- a round limb, root or strand through pts, narrowing from d0 to d1, its two colours in turn
	local function bough(pts: { Vector3 }, d0: number, d1: number, c1: string, c2: string, name: string, cap: boolean?)
		local n = #pts - 1
		tube(m, f, pts, function(i: number): number
			return d0 + (d1 - d0) * (i - 1) / math.max(1, n - 1)
		end, function(_i: number): string
			-- (one wood the whole way: segments in turn of two woods drew as light and dark chunks with stepped edges,
			-- the report of 2026-11-20, "this only happens to the tree of life"; c2 is kept for the callers)
			local _ = c2
			return c1
		end, name, cap)
	end
	local function flat(a: number, r: number, y: number): Vector3
		return Vector3.new(math.sin(a) * r, y, math.cos(a) * r)
	end
	-- whether something facing n (outward, on the ground plane) is on the side the camera sees
	local function seen(n: Vector3): boolean
		return n.X * TREE_CAM.X + n.Z * TREE_CAM.Z > -0.3
	end
	local UP = Vector3.new(0, 1, 0)

	------------------------------------------------ the ground
	-- a round mossy lawn wide enough for the ring of eggs, a soft rim of clover round it, a darker ring of moss round
	-- the trunk
	cyl(m, f, 0, 0.02, 0, 7.8, 0.04, "leaf", "EggLawn")
	cyl(m, f, 0, 0.03, 0, 5.9, 0.06, "grass_dark", "Lawn")
	cyl(m, f, 0, 0.07, 0, 3.6, 0.06, "leaf_dark", "Moss")
	-- fallen blossom on the moss and the clover (more as it grows), never on the eggs' ring
	for k = 0, 8 + 2 * s do
		local a = k * 2.39 + 0.5
		local r = 1.45 + (k * 0.37) % 1.3
		if math.cos(a) > 0.92 and r < 2.2 then
			continue -- (the doorstep stays clear)
		end
		box(m, f, math.sin(a) * r, 0.1, math.cos(a) * r, 0.25, 0.25, 0.25, if k % 3 == 0 then "white" elseif k % 3 == 1 then "pink" else "cherry", "Fallen")
	end

	------------------------------------------------ the ring of light
	-- a ring of light on the ground round the stones (the circle of life), in short glowing dashes; a second ring
	-- inside it from the fourth stage, a third outside it at the last
	for k = 0, 23 do
		local a = (k + 0.5) / 24 * math.pi * 2
		local x, z = math.sin(a) * 2.95, math.cos(a) * 2.95
		if math.abs(x) < 0.7 and z > 0 then
			continue
		end
		part(Vector3.new(0.4, 0.04, 0.12), CFrame.new(x, 0.08, z) * CFrame.Angles(0, a + math.pi / 2, 0), "gold", "Ring", true)
		if s >= 4 and k % 2 == 0 then
			part(Vector3.new(0.3, 0.04, 0.1), CFrame.new(x * 0.72, 0.09, z * 0.72) * CFrame.Angles(0, a + math.pi / 2, 0), "gold", "Ring", true)
		end
		if s >= 6 and k % 2 == 1 then
			part(Vector3.new(0.3, 0.04, 0.1), CFrame.new(x * 1.22, 0.09, z * 1.22) * CFrame.Angles(0, a + math.pi / 2, 0), "gold", "Ring", true)
		end
	end

	------------------------------------------------ the standing stones
	-- the circle of standing stones round its foot (a gap at the front for the hollow), the tall ones showing over the
	-- eggs: each with moss on top and down its face and a fleck of lichen; from the fourth stage they wear gold caps
	for k = 0, 9 do
		local a = (k + 0.5) / 10 * math.pi * 2
		if math.cos(a) > 0.9 then
			continue
		end
		local h = (if k % 3 == 0 then 1.25 else 0.75) * (if s >= 4 then 1.2 else 1)
		local col = if k % 2 == 0 then "rock" else "rock_dark"
		-- (the stone's own frame: +Z faces out, away from the trunk)
		local at = CFrame.new(flat(a, 2.3, 0)) * CFrame.Angles(0, a + (if k % 2 == 0 then 0.12 else -0.1), 0)
		part(Vector3.new(0.75, h, 0.5), at * CFrame.new(0, h / 2, 0), col, "Stone")
		part(Vector3.new(0.5, 0.25, 0.25), at * CFrame.new(-0.125, h + 0.125, 0), if s >= 4 then "gold" else "moss", "StoneMoss")
		part(Vector3.new(0.5, 0.5, 0.25), at * CFrame.new(-0.0625, h - 0.1875, 0.1875), "moss", "StoneMoss")
		-- (the fleck and the mark lie on the stone's face, a pixel or more inside its edges: at its corner they stuck out
		-- past its outline as loose pixels, the request of 2026-11-20)
		part(Vector3.new(0.25, 0.25, 0.125), at * CFrame.new(-0.1875, 0.25, 0.25), if k % 2 == 0 then "straw" else "cream", "Lichen")
	end

	------------------------------------------------ the roots
	-- wide roots spreading over the ground between the stones, as the limbs spread overhead: each one round, narrowing
	-- as it goes; the big ones dip into the ground and come up again past the stones, and the ones the camera sees put
	-- out a rootlet
	for k = 1, 9 do
		local a = k / 10 * math.pi * 2
		local big = k % 2 == 1
		local r3 = 1.0 * ts + 0.6
		local pts = { flat(a, 0.5 * ts, 1.8 * ts), flat(a, 1.1 * ts, 0.95 * ts), flat(a, r3, 0.35), flat(a, r3 + 0.5, -0.02) }
		local front = seen(flat(a, 1, 0))
		if not front then
			-- (behind the trunk: a plainer root)
			table.remove(pts, 3)
		end
		bough(pts, (if big then 1.1 else 0.85) * ts, 0.35, "wood_dark", "wood", "Root")
		if front then
			bough({ pts[3], flat(a + (if k % 2 == 0 then 0.32 else -0.32), r3 + 0.3, -0.02) }, 0.25, 0.25, "wood_dark", "wood_dark", "Root")
		end
		if big and front then
			local h0 = math.min(r3 + 0.6, 2.25)
			bough({ flat(a, h0, -0.04), flat(a, h0 + 0.25, 0.18), flat(a, h0 + 0.5, -0.04) }, 0.3, 0.25, "wood_dark", "wood_dark", "Root")
		end
	end

	------------------------------------------------ the trunk
	-- one smooth core from the ground to the limbs, and three thick strands braided round it, each one round tube
	-- rising from a flared foot, then twisting as it climbs and narrowing a little (the request of 2026-11-13: "make
	-- the trunk connected smoothly as well without the stepped boxes"); the front is the gap between two strands, the
	-- hollow in it and a strand crossing over it like an arch
	local base = 7.0 * ys -- where the limbs leave the trunk
	local core = 1.85 * ts
	cyl(m, f, 0, base / 2, 0, core, base, "wood_dark", "Trunk")
	ball(m, f, 0, base, 0, core, "wood_dark", "Trunk")
	local segs = math.floor(8 * ys + 0.5)
	local rise = (base - 0.6 * ts) / segs
	local strands: { { Vector3 } } = {}
	local function strandDia(i: number): number
		return (1.2 - math.max(0, i - 2) * 0.04 / ys) * ts
	end
	for st = 0, 2 do
		local a0 = st / 3 * math.pi * 2 + math.pi / 4
		local pts: { Vector3 } = { flat(a0 - 0.12, 0.9 * ts, 0) }
		for i = 0, segs do
			table.insert(pts, flat(a0 + i * 0.45, (0.75 - i * 0.03 / ys) * ts, 0.6 * ts + i * rise))
		end
		strands[st + 1] = pts
		tube(m, f, pts, strandDia, function(_i: number): string
			return "wood"
		end, "Strand", true)
	end
	-- the bark: moss low down, on the side the camera sees. (No glowing marks on it: cyan blocks on the bark read as
	-- stray blue rectangles, the report of 2026-11-20, "there are strange blue rectangles as well", "on the tree"; and no
	-- knots: a swelling with a dark heart drew as a blotch on a strand, the same day, "this only happens to the tree of
	-- life".)
	local toCam = (TREE_CAM * 0.866 + UP * 0.5).Unit
	for st, pts in strands do
		for i = 2, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid = (a + b) / 2
			local out = Vector3.new(mid.X, 0, mid.Z).Unit
			if not seen(out) then
				continue
			end
			local rad = strandDia(i) / 2
			if i <= 3 and out:Dot(TREE_CAM) > 0.35 then
				knob(a + (out + UP * 0.6).Unit * (rad - 0.06), 0.5, "moss", "BarkMoss")
			end
		end
	end

	------------------------------------------------ the hollow
	-- at the front, between two strands: a dark arched opening with a warm light in it, in a frame of wood, a stone
	-- step before it and a lantern on a post either side
	local z0 = 1.0 * ts + 0.1
	part(Vector3.new(1.0, 1.0, 0.25), CFrame.new(0, 0.62, z0), "black", "Hollow")
	cyl(m, f, 0, 1.12, z0, 1.0, 0.25, "black", "Hollow").CFrame = f * CFrame.new(0, 1.12, z0) * CFrame.Angles(0, math.pi / 2, 0)
	part(Vector3.new(0.75, 1.0, 0.25), CFrame.new(0, 0.62, z0 + 0.125), "gold", "Pod", true)
	local podTop = cyl(m, f, 0, 1.12, z0 + 0.125, 0.75, 0.25, "gold", "Pod")
	podTop.CFrame = f * CFrame.new(0, 1.12, z0 + 0.125) * CFrame.Angles(0, math.pi / 2, 0)
	podTop.Material = Enum.Material.Neon
	for _, x in { -0.625, 0.625 } do
		part(Vector3.new(0.25, 1.0, 0.25), CFrame.new(x, 0.62, z0 + 0.25), "wood", "Jamb")
		part(Vector3.new(0.25, 0.5, 0.25), CFrame.new(x * 0.72, 1.56, z0 + 0.25) * CFrame.Angles(0, 0, if x < 0 then -math.pi / 4 else math.pi / 4), "wood", "Lintel")
	end
	part(Vector3.new(0.5, 0.25, 0.25), CFrame.new(0, 1.81, z0 + 0.3125), "wood_dark", "Lintel")
	part(Vector3.new(1.0, 0.25, 0.5), CFrame.new(0, 0.125, z0 + 0.625), "rock", "Step")
	for _, sx in { -1, 1 } do
		part(Vector3.new(0.25, 1.25, 0.25), CFrame.new(sx * 1.0, 0.625, z0 + 0.5), "wood_dark", "Post")
		part(Vector3.new(0.5, 0.25, 0.25), CFrame.new(sx * 1.125, 1.375, z0 + 0.5), "wood_dark", "Post")
		part(Vector3.new(0.5, 0.25, 0.5), CFrame.new(sx * 1.25, 1.125, z0 + 0.5), "wood_dark", "LanternCap")
		part(Vector3.new(0.25, 0.5, 0.25), CFrame.new(sx * 1.25, 0.75, z0 + 0.5), "yellow", "Lantern", true)
	end

	------------------------------------------------ the bird house
	-- nailed to the trunk on the side the camera sees, half way up: a little house with a red roof, a round door and a
	-- perch
	do
		local a = math.rad(50)
		local y = 4.0 * ys
		local at = CFrame.new(flat(a, 1.05 * ts + 0.375, y)) * CFrame.Angles(0, a, 0)
		part(Vector3.new(0.75, 0.75, 0.75), at, "sand", "BirdHouse")
		part(Vector3.new(0.25, 0.25, 0.25), at * CFrame.new(0, 0.125, 0.375), "black", "BirdHole")
		part(Vector3.new(0.25, 0.25, 0.25), at * CFrame.new(0, -0.125, 0.5), "wood_dark", "Perch")
		part(Vector3.new(0.25, 0.5, 0.5), at * CFrame.new(0, -0.5, -0.125), "wood_dark", "Perch")
		for _, sd in { -1, 1 } do
			part(Vector3.new(0.75, 0.25, 1.0), at * CFrame.new(sd * 0.25, 0.5, 0.0625) * CFrame.Angles(0, 0, sd * -0.6), "berry_red", "BirdRoof")
		end
	end

	------------------------------------------------ the crown
	-- clouds of leaves held out on long limbs, one at the top and a ring round it at two heights (eight from the third
	-- stage, and an upper ring of four between them), with sky between them so the limbs show
	local clouds: { Vector3 } = { Vector3.new(0, 12.2 * hs, 0) }
	local ring = if s >= 3 then 8 else 6
	for k = 0, ring - 1 do
		local a = k / ring * math.pi * 2 + 0.3
		local r = (if k % 2 == 0 then 3.5 else 3.1) * rs
		table.insert(clouds, Vector3.new(math.sin(a) * r, (if k % 2 == 0 then 8.9 else 10.3) * ys, math.cos(a) * r))
	end
	if s >= 3 then
		for k = 0, 3 do
			local a = k / 4 * math.pi * 2 + 0.7
			table.insert(clouds, Vector3.new(math.sin(a) * 2.2 * rs, (10.3 * ys + 12.2 * hs) / 2, math.cos(a) * 2.2 * rs))
		end
	end
	local function sizeOf(k: number): number
		return (if k == 1 then 3.2 elseif k > ring + 1 then 2.6 else 2.8) * cs
	end
	-- the limbs: round, narrowing, each bending up and out to its cloud, a twig forking off to the cloud's edge; the
	-- trunk goes on up into the top cloud
	local top = Vector3.new(0, base, 0)
	local right = f:VectorToObjectSpace(Vector3.new(1, 0, -1).Unit) -- (the screen's right, on the ground)
	local bends: { Vector3 } = {}
	for k, c in clouds do
		local big = sizeOf(k)
		if k == 1 then
			bough({ top - Vector3.new(0, 0.5, 0), Vector3.new(0.25, (base + c.Y) / 2, -0.2), c - Vector3.new(0, 0.3 * big, 0) }, 0.85 * ts, 0.5, "wood", "wood_dark", "Branch")
			bends[k] = Vector3.new(0.25, (base + c.Y) / 2, -0.2)
			continue
		end
		local out = Vector3.new(c.X, 0, c.Z).Unit
		local p0 = top + out * 0.45 * ts - Vector3.new(0, 0.9, 0)
		local bend = Vector3.new(c.X * 0.55, base + 0.6 + (c.Y - base - 0.6) * 0.35, c.Z * 0.55)
		bends[k] = bend
		bough({ p0, bend, c - Vector3.new(0, 0.25 * big, 0) }, 0.7 * ts, 0.4, if k % 2 == 0 then "wood" else "wood_dark", if k % 2 == 0 then "wood_dark" else "wood", "Branch")
		local side = Vector3.new(-out.Z, 0, out.X) * (if k % 2 == 0 then 1 else -1)
		bough({ bend, c + side * 0.42 * big - Vector3.new(0, 0.3 * big, 0) }, 0.375, 0.25, "wood_dark", "wood_dark", "Branch")
	end
	-- the clouds: a dark underside, a middle ball with four lobes round it and two on top, a lighter green where the
	-- sun falls and a darker one on the far side, small tufts so the outline is leafy (blossom on every cloud in full
	-- blossom from the fourth stage, gold leaves at the last)
	for k, c in clouds do
		local big = sizeOf(k)
		-- (the clouds at the back a shade darker, so the crown has depth)
		local back = k > 1 and Vector3.new(c.X, 0, c.Z).Unit:Dot(TREE_CAM) < -0.25
		local body = if back then "leaf_dark" else "leaf"
		knob(c - Vector3.new(0, 0.28 * big, 0), 0.8 * big, "leaf_dark", "LeavesUnder")
		knob(c, 0.85 * big, body, "Leaves")
		-- four lobes round it and two over it
		for j = 0, 3 do
			local a = j / 4 * math.pi * 2 + k * 0.7
			knob(c + Vector3.new(math.sin(a) * 0.4 * big, -0.08 * big, math.cos(a) * 0.4 * big), 0.6 * big, body, "LeafPuff")
		end
		for j = 0, 1 do
			local a = j * math.pi + k
			knob(c + Vector3.new(math.sin(a) * 0.18 * big, 0.26 * big, math.cos(a) * 0.18 * big), 0.5 * big, "leaf", "LeafPuff")
		end
		-- a lighter green where the sun falls and a darker one on the far side, sunk in so they shade like paint
		knob(c + (TREE_SUN + TREE_CAM * 0.4).Unit * 0.25 * big, 0.42 * big, if back then "leaf" else "green", "LeafLit")
		knob(c + (right * 0.8 + TREE_CAM * 0.5 - UP * 0.5).Unit * 0.24 * big, 0.4 * big, "leaf_dark", "LeafPuff")
		if s >= 4 then
			knob(c + (UP + TREE_CAM * 0.5).Unit * 0.42 * big, 1.0, if k % 2 == 0 then "pink" else "cherry", "Blossom")
		end
		if s >= 6 and k % 2 == 1 then
			-- gold leaves catching the light at the last stage
			knob(c + (UP + right * 0.7 + TREE_CAM * 0.3).Unit * 0.3 * big, 0.4 * big, "gold", "GoldLeaves")
		end
	end
	-- blossom over the clouds (more as it grows), set into the face of the cloud the camera sees: further out, or round
	-- the side, it hung off the crown's outline as loose blobs (the request of 2026-11-20)
	for k = 0, 16 + 6 * (s - 1) do
		local ci = k % #clouds + 1
		local c, big = clouds[ci], sizeOf(ci)
		local a = k * 2.4
		local dir = (Vector3.new(math.sin(a), 0.5 + (k % 3) * 0.35, math.cos(a)).Unit + toCam * 1.2).Unit
		knob(c + dir * 0.42 * big, if k % 3 == 0 then 0.5 else 0.375, if k % 3 == 0 then "pink" elseif k % 3 == 1 then "white" else "cherry", "Blossom")
	end
	-- aerial roots hanging from the clouds of the ring (the roots again, overhead), longer as it grows: each a thin
	-- vine swaying a little as it hangs, with flowers along it and a bud at its tip
	for k = 2, ring + 1 do
		local c, big = clouds[k], sizeOf(k)
		local len = (1.0 + (k % 3) * 0.6) * (1 + 0.25 * (s - 1))
		local out = Vector3.new(c.X, 0, c.Z).Unit * 0.42 * big
		local sg = if k % 2 == 0 then 1 else -1
		local p0 = Vector3.new(c.X + out.X, c.Y - 0.3 * big, c.Z + out.Z)
		local p1 = p0 + right * 0.25 * sg - UP * len * 0.35
		local p2 = p0 - right * 0.125 * sg - UP * len * 0.7
		local p3 = p0 + right * 0.125 * sg - UP * len
		bough({ p0, p1, p2, p3 }, 0.25, 0.25, "chalk", "chalk", "Vine")
		knob(p1 + TREE_CAM * 0.125, 0.375, if k % 2 == 0 then "pink" else "white", "VineFlower")
		if len > 1.6 then
			knob(p2 + TREE_CAM * 0.125, 0.375, if k % 2 == 0 then "white" else "pink", "VineFlower")
		end
		knob(p3 - UP * 0.125, 0.375, if k % 2 == 0 then "pink" else "cherry", "VineTip")
	end
	-- gold fruit glowing under the clouds (three a cloud from the third stage), each hanging clear of the leaves on a
	-- stalk up into them: tucked up against them a fruit's outline broke where it met the leaves, and the third hung
	-- in the air on nothing (the request of 2026-11-20, "stray pixels around the outline, especially near the fruits").
	-- The first fruit of every other cloud is a "Sparkle": a twinkle comes and goes on it now and then
	-- (Controllers/AmbientView), the motes of light that drifted round the tree as loose specks before
	for k = 2, #clouds do
		local c, big = clouds[k], sizeOf(k)
		local n = if s >= 3 then 3 else 2
		-- (the leaves' underside where the fruit hang: the dark ball under the cloud, 0.32 of its size out from its middle)
		local under = c.Y - 0.52 * big
		for j = 0, n - 1 do
			local a = j * (math.pi * 2 / n) + k
			local x, y, z = c.X + math.sin(a) * 0.32 * big, under - 0.5 - j * 0.25, c.Z + math.cos(a) * 0.32 * big
			local len = under - y
			part(Vector3.new(0.25, len, 0.25), CFrame.new(x, y + 0.2 + len / 2, z), "wood_dark", "Stalk")
			ball(m, f, x, y, z, 0.5, "gold", if j == 0 and k % 2 == 0 then "Sparkle" else "Fruit").Material = Enum.Material.Neon
		end
	end
	-- lanterns of light hanging from the lower limbs (from the second stage; under every limb from the fifth)
	if s >= 2 then
		for k = 2, ring + 1, if s >= 5 then 1 else 2 do
			local c, big = clouds[k], sizeOf(k)
			local b = bends[k]
			local tip = c - Vector3.new(0, 0.25 * big, 0)
			local p = b + (tip - b) * 0.2
			local y = p.Y - 0.35
			part(Vector3.new(0.25, 0.5, 0.25), CFrame.new(p.X, y - 0.25, p.Z), "wood_dark", "Stalk")
			part(Vector3.new(0.75, 0.25, 0.75), CFrame.new(p.X, y - 0.625, p.Z), "wood_dark", "LanternCap")
			part(Vector3.new(0.5, 0.5, 0.5), CFrame.new(p.X, y - 1.0, p.Z), "yellow", "Lantern", true)
		end
	end
	-- a crown of light over the top cloud from the fourth stage (a second, wider and higher, from the fifth)
	if s >= 4 then
		local c = clouds[1]
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			part(Vector3.new(0.34, 0.1, 0.1), CFrame.new(c.X + math.sin(a) * 1.7, c.Y + 2.6, c.Z + math.cos(a) * 1.7) * CFrame.Angles(0, a + math.pi / 2, 0), "gold", "Halo", true)
		end
		if s >= 5 then
			for k = 0, 15 do
				local a = (k + 0.5) / 16 * math.pi * 2
				part(Vector3.new(0.34, 0.1, 0.1), CFrame.new(c.X + math.sin(a) * 2.4, c.Y + 3.4, c.Z + math.cos(a) * 2.4) * CFrame.Angles(0, a + math.pi / 2, 0), "yellow", "Halo", true)
			end
		end
	end
	-- stones floating round the trunk from the fifth stage: a rough rock with moss on top, roots trailing from it, a
	-- pebble under it
	if s >= 5 then
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 1.1
			local x, y, z = math.sin(a) * 3.3, 4.2 + k * 0.9, math.cos(a) * 3.3
			local at = CFrame.new(x, y, z) * CFrame.Angles(0, a, 0)
			part(Vector3.new(1.0, 0.5, 0.75), at, "rock", "Floating")
			part(Vector3.new(0.75, 0.5, 0.5), at * CFrame.new(0.0625, -0.375, 0), "rock_dark", "Floating")
			part(Vector3.new(0.5, 0.25, 0.25), at * CFrame.new(0, -0.75, 0.0), "rock_dark", "Floating")
			part(Vector3.new(0.75, 0.25, 0.5), at * CFrame.new(-0.125, 0.375, 0), "moss", "FloatingMoss")
			part(Vector3.new(0.25, 0.75, 0.25), at * CFrame.new(-0.25, -0.75, 0.0625), "wood_dark", "Floating")
			part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(x + 0.2, y - 1.4, z - 0.1), "rock_dark", "Pebble")
		end
	end
	-- low standing stones with gold caps in the lawn's corners at the last stage, outside the eggs' ring and too low to
	-- hide them
	if s >= 6 then
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				for j, q in { { 3.5, 3.5 }, if sx == sz then { 3.75, 2.875 } else { 2.875, 3.75 } } do
					local x, z = q[1] * sx, q[2] * sz
					local col = if (j + sx + sz) % 2 == 0 then "rock" else "rock_dark"
					part(Vector3.new(0.5, 0.25, 0.5), CFrame.new(x, 0.125, z) * CFrame.Angles(0, math.atan2(x, z), 0), col, "OuterStone")
					part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(x, 0.375, z) * CFrame.Angles(0, math.atan2(x, z), 0), "gold", "OuterCap")
				end
			end
		end
	end

	------------------------------------------------ the small life at its foot
	-- (the motes of light that drifted round it and the fireflies among the roots were parts until 2026-11-20: cast in
	-- the picture they were loose two and three pixel squares round the trunk and the crown, "stray pixels around the
	-- outline". The twinkles on its fruit stand in for them, and the islands' own fireflies come out at night.)
	-- mushrooms in twos among the roots, and flowers
	local caps = { { -1.45, 1.05, 1 }, { -1.7, 0.8, 2 }, { 1.65, -0.9, 1 }, { 1.45, -1.2, 2 } }
	for k, c in caps do
		local x, z, h = c[1], c[2], if c[3] == 1 then 0.5 else 0.25
		box(m, f, x, 0.125 + h / 2, z, 0.25, h, 0.25, "cream", "Stalk")
		knob(Vector3.new(x, 0.2 + h, z), if c[3] == 1 then 0.5 else 0.375, if k % 5 < 3 then "berry_red" else "orange", "Cap")
		if c[3] == 1 then
			knob(Vector3.new(x + 0.08, 0.34 + h, z + 0.14), 0.25, "white", "Spot")
		end
	end
	for k, c in { { -1.15, 2.15 }, { 1.25, 2.1 }, { -2.3, -0.9 }, { 2.4, 0.9 }, { 0.3, -2.4 }, { -0.4, 1.95 } } do
		box(m, f, c[1], 0.25, c[2], 0.25, 0.25, 0.25, "grass_dark", "Stem")
		box(m, f, c[1], 0.5, c[2], 0.25, 0.25, 0.25, if k % 3 == 0 then "yellow" elseif k % 3 == 1 then "pink" else "white", "Flower")
	end
end

-- The build catalog's own models (GAME_DESIGN 4: "make much, much more building options"), one module a group, each a
-- table of builders by id: the paths and water, the fences and water decor, nature, the themes, the fun and grand
-- pieces. A piece modelled here first keeps its builder.
-- The buildings themselves, one module a group (2026-11-15: "rework and detail every building even more").
for _, mod in { require(script.Parent.FarmBuildings), require(script.Parent.WoodBuildings), require(script.Parent.ShopBuildings), require(script.Parent.HomeBuildings), require(script.Parent.BoostBuildings) } do
	for id, fn in mod do
		B[id] = fn
	end
end
for _, mod in { require(script.Parent.GroundModels), require(script.Parent.FenceModels), require(script.Parent.NatureModels), require(script.Parent.ThemeModels), require(script.Parent.ThemeMoreModels), require(script.Parent.FunModels) } do
	for id, fn in mod do
		if B[id] == nil then
			B[id] = function(m: Model, f: CFrame, lvl: number?)
				fn(m, f, lvl or 1)
			end
		end
	end
end

-- The piece's model at `at` (the footprint's centre on the grass, turned). Unknown ids build nothing.
function DecorModels.build(id: string, at: CFrame, lvl: number?): Model
	local m = Blocks.model(nil, "Decor_" .. id)
	m:SetAttribute("Decor", id)
	-- (its frame, for what turns on it in the client: Controllers/Spinners)
	m:SetAttribute("At", at)
	local fn = B[id]
	local l = lvl or 1
	if fn then
		fn(m, at, l)
	end
	if id == "tree" then
		-- (lit as one smooth surface across its balls, its crown, roots and trunk, so it never reads as a heap of
		-- blotches: "This is also the case for the tree of life", 2026-11-14, Render/Smooth; the lawns round it keep
		-- their own light)
		m:SetAttribute("PixelSmooth", true)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Lawn" or d.Name == "EggLawn" or d.Name == "Moss") then
				d:SetAttribute("PixelOwn", true)
			end
			-- (the wood, its trunk, strands, roots and limbs, lit by its own round shapes like any log: blended across the
			-- balls at every joint, a lit band's edge wavered from one joint to the next and broke into ragged patches;
			-- the report of 2026-11-20, "its still uneven")
			if d:IsA("BasePart") and (d.Name == "Trunk" or d.Name == "Strand" or d.Name == "Root" or d.Name == "Branch") then
				d:SetAttribute("PixelOwn", true)
			end
		end
	end
	-- (the tree's lvl is its stage, a water tile's its neighbours: no pennant; nor on a path or a fence)
	local kind = KIND[id]
	if l >= 2 and kind ~= "tree" and kind ~= "water" and kind ~= "path" and kind ~= "fence" then
		local size = FOOT[id]
		if size then
			pennant(m, at, l, size[1], size[2])
		end
	end
	return m
end

function DecorModels.has(id: string): boolean
	return B[id] ~= nil
end

return DecorModels
