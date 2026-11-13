--!strict
-- The sea from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server: PlotService builds
-- every plot's water at start and each plot's island as players come and go).
--   road(parent, origin)          a plot's water: its lot's and the open sea's, and the invisible seabed under it
--                                 (every plot, occupied or not)
--   land(parent, origin, tier)    an occupied plot: the island (Data/Street's coast: grass in two tones, the sand
--                                 beach, the wet sand at the waterline, a ring of foam, the light shallows), the plaza
--                                 with its campfire, log seats and flag, the island's sign on its south beach (its
--                                 board named "SignBoard"), palms, rocks, shells, starfish, driftwood, seaweed and
--                                 flowers round the coast (never where a building may stand)
--   emptyLot(parent, origin)      an unclaimed plot: open water and a little sandbar with a palm and a sign
--   ends(parent)                  the sea at both ends of the row and the invisible walls round the world
-- The island's layers are whole-stud cells merged into as few boxes as they make (greedy rectangles), each layer a
-- little lower than the one inside it, so the coast steps down to the sea. The sea, the shallows and the foam carry a
-- "PixelWater" attribute (1, 2, 3): the pixel filter animates them. There are no docks: each island stands alone in
-- the sea (the request of 2026-11-13: "remove the docks area, it should just be an island. players can swim around
-- in water to reach other player islands"). The water lets the founders through to the seabed (Street.SEABED_Y), an
-- invisible floor under the whole sea, and an invisible shelf under the foam is the step up to the wet sand, so they
-- swim off any beach and climb out on any other. The seabed, the shelves and the world's walls are invisible and in
-- the "Bounds" collision group (the pixel filter's rays pass through them).
local Street = require(script.Parent.Parent.Data.Street)
local Util = require(script.Parent.Parent.Logic.Util)
local Types = require(script.Parent.Parent.Types)
local Blocks = require(script.Parent.Blocks)

local StreetModels = {}

local WALL_H = 40 -- the world's edge: far over a jump (Tuning.JumpHeight)

type Rect = Street.Rect
type Rng = Types.Rng

local function box(parent: Instance, frame: CFrame, x: number, y: number, z: number, w: number, h: number, d: number, color: string, name: string?, neon: boolean?): BasePart
	return Blocks.part(parent, { size = Vector3.new(w, h, d), cf = frame * CFrame.new(x, y, z), color = color, name = name, neon = neon })
end

-- A box by its top: x0..x1, z0..z1 plot-local, its top at `top`, `h` deep.
local function slab(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, h: number, color: string, name: string): BasePart
	return box(parent, o, (x0 + x1) / 2, top - h / 2, (z0 + z1) / 2, x1 - x0, h, z1 - z0, color, name)
end

local function ball(parent: Instance, frame: CFrame, x: number, y: number, z: number, dia: number, color: string): BasePart
	return Blocks.part(parent, { size = Vector3.new(dia, dia, dia), cf = frame * CFrame.new(x, y, z), color = color, shape = "Ball" })
end

-- Water (animated by the pixel filter: kind 1 the sea, 2 the shallows, 3 the foam): the founders swim through it.
local function water(p: BasePart, kind: number): BasePart
	p:SetAttribute("PixelWater", kind)
	p.CanCollide = false
	return p
end

-- An invisible floor (plot-local x0..x1, z0..z1, its top at `top`): the seabed the founders swim on, or the shelf under
-- the foam that steps up to the wet sand. Never in the pixel filter's rays ("Bounds").
local function floor(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number, top: number, name: string)
	local f = Blocks.part(parent, {
		size = Vector3.new(math.max(0.5, x1 - x0), 1, math.max(0.5, z1 - z0)),
		cf = o * CFrame.new((x0 + x1) / 2, top - 0.5, (z0 + z1) / 2),
		color = "white",
		name = name,
		transparency = 1,
		query = false,
	})
	f.CastShadow = false
	f.CollisionGroup = "Bounds"
end

------------------------------------------------------------------ cells to boxes
-- The cells `want` says yes to within b (inclusive cell coords), merged into rectangles (x0, z0, x1, z1 in studs:
-- the cells x0 .. x1 - 1, z0 .. z1 - 1).
local function greedy(b: Rect, want: (x: number, z: number) -> boolean): { Rect }
	local used: { [number]: boolean } = {}
	local out: { Rect } = {}
	local key = Street.cellKey
	local function free(x: number, z: number): boolean
		return want(x, z) and not used[key(x, z)]
	end
	for z = b.z0, b.z1 do
		local x = b.x0
		while x <= b.x1 do
			if free(x, z) then
				local x1 = x
				while x1 + 1 <= b.x1 and free(x1 + 1, z) do
					x1 += 1
				end
				local z1 = z
				while z1 + 1 <= b.z1 do
					local ok = true
					for xx = x, x1 do
						if not free(xx, z1 + 1) then
							ok = false
							break
						end
					end
					if not ok then
						break
					end
					z1 += 1
				end
				for zz = z, z1 do
					for xx = x, x1 do
						used[key(xx, zz)] = true
					end
				end
				table.insert(out, { x0 = x, z0 = z, x1 = x1 + 1, z1 = z1 + 1 })
				x = x1 + 1
			else
				x += 1
			end
		end
	end
	return out
end

------------------------------------------------------------------ small things
local function palm(parent: Instance, at: CFrame, s: number, lean: number?)
	local m = Blocks.model(nil, "Palm")
	local f = at * CFrame.Angles(0, lean or 0, 0)
	local x = 0
	for i = 0, 5 do
		x += 0.12 * i * s
		box(m, f, x, (0.45 + i * 0.85) * s, 0, (0.75 - i * 0.04) * s, 0.85 * s, (0.75 - i * 0.04) * s, if i % 2 == 0 then "wood" else "wood_dark", "Trunk")
	end
	local top = 5.4 * s
	ball(m, f, x + 0.25, top - 0.55, 0.3, 0.55 * s, "wood_dark")
	ball(m, f, x - 0.2, top - 0.6, -0.25, 0.5 * s, "wood_dark")
	box(m, f, x, top, 0, 1.25 * s, 0.5 * s, 1.25 * s, "leaf_dark", "Crown")
	for k, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } } do
		local long = k <= 4
		local len = (if long then 2.75 else 2) * s
		local cx, cz = x + d[1] * len / 2, d[2] * len / 2
		local frond = Blocks.part(m, {
			size = Vector3.new(len, 0.35 * s, 0.9 * s),
			cf = f * CFrame.new(cx, top - 0.15 - (if long then 0.35 else 0.1) * s, cz) * CFrame.Angles(0, math.atan2(-d[2], d[1]), math.rad(if long then -12 else -6)),
			color = if k % 2 == 0 then "leaf" else "leaf_dark",
			name = "Frond",
		})
		local _ = frond
	end
	m.Parent = parent
