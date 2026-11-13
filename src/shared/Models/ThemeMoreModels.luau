--!strict
-- The themed decor, part two (GAME_DESIGN 4; Data/Buildings): frost, autumn, the desert, the fairy glade, the zen garden
-- and the volcano. Roblox module. Each theme keeps to one palette so an island built in it hangs together: frost in
-- snow and ice with red; autumn in maple, orange, straw and brown; the desert in sand, clay and striped cloth; the
-- fairy glade in crystal and pink with soft lights; the zen garden in grey stone, bamboo and moss; the volcano in black
-- basalt with glowing lava. Lights (candles, lava, crystals, fairy lights) are Neon and shine at night.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
local Blocks = require(script.Parent.Blocks)
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

-- The camera looks at a piece from its +X +Z corner. A face or a profile turned by VIEW looks straight at it before the
-- piece is turned; ACROSS runs left to right across the picture.
local VIEW = math.pi / 4
local TOWARD = CFrame.Angles(0, VIEW, 0)
local ACROSS = Vector3.new(0.7071, 0, -0.7071)

local function v(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- Sways in the wind (leaves, cloth and steam in colours the wind does not pick up by itself).
local function sway(p: BasePart): BasePart
	p:SetAttribute("PixelWind", 1)
	return p
end

-- A square stick of thickness t from a to b (points in f's frame): a twig, a stalk, a leg, a crystal. `twist` turns it
-- about its own length (a crystal shows an edge).
local function seg(m: Model, f: CFrame, a: Vector3, b: Vector3, t: number, color: string, name: string?, neon: boolean?, twist: number?): BasePart
	local d = b - a
	local up = if math.abs(d.Unit.Y) > 0.98 then Vector3.xAxis else Vector3.yAxis
	local cf = CFrame.lookAt((a + b) / 2, b, up) * CFrame.Angles(0, 0, twist or 0)
	return Parts.at(m, f, cf, t, t, d.Magnitude, color, name, neon)
end

-- A wedge placed by its own frame in f (its slope toward -Z, full height at +Z): a wing, a blade's point.
local function wedgeAt(m: Model, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, shape = "Wedge", name = name, collide = false })
end

-- A small ball sunk into a bigger one (centre c, radius r) along dir, so only a dot of it shows: an eye, a pebble, a
-- spot on a cap.
local function dot(m: Model, f: CFrame, c: Vector3, r: number, dir: Vector3, depth: number, color: string, name: string, neon: boolean?): BasePart
	local p = c + dir.Unit * (r - depth)
	local b = Parts.ball(m, f, p.X, p.Y, p.Z, 0.25, color, name)
	if neon then
		b.Material = Enum.Material.Neon
	end
	return b
end

-- A flat disc of water the pixel filter ripples.
local function pool(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, color: string?): BasePart
	local p = Parts.cyl(m, f, x, y, z, dia, 0.25, color or "water", "Water")
	p:SetAttribute("PixelWater", 2)
	return p
end

-- A disc facing +Z (a moon set in a stone): Neon when asked.
local function disc(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string, neon: boolean?): BasePart
	local p = Parts.logZ(m, f, x, y, z, 0.25, dia, color, name)
	if neon then
		p.Material = Enum.Material.Neon
	end
	return p
end

-- A pennant on a pole whose top is at (x, top, z), tapering away to +X (named Flag: it ripples).
local function pennant(m: Model, f: CFrame, x: number, top: number, z: number, h: number, color: string)
	Parts.box(m, f, x, top - h / 2, z, 0.25, h, 0.25, "wood_dark", "FlagPole")
	Parts.wedge(m, f, x + 0.375, top - 0.25, z, 0.25, 0.5, 0.5, color, -math.pi / 2, "Flag")
end

-- A pumpkin with its foot at y: a round core and four lobes round it (the creases between them read as ribs).
local function pumpkin(m: Model, f: CFrame, x: number, y: number, z: number, s: number, color: string, lobe: number)
	local cy = y + s / 2 - 0.03
	Parts.ball(m, f, x, cy, z, s, color, "Pumpkin")
	for _, d in { { lobe, 0 }, { -lobe, 0 }, { 0, lobe }, { 0, -lobe } } do
		Parts.ball(m, f, x + d[1], cy - 0.02, z + d[2], s, color, "Pumpkin")
	end
end

------------------------------------------------------------------ frost
-- Snowman (1 x 1): two snowballs on a drift looking out at the view, coal eyes, a carrot nose, a smile of pebbles,
-- buttons, a red scarf and bobble hat, twig arms.
M.snowman = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "snow", "Drift")
	local base, head = v(0, 0.45, 0), v(0, 1.22, 0)
	Parts.ball(m, f, base.X, base.Y, base.Z, 1, "snow", "Base")
	Parts.ball(m, f, head.X, head.Y, head.Z, 0.75, "snow", "Head")
	-- the face
	for _, x in { -0.55, 0.55 } do
		dot(m, f, head, 0.375, TOWARD * v(x, 0.28, 0.8), 0.08, "black", "Eye")
	end
	Parts.at(m, f, CFrame.new(head + TOWARD * v(0, -0.06, 0.43)) * TOWARD, 0.25, 0.25, 0.5, "orange", "Nose")
	for _, x in { -0.6, 0.6 } do
		dot(m, f, head, 0.375, TOWARD * v(x, -0.55, 0.6), 0.08, "black", "Smile")
	end
	for _, y in { 0.55, 0.15 } do
		dot(m, f, base, 0.5, TOWARD * v(0, y, 1), 0.08, "black", "Button")
	end
	-- the scarf, one end down the front
	Parts.cyl(m, f, 0, 0.9, 0, 0.5, 0.25, "berry_red", "Scarf")
	local u = (TOWARD * v(0.7, 0, 0.7)).Unit
	seg(m, f, v(0, 0.9, 0) + u * 0.22, v(0, 0.55, 0) + u * 0.46, 0.25, "berry_red", "Scarf")
	-- the bobble hat
	Parts.ball(m, f, 0, 1.56, 0, 0.75, "berry_red", "Hat")
	Parts.cyl(m, f, 0, 1.52, 0, 0.75, 0.25, "white", "HatBand")
	Parts.ball(m, f, 0, 1.99, 0, 0.25, "white", "Bobble")
	-- twig arms out to the sides
	for _, s in { -1, 1 } do
		local a = ACROSS * s
		seg(m, f, v(0, 0.72, 0) + a * 0.3, v(0, 1.02, 0) + a * 0.62, 0.25, "wood_dark", "Twig")
	end
end

-- Sled (2 x 1): red runners curling up at the front, a seat of planks on struts, a tow rope, a folded blanket.
M.sled = function(m, f)
	Parts.box(m, f, -0.15, 0.02, 0, 1.75, 0.25, 0.75, "snow", "Snow")
	Parts.turned(m, f, 0.45, 0.01, 0.15, 0.75, 0.25, 0.5, 0.4, "snow", "Snow")
	for _, z in { -0.3, 0.3 } do
		Parts.box(m, f, -0.15, 0.15, z, 1.5, 0.25, 0.25, "berry_red", "Runner")
		seg(m, f, v(0.55, 0.15, z), v(0.85, 0.55, z), 0.25, "berry_red", "Runner")
		seg(m, f, v(0.85, 0.55, z), v(0.65, 0.68, z), 0.25, "berry_red", "Curl")
		for _, x in { -0.65, 0.3 } do
			Parts.box(m, f, x, 0.35, z, 0.25, 0.25, 0.25, "berry_red", "Strut")
		end
	end
	Parts.box(m, f, -0.2, 0.55, 0, 1.5, 0.25, 0.75, "wood", "Seat")
	for _, x in { -0.75, 0.35 } do
		Parts.box(m, f, x, 0.58, 0, 0.25, 0.25, 1, "wood_dark", "Batten")
	end
	Parts.logZ(m, f, 0.72, 0.68, 0, 0.75, 0.25, "wood_dark", "Bar")
	-- the tow rope, its loose end lying in the snow
	seg(m, f, v(0.78, 0.66, 0), v(0.88, 0.12, 0.25), 0.25, "straw", "Rope")
	seg(m, f, v(0.88, 0.1, 0.25), v(0.5, 0.06, 0.4), 0.25, "straw", "Rope")
	Parts.box(m, f, -0.6, 0.78, 0, 0.5, 0.25, 0.75, "blue", "Blanket")
	Parts.box(m, f, -0.6, 0.8, 0.02, 0.25, 0.25, 0.75, "white", "Stripe")
