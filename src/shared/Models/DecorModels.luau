--!strict
-- The island's buildings and decor from parts (GAME_DESIGN 4; Data/Buildings). Roblox module (server: PlotService
-- builds the placed pieces; client: Build mode's ghost). `build(id, at, lvl?)`: a model standing on `at` (the
-- footprint's centre on the grass, already turned by the piece's rot), facing +Z before the turn, within its
-- footprint (Data/Buildings' w x d). Each is detailed in the pixel filter's scale: a footing on the grass, framed
-- windows and doors, roofs with eaves and a ridge, and the small things of its trade (crates, barrels, sacks, tools,
-- pots). An upgraded building (lvl 2, 3) flies a pennant (a gold one at 3) and gains a lantern by its door (lvl 3).
-- Pieces do not collide (the founder walks through them, never stuck behind one).
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
-- A cylinder lying along X.
local function log(m: Instance, f: CFrame, x: number, y: number, z: number, len: number, dia: number, color: string, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(len, dia, dia), cf = f * CFrame.new(x, y, z), color = color, shape = "Cylinder", name = name or "Log", collide = false })
end

-- A wedge (its sloped face toward -Z, full height at +Z before `turn`).
local function wedge(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, turn: number?, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, turn or 0, 0), color = color, shape = "Wedge", name = name, collide = false })
end

-- A gable roof along X over a w x d box whose top is at y (eaves `over` past the walls): two wedges meeting at the
-- ridge, a darker ridge beam, a trim along the eaves.
local function roof(m: Instance, f: CFrame, y: number, w: number, d: number, h: number, color: string, trim: string?, over: number?)
	local o = over or 0.25
	local W, D = w + o * 2, d + o * 2
	wedge(m, f, 0, y + h / 2, -D / 4, W, h, D / 2, color, 0, "Roof")
	wedge(m, f, 0, y + h / 2, D / 4, W, h, D / 2, color, math.pi, "Roof")
	box(m, f, 0, y + h + 0.06, 0, W + 0.1, 0.12, 0.3, trim or "wood_dark", "Ridge")
	box(m, f, 0, y - 0.05, -D / 2 + 0.06, W, 0.1, 0.12, trim or "wood_dark", "Eave")
	box(m, f, 0, y - 0.05, D / 2 - 0.06, W, 0.1, 0.12, trim or "wood_dark", "Eave")
end

-- A window on the front (+Z) face at z: a frame, the glass, a cross of bars, a sill.
local function window(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, frame: string?)
	local fr = frame or "wood_dark"
	box(m, f, x, y, z + 0.03, w + 0.2, h + 0.2, 0.1, fr, "WindowFrame")
	box(m, f, x, y, z + 0.09, w, h, 0.05, "window", "Glass")
	box(m, f, x, y, z + 0.12, 0.08, h, 0.05, fr, "Bar")
	box(m, f, x, y, z + 0.12, w, 0.08, 0.05, fr, "Bar")
	box(m, f, x, y - h / 2 - 0.1, z + 0.12, w + 0.3, 0.1, 0.2, fr, "Sill")
end

-- A window on a side (+X) face at x.
local function sideWindow(m: Instance, f: CFrame, x: number, y: number, z: number, d: number, h: number)
	box(m, f, x + 0.03, y, z, 0.1, h + 0.2, d + 0.2, "wood_dark", "WindowFrame")
	box(m, f, x + 0.09, y, z, 0.05, h, d, "window", "Glass")
	box(m, f, x + 0.12, y, z, 0.05, h, 0.08, "wood_dark", "Bar")
end

-- A door on the front face: a frame, the planks, a knob, a step.
local function door(m: Instance, f: CFrame, x: number, z: number, w: number, h: number, color: string?)
	box(m, f, x, h / 2 + 0.05, z + 0.03, w + 0.2, h + 0.1, 0.1, "wood_dark", "DoorFrame")
	box(m, f, x, h / 2, z + 0.08, w, h - 0.05, 0.05, color or "wood", "Door")
	box(m, f, x + w / 2 - 0.15, h / 2, z + 0.13, 0.1, 0.1, 0.05, "gold", "Knob")
	box(m, f, x, 0.06, z + 0.3, w + 0.25, 0.12, 0.45, "rock", "Step")
end

local function crate(m: Instance, f: CFrame, x: number, y: number, z: number, s: number)
	box(m, f, x, y + s / 2, z, s, s, s, "wood", "Crate")
	box(m, f, x, y + s / 2, z, s + 0.04, 0.12, s + 0.04, "wood_dark", "Strap")
	box(m, f, x, y + s / 2, z, 0.12, s + 0.04, s + 0.04, "wood_dark", "Strap")
end

local function barrel(m: Instance, f: CFrame, x: number, y: number, z: number, s: number?)
	local k = s or 1
	cyl(m, f, x, y + 0.5 * k, z, 0.8 * k, 1.0 * k, "wood", "Barrel")
	cyl(m, f, x, y + 0.2 * k, z, 0.86 * k, 0.1, "steel_dark", "Hoop")
	cyl(m, f, x, y + 0.8 * k, z, 0.86 * k, 0.1, "steel_dark", "Hoop")
	cyl(m, f, x, y + 1.02 * k, z, 0.7 * k, 0.05, "wood_dark", "Lid")
end

local function sack(m: Instance, f: CFrame, x: number, y: number, z: number, color: string?)
	box(m, f, x, y + 0.3, z, 0.6, 0.6, 0.5, color or "sand_dark", "Sack")
	box(m, f, x, y + 0.65, z, 0.3, 0.15, 0.3, color or "sand_dark", "Tie")
end

