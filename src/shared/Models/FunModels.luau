--!strict
-- The things to do, seats, lights and the grand pieces (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- Seats, lights and play things match the old Bench, Hammock, Lamp Post and Tiki Torch in size and detail; the four
-- new grand pieces stand taller than the old ones (up to about 12 studs), as the island's biggest rewards.
local Blocks = require(script.Parent.Blocks)
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

local box, glow, ball, cyl, at = Parts.box, Parts.glow, Parts.ball, Parts.cyl, Parts.at
local V = Vector3.new
local R = math.rad
local PI = math.pi

------------------------------------------------------------------ helpers
-- A cylinder along the X axis of `cf` (a frame in f): a tilted tube, a lid, a wheel.
local function rod(m: Instance, f: CFrame, cf: CFrame, len: number, dia: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(m, { size = V(len, dia, dia), cf = f * cf, color = color, shape = "Cylinder", name = name or "Rod", neon = neon, collide = false })
end

-- A wheel or a disc facing +Z (its axle along Z) centred at (x, y, z).
local function disc(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, thick: number, color: string, name: string?, neon: boolean?): BasePart
	return rod(m, f, CFrame.new(x, y, z) * CFrame.Angles(0, PI / 2, 0), thick, dia, color, name, neon)
end

-- A square bar of width w from point a to point b (both in f): a leg on a slant, a rope, a wire.
local function beam(m: Instance, f: CFrame, a: Vector3, b: Vector3, w: number, color: string, name: string?, neon: boolean?): BasePart
	local d = b - a
	local len = d.Magnitude
	local up = if math.abs(d.Y) > 0.99 * len then V(0, 0, 1) else V(0, 1, 0)
	return at(m, f, CFrame.lookAt((a + b) / 2, b, up), w, w, len, color, name, neon)
end

-- A rope or wire sagging from a to b (level ends) by `sag` at its middle, in `n` straight pieces; returns the
-- height of the line at x (for things hung from it).
local function sagLine(m: Instance, f: CFrame, x0: number, x1: number, y: number, z: number, sag: number, n: number, color: string, name: string?): (number) -> number
	local function yAt(x: number): number
		local t = (x - x0) / (x1 - x0) * 2 - 1
		return y - sag * (1 - t * t)
	end
	for k = 0, n - 1 do
		local xa = x0 + (x1 - x0) * k / n
		local xb = x0 + (x1 - x0) * (k + 1) / n
		beam(m, f, V(xa, yAt(xa), z), V(xb, yAt(xb), z), 0.25, color, name or "Line")
	end
	return yAt
end

-- Round water the filter animates (a basin's, a pond's), its top at y + 0.125.
local function pool(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?): BasePart
	local p = cyl(m, f, x, y, z, dia, 0.25, color or "water", "Water")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- A jet or a fall of water: an upright box the filter animates.
local function jet(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string?): BasePart
	local p = box(m, f, x, y, z, w, h, d, color or "foam", "Jet")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- A crystal: a square prism w x h x w standing on `cf` (its foot, any tilt) that narrows to its point in steps, a
-- quarter stud at a time (the last a longer needle on a thin one), the way a gem's point reads in pixels. The
-- steps are square like the prism, so the point looks the same from every side the piece turns to.
local function crystal(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, color: string, neon: boolean?)
	at(m, f, cf * CFrame.new(0, h / 2, 0), w, h, w, color, "Crystal", neon)
	local y, s = h, w - 0.25
	while s >= 0.25 do
		local tall = if s < 0.5 and w <= 0.5 then 0.75 else 0.5
		at(m, f, cf * CFrame.new(0, y + tall / 2 - 0.05, 0), s, tall, s, color, "Point", neon)
		y += 0.375
		s -= 0.25
	end
end

-- A glint: a little four-point star of light, a sparkle in the air, facing the view.
local function glint(m: Instance, f: CFrame, x: number, y: number, z: number, color: string?)
	local c = color or "white"
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, PI / 4, 0)
	at(m, f, cf, 0.25, 0.75, 0.25, c, "Glint", true)
	at(m, f, cf, 0.75, 0.25, 0.25, c, "Glint", true)
end

local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

------------------------------------------------------------------ grand pieces
-- Golden Driftling (3 x 3): the bun driftling (DriftModels' long-eared one with the sprout) cast in gold, bigger
-- than life, on a marble pedestal with gold trims: dark gem eyes, a plaque, coins tossed on the steps, flowers.
M.goldstatue = function(m, f)
	box(m, f, 0, 0.12, 0, 3, 0.25, 3, "rock", "Step")
	box(m, f, 0, 0.37, 0, 2.75, 0.25, 2.75, "pavement", "Step")
	box(m, f, 0, 0.62, 0, 2.5, 0.25, 2.5, "cream", "Base")
	box(m, f, 0, 1.5, 0, 2.25, 1.5, 2.25, "white", "Pedestal")
	for _, c in CORNERS do
		box(m, f, c[1] * 1.0, 1.5, c[2] * 1.0, 0.5, 1.5, 0.5, "cream", "Pilaster")
	end
	box(m, f, 0, 2.12, 0, 2.5, 0.25, 2.5, "gold", "Band")
	box(m, f, 0, 2.37, 0, 2.5, 0.25, 2.5, "white", "Cornice")
	box(m, f, 0, 1.5, 1.15, 1.25, 0.5, 0.25, "gold", "Plaque")
	box(m, f, 0, 1.5, 1.2, 0.75, 0.25, 0.25, "orange", "Letters")
	box(m, f, 1.15, 1.5, 0, 0.25, 0.5, 0.5, "gold", "Medallion")
	-- the driftling, standing on the cornice (y0)
	local y0 = 2.5
	ball(m, f, 0, y0 + 1.3, -0.15, 2.25, "gold", "Body")
	ball(m, f, 0, y0 + 1.15, 0.45, 1.5, "yellow", "Belly")
	ball(m, f, 0, y0 + 1.2, -1.1, 0.75, "yellow", "Tail")
	ball(m, f, 0, y0 + 3.05, 0.3, 2.0, "gold", "Head")
	ball(m, f, 0, y0 + 2.75, 1.05, 0.75, "yellow", "Muzzle")
	box(m, f, 0, y0 + 3.0, 1.3, 0.5, 0.25, 0.25, "orange", "Nose")
	for _, s in { -1, 1 } do
		ball(m, f, s * 0.75, y0 + 0.65, -0.2, 1.25, "gold", "Thigh")
		box(m, f, s * 0.65, y0 + 0.12, 0.6, 0.75, 0.25, 1.0, "gold", "Foot")
		box(m, f, s * 0.5, y0 + 1.75, 0.95, 0.5, 0.5, 0.5, "gold", "Paw")
		box(m, f, s * 0.45, y0 + 3.3, 1.15, 0.5, 0.5, 0.25, "night", "Eye")
		box(m, f, s * 0.45 - 0.12, y0 + 3.42, 1.2, 0.25, 0.25, 0.25, "white", "Shine")
		-- long ears leaning out a little, orange inside
		local ear = CFrame.new(s * 0.5, y0 + 4.55, 0.15) * CFrame.Angles(0, 0, -s * R(10))
		at(m, f, ear, 0.5, 1.75, 0.25, "gold", "Ear")
		at(m, f, ear * CFrame.new(0, -0.1, 0.1), 0.25, 1.25, 0.25, "orange", "EarIn")
	end
	-- the sprout on its head
	box(m, f, 0, y0 + 4.25, 0.25, 0.25, 0.5, 0.25, "gold", "Sprout")
	at(m, f, CFrame.new(0.22, y0 + 4.5, 0.25) * CFrame.Angles(0, 0, R(25)), 0.5, 0.25, 0.25, "gold", "SproutLeaf")
	at(m, f, CFrame.new(-0.22, y0 + 4.45, 0.25) * CFrame.Angles(0, 0, R(-25)), 0.5, 0.25, 0.25, "gold", "SproutLeaf")
	-- coins tossed for luck, flowers left at its foot
	for _, c in { { -0.9, 1.25 }, { 0.6, 1.3 }, { 1.3, 0.4 }, { -1.3, -0.5 } } do
		box(m, f, c[1], 0.52, c[2], 0.25, 0.25, 0.25, "gold", "Coin")
	end
	for k, c in { { -0.6, 1.3 }, { -0.35, 1.32 }, { 0.3, 1.3 } } do
		box(m, f, c[1], 0.5, c[2], 0.25, 0.25, 0.25, if k == 2 then "white" else "pink", "Flower")
	end
end

-- Sky Bell Tower (3 x 3): a tall tower of sky-blue stone with white corner stones and bands, a door with lanterns,
-- windows up every face, an open belfry on slim pillars with a big gold bell, a stepped white spire on a gold eave,
-- a gold finial.
M.bellspire = function(m, f)
	box(m, f, 0, 0.12, 0, 3, 0.25, 3, "rock", "Step")
	box(m, f, 0, 0.37, 0, 2.75, 0.25, 2.75, "pavement", "Step")
	box(m, f, 0, 3.25, 0, 2.0, 5.5, 2.0, "blue", "Tower")
	for _, c in CORNERS do
		box(m, f, c[1] * 0.95, 3.25, c[2] * 0.95, 0.25, 5.5, 0.25, "white", "Quoin")
	end
	box(m, f, 0, 0.75, 0, 2.25, 0.5, 2.25, "white", "Band")
	for _, y in { 2.5, 4.25 } do
		box(m, f, 0, y, 0, 2.25, 0.25, 2.25, "white", "Band")
	end
	-- each face: a small window low down (not over the door), a tall one above it, a pair of slits up top, each with a
	-- white sill and head
	for k = 0, 3 do
		local g = f * CFrame.Angles(0, k * PI / 2, 0)
		if k ~= 0 then
			box(m, g, 0, 1.6, 1.0, 0.5, 0.75, 0.25, "night", "Glass")
			box(m, g, 0, 1.15, 1.06, 0.75, 0.25, 0.25, "white", "Sill")
		end
		box(m, g, 0, 3.4, 1.0, 0.5, 1.0, 0.25, "night", "Glass")
		box(m, g, 0, 2.82, 1.06, 0.75, 0.25, 0.25, "white", "Sill")
		box(m, g, 0, 3.98, 1.03, 0.75, 0.25, 0.25, "white", "Head")
		for _, x in { -0.2, 0.2 } do
			box(m, g, x, 5.2, 1.0, 0.25, 0.75, 0.25, "night", "Slit")
		end
		box(m, g, 0, 4.75, 1.06, 0.75, 0.25, 0.25, "white", "Sill")
	end
	-- the door, its arch and two lanterns
	for _, s in { -1, 1 } do
		box(m, f, s * 0.5, 1.25, 1.06, 0.25, 1.5, 0.25, "white", "Jamb")
		box(m, f, s * 0.25, 1.75, 1.03, 0.25, 0.25, 0.25, "white", "Arch")
		box(m, f, s * 0.75, 1.75, 1.25, 0.25, 0.5, 0.25, "yellow", "Lantern", true)
		box(m, f, s * 0.75, 2.05, 1.25, 0.25, 0.25, 0.25, "steel_dark", "LanternCap")
	end
	box(m, f, 0, 2.06, 1.06, 1.25, 0.25, 0.25, "white", "Lintel")
	box(m, f, 0, 1.12, 1.0, 0.75, 1.25, 0.25, "wood_dark", "Door")
	box(m, f, 0.2, 1.1, 1.1, 0.25, 0.25, 0.25, "gold", "Knob")
	-- the belfry: a ledge, slim corner pillars, stepped arches, a lintel
	box(m, f, 0, 6.12, 0, 2.5, 0.25, 2.5, "white", "Ledge")
	for _, c in CORNERS do
		box(m, f, c[1] * 1.0, 7.25, c[2] * 1.0, 0.25, 2.0, 0.25, "white", "Pillar")
	end
	for k = 0, 3 do
		local g = f * CFrame.Angles(0, k * PI / 2, 0)
		for _, s in { -1, 1 } do
			box(m, g, s * 0.75, 7.88, 1.0, 0.25, 0.25, 0.25, "white", "Arch")
			box(m, g, s * 0.5, 8.12, 1.0, 0.25, 0.25, 0.25, "white", "Arch")
		end
	end
	box(m, f, 0, 8.5, 0, 2.5, 0.5, 2.5, "white", "Lintel")
	-- the bell on its beam
	Parts.log(m, f, 0, 7.75, 0, 2.0, 0.25, "wood_dark", "Beam")
	box(m, f, 0, 7.6, 0, 0.25, 0.25, 0.25, "gold", "Crown")
	cyl(m, f, 0, 7.4, 0, 0.75, 0.25, "gold", "Bell")
	cyl(m, f, 0, 7.05, 0, 1.25, 0.5, "gold", "Bell")
	cyl(m, f, 0, 6.65, 0, 1.5, 0.25, "gold", "BellLip")
	ball(m, f, 0, 6.45, 0, 0.25, "steel_dark", "Clapper")
	-- the spire
	box(m, f, 0, 8.87, 0, 2.75, 0.25, 2.75, "gold", "Eave")
	for k, w in { 2.25, 1.75, 1.25, 0.75, 0.5 } do
		box(m, f, 0, 8.75 + k * 0.5, 0, w, 0.5, w, "white", "Spire")
	end
	box(m, f, 0, 11.5, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 11.85, 0, 0.5, "gold", "Knob")
end

-- Crystal Spire (3 x 3): a tall crystal grown out of a dark rock mound: a great faceted shard (two prisms, one
-- turned on the other) with light along its edges, a ring of smaller shards round its foot leaning out a little,
-- little glowing ones among the rocks, glowing cracks, crystals floating over its point, rune stones at the corners.
M.crystalspire = function(m, f)
	cyl(m, f, 0, 0.12, 0, 3.0, 0.25, "slate", "Platform")
	box(m, f, 0, 0.37, 0, 2.0, 0.5, 2.0, "basalt", "Mound")
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		Parts.turned(m, f, math.cos(a) * 0.85, 0.3, math.sin(a) * 0.85, 0.75, 0.5, 0.75, a, if k % 2 == 0 then "basalt" else "rock_dark", "Rock")
	end
	-- glowing cracks in the rock
	box(m, f, 0.6, 0.62, 0.95, 0.75, 0.25, 0.25, "crystal", "Crack", true)
	box(m, f, 1.0, 0.62, -0.2, 0.25, 0.25, 0.5, "crystal", "Crack", true)
	-- the great shard: a square prism with a turned one inside it (its corners show as a ridge down each face)
	crystal(m, f, CFrame.new(0, 0.5, 0), 1.5, 7.5, "crystal")
	at(m, f, CFrame.new(0, 4.0, 0) * CFrame.Angles(0, PI / 4, 0), 1.5, 7.0, 1.5, "purple", "Facet")
	-- light caught along its edges
	box(m, f, -0.7, 4.5, 0.7, 0.25, 5.0, 0.25, "white", "Shine", true)
	box(m, f, 0.7, 6.0, 0.7, 0.25, 2.0, 0.25, "white", "Shine", true)
	-- the ring of shards round it: slim ones leaning out to the sides (the corners have the room), stouter ones
	-- nearly upright in front and behind
	local ring = {
		{ a = 0, w = 0.5, h = 1.5, t = 15, c = "pink" },
		{ a = 45, w = 1.0, h = 1.5, t = 6, c = "purple" },
		{ a = 90, w = 0.5, h = 1.25, t = 15, c = "crystal" },
		{ a = 135, w = 0.5, h = 3.0, t = 17, c = "pink" },
		{ a = 200, w = 1.0, h = 2.75, t = 6, c = "purple" },
		{ a = 250, w = 0.5, h = 2.0, t = 14, c = "crystal" },
		{ a = 315, w = 0.5, h = 3.25, t = 17, c = "pink" },
	}
	for _, s in ring do
		local a = R(s.a)
		local cf = CFrame.new(math.cos(a) * 0.45, 0.45, math.sin(a) * 0.45) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -R(s.t))
		crystal(m, f, cf, s.w, s.h, s.c)
	end
	-- little glowing shards among the rocks
	for _, s in { { 0.85, 0.75, 40 }, { -0.8, 0.85, 160 }, { 0.75, -0.85, 290 } } do
		local a = R(s[3])
		crystal(m, f, CFrame.new(s[1], 0.2, s[2]) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, -R(15)), 0.5, 0.5, "crystal", true)
	end
	-- crystals floating over the point
	for k, c in { { 0.7, 10.5, 0.5 }, { -0.6, 11.1, 0.3 }, { 0.2, 11.7, -0.5 } } do
		at(m, f, CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(R(45), R(30 * k), R(45)), 0.5, 0.5, 0.5, if k == 2 then "pink" else "white", "Mote", true)
	end
	-- rune stones at the corners
	for _, c in CORNERS do
		box(m, f, c[1] * 1.1, 0.5, c[2] * 1.1, 0.5, 1.0, 0.5, "slate", "RuneStone")
		box(m, f, c[1] * 1.1, 1.05, c[2] * 1.1, 0.75, 0.25, 0.75, "basalt", "RuneCap")
		-- the rune on the stone's outer face (toward +Z or -Z)
		local g = f * CFrame.new(c[1] * 1.1, 0, c[2] * 1.1) * CFrame.Angles(0, if c[2] > 0 then 0 else PI, 0)
		box(m, g, 0, 0.55, 0.2, 0.25, 0.5, 0.25, "crystal", "Rune", true)
	end
