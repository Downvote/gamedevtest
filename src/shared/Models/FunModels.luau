--!strict
-- The things to do, seats, lights and the grand pieces (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
-- Since the request of 2026-11-19 ("detail all decor more, some having animations, as much as in the bakery game and
-- as much as the work/hut/ main buildings") each piece carries the small things that make it read up close: trims,
-- steps and caps, planks and bolts, cushions, cups and toys, worn earth under the play things. The camera looks down
-- from the south-east, so the detail sits on the front (+Z), the east side (+X) and the tops, and trims stand an
-- eighth or a sixteenth of a stud proud of the face they are on. The grand pieces stand up to about 12 studs tall.
-- Some parts move in the client (Parts.move): the swings and the porch swing, the seesaw, the merry-go-round, the big
-- wheel, the bell, the lanterns and the string of lights, the telescope, the climbing rope, the koi, and the grand
-- pieces' gems, crescent, pearl and rune ring. Some are named for the island's small effects (Controllers/AmbientView):
-- Flame (sparks go up), Spray (drops thrown up off a jet), Sparkle (a twinkle on a gem), Coals (smoke), Mug and Teapot
-- (steam).
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

-- One moving group (Parts.move): every part the returned function is called on moves with the others, round the same
-- hub, at the same pace and in step.
local function mover(kind: string, hub: Vector3, axis: string, speed: number, amp: number?, phase: number?): (BasePart) -> BasePart
	return function(p: BasePart): BasePart
		return Parts.move(p, kind, hub, axis, speed, amp, phase)
	end
end

-- A rope or wire sagging from a to b (level ends) by `sag` at its middle, in `n` straight pieces; returns the
-- height of the line at x (for things hung from it). `mv` makes the pieces part of a moving group.
local function sagLine(m: Instance, f: CFrame, x0: number, x1: number, y: number, z: number, sag: number, n: number, color: string, name: string?, mv: ((BasePart) -> BasePart)?): (number) -> number
	local function yAt(x: number): number
		local t = (x - x0) / (x1 - x0) * 2 - 1
		return y - sag * (1 - t * t)
	end
	for k = 0, n - 1 do
		local xa = x0 + (x1 - x0) * k / n
		local xb = x0 + (x1 - x0) * (k + 1) / n
		local p = beam(m, f, V(xa, yAt(xa), z), V(xb, yAt(xb), z), 0.25, color, name or "Line")
		if mv then
			mv(p)
		end
	end
	return yAt
end

-- Round water the filter animates (a basin's, a pond's), its top at y + 0.125.
local function pool(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string?): BasePart
	local p = cyl(m, f, x, y, z, dia, 0.25, color or "water", "Water")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- A jet of water: an upright box the filter animates (a part named Spray on its top throws drops).
local function jet(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string?): BasePart
	local p = box(m, f, x, y, z, w, h, d, color or "foam", "Jet")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- Water running down: a fall, an overflow from a bowl's lip (the filter runs it downward).
local function fall(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string?): BasePart
	local p = box(m, f, x, y, z, w, h, d, color or "foam", "Fall")
	p:SetAttribute("PixelWater", 4)
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

-- A glint: a little four-point star of light, a sparkle in the air, facing the view (it twinkles: Sparkle). `mv`
-- makes it part of a moving group.
local function glint(m: Instance, f: CFrame, x: number, y: number, z: number, color: string?, mv: ((BasePart) -> BasePart)?)
	local c = color or "white"
	local cf = CFrame.new(x, y, z) * CFrame.Angles(0, PI / 4, 0)
	local a = at(m, f, cf, 0.25, 0.75, 0.25, c, "Sparkle", true)
	local b = at(m, f, cf, 0.75, 0.25, 0.25, c, "Glint", true)
	if mv then
		mv(a)
		mv(b)
	end
end

-- A tuft of grass on the lawn (a leaf-coloured one rustles in the wind by itself).
local function tuft(m: Instance, f: CFrame, x: number, y: number, z: number, color: string?)
	ball(m, f, x, y + 0.125, z, 0.25, color or "grass_dark", "Tuft")
end

-- A flower on a leafy clump (butterflies come to parts named Flower).
local function bloom(m: Instance, f: CFrame, x: number, y: number, z: number, color: string)
	ball(m, f, x, y + 0.125, z, 0.25, "leaf", "Tuft")
	ball(m, f, x + 0.0625, y + 0.3125, z + 0.0625, 0.25, color, "Flower")
end

local CORNERS = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

------------------------------------------------------------------ grand pieces
-- Golden Driftling (3 x 3): the bun driftling (DriftModels' long-eared one with the sprout) cast in gold, bigger
-- than life, on a stepped pedestal of pale stone: cream corner pilasters, a gold band under a white cornice, a gold
-- plaque with two lines of letters on the front and a medallion on the east side. The statue is lit in a ramp (yellow
-- belly, muzzle and tail, orange in its ears, its cheeks and between its toes), holds its paws up on short arms and
-- wears an orange collar with a ruby; its dark gem eyes and the ruby twinkle (Sparkle). A red rope sags between two
-- gold posts at the front, coins tossed for luck lie on the steps and flowers are left at its foot.
M.goldstatue = function(m, f)
	box(m, f, 0, 0.125, 0, 3, 0.25, 3, "rock", "Step")
	box(m, f, 0, 0.375, 0, 2.5, 0.25, 2.5, "pavement", "Step")
	box(m, f, 0, 0.625, 0, 2.25, 0.25, 2.25, "cream", "Base")
	box(m, f, 0, 1.375, 0, 1.75, 1.25, 1.75, "white", "Pedestal")
	for _, c in CORNERS do
		box(m, f, c[1] * 0.75, 1.375, c[2] * 0.75, 0.5, 1.25, 0.5, "cream", "Pilaster")
	end
	box(m, f, 0, 2.125, 0, 2.0, 0.25, 2.0, "gold", "Band")
	box(m, f, 0, 2.375, 0, 2.25, 0.25, 2.25, "white", "Cornice")
	box(m, f, 0, 1.375, 0.9375, 1.0, 0.75, 0.25, "gold", "Plaque")
	box(m, f, 0, 1.5, 1.0, 0.75, 0.25, 0.25, "orange", "Letters")
	box(m, f, 0, 1.1875, 1.0, 0.5, 0.25, 0.25, "orange", "Letters")
	rod(m, f, CFrame.new(0.9375, 1.375, 0), 0.25, 0.75, "gold", "Medallion")
	rod(m, f, CFrame.new(1.0, 1.375, 0), 0.25, 0.25, "yellow", "Medallion")
	-- the driftling, standing on the cornice (y0)
	local y0 = 2.5
	ball(m, f, 0, y0 + 1.3, -0.15, 2.25, "gold", "Body")
	ball(m, f, 0, y0 + 1.15, 0.45, 1.5, "yellow", "Belly")
	ball(m, f, 0, y0 + 1.2, -1.1, 0.75, "yellow", "Tail")
	ball(m, f, 0, y0 + 3.05, 0.3, 2.0, "gold", "Head")
	ball(m, f, 0, y0 + 2.75, 1.05, 0.75, "yellow", "Muzzle")
	box(m, f, 0, y0 + 3.0, 1.3, 0.5, 0.25, 0.25, "orange", "Nose")
	cyl(m, f, 0, y0 + 2.25, 0.05, 1.5, 0.25, "orange", "Collar")
	box(m, f, 0, y0 + 2.15, 0.8, 0.25, 0.25, 0.25, "berry_red", "Sparkle")
	for _, s in { -1, 1 } do
		ball(m, f, s * 0.75, y0 + 0.65, -0.2, 1.25, "gold", "Thigh")
		box(m, f, s * 0.65, y0 + 0.125, 0.6, 0.75, 0.25, 1.0, "gold", "Foot")
		box(m, f, s * 0.65, y0 + 0.1875, 1.0625, 0.25, 0.25, 0.25, "orange", "Toes")
		beam(m, f, V(s * 0.85, y0 + 2.05, 0.15), V(s * 0.5, y0 + 1.8, 0.85), 0.5, "gold", "Arm")
		ball(m, f, s * 0.5, y0 + 1.75, 0.95, 0.5, "yellow", "Paw")
		ball(m, f, s * 0.68, y0 + 2.72, 0.95, 0.5, "orange", "Cheek")
		box(m, f, s * 0.45, y0 + 3.3, 1.15, 0.5, 0.5, 0.25, "night", "Sparkle")
		box(m, f, s * 0.45 - 0.12, y0 + 3.42, 1.2, 0.25, 0.25, 0.25, "white", "Shine")
		-- long ears leaning out a little, orange inside
		local ear = CFrame.new(s * 0.5, y0 + 4.55, 0.15) * CFrame.Angles(0, 0, -s * R(10))
		at(m, f, ear, 0.5, 1.75, 0.25, "gold", "Ear")
		at(m, f, ear * CFrame.new(0, -0.1, 0.1), 0.25, 1.25, 0.25, "orange", "EarIn")
	end
	-- the sprout on its head
	box(m, f, 0, y0 + 4.25, 0.25, 0.25, 0.5, 0.25, "gold", "Sprout")
	at(m, f, CFrame.new(0.22, y0 + 4.5, 0.25) * CFrame.Angles(0, 0, R(25)), 0.5, 0.25, 0.25, "yellow", "SproutLeaf")
	at(m, f, CFrame.new(-0.22, y0 + 4.45, 0.25) * CFrame.Angles(0, 0, R(-25)), 0.5, 0.25, 0.25, "gold", "SproutLeaf")
	-- the rope on its posts, along the front of the lower step
	for _, s in { -1, 1 } do
		box(m, f, s * 1.25, 0.625, 1.375, 0.25, 0.75, 0.25, "gold", "RopePost")
		ball(m, f, s * 1.25, 1.0625, 1.375, 0.25, "yellow", "RopeKnob")
	end
	sagLine(m, f, -1.25, 1.25, 0.875, 1.375, 0.25, 4, "berry_red", "Rope")
	-- coins tossed for luck, flowers left at its foot
	for _, c in { { -0.75, 0.375, 1.3 }, { 0.6, 0.375, 1.3 }, { 1.3, 0.375, 0.4 }, { 0.35, 0.625, 1.15 } } do
		cyl(m, f, c[1], c[2], c[3], 0.25, 0.25, "gold", "Coin")
	end
	bloom(m, f, -0.35, 0.25, 1.3, "pink")
	bloom(m, f, 1.3, 0.25, -0.5, "white")
	bloom(m, f, 0.95, 0.25, 1.3, "berry_red")
end

-- Sky Bell Tower (3 x 3): a tall tower of sky-blue stone with white corner stones and bands, a door with lanterns,
-- a step and two little bushes in flower, windows up every face, an open belfry on slim pillars where a big gold
-- bell (yellow at its shoulder, orange at its lip) swings on its beam, a stepped white spire on a gold eave, a gold
-- finial with a red pennant.
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
	-- the door, its arch, its step, two lanterns and two bushes in flower
	for _, s in { -1, 1 } do
		box(m, f, s * 0.5, 1.25, 1.06, 0.25, 1.5, 0.25, "white", "Jamb")
		box(m, f, s * 0.25, 1.75, 1.03, 0.25, 0.25, 0.25, "white", "Arch")
		box(m, f, s * 0.75, 1.75, 1.25, 0.25, 0.5, 0.25, "yellow", "Lantern", true)
		box(m, f, s * 0.75, 2.05, 1.25, 0.25, 0.25, 0.25, "steel_dark", "LanternCap")
		box(m, f, s * 0.875, 0.625, 1.25, 0.5, 0.25, 0.25, "clay", "Planter")
		ball(m, f, s * 0.875, 0.875, 1.25, 0.5, "leaf", "Bush")
		ball(m, f, s * 0.875 + 0.125, 1.0, 1.375, 0.25, if s < 0 then "pink" else "yellow", "Flower")
	end
	box(m, f, 0, 2.06, 1.06, 1.25, 0.25, 0.25, "white", "Lintel")
	box(m, f, 0, 1.12, 1.0, 0.75, 1.25, 0.25, "wood_dark", "Door")
	box(m, f, 0.2, 1.1, 1.1, 0.25, 0.25, 0.25, "gold", "Knob")
	box(m, f, 0, 0.625, 1.25, 1.0, 0.25, 0.25, "rock", "DoorStep")
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
	-- the bell on its beam, swinging toward the view and back (its clapper with it)
	Parts.log(m, f, 0, 7.75, 0, 2.0, 0.25, "wood_dark", "Beam")
	local sw = mover("swing", V(0, 7.75, 0), "X", 1.5, R(14))
	sw(box(m, f, 0, 7.6, 0, 0.25, 0.25, 0.25, "gold", "Crown"))
	sw(cyl(m, f, 0, 7.375, 0, 0.75, 0.25, "yellow", "Bell"))
	sw(cyl(m, f, 0, 7.125, 0, 1.0, 0.25, "gold", "Bell"))
	sw(cyl(m, f, 0, 6.875, 0, 1.25, 0.25, "gold", "Bell"))
	sw(cyl(m, f, 0, 6.625, 0, 1.5, 0.25, "orange", "BellLip"))
	sw(ball(m, f, 0, 6.4, 0, 0.25, "steel_dark", "Clapper"))
	-- the spire
	box(m, f, 0, 8.87, 0, 2.75, 0.25, 2.75, "gold", "Eave")
	for k, w in { 2.25, 1.75, 1.25, 0.75, 0.5 } do
		box(m, f, 0, 8.75 + k * 0.5, 0, w, 0.5, w, "white", "Spire")
	end
	box(m, f, 0, 11.5, 0, 0.25, 0.5, 0.25, "gold", "Finial")
	ball(m, f, 0, 11.85, 0, 0.5, "gold", "Knob")
	box(m, f, 0.3, 11.4, 0, 0.5, 0.25, 0.25, "berry_red", "Pennant")
end

-- Crystal Spire (3 x 3): a tall crystal grown out of a dark rock mound: a great faceted shard (two prisms, one
-- turned on the other) with light along its edges, a ring of smaller shards round its foot leaning out a little,
-- little glowing ones among the rocks, glowing cracks, rune stones at the corners each with a crystal on its cap. Over
-- the point a pink gem with two points turns on itself, and three motes of light circle the spire's top (Sparkle).
M.crystalspire = function(m, f)
	cyl(m, f, 0, 0.12, 0, 3.0, 0.25, "slate", "Platform")
	box(m, f, 0, 0.37, 0, 2.0, 0.5, 2.0, "basalt", "Mound")
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		Parts.turned(m, f, math.cos(a) * 0.85, 0.3, math.sin(a) * 0.85, 0.75, 0.5, 0.75, a, if k % 2 == 0 then "basalt" else "rock_dark", "Rock")
	end
	-- glowing cracks in the rock and across the platform
	box(m, f, 0.6, 0.62, 0.95, 0.75, 0.25, 0.25, "crystal", "Crack", true)
	box(m, f, 1.0, 0.62, -0.2, 0.25, 0.25, 0.5, "crystal", "Crack", true)
	box(m, f, -0.5, 0.2, 1.2, 0.5, 0.25, 0.25, "crystal", "Crack", true)
	box(m, f, 1.2, 0.2, 0.45, 0.25, 0.25, 0.5, "crystal", "Crack", true)
	-- the great shard: a square prism with a turned one inside it (its corners show as a ridge down each face)
	crystal(m, f, CFrame.new(0, 0.5, 0), 1.5, 7.5, "crystal")
	at(m, f, CFrame.new(0, 4.0, 0) * CFrame.Angles(0, PI / 4, 0), 1.5, 7.0, 1.5, "purple", "Facet")
	-- light caught along its edges
	box(m, f, -0.7, 4.5, 0.7, 0.25, 5.0, 0.25, "white", "Shine", true)
	box(m, f, 0.7, 6.0, 0.7, 0.25, 2.0, 0.25, "white", "Sparkle", true)
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
	-- the gem over the point, turning on itself: a wide middle and a stepped point above and below
	local gem = mover("spin", V(0, 0, 0), "Y", 0.9)
	gem(at(m, f, CFrame.new(0, 11.0, 0) * CFrame.Angles(0, PI / 4, 0), 0.75, 0.5, 0.75, "pink", "Sparkle", true))
	gem(at(m, f, CFrame.new(0, 11.375, 0) * CFrame.Angles(0, PI / 4, 0), 0.5, 0.25, 0.5, "pink", "Gem", true))
	gem(at(m, f, CFrame.new(0, 11.625, 0) * CFrame.Angles(0, PI / 4, 0), 0.25, 0.25, 0.25, "white", "Gem", true))
	gem(at(m, f, CFrame.new(0, 10.625, 0) * CFrame.Angles(0, PI / 4, 0), 0.5, 0.25, 0.5, "pink", "Gem", true))
	gem(at(m, f, CFrame.new(0, 10.375, 0) * CFrame.Angles(0, PI / 4, 0), 0.25, 0.25, 0.25, "crystal", "Gem", true))
	-- three motes circling the top of the spire the other way
	local orbit = mover("spin", V(0, 0, 0), "Y", -0.5)
	for k, c in { { y = 9.25, c = "white" }, { y = 9.75, c = "crystal" }, { y = 10.25, c = "pink" } } do
		local a = k * 2 * PI / 3
		orbit(at(m, f, CFrame.new(math.sin(a) * 1.0, c.y, math.cos(a) * 1.0) * CFrame.Angles(R(45), a, R(45)), 0.5, 0.5, 0.5, c.c, if k == 1 then "Sparkle" else "Mote", true))
	end
	-- rune stones at the corners, a crystal on each cap
	for _, c in CORNERS do
		box(m, f, c[1] * 1.1, 0.5, c[2] * 1.1, 0.5, 1.0, 0.5, "slate", "RuneStone")
		box(m, f, c[1] * 1.1, 1.05, c[2] * 1.1, 0.75, 0.25, 0.75, "basalt", "RuneCap")
		box(m, f, c[1] * 1.1, 1.425, c[2] * 1.1, 0.25, 0.5, 0.25, "crystal", if c[2] > 0 then "Sparkle" else "Crystal", true)
		-- the rune on the stone's outer face (toward +Z or -Z)
		local g = f * CFrame.new(c[1] * 1.1, 0, c[2] * 1.1) * CFrame.Angles(0, if c[2] > 0 then 0 else PI, 0)
		box(m, g, 0, 0.55, 0.2, 0.25, 0.5, 0.25, "crystal", "Rune", true)
	end
end

-- Rainbow Arch (5 x 2): a tall gateway of the six colours, red outside to purple inside, its feet in little clouds
-- that glow, flowers by the clouds, stepping stones on the way through. Three stars and a little cloud float round
-- its top, rising and falling a little (the stars twinkle: Sparkle).
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
	-- clouds round both feet, flowers in front of them
	for _, s in { -1, 1 } do
		ball(m, f, s * 1.65, 0.6, 0.15, 1.25, "white", "Cloud", true)
		ball(m, f, s * 2.0, 0.45, 0.5, 0.75, "white", "Cloud", true)
		ball(m, f, s * 1.05, 0.4, 0.5, 0.75, "white", "Cloud", true)
		ball(m, f, s * 2.0, 0.5, -0.45, 0.75, "white", "Cloud", true)
		ball(m, f, s * 1.45, 1.3, 0.0, 0.75, "white", "Cloud", true)
		bloom(m, f, s * 1.35, 0, 0.8, if s < 0 then "pink" else "yellow")
		bloom(m, f, s * 2.25, 0, 0.75, if s < 0 then "white" else "pink")
	end
	-- stepping stones under it
	for _, z in { -0.6, 0, 0.6 } do
		cyl(m, f, z * 0.2, 0.03, z, 0.75, 0.25, "pavement", "SteppingStone")
	end
	-- stars and a little cloud floating round the top
	glint(m, f, -2.05, 7.35, 0.2, "yellow", mover("bob", V(-2.05, 7.35, 0.2), "Z", 1.3, 0.12, 0))
	glint(m, f, 0.7, 8.3, 0.2, "white", mover("bob", V(0.7, 8.3, 0.2), "Z", 1.1, 0.1, 2.1))
	glint(m, f, -0.9, 8.6, 0.2, "yellow", mover("bob", V(-0.9, 8.6, 0.2), "Z", 1.5, 0.1, 4.0))
	local puff = mover("bob", V(1.95, 7.3, 0.15), "Z", 0.9, 0.1, 1.0)
	puff(ball(m, f, 1.9, 7.3, 0.15, 0.75, "white", "Cloud", true))
	puff(ball(m, f, 2.2, 7.15, 0.2, 0.5, "white", "Cloud", true))
end

------------------------------------------------------------------ seats
-- Log Seats (2 x 2): three logs round a stump table on a patch of trodden earth. The logs have pale cut ends with a
-- dark ring in the end the camera sees, a knot in the back one; moss on two, a folded red blanket with a cream stripe
-- on the west one, a red mushroom at the east one's foot. The stump has its bark, a pale top with a ring and three
-- roots; on it a blue mug of something hot (it steams: Mug) and an apple with its leaf. Tufts and a flower round it.
M.logseats = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.75, 0.25, "sand_dark", "Earth")
	cyl(m, f, 0, 0.375, 0, 0.75, 0.75, "wood_dark", "Stump")
	cyl(m, f, 0, 0.6875, 0, 0.5, 0.25, "sand", "CutTop")
	cyl(m, f, 0, 0.75, 0, 0.25, 0.25, "sand_dark", "Ring")
	for _, r in { { 0.45, 0.1 }, { -0.15, 0.45 }, { -0.35, -0.3 } } do
		box(m, f, r[1], 0.125, r[2], 0.25, 0.25, 0.25, "wood_dark", "Root")
	end
	box(m, f, 0.15, 0.9375, 0.12, 0.25, 0.25, 0.25, "blue", "Mug")
	box(m, f, 0.375, 0.9375, 0.12, 0.25, 0.25, 0.25, "cream", "MugHandle")
	ball(m, f, -0.15, 0.9375, -0.1, 0.25, "berry_red", "Apple")
	box(m, f, -0.08, 1.125, -0.08, 0.25, 0.25, 0.25, "green", "AppleLeaf")
	-- the back log along X: bark, pale ends, a ring in its east end, a knot, moss on its top
	Parts.log(m, f, 0, 0.27, -0.75, 0.75, 0.5, "wood", "Log")
	for _, x in { -0.5, 0.5 } do
		Parts.log(m, f, x, 0.27, -0.75, 0.25, 0.5, "sand", "LogEnd")
	end
	Parts.log(m, f, 0.5625, 0.27, -0.75, 0.25, 0.25, "sand_dark", "LogRing")
	ball(m, f, -0.2, 0.3, -0.53, 0.25, "wood_dark", "Knot")
	box(m, f, -0.25, 0.5, -0.8, 0.5, 0.25, 0.25, "moss", "Moss")
	-- the side logs along Z, their front ends to the view
	for _, x in { -0.75, 0.75 } do
		Parts.logZ(m, f, x, 0.27, 0.2, 0.75, 0.5, "wood", "Log")
		for _, z in { -0.3, 0.7 } do
			Parts.logZ(m, f, x, 0.27, z, 0.25, 0.5, "sand", "LogEnd")
		end
		Parts.logZ(m, f, x, 0.27, 0.7625, 0.25, 0.25, "sand_dark", "LogRing")
	end
	box(m, f, 0.75, 0.5, -0.05, 0.25, 0.25, 0.5, "moss", "Moss")
	box(m, f, -0.75, 0.5625, 0.15, 0.5, 0.25, 0.75, "berry_red", "Blanket")
	box(m, f, -0.6875, 0.625, 0.15, 0.5, 0.25, 0.25, "cream", "BlanketStripe")
	box(m, f, 0.35, 0.125, 0.75, 0.25, 0.25, 0.25, "cream", "MushroomStem")
	ball(m, f, 0.35, 0.3, 0.75, 0.25, "berry_red", "MushroomCap")
	tuft(m, f, -0.8, 0, 0.85)
	tuft(m, f, 0.85, 0, -0.85)
	tuft(m, f, -0.85, 0, -0.85, "leaf")
	bloom(m, f, -0.3, 0, 0.8, "yellow")
end

-- Park Bench (3 x 1): green slats on black cast-iron ends: each end a front leg with a curl up to the arm, a back leg
-- running up into the backrest with a knob on top, a seat rail, an arm with a brass cap, a splayed foot under each
-- leg; a middle support under the seat. Two seat slats and two back slats with gaps, a brass plate on the top one. A
-- folded newspaper and a paper cup of coffee (it steams: Mug) are left on the seat; it stands on two paving stones,
-- tufts and a flower at its feet.
M.parkbench = function(m, f)
	for _, x in { -1.15, 1.15 } do
		box(m, f, x, 0.3, 0.3, 0.25, 0.6, 0.25, "black", "Leg")
		beam(m, f, V(x, 0, -0.32), V(x, 1.55, -0.375), 0.25, "black", "Leg")
		ball(m, f, x, 1.65, -0.375, 0.25, "black", "Knob")
		box(m, f, x, 0.5, -0.02, 0.25, 0.25, 0.75, "black", "Rail")
		box(m, f, x, 1.0, 0.0, 0.25, 0.25, 0.75, "black", "Arm")
		box(m, f, x, 0.75, 0.25, 0.25, 0.25, 0.25, "black", "Curl")
		ball(m, f, x, 1.0, 0.375, 0.25, "gold", "ArmCap")
		box(m, f, x, 0.0625, 0.3, 0.5, 0.25, 0.25, "steel_dark", "Foot")
		box(m, f, x, 0.0625, -0.32, 0.5, 0.25, 0.25, "steel_dark", "Foot")
	end
	box(m, f, 0, 0.3, -0.02, 0.25, 0.5, 0.25, "black", "Support")
	for _, z in { 0.25, -0.125 } do
		box(m, f, 0, 0.6875, z, 2.5, 0.25, 0.25, "green", "Slat")
	end
	for _, y in { 1.0, 1.375 } do
		box(m, f, 0, y, -0.32, 2.5, 0.25, 0.25, "green", "Slat")
	end
	box(m, f, 0, 1.36, -0.1875, 0.5, 0.25, 0.25, "gold", "Plate")
	-- left on the seat
	box(m, f, 0.55, 0.875, 0.1, 0.5, 0.25, 0.5, "paper", "Newspaper")
	box(m, f, 0.5, 0.9375, 0.15, 0.25, 0.25, 0.25, "steel", "Headline")
	cyl(m, f, -0.6, 0.9375, 0.2, 0.25, 0.25, "paper", "Mug")
	cyl(m, f, -0.6, 1.125, 0.2, 0.25, 0.25, "wood_dark", "CupLid")
	-- at its feet
	tuft(m, f, -1.35, 0, 0.3)
	tuft(m, f, 1.35, 0, -0.25)
	tuft(m, f, 0.3, 0, 0.35)
	tuft(m, f, -1.35, 0, -0.35, "leaf")
	bloom(m, f, 1.3, 0, 0.3, "pink")
	for _, x in { -1.1, 1.1 } do
		box(m, f, x, -0.0625, 0, 0.75, 0.25, 0.75, "pavement", "Paving")
	end
end

-- Stone Bench (3 x 1): a pale slab with a white inset top on two carved stone legs (a dark foot, a shaft with a
-- carved ring), each on a flat paving stone. Moss in a corner and on a foot, ivy trailing down the east leg. A straw
-- sun hat with a red ribbon and an open blue book are left on it; a teal watering can, pebbles, tufts, a fern
-- and flowers at its feet.
M.stonebench = function(m, f)
	for _, x in { -0.95, 0.95 } do
		box(m, f, x, 0.02, 0, 1.0, 0.25, 0.75, "rock", "Paving")
		box(m, f, x, 0.25, 0, 0.75, 0.25, 0.5, "rock_dark", "Foot")
		box(m, f, x, 0.5, 0, 0.5, 0.25, 0.5, "rock", "Leg")
		box(m, f, x, 0.5, 0.25, 0.25, 0.25, 0.25, "rock_dark", "Carving")
	end
	box(m, f, 0, 0.75, 0, 2.75, 0.25, 0.75, "pavement", "Slab")
	box(m, f, 0, 0.8125, 0, 2.5, 0.25, 0.5, "white", "SlabTop")
	box(m, f, -1.15, 0.9375, -0.2, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, -1.25, 0.3, 0.2, 0.25, 0.25, 0.25, "moss", "Moss")
	ball(m, f, 1.15, 0.55, 0.3, 0.25, "leaf", "Ivy")
	ball(m, f, 1.1, 0.3, 0.33, 0.25, "leaf_dark", "Ivy")
	-- the hat
	cyl(m, f, 0.55, 1.0625, 0.05, 0.75, 0.25, "straw", "Brim")
	cyl(m, f, 0.55, 1.1875, 0.05, 0.5, 0.25, "berry_red", "Ribbon")
	cyl(m, f, 0.55, 1.3125, 0.05, 0.5, 0.25, "straw", "Crown")
	box(m, f, 0.9, 1.0625, 0.15, 0.25, 0.25, 0.25, "berry_red", "Ribbon")
	-- the book, open
	box(m, f, -0.45, 1.0, 0.05, 0.75, 0.25, 0.5, "blue", "Book")
	box(m, f, -0.45, 1.0625, 0.05, 0.5, 0.25, 0.25, "paper", "Pages")
	box(m, f, -0.45, 1.0, 0.3, 0.25, 0.25, 0.25, "berry_red", "Bookmark")
	-- the watering can
	box(m, f, -0.35, 0.125, 0.3, 0.5, 0.25, 0.25, "teal", "Can")
	beam(m, f, V(-0.1, 0.15, 0.3), V(0.15, 0.35, 0.3), 0.25, "teal", "Spout")
	box(m, f, -0.45, 0.375, 0.3, 0.25, 0.25, 0.25, "steel", "CanHandle")
	-- at its feet
	ball(m, f, 0.35, 0.08, 0.35, 0.25, "rock", "Pebble")
	ball(m, f, 0.55, 0.08, 0.3, 0.25, "pavement", "Pebble")
	tuft(m, f, -1.35, 0, -0.3)
	tuft(m, f, 1.35, 0, -0.2)
	tuft(m, f, 0, 0, -0.35)
	Parts.wedge(m, f, 1.35, 0.25, 0.25, 0.25, 0.5, 0.25, "leaf_dark", 0, "Fern")
	bloom(m, f, -1.35, 0, 0.3, "white")
	bloom(m, f, 0.1, 0, 0.3, "yellow")
end

-- Porch Swing (3 x 2): a slatted bench on chains from a timber A-frame (rock footings, braces, steel hooks) under a
-- canopy striped teal and white, a scalloped valance along its front and a white ridge, a little lamp hung under the
-- beam. The bench swings toward the view and back on four chains: a seat, two back slats, posts and arms, a red
-- cushion and a cream pillow. A woven mat under it, flowers either side.
M.porchswing = function(m, f)
	box(m, f, 0, 0.02, 0.1, 2.0, 0.25, 1.25, "straw", "Mat")
	box(m, f, 0, 0.0825, 0.1, 1.5, 0.25, 0.75, "sand_dark", "MatWeave")
	for _, x in { -1.25, 1.25 } do
		for _, z in { -0.85, 0.85 } do
			beam(m, f, V(x, 0, z), V(x, 2.55, 0), 0.25, "wood_dark", "Leg")
			box(m, f, x, 0.0625, z, 0.5, 0.25, 0.25, "rock", "Footing")
		end
		box(m, f, x, 0.75, 0, 0.25, 0.25, 1.25, "wood_dark", "Brace")
	end
	box(m, f, 0, 2.55, 0, 2.75, 0.25, 0.25, "wood", "Beam")
	-- the canopy: the front slope in stripes, the back in teal, a white ridge, a valance along the front
	for k = 0, 5 do
		Parts.wedge(m, f, -1.25 + k * 0.5, 2.95, 0.375, 0.5, 0.5, 0.75, if k % 2 == 0 then "teal" else "white", PI, "Canopy")
		box(m, f, -1.25 + k * 0.5, 2.5625, 0.6875, 0.5, 0.25, 0.25, if k % 2 == 0 then "white" else "teal", "Valance")
	end
	Parts.wedge(m, f, 0, 2.95, -0.375, 3.0, 0.5, 0.75, "teal", 0, "Canopy")
	box(m, f, 0, 3.25, 0, 3.0, 0.25, 0.25, "white", "Ridge")
	box(m, f, 0, 2.625, -0.6875, 3.0, 0.25, 0.25, "white", "Trim")
	for _, x in { -0.95, 0.95 } do
		box(m, f, x, 2.4375, 0, 0.25, 0.25, 0.25, "steel_dark", "Hook")
	end
	-- the little lamp under the beam
	box(m, f, 0, 2.3125, 0, 0.25, 0.25, 0.25, "black", "LampCap")
	glow(m, f, 0, 2.0625, 0, 0.25, 0.25, 0.25, "yellow", "Lamp")
	-- the bench (swinging on its chains round the hooks)
	local sw = mover("swing", V(0, 2.4375, 0), "X", 1.2, R(10))
	sw(box(m, f, 0, 0.8, 0, 1.75, 0.25, 0.75, "wood", "Seat"))
	for _, y in { 1.1, 1.45 } do
		sw(box(m, f, 0, y, -0.3, 1.75, 0.25, 0.25, "wood", "Slat"))
	end
	for _, x in { -0.95, 0.95 } do
		sw(box(m, f, x, 1.2, -0.3, 0.25, 1.0, 0.25, "wood_dark", "BackPost"))
		sw(box(m, f, x, 1.15, 0.0, 0.25, 0.25, 0.75, "wood_dark", "Arm"))
		sw(beam(m, f, V(x, 2.4375, 0), V(x, 1.275, 0.3), 0.25, "steel_dark", "Chain"))
		sw(beam(m, f, V(x, 2.4375, 0), V(x, 1.7, -0.3), 0.25, "steel_dark", "Chain"))
	end
	sw(box(m, f, 0, 0.9375, 0.05, 1.5, 0.25, 0.5, "berry_red", "Cushion"))
	sw(at(m, f, CFrame.new(-0.55, 1.2, -0.12) * CFrame.Angles(R(-15), 0, 0), 0.5, 0.5, 0.25, "cream", "Pillow"))
	-- flowers either side
	for _, s in { -1, 1 } do
		bloom(m, f, s * 1.3, 0, 0.3, if s < 0 then "pink" else "white")
		tuft(m, f, s * 1.35, 0, -0.35)
	end
end

------------------------------------------------------------------ lights
-- Garden Lights (1 x 1): a strip of border with a lamp on a post (a dark footing, a steel holder, a round lit globe
-- with a gold finial), a little stake light at the back, flowers on leafy clumps and a tall one on its stem, edging
-- stones and pebbles along the front (they run on into the next piece).
M.gardenlights = function(m, f)
	box(m, f, 0, 0.02, -0.12, 1.0, 0.25, 0.5, "wood_dark", "Bed")
	box(m, f, -0.25, 0.05, 0.25, 0.5, 0.25, 0.25, "rock", "Edging")
	box(m, f, 0.25, 0.05, 0.25, 0.5, 0.25, 0.25, "pavement", "Edging")
	ball(m, f, -0.3, 0.2, 0.32, 0.25, "rock_dark", "Pebble")
	ball(m, f, 0.2, 0.2, 0.35, 0.25, "rock", "Pebble")
	-- the lamp
	box(m, f, 0, 0.125, -0.12, 0.5, 0.25, 0.5, "rock_dark", "Footing")
	box(m, f, 0, 0.625, -0.12, 0.25, 0.75, 0.25, "steel_dark", "Post")
	cyl(m, f, 0, 1.0625, -0.12, 0.5, 0.25, "steel", "Holder")
	ball(m, f, 0, 1.375, -0.12, 0.5, "yellow", "Lamp", true)
	ball(m, f, 0, 1.6875, -0.12, 0.25, "gold", "Finial")
	-- the little stake light
	box(m, f, 0.35, 0.3, -0.35, 0.25, 0.5, 0.25, "steel", "Stake")
	glow(m, f, 0.35, 0.625, -0.35, 0.25, 0.25, 0.25, "yellow", "Light")
	box(m, f, 0.35, 0.875, -0.35, 0.25, 0.25, 0.25, "steel_dark", "StakeCap")
	-- flowers and leaves
	bloom(m, f, -0.35, 0.1, 0.0, "pink")
	bloom(m, f, -0.3, 0.1, -0.35, "white")
	bloom(m, f, 0.3, 0.1, 0.0, "yellow")
	box(m, f, -0.375, 0.5, -0.125, 0.25, 0.5, 0.25, "leaf_dark", "Stem")
	ball(m, f, -0.375, 0.8125, -0.125, 0.25, "purple", "Flower")
	tuft(m, f, 0.15, 0.1, 0.05, "leaf")
end

-- Fire Pit (2 x 2): a ring of stones (three greys) round grey ash on worn earth, a tent of sticks burning with a log
-- across it (its end charred), flames (sparks go up off them: Flame) and embers in the ash. A black kettle warms on the
-- stones at the back (it steams: Teapot), a stick with a marshmallow leans in, and two split logs wait at the side.
M.firepit = function(m, f)
	cyl(m, f, 0, 0.02, 0, 2.0, 0.25, "sand_dark", "Earth")
	cyl(m, f, 0, 0.08, 0, 1.25, 0.25, "basalt", "Ash")
	for k = 0, 9 do
		local a = k * PI / 5 + 0.2
		ball(m, f, math.cos(a) * 0.72, 0.15, math.sin(a) * 0.72, 0.5, ({ "rock", "rock_dark", "pavement" })[k % 3 + 1], "Stone")
	end
	for k = 0, 3 do
		local a = k * PI / 2 + 0.4
		beam(m, f, V(math.cos(a) * 0.4, 0.1, math.sin(a) * 0.4), V(0, 0.8, 0), 0.25, "wood_dark", "Stick")
	end
	Parts.log(m, f, 0, 0.25, 0.15, 0.75, 0.25, "wood", "Log")
	Parts.log(m, f, 0.4375, 0.25, 0.15, 0.25, 0.25, "black", "Charred")
	glow(m, f, 0, 0.45, 0, 0.5, 0.5, 0.5, "orange", "Fire")
	glow(m, f, 0.05, 0.8, 0.05, 0.25, 0.5, 0.25, "yellow", "Flame")
	glow(m, f, -0.15, 0.85, -0.12, 0.25, 0.25, 0.25, "orange", "Fire")
	glow(m, f, 0.2, 0.65, 0.15, 0.25, 0.25, 0.25, "yellow", "Flame")
	glow(m, f, -0.3, 0.15, 0.25, 0.25, 0.25, 0.25, "lava", "Ember")
	glow(m, f, 0.3, 0.15, -0.25, 0.25, 0.25, 0.25, "lava", "Ember")
	glow(m, f, -0.2, 0.15, -0.35, 0.25, 0.25, 0.25, "orange", "Ember")
	-- the kettle on the stones at the back
	ball(m, f, 0.45, 0.6, -0.55, 0.5, "black", "Teapot")
	box(m, f, 0.45, 0.6, -0.25, 0.25, 0.25, 0.25, "black", "Spout")
	ball(m, f, 0.45, 0.85, -0.55, 0.25, "steel", "Lid")
	-- the marshmallow stick
	beam(m, f, V(0.85, 0.35, 0.65), V(0.4, 0.75, 0.3), 0.25, "wood", "Stick")
	box(m, f, 0.35, 0.78, 0.27, 0.25, 0.25, 0.25, "white", "Marshmallow")
	-- two split logs at the front corner, their pale ends to the view
	for _, y in { 0.125, 0.375 } do
		Parts.log(m, f, -0.75, y, 0.85, 0.5, 0.25, "wood_dark", "Firewood")
		Parts.log(m, f, -0.45, y, 0.85, 0.25, 0.25, "sand", "LogEnd")
	end
end

-- Candles (1 x 1): three pillar candles of three heights and colours on a round slate stone, each with wax run down
-- its side, a wick and a flame in two parts (sparks rise off the top one: Flame); two tea lights in steel cups and a
-- patch of moss on the stone.
M.candles = function(m, f)
	cyl(m, f, 0, 0.12, 0, 1.0, 0.25, "slate", "Stone")
	box(m, f, -0.375, 0.2, -0.1, 0.25, 0.25, 0.25, "moss", "Moss")
	-- side by side across the view, the tallest in the middle
	for _, c in { { x = -0.22, z = 0.15, h = 0.75, c = "berry_red", d = "pink" }, { x = 0.0, z = -0.08, h = 1.0, c = "cream", d = "white" }, { x = 0.15, z = -0.2, h = 0.5, c = "white", d = "cream" } } do
		local x, z, h = c.x, c.z, c.h
		cyl(m, f, x, 0.25 + h / 2, z, 0.5, h, c.c, "Candle")
		box(m, f, x, 0.25 + h - 0.125, z + 0.1875, 0.25, 0.25, 0.25, c.d, "Drip")
		box(m, f, x + 0.1875, 0.25 + h - 0.25, z, 0.25, 0.5, 0.25, c.d, "Drip")
		box(m, f, x, 0.3 + h, z, 0.25, 0.25, 0.25, "black", "Wick")
		glow(m, f, x, 0.45 + h, z, 0.25, 0.25, 0.25, "orange", "Fire")
		glow(m, f, x, 0.65 + h, z, 0.25, 0.25, 0.25, "yellow", "Flame")
	end
	-- two tea lights
	for _, t in { { 0.3, 0.2 }, { -0.3, -0.3 } } do
		cyl(m, f, t[1], 0.3125, t[2], 0.25, 0.25, "steel", "TeaLight")
		glow(m, f, t[1], 0.5, t[2], 0.25, 0.25, 0.25, "yellow", "Light")
	end
end

-- Paper Lanterns (2 x 1): two posts on stone feet with pale caps and gold finials, a rope sagging between them, three
-- round paper lanterns aglow hanging off it (the bigger orange one in the middle lower, on a string), each with a
-- dark wooden cap, a darker rib round its middle and a gold tassel; each swings a little on the rope, out of step
-- with the others. Tufts and flowers at the posts' feet.
M.paperlanterns = function(m, f)
	for _, s in { -1, 1 } do
		box(m, f, s * 0.75, 0.08, 0, 0.5, 0.25, 0.5, "rock", "Base")
		box(m, f, s * 0.85, 1.0, 0, 0.25, 2.0, 0.25, "wood_dark", "Post")
		box(m, f, s * 0.85, 2.0625, 0, 0.25, 0.25, 0.25, "wood", "Cap")
		ball(m, f, s * 0.85, 2.3, 0, 0.25, "gold", "Finial")
		tuft(m, f, s * 0.65, 0.1, 0.3)
		bloom(m, f, s * 0.6, 0, -0.3, if s < 0 then "pink" else "yellow")
	end
	local yAt = sagLine(m, f, -0.85, 0.85, 1.85, 0, 0.25, 4, "wood_dark", "Rope")
	local list = {
		{ x = -0.45, d = 0.5, c = "berry_red", rib = "brick", drop = 0 },
		{ x = 0, d = 0.75, c = "orange", rib = "lava", drop = 0.25 },
		{ x = 0.45, d = 0.5, c = "berry_red", rib = "brick", drop = 0 },
	}
	for k, l in list do
		local top = yAt(l.x)
		local sw = mover("swing", V(l.x, top, 0), "X", 1.2 + k * 0.2, if l.drop > 0 then R(8) else R(12), k * 1.7)
		if l.drop > 0 then
			sw(box(m, f, l.x, top - l.drop / 2, 0, 0.25, l.drop, 0.25, "black", "String"))
		end
		sw(box(m, f, l.x, top - l.drop - 0.125, 0, if l.d > 0.5 then 0.5 else 0.25, 0.25, if l.d > 0.5 then 0.5 else 0.25, "wood_dark", "LanternCap"))
		local y = top - l.drop - 0.25 - l.d / 2
		sw(ball(m, f, l.x, y, 0, l.d, l.c, "Lantern", true))
		sw(cyl(m, f, l.x, y, 0, l.d, 0.25, l.rib, "Rib"))
		sw(box(m, f, l.x, y - l.d / 2 - 0.125, 0, 0.25, 0.25, 0.25, "gold", "Tassel"))
	end
end

-- String Lights (3 x 1): two poles on stone footings, each with a steel band, a cap, a short arm the wire hangs from,
-- a little flag and a guy rope to a stake behind it; a wire sagging between them with five round bulbs of party
-- colours hung off it. The wire and its bulbs sway a little in the breeze. Tufts and flowers at the poles' feet.
M.stringlights = function(m, f)
	for _, s in { -1, 1 } do
		box(m, f, s * 1.25, 0.0625, 0, 0.5, 0.25, 0.5, "rock", "Footing")
		box(m, f, s * 1.2, 1.25, 0, 0.25, 2.5, 0.25, "wood_dark", "Pole")
		box(m, f, s * 1.2, 0.5, 0, 0.5, 0.25, 0.5, "steel", "Band")
		box(m, f, s * 1.2, 2.5625, 0, 0.5, 0.25, 0.5, "wood", "Cap")
		box(m, f, s * 1.05, 2.25, 0, 0.5, 0.25, 0.25, "wood", "Arm")
		box(m, f, s * 0.95, 2.875, 0, 0.5, 0.25, 0.25, if s < 0 then "berry_red" else "yellow", "Pennant")
		box(m, f, s * 1.2, 2.8125, 0, 0.25, 0.25, 0.25, "steel_dark", "FlagPole")
		tuft(m, f, s * 1.05, 0, 0.3)
		beam(m, f, V(s * 1.2, 2.3, -0.1), V(s * 1.35, 0.1, -0.35), 0.25, "straw", "GuyRope")
		box(m, f, s * 1.35, 0.125, -0.35, 0.25, 0.25, 0.25, "wood_dark", "Stake")
		bloom(m, f, s * 0.95, 0, -0.3, if s < 0 then "white" else "pink")
	end
	local sw = mover("swing", V(0, 2.125, 0), "X", 1.1, R(14))
	local yAt = sagLine(m, f, -1.0, 1.0, 2.125, 0, 0.4, 4, "steel_dark", "Wire", sw)
	local cols = { "yellow", "berry_red", "blue", "green", "orange" }
	for k = 0, 4 do
		local x = -0.8 + k * 0.4
		sw(ball(m, f, x, yAt(x) - 0.3125, 0, 0.5, cols[k + 1], "Bulb", true))
	end
end

------------------------------------------------------------------ play
-- Sandbox (2 x 2): a timber frame (boards with a darker seam, corner seats) round the sand, the sand raked in places.
-- A sand castle (a keep with a gate, two towers, a red flag on a stick), a heap with a red spade stuck in it, a bucket
-- (blue below, yellow at the lip, full of sand), a green rake, a beach ball, a shell and a starfish.
M.sandbox = function(m, f)
	for _, z in { -0.8125, 0.8125 } do
		box(m, f, 0, 0.25, z, 1.75, 0.5, 0.25, "wood", "Board")
	end
	for _, x in { -0.8125, 0.8125 } do
		box(m, f, x, 0.25, 0, 0.25, 0.5, 1.5, "wood", "Board")
	end
	box(m, f, 0, 0.25, 0.875, 1.5, 0.25, 0.25, "wood_dark", "Seam")
	box(m, f, 0.875, 0.25, 0, 0.25, 0.25, 1.25, "wood_dark", "Seam")
	for _, c in CORNERS do
		box(m, f, c[1] * 0.75, 0.5625, c[2] * 0.75, 0.5, 0.25, 0.5, "wood_dark", "Seat")
	end
	box(m, f, 0, 0.3125, 0, 1.5, 0.25, 1.5, "sand", "Sand")
	box(m, f, 0.2, 0.375, 0.1, 0.75, 0.25, 0.25, "sand_dark", "Raked")
	box(m, f, 0.2, 0.375, -0.25, 0.75, 0.25, 0.25, "sand_dark", "Raked")
	-- the castle
	box(m, f, -0.3, 0.5625, -0.35, 0.75, 0.25, 0.5, "sand_dark", "Castle")
	box(m, f, -0.3, 0.5625, -0.0625, 0.25, 0.25, 0.25, "wood_dark", "Gate")
	for _, x in { -0.55, -0.05 } do
		box(m, f, x, 0.8125, -0.45, 0.25, 0.5, 0.25, "sand_dark", "Tower")
	end
	box(m, f, -0.55, 1.25, -0.45, 0.25, 0.5, 0.25, "wood", "FlagPole")
	box(m, f, -0.375, 1.375, -0.45, 0.25, 0.25, 0.25, "berry_red", "Flag")
	-- the heap and the spade in it
	ball(m, f, 0.4, 0.45, -0.4, 0.5, "sand", "Heap")
	beam(m, f, V(0.4, 0.55, -0.4), V(0.55, 1.15, -0.3), 0.25, "berry_red", "Handle")
	box(m, f, 0.57, 1.2, -0.29, 0.5, 0.25, 0.25, "berry_red", "Grip")
	-- the bucket
	cyl(m, f, 0.35, 0.5625, 0.35, 0.5, 0.25, "blue", "Bucket")
	cyl(m, f, 0.35, 0.8125, 0.35, 0.75, 0.25, "yellow", "Rim")
	cyl(m, f, 0.35, 0.875, 0.35, 0.5, 0.25, "sand", "Sand")
	-- the rake, the ball, a shell and a starfish
	beam(m, f, V(-0.55, 0.47, 0.5), V(0.0, 0.47, 0.55), 0.25, "green", "RakeHandle")
	box(m, f, -0.6, 0.47, 0.45, 0.25, 0.25, 0.5, "green", "Rake")
	ball(m, f, -0.15, 0.6875, 0.05, 0.5, "berry_red", "Ball")
	cyl(m, f, -0.15, 0.6875, 0.05, 0.5, 0.25, "white", "BallBand")
	box(m, f, 0.6, 0.45, -0.05, 0.25, 0.25, 0.25, "pink", "Shell")
	box(m, f, -0.45, 0.42, 0.2, 0.5, 0.25, 0.25, "orange", "Starfish")
	box(m, f, -0.45, 0.42, 0.2, 0.25, 0.25, 0.5, "orange", "Starfish")
end

-- Seesaw (3 x 1): a yellow plank with an orange rib under it, a steel plate at its middle, on a steel axle between
-- two blue A-frames on a base plate. It rocks on its axle: red seats, steel handles with blue grips across them,
-- black bumpers under its ends. Half-buried tyres under both ends on worn grass, tufts and flowers.
M.seesaw = function(m, f)
	for _, s in { -1, 1 } do
		box(m, f, s * 1.1, 0.02, 0, 0.75, 0.25, 0.75, "sand_dark", "Worn")
		Parts.logZ(m, f, s * 1.15, 0.0, 0, 0.25, 0.5, "black", "Tyre")
		Parts.logZ(m, f, s * 1.15, 0.0, 0, 0.5, 0.25, "steel_dark", "TyreHub")
		tuft(m, f, s * 1.35, 0, -0.35)
		bloom(m, f, s * 0.6, 0, 0.3, if s < 0 then "pink" else "white")
		bloom(m, f, s * 0.65, 0, -0.35, if s < 0 then "yellow" else "pink")
	end
	box(m, f, 0, 0.0625, 0, 1.0, 0.25, 1.0, "steel_dark", "Base")
	for _, x in { -0.375, 0.375 } do
		box(m, f, x, 0.1875, 0.375, 0.25, 0.25, 0.25, "steel", "Bolt")
	end
	for _, z in { -0.375, 0.375 } do
		Parts.wedge(m, f, -0.25, 0.625, z, 0.25, 0.75, 0.5, "blue", PI / 2, "Pivot")
		Parts.wedge(m, f, 0.25, 0.625, z, 0.25, 0.75, 0.5, "blue", -PI / 2, "Pivot")
	end
	Parts.logZ(m, f, 0, 0.9, 0, 1.0, 0.25, "steel", "Axle")
	-- the plank and all on it, rocking round the axle
	local sw = mover("swing", V(0, 0.9, 0), "Z", 1.3, R(11))
	sw(box(m, f, 0, 0.9, 0, 2.75, 0.25, 0.5, "yellow", "Plank"))
	sw(box(m, f, 0, 0.75, 0, 2.5, 0.25, 0.25, "orange", "PlankRib"))
	sw(box(m, f, 0, 1.0625, 0, 0.5, 0.25, 0.25, "steel", "Plate"))
	for _, s in { -1, 1 } do
		sw(box(m, f, s * 1.05, 1.125, 0, 0.5, 0.25, 0.5, "berry_red", "Seat"))
		sw(box(m, f, s * 0.65, 1.3, 0, 0.25, 0.5, 0.25, "steel", "Handle"))
		sw(box(m, f, s * 0.65, 1.55, 0, 0.25, 0.25, 0.75, "blue", "Grip"))
		sw(box(m, f, s * 1.25, 0.65, 0, 0.25, 0.25, 0.25, "black", "Bumper"))
	end
end

-- Swing Set (3 x 2): a blue A-frame with a brace across each end, steel brackets at the top, rock anchors at its feet
-- and a top bar with black hooks; two swings on dark chains (red and yellow seats with black rubber under, the chains
-- at the seat's ends, spread as wide as the frame allows), each swinging round the bar, out of step. Worn earth under
-- each, tufts, flowers and a ball.
M.swing = function(m, f)
	for _, x in { -1.375, 1.375 } do
		for _, z in { -0.85, 0.85 } do
			beam(m, f, V(x, 0, z), V(x, 2.45, 0), 0.25, "blue", "Leg")
			box(m, f, x - math.sign(x) * 0.125, 0.0625, z, 0.5, 0.25, 0.25, "rock", "Anchor")
		end
		box(m, f, x, 0.8, 0, 0.25, 0.25, 1.25, "blue", "Brace")
		box(m, f, x, 2.45, 0, 0.25, 0.5, 0.5, "steel_dark", "Bracket")
	end
	Parts.log(m, f, 0, 2.45, 0, 2.75, 0.25, "blue", "Bar")
	for i, s in { { x = -0.65625, c = "berry_red" }, { x = 0.65625, c = "yellow" } } do
		local x = s.x
		box(m, f, x, 0.02, 0, 1.0, 0.25, 1.25, "sand_dark", "Worn")
		for _, dx in { -0.40625, 0.40625 } do
			box(m, f, x + dx, 2.3, 0, 0.25, 0.25, 0.25, "black", "Hook")
		end
		-- (each seat swings on its chains round the bar, the two out of step)
		local hub = V(x, 2.4, 0)
		local sw = mover("swing", hub, "X", 1.9, R(16), if i == 1 then 0 else 2.2)
		local len = 1.75
		for _, dx in { -0.40625, 0.40625 } do
			sw(box(m, f, x + dx, 2.4 - len / 2, 0, 0.25, len, 0.25, "steel_dark", "Chain"))
		end
		sw(box(m, f, x, 0.55, 0, 1.0, 0.25, 0.5, s.c, "Seat"))
		sw(box(m, f, x, 0.4375, 0, 0.75, 0.25, 0.5, "black", "Rubber"))
	end
	for _, t in { { -1.0, 0.75 }, { 1.0, -0.75 }, { 0, 0.85 }, { -0.1, -0.8 } } do
		tuft(m, f, t[1], 0, t[2])
	end
	bloom(m, f, 1.0, 0, 0.75, "pink")
	bloom(m, f, -1.0, 0, -0.7, "white")
	ball(m, f, 0.05, 0.25, 0.65, 0.5, "orange", "Ball")
end

-- Slide (3 x 2): a little tower (a deck on blue posts with a dark edge, yellow rails with posts, a white eave under a
-- red roof with a white ridge, a yellow flag on its pole), a ladder of yellow rails and steel rungs up its front. A
-- yellow chute with red walls and a lip at the top runs down on a prop to a patch of sand with a footprint and a ball
-- in it; tufts and flowers round its feet.
M.slide = function(m, f)
	local tx = -0.875
	for _, x in { tx - 0.325, tx + 0.325 } do
		for _, z in { -0.35, 0.35 } do
			box(m, f, x, 1.375, z, 0.25, 2.75, 0.25, "blue", "Post")
		end
	end
	box(m, f, tx, 1.5, 0, 1.0, 0.25, 1.0, "wood", "Deck")
	box(m, f, tx, 1.4375, 0.4375, 1.0, 0.25, 0.25, "wood_dark", "DeckEdge")
	box(m, f, tx, 2.0, -0.35, 0.75, 0.25, 0.25, "yellow", "Rail")
	box(m, f, tx - 0.325, 2.0, 0, 0.25, 0.25, 0.75, "yellow", "Rail")
	box(m, f, tx, 1.75, -0.35, 0.25, 0.25, 0.25, "yellow", "RailPost")
	box(m, f, tx - 0.325, 1.75, 0, 0.25, 0.25, 0.25, "yellow", "RailPost")
	box(m, f, tx, 2.8, 0, 1.25, 0.25, 1.25, "white", "Eave")
	Parts.wedge(m, f, tx, 3.18, -0.25, 1.25, 0.5, 0.5, "berry_red", 0, "Roof")
	Parts.wedge(m, f, tx, 3.18, 0.25, 1.25, 0.5, 0.5, "berry_red", PI, "Roof")
	box(m, f, tx, 3.45, 0, 1.25, 0.25, 0.25, "white", "Ridge")
	box(m, f, tx, 3.85, 0, 0.25, 0.75, 0.25, "steel_dark", "FlagPole")
	Parts.wedge(m, f, tx + 0.5, 3.97, 0, 0.25, 0.5, 0.75, "yellow", -PI / 2, "Flag")
	-- the ladder down the front
	for _, x in { tx - 0.3, tx + 0.3 } do
		beam(m, f, V(x, 0, 0.85), V(x, 1.65, 0.45), 0.25, "yellow", "LadderRail")
	end
	for k = 1, 3 do
		local t = k / 4
		box(m, f, tx, t * 1.65, 0.85 - t * 0.4, 0.5, 0.25, 0.25, "steel", "Rung")
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
	box(m, f, -0.375, 1.75, 0, 0.25, 0.25, 0.75, "berry_red", "Lip")
	box(m, f, 1.2, 0.25, 0, 0.5, 0.25, 0.75, "yellow", "RunOut")
	box(m, f, 0.5, 0.4, 0, 0.25, 0.75, 0.25, "blue", "Prop")
	-- the sand, a ball in it, and the grass round its feet
	box(m, f, 1.1, 0.02, 0, 0.75, 0.25, 1.5, "sand", "Sand")
	box(m, f, 1.1, 0.06, 0.55, 0.5, 0.25, 0.25, "sand_dark", "Footprint")
	ball(m, f, 1.25, 0.3, 0.75, 0.5, "blue", "Ball")
	tuft(m, f, 0.3, 0, 0.8)
	tuft(m, f, 0.4, 0, -0.8)
	tuft(m, f, -1.35, 0, 0.8, "leaf")
	bloom(m, f, 0.0, 0, 0.75, "pink")
	bloom(m, f, -1.35, 0, -0.75, "yellow")
end

-- Trampoline (3 x 3): a round black mat with a target ring on it, in a padded rim of blue and teal pads over a steel
-- frame, on six legs bent in three pairs (each pair joined by a rail on the grass) on a darker patch of lawn. A
-- little ladder up the front, a red and white ball on the mat, two pairs of shoes kicked off by the ladder, a water
-- bottle, tufts.
M.trampoline = function(m, f)
	cyl(m, f, 0, 0.02, 0, 2.75, 0.25, "grass_dark", "Lawn")
	for k = 0, 2 do
		local a0 = k * 2 * PI / 3 + PI / 6
		local a1 = a0 + PI / 3
		local p0 = V(math.cos(a0) * 1.15, 0, math.sin(a0) * 1.15)
		local p1 = V(math.cos(a1) * 1.15, 0, math.sin(a1) * 1.15)
		for _, p in { p0, p1 } do
			box(m, f, p.X, 0.375, p.Z, 0.25, 0.75, 0.25, "steel_dark", "Leg")
		end
		beam(m, f, p0 + V(0, 0.125, 0), p1 + V(0, 0.125, 0), 0.25, "steel_dark", "Rail")
	end
	cyl(m, f, 0, 0.625, 0, 3.0, 0.25, "steel", "Frame")
	cyl(m, f, 0, 0.875, 0, 2.75, 0.25, "blue", "Padding")
	cyl(m, f, 0, 0.9375, 0, 2.25, 0.25, "black", "Mat")
	cyl(m, f, 0, 1.0, 0, 1.0, 0.25, "slate", "Target")
	cyl(m, f, 0, 1.0625, 0, 0.5, 0.25, "black", "Target")
	for k = 0, 11 do
		local a = k * PI / 6
		Parts.turned(m, f, math.sin(a) * 1.25, 1.125, math.cos(a) * 1.25, 0.75, 0.25, 0.25, a, if k % 2 == 0 then "blue" else "teal", "Pad")
	end
	-- the ladder
	for _, x in { -0.3, 0.3 } do
		box(m, f, x, 0.375, 1.35, 0.25, 0.75, 0.25, "steel_dark", "LadderRail")
	end
	for _, y in { 0.2, 0.45 } do
		box(m, f, 0, y, 1.35, 0.75, 0.25, 0.25, "steel", "Step")
	end
	-- the ball on the mat, the shoes, the bottle
	ball(m, f, 0.45, 1.3125, -0.3, 0.5, "berry_red", "Ball")
	cyl(m, f, 0.45, 1.3125, -0.3, 0.5, 0.25, "white", "BallBand")
	for _, s in { { x = 0.65, z = 1.25, c = "blue" }, { x = 0.95, z = 1.2, c = "blue" }, { x = -0.7, z = 1.25, c = "pink" }, { x = -0.95, z = 1.1, c = "pink" } } do
		box(m, f, s.x, 0.125, s.z, 0.25, 0.25, 0.5, s.c, "Shoe")
	end
	cyl(m, f, 1.15, 0.25, 0.95, 0.25, 0.5, "blue", "Bottle")
	cyl(m, f, 1.15, 0.5625, 0.95, 0.25, 0.25, "white", "BottleCap")
	for _, t in { { 1.3, -0.6 }, { -1.3, -0.6 }, { 0.0, -1.35 }, { -1.25, 0.65 }, { 1.35, 0.3 }, { -0.6, -1.3 } } do
		tuft(m, f, t[1], 0, t[2])
	end
end

-- Merry-Go-Round (3 x 3): a little round ride: a red skirt and a cream deck, a red drum with gold panels, a gold band
-- and column, a striped stepped canopy with lights round its rim, a scalloped trim, a gold top and a pennant. The
-- deck's gold and red stripes, the gold poles and four bright critters on them at two heights (a body, a head with a
-- white snout, an ear) turn round the drum.
M.carousel = function(m, f)
	cyl(m, f, 0, 0.12, 0, 3.0, 0.25, "berry_red", "Skirt")
	cyl(m, f, 0, 0.37, 0, 2.75, 0.25, "cream", "Deck")
	cyl(m, f, 0, 1.0, 0, 0.75, 1.0, "berry_red", "Drum")
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		Parts.turned(m, f, math.sin(a) * 0.375, 1.0, math.cos(a) * 0.375, 0.25, 0.5, 0.25, a, "gold", "Panel")
	end
	cyl(m, f, 0, 1.55, 0, 0.75, 0.25, "gold", "Band")
	cyl(m, f, 0, 2.15, 0, 0.5, 1.0, "gold", "Column")
	-- the canopy
	for k, d in { 3.0, 2.5, 2.0, 1.5, 1.0 } do
		cyl(m, f, 0, 2.62 + (k - 1) * 0.25, 0, d, 0.25, if k % 2 == 1 then "berry_red" else "white", "Canopy")
	end
	for k = 0, 11 do
		local a = k * PI / 6
		Parts.turned(m, f, math.sin(a) * 1.375, 2.375, math.cos(a) * 1.375, 0.5, 0.25, 0.25, a, if k % 2 == 0 then "yellow" else "berry_red", "Scallop")
	end
	for k = 0, 7 do
		local a = k * PI / 4 + PI / 8
		glow(m, f, math.sin(a) * 1.375, 2.875, math.cos(a) * 1.375, 0.25, 0.25, 0.25, "yellow", "Bulb")
	end
	ball(m, f, 0, 3.85, 0, 0.5, "gold", "Top")
	box(m, f, 0, 4.37, 0, 0.25, 0.75, 0.25, "gold", "FlagPole")
	Parts.wedge(m, f, 0.5, 4.5, 0, 0.25, 0.5, 0.75, "blue", -PI / 2, "Flag")
	-- what turns: the deck's stripes, the poles and the riders
	local spin = mover("spin", V(0, 0, 0), "Y", 0.8)
	for k = 0, 7 do
		local a = k * PI / 4
		spin(Parts.turned(m, f, math.sin(a) * 0.9, 0.5, math.cos(a) * 0.9, 0.25, 0.25, 0.75, a, if k % 2 == 0 then "gold" else "berry_red", "Stripe"))
	end
	for k, c in { "yellow", "blue", "pink", "green" } do
		local a = (k - 1) * PI / 2 + PI / 4
		local px, pz = math.cos(a) * 0.95, math.sin(a) * 0.95
		local y = if k % 2 == 0 then 1.35 else 1.05
		spin(box(m, f, px, 1.5, pz, 0.25, 2.0, 0.25, "gold", "Pole"))
		local g = f * CFrame.new(px, y, pz) * CFrame.Angles(0, -a, 0)
		spin(box(m, g, 0, 0, 0, 0.5, 0.5, 0.75, c, "Rider"))
		spin(box(m, g, 0, 0.35, 0.4, 0.5, 0.5, 0.5, c, "RiderHead"))
		spin(box(m, g, 0, 0.25, 0.7, 0.25, 0.25, 0.25, "white", "Snout"))
		spin(box(m, g, 0, 0.7, 0.3, 0.25, 0.25, 0.25, c, "Ear"))
	end
end

-- Climbing Frame (3 x 3): a timber tower on bark chips: a lookout deck of pale planks, rails with balusters, a green
-- roof with a dark ridge and an orange flag; a rope net with knots down its front, a blue climbing wall with bright
-- holds on its east side, monkey bars out to two far posts, a knotted rope swinging under them. Tufts and flowers.
M.climbframe = function(m, f)
	box(m, f, 0, 0.02, 0, 3.0, 0.25, 3.0, "sand_dark", "Bark")
	box(m, f, 0.6, 0.06, 0.8, 0.75, 0.25, 0.5, "wood_dark", "Chips")
	box(m, f, -0.9, 0.06, 1.1, 0.5, 0.25, 0.5, "wood", "Chips")
	local cx, cz = -0.4, -0.4
	for _, x in { cx - 0.75, cx + 0.75 } do
		for _, z in { cz - 0.75, cz + 0.75 } do
			box(m, f, x, 1.5, z, 0.25, 3.0, 0.25, "wood", "Post")
		end
	end
	box(m, f, cx, 1.5, cz, 1.75, 0.25, 1.75, "wood_dark", "Deck")
	for _, dz in { -0.4, 0.4 } do
		box(m, f, cx, 1.5625, cz + dz, 1.5, 0.25, 0.5, "wood", "Plank")
	end
	box(m, f, cx, 2.1, cz - 0.75, 1.5, 0.25, 0.25, "wood_dark", "Rail")
	box(m, f, cx - 0.75, 2.1, cz, 0.25, 0.25, 1.5, "wood_dark", "Rail")
	for _, d in { -0.25, 0.25 } do
		box(m, f, cx + d, 1.85, cz - 0.75, 0.25, 0.5, 0.25, "wood", "Baluster")
		box(m, f, cx - 0.75, 1.85, cz + d, 0.25, 0.5, 0.25, "wood", "Baluster")
	end
	Parts.wedge(m, f, cx, 3.37, cz - 0.5, 2.0, 0.75, 1.0, "green", 0, "Roof")
	Parts.wedge(m, f, cx, 3.37, cz + 0.5, 2.0, 0.75, 1.0, "green", PI, "Roof")
	box(m, f, cx, 3.8, cz, 2.0, 0.25, 0.25, "wood_dark", "Ridge")
	box(m, f, cx, 4.12, cz, 0.25, 0.75, 0.25, "wood_dark", "FlagPole")
	Parts.wedge(m, f, cx + 0.5, 4.25, cz, 0.25, 0.5, 0.75, "orange", -PI / 2, "Flag")
	-- the rope net, from the deck's front edge down to the ground, knotted where its ropes cross
	local z0, z1 = cz + 0.85, 1.35
	for _, x in { cx - 0.6, cx, cx + 0.6 } do
		beam(m, f, V(x, 1.55, z0), V(x, 0.05, z1), 0.25, "straw", "Rope")
	end
	for _, t in { 0.25, 0.5, 0.75 } do
		box(m, f, cx, 1.55 - t * 1.5, z0 + t * (z1 - z0), 1.5, 0.25, 0.25, "straw", "Rope")
	end
	for _, x in { cx - 0.6, cx + 0.6, cx } do
		ball(m, f, x, 1.55 - 0.5 * 1.5, z0 + 0.5 * (z1 - z0) + 0.06, 0.25, "sand_dark", "Knot")
	end
	-- the climbing wall on the east side
	box(m, f, cx + 0.9, 0.75, cz, 0.25, 1.5, 1.5, "blue", "Wall")
	box(m, f, cx + 0.9, 1.5625, cz, 0.25, 0.25, 1.5, "wood_dark", "WallCap")
	for k, h in { { 0.3, -0.4 }, { 0.65, 0.3 }, { 0.95, -0.2 }, { 1.25, 0.45 }, { 0.5, 0.05 }, { 1.2, 0.2 } } do
		box(m, f, cx + 1.05, h[1], cz + h[2], 0.25, 0.25, 0.25, ({ "berry_red", "yellow", "green", "orange" })[(k - 1) % 4 + 1], "Hold")
	end
	-- the monkey bars, out to two posts, and the knotted rope swinging under the middle bar
	local bz = cz - 0.55
	for _, z in { bz - 0.25, bz + 0.25 } do
		box(m, f, 0.8, 2.1, z, 1.25, 0.25, 0.25, "steel_dark", "BarRail")
		box(m, f, 1.25, 1.05, z, 0.25, 2.1, 0.25, "wood", "Post")
		box(m, f, 1.25, 0.0625, z, 0.5, 0.25, 0.25, "rock", "Footing")
	end
	for _, x in { 0.55, 0.85, 1.1 } do
		box(m, f, x, 2.1, bz, 0.25, 0.25, 0.75, "steel", "Bar")
	end
	local sw = mover("swing", V(0.85, 2.0, bz), "X", 1.4, R(14))
	sw(box(m, f, 0.85, 1.5, bz, 0.25, 1.0, 0.25, "straw", "SwingRope"))
	sw(ball(m, f, 0.85, 1.05, bz, 0.5, "straw", "Knot"))
	-- tufts and flowers
	tuft(m, f, 1.3, 0, 1.3)
	tuft(m, f, -1.35, 0, 1.35, "leaf")
	tuft(m, f, 1.35, 0, 0.25)
	bloom(m, f, 1.2, 0, 0.9, "yellow")
	bloom(m, f, -1.3, 0, 0.9, "pink")
end

------------------------------------------------------------------ treats
-- Grill (1 x 1): a round black kettle grill on three splayed legs with little feet, an ash pan between them, a steel
-- vent, red-hot coals (they smoke: Coals) under two grate bars, sausages, a corn cob in its husk and a patty cooking,
-- tongs across the grate, a ketchup bottle at its feet, tufts.
M.grill = function(m, f)
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + PI / 6
		beam(m, f, V(math.cos(a) * 0.32, 0.05, math.sin(a) * 0.32), V(math.cos(a) * 0.18, 0.6, math.sin(a) * 0.18), 0.25, "steel_dark", "Leg")
		box(m, f, math.cos(a) * 0.34, 0.0625, math.sin(a) * 0.34, 0.25, 0.25, 0.25, "black", "Foot")
	end
	cyl(m, f, 0, 0.3, 0, 0.5, 0.25, "steel", "AshPan")
	cyl(m, f, 0, 0.62, 0, 0.75, 0.25, "black", "Bowl")
	cyl(m, f, 0, 0.87, 0, 1.0, 0.25, "black", "Bowl")
	box(m, f, 0.1, 0.62, 0.3, 0.25, 0.25, 0.25, "steel", "Vent")
	cyl(m, f, 0, 0.9375, 0, 0.75, 0.25, "orange", "Coals", true)
	for _, z in { -0.2, 0.2 } do
		box(m, f, 0, 1.0625, z, 0.75, 0.25, 0.25, "steel_dark", "Grate")
	end
	box(m, f, -0.1, 1.2, -0.2, 0.5, 0.25, 0.25, "brick", "Sausage")
	box(m, f, 0.0, 1.2, 0.2, 0.5, 0.25, 0.25, "brick", "Sausage")
	box(m, f, 0.3, 1.2, -0.05, 0.25, 0.25, 0.5, "yellow", "Corn")
	box(m, f, 0.3, 1.2, 0.25, 0.25, 0.25, 0.25, "green", "Husk")
	cyl(m, f, -0.3, 1.15, 0.05, 0.25, 0.25, "wood_dark", "Patty")
	beam(m, f, V(-0.3, 1.25, 0.35), V(0.05, 1.25, 0.0), 0.25, "steel", "Tongs")
	cyl(m, f, -0.375, 0.25, 0.375, 0.25, 0.5, "berry_red", "Ketchup")
	cyl(m, f, -0.375, 0.5625, 0.375, 0.25, 0.25, "white", "KetchupCap")
	tuft(m, f, 0.35, 0, 0.35)
	tuft(m, f, -0.35, 0, -0.35)
end

-- Lemonade Stand (2 x 1): a white counter in yellow stripes with a chalk price board on its front, a wooden top, a
-- sign on two posts with a lemon slice and letters on it, a striped awning over the sign with little flags along its
-- edge. On the counter: a jug of lemonade with a lemon slice on its rim, a stack of paper cups and two full ones (a
-- straw in one), a blue bowl of lemons. Tufts at its feet.
M.lemonade = function(m, f)
	box(m, f, 0, 0.4375, 0.05, 1.75, 0.75, 0.5, "white", "Counter")
	for _, x in { -0.625, 0.625 } do
		box(m, f, x, 0.4375, 0.27, 0.25, 0.75, 0.25, "yellow", "Stripe")
	end
	box(m, f, 0, 0.5, 0.3125, 0.75, 0.5, 0.25, "chalk", "PriceBoard")
	box(m, f, 0, 0.5625, 0.375, 0.5, 0.25, 0.25, "white", "Chalk")
	box(m, f, 0, 0.9375, 0.05, 2.0, 0.25, 0.75, "wood", "Top")
	-- the sign on its posts, the awning over it
	for _, x in { -0.85, 0.85 } do
		box(m, f, x, 1.125, -0.3125, 0.25, 2.25, 0.25, "wood_dark", "Post")
	end
	box(m, f, 0, 1.875, -0.3125, 1.75, 0.75, 0.25, "yellow", "Sign")
	disc(m, f, -0.45, 1.85, -0.17, 0.5, 0.25, "white", "Lemon")
	box(m, f, -0.45, 1.85, -0.12, 0.25, 0.25, 0.25, "yellow", "LemonPip")
	box(m, f, 0.2, 1.95, -0.17, 0.75, 0.25, 0.25, "white", "Letters")
	box(m, f, 0.3, 1.7, -0.17, 0.5, 0.25, 0.25, "white", "Letters")
	for k = 0, 3 do
		local x = -0.75 + k * 0.5
		Parts.wedge(m, f, x, 2.5, -0.125, 0.5, 0.5, 0.75, if k % 2 == 0 then "yellow" else "white", PI, "Awning")
		Parts.wedge(m, f, x, 2.125, 0.25, 0.25, 0.25, 0.25, if k % 2 == 0 then "white" else "yellow", PI, "Pennant")
	end
	-- on the counter
	cyl(m, f, -0.5, 1.3, 0.05, 0.5, 0.5, "yellow", "Jug")
	cyl(m, f, -0.5, 1.6, 0.05, 0.5, 0.25, "window", "JugRim")
	box(m, f, -0.8, 1.3, 0.05, 0.25, 0.25, 0.25, "window", "JugHandle")
	box(m, f, -0.35, 1.75, 0.2, 0.25, 0.25, 0.25, "yellow", "LemonSlice")
	cyl(m, f, 0.05, 1.3125, -0.15, 0.25, 0.5, "paper", "Cups")
	for _, c in { { 0.05, 0.25 }, { 0.3, 0.2 } } do
		box(m, f, c[1], 1.1875, c[2], 0.25, 0.25, 0.25, "paper", "Cup")
	end
	box(m, f, 0.3, 1.4375, 0.2, 0.25, 0.25, 0.25, "pink", "Straw")
	cyl(m, f, 0.6, 1.1875, 0.05, 0.5, 0.25, "blue", "Bowl")
	for _, c in { { 0.52, -0.02 }, { 0.68, 0.12 }, { 0.6, 0.05 } } do
		ball(m, f, c[1], 1.3125 + (if c[1] == 0.6 then 0.1 else 0), c[2], 0.25, "yellow", "Lemon")
	end
	tuft(m, f, -0.85, 0, 0.35)
	tuft(m, f, 0.85, 0, 0.35)
end

-- Ice Cream Cart (2 x 1): a white cart with a pink stripe and bumper, a cone painted on its side and a pink sign, three
-- scoops on show over the glass lid (pink, vanilla with a cherry, chocolate), two cones ready in a holder, big wheels
-- with steel rims and gold hubs, a leg with a foot, a push bar with a black grip and a gold bell, a sunshade in pink
-- and white tiers with a little flag on top. Tufts at its wheels.
M.icecream = function(m, f)
	box(m, f, 0.1, 0.75, 0, 1.25, 0.75, 0.5, "white", "Body")
	box(m, f, 0.1, 0.5, 0, 1.5, 0.25, 0.5, "pink", "Bumper")
	box(m, f, 0.1, 1.0, 0.27, 1.0, 0.25, 0.25, "pink", "Stripe")
	box(m, f, 0.1, 1.25, 0, 1.25, 0.25, 0.5, "window", "Lid")
	for k, c in { "pink", "cream", "wood_dark" } do
		ball(m, f, -0.15 + (k - 1) * 0.37, 1.4, 0, 0.5, c, "Scoop")
	end
	ball(m, f, 0.22, 1.7, 0.05, 0.25, "berry_red", "Cherry")
	-- two cones in a holder at the bar end
	box(m, f, -0.4, 1.3125, 0.125, 0.25, 0.25, 0.25, "steel", "ConeHolder")
	for _, z in { 0.0, 0.25 } do
		box(m, f, -0.4, 1.5, z, 0.25, 0.5, 0.25, "sand_dark", "Cone")
	end
	-- the wheels: the front one with its rim and hub, the back one plain
	disc(m, f, 0.4, 0.38, 0.25, 0.75, 0.25, "black", "Wheel")
	disc(m, f, 0.4, 0.38, 0.3125, 0.5, 0.25, "steel", "Rim")
	disc(m, f, 0.4, 0.38, 0.375, 0.25, 0.25, "gold", "Hub")
	disc(m, f, 0.4, 0.38, -0.25, 0.75, 0.25, "black", "Wheel")
	box(m, f, -0.35, 0.2, 0, 0.25, 0.5, 0.25, "steel_dark", "Leg")
	box(m, f, -0.35, 0.0625, 0, 0.5, 0.25, 0.25, "black", "Foot")
	-- a cone drawn on its side, the shop's sign beside it
	box(m, f, -0.2, 0.75, 0.27, 0.25, 0.25, 0.25, "sand_dark", "ConePicture")
	box(m, f, -0.2, 0.95, 0.27, 0.25, 0.25, 0.25, "pink", "ConeScoop")
	box(m, f, 0.4, 0.875, 0.27, 0.5, 0.25, 0.25, "pink", "Letters")
	-- the push bar and its bell
	for _, z in { -0.25, 0.25 } do
		box(m, f, -0.65, 1.05, z, 0.5, 0.25, 0.25, "steel_dark", "BarArm")
	end
	box(m, f, -0.85, 1.05, 0, 0.25, 0.25, 0.75, "steel_dark", "PushBar")
	box(m, f, -0.85, 1.05, 0, 0.25, 0.25, 0.5, "black", "Grip")
	cyl(m, f, -0.65, 1.3, 0.25, 0.25, 0.25, "gold", "Bell")
	-- the sunshade, on a pole at the push bar's end of the cart
	box(m, f, -0.4, 2.0, 0, 0.25, 1.25, 0.25, "white", "ShadePole")
	cyl(m, f, -0.4, 2.55, 0, 1.0, 0.25, "pink", "Shade")
	cyl(m, f, -0.4, 2.75, 0, 0.75, 0.25, "white", "Shade")
	cyl(m, f, -0.4, 2.95, 0, 0.5, 0.25, "pink", "Shade")
	ball(m, f, -0.4, 3.15, 0, 0.25, "white", "ShadeTop")
	box(m, f, -0.25, 3.35, 0, 0.5, 0.25, 0.25, "berry_red", "Pennant")
	box(m, f, -0.4, 3.3, 0, 0.25, 0.25, 0.25, "steel_dark", "FlagPole")
	tuft(m, f, 0.85, 0, 0.35)
	tuft(m, f, -0.85, 0, -0.3)
end

-- Telescope (1 x 1): a brass telescope on a wooden tripod on a round stone, looking out over the sea and turning
-- slowly from side to side: a gold tube with an orange band, a lens at its far end, a dark eyepiece, a little finder
-- on top and a bracket under it, on a steel head. A tray between the legs holds a red lens case; a rolled chart and a
-- lens cap lie on the stone.
M.telescope = function(m, f)
	cyl(m, f, 0, 0.02, 0, 1.0, 0.25, "rock", "Pad")
	for k = 0, 2 do
		local a = k * 2 * PI / 3 + PI / 2
		local foot = V(math.cos(a) * 0.36, 0.1, math.sin(a) * 0.36)
		beam(m, f, foot, V(0, 1.05, 0), 0.25, "wood_dark", "Leg")
		box(m, f, foot.X, 0.1875, foot.Z, 0.25, 0.25, 0.25, "steel_dark", "Foot")
	end
	cyl(m, f, 0, 0.5, 0, 0.5, 0.25, "wood", "Tray")
	box(m, f, 0.05, 0.6875, 0.05, 0.25, 0.25, 0.25, "berry_red", "LensCase")
	box(m, f, 0, 1.125, 0, 0.5, 0.25, 0.5, "steel_dark", "Head")
	-- the telescope itself, turning on its head (round Y)
	local sw = mover("swing", V(0, 1.45, 0), "Y", 0.9, 0.3)
	local t = CFrame.new(0, 1.45, 0) * CFrame.Angles(0, R(45), 0) * CFrame.Angles(0, 0, R(30))
	sw(rod(m, f, t * CFrame.new(-0.375, 0, 0), 0.25, 0.25, "black", "Eyepiece"))
	sw(rod(m, f, t * CFrame.new(-0.0, 0, 0), 0.5, 0.5, "gold", "Tube"))
	sw(rod(m, f, t * CFrame.new(0.375, 0, 0), 0.25, 0.5, "orange", "Band"))
	sw(rod(m, f, t * CFrame.new(0.4375, 0, 0), 0.25, 0.25, "window", "Lens"))
	sw(rod(m, f, t * CFrame.new(-0.0625, 0.375, 0), 0.5, 0.25, "steel", "Finder"))
	sw(at(m, f, t * CFrame.new(0, -0.3125, 0), 0.25, 0.25, 0.25, "steel_dark", "Bracket"))
	-- on the stone
	box(m, f, -0.25, 0.1875, 0.3, 0.5, 0.25, 0.25, "cream", "Chart")
	cyl(m, f, 0.3, 0.1875, 0.25, 0.25, 0.25, "black", "LensCap")
	tuft(m, f, 0.37, 0, -0.37)
	tuft(m, f, -0.37, 0, -0.37, "leaf")
end

-- Tiki Bar (3 x 2): a bar of bamboo canes bound with rope, a carved face on its front and a garland of flowers along
-- it, a shelf of bottles behind, drinks on top (a coconut with a straw, a glass with a little umbrella) and a
-- pineapple, two stools, a thatched roof with a ragged fringe on bamboo posts, and a tiki torch on a pole at each
-- front corner (sparks go up: Flame).
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
	for k, x in { -0.9, -0.55, 0.55, 0.9 } do
		ball(m, f, x, 0.9, 0.6625, 0.25, ({ "pink", "yellow", "white", "pink" })[k], "Flower")
	end
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
	-- the torches at the front corners
	for _, x in { -1.0, 1.0 } do
		cyl(m, f, x, 0.5, 0.85, 0.25, 1.0, "bamboo", "TorchPole")
		box(m, f, x, 1.125, 0.85, 0.5, 0.25, 0.25, "straw", "TorchCup")
		glow(m, f, x, 1.3125, 0.85, 0.25, 0.25, 0.25, "orange", "Flame")
		glow(m, f, x, 1.5, 0.85, 0.25, 0.25, 0.25, "yellow", "Fire")
	end
	-- drinks and a pineapple
	ball(m, f, -0.6, 1.4, 0.3, 0.5, "wood_dark", "Coconut")
	box(m, f, -0.5, 1.75, 0.3, 0.25, 0.5, 0.25, "pink", "Straw")
	box(m, f, 0.4, 1.38, 0.35, 0.25, 0.5, 0.25, "orange", "Glass")
	cyl(m, f, 0.4, 1.75, 0.35, 0.5, 0.25, "pink", "Umbrella")
	ball(m, f, 0.85, 1.475, 0.1, 0.5, "yellow", "Pineapple")
	box(m, f, 0.85, 1.85, 0.1, 0.25, 0.5, 0.25, "green", "PineappleTop")
	-- stools
	for _, x in { -0.65, 0.65 } do
		box(m, f, x, 0.37, 0.75, 0.25, 0.75, 0.25, "bamboo", "StoolLeg")
		cyl(m, f, x, 0.8, 0.75, 0.5, 0.25, "wood_dark", "Stool")
	end
end

------------------------------------------------------------------ fountains
-- Drinking Fountain (1 x 1): a teal iron column (a foot, a capital) on four paving stones, a steel basin brim-full of
-- water, a spout on its back edge throwing a little arc of water (drops go up off it: Spray), a gold push button, a
-- steel plaque, a stone step for little ones, a drain with a puddle by it, tufts between the stones.
M.drinkfountain = function(m, f)
	for _, c in CORNERS do
		box(m, f, c[1] * 0.25, 0.0625, c[2] * 0.25, 0.5, 0.25, 0.5, if c[1] * c[2] > 0 then "pavement" else "rock", "Paving")
	end
	box(m, f, 0.3, 0.125, -0.3, 0.25, 0.25, 0.25, "steel_dark", "Drain")
	Parts.water(m, f, 0.3, 0.13, -0.05, 0.25, 0.25)
	cyl(m, f, 0, 0.3125, 0, 0.5, 0.25, "teal", "Foot")
	cyl(m, f, 0, 0.6875, 0, 0.25, 0.5, "teal", "Column")
	cyl(m, f, 0, 1.0625, 0, 0.5, 0.25, "teal", "Capital")
	cyl(m, f, 0, 1.3125, 0, 1.0, 0.25, "steel", "Basin")
	pool(m, f, 0, 1.375, 0, 0.75)
	box(m, f, 0, 1.0625, 0.3125, 0.25, 0.25, 0.25, "steel", "Plaque")
	box(m, f, 0, 1.3125, 0.375, 0.25, 0.25, 0.25, "gold", "Button")
	-- the spout and its arc
	box(m, f, 0, 1.5625, -0.375, 0.25, 0.25, 0.25, "steel_dark", "Spout")
	box(m, f, 0, 1.6875, -0.25, 0.25, 0.25, 0.25, "steel_dark", "Nozzle")
	at(m, f, CFrame.new(0, 1.8, -0.1) * CFrame.Angles(R(-30), 0, 0), 0.25, 0.25, 0.25, "foam", "Jet"):SetAttribute("PixelWater", 2)
	jet(m, f, 0, 1.6875, 0.0625, 0.25, 0.25, 0.25)
	ball(m, f, 0, 1.9375, -0.0625, 0.25, "foam", "Spray"):SetAttribute("PixelWater", 2)
	-- the step and the grass
	box(m, f, 0.25, 0.3125, 0.375, 0.5, 0.25, 0.25, "rock", "Step")
	tuft(m, f, -0.375, 0, 0.375)
	tuft(m, f, 0.375, 0, -0.375, "leaf")
end

-- Little Fountain (2 x 2): a round basin of stone blocks (two tones) full of water on square paving with a stone at
-- each corner, a pedestal in its middle holding a bowl brim-full, a jet out of a steel nozzle (drops go up off it:
-- Spray), water spilling over the bowl's lip on four sides, a lily pad with a flower, two coins, a little green frog
-- on the rim, pots of flowers on the corners either side.
M.smallfountain = function(m, f)
	box(m, f, 0, 0.0625, 0, 2.0, 0.25, 2.0, "pavement", "Paving")
	for _, c in CORNERS do
		box(m, f, c[1] * 0.75, 0.125, c[2] * 0.75, 0.5, 0.25, 0.5, "rock", "Corner")
	end
	for k = 0, 7 do
		local a = k * PI / 4 + PI / 8
		Parts.turned(m, f, math.sin(a) * 0.75, 0.4375, math.cos(a) * 0.75, 0.75, 0.5, 0.25, a, if k % 2 == 0 then "rock" else "pavement", "Rim")
	end
	pool(m, f, 0, 0.5, 0, 1.25)
	cyl(m, f, 0, 0.75, 0, 0.5, 0.5, "rock_dark", "Stem")
	cyl(m, f, 0, 1.125, 0, 1.0, 0.25, "pavement", "Bowl")
	pool(m, f, 0, 1.1875, 0, 0.75)
	box(m, f, 0, 1.375, 0, 0.25, 0.25, 0.25, "steel", "Nozzle")
	jet(m, f, 0, 1.9, 0, 0.25, 1.0, 0.25)
	ball(m, f, 0, 2.45, 0, 0.5, "foam", "Spray"):SetAttribute("PixelWater", 2)
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		fall(m, f, math.sin(a) * 0.5, 0.875, math.cos(a) * 0.5, 0.25, 0.5, 0.25)
	end
	cyl(m, f, 0.42, 0.53, -0.1, 0.5, 0.25, "leaf", "LilyPad")
	box(m, f, 0.42, 0.66, -0.1, 0.25, 0.25, 0.25, "pink", "Flower")
	box(m, f, -0.35, 0.56, 0.3, 0.25, 0.25, 0.25, "gold", "Coin")
	box(m, f, -0.2, 0.56, -0.4, 0.25, 0.25, 0.25, "gold", "Coin")
	-- the frog on the rim, the pots on the corners
	box(m, f, 0.6, 0.8125, 0.35, 0.5, 0.25, 0.25, "green", "Frog")
	ball(m, f, 0.5, 0.97, 0.4, 0.25, "leaf", "FrogEye")
	for _, s in { -1, 1 } do
		cyl(m, f, s * 0.75, 0.375, -s * 0.75, 0.5, 0.25, "clay", "Pot")
		ball(m, f, s * 0.75, 0.625, -s * 0.75, 0.5, "leaf", "Bush")
		ball(m, f, s * 0.75 + 0.1, 0.875, -s * 0.75 + 0.1, 0.25, if s < 0 then "pink" else "yellow", "Flower")
	end
end

-- Koi Pond (3 x 3): a kidney of water edged with rocks (moss on three) and pebbles, three koi near the surface
-- (orange and white, white and orange, gold), each with a spot and a fin, rising and dipping a little out of step;
-- lily pads with two flowers, reeds and cattails in two corners, a little fall of water over stacked rocks at the back
-- with foam where it lands, flowers on the bank.
M.koipond = function(m, f)
	pool(m, f, -0.2, 0.05, -0.1, 2.25)
	pool(m, f, 0.45, 0.05, 0.45, 1.5)
	-- rocks round the edge
	local rocks = {
		{ x = -1.1, z = -0.5, d = 0.75, c = "rock" },
		{ x = -1.2, z = 0.4, d = 0.5, c = "rock_dark" },
		{ x = -0.85, z = 1.05, d = 0.75, c = "rock" },
		{ x = -0.1, z = 1.2, d = 0.5, c = "rock_dark" },
		{ x = 0.55, z = 1.25, d = 0.5, c = "rock" },
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
	box(m, f, -0.85, 0.4, 1.05, 0.25, 0.25, 0.25, "moss", "Moss")
	for _, p in { { 0.2, 1.35 }, { -0.4, 1.35 }, { 1.35, 0.65 } } do
		ball(m, f, p[1], 0.08, p[2], 0.25, "pavement", "Pebble")
	end
	-- the little fall at the back
	box(m, f, 0.75, 0.37, -1.15, 1.0, 0.75, 0.5, "rock_dark", "FallRock")
	box(m, f, 0.75, 0.85, -1.2, 0.5, 0.5, 0.5, "rock", "FallRock")
	fall(m, f, 0.75, 0.45, -0.85, 0.5, 0.75, 0.25)
	box(m, f, 0.6, 0.15, -0.7, 0.25, 0.25, 0.25, "foam", "Foam")
	box(m, f, 0.95, 0.15, -0.68, 0.25, 0.25, 0.25, "foam", "Foam")
	-- lily pads and flowers
	for _, c in { { -0.6, -0.4 }, { 0.2, 0.75 }, { -0.75, 0.45 } } do
		cyl(m, f, c[1], 0.1, c[2], 0.5, 0.25, "leaf", "LilyPad")
	end
	box(m, f, -0.6, 0.25, -0.4, 0.25, 0.25, 0.25, "pink", "Flower")
	box(m, f, 0.2, 0.25, 0.75, 0.25, 0.25, 0.25, "white", "Flower")
	-- the koi: a body, a head patch, a tail and a fin, each rising and dipping by itself
	for i, k in { { x = 0.1, z = 0.0, a = 30, c = "orange", b = "white" }, { x = 0.6, z = 0.5, a = -60, c = "white", b = "orange" }, { x = -0.4, z = 0.15, a = 150, c = "gold", b = "orange" } } do
		local g = f * CFrame.new(k.x, 0.12, k.z) * CFrame.Angles(0, R(k.a), 0)
		local mv = mover("bob", V(k.x, 0.12, k.z), "Y", 1.0 + i * 0.15, 0.06, i * 2.1)
		mv(box(m, g, 0, 0, 0, 0.5, 0.25, 0.25, k.c, "Koi"))
		mv(box(m, g, 0.25, 0.02, 0, 0.25, 0.25, 0.25, k.b, "KoiHead"))
		mv(box(m, g, -0.35, 0, 0, 0.25, 0.25, 0.25, k.b, "KoiTail"))
		mv(box(m, g, 0, 0, 0.15, 0.25, 0.25, 0.25, k.b, "KoiFin"))
	end
	-- reeds and cattails at the back corner, more reeds at the front
	for _, r in { { -1.3, -0.6, 1.25 }, { -0.85, -1.25, 1.0 }, { -1.3, -1.2, 0.75 }, { -1.35, 0.8, 0.75 }, { -1.3, 1.25, 1.0 } } do
		box(m, f, r[1], r[3] / 2, r[2], 0.25, r[3], 0.25, "leaf_dark", "Reed")
	end
	box(m, f, -1.3, 1.3, -0.6, 0.25, 0.5, 0.25, "wood_dark", "Cattail")
	box(m, f, -0.85, 1.05, -1.25, 0.25, 0.5, 0.25, "wood_dark", "Cattail")
	ball(m, f, 1.2, 0.12, 0.9, 0.5, "rock_dark", "Rock")
	bloom(m, f, 1.3, 0, 1.25, "white")
	bloom(m, f, 1.3, 0, -1.0, "yellow")
	bloom(m, f, -0.35, 0, 1.3, "pink")
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor")

-- Driftling Colossus (4 x 4): a driftling carved in grey stone sitting up on a stepped plinth, as tall as a tower: a
-- round body with a paler belly, haunches, feet with toes, arms down to its paws on its knees, a big head with a pale
-- muzzle, a dark nose and mouth, brows over eyes set with glowing teal stones (Sparkle), long ears; a moss cap with
-- flowers and a sapling growing out of it, moss on a shoulder, ivy down its side, cracks, a tail curled round. At its
-- feet: a stair up the plinth, glowing glyphs, two stone lanterns burning (Flame), a bowl of fruit and two candles left
-- as offerings, a gold plaque on the east side, flowers and moss on the steps.
M.colossus = function(m, f)
	-- the plinth
	box(m, f, 0, 0.125, 0, 4, 0.25, 4, "slate", "Plinth")
	box(m, f, 0, 0.375, -0.125, 3.5, 0.25, 3.5, "rock_dark", "Plinth")
	box(m, f, 0, 0.75, -0.375, 3.0, 0.5, 3.0, "rock", "Plinth")
	box(m, f, 0, 1.125, -0.375, 3.25, 0.25, 3.25, "pavement", "Cornice")
	box(m, f, 0, 0.625, 1.5, 1.25, 0.25, 0.25, "rock", "Stair")
	box(m, f, 0, 0.875, 1.25, 1.25, 0.25, 0.25, "rock", "Stair")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.95, 0.75, 1.1875, 0.25, 0.5, 0.25, "teal", "Glyph", true)
	end
	box(m, f, 1.5625, 0.75, -0.9, 0.25, 0.5, 0.25, "teal", "Glyph", true)
	box(m, f, 1.5625, 0.75, 0.25, 0.25, 0.25, 0.75, "gold", "Plaque")
	box(m, f, 1.625, 0.75, 0.25, 0.25, 0.25, 0.5, "orange", "Letters")
	box(m, f, -1.4, 1.3125, 0.9, 0.5, 0.25, 0.25, "moss", "Moss")
	box(m, f, 1.6, 0.5625, -1.7, 0.25, 0.25, 0.5, "moss", "Moss")
	-- the body, sitting on the plinth's top (1.25)
	ball(m, f, 0, 2.6, -0.5, 3.0, "rock", "Body")
	ball(m, f, 0, 2.45, 0.05, 2.0, "pavement", "Belly")
	for _, s in { -1, 1 } do
		ball(m, f, s * 1.0, 1.9, -0.2, 1.5, "rock", "Haunch")
		ball(m, f, s * 0.75, 1.5, 0.75, 1.0, "rock", "Foot")
		box(m, f, s * 0.75 - 0.15, 1.45, 1.2, 0.25, 0.25, 0.25, "rock_dark", "Toe")
		box(m, f, s * 0.75 + 0.15, 1.45, 1.2, 0.25, 0.25, 0.25, "rock_dark", "Toe")
		beam(m, f, V(s * 1.15, 3.3, -0.35), V(s * 0.95, 2.25, 0.7), 0.5, "rock", "Arm")
		ball(m, f, s * 0.95, 2.15, 0.85, 0.75, "rock", "Paw")
	end
	ball(m, f, 1.2, 1.7, -1.35, 1.0, "rock", "Tail")
	-- the head
	ball(m, f, 0, 5.2, -0.4, 2.75, "rock", "Head")
	ball(m, f, 0, 4.75, 0.75, 1.0, "pavement", "Muzzle")
	box(m, f, 0, 5.0, 1.2, 0.5, 0.25, 0.25, "basalt", "Nose")
	box(m, f, 0, 4.45, 1.12, 0.5, 0.25, 0.25, "rock_dark", "Mouth")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.6, 5.4, 0.85, 0.5, 0.5, 0.25, "teal", "Sparkle", true)
		at(m, f, CFrame.new(s * 0.6, 5.8, 0.72) * CFrame.Angles(0, 0, -s * R(15)), 0.75, 0.25, 0.25, "rock_dark", "Brow")
		local ear = CFrame.new(s * 0.85, 6.9, -0.6) * CFrame.Angles(0, 0, -s * R(12))
		at(m, f, ear, 0.75, 1.5, 0.5, "rock", "Ear")
		at(m, f, ear * CFrame.new(0, -0.1, 0.2), 0.25, 1.0, 0.25, "rock_dark", "EarIn")
	end
	-- moss, flowers and a sapling on its head, moss on a shoulder, ivy down its side, cracks
	ball(m, f, -0.35, 6.35, -0.5, 1.25, "moss", "Moss")
	ball(m, f, 0.45, 6.4, -0.75, 0.75, "moss", "Moss")
	ball(m, f, -1.05, 3.6, -0.6, 0.75, "moss", "Moss")
	for _, p in { { x = -0.75, y = 6.75, z = -0.15, c = "pink" }, { x = 0.1, y = 6.95, z = -0.35, c = "yellow" }, { x = -1.2, y = 3.95, z = -0.3, c = "white" } } do
		ball(m, f, p.x, p.y, p.z, 0.25, p.c, "Flower")
	end
	box(m, f, -0.35, 7.2, -0.5, 0.25, 0.75, 0.25, "wood_dark", "Sapling")
	ball(m, f, -0.35, 7.7, -0.5, 0.75, "leaf", "Leaves")
	ball(m, f, -0.05, 7.55, -0.3, 0.5, "leaf_dark", "Leaves")
	beam(m, f, V(1.2, 3.8, -0.2), V(1.48, 2.5, -0.35), 0.25, "leaf_dark", "Ivy")
	beam(m, f, V(1.0, 3.9, 0.15), V(1.3, 3.0, 0.45), 0.25, "leaf_dark", "Ivy")
	ball(m, f, 1.45, 2.55, -0.3, 0.25, "leaf", "Ivy")
	at(m, f, CFrame.new(0.9, 3.0, 0.55) * CFrame.Angles(0, 0, R(30)), 0.25, 0.75, 0.25, "rock_dark", "Crack")
	at(m, f, CFrame.new(1.0, 5.6, 0.4) * CFrame.Angles(0, 0, R(-20)), 0.25, 0.75, 0.25, "rock_dark", "Crack")
	at(m, f, CFrame.new(-0.95, 2.6, 0.65) * CFrame.Angles(0, 0, R(15)), 0.25, 0.5, 0.25, "rock_dark", "Crack")
	-- the stone lanterns at the front corners
	for _, s in { -1, 1 } do
		box(m, f, s * 1.4, 0.625, 1.4, 0.5, 0.25, 0.5, "rock_dark", "LanternBase")
		box(m, f, s * 1.4, 1.0, 1.4, 0.25, 0.5, 0.25, "rock", "LanternPost")
		glow(m, f, s * 1.4, 1.5, 1.4, 0.5, 0.5, 0.5, "orange", "Flame")
		box(m, f, s * 1.4, 1.875, 1.4, 0.75, 0.25, 0.75, "rock_dark", "LanternRoof")
		ball(m, f, s * 1.4, 2.1, 1.4, 0.25, "rock", "LanternKnob")
	end
	-- offerings: a bowl of fruit between its feet, two candles on the stair
	cyl(m, f, 0, 1.375, 1.0, 0.5, 0.25, "rock_dark", "Bowl")
	ball(m, f, -0.08, 1.55, 0.95, 0.25, "berry_red", "Fruit")
	ball(m, f, 0.1, 1.55, 1.05, 0.25, "orange", "Fruit")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.4, 1.125, 1.3125, 0.25, 0.25, 0.25, "cream", "Candle")
		glow(m, f, s * 0.4, 1.375, 1.3125, 0.25, 0.25, 0.25, "yellow", "Light")
	end
	-- flowers on the lowest step
	bloom(m, f, -1.8, 0.25, 0.4, "pink")
	bloom(m, f, 1.8, 0.25, 1.1, "yellow")
	bloom(m, f, -0.9, 0.25, 1.8, "white")
