--!strict
-- The island's farms (kind "farm": what grows or is caught to sell), from parts (GAME_DESIGN 4; Data/Buildings). Each
-- builder takes the model, the frame at the footprint's centre on the grass (facing +Z before the piece's turn) and the
-- level, and stays inside the footprint. The pieces they share are Models/BuildKit's; the few only the farms use (a
-- shingled roof, crates, lanterns, rods) are below. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.", then rebuilt with the bakery's care: trims, frames, sills, signs,
-- lamps and the tools of each trade.)
-- The camera looks from the south-east, so the front (+Z) and east (+X) faces and the roofs carry the detail. The
-- back-left corner stays low (an upgraded building's pennant pole stands there) and so does the front-right one where
-- it can (a level 3 building's lantern).
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local log = K.log
local wedge = K.wedge
local sack = K.sack

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

local PI = math.pi

-- A decal's centre on a face at `face` (s = 1 on a +Z or +X face, -1 on a -Z or -X one): a quarter-stud part sunk in
-- the face with its outer side a little proud, so the two never share a plane.
local function on(face: number, s: number?): number
	return face - (s or 1) * 0.08
end

-- A part at `cf` in f (any turn).
local function put(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string, shape: ("Block" | "Wedge" | "Cylinder" | "Ball")?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, name = name, shape = shape, collide = false })
end

-- A cylinder along Z (a log end on, a porthole, a wheel): dia across, len deep.
local function rodZ(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, len: number, color: string, name: string): BasePart
	return put(m, f, CFrame.new(x, y, z) * CFrame.Angles(0, PI / 2, 0), len, dia, dia, color, name, "Cylinder")
end

-- A shingled gable roof along X over a w x d box whose top is at y in frame c (c on the box's centre at the ground):
-- the gable ends in the wall colour, each slope in rows of two colours (every other row a little proud, so the rows
-- read), bargeboards along the gable ends and a ridge cap. `over` is the eaves' overhang, `side` the gable ends'.
-- d / 2 and h are whole quarter studs.
local function gable(m: Instance, c: CFrame, y: number, w: number, d: number, h: number, a: string, b: string, trim: string, wall: string?, over: number?, side: number?)
	local o = over or 0.25
	local W = w + 2 * (side or 0.125)
	if wall then
		wedge(m, c, 0, y + h / 2, -d / 4, w, h, d / 2, wall, 0, "Gable")
		wedge(m, c, 0, y + h / 2, d / 4, w, h, d / 2, wall, PI, "Gable")
	end
	local run = d / 2 + o
	local rise = h * run / (d / 2)
	local len = math.sqrt(run * run + rise * rise)
	local tilt = math.atan2(rise, run)
	local n = math.max(2, math.ceil(len / 0.5 - 0.01))
	local step = (len - 0.5) / (n - 1)
	for _, s in { 1, -1 } do
		local rot = CFrame.Angles(s * tilt, 0, 0)
		local eave = Vector3.new(0, y + h - rise, s * run)
		local up = Vector3.new(0, rise, -s * run) / len
		local nrm = Vector3.new(0, run, s * rise) / len
		for i = 0, n - 1 do
			local p = eave + up * (step * i + 0.25) + nrm * (if i % 2 == 0 then 0.155 else 0.215)
			put(m, c, CFrame.new(p) * rot, W, 0.25, 0.5, if i % 2 == 0 then a else b, "Roof")
		end
		for _, x in { -W / 2, W / 2 } do
			put(m, c, CFrame.new(eave + up * (len / 2) + nrm * 0.215 + Vector3.new(x, 0, 0)) * rot, 0.25, 0.25, len, trim, "Barge")
		end
	end
	box(m, c, 0, y + h + 0.25, 0, W + 0.25, 0.25, 0.5, trim, "Ridge")
end

-- A crate s on a side standing on y0 at (x, z): a dark frame round pale boards on the faces that show, and what it
-- holds heaped on top (a ball for each colour).
local function crate(m: Instance, f: CFrame, x: number, y0: number, z: number, s: number, fill: { string }?)
	box(m, f, x, y0 + s / 2, z, s, s, s, "wood_dark", "Crate")
	box(m, f, x, y0 + s / 2, on(z + s / 2), s - 0.25, s - 0.25, 0.25, "wood", "Board")
	box(m, f, on(x + s / 2), y0 + s / 2, z, 0.25, s - 0.25, s - 0.25, "wood", "Board")
	if fill then
		local n = #fill
		for i, c in fill do
			local t = if n == 1 then 0 else (i - 1) / (n - 1) - 0.5
			ball(m, f, x + t * (s - 0.25), y0 + s, z + (if i % 2 == 0 then -0.06 else 0.06), 0.25, c, "Produce")
		end
	end
end

-- A small lantern standing on y0: a dark foot, the lit glass, a dark cap.
local function lantern(m: Instance, f: CFrame, x: number, y0: number, z: number)
	box(m, f, x, y0 + 0.125, z, 0.25, 0.25, 0.25, "black", "LanternFoot")
	box(m, f, x, y0 + 0.375, z, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, x, y0 + 0.625, z, 0.25, 0.25, 0.25, "black", "LanternCap")
end

-- A flower tuft on the grass: a ball of leaves and a bloom on top.
local function tuft(m: Instance, f: CFrame, x: number, z: number, bloom: string, leaf: string?)
	ball(m, f, x, 0.125, z, 0.5, leaf or "leaf", "Tuft")
	box(m, f, x + 0.06, 0.375, z + 0.06, 0.25, 0.25, 0.25, bloom, "Bloom")
end

-- Veggie Patch (3 x 3): a raised bed of two-tone planks with dark corner posts, furrows of earth, a row of staked
-- tomatoes at the back, cabbages in the middle and carrots in front. A scarecrow in a red shirt and a straw hat stands
-- beside the bed with a bluebird on his hand, a spade stuck in the ground near him. In front: a carrot sign, stepping
-- stones, a blue watering can, a crate of picked veg and a sack of seed.
B.patch = function(m, f)
	-- the bed (x -1.25 .. 0.75, z -1.25 .. 0.5): two planks on the sides that show, one on the others
	for k, c in { "wood_dark", "wood" } do
		local y = -0.125 + k * 0.25
		box(m, f, -0.25, y, 0.375, 2.0, 0.25, 0.25, c, "Plank")
		box(m, f, 0.625, y, -0.375, 0.25, 0.25, 1.25, c, "Plank")
	end
	box(m, f, -0.25, 0.25, -1.125, 2.0, 0.5, 0.25, "wood", "Plank")
	box(m, f, -1.125, 0.25, -0.375, 0.25, 0.5, 1.25, "wood", "Plank")
	for _, p in { { -1.125, 0.375 }, { 0.625, 0.375 }, { 0.625, -1.125 } } do
		box(m, f, p[1], 0.375, p[2], 0.25, 0.75, 0.25, "wood_dark", "BedPost")
	end
	box(m, f, -0.25, 0.25, -0.375, 1.5, 0.25, 1.25, "hair_brown", "Soil")
	for _, z in { -0.75, -0.375, 0.0 } do
		box(m, f, -0.25, 0.375, z, 1.5, 0.25, 0.25, "wood_dark", "Furrow")
	end
	-- tomatoes on stakes at the back
	for _, x in { -0.625, 0.125 } do
		local z = -0.75
		box(m, f, x + 0.125, 0.875, z - 0.125, 0.25, 0.75, 0.25, "wood", "Stake")
		ball(m, f, x, 0.875, z, 0.5, "leaf_dark", "Vine")
		ball(m, f, x + 0.19, 0.75, z + 0.19, 0.25, "berry_red", "Tomato")
		ball(m, f, x - 0.125, 1.0, z + 0.19, 0.25, "berry_red", "Tomato")
		ball(m, f, x + 0.19, 1.06, z + 0.06, 0.25, "orange", "Tomato")
	end
	-- cabbages
	for k, x in { -0.75, -0.25, 0.25 } do
		local z = -0.375
		put(m, f, CFrame.new(x, 0.625, z) * CFrame.Angles(0, PI / 4 + k * 0.3, 0), 0.5, 0.25, 0.5, "leaf_dark", "CabbageLeaf")
		ball(m, f, x, 0.75, z, 0.5, "screen_code", "Cabbage")
	end
	-- carrots: an orange shoulder out of the earth, two leaves
	for _, x in { -0.75, -0.25, 0.25 } do
		box(m, f, x, 0.5, 0.0, 0.25, 0.25, 0.25, "orange", "Carrot")
		put(m, f, CFrame.new(x - 0.06, 0.875, 0.0) * CFrame.Angles(0, 0, 0.3), 0.25, 0.5, 0.25, "leaf", "CarrotTop")
		put(m, f, CFrame.new(x + 0.06, 0.875, 0.06) * CFrame.Angles(0, 0, -0.3), 0.25, 0.5, 0.25, "leaf_dark", "CarrotTop")
	end
	-- the scarecrow beside the bed, turned a little toward the view
	local sc = f * CFrame.new(0.95, 0, -0.875) * CFrame.Angles(0, 0.35, 0)
	box(m, sc, 0, 0.5, 0, 0.25, 1.0, 0.25, "wood_dark", "Post")
	box(m, sc, 0, 0.75, 0, 0.5, 0.25, 0.25, "jeans", "Trousers")
	box(m, sc, 0, 1.125, 0, 0.5, 0.5, 0.25, "berry_red", "Shirt")
	box(m, sc, 0, 1.375, 0, 0.5, 0.25, 0.25, "berry_red", "Sleeves")
	box(m, sc, 0.125, 1.125, on(0.125), 0.25, 0.25, 0.25, "yellow", "Patch")
	for _, x in { -0.375, 0.375 } do
		box(m, sc, x, 1.375, 0, 0.25, 0.25, 0.25, "straw", "Hand")
	end
	box(m, sc, 0, 1.75, 0, 0.5, 0.5, 0.5, "cream", "Head")
	box(m, sc, 0, 1.75, on(0.25), 0.25, 0.25, 0.25, "orange", "Nose")
	box(m, sc, 0, 2.125, 0, 0.75, 0.25, 0.75, "straw", "HatBrim")
	box(m, sc, 0, 2.375, 0, 0.5, 0.25, 0.5, "straw", "Hat")
	box(m, sc, 0, 2.375, on(0.25), 0.5, 0.25, 0.25, "berry_red", "HatBand")
	box(m, sc, 0.375, 1.625, 0, 0.25, 0.25, 0.25, "blue", "Bird")
	-- a spade stuck in the ground
	local sp = f * CFrame.new(1.125, 0, -0.125) * CFrame.Angles(-0.2, 0, 0.1)
	box(m, sp, 0, 0.125, 0, 0.5, 0.5, 0.25, "steel", "Blade")
	box(m, sp, 0, 0.75, 0, 0.25, 0.75, 0.25, "wood", "Handle")
	box(m, sp, 0, 1.125, 0, 0.5, 0.25, 0.25, "wood_dark", "Grip")
	-- the carrot sign, the stepping stones, the flowers
	box(m, f, -1.125, 0.5, 0.875, 0.25, 1.0, 0.25, "wood_dark", "SignPost")
	box(m, f, -1.125, 1.0, 1.0, 0.75, 0.75, 0.25, "cream", "Sign")
	box(m, f, -1.125, 0.875, on(1.125), 0.25, 0.25, 0.25, "orange", "SignCarrot")
	box(m, f, -1.125, 1.125, on(1.125), 0.25, 0.25, 0.25, "leaf_dark", "SignLeaf")
	box(m, f, -0.25, 0.0, 0.875, 0.5, 0.25, 0.5, "rock", "Stone")
	box(m, f, -0.5, 0.0, 1.25, 0.5, 0.25, 0.5, "pavement", "Stone")
	tuft(m, f, -0.875, 1.25, "pink")
	-- the watering can
	cyl(m, f, 0.25, 0.25, 1.25, 0.5, 0.5, "blue", "Can")
	box(m, f, 0.125, 0.625, 1.25, 0.5, 0.25, 0.25, "blue", "CanHandle")
	put(m, f, CFrame.new(0.625, 0.375, 1.25) * CFrame.Angles(0, 0, 0.7), 0.5, 0.25, 0.25, "blue", "Spout")
	ball(m, f, 0.81, 0.56, 1.25, 0.25, "steel", "Rose")
	-- picked veg in a crate, a sack of seed
	crate(m, f, 0.75, 0, 0.875, 0.5, { "orange", "green", "berry_red" })
	sack(m, f, 1.25, 0, 0.375, "cream")
end

-- Fishing Pier (3 x 3): a pond edged in stones at the front with lily pads and a duck on it; behind it a deck of
-- two-tone boards on stilts reaching out over the water, a ladder down into it. On the deck stands a blue fishing shack
-- with white corners and skirting, a red shingled roof with a stove pipe, a porthole, a plank door and a fish on its
-- gable. A rod leans out from the deck over a red float; a rail with a lantern on its post and a pail of the catch.
B.pier = function(m, f)
	-- the pond
	box(m, f, 0, 0, 0.5, 2.75, 0.25, 1.75, "sand_dark", "Bank")
	box(m, f, 0, 0.125, 0.5, 2.25, 0.25, 1.25, "water", "Pond"):SetAttribute("PixelWater", 2)
	for k, x in { -1.0, -0.5, 0.0, 0.5 } do
		box(m, f, x, 0.25, 1.25, 0.5, 0.25, 0.25, if k % 2 == 0 then "rock" else "rock_dark", "Edge")
	end
	for k, z in { 0.0, 0.5 } do
		box(m, f, 1.25, 0.25, z, 0.25, 0.25, 0.5, if k % 2 == 0 then "rock_dark" else "rock", "Edge")
		box(m, f, -1.25, 0.25, z + 0.25, 0.25, 0.25, 0.5, if k % 2 == 0 then "rock" else "rock_dark", "Edge")
	end
	ball(m, f, 1.125, 0.25, 1.125, 0.5, "rock", "Rock")
	cyl(m, f, 0.375, 0.25, 0.875, 0.5, 0.25, "leaf", "LilyPad")
	cyl(m, f, 0.25, 0.25, 0.5, 0.5, 0.25, "leaf_dark", "LilyPad")
	box(m, f, 0.44, 0.375, 0.875, 0.25, 0.25, 0.25, "pink", "Lily")
	ball(m, f, 0.75, 0.25, 0.75, 0.25, "berry_red", "Float")
	-- a duck
	box(m, f, -0.5, 0.375, 0.75, 0.5, 0.25, 0.25, "white", "Duck")
	box(m, f, -0.375, 0.625, 0.75, 0.25, 0.25, 0.25, "white", "DuckHead")
	box(m, f, -0.125, 0.625, 0.75, 0.25, 0.25, 0.25, "orange", "Beak")
	box(m, f, -0.75, 0.5, 0.75, 0.25, 0.25, 0.25, "white", "DuckTail")
	-- the deck on stilts (x -0.875 .. 1.375, z -1.375 .. 0.375), boards running front to back
	for _, p in { { -0.75, -1.25 }, { 1.125, -1.25 }, { -0.625, 0.25 }, { 0.375, 0.25 }, { 1.125, 0.25 } } do
		box(m, f, p[1], 0.25, p[2], 0.25, 0.5, 0.25, "wood_dark", "Stilt")
	end
	for i = 0, 8 do
		box(m, f, -0.75 + i * 0.25, 0.625, -0.5, 0.25, 0.25, 1.75, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	for _, x in { 0.625, 1.125 } do
		box(m, f, x, 0.375, 0.5, 0.25, 0.75, 0.25, "wood", "LadderRail")
	end
	box(m, f, 0.875, 0.5, 0.5, 0.25, 0.25, 0.25, "wood_dark", "Rung")
	-- the shack (x -0.625 .. 1.125, z -1.25 .. -0.25)
	box(m, f, 0.25, 1.375, -0.625, 1.75, 1.25, 1.0, "blue", "Walls")
	for _, p in { { -0.625, -0.125 }, { 1.125, -0.125 }, { 1.125, -1.125 } } do
		box(m, f, p[1], 1.375, p[2], 0.25, 1.25, 0.25, "white", "Corner")
	end
	box(m, f, 0.25, 0.875, on(-0.125), 1.5, 0.25, 0.25, "white", "Skirt")
	-- the door, the porthole, the side window
	box(m, f, 0.625, 1.25, on(-0.125), 0.75, 1.0, 0.25, "white", "DoorFrame")
	box(m, f, 0.625, 1.25, 0.0, 0.5, 0.75, 0.25, "wood", "Door")
	box(m, f, 0.75, 1.25, on(0.125), 0.25, 0.25, 0.25, "gold", "Knob")
	rodZ(m, f, -0.125, 1.5, on(-0.125), 0.75, 0.25, "white", "Porthole")
	rodZ(m, f, -0.125, 1.5, 0.0, 0.5, 0.25, "window", "Glass")
	box(m, f, on(1.125), 1.5, -0.625, 0.25, 0.5, 0.5, "window", "Glass")
	box(m, f, 1.25, 1.125, -0.625, 0.25, 0.25, 0.75, "white", "Sill")
	-- the roof, a fish on the gable, the stove pipe
	gable(m, f * CFrame.new(0.25, 0, -0.625), 2.0, 1.75, 1.0, 0.5, "berry_red", "sofa", "white", "blue", 0, 0.125)
	box(m, f, on(1.125), 2.125, -0.5, 0.25, 0.25, 0.5, "orange", "SignFish")
	box(m, f, on(1.125), 2.125, -0.875, 0.25, 0.25, 0.25, "pot", "SignTail")
	cyl(m, f, -0.25, 2.5, -0.875, 0.25, 0.75, "steel_dark", "Pipe")
	box(m, f, -0.25, 2.875, -0.875, 0.5, 0.25, 0.5, "steel_dark", "PipeCap")
	-- on the deck: the rail and its lantern, the catch, the rope, the rod out over the pond
	for _, x in { -0.75, 0.0 } do
		box(m, f, x, 1.0, 0.25, 0.25, 0.5, 0.25, "wood_dark", "RailPost")
	end
	box(m, f, -0.375, 1.25, 0.25, 0.75, 0.25, 0.25, "wood", "Rail")
	lantern(m, f, -0.75, 1.25, 0.25)
	cyl(m, f, -0.375, 0.875, 0.125, 0.5, 0.25, "steel", "Pail")
	box(m, f, -0.5, 1.125, 0.125, 0.25, 0.25, 0.25, "blue", "Catch")
	box(m, f, -0.25, 1.125, 0.06, 0.25, 0.25, 0.25, "steel_dark", "Catch")
	local a, b = Vector3.new(0.25, 0.875, 0.125), Vector3.new(0.75, 1.75, 0.75)
	put(m, f, CFrame.lookAt((a + b) / 2, b), 0.25, 0.25, (b - a).Magnitude, "wood_dark", "Rod")
end

-- An orchard tree at (x, z): a flared trunk with a branch, a crown of four balls lit from the top left, five fruit on
-- the sides that show and one fallen in the grass.
local function orchardTree(m: Instance, f: CFrame, x: number, z: number, fruit: string)
	cyl(m, f, x, 0.25, z, 0.75, 0.25, "wood_dark", "Roots")
	cyl(m, f, x, 0.625, z, 0.5, 1.0, "wood_dark", "Trunk")
	put(m, f, CFrame.new(x + 0.25, 1.125, z + 0.06) * CFrame.Angles(0, 0, -0.6), 0.25, 0.5, 0.25, "wood_dark", "Branch")
	ball(m, f, x, 1.75, z, 1.25, "leaf", "Crown")
	ball(m, f, x + 0.375, 1.5, z + 0.375, 0.75, "leaf_dark", "Crown")
	ball(m, f, x - 0.25, 2.125, z - 0.125, 0.75, "leaf", "Crown")
	ball(m, f, x - 0.375, 1.5, z + 0.25, 0.75, "leaf_dark", "Crown")
	for _, p in { { 0.0, 1.5, 0.625 }, { 0.625, 1.75, 0.06 }, { 0.375, 2.06, 0.44 }, { -0.375, 1.31, 0.56 }, { 0.69, 1.38, 0.5 } } do
		ball(m, f, x + p[1], p[2], z + p[3], 0.25, fruit, "Fruit")
	end
	ball(m, f, x + 0.5, 0.25, z + 0.56, 0.25, fruit, "Fallen")
end

-- A white picket at (x, z), its point turned to face +Z (or +X when `side`).
local function picket(m: Instance, f: CFrame, x: number, z: number, side: boolean?)
	box(m, f, x, 0.375, z, 0.25, 0.75, 0.25, "white", "Picket")
	put(m, f, CFrame.new(x, 0.75, z) * (if side then CFrame.Angles(PI / 4, 0, 0) else CFrame.Angles(0, 0, PI / 4)), 0.25, 0.25, 0.25, "white", "PicketTip")
end

-- Fruit Orchard (4 x 4): four fruit trees (apples, oranges, lemons, peaches) on a lawn, a white picket fence along the
-- front and the east side with an arch over the gateway (a rose climbing it, an apple painted on its board), a low
-- stone edge at the back and the west. Stepping stones lead in from the gate; a ladder leans into the peach tree, a
-- red wheelbarrow of apples waits under the oranges, crates and baskets of picked fruit sit by the fence.
B.orchard = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 4, "grass_dark", "Lawn")
	box(m, f, -0.125, 0.125, -1.875, 3.75, 0.25, 0.25, "rock", "Edge")
	box(m, f, -1.875, 0.125, 0.0, 0.25, 0.25, 3.5, "rock", "Edge")
	for k, p in { { 0.0, 1.5 }, { 0.125, 0.875 }, { -0.125, 0.25 } } do
		box(m, f, p[1], 0.125, p[2], 0.5, 0.25, 0.5, if k == 2 then "sand_dark" else "pavement", "Stone")
	end
	orchardTree(m, f, -0.75, -0.75, "berry_red")
	orchardTree(m, f, 1.0, -0.875, "orange")
	orchardTree(m, f, -1.0, 0.875, "yellow")
	orchardTree(m, f, 0.875, 0.75, "pink")
	-- the picket fence: corner posts, pickets, a rail behind them
	for _, p in { { -1.875, 1.875 }, { 1.875, 1.875 }, { 1.875, -1.875 } } do
		box(m, f, p[1], 0.5, p[2], 0.25, 1.0, 0.25, "white", "FencePost")
		ball(m, f, p[1], 1.06, p[2], 0.25, "white", "PostCap")
	end
	for _, x in { -1.375, -0.875, 0.875, 1.375 } do
		picket(m, f, x, 1.875)
	end
	for k = 0, 6 do
		picket(m, f, 1.875, -1.375 + k * 0.5, true)
	end
	box(m, f, -1.25, 0.5, 1.75, 1.5, 0.25, 0.25, "white", "Rail")
	box(m, f, 1.25, 0.5, 1.75, 1.5, 0.25, 0.25, "white", "Rail")
	box(m, f, 1.75, 0.5, 0.0, 0.25, 0.25, 3.5, "white", "Rail")
	-- the arch over the gateway, its rose and its board
	for _, x in { -0.375, 0.375 } do
		box(m, f, x, 0.875, 1.75, 0.25, 1.75, 0.25, "white", "ArchPost")
	end
	box(m, f, 0, 1.875, 1.75, 1.25, 0.25, 0.25, "white", "ArchBeam")
	box(m, f, 0, 2.25, 1.75, 0.75, 0.5, 0.25, "wood", "ArchBoard")
	box(m, f, 0, 2.19, on(1.875), 0.25, 0.25, 0.25, "berry_red", "SignApple")
	box(m, f, 0.125, 2.375, on(1.875), 0.25, 0.25, 0.25, "leaf_dark", "SignLeaf")
	ball(m, f, -0.375, 1.125, 1.75, 0.5, "leaf", "Rose")
	ball(m, f, -0.375, 1.625, 1.75, 0.5, "leaf_dark", "Rose")
	box(m, f, -0.25, 1.25, 1.875, 0.25, 0.25, 0.25, "pink", "RoseBloom")
	box(m, f, -0.375, 1.75, 1.875, 0.25, 0.25, 0.25, "berry_red", "RoseBloom")
	-- the ladder leaning into the peach tree
	local ld = f * CFrame.new(0.625, 0, 1.375) * CFrame.Angles(-0.3, 0, 0)
	for _, x in { -0.25, 0.25 } do
		box(m, ld, x, 0.875, 0, 0.25, 1.75, 0.25, "wood", "LadderRail")
	end
	for _, y in { 0.5, 1.0, 1.5 } do
		box(m, ld, 0, y, 0, 0.25, 0.25, 0.25, "wood_dark", "Rung")
	end
	-- the wheelbarrow of apples under the oranges, handles to the back
	log(m, f, 1.25, 0.25, 0.5, 0.25, 0.5, "black", "Wheel")
	log(m, f, 1.25, 0.25, 0.5, 0.25, 0.25, "steel", "Hub")
	box(m, f, 1.25, 0.5, 0.0, 0.75, 0.25, 0.75, "berry_red", "Tray")
	wedge(m, f, 1.25, 0.5, 0.5, 0.75, 0.25, 0.25, "berry_red", PI, "TrayFront")
	box(m, f, 1.25, 0.625, 0.0, 0.5, 0.25, 0.5, "wood_dark", "Load")
	for _, x in { 1.0, 1.5 } do
		box(m, f, x, 0.5, -0.625, 0.25, 0.25, 0.5, "wood", "Handle")
		box(m, f, x, 0.25, -0.25, 0.25, 0.25, 0.25, "steel_dark", "Leg")
	end
	for _, p in { { 1.125, 0.06 }, { 1.375, -0.06 }, { 1.25, 0.19 } } do
		ball(m, f, p[1], 0.81, p[2], 0.25, "berry_red", "Apple")
	end
	-- crates and baskets of picked fruit
	crate(m, f, -1.375, 0.125, 1.25, 0.5)
	crate(m, f, -1.375, 0.625, 1.25, 0.5, { "berry_red", "berry_red", "berry_red" })
	crate(m, f, -0.875, 0.125, 1.375, 0.5, { "yellow", "yellow" })
	for _, b in { { 1.25, 1.375, "pink" }, { -0.25, -1.375, "berry_red" } } :: { { any } } do
		box(m, f, b[1], 0.25, b[2], 0.5, 0.25, 0.5, "straw", "Basket")
		for k = 0, 2 do
			ball(m, f, b[1] - 0.125 + k * 0.125, 0.44, b[2] + (k % 2) * 0.06, 0.25, b[3], "Fruit")
		end
	end
end

-- A plant in a little clay pot standing on y0: "tomato" (a vine on a cane, red fruit), "bloom" (dark leaves, a
-- flower), "fern" (a round green ball).
local function potPlant(m: Instance, f: CFrame, x: number, y0: number, z: number, kind: string, bloom: string?)
	box(m, f, x, y0 + 0.125, z, 0.25, 0.25, 0.25, "pot", "Pot")
	if kind == "tomato" then
		box(m, f, x + 0.06, y0 + 0.625, z - 0.06, 0.25, 0.75, 0.25, "wood", "Cane")
		ball(m, f, x, y0 + 0.5, z, 0.5, "leaf", "Vine")
		ball(m, f, x, y0 + 0.875, z, 0.5, "leaf_dark", "Vine")
		ball(m, f, x + 0.19, y0 + 0.56, z + 0.19, 0.25, "berry_red", "Tomato")
	else
		ball(m, f, x, y0 + 0.44, z, 0.5, if kind == "fern" then "leaf" else "leaf_dark", "Leaves")
		if bloom then
			box(m, f, x + 0.06, y0 + 0.69, z + 0.06, 0.25, 0.25, 0.25, bloom, "Flower")
		end
	end
end

-- Greenhouse (4 x 3): a glass house on a brick base with a stone cap. The east wall, the gable ends and the roof are
-- glass in white frames (the roof in two tones of pane, white rafters over it, one pane propped open, a finial at each
-- end of the ridge, a flower plaque on the east gable); the front is open frames round a doorway with its glass door
-- swung out, so the potted tomatoes and flowers just inside show through it. Two steps up to the door, a planter of
-- flowers either side of them, a water butt and a watering can.
B.greenhouse = function(m, f)
	local cx, cz = 0.375, -0.25 -- the house: x -1.125 .. 1.875, z -1.25 .. 0.75
	box(m, f, cx, 0.25, cz, 3.0, 0.5, 2.0, "brick", "Base")
	box(m, f, cx, 0.625, cz, 3.25, 0.25, 2.25, "rock", "Cap")
	box(m, f, on(1.875), 0.375, -0.5, 0.25, 0.25, 0.5, "clay", "Brick")
	box(m, f, on(1.875), 0.125, 0.25, 0.25, 0.25, 0.5, "clay", "Brick")
	-- the glass: back and west walls (seen from inside), the east wall with its frames
	box(m, f, cx, 1.375, -1.125, 2.5, 1.25, 0.25, "window", "Glass")
	box(m, f, -1.0, 1.375, -0.375, 0.25, 1.25, 1.75, "window", "Glass")
	box(m, f, 1.75, 1.375, -0.25, 0.25, 1.25, 1.5, "window", "Glass")
	box(m, f, 1.75, 1.375, -1.125, 0.25, 1.25, 0.25, "white", "Post")
	for _, z in { -0.5, 0.125 } do
		box(m, f, on(1.875), 1.375, z, 0.25, 1.25, 0.25, "white", "Mullion")
	end
	box(m, f, on(1.875), 1.5, cz, 0.25, 0.25, 1.75, "white", "Transom")
	-- the open front: posts, the eave beam, the sills, the glass door
	for _, x in { -1.0, 0.0, 0.75, 1.75 } do
		box(m, f, x, 1.375, 0.625, 0.25, 1.25, 0.25, "white", "Post")
	end
	box(m, f, cx, 1.875, 0.625, 3.0, 0.25, 0.25, "white", "Beam")
	box(m, f, -0.5, 0.875, 0.625, 0.75, 0.25, 0.25, "white", "Sill")
	box(m, f, 1.25, 0.875, 0.625, 0.75, 0.25, 0.25, "white", "Sill")
	box(m, f, 0.375, 1.625, 0.625, 0.5, 0.25, 0.25, "white", "DoorHead")
	box(m, f, 0.75, 1.125, 1.0, 0.25, 0.75, 0.5, "window", "DoorGlass")
	box(m, f, on(0.875), 1.125, 1.0, 0.25, 0.25, 0.5, "white", "DoorRail")
	box(m, f, on(0.92), 1.125, 1.125, 0.25, 0.25, 0.25, "gold", "Handle")
	-- the roof: glass rows, white rafters, a pane propped open, finials
	gable(m, f * CFrame.new(cx, 0, cz), 2.0, 3.0, 2.0, 0.75, "window", "ice", "white", "window", 0, 0)
	local tilt = math.atan2(0.75, 1.0)
	for _, x in { -0.5, 0.5 } do
		local p = Vector3.new(cx + x, 2.375, cz + 0.5) + Vector3.new(0, 1.0, 0.75) / 1.25 * 0.4
		put(m, f, CFrame.new(p) * CFrame.Angles(tilt, 0, 0), 0.25, 0.25, 1.25, "white", "Rafter")
	end
	put(m, f, CFrame.new(cx + 1.0, 2.5, cz + 0.375) * CFrame.Angles(tilt + 0.45, 0, 0), 0.5, 0.25, 0.5, "window", "Vent")
	for _, x in { -1.375, 1.375 } do
		ball(m, f, cx + x, 3.25, cz, 0.25, "white", "Finial")
	end
	-- the east gable's flower
	put(m, f, CFrame.new(on(1.875), 2.25, cz), 0.25, 0.5, 0.5, "white", "Plaque", "Cylinder")
	box(m, f, on(1.92), 2.25, cz, 0.25, 0.25, 0.25, "pink", "PlaqueFlower")
	-- inside: the aisle and two benches of pots
	box(m, f, 0.375, on(0.75), -0.25, 2.5, 0.25, 1.5, "hair_brown", "Soil")
	box(m, f, 0.375, on(0.75) + 0.03, -0.25, 0.5, 0.25, 1.75, "pavement", "Aisle")
	local plants: { { any } } = {
		{ -0.625, "tomato" },
		{ -0.25, "bloom", "pink" },
		{ 1.125, "bloom", "yellow" },
		{ 1.5, "tomato" },
	}
	for _, pl in plants do
		potPlant(m, f, pl[1], 0.75, 0.375, pl[2], pl[3])
	end
	for _, x in { -0.5, 1.25 } do
		box(m, f, x, 0.875, -0.75, 0.75, 0.25, 0.5, "wood", "Bench")
		potPlant(m, f, x, 1.0, -0.75, "fern")
	end
	-- the steps, the planters, the water butt and the can
	box(m, f, 0.375, 0.375, 1.0, 0.75, 0.25, 0.25, "rock", "Step")
	box(m, f, 0.375, 0.125, 1.25, 0.75, 0.25, 0.25, "pavement", "Step")
	for _, p in { { -0.5, 1.0, { "pink", "white", "yellow" } }, { 1.25, 0.75, { "purple", "pink" } } } :: { { any } } do
		box(m, f, p[1], 0.25, 1.125, p[2], 0.5, 0.5, "wood", "Planter")
		box(m, f, p[1], on(0.5), 1.125, p[2] - 0.25, 0.25, 0.25, "hair_brown", "PlanterSoil")
		local n = #p[3]
		for k, c in p[3] do
			local x = p[1] + ((k - 1) - (n - 1) / 2) * 0.375
			ball(m, f, x, 0.625, 1.125, 0.5, if k % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
			box(m, f, x + 0.06, 0.875, 1.19, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
	cyl(m, f, -1.625, 0.375, 0.5, 0.75, 0.75, "teal", "Butt")
	cyl(m, f, -1.625, 0.81, 0.5, 0.5, 0.25, "wood_dark", "ButtLid")
	box(m, f, -1.625, 0.25, 0.875, 0.25, 0.25, 0.25, "gold", "Tap")
	cyl(m, f, -1.25, 0.25, 1.25, 0.5, 0.5, "steel", "Can")
	put(m, f, CFrame.new(-1.625, 0.375, 1.25) * CFrame.Angles(0, 0, -0.7), 0.5, 0.25, 0.25, "steel", "Spout")
end

-- A clump of rice at (x, y, z): two blades crossing.
local function rice(m: Instance, f: CFrame, x: number, y: number, z: number, k: number)
	put(m, f, CFrame.new(x - 0.06, y + 0.25, z) * CFrame.Angles(0, k * 0.4, 0.3), 0.25, 0.5, 0.25, "leaf", "Rice")
	put(m, f, CFrame.new(x + 0.06, y + 0.25, z) * CFrame.Angles(0, k * 0.4, -0.3), 0.25, 0.5, 0.25, "leaf_dark", "Rice")
end

-- Rice Terrace (4 x 4): three paddies of still water stepping up toward the back, each held by a facing of stones in
-- two greys with a grassy bank round its water, rice growing in rows and a white heron wading in the middle one. A
-- stone path climbs the east side beside them to a little thatched shelter on the top step, where sacks of rice wait
-- under a straw hat; a stone lantern stands on the top terrace.
B.paddy = function(m, f)
	-- the earth of the three steps (the top one cut back at the back-left corner)
	box(m, f, -0.5, 0, 1.25, 3.0, 0.5, 1.0, "wood_dark", "Terrace")
	box(m, f, -0.5, 0.25, 0.125, 3.0, 0.75, 1.25, "wood_dark", "Terrace")
	box(m, f, -0.5, 0.375, -0.875, 3.0, 1.25, 0.75, "wood_dark", "Terrace")
	box(m, f, -0.125, 0.375, -1.5, 2.25, 1.25, 0.5, "wood_dark", "Terrace")
	-- the water
	box(m, f, -0.5, 0.25, 1.125, 2.5, 0.25, 0.75, "water", "Paddy"):SetAttribute("PixelWater", 2)
	box(m, f, -0.5, 0.625, 0.0, 2.5, 0.25, 1.0, "water", "Paddy"):SetAttribute("PixelWater", 2)
	box(m, f, -0.125, 1.0, -1.125, 1.75, 0.25, 0.75, "water", "Paddy"):SetAttribute("PixelWater", 2)
	-- the grassy banks round the water
	for _, t in { { 0.375, 1.625, 0.75, 1.5 }, { 0.75, 0.625, -0.5, 0.5 } } do
		local y, zf, z0, z1 = t[1], t[2], t[3], t[4]
		box(m, f, -0.5, y, zf, 3.0, 0.25, 0.25, "moss", "Bank")
		box(m, f, -1.875, y, (z0 + z1) / 2, 0.25, 0.25, z1 - z0, "moss", "Bank")
		box(m, f, 0.875, y, (z0 + z1) / 2, 0.25, 0.25, z1 - z0, "moss", "Bank")
	end
	box(m, f, -0.5, 1.125, -0.625, 3.0, 0.25, 0.25, "moss", "Bank")
	box(m, f, 0.875, 1.125, -1.125, 0.25, 0.25, 0.75, "moss", "Bank")
	box(m, f, -1.125, 1.125, -1.125, 0.25, 0.25, 0.75, "moss", "Bank")
	box(m, f, -0.125, 1.125, -1.625, 2.25, 0.25, 0.25, "moss", "Bank")
	box(m, f, -1.625, on(1.0), -1.0, 0.75, 0.25, 0.5, "grass_dark", "Grass")
	-- the stone facings of the three fronts
	for _, t in { { 0.125, 1.75 }, { 0.5, 0.75 }, { 0.875, -0.5 } } do
		for k = 0, 5 do
			box(m, f, -1.75 + k * 0.5, t[1], on(t[2]), 0.5, 0.25, 0.25, if k % 2 == 0 then "rock" else "rock_dark", "Stone")
		end
	end
	-- the rice and the heron
	for _, z in { 1.0, 1.375 } do
		for k = 0, 4 do
			rice(m, f, -1.5 + k * 0.5, 0.375, z, k)
		end
	end
	for _, z in { -0.25, 0.25 } do
		for k = 0, 3 do
			rice(m, f, -1.0 + k * 0.5, 0.75, z, k + 1)
		end
	end
	for _, z in { -1.375, -0.875 } do
		for k = 0, 2 do
			rice(m, f, -0.75 + k * 0.5, 1.125, z, k)
		end
	end
	box(m, f, -1.5, 0.875, 0.0, 0.25, 0.25, 0.25, "black", "HeronLegs")
	box(m, f, -1.5, 1.125, 0.0, 0.5, 0.25, 0.25, "white", "Heron")
	box(m, f, -1.375, 1.375, 0.0, 0.25, 0.25, 0.25, "white", "HeronNeck")
	box(m, f, -1.375, 1.625, 0.0, 0.25, 0.25, 0.25, "white", "HeronHead")
	box(m, f, -1.125, 1.625, 0.0, 0.25, 0.25, 0.25, "orange", "Beak")
	-- the stone path up the east side, a step at each rise
	box(m, f, 1.375, 0, 1.375, 0.75, 0.5, 1.25, "pavement", "Path")
	box(m, f, 1.375, 0.25, 0.125, 0.75, 0.75, 1.25, "pavement", "Path")
	box(m, f, 1.375, 0.375, -1.25, 0.75, 1.25, 1.5, "pavement", "Path")
	for k, p in { { 0.125, -1.75 }, { 0.125, -0.875 }, { 0.375, -1.25 }, { 0.625, -1.625 }, { 0.625, -0.75 }, { 0.875, -1.25 }, { 0.125, 0.375 }, { 0.375, -0.125 }, { 0.375, 0.5 } } do
		box(m, f, on(1.75), p[1], p[2], 0.25, 0.25, 0.5, if k % 2 == 0 then "rock" else "rock_dark", "Stone")
	end
	box(m, f, 1.375, 0.375, 0.875, 0.75, 0.25, 0.25, "rock", "Step")
	box(m, f, 1.375, 0.75, -0.375, 0.75, 0.25, 0.25, "rock", "Step")
	sack(m, f, 1.5, 0.25, 1.375, "cream")
	-- the shelter on the top step: four posts, a thatched roof with wooden gables
	for _, x in { 1.125, 1.625 } do
		for _, z in { -1.625, -0.625 } do
			box(m, f, x, 1.25, z, 0.25, 0.5, 0.25, "wood_dark", "ShelterPost")
		end
	end
	gable(m, f * CFrame.new(1.125, 0, -1.125) * CFrame.Angles(0, PI / 2, 0), 1.5, 1.5, 1.0, 0.5, "straw", "sand_dark", "wood_dark", "wood", 0, 0)
	box(m, f, 1.375, 1.25, -1.25, 0.5, 0.5, 0.5, "cream", "RiceSack")
	box(m, f, 1.375, 1.625, -1.25, 0.75, 0.25, 0.75, "straw", "HatBrim")
	-- the stone lantern on the top terrace
	cyl(m, f, -1.625, 1.125, -1.0, 0.5, 0.25, "rock", "LanternBase")
	box(m, f, -1.625, 1.375, -1.0, 0.25, 0.25, 0.25, "rock", "LanternPost")
	box(m, f, -1.625, 1.75, -1.0, 0.5, 0.5, 0.5, "rock", "LanternBox")
	box(m, f, -1.625, 1.75, on(-0.75), 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, on(-1.375), 1.75, -1.0, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, -1.625, 2.125, -1.0, 0.75, 0.25, 0.75, "rock_dark", "LanternCap")
end

-- Kelp Farm (4 x 4): a sea pen in a sandy bank, a boardwalk of two-tone boards on dark beams along the front and the
-- east side, a low rim of dark stone round the rest. Three lines of orange and white floats cross the water between
-- posts, kelp rising along each in short wavy strands, loose fronds drifting between. A red dinghy with its oar rests
-- at the front; on the walk a crate and a basket of cut kelp, a coil of rope and a lantern, and a gull on a post.
B.kelpfarm = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 4, "sand_dark", "Bank")
	box(m, f, -0.125, 0.125, -0.125, 3.25, 0.25, 3.25, "water", "Pen"):SetAttribute("PixelWater", 2)
	box(m, f, -0.25, 0.125, -1.875, 3.5, 0.5, 0.25, "rock_dark", "Rim")
	box(m, f, -1.875, 0.125, -0.125, 0.25, 0.5, 3.25, "rock_dark", "Rim")
	-- the boardwalk: boards across the front and east walks, beams under their near edges
	for i = 0, 7 do
		box(m, f, -1.75 + i * 0.5, 0.375, 1.75, 0.5, 0.25, 0.5, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	for i = 0, 6 do
		box(m, f, 1.75, 0.375, -1.75 + i * 0.5, 0.5, 0.25, 0.5, if i % 2 == 0 then "sand_dark" else "wood", "Board")
	end
	box(m, f, 0, 0.125, 1.875, 4.0, 0.25, 0.25, "wood_dark", "Beam")
	box(m, f, 1.875, 0.125, -0.125, 0.25, 0.25, 3.75, "wood_dark", "Beam")
	-- the three kelp lines
	for n, z in { -1.125, -0.25, 0.625 } do
		box(m, f, -1.875, 0.625, z, 0.25, 0.5, 0.25, "wood_dark", "LinePost")
		box(m, f, 1.75, 0.75, z, 0.25, 0.5, 0.25, "wood_dark", "LinePost")
		for k, x in { -1.375, -0.625, 0.125, 0.875 } do
			ball(m, f, x, 0.375, z, 0.25, if (k + n) % 2 == 0 then "orange" else "white", "Float")
		end
		for k, x in { -1.0, -0.25, 0.5, 1.25 } do
			local d = if (k + n) % 2 == 0 then 0.125 else -0.125
			box(m, f, x, 0.5, z, 0.25, 0.5, 0.25, if k % 2 == 0 then "leaf_dark" else "leaf", "Kelp")
			if (k + n) % 2 == 0 then
				box(m, f, x + d, 0.875, z, 0.25, 0.25, 0.25, "leaf", "Kelp")
			end
		end
	end
	for _, p in { { -0.875, -0.625 }, { 0.625, 0.125 }, { -1.25, 0.125 }, { 0.25, -0.75 } } do
		box(m, f, p[1], 0.25, p[2], 0.5, 0.25, 0.25, "leaf", "Frond")
	end
	-- the dinghy
	box(m, f, -1.0, 0.375, 1.125, 1.0, 0.25, 0.5, "berry_red", "Hull")
	wedge(m, f, -0.375, 0.375, 1.125, 0.5, 0.25, 0.25, "berry_red", -PI / 2, "Bow")
	box(m, f, -1.0, 0.5, 1.125, 0.25, 0.25, 0.25, "wood", "Seat")
	put(m, f, CFrame.new(-0.75, 0.56, 1.125) * CFrame.Angles(0, 0.4, 0), 0.25, 0.25, 1.0, "wood", "Oar")
	-- on the walk
	crate(m, f, 1.625, 0.5, 1.0, 0.5, { "leaf_dark", "green" })
	box(m, f, 1.0, 0.625, 1.75, 0.5, 0.25, 0.5, "straw", "Basket")
	ball(m, f, 0.875, 0.81, 1.75, 0.25, "leaf_dark", "Kelp")
	ball(m, f, 1.125, 0.81, 1.81, 0.25, "leaf", "Kelp")
	cyl(m, f, 0.25, 0.625, 1.75, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, f, 0.25, 0.75, 1.75, 0.25, 0.25, "wood_dark", "Coil")
	lantern(m, f, -1.75, 0.5, 1.75)
	box(m, f, -1.875, 1.0, -0.375, 0.25, 0.25, 0.5, "white", "Gull")
	box(m, f, -1.875, 1.25, -0.25, 0.25, 0.25, 0.25, "white", "GullHead")
	box(m, f, -1.875, 1.25, 0.0, 0.25, 0.25, 0.25, "yellow", "Beak")
end

-- A planter along X at (x, y0, z), w long: a box of wood, a row of leaf balls spilling over it, a flower every few.
local function planterX(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, blooms: { string })
	box(m, f, x, y0 + 0.25, z, w, 0.5, 0.25, "wood", "Planter")
	local n = math.floor(w / 0.5 + 0.01)
	for k = 0, n - 1 do
		local bx = x - w / 2 + 0.25 + k * 0.5
		ball(m, f, bx, y0 + 0.56, z + 0.06, 0.5, if k % 3 == 1 then "leaf_dark" else "leaf", "Leaves")
		local c = blooms[k // 2 + 1]
		if k % 2 == 0 and c then
			box(m, f, bx + 0.06, y0 + 0.81, z + 0.19, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
end

-- The same along Z at x.
local function planterZ(m: Instance, f: CFrame, x: number, y0: number, z: number, d: number, blooms: { string })
	box(m, f, x, y0 + 0.25, z, 0.25, 0.5, d, "wood", "Planter")
	local n = math.floor(d / 0.5 + 0.01)
	for k = 0, n - 1 do
		local bz = z - d / 2 + 0.25 + k * 0.5
		ball(m, f, x + 0.06, y0 + 0.56, bz, 0.5, if k % 3 == 1 then "leaf_dark" else "leaf", "Leaves")
		local c = blooms[k // 2 + 1]
		if k % 2 == 0 and c then
			box(m, f, x + 0.19, y0 + 0.81, bz + 0.06, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
end

-- Sky Garden (5 x 4): a glass tower of three floors stepping back toward the north-west, steel mullions on the faces
-- that show, white floor slabs, and on each slab a terrace with planters spilling leaves and flowers, vines hanging
-- over the edges and a potted tree. Up top a garden round a steel water tank on legs with its ladder, and a mast with
-- a red light. At the foot: a glass door under a canopy with a green sign, two potted shrubs, flower beds along the
-- front and a lamp.
B.skygarden = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 4, "pavement", "Plaza")
	-- the floors: glass, then a white slab over each (x0, x1, z0, z1, y0 of the glass)
	local floors = {
		{ -1.625, 1.875, -1.625, 0.875, 0.125 },
		{ -1.375, 1.375, -1.625, 0.375, 1.875 },
		{ -1.125, 0.875, -1.625, -0.125, 3.625 },
	}
	for i, fl in floors do
		local x0, x1, z0, z1, y0 = fl[1], fl[2], fl[3], fl[4], fl[5]
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		box(m, f, cx, y0 + 0.75, cz, x1 - x0, 1.5, z1 - z0, "window", "Glass")
		box(m, f, cx, y0 + 1.625, cz, x1 - x0 + 0.5, 0.25, z1 - z0 + 0.5, "white", "Slab")
		-- mullions and a transom on the front and east faces
		local nx = math.floor((x1 - x0) / 0.75 + 0.01)
		for k = 1, nx - 1 do
			local x = x0 + k * (x1 - x0) / nx
			if i > 1 or math.abs(x - 0.125) > 0.5 then
				box(m, f, x, y0 + 0.75, on(z1), 0.25, 1.5, 0.25, "steel", "Mullion")
			end
		end
		local nz = math.floor((z1 - z0) / 0.75 + 0.01)
		for k = 1, nz - 1 do
			box(m, f, on(x1), y0 + 0.75, z0 + k * (z1 - z0) / nz, 0.25, 1.5, 0.25, "steel", "Mullion")
		end
		box(m, f, cx, y0 + 1.125, on(z1, 1) + 0.03, x1 - x0, 0.25, 0.25, "steel", "Transom")
		box(m, f, on(x1, 1) + 0.03, y0 + 1.125, cz, 0.25, 0.25, z1 - z0, "steel", "Transom")
	end
	-- the door, its canopy and the sign over it
	box(m, f, 0.125, 0.5, on(0.875), 0.75, 0.875, 0.25, "steel_dark", "DoorFrame")
	box(m, f, 0.125, 0.5, on(0.92), 0.5, 0.75, 0.25, "screen_off", "Door")
	box(m, f, 0.125, 0.5, on(0.965), 0.25, 0.75, 0.25, "steel", "DoorBar")
	box(m, f, 0.125, 1.375, 1.125, 1.25, 0.25, 0.5, "white", "Canopy")
	box(m, f, 0.125, 1.75, on(1.125), 1.5, 0.25, 0.25, "green", "Sign")
	for _, x in { -0.25, 0.125, 0.5 } do
		box(m, f, x, 1.75, on(1.17), 0.25, 0.25, 0.25, "white", "SignMark")
	end
	-- terrace one: planters along the front and east edges, a potted tree, vines
	planterX(m, f, 0.125, 1.875, 1.0, 3.5, { "pink", "yellow", "white", "pink" })
	planterZ(m, f, 2.0, 1.875, -0.875, 1.5, { "purple", "yellow" })
	cyl(m, f, 1.75, 2.125, 0.375, 0.5, 0.5, "pot", "TreePot")
	box(m, f, 1.75, 2.5, 0.375, 0.25, 0.25, 0.25, "wood_dark", "Trunk")
	ball(m, f, 1.75, 2.875, 0.375, 0.75, "leaf", "Crown")
	ball(m, f, 1.875, 2.625, 0.5, 0.5, "leaf_dark", "Crown")
	for _, x in { -1.25, -0.75, 1.0, 1.5 } do
		box(m, f, x, 1.375, 1.0, 0.25, 0.5, 0.25, "leaf_dark", "Vine")
	end
	for _, z in { -1.0, -0.25 } do
		box(m, f, 2.0, 1.375, z, 0.25, 0.5, 0.25, "leaf", "Vine")
	end
	-- terrace two
	planterX(m, f, 0.0, 3.625, 0.5, 3.0, { "yellow", "pink", "white" })
	planterZ(m, f, 1.5, 3.625, -0.875, 1.5, { "pink", "white" })
	for _, x in { -1.0, 0.75 } do
		box(m, f, x, 3.125, 0.5, 0.25, 0.5, 0.25, "leaf_dark", "Vine")
	end
	box(m, f, 1.5, 3.125, -0.5, 0.25, 0.5, 0.25, "leaf", "Vine")
	-- the roof: a planter, the tank on its legs with a ladder, the mast
	planterX(m, f, -0.25, 5.375, 0.0, 2.0, { "pink", "yellow" })
	for _, x in { -0.5, 0.25 } do
		for _, z in { -1.25, -0.5 } do
			box(m, f, x, 5.5, z, 0.25, 0.25, 0.25, "steel_dark", "TankLeg")
		end
	end
	cyl(m, f, -0.125, 6.0, -0.875, 1.0, 0.75, "steel", "Tank")
	cyl(m, f, -0.125, 6.5, -0.875, 0.75, 0.25, "steel_dark", "TankLid")
	cyl(m, f, -0.125, 6.75, -0.875, 0.25, 0.25, "steel_dark", "TankCap")
	for _, x in { -0.375, 0.125 } do
		box(m, f, x, 5.875, -0.25, 0.25, 1.0, 0.25, "steel_dark", "LadderRail")
	end
	box(m, f, -0.125, 5.875, -0.25, 0.25, 0.25, 0.25, "steel_dark", "Rung")
	box(m, f, 0.75, 5.875, -1.5, 0.25, 1.0, 0.25, "steel", "Mast")
	box(m, f, 0.75, 6.5, -1.5, 0.25, 0.25, 0.25, "berry_red", "MastLight", true)
	-- at the foot: shrubs by the door, flower beds, a lamp
	for _, x in { -0.625, 0.875 } do
		cyl(m, f, x, 0.375, 1.25, 0.5, 0.5, "white", "ShrubPot")
		ball(m, f, x, 0.875, 1.25, 0.75, "leaf_dark", "Shrub")
	end
	for _, b in { { -1.625, { "pink", "yellow" } }, { 1.625, { "white", "purple" } } } :: { { any } } do
		box(m, f, b[1], 0.25, 1.625, 1.0, 0.25, 0.5, "wood", "Bed")
		for k, c in b[2] do
			local x = b[1] - 0.25 + (k - 1) * 0.5
			ball(m, f, x, 0.5, 1.625, 0.5, "leaf", "Leaves")
			box(m, f, x + 0.06, 0.75, 1.69, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
	box(m, f, -2.25, 0.875, 1.0, 0.25, 1.5, 0.25, "steel_dark", "LampPost")
	box(m, f, -2.25, 1.75, 1.0, 0.25, 0.25, 0.25, "yellow", "LampLight", true)
	box(m, f, -2.25, 2.0, 1.0, 0.5, 0.25, 0.5, "steel_dark", "LampCap")
end

-- Mushroom Cellar (4 x 4): a grassy hill over a cellar, its pale stone front set with darker stones under a mossy
-- cap, grass creeping over it. A round-topped plank door with iron bands sits in a dark stone arch over a step, a
-- wall lantern either side, baskets of picked mushrooms by the step. Giant spotted mushrooms grow out of the hill
-- with small ones round them and a round window glows warm in its side. A stack of logs sprouting mushrooms lies on
-- the east side, a sign with a red cap on it on the west.
B.shroomcellar = function(m, f)
	local R, CX, CZ = 1.5, 0.125, -0.375 -- the hill: a ball of radius R on the ground at (CX, CZ)
	local function hillY(x: number, z: number): number
		local d2 = (x - CX) * (x - CX) + (z - CZ) * (z - CZ)
		return if d2 < R * R then math.sqrt(R * R - d2) else 0
	end
	box(m, f, 0, 0, 0, 4, 0.25, 4, "grass_dark", "Lawn")
	ball(m, f, CX, 0, CZ, R * 2, "grass", "Hill")
	ball(m, f, -0.5, 0.75, -0.625, 1.75, "moss", "Hill")
	ball(m, f, 0.75, 0.625, -0.875, 1.5, "grass", "Hill")
	-- the stone front, its cap and the grass over it
	box(m, f, 0, 0.875, 1.25, 2.25, 1.75, 0.5, "pavement", "Front")
	box(m, f, 0, 1.875, 1.25, 2.5, 0.25, 0.75, "moss", "FrontCap")
	ball(m, f, -0.875, 2.0, 1.125, 0.5, "grass", "Overgrowth")
	ball(m, f, 0.75, 2.0, 1.0, 0.5, "moss", "Overgrowth")
	for k, p in { { -0.875, 0.375 }, { -0.75, 1.625 }, { 0.875, 0.25 }, { 0.75, 1.625 } } do
		box(m, f, p[1], p[2], on(1.5), 0.5, 0.25, 0.25, if k % 2 == 0 then "rock" else "sand_dark", "Stone")
	end
	-- the arch, the door, its bands, the step
	box(m, f, 0, 0.625, on(1.5), 1.25, 0.75, 0.25, "rock_dark", "Arch")
	rodZ(m, f, 0, 1.0, on(1.5), 1.25, 0.25, "rock_dark", "Arch")
	box(m, f, 0, 0.625, on(1.545), 0.75, 0.75, 0.25, "wood", "Door")
	rodZ(m, f, 0, 1.0, on(1.545), 0.75, 0.25, "wood", "Door")
	box(m, f, 0, 0.75, on(1.59), 0.25, 1.0, 0.25, "wood_dark", "Plank")
	for _, y in { 0.5, 0.875 } do
		box(m, f, 0, y, on(1.62), 0.75, 0.25, 0.25, "steel_dark", "Band")
	end
	box(m, f, 0.25, 0.625, on(1.665), 0.25, 0.25, 0.25, "gold", "Ring")
	box(m, f, 0, 0.125, 1.75, 1.25, 0.25, 0.5, "rock", "Step")
	-- the wall lanterns
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.375, 1.625, 0.25, 0.25, 0.25, "black", "LanternArm")
		box(m, f, x, 1.125, 1.625, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
		box(m, f, x, 0.875, 1.625, 0.25, 0.25, 0.25, "black", "LanternFoot")
	end
	-- baskets of picked mushrooms
	for _, b in { { -1.375, { "berry_red", "cream", "orange" } }, { 1.375, { "cream", "purple", "berry_red" } } } :: { { any } } do
		box(m, f, b[1], 0.25, 1.625, 0.5, 0.25, 0.5, "straw", "Basket")
		for k, c in b[2] do
			ball(m, f, b[1] - 0.25 + k * 0.125, 0.44, 1.625 + (k % 2) * 0.06, 0.25, c, "Picked")
		end
	end
	-- the giant mushrooms: x, z, cap height, cap width, colour
	local giants: { { any } } = {
		{ -0.625, -0.125, 2.375, 1.0, "berry_red" },
		{ 0.875, -0.125, 2.125, 0.75, "orange" },
		{ 0.125, -1.125, 2.625, 1.0, "purple" },
		{ -1.125, 0.5, 1.875, 0.75, "pink" },
	}
	for k, g in giants do
		local x, z, y, dia = g[1], g[2], g[3], g[4]
		local foot = math.max(hillY(x, z) - 0.25, 0.125)
		cyl(m, f, x, (foot + y) / 2, z, if dia >= 1 then 0.5 else 0.25, y - foot, "cream", "Stalk")
		K.cap(m, f, x, y, z, dia, g[5], if k % 2 == 1 then 2 else 1)
	end
	-- small ones on the hill
	for _, s in { { 0.375, 0.625, "berry_red" }, { -1.25, -0.375, "orange" }, { 1.25, -0.25, "pink" }, { -0.25, 0.75, "cream" } } :: { { any } } do
		local y = hillY(s[1], s[2])
		cyl(m, f, s[1], y, s[2], 0.25, 0.25, "cream", "Stalk")
		cyl(m, f, s[1], y + 0.25, s[2], 0.5, 0.25, s[3], "Cap")
	end
	-- the round window, the chimney, flowers
	local wf = f * CFrame.new(0.875, 0.875, 0.5) * CFrame.Angles(0, -PI / 4, 0)
	put(m, wf, CFrame.new(0, 0, 0), 0.25, 0.75, 0.75, "wood", "WindowRing", "Cylinder")
	put(m, wf, CFrame.new(0.06, 0, 0), 0.25, 0.5, 0.5, "yellow", "WindowGlow", "Cylinder").Material = Enum.Material.Neon
	for k, p in { { 0.25, 0.25 }, { -0.75, 0.375 }, { 0.5, -0.875 }, { -0.375, -1.375 } } do
		box(m, f, p[1], hillY(p[1], p[2]) + 0.06, p[2], 0.25, 0.25, 0.25, if k % 2 == 0 then "yellow" else "white", "Flower")
	end
	-- the log stack on the east side
	for _, y in { 0.25, 0.75 } do
		rodZ(m, f, 1.75, y, -0.125, 0.5, 1.25, "wood_dark", "Log")
		rodZ(m, f, 1.75, y, on(0.5), 0.25, 0.25, "wood", "LogEnd")
	end
	for k, z in { -0.5, 0.0, 0.375 } do
		box(m, f, 1.75, 1.06, z, 0.25, 0.25, 0.25, if k == 2 then "orange" else "cream", "LogCap")
	end
	box(m, f, 1.625, 0.5, on(0.5) + 0.03, 0.25, 0.25, 0.25, "cream", "LogCap")
	-- the sign on the west side
	box(m, f, -1.625, 0.5, 0.75, 0.25, 1.0, 0.25, "wood_dark", "SignPost")
	box(m, f, -1.625, 1.125, 0.875, 0.75, 0.5, 0.25, "wood", "Sign")
	box(m, f, -1.625, 1.25, on(1.0), 0.5, 0.25, 0.25, "berry_red", "SignCap")
	box(m, f, -1.625, 1.0, on(1.0), 0.25, 0.25, 0.25, "cream", "SignStalk")
end

-- Pearl Beds (5 x 4): a bed of clear shallow water on the sand, rimmed in dark rock with stones along its edges, rows
-- of dark oysters in it (some open, pink inside, on a glowing pearl), coral and weed among them, a starfish on the
-- sand. A boardwalk of two-tone boards runs along the front with a rope rail, a basket of oysters, a sack and a lantern
-- on it and a red and white dive flag at its end. The diver's hut on the east side faces the front with its gable:
-- cream walls with dark corner posts, a teal shingled roof with a glowing pearl on its ridge, a round window over a
-- teal door, portholes on its side with a net and floats hung between them, and a brass diving helmet on a crate by the
-- door.
B.pearlbeds = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 4, "sand", "Beach")
	-- the bed
	box(m, f, -0.75, 0.125, -0.5, 3.25, 0.25, 2.5, "rock_dark", "Rim")
	box(m, f, -0.75, 0.25, -0.5, 2.75, 0.25, 2.0, "shallow", "Bed"):SetAttribute("PixelWater", 2)
	for k, x in { -2.0, -1.25, -0.5, 0.25 } do
		if k % 2 == 0 then
			ball(m, f, x, 0.375, 0.625, 0.5, "rock", "Stone")
		else
			box(m, f, x, 0.375, 0.625, 0.5, 0.25, 0.25, "rock", "Stone")
		end
	end
	for k, z in { -1.25, -0.5, 0.25 } do
		if k % 2 == 1 then
			ball(m, f, 0.75, 0.375, z, 0.5, "rock", "Stone")
		else
			box(m, f, 0.75, 0.375, z, 0.25, 0.25, 0.5, "rock", "Stone")
		end
	end
	-- the oysters: a dark lower shell, a domed lid or an open one on a pearl
	for r = 0, 2 do
		for k = 0, 3 do
			local x, z = -1.75 + k * 0.625, -1.125 + r * 0.625
			if (r + k) % 3 == 1 then
				box(m, f, x, 0.375, z, 0.5, 0.25, 0.5, "cherry", "Oyster")
				put(m, f, CFrame.new(x, 0.625, z - 0.19) * CFrame.Angles(-1.0, 0, 0), 0.5, 0.25, 0.5, "slate", "Shell")
				ball(m, f, x, 0.5, z + 0.06, 0.25, "white", "Pearl").Material = Enum.Material.Neon
			else
				box(m, f, x, 0.375, z, 0.5, 0.25, 0.25, if (r + k) % 2 == 0 then "slate" else "rock_dark", "Oyster")
			end
		end
	end
	box(m, f, -2.0, 0.5, -0.19, 0.25, 0.5, 0.25, "coral", "Coral")
	box(m, f, -1.875, 0.625, -0.25, 0.25, 0.25, 0.25, "coral", "Coral")
	box(m, f, 0.375, 0.5, 0.375, 0.25, 0.5, 0.25, "leaf_dark", "Weed")
	box(m, f, -0.875, 0.5, -1.375, 0.25, 0.5, 0.25, "leaf_dark", "Weed")
	box(m, f, 0.25, 0.125, 1.0, 0.25, 0.25, 0.5, "orange", "Starfish")
	box(m, f, 0.25, 0.125, 1.0, 0.5, 0.25, 0.25, "orange", "Starfish")
	-- the boardwalk along the front, its rope rail
	for i = 0, 8 do
		box(m, f, -2.0 + i * 0.5, 0.375, 1.625, 0.5, 0.25, 0.75, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	box(m, f, 0, 0.125, 1.875, 4.5, 0.25, 0.25, "wood_dark", "Beam")
	for _, x in { -2.25, -0.75, 0.75 } do
		box(m, f, x, 0.625, 1.75, 0.25, 0.75, 0.25, "wood_dark", "Post")
	end
	for _, x in { -1.5, 0.0 } do
		box(m, f, x, 0.75, 1.75, 1.25, 0.25, 0.25, "sand_dark", "Rope")
	end
	-- the dive flag
	box(m, f, -2.25, 1.5, 1.375, 0.25, 2.0, 0.25, "white", "FlagPole")
	box(m, f, -1.875, 2.125, 1.375, 0.5, 0.5, 0.25, "berry_red", "Flag")
	put(m, f, CFrame.new(-1.875, 2.125, 1.435) * CFrame.Angles(0, 0, -PI / 4), 0.25, 0.5, 0.25, "white", "FlagStripe")
	-- on the walk
	box(m, f, -1.0, 0.625, 1.5, 0.5, 0.25, 0.5, "straw", "Basket")
	ball(m, f, -1.125, 0.81, 1.44, 0.25, "slate", "Oyster")
	ball(m, f, -0.875, 0.81, 1.56, 0.25, "rock", "Oyster")
	sack(m, f, 0.25, 0.5, 1.375, "cream")
	lantern(m, f, 1.0, 0.5, 1.5)
	-- the diver's hut (x 1.125 .. 2.125, z -1.75 .. 0.25)
	box(m, f, 1.625, 0.75, -0.75, 1.0, 1.25, 2.0, "cream", "Walls")
	box(m, f, on(2.125), 0.25, -0.75, 0.25, 0.25, 1.75, "wood_dark", "Band")
	for _, p in { { 1.125, 0.25 }, { 2.125, 0.25 }, { 2.125, -1.75 } } do
		box(m, f, p[1], 0.75, p[2], 0.25, 1.25, 0.25, "wood_dark", "Corner")
	end
	box(m, f, 1.625, 0.625, on(0.25), 0.75, 1.0, 0.25, "wood_dark", "DoorFrame")
	box(m, f, 1.625, 0.625, on(0.295), 0.5, 0.75, 0.25, "teal", "Door")
	box(m, f, 1.75, 0.625, on(0.34), 0.25, 0.25, 0.25, "gold", "Knob")
	box(m, f, 1.625, 0.125, 0.5, 0.5, 0.25, 0.5, "wood", "Step")
	gable(m, f * CFrame.new(1.625, 0, -0.75) * CFrame.Angles(0, PI / 2, 0), 1.375, 2.0, 1.0, 0.5, "teal", "blue", "wood_dark", "cream", 0, 0.125)
	rodZ(m, f, 1.625, 1.625, on(0.25), 0.5, 0.25, "white", "GableWindow")
	rodZ(m, f, 1.625, 1.625, on(0.295), 0.25, 0.25, "window", "Glass")
	cyl(m, f, 1.625, 2.375, 0.06, 0.25, 0.25, "gold", "PearlStand")
	ball(m, f, 1.625, 2.625, 0.06, 0.5, "white", "PearlSign").Material = Enum.Material.Neon
	for _, z in { -1.25, -0.25 } do
		put(m, f, CFrame.new(on(2.125), 0.875, z), 0.25, 0.75, 0.75, "white", "Porthole", "Cylinder")
		put(m, f, CFrame.new(on(2.17), 0.875, z), 0.25, 0.5, 0.5, "window", "Glass", "Cylinder")
	end
	box(m, f, on(2.125), 1.0, -0.75, 0.25, 0.5, 0.25, "sand_dark", "Net")
	ball(m, f, 2.19, 0.75, -0.75, 0.25, "orange", "Float")
	-- the diving helmet on its crate
	crate(m, f, 1.0, 0.125, 0.75, 0.5)
	cyl(m, f, 1.0, 0.75, 0.75, 0.5, 0.25, "steel_dark", "Collar")
	ball(m, f, 1.0, 1.0, 0.75, 0.5, "gold", "Helmet")
	box(m, f, 1.0, 1.0, on(1.0), 0.25, 0.25, 0.25, "window", "Faceplate")
	-- shells on the sand
	box(m, f, 2.25, 0.125, 1.0, 0.25, 0.25, 0.25, "pink", "Seashell")
	box(m, f, -2.25, 0.125, 0.875, 0.25, 0.25, 0.25, "white", "Seashell")
end

-- A beehive standing on y0 at (x, z): a dark stand, a brood box of colour a, a shallower box of colour b, a wooden lid
-- under a low clay roof, the dark way in over a landing board, a handle on its east side.
local function hive(m: Instance, f: CFrame, x: number, y0: number, z: number, a: string, b: string)
	box(m, f, x, y0 + 0.125, z, 0.5, 0.25, 0.5, "wood_dark", "HiveStand")
	box(m, f, x, y0 + 0.5, z, 0.75, 0.5, 0.75, a, "Hive")
	box(m, f, x, y0 + 0.875, z, 0.75, 0.25, 0.75, b, "Hive")
	box(m, f, x, y0 + 1.125, z, 1.0, 0.25, 1.0, "wood", "HiveLid")
	wedge(m, f, x, y0 + 1.375, z - 0.25, 1.0, 0.25, 0.5, "clay", 0, "HiveRoof")
	wedge(m, f, x, y0 + 1.375, z + 0.25, 1.0, 0.25, 0.5, "clay", PI, "HiveRoof")
	box(m, f, x, y0 + 0.375, on(z + 0.375), 0.5, 0.25, 0.25, "black", "HiveDoor")
	box(m, f, x, y0 + 0.25, z + 0.5, 0.5, 0.25, 0.25, "wood", "Landing")
	box(m, f, on(x + 0.375), y0 + 0.5, z, 0.25, 0.25, 0.25, "wood_dark", "Handle")
end

-- Honey Terraces (5 x 5): three stepped beds climbing toward the back, each held by a stone wall with darker stones
-- set in it and topped with grass, rows of flowers in six colours on them and painted beehives with clay roofs at
-- their ends, bees about. Stone steps and stepping stones climb the middle. At the front a honey stand under a
-- yellow and white awning sells jars of honey and a pot with its dipper, a lantern hung under the awning; across the
-- steps a crate holds a beekeeper's hat, a smoker stands by it and a lantern lights the way.
B.honeyterrace = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 5, "grass_dark", "Lawn")
	-- the three terraces: walls, grass tops, stones in the walls that show
	local steps: { { any } } = { { 1.25, 0.5, "rock" }, { 0.0, 1.0, "rock_dark" }, { -1.25, 1.5, "rock" } }
	for _, t in steps do
		local z, top = t[1], t[2]
		box(m, f, -0.125, (top - 0.25) / 2, z, 4.75, top - 0.25, 1.25, t[3], "Terrace")
		box(m, f, -0.125, top - 0.125, z, 4.75, 0.25, 1.25, "grass", "Bed")
	end
	for _, w in { { 0.625, 0.625, "rock" }, { -0.625, 1.125, "rock_dark" } } :: { { any } } do
		for k, x in { -2.0, -1.25, 1.0, 1.75 } do
			box(m, f, x, w[2], on(w[1]), 0.5, 0.25, 0.25, if k % 2 == 0 then w[3] else "slate", "Stone")
		end
	end
	for k, p in { { 0.25, -0.25 }, { 0.5, 0.25 }, { 0.375, -1.5 }, { 0.625, -1.0 }, { 0.875, -1.625 }, { 1.125, -1.125 } } do
		box(m, f, on(2.25), p[1], p[2], 0.25, 0.25, 0.5, if k % 2 == 0 then "slate" else "rock_dark", "Stone")
	end
	-- the steps and stepping stones up the middle
	box(m, f, 0, 0.25, 2.0, 0.75, 0.25, 0.25, "rock", "Step")
	box(m, f, 0, 0.625, 0.75, 0.75, 0.25, 0.25, "rock", "Step")
	box(m, f, 0, 1.125, -0.5, 0.75, 0.25, 0.25, "rock", "Step")
	for _, t in steps do
		box(m, f, 0, on(t[2]), t[1], 0.5, 0.25, 0.75, "pavement", "SteppingStone")
	end
	-- flowers: two rows on each bed, clear of the hives and the steps
	local cols = { "pink", "yellow", "purple", "white", "orange", "berry_red" }
	local beds: { { any } } = {
		{ 1.25, 0.5, { -2.0, -1.5, -1.0, -0.5, 0.5, 1.0 } },
		{ 0.0, 1.0, { -1.0, -0.5, 0.5, 1.0 } },
		{ -1.25, 1.5, { -1.0, -0.5, 0.5, 1.0 } },
	}
	local n = 0
	for _, b in beds do
		for _, dz in { -0.25, 0.25 } do
			for _, x in b[3] do
				n += 1
				ball(m, f, x, b[2] + 0.125, b[1] + dz, 0.5, if n % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
				box(m, f, x + 0.06, b[2] + 0.375, b[1] + dz + 0.06, 0.25, 0.25, 0.25, cols[n % #cols + 1], "Flower")
			end
		end
	end
	-- the hives, and bees about them
	local hives: { { any } } = {
		{ 1.75, 0.5, 1.25, "white", "yellow" },
		{ -1.75, 1.0, 0.0, "pink", "cream" },
		{ 1.75, 1.0, 0.0, "blue", "white" },
		{ -1.75, 1.5, -1.25, "cream", "yellow" },
		{ 1.75, 1.5, -1.25, "white", "pink" },
	}
	for k, h in hives do
		hive(m, f, h[1], h[2], h[3], h[4], h[5])
		local s = if h[1] > 0 then -1 else 1
		ball(m, f, h[1] + s * 0.625, h[2] + 1.25, h[3] + 0.5, 0.25, "yellow", "Bee")
		ball(m, f, h[1] + s * 0.25, h[2] + 1.75 - (k % 2) * 0.25, h[3] + 0.375, 0.25, "yellow", "Bee")
	end
	-- the honey stand under its awning
	box(m, f, -1.5, 0.375, 2.25, 1.5, 0.5, 0.25, "wood", "Stand")
	box(m, f, -1.5, 0.75, 2.25, 1.75, 0.25, 0.5, "wood_dark", "StandTop")
	for _, x in { -2.0, -1.0 } do
		box(m, f, x, 0.375, on(2.375), 0.25, 0.5, 0.25, "wood_dark", "Plank")
	end
	box(m, f, -1.5, 0.5, on(2.375) + 0.03, 1.0, 0.25, 0.25, "gold", "HoneyBand")
	for _, x in { -2.0, -1.625, -1.25 } do
		box(m, f, x, 1.0, 2.25, 0.25, 0.25, 0.25, "gold", "Jar")
		box(m, f, x, 1.25, 2.25, 0.25, 0.25, 0.25, "white", "JarLid")
	end
	cyl(m, f, -0.875, 1.125, 2.25, 0.5, 0.5, "orange", "HoneyPot")
	put(m, f, CFrame.new(-0.81, 1.5, 2.19) * CFrame.Angles(0, 0, -0.4), 0.25, 0.5, 0.25, "wood", "Dipper")
	for _, x in { -2.375, -0.625 } do
		box(m, f, x, 0.875, 2.25, 0.25, 1.5, 0.25, "wood", "AwningPost")
	end
	for k, x in { -2.25, -1.75, -1.25, -0.75 } do
		put(m, f, CFrame.new(x, 1.75, 2.0) * CFrame.Angles(0.35, 0, 0), 0.5, 0.25, 0.75, if k % 2 == 1 then "yellow" else "white", "Awning")
	end
	box(m, f, -1.5, 1.375, 2.25, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, -1.5, 1.625, 2.25, 0.25, 0.25, 0.25, "black", "LanternCap")
	-- across the steps: the beekeeper's crate, hat and smoker, a lantern
	crate(m, f, 1.25, 0.125, 2.125, 0.5)
	cyl(m, f, 1.25, 0.75, 2.125, 0.75, 0.25, "white", "HatBrim")
	cyl(m, f, 1.25, 1.0, 2.125, 0.5, 0.25, "white", "Hat")
	cyl(m, f, 1.75, 0.375, 2.125, 0.25, 0.5, "steel", "Smoker")
	box(m, f, 1.75, 0.75, 2.125, 0.25, 0.25, 0.25, "steel_dark", "SmokerSpout")
	lantern(m, f, 0.625, 0.125, 2.125)
end

-- Half a row of vines along X from x0 to x1 at z: a post at each end, a rail between, three clumps of leaves along
-- it, two twisted trunks and two bunches of grapes hanging on the side that shows, a ridge of earth under it.
local function vineRow(m: Instance, f: CFrame, x0: number, x1: number, z: number, k: number)
	local mid, len = (x0 + x1) / 2, x1 - x0
	box(m, f, mid, on(0.125), z, len, 0.25, 0.5, "hair_brown", "Ridge")
	for _, x in { x0, x1 } do
		box(m, f, x, 0.625, z, 0.25, 1.0, 0.25, "wood_dark", "VinePost")
	end
	box(m, f, mid, 1.0, z, len, 0.25, 0.25, "wood", "Rail")
	for i = 0, 2 do
		ball(m, f, x0 + len * (i + 0.5) / 3, 1.0, z + 0.06, 0.5, if (i + k) % 2 == 0 then "leaf" else "leaf_dark", "Vine")
	end
	for i = 1, 2 do
		local x = x0 + len * i / 3
		box(m, f, x, 0.375, z - 0.125, 0.25, 0.5, 0.25, "wood_dark", "VineTrunk")
		ball(m, f, x, 0.69, z + 0.19, 0.25, "purple", "Grapes")
		ball(m, f, x + 0.06, 0.5, z + 0.25, 0.25, if (i + k) % 3 == 0 then "berry_red" else "purple", "Grapes")
	end
end

-- Grand Vineyard (5 x 5): three rows of vines on posts and rails, bunches of grapes under the leaves and ridges of
-- earth beneath them, stepping stones up the middle with a lantern on the posts either side. At the back the press
-- house: cream walls on a stone base with dark corner posts, a brick-red shingled roof with a stone chimney and a
-- round vent in its gable, double doors over a step, shuttered windows with boxes of flowers, a side window and a
-- hanging sign with grapes on it. In the yard a wine press heaped with grapes, barrels on a cradle and a basket.
B.vineyard = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 5, "sand_dark", "Soil")
	-- the press house (x -1.75 .. 2.25, z -2.25 .. -0.75)
	local cx, cz = 0.25, -1.5
	box(m, f, cx, 0.25, cz, 4.0, 0.25, 1.5, "rock", "Base")
	box(m, f, cx, 1.125, cz, 4.0, 1.5, 1.5, "cream", "Walls")
	for _, p in { { -1.75, -0.75 }, { 2.25, -0.75 }, { 2.25, -2.25 } } do
		box(m, f, p[1], 1.0, p[2], 0.25, 1.75, 0.25, "wood_dark", "Corner")
	end
	-- the double doors and their step
	box(m, f, cx, 0.875, on(-0.75), 1.25, 1.5, 0.25, "wood_dark", "DoorFrame")
	for _, s in { -1, 1 } do
		box(m, f, cx + s * 0.25, 0.875, on(-0.705), 0.5, 1.25, 0.25, "wood", "Door")
		box(m, f, cx + s * 0.125, 0.875, on(-0.66), 0.25, 0.25, 0.25, "gold", "Handle")
	end
	box(m, f, cx, 0.5, on(-0.66), 1.0, 0.25, 0.25, "wood_dark", "Brace")
	box(m, f, cx, 0.125, -0.5, 1.25, 0.25, 0.5, "rock", "Step")
	-- the shuttered windows with flower boxes
	for k, x in { -1.0, 1.5 } do
		box(m, f, x, 1.375, on(-0.75), 0.75, 0.75, 0.25, "wood_dark", "WindowFrame")
		box(m, f, x, 1.375, on(-0.705), 0.5, 0.5, 0.25, "window", "Glass")
		for _, s in { -1, 1 } do
			box(m, f, x + s * 0.5, 1.375, on(-0.75), 0.25, 0.75, 0.25, "teal", "Shutter")
		end
		box(m, f, x, 0.875, -0.625, 0.75, 0.25, 0.25, "wood", "FlowerBox")
		for i, c in (if k == 1 then { "pink", "yellow" } else { "white", "berry_red" }) :: { string } do
			local bx = x - 0.375 + i * 0.25
			ball(m, f, bx, 1.06, -0.625, 0.5, if i == 1 then "leaf" else "leaf_dark", "Leaves")
			box(m, f, bx, 1.25, -0.5, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
	-- the side window
	box(m, f, on(2.25), 1.25, -1.5, 0.25, 0.75, 0.75, "wood_dark", "WindowFrame")
	box(m, f, on(2.295), 1.25, -1.5, 0.25, 0.5, 0.5, "window", "Glass")
	box(m, f, 2.375, 0.875, -1.5, 0.25, 0.25, 0.75, "wood_dark", "Sill")
	-- the roof, its vent and chimney
	gable(m, f * CFrame.new(cx, 0, cz), 1.875, 4.0, 1.5, 0.75, "brick", "clay", "wood_dark", "cream", 0, 0)
	put(m, f, CFrame.new(on(2.25), 2.25, cz), 0.25, 0.5, 0.5, "wood_dark", "Vent", "Cylinder")
	box(m, f, 1.5, 2.75, -1.875, 0.5, 1.0, 0.5, "rock", "Chimney")
	box(m, f, 1.5, 3.375, -1.875, 0.75, 0.25, 0.75, "rock_dark", "ChimneyCap")
	-- the hanging sign off the front corner
	box(m, f, 2.25, 1.75, -0.5, 0.25, 0.25, 0.5, "wood_dark", "SignArm")
	box(m, f, 2.25, 1.375, -0.375, 0.25, 0.5, 0.5, "wood", "Sign")
	for _, p in { { 1.5, -0.5 }, { 1.5, -0.25 }, { 1.25, -0.375 } } do
		box(m, f, on(2.375), p[1], p[2], 0.25, 0.25, 0.25, "purple", "SignGrapes")
	end
	-- the rows of vines, the stones up the middle, lanterns on the front posts
	for k, z in { 0.875, 1.5, 2.125 } do
		vineRow(m, f, -2.25, -0.5, z, k)
		vineRow(m, f, 0.5, 1.875, z, k + 1)
	end
	for _, z in { 2.25, 1.625, 1.0, 0.375 } do
		box(m, f, 0, on(0.125), z, 0.5, 0.25, 0.5, "pavement", "SteppingStone")
	end
	for _, x in { -0.5, 0.5 } do
		lantern(m, f, x, 1.125, 2.125)
	end
	-- the wine press: a hooped tub heaped with grapes, the frame and its screw
	cyl(m, f, -1.25, 0.375, -0.125, 1.0, 0.5, "wood", "Tub")
	cyl(m, f, -1.25, 0.375, -0.125, 1.25, 0.25, "steel_dark", "Hoop")
	ball(m, f, -1.25, 0.625, -0.125, 0.75, "purple", "Grapes")
	for _, x in { -1.875, -0.625 } do
		box(m, f, x, 0.75, -0.125, 0.25, 1.25, 0.25, "wood_dark", "PressPost")
	end
	box(m, f, -1.25, 1.5, -0.125, 1.5, 0.25, 0.25, "wood_dark", "PressBeam")
	cyl(m, f, -1.25, 1.125, -0.125, 0.25, 0.5, "steel", "Screw")
	box(m, f, -1.25, 1.25, -0.125, 0.75, 0.25, 0.25, "steel", "PressBar")
	-- barrels lying on a cradle, a basket of grapes
	for _, z in { -0.5, 0.0 } do
		box(m, f, 1.625, 0.25, z, 1.5, 0.25, 0.25, "wood_dark", "Cradle")
	end
	for _, x in { 1.25, 2.0 } do
		rodZ(m, f, x, 0.75, -0.25, 0.75, 0.75, "wood", "Barrel")
		rodZ(m, f, x, 0.75, on(0.125), 0.5, 0.25, "wood_dark", "BarrelEnd")
	end
	box(m, f, 0.5, 0.25, 0.0, 0.5, 0.25, 0.5, "straw", "Basket")
	ball(m, f, 0.44, 0.44, 0.0, 0.25, "purple", "Grapes")
	ball(m, f, 0.56, 0.44, 0.06, 0.25, "purple", "Grapes")
end

return B
