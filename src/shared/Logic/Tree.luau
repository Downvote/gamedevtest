--!strict
-- The Tree of Life and its pen (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). The request (2026-11-12): "players start with
-- a tree of life: it creates a creature every few seconds to be put into a pen. the pen will automatically send the
-- best creatures into huts if there is space, and the player can also select which creatures are sent to which hut.
-- players can upgrade the incubator's luck and speed." And later: "pens should be infinite, and no need to render the
-- pen, just a ui should be enough". Pure: IslandService calls these with the session's profile and Rng. Actions
-- return (true, data?) or (false, ErrCode) and change the profile only when they succeed.
--   The tree grows a driftling every `secs(p)` seconds while the player is here (Tuning.TreeSecs by its speed level,
--   faster with the huts' Leafy driftlings) into the pen, which has no room limit (past Tuning.PenKeep waiting there
--   the least useful is sold as each new one grows: `overflow`). What grows: a rarity by Data/Traits.RARITY's weights, each rarity step's weight times the tree's
--   luck (`luck(p)`), then one of that rarity's driftlings among the kinds open at the island's tier (Data/Islets
--   `tier`; a rarity none of them has falls to the next commoner one), born with mutations (Traits.roll, as a rarer
--   one every Tuning.TreeMutLuck luck levels).
--   The pen sends its best driftlings (`worth`: how much they add at work) into the huts with room, the comfiest hut
--   first, each one with a free place at a building of its knack, which it takes. A driftling the player put in the pen (`held`)
--   stays there.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Islets = require(script.Parent.Parent.Data.Islets)
local Traits = require(script.Parent.Parent.Data.Traits)
local Island = require(script.Parent.Island)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Pal = Types.Pal
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Tree = {}

Tree.ID = "tree" -- its piece (Data/Buildings)
Tree.SPOT = { x = -3, z = -4 } -- where a new island's tree goes (the nearest free spot: behind the campfire)

------------------------------------------------------------------ its numbers
-- The huts' driftlings' tree and luck effects together (Data/Traits: Leafy, Lucky and their kin, passives too),
-- each at most Tuning.HutTree / HutLuck.
function Tree.hutFx(p: Profile): (number, number)
	local tree, luck = 0, 0
	for _, x in p.pals do
		if x.home ~= 0 then
			local d = Creatures.byId[x.sp]
			local fx = Traits.sum(if d then d.passive.fx else nil, x.muts)
			tree += fx.tree or 0
			luck += fx.luck or 0
		end
	end
	return math.clamp(tree, 0, Tuning.HutTree), math.clamp(luck, 0, Tuning.HutLuck)
end