end

-- Moonwell (4 x 4): a round well of pale stone blocks (white and grey) under cream caps on three round steps, the
-- water inside lit by the moon, a round reflection of it glowing on the water. Six standing stones round it (short
-- at the front, tall at the back), each with a cap and a glowing light on top (the tall ones twinkle: Sparkle). A
-- silver arch over the well on two footed posts, two stars on it, a crescent moon of light hung from its top on a
-- chain, turning slowly; four motes of light rising and falling over the water. Moonflowers and little crystals
-- round the steps.
M.moonwell = function(m, f)
	cyl(m, f, 0, 0.125, 0, 4.0, 0.25, "slate", "Step")
	cyl(m, f, 0, 0.375, 0, 3.25, 0.25, "rock", "Step")
	cyl(m, f, 0, 0.625, 0, 2.75, 0.25, "pavement", "Step")
	-- the well: eight blocks in a ring under eight caps, the water inside
	for k = 0, 7 do
		local a = k * PI / 4 + PI / 8
		Parts.turned(m, f, math.sin(a) * 1.0, 1.125, math.cos(a) * 1.0, 0.75, 0.75, 0.5, a, if k % 2 == 0 then "white" else "pavement", "Wall")
		Parts.turned(m, f, math.sin(a) * 1.0, 1.625, math.cos(a) * 1.0, 0.75, 0.25, 0.75, a, "cream", "Cap")
	end
	pool(m, f, 0, 1.375, 0, 1.5, "ice")
	cyl(m, f, 0.1, 1.5, -0.05, 0.5, 0.25, "white", "Moon", true)
	-- the standing stones (none where the arch stands)
	for _, k in { 0, 1, 3, 4, 5, 7 } do
		local a = k * PI / 4
		local h = if k == 0 then 0.75 elseif k == 1 or k == 7 then 1.0 elseif k == 4 then 1.75 else 1.5
		local x, z = math.sin(a) * 1.65, math.cos(a) * 1.65
		Parts.turned(m, f, x, 0.25 + h / 2, z, 0.5, h, 0.5, a, "rock", "Stone")
		Parts.turned(m, f, x, 0.25 + h + 0.125, z, 0.75, 0.25, 0.5, a, "rock_dark", "StoneCap")
		glow(m, f, x, 0.25 + h + 0.375, z, 0.25, 0.25, 0.25, "crystal", if h >= 1.5 then "Sparkle" else "StoneLight")
	end
	-- the arch
	for _, s in { -1, 1 } do
		box(m, f, s * 1.375, 0.625, 0, 0.5, 0.25, 0.5, "rock_dark", "ArchFoot")
		box(m, f, s * 1.375, 2.125, 0, 0.25, 2.75, 0.25, "steel", "ArchPost")
	end
	local n = 8
	for k = 0, n - 1 do
		local t0, t1 = PI * k / n, PI * (k + 1) / n
		beam(m, f, V(1.375 * math.cos(t0), 3.5 + 1.375 * math.sin(t0), 0), V(1.375 * math.cos(t1), 3.5 + 1.375 * math.sin(t1), 0), 0.25, "steel", "Arch")
	end
	glint(m, f, -1.25, 5.0, 0.0, "white")
	glint(m, f, 1.1, 5.3, 0.0, "ice")
	box(m, f, 0, 4.3125, 0, 0.25, 1.0, 0.25, "steel_dark", "Chain")
	-- the crescent, turning slowly round its chain: a C of light, thick in the middle
	local spin = mover("spin", V(0, 0, 0), "Y", 0.5)
	for k, t in { 90, 135, 180, 225, 270 } do
		local a = R(t)
		local thick = if k == 3 then 0.5 else 0.25
		spin(at(m, f, CFrame.new(0.625 * math.cos(a), 3.25 + 0.625 * math.sin(a), 0) * CFrame.Angles(0, 0, a + PI / 2), 0.5, thick, 0.25, if k == 3 then "white" else "ice", if k == 3 then "Sparkle" else "Crescent", true))
	end
	-- motes over the water
	for k = 0, 3 do
		local a = k * PI / 2 + 0.4
		local x, y, z = math.sin(a) * 0.4, 1.9 + k * 0.15, math.cos(a) * 0.4
		Parts.move(glow(m, f, x, y, z, 0.25, 0.25, 0.25, if k % 2 == 0 then "white" else "ice", "Mote"), "bob", V(x, y, z), "Z", 1.0 + k * 0.2, 0.12, k * 1.3)
	end
	-- moonflowers and little crystals round the steps
	for k, t in { 22.5, 67.5, 157.5, 202.5, 292.5, 337.5 } do
		local a = R(t)
		bloom(m, f, math.sin(a) * 1.5, 0.5, math.cos(a) * 1.5, ({ "white", "ice", "pink" })[(k - 1) % 3 + 1])
	end
	for _, t in { 112.5, 247.5 } do
		local a = R(t)
		crystal(m, f, CFrame.new(math.sin(a) * 1.85, 0.25, math.cos(a) * 1.85) * CFrame.Angles(0, a, R(10)), 0.25, 0.5, "crystal", true)
	end
