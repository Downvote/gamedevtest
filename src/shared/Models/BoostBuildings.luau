--!strict
-- The island's the boost buildings (kind "gen": every building of a knack makes more), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model, the frame at
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
local barrel = K.barrel
local sack = K.sack
local footing = K.footing
local storey = K.storey
local flatRoof = K.flatRoof
local streetLamp = K.streetLamp

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
local B: { [string]: Builder } = {}

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

return B
