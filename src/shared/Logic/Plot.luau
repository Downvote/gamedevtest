--!strict
-- The island's building rules (GAME_DESIGN 4; docs/ARCHITECTURE.md 6): where buildings and decor may stand, placing
-- (paid in shells and wood), moving and clearing them away. Pure. Positions are plot-local whole studs: a piece's
-- (x, z) is its footprint's north-west corner, its rot a quarter turn (0, 90, 180, 270; 90 and 270 swap the
-- footprint's width and depth). A piece stands wholly on the island's buildable cells (Data/Street: the grass a stud
-- in from its edge, the island's shape by its tier), off the plaza round the campfire and the path to the jetty, and
-- off every other piece. A wild place (Data/Sites: a piece of kind "site" still wild) keeps a ring of Tuning.SiteRadius
-- studs round it clear of anything new, can't be moved or cleared away, and isn't counted in the piece limit (no
-- place is); once cleared it is a piece like any other.
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
function Plot.pathLimit(tier: number): number
	return Tuning.PathPieces[math.clamp(math.floor(tier), 1, #Tuning.PathPieces)]
end

-- Whether a piece is a path tile (counted apart).
function Plot.isPath(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and d.kind == "path"
end

-- Whether a piece is a wild place (Data/Sites), or any place, wild or cleared.
function Plot.isWild(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and d.kind == "site" and string.sub(id, 1, 5) == "wild_"
end
function Plot.isSite(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and d.kind == "site"
end

-- How many pieces of the same count as `id` stand (paths, or the rest: the wild places never count), and that
-- count's limit.
function Plot.used(p: Profile, id: string): (number, number)
	local path = Plot.isPath(id)
	local n = 0
	for _, q in p.plot.placed do
		if Plot.isPath(q.id) == path and not Plot.isSite(q.id) then
			n += 1
		end
	end
	return n, if path then Plot.pathLimit(p.tier) else Plot.limit(p.tier)
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

-- The ring a wild place keeps clear: its footprint and Tuning.SiteRadius studs round it.
function Plot.zone(q: Piece): Rect
	local r = Plot.rect(q.id, q.x, q.z, q.rot)
	local k = Tuning.SiteRadius
	return { x0 = r.x0 - k, z0 = r.z0 - k, x1 = r.x1 + k, z1 = r.z1 + k }
end

-- The fixed things on an island no piece may cover (plot-local): the plaza round the campfire and the path to the
-- jetty (the same on every tier).
function Plot.blockers(_tier: number): { Rect }
	return { Street.PLAZA, Street.PATH }
end

local ROT_OK: { [number]: boolean } = { [0] = true, [90] = true, [180] = true, [270] = true }

-- Whether piece `id` fits at (x, z, rot) on an island of `tier` with these pieces (skip = the index of the piece
-- being moved). Returns true, or false and why: "outside" (off the buildable grass or not on the grid), "blocked"
-- (the plaza or the path), "overlap" (another piece), "wild" (inside a wild place's ring), "unknown" (no such
-- piece). `loose`: the rings are not checked (pieces already standing, a place itself coming up: Logic/Sites).
function Plot.fits(tier: number, placed: { Piece }, id: string, x: number, z: number, rot: number, skip: number?, loose: boolean?): (boolean, string?)
	if Buildings.byId[id] == nil then
		return false, "unknown"
	end
	if x ~= math.floor(x) or z ~= math.floor(z) or not ROT_OK[rot] then
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
	for i, q in placed do
		if i ~= skip and overlaps(r, Plot.rect(q.id, q.x, q.z, q.rot)) then
			return false, "overlap"
		end
	end
	if not loose then
		for i, q in placed do
			if i ~= skip and Plot.isWild(q.id) and overlaps(r, Plot.zone(q)) then
				return false, "wild"
			end
		end
	end
	return true, nil
end

-- The refusal for a spot that doesn't fit: "wild" inside a wild place's ring, else "blocked".
local function misfit(why: string?): ErrCode
	return if why == "wild" then "wild" else "blocked"
end

------------------------------------------------------------------ actions (change the profile only on success)
-- Place a new piece: its tier reached, room under the island's limit, its price in shells and wood. A building that
-- takes a worker gets an idle villager if there is one.
function Plot.place(p: Profile, id: string, x: number, z: number, rot: number): (boolean, any)
	local def = Buildings.byId[id]
	if def == nil or def.kind == "site" then
		return false, "bad_payload" :: ErrCode
	end
	if def.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local used, most = Plot.used(p, id)
	if used >= most then
		return false, "full" :: ErrCode
	end
	if p.shells < def.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < def.wood then
		return false, "wood" :: ErrCode
	end
	local ok, why = Plot.fits(p.tier, p.plot.placed, id, x, z, rot)
	if not ok then
		return false, misfit(why)
	end
	p.shells -= def.shells
	p.wood -= def.wood
	local uid = p.nextId
	p.nextId += 1
	table.insert(p.plot.placed, { uid = uid, id = id, x = x, z = z, rot = rot, lvl = 1 })
	p.stats.built += 1
	if def.kind == "food" or def.kind == "wood" or def.kind == "shop" then
		for _, v in p.folk do
			if v.work == 0 then
				v.work = uid
				break
			end
		end
	end
	return true, { i = #p.plot.placed, uid = uid }
end

------------------------------------------------------------------ drawing paths (GAME_DESIGN 4: a line or a box)
-- Path tiles are 2 x 2 and drawn on the even studs (a cell is a tile's north-west corner); a request carries at most
-- PAINT_MAX cells, written "x,z;x,z;..." (Validate's "cells").
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

-- Lay path tiles of `id` on the cells in order, while the island's path room and the stores last; a cell where a tile
-- doesn't fit is passed over. True with { placed, skipped } when at least one went down, else why none could.
function Plot.paint(p: Profile, id: string, cells: { { number } }): (boolean, any)
	local def = Buildings.byId[id]
	if def == nil or def.kind ~= "path" or #cells == 0 or #cells > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	if def.tier > p.tier then
		return false, "locked" :: ErrCode
	end
	local laid, skipped = 0, 0
	local why: ErrCode = "blocked"
	for _, c in cells do
		local used, most = Plot.used(p, id)
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
		local fit, whyNot = Plot.fits(p.tier, p.plot.placed, id, c[1], c[2], 0)
		if not fit and whyNot == "wild" then
			why = "wild"
		end
		if fit then
			p.shells -= def.shells
			p.wood -= def.wood
			local uid = p.nextId
			p.nextId += 1
			table.insert(p.plot.placed, { uid = uid, id = id, x = c[1], z = c[2], rot = 0, lvl = 1 })
			p.stats.built += 1
			laid += 1
		else
			skipped += 1
		end
	end
	if laid == 0 then
		return false, why
	end
	return true, { placed = laid, skipped = skipped }
end

-- Take up every path tile that covers one of the cells' studs (Erase), half its price back each.
function Plot.unpaint(p: Profile, cells: { { number } }): (boolean, any)
	if #cells == 0 or #cells > Plot.PAINT_MAX then
		return false, "bad_payload" :: ErrCode
	end
	local hit: { [number]: boolean } = {}
	for i, q in p.plot.placed do
		if Plot.isPath(q.id) then
			local r = Plot.rect(q.id, q.x, q.z, q.rot)
			for _, c in cells do
				if c[1] < r.x1 and c[1] + Plot.PATH_STEP > r.x0 and c[2] < r.z1 and c[2] + Plot.PATH_STEP > r.z0 then
					hit[i] = true
					break
				end
			end
		end
	end
	local keep: { Piece } = {}
	local removed = 0
	for i, q in p.plot.placed do
		if hit[i] then
			local def = Buildings.byId[q.id]
			if def then
				p.shells += math.floor(def.shells * Tuning.Refund)
				p.wood += math.floor(def.wood * Tuning.Refund)
			end
			removed += 1
		else
			table.insert(keep, q)
		end
	end
	if removed == 0 then
		return false, "not_found" :: ErrCode
	end
	p.plot.placed = keep
	return true, { removed = removed }
end

function Plot.move(p: Profile, i: number, x: number, z: number, rot: number): (boolean, any)
	local q = p.plot.placed[i]
	if q == nil then
		return false, "bad_payload" :: ErrCode
	end
	if Plot.isWild(q.id) then
		return false, "wild" :: ErrCode
	end
	local ok, why = Plot.fits(p.tier, p.plot.placed, q.id, x, z, rot, i)
	if not ok then
		return false, misfit(why)
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

-- The pieces piece `q` may be replaced with: the others of its kind open at the tier (the island's own list order).
function Plot.replacements(q: Piece, tier: number): { string }
	local old = Buildings.byId[q.id]
	local out: { string } = {}
	if old == nil or old.kind == "site" then
		return out
	end
	for _, d in Buildings.list do
		if d.kind == old.kind and d.id ~= old.id and d.tier <= tier then
			table.insert(out, d.id)
		end
	end
	return out
end

-- Replace piece i with another of its kind where it stands (GAME_DESIGN 4.1: a tent for a cottage, a nest for a
-- den, a patch for an orchard): its uid stays (its workers and helpers stay where the knack still fits), its level
-- starts again at 1. bad_payload (another kind, the same piece), locked (a bigger island's), money / wood, blocked
-- (the new footprint does not fit there), no_room (fewer beds or nests than the island needs), egg (a Hatchery's).
function Plot.replace(p: Profile, i: number, id: string): (boolean, any)
	local q = p.plot.placed[i]
	local old, new = if q then Buildings.byId[q.id] else nil, Buildings.byId[id]
	if q == nil or old == nil or new == nil or new.kind ~= old.kind or new.id == old.id or old.kind == "site" then
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
	if not Plot.fits(p.tier, p.plot.placed, id, q.x, q.z, q.rot, i, true) then
		return false, "blocked" :: ErrCode
	end
	local beds, slots = 0, 0
	for j, o in p.plot.placed do
		local od = if j == i then new else Buildings.byId[o.id]
		if od then
			beds += od.beds
			slots += od.slots
		end
	end
	if beds < #p.folk or slots < #p.pals then
		return false, "no_room" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	q.id = id
	q.lvl = 1
	-- helpers whose knack the new one does not take go back to rest
	for _, x in p.pals do
		if x.work == q.uid and new.knack ~= old.knack then
			x.work = 0
		end
	end
	p.stats.built += 1
	return true, { i = i, uid = q.uid, id = id }
end

-- After the island grew (its lodge bigger, its path and sign moved): every piece that no longer fits moves to the free
-- spot nearest its old one (turned a quarter if that fits closer); one with no spot left is cleared away with its whole
-- price back and its workers idle. Returns how many moved and how many were cleared.
function Plot.refit(p: Profile): (number, number)
	local kept: { Piece } = {}
	local homeless: { Piece } = {}
	-- (the wild places' rings don't move what already stands: `loose`)
	for _, q in p.plot.placed do
		if Plot.fits(p.tier, kept, q.id, q.x, q.z, q.rot, nil, true) then
			table.insert(kept, q)
		else
			table.insert(homeless, q)
		end
	end
	if #homeless == 0 then
		return 0, 0
	end
	local pr = Street.plot(p.tier)
	local moved, cleared = 0, 0
	local gone: { [Piece]: boolean } = {}
	for _, q in homeless do
		local best, bx, bz, brot = math.huge, 0, 0, q.rot
		for _, rot in { q.rot, (q.rot + 90) % 360 } do
			for z = math.floor(pr.z0) + 1, math.floor(pr.z1) - 1 do
				for x = math.floor(pr.x0) + 1, math.floor(pr.x1) - 1 do
					local d = (x - q.x) ^ 2 + (z - q.z) ^ 2 + (if rot == q.rot then 0 else 0.5)
					if d < best and Plot.fits(p.tier, kept, q.id, x, z, rot, nil, true) then
						best, bx, bz, brot = d, x, z, rot
					end
				end
			end
		end
		if best < math.huge then
			q.x, q.z, q.rot = bx, bz, brot
			table.insert(kept, q)
			moved += 1
		else
			local def = Buildings.byId[q.id]
			if def then
				p.shells += def.shells
				p.wood += def.wood
			end
			for _, v in p.folk do
				if v.work == q.uid then
					v.work = 0
				end
			end
			for _, x in p.pals do
				if x.work == q.uid then
					x.work = 0
				end
			end
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

-- Clear a piece away: a share of its price back; its workers go idle. Not a home or a nest whose beds are needed.
function Plot.store(p: Profile, i: number): (boolean, any)
	local q = p.plot.placed[i]
	if q == nil then
		return false, "bad_payload" :: ErrCode
	end
	if Plot.isWild(q.id) then
		return false, "wild" :: ErrCode
	end
	local def = Buildings.byId[q.id]
	if def then
		local beds, slots = 0, 0
		for j, o in p.plot.placed do
			local od = Buildings.byId[o.id]
			if od and j ~= i then
				beds += od.beds
				slots += od.slots
			end
		end
		if (def.beds > 0 and beds < #p.folk) or (def.slots > 0 and slots < #p.pals) then
			return false, "no_room" :: ErrCode
		end
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
	for _, v in p.folk do
		if v.work == q.uid then
			v.work = 0
		end
	end
	for _, pal in p.pals do
		if pal.work == q.uid then
			pal.work = 0
		end
	end
	table.remove(p.plot.placed, i)
	return true, nil
end

return Plot
