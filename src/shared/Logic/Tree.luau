--!strict
-- The Tree of Life, its eggs and the huts (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). The request (2026-11-13): "bring
-- back the tree of life and remove the converyer belt system. it now spawns eggs around it that the player can choose
-- to hatch for some shells. it spawns in 5 eggs around it, which refreshes every few minutes to spawn in another 5
-- eggs, replacing any existing eggs that were not taken. expanding the island increases the quality of eggs spawned
-- and amount of eggs spawned". Pure: IslandService calls these with the session's profile and Rng. Actions return
-- (true, data?) or (false, ErrCode) and change the profile only when they succeed.
--   Every island has its tree (a piece, `plant`: never bought, cleared away or replaced). Every `secs(p)` seconds
--   while the player is here (Tuning.EggSecs, sooner with the huts' tree shares) it lays `count(tier)` eggs round its
--   roots (Tuning.EggCount: more on a bigger island), the ones left unhatched going (`step`, `lay`). An egg's rarity:
--   Data/Traits.RARITY's weights, each rarity step's weight times the island's luck (`luck(p)`: Tuning.EggLuck by its
--   tier and the huts' luck shares: a bigger island lays better eggs). A rarity none of the kinds open at the island's
--   tier has (Data/Islets `tier`) falls to the next commoner one. Expanding the island lays the extra eggs at once
--   (`fill`). The eggs are saved (`p.clutch`), so leaving and coming back doesn't lay a new lot.
--   Hatching one (`hatch`) costs shells (`cost`: Tuning.EggPrice by its rarity, times EggTier by the island's tier,
--   less the huts' cost shares) and needs a hut with room; with every hut full the player names one of theirs to swap
--   out (it is sold for its `price`). What hatches is one of the egg's rarity's driftlings among the kinds open at the
--   island's tier, with mutations (Traits.roll, as a rarer one every Tuning.EggMutTier tiers); a new island's first
--   two are good with wood and at a farm. It moves into the comfiest hut with room (or the swapped one's) and takes a
--   free place: at a building of its knack first, else wherever it works fastest (any driftling works anywhere).
--   A driftling without a hut (its hut cleared away or made smaller, a hatchling with no room) waits on the island,
--   working nowhere, and moves in the moment a hut has room (`settle`).
--   While the quest on the go asks for a rarity (`wanted`: the uncommon, rare and epic ones), the eggs under the tree
--   always hold one of it (`ensure`: every lot laid, and the lot there when such a quest comes up).
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Islets = require(script.Parent.Parent.Data.Islets)
local Traits = require(script.Parent.Parent.Data.Traits)
local Island = require(script.Parent.Island)
local Plot = require(script.Parent.Plot)
local Quest = require(script.Parent.Quest)
local Weather = require(script.Parent.Weather)
local WeatherData = require(script.Parent.Parent.Data.Weather)

type Profile = Types.Profile
type Pal = Types.Pal
type Laid = Types.Laid
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Tree = {}

Tree.ID = "tree" -- its piece (Data/Buildings)
Tree.SPOT = { x = -4, z = -6 } -- where a new island's tree goes (the nearest free spot: behind the campfire)

------------------------------------------------------------------ its numbers
-- The huts' driftlings' tree, luck and cost shares together (Data/Traits: Leafy, Lucky, Thrifty and their kin,
-- passives too), each at most Tuning.HutTree / HutLuck / HutCost (cost: a share off, 0 .. HutCost).
function Tree.hutFx(p: Profile): (number, number, number)
	local tree, luck, cost = 0, 0, 0
	for _, x in p.pals do
		if x.home ~= 0 then
			local d = Creatures.byId[x.sp]
			local fx = Traits.sum(if d then d.passive.fx else nil, x.muts)
			tree += fx.tree or 0
			luck += fx.luck or 0
			cost -= fx.cost or 0
		end
	end
	return math.clamp(tree, 0, Tuning.HutTree), math.clamp(luck, 0, Tuning.HutLuck), math.clamp(cost, 0, Tuning.HutCost)
end

-- Seconds between two lots of eggs.
function Tree.secs(p: Profile): number
	local boost = Tree.hutFx(p)
	return Tuning.EggSecs / (1 + boost)
end

-- How many eggs the tree lays on an island of `tier`.
function Tree.count(tier: number): number
	return Tuning.EggCount[math.clamp(tier, 1, #Tuning.EggCount)]
end

-- The tree's stage (its model grows grander with the island: Models/DecorModels).
function Tree.stage(tier: number): number
	return Tuning.TreeStage[math.clamp(tier, 1, #Tuning.TreeStage)]
end

-- The island's luck: each rarity step's weight is multiplied by this (`tier`: another tier, for a preview).
function Tree.luck(p: Profile, tier: number?): number
	local t = math.clamp(tier or p.tier, 1, #Tuning.EggLuck)
	local _, extra = Tree.hutFx(p)
	return 1 + Tuning.EggLuck[t] + extra
end

-- The driftlings that hatch at a tier, by rarity (1 .. 5): every species of the kinds open there.
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

-- How likely each rarity of egg is now (shares that add to 1; a rarity none of the open kinds has gives its share to the
-- next commoner one). `extra`: luck the weather adds (Logic/Weather.luck: a storm's eggs come rarer).
function Tree.odds(p: Profile, tier: number?, extra: number?): { number }
	local t = tier or p.tier
	local pool = Tree.pool(t)
	local f = Tree.luck(p, t) + (extra or 0)
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

-- How much a driftling adds at work, the order its list is shown in and the weakest goes first in a swap: its
-- rarity's speed times 1 + its work share at its knack. (Kept per driftling table: its kind and mutations never change
-- once it is born; a changed one is worked out again.)
type Kept = { sp: string, muts: { string }?, w: number }
local kept: { [Pal]: Kept } = setmetatable({}, { __mode = "k" }) :: any
function Tree.worth(x: Pal): number
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

-- How fast a driftling works at a building of `knack` (any driftling works anywhere; its passive and mutations may
-- help more at one knack than another): its rarity's speed times 1 + its work share there. The work picker shows it.
function Tree.worthAt(x: Pal, knack: string): number
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	return (Tuning.RarityWork[d.rarity] or 1) * (1 + Traits.workAt(Traits.sum(d.passive.fx, x.muts), knack))
end

-- a before b: the better worker first, then the older
function Tree.better(a: Pal, b: Pal): boolean
	local wa, wb = Tree.worth(a), Tree.worth(b)
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
function Tree.price(x: Pal): number
	local d = Creatures.byId[x.sp]
	if d == nil then
		return 0
	end
	local fx = Traits.sum(d.passive.fx, x.muts)
	return math.max(1, math.floor(Tuning.SellPrice[d.rarity] * (1 + Tuning.SellTier * tiersOf(x.muts)) * math.max(0.2, 1 + (fx.sell or 0)) + 0.5))
end

-- What an egg of rarity `r` costs to hatch: its rarity's price, times the island's EggTier, less the huts' cost shares.
function Tree.cost(p: Profile, r: number): number
	local tier = Tuning.EggTier[math.clamp(p.tier, 1, #Tuning.EggTier)]
	local _, _, off = Tree.hutFx(p)
	return math.max(1, math.floor(Tuning.EggPrice[math.clamp(r, 1, 5)] * tier * (1 - off) + 0.5))
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

-- The huts' free places in all.
function Tree.room(p: Profile): number
	local n = 0
	for _, h in Tree.huts(p) do
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

-- A driftling just moved into a hut takes a free place (Island.freeJob: at a building of its knack first, else
-- wherever it works fastest), if there is one.
local function toWork(p: Profile, x: Pal)
	local d = Creatures.byId[x.sp]
	if d and x.home ~= 0 and x.work == 0 then
		x.work = Island.freeJob(p, d.knack, Traits.sum(d.passive.fx, x.muts))
	end
end

-- The driftlings with no hut move into the huts with room, the best first into the comfiest, each taking a free
-- place (its knack's first). Returns the ids moved.
function Tree.settle(p: Profile): { number }
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
	table.sort(waiting, Tree.better)
	local huts = Tree.huts(p)
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

-- Every resting driftling in a hut takes a free place, its knack's first (after a building went up, or a helper
-- left).
function Tree.fillJobs(p: Profile)
	for _, x in p.pals do
		toWork(p, x)
	end
end

-- A driftling sold (or swapped out): its price in shells.
local function sellOne(p: Profile, i: number): number
	local x = p.pals[i]
	local price = Tree.price(x)
	table.remove(p.pals, i)
	p.shells += price
	p.stats.earned += price
	p.stats.sold += 1
	return price
end

-- A new driftling (one taken in, or a hatchling): into the comfiest hut with room (none: it waits with no hut), at
-- a free place, its knack's first; in the Index, and the rarest had.
function Tree.add(p: Profile, sp: string, muts: { string }): Pal
	local x: Pal = { id = p.nextId, sp = sp, home = 0, work = 0, muts = Traits.clean(muts) }
	p.nextId += 1
	for _, h in Tree.huts(p) do
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

------------------------------------------------------------------ the eggs
-- A kind and its mutations out of an egg of rarity `rarity` (of `knack` when one is asked for and the rarity has one),
-- mutations as a rarer one every EggMutTier tiers. `season`: the season the egg was laid in (Data/Weather): its own
-- islets' kinds come Tuning.SeasonFavour times as often (when the rarity has any).
function Tree.roll(p: Profile, rng: Rng, rarity: number, knack: string?, season: string?): (string, { string })
	local r = math.clamp(rarity, 1, 5)
	local pool = Tree.pool(p.tier)
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
	local sdef = if season then WeatherData.seasonById[season] else nil
	if sdef and knack == nil then
		-- (the season's own kinds weigh more: a weighted pick in place of the plain one)
		local fav: { [number]: boolean } = {}
		for _, i in sdef.favour do
			fav[i] = true
		end
		local total = 0
		for _, x in list do
			total += if fav[Creatures.byId[x].islet] then Tuning.SeasonFavour else 1
		end
		local roll = rng:next() * total
		for _, x in list do
			roll -= if fav[Creatures.byId[x].islet] then Tuning.SeasonFavour else 1
			if roll < 0 then
				sp = x
				break
			end
		end
	end
	local mutR = math.min(5, r + math.floor((p.tier - 1) / Tuning.EggMutTier))
	return sp, Traits.roll(rng, mutR)
end

-- The rarity an egg of rarity `r` hatches as: one up with Tuning.EggUp[r], and on while the rolls hold, never past a
-- rarity the island's tree has no driftlings of (the hatch scene shows each step).
function Tree.rise(p: Profile, rng: Rng, r: number): number
	local pool = Tree.pool(p.tier)
	local out = math.clamp(r, 1, 5)
	while out < 5 and #pool[out + 1] > 0 and rng:next() < (Tuning.EggUp[out] or 0) do
		out += 1
	end
	return out
end

-- An egg's rarity by the odds now (and the weather's luck: Logic/Weather.luck).
local function rarityRoll(p: Profile, rng: Rng, wx: Weather.State?): number
	local odds = Tree.odds(p, nil, Weather.luck(wx))
	local x = rng:next()
	for i = 5, 1, -1 do
		x -= odds[i]
		if x < 0 then
			return i
		end
	end
	return 1
end

-- A new island (nothing hatched yet, nobody in a hut): its first lot has two common eggs, so the tips' first
-- driftling is cheap.
local function fresh(p: Profile): boolean
	return p.stats.taken == 0 and #p.pals == 0
end

-- The rarity the quest on the go asks for (Data/Quests: a "best" goal, the rarest driftling had: "An uncommon one",
-- "A rare one", "An epic one") while it isn't met yet and the island's tree has driftlings of that rarity; 0 when
-- there is none. The request (2026-11-14): "also, while the rare one quest is active or any rarity related quests,
-- make it such that an egg of that rarity will always spawn in the tree of life."
function Tree.wanted(p: Profile): number
	local q = Quest.current(p.tut, p.quest)
	if q == nil or q.goal.kind ~= "best" then
		return 0
	end
	local r = math.clamp(q.goal.n, 1, 5)
	if r <= 1 or p.stats.best >= r or #Tree.pool(p.tier)[r] == 0 then
		return 0
	end
	return r
end

-- While a quest wants a rarity (`wanted`), the eggs under the tree hold one of it: with none there, the commonest egg
-- (the first laid of those) turns into one, keeping its id and its place on the ring, at that rarity's price. An
-- egg already rarer than the quest asks is left alone (with every egg rarer, nothing changes), and so is a new
-- island's first lot. Returns the egg that turned (nil: nothing changed).
function Tree.ensure(p: Profile): Laid?
	local r = Tree.wanted(p)
	if r == 0 or fresh(p) then
		return nil
	end
	local pick: Laid? = nil
	for _, e in p.clutch.list do
		if e.r == r then
			return nil
		end
		if e.r < r and (pick == nil or e.r < (pick :: Laid).r) then
			pick = e
		end
	end
	if pick then
		pick.r = r
	end
	return pick
end

-- Eggs up to the island's count (after it grew, or a lot just laid), the quest's egg among them (`ensure`). `wx`: the
-- season and weather now (Logic/Weather.at; GAME_DESIGN 13): each new egg keeps the season it was laid in, the
-- weather may touch it (Weather.touch: it hatches with the weather's mutation) and a storm lays rarer eggs. A new
-- island's first lot keeps its two plain commons for the tips.
function Tree.fill(p: Profile, rng: Rng, wx: Weather.State?): { Laid }
	local c = p.clutch
	local laid: { Laid } = {}
	local commons = 0
	for _, e in c.list do
		if e.r == 1 then
			commons += 1
		end
	end
	while #c.list < Tree.count(p.tier) do
		local tips = fresh(p) and commons < 2
		local r = if tips then 1 else rarityRoll(p, rng, wx)
		if r == 1 then
			commons += 1
		end
		local e: Laid = { id = c.next, r = r }
		if wx and not tips then
			e.ss = wx.season
			local kind, tier = Weather.touch(rng, wx, r)
			if kind then
				e.wx, e.wt = kind, tier
			end
		end
		c.next += 1
		table.insert(c.list, e)
		table.insert(laid, e)
	end
	Tree.ensure(p)
	return laid
end

-- A new lot: the eggs left go, `count(tier)` new ones, the next lot `secs` away.
function Tree.lay(p: Profile, rng: Rng, wx: Weather.State?): { Laid }
	table.clear(p.clutch.list)
	p.clutch.left = Tree.secs(p)
	return Tree.fill(p, rng, wx)
end

-- dt seconds of the tree: when its time comes it lays a new lot (in the weather `wx`). Returns the new lot (nil: none
-- laid).
function Tree.step(p: Profile, dt: number, rng: Rng, wx: Weather.State?): { Laid }?
	local c = p.clutch
	c.left -= dt
	if c.left <= 0 then
		return Tree.lay(p, rng, wx)
	end
	return nil
end

-- The eggs as the client sees them: each with its price on this island now, the season it was laid in and the
-- weather that touched it.
function Tree.view(p: Profile): { Laid }
	local out: { Laid } = {}
	for _, e in p.clutch.list do
		table.insert(out, { id = e.id, r = e.r, cost = Tree.cost(p, e.r), ss = e.ss, wx = e.wx, wt = e.wt })
	end
	return out
end

-- The weather mutation an egg hatches with (nil: the weather didn't touch it).
function Tree.weatherMut(e: Laid): string?
	return Weather.mutation(e.wx, e.wt)
end

-- A driftling's mutations with the weather's one added: in place of the same family's, else on the end, else (the
-- list full) in place of the lowest tier (a flaw first).
local function withWeather(muts: { string }, id: string): { string }
	local m = Traits.byId[id]
	if m == nil then
		return muts
	end
	local out = table.clone(muts)
	for i, x in out do
		local mx = Traits.byId[x]
		if mx and mx.family == m.family then
			out[i] = id
			return out
		end
	end
	if #out < Traits.MAX then
		table.insert(out, id)
		return out
	end
	local low, at = math.huge, 1
	for i, x in out do
		local t = (Traits.byId[x] :: any).tier
		if t < low then
			low, at = t, i
		end
	end
	out[at] = id
	return out
end

------------------------------------------------------------------ the player's actions
-- Hatch egg `id` for its cost: it may turn rarer first (Tree.rise; `hr` in the result), then what hatches moves into
-- the comfiest hut with room, or, every hut full, into the place of `swap` (one of the player's in a hut: sold for its
-- price). The result's `new` is true when the player never had that kind before (the hatch scene's "New!").
-- not_found (no such egg: a new lot came), no_hut (no hut built), money, full (every hut full and no swap named),
-- bad_payload (a swap that isn't in a hut).
local FIRST_KNACKS = { "wood", "farm" }
function Tree.hatch(p: Profile, id: number, swap: number, rng: Rng): (boolean, any)
	local at = 0
	for i, e in p.clutch.list do
		if e.id == id then
			at = i
		end
	end
	if at == 0 then
		return false, "not_found" :: ErrCode
	end
	local egg = p.clutch.list[at]
	local huts = Tree.huts(p)
	if #huts == 0 then
		return false, "no_hut" :: ErrCode
	end
	local cost = Tree.cost(p, egg.r)
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
	table.remove(p.clutch.list, at)
	-- (a new island's first two: good with wood, then at a farm, the tips' first buildings)
	local knack = if p.stats.taken < #FIRST_KNACKS and #p.pals < #FIRST_KNACKS then FIRST_KNACKS[p.stats.taken + 1] else nil
	-- (it may turn rarer as it hatches; never the tips' first two)
	local hr = if knack then egg.r else Tree.rise(p, rng, egg.r)
	local sp, muts = Tree.roll(p, rng, hr, knack, egg.ss)
	-- (an egg the weather touched hatches with its mutation: GAME_DESIGN 13)
	local wm = Tree.weatherMut(egg)
	if wm then
		muts = withWeather(Traits.clean(muts), wm)
	end
	local x: Pal = { id = p.nextId, sp = sp, home = home, work = 0, muts = Traits.clean(muts) }
	p.nextId += 1
	table.insert(p.pals, x)
	toWork(p, x)
	-- (`new`: a kind never had before this one, seen in the Index or not: the hatch says "New!")
	local fresh = (p.seen[x.sp] or 0) < 2
	p.seen[x.sp] = 2
	p.stats.taken += 1
	local def = Creatures.byId[x.sp]
	if def then
		p.stats.best = math.max(p.stats.best, def.rarity)
	end
	return true, { id = x.id, sp = x.sp, muts = x.muts, egg = id, r = egg.r, hr = hr, cost = cost, sold = sold, swapped = if out then swap else 0, wx = egg.wx, wm = wm, new = fresh }
end

-- A driftling sold (from a hut or with none): its price in shells; a hut's room goes to one waiting with no hut.
function Tree.sell(p: Profile, id: number): (boolean, any)
	for i, x in p.pals do
		if x.id == id then
			local price = sellOne(p, i)
			Tree.settle(p)
			Tree.fillJobs(p)
			return true, { shells = price, sold = 1 }
		end
	end
	return false, "not_found" :: ErrCode
end

-- A driftling to another hut (`uid`), the player's pick. A full hut takes it only in a swap: `swap` (a driftling living
-- there) goes to where this one was. not_found, bad_payload (not a hut, a swap that doesn't live there), full.
function Tree.house(p: Profile, id: number, uid: number, swap: number): (boolean, any)
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
	for _, h in Tree.huts(p) do
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
local MAKE_ROOM: { [string]: number } = { path = 1, decor = 2, gen = 3, farm = 4, wood = 4, shop = 4 }
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