end

-- Ice Lantern (1 x 1): a block of ice on a drift, framed by its own edges, a candle's warm light filling it, snow on
-- top.
M.icelantern = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "snow", "Drift")
	Parts.box(m, f, 0, 0.25, 0, 1, 0.25, 1, "ice", "Ice")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.375, 0.75, c[2] * 0.375, 0.25, 0.75, 0.25, "ice", "Ice")
	end
	Parts.box(m, f, 0, 1.25, 0, 1, 0.25, 1, "window", "Ice")
	Parts.glow(m, f, 0, 0.75, 0, 0.75, 0.75, 0.75, "yellow", "Candlelight")
	Parts.box(m, f, -0.1, 1.42, -0.05, 0.75, 0.25, 0.5, "snow", "Snow")
	Parts.ball(m, f, 0.35, 0.1, 0.35, 0.5, "snow", "Drift")
end

-- Ice Sculpture (2 x 2): a swan carved out of ice, side on to the view: its body, wings lifted at the back, its neck in
-- an S, head and beak, on a plinth of ice capped with snow.
M.icesculpture = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 2, 0.25, "snow", "Snow")
	Parts.box(m, f, 0, 0.25, 0, 1.25, 0.5, 1.25, "ice", "Plinth")
	Parts.box(m, f, 0, 0.55, 0, 1.5, 0.25, 1.5, "snow", "Top")
	-- the swan's own frame: its head to -X, its side to the view
	local s = f * CFrame.new(0, 0.675, 0) * TOWARD
	Parts.ball(m, s, 0.05, 0.32, 0, 0.75, "ice", "Body")
	Parts.ball(m, s, 0.3, 0.38, 0, 0.75, "ice", "Body")
	Parts.ball(m, s, -0.28, 0.36, 0, 0.5, "ice", "Breast")
	seg(m, s, v(0.55, 0.45, 0), v(0.78, 0.78, 0), 0.25, "ice", "Tail")
	for _, z in { -0.25, 0.25 } do
		wedgeAt(m, s, CFrame.new(0.22, 0.78, z) * CFrame.Angles(z * 1.2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.75, 1, "window", "Wing")
	end
	local neck = { v(-0.35, 0.5, 0), v(-0.47, 0.8, 0), v(-0.44, 1.1, 0), v(-0.3, 1.3, 0), v(-0.36, 1.48, 0) }
	for i = 1, #neck - 1 do
		for k = 0, 2 do
			local p = neck[i]:Lerp(neck[i + 1], k / 3)
			Parts.ball(m, s, p.X, p.Y, p.Z, 0.25, "ice", "Neck")
		end
	end
	Parts.ball(m, s, -0.42, 1.5, 0, 0.25, "ice", "Head")
	seg(m, s, v(-0.48, 1.48, 0), v(-0.72, 1.4, 0), 0.25, "window", "Beak")
	-- chips of ice in the snow
	Parts.turned(m, f, 0.8, 0.12, 0.75, 0.25, 0.25, 0.25, 0.5, "ice", "Chip")
	Parts.turned(m, f, -0.75, 0.12, 0.8, 0.25, 0.25, 0.25, 0.9, "window", "Chip")
end

-- A ring of ice round the dome where one course of snow blocks meets the next: dia d, standing proud of the dome by
-- `poke` at its top edge (the dome: radius r, centre (0, cy, cz)).
local function course(m: Model, f: CFrame, cy: number, cz: number, r: number, d: number, poke: number)
	local top = math.sqrt(r * r - (d / 2 - poke) ^ 2)
	Parts.cyl(m, f, 0, cy + top - 0.125, cz, d, 0.25, "ice", "Course")
end

-- Igloo (3 x 3): a dome of snow blocks (ice between the courses), a tunnel to a dark round door framed in ice, a stack
-- of spare blocks, a lantern by the door, a red flag on top.
M.igloo = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 3, 0.25, "snow", "Snow")
	local r, cy, cz = 1.25, 0.1, -0.25
	Parts.ball(m, f, 0, cy, cz, r * 2, "snow", "Dome")
	course(m, f, cy, cz, r, 2.25, 0.06)
	course(m, f, cy, cz, r, 1.75, 0.07)
	course(m, f, cy, cz, r, 1, 0.12)
	-- the tunnel and its door
	Parts.logZ(m, f, 0, 0.15, 0.9, 1, 1, "snow", "Tunnel")
	Parts.logZ(m, f, 0, 0.15, 1.3, 0.25, 1.25, "ice", "Arch")
	disc(m, f, 0, 0.1, 1.33, 0.75, "night", "Door")
	-- spare blocks
	Parts.box(m, f, 1.05, 0.15, 0.85, 0.5, 0.25, 0.5, "snow", "Block")
	Parts.turned(m, f, 1.0, 0.4, 0.85, 0.5, 0.25, 0.5, 0.3, "white", "Block")
	Parts.box(m, f, 1.15, 0.15, 0.3, 0.5, 0.25, 0.5, "white", "Block")
	-- a lantern on a post by the door
	Parts.box(m, f, -0.85, 0.4, 1.15, 0.25, 0.75, 0.25, "wood_dark", "LampPost")
	Parts.glow(m, f, -0.85, 0.9, 1.15, 0.25, 0.25, 0.25, "yellow", "Lamp")
	Parts.box(m, f, -0.85, 1.1, 1.15, 0.25, 0.25, 0.25, "wood_dark", "LampCap")
	pennant(m, f, 0.1, 2.15, -0.3, 1, "berry_red")
end

------------------------------------------------------------------ autumn
-- Leaf Pile (2 x 2): a heap of fallen leaves in red, orange and gold, leaves blown loose round it, a rake left
-- leaning on it.
M.leafpile = function(m, f)
	local hue = { "maple", "orange", "straw", "orange", "maple" }
	for i, b in { { 0, 0.05, 0, 1.5 }, { 0.45, 0, 0.35, 1 }, { -0.45, 0, 0.3, 1 }, { -0.3, 0.15, -0.4, 0.75 }, { 0.4, 0.1, -0.35, 0.75 } } do
		Parts.ball(m, f, b[1], b[2], b[3], b[4], hue[i], "Leaves")
	end
	sway(Parts.ball(m, f, 0.05, 0.62, 0.05, 0.5, "straw", "Leaves"))
	-- leaves on top of the heap and blown loose round it
	for i, l in { { 0.75, 0.75, 0.3 }, { -0.8, 0.55, 1.2 }, { 0.2, 0.85, 2.1 }, { -0.7, -0.75, 0.7 }, { 0.85, -0.2, 1.7 }, { -0.15, -0.85, 2.6 } } do
		sway(Parts.turned(m, f, l[1], 0.02, l[2], 0.5, 0.25, 0.25, l[3], if i % 3 == 0 then "orange" elseif i % 3 == 1 then "maple" else "straw", "Leaf"))
	end
	for i, l in { { -0.2, 0.72, 0.3 }, { 0.45, 0.42, 0.55 }, { -0.55, 0.38, 0.45 } } do
		sway(Parts.at(m, f, CFrame.new(l[1], l[2], l[3]) * CFrame.Angles(0.5, i * 0.9, 0.3), 0.5, 0.25, 0.25, if i == 2 then "straw" else "orange", "Leaf"))
	end
	-- the rake
	seg(m, f, v(0.62, 0.08, 0.68), v(-0.05, 1.15, -0.1), 0.25, "wood", "Rake")
	Parts.turned(m, f, 0.62, 0.1, 0.68, 0.75, 0.25, 0.25, math.pi / 4, "steel_dark", "RakeHead")
end