end

-- A rock cluster half in the water: a big stone and a couple of smaller ones round it.
local function rocks(parent: Instance, at: CFrame, s: number, rng: Rng)
	local m = Blocks.model(nil, "Rocks")
	box(m, at, 0, 0.35 * s, 0, 1.5 * s, 1.0 * s, 1.25 * s, "rock", "Stone")
	box(m, at, 0.1 * s, 0.9 * s, -0.05 * s, 1.0 * s, 0.25 * s, 0.75 * s, "rock", "Stone")
	for k = 1, rng:int(1, 3) do
		local a = rng:next() * math.pi * 2
		local r = (1.0 + rng:next() * 0.4) * s
		box(m, at, math.cos(a) * r, 0.15 * s, math.sin(a) * r, (0.5 + rng:next() * 0.5) * s, (0.4 + rng:next() * 0.3) * s, (0.5 + rng:next() * 0.4) * s, if k % 2 == 0 then "rock" else "rock_dark", "Stone")
	end
	m.Parent = parent
end

local function shell(parent: Instance, at: CFrame, kind: number)
	if kind == 1 then
		-- a starfish: two crossed bars
		box(parent, at, 0, 0.06, 0, 0.9, 0.12, 0.25, "orange", "Starfish")
		box(parent, at * CFrame.Angles(0, math.rad(72), 0), 0, 0.06, 0, 0.9, 0.12, 0.25, "orange", "Starfish")
	elseif kind == 2 then
		box(parent, at, 0, 0.08, 0, 0.5, 0.16, 0.4, "pink", "Shell")
		box(parent, at, 0, 0.18, -0.05, 0.25, 0.08, 0.25, "cream", "Shell")
	else
		box(parent, at, 0, 0.08, 0, 0.4, 0.16, 0.4, "cream", "Shell")
	end
end