end

-- Rainbow Arch (5 x 2): a tall gateway of the six colours, red outside to purple inside, its feet in little clouds
-- that glow, stars sparkling round its top.
M.rainbowarch = function(m, f)
	local cols = { "berry_red", "orange", "yellow", "green", "blue", "purple" }
	local yc = 5.25 -- the centre of the arch's half circle
	for i, col in cols do
		local r = 2.125 - (i - 1) * 0.25
		for _, s in { -1, 1 } do
			box(m, f, s * r, (0.25 + yc) / 2, 0, 0.25, yc - 0.25, 0.75, col, "Band")
		end
		local n = math.ceil(PI * r / 0.4)
		for k = 0, n - 1 do
			local t = PI * (k + 0.5) / n
			at(m, f, CFrame.new(r * math.cos(t), yc + r * math.sin(t), 0) * CFrame.Angles(0, 0, t + PI / 2), 0.5, 0.25, 0.75, col, "Band")
		end
	end
	-- clouds round both feet
	for _, s in { -1, 1 } do
		ball(m, f, s * 1.65, 0.6, 0.15, 1.25, "white", "Cloud", true)
		ball(m, f, s * 2.0, 0.45, 0.5, 0.75, "white", "Cloud", true)
		ball(m, f, s * 1.05, 0.4, 0.5, 0.75, "white", "Cloud", true)
		ball(m, f, s * 2.0, 0.5, -0.45, 0.75, "white", "Cloud", true)
		ball(m, f, s * 1.45, 1.3, 0.0, 0.75, "white", "Cloud", true)
	end
	-- stars round the top
	glint(m, f, -1.9, 7.6, 0.3, "yellow")
	glint(m, f, 1.95, 6.9, 0.3, "yellow")
	glint(m, f, 0.5, 8.2, 0.2, "white")
