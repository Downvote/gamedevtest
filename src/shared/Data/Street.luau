--!strict
-- The sea (GAME_DESIGN 8; docs/ARCHITECTURE.md 5): every island on the server stands on a plot in one row along X,
-- each an island alone in the sea, nothing between them but water (the request of 2026-11-13: "remove the docks area,
-- it should just be an island. players can swim around in water to reach other player islands"). Pure. Coordinates
-- are studs; plot-local ones are from the plot's origin (`Street.origin(i)`). (The module keeps its old name: the
-- street it once was.)
--
--   north (-Z)   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                |  lot (water)   (( an island: grass, sand, wet sand, foam, shallows ))      |
--                |                the Tree of Life in its middle, the island's sign on its beach |
--   z = 30..58   ~ ~ ~ ~ ~ ~ ~ ~ ~ the open sea (sailboats pass) ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--   south (+Z)
--
-- The founders swim: the water (the sea, the shallows, the foam) lets them through down to an invisible seabed
-- (SEABED_Y) that runs under the whole sea, so they swim from island to island, and the wet sand steps up out of it.
--
-- An island is whole from the start: the top tier's wobbly ellipse (ISLES[TOP]), its coast `cellDist`, the signed
-- distance in studs from the grass's edge (negative on the grass). Round the grass, outward: the sand beach, the wet
-- sand at the waterline, a ring of foam, the light shallows, then the sea. Whole-stud cells (x .. x + 1, z .. z + 1)
-- have a `layer` by their centre's coast distance. The founder starts in the middle of it, on the open ground round
-- the Tree of Life, and the rest of the grass lies in the dark (`darkness`: the pixel filter's, since the request of
-- 2026-11-20 that took the rocks away); each tier opens a wider ring (ISLES[tier], all round the island's heart:
-- `openDist`, the signed distance from the open ground's edge) and an expansion pushes the dark back off it (the
-- request of 2026-11-20: "instead of expansion actually expanding the island, make the player start in the middle of
-- the island first, which is surrounded by rocks. expanding removes these rocks to give space to the player to
-- build"). Buildings stand only on `buildable` cells (a stud in from the coast and from the dark); the founders walk
-- anywhere on the island (`walkable`). The land itself is the same on every tier, and the same tier is the same shape
-- on every plot (a save does not depend on where the island is moored).
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
Street.SEABED_Y = -1.6 -- the invisible floor under the water the founders swim on (the wet sand's foot: one step up)

-- The layers of a cell, outward (0: the open sea).
Street.GRASS, Street.SAND, Street.WET, Street.FOAM, Street.SHALLOW, Street.SEA_CELL = 1, 2, 3, 4, 5, 0
-- Where each layer ends (studs past the grass's edge).
Street.BANDS = { sand = 2.5, wet = 3.5, foam = 4.5, shallow = 8 }

-- The open sea south of the lots, plot-local z (the same for every plot; the sailboats' lanes).
Street.SEA = { z0 = 86, z1 = 114 }
-- Water past the invisible walls (studs): north of the lots, south of the sea and both ends, so no sky shows past the
-- world's edges wherever the view goes.
Street.FAR = 120
Street.END_FAR = 160

-- The lot: the water between two neighbours (plot-local).
-- (far enough north and south for the whole island's shallows: ISLES[TOP])
Street.LOT = { x0 = -Tuning.PlotSpacing / 2, z0 = -72, x1 = Tuning.PlotSpacing / 2, z1 = 86 } :: Rect

-- The island's heart, where a new island's Tree of Life stands (Logic/Tree.SPOT; the request of 2026-11-20: "Remove
-- the campfire in the middle and put the tree in the middle instead"). (A plaza round a campfire stood here till then,
-- and a path ran from it south to a jetty till 2026-11-13.)
Street.CENTER = { x = 0, z = 6 }

-- The open ground by tier: centre, radii, the edge's wobble phases (four sines round it). Every tier's is round the
-- island's heart (the tree's spot), each opening as much ground as that tier's island had when the islands grew (rings the
-- same area as before, so the limits and the prices still fit), and the top tier's is the whole island. Past the first
-- they are circles, so the open ground grows outward evenly every way (the request of 2026-11-20: "make expansion expand
-- outwards evenly instead of resulting in one long stretch"); the wobble keeps each ring's edge its own.
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

-- The signed distance from the open ground's edge at a tier (negative inside): the tier's own shape and every smaller
-- tier's together, so the open ground only ever grows (nothing built near its old edge has to move).
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
	-- (the tier's own shape against the tier below's cells: the same as Street.coast for every cell short of the open
	-- sea, as a cell the tier below leaves out is more than the shallows' width from its coast, and one sum a cell
	-- in place of twenty at the top tier)
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

-- The whole island's cells (the top tier's): its layers and coast distances, whatever the tier.
local function land(): Cells
	return cellsOf(#ISLES)
end

-- Works a tier's cells out now (a few ms to tens of ms at the top tiers), so the moment that needs them (an
-- expansion) doesn't: the server warms every tier at start, the client the next one.
function Street.warm(tier: number)
	land()
	cellsOf(tier)
end

-- The layer of the whole-stud cell x .. x + 1, z .. z + 1 (plot-local): the whole island's, on every tier.
function Street.layer(_tier: number, x: number, z: number): number
	return land().layer[key(x, z)] or Street.SEA_CELL
end

-- The coast distance at a cell's centre (huge out at sea).
function Street.cellDist(_tier: number, x: number, z: number): number
	return land().dist[key(x, z)] or math.huge
end

-- The distance from the open ground's edge at a cell's centre at a tier (negative inside it, huge far out).
function Street.openDist(tier: number, x: number, z: number): number
	return cellsOf(tier).dist[key(x, z)] or math.huge
end

-- Whether cell (x, z) is the island's grass past the open ground at a tier: land not open yet, under the darkness
-- (the pixel filter's: `darkness`), never built on.
function Street.locked(tier: number, x: number, z: number): boolean
	local k = key(x, z)
	local d = land().dist[k]
	return d ~= nil and d <= 0 and (cellsOf(tier).dist[k] or math.huge) > 0
end

------------------------------------------------------------------ the darkness over the land not open yet
-- The request of 2026-11-20: "Remove the rocks and make it a gradient dark filter instead, with the darkness
-- retreating as it expands. This should also make it much less laggy when expanding". The land past the open ground
-- is drawn as the rest of the island; the pixel filter darkens it by how far it lies past the open ground's edge
-- (DARK_RAMP studs from none to the full DARK_MAX), fading out again over the last DARK_COAST studs before the
-- beach, so the beach and the sea stay lit. Every tier's open ground is a ring round the island's heart, so along
-- each direction from it the open ground reaches out to a radius (`openRadius`), and a point's darkness depends on
-- its distance from the heart against that radius: the renderer keeps the radius in DARK_BINS directions for each
-- island and lets it grow between two tiers' as the island expands (`darkAt`).
Street.DARK_RAMP = 6
Street.DARK_COAST = 3
Street.DARK_BINS = 1024
Street.HEART = { x = ISLES[1].cx, z = ISLES[1].cz }

-- The radius a tier's own ring reaches along the direction `a` (radians, atan2(dz, dx) from the heart).
local function ringRadius(t: number, a: number): number
	local s = ISLES[math.clamp(math.floor(t), 1, #ISLES)]
	local c, sn = math.cos(a), math.sin(a)
	local er = 1 / math.sqrt((c / s.rx) ^ 2 + (sn / s.rz) ^ 2)
	local w = 1
	for k = 1, #AMP do
		w += AMP[k] * math.sin(FREQ[k] * a + s.ph[k])
	end
	return er * w
end

-- How far the open ground reaches along direction `a` at a tier: the widest of its ring and every smaller one's (the
-- open ground only grows; openDist is the distance from the heart less this).
function Street.openRadius(tier: number, a: number): number
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local r = 0
	for k = 1, t do
		r = math.max(r, ringRadius(k, a))
	end
	return r
end

-- A tier's open radius in DARK_BINS directions (bin b covers the angle (b + 0.5) / DARK_BINS of a turn from -pi),
-- worked out once per tier.
local radii: { [number]: { number } } = {}
function Street.openRadii(tier: number): { number }
	local t = math.clamp(math.floor(tier), 1, #ISLES)
	local have = radii[t]
	if have then
		return have
	end
	local out = table.create(Street.DARK_BINS, 0)
	for b = 1, Street.DARK_BINS do
		out[b] = Street.openRadius(t, -math.pi + (b - 0.5) / Street.DARK_BINS * 2 * math.pi)
	end
	radii[t] = out
	return out
end

-- The direction bin (1 .. DARK_BINS) and the distance from the heart of plot-local point (x, z).
function Street.darkBin(x: number, z: number): (number, number)
	local dx, dz = x - Street.HEART.x, z - Street.HEART.z
	local a = math.atan2(dz, dx)
	local b = math.floor((a + math.pi) / (2 * math.pi) * Street.DARK_BINS) + 1
	return math.clamp(b, 1, Street.DARK_BINS), math.sqrt(dx * dx + dz * dz)
end

-- How dark a point is (0 lit .. 1 the darkest) at distance `rho` from the heart, where the open ground reaches `open`
-- and the island's grass `coast` along its direction.
function Street.darkAt(rho: number, open: number, coast: number): number
	local past = math.min(rho - open, (coast - rho) * Street.DARK_RAMP / Street.DARK_COAST)
	if past <= 0 then
		return 0
	end
	return math.min(1, past / Street.DARK_RAMP)
end

-- How dark plot-local point (x, z) is at a tier (the pure picture of what the pixel filter draws: sims and specs).
function Street.darkness(tier: number, x: number, z: number): number
	local b, rho = Street.darkBin(x, z)
	return Street.darkAt(rho, Street.openRadii(tier)[b], Street.openRadii(#ISLES)[b])
end

-- Every cell the layers cover (the shallows' outer box) for drawing the island.
function Street.cellBounds(_tier: number): Rect
	return land().bounds
end

-- Whether a building may cover cell (x, z): grass a stud in from the coast and from the dark.
function Street.buildable(tier: number, x: number, z: number): boolean
	local k = key(x, z)
	local d = land().dist[k]
	return d ~= nil and d <= -1 and (cellsOf(tier).dist[k] or math.huge) <= -1
end

-- Whether a founder may stand on cell (x, z): the whole island's grass (dark or not), the beach and the wet sand.
function Street.walkable(tier: number, x: number, z: number): boolean
	local l = Street.layer(tier, x, z)
	return l == Street.GRASS or l == Street.SAND or l == Street.WET
end

-- The open ground's bounding box (plot-local): the scans for a free spot stay inside it.
function Street.plot(tier: number): Rect
	return cellsOf(tier).land
end

-- The origin of plot i (1..MAX) in world studs: the row is centred on x = 0.
function Street.origin(i: number): (number, number)
	return (i - (Street.MAX + 1) / 2) * Street.SPACING, 0
end

-- Which plot a world point is at (its lot, by x; the open sea south of a lot counts as that lot's), 0 off the row.
function Street.plotAt(x: number, z: number): number
	local i = math.floor(x / Street.SPACING + (Street.MAX + 1) / 2 + 0.5)
	if i < 1 or i > Street.MAX then
		return 0
	end
	local ox, oz = Street.origin(i)
	local lx, lz = x - ox, z - oz
	if lx >= Street.LOT.x0 and lx <= Street.LOT.x1 and lz >= Street.LOT.z0 and lz <= Street.SEA.z1 then
		return i
	end
	return 0
end

-- The world's box (world studs): every lot and the sea south of them, and a stretch past each end (the founders swim
-- anywhere inside it).
function Street.bounds(): Rect
	local x0 = Street.origin(1) + Street.LOT.x0 - 24
	local x1 = Street.origin(Street.MAX) + Street.LOT.x1 + 24
	return { x0 = x0, z0 = Street.LOT.z0, x1 = x1, z1 = Street.SEA.z1 }
end

-- Where a founder appears on an island with nothing in the way: just south of a new island's tree (plot-local x, z;
-- Logic/Plot.spawn finds the free spot nearest the tree where it stands).
function Street.spawn(): (number, number)
	return Street.CENTER.x, Street.CENTER.z + 5.5
end

-- The island's sign: on its south beach, west of the tree (plot-local centre, on the sand), on a tier.
function Street.sign(tier: number): (number, number)
	local x = -5
	local z = Street.CENTER.z
	while z < Street.SEA.z0 and Street.layer(tier, x, z) ~= Street.SAND do
		z += 1
	end
	return x + 0.5, z + 0.5
end

return Street
