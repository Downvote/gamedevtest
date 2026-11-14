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

-- footprints by id (the pennant's corner), and kinds
local FOOT: { [string]: { number } } = {}
local KIND: { [string]: string } = {}
for _, d in Buildings.list do
	FOOT[d.id] = { d.w, d.d }
	KIND[d.id] = d.kind
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

-- A round tube through `pts` (f's frame, in order): a cylinder from each point to the next and a ball at each joint as
-- wide as the segment below it, so it bends with no gap and no step (a trunk, a braided strand). `dia(i)` and
-- `color(i)` give segment i's width (on the 1/8-stud grid: an art pixel; exact, so the joints meet) and colour; `cap`
-- puts a ball on its last point too.
local function tube(m: Instance, f: CFrame, pts: { Vector3 }, dia: (i: number) -> number, color: (i: number) -> string, name: string, cap: boolean?)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local d = math.max(0.25, math.floor(dia(i) * 8 + 0.5) / 8)
		local seg = Blocks.part(m, { size = Vector3.new(1, 1, 1), cf = f * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color = color(i), shape = "Cylinder", name = name, collide = false })
		seg.Size = Vector3.new((b - a).Magnitude, d, d)
		if i < #pts - 1 or cap then
			local joint = Blocks.part(m, { size = Vector3.new(1, 1, 1), cf = f * CFrame.new(b), color = color(i), shape = "Ball", name = name, collide = false })
			joint.Size = Vector3.new(d, d, d)
		end
	end
end

-- A palm's trunk from its foot up into its crown at (x, top) in f: one smooth curve (upright at the foot, leaning out
-- through the middle, upright again under the crown) in six rings of the two woods in turn, narrowing from w.
local function palmTrunk(m: Instance, f: CFrame, x: number, top: number, w: number)
	local pts: { Vector3 } = {}
	for j = 0, 6 do
		local t = j / 6
		table.insert(pts, Vector3.new(x * (3 * t * t - 2 * t * t * t), top * t, 0))
	end
	tube(m, f, pts, function(i: number): number
		return w * (1 - (i - 1) * 0.055)
	end, function(i: number): string
		return if i % 2 == 1 then "wood" else "wood_dark"
	end, "Trunk")
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


------------------------------------------------------------------ the islands past Driftling Haven (GAME_DESIGN 4.1)
-- The request of 2026-11-14: "allow expansion up to level 20, you can make the previous levels of expansion a bit
-- cheaper too. add decor, huts, work buildings ... and other details as required for this". Our own designs, each a
-- step up from the city's: taller, more of its trade on show, a light or two.

-- A box from a to b (points in f), w wide and h deep, its top facing up: a chute, a cable, a beam on a slant.
local function span(m: Instance, f: CFrame, a: Vector3, b: Vector3, w: number, h: number, color: string, name: string): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, (b - a).Magnitude), cf = f * CFrame.lookAt((a + b) / 2, b), color = color, name = name, collide = false })
end

