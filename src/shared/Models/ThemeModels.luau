--!strict
-- The themed decor: beach, garden, farm, harbour, town, jungle (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- Each theme keeps to its own colours so an island built in one hangs together: the beach sand, pale wood and
-- stripes (coral, yellow, teal, blue and white); the garden soft stone, white paint, roses and blossom; the farm rough
-- wood, straw, tin and twine; the harbour weathered wood, rope, slate iron and red and white; the town painted wood
-- (teal and cream) and slate iron; the jungle mossy stone, carved and painted wood and hanging vines.
local Blocks = require(script.Parent.Blocks)
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

local PI = math.pi
local box, ball, cyl = Parts.box, Parts.ball, Parts.cyl

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

------------------------------------------------------------------ the beach

-- Coconut Pile (1 x 1): three coconuts on a patch of sand and one on top, a green one among them, one split open
-- and white inside, a palm frond fallen behind them.
M.coconuts = function(m, f)
	cyl(m, f, 0, 0, 0, 1.0, 0.25, "sand", "Sand")
	Parts.turned(m, f, 0.05, 0.15, -0.25, 0.75, 0.25, 0.25, -0.35, "leaf", "Frond")
	ball(m, f, -0.2, 0.37, -0.2, 0.5, "wood_dark", "Coconut")
	ball(m, f, 0.22, 0.37, -0.18, 0.5, "wood", "Coconut")
	ball(m, f, -0.2, 0.37, 0.22, 0.5, "moss", "Coconut")
	ball(m, f, 0, 0.72, -0.06, 0.5, "wood", "Coconut")
	cyl(m, f, 0.24, 0.25, 0.24, 0.5, 0.25, "wood_dark", "Half")
	cyl(m, f, 0.24, 0.27, 0.24, 0.25, 0.25, "white", "Flesh")
end

-- Deck Chair (1 x 2): a low frame of pale wood, blue and white canvas sagging in the seat and leaning back, a
-- yellow cushion at the top. The foot is toward +Z.
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
	for _, x in { -0.375, 0.375 } do
		box(m, f, x, 0.48, 0.42, 0.25, 0.25, 1.0, "wood", "Rail")
		put(m, f, back(0.55, x, 0.05), 0.25, 0.25, 1.0, "wood", nil, "Rail")
		box(m, f, x, 0.2, 0.8, 0.25, 0.5, 0.25, "wood", "Leg")
		strut(m, f, Vector3.new(x, 0.8, -0.55), Vector3.new(x, 0, -0.82), 0.25, "wood", "Leg")
	end
	put(m, f, back(1.05, 0, 0.05), 0.75, 0.25, 0.25, "wood", nil, "Bar")
	put(m, f, back(0.85, 0, 0.22), 0.5, 0.25, 0.25, "yellow", nil, "Cushion")
end

-- Beach Umbrella (2 x 2): a wooden pole in a little mound of sand, a canopy of coral and white panels, a striped
-- towel and a cool box in its shade.
M.umbrella = function(m, f)
	cyl(m, f, 0, 0, 0, 0.75, 0.25, "sand", "Mound")
	box(m, f, 0, 1.1, 0, 0.25, 2.2, 0.25, "wood", "Pole")
	local top, tilt = 2.3, math.rad(24)
	for k = 0, 7 do
		local coloured = k % 2 == 0
		local cf = CFrame.new(0, top - (if coloured then 0 else 0.08), 0) * CFrame.Angles(0, k * PI / 4, 0) * CFrame.Angles(tilt, 0, 0)
		put(m, f, cf * CFrame.new(0, -0.125, 0.5), if coloured then 0.5 else 0.75, 0.25, 1.0, if coloured then "coral" else "white", nil, "Canopy")
	end
	cyl(m, f, 0, top + 0.1, 0, 0.25, 0.25, "white", "Finial")
	-- a towel (teal ends, yellow middle) and a cool box
	box(m, f, 0.45, 0, -0.15, 0.75, 0.25, 0.25, "teal", "Towel")
	box(m, f, 0.45, 0, 0.35, 0.75, 0.25, 0.75, "yellow", "Towel")
	box(m, f, 0.45, 0, 0.85, 0.75, 0.25, 0.25, "teal", "Towel")
	box(m, f, -0.55, 0.25, 0.55, 0.5, 0.5, 0.5, "blue", "CoolBox")
	box(m, f, -0.55, 0.625, 0.55, 0.5, 0.25, 0.5, "white", "Lid")
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

-- Surfboard Rack (2 x 1): a rack of pale wood with three boards leaning on it, coral, yellow and teal.
M.surfboards = function(m, f)
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 0.625, -0.3, 0.25, 1.25, 0.25, "wood", "Post")
		box(m, f, x, 0.125, 0.05, 0.25, 0.25, 0.75, "wood", "Foot")
	end
	box(m, f, 0, 1.15, -0.3, 2.0, 0.25, 0.25, "wood", "Bar")
	box(m, f, 0, 0.125, 0.4, 1.5, 0.25, 0.25, "wood_dark", "Lip")
	board(m, f, -0.6, 0.15, 1.75, math.rad(12), "coral", "white")
	board(m, f, 0, 0.15, 1.5, math.rad(14), "yellow", "teal")
	board(m, f, 0.6, 0.15, 1.75, math.rad(12), "teal", "white")
end

-- Lifeguard Chair (2 x 2): four white legs leaning in, a ladder up the front, a seat on a platform under a red and
-- white roof, a lifebuoy hung on the side and a flag to say the sea is watched.
M.lifeguard = function(m, f)
	local top = 2.25
	local function at(y: number): number -- a leg's distance out from the middle at height y
		return 0.8 - 0.25 * y / top
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		strut(m, f, Vector3.new(c[1] * 0.8, 0, c[2] * 0.8), Vector3.new(c[1] * at(top), top, c[2] * at(top)), 0.25, "white", "Leg")
	end
	for _, y in { 0.5, 0.95, 1.4, 1.85 } do
		box(m, f, 0, y, at(y), at(y) * 2, 0.25, 0.25, "wood", "Rung")
	end
	box(m, f, at(1.0), 1.0, 0, 0.25, 0.25, at(1.0) * 2, "white", "Brace")
	box(m, f, -at(1.0), 1.0, 0, 0.25, 0.25, at(1.0) * 2, "white", "Brace")
	box(m, f, 0, 1.0, -at(1.0), at(1.0) * 2, 0.25, 0.25, "white", "Brace")
	-- the platform, the seat
	box(m, f, 0, top + 0.125, 0, 1.5, 0.25, 1.5, "wood", "Platform")
	box(m, f, 0, top + 0.375, -0.1, 1.0, 0.25, 0.75, "white", "Seat")
	box(m, f, 0, top + 0.75, -0.5, 1.0, 0.75, 0.25, "white", "Back")
	for _, x in { -0.5, 0.5 } do
		box(m, f, x, top + 0.625, -0.1, 0.25, 0.25, 0.75, "wood", "Arm")
	end
	-- the roof on four posts, striped red and white; the back left post runs on up as the flagpole
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local tall = c[1] == -1 and c[2] == -1
		local h = if tall then 2.25 else 1.25
		box(m, f, c[1] * 0.625, top + 0.25 + h / 2, c[2] * 0.625, 0.25, h, 0.25, "white", if tall then "FlagPole" else "Post")
	end
	for k = -1, 1 do
		box(m, f, k * 0.5, top + 1.625, 0, 0.5, 0.25, 1.5, if k == 0 then "white" else "berry_red", "Roof")
	end
	box(m, f, -0.125, top + 2.125, -0.625, 0.75, 0.25, 0.25, "berry_red", "Flag")
	box(m, f, -0.125, top + 1.875, -0.625, 0.75, 0.25, 0.25, "yellow", "Flag")
	-- a lifebuoy on the right-hand side
	ring(m, f, CFrame.new(at(1.55) + 0.15, 1.55, 0) * CFrame.Angles(0, PI / 2, 0), "berry_red", "white", "Lifebuoy")