local function pot(m: Instance, f: CFrame, x: number, y: number, z: number, bloom: string?)
	box(m, f, x, y + 0.2, z, 0.5, 0.4, 0.5, "pot", "Pot")
	ball(m, f, x, y + 0.55, z, 0.55, "leaf", "Plant")
	if bloom then
		box(m, f, x + 0.1, y + 0.8, z, 0.2, 0.2, 0.2, bloom, "Bloom")
	end
end

-- A footing on the grass under a building (a little proud of it): stone or planks.
local function footing(m: Instance, f: CFrame, w: number, d: number, color: string, h: number?)
	box(m, f, 0, (h or 0.15) / 2, 0, w, h or 0.15, d, color, "Footing")
end

-- A short fence along X at z from x0 to x1: posts every stud, two rails.
local function fence(m: Instance, f: CFrame, x0: number, x1: number, z: number, color: string?)
	local c = color or "wood"
	local x = x0
	while x <= x1 + 0.01 do
		box(m, f, x, 0.4, z, 0.2, 0.8, 0.2, "wood_dark", "FencePost")
		x += 1
	end
	box(m, f, (x0 + x1) / 2, 0.55, z, x1 - x0, 0.1, 0.1, c, "Rail")
	box(m, f, (x0 + x1) / 2, 0.3, z, x1 - x0, 0.1, 0.1, c, "Rail")
end

-- The same along Z at x.
local function fenceZ(m: Instance, f: CFrame, z0: number, z1: number, x: number, color: string?)
	local c = color or "wood"
	local z = z0
	while z <= z1 + 0.01 do
		box(m, f, x, 0.4, z, 0.2, 0.8, 0.2, "wood_dark", "FencePost")
		z += 1
	end
	box(m, f, x, 0.55, (z0 + z1) / 2, 0.1, 0.1, z1 - z0, c, "Rail")
	box(m, f, x, 0.3, (z0 + z1) / 2, 0.1, 0.1, z1 - z0, c, "Rail")
end

local function lamp(m: Instance, f: CFrame, x: number, z: number)
	box(m, f, x, 0.9, z, 0.15, 1.8, 0.15, "wood_dark", "LampPost")
	box(m, f, x, 1.95, z, 0.4, 0.4, 0.4, "yellow", "LampLight", true)
	box(m, f, x, 2.2, z, 0.5, 0.1, 0.5, "wood_dark", "LampCap")
end

local B: { [string]: Builder } = {}

------------------------------------------------------------------ food
-- Veggie Patch (3 x 3): a raised bed of soil in rows, carrots, cabbages and sprouts, a watering can, a scarecrow.
B.patch = function(m, f)
	box(m, f, 0, 0.15, 0, 3, 0.3, 3, "wood_dark", "Bed")
	box(m, f, 0, 0.32, 0, 2.7, 0.08, 2.7, "pot", "Soil")
	for r = 0, 2 do
		local z = -0.9 + r * 0.9
		box(m, f, 0, 0.4, z, 2.5, 0.1, 0.45, "wood_dark", "Row")
		for c = 0, 3 do
			local x = -0.95 + c * 0.63
			if r == 0 then
				box(m, f, x, 0.5, z, 0.25, 0.15, 0.25, "orange", "Carrot")
				box(m, f, x, 0.7, z, 0.12, 0.3, 0.12, "leaf", "Top")
				box(m, f, x + 0.1, 0.7, z, 0.12, 0.25, 0.12, "leaf_dark", "Top")
			elseif r == 1 then
				ball(m, f, x, 0.6, z, 0.45, if c % 2 == 0 then "leaf" else "green", "Cabbage")
			else
				box(m, f, x, 0.55, z, 0.12, 0.3, 0.12, "leaf", "Sprout")
				box(m, f, x + 0.12, 0.65, z, 0.25, 0.1, 0.12, "leaf_dark", "Leaf")
			end
		end
	end
	-- the scarecrow at the back corner
	box(m, f, 1.15, 1.0, -1.15, 0.15, 1.6, 0.15, "wood_dark", "Post")
	box(m, f, 1.15, 1.35, -1.15, 1.1, 0.12, 0.12, "wood_dark", "Arms")
	box(m, f, 1.15, 1.25, -1.15, 0.5, 0.55, 0.3, "berry_red", "Shirt")
	box(m, f, 1.15, 1.75, -1.15, 0.4, 0.4, 0.35, "sand", "Head")
	box(m, f, 1.15, 2.0, -1.15, 0.7, 0.1, 0.6, "yellow", "HatBrim")
	box(m, f, 1.15, 2.15, -1.15, 0.35, 0.25, 0.35, "yellow", "Hat")
	cyl(m, f, -1.15, 0.55, 1.2, 0.4, 0.45, "blue", "WateringCan")
	box(m, f, -0.9, 0.65, 1.2, 0.3, 0.1, 0.1, "blue", "Spout")
end

