--!strict
-- Battles on expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): the party (the captain and up to three villagers or
-- driftlings) against one to three wild driftlings, turn by turn. Pure: every random draw comes from the Rng argument.
-- A round: the player picks what the party does ("fight", "guard", "treat" a wild one with food, or "flee"), then
-- everyone acts in speed order (the party first on a tie): a fighter attacks (the party the weakest foe, a foe a
-- random member) or, every Tuning.SkillEvery actions, uses its skill. Guarding takes Tuning.GuardTake of the damage
-- and mends a little; a treat may befriend the wild one (its trust, more the more hurt it is, less the higher its
-- level), which then leaves the battle; a guardian can't be befriended or fled from.
--   damage = max(1, atk x (0.85 .. 1.15) - def / 2), a skill's times that; stats grow Tuning.LevelGrow a level
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Util = require(script.Parent.Util)

type Fighter = Types.Fighter
type Battle = Types.Battle
type Rng = Types.Rng

local Battle = {}

export type Base = { hp: number, atk: number, def: number, spd: number, skill: string }
-- One thing that happened, in order (the client plays them back):
--   { t = "hit", by, to, dmg, skill?, ko? } { t = "heal", by, to, amt } { t = "shield", by } { t = "rally", by }
--   { t = "guard" } { t = "treat", to, ok } { t = "flee", ok }
export type Event = { [string]: any }

Battle.FOUNDER = { hp = 30, atk = 8, def = 5, spd = 6, skill = "rally" } :: Base
local VILLAGER_SKILLS = { "bash", "heal", "shell" }