end

-- Star Gate (5 x 2): a great ring of carved stone (grey and slate blocks) standing on its edge in two carved feet on
-- a stepped base, gold chevrons at its sides and a gold key stone with a gem at its top (Sparkle), teal runes glowing
-- round it and four gold studs. Inside it a ring of dark stone and teal runes turns slowly round the gate's
-- axis, over a field of stars: white and yellow stars (two of them twinkle), a swirl of purple and blue, a bright
-- star in the middle. Braziers burn at its front corners (Flame), crystals grow at its back corners.
M.stargate = function(m, f)
	box(m, f, 0, 0.125, 0, 5, 0.25, 2, "slate", "Base")
	box(m, f, 0, 0.375, -0.125, 4.5, 0.25, 1.5, "rock_dark", "Base")
	local yc, zc = 2.875, -0.125
	-- the ring: twenty blocks, chevrons at its sides, runes and studs between
	local r = 2.0
	for k = 0, 19 do
		local a = k * PI / 10
		local sx, cy = math.sin(a), math.cos(a)
		at(m, f, CFrame.new(sx * r, yc + cy * r, zc) * CFrame.Angles(0, 0, -a), 0.75, 0.75, 1.0, if k % 2 == 0 then "rock" else "slate", "Ring")
		if k == 5 or k == 15 then
			at(m, f, CFrame.new(sx * r, yc + cy * r, zc + 0.5) * CFrame.Angles(0, 0, -a), 0.5, 0.5, 0.25, "gold", "Chevron")
		elseif k == 2 or k == 8 or k == 12 or k == 18 then
			glow(m, f, sx * r, yc + cy * r, zc + 0.5625, 0.25, 0.25, 0.25, "teal", "Rune")
		elseif k == 4 or k == 6 or k == 14 or k == 16 then
			box(m, f, sx * (r + 0.125), yc + cy * (r + 0.125), zc + 0.5625, 0.25, 0.25, 0.25, "gold", "Stud")
		end
	end
	box(m, f, 0, yc + r + 0.125, zc, 0.75, 0.75, 1.25, "gold", "KeyStone")
	box(m, f, 0, yc + r + 0.125, zc + 0.6875, 0.25, 0.25, 0.25, "teal", "Sparkle", true)
	-- the field of stars behind the turning ring
	disc(m, f, 0, yc, zc - 0.125, 3.25, 0.25, "night", "Stars")
	local stars = {
		{ x = 0.35, y = 0.6, c = "white" },
		{ x = -0.6, y = 0.3, c = "yellow" },
		{ x = -0.2, y = -0.75, c = "white" },
		{ x = 0.8, y = -0.35, c = "white" },
		{ x = -0.85, y = -0.45, c = "white" },
		{ x = 0.15, y = 0.95, c = "yellow" },
		{ x = 0.65, y = 0.55, c = "white" },
		{ x = -0.45, y = 0.85, c = "white" },
	}
	for k, s in stars do
		glow(m, f, s.x, yc + s.y, zc + 0.0625, 0.25, 0.25, 0.25, s.c, if k == 2 or k == 4 then "Sparkle" else "Star")
	end
	for k, s in { { -0.25, 0.25 }, { 0.25, -0.2 }, { 0.45, 0.15 }, { -0.4, -0.25 } } do
		glow(m, f, s[1], yc + s[2], zc + 0.0625, 0.25, 0.25, 0.25, if k % 2 == 0 then "purple" else "blue", "Swirl")
	end
	glow(m, f, 0, yc, zc + 0.125, 0.25, 0.25, 0.25, "white", "Sparkle")
	-- the inner ring, turning slowly round the gate's axis
	local spin = mover("spin", V(0, yc, zc), "Z", 0.4)
	for k = 0, 11 do
		local a = k * PI / 6
		local p = at(m, f, CFrame.new(math.sin(a) * 1.4, yc + math.cos(a) * 1.4, zc + 0.125) * CFrame.Angles(0, 0, -a), 0.75, 0.25, 0.25, if k % 2 == 0 then "basalt" else "teal", if k % 2 == 0 then "InnerRing" else "Rune", k % 2 == 1)
		spin(p)
	end
	-- the feet holding it, with glyphs and caps
	for _, s in { -1, 1 } do
		box(m, f, s * 1.85, 1.0, zc, 1.0, 1.0, 1.25, "rock", "Foot")
		box(m, f, s * 1.85, 1.625, zc, 1.25, 0.25, 1.5, "slate", "FootCap")
		glow(m, f, s * 1.85, 1.0, zc + 0.6875, 0.25, 0.5, 0.25, "teal", "Glyph")
	end
	-- braziers at the front corners, crystals at the back ones
	for _, s in { -1, 1 } do
		box(m, f, s * 2.1, 0.5, 0.75, 0.25, 0.5, 0.25, "rock_dark", "BrazierStand")
		cyl(m, f, s * 2.1, 0.875, 0.75, 0.5, 0.25, "gold", "Brazier")
		glow(m, f, s * 2.1, 1.0625, 0.75, 0.25, 0.25, 0.25, "orange", "Flame")
		glow(m, f, s * 2.1, 1.25, 0.75, 0.25, 0.25, 0.25, "yellow", "Fire")
		crystal(m, f, CFrame.new(s * 1.85, 0.5, -0.6) * CFrame.Angles(0, R(30), -s * R(10)), 0.5, 0.75, "crystal", true)
		crystal(m, f, CFrame.new(s * 1.6, 0.5, -0.7) * CFrame.Angles(0, R(10), s * R(10)), 0.25, 0.5, "purple", true)
	end
