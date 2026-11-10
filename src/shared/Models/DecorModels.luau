--!strict
-- The island's buildings and decor from parts (GAME_DESIGN 4; Data/Buildings). Roblox module (server: PlotService
-- builds the placed pieces; client: Build mode's ghost). `build(id, at, lvl?)`: a model standing on `at` (the
-- footprint's centre on the grass, already turned by the piece's rot), facing +Z before the turn, its footprint
-- Data/Buildings' w x d; an upgraded building (lvl 2, 3) flies a pennant (a gold one at 3). Pieces do not collide
-- (the founder walks through them, never stuck behind one).
local Blocks = require(script.Parent.Blocks)
local Buildings = require(script.Parent.Parent.Data.Buildings)

-- footprints by id (the pennant's corner)
local FOOT: { [string]: { number } } = {}
for _, d in Buildings.list do
	FOOT[d.id] = { d.w, d.d }
end

local DecorModels = {}

type Builder = (m: Model, f: CFrame) -> ()

local function box(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z), color = color, name = name, neon = neon, collide = false })
end
local function ball(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(dia, dia, dia), cf = f * CFrame.new(x, y, z), color = color, shape = "Ball", name = name, collide = false })
end
local function cyl(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, h: number, color: string, name: string?): BasePart
	local p = Blocks.cylY(m, dia, h, f * CFrame.new(x, y, z), color)
	p.CanCollide = false
	if name then
		p.Name = name
	end
	return p
end

-- A wedge (its sloped face toward -Z, full height at +Z before `turn`).
local function wedge(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, turn: number?, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, turn or 0, 0), color = color, shape = "Wedge", name = name, collide = false })
end

-- A gable roof along X over a w x d box whose top is at y: two wedges meeting at the ridge.
local function roof(m: Instance, f: CFrame, y: number, w: number, d: number, h: number, color: string)
	wedge(m, f, 0, y + h / 2, -d / 4, w, h, d / 2, color, 0, "Roof")
	wedge(m, f, 0, y + h / 2, d / 4, w, h, d / 2, color, math.pi, "Roof")
end

local B: { [string]: Builder } = {}


B.flowers = function(m, f)
	box(m, f, 0, 0.2, 0, 2, 0.4, 2, "wood_dark", "Bed")
	box(m, f, 0, 0.35, 0, 1.75, 0.25, 1.75, "leaf_dark", "Soil")
	local cols = { "pink", "yellow", "purple", "berry_red" }
	for i = 0, 3 do
		local x, z = (i % 2) * 0.9 - 0.45, (i // 2) * 0.9 - 0.45
		box(m, f, x, 0.6, z, 0.25, 0.4, 0.25, "leaf", "Stem")
		ball(m, f, x, 0.85, z, 0.6, cols[i + 1], "Bloom")
	end
end

B.bush = function(m, f)
	ball(m, f, 0, 0.8, 0, 2, "leaf", "Bush")
	ball(m, f, 0.5, 0.65, 0.4, 1.25, "leaf_dark", "Bush")
	ball(m, f, -0.4, 1.2, -0.2, 1.0, "leaf", "Bush")
end

B.bench = function(m, f)
	box(m, f, 0, 0.75, 0.1, 3, 0.25, 1, "wood", "Seat")
	box(m, f, 0, 1.4, -0.45, 3, 0.75, 0.25, "wood", "Back")
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 0.4, 0.1, 0.25, 0.75, 0.75, "steel_dark", "Leg")
		box(m, f, x, 1.1, -0.45, 0.25, 1.25, 0.25, "steel_dark", "Arm")
	end
end






