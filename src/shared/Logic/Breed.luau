--!strict
-- The Hatchery (GAME_DESIGN 6.1: "make a breeding system that also works like in palworld that unlocks after a certain
-- island level"): two driftlings and a feast make an egg; it hatches after a few island turns into a hut with room
-- (Logic/Tree.add: with none it waits with no hut till one has room).
-- The genre's system in our own numbers. Pure.
--   What hatches: the same kind from a pair of one kind; else the kind whose power (Data/Creatures `power`) lies
--   nearest the parents' average (the commoner, then the first by name, on a tie). A legend only hatches from two
--   legends.
--   Its mutations (Data/Traits): one both parents carry always passes on (the better tier), and with `BreedTierUp`
--   comes out a tier better (a shared flaw turns into its family's first tier); one only a parent carries passes on
--   with `BreedKeep`; with `BreedNew` it gains one of its own (tier 1 or 2 of a family neither carries). The best four.
--   An egg is laid at a Hatchery with no egg (one each), for a feast of `BreedShells` shells by the child's rarity (food
--   till 2026-11-13), and takes `BreedTurns` turns (Island.turn's, while the player is here).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Island = require(script.Parent.Island)
local Tree = require(script.Parent.Tree)

type Profile = Types.Profile
type Egg = Types.Egg
type ErrCode = Types.ErrCode

local Breed = {}

-- What a pair hatches (species ids).
function Breed.child(a: string, b: string): string
	if a == b then
		return a
	end
	local da, db = Creatures.byId[a], Creatures.byId[b]
	if da == nil or db == nil then
		return if da then a else b
	end
	local avg = (da.power + db.power) / 2
	local legend = da.rarity == 5 and db.rarity == 5
	local best: Creatures.CreatureDef? = nil
	local bestD = math.huge
	for _, d in Creatures.list do
		if d.rarity < 5 or legend then
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

-- The feast an egg of a kind takes (shells) and the turns it takes to hatch.
function Breed.cost(sp: string): (number, number)
	local d = Creatures.byId[sp]
	local r = if d then d.rarity else 1
	return Tuning.BreedShells[r] or Tuning.BreedShells[1], Tuning.BreedTurns[r] or Tuning.BreedTurns[1]
end

-- A child's mutations from its parents' (rng: Util.newRng's).
function Breed.inherit(ma: { string }?, mb: { string }?, rng: any): { string }
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
			-- both carry it: the better tier, maybe one better still
			local ta, tb = Traits.byId[ida].tier, Traits.byId[idb].tier
			local id = if ta >= tb then ida else idb
			local tier = math.max(ta, tb)
			if rng:next() < Tuning.BreedTierUp and tier < 4 then
				id = Traits.at(e.family, tier + 1)
			end
			table.insert(out, id)
		else
			local id = (ida or idb) :: string
			if rng:next() < Tuning.BreedKeep then
				table.insert(out, id)
			end
		end
	end
	if rng:next() < Tuning.BreedNew then
		local free: { string } = {}
		for _, f in Traits.families do
			if byFam[f.family] == nil then
				table.insert(free, f.family)
			end
		end
		if #free > 0 then
			table.insert(out, Traits.at(free[rng:int(1, #free)], rng:int(1, 2)))
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

-- The egg at a Hatchery (its piece uid), if any.
function Breed.eggAt(p: Profile, uid: number): Egg?
	for _, e in p.eggs do
		if e.uid == uid then
			return e
		end
	end
	return nil
end

-- Lay an egg at the Hatchery `uid` from driftlings `a` and `b` (two of the island's own): not_found (no such Hatchery or
-- driftling), egg (an egg there already), bad_payload (the same one twice), money (not enough for the feast).
function Breed.start(p: Profile, uid: number, a: number, b: number, rng: any): (boolean, any)
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
	local sp = Breed.child(pa.sp, pb.sp)
	local feast, turns = Breed.cost(sp)
	if p.shells < feast then
		return false, "money" :: ErrCode
	end
	p.shells -= feast
	local egg: Egg = { uid = uid, a = a, b = b, sp = sp, muts = Breed.inherit(pa.muts, pb.muts, rng), left = turns }
	table.insert(p.eggs, egg)
	return true, egg
end

-- A turn's end: every egg a turn nearer; the ready ones hatch into a hut with room (in the Index). The hatched.
function Breed.turn(p: Profile): { Types.Pal }
	local born: { Types.Pal } = {}
	local keep: { Egg } = {}
	for _, egg in p.eggs do
		egg.left = math.max(0, egg.left - 1)
		local d = Creatures.byId[egg.sp]
		if egg.left == 0 and d then
			table.insert(born, Tree.add(p, egg.sp, Traits.clean(egg.muts)))
			p.stats.hatched += 1
		else
			table.insert(keep, egg)
		end
	end
	p.eggs = keep
	return born
end

return table.freeze(Breed)