end

-- Crown of the Sea (5 x 5): a crown three rings high built of coral and gold on a round white base inside a moat of
-- shallow water, the moat's rim a ring of coral and cream stones on the sand. Each ring is narrower: a tall band under
-- a rim, points of two steps round the rim with a white or pink pearl on each, gems set in the band (one twinkles in
-- each: Sparkle). On a gold stem and cup at the top a great glowing pearl floats and bobs. Gold spouts on the lowest
-- band pour water into the moat, two jets rise from it (Spray), coral grows in it with seaweed and two little fish;
-- shells and starfish lie on the sand.
M.seacrown = function(m, f)
	cyl(m, f, 0, 0.125, 0, 5.0, 0.25, "sand", "Base")
	cyl(m, f, 0, 0.375, 0, 4.5, 0.25, "white", "Base")
	pool(m, f, 0, 0.5, 0, 4.0, "shallow")
	for k = 0, 11 do
		local a = k * PI / 6
		Parts.turned(m, f, math.sin(a) * 2.125, 0.625, math.cos(a) * 2.125, 1.0, 0.25, 0.25, a, if k % 2 == 0 then "coral" else "cream", "MoatRim")
	end
	cyl(m, f, 0, 0.75, 0, 3.25, 0.5, "white", "CrownBase")
	-- the three rings: a band under a rim, points of two steps with a pearl on each, gems in the band
	local gems = { "teal", "pink", "blue" }
	for i = 0, 2 do
		local dia = 3.0 - i * 0.75
		local y = 1.0 + i * 1.5
		cyl(m, f, 0, y + 0.5, 0, dia, 1.0, if i % 2 == 0 then "coral" else "gold", "Band")
		cyl(m, f, 0, y + 1.125, 0, dia + 0.25, 0.25, if i % 2 == 0 then "gold" else "coral", "Rim")
		local n = 8 - i * 2
		for k = 0, n - 1 do
			local a = k * 2 * PI / n + (if i == 1 then PI / n else 0)
			local x, z = math.sin(a) * dia / 2, math.cos(a) * dia / 2
			local turn = CFrame.Angles(0, a, 0)
			at(m, f, CFrame.new(x, y + 1.5, z) * turn, 0.5, 0.5, 0.25, "gold", "Point")
			at(m, f, CFrame.new(x, y + 2.0, z) * turn, 0.25, 0.5, 0.25, "yellow", "Point")
			ball(m, f, x, y + 2.375, z, 0.25, if k % 2 == 0 then "white" else "pink", "Pearl")
		end
		for k, t in { 15, 55, 95 } do
			local a = R(t)
			local g = f * CFrame.new(math.sin(a) * dia / 2, y + 0.5, math.cos(a) * dia / 2) * CFrame.Angles(0, a, 0)
			box(m, g, 0, 0, 0.0625, 0.25, 0.5, 0.25, gems[(k + i - 1) % 3 + 1], if k == 2 then "Sparkle" else "Gem", true)
		end
	end
	-- the stem and cup at the top, the great pearl floating over it
	cyl(m, f, 0, 5.375, 0, 0.75, 0.25, "gold", "Stem")
	cyl(m, f, 0, 5.75, 0, 0.5, 0.5, "yellow", "Stem")
	cyl(m, f, 0, 6.125, 0, 0.75, 0.25, "gold", "Cup")
	Parts.move(ball(m, f, 0, 6.85, 0, 1.0, "white", "Sparkle", true), "bob", V(0, 6.85, 0), "X", 1.0, 0.1)
	-- spouts on the lowest band pouring into the moat
	for _, t in { -25, 25, 70 } do
		local a = R(t)
		box(m, f, math.sin(a) * 1.5625, 1.5, math.cos(a) * 1.5625, 0.25, 0.25, 0.25, "gold", "Spout")
		fall(m, f, math.sin(a) * 1.75, 1.0, math.cos(a) * 1.75, 0.25, 0.75, 0.25)
	end
	-- two jets rising from the moat
	for _, t in { 125, -110 } do
		local a = R(t)
		local x, z = math.sin(a) * 1.85, math.cos(a) * 1.85
		jet(m, f, x, 1.0, z, 0.25, 0.75, 0.25)
		ball(m, f, x, 1.5, z, 0.25, "foam", "Spray"):SetAttribute("PixelWater", 2)
	end
	-- coral and seaweed in the moat, two fish
	for _, t in { 45, 160, 225, 315 } do
		local a = R(t)
		local x, z = math.sin(a) * 1.85, math.cos(a) * 1.85
		beam(m, f, V(x, 0.5, z), V(x, 1.25, z), 0.25, "coral", "Coral")
		beam(m, f, V(x, 0.85, z), V(x + 0.2, 1.15, z + 0.1), 0.25, "pink", "Coral")
		beam(m, f, V(x, 0.75, z), V(x - 0.2, 1.0, z - 0.1), 0.25, "coral", "Coral")
	end
	for _, t in { 0, 90, 200, 270 } do
		local a = R(t + 10)
		box(m, f, math.sin(a) * 1.8, 0.875, math.cos(a) * 1.8, 0.25, 0.75, 0.25, "leaf_dark", "Seaweed")
	end
	for _, t in { 185, 300 } do
		local a = R(t)
		Parts.turned(m, f, math.sin(a) * 1.85, 0.6, math.cos(a) * 1.85, 0.5, 0.25, 0.25, a, "orange", "Fish")
	end
	-- shells on the sand, starfish in the corners
	for k = 0, 5 do
		local a = k * PI / 3 + 0.3
		ball(m, f, math.sin(a) * 2.375, 0.3, math.cos(a) * 2.375, 0.25, if k % 2 == 0 then "pink" else "cream", "Shell")
	end
	for _, c in { { 2.0, 2.0 }, { -2.05, 1.95 } } do
		box(m, f, c[1], 0.0625, c[2], 0.5, 0.25, 0.25, "orange", "Starfish")
		box(m, f, c[1], 0.0625, c[2], 0.25, 0.25, 0.5, "orange", "Starfish")
	end
