--!strict
-- The island's rules (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 6): what it makes a turn, its charm and what charm adds,
-- which driftling works where, expanding the island. The driftlings do all the work (the request of 2026-11-12:
-- "remove villagers, only creatures should be enough"). Pure: IslandService calls these with the session's profile;
-- the Economy spec plays whole sessions through the same functions. Actions return (true, data?) or (false, ErrCode)
-- and change the profile only when they succeed.
--
-- A turn (Tuning.TurnSeconds): each workplace (kind "work": farms, wood buildings and shops alike since the request of
--   2026-11-19, "remove work building types. They all now fall in the same category of work") makes its rate
--   (Data/Buildings) times (the work of its driftlings, up to its `jobs`: each PalWork x its rarity's RarityWork x (1 +
--   its work share + its hut's comfort + the island's aura), its work share its passive's and mutations' (Data/Traits;
--   a driftling may work anywhere); IdleOutput with none) x (1 + the boost: every boost building's share, BoostMax at
--   most, times 1 + the huts' boost share)
-- in shells, all of it (the request of 2026-11-14: "make shells the main currency ... remove the visitors mechanic,
-- charm simply increases your shell gain"); then the whole is times 1 + the charm bonus (`charmBonus`), the passes,
-- the huts' "all" share and a timed boost while one runs. Nothing eats (food went on 2026-11-13: "remove food as a
-- resource"); a driftling with no hut doesn't work. What the huts' driftlings give the whole island (luck, cheaper eggs,
-- quicker Hatcheries, stronger boosts, more charm and the wondrous mutations' effects): `isle`.
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Buildings = require(script.Parent.Parent.Data.Buildings)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Looks = require(script.Parent.Parent.Data.Looks)
local Plot = require(script.Parent.Plot)

type Profile = Types.Profile
type Piece = Types.Piece
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Island = {}

export type Rates = { shells: number }

function Island.piece(p: Profile, uid: number): Piece?
	for _, q in p.plot.placed do
		if q.uid == uid then
			return q
		end
	end
	return nil
end

local function count(p: Profile, field: string): number
	local n = 0
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d then
			n += (d :: any)[field]
		end
	end
	return n
end

function Island.nests(p: Profile): number
	return count(p, "slots")
end

-- A driftling's effects: its passive and its mutations together (Data/Traits).
function Island.fxOf(pal: Types.Pal): Traits.Fx
	local d = Creatures.byId[pal.sp]
	return Traits.sum(if d then d.passive.fx else nil, pal.muts)
end

-- What the huts' driftlings give the whole island (Data/Traits.ISLE), each summed and held to Tuning.IsleCap, but
-- hatch, which multiplies: each driftling's share takes that much off the time left, so a second one counts for less
-- than the first (the request of 2026-11-19: "make mutations that decrease hatchery time, with diminishing returns if
-- stacked"), never below Tuning.HatchMin of it. `hatch` is the time's multiplier (1: no faster); `charm` the flat charm
-- they add (one each and their charm shares, Island.charm). Worked out from the island's driftlings as they are.
export type Isle = {
	luck: number,
	cost: number, -- a share off the eggs' price (0 .. its cap)
	hatch: number, -- the Hatcheries' time multiplier (Tuning.HatchMin .. 1)
	boost: number,
	charmPct: number,
	all: number,
	aura: number,
	eggs: number, -- whole eggs more a lot
	skip: number,
	away: number,
	charm: number,
}
function Island.isle(p: Profile): Isle
	local sum: { [string]: number } = {}
	local hatch, charm = 1, 0
	for _, x in p.pals do
		if x.home ~= 0 then
			local fx = Island.fxOf(x)
			for _, k in Traits.ISLE do
				local v = fx[k]
				if v then
					sum[k] = (sum[k] or 0) + v
				end
			end
			local h = fx.hatch
			if h and h > 0 then
				hatch *= 1 - math.min(h, 0.9)
			end
			charm += 1 + (fx.charm or 0)
		end
	end
	local cap = Tuning.IsleCap
	local function held(k: string, v: number): number
		return math.clamp(v, 0, cap[k] or math.huge)
	end
	return {
		luck = held("luck", sum.luck or 0),
		cost = held("cost", -(sum.cost or 0)),
		hatch = math.max(Tuning.HatchMin, hatch),
		boost = held("boost", sum.boost or 0),
		charmPct = held("charmPct", sum.charmPct or 0),
		all = held("all", sum.all or 0),
		aura = held("aura", sum.aura or 0),
		eggs = math.floor(held("eggs", sum.eggs or 0) + 1e-9),
		skip = held("skip", sum.skip or 0),
		away = held("away", sum.away or 0),
		charm = charm,
	}
end

-- The charm: every piece's and each driftling living in a hut (one each, and their charm shares), times 1 + the huts'
-- charm share (the request of 2026-11-19: "a percentage boost to charm, while keeping some as a flat boost").
function Island.charm(p: Profile, isle: Isle?): number
	local i = isle or Island.isle(p)
	return math.max(0, (count(p, "charm") + i.charm) * (1 + i.charmPct))
end

-- What charm adds to every shell the island makes (0.25 = +25%): CharmMax x charm / (charm + CharmHalf), a soft curve
-- that never passes CharmMax (the visitors it brought went on 2026-11-14).
function Island.charmBonus(charm: number): number
	local c = math.max(0, charm)
	return Tuning.CharmMax * c / (c + Tuning.CharmHalf)
end

-- Each driftling's hut and its comfort (its own and its level's), keyed "p<id>" (Pal.home: Logic/Tree), none for one
-- with no hut.
export type Home = { uid: number, comfort: number }
function Island.homes(p: Profile): { [string]: Home }
	local out: { [string]: Home } = {}
	local hut: { [number]: number } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "nest" then
			hut[q.uid] = d.comfort + (Tuning.ComfortLvl[q.lvl or 1] or 0)
		end
	end
	for _, x in p.pals do
		local c = hut[x.home]
		if c then
			out["p" .. x.id] = { uid = x.home, comfort = c }
		end
	end
	return out
end

-- The share the k-th boost building of one kind gives (k from 1): its whole share for the first, Tuning.BoostStack of
-- it for a second, BoostStack² for a third and so on (the request of 2026-11-15: "make it such that boost buildings
-- can stack, but with diminishing returns"; till then a second of a kind gave nothing).
function Island.boostShare(id: string, k: number): number
	local d = Buildings.byId[id]
	if d == nil or d.kind ~= "gen" or k < 1 then
		return 0
	end
	return d.boostBy * Tuning.BoostStack ^ (k - 1)
end

-- The boost buildings' shares together (GAME_DESIGN 4.1), every one for every workplace since the request of
-- 2026-11-19 ("All boost buildings should also just boost everything instead"): the copies of a kind less and less
-- (boostShare).
function Island.boostRaw(p: Profile): number
	local out = 0
	local n: { [string]: number } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "gen" then
			local k = (n[d.id] or 0) + 1
			n[d.id] = k
			out += Island.boostShare(d.id, k)
		end
	end
	return out
end

-- The boost every workplace gets: the boost buildings' shares, `BoostMax` at most, times 1 + the huts' boost share
-- (Data/Traits boost: "Make mutations and rework some passives to boost boost buildings").
function Island.boost(p: Profile, isle: Isle?): number
	local i = isle or Island.isle(p)
	return math.min(Tuning.BoostMax, Island.boostRaw(p)) * (1 + i.boost)
end

-- What a boost building of piece id `id` stands for on the island (its card: GAME_DESIGN 4.6): how many boost
-- buildings there are, their shares together before and after the cap and the driftlings' boost (`total`, every
-- workplace's), the driftlings' multiplier, and what one more of its kind would add before it.
function Island.boostInfo(p: Profile, id: string): { count: number, raw: number, total: number, mult: number, more: number }
	local d = Buildings.byId[id]
	if d == nil or d.kind ~= "gen" then
		return { count = 0, raw = 0, total = 0, mult = 1, more = 0 }
	end
	local i = Island.isle(p)
	local count, same = 0, 0
	for _, q in p.plot.placed do
		local e = Buildings.byId[q.id]
		if e and e.kind == "gen" then
			count += 1
			if e.id == d.id then
				same += 1
			end
		end
	end
	return { count = count, raw = Island.boostRaw(p), total = Island.boost(p, i), mult = 1 + i.boost, more = Island.boostShare(d.id, same + 1) }
end

-- Whether a building takes workers (it makes something).
function Island.works(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and d.kind == "work"
end

-- The places at work on an island: every workplace's `jobs` (`works`). The island card's Working line counts
-- the driftlings at work out of these (the request of 2026-11-17: "for working, make it x/y, where x is amount of
-- creatures working and y being the amount of work spaces available").
function Island.jobPlaces(pieces: { Types.Piece }): number
	local n = 0
	for _, q in pieces do
		local d = Buildings.byId[q.id]
		if d and Island.works(q.id) then
			n += d.jobs
		end
	end
	return n
end

-- A driftling's work share (Data/Traits.work: its passive's and mutations' work; the same at every workplace).
function Island.palWork(_p: Profile, pal: Types.Pal): number
	return Traits.work(Island.fxOf(pal))
end

-- What a driftling makes at the building it works at, in shares of the building's rate: PalWork x its rarity's
-- RarityWork x (1 + its work share + its hut's comfort + the island's aura). `comfort`: its hut's (Island.homes), 0
-- with no hut; `aura`: Island.isle's (a wondrous Maestro's), 0 when not given.
function Island.palBoost(p: Profile, pal: Types.Pal, comfort: number?, aura: number?): number
	local d = Creatures.byId[pal.sp]
	local r = if d then d.rarity else 1
	return Tuning.PalWork * (Tuning.RarityWork[r] or 1) * math.max(0, 1 + Island.palWork(p, pal) + (comfort or 0) + (aura or 0))
end

-- What each workplace makes a turn before the charm bonus and the passes (uid -> shells): its rate x its level's
-- multiplier x (its workers' shares, or IdleOutput with none) x (1 + the boost). The client's building card
-- (Controllers/BuildingTags) shows one times the view's charm bonus and income multiplier.
function Island.output(p: Profile, isle: Isle?): { [number]: number }
	local i = isle or Island.isle(p)
	local out: { [number]: number } = {}
	local homes = Island.homes(p)
	local boost = Island.boost(p, i)
	-- the working driftlings' shares (each in a hut), added up at each building
	local helper: { [number]: number } = {}
	for _, pal in p.pals do
		local h = homes["p" .. pal.id]
		if pal.work ~= 0 and h then
			helper[pal.work] = (helper[pal.work] or 0) + Island.palBoost(p, pal, h.comfort, i.aura)
		end
	end
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 and d.kind == "work" then
			local k = (helper[q.uid] or Tuning.IdleOutput) * (Tuning.UpgradeMult[q.lvl] or 1) * (1 + boost)
			out[q.uid] = d.rate * k
		end
	end
	return out
end

-- What a turn makes now: the workplaces' together, times 1 + the charm bonus, the passes, the huts' "all" share (a
-- wondrous Goldtouched's) and a timed shells boost while one runs (Logic/Rewards: Profile.boosts).
function Island.rates(p: Profile): Rates
	local i = Island.isle(p)
	local made = Island.output(p, i)
	local shells = 0
	for _, q in p.plot.placed do
		shells += made[q.uid] or 0
	end
	return { shells = shells * (1 + Island.charmBonus(Island.charm(p, i))) * Island.passMult(p) * (1 + i.all) * Island.timedMult(p) }
end

-- A timed shells boost (a reward's: Logic/Rewards) multiplies every shell by 1 + Tuning.TimedShells while it runs.
function Island.timedMult(p: Profile): number
	local b = p.boosts
	return if b and (b.shells or 0) > 0 then 1 + Tuning.TimedShells else 1
end

-- What the passes and the group multiply every shell by (GAME_DESIGN 14): Double Income x Tuning.DoubleIncome, VIP 1 +
-- Tuning.VipIncome, in the group 1 + Tuning.GroupBoost (all three: x2 x 1.25 x 1.1).
function Island.passMult(p: Profile): number
	local ps = p.passes
	local g = if p.group and p.group.member then 1 + Tuning.GroupBoost else 1
	if ps == nil then
		return g
	end
	return (if ps.DoubleIncome then Tuning.DoubleIncome else 1) * (if ps.VIP then 1 + Tuning.VipIncome else 1) * g
end

-- dt seconds of the island's turns: what it made (fractions; the stats count the shells). The timed boosts run down
-- while the player is here (Profile.boosts: seconds left).
function Island.step(p: Profile, dt: number): Rates
	local r = Island.rates(p)
	local k = dt / Tuning.TurnSeconds
	p.shells += r.shells * k
	p.stats.earned += r.shells * k
	local b = p.boosts
	if b then
		local gone: { string } = {}
		for key, left in b do
			local t = left - dt
			if t > 0 then
				b[key] = t
			else
				table.insert(gone, key)
			end
		end
		for _, key in gone do
			b[key] = nil
		end
	end
	return { shells = r.shells * k }
end

------------------------------------------------------------------ looks, work and the days
-- A random look (the loading card's art; the founder starts with one too).
function Island.randomLook(rng: Rng): Types.Look
	return { skin = rng:int(1, #Looks.skin), hair = rng:int(1, #Looks.hair), style = rng:int(1, #Looks.styles), shirt = rng:int(1, #Looks.shirt) }
end

-- A free place at work: the workplace with fewer driftlings working there than its `jobs` that makes the most (its
-- rate and level), then the emptiest, the first built; 0 with none. Any driftling may work anywhere (the request of
-- 2026-11-13); every workplace is one kind of work since 2026-11-19.
function Island.freeJob(p: Profile): number
	local taken: { [number]: number } = {}
	for _, pal in p.pals do
		if pal.work ~= 0 then
			taken[pal.work] = (taken[pal.work] or 0) + 1
		end
	end
	local best, bestOut, bestN = 0, -1, math.huge
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		local n = taken[q.uid] or 0
		if d and d.kind == "work" and n < d.jobs then
			local out = d.rate * (Tuning.UpgradeMult[q.lvl or 1] or 1)
			if out > bestOut + 1e-9 or (math.abs(out - bestOut) <= 1e-9 and n < bestN) then
				best, bestOut, bestN = q.uid, out, n
			end
		end
	end
	return best
end

-- A new calendar day on the island (the sea's clock passed a day's end while the player was here): the day count.
function Island.newDay(p: Profile)
	p.day += 1
	p.stats.days += 1
end

-- The automatic arrangement (the request of 2026-11-14: "make it such that driftlings will automatically work at
-- whatever they do best in, at the best work areas"). Every driftling living in a hut that the player hasn't placed
-- by hand (`pin`) works where it makes the most shells: the best workers choose first (their speed, then the older),
-- each taking the free place at the best workplace with room (rate x level; every workplace is one kind of work since
-- 2026-11-19, so a driftling's speed is the same everywhere: Tuning.PalWork x its rarity's RarityWork x (1 + its work
-- share + its hut's comfort)). Ties: the first built. A pinned one keeps its place while that stands (its place gone,
-- it goes back to the arrangement); one with no hut rests. Runs whenever the island changes (Logic/Tree.fillJobs and
-- settle, a hatch, a building placed, replaced or cleared, a sale, a move, growing the island, a save loaded).
function Island.arrange(p: Profile)
	local homes = Island.homes(p)
	-- the workplaces, the best first, and the places left at each
	type Spot = { uid: number, out: number, n: number, order: number }
	local list: { Spot } = {}
	local spots: { [number]: Spot } = {}
	for i, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 and Island.works(q.id) then
			local sp: Spot = { uid = q.uid, out = d.rate * (Tuning.UpgradeMult[q.lvl or 1] or 1), n = d.jobs, order = i }
			spots[q.uid] = sp
			table.insert(list, sp)
		end
	end
	-- the pinned keep their places (a place gone: back to the arrangement); one with no hut rests
	local free: { Types.Pal } = {}
	for _, x in p.pals do
		if x.home == 0 or homes["p" .. x.id] == nil then
			x.work = 0
		elseif x.pin then
			local sp = if x.work ~= 0 then spots[x.work] else nil
			if x.work ~= 0 and (sp == nil or sp.n <= 0) then
				x.pin = nil
				table.insert(free, x)
			elseif sp then
				sp.n -= 1
			end
		else
			table.insert(free, x)
		end
	end
	table.sort(list, function(a, b)
		if math.abs(a.out - b.out) > 1e-9 then
			return a.out > b.out
		end
		return a.order < b.order
	end)
	-- each one's speed (the same at every workplace)
	local speed: { [Types.Pal]: number } = {}
	for _, x in free do
		local c = homes["p" .. x.id].comfort
		local d = Creatures.byId[x.sp]
		local r = if d then d.rarity else 1
		speed[x] = Tuning.PalWork * (Tuning.RarityWork[r] or 1) * math.max(0, 1 + Traits.work(Island.fxOf(x)) + c)
	end
	table.sort(free, function(a, b)
		if math.abs(speed[a] - speed[b]) > 1e-9 then
			return speed[a] > speed[b]
		end
		return a.id < b.id
	end)
	local head = 1
	for _, x in free do
		while list[head] and list[head].n <= 0 do
			head += 1
		end
		local sp = list[head]
		if sp then
			sp.n -= 1
			x.work = sp.uid
		else
			x.work = 0
		end
	end
end

-- A driftling living in a hut to any workplace (uid) or resting (0), by the player's hand: it stays there (`pin`)
-- while the rest are arranged round it (Island.arrange). Its `jobs` a building: a full one sends the helper that came
-- first back to the arrangement. One with no hut doesn't work, nor anywhere that makes nothing (bad_payload).
function Island.setHelp(p: Profile, id: number, uid: number): (boolean, any)
	local who: Types.Pal? = nil
	for _, pal in p.pals do
		if pal.id == id then
			who = pal
		end
	end
	if who == nil then
		return false, "not_found" :: ErrCode
	end
	if uid ~= 0 then
		local q = Island.piece(p, uid)
		local def = Creatures.byId[who.sp]
		if q == nil or def == nil or not Island.works(q.id) or who.home == 0 then
			return false, "bad_payload" :: ErrCode
		end
		local there: { Types.Pal } = {}
		for _, pal in p.pals do
			if pal ~= who and pal.work == uid then
				table.insert(there, pal)
			end
		end
		if #there >= (Buildings.byId[q.id] :: Buildings.BuildingDef).jobs then
			there[1].work = 0
			there[1].pin = nil
		end
	end
	who.work = uid
	who.pin = true
	Island.arrange(p)
	return true, nil
end

-- A driftling handed back to the arrangement (the work picker's Auto): it works wherever it makes the most.
function Island.autoWork(p: Profile, id: number): (boolean, any)
	for _, pal in p.pals do
		if pal.id == id then
			pal.pin = nil
			Island.arrange(p)
			return true, { work = pal.work }
		end
	end
	return false, "not_found" :: ErrCode
end

------------------------------------------------------------------ the island's size
-- Growing the island to the next tier: its price in shells, TierCost's wood at Tuning.WoodShells (it was wood until
-- 2026-11-14: "allowing you to buy decor and expansions with it"), nil at the biggest.
function Island.expandCost(tier: number): { shells: number }?
	local w = Tuning.TierCost[tier + 1]
	return if w then { shells = Buildings.shellsFor(w, tier + 1) } else nil
end

function Island.expand(p: Profile): (boolean, any)
	local cost = Island.expandCost(p.tier)
	if cost == nil then
		return false, "max" :: ErrCode
	end
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	p.shells -= cost.shells
	p.tier += 1
	-- pieces that no longer fit the bigger island's shape make room (Plot.refit)
	local moved, cleared = Plot.refit(p)
	Island.arrange(p)
	return true, { tier = p.tier, moved = moved, cleared = cleared }
end

-- The founder's colours and hair style (free; the pieces they wear stay on: Logic/Store.wear).
function Island.setFounder(p: Profile, skin: number, hair: number, style: number, shirt: number): (boolean, any)
	if skin > #Looks.skin or hair > #Looks.hair or style > #Looks.styles or shirt > #Looks.shirt then
		return false, "bad_payload" :: ErrCode
	end
	local f = p.founder
	f.skin, f.hair, f.style, f.shirt = skin, hair, style, shirt
	return true, nil
end

return Island
