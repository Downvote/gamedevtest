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

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()

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

-- Hatchery (4 x 4): a warm nursery at the back (plaster walls, a thatched roof, a round window aglow, a chimney's
-- wisp), a big nest of straw in front holding three speckled eggs of the rarities' colours, a heat lamp over them, a
-- sack of feed and a low fence round the nest.
B.hatchery = function(m, f)
	footing(m, f, 4, 4, "sand_dark", 0.1)
	-- the nursery
	box(m, f, 0, 1.15, -0.9, 3.2, 1.9, 1.8, "cream", "Walls")
	for _, x in { -1.55, 1.55 } do
		box(m, f, x, 1.15, -0.9, 0.15, 1.95, 1.85, "wood_dark", "Corner")
	end
	box(m, f, 0, 0.25, -0.9, 3.3, 0.3, 1.9, "rock", "Sill")
	roof(m, f * CFrame.new(0, 0, -0.9), 2.1, 3.2, 1.8, 1.2, "sand_dark", "wood_dark", 0.35)
	for k = 0, 6 do
		box(m, f, -1.5 + k * 0.5, 1.98, 0.1, 0.3, 0.22, 0.1, "sand", "Fringe")
	end
	door(m, f * CFrame.new(-0.8, 0.4, 0), 0, 0.02, 0.6, 1.05, "wood_dark")
	-- a round window aglow (a warm room for the eggs)
	cyl(m, f, 0.75, 1.3, 0.01, 0.7, 0.08, "wood_dark", "WindowRim").CFrame = f * CFrame.new(0.75, 1.3, 0.01) * CFrame.Angles(math.pi / 2, 0, 0)
	cyl(m, f, 0.75, 1.3, 0.05, 0.5, 0.06, "yellow", "WindowGlow").CFrame = f * CFrame.new(0.75, 1.3, 0.05) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, 1.1, 2.75, -1.3, 0.4, 0.8, 0.4, "rock_dark", "Chimney")
	box(m, f, 1.1, 3.2, -1.3, 0.5, 0.12, 0.5, "rock", "ChimneyCap")
	-- the nest of straw and its eggs
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		Blocks.part(m, { size = Vector3.new(0.6, 0.28, 0.32), cf = f * CFrame.new(0.4 + math.cos(a) * 0.8, 0.28, 1.05 + math.sin(a) * 0.6) * CFrame.Angles(0, -a, math.rad(15)), color = if i % 2 == 0 then "sand_dark" else "wood", name = "Straw", collide = false })
	end
	box(m, f, 0.4, 0.2, 1.05, 1.2, 0.15, 0.9, "sand", "Bed")
	ball(m, f, 0.05, 0.5, 1.0, 0.55, "cream", "Egg")
	box(m, f, 0.12, 0.62, 1.27, 0.1, 0.1, 0.04, "green", "Speckle")
	ball(m, f, 0.55, 0.52, 0.9, 0.6, "window", "Egg")
	box(m, f, 0.62, 0.66, 1.2, 0.1, 0.1, 0.04, "purple", "Speckle")
	ball(m, f, 0.75, 0.46, 1.35, 0.45, "yellow", "Egg")
	box(m, f, 0.82, 0.52, 1.57, 0.08, 0.08, 0.04, "orange", "Speckle")
	-- the heat lamp leaning over the nest
	box(m, f, 1.6, 0.9, 1.6, 0.12, 1.8, 0.12, "steel_dark", "LampPole")
	box(m, f, 1.2, 1.78, 1.35, 0.9, 0.1, 0.1, "steel_dark", "LampArm")
	box(m, f, 0.8, 1.62, 1.2, 0.4, 0.25, 0.4, "steel", "LampHood")
	box(m, f, 0.8, 1.45, 1.2, 0.25, 0.1, 0.25, "orange", "LampGlow", true)
	-- a sack of feed and the fence
	sack(m, f, -1.45, 0, 1.45, "sand")
	fence(m, f, -0.65, 1.85, 1.92, "wood")
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

------------------------------------------------------------------ the town and the city (GAME_DESIGN 4.1)
-- A storey's box: walls of `color` w x h x d centred at (x, y0 + h / 2, z), a darker band at its foot.
local function storey(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, h: number, d: number, color: string, band: string?)
	box(m, f, x, y0 + h / 2, z, w, h, d, color, "Walls")
	box(m, f, x, y0 + 0.12, z, w + 0.06, 0.24, d + 0.06, band or "rock", "Band")
end

-- A flat roof with a parapet over a w x d box whose top is at y.
local function flatRoof(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, d: number, color: string, rim: string?)
	box(m, f, x, y + 0.06, z, w + 0.2, 0.12, d + 0.2, color, "Roof")
	box(m, f, x, y + 0.3, z - d / 2 - 0.05, w + 0.2, 0.36, 0.12, rim or "wall_trim", "Parapet")
	box(m, f, x, y + 0.3, z + d / 2 + 0.05, w + 0.2, 0.36, 0.12, rim or "wall_trim", "Parapet")
	box(m, f, x - w / 2 - 0.05, y + 0.3, z, 0.12, 0.36, d + 0.2, rim or "wall_trim", "Parapet")
	box(m, f, x + w / 2 + 0.05, y + 0.3, z, 0.12, 0.36, d + 0.2, rim or "wall_trim", "Parapet")
