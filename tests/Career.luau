-- A sensible player for the Economy spec and the tuning runs: plays a session second by second through the island's
-- own rules (Logic/Island, Plot, Tree: what the server runs) and logs it every ten minutes. Every few seconds they
-- build what the island lacks most (food when it runs short, a hut while the pen has driftlings, the huts are full and
-- there is work for more, wood, a shop a tier, decor with spare shells), expand the island when they can, buy the
-- tree's next speed or luck when it costs a third of their shells or less, and sell the pen's commons once a few wait
-- there (its uncommons too once many do).
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Island = require("../build/luautest/shared/Logic/Island")
local Plot = require("../build/luautest/shared/Logic/Plot")
local Tree = require("../build/luautest/shared/Logic/Tree")
local Breed = require("../build/luautest/shared/Logic/Breed")
local Buildings = require("../build/luautest/shared/Data/Buildings")
local Creatures = require("../build/luautest/shared/Data/Creatures")
local Street = require("../build/luautest/shared/Data/Street")
local Util = require("../build/luautest/shared/Logic/Util")

local Career = {}

export type Opts = { log: ((string) -> ())?, skill: number? }

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
	return (Plot.place(p, id, x :: number, z :: number, 0))
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

-- One building decision.
local function plan(p: any)
	local r = Island.rates(p)
	local ex = Island.expandCost(p.tier)
	if ex and p.shells >= ex.shells and p.wood >= ex.wood then
		Island.expand(p)
		Tree.settle(p)
		return
	end
	-- the tips' buildings first (a patch, a camp, a stall, a hut), as a new player builds them
	for _, first in { { "food", "patch" }, { "wood", "lumber" }, { "shop", "stall" }, { "nest", "nest" } } do
		if countKind(p, first[1]) == 0 then
			if build(p, first[2]) then
				Tree.settle(p)
				Tree.fillJobs(p)
			end
			return
		end
	end
	local housed = 0
	for _, x in p.pals do
		if x.home ~= 0 then
			housed += 1
		end
	end
	-- saving up for the next tier once the island is going (its shells and its wood)
	local saving = ex ~= nil and housed >= 4 * p.tier and (p.shells < ex.shells or p.wood < ex.wood)
	local wants: { string } = {}
	if r.food < 3 or p.food < 20 then
		table.insert(wants, "food")
	end
	-- the pen: a hut when one waiting has a free place at work but no hut has room; a building of a knack two or more
	-- wait for with nowhere to work
	local room = 0
	for _, h in Tree.huts(p) do
		room += h.room - h.n
	end
	local waiting: { [string]: number } = {}
	local needHut = false
	for _, x in p.pals do
		if x.home == 0 and x.held == nil then
			local knack = Creatures.byId[x.sp].knack
			if Island.freeJob(p, knack) ~= 0 then
				needHut = needHut or room <= 0
			else
				waiting[knack] = (waiting[knack] or 0) + 1
			end
		end
	end
	if needHut then
		table.insert(wants, "nest")
	end
	if r.wood < 3 + 5 * p.tier or (ex and p.wood < ex.wood and r.wood < 10 * p.tier) then
		table.insert(wants, "wood")
	end
	if countKind(p, "shop") < p.tier then
		table.insert(wants, "shop")
	end
	do
		local most, pick = 1, nil
		for knack, n in waiting do
			if n > most then
				most, pick = n, knack
			end
		end
		if pick then
			table.insert(wants, "knack:" .. pick)
		end
	end
	for _, kind in wants do
		local id = best(p, kind)
		if string.sub(kind, 1, 6) == "knack:" then
			-- a building of that knack (the best the island can have now that it can afford, else a cheaper one)
			local knack = string.sub(kind, 7)
			local pick: any = nil
			for _, d in Buildings.list do
				-- (while saving for the next tier, only one it can easily afford)
				local k = if saving then 3 else 1
				if d.knack == knack and d.tier <= p.tier and p.shells >= d.shells * k and p.wood >= d.wood * k and (pick == nil or d.tier > pick.tier) then
					pick = d
				end
			end
			if pick and build(p, pick.id) then
				Tree.settle(p)
				Tree.fillJobs(p)
				return
			end
			continue
		end
		if id and build(p, id) then
			Tree.settle(p)
			Tree.fillJobs(p)
			return
		end
		-- a cheaper one of the kind will do
		for _, d in Buildings.list do
			if d.kind == kind and build(p, d.id) then
				Tree.settle(p)
				Tree.fillJobs(p)
				return
			end
		end
	end
	-- the tree: its next speed or luck when it costs a third of the shells or less
	for _, what in { "speed", "luck" } do
		local c = Tree.upgradeCost(p, what)
		if c and c.shells * 3 <= p.shells and c.wood * 3 <= p.wood then
			Tree.upgrade(p, what)
			return
		end
	end
	-- spare shells go on decor (the dearest the island can have and easily afford)
	if not saving then
		local pick: any = nil
		for _, d in Buildings.list do
			if d.kind == "decor" and d.tier <= p.tier and p.shells >= d.shells * 3 and p.wood >= d.wood * 2 and (pick == nil or d.shells > pick.shells) then
				pick = d
			end
		end
		if pick then
			build(p, pick.id)
		end
	end
