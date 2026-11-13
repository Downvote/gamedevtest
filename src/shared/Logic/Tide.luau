--!strict
-- The tide and the huts (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). The request (2026-11-13), after the Tree of Life's
-- stream gave too many driftlings for too little: "use the drifting in idea. you can remove the tree of life, there
-- should now be a steady stream of driftlings, with rarities that players can pick up". Pure: IslandService keeps each
-- session's tide (`State`, never saved) and calls these with its profile and Rng. Actions return (true, data?) or
-- (false, ErrCode) and change the profile only when they succeed.
--   The request after (2026-11-13): "make them float by just like a conveyer belt instead of drifting towards the
--   island and stopping, with one every second". Every `secs(p)` seconds (Tuning.TideSecs, faster with the huts' tide
--   shares) a driftling comes in on the tide and floats past the island in `life(p)` seconds (Tuning.TideLife, as
--   much faster), then it's gone: a rarity by Data/Traits.RARITY's weights, each rarity step's weight times the
--   island's luck (`luck(p)`: Tuning.TideLuck by its tier and the huts' luck shares), then one of that rarity's
--   driftlings among the kinds open at the island's tier (Data/Islets `tier`; a rarity none of them has falls to the
--   next commoner one), with mutations (Traits.roll, as a rarer one every Tuning.TideMutTier tiers). Each keeps the
--   tide's clock when it came (`at`) and its `life`, so every client puts it at the same place along the way
--   (Controllers/TideView). Seeing one puts it in the Index (`seen` 1).
--   Taking one in (`take`) costs shells (`cost`) and needs a hut with room; with every hut full the player names one of
--   theirs to swap out (it is sold for its `price`). It moves into the comfiest hut with room (or the swapped one's)
--   and takes a free place at a building of its knack.
--   A driftling without a hut (its hut cleared away or made smaller, a hatchling with no room) waits on the island,
--   working nowhere, and moves in the moment a hut has room (`settle`).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Islets = require(script.Parent.Parent.Data.Islets)
local Traits = require(script.Parent.Parent.Data.Traits)
local Island = require(script.Parent.Island)

type Profile = Types.Profile
type Pal = Types.Pal
type Drift = Types.Drift
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Tide = {}

------------------------------------------------------------------ its numbers
-- The huts' driftlings' tide and luck shares together (Data/Traits: Breezy, Lucky and their kin, passives too), each
-- at most Tuning.HutTide / HutLuck.
function Tide.hutFx(p: Profile): (number, number)
	local tide, luck = 0, 0
	for _, x in p.pals do
		if x.home ~= 0 then
			local d = Creatures.byId[x.sp]
			local fx = Traits.sum(if d then d.passive.fx else nil, x.muts)
			tide += fx.tide or 0
			luck += fx.luck or 0
		end
	end
	return math.clamp(tide, 0, Tuning.HutTide), math.clamp(luck, 0, Tuning.HutLuck)
end

-- Seconds between two driftlings coming in.
function Tide.secs(p: Profile): number
	local boost = Tide.hutFx(p)
	return Tuning.TideSecs / (1 + boost)
end

-- The island's luck: each rarity step's weight is multiplied by this (`tier`: another tier, for a preview).
function Tide.luck(p: Profile, tier: number?): number
	local t = math.clamp(tier or p.tier, 1, #Tuning.TideLuck)
	local _, extra = Tide.hutFx(p)
	return 1 + Tuning.TideLuck[t] + extra
end

-- The driftlings that drift in at a tier, by rarity (1 .. 5): every species of the kinds open there.
function Tide.pool(tier: number): { { string } }
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
-- next commoner one).
function Tide.odds(p: Profile, tier: number?): { number }
	local t = tier or p.tier
	local pool = Tide.pool(t)
	local f = Tide.luck(p, t)
	local w: { number } = {}
	local total = 0
	for r, rd in Traits.RARITY do
		w[r] = rd.weight * (Tuning.TideRare[r] or 1) * f ^ (r - 1)
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

-- How much a driftling adds at work, the order its list is shown in and the weakest goes first in a swap: its
-- rarity's speed times 1 + its work share at its knack. (Kept per driftling table: its kind and mutations never change
-- once it is born; a changed one is worked out again.)
type Kept = { sp: string, muts: { string }?, w: number }
local kept: { [Pal]: Kept } = setmetatable({}, { __mode = "k" }) :: any
function Tide.worth(x: Pal): number
	local k = kept[x]
	if k and k.sp == x.sp and k.muts == x.muts then
		return k.w
	end
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	local fx = Traits.sum(d.passive.fx, x.muts)
	local w = (Tuning.RarityWork[d.rarity] or 1) * (1 + Traits.workAt(fx, d.knack))
	kept[x] = { sp = x.sp, muts = x.muts, w = w }
	return w
