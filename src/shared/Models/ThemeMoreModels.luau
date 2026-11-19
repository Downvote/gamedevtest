--!strict
-- The themed decor, part two (GAME_DESIGN 4; Data/Buildings): frost, autumn, the desert, the fairy glade, the zen
-- garden and the volcano. Roblox module. Each theme keeps to one palette so an island built in it hangs together: frost
-- in snow and ice with red; autumn in maple, orange, straw and brown; the desert in sand, clay and striped cloth; the
-- fairy glade in crystal and pink with soft lights; the zen garden in grey stone, bamboo and moss; the volcano in black
-- basalt with glowing lava. Lights (candles, lava, crystals, fairy lights) are Neon and shine at night.
-- Since the request of 2026-11-19 ("detail all decor more, some having animations, as much as in the bakery game and
-- as much as the work/hut/ main buildings") every piece carries more of its theme's small things, and some parts move
-- (Parts.move): lanterns, bells, chimes and buckets swing on their hooks, lights and bubbles bob, the cider press's
-- capstan turns. Parts named Flame, Smoke, Steam, Teapot, Mug or Sparkle give off sparks, smoke, steam or a twinkle
-- (Controllers/AmbientView); only a few in a piece, as an island keeps a few dozen such spots.
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

-- A four-sided cone w x w and h tall, its foot's middle at (x, y0, z): four corner wedges leaning in to a point (a
-- pine's tier, an obelisk's cap). w is a whole number of half studs.
local QUARTERS = { { -1, 1, 0 }, { 1, 1, math.pi / 2 }, { 1, -1, math.pi }, { -1, -1, -math.pi / 2 } }
local function cone(m: Model, f: CFrame, x: number, y0: number, z: number, w: number, h: number, color: string, name: string, neon: boolean?)
	local q = w / 2
	for _, s in QUARTERS do
		Blocks.part(m, { size = Vector3.new(q, h, q), cf = f * CFrame.new(x + s[1] * q / 2, y0 + h / 2, z + s[2] * q / 2) * CFrame.Angles(0, s[3], 0), color = color, shape = "CornerWedge", name = name, neon = neon, collide = false })
	end
end

-- Marks a part to rock on its hook (Parts.move "swing"): round `axis` through `hub`, `amp` radians either way.
local function swing(p: BasePart, hub: Vector3, axis: string, speed: number, amp: number, phase: number?): BasePart
	return Parts.move(p, "swing", hub, axis, speed, amp, phase)
end

-- A little snowy pine with its foot at (x, y0, z): a stub of trunk, tiers of needles narrowing up, snow on each tier.
local function snowpine(m: Model, f: CFrame, x: number, y0: number, z: number, widths: { number })
	Parts.cyl(m, f, x, y0 + 0.2, z, 0.25, 0.5, "wood_dark", "Trunk")
	local y = y0 + 0.3
	for k, w in widths do
		cone(m, f, x, y, z, w, 0.75, if k % 2 == 1 then "leaf_dark" else "leaf", "Needles")
		Parts.ball(m, f, x + w * 0.3, y + 0.12, z + w * 0.3, 0.25, "snow", "Snow")
		if w >= 1 then
			Parts.ball(m, f, x + w * 0.38, y + 0.08, z - w * 0.1, 0.25, "white", "Snow")
		end
		y += 0.45
	end
	Parts.ball(m, f, x, y + 0.25, z, 0.25, "snow", "Snow")
end

------------------------------------------------------------------ frost
-- Snowman (1 x 1): two snowballs on a drift with lumps of snow round it, looking out at the view: coal eyes, a carrot
-- nose, a pebble smile, two coal buttons, a red scarf with a white stripe at its knot and one end hanging, a bobble hat
-- with a white band, twig arms, one with a forked twig for fingers and one in a red mitten.
M.snowman = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "snow", "Drift")
	Parts.ball(m, f, 0.33, 0.06, 0.3, 0.25, "white", "Snowball")
	Parts.ball(m, f, -0.34, 0.05, 0.28, 0.25, "ice", "Drift")
	Parts.ball(m, f, 0.34, 0.05, -0.3, 0.25, "snow", "Drift")
	local base, head = v(0, 0.45, 0), v(0, 1.22, 0)
	Parts.ball(m, f, base.X, base.Y, base.Z, 1, "snow", "Base")
	Parts.ball(m, f, head.X, head.Y, head.Z, 0.75, "snow", "Head")
	-- the face
	for _, x in { -0.55, 0.55 } do
		dot(m, f, head, 0.375, TOWARD * v(x, 0.28, 0.8), 0.08, "black", "Eye")
	end
	Parts.at(m, f, CFrame.new(head + TOWARD * v(0, -0.06, 0.43)) * TOWARD, 0.25, 0.25, 0.5, "orange", "Nose")
	for _, x in { -0.6, 0.6 } do
		dot(m, f, head, 0.375, TOWARD * v(x, -0.45, 0.65), 0.08, "black", "Smile")
	end
	for _, y in { 0.5, -0.15 } do
		dot(m, f, base, 0.5, TOWARD * v(0, y, 1), 0.08, "black", "Button")
	end
	-- the scarf, one end down the front with a white stripe
	Parts.cyl(m, f, 0, 0.9, 0, 0.5, 0.25, "berry_red", "Scarf")
	local u = (TOWARD * v(0.7, 0, 0.7)).Unit
	seg(m, f, v(0, 0.9, 0) + u * 0.22, v(0, 0.55, 0) + u * 0.4, 0.25, "berry_red", "Scarf")
	local knot = (TOWARD * v(0, 0, 1)) * 0.24
	Parts.box(m, f, knot.X, 0.92, knot.Z, 0.25, 0.25, 0.25, "white", "Stripe")
	-- the bobble hat
	Parts.ball(m, f, 0, 1.56, 0, 0.75, "berry_red", "Hat")
	Parts.cyl(m, f, 0, 1.52, 0, 0.75, 0.25, "white", "HatBand")
	Parts.ball(m, f, 0, 1.99, 0, 0.25, "white", "Bobble")
	-- twig arms out to the sides: a fork of twigs on the left, a mitten on the right
	for _, s in { -1, 1 } do
		local a = ACROSS * s
		local tip = v(0, 1.0, 0) + a * 0.5
		seg(m, f, v(0, 0.72, 0) + a * 0.3, tip, 0.25, "wood_dark", "Twig")
		if s < 0 then
			seg(m, f, tip, tip + v(0, 0.22, 0) + a * 0.05, 0.25, "wood_dark", "Twig")
			seg(m, f, tip - a * 0.1, tip - a * 0.1 + v(0, 0.2, -0.1), 0.25, "wood", "Twig")
		else
			Parts.at(m, f, CFrame.new(tip + v(0, 0.06, 0)) * TOWARD, 0.25, 0.25, 0.25, "berry_red", "Mitten")
		end
	end
end

-- Sled (2 x 1): red runners curling up at the front to brass knobs, struts under a seat of slats on a dark frame, a
-- red back board, a folded blanket with a white stripe, a parcel tied with gold ribbon, the tow rope lying in a loop
-- in the snow, drifts at its ends.
M.sled = function(m, f)
	Parts.box(m, f, -0.15, 0.02, 0, 1.75, 0.25, 0.75, "snow", "Snow")
	Parts.turned(m, f, 0.45, 0.01, 0.15, 0.75, 0.25, 0.5, 0.4, "snow", "Snow")
	Parts.ball(m, f, -0.85, 0.06, 0.28, 0.25, "white", "Drift")
	Parts.ball(m, f, -0.9, 0.05, -0.3, 0.25, "ice", "Drift")
	for _, z in { -0.3, 0.3 } do
		Parts.box(m, f, -0.15, 0.15, z, 1.5, 0.25, 0.25, "berry_red", "Runner")
		seg(m, f, v(0.55, 0.15, z), v(0.85, 0.55, z), 0.25, "berry_red", "Runner")
		seg(m, f, v(0.85, 0.55, z), v(0.65, 0.68, z), 0.25, "berry_red", "Curl")
		Parts.ball(m, f, 0.6, 0.66, z, 0.25, "gold", "Knob")
		for _, x in { -0.65, 0.3 } do
			Parts.box(m, f, x, 0.35, z, 0.25, 0.25, 0.25, "berry_red", "Strut")
		end
	end
	-- the seat: slats on a dark frame, the bar across the front, a back board
	Parts.box(m, f, -0.2, 0.5, 0, 1.5, 0.25, 0.75, "wood_dark", "Frame")
	for _, x in { -0.78, -0.43, -0.08, 0.27 } do
		Parts.box(m, f, x, 0.58, 0.01, 0.25, 0.25, 0.75, "wood", "Slat")
	end
	Parts.logZ(m, f, 0.72, 0.68, 0, 0.75, 0.25, "wood_dark", "Bar")
	Parts.box(m, f, -0.9, 0.85, 0, 0.25, 0.5, 0.75, "berry_red", "Back")
	Parts.box(m, f, -0.9, 1.12, 0, 0.25, 0.25, 0.5, "gold", "BackCap")
	-- a folded blanket, a parcel
	Parts.box(m, f, -0.5, 0.78, 0, 0.5, 0.25, 0.75, "blue", "Blanket")
	Parts.box(m, f, -0.5, 0.8, 0.02, 0.25, 0.25, 0.75, "white", "Stripe")
	Parts.box(m, f, -0.55, 0.98, -0.05, 0.5, 0.25, 0.5, "blue", "Blanket")
	Parts.box(m, f, 0.12, 0.92, 0.02, 0.5, 0.5, 0.5, "green", "Parcel")
	Parts.box(m, f, 0.12, 0.95, 0.05, 0.25, 0.5, 0.5, "gold", "Ribbon")
	Parts.ball(m, f, 0.12, 1.22, 0.02, 0.25, "gold", "Bow")
	-- the tow rope, its loose end in a loop in the snow
	seg(m, f, v(0.78, 0.66, 0), v(0.88, 0.12, 0.25), 0.25, "straw", "Rope")
	seg(m, f, v(0.88, 0.1, 0.25), v(0.5, 0.06, 0.4), 0.25, "straw", "Rope")
	seg(m, f, v(0.5, 0.06, 0.4), v(0.3, 0.06, 0.2), 0.25, "straw", "Rope")
end

-- Ice Lantern (1 x 1): a block of ice on a drift: a pale slab under four ice corners with a frost streak on the front
-- one, a candle's warm light filling the middle, an open rim on top with the flame standing out of it, snow on the rim,
-- icicles under its front edge, chips of ice and lumps of snow round its foot.
M.icelantern = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "snow", "Drift")
	Parts.ball(m, f, 0.26, 0.1, 0.26, 0.5, "snow", "Drift")
	Parts.ball(m, f, -0.36, 0.06, 0.3, 0.25, "ice", "Drift")
	Parts.ball(m, f, 0.36, 0.06, -0.32, 0.25, "white", "Drift")
	Parts.box(m, f, 0, 0.2, 0, 0.75, 0.25, 0.75, "window", "Slab")
	Parts.glow(m, f, 0, 0.7, 0, 0.75, 0.75, 0.75, "yellow", "Candlelight")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.32, 0.7, c[2] * 0.32, 0.25, 0.75, 0.25, "ice", "Ice")
	end
	Parts.box(m, f, -0.34, 0.75, 0.37, 0.25, 0.5, 0.25, "white", "Frost")
	-- the rim round the open top, the flame in it
	Parts.box(m, f, 0, 1.2, 0.375, 1, 0.25, 0.25, "window", "Rim")
	Parts.box(m, f, 0, 1.2, -0.375, 1, 0.25, 0.25, "window", "Rim")
	for _, x in { -0.375, 0.375 } do
		Parts.box(m, f, x, 1.2, 0, 0.25, 0.25, 0.5, "ice", "Rim")
	end
	Parts.glow(m, f, 0, 1.3, 0, 0.25, 0.25, 0.25, "orange", "Flame")
	Parts.glow(m, f, 0.02, 1.5, 0.02, 0.25, 0.25, 0.25, "yellow", "FlameTip")
	Parts.box(m, f, -0.1, 1.38, -0.4, 0.75, 0.25, 0.25, "snow", "Snow")
	Parts.ball(m, f, -0.38, 1.36, -0.1, 0.25, "snow", "Snow")
	for i, x in { -0.22, 0.18 } do
		Parts.box(m, f, x, 0.95, 0.42, 0.25, 0.25, 0.25, if i == 1 then "white" else "ice", "Icicle")
	end
	Parts.box(m, f, 0.42, 0.95, 0.12, 0.25, 0.25, 0.25, "window", "Icicle")
	Parts.turned(m, f, -0.3, 0.12, -0.32, 0.25, 0.25, 0.25, 0.6, "ice", "Chip")
end

