--!strict
-- The themed decor: beach, garden, farm, harbour, town, jungle (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- Each theme keeps to its own colours so an island built in one hangs together: the beach sand, pale wood and
-- stripes (coral, yellow, teal, blue and white); the garden soft stone, white paint, roses and blossom; the farm rough
-- wood, straw, tin and twine; the harbour weathered wood, rope, slate iron and red and white; the town painted wood
-- (teal and cream) and slate iron; the jungle mossy stone, carved and painted wood and hanging vines.
-- (Detailed again for the request of 2026-11-19, "detail all decor more, some having animations, as much as in the
-- bakery game and as much as the work/hut/ main buildings": trims, planks, rims and bands, the small props of each
-- theme, flowers at the feet, and a few things that move (Parts.move): a buoy riding its pool, a bucket on its rope, a
-- sign on its chains, floats on a net rack, a ship's wheel, a parrot, a weathervane and a flower clock's hands. The
-- camera looks from the south-east, so the front (+Z) and east (+X) faces carry the detail. The pieces of the late
-- tiers (the Beach Hut, the Red Barn, the Old Galleon, the Hedge Maze, the Flower Clock and the Temple Steps) were
-- built again as big as the buildings of their tiers.)
local Parts = require(script.Parent.Parts)
local Blocks = require(script.Parent.Blocks)

local M: { [string]: Parts.Builder } = {}

local PI = math.pi
local V = Vector3.new
local box, ball, cyl = Parts.box, Parts.ball, Parts.cyl
local move = Parts.move

type Shape = "Block" | "Wedge" | "Cylinder" | "Ball"

-- Any part at the frame `cf` (relative to f); a cylinder's axis runs along that frame's X.
local function put(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, shape: Shape?, name: string?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, shape = shape, name = name, collide = false })
end

-- A beam `t` thick from a to b (points in f). Never quite upright (use a box for that).
local function strut(m: Instance, f: CFrame, a: Vector3, b: Vector3, t: number, color: string, name: string?): BasePart
	return put(m, f, CFrame.lookAt((a + b) / 2, b), t, t, (b - a).Magnitude, color, nil, name)
end

-- A round water surface (the filter ripples it).
local function pool(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?): BasePart
	local p = cyl(m, f, x, y, z, dia, 0.25, color or "water", "Water")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- Upright cylinders stacked from y0 at (x, z), bottom first: { d = diameter, h = height, c = colour }.
type Layer = { d: number, h: number, c: string }
local function stack(m: Instance, f: CFrame, x: number, y0: number, z: number, layers: { Layer }, name: string): number
	local y = y0
	for _, l in layers do
		cyl(m, f, x, y + l.h / 2, z, l.d, l.h, l.c, name)
		y += l.h
	end
	return y
end

-- A ring of four bars in the frame cf's XY plane (a lifebuoy, an anchor's eye): `a` the sides, `b` the top and
-- bottom, 0.75 across with a hole in the middle.
local function ring(m: Instance, f: CFrame, cf: CFrame, a: string, b: string, name: string)
	for _, s in { -1, 1 } do
		put(m, f, cf * CFrame.new(s * 0.25, 0, 0), 0.25, 0.75, 0.25, a, nil, name)
		put(m, f, cf * CFrame.new(0, s * 0.25, 0), 0.25, 0.25, 0.25, b, nil, name)
	end
end

-- A decal's centre on a face at `face` (s = 1 on a +Z or +X face, -1 on a -Z or -X one): a quarter-stud part sunk in
-- the face with its outer side a little proud, so the two never share a plane.
local function on(face: number, s: number?): number
	return face - (s or 1) * 0.08
end

-- A flower standing on y0 at (x, z): a ball of leaves and its bloom (named so the butterflies find it); a small one
-- is a quarter stud across, for a tight corner.
local function tuft(m: Instance, f: CFrame, x: number, y0: number, z: number, bloom: string, small: boolean?, leaf: string?)
	if small then
		ball(m, f, x, y0 + 0.125, z, 0.25, leaf or "leaf", "Leaves")
		box(m, f, x, y0 + 0.3, z, 0.25, 0.25, 0.25, bloom, "Bloom")
	else
		ball(m, f, x, y0 + 0.125, z, 0.5, leaf or "leaf", "Leaves")
		box(m, f, x + 0.06, y0 + 0.375, z + 0.06, 0.25, 0.25, 0.25, bloom, "Bloom")
	end
end

-- A gable roof along X over a w x d box whose top is at y, centred on (x0, zc) in f: the gable ends in the wall
-- colour, each slope in rows of `a` and `b` (every other row a little proud, so the rows read), bargeboards up both
-- ends and a ridge cap the birds sit on. `over` is the eaves' overhang. d / 2 and h are whole quarter studs.
local function gable(m: Instance, f: CFrame, x0: number, zc: number, y: number, w: number, d: number, h: number, a: string, b: string, trim: string, wall: string, over: number?)
	local c = f * CFrame.new(x0, 0, zc)
	local o = over or 0.25
	local W = w + 0.25
	Parts.wedge(m, c, 0, y + h / 2, -d / 4, w, h, d / 2, wall, 0, "Gable")
	Parts.wedge(m, c, 0, y + h / 2, d / 4, w, h, d / 2, wall, PI, "Gable")
	local run = d / 2 + o
	local rise = h * run / (d / 2)
	local len = math.sqrt(run * run + rise * rise)
	local tilt = math.atan2(rise, run)
	local n = math.max(2, math.ceil(len / 0.5 - 0.01))
	local step = (len - 0.5) / (n - 1)
	for _, s in { 1, -1 } do
		local rot = CFrame.Angles(s * tilt, 0, 0)
		local eave = V(0, y + h - rise, s * run)
		local up = V(0, rise, -s * run) / len
		local nrm = V(0, run, s * rise) / len
		for i = 0, n - 1 do
			local p = eave + up * (step * i + 0.25) + nrm * (if i % 2 == 0 then 0.155 else 0.215)
			put(m, c, CFrame.new(p) * rot, W, 0.25, 0.5, if i % 2 == 0 then a else b, nil, "Roof")
		end
		for _, x in { -W / 2, W / 2 } do
			put(m, c, CFrame.new(eave + up * (len / 2) + nrm * 0.215 + V(x, 0, 0)) * rot, 0.25, 0.25, len, trim, nil, "Barge")
		end
	end
	box(m, c, 0, y + h + 0.25, 0, W + 0.25, 0.25, 0.5, trim, "Ridge")
end

-- A small lantern hung or stood with its glass's middle at (x, y, z): a dark cap, the lit glass, a dark foot.
local function lamp(m: Instance, f: CFrame, x: number, y: number, z: number, foot: boolean?)
	box(m, f, x, y + 0.25, z, 0.25, 0.25, 0.25, "black", "LanternCap")
	Parts.glow(m, f, x, y, z, 0.25, 0.25, 0.25, "yellow", "Lantern")
	if foot then
		box(m, f, x, y - 0.25, z, 0.25, 0.25, 0.25, "black", "LanternFoot")
	end
end

------------------------------------------------------------------ the beach

-- Coconut Pile (1 x 1): four coconuts heaped on a patch of pale sand ringed with darker sand: brown ones with their
-- dark eyes and a tuft of husk, a young green one with its stalk, one cut open with its white flesh showing, a palm
-- frond fallen behind with its leaflets fanned up, two shells in the sand.
M.coconuts = function(m, f)
	cyl(m, f, 0, 0, 0, 1.0, 0.25, "sand_dark", "Sand")
	cyl(m, f, -0.06, 0.05, -0.04, 0.75, 0.25, "sand", "Sand")
	-- the frond: its stem along the back, five leaflets fanned up and back from it
	local fr = CFrame.new(0.02, 0.22, -0.25) * CFrame.Angles(0, 0.12, 0)
	put(m, f, fr, 0.75, 0.25, 0.25, "wood", nil, "Stem")
	for k = -2, 2 do
		put(m, f, fr * CFrame.new(k * 0.13, 0.22, -0.03) * CFrame.Angles(-0.3, 0, -k * 0.22), 0.25, 0.5, 0.25, if k % 2 == 0 then "leaf" else "leaf_dark", nil, "Frond")
	end
	-- the coconuts
	ball(m, f, -0.2, 0.42, -0.02, 0.5, "wood_dark", "Coconut")
	ball(m, f, 0.2, 0.42, -0.08, 0.5, "wood", "Coconut")
	ball(m, f, -0.17, 0.42, 0.25, 0.5, "moss", "Coconut")
	ball(m, f, 0.0, 0.78, 0.05, 0.5, "wood", "Coconut")
	box(m, f, 0.1, 0.84, 0.2, 0.25, 0.25, 0.25, "wood_dark", "Eyes")
	box(m, f, 0.32, 0.46, 0.06, 0.25, 0.25, 0.25, "wood_dark", "Eyes")
	box(m, f, -0.3, 0.62, -0.1, 0.25, 0.25, 0.25, "sand_dark", "Husk")
	box(m, f, -0.15, 0.66, 0.29, 0.25, 0.25, 0.25, "wood_dark", "Stalk")
	-- the one cut open
	cyl(m, f, 0.24, 0.3, 0.24, 0.5, 0.25, "wood_dark", "Half")
	cyl(m, f, 0.24, 0.33, 0.24, 0.25, 0.25, "white", "Flesh")
	-- two shells
	cyl(m, f, -0.02, 0.16, 0.36, 0.25, 0.25, "pink", "Shell")
	cyl(m, f, 0.36, 0.16, -0.3, 0.25, 0.25, "cream", "Shell")
end

-- Deck Chair (1 x 2): a frame of pale wood with brass pins at its joints, dark props behind and a bar across each
-- end, blue and white canvas sagging in the seat and leaning back, a yellow cushion at the top; an open book left on
-- the seat. The foot is toward +Z.
M.deckchair = function(m, f)
	for k, s in { { 0.8, 0.46 }, { 0.55, 0.4 }, { 0.3, 0.36 }, { 0.05, 0.36 } } do
		box(m, f, 0, s[2], s[1], 0.5, 0.25, 0.25, if k % 2 == 1 then "blue" else "white", "Canvas")
	end
	-- the back: from the hip (z -0.12, y 0.38) up and back at about 47 degrees
	local a = math.atan2(0.75, 0.7)
	local function back(t: number, x: number, up: number): CFrame
		return CFrame.new(x, 0.38 + math.sin(a) * t + math.cos(a) * up, -0.12 - math.cos(a) * t + math.sin(a) * up) * CFrame.Angles(a, 0, 0)
	end
	for k = 0, 3 do
		put(m, f, back(0.125 + k * 0.25, 0, 0), 0.5, 0.25, 0.25, if k % 2 == 0 then "white" else "blue", nil, "Canvas")
	end
	for _, x in { -0.3, 0.3 } do
		local s = if x < 0 then -1 else 1
		box(m, f, x, 0.48, 0.42, 0.25, 0.25, 1.0, "wood", "Rail")
		put(m, f, back(0.55, x, 0.05), 0.25, 0.25, 1.0, "wood", nil, "Rail")
		box(m, f, x, 0.2, 0.8, 0.25, 0.5, 0.25, "wood", "Leg")
		strut(m, f, V(x, 0.8, -0.55), V(x, 0, -0.82), 0.25, "wood_dark", "Prop")
		-- brass pins at the hip and where the prop meets the back
		box(m, f, x + s * 0.05, 0.46, -0.1, 0.25, 0.25, 0.25, "gold", "Pin")
		box(m, f, x + s * 0.05, 0.8, -0.5, 0.25, 0.25, 0.25, "gold", "Pin")
	end
	box(m, f, 0, 0.12, 0.8, 0.75, 0.25, 0.25, "wood_dark", "Bar")
	box(m, f, 0, 0.12, -0.8, 0.75, 0.25, 0.25, "wood_dark", "Bar")
	put(m, f, back(1.05, 0, 0.05), 0.75, 0.25, 0.25, "wood", nil, "Bar")
	put(m, f, back(0.85, 0, 0.22), 0.5, 0.25, 0.25, "yellow", nil, "Cushion")
	-- a book left open on the seat
	box(m, f, -0.05, 0.52, 0.45, 0.75, 0.25, 0.25, "berry_red", "Book")
	box(m, f, -0.05, 0.58, 0.45, 0.5, 0.25, 0.25, "paper", "Pages")
end

-- Beach Umbrella (2 x 2): a pale wooden pole with a dark collar, stood in a mound of sand; a canopy of coral and white
-- panels with a scalloped edge in the other colour, a white finial and a coral pennant on top. In its shade a striped
-- towel with sunglasses on it, a cool box with its handle and catch, a bucket with a spade leaning on it, and a
-- sandcastle of two towers with a flag.
M.umbrella = function(m, f)
	cyl(m, f, 0, 0, 0, 1.0, 0.25, "sand_dark", "Mound")
	cyl(m, f, 0, 0.1, 0, 0.5, 0.25, "sand", "Mound")
	box(m, f, 0, 1.15, 0, 0.25, 2.3, 0.25, "wood", "Pole")
	cyl(m, f, 0, 1.3, 0, 0.5, 0.25, "wood_dark", "Collar")
	local top, tilt = 2.3, math.rad(24)
	for k = 0, 7 do
		local coloured = k % 2 == 0
		local cf = CFrame.new(0, top - (if coloured then 0 else 0.08), 0) * CFrame.Angles(0, k * PI / 4, 0) * CFrame.Angles(tilt, 0, 0)
		put(m, f, cf * CFrame.new(0, -0.125, 0.45), if coloured then 0.5 else 0.75, 0.25, 1.0, if coloured then "coral" else "white", nil, "Canopy")
		-- the scallop under the panel's outer edge, hanging straight down
		put(m, f, cf * CFrame.new(0, -0.3, 0.86) * CFrame.Angles(-tilt, 0, 0), 0.5, 0.25, 0.25, if coloured then "white" else "coral", nil, "Valance")
	end
	cyl(m, f, 0, top + 0.1, 0, 0.25, 0.25, "white", "Finial")
	box(m, f, 0, top + 0.45, 0, 0.25, 0.5, 0.25, "white", "PennantPole")
	Parts.wedge(m, f, 0.25, top + 0.55, 0, 0.25, 0.25, 0.5, "coral", -PI / 2, "Pennant")
	-- a towel in stripes, sunglasses on it
	for k, c in { "teal", "yellow", "white", "yellow", "teal" } do
		box(m, f, 0.55, 0.0, -0.3 + (k - 1) * 0.25, 0.75, 0.25, 0.25, c, "Towel")
	end
	box(m, f, 0.55, 0.12, 0.2, 0.5, 0.25, 0.25, "black", "Glasses")
	-- the cool box
	box(m, f, -0.55, 0.25, -0.5, 0.5, 0.5, 0.5, "blue", "CoolBox")
	box(m, f, -0.55, 0.625, -0.5, 0.5, 0.25, 0.5, "white", "Lid")
	box(m, f, -0.55, 0.8, -0.5, 0.5, 0.25, 0.25, "steel", "Handle")
	box(m, f, -0.55, 0.42, on(-0.25), 0.25, 0.25, 0.25, "white", "Catch")
	-- the bucket and its spade
	cyl(m, f, 0.62, 0.125, -0.72, 0.5, 0.25, "yellow", "Bucket")
	cyl(m, f, 0.62, 0.375, -0.72, 0.5, 0.25, "berry_red", "Bucket")
	strut(m, f, V(0.82, 0.05, -0.45), V(0.72, 0.75, -0.62), 0.25, "blue", "Spade")
	box(m, f, 0.82, 0.12, -0.42, 0.25, 0.25, 0.25, "blue", "Blade")
	-- the sandcastle: a darker base, a keep between two towers, a flag
	box(m, f, -0.5, 0.125, 0.6, 0.75, 0.25, 0.5, "sand_dark", "Castle")
	box(m, f, -0.5, 0.375, 0.6, 0.5, 0.25, 0.25, "sand", "Keep")
	for _, x in { -0.75, -0.25 } do
		box(m, f, x, 0.5, 0.6, 0.25, 0.5, 0.25, "sand", "Tower")
	end
	box(m, f, -0.25, 0.95, 0.6, 0.25, 0.5, 0.25, "white", "PennantPole")
	Parts.wedge(m, f, -0.05, 1.07, 0.6, 0.25, 0.25, 0.5, "pink", -PI / 2, "Pennant")
end

-- A surfboard standing on its tail at (x, z), leaning back by `lean`: rounded at both ends, a stripe down it.
local function board(m: Instance, f: CFrame, x: number, z: number, h: number, lean: number, color: string, stripe: string)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(-lean, 0, 0) * CFrame.new(0, h / 2, 0)
	put(m, f, cf, 0.5, h - 0.5, 0.25, color, nil, "Board")
	for _, s in { -1, 1 } do
		put(m, f, cf * CFrame.new(0, s * (h / 2 - 0.25), 0) * CFrame.Angles(0, PI / 2, 0), 0.25, 0.5, 0.5, color, "Cylinder", "Board")
	end
	put(m, f, cf * CFrame.new(0, 0, 0.06), 0.25, h - 0.75, 0.25, stripe, nil, "Stripe")
end

-- Surfboard Rack (2 x 1): a rack of pale wood on dark feet with a rail behind and a lip in front, three boards
-- leaning on its bar (coral, yellow and teal) between dark pegs, each with a stripe down it; a little cream sign with
-- a teal wave on the left post, a striped towel hung on the right one, a spare fin on the left foot and a bar of wax
-- on the right one.
M.surfboards = function(m, f)
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 0.625, -0.3, 0.25, 1.25, 0.25, "wood", "Post")
		box(m, f, x, 0.125, 0.05, 0.25, 0.25, 0.75, "wood_dark", "Foot")
	end
	box(m, f, 0, 1.15, -0.3, 2.0, 0.25, 0.25, "wood", "Bar")
	for _, x in { -0.25, 0.25 } do
		box(m, f, x, 1.15, -0.15, 0.25, 0.25, 0.25, "wood_dark", "Peg")
	end
	box(m, f, -0.875, 0.95, -0.12, 0.25, 0.5, 0.25, "cream", "Sign")
	box(m, f, -0.875, 0.95, -0.09, 0.25, 0.25, 0.25, "teal", "Sign")
	box(m, f, 0, 0.2, -0.3, 1.5, 0.25, 0.25, "wood_dark", "Rail")
	box(m, f, 0, 0.125, 0.37, 1.5, 0.25, 0.25, "wood_dark", "Lip")
	board(m, f, -0.5, 0.15, 1.75, math.rad(12), "coral", "white")
	board(m, f, 0, 0.15, 1.5, math.rad(14), "yellow", "teal")
	board(m, f, 0.5, 0.15, 1.75, math.rad(12), "teal", "white")
	-- the towel on the right post, the fin and the wax
	box(m, f, 0.875, 0.85, -0.1, 0.25, 0.75, 0.25, "yellow", "Towel")
	box(m, f, 0.875, 0.6, -0.07, 0.25, 0.25, 0.25, "blue", "Towel")
	Parts.wedge(m, f, -0.875, 0.37, 0.25, 0.25, 0.25, 0.5, "black", 0, "Fin")
	box(m, f, 0.875, 0.37, 0.3, 0.25, 0.25, 0.25, "white", "Wax")
end