end

-- A street lamp: an iron post with a lit lantern (or two arms).
local function streetLamp(m: Instance, f: CFrame, x: number, z: number, double: boolean?)
	box(m, f, x, 0.1, z, 0.35, 0.2, 0.35, "steel_dark", "LampBase")
	box(m, f, x, 1.3, z, 0.14, 2.4, 0.14, "steel_dark", "LampPost")
	if double then
		box(m, f, x, 2.45, z, 0.9, 0.08, 0.08, "steel_dark", "LampArm")
		for _, dx in { -0.42, 0.42 } do
			box(m, f, x + dx, 2.25, z, 0.26, 0.32, 0.26, "yellow", "LampLight", true)
			box(m, f, x + dx, 2.47, z, 0.34, 0.08, 0.34, "steel_dark", "LampCap")
		end
	else
		box(m, f, x, 2.6, z, 0.32, 0.38, 0.32, "yellow", "LampLight", true)
		box(m, f, x, 2.86, z, 0.42, 0.1, 0.42, "steel_dark", "LampCap")
	end
end

-- A row of rice or kelp: thin blades in a line along X.
local function blades(m: Instance, f: CFrame, x0: number, x1: number, y: number, z: number, h: number, a: string, b: string)
	local x = x0
	local k = 0
	while x <= x1 + 0.01 do
		box(m, f, x, y + h / 2, z, 0.1, h, 0.1, if k % 2 == 0 then a else b, "Blade")
		x += 0.3
		k += 1
	end
end

-- Rice Terrace (4 x 4): two stepped paddies of still water edged in earth, rows of rice, a hut with a straw hat.
B.paddy = function(m, f)
	footing(m, f, 4, 4, "wood_dark", 0.1)
	for k, z in { -0.95, 0.95 } do
		local y = if k == 1 then 0.55 else 0.2
		box(m, f, 0, y / 2, z, 3.9, y, 1.85, "wood_dark", "Terrace")
		box(m, f, 0, y + 0.02, z, 3.6, 0.06, 1.6, "water", "Paddy"):SetAttribute("PixelWater", 2)
		for r = 0, 2 do
			blades(m, f, -1.6, 1.6, y, z - 0.55 + r * 0.55, 0.45, "leaf", "green")
		end
	end
	box(m, f, 1.55, 0.95, -1.5, 0.12, 1.2, 0.12, "wood_dark", "Post")
	box(m, f, 1.55, 1.6, -1.5, 0.8, 0.12, 0.8, "sand_dark", "HatBrim")
	box(m, f, 1.55, 1.75, -1.5, 0.4, 0.2, 0.4, "sand", "Hat")
	sack(m, f, -1.6, 0.2, 1.65, "cream")
end

-- Kelp Farm (4 x 4): a sea pen of blue water in a timber frame, kelp swaying in rows, floats, a diver's boat.
B.kelpfarm = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 4, "sand_dark", "Bank")
	box(m, f, 0, 0.12, 0, 3.6, 0.1, 3.6, "water", "Pen"):SetAttribute("PixelWater", 2)
	for _, z in { -1.85, 1.85 } do
		box(m, f, 0, 0.3, z, 4, 0.2, 0.2, "wood", "Boardwalk")
	end
	for _, x in { -1.85, 1.85 } do
		box(m, f, x, 0.3, 0, 0.2, 0.2, 4, "wood", "Boardwalk")
	end
	for r = 0, 3 do
		local x = -1.2 + r * 0.8
		for k = 0, 3 do
			local z = -1.2 + k * 0.8
			box(m, f, x, 0.45, z, 0.12, 0.7 + (r + k) % 2 * 0.25, 0.12, if (r + k) % 2 == 0 then "leaf_dark" else "green", "Kelp")
		end
		ball(m, f, x, 0.22, -1.6, 0.25, "orange", "Float")
	end
	box(m, f, 1.2, 0.3, 1.3, 1.2, 0.25, 0.6, "berry_red", "Boat")
	box(m, f, 1.2, 0.45, 1.3, 1.0, 0.08, 0.45, "wood", "BoatSeat")
	barrel(m, f, -1.6, 0.4, 1.6, 0.6)
end

-- Sky Garden (5 x 4): a glass tower of three floors, each a terrace of planters spilling green, a water tank on top.
B.skygarden = function(m, f)
	footing(m, f, 5, 4, "pavement", 0.15)
	for i = 0, 2 do
		local w, d = 4.4 - i * 0.8, 3.4 - i * 0.6
		local y0 = 0.15 + i * 1.6
		box(m, f, 0, y0 + 0.75, -0.2, w - 0.6, 1.5, d - 0.6, "window", "Glass")
		for _, x in { -(w - 0.6) / 2, (w - 0.6) / 2 } do
			box(m, f, x, y0 + 0.75, -0.2, 0.12, 1.5, d - 0.5, "steel", "Mullion")
		end
		box(m, f, 0, y0 + 1.55, -0.2, w, 0.12, d, "steel", "Slab")
		box(m, f, 0, y0 + 1.75, -0.2 + d / 2 - 0.2, w, 0.3, 0.35, "pot", "Planter")
		for k = 0, math.floor(w / 0.5) - 1 do
			ball(m, f, -w / 2 + 0.25 + k * 0.5, y0 + 1.95, -0.2 + d / 2 - 0.2, 0.42, if k % 3 == 0 then "leaf" elseif k % 3 == 1 then "green" else "leaf_dark", "Leaves")
		end
	end
	cyl(m, f, 0, 5.3, -0.4, 0.9, 0.7, "steel", "Tank")
	cyl(m, f, 0, 5.7, -0.4, 1.0, 0.1, "steel_dark", "TankLid")
	door(m, f * CFrame.new(0, 0.15, 0), 0, 1.3, 0.8, 1.2, "steel")