-- Ice Sculpture (2 x 2): a swan carved out of ice, side on to the view: its body, two layers of feathers on each lifted
-- wing, its neck in an S, head and beak, swirls of ice like water round it, a glint on a wing; on a plinth of ice with
-- panels on its faces in view, a step of packed snow, a snow cap with icicles; the carver's mallet and chisel left in
-- the snow with chips of ice.
M.icesculpture = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 2, 0.25, "snow", "Snow")
	Parts.box(m, f, 0, 0.14, 0, 1.5, 0.25, 1.5, "white", "Step")
	Parts.box(m, f, 0, 0.42, 0, 1.25, 0.5, 1.25, "ice", "Plinth")
	Parts.box(m, f, 0, 0.42, 0.56, 0.75, 0.25, 0.25, "window", "Panel")
	Parts.box(m, f, 0.56, 0.42, 0, 0.25, 0.25, 0.75, "window", "Panel")
	Parts.box(m, f, 0, 0.74, 0, 1.5, 0.25, 1.5, "snow", "Top")
	for i, p in { { -0.4, 0.68 }, { 0.3, 0.68 }, { 0.68, 0.2 }, { 0.68, -0.4 } } do
		Parts.box(m, f, p[1], 0.52, p[2], 0.25, 0.25, 0.25, if i % 2 == 0 then "window" else "ice", "Icicle")
	end
	-- the swan's own frame: its head to -X, its side to the view
	local s = f * CFrame.new(0, 0.865, 0) * TOWARD
	for i, w in { { -0.45, 0.05, 0.25, 0.5 }, { 0.5, 0.05, -0.15, 0.5 }, { 0.15, 0.02, 0.4, 0.5 } } do
		Parts.ball(m, s, w[1], w[2], w[3], w[4], if i == 2 then "white" else "window", "Swirl")
	end
	Parts.ball(m, s, 0.05, 0.32, 0, 0.75, "ice", "Body")
	Parts.ball(m, s, 0.3, 0.38, 0, 0.75, "ice", "Body")
	Parts.ball(m, s, -0.28, 0.36, 0, 0.5, "ice", "Breast")
	seg(m, s, v(0.55, 0.45, 0), v(0.78, 0.78, 0), 0.25, "ice", "Tail")
	for _, z in { -0.25, 0.25 } do
		wedgeAt(m, s, CFrame.new(0.22, 0.78, z) * CFrame.Angles(z * 1.2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.75, 1, "window", "Wing")
		wedgeAt(m, s, CFrame.new(0.36, 0.62, z * 1.3) * CFrame.Angles(z * 1.2, 0, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.25, 0.5, 0.75, "white", "Feathers")
	end
	Parts.box(m, s, 0.62, 1.05, 0.32, 0.25, 0.25, 0.25, "white", "Sparkle")
	local neck = { v(-0.38, 0.5, 0), v(-0.55, 0.85, 0), v(-0.48, 1.15, 0), v(-0.32, 1.35, 0) }
	for i = 1, #neck - 1 do
		seg(m, s, neck[i], neck[i + 1], 0.5, if i == 2 then "window" else "ice", "Neck")
	end
	Parts.ball(m, s, -0.4, 1.5, 0, 0.5, "ice", "Head")
	seg(m, s, v(-0.58, 1.5, 0), v(-0.85, 1.42, 0), 0.25, "window", "Beak")
	-- the carver's tools and chips of ice in the snow
	seg(m, f, v(0.84, 0.1, 0.05), v(0.84, 0.1, 0.45), 0.25, "wood", "Mallet")
	Parts.box(m, f, 0.84, 0.15, 0.6, 0.25, 0.25, 0.25, "wood_dark", "MalletHead")
	seg(m, f, v(-0.85, 0.07, 0.55), v(-0.62, 0.07, 0.85), 0.25, "steel_dark", "Chisel")
	Parts.turned(m, f, 0.78, 0.12, -0.3, 0.25, 0.25, 0.25, 0.5, "ice", "Chip")
	Parts.turned(m, f, -0.3, 0.12, 0.8, 0.25, 0.25, 0.25, 0.9, "window", "Chip")
	Parts.turned(m, f, -0.78, 0.1, -0.2, 0.25, 0.25, 0.25, 0.2, "white", "Chip")
	Parts.ball(m, f, 0.8, 0.08, -0.7, 0.5, "snow", "Drift")
end

-- A ring of ice round the dome where one course of snow blocks meets the next: dia d, standing proud of the dome by
-- `poke` at its top edge (the dome: radius r, centre (0, cy, cz)).
local function course(m: Model, f: CFrame, cy: number, cz: number, r: number, d: number, poke: number)
	local top = math.sqrt(r * r - (d / 2 - poke) ^ 2)
	Parts.cyl(m, f, 0, cy + top - 0.125, cz, d, 0.25, "ice", "Course")
end

-- Igloo (3 x 3): a dome of snow blocks, ice between the courses and in the joints, staggered row to row; a tunnel to a
-- dark round door framed in ice, a hide flap tied back and a fire's glow inside; a lantern swinging from a post by the
-- door; spare blocks and the snow knife that cut them; skis and a pole leaning on the dome; a fishing hole with its rod
-- and a fish on the snow; a red flag on top; drifts.
M.igloo = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 3, 0.25, "snow", "Snow")
	for i, d in { { -1.25, -0.95, 0.5 }, { 1.25, -1.15, 0.5 }, { -1.22, 0.35, 0.5 }, { 0.15, 1.3, 0.25 } } do
		Parts.ball(m, f, d[1], 0.06, d[2], d[3], if i % 2 == 0 then "white" else "snow", "Drift")
	end
	local r, cy, cz = 1.25, 0.1, -0.25
	Parts.ball(m, f, 0, cy, cz, r * 2, "snow", "Dome")
	course(m, f, cy, cz, r, 2.25, 0.06)
	course(m, f, cy, cz, r, 1.75, 0.07)
	course(m, f, cy, cz, r, 1, 0.12)
	-- the joints between blocks, on the side in view (the tunnel hides the front of the lowest course)
	for _, row in { { h = 0.35, a = { -30, 10, 150 } }, { h = 0.88, a = { -10, 35, 80, 125 } }, { h = 1.12, a = { 12, 60, 108 } } } do
		local dy = row.h - cy
		local rr = math.sqrt(r * r - dy * dy)
		for _, deg in row.a do
			local a = math.rad(deg)
			local p = v(math.cos(a) * (rr - 0.04), row.h, cz + math.sin(a) * (rr - 0.04))
			Parts.at(m, f, CFrame.lookAt(p, v(0, row.h, cz)), 0.25, 0.25, 0.25, "ice", "Joint")
		end
	end
	-- the tunnel and its door
	Parts.logZ(m, f, 0, 0.15, 0.9, 1, 1, "snow", "Tunnel")
	Parts.box(m, f, 0, 0.6, 0.8, 0.25, 0.25, 0.25, "ice", "Joint")
	Parts.logZ(m, f, 0, 0.15, 1.3, 0.25, 1.25, "ice", "Arch")
	disc(m, f, 0, 0.1, 1.33, 0.75, "night", "Door")
	Parts.glow(m, f, 0.05, 0.08, 1.38, 0.25, 0.25, 0.25, "orange", "Glow")
	Parts.box(m, f, -0.24, 0.22, 1.39, 0.25, 0.5, 0.25, "wood", "Flap")
	-- spare blocks and the knife
	Parts.box(m, f, 1.2, 0.15, 0.3, 0.5, 0.25, 0.5, "snow", "Block")
	Parts.turned(m, f, 1.18, 0.4, 0.3, 0.5, 0.25, 0.5, 0.3, "white", "Block")
	Parts.box(m, f, 1.15, 0.15, 1.15, 0.5, 0.25, 0.5, "white", "Block")
	Parts.box(m, f, 1.15, 0.4, 1.15, 0.25, 0.5, 0.25, "steel", "Knife")
	Parts.box(m, f, 1.15, 0.72, 1.15, 0.25, 0.25, 0.25, "wood_dark", "KnifeHandle")
	-- skis and a pole leaning on the dome
	for _, z in { -0.6, -0.95 } do
		seg(m, f, v(1.35, 0.05, z), v(1.05, 1.05, z), 0.25, "berry_red", "Ski")
		Parts.box(m, f, 1.24, 0.45, z, 0.25, 0.25, 0.25, "black", "Binding")
	end
	seg(m, f, v(1.35, 0.05, -0.22), v(1.15, 1.1, -0.27), 0.25, "steel_dark", "Pole")
	-- the lantern on its post by the door, swinging a little
	Parts.box(m, f, 0.75, 0.55, 0.8, 0.25, 1.1, 0.25, "wood_dark", "LampPost")
	Parts.box(m, f, 0.62, 1.05, 0.8, 0.5, 0.25, 0.25, "wood_dark", "LampArm")
	local hook = v(0.5, 0.95, 0.8)
	swing(Parts.box(m, f, hook.X, 0.86, hook.Z, 0.25, 0.25, 0.25, "gold", "LampCap"), hook, "X", 1.6, 0.2)
	swing(Parts.glow(m, f, hook.X, 0.66, hook.Z, 0.25, 0.25, 0.25, "yellow", "Lamp"), hook, "X", 1.6, 0.2)
	-- a fishing hole, its rod stuck in the snow, the catch
	Parts.cyl(m, f, -0.95, 0.05, 0.95, 0.75, 0.25, "ice", "Ice")
	pool(m, f, -0.95, 0.08, 0.95, 0.5)
	seg(m, f, v(-1.32, 0.05, 1.3), v(-1.0, 1.0, 0.98), 0.25, "wood_dark", "Rod")
	seg(m, f, v(-1.0, 0.98, 0.98), v(-0.97, 0.15, 0.96), 0.25, "white", "Line")
	Parts.ball(m, f, -0.5, 0.1, 1.25, 0.25, "blue", "Fish")
	Parts.turned(m, f, -0.32, 0.1, 1.3, 0.25, 0.25, 0.25, 0.8, "steel_dark", "Tail")
	pennant(m, f, 0.1, 2.15, -0.3, 1, "berry_red")
end

------------------------------------------------------------------ autumn
-- Leaf Pile (2 x 2): a lumpy heap of fallen leaves in red, orange, gold and brown, leaves lying on top of it and blown
-- loose round it, a rake left leaning on it with a brass collar and a dark grip, two acorns and a twig, and a hedgehog
-- peeking out at the front.
M.leafpile = function(m, f)
	local hue = { "maple", "orange", "straw", "orange", "brick", "gold", "orange", "maple" }
	for i, b in { { 0, 0.05, 0, 1.5 }, { 0.45, 0, 0.35, 1 }, { -0.45, 0, 0.3, 1 }, { -0.3, 0.15, -0.4, 0.75 }, { 0.4, 0.1, -0.35, 0.75 }, { 0.2, 0.38, 0.3, 0.75 }, { -0.28, 0.42, 0.08, 0.75 }, { 0.22, 0.52, -0.12, 0.5 } } do
		Parts.ball(m, f, b[1], b[2], b[3], b[4], hue[i], if i <= 2 then "Leaves" else "Pile")
	end
	sway(Parts.ball(m, f, 0.02, 0.7, 0.05, 0.5, "straw", "Pile"))
	-- leaves on the heap and blown loose round it
	for i, l in { { -0.2, 0.78, 0.3 }, { 0.45, 0.62, 0.55 }, { -0.55, 0.42, 0.45 }, { 0.15, 0.9, -0.2 }, { 0.62, 0.35, 0.05 }, { -0.1, 0.62, 0.62 } } do
		sway(Parts.at(m, f, CFrame.new(l[1], l[2], l[3]) * CFrame.Angles(0.5, i * 0.9, 0.3), 0.5, 0.25, 0.25, if i % 3 == 0 then "brick" elseif i % 3 == 1 then "orange" else "straw", "Leaf"))
	end
	for i, l in { { 0.75, 0.75, 0.3 }, { -0.8, 0.55, 1.2 }, { 0.2, 0.7, 2.1 }, { -0.7, -0.7, 0.7 }, { 0.85, -0.2, 1.7 }, { -0.15, -0.72, 2.6 }, { 0.5, 0.7, 0.9 } } do
		sway(Parts.turned(m, f, l[1], 0.02, l[2], 0.5, 0.25, 0.25, l[3], if i % 4 == 0 then "brick" elseif i % 4 == 1 then "maple" elseif i % 4 == 2 then "straw" else "orange", "Leaf"))
	end
	-- the rake
	seg(m, f, v(0.62, 0.08, 0.68), v(-0.05, 1.15, -0.1), 0.25, "wood", "Rake")
	Parts.turned(m, f, 0.62, 0.1, 0.68, 0.75, 0.25, 0.25, math.pi / 4, "steel_dark", "RakeHead")
	Parts.box(m, f, 0.55, 0.2, 0.6, 0.25, 0.25, 0.25, "gold", "Collar")
	seg(m, f, v(0.08, 0.95, 0.05), v(-0.05, 1.15, -0.1), 0.25, "wood_dark", "Grip")
	-- acorns, a twig, a hedgehog
	for _, a in { { -0.78, 0.62 }, { 0.82, -0.62 } } do
		Parts.ball(m, f, a[1], 0.08, a[2], 0.25, "wood", "Acorn")
		Parts.box(m, f, a[1] - 0.02, 0.22, a[2] - 0.02, 0.25, 0.25, 0.25, "wood_dark", "Cup")
	end
	seg(m, f, v(-0.85, 0.05, -0.2), v(-0.6, 0.05, -0.7), 0.25, "wood_dark", "Twig")
	Parts.ball(m, f, -0.45, 0.18, 0.62, 0.5, "hair_brown", "Hedgehog")
	Parts.ball(m, f, -0.3, 0.14, 0.8, 0.25, "skin2", "Snout")
	Parts.ball(m, f, -0.24, 0.14, 0.9, 0.25, "black", "Nose")
end

-- Harvest Basket (1 x 1): a woven basket in bands of dark wood, straw and wood on a dark foot, its handle arched over
-- with a ribbon tied at the top; red apples, a yellow one, a green squash with its stem, a bunch of grapes and a corn
-- cob in its husk heaped in it; one apple rolled out, fallen leaves.
M.basket = function(m, f)
	Parts.cyl(m, f, 0, 0.08, 0, 0.5, 0.25, "wood_dark", "Foot")
	Parts.cyl(m, f, 0, 0.2, 0, 0.75, 0.25, "wood_dark", "Basket")
	Parts.cyl(m, f, 0, 0.4, 0, 1, 0.25, "straw", "Basket")
	Parts.cyl(m, f, 0, 0.65, 0, 1, 0.25, "wood", "Rim")
	-- what is in it
	Parts.ball(m, f, -0.05, 0.88, -0.12, 0.5, "green", "Squash")
	Parts.box(m, f, -0.05, 1.12, -0.12, 0.25, 0.25, 0.25, "wood_dark", "Stem")
	for i, a in { { -0.25, 0.2 }, { 0.12, 0.28 }, { 0.3, -0.05 }, { -0.3, -0.15 }, { 0.05, 0.05 } } do
		Parts.ball(m, f, a[1], if i == 5 then 0.95 else 0.85, a[2], 0.25, if i == 5 then "yellow" else "berry_red", "Apple")
	end
	Parts.ball(m, f, 0.22, 0.88, -0.28, 0.25, "purple", "Grapes")
	Parts.ball(m, f, 0.28, 0.8, -0.2, 0.25, "crystal", "Grapes")
	Parts.at(m, f, CFrame.new(0.18, 0.95, 0.05) * TOWARD * CFrame.Angles(0, 0, -0.7), 0.25, 0.75, 0.25, "yellow", "Corn")
	Parts.at(m, f, CFrame.new(0.05, 0.8, 0.05) * TOWARD * CFrame.Angles(0, 0, -0.7), 0.25, 0.25, 0.25, "leaf", "Husk")
	-- the handle, arched across the view, a ribbon at the top
	local h = { { -0.42, 0.75 }, { -0.36, 1.12 }, { 0, 1.34 }, { 0.36, 1.12 }, { 0.42, 0.75 } }
	for i = 1, #h - 1 do
		local a, b = h[i], h[i + 1]
		seg(m, f, ACROSS * a[1] + v(0, a[2], 0), ACROSS * b[1] + v(0, b[2], 0), 0.25, "wood", "Handle")
	end
	Parts.at(m, f, CFrame.new(0.02, 1.34, 0.02) * TOWARD, 0.5, 0.25, 0.25, "maple", "Ribbon")
	-- an apple rolled out, leaves on the grass
	Parts.ball(m, f, 0.32, 0.12, 0.36, 0.25, "berry_red", "Apple")
	sway(Parts.turned(m, f, -0.2, 0.02, 0.22, 0.5, 0.25, 0.25, 0.8, "orange", "Leaf"))
	sway(Parts.turned(m, f, 0.3, 0.02, -0.22, 0.25, 0.25, 0.5, 0.3, "maple", "Leaf"))
end

-- Pumpkin Stack (1 x 1): an orange pumpkin, a red one on it, a pale gold one on top, each with its lobes; a stem with a
-- green vine curling down its side and two leaves, straw under them with tufts, a striped gourd at their feet.
M.pumpkinstack = function(m, f)
	Parts.turned(m, f, 0, 0, 0, 0.75, 0.25, 0.75, 0.4, "straw", "Straw")
	Parts.turned(m, f, -0.35, 0.08, 0.25, 0.25, 0.25, 0.25, 0.6, "gold", "Tuft")
	Parts.turned(m, f, 0.25, 0.08, -0.35, 0.25, 0.25, 0.25, 0.2, "gold", "Tuft")
	pumpkin(m, f, 0, 0, 0, 0.75, "orange", 0.1)
	pumpkin(m, f, 0.02, 0.62, 0.02, 0.5, "maple", 0.1)
	pumpkin(m, f, 0, 1.05, 0, 0.5, "straw", 0.06)
	Parts.at(m, f, CFrame.new(0.02, 1.58, 0) * CFrame.Angles(0, 0, -0.3), 0.25, 0.25, 0.25, "wood_dark", "Stem")
	-- the vine and its leaves
	local a, b, c = ACROSS * 0.12 + v(0, 1.55, 0), ACROSS * 0.36 + v(0, 1.3, 0), ACROSS * 0.42 + v(0, 0.95, 0)
	seg(m, f, a, b, 0.25, "moss", "Vine")
	seg(m, f, b, c, 0.25, "moss", "Vine")
	sway(Parts.at(m, f, CFrame.new(-0.15, 1.52, -0.1) * CFrame.Angles(0.3, 0.5, 0.5), 0.25, 0.25, 0.5, "moss", "Leaf"))
	sway(Parts.at(m, f, CFrame.new(c + ACROSS * 0.02 + v(0, -0.15, 0)) * TOWARD, 0.25, 0.25, 0.25, "leaf_dark", "Leaf"))
	-- a striped gourd at their feet
	Parts.ball(m, f, 0.36, 0.12, 0.36, 0.25, "cream", "Gourd")
	Parts.ball(m, f, 0.38, 0.22, 0.4, 0.25, "green", "Gourd")
end

-- A shock of corn stalks standing at (cx, cz): four stalks lean in to a twine tie with a red bow, five flare out above
-- it, two dry leaves droop, an ear of corn in its husk is tucked into the tie.
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
	Parts.at(m, f, CFrame.new(cx + 0.18, tie, cz + 0.18) * TOWARD, 0.5, 0.25, 0.25, "maple", "Bow")
	for _, s in { -1, 1 } do
		sway(seg(m, f, v(cx, tie + 0.3, cz) + ACROSS * (s * 0.1), v(cx, tie - 0.05, cz) + ACROSS * (s * 0.45), 0.25, "sand", "Leaf"))
	end
	local ear = v(cx, tie - 0.2, cz) + ACROSS * 0.2 + v(0.12, 0, 0.12)
	seg(m, f, ear, ear + v(0.06, -0.45, 0.06), 0.25, "yellow", "Corn")
	sway(seg(m, f, ear + v(-0.05, 0.05, 0.08), ear + v(-0.12, -0.3, 0.18), 0.25, "leaf", "Husk"))
end

-- Corn Stalks (2 x 1): two shocks of dry stalks tied with twine and red bows, an ear of corn tucked in each, a small
-- pumpkin with its stem and a cob in its husk at their feet, a crow's feather and fallen husks.
M.cornstalks = function(m, f)
	shock(m, f, -0.5, -0.05, 1.75, 0)
	shock(m, f, 0.5, 0, 1.5, 0.3)
	pumpkin(m, f, 0.05, 0, 0.17, 0.5, "orange", 0.08)
	Parts.box(m, f, 0.05, 0.6, 0.17, 0.25, 0.25, 0.25, "wood_dark", "Stem")
	Parts.turned(m, f, -0.5, 0.1, 0.3, 0.5, 0.25, 0.25, 0.3, "yellow", "Corn")
	Parts.turned(m, f, -0.25, 0.1, 0.32, 0.25, 0.25, 0.25, 0.3, "leaf", "Husk")
	Parts.turned(m, f, 0.75, 0.04, 0.25, 0.5, 0.25, 0.25, -0.5, "sand", "Husk")
	Parts.turned(m, f, -0.8, 0.04, 0.15, 0.25, 0.25, 0.5, 0.2, "black", "Feather")
end

-- Carved Pumpkin (1 x 1): a big pumpkin on a straw bale tied with twine, tufts of straw sticking out, turned to look at
-- the view: its eyes, nose and grin lit from inside, two teeth left in the grin, the lid cut round its stem with the
-- light showing through the cut, a curling vine and two leaves.
M.jackolantern = function(m, f)
	Parts.box(m, f, 0, 0.25, 0, 1, 0.5, 0.75, "straw", "Bale")
	for _, x in { -0.3, 0.3 } do
		Parts.box(m, f, x, 0.4, 0.01, 0.25, 0.25, 0.75, "sand_dark", "Twine")
	end
	for _, t in { { -0.42, 0.45, 0.3 }, { 0.42, 0.2, 0.3 }, { 0.38, 0.45, -0.3 } } do
		Parts.box(m, f, t[1], t[2], t[3], 0.25, 0.25, 0.25, "gold", "Tuft")
	end
	local p = f * CFrame.new(0, 0.5, 0) * TOWARD
	pumpkin(m, p, 0, 0, 0, 0.75, "orange", 0.1)
	local cy = 0.345
	for _, x in { -0.2, 0.2 } do
		Parts.glow(m, p, x, cy + 0.18, 0.31, 0.25, 0.25, 0.25, "yellow", "Eye")
	end
	Parts.glow(m, p, 0, cy + 0.02, 0.36, 0.25, 0.25, 0.25, "orange", "Nose")
	Parts.glow(m, p, 0, cy - 0.17, 0.31, 0.5, 0.25, 0.25, "yellow", "Grin")
	Parts.box(m, p, -0.1, cy - 0.1, 0.36, 0.25, 0.25, 0.25, "orange", "Tooth")
	Parts.box(m, p, 0.12, cy - 0.24, 0.36, 0.25, 0.25, 0.25, "orange", "Tooth")
	-- the lid, the light through its cut
	Parts.cyl(m, p, 0, cy + 0.33, 0, 0.5, 0.25, "brick", "Lid")
	Parts.glow(m, p, 0.18, cy + 0.33, 0.12, 0.25, 0.25, 0.25, "yellow", "Flame")
	Parts.at(m, p, CFrame.new(0, cy + 0.48, 0) * CFrame.Angles(0, 0, 0.25), 0.25, 0.25, 0.25, "wood_dark", "Stem")
	seg(m, p, v(0.02, cy + 0.55, 0), v(-0.22, cy + 0.6, 0.12), 0.25, "moss", "Vine")
	seg(m, p, v(-0.22, cy + 0.6, 0.12), v(-0.35, cy + 0.42, 0.2), 0.25, "moss", "Vine")
	sway(Parts.at(m, p, CFrame.new(0.18, cy + 0.42, -0.12) * CFrame.Angles(0.2, 0.4, -0.35), 0.5, 0.25, 0.25, "moss", "Leaf"))
	sway(Parts.at(m, p, CFrame.new(-0.12, cy + 0.45, -0.22) * CFrame.Angles(-0.3, 0.2, 0.3), 0.25, 0.25, 0.5, "leaf_dark", "Leaf"))
end

------------------------------------------------------------------ the desert
-- A tall clay jar standing at (x, z): a dark foot, a long round belly with a painted band and two painted dots on its
-- shoulder, a narrow neck with a loop handle each side, a lip (its top at 1.475).
local function jar(m: Model, f: CFrame, x: number, z: number, band: string)
	Parts.cyl(m, f, x, 0.125, z, 0.5, 0.25, "brick", "Foot")
	Parts.ball(m, f, x, 0.5, z, 0.75, "clay", "Jar")
	Parts.ball(m, f, x, 0.78, z, 0.75, "clay", "Jar")
	Parts.cyl(m, f, x, 0.62, z, 0.75, 0.25, band, "Band")
	for _, s in { -0.5, 0.5 } do
		dot(m, f, v(x, 0.78, z), 0.375, TOWARD * v(s, 0.45, 0.8), 0.06, if band == "cream" then "teal" else "cream", "Paint")
		local h = v(x, 1.05, z) + ACROSS * (s * 0.56)
		Parts.box(m, f, h.X, h.Y, h.Z, 0.25, 0.25, 0.25, "brick", "Handle")
	end
	Parts.cyl(m, f, x, 1.2, z, 0.25, 0.25, "clay", "Neck")
	Parts.cyl(m, f, x, 1.35, z, 0.5, 0.25, "brick", "Lip")
end

-- Water Jars (1 x 1): a tall clay jar with a cream band and teal dots, water in its mouth and a ladle hung on its lip,
-- a small round one with a teal band and a cork beside it, a cup, on a patch of sand with pebbles and a little lizard
-- sunning itself.
M.waterjars = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "sand", "Sand")
	Parts.ball(m, f, 0.38, 0.06, 0.2, 0.25, "sand_dark", "Pebble")
	Parts.ball(m, f, -0.4, 0.06, 0.12, 0.25, "rock", "Pebble")
	jar(m, f, -0.1, -0.12, "cream")
	pool(m, f, -0.1, 1.37, -0.12, 0.25)
	seg(m, f, v(0.05, 1.42, -0.02), v(0.22, 0.98, 0.18), 0.25, "wood_dark", "Ladle")
	Parts.ball(m, f, 0.24, 0.9, 0.2, 0.25, "wood", "Ladle")
	Parts.ball(m, f, 0.25, 0.25, -0.18, 0.5, "clay", "Jar")
	Parts.cyl(m, f, 0.25, 0.25, -0.18, 0.5, 0.25, "teal", "Band")
	Parts.cyl(m, f, 0.25, 0.55, -0.18, 0.25, 0.25, "brick", "Lip")
	Parts.box(m, f, 0.25, 0.7, -0.18, 0.25, 0.25, 0.25, "wood", "Cork")
	Parts.cyl(m, f, -0.2, 0.15, 0.32, 0.25, 0.25, "clay", "Cup")
	-- the lizard
	Parts.at(m, f, CFrame.new(0.05, 0.08, 0.22) * TOWARD, 0.5, 0.25, 0.25, "green", "Lizard")
	seg(m, f, v(-0.1, 0.05, 0.12), v(-0.3, 0.05, 0.08), 0.25, "moss", "Tail")