-- Fishing Pier (3 x 3): a little fishing shack on stilts over a pond, nets, a drying rack of fish, a bucket.
B.pier = function(m, f)
	box(m, f, 0.6, 0.06, 0.6, 1.8, 0.12, 1.8, "sand_dark", "Bank")
	box(m, f, 0.6, 0.1, 0.6, 1.5, 0.1, 1.5, "water", "Pond"):SetAttribute("PixelWater", 2)
	for _, x in { -1.3, 0.1 } do
		for _, z in { -1.3, -0.1 } do
			box(m, f, x, 0.35, z, 0.2, 0.7, 0.2, "wood_dark", "Stilt")
		end
	end
	box(m, f, -0.6, 0.75, -0.6, 1.7, 0.15, 1.7, "wood", "Deck")
	box(m, f, -0.6, 1.4, -0.75, 1.4, 1.15, 1.2, "wood", "Shack")
	door(m, f * CFrame.new(-0.85, 0.82, 0), 0, -0.15, 0.45, 0.85, "wood_dark")
	window(m, f * CFrame.new(0, 0.82, 0), -0.25, 0.75, -0.15, 0.35, 0.35)
	roof(m, f * CFrame.new(-0.6, 0, -0.75), 1.98, 1.4, 1.2, 0.55, "berry_red", "white")
	-- a rod leaning out over the pond, its line, the drying rack
	Blocks.part(m, { size = Vector3.new(0.1, 2.2, 0.1), cf = f * CFrame.new(0.5, 1.6, 0.2) * CFrame.Angles(math.rad(-35), 0, math.rad(-20)), color = "wood_dark", name = "Rod", collide = false })
	box(m, f, 1.0, 0.8, 0.95, 0.05, 1.1, 0.05, "white", "Line")
	for _, x in { -1.35, 0.15 } do
		box(m, f, x, 0.6, 1.25, 0.12, 1.2, 0.12, "wood_dark", "RackPost")
	end
	box(m, f, -0.6, 1.15, 1.25, 1.6, 0.08, 0.08, "wood_dark", "RackBar")
	for k = 0, 2 do
		box(m, f, -1.05 + k * 0.45, 0.95, 1.25, 0.2, 0.4, 0.08, if k == 1 then "steel" else "blue", "Fish")
	end
	box(m, f, 1.25, 0.12, -1.2, 0.5, 0.25, 0.5, "steel_dark", "Bucket")
	box(m, f, 1.25, 0.28, -1.2, 0.3, 0.1, 0.12, "blue", "Catch")
end

local function fruitTree(m: Model, f: CFrame, x: number, z: number, fruit: string)
	box(m, f, x, 0.55, z, 0.4, 1.1, 0.4, "wood_dark", "Trunk")
	box(m, f, x + 0.2, 1.05, z, 0.5, 0.15, 0.15, "wood_dark", "Branch")
	ball(m, f, x, 1.75, z, 1.5, "leaf", "Crown")
	ball(m, f, x + 0.35, 1.5, z + 0.35, 0.9, "leaf_dark", "Crown")
	ball(m, f, x - 0.3, 2.15, z - 0.2, 0.8, "leaf", "Crown")
	ball(m, f, x + 0.55, 1.35, z + 0.55, 0.35, fruit, "Fruit")
	ball(m, f, x - 0.55, 1.85, z + 0.35, 0.35, fruit, "Fruit")
	ball(m, f, x + 0.2, 2.2, z + 0.5, 0.35, fruit, "Fruit")
end

-- Fruit Orchard (4 x 4): four fruit trees on a fenced lawn, a ladder, baskets of fruit.
B.orchard = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 4, "grass_dark", "Ground")
	fruitTree(m, f, -1, -1, "berry_red")
	fruitTree(m, f, 1, -1, "orange")
	fruitTree(m, f, -1, 1, "yellow")
	fruitTree(m, f, 1, 1, "berry_red")
	fence(m, f, -1.9, 1.9, -1.9)
	fenceZ(m, f, -1.9, 1.9, -1.9)
	Blocks.part(m, { size = Vector3.new(0.6, 2, 0.12), cf = f * CFrame.new(0.4, 1.0, 0.3) * CFrame.Angles(math.rad(15), 0, 0), color = "wood", name = "Ladder", collide = false })
	box(m, f, 1.8, 0.25, 0, 0.6, 0.5, 0.6, "wood", "Basket")
	ball(m, f, 1.75, 0.55, 0, 0.3, "berry_red", "Fruit")
	ball(m, f, 1.9, 0.55, 0.1, 0.3, "orange", "Fruit")
	box(m, f, 0, 0.25, 1.85, 0.6, 0.5, 0.6, "wood", "Basket")
	ball(m, f, 0, 0.55, 1.85, 0.3, "yellow", "Fruit")
end

-- Greenhouse (4 x 3): a frame of white beams round glass panes on a stone base, tables of potted plants inside, a
-- water butt.
B.greenhouse = function(m, f)
	footing(m, f, 4, 3, "rock", 0.3)
	-- the glass box: the back and left glass, the front glass lower so the plants show
	box(m, f, 0, 1.25, -1.4, 3.8, 1.9, 0.1, "window", "Glass")
	box(m, f, -1.85, 1.25, 0, 0.1, 1.9, 2.8, "window", "Glass")
	box(m, f, 1.85, 1.25, 0, 0.1, 1.9, 2.8, "window", "Glass")
	box(m, f, 0, 0.6, 1.4, 3.8, 0.6, 0.1, "window", "Glass")
	for _, x in { -1.9, -0.95, 0, 0.95, 1.9 } do
		box(m, f, x, 1.25, -1.45, 0.12, 1.95, 0.12, "white", "Beam")
		box(m, f, x, 0.6, 1.45, 0.12, 0.65, 0.12, "white", "Beam")
	end
	for _, z in { -1.45, 0, 1.45 } do
		box(m, f, -1.9, 1.25, z, 0.12, 1.95, 0.12, "white", "Beam")
		box(m, f, 1.9, 1.25, z, 0.12, 1.95, 0.12, "white", "Beam")
	end
	box(m, f, 0, 2.2, -1.45, 3.9, 0.12, 0.12, "white", "Beam")
	roof(m, f, 2.2, 3.8, 2.9, 0.9, "window", "white", 0.1)
	-- two tables of pots
	for _, z in { -0.6, 0.6 } do
		box(m, f, 0, 0.75, z, 3.2, 0.12, 0.6, "wood", "Table")
		for k = 0, 3 do
			pot(m, f, -1.2 + k * 0.8, 0.81, z, if k % 2 == 0 then "pink" else nil)
		end
	end
	barrel(m, f, 1.6, 0.3, 1.75 - 0.4, 0.7)