B.picnic = function(m, f)
	box(m, f, 0, 1.05, 0, 4, 0.25, 1.5, "wood", "Top")
	for _, x in { -1.6, 1.6 } do
		box(m, f, x, 0.5, 0, 0.25, 1, 1.25, "wood_dark", "Leg")
	end
	for _, z in { -1.2, 1.2 } do
		box(m, f, 0, 0.55, z, 4, 0.25, 0.5, "wood", "Bench")
	end
	box(m, f, -0.8, 1.3, 0, 1.2, 0.25, 0.9, "berry_red", "Cloth")
	cyl(m, f, 0.9, 1.4, 0.1, 0.5, 0.5, "orange", "Cup")
end


B.fountain = function(m, f)
	cyl(m, f, 0, 0.35, 0, 5, 0.7, "steel", "Basin")
	cyl(m, f, 0, 0.6, 0, 4.25, 0.25, "blue", "Water")
	cyl(m, f, 0, 1.3, 0, 1, 1.5, "steel", "Column")
	cyl(m, f, 0, 2.1, 0, 2.25, 0.4, "steel", "Bowl")
	cyl(m, f, 0, 2.3, 0, 1.75, 0.25, "blue", "Water")
	ball(m, f, 0, 2.75, 0, 0.6, "window", "Jet")
end

B.statue = function(m, f)
	box(m, f, 0, 0.6, 0, 2.5, 1.2, 2.5, "steel", "Plinth")
	box(m, f, 0, 1.3, 0, 2.75, 0.25, 2.75, "steel_dark", "Cap")
	-- the guardian of the islets holding up a pearl
	box(m, f, -0.3, 1.9, 0, 0.5, 1, 0.5, "gold", "Leg")
	box(m, f, 0.3, 1.9, 0, 0.5, 1, 0.5, "gold", "Leg")
	box(m, f, 0, 2.9, 0, 1.25, 1.1, 0.75, "gold", "Body")
	box(m, f, 0, 3.95, 0, 1.25, 1, 1, "gold", "Head")
	box(m, f, 0.8, 3.6, 0, 0.4, 1.4, 0.4, "gold", "Arm")
	ball(m, f, 0.8, 4.55, 0, 0.8, "pink", "Pearl")
end




-- The piece's model at `at` (the footprint's centre on the lawn, turned). Unknown ids build nothing.

------------------------------------------------------------------ food
B.patch = function(m, f)
	box(m, f, 0, 0.15, 0, 3, 0.3, 3, "wood_dark", "Bed")
	box(m, f, 0, 0.32, 0, 2.6, 0.1, 2.6, "pot", "Soil")
	for r = -1, 1 do
		for c = -1, 1 do
			box(m, f, c * 0.85, 0.5, r * 0.85, 0.25, 0.35, 0.25, "leaf", "Sprout")
			box(m, f, c * 0.85 + 0.15, 0.62, r * 0.85, 0.25, 0.25, 0.25, if (r + c) % 2 == 0 then "orange" else "leaf_dark", "Leaf")
		end
	end
end

B.pier = function(m, f)
	for _, x in { -1.25, 1.25 } do
		for _, z in { -1.25, 1.25 } do
			box(m, f, x, 0.25, z, 0.25, 0.5, 0.25, "wood_dark", "Post")
		end
	end
	box(m, f, 0, 0.55, 0, 3, 0.25, 3, "wood", "Deck")
	box(m, f, -0.6, 1.25, -0.6, 1.5, 1.2, 1.5, "wood", "Shack")
	roof(m, f * CFrame.new(-0.6, 0, -0.6), 1.85, 1.75, 1.75, 0.6, "berry_red")
	box(m, f, 0.9, 1.4, 0.9, 0.25, 1.75, 0.25, "wood_dark", "Rod")
	box(m, f, 1.1, 2.25, 1.1, 0.25, 0.25, 0.75, "wood_dark", "Rod")
	cyl(m, f, 0.6, 0.9, -0.9, 0.6, 0.5, "steel", "Bucket")
	box(m, f, 0.6, 1.2, -0.9, 0.25, 0.25, 0.5, "blue", "Fish")
end