end

-- Timber Works (4 x 4): an open shed of stacked planks, a crane arm lifting a log, a cart.
B.timber = function(m, f)
	footing(m, f, 4, 4, "sand_dark", 0.08)
	for _, x in { -1.8, 0.2 } do
		for _, z in { -1.7, -0.1 } do
			box(m, f, x, 1.2, z, 0.18, 2.4, 0.18, "wood_dark", "Post")
		end
	end
	wedge(m, f, -0.8, 2.6, -0.9, 2.5, 0.5, 2.0, "berry_red", math.pi, "ShedRoof")
	for k = 0, 3 do
		box(m, f, -0.8, 0.25 + k * 0.22, -0.9, 1.8, 0.18, 1.2, if k % 2 == 0 then "wood" else "sand_dark", "Planks")
	end
	-- the crane: a mast, a jib, a rope and a log
	box(m, f, 1.4, 1.5, -1.2, 0.25, 3.0, 0.25, "wood_dark", "Mast")
	box(m, f, 1.0, 2.9, -0.4, 0.15, 0.15, 1.8, "wood_dark", "Jib")
	box(m, f, 1.0, 2.2, 0.4, 0.05, 1.3, 0.05, "sand", "Rope")
	log(m, f, 1.0, 1.4, 0.4, 1.4, 0.4, "wood")
	-- a cart of logs
	box(m, f, -0.6, 0.45, 1.3, 1.4, 0.3, 0.8, "wood_dark", "Cart")
	for _, x in { -1.1, -0.1 } do
		cyl(m, f, x, 0.3, 1.75, 0.5, 0.1, "wood_dark", "Wheel").CFrame = f * CFrame.new(x, 0.3, 1.75) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	log(m, f, -0.6, 0.75, 1.2, 1.3, 0.3, "wood")
	log(m, f, -0.6, 0.75, 1.45, 1.3, 0.3, "wood")
end

-- Bamboo Grove (4 x 3): tall green canes in clumps, a little shrine of cut bamboo, bundles ready to carry.
B.bamboo = function(m, f)
	footing(m, f, 4, 3, "grass_dark", 0.06)
	local spots = { { -1.5, -1.0 }, { -1.1, -0.6 }, { -0.4, -1.1 }, { 0.2, -0.7 }, { 0.9, -1.1 }, { 1.5, -0.6 }, { -1.6, 0.2 }, { 1.4, 0.3 } }
	for i, sp in spots do
		local h = 2.2 + (i % 3) * 0.6
		box(m, f, sp[1], h / 2, sp[2], 0.16, h, 0.16, if i % 2 == 0 then "leaf" else "green", "Cane")
		box(m, f, sp[1], h * 0.4, sp[2], 0.2, 0.06, 0.2, "leaf_dark", "Node")
		box(m, f, sp[1] + 0.25, h - 0.2, sp[2], 0.5, 0.08, 0.2, "leaf_dark", "Leaf")
		box(m, f, sp[1] - 0.2, h - 0.5, sp[2] + 0.1, 0.4, 0.08, 0.2, "leaf", "Leaf")
	end
	for k = 0, 2 do
		log(m, f, -0.3, 0.12 + k * 0.16, 0.9 + (k % 2) * 0.12, 1.6, 0.14, "green")
	end
	box(m, f, -0.3, 0.3, 0.95, 0.12, 0.5, 0.5, "sand_dark", "Tie")
	box(m, f, 0.9, 0.5, 1.0, 0.7, 1.0, 0.6, "sand", "Shrine")
	wedge(m, f, 0.9, 1.15, 1.0, 0.9, 0.3, 0.8, "green", math.pi / 2, "ShrineRoof")
end