end

------------------------------------------------------------------ seats
-- Log Seats (2 x 2): three logs round a stump table on a patch of trodden earth, a mug and an apple on the stump.
M.logseats = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.0, 0.25, "sand_dark", "Earth")
	cyl(m, f, 0, 0.3, 0, 0.75, 0.5, "wood_dark", "Stump")
	cyl(m, f, 0, 0.6, 0, 0.75, 0.25, "sand", "CutTop")
	cyl(m, f, 0, 0.62, 0, 0.25, 0.25, "sand_dark", "Ring")
	box(m, f, 0.4, 0.12, 0.15, 0.25, 0.25, 0.25, "wood_dark", "Root")
	box(m, f, -0.2, 0.12, 0.4, 0.25, 0.25, 0.25, "wood_dark", "Root")
	box(m, f, 0.15, 0.85, 0.12, 0.25, 0.25, 0.25, "blue", "Mug")
	ball(m, f, -0.15, 0.85, -0.1, 0.25, "berry_red", "Apple")
	-- the logs: bark, and pale cut ends
	Parts.log(m, f, 0, 0.27, -0.7, 1.0, 0.5, "wood")
	for _, x in { -0.625, 0.625 } do
		Parts.log(m, f, x, 0.27, -0.7, 0.25, 0.5, "sand", "LogEnd")
	end
	for _, x in { -0.7, 0.7 } do
		Parts.logZ(m, f, x, 0.27, 0.05, 1.0, 0.5, "wood")
		for _, z in { -0.575, 0.675 } do
			Parts.logZ(m, f, x, 0.27, z, 0.25, 0.5, "sand", "LogEnd")
		end
	end
	box(m, f, 0.7, 0.5, 0.3, 0.25, 0.25, 0.5, "moss", "Moss")
end

-- Park Bench (3 x 1): green slats on black cast-iron ends with arms, a brass plate, a newspaper left on the seat.
M.parkbench = function(m, f)
	for _, x in { -1.15, 1.15 } do
		box(m, f, x, 0.5, 0.3, 0.25, 1.0, 0.25, "black", "Leg")
		box(m, f, x, 0.7, -0.35, 0.25, 1.4, 0.25, "black", "Leg")
		box(m, f, x, 1.0, -0.02, 0.25, 0.25, 0.75, "black", "Arm")
		box(m, f, x, 0.12, -0.02, 0.25, 0.25, 0.75, "black", "Foot")
		box(m, f, x, 0.85, 0.35, 0.25, 0.25, 0.25, "black", "Curl")
	end
	for _, z in { 0.3, 0.02 } do
		box(m, f, 0, 0.62, z, 2.5, 0.25, 0.25, "green", "Slat")
	end
	for _, y in { 0.95, 1.25 } do
		box(m, f, 0, y, -0.25, 2.5, 0.25, 0.25, "green", "Slat")
	end
	box(m, f, 0, 0.62, 0.16, 2.0, 0.25, 0.25, "moss", "Gap")
	box(m, f, 0, 1.25, -0.15, 0.5, 0.25, 0.25, "gold", "Plate")
	box(m, f, 0.55, 0.68, 0.15, 0.5, 0.25, 0.25, "paper", "Newspaper")
end

-- Stone Bench (3 x 1): a pale slab on two carved stone legs, moss in a corner, grass at its feet, a straw sun hat
-- left on it.
M.stonebench = function(m, f)
	for _, x in { -0.95, 0.95 } do
		box(m, f, x, 0.12, 0, 0.75, 0.25, 0.75, "rock_dark", "Foot")
		box(m, f, x, 0.37, 0, 0.5, 0.25, 0.5, "rock", "Leg")
		box(m, f, x, 0.37, 0.2, 0.25, 0.25, 0.25, "rock_dark", "Carving")
		box(m, f, x - 0.35, 0.12, 0.3, 0.25, 0.25, 0.25, "grass_dark", "Tuft")
	end
	box(m, f, 0, 0.62, 0, 2.75, 0.25, 0.75, "pavement", "Slab")
	box(m, f, 0, 0.5, 0.05, 2.25, 0.25, 0.5, "rock", "Underside")
	box(m, f, -1.1, 0.68, -0.2, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, -0.95, 0.4, 0.27, 0.25, 0.25, 0.25, "moss", "Moss")
	-- the hat
	cyl(m, f, 0.55, 0.78, 0.05, 0.75, 0.25, "straw", "Brim")
	cyl(m, f, 0.55, 0.92, 0.05, 0.5, 0.25, "straw", "Crown")
	cyl(m, f, 0.55, 0.85, 0.05, 0.5, 0.25, "berry_red", "Band")
end

-- Porch Swing (3 x 2): a slatted bench on chains from a timber A-frame under a little teal canopy with a white
-- trim, a red cushion and a pillow.
M.porchswing = function(m, f)
	for _, x in { -1.25, 1.25 } do
		for _, z in { -0.85, 0.85 } do
			beam(m, f, V(x, 0, z), V(x, 2.55, 0), 0.25, "wood_dark", "Leg")
		end
		box(m, f, x, 0.75, 0, 0.25, 0.25, 1.25, "wood_dark", "Brace")
	end
	box(m, f, 0, 2.55, 0, 2.75, 0.25, 0.25, "wood", "Beam")
	Parts.wedge(m, f, 0, 2.95, -0.375, 3.0, 0.5, 0.75, "teal", 0, "Canopy")
	Parts.wedge(m, f, 0, 2.95, 0.375, 3.0, 0.5, 0.75, "teal", PI, "Canopy")
	box(m, f, 0, 3.25, 0, 3.0, 0.25, 0.25, "white", "Ridge")
	for _, z in { -0.75, 0.75 } do
		box(m, f, 0, 2.62, z, 3.0, 0.25, 0.25, "white", "Trim")
	end
	-- the bench
	box(m, f, 0, 0.75, 0, 2.0, 0.25, 0.75, "wood", "Seat")
	for _, y in { 1.05, 1.35 } do
		box(m, f, 0, y, -0.3, 2.0, 0.25, 0.25, "wood", "Slat")
	end
	for _, x in { -1.0, 1.0 } do
		box(m, f, x, 1.05, -0.3, 0.25, 0.75, 0.25, "wood_dark", "BackPost")
		box(m, f, x, 1.1, 0.02, 0.25, 0.25, 0.75, "wood_dark", "Arm")
		box(m, f, x, 1.8, 0.02, 0.25, 1.25, 0.25, "steel_dark", "Chain")
	end
	box(m, f, 0, 0.88, 0.05, 1.75, 0.25, 0.5, "berry_red", "Cushion")
	at(m, f, CFrame.new(-0.6, 1.12, -0.12) * CFrame.Angles(R(-15), 0, 0), 0.5, 0.5, 0.25, "cream", "Pillow")
end

------------------------------------------------------------------ lights
-- Garden Lights (1 x 1): a strip of border with a little lamp on a post (a lit head under a cap), flowers and a
-- leafy tuft either side, edging stones along the front (they run on into the next piece).
M.gardenlights = function(m, f)
	box(m, f, 0, 0.02, -0.12, 1.0, 0.25, 0.5, "wood_dark", "Bed")
	box(m, f, -0.25, 0.05, 0.25, 0.5, 0.25, 0.25, "rock", "Edging")
	box(m, f, 0.25, 0.05, 0.25, 0.5, 0.25, 0.25, "pavement", "Edging")
	box(m, f, 0, 0.35, -0.12, 0.25, 0.5, 0.25, "steel_dark", "Post")
	glow(m, f, 0, 0.7, -0.12, 0.5, 0.25, 0.5, "yellow", "Lamp")
	box(m, f, 0, 0.92, -0.12, 0.5, 0.25, 0.5, "steel_dark", "Cap")
	box(m, f, -0.35, 0.2, -0.25, 0.25, 0.25, 0.25, "leaf", "Tuft")
	box(m, f, -0.35, 0.3, -0.02, 0.25, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0.35, 0.3, -0.2, 0.25, 0.25, 0.25, "yellow", "Flower")
	box(m, f, 0.35, 0.18, 0.0, 0.25, 0.25, 0.25, "leaf", "Tuft")
end

