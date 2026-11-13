--!strict
-- The sea from parts (GAME_DESIGN 8; docs/ARCHITECTURE.md 6; Data/Street). Roblox module (server: PlotService builds
-- every plot's stretch at start and each plot's island as players come and go).
--   road(parent, origin)          a plot's stretch: the water of its lot and the open sea, the boardwalk of planks on
--                                 its posts with a rope rail and lanterns, the pier with its bollards, crates and the
--                                 old boat moored at its end (every plot, occupied or not, so the boardwalk
--                                 runs on unbroken)
--   land(parent, origin, tier)    an occupied plot: the island (Data/Street's coast: grass in two tones, the sand
--                                 beach, the wet sand at the waterline, a ring of foam, the light shallows), the plaza
--                                 with its campfire, log seats and flag, stepping stones down to the jetty, the
--                                 island's sign (its board named "SignBoard") and the mailbox on the boardwalk, palms,
--                                 rocks, shells, starfish, driftwood, seaweed and flowers round the coast (never where a
--                                 building may stand), and the invisible walls that follow the coast and the jetty
--   emptyLot(parent, origin)      an unclaimed plot: open water and a little sandbar with a palm and a sign
--   ends(parent)                  the sea at both ends of the boardwalk and the invisible walls round the world
-- The island's layers are whole-stud cells merged into as few boxes as they make (greedy rectangles), each layer a
-- little lower than the one inside it, so the coast steps down to the sea. The sea, the shallows and the foam carry a
-- "PixelWater" attribute (1, 2, 3): the pixel filter animates them. Walls are invisible and never queried (the
-- renderer's rays pass through), 40 studs high: far higher than a jump (nobody hops the coast onto the sea).
local Street = require(script.Parent.Parent.Data.Street)
local Util = require(script.Parent.Parent.Logic.Util)
local Types = require(script.Parent.Parent.Types)
local Blocks = require(script.Parent.Blocks)
local BoatSpec = require(script.Parent.BoatSpec)

local StreetModels = {}

local BOARD_Y = -0.3
local WALL_H = 40 -- far over a jump (Tuning.JumpHeight): nobody hops the coast onto the sea

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

local function water(p: BasePart, kind: number): BasePart
	p:SetAttribute("PixelWater", kind)
	return p
end

-- An invisible wall (plot-local x0..x1, z0..z1) the founder can't walk through.
local function wall(parent: Instance, o: CFrame, x0: number, z0: number, x1: number, z1: number)
	local w = Blocks.part(parent, {
		size = Vector3.new(math.max(0.5, x1 - x0), WALL_H, math.max(0.5, z1 - z0)),
		cf = o * CFrame.new((x0 + x1) / 2, WALL_H / 2 - 1, (z0 + z1) / 2),
		color = "white",
		name = "Bound",
		transparency = 1,
		query = false,
	})
	w.CastShadow = false
	w.CollisionGroup = "Bounds"
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
local function lantern(parent: Instance, at: CFrame)
	local m = Blocks.model(nil, "Lantern")
	box(m, at, 0, 1.5, 0, 0.5, 3, 0.5, "wood_dark", "Pole")
	box(m, at, 0, 0.125, 0, 0.75, 0.25, 0.75, "wood_dark", "Foot")
	box(m, at, 0, 3.25, 0, 1, 0.25, 1, "wood_dark", "Cap")
	box(m, at, 0, 3.5, 0, 0.5, 0.25, 0.5, "wood_dark", "Knob")
	box(m, at, 0, 2.75, 0, 0.75, 0.75, 0.75, "yellow", "Light", true)
	for _, c in { { -0.375, -0.375 }, { 0.375, -0.375 }, { -0.375, 0.375 }, { 0.375, 0.375 } } do
		box(m, at, c[1], 2.75, c[2], 0.125, 0.75, 0.125, "black", "Frame")
	end
	m.Parent = parent
end

-- A palm: a curving trunk of rings leaning `lean` (radians about Y: the way it leans), a crown of fronds, coconuts.
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

-- The boat moored beside the pier (Models/BoatSpec at `level`, 1 from `road`: scenery; its bow to the south). Its
-- flags carry PixelWind 2 (they ripple in the pixel filter's wind).
function StreetModels.boat(parent: Instance, origin: Vector3, level: number): Model
	local m = Blocks.model(nil, "Boat")
	m:SetAttribute("Level", level)
	local mx, mz = BoatSpec.moor(level)
	local at = CFrame.new(origin) * CFrame.new(mx, Street.WATER_Y + BoatSpec.deckOverWater(level), mz)
	for _, sp in BoatSpec.parts(level) do
		local cf = at * sp.cf
		local p: BasePart
		if sp.shape == "CylY" then
			p = Blocks.cylY(m, sp.size.X, sp.size.Y, cf, sp.color)
		else
			p = Blocks.part(m, { size = sp.size, cf = cf, color = sp.color, name = sp.name, shape = if sp.shape == "Wedge" then "Wedge" else nil, neon = sp.neon })
		end
		p.Name = sp.name
		p.CanCollide = false -- (scenery beside the pier: nothing to snag on)
		if sp.wind then
			p:SetAttribute("PixelWind", sp.wind)
		end
	end
	m.Parent = parent
	return m
end

local function crate(parent: Instance, at: CFrame, s: number)
	box(parent, at, 0, 0.5 * s, 0, s, s, s, "wood", "Crate")
	box(parent, at, 0, 0.5 * s, 0, s + 0.05, 0.2 * s, s + 0.05, "wood_dark", "Strap")
	box(parent, at, 0, s + 0.02, 0, 0.8 * s, 0.05, 0.15 * s, "wood_dark", "Lid")
end

local function barrel(parent: Instance, at: CFrame)
	Blocks.cylY(parent, 1.0, 1.2, at * CFrame.new(0, 0.6, 0), "wood")
	Blocks.cylY(parent, 1.08, 0.12, at * CFrame.new(0, 0.3, 0), "steel_dark")
	Blocks.cylY(parent, 1.08, 0.12, at * CFrame.new(0, 0.9, 0), "steel_dark")
end

------------------------------------------------------------------ a plot's stretch
function StreetModels.road(parent: Instance, origin: Vector3): Model
	local m = Blocks.model(nil, "Road")
	local o = CFrame.new(origin)
	local x0, x1 = Street.LOT.x0, Street.LOT.x1
	-- the water: the lot's and the open sea's (animated by the pixel filter)
	water(slab(m, o, x0, Street.LOT.z0 - Street.FAR, x1, Street.BOARD.z0, Street.WATER_Y, 1, "water", "Water"), 1)
	water(slab(m, o, x0, Street.BOARD.z1, x1, Street.SEA.z1 + Street.FAR, Street.WATER_Y, 1, "water", "Water"), 1)
	water(slab(m, o, x0, Street.BOARD.z0, x1, Street.BOARD.z1, Street.WATER_Y, 1, "water", "Water"), 1)
	-- the boardwalk: planks across it in three tones, beams under its edges, posts down into the water
	local B0, B1 = Street.BOARD.z0, Street.BOARD.z1
	slab(m, o, x0, B0 + 0.25, x1, B1 - 0.25, BOARD_Y - 0.25, 0.5, "wood_dark", "Beam")
	local tones = { "wood", "wood", "desk", "wood" }
	local rng = Util.newRng(7)
	local x = x0
	while x < x1 do
		local w = math.min(1, x1 - x)
		slab(m, o, x + 0.05, B0, x + w - 0.05, B1, BOARD_Y, 0.25, tones[rng:int(1, #tones)], "Plank")
		x += w
	end
	slab(m, o, x0, B0, x1, B0 + 0.25, BOARD_Y - 0.25, 0.25, "wood_dark", "Edge")
	slab(m, o, x0, B1 - 0.25, x1, B1, BOARD_Y - 0.25, 0.25, "wood_dark", "Edge")
	x = x0 + 2
	while x < x1 do
		for _, z in { B0 + 0.25, B1 - 0.25 } do
			box(m, o, x, (BOARD_Y + Street.WATER_Y) / 2 - 0.4, z, 0.5, BOARD_Y - Street.WATER_Y + 0.7, 0.5, "wood_dark", "Post")
		end
		x += 4
	end
	-- the sea side's rope rail: a short post every 4 studs (but at the pier), a rope between
	local pr = Street.pier()
	x = x0 + 2
	while x < x1 do
		if x < pr.x0 - 0.5 or x > pr.x1 + 0.5 then
			box(m, o, x, BOARD_Y + 0.6, B1 - 0.25, 0.25, 1.2, 0.25, "wood_dark", "RailPost")
		end
		x += 4
	end
	slab(m, o, x0, B1 - 0.32, pr.x0, B1 - 0.18, BOARD_Y + 1.0, 0.1, "sand_dark", "Rope")
	slab(m, o, pr.x1, B1 - 0.32, x1, B1 - 0.18, BOARD_Y + 1.0, 0.1, "sand_dark", "Rope")
	for _, lx in Street.LAMPS do
		lantern(m, o * CFrame.new(lx, BOARD_Y, B1 - 0.6))
	end
	-- the pier: planks along it, posts, bollards at its end, crates and a barrel, its boat
	slab(m, o, pr.x0, pr.z0, pr.x1, pr.z1, BOARD_Y - 0.25, 0.5, "wood_dark", "PierBeam")
	local z = pr.z0
	while z < pr.z1 do
		slab(m, o, pr.x0, z + 0.05, pr.x1, math.min(z + 1, pr.z1) - 0.05, BOARD_Y, 0.25, tones[rng:int(1, #tones)], "Pier")
		z += 1
	end
	for zz = pr.z0 + 2, pr.z1, 3 do
		box(m, o, pr.x0 + 0.25, (BOARD_Y + Street.WATER_Y) / 2 - 0.4, zz, 0.5, BOARD_Y - Street.WATER_Y + 0.7, 0.5, "wood_dark", "Post")
		box(m, o, pr.x1 - 0.25, (BOARD_Y + Street.WATER_Y) / 2 - 0.4, zz, 0.5, BOARD_Y - Street.WATER_Y + 0.7, 0.5, "wood_dark", "Post")
	end
	-- the pier's things (bollards, crates, a barrel, a coil of rope) and its boat are scenery: nothing to snag on
	local props = Instance.new("Folder")
	props.Name = "PierProps"
	for _, bx in { pr.x0 + 0.5, pr.x1 - 0.5 } do
		Blocks.cylY(props, 0.5, 0.8, o * CFrame.new(bx, BOARD_Y + 0.4, pr.z1 - 0.5), "steel_dark")
		Blocks.cylY(props, 0.7, 0.15, o * CFrame.new(bx, BOARD_Y + 0.85, pr.z1 - 0.5), "steel_dark")
	end
	crate(props, o * CFrame.new(pr.x0 + 0.75, BOARD_Y, pr.z0 + 3), 1)
	crate(props, o * CFrame.new(pr.x0 + 0.65, BOARD_Y + 1, pr.z0 + 3.1), 0.7)
	barrel(props, o * CFrame.new(pr.x1 - 0.75, BOARD_Y, pr.z0 + 5))
	Blocks.cylY(props, 0.9, 0.2, o * CFrame.new(pr.x1 - 0.7, BOARD_Y + 0.1, pr.z1 - 2.5), "sand_dark") -- a coil of rope
	for _, d in props:GetChildren() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	props.Parent = m
	StreetModels.boat(m, origin, 1)
	-- walls: the boardwalk's sea side (but the pier), the pier's sides and end
	wall(m, o, x0, B1, pr.x0, B1 + 0.5)
	wall(m, o, pr.x1, B1, x1, B1 + 0.5)
	wall(m, o, pr.x0 - 0.5, pr.z0, pr.x0, pr.z1)
	wall(m, o, pr.x1, pr.z0, pr.x1 + 0.5, pr.z1)
	wall(m, o, pr.x0 - 0.5, pr.z1, pr.x1 + 0.5, pr.z1 + 0.5)
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

-- Invisible walls round the walkable cells (walk(x, z)): a wall on every edge between a walkable cell and one that is
-- not, runs along a row or a column merged into one wall.
local function coastWalls(m: Instance, o: CFrame, b: Rect, walk: (x: number, z: number) -> boolean)
	-- horizontal edges: the line z (between cells z - 1 and z), x runs
	for z = b.z0, b.z1 + 1 do
		local run: number? = nil
		local side = 0
		for x = b.x0, b.x1 + 1 do
			local a, c = walk(x, z - 1), walk(x, z)
			local s = if a and not c then 1 elseif c and not a then -1 else 0
			if s ~= side or s == 0 then
				if run and side ~= 0 then
					-- the wall stands on the side away from the walkable cell
					if side == 1 then
						wall(m, o, run, z, x, z + 0.5)
					else
						wall(m, o, run, z - 0.5, x, z)
					end
				end
				run = if s ~= 0 then x else nil
				side = s
			end
		end
	end
	-- vertical edges: the line x (between cells x - 1 and x), z runs
	for x = b.x0, b.x1 + 1 do
		local run: number? = nil
		local side = 0
		for z = b.z0, b.z1 + 1 do
			local a, c = walk(x - 1, z), walk(x, z)
			local s = if a and not c then 1 elseif c and not a then -1 else 0
			if s ~= side or s == 0 then
				if run and side ~= 0 then
					if side == 1 then
						wall(m, o, x, run, x + 0.5, z)
					else
						wall(m, o, x - 0.5, run, x, z)
					end
				end
				run = if s ~= 0 then z else nil
				side = s
			end
		end
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

local function mailbox(m: Instance, at: CFrame)
	box(m, at, 0, 0.8, 0, 0.25, 1.6, 0.25, "wood_dark", "MailPost")
	box(m, at, 0, 1.85, 0, 0.75, 0.75, 1.25, "berry_red", "Mailbox")
	box(m, at, 0, 2.3, 0, 0.75, 0.15, 1.25, "berry_red", "Lid")
	box(m, at, 0, 1.85, 0.66, 0.5, 0.5, 0.05, "black", "Slot")
	box(m, at, 0.45, 2.1, -0.2, 0.25, 0.5, 0.25, "yellow", "Flag")
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
	-- two tiki torches at the path's start
	for _, tx in { -2.5, 2.5 } do
		local tf = o * CFrame.new(tx, Street.LAWN_Y, Street.PLAZA.z1 - 0.5)
		box(m, tf, 0, 1.1, 0, 0.25, 2.2, 0.25, "wood_dark", "TorchPole")
		box(m, tf, 0, 2.3, 0, 0.5, 0.35, 0.5, "wood", "TorchCup")
		box(m, tf, 0, 2.6, 0, 0.3, 0.35, 0.3, "orange", "TorchFlame", true)
	end
end

-- The stepping stones from the plaza to the shore, and the jetty of planks over the water to the boardwalk.
local function pathAndJetty(m: Instance, o: CFrame, tier: number, rng: Rng)
	local jt = Street.jetty(tier)
	local z = Street.PLAZA.z1 + 0.5
	local k = 0
	while z < jt.z0 do
		local sx = if k % 2 == 0 then -0.6 else 0.5
		local top = if Street.layer(tier, 0, math.floor(z)) == Street.GRASS then Street.LAWN_Y + 0.06 else Street.SAND_Y + 0.06
		slab(m, o, sx - 0.75 + rng:next() * 0.2, z, sx + 0.75, z + 1, top, 0.15, if k % 3 == 0 then "rock" else "pavement", "Stone")
		z += 1.5
		k += 1
	end
	-- the jetty: a beam, planks across, posts both sides, a rope rail on posts
	local jz0 = jt.z0
	slab(m, o, jt.x0 + 0.25, jz0, jt.x1 - 0.25, jt.z1, BOARD_Y - 0.25, 0.4, "wood_dark", "JettyBeam")
	z = jz0
	while z < jt.z1 do
		slab(m, o, jt.x0, z + 0.05, jt.x1, math.min(z + 1, jt.z1) - 0.05, BOARD_Y, 0.25, if rng:chance(0.3) then "desk" else "wood", "JettyPlank")
		z += 1
	end
	for pz = jz0 + 1, jt.z1, 2.5 do
		for _, px in { jt.x0 + 0.2, jt.x1 - 0.2 } do
			box(m, o, px, (BOARD_Y + Street.WATER_Y) / 2 - 0.4 + 0.5, pz, 0.4, BOARD_Y - Street.WATER_Y + 1.7, 0.4, "wood_dark", "JettyPost")
		end
	end
	slab(m, o, jt.x0 + 0.1, jz0 + 1, jt.x0 + 0.3, jt.z1, BOARD_Y + 1.0, 0.1, "sand_dark", "Rope")
	slab(m, o, jt.x1 - 0.3, jz0 + 1, jt.x1 - 0.1, jt.z1, BOARD_Y + 1.0, 0.1, "sand_dark", "Rope")
	return jt
end

-- Things round the coast, never on a cell a building may use: palms at the grass's edge, rocks in the shallows,
-- shells and starfish on the beach, driftwood, seaweed on the wet sand, tufts and flowers on the grass's rim.
local function scatter(m: Instance, o: CFrame, tier: number, b: Rect, rng: Rng, jt: Rect)
	local cells: { [number]: { { x: number, z: number } } } = { {}, {}, {}, {}, {} }
	local rim: { { x: number, z: number } } = {}
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			local l = Street.layer(tier, x, z)
			local nearJetty = x >= jt.x0 - 2 and x < jt.x1 + 2 and z >= Street.PLAZA.z1
			if l ~= Street.SEA_CELL and not nearJetty then
				table.insert(cells[l], { x = x, z = z })
				if l == Street.GRASS and not Street.buildable(tier, x, z) then
					table.insert(rim, { x = x, z = z })
				end
			end
		end
	end
	local taken: { { x: number, z: number, r: number } } = {}
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
	local jt = pathAndJetty(m, o, tier, rng)
	scatter(m, o, tier, cb, rng, jt)
	local sx, sz = Street.sign()
	sign(m, o * CFrame.new(sx, BOARD_Y, sz), "island")
	local mx, mz = Street.mailbox()
	mailbox(m, o * CFrame.new(mx, BOARD_Y, mz))
	-- walls round the walkable sand and grass, the jetty's sides, the boardwalk's island side (but the jetty)
	local function walk(x: number, z: number): boolean
		if z >= Street.BOARD.z0 then
			return true
		end
		if x >= jt.x0 and x < jt.x1 and z >= jt.z0 then
			return true
		end
		return Street.walkable(tier, x, z)
	end
	coastWalls(m, o, { x0 = cb.x0 - 1, z0 = cb.z0 - 1, x1 = cb.x1 + 1, z1 = Street.BOARD.z0 - 1 }, walk)
	wall(m, o, lot.x0, Street.BOARD.z0 - 0.5, math.min(cb.x0 - 1, jt.x0), Street.BOARD.z0)
	wall(m, o, math.max(cb.x1 + 2, jt.x1), Street.BOARD.z0 - 0.5, lot.x1, Street.BOARD.z0)
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
	-- the boardwalk's island side is closed here
	wall(m, o, Street.LOT.x0, Street.BOARD.z0 - 0.5, Street.LOT.x1, Street.BOARD.z0)
	m.Parent = parent
	return m
end

------------------------------------------------------------------ the sea's ends and the world's walls
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
		-- the boardwalk runs on to a last post and lantern (this end's stretch only: past the first plot on the west,
		-- past the last on the east; the east's once ran from the first plot, its walls across every pier and jetty)
		local bx0 = if west then b.x0 else last
		local bx1 = if west then first else b.x1
		slab(m, o, bx0, Street.BOARD.z0, bx1, Street.BOARD.z1, BOARD_Y, 0.5, "wood", "Boardwalk")
		local hx = if west then b.x0 + 1 else b.x1 - 1
		lantern(m, o * CFrame.new(hx, BOARD_Y, Street.BOARD.z0 + 0.5))
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
		wall(m, o, bx0, Street.BOARD.z0 - 0.5, bx1, Street.BOARD.z0)
		wall(m, o, bx0, Street.BOARD.z1, bx1, Street.BOARD.z1 + 0.5)
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
