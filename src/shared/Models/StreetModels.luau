--!strict
-- The street from parts (GAME_DESIGN 12; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server: PlotService
-- builds every plot's stretch at start and each plot's land as studios come and go).
--   road(parent, origin)          a plot's stretch of the street: the north pavement, the road with its dashed line,
--                                 the south pavement, the verge with its trees and lamp posts (every plot, occupied
--                                 or not, so the road runs on unbroken)
--   land(parent, origin, tier)    an occupied lot: meadow, the plot's lawn on top of it, the footpath from the office's
--                                 doorway, the plot sign (its board named "SignBoard") and the mailbox
--   emptyLot(parent, origin)      an empty lot: meadow, a low fence, an "Empty lot" sign, a few bushes
--   ends(parent)                  the street's two ends (a hedge and a lamp) and the invisible walls round the world
-- Every top is just under the office floor's (y = 0): the lawn at Street.LAWN_Y (-0.5), the meadow 0.05 lower, the
-- road at -0.45, pavements and the footpath at -0.3.
local Street = require(script.Parent.Parent.Data.Street)
local Office = require(script.Parent.Parent.Data.Office)
local Blocks = require(script.Parent.Blocks)

local StreetModels = {}

local function box(parent: Instance, frame: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(parent, { size = Vector3.new(w, h, d), cf = frame * CFrame.new(x, y, z), color = color, name = name, neon = neon })
end

-- A box by its top: x0..x1, z0..z1 plot-local, its top at `top`, `h` deep.
local function slab(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, h: number, color: string, name: string): BasePart
	return box(parent, o, (x0 + x1) / 2, top - h / 2, (z0 + z1) / 2, x1 - x0, h, z1 - z0, color, name)
end

local function ball(parent: Instance, frame: CFrame, x: number, y: number, z: number, dia: number, color: string): BasePart
	return Blocks.part(parent, { size = Vector3.new(dia, dia, dia), cf = frame * CFrame.new(x, y, z), color = color, shape = "Ball" })
end

local function lampPost(parent: Instance, at: CFrame)
	local m = Blocks.model(nil, "LampPost")
	box(m, at, 0, 0.125, 0, 1, 0.25, 1, "steel_dark", "Foot")
	box(m, at, 0, 2.6, 0, 0.5, 5, 0.5, "steel_dark", "Pole")
	box(m, at, 0, 5.25, 0, 1.25, 0.5, 1.25, "steel_dark", "Cap")
	box(m, at, 0, 4.75, 0, 0.75, 0.5, 0.75, "yellow", "Lantern", true)
	m.Parent = parent
end

local function tree(parent: Instance, at: CFrame, big: boolean)
	local m = Blocks.model(nil, "Tree")
	local s = if big then 1.25 else 1
	box(m, at, 0, 1.5 * s, 0, 0.75 * s, 3 * s, 0.75 * s, "wood_dark", "Trunk")
	ball(m, at, 0, 4.2 * s, 0, 3.5 * s, "leaf")
	ball(m, at, -0.9 * s, 3.6 * s, 0.6 * s, 2.25 * s, "leaf_dark")
	ball(m, at, 0.9 * s, 3.8 * s, -0.4 * s, 2.25 * s, "leaf")
	ball(m, at, 0.2 * s, 5.4 * s, 0.1 * s, 1.75 * s, "leaf_dark")
	m.Parent = parent
end

local function bush(parent: Instance, at: CFrame)
	ball(parent, at, 0, 0.6, 0, 1.75, "leaf")
	ball(parent, at, 0.6, 0.5, 0.4, 1.25, "leaf_dark")
end

------------------------------------------------------------------ a plot's stretch of the street
function StreetModels.road(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Road")
	local o = CFrame.new(origin)
	local x0, x1 = Street.LOT.x0, Street.LOT.x1
	slab(m, o, x0, Street.PAVE_N.z0, x1, Street.PAVE_N.z1, -0.3, 0.5, "pavement", "Pavement")
	slab(m, o, x0, Street.ROAD.z0, x1, Street.ROAD.z1, -0.45, 0.5, "road", "Road")
	slab(m, o, x0, Street.PAVE_S.z0, x1, Street.PAVE_S.z1, -0.3, 0.5, "pavement", "Pavement")
	slab(m, o, x0, Street.VERGE.z0, x1, Street.VERGE.z1 + Street.FAR, -0.5, 0.5, "grass", "Verge")
	-- kerbs along the pavements' road sides
	slab(m, o, x0, Street.PAVE_N.z1 - 0.25, x1, Street.PAVE_N.z1, -0.25, 0.5, "steel", "Kerb")
	slab(m, o, x0, Street.PAVE_S.z0, x1, Street.PAVE_S.z0 + 0.25, -0.25, 0.5, "steel", "Kerb")
	-- the dashed centre line
	local mid = (Street.ROAD.z0 + Street.ROAD.z1) / 2
	local x = x0 + 1
	while x + 3 <= x1 do
		box(m, o, x + 1.5, -0.42, mid, 3, 0.25, 0.5, "cream", "Line")
		x += 6
	end
	for _, lx in Street.LAMPS do
		lampPost(m, o * CFrame.new(lx, -0.3, Street.PAVE_S.z0 + 1))
	end
	for k, t in Street.TREES do
		tree(m, o * CFrame.new(t[1], -0.5, t[2]), k % 2 == 0)
	end
	-- a second row past the walls
	tree(m, o * CFrame.new(-18, -0.5, Street.VERGE.z1 + 10), true)
	tree(m, o * CFrame.new(14, -0.5, Street.VERGE.z1 + 16), false)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an occupied lot
local function meadow(m: Instance, o: CFrame)
	local lot = Street.LOT
	slab(m, o, lot.x0, lot.z0 - Street.FAR, lot.x1, lot.z1, -0.55, 0.5, "grass_dark", "Meadow")
end

local function sign(m: Instance, at: CFrame, words: string?)
	local s = Blocks.model(nil, "PlotSign")
	box(s, at, -1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	box(s, at, 1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	local board = box(s, at, 0, 2.05, 0.1, 2.75, 1.25, 0.25, "wood", "SignBoard")
	if words then
		board:SetAttribute("Words", words)
	end
	box(s, at, 0, 2.05, 0.2, 2.25, 0.75, 0.25, "paper", "Face")
	s.Parent = m
end

function StreetModels.land(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, "Land")
	local o = CFrame.new(origin)
	meadow(m, o)
	local p = Street.plot(tier)
	slab(m, o, p.x0, p.z0, p.x1, p.z1, Street.LAWN_Y, 0.5, "grass", "Lawn")
	local plan = Office.plan(tier)
	-- the footpath: stepping stones from the doorstep to the pavement
	local fp = Street.footpath(plan.maxX, plan.maxZ)
	local z = fp.z0 + 1
	while z < fp.z1 - 0.5 do
		slab(m, o, fp.x0 + 0.25, z, fp.x1 - 0.25, math.min(z + 1.5, fp.z1), -0.3, 0.5, "pavement", "Footpath")
		z += 2
	end
	local sx, sz = Street.sign(plan.maxX, plan.maxZ)
	sign(m, o * CFrame.new(sx, Street.LAWN_Y, sz), "studio")
	local mx, mz = Street.mailbox(plan.maxX, plan.maxZ)
	local mf = o * CFrame.new(mx, Street.LAWN_Y, mz)
	box(m, mf, 0, 0.8, 0, 0.25, 1.6, 0.25, "wood_dark", "MailPost")
	box(m, mf, 0, 1.85, 0, 0.75, 0.75, 1.25, "berry_red", "Mailbox")
	box(m, mf, 0.45, 2.1, -0.2, 0.25, 0.5, 0.25, "yellow", "Flag")
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an empty lot
function StreetModels.emptyLot(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "EmptyLot")
	local o = CFrame.new(origin)
	meadow(m, o)
	-- a low white fence along the lot's front, with a gap
	local lot = Street.LOT
	local z = Street.PAVE_N.z0 - 1
	local x = lot.x0 + 4
	while x <= lot.x1 - 4 do
		if math.abs(x) > 3 then
			box(m, o, x, Street.LAWN_Y + 0.6, z, 0.25, 1.2, 0.25, "white", "Picket")
		end
		x += 2
	end
	for _, run in { { lot.x0 + 4, -3 }, { 3, lot.x1 - 4 } } do
		box(m, o, (run[1] + run[2]) / 2, Street.LAWN_Y + 0.8, z, run[2] - run[1], 0.25, 0.25, "white", "Rail")
	end
	sign(m, o * CFrame.new(-7, Street.LAWN_Y, z - 1.5), "empty")
	bush(m, o * CFrame.new(-18, Street.LAWN_Y, 14))
	bush(m, o * CFrame.new(12, Street.LAWN_Y, 6))
	bush(m, o * CFrame.new(20, Street.LAWN_Y, 20))
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the street's ends and the world's walls
function StreetModels.ends(parent: Instance): Model
	local m = Blocks.model(nil, "StreetEnds")
	local b = Street.bounds()
	local o = CFrame.new()
	local first = Street.origin(1) + Street.LOT.x0
	local last = Street.origin(Street.MAX) + Street.LOT.x1
	for _, e in { { b.x0, first }, { last, b.x1 } } do
		local west = e[1] == b.x0
		-- the ground runs on END_FAR studs past the walls
		local x0 = if west then e[1] - Street.END_FAR else e[1]
		local x1 = if west then e[2] else e[2] + Street.END_FAR
		slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.PAVE_N.z0, -0.55, 0.5, "grass_dark", "Meadow")
		slab(m, o, x0, Street.PAVE_N.z0, x1, Street.PAVE_N.z1, -0.3, 0.5, "pavement", "Pavement")
		slab(m, o, x0, Street.ROAD.z0, x1, Street.ROAD.z1, -0.45, 0.5, "road", "Road")
		slab(m, o, x0, Street.PAVE_S.z0, x1, Street.PAVE_S.z1, -0.3, 0.5, "pavement", "Pavement")
		slab(m, o, x0, Street.VERGE.z0, x1, Street.VERGE.z1 + Street.FAR, -0.5, 0.5, "grass", "Verge")
		-- a hedge across the end of the street, on the wall
		local hx = if west then b.x0 + 1 else b.x1 - 1
		slab(m, o, hx - 1, Street.LOT.z0, hx + 1, Street.VERGE.z1, 1.5, 2, "leaf_dark", "Hedge")
		lampPost(m, o * CFrame.new(if west then hx + 3 else hx - 3, -0.3, Street.PAVE_N.z0 + 1))
		tree(m, o * CFrame.new(if west then hx - 12 else hx + 12, -0.55, 6), true)
		tree(m, o * CFrame.new(if west then hx - 20 else hx + 20, -0.5, 52), false)
	end
	-- invisible walls round the world (the founder never walks off its edge); the bake's rays ignore them
	local H = 30
	local function wall(x0: number, z0: number, x1: number, z1: number)
		local w = Blocks.part(m, {
			size = Vector3.new(math.max(1, x1 - x0), H, math.max(1, z1 - z0)),
			cf = CFrame.new((x0 + x1) / 2, H / 2 - 1, (z0 + z1) / 2),
			color = "white",
			name = "Bound",
			transparency = 1,
			query = false,
		})
		w.CastShadow = false
	end
	wall(b.x0 - 1, b.z0 - 1, b.x1 + 1, b.z0)
	wall(b.x0 - 1, b.z1, b.x1 + 1, b.z1 + 1)
	wall(b.x0 - 1, b.z0, b.x0, b.z1)
	wall(b.x1, b.z0, b.x1 + 1, b.z1)
	m.Parent = parent
	return m
end

return StreetModels