local function driftwood(parent: Instance, at: CFrame)
	box(parent, at, 0, 0.18, 0, 2.5, 0.35, 0.4, "wood", "Driftwood")
	box(parent, at, 0.9, 0.2, 0.3, 0.75, 0.25, 0.25, "wood_dark", "Branch")
end

local function seaweed(parent: Instance, at: CFrame)
	box(parent, at, 0, 0.05, 0, 0.75, 0.1, 0.25, "leaf_dark", "Seaweed")
	box(parent, at, 0.25, 0.05, 0.25, 0.25, 0.1, 0.5, "leaf_dark", "Seaweed")
end

local function tuft(parent: Instance, at: CFrame, flower: string?)
	box(parent, at, -0.1, 0.25, 0, 0.125, 0.5, 0.125, "leaf_dark", "Blade")
	box(parent, at, 0.12, 0.2, 0.08, 0.125, 0.4, 0.125, "leaf", "Blade")
	box(parent, at, 0, 0.3, -0.12, 0.125, 0.6, 0.125, "leaf_dark", "Blade")
	if flower then
		box(parent, at, 0, 0.7, -0.12, 0.25, 0.25, 0.25, flower, "Bloom")
	end
end

------------------------------------------------------------------ a plot's water
function StreetModels.road(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Road")
	local o = CFrame.new(origin)
	local x0, x1 = Street.LOT.x0, Street.LOT.x1
	-- the water: the lot's and the open sea's (animated by the pixel filter), far past the world's walls
	water(slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water"), 1)
	-- the seabed under it, as far as the world's walls
	floor(m, o, x0, Street.LOT.z0, x1, Street.SEA.z1, Street.SEABED_Y, "Seabed")
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the coast
-- An island's layers from a cell source: layer(x, z) (Street's codes) and dist(x, z) (the coast distance at the
-- cell's centre), over the cells of b. Grass in two tones (a darker rim and darker patches), the sand beach, the wet
-- sand, the foam, the shallows; each a step lower than the one inside it.
local function coast(m: Instance, o: CFrame, b: Rect, layer: (x: number, z: number) -> number, dist: (x: number, z: number) -> number)
	local G, S, W, F = Street.GRASS, Street.SAND, Street.WET, Street.FOAM
	local function any(x: number, z: number): boolean
		return layer(x, z) ~= Street.SEA_CELL
	end
	local function beach(x: number, z: number): boolean
		local l = layer(x, z)
		return l == G or l == S or l == W
	end
	local function dry(x: number, z: number): boolean
		local l = layer(x, z)
		return l == G or l == S
	end
	local function dark(x: number, z: number): boolean
		if dist(x, z) > -0.9 then
			return true
		end
		local n = math.sin(x * 0.31 + z * 0.17) + math.sin(x * 0.11 - z * 0.29 + 1.3) + math.sin(z * 0.43 + 2.1) * 0.4
		return n > 1.05
	end
	for _, r in greedy(b, any) do
		water(slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.SHALLOW_Y, 0.5, "shallow", "Shallows"), 2)
	end
	for _, r in greedy(b, function(x, z)
		return layer(x, z) == F
	end) do
		water(slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.FOAM_Y, 0.2, "foam", "Foam"), 3)
		-- (the step out of the sea: halfway from the seabed up to the wet sand)
		floor(m, o, r.x0, r.z0, r.x1, r.z1, (Street.SEABED_Y + Street.WET_Y) / 2, "Shelf")
	end
	for _, r in greedy(b, beach) do
		slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.WET_Y, 0.9, "sand_dark", "WetSand")
	end
	for _, r in greedy(b, dry) do
		slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.SAND_Y, 0.15, "sand", "Beach")
	end
	for _, r in greedy(b, function(x, z)
		return layer(x, z) == G and not dark(x, z)
	end) do
		slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.LAWN_Y, 0.12, "grass", "Lawn")
	end
	for _, r in greedy(b, function(x, z)
		return layer(x, z) == G and dark(x, z)
	end) do
		slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.LAWN_Y, 0.12, "grass_dark", "Lawn")
	end
end

