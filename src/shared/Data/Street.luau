--!strict
-- The sea (GAME_DESIGN 8; docs/ARCHITECTURE.md 5): every island on the server stands on a plot in one row along X,
-- all joined by one long boardwalk on their south side (the side the camera sees), the open sea beyond. Pure.
-- Coordinates are studs; plot-local ones are from the plot's origin (`Street.origin(i)`). (The module keeps its old
-- name: the street it once was.)
--
--   north (-Z)   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                |  lot (water)   (( an island: grass, sand, wet sand, foam, shallows ))      |
--                |                     a plaza (the campfire) and a path south to a jetty    |
--   z = 30..35   |================ the boardwalk (planks on posts) ===========================|
--                |                 a pier from the boardwalk, a boat at its end               |
--   z = 35..58   ~ ~ ~ ~ ~ ~ ~ ~ ~ the open sea ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--   south (+Z)
--
-- An island is a wobbly ellipse that grows with its tier (ISLES[tier]): its coast is `coast(tier, x, z)`, the signed
-- distance in studs from the grass's edge (negative on the grass). Round the grass, outward: the sand beach, the wet
-- sand at the waterline, a ring of foam, the light shallows, then the sea. Whole-stud cells (x .. x + 1, z .. z + 1)
-- have a `layer` by their centre's coast distance; buildings stand only on `buildable` cells (a stud in from the grass's
-- edge, off the plaza and the path). The same tier is the same shape on every plot (a save does not depend on where
-- the island is moored).
local Tuning = require(script.Parent.Parent.Config.Tuning)

export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type Isle = { cx: number, cz: number, rx: number, rz: number, ph: { number } }

local Street = {}

Street.MAX = Tuning.MaxPlots
Street.SPACING = Tuning.PlotSpacing
Street.LAWN_Y = -0.5 -- the top of the island's grass (pieces stand here)
Street.SAND_Y = -0.6 -- the beach
Street.WET_Y = -0.72 -- the wet sand at the waterline
Street.FOAM_Y = -0.98 -- the foam lapping the shore
Street.SHALLOW_Y = -1.04 -- the shallows round an island
Street.WATER_Y = -1.1 -- the sea's surface