local function fruitTree(m: Model, f: CFrame, x: number, z: number, fruit: string)
	box(m, f, x, 0.6, z, 0.5, 1.2, 0.5, "wood_dark", "Trunk")
	ball(m, f, x, 1.7, z, 1.6, "leaf", "Crown")
	ball(m, f, x + 0.5, 1.4, z + 0.5, 0.4, fruit, "Fruit")
	ball(m, f, x - 0.5, 1.9, z + 0.3, 0.4, fruit, "Fruit")
end

B.orchard = function(m, f)
	box(m, f, 0, 0.1, 0, 4, 0.2, 4, "grass_dark", "Ground")
	fruitTree(m, f, -1, -1, "berry_red")
	fruitTree(m, f, 1, -1, "orange")
	fruitTree(m, f, -1, 1, "yellow")
	fruitTree(m, f, 1, 1, "berry_red")
end

B.greenhouse = function(m, f)
	box(m, f, 0, 0.2, 0, 4, 0.4, 3, "steel_dark", "Base")
	box(m, f, 0, 1.3, -1.35, 4, 1.8, 0.25, "window", "Glass")
	box(m, f, -1.85, 1.3, 0, 0.25, 1.8, 3, "window", "Glass")
	box(m, f, 1.85, 1.3, 0, 0.25, 1.8, 3, "window", "Glass")
	roof(m, f, 2.2, 4, 3, 1, "window")
	for _, x in { -1.1, 0, 1.1 } do
		box(m, f, x, 0.7, 0.3, 0.6, 0.6, 0.6, "pot", "Pot")
		ball(m, f, x, 1.2, 0.3, 0.8, "leaf", "Plant")
	end
end

------------------------------------------------------------------ wood
B.lumber = function(m, f)
	for k, z in { -0.55, 0.55 } do
		Blocks.part(m, { size = Vector3.new(3, 0.9, 0.9), cf = f * CFrame.new(-0.4, 0.45, z), color = "wood", shape = "Cylinder", name = "Log", collide = false })
		if k == 1 then
			Blocks.part(m, { size = Vector3.new(3, 0.9, 0.9), cf = f * CFrame.new(-0.4, 1.2, 0), color = "wood_dark", shape = "Cylinder", name = "Log", collide = false })
		end
	end
	cyl(m, f, 1.5, 0.35, 0.6, 1, 0.7, "wood_dark", "Stump")
	box(m, f, 1.5, 0.9, 0.6, 0.25, 0.6, 0.25, "wood", "Handle")
	box(m, f, 1.5, 1.25, 0.45, 0.25, 0.3, 0.5, "steel", "Axe")
	box(m, f, 1.3, 0.05, -0.8, 1, 0.1, 0.8, "sand", "Chips")
end

B.sawmill = function(m, f)
	box(m, f, 0, 0.15, 0, 4, 0.3, 4, "wood_dark", "Floor")
	box(m, f, -1.2, 1.4, -1, 1.5, 2.2, 2, "wood", "Shed")
	roof(m, f * CFrame.new(-1.2, 0, -1), 2.5, 1.75, 2.25, 0.8, "wood_dark")
	box(m, f, 0.8, 0.9, 0.8, 2.2, 0.25, 1.2, "wood", "Bench")
	Blocks.part(m, { size = Vector3.new(0.25, 1.4, 1.4), cf = f * CFrame.new(0.8, 1.3, 0.8), color = "steel", shape = "Cylinder", name = "Blade", collide = false })
	Blocks.part(m, { size = Vector3.new(3, 0.75, 0.75), cf = f * CFrame.new(0.4, 0.75, 1.6), color = "wood", shape = "Cylinder", name = "Log", collide = false })
end

------------------------------------------------------------------ shops
local function awning(m: Model, f: CFrame, y: number, w: number, z: number)
	local n = math.max(2, math.floor(w / 0.5))
	for i = 0, n - 1 do
		box(m, f, -w / 2 + (i + 0.5) * w / n, y, z, w / n, 0.25, 1, if i % 2 == 0 then "berry_red" else "white", "Awning")
	end
