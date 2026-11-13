--!strict
-- The paths and the water tiles (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
--
-- A path is a 2 x 2 tile, painted in long runs and boxes. Each one either covers its whole square or keeps the same
-- gap at every edge, so tiles side by side join up with no seam, and its small things (grit, shells, leaves,
-- flowers, stars) move about by the tile's hash so a long run never repeats. Tops stay at about 0.2 (the lawn's own
-- top is at 0.065); only the meadow's tufts of grass stand a little taller.
--
-- A water tile gets its neighbours in lvl: mask = lvl - 1, north 1 (-Z), east 2 (+X), south 4 (+Z), west 8 (-X), set
-- where the tile on that side is water too. The water covers the whole tile, a bank runs only along the sides with
-- no water next to it, and a block rounds the corner where two banks meet, so a river reads as one body of water.
--
-- At most 8 parts a tile: an island can hold 1,200 of them.
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

-- A box whose top is at height t (every part is 0.25 thick, so it sits 0.125 lower).
local function top(m: Model, f: CFrame, x: number, z: number, w: number, d: number, t: number, color: string, name: string?): BasePart
	return Parts.box(m, f, x, t - 0.125, z, w, 0.25, d, color, name)
end

-- A number 0 .. 1 for the tile at f (k picks another one). Parts.hash steps evenly with k, so it is stirred again here.
local function rnd(f: CFrame, k: number): number
	local v = math.sin(Parts.hash(f, k) * 7919.13 + k * 3.71) * 43758.5453
	return v - math.floor(v)
end

-- A whole number 1 .. n for the tile at f.
local function pick(f: CFrame, k: number, n: number): number
	return math.min(n, 1 + math.floor(rnd(f, k) * n))
end

type Map = (x: number, z: number, w: number, d: number) -> (number, number, number, number)