end

-- Big Wheel (4 x 2): a ferris wheel on two steel A-frames (braced, on rock footings) on a paved base, a steel axle with
-- gold caps and a lit hub. The wheel turns slowly: a white rim, six spokes and six round cars in bright colours, each
-- with its window. A wooden boarding deck with a step and rails under it, lights along the front legs, a ticket sign
-- on a post, lamp posts at the front corners, a planter of flowers.
M.bigwheel = function(m, f)
	box(m, f, 0, 0.125, 0, 4, 0.25, 2, "pavement", "Base")
	box(m, f, 0, 0.375, 0.25, 1.0, 0.25, 1.0, "wood", "Deck")
	box(m, f, 0, 0.1875, 0.875, 1.0, 0.25, 0.25, "wood_dark", "DeckStep")
	for _, s in { -1, 1 } do
		box(m, f, s * 0.5, 0.75, 0.0, 0.25, 0.5, 0.25, "steel", "DeckRail")
	end
	local hy = 2.5
	for _, sz in { -0.625, 0.625 } do
		for _, s in { -1, 1 } do
			beam(m, f, V(s * 1.5, 0.25, sz), V(0, hy, sz), 0.25, "steel_dark", "Leg")
			box(m, f, s * 1.5, 0.375, sz, 0.5, 0.25, 0.5, "rock_dark", "Footing")
		end
		box(m, f, 0, 1.0, sz, 2.0, 0.25, 0.25, "steel_dark", "Brace")
	end
	for _, t in { 0.3, 0.6 } do
		for _, s in { -1, 1 } do
			glow(m, f, s * 1.5 * (1 - t), 0.25 + (hy - 0.25) * t, 0.8125, 0.25, 0.25, 0.25, "yellow", "Bulb")
		end
	end
	rod(m, f, CFrame.new(0, hy, 0) * CFrame.Angles(0, PI / 2, 0), 1.5, 0.5, "steel", "Axle")
	for _, z in { -0.8125, 0.8125 } do
		disc(m, f, 0, hy, z, 0.5, 0.25, "gold", "AxleCap")
	end
	disc(m, f, 0, hy, 0, 0.75, 0.5, "yellow", "Hub", true)
	-- the wheel, turning on the axle
	local spin = mover("spin", V(0, hy, 0), "Z", 0.35)
	local r = 1.5
	local colors = { "berry_red", "teal", "yellow", "purple", "orange", "pink" }
	for k = 0, 11 do
		local a = k * PI / 6
		local p = V(math.sin(a) * r, hy + math.cos(a) * r, 0)
		local q = V(math.sin(a + PI / 6) * r, hy + math.cos(a + PI / 6) * r, 0)
		spin(beam(m, f, p, q, 0.25, "white", "Rim"))
		if k % 2 == 0 then
			spin(beam(m, f, V(0, hy, 0), p, 0.25, "white", "Spoke"))
			local c = V(math.sin(a) * 1.6, hy + math.cos(a) * 1.6, 0)
			spin(disc(m, f, c.X, c.Y, 0, 0.75, 0.5, colors[k // 2 + 1], "Car"))
			spin(disc(m, f, c.X, c.Y, 0.25, 0.5, 0.25, "window", "Glass"))
		end
	end
	-- the ticket sign, lamp posts at the front corners, planters
	box(m, f, 1.1, 0.75, 0.8125, 0.25, 1.0, 0.25, "wood_dark", "SignPost")
	box(m, f, 1.1, 1.375, 0.8125, 0.75, 0.5, 0.25, "berry_red", "Sign")
	box(m, f, 1.1, 1.375, 0.875, 0.5, 0.25, 0.25, "white", "Letters")
	for _, s in { -1, 1 } do
		box(m, f, s * 1.85, 0.875, 0.85, 0.25, 1.25, 0.25, "black", "LampPost")
		glow(m, f, s * 1.85, 1.625, 0.85, 0.25, 0.25, 0.25, "yellow", "Lamp")
		box(m, f, s * 1.85, 1.875, 0.85, 0.25, 0.25, 0.25, "black", "LampCap")
	end
	box(m, f, -0.85, 0.375, 0.75, 0.5, 0.25, 0.25, "wood", "Planter")
	ball(m, f, -0.85, 0.55, 0.75, 0.5, "leaf", "Bush")
	ball(m, f, -0.75, 0.75, 0.8, 0.25, "pink", "Flower")
	ball(m, f, -0.95, 0.7, 0.82, 0.25, "yellow", "Flower")
end

return M
