--!strict
-- The shared pieces the island's buildings and decor are made of (docs/ARCHITECTURE.md 6; GAME_DESIGN 4): boxes, balls,
-- cylinders, logs, tubes and wedges on the 1/8-stud grid, roofs, windows, doors, crates, barrels, sacks, pots, footings,
-- fences, lamps, awnings, storeys, spans, round doors, mushroom caps, spires and the upgrade pennant. Every builder in
-- Models/DecorModels and the building groups (Farm, Wood, Shop, Home and BoostBuildings) uses these. Pure model code.
local Blocks = require(script.Parent.Blocks)

local BuildKit = {}

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

-- (sizes snap to the 0.25 grid: the straps and hoops stand a whole step proud, never on the body's own faces)
local function crate(m: Instance, f: CFrame, x: number, y: number, z: number, s: number)
	box(m, f, x, y + s / 2, z, s, s, s, "wood", "Crate")
	box(m, f, x, y + s / 2, z, s + 0.25, 0.25, s + 0.25, "wood_dark", "Strap")
end

local function barrel(m: Instance, f: CFrame, x: number, y: number, z: number, s: number?)
	local k = s or 1
	cyl(m, f, x, y + 0.5 * k, z, 0.8 * k, 1.0 * k, "wood", "Barrel")
	cyl(m, f, x, y + 0.2 * k, z, 0.8 * k + 0.25, 0.1, "steel_dark", "Hoop")
	cyl(m, f, x, y + 0.8 * k, z, 0.8 * k + 0.25, 0.1, "steel_dark", "Hoop")
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

local function awning(m: Model, f: CFrame, y: number, w: number, z: number, a: string?, b: string?)
	local n = math.max(2, math.floor(w / 0.5))
	for i = 0, n - 1 do
		local x = -w / 2 + (i + 0.5) * w / n
		Blocks.part(m, { size = Vector3.new(w / n, 0.12, 1.1), cf = f * CFrame.new(x, y, z) * CFrame.Angles(math.rad(-14), 0, 0), color = if i % 2 == 0 then a or "berry_red" else b or "white", name = "Awning", collide = false })
		box(m, f, x, y - 0.32, z + 0.53, w / n, 0.2, 0.06, if i % 2 == 0 then a or "berry_red" else b or "white", "Flap")
	end
end

-- A storey's box: walls of `color` w x h x d from y0 up at (x, z), a darker band its lowest 0.25 (the walls stand on
-- the band: the two never share a face, which would flicker).
local function storey(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, h: number, d: number, color: string, band: string?)
	box(m, f, x, y0 + 0.25 + (h - 0.25) / 2, z, w, h - 0.25, d, color, "Walls")
	box(m, f, x, y0 + 0.125, z, w, 0.25, d, band or "rock", "Band")
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

-- An upgraded building's pennant: a pole at its back-left corner (the corner every builder keeps clear), the flag red
-- at level 2, gold at 3. At level 3 a second flag, and a lit lantern on the pole's top for its knob (it stood on the
-- front corner once, where the reworked buildings keep their props).
local function pennant(m: Model, f: CFrame, lvl: number, w: number, d: number)
	local x, z = -w / 2 + 0.3, -d / 2 + 0.3
	box(m, f, x, 1.6, z, 0.15, 3.2, 0.15, "wood_dark", "PennantPole")
	wedge(m, f, x + 0.45, 2.85, z, 0.75, 0.5, 0.08, if lvl >= 3 then "gold" else "berry_red", math.pi / 2, "Flag")
	if lvl >= 3 then
		wedge(m, f, x + 0.35, 2.3, z, 0.55, 0.35, 0.08, "berry_red", math.pi / 2, "Flag")
		box(m, f, x, 3.45, z, 0.5, 0.5, 0.5, "yellow", "LampLight", true)
		box(m, f, x, 3.825, z, 0.75, 0.25, 0.75, "wood_dark", "LampCap")
		ball(m, f, x, 4.0, z, 0.25, "gold", "Knob")
	else
		ball(m, f, x, 3.25, z, 0.25, "gold", "Knob")
	end
end

-- A box from a to b (points in f), w wide and h deep, its top facing up: a chute, a cable, a beam on a slant.
local function span(m: Instance, f: CFrame, a: Vector3, b: Vector3, w: number, h: number, color: string, name: string): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, (b - a).Magnitude), cf = f * CFrame.lookAt((a + b) / 2, b), color = color, name = name, collide = false })
end

-- A round door facing +Z (a driftling's): a dark disc in a lighter ring. (A cylinder's axis is its X: turned a quarter
-- round Y it lies along Z, the disc facing front; the old quarter turn round X left it facing the side.)
local function roundDoor(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?)
	cyl(m, f, x, y, z, dia + 0.25, 0.25, color or "wood", "DoorRing").CFrame = f * CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0)
	cyl(m, f, x, y, z + 0.05, dia, 0.25, "wood_dark", "Door").CFrame = f * CFrame.new(x, y, z + 0.05) * CFrame.Angles(0, math.pi / 2, 0)
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

-- (every piece, by name)
BuildKit.box = box
BuildKit.ball = ball
BuildKit.cyl = cyl
BuildKit.log = log
BuildKit.tube = tube
BuildKit.palmTrunk = palmTrunk
BuildKit.wedge = wedge
BuildKit.roof = roof
BuildKit.window = window
BuildKit.sideWindow = sideWindow
BuildKit.door = door
BuildKit.crate = crate
BuildKit.barrel = barrel
BuildKit.sack = sack
BuildKit.pot = pot
BuildKit.footing = footing
BuildKit.fence = fence
BuildKit.fenceZ = fenceZ
BuildKit.lamp = lamp
BuildKit.fruitTree = fruitTree
BuildKit.awning = awning
BuildKit.storey = storey
BuildKit.flatRoof = flatRoof
BuildKit.streetLamp = streetLamp
BuildKit.blades = blades
BuildKit.pennant = pennant
BuildKit.span = span
BuildKit.roundDoor = roundDoor
BuildKit.cap = cap
BuildKit.spire = spire
-- (a part that moves on the island: Models/Parts.move)
BuildKit.move = require(script.Parent.Parts).move

return BuildKit