end

------------------------------------------------------------------ wood
-- Lumber Camp (4 x 3): a stack of logs, a chopping block with an axe and split wood, a saw horse, wood chips, a
-- tool rack.
B.lumber = function(m, f)
	box(m, f, 0.2, 0.03, 0.4, 1.6, 0.06, 1.2, "sand_dark", "Chips")
	-- the log pile between two stakes
	for k, y in { 0.38, 0.38, 0.38, 1.0, 1.0, 1.6 } do
		local z = if k <= 3 then -1.1 + (k - 1) * 0.6 elseif k <= 5 then -0.8 + (k - 4) * 0.6 else -0.5
		log(m, f, -0.7, y, z, 2.2, 0.65, if k % 2 == 0 then "wood_dark" else "wood", "Log")
		cyl(m, f, 0.42, y, z, 0.5, 0.05, "sand", "Ring").CFrame = f * CFrame.new(0.43, y, z) * CFrame.Angles(0, 0, math.pi / 2)
	end
	for _, x in { -1.9, 0.5 } do
		box(m, f, x, 1.0, -1.4, 0.15, 2.0, 0.15, "wood_dark", "Stake")
	end
	-- the chopping block, its axe and a split log
	cyl(m, f, 1.3, 0.35, 0.6, 0.9, 0.7, "wood_dark", "Block")
	cyl(m, f, 1.3, 0.71, 0.6, 0.75, 0.05, "sand", "Top")
	Blocks.part(m, { size = Vector3.new(0.12, 0.9, 0.12), cf = f * CFrame.new(1.3, 1.1, 0.5) * CFrame.Angles(math.rad(25), 0, 0), color = "wood", name = "Handle", collide = false })
	box(m, f, 1.3, 0.85, 0.75, 0.1, 0.35, 0.4, "steel", "Axe")
	box(m, f, 0.65, 0.15, 1.15, 0.6, 0.3, 0.25, "wood", "Split")
	box(m, f, 0.9, 0.15, 1.3, 0.25, 0.3, 0.5, "wood", "Split")
	-- the saw horse
	for _, x in { 0.6, 1.5 } do
		box(m, f, x, 0.4, -0.6, 0.12, 0.8, 0.6, "wood_dark", "Leg")
	end
	box(m, f, 1.05, 0.8, -0.6, 1.2, 0.15, 0.15, "wood", "Bar")
	box(m, f, 1.05, 0.95, -0.6, 0.9, 0.12, 0.05, "steel", "Saw")
end

-- Sawmill (4 x 4): a shed with a water-wheel-turned blade, planks stacked, logs waiting, a cart.
B.sawmill = function(m, f)
	footing(m, f, 4, 4, "wood_dark", 0.2)
	box(m, f, -1.0, 1.25, -1.0, 1.8, 2.1, 1.8, "wood", "Shed")
	for k = 0, 3 do
		box(m, f, -1.0, 0.4 + k * 0.5, -0.08, 1.85, 0.05, 0.05, "wood_dark", "Board")
	end
	door(m, f * CFrame.new(0, 0.2, 0), -0.6, -0.1, 0.6, 1.2, "wood_dark")
	window(m, f * CFrame.new(0, 0.2, 0), -1.4, 1.35, -0.1, 0.4, 0.4)
	roof(m, f * CFrame.new(-1.0, 0, -1.0), 2.3, 1.8, 1.8, 0.8, "wood_dark", "black")
	box(m, f, -0.5, 3.0, -1.4, 0.3, 0.9, 0.3, "rock_dark", "Chimney")
	-- the bench and its round blade
	box(m, f, 0.9, 0.75, 0.6, 2.2, 0.15, 1.0, "wood", "Bench")
	for _, x in { -0.05, 1.85 } do
		for _, z in { 0.2, 1.0 } do
			box(m, f, x, 0.45, z, 0.15, 0.6, 0.15, "wood_dark", "Leg")
		end
	end
	Blocks.part(m, { size = Vector3.new(0.08, 1.2, 1.2), cf = f * CFrame.new(0.9, 1.05, 0.6) * CFrame.Angles(0, math.pi / 2, 0), color = "steel", shape = "Cylinder", name = "Blade", collide = false })
	log(m, f, 0.5, 0.95, 0.6, 1.4, 0.4, "wood", "Log")
	-- planks stacked, logs waiting
	for k = 0, 3 do
		box(m, f, 1.2, 0.3 + k * 0.15, -1.2, 1.4, 0.12, 0.8, if k % 2 == 0 then "wood" else "desk", "Plank")
	end
	log(m, f, -0.6, 0.55, 1.5, 2.2, 0.6, "wood_dark")
	crate(m, f, 1.55, 0.2, 1.55, 0.7)
	log(m, f, -0.6, 0.55, 0.85, 2.2, 0.6, "wood")
end

------------------------------------------------------------------ shops
local function awning(m: Model, f: CFrame, y: number, w: number, z: number, a: string?, b: string?)
	local n = math.max(2, math.floor(w / 0.5))
	for i = 0, n - 1 do
		local x = -w / 2 + (i + 0.5) * w / n
		Blocks.part(m, { size = Vector3.new(w / n, 0.12, 1.1), cf = f * CFrame.new(x, y, z) * CFrame.Angles(math.rad(-14), 0, 0), color = if i % 2 == 0 then a or "berry_red" else b or "white", name = "Awning", collide = false })
		box(m, f, x, y - 0.32, z + 0.53, w / n, 0.2, 0.06, if i % 2 == 0 then a or "berry_red" else b or "white", "Flap")
	end
