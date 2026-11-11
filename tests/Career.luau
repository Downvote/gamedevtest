-- A sensible player for the Economy spec and the tuning runs: plays a session second by second through the island's
-- own rules (Logic/Island, Plot, Expedition: what the server runs) and logs it every ten minutes. Every few seconds
-- they build what the island lacks most (a bed when the village is full, food when it runs short, a nest for a new
-- friend, wood, a shop for every three villagers, decor with spare shells), expand the island when they can, and
-- every couple of minutes sail on an expedition with the captain and the three strongest to an island at the
-- captain's level, or lower while the party looks too weak for its guardian or after defeats (the slider). Battles run
-- in time (Expedition.tick, a second at a time); in one they throw a snack at a hurt wild one while a nest is free
-- (one of a kind not yet befriended, or any while they have fewer than six friends: a friend gives no experience),
-- use a skill when the points cover one (a mend for the most hurt member, else the first that strikes), and flee when
-- the party is nearly beaten; a node takes NodeSec.
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Island = require("../build/luautest/shared/Logic/Island")
local Plot = require("../build/luautest/shared/Logic/Plot")
local Expedition = require("../build/luautest/shared/Logic/Expedition")
local Chart = require("../build/luautest/shared/Logic/Chart")
local Buildings = require("../build/luautest/shared/Data/Buildings")
local Street = require("../build/luautest/shared/Data/Street")
local Util = require("../build/luautest/shared/Logic/Util")
local Skills = require("../build/luautest/shared/Data/Skills")

local Career = {}

local NODE_SEC = 4

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
local function plan(p: any, away: { [string]: boolean })
	local r = Island.rates(p, away)
	local ex = Island.expandCost(p.tier)
	if ex and p.shells >= ex.shells and p.wood >= ex.wood then
		Island.expand(p)
		return
	end
	-- saving up for the next tier once the village is going (its shells and its wood)
	local saving = ex ~= nil and #p.folk >= 4 * p.tier and (p.shells < ex.shells or p.wood < ex.wood)
	local wants: { string } = {}
	if Island.beds(p) <= #p.folk and #p.folk < Tuning.FolkMax then
		table.insert(wants, "home")
	end
	if Island.nests(p) == 0 then
		table.insert(wants, "nest")
	end
	if r.food < 3 or p.food < 20 then
		table.insert(wants, "food")
	end
	if Island.nests(p) <= #p.pals then
		table.insert(wants, "nest")
	end
	if r.wood < 3 + 5 * p.tier or (ex and p.wood < ex.wood and r.wood < 10 * p.tier) then
		table.insert(wants, "wood")
	end
	if countKind(p, "shop") < 1 + #p.folk // 3 then
		table.insert(wants, "shop")
	end
	for _, kind in wants do
		local id = best(p, kind)
		if id and build(p, id) then
			return
		end
		-- a cheaper one of the kind will do
		for _, d in Buildings.list do
			if d.kind == kind and build(p, d.id) then
				return
			end
		end
	end
	if p.tier >= 2 and countKind(p, "train") == 0 then
		build(p, "yard")
	end
	-- the island full (or the shells piling up): upgrade a building, food first when it runs short
	if #p.plot.placed >= Plot.limit(p.tier) or p.shells > 4000 * p.tier then
		local order = if r.food < 5 then { "food", "shop", "wood" } else { "shop", "food", "wood" }
		for _, kind in order do
			for i, q in p.plot.placed do
				local d = Buildings.byId[q.id]
				local cost = Plot.upgradeCost(q)
				if d and d.kind == kind and cost and p.shells >= cost.shells and p.wood >= cost.wood and not (saving and (p.shells - cost.shells < (ex :: any).shells or p.wood - cost.wood < (ex :: any).wood)) then
					Plot.upgrade(p, i)
					return
				end
			end
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