end

------------------------------------------------------------------ the garden

-- Garden Gnome (1 x 1): on a round stone, brown boots, a blue coat with a gold buckle, a white beard, a pink nose
-- and a tall red hat.
M.gnome = function(m, f)
	cyl(m, f, 0, 0, 0, 0.75, 0.25, "rock", "Stone")
	box(m, f, 0, 0.25, 0.04, 0.5, 0.25, 0.5, "wood_dark", "Boots")
	cyl(m, f, 0, 0.625, 0, 0.5, 0.5, "blue", "Coat")
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.66, 0.02, 0.25, 0.5, 0.25, "blue", "Arm")
	end
	box(m, f, 0, 0.48, 0.18, 0.25, 0.25, 0.25, "gold", "Buckle")
	ball(m, f, 0, 1.05, 0, 0.5, "skin2", "Head")
	box(m, f, 0, 0.82, 0.18, 0.5, 0.5, 0.25, "white", "Beard")
	ball(m, f, 0, 1.12, 0.24, 0.25, "pink", "Nose")
	cyl(m, f, 0, 1.375, 0, 0.5, 0.25, "berry_red", "Hat")
	put(m, f, CFrame.new(0, 1.62, -0.05) * CFrame.Angles(math.rad(-14), 0, 0) * CFrame.Angles(0, 0, PI / 2), 0.5, 0.25, 0.25, "berry_red", "Cylinder", "Hat")
end

-- Wheelbarrow (2 x 1): a red tray on a black wheel (toward +X), wooden handles and legs, a heap of soil with a
-- trowel stuck in it and a seedling.
M.wheelbarrow = function(m, f)
	Parts.logZ(m, f, 0.7, 0.25, 0, 0.25, 0.5, "black", "Wheel")
	Parts.logZ(m, f, 0.7, 0.25, 0.06, 0.25, 0.25, "steel", "Hub")
	box(m, f, -0.2, 0.65, 0, 0.75, 0.5, 0.75, "berry_red", "Tray")
	Parts.wedge(m, f, 0.42, 0.65, 0, 0.75, 0.5, 0.5, "berry_red", -PI / 2, "Tray")
	for _, z in { -0.3, 0.3 } do
		box(m, f, -0.6, 0.55, z, 0.75, 0.25, 0.25, "wood", "Handle")
		box(m, f, -0.9, 0.55, z, 0.25, 0.25, 0.25, "wood_dark", "Grip")
		box(m, f, -0.35, 0.2, z, 0.25, 0.5, 0.25, "steel_dark", "Leg")
	end
	box(m, f, -0.15, 0.92, 0, 0.75, 0.25, 0.5, "wood_dark", "Soil")
	ball(m, f, -0.2, 0.98, 0, 0.5, "wood_dark", "Soil")
	put(m, f, CFrame.new(0.15, 1.12, 0.05) * CFrame.Angles(0, 0, math.rad(-20)), 0.25, 0.25, 0.25, "steel", nil, "Trowel")
	put(m, f, CFrame.new(0.22, 1.35, 0.05) * CFrame.Angles(0, 0, math.rad(-20)), 0.25, 0.5, 0.25, "wood", nil, "Handle")
	box(m, f, -0.45, 1.1, 0.1, 0.25, 0.25, 0.25, "leaf", "Seedling")
end

-- Birdbath (1 x 1): a grey stone column and bowl full of clear water, a bluebird on the rim, flowers at its foot.
M.birdbath = function(m, f)
	cyl(m, f, 0, 0, 0, 0.75, 0.25, "rock_dark", "Foot")
	cyl(m, f, 0, 0.375, 0, 0.5, 0.5, "rock", "Column")
	cyl(m, f, 0, 0.75, 0, 0.75, 0.25, "rock", "Flare")
	cyl(m, f, 0, 1.0, 0, 1.0, 0.25, "rock", "Bowl")
	pool(m, f, 0, 1.02, 0, 0.75, "shallow")
	-- the bird on the far rim, facing +X
	box(m, f, -0.1, 1.25, -0.32, 0.5, 0.25, 0.25, "blue", "Bird")
	box(m, f, 0.15, 1.42, -0.32, 0.25, 0.25, 0.25, "blue", "Bird")
	box(m, f, 0.3, 1.38, -0.32, 0.25, 0.25, 0.25, "orange", "Beak")
	-- flowers
	ball(m, f, 0.3, 0.2, 0.3, 0.5, "leaf", "Leaves")
	box(m, f, 0.32, 0.45, 0.32, 0.25, 0.25, 0.25, "pink", "Bloom")
	ball(m, f, -0.32, 0.15, 0.28, 0.5, "leaf_dark", "Leaves")
	box(m, f, -0.3, 0.38, 0.3, 0.25, 0.25, 0.25, "purple", "Bloom")
end

-- Beehive (1 x 1): two painted boxes (white, then yellow) on a dark stand, a clay roof, the way in at the foot and
-- three bees about it.
M.beehive = function(m, f)
	for _, x in { -0.25, 0.25 } do
		box(m, f, x, 0.125, 0, 0.25, 0.25, 0.75, "wood_dark", "Runner")
	end
	box(m, f, 0, 0.375, 0, 0.75, 0.25, 0.75, "wood_dark", "Stand")
	box(m, f, 0, 0.75, 0, 0.75, 0.5, 0.75, "white", "Box")
	box(m, f, 0, 1.25, 0, 0.75, 0.5, 0.75, "yellow", "Box")
	box(m, f, 0, 1.625, 0, 1.0, 0.25, 1.0, "wood", "Lid")
	Parts.wedge(m, f, 0, 1.875, -0.25, 1.0, 0.25, 0.5, "clay", 0, "Roof")
	Parts.wedge(m, f, 0, 1.875, 0.25, 1.0, 0.25, 0.5, "clay", PI, "Roof")
	box(m, f, 0, 0.6, 0.3, 0.5, 0.25, 0.25, "black", "Door")
	box(m, f, 0.37, 0.8, 0, 0.25, 0.25, 0.25, "wood_dark", "Handle")
	box(m, f, 0.37, 1.3, 0, 0.25, 0.25, 0.25, "wood_dark", "Handle")
	ball(m, f, 0.42, 1.0, -0.4, 0.25, "yellow", "Bee")
	ball(m, f, -0.4, 1.55, 0.42, 0.25, "yellow", "Bee")
	ball(m, f, 0.3, 2.2, 0.3, 0.25, "yellow", "Bee")
end