end

-- Clay Pots (2 x 1): a row of painted pots on the sand: a round one with a cream band, teal dots and a knob of a lid, a
-- low bowl with a cactus in flower, a tall jar banded in teal with its handles, a small one at their feet, a stack of
-- dishes, a little pot lying on its side, pebbles.
M.claypots = function(m, f)
	Parts.cyl(m, f, -0.5, 0, 0, 1, 0.25, "sand", "Sand")
	Parts.cyl(m, f, 0.5, 0, 0, 1, 0.25, "sand", "Sand")
	-- round pot
	local rp = v(-0.6, 0.35, -0.05)
	Parts.ball(m, f, rp.X, rp.Y, rp.Z, 0.75, "clay", "Pot")
	Parts.cyl(m, f, rp.X, rp.Y, rp.Z, 0.75, 0.25, "cream", "Band")
	for _, s in { -0.55, 0.55 } do
		dot(m, f, rp, 0.375, TOWARD * v(s, 0.5, 0.7), 0.06, "teal", "Paint")
	end
	Parts.cyl(m, f, rp.X, 0.75, rp.Z, 0.5, 0.25, "brick", "Neck")
	Parts.ball(m, f, rp.X, 0.88, rp.Z, 0.25, "clay", "Lid")
	-- the bowl and its cactus
	Parts.cyl(m, f, 0.05, 0.125, -0.12, 0.75, 0.25, "brick", "Bowl")
	Parts.cyl(m, f, 0.05, 0.375, -0.12, 0.75, 0.25, "clay", "Bowl")
	Parts.cyl(m, f, 0.05, 0.5, -0.12, 0.5, 0.25, "sand_dark", "Soil")
	Parts.cyl(m, f, 0.05, 0.8, -0.12, 0.25, 0.75, "green", "Cactus")
	Parts.box(m, f, 0.2, 0.85, -0.12, 0.25, 0.25, 0.25, "green", "Cactus")
	Parts.box(m, f, 0.28, 1.0, -0.12, 0.25, 0.25, 0.25, "leaf_dark", "Cactus")
	Parts.box(m, f, -0.1, 0.75, -0.1, 0.25, 0.25, 0.25, "leaf_dark", "Cactus")
	Parts.box(m, f, -0.15, 0.9, -0.1, 0.25, 0.25, 0.25, "green", "Cactus")
	Parts.box(m, f, 0.05, 1.2, -0.12, 0.25, 0.25, 0.25, "pink", "Bloom")
	-- the tall jar
	jar(m, f, 0.62, -0.12, "teal")
	-- in front: a small pot, a stack of dishes, one lying on its side, pebbles
	Parts.ball(m, f, 0.35, 0.22, 0.25, 0.5, "clay", "Pot")
	Parts.cyl(m, f, 0.35, 0.22, 0.25, 0.5, 0.25, "cream", "Band")
	Parts.cyl(m, f, 0.35, 0.45, 0.25, 0.25, 0.25, "brick", "Lip")
	Parts.cyl(m, f, -0.15, 0.06, 0.25, 0.5, 0.25, "brick", "Dish")
	Parts.cyl(m, f, -0.15, 0.16, 0.25, 0.25, 0.25, "cream", "Dish")
	Parts.ball(m, f, -0.65, 0.15, 0.25, 0.5, "clay", "Pot")
	Parts.log(m, f, -0.42, 0.15, 0.25, 0.25, 0.25, "brick", "Lip")
	Parts.ball(m, f, 0.85, 0.06, 0.3, 0.25, "sand_dark", "Pebble")
	Parts.ball(m, f, 0.1, 0.06, 0.36, 0.25, "rock", "Pebble")
end

-- Market Rug (2 x 2): a woven rug: a gold border set with little teal and cream squares and red corners, a red field
-- with cream corners round a gold diamond and its teal heart, cream tassels along the ends; two cushions with gold
-- buttons at the back, a brass tray at the side with a teapot steaming and a glass.
M.rug = function(m, f)
	for _, x in { -0.85, 0.85 } do
		for _, z in { -0.45, -0.15, 0.15, 0.45 } do
			Parts.box(m, f, x, 0, z, 0.25, 0.25, 0.25, "cream", "Tassel")
		end
	end
	Parts.box(m, f, 0, 0.01, 0, 1.5, 0.25, 1.5, "gold", "Rug")
	Parts.box(m, f, 0, 0.02, 0, 1, 0.25, 1, "berry_red", "Field")
	for i, p in { { -0.625, -0.3 }, { -0.625, 0.3 }, { 0.625, -0.3 }, { 0.625, 0.3 }, { -0.3, -0.625 }, { 0.3, -0.625 }, { -0.3, 0.625 }, { 0.3, 0.625 } } do
		Parts.box(m, f, p[1], 0.03, p[2], 0.25, 0.25, 0.25, if i % 2 == 0 then "cream" else "teal", "Motif")
	end
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.625, 0.03, c[2] * 0.625, 0.25, 0.25, 0.25, "berry_red", "Corner")
		Parts.box(m, f, c[1] * 0.375, 0.03, c[2] * 0.375, 0.25, 0.25, 0.25, "cream", "Corner")
	end
	Parts.turned(m, f, 0, 0.03, 0, 0.5, 0.25, 0.5, math.pi / 4, "gold", "Diamond")
	Parts.turned(m, f, 0, 0.04, 0, 0.25, 0.25, 0.25, math.pi / 4, "teal", "Heart")
	-- cushions, a pouf
	Parts.turned(m, f, -0.5, 0.25, -0.55, 0.5, 0.25, 0.5, 0.2, "teal", "Cushion")
	Parts.box(m, f, -0.5, 0.32, -0.55, 0.25, 0.25, 0.25, "gold", "Button")
	Parts.turned(m, f, 0.1, 0.25, -0.6, 0.5, 0.25, 0.5, -0.15, "purple", "Cushion")
	Parts.box(m, f, 0.1, 0.32, -0.6, 0.25, 0.25, 0.25, "gold", "Button")
	-- the tea tray at the side
	Parts.cyl(m, f, 0.62, 0.06, -0.15, 0.75, 0.25, "gold", "Tray")
	Parts.ball(m, f, 0.6, 0.3, -0.25, 0.5, "teal", "Teapot")
	Parts.box(m, f, 0.6, 0.55, -0.25, 0.25, 0.25, 0.25, "gold", "Lid")
	seg(m, f, v(0.62, 0.32, -0.05), v(0.64, 0.48, 0.12), 0.25, "teal", "Spout")
	Parts.cyl(m, f, 0.72, 0.2, 0.08, 0.25, 0.25, "shallow", "Glass")
end

-- Striped Tent (3 x 3): a roof of clay and cream stripes on poles, gold finials at the ridge's ends, the back and the
-- gables closed, the sides rolled up, the front flaps tied open, a gold trim with flaps along
-- the eave, a rug with a gold diamond inside, a bolster and cushions, a tray table with a teapot and two cups, a
-- lantern swinging at the door, pennants on the ridge.
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
		Parts.ball(m, f, x, ridge + 0.22, 0, 0.25, "gold", "Finial")
		for _, z in { -1.125, 1.125 } do
			Parts.box(m, f, x, eave / 2, z, 0.25, eave, 0.25, "wood_dark", "Pole")
		end
		Parts.logZ(m, f, x * 0.91, eave - 0.2, 0, 2, 0.5, "clay", "Roll")
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
	Parts.turned(m, f, -0.6, 0.02, 0.45, 0.5, 0.25, 0.5, math.pi / 4, "gold", "Diamond")
	Parts.turned(m, f, -0.6, 0.03, 0.45, 0.25, 0.25, 0.25, math.pi / 4, "teal", "Diamond")
	Parts.log(m, f, 0, 0.3, -0.75, 1.5, 0.5, "orange", "Bolster")
	Parts.box(m, f, -0.75, 0.25, -0.2, 0.5, 0.25, 0.5, "teal", "Cushion")
	Parts.box(m, f, 0.8, 0.25, -0.3, 0.5, 0.25, 0.5, "teal", "Cushion")
	Parts.cyl(m, f, 0.1, 0.2, 0.15, 0.25, 0.25, "wood_dark", "Stand")
	Parts.cyl(m, f, 0.1, 0.38, 0.15, 0.75, 0.25, "gold", "Tray")
	Parts.ball(m, f, 0.1, 0.58, 0.15, 0.25, "teal", "Teapot")
	Parts.cyl(m, f, 0.35, 0.5, 0.3, 0.25, 0.25, "cream", "Cup")
	Parts.cyl(m, f, -0.15, 0.5, 0.32, 0.25, 0.25, "cream", "Cup")
	-- the lantern at the door, swinging on its chain
	local hook = v(0, eave - 0.32, 1.2)
	swing(Parts.box(m, f, 0, eave - 0.45, 1.2, 0.25, 0.25, 0.25, "wood_dark", "Chain"), hook, "X", 1.5, 0.22)
	swing(Parts.box(m, f, 0, eave - 0.7, 1.2, 0.25, 0.25, 0.25, "gold", "Lantern"), hook, "X", 1.5, 0.22)
	swing(Parts.box(m, f, 0, eave - 1.15, 1.2, 0.25, 0.25, 0.25, "gold", "Lantern"), hook, "X", 1.5, 0.22)
	swing(Parts.glow(m, f, 0, eave - 0.93, 1.2, 0.25, 0.25, 0.25, "yellow", "Lamp"), hook, "X", 1.5, 0.22)
	pennant(m, f, 0, ridge + 0.75, 0, 0.75, "teal")
	pennant(m, f, -1.2, ridge + 0.6, 0, 0.5, "berry_red")
end

-- Sandstone Arch (3 x 1): two carved pillars on plinths, a teal tile set in each pillar's groove, a round arch of
-- darker stones with a clay keystone, carved panels over its shoulders, a lintel with a teal band of tiles, clay
-- diamonds and gold studs, battlements on top, sand drifted at its feet and in the way through with a few stones, a
-- lantern swinging in the arch.
M.sandarch = function(m, f)
	local spring, r = 2, 0.85
	for _, s in { -1, 1 } do
		local x = s * 1.0
		Parts.box(m, f, x, 0.25, 0, 1, 0.5, 1, "sand_dark", "Plinth")
		Parts.box(m, f, x, 1.125, 0, 0.75, 1.25, 0.75, "sand", "Pillar")
		Parts.box(m, f, x, 1.1, 0.3, 0.25, 0.75, 0.25, "sand_dark", "Groove")
		Parts.box(m, f, x, 1.2, 0.33, 0.25, 0.25, 0.25, "teal", "Tile")
		Parts.box(m, f, x, 0.62, 0.3, 0.75, 0.25, 0.25, "sand_dark", "Band")
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
	for _, x in { -1.3, 1.3 } do
		Parts.box(m, f, x, 3.35, 0.32, 0.25, 0.25, 0.25, "gold", "Stud")
	end
	Parts.box(m, f, 0, 3.7, 0, 3, 0.25, 1, "sand_dark", "Cornice")
	for _, x in { -1.25, -0.4, 0.4, 1.25 } do
		Parts.box(m, f, x, 4.05, 0, 0.5, 0.5, 0.75, "sand", "Merlon")
	end
	-- a lantern swinging in the arch
	local hook = v(0, 2.62, 0)
	swing(Parts.box(m, f, 0, 2.5, 0, 0.25, 0.25, 0.25, "wood_dark", "Chain"), hook, "Z", 1.3, 0.2)
	swing(Parts.box(m, f, 0, 2.27, 0, 0.25, 0.25, 0.25, "gold", "Lantern"), hook, "Z", 1.3, 0.2)
	swing(Parts.box(m, f, 0, 1.83, 0, 0.25, 0.25, 0.25, "gold", "Lantern"), hook, "Z", 1.3, 0.2)
	swing(Parts.glow(m, f, 0, 2.05, 0, 0.25, 0.25, 0.25, "yellow", "Lamp"), hook, "Z", 1.3, 0.2)
	-- stones and sand in the way through
	Parts.ball(m, f, 0.42, 0.06, 0.3, 0.25, "sand_dark", "Stone")
	Parts.ball(m, f, -0.3, 0.04, 0.24, 0.5, "sand", "Drift")
	Parts.ball(m, f, -0.35, 0.06, -0.3, 0.25, "rock", "Stone")
end

------------------------------------------------------------------ the fairy glade
-- A toadstool at (x, z): a cream stalk, a flat cap of colour `cap` (Neon when `lit`) over a sandy gill; a big one has a
-- dome and three white spots on it, a middle one a dome and one spot.
local function toadstool(m: Model, f: CFrame, x: number, z: number, size: number, cap: string, lit: boolean)
	if size >= 3 then
		Parts.cyl(m, f, x, 0.375, z, 0.5, 0.75, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.68, z, 0.75, 0.25, "sand", "Gill")
		Parts.cyl(m, f, x, 0.8, z, 1, 0.25, cap, "Cap", lit)
		Parts.ball(m, f, x, 0.925, z, 0.75, cap, "Cap")
		for _, d in { v(0.6, 0.6, 0.5), v(-0.5, 0.7, 0.4), v(0.1, 1, -0.2) } do
			dot(m, f, v(x, 0.925, z), 0.375, d, 0.1, "white", "Spot")
		end
	elseif size == 2 then
		Parts.cyl(m, f, x, 0.3, z, 0.25, 0.6, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.52, z, 0.5, 0.25, "sand", "Gill")
		Parts.cyl(m, f, x, 0.62, z, 0.75, 0.25, cap, "Cap", lit)
		Parts.ball(m, f, x, 0.745, z, 0.5, cap, "Cap")
		dot(m, f, v(x, 0.745, z), 0.25, v(0.5, 0.8, 0.5), 0.08, "white", "Spot")
	else
		Parts.cyl(m, f, x, 0.2, z, 0.25, 0.4, "cream", "Stalk")
		Parts.cyl(m, f, x, 0.42, z, 0.5, 0.25, cap, "Cap", lit)
	end