-- A round door facing +Z (a driftling's): a dark disc in a lighter ring.
local function roundDoor(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?)
	cyl(m, f, x, y, z, dia + 0.25, 0.25, color or "wood", "DoorRing").CFrame = f * CFrame.new(x, y, z) * CFrame.Angles(math.pi / 2, 0, 0)
	cyl(m, f, x, y, z + 0.05, dia, 0.25, "wood_dark", "Door").CFrame = f * CFrame.new(x, y, z + 0.05) * CFrame.Angles(math.pi / 2, 0, 0)
end

-- A mushroom cap of dia at (x, y, z): a wide brim, a dome on it, a pale underside, a white spot or two.
local function cap(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, spots: number)
	cyl(m, f, x, y - 0.2, z, dia * 0.8, 0.25, "cream", "Gills")
	cyl(m, f, x, y, z, dia, 0.25, color, "Cap")
	ball(m, f, x, y + 0.05, z, dia * 0.8, color, "Cap")
	for k = 1, spots do
		local a = k * 2.2
		ball(m, f, x + math.sin(a) * dia * 0.22, y + dia * 0.3, z + math.cos(a) * dia * 0.22, 0.25, "white", "Spot")
	end
end

-- A small tower roof: rings narrowing up to a point, from a base at y.
local function spire(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string)
	local d = dia
	local yy = y
	while d > 0.3 do
		cyl(m, f, x, yy + 0.125, z, d, 0.25, color, "Spire")
		yy += 0.25
		d -= 0.25
	end
	ball(m, f, x, yy + 0.1, z, 0.25, "gold", "Finial")
end

-- Mushroom Cellar (4 x 4): a grassy mound over a stone cellar, its door at the front over a step, giant mushrooms
-- growing out of the roof, baskets of picked ones either side of the door, a lantern.
B.shroomcellar = function(m, f)
	box(m, f, 0, 0.05, 0, 4, 0.1, 4, "grass_dark", "Lawn")
	ball(m, f, 0, 0.1, -0.25, 3.5, "grass", "Mound")
	ball(m, f, -0.75, 0.75, -0.75, 1.75, "grass_dark", "Mound")
	box(m, f, 0, 0.75, 1.25, 2.0, 1.5, 0.5, "rock", "Wall")
	box(m, f, 0, 1.5, 1.3, 2.25, 0.25, 0.5, "rock_dark", "Lintel")
	box(m, f, 0, 0.6, 1.5, 0.75, 1.0, 0.25, "wood_dark", "Door")
	box(m, f, 0.25, 0.6, 1.65, 0.25, 0.25, 0.25, "gold", "Knob")
	box(m, f, 0, 0.12, 1.75, 1.0, 0.25, 0.5, "rock_dark", "Step")
	for k, c in ({ { -0.9, 1.75, 0.0, 1.25, "berry_red" }, { 0.85, 1.6, -0.6, 1.0, "orange" }, { 0.1, 2.0, -1.2, 1.0, "purple" }, { -1.2, 1.4, -1.3, 0.75, "pink" } } :: { { any } }) do
		cyl(m, f, c[1], c[2] / 2 + 0.3, c[3], 0.25 + c[4] * 0.2, c[2] - 0.6, "cream", "Stalk")
		cap(m, f, c[1], c[2], c[3], c[4], c[5], if k % 2 == 1 then 2 else 1)
	end
	for _, x in { -1.4, 1.4 } do
		box(m, f, x, 0.25, 1.6, 0.5, 0.5, 0.5, "straw", "Basket")
		ball(m, f, x - 0.1, 0.55, 1.6, 0.25, "berry_red", "Picked")
		ball(m, f, x + 0.12, 0.55, 1.55, 0.25, "cream", "Picked")
	end
	lamp(m, f, 1.6, 0.75)
end

-- Pearl Beds (5 x 4): a rock-rimmed bed of clear shallow water with rows of oysters, a few open on a glowing pearl, a
-- boardwalk along the front and the diver's hut with a pearl on its roof.
B.pearlbeds = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 4, "sand", "Beach")
	box(m, f, -0.5, 0.12, -0.4, 3.75, 0.25, 3.0, "rock_dark", "Rim")
	box(m, f, -0.5, 0.25, -0.4, 3.5, 0.25, 2.75, "shallow", "Bed"):SetAttribute("PixelWater", 2)
	for r = 0, 2 do
		for k = 0, 4 do
			local x, z = -2.0 + k * 0.75, -1.35 + r * 0.9
			box(m, f, x, 0.35, z, 0.5, 0.25, 0.5, "slate", "Oyster")
			Blocks.part(m, { size = Vector3.new(0.5, 0.25, 0.5), cf = f * CFrame.new(x, 0.6, z - 0.2) * CFrame.Angles(math.rad(-55), 0, 0), color = "rock", name = "Shell", collide = false })
			if (r + k) % 3 == 0 then
				ball(m, f, x, 0.5, z + 0.05, 0.25, "white", "Pearl").Material = Enum.Material.Neon
			end
		end
	end
	box(m, f, -0.5, 0.35, 1.55, 3.75, 0.25, 0.75, "wood", "Boardwalk")
	for _, x in { -2.25, -0.5, 1.25 } do
		box(m, f, x, 0.2, 1.85, 0.25, 0.5, 0.25, "wood_dark", "Post")
	end
	storey(m, f, 1.95, 0.1, -0.7, 0.9, 1.5, 2.0, "cream", "wood_dark")
	roof(m, f * CFrame.new(1.95, 0, -0.7) * CFrame.Angles(0, math.pi / 2, 0), 1.6, 2.0, 0.9, 0.75, "teal", "wood_dark", 0.1)
	door(m, f * CFrame.new(1.95, 0.1, 0), 0, 0.3, 0.5, 1.0, "teal")
	ball(m, f, 1.95, 2.6, -0.7, 0.5, "white", "PearlSign").Material = Enum.Material.Neon
	sack(m, f, 2.0, 0.1, 1.3, "cream")
end

-- Honey Terraces (5 x 5): three stepped beds of flowers climbing toward the back, white hives at each end, bees about
-- them and a table of honey jars at the front.
B.honeyterrace = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "grass_dark", "Lawn")
	local cols = { "pink", "yellow", "purple", "white", "orange" }
	for i = 0, 2 do
		local z, h = 1.5 - i * 1.5, 0.5 + i * 0.5
		box(m, f, 0, (h - 0.25) / 2, z, 5, h - 0.25, 1.5, if i % 2 == 0 then "rock" else "rock_dark", "Terrace")
		box(m, f, 0, h - 0.125, z, 5, 0.25, 1.5, "grass", "Bed")
		for _, dz in (if i == 0 then { -0.35 } else { -0.35, 0.35 }) :: { number } do
			box(m, f, 0, h + 0.05, z + dz, 2.5, 0.25, 0.25, "leaf", "Row")
			for k = 0, 4 do
				ball(m, f, -1.0 + k * 0.5, h + 0.3, z + dz, 0.25, cols[(k + i) % 5 + 1], "Flower")
			end
		end
		for _, x in { -1.75, 1.75 } do
			box(m, f, x, h + 0.375, z, 0.75, 0.75, 0.75, "white", "Hive")
			box(m, f, x, h + 0.5, z, 0.8, 0.25, 0.8, "yellow", "Band")
			box(m, f, x, h + 0.85, z, 1.0, 0.25, 1.0, "wood", "HiveLid")
			box(m, f, x, h + 0.15, z + 0.4, 0.5, 0.25, 0.25, "black", "Entrance")
			ball(m, f, x + 0.5, h + 1.2, z + 0.3, 0.25, "yellow", "Bee")
		end
	end
	box(m, f, 0, 0.75, 1.75, 1.25, 0.25, 0.5, "wood", "Table")
	for _, x in { -0.5, 0.5 } do
		box(m, f, x, 0.5, 1.75, 0.25, 0.5, 0.25, "wood_dark", "Leg")
	end
	for k = 0, 2 do
		cyl(m, f, -0.35 + k * 0.35, 1.0, 1.75, 0.25, 0.25, "gold", "Jar").Material = Enum.Material.Neon
	end
end

