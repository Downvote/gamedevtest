--!strict
-- Build mode's Undo (GAME_DESIGN 4.7; docs/ARCHITECTURE.md 6). Pure. The request of 2026-11-21: "add an undo button,
-- selection tool and saving/loading of plots". Every build action a player takes (a piece put down, moved, turned, put
-- away, replaced; tiles and fences drawn or rubbed out; Remove all; a group moved, put away or copied; a layout loaded;
-- pieces sold from the inventory) is one step on the session's stack (IslandService keeps it: Tuning.UndoSteps steps,
-- Tuning.UndoRecords pieces and driftlings across them, the newest always kept). A step is what the action changed, not
-- a copy of the island: the pieces it took away (as they stood), the uids it put down, the pieces it moved (as they
-- stood), the inventory and the coins by how much they changed, and the driftlings whose hut or work changed. Undo
-- puts each back, so the coins come back by what the action cost (income since then stays), and is refused with a
-- reason when the island no longer allows it. The stack lives on the server only and goes when the session ends or
-- the island grows.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Piece = Types.Piece
type ErrCode = Types.ErrCode

local Undo = {}

type PalWas = { id: number, home: number, work: number, pin: boolean? }

-- The island before an action (Undo.capture): every piece as it stood, the inventory, the coins, the build count, each
-- driftling's hut and work.
export type Snap = {
	pieces: { [number]: Piece },
	inv: { [string]: number },
	shells: number,
	built: number,
	pals: { [number]: PalWas },
}

-- One action's change (Undo.diff), and what an undo puts back.
export type Step = {
	what: string, -- the action (its Validate name), for the client's notice
	gone: { Piece }, -- pieces the action took away, as they stood
	added: { number }, -- uids the action put down
	moved: { Piece }, -- pieces the action moved, turned or swapped, as they stood
	inv: { [string]: number }, -- what the inventory held before less what it holds after
	shells: number, -- coins before less after (what the action cost; negative for a sale)
	built: number, -- the build count after less before
	pals: { PalWas }, -- driftlings whose hut or work changed, as they were
	size: number, -- records held (Tuning.UndoRecords)
}

local function copy(q: Piece): Piece
	return { uid = q.uid, id = q.id, x = q.x, z = q.z, rot = q.rot, lvl = q.lvl }
end

function Undo.capture(p: Profile): Snap
	local pieces: { [number]: Piece } = {}
	for _, q in p.plot.placed do
		pieces[q.uid] = copy(q)
	end
	local pals: { [number]: PalWas } = {}
	for _, x in p.pals do
		pals[x.id] = { id = x.id, home = x.home, work = x.work, pin = x.pin }
	end
	return { pieces = pieces, inv = table.clone(p.inv or {}), shells = p.shells, built = p.stats.built, pals = pals }
end

-- What changed between `before` and the profile now; nil when nothing did.
function Undo.diff(before: Snap, p: Profile, what: string): Step?
	local gone: { Piece } = {}
	local added: { number } = {}
	local moved: { Piece } = {}
	local now: { [number]: boolean } = {}
	for _, q in p.plot.placed do
		now[q.uid] = true
		local b = before.pieces[q.uid]
		if b == nil then
			table.insert(added, q.uid)
		elseif b.id ~= q.id or b.x ~= q.x or b.z ~= q.z or b.rot ~= q.rot or b.lvl ~= q.lvl then
			table.insert(moved, b)
		end
	end
	for uid, b in before.pieces do
		if not now[uid] then
			table.insert(gone, b)
		end
	end
	local inv: { [string]: number } = {}
	local nInv = 0
	local after: { [string]: number } = p.inv or {}
	for id, n in before.inv do
		local d = n - (after[id] or 0)
		if d ~= 0 then
			inv[id] = d
			nInv += 1
		end
	end
	for id, n in after do
		if before.inv[id] == nil and n ~= 0 then
			inv[id] = -n
			nInv += 1
		end
	end
	local pals: { PalWas } = {}
	for _, x in p.pals do
		local b = before.pals[x.id]
		if b and (b.home ~= x.home or b.work ~= x.work or b.pin ~= x.pin) then
			table.insert(pals, b)
		end
	end
	local shells = before.shells - p.shells
	local built = p.stats.built - before.built
	if #gone + #added + #moved + nInv + #pals == 0 and shells == 0 then
		return nil
	end
	-- (the tree goes back first, then the water, so what floats on it finds it)
	table.sort(gone, function(a: Piece, b: Piece): boolean
		return Plot.groupRank(a.id) < Plot.groupRank(b.id)
	end)
	return {
		what = what,
		gone = gone,
		added = added,
		moved = moved,
		inv = inv,
		shells = shells,
		built = built,
		pals = pals,
		size = 1 + #gone + #added + #moved + nInv + #pals,
	}
end

-- A step onto the stack, the oldest dropped past Tuning.UndoSteps steps or Tuning.UndoRecords records (the newest is
-- always kept, however big).
function Undo.push(stack: { Step }, step: Step)
	table.insert(stack, step)
	local total = 0
	for _, s in stack do
		total += s.size
	end
	while #stack > 1 and (#stack > Tuning.UndoSteps or total > Tuning.UndoRecords) do
		total -= stack[1].size
		table.remove(stack, 1)
	end
end

