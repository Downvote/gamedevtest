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
--   next(p, e, rng)                            (the next node: loot, a chest, a rest, or a battle)
--   act(p, e, act, target, rng)                (a battle round; a win shares xp, a beaten guardian charts the island)
--   home(p, e)                                 (back on the island: the loot is added, half of it after a defeat)
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

-- An island's path: the landing, six to nine stops (battles, loot, chests, one rest late on), the guardian.
local function path(rng: Rng, lvl: number): { string }
	local n = 6 + rng:int(0, 2) + (if lvl >= 10 then 1 else 0)
	local restAt = math.max(3, math.floor(n * 0.7 + 0.5) - rng:int(0, 1))
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
	local out = { "start" }
	for _, k in mid do
		table.insert(out, k)
	end
	table.insert(out, "boss")
	return out
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

-- The island's path of nodes (from its seed).
function Expedition.nodesOf(isle: Isle): { string }
	return path(Util.newRng(Util.hash32(isle.seed) + 17), isle.lvl)
end

-- The wild driftlings' level at a node: a level under the island's at the landing, one more every four stops.
function Expedition.levelAt(isle: Isle, node: number): number
	return math.max(1, isle.lvl - 1 + (node - 1) // 4)
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
	if e.node >= #e.nodes then
		return false, "max" :: ErrCode
	end
	local isle = e.isle
	e.node += 1
	e.done[e.node] = true
	local kind = e.nodes[e.node]
	local out: { [string]: any } = { kind = kind, node = e.node }
	if kind == "loot" then
		local food, wood = vary(rng, isle.loot.food), vary(rng, isle.loot.wood)
		e.loot.food += food
		e.loot.wood += wood
		out.food, out.wood = food, wood
	elseif kind == "chest" then
		local shells = vary(rng, isle.loot.shells)
		e.loot.shells += shells
		out.shells = shells
	elseif kind == "rest" then
		for _, f in e.party do
			f.hp = math.min(f.maxHp, f.hp + math.ceil(f.maxHp * Tuning.RestHeal))
		end
	elseif kind == "wild" or kind == "boss" then
		local lvl = Expedition.levelAt(isle, e.node)
		local foes: { Fighter } = {}
		if kind == "boss" then
			table.insert(foes, Battle.wild(isle.boss, lvl + 1, 1, true, isle.bossName))
			if isle.lvl >= 4 then
				table.insert(foes, Battle.wild(isle.wild[rng:int(1, #isle.wild)], lvl, 2, false))
			end
		else
			local n = rng:int(1, if isle.lvl >= 3 then 3 else 2)
			for i = 1, n do
				table.insert(foes, Battle.wild(isle.wild[rng:int(1, #isle.wild)], lvl + rng:int(0, 1), i, false))
			end
		end
		for _, f in foes do
			local sp = f.sp :: string
			p.seen[sp] = math.max(p.seen[sp] or 0, 1)
		end
		e.battle = Battle.new(foes, kind == "boss")
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
					e.party[i] = fresh
				end
			end
		end
	end
	return ups
end

-- A battle round (Logic/Battle). A treat costs Tuning.TreatFood and needs a free nest.
function Expedition.act(p: Profile, e: Expedition, act: string, target: string?, rng: Rng): (boolean, any)
	local b = e.battle
	if e.over or b == nil then
		return false, "no_exp" :: ErrCode
	end
	if act == "treat" then
		if b.boss then
			return false, "blocked" :: ErrCode
		end
		if p.food < Tuning.TreatFood then
			return false, "food" :: ErrCode
		end
		if not Expedition.room(p) then
			return false, "no_room" :: ErrCode
		end
		p.food -= Tuning.TreatFood
	elseif act == "flee" and b.boss then
		return false, "blocked" :: ErrCode
	end
	local events, result = Battle.round(e.party, b, act, target, rng)
	local out: { [string]: any } = { events = events, result = result }
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
			-- the first time the island is charted: its whole reward; later trips half of it
			local id = e.isle.id
			local first = id == nil or table.find(p.chart, id) == nil
			local reward = if first then e.isle.reward else math.floor(e.isle.reward / 2)
			e.loot.shells += reward
			out.reward = reward
			out.first = first
			if first then
				if id then
					table.insert(p.chart, id)
				end
				p.islets += 1
			end
			out.charted = p.islets
			p.stats.cleared += 1
			e.over = "won"
		end
	elseif result == "lose" then
		e.battle = nil
		e.over = "lost"
	elseif result == "fled" then
		e.battle = nil
	end
	return true, out
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