-- Grand Vineyard (5 x 5): rows of vines on posts and rails with bunches of grapes under the leaves, the press house at
-- the back with a red roof, barrels either side.
B.vineyard = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "sand_dark", "Soil")
	storey(m, f, 0, 0.1, -1.6, 4.0, 1.75, 1.5, "cream", "rock")
	roof(m, f * CFrame.new(0, 0, -1.6), 1.85, 4.0, 1.5, 0.75, "brick", "wood_dark", 0.2)
	door(m, f * CFrame.new(0, 0.1, 0), 0, -0.85, 0.75, 1.25, "wood_dark")
	window(m, f, -1.25, 1.1, -0.85, 0.5, 0.5)
	window(m, f, 1.25, 1.1, -0.85, 0.5, 0.5)
	for r = 0, 2 do
		local z = 0.15 + r * 0.8
		for _, x in { -2.25, 0, 2.25 } do
			box(m, f, x, 0.5, z, 0.25, 1.0, 0.25, "wood_dark", "Post")
		end
		box(m, f, 0, 0.95, z, 4.5, 0.25, 0.25, "wood", "Rail")
		for k = 0, 7 do
			local x = -1.9 + k * 0.55
			ball(m, f, x, 0.9, z, 0.5, if k % 2 == 0 then "leaf" else "leaf_dark", "Vine")
			if (k + r) % 2 == 0 then
				ball(m, f, x + 0.1, 0.6, z + 0.2, 0.25, "purple", "Grapes")
				ball(m, f, x + 0.1, 0.42, z + 0.2, 0.25, "purple", "Grapes")
			end
		end
	end
	barrel(m, f, -2.15, 0.1, -0.55, 0.6)
	barrel(m, f, 2.15, 0.1, -0.55, 0.6)
end

-- Log Flume (5 x 4): a wooden chute on trestles running from a wooded hill at the back down to a pond at the front,
-- a log riding it and another splashing down, a stack of logs waiting.
B.logflume = function(m, f)
	footing(m, f, 5, 4, "wood_dark", 0.1)
	ball(m, f, -1.4, 0.0, -1.0, 2.0, "grass", "Hill")
	for _, p in { { -1.8, -1.4 }, { -1.0, -1.6 } } do
		cyl(m, f, p[1], 1.2, p[2], 0.25, 1.0, "wood_dark", "Trunk")
		box(m, f, p[1], 1.85, p[2], 0.75, 0.75, 0.75, "leaf_dark", "Pine")
		box(m, f, p[1], 2.35, p[2], 0.5, 0.5, 0.5, "leaf", "Pine")
	end
	local a, b = Vector3.new(-1.3, 1.5, -0.9), Vector3.new(1.3, 0.55, 0.75)
	local cf = CFrame.lookAt((a + b) / 2, b)
	local len = (b - a).Magnitude
	Blocks.part(m, { size = Vector3.new(0.75, 0.25, len), cf = f * cf, color = "wood", name = "Chute", collide = false })
	for _, s in { -1, 1 } do
		Blocks.part(m, { size = Vector3.new(0.25, 0.5, len), cf = f * cf * CFrame.new(s * 0.375, 0.2, 0), color = "wood_dark", name = "ChuteSide", collide = false })
	end
	Blocks.part(m, { size = Vector3.new(0.5, 0.25, len), cf = f * cf * CFrame.new(0, 0.13, 0), color = "water", name = "Water", collide = false }):SetAttribute("PixelWater", 2)
	for k = 1, 3 do
		local p = a:Lerp(b, k / 4)
		box(m, f, p.X, (p.Y - 0.1) / 2, p.Z, 0.25, p.Y - 0.1, 0.25, "wood_dark", "Trestle")
	end
	Blocks.part(m, { size = Vector3.new(0.9, 0.5, 0.5), cf = f * cf * CFrame.new(0, 0.45, -len * 0.15) * CFrame.Angles(0, math.pi / 2, 0), color = "wood", shape = "Cylinder", name = "Log", collide = false })
	box(m, f, 1.6, 0.15, 1.2, 1.75, 0.25, 1.5, "rock", "PondRim")
	box(m, f, 1.6, 0.25, 1.2, 1.5, 0.25, 1.25, "water", "Pond"):SetAttribute("PixelWater", 2)
	ball(m, f, 1.4, 0.45, 1.2, 0.5, "white", "Splash")
	for k = 0, 2 do
		log(m, f, -1.3, 0.35 + (if k == 2 then 0.45 else 0), 1.05 + (if k == 2 then 0.25 else k * 0.5), 1.75, 0.5, if k == 1 then "wood_dark" else "wood")
	end
end

-- Ironwood Yard (5 x 5): a great dark tree at the back and the stump of another, a saw shed with a round blade, dark
-- planks stacked to dry and a derrick lifting a log.
B.ironwood = function(m, f)
	footing(m, f, 5, 5, "rock", 0.15)
	cyl(m, f, -1.5, 1.85, -1.5, 0.75, 3.5, "basalt", "Trunk")
	ball(m, f, -1.5, 4.0, -1.5, 2.0, "leaf_dark", "Crown")
	ball(m, f, -1.0, 3.5, -1.0, 1.25, "swamp", "Crown")
	cyl(m, f, 0.2, 0.4, -1.75, 1.0, 0.5, "basalt", "Stump")
	cyl(m, f, 0.2, 0.67, -1.75, 0.75, 0.25, "wood", "Rings")
	for _, p in { { 0.95, -0.55 }, { 2.25, -0.55 }, { 0.95, -2.05 }, { 2.25, -2.05 } } do
		box(m, f, p[1], 1.1, p[2], 0.25, 1.9, 0.25, "steel_dark", "Post")
	end
	box(m, f, 1.6, 2.1, -1.3, 1.75, 0.25, 2.0, "steel", "Roof")
	box(m, f, 1.6, 0.65, -1.3, 1.25, 0.25, 0.75, "steel_dark", "Bench")
	cyl(m, f, 1.6, 1.0, -1.3, 1.0, 0.25, "steel", "Blade").CFrame = f * CFrame.new(1.6, 1.0, -1.3) * CFrame.Angles(0, 0, math.pi / 2)
	for k = 0, 3 do
		box(m, f, -1.2, 0.3 + k * 0.25, 1.4, 1.75, 0.25, 0.75, if k % 2 == 0 then "basalt" else "wood_dark", "Planks")
		box(m, f, 1.3, 0.3 + k * 0.25, 1.4, 1.5, 0.25, 0.75, if k % 2 == 0 then "wood_dark" else "basalt", "Planks")
	end
	box(m, f, -2.1, 1.6, 0.4, 0.25, 3.0, 0.25, "wood_dark", "Mast")
	box(m, f, -1.35, 3.0, 0.4, 1.75, 0.25, 0.25, "wood_dark", "Boom")
	box(m, f, -0.6, 2.45, 0.4, 0.25, 0.9, 0.25, "straw", "Rope")
	log(m, f, -0.6, 1.85, 0.4, 1.25, 0.5, "basalt")
