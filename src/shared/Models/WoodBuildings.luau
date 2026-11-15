--!strict
-- The island's wood buildings (kind "wood"), from parts (GAME_DESIGN 4; Data/Buildings). Each builder takes the model,
-- the frame at the footprint's centre on the grass (facing +Z before the piece's turn) and the level, and stays inside
-- the footprint. The pieces they share are Models/BuildKit's; the ones only these need (logs showing their sawn ends,
-- stacks of drying boards, shingled gable roofs, plank doors, windows with flower boxes, lanterns, a flume's chute,
-- pines) are below. Models/DecorModels registers them.
-- (Split out of Models/DecorModels on 2026-11-15 for the request "could you rework and detail every building even
-- more? look at the bakery game for reference.", then each one rebuilt with the care of Random Bakery's garden pieces:
-- trims, frames, sills, signs and lanterns, and the tools of its trade lying about.)
-- The view looks from the south-east, so the fronts (+Z), the east sides (+X) and the roofs carry the detail. The
-- back-left corner stays low for the upgrade pennant (levels 2 and 3), the front-right corner clear for the lantern a
-- level 3 building gets.
local Blocks = require(script.Parent.Blocks)
local K = require(script.Parent.BuildKit)
local box = K.box
local ball = K.ball
local cyl = K.cyl
local log = K.log
local wedge = K.wedge
local span = K.span
local tube = K.tube

type Builder = (m: Model, f: CFrame, lvl: number?) -> ()
type Shape = "Block" | "Wedge" | "CornerWedge" | "Cylinder" | "Ball"
local B: { [string]: Builder } = {}

local ACROSS = CFrame.Angles(0, math.pi / 2, 0) -- a part's X axis turned to run along Z

------------------------------------------------------------------ helpers
-- Any part at `cf` in f's frame.
local function put(m: Instance, f: CFrame, cf: CFrame, w: number, h: number, d: number, color: string, name: string?, shape: Shape?, neon: boolean?): BasePart
	return Blocks.part(m, { size = Vector3.new(w, h, d), cf = f * cf, color = color, name = name, shape = shape, neon = neon, collide = false })
end

-- An upright post, a quarter stud square, from y0 up h.
local function post(m: Instance, f: CFrame, x: number, y0: number, z: number, h: number, color: string?, name: string?): BasePart
	return box(m, f, x, y0 + h / 2, z, 0.25, h, 0.25, color or "wood_dark", name or "Post")
end

-- A disc facing the front (+Z), a quarter stud thick: a saw blade, a wheel.
local function discZ(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string?): BasePart
	return put(m, f, CFrame.new(x, y, z) * ACROSS, 0.25, dia, dia, color, name, "Cylinder")
end

-- A disc facing east (+X).
local function discX(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, color: string, name: string?): BasePart
	return log(m, f, x, y, z, 0.25, dia, color, name)
end

-- A log lying along X with its sawn end to the east: a pale face a hair proud of the bark and, on a log 0.75 or more
-- across, the heartwood in its middle.
local function logX(m: Instance, f: CFrame, x: number, y: number, z: number, len: number, dia: number, bark: string?, face: string?, heart: string?)
	log(m, f, x, y, z, len, dia, bark or "wood", "Log")
	local e = x + len / 2 - 0.125
	log(m, f, e + 0.03, y, z, 0.25, dia - 0.25, face or "desk", "LogEnd")
	if dia >= 0.75 then
		log(m, f, e + 0.06, y, z, 0.25, dia - 0.5, heart or bark or "wood", "LogHeart")
	end
end

-- The same lying along Z, its end to the front.
local function logZ(m: Instance, f: CFrame, x: number, y: number, z: number, len: number, dia: number, bark: string?, face: string?, heart: string?)
	put(m, f, CFrame.new(x, y, z) * ACROSS, len, dia, dia, bark or "wood", "Log", "Cylinder")
	local e = z + len / 2 - 0.125
	put(m, f, CFrame.new(x, y, e + 0.03) * ACROSS, 0.25, dia - 0.25, dia - 0.25, face or "desk", "LogEnd", "Cylinder")
	if dia >= 0.75 then
		put(m, f, CFrame.new(x, y, e + 0.06) * ACROSS, 0.25, dia - 0.5, dia - 0.5, heart or bark or "wood", "LogHeart", "Cylinder")
	end
end

-- A gable roof along X over walls w x d (centred on cx, cz, their top at y), its ridge h above them: the gable ends in
-- `gable`, two roof boards of `color` lapping past the walls by ox at the ends and oz at the eaves, rows of shingles in
-- `lines` across the front slope (the one the camera sees), a cap along the ridge and dark barge boards up the east
-- end.
local function gableRoof(m: Instance, f: CFrame, cx: number, cz: number, y: number, w: number, d: number, h: number, color: string, lines: string, gable: string, ox: number, oz: number)
	wedge(m, f, cx, y + h / 2, cz - d / 4, w, h, d / 2, gable, 0, "Gable")
	wedge(m, f, cx, y + h / 2, cz + d / 4, w, h, d / 2, gable, math.pi, "Gable")
	local hd = d / 2
	local s = math.sqrt(hd * hd + h * h)
	local ridge = Vector3.new(cx, y + h, cz)
	local len = s + oz + 0.125
	local W = w + ox * 2
	for _, side in { 1, -1 } do
		local u = Vector3.new(0, -h, side * hd) / s -- down the slope
		local n = Vector3.new(0, hd, side * h) / s -- out of it
		local c = ridge + u * (len / 2 - 0.125) + n * 0.125
		put(m, f, CFrame.lookAt(c, c + u), W, 0.25, len, color, "Roof")
		if side == 1 then
			local t = s + oz - 0.375
			while t > 0.3 do
				local p = ridge + u * t + n * 0.165
				put(m, f, CFrame.lookAt(p, p + u), W - 0.25, 0.25, 0.25, lines, "Shingles")
				t -= 0.5
			end
		end
		local bc = ridge + u * ((s + oz) / 2) - n * 0.125 + Vector3.new(w / 2 + ox - 0.125, 0, 0)
		put(m, f, CFrame.lookAt(bc, bc + u), 0.25, 0.25, s + oz, "wood_dark", "Barge")
	end
	box(m, f, cx, y + h + 0.25 * s / hd - 0.06, cz, W + 0.25, 0.25, 0.5, lines, "RidgeCap")
end

-- A plank door in a front (+Z) wall whose face is at z, its foot at y0: a dark frame, the door a hair proud of it,
-- ledges across a wide one, a gold handle.
local function plankDoor(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, h: number, color: string)
	box(m, f, x, y0 + (h + 0.125) / 2, z + 0.0625, w + 0.25, h + 0.125, 0.25, "wood_dark", "DoorFrame")
	box(m, f, x, y0 + h / 2, z + 0.125, w, h, 0.25, color, "Door")
	if w >= 0.75 then
		for _, t in { 0.25, 0.75 } do
			box(m, f, x, y0 + h * t, z + 0.16, w - 0.25, 0.25, 0.25, "wood_dark", "Ledge")
		end
	end
	box(m, f, x + w / 2 - 0.1875, y0 + h * 0.5, z + 0.2, 0.25, 0.25, 0.25, "gold", "Handle")
end

