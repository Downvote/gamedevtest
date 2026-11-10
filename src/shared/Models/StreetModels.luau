--!strict
-- The sea from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server: PlotService builds
-- every plot's stretch at start and each plot's island as players come and go).
--   road(parent, origin)          a plot's stretch: the water of its lot and the open sea, the boardwalk on its posts
--                                 with lanterns, the pier and the expedition boat moored at its end (every plot,
--                                 occupied or not, so the boardwalk runs on unbroken)
--   land(parent, origin, tier)    an occupied plot: the island (a sand beach round its grass), the sandy path from
--                                 the lodge's doorway, the island's sign (its board named "SignBoard"), the mailbox,
--                                 and the invisible walls that keep the founder on the island and the boardwalk
--   emptyLot(parent, origin)      an unclaimed plot: water and a little sandbar with a palm and a sign
--   ends(parent)                  the sea at both ends of the boardwalk and the invisible walls round the world
-- Tops: the grass at Street.LAWN_Y (-0.5, just under the lodge floor's 0), the beach at SAND_Y, the sea at WATER_Y,
-- the boardwalk at -0.3. Walls are invisible and never queried (the renderer's rays pass through).
local Street = require(script.Parent.Parent.Data.Street)
local Office = require(script.Parent.Parent.Data.Office)
local Blocks = require(script.Parent.Blocks)

local StreetModels = {}

local BOARD_Y = -0.3

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

-- An invisible wall (plot-local x0..x1, z0..z1) the founder can't walk through.
local function wall(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number)
	local H = 8 -- higher than a jump; low, so the pixel filter's rays seldom pass more than one (BakeCast.MAX_HOPS)
	local w = Blocks.part(parent, {
		size = Vector3.new(math.max(0.5, x1 - x0), H, math.max(0.5, z1 - z0)),
		cf = o * CFrame.new((x0 + x1) / 2, H / 2 - 1, (z0 + z1) / 2),
		color = "white",
		name = "Bound",
		transparency = 1,
		query = false,
	})
	w.CastShadow = false
end

local function lantern(parent: Instance, at: CFrame)
	local m = Blocks.model(nil, "Lantern")
	box(m, at, 0, 1.5, 0, 0.5, 3, 0.5, "wood_dark", "Pole")
	box(m, at, 0, 3.25, 0, 1, 0.25, 1, "wood_dark", "Cap")
	box(m, at, 0, 2.85, 0, 0.75, 0.5, 0.75, "yellow", "Light", true)
	m.Parent = parent
end

local function palm(parent: Instance, at: CFrame, s: number)
	local m = Blocks.model(nil, "Palm")
	for i = 0, 3 do
		box(m, at, i * 0.2 * s, (0.6 + i * 1.1) * s, 0, 0.75 * s, 1.2 * s, 0.75 * s, if i % 2 == 0 then "wood" else "wood_dark", "Trunk")
	end
	local top = 4.8 * s
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		box(m, at, 0.8 + d[1] * 1.4 * s, top - 0.2, d[2] * 1.4 * s, (if d[1] ~= 0 then 2.5 else 1) * s, 0.4, (if d[2] ~= 0 then 2.5 else 1) * s, if k % 2 == 0 then "leaf" else "leaf_dark", "Frond")
	end
	ball(m, at, 0.8, top - 0.6, 0.3, 0.6 * s, "wood_dark")
	m.Parent = parent
end

-- The boat at the pier's end (its bow to the south).
local function boat(parent: Instance, at: CFrame)
	local m = Blocks.model(nil, "Boat")
	box(m, at, 0, -0.75, 0, 3, 1, 5, "wood_dark", "Hull")
	box(m, at, 0, -0.15, 0, 3.25, 0.25, 5.25, "wood", "Rim")
	box(m, at, 0, -0.35, 2.75, 2, 0.75, 0.75, "wood_dark", "Bow")
	box(m, at, 0, -0.1, 0, 2.5, 0.25, 4.25, "wood", "Deck")
	box(m, at, 0, 2.4, -0.25, 0.25, 5, 0.25, "wood_dark", "Mast")
	box(m, at, 0.15, 2.6, 0.75, 0.25, 3.5, 2, "white", "Sail")
	box(m, at, 0, 4.75, -0.25, 0.25, 0.5, 0.75, "berry_red", "Flag")
	m.Parent = parent
end

------------------------------------------------------------------ a plot's stretch
function StreetModels.road(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Road")
	local o = CFrame.new(origin)
	local x0, x1 = Street.LOT.x0, Street.LOT.x1
	-- the water: the lot's and the open sea's
	slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.BOARD.z0, Street.WATER_Y, 1, "water", "Water")
	slab(m, o, x0, Street.BOARD.z1, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water")
	slab(m, o, x0, Street.BOARD.z0, x1, Street.BOARD.z1, Street.WATER_Y, 1, "water", "Water")
	-- the boardwalk: planks across it, a darker seam every other stud, posts down into the water
	slab(m, o, x0, Street.BOARD.z0, x1, Street.BOARD.z1, BOARD_Y, 0.5, "wood", "Boardwalk")
	local x = x0 + 1
	while x < x1 do
		box(m, o, x, BOARD_Y + 0.01, (Street.BOARD.z0 + Street.BOARD.z1) / 2, 0.25, 0.05, Street.BOARD.z1 - Street.BOARD.z0, "wood_dark", "Seam")
		x += 2
	end
	x = x0 + 2
	while x < x1 do
		box(m, o, x, (BOARD_Y + Street.WATER_Y) / 2 - 0.25, Street.BOARD.z1 - 0.25, 0.5, BOARD_Y - Street.WATER_Y + 0.5, 0.5, "wood_dark", "Post")
		x += 6
	end
	for _, lx in Street.LAMPS do
		lantern(m, o * CFrame.new(lx, BOARD_Y, Street.BOARD.z1 - 0.5))
	end
	-- the pier and its boat
	local pr = Street.pier()
	slab(m, o, pr.x0, pr.z0, pr.x1, pr.z1, BOARD_Y, 0.5, "wood", "Pier")
	for z = pr.z0 + 2, pr.z1, 3 do
		box(m, o, pr.x0 + 0.25, (BOARD_Y + Street.WATER_Y) / 2 - 0.25, z, 0.5, BOARD_Y - Street.WATER_Y + 0.5, 0.5, "wood_dark", "Post")
		box(m, o, pr.x1 - 0.25, (BOARD_Y + Street.WATER_Y) / 2 - 0.25, z, 0.5, BOARD_Y - Street.WATER_Y + 0.5, 0.5, "wood_dark", "Post")
	end
	boat(m, o * CFrame.new(pr.x1 + 2.25, Street.WATER_Y + 0.6, pr.z1 - 2.5))
	-- walls: the boardwalk's sea side (but the pier), the pier's sides and end
	wall(m, o, x0, Street.BOARD.z1, pr.x0, Street.BOARD.z1 + 0.5)
	wall(m, o, pr.x1, Street.BOARD.z1, x1, Street.BOARD.z1 + 0.5)
	wall(m, o, pr.x0 - 0.5, pr.z0, pr.x0, pr.z1)
	wall(m, o, pr.x1, pr.z0, pr.x1 + 0.5, pr.z1)
	wall(m, o, pr.x0 - 0.5, pr.z1, pr.x1 + 0.5, pr.z1 + 0.5)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an island
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
	local p = Street.plot(tier)
	local B = Street.BEACH
	-- the beach round the island, the grass on it, a few rocks at the waterline
	slab(m, o, p.x0 - B, p.z0 - B, p.x1 + B, Street.BOARD.z0, Street.SAND_Y, 1.2, "sand", "Beach")
	slab(m, o, p.x0, p.z0, p.x1, p.z1, Street.LAWN_Y, 1, "grass", "Lawn")
	for k, r in { { p.x0 - B + 0.5, p.z0 + 4 }, { p.x1 + B - 1, p.z0 + 10 }, { p.x0 + 6, p.z0 - B + 0.5 }, { p.x1 - 8, p.z0 - B + 0.4 } } do
		box(m, o, r[1], Street.SAND_Y + 0.2, r[2], 1 + k % 2 * 0.5, 0.75, 1, if k % 2 == 0 then "steel" else "steel_dark", "Rock")
	end
	palm(m, o * CFrame.new(p.x0 - B + 1, Street.SAND_Y, p.z1 - 4), 1)
	local plan = Office.plan(tier)
	-- the sandy path: stepping stones from the doorstep to the boardwalk
	local fp = Street.footpath(plan.maxX, plan.maxZ)
	local z = fp.z0 + 1
	while z < fp.z1 - 0.5 do
		slab(m, o, fp.x0 + 0.25, z, fp.x1 - 0.25, math.min(z + 1.5, fp.z1), -0.3, 0.5, "sand_dark", "Footpath")
		z += 2
	end
	local sx, sz = Street.sign(plan.maxX, plan.maxZ)
	sign(m, o * CFrame.new(sx, Street.LAWN_Y, sz), "island")
	local mx, mz = Street.mailbox(plan.maxX, plan.maxZ)
	local mf = o * CFrame.new(mx, Street.LAWN_Y, mz)
	box(m, mf, 0, 0.8, 0, 0.25, 1.6, 0.25, "wood_dark", "MailPost")
	box(m, mf, 0, 1.85, 0, 0.75, 0.75, 1.25, "berry_red", "Mailbox")
	box(m, mf, 0.45, 2.1, -0.2, 0.25, 0.5, 0.25, "yellow", "Flag")
	-- walls round the beach, and along the boardwalk's island side where the lot is water
	local lot = Street.LOT
	wall(m, o, p.x0 - B - 0.5, p.z0 - B - 0.5, p.x1 + B + 0.5, p.z0 - B)
	wall(m, o, p.x0 - B - 0.5, p.z0 - B, p.x0 - B, Street.BOARD.z0)
	wall(m, o, p.x1 + B, p.z0 - B, p.x1 + B + 0.5, Street.BOARD.z0)
	wall(m, o, lot.x0, Street.BOARD.z0 - 0.5, p.x0 - B - 0.5, Street.BOARD.z0)
	wall(m, o, p.x1 + B + 0.5, Street.BOARD.z0 - 0.5, lot.x1, Street.BOARD.z0)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an unclaimed plot
function StreetModels.emptyLot(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "EmptyLot")
	local o = CFrame.new(origin)
	slab(m, o, -6, 10, 6, 18, Street.SAND_Y, 1.2, "sand", "Sandbar")
	palm(m, o * CFrame.new(-3, Street.SAND_Y, 13), 1)
	sign(m, o * CFrame.new(2, Street.SAND_Y, 16), "empty")
	box(m, o, 4, Street.SAND_Y + 0.25, 12, 1, 0.5, 1, "steel", "Rock")
	-- the boardwalk's island side is closed here
	wall(m, o, Street.LOT.x0, Street.BOARD.z0 - 0.5, Street.LOT.x1, Street.BOARD.z0)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the sea's ends and the world's walls
function StreetModels.ends(parent: Instance): Model
	local m = Blocks.model(nil, "StreetEnds")
	local b = Street.bounds()
	local o = CFrame.new()
	local first = Street.origin(1) + Street.LOT.x0
	local last = Street.origin(Street.MAX) + Street.LOT.x1
	for _, e in { { b.x0, first }, { last, b.x1 } } do
		local west = e[1] == b.x0
		local x0 = if west then e[1] - Street.END_FAR else e[1]
		local x1 = if west then e[2] else e[2] + Street.END_FAR
		slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water")
		-- the boardwalk runs on to a last post and lantern
		local bx0 = if west then b.x0 else first
		local bx1 = if west then first else b.x1
		slab(m, o, bx0, Street.BOARD.z0, bx1, Street.BOARD.z1, BOARD_Y, 0.5, "wood", "Boardwalk")
		local hx = if west then b.x0 + 1 else b.x1 - 1
		lantern(m, o * CFrame.new(hx, BOARD_Y, Street.BOARD.z0 + 0.5))
		palm(m, o * CFrame.new(if west then hx - 12 else hx + 12, Street.WATER_Y, 6), 1.2)
		slab(m, o, (if west then hx - 16 else hx + 8), 2, (if west then hx - 8 else hx + 16), 10, Street.SAND_Y, 1.2, "sand", "Sandbar")
		wall(m, o, bx0, Street.BOARD.z0 - 0.5, bx1, Street.BOARD.z0)
		wall(m, o, bx0, Street.BOARD.z1, bx1, Street.BOARD.z1 + 0.5)
	end
	-- the world's outer walls
	local H = 8 -- higher than a jump; low, so the pixel filter's rays seldom pass more than one (BakeCast.MAX_HOPS)
	local function outer(x0: number, z0: number, x1: number, z1: number)
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
	outer(b.x0 - 1, b.z0 - 1, b.x1 + 1, b.z0)
	outer(b.x0 - 1, b.z1, b.x1 + 1, b.z1 + 1)
	outer(b.x0 - 1, b.z0, b.x0, b.z1)
	outer(b.x1, b.z0, b.x1 + 1, b.z1)
	m.Parent = parent
	return m
end

return StreetModels
