--!strict
-- The lodge (GAME_DESIGN 4; docs/ARCHITECTURE.md 6): the island's one fixed building, the room of each island tier,
-- its furniture, and the boxes the camera fits on screen (the room and a stretch of the island in front of it).
-- Pure. (The module keeps its old name: it was the studio's office.) Coordinates are studs, plot-local (the plot's
-- origin is Office.origin(i)); +Y is up. The camera looks from the south-east corner (+X, +Z) at 45 degrees, so the
-- two back walls stand on the north (minZ) and west (minX) edges and the south and east edges are open, with a low
-- rim. `desks` stays (empty) from the office.
local Street = require(script.Parent.Street)

export type Anchor = { x: number, z: number }
export type Prop = { kind: string, x: number, z: number, rot: number, y: number? }
export type Box = { min: { x: number, y: number, z: number }, max: { x: number, y: number, z: number } }
export type Plan = {
	tier: number,
	name: string,
	theme: string,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	wallH: number,
	lot: number, -- studs of ground round the room
	desks: { Anchor },
	props: { Prop },
	windows: { { wall: string, at: number, w: number } }, -- "north" (x along) / "west" (z along)
	OUTLINE: { Box },
}

local Office = {}

Office.DESK_W = 4
Office.DESK_D = 2.4
Office.DESK_H = 2.2
Office.SEAT_BACK = 1.9 -- a developer sits this far north of the desk's centre
Office.SEAT_H = 1.4 -- the chair's seat height
Office.RIM_H = 0.75 -- the low rim on the open sides
Office.WALL_T = 1 -- wall thickness

local function B(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): Box
	return { min = { x = x0, y = y0, z = z0 }, max = { x = x1, y = y1, z = z1 } }
end

-- The boxes the camera fits (the walls, the floor and the ground strip in front of the open sides).
local function outlineOf(minX: number, maxX: number, minZ: number, maxZ: number, h: number, lot: number): { Box }
	local t = Office.WALL_T
	return {
		B(minX, -0.5, minZ, maxX, 0, maxZ), -- floor
		B(minX - t, 0, minZ - t, maxX, h + 0.5, minZ), -- north wall
		B(minX - t, 0, minZ, minX, h + 0.5, maxZ), -- west wall
		B(minX - t, -0.5, maxZ, maxX + lot, 0, maxZ + lot), -- ground south
		B(maxX, -0.5, minZ - t, maxX + lot, 0, maxZ), -- ground east
	}
end

local function plan(
	tier: number,
	name: string,
	theme: string,
	w: number,
	d: number,
	desks: { Anchor },
	props: { Prop },
	windows: { { wall: string, at: number, w: number } }
): Plan
	local minX, maxX, minZ, maxZ = -w / 2, w / 2, -d / 2, d / 2
	local wallH, lot = 8, 10
	return {
		tier = tier,
		name = name,
		theme = theme,
		minX = minX,
		maxX = maxX,
		minZ = minZ,
		maxZ = maxZ,
		wallH = wallH,
		lot = lot,
		desks = desks,
		props = props,
		windows = windows,
		OUTLINE = outlineOf(minX, maxX, minZ, maxZ, wallH, lot),
	}
end

local function P(kind: string, x: number, z: number, rot: number?, y: number?): Prop
	return { kind = kind, x = x, z = z, rot = rot or 0, y = y }
end

-- The lodge by the island's tier (GAME_DESIGN 4): the castaway's hut, then a lodge, then a harbour hall. No desks: its
-- props are a home's (a map on the wall, a chest of relics, a kettle, cushions).
local PLANS: { Plan } = {
	plan(1, "Castaway Hut", "garage", 16, 12, {}, {
		P("shelf", -6.6, -4.4, 90),
		P("boxes", -3.6, -5, 0),
		P("plant", 6.6, -4.8, 0),
		P("lamp", -6.8, 2.6, 0),
		P("beanbag", -4.6, 3, 0),
		P("barrel", 6.8, 3.4, 0),
		P("poster", -8, -1.5, 90, 4.5),
	}, {}),
	plan(2, "Driftwood Lodge", "loft", 22, 16, {}, {
		P("bookcase", -10.3, -5, 90),
		P("chart", -4, -8, 0, 4.2),
		P("seachest", 9.4, -6.6, 0),
		P("plant", 9.8, -2.6, 0),
		P("plant", -10, 6.4, 0),
		P("rug", 4.6, 3.4, 0),
		P("sofa", 4.6, 5.4, 180),
		P("lamp", 9.8, 2.4, 0),
		P("poster", -11, 1, 90, 4.5),
	}, { { wall = "north", at = 3, w = 4 }, { wall = "north", at = 8, w = 3 } }),
	plan(3, "Harbor Hall", "studio", 28, 20, {}, {
		P("trophies", -13.3, -4.4, 90),
		P("bookcase", -13.3, -8.4, 90),
		P("chart", -6, -10, 0, 4.2),
		P("seachest", 12.6, -0.6, 90),
		P("barrel", 13, 2.4, 0),
		P("rug", 8.4, 5, 0),
		P("sofa", 8.4, 7.4, 180),
		P("plant", 13.2, 6.4, 0),
		P("plant", -13, 8.4, 0),
		P("plant", 6.4, -8.6, 0),
		P("poster", -14, 3.4, 90, 4.5),
	}, { { wall = "north", at = -1, w = 4 }, { wall = "north", at = 5, w = 4 } }),
}
Office.plans = PLANS

function Office.plan(tier: number): Plan
	return PLANS[math.clamp(math.floor(tier), 1, #PLANS)]
end

-- The plot's origin in world studs (Data/Street: plots in a row along X, centred on x = 0).
function Office.origin(plot: number): (number, number)
	return Street.origin(plot)
end

-- Where a developer at desk `a` sits (plot-local): the seat's centre, at seat height.
function Office.seat(a: Anchor): (number, number, number)
	return a.x, Office.SEAT_H, a.z - Office.SEAT_BACK
end

-- The camera's fit points for a tier: the corners of its OUTLINE boxes, flat x, y, z, for a plot at (ox, oz).
function Office.outlinePts(tier: number, ox: number, oz: number): { number }
	local pts = {}
	for _, b in Office.plan(tier).OUTLINE do
		for _, x in { b.min.x, b.max.x } do
			for _, y in { b.min.y, b.max.y } do
				for _, z in { b.min.z, b.max.z } do
					table.insert(pts, ox + x)
					table.insert(pts, y)
					table.insert(pts, oz + z)
				end
			end
		end
	end
	return pts
end

return Office