-- The layers of a cell, outward (0: the open sea).
Street.GRASS, Street.SAND, Street.WET, Street.FOAM, Street.SHALLOW, Street.SEA_CELL = 1, 2, 3, 4, 5, 0
-- Where each layer ends (studs past the grass's edge).
Street.BANDS = { sand = 2.5, wet = 3.5, foam = 4.5, shallow = 8 }

-- The boardwalk and the sea, plot-local z (the same for every plot).
Street.BOARD = { z0 = 30, z1 = 35 }
Street.SEA = { z0 = 35, z1 = 58 }
-- Water past the invisible walls (studs): north of the lots, south of the sea and both ends, so no sky shows past the
-- world's edges wherever the view goes.
Street.FAR = 120
Street.END_FAR = 160

-- The tide's lane (GAME_DESIGN 6: "make them float by just like a conveyer belt"): the water between the island's
-- foam and the boardwalk, all along the lot (plot-local z; the driftlings float from x0 to x1, west to east, and duck
-- under the jetty on the way). Nothing stands in it (no rocks in the shallows there).
Street.TIDE = { z = 26, x0 = -Tuning.PlotSpacing / 2, x1 = Tuning.PlotSpacing / 2, clear = 2.5 }

-- The lot: the water between two neighbours (plot-local).
Street.LOT = { x0 = -Tuning.PlotSpacing / 2, z0 = -64, x1 = Tuning.PlotSpacing / 2, z1 = 30 } :: Rect

-- The island's heart: a plaza round the campfire (the same on every tier), and the path from it south down to the
-- jetty and the boardwalk.
Street.CENTER = { x = 0, z = 6 }
Street.PLAZA = { x0 = -4, z0 = 2, x1 = 4, z1 = 10 } :: Rect
Street.PATH = { x0 = -2, z0 = 10, x1 = 2, z1 = 30 } :: Rect

-- The islands by tier: centre, radii, the coast's wobble phases (four sines round the coast).
local ISLES: { Isle } = {
	{ cx = 0, cz = 6, rx = 15, rz = 12, ph = { 0.6, 2.1, 0.3, 4.0 } },
	{ cx = 0, cz = 2, rx = 22, rz = 16, ph = { 1.4, 0.4, 2.6, 1.1 } },
	{ cx = 0, cz = -2, rx = 28, rz = 20, ph = { 2.2, 3.3, 1.7, 5.2 } },
	-- the town and city tiers grow north (the boardwalk stays where it is): twice tier 3's grass by tier 6
	{ cx = 0, cz = -8, rx = 30, rz = 25, ph = { 0.9, 1.8, 4.1, 2.7 } },
	{ cx = 0, cz = -14, rx = 31, rz = 30, ph = { 3.0, 0.7, 5.5, 1.9 } },
	{ cx = 0, cz = -20, rx = 31, rz = 35, ph = { 1.7, 2.9, 0.4, 3.6 } },
}
local AMP = { 0.09, 0.06, 0.045, 0.025 }
local FREQ = { 2, 3, 5, 7 }

function Street.isle(tier: number): Isle
	return ISLES[math.clamp(math.floor(tier), 1, #ISLES)]
end

-- One tier's own shape: the signed distance (studs, along the ray from its centre) from its grass's edge.
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

-- The signed distance from the grass's edge (negative on the grass): the tier's own shape and every smaller tier's
-- together, so an island only ever gains land as it grows (nothing built near an old shore has to move).
function Street.coast(tier: number, x: number, z: number): number
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local d = ownCoast(ISLES[t], x, z)
	for k = 1, t - 1 do
		d = math.min(d, ownCoast(ISLES[k], x, z))
	end
	return d
end

-- The layer of a coast distance.
function Street.layerAt(d: number): number
	if d <= 0 then
		return Street.GRASS
	elseif d <= Street.BANDS.sand then
		return Street.SAND
	elseif d <= Street.BANDS.wet then
		return Street.WET
	elseif d <= Street.BANDS.foam then
		return Street.FOAM
	elseif d <= Street.BANDS.shallow then
		return Street.SHALLOW
	end
	return Street.SEA_CELL
end

-- Each tier's cells, worked out once: layer and coast distance by key.
type Cells = { layer: { [number]: number }, dist: { [number]: number }, bounds: Rect, land: Rect }
local cache: { [number]: Cells } = {}
local function key(x: number, z: number): number
	return (x + 256) * 1024 + (z + 256)
end
Street.cellKey = key

local function cellsOf(tier: number): Cells
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local c = cache[t]
	if c then
		return c
	end
	local reach = Street.BANDS.shallow + 1
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
	for z = z0, z1 do
		for x = x0, x1 do
			local d = Street.coast(t, x + 0.5, z + 0.5)
			local l = Street.layerAt(d)
			if l ~= Street.SEA_CELL then
				local k = key(x, z)
				layer[k] = l
				dist[k] = d
				if l == Street.GRASS then
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

-- The layer of the whole-stud cell x .. x + 1, z .. z + 1 (plot-local).
function Street.layer(tier: number, x: number, z: number): number
	return cellsOf(tier).layer[key(x, z)] or Street.SEA_CELL
end

-- The coast distance at a cell's centre (huge out at sea).
function Street.cellDist(tier: number, x: number, z: number): number
	return cellsOf(tier).dist[key(x, z)] or math.huge
end

-- Every cell the layers cover (the shallows' outer box) for drawing the island.
function Street.cellBounds(tier: number): Rect
	return cellsOf(tier).bounds
end

-- Whether a building may cover cell (x, z): grass a stud in from its edge (the plaza and the path are Logic/Plot's).
function Street.buildable(tier: number, x: number, z: number): boolean
	local d = cellsOf(tier).dist[key(x, z)]
	return d ~= nil and d <= -1
end

-- Whether a founder may stand on cell (x, z): the grass, the beach and the wet sand.
function Street.walkable(tier: number, x: number, z: number): boolean
	local l = Street.layer(tier, x, z)
	return l == Street.GRASS or l == Street.SAND or l == Street.WET
end

-- The island's grass's bounding box (plot-local): the scans for a free spot stay inside it.
function Street.plot(tier: number): Rect
	return cellsOf(tier).land
end

-- The origin of plot i (1..MAX) in world studs: the row is centred on x = 0.
function Street.origin(i: number): (number, number)
	return (i - (Street.MAX + 1) / 2) * Street.SPACING, 0
end

-- Which plot a world point stands on (its lot, by x), 0 when off the row's lots.
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

-- The world's box (world studs): every lot, the boardwalk and the sea, and a stretch past each end.
function Street.bounds(): Rect
	local x0 = Street.origin(1) + Street.LOT.x0 - 24
	local x1 = Street.origin(Street.MAX) + Street.LOT.x1 + 24
	return { x0 = x0, z0 = Street.LOT.z0, x1 = x1, z1 = Street.SEA.z1 }
end

-- The path from the plaza south to the boardwalk (plot-local): a jetty where it crosses the water.
function Street.footpath(): Rect
	return Street.PATH
end

-- The jetty: where the path leaves the island's walkable sand for the boardwalk (plot-local z), on a tier.
function Street.jetty(tier: number): Rect
	local z = Street.CENTER.z
	while z < Street.BOARD.z0 and Street.walkable(tier, 0, z) do
		z += 1
	end
	return { x0 = Street.PATH.x0, z0 = z - 1, x1 = Street.PATH.x1, z1 = Street.BOARD.z0 }
end

-- Where a founder appears: on the path just south of the plaza (plot-local x, z).
function Street.spawn(): (number, number)
	return 0, Street.PLAZA.z1 + 2
end

-- The island's sign and the mailbox on the boardwalk's north edge, west and east of the jetty (plot-local centres).
function Street.sign(): (number, number)
	return -4.5, Street.BOARD.z0 + 0.75
end
function Street.mailbox(): (number, number)
	return 3.5, Street.BOARD.z0 + 0.75
end

-- Along each plot's stretch (plot-local): lanterns on the boardwalk's posts, and the pier (its x, from the boardwalk
-- out to PIER_Z) where the old boat is moored.
Street.LAMPS = { -28, -8, 12, 28 } :: { number }
Street.PIER_X = 0
Street.PIER_Z = 44
Street.PIER_W = 4

-- The pier of plot-local x (where the boat waits).
function Street.pier(): Rect
	return { x0 = Street.PIER_X - Street.PIER_W / 2, z0 = Street.BOARD.z1, x1 = Street.PIER_X + Street.PIER_W / 2, z1 = Street.PIER_Z }
end

return Street