end

-- a before b: the better worker first, then the older
function Tide.better(a: Pal, b: Pal): boolean
	local wa, wb = Tide.worth(a), Tide.worth(b)
	if math.abs(wa - wb) > 1e-9 then
		return wa > wb
	end
	return a.id < b.id
end

local function tiersOf(muts: { string }?): number
	local tiers = 0
	local list: { string } = muts or {}
	for _, id in list do
		local m = Traits.byId[id]
		if m then
			tiers += m.tier
		end
	end
	return tiers
end

-- What a driftling sells for (or brings back when swapped out): its rarity's price, times 1 + SellTier x its
-- mutations' tiers, times its sell share.
function Tide.price(x: Pal): number
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	local fx = Traits.sum(d.passive.fx, x.muts)
	return math.max(1, math.floor(Tuning.SellPrice[d.rarity] * (1 + Tuning.SellTier * tiersOf(x.muts)) * math.max(0.2, 1 + (fx.sell or 0)) + 0.5))
end

-- What one off the tide costs to take in: its rarity's price, times 1 + SellTier x its mutations' tiers, times its
-- cost share, times the island's TideTier.
function Tide.cost(p: Profile, sp: string, muts: { string }?): number
	local d = Creatures.byId[sp]
	if d == nil then
		return 0
	end
	local fx = Traits.sum(d.passive.fx, muts)
	local tier = Tuning.TideTier[math.clamp(p.tier, 1, #Tuning.TideTier)]
	return math.max(1, math.floor(Tuning.TidePrice[d.rarity] * (1 + Tuning.SellTier * tiersOf(muts)) * math.max(0.2, 1 + (fx.cost or 0)) * tier + 0.5))
end

------------------------------------------------------------------ the huts
-- Each hut's uid, room, comfort and how many live there, comfiest first (then the first built).
export type Hut = { uid: number, room: number, comfort: number, n: number }
function Tide.huts(p: Profile): { Hut }
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

-- The huts' free places in all.
function Tide.room(p: Profile): number
	local n = 0
	for _, h in Tide.huts(p) do
		n += math.max(0, h.room - h.n)
	end
	return n
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

-- The driftlings with no hut move into the huts with room, the best first into the comfiest, each taking a free
-- place at a building of its knack. Returns the ids moved.
function Tide.settle(p: Profile): { number }
	local moved: { number } = {}
	local waiting: { Pal } = {}
	for _, x in p.pals do
		if x.home == 0 then
			table.insert(waiting, x)
		end
	end
	if #waiting == 0 then
		return moved
	end
	table.sort(waiting, Tide.better)
	local huts = Tide.huts(p)
	for _, x in waiting do
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
		spot.n += 1
		x.home, x.work = spot.uid, 0
		toWork(p, x)
		table.insert(moved, x.id)
	end
	return moved
end

-- Every resting driftling in a hut takes a free place at a building of its knack (after a building went up, or a
-- helper left).
function Tide.fillJobs(p: Profile)
	for _, x in p.pals do
		toWork(p, x)
	end
end

-- A driftling sold (or swapped out): its price in shells.
local function sellOne(p: Profile, i: number): number
	local x = p.pals[i]
	local price = Tide.price(x)
	table.remove(p.pals, i)
	p.shells += price
	p.stats.earned += price
	p.stats.sold += 1
	return price
end

-- A new driftling (one taken in, or a hatchling): into the comfiest hut with room (none: it waits with no hut), at
-- a free place of its knack; in the Index, and the rarest had.
function Tide.add(p: Profile, sp: string, muts: { string }): Pal
	local x: Pal = { id = p.nextId, sp = sp, home = 0, work = 0, muts = Traits.clean(muts) }
	p.nextId += 1
	for _, h in Tide.huts(p) do
		if h.n < h.room then
			x.home = h.uid
			break
		end
	end
	table.insert(p.pals, x)
	toWork(p, x)
	p.seen[sp] = 2
	local d = Creatures.byId[sp]
	if d then
		p.stats.best = math.max(p.stats.best, d.rarity)
	end
	return x
end

------------------------------------------------------------------ the tide
-- Seconds one takes to float past the island (the faster the tide comes in, the faster it runs).
function Tide.life(p: Profile): number
	return Tuning.TideLife * Tide.secs(p) / Tuning.TideSecs
end

-- A session's tide (never saved): its clock (IslandService runs it on the server's time), seconds since the last one
-- came in, the ones floating past (the oldest, the furthest along, first) and the next one's id.
export type State = { clock: number, t: number, list: { Drift }, next: number }

function Tide.new(clock: number?): State
	return { clock = clock or 0, t = 0, list = {}, next = 1 }
end

-- A kind and its mutations off the tide: a rarity by the odds (or `rarity`), one of its kinds (of `knack` when one is
-- asked for and the rarity has one), mutations as a rarer one every TideMutTier tiers.
function Tide.roll(p: Profile, rng: Rng, rarity: number?, knack: string?): (string, { string })
	local r = rarity or 1
	if rarity == nil then
		local odds = Tide.odds(p)
		local x = rng:next()
		for i = 5, 1, -1 do
			x -= odds[i]
			if x < 0 then
				r = i
				break
			end
		end
	end
	local pool = Tide.pool(p.tier)
	while r > 1 and #pool[r] == 0 do
		r -= 1
	end
	local list = pool[r]
	if knack then
		local of: { string } = {}
		for _, sp in list do
			if Creatures.byId[sp].knack == knack then
				table.insert(of, sp)
			end
		end
		if #of > 0 then
			list = of
		end
	end
	local sp = list[rng:int(1, #list)]
	local mutR = math.min(5, r + math.floor((p.tier - 1) / Tuning.TideMutTier))
	return sp, Traits.roll(rng, mutR)
end

-- A new island (nothing taken in yet, nobody in a hut): every third one is a common that can work at its first
-- buildings (good with wood, or at a farm, by turns), so the tips' first driftling is cheap and has somewhere to go.
local FIRST_KNACKS = { "wood", "farm" }
local function firstOf(p: Profile, s: State): (number?, string?)
	if p.stats.taken == 0 and #p.pals == 0 and s.next % 3 == 1 then
		return 1, FIRST_KNACKS[(s.next // 3) % #FIRST_KNACKS + 1]
	end
	return nil, nil
end

-- One comes in at the tide's clock `at` (seen in the Index). Returns it.
function Tide.drift(p: Profile, s: State, rng: Rng, at: number, rarity: number?, knack: string?): Drift
	local r, k = rarity, knack
	if r == nil and k == nil then
		r, k = firstOf(p, s)
	end
	local sp, muts = Tide.roll(p, rng, r, k)
	local d: Drift = { id = s.next, sp = sp, muts = muts, cost = Tide.cost(p, sp, muts), at = at, life = Tide.life(p) }
	s.next += 1
	table.insert(s.list, d)
	p.seen[sp] = math.max(p.seen[sp] or 0, 1)
	return d
end

-- A session's first: the tide already running, one every `secs` all the way along.
function Tide.start(p: Profile, s: State, rng: Rng)
	local secs, life = Tide.secs(p), Tide.life(p)
	local n = math.max(1, math.floor(life / secs))
	for k = n - 1, 0, -1 do
		Tide.drift(p, s, rng, s.clock - k * secs)
	end
	s.t = 0
end

-- dt seconds of the tide: every `secs` one comes in; each one gone past the island leaves. Returns the ones that came
-- and the ids that left.
function Tide.step(p: Profile, s: State, dt: number, rng: Rng): ({ Drift }, { number })
	local came: { Drift } = {}
	local gone: { number } = {}
	local secs = Tide.secs(p)
	s.clock += dt
	s.t += dt
	while s.t >= secs do
		s.t -= secs
		table.insert(came, Tide.drift(p, s, rng, s.clock - s.t))
	end
	local i = 1
	while i <= #s.list do
		local d = s.list[i]
		if s.clock - d.at >= d.life then
			table.remove(s.list, i)
			table.insert(gone, d.id)
		else
			i += 1
		end
	end
	return came, gone
end

-- How far along one is (0 just come in .. 1 gone past), at the tide's clock `now`.
function Tide.along(d: Drift, now: number): number
	return math.clamp((now - d.at) / math.max(0.1, d.life), 0, 1)
end

-- One as the client sees it: its cost on this island (it changes as the island grows).
function Tide.entry(p: Profile, d: Drift): Drift
	return { id = d.id, sp = d.sp, muts = d.muts, cost = Tide.cost(p, d.sp, d.muts), at = d.at, life = d.life }
end

-- The ones floating past now.
function Tide.view(p: Profile, s: State): { Drift }
	local out: { Drift } = {}
	for _, d in s.list do
		table.insert(out, Tide.entry(p, d))
	end
	return out
end

------------------------------------------------------------------ the player's actions
-- One off the tide taken in for its cost: into the comfiest hut with room, or, every hut full, into the place of
-- `swap` (one of the player's in a hut: sold for its price). not_found (it floated off), no_hut (no hut built),
-- money, full (every hut full and no swap named), bad_payload (a swap that isn't in a hut).
function Tide.take(p: Profile, s: State, id: number, swap: number): (boolean, any)
	local at = 0
	for i, d in s.list do
		if d.id == id then
			at = i
		end
	end
	if at == 0 then
		return false, "not_found" :: ErrCode
	end
	local d = s.list[at]
	local huts = Tide.huts(p)
	if #huts == 0 then
		return false, "no_hut" :: ErrCode
	end
	local cost = Tide.cost(p, d.sp, d.muts)
	if p.shells < cost then
		return false, "money" :: ErrCode
	end
	local spot: Hut? = nil
	for _, h in huts do
		if h.n < h.room then
			spot = h
			break
		end
	end
	local out: Pal? = nil
	if spot == nil then
		if swap == 0 then
			return false, "full" :: ErrCode
		end
		out = palOf(p, swap)
		if out == nil or out.home == 0 then
			return false, "bad_payload" :: ErrCode
		end
	end
	p.shells -= cost
	local sold, home = 0, if spot then spot.uid else 0
	if out then
		home = out.home
		sold = sellOne(p, table.find(p.pals, out) :: number)
	end
	table.remove(s.list, at)
	local x: Pal = { id = p.nextId, sp = d.sp, home = home, work = 0, muts = Traits.clean(d.muts) }
	p.nextId += 1
	table.insert(p.pals, x)
	toWork(p, x)
	p.seen[x.sp] = 2
	p.stats.taken += 1
	local def = Creatures.byId[x.sp]
	if def then
		p.stats.best = math.max(p.stats.best, def.rarity)
	end
	return true, { id = x.id, sp = x.sp, cost = cost, sold = sold, swapped = if out then swap else 0 }
end

-- A driftling sold (from a hut or with none): its price in shells; a hut's room goes to one waiting with no hut.
function Tide.sell(p: Profile, id: number): (boolean, any)
	for i, x in p.pals do
		if x.id == id then
			local price = sellOne(p, i)
			Tide.settle(p)
			Tide.fillJobs(p)
			return true, { shells = price, sold = 1 }
		end
	end
	return false, "not_found" :: ErrCode
end

-- A driftling to another hut (`uid`), the player's pick. A full hut takes it only in a swap: `swap` (a driftling living
-- there) goes to where this one was. not_found, bad_payload (not a hut, a swap that doesn't live there), full.
function Tide.house(p: Profile, id: number, uid: number, swap: number): (boolean, any)
	local x = palOf(p, id)
	if x == nil then
		return false, "not_found" :: ErrCode
	end
	local q = Island.piece(p, uid)
	local hd = if q then Buildings.byId[q.id] else nil
	if hd == nil or hd.kind ~= "nest" then
		return false, "bad_payload" :: ErrCode
	end
	if x.home == uid then
		return true, { moved = 0 }
	end
	local room, n = 0, 0
	for _, h in Tide.huts(p) do
		if h.uid == uid then
			room, n = h.room, h.n
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
	end
	x.home = uid
	x.work = 0
	toWork(p, x)
	if other then
		toWork(p, other)
	end
	-- (a hut left with room takes in one waiting with no hut; the helpers' places freed fill too)
	Tide.settle(p)
	Tide.fillJobs(p)
	return true, { moved = if other then 2 else 1 }
end

return table.freeze(Tide)
