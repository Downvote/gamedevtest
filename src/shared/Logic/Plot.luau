--!strict
-- The island's building rules (GAME_DESIGN 4; docs/ARCHITECTURE.md 6): where buildings and decor may stand, placing
-- (paid in wood: Data/Buildings), moving and clearing them away. Pure. Positions are plot-local whole studs: a piece's
-- (x, z) is its footprint's north-west corner, its rot a quarter turn (0, 90, 180, 270; 90 and 270 swap the
-- footprint's width and depth). A piece stands wholly on the island's buildable cells (Data/Street: the grass a stud
-- in from its edge, the island's shape by its tier), off the plaza round the campfire and the path to the jetty, and
-- off every other piece. Paths and water are 2 x 2 tiles drawn on the even studs (paint / unpaint): water makes rivers and
-- ponds ("add the ability to add water to make rivers"), a piece marked `water = "over"` (a bridge, a dock) may stand
-- over water tiles as well as grass and one marked "on" (lily pads, a rowboat) only on water. Fences are 2-stud lengths
-- along the even grid lines (fence / unfence: rot 0 runs east from (x, z), rot 90 south), never through a building,
-- the plaza or the path; tiles and fences never get in each other's way, and a fence may run along a building's side.
-- Paths and water count together against Tuning.PathPieces, fences against Tuning.FencePieces, the rest against the
-- piece limit. The Tree of Life (Data/Buildings kind "tree": every island's, Logic/Tree) may be moved like any
-- piece, but is never bought, cleared away or replaced, and isn't counted in the piece limit. Clearing a hut away (or
-- replacing it with a smaller one) leaves the driftlings it can no longer house with no hut: they wait till a hut has
-- room (Logic/Tree.settle).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Street = require(script.Parent.Parent.Data.Street)
local Buildings = require(script.Parent.Parent.Data.Buildings)

type Profile = Types.Profile
type Piece = Types.Piece
type ErrCode = Types.ErrCode
type Rect = Street.Rect

local Plot = {}

Plot.ROTS = { 0, 90, 180, 270 }

-- The island's piece limit by its tier (buildings and decor), and its path tiles' (apart: Tuning.PathPieces).
function Plot.limit(tier: number): number
	return Tuning.PlotPieces[math.clamp(math.floor(tier), 1, #Tuning.PlotPieces)]
end
-- How many huts an island of `tier` may have (Tuning.HutLimit), and how many stand.
function Plot.hutLimit(tier: number): number
	return Tuning.HutLimit[math.clamp(math.floor(tier), 1, #Tuning.HutLimit)]
end
function Plot.huts(placed: { Piece }): number
	local n = 0
	for _, q in placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "nest" then
			n += 1
		end
	end
	return n
end
function Plot.pathLimit(tier: number): number
	return Tuning.PathPieces[math.clamp(math.floor(tier), 1, #Tuning.PathPieces)]
end
function Plot.fenceLimit(tier: number): number
	return Tuning.FencePieces[math.clamp(math.floor(tier), 1, #Tuning.FencePieces)]
end

local function kindOf(id: string): string
	local d = Buildings.byId[id]
	return if d then d.kind else ""
end

-- Whether a piece is a path tile, a water tile, either (a tile: drawn on the even studs, counted apart), a fence length.
function Plot.isPath(id: string): boolean
	return kindOf(id) == "path"
end
function Plot.isWater(id: string): boolean
	return kindOf(id) == "water"
end
function Plot.isTile(id: string): boolean
	local k = kindOf(id)
	return k == "path" or k == "water"
end
function Plot.isFence(id: string): boolean
	return kindOf(id) == "fence"
end
-- Whether a piece is drawn with Build mode's draw bar (a line, a box, rubbed out) rather than put down one at a time.
function Plot.isDrawn(id: string): boolean
	local k = kindOf(id)
	return k == "path" or k == "water" or k == "fence"
end

-- Whether a piece is the Tree of Life (it stays on the island: never bought, cleared away or replaced).
function Plot.isFixed(id: string): boolean
	return kindOf(id) == "tree"
end

-- A piece's count: "tile" (paths and water: Tuning.PathPieces), "fence" (Tuning.FencePieces), "fixed" (the tree: never
-- counted) or "piece" (the rest: the piece limit).
function Plot.group(id: string): string
	local k = kindOf(id)
	if k == "path" or k == "water" then
		return "tile"
	elseif k == "fence" then
		return "fence"
	elseif k == "tree" then
		return "fixed"
	end
	return "piece"
end

-- A count's limit at a tier.
function Plot.groupLimit(group: string, tier: number): number
	if group == "tile" then
		return Plot.pathLimit(tier)
	elseif group == "fence" then
		return Plot.fenceLimit(tier)
	elseif group == "fixed" then
		return 1
	end
	return Plot.limit(tier)
end

-- How many pieces of the same count as `id` stand, and that count's limit.
function Plot.used(p: Profile, id: string): (number, number)
	local g = Plot.group(id)
	local n = 0
	for _, q in p.plot.placed do
		if Plot.group(q.id) == g then
			n += 1
		end
	end
	return n, Plot.groupLimit(g, p.tier)
end

-- The footprint (w along x, d along z) of a piece turned by rot.
function Plot.footprint(id: string, rot: number): (number, number)
	local def = Buildings.byId[id]
	if def == nil then
		return 1, 1
	end
	if rot == 90 or rot == 270 then
		return def.d, def.w
	end
	return def.w, def.d
end

function Plot.rect(id: string, x: number, z: number, rot: number): Rect
	local w, d = Plot.footprint(id, rot)
	return { x0 = x, z0 = z, x1 = x + w, z1 = z + d }
end

local function overlaps(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.z0 < b.z1 and b.z0 < a.z1
end

-- The fixed things on an island no piece may cover (plot-local): the plaza round the campfire (the same on every tier;
-- the path south to the jetty went with the docks on 2026-11-13).
function Plot.blockers(_tier: number): { Rect }
	return { Street.PLAZA }
end

local ROT_OK: { [number]: boolean } = { [0] = true, [90] = true, [180] = true, [270] = true }

-- Whether every cell of rect r is covered by a water tile of `placed` (skip: the index left out).
local function onWater(r: Rect, placed: { Piece }, skip: number?): boolean
	local wet: { [number]: boolean } = {}
	for i, q in placed do
		if i ~= skip and Plot.isWater(q.id) then
			local qr = Plot.rect(q.id, q.x, q.z, q.rot)
			for cz = qr.z0, qr.z1 - 1 do
				for cx = qr.x0, qr.x1 - 1 do
					wet[Street.cellKey(cx, cz)] = true
				end
			end
		end
	end
	for cz = r.z0, r.z1 - 1 do
		for cx = r.x0, r.x1 - 1 do
			if not wet[Street.cellKey(cx, cz)] then
				return false
			end
		end
	end
	return true
end

-- A fence length at (x, z, rot): on the even grid, rot 0 (east) or 90 (south), each of its two studs with buildable
-- grass on at least one side; not through the plaza, the path or a piece (it may run along one's side, and past tiles),
-- and not where a fence stands already.
local function fenceFits(tier: number, placed: { Piece }, x: number, z: number, rot: number, skip: number?): (boolean, string?)
	if x % 2 ~= 0 or z % 2 ~= 0 or (rot ~= 0 and rot ~= 90) then
		return false, "outside"
	end
	for k = 0, 1 do
		local ok
		if rot == 0 then
			ok = Street.buildable(tier, x + k, z - 1) or Street.buildable(tier, x + k, z)
		else
			ok = Street.buildable(tier, x - 1, z + k) or Street.buildable(tier, x, z + k)
		end
		if not ok then
			return false, "outside"
		end
	end
	local seg: Rect = if rot == 0 then { x0 = x, z0 = z, x1 = x + 2, z1 = z } else { x0 = x, z0 = z, x1 = x, z1 = z + 2 }
	for _, b in Plot.blockers(tier) do
		if overlaps(seg, b) then
			return false, "blocked"
		end
	end
	for i, q in placed do
		if i == skip then
			continue
		end
		local k = kindOf(q.id)
		if k == "fence" then
			if q.x == x and q.z == z and q.rot % 180 == rot % 180 then
				return false, "overlap"
			end
		elseif k ~= "path" and k ~= "water" and overlaps(seg, Plot.rect(q.id, q.x, q.z, q.rot)) then
			return false, "overlap"
		end
	end
	return true, nil
end

-- Whether a piece may stand on path tiles, and paving go under it (GAME_DESIGN 4: a themed yard paved in snow, sand or
-- moss stone with its decor on it; since the request of 2026-11-14, "make it such that paths can be put below
-- buildings, and buildings can be put on to paths", the huts and the workplaces too): every piece but the tree (its eggs
-- lie on its own lawn), a fence, the tiles themselves and anything for the water.
local function onPaths(def: Buildings.BuildingDef): boolean
	local k = def.kind
	return k ~= "tree" and k ~= "fence" and k ~= "path" and k ~= "water" and def.water == ""
end
function Plot.onPaths(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and onPaths(d)
end

-- Whether piece `id` fits at (x, z, rot) on an island of `tier` with these pieces (skip = the index of the piece
-- being moved). Returns true, or false and why: "outside" (off the buildable grass or not on the grid; a piece that
-- floats, off the water), "blocked" (the plaza or the path), "overlap" (another piece), "unknown" (no such piece).
function Plot.fits(tier: number, placed: { Piece }, id: string, x: number, z: number, rot: number, skip: number?): (boolean, string?)
	local def = Buildings.byId[id]
	if def == nil then
		return false, "unknown"
	end
	if x ~= math.floor(x) or z ~= math.floor(z) or not ROT_OK[rot] then
		return false, "outside"
	end
	if def.kind == "fence" then
		return fenceFits(tier, placed, x, z, rot, skip)
	end
	-- (a tile lies on the even studs, as it is drawn: the water's banks follow its neighbours on that grid)
	if (def.kind == "path" or def.kind == "water") and (x % 2 ~= 0 or z % 2 ~= 0) then
		return false, "outside"
	end
	local r = Plot.rect(id, x, z, rot)
	for cz = r.z0, r.z1 - 1 do
		for cx = r.x0, r.x1 - 1 do
			if not Street.buildable(tier, cx, cz) then
				return false, "outside"
			end
		end
	end
	for _, b in Plot.blockers(tier) do
		if overlaps(r, b) then
			return false, "blocked"
		end
	end
	local tile = def.kind == "path" or def.kind == "water"
	for i, q in placed do
		if i == skip then
			continue
		end
		local qd = Buildings.byId[q.id]
		local qk = if qd then qd.kind else ""
		if qk == "fence" then
			-- (a tile never meets a fence; a piece may not have one running through it)
			if not tile and overlaps(r, Plot.rect(q.id, q.x, q.z, q.rot)) then
				return false, "overlap"
			end
		elseif qk == "water" and def.water ~= "" then
			-- (a bridge or a lily pad over water)
		elseif def.kind == "water" and qd and qd.water ~= "" then
			-- (water under a bridge or a lily pad)
		elseif qk == "path" and onPaths(def) then
			-- (decor, a plant or a bench on a paved yard: a snowman on snow, a deck chair on sand)
		elseif def.kind == "path" and qd and onPaths(qd) then
			-- (paving under them)
		elseif overlaps(r, Plot.rect(q.id, q.x, q.z, q.rot)) then
			return false, "overlap"
		end
	end
	if def.water == "on" and not onWater(r, placed, skip) then
		return false, "outside"
	end
	return true, nil
end

-- The free spot nearest (x, z) where piece `id` fits (turned `rot`, or a quarter more if that is nearer), searched over
-- the island's grass: x, z, rot, or nil when there is none (Logic/Tree plants the tree with it; refit moves pieces).
function Plot.spot(tier: number, placed: { Piece }, id: string, x: number, z: number, rot: number): (number?, number?, number?)
	local pr = Street.plot(tier)
	local best, bx, bz, brot = math.huge, nil, nil, rot
	for _, r in { rot, (rot + 90) % 360 } do
		for cz = math.floor(pr.z0) + 1, math.floor(pr.z1) - 1 do
			for cx = math.floor(pr.x0) + 1, math.floor(pr.x1) - 1 do
				local d = (cx - x) ^ 2 + (cz - z) ^ 2 + (if r == rot then 0 else 0.5)
				if d < best and Plot.fits(tier, placed, id, cx, cz, r) then
					best, bx, bz, brot = d, cx, cz, r
				end
			end
		end
	end
	if bx == nil then
		return nil, nil, nil
	end
	return bx, bz, brot
end

-- Driftlings out of a hut that is gone (cleared away, or past a smaller hut's room): no hut, resting (they move into
-- a hut with room again: Logic/Tree.settle).
local function unhouse(p: Profile, uid: number, keep: number?)
	local list: { Types.Pal } = {}
	for _, x in p.pals do
		if x.home == uid then
			table.insert(list, x)
		end
	end
	-- (the hut keeps its best `keep`: the list is in the order they came, the first kept)
	for i, x in list do
		if keep == nil or i > keep then
			x.home = 0
			x.work = 0
		end
	end
end
Plot.unhouse = unhouse

------------------------------------------------------------------ actions (change the profile only on success)
-- Place a new piece: its tier reached, room under the island's limit (and its huts' limit: Tuning.HutLimit), its price
-- (wood; IslandService then sends resting driftlings to work there: Logic/Tree.fillJobs).
function Plot.place(p: Profile, id: string, x: number, z: number, rot: number): (boolean, any)
	local def = Buildings.byId[id]
	if def == nil or def.kind == "tree" then
		return false, "bad_payload" :: ErrCode
	end
	if def.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local used, most = Plot.used(p, id)
	if used >= most then
		return false, "full" :: ErrCode
	end
	if def.kind == "nest" and Plot.huts(p.plot.placed) >= Plot.hutLimit(p.tier) then
		return false, "huts" :: ErrCode
	end
	if p.shells < def.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < def.wood then
		return false, "wood" :: ErrCode
	end
	if not Plot.fits(p.tier, p.plot.placed, id, x, z, rot) then
		return false, "blocked" :: ErrCode
	end
	p.shells -= def.shells
	p.wood -= def.wood
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = x, z = z, rot = rot, lvl = 1 })
	p.stats.built += 1
	return true, { i = #p.plot.placed, uid = uid }
end

------------------------------------------------------------------ drawing paths, water and fences (GAME_DESIGN 4)
-- Tiles (paths and water) are 2 x 2 and drawn on the even studs (a cell is a tile's north-west corner); a request carries
-- at most PAINT_MAX cells, written "x,z;x,z;..." (Validate's "cells"). Fences are drawn along the grid lines: an edge is
-- a length's start and its way, "x,z,r;..." (r 0 east, 90 south; Validate's "edges").
Plot.PAINT_MAX = 40
Plot.PATH_STEP = 2

function Plot.cells(s: string): { { number } }
	local out: { { number } } = {}
	for x, z in string.gmatch(s, "(%-?%d+),(%-?%d+)") do
		table.insert(out, { tonumber(x) :: number, tonumber(z) :: number })
	end
	return out
end

function Plot.cellString(cells: { { number } }): string
	local parts = {}
	for _, c in cells do
		table.insert(parts, c[1] .. "," .. c[2])
	end
	return table.concat(parts, ";")
end

function Plot.edges(s: string): { { number } }
	local out: { { number } } = {}
	for x, z, r in string.gmatch(s, "(%-?%d+),(%-?%d+),(%d+)") do
		table.insert(out, { tonumber(x) :: number, tonumber(z) :: number, tonumber(r) :: number })
	end
	return out
end

function Plot.edgeString(edges: { { number } }): string
	local parts = {}
	for _, e in edges do
		table.insert(parts, e[1] .. "," .. e[2] .. "," .. e[3])
	end
	return table.concat(parts, ";")
end

local function count(placed: { Piece }, group: string): number
	local n = 0
	for _, q in placed do
		if Plot.group(q.id) == group then
			n += 1
		end
	end
	return n
end

-- Swap the drawn piece q for `id` where it lies (another look of the same kind): half the old one's price back, the
-- new one's paid. False when the stores can't cover it.
local function swapDrawn(p: Profile, q: Piece, id: string): boolean
	local old, new = Buildings.byId[q.id], Buildings.byId[id]
	if old == nil or new == nil then
		return false
	end
	local backS, backW = math.floor(old.shells * Tuning.Refund), math.floor(old.wood * Tuning.Refund)
	if p.shells + backS < new.shells or p.wood + backW < new.wood then
		return false
	end
	p.shells += backS - new.shells
	p.wood += backW - new.wood
	q.id = id
	q.lvl = 1
	p.stats.built += 1
	return true
end

-- Lay tiles of `id` (a path or water) on the cells in order, while the island's tile room and the stores last. Where a
-- tile of the same kind but another look lies, it's swapped for this one (half its price back); a cell where a tile
-- doesn't fit is passed over. True with { placed, swapped, skipped } when at least one changed, else why none could.
function Plot.paint(p: Profile, id: string, cells: { { number } }): (boolean, any)
	local def = Buildings.byId[id]
	if def == nil or (def.kind ~= "path" and def.kind ~= "water") or #cells == 0 or #cells > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	if def.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local at: { [number]: Piece } = {}
	for _, q in p.plot.placed do
		if Plot.isTile(q.id) then
			at[Street.cellKey(q.x, q.z)] = q
		end
	end
	local used, most = count(p.plot.placed, "tile"), Plot.pathLimit(p.tier)
	local laid, swapped, skipped = 0, 0, 0
	local why: ErrCode = "blocked"
	for _, c in cells do
		local k = Street.cellKey(c[1], c[2])
		local old = at[k]
		if old and old.id == id then
			skipped += 1
		elseif old and old.rot == 0 and kindOf(old.id) == def.kind then
			if swapDrawn(p, old, id) then
				swapped += 1
			else
				why = if p.wood < def.wood then "wood" else "money"
				break
			end
		else
			if used >= most then
				why = "full"
				break
			end
			if p.shells < def.shells then
				why = "money"
				break
			end
			if p.wood < def.wood then
				why = "wood"
				break
			end
			if Plot.fits(p.tier, p.plot.placed, id, c[1], c[2], 0) then
				p.shells -= def.shells
				p.wood -= def.wood
				local uid = p.nextId
				p.nextId += 1
				local q: Piece = { uid = uid, id = id, x = c[1], z = c[2], rot = 0, lvl = 1 }
				table.insert(p.plot.placed, q)
				at[k] = q
				p.stats.built += 1
				used += 1
				laid += 1
			else
				skipped += 1
			end
		end
	end
	if laid + swapped == 0 then
		return false, why
	end
	return true, { placed = laid, swapped = swapped, skipped = skipped }
end

-- Clear the pieces at the indices in `gone` away, `share` of each one's price back (workers to rest, huts emptied).
local function clearOut(p: Profile, gone: { [number]: boolean }, share: number)
	local keep: { Piece } = {}
	for i, q in p.plot.placed do
		if gone[i] then
			local def = Buildings.byId[q.id]
			if def then
				p.shells += math.floor(def.shells * share)
				p.wood += math.floor(def.wood * share)
			end
			for _, x in p.pals do
				if x.work == q.uid then
					x.work = 0
				end
			end
			unhouse(p, q.uid)
		else
			table.insert(keep, q)
		end
	end
	p.plot.placed = keep
end

-- Take up every tile of `kind` ("path", "water" or "all") that covers one of the cells' studs (Erase), half its price
-- back each. Anything that floats (water "on") left off the water comes up with it, half its price back too. True with
-- { removed, floated }, else not_found.
function Plot.unpaint(p: Profile, cells: { { number } }, kind: string?): (boolean, any)
	if #cells == 0 or #cells > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	local want = kind or "all"
	local hit: { [number]: boolean } = {}
	local removed = 0
	local wet = false
	for i, q in p.plot.placed do
		local k = kindOf(q.id)
		if (k == "path" or k == "water") and (want == "all" or want == k) then
			local r = Plot.rect(q.id, q.x, q.z, q.rot)
			for _, c in cells do
				if c[1] < r.x1 and c[1] + Plot.PATH_STEP > r.x0 and c[2] < r.z1 and c[2] + Plot.PATH_STEP > r.z0 then
					hit[i] = true
					removed += 1
					wet = wet or k == "water"
					break
				end
			end
		end
	end
	if removed == 0 then
		return false, "not_found" :: ErrCode
	end
	-- (what floated on the water taken up goes with it)
	local floated = 0
	if wet then
		local after: { Piece } = {}
		for i, q in p.plot.placed do
			if not hit[i] then
				table.insert(after, q)
			end
		end
		for i, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			if not hit[i] and d and d.water == "on" and not onWater(Plot.rect(q.id, q.x, q.z, q.rot), after) then
				hit[i] = true
				floated += 1
			end
		end
	end
	clearOut(p, hit, Tuning.Refund)
	return true, { removed = removed, floated = floated }
end

-- Put fence lengths of `id` along the edges in order, while the fence room and the stores last. A length of another
-- fence on an edge is swapped for this one (half its price back); an edge where it doesn't fit is passed over. True
-- with { placed, swapped, skipped } when at least one changed, else why none could.
function Plot.fence(p: Profile, id: string, edges: { { number } }): (boolean, any)
	local def = Buildings.byId[id]
	if def == nil or def.kind ~= "fence" or #edges == 0 or #edges > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	if def.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local at: { [string]: Piece } = {}
	for _, q in p.plot.placed do
		if Plot.isFence(q.id) then
			at[q.x .. "," .. q.z .. "," .. q.rot % 180] = q
		end
	end
	local used, most = count(p.plot.placed, "fence"), Plot.fenceLimit(p.tier)
	local laid, swapped, skipped = 0, 0, 0
	local why: ErrCode = "blocked"
	for _, e in edges do
		local rot = e[3]
		if rot ~= 0 and rot ~= 90 then
			skipped += 1
			continue
		end
		local k = e[1] .. "," .. e[2] .. "," .. rot
		local old = at[k]
		if old and old.id == id then
			skipped += 1
		elseif old then
			if swapDrawn(p, old, id) then
				swapped += 1
			else
				why = if p.wood < def.wood then "wood" else "money"
				break
			end
		else
			if used >= most then
				why = "full"
				break
			end
			if p.shells < def.shells then
				why = "money"
				break
			end
			if p.wood < def.wood then
				why = "wood"
				break
			end
			if fenceFits(p.tier, p.plot.placed, e[1], e[2], rot, nil) then
				p.shells -= def.shells
				p.wood -= def.wood
				local uid = p.nextId
				p.nextId += 1
				local q: Piece = { uid = uid, id = id, x = e[1], z = e[2], rot = rot, lvl = 1 }
				table.insert(p.plot.placed, q)
				at[k] = q
				p.stats.built += 1
				used += 1
				laid += 1
			else
				skipped += 1
			end
		end
	end
	if laid + swapped == 0 then
		return false, why
	end
	return true, { placed = laid, swapped = swapped, skipped = skipped }
end

-- Take the fence lengths on the edges down, half their price back each. True with { removed }, else not_found.
function Plot.unfence(p: Profile, edges: { { number } }): (boolean, any)
	if #edges == 0 or #edges > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	local want: { [string]: boolean } = {}
	for _, e in edges do
		want[e[1] .. "," .. e[2] .. "," .. e[3] % 180] = true
	end
	local hit: { [number]: boolean } = {}
	local removed = 0
	for i, q in p.plot.placed do
		if Plot.isFence(q.id) and want[q.x .. "," .. q.z .. "," .. q.rot % 180] then
			hit[i] = true
			removed += 1
		end
	end
	if removed == 0 then
		return false, "not_found" :: ErrCode
	end
	clearOut(p, hit, Tuning.Refund)
	return true, { removed = removed }
end

function Plot.move(p: Profile, i: number, x: number, z: number, rot: number): (boolean, any)
	local q = p.plot.placed[i]
	if q == nil then
		return false, "bad_payload" :: ErrCode
	end
	if not Plot.fits(p.tier, p.plot.placed, q.id, x, z, rot, i) then
		return false, "blocked" :: ErrCode
	end
	q.x, q.z, q.rot = x, z, rot
	return true, nil
end

-- What replacing piece `q` with `id` costs: the new one's price less what clearing the old away gives back (never
-- below nothing).
function Plot.replaceCost(q: Piece, id: string): { shells: number, wood: number }?
	local old, new = Buildings.byId[q.id], Buildings.byId[id]
	if old == nil or new == nil then
		return nil
	end
	return {
		shells = math.max(0, new.shells - math.floor(old.shells * Tuning.Refund)),
		wood = math.max(0, new.wood - math.floor(old.wood * Tuning.Refund)),
	}
end

-- The pieces piece `q` may be replaced with: the others of its kind open at the tier (the island's own list order); a
-- decor piece's from its own row (Data/Buildings tab and sub); none for the tree or a drawn piece (draw over it).
function Plot.replacements(q: Piece, tier: number): { string }
	local old = Buildings.byId[q.id]
	local out: { string } = {}
	if old == nil or old.kind == "tree" or Plot.isDrawn(old.id) then
		return out
	end
	for _, d in Buildings.list do
		-- (decor: the others in its row of Build mode's tab, a tree for a tree, a bench for a bench)
		if d.kind == old.kind and d.id ~= old.id and d.tier <= tier and (old.kind ~= "decor" or (d.tab == old.tab and d.sub == old.sub)) then
			table.insert(out, d.id)
		end
	end
	return out
end

-- Replace piece i with another of its kind where it stands (GAME_DESIGN 4.1: a hut for a den, a patch for an
-- orchard): its uid stays (its workers stay), its level starts again at 1. bad_payload
-- (another kind, the same piece, the tree), locked (a bigger island's), money / wood, blocked (the new footprint does
-- not fit there). A smaller hut keeps the driftlings it has room for; the rest are left with no hut.
function Plot.replace(p: Profile, i: number, id: string): (boolean, any)
	local q = p.plot.placed[i]
	local old, new = if q then Buildings.byId[q.id] else nil, Buildings.byId[id]
	if q == nil or old == nil or new == nil or new.kind ~= old.kind or new.id == old.id or old.kind == "tree" then
		return false, "bad_payload" :: ErrCode
	end
	-- (drawn pieces aren't replaced; decor only from its own row, as Plot.replacements offers)
	if Plot.isDrawn(old.id) or (old.kind == "decor" and (new.tab ~= old.tab or new.sub ~= old.sub)) then
		return false, "bad_payload" :: ErrCode
	end
	if new.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local cost = Plot.replaceCost(q, id) :: { shells: number, wood: number }
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < cost.wood then
		return false, "wood" :: ErrCode
	end
	if not Plot.fits(p.tier, p.plot.placed, id, q.x, q.z, q.rot, i) then
		return false, "blocked" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	q.id = id
	q.lvl = 1
	if new.kind == "nest" then
		unhouse(p, q.uid, new.slots)
	end
	-- (its helpers stay: any driftling works anywhere)
	p.stats.built += 1
	return true, { i = i, uid = q.uid, id = id }
end

-- After the island grew (its lodge bigger, its path and sign moved): every piece that no longer fits moves to the free
-- spot nearest its old one (turned a quarter if that fits closer); one with no spot left is cleared away with its whole
-- price back and its workers idle. Returns how many moved and how many were cleared.
function Plot.refit(p: Profile): (number, number)
	local kept: { Piece } = {}
	local homeless: { Piece } = {}
	-- (the tree first: it keeps its place, the rest make room round it)
	local order: { Piece } = {}
	for _, q in p.plot.placed do
		if Plot.isFixed(q.id) then
			table.insert(order, 1, q)
		else
			table.insert(order, q)
		end
	end
	for _, q in order do
		if Plot.fits(p.tier, kept, q.id, q.x, q.z, q.rot) then
			table.insert(kept, q)
		else
			table.insert(homeless, q)
		end
	end
	if #homeless == 0 then
		return 0, 0
	end
	local moved, cleared = 0, 0
	local gone: { [Piece]: boolean } = {}
	for _, q in homeless do
		-- (a tile or a fence isn't moved somewhere else: it's cleared away below)
		local bx, bz, brot = nil, nil, nil
		if not Plot.isDrawn(q.id) then
			bx, bz, brot = Plot.spot(p.tier, kept, q.id, q.x, q.z, q.rot)
		end
		if bx and bz and brot then
			q.x, q.z, q.rot = bx, bz, brot
			table.insert(kept, q)
			moved += 1
		elseif Plot.isFixed(q.id) then
			-- (the tree is never cleared away: it stays where it stood)
			table.insert(kept, q)
		else
			local def = Buildings.byId[q.id]
			if def then
				p.shells += def.shells
				p.wood += def.wood
			end
			for _, x in p.pals do
				if x.work == q.uid then
					x.work = 0
				end
			end
			unhouse(p, q.uid)
			gone[q] = true
			cleared += 1
		end
	end
	if cleared > 0 then
		local keep: { Piece } = {}
		for _, q in p.plot.placed do
			if not gone[q] then
				table.insert(keep, q)
			end
		end
		p.plot.placed = keep
	end
	return moved, cleared
end

-- Clear a piece away: a share of its price back; its workers go to rest, a hut's driftlings are left with no hut. Not
-- the tree (fixed), not a Hatchery warming an egg (egg).
function Plot.store(p: Profile, i: number): (boolean, any)
	local q = p.plot.placed[i]
	if q == nil then
		return false, "bad_payload" :: ErrCode
	end
	if Plot.isFixed(q.id) then
		return false, "fixed" :: ErrCode
	end
	local def = Buildings.byId[q.id]
	if def then
		-- a Hatchery keeps its egg: not cleared away till it hatches (Logic/Breed)
		local eggs: { Types.Egg } = p.eggs or {}
		for _, egg in eggs do
			if egg.uid == q.uid then
				return false, "egg" :: ErrCode
			end
		end
		p.shells += math.floor(def.shells * Tuning.Refund)
		p.wood += math.floor(def.wood * Tuning.Refund)
	end
	for _, pal in p.pals do
		if pal.work == q.uid then
			pal.work = 0
		end
	end
	unhouse(p, q.uid)
	table.remove(p.plot.placed, i)
	return true, nil
end

return Plot