-- Lifeguard Chair (2 x 2): four white legs leaning in, a ladder of rungs up the front, a platform trimmed in white with
-- a seat (a yellow cushion on it, a teal towel over its back, binoculars on an arm, a megaphone by it) under a red and
-- white roof with a scalloped edge and a red cross sign on its front, a lifebuoy hung on the side and two flags on a
-- pole to say the sea is watched.
M.lifeguard = function(m, f)
	local top = 2.25
	local function at(y: number): number -- a leg's distance out from the middle at height y
		return 0.8 - 0.25 * y / top
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		strut(m, f, V(c[1] * 0.8, 0, c[2] * 0.8), V(c[1] * at(top), top, c[2] * at(top)), 0.25, "white", "Leg")
	end
	for _, y in { 0.5, 0.95, 1.4, 1.85 } do
		box(m, f, 0, y, at(y), at(y) * 2, 0.25, 0.25, "wood", "Rung")
	end
	box(m, f, at(1.0), 1.0, 0, 0.25, 0.25, at(1.0) * 2, "white", "Brace")
	box(m, f, -at(1.0), 1.0, 0, 0.25, 0.25, at(1.0) * 2, "white", "Brace")
	box(m, f, 0, 1.0, -at(1.0), at(1.0) * 2, 0.25, 0.25, "white", "Brace")
	-- the platform and its trim, the seat
	box(m, f, 0, top + 0.125, 0, 1.5, 0.25, 1.5, "wood", "Platform")
	box(m, f, 0, top + 0.06, on(0.75), 1.5, 0.25, 0.25, "white", "Trim")
	box(m, f, on(0.75), top + 0.06, 0, 0.25, 0.25, 1.5, "white", "Trim")
	box(m, f, 0, top + 0.375, -0.1, 1.0, 0.25, 0.75, "white", "Seat")
	box(m, f, 0, top + 0.6, 0.0, 0.75, 0.25, 0.5, "yellow", "Cushion")
	box(m, f, 0, top + 0.75, -0.5, 1.0, 0.75, 0.25, "white", "Back")
	box(m, f, -0.2, top + 0.85, -0.4, 0.5, 0.75, 0.25, "teal", "Towel")
	box(m, f, -0.2, top + 0.6, -0.37, 0.5, 0.25, 0.25, "white", "Towel")
	for _, x in { -0.5, 0.5 } do
		box(m, f, x, top + 0.625, -0.1, 0.25, 0.25, 0.75, "wood", "Arm")
	end
	box(m, f, 0.5, top + 0.85, 0.05, 0.25, 0.25, 0.5, "black", "Binoculars")
	Parts.log(m, f, -0.55, top + 0.4, 0.45, 0.5, 0.25, "white", "Megaphone")
	Parts.log(m, f, -0.3, top + 0.45, 0.45, 0.25, 0.5, "berry_red", "Megaphone")
	-- the roof on four posts, striped red and white with a scalloped front; the back left post runs on up as the
	-- flagpole
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local tall = c[1] == -1 and c[2] == -1
		local h = if tall then 2.25 else 1.25
		box(m, f, c[1] * 0.625, top + 0.25 + h / 2, c[2] * 0.625, 0.25, h, 0.25, "white", if tall then "FlagPole" else "Post")
	end
	for k = -1, 1 do
		box(m, f, k * 0.5, top + 1.625, 0, 0.5, 0.25, 1.5, if k == 0 then "white" else "berry_red", "Roof")
		box(m, f, k * 0.5, top + 1.42, 0.7, 0.5, 0.25, 0.25, if k == 0 then "berry_red" else "white", "Valance")
	end
	box(m, f, 0, top + 2.0, 0.55, 0.75, 0.5, 0.25, "white", "Sign")
	box(m, f, 0, top + 2.0, 0.6, 0.5, 0.25, 0.25, "berry_red", "Cross")
	box(m, f, 0, top + 2.0, 0.62, 0.25, 0.5, 0.25, "berry_red", "Cross")
	box(m, f, -0.125, top + 2.125, -0.625, 0.75, 0.25, 0.25, "berry_red", "Flag")
	box(m, f, -0.125, top + 1.875, -0.625, 0.75, 0.25, 0.25, "yellow", "Flag")
	-- a lifebuoy on the right-hand side
	ring(m, f, CFrame.new(at(1.55) + 0.15, 1.55, 0) * CFrame.Angles(0, PI / 2, 0), "berry_red", "white", "Lifebuoy")
end

------------------------------------------------------------------ the garden

-- Garden Gnome (1 x 1): on a round mossy stone, dark boots under a blue coat flared at the hem, a black belt with a
-- gold buckle, blue arms and pink hands (one on the handle of a little spade stuck in the stone), a white beard, a
-- pink nose under heavy white brows, a tall red hat with its tip bent back; two small flowers by the stone.
M.gnome = function(m, f)
	cyl(m, f, 0, 0.05, 0, 0.75, 0.25, "rock", "Stone")
	box(m, f, -0.22, 0.13, -0.18, 0.25, 0.25, 0.25, "moss", "Moss")
	box(m, f, 0, 0.3, 0.06, 0.5, 0.25, 0.5, "wood_dark", "Boots")
	cyl(m, f, 0, 0.55, 0, 0.75, 0.25, "blue", "Coat")
	cyl(m, f, 0, 0.85, 0, 0.5, 0.5, "blue", "Coat")
	box(m, f, 0, 0.7, 0.17, 0.5, 0.25, 0.25, "black", "Belt")
	box(m, f, 0, 0.7, 0.22, 0.25, 0.25, 0.25, "gold", "Buckle")
	for _, x in { -0.32, 0.32 } do
		box(m, f, x, 0.85, 0.04, 0.25, 0.5, 0.25, "blue", "Arm")
		ball(m, f, x, 0.58, 0.08, 0.25, "skin2", "Hand")
	end
	box(m, f, 0, 1.0, 0.18, 0.5, 0.5, 0.25, "white", "Beard")
	ball(m, f, 0, 1.3, 0, 0.5, "skin2", "Head")
	ball(m, f, 0, 1.27, 0.24, 0.25, "pink", "Nose")
	box(m, f, 0, 1.42, 0.18, 0.5, 0.25, 0.25, "white", "Brows")
	cyl(m, f, 0, 1.65, 0, 0.5, 0.5, "berry_red", "Hat")
	put(m, f, CFrame.new(0, 2.08, -0.06) * CFrame.Angles(-0.3, 0, 0), 0.25, 0.5, 0.25, "berry_red", nil, "Hat")
	ball(m, f, 0, 2.32, -0.16, 0.25, "berry_red", "Hat")
	-- the spade by his right hand
	strut(m, f, V(0.36, 0.15, 0.28), V(0.36, 0.78, 0.18), 0.25, "wood", "Handle")
	box(m, f, 0.36, 0.84, 0.17, 0.25, 0.25, 0.25, "wood_dark", "Grip")
	box(m, f, 0.36, 0.2, 0.28, 0.25, 0.25, 0.25, "steel", "Blade")
	tuft(m, f, -0.36, 0, 0.33, "pink", true)
	tuft(m, f, 0.36, 0, -0.33, "yellow", true)
end

-- Wheelbarrow (2 x 1): a red tray with a rolled steel rim, its nose over a black tyre on a steel hub (toward +X) held
-- by a steel fork; dark legs braced across, wooden handles with dark grips. In it a heap of soil with a trowel stuck in
-- it, three seedlings in clay pots and a pair of yellow gloves over the back rim.
M.wheelbarrow = function(m, f)
	Parts.logZ(m, f, 0.7, 0.25, 0, 0.25, 0.5, "black", "Wheel")
	Parts.logZ(m, f, 0.7, 0.25, 0.08, 0.25, 0.25, "steel", "Hub")
	for _, z in { -0.2, 0.2 } do
		strut(m, f, V(0.7, 0.25, z), V(0.35, 0.6, z), 0.25, "steel_dark", "Fork")
	end
	box(m, f, -0.2, 0.65, 0, 0.75, 0.5, 0.75, "berry_red", "Tray")
	Parts.wedge(m, f, 0.42, 0.65, 0, 0.75, 0.5, 0.5, "berry_red", -PI / 2, "Tray")
	box(m, f, -0.2, 0.92, on(0.375), 0.75, 0.25, 0.25, "steel", "Rim")
	box(m, f, -0.2, 0.92, on(-0.375, -1), 0.75, 0.25, 0.25, "steel", "Rim")
	box(m, f, on(-0.575, -1), 0.92, 0, 0.25, 0.25, 0.75, "steel", "Rim")
	for _, z in { -0.3, 0.3 } do
		box(m, f, -0.58, 0.55, z, 0.75, 0.25, 0.25, "wood", "Handle")
		box(m, f, -0.86, 0.55, z, 0.25, 0.25, 0.25, "wood_dark", "Grip")
		box(m, f, -0.35, 0.2, z, 0.25, 0.5, 0.25, "steel_dark", "Leg")
	end
	box(m, f, -0.35, 0.2, 0, 0.25, 0.25, 0.5, "steel_dark", "Brace")
	-- the load
	box(m, f, -0.15, 0.92, 0, 0.75, 0.25, 0.5, "wood_dark", "Soil")
	ball(m, f, -0.2, 1.0, 0, 0.5, "wood_dark", "Soil")
	for _, p in { { 0.08, 0.14 }, { -0.42, 0.14 }, { -0.3, -0.15 } } do
		cyl(m, f, p[1], 1.08, p[2], 0.25, 0.25, "clay", "Pot")
		ball(m, f, p[1], 1.28, p[2], 0.25, "leaf", "Seedling")
	end
	put(m, f, CFrame.new(0.08, 1.1, -0.14) * CFrame.Angles(0, 0, -0.35), 0.25, 0.25, 0.25, "steel", nil, "Trowel")
	put(m, f, CFrame.new(0.15, 1.32, -0.14) * CFrame.Angles(0, 0, -0.35), 0.25, 0.5, 0.25, "wood", nil, "Handle")
	box(m, f, -0.5, 1.08, 0.12, 0.25, 0.25, 0.25, "yellow", "Glove")
	box(m, f, -0.47, 1.0, -0.1, 0.25, 0.25, 0.25, "yellow", "Glove")
end