-- A lattice of slats crossing at 45 degrees in the XY plane at z, filling x0..x1, y0..y1, `gap` apart along X.
local function lattice(m: Instance, f: CFrame, x0: number, x1: number, y0: number, y1: number, z: number, gap: number, color: string)
	for _, s in { 1, -1 } do
		-- lines y = s * x + c
		local lo = if s == 1 then y0 - x1 else y0 + x0
		local hi = if s == 1 then y1 - x0 else y1 + x1
		local c = lo + gap / 2
		while c < hi do
			local xa = if s == 1 then math.max(x0, y0 - c) else math.max(x0, c - y1)
			local xb = if s == 1 then math.min(x1, y1 - c) else math.min(x1, c - y0)
			if xb - xa > 0.2 then
				local xm = (xa + xb) / 2
				put(m, f, CFrame.new(xm, s * xm + c, z) * CFrame.Angles(0, 0, s * PI / 4), (xb - xa) * math.sqrt(2), 0.25, 0.25, color, nil, "Slat")
			end
			c += gap
		end
	end
end

-- Rose Trellis (2 x 1): a white lattice between two posts, a rose climbing it from a bed of earth, red and pink
-- roses among the leaves.
M.trellis = function(m, f)
	box(m, f, 0, 0, 0.1, 1.75, 0.25, 0.75, "wood_dark", "Bed")
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.0, -0.25, 0.25, 2.0, 0.25, "white", "Post")
	end
	box(m, f, 0, 1.875, -0.25, 2.0, 0.25, 0.25, "white", "Rail")
	box(m, f, 0, 0.25, -0.25, 1.5, 0.25, 0.25, "white", "Rail")
	lattice(m, f, -0.75, 0.75, 0.375, 1.75, -0.25, 0.8, "white")
	for k, l in { { -0.55, 0.45 }, { -0.4, 0.95 }, { -0.15, 1.45 }, { 0.35, 1.6 }, { 0.55, 1.05 }, { 0.3, 0.4 }, { -0.75, 0.25 } } do
		ball(m, f, l[1], l[2], -0.05, 0.5, if k % 2 == 1 then "leaf_dark" else "leaf", "Leaves")
	end
	for k, r in { { -0.45, 0.65 }, { -0.25, 1.2 }, { 0.05, 1.65 }, { 0.55, 1.35 }, { 0.45, 0.75 }, { 0.1, 0.45 } } do
		box(m, f, r[1], r[2], 0.17, 0.25, 0.25, 0.25, if k % 2 == 0 then "pink" else "berry_red", "Rose")
	end
end

-- Sundial (1 x 1): a square pedestal of pale stone on a step, a brass dial with its dark blade, flowers round its
-- foot.
M.sundial = function(m, f)
	box(m, f, 0, 0.125, 0, 0.75, 0.25, 0.75, "pavement", "Step")
	box(m, f, 0, 0.625, 0, 0.5, 0.75, 0.5, "cream", "Pedestal")
	box(m, f, 0, 1.125, 0, 0.75, 0.25, 0.75, "pavement", "Cap")
	cyl(m, f, 0, 1.3, 0, 0.75, 0.25, "gold", "Dial")
	Parts.wedge(m, f, 0, 1.6, 0, 0.25, 0.5, 0.5, "slate", PI / 2, "Blade")
	local blooms = { "purple", "pink", "yellow" }
	for k, c in { { 0.38, 0.38 }, { -0.38, 0.38 }, { 0.38, -0.38 } } do
		ball(m, f, c[1], 0.15, c[2], 0.25, "leaf", "Leaves")
		box(m, f, c[1], 0.35, c[2], 0.25, 0.25, 0.25, blooms[k], "Bloom")
	end
end

------------------------------------------------------------------ the farm

-- A milk churn standing on y0 at (x, z): a tin body, a dark narrow neck, a wide lid.
local function churn(m: Instance, f: CFrame, x: number, y0: number, z: number, body: number)
	stack(m, f, x, y0, z, {
		{ d = 0.5, h = body, c = "steel" },
		{ d = 0.25, h = 0.25, c = "steel_dark" },
		{ d = 0.5, h = 0.25, c = "steel" },
	}, "Churn")
end

-- Milk Churns (1 x 1): two tin churns side by side on a low stand of planks, one taller, a wisp of straw.
M.churns = function(m, f)
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.06, 0, 0.25, 0.25, 0.75, "wood_dark", "Block")
	end
	box(m, f, 0, 0.25, 0, 1.0, 0.25, 1.0, "wood", "Stand")
	churn(m, f, -0.24, 0.375, 0.24, 0.75)
	churn(m, f, 0.24, 0.375, -0.24, 0.5)
	box(m, f, 0.4, 0.06, 0.42, 0.25, 0.25, 0.25, "straw", "Straw")
end