-- Fire Pit (2 x 2): a ring of stones round grey ash, a little tent of sticks burning, embers, sparks going up, a
-- stick with a marshmallow leaning in.
M.firepit = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.25, 0.25, "basalt", "Ash")
	for k = 0, 7 do
		local a = k * PI / 4 + 0.2
		ball(m, f, math.cos(a) * 0.72, 0.15, math.sin(a) * 0.72, 0.5, if k % 2 == 0 then "rock" else "rock_dark", "Stone")
	end
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + 0.4
		beam(m, f, V(math.cos(a) * 0.4, 0.1, math.sin(a) * 0.4), V(0, 0.75, 0), 0.25, "wood_dark", "Stick")
	end
	Parts.log(m, f, 0, 0.2, 0.15, 0.75, 0.25, "wood", "Log")
	glow(m, f, 0, 0.42, 0, 0.5, 0.5, 0.5, "orange", "Flame")
	glow(m, f, 0.05, 0.78, 0.05, 0.25, 0.5, 0.25, "yellow", "Flame")
	glow(m, f, -0.15, 0.85, -0.12, 0.25, 0.25, 0.25, "orange", "Flame")
	glow(m, f, -0.3, 0.15, 0.25, 0.25, 0.25, 0.25, "lava", "Ember")
	glow(m, f, 0.3, 0.15, -0.25, 0.25, 0.25, 0.25, "lava", "Ember")
	glow(m, f, 0.2, 1.25, 0.1, 0.25, 0.25, 0.25, "yellow", "Spark")
	glow(m, f, -0.1, 1.6, -0.05, 0.25, 0.25, 0.25, "orange", "Spark")
	beam(m, f, V(0.8, 0.25, 0.7), V(0.4, 0.7, 0.35), 0.25, "wood", "Stick")
	box(m, f, 0.35, 0.73, 0.32, 0.25, 0.25, 0.25, "white", "Marshmallow")
end

-- Candles (1 x 1): three pillar candles of three heights and colours on a round slate stone with moss, each with
-- its flame.
M.candles = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "slate", "Stone")
	box(m, f, 0.3, 0.2, -0.3, 0.25, 0.25, 0.25, "moss", "Moss")
	-- side by side across the view, the tallest in the middle
	for _, c in { { x = -0.25, z = 0.2, h = 0.75, c = "berry_red" }, { x = 0.02, z = -0.08, h = 1.0, c = "cream" }, { x = 0.25, z = -0.25, h = 0.5, c = "white" } } do
		local x, z, h = c.x, c.z, c.h
		cyl(m, f, x, 0.25 + h / 2, z, 0.5, h, c.c, "Candle")
		box(m, f, x, 0.3 + h, z, 0.25, 0.25, 0.25, "black", "Wick")
		glow(m, f, x, 0.5 + h, z, 0.25, 0.25, 0.25, "yellow", "Flame")
	end
end

-- Paper Lanterns (2 x 1): two posts with a rope between, three round paper lanterns aglow hanging off it (the
-- middle one lower), each with a black cap and a gold tassel.
M.paperlanterns = function(m, f)
	for _, x in { -0.875, 0.875 } do
		box(m, f, x * 0.86, 0.08, 0, 0.5, 0.25, 0.5, "rock", "Base")
		box(m, f, x, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
		box(m, f, x, 2.05, 0, 0.25, 0.25, 0.25, "wood", "Cap")
	end
	local yAt = sagLine(m, f, -0.875, 0.875, 1.85, 0, 0.25, 4, "wood_dark", "Rope")
	for _, l in { { x = -0.5, d = 0.5, c = "berry_red", drop = 0 }, { x = 0, d = 0.5, c = "orange", drop = 0.35 }, { x = 0.5, d = 0.5, c = "berry_red", drop = 0 } } do
		local top = yAt(l.x) - 0.1 - l.drop
		local y = top - 0.15 - l.d / 2
		if l.drop > 0 then
			box(m, f, l.x, top + l.drop / 2, 0, 0.25, l.drop, 0.25, "black", "String")
		end
		box(m, f, l.x, top - 0.05, 0, 0.25, 0.25, 0.25, "black", "LanternCap")
		ball(m, f, l.x, y, 0, l.d, l.c, "Lantern", true)
		box(m, f, l.x, y - l.d / 2 - 0.1, 0, 0.25, 0.25, 0.25, "gold", "Tassel")
	end
end

-- String Lights (3 x 1): two poles, a wire sagging between them, six bulbs of party colours hanging off it.
M.stringlights = function(m, f)
	for _, x in { -1.3, 1.3 } do
		box(m, f, x, 1.12, 0, 0.25, 2.25, 0.25, "wood_dark", "Pole")
		box(m, f, x, 2.3, 0, 0.25, 0.25, 0.25, "wood", "Cap")
		box(m, f, x * 0.96, 0.05, 0, 0.5, 0.25, 0.5, "grass_dark", "Tuft")
	end
	local yAt = sagLine(m, f, -1.3, 1.3, 2.15, 0, 0.4, 6, "black", "Wire")
	local cols = { "yellow", "berry_red", "blue", "green", "orange", "pink" }
	for k = 0, 5 do
		local x = -1.0 + k * 0.4
		glow(m, f, x, yAt(x) - 0.3, 0, 0.25, 0.25, 0.25, cols[k + 1], "Bulb")
	end
end

------------------------------------------------------------------ play
-- Sandbox (2 x 2): a timber frame with corner seats round the sand, a bucket, a spade stuck in, a little sand
-- castle.
M.sandbox = function(m, f)
	for _, z in { -0.875, 0.875 } do
		box(m, f, 0, 0.15, z, 2.0, 0.5, 0.25, "wood", "Board")
	end
	for _, x in { -0.875, 0.875 } do
		box(m, f, x, 0.15, 0, 0.25, 0.5, 1.5, "wood", "Board")
	end
	for _, c in CORNERS do
		box(m, f, c[1] * 0.75, 0.42, c[2] * 0.75, 0.5, 0.25, 0.5, "wood_dark", "Seat")
	end
	box(m, f, 0, 0.2, 0, 1.5, 0.25, 1.5, "sand", "Sand")
	-- a castle and a heap
	box(m, f, -0.3, 0.4, -0.25, 0.5, 0.25, 0.5, "sand_dark", "Castle")
	box(m, f, -0.3, 0.6, -0.25, 0.25, 0.25, 0.25, "sand_dark", "Tower")
	ball(m, f, 0.3, 0.3, -0.35, 0.5, "sand", "Heap")
	-- the bucket
	cyl(m, f, 0.35, 0.5, 0.3, 0.5, 0.5, "blue", "Bucket")
	cyl(m, f, 0.35, 0.7, 0.3, 0.5, 0.25, "yellow", "Rim")
	-- the spade
	beam(m, f, V(-0.4, 0.3, 0.35), V(-0.3, 1.05, 0.45), 0.25, "berry_red", "Handle")
	box(m, f, -0.3, 1.1, 0.45, 0.5, 0.25, 0.25, "berry_red", "Grip")
	box(m, f, -0.42, 0.35, 0.33, 0.5, 0.25, 0.25, "steel", "Blade")
end

-- Seesaw (3 x 1): a yellow plank on a blue pivot, tipped down on its left end (a tyre under it), red seats and
-- handles, worn grass under both ends.
M.seesaw = function(m, f)
	for _, x in { -1.1, 1.1 } do
		box(m, f, x, 0.02, 0, 0.75, 0.25, 0.75, "sand_dark", "Worn")
	end
	box(m, f, 0, 0.12, 0, 1.0, 0.25, 0.75, "steel_dark", "Base")
	Parts.wedge(m, f, -0.25, 0.5, 0, 0.5, 0.5, 0.5, "blue", PI / 2, "Pivot")
	Parts.wedge(m, f, 0.25, 0.5, 0, 0.5, 0.5, 0.5, "blue", -PI / 2, "Pivot")
	Parts.logZ(m, f, 0, 0.78, 0, 0.75, 0.25, "steel", "Axle")
	Parts.logZ(m, f, -1.2, 0.18, 0, 0.5, 0.5, "black", "Tyre")
	local p = CFrame.new(0, 0.85, 0) * CFrame.Angles(0, 0, R(-14))
	at(m, f, p, 2.75, 0.25, 0.5, "yellow", "Plank")
	for _, s in { -1, 1 } do
		at(m, f, p * CFrame.new(s * 1.05, 0.22, 0), 0.5, 0.25, 0.5, "berry_red", "Seat")
		at(m, f, p * CFrame.new(s * 0.6, 0.4, 0), 0.25, 0.5, 0.25, "berry_red", "Handle")
		at(m, f, p * CFrame.new(s * 0.6, 0.65, 0), 0.25, 0.25, 0.75, "berry_red", "Grip")
	end
end

-- Swing Set (3 x 2): a blue A-frame and top bar, two swings on chains (the right one mid swing), worn earth under
-- them.
M.swing = function(m, f)
	for _, x in { -1.3, 1.3 } do
		for _, z in { -0.85, 0.85 } do
			beam(m, f, V(x, 0, z), V(x, 2.45, 0), 0.25, "blue", "Leg")
		end
	end
	Parts.log(m, f, 0, 2.45, 0, 2.85, 0.25, "blue", "Bar")
	for _, s in { { x = -0.55, swing = 0, c = "berry_red" }, { x = 0.55, swing = -R(22), c = "yellow" } } do
		local x, swing = s.x, s.swing
		box(m, f, x, 0.02, 0, 0.75, 0.25, 1.0, "sand_dark", "Worn")
		local cf = CFrame.new(x, 2.4, 0) * CFrame.Angles(swing, 0, 0)
		local len = 1.8
		for _, dx in { -0.3, 0.3 } do
			at(m, f, cf * CFrame.new(dx, -len / 2, 0), 0.25, len, 0.25, "steel", "Chain")
		end
		at(m, f, cf * CFrame.new(0, -len, 0), 0.75, 0.25, 0.5, s.c, "Seat")
	end
end

-- Slide (3 x 2): a little tower (a deck on blue posts under a red roof with a pennant), a ladder up its front, a
-- yellow chute with red walls down to a patch of sand.
M.slide = function(m, f)
	local tx = -0.875
	for _, x in { tx - 0.325, tx + 0.325 } do
		for _, z in { -0.35, 0.35 } do
			box(m, f, x, 1.375, z, 0.25, 2.75, 0.25, "blue", "Post")
		end
	end
	box(m, f, tx, 1.5, 0, 1.0, 0.25, 1.0, "wood", "Deck")
	box(m, f, tx, 2.0, -0.35, 0.75, 0.25, 0.25, "yellow", "Rail")
	box(m, f, tx - 0.325, 2.0, 0, 0.25, 0.25, 0.75, "yellow", "Rail")
	box(m, f, tx, 2.8, 0, 1.25, 0.25, 1.25, "white", "Eave")
	Parts.wedge(m, f, tx, 3.18, -0.25, 1.25, 0.5, 0.5, "berry_red", 0, "Roof")
	Parts.wedge(m, f, tx, 3.18, 0.25, 1.25, 0.5, 0.5, "berry_red", PI, "Roof")
	box(m, f, tx, 3.75, 0, 0.25, 0.75, 0.25, "steel_dark", "FlagPole")
	Parts.wedge(m, f, tx + 0.5, 3.87, 0, 0.25, 0.5, 0.75, "yellow", -PI / 2, "Flag")
	-- the ladder down the front
	for _, x in { tx - 0.3, tx + 0.3 } do
		beam(m, f, V(x, 0, 0.85), V(x, 1.65, 0.45), 0.25, "steel", "LadderRail")
	end
	for k = 1, 4 do
		local t = k / 5
		box(m, f, tx, t * 1.65, 0.85 - t * 0.4, 0.75, 0.25, 0.25, "steel", "Rung")
	end
	-- the chute
	local a, b = V(-0.4, 1.6, 0), V(1.0, 0.35, 0)
	local d = b - a
	local cf = CFrame.new((a + b) / 2) * CFrame.Angles(0, 0, math.atan2(d.Y, d.X))
	local len = d.Magnitude + 0.25
	at(m, f, cf, len, 0.25, 0.75, "yellow", "Chute")
	for _, s in { -1, 1 } do
		at(m, f, cf * CFrame.new(0, 0.25, s * 0.5), len, 0.25, 0.25, "berry_red", "Wall")
		box(m, f, 1.2, 0.5, s * 0.5, 0.5, 0.25, 0.25, "berry_red", "Wall")
	end
	box(m, f, 1.2, 0.25, 0, 0.5, 0.25, 0.75, "yellow", "RunOut")
	box(m, f, 0.5, 0.4, 0, 0.25, 0.75, 0.25, "blue", "Prop")
	box(m, f, 1.1, 0.02, 0, 0.75, 0.25, 1.25, "sand", "Sand")
end

-- Trampoline (3 x 3): a round black mat in a blue padded ring on six legs, a step up at the front, a red ball in
-- the air over it.
M.trampoline = function(m, f)
	for k = 0, 5 do
		local a = k * PI / 3 + PI / 6
		box(m, f, math.cos(a) * 1.15, 0.38, math.sin(a) * 1.15, 0.25, 0.75, 0.25, "steel_dark", "Leg")
	end
	cyl(m, f, 0, 0.8, 0, 2.75, 0.25, "blue", "Padding")
	cyl(m, f, 0, 0.83, 0, 2.25, 0.25, "black", "Mat")
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.45, 1.38, 0.25, 0.9, 0.25, "steel_dark", "StepRail")
	end
	for _, y in { 0.3, 0.6 } do
		box(m, f, 0, y, 1.38, 0.75, 0.25, 0.25, "steel", "Step")
	end
	ball(m, f, 0.3, 2.3, -0.2, 0.75, "berry_red", "Ball")
