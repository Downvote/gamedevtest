--!strict
-- Which parts the pixel filter lights smooth (Render/Smooth; docs/ARCHITECTURE.md 11), and their balls: a model with
-- its "PixelSmooth" attribute true (an egg, a driftling, the Tree of Life) is lit as one surface. A part's role comes
-- from its shape and attributes: "PixelOwn" keeps its own normal (eyes, gems), "PixelFollow" follows the body without
-- leaning it (a round spot set into a shell), a glowing part keeps its own, any other ball leans and follows, any
-- other shape follows.
--   SmoothParts.model(part) -> Model?            the smooth model the part is in (its nearest Model ancestor marked)
--   SmoothParts.role(part) -> number             Smooth.ROLE_*
--   SmoothParts.staticNormal(part, px, py, pz, ox, oy, oz) -> (nx, ny, nz)?   for the static bake: the smooth normal
--       at a hit point on a part of a smooth model (its balls as they stand, gathered once), nil for any other part
--   SmoothParts.Smooth                            Render/Smooth (one require for the renderer)
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Smooth = require(ReplicatedStorage.Shared.Render.Smooth)

local SmoothParts = {}
SmoothParts.Smooth = Smooth

function SmoothParts.model(part: Instance): Model?
	local p = part.Parent
	while p ~= nil and p ~= workspace do
		if p:IsA("Model") and p:GetAttribute("PixelSmooth") == true then
			return p
		end
		p = p.Parent
	end
	return nil
end

function SmoothParts.role(part: BasePart): number
	local own = part:GetAttribute("PixelOwn") == true or part.Material == Enum.Material.Neon
	local follow = part:GetAttribute("PixelFollow") == true
	local isBall = part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Ball
	return Smooth.role(isBall, own, follow)
end

-- the static models' balls (gathered the first time one of their parts is hit) and each part's group and role
type Group = { xs: { number }, ys: { number }, zs: { number }, rs: { number }, idx: { number }, n: number }
type PartInfo = { g: Group, role: number }
local groups: { [Model]: Group } = setmetatable({}, { __mode = "k" }) :: any
local infos: { [BasePart]: PartInfo } = setmetatable({}, { __mode = "k" }) :: any
local plain: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- parts lit their own way
local near: { number } = {}

local function groupOf(m: Model): Group
	local g = groups[m]
	if g then
		return g
	end
	local ng: Group = { xs = {}, ys = {}, zs = {}, rs = {}, idx = {}, n = 0 }
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 and SmoothParts.role(d) == Smooth.ROLE_BALL then
			local pos, sz = d.Position, d.Size
			ng.n += 1
			ng.xs[ng.n], ng.ys[ng.n], ng.zs[ng.n] = pos.X, pos.Y, pos.Z
			ng.rs[ng.n] = math.min(sz.X, sz.Y, sz.Z) * 0.5
		end
	end
	groups[m] = ng
	return ng
end

function SmoothParts.staticNormal(part: BasePart, px: number, py: number, pz: number, ox: number, oy: number, oz: number): (number?, number?, number?)
	if plain[part] then
		return nil, nil, nil
	end
	local inf = infos[part]
	if inf == nil then
		local m = SmoothParts.model(part)
		local role = if m then SmoothParts.role(part) else Smooth.ROLE_NONE
		if m == nil or role == Smooth.ROLE_OWN then
			plain[part] = true
			return nil, nil, nil
		end
		inf = { g = groupOf(m :: Model), role = role }
		infos[part] = inf
	end
	local g = inf.g
	local n = Smooth.near(g.xs, g.ys, g.zs, g.rs, g.n, px, py, pz, 0, near)
	local nx, ny, nz = Smooth.normal(g.xs, g.ys, g.zs, g.rs, near, n, px, py, pz, ox, oy, oz, inf.role)
	return nx, ny, nz
end

-- Forget the static models' balls (a new bake after the island changed).
function SmoothParts.reset()
	table.clear(groups)
	table.clear(infos)
	table.clear(plain)
end

return SmoothParts
