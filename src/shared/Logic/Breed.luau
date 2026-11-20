--!strict
-- The Hatchery (GAME_DESIGN 6.1: "make a breeding system that also works like in palworld that unlocks after a certain
-- island level"; 2026-11-15: "say Breed two driftlings for an egg"): two driftlings bred for an egg; it is ready after
-- a few island turns and hatches when the player taps its Hatchery (`hatch`), into a hut with room
-- (Logic/Tree.add: with none it waits with no hut till one has room).
-- The genre's system in our own numbers. Pure.
--   What hatches: the same kind from a pair of one kind; else the kind whose power (Data/Creatures `power`) lies
--   nearest the parents' average (the commoner, then the first by name, on a tie). A legend only hatches from two
--   legends, a mythic one from two mythic or rarer, and so on up: an eternal one only from two eternal ones. With the
--   island's tier given, only kinds of land open there (Data/Islets `tier`) hatch, besides the parents' own kinds.
--   Its mutations (Data/Traits), decided and shown before the egg is laid (the request of 2026-11-19: "In hatchery,
--   show the resultant mutation combination the pet will have. Always take the highest tier mutations to combine with
--   each other if possible"): every family either parent carries, at the better parent's tier, one both carry a tier
--   above that (at most 4; a wondrous or fabled one stays itself; a flaw both carry turns into its family's first tier,
--   a flaw only one carries is left behind), the highest tiers first (a fabled one before a wondrous one), at most four
--   (`inherit`, `preview`). Before, a parent's
--   own passed on half the time, a shared one came out a tier up now and then and a new one came now and then.
--   An egg is laid at a Hatchery with no egg (one each), for `BreedShells` shells by the child's rarity (food
--   till 2026-11-13), and takes `BreedTurns` turns (Island.turn's, while the player is here), times the huts'
--   Hatchery multiplier (Island.isle.hatch: each Hatchery share takes its part off what is left, Tuning.HatchMin at
--   most), at least one.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Islets = require(script.Parent.Parent.Data.Islets)
local Traits = require(script.Parent.Parent.Data.Traits)
local Island = require(script.Parent.Island)
local Tree = require(script.Parent.Tree)

type Profile = Types.Profile
type Egg = Types.Egg
type ErrCode = Types.ErrCode

local Breed = {}

-- What a pair hatches (species ids; `tier`: the island's, so a far kind's driftling never hatches early).
function Breed.child(a: string, b: string, tier: number?): string
	if a == b then
		return a
	end
	local da, db = Creatures.byId[a], Creatures.byId[b]
	if da == nil or db == nil then
		return if da then a else b
	end
	local avg = (da.power + db.power) / 2
	-- (legendary and up: no rarer than the commoner parent)
	local top = math.max(4, math.min(da.rarity, db.rarity))
	local best: Creatures.CreatureDef? = nil
	local bestD = math.huge
	for _, d in Creatures.list do
		local kind = Islets.list[d.islet]
		local open = tier == nil or kind == nil or kind.tier <= tier or d.id == a or d.id == b
		if d.rarity <= top and open then
			local dist = math.abs(d.power - avg)
			local better = false
			if best == nil or dist < bestD - 1e-9 then
				better = true
			elseif math.abs(dist - bestD) <= 1e-9 then
				local bd = best :: Creatures.CreatureDef
				better = d.rarity < bd.rarity or (d.rarity == bd.rarity and d.id < bd.id)
			end
			if better then
				best, bestD = d, dist
			end
		end
	end
	return if best then best.id else a
end

-- What an egg of a kind costs (shells) and the turns it takes to hatch (on this island when `p` is given: the huts'
-- Hatchery shares take some off, Island.isle).
function Breed.cost(sp: string, p: Profile?): (number, number)
	local d = Creatures.byId[sp]
	local r = if d then d.rarity else 1
	local turns = Tuning.BreedTurns[r] or Tuning.BreedTurns[1]
	if p then
		turns = math.max(1, math.ceil(turns * Island.isle(p).hatch - 1e-9))
	end
	return Tuning.BreedShells[r] or Tuning.BreedShells[1], turns
end

-- A child's mutations from its parents' (the best tiers, a shared family one tier up: the module's header).
function Breed.inherit(ma: { string }?, mb: { string }?): { string }
	type Pair = { family: string, a: string?, b: string? }
	local order: { Pair } = {}
	local byFam: { [string]: Pair } = {}
	local function add(list: { string }?, side: string)
		for _, id in Traits.clean(list) do
			local m = Traits.byId[id]
			local e = byFam[m.family]
			if e == nil then
				e = { family = m.family }
				byFam[m.family] = e
				table.insert(order, e)
			end
			if side == "a" then
				e.a = id
			else
				e.b = id
			end
		end
	end
	add(ma, "a")
	add(mb, "b")
	local out: { string } = {}
	for _, e in order do
		local ida, idb = e.a, e.b
		if ida and idb then
			-- both carry it: one tier above the better of the two (a wondrous or fabled one is a family of one tier, so
			-- it stays itself; a shared flaw becomes its family's first tier)
			local ta, tb = Traits.byId[ida].tier, Traits.byId[idb].tier
			local tier = math.max(ta, tb)
			table.insert(out, if tier >= 5 then (if ta >= tb then ida else idb) else Traits.at(e.family, tier + 1))
		else
			local id = (ida or idb) :: string
			if Traits.byId[id].tier > 0 then
				table.insert(out, id)
			end
		end
	end
	-- the best four
	table.sort(out, function(x: string, y: string): boolean
		local tx, ty = Traits.byId[x].tier, Traits.byId[y].tier
		if tx ~= ty then
			return tx > ty
		end
		return x < y
	end)
	return Traits.clean(out)
end

local function pal(p: Profile, id: number): Types.Pal?
	for _, x in p.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end

-- What a pair of the island's driftlings (ids `a` and `b`) would make: the kind, its mutations, the price and the
-- turns (the Hatchery's preview, before the egg is laid; nil when either isn't the island's).
export type Preview = { sp: string, muts: { string }, price: number, turns: number }
function Breed.preview(p: Profile, a: number, b: number): Preview?
	local pa, pb = pal(p, a), pal(p, b)
	if pa == nil or pb == nil or a == b then
		return nil
	end
	local sp = Breed.child(pa.sp, pb.sp, p.tier)
	local price, turns = Breed.cost(sp, p)
	return { sp = sp, muts = Breed.inherit(pa.muts, pb.muts), price = price, turns = turns }
end

-- The egg at a Hatchery (its piece uid), if any.
function Breed.eggAt(p: Profile, uid: number): Egg?
	for _, e in p.eggs do
		if e.uid == uid then
			return e
		end
	end
	return nil
end

-- Lay an egg at the Hatchery `uid` from driftlings `a` and `b` (two of the island's own; what hatches is `preview`'s):
-- not_found (no such Hatchery or driftling), egg (an egg there already), bad_payload (the same one twice), money (not
-- enough shells).
function Breed.start(p: Profile, uid: number, a: number, b: number): (boolean, any)
	local q = Island.piece(p, uid)
	local def = if q then Buildings.byId[q.id] else nil
	if def == nil or def.kind ~= "breed" then
		return false, "not_found" :: ErrCode
	end
	if Breed.eggAt(p, uid) then
		return false, "egg" :: ErrCode
	end
	if a == b then
		return false, "bad_payload" :: ErrCode
	end
	local pa, pb = pal(p, a), pal(p, b)
	if pa == nil or pb == nil then
		return false, "not_found" :: ErrCode
	end
	local pv = Breed.preview(p, a, b) :: Preview
	if p.shells < pv.price then
		return false, "money" :: ErrCode
	end
	p.shells -= pv.price
	local egg: Egg = { uid = uid, a = a, b = b, sp = pv.sp, muts = pv.muts, left = pv.turns }
	table.insert(p.eggs, egg)
	return true, egg
end

-- A turn's end: every egg a turn nearer. One reaching 0 is ready and waits at its Hatchery till the player taps it
-- (`hatch`; the request of 2026-11-20: "the hatchery should have the timer above its building, and show ready! once
-- the egg is ready. clicking it while ready shows the hatching screen just like hatching an egg normally, but with the
-- resultant creature"). The eggs that turned ready this turn (each its Hatchery's uid and kind).
export type Ready = { uid: number, sp: string }
function Breed.turn(p: Profile): { Ready }
	local ready: { Ready } = {}
	for _, egg in p.eggs do
		if egg.left > 0 then
			egg.left -= 1
			if egg.left == 0 then
				table.insert(ready, { uid = egg.uid, sp = egg.sp })
			end
		end
	end
	return ready
end

-- Every warming egg ready now (the Finish Hatcheries product): how many turned ready.
function Breed.finish(p: Profile): number
	local n = 0
	for _, egg in p.eggs do
		if egg.left > 0 then
			egg.left = 0
			n += 1
		end
	end
	return n
end

-- Hatch the ready egg at the Hatchery `uid` into a hut with room (Logic/Tree.add: with none it waits with no hut; in
-- the Index either way): not_found (no egg there), egg (still warming). What hatched: its Hatchery, kind, mutations,
-- rarity, new id and hut, and `new` for a kind the player never had before (the hatch scene's "New!").
export type Hatched = { uid: number, sp: string, muts: { string }, r: number, id: number, home: number, new: boolean }
function Breed.hatch(p: Profile, uid: number): (boolean, any)
	local at = 0
	for i, e in p.eggs do
		if e.uid == uid then
			at = i
		end
	end
	local egg = p.eggs[at]
	local d = if egg then Creatures.byId[egg.sp] else nil
	if egg == nil or d == nil then
		return false, "not_found" :: ErrCode
	end
	if egg.left > 0 then
		return false, "egg" :: ErrCode
	end
	local fresh = (p.seen[egg.sp] or 0) < 2
	local muts = Traits.clean(egg.muts)
	local pal = Tree.add(p, egg.sp, muts)
	p.stats.hatched += 1
	table.remove(p.eggs, at)
	local out: Hatched = { uid = uid, sp = egg.sp, muts = table.clone(muts), r = d.rarity, id = pal.id, home = pal.home, new = fresh }
	return true, out
end

return table.freeze(Breed)
