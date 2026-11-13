-- A sensible player for the Economy spec and the tuning runs: plays a session second by second through the island's
-- own rules (Logic/Island, Plot, Tide: what the server runs) and logs it every ten minutes. Every few seconds they
-- take in the best driftling on the tide they can afford (into a hut with room, or swapping out their weakest for one
-- clearly better), then build what the island lacks most with its wood (a hut while the huts are full and a good one
-- floats by, a building for driftlings resting with no work, wood when it comes slowly, a shop a tier, decor with
-- spare wood), and expand the island when they can.
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Island = require("../build/luautest/shared/Logic/Island")
local Plot = require("../build/luautest/shared/Logic/Plot")
local Tide = require("../build/luautest/shared/Logic/Tide")
local Breed = require("../build/luautest/shared/Logic/Breed")
local Buildings = require("../build/luautest/shared/Data/Buildings")
local Creatures = require("../build/luautest/shared/Data/Creatures")
local Street = require("../build/luautest/shared/Data/Street")
local Util = require("../build/luautest/shared/Logic/Util")

local Career = {}

export type Opts = { log: ((string) -> ())? }

-- The first free spot for a piece (scanning the island in rows).
local function spot(p: any, id: string): (number?, number?)
	local r = Street.plot(p.tier)
	for z = r.z0 + 1, r.z1 - 2 do
		for x = r.x0 + 1, r.x1 - 2 do
			if Plot.fits(p.tier, p.plot.placed, id, x, z, 0) then
				return x, z
			end
		end
	end
	return nil, nil
end

local function build(p: any, id: string): boolean
	local d = Buildings.byId[id]
	if d == nil or d.tier > p.tier or p.shells < d.shells or p.wood < d.wood then
		return false
	end
	local x, z = spot(p, id)
	if x == nil then
		return false
	end
	local ok = Plot.place(p, id, x :: number, z :: number, 0)
	if ok then
		Tide.settle(p)
		Tide.fillJobs(p)
	end
	return ok
end

-- The best building of a kind the island can have now (the highest tier first).
local function best(p: any, kind: string): string?
	local pick: any = nil
	for _, d in Buildings.list do
		if d.kind == kind and d.tier <= p.tier and (pick == nil or d.tier > pick.tier or (d.tier == pick.tier and d.wood > pick.wood)) then
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

-- The weakest driftling in a hut (the one a swap gives up), or nil.
local function weakest(p: any): any
	local w: any = nil
	for _, x in p.pals do
		if x.home ~= 0 and (w == nil or Tide.better(w, x)) then
			w = x
		end
	end
	return w
end

-- Off the tide: the best one it can afford, into a hut with room (one with work waiting for it first), or in a swap
-- for the weakest when it is clearly better.
local function shop(p: any, s: any): any
	local list = {}
	for _, d in s.list do
		local x = { id = 0, sp = d.sp, home = 0, work = 0, muts = d.muts }
		table.insert(list, { d = d, w = Tide.worth(x), cost = Tide.cost(p, d.sp, d.muts) })
	end
	table.sort(list, function(a, b)
		return a.w > b.w
	end)
	local room = Tide.room(p)
	for _, e in list do
		if e.cost <= p.shells then
			local knack = Creatures.byId[e.d.sp].knack
			if room > 0 and (Island.freeJob(p, knack) ~= 0 or e.w >= Tuning.RarityWork[2]) then
				local ok = Tide.take(p, s, e.d.id, 0)
				if ok then
					return e.d
				end
			elseif room <= 0 then
				local w = weakest(p)
				if w and e.w > Tide.worth(w) * 1.4 then
					local ok = Tide.take(p, s, e.d.id, w.id)
					if ok then
						return e.d
					end
				end
			end
		end
	end
	return nil
end