-- Harvest Basket (1 x 1): a woven basket, its handle arched over, red apples, a green squash and a corn cob heaped in
-- it, one apple rolled out.
M.basket = function(m, f)
	Parts.cyl(m, f, 0, 0.125, 0, 0.75, 0.25, "wood", "Basket")
	Parts.cyl(m, f, 0, 0.375, 0, 1, 0.25, "straw", "Basket")
	Parts.cyl(m, f, 0, 0.625, 0, 1, 0.25, "wood", "Rim")
	-- what is in it
	Parts.ball(m, f, -0.05, 0.85, -0.12, 0.5, "green", "Squash")
	Parts.box(m, f, -0.05, 1.1, -0.12, 0.25, 0.25, 0.25, "wood_dark", "Stem")
	for _, a in { { -0.25, 0.2 }, { 0.12, 0.28 }, { 0.3, -0.05 }, { -0.3, -0.15 } } do
		Parts.ball(m, f, a[1], 0.82, a[2], 0.25, "berry_red", "Apple")
	end
	Parts.at(m, f, CFrame.new(0.18, 0.92, 0.05) * TOWARD * CFrame.Angles(0, 0, -0.7), 0.25, 0.75, 0.25, "yellow", "Corn")
	Parts.at(m, f, CFrame.new(0.05, 0.78, 0.05) * TOWARD * CFrame.Angles(0, 0, -0.7), 0.25, 0.25, 0.25, "leaf", "Husk")
	-- the handle, arched across the view
	local h = { { -0.42, 0.7 }, { -0.36, 1.1 }, { 0, 1.32 }, { 0.36, 1.1 }, { 0.42, 0.7 } }
	for i = 1, #h - 1 do
		local a, b = h[i], h[i + 1]
		seg(m, f, ACROSS * a[1] + v(0, a[2], 0), ACROSS * b[1] + v(0, b[2], 0), 0.25, "wood_dark", "Handle")
	end
	Parts.ball(m, f, 0.3, 0.12, 0.38, 0.25, "berry_red", "Apple")
end

-- Pumpkin Stack (1 x 1): an orange pumpkin, a red one on it, a pale gold one on top with its stem and a leaf, straw
-- under them.
M.pumpkinstack = function(m, f)
	Parts.turned(m, f, 0, 0, 0, 1, 0.25, 0.75, 0.4, "straw", "Straw")
	pumpkin(m, f, 0, 0, 0, 0.75, "orange", 0.1)
	pumpkin(m, f, 0.02, 0.62, 0.02, 0.5, "maple", 0.1)
	Parts.ball(m, f, 0, 1.25, 0, 0.5, "straw", "Pumpkin")
	Parts.at(m, f, CFrame.new(0.02, 1.52, 0) * CFrame.Angles(0, 0, -0.3), 0.25, 0.25, 0.25, "wood_dark", "Stem")
	sway(Parts.at(m, f, CFrame.new(-0.12, 1.5, 0.1) * CFrame.Angles(0.3, 0.5, 0.5), 0.25, 0.25, 0.5, "moss", "Leaf"))
end

-- A shock of corn stalks standing at (cx, cz): four stalks lean in to a twine tie, five flare out above it, two dry
-- leaves droop.
local function shock(m: Model, f: CFrame, cx: number, cz: number, h: number, turn: number)
	local tie = h * 0.5
	for k = 0, 3 do
		local a = turn + k * math.pi / 2 + math.pi / 4
		local ca, sa = math.cos(a), math.sin(a)
		seg(m, f, v(cx + ca * 0.32, 0, cz + sa * 0.32), v(cx + ca * 0.06, tie, cz + sa * 0.06), 0.25, if k % 2 == 0 then "straw" else "sand_dark", "Stalk")
	end
	for k = 0, 4 do
		local a = turn + k * math.pi * 2 / 5
		local ca, sa = math.cos(a), math.sin(a)
		local top = h - (k % 2) * 0.2
		seg(m, f, v(cx + ca * 0.05, tie - 0.1, cz + sa * 0.05), v(cx + ca * 0.32, top, cz + sa * 0.32), 0.25, if k % 2 == 0 then "sand" else "straw", "Stalk")
	end
	Parts.cyl(m, f, cx, tie, cz, 0.5, 0.25, "wood_dark", "Twine")
	for _, s in { -1, 1 } do
		sway(seg(m, f, v(cx, tie + 0.3, cz) + ACROSS * (s * 0.1), v(cx, tie - 0.05, cz) + ACROSS * (s * 0.45), 0.25, "sand", "Leaf"))
	end
end

-- Corn Stalks (2 x 1): two shocks of dry stalks tied with twine, a small pumpkin and a cob at their feet.
M.cornstalks = function(m, f)
	shock(m, f, -0.5, -0.05, 1.75, 0)
	shock(m, f, 0.5, 0, 1.5, 0.3)
	pumpkin(m, f, 0.05, 0, 0.3, 0.5, "orange", 0.08)
	Parts.box(m, f, 0.05, 0.6, 0.3, 0.25, 0.25, 0.25, "wood_dark", "Stem")
	Parts.turned(m, f, -0.5, 0.1, 0.38, 0.5, 0.25, 0.25, 0.3, "yellow", "Corn")
	Parts.turned(m, f, -0.25, 0.1, 0.4, 0.25, 0.25, 0.25, 0.3, "leaf", "Husk")
end

-- Carved Pumpkin (1 x 1): a big pumpkin on a straw bale, turned to look at the view, its eyes and grin lit from
-- inside, a stem and a leaf.
M.jackolantern = function(m, f)
	Parts.box(m, f, 0, 0.25, 0, 1, 0.5, 0.75, "straw", "Bale")
	for _, x in { -0.3, 0.3 } do
		Parts.box(m, f, x, 0.4, 0.01, 0.25, 0.25, 0.75, "sand_dark", "Twine")
	end
	local p = f * CFrame.new(0, 0.5, 0) * TOWARD
	pumpkin(m, p, 0, 0, 0, 0.75, "orange", 0.1)
	local cy = 0.345
	for _, x in { -0.2, 0.2 } do
		Parts.glow(m, p, x, cy + 0.18, 0.31, 0.25, 0.25, 0.25, "yellow", "Eye")
	end
	Parts.glow(m, p, 0, cy - 0.17, 0.31, 0.5, 0.25, 0.25, "yellow", "Grin")
	Parts.at(m, p, CFrame.new(0, cy + 0.42, 0) * CFrame.Angles(0, 0, 0.25), 0.25, 0.25, 0.25, "wood_dark", "Stem")
	sway(Parts.at(m, p, CFrame.new(0.18, cy + 0.38, -0.12) * CFrame.Angles(0.2, 0.4, -0.35), 0.5, 0.25, 0.25, "moss", "Leaf"))
end

------------------------------------------------------------------ the desert
-- A tall clay jar standing at (x, z): a dark foot, a long round belly with a painted band, a narrow neck, a lip (its
-- top at 1.475).
local function jar(m: Model, f: CFrame, x: number, z: number, band: string)
	Parts.cyl(m, f, x, 0.125, z, 0.5, 0.25, "brick", "Foot")
	Parts.ball(m, f, x, 0.5, z, 0.75, "clay", "Jar")
	Parts.ball(m, f, x, 0.78, z, 0.75, "clay", "Jar")
	Parts.cyl(m, f, x, 0.62, z, 0.75, 0.25, band, "Band")
	Parts.cyl(m, f, x, 1.2, z, 0.25, 0.25, "clay", "Neck")
	Parts.cyl(m, f, x, 1.35, z, 0.5, 0.25, "brick", "Lip")
end

-- Water Jars (1 x 1): a tall clay jar with a cream band, water in its mouth, a small round one with a teal band beside
-- it, on a patch of sand.
M.waterjars = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "sand", "Sand")
	jar(m, f, -0.1, -0.12, "cream")
	pool(m, f, -0.1, 1.37, -0.12, 0.25)
	Parts.ball(m, f, 0.25, 0.25, -0.18, 0.5, "clay", "Jar")
	Parts.cyl(m, f, 0.25, 0.25, -0.18, 0.5, 0.25, "teal", "Band")
	Parts.cyl(m, f, 0.25, 0.55, -0.18, 0.25, 0.25, "brick", "Lip")
	Parts.cyl(m, f, -0.2, 0.15, 0.32, 0.25, 0.25, "clay", "Cup")
end

