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
local palmTrunk = K.palmTrunk
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
-- Flower Bed (2 x 2): a bordered bed, flowers of four colours at different heights, leaves.
B.flowers = function(m, f)
	box(m, f, 0, 0.15, 0, 2, 0.3, 2, "rock", "Border")
	box(m, f, 0, 0.27, 0, 1.75, 0.1, 1.75, "pot", "Soil")
	local cols = { "pink", "yellow", "purple", "berry_red", "white", "orange" }
	for i = 0, 8 do
		local x, z = (i % 3) * 0.55 - 0.55, (i // 3) * 0.55 - 0.55
		local h = 0.3 + (i * 7 % 3) * 0.12
		box(m, f, x, 0.32 + h / 2, z, 0.08, h, 0.08, "leaf", "Stem")
		box(m, f, x + 0.12, 0.4, z, 0.2, 0.08, 0.12, "leaf_dark", "Leaf")
		box(m, f, x, 0.36 + h, z, 0.25, 0.2, 0.25, cols[i % #cols + 1], "Bloom")
		box(m, f, x, 0.48 + h, z, 0.1, 0.06, 0.1, "yellow", "Heart")
	end
end

-- Round Bush (2 x 2): leafy clumps in two greens, a few berries.
B.bush = function(m, f)
	ball(m, f, 0, 0.75, 0, 1.8, "leaf", "Bush")
	ball(m, f, 0.5, 0.6, 0.45, 1.2, "leaf_dark", "Bush")
	ball(m, f, -0.45, 1.15, -0.25, 1.0, "leaf", "Bush")
	ball(m, f, -0.5, 0.5, 0.5, 0.9, "leaf_dark", "Bush")
	for _, b in { { 0.6, 1.1, 0.6 }, { -0.2, 1.5, 0.3 }, { 0.75, 0.75, -0.2 } } do
		ball(m, f, b[1], b[2], b[3], 0.25, "berry_red", "Berry")
	end
end

-- Tiki Torch (1 x 1): a carved pole, a bound cup, its flame.
B.torch = function(m, f)
	box(m, f, 0, 0.9, 0, 0.25, 1.8, 0.25, "wood_dark", "Pole")
	box(m, f, 0, 1.4, 0, 0.32, 0.1, 0.32, "sand_dark", "Binding")
	box(m, f, 0, 0.6, 0, 0.32, 0.1, 0.32, "sand_dark", "Binding")
	box(m, f, 0, 1.9, 0, 0.5, 0.3, 0.5, "wood", "Cup")
	box(m, f, 0, 2.1, 0, 0.55, 0.1, 0.55, "wood_dark", "Rim")
	box(m, f, 0, 2.3, 0, 0.4, 0.4, 0.4, "orange", "Flame", true)
	box(m, f, 0, 2.55, 0, 0.25, 0.25, 0.25, "yellow", "Tip", true)
end

-- Shell Pile (2 x 2): a heap of shells, a conch, a starfish.
B.shellpile = function(m, f)
	box(m, f, 0, 0.05, 0, 1.8, 0.1, 1.8, "sand", "Sand")
	ball(m, f, -0.4, 0.25, -0.2, 0.55, "pink", "Shell")
	ball(m, f, 0.3, 0.25, 0.1, 0.55, "cream", "Shell")
	ball(m, f, 0, 0.5, -0.05, 0.45, "sand", "Shell")
	ball(m, f, -0.1, 0.2, 0.55, 0.4, "orange", "Shell")
	box(m, f, 0.6, 0.15, -0.6, 0.4, 0.25, 0.4, "white", "Shell")
	Blocks.part(m, { size = Vector3.new(0.9, 0.45, 0.45), cf = f * CFrame.new(0.45, 0.25, 0.55) * CFrame.Angles(0, math.rad(30), 0), color = "pink", name = "Conch", collide = false })
	box(m, f, -0.6, 0.08, 0.65, 0.6, 0.1, 0.15, "orange", "Starfish")
	box(m, f, -0.6, 0.08, 0.65, 0.15, 0.1, 0.6, "orange", "Starfish")
end

-- Palm Tree (3 x 3): a ringed trunk curving up in one smooth line, eight fronds, coconuts, a mound of sand at its foot.
B.palm = function(m, f)
	box(m, f, 0, 0.05, 0, 1.5, 0.1, 1.5, "sand", "Mound")
	local x = 1.5
	local top = 5.4
	palmTrunk(m, f, x, top - 0.1, 0.7)
	box(m, f, x, top, 0, 1.2, 0.45, 1.2, "leaf_dark", "Crown")
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } } do
		local long = k <= 4
		local len = if long then 2.6 else 1.9
		Blocks.part(m, {
			size = Vector3.new(len, 0.3, 0.85),
			cf = f * CFrame.new(x + d[1] * len / 2, top - 0.15 - (if long then 0.3 else 0.1), d[2] * len / 2) * CFrame.Angles(0, math.atan2(-d[2], d[1]), math.rad(if long then -12 else -6)),
			color = if k % 2 == 0 then "leaf" else "leaf_dark",
			name = "Frond",
			collide = false,
		})
	end
	ball(m, f, x + 0.3, top - 0.55, 0.3, 0.5, "wood_dark", "Coconut")
	ball(m, f, x - 0.25, top - 0.55, -0.2, 0.45, "wood_dark", "Coconut")
	ball(m, f, 0.6, 0.2, 0.7, 0.4, "wood_dark", "Coconut")
end

-- Bench (3 x 2): slatted seat and back on iron legs, a pot plant beside.
B.bench = function(m, f)
	for k = 0, 2 do
		box(m, f, -0.2, 0.75, -0.2 + k * 0.28, 2.4, 0.1, 0.22, "wood", "Slat")
	end
	for k = 0, 1 do
		box(m, f, -0.2, 1.15 + k * 0.3, -0.5, 2.4, 0.2, 0.08, "wood", "Slat")
	end
	for _, x in { -1.3, 0.9 } do
		box(m, f, x, 0.4, 0.05, 0.15, 0.8, 0.7, "steel_dark", "Leg")
		box(m, f, x, 1.15, -0.5, 0.15, 0.8, 0.12, "steel_dark", "Back")
		box(m, f, x, 0.95, 0.05, 0.15, 0.1, 0.7, "steel_dark", "Arm")
	end
	pot(m, f, 1.3, 0, 0.3, "yellow")
end

-- Hammock (4 x 2): two posts, a striped cloth sagging between, a pillow, a book left on it.
B.hammock = function(m, f)
	for _, x in { -1.8, 1.8 } do
		box(m, f, x, 1.0, 0, 0.3, 2.0, 0.3, "wood_dark", "Post")
		box(m, f, x, 2.05, 0, 0.4, 0.1, 0.4, "wood", "Cap")
	end
	local segs = 7
	for k = 0, segs - 1 do
		local t = (k + 0.5) / segs
		local x = -1.6 + t * 3.2
		local y = 1.45 - math.sin(t * math.pi) * 0.6
		box(m, f, x, y, 0, 3.2 / segs + 0.02, 0.12, 0.9, if k % 2 == 0 then "berry_red" else "cream", "Cloth")
	end
	box(m, f, -1.15, 1.25, 0, 0.5, 0.2, 0.6, "white", "Pillow")
	box(m, f, 0.3, 0.98, 0.1, 0.4, 0.08, 0.3, "blue", "Book")
end

-- Picnic Table (4 x 3): a planked table and benches, a checked cloth, a basket, plates and a jug.
B.picnic = function(m, f)
	for k = 0, 3 do
		box(m, f, 0, 1.05, -0.45 + k * 0.3, 3.6, 0.12, 0.28, "wood", "Plank")
	end
	for _, x in { -1.5, 1.5 } do
		Blocks.part(m, { size = Vector3.new(0.15, 1.1, 0.15), cf = f * CFrame.new(x, 0.5, -0.3) * CFrame.Angles(math.rad(20), 0, 0), color = "wood_dark", name = "Leg", collide = false })
		Blocks.part(m, { size = Vector3.new(0.15, 1.1, 0.15), cf = f * CFrame.new(x, 0.5, 0.3) * CFrame.Angles(math.rad(-20), 0, 0), color = "wood_dark", name = "Leg", collide = false })
	end
	for _, z in { -1.2, 1.2 } do
		box(m, f, 0, 0.55, z, 3.6, 0.12, 0.45, "wood", "Bench")
	end
	for k = 0, 3 do
		box(m, f, -1.0 + (k % 2) * 0.5, 1.13, -0.25 + (k // 2) * 0.5, 0.5, 0.04, 0.5, if (k + k // 2) % 2 == 0 then "berry_red" else "white", "Cloth")
	end
	box(m, f, 0.8, 1.35, 0, 0.6, 0.45, 0.45, "wood", "Basket")
	box(m, f, 0.8, 1.7, 0, 0.6, 0.08, 0.08, "wood_dark", "Handle")
	cyl(m, f, -0.2, 1.14, -0.3, 0.45, 0.05, "white", "Plate")
	cyl(m, f, 0.2, 1.14, 0.35, 0.45, 0.05, "white", "Plate")
	cyl(m, f, 1.4, 1.3, -0.3, 0.3, 0.4, "blue", "Jug")
end

-- Totem Pole (2 x 2): four carved faces in bright colours, wings and a beak on top, a stone base.
B.totem = function(m, f)
	box(m, f, 0, 0.15, 0, 1.8, 0.3, 1.8, "rock", "Base")
	local cols = { "berry_red", "yellow", "blue", "green" }
	for i = 0, 3 do
		local y = 0.8 + i * 0.95
		box(m, f, 0, y, 0, 1.3, 0.95, 1.3, cols[i + 1], "Block")
		box(m, f, 0, y + 0.42, 0, 1.4, 0.1, 1.4, "black", "Band")
		box(m, f, -0.3, y + 0.1, 0.66, 0.3, 0.2, 0.05, "white", "Eye")
		box(m, f, 0.3, y + 0.1, 0.66, 0.3, 0.2, 0.05, "white", "Eye")
		box(m, f, -0.3, y + 0.1, 0.69, 0.12, 0.12, 0.04, "black", "Pupil")
		box(m, f, 0.3, y + 0.1, 0.69, 0.12, 0.12, 0.04, "black", "Pupil")
		box(m, f, 0, y - 0.25, 0.66, 0.6, 0.15, 0.05, if i % 2 == 0 then "white" else "black", "Mouth")
		box(m, f, 0, y - 0.05, 0.72, 0.15, 0.25, 0.1, cols[(i + 2) % 4 + 1], "Nose")
	end
	box(m, f, 0, 4.45, 0, 2.4, 0.3, 0.5, "orange", "Wings")
	box(m, f, 0, 4.4, 0.55, 0.3, 0.25, 0.5, "yellow", "Beak")
end

-- Fountain (5 x 5): a round stone basin with a rim, water, a column with two bowls, a jet, lily pads, coins.
B.fountain = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "pavement", "Paving")
	cyl(m, f, 0, 0.4, 0, 4.6, 0.7, "rock", "Basin")
	cyl(m, f, 0, 0.78, 0, 4.8, 0.1, "steel", "Rim")
	cyl(m, f, 0, 0.7, 0, 4.0, 0.12, "water", "Water"):SetAttribute("PixelWater", 2)
	cyl(m, f, 0, 1.4, 0, 0.8, 1.4, "rock", "Column")
	cyl(m, f, 0, 2.15, 0, 2.2, 0.35, "rock", "Bowl")
	cyl(m, f, 0, 2.33, 0, 1.8, 0.08, "water", "Water"):SetAttribute("PixelWater", 2)
	cyl(m, f, 0, 2.8, 0, 0.4, 0.9, "rock", "Spire")
	cyl(m, f, 0, 3.3, 0, 1.0, 0.2, "rock", "Bowl")
	ball(m, f, 0, 3.6, 0, 0.45, "window", "Jet")
	for _, p in { { 1.3, 0.6 }, { -1.1, -0.9 }, { 0.4, -1.5 } } do
		cyl(m, f, p[1], 0.78, p[2], 0.5, 0.05, "leaf", "LilyPad")
	end
	box(m, f, -0.9, 0.77, 1.2, 0.15, 0.04, 0.15, "gold", "Coin")
	box(m, f, 0.7, 0.77, -0.4, 0.15, 0.04, 0.15, "gold", "Coin")
end

-- Lighthouse (4 x 4): a striped tapering tower on a rock base, a gallery with a rail, the lamp room, a cap, a
-- door, small windows up the tower.
B.lighthouse = function(m, f)
	box(m, f, 0, 0.3, 0, 4, 0.6, 4, "rock", "Base")
	box(m, f, 0.9, 0.7, 0.9, 1.2, 0.4, 1.2, "rock_dark", "Rock")
	for i = 0, 4 do
		local w = 2.6 - i * 0.22
		box(m, f, 0, 1.2 + i * 1.2, 0, w, 1.2, w, if i % 2 == 0 then "white" else "berry_red", "Tower")
	end
	for i = 1, 3 do
		local w = 2.6 - i * 0.22
		box(m, f, 0, 1.4 + i * 1.2, w / 2 + 0.03, 0.35, 0.45, 0.06, "window", "Window")
	end
	box(m, f, 0, 6.65, 0, 2.6, 0.2, 2.6, "steel_dark", "Gallery")
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(m, f, math.cos(a) * 1.2, 7.0, math.sin(a) * 1.2, 0.1, 0.5, 0.1, "steel_dark", "Rail")
	end
	box(m, f, 0, 7.3, 0, 2.5, 0.08, 2.5, "steel_dark", "RailTop").Transparency = 0
	box(m, f, 0, 7.35, 0, 1.4, 1.0, 1.4, "window", "LampRoom")
	box(m, f, 0, 7.35, 0, 0.8, 0.8, 0.8, "yellow", "Lamp", true)
	box(m, f, 0, 8.0, 0, 1.8, 0.3, 1.8, "berry_red", "Cap")
	box(m, f, 0, 8.35, 0, 1.0, 0.4, 1.0, "berry_red", "Cap")
	ball(m, f, 0, 8.7, 0, 0.35, "gold", "Knob")
	door(m, f * CFrame.new(0, 0.6, 0), 0, 1.3, 0.7, 1.1, "wood_dark")
end

-- Guardian Statue (3 x 3): an original guardian of the islets holding up a pearl, on a carved plinth with steps.
B.statue = function(m, f)
	box(m, f, 0, 0.15, 0, 3, 0.3, 3, "rock", "Step")
	box(m, f, 0, 0.75, 0, 2.4, 0.9, 2.4, "steel", "Plinth")
	box(m, f, 0, 1.25, 0, 2.6, 0.12, 2.6, "steel_dark", "Cap")
	box(m, f, 0, 0.75, 1.22, 1.4, 0.4, 0.05, "gold", "Plaque")
	box(m, f, -0.3, 1.8, 0, 0.45, 0.9, 0.5, "gold", "Leg")
	box(m, f, 0.3, 1.8, 0, 0.45, 0.9, 0.5, "gold", "Leg")
	box(m, f, 0, 2.75, 0, 1.25, 1.1, 0.75, "gold", "Body")
	box(m, f, 0, 2.6, 0.4, 0.9, 0.12, 0.05, "yellow", "Sash")
	box(m, f, 0, 3.75, 0, 1.15, 0.95, 0.95, "gold", "Head")
	box(m, f, -0.25, 3.8, 0.49, 0.18, 0.18, 0.04, "steel_dark", "Eye")
	box(m, f, 0.25, 3.8, 0.49, 0.18, 0.18, 0.04, "steel_dark", "Eye")
	box(m, f, -0.45, 4.35, 0, 0.2, 0.4, 0.2, "gold", "Ear")
	box(m, f, 0.45, 4.35, 0, 0.2, 0.4, 0.2, "gold", "Ear")
	box(m, f, 0.8, 3.5, 0, 0.35, 1.4, 0.35, "gold", "Arm")
	box(m, f, -0.75, 2.8, 0, 0.3, 0.9, 0.3, "gold", "Arm")
	ball(m, f, 0.8, 4.4, 0, 0.75, "pink", "Pearl")
	ball(m, f, 0.65, 4.55, 0.25, 0.2, "white", "Shine")
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
B.sandcastle = function(m, f)
	box(m, f, 0, 0.25, 0, 1.4, 0.5, 1.4, "sand", "Keep")
	for _, c in { { -0.6, -0.6 }, { 0.6, -0.6 }, { -0.6, 0.6 }, { 0.6, 0.6 } } do
		cyl(m, f, c[1], 0.45, c[2], 0.45, 0.9, "sand_dark", "Tower")
	end
	box(m, f, 0, 0.7, 0, 0.6, 0.4, 0.6, "sand", "Top")
	box(m, f, 0, 1.1, 0, 0.05, 0.5, 0.05, "wood_dark", "Stick")
	wedge(m, f, 0.15, 1.25, 0, 0.3, 0.2, 0.04, "berry_red", math.pi / 2, "Flag")
	box(m, f, 0, 0.2, 0.71, 0.3, 0.35, 0.04, "sand_dark", "Gate")
	box(m, f, 0.8, 0.12, 0.8, 0.3, 0.25, 0.3, "berry_red", "Bucket")
end
B.rockgarden = function(m, f)
	box(m, f, 0, 0.03, 0, 2, 0.06, 2, "sand", "Gravel")
	for k = 0, 3 do
		box(m, f, 0, 0.07, -0.7 + k * 0.45, 1.8, 0.02, 0.06, "sand_dark", "Rake")
	end
	ball(m, f, -0.4, 0.3, -0.3, 0.7, "rock", "Rock")
	ball(m, f, 0.5, 0.22, 0.4, 0.5, "rock_dark", "Rock")
	ball(m, f, 0.55, 0.38, 0.35, 0.3, "leaf_dark", "Moss")
end
B.hedge = function(m, f)
	box(m, f, 0, 0.45, 0, 2.9, 0.9, 0.8, "leaf_dark", "Hedge")
	box(m, f, 0, 0.92, 0, 2.7, 0.12, 0.6, "leaf", "Top")
	for _, x in { -1.0, 0.2, 1.1 } do
		box(m, f, x, 0.6, 0.41, 0.12, 0.12, 0.04, "pink", "Flower")
	end
end
B.lamppost = function(m, f)
	streetLamp(m, f, 0, 0, false)
end
B.streetlamp = function(m, f)
	streetLamp(m, f, 0, 0, true)
	box(m, f, 0, 1.4, 0.1, 0.4, 0.25, 0.04, "blue", "Sign")
end
B.flowerarch = function(m, f)
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 0.9, 0, 0.15, 1.8, 0.15, "white", "Post")
	end
	for k = 0, 6 do
		local a = math.pi * k / 6
		box(m, f, -math.cos(a) * 1.25, 1.8 + math.sin(a) * 0.45, 0, 0.4, 0.15, 0.2, "white", "Arch")
		ball(m, f, -math.cos(a) * 1.25, 1.85 + math.sin(a) * 0.45, 0.12, 0.3, if k % 2 == 0 then "pink" else "leaf", "Bloom")
	end
	for _, x in { -1.25, 1.25 } do
		ball(m, f, x, 0.9, 0.15, 0.3, "leaf", "Vine")
		ball(m, f, x, 1.4, 0.15, 0.25, "purple", "Bloom")
	end
end
B.gazebo = function(m, f)
	box(m, f, 0, 0.15, 0, 3.6, 0.3, 3.6, "wood", "Deck")
	for k = 0, 5 do
		local a = k * math.pi / 3
		box(m, f, math.cos(a) * 1.5, 1.2, math.sin(a) * 1.5, 0.15, 1.9, 0.15, "white", "Post")
		box(m, f, math.cos(a) * 1.5, 0.55, math.sin(a) * 1.5, 0.6, 0.06, 0.06, "white", "Rail")
	end
	cyl(m, f, 0, 2.2, 0, 3.6, 0.15, "white", "Eave")
	Blocks.part(m, { size = Vector3.new(3.0, 1.4, 3.0), cf = f * CFrame.new(0, 2.95, 0), color = "green", shape = "Ball", name = "Roof", collide = false })
	box(m, f, 0, 3.75, 0, 0.12, 0.5, 0.12, "gold", "Finial")
	box(m, f, 0, 0.55, 0, 0.8, 0.5, 0.8, "wood_dark", "Table")
	box(m, f, 0, 0.88, 0, 0.3, 0.2, 0.3, "pink", "Vase")
end
B.topiary = function(m, f)
	box(m, f, 0, 0.25, 0, 0.8, 0.5, 0.8, "pot", "Planter")
	box(m, f, 0, 0.7, 0, 0.12, 0.5, 0.12, "wood_dark", "Stem")
	ball(m, f, 0, 1.1, 0, 0.9, "leaf_dark", "Ball")
	ball(m, f, 0, 1.75, 0, 0.6, "leaf", "Ball")
	ball(m, f, 0, 2.15, 0, 0.3, "leaf_dark", "Ball")
end
B.bandstand = function(m, f)
	cyl(m, f, 0, 0.3, 0, 3.6, 0.6, "white", "Stage")
	cyl(m, f, 0, 0.62, 0, 3.4, 0.06, "wood", "Floor")
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(m, f, math.cos(a) * 1.55, 1.6, math.sin(a) * 1.55, 0.12, 2.0, 0.12, "white", "Post")
	end
	cyl(m, f, 0, 2.65, 0, 3.8, 0.15, "berry_red", "Eave")
	Blocks.part(m, { size = Vector3.new(3.2, 1.2, 3.2), cf = f * CFrame.new(0, 3.2, 0), color = "berry_red", shape = "Ball", name = "Roof", collide = false })
	box(m, f, 0, 3.9, 0, 0.1, 0.5, 0.1, "gold", "Finial")
	box(m, f, -0.5, 0.95, 0, 0.6, 0.6, 0.4, "black", "Piano")
	cyl(m, f, 0.6, 0.85, 0.3, 0.5, 0.4, "berry_red", "Drum")
	box(m, f, 0, 0.3, 1.85, 1.0, 0.1, 0.5, "white", "Step")
end
B.clocktower = function(m, f)
	footing(m, f, 3, 3, "rock", 0.15)
	box(m, f, 0, 2.6, 0, 2.0, 5.0, 2.0, "cream", "Tower")
	for _, y in { 0.4, 5.1 } do
		box(m, f, 0, y, 0, 2.2, 0.3, 2.2, "rock", "Band")
	end
	for _, side in { { 0, 1.02, 0 }, { 1.02, 0, math.pi / 2 } } do
		local cf = f * CFrame.new(side[1], 4.3, side[2]) * CFrame.Angles(0, side[3], 0)
		Blocks.part(m, { size = Vector3.new(1.3, 1.3, 0.1), cf = cf, color = "white", name = "ClockFace", collide = false })
		Blocks.part(m, { size = Vector3.new(0.08, 0.5, 0.04), cf = cf * CFrame.new(0, 0.2, 0.07), color = "black", name = "Hand", collide = false })
		Blocks.part(m, { size = Vector3.new(0.35, 0.08, 0.04), cf = cf * CFrame.new(0.15, 0, 0.07), color = "black", name = "Hand", collide = false })
		Blocks.part(m, { size = Vector3.new(1.45, 1.45, 0.06), cf = cf * CFrame.new(0, 0, -0.03), color = "gold", name = "ClockRim", collide = false })
	end
	window(m, f, 0, 2.2, 1.0, 0.4, 0.8)
	door(m, f * CFrame.new(0, 0.15, 0), 0, 1.0, 0.7, 1.2, "wood_dark")
	-- a stepped blue spire roof
	for k, w in { 2.4, 1.8, 1.2, 0.6 } do
		box(m, f, 0, 5.4 + k * 0.32, 0, w, 0.32, w, if k % 2 == 1 then "blue" else "window", "Roof")
	end
	box(m, f, 0, 7.0, 0, 0.1, 0.6, 0.1, "gold", "Spire")
end
B.canal = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 3, "rock", "Bank")
	box(m, f, 0, 0.1, 0, 4, 0.1, 1.8, "water", "Canal"):SetAttribute("PixelWater", 2)
	for _, z in { -1.0, 1.0 } do
		box(m, f, 0, 0.2, z, 4, 0.2, 0.25, "rock_dark", "Edge")
	end
	-- an arched footbridge across it
	for k = 0, 6 do
		local t = (k - 3) / 3
		box(m, f, 0, 0.55 - math.abs(t) * 0.35, t * 1.2, 1.2, 0.12, 0.42, "wood", "Plank")
	end
	for _, x in { -0.6, 0.6 } do
		for k = 0, 4 do
			local t = (k - 2) / 2
			box(m, f, x, 0.85 - math.abs(t) * 0.3, t * 1.2, 0.08, 0.5, 0.08, "wood_dark", "Baluster")
		end
	end
	box(m, f, 1.5, 0.15, 0.3, 0.9, 0.15, 0.5, "berry_red", "Boat")
	cyl(m, f, -1.4, 0.16, -0.3, 0.4, 0.04, "leaf", "LilyPad")