end

-- Fairy Lantern (1 x 1): a jar of tiny lights in many colours under a gold lid, swinging gently on its cord from a
-- crook with a pink ribbon and ivy on it, over a mossy patch; a few lights loose round it, flowers, a little pink
-- toadstool, a pebble.
M.fairylantern = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1, 0.25, "moss", "Moss")
	local post = ACROSS * -0.3
	Parts.box(m, f, post.X, 0.85, post.Z, 0.25, 1.7, 0.25, "wood_dark", "Crook")
	seg(m, f, post + v(0, 1.62, 0), ACROSS * 0.02 + v(0, 1.82, 0), 0.25, "wood_dark", "Crook")
	seg(m, f, ACROSS * 0.02 + v(0, 1.82, 0), ACROSS * 0.24 + v(0, 1.66, 0), 0.25, "wood_dark", "Crook")
	Parts.box(m, f, post.X + 0.04, 1.3, post.Z + 0.04, 0.25, 0.25, 0.25, "pink", "Ribbon")
	sway(Parts.box(m, f, post.X + 0.05, 0.55, post.Z + 0.06, 0.25, 0.25, 0.25, "leaf", "Ivy"))
	sway(Parts.box(m, f, post.X - 0.04, 0.95, post.Z + 0.06, 0.25, 0.25, 0.25, "leaf_dark", "Ivy"))
	-- the jar on its cord, swinging from the crook's tip
	local hook = ACROSS * 0.24 + v(0, 1.62, 0)
	local jar = ACROSS * 0.24 + v(0, 0.92, 0)
	local function hang(p: BasePart)
		swing(p, hook, "X", 1.4, 0.18)
	end
	hang(Parts.box(m, f, jar.X, 1.47, jar.Z, 0.25, 0.25, 0.25, "straw", "Cord"))
	hang(Parts.box(m, f, jar.X, 1.42, jar.Z, 0.25, 0.25, 0.25, "gold", "Knob"))
	hang(Parts.cyl(m, f, jar.X, 1.3, jar.Z, 0.5, 0.25, "gold", "Lid"))
	hang(Parts.cyl(m, f, jar.X, jar.Y, jar.Z, 0.5, 0.5, "cream", "Jar", true))
	hang(Parts.cyl(m, f, jar.X, 0.55, jar.Z, 0.5, 0.25, "window", "Glass"))
	for i, d in { v(0.2, 0.15, 1), v(1, -0.35, 0.3), v(-0.6, -0.2, 0.8), v(0.7, 0.4, 0.6) } do
		local c = if i == 1 then "pink" elseif i == 2 then "crystal" elseif i == 3 then "teal" else "pink"
		hang(dot(m, f, jar, 0.25, TOWARD * d, 0.07, c, if i == 1 then "Sparkle" else "Firefly", true))
	end
	Parts.glow(m, f, 0.38, 1.55, 0.25, 0.25, 0.25, 0.25, "pink", "Firefly")
	Parts.glow(m, f, -0.05, 0.6, 0.4, 0.25, 0.25, 0.25, "yellow", "Firefly")
	Parts.glow(m, f, 0.42, 0.45, -0.05, 0.25, 0.25, 0.25, "crystal", "Firefly")
	-- flowers, a toadstool, a pebble on the moss
	for i, b in { { -0.34, 0.3 }, { 0.05, 0.36 } } do
		Parts.box(m, f, b[1], 0.1, b[2], 0.25, 0.25, 0.25, "leaf", "Leaf")
		Parts.box(m, f, b[1], 0.25, b[2], 0.25, 0.25, 0.25, if i == 1 then "cream" else "pink", "Bloom")
	end
	toadstool(m, f, 0.28, 0.28, 1, "pink", false)
	Parts.ball(m, f, -0.3, 0.06, -0.35, 0.25, "steel", "Pebble")
end

-- Mushroom Ring (3 x 3): toadstools in a ring of moss, two big spotted ones (one with a little round door, a lit window
-- and stepping stones up to it), middle ones with a spot, small ones glowing softly; lights bobbing over the grass
-- inside, one of them twinkling; flowers and tufts of grass in the ring.
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
	-- the little door in the big one at the front, its window and the stepping stones to it
	local da = math.rad(45)
	local dx, dz = math.cos(da) * 1.0, math.sin(da) * 1.0
	Parts.box(m, f, dx + 0.05, 0.25, dz + 0.19, 0.25, 0.5, 0.25, "wood_dark", "Door")
	Parts.box(m, f, dx + 0.12, 0.25, dz + 0.24, 0.25, 0.25, 0.25, "gold", "Knob")
	Parts.glow(m, f, dx + 0.22, 0.45, dz - 0.05, 0.25, 0.25, 0.25, "yellow", "Window")
	for k, s in { { 0.38, 0.32 }, { 0.12, 0.05 }, { -0.18, -0.12 } } do
		Parts.cyl(m, f, s[1], 0.04, s[2], if k == 1 then 0.5 else 0.25, 0.25, "pavement", "Stone")
	end
	-- lights bobbing over the grass inside
	for i, l in { { x = 0.2, y = 0.7, z = -0.1, c = "cream" }, { x = -0.35, y = 1.0, z = 0.2, c = "pink" }, { x = 0.1, y = 1.3, z = 0.35, c = "crystal" }, { x = -0.1, y = 0.5, z = -0.45, c = "yellow" } } do
		local p = Parts.glow(m, f, l.x, l.y, l.z, 0.25, 0.25, 0.25, l.c, if i == 3 then "Sparkle" else "Wisp")
		Parts.move(p, "bob", v(l.x, l.y, l.z), "Y", 1.2 + i * 0.15, 0.1, i * 1.6)
	end
	-- flowers and tufts in the ring
	for i, b in { { -1.3, 0.35 }, { 0.35, -1.3 }, { -0.75, 1.1 }, { 1.2, -0.65 } } do
		Parts.box(m, f, b[1], 0.15, b[2], 0.25, 0.25, 0.25, if i % 2 == 0 then "cream" else "pink", "Bloom")
	end
	for _, t in { { -0.45, 0.55 }, { 0.55, -0.4 }, { -0.6, -0.35 } } do
		Parts.box(m, f, t[1], 0.1, t[2], 0.25, 0.25, 0.25, "grass_dark", "Tuft")
	end
end

-- Moonstone (2 x 2): a pale standing stone on a mossy mound, lit along its left edge and shadowed down its right, a
-- crescent moon set in its face glowing with a star by it that twinkles, two runes under the moon and two down its side
-- that glow; moss creeping up it, a ring of pale stones (two of them glowing), white moonflowers.
M.moonstone = function(m, f)
	Parts.cyl(m, f, 0, 0.02, 0, 1.75, 0.25, "moss", "Moss")
	Parts.cyl(m, f, -0.05, 0.08, -0.05, 1.25, 0.25, "swamp", "Mound")
	Parts.box(m, f, 0.45, 0.2, 0.3, 0.5, 0.25, 0.25, "rock", "Footing")
	Parts.box(m, f, -0.5, 0.2, 0.25, 0.25, 0.25, 0.5, "rock_dark", "Footing")
	Parts.box(m, f, 0, 0.75, -0.05, 1, 1.25, 0.75, "steel", "Stone")
	Parts.turned(m, f, -0.05, 1.6, -0.05, 0.75, 0.75, 0.75, -0.1, "steel", "Stone")
	Parts.ball(m, f, -0.05, 2.0, -0.05, 0.75, "steel", "Stone")
	Parts.box(m, f, -0.45, 1.0, 0.27, 0.25, 1.25, 0.25, "white", "Edge")
	Parts.box(m, f, 0.45, 0.85, -0.05, 0.25, 1, 0.5, "steel_dark", "Shade")
	-- the crescent: a glowing disc half hidden by a disc of stone; a star by it
	disc(m, f, -0.02, 0.95, 0.24, 0.75, "white", "Moon", true)
	disc(m, f, 0.16, 1.05, 0.255, 0.75, "steel", "Stone")
	Parts.glow(m, f, 0.25, 1.4, 0.3, 0.25, 0.25, 0.25, "ice", "Sparkle")
	for _, x in { -0.25, 0.25 } do
		Parts.glow(m, f, x, 0.42, 0.24, 0.25, 0.25, 0.25, "crystal", "Rune")
	end
	for _, y in { 0.6, 1.15 } do
		Parts.glow(m, f, 0.53, y, 0.15, 0.25, 0.25, 0.25, "crystal", "Rune")
	end
	-- moss creeping up it
	Parts.box(m, f, -0.3, 0.3, 0.3, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, -0.42, 0.55, 0.32, 0.25, 0.25, 0.25, "leaf_dark", "Moss")
	Parts.box(m, f, 0.2, 1.95, 0.15, 0.25, 0.25, 0.25, "moss", "Moss")
	-- pale stones round it, two of them glowing
	for i, s in { { 0.75, 0.45 }, { -0.7, 0.55 }, { 0.65, -0.6 }, { -0.75, -0.45 }, { 0.05, 0.8 }, { 0.82, -0.05 } } do
		local lit = i == 2 or i == 3
		local b = Parts.ball(m, f, s[1], 0.1, s[2], if i >= 5 then 0.25 else 0.5, if lit then "ice" else "steel", "Pebble")
		if lit then
			b.Material = Enum.Material.Neon
		end
	end
	-- moonflowers
	for _, b in { { -0.35, 0.72 }, { 0.42, 0.68 }, { -0.82, 0.05 } } do
		Parts.box(m, f, b[1], 0.12, b[2], 0.25, 0.25, 0.25, "leaf", "Leaf")
		Parts.box(m, f, b[1] + 0.03, 0.28, b[2] + 0.03, 0.25, 0.25, 0.25, "white", "Bloom")
	end
end

-- Wishing Well (2 x 2): a round well of grey stone with darker stones set in it and moss on it, a pale rim, water with
-- coins shining at the bottom (one twinkling), two posts under a little lilac roof with purple trim and gold finials,
-- the rope wound on its axle, the bucket hanging over the water and swinging, a lamp on a post, pink
-- roses climbing it.
M.wishingwell = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 2, 0.25, "rock_dark", "Paving")
	Parts.cyl(m, f, 0, 0.275, 0, 1.5, 0.5, "rock", "Wall")
	Parts.cyl(m, f, 0, 0.65, 0, 1.5, 0.25, "rock_dark", "Wall")
	for i, a in { -10, 35, 80, 125 } do
		local r = math.rad(a)
		local p = v(math.cos(r) * 0.72, if i % 2 == 0 then 0.42 else 0.2, math.sin(r) * 0.72)
		Parts.at(m, f, CFrame.lookAt(p, v(0, p.Y, 0)), 0.5, 0.25, 0.25, if i % 2 == 0 then "pavement" else "rock_dark", "Stone")
	end
	Parts.box(m, f, -0.45, 0.45, 0.58, 0.5, 0.25, 0.25, "moss", "Moss")
	pool(m, f, 0, 0.68, 0, 1)
	for k = 0, 7 do
		local a = k * math.pi / 4
		Parts.turned(m, f, math.cos(a) * 0.625, 0.9, math.sin(a) * 0.625, 0.5, 0.25, 0.25, math.pi / 2 - a, "pavement", "Rim")
	end
	for i, c in { { 0.15, 0.12 }, { -0.2, -0.12 }, { 0.12, -0.28 } } do
		Parts.glow(m, f, c[1], 0.69, c[2], 0.25, 0.25, 0.25, "gold", if i == 1 then "Sparkle" else "Coin")
	end
	-- posts, the axle with its rope and crank, the roof
	for _, x in { -0.8, 0.8 } do
		Parts.box(m, f, x, 0.875, 0, 0.25, 1.75, 0.25, "wood", "Post")
	end
	Parts.log(m, f, 0, 1.45, 0, 1.75, 0.25, "wood_dark", "Axle")
	Parts.log(m, f, 0, 1.45, 0, 0.5, 0.5, "straw", "Rope")
	Parts.wedge(m, f, 0, 2.0, -0.375, 2, 0.5, 0.75, "crystal", 0, "Roof")
	Parts.wedge(m, f, 0, 2.0, 0.375, 2, 0.5, 0.75, "crystal", math.pi, "Roof")
	Parts.log(m, f, 0, 2.28, 0, 2, 0.25, "purple", "Ridge")
	Parts.box(m, f, 0, 1.8, 0.7, 2, 0.25, 0.25, "purple", "Trim")
	for _, x in { -0.9, 0.9 } do
		Parts.ball(m, f, x, 2.45, 0, 0.25, "gold", "Finial")
	end
	-- the bucket on its rope, swinging over the water
	local hook = v(0, 1.45, 0.2)
	swing(Parts.box(m, f, 0, 1.3, 0.2, 0.25, 0.25, 0.25, "straw", "Rope"), hook, "X", 1.3, 0.15)
	swing(Parts.box(m, f, 0, 1.18, 0.2, 0.5, 0.25, 0.25, "steel_dark", "Handle"), hook, "X", 1.3, 0.15)
	swing(Parts.cyl(m, f, 0, 1.0, 0.2, 0.5, 0.25, "wood", "Bucket"), hook, "X", 1.3, 0.15)
	swing(Parts.cyl(m, f, 0, 0.88, 0.2, 0.25, 0.25, "wood_dark", "Bucket"), hook, "X", 1.3, 0.15)
	-- a lamp on the left post
	Parts.box(m, f, -0.8, 1.35, 0.2, 0.25, 0.25, 0.25, "gold", "LampCap")
	Parts.glow(m, f, -0.8, 1.12, 0.2, 0.25, 0.25, 0.25, "cream", "Lamp")
	-- roses climbing the right post
	for i, y in { 0.45, 0.85, 1.3, 1.6 } do
		local leaf = i % 2 == 0
		Parts.box(m, f, 0.8 + (if leaf then -0.1 else 0.1), y, 0.15, 0.25, 0.25, 0.25, if leaf then "moss" else "pink", if leaf then "Leaf" else "Bloom")
	end
	Parts.box(m, f, 0.7, 0.65, 0.12, 0.25, 0.25, 0.25, "leaf", "Leaf")
end

-- Crystal Arch (3 x 1): two crystals, one lilac and one pink, grown up from mossy rocks, darker at the root and paler
-- up their length, bent over to cross at the top where a light bobs; small crystals growing out of the bends and in
-- clusters at their feet, the tips twinkling, lights drifting up and down under the arch, flowers in the moss.
M.crystalarch = function(m, f)
	for _, s in { -1, 1 } do
		local tones = if s < 0 then { "purple", "crystal", "crystal" } else { "pink", "pink", "cherry" }
		local z = s * 0.12
		Parts.ball(m, f, s * 1.05, 0.12, 0, 0.75, "rock", "Rock")
		Parts.ball(m, f, s * 1.22, 0.05, 0.22, 0.5, "rock_dark", "Rock")
		Parts.ball(m, f, s * 0.75, 0.05, -0.22, 0.5, "rock_dark", "Rock")
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
				seg(m, f, b, b + v(s * 0.35, 0.3, 0), 0.25, tones[i + 1], if i == 2 then "Sparkle" else "Crystal", true, math.pi / 4)
			end
		end
		seg(m, f, pts[4] + d * 0.1, pts[4] + d * 0.55, 0.25, "white", "Tip", true, math.pi / 4)
		-- small crystals at its foot
		for k, c in { { 1.22, 0.22, 1.3, 0.75, 0.28 }, { 0.75, 0.25, 0.6, 0.6, 0.28 }, { 1.2, -0.22, 1.3, 0.65, -0.28 }, { 0.72, -0.25, 0.55, 0.5, -0.28 }, { 1.3, 0.02, 1.3, 0.45, 0.05 } } do
			seg(m, f, v(s * c[1], 0.1, c[2]), v(s * c[3], c[4], c[5]), 0.25, if k == 2 or k == 5 then "ice" else tones[2], "Crystal", k == 1, math.pi / 4)
		end
	end
	Parts.move(Parts.ball(m, f, 0, 3.05, 0, 0.5, "white", "Orb", true), "bob", v(0, 3.05, 0), "Y", 1.1, 0.06)
	for i, l in { { x = -0.35, y = 1.0, z = 0.2, c = "pink" }, { x = 0.3, y = 1.6, z = -0.1, c = "crystal" }, { x = 0, y = 0.55, z = 0.25, c = "cream" } } do
		local p = Parts.glow(m, f, l.x, l.y, l.z, 0.25, 0.25, 0.25, l.c, if i == 2 then "Sparkle" else "Wisp")
		Parts.move(p, "bob", v(l.x, l.y, l.z), "Y", 1.3 + i * 0.2, 0.12, i * 2.1)
	end
	for i, c in { { -0.55, 0.3 }, { 0.6, -0.3 }, { 0.5, 0.35 }, { -0.6, -0.32 } } do
		Parts.box(m, f, c[1], 0.1, c[2], 0.25, 0.25, 0.25, if i == 4 then "cream" else "pink", "Flower")
	end
end