-- A villager's level-1 stats, the same every time for their seed.
function Battle.villagerBase(seed: number): Base
	local r = Util.newRng(seed * 31 + 7)
	return { hp = r:int(22, 30), atk = r:int(5, 8), def = r:int(3, 6), spd = r:int(4, 8), skill = VILLAGER_SKILLS[r:int(1, #VILLAGER_SKILLS)] }
end

function Battle.speciesBase(sp: string): Base
	local d = Creatures.byId[sp]
	if d == nil then
		return { hp = 10, atk = 4, def = 3, spd = 4, skill = "bash" }
	end
	return { hp = d.hp, atk = d.atk, def = d.def, spd = d.spd, skill = d.skill }
end

function Battle.grow(v: number, lvl: number): number
	return math.floor(v * (1 + Tuning.LevelGrow * (math.max(1, lvl) - 1)) + 0.5)
end

local function make(key: string, name: string, kind: string, base: Base, lvl: number, boost: number?): Fighter
	local k = boost or 1
	local hp = math.floor(Battle.grow(base.hp, lvl) * k + 0.5)
	return {
		key = key,
		name = name,
		kind = kind,
		sp = nil,
		look = nil,
		lvl = lvl,
		hp = hp,
		maxHp = hp,
		atk = math.floor(Battle.grow(base.atk, lvl) * k + 0.5),
		def = math.floor(Battle.grow(base.def, lvl) * k + 0.5),
		spd = Battle.grow(base.spd, lvl),
		skill = base.skill,
		charge = 0,
	}
end

function Battle.founder(p: Types.Profile): Fighter
	local f = make("f", "You", "founder", Battle.FOUNDER, p.cap.lvl)
	f.look = p.founder
	return f
end

function Battle.villager(v: Types.Villager): Fighter
	local f = make("v" .. v.id, v.name, "villager", Battle.villagerBase(v.seed), v.lvl)
	f.look = v.look
	return f
end

function Battle.pal(pal: Types.Pal): Fighter
	local d = Creatures.byId[pal.sp]
	local f = make("p" .. pal.id, if d then d.name else pal.sp, "pal", Battle.speciesBase(pal.sp), pal.lvl)
	f.sp = pal.sp
	return f
end

function Battle.wild(sp: string, lvl: number, i: number, boss: boolean, name: string?): Fighter
	local d = Creatures.byId[sp]
	local f = make("w" .. i, name or (if d then d.name else sp), "wild", Battle.speciesBase(sp), lvl, if boss then Tuning.BossBoost else 1)
	f.sp = sp
	return f
end

function Battle.new(foes: { Fighter }, boss: boolean): Battle
	return { foes = foes, round = 0, boss = boss, shield = 0, foeShield = 0 }
end

function Battle.alive(list: { Fighter }): { Fighter }
	local out = {}
	for _, f in list do
		if f.hp > 0 then
			table.insert(out, f)
		end
	end
	return out
end

-- The chance a treat befriends this wild one.
function Battle.treatChance(foe: Fighter, party: { Fighter }, boss: boolean): number
	if boss or foe.sp == nil then
		return 0
	end
	local d = Creatures.byId[foe.sp :: string]
	if d == nil then
		return 0
	end
	local lv, n = 0, 0
	for _, f in party do
		lv += f.lvl
		n += 1
	end
	local avg = if n > 0 then lv / n else 1
	local hurt = 1.6 - foe.hp / math.max(1, foe.maxHp)
	local lvlK = math.clamp(1 + 0.08 * (avg - foe.lvl), 0.5, 1.5)
	return math.clamp(d.trust * hurt * lvlK, 0.03, 0.95)
end

function Battle.fleeChance(party: { Fighter }, foes: { Fighter }): number
	local function avg(list: { Fighter }): number
		local s, n = 0, 0
		for _, f in Battle.alive(list) do
			s += f.spd
			n += 1
		end
		return if n > 0 then s / n else 0
	end
	return math.clamp(Tuning.FleeBase + 0.04 * (avg(party) - avg(foes)), 0.15, 0.95)
end

local function damage(by: Fighter, to: Fighter, k: number, rng: Rng, take: number): number
	local raw = by.atk * (0.85 + 0.3 * rng:next()) * k - to.def * 0.5
	return math.max(1, math.floor(raw * take + 0.5))
end

-- One round. `act`: "fight" | "guard" | "treat" | "flee"; `target`: the wild one a treat is for. Returns the events
-- and how it ended: "win" (every foe beaten or befriended), "lose" (the party beaten), "fled", or nil (on it goes).
-- A befriended foe leaves the battle with `friend = true`.
function Battle.round(party: { Fighter }, b: Battle, act: string, target: string?, rng: Rng): ({ Event }, string?)
	local ev: { Event } = {}
	b.round += 1
	local guarding = act == "guard"
	if act == "flee" then
		local ok = not b.boss and rng:chance(Battle.fleeChance(party, b.foes))
		table.insert(ev, { t = "flee", ok = ok })
		if ok then
			return ev, "fled"
		end
	elseif act == "guard" then
		table.insert(ev, { t = "guard" })
		for _, f in Battle.alive(party) do
			f.hp = math.min(f.maxHp, f.hp + math.ceil(f.maxHp * 0.05))
		end
	elseif act == "treat" then
		local foe: Fighter? = nil
		for _, f in Battle.alive(b.foes) do
			if f.key == target then
				foe = f
			end
		end
		if foe then
			local ok = rng:chance(Battle.treatChance(foe, party, b.boss))
			table.insert(ev, { t = "treat", to = foe.key, ok = ok })
			if ok then
				foe.hp = 0
				local fa: any = foe
				fa.friend = true
				if #Battle.alive(b.foes) == 0 then
					return ev, "win"
				end
			end
		end
	end
	-- everyone acts in speed order
	local order: { Fighter } = {}
	for _, f in Battle.alive(party) do
		table.insert(order, f)
	end
	for _, f in Battle.alive(b.foes) do
		table.insert(order, f)
	end
	table.sort(order, function(a: Fighter, c: Fighter): boolean
		if a.spd ~= c.spd then
			return a.spd > c.spd
		end
		return a.kind ~= "wild" and c.kind == "wild"
	end)
	for _, f in order do
		if f.hp <= 0 then
			continue
		end
		local mine = f.kind ~= "wild"
		local allies = if mine then party else b.foes
		local enemies = Battle.alive(if mine then b.foes else party)
		if #enemies == 0 then
			break
		end
		if mine and (guarding or (act == "treat" and f.kind == "founder") or act == "flee") then
			continue
		end
		local function take(to: Fighter): number
			local k = 1
			if to.kind ~= "wild" then
				k = (if guarding then Tuning.GuardTake else 1) * (if b.shield > 0 then Tuning.ShieldTake else 1)
			elseif b.foeShield > 0 then
				k = Tuning.ShieldTake
			end
			return k
		end
		local function hit(to: Fighter, mult: number, skill: string?)
			local dmg = damage(f, to, mult, rng, take(to))
			to.hp = math.max(0, to.hp - dmg)
			table.insert(ev, { t = "hit", by = f.key, to = to.key, dmg = dmg, skill = skill, ko = to.hp <= 0 })
		end
		local function pick(): Fighter
			if mine then
				local best = enemies[1]
				for _, e in enemies do
					if e.hp < best.hp then
						best = e
					end
				end
				return best
			end
			return enemies[rng:int(1, #enemies)]
		end
		f.charge += 1
		local skill = if f.charge >= Tuning.SkillEvery then f.skill else nil
		if skill then
			f.charge = 0
		end
		if skill == "bash" then
			hit(pick(), 1.8, "bash")
		elseif skill == "quick" then
			hit(pick(), 1, "quick")
			local again = Battle.alive(if mine then b.foes else party)
			if #again > 0 then
				enemies = again
				hit(pick(), 1, "quick")
			end
		elseif skill == "zap" then
			for _, e in enemies do
				hit(e, 0.6, "zap")
			end
		elseif skill == "heal" then
			local worst, wr = f, 2
			for _, a in Battle.alive(allies) do
				local r = a.hp / math.max(1, a.maxHp)
				if r < wr then
					worst, wr = a, r
				end
			end
			local amt = math.min(worst.maxHp - worst.hp, math.ceil(worst.maxHp * 0.35))
			worst.hp += amt
			table.insert(ev, { t = "heal", by = f.key, to = worst.key, amt = amt })
		elseif skill == "shell" then
			if mine then
				b.shield = 2
			else
				b.foeShield = 2
			end
			table.insert(ev, { t = "shield", by = f.key })
		elseif skill == "rally" then
			for _, a in Battle.alive(allies) do
				a.atk = math.floor(a.atk * 1.15 + 0.5)
			end
			table.insert(ev, { t = "rally", by = f.key })
		else
			hit(pick(), 1, nil)
		end
	end
	b.shield = math.max(0, b.shield - 1)
	b.foeShield = math.max(0, b.foeShield - 1)
	if #Battle.alive(b.foes) == 0 then
		return ev, "win"
	end
	if #Battle.alive(party) == 0 then
		return ev, "lose"
	end
	return ev, nil
end

return Battle
