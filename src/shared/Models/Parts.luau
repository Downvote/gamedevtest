--!strict
-- Small part helpers for the build catalog's models (Models/GroundModels, FenceModels, NatureModels, ThemeModels,
-- FunModels; GAME_DESIGN 4). Roblox module (server and client). The same shapes Models/DecorModels builds with: every
-- part through Blocks (anchored, no collision, palette colours, sizes on the 0.25-stud grid, never thinner than 0.25),
-- placed in the piece's frame `f` (its footprint's centre on the grass, already turned; +Z faces the view before the
-- turn). y is the height above the grass.
local Blocks = require(script.Parent.Blocks)

local Parts = {}

export type Builder = (m: Model, f: CFrame, lvl: number) -> ()

-- A box centred at (x, y, z) in f.
function Parts.box(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z), color = color, name = name, neon = neon, collide = false })
end

-- A box turned by `yaw` (radians) about its own centre.
function Parts.turned(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, yaw: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), color = color, name = name, neon = neon, collide = false })
end

-- A box tilted: `cf` is its centre's frame relative to f (any turn).
function Parts.at(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, name = name, neon = neon, collide = false })
end

-- A ball of diameter dia.
function Parts.ball(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(dia, dia, dia), cf = f * CFrame.new(x, y, z), color = color, shape = "Ball", name = name, neon = neon, collide = false })
end

-- An upright cylinder (diameter dia, height h) centred at (x, y, z).
function Parts.cyl(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, h: number, color: string, name: string?, neon: boolean?): BasePart
	local p = Blocks.part(m, { size = Vector3.new(h, dia, dia), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2), color = color, shape = "Cylinder", name = name, neon = neon, collide = false })
	return p
end

-- A cylinder lying along X (a log, a rail, a pipe) of length len.
function Parts.log(m: Instance, f: CFrame, x: number, y: number, z: number, len: number, dia: number, color: string, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(len, dia, dia), cf = f * CFrame.new(x, y, z), color = color, shape = "Cylinder", name = name or "Log", collide = false })
end

-- The same along Z.
function Parts.logZ(m: Instance, f: CFrame, x: number, y: number, z: number, len: number, dia: number, color: string, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(len, dia, dia), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, math.pi / 2, 0), color = color, shape = "Cylinder", name = name or "Log", collide = false })
end

-- A wedge (its sloped face toward -Z, full height at +Z before `turn`).
function Parts.wedge(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, turn: number?, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * CFrame.new(x, y, z) * CFrame.Angles(0, turn or 0, 0), color = color, shape = "Wedge", name = name, collide = false })
end

-- A glowing part (Neon: a light at night, a lantern's flame, a crystal).
function Parts.glow(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?): BasePart
	return Parts.box(m, f, x, y, z, w, h, d, color, name or "Light", true)
end

-- A water surface the pixel filter animates (class 2: the shallows' ripple), flat at height y.
function Parts.water(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, d: number, color: string?, name: string?): BasePart
	local p = Parts.box(m, f, x, y, z, w, 0.25, d, color or "water", name or "Water")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- A small hash of a piece's place (stable for a footprint): to vary a tile's stones or flowers between neighbours.
-- `f` is the piece's frame; k picks another number from the same place.
function Parts.hash(f: CFrame, k: number?): number
	local p = f.Position
	local n = math.floor(p.X * 7 + 0.5) * 73856093 + math.floor(p.Z * 7 + 0.5) * 19349663 + (k or 0) * 83492791
	return (n % 1000003) / 1000003
end

return Parts