-- Birdbath (1 x 1): a grey stone foot, a column with a carved band and a flared top, a wide bowl with a pale lip full
-- of clear water, moss on the lip and ivy climbing the column; a bluebird on the far rim dipping its head to drink
-- (it moves), flowers round the foot.
M.birdbath = function(m, f)
	cyl(m, f, 0, 0.06, 0, 0.75, 0.25, "rock_dark", "Foot")
	cyl(m, f, 0, 0.435, 0, 0.5, 0.5, "rock", "Column")
	cyl(m, f, 0, 0.5, 0, 0.75, 0.25, "rock_dark", "Band")
	cyl(m, f, 0, 0.8, 0, 0.75, 0.25, "rock", "Flare")
	cyl(m, f, 0, 0.95, 0, 1.0, 0.25, "rock", "Bowl")
	cyl(m, f, 0, 1.2, 0, 1.0, 0.25, "pavement", "Lip")
	pool(m, f, 0, 1.22, 0, 0.75, "shallow")
	box(m, f, -0.35, 1.3, 0.15, 0.25, 0.25, 0.25, "moss", "Moss")
	box(m, f, 0.22, 0.4, 0.12, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	ball(m, f, 0.2, 0.72, 0.16, 0.25, "leaf", "Ivy")
	-- the bird on the far rim facing +X, rocking on its feet to drink
	local hub = V(0.05, 1.33, -0.36)
	for _, p in {
		box(m, f, -0.05, 1.45, -0.36, 0.5, 0.25, 0.25, "blue", "Bird"),
		box(m, f, 0.2, 1.62, -0.36, 0.25, 0.25, 0.25, "blue", "Bird"),
		box(m, f, 0.35, 1.58, -0.36, 0.25, 0.25, 0.25, "orange", "Beak"),
		box(m, f, -0.3, 1.52, -0.36, 0.25, 0.25, 0.25, "jeans", "Tail"),
		box(m, f, 0.08, 1.42, -0.3, 0.25, 0.25, 0.25, "orange", "Breast"),
		box(m, f, -0.08, 1.5, -0.27, 0.25, 0.25, 0.25, "jeans", "Wing"),
	} do
		move(p, "swing", hub, "Z", 1.4, 0.22)
	end
	tuft(m, f, 0.36, 0, 0.33, "purple", true)
	tuft(m, f, -0.36, 0, 0.33, "pink", true)
	tuft(m, f, 0.36, 0, -0.33, "yellow", true)
end

-- Beehive (1 x 1): a hive of painted boxes (white, yellow, white) with hand holds, on a dark stand with splayed legs, a
-- landing board under the dark way in with a drop of honey on it, handles on the side, a wooden lid under a clay roof
-- with a ridge, three striped bees hovering over it (they bob).
M.beehive = function(m, f)
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		strut(m, f, V(c[1] * 0.33, 0, c[2] * 0.33), V(c[1] * 0.25, 0.3, c[2] * 0.25), 0.25, "wood_dark", "Leg")
	end
	box(m, f, 0, 0.375, 0, 0.75, 0.25, 0.75, "wood_dark", "Stand")
	box(m, f, 0, 0.75, 0, 0.75, 0.5, 0.75, "white", "Box")
	box(m, f, 0, 1.25, 0, 0.75, 0.5, 0.75, "yellow", "Box")
	box(m, f, 0, 1.625, 0, 0.75, 0.25, 0.75, "white", "Box")
	box(m, f, 0, 1.875, 0, 1.0, 0.25, 1.0, "wood", "Lid")
	Parts.wedge(m, f, 0, 2.125, -0.25, 1.0, 0.25, 0.5, "clay", 0, "Roof")
	Parts.wedge(m, f, 0, 2.125, 0.25, 1.0, 0.25, 0.5, "clay", PI, "Roof")
	box(m, f, 0, 2.3, 0, 1.0, 0.25, 0.25, "brick", "Ridge")
	box(m, f, 0, 0.6, on(0.375), 0.5, 0.25, 0.25, "black", "Door")
	box(m, f, 0, 0.47, 0.37, 0.5, 0.25, 0.25, "wood", "Landing")
	box(m, f, 0.15, 0.6, 0.37, 0.25, 0.25, 0.25, "gold", "Honey")
	for _, y in { 0.8, 1.3 } do
		box(m, f, on(0.375), y, 0, 0.25, 0.25, 0.25, "wood_dark", "Handle")
		box(m, f, 0, y + 0.05, on(0.375), 0.5, 0.25, 0.25, if y < 1 then "pavement" else "straw", "HandHold")
	end
	-- the bees, each with its dark stripe, bobbing out of step
	for k, b in { { 0.25, 2.65, 0.2 }, { -0.22, 2.8, -0.1 }, { 0.05, 2.98, 0.3 } } do
		local hub = V(b[1], b[2], b[3])
		move(ball(m, f, b[1], b[2], b[3], 0.25, "yellow", "Bee"), "bob", hub, "Y", 1.8, 0.1, k * 2.1)
		move(box(m, f, b[1] - 0.08, b[2], b[3], 0.25, 0.25, 0.25, "black", "Bee"), "bob", hub, "Y", 1.8, 0.1, k * 2.1)
	end
end

-- Rose Trellis (2 x 1): a white frame of two posts with cream ball finials, a top and a bottom rail and a cream rail
-- across its middle, in a bed of earth edged with stones; a rose climbing it, red and pink roses and buds among its
-- leaves, and a green watering can left on the bed. (Its openings are kept wide: slats a quarter stud deep close any
-- narrower gap at the view's angle.)
M.trellis = function(m, f)
	box(m, f, 0, 0, 0.1, 1.75, 0.25, 0.75, "wood_dark", "Bed")
	for k, x in { 0, 0.6 } do
		box(m, f, x, 0.1, 0.36, 0.5, 0.25, 0.25, if k == 1 then "rock" else "pavement", "Edging")
	end
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.0, -0.25, 0.25, 2.0, 0.25, "white", "Post")
		ball(m, f, x, 2.15, -0.25, 0.25, "cream", "Finial")
	end
	box(m, f, 0, 1.875, -0.25, 2.0, 0.25, 0.25, "white", "Rail")
	box(m, f, 0, 0.25, -0.25, 1.5, 0.25, 0.25, "white", "Rail")
	box(m, f, 0, 1.06, -0.25, 1.5, 0.25, 0.25, "cream", "Rail")
	for k, l in { { -0.55, 0.45 }, { -0.4, 0.95 }, { -0.15, 1.45 }, { 0.35, 1.6 }, { 0.55, 1.05 }, { 0.3, 0.4 }, { -0.75, 0.25 } } do
		ball(m, f, l[1], l[2], -0.05, 0.5, if k % 2 == 1 then "leaf_dark" else "leaf", "Leaves")
	end
	for k, r in { { -0.45, 0.65 }, { -0.25, 1.2 }, { 0.05, 1.65 }, { 0.55, 1.35 }, { 0.45, 0.75 }, { 0.1, 0.45 } } do
		box(m, f, r[1], r[2], 0.17, 0.25, 0.25, 0.25, if k % 2 == 0 then "pink" else "berry_red", "Bloom")
	end
	for _, b in { { -0.6, 1.15 }, { 0.2, 1.05 } } do
		ball(m, f, b[1], b[2], 0.15, 0.25, "pink", "Bud")
	end
	-- the watering can
	cyl(m, f, -0.62, 0.32, 0.25, 0.5, 0.25, "green", "Can")
	strut(m, f, V(-0.4, 0.32, 0.3), V(-0.2, 0.5, 0.36), 0.25, "green", "Spout")
	box(m, f, -0.72, 0.52, 0.25, 0.25, 0.25, 0.25, "green", "Handle")
end

-- Sundial (1 x 1): a square pedestal of pale stone on two steps, a grey panel set in its front and side, a capital,
-- a brass dial with four dark hour marks and the slate blade with its shadow; ivy climbing a corner, moss on the
-- step, small flowers on the step's corners.
M.sundial = function(m, f)
	box(m, f, 0, 0.06, 0, 1.0, 0.25, 1.0, "rock", "Step")
	box(m, f, 0, 0.31, 0, 0.75, 0.25, 0.75, "pavement", "Step")
	box(m, f, 0, 0.685, 0, 0.5, 0.5, 0.5, "cream", "Pedestal")
	box(m, f, 0, 0.685, on(0.25), 0.25, 0.25, 0.25, "pavement", "Panel")
	box(m, f, on(0.25), 0.685, 0, 0.25, 0.25, 0.25, "pavement", "Panel")
	box(m, f, 0, 1.06, 0, 0.75, 0.25, 0.75, "pavement", "Cap")
	cyl(m, f, 0, 1.25, 0, 0.75, 0.25, "gold", "Dial")
	for _, p in { { 0.25, 0 }, { -0.25, 0 }, { 0, 0.25 }, { 0, -0.25 } } do
		box(m, f, p[1], 1.26, p[2], 0.25, 0.25, 0.25, "wood_dark", "Hour")
	end
	Parts.wedge(m, f, 0, 1.55, 0, 0.25, 0.5, 0.5, "slate", PI / 2, "Blade")
	Parts.turned(m, f, 0.12, 1.29, 0.12, 0.25, 0.25, 0.5, PI / 4, "rock_dark", "Shadow")
	box(m, f, 0.25, 0.72, 0.25, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	ball(m, f, 0.22, 0.98, 0.24, 0.25, "leaf", "Ivy")
	box(m, f, -0.28, 0.45, 0.28, 0.25, 0.25, 0.25, "moss", "Moss")
	tuft(m, f, 0.37, 0.185, 0.37, "purple", true)
	tuft(m, f, -0.37, 0.185, 0.37, "pink", true)
	tuft(m, f, 0.37, 0.185, -0.37, "yellow", true)
end

------------------------------------------------------------------ the farm

-- A milk churn standing on y0 at (x, z): a dark foot ring, the tin body, a dark band at the shoulder, a dark neck, a
-- wide lid with a knob, a handle toward the view.
local function churn(m: Instance, f: CFrame, x: number, y0: number, z: number, body: number)
	local y = stack(m, f, x, y0, z, {
		{ d = 0.5, h = 0.25, c = "steel_dark" },
		{ d = 0.5, h = body, c = "steel" },
		{ d = 0.5, h = 0.25, c = "steel_dark" },
		{ d = 0.25, h = 0.25, c = "steel_dark" },
		{ d = 0.5, h = 0.25, c = "steel" },
	}, "Churn")
	ball(m, f, x, y + 0.06, z, 0.25, "steel_dark", "Knob")
	box(m, f, x + 0.15, y0 + 0.25 + body * 0.6, z + 0.15, 0.25, 0.25, 0.25, "steel_dark", "Handle")
end

-- Milk Churns (1 x 1): a tall tin churn and a short one on a stand of two planks on dark runners, two bottles of milk
-- with cream caps beside them and a wisp of straw.
M.churns = function(m, f)
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.06, 0, 0.25, 0.25, 0.75, "wood_dark", "Runner")
	end
	box(m, f, 0, 0.25, -0.25, 1.0, 0.25, 0.5, "wood", "Plank")
	box(m, f, 0, 0.25, 0.25, 1.0, 0.25, 0.5, "sand_dark", "Plank")
	churn(m, f, -0.22, 0.375, 0.22, 0.5)
	churn(m, f, 0.22, 0.375, -0.22, 0.25)
	for _, b in { { 0.32, 0.32 }, { 0.36, 0.1 } } do
		cyl(m, f, b[1], 0.5, b[2], 0.25, 0.25, "white", "Bottle")
		cyl(m, f, b[1], 0.7, b[2], 0.25, 0.25, "cream", "Cap")
	end
	put(m, f, CFrame.new(-0.22, 0.42, -0.25) * CFrame.Angles(0, 0.6, 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
	box(m, f, -0.36, 0.45, -0.1, 0.25, 0.25, 0.25, "yellow", "Straw")
end

-- Hay Bale (2 x 1): a long bale pressed in flakes of two shades, its cut end paler with darker stalks in it, tied with
-- two bands of twine knotted on top; a white hen sitting on it pecking at the straw (her head moves), a pitchfork laid
-- along the back and wisps of loose straw on top.
M.haybale = function(m, f)
	for k = 0, 5 do
		box(m, f, -0.75 + k * 0.25, 0.375, 0, 0.25, 0.75, 0.75, if k % 2 == 0 then "straw" else "yellow", "Bale")
	end
	box(m, f, 0.75, 0.375, 0, 0.25, 0.75, 0.75, "sand", "End")
	box(m, f, on(0.875), 0.25, -0.15, 0.25, 0.25, 0.25, "sand_dark", "Stalks")
	box(m, f, on(0.875), 0.55, 0.18, 0.25, 0.25, 0.25, "sand_dark", "Stalks")
	for _, x in { -0.5, 0.25 } do
		box(m, f, x, 0.375, on(0.375), 0.25, 0.75, 0.25, "wood_dark", "Twine")
		box(m, f, x, on(0.75), 0, 0.25, 0.25, 0.75, "wood_dark", "Twine")
		box(m, f, x, 0.8, 0.12, 0.25, 0.25, 0.25, "wood_dark", "Knot")
	end
	-- the pitchfork laid along the back
	strut(m, f, V(-0.8, 0.82, -0.25), V(0.35, 0.82, -0.27), 0.25, "wood", "Handle")
	box(m, f, 0.5, 0.82, -0.25, 0.25, 0.25, 0.5, "steel", "Fork")
	box(m, f, 0.68, 0.82, -0.25, 0.25, 0.25, 0.25, "steel", "Tine")
	-- the hen, facing +X, her head pecking
	ball(m, f, -0.1, 0.98, 0.02, 0.5, "white", "Hen")
	box(m, f, -0.36, 1.15, 0.02, 0.25, 0.25, 0.25, "white", "Tail")
	box(m, f, -0.12, 1.0, 0.2, 0.25, 0.25, 0.25, "cream", "Wing")
	local neck = V(0.08, 1.1, 0.02)
	move(box(m, f, 0.2, 1.25, 0.02, 0.25, 0.25, 0.25, "white", "Head"), "swing", neck, "Z", 2.2, 0.3)
	move(box(m, f, 0.36, 1.22, 0.02, 0.25, 0.25, 0.25, "orange", "Beak"), "swing", neck, "Z", 2.2, 0.3)
	move(box(m, f, 0.18, 1.42, 0.02, 0.25, 0.25, 0.25, "berry_red", "Comb"), "swing", neck, "Z", 2.2, 0.3)
	-- loose straw on top
	put(m, f, CFrame.new(-0.62, 0.8, 0.15) * CFrame.Angles(0, 0.4, math.rad(25)), 0.5, 0.25, 0.25, "yellow", nil, "Tuft")
	put(m, f, CFrame.new(0.55, 0.8, 0.18) * CFrame.Angles(0, -0.5, 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
end

-- Scarecrow (1 x 1): turned to face the view with its arms out: a post and crossbar in a mound of earth, a red shirt
-- with a yellow patch, a blue patch on a sleeve and a cream button, a rope belt, blue trousers with straw at the cuffs,
-- straw hands, an orange scarf, a sacking head with stitched eyes and mouth under a straw hat with a red band and a
-- pink flower in it; a crow sitting on its arm, bobbing (it moves).
M.scarecrow = function(m, f)
	local g = f * CFrame.Angles(0, PI / 4, 0)
	cyl(m, g, 0, 0, 0, 0.5, 0.25, "wood_dark", "Mound")
	box(m, g, 0, 0.875, -0.15, 0.25, 1.75, 0.25, "wood_dark", "Post")
	box(m, g, 0, 1.45, -0.04, 1.0, 0.25, 0.25, "wood_dark", "Bar")
	box(m, g, 0, 1.45, 0, 1.0, 0.25, 0.25, "berry_red", "Sleeves")
	box(m, g, 0, 1.0, 0, 0.5, 0.75, 0.5, "berry_red", "Shirt")
	box(m, g, 0.12, 0.9, on(0.25), 0.25, 0.25, 0.25, "yellow", "Patch")
	box(m, g, -0.28, 1.45, on(0.125), 0.25, 0.25, 0.25, "blue", "Patch")
	box(m, g, -0.08, 1.15, on(0.25), 0.25, 0.25, 0.25, "cream", "Button")
	box(m, g, 0, 0.68, on(0.25), 0.5, 0.25, 0.25, "sand_dark", "Belt")
	for _, x in { -0.125, 0.125 } do
		box(m, g, x, 0.45, 0, 0.25, 0.5, 0.25, "jeans", "Leg")
		box(m, g, x, 0.2, 0.02, 0.25, 0.25, 0.25, "straw", "Straw")
	end
	for _, x in { -0.44, 0.44 } do
		box(m, g, x, 1.4, 0.02, 0.25, 0.25, 0.25, "straw", "Hand")
	end
	box(m, g, 0, 1.47, 0.06, 0.5, 0.25, 0.5, "orange", "Scarf")
	box(m, g, 0.12, 1.28, on(0.25) + 0.06, 0.25, 0.25, 0.25, "orange", "Scarf")
	ball(m, g, 0, 1.8, 0, 0.5, "cream", "Head")
	for _, x in { -0.14, 0.14 } do
		box(m, g, x, 1.88, 0.16, 0.25, 0.25, 0.25, "wood_dark", "Stitch")
	end
	box(m, g, 0, 1.68, 0.18, 0.25, 0.25, 0.25, "wood_dark", "Stitch")
	cyl(m, g, 0, 2.05, 0, 0.75, 0.25, "straw", "Brim")
	cyl(m, g, 0, 2.2, 0, 0.5, 0.25, "berry_red", "Band")
	cyl(m, g, 0, 2.42, 0, 0.5, 0.25, "straw", "Crown")
	box(m, g, 0.2, 2.22, 0.12, 0.25, 0.25, 0.25, "pink", "Bloom")
	-- the crow on the left arm, looking out and bobbing
	local h = CFrame.Angles(0, PI / 4, 0) * V(-0.36, 1.77, 0)
	for _, p in {
		box(m, g, -0.36, 1.77, 0, 0.25, 0.25, 0.25, "black", "Crow"),
		ball(m, g, -0.44, 1.93, 0, 0.25, "black", "Crow"),
	} do
		move(p, "bob", h, "Y", 1.6, 0.05)
	end
end

-- A barrel lying along Z at (x, y, z), 1.25 long: staves bulging to the middle with two dark hoops, its front end a
-- dark rim round a paler lid with a clay bung, a brass tap when asked.
local function lyingBarrel(m: Instance, f: CFrame, x: number, y: number, z: number, tap: boolean?)
	for k = 1, 5 do
		local hoop = k == 2 or k == 4
		Parts.logZ(m, f, x, y, z - 0.75 + k * 0.25, 0.25, if k == 1 or k == 5 then 0.75 else 1.0, if hoop then "steel_dark" else "wood", "Barrel")
	end
	Parts.logZ(m, f, x, y, z + 0.6, 0.25, 0.75, "wood_dark", "Rim")
	Parts.logZ(m, f, x, y, z + 0.64, 0.25, 0.5, "wood", "Lid")
	Parts.logZ(m, f, x, y + 0.12, z + 0.68, 0.25, 0.25, "clay", "Bung")
	if tap then
		box(m, f, x, y - 0.15, z + 0.78, 0.25, 0.25, 0.25, "gold", "Tap")
	end
end

-- Barrel Stack (2 x 2): two barrels lying side by side on a pair of beams and a third on top of them stamped in red, a
-- brass tap on one with a tin cup under it, an orange cat asleep on the top barrel, sawdust on the ground.
M.barrels = function(m, f)
	for _, z in { -0.4, 0.4 } do
		box(m, f, 0, 0.125, z, 2.0, 0.25, 0.25, "wood_dark", "Beam")
	end
	lyingBarrel(m, f, -0.5, 0.75, -0.05, false)
	lyingBarrel(m, f, 0.5, 0.75, -0.05, true)
	lyingBarrel(m, f, 0, 1.62, -0.15, false)
	box(m, f, 0.44, 1.78, -0.15, 0.25, 0.25, 0.25, "berry_red", "Stamp")
	cyl(m, f, 0.5, 0.125, 0.85, 0.25, 0.25, "steel", "Cup")
	-- the cat, curled up
	ball(m, f, -0.05, 2.25, -0.25, 0.5, "orange", "Cat")
	ball(m, f, 0.2, 2.25, -0.02, 0.25, "orange", "Cat")
	box(m, f, 0.2, 2.42, -0.02, 0.25, 0.25, 0.25, "orange", "Ear")
	box(m, f, -0.1, 2.12, 0.06, 0.5, 0.25, 0.25, "cream", "Tail")
	for _, s in { { -0.7, 0.75 }, { 0.15, 0.75 } } do
		put(m, f, CFrame.new(s[1], 0.02, s[2]) * CFrame.Angles(0, 0.4, 0), 0.5, 0.25, 0.25, "sand", nil, "Sawdust")
	end
end

-- Haystack (2 x 2): a round stack of straw in layers of two shades, narrowing to a knot tied with twine, a sparrow on
-- the knot; wisps sticking out, a pitchfork leaning on it, a sack of feed tied at the neck, a pail, an orange cat
-- asleep at its foot and loose straw on the ground.
M.haystack = function(m, f)
	cyl(m, f, -0.05, 0.25, -0.05, 1.75, 0.5, "straw", "Hay")
	ball(m, f, -0.05, 0.65, -0.05, 1.75, "straw", "Hay")
	ball(m, f, -0.05, 1.3, -0.05, 1.25, "yellow", "Hay")
	ball(m, f, -0.05, 1.72, -0.05, 0.75, "straw", "Hay")
	ball(m, f, -0.05, 2.08, -0.05, 0.5, "sand_dark", "Knot")
	cyl(m, f, -0.05, 1.95, -0.05, 0.5, 0.25, "wood_dark", "Twine")
	ball(m, f, 0.1, 2.3, -0.05, 0.25, "wood_dark", "Sparrow")
	ball(m, f, 0.22, 2.42, -0.02, 0.25, "wood", "Sparrow")
	box(m, f, -0.02, 2.36, -0.08, 0.25, 0.25, 0.25, "wood_dark", "Tail")
	for _, t in { { 0.45, 1.0, 0.45, 0.6 }, { -0.55, 1.05, 0.4, -0.5 }, { 0.6, 0.45, -0.3, 1.2 }, { 0.2, 1.65, 0.3, 0.2 }, { -0.4, 0.5, 0.55, -1.0 }, { -0.6, 1.4, -0.2, 0.9 }, { 0.5, 1.45, -0.1, -0.7 } } do
		put(m, f, CFrame.new(t[1], t[2], t[3]) * CFrame.Angles(0, t[4], math.rad(30)), 0.5, 0.25, 0.25, "yellow", nil, "Wisp")
	end
	-- the pitchfork, tines up, leaning on the front
	local foot, head = V(0.85, 0, 0.75), V(0.55, 1.6, 0.45)
	strut(m, f, foot, head, 0.25, "wood", "Handle")
	local up = (head - foot).Unit
	local across = V(1, 0, 1).Unit
	across = (across - up * across:Dot(up)).Unit
	local cf = CFrame.fromMatrix(head, across, up)
	put(m, f, cf * CFrame.new(0, 0.125, 0), 0.75, 0.25, 0.25, "steel_dark", nil, "Fork")
	for _, s in { -1, 1 } do
		put(m, f, cf * CFrame.new(s * 0.25, 0.5, 0), 0.25, 0.5, 0.25, "steel", nil, "Tine")
	end
	-- the rake in front, the sack and the pail, the cat
	ball(m, f, 0.72, 0.25, -0.72, 0.5, "sand_dark", "Sack")
	box(m, f, 0.72, 0.52, -0.72, 0.25, 0.25, 0.25, "wood_dark", "Tie")
	cyl(m, f, -0.72, 0.125, -0.72, 0.5, 0.25, "wood", "Pail")
	cyl(m, f, -0.72, 0.375, -0.72, 0.5, 0.25, "steel_dark", "Pail")
	ball(m, f, -0.68, 0.2, 0.62, 0.5, "orange", "Cat")
	ball(m, f, -0.45, 0.25, 0.75, 0.25, "orange", "Cat")
	box(m, f, -0.45, 0.42, 0.75, 0.25, 0.25, 0.25, "orange", "Ear")
	box(m, f, -0.72, 0.1, 0.86, 0.5, 0.25, 0.25, "cream", "Tail")
	for _, s in { { 0.6, 0.72, 0.8 }, { 0.15, 0.82, 0 } } do
		put(m, f, CFrame.new(s[1], 0.02, s[2]) * CFrame.Angles(0, s[3], 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
	end
end

-- Water Trough (2 x 1): a trough of planks in two shades on dark blocks, two iron bands across its front, its ends
-- capped, water to the brim with a leaf afloat; an iron hand pump at its east end with its spout over the water and a
-- tin cup hung on it, a puddle at its foot, a sparrow on the rim and a frog by the pump.
M.trough = function(m, f)
	for _, x in { -0.75, 0.25 } do
		box(m, f, x, 0.125, 0, 0.25, 0.25, 0.75, "wood_dark", "Block")
	end
	box(m, f, -0.75, 0.2, 0.2, 0.25, 0.25, 0.25, "moss", "Moss")
	box(m, f, -0.25, 0.375, 0, 1.5, 0.25, 0.75, "wood", "Bottom")
	for _, z in { -0.33, 0.33 } do
		box(m, f, -0.25, 0.625, z, 1.5, 0.25, 0.25, "wood", "Side")
		box(m, f, -0.25, 0.875, z, 1.5, 0.25, 0.25, "wood_dark", "Side")
	end
	for _, x in { -0.875, 0.375 } do
		box(m, f, x, 0.75, 0, 0.25, 0.5, 0.5, "wood_dark", "End")
	end
	Parts.water(m, f, -0.25, 0.86, 0, 1.0, 0.5)
	box(m, f, -0.55, 0.98, -0.05, 0.25, 0.25, 0.25, "leaf_dark", "Leaf")
	for _, x in { -0.6, 0.1 } do
		box(m, f, x, 0.75, on(0.455), 0.25, 0.5, 0.25, "steel_dark", "Band")
	end
	-- the pump
	box(m, f, 0.75, 0.125, 0, 0.5, 0.25, 0.5, "rock", "PumpBase")
	box(m, f, 0.75, 0.75, 0, 0.25, 1.0, 0.25, "steel_dark", "Pump")
	cyl(m, f, 0.75, 1.3, 0, 0.5, 0.25, "steel_dark", "PumpCap")
	box(m, f, 0.55, 1.05, 0, 0.5, 0.25, 0.25, "steel_dark", "Spout")
	strut(m, f, V(0.75, 1.4, 0), V(0.75, 1.65, 0.3), 0.25, "steel", "PumpHandle")
	cyl(m, f, 0.87, 0.9, 0.0, 0.25, 0.25, "steel", "Cup")
	Parts.water(m, f, 0.6, 0.02, 0.37, 0.5, 0.25, "shallow", "Puddle")
	-- the sparrow on the front rim, the frog by the pump
	ball(m, f, -0.6, 1.12, 0.33, 0.25, "wood_dark", "Sparrow")
	ball(m, f, -0.45, 1.25, 0.33, 0.25, "wood", "Sparrow")
	box(m, f, -0.75, 1.17, 0.33, 0.25, 0.25, 0.25, "wood_dark", "Tail")
	ball(m, f, 0.86, 0.12, -0.35, 0.25, "green", "Frog")
	box(m, f, 0.86, 0.3, -0.3, 0.25, 0.25, 0.25, "green", "Frog")
end

-- A cart wheel turning about Z at (x, y, z): an iron tyre round the felloe, four crossing spokes on its outer face
-- (+Z when side is 1), a dark hub with a brass cap.
local function wheel(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, side: number)
	Parts.logZ(m, f, x, y, z, 0.25, dia, "steel_dark", "Tyre")
	Parts.logZ(m, f, x, y, z + side * 0.03, 0.25, dia - 0.25, "wood_dark", "Wheel")
	for k = 0, 3 do
		put(m, f, CFrame.new(x, y, z + side * 0.06) * CFrame.Angles(0, 0, k * PI / 4), dia - 0.5, 0.25, 0.25, "wood", nil, "Spoke")
	end
	Parts.logZ(m, f, x, y, z + side * 0.1, 0.25, 0.5, "steel_dark", "Hub")
	Parts.logZ(m, f, x, y, z + side * 0.13, 0.25, 0.25, "gold", "HubCap")
end

-- Farm Cart (3 x 2): a plank bed with sides of two boards held by iron straps and stakes, on two big iron-tyred wheels,
-- shafts resting on the ground (+X), a prop at the back, a lantern hung on a stake, and a load of veg: cabbages, a
-- pumpkin, carrots with their tops, turnips, a crate of apples, a sack of potatoes.
M.cart = function(m, f)
	wheel(m, f, -0.25, 0.625, 0.74, 1.25, 1)
	wheel(m, f, -0.25, 0.625, -0.74, 1.25, -1)
	Parts.logZ(m, f, -0.25, 0.625, 0, 1.25, 0.25, "wood_dark", "Axle")
	box(m, f, -0.25, 1.0, 0, 2.25, 0.25, 1.25, "wood", "Bed")
	for _, z in { -0.5, 0.5 } do
		box(m, f, -0.25, 1.25, z, 2.25, 0.25, 0.25, "wood", "Side")
		box(m, f, -0.25, 1.5, z, 2.25, 0.25, 0.25, "wood_dark", "Side")
	end
	for _, x in { -1.25, 0.75 } do
		box(m, f, x, 1.375, 0, 0.25, 0.5, 0.75, "wood", "End")
		box(m, f, x, 1.4, 0.55, 0.25, 0.75, 0.25, "wood_dark", "Stake")
	end
	for _, x in { -0.75, 0.25 } do
		box(m, f, x, 1.375, on(0.625), 0.25, 0.5, 0.25, "steel_dark", "Strap")
	end
	box(m, f, -1.25, 0.45, 0, 0.25, 0.9, 0.25, "wood_dark", "Prop")
	for _, z in { -0.375, 0.375 } do
		strut(m, f, V(0.75, 0.95, z), V(1.4, 0.15, z), 0.25, "wood_dark", "Shaft")
	end
	box(m, f, 1.3, 0.25, 0, 0.25, 0.25, 1.0, "wood_dark", "Bar")
	lamp(m, f, 0.75, 1.6, 0.72)
	-- the load
	ball(m, f, -0.85, 1.4, -0.1, 0.5, "green", "Cabbage")
	ball(m, f, -0.45, 1.45, 0.12, 0.5, "moss", "Cabbage")
	ball(m, f, -0.75, 1.75, 0.0, 0.5, "green", "Cabbage")
	ball(m, f, 0.05, 1.45, -0.1, 0.5, "orange", "Pumpkin")
	box(m, f, 0.05, 1.75, -0.1, 0.25, 0.25, 0.25, "wood_dark", "Stem")
	for k = 0, 2 do
		put(m, f, CFrame.new(-0.25 + k * 0.12, 1.62, 0.2 - k * 0.08) * CFrame.Angles(0, 0.3 + k * 0.2, 0), 0.5, 0.25, 0.25, "orange", nil, "Carrot")
	end
	box(m, f, -0.05, 1.7, 0.2, 0.25, 0.25, 0.25, "leaf", "Tops")
	box(m, f, 0.02, 1.8, 0.1, 0.25, 0.25, 0.25, "leaf_dark", "Tops")
	ball(m, f, -0.4, 1.7, -0.2, 0.25, "purple", "Turnip")
	ball(m, f, -0.25, 1.62, -0.25, 0.25, "white", "Turnip")
	box(m, f, 0.45, 1.375, 0, 0.5, 0.5, 0.5, "wood_dark", "Crate")
	box(m, f, 0.45, 1.375, on(0.25), 0.25, 0.25, 0.25, "wood", "Slat")
	for _, a in { { 0.35, -0.1 }, { 0.55, 0.1 }, { 0.5, -0.12 } } do
		ball(m, f, a[1], 1.7, a[2], 0.25, "berry_red", "Apple")
	end
	box(m, f, -0.95, 1.4, 0.1, 0.5, 0.5, 0.5, "sand_dark", "Sack")
	box(m, f, -0.95, 1.7, 0.1, 0.25, 0.25, 0.25, "wood_dark", "Tie")
end

-- Stone Well (2 x 2): a round wall of stones in two courses, a ring of pale capstones round the dark shaft, moss on the
-- wall; two posts braced to a thatched roof with a fringe and a ridge, a windlass with a crank, and a bucket hanging on
-- its rope that sways a little (it moves). A full bucket and flowers at its foot.
M.well = function(m, f)
	cyl(m, f, 0, 0.375, 0, 1.75, 0.75, "rock", "Wall")
	for k, s in { { 0.3, 0.25 }, { 1.1, 0.5 }, { 1.7, 0.25 }, { 0.75, 0.6 }, { 1.4, 0.15 }, { -0.2, 0.55 }, { 0.5, 0.05 }, { 1.95, 0.6 } } do
		local a = s[1]
		put(m, f, CFrame.new(math.cos(a) * 0.82, s[2] + 0.12, math.sin(a) * 0.82) * CFrame.Angles(0, -a, 0), 0.25, 0.25, 0.5, if k % 3 == 0 then "pavement" else "rock_dark", nil, "Stone")
	end
	for k = 0, 7 do
		local a = k * PI / 4
		put(m, f, CFrame.new(math.cos(a) * 0.75, 0.875, math.sin(a) * 0.75) * CFrame.Angles(0, -a, 0), 0.5, 0.25, 0.5, if k % 2 == 0 then "pavement" else "rock", nil, "Capstone")
	end
	cyl(m, f, 0, 0.8, 0, 1.0, 0.25, "night", "Shaft")
	box(m, f, 0.62, 0.6, 0.48, 0.25, 0.25, 0.25, "moss", "Moss")
	box(m, f, -0.3, 0.98, 0.7, 0.25, 0.25, 0.25, "moss", "Moss")
	for _, z in { -0.625, 0.625 } do
		box(m, f, 0, 1.125, z, 0.25, 2.25, 0.25, "wood_dark", "Post")
		strut(m, f, V(0, 2.0, z), V(0, 2.35, z * 0.55), 0.25, "wood", "Brace")
	end
	-- the windlass across the shaft, the rope wound in the middle, a crank at the front
	for k, c in { "wood", "sand_dark", "wood" } do
		Parts.logZ(m, f, 0, 1.85, -0.5 + (k - 1) * 0.5, 0.5, 0.5, c, "Windlass")
	end
	box(m, f, 0, 1.7, 0.875, 0.25, 0.5, 0.25, "wood_dark", "Crank")
	box(m, f, 0.15, 1.5, 0.875, 0.25, 0.25, 0.25, "wood", "Handle")
	-- the bucket on its rope, swaying side to side under the windlass
	local hub = V(0, 1.85, 0)
	move(box(m, f, 0, 1.7, 0, 0.25, 0.25, 0.25, "sand_dark", "Rope"), "swing", hub, "Z", 1.3, 0.12)
	move(box(m, f, 0, 1.5, 0, 0.5, 0.25, 0.25, "steel_dark", "Bail"), "swing", hub, "Z", 1.3, 0.12)
	move(cyl(m, f, 0, 1.31, 0, 0.5, 0.25, "wood", "Bucket"), "swing", hub, "Z", 1.3, 0.12)
	move(cyl(m, f, 0, 1.06, 0, 0.5, 0.25, "steel_dark", "Bucket"), "swing", hub, "Z", 1.3, 0.12)
	-- a steep thatched roof, its gable to the front, a fringe along each eave
	Parts.wedge(m, f, -0.375, 2.625, 0, 1.75, 0.75, 0.75, "straw", PI / 2, "Roof")
	Parts.wedge(m, f, 0.375, 2.625, 0, 1.75, 0.75, 0.75, "straw", -PI / 2, "Roof")
	for _, s in { -1, 1 } do
		put(m, f, CFrame.new(s * 0.47, 2.6, 0) * CFrame.Angles(0, 0, -s * PI / 4), 0.25, 0.25, 1.75, "sand_dark", nil, "Thatch")
		box(m, f, s * 0.8, 2.22, 0, 0.25, 0.25, 1.75, "sand_dark", "Fringe")
	end
	box(m, f, 0, 3.0, 0, 0.25, 0.25, 1.75, "wood_dark", "Ridge")
	-- a full bucket by the wall, flowers
	cyl(m, f, 0.72, 0.125, 0.72, 0.5, 0.25, "wood", "Pail")
	cyl(m, f, 0.72, 0.375, 0.72, 0.5, 0.25, "steel_dark", "Pail")
	pool(m, f, 0.72, 0.42, 0.72, 0.25, "water")
	tuft(m, f, -0.75, 0, 0.75, "pink")
	tuft(m, f, 0.74, 0, -0.74, "yellow")
end

------------------------------------------------------------------ the harbour

-- Mooring Post (1 x 1): a stout dark post on four planks of the quay with two nail heads, an iron band and an iron cap
-- with a rounded top; rope wound round it twice and running off to a coil on the boards, an iron cleat behind; a gull
-- standing on the cap (it bobs) and a little crab by the post.
M.bollard = function(m, f)
	for k = 0, 3 do
		box(m, f, -0.375 + k * 0.25, 0, 0, 0.25, 0.25, 1.0, if k % 2 == 0 then "wood" else "sand_dark", "Plank")
	end
	for _, n in { { -0.375, 0.36 }, { 0.125, -0.36 } } do
		box(m, f, n[1], 0.06, n[2], 0.25, 0.25, 0.25, "steel_dark", "Nail")
	end
	cyl(m, f, 0, 0.625, -0.05, 0.5, 1.0, "wood_dark", "Post")
	cyl(m, f, 0, 1.0, -0.05, 0.75, 0.25, "steel_dark", "Band")
	cyl(m, f, 0, 1.25, -0.05, 0.75, 0.25, "slate", "Cap")
	ball(m, f, 0, 1.4, -0.05, 0.5, "slate", "Cap")
	cyl(m, f, 0, 0.5, -0.05, 0.75, 0.25, "sand_dark", "Rope")
	cyl(m, f, 0, 0.75, -0.05, 0.75, 0.25, "straw", "Rope")
	strut(m, f, V(0.25, 0.45, 0.15), V(0.25, 0.2, 0.3), 0.25, "sand_dark", "Rope")
	cyl(m, f, 0.22, 0.18, 0.25, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, f, 0.22, 0.25, 0.25, 0.25, 0.25, "straw", "Coil")
	box(m, f, -0.25, 0.2, -0.38, 0.5, 0.25, 0.25, "steel_dark", "Cleat")
	-- the crab
	ball(m, f, -0.28, 0.2, 0.25, 0.25, "coral", "Crab")
	ball(m, f, -0.36, 0.2, 0.36, 0.25, "berry_red", "Claw")
	ball(m, f, -0.16, 0.2, 0.36, 0.25, "berry_red", "Claw")
	-- the gull on the cap, facing +X, bobbing
	local hub = V(0, 1.9, -0.05)
	for _, p in {
		box(m, f, 0, 1.8, -0.05, 0.25, 0.25, 0.25, "orange", "Legs"),
		box(m, f, -0.02, 1.96, -0.05, 0.5, 0.25, 0.25, "white", "Gull"),
		ball(m, f, 0.2, 2.13, -0.05, 0.25, "white", "Gull"),
		box(m, f, 0.35, 2.1, -0.05, 0.25, 0.25, 0.25, "yellow", "Beak"),
		box(m, f, -0.05, 2.0, 0.05, 0.25, 0.25, 0.25, "steel", "Wing"),
		box(m, f, -0.3, 2.01, -0.05, 0.25, 0.25, 0.25, "black", "Tail"),
	} do
		move(p, "bob", hub, "Y", 1.5, 0.04)
	end
end

-- Buoy (1 x 1): a red and white float riding a little round pool (it bobs): three bands with a dark number on the
-- white, steel bars round a lit lamp and a brass bell, a red cap and a white knob; rocks in the corners round the
-- water, weed and moss on two, a pink shell and a starfish on the others.
M.buoy = function(m, f)
	pool(m, f, 0, 0.06, 0, 1.0, "water")
	for k, c in { { 0.37, 0.37 }, { -0.37, 0.37 }, { 0.37, -0.37 }, { -0.37, -0.37 } } do
		ball(m, f, c[1], 0.1, c[2], 0.25, if k % 2 == 0 then "rock" else "rock_dark", "Rock")
	end
	box(m, f, 0.37, 0.25, -0.37, 0.25, 0.25, 0.25, "leaf_dark", "Weed")
	ball(m, f, 0.37, 0.38, -0.34, 0.25, "leaf", "Weed")
	box(m, f, -0.37, 0.22, -0.37, 0.25, 0.25, 0.25, "moss", "Moss")
	cyl(m, f, -0.37, 0.24, 0.37, 0.25, 0.25, "pink", "Shell")
	ball(m, f, 0.37, 0.26, 0.37, 0.25, "coral", "Starfish")
	-- the float, riding the water
	local hub = V(0, 0.4, 0)
	local parts = {
		cyl(m, f, 0, 0.25, 0, 0.5, 0.25, "berry_red", "Buoy"),
		cyl(m, f, 0, 0.5, 0, 0.5, 0.25, "white", "Buoy"),
		cyl(m, f, 0, 0.75, 0, 0.5, 0.25, "berry_red", "Buoy"),
		box(m, f, 0.12, 0.5, 0.12, 0.25, 0.25, 0.25, "black", "Number"),
		box(m, f, -0.125, 1.1, -0.125, 0.25, 0.5, 0.25, "steel", "Cage"),
		box(m, f, 0.125, 1.1, 0.125, 0.25, 0.5, 0.25, "steel", "Cage"),
		Parts.glow(m, f, 0, 1.12, 0, 0.25, 0.25, 0.25, "yellow", "Lamp"),
		ball(m, f, 0.12, 0.98, -0.12, 0.25, "gold", "Bell"),
		box(m, f, 0, 1.4, 0, 0.5, 0.25, 0.5, "berry_red", "Cap"),
		ball(m, f, 0, 1.58, 0, 0.25, "white", "Knob"),
	}
	for _, p in parts do
		move(p, "bob", hub, "X", 1.4, 0.08)
	end
end

-- A crate s on a side standing at (x, y0, z), turned yaw: a dark frame round pale boards on the faces that show, a
-- dark seam across a big crate's boards, a stamp on its front, a brace across its right side when asked.
local function crate(m: Instance, f: CFrame, x: number, y0: number, z: number, s: number, yaw: number, stamp: string?, brace: boolean?)
	local c = CFrame.new(x, y0 + s / 2, z) * CFrame.Angles(0, yaw, 0)
	local p = s - 0.25
	put(m, f, c, s, s, s, "wood_dark", nil, "Crate")
	put(m, f, c * CFrame.new(0, 0, s / 2 - 0.1), p, p, 0.25, "sand_dark", nil, "Board")
	put(m, f, c * CFrame.new(s / 2 - 0.1, 0, 0), 0.25, p, p, "sand_dark", nil, "Board")
	put(m, f, c * CFrame.new(0, s / 2 - 0.1, 0), p, 0.25, p, "sand_dark", nil, "Board")
	if s >= 0.75 then
		put(m, f, c * CFrame.new(0, 0, s / 2 - 0.07), p, 0.25, 0.25, "wood", nil, "Seam")
		put(m, f, c * CFrame.new(0, s / 2 - 0.07, 0), 0.25, 0.25, p, "wood", nil, "Seam")
	end
	if stamp then
		put(m, f, c * CFrame.new(s / 4, s / 4, s / 2 - 0.04), 0.25, 0.25, 0.25, stamp, nil, "Stamp")
	end
	if brace then
		put(m, f, c * CFrame.new(s / 2 - 0.06, 0, 0) * CFrame.Angles(PI / 4, 0, 0), 0.25, p * math.sqrt(2), 0.25, "wood_dark", nil, "Brace")
	end
end

-- Crate Stack (2 x 2): a big crate with a smaller one on top of it and a lantern on that, another beside, a little one
-- in front, stamped red and blue and nailed shut; an open box of fish on ice and a crowbar leaning on the big crate.
M.crates = function(m, f)
	crate(m, f, -0.45, 0, -0.4, 1.0, 0, "berry_red", true)
	crate(m, f, 0.5, 0, -0.5, 0.75, 0, "blue", true)
	crate(m, f, -0.42, 1.0, -0.45, 0.75, 0.25, "blue")
	crate(m, f, 0.45, 0, 0.5, 0.5, -0.3)
	lamp(m, f, -0.42, 2.0, -0.45, true)
	-- the box of fish
	box(m, f, -0.45, 0.125, 0.6, 0.75, 0.25, 0.5, "wood_dark", "FishBox")
	box(m, f, -0.45, 0.2, 0.6, 0.5, 0.25, 0.25, "white", "Ice")
	for k, x in { -0.65, -0.45, -0.25 } do
		put(m, f, CFrame.new(x, 0.3, 0.6) * CFrame.Angles(0, 0.3 * (k - 2), 0), 0.25, 0.25, 0.5, if k == 2 then "blue" else "steel", nil, "Fish")
	end
	strut(m, f, V(-0.05, 0.02, 0.24), V(-0.12, 0.8, 0.16), 0.25, "steel_dark", "Crowbar")
end

-- A lobster pot standing on y0 at (x, z): a round wicker pot on a dark base ring, a band of straw and a narrower top
-- round the dark mouth, a rope handle over it.
local function creel(m: Instance, f: CFrame, x: number, y0: number, z: number)
	local y = stack(m, f, x, y0, z, { { d = 0.75, h = 0.25, c = "wood_dark" }, { d = 0.75, h = 0.25, c = "straw" }, { d = 0.5, h = 0.25, c = "wood" } }, "Pot")
	cyl(m, f, x, y - 0.1, z, 0.25, 0.25, "black", "Mouth")
	box(m, f, x, y + 0.04, z, 0.5, 0.25, 0.25, "sand_dark", "Handle")
end

-- Lobster Pots (2 x 2): three wicker pots in a pile and a fourth on its side with its mouth to the view, a red lobster
-- sitting on it, red and white floats on a rope, a coil of rope and a tin bucket of bait with a fish's tail in it.
M.lobsterpots = function(m, f)
	creel(m, f, -0.5, 0, 0.3)
	creel(m, f, 0.35, 0, -0.5)
	creel(m, f, -0.1, 0.6, -0.12)
	-- the one on its side
	for _, c in { { 0.3, 0.75, "wood_dark" }, { 0.55, 0.75, "straw" }, { 0.8, 0.5, "wood" } } :: { { any } } do
		Parts.log(m, f, c[1], 0.375, 0.45, 0.25, c[2], c[3], "Pot")
	end
	Parts.log(m, f, 0.86, 0.375, 0.45, 0.25, 0.25, "black", "Mouth")
	-- the lobster on it, facing +X
	box(m, f, 0.5, 0.85, 0.45, 0.5, 0.25, 0.25, "berry_red", "Lobster")
	box(m, f, 0.2, 0.82, 0.45, 0.25, 0.25, 0.25, "berry_red", "Tail")
	ball(m, f, 0.82, 0.88, 0.32, 0.25, "berry_red", "Claw")
	ball(m, f, 0.82, 0.88, 0.58, 0.25, "berry_red", "Claw")
	box(m, f, 0.7, 1.0, 0.45, 0.25, 0.25, 0.25, "black", "Eyes")
	-- the floats on their rope, the coil, the bucket
	stack(m, f, -0.55, 0, -0.6, { { d = 0.5, h = 0.25, c = "berry_red" }, { d = 0.5, h = 0.25, c = "white" } }, "Float")
	ball(m, f, -0.82, 0.15, -0.2, 0.25, "orange", "Float")
	strut(m, f, V(-0.5, 0.35, -0.4), V(-0.5, 0.2, 0.0), 0.25, "sand_dark", "Rope")
	cyl(m, f, -0.72, 0.06, 0.74, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, f, -0.72, 0.12, 0.74, 0.25, 0.25, "straw", "Coil")
	cyl(m, f, 0.75, 0.25, -0.72, 0.5, 0.5, "steel", "Bucket")
	box(m, f, 0.75, 0.55, -0.72, 0.25, 0.25, 0.25, "steel_dark", "FishTail")
end

-- A net hung in a bay from x0 to x1: three cords down, three across, the bottom one sagging, cork floats along the top.
local function net(m: Instance, f: CFrame, x0: number, x1: number, z: number, color: string)
	local mid = (x0 + x1) / 2
	local half = (x1 - x0) / 2
	for k = -1, 1 do
		local len = if k == 0 then 1.5 else 1.25
		box(m, f, mid + k * half, 1.875 - len / 2, z, 0.25, len, 0.25, color, "Net")
	end
	box(m, f, mid, 1.75, z, x1 - x0 + 0.25, 0.25, 0.25, color, "Net")
	box(m, f, mid, 1.25, z, x1 - x0, 0.25, 0.25, color, "Net")
	for _, s in { -1, 1 } do
		strut(m, f, V(mid + s * half, 0.72, z), V(mid, 0.5, z), 0.25, color, "Net")
	end
	for _, s in { -0.25, 0.25 } do
		ball(m, f, mid + s * half * 2, 1.75, z + 0.1, 0.25, "orange", "Cork")
	end
end

-- Net Rack (3 x 1): three weathered posts on long feet, the outer ones braced, and a rail; a rope-brown net and a teal
-- one hung out to dry with cork floats along their tops; a glass float and a cork hung on a peg in front of each net,
-- swaying on their line (they move); a basket of fish and a coil of rope.
M.netrack = function(m, f)
	for _, x in { -1.375, 0, 1.375 } do
		box(m, f, x, 1.0, -0.32, 0.25, 2.0, 0.25, "wood_dark", "Post")
		box(m, f, x, 0.125, -0.12, 0.25, 0.25, 0.75, "wood_dark", "Foot")
		if x ~= 0 then
			strut(m, f, V(x, 0.15, 0.15), V(x, 0.9, -0.3), 0.25, "wood", "Brace")
		end
	end
	box(m, f, 0, 2.0, -0.32, 3.0, 0.25, 0.25, "wood", "Rail")
	net(m, f, -1.2, -0.2, -0.13, "sand_dark")
	net(m, f, 0.2, 1.2, -0.13, "teal")
	-- the glass floats on their pegs, swaying side to side
	for k, x in { -0.7, 0.7 } do
		box(m, f, x, 1.95, -0.03, 0.25, 0.25, 0.75, "wood_dark", "Peg")
		local hub = V(x, 1.9, 0.25)
		local phase = (k - 1) * 2.4
		move(box(m, f, x, 1.6, 0.25, 0.25, 0.5, 0.25, "sand_dark", "Line"), "swing", hub, "Z", 1.6, 0.15, phase)
		move(ball(m, f, x, 1.15, 0.25, 0.5, if k == 1 then "teal" else "blue", "Glass"), "swing", hub, "Z", 1.6, 0.15, phase)
		move(ball(m, f, x, 0.82, 0.25, 0.25, "orange", "Cork"), "swing", hub, "Z", 1.6, 0.15, phase)
	end
	-- a basket of fish and a coil of rope
	cyl(m, f, -1.15, 0.25, 0.22, 0.5, 0.5, "straw", "Basket")
	cyl(m, f, -1.15, 0.4, 0.22, 0.5, 0.25, "wood", "Basket")
	box(m, f, -1.15, 0.6, 0.22, 0.25, 0.25, 0.25, "steel", "Fish")
	cyl(m, f, 1.15, 0.06, 0.22, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, f, 1.15, 0.12, 0.22, 0.25, 0.25, "straw", "Coil")
end

-- Anchor (2 x 1): an old slate-iron anchor stood on its crown in a bed of stones, turned a little toward the view: the
-- shank, a wooden stock across it with iron bands at its ends, the eye at the top, the arms curving up to their flukes,
-- rust, moss and white barnacles here and there; a chain from the eye down to a heap of links on the ground.
M.anchor = function(m, f)
	box(m, f, 0, 0.06, 0, 1.25, 0.25, 0.75, "rock", "Bed")
	ball(m, f, -0.55, 0.15, 0.22, 0.5, "rock_dark", "Stone")
	ball(m, f, 0.4, 0.12, -0.25, 0.5, "rock_dark", "Stone")
	ball(m, f, -0.75, 0.06, -0.3, 0.25, "pavement", "Pebble")
	ball(m, f, 0.7, 0.06, 0.32, 0.25, "rock", "Pebble")
	local g = f * CFrame.Angles(0, math.rad(20), 0)
	box(m, g, 0, 1.1, 0, 0.5, 1.5, 0.25, "slate", "Shank")
	-- the arms: an arc from one side down round the crown and up the other
	local cy, r = 0.95, 0.7
	for k = 0, 5 do
		local a = math.rad(-155 + k * 26)
		put(m, g, CFrame.new(math.cos(a) * r, cy + math.sin(a) * r, 0) * CFrame.Angles(0, 0, a + PI / 2), 0.5, 0.25, 0.25, "slate", nil, "Arm")
	end
	for _, s in { -1, 1 } do
		local a = math.rad(if s < 0 then -155 else -25)
		put(m, g, CFrame.new(math.cos(a) * r, cy + math.sin(a) * r + 0.12, 0) * CFrame.Angles(0, 0, PI / 4), 0.5, 0.5, 0.25, "slate", nil, "Fluke")
	end
	box(m, g, 0, 1.55, 0, 1.25, 0.25, 0.25, "wood_dark", "Stock")
	for _, x in { -0.5, 0.5 } do
		box(m, g, x, 1.55, 0.03, 0.25, 0.25, 0.25, "steel_dark", "StockBand")
	end
	ring(m, g, CFrame.new(0, 2.0, 0), "slate", "slate", "Eye")
	box(m, g, 0.12, 0.9, 0.06, 0.25, 0.25, 0.25, "clay", "Rust")
	box(m, g, -0.45, 0.42, 0.06, 0.25, 0.25, 0.25, "clay", "Rust")
	box(m, g, 0.05, 0.3, 0.06, 0.25, 0.25, 0.25, "moss", "Moss")
	box(m, g, -0.08, 1.35, 0.08, 0.25, 0.25, 0.25, "white", "Barnacle")
	box(m, g, 0.55, 0.55, 0.08, 0.25, 0.25, 0.25, "white", "Barnacle")
	-- the chain from the eye down in front of the right arm to its heap
	local a0, a1 = V(0.22, 1.88, 0.14), V(0.75, 0.2, 0.2)
	for k = 0, 4 do
		local t0, t1 = k / 5, (k + 1) / 5
		local p0 = a0:Lerp(a1, t0) + V(0.12 * math.sin(t0 * PI), 0, 0)
		local p1 = a0:Lerp(a1, t1) + V(0.12 * math.sin(t1 * PI), 0, 0)
		strut(m, g, p0, p1, 0.25, if k % 2 == 0 then "steel_dark" else "slate", "Chain")
	end
	cyl(m, g, 0.68, 0.12, 0.15, 0.5, 0.25, "steel_dark", "Links")
	ball(m, g, 0.6, 0.2, 0.2, 0.25, "slate", "Links")
end

-- Ship's Wheel (1 x 1): an old helm on a square of deck planks: a turned post with dark collars and a brass cap, its
-- axle and the wheel on it, facing the front: a rim of eight pieces, four spokes crossing it to their handles and a
-- brass hub. The wheel turns a little one way and back (it moves). A coil of rope on the deck and a brass bell hung on
-- the post.
M.shipwheel = function(m, f)
	for k = 0, 3 do
		box(m, f, -0.375 + k * 0.25, 0.06, 0, 0.25, 0.25, 1.0, if k % 2 == 0 then "wood" else "sand_dark", "Plank")
	end
	cyl(m, f, 0, 0.31, -0.2, 0.5, 0.25, "wood_dark", "Post")
	cyl(m, f, 0, 0.685, -0.2, 0.5, 0.5, "wood", "Post")
	cyl(m, f, 0, 1.06, -0.2, 0.5, 0.25, "wood_dark", "Post")
	cyl(m, f, 0, 1.31, -0.2, 0.5, 0.25, "gold", "Cap")
	Parts.logZ(m, f, 0, 1.2, 0.0, 0.25, 0.25, "steel_dark", "Axle")
	-- the wheel, swinging round its hub
	local hub = V(0, 1.2, 0.18)
	local c = CFrame.new(hub)
	for k = 0, 3 do
		move(put(m, f, c * CFrame.Angles(0, 0, k * PI / 4), 1.0, 0.25, 0.25, "wood", nil, "Spoke"), "swing", hub, "Z", 0.9, 0.35)
	end
	for k = 0, 7 do
		local a = k * PI / 4 + PI / 8
		move(put(m, f, c * CFrame.new(math.cos(a) * 0.27, math.sin(a) * 0.27, 0.04) * CFrame.Angles(0, 0, a + PI / 2), 0.25, 0.25, 0.25, "wood_dark", nil, "Rim"), "swing", hub, "Z", 0.9, 0.35)
	end
	Parts.logZ(m, f, 0, 1.2, 0.27, 0.25, 0.25, "gold", "Hub")
	-- the coil and the bell
	cyl(m, f, -0.25, 0.25, 0.25, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, f, -0.25, 0.32, 0.25, 0.25, 0.25, "straw", "Coil")
	box(m, f, 0.3, 1.0, -0.2, 0.25, 0.25, 0.25, "wood_dark", "Bracket")
	ball(m, f, 0.33, 0.8, -0.2, 0.25, "gold", "Bell")
	box(m, f, 0.33, 0.62, -0.2, 0.25, 0.25, 0.25, "gold", "Bell")
end

------------------------------------------------------------------ the town

-- Bin (1 x 1): a teal painted can on a slate foot with slate bands at its middle and rim, handles each side, a green
-- sticker and a gold crest turned to the view; a white bag folded over the rim with a crumpled paper and a bottle
-- showing, a litter picker leaning on its front, two small flowers at its foot.
M.bin = function(m, f)
	stack(m, f, 0, -0.065, 0, {
		{ d = 0.75, h = 0.25, c = "slate" },
		{ d = 0.75, h = 0.25, c = "teal" },
		{ d = 0.75, h = 0.25, c = "slate" },
		{ d = 0.75, h = 0.25, c = "teal" },
		{ d = 0.75, h = 0.25, c = "slate" },
	}, "Bin")
	cyl(m, f, 0, 1.31, 0, 0.75, 0.25, "white", "Bag")
	cyl(m, f, 0, 1.33, 0, 0.5, 0.25, "black", "Inside")
	box(m, f, 0.28, 1.15, 0.12, 0.25, 0.25, 0.25, "white", "Bag")
	box(m, f, 0.05, 1.15, 0.31, 0.25, 0.25, 0.25, "white", "Bag")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.37, 0.95, 0, 0.25, 0.25, 0.25, "slate", "Handle")
	end
	put(m, f, CFrame.new(0.26, 0.81, 0.26) * CFrame.Angles(0, PI / 4, 0), 0.25, 0.25, 0.25, "gold", nil, "Crest")
	put(m, f, CFrame.new(0.26, 0.31, 0.26) * CFrame.Angles(0, PI / 4, 0), 0.25, 0.25, 0.25, "green", nil, "Sticker")
	ball(m, f, 0.1, 1.52, -0.1, 0.25, "paper", "Paper")
	put(m, f, CFrame.new(-0.12, 1.55, 0.02) * CFrame.Angles(0.3, 0, 0.2), 0.25, 0.5, 0.25, "green", nil, "Bottle")
	-- the litter picker
	strut(m, f, V(-0.2, 0.05, 0.34), V(-0.28, 1.05, 0.2), 0.25, "steel", "Picker")
	box(m, f, -0.28, 1.12, 0.19, 0.25, 0.25, 0.25, "yellow", "Grip")
	box(m, f, -0.19, 0.08, 0.35, 0.25, 0.25, 0.25, "steel_dark", "Jaw")
	tuft(m, f, -0.37, 0, -0.05, "white", true)
	tuft(m, f, 0.37, 0, -0.37, "yellow", true)
end

-- An arrow board on the signpost at height y pointing `yaw` (0 = +X): a board and a pointed end.
local function arrow(m: Instance, f: CFrame, y: number, yaw: number, color: string)
	local c = CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0)
	put(m, f, c * CFrame.new(0, 0, 0.0), 0.5, 0.25, 0.25, color, nil, "Sign")
	put(m, f, c * CFrame.new(0.375, 0.125, 0) * CFrame.Angles(0, -PI / 2, 0), 0.25, 0.25, 0.25, color, "Wedge", "Point")
	put(m, f, c * CFrame.new(0.375, -0.125, 0) * CFrame.Angles(0, -PI / 2, 0) * CFrame.Angles(0, 0, PI), 0.25, 0.25, 0.25, color, "Wedge", "Point")
end

-- Signpost (1 x 1): a dark post set in a stone with a darker collar, four painted arrows pointing four ways, a wooden
-- cap and a gold knob on top; an arm out to the east with a little cream board hung on a chain under it, a teal mark
-- painted on it, that sways in the wind (it moves); a flower by the stone.
M.signpost = function(m, f)
	cyl(m, f, 0, 0.05, 0, 0.75, 0.25, "rock", "Stone")
	cyl(m, f, 0, 0.2, 0, 0.5, 0.25, "rock_dark", "Collar")
	box(m, f, 0, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	box(m, f, 0, 2.45, 0, 0.5, 0.25, 0.5, "wood", "Cap")
	ball(m, f, 0, 2.65, 0, 0.25, "gold", "Knob")
	arrow(m, f, 2.15, math.rad(45), "cream")
	arrow(m, f, 1.9, math.rad(160), "teal")
	arrow(m, f, 1.65, math.rad(-20), "berry_red")
	arrow(m, f, 1.4, math.rad(-135), "yellow")
	-- the hanging board, swaying in its own plane
	box(m, f, 0.25, 1.1, 0, 0.5, 0.25, 0.25, "wood_dark", "Arm")
	local hub = V(0.35, 1.0, 0)
	move(box(m, f, 0.35, 0.92, 0, 0.25, 0.25, 0.25, "steel_dark", "Chain"), "swing", hub, "X", 1.7, 0.18)
	move(box(m, f, 0.35, 0.6, 0, 0.25, 0.5, 0.5, "cream", "Board"), "swing", hub, "X", 1.7, 0.18)
	move(box(m, f, 0.37, 0.6, 0, 0.25, 0.25, 0.25, "teal", "Paint"), "swing", hub, "X", 1.7, 0.18)
	tuft(m, f, -0.36, 0, 0.36, "pink", true)
	ball(m, f, 0.38, 0.06, -0.38, 0.25, "pavement", "Pebble")
end

-- Planter Box (2 x 1): a teal box on slate feet with cream corner posts, a cream rail round its top and a slate
-- skirting; leaves with red, white and yellow flowers in it, two tall pink spikes at the back, ivy trailing over the
-- front.
M.planter = function(m, f)
	box(m, f, 0, 0.375, 0, 1.75, 0.5, 0.75, "teal", "Box")
	box(m, f, 0, 0.68, on(0.375), 1.75, 0.25, 0.25, "cream", "Rail")
	box(m, f, on(0.875), 0.68, 0, 0.25, 0.25, 0.75, "cream", "Rail")
	box(m, f, 0, 0.2, on(0.375), 1.75, 0.25, 0.25, "slate", "Skirting")
	for _, x in { -0.875, 0.875 } do
		for _, z in { -0.375, 0.375 } do
			box(m, f, x * 0.93, 0.4, z * 0.93, 0.25, 0.75, 0.25, "cream", "Corner")
		end
		box(m, f, x * 0.8, 0.0, 0, 0.25, 0.25, 0.75, "slate", "Foot")
	end
	box(m, f, 0, 0.6, 0, 1.5, 0.25, 0.5, "wood_dark", "Soil")
	local blooms = { "berry_red", "white", "yellow", "berry_red", "white" }
	for k = 1, 5 do
		local x, z = -0.7 + (k - 1) * 0.35, if k % 2 == 0 then 0.1 else -0.1
		ball(m, f, x, 0.9, z, 0.5, if k % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
		box(m, f, x + 0.05, 1.15, z + 0.05, 0.25, 0.25, 0.25, blooms[k], "Bloom")
	end
	for _, x in { -0.35, 0.5 } do
		box(m, f, x, 1.2, -0.2, 0.25, 0.5, 0.25, "leaf_dark", "Stem")
		ball(m, f, x, 1.5, -0.2, 0.25, "pink", "Bloom")
	end
	box(m, f, -0.35, 0.45, 0.36, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	box(m, f, 0.5, 0.5, 0.36, 0.25, 0.25, 0.25, "leaf", "Ivy")
	box(m, f, 0.05, 0.42, 0.36, 0.25, 0.25, 0.25, "leaf", "Ivy")
end

-- Post Box (1 x 1): a red pillar box on a two-step slate foot, a darker band round its top under a cap and a dome with
-- a gold knob; turned to the view: a hooded slot with a letter half posted in it, a white plate on a darker door with
-- its keyhole, a gold crest on the cap; a dropped letter and a parcel tied with string on the step, two small
-- flowers at its foot.
M.postbox = function(m, f)
	cyl(m, f, 0, 0.06, 0, 1.0, 0.25, "slate", "Foot")
	cyl(m, f, 0, 0.2, 0, 0.75, 0.25, "slate", "Foot")
	cyl(m, f, 0, 0.7, 0, 0.75, 0.75, "berry_red", "Pillar")
	cyl(m, f, 0, 1.2, 0, 0.75, 0.25, "brick", "Band")
	cyl(m, f, 0, 1.45, 0, 1.0, 0.25, "berry_red", "Cap")
	ball(m, f, 0, 1.6, 0, 0.75, "berry_red", "Dome")
	ball(m, f, 0, 2.0, 0, 0.25, "gold", "Knob")
	-- the face, turned to the view
	local r = math.sqrt(0.5)
	local function face(d: number, y: number, w: number, h: number, color: string, name: string)
		Parts.turned(m, f, d * r, y, d * r, w, h, 0.25, PI / 4, color, name)
	end
	face(0.28, 0.6, 0.5, 0.5, "brick", "Door")
	face(0.31, 0.65, 0.25, 0.25, "white", "Plate")
	face(0.31, 0.42, 0.25, 0.25, "black", "Keyhole")
	face(0.3, 0.97, 0.5, 0.25, "black", "Slot")
	face(0.3, 1.1, 0.5, 0.25, "berry_red", "Hood")
	face(0.38, 0.97, 0.25, 0.25, "paper", "Letter")
	face(0.45, 1.45, 0.25, 0.25, "gold", "Crest")
	Parts.turned(m, f, 0.0, 0.34, 0.33, 0.25, 0.25, 0.25, 0.3, "paper", "Letter")
	box(m, f, -0.35, 0.31, 0.35, 0.25, 0.25, 0.25, "sand_dark", "Parcel")
	box(m, f, -0.33, 0.33, 0.37, 0.25, 0.25, 0.25, "wood_dark", "String")
	tuft(m, f, 0.37, 0, -0.37, "yellow", true)
	tuft(m, f, -0.37, 0, -0.1, "pink", true)
end

-- Notice Board (2 x 1): a cork board in a dark frame on two posts under a little slate roof with a cream fascia and a
-- ridge, notices pinned all over it with red and blue pins; somebody's lost red hat hung on the left post and a
-- striped scarf on the right one, a small board hung on chains under the frame offering lessons (it swings), a
-- lantern under the eave and flowers at the posts' feet.
M.noticeboard = function(m, f)
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0, 1.25, 0, 1.5, 1.0, 0.25, "sand_dark", "Cork")
	box(m, f, 0, 1.875, 0.03, 1.75, 0.25, 0.25, "wood_dark", "Frame")
	box(m, f, 0, 0.625, 0.03, 1.75, 0.25, 0.25, "wood_dark", "Frame")
	Parts.wedge(m, f, 0, 2.25, -0.25, 2.0, 0.5, 0.5, "slate", 0, "Roof")
	Parts.wedge(m, f, 0, 2.25, 0.25, 2.0, 0.5, 0.5, "slate", PI, "Roof")
	box(m, f, 0, 2.52, 0, 2.0, 0.25, 0.25, "wood_dark", "Ridge")
	box(m, f, 0, 1.95, 0.37, 2.0, 0.25, 0.25, "cream", "Fascia")
	local colours = { "paper", "yellow", "pink", "blue", "white", "cream", "paper" }
	for k, n in { { -0.45, 1.45, 0.5, 0.5 }, { 0.05, 1.5, 0.25, 0.5 }, { 0.45, 1.55, 0.5, 0.25 }, { 0.45, 1.05, 0.5, 0.5 }, { -0.2, 1.0, 0.25, 0.25 }, { -0.55, 0.95, 0.25, 0.25 }, { 0.06, 0.98, 0.25, 0.25 } } do
		box(m, f, n[1], n[2], 0.05, n[3], n[4], 0.25, colours[k], "Notice")
	end
	for k, p in { { -0.55, 1.62 }, { 0.5, 1.62 }, { 0.38, 1.22 } } do
		box(m, f, p[1], p[2], 0.08, 0.25, 0.25, 0.25, if k % 2 == 0 then "blue" else "berry_red", "Pin")
	end
	-- the hat on a nail on the left post, the scarf on the right one
	Parts.logZ(m, f, -0.75, 1.0, 0.2, 0.25, 0.5, "berry_red", "Hat")
	Parts.logZ(m, f, -0.75, 1.0, 0.3, 0.25, 0.25, "berry_red", "Hat")
	box(m, f, 0.875, 1.2, 0.2, 0.25, 0.75, 0.25, "teal", "Scarf")
	box(m, f, 0.875, 0.95, 0.23, 0.25, 0.25, 0.25, "white", "Scarf")
	-- the lessons board on its chains, swinging under the frame
	local hub = V(0, 0.5, 0.06)
	for _, p in {
		box(m, f, -0.25, 0.42, 0.06, 0.25, 0.25, 0.25, "steel_dark", "Chain"),
		box(m, f, 0.25, 0.42, 0.06, 0.25, 0.25, 0.25, "steel_dark", "Chain"),
		box(m, f, 0, 0.2, 0.06, 0.75, 0.25, 0.25, "cream", "Sign"),
		box(m, f, 0, 0.2, 0.09, 0.5, 0.25, 0.25, "teal", "Sign"),
	} do
		move(p, "swing", hub, "X", 1.5, 0.15)
	end
	lamp(m, f, 0.65, 1.7, 0.3)
	tuft(m, f, -0.7, 0, 0.3, "yellow", true)
	tuft(m, f, 0.7, 0, 0.3, "pink", true)
end

-- Newsstand (2 x 2): a little teal kiosk on a slate step with cream corner boards: a window full of magazines under a
-- striped awning with a lantern hung from it, a counter of papers, postcards on its side, a cream fascia and a sign
-- on the roof; a bundle of papers tied with string.
M.newsstand = function(m, f)
	box(m, f, 0, 0.125, -0.3, 1.75, 0.25, 1.25, "slate", "Step")
	box(m, f, 0, 1.125, -0.3, 1.75, 1.75, 1.25, "teal", "Kiosk")
	box(m, f, 0, 2.125, -0.15, 2.0, 0.25, 1.5, "slate", "Roof")
	box(m, f, 0, 1.95, on(0.6), 2.0, 0.25, 0.25, "cream", "Fascia")
	for _, x in { -0.84, 0.84 } do
		box(m, f, x, 1.125, 0.29, 0.25, 1.75, 0.25, "cream", "Corner")
	end
	-- the window and its magazines
	box(m, f, 0, 1.25, 0.25, 1.25, 0.5, 0.25, "night", "Window")
	for k, c in { "pink", "yellow", "blue", "white" } do
		box(m, f, -0.45 + (k - 1) * 0.3, 1.25, 0.3, 0.25, 0.25, 0.25, c, "Magazine")
	end
	-- the awning: red and cream stripes sloping out over the window, a lantern under it
	for k = 0, 3 do
		Parts.wedge(m, f, -0.75 + k * 0.5, 1.75, 0.575, 0.5, 0.5, 0.5, if k % 2 == 0 then "berry_red" else "cream", PI, "Awning")
	end
	lamp(m, f, -0.6, 1.4, 0.62)
	-- the counter and its papers
	box(m, f, 0, 0.875, 0.45, 1.75, 0.25, 0.5, "wood", "Counter")
	box(m, f, 0, 0.5, 0.3, 1.5, 0.5, 0.25, "cream", "Front")
	for _, x in { -0.45, 0.45 } do
		box(m, f, x, 0.5, 0.36, 0.5, 0.25, 0.25, "paper", "Paper")
	end
	box(m, f, -0.45, 1.125, 0.5, 0.5, 0.25, 0.25, "paper", "Papers")
	box(m, f, 0.35, 1.125, 0.5, 0.5, 0.25, 0.25, "white", "Papers")
	box(m, f, 0.35, 1.15, 0.53, 0.25, 0.25, 0.25, "black", "Headline")
	-- postcards on the right-hand side
	local cards = { "blue", "pink", "yellow", "green", "orange", "white" }
	for k = 1, 6 do
		box(m, f, 0.87, 0.95 + ((k - 1) // 3) * 0.35, -0.75 + ((k - 1) % 3) * 0.35, 0.25, 0.25, 0.25, cards[k], "Postcard")
	end
	-- the sign on the roof
	box(m, f, 0, 2.5, 0.2, 1.5, 0.5, 0.25, "cream", "Sign")
	for k = 0, 3 do
		box(m, f, -0.45 + k * 0.3, 2.5, 0.25, 0.25, 0.25, 0.25, "berry_red", "Letter")
	end
	-- a bundle of papers tied with string
	box(m, f, -0.6, 0.15, 0.75, 0.5, 0.25, 0.5, "paper", "Bundle")
	box(m, f, -0.6, 0.17, 0.75, 0.25, 0.25, 0.5, "sand_dark", "String")
end

------------------------------------------------------------------ the jungle

-- Tiki Mask (1 x 1): a carved board of a face on a dark post with a paler foot, among ferns, turned to look at the
-- view: a heavy brow over white eyes looking down, a long clay nose, teal and red paint on the cheeks, ears at its
-- sides, a grin of white teeth over a red tongue, a knob of a chin and a crest of five feathers; a clay bowl with a
-- flame burning in it at its foot.
M.tikimask = function(m, f)
	ball(m, f, -0.25, 0.2, 0.25, 0.5, "leaf", "Fern")
	ball(m, f, 0.24, 0.15, -0.05, 0.5, "leaf_dark", "Fern")
	local g = f * CFrame.Angles(0, PI / 4, 0)
	box(m, g, 0, 0.125, -0.05, 0.5, 0.25, 0.5, "wood", "Base")
	box(m, g, 0, 0.5, -0.05, 0.5, 0.5, 0.5, "wood_dark", "Post")
	box(m, g, 0, 1.5, 0, 1.0, 1.5, 0.25, "wood", "Mask")
	box(m, g, 0, 2.0, 0.1, 1.0, 0.25, 0.25, "wood_dark", "Brow")
	for _, s in { -1, 1 } do
		box(m, g, s * 0.25, 1.72, 0.06, 0.25, 0.5, 0.25, "white", "Eye")
		box(m, g, s * 0.25, 1.6, 0.09, 0.25, 0.25, 0.25, "black", "Pupil")
		box(m, g, s * 0.375, 1.4, 0.06, 0.25, 0.25, 0.25, if s < 0 then "teal" else "berry_red", "Paint")
		box(m, g, s * 0.44, 1.5, 0, 0.25, 0.5, 0.25, "wood_dark", "Ear")
	end
	box(m, g, 0, 1.45, 0.15, 0.25, 0.5, 0.25, "clay", "Nose")
	box(m, g, 0, 1.0, 0.06, 0.75, 0.5, 0.25, "black", "Mouth")
	box(m, g, 0, 1.12, 0.1, 0.5, 0.25, 0.25, "white", "Teeth")
	box(m, g, 0, 0.88, 0.09, 0.25, 0.25, 0.25, "berry_red", "Tongue")
	box(m, g, 0, 0.7, 0.08, 0.5, 0.25, 0.25, "wood_dark", "Chin")
	for k, c in { "teal", "yellow", "berry_red", "yellow", "teal" } do
		local a = (k - 3) * 0.35
		put(m, g, CFrame.new(math.sin(a) * 0.35, 2.4 + math.cos(a) * 0.1, -0.05) * CFrame.Angles(0, 0, -a), 0.25, 0.5, 0.25, c, nil, "Feather")
	end
	-- the bowl and its flame at the foot
	cyl(m, g, 0, 0.12, 0.3, 0.5, 0.25, "clay", "Bowl")
	Parts.glow(m, g, 0, 0.32, 0.32, 0.25, 0.25, 0.25, "orange", "Flame")
end

-- Parrot Perch (1 x 1): a carved and painted parrot on a branch set on a banded post in a stump: red with an orange
-- breast, a white face, a dark eye and a yellow beak, blue wings with yellow coverts, a blue tail with a red tip; it
-- sways from side to side on its dark feet (it moves). Leaves at one end of the branch, a cup of seed at the other,
-- a vine climbing the post.
M.parrotperch = function(m, f)
	cyl(m, f, 0, 0.125, 0, 0.75, 0.25, "wood_dark", "Stump")
	cyl(m, f, 0, 0.14, 0, 0.5, 0.25, "sand_dark", "Rings")
	box(m, f, 0, 0.85, -0.1, 0.25, 1.25, 0.25, "wood", "Post")
	box(m, f, 0, 0.6, -0.1, 0.5, 0.25, 0.5, "wood_dark", "Band")
	Parts.log(m, f, 0, 1.5, -0.1, 1.0, 0.25, "wood_dark", "Branch")
	ball(m, f, 0.36, 1.62, -0.1, 0.25, "leaf", "Leaf")
	ball(m, f, 0.34, 1.78, -0.2, 0.25, "leaf_dark", "Leaf")
	cyl(m, f, -0.38, 1.72, -0.1, 0.25, 0.25, "clay", "Cup")
	ball(m, f, -0.38, 1.85, -0.1, 0.25, "sand", "Seed")
	box(m, f, 0.1, 0.85, 0.03, 0.25, 0.5, 0.25, "leaf_dark", "Vine")
	ball(m, f, 0.12, 1.15, 0.05, 0.25, "leaf", "Vine")
	box(m, f, -0.05, 1.65, 0.02, 0.25, 0.25, 0.25, "black", "Feet")
	-- the parrot, swaying on its feet
	local hub = V(-0.05, 1.75, 0)
	for _, p in {
		box(m, f, -0.05, 1.98, 0, 0.5, 0.5, 0.5, "berry_red", "Body"),
		box(m, f, -0.05, 1.92, 0.2, 0.25, 0.25, 0.25, "orange", "Breast"),
		box(m, f, -0.05, 2.35, 0.05, 0.5, 0.5, 0.5, "berry_red", "Head"),
		box(m, f, -0.05, 2.35, 0.25, 0.25, 0.25, 0.25, "white", "Face"),
		box(m, f, 0.16, 2.42, 0.1, 0.25, 0.25, 0.25, "black", "Eye"),
		Parts.wedge(m, f, -0.05, 2.15, 0.38, 0.25, 0.25, 0.25, "yellow", PI, "Beak"),
		box(m, f, -0.35, 1.98, -0.02, 0.25, 0.5, 0.5, "blue", "Wing"),
		box(m, f, 0.25, 1.98, -0.02, 0.25, 0.5, 0.5, "blue", "Wing"),
		box(m, f, -0.37, 2.15, 0.0, 0.25, 0.25, 0.5, "yellow", "Wing"),
		box(m, f, 0.27, 2.15, 0.0, 0.25, 0.25, 0.5, "yellow", "Wing"),
		box(m, f, -0.05, 1.82, -0.37, 0.25, 0.5, 0.25, "blue", "Tail"),
		box(m, f, -0.05, 1.58, -0.37, 0.25, 0.25, 0.25, "berry_red", "Tail"),
	} do
		move(p, "swing", hub, "Z", 1.2, 0.14)
	end
end

-- Vine Arch (3 x 1): two carved posts on stone feet with bands and capitals, a rough log across their tops with paler
-- cut ends and moss on it, all of it lost in creepers: leafy clumps over the log and up the posts, vines hanging down,
-- jungle flowers and an orchid or two; a lantern hung on a vine in the middle swaying a little (it moves), a stone
-- threshold between the posts, ferns and a mushroom at their feet.
M.vinearch = function(m, f)
	box(m, f, 0, 0.06, 0, 1.75, 0.25, 0.75, "pavement", "Threshold")
	for _, x in { -1.125, 1.125 } do
		box(m, f, x, 0.125, 0, 0.75, 0.25, 0.75, "rock", "Foot")
		box(m, f, x, 1.25, 0, 0.5, 2.25, 0.5, "wood_dark", "Post")
		box(m, f, x, 2.25, 0, 0.75, 0.25, 0.75, "wood", "Capital")
		box(m, f, x, 0.9, 0, 0.75, 0.25, 0.75, "wood", "Band")
		box(m, f, x, 1.6, 0, 0.75, 0.25, 0.75, "clay", "Band")
	end
	Parts.log(m, f, 0, 2.6, 0, 2.75, 0.5, "wood", "Log")
	for _, x in { -1.35, 1.35 } do
		Parts.log(m, f, x, 2.6, 0, 0.25, 0.25, "sand_dark", "LogEnd")
	end
	box(m, f, -0.6, 2.85, 0.05, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, 0.75, 2.85, -0.05, 0.5, 0.25, 0.25, "moss", "Moss")
	for k, c in { { -1.0, 2.85, 0.05, 0.75 }, { -0.35, 2.9, -0.05, 0.75 }, { 0.35, 2.85, 0.05, 0.75 }, { 1.05, 2.9, 0.0, 0.75 }, { -1.2, 1.6, 0.22, 0.5 }, { -1.05, 0.55, 0.22, 0.5 }, { 1.2, 1.9, 0.22, 0.5 }, { 1.05, 1.2, 0.25, 0.5 }, { 1.25, 0.4, 0.15, 0.5 } } do
		ball(m, f, c[1], c[2], c[3], c[4], if k % 2 == 0 then "leaf_dark" else "leaf", "Creeper")
	end
	for _, v in { { -0.7, 0.75 }, { -0.35, 1.25 }, { 0.3, 0.5 }, { 0.6, 1.0 }, { 0.9, 0.5 } } do
		local len = v[2]
		box(m, f, v[1], 2.4 - len / 2, 0.1, 0.25, len, 0.25, "leaf_dark", "Vine")
		box(m, f, v[1] + 0.1, 2.4 - len - 0.05, 0.12, 0.25, 0.25, 0.25, "leaf", "Vine")
	end
	local flowers = { "orange", "pink", "purple", "orange", "pink", "white" }
	for k, b in { { -0.85, 3.05, 0.3 }, { 0.25, 3.1, 0.3 }, { -1.3, 1.75, 0.3 }, { 1.3, 2.05, 0.3 }, { 0.6, 0.45, 0.2 }, { 1.15, 0.65, 0.35 } } do
		box(m, f, b[1], b[2], b[3], 0.25, 0.25, 0.25, flowers[k], "Flower")
	end
	-- the lantern on its vine, swaying
	local hub = V(0, 2.4, 0.05)
	move(box(m, f, 0, 2.15, 0.05, 0.25, 0.5, 0.25, "leaf_dark", "Vine"), "swing", hub, "X", 1.3, 0.15)
	move(box(m, f, 0, 1.82, 0.05, 0.25, 0.25, 0.25, "black", "LanternCap"), "swing", hub, "X", 1.3, 0.15)
	move(Parts.glow(m, f, 0, 1.57, 0.05, 0.25, 0.25, 0.25, "yellow", "Lantern"), "swing", hub, "X", 1.3, 0.15)
	move(box(m, f, 0, 1.32, 0.05, 0.25, 0.25, 0.25, "black", "LanternFoot"), "swing", hub, "X", 1.3, 0.15)
	-- ferns and a mushroom at the feet
	ball(m, f, -0.65, 0.15, 0.25, 0.5, "leaf", "Fern")
	ball(m, f, 1.3, 0.15, -0.2, 0.25, "leaf_dark", "Fern")
	cyl(m, f, -1.35, 0.35, 0.3, 0.25, 0.25, "cream", "Mushroom")
	cyl(m, f, -1.35, 0.5, 0.3, 0.25, 0.25, "clay", "Mushroom")
end

-- Mossy Idol (2 x 2): a big stone head sunk to its lips in the earth and turned to look at the view: moss on its crown
-- and dripping down its face, a carved clay headband with teal studs and a gem that glints, a heavy brow over eyes of
-- glowing teal stone that glint now and then, a long nose, broad ears, cracks, vines hanging over it, ferns at its
-- sides; at its foot a stone slab of offerings: fruit, a bowl with a flower in it and a candle burning.
M.idol = function(m, f)
	cyl(m, f, 0, 0, 0, 2.0, 0.25, "moss", "Mound")
	local g = f * CFrame.Angles(0, PI / 4, 0)
	box(m, g, 0, 0.825, 0, 1.25, 1.75, 1.0, "rock", "Head")
	Parts.log(m, g, 0, 1.7, 0, 1.25, 1.0, "rock", "Crown")
	box(m, g, 0, 2.18, -0.05, 0.75, 0.25, 0.5, "moss", "Moss")
	box(m, g, -0.25, 2.05, 0.3, 0.5, 0.25, 0.5, "moss", "Moss")
	box(m, g, -0.5, 1.5, 0.475, 0.25, 0.75, 0.25, "moss", "Moss")
	box(m, g, 0.25, 1.95, 0.475, 0.25, 0.5, 0.25, "moss", "Moss")
	-- the face
	box(m, g, 0, 1.85, 0.525, 1.25, 0.25, 0.25, "clay", "Band")
	for _, x in { -0.4, 0.4 } do
		box(m, g, x, 1.85, 0.575, 0.25, 0.25, 0.25, "teal", "Stud")
	end
	Parts.glow(m, g, 0, 1.85, 0.605, 0.25, 0.25, 0.25, "teal", "Sparkle")
	box(m, g, 0, 1.58, 0.575, 1.25, 0.25, 0.25, "rock_dark", "Brow")
	for _, x in { -0.33, 0.33 } do
		box(m, g, x, 1.32, 0.525, 0.5, 0.25, 0.25, "rock_dark", "Socket")
		Parts.glow(m, g, x, 1.32, 0.585, 0.25, 0.25, 0.25, "teal", "Sparkle")
	end
	box(m, g, 0, 1.02, 0.625, 0.25, 0.5, 0.25, "rock", "Nose")
	box(m, g, 0, 0.5, 0.545, 0.75, 0.25, 0.25, "rock_dark", "Lips")
	for _, x in { -0.75, 0.75 } do
		box(m, g, x, 1.2, 0, 0.25, 0.75, 0.5, "rock_dark", "Ear")
	end
	put(m, g, CFrame.new(0.45, 0.8, 0.535) * CFrame.Angles(0, 0, math.rad(25)), 0.25, 0.5, 0.25, "rock_dark", nil, "Crack")
	put(m, g, CFrame.new(-0.3, 0.75, 0.535) * CFrame.Angles(0, 0, math.rad(-35)), 0.25, 0.5, 0.25, "rock_dark", nil, "Crack")
	-- vines hanging over the crown
	for _, v in { { -0.4, 0.5 }, { 0.5, 0.75 } } do
		box(m, g, v[1], 2.1 - v[2] / 2, 0.535, 0.25, v[2], 0.25, "leaf_dark", "Vine")
		box(m, g, v[1], 2.1 - v[2], 0.575, 0.25, 0.25, 0.25, "leaf", "Vine")
	end
	-- ferns, the slab of offerings
	ball(m, g, -0.8, 0.25, 0.0, 0.5, "leaf", "Fern")
	ball(m, g, 0.8, 0.3, 0.0, 0.5, "leaf_dark", "Fern")
	box(m, g, 0, 0.12, 0.75, 1.0, 0.25, 0.25, "rock_dark", "Slab")
	ball(m, g, 0.28, 0.3, 0.75, 0.25, "yellow", "Fruit")
	ball(m, g, 0.42, 0.3, 0.68, 0.25, "berry_red", "Fruit")
	cyl(m, g, 0.0, 0.3, 0.75, 0.25, 0.25, "clay", "Bowl")
	box(m, g, 0.0, 0.48, 0.75, 0.25, 0.25, 0.25, "pink", "Bloom")
	box(m, g, -0.35, 0.37, 0.75, 0.25, 0.25, 0.25, "cream", "Candle")
	Parts.glow(m, g, -0.35, 0.62, 0.75, 0.25, 0.25, 0.25, "orange", "Flame")
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor"; each built again as big as the
-- buildings of its tier for the request of 2026-11-19)

-- Beach Hut (3 x 3): a hut of white boards with teal stripes and cream corners on six dark stilts, over a deck of
-- planks with a white fascia and a white rail round its front and sides. A stable door with its top half swung open on
-- the dark inside and a brass knob, a window with a box of flowers under its sill, a lantern by the door; a roof of red
-- and coral rows with white bargeboards and a ridge where the gulls sit, a porthole in the east gable and two flags on
-- a pole. Towels drying on the rail, a wind chime of tubes and a shell swinging under the eave (it moves), a lifebuoy
-- on the east wall and a surfboard leaning by it, a potted palm on the deck, steps down to a patch of sand with a
-- bucket and spade.
M.beachhut = function(m, f)
	box(m, f, 0, 0, 1.25, 1.75, 0.25, 0.5, "sand", "Sand")
	for _, x in { -1.25, 0, 1.25 } do
		for _, z in { -1.25, 1.0 } do
			box(m, f, x, 0.25, z, 0.25, 0.5, 0.25, "wood_dark", "Stilt")
		end
	end
	-- the deck
	box(m, f, 0, 0.625, -0.125, 2.75, 0.25, 2.5, "wood_dark", "Deck")
	for _, z in { 0.375, 0.875 } do
		box(m, f, 0, 0.66, z, 2.75, 0.25, 0.25, "wood", "Plank")
	end
	box(m, f, 0, 0.6, on(1.125), 2.75, 0.25, 0.25, "white", "Fascia")
	box(m, f, on(1.375), 0.6, -0.125, 0.25, 0.25, 2.5, "white", "Fascia")
	-- the hut: white boards, teal stripes, cream corners
	box(m, f, 0, 1.625, -0.5, 2.0, 1.75, 1.5, "white", "Hut")
	for _, x in { -0.875, -0.375, 0.125, 0.625 } do
		box(m, f, x, 1.625, on(0.25), 0.25, 1.75, 0.25, "teal", "Stripe")
	end
	for _, z in { -1.0, -0.5, 0.0 } do
		box(m, f, on(1.0), 1.625, z, 0.25, 1.75, 0.25, "teal", "Stripe")
	end
	for _, z in { 0.19, -1.19 } do
		box(m, f, 0.94, 1.625, z, 0.25, 1.75, 0.25, "cream", "Corner")
	end
	-- the stable door, its top half open
	box(m, f, -0.5, 1.5, on(0.25), 0.75, 1.5, 0.25, "cream", "DoorFrame")
	box(m, f, -0.5, 1.0, 0.215, 0.5, 0.5, 0.25, "blue", "Door")
	box(m, f, -0.5, 1.625, 0.195, 0.5, 0.75, 0.25, "night", "Inside")
	box(m, f, -0.2, 1.625, 0.495, 0.25, 0.75, 0.5, "blue", "DoorLeaf")
	ball(m, f, -0.32, 1.05, 0.345, 0.25, "gold", "Knob")
	-- the window, its sill and box of flowers
	box(m, f, 0.45, 1.65, on(0.25), 0.75, 0.75, 0.25, "cream", "WindowFrame")
	box(m, f, 0.45, 1.65, 0.195, 0.5, 0.5, 0.25, "window", "Glass")
	box(m, f, 0.45, 1.65, 0.225, 0.25, 0.5, 0.25, "cream", "Bar")
	box(m, f, 0.45, 1.24, 0.295, 0.75, 0.25, 0.25, "wood", "Sill")
	box(m, f, 0.45, 1.02, 0.375, 0.75, 0.25, 0.25, "berry_red", "FlowerBox")
	for k, c in { "pink", "yellow", "white" } do
		ball(m, f, 0.2 + (k - 1) * 0.25, 1.2, 0.455, 0.25, c, "Bloom")
	end
	-- the roof, the porthole in its east gable, the flags
	gable(m, f, 0, -0.5, 2.5, 2.0, 1.5, 0.75, "berry_red", "coral", "white", "white", 0.125)
	Parts.log(m, f, 1.04, 2.85, -0.5, 0.25, 0.5, "white", "PortholeRing")
	Parts.log(m, f, 1.08, 2.85, -0.5, 0.25, 0.25, "window", "Glass")
	box(m, f, 1.0, 3.9, -0.5, 0.25, 1.0, 0.25, "white", "FlagPole")
	box(m, f, 0.75, 4.25, -0.5, 0.5, 0.25, 0.25, "berry_red", "Flag")
	box(m, f, 0.75, 4.0, -0.5, 0.5, 0.25, 0.25, "yellow", "Flag")
	-- the lifebuoy and the surfboard on the east side
	ring(m, f, CFrame.new(1.1, 1.65, -0.225) * CFrame.Angles(0, PI / 2, 0), "berry_red", "white", "Lifebuoy")
	board(m, f * CFrame.new(1.3, 0.75, -0.875) * CFrame.Angles(0, PI / 2, 0), 0, 0, 1.75, math.rad(4), "yellow", "berry_red")
	-- the lantern by the door
	box(m, f, -1.0, 2.35, 0.375, 0.25, 0.25, 0.25, "black", "Hook")
	lamp(m, f, -1.0, 1.95, 0.375)
	-- the rail round the deck, towels drying on it
	for _, x in { -1.25, -0.5, 0.5, 1.25 } do
		box(m, f, x, 1.125, 1.0, 0.25, 0.75, 0.25, "white", "RailPost")
	end
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.45, 1.0, 1.0, 0.25, 0.25, "white", "Rail")
	end
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 1.45, 0.625, 0.25, 0.25, 0.75, "white", "Rail")
	end
	for _, t in { { -1.1, "orange", "white" }, { -0.6, "pink", "yellow" }, { 0.85, "yellow", "blue" } } :: { { any } } do
		box(m, f, t[1], 1.2, 1.12, 0.5, 0.5, 0.25, t[2], "Towel")
		box(m, f, t[1], 1.05, 1.15, 0.5, 0.25, 0.25, t[3], "Towel")
	end
	-- the potted palm
	cyl(m, f, -0.95, 1.0, 0.72, 0.5, 0.5, "clay", "Pot")
	box(m, f, -0.95, 1.5, 0.72, 0.25, 0.5, 0.25, "wood", "Trunk")
	for k = 0, 2 do
		put(m, f, CFrame.new(-0.95, 1.8, 0.72) * CFrame.Angles(0, k * 2 * PI / 3 + 0.4, 0) * CFrame.new(0, 0, 0.2) * CFrame.Angles(0.5, 0, 0), 0.25, 0.25, 0.5, if k % 2 == 0 then "leaf" else "leaf_dark", nil, "Frond")
	end
	-- the steps, the bucket and spade on the sand
	box(m, f, 0, 0.125, 1.375, 0.75, 0.25, 0.25, "wood", "Step")
	box(m, f, 0, 0.25, 1.19, 0.75, 0.5, 0.25, "wood_dark", "Step")
	cyl(m, f, -0.6, 0.25, 1.24, 0.5, 0.25, "blue", "Bucket")
	cyl(m, f, -0.6, 0.5, 1.24, 0.5, 0.25, "white", "Bucket")
	put(m, f, CFrame.new(0.62, 0.55, 1.24) * CFrame.Angles(0, 0, -0.2), 0.25, 0.75, 0.25, "yellow", nil, "Spade")
	box(m, f, 0.55, 0.2, 1.24, 0.25, 0.25, 0.25, "blue", "Blade")
	-- the wind chime under the eave, swinging
	box(m, f, 1.1, 2.3, 0.4, 0.25, 0.25, 0.25, "wood_dark", "Hook")
	local hub = V(1.1, 2.2, 0.43)
	move(cyl(m, f, 1.1, 2.05, 0.43, 0.5, 0.25, "wood", "Chime"), "swing", hub, "Z", 1.8, 0.15)
	move(box(m, f, 0.98, 1.7, 0.43, 0.25, 0.5, 0.25, "steel", "Chime"), "swing", hub, "Z", 1.8, 0.15)
	move(box(m, f, 1.22, 1.6, 0.43, 0.25, 0.75, 0.25, "steel_dark", "Chime"), "swing", hub, "Z", 1.8, 0.15)
	move(ball(m, f, 1.1, 1.42, 0.43, 0.25, "pink", "Shell"), "swing", hub, "Z", 1.8, 0.15)
end

-- Hedge Maze (5 x 5): clipped hedge walls on a gravel floor in two rings with a way in at the front, the inner ring
-- open at the back and a spur that closes the right-hand way into a dead end; topiary balls on the corners and at the
-- ends of the openings, a white arch with climbing roses over the way in, lanterns on the inner corners, stepping
-- stones along the right way, a fountain at its heart throwing up spray with flowers round it, rose bushes in the
-- front corners, urns of flowers at the back and a bench in the dead end. Birds sit on the long hedge tops.
M.hedgemaze = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 5, "pavement", "Gravel")
	local walls: { { number } } = {
		-- the outer ring, the way in at the front
		{ 0, -2.25, 5.0, 0.5 },
		{ -2.25, 0, 0.5, 4.0 },
		{ 2.25, 0, 0.5, 4.0 },
		{ -1.5, 2.25, 2.0, 0.5 },
		{ 1.5, 2.25, 2.0, 0.5 },
		-- the inner ring, open at the back
		{ 0, 1.0, 2.5, 0.5 },
		{ -1.0, 0, 0.5, 1.5 },
		{ 1.0, 0, 0.5, 1.5 },
		{ -0.875, -1.0, 0.75, 0.5 },
		{ 0.875, -1.0, 0.75, 0.5 },
		-- the spur that closes the right-hand way
		{ 1.625, 0.25, 0.75, 0.5 },
	}
	for k, w in walls do
		box(m, f, w[1], 0.5, w[2], w[3], 0.75, w[4], "leaf_dark", "Hedge")
		-- (the two longest tops are named Ridge so the birds sit on them)
		box(m, f, w[1], 1.0, w[2], w[3], 0.25, w[4], "leaf", if k == 1 or k == 6 then "Ridge" else "HedgeTop")
	end
	-- topiary at the ends of the openings and on the corners
	for _, e in { { -0.75, 2.25 }, { 0.75, 2.25 }, { -0.65, -1.0 }, { 0.65, -1.0 } } do
		ball(m, f, e[1], 1.2, e[2], 0.5, "leaf", "Topiary")
	end
	for _, c in { { -2.1, -2.1 }, { 2.1, -2.1 }, { -2.1, 2.1 }, { 2.1, 2.1 } } do
		ball(m, f, c[1], 1.45, c[2], 0.75, "leaf_dark", "Topiary")
		ball(m, f, c[1], 1.9, c[2], 0.25, "leaf", "Topiary")
	end
	-- the fountain at the heart
	cyl(m, f, 0, 0.25, 0, 1.25, 0.25, "rock_dark", "Basin")
	cyl(m, f, 0, 0.5, 0, 1.25, 0.25, "rock", "Basin")
	pool(m, f, 0, 0.52, 0, 1.0, "water")
	cyl(m, f, 0, 0.9, 0, 0.25, 0.75, "pavement", "Column")
	cyl(m, f, 0, 1.3, 0, 0.75, 0.25, "rock", "Bowl")
	pool(m, f, 0, 1.32, 0, 0.5, "water")
	box(m, f, 0, 1.6, 0, 0.25, 0.5, 0.25, "white", "Spray")
	for _, c in { { -0.6, -0.6, "pink" }, { 0.6, -0.6, "yellow" }, { -0.6, 0.6, "white" }, { 0.6, 0.6, "purple" } } :: { { any } } do
		tuft(m, f, c[1], 0.125, c[2], c[3], true)
	end
	-- the arch over the way in, roses climbing it
	for _, x in { -0.6, 0.6 } do
		box(m, f, x, 0.875, 2.25, 0.25, 1.75, 0.25, "white", "ArchPost")
	end
	box(m, f, 0, 1.85, 2.25, 1.5, 0.25, 0.25, "white", "Arch")
	for k, l in { { -0.4, 2.0 }, { 0.15, 2.05 }, { 0.55, 1.6 } } do
		ball(m, f, l[1], l[2], 2.25, 0.5, if k % 2 == 0 then "leaf_dark" else "leaf", "Leaves")
	end
	for k, b in { { -0.45, 2.15 }, { 0.05, 2.2 }, { 0.4, 1.95 }, { 0.6, 1.5 } } do
		box(m, f, b[1], b[2], 2.37, 0.25, 0.25, 0.25, if k % 2 == 0 then "pink" else "berry_red", "Bloom")
	end
	-- lanterns on the inner ring's front corners
	for _, x in { -1.0, 1.0 } do
		lamp(m, f, x, 1.45, 1.0, true)
	end
	-- stepping stones along the way round the left and in at the back
	for k, s in { { 0, 1.625 }, { -0.9, 1.625 }, { -1.625, 0.9 }, { -1.625, -0.1 }, { -1.0, -1.625 }, { 0, -1.625 }, { 0, -1.0 } } do
		box(m, f, s[1], 0.13, s[2], 0.5, 0.25, 0.5, if k % 2 == 0 then "rock_dark" else "rock", "Stone")
	end
	-- rose bushes in the front corners
	for _, x in { -1.625, 1.625 } do
		ball(m, f, x, 0.4, 1.625, 0.75, "leaf_dark", "Bush")
		for k, d in { { -0.2, 0.15 }, { 0.15, 0.2 }, { 0.05, -0.15 } } do
			box(m, f, x + d[1], 0.75, 1.625 + d[2], 0.25, 0.25, 0.25, if k == 2 then "pink" else "berry_red", "Bloom")
		end
	end
	-- urns of flowers in the back corners
	for k, x in { -1.625, 1.625 } do
		cyl(m, f, x, 0.375, -1.625, 0.5, 0.5, "rock", "Urn")
		cyl(m, f, x, 0.72, -1.625, 0.5, 0.25, "pavement", "Urn")
		ball(m, f, x, 0.95, -1.625, 0.5, "leaf", "Leaves")
		box(m, f, x + 0.06, 1.2, -1.56, 0.25, 0.25, 0.25, if k == 1 then "purple" else "yellow", "Bloom")
	end
	-- the bench in the dead end
	box(m, f, 1.7, 0.4, 0.9, 0.5, 0.25, 0.75, "wood", "Bench")
	for _, z in { 0.65, 1.15 } do
		box(m, f, 1.7, 0.2, z, 0.25, 0.25, 0.25, "wood_dark", "Leg")
	end
	box(m, f, 1.92, 0.65, 0.9, 0.25, 0.5, 0.75, "wood", "BenchBack")
end

-- Red Barn (4 x 4): a red barn on a stone footing under a two-pitched slate roof with a ridge, white trim along its
-- gable and corners, dark red battens. Big double doors with white X braces and black handles up a plank ramp, a hay
-- loft door in the gable with hay spilling out under a hoist beam whose rope and hook sway (they move), a lantern by
-- the doors; two windows with white bars down the east side, a cupola on the ridge and a weathervane with its rooster
-- turning back and forth on top (it moves). Hay bales by the front, a hen pecking (her head moves) and another
-- sitting by the east wall, a pitchfork leaning on it.
M.redbarn = function(m, f)
	local zc = -0.25
	box(m, f, 0, 0.12, zc, 3.25, 0.25, 3.25, "rock", "Footing")
	box(m, f, 0, 1.25, zc, 3.0, 2.0, 3.0, "berry_red", "Walls")
	-- the gambrel: the gable ends in red, two slopes a side in slate
	box(m, f, 0, 2.625, zc, 2.0, 0.75, 3.0, "berry_red", "Gable")
	for _, s in { -1, 1 } do
		Parts.wedge(m, f, s * 1.25, 2.625, zc, 3.0, 0.75, 0.5, "berry_red", -s * PI / 2, "Gable")
		Parts.wedge(m, f, s * 0.5, 3.25, zc, 3.0, 0.5, 1.0, "berry_red", -s * PI / 2, "Gable")
	end
	-- a slab of roof from a (x, y) to b in the XY plane, `len` long from a, a little proud of the slope
	local function slab(ax: number, ay: number, bx: number, by: number, len: number, color: string, name: string, lift: number)
		local d = V(bx - ax, by - ay, 0).Unit
		local n = if d.X < 0 then V(d.Y, -d.X, 0) else V(-d.Y, d.X, 0)
		if n.Y < 0 then
			n = -n
		end
		local c = V(ax, ay, zc) + d * (len / 2) + n * lift
		put(m, f, CFrame.new(c) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X)), len, 0.25, 3.5, color, nil, name)
	end
	for _, s in { -1, 1 } do
		-- (the lower slope starts a quarter stud out past the eave)
		local ex, ey = s * 1.5, 2.25
		local d = V(s * 1.0 - ex, 3.0 - ey, 0).Unit
		slab(ex - d.X * 0.25, ey - d.Y * 0.25, s * 1.0, 3.0, 1.25, "slate", "Roof", 0.125)
		slab(s * 1.0, 3.0, 0, 3.5, 1.25, "slate", "Roof", 0.125)
	end
	-- a row line on each of the east slopes
	slab(1.35, 2.475, 1.0, 3.0, 0.25, "steel_dark", "RoofRow", 0.2)
	slab(0.55, 3.225, 0, 3.5, 0.25, "steel_dark", "RoofRow", 0.2)
	box(m, f, 0, 3.75, zc, 0.5, 0.25, 3.5, "steel_dark", "Ridge")
	-- white trim up the front gable and down the corners, an eave trim on the east
	local zf = 1.5
	for _, s in { -1, 1 } do
		strut(m, f, V(s * 1.62, 2.18, zf), V(s * 1.0, 3.1, zf), 0.25, "white", "Trim")
		strut(m, f, V(s * 1.0, 3.1, zf), V(0, 3.65, zf), 0.25, "white", "Trim")
	end
	for _, c in { { -1.45, 1.2 }, { 1.45, 1.2 }, { 1.45, -1.7 } } do
		box(m, f, c[1], 1.25, c[2], 0.25, 2.0, 0.25, "white", "Corner")
	end
	box(m, f, 1.55, 2.2, zc, 0.25, 0.25, 3.0, "white", "Eave")
	-- dark red battens
	box(m, f, -1.15, 1.25, on(1.25), 0.25, 2.0, 0.25, "brick", "Batten")
	for _, z in { -1.5, -0.25, 1.0 } do
		box(m, f, on(1.5), 1.25, z, 0.25, 2.0, 0.25, "brick", "Batten")
	end
	-- the big doors, their braces and handles, the ramp up to them
	box(m, f, 0, 1.1, on(1.25), 1.75, 1.75, 0.25, "white", "DoorFrame")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.42, 1.0, 1.25, 0.75, 1.5, 0.25, "berry_red", "Door")
		for _, t in { -1, 1 } do
			put(m, f, CFrame.new(s * 0.42, 1.0, 1.33) * CFrame.Angles(0, 0, t * 0.38), 0.25, 1.5, 0.25, "white", nil, "Brace")
		end
		box(m, f, s * 0.12, 1.0, 1.4, 0.25, 0.25, 0.25, "black", "Handle")
	end
	box(m, f, 0, 0.12, 1.5, 1.75, 0.25, 0.5, "wood", "Ramp")
	box(m, f, 0, 0.16, 1.62, 1.75, 0.25, 0.25, "wood_dark", "Ramp")
	lamp(m, f, 1.15, 1.9, 1.38)
	-- the hay loft door, its hay, the hoist beam with its rope and hook
	box(m, f, 0, 2.6, on(1.25), 0.75, 0.75, 0.25, "white", "LoftFrame")
	box(m, f, 0, 2.6, 1.22, 0.5, 0.5, 0.25, "night", "Loft")
	box(m, f, 0, 2.45, 1.32, 0.5, 0.25, 0.25, "straw", "Hay")
	ball(m, f, 0.12, 2.5, 1.38, 0.25, "yellow", "Hay")
	box(m, f, 0, 3.25, 1.45, 0.25, 0.25, 0.75, "wood_dark", "Beam")
	Parts.log(m, f, 0, 3.05, 1.7, 0.25, 0.25, "steel_dark", "Pulley")
	local hoist = V(0, 3.0, 1.7)
	move(box(m, f, 0, 2.75, 1.7, 0.25, 0.5, 0.25, "sand_dark", "Rope"), "swing", hoist, "Z", 1.4, 0.15)
	move(box(m, f, 0, 2.42, 1.7, 0.25, 0.25, 0.25, "steel_dark", "Hook"), "swing", hoist, "Z", 1.4, 0.15)
	-- the windows down the east side
	for _, z in { -1.0, 0.45 } do
		box(m, f, on(1.5), 1.5, z, 0.25, 0.75, 0.75, "white", "WindowFrame")
		box(m, f, 1.45, 1.5, z, 0.25, 0.5, 0.5, "window", "Glass")
		box(m, f, 1.48, 1.5, z, 0.25, 0.5, 0.25, "white", "Bar")
		box(m, f, 1.48, 1.5, z, 0.25, 0.25, 0.5, "white", "Bar")
		box(m, f, 1.55, 1.08, z, 0.25, 0.25, 0.75, "white", "Sill")
	end
	-- the cupola and the weathervane
	box(m, f, 0, 4.15, zc, 0.75, 0.5, 0.75, "white", "Cupola")
	box(m, f, 0, 4.15, zc + 0.3, 0.5, 0.25, 0.25, "wood_dark", "Louvre")
	box(m, f, 0.3, 4.15, zc, 0.25, 0.25, 0.5, "wood_dark", "Louvre")
	Parts.wedge(m, f, 0, 4.525, zc - 0.25, 1.0, 0.25, 0.5, "slate", 0, "CupolaRoof")
	Parts.wedge(m, f, 0, 4.525, zc + 0.25, 1.0, 0.25, 0.5, "slate", PI, "CupolaRoof")
	box(m, f, 0, 4.82, zc, 0.25, 0.5, 0.25, "steel_dark", "VanePole")
	box(m, f, 0, 4.82, zc, 0.75, 0.25, 0.25, "black", "Points")
	box(m, f, 0, 4.82, zc, 0.25, 0.25, 0.75, "black", "Points")
	local vane = V(0, 5.1, zc)
	move(box(m, f, 0, 5.1, zc, 0.75, 0.25, 0.25, "black", "Arrow"), "swing", vane, "Y", 0.4, 0.6)
	move(box(m, f, 0.375, 5.1, zc, 0.25, 0.25, 0.25, "gold", "Arrow"), "swing", vane, "Y", 0.4, 0.6)
	move(put(m, f, CFrame.new(0.05, 5.35, zc), 0.5, 0.25, 0.25, "black", "Wedge", "Rooster"), "swing", vane, "Y", 0.4, 0.6)
	-- hay bales by the front, twine round them
	for _, b in { { 1.4, 0.375 }, { 1.4, 0.875 }, { -1.4, 0.375 } } do
		box(m, f, b[1], b[2], 1.65, 0.75, 0.5, 0.5, "straw", "Bale")
		box(m, f, b[1], b[2], on(1.9), 0.25, 0.5, 0.25, "wood_dark", "Twine")
	end
	-- a hen pecking by the east wall, another sitting
	ball(m, f, 1.74, 0.25, 0.0, 0.5, "white", "Hen")
	box(m, f, 1.74, 0.4, -0.25, 0.25, 0.25, 0.25, "white", "Tail")
	local neck = V(1.74, 0.35, 0.12)
	move(box(m, f, 1.74, 0.48, 0.22, 0.25, 0.25, 0.25, "white", "Head"), "swing", neck, "X", 2.2, 0.35)
	move(box(m, f, 1.74, 0.45, 0.38, 0.25, 0.25, 0.25, "orange", "Beak"), "swing", neck, "X", 2.2, 0.35)
	move(box(m, f, 1.74, 0.65, 0.2, 0.25, 0.25, 0.25, "berry_red", "Comb"), "swing", neck, "X", 2.2, 0.35)
	ball(m, f, 1.75, 0.22, -1.0, 0.5, "cream", "Hen")
	box(m, f, 1.75, 0.45, -0.8, 0.25, 0.25, 0.25, "cream", "Head")
	box(m, f, 1.75, 0.62, -0.8, 0.25, 0.25, 0.25, "berry_red", "Comb")
	box(m, f, 1.75, 0.42, -0.64, 0.25, 0.25, 0.25, "orange", "Beak")
	-- the pitchfork against the east wall
	strut(m, f, V(1.85, 0, -1.55), V(1.65, 1.35, -1.6), 0.25, "wood", "Handle")
	box(m, f, 1.63, 1.5, -1.6, 0.25, 0.25, 0.5, "steel", "Fork")
	box(m, f, 1.63, 1.7, -1.6, 0.25, 0.25, 0.25, "steel", "Tine")
end

-- Old Galleon (5 x 3): an old ship sitting in the sand, listing and its bow raised: a hull of dark planks with paler
-- strakes, a gold rail along its side, gunports with their lids and cannons, a hole stove in near the waterline with
-- broken planks, weed and barnacles along it, sand drifted against it. A tapered bow with a bowsprit and a gold
-- figurehead, an anchor chain from the bow into the sand; a deck of planks with a foremast stump, a broken mainmast
-- with its yard, a torn sail that flaps in the wind and its rigging; a stern castle with lit windows, a gold trim, a
-- dark door, a wheel on its deck, a lantern swinging from its corner (it moves) and a red and cream flag. A crate and
-- a coil on deck, a gull on the yard. In the sand: a chest of gold with a gem in it and coins spilled, a barrel washed
-- up, a crab.
M.galleon = function(m, f)
	box(m, f, 0, 0, 0, 4.5, 0.25, 2.75, "sand", "Sand")
	local hf = f * CFrame.new(-0.1, 0, -0.15) * CFrame.Angles(0.08, 0, 0.06)
	local h = f:ToObjectSpace(hf)
	-- the hull
	box(m, hf, -0.2, 0.3, 0, 3.0, 0.75, 1.0, "wood_dark", "Hull")
	box(m, hf, -0.25, 0.85, 0, 3.5, 0.75, 1.5, "wood_dark", "Hull")
	for _, s in { -1, 1 } do
		local vx = V(0, -s, 0)
		local vy = V(0, 0, s)
		put(m, hf, CFrame.fromMatrix(V(2.0, 0.975, s * 0.375), vx, vy), 1.25, 0.75, 1.0, "wood_dark", "Wedge", "Bow")
	end
	box(m, hf, -0.25, 1.35, 0.75, 3.5, 0.5, 0.25, "wood", "Bulwark")
	box(m, hf, -0.25, 1.35, -0.75, 3.5, 0.5, 0.25, "wood_dark", "Bulwark")
	box(m, hf, -0.25, 1.62, 0.78, 3.5, 0.25, 0.25, "gold", "Rail")
	box(m, hf, -0.25, 1.15, 0, 3.25, 0.25, 1.25, "wood", "Deck")
	for _, z in { -0.3, 0.3 } do
		box(m, hf, -0.25, 1.18, z, 3.25, 0.25, 0.25, "sand_dark", "Plank")
	end
	for _, y in { 0.6, 1.15 } do
		box(m, hf, -0.25, y, 0.72, 3.5, 0.25, 0.25, "wood", "Strake")
	end
	-- gunports with lids and cannons, the hole, weed and barnacles
	for _, x in { -0.9, -0.3, 0.3 } do
		box(m, hf, x, 0.88, 0.72, 0.25, 0.25, 0.25, "black", "Port")
		box(m, hf, x, 1.0, 0.8, 0.25, 0.25, 0.25, "wood", "PortLid")
		Parts.logZ(m, hf, x, 0.85, 0.85, 0.25, 0.25, "basalt", "Cannon")
	end
	box(m, hf, 1.0, 0.85, 0.7, 0.5, 0.5, 0.25, "black", "Hole")
	put(m, hf, CFrame.new(0.78, 0.72, 0.8) * CFrame.Angles(0, 0, 0.6), 0.25, 0.5, 0.25, "wood", nil, "Splinter")
	put(m, hf, CFrame.new(1.22, 1.0, 0.8) * CFrame.Angles(0, 0, -0.5), 0.25, 0.5, 0.25, "wood", nil, "Splinter")
	for k, w in { { -1.5, 0.4 }, { -0.6, 0.35 }, { 0.45, 0.4 }, { 1.35, 0.45 } } do
		box(m, hf, w[1], w[2], 0.76, 0.25, 0.25, 0.25, if k % 2 == 0 then "moss" else "leaf_dark", "Weed")
	end
	for _, b in { { -1.2, 0.5 }, { 0.0, 0.45 }, { 0.7, 0.5 } } do
		box(m, hf, b[1], b[2], 0.78, 0.25, 0.25, 0.25, "white", "Barnacle")
	end
	-- the bow: bowsprit, figurehead, the anchor chain
	strut(m, hf, V(2.0, 1.3, 0), V(2.45, 1.95, 0), 0.25, "wood_dark", "Bowsprit")
	box(m, hf, 2.25, 1.2, 0, 0.25, 0.5, 0.25, "gold", "Figurehead")
	ball(m, hf, 2.3, 1.5, 0, 0.25, "gold", "Figurehead")
	local hawse = h * V(1.9, 0.95, 0.35)
	local seabed = V(2.25, 0.1, 0.95)
	for k = 0, 2 do
		strut(m, f, hawse:Lerp(seabed, k / 3), hawse:Lerp(seabed, (k + 1) / 3), 0.25, if k % 2 == 0 then "steel_dark" else "slate", "Chain")
	end
	-- the stern castle
	box(m, hf, -1.5, 1.75, 0, 1.0, 1.0, 1.5, "wood", "Cabin")
	box(m, hf, -1.5, 2.375, 0, 1.25, 0.25, 1.75, "wood_dark", "CabinRoof")
	box(m, hf, -1.5, 2.25, 0.82, 1.25, 0.25, 0.25, "gold", "Trim")
	for _, x in { -1.75, -1.25 } do
		Parts.glow(m, hf, x, 1.8, 0.7, 0.25, 0.25, 0.25, "yellow", "Window")
	end
	box(m, hf, -0.97, 1.65, 0, 0.25, 0.75, 0.5, "night", "Door")
	Parts.logZ(m, hf, -1.25, 2.75, 0.0, 0.25, 0.5, "wood_dark", "Wheel")
	box(m, hf, -1.25, 2.55, -0.1, 0.25, 0.5, 0.25, "wood_dark", "Helm")
	box(m, hf, -1.9, 3.0, -0.4, 0.25, 1.25, 0.25, "wood_dark", "FlagPole")
	box(m, hf, -1.55, 3.4, -0.4, 0.5, 0.25, 0.25, "berry_red", "Flag")
	box(m, hf, -1.55, 3.15, -0.4, 0.5, 0.25, 0.25, "cream", "Flag")
	-- the lantern swinging off the stern castle's corner
	box(m, hf, -0.7, 2.3, 0.85, 0.25, 0.25, 0.5, "wood_dark", "Arm")
	local lh = h * V(-0.7, 2.2, 1.0)
	move(box(m, hf, -0.7, 2.05, 1.0, 0.25, 0.25, 0.25, "black", "LanternCap"), "swing", lh, "Z", 1.3, 0.18)
	move(Parts.glow(m, hf, -0.7, 1.8, 1.0, 0.25, 0.25, 0.25, "yellow", "Lantern"), "swing", lh, "Z", 1.3, 0.18)
	move(box(m, hf, -0.7, 1.55, 1.0, 0.25, 0.25, 0.25, "black", "LanternFoot"), "swing", lh, "Z", 1.3, 0.18)
	-- the masts, the yard, the torn sail (named Flag so the wind ripples it), the rigging
	box(m, hf, 1.3, 1.5, 0, 0.25, 0.5, 0.25, "wood_dark", "Stump")
	put(m, hf, CFrame.new(0.2, 2.4, 0) * CFrame.Angles(0, 0, -0.12), 0.25, 2.5, 0.25, "wood_dark", nil, "Mast")
	box(m, hf, 0.08, 3.68, 0.06, 0.25, 0.25, 0.25, "wood", "Break")
	box(m, hf, 0.16, 3.8, -0.06, 0.25, 0.25, 0.25, "wood_dark", "Break")
	box(m, hf, 0.3, 3.1, 0, 0.25, 0.25, 1.75, "wood_dark", "Yard")
	box(m, hf, 0.35, 2.6, 0.15, 0.25, 0.75, 1.25, "cream", "FlagSail")
	box(m, hf, 0.35, 2.12, -0.2, 0.25, 0.25, 0.5, "cream", "FlagSail")
	box(m, hf, 0.38, 2.7, 0.35, 0.25, 0.25, 0.25, "sand", "Patch")
	strut(m, hf, V(0.12, 3.45, 0), V(-1.0, 2.5, 0), 0.25, "sand_dark", "Rope")
	strut(m, hf, V(0.2, 3.0, 0.1), V(0.6, 1.5, 0.75), 0.25, "sand_dark", "Rope")
	-- a gull on the yard, a crate and a coil on the deck
	box(m, hf, 0.3, 3.32, -0.6, 0.25, 0.25, 0.25, "white", "Gull")
	ball(m, hf, 0.3, 3.48, -0.48, 0.25, "white", "Gull")
	box(m, hf, 0.3, 3.45, -0.35, 0.25, 0.25, 0.25, "yellow", "Beak")
	box(m, hf, 0.85, 1.5, -0.35, 0.5, 0.5, 0.5, "sand_dark", "Crate")
	cyl(m, hf, -0.45, 1.3, 0.35, 0.5, 0.25, "sand_dark", "Coil")
	cyl(m, hf, -0.45, 1.36, 0.35, 0.25, 0.25, "straw", "Coil")
	-- sand drifted against the hull
	for _, s in { { -0.6, 0.95 }, { 0.3, 0.9 }, { 1.3, 0.8 } } do
		ball(m, f, s[1], 0.05, s[2], 0.75, "sand", "Drift")
	end
	-- the chest of gold, its gem and spilled coins
	box(m, f, 1.6, 0.35, 1.05, 0.75, 0.5, 0.5, "wood", "Chest")
	for _, x in { 1.4, 1.8 } do
		box(m, f, x, 0.35, on(1.3), 0.25, 0.5, 0.25, "steel_dark", "Band")
	end
	put(m, f, CFrame.new(1.6, 0.75, 0.82) * CFrame.Angles(-0.9, 0, 0), 0.75, 0.25, 0.5, "wood_dark", nil, "Lid")
	ball(m, f, 1.45, 0.62, 1.05, 0.5, "gold", "Gold")
	ball(m, f, 1.78, 0.6, 1.1, 0.5, "gold", "Gold")
	Parts.glow(m, f, 1.62, 0.82, 1.1, 0.25, 0.25, 0.25, "crystal", "Sparkle")
	for _, c in { { 2.12, 1.25 }, { 2.3, 0.95 }, { 1.95, 1.38 } } do
		cyl(m, f, c[1], 0.07, c[2], 0.25, 0.25, "gold", "Coin")
	end
	-- the barrel washed up, a crab
	for _, s in { { -2.05, 0.5, "wood" }, { -1.85, 0.75, "steel_dark" }, { -1.6, 0.75, "wood" }, { -1.35, 0.75, "steel_dark" }, { -1.15, 0.5, "wood" } } :: { { any } } do
		Parts.log(m, f, s[1], 0.3, 1.1, 0.25, s[2], s[3], "Barrel")
	end
	ball(m, f, 0.75, 0.15, 1.25, 0.25, "coral", "Crab")
	ball(m, f, 0.65, 0.15, 1.36, 0.25, "berry_red", "Claw")
	ball(m, f, 0.88, 0.15, 1.36, 0.25, "berry_red", "Claw")
end

-- Flower Clock (3 x 3): a round clock of flowers on a ring of gravel: a low stone rim set with twelve hour stones (gold
-- at the quarters), a bed of leaves with an hour flower at each stone, rings of pink, yellow and purple rising to a
-- green middle with white and orange flowers in the rings; two dark hands with gold tips turning slowly round a gold
-- pin (they move). In the corners a lamp post and an urn of flowers behind, a stone plaque on its stand in front,
-- tulips by each.
M.flowerclock = function(m, f)
	cyl(m, f, 0, 0, 0, 3.0, 0.25, "pavement", "Gravel")
	cyl(m, f, 0, 0.12, 0, 2.75, 0.25, "rock", "Rim")
	for k = 0, 11 do
		local a = k * PI / 6
		put(m, f, CFrame.new(math.sin(a) * 1.25, 0.26, math.cos(a) * 1.25) * CFrame.Angles(0, a, 0), 0.5, 0.25, 0.25, if k % 3 == 0 then "gold" else "pavement", nil, "Hour")
	end
	cyl(m, f, 0, 0.25, 0, 2.5, 0.25, "leaf_dark", "Bed")
	for k = 0, 11 do
		local a = k * PI / 6 + PI / 12
		local cols = { "white", "berry_red", "orange" }
		ball(m, f, math.sin(a) * 1.1, 0.45, math.cos(a) * 1.1, 0.25, cols[k % 3 + 1], "Bloom")
	end
	for k, c in ({ { 2.0, "pink" }, { 1.5, "yellow" }, { 1.0, "purple" } } :: { { any } }) do
		cyl(m, f, 0, 0.32 + k * 0.05, 0, c[1], 0.25, c[2], "Flowers")
	end
	for k = 0, 7 do
		local a = k * PI / 4
		local r = if k % 2 == 0 then 0.85 else 0.6
		ball(m, f, math.sin(a) * r, 0.55 + (if k % 2 == 0 then 0 else 0.05), math.cos(a) * r, 0.25, if k % 2 == 0 then "white" else "orange", "Bloom")
	end
	cyl(m, f, 0, 0.55, 0, 0.5, 0.25, "leaf", "Middle")
	cyl(m, f, 0, 0.85, 0, 0.25, 0.5, "gold", "Pin")
	ball(m, f, 0, 1.22, 0, 0.25, "gold", "Pin")
	-- the hands, the minute hand three times the hour hand's pace
	local hub = V(0, 0.9, 0)
	move(box(m, f, 0, 0.8, 0.375, 0.25, 0.25, 0.75, "black", "HourHand"), "spin", hub, "Y", -0.05)
	move(ball(m, f, 0, 0.8, 0.85, 0.25, "gold", "HourHand"), "spin", hub, "Y", -0.05)
	move(box(m, f, 0.5, 1.05, 0, 1.0, 0.25, 0.25, "black", "MinuteHand"), "spin", hub, "Y", -0.15)
	move(ball(m, f, 1.1, 1.05, 0, 0.25, "gold", "MinuteHand"), "spin", hub, "Y", -0.15)
	move(box(m, f, -0.2, 1.05, 0, 0.25, 0.25, 0.25, "black", "MinuteHand"), "spin", hub, "Y", -0.15)
	-- the lamp post (behind, on the right)
	cyl(m, f, 1.25, 0.125, -1.25, 0.5, 0.25, "rock_dark", "LampBase")
	box(m, f, 1.25, 1.0, -1.25, 0.25, 1.75, 0.25, "slate", "LampPost")
	box(m, f, 1.25, 1.95, -1.25, 0.5, 0.25, 0.5, "slate", "LampCap")
	Parts.glow(m, f, 1.25, 2.2, -1.25, 0.25, 0.25, 0.25, "yellow", "Lamp")
	box(m, f, 1.25, 2.45, -1.25, 0.5, 0.25, 0.5, "slate", "LampCap")
	-- the plaque (front left)
	box(m, f, -1.25, 0.3, 1.25, 0.25, 0.5, 0.25, "rock", "PlaqueStand")
	Parts.turned(m, f, -1.25, 0.65, 1.25, 0.5, 0.5, 0.25, PI / 4, "rock_dark", "Plaque")
	Parts.turned(m, f, -1.2, 0.65, 1.3, 0.25, 0.25, 0.25, PI / 4, "gold", "Plaque")
	-- the urn (behind, on the left)
	cyl(m, f, -1.25, 0.25, -1.25, 0.5, 0.5, "rock", "Urn")
	cyl(m, f, -1.25, 0.6, -1.25, 0.5, 0.25, "pavement", "Urn")
	ball(m, f, -1.25, 0.85, -1.25, 0.5, "leaf", "Leaves")
	box(m, f, -1.19, 1.1, -1.19, 0.25, 0.25, 0.25, "pink", "Bloom")
	-- tulips in the corners
	for _, t in { { 0.85, 1.32, "berry_red" }, { -1.32, 0.85, "yellow" }, { 1.32, -0.85, "pink" }, { -0.85, -1.32, "white" } } :: { { any } } do
		tuft(m, f, t[1], 0, t[2], t[3], true)
	end
end

-- Temple Steps (4 x 4): a stepped mound of four tiers of mossy stone in two shades with darker stones set in their
-- faces, moss dripping over the edges and vines down the east side, glyphs painted beside the stair; a stair of eight
-- steps up the front between sloping rails that end in carved serpent heads with glowing eyes; two braziers on the
-- first tier and two small ones on the third, their flames throwing sparks; at the top a little shrine with stone
-- pillars, a gold lintel, a slate roof with a gold ridge and finial, a glowing gem in its niche and a bowl of
-- offerings before it; ferns and flowers on the tiers.
M.templesteps = function(m, f)
	local tiers: { [number]: { s: number, z: number, d: number, front: number, y: number } } = {}
	for k = 0, 3 do
		local s = 3.75 - k * 0.75
		local z = -k * 0.2
		local d = s - 0.25
		box(m, f, 0, 0.25 + k * 0.5, z, s, 0.5, d, if k % 2 == 0 then "rock" else "rock_dark", "Tier")
		box(m, f, 0, 0.5 + k * 0.5, z, s, 0.25, d, "moss", "Moss")
		tiers[k] = { s = s, z = z, d = d, front = z + d / 2, y = 0.25 + k * 0.5 }
	end
	-- set stones in the front and east faces, moss dripping over the edges
	for k = 0, 2 do
		local t = tiers[k]
		local stone = if k % 2 == 0 then "rock_dark" else "slate"
		for _, x in { -t.s / 2 + 0.45, t.s / 2 - 0.45 } do
			box(m, f, x, t.y - 0.05, on(t.front), 0.5, 0.25, 0.25, stone, "Stone")
		end
		box(m, f, on(t.s / 2), t.y - 0.05, t.z - 0.4, 0.25, 0.25, 0.5, stone, "Stone")
		box(m, f, on(t.s / 2), t.y + 0.05, t.z + 0.6, 0.25, 0.25, 0.5, stone, "Stone")
		box(m, f, -t.s / 2 + 0.8, t.y + 0.1, on(t.front) + 0.04, 0.25, 0.5, 0.25, "moss", "Moss")
		box(m, f, t.s / 2 - 0.85, t.y + 0.1, on(t.front) + 0.04, 0.25, 0.5, 0.25, "moss", "Moss")
		box(m, f, on(t.s / 2) + 0.04, t.y + 0.1, t.z + 0.1, 0.25, 0.5, 0.25, "moss", "Moss")
	end
	for _, v in { { 0.9, 0.5 }, { -0.5, 0.75 }, { -1.3, 0.5 } } do
		box(m, f, on(1.875) + 0.04, 0.625 - v[2] / 2, v[1], 0.25, v[2], 0.25, "leaf_dark", "Vine")
	end
	-- the stair, its rails and serpent heads
	for i = 1, 8 do
		box(m, f, 0, 0.125 * i, 1.95 - 0.25 * (i - 0.5), 1.0, 0.25 * i, 0.25, if i % 2 == 0 then "rock" else "pavement", "Step")
	end
	for _, s in { -1, 1 } do
		strut(m, f, V(s * 0.625, 0.4, 1.85), V(s * 0.625, 2.2, 0.05), 0.25, "rock_dark", "StairRail")
		box(m, f, s * 0.625, 0.4, 1.8, 0.25, 0.5, 0.25, "rock_dark", "Serpent")
		Parts.glow(m, f, s * 0.7, 0.5, 1.83, 0.25, 0.25, 0.25, "teal", "Sparkle")
	end
	-- glyphs beside the stair on the second tier
	local t1 = tiers[1]
	for k, g in { { -1.0, "teal" }, { -1.35, "clay" }, { 1.0, "gold" }, { 1.35, "teal" } } :: { { any } } do
		box(m, f, g[1], t1.y - 0.05 + (k % 2) * 0.1, on(t1.front) + 0.02, 0.25, 0.25, 0.25, g[2], "Glyph")
	end
	-- the braziers: two on the first tier, two small ones on the third
	for _, s in { -1, 1 } do
		local x = s * 1.4
		cyl(m, f, x, 0.875, 1.6, 0.5, 0.5, "rock_dark", "Brazier")
		cyl(m, f, x, 1.25, 1.6, 0.75, 0.25, "gold", "Brazier")
		cyl(m, f, x, 1.3, 1.6, 0.5, 0.25, "black", "Brazier")
		Parts.glow(m, f, x, 1.55, 1.6, 0.25, 0.5, 0.25, "orange", "Flame")
		Parts.glow(m, f, x + 0.05, 1.85, 1.62, 0.25, 0.25, 0.25, "yellow", "Flame")
		cyl(m, f, s * 1.0, 1.75, 0.45, 0.5, 0.25, "gold", "Brazier")
		Parts.glow(m, f, s * 1.0, 1.98, 0.45, 0.25, 0.25, 0.25, "orange", "Flame")
	end
	-- the shrine on top
	box(m, f, 0, 2.625, -0.7, 1.0, 1.0, 0.75, "rock", "Shrine")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.5, 2.625, -0.3, 0.25, 1.0, 0.25, "pavement", "Pillar")
	end
	box(m, f, 0, 3.15, -0.3, 1.25, 0.25, 0.25, "gold", "Lintel")
	Parts.wedge(m, f, 0, 3.5, -0.95, 1.5, 0.5, 0.5, "slate", 0, "ShrineRoof")
	Parts.wedge(m, f, 0, 3.5, -0.45, 1.5, 0.5, 0.5, "slate", PI, "ShrineRoof")
	box(m, f, 0, 3.8, -0.7, 1.75, 0.25, 0.25, "gold", "Ridge")
	ball(m, f, 0, 4.0, -0.7, 0.25, "gold", "Finial")
	box(m, f, 0, 2.55, on(-0.325), 0.5, 0.5, 0.25, "black", "Niche")
	Parts.glow(m, f, 0, 2.55, -0.27, 0.25, 0.25, 0.25, "teal", "Sparkle")
	cyl(m, f, 0, 2.25, -0.05, 0.5, 0.25, "gold", "Bowl")
	ball(m, f, 0, 2.42, -0.05, 0.25, "orange", "Fruit")
	-- ferns and flowers on the tiers
	for _, p in { { -1.62, 0.7, 1.5 }, { 1.62, 0.7, 1.45 }, { 1.68, 0.7, -0.2 }, { -1.3, 1.2, -1.2 } } do
		ball(m, f, p[1], p[2], p[3], 0.5, "leaf", "Fern")
	end
	for _, b in { { -1.65, 0.625, 0.6, "pink" }, { 1.3, 1.125, 0.85, "yellow" }, { -1.3, 1.125, 0.7, "orange" }, { 1.65, 0.625, -1.0, "purple" } } :: { { any } } do
		tuft(m, f, b[1], b[2], b[3], b[4], true)
	end
end

return M