end

-- Canopy Mill (5 x 5): one huge trunk carrying two round decks, a saw turning in a hut on each, a rope lift hauling a
-- basket of logs, a ladder up the front, the crown over it all and logs piled at its foot.
B.canopymill = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "grass_dark", "Lawn")
	cyl(m, f, 0, 2.6, -0.5, 1.5, 5.0, "wood_dark", "Trunk")
	for k = 0, 3 do
		local a = k * math.pi / 2 + 0.4
		span(m, f, Vector3.new(math.sin(a) * 0.6, 0.5, -0.5 + math.cos(a) * 0.6), Vector3.new(math.sin(a) * 1.4, 0.1, -0.5 + math.cos(a) * 1.4), 0.5, 0.5, "wood_dark", "Root")
	end
	for i, y in { 1.75, 3.5 } do
		local dia = 4.0 - i * 0.5
		cyl(m, f, 0, y, -0.5, dia, 0.25, "wood", "Deck")
		for k = 0, 7 do
			local a = k * math.pi / 4
			box(m, f, math.sin(a) * (dia / 2 - 0.15), y + 0.35, -0.5 + math.cos(a) * (dia / 2 - 0.15), 0.25, 0.5, 0.25, "wood_dark", "Rail")
		end
		box(m, f, 1.0, y + 0.5, -0.5, 0.75, 0.75, 0.75, "wood", "SawHut")
		box(m, f, 1.0, y + 0.95, -0.5, 1.0, 0.25, 1.0, "leaf_dark", "HutRoof")
		cyl(m, f, 1.0, y + 0.5, -0.1, 0.75, 0.25, "steel", "Blade").CFrame = f * CFrame.new(1.0, y + 0.5, -0.05) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	ball(m, f, 0, 5.6, -0.5, 3.25, "leaf", "Crown")
	ball(m, f, -1.0, 5.2, -0.9, 1.75, "leaf_dark", "Crown")
	ball(m, f, 1.0, 5.4, -0.2, 1.75, "leaf_dark", "Crown")
	box(m, f, -1.6, 2.0, 0.5, 0.25, 3.5, 0.25, "straw", "LiftRope")
	box(m, f, -1.6, 0.5, 0.5, 0.75, 0.5, 0.75, "wood", "Basket")
	log(m, f, -1.6, 0.85, 0.5, 0.75, 0.25, "wood")
	for k = 0, 8 do
		box(m, f, 0, 0.4 + k * 0.4, 0.3, 0.5, 0.25, 0.25, "wood", "Rung")
	end
	for k = 0, 2 do
		log(m, f, 0.9, 0.35 + (if k == 2 then 0.45 else 0), 1.6 + (if k == 2 then 0.25 else k * 0.5 - 0.25), 2.0, 0.5, if k == 1 then "wood_dark" else "wood")
	end
end

-- Night Market (5 x 4): three stalls along the back under striped awnings with their goods out, strings of lanterns
-- between four poles, a table and stools in the middle.
B.nightmarket = function(m, f)
	footing(m, f, 5, 4, "pavement", 0.1)
	local goods = { { "orange", "yellow" }, { "berry_red", "green" }, { "pink", "cream" } }
	for k, x in { -1.6, 0, 1.6 } do
		local a = ({ "berry_red", "teal", "purple" })[k]
		box(m, f, x, 0.45, -1.2, 1.25, 0.75, 0.75, "wood", "Counter")
		box(m, f, x, 0.9, -1.2, 1.5, 0.25, 0.75, "wood_dark", "Top")
		for j = 0, 2 do
			ball(m, f, x - 0.4 + j * 0.4, 1.15, -1.15, 0.25, goods[k][j % 2 + 1], "Goods")
		end
		for _, dx in { -0.6, 0.6 } do
			box(m, f, x + dx, 1.1, -1.7, 0.25, 2.0, 0.25, "wood_dark", "Post")
		end
		Blocks.part(m, { size = Vector3.new(1.5, 0.25, 1.25), cf = f * CFrame.new(x, 2.0, -1.2) * CFrame.Angles(math.rad(-14), 0, 0), color = a, name = "Awning", collide = false })
		Blocks.part(m, { size = Vector3.new(0.5, 0.25, 1.25), cf = f * CFrame.new(x, 2.05, -1.2) * CFrame.Angles(math.rad(-14), 0, 0), color = "white", name = "Awning", collide = false })
	end
	for _, x in { -2.3, 2.3 } do
		for _, z in { -0.3, 1.7 } do
			box(m, f, x, 1.2, z, 0.25, 2.4, 0.25, "steel_dark", "Pole")
		end
		box(m, f, x, 2.3, 0.7, 0.25, 0.25, 2.0, "wood_dark", "Line")
		for j = 0, 3 do
			box(m, f, x, 2.0, -0.1 + j * 0.55, 0.25, 0.25, 0.25, ({ "yellow", "orange", "pink", "yellow" })[j + 1], "Lantern", true)
		end
	end
	box(m, f, -0.1, 2.3, 1.7, 4.6, 0.25, 0.25, "wood_dark", "Line")
	for j = 0, 6 do
		box(m, f, -2.0 + j * 0.65, 2.0, 1.7, 0.25, 0.25, 0.25, ({ "orange", "yellow", "pink" })[j % 3 + 1], "Lantern", true)
	end
	box(m, f, 0, 0.6, 0.6, 1.25, 0.25, 0.75, "wood", "Table")
	box(m, f, 0, 0.3, 0.6, 0.25, 0.5, 0.25, "wood_dark", "Leg")
	for _, x in { -1.0, 1.0 } do
		cyl(m, f, x, 0.3, 0.6, 0.5, 0.5, "wood_dark", "Stool")
	end