end

-- The pen (it never fills): its commons sold once a few wait there, its uncommons too once many do.
local function tidy(p: any)
	local n = Tree.inPen(p)
	if n > 8 then
		Tree.sellPen(p, 1)
	end
	if Tree.inPen(p) > 20 then
		Tree.sellPen(p, 2)
	end
end

function Career.play(seed: number, seconds: number, opts: Opts?)
	local o: Opts = opts or {}
	local log = o.log
	local p = Schema.default(0, seed)
	local rng = Util.newRng(Util.hash32("career:" .. seed)) -- (hashed, as the server seeds a session: a small seed's first draws are weak)
	local turnClock = 0
	local sold = 0
	local first: { [string]: number } = {}
	local timeline = {}
	local function say(s: string)
		if log then
			log(s)
		end
	end
	local function mark(k: string, t: number)
		if first[k] == nil then
			first[k] = t
			say(string.format("  %5ds %s", t, k))
		end
	end
	for t = 1, seconds do
		Island.step(p, 1)
		local grown, _, auto = Tree.step(p, 1, rng)
		sold += auto
		for _, x in grown do
			local r = Creatures.byId[x.sp].rarity
			for k = 2, r do
				mark("rarity" .. k, t)
			end
		end
		turnClock += 1
		if turnClock >= Tuning.TurnSeconds then
			turnClock -= Tuning.TurnSeconds
			Breed.turn(p)
		end
		if t % 5 == 0 then
			plan(p)
			local before = p.stats.earned
			tidy(p)
			sold += p.stats.earned - before
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
			local row = { t = t, shells = p.shells, food = p.food, wood = p.wood, pals = housed, pen = Tree.inPen(p), tier = p.tier, luck = p.tree.luck, speed = p.tree.speed, pieces = #p.plot.placed, charm = Island.charm(p), shellRate = r.shells, foodRate = r.food, woodRate = r.wood, sold = sold, earned = p.stats.earned }
			table.insert(timeline, row)
			say(string.format("%3dmin shells %d (+%.0f/t) food %d (%+.0f/t) wood %d (+%.0f/t) tier %d pieces %d huts %d pen %d luck %d speed %d charm %d sold %d of %d", t // 60, math.floor(p.shells), r.shells, math.floor(p.food), r.food, math.floor(p.wood), r.wood, p.tier, #p.plot.placed, housed, Tree.inPen(p), p.tree.luck, p.tree.speed, Island.charm(p), math.floor(sold), math.floor(p.stats.earned)))
		end
	end
	return { profile = p, timeline = timeline, first = first, sold = sold }
end

return Career
