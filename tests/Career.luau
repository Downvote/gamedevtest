-- A sensible player for the Economy spec and the tuning runs: plays a session second by second through the island's
-- own rules (Logic/Island, Plot, Tree: what the server runs) and logs it every ten minutes. Every few seconds they
-- hatch the rarest egg under the Tree of Life they can afford (into a hut with room, or swapping out their weakest
-- when it is a rarer egg than that one was), then build what the island lacks most with its shells (a hut while the huts are full and a good one
-- floats by, a building for driftlings resting with no work or working away from their knack, the workplace that pays back soonest while the
-- shells come slowly, a shop a tier, decor with spare shells), and expand the island when they can. One store since 2026-11-14 (shells pay
-- for everything), so while they save for the next tier they keep a reserve: an egg or a building only when they could pay for it three times.
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Island = require("../build/luautest/shared/Logic/Island")
local Plot = require("../build/luautest/shared/Logic/Plot")
local Tree = require("../build/luautest/shared/Logic/Tree")
local Weather = require("../build/luautest/shared/Logic/Weather")
local Breed = require("../build/luautest/shared/Logic/Breed")
local Buildings = require("../build/luautest/shared/Data/Buildings")
local Creatures = require("../build/luautest/shared/Data/Creatures")
local Street = require("../build/luautest/shared/Data/Street")
local Util = require("../build/luautest/shared/Logic/Util")

local Career = {}

local clock = 0 -- the career's second now: the sea's clock its weather comes from (Logic/Weather)

export type Opts = { log: ((string) -> ())? }