------------------------------------------------------------------ the zen garden
-- Bamboo Screen (2 x 1): four canes in a panel, each in two lengths with a dark knot between, between two thick posts
-- with straw knots and cut tops, two rails across tied with cord, on a stone curb with a strip of pale gravel in front,
-- moss and a fern at its foot.
M.bambooscreen = function(m, f)
	Parts.box(m, f, 0, 0, 0, 2, 0.25, 0.5, "rock", "Curb")
	Parts.box(m, f, 0, 0, 0.36, 2, 0.25, 0.25, "pavement", "Gravel")
	for _, x in { -0.75, 0.75 } do
		Parts.cyl(m, f, x, 0.5, 0, 0.5, 1, "bamboo", "Post")
		Parts.cyl(m, f, x, 1.125, 0, 0.5, 0.25, "straw", "Knot")
		Parts.cyl(m, f, x, 1.5, 0, 0.5, 0.5, "bamboo", "Post")
		Parts.cyl(m, f, x, 1.8, 0, 0.25, 0.25, "straw", "Cut")
	end
	for i, x in { -0.375, -0.125, 0.125, 0.375 } do
		local h = if i % 2 == 0 then 1.5 else 1.25
		local k = if i % 2 == 0 then 0.8 else 0.65
		local tone = if i == 3 then "straw" else "bamboo"
		Parts.cyl(m, f, x, 0.1 + (k - 0.1) / 2, 0, 0.25, k - 0.1, tone, "Cane")
		Parts.cyl(m, f, x, k + 0.02, 0, 0.25, 0.25, "moss", "Knot")
		Parts.cyl(m, f, x, k + 0.12 + (h - k) / 2, 0, 0.25, h - k, tone, "Cane")
	end
	for _, y in { 0.45, 1.05 } do
		Parts.log(m, f, 0, y, 0.2, 1.5, 0.25, "bamboo", "Rail")
		for _, x in { -0.5, 0.5 } do
			Parts.box(m, f, x, y, 0.22, 0.25, 0.25, 0.25, "wood_dark", "Cord")
		end
	end
	Parts.ball(m, f, -0.55, 0.1, 0.25, 0.5, "moss", "Moss")
	Parts.ball(m, f, 0.3, 0.05, 0.32, 0.25, "moss", "Moss")
	Parts.ball(m, f, 0.85, 0.15, 0.3, 0.25, "leaf", "Fern")
	Parts.ball(m, f, 0.72, 0.2, 0.36, 0.25, "leaf_dark", "Fern")
end

-- Wind Chimes (1 x 1): a bamboo post banded in moss green on a flat stone, an arm out from it, a wooden plate with a
-- little cap and a brass bead hung from the arm, four tubes of different lengths (one of brass) each swinging on its
-- own, out of step, and a clapper with a paper strip under it swinging in the wind; moss, a fern and a pebble at its
-- foot.
M.windchime = function(m, f)
	Parts.cyl(m, f, 0.05, 0.02, 0.05, 0.75, 0.25, "rock", "Stone")
	Parts.box(m, f, -0.25, 0.08, -0.25, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.ball(m, f, 0.34, 0.06, 0.3, 0.25, "rock_dark", "Pebble")
	Parts.ball(m, f, -0.35, 0.12, 0.3, 0.25, "leaf", "Fern")
	local post = ACROSS * -0.45
	local c = ACROSS * 0.15
	Parts.cyl(m, f, post.X, 1.0, post.Z, 0.25, 2, "bamboo", "Post")
	for _, y in { 0.7, 1.4 } do
		Parts.cyl(m, f, post.X, y, post.Z, 0.25, 0.25, "moss", "Knot")
	end
	seg(m, f, post + v(0, 1.9, 0), c + v(0, 1.9, 0), 0.25, "bamboo", "Arm")
	Parts.box(m, f, post.X, 1.9, post.Z, 0.25, 0.25, 0.25, "wood_dark", "Cord")
	Parts.box(m, f, c.X, 1.72, c.Z, 0.25, 0.25, 0.25, "wood_dark", "Cord")
	Parts.cyl(m, f, c.X, 1.6, c.Z, 0.5, 0.25, "wood_dark", "Cap")
	Parts.cyl(m, f, c.X, 1.5, c.Z, 0.75, 0.25, "wood", "Plate")
	-- the tubes, each on its own hook under the plate
	local tz = (TOWARD * v(0, 0, 1))
	local tones = { "steel", "steel", "gold", "steel_dark" }
	for k, off in { ACROSS * -0.26, tz * 0.22, ACROSS * 0.26, tz * -0.2 } do
		local at = c + off
		local len = if k % 2 == 1 then 0.75 else 0.5
		local hub = v(at.X, 1.375, at.Z)
		swing(Parts.cyl(m, f, at.X, 1.375 - len / 2, at.Z, 0.25, len, tones[k], "Chime"), hub, if k % 2 == 0 then "X" else "Z", 1.7 + k * 0.15, 0.15, k * 1.4)
	end
	-- the clapper and the paper strip that catches the wind
	local hub = v(c.X, 1.375, c.Z)
	swing(Parts.box(m, f, c.X, 1.2, c.Z, 0.25, 0.25, 0.25, "straw", "String"), hub, "X", 1.2, 0.25, 0.7)
	swing(Parts.box(m, f, c.X, 0.95, c.Z, 0.25, 0.25, 0.25, "wood_dark", "Clapper"), hub, "X", 1.2, 0.25, 0.7)
	swing(Parts.box(m, f, c.X, 0.6, c.Z, 0.25, 0.5, 0.25, "paper", "Paper"), hub, "X", 1.2, 0.25, 0.7)
	Parts.ball(m, f, c.X, 1.78, c.Z, 0.25, "gold", "Bead")
end

-- Stone Lantern (1 x 1): a grey stone lantern on a bed of pale pebbles: a dark base, a round pillar with a band, a
-- shelf, a light box with its flame showing between the corners, a wide roof with turned-up corners, two
-- smaller roofs over it, a knob and a jewel on top, moss on the roof and the base, a fern, a stepping stone.
M.stonelantern = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "pavement", "Pebbles")
	Parts.ball(m, f, 0.38, 0.06, 0.28, 0.25, "rock_dark", "Pebble")
	Parts.box(m, f, -0.2, 0.06, 0.4, 0.25, 0.25, 0.25, "rock", "Stone")
	Parts.box(m, f, 0, 0.18, 0, 0.75, 0.25, 0.75, "rock_dark", "Base")
	Parts.cyl(m, f, 0, 0.55, 0, 0.5, 0.5, "rock", "Pillar")
	Parts.cyl(m, f, 0, 0.55, 0, 0.5, 0.25, "rock_dark", "Band")
	Parts.box(m, f, 0, 0.9, 0, 0.75, 0.25, 0.75, "rock", "Shelf")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.25, 1.25, c[2] * 0.25, 0.25, 0.5, 0.25, "rock", "Corner")
	end
	Parts.glow(m, f, 0, 1.25, 0, 0.5, 0.5, 0.5, "yellow", "Flame")
	Parts.box(m, f, 0, 1.625, 0, 1, 0.25, 1, "rock", "Roof")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.375, 1.75, c[2] * 0.375, 0.25, 0.25, 0.25, "rock", "Eave")
	end
	Parts.box(m, f, 0, 1.875, 0, 0.75, 0.25, 0.75, "rock_dark", "Roof")
	Parts.box(m, f, 0, 2.1, 0, 0.5, 0.25, 0.5, "rock", "Roof")
	Parts.ball(m, f, 0, 2.3, 0, 0.25, "rock_dark", "Knob")
	Parts.ball(m, f, 0, 2.48, 0, 0.25, "rock", "Jewel")
	Parts.box(m, f, -0.25, 1.78, 0.25, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.12, 2.0, -0.2, 0.25, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.28, 0.32, 0.3, 0.25, 0.25, 0.25, "moss", "Moss")
	Parts.ball(m, f, -0.38, 0.15, -0.32, 0.25, "leaf", "Fern")
end

-- Water Basin (1 x 1): a round stone bowl on a dark foot full of still water, on a bed of pale pebbles with dark ones
-- in it; a bamboo pipe with two knots, held by two crossed stakes tied with cord, its spout running a thin stream into
-- the bowl; a bamboo ladle laid across the bowl's rim; moss and a fern.
M.zenbasin = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "pavement", "Pebbles")
	for _, p in { { -0.36, -0.05 }, { 0.36, 0.28 }, { -0.1, 0.36 }, { 0.28, -0.36 } } do
		Parts.ball(m, f, p[1], 0.06, p[2], 0.25, "rock_dark", "Pebble")
	end
	local b = ACROSS * 0.12 + v(0.05, 0, 0.05)
	Parts.cyl(m, f, b.X, 0.12, b.Z, 0.5, 0.25, "rock_dark", "Foot")
	Parts.cyl(m, f, b.X, 0.35, b.Z, 0.75, 0.5, "rock", "Bowl")
	pool(m, f, b.X, 0.49, b.Z, 0.5)
	-- the pipe, its stakes and the stream
	local post = ACROSS * -0.42 + v(0.02, 0, 0.02)
	Parts.cyl(m, f, post.X, 0.5, post.Z, 0.25, 1, "bamboo", "Pipe")
	for _, y in { 0.35, 0.72 } do
		Parts.cyl(m, f, post.X, y, post.Z, 0.25, 0.25, "moss", "Knot")
	end
	local spoutEnd = b + v(0, 0.82, 0) - ACROSS * 0.05
	seg(m, f, post + v(0, 0.95, 0), spoutEnd, 0.25, "bamboo", "Spout")
	local mid = post:Lerp(spoutEnd, 0.5)
	for _, s in { -1, 1 } do
		seg(m, f, v(mid.X, 0.05, mid.Z) + (TOWARD * v(0, 0, s * 0.18)), v(mid.X, 0.95, mid.Z) - (TOWARD * v(0, 0, s * 0.14)), 0.25, "wood", "Stake")
	end
	Parts.box(m, f, mid.X, 0.82, mid.Z, 0.25, 0.25, 0.25, "wood_dark", "Tie")
	Parts.box(m, f, b.X - 0.02, 0.66, b.Z + 0.02, 0.25, 0.25, 0.25, "shallow", "Stream"):SetAttribute("PixelWater", 4)
	-- the ladle across the rim
	seg(m, f, b + v(-0.1, 0.62, 0.3), b + v(0.3, 0.62, -0.1), 0.25, "bamboo", "Ladle")
	Parts.cyl(m, f, b.X - 0.12, 0.66, b.Z + 0.32, 0.25, 0.25, "straw", "Ladle")
	Parts.box(m, f, b.X + 0.2, 0.1, b.Z + 0.28, 0.25, 0.25, 0.25, "moss", "Moss")
	Parts.ball(m, f, -0.25, 0.2, -0.25, 0.5, "leaf", "Fern")
	Parts.ball(m, f, -0.15, 0.32, -0.18, 0.25, "leaf_dark", "Fern")
end

-- Lantern Tower (2 x 2): a tall stone lantern on a bed of pale gravel: a stepped base, a light chamber with its flame
-- glowing between the corners, five slate roofs stacked high with turned-up corners and a short stone
-- neck between each, two small brass bells swinging under the lowest roof's corners in view, a knob and brass rings on
-- top, moss, a fern.
M.lanterntower = function(m, f)
	Parts.box(m, f, 0, 0, 0, 2, 0.25, 2, "pavement", "Gravel")
	Parts.box(m, f, 0, 0.1, 0, 1.75, 0.25, 1.75, "rock_dark", "Base")
	Parts.box(m, f, 0, 0.475, 0, 1.25, 0.5, 1.25, "rock", "Base")
	for _, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		Parts.box(m, f, c[1] * 0.375, 1.1, c[2] * 0.375, 0.25, 0.75, 0.25, "rock", "Corner")
	end
	Parts.glow(m, f, 0, 1.1, 0, 0.75, 0.75, 0.75, "yellow", "Flame")
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
	-- the bells under the lowest roof's corners in view
	for k, c in { { 1, 1 }, { 1, -1 } } do
		local hub = v(c[1] * 0.75, 1.475, c[2] * 0.75)
		swing(Parts.box(m, f, hub.X, hub.Y - 0.2, hub.Z, 0.25, 0.25, 0.25, "gold", "Bell"), hub, if k == 1 then "X" else "Z", 1.8, 0.2, k * 1.7)
	end
	Parts.box(m, f, 0, y - 0.125, 0, 0.25, 0.25, 0.25, "rock", "Neck")
	Parts.ball(m, f, 0, y + 0.1, 0, 0.5, "rock", "Knob")
	Parts.cyl(m, f, 0, y + 0.35, 0, 0.25, 0.25, "gold", "Ring")
	Parts.ball(m, f, 0, y + 0.52, 0, 0.25, "gold", "Jewel")
	Parts.box(m, f, -0.55, 1.85, 0.55, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.6, 0.3, 0.75, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.ball(m, f, -0.75, 0.25, 0.72, 0.25, "leaf", "Fern")
	Parts.ball(m, f, -0.65, 0.2, 0.82, 0.25, "leaf_dark", "Fern")
end

------------------------------------------------------------------ the volcano
-- Fire Basin (1 x 1): an iron bowl with a steel rim and rivets on three legs with feet, over a slab of basalt ringed
-- with stones, glowing coals smoking a little, flames in three colours, sparks rising, two logs stacked ready at its
-- foot.
M.firebasin = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1, 0.25, "basalt", "Slab")
	for i, s in { { -0.38, -0.25 }, { 0.38, -0.2 }, { -0.36, 0.3 }, { 0.15, -0.4 } } do
		Parts.ball(m, f, s[1], 0.1, s[2], 0.25, if i % 2 == 0 then "rock_dark" else "black", "Stone")
	end
	for k = 0, 2 do
		local a = k * math.pi * 2 / 3 + math.pi / 6
		local foot = v(math.cos(a) * 0.36, 0.1, math.sin(a) * 0.36)
		seg(m, f, foot, v(math.cos(a) * 0.18, 0.6, math.sin(a) * 0.18), 0.25, "black", "Leg")
		Parts.box(m, f, foot.X, 0.1, foot.Z, 0.25, 0.25, 0.25, "steel_dark", "Foot")
	end
	Parts.ball(m, f, 0, 0.62, 0, 0.5, "black", "Bowl")
	Parts.cyl(m, f, 0, 0.8, 0, 0.75, 0.25, "black", "Bowl")
	Parts.cyl(m, f, 0, 0.95, 0, 1, 0.25, "steel_dark", "Rim")
	for _, d in { v(-0.6, 0, 1), v(0.6, 0, 1) } do
		local p = TOWARD * d.Unit * 0.36
		Parts.box(m, f, p.X, 0.82, p.Z, 0.25, 0.25, 0.25, "steel", "Rivet")
	end
	Parts.cyl(m, f, 0, 1.02, 0, 0.75, 0.25, "basalt", "Coals")
	for _, e in { { 0.25, 0.12 }, { -0.2, -0.2 }, { 0.05, 0.28 } } do
		Parts.glow(m, f, e[1], 1.05, e[2], 0.25, 0.25, 0.25, "lava", "Ember")
	end
	-- the flames
	Parts.at(m, f, CFrame.new(0, 1.35, 0) * CFrame.Angles(0, math.pi / 4, 0), 0.5, 0.5, 0.5, "lava", "Flame", true)
	Parts.at(m, f, CFrame.new(0.06, 1.7, 0.04) * CFrame.Angles(0, 0.3, 0.15), 0.25, 0.5, 0.25, "orange", "Fire", true)
	Parts.glow(m, f, -0.04, 1.98, -0.03, 0.25, 0.25, 0.25, "yellow", "Fire")
	Parts.glow(m, f, -0.22, 1.35, 0.15, 0.25, 0.25, 0.25, "orange", "Fire")
	Parts.glow(m, f, 0.2, 1.3, -0.15, 0.25, 0.25, 0.25, "orange", "Fire")
	Parts.glow(m, f, 0.2, 2.3, 0.1, 0.25, 0.25, 0.25, "yellow", "Spark")
	Parts.glow(m, f, -0.15, 2.6, 0.0, 0.25, 0.25, 0.25, "lava", "Spark")
	-- logs ready at its foot
	Parts.log(m, f, 0, 0.12, 0.36, 0.5, 0.25, "wood_dark", "Log")
	Parts.log(m, f, 0.05, 0.3, 0.36, 0.5, 0.25, "wood", "Log")
end

-- Steam Vent (2 x 2): a low cone of basalt in two steps with a black lip round a glowing mouth hot white at its heart,
-- yellow and gold crust round it, plates of darker rock and cracks of lava in the ground, dark rocks, a smaller vent
-- at the side, steam rolling up in puffs that rise and fall and drift.
M.steamvent = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1.75, 0.25, "basalt", "Ground")
	Parts.turned(m, f, 0.4, 0.005, 0.45, 1, 0.25, 0.75, 0.5, "basalt", "Ground")
	Parts.turned(m, f, -0.5, 0.02, 0.45, 0.5, 0.25, 0.5, 0.3, "rock_dark", "Plate")
	Parts.turned(m, f, 0.55, 0.02, -0.25, 0.5, 0.25, 0.5, 0.9, "black", "Plate")
	Parts.cyl(m, f, -0.1, 0.25, -0.1, 1, 0.5, "basalt", "Cone")
	Parts.cyl(m, f, -0.1, 0.55, -0.1, 0.75, 0.25, "black", "Cone")
	Parts.cyl(m, f, -0.1, 0.64, -0.1, 0.5, 0.25, "lava", "Mouth", true)
	Parts.glow(m, f, -0.1, 0.68, -0.1, 0.25, 0.25, 0.25, "yellow", "Heart")
	for i, s in { { 0.25, 0.48, 0.15 }, { -0.45, 0.45, 0.05 }, { -0.05, 0.48, 0.35 }, { 0.28, 0.42, -0.2 }, { -0.35, 0.42, 0.28 } } do
		Parts.box(m, f, s[1], s[2], s[3], 0.25, 0.25, 0.25, if i > 3 then "gold" else "yellow", "Crust")
	end
	for i, r in { { 0.6, 0.15, -0.55, 0.75 }, { -0.65, 0.1, 0.5, 0.5 }, { 0.7, 0.1, 0.5, 0.5 }, { -0.7, 0.08, -0.35, 0.25 }, { 0.2, 0.08, 0.78, 0.25 } } do
		Parts.ball(m, f, r[1], r[2], r[3], r[4], if i % 2 == 0 then "rock_dark" else "basalt", "Rock")
	end
	for _, c in { { 0.5, 0.15, 0.4, 0.75 }, { -0.55, -0.4, -0.7, 0.5 }, { 0.05, 0.62, 1.3, 0.5 }, { -0.2, -0.75, 0.2, 0.5 } } do
		Parts.turned(m, f, c[1], 0.02, c[2], c[4], 0.25, 0.25, c[3], "lava", "Crack", true)
	end
	-- a smaller vent at the side
	Parts.cyl(m, f, 0.55, 0.15, 0.2, 0.5, 0.25, "basalt", "Cone")
	Parts.cyl(m, f, 0.55, 0.22, 0.2, 0.25, 0.25, "orange", "Mouth", true)
	-- the steam, its lower puffs rising and falling
	for i, p in { { -0.1, 1.05, -0.1, 0.5 }, { 0, 1.5, -0.15, 0.75 }, { 0.15, 2.05, -0.25, 0.75 }, { 0.3, 2.55, -0.3, 0.5 }, { 0.45, 2.9, -0.35, 0.5 }, { 0.6, 0.55, 0.2, 0.25 } } do
		local puff = sway(Parts.ball(m, f, p[1], p[2], p[3], p[4], "white", if i == 1 or i == 6 then "Steam" else "Cloud"))
		if i >= 2 and i <= 4 then
			Parts.move(puff, "bob", v(p[1], p[2], p[3]), "Y", 1.1 + i * 0.1, 0.1, i * 1.3)
		end
	end