-- Grand Mill (5 x 4): a stone mill house, a big waterwheel turning in a race, a stack of sawn boards.
B.grandmill = function(m, f)
	footing(m, f, 5, 4, "rock", 0.15)
	storey(m, f, -0.6, 0.15, -0.6, 3.2, 2.4, 2.4, "rock")
	window(m, f, -1.3, 1.5, 0.6, 0.6, 0.6)
	door(m, f * CFrame.new(0, 0.15, 0), -0.1, 0.6, 0.8, 1.4, "wood_dark")
	roof(m, f * CFrame.new(-0.6, 0, -0.6), 2.55, 3.2, 2.4, 1.2, "wood_dark", "wood", 0.3)
	-- the race and the wheel on the east side
	box(m, f, 1.75, 0.15, 0, 1.2, 0.2, 3.8, "rock_dark", "Race")
	box(m, f, 1.75, 0.3, 0, 0.9, 0.08, 3.6, "water", "Water"):SetAttribute("PixelWater", 2)
	cyl(m, f, 1.6, 1.5, -0.6, 2.6, 0.4, "wood", "Wheel").CFrame = f * CFrame.new(1.6, 1.5, -0.6) * CFrame.Angles(0, 0, math.pi / 2)
	cyl(m, f, 1.6, 1.5, -0.6, 2.0, 0.45, "wood_dark", "WheelInner").CFrame = f * CFrame.new(1.6, 1.5, -0.6) * CFrame.Angles(0, 0, math.pi / 2)
	for k = 0, 5 do
		local a = k * math.pi / 3
		Blocks.part(m, { size = Vector3.new(0.5, 0.12, 0.6), cf = f * CFrame.new(1.6, 1.5 + math.sin(a) * 1.2, -0.6 + math.cos(a) * 1.2) * CFrame.Angles(a, 0, 0), color = "wood_dark", name = "Paddle", collide = false })
	end
	for k = 0, 3 do
		box(m, f, -1.6, 0.25 + k * 0.18, 1.5, 1.6, 0.15, 0.7, if k % 2 == 0 then "wood" else "sand_dark", "Boards")
	end
end

-- Bakery (4 x 3): a warm brick shop with an arched window of loaves, a striped awning, a chimney, a bench.
B.bakery = function(m, f)
	footing(m, f, 4, 3, "rock", 0.15)
	storey(m, f, 0, 0.15, -0.3, 3.6, 2.4, 2.2, "berry_red", "rock_dark")
	for k = 0, 4 do
		box(m, f, 0, 0.6 + k * 0.45, 0.82, 3.62, 0.04, 0.02, "orange", "Mortar")
	end
	door(m, f * CFrame.new(0, 0.15, 0), 1.0, 0.8, 0.75, 1.5, "wood_dark")
	box(m, f, -0.7, 1.4, 0.83, 1.6, 1.0, 0.1, "wood_dark", "ShopFrame")
	box(m, f, -0.7, 1.4, 0.87, 1.4, 0.8, 0.05, "window", "ShopWindow")
	for k = 0, 2 do
		box(m, f, -1.2 + k * 0.5, 1.1, 0.92, 0.35, 0.18, 0.12, "sand_dark", "Loaf")
	end
	awning(m, f, 2.1, 3.6, 0.85, "white", "berry_red")
	flatRoof(m, f, 0, 2.55, -0.3, 3.6, 2.2, "rock_dark", "berry_red")
	box(m, f, 1.2, 3.2, -0.9, 0.45, 1.1, 0.45, "rock", "Chimney")
	box(m, f, 0, 2.3, 0.9, 1.2, 0.3, 0.06, "cream", "Sign")
	box(m, f, 0, 2.3, 0.94, 0.9, 0.12, 0.03, "wood_dark", "Letters")
	barrel(m, f, -1.65, 0.15, 1.2, 0.5)
end

-- Grand Bazaar (5 x 4): three stalls under striped awnings round a tiled court, rugs, jars, lanterns on a line.
B.bazaar = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 4, "floor_b", "Court")
	local stripes = { { "orange", "yellow" }, { "purple", "white" }, { "blue", "white" } }
	for i, x in { -1.6, 0, 1.6 } do
		box(m, f, x, 0.45, -0.9, 1.4, 0.7, 0.9, "wood", "Counter")
		box(m, f, x, 0.85, -0.9, 1.4, 0.1, 0.9, "wood_dark", "Top")
		for _, dx in { -0.65, 0.65 } do
			box(m, f, x + dx, 1.1, -1.35, 0.1, 2.2, 0.1, "wood_dark", "Pole")
		end
		awning(m, f * CFrame.new(x, 0, -1.6), 2.2, 1.6, 0.7, stripes[i][1], stripes[i][2])
		box(m, f, x - 0.3, 1.0, -0.9, 0.3, 0.3, 0.3, if i == 1 then "orange" elseif i == 2 then "purple" else "blue", "Goods")
		ball(m, f, x + 0.3, 1.05, -0.9, 0.35, if i == 1 then "yellow" elseif i == 2 then "pink" else "window", "Goods")
	end
	box(m, f, -0.8, 0.12, 1.0, 1.4, 0.04, 1.0, "rug", "Rug")
	box(m, f, 1.0, 0.12, 1.1, 1.2, 0.04, 0.9, "berry_red", "Rug")
	for _, x in { -2.2, 2.2 } do
		cyl(m, f, x, 0.35, 1.4, 0.45, 0.6, "pot", "Jar")
	end
	box(m, f, 0, 2.3, 0.4, 4.6, 0.04, 0.04, "wood_dark", "Line")
	for k = 0, 4 do
		box(m, f, -1.8 + k * 0.9, 2.15, 0.4, 0.2, 0.25, 0.2, if k % 2 == 0 then "yellow" else "orange", "Lantern", true)
	end
end