end

-- Seaside Theatre (5 x 5): a cream hall whose front opens on a stage with red curtains drawn back and footlights, a row
-- of bulbs over it, columns either side, posters, steps up and a lamp each side.
B.theatre = function(m, f)
	footing(m, f, 5, 5, "pavement", 0.15)
	storey(m, f, 0, 0.15, -0.75, 4.5, 3.0, 3.0, "cream", "rock")
	box(m, f, 0, 1.6, 0.78, 2.5, 2.0, 0.25, "black", "Stage")
	box(m, f, 0, 0.62, 0.85, 2.5, 0.25, 0.25, "wood", "StageEdge")
	for _, x in { -1.0, 1.0 } do
		box(m, f, x, 1.6, 0.9, 0.5, 2.0, 0.25, "berry_red", "Curtain")
	end
	box(m, f, 0, 2.75, 0.9, 2.75, 0.5, 0.25, "berry_red", "Valance")
	for k = 0, 4 do
		box(m, f, -1.0 + k * 0.5, 0.8, 1.0, 0.25, 0.25, 0.25, "yellow", "Footlight", true)
		box(m, f, -1.0 + k * 0.5, 3.1, 0.95, 0.25, 0.25, 0.25, "yellow", "Bulb", true)
	end
	flatRoof(m, f, 0, 3.15, -0.75, 4.5, 3.0, "rock_dark", "gold")
	box(m, f, 0, 3.75, 0.6, 2.5, 0.75, 0.25, "cream", "Crest")
	box(m, f, 0, 3.75, 0.75, 1.5, 0.25, 0.25, "gold", "Name")
	box(m, f, 0, 4.25, 0.6, 0.5, 0.25, 0.25, "yellow", "Star", true)
	for _, x in { -1.75, 1.75 } do
		cyl(m, f, x, 1.65, 1.05, 0.5, 3.0, "white", "Column")
		box(m, f, x * 1.17, 1.3, 0.8, 0.5, 0.75, 0.25, if x < 0 then "orange" else "teal", "Poster")
	end
	box(m, f, 0, 0.27, 1.45, 3.0, 0.25, 0.75, "rock", "Step")
	streetLamp(m, f, -2.1, 2.1)
	streetLamp(m, f, 2.1, 2.1)
end

-- Sky Tram (5 x 5): a glass-fronted station with the cable's wheel on its roof, a steel pylon at the back, the cable
-- between them and a red car hanging half way up, a ticket booth.
B.skytram = function(m, f)
	footing(m, f, 5, 5, "pavement", 0.15)
	storey(m, f, -0.9, 0.15, 0.9, 2.75, 1.75, 2.25, "white", "rock_dark")
	window(m, f, -0.9, 1.05, 2.025, 1.75, 0.75)
	flatRoof(m, f, -0.9, 1.9, 0.9, 2.75, 2.25, "teal", "white")
	cyl(m, f, -0.9, 2.4, 0.9, 1.25, 0.25, "steel_dark", "Wheel")
	for _, p in { { 1.4, -1.4 }, { 2.1, -1.4 }, { 1.4, -2.1 }, { 2.1, -2.1 } } do
		box(m, f, p[1], 3.1, p[2], 0.25, 6.0, 0.25, "steel", "Leg")
	end
	for _, y in { 1.5, 3.0, 4.5 } do
		box(m, f, 1.75, y, -1.4, 0.75, 0.25, 0.25, "steel_dark", "Brace")
		box(m, f, 1.75, y, -2.1, 0.75, 0.25, 0.25, "steel_dark", "Brace")
	end
	box(m, f, 1.75, 6.15, -1.75, 1.25, 0.25, 1.0, "steel_dark", "Arm")
	local a, b = Vector3.new(-0.9, 2.6, 0.9), Vector3.new(1.75, 6.35, -1.75)
	span(m, f, a, b, 0.25, 0.25, "black", "Cable")
	local c = a:Lerp(b, 0.55)
	box(m, f, c.X, c.Y - 0.4, c.Z, 0.25, 0.75, 0.25, "steel_dark", "Hanger")
	box(m, f, c.X, c.Y - 0.85, c.Z, 1.25, 0.25, 0.75, "white", "CarRoof")
	box(m, f, c.X, c.Y - 1.35, c.Z, 1.0, 0.75, 0.75, "berry_red", "Car")
	box(m, f, c.X, c.Y - 1.25, c.Z + 0.4, 0.75, 0.25, 0.25, "window", "CarWindow")
	box(m, f, 1.6, 0.65, 1.6, 0.75, 1.0, 0.75, "berry_red", "Booth")
	box(m, f, 1.6, 1.25, 1.6, 1.0, 0.25, 1.0, "white", "BoothRoof")
	box(m, f, 1.6, 0.85, 2.0, 0.5, 0.25, 0.25, "window", "BoothWindow")
end