-- Seconds a driftling takes to grow now (`level`: another speed level, for the upgrade's preview).
function Tree.secs(p: Profile, level: number?): number
	local lv = math.clamp(level or p.tree.speed, 1, #Tuning.TreeSecs)
	local boost = Tree.hutFx(p)
	return Tuning.TreeSecs[lv] / (1 + boost)
end

-- The tree's luck: each rarity step's weight is multiplied by this (`level`: another luck level, for the preview).
function Tree.luck(p: Profile, level: number?): number
	local lv = math.clamp(level or p.tree.luck, 1, #Tuning.TreeLuckCost)
	local _, extra = Tree.hutFx(p)
	return 1 + Tuning.TreeLuck * (lv - 1) + extra
end

-- The driftlings the tree grows at a tier, by rarity (1 .. 5): every species of the kinds open there.
function Tree.pool(tier: number): { { string } }
	local out: { { string } } = { {}, {}, {}, {}, {} }
	for _, k in Islets.list do
		if k.tier <= tier then
			for _, sp in k.wild do
				local d = Creatures.byId[sp]
				table.insert(out[d.rarity], sp)
			end
		end
	end
	return out
end

-- How likely each rarity is now (shares that add to 1; a rarity none of the open kinds has gives its share to the
-- next commoner one). `luckLevel`: another luck level (the upgrade's preview).
function Tree.odds(p: Profile, luckLevel: number?): { number }
	local pool = Tree.pool(p.tier)
	local f = Tree.luck(p, luckLevel)
	local w: { number } = {}
	local total = 0
	for r, rd in Traits.RARITY do
		w[r] = rd.weight * f ^ (r - 1)
		total += w[r]
	end
	local out: { number } = { 0, 0, 0, 0, 0 }
	for r = 5, 1, -1 do
		local to = r
		while to > 1 and #pool[to] == 0 do
			to -= 1
		end
		out[to] += w[r] / total
	end
	return out
end

-- How many wait in the pen (it has no room limit: "pens should be infinite").
function Tree.inPen(p: Profile): number
	local n = 0
	for _, x in p.pals do
		if x.home == 0 then
			n += 1
		end
	end
	return n
end

-- How much a driftling adds at work, the pen's ranking: its rarity's speed times 1 + its work share at its knack.
function Tree.worth(x: Pal): number
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	local fx = Traits.sum(d.passive.fx, x.muts)
	return (Tuning.RarityWork[d.rarity] or 1) * (1 + Traits.workAt(fx, d.knack))
end

-- What a driftling sells for: its rarity's price, times 1 + SellTier x its mutations' tiers, times its sell share.
function Tree.price(x: Pal): number
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	local tiers = 0
	local list: { string } = x.muts or {}
	for _, id in list do
		local m = Traits.byId[id]
		if m then
			tiers += m.tier
		end
	end
	local fx = Traits.sum(d.passive.fx, x.muts)
	return math.max(1, math.floor(Tuning.SellPrice[d.rarity] * (1 + Tuning.SellTier * tiers) * math.max(0.2, 1 + (fx.sell or 0)) + 0.5))
end

------------------------------------------------------------------ the huts
-- Each hut's uid, room, comfort and how many live there, comfiest first (then the first built).
export type Hut = { uid: number, room: number, comfort: number, n: number }
function Tree.huts(p: Profile): { Hut }
	local out: { Hut } = {}
	local byUid: { [number]: Hut } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "nest" then
			local h: Hut = { uid = q.uid, room = d.slots, comfort = d.comfort + (Tuning.ComfortLvl[q.lvl or 1] or 0), n = 0 }
			table.insert(out, h)
			byUid[q.uid] = h
		end
	end
	for _, x in p.pals do
		local h = byUid[x.home]
		if h then
			h.n += 1
		end
	end
	table.sort(out, function(a: Hut, b: Hut): boolean
		if math.abs(a.comfort - b.comfort) > 1e-9 then
			return a.comfort > b.comfort
		end
		return a.uid < b.uid
	end)
	return out
end

local function palOf(p: Profile, id: number): Pal?
	for _, x in p.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end

-- A driftling just moved into a hut takes a free place at a building of its knack (Island.freeJob), if there is one.
local function toWork(p: Profile, x: Pal)
	local d = Creatures.byId[x.sp]
	if d and x.home ~= 0 and x.work == 0 then
		x.work = Island.freeJob(p, d.knack)
	end
end

-- The pen sends its best driftlings (not the held ones) into the huts with room, comfiest first: the best by `worth`
-- of those with a free place at a building of their knack (a driftling with nowhere to work stays in the pen till
-- there is somewhere). Returns the ids moved.
function Tree.settle(p: Profile): { number }
	local moved: { number } = {}
	local huts = Tree.huts(p)
	local free = 0
	for _, h in huts do
		free += math.max(0, h.room - h.n)
	end
	if free == 0 then
		return moved
	end
	local list: { Pal } = {}
	for _, x in p.pals do
		if x.home == 0 and x.held == nil then
			table.insert(list, x)
		end
	end
	table.sort(list, function(a: Pal, b: Pal): boolean
		local wa, wb = Tree.worth(a), Tree.worth(b)
		if math.abs(wa - wb) > 1e-9 then
			return wa > wb
		end
		return a.id < b.id
	end)
	-- (a knack with no free place left is passed over at once: no free place appears while the pen moves in)
	local full: { [string]: boolean } = {}
	for _, x in list do
		local spot: Hut? = nil
		for _, h in huts do
			if h.n < h.room then
				spot = h
				break
			end
		end
		if spot == nil then
			break
		end
		local d = Creatures.byId[x.sp]
		if d and not full[d.knack] then
			local job = Island.freeJob(p, d.knack)
			if job == 0 then
				full[d.knack] = true
			else
				spot.n += 1
				x.home = spot.uid
				x.work = job
				table.insert(moved, x.id)
			end
		end
	end
	return moved
end

-- Every resting driftling in a hut takes a free place at a building of its knack (after a building went up, or a
-- helper left).
function Tree.fillJobs(p: Profile)
	for _, x in p.pals do
		toWork(p, x)
	end
end

-- A driftling sold (from the pen or a hut): its price in shells; a hut's room fills again from the pen.
local function sellOne(p: Profile, i: number): number
	local x = p.pals[i]
	local price = Tree.price(x)
	table.remove(p.pals, i)
	p.shells += price
	p.stats.earned += price
	p.stats.sold += 1
	return price
end

------------------------------------------------------------------ growing
-- A new driftling (no checks): its kind and mutations from the tree's luck and the island's tier.
function Tree.roll(p: Profile, rng: Rng): (string, { string })
	local odds = Tree.odds(p)
	local r = 1
	local x = rng:next()
	for i = 5, 1, -1 do
		x -= odds[i]
		if x < 0 then
			r = i
			break
		end
	end
	local pool = Tree.pool(p.tier)
	while r > 1 and #pool[r] == 0 do
		r -= 1
	end
	local list = pool[r]
	local sp = list[rng:int(1, #list)]
	local mutR = math.min(5, r + math.floor((p.tree.luck - 1) / Tuning.TreeMutLuck))
	return sp, Traits.roll(rng, mutR)
end

-- A driftling into the pen (grown or hatched): it joins the Index and the stats. No checks.
function Tree.add(p: Profile, sp: string, muts: { string }): Pal
	local x: Pal = { id = p.nextId, sp = sp, home = 0, work = 0, muts = Traits.clean(muts) }
	p.nextId += 1
	table.insert(p.pals, x)
	p.seen[sp] = 2
	local d = Creatures.byId[sp]
	if d then
		p.stats.best = math.max(p.stats.best, d.rarity)
	end
	return x
end

-- dt seconds of the tree: it grows toward its next driftling and drops it into the pen, which never fills. Past
-- Tuning.PenKeep waiting there, the least useful one the player didn't keep there is sold as each new one grows (the
-- save and the view stay small). Returns the driftlings that grew, the ids the pen sent to the huts and the shells
-- the overflow sold for.
function Tree.step(p: Profile, dt: number, rng: Rng): ({ Pal }, { number }, number)
	local grown: { Pal } = {}
	local secs = Tree.secs(p)
	local sold = 0
	p.tree.t += dt
	while p.tree.t >= secs do
		p.tree.t -= secs
		local sp, muts = Tree.roll(p, rng)
		table.insert(grown, Tree.add(p, sp, muts))
		p.stats.grown += 1
	end
	local moved = if #grown > 0 then Tree.settle(p) else {}
	if #grown > 0 then
		sold = Tree.overflow(p)
	end
	return grown, moved, sold
end

-- The pen past Tuning.PenKeep: the least useful (worth, then price, then the newest) of those the player didn't keep
-- there sold until it is back to PenKeep. Returns the shells.
function Tree.overflow(p: Profile): number
	local n = Tree.inPen(p)
	if n <= Tuning.PenKeep then
		return 0
	end
	local list: { Pal } = {}
	for _, x in p.pals do
		if x.home == 0 and x.held == nil then
			table.insert(list, x)
		end
	end
	table.sort(list, function(a: Pal, b: Pal): boolean
		local wa, wb = Tree.worth(a), Tree.worth(b)
		if math.abs(wa - wb) > 1e-9 then
			return wa < wb
		end
		local pa, pb = Tree.price(a), Tree.price(b)
		if pa ~= pb then
			return pa < pb
		end
		return a.id > b.id
	end)
	local drop: { [Pal]: boolean } = {}
	local total = 0
	for _, x in list do
		if n <= Tuning.PenKeep then
			break
		end
		drop[x] = true
		n -= 1
	end
	local i = 1
	while i <= #p.pals do
		if drop[p.pals[i]] then
			total += sellOne(p, i)
		else
			i += 1
		end
	end
	return total
end

------------------------------------------------------------------ the player's actions
-- What the next level of an upgrade ("luck" or "speed") costs, or nil at the top.
function Tree.upgradeCost(p: Profile, what: string): { shells: number, wood: number }?
	local list = if what == "luck" then Tuning.TreeLuckCost else Tuning.TreeSpeedCost
	local lv = if what == "luck" then p.tree.luck else p.tree.speed
	return list[lv + 1]
end

-- A level more of the tree's luck or speed: bad_payload, max, money, wood.
function Tree.upgrade(p: Profile, what: string): (boolean, any)
	if what ~= "luck" and what ~= "speed" then
		return false, "bad_payload" :: ErrCode
	end
	local cost = Tree.upgradeCost(p, what)
	if cost == nil then
		return false, "max" :: ErrCode
	end
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < cost.wood then
		return false, "wood" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	if what == "luck" then
		p.tree.luck += 1
	else
		p.tree.speed += 1
	end
	return true, { what = what, level = if what == "luck" then p.tree.luck else p.tree.speed }
end

function Tree.sell(p: Profile, id: number): (boolean, any)
	for i, x in p.pals do
		if x.id == id then
			local wasHut = x.home ~= 0
			local price = sellOne(p, i)
			if wasHut then
				Tree.settle(p)
				Tree.fillJobs(p)
			end
			return true, { shells = price, sold = 1 }
		end
	end
	return false, "not_found" :: ErrCode
end

-- Every driftling in the pen of rarity `r` or commoner sold at once: not_found when there is none.
function Tree.sellPen(p: Profile, r: number): (boolean, any)
	local total, n = 0, 0
	local i = 1
	while i <= #p.pals do
		local x = p.pals[i]
		local d = Creatures.byId[x.sp]
		if x.home == 0 and d and d.rarity <= r then
			total += sellOne(p, i)
			n += 1
		else
			i += 1
		end
	end
	if n == 0 then
		return false, "not_found" :: ErrCode
	end
	return true, { shells = total, sold = n }
end

-- A driftling to a hut (`uid`) or the pen (0), the player's pick. A full hut takes it only in a swap: `swap` (a
-- driftling living there) goes to where this one was; the pen always has room. A driftling put in the pen stays there (`held`) till
-- it is moved again. not_found, bad_payload (not a hut, a swap that doesn't live there), full.
function Tree.house(p: Profile, id: number, uid: number, swap: number): (boolean, any)
	local x = palOf(p, id)
	if x == nil then
		return false, "not_found" :: ErrCode
	end
	if uid ~= 0 then
		local q = Island.piece(p, uid)
		local d = if q then Buildings.byId[q.id] else nil
		if d == nil or d.kind ~= "nest" then
			return false, "bad_payload" :: ErrCode
		end
	end
	if x.home == uid then
		return true, { moved = 0 }
	end
	local room, n = math.huge, 0
	if uid ~= 0 then
		for _, h in Tree.huts(p) do
			if h.uid == uid then
				room, n = h.room, h.n
			end
		end
	end
	local other: Pal? = nil
	if swap ~= 0 then
		other = palOf(p, swap)
		if other == nil or other.home ~= uid or other == x then
			return false, "bad_payload" :: ErrCode
		end
	elseif n >= room then
		return false, "full" :: ErrCode
	end
	local from = x.home
	if other then
		other.home = from
		other.work = 0
		other.held = if from == 0 then 1 else nil
	end
	x.home = uid
	x.work = 0
	x.held = if uid == 0 then 1 else nil
	toWork(p, x)
	if other then
		toWork(p, other)
	end
	-- (a hut left with room fills from the pen; the helpers' places freed fill too)
	Tree.settle(p)
	Tree.fillJobs(p)
	return true, { moved = if other then 2 else 1 }
end

------------------------------------------------------------------ the tree on the island
-- The tree's piece, or nil.
function Tree.piece(p: Profile): Types.Piece?
	for _, q in p.plot.placed do
		if q.id == Tree.ID then
			return q
		end
	end
	return nil
end

-- An island with no tree gets one (a new island, an older save) at the free spot nearest Tree.SPOT. On an island with
-- no spot left (an older save built full), the pieces nearest it make room, paths first, then decor, then the rest
-- that houses nobody, each cleared away with its whole price back. Returns the tree.
local MAKE_ROOM: { [string]: number } = { path = 1, decor = 2, gen = 3, food = 4, wood = 4, shop = 4 }
function Tree.plant(p: Profile): Types.Piece?
	local have = Tree.piece(p)
	if have then
		return have
	end
	local x, z, rot = Plot.spot(p.tier, p.plot.placed, Tree.ID, Tree.SPOT.x, Tree.SPOT.z, 0)
	while x == nil do
		local best, bi = math.huge, 0
		for i, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			local rank = if d then MAKE_ROOM[d.kind] else nil
			if rank then
				local score = rank * 1e6 + (q.x - Tree.SPOT.x) ^ 2 + (q.z - Tree.SPOT.z) ^ 2
				if score < best then
					best, bi = score, i
				end
			end
		end
		if bi == 0 then
			return nil
		end
		local q = p.plot.placed[bi]
		local d = Buildings.byId[q.id]
		if d then
			p.shells += d.shells
			p.wood += d.wood
		end
		for _, pal in p.pals do
			if pal.work == q.uid then
				pal.work = 0
			end
		end
		table.remove(p.plot.placed, bi)
		x, z, rot = Plot.spot(p.tier, p.plot.placed, Tree.ID, Tree.SPOT.x, Tree.SPOT.z, 0)
	end
	if x == nil or z == nil or rot == nil then
		return nil
	end
	local q: Types.Piece = { uid = p.nextId, id = Tree.ID, x = x, z = z, rot = rot, lvl = 1 }
	p.nextId += 1
	table.insert(p.plot.placed, q)
	return q
end

return table.freeze(Tree)