end

-- Merry-Go-Round (3 x 3): a little round ride: a red and cream deck, a gold column, four bright critters on gold
-- poles at two heights, a striped stepped canopy with a scalloped trim, a gold top and a pennant.
M.carousel = function(m, f)
	cyl(m, f, 0, 0.12, 0, 2.75, 0.25, "berry_red", "Skirt")
	cyl(m, f, 0, 0.37, 0, 2.75, 0.25, "cream", "Deck")
	cyl(m, f, 0, 1.0, 0, 0.75, 1.0, "berry_red", "Drum")
	cyl(m, f, 0, 1.55, 0, 0.75, 0.25, "gold", "Band")
	cyl(m, f, 0, 2.15, 0, 0.5, 1.0, "gold", "Column")
	-- the canopy
	for k, d in { 3.0, 2.5, 2.0, 1.5, 1.0 } do
		cyl(m, f, 0, 2.62 + (k - 1) * 0.25, 0, d, 0.25, if k % 2 == 1 then "berry_red" else "white", "Canopy")
	end
	for k = 0, 11 do
		local a = k * PI / 6
		Parts.turned(m, f, math.cos(a) * 1.3, 2.37, math.sin(a) * 1.3, 0.25, 0.25, 0.5, -a, if k % 2 == 0 then "yellow" else "berry_red", "Scallop")
	end
	ball(m, f, 0, 3.85, 0, 0.5, "gold", "Top")
	box(m, f, 0, 4.37, 0, 0.25, 0.75, 0.25, "gold", "FlagPole")
	Parts.wedge(m, f, 0.5, 4.5, 0, 0.25, 0.5, 0.75, "blue", -PI / 2, "Flag")
	-- the riders: a body, a head with a snout, an ear, on a pole
	for k, c in { "yellow", "blue", "pink", "green" } do
		local a = (k - 1) * PI / 2 + PI / 4
		local px, pz = math.cos(a) * 0.95, math.sin(a) * 0.95
		local y = if k % 2 == 0 then 1.35 else 1.05
		box(m, f, px, 1.5, pz, 0.25, 2.25, 0.25, "gold", "Pole")
		local g = f * CFrame.new(px, y, pz) * CFrame.Angles(0, -a, 0)
		box(m, g, 0, 0, 0, 0.5, 0.5, 0.75, c, "Rider")
		box(m, g, 0, 0.35, 0.4, 0.5, 0.5, 0.5, c, "RiderHead")
		box(m, g, 0, 0.25, 0.7, 0.25, 0.25, 0.25, "white", "Snout")
		box(m, g, 0, 0.7, 0.3, 0.25, 0.25, 0.25, c, "Ear")
		box(m, g, 0, -0.2, -0.45, 0.25, 0.25, 0.25, "white", "Tail")
	end
end

-- Climbing Frame (3 x 3): a timber tower with a lookout deck under a green roof and a flag, a rope net down its
-- front, a climbing wall with bright holds on its side, monkey bars out to a far post with a knotted rope.
M.climbframe = function(m, f)
	box(m, f, 0, 0.02, 0, 3.0, 0.25, 3.0, "sand_dark", "Bark")
	local cx, cz = -0.4, -0.4
	for _, x in { cx - 0.75, cx + 0.75 } do
		for _, z in { cz - 0.75, cz + 0.75 } do
			box(m, f, x, 1.5, z, 0.25, 3.0, 0.25, "wood", "Post")
		end
	end
	box(m, f, cx, 1.5, cz, 1.75, 0.25, 1.75, "wood_dark", "Deck")
	box(m, f, cx, 2.1, cz - 0.75, 1.5, 0.25, 0.25, "wood_dark", "Rail")
	box(m, f, cx - 0.75, 2.1, cz, 0.25, 0.25, 1.5, "wood_dark", "Rail")
	Parts.wedge(m, f, cx, 3.37, cz - 0.5, 2.0, 0.75, 1.0, "green", 0, "Roof")
	Parts.wedge(m, f, cx, 3.37, cz + 0.5, 2.0, 0.75, 1.0, "green", PI, "Roof")
	box(m, f, cx, 4.12, cz, 0.25, 0.75, 0.25, "wood_dark", "FlagPole")
	Parts.wedge(m, f, cx + 0.5, 4.25, cz, 0.25, 0.5, 0.75, "orange", -PI / 2, "Flag")
	-- the rope net, from the deck's front edge down to the ground
	local z0, z1 = cz + 0.85, 1.35
	for _, x in { cx - 0.6, cx, cx + 0.6 } do
		beam(m, f, V(x, 1.55, z0), V(x, 0.05, z1), 0.25, "straw", "Rope")
	end
	for _, t in { 0.25, 0.5, 0.75 } do
		box(m, f, cx, 1.55 - t * 1.5, z0 + t * (z1 - z0), 1.5, 0.25, 0.25, "straw", "Rope")
	end
	-- the climbing wall on the right side
	box(m, f, cx + 0.9, 0.75, cz, 0.25, 1.5, 1.5, "blue", "Wall")
	for k, h in { { 0.3, -0.4 }, { 0.65, 0.3 }, { 0.95, -0.2 }, { 1.25, 0.45 }, { 0.5, 0.05 }, { 1.2, -0.5 } } do
		box(m, f, cx + 1.05, h[1], cz + h[2], 0.25, 0.25, 0.25, ({ "berry_red", "yellow", "green", "orange" })[(k - 1) % 4 + 1], "Hold")
	end
	-- the monkey bars, out to a post, and a rope hanging
	local bz = cz - 0.55
	for _, z in { bz - 0.25, bz + 0.25 } do
		box(m, f, 0.7, 2.1, z, 1.5, 0.25, 0.25, "steel_dark", "BarRail")
		box(m, f, 1.25, 1.05, z, 0.25, 2.1, 0.25, "wood", "Post")
	end
	for _, x in { 0.6, 0.9 } do
		box(m, f, x, 2.1, bz, 0.25, 0.25, 0.75, "steel", "Bar")
	end
	box(m, f, 1.25, 1.55, bz, 0.25, 1.0, 0.25, "straw", "SwingRope")
	ball(m, f, 1.25, 1.0, bz, 0.5, "straw", "Knot")