-- The first free spot for a piece (scanning the island in rows). A map of the covered cells first, so Plot.fits (which
-- looks at every piece) only checks the spots that are free on it (a full island has hundreds of pieces).
local function spot(p: any, id: string): (number?, number?)
	local r = Street.plot(p.tier)
	local covered: { [number]: boolean } = {}
	-- (decor, plants and fun pieces may stand on path tiles: those don't count for them)
	local onPaths = Plot.onPaths(id)
	for _, q in p.plot.placed do
		if not Plot.isFence(q.id) and not (onPaths and Plot.isPath(q.id)) then
			local qr = Plot.rect(q.id, q.x, q.z, q.rot)
			for cz = qr.z0, qr.z1 - 1 do
				for cx = qr.x0, qr.x1 - 1 do
					covered[Street.cellKey(cx, cz)] = true
				end
			end
		end
	end
	local w, d = Plot.footprint(id, 0)
	local function free(x: number, z: number): boolean
		for cz = z, z + d - 1 do
			for cx = x, x + w - 1 do
				if covered[Street.cellKey(cx, cz)] or not Street.buildable(p.tier, cx, cz) then
					return false
				end
			end
		end
		return true
	end
	for z = r.z0 + 1, r.z1 - 2 do
		for x = r.x0 + 1, r.x1 - 2 do
			if free(x, z) and Plot.fits(p.tier, p.plot.placed, id, x, z, 0) then
				return x, z
			end
		end
	end
	return nil, nil
end

local function build(p: any, id: string): boolean
	local d = Buildings.byId[id]
	if d == nil or d.tier > p.tier or p.shells < d.shells then
		return false
	end
	-- (no room for one more of its count, or a hut past the huts' limit: no scan of the island for a spot)
	local used, most = Plot.used(p, id)
	if used >= most or (d.kind == "nest" and Plot.huts(p.plot.placed) >= Plot.hutLimit(p.tier)) then
		return false
	end
	local x, z = spot(p, id)
	if x == nil then
		return false
	end
	local ok = Plot.place(p, id, x :: number, z :: number, 0)
	if ok then
		-- (the driftlings arrange themselves where they make the most: Island.arrange, as on the server)
		Tree.settle(p)
		Tree.fillJobs(p)
	end
	return ok
end

-- The best building of a kind the island can have now (the highest tier first).
local function best(p: any, kind: string): string?
	local pick: any = nil
	for _, d in Buildings.list do
		if d.kind == kind and d.tier <= p.tier and (pick == nil or d.tier > pick.tier or (d.tier == pick.tier and d.shells > pick.shells)) then
			pick = d
		end
	end
	return if pick then pick.id else nil
end

local function countKind(p: any, kind: string): number
	local n = 0
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == kind then
			n += 1
		end
	end
	return n
end

-- The weakest building of a kind replaced with the best the island can have (where it stands, its workers staying;
-- else cleared away and the new one built where there's room), as a player upgrades a camp to a mill once the island
-- has places to spare at work. `k`: how many times its price there must be in the store.
local function upgrade(p: any, kind: string, k: number): boolean
	local bestId = best(p, kind)
	local bd = if bestId then Buildings.byId[bestId] else nil
	if bd == nil or p.shells < bd.shells * k then
		return false
	end
	local worst: any, wi = nil, 0
	for i, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == kind and (worst == nil or d.rate < worst.rate) then
			worst, wi = d, i
		end
	end
	if worst == nil or worst.rate >= bd.rate then
		return false
	end
	if Plot.replace(p, wi, bd.id) then
		Tree.settle(p)
		Tree.fillJobs(p)
		return true
	end
	if spot(p, bd.id) ~= nil and Plot.store(p, wi) then
		build(p, bd.id)
		Tree.settle(p)
		Tree.fillJobs(p)
		return true
	end
	return false
end

-- Places at work with nobody there (every workplace takes Tuning.HelpMax).
local function freeJobs(p: any): number
	local jobs, at = 0, 0
	for _, q in p.plot.placed do
		if Island.works(q.id) then
			jobs += Tuning.HelpMax
		end
	end
	for _, pal in p.pals do
		if pal.work ~= 0 then
			at += 1
		end
	end
	return jobs - at
end

-- The weakest driftling in a hut (the one a swap gives up), or nil.
local function weakest(p: any): any
	local w: any = nil
	for _, x in p.pals do
		if x.home ~= 0 and (w == nil or Tree.better(w, x)) then
			w = x
		end
	end
	return w
end

-- The driftlings living in huts.
local function housedOf(p: any): number
	local n = 0
	for _, x in p.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end

-- Whether they are saving up for the next tier (once the island is going: four in huts a tier) and so keep a reserve.
local function savingUp(p: any): boolean
	local ex = Island.expandCost(p.tier)
	return ex ~= nil and housedOf(p) >= 4 * p.tier and p.shells < ex.shells
end

-- Under the tree: the rarest egg it can afford, into a hut with room (while there is work waiting, or the egg is better
-- than common), or in a swap for the weakest when the egg is two rarities better than it.
local function shop(p: any, rng: any): any
	local list = {}
	for _, e in p.clutch.list do
		table.insert(list, { e = e, cost = Tree.cost(p, e.r) })
	end
	table.sort(list, function(a, b)
		if a.e.r ~= b.e.r then
			return a.e.r > b.e.r
		end
		return a.cost < b.cost
	end)
	local room = Tree.room(p)
	local k = if savingUp(p) then 3 else 1
	for _, x in list do
		if x.cost * k <= p.shells then
			if room > 0 then
				local jobs = 0
				for _, q in p.plot.placed do
					if Island.works(q.id) then
						jobs += Tuning.HelpMax
					end
				end
				local at = 0
				for _, pal in p.pals do
					if pal.work ~= 0 then
						at += 1
					end
				end
				if jobs > at or x.e.r >= 2 then
					local ok, data = Tree.hatch(p, x.e.id, 0, rng)
					if ok then
						return data
					end
				end
			else
				local w = weakest(p)
				local wr = if w then Creatures.byId[w.sp].rarity else 5
				if w and x.e.r >= wr + 2 then
					local ok, data = Tree.hatch(p, x.e.id, w.id, rng)
					if ok then
						return data
					end
				end
			end
		end
	end
	return nil
end

-- Growing the island the moment the shells cover it (before anything else is bought).
local function tryExpand(p: any, rng: any): boolean
	local ex = Island.expandCost(p.tier)
	if ex and p.shells >= ex.shells and Island.expand(p) then
		Tree.settle(p)
		Tree.fill(p, rng, Weather.at(clock))
		return true
	end
	return false
end

-- The workplace that pays back soonest (its rate over its price) of the best of each group the island can have.
local function payback(p: any, k: number): string?
	local pick, score = nil, 0
	for _, kind in { "farm", "wood", "shop" } do
		local id = best(p, kind)
		local d = if id then Buildings.byId[id] else nil
		if d and p.shells >= d.shells * k and d.rate / math.max(1, d.shells) > score then
			pick, score = d.id, d.rate / math.max(1, d.shells)
		end
	end
	return pick
end

-- One building decision.
local function plan(p: any, rng: any)
	local r = Island.rates(p)
	local ex = Island.expandCost(p.tier)
	-- the tips' buildings first (a camp, a patch, a hut, then a stall), as a new player builds them
	for _, first in { { "wood", "lumber" }, { "farm", "patch" }, { "nest", "nest" }, { "shop", "stall" } } do
		if countKind(p, first[1]) == 0 then
			build(p, first[2])
			return
		end
	end
	local housed = 0
	-- (the driftlings that want a building of their knack: resting, or working at another knack's, where they work
	-- slower)
	local resting: { [string]: number } = {}
	for _, x in p.pals do
		if x.home ~= 0 then
			housed += 1
			local k = Creatures.byId[x.sp].knack
			local q = if x.work ~= 0 then Island.piece(p, x.work) else nil
			local bd = if q then Buildings.byId[q.id] else nil
			if x.work == 0 or (bd and bd.knack ~= k) then
				resting[k] = (resting[k] or 0) + 1
			end
		end
	end
	-- saving up for the next tier once the island is going
	local saving = ex ~= nil and housed >= 4 * p.tier and p.shells < ex.shells
	local wants: { string } = {}
	-- a hut when every hut is full and the island has work for more; at the island's huts' limit, a bigger hut in the
	-- smallest one's place
	if Tree.room(p) <= 0 then
		local jobs = 0
		for _, q in p.plot.placed do
			if Island.works(q.id) then
				jobs += Tuning.HelpMax
			end
		end
		if jobs > housed then
			if Plot.huts(p.plot.placed) >= Plot.hutLimit(p.tier) then
				local small, si = math.huge, 0
				for i, q in p.plot.placed do
					local d = Buildings.byId[q.id]
					if d and d.kind == "nest" and d.slots < small then
						small, si = d.slots, i
					end
				end
				local big = best(p, "nest")
				local bd = if big then Buildings.byId[big] else nil
				if si > 0 and bd and bd.slots > small and p.shells >= bd.shells * (if saving then 3 else 1) then
					if Plot.replace(p, si, bd.id) then
						Tree.settle(p)
						Tree.fillJobs(p)
						return
					end
					-- (it doesn't fit where the small one stands: the small one comes down, the big one goes up where
					-- there's room, and its driftlings move in)
					local q = p.plot.placed[si]
					local rest = table.clone(p.plot.placed)
					table.remove(rest, si)
					local r = Street.plot(p.tier)
					local fits = false
					for z = r.z0 + 1, r.z1 - 2 do
						for x = r.x0 + 1, r.x1 - 2 do
							if not fits and Plot.fits(p.tier, rest, bd.id, x, z, 0) then
								fits = true
							end
						end
					end
					if fits and q and Plot.store(p, si) then
						build(p, bd.id)
						Tree.settle(p)
						Tree.fillJobs(p)
						return
					end
					-- (no room anywhere: the weakest workplace nobody works at comes down to make some)
					if not fits and freeJobs(p) >= Tuning.HelpMax then
						local taken: { [number]: boolean } = {}
						for _, pal in p.pals do
							if pal.work ~= 0 then
								taken[pal.work] = true
							end
						end
						local low, li = math.huge, 0
						for i, w in p.plot.placed do
							local d = Buildings.byId[w.id]
							if d and Island.works(w.id) and not taken[w.uid] and d.rate < low then
								low, li = d.rate, i
							end
						end
						if li > 0 and Plot.store(p, li) then
							return
						end
					end
				end
			else
				table.insert(wants, "nest")
			end
		end
	end
	-- (more coming in when it comes slowly, or when saving up for the next tier at this rate would take over half an
	-- hour: the workplace that pays back soonest)
	local slowSave = ex ~= nil and p.shells < ex.shells and (ex.shells - p.shells) / math.max(1, r.shells) > 1800 / Tuning.TurnSeconds
	if r.shells < 40 * p.tier or slowSave then
		table.insert(wants, "earn")
	end
	if countKind(p, "shop") < p.tier then
		table.insert(wants, "shop")
	end
	if countKind(p, "farm") < p.tier + 1 then
		table.insert(wants, "farm")
	end
	do
		local most, pick = 0, nil
		for knack, n in resting do
			if n > most then
				most, pick = n, knack
			end
		end
		if pick then
			table.insert(wants, "knack:" .. pick)
		end
	end
	for _, kind in wants do
		if kind == "earn" then
			local id = payback(p, if saving then 3 else 1)
			if id and build(p, id) then
				return
			end
			continue
		end
		if string.sub(kind, 1, 6) == "knack:" then
			-- a building of that knack (the best the island can have now that it can afford, else a cheaper one)
			local knack = string.sub(kind, 7)
			local pick: any = nil
			for _, d in Buildings.list do
				-- (while saving for the next tier, only one it can easily afford)
				local k = if saving then 3 else 1
				if d.knack == knack and d.tier <= p.tier and p.shells >= d.shells * k and (pick == nil or d.tier > pick.tier) then
					pick = d
				end
			end
			if pick and build(p, pick.id) then
				return
			end
			continue
		end
		local id = best(p, kind)
		if id and (not saving or p.shells >= Buildings.byId[id].shells * 3) and build(p, id) then
			return
		end
		-- (no room for it: the weakest of its kind makes way for it)
		if id and upgrade(p, kind, if saving then 3 else 1) then
			return
		end
		-- a cheaper one of the kind will do
		for _, d in Buildings.list do
			if d.kind == kind and (not saving or p.shells >= d.shells * 3) and build(p, d.id) then
				return
			end
		end
	end
	-- spare shells go on decor (the dearest the island can have and easily afford), keeping two thirds of the island's
	-- piece room for buildings (the catalog has plenty of cheap decor: a player decorates, but not before the huts),
	-- nothing that needs water
	local decor = 0
	for _, q in p.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "decor" then
			decor += 1
		end
	end
	if not saving and decor < Plot.limit(p.tier) // 3 then
		local pick: any = nil
		for _, d in Buildings.list do
			if d.kind == "decor" and d.water == "" and d.tier <= p.tier and p.shells >= d.shells * 4 and (pick == nil or d.shells > pick.shells) then
				pick = d
			end
		end
		if pick then
			build(p, pick.id)
		end
	end
end

function Career.play(seed: number, seconds: number, opts: Opts?)
	local o: Opts = opts or {}
	local log = o.log
	local p = Schema.default(0, seed)
	local rng = Util.newRng(Util.hash32("career:" .. seed)) -- (hashed, as the server seeds a session: a small seed's first draws are weak)
	local turnClock = 0
	local first: { [string]: number } = {}
	local timeline = {}
	local soldAt = 0
	local function say(line: string)
		if log then
			log(line)
		end
	end
	local function mark(k: string, t: number)
		if first[k] == nil then
			first[k] = t
			say(string.format("  %5ds %s", t, k))
		end
	end
	local shellsSold = 0
	for t = 1, seconds do
		Island.step(p, 1)
		clock = t
		-- (the eggs laid in the weather of the sea's clock from the epoch: GAME_DESIGN 13, the weather mutations counted)
		Tree.step(p, 1, rng, Weather.at(t))
		turnClock += 1
		if turnClock >= Tuning.TurnSeconds then
			turnClock -= Tuning.TurnSeconds
			Breed.turn(p)
		end
		-- (every five seconds; every twenty from Moonlit Bay on, where a turn's choices are big ones and the Economy
		-- spec's three hours never reach)
		if t % (if p.tier >= 7 then 20 else 5) == 0 then
			tryExpand(p, rng)
			local before = p.stats.earned
			local sold = p.stats.sold
			local got = shop(p, rng)
			if p.stats.sold > sold then
				shellsSold += p.stats.earned - before
			end
			if got then
				mark("taken", t)
				local r = Creatures.byId[got.sp].rarity
				for k = 2, r do
					mark("rarity" .. k, t)
				end
			end
			plan(p, rng)
		end
		for _, x in p.pals do
			if x.work ~= 0 then
				mark("helper", t)
			end
		end
		for k = 2, p.tier do
			mark("tier" .. k, t)
		end
		if t % 600 == 0 then
			local r = Island.rates(p)
			local housed = 0
			for _, x in p.pals do
				if x.home ~= 0 then
					housed += 1
				end
			end
			soldAt = shellsSold
			local charm = Island.charm(p)
			local row = { t = t, shells = p.shells, pals = housed, tier = p.tier, pieces = #p.plot.placed, charm = charm, shellRate = r.shells, sold = soldAt, earned = p.stats.earned, taken = p.stats.taken, best = p.stats.best }
			table.insert(timeline, row)
			say(string.format("%3dmin shells %d (+%.0f/t) tier %d pieces %d huts %d taken %d best %d charm %d (+%d%%) sold %d of %d", t // 60, math.floor(p.shells), r.shells, p.tier, #p.plot.placed, housed, p.stats.taken, p.stats.best, charm, math.round(Island.charmBonus(charm) * 100), math.floor(soldAt), math.floor(p.stats.earned)))
		end
	end
	return { profile = p, timeline = timeline, first = first, sold = shellsSold }
end

return Career