end

-- Snack Stall (3 x 2): a counter with fruit, fish and drinks under a striped awning, a sign, stools.
B.stall = function(m, f)
	box(m, f, 0, 0.55, 0.2, 2.6, 1.1, 0.9, "wood", "Counter")
	for k = 0, 3 do
		box(m, f, -1.0 + k * 0.66, 0.55, 0.66, 0.06, 1.0, 0.05, "wood_dark", "Board")
	end
	box(m, f, 0, 1.15, 0.2, 2.8, 0.12, 1.05, "wood_dark", "Top")
	for _, x in { -1.3, 1.3 } do
		box(m, f, x, 1.4, -0.6, 0.18, 2.8, 0.18, "wood_dark", "Post")
		box(m, f, x, 1.4, 0.65, 0.18, 2.8, 0.18, "wood_dark", "Post")
	end
	awning(m, f, 2.75, 2.9, 0.05)
	-- the goods
	ball(m, f, -0.95, 1.38, 0.3, 0.35, "orange", "Fruit")
	ball(m, f, -0.65, 1.38, 0.4, 0.35, "berry_red", "Fruit")
	ball(m, f, -0.8, 1.6, 0.35, 0.35, "yellow", "Fruit")
	box(m, f, 0.1, 1.3, 0.35, 0.6, 0.2, 0.3, "blue", "Fish")
	box(m, f, 0.45, 1.33, 0.3, 0.12, 0.12, 0.2, "blue", "Tail")
	for k = 0, 2 do
		cyl(m, f, 0.75 + k * 0.22, 1.36, 0.45, 0.18, 0.3, if k == 1 then "pink" else "yellow", "Drink")
	end
	sack(m, f, 1.2, 0, -0.75, "sand")
	-- the sign on top and two stools
	box(m, f, 0, 3.25, 0.1, 1.6, 0.5, 0.12, "cream", "Sign")
	box(m, f, 0, 3.25, 0.17, 1.2, 0.2, 0.05, "berry_red", "Letters")
	for _, x in { -0.7, 0.7 } do
		cyl(m, f, x, 0.45, 0.95, 0.45, 0.1, "berry_red", "Stool")
		box(m, f, x, 0.2, 0.95, 0.1, 0.4, 0.1, "steel_dark", "Leg")
	end
end

-- Beach Cafe (4 x 3): a little cream building with a tiled roof, a door, windows with flower boxes, an awning over
-- the terrace with a table and parasol.
B.cafe = function(m, f)
	footing(m, f, 4, 3, "pavement", 0.12)
	box(m, f, 0, 1.3, -0.65, 3.8, 2.4, 1.6, "cream", "Walls")
	box(m, f, 0, 0.2, -0.65, 3.85, 0.3, 1.65, "wall_trim", "Skirting")
	door(m, f * CFrame.new(0, 0.12, 0), 1.0, 0.15, 0.7, 1.5, "berry_red")
	window(m, f * CFrame.new(0, 0.12, 0), -0.8, 1.35, 0.15, 1.3, 0.75)
	box(m, f, -0.8, 0.82, 0.3, 1.3, 0.2, 0.25, "wood", "FlowerBox")
	for k = 0, 3 do
		box(m, f, -1.25 + k * 0.3, 0.98, 0.3, 0.15, 0.15, 0.15, if k % 2 == 0 then "pink" else "yellow", "Bloom")
	end
	sideWindow(m, f * CFrame.new(0, 0.12, 0), 1.9, 1.35, -0.65, 0.8, 0.6)
	roof(m, f * CFrame.new(0, 0, -0.65), 2.5, 3.8, 1.6, 0.9, "orange", "wood_dark", 0.3)
	box(m, f, -1.2, 3.0, -1.1, 0.35, 0.7, 0.35, "rock", "Chimney")
	awning(m, f, 2.2, 3.8, 0.55, "blue", "white")
	-- the terrace: a table, two chairs, a parasol
	cyl(m, f, -0.6, 0.7, 1.05, 0.8, 0.1, "white", "Table")
	box(m, f, -0.6, 0.35, 1.05, 0.12, 0.7, 0.12, "steel_dark", "Leg")
	cyl(m, f, -0.6, 0.85, 1.05, 0.2, 0.2, "orange", "Cup")
	for _, x in { -1.25, 0.05 } do
		box(m, f, x, 0.4, 1.1, 0.4, 0.1, 0.4, "wood", "Chair")
		box(m, f, x, 0.65, 1.3, 0.4, 0.5, 0.08, "wood", "ChairBack")
	end
	box(m, f, 1.6, 0.45, 1.1, 0.12, 0.9, 0.12, "wood_dark", "MenuPost")
	box(m, f, 1.6, 0.85, 1.15, 0.5, 0.6, 0.08, "chalk", "Menu")
end