-- One of the eight ways to mirror or turn a layout (by the tile's hash): maps a rectangle of the layout onto the tile.
local function orient(f: CFrame, k: number): Map
	local v = pick(f, k, 8) - 1
	local fx = if v % 2 == 1 then -1 else 1
	local fz = if (v // 2) % 2 == 1 then -1 else 1
	local swap = v >= 4
	return function(x: number, z: number, w: number, d: number)
		if swap then
			return z * fz, x * fx, d, w
		end
		return x * fx, z * fz, w, d
	end
end

-- n spots spread over the tile: n of the nine cells of a 3 x 3, each spot nudged up to `j` from its cell's middle.
local CELLS = { -0.6, 0, 0.6 }
local function scatter(f: CFrame, k: number, n: number, j: number?): { { number } }
	local order = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
	for i = 9, 2, -1 do
		local o = 1 + math.floor(rnd(f, k + i) * i)
		order[i], order[o] = order[o], order[i]
	end
	local jj = j or 0.15
	local out = {}
	for i = 1, n do
		local c = order[i] - 1
		table.insert(out, { CELLS[c % 3 + 1] + (rnd(f, k + 20 + i) * 2 - 1) * jj, CELLS[c // 3 + 1] + (rnd(f, k + 40 + i) * 2 - 1) * jj })
	end
	return out
end

------------------------------------------------------------------ paths
-- Soft sand: a pale slab, two darker wind ripples across it (each a dash and a second one a step over, so it bends),
-- now and then a shell or a pebble.
M.sandtrail = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "sand", "Path")
	for i = 1, 2 do
		local z = (if i == 1 then -0.45 else 0.4) + (rnd(f, 30 + i) * 2 - 1) * 0.12
		local x0 = -0.875 + rnd(f, 20 + i) * 0.5 -- where it starts (it is 1.25 long)
		local step = if rnd(f, 40 + i) < 0.5 then 0.25 else -0.25
		top(m, f, x0 + 0.375, z, 0.75, 0.25, 0.155, "sand_dark", "Ripple")
		top(m, f, x0 + 1, z + step, 0.5, 0.25, 0.155, "sand_dark", "Ripple")
	end
	local v = pick(f, 40, 5)
	if v <= 2 then
		local s = scatter(f, 50, 1)[1]
		top(m, f, s[1], s[2], 0.25, 0.25, 0.175, if v == 1 then "pink" else "rock", if v == 1 then "Shell" else "Pebble")
	end
end

-- Grey grit: a grey slab speckled with darker and paler stones.
M.gravel = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "rock", "Path")
	for i, s in scatter(f, 0, 7) do
		top(m, f, s[1], s[2], 0.25, 0.25, 0.16, if i <= 4 then "rock_dark" else "pavement", "Grit")
	end
end

-- Crushed shells: a pale slab with bright chips, some lying square and some on the slant.
local SHELLS = { "pink", "white", "coral", "cherry", "sand_dark", "white", "pink" }
M.shellpath = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "cream", "Path")
	for i, s in scatter(f, 0, 7, 0.12) do
		local c = SHELLS[pick(f, 50 + i, #SHELLS)]
		if rnd(f, 60 + i) < 0.5 then
			Parts.turned(m, f, s[1], 0.04, s[2], 0.25, 0.25, 0.25, math.pi / 4, c, "Shell")
		else
			top(m, f, s[1], s[2], 0.25, 0.25, 0.165, c, "Shell")
		end
	end
end

-- Boards side by side: three along each tile with dark gaps between, each with one joint at its own place (some
-- boards paler with age).
M.plankwalk = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.11, "wood_dark", "Path")
	for i, x in { -2 / 3, 0, 2 / 3 } do
		local a = 0.25 + 0.25 * pick(f, i, 4)
		local b = 1.75 - a
		top(m, f, x, -1 + a / 2, 0.5, a, 0.19, if rnd(f, 10 + i) < 0.2 then "sand_dark" else "wood", "Board")
		top(m, f, x, 1 - b / 2, 0.5, b, 0.19, if rnd(f, 20 + i) < 0.2 then "sand_dark" else "wood", "Board")
	end
end

-- Big flat stones with the grass showing between them: three layouts, each mirrored or turned by the hash.
local FLAGS: { { { number } } } = {
	{ { -0.375, -0.5, 1, 0.75 }, { 0.625, -0.5, 0.5, 0.75 }, { -0.625, 0.5, 0.5, 0.75 }, { 0.375, 0.5, 1, 0.75 } },
	{ { -0.375, 0, 1, 1.75 }, { 0.625, -0.5, 0.5, 0.75 }, { 0.625, 0.5, 0.5, 0.75 } },
	{ { -0.5, -0.5, 0.75, 0.75 }, { 0.5, -0.5, 0.75, 0.75 }, { 0, 0.5, 1.75, 0.75 } },
}
M.flagstone = function(m, f)
	local map = orient(f, 1)
	for i, s in FLAGS[pick(f, 2, #FLAGS)] do
		local x, z, w, d = map(s[1] + (rnd(f, 10 + i) * 2 - 1) * 0.06, s[2] + (rnd(f, 20 + i) * 2 - 1) * 0.06, s[3], s[4])
		local c = if rnd(f, 30 + i) < 0.2 then "rock" else "pavement"
		top(m, f, x, z, w, d, if i % 2 == 0 then 0.17 else 0.16, c, "Flagstone")
	end
end

-- Round stones on dark grit: four big ones (a worn one smaller now and then), a small one where they meet, chips at
-- the edges.
local COBBLES = { "rock", "pavement", "rock", "steel", "rock_dark" }
M.cobble = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "road", "Path")
	for i, c in { { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } } do
		local x, z = c[1] + (rnd(f, i) * 2 - 1) * 0.06, c[2] + (rnd(f, 10 + i) * 2 - 1) * 0.06
		local small = rnd(f, 40 + i) < 0.2
		Parts.cyl(m, f, x, if small then 0.055 else 0.065, z, if small then 0.5 else 0.75, 0.25, COBBLES[pick(f, 20 + i, #COBBLES)], "Cobble")
	end
	Parts.cyl(m, f, 0, 0.055, 0, 0.5, 0.25, "rock_dark", "Cobble")
	local edges = { { 0, -0.875 }, { 0.875, 0 }, { 0, 0.875 }, { -0.875, 0 } }
	local first = pick(f, 30, 4)
	for i = 0, pick(f, 31, 3) - 1 do
		if i < 2 then
			local c = edges[(first + i * 2 - 1) % 4 + 1]
			top(m, f, c[1], c[2], 0.25, 0.25, 0.16, "rock", "Chip")
		end
	end
end

-- Grey stones sunk in moss, the moss creeping up over their corners.
local MOSSY: { { { number } } } = {
	{ { -0.45, -0.45, 0.75, 0.75 }, { 0.5, -0.55, 0.75, 0.5 }, { 0.45, 0.45, 0.75, 0.75 }, { -0.55, 0.5, 0.5, 0.75 } },
	{ { -0.3, -0.35, 1.25, 1 }, { 0.6, -0.5, 0.5, 0.5 }, { 0.55, 0.45, 0.5, 0.75 }, { -0.45, 0.6, 0.75, 0.5 } },
}
local MOSS_ON: { { { number } } } = {
	{ { -0.7, -0.2, 0.5, 0.25 }, { 0.7, 0.3, 0.25, 0.5 }, { -0.55, 0.75, 0.5, 0.25 } },
	{ { -0.75, -0.6, 0.25, 0.5 }, { 0.1, -0.1, 0.5, 0.25 }, { 0.6, 0.7, 0.5, 0.25 } },
}
M.mossstone = function(m, f)
	local map = orient(f, 1)
	local v = pick(f, 2, #MOSSY)
	top(m, f, 0, 0, 2, 2, 0.12, "moss", "Path")
	for i, s in MOSSY[v] do
		local x, z, w, d = map(s[1], s[2], s[3], s[4])
		top(m, f, x, z, w, d, if i % 2 == 0 then 0.17 else 0.18, if rnd(f, 10 + i) < 0.3 then "rock_dark" else "rock", "Stone")
	end
	for _, s in MOSS_ON[v] do
		local x, z, w, d = map(s[1], s[2], s[3], s[4])
		top(m, f, x, z, w, d, 0.2, "moss", "Moss")
	end
end

-- Red and gold leaves over brown earth, lying every which way.
local LEAVES = { "maple", "gold", "orange", "berry_red", "yellow", "maple", "orange" }
M.leafpath = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "wood_dark", "Path")
	for i, s in scatter(f, 0, 7, 0.08) do
		local yaw = (pick(f, 50 + i, 4) - 1) * math.pi / 4
		Parts.turned(m, f, s[1], 0.035 + (i % 2) * 0.01, s[2], 0.25, 0.25, 0.5, yaw, LEAVES[pick(f, 60 + i, #LEAVES)], "Leaf")
	end
end

-- Long grass full of small flowers: a darker green patch, tufts that sway, flowers in it.
local BLOOMS = { "pink", "yellow", "white", "purple", "blue", "berry_red" }
M.meadow = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "grass_dark", "Path")
	local s = scatter(f, 0, 7, 0.12)
	for i = 1, 3 do
		Parts.box(m, f, s[i][1], 0.05, s[i][2], 0.25, 0.5, 0.25, if i == 2 then "leaf" else "leaf_dark", "Tuft")
	end
	for i = 4, 7 do
		top(m, f, s[i][1], s[i][2], 0.25, 0.25, 0.21 + (i % 2) * 0.03, BLOOMS[pick(f, 60 + i, #BLOOMS)], "Flower")
	end
end

-- Gravel combed into lines: pale ridges along the tile, a stone set in it now and then.
M.raked = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "pavement", "Path")
	for _, z in { -0.75, -0.25, 0.25, 0.75 } do
		top(m, f, 0, z, 2, 0.25, 0.15, "white", "Ridge")
	end
	if rnd(f, 1) < 0.15 then
		local s = scatter(f, 10, 1, 0.05)[1]
		top(m, f, s[1], s[2], 0.5, 0.5, 0.25, "rock", "Stone")
	end
end

-- Snow with footprints: a trail of prints across most tiles (one way or the other), a stone or a twig showing
-- through here and there.
M.snowpath = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "snow", "Path")
	local v = pick(f, 1, 5)
	if v <= 4 then
		-- the trail runs along Z (v 1, 2) or along X (v 3, 4); a stone may show off to one side of it
		local c = (rnd(f, 2) * 2 - 1) * 0.3
		local along = (rnd(f, 3) * 2 - 1) * 0.5
		local side = if c < 0 then 0.7 else -0.7
		for i, a in { -0.75, -0.25, 0.25, 0.75 } do
			local b = c + (if i % 2 == 0 then 0.2 else -0.2)
			if v <= 2 then
				top(m, f, b, a, 0.25, 0.5, 0.155, "ice", "Print")
			else
				top(m, f, a, b, 0.5, 0.25, 0.155, "ice", "Print")
			end
		end
		if rnd(f, 4) < 0.35 then
			local x, z = if v <= 2 then side else along, if v <= 2 then along else side
			top(m, f, x, z, 0.25, 0.25, 0.18, "rock_dark", "Stone")
		end
	elseif rnd(f, 4) < 0.6 then
		local s = scatter(f, 10, 1, 0.05)[1]
		Parts.turned(m, f, s[1] * 0.8, 0.045, s[2] * 0.8, 0.75, 0.25, 0.25, (rnd(f, 5) * 2 - 1) * 0.5, "wood_dark", "Twig")
	end
end

-- Warm yellow slabs in a running bond on sandy grout, each slab its own shade.
local SANDSTONE: { { number } } = { { -0.375, -0.5, 1, 0.75 }, { 0.625, -0.5, 0.5, 0.75 }, { -0.625, 0.5, 0.5, 0.75 }, { 0.375, 0.5, 1, 0.75 } }
M.sandstone = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "sand_dark", "Grout")
	for i, s in SANDSTONE do
		local r = rnd(f, i)
		top(m, f, s[1], s[2], s[3], s[4], 0.17, if r < 0.5 then "straw" else "sand", "Slab")
	end
	if rnd(f, 9) < 0.4 then
		local s = SANDSTONE[pick(f, 10, 4)]
		top(m, f, s[1] + (s[3] / 2 - 0.25) * (if rnd(f, 11) < 0.5 then 1 else -1), s[2], 0.25, 0.25, 0.185, "sand_dark", "Chip")
	end
end

-- Baked clay squares on pale grout, two shades in a check, a small teal tile where the four meet.
M.terracotta = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.12, "cream", "Grout")
	for i, c in { { -0.5, -0.5 }, { 0.5, -0.5 }, { -0.5, 0.5 }, { 0.5, 0.5 } } do
		top(m, f, c[1], c[2], 0.75, 0.75, 0.17, if i == 1 or i == 4 then "clay" else "pot", "Tile")
	end
	Parts.turned(m, f, 0, 0.055, 0, 0.25, 0.25, 0.25, math.pi / 4, "teal", "Insert")
end

-- Black and white squares, a stud each, so tiles side by side keep the check.
M.checker = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "white", "Path")
	top(m, f, -0.5, -0.5, 1, 1, 0.16, "black", "Square")
	top(m, f, 0.5, 0.5, 1, 1, 0.16, "black", "Square")
end

-- Pale violet stones on slate (laid like the flagstones, a darker one among them), a few glints in them that glow a
-- little at night.
M.crystalpath = function(m, f)
	local map = orient(f, 1)
	local stones = FLAGS[pick(f, 2, #FLAGS)]
	top(m, f, 0, 0, 2, 2, 0.12, "slate", "Path")
	local dark = pick(f, 3, #stones)
	for i, s in stones do
		local x, z, w, d = map(s[1], s[2], s[3], s[4])
		top(m, f, x, z, w, d, if i % 2 == 0 then 0.17 else 0.16, if i == dark then "purple" else "crystal", "Stone")
	end
	for i = 1, 2 do
		local s = stones[1 + (pick(f, 10, #stones) + i - 1) % #stones]
		local x, z = map(s[1] + (rnd(f, 20 + i) * 2 - 1) * (s[3] / 2 - 0.125), s[2] + (rnd(f, 30 + i) * 2 - 1) * (s[4] / 2 - 0.125), 0.25, 0.25)
		Parts.glow(m, f, x, 0.065, z, 0.25, 0.25, 0.25, if i == 1 then "white" else "crystal", "Glint")
	end
end

-- Black rock in slabs at a few heights, with the warm glow of lava in the cracks between.
local BASALT: { { number } } = { { -0.625, -0.5, 0.75, 1, 0.18 }, { 0.5, -0.625, 1, 0.75, 0.2 }, { -0.375, 0.625, 1.25, 0.75, 0.16 }, { 0.75, 0.5, 0.5, 1, 0.19 } }
M.basalt = function(m, f)
	local map = orient(f, 1)
	Parts.glow(m, f, 0, -0.01, 0, 2, 0.25, 2, "lava", "Crack")
	for _, s in BASALT do
		local x, z, w, d = map(s[1], s[2], s[3], s[4])
		top(m, f, x, z, w, d, s[5], "basalt", "Slab")
	end
end

-- Cream stone with a thin gold frame set into each tile round a paler panel.
M.goldpath = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "cream", "Path")
	top(m, f, 0, 0, 1.5, 1.5, 0.155, "gold", "Rim")
	top(m, f, 0, 0, 1, 1, 0.165, "paper", "Panel")
end

-- Dark blue stone full of little stars (they glow at night): one bigger star a tile, the rest single points.
M.starpath = function(m, f)
	top(m, f, 0, 0, 2, 2, 0.14, "night", "Path")
	local s = scatter(f, 0, 7, 0.12)
	local x, z = math.clamp(s[1][1], -0.4, 0.4), math.clamp(s[1][2], -0.4, 0.4)
	Parts.at(m, f, CFrame.new(x, 0.035, z) * CFrame.Angles(0, math.pi / 4, 0), 0.75, 0.25, 0.25, "yellow", "Star", true)
	Parts.at(m, f, CFrame.new(x, 0.04, z) * CFrame.Angles(0, math.pi / 4, 0), 0.25, 0.25, 1, "yellow", "Star", true)
	local n = 0
	for i = 2, 7 do
		if n < 5 and math.abs(s[i][1] - x) + math.abs(s[i][2] - z) > 0.6 then
			Parts.glow(m, f, s[i][1], 0.025, s[i][2], 0.25, 0.25, 0.25, if i % 2 == 0 then "white" else "yellow", "Star")
			n += 1
		end
	end
end

------------------------------------------------------------------ water
local WATER_Y = -0.035 -- the water's top at 0.09, just over the lawn's
local BANK_TOP = 0.19

type Pond = {
	n: boolean, -- a bank on this side (no water next to it)
	e: boolean,
	s: boolean,
	w: boolean,
	b: number, -- the bank's width
	-- the open water's rect (inside the banks)
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	left: number, -- parts left of the tile's 8
}

-- Which sides of a water tile have no water next to them (lvl = 1 + the neighbour mask).
local function banksOf(lvl: number): (boolean, boolean, boolean, boolean)
	local mask = math.max(0, math.floor(lvl) - 1) % 16
	return bit32.band(mask, 1) == 0, bit32.band(mask, 2) == 0, bit32.band(mask, 4) == 0, bit32.band(mask, 8) == 0
end

-- The water over the whole tile (a Parts.water surface, or a plain slab for ice), then a bank of width b along each
-- side with no water next to it (north and south full length, east and west between them), then a block of bank
-- rounding the water's corner wherever two banks meet (when the parts allow).
local function pond(m: Model, f: CFrame, lvl: number, surface: string, bank: string, b: number, ice: boolean?): Pond
	local n, e, s, w = banksOf(lvl)
	if ice then
		top(m, f, 0, 0, 2, 2, 0.11, surface, "Ice")
	else
		Parts.water(m, f, 0, WATER_Y, 0, 2, 2, surface)
	end
	local left = 7
	local y = BANK_TOP - 0.125
	if n then
		Parts.box(m, f, 0, y, -1 + b / 2, 2, 0.25, b, bank, "Bank")
		left -= 1
	end
	if s then
		Parts.box(m, f, 0, y, 1 - b / 2, 2, 0.25, b, bank, "Bank")
		left -= 1
	end
	local za, zb = if n then -1 + b else -1, if s then 1 - b else 1
	if e then
		Parts.box(m, f, 1 - b / 2, y, (za + zb) / 2, b, 0.25, zb - za, bank, "Bank")
		left -= 1
	end
	if w then
		Parts.box(m, f, -1 + b / 2, y, (za + zb) / 2, b, 0.25, zb - za, bank, "Bank")
		left -= 1
	end
	local x0, x1 = if w then -1 + b else -1, if e then 1 - b else 1
	local corners: { { number } } = {}
	if n and e then
		table.insert(corners, { x1 - 0.125, za + 0.125 })
	end
	if e and s then
		table.insert(corners, { x1 - 0.125, zb - 0.125 })
	end
	if s and w then
		table.insert(corners, { x0 + 0.125, zb - 0.125 })
	end
	if w and n then
		table.insert(corners, { x0 + 0.125, za + 0.125 })
	end
	if #corners > 0 and left - #corners >= 1 then
		for _, c in corners do
			Parts.box(m, f, c[1], y, c[2], 0.25, 0.25, 0.25, bank, "Corner")
		end
		left -= #corners
	end
	return { n = n, e = e, s = s, w = w, b = b, x0 = x0, x1 = x1, z0 = za, z1 = zb, left = left }
end

-- A spot in the open water for a thing of size w x d (kept off the banks), by the hash.
local function inWater(p: Pond, f: CFrame, k: number, w: number, d: number): (number, number)
	local ax, bx = p.x0 + w / 2 + 0.125, p.x1 - w / 2 - 0.125
	local az, bz = p.z0 + d / 2 + 0.125, p.z1 - d / 2 - 0.125
	if ax > bx then
		ax, bx = (p.x0 + p.x1) / 2, (p.x0 + p.x1) / 2
	end
	if az > bz then
		az, bz = (p.z0 + p.z1) / 2, (p.z0 + p.z1) / 2
	end
	return ax + (bx - ax) * rnd(f, k), az + (bz - az) * rnd(f, k + 1)
end

-- A spot along one of the tile's banks (on its inner edge), by the hash; nil when the tile has no bank.
local function onBank(p: Pond, f: CFrame, k: number): (number?, number?)
	local sides = {}
	if p.n then
		table.insert(sides, { 0, -1 })
	end
	if p.e then
		table.insert(sides, { 1, 0 })
	end
	if p.s then
		table.insert(sides, { 0, 1 })
	end
	if p.w then
		table.insert(sides, { -1, 0 })
	end
	if #sides == 0 then
		return nil, nil
	end
	local sd = sides[pick(f, k, #sides)]
	local along = (rnd(f, k + 1) * 2 - 1) * 0.55
	local edge = 1 - p.b
	if sd[1] == 0 then
		return along, sd[2] * edge
	end
	return sd[1] * edge, along
end

-- Clear and shallow: light water in a bed of pale pebbles, darker stones along its edge, one poking out of the
-- water here and there.
M.stream = function(m, f, lvl)
	local p = pond(m, f, lvl, "shallow", "pavement", 0.5)
	for i = 1, math.min(2, p.left) do
		local x, z = onBank(p, f, 10 * i)
		if x and z then
			top(m, f, x, z, 0.25 * pick(f, 10 * i + 5, 2), 0.25, BANK_TOP + 0.02, if i == 1 then "rock" else "rock_dark", "Pebble")
		end
	end
	if p.left >= 3 and rnd(f, 40) < 0.6 then
		local x, z = inWater(p, f, 41, 0.25, 0.25)
		top(m, f, x, z, 0.25, 0.25, 0.12, "rock", "Stone")
	end
end

-- Deep and dark, with paler streaks of current running the way the river goes.
M.river = function(m, f, lvl)
	local p = pond(m, f, lvl, "water", "rock_dark", 0.5)
	local alongZ = (not p.n or not p.s) and p.e and p.w
	local alongX = (not p.e or not p.w) and p.n and p.s
	if not alongZ and not alongX then
		alongZ = rnd(f, 1) < 0.5
	end
	for i = 1, math.min(2, p.left) do
		local w, d = if alongZ then 0.25 else 0.75, if alongZ then 0.75 else 0.25
		local x, z = inWater(p, f, 10 * i, w, d)
		Parts.water(m, f, x, -0.025, z, w, d, "shallow", "Current")
	end
	if p.left >= 3 and rnd(f, 30) < 0.6 then
		local x, z = onBank(p, f, 31)
		if x and z then
			top(m, f, x, z, 0.5, 0.25, BANK_TOP + 0.03, "rock", "Stone")
		end
	end
end

-- Still water with lily pads on it, a pink flower on some.
M.lilypond = function(m, f, lvl)
	local p = pond(m, f, lvl, "water", "moss", 0.5)
	local pads = math.min(p.left, if rnd(f, 1) < 0.5 then 2 else 1)
	for i = 1, pads do
		local dia = if i == 1 then 0.75 else 0.5
		local x, z = inWater(p, f, 10 * i, dia, dia)
		Parts.cyl(m, f, x, -0.01, z, dia, 0.25, if i == 1 then "green" else "leaf_dark", "Pad")
		if i == 1 and p.left > pads and rnd(f, 30) < 0.5 then
			top(m, f, x + 0.1, z - 0.05, 0.25, 0.25, 0.2, "pink", "Flower")
		end
	end
end

-- Murky green and still: muddy banks, a clump of reeds (the taller one with a brown head), a patch of scum.
M.swamp = function(m, f, lvl)
	local p = pond(m, f, lvl, "swamp", "wood_dark", 0.5)
	local reeds = if p.left >= 4 and rnd(f, 1) < 0.7 then 1 else 0
	for i = 1, reeds do
		local x, z = inWater(p, f, 10 * i, 0.5, 0.25)
		local h = 0.5 + 0.25 * pick(f, 10 * i + 5, 2)
		Parts.box(m, f, x, 0.09 + h / 2, z, 0.25, h, 0.25, "leaf", "Reed")
		Parts.box(m, f, x, 0.09 + h + 0.125, z, 0.25, 0.25, 0.25, "wood_dark", "ReedHead")
		Parts.box(m, f, x + 0.25, 0.34, z + 0.05, 0.25, 0.5, 0.25, "leaf_dark", "Reed")
	end
	if p.left > reeds * 3 and rnd(f, 30) < 0.6 then
		local x, z = inWater(p, f, 31, 0.5, 0.25)
		top(m, f, x, z, 0.5, 0.25, 0.1, "moss", "Scum")
	end
end

-- Bright blue-green like the reef: sandy banks, pale shallows along them, deeper teal in the middle, a shell or a
-- bit of coral on the sand now and then.
M.lagoon = function(m, f, lvl)
	local p = pond(m, f, lvl, "shallow", "sand", 0.5)
	local x0, x1 = if p.w then p.x0 + 0.25 else -1, if p.e then p.x1 - 0.25 else 1
	local z0, z1 = if p.n then p.z0 + 0.25 else -1, if p.s then p.z1 - 0.25 else 1
	if x1 > x0 and z1 > z0 then
		Parts.water(m, f, (x0 + x1) / 2, WATER_Y + 0.01, (z0 + z1) / 2, x1 - x0, z1 - z0, "teal", "Deep")
	end
	if p.left >= 2 and rnd(f, 1) < 0.5 then
		local x, z = onBank(p, f, 10)
		if x and z then
			top(m, f, x, z, 0.25, 0.25, BANK_TOP + 0.02, if rnd(f, 20) < 0.5 then "coral" else "pink", "Shell")
		end
	end
end

-- Warm water in a ring of stones, steam rising off it.
M.hotspring = function(m, f, lvl)
	local p = pond(m, f, lvl, "teal", "rock", 0.5)
	local x, z = onBank(p, f, 1)
	if x and z and p.left >= 3 then
		top(m, f, x, z, 0.5, 0.5, BANK_TOP + 0.06, "rock_dark", "Stone")
	end
	if p.left >= 2 and rnd(f, 10) < 0.75 then
		-- see-through puffs: the pixel filter tints what lies behind them, a mist with no ink line round it
		local sx, sz = inWater(p, f, 11, 0.75, 0.75)
		Parts.ball(m, f, sx - 0.06, 0.35, sz + 0.06, 0.5, "white", "Steam").Transparency = 0.45
		Parts.ball(m, f, sx + 0.06, 0.75, sz - 0.06, 0.5, "white", "Steam").Transparency = 0.6
	end
end

-- Ice thick enough to stand on: a pale slab with a white crack and a glint, snow banked round it.
M.icepond = function(m, f, lvl)
	local p = pond(m, f, lvl, "ice", "snow", 0.5, true)
	if p.left >= 1 then
		-- two strokes end to end, the second bent off the first; the crack centred on a spot in the open ice and
		-- kept inside the tile
		local x, z = inWater(p, f, 1, 1.25, 1.25)
		local a = (rnd(f, 2) * 2 - 1) * 0.5 + (if rnd(f, 5) < 0.5 then 0 else math.pi / 2)
		local b = a + (if rnd(f, 6) < 0.5 then 0.8 else -0.8)
		local jx, jz = math.sin(a) * 0.375, math.cos(a) * 0.375 -- the bend (the start is at minus this)
		local ex, ez = jx + math.sin(b) * 0.5, jz + math.cos(b) * 0.5 -- the end
		local lx, hx = math.min(-math.abs(jx), ex), math.max(math.abs(jx), ex)
		local lz, hz = math.min(-math.abs(jz), ez), math.max(math.abs(jz), ez)
		local cx = math.clamp(x - (lx + hx) / 2, -0.82 - lx, 0.82 - hx)
		local cz = math.clamp(z - (lz + hz) / 2, -0.82 - lz, 0.82 - hz)
		Parts.at(m, f, CFrame.new(cx, 0.005, cz) * CFrame.Angles(0, a, 0), 0.25, 0.25, 0.75, "white", "Crack")
		if p.left >= 2 then
			Parts.at(m, f, CFrame.new(cx + jx + math.sin(b) * 0.25, 0.005, cz + jz + math.cos(b) * 0.25) * CFrame.Angles(0, b, 0), 0.25, 0.25, 0.5, "white", "Crack")
		end
	end
	if p.left >= 3 and rnd(f, 3) < 0.6 then
		local x, z = inWater(p, f, 4, 0.75, 0.25)
		top(m, f, x, z, 0.75, 0.25, 0.125, "white", "Glint")
	end
end

return M