-- Seed Vault (3 x 3): a stone door into a grassy mound, a round steel hatch with a wheel, a frosty light over it, sacks
-- of seed either side and a sprout on top.
B.seedvault = function(m, f)
	box(m, f, 0, 0.05, 0, 3, 0.1, 3, "grass_dark", "Lawn")
	ball(m, f, 0, 0.0, -0.4, 2.75, "grass", "Mound")
	box(m, f, 0, 0.75, 0.75, 2.0, 1.5, 0.5, "slate", "Face")
	cyl(m, f, 0, 0.75, 1.05, 1.0, 0.25, "steel", "Hatch").CFrame = f * CFrame.new(0, 0.75, 1.05) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, 0, 0.75, 1.2, 0.75, 0.25, 0.25, "steel_dark", "Wheel")
	box(m, f, 0, 0.75, 1.2, 0.25, 0.75, 0.25, "steel_dark", "Wheel")
	box(m, f, 0, 1.65, 1.0, 0.5, 0.25, 0.25, "ice", "Frost", true)
	sack(m, f, -1.15, 0, 1.2, "cream")
	sack(m, f, 1.15, 0, 1.2, "sand_dark")
	box(m, f, 0, 1.5, -0.4, 0.25, 0.5, 0.25, "leaf_dark", "Sprout")
	ball(m, f, -0.2, 1.75, -0.4, 0.5, "leaf", "Leaf")
	ball(m, f, 0.2, 1.85, -0.4, 0.5, "green", "Leaf")
end

-- Carpenters' Hall (4 x 3): a timber-framed hall, dark beams on cream walls, a board with a saw over the door, a
-- chimney, a workbench with planks out front.
B.guildhall = function(m, f)
	footing(m, f, 4, 3, "rock", 0.15)
	storey(m, f, 0, 0.15, -0.4, 3.5, 2.0, 2.0, "cream", "rock_dark")
	for _, x in { -1.65, -0.6, 0.6, 1.65 } do
		box(m, f, x, 1.15, 0.63, 0.25, 2.0, 0.25, "wood_dark", "Beam")
	end
	box(m, f, 0, 2.05, 0.63, 3.5, 0.25, 0.25, "wood_dark", "Beam")
	for _, s in { -1, 1 } do
		Blocks.part(m, { size = Vector3.new(0.25, 1.25, 0.25), cf = f * CFrame.new(s * 1.12, 1.6, 0.66) * CFrame.Angles(0, 0, s * math.rad(40)), color = "wood_dark", name = "Brace", collide = false })
	end
	window(m, f, -1.12, 1.0, 0.6, 0.5, 0.5)
	window(m, f, 1.12, 1.0, 0.6, 0.5, 0.5)
	door(m, f * CFrame.new(0, 0.15, 0), 0, 0.6, 0.75, 1.25, "wood_dark")
	roof(m, f * CFrame.new(0, 0, -0.4), 2.15, 3.5, 2.0, 1.0, "wood_dark", "wood", 0.25)
	box(m, f, 1.2, 3.0, -0.9, 0.5, 1.0, 0.5, "brick", "Chimney")
	box(m, f, 0, 1.75, 0.8, 1.0, 0.5, 0.25, "wood", "Board")
	cyl(m, f, 0, 1.75, 0.95, 0.5, 0.25, "steel", "Saw").CFrame = f * CFrame.new(0, 1.75, 0.95) * CFrame.Angles(math.pi / 2, 0, 0)
	box(m, f, 1.3, 0.6, 1.1, 1.0, 0.25, 0.5, "wood", "Bench")
	for _, x in { 0.9, 1.7 } do
		box(m, f, x, 0.3, 1.1, 0.25, 0.5, 0.25, "wood_dark", "Leg")
	end
	for k = 0, 2 do
		box(m, f, -1.3, 0.3 + k * 0.25, 1.1, 1.25, 0.25, 0.5, if k % 2 == 0 then "wood" else "sand_dark", "Planks")
	end
end

-- Trade Hall (4 x 4): a brick hall with three tall doorways and a cream cornice, flags of far ports on its roof, crates,
-- a sack and a barrel out front.
B.tradehall = function(m, f)
	footing(m, f, 4, 4, "pavement", 0.15)
	storey(m, f, 0, 0.15, -0.5, 3.5, 2.25, 2.5, "brick", "rock_dark")
	for _, x in { -1.1, 0, 1.1 } do
		box(m, f, x, 0.95, 0.78, 0.75, 1.5, 0.25, "black", "Doorway")
		box(m, f, x, 1.8, 0.8, 0.75, 0.25, 0.25, "cream", "Arch")
	end
	box(m, f, 0, 2.45, 0.8, 3.75, 0.25, 0.25, "cream", "Cornice")
	flatRoof(m, f, 0, 2.4, -0.5, 3.5, 2.5, "rock_dark", "cream")
	for k, x in { -1.2, 0, 1.2 } do
		box(m, f, x, 3.25, -1.2, 0.25, 1.25, 0.25, "steel_dark", "FlagPole")
		wedge(m, f, x + 0.35, 3.6, -1.2, 0.5, 0.5, 0.25, ({ "teal", "orange", "purple" })[k], math.pi / 2, "Flag")
	end
	crate(m, f, -1.4, 0.15, 1.35, 0.5)
	crate(m, f, -1.4, 0.65, 1.35, 0.5)
	crate(m, f, -0.8, 0.15, 1.45, 0.5)
	sack(m, f, 0.9, 0.15, 1.4, "sand_dark")
	barrel(m, f, 1.55, 0.15, 1.4, 0.75)
end

