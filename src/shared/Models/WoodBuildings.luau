--!strict
-- The island's the wood buildings (kind "wood"), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
-- the footprint's centre on the grass (facing +Z before the piece's turn) and the level, and stays inside the
-- footprint. The pieces they share are Models/BuildKit's. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.")
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local log = K.log
local wedge = K.wedge
local roof = K.roof
local window = K.window
local door = K.door
local crate = K.crate
local footing = K.footing
local storey = K.storey
local span = K.span

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

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

return B