-- Grand Hotel (5 x 5): four floors of cream stone with balconies and rows of windows, a gold-trimmed entrance with an
-- awning and a doorman's lamps, a flag on the roof.
B.hotel = function(m, f)
	footing(m, f, 5, 5, "pavement", 0.15)
	for i = 0, 3 do
		local y0 = 0.15 + i * 1.6
		storey(m, f, 0, y0, -0.5, 4.4, 1.6, 3.6, "cream", if i == 0 then "rock_dark" else "wall_trim")
		if i > 0 then
			for _, x in { -1.5, -0.5, 0.5, 1.5 } do
				window(m, f, x, y0 + 0.85, 1.3, 0.5, 0.65)
			end
			box(m, f, 0, y0 + 0.1, 1.55, 4.0, 0.1, 0.4, "wall_trim", "Balcony")
			box(m, f, 0, y0 + 0.4, 1.73, 4.0, 0.06, 0.06, "gold", "Railing")
		end
		sideWindow(m, f, 2.2, y0 + 0.85, -0.5, 0.6, 0.6)
	end
	door(m, f * CFrame.new(0, 0.15, 0), 0, 1.35, 1.0, 1.3, "gold")
	awning(m, f, 1.6, 2.0, 1.6, "berry_red", "berry_red")
	for _, x in { -1.6, 1.6 } do
		window(m, f * CFrame.new(0, 0.15, 0), x, 0.9, 1.3, 0.7, 0.6)
	end
	flatRoof(m, f, 0, 6.55, -0.5, 4.4, 3.6, "rock_dark", "gold")
	box(m, f, 1.6, 7.6, -1.6, 0.1, 2.0, 0.1, "steel_dark", "FlagPole")
	wedge(m, f, 2.0, 8.3, -1.6, 0.8, 0.5, 0.06, "berry_red", math.pi / 2, "Flag")
	box(m, f, 0, 6.2, 1.36, 1.6, 0.4, 0.06, "gold", "Sign")
	for _, x in { -1.0, 1.0 } do
		box(m, f, x, 1.1, 2.1, 0.25, 0.4, 0.25, "yellow", "Lamp", true)
		box(m, f, x, 0.45, 2.1, 0.12, 0.9, 0.12, "steel_dark", "LampPost")
	end
	pot(m, f, -2.0, 0.15, 2.1, "pink")
	pot(m, f, 2.0, 0.15, 2.1, "yellow")
end


-- Driftling Den (3 x 3): a mossy rock with a round entrance, soft beds of leaves inside, a sign, mushrooms.
B.den = function(m, f)
	ball(m, f, 0, 0.6, -0.3, 2.8, "rock", "Rock")
	ball(m, f, -0.5, 1.4, -0.5, 1.4, "rock_dark", "Rock")
	ball(m, f, 0.2, 1.7, -0.4, 1.6, "grass_dark", "Moss")
	box(m, f, 0, 0.02, 0, 3, 0.04, 3, "grass_dark", "Lawn")
	cyl(m, f, 0, 0.55, 1.0, 1.1, 0.2, "black", "Hole").CFrame = f * CFrame.new(0, 0.55, 1.02) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, 0, 0.1, 1.2, 1.2, 0.12, 0.4, "leaf", "Bed")
	for k, x in { -1.1, 1.1 } do
		box(m, f, x, 0.18, 1.1, 0.1, 0.36, 0.1, "cream", "Stalk")
		box(m, f, x, 0.4, 1.1, 0.35, 0.15, 0.35, if k == 1 then "pink" else "purple", "Cap")
	end
	box(m, f, 1.2, 0.4, 0.4, 0.08, 0.8, 0.08, "wood_dark", "SignPost")
	box(m, f, 1.2, 0.75, 0.43, 0.45, 0.3, 0.06, "wood", "Sign")
end

-- Treetop Roost (4 x 4): a great tree whose boughs hold round nests and a ladder, lanterns hung in the leaves.
B.roost = function(m, f)
	box(m, f, 0, 0.02, 0, 4, 0.04, 4, "grass_dark", "Lawn")
	cyl(m, f, 0, 2.0, 0, 1.0, 4.0, "wood_dark", "Trunk")
	for _, r in { { 1.0, 0.4 }, { -0.9, -0.5 }, { 0.4, -1.0 } } do
		box(m, f, r[1] / 2, 0.15, r[2] / 2, math.abs(r[1]) + 0.3, 0.3, 0.3, "wood_dark", "Root")
	end
	ball(m, f, 0, 4.6, 0, 3.4, "leaf_dark", "Crown")
	ball(m, f, -0.9, 4.2, 0.7, 2.0, "leaf", "Crown")
	ball(m, f, 0.9, 4.9, -0.5, 2.0, "leaf", "Crown")
	for _, n in { { 1.3, 2.6, 0.6 }, { -1.3, 3.0, 0.2 }, { 0.2, 3.4, 1.4 } } do
		cyl(m, f, n[1], n[2], n[3], 0.9, 0.3, "sand_dark", "Nest")
		ball(m, f, n[1], n[2] + 0.2, n[3], 0.35, "cream", "Egg")
		box(m, f, n[1] * 0.5, n[2] - 0.2, n[3] * 0.5, math.abs(n[1]) + 0.2, 0.15, 0.15, "wood_dark", "Bough")
	end
	for k = 0, 5 do
		box(m, f, 0.55, 0.3 + k * 0.4, 0.55, 0.4, 0.06, 0.06, "wood", "Rung")
	end
	box(m, f, -1.0, 3.2, 1.2, 0.2, 0.25, 0.2, "yellow", "Lantern", true)
	box(m, f, 1.4, 3.5, -0.9, 0.2, 0.25, 0.2, "yellow", "Lantern", true)
