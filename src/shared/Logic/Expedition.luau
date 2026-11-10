--!strict
-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): the captain and up to Tuning.PartyMax villagers or
-- driftlings sail from the island's pier to an island of the sea chart (Logic/Chart: its place sets its level, its
-- seed what it holds; `chart` makes it up: its kind from Data/Islets, its name, driftlings, path and loot),
-- walk its path a node at a time, battle its driftlings (Logic/Battle), befriend some with treats, and sail home
-- with what they gathered. Pure; the server keeps the expedition in the session (it ends, the loot kept, when the
-- player leaves). Those away neither work nor eat.
--   chart(lvl, seed) -> Isle                   (the island: the same seed and level make the same island)
--   start(p, isle, members) -> Expedition      (the island from Logic/Chart; members: "v<id>" / "p<id>"; each of the
--                                               party takes Tuning.Supplies food)
--   next(p, e, rng)                            (the next node: loot, a chest, a rest, or a battle: timed, paused)
--   tick(p, e, dt, rng) -> out?                (the battle runs on dt seconds; what happened, if anything: a win
--                                               shares xp, a beaten guardian charts the island)
--   snack(p, e, target, rng) / skill(p, e, who, id, target, rng) / flee(p, e, rng)
--                                              (the player's moves in a battle) / pause(e, on)
--   home(p, e)                                 (back on the island: the loot is added, half of it after a defeat)
--   snacksFor(p), upgradePouch(p)              (snacks an expedition by the pouch's level; a bigger pouch)
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Islets = require(script.Parent.Parent.Data.Islets)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Battle = require(script.Parent.Battle)
local Island = require(script.Parent.Island)
local Util = require(script.Parent.Util)

type Profile = Types.Profile
type Expedition = Types.Expedition
type Isle = Types.Isle
type Fighter = Types.Fighter
type Rng = Types.Rng
type ErrCode = Types.ErrCode

local Expedition = {}

local function villager(p: Profile, id: number): Types.Villager?
	for _, v in p.folk do
		if v.id == id then
			return v
		end
	end
	return nil
end

local function pal(p: Profile, id: number): Types.Pal?
	for _, x in p.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end

-- The fighter for a party key (as the profile has them now), or nil.
function Expedition.fighter(p: Profile, key: string): Fighter?
	if key == "f" then
		return Battle.founder(p)
	end
	local kind, id = string.match(key, "^([vp])(%d+)$")
	local n = tonumber(id)
	if kind == "v" and n then
		local v = villager(p, n)
		return if v then Battle.villager(v) else nil
	elseif kind == "p" and n then
		local x = pal(p, n)
		return if x then Battle.pal(x) else nil
	end
	return nil
end

-- The keys of those away (Island.rates leaves them out).
function Expedition.away(e: Expedition?): { [string]: boolean }
	local out: { [string]: boolean } = {}
	if e then
		for _, f in e.party do
			out[f.key] = true
		end
	end
	return out
end

function Expedition.supplies(n: number): number
	return Tuning.Supplies * n
end

------------------------------------------------------------------ the islands at sea
-- The kinds of island (Data/Islets ids) that can turn up at a level.
function Expedition.kindsAt(lvl: number): { number }
	local out: { number } = {}
	for _, d in Islets.list do
		if d.lvl <= lvl then
			table.insert(out, d.id)
		end
	end
	return out
end

-- The species that can live on an island of a level (every kind open at it).
function Expedition.speciesAt(lvl: number): { string }
	local out: { string } = {}
	for _, k in Expedition.kindsAt(lvl) do
		for _, sp in Islets.list[k].wild do
			table.insert(out, sp)
		end
	end
	return out
end

-- An island never ends (GAME_DESIGN 7: "make all islands infinite, with monsters scaling in difficulty every level and
-- bosses every few stages"): after the landing its stages come in blocks of Tuning.BossEvery, the last of each a
-- guardian; a block's stops (battles, loot, chests, maybe a rest late on; at least three battles) come from the island's
-- seed and the block's number, so the same island is the same island every time, as far as anyone goes.
local function block(seed: number, b: number): { string }
	local rng = Util.newRng(Util.hash32(seed + b * 7919) + 17)
	local n = Tuning.BossEvery - 1
	local restAt = if b > 0 or rng:next() < 0.6 then n - rng:int(0, 1) else 0
	local mid: { string } = {}
	for i = 1, n do
		if i == restAt then
			mid[i] = "rest"
		else
			local r = rng:next()
			mid[i] = if r < 0.55 then "wild" elseif r < 0.8 then "loot" else "chest"
		end
	end
	local function wilds(): number
		local c = 0
		for _, k in mid do
			if k == "wild" then
				c += 1
			end
		end
		return c
	end
	local guard = 0
	while wilds() < 3 and guard < 50 do
		guard += 1
		local i = rng:int(1, n)
		if mid[i] ~= "rest" then
			mid[i] = "wild"
		end
	end
	table.insert(mid, "boss")
	return mid
end

-- The island for a level and a seed: its kind (one of those open at the level), a name of its kind's words, two of
-- its kind's driftlings and one that strayed in from any open kind, a guardian (one of its own, titled), what its
-- loot and chests hold and the guardian's reward (Tuning.Isle*). Its path comes from the same seed (`nodesOf`).
function Expedition.chart(lvl: number, seed: number): Isle
	lvl = math.clamp(math.floor(lvl), 1, Tuning.LevelMax)
	local rng = Util.newRng(seed)
	local kinds = Expedition.kindsAt(lvl)
	local kind = kinds[rng:int(1, #kinds)]
	local def = Islets.list[kind]
	local first = def.first[rng:int(1, #def.first)]
	local last = def.last[rng:int(1, #def.last)]
	if string.lower(first) == string.lower(last) then
		last = def.last[(table.find(def.last, last) or 1) % #def.last + 1]
	end
	local own = table.clone(def.wild)
	Util.shuffle(rng, own)
	local wild = { own[1], own[2] }
	local strays: { string } = {}
	for _, sp in Expedition.speciesAt(lvl) do
		if sp ~= own[1] and sp ~= own[2] then
			table.insert(strays, sp)
		end
	end
	table.insert(wild, strays[rng:int(1, #strays)])
	local boss = own[rng:int(1, 2)]
	local bd = Creatures.byId[boss]
	local title = Islets.titles[rng:int(1, #Islets.titles)]
	return {
		seed = seed,
		lvl = lvl,
		kind = kind,
		name = first .. " " .. last,
		wild = wild,
		boss = boss,
		bossName = title .. " " .. (if bd then bd.name else boss),
		loot = {
			food = math.floor(Tuning.IsleFoodBase + Tuning.IsleFoodLvl * lvl + 0.5),
			wood = math.floor(Tuning.IsleWoodBase + Tuning.IsleWoodLvl * lvl + 0.5),
			shells = math.floor(Tuning.IsleChestBase + Tuning.IsleChestLvl2 * lvl * lvl + 0.5),
		},
		reward = math.floor(Tuning.IsleRewardBase + Tuning.IsleRewardLvl2 * lvl * lvl + 0.5),
	}
end

-- The island's path as far as `count` nodes (at least the landing and its first block): node 1 the landing, node
-- 1 + k x BossEvery the k-th guardian.
function Expedition.nodesTo(isle: Isle, count: number?): { string }
	local out = { "start" }
	local b = 0
	repeat
		for _, k in block(isle.seed, b) do
			table.insert(out, k)
		end
		b += 1
	until #out >= (count or 0)
	return out
end

-- The first block (the landing to the first guardian); an expedition's path grows a block at a time.
function Expedition.nodesOf(isle: Isle): { string }
	return Expedition.nodesTo(isle, 0)
end

-- The stage of a node (the landing is stage 0) and the guardian a node holds (1 the first, 0 none).
function Expedition.stageOf(node: number): number
	return math.max(0, node - 1)
end
function Expedition.guardianAt(node: number): number
	local st = Expedition.stageOf(node)
	return if st > 0 and st % Tuning.BossEvery == 0 then st // Tuning.BossEvery else 0
end

-- The wild driftlings' level at a node: a level under the island's at the first stage, StageLvl more every stage
-- after it (without end: past the captain's own levels); and their strength's boost there (StageBoost a stage).
function Expedition.levelAt(isle: Isle, node: number): number
	return math.max(1, isle.lvl - 1 + math.floor(math.max(0, Expedition.stageOf(node) - 1) * Tuning.StageLvl))
end
function Expedition.boostAt(node: number): number
	return 1 + Tuning.StageBoost * math.max(0, Expedition.stageOf(node) - 1)
end

-- The party's outlook for the fight under way, or else for the next stop when it is a fight (its likely foes: two of
-- the island's wild ones at that stage, or its guardian and a friend); nil when no fight is next.
function Expedition.risk(e: Expedition): Battle.Forecast?
	if e.battle then
		return Battle.forecast(e.party, e.battle.foes)
	end
	local isle = e.isle
	local nodes = if e.node + 1 <= #e.nodes then e.nodes else Expedition.nodesTo(isle, e.node + 1)
	local kind = nodes[e.node + 1]
	if kind ~= "wild" and kind ~= "boss" then
		return nil
	end
	local node = e.node + 1
	local lvl, boost = Expedition.levelAt(isle, node), Expedition.boostAt(node)
	local foes: { Fighter } = {}
	if kind == "boss" then
		table.insert(foes, Battle.wild(isle.boss, lvl + 1, 1, true, isle.bossName, boost))
		if isle.lvl >= 4 or Expedition.guardianAt(node) > 1 then
			table.insert(foes, Battle.wild(isle.wild[1], lvl, 2, false, nil, boost))
		end
	else
		for i = 1, if isle.lvl >= 3 then 2 else 1 do
			table.insert(foes, Battle.wild(isle.wild[i], lvl, i, false, nil, boost))
		end
	end
	return Battle.forecast(e.party, foes)
end

-- The n-th guardian's reward (the first's is the island's: halved when the island was charted before).
function Expedition.rewardOf(isle: Isle, n: number): number
	return math.floor(isle.reward * (1 + Tuning.BossRewardGrow * math.max(0, n - 1)) + 0.5)
end

-- Snacks an expedition takes (GAME_DESIGN 7: "only allowed to use snacks 5 times an expedition, which can be
-- upgraded to 30"): Tuning.SnackBase a pouch level.
function Expedition.snacksFor(p: Profile): number
	return Tuning.SnackBase * math.clamp(p.pouch or 1, 1, #Tuning.PouchCost)
end

-- A bigger snack pouch (the next level's price in shells and wood). Returns its new level.
function Expedition.upgradePouch(p: Profile): (boolean, any)
	local lvl = math.clamp(p.pouch or 1, 1, #Tuning.PouchCost)
	if lvl >= #Tuning.PouchCost then
		return false, "max" :: ErrCode
	end
	local cost = Tuning.PouchCost[lvl + 1]
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < cost.wood then
		return false, "wood" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	p.pouch = lvl + 1
	return true, { pouch = p.pouch, snacks = Expedition.snacksFor(p) }
end

-- Set out for an island (Logic/Chart.sail checks it is on the chart and in the boat's range).
function Expedition.start(p: Profile, isle: Isle, members: { string }): (boolean, any)
	if #members > Tuning.PartyMax then
		return false, "full" :: ErrCode
	end
	local party: { Fighter } = { Battle.founder(p) }
	local seen: { [string]: boolean } = { f = true }
	for _, key in members do
		if seen[key] then
			return false, "bad_payload" :: ErrCode
		end
		seen[key] = true
		local f = Expedition.fighter(p, key)
		if f == nil then
			return false, "not_found" :: ErrCode
		end
		table.insert(party, f)
	end
	local need = Expedition.supplies(#party)
	if p.food < need then
		return false, "food" :: ErrCode
	end
	p.food -= need
	local nodes = Expedition.nodesOf(isle)
	local done = table.create(#nodes, false)
	done[1] = true
	local e: Expedition = {
		isle = isle,
		node = 1,
		nodes = nodes,
		done = done,
		party = party,
		loot = { shells = 0, food = 0, wood = 0 },
		battle = nil,
		befriended = {},
		snacks = Expedition.snacksFor(p),
		over = nil,
	}
	if p.tut == 5 then
		p.tut = 6
	end
	return true, e
end

local function vary(rng: Rng, n: number): number
	return math.max(1, math.floor(n * (0.75 + 0.5 * rng:next()) + 0.5))
end

-- The next node of the path: what it held.
function Expedition.next(p: Profile, e: Expedition, rng: Rng): (boolean, any)
	if e.over then
		return false, "no_exp" :: ErrCode
	end
	if e.battle then
		return false, "in_battle" :: ErrCode
	end
	local isle = e.isle
	if e.node >= #e.nodes then
		-- the path goes on: its next block
		local more = Expedition.nodesTo(isle, #e.nodes + 1)
		for i = #e.nodes + 1, #more do
			e.nodes[i] = more[i]
			e.done[i] = false
		end
	end
	e.node += 1
	e.done[e.node] = true
	local kind = e.nodes[e.node]
	local out: { [string]: any } = { kind = kind, node = e.node }
	-- loot and chests grow with the stage
	local grow = 1 + Tuning.StageLoot * math.max(0, Expedition.stageOf(e.node) - 1)
	if kind == "loot" then
		local food, wood = vary(rng, isle.loot.food * grow), vary(rng, isle.loot.wood * grow)
		e.loot.food += food
		e.loot.wood += wood
		out.food, out.wood = food, wood
	elseif kind == "chest" then
		local shells = vary(rng, isle.loot.shells * grow)
		e.loot.shells += shells
		out.shells = shells
	elseif kind == "rest" then
		for _, f in e.party do
			f.hp = math.min(f.maxHp, f.hp + math.ceil(f.maxHp * Tuning.RestHeal))
		end
	elseif kind == "wild" or kind == "boss" then
		local lvl = Expedition.levelAt(isle, e.node)
		local boost = Expedition.boostAt(e.node)
		local foes: { Fighter } = {}
		if kind == "boss" then
			table.insert(foes, Battle.wild(isle.boss, lvl + 1, 1, true, isle.bossName, boost))
			if isle.lvl >= 4 or Expedition.guardianAt(e.node) > 1 then
				table.insert(foes, Battle.wild(isle.wild[rng:int(1, #isle.wild)], lvl, 2, false, nil, boost))
			end
		else
			local n = rng:int(1, if isle.lvl >= 3 then 3 else 2)
			for i = 1, n do
				table.insert(foes, Battle.wild(isle.wild[rng:int(1, #isle.wild)], lvl + rng:int(0, 1), i, false, nil, boost))
			end
		end
		for _, f in foes do
			local sp = f.sp :: string
			p.seen[sp] = math.max(p.seen[sp] or 0, 1)
		end
		e.battle = Battle.new(foes, kind == "boss", e.party, rng)
		out.foes = foes
	end
	return true, out
end

-- A new driftling friend from the wild one (at its level), helping where its knack is needed.
local function befriend(p: Profile, e: Expedition, foe: Fighter): Types.Pal
	local sp = foe.sp :: string
	local x: Types.Pal = { id = p.nextId, sp = sp, lvl = foe.lvl, xp = 0, work = 0 }
	p.nextId += 1
	local d = Creatures.byId[sp]
	if d then
		x.work = Island.freeJob(p, d.knack)
	end
	table.insert(p.pals, x)
	p.seen[sp] = 2
	p.stats.befriended += 1
	table.insert(e.befriended, sp)
	return x
end

-- Room for one more driftling.
function Expedition.room(p: Profile): boolean
	return #p.pals < math.min(Tuning.PalsMax, Island.nests(p))
end

-- The party's xp after a win, onto the profile's captain, villagers and driftlings (their fighters grow with them).
local function share(p: Profile, e: Expedition, xp: number): { [string]: number }
	local ups: { [string]: number } = {}
	local each = math.floor(xp / math.max(1, #e.party) + 0.5)
	for i, f in e.party do
		local who: { lvl: number, xp: number }? = nil
		if f.key == "f" then
			who = p.cap
		else
			local kind, id = string.match(f.key, "^([vp])(%d+)$")
			local n = tonumber(id) or 0
			if kind == "v" then
				who = villager(p, n)
			elseif kind == "p" then
				who = pal(p, n)
			end
		end
		if who then
			local up = Island.gain(who, each)
			if up > 0 then
				ups[f.key] = up
				local fresh = Expedition.fighter(p, f.key)
				if fresh then
					fresh.hp = math.max(1, f.hp + (fresh.maxHp - f.maxHp))
					fresh.charge = f.charge
					fresh.gauge = f.gauge
					e.party[i] = fresh
				end
			end
		end
	end
	return ups
end

-- What a battle's events came to: a befriended wild one joins the island; a win shares the xp and shells (a beaten
-- guardian charts the island: its whole reward the first time, half on later trips; each later one pays more), the
-- beaten getting up with a quarter of their health; a defeat ends the expedition. `out` gets the events, the result
-- and what came of them, the snacks left, and the timers as they stand while it goes on (Battle.gauges).
local function settle(p: Profile, e: Expedition, b: Types.Battle, events: { any }, result: string?): { [string]: any }
	local out: { [string]: any } = { events = events, result = result, snacks = e.snacks }
	for _, f in b.foes do
		local fa: any = f
		if fa.friend and not fa.joined then
			fa.joined = true
			out.friend = befriend(p, e, f)
		end
	end
	if result == "win" then
		local xp, shells = 0, 0
		for _, f in b.foes do
			if not (f :: any).friend then
				xp += f.lvl * Tuning.XpPerFoe
				shells += f.lvl * 3
			end
		end
		e.loot.shells += shells
		out.xp = xp
		out.shells = shells
		out.ups = share(p, e, xp)
		-- the beaten get up again with a quarter of their health
		for _, f in e.party do
			if f.hp <= 0 then
				f.hp = math.max(1, math.floor(f.maxHp * 0.25))
			end
		end
		p.stats.battles += 1
		e.battle = nil
		if b.boss then
			-- a guardian beaten: the first charts the island (its whole reward the first time, half on later trips),
			-- each later one pays more; the path goes on (the party sails home when it likes)
			local n = math.max(1, Expedition.guardianAt(e.node))
			local id = e.isle.id
			local first = n == 1 and (id == nil or table.find(p.chart, id) == nil)
			local reward = Expedition.rewardOf(e.isle, n)
			if n == 1 and not first then
				reward = math.floor(reward / 2)
			end
			e.loot.shells += reward
			out.reward = reward
			out.first = first
			out.guardian = n
			if first then
				if id then
					table.insert(p.chart, id)
				end
				p.islets += 1
			end
			out.charted = p.islets
			p.stats.cleared += 1
			e.beaten = math.max(e.beaten or 0, n)
		end
	elseif result == "lose" then
		e.battle = nil
		e.over = "lost"
	elseif result == "fled" then
		e.battle = nil
	else
		local gs = Battle.gauges(e.party, b)
		out.g, out.lock, out.paused, out.sp, out.crowd = gs.g, gs.lock, gs.paused, gs.sp, gs.crowd
	end
	return out
end

-- The battle runs on `dt` seconds (the server's step). Returns what happened (settle's out) or nil when nothing did.
function Expedition.tick(p: Profile, e: Expedition, dt: number, rng: Rng): { [string]: any }?
	local b = e.battle
	if e.over or b == nil or b.paused then
		return nil
	end
	local events, result = Battle.step(e.party, b, dt, rng)
	if #events == 0 and result == nil then
		return nil
	end
	return settle(p, e, b, events, result)
end

-- A snack thrown at a wild one (the leader's timer starts again; one of the trip's snacks; it needs a free nest).
function Expedition.snack(p: Profile, e: Expedition, target: string?, rng: Rng): (boolean, any)
	local b = e.battle
	if e.over or b == nil then
		return false, "no_exp" :: ErrCode
	end
	if b.boss then
		return false, "blocked" :: ErrCode
	end
	if e.snacks <= 0 then
		return false, "no_snacks" :: ErrCode
	end
	if not Expedition.room(p) then
		return false, "no_room" :: ErrCode
	end
	local ok, events, result = Battle.snack(e.party, b, target, rng)
	if not ok then
		return false, events
	end
	e.snacks -= 1
	return true, settle(p, e, b, events, result)
end

-- A learnt skill (Data/Skills) used by one of the party, paid in the battle's skill points.
function Expedition.skill(p: Profile, e: Expedition, who: string, id: string, target: string?, rng: Rng): (boolean, any)
	local b = e.battle
	if e.over or b == nil then
		return false, "no_exp" :: ErrCode
	end
	local ok, events, result = Battle.useSkill(e.party, b, who, id, target, rng)
	if not ok then
		return false, events
	end
	return true, settle(p, e, b, events, result)
end

-- Run from a wild ones' battle (not from a guardian).
function Expedition.flee(p: Profile, e: Expedition, rng: Rng): (boolean, any)
	local b = e.battle
	if e.over or b == nil then
		return false, "no_exp" :: ErrCode
	end
	local ok, events, result = Battle.flee(e.party, b, rng)
	if not ok then
		return false, events
	end
	return true, settle(p, e, b, events, result)
end

-- Pause the battle (its wild ones landing, a snack being aimed, the screen closed) or let it run. Returns the timers.
function Expedition.pause(e: Expedition, on: boolean): (boolean, any)
	local b = e.battle
	if e.over or b == nil then
		return false, "no_exp" :: ErrCode
	end
	b.paused = on
	return true, Battle.gauges(e.party, b)
end

-- Back on the island: the loot added (half after a defeat). Returns what came home.
function Expedition.home(p: Profile, e: Expedition): { shells: number, food: number, wood: number }
	local k = if e.over == "lost" then 0.5 else 1
	local got = { shells = math.floor(e.loot.shells * k), food = math.floor(e.loot.food * k), wood = math.floor(e.loot.wood * k) }
	p.shells += got.shells
	p.food += got.food
	p.wood += got.wood
	p.stats.earned += got.shells
	e.over = e.over or "home"
	return got
end

return Expedition