end

------------------------------------------------------------------ treats
-- Grill (1 x 1): a round black grill on three splayed legs, red-hot coals, sausages and a corn cob cooking on it,
-- smoke going up.
M.grill = function(m, f)
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + PI / 6
		beam(m, f, V(math.cos(a) * 0.32, 0, math.sin(a) * 0.32), V(math.cos(a) * 0.18, 0.6, math.sin(a) * 0.18), 0.25, "steel_dark", "Leg")
	end
	cyl(m, f, 0, 0.62, 0, 0.75, 0.25, "black", "Bowl")
	cyl(m, f, 0, 0.87, 0, 1.0, 0.25, "black", "Bowl")
	cyl(m, f, 0, 0.9, 0, 0.75, 0.25, "orange", "Coals", true)
	box(m, f, -0.05, 1.07, -0.15, 0.5, 0.25, 0.25, "brick", "Sausage")
	box(m, f, 0.05, 1.07, 0.15, 0.5, 0.25, 0.25, "brick", "Sausage")
	box(m, f, 0.25, 1.07, 0.0, 0.25, 0.25, 0.5, "yellow", "Corn")
	ball(m, f, 0.0, 1.6, 0.0, 0.5, "white", "Smoke")
	ball(m, f, -0.15, 2.1, 0.15, 0.5, "white", "Smoke")
end

-- Lemonade Stand (2 x 1): a counter in yellow and white stripes, a jug of lemonade, cups, a bowl of lemons, a sign
-- on two posts with a lemon slice drawn on it.
M.lemonade = function(m, f)
	box(m, f, 0, 0.375, 0.05, 1.75, 0.75, 0.5, "white", "Counter")
	for _, x in { -0.625, 0, 0.625 } do
		box(m, f, x, 0.375, 0.27, 0.25, 0.75, 0.25, "yellow", "Stripe")
	end
	box(m, f, 0, 0.85, 0.05, 2.0, 0.25, 0.75, "wood", "Top")
	for _, x in { -0.85, 0.85 } do
		box(m, f, x, 1.45, -0.25, 0.25, 1.0, 0.25, "wood", "Post")
	end
	box(m, f, 0, 1.85, -0.25, 1.75, 0.75, 0.25, "yellow", "Sign")
	disc(m, f, -0.45, 1.85, -0.17, 0.5, 0.25, "white", "Lemon")
	box(m, f, -0.45, 1.85, -0.12, 0.25, 0.25, 0.25, "yellow", "LemonPip")
	box(m, f, 0.2, 1.95, -0.17, 0.75, 0.25, 0.25, "white", "Letters")
	box(m, f, 0.3, 1.7, -0.17, 0.5, 0.25, 0.25, "white", "Letters")
	-- on the counter
	cyl(m, f, -0.5, 1.15, 0.05, 0.5, 0.5, "yellow", "Jug")
	cyl(m, f, -0.5, 1.4, 0.05, 0.5, 0.25, "window", "JugRim")
	box(m, f, -0.8, 1.15, 0.05, 0.25, 0.25, 0.25, "window", "JugHandle")
	for _, c in { { 0.05, 0.25 }, { 0.3, 0.2 }, { 0.05, -0.1 } } do
		box(m, f, c[1], 1.08, c[2], 0.25, 0.25, 0.25, "paper", "Cup")
	end
	cyl(m, f, 0.6, 1.02, 0.05, 0.5, 0.25, "blue", "Bowl")
	for _, c in { { 0.52, -0.02 }, { 0.68, 0.12 }, { 0.6, 0.05 } } do
		ball(m, f, c[1], 1.15 + (if c[1] == 0.6 then 0.1 else 0), c[2], 0.25, "yellow", "Lemon")
	end
end

-- Ice Cream Cart (2 x 1): a white cart on big wheels with a pink bumper and a cone painted on its side, three
-- scoops on show over the glass lid (pink, vanilla, chocolate), a push bar with a gold bell, a little pink sunshade.
M.icecream = function(m, f)
	box(m, f, 0.1, 0.75, 0, 1.25, 0.75, 0.5, "white", "Body")
	box(m, f, 0.1, 0.5, 0, 1.5, 0.25, 0.75, "pink", "Bumper")
	box(m, f, 0.1, 1.2, 0, 1.25, 0.25, 0.5, "window", "Lid")
	for k, c in { "pink", "cream", "wood_dark" } do
		ball(m, f, -0.15 + (k - 1) * 0.37, 1.4, 0, 0.5, c, "Scoop")
	end
	for _, z in { -0.34, 0.34 } do
		disc(m, f, 0.4, 0.38, z, 0.75, 0.25, "black", "Wheel")
		disc(m, f, 0.4, 0.38, z + (if z > 0 then 0.03 else -0.03), 0.25, 0.25, "steel", "Hub")
	end
	box(m, f, -0.35, 0.2, 0, 0.25, 0.5, 0.25, "steel_dark", "Leg")
	-- a cone drawn on its side
	box(m, f, -0.2, 0.75, 0.27, 0.25, 0.25, 0.25, "sand_dark", "Cone")
	box(m, f, -0.2, 0.95, 0.27, 0.25, 0.25, 0.25, "pink", "ConeScoop")
	-- the push bar and its bell
	for _, z in { -0.25, 0.25 } do
		box(m, f, -0.65, 1.05, z, 0.5, 0.25, 0.25, "steel_dark", "BarArm")
	end
	box(m, f, -0.85, 1.05, 0, 0.25, 0.25, 0.75, "steel_dark", "PushBar")
	cyl(m, f, -0.65, 1.3, 0.25, 0.25, 0.25, "gold", "Bell")
	-- the sunshade, on a pole at the push bar's end of the cart
	box(m, f, -0.4, 1.9, 0, 0.25, 1.25, 0.25, "white", "ShadePole")
	cyl(m, f, -0.4, 2.55, 0, 1.0, 0.25, "pink", "Shade")
	cyl(m, f, -0.4, 2.75, 0, 0.5, 0.25, "white", "Shade")
	ball(m, f, -0.4, 2.95, 0, 0.25, "pink", "ShadeTop")
end

-- Telescope (1 x 1): a brass telescope on a wooden tripod, tipped up at the sky over the sea.
M.telescope = function(m, f)
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + PI / 2
		beam(m, f, V(math.cos(a) * 0.32, 0, math.sin(a) * 0.32), V(0, 1.15, 0), 0.25, "wood_dark", "Leg")
	end
	box(m, f, 0, 1.2, 0, 0.25, 0.25, 0.25, "steel_dark", "Mount")
	local t = CFrame.new(0, 1.45, 0) * CFrame.Angles(0, R(45), 0) * CFrame.Angles(0, 0, R(32))
	rod(m, f, t, 0.75, 0.5, "gold", "Tube")
	rod(m, f, t * CFrame.new(0.4, 0, 0), 0.25, 0.25, "window", "Lens")
	rod(m, f, t * CFrame.new(-0.45, 0, 0), 0.25, 0.25, "steel_dark", "Eyepiece")
end