end
B.grandarch = function(m, f)
	for _, x in { -2.1, 2.1 } do
		box(m, f, x, 1.8, 0, 0.8, 3.6, 1.2, "white", "Pier")
		box(m, f, x, 0.2, 0, 1.0, 0.4, 1.4, "rock", "Plinth")
	end
	for k = 0, 8 do
		local a = math.pi * k / 8
		box(m, f, -math.cos(a) * 1.7, 3.6 + math.sin(a) * 1.0, 0, 0.7, 0.5, 1.2, "white", "Arch")
	end
	box(m, f, 0, 4.9, 0, 5.0, 0.6, 1.3, "cream", "Attic")
	box(m, f, 0, 4.9, 0.66, 2.0, 0.35, 0.05, "gold", "Plaque")
	box(m, f, 0, 5.35, 0, 1.0, 0.3, 0.6, "gold", "Crest")
	for _, x in { -2.1, 2.1 } do
		box(m, f, x, 2.5, 0.62, 0.4, 0.6, 0.04, "gold", "Medallion")
	end
end
B.observatory = function(m, f)
	footing(m, f, 4, 4, "rock", 0.15)
	cyl(m, f, 0, 1.3, -0.2, 3.2, 2.3, "cream", "Drum")
	cyl(m, f, 0, 2.5, -0.2, 3.4, 0.2, "rock", "Cornice")
	Blocks.part(m, { size = Vector3.new(3.2, 3.2, 3.2), cf = f * CFrame.new(0, 2.6, -0.2), color = "steel", shape = "Ball", name = "Dome", collide = false })
	box(m, f, 0, 3.9, 0.4, 0.5, 1.4, 0.4, "night", "Slit")
	Blocks.part(m, { size = Vector3.new(0.35, 0.35, 1.8), cf = f * CFrame.new(0, 4.2, 0.6) * CFrame.Angles(math.rad(-35), 0, 0), color = "gold", name = "Telescope", collide = false })
	door(m, f * CFrame.new(0, 0.15, 0), 0, 1.4, 0.7, 1.2, "blue")
	for _, a in { -0.7, 0.7 } do
		window(m, f, math.sin(a) * 1.6, 1.4, math.cos(a) * 1.6 - 0.2, 0.35, 0.5)
	end
	streetLamp(m, f, 1.6, 1.6)