end

B.stall = function(m, f)
	box(m, f, 0, 0.55, 0.25, 2.75, 1.1, 1, "wood", "Counter")
	box(m, f, 0, 1.15, 0.25, 2.9, 0.15, 1.15, "wood_dark", "Top")
	for _, x in { -1.3, 1.3 } do
		box(m, f, x, 1.3, -0.65, 0.25, 2.6, 0.25, "wood_dark", "Post")
	end
	awning(m, f, 2.6, 3, -0.2)
	ball(m, f, -0.7, 1.4, 0.3, 0.4, "orange", "Fruit")
	ball(m, f, -0.2, 1.4, 0.4, 0.4, "berry_red", "Fruit")
	box(m, f, 0.6, 1.35, 0.3, 0.6, 0.25, 0.4, "blue", "Fish")
end

B.cafe = function(m, f)
	box(m, f, 0, 1.25, -0.6, 4, 2.5, 1.8, "cream", "Walls")
	roof(m, f * CFrame.new(0, 0, -0.6), 2.5, 4.25, 2.1, 0.9, "orange")
	box(m, f, -1, 1.4, 0.32, 1, 0.8, 0.1, "window", "Window")
	box(m, f, 0.9, 0.85, 0.32, 0.9, 1.7, 0.1, "wood_dark", "Door")
	awning(m, f, 2.25, 4, 0.7)
	cyl(m, f, -0.9, 0.6, 1.1, 0.9, 0.15, "white", "Table")
	box(m, f, -0.9, 0.3, 1.1, 0.25, 0.6, 0.25, "steel_dark", "Leg")
end

B.inn = function(m, f)
	box(m, f, 0, 1.6, -0.4, 5, 3.2, 3, "wall", "Walls")
	box(m, f, 0, 3.25, -0.4, 5.25, 0.25, 3.25, "wood_dark", "Floor2")
	box(m, f, 0, 4.1, -0.6, 4.4, 1.5, 2.4, "wall", "Upper")
	roof(m, f * CFrame.new(0, 0, -0.6), 4.85, 4.75, 2.75, 1.1, "berry_red")
	for _, x in { -1.6, 0, 1.6 } do
		box(m, f, x, 4.1, 0.62, 0.8, 0.7, 0.1, "window", "Window")
	end
	box(m, f, -1.5, 1.8, 1.12, 1, 0.8, 0.1, "window", "Window")
	box(m, f, 1, 1, 1.12, 1, 2, 0.1, "wood_dark", "Door")
	box(m, f, 1, 2.6, 1.4, 1.6, 0.6, 0.15, "wood", "Sign")
	box(m, f, 1, 2.6, 1.5, 1.2, 0.3, 0.1, "gold", "Letters")
end

------------------------------------------------------------------ homes and nests
B.tent = function(m, f)
	wedge(m, f, 0, 0.75, -0.45, 1.8, 1.5, 0.9, "orange", 0, "Canvas")
	wedge(m, f, 0, 0.75, 0.45, 1.8, 1.5, 0.9, "orange", math.pi, "Canvas")
	box(m, f, 0, 0.45, 0.93, 0.6, 0.9, 0.05, "wood_dark", "Opening")
	box(m, f, 0, 1.6, 0, 0.25, 0.25, 0.25, "wood_dark", "Pole")
end

B.hut = function(m, f)
	box(m, f, 0, 0.9, 0, 2.6, 1.8, 2.6, "wood", "Walls")
	roof(m, f, 1.8, 3, 3, 1.4, "sand_dark")
	box(m, f, 0, 0.7, 1.32, 0.8, 1.4, 0.1, "wood_dark", "Door")
	box(m, f, -0.9, 1.1, 1.32, 0.5, 0.5, 0.1, "window", "Window")