-- Hay Bale (2 x 1): a long bale of straw tied with two bands of twine, its cut end lighter, loose straw about.
M.haybale = function(m, f)
	box(m, f, -0.125, 0.375, 0, 1.5, 0.75, 0.75, "straw", "Bale")
	box(m, f, 0.75, 0.375, 0, 0.25, 0.75, 0.75, "sand", "End")
	for _, x in { -0.5, 0.25 } do
		box(m, f, x, 0.375, 0.28, 0.25, 0.75, 0.25, "wood_dark", "Twine")
		box(m, f, x, 0.655, 0, 0.25, 0.25, 0.75, "wood_dark", "Twine")
	end
	put(m, f, CFrame.new(-0.6, 0.8, -0.1) * CFrame.Angles(0, 0.4, math.rad(25)), 0.5, 0.25, 0.25, "yellow", nil, "Tuft")
	put(m, f, CFrame.new(0.55, 0.06, 0.4) * CFrame.Angles(0, 0.5, 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
	box(m, f, -0.75, 0.06, 0.35, 0.25, 0.25, 0.25, "straw", "Straw")
end

-- Scarecrow (1 x 1): turned to face the view with its arms out: a post and crossbar, a red shirt with a yellow
-- patch, blue trousers with straw at the cuffs and hands, a sacking head with a stitched mouth under a straw hat.
M.scarecrow = function(m, f)
	local g = f * CFrame.Angles(0, PI / 4, 0)
	cyl(m, g, 0, 0, 0, 0.5, 0.25, "wood_dark", "Mound")
	box(m, g, 0, 0.875, -0.15, 0.25, 1.75, 0.25, "wood_dark", "Post")
	box(m, g, 0, 1.45, -0.15, 1.25, 0.25, 0.25, "wood_dark", "Bar")
	box(m, g, 0, 1.45, 0, 1.0, 0.25, 0.25, "berry_red", "Sleeves")
	box(m, g, 0, 1.0, 0, 0.5, 0.75, 0.5, "berry_red", "Shirt")
	box(m, g, 0.12, 0.95, 0.2, 0.25, 0.25, 0.25, "yellow", "Patch")
	for _, x in { -0.125, 0.125 } do
		box(m, g, x, 0.5, 0, 0.25, 0.5, 0.25, "jeans", "Leg")
		box(m, g, x, 0.2, 0.02, 0.25, 0.25, 0.25, "straw", "Straw")
	end
	for _, x in { -0.5, 0.5 } do
		box(m, g, x, 1.25, 0, 0.25, 0.25, 0.25, "straw", "Hand")
	end
	ball(m, g, 0, 1.8, 0, 0.5, "cream", "Head")
	box(m, g, 0, 1.72, 0.2, 0.25, 0.25, 0.25, "wood_dark", "Stitch")
	cyl(m, g, 0, 2.05, 0, 0.75, 0.25, "straw", "Brim")
	cyl(m, g, 0, 2.25, 0, 0.5, 0.25, "straw", "Crown")
end

-- A barrel lying along Z at (x, y, z), 1.25 long: a bulge, two dark hoops, its end showing a darker lid, a tap.
local function lyingBarrel(m: Instance, f: CFrame, x: number, y: number, z: number, tap: boolean?)
	for k = 1, 5 do
		local hoop = k == 2 or k == 4
		Parts.logZ(m, f, x, y, z - 0.75 + k * 0.25, 0.25, if k == 1 or k == 5 then 0.75 else 1.0, if hoop then "steel_dark" else "wood", "Barrel")
	end
	Parts.logZ(m, f, x, y, z + 0.55, 0.25, 0.5, "wood_dark", "Lid")
	if tap then
		box(m, f, x, y - 0.1, z + 0.7, 0.25, 0.25, 0.25, "steel", "Tap")
	end
end

-- Barrel Stack (2 x 2): two barrels lying side by side on a pair of beams and a third on top of them.
M.barrels = function(m, f)
	for _, z in { -0.4, 0.4 } do
		box(m, f, 0, 0.125, z, 2.0, 0.25, 0.25, "wood_dark", "Beam")
	end
	lyingBarrel(m, f, -0.5, 0.75, -0.05, false)
	lyingBarrel(m, f, 0.5, 0.75, -0.05, true)
	lyingBarrel(m, f, 0, 1.62, -0.15, false)
end

-- Haystack (2 x 2): a round stack of straw rising to a knot, a few loose wisps, a pitchfork leaning on it.
M.haystack = function(m, f)
	cyl(m, f, -0.1, 0.25, -0.1, 1.75, 0.5, "straw", "Hay")
	ball(m, f, -0.1, 0.65, -0.1, 1.75, "straw", "Hay")
	ball(m, f, -0.1, 1.35, -0.1, 1.0, "straw", "Hay")
	ball(m, f, -0.1, 1.9, -0.1, 0.5, "sand_dark", "Knot")
	for _, t in { { 0.45, 1.0, 0.45, 0.6 }, { -0.55, 1.05, 0.4, -0.5 }, { 0.6, 0.45, -0.3, 1.2 } } do
		put(m, f, CFrame.new(t[1], t[2], t[3]) * CFrame.Angles(0, t[4], math.rad(30)), 0.5, 0.25, 0.25, "yellow", nil, "Wisp")
	end
	-- the pitchfork, tines up, leaning on the front
	local foot, head = Vector3.new(0.85, 0, 0.75), Vector3.new(0.55, 1.6, 0.45)
	strut(m, f, foot, head, 0.25, "wood", "Handle")
	-- the fork's frame: up the handle, its tines spread across the view
	local up = (head - foot).Unit
	local across = Vector3.new(1, 0, -1).Unit
	across = (across - up * across:Dot(up)).Unit
	local cf = CFrame.fromMatrix(head, across, up)
	put(m, f, cf * CFrame.new(0, 0.125, 0), 0.75, 0.25, 0.25, "steel", nil, "Fork")
	for _, s in { -1, 1 } do
		put(m, f, cf * CFrame.new(s * 0.25, 0.5, 0), 0.25, 0.5, 0.25, "steel", nil, "Tine")
	end
	put(m, f, CFrame.new(0.3, 0.06, 0.85) * CFrame.Angles(0, 0.3, 0), 0.5, 0.25, 0.25, "straw", nil, "Straw")
end

-- Water Trough (2 x 1): a trough of planks on two dark blocks, iron bands round it, water up to the brim, a tin cup
-- hung on its end.
M.trough = function(m, f)
	for _, x in { -0.6, 0.6 } do
		box(m, f, x, 0.125, 0, 0.25, 0.25, 1.0, "wood_dark", "Block")
	end
	box(m, f, 0, 0.375, 0, 1.75, 0.25, 1.0, "wood", "Bottom")
	for _, z in { -0.35, 0.35 } do
		box(m, f, 0, 0.625, z, 1.75, 0.25, 0.25, "wood", "Side")
	end
	for _, x in { -0.75, 0.75 } do
		box(m, f, x, 0.625, 0, 0.25, 0.25, 0.5, "wood_dark", "End")
	end
	Parts.water(m, f, 0, 0.615, 0, 1.25, 0.5)
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.5, 0.37, 0.25, 0.5, 0.25, "steel_dark", "Band")
	end
	cyl(m, f, 0.75, 0.875, 0, 0.25, 0.25, "steel", "Cup")
end

-- A cart wheel turning about Z at (x, y, z): an iron-shod rim, four crossing spokes on its outer face (+Z when
-- side is 1), a hub.
local function wheel(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, side: number)
	Parts.logZ(m, f, x, y, z, 0.25, dia, "wood_dark", "Wheel")
	for k = 0, 3 do
		put(m, f, CFrame.new(x, y, z + side * 0.06) * CFrame.Angles(0, 0, k * PI / 4), dia - 0.25, 0.25, 0.25, "wood", nil, "Spoke")
	end
	Parts.logZ(m, f, x, y, z + side * 0.12, 0.25, 0.5, "steel_dark", "Hub")
end

-- Farm Cart (3 x 2): a plank bed with staked sides on two big wheels, shafts resting on the ground (+X), a prop at
-- the back, and a load of veg: cabbages, a pumpkin, carrots, turnips, a crate of apples, a sack of potatoes.
M.cart = function(m, f)
	wheel(m, f, -0.25, 0.625, 0.75, 1.25, 1)
	wheel(m, f, -0.25, 0.625, -0.75, 1.25, -1)
	Parts.logZ(m, f, -0.25, 0.625, 0, 1.25, 0.25, "wood_dark", "Axle")
	box(m, f, -0.25, 1.0, 0, 2.25, 0.25, 1.25, "wood", "Bed")
	for _, z in { -0.5, 0.5 } do
		box(m, f, -0.25, 1.375, z, 2.25, 0.5, 0.25, "wood", "Side")
	end
	for _, x in { -1.25, 0.75 } do
		box(m, f, x, 1.375, 0, 0.25, 0.5, 0.75, "wood", "End")
	end
	for _, x in { -1.25, 0.75 } do
		box(m, f, x, 1.4, 0.55, 0.25, 0.75, 0.25, "wood_dark", "Stake")
	end
	box(m, f, -1.25, 0.45, 0, 0.25, 0.9, 0.25, "wood_dark", "Prop")
	for _, z in { -0.375, 0.375 } do
		strut(m, f, Vector3.new(0.75, 0.95, z), Vector3.new(1.4, 0.15, z), 0.25, "wood_dark", "Shaft")
	end
	box(m, f, 1.3, 0.25, 0, 0.25, 0.25, 1.0, "wood_dark", "Bar")
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
	ball(m, f, -0.4, 1.7, -0.2, 0.25, "purple", "Turnip")
	ball(m, f, -0.25, 1.62, -0.25, 0.25, "white", "Turnip")
	box(m, f, 0.45, 1.375, 0, 0.5, 0.5, 0.5, "wood_dark", "Crate")
	for _, a in { { 0.35, -0.1 }, { 0.55, 0.1 }, { 0.5, -0.12 } } do
		ball(m, f, a[1], 1.7, a[2], 0.25, "berry_red", "Apple")
	end
	box(m, f, -0.95, 1.4, 0.1, 0.5, 0.5, 0.5, "sand_dark", "Sack")
end

-- Stone Well (2 x 2): a round wall of stones, a ring of pale capstones round the dark shaft, two posts holding a
-- thatched roof and a windlass with a crank, a bucket hanging on its rope.
M.well = function(m, f)
	cyl(m, f, 0, 0.375, 0, 1.75, 0.75, "rock", "Wall")
	for _, s in { { 0.3, 0.25 }, { 1.1, 0.5 }, { 1.7, 0.25 }, { 0.75, 0.6 }, { 1.4, 0.15 } } do
		local a = s[1]
		put(m, f, CFrame.new(math.cos(a) * 0.82, s[2] + 0.12, math.sin(a) * 0.82) * CFrame.Angles(0, -a, 0), 0.25, 0.25, 0.5, "rock_dark", nil, "Stone")
	end
	for k = 0, 7 do
		local a = k * PI / 4
		put(m, f, CFrame.new(math.cos(a) * 0.75, 0.875, math.sin(a) * 0.75) * CFrame.Angles(0, -a, 0), 0.5, 0.25, 0.5, if k % 2 == 0 then "pavement" else "rock", nil, "Capstone")
	end
	cyl(m, f, 0, 0.8, 0, 1.0, 0.25, "night", "Shaft")
	for _, z in { -0.625, 0.625 } do
		box(m, f, 0, 1.125, z, 0.25, 2.25, 0.25, "wood_dark", "Post")
	end
	-- the windlass across the shaft, the rope wound in the middle, a crank at the front
	for k, c in { "wood", "sand_dark", "wood" } do
		Parts.logZ(m, f, 0, 1.85, -0.5 + (k - 1) * 0.5, 0.5, 0.5, c, "Windlass")
	end
	box(m, f, 0, 1.7, 0.875, 0.25, 0.5, 0.25, "wood_dark", "Crank")
	box(m, f, 0.15, 1.5, 0.875, 0.25, 0.25, 0.25, "wood", "Handle")
	box(m, f, 0, 1.6, 0, 0.25, 0.25, 0.25, "sand_dark", "Rope")
	stack(m, f, 0, 1.05, 0, { { d = 0.5, h = 0.25, c = "steel_dark" }, { d = 0.5, h = 0.25, c = "wood" } }, "Bucket")
	-- a steep thatched roof, its gable to the front
	Parts.wedge(m, f, -0.375, 2.625, 0, 1.75, 0.75, 0.75, "straw", PI / 2, "Roof")
	Parts.wedge(m, f, 0.375, 2.625, 0, 1.75, 0.75, 0.75, "straw", -PI / 2, "Roof")
	box(m, f, 0, 3.0, 0, 0.25, 0.25, 1.75, "sand_dark", "Ridge")
end

------------------------------------------------------------------ the harbour

-- Mooring Post (1 x 1): a stout dark post on two planks of the quay, an iron cap, rope wound round it twice and its
-- end coiled on the boards.
M.bollard = function(m, f)
	box(m, f, -0.25, 0, 0, 0.5, 0.25, 1.0, "wood", "Plank")
	box(m, f, 0.25, 0, 0, 0.5, 0.25, 1.0, "wood_dark", "Plank")
	cyl(m, f, 0, 0.625, -0.05, 0.5, 1.0, "wood_dark", "Post")
	cyl(m, f, 0, 1.25, -0.05, 0.75, 0.25, "slate", "Cap")
	cyl(m, f, 0, 0.55, -0.05, 0.75, 0.25, "sand_dark", "Rope")
	cyl(m, f, 0, 0.8, -0.05, 0.75, 0.25, "straw", "Rope")
	strut(m, f, Vector3.new(0.25, 0.45, 0.15), Vector3.new(0.25, 0.2, 0.3), 0.25, "sand_dark", "Rope")
	cyl(m, f, 0.2, 0.18, 0.25, 0.5, 0.25, "sand_dark", "Coil")
end

-- Buoy (1 x 1): a float in red and white bands narrowing to a little mast with a lamp, set on a wooden cradle.
M.buoy = function(m, f)
	for _, x in { -0.25, 0.25 } do
		box(m, f, x, 0.125, 0, 0.25, 0.25, 0.75, "wood_dark", "Cradle")
	end
	local y = stack(m, f, 0, 0.15, 0, {
		{ d = 1.0, h = 0.25, c = "berry_red" },
		{ d = 1.0, h = 0.25, c = "white" },
		{ d = 1.0, h = 0.25, c = "berry_red" },
		{ d = 0.75, h = 0.25, c = "white" },
		{ d = 0.5, h = 0.25, c = "berry_red" },
	}, "Buoy")
	box(m, f, 0, y + 0.25, 0, 0.25, 0.5, 0.25, "slate", "Mast")
	Parts.glow(m, f, 0, y + 0.625, 0, 0.25, 0.25, 0.25, "yellow", "Lamp")
	box(m, f, 0, y + 0.875, 0, 0.5, 0.25, 0.5, "slate", "Cap")
end

-- A crate s on a side standing at (x, y0, z), turned yaw: a dark frame round pale boards on the faces that show,
-- a stamp on its front, a brace across its right side when asked.
local function crate(m: Instance, f: CFrame, x: number, y0: number, z: number, s: number, yaw: number, stamp: string?, brace: boolean?)
	local c = CFrame.new(x, y0 + s / 2, z) * CFrame.Angles(0, yaw, 0)
	local p = s - 0.25
	put(m, f, c, s, s, s, "wood_dark", nil, "Crate")
	put(m, f, c * CFrame.new(0, 0, s / 2 - 0.1), p, p, 0.25, "sand_dark", nil, "Board")
	put(m, f, c * CFrame.new(s / 2 - 0.1, 0, 0), 0.25, p, p, "sand_dark", nil, "Board")
	put(m, f, c * CFrame.new(0, s / 2 - 0.1, 0), p, 0.25, p, "sand_dark", nil, "Board")
	if stamp then
		put(m, f, c * CFrame.new(0, 0, s / 2 - 0.04), 0.25, 0.25, 0.25, stamp, nil, "Stamp")
	end
	if brace then
		put(m, f, c * CFrame.new(s / 2 - 0.06, 0, 0) * CFrame.Angles(PI / 4, 0, 0), 0.25, p * math.sqrt(2), 0.25, "wood_dark", nil, "Brace")
	end
end

-- Crate Stack (2 x 2): a big crate with a smaller one on top of it, another beside, a little one in front, stamped
-- red and blue.
M.crates = function(m, f)
	crate(m, f, -0.45, 0, -0.4, 1.0, 0, "berry_red", true)
	crate(m, f, 0.5, 0, -0.5, 0.75, 0, "blue", true)
	crate(m, f, -0.42, 1.0, -0.45, 0.75, 0.25, "blue")
	crate(m, f, 0.45, 0, 0.5, 0.5, -0.3)
	cyl(m, f, -0.45, 0.06, 0.55, 0.75, 0.25, "sand_dark", "Coil")
end

-- A lobster pot standing on y0 at (x, z): a round wicker pot in bands, narrowing to the dark mouth on its top.
local function creel(m: Instance, f: CFrame, x: number, y0: number, z: number)
	local y = stack(m, f, x, y0, z, { { d = 0.75, h = 0.25, c = "wood" }, { d = 0.75, h = 0.25, c = "straw" }, { d = 0.5, h = 0.25, c = "wood" } }, "Pot")
	cyl(m, f, x, y - 0.1, z, 0.25, 0.25, "black", "Mouth")
end

-- Lobster Pots (2 x 2): three wicker pots in a pile, a red and white float on a rope, a red lobster that got away.
M.lobsterpots = function(m, f)
	creel(m, f, -0.5, 0, 0.3)
	creel(m, f, 0.35, 0, -0.5)
	creel(m, f, -0.1, 0.6, -0.12)
	stack(m, f, -0.55, 0, -0.6, { { d = 0.5, h = 0.25, c = "berry_red" }, { d = 0.5, h = 0.25, c = "white" } }, "Float")
	strut(m, f, Vector3.new(-0.5, 0.35, -0.4), Vector3.new(-0.5, 0.2, 0.0), 0.25, "sand_dark", "Rope")
	box(m, f, 0.45, 0.125, 0.45, 0.25, 0.25, 0.5, "berry_red", "Lobster")
	box(m, f, 0.45, 0.1, 0.2, 0.25, 0.25, 0.25, "berry_red", "Tail")
	ball(m, f, 0.33, 0.15, 0.78, 0.25, "berry_red", "Claw")
	ball(m, f, 0.57, 0.15, 0.78, 0.25, "berry_red", "Claw")
end

-- A net hung in a bay from x0 to x1: three cords down, three across, the bottom one sagging, floats along the top.
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
		strut(m, f, Vector3.new(mid + s * half, 0.72, z), Vector3.new(mid, 0.5, z), 0.25, color, "Net")
	end
	for _, s in { -0.25, 0.25 } do
		ball(m, f, mid + s * half * 2, 1.75, z + 0.1, 0.25, "orange", "Float")
	end
end

-- Net Rack (3 x 1): three weathered posts and a rail, a rope-brown net and a teal one hung out to dry, orange
-- floats along their tops.
M.netrack = function(m, f)
	for _, x in { -1.375, 0, 1.375 } do
		box(m, f, x, 1.0, -0.2, 0.25, 2.0, 0.25, "wood_dark", "Post")
		box(m, f, x, 0.125, 0, 0.25, 0.25, 0.75, "wood_dark", "Foot")
	end
	box(m, f, 0, 2.0, -0.05, 3.0, 0.25, 0.25, "wood", "Rail")
	net(m, f, -1.2, -0.2, 0.12, "sand_dark")
	net(m, f, 0.2, 1.2, 0.12, "teal")
end

-- Anchor (2 x 1): an old slate-iron anchor stood on its crown in a bed of stones, turned a little toward the view:
-- the shank, a wooden stock across it, the eye at the top, the arms curving up to their flukes, rust here and there,
-- a rope from the eye down to a coil on the ground.
M.anchor = function(m, f)
	box(m, f, 0, 0.06, 0, 1.25, 0.25, 0.75, "rock", "Bed")
	ball(m, f, -0.55, 0.15, 0.22, 0.5, "rock_dark", "Stone")
	ball(m, f, 0.4, 0.12, -0.25, 0.5, "rock_dark", "Stone")
	local g = f * CFrame.Angles(0, PI / 6, 0)
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
	ring(m, g, CFrame.new(0, 2.0, 0), "slate", "slate", "Eye")
	box(m, g, 0.12, 0.9, 0.06, 0.25, 0.25, 0.25, "clay", "Rust")
	box(m, g, -0.45, 0.42, 0.06, 0.25, 0.25, 0.25, "clay", "Rust")
	-- the rope, behind
	strut(m, g, Vector3.new(0.3, 1.95, -0.2), Vector3.new(0.7, 0.25, -0.15), 0.25, "sand_dark", "Rope")
	cyl(m, g, 0.75, 0.12, 0.15, 0.5, 0.25, "sand_dark", "Coil")
end

-- Ship's Wheel (1 x 1): an old helm on a round wooden post, turned to face the view: a ring, eight spokes running
-- out past it to their handles, a brass hub.
M.shipwheel = function(m, f)
	local g = f * CFrame.Angles(0, PI / 4, 0)
	cyl(m, g, 0, 0, -0.15, 0.75, 0.25, "wood_dark", "Base")
	cyl(m, g, 0, 0.6, -0.3, 0.5, 1.0, "wood", "Post")
	cyl(m, g, 0, 1.15, -0.3, 0.5, 0.25, "gold", "Cap")
	Parts.logZ(m, g, 0, 1.2, -0.15, 0.25, 0.25, "steel_dark", "Axle")
	local c = CFrame.new(0, 1.2, 0)
	for k = 0, 3 do
		put(m, g, c * CFrame.Angles(0, 0, k * PI / 4), 1.25, 0.25, 0.25, "wood_dark", nil, "Spoke")
	end
	for k = 0, 7 do
		local a = k * PI / 4
		put(m, g, c * CFrame.new(math.cos(a + PI / 8) * 0.36, math.sin(a + PI / 8) * 0.36, 0.04) * CFrame.Angles(0, 0, a + PI / 8 + PI / 2), 0.5, 0.25, 0.25, "wood", nil, "Rim")
		put(m, g, c * CFrame.new(math.cos(a) * 0.6, math.sin(a) * 0.6, 0.02), 0.25, 0.25, 0.25, "wood", nil, "Handle")
	end
	put(m, g, c * CFrame.new(0, 0, 0.1) * CFrame.Angles(0, PI / 2, 0), 0.25, 0.25, 0.25, "gold", "Cylinder", "Hub")
end

------------------------------------------------------------------ the town

-- Bin (1 x 1): a teal painted can with slate bands and handles, open at the top on a white bag, a gold crest on its
-- side.
M.bin = function(m, f)
	local y = stack(m, f, 0, 0, 0, { { d = 0.75, h = 0.25, c = "slate" }, { d = 0.75, h = 0.5, c = "teal" }, { d = 0.75, h = 0.25, c = "slate" } }, "Bin")
	cyl(m, f, 0, y + 0.1, 0, 0.75, 0.25, "white", "Bag")
	cyl(m, f, 0, y + 0.12, 0, 0.5, 0.25, "black", "Inside")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.33, 0.8, -s * 0.33, 0.25, 0.25, 0.25, "slate", "Handle")
	end
	put(m, f, CFrame.new(0.25, 0.5, 0.25) * CFrame.Angles(0, PI / 4, 0), 0.25, 0.25, 0.25, "gold", nil, "Crest")