end

-- Spring Grotto (4 x 4): a rock arch over a steaming warm pool, smooth stones round it, little waterfalls.
B.grotto = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 4, "rock", "Floor")
	cyl(m, f, 0.2, 0.15, 0.6, 2.6, 0.2, "rock_dark", "PoolRim")
	cyl(m, f, 0.2, 0.22, 0.6, 2.2, 0.1, "shallow", "Pool"):SetAttribute("PixelWater", 2)
	ball(m, f, -1.3, 1.2, -1.0, 2.0, "rock", "Rock")
	ball(m, f, 1.4, 1.1, -1.1, 1.8, "rock", "Rock")
	box(m, f, 0, 2.2, -1.2, 3.0, 0.6, 0.9, "rock", "Arch")
	box(m, f, 0, 2.55, -1.2, 2.6, 0.2, 0.7, "grass_dark", "Moss")
	box(m, f, 0, 1.2, -0.95, 0.5, 1.8, 0.08, "window", "Falls")
	for k = 0, 4 do
		local a = k * 1.25
		ball(m, f, 0.2 + math.cos(a) * 1.4, 0.25, 0.6 + math.sin(a) * 1.4, 0.35, if k % 2 == 0 then "rock_dark" else "rock", "Stone")
	end
	for _, s in { { -0.2, 0.8 }, { 0.6, 0.4 } } do
		ball(m, f, s[1], 0.6, s[2], 0.3, "white", "Steam")
		ball(m, f, s[1] + 0.1, 0.95, s[2], 0.22, "white", "Steam")
	end
	box(m, f, -1.6, 0.4, 1.4, 0.4, 0.5, 0.4, "yellow", "Lamp", true)
end

-- Driftling Palace (5 x 5): a little palace of pastel domes for driftlings: round doors at every size, a gold crown on
-- the main dome, a moat of shallow water, banners.
B.palace = function(m, f)
	footing(m, f, 5, 5, "white", 0.15)
	box(m, f, 0, 0.2, 2.15, 5, 0.1, 0.6, "shallow", "Moat"):SetAttribute("PixelWater", 2)
	storey(m, f, 0, 0.15, -0.5, 3.0, 2.0, 2.8, "pink", "white")
	Blocks.part(m, { size = Vector3.new(2.6, 2.6, 2.6), cf = f * CFrame.new(0, 2.6, -0.5), color = "purple", shape = "Ball", name = "Dome", collide = false })
	box(m, f, 0, 3.95, -0.5, 0.6, 0.3, 0.6, "gold", "Crown")
	for k = 0, 3 do
		local a = k * math.pi / 2
		box(m, f, math.cos(a) * 0.3, 4.2, -0.5 + math.sin(a) * 0.3, 0.12, 0.3, 0.12, "gold", "Point")
	end
	for _, x in { -2.0, 2.0 } do
		cyl(m, f, x, 1.1, -0.5, 1.0, 2.2, "white", "Tower")
		Blocks.part(m, { size = Vector3.new(1.1, 1.1, 1.1), cf = f * CFrame.new(x, 2.3, -0.5), color = "window", shape = "Ball", name = "Dome", collide = false })
		box(m, f, x, 2.9, -0.5, 0.08, 0.6, 0.08, "gold", "Pole")
		wedge(m, f, x + 0.25, 3.05, -0.5, 0.45, 0.3, 0.05, "berry_red", math.pi / 2, "Banner")
	end
	for i, s in { 0.9, 0.6, 0.4 } do
		local x = -0.9 + (i - 1) * 0.9
		cyl(m, f, x, 0.15 + s / 2, 0.92, s, 0.1, "wood_dark", "Door").CFrame = f * CFrame.new(x, 0.15 + s / 2, 0.92) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	box(m, f, 0, 0.25, 1.75, 1.0, 0.12, 0.6, "wood", "Bridge")
end

------------------------------------------------------------------ boosts
-- Tool Shed (2 x 2): a lean-to of planks, axes and saws on the wall, a whetstone.
B.toolshed = function(m, f)
	footing(m, f, 2, 2, "wood_dark", 0.08)
	box(m, f, 0, 0.8, -0.3, 1.8, 1.5, 1.2, "wood", "Shed")
	wedge(m, f, 0, 1.8, -0.3, 2.0, 0.5, 1.4, "steel", math.pi, "Roof")
	door(m, f * CFrame.new(0, 0.08, 0), -0.4, 0.3, 0.6, 1.1, "wood_dark")
	box(m, f, 0.45, 1.1, 0.33, 0.08, 0.6, 0.04, "wood_dark", "Handle")
	box(m, f, 0.45, 1.35, 0.35, 0.3, 0.2, 0.04, "steel", "AxeHead")
	box(m, f, 0.75, 0.9, 0.33, 0.06, 0.5, 0.04, "steel", "Saw")
	cyl(m, f, 0.6, 0.3, 0.75, 0.5, 0.15, "rock", "Whetstone").CFrame = f * CFrame.new(0.6, 0.3, 0.75) * CFrame.Angles(math.pi / 2, 0, 0)
end