-- Seaside Inn (5 x 4): two storeys, a balcony, windows and shutters, a hanging sign, lanterns, a bench by the door.
B.inn = function(m, f)
	footing(m, f, 5, 4, "rock", 0.15)
	box(m, f, 0, 1.55, -0.45, 4.8, 2.8, 2.9, "wall", "Walls")
	box(m, f, 0, 0.3, -0.45, 4.85, 0.3, 2.95, "rock_dark", "Skirting")
	box(m, f, 0, 3.05, -0.45, 5.0, 0.2, 3.1, "wood_dark", "Floor2")
	box(m, f, 0, 3.95, -0.7, 4.4, 1.6, 2.3, "wall", "Upper")
	for _, x in { -2.15, 2.15 } do
		box(m, f, x, 3.95, -0.7, 0.12, 1.6, 2.35, "wood_dark", "Beam")
	end
	-- the ground floor: the door, two windows with shutters
	door(m, f * CFrame.new(0, 0.15, 0), 0.9, 1.0, 0.8, 1.7, "wood_dark")
	for _, x in { -1.6, -0.3 } do
		window(m, f * CFrame.new(0, 0.15, 0), x, 1.5, 1.0, 0.7, 0.7)
		box(m, f, x - 0.5, 1.5, 1.08, 0.25, 0.8, 0.06, "berry_red", "Shutter")
		box(m, f, x + 0.5, 1.5, 1.08, 0.25, 0.8, 0.06, "berry_red", "Shutter")
	end
	-- the upper floor's windows and a balcony
	for _, x in { -1.4, 0, 1.4 } do
		window(m, f, x, 4.0, 0.45, 0.6, 0.6)
	end
	box(m, f, 0, 3.15, 0.75, 4.4, 0.12, 0.6, "wood", "Balcony")
	for k = 0, 8 do
		box(m, f, -2.0 + k * 0.5, 3.45, 1.0, 0.08, 0.5, 0.08, "wood_dark", "Baluster")
	end
	box(m, f, 0, 3.7, 1.0, 4.3, 0.1, 0.1, "wood_dark", "Railing")
	roof(m, f * CFrame.new(0, 0, -0.7), 4.75, 4.4, 2.3, 1.1, "berry_red", "wood_dark", 0.3)
	box(m, f, 1.5, 5.7, -1.0, 0.4, 0.9, 0.4, "rock", "Chimney")
	-- the hanging sign, lanterns by the door, a bench
	box(m, f, 1.75, 2.55, 1.35, 0.8, 0.08, 0.08, "wood_dark", "SignArm")
	box(m, f, 1.95, 2.2, 1.4, 0.7, 0.5, 0.08, "wood", "Sign")
	box(m, f, 1.95, 2.2, 1.45, 0.5, 0.25, 0.04, "gold", "Letters")
	box(m, f, 0.3, 1.9, 1.15, 0.25, 0.35, 0.25, "yellow", "Lantern", true)
	box(m, f, 1.5, 1.9, 1.15, 0.25, 0.35, 0.25, "yellow", "Lantern", true)
	box(m, f, -1.0, 0.45, 1.6, 1.4, 0.12, 0.45, "wood", "Bench")
	box(m, f, -1.0, 0.2, 1.6, 1.2, 0.4, 0.1, "wood_dark", "BenchLeg")
	pot(m, f, -2.1, 0.12, 1.6, "pink")
	pot(m, f, 2.1, 0.12, 1.6, "yellow")
end

------------------------------------------------------------------ homes and nests
-- Tent (2 x 2): a canvas ridge tent with a seam, its flap open, poles and pegs, a bedroll inside, a lantern.
B.tent = function(m, f)
	box(m, f, 0, 0.03, 0, 1.9, 0.06, 1.9, "sand_dark", "Groundsheet")
	wedge(m, f, 0, 0.7, -0.45, 1.7, 1.4, 0.9, "orange", 0, "Canvas")
	wedge(m, f, 0, 0.7, 0.45, 1.7, 1.4, 0.9, "orange", math.pi, "Canvas")
	box(m, f, 0, 1.42, 0, 1.75, 0.08, 0.12, "berry_red", "Seam")
	box(m, f, 0, 0.45, 0.9, 0.6, 0.85, 0.05, "black", "Opening")
	Blocks.part(m, { size = Vector3.new(0.05, 0.9, 0.5), cf = f * CFrame.new(0.42, 0.45, 0.98) * CFrame.Angles(0, math.rad(-35), 0), color = "orange", name = "Flap", collide = false })
	for _, x in { -0.9, 0.9 } do
		box(m, f, x, 0.75, 0, 0.1, 1.5, 0.1, "wood_dark", "Pole")
		box(m, f, x * 1.05, 0.08, 0.9, 0.1, 0.16, 0.1, "wood_dark", "Peg")
		box(m, f, x * 1.05, 0.08, -0.9, 0.1, 0.16, 0.1, "wood_dark", "Peg")
	end
	box(m, f, 0, 0.15, 0.45, 0.5, 0.15, 0.6, "blue", "Bedroll")
	box(m, f, 0.85, 0.2, 0.85, 0.2, 0.3, 0.2, "yellow", "Lantern", true)
end

-- Grass Hut (3 x 3): plank walls on stilts, a thatched roof with fringes, a ladder, a round window, a pot plant.
B.hut = function(m, f)
	for _, x in { -1.2, 1.2 } do
		for _, z in { -1.2, 1.2 } do
			box(m, f, x, 0.3, z, 0.2, 0.6, 0.2, "wood_dark", "Stilt")
		end
	end
	box(m, f, 0, 0.62, 0, 2.8, 0.15, 2.8, "wood", "Floor")
	box(m, f, 0, 1.45, -0.15, 2.4, 1.5, 2.3, "wood", "Walls")
	for k = 0, 2 do
		box(m, f, 0, 0.9 + k * 0.5, 1.02, 2.4, 0.05, 0.05, "wood_dark", "Board")
	end
	door(m, f * CFrame.new(0, 0.7, 0), 0.4, 1.0, 0.6, 1.0, "wood_dark")
	box(m, f, -0.6, 1.5, 1.03, 0.5, 0.5, 0.06, "wood_dark", "WindowFrame")
	box(m, f, -0.6, 1.5, 1.07, 0.35, 0.35, 0.04, "window", "Glass")
	roof(m, f * CFrame.new(0, 0, -0.15), 2.2, 2.4, 2.3, 1.3, "sand_dark", "wood_dark", 0.4)
	for k = 0, 5 do
		box(m, f, -1.4 + k * 0.56, 2.05, 1.4, 0.3, 0.25, 0.1, "sand", "Fringe")
	end
	-- the ladder up to the door
	for _, x in { 0.1, 0.7 } do
		Blocks.part(m, { size = Vector3.new(0.1, 0.9, 0.1), cf = f * CFrame.new(x, 0.35, 1.35) * CFrame.Angles(math.rad(25), 0, 0), color = "wood_dark", name = "Rail", collide = false })
	end
	box(m, f, 0.4, 0.3, 1.38, 0.6, 0.08, 0.08, "wood", "Rung")
	pot(m, f, -1.2, 0.69, 1.15, "pink")
