--!strict
-- The offices (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): the room of each tier, its desks and furniture, and the
-- boxes the camera fits on screen. Pure. Coordinates are studs, plot-local (the plot's origin is Office.origin(i));
-- +Y is up. The camera looks from the south-east corner (+X, +Z) at 45°, so the two back walls stand on the north
-- (minZ) and west (minX) edges and the south and east edges are open, with a low rim.
-- Desks: the desk's centre; a developer sits on its north side facing south (+Z, toward the camera) with the
-- monitor at the desk's south-west corner turned toward them, so faces show above it.
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
	local wallH, lot = 8, 3
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

local function A(x: number, z: number): Anchor
	return { x = x, z = z }
end
local function P(kind: string, x: number, z: number, rot: number?, y: number?): Prop
	return { kind = kind, x = x, z = z, rot = rot or 0, y = y }
end

local PLANS: { Plan } = {
	plan(1, "Garage", "garage", 20, 16, { A(-4, 0), A(1, 0), A(6, 0) }, {
		P("garage_door", 2, -8, 0),
		P("shelf", -8.6, -6.4, 90),
		P("boxes", -5.6, -7, 0),
		P("plant", 8.6, -6.8, 0),
		P("lamp", -8.8, 2.6, 0),
		P("beanbag", -6.6, 5, 0),
		P("cooler", 8.8, 5.4, 0),
		P("poster", -10, -1.5, 90, 4.5),
	}, {}),
	plan(2, "Loft", "loft", 26, 20, { A(-8, -2.5), A(-2.5, -2.5), A(3, -2.5), A(-5.25, 4), A(0.25, 4) }, {
		P("bookcase", -12.3, -7, 90),
		P("whiteboard", -6, -10, 0, 4.2),
		P("coffee", 11.6, -8.6, 0),
		P("plant", 11.8, -4.6, 0),
		P("plant", -12, 8.4, 0),
		P("rug", 8.6, 5.4, 0),
		P("sofa", 8.6, 7.4, 180),
		P("lamp", 11.8, 2.4, 0),
		P("poster", -13, 1, 90, 4.5),
	}, { { wall = "north", at = 3, w = 4 }, { wall = "north", at = 8.5, w = 4 } }),
	plan(3, "Studio Floor", "studio", 32, 24, {
		A(-10, -4.5),
		A(-4.5, -4.5),
		A(1, -4.5),
		A(6.5, -4.5),
		A(-10, 3),
		A(-4.5, 3),
		A(1, 3),
		A(6.5, 3),
	}, {
		P("server", -15.2, -10.4, 90),
		P("trophies", -15.3, -6.4, 90),
		P("tv", -16, 2.4, 90, 3.4),
		P("arcade", 11.6, -11, 0),
		P("arcade", 13.8, -11, 0),
		P("coffee", 15, -2.6, 0),
		P("cooler", 15, 0.4, 0),
		P("rug", 12.4, 7, 0),
		P("sofa", 12.4, 9.4, 180),
		P("plant", 15.2, 4.4, 0),
		P("plant", -15, 10.4, 0),
		P("plant", 9.4, 10.6, 0),
		P("poster", -16, 7.4, 90, 4.5),
	}, { { wall = "north", at = -6, w = 4 }, { wall = "north", at = 0, w = 4 }, { wall = "north", at = 5.5, w = 3 } }),
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