-- Tiki Bar (3 x 2): a bar of bamboo canes bound with rope, a carved face on its front, a shelf of bottles behind,
-- drinks on top (a coconut with a straw, a glass with a little umbrella), two stools, a thatched roof with a ragged
-- fringe on bamboo posts, a torch at each front post.
M.tikibar = function(m, f)
	box(m, f, 0, 0.02, 0, 2.75, 0.25, 1.75, "sand", "Floor")
	for k = 0, 7 do
		cyl(m, f, -0.98 + k * 0.28, 0.55, 0.38, 0.25, 1.0, "bamboo", "Cane")
	end
	box(m, f, 0, 0.55, 0.5, 2.25, 0.25, 0.25, "straw", "Binding")
	box(m, f, 0, 1.1, 0.25, 2.5, 0.25, 0.75, "wood", "Counter")
	box(m, f, 0, 0.5, 0.58, 0.5, 0.75, 0.25, "wood_dark", "Face")
	for _, x in { -0.12, 0.12 } do
		box(m, f, x, 0.65, 0.65, 0.25, 0.25, 0.25, "yellow", "FaceEye")
	end
	box(m, f, 0, 0.3, 0.65, 0.25, 0.25, 0.25, "white", "FaceMouth")
	-- the back shelf of bottles
	box(m, f, 0, 1.25, -0.65, 2.25, 0.25, 0.5, "wood_dark", "Shelf")
	for k, c in { "teal", "green", "berry_red", "orange", "purple" } do
		box(m, f, -0.8 + (k - 1) * 0.4, 1.6, -0.65, 0.25, 0.5, 0.25, c, "Bottle")
	end
	-- posts and roof
	for _, x in { -1.3, 1.3 } do
		for _, z in { -0.75, 0.75 } do
			cyl(m, f, x, 1.15, z, 0.25, 2.3, "bamboo", "Post")
		end
		box(m, f, x, 1.75, 0.85, 0.25, 0.25, 0.25, "wood", "TorchCup")
		glow(m, f, x, 2.0, 0.85, 0.25, 0.25, 0.25, "orange", "Flame")
	end
	Parts.wedge(m, f, 0, 2.62, -0.5, 3.0, 0.75, 1.0, "straw", 0, "Thatch")
	Parts.wedge(m, f, 0, 2.62, 0.5, 3.0, 0.75, 1.0, "straw", PI, "Thatch")
	box(m, f, 0, 3.05, 0, 3.0, 0.25, 0.25, "sand_dark", "Ridge")
	for _, z in { -1, 1 } do
		-- a course of thatch across each slope, and the ragged fringe under each eave
		box(m, f, 0, 2.6, z * 0.5, 3.0, 0.25, 0.25, "sand_dark", "Thatch")
		for k = 0, 5 do
			local long = (k + (if z > 0 then 0 else 1)) % 2 == 0
			box(m, f, -1.25 + k * 0.5, if long then 2.0 else 2.12, z * 0.88, 0.5, if long then 0.5 else 0.25, 0.25, if long then "sand_dark" else "straw", "Fringe")
		end
	end
	-- drinks
	ball(m, f, -0.6, 1.4, 0.3, 0.5, "wood_dark", "Coconut")
	box(m, f, -0.5, 1.75, 0.3, 0.25, 0.5, 0.25, "pink", "Straw")
	box(m, f, 0.4, 1.38, 0.35, 0.25, 0.5, 0.25, "orange", "Glass")
	cyl(m, f, 0.4, 1.75, 0.35, 0.5, 0.25, "pink", "Umbrella")
	-- stools
	for _, x in { -0.65, 0.65 } do
		box(m, f, x, 0.37, 0.75, 0.25, 0.75, 0.25, "bamboo", "StoolLeg")
		cyl(m, f, x, 0.8, 0.75, 0.5, 0.25, "wood_dark", "Stool")
	end
end

------------------------------------------------------------------ fountains
-- Drinking Fountain (1 x 1): a teal iron column on a slab, a steel basin of water, a little jet from its spout.
M.drinkfountain = function(m, f)
	box(m, f, 0, 0.1, 0, 0.75, 0.25, 0.75, "pavement", "Slab")
	cyl(m, f, 0, 0.3, 0, 0.75, 0.25, "teal", "Foot")
	cyl(m, f, 0, 0.65, 0, 0.5, 0.75, "teal", "Column")
	cyl(m, f, 0, 1.05, 0, 0.75, 0.25, "steel", "Basin")
	pool(m, f, 0, 1.08, 0, 0.5)
	box(m, f, 0, 1.3, -0.2, 0.25, 0.25, 0.25, "steel_dark", "Spout")
	jet(m, f, 0, 1.45, -0.05, 0.25, 0.5, 0.25)
	box(m, f, 0.3, 0.3, 0.3, 0.25, 0.25, 0.25, "steel_dark", "Drain")
end

-- Little Fountain (2 x 2): a stone bowl on a stem on square paving, water in it, a jet in the middle with drops
-- falling round it, a lily pad, a coin.
M.smallfountain = function(m, f)
	box(m, f, 0, 0.02, 0, 2.0, 0.25, 2.0, "pavement", "Paving")
	for _, c in CORNERS do
		box(m, f, c[1] * 0.75, 0.05, c[2] * 0.75, 0.5, 0.25, 0.5, "rock", "Corner")
	end
	cyl(m, f, 0, 0.2, 0, 1.0, 0.25, "rock_dark", "Foot")
	cyl(m, f, 0, 0.42, 0, 0.5, 0.25, "rock", "Stem")
	cyl(m, f, 0, 0.6, 0, 1.25, 0.25, "rock", "Bowl")
	cyl(m, f, 0, 0.8, 0, 1.75, 0.25, "pavement", "Rim")
	pool(m, f, 0, 0.83, 0, 1.25)
	box(m, f, 0, 1.0, 0, 0.25, 0.25, 0.25, "steel", "Nozzle")
	jet(m, f, 0, 1.6, 0, 0.25, 1.0, 0.25)
	ball(m, f, 0, 2.15, 0, 0.5, "foam", "Spray"):SetAttribute("PixelWater", 2)
	for _, c in { { 0.35, 1.5, 0.15 }, { -0.3, 1.3, 0.25 }, { 0.15, 1.2, -0.4 } } do
		jet(m, f, c[1], c[2], c[3], 0.25, 0.25, 0.25, "shallow")
	end
	cyl(m, f, 0.4, 0.86, 0.25, 0.5, 0.25, "leaf", "LilyPad")
	box(m, f, -0.3, 0.86, 0.35, 0.25, 0.25, 0.25, "gold", "Coin")
end

-- Koi Pond (3 x 3): a kidney of water edged with rocks and moss, three koi near the surface (orange and white,
-- white and orange, gold), lily pads with a flower, reeds and cattails in a corner, a little fall of water over
-- stacked rocks at the back.
M.koipond = function(m, f)
	pool(m, f, -0.2, 0.05, -0.1, 2.25)
	pool(m, f, 0.45, 0.05, 0.45, 1.5)
	-- rocks round the edge
	local rocks = {
		{ x = -1.1, z = -0.5, d = 0.75, c = "rock" },
		{ x = -1.2, z = 0.4, d = 0.5, c = "rock_dark" },
		{ x = -0.85, z = 1.05, d = 0.75, c = "rock" },
		{ x = -0.1, z = 1.2, d = 0.5, c = "rock_dark" },
		{ x = 0.6, z = 1.2, d = 0.5, c = "rock" },
		{ x = 1.2, z = 0.9, d = 0.5, c = "rock_dark" },
		{ x = 1.1, z = 0.2, d = 0.75, c = "rock" },
		{ x = 1.2, z = -0.55, d = 0.5, c = "rock_dark" },
		{ x = -0.6, z = -1.2, d = 0.5, c = "rock_dark" },
		{ x = -1.15, z = -1.1, d = 0.5, c = "rock" },
		{ x = 0.15, z = -1.2, d = 0.5, c = "rock" },
	}
	for _, r in rocks do
		ball(m, f, r.x, 0.12, r.z, r.d, r.c, "Rock")
	end
	box(m, f, -1.1, 0.4, -0.5, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, 1.1, 0.4, 0.2, 0.25, 0.25, 0.5, "moss", "Moss")
	-- the little fall at the back
	box(m, f, 0.75, 0.37, -1.15, 1.0, 0.75, 0.5, "rock_dark", "FallRock")
	box(m, f, 0.75, 0.85, -1.2, 0.5, 0.5, 0.5, "rock", "FallRock")
	jet(m, f, 0.75, 0.4, -0.85, 0.5, 0.75, 0.25)
	-- lily pads and a flower
	for _, c in { { -0.6, -0.4 }, { 0.2, 0.75 }, { -0.75, 0.45 } } do
		cyl(m, f, c[1], 0.1, c[2], 0.5, 0.25, "leaf", "LilyPad")
	end
	box(m, f, -0.6, 0.25, -0.4, 0.25, 0.25, 0.25, "pink", "LilyFlower")
	-- the koi: a body, a head patch, a tail
	for _, k in { { x = 0.1, z = 0.0, a = 30, c = "orange", b = "white" }, { x = 0.6, z = 0.6, a = -60, c = "white", b = "orange" }, { x = -0.4, z = 0.15, a = 150, c = "gold", b = "orange" } } do
		local g = f * CFrame.new(k.x, 0.12, k.z) * CFrame.Angles(0, R(k.a), 0)
		box(m, g, 0, 0, 0, 0.5, 0.25, 0.25, k.c, "Koi")
		box(m, g, 0.25, 0.02, 0, 0.25, 0.25, 0.25, k.b, "KoiHead")
		box(m, g, -0.35, 0, 0, 0.25, 0.25, 0.25, k.b, "KoiTail")
	end
	-- reeds and cattails
	for _, r in { { -1.3, -0.6, 1.25 }, { -0.85, -1.25, 1.0 }, { -1.3, -1.2, 0.75 } } do
		box(m, f, r[1], r[3] / 2, r[2], 0.25, r[3], 0.25, "leaf_dark", "Reed")
	end
	box(m, f, -1.3, 1.3, -0.6, 0.25, 0.5, 0.25, "wood_dark", "Cattail")
	box(m, f, -0.85, 1.05, -1.25, 0.25, 0.5, 0.25, "wood_dark", "Cattail")
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor")