-- Clay Pots (2 x 1): a row of painted pots on the sand: a round one with a cream band, a low bowl with a little cactus
-- in flower, a tall jar banded in teal, a small one at their feet.
M.claypots = function(m, f)
	Parts.cyl(m, f, -0.5, 0, 0, 1, 0.25, "sand", "Sand")
	Parts.cyl(m, f, 0.5, 0, 0, 1, 0.25, "sand", "Sand")
	-- round pot
	Parts.ball(m, f, -0.6, 0.35, -0.05, 0.75, "clay", "Pot")
	Parts.cyl(m, f, -0.6, 0.35, -0.05, 0.75, 0.25, "cream", "Band")
	Parts.cyl(m, f, -0.6, 0.75, -0.05, 0.5, 0.25, "brick", "Neck")
	-- the bowl and its cactus
	Parts.cyl(m, f, 0.05, 0.125, -0.12, 0.75, 0.25, "brick", "Bowl")
	Parts.cyl(m, f, 0.05, 0.375, -0.12, 0.75, 0.25, "clay", "Bowl")
	Parts.cyl(m, f, 0.05, 0.75, -0.12, 0.25, 0.75, "green", "Cactus")
	Parts.box(m, f, 0.2, 0.85, -0.12, 0.25, 0.25, 0.25, "green", "Cactus")
	Parts.box(m, f, 0.28, 1.0, -0.12, 0.25, 0.25, 0.25, "green", "Cactus")
	Parts.box(m, f, 0.05, 1.15, -0.12, 0.25, 0.25, 0.25, "pink", "Bloom")
	-- the tall jar
	jar(m, f, 0.62, -0.12, "teal")
	-- a small one in front
	Parts.ball(m, f, 0.35, 0.22, 0.25, 0.5, "clay", "Pot")
	Parts.cyl(m, f, 0.35, 0.22, 0.25, 0.5, 0.25, "cream", "Band")
end

-- Market Rug (2 x 2): a woven rug, gold round a red field with a gold diamond in the middle and gold corners, cream
-- fringes at the ends, two cushions.
M.rug = function(m, f)
	for _, x in { -0.85, 0.85 } do
		Parts.box(m, f, x, 0, 0, 0.25, 0.25, 1.25, "cream", "Fringe")
	end
	Parts.box(m, f, 0, 0.01, 0, 1.5, 0.25, 1.5, "gold", "Rug")
	Parts.box(m, f, 0, 0.02, 0, 1.25, 0.25, 1.25, "berry_red", "Field")
	Parts.turned(m, f, 0, 0.03, 0, 0.75, 0.25, 0.75, math.pi / 4, "gold", "Diamond")
	Parts.turned(m, f, 0, 0.04, 0, 0.5, 0.25, 0.5, math.pi / 4, "berry_red", "Diamond")
	Parts.turned(m, f, 0, 0.05, 0, 0.25, 0.25, 0.25, math.pi / 4, "teal", "Heart")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.45, 0.03, c[2] * 0.45, 0.25, 0.25, 0.25, "gold", "Corner")
	end
	Parts.turned(m, f, -0.35, 0.25, -0.5, 0.5, 0.25, 0.5, 0.2, "teal", "Cushion")
	Parts.turned(m, f, 0.3, 0.25, -0.55, 0.5, 0.25, 0.5, -0.15, "orange", "Cushion")
end

-- Striped Tent (3 x 3): a roof of clay and cream stripes on poles, the back and the gables closed, the sides rolled
-- up, the front flaps tied open, a gold trim with flaps along the eave, a rug and cushions inside, a lantern at the
-- door, a pennant on the ridge.
M.stripedtent = function(m, f)
	local eave, ridge = 1.5, 2.5
	local function stripe(i: number): string
		return if i % 2 == 0 then "clay" else "cream"
	end
	for i = 0, 5 do
		local x = -1.25 + i * 0.5
		Parts.wedge(m, f, x, eave + 0.5, 0.625, 0.5, 1, 1.25, stripe(i), math.pi, "Roof")
		Parts.wedge(m, f, x, eave + 0.5, -0.625, 0.5, 1, 1.25, stripe(i), 0, "Roof")
		Parts.box(m, f, x, eave / 2, -1.125, 0.5, eave, 0.25, stripe(i + 1), "Wall")
	end
	Parts.log(m, f, 0, ridge + 0.05, 0, 3, 0.25, "wood_dark", "Ridge")
	for _, x in { -1.375, 1.375 } do
		Parts.wedge(m, f, x, eave + 0.5, -0.5, 0.25, 1, 1, "cream", 0, "Gable")
		Parts.wedge(m, f, x, eave + 0.5, 0.5, 0.25, 1, 1, "cream", math.pi, "Gable")
		Parts.box(m, f, x, ridge / 2, 0, 0.25, ridge, 0.25, "wood_dark", "Pole")
		for _, z in { -1.125, 1.125 } do
			Parts.box(m, f, x, eave / 2, z, 0.25, eave, 0.25, "wood_dark", "Pole")
		end
		Parts.logZ(m, f, x, eave - 0.2, 0, 2, 0.5, "clay", "Roll")
	end
	-- the eave's trim and flaps
	Parts.box(m, f, 0, eave - 0.1, 1.2, 3, 0.25, 0.25, "gold", "Trim")
	for i = 0, 5 do
		Parts.box(m, f, -1.25 + i * 0.5, eave - 0.35, 1.2, 0.25, 0.25, 0.25, stripe(i), "Fringe")
	end
	-- the door flaps tied back
	for _, s in { -1, 1 } do
		Parts.at(m, f, CFrame.new(s * 1.05, eave - 0.6, 1.05) * CFrame.Angles(0, 0, s * 0.3), 0.5, 1, 0.25, "clay", "Flap")
		Parts.box(m, f, s * 1.12, eave - 0.75, 1.1, 0.25, 0.25, 0.25, "gold", "Tie")
	end
	-- inside: a rug, cushions, a tray table
	Parts.box(m, f, 0, 0, -0.05, 2.5, 0.25, 2, "gold", "Rug")
	Parts.box(m, f, 0, 0.01, -0.05, 2.25, 0.25, 1.75, "berry_red", "Rug")
	Parts.log(m, f, 0, 0.3, -0.75, 1.5, 0.5, "orange", "Bolster")
	Parts.box(m, f, -0.75, 0.25, -0.2, 0.5, 0.25, 0.5, "teal", "Cushion")
	Parts.box(m, f, 0.8, 0.25, -0.3, 0.5, 0.25, 0.5, "teal", "Cushion")
	Parts.cyl(m, f, 0.1, 0.2, 0.15, 0.25, 0.25, "wood_dark", "Stand")
	Parts.cyl(m, f, 0.1, 0.38, 0.15, 0.75, 0.25, "gold", "Tray")
	Parts.ball(m, f, 0.1, 0.58, 0.15, 0.25, "teal", "Teapot")
	-- the lantern at the door
	Parts.box(m, f, 0, eave - 0.45, 1.2, 0.25, 0.25, 0.25, "wood_dark", "Chain")
	Parts.box(m, f, 0, eave - 0.7, 1.2, 0.25, 0.25, 0.25, "gold", "Lantern")
	Parts.glow(m, f, 0, eave - 0.95, 1.2, 0.25, 0.25, 0.25, "yellow", "Lamp")
	pennant(m, f, 0, ridge + 0.75, 0, 0.75, "teal")
end