-- Tide Bell (3 x 3): two white pillars on steps carrying a beam and a small teal roof, a gold bell hung between them,
-- a wave of light along the front step.
B.tidebell = function(m, f)
	box(m, f, 0, 0.12, 0, 3, 0.25, 3, "white", "Step")
	box(m, f, 0, 0.37, 0, 2.5, 0.25, 2.5, "cream", "Step")
	for _, x in { -0.9, 0.9 } do
		box(m, f, x, 0.62, 0, 0.75, 0.25, 0.75, "teal", "Base")
		box(m, f, x, 2.1, 0, 0.5, 2.75, 0.5, "white", "Pillar")
		box(m, f, x, 3.55, 0, 0.75, 0.25, 0.75, "teal", "Capital")
	end
	box(m, f, 0, 3.8, 0, 2.5, 0.25, 0.75, "white", "Beam")
	wedge(m, f, 0, 4.15, -0.2, 2.75, 0.5, 0.5, "teal", 0, "Roof")
	wedge(m, f, 0, 4.15, 0.2, 2.75, 0.5, 0.5, "teal", math.pi, "Roof")
	box(m, f, 0, 3.45, 0, 0.25, 0.5, 0.25, "steel_dark", "Yoke")
	ball(m, f, 0, 2.85, 0, 1.0, "gold", "Bell")
	cyl(m, f, 0, 2.45, 0, 1.25, 0.25, "gold", "Lip")
	box(m, f, 0, 2.1, 0, 0.25, 0.5, 0.25, "steel_dark", "Clapper")
	for k = 0, 6 do
		box(m, f, -1.05 + k * 0.35, 0.3 + (if k % 2 == 0 then 0 else 0.1), 1.4, 0.25, 0.25, 0.25, "shallow", "Wave", true)
	end
end

-- Lighthouse Loft (5 x 5): a striped round tower of bunks with round windows and a little driftling door, a lit lamp
-- room and a gallery on top, a cottage beside it and flowers at the door.
B.loft = function(m, f)
	box(m, f, 0, 0.05, 0, 5, 0.1, 5, "grass_dark", "Lawn")
	cyl(m, f, -0.6, 0.15, -0.6, 2.75, 0.25, "rock", "Base")
	for i = 0, 5 do
		cyl(m, f, -0.6, 0.65 + i * 0.75, -0.6, 2.25, 0.75, if i % 2 == 0 then "white" else "berry_red", "Tower")
	end
	for i = 1, 4 do
		local x = -0.6 + (if i % 2 == 0 then 0.35 else -0.35)
		cyl(m, f, x, 0.65 + i * 0.75, 0.5, 0.5, 0.25, "window", "Porthole").CFrame = f * CFrame.new(x, 0.65 + i * 0.75, 0.5) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	roundDoor(m, f, -0.6, 0.65, 0.5, 0.75)
	cyl(m, f, -0.6, 4.9, -0.6, 2.75, 0.25, "steel_dark", "Gallery")
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(m, f, -0.6 + math.sin(a) * 1.25, 5.2, -0.6 + math.cos(a) * 1.25, 0.25, 0.5, 0.25, "steel_dark", "Rail")
	end
	cyl(m, f, -0.6, 5.4, -0.6, 1.25, 0.75, "yellow", "Lamp").Material = Enum.Material.Neon
	cyl(m, f, -0.6, 5.85, -0.6, 1.5, 0.25, "steel_dark", "LampCap")
	ball(m, f, -0.6, 6.0, -0.6, 1.0, "berry_red", "Dome")
	storey(m, f, 1.35, 0.15, 0.8, 2.0, 1.5, 2.0, "cream", "rock_dark")
	roof(m, f * CFrame.new(1.35, 0, 0.8) * CFrame.Angles(0, math.pi / 2, 0), 1.65, 2.0, 2.0, 0.75, "teal", "wood_dark", 0.15)
	door(m, f * CFrame.new(1.35, 0.15, 0), 0, 1.8, 0.6, 1.0, "teal")
	sideWindow(m, f, 2.35, 1.0, 0.8, 0.5, 0.5)
	pot(m, f, -2.0, 0.1, 1.8, "pink")
	pot(m, f, 0.6, 0.1, 2.1, "yellow")
end

-- Coral Manor (5 x 5): pink and coral stone wings round a warm pool in the courtyard, round doors on the back wing,
-- coral towers at the back corners and a gate of two posts with shells on top.
B.coralmanor = function(m, f)
	footing(m, f, 5, 5, "sand", 0.15)
	storey(m, f, 0, 0.15, -1.6, 4.5, 2.0, 1.25, "coral", "white")
	flatRoof(m, f, 0, 2.15, -1.6, 4.5, 1.25, "pink", "white")
	for _, s in { -1, 1 } do
		storey(m, f, s * 1.75, 0.15, 0.4, 1.0, 1.5, 2.75, "pink", "white")
		flatRoof(m, f, s * 1.75, 1.65, 0.4, 1.0, 2.75, "coral", "white")
		cyl(m, f, s * 1.95, 1.65, -1.95, 0.75, 3.0, "coral", "Tower")
		ball(m, f, s * 1.95, 3.3, -1.95, 0.75, "pink", "TowerTop")
		box(m, f, s * 1.25, 0.85, 0.4, 0.25, 0.75, 0.5, "window", "Glass")
		box(m, f, s * 0.9, 0.5, 2.2, 0.25, 0.75, 0.25, "white", "GatePost")
		ball(m, f, s * 0.9, 1.0, 2.2, 0.5, "cream", "Shell")
	end
	box(m, f, 0, 0.25, 0.3, 2.25, 0.25, 2.0, "rock", "PoolRim")
	box(m, f, 0, 0.35, 0.3, 1.75, 0.25, 1.5, "shallow", "Pool"):SetAttribute("PixelWater", 2)
	ball(m, f, -0.3, 0.75, 0.2, 0.5, "white", "Steam")
	ball(m, f, 0.3, 1.0, 0.5, 0.25, "white", "Steam")
	for i, x in { -1.25, 0, 1.25 } do
		roundDoor(m, f, x, 0.15 + (0.25 + i * 0.1), -0.95, 0.5 + (if i == 2 then 0.25 else 0), "white")
		window(m, f, x, 1.6, -0.97, 0.5, 0.5, "white")
	end
