--!strict
-- The sky (GAME_DESIGN 8; docs/ARCHITECTURE.md 5): every island on the server stands on a plot in one row along X,
-- each a floating island alone in the sky (the request of 2026-11-20: "Never mind, make it a floating island instead,
-- with a 2d skybox. Expanding makes the island bigger."), nothing between them but air: a grass top, an earth lip
-- under its edge, rock stepping in and down under that, stones hanging below (Models/StreetModels draws it), and a
-- painted sky behind everything (UI/SkyBackdrop). Pure. Coordinates are studs; plot-local ones are from the plot's
-- origin (`Street.origin(i)`). (The module keeps its old name: the street it once was, then a sea.)
--
--   north (-Z)       .  ~  .   (( an island: grass on top, the lip and the rock under its edge ))   .  ~  .
--                    |  lot (air)       the Tree of Life in its middle, the island's sign on its south rim  |
--   south (+Z)
--
-- An island grows with its tier: its grass is every cell inside the tier's shape (ISLES[1 .. tier] together: `coast`,
-- the signed distance in studs from the grass's edge, negative on the grass), so an expansion pushes the edge outward
-- all round. Whole-stud cells (x .. x + 1, z .. z + 1) are grass by their centre's coast distance. Buildings stand only
-- on `buildable` cells (a stud in from the edge); the founders walk on the grass (`walkable`) and an invisible wall
-- just past the edge keeps them on it. The same tier is the same shape on every plot (a save does not depend on where
-- the island floats).
local Tuning = require(script.Parent.Parent.Config.Tuning)

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Isle = { cx: number, cz: number, rx: number, rz: number, ph: { number } }

local Street = {}

Street.MAX = Tuning.MaxPlots
Street.SPACING = Tuning.PlotSpacing
Street.LAWN_Y = -0.5 -- the top of the island's grass (pieces stand here)

-- A cell's layer: the grass, or the open air past the edge.
Street.GRASS, Street.AIR = 1, 0
-- How far past the edge a cell's coast distance is kept (studs): the wall's cells, and the bevels round the edge.
Street.REACH = 3
-- The invisible wall round the grass: the cells past the edge up to this far out (studs).
Street.WALL = 1.5

-- The lot: the air round an island (plot-local), wide enough for the top tier's island and its wall.
Street.LOT = { x0 = -Tuning.PlotSpacing / 2, z0 = -72, x1 = Tuning.PlotSpacing / 2, z1 = 86 } :: Rect

-- The island's heart, where a new island's Tree of Life stands (Logic/Tree.SPOT; the request of 2026-11-20: "Remove
-- the campfire in the middle and put the tree in the middle instead"). Every tier's shape is round it.
Street.CENTER = { x = 0, z = 6 }

-- The island by tier: centre, radii, the edge's wobble phases (four sines round it). Each tier's island is the union of
-- its shape and every smaller one's, so the island only ever grows (nothing built near its old edge has to move); each
-- adds as much ground as the tiers always did, so the limits and the prices still fit. Past the first they are
-- circles round the heart, so the island grows outward evenly every way (the request of 2026-11-20: "make expansion
-- expand outwards evenly instead of resulting in one long stretch"); the wobble keeps each edge its own.
local ISLES: { Isle } = {
	{ cx = 0, cz = 6, rx = 15, rz = 12, ph = { 0.6, 2.1, 0.3, 4.0 } },
	{ cx = 0, cz = 6, rx = 19.1, rz = 19.1, ph = { 1.4, 0.4, 2.6, 1.1 } },
	{ cx = 0, cz = 6, rx = 24.2, rz = 24.2, ph = { 2.2, 3.3, 1.7, 5.2 } },
	{ cx = 0, cz = 6, rx = 28.3, rz = 28.3, ph = { 0.9, 1.8, 4.1, 2.7 } },
	{ cx = 0, cz = 6, rx = 31.4, rz = 31.4, ph = { 3.0, 0.7, 5.5, 1.9 } },
	{ cx = 0, cz = 6, rx = 34.6, rz = 34.6, ph = { 1.7, 2.9, 0.4, 3.6 } },
	{ cx = 0, cz = 6, rx = 37.8, rz = 37.8, ph = { 2.5, 1.2, 3.9, 0.8 } },
	{ cx = 0, cz = 6, rx = 40, rz = 40, ph = { 0.4, 3.6, 2.2, 4.7 } },
	{ cx = 0, cz = 6, rx = 43.2, rz = 43.2, ph = { 3.3, 2.4, 0.9, 2.1 } },
	{ cx = 0, cz = 6, rx = 44.5, rz = 44.5, ph = { 1.1, 0.6, 4.6, 3.3 } },
	{ cx = 0, cz = 6, rx = 47.3, rz = 47.3, ph = { 1.1, 1.2, 2.6, 4.6 } },
	{ cx = 0, cz = 6, rx = 48.6, rz = 48.6, ph = { 0.3, 4.1, 5.6, 1.2 } },
	{ cx = 0, cz = 6, rx = 50.6, rz = 50.6, ph = { 2.1, 3.7, 2.8, 0.7 } },
	{ cx = 0, cz = 6, rx = 52.2, rz = 52.2, ph = { 2.8, 3.5, 1.8, 4.1 } },
	{ cx = 0, cz = 6, rx = 53.5, rz = 53.5, ph = { 1.5, 5.1, 2.2, 1.2 } },
	{ cx = 0, cz = 6, rx = 55, rz = 55, ph = { 2.5, 1.2, 5.9, 4.7 } },
	{ cx = 0, cz = 6, rx = 57.1, rz = 57.1, ph = { 2.0, 4.2, 2.8, 5.4 } },
	{ cx = 0, cz = 6, rx = 58.6, rz = 58.6, ph = { 1.2, 5.2, 2.2, 2.7 } },
	{ cx = 0, cz = 6, rx = 59.1, rz = 59.1, ph = { 0.5, 4.6, 0.7, 5.8 } },
	{ cx = 0, cz = 6, rx = 60.1, rz = 60.1, ph = { 1.8, 1.7, 4.9, 0.6 } },
}
Street.TOP = #ISLES
local AMP = { 0.09, 0.06, 0.045, 0.025 }
local FREQ = { 2, 3, 5, 7 }

function Street.isle(tier: number): Isle
	return ISLES[math.clamp(math.floor(tier), 1, #ISLES)]
end

-- One tier's own shape: the signed distance (studs, along the ray from its centre) from its edge.
local function ownCoast(s: Isle, x: number, z: number): number
	local dx, dz = x - s.cx, z - s.cz
	local a = math.atan2(dz, dx)
	local c, sn = math.cos(a), math.sin(a)
	local er = 1 / math.sqrt((c / s.rx) ^ 2 + (sn / s.rz) ^ 2)
	local w = 1
	for k = 1, #AMP do
		w += AMP[k] * math.sin(FREQ[k] * a + s.ph[k])
	end
	return math.sqrt(dx * dx + dz * dz) - er * w
end

-- The signed distance from the island's edge at a tier (negative inside): the tier's own shape and every smaller
-- tier's together, so the island only ever grows.
function Street.coast(tier: number, x: number, z: number): number
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local d = ownCoast(ISLES[t], x, z)
	for k = 1, t - 1 do
		d = math.min(d, ownCoast(ISLES[k], x, z))
	end
	return d
end

-- Each tier's cells, worked out once: layer and coast distance by key (the grass and the cells up to REACH past it).
type Cells = { layer: { [number]: number }, dist: { [number]: number }, bounds: Rect, land: Rect }
local cache: { [number]: Cells } = {}
local function key(x: number, z: number): number
	return (x + 1024) * 4096 + (z + 1024)
end
Street.cellKey = key

local cellsOf: (tier: number) -> Cells
function cellsOf(tier: number): Cells
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local c = cache[t]
	if c then
		return c
	end
	local reach = Street.REACH + 1
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for k = 1, t do
		local s = ISLES[k]
		x0 = math.min(x0, math.floor(s.cx - s.rx * 1.3 - reach))
		x1 = math.max(x1, math.ceil(s.cx + s.rx * 1.3 + reach))
		z0 = math.min(z0, math.floor(s.cz - s.rz * 1.3 - reach))
		z1 = math.max(z1, math.ceil(s.cz + s.rz * 1.3 + reach))
	end
	local layer, dist = {}, {}
	local lx0, lz0, lx1, lz1 = math.huge, math.huge, -math.huge, -math.huge
	-- (the tier's own shape against the tier below's cells: the same as Street.coast for every cell within REACH of
	-- the edge, as a cell the tier below leaves out is more than REACH past its edge, and one sum a cell in place of
	-- twenty at the top tier)
	local below = if t > 1 then cellsOf(t - 1).dist else nil
	local s = ISLES[t]
	for z = z0, z1 do
		for x = x0, x1 do
			local d = ownCoast(s, x + 0.5, z + 0.5)
			if below then
				local b = below[key(x, z)]
				if b and b < d then
					d = b
				end
			end
			if d <= Street.REACH then
				local k = key(x, z)
				dist[k] = d
				if d <= 0 then
					layer[k] = Street.GRASS
					lx0, lz0, lx1, lz1 = math.min(lx0, x), math.min(lz0, z), math.max(lx1, x + 1), math.max(lz1, z + 1)
				end
			end
		end
	end
	local made: Cells = { layer = layer, dist = dist, bounds = { x0 = x0, z0 = z0, x1 = x1, z1 = z1 }, land = { x0 = lx0, z0 = lz0, x1 = lx1, z1 = lz1 } }
	cache[t] = made
	return made
end

-- Works a tier's cells out now (a few ms to tens of ms at the top tiers), so the moment that needs them (an
-- expansion) doesn't: the server warms every tier at start, the client the next one.
function Street.warm(tier: number)
	cellsOf(tier)
end

-- The layer of the whole-stud cell x .. x + 1, z .. z + 1 (plot-local) at a tier: the grass or the air.
function Street.layer(tier: number, x: number, z: number): number
	return cellsOf(tier).layer[key(x, z)] or Street.AIR
end

-- The coast distance at a cell's centre at a tier (negative on the grass; huge more than REACH past the edge).
function Street.cellDist(tier: number, x: number, z: number): number
	return cellsOf(tier).dist[key(x, z)] or math.huge
end

-- Every cell the island's drawing looks at (the grass and REACH past it) at a tier.
function Street.cellBounds(tier: number): Rect
	return cellsOf(tier).bounds
end

-- Whether a building may cover cell (x, z): grass a stud in from the edge.
function Street.buildable(tier: number, x: number, z: number): boolean
	return (cellsOf(tier).dist[key(x, z)] or math.huge) <= -1
end

-- Whether a founder may stand on cell (x, z): the island's grass.
function Street.walkable(tier: number, x: number, z: number): boolean
	return cellsOf(tier).layer[key(x, z)] == Street.GRASS
end

-- The island's bounding box (plot-local): the scans for a free spot stay inside it.
function Street.plot(tier: number): Rect
	return cellsOf(tier).land
end

-- The origin of plot i (1..MAX) in world studs: the row is centred on x = 0.
function Street.origin(i: number): (number, number)
	return (i - (Street.MAX + 1) / 2) * Street.SPACING, 0
end

-- Which plot a world point is at (its lot, by x), 0 off the row.
function Street.plotAt(x: number, z: number): number
	local i = math.floor(x / Street.SPACING + (Street.MAX + 1) / 2 + 0.5)
	if i < 1 or i > Street.MAX then
		return 0
	end
	local ox, oz = Street.origin(i)
	local lx, lz = x - ox, z - oz
	if lx >= Street.LOT.x0 and lx <= Street.LOT.x1 and lz >= Street.LOT.z0 and lz <= Street.LOT.z1 then
		return i
	end
	return 0
end

-- The world's box (world studs): every lot.
function Street.bounds(): Rect
	local x0 = Street.origin(1) + Street.LOT.x0
	local x1 = Street.origin(Street.MAX) + Street.LOT.x1
	return { x0 = x0, z0 = Street.LOT.z0, x1 = x1, z1 = Street.LOT.z1 }
end

-- Where a founder appears on an island with nothing in the way: just south of a new island's tree (plot-local x, z;
-- Logic/Plot.spawn finds the free spot nearest the tree where it stands).
function Street.spawn(): (number, number)
	return Street.CENTER.x, Street.CENTER.z + 5.5
end

-- The island's sign: on the south rim of its grass, west of the tree (plot-local centre of its cell), on a tier: the
-- last cell of grass going south from the heart, so it stands on the stud nearest the edge, where nothing is built.
function Street.sign(tier: number): (number, number)
	local x = -5
	local z = Street.CENTER.z
	while Street.layer(tier, x, z + 1) == Street.GRASS do
		z += 1
	end
	return x + 0.5, z + 0.5
end

return Street