end

-- A shard of black glass standing at (x, z), side on to the view so its point shows: a square shaft of width a and
-- height h with a wedge for a point, leaning by `lean` across the view.
local function shard(m: Model, f: CFrame, x: number, z: number, flip: boolean, lean: number, a: number, h: number, tip: number, color: string)
	local c = CFrame.new(x, 0, z) * CFrame.Angles(0, if flip then 3 * VIEW else -VIEW, 0) * CFrame.Angles(lean, 0, 0)
	Parts.at(m, f, c * CFrame.new(0, h / 2, 0), a, h, a, color, "Shard")
	wedgeAt(m, f, c * CFrame.new(0, h + tip / 2, 0), a, tip, a, color, "Shard")
end

-- Obsidian Spire (2 x 2): a tall spire of black glass narrowing to a sharp point that glints, a sheen down one edge and
-- a darker facet down another, molten seams at its foot and up its shaft, smaller blades leaning out round it, a pool
-- of lava at its foot, rubble, cracked plates and veins of lava in the basalt.
M.obsidian = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 1.75, 0.25, "basalt", "Ground")
	Parts.turned(m, f, -0.45, 0.02, 0.5, 0.5, 0.25, 0.5, 0.4, "black", "Plate")
	Parts.turned(m, f, 0.62, 0.02, -0.1, 0.5, 0.25, 0.25, 1.1, "rock_dark", "Plate")
	for _, c in { { 0.55, 0.45, 0.6, 0.75 }, { -0.6, 0.3, 2.2, 0.5 }, { 0.1, -0.7, 1.4, 0.5 }, { -0.75, -0.1, 0.4, 0.5 } } do
		Parts.turned(m, f, c[1], 0.03, c[2], c[4], 0.25, 0.25, c[3], "lava", "Vein", true)
	end
	for i, r in { { 0.7, -0.55, 0.5 }, { -0.7, -0.5, 0.5 }, { -0.35, 0.7, 0.25 }, { 0.78, 0.15, 0.25 }, { 0.2, 0.8, 0.25 } } do
		Parts.ball(m, f, r[1], 0.12, r[2], r[3], if i % 2 == 0 then "rock_dark" else "basalt", "Rubble")
	end
	-- the spire: a broad foot, a narrower shaft, the point
	local c = CFrame.new(-0.1, 0, -0.1) * CFrame.Angles(0, -VIEW, 0) * CFrame.Angles(0.06, 0, 0)
	Parts.at(m, f, c * CFrame.new(0, 0.875, 0), 0.75, 1.75, 0.75, "black", "Spire")
	Parts.at(m, f, c * CFrame.new(0, 2.25, 0.08), 0.5, 1, 0.5, "black", "Spire")
	wedgeAt(m, f, c * CFrame.new(0, 3.375, 0.08), 0.5, 1.25, 0.5, "black", "Spire")
	Parts.at(m, f, c * CFrame.new(0.3, 1.1, 0.3), 0.25, 1.5, 0.25, "slate", "Sheen")
	Parts.at(m, f, c * CFrame.new(0.18, 2.3, 0.3), 0.25, 0.75, 0.25, "slate", "Sheen")
	Parts.at(m, f, c * CFrame.new(-0.3, 1.0, 0.3), 0.25, 1.25, 0.25, "night", "Facet")
	Parts.at(m, f, c * CFrame.new(-0.2, 0.35, 0.32), 0.25, 0.5, 0.25, "lava", "Seam", true)
	Parts.at(m, f, c * CFrame.new(0.05, 1.55, 0.33), 0.25, 0.5, 0.25, "orange", "Seam", true)
	Parts.at(m, f, c * CFrame.new(0, 3.3, 0.22), 0.25, 0.25, 0.25, "white", "Sparkle")
	-- blades round it
	shard(m, f, 0.38, 0.32, false, -0.3, 0.5, 0.75, 0.75, "night")
	shard(m, f, -0.48, 0.2, true, 0.3, 0.5, 1, 0.75, "black")
	shard(m, f, 0.55, -0.45, true, -0.25, 0.25, 0.5, 0.5, "black")
	shard(m, f, -0.4, -0.42, false, 0.3, 0.5, 0.5, 0.75, "night")
	shard(m, f, 0.1, 0.5, true, -0.2, 0.25, 0.25, 0.5, "black")
	-- a pool of lava at its foot
	Parts.cyl(m, f, 0.12, 0.04, 0.3, 0.5, 0.25, "lava", "Lava", true)
	Parts.glow(m, f, 0.12, 0.08, 0.3, 0.25, 0.25, 0.25, "yellow", "Lava")
end

-- Lava Pool (3 x 3): a pool of glowing lava hotter at its heart, set in a black rim, crusts of rock floating on it,
-- bubbles rising and sinking, a flicker of flame over the hottest spot; a ring of basalt boulders with stones on them
-- and a gap where a rivulet escapes, a heap of rock at the back with a smoking chimney and lava trickling down it,
-- black shards, glowing cracks in the ground round it.
M.lavapool = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 3, 0.25, "basalt", "Ground")
	Parts.cyl(m, f, 0, 0.03, 0.1, 2.5, 0.25, "black", "Rim")
	Parts.cyl(m, f, 0, 0.05, 0.1, 2.25, 0.25, "lava", "Lava", true)
	Parts.cyl(m, f, -0.2, 0.06, 0.2, 1, 0.25, "orange", "Lava", true)
	Parts.cyl(m, f, -0.3, 0.07, 0.3, 0.5, 0.25, "yellow", "Lava", true)
	Parts.glow(m, f, -0.3, 0.3, 0.3, 0.25, 0.25, 0.25, "yellow", "Flame")
	Parts.turned(m, f, 0.45, 0.08, 0.5, 0.5, 0.25, 0.75, 0.6, "basalt", "Crust")
	Parts.turned(m, f, -0.6, 0.08, -0.25, 0.75, 0.25, 0.5, 1.2, "black", "Crust")
	Parts.turned(m, f, 0.3, 0.08, -0.55, 0.5, 0.25, 0.25, 0.3, "rock_dark", "Crust")
	Parts.turned(m, f, -0.75, 0.08, 0.6, 0.25, 0.25, 0.5, 0.8, "basalt", "Crust")
	-- bubbles rising and sinking
	for i, b in { { 0.4, 0.12, -0.3, 0.5 }, { -0.65, 0.18, 0.45, 0.25 }, { 0.15, 0.2, 0.75, 0.25 }, { 0.75, 0.12, 0.1, 0.25 }, { -0.1, 0.12, -0.35, 0.25 } } do
		local p = Parts.ball(m, f, b[1], b[2], b[3], b[4], if i == 2 or i == 3 then "yellow" else "orange", "Bubble", true)
		if i <= 3 then
			Parts.move(p, "bob", v(b[1], b[2], b[3]), "Y", 1.4 + i * 0.2, 0.06, i * 2)
		end
	end
	-- the ring of boulders, a gap at the front right
	for k = 0, 9 do
		local a = k * math.pi * 2 / 11 + 1.1
		local size = if k % 3 == 0 then 0.75 else 0.5
		local p = v(math.cos(a) * math.min(1.28, 1.48 - size / 2), 0.1, 0.1 + math.sin(a) * math.min(1.22, 1.38 - size / 2))
		Parts.ball(m, f, p.X, p.Y, p.Z, size, if k % 4 == 1 then "rock_dark" else "basalt", "Boulder")
		if k % 3 == 0 then
			Parts.ball(m, f, p.X, 0.42, p.Z, 0.25, if k == 3 then "black" else "rock_dark", "Stone")
		end
	end
	Parts.turned(m, f, 1.0, 0.03, 1.0, 0.25, 0.25, 0.75, -math.pi / 4, "lava", "Rivulet", true)
	-- the heap at the back, its chimney and its trickle
	Parts.ball(m, f, -0.55, 0.25, -1.0, 1, "basalt", "Heap")
	Parts.ball(m, f, -0.15, 0.6, -1.1, 0.75, "basalt", "Heap")
	Parts.ball(m, f, -0.85, 0.5, -1.05, 0.5, "rock_dark", "Heap")
	Parts.cyl(m, f, -0.15, 1.05, -1.1, 0.25, 0.25, "black", "Smoke")
	seg(m, f, v(-0.25, 0.85, -0.95), v(-0.12, 0.2, -0.62), 0.25, "lava", "Trickle", true)
	shard(m, f, 0.75, -0.95, false, -0.2, 0.25, 0.75, 0.5, "black")
	shard(m, f, 1.05, -0.6, true, 0.25, 0.25, 0.5, 0.5, "night")
	shard(m, f, -1.15, 0.55, true, 0.2, 0.25, 0.5, 0.5, "black")
	-- cracks glowing in the ground round it
	Parts.turned(m, f, -1.25, 0.03, -0.35, 0.5, 0.25, 0.25, 1.2, "lava", "Crack", true)
	Parts.turned(m, f, 0.35, 0.03, 1.38, 0.5, 0.25, 0.25, 0.1, "orange", "Crack", true)
end

------------------------------------------------------------------ the islands past Driftling Haven
-- (the request of 2026-11-14: "allow expansion up to level 20 ... add decor")

-- Frozen Waterfall (3 x 2): a cliff of grey and blue-grey rock in three masses with crags standing out of them, snow
-- along the tops dripping over the edges, a snowy pine up on the right; in the middle the fall, frozen in streaks of
-- ice and white with a thread of water still running down it, curled over the lip, fringed with icicles, piled up in
-- lumps at its foot on a frozen pool with cracks and one open hole; stones round the pool with snow on them, a second
-- pine at the front left, glints on the ice, drifts.
M.frozenfall = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 3, 0.25, 2, "snow", "Snow")
	-- the cliff: three masses, crags out of them
	Parts.box(m, f, -1.0, 1.375, -0.625, 1, 2.75, 0.75, "rock_dark", "Cliff")
	Parts.box(m, f, 1.0, 1.25, -0.625, 1, 2.5, 0.75, "slate", "Cliff")
	Parts.box(m, f, 0, 1.125, -0.75, 1, 2.25, 0.5, "slate", "Cliff")
	Parts.box(m, f, -0.7, 2.05, -0.3, 0.5, 0.75, 0.25, "rock", "Crag")
	Parts.box(m, f, -1.25, 1.2, -0.2, 0.5, 1, 0.25, "slate", "Crag")
	Parts.box(m, f, 0.75, 1.6, -0.3, 0.5, 0.75, 0.25, "rock", "Crag")
	Parts.box(m, f, 1.1, 0.375, -0.15, 0.75, 0.75, 0.5, "rock_dark", "Ledge")
	-- snow along the tops and on the ledges, dripping over the edges
	Parts.box(m, f, -1.0, 2.875, -0.6, 1.0, 0.25, 0.75, "snow", "Snow")
	Parts.box(m, f, 1.0, 2.625, -0.6, 1.0, 0.25, 0.75, "snow", "Snow")
	Parts.box(m, f, 1.1, 0.8, -0.15, 0.75, 0.25, 0.5, "snow", "Snow")
	Parts.box(m, f, -0.7, 2.5, -0.3, 0.5, 0.25, 0.25, "snow", "Snow")
	for _, d in { { -1.3, 2.7, -0.2 }, { -0.75, 2.72, -0.22 }, { 0.7, 2.45, -0.22 }, { 1.35, 2.42, -0.2 }, { 0.85, 0.62, 0.12 } } do
		Parts.box(m, f, d[1], d[2], d[3], 0.25, 0.25, 0.25, "white", "Drip")
	end
	for i, d in { { -1.15, 0.6, -0.04 }, { -0.62, 1.58, -0.13 }, { 1.3, 0.55, 0.12 } } do
		Parts.box(m, f, d[1], d[2], d[3], 0.25, 0.5, 0.25, if i == 2 then "window" else "ice", "Icicle")
	end
	-- the fall: a sheet of ice over the lip, streaks down its face, a thread of water still running
	Parts.log(m, f, 0, 2.2, -0.45, 1, 0.5, "ice", "Lip")
	Parts.box(m, f, 0, 1.2, -0.4, 1, 2, 0.25, "ice", "Fall")
	Parts.box(m, f, -0.35, 1.2, -0.25, 0.25, 1.75, 0.25, "window", "Streak")
	Parts.box(m, f, 0.15, 1.3, -0.22, 0.25, 1.5, 0.25, "white", "Streak")
	Parts.box(m, f, 0.38, 1.05, -0.25, 0.25, 1.25, 0.25, "window", "Streak")
	Parts.box(m, f, -0.1, 1.05, -0.2, 0.25, 1.5, 0.25, "shallow", "Trickle"):SetAttribute("PixelWater", 4)
	for i, x in { -0.4, -0.12, 0.2, 0.42 } do
		Parts.box(m, f, x, 1.92, -0.12, 0.25, if i % 2 == 0 then 0.5 else 0.25, 0.25, if i % 2 == 0 then "ice" else "white", "Icicle")
	end
	Parts.box(m, f, 0.15, 1.6, -0.1, 0.25, 0.25, 0.25, "white", "Sparkle")
	-- piled at its foot on the frozen pool
	Parts.cyl(m, f, 0.1, 0.1, 0.25, 1.5, 0.25, "ice", "FrozenPool")
	Parts.ball(m, f, -0.2, 0.35, -0.05, 0.75, "ice", "Heap")
	Parts.ball(m, f, 0.3, 0.3, 0.02, 0.5, "window", "Heap")
	Parts.ball(m, f, 0.02, 0.58, -0.12, 0.5, "white", "Heap")
	Parts.turned(m, f, -0.25, 0.14, 0.6, 0.5, 0.25, 0.25, 0.5, "window", "Crack")
	Parts.turned(m, f, 0.3, 0.14, 0.75, 0.5, 0.25, 0.25, -0.4, "white", "Crack")
	pool(m, f, 0.5, 0.15, 0.45, 0.5)
	Parts.box(m, f, -0.5, 0.25, 0.15, 0.25, 0.25, 0.25, "white", "Sparkle")
	-- stones round the pool, snow on two of them
	for i, s in { { -0.72, 0.62 }, { -0.4, 0.72 }, { 0.62, 0.72 }, { 0.95, 0.55 }, { 0.92, 0.18 } } do
		Parts.ball(m, f, s[1], 0.12, s[2], 0.5, if i % 2 == 0 then "rock_dark" else "rock", "Stone")
	end
	Parts.box(m, f, -0.72, 0.36, 0.6, 0.25, 0.25, 0.25, "snow", "Snow")
	Parts.box(m, f, 0.95, 0.36, 0.53, 0.25, 0.25, 0.25, "snow", "Snow")
	-- pines, one up on the cliff and one at the front, drifts
	snowpine(m, f, 1.0, 2.75, -0.5, { 1.0, 0.5 })
	snowpine(m, f, -1.0, 0.1, 0.45, { 1.0, 0.5 })
	Parts.ball(m, f, 1.22, 0.06, 0.7, 0.5, "white", "Drift")
	Parts.ball(m, f, -0.15, 0.06, 0.82, 0.25, "snow", "Drift")
end