-- A window in a front wall whose face is at z: a dark frame, the glass, a cross of bars on a wide one, a sill, and
-- shutters and a box of flowers when asked for.
local function frontWindow(m: Instance, f: CFrame, x: number, y: number, z: number, w: number, h: number, shutters: string?, flowers: { string }?)
	box(m, f, x, y, z + 0.0625, w + 0.25, h + 0.25, 0.25, "wood_dark", "WindowFrame")
	box(m, f, x, y, z + 0.1, w, h, 0.25, "window", "Glass")
	if w >= 0.75 then
		box(m, f, x, y, z + 0.14, 0.25, h, 0.25, "wood_dark", "Bar")
		box(m, f, x, y, z + 0.14, w, 0.25, 0.25, "wood_dark", "Bar")
	end
	box(m, f, x, y - h / 2 - 0.125, z + 0.1875, w + 0.5, 0.25, 0.25, "wood_dark", "Sill")
	if shutters then
		for _, s in { -1, 1 } do
			box(m, f, x + s * (w / 2 + 0.25), y, z + 0.0625, 0.25, h + 0.25, 0.25, shutters, "Shutter")
		end
	end
	if flowers then
		box(m, f, x, y - h / 2 - 0.0625, z + 0.375, w + 0.25, 0.25, 0.25, "wood", "FlowerBox")
		local n = math.floor((w + 0.25) / 0.25 + 0.5)
		for i = 1, n do
			local c = if i % 2 == 0 then "leaf" else flowers[(i // 2) % #flowers + 1]
			box(m, f, x - (w + 0.25) / 2 + (i - 0.5) * 0.25, y - h / 2 + 0.1875, z + 0.375, 0.25, 0.25, 0.25, c, "Flower")
		end
	end
end

-- A lantern hung from an iron bracket that reaches (dx, dz) out from (x, y, z) (whole quarter studs): a cap and the
-- lit box under the bracket's end.
local function lantern(m: Instance, f: CFrame, x: number, y: number, z: number, dx: number, dz: number)
	box(m, f, x + dx / 2, y, z + dz / 2, math.abs(dx) + 0.25, 0.25, math.abs(dz) + 0.25, "steel_dark", "LanternArm")
	box(m, f, x + dx, y - 0.25, z + dz, 0.25, 0.25, 0.25, "steel_dark", "LanternCap")
	box(m, f, x + dx, y - 0.5, z + dz, 0.25, 0.25, 0.25, "yellow", "Lantern", true)
end

-- Sawn boards stacked to dry: `layers` layers of boards half a stud wide (the tones in turn, so each board shows) with
-- sticks laid across between the layers, every other layer a little shorter; the boards along X (ends to the east)
-- or along Z (ends to the front). (x, z) is its middle, y0 its foot, `deep` how wide a layer is, `sticker` the sticks'
-- colour (dark by default).
local function boardStack(m: Instance, f: CFrame, x: number, y0: number, z: number, len: number, deep: number, layers: number, alongX: boolean, tones: { string }, sticker: string?)
	local nb = math.max(1, math.floor(deep / 0.5 + 0.5))
	for i = 0, layers - 1 do
		local y = y0 + i * 0.5 + 0.125
		local l = len - (i % 2) * 0.25
		local back = (i % 2) * 0.125
		for j = 0, nb - 1 do
			local o = -deep / 2 + 0.25 + j * 0.5
			local c = tones[(i + j) % #tones + 1]
			if alongX then
				box(m, f, x - back, y, z + o, l, 0.25, 0.5, c, "Board")
			else
				box(m, f, x + o, y, z - back, 0.5, 0.25, l, c, "Board")
			end
		end
		if i < layers - 1 then
			for _, s in { -1, 1 } do
				local a = s * (len / 2 - 0.25)
				if alongX then
					box(m, f, x + a, y + 0.25, z, 0.25, 0.25, deep, sticker or "wood_dark", "Sticker")
				else
					box(m, f, x, y + 0.25, z + a, deep, 0.25, 0.25, sticker or "wood_dark", "Sticker")
				end
			end
		end
	end
end

-- A four-sided cone w x w, h tall, its foot's middle at (x, y0, z): four corner wedges pointing to the middle.
local QUARTERS = { { -1, 1, 0 }, { 1, 1, math.pi / 2 }, { 1, -1, math.pi }, { -1, -1, -math.pi / 2 } }
local function cone(m: Instance, f: CFrame, x: number, y0: number, z: number, w: number, h: number, color: string, name: string?)
	local q = w / 2
	for _, s in QUARTERS do
		put(m, f, CFrame.new(x + s[1] * q / 2, y0 + h / 2, z + s[2] * q / 2) * CFrame.Angles(0, s[3], 0), q, h, q, color, name or "Cone", "CornerWedge")
	end
end

-- A pine at (x, z) standing on y0: a short trunk under stacked cones of `widths` (whole half studs), the bottom first.
local function pine(m: Instance, f: CFrame, x: number, y0: number, z: number, widths: { number })
	cyl(m, f, x, y0 + 0.25, z, 0.25, 0.5, "wood_dark", "Trunk")
	for k, w in widths do
		cone(m, f, x, y0 + 0.375 + (k - 1) * 0.5, z, w, 0.75, if k % 2 == 1 then "leaf_dark" else "leaf", "Needles")
	end
end

-- A round saw blade standing in a bench, facing the front: the disc, its hub and a few teeth on its upper rim (angles
-- in radians from the east).
local function sawBlade(m: Instance, f: CFrame, x: number, y: number, z: number, dia: number, teeth: { number })
	discZ(m, f, x, y, z, dia, "steel", "Blade")
	discZ(m, f, x, y, z + 0.06, 0.25, "steel_dark", "Hub")
	for _, a in teeth do
		put(m, f, CFrame.new(x + math.cos(a) * dia / 2, y + math.sin(a) * dia / 2, z) * CFrame.Angles(0, 0, a + math.pi / 4), 0.25, 0.25, 0.25, "steel", "Tooth")
	end
end

------------------------------------------------------------------ the buildings
-- Lumber Camp (4 x 3): a clearing of trodden earth with a paler patch of chips. At the back a canvas tent with its door
-- open and two pegs, and a pile of logs held by two stakes with their sawn ends to the east, a lantern hung out from a
-- stake. In front a saw horse with a log half cut by an orange bow saw and sawdust under it, a bucket, a chopping stump
-- with an axe in it and split wood round it, and a stack of firewood with its ends to the front.
B.lumber = function(m, f)
	box(m, f, 0, 0, 0, 3.5, 0.25, 2.5, "sand_dark", "Clearing")
	box(m, f, 0.5, 0.03, 0.75, 1.5, 0.25, 1.0, "sand", "Chips")
	for _, c in { { -0.125, 0.5, 0.5 }, { -0.5, 1.25, 1.1 }, { 1.0, 1.25, 0.3 }, { 0.375, 0.25, 0.9 }, { -1.625, 1.25, 0.2 } } do
		put(m, f, CFrame.new(c[1], 0.0625, c[2]) * CFrame.Angles(0, c[3], 0), 0.25, 0.25, 0.25, "desk", "Chip")
	end
	-- the tent, its ridge pole, open door and pegs
	wedge(m, f, -1.0, 0.75, -0.75, 1.25, 1.25, 0.5, "cream", math.pi / 2, "Tent")
	wedge(m, f, -0.5, 0.75, -0.75, 1.25, 1.25, 0.5, "cream", -math.pi / 2, "Tent")
	box(m, f, -0.75, 1.375, -0.75, 0.25, 0.25, 1.5, "wood_dark", "RidgePole")
	wedge(m, f, -0.875, 0.5, -0.21, 0.25, 0.75, 0.25, "black", math.pi / 2, "TentDoor")
	wedge(m, f, -0.625, 0.5, -0.21, 0.25, 0.75, 0.25, "black", -math.pi / 2, "TentDoor")
	for _, z in { -1.25, -0.25 } do
		box(m, f, -1.375, 0.1875, z, 0.25, 0.25, 0.25, "wood_dark", "Peg")
	end
	-- the log pile, its stakes and the lantern
	local pile = { { 1.0, 0.375, -1.25, 1.75 }, { 1.0, 0.375, -0.75, 1.75 }, { 0.875, 0.375, -0.25, 1.5 }, { 1.0, 0.8125, -1.0, 1.75 }, { 0.875, 0.8125, -0.5, 1.5 }, { 0.875, 1.25, -0.75, 1.5 } }
	for k, l in pile do
		logX(m, f, l[1], l[2], l[3], l[4], 0.5, if k % 2 == 0 then "wood_dark" else "wood")
	end
	for _, z in { -1.375, -0.125 } do
		post(m, f, -0.125, 0, z, 1.5, "wood_dark", "Stake")
	end
	lantern(m, f, -0.125, 1.625, -0.125, 0.5, 0)
	-- the saw horse, a log on it and the bow saw in the cut, facing the front
	for _, z in { 0.375, 1.125 } do
		for _, t in { -0.4, 0.4 } do
			put(m, f, CFrame.new(-1.0, 0.5625, z) * CFrame.Angles(0, 0, t), 0.25, 1.0, 0.25, "wood_dark", "Leg")
		end
	end
	logZ(m, f, -1.0, 1.125, 0.75, 1.0, 0.5, "wood")
	box(m, f, -1.0, 1.4375, 0.75, 0.75, 0.25, 0.25, "steel", "SawBlade")
	for _, x in { -1.5, -0.5 } do
		box(m, f, x, 1.6875, 0.75, 0.25, 0.75, 0.25, "orange", "SawBow")
	end
	box(m, f, -1.0, 2.0, 0.75, 1.25, 0.25, 0.25, "orange", "SawBow")
	ball(m, f, -1.0, 0.05, 0.75, 0.5, "desk", "Sawdust")
	cyl(m, f, -0.125, 0.375, 1.125, 0.5, 0.5, "steel", "Bucket")
	box(m, f, -0.125, 0.6875, 1.125, 0.5, 0.25, 0.25, "steel_dark", "BucketHandle")
	-- the chopping stump with its rings, roots and an axe, split wood about
	cyl(m, f, 0.625, 0.5, 0.875, 1.0, 0.75, "wood_dark", "Stump")
	cyl(m, f, 0.625, 0.78, 0.875, 0.75, 0.25, "desk", "StumpTop")
	cyl(m, f, 0.625, 0.81, 0.875, 0.5, 0.25, "wood", "Ring")
	cyl(m, f, 0.625, 0.84, 0.875, 0.25, 0.25, "desk", "Ring")
	for _, a in { 1.0, 2.4, -1.6 } do
		put(m, f, CFrame.new(0.625 + math.sin(a) * 0.5, 0.25, 0.875 + math.cos(a) * 0.5) * CFrame.Angles(0, a, 0), 0.25, 0.25, 0.5, "wood_dark", "Root")
	end
	box(m, f, 0.75, 1.0625, 0.875, 0.25, 0.25, 0.25, "steel", "AxeHead")
	span(m, f, Vector3.new(0.8125, 1.125, 0.875), Vector3.new(1.3125, 1.5, 0.875), 0.25, 0.25, "wood", "AxeHandle")
	for k, s in { { 0.0, 0.625, 0.7 }, { 1.375, 1.25, 0.15 }, { 1.125, 0.25, -0.5 } } do
		put(m, f, CFrame.new(s[1], 0.25, s[2]) * CFrame.Angles(0, s[3], 0), 0.5, 0.25, 0.25, if k == 2 then "wood" else "desk", "Split")
	end
	-- firewood stacked crosswise, its ends to the front
	for i = 0, 2 do
		for j = 0, 1 do
			box(m, f, 1.5 + j * 0.25, 0.25 + i * 0.25, 0.5 + (i % 2) * 0.125, 0.25, 0.25, 0.75, if (i + j) % 2 == 0 then "desk" else "wood", "Firewood")
		end
	end
end

-- Sawmill (4 x 4): a board shed on a plank deck under a blue-grey shingled roof with a brick chimney and a round vent
-- in its gable. On the left the office: a red plank door with a step, a window with a box of flowers, a sign with a saw
-- blade on it hung out from the corner. On the right the open saw bay: braced posts, the big round saw in its bench
-- cutting a log, sawdust heaped under it, a spare blade on the back wall, a lantern. Out front logs on skids, a low
-- stack of fresh boards drying and stepping stones to the door.
B.sawmill = function(m, f)
	box(m, f, 0, 0, 1.25, 4, 0.25, 1.5, "sand_dark", "Yard")
	box(m, f, 0.25, 0.125, -0.625, 3.25, 0.25, 2.5, "wood_dark", "Deck")
	-- the shed: the office's walls, the bay's back wall, posts, beams and braces
	box(m, f, -0.375, 1.125, -0.75, 1.75, 1.75, 1.75, "wood", "Walls")
	box(m, f, 1.125, 1.125, -1.5, 1.25, 1.75, 0.25, "wood", "BackWall")
	for _, p in { { -1.25, 0.125 }, { 0.5, 0.125 }, { 1.75, 0.125 }, { 1.75, -1.5 } } do
		post(m, f, p[1], 0.25, p[2], 1.75)
	end
	box(m, f, 1.125, 1.875, 0.125, 1.0, 0.25, 0.25, "wood_dark", "Lintel")
	box(m, f, 1.75, 1.875, -0.625, 0.25, 0.25, 1.25, "wood_dark", "Plate")
	span(m, f, Vector3.new(1.75, 1.25, 0.0625), Vector3.new(1.25, 1.75, 0.0625), 0.25, 0.25, "wood_dark", "Brace")
	span(m, f, Vector3.new(0.5, 1.25, 0.0625), Vector3.new(1.0, 1.75, 0.0625), 0.25, 0.25, "wood_dark", "Brace")
	plankDoor(m, f, -0.75, 0.25, 0.125, 0.5, 1.125, "berry_red")
	frontWindow(m, f, 0.0, 1.25, 0.125, 0.5, 0.5, nil, { "pink", "yellow" })
	box(m, f, -0.75, 0.0625, 0.75, 0.75, 0.25, 0.25, "rock", "Step")
	-- on the bay's back wall: a spare blade
	discZ(m, f, 1.5, 1.25, -1.22, 0.5, "steel", "SpareBlade")
	discZ(m, f, 1.5, 1.25, -1.19, 0.25, "steel_dark", "Hub")
	-- the saw bench: the blade cutting a log, sawdust heaped in front
	box(m, f, 1.25, 0.875, -0.375, 1.25, 0.25, 0.5, "wood", "Bench")
	for _, x in { 0.75, 1.75 } do
		box(m, f, x, 0.5, -0.375, 0.25, 0.5, 0.5, "wood_dark", "BenchLeg")
	end
	sawBlade(m, f, 1.0, 1.0, -0.375, 1.0, { 1.4, 1.95, 2.5 })
	logX(m, f, 1.5, 1.25, -0.375, 0.75, 0.5, "wood")
	ball(m, f, 1.0, 0.25, 0.125, 0.75, "desk", "Sawdust")
	-- the roof, its vent and the chimney
	gableRoof(m, f, 0.25, -0.75, 2.0, 3.0, 1.75, 0.875, "steel_dark", "slate", "wood", 0.125, 0.25)
	discX(m, f, 1.685, 2.25, -0.75, 0.5, "wood_dark", "Vent")
	discX(m, f, 1.715, 2.25, -0.75, 0.25, "black", "Vent")
	box(m, f, -0.625, 2.8125, -1.25, 0.5, 1.25, 0.5, "brick", "Chimney")
	box(m, f, -0.625, 3.5, -1.25, 0.75, 0.25, 0.75, "rock_dark", "ChimneyCap")
	-- the sign hung out from the corner, a saw blade painted on it, and the lantern by the bay
	box(m, f, -1.5, 1.6875, 0.25, 0.75, 0.25, 0.25, "steel_dark", "SignArm")
	box(m, f, -1.625, 1.1875, 0.22, 0.75, 0.75, 0.25, "wood_dark", "SignBack")
	box(m, f, -1.625, 1.1875, 0.25, 0.5, 0.5, 0.25, "desk", "Sign")
	discZ(m, f, -1.625, 1.1875, 0.28, 0.5, "steel", "SignBlade")
	discZ(m, f, -1.625, 1.1875, 0.31, 0.25, "steel_dark", "SignHub")
	lantern(m, f, 0.5, 1.5, 0.25, 0, 0.25)
	-- the yard: logs on skids, boards drying, stepping stones
	for _, z in { 1.0, 1.75 } do
		box(m, f, -1.375, 0.25, z, 1.25, 0.25, 0.25, "wood_dark", "Skid")
	end
	logZ(m, f, -1.625, 0.625, 1.375, 1.0, 0.5, "wood")
	logZ(m, f, -1.125, 0.625, 1.375, 1.0, 0.5, "wood_dark")
	logZ(m, f, -1.375, 1.0625, 1.375, 1.0, 0.5, "wood")
	boardStack(m, f, 1.0, 0.125, 1.5, 1.0, 1.0, 2, false, { "desk", "sand_dark" })
	for k, s in { { -0.5, 0.875 }, { -0.25, 1.375 }, { -0.5, 1.75 } } do
		box(m, f, s[1], 0.03, s[2], 0.5, 0.25, 0.5, if k == 2 then "rock_dark" else "rock", "Stone")
	end
end

-- Timber Works (4 x 4): a yard of packed earth. At the back an open drying shed on four posts under a red shingled
-- roof, three racks of pale boards on arms inside with their ends staggered, a lantern at its corner. On the right a
-- wooden crane: a mast on a stone block with braces, a jib with its tie and a counterweight, a pulley, a rope and a
-- hook lifting a bundle of boards in slings, a winch with rope wound on its drum, a crate beside it. In front of the
-- shed a row of squared beams, and along the front a short rail track on sleepers with a trolley of logs and a
-- red-topped buffer at its end.
B.timber = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 4, "sand_dark", "Yard")
	-- the drying shed and its racks
	for _, p in { { -1.25, -1.625 }, { 0.5, -1.625 }, { -1.25, -0.125 }, { 0.5, -0.125 } } do
		post(m, f, p[1], 0, p[2], 1.75)
	end
	for _, z in { -1.625, -0.125 } do
		box(m, f, -0.375, 1.875, z, 2.0, 0.25, 0.25, "wood_dark", "Plate")
	end
	for _, x in { -1.25, 0.5 } do
		box(m, f, x, 1.875, -0.875, 0.25, 0.25, 1.25, "wood_dark", "Plate")
	end
	local tones = { { "desk", "sand" }, { "sand_dark", "desk" }, { "sand", "sand_dark" } }
	local ends = { 0.75, 1.0, 0.5 }
	for k = 1, 3 do
		local ya = 0.375 + (k - 1) * 0.5
		for _, x in { -1.25, 0.5 } do
			box(m, f, x, ya, -0.875, 0.25, 0.25, 1.25, "wood_dark", "Arm")
		end
		local len = ends[k] + 1.25
		for j, z in { -1.125, -0.625 } do
			box(m, f, ends[k] - len / 2, ya + 0.25, z, len, 0.25, 0.5, tones[k][j], "Boards")
		end
	end
	gableRoof(m, f, -0.375, -0.875, 2.0, 1.75, 1.5, 0.75, "berry_red", "brick", "wood", 0.125, 0.25)
	lantern(m, f, -1.25, 1.5, -0.125, 0, 0.25)
	-- a crate by the crane
	box(m, f, 1.5, 0.5, 0.0, 0.75, 0.75, 0.75, "wood", "Crate")
	box(m, f, 1.5, 0.5, 0.28, 0.5, 0.25, 0.25, "wood_dark", "CrateSlat")
	box(m, f, 1.78, 0.5, 0.0, 0.25, 0.25, 0.5, "wood_dark", "CrateSlat")
	-- squared beams in a row, their ends to the front
	for k, x in { -0.875, -0.25, 0.375 } do
		box(m, f, x, 0.375, 0.5, 0.5, 0.5, 0.75, if k == 2 then "sand_dark" else "desk", "Beam")
	end
	-- the crane
	box(m, f, 1.375, 0.25, -1.25, 0.75, 0.5, 0.75, "rock", "CraneBase")
	box(m, f, 1.375, 2.125, -1.25, 0.25, 3.25, 0.25, "wood_dark", "Mast")
	for _, x in { 1.0, 1.75 } do
		span(m, f, Vector3.new(1.375, 1.5, -1.25), Vector3.new(x, 0.5, -0.875), 0.25, 0.25, "wood_dark", "Brace")
	end
	box(m, f, 1.375, 3.0, -0.5, 0.25, 0.25, 2.5, "wood", "Jib")
	span(m, f, Vector3.new(1.375, 3.625, -1.25), Vector3.new(1.375, 3.125, 0.625), 0.25, 0.25, "wood_dark", "Tie")
	box(m, f, 1.375, 2.625, -1.625, 0.5, 0.5, 0.5, "rock_dark", "Counterweight")
	discX(m, f, 1.375, 2.75, 0.625, 0.5, "steel", "Pulley")
	box(m, f, 1.375, 2.125, 0.75, 0.25, 0.75, 0.25, "straw", "Rope")
	box(m, f, 1.375, 1.625, 0.75, 0.25, 0.25, 0.25, "steel_dark", "Hook")
	for _, x in { 0.875, 1.875 } do
		span(m, f, Vector3.new(1.375, 1.5, 0.75), Vector3.new(x, 1.125, 0.75), 0.25, 0.25, "straw", "Sling")
	end
	box(m, f, 1.375, 0.875, 0.75, 1.25, 0.25, 0.5, "desk", "Bundle")
	box(m, f, 1.375, 1.125, 0.75, 1.25, 0.25, 0.5, "wood", "Bundle")
	for _, x in { 1.0, 1.75 } do
		box(m, f, x, 0.375, -0.625, 0.25, 0.75, 0.5, "wood_dark", "WinchFrame")
	end
	log(m, f, 1.375, 0.5, -0.625, 0.5, 0.5, "wood", "Drum")
	log(m, f, 1.375, 0.5, -0.625, 0.25, 0.75, "straw", "RopeCoil")
	-- the track, the trolley of logs and the buffer
	for k = 0, 6 do
		box(m, f, -1.75 + k * 0.5, 0.0625, 1.5, 0.25, 0.25, 1.0, "wood_dark", "Sleeper")
	end
	for _, z in { 1.25, 1.75 } do
		box(m, f, -0.25, 0.3125, z, 3.5, 0.25, 0.25, "steel", "Rail")
	end
	box(m, f, 1.5, 0.4375, 1.5, 0.25, 0.5, 0.75, "wood_dark", "Buffer")
	box(m, f, 1.5, 0.8125, 1.5, 0.25, 0.25, 0.75, "berry_red", "Buffer")
	for _, x in { -1.125, -0.375 } do
		for _, z in { 1.25, 1.75 } do
			discZ(m, f, x, 0.6875, z, 0.5, "steel_dark", "Wheel")
		end
	end
	box(m, f, -0.75, 1.0625, 1.5, 1.25, 0.25, 1.0, "wood", "Trolley")
	logX(m, f, -0.75, 1.4375, 1.25, 1.5, 0.5, "wood")
	logX(m, f, -0.75, 1.4375, 1.75, 1.5, 0.5, "wood_dark")
end

-- A bamboo cane at (x, z): `n` segments of `body` each topped by a ring of `node`, a short top piece when `tip`, a leaf
-- drooping toward `dir` (1 east, -1 west) at the top, one toward the front lower down and a sprig on top.
local function cane(m: Instance, f: CFrame, x: number, z: number, n: number, tip: boolean, body: string, node: string, dir: number)
	local y = 0.125
	for _ = 1, n do
		box(m, f, x, y + 0.375, z, 0.25, 0.75, 0.25, body, "Cane")
		box(m, f, x, y + 0.875, z, 0.25, 0.25, 0.25, node, "Node")
		y += 1.0
	end
	if tip then
		box(m, f, x, y + 0.25, z, 0.25, 0.5, 0.25, body, "Cane")
		y += 0.5
	end
	put(m, f, CFrame.new(x + dir * 0.375, y - 0.125, z) * CFrame.Angles(0, 0, -dir * 0.35), 0.75, 0.25, 0.25, "leaf", "Leaf")
	put(m, f, CFrame.new(x, y - 0.625, z + 0.375) * CFrame.Angles(0.35, 0, 0), 0.25, 0.25, 0.75, "leaf_dark", "Leaf")
	box(m, f, x, y + 0.125, z, 0.25, 0.25, 0.25, "leaf", "Sprig")
end

-- Bamboo Grove (4 x 3): three clumps of ringed canes, green and golden, on patches of soil, leaves drooping from them,
-- young shoots coming up between. On the right cut poles leaning on a drying rack, a bundle of them on the ground in
-- front; on the left a pond with stones round it, a bamboo spout dripping into it and a lily pad. A stone lantern lit
-- inside, a basket of shoots and stepping stones up the middle.
B.bamboo = function(m, f)
	box(m, f, 0, 0, 0, 4, 0.25, 3, "grass_dark", "Ground")
	for _, c in { { -0.625, -1.0, 1.0, 0.75 }, { 1.0, -1.0, 1.25, 0.75 }, { -1.625, 0.0, 0.5, 0.75 } } do
		box(m, f, c[1], 0.03, c[2], c[3], 0.25, c[4], "sand_dark", "Soil")
	end
	cane(m, f, -0.25, -1.375, 3, true, "green", "bamboo", 1)
	cane(m, f, -0.875, -1.375, 3, false, "bamboo", "moss", 1)
	cane(m, f, -0.875, -0.75, 2, true, "green", "bamboo", 1)
	cane(m, f, -0.5, -1.0, 2, true, "bamboo", "moss", 1)
	cane(m, f, 0.625, -1.125, 3, true, "bamboo", "moss", -1)
	cane(m, f, 1.0, -1.375, 3, false, "green", "bamboo", 1)
	cane(m, f, 1.0, -0.75, 2, false, "green", "bamboo", -1)
	cane(m, f, 1.375, -1.0, 2, true, "bamboo", "moss", -1)
	cane(m, f, -1.75, -0.125, 2, true, "green", "bamboo", 1)
	cane(m, f, -1.375, 0.125, 3, false, "bamboo", "moss", 1)
	for _, s in { { 0.25, -1.0 }, { -1.125, -0.375 }, { 1.75, -0.875 } } do
		box(m, f, s[1], 0.25, s[2], 0.25, 0.25, 0.25, "sand_dark", "Shoot")
		box(m, f, s[1], 0.5, s[2], 0.25, 0.25, 0.25, "green", "Shoot")
	end
	for k, s in { { 0.0, 1.25 }, { -0.125, 0.625 }, { -0.375, 0.0 } } do
		box(m, f, s[1], 0.0625, s[2], 0.5, 0.25, 0.5, if k == 2 then "rock_dark" else "rock", "Stone")
	end
	-- the drying rack: a bar on two posts with cut poles leaning on it, a bundle on the ground in front
	for _, x in { 1.0, 1.75 } do
		post(m, f, x, 0.125, -0.375, 1.25, "bamboo", "RackPost")
	end
	box(m, f, 1.375, 1.375, -0.375, 1.0, 0.25, 0.25, "bamboo", "RackBar")
	for k, x in { 1.0, 1.25, 1.5, 1.75 } do
		span(m, f, Vector3.new(x, 0.125, 0.5), Vector3.new(x, 1.625, -0.5), 0.25, 0.25, ({ "straw", "green", "bamboo", "straw" })[k], "Pole")
	end
	box(m, f, 1.0, 0.25, 0.875, 1.0, 0.25, 0.25, "bamboo", "Pole")
	box(m, f, 1.0, 0.25, 1.125, 1.0, 0.25, 0.25, "green", "Pole")
	box(m, f, 1.0, 0.5, 1.0, 1.0, 0.25, 0.25, "straw", "Pole")
	-- the pond, its stones, the spout dripping into it, a lily pad
	box(m, f, -1.25, 0.03, 0.875, 1.0, 0.25, 0.75, "water", "Water"):SetAttribute("PixelWater", 2)
	for _, r in { { -1.875, 0.25, 0.875, 0.25, 0.5, 0.75 }, { -1.5, 0.1875, 1.375, 0.5, 0.25, 0.25 }, { -0.875, 0.1875, 1.375, 0.75, 0.25, 0.25 }, { -0.625, 0.25, 0.875, 0.25, 0.5, 0.5 }, { -0.875, 0.1875, 0.375, 0.5, 0.25, 0.25 } } do
		box(m, f, r[1], r[2], r[3], r[4], r[5], r[6], if r[5] > 0.25 then "rock_dark" else "rock", "PondStone")
	end
	post(m, f, -1.375, 0.125, 0.375, 0.75, "bamboo", "SpoutPost")
	put(m, f, CFrame.new(-1.375, 0.75, 0.625) * CFrame.Angles(0.25, 0, 0), 0.25, 0.25, 0.5, "green", "Spout")
	box(m, f, -1.375, 0.0625, 0.875, 0.25, 0.25, 0.25, "foam", "Ripple")
	cyl(m, f, -1.0, 0.0625, 1.0, 0.5, 0.25, "leaf", "LilyPad")
	box(m, f, -0.9375, 0.3125, 1.0, 0.25, 0.25, 0.25, "pink", "Lily")
	-- the stone lantern
	local lx, lz = 0.375, 0.25
	box(m, f, lx, 0.25, lz, 0.5, 0.25, 0.5, "rock", "LanternBase")
	box(m, f, lx, 0.625, lz, 0.25, 0.5, 0.25, "rock", "LanternPillar")
	box(m, f, lx, 1.125, lz, 0.5, 0.5, 0.5, "rock", "LanternBox")
	box(m, f, lx, 1.125, lz + 0.155, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, lx + 0.155, 1.125, lz, 0.25, 0.25, 0.25, "yellow", "LanternLight", true)
	box(m, f, lx, 1.5, lz, 0.75, 0.25, 0.75, "rock_dark", "LanternRoof")
	box(m, f, lx, 1.75, lz, 0.25, 0.25, 0.25, "rock_dark", "LanternTop")
	-- a basket of shoots
	box(m, f, 0.25, 0.375, -0.5, 0.5, 0.5, 0.5, "straw", "Basket")
	box(m, f, 0.125, 0.875, -0.5, 0.25, 0.5, 0.25, "sand_dark", "Shoot")
	box(m, f, 0.375, 0.75, -0.375, 0.25, 0.25, 0.25, "bamboo", "Shoot")
end

-- Grand Mill (5 x 4): a mill house of stone below and white plaster framed in dark timber above, the upper storey
-- jutting out over the lower, under a clay tiled roof with a stone chimney and a round window in its east gable. An
-- arched double door up a stone ramp, a shuttered window, a lantern and a pot of flowers below; above, a window with a
-- flower box between braced corner posts, and a sign with a saw blade hung out from the corner. On the east the big
-- waterwheel turning in a stone race: two rims, spokes and paddles round a hub on an axle from the wall to a stone
-- pier, foam where the paddles dip. In front a low stack of sawn boards and two logs.
B.grandmill = function(m, f)
	box(m, f, -0.5, 0.125, -0.25, 2.75, 0.25, 2.25, "rock_dark", "Plinth")
	box(m, f, -0.5, 0.875, -0.375, 2.5, 1.25, 1.75, "rock", "Walls")
	box(m, f, -0.5, 2.125, -0.25, 2.5, 1.25, 2.0, "cream", "Upper")
	-- the upper storey's frame: a sill beam under the jetty, corner posts, the top plate, braces; a window between
	box(m, f, -0.5, 1.5, 0.6875, 2.75, 0.25, 0.25, "wood_dark", "Sill")
	for _, x in { -1.75, 0.75 } do
		box(m, f, x, 2.125, 0.655, 0.25, 1.25, 0.25, "wood_dark", "Beam")
	end
	box(m, f, -0.5, 2.625, 0.655, 2.25, 0.25, 0.25, "wood_dark", "Beam")
	span(m, f, Vector3.new(-1.625, 1.6875, 0.64), Vector3.new(-1.0, 2.5, 0.64), 0.25, 0.25, "wood_dark", "Brace")
	span(m, f, Vector3.new(0.625, 1.6875, 0.64), Vector3.new(0.0, 2.5, 0.64), 0.25, 0.25, "wood_dark", "Brace")
	frontWindow(m, f, -0.5, 2.125, 0.75, 0.5, 0.5, nil, { "pink", "yellow" })
	-- below: a shuttered window, the arched door, its ramp and a lantern
	frontWindow(m, f, -1.125, 0.875, 0.5, 0.5, 0.5, "teal", nil)
	discZ(m, f, 0.0, 1.0, 0.5625, 1.0, "wood_dark", "DoorFrame")
	box(m, f, 0.0, 0.625, 0.5625, 1.0, 0.75, 0.25, "wood_dark", "DoorFrame")
	box(m, f, 0.0, 0.625, 0.625, 0.75, 0.75, 0.25, "wood", "Door")
	discZ(m, f, 0.0, 1.0, 0.6, 0.75, "wood", "Door")
	box(m, f, 0.0, 0.75, 0.655, 0.25, 1.0, 0.25, "wood_dark", "DoorSeam")
	wedge(m, f, 0.0, 0.125, 1.125, 1.0, 0.25, 0.5, "rock", math.pi, "Ramp")
	box(m, f, -0.625, 1.25, 0.8125, 0.25, 0.25, 0.25, "steel_dark", "LanternCap")
	box(m, f, -0.625, 1.0, 0.8125, 0.25, 0.25, 0.25, "yellow", "Lantern", true)
	-- the sign hung out from the front-left corner
	box(m, f, -1.75, 2.375, 1.0, 0.25, 0.25, 0.5, "steel_dark", "SignArm")
	box(m, f, -1.78, 1.875, 1.1875, 0.25, 0.75, 0.75, "wood_dark", "SignBack")
	box(m, f, -1.75, 1.875, 1.1875, 0.25, 0.5, 0.5, "desk", "Sign")
	discX(m, f, -1.72, 1.875, 1.1875, 0.5, "steel", "SignBlade")
	discX(m, f, -1.69, 1.875, 1.1875, 0.25, "steel_dark", "SignHub")
	-- the roof, its round window, the chimney
	gableRoof(m, f, -0.5, -0.25, 2.75, 2.5, 2.0, 1.125, "clay", "brick", "cream", 0.125, 0.25)
	discX(m, f, 0.685, 2.875, -0.25, 0.75, "wood_dark", "Oculus")
	discX(m, f, 0.715, 2.875, -0.25, 0.5, "window", "Oculus")
	box(m, f, -1.25, 3.625, -0.875, 0.5, 1.25, 0.5, "rock", "Chimney")
	box(m, f, -1.25, 4.3125, -0.875, 0.75, 0.25, 0.75, "rock_dark", "ChimneyCap")
	-- the race: stone walls, the water, foam
	box(m, f, 1.625, 0.25, -0.25, 1.25, 0.25, 3.25, "water", "Water"):SetAttribute("PixelWater", 2)
	for _, x in { 0.875, 2.375 } do
		box(m, f, x, 0.25, -0.25, 0.25, 0.5, 3.25, "rock", "RaceWall")
	end
	box(m, f, 1.625, 0.25, 1.5, 1.75, 0.5, 0.25, "rock", "RaceWall")
	box(m, f, 1.625, 0.3125, 0.0, 0.75, 0.25, 0.5, "foam", "Foam")
	box(m, f, 1.5, 0.3125, 0.625, 0.5, 0.25, 0.25, "foam", "Foam")
	-- the waterwheel (only the parts named Paddle turn: Controllers/Spinners, about the hub at (1.6, 1.5, -0.6))
	local hy, hz = 1.5, -0.6
	for _, sx in { 1.225, 1.975 } do
		for k = 0, 9 do
			local a = k * math.pi / 5
			put(m, f, CFrame.new(sx, hy + math.sin(a) * 1.125, hz + math.cos(a) * 1.125) * CFrame.Angles(-a, 0, 0), 0.25, 0.75, 0.25, "wood_dark", "Rim")
		end
	end
	for k = 0, 9 do
		local a = (k + 0.5) * math.pi / 5
		put(m, f, CFrame.new(1.6, hy + math.sin(a) * 1.125, hz + math.cos(a) * 1.125) * CFrame.Angles(-a, 0, 0), 0.5, 0.25, 0.5, "wood", "Paddle")
	end
	for k = 0, 2 do
		put(m, f, CFrame.new(1.975, hy, hz) * CFrame.Angles(-k * math.pi / 3, 0, 0), 0.25, 0.25, 2.0, "wood", "Paddle")
	end
	log(m, f, 1.6, hy, hz, 1.0, 0.75, "wood_dark", "Hub")
	log(m, f, 2.035, hy, hz, 0.25, 0.5, "steel_dark", "HubCap")
	log(m, f, 1.625, hy, hz, 1.75, 0.5, "steel_dark", "Axle")
	box(m, f, 2.375, 0.875, hz, 0.25, 0.75, 0.5, "rock", "Pier")
	box(m, f, 2.375, 1.5, hz, 0.25, 0.5, 0.75, "wood_dark", "Bearing")
	-- the yard: a low stack of sawn boards, two logs waiting, a pot of flowers by the door
	boardStack(m, f, -2.0, 0.0, 1.375, 1.0, 1.0, 2, true, { "desk", "sand_dark", "wood" })
	logZ(m, f, -1.25, 0.25, 1.5, 0.75, 0.5, "wood")
	logZ(m, f, -0.75, 0.25, 1.5, 0.75, 0.5, "wood_dark")
	box(m, f, 0.625, 0.375, 0.75, 0.25, 0.25, 0.25, "pot", "Pot")
	box(m, f, 0.625, 0.625, 0.75, 0.25, 0.25, 0.25, "leaf", "Plant")
	box(m, f, 0.5625, 0.75, 0.8125, 0.25, 0.25, 0.25, "pink", "Bloom")
end

-- A chute along a slope from a to b (the middle of its floor's top): the floor, two sides and water running in it a
-- step short of each end.
local function chute(m: Instance, f: CFrame, a: Vector3, b: Vector3)
	local cf = CFrame.lookAt((a + b) / 2, b)
	local len = (b - a).Magnitude
	put(m, f, cf * CFrame.new(0, -0.125, 0), 0.5, 0.25, len, "wood", "Chute")
	for _, s in { -1, 1 } do
		put(m, f, cf * CFrame.new(s * 0.375, 0, 0), 0.25, 0.5, len, "wood_dark", "ChuteSide")
	end
	put(m, f, cf, 0.5, 0.25, len - 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
end

-- An A-frame trestle under a chute at p (the floor's top; the chute runs along X when `alongX`): two legs splayed out
-- to the ground and a bar across them.
local function trestle(m: Instance, f: CFrame, p: Vector3, alongX: boolean)
	local top = p.Y - 0.25
	for _, s in { -1, 1 } do
		local o = if alongX then Vector3.new(0, 0, s) else Vector3.new(s, 0, 0)
		span(m, f, Vector3.new(p.X, top, p.Z) + o * 0.25, Vector3.new(p.X, 0.0625, p.Z) + o * 0.5, 0.25, 0.25, "wood_dark", "Trestle")
	end
	box(m, f, p.X, top * 0.45, p.Z, if alongX then 0.25 else 1.0, 0.25, if alongX then 1.0 else 0.25, "wood_dark", "Trestle")
end

-- Log Flume (5 x 4): a mossy hill at the back with pines and rocks on it, a head deck on posts at its top with a water
-- tank pouring into the flume and a log waiting. The flume runs east on trestles to a box where it turns, then down
-- toward the front into a stone pool, a log riding each length and another floating in the pool by the splash. In
-- front a plank yard with logs stacked on skids and a cant hook leaning on them, a lantern post and a sign pointing
-- the way the logs go.
B.logflume = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 4, "grass_dark", "Lawn")
	box(m, f, -1.25, 0.0625, 1.25, 2.5, 0.25, 1.25, "wood_dark", "Yard")
	ball(m, f, -0.875, 0, -0.75, 2.25, "moss", "Hill")
	ball(m, f, -1.75, 0, -0.125, 1.5, "moss", "Hill")
	ball(m, f, -0.25, 0.25, 0.0, 0.75, "rock", "Rock")
	ball(m, f, -1.125, 0.375, 0.375, 0.5, "rock_dark", "Rock")
	pine(m, f, -1.625, 0.75, -0.5, { 1.5, 1.0, 0.5 })
	pine(m, f, -2.0, 0.625, 0.0, { 1.0, 0.5 })
	ball(m, f, 0.75, 0.25, -1.5, 0.75, "leaf_dark", "Bush")
	-- the head deck, its tank and spout, a log waiting
	box(m, f, -0.5, 1.5, -1.25, 1.0, 0.25, 1.0, "wood_dark", "HeadDeck")
	for _, z in { -0.875, -1.625 } do
		post(m, f, -0.125, 0.375, z, 1.0, "wood_dark", "DeckPost")
	end
	cyl(m, f, -0.625, 2.125, -1.375, 0.75, 1.0, "wood", "Tank")
	cyl(m, f, -0.625, 2.53, -1.375, 0.5, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
	for _, y in { 1.875, 2.375 } do
		cyl(m, f, -0.625, y, -1.375, 1.0, 0.25, "steel_dark", "Hoop")
	end
	box(m, f, -0.125, 1.875, -1.25, 0.5, 0.25, 0.25, "wood_dark", "Spout")
	logX(m, f, -0.5, 1.875, -0.75, 0.75, 0.5, "wood")
	-- the flume: east along the back, the turning box, south to the pool
	local a1, b1 = Vector3.new(0.0, 1.625, -1.25), Vector3.new(1.375, 1.125, -1.25)
	local a2, b2 = Vector3.new(1.75, 1.125, -0.875), Vector3.new(1.75, 0.5, 0.625)
	chute(m, f, a1, b1)
	chute(m, f, a2, b2)
	box(m, f, 1.75, 1.0, -1.25, 0.75, 0.25, 0.75, "wood", "Chute")
	box(m, f, 1.75, 1.125, -1.625, 1.0, 0.5, 0.25, "wood_dark", "ChuteSide")
	box(m, f, 2.125, 1.125, -1.125, 0.25, 0.5, 0.75, "wood_dark", "ChuteSide")
	box(m, f, 1.75, 1.125, -1.25, 0.5, 0.25, 0.5, "water", "Water"):SetAttribute("PixelWater", 2)
	for _, p in { { 1.5, -1.5 }, { 2.0, -1.0 } } do
		post(m, f, p[1], 0, p[2], 1.0, "wood_dark", "Trestle")
	end
	for _, x in { 0.375, 1.0 } do
		trestle(m, f, a1:Lerp(b1, (x - a1.X) / (b1.X - a1.X)), true)
	end
	trestle(m, f, a2:Lerp(b2, 0.4), false)
	-- a log riding each length
	local c1 = CFrame.lookAt((a1 + b1) / 2, b1)
	put(m, f, c1 * CFrame.new(0, 0.25, 0.1 * (b1 - a1).Magnitude) * ACROSS, 0.75, 0.5, 0.5, "wood", "Log", "Cylinder")
	local c2 = CFrame.lookAt((a2 + b2) / 2, b2)
	put(m, f, c2 * CFrame.new(0, 0.25, -0.15 * (b2 - a2).Magnitude) * ACROSS, 0.75, 0.5, 0.5, "wood_dark", "Log", "Cylinder")
	-- the pool, the splash, a log floating
	box(m, f, 1.5, 0.25, 0.75, 1.25, 0.5, 0.25, "rock", "PondRim")
	box(m, f, 1.5, 0.25, 1.75, 1.25, 0.5, 0.25, "rock", "PondRim")
	for _, x in { 1.0, 2.0 } do
		box(m, f, x, 0.25, 1.25, 0.25, 0.5, 0.75, "rock_dark", "PondRim")
	end
	box(m, f, 1.5, 0.25, 1.25, 0.75, 0.25, 0.75, "water", "Pond"):SetAttribute("PixelWater", 2)
	ball(m, f, 1.75, 0.4375, 1.0, 0.5, "foam", "Splash")
	ball(m, f, 1.5, 0.4375, 0.9375, 0.25, "white", "Splash")
	logX(m, f, 1.375, 0.375, 1.375, 0.5, 0.5, "wood")
	-- the yard: logs on skids, a cant hook, the lantern post and the sign
	for _, x in { -1.875, -0.875 } do
		box(m, f, x, 0.3125, 1.125, 0.25, 0.25, 1.0, "wood", "Skid")
	end
	logX(m, f, -1.375, 0.6875, 0.875, 1.75, 0.5, "wood")
	logX(m, f, -1.375, 0.6875, 1.375, 1.75, 0.5, "wood_dark")
	logX(m, f, -1.5, 1.125, 1.125, 1.5, 0.5, "wood")
	span(m, f, Vector3.new(-0.25, 0.125, 1.625), Vector3.new(-0.5, 1.125, 1.375), 0.25, 0.25, "wood", "CantHook")
	box(m, f, -0.5, 1.125, 1.375, 0.25, 0.25, 0.25, "black", "Hook")
	post(m, f, 0.625, 0.125, 0.75, 1.5, "wood_dark", "LampPost")
	lantern(m, f, 0.625, 1.375, 0.75, 0, 0.25)
	post(m, f, 0.25, 0, 1.5, 1.25, "wood_dark", "SignPost")
	box(m, f, 0.375, 1.0, 1.5, 0.75, 0.25, 0.25, "desk", "Sign")
	wedge(m, f, 0.875, 1.0, 1.5, 0.25, 0.25, 0.25, "desk", -math.pi / 2, "Sign")
end

-- Ironwood Yard (5 x 5): a stone yard with a few pale slabs. At the back left the great ironwood, a gnarled dark trunk
-- on spreading roots over a patch of moss, with a knot hole and limbs holding a dense crown, the stump of another
-- beside it with an axe in it. At the back right a slate tool shed under a ribbed steel roof, a window in its front and
-- a teal sliding door on its side, and before it a band saw: two teal wheels, the blade, a table with a dark plank on
-- it, a lamp post lit beside it, a grindstone in its trough. Down the middle a huge log on chocks, its sawn end to the
-- front showing red heartwood with a steel wedge driven in, a crosscut saw on it and a sledgehammer leaning, the
-- derrick on the left about to lift it by its chain and tongs. Two stacks of reddish boards drying at the front
-- corners.
B.ironwood = function(m, f)
	box(m, f, 0, 0, 0, 5, 0.25, 5, "rock", "Yard")
	for _, s in { { 1.375, 0.25, 0.75, 1.0 }, { 0.5, 1.0, 0.5, 0.75 }, { -1.75, 0.0, 0.75, 0.5 }, { 0.25, -0.75, 0.5, 0.5 } } do
		box(m, f, s[1], 0.03, s[2], s[3], 0.25, s[4], "pavement", "Slab")
	end
	box(m, f, -1.25, 0.03, -1.0, 1.75, 0.25, 1.5, "moss", "Moss")
	-- the tree: roots, the trunk, limbs, the crown
	for _, a in { 0.4, 1.6, 2.9, 4.4, 5.5 } do
		span(m, f, Vector3.new(-1.25 + math.sin(a) * 0.375, 0.4375, -1.25 + math.cos(a) * 0.375), Vector3.new(-1.25 + math.sin(a) * 1.0, 0.125, -1.25 + math.cos(a) * 1.0), 0.5, 0.25, "basalt", "Root")
	end
	tube(m, f, { Vector3.new(-1.25, -0.25, -1.25), Vector3.new(-1.25, 1.25, -1.25), Vector3.new(-1.125, 2.5, -1.0), Vector3.new(-1.0, 3.375, -1.0) }, function(i: number): number
		return 1.0 - (i - 1) * 0.125
	end, function(_: number): string
		return "basalt"
	end, "Trunk", true)
	box(m, f, -1.25, 1.0, -0.78, 0.25, 0.25, 0.25, "black", "Knot")
	for _, l in { { -0.125, 3.375, -0.5 }, { -1.875, 3.375, -0.375 }, { -0.75, 3.625, -1.875 } } do
		local a, b = Vector3.new(-1.125, 2.5, -1.0), Vector3.new(l[1], l[2], l[3])
		put(m, f, CFrame.lookAt((a + b) / 2, b) * ACROSS, (b - a).Magnitude, 0.5, 0.5, "basalt", "Limb", "Cylinder")
	end
	ball(m, f, -1.0, 4.25, -1.0, 2.25, "leaf_dark", "Crown")
	ball(m, f, -0.25, 3.75, -0.375, 1.5, "leaf_dark", "Crown")
	ball(m, f, -1.75, 3.625, -0.375, 1.25, "swamp", "Crown")
	ball(m, f, -0.75, 3.625, -1.75, 1.25, "swamp", "Crown")
	ball(m, f, -0.875, 5.0, -1.125, 1.25, "leaf_dark", "Crown")
	-- the stump and its axe
	cyl(m, f, 0.125, 0.375, -1.75, 1.0, 0.5, "basalt", "Stump")
	cyl(m, f, 0.125, 0.53, -1.75, 0.75, 0.25, "wood_dark", "Rings")
	cyl(m, f, 0.125, 0.56, -1.75, 0.5, 0.25, "brick", "Rings")
	cyl(m, f, 0.125, 0.59, -1.75, 0.25, 0.25, "wood_dark", "Rings")
	box(m, f, 0.25, 0.8125, -1.75, 0.25, 0.25, 0.25, "steel_dark", "AxeHead")
	span(m, f, Vector3.new(0.25, 0.875, -1.625), Vector3.new(0.25, 1.3125, -1.125), 0.25, 0.25, "wood", "AxeHandle")
	-- the tool shed: slate walls, corner posts, a window, a sliding door on the east, a ribbed steel roof
	box(m, f, 1.5, 0.875, -1.875, 1.5, 1.5, 0.75, "slate", "Shed")
	for _, x in { 0.75, 2.25 } do
		post(m, f, x, 0.125, -1.5, 1.5, "steel_dark", "ShedPost")
	end
	frontWindow(m, f, 1.875, 1.125, -1.5, 0.5, 0.5, nil, nil)
	box(m, f, 2.31, 0.6875, -1.875, 0.25, 1.0, 0.5, "teal", "ShedDoor")
	box(m, f, 2.34, 0.6875, -1.75, 0.25, 0.25, 0.25, "steel_dark", "DoorHandle")
	local ra, rb = Vector3.new(1.5, 2.0625, -2.375), Vector3.new(1.5, 1.6875, -1.25)
	local rcf = CFrame.lookAt((ra + rb) / 2, rb)
	local rlen = (rb - ra).Magnitude
	put(m, f, rcf, 1.75, 0.25, rlen, "steel", "Roof")
	for _, dx in { -0.625, -0.125, 0.375 } do
		put(m, f, rcf * CFrame.new(dx, 0.03, 0), 0.25, 0.25, rlen - 0.25, "steel_dark", "Rib")
	end
	-- the band saw and its lamp post
	box(m, f, 1.5, 0.375, -1.0, 0.75, 0.5, 0.5, "steel_dark", "SawBase")
	box(m, f, 1.875, 1.625, -1.125, 0.25, 2.0, 0.25, "steel_dark", "SawColumn")
	for _, y in { 0.875, 2.125 } do
		discZ(m, f, 1.5, y, -0.875, 0.75, "teal", "SawWheel")
		discZ(m, f, 1.5, y, -0.815, 0.25, "steel_dark", "Hub")
	end
	box(m, f, 1.125, 1.375, -0.875, 0.75, 0.25, 0.75, "steel", "SawTable")
	box(m, f, 1.125, 1.5, -0.875, 0.25, 1.25, 0.25, "steel", "BandBlade")
	box(m, f, 1.125, 1.625, -0.75, 0.5, 0.25, 1.0, "wood_dark", "Plank")
	ball(m, f, 1.0, 0.125, -0.25, 0.5, "sand_dark", "Sawdust")
	post(m, f, 0.5, 0.125, -1.25, 2.25, "steel_dark", "LampPost")
	lantern(m, f, 0.5, 2.25, -1.25, 0.25, 0)
	-- the huge log on its chocks, its sawn end to the front with a wedge driven in, a crosscut saw on it, a sledgehammer
	-- leaning on it
	for _, z in { 0.25, 1.75 } do
		box(m, f, -0.5, 0.3125, z, 1.0, 0.25, 0.5, "wood", "Chock")
	end
	logZ(m, f, -0.5, 0.9375, 1.0, 2.5, 1.0, "wood_dark", "brick", "basalt")
	box(m, f, -0.375, 1.125, 2.28, 0.25, 0.25, 0.25, "steel", "Wedge")
	box(m, f, -0.5, 1.5625, 1.0, 0.25, 0.25, 1.5, "steel", "CrosscutSaw")
	for _, z in { 0.25, 1.75 } do
		box(m, f, -0.5, 1.6875, z, 0.25, 0.5, 0.25, "wood", "SawHandle")
	end
	box(m, f, 0.25, 0.25, 2.125, 0.25, 0.25, 0.5, "steel_dark", "Sledge")
	span(m, f, Vector3.new(0.25, 0.3125, 2.125), Vector3.new(0.125, 1.1875, 1.75), 0.25, 0.25, "wood", "SledgeHandle")
	-- the derrick, its chain and tongs over the log
	box(m, f, -2.125, 0.25, 1.0, 0.75, 0.25, 0.75, "rock_dark", "DerrickFoot")
	box(m, f, -2.125, 1.875, 1.0, 0.25, 3.0, 0.25, "wood", "DerrickMast")
	box(m, f, -1.25, 3.125, 1.0, 2.0, 0.25, 0.25, "wood", "DerrickArm")
	span(m, f, Vector3.new(-2.125, 2.25, 1.0), Vector3.new(-1.25, 3.125, 1.0), 0.25, 0.25, "wood_dark", "DerrickBrace")
	for k = 0, 2 do
		put(m, f, CFrame.new(-0.5, 2.875 - k * 0.25, 1.0) * CFrame.Angles(0, if k % 2 == 0 then 0 else math.pi / 4, 0), 0.25, 0.25, 0.25, if k % 2 == 0 then "steel" else "steel_dark", "Chain")
	end
	box(m, f, -0.5, 2.125, 1.0, 0.25, 0.25, 0.25, "steel_dark", "Hook")
	for _, s in { -1, 1 } do
		span(m, f, Vector3.new(-0.5, 2.0625, 1.0), Vector3.new(-0.5 + s * 0.375, 1.5, 1.0), 0.25, 0.25, "steel_dark", "Tongs")
	end
	-- the stacks of reddish boards
	boardStack(m, f, 1.375, 0.125, 1.625, 1.25, 1.0, 2, true, { "brick", "wood_dark" }, "wood")
	boardStack(m, f, -1.75, 0.125, 1.875, 1.0, 1.0, 2, false, { "wood_dark", "brick" }, "wood")
	-- the grindstone in its trough
	for _, z in { -0.25, 0.75 } do
		post(m, f, 1.375, 0.125, z, 1.0, "wood_dark", "GrindPost")
	end
	put(m, f, CFrame.new(1.375, 0.8125, 0.25) * ACROSS, 0.5, 0.75, 0.75, "pavement", "Grindstone", "Cylinder")
	put(m, f, CFrame.new(1.375, 0.8125, 0.25) * ACROSS, 1.25, 0.25, 0.25, "steel_dark", "Axle", "Cylinder")
	box(m, f, 1.375, 0.75, 0.9375, 0.25, 0.5, 0.25, "steel_dark", "Crank")
	box(m, f, 1.375, 0.25, 0.25, 0.75, 0.25, 0.5, "wood_dark", "Trough")
	box(m, f, 1.375, 0.28, 0.25, 0.5, 0.25, 0.25, "water", "Water"):SetAttribute("PixelWater", 2)
end

-- A ring of railing round a round deck: `n` rails on a circle of radius r round (cx, cz), their tops at y0 + 0.75, a
-- post under every other joint, leaving out the rails whose index is in `gaps` (an opening).
local function railing(m: Instance, f: CFrame, cx: number, cz: number, r: number, y0: number, n: number, gaps: { [number]: boolean })
	local step = math.pi * 2 / n
	for k = 0, n - 1 do
		local a = step / 2 + k * step
		if k % 2 == 0 then
			box(m, f, cx + math.sin(a) * r, y0 + 0.25, cz + math.cos(a) * r, 0.25, 0.5, 0.25, "wood_dark", "RailPost")
		end
		if not gaps[k] then
			local am = a + step / 2
			local rr = r * math.cos(step / 2)
			put(m, f, CFrame.new(cx + math.sin(am) * rr, y0 + 0.625, cz + math.cos(am) * rr) * CFrame.Angles(0, am + math.pi / 2, 0), 0.25, 0.25, 2 * r * math.sin(step / 2) + 0.125, "desk", "Rail")
		end
	end
end

-- Struts under a round deck: braces from the trunk out to the deck's rim, at four angles.
local function struts(m: Instance, f: CFrame, cz: number, y0: number, y1: number, r0: number, r1: number)
	for k = 0, 3 do
		local a = math.pi / 4 + k * math.pi / 2
		span(m, f, Vector3.new(math.sin(a) * r0, y0, cz + math.cos(a) * r0), Vector3.new(math.sin(a) * r1, y1, cz + math.cos(a) * r1), 0.25, 0.25, "wood_dark", "Strut")
	end
end

-- Canopy Mill (5 x 5): one huge trunk on buttress roots with a round door and a lantern at its foot, carrying two
-- round decks on struts, each railed round. On the lower deck a cabin against the trunk with a window and a mossy
-- shingled roof, and a round saw at its bench cutting a log; a ladder up its east side. On the upper deck a saw under
-- an orange pointed roof on two posts, and a beam reaching out west with a pulley whose rope hauls a basket of logs.
-- Lanterns hang under the lower deck, vines from the upper, limbs carry the crown over it all and logs lie piled at
-- the tree's foot by a crate.
B.canopymill = function(m, f)
	local cz = -0.5
	box(m, f, 0, 0, 0, 5, 0.25, 5, "grass_dark", "Lawn")
	for _, a in { 0.65, 1.9, 3.0, 4.1, 5.6 } do
		span(m, f, Vector3.new(math.sin(a) * 0.5, 0.875, cz + math.cos(a) * 0.5), Vector3.new(math.sin(a) * 1.375, 0.125, cz + math.cos(a) * 1.375), 0.5, 0.5, "wood_dark", "Root")
	end
	cyl(m, f, 0, 3.0, cz, 1.5, 6.0, "wood_dark", "Trunk")
	ball(m, f, 0.55, 3.0, 0.0, 0.5, "wood", "Burl")
	ball(m, f, -0.5, 4.75, 0.0, 0.5, "wood", "Burl")
	K.roundDoor(m, f, 0.0, 0.625, 0.2, 0.75, "wood")
	lantern(m, f, -0.625, 1.25, 0.0, 0, 0.25)
	-- the lower deck: the deck, its rim, struts and railing (an opening at the ladder)
	cyl(m, f, 0, 1.75, cz, 3.75, 0.25, "wood", "Deck")
	cyl(m, f, 0, 1.5, cz, 3.5, 0.25, "wood_dark", "DeckRim")
	struts(m, f, cz, 0.75, 1.375, 0.75, 1.625)
	railing(m, f, 0, cz, 1.75, 1.875, 12, { [2] = true })
	-- the cabin against the trunk
	box(m, f, -0.75, 2.375, 0.25, 1.0, 1.0, 0.75, "wood", "Cabin")
	for _, x in { -1.25, -0.25 } do
		box(m, f, x, 2.375, 0.625, 0.25, 1.0, 0.25, "wood_dark", "CabinPost")
	end
	frontWindow(m, f, -0.75, 2.375, 0.625, 0.5, 0.5, nil, nil)
	gableRoof(m, f, -0.75, 0.25, 2.875, 1.0, 0.75, 0.375, "moss", "swamp", "wood", 0.125, 0.125)
	-- the lower saw
	box(m, f, 0.625, 2.25, 0.5, 0.75, 0.25, 0.5, "wood", "SawBench")
	for _, x in { 0.375, 0.875 } do
		box(m, f, x, 2.0, 0.5, 0.25, 0.25, 0.5, "wood_dark", "BenchLeg")
	end
	sawBlade(m, f, 0.5, 2.375, 0.5, 0.75, { 1.6, 2.2, 2.75 })
	logX(m, f, 0.875, 2.625, 0.5, 0.5, 0.5, "wood")
	-- the ladder
	for _, z in { -0.875, -0.125 } do
		box(m, f, 2.0, 1.1875, z, 0.25, 2.25, 0.25, "wood_dark", "LadderRail")
	end
	for k = 1, 5 do
		box(m, f, 2.0, k * 0.375, -0.5, 0.25, 0.25, 0.5, "wood", "Rung")
	end
	-- the upper deck
	cyl(m, f, 0, 4.125, cz, 3.25, 0.25, "wood", "Deck")
	cyl(m, f, 0, 3.875, cz, 3.0, 0.25, "wood_dark", "DeckRim")
	struts(m, f, cz, 3.25, 3.75, 0.75, 1.375)
	railing(m, f, 0, cz, 1.5, 4.25, 8, {})
	-- the upper saw under its pointed roof
	for _, x in { -0.5, 0.5 } do
		post(m, f, x, 4.25, 0.625, 1.0, "wood_dark", "CanopyPost")
	end
	cone(m, f, 0, 5.25, 0.375, 1.5, 0.75, "maple", "CanopyRoof")
	box(m, f, 0, 6.125, 0.375, 0.25, 0.25, 0.25, "gold", "Finial")
	box(m, f, 0, 4.625, 0.625, 0.75, 0.25, 0.5, "wood", "SawBench")
	sawBlade(m, f, -0.125, 4.75, 0.625, 0.75, { 1.8, 2.5 })
	logX(m, f, 0.25, 5.0, 0.625, 0.5, 0.5, "wood_dark")
	-- the lift: a post and a beam out west, its pulley and rope, the basket of logs on the ground
	post(m, f, -1.125, 4.25, -0.25, 1.0, "wood_dark", "LiftPost")
	box(m, f, -1.625, 5.125, -0.25, 1.25, 0.25, 0.25, "wood_dark", "LiftBeam")
	discZ(m, f, -2.0, 4.875, -0.25, 0.5, "steel", "Pulley")
	box(m, f, -2.125, 2.6875, -0.25, 0.25, 4.25, 0.25, "straw", "LiftRope")
	box(m, f, -2.0, 0.375, -0.25, 0.75, 0.5, 0.75, "straw", "Basket")
	logX(m, f, -2.0, 0.75, -0.375, 0.5, 0.25, "wood")
	logX(m, f, -1.875, 0.75, -0.125, 0.5, 0.25, "wood_dark")
	-- lanterns under the lower deck, vines from the upper
	for _, x in { -1.25, 1.25 } do
		box(m, f, x, 1.25, 0.25, 0.25, 0.25, 0.25, "black", "LanternChain")
		box(m, f, x, 1.0, 0.25, 0.25, 0.25, 0.25, "yellow", "Lantern", true)
	end
	for _, v in { { 1.25, 0.25, 1.0 }, { -1.25, -1.375, 0.75 }, { 1.0, -1.5, 0.75 } } do
		box(m, f, v[1], 3.75 - v[3] / 2, v[2], 0.25, v[3], 0.25, "leaf", "Vine")
	end
	-- the crown and its limbs
	for _, l in { { 1.125, 6.75, -0.5 }, { -1.125, 6.625, -1.0 }, { -0.25, 6.875, -1.75 }, { 0.125, 6.875, 0.25 } } do
		local a, b = Vector3.new(0, 5.75, cz), Vector3.new(l[1], l[2], l[3])
		put(m, f, CFrame.lookAt((a + b) / 2, b) * ACROSS, (b - a).Magnitude, 0.5, 0.5, "wood_dark", "Limb", "Cylinder")
	end
	ball(m, f, 0, 6.375, -0.875, 2.5, "leaf_dark", "Crown")
	ball(m, f, 0, 7.375, -0.875, 2.25, "leaf", "Crown")
	ball(m, f, -1.125, 6.75, -1.0, 1.75, "leaf_dark", "Crown")
	ball(m, f, 1.125, 6.875, -0.5, 1.75, "leaf", "Crown")
	ball(m, f, -0.25, 7.0, -1.75, 1.5, "leaf_dark", "Crown")
	ball(m, f, 0.125, 7.0, 0.25, 1.5, "leaf", "Crown")
	ball(m, f, 0.25, 8.125, -0.875, 1.25, "leaf", "Crown")
	-- logs piled at the foot on skids, a crate by the ladder
	for _, x in { -0.5, 1.0 } do
		box(m, f, x, 0.25, 1.75, 0.25, 0.25, 1.0, "wood", "Skid")
	end
	logX(m, f, 0.25, 0.625, 1.5, 2.0, 0.5, "wood")
	logX(m, f, 0.25, 0.625, 2.0, 2.0, 0.5, "wood_dark")
	logX(m, f, 0.125, 1.0625, 1.75, 1.75, 0.5, "wood")
	box(m, f, 1.75, 0.5, 0.625, 0.75, 0.75, 0.75, "wood", "Crate")
	box(m, f, 1.75, 0.5, 0.905, 0.5, 0.25, 0.25, "wood_dark", "CrateSlat")
	box(m, f, 2.03, 0.5, 0.625, 0.25, 0.25, 0.5, "wood_dark", "CrateSlat")
end

return B