end
B.crystalfountain = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "white", "Paving")
	cyl(m, f, 0, 0.35, 0, 4.6, 0.6, "white", "Basin")
	cyl(m, f, 0, 0.68, 0, 4.8, 0.1, "gold", "Rim")
	-- (the water a little above the rim's top, so the gold shows as a ring round it)
	cyl(m, f, 0, 0.75, 0, 4.0, 0.06, "shallow", "Water"):SetAttribute("PixelWater", 2)
	for k = 0, 5 do
		local a = k * math.pi / 3
		local h = 1.2 + (k % 2) * 0.8
		Blocks.part(m, { size = Vector3.new(0.35, h, 0.35), cf = f * CFrame.new(math.cos(a) * 0.9, 0.6 + h / 2, math.sin(a) * 0.9) * CFrame.Angles(math.rad(12) * math.cos(a), 0, math.rad(12) * math.sin(a)), color = if k % 2 == 0 then "purple" else "window", name = "Crystal", collide = false })
	end
	Blocks.part(m, { size = Vector3.new(0.6, 2.8, 0.6), cf = f * CFrame.new(0, 2.0, 0), color = "pink", name = "Crystal", neon = true, collide = false })
	ball(m, f, 0, 3.6, 0, 0.5, "white", "Spray")
	for _, p in { { 1.5, 1.0 }, { -1.3, 1.2 }, { 1.0, -1.5 } } do
		box(m, f, p[1], 0.7, p[2], 0.15, 0.04, 0.15, "gold", "Coin")
	end
end
B.sunspire = function(m, f)
	box(m, f, 0, 0.25, 0, 3, 0.5, 3, "cream", "Base")
	for i = 0, 4 do
		local w = 1.8 - i * 0.3
		box(m, f, 0, 0.5 + i * 1.3 + 0.65, 0, w, 1.3, w, if i % 2 == 0 then "white" else "cream", "Spire")
		box(m, f, 0, 0.5 + (i + 1) * 1.3, 0, w + 0.12, 0.12, w + 0.12, "gold", "Band")
	end
	Blocks.part(m, { size = Vector3.new(0.5, 1.4, 0.5), cf = f * CFrame.new(0, 7.7, 0), color = "gold", shape = "Wedge", name = "Tip", collide = false })
	ball(m, f, 0, 7.3, 0, 0.7, "yellow", "Sun").Material = Enum.Material.Neon
	for _, x in { -1.2, 1.2 } do
		box(m, f, x, 0.75, 1.2, 0.25, 0.3, 0.25, "yellow", "Lamp", true)
	end
end
B.monument = function(m, f)
	box(m, f, 0, 0.15, 0, 4, 0.3, 4, "rock", "Plinth")
	box(m, f, 0, 0.5, 0, 3.2, 0.4, 3.2, "white", "Step")
	box(m, f, 0, 1.3, 0, 2.0, 1.2, 2.0, "cream", "Pedestal")
	box(m, f, 0, 1.3, 1.02, 1.4, 0.5, 0.04, "gold", "Plaque")
	-- the founder in bronze: boots, coat, a raised arm holding a spyglass, a captain's hat
	box(m, f, -0.25, 2.2, 0, 0.35, 0.6, 0.4, "gold", "Leg")
	box(m, f, 0.25, 2.2, 0, 0.35, 0.6, 0.4, "gold", "Leg")
	box(m, f, 0, 3.0, 0, 1.0, 1.1, 0.6, "gold", "Coat")
	box(m, f, 0, 3.9, 0, 0.8, 0.8, 0.7, "gold", "Head")
	box(m, f, 0, 4.4, 0, 1.0, 0.15, 0.8, "gold", "HatBrim")
	box(m, f, 0, 4.6, 0, 0.6, 0.3, 0.5, "gold", "Hat")
	box(m, f, 0.65, 3.6, 0, 0.3, 1.0, 0.3, "gold", "Arm")
	box(m, f, 0.65, 4.2, 0.3, 0.15, 0.15, 0.7, "gold", "Spyglass")
	box(m, f, -0.65, 2.9, 0, 0.3, 0.9, 0.3, "gold", "Arm")
	for _, c in { { -1.7, -1.7 }, { 1.7, -1.7 }, { -1.7, 1.7 }, { 1.7, 1.7 } } do
		box(m, f, c[1], 0.55, c[2], 0.35, 0.5, 0.35, "yellow", "Lamp", true)
	end
end


------------------------------------------------------------------ the islands past Driftling Haven (GAME_DESIGN 4.1)
-- The request of 2026-11-14: "allow expansion up to level 20, you can make the previous levels of expansion a bit
-- cheaper too. add decor, huts, work buildings ... and other details as required for this". Our own designs, each a
-- step up from the city's: taller, more of its trade on show, a light or two.


------------------------------------------------------------------ the Tree of Life (GAME_DESIGN 6; Logic/Tree)
-- Tree of Life (8 x 8; `lvl` its stage, 1 .. 6, Logic/Tree.stage: it grows grander with the island: from the second
-- stage a taller trunk, a crown climbing and spreading wider, more runes, blossom, fruit, lanterns and lit stones; from
-- the fourth a crown in full blossom, a ring of light over it and a second ring of light on the ground; on the islands
-- past Driftling Haven (the request of 2026-11-14: "allow expansion up to level 20 ... and other details as required
-- for this") the fifth adds a lantern under every limb, a second ring of light over the crown and three stones floating
-- round the trunk, each with its glowing mark, and the sixth gold leaves in the crown, a third ring of light on the
-- ground and a ring of standing stones round the eggs' lawn). The request
-- (2026-11-12): "make the tree of life more like a tree of life, reference references for it, make it look bigger and
-- more grand". After the old pictures of a world tree (our own design): a great trunk of three strands braided round
-- each other, wide roots that spread over the ground the way the limbs spread overhead (as above, so below), a ring
-- of standing stones round its foot (the circle of life), a glowing hollow at the front (`Pod`), glowing marks winding
-- up the bark, long limbs holding out clouds of leaves with sky between them, aerial roots and blossom hanging from
-- them, gold fruit glowing under them, a ring of light on the ground, and motes of light drifting round. Round the
-- ring of light a wide mossy lawn where its eggs lie (2026-11-13: "it now spawns eggs around it"): they are the
-- client's (Controllers/EggView), on a circle DecorModels.EGG_RING studs from its middle. DecorModels.HOLLOW: the
-- hollow's foot in the model's own frame.
DecorModels.HOLLOW = Vector3.new(0, 0, 1.25)
DecorModels.EGG_RING = 3.45
B.tree = function(m, f, stage)
	local s = math.clamp(stage or 1, 1, 6)
	-- what each stage adds (the ground, the stones and the roots stay inside the inner 6 x 6 of its footprint, the eggs'
	-- lawn round them; the trunk rises, the
	-- crown climbs and spreads, and the light and fruit grow with it)
	local hs = ({ 1, 1.18, 1.36, 1.55, 1.68, 1.8 })[s] -- the top cloud's height
	local ys = ({ 1, 1.1, 1.2, 1.3, 1.37, 1.44 })[s] -- the limbs' and the ring of clouds' height (the crown spreads more than it climbs)
	local rs = ({ 1, 1.15, 1.32, 1.5, 1.58, 1.66 })[s] -- the crown's spread
	local ts = ({ 1, 1.1, 1.2, 1.3, 1.36, 1.42 })[s] -- the trunk's girth
	local cs = ({ 1, 1.1, 1.2, 1.3, 1.36, 1.42 })[s] -- each leaf cloud's size
	local function part(size: Vector3, cf: CFrame, color: string, name: string, neon: boolean?)
		return Blocks.part(m, { size = size, cf = f * cf, color = color, name = name, neon = neon, collide = false })
	end
	-- the ground: a round mossy lawn wide enough for the ring of eggs, a soft rim of clover round it, a darker ring of
	-- moss round the trunk
	cyl(m, f, 0, 0.02, 0, 7.8, 0.04, "leaf", "EggLawn")
	cyl(m, f, 0, 0.03, 0, 5.9, 0.06, "grass_dark", "Lawn")
	cyl(m, f, 0, 0.07, 0, 3.6, 0.06, "leaf_dark", "Moss")
	-- the circle of standing stones round its foot (a gap at the front for the hollow); more of them glow as it grows:
	-- every third, then every other one, then all of them
	local glowEvery = ({ 3, 2, 1, 1, 1, 1 })[s]
	for k = 0, 9 do
		local a = (k + 0.5) / 10 * math.pi * 2
		local h = (if k % 3 == 0 then 0.95 else 0.7) * (if s >= 4 then 1.2 else 1)
		local x, z = math.sin(a) * 2.6, math.cos(a) * 2.6
		if z > 2.3 then
			continue
		end
		part(Vector3.new(0.45, h, 0.32), CFrame.new(x, h / 2, z) * CFrame.Angles(0, a, 0), if k % 2 == 0 then "rock" else "rock_dark", "Stone")
		part(Vector3.new(0.47, 0.1, 0.34), CFrame.new(x, h + 0.04, z) * CFrame.Angles(0, a, 0), if s >= 4 then "gold" else "leaf_dark", "StoneMoss")
		if k % glowEvery == 0 then
			-- a glowing mark carved in the stone
			part(Vector3.new(0.14, 0.3, 0.04), CFrame.new(x, h * 0.55, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.17), "screen_on", "Glyph", true)
		end
	end
	-- wide roots spreading over the ground, as the limbs spread overhead: each in two lengths, sloping down
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + 0.2
		if math.abs(((a + math.pi) % (math.pi * 2)) - math.pi) < 0.3 then
			continue -- (the front stays clear: the hollow)
		end
		local dx, dz = math.sin(a), math.cos(a)
		part(Vector3.new(0.7 * ts, 0.55 * ts, 1.5), CFrame.new(dx * 1.1 * ts, 0.32 * ts, dz * 1.1 * ts) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(14), 0, 0), if k % 2 == 0 then "wood_dark" else "wood", "Root")
		part(Vector3.new(0.45, 0.35, 1.2), CFrame.new(dx * 2.0, 0.16, dz * 2.0) * CFrame.Angles(0, a + 0.15, 0) * CFrame.Angles(math.rad(8), 0, 0), "wood_dark", "Root")
	end
	-- the trunk: one smooth core from the ground to the limbs, and three thick strands braided round it, each one round
	-- tube rising straight from the ground, then twisting as it climbs and narrowing a little (the request of
	-- 2026-11-13: "make the trunk connected smoothly as well without the stepped boxes"; nothing below the ground, so
	-- the model's box is as it was)
	local base = 7.0 * ys -- where the limbs leave the trunk
	local core = 1.7 * ts
	cyl(m, f, 0, base / 2, 0, core, base, "wood_dark", "Trunk")
	ball(m, f, 0, base, 0, core, "wood_dark", "Trunk")
	local segs = math.floor(8 * ys + 0.5)
	local rise = (base - 0.6 * ts) / segs
	for st = 0, 2 do
		local a0 = st / 3 * math.pi * 2
		local pts: { Vector3 } = { Vector3.new(math.sin(a0) * 0.7 * ts, 0, math.cos(a0) * 0.7 * ts) }
		for i = 0, segs do
			local a = a0 + i * 0.45
			local r = (0.7 - i * 0.03 / ys) * ts
			table.insert(pts, Vector3.new(math.sin(a) * r, 0.6 * ts + i * rise, math.cos(a) * r))
		end
		tube(m, f, pts, function(i: number): number
			return (1.15 - math.max(0, i - 2) * 0.04 / ys) * ts
		end, function(i: number): string
			return if (st + i) % 2 == 1 then "wood" else "wood_dark"
		end, "Strand", true)
	end
	-- glowing marks winding up the bark (more as it grows)
	for i = 0, 3 + 3 * s - 1 do
		local a = i * 0.9 + 0.6
		local r = core / 2 + 0.1
		part(Vector3.new(0.12, 0.34, 0.08), CFrame.new(math.sin(a) * r, 1.8 + i * 0.8 * (ys * 6 / (3 + 3 * s)), math.cos(a) * r) * CFrame.Angles(0, a, 0), "screen_on", "Rune", true)
	end
	-- the hollow at the front: an arched opening of dark wood, a warm light in it
	local hz = 1.18 * ts
	part(Vector3.new(1.0, 1.25, 0.2), CFrame.new(0, 0.7, hz), "black", "Hollow")
	part(Vector3.new(0.7, 0.95, 0.1), CFrame.new(0, 0.62, hz + 0.08), "gold", "Pod", true)
	part(Vector3.new(1.3, 0.22, 0.24), CFrame.new(0, 1.4, hz + 0.02), "wood_dark", "Lintel")
	part(Vector3.new(0.22, 1.3, 0.24), CFrame.new(-0.6, 0.65, hz + 0.02), "wood", "Jamb")
	part(Vector3.new(0.22, 1.3, 0.24), CFrame.new(0.6, 0.65, hz + 0.02), "wood", "Jamb")
	-- the crown: clouds of leaves held out on long limbs, one at the top and a ring round it at two heights (eight
	-- from the third stage, and an upper ring of four), with sky between them so the limbs show
	local function limb(p0: Vector3, p1: Vector3, thick: number, color: string)
		local mid = (p0 + p1) / 2
		part(Vector3.new(thick, thick, (p1 - p0).Magnitude + thick * 0.5), CFrame.lookAt(mid, p1), color, "Branch")
	end
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
	local top = Vector3.new(0, base, 0)
	for k, c in clouds do
		-- the limb out to it, forking once on the way
		local bend = Vector3.new(c.X * 0.55, base + 0.6 + (c.Y - base - 0.6) * 0.35, c.Z * 0.55)
		limb(top, bend, (if k == 1 then 0.75 else 0.6) * ts, if k % 2 == 0 then "wood" else "wood_dark")
		limb(bend, c - Vector3.new(0, 0.6, 0), 0.45 * ts, "wood_dark")
		if k > 1 then
			local side = Vector3.new(-c.Z, 0, c.X).Unit * 1.1
			limb(bend, c + side * 0.8 - Vector3.new(0, 0.4, 0), 0.3, "wood_dark")
		end
		-- the cloud: a dark underside, a light top, side puffs (in full blossom at the last stage)
		local big = (if k == 1 then 3.0 else 2.6) * cs
		ball(m, f, c.X, c.Y - 0.55, c.Z, big * 0.85, "leaf_dark", "LeavesUnder")
		ball(m, f, c.X, c.Y, c.Z, big, "leaf", "Leaves")
		for j = 0, 3 do
			local a = j / 4 * math.pi * 2 + k
			ball(m, f, c.X + math.sin(a) * big * 0.42, c.Y - 0.15, c.Z + math.cos(a) * big * 0.42, big * 0.7, if j % 2 == 0 then "leaf" else "leaf_dark", "Leaves")
		end
		ball(m, f, c.X + 0.2, c.Y + big * 0.32, c.Z - 0.1, big * 0.6, "leaf", "Leaves")
		if s >= 4 then
			ball(m, f, c.X - 0.3, c.Y + big * 0.42, c.Z + 0.2, big * 0.38, if k % 2 == 0 then "pink" else "white", "Blossom")
		end
		if s >= 6 and k % 2 == 1 then
			-- gold leaves catching the light at the last stage
			ball(m, f, c.X + 0.4, c.Y + big * 0.2, c.Z - 0.35, big * 0.42, "gold", "GoldLeaves")
		end
	end
	-- blossom through the clouds (more as it grows)
	for k = 0, 20 + 9 * (s - 1) do
		local c = clouds[k % #clouds + 1]
		local a = k * 2.4
		ball(m, f, c.X + math.sin(a) * 1.2 * cs, c.Y + 0.4 + (k % 3) * 0.25, c.Z + math.cos(a) * 1.2 * cs, if k % 3 == 0 then 0.6 else 0.45, if k % 2 == 0 then "pink" else "white", "Blossom")
	end
	-- aerial roots hanging from the clouds (the roots again, overhead), longer as it grows
	for k = 2, #clouds do
		local c = clouds[k]
		local len = (1.0 + (k % 3) * 0.6) * (1 + 0.25 * (s - 1))
		local out = Vector3.new(c.X, 0, c.Z).Unit * 1.2 * cs
		part(Vector3.new(0.12, len, 0.12), CFrame.new(c.X + out.X, c.Y - 1.1 - len / 2, c.Z + out.Z), "leaf_dark", "Vine")
		part(Vector3.new(0.22, 0.18, 0.22), CFrame.new(c.X + out.X, c.Y - 1.1 - len, c.Z + out.Z), if k % 2 == 0 then "pink" else "leaf", "VineTip")
	end
	-- a ring of light on the ground round the stones (the circle of life), in short glowing dashes; a second ring
	-- inside it at the last stage
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
	-- gold fruit glowing under the clouds (three a cloud from the third stage)
	for k = 2, #clouds do
		local c = clouds[k]
		for j = 0, (if s >= 3 then 2 else 1) do
			local a = j * (math.pi * 2 / (if s >= 3 then 3 else 2)) + k
			local x, y, z = c.X + math.sin(a) * 0.9 * cs, c.Y - 1.55 * cs - j * 0.2, c.Z + math.cos(a) * 0.9 * cs
			part(Vector3.new(0.06, 0.45, 0.06), CFrame.new(x, y + 0.42, z), "wood_dark", "Stalk")
			ball(m, f, x, y, z, 0.5, "gold", "Fruit").Material = Enum.Material.Neon
		end
	end
	-- lanterns of light hanging from the lower limbs (from the second stage; under every limb from the fifth)
	if s >= 2 then
		for k = 2, ring + 1, if s >= 5 then 1 else 2 do
			local c = clouds[k]
			local x, z = c.X * 0.7, c.Z * 0.7
			local y = base + 0.2
			part(Vector3.new(0.05, 0.6, 0.05), CFrame.new(x, y - 0.3, z), "wood_dark", "Stalk")
			part(Vector3.new(0.3, 0.38, 0.3), CFrame.new(x, y - 0.75, z), "yellow", "Lantern", true)
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
	-- stones floating round the trunk from the fifth stage: a rough rock with moss on top and a glowing mark, a few
	-- pebbles under it
	if s >= 5 then
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 1.1
			local x, y, z = math.sin(a) * 3.3, 4.2 + k * 0.9, math.cos(a) * 3.3
			part(Vector3.new(0.9, 0.6, 0.8), CFrame.new(x, y, z) * CFrame.Angles(0.15, a, 0.1), "rock", "Floating")
			part(Vector3.new(0.6, 0.36, 0.5), CFrame.new(x, y - 0.42, z) * CFrame.Angles(0, a + 0.4, 0), "rock_dark", "Floating")
			part(Vector3.new(0.92, 0.12, 0.82), CFrame.new(x, y + 0.33, z) * CFrame.Angles(0.15, a, 0.1), "leaf_dark", "FloatingMoss")
			part(Vector3.new(0.12, 0.28, 0.04), CFrame.new(x, y, z) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 0.41), "screen_on", "Glyph", true)
			part(Vector3.new(0.18, 0.18, 0.18), CFrame.new(x + 0.2, y - 0.95, z - 0.1), "rock_dark", "Pebble")
		end
	end
	-- a ring of low standing stones round the eggs' lawn at the last stage, each with a gold cap (a gap at the front)
	if s >= 6 then
		for k = 0, 15 do
			local a = (k + 0.5) / 16 * math.pi * 2
			local x, z = math.sin(a) * 3.85, math.cos(a) * 3.85
			if z > 3.3 then
				continue
			end
			part(Vector3.new(0.3, 0.42, 0.24), CFrame.new(x, 0.21, z) * CFrame.Angles(0, a, 0), if k % 2 == 0 then "rock" else "rock_dark", "OuterStone")
			part(Vector3.new(0.32, 0.08, 0.26), CFrame.new(x, 0.45, z) * CFrame.Angles(0, a, 0), "gold", "OuterCap")
		end
	end
	-- motes of light drifting round it (more as it grows)
	local motes = { { -2.4, 3.2, 1.6 }, { 2.2, 4.4, 1.2 }, { -1.6, 5.6, -2.0 }, { 2.6, 2.4, -1.0 }, { 0.6, 6.4, 2.4 }, { -2.8, 6.8, 0.2 } }
	for k = 1, 3 * (s - 1) do
		local a = k * 2.1
		table.insert(motes, { math.sin(a) * (2.4 + (k % 3) * 0.5) * rs, 3 + (k % 5) * 1.3 * ys, math.cos(a) * (2.4 + (k % 3) * 0.5) * rs })
	end
	for k, c in motes do
		part(Vector3.new(0.18, 0.18, 0.18), CFrame.new(c[1], c[2] * (if k <= 6 then ys else 1), c[3]), if k % 2 == 0 then "yellow" else "white", "Mote", true)
	end
	-- mushrooms and flowers among the roots
	for k, c in { { -2.0, 1.4 }, { 1.7, 1.6 }, { -1.5, -2.0 }, { 2.1, -1.2 } } do
		box(m, f, c[1], 0.19, c[2], 0.12, 0.34, 0.12, "cream", "Stalk")
		box(m, f, c[1], 0.4, c[2], 0.36, 0.14, 0.36, if k % 2 == 0 then "berry_red" else "orange", "Cap")
	end
	for k, c in { { -1.2, 2.1 }, { 1.2, 2.1 }, { -2.3, -0.4 }, { 2.4, 0.4 }, { 0.3, -2.4 } } do
		box(m, f, c[1], 0.13, c[2], 0.22, 0.12, 0.22, if k % 2 == 0 then "yellow" else "pink", "Flower")
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
	Blocks.windy(m) -- leaves sway, pennants ripple
	return m
end

function DecorModels.has(id: string): boolean
	return B[id] ~= nil
end

return DecorModels