-- Windmill (3 x 3): a round white tower, a cap, four sails, sacks of flour.
B.windmill = function(m, f)
	footing(m, f, 3, 3, "rock", 0.12)
	cyl(m, f, 0, 1.9, -0.2, 1.8, 3.6, "white", "Tower")
	cyl(m, f, 0, 0.35, -0.2, 2.0, 0.5, "rock", "TowerBase")
	Blocks.part(m, { size = Vector3.new(1.9, 1.9, 1.9), cf = f * CFrame.new(0, 3.8, -0.2), color = "berry_red", shape = "Ball", name = "Cap", collide = false })
	door(m, f * CFrame.new(0, 0.12, 0), 0, 0.68, 0.55, 1.0, "wood_dark")
	window(m, f, 0, 2.6, 0.68, 0.35, 0.35)
	box(m, f, 0, 3.4, 0.75, 0.25, 0.25, 0.3, "wood_dark", "Hub")
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		Blocks.part(m, { size = Vector3.new(0.12, 1.9, 0.06), cf = f * CFrame.new(math.cos(a) * 0.95, 3.4 + math.sin(a) * 0.95, 0.9) * CFrame.Angles(0, 0, a - math.pi / 2), color = "wood_dark", name = "SailArm", collide = false })
		Blocks.part(m, { size = Vector3.new(0.45, 1.5, 0.04), cf = f * CFrame.new(math.cos(a) * 1.05, 3.4 + math.sin(a) * 1.05, 0.93) * CFrame.Angles(0, 0, a - math.pi / 2), color = "cream", name = "Sail", collide = false })
	end
	sack(m, f, 1.05, 0.12, 0.9, "cream")
	sack(m, f, -1.05, 0.12, 0.95, "white")
end

-- Smokehouse (3 x 3): a dark timber house with a smoking vent, fish hanging under the eaves, a stack of firewood.
B.smokehouse = function(m, f)
	footing(m, f, 3, 3, "rock", 0.12)
	storey(m, f, 0, 0.12, -0.3, 2.4, 1.6, 2.0, "wood_dark", "rock_dark")
	door(m, f * CFrame.new(0, 0.12, 0), 0, 0.7, 0.6, 1.2, "wood")
	roof(m, f * CFrame.new(0, 0, -0.3), 1.72, 2.4, 2.0, 0.9, "rock_dark", "wood_dark", 0.3)
	box(m, f, 0, 2.85, -0.3, 0.5, 0.3, 0.5, "rock", "Vent")
	ball(m, f, 0.1, 3.25, -0.3, 0.45, "white", "Smoke")
	ball(m, f, 0.3, 3.6, -0.4, 0.35, "chalk", "Smoke")
	box(m, f, 0, 1.6, 1.0, 2.2, 0.06, 0.06, "wood_dark", "Rack")
	for k = 0, 3 do
		box(m, f, -0.75 + k * 0.5, 1.35, 1.0, 0.18, 0.4, 0.06, if k % 2 == 0 then "orange" else "sand_dark", "Fish")
	end
	for k = 0, 2 do
		log(m, f, -1.1, 0.25 + k * 0.22, 1.1, 0.7, 0.22, "wood")
	end
end

-- Market Hall (4 x 3): an open hall on stone columns under a long roof, crates of goods, a bell over the door.
B.market = function(m, f)
	footing(m, f, 4, 3, "pavement", 0.12)
	for _, x in { -1.7, -0.6, 0.6, 1.7 } do
		for _, z in { -1.1, 1.0 } do
			box(m, f, x, 1.1, z, 0.25, 2.0, 0.25, "rock", "Column")
		end
	end
	box(m, f, 0, 2.2, -0.05, 3.9, 0.2, 2.6, "wood_dark", "Beam")
	roof(m, f * CFrame.new(0, 0, -0.05), 2.3, 3.8, 2.5, 1.0, "green", "wood_dark", 0.3)
	crate(m, f, -1.1, 0.12, -0.3, 0.6)
	crate(m, f, -0.5, 0.12, -0.5, 0.5)
	barrel(m, f, 0.6, 0.12, -0.4, 0.6)
	box(m, f, 1.2, 0.5, 0.2, 1.0, 0.5, 0.6, "wood", "Table")
	box(m, f, 1.0, 0.85, 0.2, 0.3, 0.2, 0.3, "orange", "Goods")
	box(m, f, 1.4, 0.85, 0.2, 0.3, 0.2, 0.3, "leaf", "Goods")
	box(m, f, 0, 2.65, 1.3, 0.1, 0.5, 0.1, "wood_dark", "BellPost")
	ball(m, f, 0, 2.95, 1.35, 0.35, "gold", "Bell")
end

