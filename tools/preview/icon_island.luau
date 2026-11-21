-- The game icon's island (the request of 2026-11-21: "make an icon, with the island being the centerpiece"): a first
-- island (tier 1, the smallest, so it shows whole at a readable zoom) furnished as a player would, kept to the game's
-- own rules (Logic/Plot.fits for every piece, tile and fence; the piece, tile and fence limits, the huts' room and the
-- places at work). The camera looks from the south-east, so the plan keeps the low things in front and the tall ones
-- at the sides, clear of the Tree of Life in the middle:
-- * a ring of pale shell path round the tree, a plank walk from it to the front;
-- * a pond on the right (stream tiles and lily pads), flower beds along the front;
-- * the stall on the right facing the camera, the huts on the left, a veggie patch at the back;
-- * an oak, a palm and pines framing it. At the icon's size small props turn to noise, so it keeps to a few bold
--   masses of colour round the tree.
--   (env) -> plan(prof) -> stats
return function(env)
	local Plot, Buildings, Street = env.Plot, env.Buildings, env.Street
	local log = env.log or function(...) end

	return function(prof)
		local tier = prof.tier
		local placed = prof.plot.placed
		local L = {
			piece = Plot.limit(tier),
			tile = Plot.pathLimit(tier),
			fence = Plot.fenceLimit(tier),
			house = Plot.housingLimit(tier),
			work = Plot.workLimit(tier),
		}
		local used = { piece = 0, tile = 0, fence = 0, house = 0, work = 0 }
		for _, q in placed do
			local g = Plot.group(q.id)
			if g == "piece" and Buildings.byId[q.id] and Buildings.byId[q.id].kind ~= "tree" then
				used.piece += 1
			end
		end
		local function add(id: string, x: number, z: number, rot: number?): boolean
			local d = Buildings.byId[id]
			if d == nil or d.tier > tier then
				return false
			end
			local r = rot or 0
			local g = Plot.group(id)
			if used[g] ~= nil and L[g] ~= nil and used[g] >= L[g] then
				return false
			end
			if d.kind == "nest" and used.house + d.slots > L.house then
				return false
			end
			if (d.jobs or 0) > 0 and used.work + d.jobs > L.work then
				return false
			end
			if not Plot.fits(tier, placed, id, x, z, r) then
				return false
			end
			table.insert(placed, { uid = prof.nextId, id = id, x = x, z = z, rot = r, lvl = 1 })
			prof.nextId += 1
			used[g] = (used[g] or 0) + 1
			if d.kind == "nest" then
				used.house += d.slots
			end
			used.work += d.jobs or 0
			return true
		end
		-- a stud or two each way for a piece that is fussy about where it fits
		local function near(id: string, x: number, z: number, rot: number?): boolean
			for _, o in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, { 2, 0 }, { 0, 2 }, { -2, 0 }, { 0, -2 }, { 2, 2 }, { -2, 2 }, { 2, -2 }, { -2, -2 } } do
				if add(id, x + o[1], z + o[2], rot) then
					return true
				end
			end
			return false
		end
		local function even(v: number): number
			return v - v % 2
		end

		-- the tree's box (the ring goes round it)
		local tr = { x0 = -4, z0 = 2, x1 = 4, z1 = 10 }
		for _, q in placed do
			local d = Buildings.byId[q.id]
			if d and d.kind == "tree" then
				tr = Plot.rect(q.id, q.x, q.z, q.rot)
			end
		end
		local rx0, rz0 = even(tr.x0 - 2), even(tr.z0 - 2)
		local rx1, rz1 = tr.x1 + tr.x1 % 2, tr.z1 + tr.z1 % 2

		-- (at the icon's size small props turn to noise: a few bold masses of colour instead, the tree in the middle)
		-- the ring round the tree in pale shell, two tiles of plank walk down from it to the front
		for x = rx0, rx1, 2 do
			add("shellpath", x, rz0, 0)
			add("shellpath", x, rz1, 0)
		end
		for z = rz0 + 2, rz1 - 2, 2 do
			add("shellpath", rx0, z, 0)
			add("shellpath", rx1, z, 0)
		end
		for z = rz1 + 2, rz1 + 6, 2 do
			add("plankwalk", -2, z, 0)
		end
		-- the pond on the right of the ring (east: the picture's lower right), rounded, lily pads on it
		local pond = 0
		for _, c in { { 8, 4 }, { 10, 4 }, { 8, 6 }, { 10, 6 }, { 12, 6 }, { 8, 8 }, { 10, 8 }, { 12, 8 }, { 10, 10 }, { 8, 10 }, { 12, 4 }, { 12, 10 } } do
			if add("stream", c[1], c[2], 0) then
				pond += 1
			end
		end
		near("lilypads", 10, 6, 0)
		near("lilypads", 8, 9, 0)
		-- trees framing it (before the flowers, so they get their spots): an oak at the front left, a palm at the
		-- left, pines at the corners
		near("oak", -12, 11, 0)
		near("palm", -15, 3, 0)
		near("pine", 13, 12, 0)
		near("pine", 7, -8, 0)
		near("pine", -4, -7, 0)
		-- flower beds along the front (south), either side of the walk
		for _, c in { { -6, 14 }, { -9, 13 }, { 1, 14 }, { 4, 13 }, { -12, 11 } } do
			near("flowers", c[1], c[2], 0)
		end
		near("tulips", -4, 16, 0)
		near("tulips", 2, 16, 0)
		-- the stall on the right, its front toward the camera; the huts on the left, a lumber camp at the back
		near("stall", 9, -2, 0)
		local huts = 0
		for _, c in { { -11, 3 }, { -11, 7 }, { -8, -3 }, { -12, -1 } } do
			if near("nest", c[1], c[2], 0) then
				huts += 1
			end
		end
		near("patch", 4, -6, 0)
		near("berrybush", 7, 12, 0)
		near("bush", 13, 12, 0)
		near("berrybush", -14, 8, 0)
		log("icon island: tier %d, %d huts, pieces %d of %d, tiles %d of %d, fences %d of %d, work %d of %d", tier, huts, used.piece, L.piece, used.tile, L.tile, used.fence, L.fence, used.work, L.work)
		return { used = used, limits = L }
	end
end