end

-- An arrow board on the signpost at height y pointing `yaw` (0 = +X): a board and a pointed end.
local function arrow(m: Instance, f: CFrame, y: number, yaw: number, color: string)
	local c = CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0)
	put(m, f, c * CFrame.new(0, 0, 0.0), 0.5, 0.25, 0.25, color, nil, "Sign")
	put(m, f, c * CFrame.new(0.375, 0.125, 0) * CFrame.Angles(0, -PI / 2, 0), 0.25, 0.25, 0.25, color, "Wedge", "Point")
	put(m, f, c * CFrame.new(0.375, -0.125, 0) * CFrame.Angles(0, -PI / 2, 0) * CFrame.Angles(0, 0, PI), 0.25, 0.25, 0.25, color, "Wedge", "Point")
end

-- Signpost (1 x 1): a dark post in a stone, four painted arrows pointing four ways, a gold knob on top.
M.signpost = function(m, f)
	cyl(m, f, 0, 0, 0, 0.5, 0.25, "rock", "Stone")
	box(m, f, 0, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
	ball(m, f, 0, 2.1, 0, 0.25, "gold", "Knob")
	arrow(m, f, 1.75, math.rad(45), "cream")
	arrow(m, f, 1.45, math.rad(160), "teal")
	arrow(m, f, 1.15, math.rad(-20), "berry_red")
	arrow(m, f, 0.85, math.rad(-135), "yellow")
end

-- Planter Box (2 x 1): a teal box with cream corner posts on slate feet, red, white and yellow flowers in it and ivy
-- trailing over the front.
M.planter = function(m, f)
	box(m, f, 0, 0.375, 0, 1.75, 0.5, 0.75, "teal", "Box")
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
	box(m, f, -0.35, 0.45, 0.36, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	box(m, f, 0.5, 0.5, 0.36, 0.25, 0.25, 0.25, "leaf", "Ivy")
end

-- Post Box (1 x 1): a red pillar on a slate foot with a domed cap, its slot and a white plate turned to the view.
M.postbox = function(m, f)
	cyl(m, f, 0, 0.125, 0, 0.75, 0.25, "slate", "Foot")
	cyl(m, f, 0, 0.75, 0, 0.75, 1.0, "berry_red", "Pillar")
	cyl(m, f, 0, 1.375, 0, 1.0, 0.25, "berry_red", "Cap")
	ball(m, f, 0, 1.5, 0, 0.75, "berry_red", "Dome")
	ball(m, f, 0, 1.9, 0, 0.25, "gold", "Knob")
	local r = math.sqrt(0.5)
	Parts.turned(m, f, 0.3 * r, 1.05, 0.3 * r, 0.5, 0.25, 0.25, PI / 4, "black", "Slot")
	Parts.turned(m, f, 0.3 * r, 0.7, 0.3 * r, 0.25, 0.25, 0.25, PI / 4, "white", "Plate")
end

-- Notice Board (2 x 1): a cork board in a dark frame on two posts under a little slate roof, notices pinned all
-- over it, and somebody's lost hat hung on a post.
M.noticeboard = function(m, f)
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0, 1.25, 0, 1.5, 1.0, 0.25, "sand_dark", "Cork")
	box(m, f, 0, 1.875, 0.03, 1.75, 0.25, 0.25, "wood_dark", "Frame")
	box(m, f, 0, 0.625, 0.03, 1.75, 0.25, 0.25, "wood_dark", "Frame")
	Parts.wedge(m, f, 0, 2.25, -0.25, 2.0, 0.5, 0.5, "slate", 0, "Roof")
	Parts.wedge(m, f, 0, 2.25, 0.25, 2.0, 0.5, 0.5, "slate", PI, "Roof")
	local colours = { "paper", "yellow", "pink", "blue", "white", "cream" }
	for k, n in { { -0.45, 1.45, 0.5, 0.5 }, { 0.05, 1.5, 0.25, 0.5 }, { 0.45, 1.55, 0.5, 0.25 }, { 0.45, 1.05, 0.5, 0.5 }, { -0.15, 1.0, 0.25, 0.25 }, { -0.55, 0.95, 0.25, 0.25 } } do
		box(m, f, n[1], n[2], 0.05, n[3], n[4], 0.25, colours[k], "Notice")
	end
	-- the hat, hung on a nail on the left post
	Parts.logZ(m, f, -0.75, 1.0, 0.2, 0.25, 0.5, "berry_red", "Hat")
	Parts.logZ(m, f, -0.75, 1.0, 0.3, 0.25, 0.25, "berry_red", "Hat")
end

-- Newsstand (2 x 2): a little teal kiosk on a slate step: a window full of magazines under a striped awning, a
-- counter of papers, postcards on its side, a sign on the roof, a bundle of papers on the ground.
M.newsstand = function(m, f)
	box(m, f, 0, 0.125, -0.3, 1.75, 0.25, 1.25, "slate", "Step")
	box(m, f, 0, 1.125, -0.3, 1.75, 1.75, 1.25, "teal", "Kiosk")
	box(m, f, 0, 2.125, -0.15, 2.0, 0.25, 1.5, "slate", "Roof")
	-- the window and its magazines
	box(m, f, 0, 1.25, 0.25, 1.25, 0.5, 0.25, "night", "Window")
	for k, c in { "pink", "yellow", "blue", "white" } do
		box(m, f, -0.45 + (k - 1) * 0.3, 1.25, 0.3, 0.25, 0.25, 0.25, c, "Magazine")
	end
	-- the awning: red and cream stripes sloping out over the window
	for k = 0, 3 do
		Parts.wedge(m, f, -0.75 + k * 0.5, 1.75, 0.575, 0.5, 0.5, 0.5, if k % 2 == 0 then "berry_red" else "cream", PI, "Awning")
	end
	-- the counter and its papers
	box(m, f, 0, 0.875, 0.45, 1.75, 0.25, 0.5, "wood", "Counter")
	box(m, f, 0, 0.5, 0.3, 1.5, 0.5, 0.25, "cream", "Front")
	for _, x in { -0.45, 0.45 } do
		box(m, f, x, 0.5, 0.36, 0.5, 0.25, 0.25, "paper", "Paper")
	end
	box(m, f, -0.45, 1.125, 0.5, 0.5, 0.25, 0.25, "paper", "Papers")
	box(m, f, 0.35, 1.125, 0.5, 0.5, 0.25, 0.25, "white", "Papers")
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

-- Tiki Mask (1 x 1): a carved board of a face on a dark post among ferns, turned to look at the view: a heavy brow,
-- white eyes, a long nose, a grin of white teeth, teal and red paint on the cheeks, a crest of three feathers.
M.tikimask = function(m, f)
	ball(m, f, -0.3, 0.2, 0.25, 0.5, "leaf", "Fern")
	ball(m, f, 0.3, 0.15, 0.3, 0.5, "leaf_dark", "Fern")
	local g = f * CFrame.Angles(0, PI / 4, 0)
	box(m, g, 0, 0.375, -0.05, 0.5, 0.75, 0.5, "wood_dark", "Post")
	box(m, g, 0, 1.375, 0, 1.0, 1.25, 0.25, "wood", "Mask")
	box(m, g, 0, 1.875, 0.1, 1.0, 0.25, 0.25, "wood_dark", "Brow")
	for _, s in { -1, 1 } do
		box(m, g, s * 0.25, 1.625, 0.06, 0.25, 0.25, 0.25, "white", "Eye")
		box(m, g, s * 0.375, 1.375, 0.06, 0.25, 0.25, 0.25, if s < 0 then "teal" else "berry_red", "Paint")
	end
	box(m, g, 0, 1.375, 0.15, 0.25, 0.5, 0.25, "clay", "Nose")
	box(m, g, 0, 1.0, 0.06, 0.75, 0.5, 0.25, "black", "Mouth")
	box(m, g, 0, 1.0, 0.1, 0.5, 0.25, 0.25, "white", "Teeth")
	for k, c in { "teal", "yellow", "berry_red" } do
		local a = (k - 2) * 0.45
		put(m, g, CFrame.new(math.sin(a) * 0.3, 2.15 + math.cos(a) * 0.1, -0.05) * CFrame.Angles(0, 0, -a), 0.25, 0.5, 0.25, c, nil, "Feather")
	end
end

-- Parrot Perch (1 x 1): a carved and painted parrot, red with blue and yellow wings and a long blue tail, on a
-- branch set on a post in a stump, a leaf at one end and a cup of seed at the other.
M.parrotperch = function(m, f)
	cyl(m, f, 0, 0.125, 0, 0.75, 0.25, "wood_dark", "Stump")
	box(m, f, 0, 0.75, -0.1, 0.25, 1.25, 0.25, "wood", "Post")
	Parts.log(m, f, 0, 1.375, -0.1, 1.0, 0.25, "wood_dark", "Branch")
	ball(m, f, 0.38, 1.5, -0.1, 0.25, "leaf", "Leaf")
	cyl(m, f, -0.38, 1.6, -0.1, 0.25, 0.25, "clay", "Cup")
	-- the parrot
	box(m, f, -0.05, 1.55, 0.02, 0.25, 0.25, 0.25, "black", "Feet")
	box(m, f, -0.05, 1.875, 0, 0.5, 0.5, 0.5, "berry_red", "Body")
	box(m, f, -0.05, 2.25, 0.05, 0.5, 0.5, 0.5, "berry_red", "Head")
	box(m, f, -0.05, 2.25, 0.25, 0.25, 0.25, 0.25, "white", "Face")
	Parts.wedge(m, f, -0.05, 2.1, 0.38, 0.25, 0.25, 0.25, "yellow", PI, "Beak")
	for _, s in { -1, 1 } do
		box(m, f, -0.05 + s * 0.3, 1.85, -0.02, 0.25, 0.25, 0.5, "blue", "Wing")
		box(m, f, -0.05 + s * 0.3, 2.06, 0.0, 0.25, 0.25, 0.5, "yellow", "Wing")
	end
	put(m, f, CFrame.new(-0.05, 1.45, -0.35) * CFrame.Angles(math.rad(20), 0, 0), 0.25, 0.75, 0.25, "blue", nil, "Tail")
end

-- Vine Arch (3 x 1): two carved posts on stone feet, a rough log across their tops, all of it lost in creepers:
-- leafy clumps over the log and up the posts, vines hanging down the middle, a few jungle flowers.
M.vinearch = function(m, f)
	for _, x in { -1.125, 1.125 } do
		box(m, f, x, 0.125, 0, 0.75, 0.25, 0.75, "rock", "Foot")
		box(m, f, x, 1.25, 0, 0.5, 2.25, 0.5, "wood_dark", "Post")
		box(m, f, x, 2.25, 0, 0.75, 0.25, 0.75, "wood", "Capital")
		box(m, f, x, 0.9, 0, 0.75, 0.25, 0.75, "wood", "Band")
	end
	Parts.log(m, f, 0, 2.6, 0, 3.0, 0.5, "wood", "Log")
	for k, c in { { -1.0, 2.85, 0.05, 0.75 }, { -0.35, 2.9, -0.05, 0.75 }, { 0.35, 2.85, 0.05, 0.75 }, { 1.05, 2.9, 0.0, 0.75 }, { -1.2, 1.6, 0.22, 0.5 }, { -1.05, 0.55, 0.22, 0.5 }, { 1.2, 1.9, 0.22, 0.5 }, { 1.05, 1.2, 0.25, 0.5 }, { 1.25, 0.4, 0.15, 0.5 } } do
		ball(m, f, c[1], c[2], c[3], c[4], if k % 2 == 0 then "leaf_dark" else "leaf", "Creeper")
	end
	for _, v in { { -0.7, 0.75 }, { -0.3, 1.25 }, { 0.15, 0.5 }, { 0.55, 1.0 }, { 0.85, 0.5 } } do
		local len = v[2]
		box(m, f, v[1], 2.4 - len / 2, 0.1, 0.25, len, 0.25, "leaf_dark", "Vine")
		box(m, f, v[1] + 0.1, 2.4 - len - 0.05, 0.12, 0.25, 0.25, 0.25, "leaf", "Vine")
	end
	local flowers = { "orange", "pink", "purple", "orange" }
	for k, b in { { -0.85, 3.05, 0.3 }, { 0.25, 3.1, 0.3 }, { -1.3, 1.75, 0.3 }, { 1.3, 2.05, 0.3 } } do
		box(m, f, b[1], b[2], b[3], 0.25, 0.25, 0.25, flowers[k], "Flower")
	end
end

-- Mossy Idol (2 x 2): a big stone head sunk to its lips in the earth and turned to look at the view: moss on its
-- crown and dripping down one side, a carved headband with a gem, a heavy brow over eyes of glowing teal stone, a
-- broad nose, broad ears, a crack, vines hanging over it, ferns at its sides, fruit and a candle left at its foot.
M.idol = function(m, f)
	cyl(m, f, 0, 0, 0, 2.0, 0.25, "moss", "Mound")
	local g = f * CFrame.Angles(0, PI / 4, 0)
	box(m, g, 0, 0.825, 0, 1.5, 1.75, 1.25, "rock", "Head")
	Parts.log(m, g, 0, 1.7, 0, 1.5, 1.25, "rock", "Crown")
	box(m, g, 0, 2.25, -0.05, 1.0, 0.25, 0.75, "moss", "Moss")
	box(m, g, -0.3, 2.15, 0.4, 0.5, 0.25, 0.5, "moss", "Moss")
	box(m, g, -0.65, 1.5, 0.6, 0.25, 0.75, 0.25, "moss", "Moss")
	-- the face
	box(m, g, 0, 1.85, 0.65, 1.5, 0.25, 0.25, "clay", "Band")
	Parts.glow(m, g, 0, 1.85, 0.73, 0.25, 0.25, 0.25, "teal", "Gem")
	box(m, g, 0, 1.58, 0.7, 1.5, 0.25, 0.25, "rock_dark", "Brow")
	for _, x in { -0.4, 0.4 } do
		box(m, g, x, 1.32, 0.65, 0.5, 0.25, 0.25, "rock_dark", "Socket")
		Parts.glow(m, g, x, 1.32, 0.71, 0.25, 0.25, 0.25, "teal", "Eye")
	end
	box(m, g, 0, 1.02, 0.75, 0.5, 0.5, 0.25, "rock", "Nose")
	box(m, g, 0, 0.5, 0.67, 0.75, 0.25, 0.25, "rock_dark", "Lips")
	for _, x in { -0.875, 0.875 } do
		box(m, g, x, 1.2, 0, 0.25, 0.75, 0.5, "rock_dark", "Ear")
	end
	put(m, g, CFrame.new(0.55, 0.8, 0.66) * CFrame.Angles(0, 0, math.rad(25)), 0.25, 0.5, 0.25, "rock_dark", nil, "Crack")
	-- vines hanging over the crown
	for _, v in { { -0.45, 0.5 }, { 0.62, 0.75 } } do
		box(m, g, v[1], 2.2 - v[2] / 2, 0.66, 0.25, v[2], 0.25, "leaf_dark", "Vine")
		box(m, g, v[1], 2.2 - v[2], 0.7, 0.25, 0.25, 0.25, "leaf", "Vine")
	end
	-- ferns, the offering
	ball(m, g, -0.85, 0.25, 0.2, 0.5, "leaf", "Fern")
	ball(m, g, 0.85, 0.3, 0.2, 0.5, "leaf_dark", "Fern")
	ball(m, g, 0.35, 0.15, 0.85, 0.25, "yellow", "Fruit")
	ball(m, g, 0.55, 0.15, 0.7, 0.25, "berry_red", "Fruit")
	box(m, g, -0.55, 0.2, 0.75, 0.25, 0.25, 0.25, "cream", "Candle")
	Parts.glow(m, g, -0.55, 0.45, 0.75, 0.25, 0.25, 0.25, "orange", "Flame")
end

return M