-- The party: the captain and the three strongest villagers or driftlings.
local function party(p: any): { string }
	local list: { { key: string, lvl: number } } = {}
	for _, v in p.folk do
		table.insert(list, { key = "v" .. v.id, lvl = v.lvl })
	end
	for _, x in p.pals do
		table.insert(list, { key = "p" .. x.id, lvl = x.lvl })
	end
	table.sort(list, function(a, b)
		return a.lvl > b.lvl
	end)
	local out = {}
	for i = 1, math.min(Tuning.PartyMax, #list) do
		table.insert(out, list[i].key)
	end
	return out
end

local function power(p: any, keys: { string }): number
	local s = 0
	for _, k in { "f", table.unpack(keys) } do
		local f = Expedition.fighter(p, k)
		if f then
			s += f.maxHp * 0.25 + f.atk + f.def * 0.5
		end
	end
	return s
end

-- What a party of four at an island's guardian would need (a rough match of its foes).
local function needed(lvl: number): number
	return (30 * 0.25 + 8 + 2.5) * (1 + Tuning.LevelGrow * (lvl + 1)) * 2.6
end

-- The island to sail to (the sea chart): the highest-level one in the boat's range the party looks strong enough for
-- (less after defeats), one not charted yet first (its whole reward), else a charted one again (half); the nearest
-- when none looks safe.
local function pickIsle(p: any, keys: { string }, fails: number): number
	local can = power(p, keys)
	local best, bestCharted = nil, nil
	for _, c in Chart.islands(p.sea) do
		if Chart.reachable(p, c.id) and needed(c.lvl + 2 * fails) <= can then
			if not Chart.charted(p, c.id) then
				if best == nil or c.lvl > best.lvl then
					best = c
				end
			elseif bestCharted == nil or c.lvl > bestCharted.lvl then
				bestCharted = c
			end
		end
	end
	local pick = best or bestCharted
	return if pick then pick.id else 1
end

-- Whether a bigger boat would help: nothing new the party can take on is left in reach, and the next range holds
-- islands it could.
local function wantsBoat(p: any, keys: { string }): boolean
	if Chart.boatCost(p.boat) == nil then
		return false
	end
	local can = power(p, keys)
	local farther = false
	for _, c in Chart.islands(p.sea) do
		local ok = needed(c.lvl) <= can
		if ok and Chart.reachable(p, c.id) and not Chart.charted(p, c.id) then
			return false
		end
		if ok and c.dist <= Chart.radius(p.boat + 1) and c.dist > Chart.radius(p.boat) then
			farther = true
		end
	end
	return farther
end

function Career.play(seed: number, seconds: number, opts: Opts?)
	local o: Opts = opts or {}
	local log = o.log
	local p = Schema.default(0, seed)
	local rng = Util.newRng(seed * 7 + 1)
	local dayClock = 0
	local exp: any = nil
	local busyUntil = 0
	local nextTrip = 120
	local fails = 0
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
		local away = Expedition.away(exp)
		Island.step(p, 1, away)
		dayClock += 1
		if dayClock >= Tuning.TurnSeconds then
			dayClock -= Tuning.TurnSeconds
			local news = Island.turn(p, rng, away)
			if news.movedIn then
				mark("villager", t)
			end
		end
		if t % 5 == 0 then
			plan(p, away)
			-- a bigger boat when nothing new is left in reach (not while it is away)
			local bc = Chart.boatCost(p.boat)
			if exp == nil and bc and p.shells >= bc.shells and p.wood >= bc.wood and wantsBoat(p, party(p)) then
				Chart.upgradeBoat(p)
				mark("boat" .. p.boat, t)
			end
		end
		for k = 2, p.tier do
			mark("tier" .. k, t)
		end
		-- the expedition
		if exp == nil and t >= nextTrip then
			local keys = party(p)
			local ok, e = Chart.sail(p, pickIsle(p, keys, fails), keys)
			if ok then
				exp = e
				busyUntil = t + NODE_SEC
			end
			nextTrip = t + 60
		elseif exp and t >= busyUntil then
			local e = exp
			if e.over then
				Expedition.home(p, e)
				if e.over == "won" then
					for _, l in { 1, 5, 10, 16, 23 } do
						if e.isle.lvl >= l then
							mark("guardian" .. l, t)
						end
					end
					fails = 0
				elseif e.over == "lost" then
					fails += 1
				end
				exp = nil
				nextTrip = t + 90
			elseif e.battle then
				local b = e.battle
				b.paused = false
				local hp, max = 0, 0
				for _, f in e.party do
					hp += f.hp
					max += f.maxHp
				end
				local data: any = nil
				if not b.boss and hp < max * 0.25 then
					local _, d = Expedition.flee(p, e, rng)
					data = d
				elseif not b.boss and Expedition.room(p) and e.snacks > 0 and rng:chance(0.3) then
					for _, f in b.foes do
						local wanted = #p.pals < 6 or (f.sp ~= nil and (p.seen[f.sp] or 0) < 2)
						if f.hp > 0 and f.hp < f.maxHp * 0.5 and wanted then
							local _, d = Expedition.snack(p, e, f.key, rng)
							data = d
							break
						end
					end
				end
				if data == nil and b.sp >= 3 then
					-- a skill the points cover: a mend for the most hurt, else the first that strikes
					local hurt: any = nil
					for _, f in e.party do
						if f.hp > 0 and (hurt == nil or f.hp / f.maxHp < hurt.hp / hurt.maxHp) then
							hurt = f
						end
					end
					for _, f in e.party do
						if f.hp > 0 and data == nil then
							for _, d in Skills.known(Skills.lineOf(f.kind, f.skill), f.lvl) do
								if d.cost <= b.sp and data == nil then
									local tgt: string? = nil
									if d.target == "ally" and hurt and hurt.hp < hurt.maxHp * 0.6 then
										tgt = hurt.key
									elseif d.target == "foe" then
										for _, w in b.foes do
											if w.hp > 0 then
												tgt = w.key
											end
										end
									end
									if d.target == "none" or tgt then
										local ok, out = Expedition.skill(p, e, f.key, d.id, tgt, rng)
										if ok then
											data = out
										end
									end
								end
							end
						end
					end
				end
				if e.battle then
					data = Expedition.tick(p, e, 1, rng) or data
				end
				if data and data.friend then
					mark("driftling", t)
				end
				-- (islands never end: this player sails home after a guardian)
				if data and data.reward then
					e.over = "won"
				end
				busyUntil = t + 1
			else
				-- heading home early when hurt
				local hp, max = 0, 0
				for _, f in e.party do
					hp += f.hp
					max += f.maxHp
				end
				if hp < max * 0.3 and e.nodes[e.node + 1] ~= "rest" then
					e.over = "home"
				else
					Expedition.next(p, e, rng)
				end
				busyUntil = t + NODE_SEC
			end
		end
		if t % 600 == 0 then
			local r = Island.rates(p, Expedition.away(exp))
			local row = { t = t, shells = p.shells, food = p.food, wood = p.wood, folk = #p.folk, pals = #p.pals, tier = p.tier, islets = p.islets, boat = p.boat, cap = p.cap.lvl, pieces = #p.plot.placed, charm = Island.charm(p), shellRate = r.shells, foodRate = r.food, woodRate = r.wood }
			table.insert(timeline, row)
			say(string.format("%3dmin shells %d (+%.0f/d) food %d (%+.0f/d) wood %d (+%.0f/d) tier %d pieces %d folk %d pals %d islets %d boat %d cap %d charm %d", t // 60, math.floor(p.shells), r.shells, math.floor(p.food), r.food, math.floor(p.wood), r.wood, p.tier, #p.plot.placed, #p.folk, #p.pals, p.islets, p.boat, p.cap.lvl, Island.charm(p)))
		end
	end
	return { profile = p, timeline = timeline, first = first }
end

return Career
