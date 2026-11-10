--!strict
-- Expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): the captain and up to Tuning.PartyMax villagers or
-- driftlings sail from the island's dock to an open islet (Data/Islets), walk its path a node at a time, battle its
-- driftlings (Logic/Battle), befriend some with treats, and sail home with what they gathered. Pure; the server keeps
-- the expedition in the session (it ends, the loot kept, when the player leaves). Those away neither work nor eat.
--   start(p, islet, members) -> Expedition    (members: "v<id>" / "p<id>"; each of the party takes Tuning.Supplies food)
--   next(p, e, rng)                           (the next node: loot, a chest, a rest, or a battle)
--   act(p, e, act, target, rng)               (a battle round; a win shares xp, a beaten guardian opens the next islet)
--   home(p, e)                                (back on the island: the loot is added, half of it after a defeat)
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Islets = require(script.Parent.Parent.Data.Islets)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Battle = require(script.Parent.Battle)
local Island = require(script.Parent.Island)

type Profile = Types.Profile
type Expedition = Types.Expedition
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

-- The wild driftlings' level at a node.
function Expedition.levelAt(islet: number, node: number): number
	local def = Islets.list[islet]
	return (if def then def.lvl else 1) + (node - 1) // 3
end

function Expedition.start(p: Profile, islet: number, members: { string }): (boolean, any)
	local def = Islets.list[islet]
	if def == nil then
		return false, "bad_payload" :: ErrCode
	end
	if islet > p.islets + 1 then
		return false, "locked" :: ErrCode
	end
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
	local done = table.create(#def.nodes, false)
	done[1] = true
	local e: Expedition = {
		islet = islet,
		node = 1,
		nodes = table.clone(def.nodes),
		done = done,
		party = party,
		loot = { shells = 0, food = 0, wood = 0 },
		battle = nil,
		befriended = {},
		over = nil,
	}
	if p.tut == 3 then
		p.tut = 4
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
	local def = Islets.list[e.islet]
	e.node += 1
	e.done[e.node] = true
	local kind = e.nodes[e.node]
	local out: { [string]: any } = { kind = kind, node = e.node }
	if kind == "loot" then
		local food, wood = vary(rng, def.loot.food), vary(rng, def.loot.wood)
		e.loot.food += food
		e.loot.wood += wood
		out.food, out.wood = food, wood
	elseif kind == "chest" then
		local shells = vary(rng, def.loot.shells)
		e.loot.shells += shells
		out.shells = shells
	elseif kind == "rest" then
		for _, f in e.party do
			f.hp = math.min(f.maxHp, f.hp + math.ceil(f.maxHp * Tuning.RestHeal))
		end
	elseif kind == "wild" or kind == "boss" then
		local lvl = Expedition.levelAt(e.islet, e.node)
		local foes: { Fighter } = {}
		if kind == "boss" then
			table.insert(foes, Battle.wild(def.boss, lvl + 2, 1, true, def.bossName))
			if e.islet >= 2 then
				table.insert(foes, Battle.wild(def.wild[rng:int(1, #def.wild)], lvl, 2, false))
			end
		else
			local n = rng:int(1, math.min(3, 1 + e.islet))
			for i = 1, n do
				table.insert(foes, Battle.wild(def.wild[rng:int(1, #def.wild)], lvl + rng:int(0, 1), i, false))
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
			local def = Islets.list[e.islet]
			local first = e.islet > p.islets
			local reward = if first then def.reward else math.floor(def.reward / 2)
			e.loot.shells += reward
			out.reward = reward
			out.first = first
			if first then
				p.islets = e.islet
			end
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