end

B.cottage = function(m, f)
	box(m, f, 0, 1.1, 0, 3.6, 2.2, 2.6, "wall", "Walls")
	roof(m, f, 2.2, 4, 3, 1.4, "berry_red")
	box(m, f, 1.1, 3.1, -0.5, 0.5, 1.2, 0.5, "steel_dark", "Chimney")
	box(m, f, 0.6, 0.8, 1.32, 0.8, 1.6, 0.1, "wood_dark", "Door")
	box(m, f, -0.9, 1.3, 1.32, 0.8, 0.7, 0.1, "window", "Window")
	box(m, f, -1.85, 1.3, 0, 0.1, 0.7, 0.8, "window", "Window")
	box(m, f, -0.9, 0.85, 1.4, 0.9, 0.2, 0.25, "pink", "Flowers")
end

B.nest = function(m, f)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		box(m, f, math.cos(a) * 0.7, 0.2, math.sin(a) * 0.7, 0.6, 0.4, 0.6, if i % 2 == 0 then "sand_dark" else "wood", "Straw")
	end
	box(m, f, 0, 0.1, 0, 1.2, 0.2, 1.2, "sand", "Bed")
	ball(m, f, 0, 0.45, 0, 0.6, "cream", "Egg")
	box(m, f, 0.1, 0.55, 0.25, 0.15, 0.15, 0.1, "blue", "Spot")
end

B.burrow = function(m, f)
	ball(m, f, 0, 0.3, -0.2, 2.6, "grass_dark", "Mound")
	box(m, f, 0, 0.5, 1.0, 1.1, 0.8, 0.2, "black", "Hole")
	box(m, f, 0, 1.0, 1.05, 1.3, 0.25, 0.3, "wood", "Lintel")
	for _, x in { -1.3, 1.3 } do
		box(m, f, x, 0.45, 1.2, 0.25, 0.9, 0.25, "wood_dark", "Post")
	end
	ball(m, f, 0.9, 1.4, -0.5, 0.6, "leaf", "Bush")
end

B.yard = function(m, f)
	box(m, f, 0, 0.08, 0, 4, 0.16, 4, "sand", "Ground")
	for _, s in { -1.8, 1.8 } do
		box(m, f, s, 0.45, 0, 0.25, 0.25, 3.6, "wood", "Rail")
		box(m, f, 0, 0.45, s, 3.6, 0.25, 0.25, "wood", "Rail")
	end
	box(m, f, 0, 0.9, 0, 0.25, 1.8, 0.25, "wood_dark", "Post")
	box(m, f, 0, 1.4, 0, 0.8, 0.8, 0.5, "sand_dark", "Dummy")
	box(m, f, 0, 2.0, 0, 0.5, 0.5, 0.5, "sand_dark", "Head")
	box(m, f, 0.65, 1.5, 0, 0.5, 0.25, 0.25, "sand_dark", "Arm")
end

------------------------------------------------------------------ decor
B.torch = function(m, f)
	box(m, f, 0, 0.9, 0, 0.25, 1.8, 0.25, "wood_dark", "Pole")
	box(m, f, 0, 1.9, 0, 0.5, 0.3, 0.5, "wood", "Cup")
	box(m, f, 0, 2.2, 0, 0.4, 0.4, 0.4, "orange", "Flame", true)
	box(m, f, 0, 2.45, 0, 0.25, 0.25, 0.25, "yellow", "Tip", true)
end

B.shellpile = function(m, f)
	ball(m, f, -0.4, 0.25, -0.2, 0.6, "pink", "Shell")
	ball(m, f, 0.3, 0.25, 0.1, 0.6, "cream", "Shell")
	ball(m, f, 0, 0.55, -0.05, 0.5, "sand", "Shell")
	ball(m, f, -0.1, 0.2, 0.55, 0.45, "orange", "Shell")
	box(m, f, 0.6, 0.12, -0.6, 0.4, 0.25, 0.4, "white", "Shell")