------------------------------------------------------------------ an island
local function sign(m: Instance, at: CFrame, words: string?)
	local s = Blocks.model(nil, "PlotSign")
	box(s, at, -1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	box(s, at, 1.1, 1.2, 0, 0.25, 2.4, 0.25, "wood_dark", "Post")
	local board = box(s, at, 0, 2.05, 0.1, 2.75, 1.25, 0.25, "wood", "SignBoard")
	if words then
		board:SetAttribute("Words", words)
	end
	box(s, at, 0, 2.05, 0.2, 2.25, 0.75, 0.25, "paper", "Face")
	box(s, at, 0, 2.75, 0.1, 3, 0.15, 0.4, "wood_dark", "Top")
	s.Parent = m
end

-- The plaza round the campfire: a ring of sand on the grass, a ring of stones round the fire's logs and flames, three
-- log seats, a flagpole with the island's pennant and two torches.
local function plaza(m: Instance, o: CFrame)
	local c = Street.CENTER
	local function inRing(x: number, z: number): boolean
		local dx, dz = x + 0.5 - c.x, z + 0.5 - c.z
		return dx * dx + dz * dz <= 12.5
	end
	for _, r in greedy({ x0 = c.x - 5, z0 = c.z - 5, x1 = c.x + 4, z1 = c.z + 4 }, inRing) do
		slab(m, o, r.x0, r.z0, r.x1, r.z1, Street.LAWN_Y + 0.04, 0.1, "sand_dark", "PlazaSand")
	end
	local at = o * CFrame.new(c.x, Street.LAWN_Y + 0.04, c.z)
	for k = 0, 7 do
		local a = k * math.pi / 4
		box(m, at, math.cos(a) * 1.25, 0.2, math.sin(a) * 1.25, 0.6, 0.4, 0.6, if k % 2 == 0 then "rock" else "rock_dark", "FireStone")
	end
	box(m, at * CFrame.Angles(0, math.rad(30), 0), 0, 0.2, 0, 1.6, 0.35, 0.35, "wood_dark", "Log")
	box(m, at * CFrame.Angles(0, math.rad(-40), 0), 0, 0.3, 0, 1.6, 0.35, 0.35, "wood", "Log")
	box(m, at, 0, 0.65, 0, 0.75, 0.6, 0.75, "orange", "Flame", true)
	box(m, at, 0, 1.1, 0, 0.4, 0.5, 0.4, "yellow", "Flame", true)
	box(m, at, 0.2, 0.9, -0.2, 0.25, 0.3, 0.25, "berry_red", "Ember", true)
	for _, s in { { -2.75, 0.5, 90 }, { 2.75, 0.25, 90 }, { 0, -2.75, 0 } } do
		box(m, at * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0), 0, 0.3, 0, 2.2, 0.55, 0.6, "wood", "Seat")
		box(m, at * CFrame.new(s[1], 0, s[2]) * CFrame.Angles(0, math.rad(s[3]), 0), 0, 0.45, 0, 2.25, 0.1, 0.4, "wood_dark", "Bark")
	end
	-- the flagpole and its pennant
	box(m, at, 3, 2.5, -3, 0.25, 5, 0.25, "wood_dark", "FlagPole")
	ball(m, at, 3, 5.1, -3, 0.4, "gold")
	box(m, at, 3, 4.4, -2.1, 0.1, 1, 1.75, "berry_red", "Pennant")
	box(m, at, 3, 4.4, -1.5, 0.1, 0.5, 0.5, "white", "Mark")
	-- two tiki torches at the plaza's south edge
	for _, tx in { -2.5, 2.5 } do
		local tf = o * CFrame.new(tx, Street.LAWN_Y, Street.PLAZA.z1 - 0.5)
		box(m, tf, 0, 1.1, 0, 0.25, 2.2, 0.25, "wood_dark", "TorchPole")
		box(m, tf, 0, 2.3, 0, 0.5, 0.35, 0.5, "wood", "TorchCup")
		box(m, tf, 0, 2.6, 0, 0.3, 0.35, 0.3, "orange", "TorchFlame", true)
	end
end

