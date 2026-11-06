--!strict
-- The plot's rules (GAME_DESIGN 13; docs/ARCHITECTURE.md 6): where decor may stand, buying, placing, moving and
-- storing it. Pure. Positions are plot-local whole studs: a piece's (x, z) is its footprint's north-west corner, its
-- rot a quarter turn (0, 90, 180, 270; 90 and 270 swap the footprint's width and depth).
-- A piece stands wholly on the plot (Data/Street PLOT of the office's tier) a stud in from its edges, off the office
-- (its room, walls and a stud round them), the footpath, the plot sign and the mailbox, and off every other piece.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Office = require(script.Parent.Parent.Data.Office)
local Street = require(script.Parent.Parent.Data.Street)
local Decor = require(script.Parent.Parent.Data.Decor)

type Profile = Types.Profile
type Piece = Types.Piece
type ErrCode = Types.ErrCode
type Rect = Street.Rect

local Plot = {}

Plot.ROTS = { 0, 90, 180, 270 }

function Plot.limit(tier: number): number
	return Tuning.PlotPieces[math.clamp(math.floor(tier), 1, #Tuning.PlotPieces)]
end

-- The footprint (w along x, d along z) of a piece turned by rot.
function Plot.footprint(id: string, rot: number): (number, number)
	local def = Decor.byId[id]
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

-- The fixed things on a plot no piece may cover (plot-local): the office with a stud round it, the footpath, the
-- sign and the mailbox.
function Plot.blockers(tier: number): { Rect }
	local plan = Office.plan(tier)
	local t = Office.WALL_T
	local fp = Street.footpath(plan.maxX, plan.maxZ)
	local sx, sz = Street.sign(plan.maxX, plan.maxZ)
	local mx, mz = Street.mailbox(plan.maxX, plan.maxZ)
	return {
		{ x0 = plan.minX - t - 1, z0 = plan.minZ - t - 1, x1 = plan.maxX + 1, z1 = plan.maxZ + 1 },
		{ x0 = fp.x0 - 0.5, z0 = fp.z0, x1 = fp.x1 + 0.5, z1 = fp.z1 },
		{ x0 = sx - 1.5, z0 = sz - 1, x1 = sx + 1.5, z1 = sz + 1 },
		{ x0 = mx - 0.75, z0 = mz - 0.75, x1 = mx + 0.75, z1 = mz + 0.75 },
	}
end

local ROT_OK: { [number]: boolean } = { [0] = true, [90] = true, [180] = true, [270] = true }

-- Whether piece `id` fits at (x, z, rot) on a plot of `tier` with these pieces (skip = the index of the piece being
-- moved). Returns true, or false and why: "outside" (off the plot or not on the grid), "blocked" (the office, the
-- footpath, the sign or the mailbox), "overlap" (another piece), "unknown" (no such piece).
function Plot.fits(tier: number, placed: { Piece }, id: string, x: number, z: number, rot: number, skip: number?): (boolean, string?)
	if Decor.byId[id] == nil then
		return false, "unknown"
	end
	if x ~= math.floor(x) or z ~= math.floor(z) or not ROT_OK[rot] then
		return false, "outside"
	end
	local r = Plot.rect(id, x, z, rot)
	local p = Street.plot(tier)
	if r.x0 < p.x0 + 1 or r.x1 > p.x1 - 1 or r.z0 < p.z0 + 1 or r.z1 > p.z1 - 1 then
		return false, "outside"
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
	return true, nil
end

------------------------------------------------------------------ actions (change the profile only on success)
function Plot.buy(p: Profile, id: string): (boolean, any)
	local def = Decor.byId[id]
	if def == nil then
		return false, "bad_payload" :: ErrCode
	end
	if p.plot.owned[id] then
		return false, "max" :: ErrCode
	end
	if p.office < def.office then
		return false, "locked" :: ErrCode
	end
	if p.money < def.price then
		return false, "money" :: ErrCode
	end
	p.money -= def.price
	p.fans += def.fans
	p.plot.owned[id] = true
	return true, { fans = def.fans }
end

function Plot.place(p: Profile, id: string, x: number, z: number, rot: number): (boolean, any)
	if not p.plot.owned[id] then
		return false, "locked" :: ErrCode
	end
	if #p.plot.placed >= Plot.limit(p.office) then
		return false, "full" :: ErrCode
	end
	local ok = Plot.fits(p.office, p.plot.placed, id, x, z, rot)
	if not ok then
		return false, "blocked" :: ErrCode
	end
	table.insert(p.plot.placed, { id = id, x = x, z = z, rot = rot })
	return true, { i = #p.plot.placed }
end

function Plot.move(p: Profile, i: number, x: number, z: number, rot: number): (boolean, any)
	local q = p.plot.placed[i]
	if q == nil then
		return false, "bad_payload" :: ErrCode
	end
	local ok = Plot.fits(p.office, p.plot.placed, q.id, x, z, rot, i)
	if not ok then
		return false, "blocked" :: ErrCode
	end
	q.x, q.z, q.rot = x, z, rot
	return true, nil
end

function Plot.store(p: Profile, i: number): (boolean, any)
	if p.plot.placed[i] == nil then
		return false, "bad_payload" :: ErrCode
	end
	table.remove(p.plot.placed, i)
	return true, nil
end

-- After the office changed (a move to a bigger office): the pieces that no longer fit go back in the box (they stay
-- owned). Returns how many went.
function Plot.clean(p: Profile): number
	local keep: { Piece } = {}
	local gone = 0
	for _, q in p.plot.placed do
		if #keep < Plot.limit(p.office) and Plot.fits(p.office, keep, q.id, q.x, q.z, q.rot) then
			table.insert(keep, q)
		else
			gone += 1
		end
	end
	p.plot.placed = keep
	return gone
end

return Plot
