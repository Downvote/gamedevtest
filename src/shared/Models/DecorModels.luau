--!strict
-- The plot's decor from parts (GAME_DESIGN 13; Data/Decor). Roblox module (server: PlotService builds the placed
-- pieces; client: Build mode's ghost and the decor box's pictures). `build(id, at)`: a model standing on `at` (the
-- footprint's centre on the lawn, already turned by the piece's rot), facing +Z before the turn, its footprint
-- Data/Decor's w x d. Pieces do not collide (the founder walks through them, never stuck behind one).
local Blocks = require(script.Parent.Blocks)

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

-- A wheel standing up, its axle along the frame's X (a Roblox cylinder runs along X).
local function wheel(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, w: number): BasePart
	return Blocks.part(m, { size = Vector3.new(w, dia, dia), cf = f * CFrame.new(x, y, z), color = "black", shape = "Cylinder", name = "Wheel", collide = false })
end

local B: { [string]: Builder } = {}

B.gnome = function(m, f)
	box(m, f, 0, 0.35, 0, 0.75, 0.7, 0.6, "blue", "Body")
	ball(m, f, 0, 0.95, 0, 0.6, "skin1", "Head")
	box(m, f, 0, 0.95, 0.25, 0.5, 0.25, 0.25, "white", "Beard")
	box(m, f, 0, 1.35, 0, 0.5, 0.5, 0.5, "berry_red", "Hat")
	box(m, f, 0, 1.65, 0, 0.25, 0.25, 0.25, "berry_red", "Tip")
end

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

B.lamp = function(m, f)
	box(m, f, 0, 0.125, 0, 0.75, 0.25, 0.75, "steel_dark", "Foot")
	box(m, f, 0, 2.2, 0, 0.25, 4.2, 0.25, "steel_dark", "Pole")
	box(m, f, 0, 4.5, 0, 0.75, 0.5, 0.75, "steel_dark", "Cap")
	box(m, f, 0, 4.1, 0, 0.5, 0.5, 0.5, "yellow", "Lantern", true)
end

local function trunk(m: Model, f: CFrame, h: number)
	box(m, f, 0, h / 2, 0, 0.75, h, 0.75, "wood_dark", "Trunk")
end

B.oak = function(m, f)
	trunk(m, f, 3)
	ball(m, f, 0, 4, 0, 3, "leaf", "Crown")
	ball(m, f, -0.8, 3.5, 0.6, 2, "leaf_dark", "Crown")
	ball(m, f, 0.8, 3.7, -0.4, 2, "leaf", "Crown")
	ball(m, f, 0.1, 5.1, 0.1, 1.5, "leaf_dark", "Crown")
end

B.pine = function(m, f)
	trunk(m, f, 1.5)
	for k = 0, 3 do
		local s = 3 - k * 0.6
		box(m, f, 0, 1.6 + k * 1.1, 0, s, 1, s, if k % 2 == 0 then "leaf_dark" else "leaf", "Tier")
	end
	box(m, f, 0, 6.1, 0, 0.5, 0.5, 0.5, "leaf_dark", "Top")
end

B.bikes = function(m, f)
	box(m, f, 0, 0.1, 0, 3, 0.25, 0.75, "steel_dark", "Base")
	for k, x in { -1, 0, 1 } do
		box(m, f, x, 0.6, -0.4, 0.25, 1, 0.25, "steel", "Loop")
		if k ~= 2 then
			-- a bike parked across the rack: two wheels front and back, a frame between
			wheel(m, f, x + 0.25, 0.45, -0.45, 0.9, 0.25)
			wheel(m, f, x + 0.25, 0.45, 0.45, 0.9, 0.25)
			box(m, f, x + 0.25, 0.85, 0, 0.25, 0.25, 1, if k == 1 then "berry_red" else "blue", "Frame")
			box(m, f, x + 0.25, 1.05, -0.35, 0.25, 0.25, 0.25, "black", "Saddle")
		end
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