-- Water Tower (3 x 3): a round tank on four legs with cross braces, a ladder, a pipe down to a trough.
B.watertower = function(m, f)
	for _, x in { -1.0, 1.0 } do
		for _, z in { -1.0, 1.0 } do
			box(m, f, x, 1.6, z, 0.2, 3.2, 0.2, "wood_dark", "Leg")
		end
	end
	for _, y in { 1.0, 2.2 } do
		box(m, f, 0, y, -1.0, 2.0, 0.1, 0.1, "wood", "Brace")
		box(m, f, 0, y, 1.0, 2.0, 0.1, 0.1, "wood", "Brace")
		box(m, f, -1.0, y, 0, 0.1, 0.1, 2.0, "wood", "Brace")
		box(m, f, 1.0, y, 0, 0.1, 0.1, 2.0, "wood", "Brace")
	end
	cyl(m, f, 0, 3.9, 0, 2.6, 1.6, "blue", "Tank")
	for _, y in { 3.4, 4.4 } do
		cyl(m, f, 0, y, 0, 2.7, 0.1, "steel_dark", "Hoop")
	end
	-- a stepped cone of a lid and a vent cap
	cyl(m, f, 0, 4.8, 0, 2.8, 0.2, "steel_dark", "Lid")
	cyl(m, f, 0, 5.0, 0, 2.0, 0.25, "blue", "Lid")
	cyl(m, f, 0, 5.22, 0, 1.2, 0.22, "blue", "Lid")
	cyl(m, f, 0, 5.42, 0, 0.4, 0.2, "steel", "Vent")
	for k = 0, 6 do
		box(m, f, 1.2, 0.4 + k * 0.45, 0.4, 0.3, 0.05, 0.05, "steel", "Rung")
	end
	box(m, f, -0.5, 1.6, 0.6, 0.12, 3.0, 0.12, "steel", "Pipe")
	box(m, f, -0.5, 0.2, 1.1, 0.8, 0.4, 0.5, "wood", "Trough")
	box(m, f, -0.5, 0.38, 1.1, 0.6, 0.06, 0.3, "water", "Water"):SetAttribute("PixelWater", 2)
end

-- Town Hall (5 x 4): a stately hall of pale stone, columns across the front, steps, a clock in the pediment and a
-- domed bell tower with a flag.
B.townhall = function(m, f)
	footing(m, f, 5, 4, "pavement", 0.15)
	box(m, f, 0, 0.3, 1.4, 3.4, 0.3, 0.8, "rock", "Steps")
	storey(m, f, 0, 0.15, -0.5, 4.6, 2.6, 2.6, "cream", "rock")
	for k = 0, 5 do
		box(m, f, -1.9 + k * 0.76, 1.45, 0.95, 0.3, 2.3, 0.3, "white", "Column")
	end
	box(m, f, 0, 2.75, 0.95, 4.4, 0.25, 0.4, "white", "Entablature")
	wedge(m, f, 0, 3.25, 0.95, 4.4, 0.75, 0.4, "white", 0, "Pediment")
	cyl(m, f, 0, 3.25, 1.18, 0.6, 0.05, "gold", "Clock").CFrame = f * CFrame.new(0, 3.25, 1.18) * CFrame.Angles(math.pi / 2, 0, 0)
	door(m, f * CFrame.new(0, 0.15, 0), 0, 0.82, 0.9, 1.6, "wood_dark")
	for _, x in { -1.6, 1.6 } do
		window(m, f, x, 1.55, 0.82, 0.5, 0.9)
	end
	flatRoof(m, f, 0, 2.75, -0.5, 4.6, 2.6, "rock_dark", "white")
	box(m, f, 0, 3.6, -0.7, 1.2, 1.4, 1.2, "cream", "BellTower")
	window(m, f, 0, 3.7, -0.08, 0.4, 0.6)
	Blocks.part(m, { size = Vector3.new(1.3, 1.3, 1.3), cf = f * CFrame.new(0, 4.4, -0.7), color = "green", shape = "Ball", name = "Dome", collide = false })
	box(m, f, 0, 5.3, -0.7, 0.08, 1.0, 0.08, "steel_dark", "FlagPole")
	wedge(m, f, 0.3, 5.6, -0.7, 0.55, 0.35, 0.05, "blue", math.pi / 2, "Flag")
	streetLamp(m, f, -2.1, 1.6)
	streetLamp(m, f, 2.1, 1.6)
end

-- Sun Beacon (3 x 3): a tall pale obelisk on a stepped base holding a glowing sun disc, gold rays round it.
B.beacon = function(m, f)
	box(m, f, 0, 0.2, 0, 3, 0.4, 3, "white", "Step")
	box(m, f, 0, 0.55, 0, 2.2, 0.3, 2.2, "cream", "Step")
	box(m, f, 0, 2.6, 0, 0.9, 3.8, 0.9, "white", "Obelisk")
	for _, y in { 1.2, 2.4, 3.6 } do
		box(m, f, 0, y, 0, 0.98, 0.12, 0.98, "gold", "Ring")
	end
	cyl(m, f, 0, 5.3, 0, 1.5, 0.2, "gold", "Disc").CFrame = f * CFrame.new(0, 5.3, 0) * CFrame.Angles(math.pi / 2, 0, 0)
	ball(m, f, 0, 5.3, 0.05, 0.9, "yellow", "Sun").Material = Enum.Material.Neon
	for k = 0, 7 do
		local a = k * math.pi / 4
		Blocks.part(m, { size = Vector3.new(0.12, 0.6, 0.08), cf = f * CFrame.new(math.cos(a) * 1.05, 5.3 + math.sin(a) * 1.05, 0) * CFrame.Angles(0, 0, a - math.pi / 2), color = "gold", name = "Ray", collide = false })
	end
	for _, x in { -1.2, 1.2 } do
		box(m, f, x, 0.9, 1.2, 0.25, 0.4, 0.25, "yellow", "Lamp", true)
	end
end

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
	local l = lvl or 1
	if fn then
		fn(m, at, l)
	end
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