end

-- Cottage (4 x 3): stone and plaster with a red roof, a chimney, a porch, windows with flower boxes, a picket fence.
B.cottage = function(m, f)
	footing(m, f, 4, 3, "rock", 0.15)
	box(m, f, 0, 1.25, -0.3, 3.6, 2.2, 2.2, "wall", "Walls")
	box(m, f, 0, 0.35, -0.3, 3.65, 0.4, 2.25, "rock", "Stones")
	for _, x in { -1.8, 1.8 } do
		box(m, f, x, 1.25, 0.8, 0.12, 2.2, 0.12, "wood_dark", "Corner")
	end
	door(m, f * CFrame.new(0, 0.15, 0), 0.7, 0.8, 0.75, 1.5, "blue")
	window(m, f * CFrame.new(0, 0.15, 0), -0.9, 1.35, 0.8, 0.8, 0.7)
	box(m, f, -0.9, 0.85, 0.95, 0.9, 0.18, 0.25, "wood", "FlowerBox")
	for k = 0, 3 do
		box(m, f, -1.25 + k * 0.24, 1.0, 0.95, 0.15, 0.15, 0.15, if k % 2 == 0 then "pink" else "purple", "Bloom")
	end
	sideWindow(m, f * CFrame.new(0, 0.15, 0), 1.8, 1.35, -0.3, 0.7, 0.6)
	roof(m, f * CFrame.new(0, 0, -0.3), 2.35, 3.6, 2.2, 1.3, "berry_red", "wood_dark", 0.3)
	box(m, f, 1.1, 3.35, -0.75, 0.45, 1.2, 0.45, "rock", "Chimney")
	box(m, f, 1.1, 3.98, -0.75, 0.55, 0.1, 0.55, "rock_dark", "ChimneyCap")
	-- the porch roof on two posts
	box(m, f, 0.7, 1.95, 1.2, 1.3, 0.12, 0.7, "berry_red", "Porch")
	for _, x in { 0.15, 1.25 } do
		box(m, f, x, 1.0, 1.4, 0.12, 1.9, 0.12, "wood", "PorchPost")
	end
	-- a picket fence along the front, a gap at the path
	for k = 0, 6 do
		local x = -1.9 + k * 0.32
		box(m, f, x, 0.3, 1.45, 0.12, 0.6, 0.08, "white", "Picket")
	end
	box(m, f, -0.95, 0.4, 1.45, 2.0, 0.08, 0.06, "white", "Rail")
end

-- Driftling Nest (2 x 2): a woven nest of straw on a ring of stones, two speckled eggs, a feather, a little sign.
B.nest = function(m, f)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		box(m, f, math.cos(a) * 0.75, 0.1, math.sin(a) * 0.75, 0.35, 0.2, 0.35, if i % 2 == 0 then "rock" else "rock_dark", "Stone")
	end
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		Blocks.part(m, { size = Vector3.new(0.6, 0.25, 0.3), cf = f * CFrame.new(math.cos(a) * 0.6, 0.35, math.sin(a) * 0.6) * CFrame.Angles(0, -a, math.rad(15)), color = if i % 2 == 0 then "sand_dark" else "wood", name = "Straw", collide = false })
	end
	box(m, f, 0, 0.22, 0, 1.0, 0.15, 1.0, "sand", "Bed")
	ball(m, f, -0.15, 0.45, -0.05, 0.45, "cream", "Egg")
	ball(m, f, 0.22, 0.42, 0.18, 0.4, "window", "Egg")
	box(m, f, -0.1, 0.55, 0.12, 0.08, 0.08, 0.04, "blue", "Speckle")
	box(m, f, 0.3, 0.52, 0.32, 0.08, 0.08, 0.04, "berry_red", "Speckle")
	Blocks.part(m, { size = Vector3.new(0.12, 0.05, 0.5), cf = f * CFrame.new(0.55, 0.5, -0.45) * CFrame.Angles(0, math.rad(40), math.rad(20)), color = "white", name = "Feather", collide = false })
	box(m, f, -0.85, 0.4, 0.85, 0.08, 0.8, 0.08, "wood_dark", "SignPost")
	box(m, f, -0.85, 0.75, 0.88, 0.45, 0.3, 0.06, "wood", "Sign")
end