-- Sandstone Arch (3 x 1): two carved pillars on plinths, a round arch of darker stones with a clay keystone, carved
-- panels over its shoulders, a lintel with a teal band of tiles and clay diamonds, battlements on top, sand drifted at
-- its feet, a lantern hung in the arch.
M.sandarch = function(m, f)
	local spring, r = 2, 0.85
	for _, s in { -1, 1 } do
		local x = s * 1.0
		Parts.box(m, f, x, 0.25, 0, 1, 0.5, 1, "sand_dark", "Plinth")
		Parts.box(m, f, x, 1.125, 0, 0.75, 1.25, 0.75, "sand", "Pillar")
		Parts.box(m, f, x, 1.1, 0.3, 0.25, 0.75, 0.25, "sand_dark", "Groove")
		Parts.box(m, f, x, spring - 0.125, 0, 1, 0.25, 1, "sand_dark", "Capital")
		Parts.wedge(m, f, s * 1.25, 0.12, 0.25, 0.5, 0.25, 0.5, "sand", 0, "Drift")
		-- the carved panels over the arch's shoulders, set back from its face
		Parts.box(m, f, s * 1.0, 2.85, -0.05, 0.75, 0.5, 0.5, "sand", "Spandrel")
		Parts.box(m, f, s * 1.125, 2.375, -0.05, 0.5, 0.75, 0.5, "sand", "Spandrel")
	end
	-- the arch: stones round a half circle, the keystone in clay
	for k = 0, 8 do
		local a = math.pi * k / 8
		Parts.at(m, f, CFrame.new(-math.cos(a) * r, spring + math.sin(a) * r, 0) * CFrame.Angles(0, 0, math.pi / 2 - a), 0.5, 0.5, if k == 4 then 1 else 0.75, if k == 4 then "clay" else "sand_dark", "Arch")
	end
	-- the lintel, its band of tiles, battlements
	Parts.box(m, f, 0, 3.35, 0, 3, 0.5, 0.75, "sand", "Lintel")
	Parts.box(m, f, 0, 3.35, 0.3, 2.5, 0.25, 0.25, "teal", "Tiles")
	for _, x in { -0.75, 0.75 } do
		Parts.at(m, f, CFrame.new(x, 3.35, 0.36) * CFrame.Angles(0, 0, math.pi / 4), 0.25, 0.25, 0.25, "clay", "Diamond")
	end
	Parts.box(m, f, 0, 3.7, 0, 3, 0.25, 1, "sand_dark", "Cornice")
	for _, x in { -1.25, -0.4, 0.4, 1.25 } do
		Parts.box(m, f, x, 4.05, 0, 0.5, 0.5, 0.75, "sand", "Merlon")
	end
	-- a lantern hung in the arch
	Parts.box(m, f, 0, 2.5, 0, 0.25, 0.25, 0.25, "wood_dark", "Chain")
	Parts.box(m, f, 0, 2.27, 0, 0.25, 0.25, 0.25, "gold", "Lantern")
	Parts.glow(m, f, 0, 2.05, 0, 0.25, 0.25, 0.25, "yellow", "Lamp")
	Parts.box(m, f, 0, 1.83, 0, 0.25, 0.25, 0.25, "gold", "Lantern")
end

------------------------------------------------------------------ the fairy glade
-- A toadstool at (x, z): a cream stalk, a flat cap of colour `cap` (Neon when `lit`) with a dome on it when it is big.
local function toadstool(m: Model, f: CFrame, x: number, z: number, size: number, cap: string, lit: boolean)
	if size >= 3 then
		Parts.cyl(m, f, x, 0.375, z, 0.5, 0.75, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.8, z, 1, 0.25, cap, "Cap", lit)
		Parts.ball(m, f, x, 0.925, z, 0.75, cap, "Cap")
		for _, d in { v(0.6, 0.6, 0.5), v(-0.5, 0.7, 0.4), v(0.1, 1, -0.2) } do
			dot(m, f, v(x, 0.925, z), 0.375, d, 0.1, "white", "Spot")
		end
	elseif size == 2 then
		Parts.cyl(m, f, x, 0.3, z, 0.25, 0.6, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.62, z, 0.75, 0.25, cap, "Cap", lit)
		Parts.ball(m, f, x, 0.745, z, 0.5, cap, "Cap")
	else
		Parts.cyl(m, f, x, 0.2, z, 0.25, 0.4, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.42, z, 0.5, 0.25, cap, "Cap", lit)
	end
end

-- Fairy Lantern (1 x 1): a jar of tiny lights in many colours hung from a crook over a mossy patch, a few lights loose
-- round it, a little pink toadstool.
M.fairylantern = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "moss", "Moss")
	local post = ACROSS * -0.3
	Parts.box(m, f, post.X, 0.85, post.Z, 0.25, 1.7, 0.25, "wood_dark", "Crook")
	seg(m, f, post + v(0, 1.62, 0), ACROSS * 0.02 + v(0, 1.82, 0), 0.25, "wood_dark", "Crook")
	seg(m, f, ACROSS * 0.02 + v(0, 1.82, 0), ACROSS * 0.24 + v(0, 1.66, 0), 0.25, "wood_dark", "Crook")
	local jar = ACROSS * 0.24 + v(0, 0.92, 0)
	Parts.box(m, f, jar.X, 1.47, jar.Z, 0.25, 0.25, 0.25, "straw", "Cord")
	Parts.cyl(m, f, jar.X, 1.3, jar.Z, 0.5, 0.25, "gold", "Lid")
	Parts.cyl(m, f, jar.X, jar.Y, jar.Z, 0.5, 0.5, "cream", "Jar", true)
	Parts.cyl(m, f, jar.X, 0.55, jar.Z, 0.5, 0.25, "window", "Glass")
	for i, d in { v(0.2, 0.15, 1), v(1, -0.35, 0.3), v(-0.6, -0.2, 0.8), v(0.7, 0.4, 0.6) } do
		local c = if i == 1 then "pink" elseif i == 2 then "crystal" elseif i == 3 then "teal" else "pink"
		dot(m, f, jar, 0.25, TOWARD * d, 0.07, c, "Firefly", true)
	end
	Parts.glow(m, f, 0.38, 1.55, 0.25, 0.25, 0.25, 0.25, "pink", "Firefly")
	Parts.glow(m, f, -0.05, 0.6, 0.4, 0.25, 0.25, 0.25, "yellow", "Firefly")
	Parts.glow(m, f, 0.42, 0.45, -0.05, 0.25, 0.25, 0.25, "crystal", "Firefly")
	toadstool(m, f, 0.28, 0.28, 1, "pink", false)
end

-- Mushroom Ring (3 x 3): toadstools in a ring of moss, two big spotted ones (one with a little door), some glowing
-- softly, lights floating over the grass inside.
M.mushroomring = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 3, 0.25, "moss", "Ring")
	Parts.cyl(m, f, 0, 0.01, 0, 2, 0.25, "grass", "Lawn")
	local ring = {
		{ a = 45, size = 3, cap = "berry_red", lit = false },
		{ a = 90, size = 1, cap = "crystal", lit = true },
		{ a = 130, size = 2, cap = "pink", lit = false },
		{ a = 175, size = 1, cap = "berry_red", lit = false },
		{ a = 225, size = 3, cap = "pink", lit = false },
		{ a = 265, size = 1, cap = "teal", lit = true },
		{ a = 305, size = 2, cap = "berry_red", lit = false },
		{ a = 345, size = 1, cap = "pink", lit = true },
		{ a = 15, size = 1, cap = "purple", lit = false },
	}
	for _, t in ring do
		local a = math.rad(t.a)
		local rr = if t.size >= 3 then 1.0 else 1.15
		toadstool(m, f, math.cos(a) * rr, math.sin(a) * rr, t.size, t.cap, t.lit)
	end
	-- the little door in the big one at the front
	local da = math.rad(45)
	Parts.box(m, f, math.cos(da) * 1.0 + 0.05, 0.25, math.sin(da) * 1.0 + 0.19, 0.25, 0.5, 0.25, "wood_dark", "Door")
	for _, l in { { x = 0.2, y = 0.7, z = -0.1, c = "cream" }, { x = -0.35, y = 1.0, z = 0.2, c = "pink" }, { x = 0.1, y = 1.3, z = 0.35, c = "crystal" }, { x = -0.1, y = 0.5, z = -0.45, c = "yellow" } } do
		Parts.glow(m, f, l.x, l.y, l.z, 0.25, 0.25, 0.25, l.c, "Wisp")
	end
end