-- Cider Press (2 x 2): a wooden press on a tray on legs: a basket of staves bound in two iron hoops with apples heaped
-- in its top, a pressing plate on a big iron screw with threads, two uprights and a beam with iron pegs, and on top a
-- capstan of crossed bars with knobs that turns slowly; cider running from the tray's spout into a bucket; beside it a
-- barrel with a tap and a mug of hot cider on its lid, a crate of apples, apples and a leaf on the grass.
M.ciderpress = function(m, f)
	local cz = -0.25
	-- the tray on its legs, its lip and spout
	for _, x in { -0.6, 0.6 } do
		for _, z in { -0.9, 0.3 } do
			Parts.box(m, f, x * 1.25, 0.25, z, 0.25, 0.5, 0.25, "wood_dark", "Leg")
		end
	end
	Parts.box(m, f, 0, 0.55, cz, 1.75, 0.25, 1.5, "wood", "Tray")
	Parts.box(m, f, 0, 0.75, 0.45, 1.75, 0.25, 0.25, "wood_dark", "Lip")
	Parts.box(m, f, 0.8, 0.75, cz, 0.25, 0.25, 1.25, "wood_dark", "Lip")
	Parts.box(m, f, 0.25, 0.6, 0.62, 0.25, 0.25, 0.25, "wood_dark", "Spout")
	Parts.box(m, f, 0.25, 0.38, 0.68, 0.25, 0.25, 0.25, "orange", "Cider"):SetAttribute("PixelWater", 4)
	Parts.cyl(m, f, 0.25, 0.12, 0.7, 0.5, 0.25, "wood", "Bucket")
	Parts.cyl(m, f, 0.25, 0.2, 0.7, 0.25, 0.25, "gold", "Cider")
	-- the basket: staves round a dark core, two hoops, apples in the top
	Parts.cyl(m, f, 0, 1.05, cz, 1, 0.75, "wood_dark", "Basket")
	for _, deg in { -35, 10, 55, 100, 145 } do
		local a = math.rad(deg)
		Parts.turned(m, f, math.cos(a) * 0.45, 1.05, cz + math.sin(a) * 0.45, 0.25, 0.75, 0.25, math.pi / 2 - a, "wood", "Stave")
	end
	for _, y in { 0.8, 1.3 } do
		Parts.cyl(m, f, 0, y, cz, 1.25, 0.25, "steel_dark", "Hoop")
	end
	for i, a in { { 0.28, 0.1 }, { -0.25, 0.15 }, { 0.05, -0.3 }, { -0.2, -0.22 } } do
		Parts.ball(m, f, a[1], 1.48, cz + a[2], 0.25, if i % 2 == 0 then "maple" else "berry_red", "Apple")
	end
	-- the plate, the screw, the frame
	Parts.cyl(m, f, 0, 1.75, cz, 0.75, 0.25, "wood", "Plate")
	Parts.cyl(m, f, 0, 2.6, cz, 0.25, 1.75, "steel_dark", "Screw")
	for _, y in { 2.05, 2.3 } do
		Parts.cyl(m, f, 0, y, cz, 0.5, 0.25, "steel", "Thread")
	end
	for _, x in { -0.8, 0.8 } do
		Parts.box(m, f, x, 1.5, cz, 0.25, 3, 0.5, "wood_dark", "Upright")
		Parts.box(m, f, x, 2.75, cz + 0.27, 0.25, 0.25, 0.25, "steel_dark", "Peg")
	end
	Parts.box(m, f, 0, 2.75, cz, 1.75, 0.5, 0.5, "wood", "Beam")
	Parts.ball(m, f, 0, 3.48, cz, 0.25, "gold", "Cap")
	-- the capstan, turning slowly round the screw
	local hub = v(0, 3.25, cz)
	local function turn(p: BasePart)
		Parts.move(p, "spin", hub, "Y", 0.5)
	end
	turn(Parts.cyl(m, f, 0, 3.25, cz, 0.5, 0.25, "wood_dark", "Hub"))
	turn(Parts.log(m, f, 0, 3.25, cz, 1.25, 0.25, "wood", "Bar"))
	turn(Parts.logZ(m, f, 0, 3.25, cz, 1.25, 0.25, "wood", "Bar"))
	for _, d in { v(0.625, 0, 0), v(-0.625, 0, 0), v(0, 0, 0.625), v(0, 0, -0.625) } do
		turn(Parts.ball(m, f, d.X, 3.25, cz + d.Z, 0.25, "wood_dark", "Knob"))
	end
	-- the barrel with its tap and a mug
	local bx, bz = -0.68, 0.7
	Parts.cyl(m, f, bx, 0.375, bz, 0.5, 0.75, "wood", "Barrel")
	Parts.cyl(m, f, bx, 0.8, bz, 0.25, 0.25, "wood_dark", "Bung")
	Parts.box(m, f, bx + 0.12, 0.3, bz + 0.15, 0.25, 0.25, 0.25, "steel", "Tap")
	Parts.cyl(m, f, bx - 0.05, 0.85, bz - 0.12, 0.25, 0.25, "cream", "Mug")
	-- a crate of apples, apples and a leaf on the grass
	Parts.box(m, f, 0.72, 0.18, 0.72, 0.5, 0.25, 0.5, "wood", "Crate")
	Parts.box(m, f, 0.72, 0.18, 0.76, 0.5, 0.25, 0.25, "wood_dark", "Slat")
	for i, a in { { 0.62, 0.82 }, { 0.82, 0.68 }, { 0.75, 0.88 } } do
		Parts.ball(m, f, a[1], 0.38, a[2], 0.25, if i == 2 then "green" else "berry_red", "Apple")
	end
	Parts.ball(m, f, -0.15, 0.12, 0.82, 0.25, "berry_red", "Apple")
	Parts.ball(m, f, -0.9, 0.12, 0.05, 0.25, "maple", "Apple")
	sway(Parts.turned(m, f, -0.15, 0.02, 0.6, 0.25, 0.25, 0.5, 0.6, "orange", "Leaf"))
end

-- Desert Obelisk (2 x 2): a tall stone needle on three steps and a carved plinth: panels on all four sides of the
-- plinth, a gold sun on its front, a cornice set with teal tiles; the shaft carved down its faces with rows of signs in
-- dark stone, clay and teal, banded where it narrows, a gold point on top that glints; two fire bowls burning at its
-- feet, sand drifted against the steps, a little cactus.
M.obelisk = function(m, f)
	Parts.box(m, f, 0, 0.12, 0, 2, 0.25, 2, "sand_dark", "Step")
	Parts.box(m, f, 0, 0.37, 0, 1.75, 0.25, 1.75, "sand", "Step")
	Parts.box(m, f, 0, 0.62, 0, 1.5, 0.25, 1.5, "sand_dark", "Step")
	-- the plinth and its panels, one on each side
	Parts.box(m, f, 0, 1.12, 0, 1.25, 0.75, 1.25, "sand", "Plinth")
	for _, s in { 1, -1 } do
		Parts.box(m, f, 0, 1.12, s * 0.58, 0.75, 0.5, 0.25, "sand_dark", "Panel")
		Parts.box(m, f, s * 0.58, 1.12, 0, 0.25, 0.5, 0.75, "sand_dark", "Panel")
	end
	disc(m, f, 0, 1.12, 0.72, 0.5, "gold", "Sun")
	Parts.box(m, f, 0.72, 1.12, 0, 0.25, 0.25, 0.25, "teal", "Sign")
	Parts.box(m, f, 0, 1.6, 0, 1.5, 0.25, 1.5, "sand_dark", "Cornice")
	for _, x in { -0.45, 0.45 } do
		Parts.box(m, f, x, 1.6, 0.7, 0.25, 0.25, 0.25, "teal", "Tile")
		Parts.box(m, f, 0.7, 1.6, x, 0.25, 0.25, 0.25, "teal", "Tile")
	end
	-- the shaft, carved down its faces, narrowing near the top
	Parts.box(m, f, 0, 2.6, 0, 0.75, 1.75, 0.75, "sand", "Needle")
	Parts.box(m, f, 0, 3.6, 0, 0.5, 0.5, 0.5, "sand", "Needle")
	Parts.box(m, f, 0, 3.97, 0, 0.5, 0.25, 0.5, "sand", "Needle")
	Parts.box(m, f, 0, 2.0, 0, 1, 0.25, 1, "clay", "Band")
	Parts.box(m, f, 0, 3.4, 0, 0.75, 0.25, 0.75, "clay", "Band")
	for k, y in { 2.4, 2.75, 3.1 } do
		local tone = if k == 2 then "teal" else "sand_dark"
		Parts.box(m, f, 0, y, 0.33, 0.25, 0.25, 0.25, tone, "Sign")
		Parts.box(m, f, 0.33, y, 0, 0.25, 0.25, 0.25, if k == 2 then "clay" else "sand_dark", "Sign")
	end
	Parts.box(m, f, 0, 2.6, -0.33, 0.25, 0.75, 0.25, "sand_dark", "Sign")
	Parts.box(m, f, -0.33, 2.6, 0, 0.25, 0.75, 0.25, "sand_dark", "Sign")
	for _, y in { 3.65, 3.95 } do
		Parts.box(m, f, 0, y, 0.21, 0.25, 0.25, 0.25, "sand_dark", "Sign")
		Parts.box(m, f, 0.21, y, 0, 0.25, 0.25, 0.25, "sand_dark", "Sign")
	end
	cone(m, f, 0, 4.095, 0, 0.5, 0.5, "gold", "Cap")
	Parts.ball(m, f, 0, 4.55, 0, 0.25, "gold", "Sparkle")
	-- fire bowls at its feet
	for _, c in { { 0.72, 0.72 }, { -0.72, 0.72 } } do
		Parts.cyl(m, f, c[1], 0.62, c[2], 0.25, 0.25, "brick", "Stand")
		Parts.cyl(m, f, c[1], 0.8, c[2], 0.5, 0.25, "brick", "Bowl")
		Parts.glow(m, f, c[1], 0.98, c[2], 0.25, 0.25, 0.25, "orange", if c[1] > 0 then "Flame" else "Fire")
	end
	-- sand drifted against the steps, a cactus
	Parts.wedge(m, f, 0.75, 0.3, -0.75, 0.5, 0.25, 0.25, "sand", math.pi / 2, "Drift")
	Parts.wedge(m, f, -0.85, 0.3, -0.1, 0.25, 0.25, 0.5, "sand", 0, "Drift")
	Parts.cyl(m, f, -0.82, 0.62, -0.82, 0.25, 0.5, "green", "Cactus")
	Parts.box(m, f, -0.7, 0.68, -0.82, 0.25, 0.25, 0.25, "leaf_dark", "Cactus")
end

-- A round window or door set in the trunk of the fairy tree house (radius r round its middle) at angle a, facing out:
-- a disc `dia` across and a quarter stud thick.
local function porthole(m: Model, f: CFrame, a: number, y: number, r: number, dia: number, color: string, name: string, neon: boolean?): BasePart
	local p = v(math.sin(a) * r, y, math.cos(a) * r)
	return Blocks.part(m, { size = Vector3.new(0.25, dia, dia), cf = f * CFrame.new(p) * CFrame.Angles(0, a - math.pi / 2, 0), color = color, shape = "Cylinder", name = name, neon = neon, collide = false })
end

-- Fairy Tree House (3 x 3): a fat old trunk with bark down it and roots spreading over a mossy lawn, three little
-- arched doors (one at the foot with a step and stepping stones up to it, two up the trunk with balconies and railings)
-- and round windows lit warm, shelf fungus for steps winding up its side, ivy; a big pink mushroom roof with white
-- spots, a sandy gill under it, an attic window and a stone chimney smoking, fairy lights round its rim, a lantern
-- swinging from the rim; motes of light bobbing round it and twinkling; toadstools and flowers in the moss.
M.fairyhouse = function(m, f)
	Parts.cyl(m, f, 0, 0, 0, 3, 0.25, "moss", "Moss")
	Parts.cyl(m, f, 0.2, 0.01, 0.2, 2.5, 0.25, "grass", "Lawn")
	-- roots
	for k = 0, 4 do
		local a = k * math.pi * 2 / 5 + 0.3
		seg(m, f, v(math.sin(a) * 0.7, 0.4, math.cos(a) * 0.7), v(math.sin(a) * 1.25, 0.08, math.cos(a) * 1.25), 0.5, if k % 2 == 0 then "wood_dark" else "wood", "Root")
	end
	-- the trunk and its bark
	Parts.cyl(m, f, 0, 1.5, 0, 1.75, 3, "wood", "Trunk")
	for i, b in { { -0.1, 0.9 }, { 0.9, 1.9 }, { 1.7, 0.7 }, { 0.5, 2.6 } } do
		local a = b[1]
		Parts.turned(m, f, math.sin(a) * 0.86, b[2], math.cos(a) * 0.86, 0.25, if i % 2 == 0 then 0.75 else 1, 0.25, a, "wood_dark", "Bark")
	end
	-- the door at the foot, its step and stones
	local da = 0.6
	Parts.turned(m, f, math.sin(da) * 0.86, 0.42, math.cos(da) * 0.86, 0.5, 0.75, 0.25, da, "wood_dark", "Door")
	porthole(m, f, da, 0.8, 0.86, 0.5, "wood_dark", "Door")
	Parts.turned(m, f, math.sin(da) * 0.96 + 0.12, 0.42, math.cos(da) * 0.96 - 0.08, 0.25, 0.25, 0.25, da, "gold", "Knob")
	Parts.turned(m, f, math.sin(da) * 1.15, 0.06, math.cos(da) * 1.15, 0.75, 0.25, 0.25, da, "pavement", "Step")
	Parts.cyl(m, f, 0.95, 0.02, 1.25, 0.5, 0.25, "pavement", "Stone")
	Parts.cyl(m, f, 1.3, 0.02, 1.0, 0.25, 0.25, "pavement", "Stone")
	-- two doors up the trunk with balconies and railings
	for _, d in { { a = 1.35, y = 1.55 }, { a = -0.5, y = 2.3 } } do
		local s, c = math.sin(d.a), math.cos(d.a)
		Parts.turned(m, f, s * 0.86, d.y, c * 0.86, 0.5, 0.5, 0.25, d.a, "wood_dark", "Door")
		porthole(m, f, d.a, d.y + 0.25, 0.86, 0.5, "wood_dark", "Door")
		Parts.turned(m, f, s * 1.08, d.y - 0.38, c * 1.08, 0.75, 0.25, 0.5, d.a, "wood_dark", "Balcony")
		Parts.turned(m, f, s * 1.3, d.y - 0.05, c * 1.3, 0.75, 0.25, 0.25, d.a, "wood", "Rail")
		for _, side in { -1, 1 } do
			local p = v(s * 1.3, d.y - 0.2, c * 1.3) + v(c, 0, -s) * (side * 0.3)
			Parts.box(m, f, p.X, p.Y, p.Z, 0.25, 0.5, 0.25, "wood", "Rail")
		end
	end
	-- round windows lit warm
	for _, w in { { a = -0.2, y = 1.15 }, { a = 0.45, y = 2.4 }, { a = 1.75, y = 0.95 } } do
		porthole(m, f, w.a, w.y, 0.86, 0.75, "wood_dark", "Frame")
		porthole(m, f, w.a, w.y, 0.94, 0.5, "yellow", "Window", true)
	end
	-- shelf fungus for steps, winding up its side
	for k = 0, 7 do
		local a = k * 0.8 + 2.5
		Parts.turned(m, f, math.sin(a) * 1.0, 0.25 + k * 0.33, math.cos(a) * 1.0, 0.5, 0.25, 0.25, a, if k % 2 == 0 then "cream" else "sand", "Step")
	end
	-- ivy
	for _, l in { { 0.15, 0.55 }, { 1.0, 1.25 }, { -0.35, 1.7 }, { 1.1, 2.6 } } do
		sway(Parts.turned(m, f, math.sin(l[1]) * 0.92, l[2], math.cos(l[1]) * 0.92, 0.25, 0.25, 0.25, l[1], "leaf", "Ivy"))
	end
	-- the mushroom roof
	Parts.cyl(m, f, 0, 2.95, 0, 2.25, 0.25, "sand", "Gill")
	Parts.cyl(m, f, 0, 3.1, 0, 2.75, 0.25, "pink", "Roof")
	local dome = v(0, 3.15, 0)
	Parts.ball(m, f, dome.X, dome.Y, dome.Z, 2.25, "pink", "Roof")
	for _, d in { v(0.5, 0.4, 0.75), v(0.9, 0.5, -0.1), v(-0.4, 0.5, 0.8), v(0.2, 0.95, 0.25), v(-0.8, 0.6, 0.1), v(0.55, 0.75, -0.6) } do
		local p = dome + d.Unit * 1.0
		Parts.ball(m, f, p.X, p.Y, p.Z, 0.5, "white", "Spot")
	end
	local wdir = v(0.75, 0.35, 0.55).Unit
	local wp = dome + wdir * 1.08
	Blocks.part(m, { size = Vector3.new(0.25, 0.5, 0.5), cf = f * CFrame.lookAt(wp, wp + wdir) * CFrame.Angles(0, math.pi / 2, 0), color = "yellow", shape = "Cylinder", name = "Window", neon = true, collide = false })
	Parts.cyl(m, f, -0.4, 4.0, -0.4, 0.5, 0.5, "rock", "Stack")
	Parts.cyl(m, f, -0.4, 4.3, -0.4, 0.5, 0.25, "rock_dark", "Chimney")
	-- fairy lights round the rim
	for k, deg in { -40, 0, 40, 80, 120 } do
		local a = math.rad(deg)
		Parts.ball(m, f, math.sin(a) * 1.3, 2.95, math.cos(a) * 1.3, 0.25, if k % 3 == 0 then "pink" elseif k % 3 == 1 then "yellow" else "crystal", "FairyLight", true)
	end
	-- the lantern swinging from the rim
	local la = 1.0
	local hook = v(math.sin(la) * 1.15, 2.95, math.cos(la) * 1.15)
	swing(Parts.box(m, f, hook.X, 2.82, hook.Z, 0.25, 0.25, 0.25, "wood_dark", "Chain"), hook, "X", 1.4, 0.2)
	swing(Parts.box(m, f, hook.X, 2.6, hook.Z, 0.25, 0.25, 0.25, "gold", "LampCap"), hook, "X", 1.4, 0.2)
	swing(Parts.glow(m, f, hook.X, 2.38, hook.Z, 0.25, 0.25, 0.25, "yellow", "Lamp"), hook, "X", 1.4, 0.2)
	swing(Parts.box(m, f, hook.X, 2.16, hook.Z, 0.25, 0.25, 0.25, "gold", "LampCap"), hook, "X", 1.4, 0.2)
	-- motes of light bobbing round it
	local tints = { "pink", "crystal", "cream" }
	for i, l in { v(-1.15, 1.8, 0.65), v(1.25, 1.45, -0.45), v(0.3, 0.9, 1.3) } do
		local p = Parts.glow(m, f, l.X, l.Y, l.Z, 0.25, 0.25, 0.25, tints[i], "Sparkle")
		Parts.move(p, "bob", l, "Y", 1.1 + i * 0.2, 0.12, i * 1.9)
	end
	-- toadstools and flowers in the moss
	toadstool(m, f, -1.1, 0.85, 1, "berry_red", false)
	toadstool(m, f, 1.15, -0.95, 1, "crystal", true)
	for i, b in { { -0.55, 1.25 }, { 1.3, 0.35 }, { -1.3, -0.3 }, { 0.15, 1.38 } } do
		Parts.box(m, f, b[1], 0.15, b[2], 0.25, 0.25, 0.25, if i % 2 == 0 then "cream" else "pink", "Bloom")
	end
