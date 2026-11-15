--!strict
-- The island's the farms (kind "farm": what grows or is caught to sell), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
-- the footprint's centre on the grass (facing +Z before the piece's turn) and the level, and stays inside the
-- footprint. The pieces they share are Models/BuildKit's. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.")
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local roof = K.roof
local window = K.window
local door = K.door
local barrel = K.barrel
local sack = K.sack
local pot = K.pot
local footing = K.footing
local fence = K.fence
local fenceZ = K.fenceZ
local lamp = K.lamp
local fruitTree = K.fruitTree
local storey = K.storey
local blades = K.blades
local cap = K.cap

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

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

return B
