--!strict
-- Part / model construction helpers for procedural models (docs/ARCHITECTURE.md 6; copied from Random Bakery). Roblox module (server and client).
--
-- Every procedural model in the game is built from plain Parts through these helpers: anchored, SmoothPlastic
-- (Neon only when asked), sizes on the 0.25-stud grid, colours from the palette (Data/Palette), no meshes,
-- decals, textures or SurfaceGuis. Invisible helpers are created with transparency = 1, collide = false and
-- query = false by their builders.
local Palette = require(script.Parent.Parent.Data.Palette)

export type PartSpec = {
	size: Vector3,
	cf: CFrame,
	color: string,
	shape: ("Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball")?,
	name: string?,
	collide: boolean?,
	query: boolean?,
	transparency: number?,
	neon: boolean?,
}

local Blocks = {}

local GRID = 0.25
local MAGENTA = Color3.fromRGB(255, 0, 255)

local colorCache: { [string]: Color3 } = {}
local warned: { [string]: boolean } = {}

-- Snaps a length to the 0.25-stud grid (nearest multiple).
function Blocks.snap(v: number): number
	return math.floor(v / GRID + 0.5) * GRID
end

-- Part sizes snap to the grid and never collapse below one grid step.
local function snapLen(v: number): number
	return math.max(GRID, Blocks.snap(v))
end

-- Palette key -> Color3 (cached). An unknown key is a content bug: magenta, warned once per key.
function Blocks.color(key: string): Color3
	local cached = colorCache[key]
	if cached then
		return cached
	end
	local hex = Palette.colors[key]
	if hex == nil then
		if not warned[key] then
			warned[key] = true
			warn("[Blocks] unknown palette key '" .. tostring(key) .. "'")
		end
		return MAGENTA
	end
	local c = Color3.fromRGB(math.floor(hex / 65536) % 256, math.floor(hex / 256) % 256, hex % 256)
	colorCache[key] = c
	return c
end

-- Creates one anchored part from a spec and parents it last (cheap property writes while unparented).
-- Defaults: Block shape, CanCollide true, CanQuery true, opaque, SmoothPlastic, CastShadow true, CanTouch false.
function Blocks.part(parent: Instance, spec: PartSpec): BasePart
	local shape = spec.shape or "Block"
	local p: BasePart
	if shape == "Wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "CornerWedge" then
		p = Instance.new("CornerWedgePart")
	else
		local part = Instance.new("Part")
		part.Shape = if shape == "Ball"
			then Enum.PartType.Ball
			elseif shape == "Cylinder" then Enum.PartType.Cylinder
			else Enum.PartType.Block
		p = part
	end
	local transparency = spec.transparency or 0
	p.Name = spec.name or shape
	p.Anchored = true
	p.Material = if spec.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.CastShadow = transparency < 1
	p.CanTouch = false
	p.CanCollide = spec.collide ~= false
	p.CanQuery = spec.query ~= false
	p.Transparency = transparency
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = Blocks.color(spec.color)
	p.Size = Vector3.new(snapLen(spec.size.X), snapLen(spec.size.Y), snapLen(spec.size.Z))
	p.CFrame = spec.cf
	p.Parent = parent
	return p
end

-- Upright cylinder (Roblox cylinders run along X; this one is turned to run along Y). `cf` is its centre.
function Blocks.cylY(parent: Instance, diameter: number, height: number, cf: CFrame, color: string): BasePart
	return Blocks.part(parent, {
		size = Vector3.new(height, diameter, diameter),
		cf = cf * CFrame.Angles(0, 0, math.pi / 2),
		color = color,
		shape = "Cylinder",
	})
end

-- New Model; sets the "Interact" attribute when given. Parented only when a parent is passed (builders usually
-- fill the model first and parent it last).
function Blocks.model(parent: Instance?, name: string, interact: string?): Model
	local m = Instance.new("Model")
	m.Name = name
	if interact then
		m:SetAttribute("Interact", interact)
	end
	if parent then
		m.Parent = parent
	end
	return m
end

return Blocks
