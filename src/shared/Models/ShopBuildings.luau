--!strict
-- The island's the shops (kind "shop"), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
-- the footprint's centre on the grass (facing +Z before the piece's turn) and the level, and stays inside the
-- footprint. The pieces they share are Models/BuildKit's. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.")
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local wedge = K.wedge
local roof = K.roof
local window = K.window
local sideWindow = K.sideWindow
local door = K.door
local barrel = K.barrel
local sack = K.sack
local pot = K.pot
local footing = K.footing
local awning = K.awning
local storey = K.storey
local flatRoof = K.flatRoof
local streetLamp = K.streetLamp
local span = K.span

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

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

return B
