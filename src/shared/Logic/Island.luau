--!strict
-- The island's rules (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 6): what it makes a turn, its charm and what charm adds,
-- which driftling works where, expanding the island. The driftlings do all the work (the request of 2026-11-12:
-- "remove villagers, only creatures should be enough"). Pure: IslandService calls these with the session's profile;
-- the Economy spec plays whole sessions through the same functions. Actions return (true, data?) or (false, ErrCode)
-- and change the profile only when they succeed.
--
-- A turn (Tuning.TurnSeconds): each building of kind farm, wood or shop makes its rate (Data/Buildings) times
--   (the work of its driftlings, up to Tuning.HelpMax: each PalWork x its rarity's RarityWork x (1 + its work share +
--   its hut's comfort), its work share its passive's and mutations' (Data/Traits: work and the building's knack; a
--   driftling may work anywhere, its passive usually helping at its own knack's buildings);
--   IdleOutput with none)
--   x (1 + the boost buildings' share at its knack)
-- in shells, all of it: a farm sells what it grows, a wood building what it cuts, a shop its snacks and rooms (the
-- request of 2026-11-14: "make shells the main currency ... the wood tab buildings will also now give shells ... remove
-- the visitors mechanic, charm simply increases your shell gain"); then the whole is times 1 + the charm bonus
-- (`charmBonus`). Nothing eats (food went on 2026-11-13: "remove food as a resource"); a driftling with no hut doesn't
-- work.
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

-- The charm: every piece's, and each driftling living in a hut (one each, and their charm share).
function Island.charm(p: Profile): number
	local n = count(p, "charm")
	for _, x in p.pals do
		if x.home ~= 0 then
			n += 1 + (Island.fxOf(x).charm or 0)
		end
	end
	return math.max(0, n)
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

-- The boost buildings' shares (GAME_DESIGN 4.1), by knack and "all": each kind of boost building counts once.
function Island.boosts(p: Profile): { [string]: number }
	local out: { [string]: number } = { farm = 0, wood = 0, shop = 0, all = 0 }
	local seen: { [string]: boolean } = {}
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "gen" and d.boost ~= "" and not seen[d.id] then
			seen[d.id] = true
			out[d.boost] = (out[d.boost] or 0) + d.boostBy
		end
	end
	return out
end

-- The boost at a building of a knack: its own and every building's, `BoostMax` at most.
function Island.boostAt(b: { [string]: number }, knack: string): number
	return math.min(Tuning.BoostMax, (b[knack] or 0) + (b.all or 0))
end

-- Whether a building takes workers (it makes something).
function Island.works(id: string): boolean
	local d = Buildings.byId[id]
	return d ~= nil and (d.kind == "farm" or d.kind == "wood" or d.kind == "shop")
end

-- A driftling's work share where it helps (Data/Traits.workAt: its passive's and mutations' work and the building's
-- knack; at its own knack when it helps nowhere).
function Island.palWork(p: Profile, pal: Types.Pal): number
	local d = Creatures.byId[pal.sp]
	local q = if pal.work ~= 0 then Island.piece(p, pal.work) else nil
	local bd = if q then Buildings.byId[q.id] else nil
	return Traits.workAt(Island.fxOf(pal), if bd then bd.knack else (if d then d.knack else ""))
end

-- What a driftling makes at the building it works at, in shares of the building's rate: PalWork x its rarity's
-- RarityWork x (1 + its work share + its hut's comfort). `comfort`: its hut's (Island.homes), 0 with no hut.
function Island.palBoost(p: Profile, pal: Types.Pal, comfort: number?): number
	local d = Creatures.byId[pal.sp]
	local r = if d then d.rarity else 1
	return Tuning.PalWork * (Tuning.RarityWork[r] or 1) * math.max(0, 1 + Island.palWork(p, pal) + (comfort or 0))
end

-- What a turn makes now (the charm bonus and the passes in).
function Island.rates(p: Profile): Rates
	local out = { shells = 0 }
	local homes = Island.homes(p)
	local boosts = Island.boosts(p)
	-- the working driftlings' shares (each in a hut), added up at each building
	local helper: { [number]: number } = {}
	for _, pal in p.pals do
		local h = homes["p" .. pal.id]
		if pal.work ~= 0 and h then
			helper[pal.work] = (helper[pal.work] or 0) + Island.palBoost(p, pal, h.comfort)
		end
	end
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 and (d.kind == "farm" or d.kind == "wood" or d.kind == "shop") then
			local k = (helper[q.uid] or Tuning.IdleOutput) * (Tuning.UpgradeMult[q.lvl] or 1) * (1 + Island.boostAt(boosts, d.knack))
			out.shells += d.rate * k
		end
	end
	out.shells *= (1 + Island.charmBonus(Island.charm(p))) * Island.passMult(p)
	return out
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

-- dt seconds of the island's turns: what it made (fractions; the stats count the shells).
function Island.step(p: Profile, dt: number): Rates
	local r = Island.rates(p)
	local k = dt / Tuning.TurnSeconds
	p.shells += r.shells * k
	p.stats.earned += r.shells * k
	return { shells = r.shells * k }
end

------------------------------------------------------------------ looks, work and the days
-- A random look (the loading card's art; the founder starts with one too).
function Island.randomLook(rng: Rng): Types.Look
	return { skin = rng:int(1, #Looks.skin), hair = rng:int(1, #Looks.hair), style = rng:int(1, #Looks.styles), shirt = rng:int(1, #Looks.shirt) }
end

-- A free place for a driftling of `knack` (with effects `fx`, Data/Traits): a workplace with fewer than Tuning.HelpMax
-- driftlings working there, or 0. Any driftling may work anywhere (the request of 2026-11-13: "make it such that each
-- creature can work at any place, and is no longer restricted"); this picks the place it goes to by itself: a building
-- of its own knack first (its passive helps there), else the one where it works fastest (`fx`); then the emptiest,
-- farms before wood before shops, the first built.
function Island.freeJob(p: Profile, knack: string, fx: Traits.Fx?): number
	local taken: { [number]: number } = {}
	for _, pal in p.pals do
		if pal.work ~= 0 then
			taken[pal.work] = (taken[pal.work] or 0) + 1
		end
	end
	local best, bestKey = 0, nil :: { number }?
	for k, kind in { "farm", "wood", "shop" } do
		for _, q in p.plot.placed do
			local d = Buildings.byId[q.id]
			local n = taken[q.uid] or 0
			if d and d.kind == kind and n < Tuning.HelpMax then
				-- (compared in order: its knack, its share there, room, then the kind's order and the first built)
				local key = { if d.knack == knack then 1 else 0, if fx then Traits.workAt(fx, d.knack) else 0, -n, -k }
				local better = bestKey == nil
				if bestKey then
					for i = 1, #key do
						if key[i] ~= bestKey[i] then
							better = key[i] > bestKey[i]
							break
						end
					end
				end
				if better then
					best, bestKey = q.uid, key
				end
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
-- by hand (`pin`) works where it makes the most shells: the best workers choose first (their best speed, then the
-- older), each taking the free place where its output is highest, a workplace's own (rate x level x the boosts at
-- its knack) times its speed there (Tuning.PalWork x its rarity's RarityWork x (1 + its work share at that knack +
-- its hut's comfort)). So it goes to the kind of work it does best, at the best workplace of that kind with room,
-- and only elsewhere when that kind is full or much better is free. Ties: its own knack, then farms, wood, shops,
-- then the first built. A pinned one keeps its place while that stands (its place gone, it goes back to the
-- arrangement); one with no hut rests. Runs whenever the island changes (Logic/Tree.fillJobs and settle, a hatch, a
-- building placed, replaced or cleared, a sale, a move, growing the island, a save loaded).
local ARRANGE_KNACKS = { "farm", "wood", "shop" }
function Island.arrange(p: Profile)
	local homes = Island.homes(p)
	local boosts = Island.boosts(p)
	-- the workplaces of each knack, the best first, and the places left at each
	type Spot = { uid: number, out: number, n: number, order: number }
	local byKnack: { [string]: { Spot } } = { farm = {}, wood = {}, shop = {} }
	local spots: { [number]: Spot } = {}
	for i, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.rate > 0 and Island.works(q.id) then
			local out = d.rate * (Tuning.UpgradeMult[q.lvl or 1] or 1) * (1 + Island.boostAt(boosts, d.knack))
			local sp: Spot = { uid = q.uid, out = out, n = Tuning.HelpMax, order = i }
			spots[q.uid] = sp
			local list = byKnack[d.knack]
			if list == nil then
				list = {}
				byKnack[d.knack] = list
			end
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
	for _, list in byKnack do
		table.sort(list, function(a, b)
			if math.abs(a.out - b.out) > 1e-9 then
				return a.out > b.out
			end
			return a.order < b.order
		end)
	end
	-- each one's speed at each knack, and its best
	local speed: { [Types.Pal]: { [string]: number } } = {}
	local best: { [Types.Pal]: number } = {}
	for _, x in free do
		local c = homes["p" .. x.id].comfort
		local d = Creatures.byId[x.sp]
		local r = if d then d.rarity else 1
		local fx = Island.fxOf(x)
		local s: { [string]: number } = {}
		local top = 0
		for _, k in ARRANGE_KNACKS do
			local v = Tuning.PalWork * (Tuning.RarityWork[r] or 1) * math.max(0, 1 + Traits.workAt(fx, k) + c)
			s[k] = v
			top = math.max(top, v)
		end
		speed[x], best[x] = s, top
	end
	table.sort(free, function(a, b)
		if math.abs(best[a] - best[b]) > 1e-9 then
			return best[a] > best[b]
		end
		return a.id < b.id
	end)
	local head: { [string]: number } = { farm = 1, wood = 1, shop = 1 }
	for _, x in free do
		local d = Creatures.byId[x.sp]
		local own = if d then d.knack else ""
		local pick: Spot?, pickOut, pickRank = nil, -1, 99
		for rank, k in ARRANGE_KNACKS do
			local list = byKnack[k]
			local h = head[k]
			while list[h] and list[h].n <= 0 do
				h += 1
			end
			head[k] = h
			local sp = list[h]
			if sp then
				local out = sp.out * speed[x][k]
				local rk = if k == own then 0 else rank
				if out > pickOut + 1e-9 or (math.abs(out - pickOut) <= 1e-9 and rk < pickRank) then
					pick, pickOut, pickRank = sp, out, rk
				end
			end
		end
		if pick then
			pick.n -= 1
			x.work = pick.uid
		else
			x.work = 0
		end
	end
end

-- A driftling living in a hut to any workplace (uid: a farm, a lumber camp or a shop, whatever its knack; it works best
-- at its own) or resting (0), by the player's hand: it stays there (`pin`) while the rest are arranged round it
-- (Island.arrange). Tuning.HelpMax a building: a full one sends the helper that came first back to the arrangement.
-- One with no hut doesn't work, nor anywhere that makes nothing (bad_payload).
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
		if #there >= Tuning.HelpMax then
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
