--!strict
-- The office diorama from parts (docs/ARCHITECTURE.md 6; GAME_DESIGN 2, 7). Roblox module (server: PlotService builds
-- it into Workspace.Plots.Plot_<i>.Static; the preview tools build the same). Built from Data/Office's plan for the
-- tier: the lot, the floor, the two back walls with their trim, windows and the garage door, the low rim on the open
-- sides, the desks (desk, chair, monitor, keyboard, a mug) and the furniture. Every model faces +Z before its prop's
-- `rot` turns it (degrees about Y: 90 faces east, for the west wall; 0 faces south, for the north wall).
local Office = require(script.Parent.Parent.Data.Office)
local Blocks = require(script.Parent.Blocks)

local OfficeModels = {}

type Ctx = { parent: Instance, origin: Vector3, theme: string }

-- An axis-aligned box in a model's frame: centre (x, y, z) from the frame, size (w, h, d).
local function box(parent: Instance, frame: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(parent, {
		size = Vector3.new(w, h, d),
		cf = frame * CFrame.new(x, y, z),
		color = color,
		name = name,
		neon = neon,
	})
end

local function cylY(parent: Instance, frame: CFrame, x: number, y: number, z: number, dia: number, h: number, color: string): BasePart
	return Blocks.cylY(parent, dia, h, frame * CFrame.new(x, y, z), color)
end

local function ball(parent: Instance, frame: CFrame, x: number, y: number, z: number, dia: number, color: string): BasePart
	return Blocks.part(parent, { size = Vector3.new(dia, dia, dia), cf = frame * CFrame.new(x, y, z), color = color, shape = "Ball" })
end

------------------------------------------------------------------ the room
local FLOOR_TILE: { [string]: { w: number, d: number } } = {
	garage = { w = 4, d = 4 }, -- big concrete slabs
	loft = { w = 26, d = 1 }, -- planks along X (a plank per row, two tones)
	studio = { w = 2, d = 2 }, -- carpet tiles
}

local function room(c: Ctx, plan: Office.Plan, model: Model)
	local o = CFrame.new(c.origin)
	local minX, maxX, minZ, maxZ = plan.minX, plan.maxX, plan.minZ, plan.maxZ
	local t = Office.WALL_T
	local h = plan.wallH
	-- (the lawn, the footpath and the street round the room: Models/StreetModels)
	-- the floor slab and its tiles (floor_a under, floor_b tiles in a checker on top)
	local floor = Blocks.model(model, "Floor")
	box(floor, o, (minX + maxX) / 2, -0.375, (minZ + maxZ) / 2, maxX - minX, 0.5, maxZ - minZ, "floor_a", "Slab")
	local tile = FLOOR_TILE[plan.theme] or FLOOR_TILE.studio
	local tw, td = math.min(tile.w, maxX - minX), tile.d
	local nx, nz = math.floor((maxX - minX) / tw + 0.5), math.floor((maxZ - minZ) / td + 0.5)
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			if (ix + iz) % 2 == 1 then
				box(floor, o, minX + (ix + 0.5) * tw, -0.125, minZ + (iz + 0.5) * td, tw, 0.25, td, "floor_b", "Tile")
			end
		end
	end
	-- the two back walls, the skirting along their foot and the crown on top
	local walls = Blocks.model(model, "Walls")
	box(walls, o, (minX - t + maxX) / 2, h / 2, minZ - t / 2, maxX - minX + t, h, t, "wall", "NorthWall")
	box(walls, o, minX - t / 2, h / 2, (minZ + maxZ) / 2, t, h, maxZ - minZ, "wall", "WestWall")
	box(walls, o, (minX + maxX) / 2, 0.25, minZ + 0.125, maxX - minX, 0.5, 0.25, "wall_trim", "Skirting")
	box(walls, o, minX + 0.125, 0.25, (minZ + maxZ) / 2, 0.25, 0.5, maxZ - minZ - 0.25, "wall_trim", "Skirting")
	box(walls, o, (minX - t + maxX) / 2, h + 0.25, minZ - t / 2, maxX - minX + t + 0.5, 0.5, t + 0.5, "wall_trim", "Crown")
	box(walls, o, minX - t / 2, h + 0.25, (minZ + maxZ) / 2 + 0.25, t + 0.5, 0.5, maxZ - minZ - 0.5, "wall_trim", "Crown")
	-- the low rim along the open sides (a gap on the south side: the way in)
	-- (it does not collide: the founder steps in and out over it, through the doorway or not)
	local rim = Office.RIM_H
	local gapX0, gapX1 = maxX - 6, maxX - 3
	box(walls, o, (minX + gapX0) / 2 - t / 2, rim / 2, maxZ - 0.25, gapX0 - minX + t, rim, 0.5, "wall_trim", "Rim").CanCollide = false
	box(walls, o, (gapX1 + maxX) / 2, rim / 2, maxZ - 0.25, maxX - gapX1, rim, 0.5, "wall_trim", "Rim").CanCollide = false
	box(walls, o, maxX - 0.25, rim / 2, (minZ - t + maxZ - 0.5) / 2, 0.5, rim, maxZ - 0.5 - minZ + t, "wall_trim", "Rim").CanCollide = false
	-- the doorstep in the gap
	box(walls, o, (gapX0 + gapX1) / 2, -0.125, maxZ + 0.5, gapX1 - gapX0, 0.25, 1, "pavement", "Doorstep")
	-- windows in the north wall: a frame, the pane and a sill
	for _, w in plan.windows do
		local f = o * CFrame.new(w.at, 0, minZ)
		box(walls, f, 0, 4.6, 0.05, w.w + 0.5, 3.4, 0.25, "wall_trim", "WindowFrame")
		box(walls, f, 0, 4.6, 0.15, w.w - 0.25, 2.75, 0.25, "window", "Pane")
		box(walls, f, 0, 4.6, 0.2, 0.25, 2.75, 0.25, "wall_trim", "Mullion")
		box(walls, f, 0, 3.0, 0.3, w.w + 0.75, 0.25, 0.5, "wall_trim", "Sill")
	end
end

------------------------------------------------------------------ desks
local DESK_LOOK: { [number]: { top: string, legs: string, chair: string } } = {
	{ top = "wood", legs = "wood_dark", chair = "steel_dark" },
	{ top = "desk", legs = "wood_dark", chair = "berry_red" },
	{ top = "plastic", legs = "steel", chair = "blue" },
}

local function desk(c: Ctx, plan: Office.Plan, i: number, a: Office.Anchor, parent: Instance)
	local look = DESK_LOOK[plan.tier] or DESK_LOOK[1]
	local m = Blocks.model(nil, "Desk_" .. i)
	m:SetAttribute("Desk", i)
	local f = CFrame.new(c.origin + Vector3.new(a.x, 0, a.z))
	local W, D, H = Office.DESK_W, Office.DESK_D, Office.DESK_H
	-- desk: the top and two side panels
	box(m, f, 0, H - 0.125, 0, W, 0.25, D, look.top, "Top")
	box(m, f, -W / 2 + 0.25, (H - 0.25) / 2, 0, 0.25, H - 0.25, D - 0.25, look.legs, "Side")
	box(m, f, W / 2 - 0.25, (H - 0.25) / 2, 0, 0.25, H - 0.25, D - 0.25, look.legs, "Side")
	box(m, f, 0, H * 0.55, D / 2 - 0.375, W - 0.5, H * 0.5, 0.25, look.legs, "Modesty")
	-- the monitor at the south-west corner, its back to the camera: casing, a stand and a power light
	local mf = f * CFrame.new(-0.85, H, 0.45) * CFrame.Angles(0, math.rad(-12), 0)
	box(m, mf, 0, 0.125, 0, 0.75, 0.25, 0.5, "steel_dark", "Stand")
	box(m, mf, 0, 0.5, 0.1, 0.25, 0.5, 0.25, "steel_dark", "Neck")
	box(m, mf, 0, 1.25, 0, 1.75, 1.25, 0.5, "plastic", "Monitor")
	box(m, mf, 0, 1.25, -0.27, 1.5, 1, 0.25, "screen_off", "Screen")
	box(m, mf, 0.6, 0.8, 0.27, 0.25, 0.25, 0.25, "screen_code", "Light", true)
	-- keyboard and mouse in front of the seat, a mug
	box(m, f, 0.15, H + 0.125, -0.45, 1.5, 0.25, 0.5, "plastic_dark", "Keyboard")
	box(m, f, 1.15, H + 0.125, -0.45, 0.25, 0.25, 0.5, "plastic_dark", "Mouse")
	cylY(m, f, 1.45, H + 0.375, 0.45, 0.5, 0.5, if i % 2 == 0 then "orange" else "white")
	-- the chair behind the seat
	local sx, sy, sz = Office.seat(a)
	local cf = CFrame.new(c.origin + Vector3.new(sx, 0, sz))
	box(m, cf, 0, sy - 0.125, 0, 1.5, 0.25, 1.5, look.chair, "Seat")
	box(m, cf, 0, sy + 0.9, -0.75, 1.5, 1.75, 0.25, look.chair, "Back")
	box(m, cf, 0, sy / 2 - 0.1, 0, 0.25, sy - 0.25, 0.25, "steel_dark", "Post")
	box(m, cf, 0, 0.125, 0, 1.25, 0.25, 0.25, "steel_dark", "Base")
	box(m, cf, 0, 0.125, 0, 0.25, 0.25, 1.25, "steel_dark", "Base")
	m.Parent = parent
end

------------------------------------------------------------------ furniture
type Builder = (m: Model, f: CFrame, prop: Office.Prop, c: Ctx) -> ()

local PROPS: { [string]: Builder } = {}

PROPS.garage_door = function(m, f)
	-- a roll-up door in the north wall: frame and slats (f sits on the wall's inner face)
	box(m, f, 0, 3.1, 0.06, 8.5, 6.25, 0.25, "steel_dark", "DoorFrame")
	for k = 0, 7 do
		box(m, f, 0, 0.5 + k * 0.75, 0.16, 7.75, 0.5, 0.25, if k % 2 == 0 then "steel" else "plastic", "Slat")
	end
	box(m, f, 0, 0.25, 0.25, 2, 0.25, 0.25, "steel_dark", "Handle")
end

PROPS.shelf = function(m, f)
	-- a metal shelf unit with boxes and odds and ends (faces +Z before rot)
	for _, x in { -1.75, 1.75 } do
		box(m, f, x, 2.5, -0.5, 0.25, 5, 0.25, "steel_dark", "Post")
		box(m, f, x, 2.5, 0.5, 0.25, 5, 0.25, "steel_dark", "Post")
	end
	for k = 0, 3 do
		box(m, f, 0, 0.5 + k * 1.4, 0, 3.75, 0.25, 1.25, "steel", "Board")
	end
	box(m, f, -1, 1.0, 0, 1.25, 0.75, 1, "wood", "Box")
	box(m, f, 0.75, 1.1, 0, 1.25, 1, 1, "wood_dark", "Box")
	box(m, f, -0.75, 2.4, 0, 1.5, 0.75, 0.9, "orange", "Toolbox")
	box(m, f, 1, 2.35, 0.1, 0.75, 0.5, 0.75, "berry_red", "Can")
	box(m, f, 0, 3.75, 0, 2.5, 0.75, 1, "wood", "Box")
end

PROPS.boxes = function(m, f)
	box(m, f, 0, 0.6, 0, 1.75, 1.25, 1.5, "wood", "Box")
	box(m, f, 1.4, 0.5, 0.2, 1.25, 1, 1.25, "wood_dark", "Box")
	box(m, f, 0.25, 1.75, 0, 1.25, 1, 1.25, "wood", "Box")
	box(m, f, 0.25, 1.75, 0.65, 0.75, 0.25, 0.25, "paper", "Label")
end

PROPS.plant = function(m, f)
	cylY(m, f, 0, 0.6, 0, 1.25, 1.25, "pot")
	cylY(m, f, 0, 1.3, 0, 1.0, 0.25, "wood_dark")
	ball(m, f, 0, 2.2, 0, 1.75, "leaf")
	ball(m, f, -0.5, 2.7, 0.25, 1.0, "leaf_dark")
	ball(m, f, 0.45, 2.9, -0.2, 1.0, "leaf")
	ball(m, f, 0.1, 3.3, 0.1, 0.75, "leaf_dark")
end

PROPS.lamp = function(m, f)
	box(m, f, 0, 0.125, 0, 1, 0.25, 1, "steel_dark", "Foot")
	box(m, f, 0, 2.25, 0, 0.25, 4, 0.25, "steel_dark", "Pole")
	box(m, f, 0, 4.4, 0, 1.25, 0.75, 1.25, "cream", "Shade")
	box(m, f, 0, 4.0, 0, 0.5, 0.25, 0.5, "yellow", "Bulb", true)
end

PROPS.beanbag = function(m, f)
	box(m, f, 0, 0.4, 0, 2.25, 0.75, 2, "purple", "Bag")
	box(m, f, 0, 1.0, -0.5, 2, 0.75, 1, "purple", "Bag")
	box(m, f, 0, 0.9, 0.2, 1.5, 0.25, 1.25, "pink", "Dent")
end

PROPS.cooler = function(m, f)
	box(m, f, 0, 1.25, 0, 1.25, 2.5, 1.25, "plastic", "Body")
	box(m, f, 0, 1.6, 0.65, 0.5, 0.25, 0.25, "blue", "Tap")
	cylY(m, f, 0, 3.1, 0, 1.0, 1.25, "window")
	box(m, f, 0, 3.85, 0, 0.5, 0.25, 0.5, "blue", "Cap")
end

-- A rain barrel: staves, two iron hoops, a lid with a ladle.
PROPS.barrel = function(m, f)
	cylY(m, f, 0, 1.25, 0, 1.75, 2.5, "wood")
	cylY(m, f, 0, 0.5, 0, 1.875, 0.25, "steel_dark")
	cylY(m, f, 0, 2.0, 0, 1.875, 0.25, "steel_dark")
	cylY(m, f, 0, 2.6, 0, 1.5, 0.25, "wood_dark")
	box(m, f, 0.35, 2.95, 0, 0.25, 0.5, 0.25, "steel", "Ladle")
end

-- A sea chest: a wooden box, a gold band and lock, a coil of rope on its lid.
PROPS.seachest = function(m, f)
	box(m, f, 0, 0.75, 0, 2.5, 1.5, 1.5, "wood_dark", "Chest")
	box(m, f, 0, 1.6, 0, 2.6, 0.25, 1.6, "wood", "Lid")
	box(m, f, 0, 0.9, 0.76, 2.6, 0.25, 0.1, "gold", "Band")
	box(m, f, 0, 1.1, 0.8, 0.5, 0.5, 0.15, "gold", "Lock")
	cylY(m, f, -0.6, 1.85, 0, 1.0, 0.25, "sand_dark")
end

-- A sea chart pinned to a wall (f: the wall's inner face): the paper, three islands, a dotted route, a red mark.
PROPS.chart = function(m, f)
	box(m, f, 0, 0, 0.06, 4.25, 2.75, 0.25, "wood_dark", "Frame")
	box(m, f, 0, 0, 0.16, 4.0, 2.5, 0.25, "cream", "Paper")
	box(m, f, -1.2, 0.5, 0.26, 1.0, 0.75, 0.25, "leaf", "Isle")
	box(m, f, 0.9, -0.4, 0.26, 0.75, 0.5, 0.25, "leaf", "Isle")
	box(m, f, 1.4, 0.7, 0.26, 0.5, 0.5, 0.25, "sand_dark", "Isle")
	for k = 0, 3 do
		box(m, f, -0.6 + k * 0.4, 0.1 - k * 0.12, 0.26, 0.25, 0.25, 0.25, "ink", "Route")
	end
	box(m, f, 0.9, -0.4, 0.36, 0.25, 0.25, 0.25, "berry_red", "Mark")
end

PROPS.poster = function(m, f)
	-- a framed game poster on a wall (f: the wall's inner face at the prop's height)
	box(m, f, 0, 0, 0.06, 2.5, 3.25, 0.25, "ink", "Frame")
	box(m, f, 0, 0.1, 0.16, 2.25, 3.0, 0.25, "blue", "Print")
	box(m, f, 0, 0.6, 0.26, 1.5, 1.25, 0.25, "yellow", "Hero")
	box(m, f, 0, -0.9, 0.26, 1.75, 0.5, 0.25, "berry_red", "Logo")
end

PROPS.bookcase = function(m, f)
	box(m, f, 0, 2.5, -0.375, 3.5, 5, 0.25, "wood_dark", "Back")
	for _, x in { -1.625, 1.625 } do
		box(m, f, x, 2.5, 0, 0.25, 5, 1, "wood", "Side")
	end
	local books = { "berry_red", "blue", "green", "yellow", "purple", "orange", "cream" }
	for k = 0, 3 do
		box(m, f, 0, 0.125 + k * 1.25, 0, 3, 0.25, 1, "wood", "Board")
		local x = -1.3
		for b = 1, 5 do
			local w = 0.25 + ((b + k) % 3) * 0.25
			local hgt = 0.75 + ((b * 3 + k) % 2) * 0.25
			box(m, f, x + w / 2, 0.25 + k * 1.25 + hgt / 2, 0, w, hgt, 0.75, books[(b + k * 2) % #books + 1], "Book")
			x += w + 0.1
		end
	end
	box(m, f, 0, 5.125, 0, 3.5, 0.25, 1.25, "wood", "Top")
end

PROPS.whiteboard = function(m, f)
	box(m, f, 0, 0, 0.06, 4.5, 2.75, 0.25, "steel", "Frame")
	box(m, f, 0, 0, 0.16, 4.25, 2.5, 0.25, "paper", "Board")
	box(m, f, -1, 0.5, 0.26, 1.5, 0.25, 0.25, "blue", "Note")
	box(m, f, 0.75, 0.25, 0.26, 1.75, 0.25, 0.25, "berry_red", "Note")
	box(m, f, -0.5, -0.25, 0.26, 2.5, 0.25, 0.25, "green", "Note")
	box(m, f, 1.4, -0.75, 0.26, 0.75, 0.75, 0.25, "yellow", "Sticky")
	box(m, f, 0, -1.375, 0.35, 3.5, 0.25, 0.5, "steel", "Tray")
end

PROPS.coffee = function(m, f)
	box(m, f, 0, 1, 0, 2.5, 2, 1.5, "wood", "Counter")
	box(m, f, 0, 2.125, 0, 2.75, 0.25, 1.75, "plastic", "Worktop")
	box(m, f, -0.5, 2.9, -0.2, 1.25, 1.5, 1, "black", "Machine")
	box(m, f, -0.5, 3.0, 0.35, 0.75, 0.25, 0.25, "berry_red", "Light", true)
	cylY(m, f, -0.5, 2.5, 0.25, 0.5, 0.5, "white")
	cylY(m, f, 0.75, 2.5, 0.1, 0.5, 0.5, "orange")
end

PROPS.rug = function(m, f)
	box(m, f, 0, 0.05, 0, 5.5, 0.25, 3.5, "rug", "Rug")
	box(m, f, 0, 0.1, 0, 4.5, 0.25, 2.5, "orange", "Inner")
end

PROPS.sofa = function(m, f)
	box(m, f, 0, 0.6, 0, 4.5, 1, 1.75, "sofa", "Seat")
	box(m, f, 0, 1.6, -0.75, 4.5, 1.25, 0.5, "sofa", "Back")
	box(m, f, -2.1, 1.1, 0, 0.5, 1.25, 1.75, "sofa", "Arm")
	box(m, f, 2.1, 1.1, 0, 0.5, 1.25, 1.75, "sofa", "Arm")
	box(m, f, -1, 1.2, 0.1, 1.75, 0.25, 1.25, "pink", "Cushion")
	box(m, f, 1, 1.2, 0.1, 1.75, 0.25, 1.25, "pink", "Cushion")
end

PROPS.server = function(m, f)
	box(m, f, 0, 2.5, 0, 2, 5, 1.75, "black", "Rack")
	for k = 0, 5 do
		box(m, f, 0, 0.75 + k * 0.7, 0.9, 1.75, 0.5, 0.25, "steel_dark", "Unit")
		box(m, f, 0.6, 0.75 + k * 0.7, 1.02, 0.25, 0.25, 0.25, if k % 2 == 0 then "screen_code" else "screen_on", "Led", true)
	end
end

PROPS.trophies = function(m, f)
	box(m, f, 0, 1, 0, 3.5, 2, 1.25, "wood_dark", "Cabinet")
	box(m, f, 0, 2.1, 0, 3.75, 0.25, 1.5, "wood", "Top")
	for k, x in { -1.1, 0, 1.1 } do
		cylY(m, f, x, 2.45, 0, 0.75, 0.5, "wood_dark")
		cylY(m, f, x, 3.0, 0, 0.5, 0.75, "gold")
		ball(m, f, x, 3.6, 0, if k == 2 then 1.0 else 0.75, "gold")
	end
end

PROPS.tv = function(m, f)
	-- a big screen on a wall (f: the wall's inner face at the prop's height)
	box(m, f, 0, 0, 0.1, 5, 2.75, 0.25, "black", "Tv")
	box(m, f, 0, 0, 0.2, 4.5, 2.25, 0.25, "screen_on", "Picture", true)
	box(m, f, -1.2, -0.5, 0.3, 1, 0.75, 0.25, "green", "Sprite", true)
	box(m, f, 1, 0.4, 0.3, 0.75, 0.75, 0.25, "yellow", "Sprite", true)
end

PROPS.arcade = function(m, f)
	box(m, f, 0, 1.6, 0, 1.75, 3.2, 1.5, "purple", "Cabinet")
	box(m, f, 0, 2.6, 0.7, 1.5, 1.0, 0.25, "black", "Bezel")
	box(m, f, 0, 2.6, 0.8, 1.25, 0.75, 0.25, "screen_code", "Screen", true)
	box(m, f, 0, 1.8, 0.9, 1.75, 0.25, 0.75, "black", "Panel")
	ball(m, f, -0.4, 2.0, 1.0, 0.5, "berry_red")
	ball(m, f, 0.4, 2.0, 1.0, 0.5, "yellow")
	box(m, f, 0, 3.4, 0, 1.75, 0.5, 1.5, "pink", "Marquee", true)
end

-- Where a prop stands: wall pieces (garage door, poster, whiteboard, tv) hang on the inner face of their wall.
local function propFrame(c: Ctx, plan: Office.Plan, p: Office.Prop): CFrame
	local x, z = p.x, p.z
	local y = p.y or 0
	if p.kind == "garage_door" or p.kind == "whiteboard" or p.kind == "chart" or (p.kind == "tv" and p.rot == 0) or (p.kind == "poster" and p.rot == 0) then
		z = plan.minZ
	elseif p.kind == "poster" or p.kind == "tv" then
		x = plan.minX
	end
	return CFrame.new(c.origin + Vector3.new(x, y, z)) * CFrame.Angles(0, math.rad(p.rot), 0)
end

------------------------------------------------------------------ build
-- Builds the office of `tier` under `parent` with the plot's origin at `origin`. Returns the room model.
function OfficeModels.build(parent: Instance, tier: number, origin: Vector3): Model
	local plan = Office.plan(tier)
	local c: Ctx = { parent = parent, origin = origin, theme = plan.theme }
	local model = Blocks.model(nil, "Office")
	model:SetAttribute("Tier", plan.tier)
	room(c, plan, model)
	local desks = Blocks.model(model, "Desks")
	for i, a in plan.desks do
		desk(c, plan, i, a, desks)
	end
	local props = Blocks.model(model, "Props")
	for i, p in plan.props do
		local fn = PROPS[p.kind]
		if fn then
			local m = Blocks.model(nil, p.kind .. "_" .. i)
			fn(m, propFrame(c, plan, p), p, c)
			m.Parent = props
		end
	end
	-- the theme's colours for the floor and walls (Palette.themes)
	OfficeModels.paint(model, plan.theme)
	model.Parent = parent
	return model
end

-- Floor and wall parts take their tier's theme colours (Palette.themes[theme]).
function OfficeModels.paint(model: Instance, theme: string)
	local Palette = require(script.Parent.Parent.Data.Palette)
	local t = Palette.themes[theme]
	if t == nil then
		return
	end
	local keys: { [string]: string } = { Slab = "floor_a", Tile = "floor_b", NorthWall = "wall", WestWall = "wall", Skirting = "wall_trim", Crown = "wall_trim", Rim = "wall_trim", WindowFrame = "wall_trim", Sill = "wall_trim", Mullion = "wall_trim" }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local key = keys[d.Name]
			local hex = if key then t[key] else nil
			if hex then
				local c = Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
				d.Color = c
			end
		end
	end
end

return OfficeModels