end

B.palm = function(m, f)
	for i = 0, 3 do
		box(m, f, i * 0.2, 0.6 + i * 1.1, 0, 0.75, 1.2, 0.75, if i % 2 == 0 then "wood" else "wood_dark", "Trunk")
	end
	local top = 4.8
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		box(m, f, 0.8 + d[1] * 1.3, top - 0.2, d[2] * 1.3, if d[1] ~= 0 then 2.4 else 1, 0.4, if d[2] ~= 0 then 2.4 else 1, if k % 2 == 0 then "leaf" else "leaf_dark", "Frond")
	end
	ball(m, f, 0.8, top - 0.6, 0.3, 0.6, "wood_dark", "Coconut")
end

B.hammock = function(m, f)
	for _, x in { -1.8, 1.8 } do
		box(m, f, x, 1, 0, 0.3, 2, 0.3, "wood_dark", "Post")
	end
	box(m, f, -1.1, 1.0, 0, 1.2, 0.2, 1, "sand", "Cloth")
	box(m, f, 1.1, 1.0, 0, 1.2, 0.2, 1, "sand", "Cloth")
	box(m, f, 0, 0.75, 0, 1.2, 0.2, 1, "berry_red", "Cloth")
	box(m, f, -0.2, 0.95, 0, 0.6, 0.3, 0.6, "white", "Pillow")
end

B.totem = function(m, f)
	local cols = { "berry_red", "yellow", "blue", "green" }
	for i = 0, 3 do
		box(m, f, 0, 0.5 + i, 0, 1.4, 1, 1.4, cols[i + 1], "Block")
		box(m, f, -0.3, 0.6 + i, 0.72, 0.25, 0.25, 0.05, "black", "Eye")
		box(m, f, 0.3, 0.6 + i, 0.72, 0.25, 0.25, 0.05, "black", "Eye")
		box(m, f, 0, 0.3 + i, 0.72, 0.6, 0.15, 0.05, "white", "Mouth")
	end
	box(m, f, 0, 4.15, 0, 2, 0.3, 0.5, "orange", "Wings")
end

B.lighthouse = function(m, f)
	box(m, f, 0, 0.3, 0, 4, 0.6, 4, "steel", "Base")
	for i = 0, 4 do
		box(m, f, 0, 1.1 + i * 1.2, 0, 2.6 - i * 0.2, 1.2, 2.6 - i * 0.2, if i % 2 == 0 then "white" else "berry_red", "Tower")
	end
	box(m, f, 0, 7.2, 0, 1.6, 1, 1.6, "yellow", "Lamp", true)
	box(m, f, 0, 7.9, 0, 2, 0.4, 2, "berry_red", "Cap")
	box(m, f, 0, 0.9, 1.31, 0.8, 1.2, 0.05, "wood_dark", "Door")
end

-- An upgraded building's pennant: a pole at its back-left corner, the flag red at level 2, gold at 3.
local function pennant(m: Model, f: CFrame, lvl: number, w: number, d: number)
	local x, z = -w / 2 + 0.3, -d / 2 + 0.3
	box(m, f, x, 1.6, z, 0.2, 3.2, 0.2, "wood_dark", "Pennant")
	box(m, f, x + 0.45, 2.9, z, 0.7, 0.45, 0.1, if lvl >= 3 then "gold" else "berry_red", "Flag")
	if lvl >= 3 then
		box(m, f, x + 0.35, 2.3, z, 0.5, 0.35, 0.1, "gold", "Flag")
	end
end

function DecorModels.build(id: string, at: CFrame, lvl: number?): Model
	local m = Blocks.model(nil, "Decor_" .. id)
	m:SetAttribute("Decor", id)
	local fn = B[id]
	if fn then
		fn(m, at)
	end
	local l = lvl or 1
	if l >= 2 then
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