B.kiosk = function(m, f)
	box(m, f, 0, 1.4, 0, 1.75, 2.8, 1.5, "purple", "Cabinet")
	box(m, f, 0, 2.2, 0.7, 1.5, 0.9, 0.25, "black", "Bezel")
	box(m, f, 0, 2.2, 0.8, 1.25, 0.65, 0.25, "screen_code", "Screen", true)
	box(m, f, 0, 1.45, 0.9, 1.75, 0.25, 0.75, "black", "Panel")
	ball(m, f, -0.4, 1.65, 1.0, 0.4, "berry_red")
	ball(m, f, 0.4, 1.65, 1.0, 0.4, "yellow")
	box(m, f, 0, 3.05, 0, 1.75, 0.5, 1.5, "pink", "Marquee", true)
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
	-- a little pixel hero holding a controller up
	box(m, f, -0.3, 1.9, 0, 0.5, 1, 0.5, "gold", "Leg")
	box(m, f, 0.3, 1.9, 0, 0.5, 1, 0.5, "gold", "Leg")
	box(m, f, 0, 2.9, 0, 1.25, 1.1, 0.75, "gold", "Body")
	box(m, f, 0, 3.95, 0, 1.25, 1, 1, "gold", "Head")
	box(m, f, 0.8, 3.6, 0, 0.4, 1.4, 0.4, "gold", "Arm")
	box(m, f, 0.8, 4.4, 0, 0.9, 0.4, 0.4, "gold", "Controller")
end

B.dish = function(m, f)
	box(m, f, 0, 0.25, 0, 2.5, 0.5, 2.5, "steel_dark", "Base")
	box(m, f, 0, 1.2, 0, 0.5, 1.5, 0.5, "steel", "Mast")
	-- the bowl faces up and toward the south-east (the camera), so it reads as a dish: a rim and a deeper centre
	local tilt = f * CFrame.new(0, 2.7, 0) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(40), 0, 0)
	cyl(m, tilt, 0, 0, 0, 3, 0.5, "white", "Dish")
	cyl(m, tilt, 0, -0.35, 0, 1.75, 0.5, "plastic_dark", "Back")
	box(m, tilt, 0, 0.9, 0, 0.25, 1.5, 0.25, "steel", "Arm")
	box(m, tilt, 0, 1.75, 0, 0.5, 0.5, 0.5, "berry_red", "Feed", true)
end

B.billboard = function(m, f)
	for _, x in { -2.2, 2.2 } do
		box(m, f, x, 1.6, -0.3, 0.4, 3.2, 0.4, "steel_dark", "Leg")
	end
	box(m, f, 0, 4.4, 0, 6, 2.75, 0.5, "black", "Frame")
	box(m, f, 0, 4.4, 0.2, 5.5, 2.25, 0.25, "screen_on", "Board", true)
	box(m, f, -1.6, 4.1, 0.35, 1.5, 1.2, 0.25, "yellow", "Hero")
	box(m, f, 1.1, 4.8, 0.35, 2.5, 0.6, 0.25, "berry_red", "Logo")
	box(m, f, 1.1, 4.0, 0.35, 2, 0.4, 0.25, "white", "Tag")
end

B.truck = function(m, f)
	box(m, f, 0, 1.4, 0, 6, 2.2, 2.75, "white", "Body")
	box(m, f, -2.4, 1.2, 0, 1.2, 1.8, 2.75, "berry_red", "Cab")
	box(m, f, -2.7, 1.7, 0, 0.5, 0.8, 2.5, "window", "Windshield")
	box(m, f, 0.6, 1.6, 1.4, 3.5, 1, 0.25, "black", "Hatch")
	box(m, f, 0.6, 2.25, 1.6, 3.75, 0.25, 0.75, "orange", "Awning")
	box(m, f, 0.6, 2.75, 0, 2.5, 0.75, 0.5, "yellow", "Sign", true)
	-- wheels, axles along Z (a Roblox cylinder runs along X: turned a quarter about Y)
	for _, x in { -2.2, 1.8 } do
		for _, z in { -1.3, 1.3 } do
			wheel(m, f * CFrame.new(x, 0.45, z) * CFrame.Angles(0, math.rad(90), 0), 0, 0, 0, 0.9, 0.3)
		end
	end
end

-- The piece's model at `at` (the footprint's centre on the lawn, turned). Unknown ids build nothing.
function DecorModels.build(id: string, at: CFrame): Model
	local m = Blocks.model(nil, "Decor_" .. id)
	m:SetAttribute("Decor", id)
	local fn = B[id]
	if fn then
		fn(m, at)
	end
	return m
end

function DecorModels.has(id: string): boolean
	return B[id] ~= nil
end

return DecorModels