-- Cozy Burrow (3 x 3): a grassy mound with a round door in a timber frame, a mossy rock, mushrooms, a lantern.
B.burrow = function(m, f)
	ball(m, f, 0, 0.25, -0.25, 2.8, "grass_dark", "Mound")
	ball(m, f, -0.6, 0.6, -0.5, 1.4, "grass", "Mound")
	box(m, f, 0, 0.02, 0, 3, 0.04, 3, "grass_dark", "Lawn")
	cyl(m, f, 0, 0.55, 1.0, 1.0, 0.15, "black", "Hole").CFrame = f * CFrame.new(0, 0.55, 1.0) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, 0, 1.15, 1.08, 1.3, 0.2, 0.25, "wood", "Lintel")
	for _, x in { -0.6, 0.6 } do
		box(m, f, x, 0.55, 1.1, 0.2, 1.1, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0, 0.05, 1.35, 0.9, 0.1, 0.5, "rock", "Doorstep")
	ball(m, f, 1.1, 0.35, 0.6, 0.7, "rock", "Rock")
	ball(m, f, 1.05, 0.62, 0.55, 0.4, "leaf_dark", "Moss")
	for k, x in { -1.1, -0.85 } do
		box(m, f, x, 0.18, 0.9, 0.1, 0.36, 0.1, "cream", "Stalk")
		box(m, f, x, 0.4, 0.9, 0.35, 0.15, 0.35, if k == 1 then "berry_red" else "orange", "Cap")
	end
	box(m, f, 0.9, 0.35, 1.25, 0.08, 0.7, 0.08, "wood_dark", "LampPost")
	box(m, f, 0.9, 0.75, 1.25, 0.2, 0.25, 0.2, "yellow", "Lamp", true)
end

-- Training Yard (4 x 4): a sandy ring in a fence, a dummy on a post, a rack of wooden swords, a target, a bench.
B.yard = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 4, "sand", "Ground")
	box(m, f, 0, 0.07, 0, 2.2, 0.06, 2.2, "sand_dark", "Ring")
	fence(m, f, -1.9, 1.9, -1.9)
	fenceZ(m, f, -1.9, 1.9, -1.9)
	fenceZ(m, f, -1.9, 1.9, 1.9)
	-- the dummy
	box(m, f, 0, 0.9, -0.2, 0.2, 1.8, 0.2, "wood_dark", "Post")
	box(m, f, 0, 1.3, -0.2, 0.7, 0.8, 0.45, "sand_dark", "Dummy")
	box(m, f, 0, 1.3, -0.2, 0.75, 0.12, 0.5, "wood_dark", "Belt")
	box(m, f, 0, 1.95, -0.2, 0.45, 0.45, 0.45, "sand_dark", "Head")
	box(m, f, 0, 1.55, -0.2, 1.4, 0.15, 0.15, "wood_dark", "Arms")
	box(m, f, -0.1, 2.0, 0.03, 0.08, 0.08, 0.04, "black", "Eye")
	box(m, f, 0.1, 2.0, 0.03, 0.08, 0.08, 0.04, "black", "Eye")
	-- the weapon rack and the target
	box(m, f, 1.3, 0.6, -1.3, 0.12, 1.2, 0.12, "wood_dark", "RackPost")
	box(m, f, 0.7, 0.6, -1.3, 0.12, 1.2, 0.12, "wood_dark", "RackPost")
	box(m, f, 1.0, 1.0, -1.3, 0.8, 0.1, 0.1, "wood_dark", "RackBar")
	for k = 0, 2 do
		box(m, f, 0.8 + k * 0.2, 0.7, -1.25, 0.08, 1.0, 0.15, "wood", "Sword")
	end
	cyl(m, f, -1.2, 1.0, -1.4, 1.0, 0.15, "white", "Target").CFrame = f * CFrame.new(-1.2, 1.0, -1.4) * CFrame.Angles(math.pi / 2, 0, 0)
	cyl(m, f, -1.2, 1.0, -1.32, 0.6, 0.06, "berry_red", "Ring").CFrame = f * CFrame.new(-1.2, 1.0, -1.32) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, -1.2, 0.5, -1.5, 0.12, 1.0, 0.12, "wood_dark", "Stand")
	box(m, f, 1.1, 0.35, 1.3, 1.2, 0.12, 0.4, "wood", "Bench")
	box(m, f, 1.1, 0.15, 1.3, 1.0, 0.3, 0.1, "wood_dark", "BenchLeg")
	cyl(m, f, 0.65, 0.55, 1.3, 0.3, 0.3, "blue", "Flask")
end

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

-- Palm Tree (3 x 3): a ringed trunk curving up, eight fronds, coconuts, a mound of sand at its foot.
B.palm = function(m, f)
	box(m, f, 0, 0.05, 0, 1.5, 0.1, 1.5, "sand", "Mound")
	local x = 0
	for i = 0, 5 do
		x += 0.1 * i
		box(m, f, x, 0.45 + i * 0.85, 0, 0.7 - i * 0.04, 0.85, 0.7 - i * 0.04, if i % 2 == 0 then "wood" else "wood_dark", "Trunk")
	end
	local top = 5.4
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

-- An upgraded building's pennant: a pole at its back-left corner, the flag red at level 2, gold at 3.
local function pennant(m: Model, f: CFrame, lvl: number, w: number, d: number)
	local x, z = -w / 2 + 0.3, -d / 2 + 0.3
	box(m, f, x, 1.6, z, 0.15, 3.2, 0.15, "wood_dark", "PennantPole")
	ball(m, f, x, 3.25, z, 0.25, "gold", "Knob")
	wedge(m, f, x + 0.45, 2.85, z, 0.75, 0.5, 0.08, if lvl >= 3 then "gold" else "berry_red", math.pi / 2, "Flag")
	if lvl >= 3 then
		wedge(m, f, x + 0.35, 2.3, z, 0.55, 0.35, 0.08, "berry_red", math.pi / 2, "Flag")
		lamp(m, f, w / 2 - 0.25, d / 2 - 0.25)
	end
end

-- The piece's model at `at` (the footprint's centre on the grass, turned). Unknown ids build nothing.
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
	Blocks.windy(m) -- leaves sway, pennants ripple
	return m
end

function DecorModels.has(id: string): boolean
	return B[id] ~= nil
end

return DecorModels