end

-- Cloud Keep (6 x 5): a white keep with a turret and two side towers with stepped blue roofs, bridges joining them,
-- puffs of cloud round their middles, round doors at the front.
B.cloudkeep = function(m, f)
	box(m, f, 0, 0.05, 0, 6, 0.1, 5, "grass_dark", "Lawn")
	storey(m, f, 0, 0.1, -0.6, 2.5, 3.0, 2.5, "white", "slate")
	flatRoof(m, f, 0, 3.1, -0.6, 2.5, 2.5, "blue", "white")
	cyl(m, f, 0, 4.0, -0.6, 1.0, 1.5, "white", "Turret")
	spire(m, f, 0, 4.75, -0.6, 1.25, "blue")
	for _, s in { -1, 1 } do
		cyl(m, f, s * 2.2, 1.85, -0.4, 1.25, 3.5, "white", "Tower")
		spire(m, f, s * 2.2, 3.6, -0.4, 1.5, "blue")
		box(m, f, s * 1.7, 2.5, -0.4, 1.0, 0.25, 0.75, "wood", "Bridge")
		window(m, f, s * 2.2, 2.6, 0.25, 0.25, 0.5)
		for k = 0, 2 do
			local a = k * 2.1 + (if s > 0 then 1 else 0)
			ball(m, f, s * 2.2 + math.sin(a) * 0.55, 1.4 + k * 0.15, -0.4 + math.cos(a) * 0.55, 0.75, if k % 2 == 0 then "white" else "ice", "Cloud")
		end
	end
	for k, c in { { -1.0, 1.2, 0.7 }, { 0.0, 1.6, 0.8 }, { 1.0, 1.3, 0.7 }, { -0.8, 2.6, -1.9 }, { 0.9, 2.4, -1.9 } } do
		ball(m, f, c[1], c[2], c[3], if k % 2 == 0 then 1.0 else 0.75, if k % 2 == 0 then "white" else "ice", "Cloud")
	end
	roundDoor(m, f, -0.5, 0.55, 0.65, 0.75, "blue")
	roundDoor(m, f, 0.55, 0.45, 0.65, 0.5, "blue")
	box(m, f, 0, 0.12, 1.25, 1.75, 0.25, 0.75, "slate", "Step")
end

-- Driftling Citadel (6 x 6): a wall round three sides with a gate in the front, a tower at each corner, the great hall
-- in the middle under a teal dome with a gold spire, banners on the towers and a little fountain in the court.
B.citadel = function(m, f)
	footing(m, f, 6, 6, "rock", 0.15)
	box(m, f, 0, 0.17, 0.4, 4.75, 0.1, 4.0, "grass", "Court")
	local function wall(x: number, z: number, w: number, d: number)
		box(m, f, x, 0.8, z, w, 1.25, d, "cream", "Wall")
		local n = math.floor(math.max(w, d) / 0.5)
		for k = 0, n - 1, 2 do
			local t = -math.max(w, d) / 2 + 0.25 + k * 0.5
			box(m, f, x + (if w > d then t else 0), 1.55, z + (if w > d then 0 else t), 0.25, 0.25, 0.25, "cream", "Merlon")
		end
	end
	wall(0, -2.6, 4.5, 0.5)
	wall(-2.6, 0, 0.5, 4.5)
	wall(2.6, 0, 0.5, 4.5)
	wall(-1.65, 2.6, 1.75, 0.5)
	wall(1.65, 2.6, 1.75, 0.5)
	box(m, f, 0, 1.6, 2.6, 1.5, 0.5, 0.5, "cream", "GateTop")
	box(m, f, 0, 0.7, 2.7, 1.25, 1.25, 0.25, "black", "Gate")
	for k = 0, 3 do
		box(m, f, -0.45 + k * 0.3, 0.7, 2.85, 0.25, 1.25, 0.25, "steel_dark", "Bar")
	end
	for _, c in { { -2.5, -2.5 }, { 2.5, -2.5 }, { -2.5, 2.5 }, { 2.5, 2.5 } } do
		cyl(m, f, c[1], 1.4, c[2], 1.0, 2.5, "cream", "Tower")
		cyl(m, f, c[1], 2.75, c[2], 1.25, 0.25, "teal", "TowerTop")
		spire(m, f, c[1], 2.85, c[2], 1.0, "teal")
		box(m, f, c[1], 3.95, c[2], 0.25, 0.75, 0.25, "steel_dark", "Pole")
		wedge(m, f, c[1] + 0.3, 4.1, c[2], 0.5, 0.5, 0.25, "berry_red", math.pi / 2, "Banner")
	end
	storey(m, f, 0, 0.15, -1.0, 3.0, 2.5, 2.25, "white", "gold")
	ball(m, f, 0, 3.0, -1.0, 2.25, "teal", "Dome")
	box(m, f, 0, 4.25, -1.0, 0.25, 0.75, 0.25, "gold", "Spire")
	ball(m, f, 0, 4.7, -1.0, 0.25, "gold", "Finial")
	roundDoor(m, f, 0, 0.75, 0.15, 1.0, "gold")
	for _, x in { -1.0, 1.0 } do
		window(m, f, x, 1.5, 0.15, 0.5, 0.75, "gold")
		roundDoor(m, f, x, 0.45, 0.15, 0.5, "gold")
	end
	cyl(m, f, 0, 0.3, 1.5, 1.0, 0.25, "rock", "FountainRim")
	cyl(m, f, 0, 0.4, 1.5, 0.75, 0.25, "shallow", "Fountain"):SetAttribute("PixelWater", 2)
	box(m, f, 0, 0.7, 1.5, 0.25, 0.5, 0.25, "white", "Jet")
end

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
