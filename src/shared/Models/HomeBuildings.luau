--!strict
-- The island's the huts (kind "nest") and the Hatchery (kind "breed"), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
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
local sack = K.sack
local pot = K.pot
local footing = K.footing
local fence = K.fence
local storey = K.storey
local flatRoof = K.flatRoof
local roundDoor = K.roundDoor
local spire = K.spire

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

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
	box(m, f, 0, 1.2, -0.95, 0.5, 1.8, 0.08, "shallow", "Falls"):SetAttribute("PixelWater", 4) -- (streaks run down it)
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

return B