-- Things round the coast, never on a cell a building may use: palms at the grass's edge, rocks in the shallows,
-- shells and starfish on the beach, driftwood, seaweed on the wet sand, tufts and flowers on the grass's rim.
local function scatter(m: Instance, o: CFrame, tier: number, b: Rect, rng: Rng)
	local cells: { [number]: { { x: number, z: number } } } = { {}, {}, {}, {}, {} }
	local rim: { { x: number, z: number } } = {}
	local sx, sz = Street.sign(tier)
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			local l = Street.layer(tier, x, z)
			-- (clear round the island's sign)
			local nearSign = math.abs(x + 0.5 - sx) < 3 and math.abs(z + 0.5 - sz) < 2.5
			if l ~= Street.SEA_CELL and not nearSign then
				table.insert(cells[l], { x = x, z = z })
				if l == Street.GRASS and not Street.buildable(tier, x, z) then
					table.insert(rim, { x = x, z = z })
				end
			end
		end
	end
	-- (the sign's spot taken first, wide: no palm leans in front of it)
	local taken: { { x: number, z: number, r: number } } = { { x = sx, z = sz, r = 5 } }
	local function clear(x: number, z: number, r: number): boolean
		for _, t in taken do
			if (t.x - x) ^ 2 + (t.z - z) ^ 2 < (t.r + r) ^ 2 then
				return false
			end
		end
		return true
	end
	local function pick(list: { { x: number, z: number } }, n: number, r: number, fn: (x: number, z: number) -> ())
		local done, tries = 0, 0
		while done < n and tries < n * 12 and #list > 0 do
			tries += 1
			local c = list[rng:int(1, #list)]
			local x, z = c.x + 0.5, c.z + 0.5
			if clear(x, z, r) then
				table.insert(taken, { x = x, z = z, r = r })
				fn(x, z)
				done += 1
			end
		end
	end
	local isle = Street.isle(tier)
	-- palms on the sand at the grass's edge, leaning out to sea
	local palmsAt: { { x: number, z: number } } = {}
	for _, c in cells[Street.SAND] do
		if Street.cellDist(tier, c.x, c.z) < 1.2 then
			table.insert(palmsAt, c)
		end
	end
	pick(palmsAt, 3 + tier * 2, 4, function(x, z)
		local lean = math.atan2(-(z - isle.cz), x - isle.cx)
		palm(m, o * CFrame.new(x, Street.SAND_Y, z), 0.9 + rng:next() * 0.3, lean)
	end)
	pick(cells[Street.SHALLOW], 3 + tier * 2, 2.5, function(x, z)
		rocks(m, o * CFrame.new(x, Street.SHALLOW_Y - 0.2, z) * CFrame.Angles(0, rng:next() * 6, 0), 0.8 + rng:next() * 0.6, rng)
	end)
	pick(cells[Street.FOAM], 2 + tier, 2, function(x, z)
		rocks(m, o * CFrame.new(x, Street.FOAM_Y - 0.25, z) * CFrame.Angles(0, rng:next() * 6, 0), 0.6 + rng:next() * 0.3, rng)
	end)
	pick(cells[Street.SAND], 6 + tier * 4, 1, function(x, z)
		shell(m, o * CFrame.new(x, Street.SAND_Y, z) * CFrame.Angles(0, rng:next() * 6, 0), rng:int(1, 3))
	end)
	pick(cells[Street.SAND], 1 + tier, 2.5, function(x, z)
		driftwood(m, o * CFrame.new(x, Street.SAND_Y, z) * CFrame.Angles(0, rng:next() * 6, 0))
	end)
	pick(cells[Street.WET], 4 + tier * 3, 1, function(x, z)
		seaweed(m, o * CFrame.new(x, Street.WET_Y, z) * CFrame.Angles(0, rng:next() * 6, 0))
	end)
	local blooms = { "pink", "yellow", "white", "purple", "berry_red" }
	pick(rim, 10 + tier * 6, 0.9, function(x, z)
		tuft(m, o * CFrame.new(x, Street.LAWN_Y, z), if rng:chance(0.45) then blooms[rng:int(1, #blooms)] else nil)
	end)
end

function StreetModels.land(parent: Instance, origin: Vector3, tier: number): Model
	local m = Blocks.model(nil, "Land")
	local o = CFrame.new(origin)
	local b = Street.cellBounds(tier)
	local lot = Street.LOT
	-- the cells inside the lot (a neighbour's water is theirs)
	local cb = { x0 = math.max(b.x0, lot.x0), z0 = math.max(b.z0, lot.z0), x1 = math.min(b.x1, lot.x1 - 1), z1 = math.min(b.z1, lot.z1 - 1) }
	coast(m, o, cb, function(x, z)
		return Street.layer(tier, x, z)
	end, function(x, z)
		return Street.cellDist(tier, x, z)
	end)
	local rng = Util.newRng(tier * 7919 + 13)
	plaza(m, o)
	scatter(m, o, tier, cb, rng)
	-- the island's sign on its south beach (tapped: the island's card; its name floats over it)
	local sx, sz = Street.sign(tier)
	sign(m, o * CFrame.new(sx, Street.SAND_Y, sz), "island")
	Blocks.windy(m) -- palms and tufts sway, the plaza's pennant ripples
	m.Parent = parent
	return m
end

------------------------------------------------------------------ an unclaimed plot
function StreetModels.emptyLot(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "EmptyLot")
	local o = CFrame.new(origin)
	-- a little sandbar (a wobbly oval of sand, its foam and shallows)
	local cx, cz, rx, rz = 0, 12, 6, 3.5
	local function dist(x: number, z: number): number
		local dx, dz = x + 0.5 - cx, z + 0.5 - cz
		local a = math.atan2(dz, dx)
		local er = 1 / math.sqrt((math.cos(a) / rx) ^ 2 + (math.sin(a) / rz) ^ 2)
		return math.sqrt(dx * dx + dz * dz) - er * (1 + 0.1 * math.sin(3 * a + 1)) - 0.01
	end
	local function layer(x: number, z: number): number
		local d = dist(x, z)
		-- no grass on a sandbar: what would be grass is sand
		local l = Street.layerAt(d)
		return if l == Street.GRASS then Street.SAND else l
	end
	coast(m, o, { x0 = -16, z0 = 0, x1 = 15, z1 = 24 }, layer, dist)
	palm(m, o * CFrame.new(-2.5, Street.SAND_Y, 12), 1, 2.6)
	sign(m, o * CFrame.new(1.5, Street.SAND_Y, 13.5), "empty")
	rocks(m, o * CFrame.new(5, Street.SHALLOW_Y - 0.2, 10), 0.9, Util.newRng(3))
	shell(m, o * CFrame.new(3, Street.SAND_Y, 11.5), 1)
	shell(m, o * CFrame.new(-0.5, Street.SAND_Y, 13.8), 2)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the sea's ends and the world's walls
-- The sea past the row's ends (the seabed under it as far as the walls), a sandbar with a palm beyond each wall, and
-- the invisible walls round the world.
function StreetModels.ends(parent: Instance): Model
	local m = Blocks.model(nil, "StreetEnds")
	local b = Street.bounds()
	local o = CFrame.new()
	local first = Street.origin(1) + Street.LOT.x0
	local last = Street.origin(Street.MAX) + Street.LOT.x1
	for _, e in { { b.x0, first }, { last, b.x1 } } do
		local west = e[1] == b.x0
		local x0 = if west then e[1] - Street.END_FAR else e[1]
		local x1 = if west then e[2] else e[2] + Street.END_FAR
		water(slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water"), 1)
		-- the seabed from the row's end to the world's wall
		local bx0 = if west then b.x0 else last
		local bx1 = if west then first else b.x1
		floor(m, o, bx0, Street.LOT.z0, bx1, Street.SEA.z1, Street.SEABED_Y, "Seabed")
		local hx = if west then b.x0 + 1 else b.x1 - 1
		local sx = if west then hx - 12 else hx + 12
		local function dist(x: number, z: number): number
			local dx, dz = x + 0.5 - sx, z + 0.5 - 6
			return math.sqrt((dx / 1.6) ^ 2 + dz * dz) - 3
		end
		local function layer(x: number, z: number): number
			local l = Street.layerAt(dist(x, z))
			return if l == Street.GRASS then Street.SAND else l
		end
		coast(m, o, { x0 = math.floor(sx) - 16, z0 = -8, x1 = math.floor(sx) + 15, z1 = 20 }, layer, dist)
		palm(m, o * CFrame.new(sx, Street.SAND_Y, 6), 1.2, if west then 3.1 else 0)
	end
	-- the world's outer walls
	local function outer(wx0: number, z0: number, wx1: number, z1: number)
		local w = Blocks.part(m, {
			size = Vector3.new(math.max(1, wx1 - wx0), WALL_H, math.max(1, z1 - z0)),
			cf = CFrame.new((wx0 + wx1) / 2, WALL_H / 2 - 1, (z0 + z1) / 2),
			color = "white",
			name = "Bound",
			transparency = 1,
			query = false,
		})
		w.CastShadow = false
		w.CollisionGroup = "Bounds"
	end
	outer(b.x0 - 1, b.z0 - 1, b.x1 + 1, b.z0)
	outer(b.x0 - 1, b.z1, b.x1 + 1, b.z1 + 1)
	outer(b.x0 - 1, b.z0, b.x0, b.z1)
	outer(b.x1, b.z0, b.x1 + 1, b.z1)
	m.Parent = parent
	return m
end

return StreetModels