-- Moonstone (2 x 2): a pale standing stone on a mossy mound, a crescent moon set in its face and two marks under it
-- that glow, small pale stones round it, two of them glowing.
M.moonstone = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1.75, 0.25, "moss", "Moss")
	Parts.box(m, f, 0, 0.7, -0.05, 1, 1.25, 0.75, "steel", "Stone")
	Parts.turned(m, f, -0.05, 1.6, -0.05, 0.75, 0.75, 0.75, -0.1, "steel", "Stone")
	Parts.ball(m, f, -0.05, 2.0, -0.05, 0.75, "steel", "Stone")
	-- the crescent: a glowing disc half hidden by a disc of stone
	disc(m, f, -0.02, 0.95, 0.24, 0.75, "white", "Moon", true)
	disc(m, f, 0.16, 1.05, 0.255, 0.75, "steel", "Stone")
	for _, x in { -0.25, 0.25 } do
		Parts.glow(m, f, x, 0.35, 0.24, 0.25, 0.25, 0.25, "crystal", "Mark")
	end
	Parts.box(m, f, -0.3, 0.2, 0.25, 0.5, 0.25, 0.5, "moss", "Moss")
	-- pale stones round it
	for i, s in { { 0.75, 0.45 }, { -0.7, 0.55 }, { 0.65, -0.6 }, { -0.75, -0.45 }, { 0.05, 0.8 } } do
		local lit = i == 2 or i == 3
		local b = Parts.ball(m, f, s[1], 0.1, s[2], if i == 5 then 0.25 else 0.5, if lit then "ice" else "steel", "Pebble")
		if lit then
			b.Material = Enum.Material.Neon
		end
	end
end

-- Wishing Well (2 x 2): a round well of grey stone with a pale rim, water with coins shining in it, two posts under a
-- little lilac roof, the rope wound on its axle, a bucket on the rim, a lamp on a post, pink flowers climbing it.
M.wishingwell = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 2, 0.25, "rock_dark", "Paving")
	Parts.cyl(m, f, 0, 0.275, 0, 1.5, 0.5, "rock", "Wall")
	Parts.cyl(m, f, 0, 0.65, 0, 1.5, 0.25, "rock_dark", "Wall")
	pool(m, f, 0, 0.68, 0, 1)
	for k = 0, 7 do
		local a = k * math.pi / 4
		Parts.turned(m, f, math.cos(a) * 0.625, 0.9, math.sin(a) * 0.625, 0.5, 0.25, 0.25, math.pi / 2 - a, "pavement", "Rim")
	end
	for _, c in { { 0.15, 0.12 }, { -0.2, -0.12 }, { 0.12, -0.28 } } do
		Parts.glow(m, f, c[1], 0.69, c[2], 0.25, 0.25, 0.25, "gold", "Coin")
	end
	-- posts, the axle with its rope, the roof
	for _, x in { -0.8, 0.8 } do
		Parts.box(m, f, x, 0.875, 0, 0.25, 1.75, 0.25, "wood", "Post")
	end
	Parts.log(m, f, 0, 1.45, 0, 1.75, 0.25, "wood_dark", "Axle")
	Parts.log(m, f, 0, 1.45, 0, 0.5, 0.5, "straw", "Rope")
	Parts.wedge(m, f, 0, 2.0, -0.375, 2, 0.5, 0.75, "crystal", 0, "Roof")
	Parts.wedge(m, f, 0, 2.0, 0.375, 2, 0.5, 0.75, "crystal", math.pi, "Roof")
	Parts.log(m, f, 0, 2.28, 0, 2, 0.25, "purple", "Ridge")
	-- a lamp on the left post
	Parts.box(m, f, -0.8, 1.35, 0.2, 0.25, 0.25, 0.25, "gold", "LampCap")
	Parts.glow(m, f, -0.8, 1.12, 0.2, 0.25, 0.25, 0.25, "cream", "Lamp")
	-- the bucket on the rim
	Parts.cyl(m, f, 0.42, 1.15, 0.42, 0.5, 0.25, "wood", "Bucket")
	Parts.cyl(m, f, 0.42, 1.22, 0.42, 0.25, 0.25, "steel_dark", "Handle")
	-- flowers climbing the right post
	for i, y in { 0.45, 0.85, 1.3 } do
		Parts.box(m, f, 0.8 + (if i == 2 then -0.1 else 0.1), y, 0.15, 0.25, 0.25, 0.25, if i == 2 then "moss" else "pink", "Bloom")
	end
end

-- Crystal Arch (3 x 1): two crystals, one lilac and one pink, grown up from mossy rocks, darker at the root and paler
-- up their length, bent over to cross at the top where a light hangs; small crystals at their feet, lights drifting
-- under the arch.
M.crystalarch = function(m, f)
	for _, s in { -1, 1 } do
		local tones = if s < 0 then { "purple", "crystal", "crystal" } else { "pink", "pink", "cherry" }
		local z = s * 0.12
		Parts.ball(m, f, s * 1.05, 0.12, 0, 0.75, "rock", "Rock")
		Parts.ball(m, f, s * 1.3, 0.05, 0.25, 0.5, "rock_dark", "Rock")
		Parts.box(m, f, s * 1.0, 0.4, -0.05, 0.5, 0.25, 0.5, "moss", "Moss")
		-- the crystal, bending over the middle and past it
		local pts = { v(s * 1.0, 0.25, z), v(s * 0.98, 1.3, z), v(s * 0.62, 2.4, z), v(-s * 0.25, 3.0, z) }
		local d = Vector3.yAxis
		for i = 1, 3 do
			local a, b = pts[i], pts[i + 1]
			d = (b - a).Unit
			seg(m, f, a - d * 0.2, b + d * 0.2, 0.5, tones[i], "Crystal", i == 3, math.pi / 4)
			-- a small crystal growing out of the bend
			if i < 3 then
				seg(m, f, b, b + v(s * 0.35, 0.3, 0), 0.25, tones[i + 1], "Crystal", true, math.pi / 4)
			end
		end
		seg(m, f, pts[4] + d * 0.1, pts[4] + d * 0.55, 0.25, "white", "Tip", true, math.pi / 4)
		-- small crystals at its foot
		for k, c in { { 1.3, 0.25, 1.45, 0.75, 0.3 }, { 0.75, 0.25, 0.6, 0.6, 0.3 }, { 1.25, -0.25, 1.42, 0.65, -0.3 } } do
			seg(m, f, v(s * c[1], 0.1, c[2]), v(s * c[3], c[4], c[5]), 0.25, if k == 2 then "ice" else tones[2], "Crystal", k == 1, math.pi / 4)
		end
	end
	Parts.ball(m, f, 0, 3.05, 0, 0.5, "white", "Orb").Material = Enum.Material.Neon
	for _, l in { { x = -0.35, y = 1.0, z = 0.2, c = "pink" }, { x = 0.3, y = 1.6, z = -0.1, c = "crystal" }, { x = 0, y = 0.55, z = 0.25, c = "cream" } } do
		Parts.glow(m, f, l.x, l.y, l.z, 0.25, 0.25, 0.25, l.c, "Wisp")
	end
	for _, c in { { -0.55, 0.3 }, { 0.6, -0.3 }, { 0.5, 0.35 } } do
		Parts.box(m, f, c[1], 0.1, c[2], 0.25, 0.25, 0.25, "pink", "Flower")
	end
end

------------------------------------------------------------------ the zen garden
-- Bamboo Screen (2 x 1): canes in a panel between two thick posts with knots, two rails across tied with cord, on a
-- stone curb, moss at its foot.
M.bambooscreen = function(m, f)
	Parts.box(m, f, 0, 0, 0, 2, 0.25, 0.5, "rock", "Curb")
	for _, x in { -0.75, 0.75 } do
		Parts.cyl(m, f, x, 0.5, 0, 0.5, 1, "bamboo", "Post")
		Parts.cyl(m, f, x, 1.125, 0, 0.5, 0.25, "straw", "Knot")
		Parts.cyl(m, f, x, 1.5, 0, 0.5, 0.5, "bamboo", "Post")
	end
	for i, x in { -0.375, -0.125, 0.125, 0.375 } do
		local h = if i % 2 == 0 then 1.5 else 1.25
		Parts.cyl(m, f, x, 0.1 + h / 2, 0, 0.25, h, if i == 3 then "straw" else "bamboo", "Cane")
	end
	for _, y in { 0.45, 1.05 } do
		Parts.log(m, f, 0, y, 0.2, 1.5, 0.25, "bamboo", "Rail")
		for _, x in { -0.5, 0.5 } do
			Parts.box(m, f, x, y, 0.22, 0.25, 0.25, 0.25, "wood_dark", "Cord")
		end
	end
	Parts.ball(m, f, -0.55, 0.1, 0.3, 0.5, "moss", "Moss")
	Parts.ball(m, f, 0.3, 0.05, 0.32, 0.25, "moss", "Moss")
end