-- One building decision.
local function plan(p: any, s: any)
	local r = Island.rates(p)
	local ex = Island.expandCost(p.tier)
	if ex and p.wood >= ex.wood then
		Island.expand(p)
		Tide.settle(p)
		return
	end
	-- the tips' buildings first (a camp, a patch, a hut, then a stall), as a new player builds them
	for _, first in { { "wood", "lumber" }, { "farm", "patch" }, { "nest", "nest" }, { "shop", "stall" } } do
		if countKind(p, first[1]) == 0 then
			build(p, first[2])
			return
		end
	end
	local housed = 0
	local resting: { [string]: number } = {}
	for _, x in p.pals do
		if x.home ~= 0 then
			housed += 1
			if x.work == 0 then
				local k = Creatures.byId[x.sp].knack
				resting[k] = (resting[k] or 0) + 1
			end
		end
	end
	-- saving up for the next tier once the island is going
	local saving = ex ~= nil and housed >= 4 * p.tier and p.wood < ex.wood
	local wants: { string } = {}
	-- a hut when every hut is full and the island has work for more
	if Tide.room(p) <= 0 then
		local jobs = 0
		for _, q in p.plot.placed do
			if Island.works(q.id) then
				jobs += Tuning.HelpMax
			end
		end
		if jobs > housed then
			table.insert(wants, "nest")
		end
	end
	if r.wood < 20 * p.tier or (ex and p.wood < ex.wood and r.wood < 60 * p.tier) then
		table.insert(wants, "wood")
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
		if string.sub(kind, 1, 6) == "knack:" then
			-- a building of that knack (the best the island can have now that it can afford, else a cheaper one)
			local knack = string.sub(kind, 7)
			local pick: any = nil
			for _, d in Buildings.list do
				-- (while saving for the next tier, only one it can easily afford)
				local k = if saving then 3 else 1
				if d.knack == knack and d.tier <= p.tier and p.wood >= d.wood * k and (pick == nil or d.tier > pick.tier) then
					pick = d
				end
			end
			if pick and build(p, pick.id) then
				return
			end
			continue
		end
		local id = best(p, kind)
		if id and (not saving or p.wood >= Buildings.byId[id].wood * 3) and build(p, id) then
			return
		end
		-- a cheaper one of the kind will do
		for _, d in Buildings.list do
			if d.kind == kind and (not saving or p.wood >= d.wood * 3) and build(p, d.id) then
				return
			end
		end
	end
	-- spare wood goes on decor (the dearest the island can have and easily afford)
	if not saving then
		local pick: any = nil
		for _, d in Buildings.list do
			if d.kind == "decor" and d.tier <= p.tier and p.wood >= d.wood * 4 and (pick == nil or d.wood > pick.wood) then
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
	local s = Tide.new()
	Tide.start(p, s, rng)
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
		Tide.step(p, s, 1, rng)
		turnClock += 1
		if turnClock >= Tuning.TurnSeconds then
			turnClock -= Tuning.TurnSeconds
			Breed.turn(p)
		end
		if t % 5 == 0 then
			local before = p.stats.earned
			local sold = p.stats.sold
			local got = shop(p, s)
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
			plan(p, s)
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
			local row = { t = t, shells = p.shells, wood = p.wood, pals = housed, tier = p.tier, pieces = #p.plot.placed, charm = Island.charm(p), shellRate = r.shells, woodRate = r.wood, sold = soldAt, earned = p.stats.earned, taken = p.stats.taken, best = p.stats.best }
			table.insert(timeline, row)
			say(string.format("%3dmin shells %d (+%.0f/t) wood %d (+%.0f/t) tier %d pieces %d huts %d taken %d best %d charm %d sold %d of %d", t // 60, math.floor(p.shells), r.shells, math.floor(p.wood), r.wood, p.tier, #p.plot.placed, housed, p.stats.taken, p.stats.best, Island.charm(p), math.floor(soldAt), math.floor(p.stats.earned)))
		end
	end
	return { profile = p, timeline = timeline, first = first, sold = shellsSold }
end

return Career