end

-- Tea Pavilion (4 x 4): an open pavilion on a stone base in a bed of pale gravel, stone steps up to it: a dark wooden
-- floor laid with four straw mats, dark posts with red rails along the sides, a paper screen at the back crossed by
-- dark bars, red beams round the top, a sweeping slate roof with rows of tiles, a red fascia, a dark ridge with horns
-- at its ends and turned-up corners; inside a low table with two cups and a tea caddy, cushions, a kettle steaming on a
-- small brazier; two paper lanterns swinging from the front beam; a stone lantern by the steps, a little red maple and
-- a mossy stone in the gravel, stepping stones.
M.teahouse = function(m, f)
	local cz = -0.25
	Parts.box(m, f, 0, 0, 0, 4, 0.25, 4, "pavement", "Gravel")
	Parts.box(m, f, 0, 0.3, cz, 3.5, 0.5, 3.25, "rock", "Base")
	Parts.box(m, f, 0, 0.5, cz + 1.55, 3.5, 0.25, 0.25, "rock_dark", "Trim")
	Parts.box(m, f, 0, 0.675, cz, 3.25, 0.25, 3, "wood_dark", "Floor")
	for _, x in { -0.7, 0.7 } do
		for _, z in { -0.65, 0.65 } do
			Parts.box(m, f, x, 0.7, cz + z, 1.25, 0.25, 1.25, "straw", "Mats")
		end
	end
	-- the steps up the front
	Parts.box(m, f, 0, 0.12, 1.72, 1.25, 0.25, 0.5, "rock", "Step")
	Parts.box(m, f, 0, 0.37, 1.45, 1.25, 0.25, 0.5, "rock_dark", "Step")
	-- posts, rails along the sides, the screen at the back
	for _, x in { -1.5, 1.5 } do
		for _, z in { -1.65, 1.15 } do
			Parts.box(m, f, x, 1.75, z, 0.25, 2, 0.25, "wood_dark", "Post")
		end
		Parts.box(m, f, x, 1.25, cz, 0.25, 0.25, 2.75, "berry_red", "Rail")
		for _, z in { -0.85, 0.35 } do
			Parts.box(m, f, x, 1.0, z, 0.25, 0.25, 0.25, "berry_red", "Baluster")
		end
	end
	Parts.box(m, f, 0, 1.75, -1.65, 3, 1.75, 0.25, "paper", "Screen")
	for _, x in { -0.75, 0, 0.75 } do
		Parts.box(m, f, x, 1.75, -1.55, 0.25, 1.75, 0.25, "wood_dark", "Bar")
	end
	Parts.box(m, f, 0, 1.75, -1.53, 3, 0.25, 0.25, "wood_dark", "Bar")
	-- the beams round the top
	Parts.box(m, f, 0, 2.75, 1.15, 3.25, 0.25, 0.25, "berry_red", "Beam")
	Parts.box(m, f, 0, 2.75, -1.65, 3.25, 0.25, 0.25, "berry_red", "Beam")
	for _, x in { -1.5, 1.5 } do
		Parts.box(m, f, x, 2.75, cz, 0.25, 0.25, 3, "berry_red", "Beam")
	end
	-- the roof: two slopes, rows of tiles, the fascia, the ridge with its horns, the turned-up corners
	wedgeAt(m, f, CFrame.new(0, 3.05, -1.075), 4, 0.75, 1.75, "slate", "Roof")
	wedgeAt(m, f, CFrame.new(0, 3.05, 0.675) * CFrame.Angles(0, math.pi, 0), 4, 0.75, 1.75, "slate", "Roof")
	local th = math.atan(0.75 / 1.75)
	for _, t in { 0.3, 0.55, 0.8 } do
		local z, y = -0.2 + 1.75 * t, 3.425 - 0.75 * t
		Parts.at(m, f, CFrame.new(0, y + 0.08 * math.cos(th), z + 0.08 * math.sin(th)) * CFrame.Angles(th, 0, 0), 3.75, 0.25, 0.25, "steel_dark", "Tiles")
	end
	Parts.box(m, f, 0, 2.6, 1.45, 4, 0.25, 0.25, "berry_red", "Fascia")
	Parts.log(m, f, 0, 3.45, -0.2, 3.75, 0.25, "rock_dark", "Ridge")
	for _, x in { -1.85, 1.85 } do
		Parts.box(m, f, x, 3.62, -0.2, 0.25, 0.5, 0.25, "rock_dark", "Horn")
		Parts.box(m, f, x, 2.82, 1.5, 0.25, 0.25, 0.25, "slate", "Tip")
		Parts.box(m, f, x, 2.82, -1.9, 0.25, 0.25, 0.25, "slate", "Tip")
	end
	-- inside: the low table and its cups, cushions, the kettle on its brazier
	Parts.box(m, f, 0, 1.08, -0.35, 1.25, 0.25, 0.75, "wood", "Table")
	for _, x in { -0.45, 0.45 } do
		Parts.box(m, f, x, 0.9, -0.35, 0.25, 0.25, 0.5, "wood_dark", "Leg")
	end
	Parts.cyl(m, f, -0.3, 1.3, -0.25, 0.25, 0.25, "white", "Cup")
	Parts.cyl(m, f, 0.2, 1.3, -0.15, 0.25, 0.25, "white", "Cup")
	Parts.box(m, f, -0.05, 1.3, -0.55, 0.25, 0.25, 0.25, "berry_red", "Caddy")
	Parts.box(m, f, -0.95, 0.88, -0.35, 0.75, 0.25, 0.75, "purple", "Cushion")
	Parts.box(m, f, 0.05, 0.88, 0.45, 0.75, 0.25, 0.75, "teal", "Cushion")
	Parts.cyl(m, f, 1.0, 0.95, -0.6, 0.5, 0.25, "black", "Brazier")
	Parts.glow(m, f, 1.0, 1.02, -0.6, 0.25, 0.25, 0.25, "lava", "Coal")
	Parts.ball(m, f, 1.0, 1.3, -0.6, 0.5, "steel_dark", "Teapot")
	Parts.box(m, f, 1.0, 1.55, -0.6, 0.25, 0.25, 0.25, "black", "Lid")
	seg(m, f, v(1.18, 1.3, -0.45), v(1.32, 1.45, -0.3), 0.25, "steel_dark", "Spout")
	-- paper lanterns swinging from the front beam
	for k, x in { -0.9, 0.9 } do
		local hook = v(x, 2.62, 1.15)
		local ph = k * 1.5
		swing(Parts.box(m, f, x, 2.5, 1.15, 0.25, 0.25, 0.25, "wood_dark", "Cord"), hook, "X", 1.4, 0.15, ph)
		swing(Parts.cyl(m, f, x, 2.35, 1.15, 0.25, 0.25, "berry_red", "LanternCap"), hook, "X", 1.4, 0.15, ph)
		swing(Parts.cyl(m, f, x, 2.1, 1.15, 0.5, 0.5, "cream", "Lantern", true), hook, "X", 1.4, 0.15, ph)
		swing(Parts.cyl(m, f, x, 1.82, 1.15, 0.25, 0.25, "berry_red", "LanternCap"), hook, "X", 1.4, 0.15, ph)
	end
	-- a stone lantern by the steps
	Parts.box(m, f, 1.55, 0.12, 1.6, 0.5, 0.25, 0.5, "rock_dark", "LanternBase")
	Parts.cyl(m, f, 1.55, 0.45, 1.6, 0.25, 0.5, "rock", "LanternPost")
	Parts.glow(m, f, 1.55, 0.8, 1.6, 0.25, 0.25, 0.25, "yellow", "Light")
	Parts.box(m, f, 1.55, 1.0, 1.6, 0.5, 0.25, 0.5, "rock", "LanternRoof")
	Parts.ball(m, f, 1.55, 1.2, 1.6, 0.25, "rock", "Knob")
	-- a little red maple, a mossy stone, stepping stones
	seg(m, f, v(-1.55, 0.05, 1.55), v(-1.5, 0.75, 1.5), 0.25, "wood_dark", "Trunk")
	Parts.ball(m, f, -1.45, 1.0, 1.45, 1, "maple", "Leaves")
	Parts.ball(m, f, -1.3, 1.25, 1.6, 0.5, "orange", "Leaves")
	Parts.ball(m, f, 1.65, 0.1, -1.7, 0.5, "rock", "Stone")
	Parts.box(m, f, 1.65, 0.3, -1.7, 0.25, 0.25, 0.25, "moss", "Moss")
	Parts.cyl(m, f, 0.75, 0.04, 1.72, 0.5, 0.25, "rock", "Stone")
	Parts.cyl(m, f, -0.75, 0.04, 1.75, 0.25, 0.25, "rock", "Stone")
end

-- Ember Forge (3 x 3): a hearth of basalt laid in courses with a bed of fire burning on it under a stone hood and a
-- chimney smoking, an ash pit glowing in its front; bellows at its side whose top board rises and falls; an anvil on a
-- stump with a bar glowing on its face and a hammer by it; beside it a pool of fire in a ring of stone with bubbles
-- rising and sinking and tongs dropped by it; a rack of tools at the back, a barrel of water, a heap of coal,
-- flagstones in the floor, sparks.
M.emberforge = function(m, f)
	Parts.box(m, f, 0, 0.02, 0, 3, 0.25, 3, "basalt", "Floor")
	for _, s in { { -0.3, 0.9, 0.2 }, { 0.6, -0.15, -0.3 }, { -1.05, 0.15, 0.5 } } do
		Parts.turned(m, f, s[1], 0.04, s[2], 0.5, 0.25, 0.5, s[3], "rock_dark", "Flagstone")
	end
	-- the hearth, its fire, the ash pit
	local hx, hz = -0.75, -0.85
	Parts.box(m, f, hx, 0.5, hz, 1.5, 1, 1.25, "basalt", "Hearth")
	Parts.box(m, f, hx, 1.12, hz, 1.5, 0.25, 1.25, "rock_dark", "Hearth")
	for i, b in { { -1.2, 0.75 }, { -0.4, 0.75 }, { -0.8, 0.3 } } do
		Parts.box(m, f, b[1], b[2], hz + 0.6, 0.5, 0.25, 0.25, if i == 3 then "rock_dark" else "rock", "Course")
	end
	Parts.box(m, f, -1.25, 0.3, hz + 0.6, 0.5, 0.25, 0.25, "black", "AshPit")
	Parts.glow(m, f, -1.25, 0.3, hz + 0.65, 0.25, 0.25, 0.25, "lava", "Ash")
	Parts.glow(m, f, hx, 1.2, hz + 0.1, 1, 0.25, 0.75, "lava", "Fire")
	Parts.ball(m, f, hx - 0.3, 1.32, hz + 0.25, 0.25, "black", "Coal")
	Parts.ball(m, f, hx + 0.3, 1.3, hz - 0.1, 0.25, "black", "Coal")
	Parts.glow(m, f, hx - 0.1, 1.5, hz + 0.15, 0.25, 0.5, 0.25, "orange", "Flame")
	Parts.glow(m, f, hx + 0.2, 1.42, hz + 0.05, 0.25, 0.25, 0.25, "yellow", "Fire")
	Parts.glow(m, f, hx - 0.05, 1.85, hz + 0.1, 0.25, 0.25, 0.25, "yellow", "Spark")
	-- the hood over it on two posts, the chimney
	for _, x in { -1.35, -0.15 } do
		Parts.box(m, f, x, 1.62, -0.35, 0.25, 0.75, 0.25, "basalt", "HoodPost")
	end
	Parts.box(m, f, hx, 2.12, -0.35, 1.5, 0.25, 0.25, "rock", "Lintel")
	Parts.box(m, f, hx, 2.4, hz - 0.1, 1.25, 0.75, 0.75, "rock_dark", "Hood")
	Parts.box(m, f, hx, 3.25, hz - 0.1, 0.75, 1, 0.75, "basalt", "Chimney")
	Parts.box(m, f, hx, 3.1, hz - 0.1, 1, 0.25, 1, "rock_dark", "Band")
	Parts.box(m, f, hx, 3.85, hz - 0.1, 1, 0.25, 1, "rock_dark", "Cap")
	Parts.box(m, f, hx, 4.0, hz - 0.1, 0.5, 0.25, 0.5, "black", "Smoke")
	-- the bellows at its side, the top board rising and falling
	Parts.box(m, f, 0.45, 0.25, -0.9, 0.25, 0.5, 0.25, "wood_dark", "Stand")
	Parts.box(m, f, 0.45, 0.6, -0.9, 0.75, 0.25, 0.5, "wood_dark", "Bellows")
	Parts.box(m, f, 0.5, 0.75, -0.9, 0.5, 0.25, 0.5, "brick", "Leather")
	seg(m, f, v(0.12, 0.62, -0.9), v(-0.08, 0.75, -0.9), 0.25, "steel_dark", "Nozzle")
	local hinge = v(0.12, 0.85, -0.9)
	swing(Parts.box(m, f, 0.45, 0.92, -0.9, 0.75, 0.25, 0.5, "wood", "Bellows"), hinge, "Z", 1.6, 0.12)
	swing(Parts.box(m, f, 0.9, 0.92, -0.9, 0.25, 0.25, 0.25, "wood_dark", "Handle"), hinge, "Z", 1.6, 0.12)
	-- the anvil on its stump, a hot bar on it, the hammer
	Parts.cyl(m, f, 0.25, 0.25, 0.25, 0.75, 0.5, "wood_dark", "Stump")
	Parts.cyl(m, f, 0.25, 0.42, 0.25, 0.5, 0.25, "wood", "Rings")
	Parts.box(m, f, 0.25, 0.62, 0.25, 0.5, 0.25, 0.5, "steel_dark", "Anvil")
	Parts.box(m, f, 0.25, 0.8, 0.25, 0.25, 0.25, 0.25, "steel_dark", "Anvil")
	Parts.box(m, f, 0.25, 1.0, 0.25, 1, 0.25, 0.5, "steel", "Anvil")
	wedgeAt(m, f, CFrame.new(0.95, 1.0, 0.25) * CFrame.Angles(0, -math.pi / 2, 0), 0.5, 0.25, 0.5, "steel", "Horn")
	Parts.glow(m, f, 0.2, 1.17, 0.3, 0.5, 0.25, 0.25, "orange", "HotBar")
	seg(m, f, v(-0.25, 0.75, 0.55), v(-0.05, 0.5, 0.75), 0.25, "wood", "Hammer")
	Parts.turned(m, f, -0.28, 0.8, 0.52, 0.5, 0.25, 0.25, VIEW, "black", "HammerHead")
	-- the pool of fire in its ring of stone
	local px, pz = 0.95, 0.95
	Parts.cyl(m, f, px, 0.14, pz, 1, 0.25, "rock_dark", "Ring")
	Parts.cyl(m, f, px, 0.2, pz, 0.75, 0.25, "lava", "Lava", true)
	Parts.glow(m, f, px - 0.1, 0.24, pz + 0.05, 0.25, 0.25, 0.25, "yellow", "Lava")
	for i, b in { { 0.18, -0.12 }, { -0.15, 0.2 } } do
		local p = Parts.ball(m, f, px + b[1], 0.28, pz + b[2], 0.25, "orange", "Bubble", true)
		Parts.move(p, "bob", v(px + b[1], 0.28, pz + b[2]), "Y", 1.5 + i * 0.3, 0.05, i * 2.2)
	end
	for _, s in { { 0.55, 0.62 }, { 1.35, 0.6 }, { 0.62, 1.35 } } do
		Parts.ball(m, f, s[1], 0.15, s[2], 0.25, "basalt", "Stone")
	end
	seg(m, f, v(-0.15, 0.08, 1.25), v(0.35, 0.08, 1.38), 0.25, "black", "Tongs")
	-- a rack of tools at the back
	for _, x in { 0.75, 1.35 } do
		Parts.box(m, f, x, 0.75, -1.35, 0.25, 1.5, 0.25, "wood_dark", "Rack")
	end
	Parts.box(m, f, 1.05, 1.4, -1.35, 0.75, 0.25, 0.25, "wood", "Rack")
	Parts.box(m, f, 0.92, 1.05, -1.25, 0.25, 0.5, 0.25, "black", "Tongs")
	Parts.box(m, f, 1.18, 1.1, -1.25, 0.25, 0.5, 0.25, "wood", "Hammer")
	Parts.box(m, f, 1.18, 0.82, -1.25, 0.25, 0.25, 0.25, "steel_dark", "HammerHead")
	-- a barrel of water, a heap of coal
	Parts.cyl(m, f, 1.1, 0.375, -0.4, 0.5, 0.75, "wood", "Barrel")
	for _, y in { 0.2, 0.6 } do
		Parts.cyl(m, f, 1.1, y, -0.4, 0.75, 0.25, "steel_dark", "Hoop")
	end
	pool(m, f, 1.1, 0.68, -0.4, 0.25)
	for i, c in { { -1.15, 0.55, 0.5 }, { -0.85, 0.75, 0.25 }, { -1.3, 0.85, 0.25 }, { -0.95, 0.45, 0.25 } } do
		Parts.ball(m, f, c[1], 0.12 + (if i == 1 then 0.05 else 0), c[2], c[3], if i % 2 == 0 then "basalt" else "black", "Coal")
	end
	Parts.glow(m, f, -0.2, 2.3, -0.4, 0.25, 0.25, 0.25, "yellow", "Spark")
end

return M