-- Wind Chimes (1 x 1): a bamboo post with an arm, a wooden plate hung from it, three tubes of different lengths (one
-- of brass) and a paper strip that catches the wind, a flat stone at its foot.
M.windchime = function(m, f)
	Parts.cyl(m, f, 0.05, 0.02, 0.05, 0.75, 0.25, "rock", "Stone")
	Parts.box(m, f, -0.3, 0.08, -0.25, 0.5, 0.25, 0.25, "moss", "Moss")
	local post = ACROSS * -0.45
	local c = ACROSS * 0.15
	Parts.cyl(m, f, post.X, 1.0, post.Z, 0.25, 2, "bamboo", "Post")
	seg(m, f, post + v(0, 1.9, 0), c + v(0, 1.9, 0), 0.25, "bamboo", "Arm")
	Parts.box(m, f, post.X, 1.9, post.Z, 0.25, 0.25, 0.25, "wood_dark", "Cord")
	Parts.box(m, f, c.X, 1.72, c.Z, 0.25, 0.25, 0.25, "wood_dark", "Cord")
	Parts.cyl(m, f, c.X, 1.55, c.Z, 0.75, 0.25, "wood", "Plate")
	for k, len in { 0.75, 0.5, 0.75 } do
		local p = c + ACROSS * ((k - 2) * 0.28) + v(0, 1.425 - len / 2, 0)
		sway(Parts.cyl(m, f, p.X, p.Y, p.Z, 0.25, len, if k == 3 then "gold" else "steel", "Chime"))
	end
	-- the paper strip on a cord under the short middle tube
	sway(Parts.box(m, f, c.X, 0.95, c.Z, 0.25, 0.25, 0.25, "wood_dark", "Clapper"))
	sway(Parts.box(m, f, c.X, 0.6, c.Z, 0.25, 0.5, 0.25, "paper", "Paper"))
end

-- Stone Lantern (1 x 1): a grey stone lantern: base, round pillar, a light box with its glow showing between the
-- corners, a wide roof with turned-up corners, a knob on top, moss.
M.stonelantern = function(m, f)
	Parts.box(m, f, 0, 0.125, 0, 0.75, 0.25, 0.75, "rock_dark", "Base")
	Parts.cyl(m, f, 0, 0.5, 0, 0.5, 0.5, "rock", "Pillar")
	Parts.box(m, f, 0, 0.875, 0, 0.75, 0.25, 0.75, "rock", "Shelf")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.25, 1.25, c[2] * 0.25, 0.25, 0.5, 0.25, "rock", "Corner")
	end
	Parts.glow(m, f, 0, 1.25, 0, 0.5, 0.5, 0.5, "yellow", "Light")
	Parts.box(m, f, 0, 1.625, 0, 1, 0.25, 1, "rock", "Roof")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.4, 1.75, c[2] * 0.4, 0.25, 0.25, 0.25, "rock", "Eave")
	end
	Parts.box(m, f, 0, 1.875, 0, 0.75, 0.25, 0.75, "rock_dark", "Roof")
	Parts.box(m, f, 0, 2.1, 0, 0.5, 0.25, 0.5, "rock", "Roof")
	Parts.ball(m, f, 0, 2.35, 0, 0.25, "rock", "Knob")
	Parts.box(m, f, -0.25, 1.78, 0.25, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.25, 0.3, 0.3, 0.25, 0.25, 0.25, "moss", "Moss")
end

-- Water Basin (1 x 1): a round stone bowl of still water on a bed of pale pebbles, a bamboo pipe dripping into it,
-- moss and a fern.
M.zenbasin = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "pavement", "Pebbles")
	for _, p in { { -0.38, -0.05 }, { 0.38, 0.3 }, { -0.1, 0.42 } } do
		Parts.ball(m, f, p[1], 0.06, p[2], 0.25, "rock_dark", "Pebble")
	end
	local b = ACROSS * 0.12 + v(0.05, 0, 0.05)
	Parts.cyl(m, f, b.X, 0.3, b.Z, 0.75, 0.5, "rock", "Bowl")
	pool(m, f, b.X, 0.44, b.Z, 0.5)
	local post = ACROSS * -0.42 + v(0.02, 0, 0.02)
	Parts.cyl(m, f, post.X, 0.5, post.Z, 0.25, 1, "bamboo", "Pipe")
	seg(m, f, post + v(0, 0.95, 0), b + v(0, 0.78, 0) - ACROSS * 0.05, 0.25, "bamboo", "Spout")
	Parts.box(m, f, b.X - 0.02, 0.66, b.Z + 0.02, 0.25, 0.25, 0.25, "shallow", "Drip")
	Parts.box(m, f, b.X + 0.3, 0.35, b.Z - 0.05, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.ball(m, f, -0.3, 0.2, -0.35, 0.5, "leaf", "Fern")
end

-- Lantern Tower (2 x 2): a tall stone lantern: a stepped base, a light chamber glowing between its corners, five
-- slate roofs stacked high with turned-up corners and a short stone neck between each, a knob on top, moss.
M.lanterntower = function(m, f)
	Parts.box(m, f, 0, 0.1, 0, 1.75, 0.25, 1.75, "rock_dark", "Base")
	Parts.box(m, f, 0, 0.475, 0, 1.25, 0.5, 1.25, "rock", "Base")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.375, 1.1, c[2] * 0.375, 0.25, 0.75, 0.25, "rock", "Corner")
	end
	Parts.glow(m, f, 0, 1.1, 0, 0.75, 0.75, 0.75, "yellow", "Light")
	local y = 1.475
	for i = 0, 4 do
		local w = 1.75 - i * 0.25
		Parts.box(m, f, 0, y + 0.125, 0, w, 0.25, w, "slate", "Roof")
		Parts.box(m, f, 0, y + 0.375, 0, w - 0.5, 0.25, w - 0.5, "slate", "Roof")
		local e = w / 2 - 0.125
		for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			Parts.box(m, f, c[1] * e, y + 0.25, c[2] * e, 0.25, 0.25, 0.25, "slate", "Eave")
		end
		if i < 4 then
			Parts.box(m, f, 0, y + 0.625, 0, 0.5, 0.25, 0.5, "rock", "Neck")
		end
		y += 0.75
	end
	Parts.box(m, f, 0, y - 0.125, 0, 0.25, 0.25, 0.25, "rock", "Neck")
	Parts.ball(m, f, 0, y + 0.1, 0, 0.5, "rock", "Knob")
	Parts.ball(m, f, 0, y + 0.45, 0, 0.25, "rock", "Knob")
	Parts.box(m, f, -0.55, 1.85, 0.55, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.6, 0.3, 0.75, 0.5, 0.25, 0.25, "moss", "Moss")
end

------------------------------------------------------------------ the volcano
-- Fire Basin (1 x 1): an iron bowl on three legs over a slab of basalt, glowing coals, flames in three colours, sparks
-- rising.
M.firebasin = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "basalt", "Slab")
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 6
		seg(m, f, v(math.cos(a) * 0.38, 0.05, math.sin(a) * 0.38), v(math.cos(a) * 0.18, 0.6, math.sin(a) * 0.18), 0.25, "black", "Leg")
	end
	Parts.ball(m, f, 0, 0.62, 0, 0.5, "black", "Bowl")
	Parts.cyl(m, f, 0, 0.8, 0, 0.75, 0.25, "black", "Bowl")
	Parts.cyl(m, f, 0, 0.95, 0, 1, 0.25, "steel_dark", "Rim")
	Parts.cyl(m, f, 0, 1.02, 0, 0.75, 0.25, "basalt", "Coals")
	Parts.glow(m, f, 0.25, 1.05, 0.12, 0.25, 0.25, 0.25, "lava", "Ember")
	Parts.glow(m, f, -0.2, 1.05, -0.2, 0.25, 0.25, 0.25, "lava", "Ember")
	-- the flames
	Parts.at(m, f, CFrame.new(0, 1.35, 0) * CFrame.Angles(0, math.pi / 4, 0), 0.5, 0.5, 0.5, "lava", "Flame", true)
	Parts.at(m, f, CFrame.new(0.06, 1.7, 0.04) * CFrame.Angles(0, 0.3, 0.15), 0.25, 0.5, 0.25, "orange", "Flame", true)
	Parts.glow(m, f, -0.04, 1.98, -0.03, 0.25, 0.25, 0.25, "yellow", "Flame")
	Parts.glow(m, f, -0.22, 1.35, 0.15, 0.25, 0.25, 0.25, "orange", "Flame")
	Parts.glow(m, f, 0.2, 1.3, -0.15, 0.25, 0.25, 0.25, "orange", "Flame")
	Parts.glow(m, f, 0.2, 2.3, 0.1, 0.25, 0.25, 0.25, "yellow", "Spark")
	Parts.glow(m, f, -0.15, 2.6, 0.0, 0.25, 0.25, 0.25, "lava", "Spark")