-- Driftling Colossus (4 x 4): a driftling carved in grey stone sitting up on a plinth, as tall as a tower: a round body,
-- a big head with ears, a moss cap, eyes set with glowing stones, its paws on its knees.
M.colossus = function(m, f)
	box(m, f, 0, 0.25, 0, 4, 0.5, 4, "slate", "Plinth")
	box(m, f, 0, 0.62, 0, 3.5, 0.25, 3.5, "rock", "Plinth")
	ball(m, f, 0, 2.2, -0.2, 3.25, "rock", "Body")
	ball(m, f, 0, 2.0, 0.4, 2.25, "cream", "Belly")
	for _, s in { -1, 1 } do
		ball(m, f, s * 1.0, 1.0, 1.0, 1.0, "rock_dark", "Foot")
		ball(m, f, s * 1.2, 2.0, 0.9, 0.75, "rock_dark", "Paw")
		at(m, f, CFrame.new(s * 0.85, 5.75, -0.2) * CFrame.Angles(0, 0, -s * 0.35), 0.75, 1.25, 0.5, "rock", "Ear")
		glow(m, f, s * 0.5, 4.6, 0.95, 0.5, 0.5, 0.25, "teal", "Eye")
	end
	ball(m, f, 0, 4.6, -0.1, 2.75, "rock", "Head")
	box(m, f, 0, 4.1, 1.15, 0.5, 0.25, 0.25, "rock_dark", "Mouth")
	ball(m, f, -0.4, 5.75, -0.3, 1.25, "moss", "Moss")
	ball(m, f, 0.5, 5.6, -0.6, 0.75, "moss", "Moss")
	box(m, f, 0, 0.5, 2.05, 1.5, 0.25, 0.25, "gold", "Plaque")
end

-- Moonwell (4 x 4): a round well of pale stone on three steps, a ring of standing stones round it, a glowing moon of
-- water inside, a silver arch over it holding a crescent, motes of light over the water.
M.moonwell = function(m, f)
	cyl(m, f, 0, 0.12, 0, 4.0, 0.25, "slate", "Step")
	cyl(m, f, 0, 0.37, 0, 3.25, 0.25, "rock", "Step")
	cyl(m, f, 0, 0.75, 0, 2.25, 0.5, "white", "Wall")
	cyl(m, f, 0, 1.05, 0, 2.5, 0.25, "cream", "Lip")
	cyl(m, f, 0, 1.0, 0, 1.75, 0.25, "ice", "Moon", true)
	for k = 0, 7 do
		local a = k * PI / 4 + PI / 8
		box(m, f, math.sin(a) * 1.75, 0.75, math.cos(a) * 1.75, 0.25, 1.0, 0.25, "rock", "Stone")
		glow(m, f, math.sin(a) * 1.75, 1.35, math.cos(a) * 1.75, 0.25, 0.25, 0.25, "crystal", "StoneLight")
	end
	for _, s in { -1, 1 } do
		box(m, f, s * 1.1, 2.0, 0, 0.25, 2.0, 0.25, "steel", "ArchPost")
	end
	box(m, f, 0, 3.0, 0, 2.5, 0.25, 0.25, "steel", "ArchTop")
	disc(m, f, 0, 3.55, 0, 0.75, 0.25, "ice", "Crescent", true)
	disc(m, f, 0.2, 3.65, 0.1, 0.5, 0.25, "steel", "CrescentShade")
	for k = 0, 3 do
		local a = k * 1.7
		glow(m, f, math.sin(a) * 0.5, 1.6 + k * 0.3, math.cos(a) * 0.5, 0.25, 0.25, 0.25, if k % 2 == 0 then "white" else "ice", "Mote")
	end
end

-- Star Gate (5 x 2): a great ring of carved stone standing on its edge in two feet, its middle filled with a field of
-- stars, runes glowing round the ring and a gold key stone at the top.
M.stargate = function(m, f)
	box(m, f, 0, 0.25, 0, 5, 0.5, 2, "slate", "Base")
	for _, s in { -1, 1 } do
		box(m, f, s * 1.75, 0.9, 0, 1.0, 0.75, 1.25, "rock", "Foot")
	end
	local r = 2.0
	for k = 0, 15 do
		local a = k * PI / 8
		at(m, f, CFrame.new(math.sin(a) * r, 2.75 + math.cos(a) * r, 0) * CFrame.Angles(0, 0, -a), 0.75, 0.75, 0.75, if k % 2 == 0 then "rock" else "slate", "Ring")
		if k % 2 == 1 then
			glow(m, f, math.sin(a) * r, 2.75 + math.cos(a) * r, 0.4, 0.25, 0.25, 0.25, "teal", "Rune")
		end
	end
	disc(m, f, 0, 2.75, 0, 3.25, 0.25, "night", "Stars")
	for k = 0, 9 do
		local a = k * 2.3
		local d = 0.3 + (k % 4) * 0.35
		glow(m, f, math.sin(a) * d, 2.75 + math.cos(a) * d, 0.15, 0.25, 0.25, 0.25, if k % 3 == 0 then "yellow" else "white", "Star")
	end
	box(m, f, 0, 4.85, 0, 0.75, 0.5, 0.75, "gold", "KeyStone")
end

-- Crown of the Sea (5 x 5): a crown three rings high built of coral and gold on a round base of pale stone, each ring
-- narrower with points round its rim, pearls on the points, a great glowing pearl at the top and shells round the foot.
M.seacrown = function(m, f)
	cyl(m, f, 0, 0.12, 0, 5.0, 0.25, "sand", "Base")
	cyl(m, f, 0, 0.37, 0, 4.25, 0.25, "white", "Base")
	for i = 0, 2 do
		local dia = 3.75 - i * 1.0
		local y = 0.75 + i * 1.25
		cyl(m, f, 0, y + 0.37, 0, dia, 0.75, if i % 2 == 0 then "coral" else "gold", "Band")
		cyl(m, f, 0, y + 0.85, 0, dia + 0.25, 0.25, if i % 2 == 0 then "gold" else "coral", "Rim")
		local n = 8 - i * 2
		for k = 0, n - 1 do
			local a = k * 2 * PI / n
			local x, z = math.sin(a) * dia / 2, math.cos(a) * dia / 2
			at(m, f, CFrame.new(x, y + 1.2, z) * CFrame.Angles(0, a, 0), 0.25, 0.5, 0.25, "gold", "Point")
			ball(m, f, x, y + 1.5, z, 0.25, "white", "Pearl")
		end
	end
	ball(m, f, 0, 4.65, 0, 0.75, "white", "GreatPearl").Material = Enum.Material.Neon
	for k = 0, 5 do
		local a = k * PI / 3 + 0.3
		ball(m, f, math.sin(a) * 2.25, 0.35, math.cos(a) * 2.25, 0.5, if k % 2 == 0 then "pink" else "cream", "Shell")
	end
end

-- Big Wheel (4 x 2): a ferris wheel on two A-frame legs, its rim and spokes in white, six little cars in bright colours
-- hanging from it, lights on the hub and the rim.
M.bigwheel = function(m, f)
	box(m, f, 0, 0.12, 0, 4, 0.25, 2, "pavement", "Base")
	local hub = V(0, 2.25, 0)
	for _, sz in { -0.75, 0.75 } do
		beam(m, f, V(-1.25, 0.25, sz), V(0, 2.25, sz), 0.25, "steel_dark", "Leg")
		beam(m, f, V(1.25, 0.25, sz), V(0, 2.25, sz), 0.25, "steel_dark", "Leg")
	end
	rod(m, f, CFrame.new(hub) * CFrame.Angles(0, PI / 2, 0), 1.75, 0.5, "steel", "Axle")
	disc(m, f, 0, 2.25, 0, 0.75, 0.5, "yellow", "Hub", true)
	local r = 1.75
	for k = 0, 11 do
		local a = k * PI / 6
		local p = V(math.sin(a) * r, 2.25 + math.cos(a) * r, 0)
		local q = V(math.sin(a + PI / 6) * r, 2.25 + math.cos(a + PI / 6) * r, 0)
		beam(m, f, p, q, 0.25, "white", "Rim")
		if k % 2 == 0 then
			beam(m, f, hub, p, 0.25, "white", "Spoke")
			box(m, f, p.X, p.Y - 0.5, 0.35, 0.5, 0.5, 0.5, ({ "berry_red", "teal", "yellow", "purple", "orange", "pink" })[k // 2 + 1], "Car")
		else
			glow(m, f, p.X, p.Y, 0.15, 0.25, 0.25, 0.25, "yellow", "Bulb")
		end
	end
end

return M