-- Whether `step` can be taken back on `p` now: true, or false and why (not_found: a piece it put down or moved is no
-- longer there, or the inventory no longer holds what it put away; egg: a Hatchery it put down warms an egg; money: the
-- coins a sale gave are spent; blocked: a piece would not fit where it stood; full / huts / work / hatcheries / boosts:
-- the island's limits). With the island it would leave.
local function check(p: Profile, step: Step): (boolean, any, { Piece }?)
	local byUid: { [number]: Piece } = {}
	for _, q in p.plot.placed do
		byUid[q.uid] = q
	end
	local drop: { [number]: boolean } = {}
	local warming: { [number]: boolean } = {}
	local eggs: { Types.Egg } = p.eggs or {}
	for _, egg in eggs do
		warming[egg.uid] = true
	end
	for _, uid in step.added do
		local q = byUid[uid]
		if q == nil then
			return false, "not_found", nil
		end
		if warming[uid] then
			return false, "egg", nil
		end
		drop[uid] = true
	end
	local was: { [number]: Piece } = {}
	for _, b in step.moved do
		if byUid[b.uid] == nil or drop[b.uid] or Buildings.byId[b.id] == nil then
			return false, "not_found", nil
		end
		was[b.uid] = b
	end
	for _, b in step.gone do
		if byUid[b.uid] ~= nil or Buildings.byId[b.id] == nil then
			return false, "not_found", nil
		end
	end
	local inv = p.inv or {}
	for id, d in step.inv do
		if (inv[id] or 0) + d < 0 then
			return false, "not_found", nil
		end
	end
	if p.shells + step.shells < 0 then
		return false, "money", nil
	end
	-- the island after: the pieces put down gone, the moved ones where they stood, the ones taken away back
	local result: { Piece } = {}
	local back: { Piece } = {}
	for _, q in p.plot.placed do
		if not drop[q.uid] then
			local b = was[q.uid]
			if b then
				local r = copy(b)
				table.insert(result, r)
				table.insert(back, r)
			else
				table.insert(result, q)
			end
		end
	end
	for _, b in step.gone do
		local r = copy(b)
		table.insert(result, r)
		table.insert(back, r)
	end
	-- (each piece going back against the whole island after, itself left out)
	local idx = Plot.index(result)
	for _, r in back do
		if not Plot.fitsNear(p.tier, idx, r.id, r.x, r.z, r.rot, r) then
			return false, "blocked", nil
		end
	end
	local okLimits, why = Plot.limitsOk(p.tier, result, p.plot.placed)
	if not okLimits then
		return false, why, nil
	end
	return true, nil, result
end

function Undo.can(p: Profile, step: Step): (boolean, any)
	local ok, why = check(p, step)
	return ok, why
end

-- Take `step` back on `p`, all or nothing. True with { what }, else false and why (check's codes).
function Undo.apply(p: Profile, step: Step): (boolean, any)
	local ok, why, result = check(p, step)
	if not ok or result == nil then
		return false, why
	end
	local keep: { [number]: boolean } = {}
	for _, q in result do
		keep[q.uid] = true
	end
	-- (the pieces it put down go: their workers rest, their huts empty; nothing goes into the inventory, which takes
	-- its own change back below)
	for _, uid in step.added do
		if not keep[uid] then
			Plot.freeWorkers(p, uid)
			Plot.unhouse(p, uid)
		end
	end
	-- (a moved piece keeps its table: what points at it stays)
	local byUid: { [number]: Piece } = {}
	for _, q in p.plot.placed do
		byUid[q.uid] = q
	end
	local placed: { Piece } = {}
	for _, r in result do
		local q = byUid[r.uid]
		if q then
			q.id, q.x, q.z, q.rot, q.lvl = r.id, r.x, r.z, r.rot, r.lvl
			table.insert(placed, q)
		else
			table.insert(placed, r)
		end
	end
	p.plot.placed = placed
	local inv = p.inv
	for id, d in step.inv do
		local n = math.min(Plot.INV_MAX, (inv[id] or 0) + d)
		if n > 0 then
			inv[id] = n
		else
			(inv :: any)[id] = nil
		end
	end
	p.shells += step.shells
	p.stats.built = math.max(0, p.stats.built - step.built)
	-- the driftlings back in their huts and at their work, where those have room (one moved since keeps its own)
	local inHut: { [number]: number } = {}
	local atWork: { [number]: number } = {}
	local back: { [number]: PalWas } = {}
	for _, w in step.pals do
		back[w.id] = w
	end
	for _, x in p.pals do
		if back[x.id] == nil then
			if x.home ~= 0 then
				inHut[x.home] = (inHut[x.home] or 0) + 1
			end
			if x.work ~= 0 then
				atWork[x.work] = (atWork[x.work] or 0) + 1
			end
		end
	end
	local after: { [number]: Piece } = {}
	for _, q in placed do
		after[q.uid] = q
	end
	for _, x in p.pals do
		local w = back[x.id]
		if w then
			local hq = after[w.home]
			local hd = if hq then Buildings.byId[hq.id] else nil
			local home = 0
			if w.home ~= 0 and hd and hd.kind == "nest" and (inHut[w.home] or 0) < hd.slots then
				home = w.home
				inHut[home] = (inHut[home] or 0) + 1
			end
			local work = 0
			if home ~= 0 and w.work ~= 0 then
				local wq = after[w.work]
				local wd = if wq then Buildings.byId[wq.id] else nil
				if wd and wd.jobs > (atWork[w.work] or 0) then
					work = w.work
					atWork[work] = (atWork[work] or 0) + 1
				end
			end
			x.home, x.work = home, work
			x.pin = if home ~= 0 and w.pin == true then true else nil
		end
	end
	return true, { what = step.what }
end

return Undo