end

-- Steam Vent (2 x 2): a low cone of basalt with a glowing mouth, yellow crust round it, cracks of lava in the ground,
-- dark rocks, steam rolling up and drifting.
M.steamvent = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1.75, 0.25, "basalt", "Ground")
	Parts.turned(m, f, 0.4, 0.005, 0.45, 1, 0.25, 0.75, 0.5, "basalt", "Ground")
	Parts.cyl(m, f, -0.1, 0.25, -0.1, 1, 0.5, "basalt", "Cone")
	Parts.cyl(m, f, -0.1, 0.6, -0.1, 0.75, 0.25, "basalt", "Cone")
	Parts.cyl(m, f, -0.1, 0.62, -0.1, 0.5, 0.25, "lava", "Mouth", true)
	for _, s in { { 0.25, 0.48, 0.15 }, { -0.45, 0.45, 0.05 }, { -0.05, 0.48, 0.35 } } do
		Parts.box(m, f, s[1], s[2], s[3], 0.25, 0.25, 0.25, "yellow", "Crust")
	end
	for i, r in { { 0.6, 0.15, -0.55, 0.75 }, { -0.65, 0.1, 0.5, 0.5 }, { 0.7, 0.1, 0.5, 0.5 } } do
		Parts.ball(m, f, r[1], r[2], r[3], r[4], if i == 3 then "rock_dark" else "basalt", "Rock")
	end
	for _, c in { { 0.5, 0.15, 0.4, 0.75 }, { -0.55, -0.4, -0.7, 0.5 }, { 0.05, 0.62, 1.3, 0.5 } } do
		Parts.turned(m, f, c[1], 0.02, c[2], c[4], 0.25, 0.25, c[3], "lava", "Crack", true)
	end
	-- the steam
	for _, p in { { -0.1, 1.05, -0.1, 0.5 }, { 0, 1.5, -0.15, 0.75 }, { 0.15, 2.05, -0.25, 0.75 }, { 0.3, 2.55, -0.3, 0.5 }, { 0.45, 2.9, -0.35, 0.5 } } do
		sway(Parts.ball(m, f, p[1], p[2], p[3], p[4], "white", "Steam"))
	end
end

-- A shard of black glass standing at (x, z), side on to the view so its point shows: a square shaft of width a and
-- height h with a wedge for a point, leaning by `lean` across the view.
local function shard(m: Model, f: CFrame, x: number, z: number, flip: boolean, lean: number, a: number, h: number, tip: number, color: string)
	local c = CFrame.new(x, 0, z) * CFrame.Angles(0, if flip then 3 * VIEW else -VIEW, 0) * CFrame.Angles(lean, 0, 0)
	Parts.at(m, f, c * CFrame.new(0, h / 2, 0), a, h, a, color, "Shard")
	wedgeAt(m, f, c * CFrame.new(0, h + tip / 2, 0), a, tip, a, color, "Shard")
end

-- Obsidian Spire (2 x 2): a tall spire of black glass narrowing to a sharp point with a sheen down one edge and a
-- molten seam at its foot, smaller blades leaning out round it, rubble and veins of lava in the basalt.
M.obsidian = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1.75, 0.25, "basalt", "Ground")
	for _, c in { { 0.55, 0.45, 0.6, 0.75 }, { -0.6, 0.3, 2.2, 0.5 }, { 0.1, -0.7, 1.4, 0.5 } } do
		Parts.turned(m, f, c[1], 0.02, c[2], c[4], 0.25, 0.25, c[3], "lava", "Vein", true)
	end
	for _, r in { { 0.7, -0.55, 0.5 }, { -0.7, -0.5, 0.5 }, { -0.35, 0.7, 0.25 } } do
		Parts.ball(m, f, r[1], 0.12, r[2], r[3], "basalt", "Rubble")
	end
	-- the spire: a broad foot, a narrower shaft, the point
	local c = CFrame.new(-0.1, 0, -0.1) * CFrame.Angles(0, -VIEW, 0) * CFrame.Angles(0.06, 0, 0)
	Parts.at(m, f, c * CFrame.new(0, 0.875, 0), 0.75, 1.75, 0.75, "black", "Spire")
	Parts.at(m, f, c * CFrame.new(0, 2.25, 0.08), 0.5, 1, 0.5, "black", "Spire")
	wedgeAt(m, f, c * CFrame.new(0, 3.375, 0.08), 0.5, 1.25, 0.5, "black", "Spire")
	Parts.at(m, f, c * CFrame.new(0.3, 1.1, 0.3), 0.25, 1.5, 0.25, "slate", "Sheen")
	Parts.at(m, f, c * CFrame.new(-0.2, 0.35, 0.32), 0.25, 0.5, 0.25, "lava", "Seam", true)
	-- blades round it
	shard(m, f, 0.45, 0.4, false, -0.3, 0.5, 0.75, 0.75, "night")
	shard(m, f, -0.55, 0.25, true, 0.3, 0.5, 1, 0.75, "black")
	shard(m, f, 0.55, -0.45, true, -0.25, 0.25, 0.5, 0.5, "black")
	shard(m, f, -0.45, -0.5, false, 0.3, 0.5, 0.5, 0.75, "night")
end

-- Lava Pool (3 x 3): a pool of glowing lava hotter at its heart, crusts of rock floating on it, bubbles, a ring of
-- basalt boulders with a gap where a rivulet escapes, a heap of rock at the back with lava trickling down it, black
-- shards.
M.lavapool = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 3, 0.25, "basalt", "Ground")
	Parts.cyl(m, f, 0, 0.05, 0.1, 2.25, 0.25, "lava", "Lava", true)
	Parts.cyl(m, f, -0.2, 0.06, 0.2, 1, 0.25, "orange", "Lava", true)
	Parts.cyl(m, f, -0.3, 0.07, 0.3, 0.5, 0.25, "yellow", "Lava", true)
	Parts.turned(m, f, 0.45, 0.08, 0.5, 0.5, 0.25, 0.75, 0.6, "basalt", "Crust")
	Parts.turned(m, f, -0.6, 0.08, -0.25, 0.75, 0.25, 0.5, 1.2, "black", "Crust")
	Parts.ball(m, f, 0.4, 0.12, -0.3, 0.5, "orange", "Bubble").Material = Enum.Material.Neon
	Parts.ball(m, f, -0.65, 0.18, 0.45, 0.25, "yellow", "Bubble").Material = Enum.Material.Neon
	Parts.ball(m, f, 0.15, 0.2, 0.75, 0.25, "yellow", "Bubble").Material = Enum.Material.Neon
	-- the ring of boulders, a gap at the front right
	for k = 0, 9 do
		local a = k * math.pi * 2 / 11 + 1.1
		Parts.ball(m, f, math.cos(a) * 1.28, 0.1, 0.1 + math.sin(a) * 1.22, if k % 3 == 0 then 0.75 else 0.5, if k % 4 == 1 then "rock_dark" else "basalt", "Boulder")
	end
	Parts.turned(m, f, 1.0, 0.03, 1.0, 0.25, 0.25, 0.75, -math.pi / 4, "lava", "Rivulet", true)
	-- the heap at the back and its trickle
	Parts.ball(m, f, -0.55, 0.25, -1.05, 1, "basalt", "Heap")
	Parts.ball(m, f, -0.15, 0.6, -1.15, 0.75, "basalt", "Heap")
	seg(m, f, v(-0.25, 0.85, -0.95), v(-0.12, 0.2, -0.62), 0.25, "lava", "Trickle", true)
	shard(m, f, 0.75, -0.95, false, -0.2, 0.25, 0.75, 0.5, "black")
	shard(m, f, 1.05, -0.6, true, 0.25, 0.25, 0.5, 0.5, "night")
end

return M
