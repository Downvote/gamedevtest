--!strict
-- The sea (GAME_DESIGN 8; docs/ARCHITECTURE.md 5): every island on the server stands on a plot in one row along X,
-- all joined by one long boardwalk on their south side (the side the camera sees), the open sea beyond. Pure.
-- Coordinates are studs; plot-local ones are from the plot's origin (`Street.origin(i)`), where the lodge's room is
-- centred (Data/Office). (The module keeps its old name: the street it once was.)
--
--   north (-Z)   ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--                |  lot (water)   [ plot (grass, a sand beach round it): the lodge, buildings ]   |
--   z = 30..35   |================ the boardwalk (planks on posts) ===========================|
--                |                 a pier from the boardwalk, a boat at its end               |
--   z = 35..58   ~ ~ ~ ~ ~ ~ ~ ~ ~ the open sea ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~ ~
--   south (+Z)
--
-- An island grows with its tier (PLOT[tier]): out to the east and west and back behind the lodge, always down to
-- the boardwalk. What is not island on a lot is water.
local Tuning = require(script.Parent.Parent.Config.Tuning)

export type Rect = { x0: number, z0: number, x1: number, z1: number }

local Street = {}

Street.MAX = Tuning.MaxPlots
Street.SPACING = Tuning.PlotSpacing
Street.LAWN_Y = -0.5 -- the top of the island's grass (pieces stand here; the lodge floor's top is 0)
Street.SAND_Y = -0.6 -- the beach round an island
Street.WATER_Y = -1.1 -- the sea's surface
Street.BEACH = 2 -- studs of beach round an island's grass (west, north and east)

-- The boardwalk and the sea, plot-local z (the same for every plot).
Street.BOARD = { z0 = 30, z1 = 35 }
Street.SEA = { z0 = 35, z1 = 58 }
-- Water past the invisible walls (studs): north of the lots, south of the sea and both ends, so no sky shows past the
-- world's edges wherever the view goes.
Street.FAR = 120
Street.END_FAR = 160

-- The lot: the water between two neighbours (plot-local).
Street.LOT = { x0 = -Tuning.PlotSpacing / 2, z0 = -24, x1 = Tuning.PlotSpacing / 2, z1 = 30 } :: Rect

-- The island of each tier (plot-local): its grass, where buildings and decor stand.
local PLOTS: { Rect } = {
	{ x0 = -16, z0 = -12, x1 = 24, z1 = 30 },
	{ x0 = -20, z0 = -14, x1 = 30, z1 = 30 },
	{ x0 = -24, z0 = -16, x1 = 36, z1 = 30 },
}

function Street.plot(tier: number): Rect
	return PLOTS[math.clamp(math.floor(tier), 1, #PLOTS)]
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

-- The lodge's doorway: the gap in the room's south rim (Models/OfficeModels), by the room's east edge.
-- `maxX` / `maxZ` are the room's (Data/Office plan).
function Street.door(maxX: number, maxZ: number): (number, number)
	return maxX - 4.5, maxZ
end

-- The sandy path from the doorway down to the boardwalk (plot-local).
function Street.footpath(maxX: number, maxZ: number): Rect
	local dx, dz = Street.door(maxX, maxZ)
	return { x0 = dx - 1.5, z0 = dz, x1 = dx + 1.5, z1 = Street.BOARD.z0 }
end

-- Where a founder appears: on the footpath just outside the doorway (plot-local x, z).
function Street.spawn(maxX: number, maxZ: number): (number, number)
	local dx, dz = Street.door(maxX, maxZ)
	return dx, dz + 3
end

-- The island's sign and the mailbox by the boardwalk, west and east of the path (plot-local centres).
function Street.sign(maxX: number, maxZ: number): (number, number)
	local dx = Street.door(maxX, maxZ)
	return dx - 6, 28.5
end
function Street.mailbox(maxX: number, maxZ: number): (number, number)
	local dx = Street.door(maxX, maxZ)
	return dx + 3.5, 28.5
end

-- Along each plot's stretch (plot-local): lanterns on the boardwalk's posts, and the pier (its x, from the boardwalk
-- out to PIER_Z) where the expedition boat is moored.
Street.LAMPS = { -28, 12 } :: { number }
Street.PIER_X = 0
Street.PIER_Z = 44
Street.PIER_W = 4

-- The pier of plot-local x (where the boat waits).
function Street.pier(): Rect
	return { x0 = Street.PIER_X - Street.PIER_W / 2, z0 = Street.BOARD.z1, x1 = Street.PIER_X + Street.PIER_W / 2, z1 = Street.PIER_Z }
end

return Street
