--!strict
-- The street (GAME_DESIGN 12; docs/ARCHITECTURE.md 5): every studio on the server stands on a plot in one row along
-- X, all facing one road on their south side (the side the camera sees). Pure. Coordinates are studs; plot-local ones
-- are from the plot's origin (`Street.origin(i)`), where the office's room is centred (Data/Office).
--
--   north (-Z)   . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . .
--                |  lot (meadow)   [ plot (lawn): the office, its yard, decor ]    |
--   z = 30       |==================== pavement ======================================|
--   z = 32..42   |                     the road (asphalt, a dashed line)               |
--   z = 42..44   |==================== pavement ======================================|
--   z = 44..58   |  verge: grass, trees, lamp posts                                     |
--   south (+Z)
--
-- A plot grows with the office tier (PLOT[tier]): out to the east and west and back behind the office, always down
-- to the pavement. The lot is the land between two neighbours (LOT): what is not the plot is meadow, a shade darker.
local Tuning = require(script.Parent.Parent.Config.Tuning)

export type Rect = { x0: number, z0: number, x1: number, z1: number }

local Street = {}

Street.MAX = Tuning.MaxPlots
Street.SPACING = Tuning.PlotSpacing
Street.LAWN_Y = -0.5 -- the top of the lawn (decor stands here; the office floor's top is 0)

-- The road and its pavements, plot-local z (the same for every plot: one straight road).
Street.ROAD = { z0 = 32, z1 = 42 }
Street.PAVE_N = { z0 = 30, z1 = 32 }
Street.PAVE_S = { z0 = 42, z1 = 44 }
Street.VERGE = { z0 = 44, z1 = 58 }

-- The lot: the land between two neighbours (plot-local).
Street.LOT = { x0 = -Tuning.PlotSpacing / 2, z0 = -24, x1 = Tuning.PlotSpacing / 2, z1 = 30 } :: Rect

-- The plot of each office tier (plot-local): the player's land, lawn instead of meadow, where decor stands.
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

-- The world's playable box (world studs): every lot, the road and the verge, and a stretch past each end.
function Street.bounds(): Rect
	local x0 = Street.origin(1) + Street.LOT.x0 - 24
	local x1 = Street.origin(Street.MAX) + Street.LOT.x1 + 24
	return { x0 = x0, z0 = Street.LOT.z0, x1 = x1, z1 = Street.VERGE.z1 }
end

-- The office's doorway: the gap in the room's south rim (Models/OfficeModels), by the room's east edge.
-- `maxX` / `maxZ` are the room's (Data/Office plan).
function Street.door(maxX: number, maxZ: number): (number, number)
	return maxX - 4.5, maxZ
end

-- The footpath from the doorway down to the pavement (plot-local).
function Street.footpath(maxX: number, maxZ: number): Rect
	local dx, dz = Street.door(maxX, maxZ)
	return { x0 = dx - 1.5, z0 = dz, x1 = dx + 1.5, z1 = Street.PAVE_N.z0 }
end

-- Where a founder appears: on the footpath just outside the doorway (plot-local x, z).
function Street.spawn(maxX: number, maxZ: number): (number, number)
	local dx, dz = Street.door(maxX, maxZ)
	return dx, dz + 3
end

-- The plot sign and the mailbox by the pavement, west and east of the footpath (plot-local centres).
function Street.sign(maxX: number, maxZ: number): (number, number)
	local dx = Street.door(maxX, maxZ)
	return dx - 6, 28.5
end
function Street.mailbox(maxX: number, maxZ: number): (number, number)
	local dx = Street.door(maxX, maxZ)
	return dx + 3.5, 28.5
end

-- The street's furniture along each plot's stretch (plot-local): lamp posts on the south pavement, trees on the verge.
Street.LAMPS = { -28, 12 } :: { number }
Street.TREES = { { -32, 51 }, { -6, 54 }, { 22, 50 } } :: { { number } }

return Street
