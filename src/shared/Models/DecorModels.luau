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

-- Palm Tree (3 x 3): StreetModels' shore palm, a little fuller. A ringed trunk leaning out from its foot in one smooth
-- curve and coming upright under the crown (round segments, a thin dark ring at each joint), a fibrous boot, eight
-- fronds that rise, arch and droop (each a fold of toothed leaflet blades, the upper ones lighter), two young ones
-- spearing up, two dead ones hanging, a bunch of coconuts; at its foot a mound of sand with a fallen coconut, a split
-- one and a tuft of beach grass.
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
	-- at its foot: a fallen coconut, a split one showing its white, beach grass
	ball(m, f, -0.45, 0.42, 0.55, 0.5, "wood_dark", "Coconut")
	part(f * CFrame.new(0.75, 0.25, 0.55) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 0.5, 0.5, "wood_dark", "Husk", "Cylinder")
	part(f * CFrame.new(0.75, 0.3125, 0.55) * CFrame.Angles(0, 0, math.pi / 2), 0.25, 0.25, 0.25, "cream", "Flesh", "Cylinder")
	for k, b in { { -0.85, -0.45, 0.5, 0.2 }, { -0.7, -0.6, 0.75, -0.25 }, { -0.95, -0.7, 0.5, 0.35 } } do
		part(f * CFrame.new(b[1], 0.2 + b[3] / 2, b[2]) * CFrame.Angles(b[4], 0, b[4] * 0.6), 0.25, b[3], 0.25, if k == 2 then "leaf_dark" else "leaf", "Blade")
	end
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
-- the third eight clouds round the crown and four over them and three fruit a cloud; from the fourth a crown in full
-- blossom, gold caps on the stones, a ring of light over it and a second ring of light on the
-- ground; on the islands past Driftling Haven (the request of 2026-11-14: "allow expansion up to level 20 ... and other
-- details as required for this") the fifth adds a lantern under every limb, a second ring of light over the crown and
-- three stones floating round the trunk, each with its glowing mark, and the sixth gold leaves in the crown, a third
-- ring of light on the ground and low standing stones with gold caps in the lawn's corners). The request
-- (2026-11-12): "make the tree of life more like a tree of life, reference references for it, make it look bigger and
-- more grand". After the old pictures of a world tree (our own design): a great trunk of three strands braided round
-- each other, wide roots that spread over the ground the way the limbs spread overhead (as above, so below), a ring
-- of standing stones round its foot (the circle of life), a glowing hollow at the front (`Pod`), glowing marks winding
-- up the bark, long limbs holding out clouds of leaves with sky between them, aerial roots and blossom hanging from
-- them, gold fruit glowing under them, a ring of light on the ground, and motes of light drifting round. Round the
-- ring of light a wide mossy lawn where its eggs lie (2026-11-13: "it now spawns eggs around it"): they are the
-- client's (Controllers/EggView), on a circle DecorModels.EGG_RING studs from its middle. DecorModels.HOLLOW: the
-- hollow's foot in the model's own frame.
-- Rebuilt in more detail on 2026-11-15 ("can you also rebuild the tree of life", after every building was reworked
-- the bakery's way): bark with knots and moss on it and the runes facing the camera; roots flaring from high on the
-- trunk, the big ones dipping into the ground and coming up again past the stones, with rootlets; stones with moss and
-- lichen; a bigger glowing doorway in an arched frame, with a step and a lantern either side; a bird house on the
-- trunk; leaf clouds of more puffs in three greens, lit on top and dark underneath; vines that sway as they hang, with
-- flowers; mushrooms, flowers, fallen blossom and fireflies among the roots. The eggs' ring (3 to 3.9 studs out, all
-- the way round: the eggs lie on the south and east whichever way the tree is turned) stays clear of anything that
-- stands up off the lawn; only the ring of light lies flat on it.
DecorModels.HOLLOW = Vector3.new(0, 0, 1.25)
DecorModels.EGG_RING = 3.45
-- (the side the camera sees, on the ground: the view looks down from the south-east)
local TREE_CAM = Vector3.new(1, 0, 1).Unit
-- (toward the sun, Render/Shading's: the lit side of a cloud of leaves)
local TREE_SUN = Vector3.new(-0.45, 0.8, 0.35).Unit
B.tree = function(m, f, stage)
	local s = math.clamp(stage or 1, 1, 6)
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
	-- a piece lying on a surface at p, its face toward n and its height along up
	local function onFace(p: Vector3, n: Vector3, up: Vector3, w: number, h: number, d: number, color: string, name: string, neon: boolean?): BasePart
		return part(Vector3.new(w, h, d), CFrame.lookAt(p, p + n, up), color, name, neon)
	end
	-- a round limb, root or strand through pts, narrowing from d0 to d1, its two colours in turn
	local function bough(pts: { Vector3 }, d0: number, d1: number, c1: string, c2: string, name: string, cap: boolean?)
		local n = #pts - 1
		tube(m, f, pts, function(i: number): number
			return d0 + (d1 - d0) * (i - 1) / math.max(1, n - 1)
		end, function(i: number): string
			return if i % 2 == 1 then c1 else c2
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
	-- eggs: each with moss on top and down its face and a fleck of lichen; more of them glow as it grows (every third,
	-- then every other one, then all of them) and from the fourth stage they wear gold caps
	local glowEvery = ({ 3, 2, 1, 1, 1, 1 })[s]
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
		part(Vector3.new(0.25, 0.25, 0.25), at * CFrame.new(-0.25, 0.375, 0.25), if k % 2 == 0 then "straw" else "cream", "Lichen")
		if k % glowEvery == 0 then
			-- a glowing mark carved in the stone
			part(Vector3.new(0.25, 0.5, 0.25), at * CFrame.new(0.3125, h * 0.5, 0.1875), "screen_on", "Glyph", true)
			part(Vector3.new(0.25, 0.25, 0.25), at * CFrame.new(0, h * 0.5 - 0.125, 0.25), "screen_on", "Glyph", true)
		end
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
			bough({ pts[3], flat(a + (if k % 2 == 0 then 0.32 else -0.32), r3 + 0.3, -0.02) }, 0.25, 0.25, "skin4", "skin4", "Root")
		end
		if big and front then
			local h0 = math.min(r3 + 0.6, 2.25)
			bough({ flat(a, h0, -0.04), flat(a, h0 + 0.25, 0.18), flat(a, h0 + 0.5, -0.04) }, 0.3, 0.25, "wood_dark", "skin4", "Root")
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
		tube(m, f, pts, strandDia, function(i: number): string
			return if (st + i) % 2 == 1 then "wood" else "wood_dark"
		end, "Strand", true)
	end
	-- the bark: knots with a dark heart and moss low down, on the side the camera sees; and the glowing marks winding
	-- up it (more as it grows), each where a strand faces the camera
	local toCam = (TREE_CAM * 0.866 + UP * 0.5).Unit
	local runeSpots: { { p: Vector3, n: Vector3 } } = {}
	for st, pts in strands do
		for i = 2, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid = (a + b) / 2
			local out = Vector3.new(mid.X, 0, mid.Z).Unit
			if not seen(out) then
				continue
			end
			local dir = (b - a).Unit
			local rad = strandDia(i) / 2
			if (i + st) % 3 == 0 and i < #pts - 1 then
				-- a knot: a swelling with a dark heart
				local kn = (out - dir:Cross(out).Unit * 0.5).Unit
				knob(b + kn * (rad - 0.12), 0.5 * ts, "skin4", "Knot")
				knob(b + kn * (rad + 0.08), 0.25, "skin5", "Knot")
			end
			if i <= 3 then
				knob(a + (out + UP * 0.6).Unit * (rad - 0.06), 0.5, "moss", "BarkMoss")
			end
			if out:Dot(TREE_CAM) > 0.2 then
				local n = (toCam - dir * toCam:Dot(dir)).Unit
				for _, t in { 0.3, 0.75 } do
					local p = a + (b - a) * t + n * (rad - 0.0625)
					if p.Y > 1.9 and p.Y < base - 0.4 then
						table.insert(runeSpots, { p = p, n = n })
					end
				end
			end
		end
	end
	table.sort(runeSpots, function(x, y)
		return x.p.Y < y.p.Y
	end)
	local nRunes = math.min(2 + 2 * s, #runeSpots)
	for i = 1, nRunes do
		local sp = runeSpots[math.floor((i - 0.5) * #runeSpots / nRunes) + 1]
		onFace(sp.p, sp.n, UP, 0.25, 0.5, 0.25, "screen_on", "Rune", true)
		if i % 3 == 0 then
			-- (a dot beside it: a mark of two strokes)
			local side = UP:Cross(sp.n).Unit
			onFace(sp.p + side * 0.25 + UP * 0.125, sp.n, UP, 0.25, 0.25, 0.25, "screen_on", "Rune", true)
		end
	end

	------------------------------------------------ the hollow
	-- at the front, between two strands: a dark arched opening with a warm light in it, in a frame of wood with a
	-- glowing mark on its keystone, a stone step before it and a lantern on a post either side
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
	part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(0, 1.81, z0 + 0.4375), "screen_on", "Rune", true)
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
	local right = Vector3.new(1, 0, -1).Unit -- (the screen's right, on the ground)
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
	-- blossom over the clouds (more as it grows)
	for k = 0, 16 + 6 * (s - 1) do
		local ci = k % #clouds + 1
		local c, big = clouds[ci], sizeOf(ci)
		local a = k * 2.4
		local dir = Vector3.new(math.sin(a), 0.5 + (k % 3) * 0.35, math.cos(a)).Unit
		knob(c + dir * 0.6 * big, if k % 3 == 0 then 0.5 else 0.375, if k % 3 == 0 then "pink" elseif k % 3 == 1 then "white" else "cherry", "Blossom")
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
		part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(p1 + TREE_CAM * 0.125), if k % 2 == 0 then "pink" else "white", "VineFlower")
		if len > 1.6 then
			part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(p2 + TREE_CAM * 0.125), if k % 2 == 0 then "white" else "pink", "VineFlower")
		end
		knob(p3 - UP * 0.125, 0.375, if k % 2 == 0 then "pink" else "cherry", "VineTip")
	end
	-- gold fruit glowing under the clouds (three a cloud from the third stage), hanging on stalks
	for k = 2, #clouds do
		local c, big = clouds[k], sizeOf(k)
		local n = if s >= 3 then 3 else 2
		for j = 0, n - 1 do
			local a = j * (math.pi * 2 / n) + k
			local x, y, z = c.X + math.sin(a) * 0.32 * big, c.Y - 0.62 * big - j * 0.2, c.Z + math.cos(a) * 0.32 * big
			if j < 2 then
				part(Vector3.new(0.25, 0.5, 0.25), CFrame.new(x, y + 0.45, z), "wood_dark", "Stalk")
			end
			ball(m, f, x, y, z, 0.5, "gold", "Fruit").Material = Enum.Material.Neon
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
	-- stones floating round the trunk from the fifth stage: a rough rock with moss on top and a glowing mark, roots
	-- trailing from it, a pebble under it
	if s >= 5 then
		for k = 0, 2 do
			local a = k / 3 * math.pi * 2 + 1.1
			local x, y, z = math.sin(a) * 3.3, 4.2 + k * 0.9, math.cos(a) * 3.3
			local at = CFrame.new(x, y, z) * CFrame.Angles(0, a, 0)
			part(Vector3.new(1.0, 0.5, 0.75), at, "rock", "Floating")
			part(Vector3.new(0.75, 0.5, 0.5), at * CFrame.new(0.0625, -0.375, 0), "rock_dark", "Floating")
			part(Vector3.new(0.5, 0.25, 0.25), at * CFrame.new(0, -0.75, 0.0), "rock_dark", "Floating")
			part(Vector3.new(0.75, 0.25, 0.5), at * CFrame.new(-0.125, 0.375, 0), "moss", "FloatingMoss")
			part(Vector3.new(0.25, 0.25, 0.25), at * CFrame.new(0.25, 0, 0.4375), "screen_on", "Glyph", true)
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
	-- motes of light drifting round it (more as it grows), and fireflies low among the roots
	local motes = { { -2.4, 3.2, 1.6 }, { 2.2, 4.4, 1.2 }, { -1.6, 5.6, -2.0 }, { 2.6, 2.4, -1.0 }, { 0.6, 6.4, 2.4 }, { -2.8, 6.8, 0.2 } }
	for k = 1, 3 * (s - 1) do
		local a = k * 2.1
		table.insert(motes, { math.sin(a) * (2.4 + (k % 3) * 0.5) * rs, 3 + (k % 5) * 1.3 * ys, math.cos(a) * (2.4 + (k % 3) * 0.5) * rs })
	end
	for k, c in motes do
		part(Vector3.new(0.18, 0.18, 0.18), CFrame.new(c[1], c[2] * (if k <= 6 then ys else 1), c[3]), if k % 2 == 0 then "yellow" else "white", "Mote", true)
	end
	for k = 0, 2 + s // 2 do
		local a = k * 1.9 + 0.9
		local r = 1.3 * ts + 0.45 + (k % 2) * 0.2
		part(Vector3.new(0.25, 0.25, 0.25), CFrame.new(math.sin(a) * r, 1.2 + (k % 4) * 0.4, math.cos(a) * r), "yellow", "Mote", true)
	end
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
