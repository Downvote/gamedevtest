--!strict
-- Battles on expeditions (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): the party (the captain and up to three villagers or
-- driftlings) against one to three wild driftlings, in time (GAME_DESIGN 7: "the characters have a timer above their
-- heads ... and will attack or use its skill once a timer is done, and reset the timer"). Pure: every random draw
-- comes from the Rng argument, time from `step`'s dt.
--   Each fighter's timer (`gauge`, 0 .. 1) fills in `fillTime(f)` seconds (faster the quicker it is); full, the
--   fighter acts: attacks (the party the weakest foe, a foe a random member) or, every Tuning.SkillEvery actions, uses
--   its skill, and its timer starts again. One action at a time: while one plays (`lock`: as long as its events take
--   on screen, Battle.playTime) nobody else acts, so the screen can show it (the timers fill on meanwhile). A battle
--   starts `paused` (its foes are still landing) and pauses while the player aims a snack or a skill, or is off the
--   screen.
--   The player's moves: a snack (`snack`: the leader's timer starts again and it throws one at a wild one, which
--   catches it, and joins, as often as its trust says: more the more hurt it is, less the higher its level), a skill
--   (`useSkill`: one of the party uses a skill it has learnt (Data/Skills), paid in the party's skill points (`sp`,
--   charging Tuning.SpRate a second while the battle runs, up to Tuning.SpMax); its timer starts again), or `flee`
--   (a chance by speed; a miss starts the leader's timer again). A guardian takes no snack, and is not fled.
--   damage = max(1, atk x (0.85 .. 1.15) - def / 2), a skill's times that; stats grow Tuning.LevelGrow a level
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Creatures = require(script.Parent.Parent.Data.Creatures)
local Traits = require(script.Parent.Parent.Data.Traits)
local Skills = require(script.Parent.Parent.Data.Skills)
local Util = require(script.Parent.Util)

type Fighter = Types.Fighter
type Battle = Types.Battle
type Rng = Types.Rng

local Battle = {}

export type Base = { hp: number, atk: number, def: number, spd: number, skill: string }
-- One thing that happened, in order (the client plays them back):
--   { t = "hit", by, to, dmg, skill?, ko? } { t = "heal", by, to, amt } { t = "shield", by } { t = "rally", by }
--   { t = "treat", by, to, ok } { t = "flee", ok } and the skills' { t = "skill", by, id } (first, naming it),
--   { t = "revive", by, to, amt } { t = "haste", by } { t = "dizzy", by } (a skill's strikes are hits with its id)
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
		gauge = 0,
	}
end

-- What a driftling's passive and mutations (Data/Traits) do to its stats: health, attack and defence times
-- (1 + share), its timer's speed too (`extra`: more shares, e.g. a better home's: Logic/Island.comfort).
function Battle.fxOf(sp: string, muts: { string }?): Traits.Fx
	local d = Creatures.byId[sp]
	return Traits.sum(if d then d.passive.fx else nil, muts)
end
function Battle.applyFx(f: Fighter, fx: Traits.Fx)
	local function k(key: string): number
		return math.max(0.3, 1 + (fx[key] or 0))
	end
	f.maxHp = math.max(1, math.floor(f.maxHp * k("hp") + 0.5))
	f.hp = f.maxHp
	f.atk = math.max(1, math.floor(f.atk * k("atk") + 0.5))
	f.def = math.max(0, math.floor(f.def * k("def") + 0.5))
	f.spd = math.max(0, math.floor(f.spd * k("spd") + 0.5))
end

function Battle.founder(p: Types.Profile): Fighter
	local f = make("f", "You", "founder", Battle.FOUNDER, p.cap.lvl)
	f.look = p.founder
	return f
end

-- A villager at its level (`extra`: shares on top, e.g. its home's comfort: Logic/Island.homes).
function Battle.villager(v: Types.Villager, extra: Traits.Fx?): Fighter
	local f = make("v" .. v.id, v.name, "villager", Battle.villagerBase(v.seed), v.lvl)
	f.look = v.look
	if extra then
		Battle.applyFx(f, extra)
	end
	return f
end

-- A befriended driftling: its species' stats at its level, then its passive and mutations (`extra`: more shares on
-- top, e.g. its nest's comfort).
function Battle.pal(pal: Types.Pal, extra: Traits.Fx?): Fighter
	local d = Creatures.byId[pal.sp]
	local f = make("p" .. pal.id, if d then d.name else pal.sp, "pal", Battle.speciesBase(pal.sp), pal.lvl)
	f.sp = pal.sp
	f.muts = pal.muts
	local fx = Battle.fxOf(pal.sp, pal.muts)
	if extra then
		for key, v in extra do
			fx[key] = (fx[key] or 0) + v
		end
	end
	Battle.applyFx(f, fx)
	return f
end

-- A wild one: its species' stats at the level (a guardian's and a later stage's boosted), its passive and the
-- mutations it was born with (`muts`: Traits.roll, kept if it is befriended).
function Battle.wild(sp: string, lvl: number, i: number, boss: boolean, name: string?, boost: number?, muts: { string }?): Fighter
	local d = Creatures.byId[sp]
	local f = make("w" .. i, name or (if d then d.name else sp), "wild", Battle.speciesBase(sp), lvl, (if boss then Tuning.BossBoost else 1) * (boost or 1))
	Battle.applyFx(f, Battle.fxOf(sp, muts))
	f.sp = sp
	if muts and #muts > 0 then
		f.muts = muts
	end
	return f
end

-- A fresh battle: paused (the client lets it run once the wild ones have landed), every timer a little way in (the
-- party's from `rng` so not everyone starts together).
function Battle.new(foes: { Fighter }, boss: boolean, party: { Fighter }?, rng: Rng?): Battle
	local b: Battle = { foes = foes, acts = 0, boss = boss, shield = 0, foeShield = 0, lock = 0, paused = true, clock = 0, sp = 0 }
	for _, list in { foes, party or {} } :: { { Fighter } } do
		for _, f in list do
			f.gauge = if rng then rng:range(0, 0.3) else 0
		end
	end
	return b
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

-- Seconds for a fighter's timer to fill: Tuning.AtbTime for an average speed (AtbRef), quicker for quicker ones.
function Battle.fillTime(f: Fighter): number
	return math.clamp(Tuning.AtbTime * 2 * Tuning.AtbRef / (Tuning.AtbRef + math.max(0, f.spd)), Tuning.AtbMin, Tuning.AtbMax)
end

-- How long each event plays on screen (seconds; a strike by its move): an action holds the battle that long
-- (`playTime`, times Tuning.ActLock) so the screen keeps up.
Battle.EVENT_SECS = { attack = 0.95, bash = 1.2, quick = 0.9, zap = 0.85, heal = 0.8, shield = 0.8, rally = 0.8, treat = 1.6, flee = 0.8, skill = 0.5, revive = 1.0, haste = 0.8, dizzy = 0.8, cancel = 0.3 } :: { [string]: number }

-- How a strike plays: an auto skill's own move (bash, quick, zap), a learnt skill's (Data/Skills), else an attack.
function Battle.moveOf(skill: string?): string
	if skill == nil then
		return "attack"
	end
	if skill == "bash" or skill == "quick" or skill == "zap" then
		return skill
	end
	local d = Skills.byId[skill]
	if d and d.move ~= "cast" then
		return d.move
	end
	return "attack"
end

-- Seconds a list of events plays for, a small gap after each action.
function Battle.playTime(events: { Event }, from: number?): number
	local t = 0.15
	for i = from or 1, #events do
		local ev = events[i]
		local k = if ev.t == "hit" then Battle.moveOf(ev.skill) else ev.t
		t += Battle.EVENT_SECS[k] or 0.8
	end
	return t * Tuning.ActLock
end

-- How much slower every timer fills in this fight (at least 1): the actions the timers ask for a second (each
-- standing fighter's 1 / fillTime) times a plain attack's play time, over the share of the time actions may take
-- (Tuning.AtbShare). One action plays at a time, so a crowded fight would otherwise keep full timers waiting in line;
-- this way the fighters act as their timers fill. Both sides slow alike: the odds stay the same.
function Battle.crowd(party: { Fighter }, foes: { Fighter }): number
	local demand = 0
	for _, list in { party, foes } :: { { Fighter } } do
		for _, f in list do
			if f.hp > 0 then
				demand += 1 / Battle.fillTime(f)
			end
		end
	end
	local busy = (0.15 + Battle.EVENT_SECS.attack) * Tuning.ActLock
	return math.max(1, demand * busy / Tuning.AtbShare)
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

-- How it stands: "win" (every foe beaten or befriended), "lose" (the party beaten) or nil.
local function outcome(party: { Fighter }, b: Battle): string?
	if #Battle.alive(b.foes) == 0 then
		return "win"
	end
	if #Battle.alive(party) == 0 then
		return "lose"
	end
	return nil
end

-- One fighter acts (its timer full): its attack or, every Tuning.SkillEvery actions, its skill. Returns the action's
-- kind (Battle.LOCK's key).
local function actOne(f: Fighter, party: { Fighter }, b: Battle, rng: Rng, ev: { Event }): string
	local mine = f.kind ~= "wild"
	local allies = if mine then party else b.foes
	local enemies = Battle.alive(if mine then b.foes else party)
	if #enemies == 0 then
		return "attack"
	end
	local function take(to: Fighter): number
		if to.kind ~= "wild" then
			return if b.shield > 0 then Tuning.ShieldTake else 1
		end
		return if b.foeShield > 0 then Tuning.ShieldTake else 1
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
			b.shield = Tuning.ShieldSecs
		else
			b.foeShield = Tuning.ShieldSecs
		end
		table.insert(ev, { t = "shield", by = f.key })
	elseif skill == "rally" then
		for _, a in Battle.alive(allies) do
			a.atk = math.floor(a.atk * 1.15 + 0.5)
		end
		table.insert(ev, { t = "rally", by = f.key })
	else
		hit(pick(), 1, nil)
		return "attack"
	end
	return skill :: string
end

local SUB = 0.05 -- the step's slice (seconds): timers fill and actions start slice by slice

-- Time passes (`dt` seconds, in slices): the timers fill, one full timer at a time acts (the party first on a tie),
-- each action holding the rest while it plays. Returns what happened and how it ended ("win", "lose" or nil).
function Battle.step(party: { Fighter }, b: Battle, dt: number, rng: Rng): ({ Event }, string?)
	local ev: { Event } = {}
	if b.paused then
		return ev, nil
	end
	local left = math.max(0, dt)
	while left > 1e-9 do
		local h = math.min(left, SUB)
		left -= h
		b.clock += h
		b.shield = math.max(0, b.shield - h)
		b.foeShield = math.max(0, b.foeShield - h)
		b.sp = math.min(Tuning.SpMax, b.sp + h * Tuning.SpRate)
		-- every timer fills (an action playing too: the next is ready when it ends; slower in a crowd), one full one
		-- acts when none plays
		local ready: Fighter? = nil
		local crowd = Battle.crowd(party, b.foes)
		for _, list in { party, b.foes } :: { { Fighter } } do
			for _, f in list do
				if f.hp > 0 then
					f.gauge = math.min(1, f.gauge + h / (Battle.fillTime(f) * crowd))
					if f.gauge >= 1 and ready == nil then
						ready = f
					end
				end
			end
		end
		if b.lock > 0 then
			b.lock = math.max(0, b.lock - h)
			if b.lock <= 0 then
				b.undo = nil -- (played out: no longer cancelled by a snack)
			end
			continue
		end
		if ready then
			local f = ready :: Fighter
			f.gauge = 0
			b.acts += 1
			local first = #ev + 1
			-- how things stand before it, while it plays (a snack thrown meanwhile cancels it: Battle.snack)
			local undo: Types.Undo = { by = f.key, charge = f.charge, shield = b.shield, foeShield = b.foeShield, hp = {}, atk = {} }
			for _, list in { party, b.foes } :: { { Fighter } } do
				for _, x in list do
					undo.hp[x.key] = x.hp
					undo.atk[x.key] = x.atk
				end
			end
			actOne(f, party, b, rng, ev)
			b.lock = Battle.playTime(ev, first)
			b.undo = if b.lock > 0 then undo else nil
			local r = outcome(party, b)
			if r then
				return ev, r
			end
		end
	end
	return ev, nil
end

-- The leader (the founder), standing; nil when down.
local function leader(party: { Fighter }): Fighter?
	for _, f in party do
		if f.key == "f" and f.hp > 0 then
			return f
		end
	end
	return nil
end

-- A snack for a wild one: the leader's timer starts again and it throws; the wild one catches it (and leaves the
-- battle a friend, `friend = true`) as often as its trust says. The battle runs again. Returns (true, events, result)
-- or (false, an ErrCode).
-- A snack at the wild one `target` (GAME_DESIGN 7). Thrown while an automatic action is still playing, it cancels it
-- first ("if a snack is thrown, the attack is cancelled if it is mid attack"): everyone's health and attack, the
-- shields and the actor's count to its skill back as they stood before it (a "cancel" event with the health as it is
-- again); a wild one's cancelled attack is lost (its timer starts over: it turned to look at the snack), a party
-- member's comes back at once (its timer full). (`sure`: it befriends whatever the chance: the tips' first snack.)
function Battle.snack(party: { Fighter }, b: Battle, target: string?, rng: Rng, sure: boolean?): (boolean, any, string?)
	if b.boss then
		return false, "blocked"
	end
	local undo = if b.lock > 0 then b.undo else nil
	local function hpNow(f: Fighter): number
		return if undo and undo.hp[f.key] ~= nil then undo.hp[f.key] else f.hp
	end
	local lead: Fighter? = nil
	for _, f in party do
		if f.key == "f" and hpNow(f) > 0 then
			lead = f
		end
	end
	if lead == nil then
		return false, "blocked"
	end
	local foe: Fighter? = nil
	for _, f in b.foes do
		if f.key == target and hpNow(f) > 0 and not (f :: any).friend then
			foe = f
		end
	end
	if foe == nil then
		return false, "not_found"
	end
	local ev: { Event } = {}
	if undo then
		local back: { [string]: number } = {}
		for _, list in { party, b.foes } :: { { Fighter } } do
			for _, x in list do
				local hp, atk = undo.hp[x.key], undo.atk[x.key]
				if hp ~= nil and hp ~= x.hp then
					x.hp = hp
					back[x.key] = hp
				end
				if atk ~= nil then
					x.atk = atk
				end
				if x.key == undo.by then
					x.charge = undo.charge
					x.gauge = if x.kind == "wild" then 0 else 1
				end
			end
		end
		b.shield, b.foeShield = undo.shield, undo.foeShield
		b.undo = nil
		b.lock = 0
		table.insert(ev, { t = "cancel", by = undo.by, hp = back })
	end
	local fo = foe :: Fighter
	local ld = lead :: Fighter
	ld.gauge = 0
	local ok = sure == true or rng:chance(Battle.treatChance(fo, party, b.boss))
	table.insert(ev, { t = "treat", by = ld.key, to = fo.key, ok = ok })
	if ok then
		fo.hp = 0
		local fa: any = fo
		fa.friend = true
	end
	b.lock = Battle.playTime(ev)
	b.undo = nil
	b.paused = false
	return true, ev, outcome(party, b)
end

-- Run: away (the battle over, "fled") as often as the party's speed against the wild ones' says; a miss starts the
-- leader's timer again and the battle runs on. Returns (true, events, result) or (false, an ErrCode).
function Battle.flee(party: { Fighter }, b: Battle, rng: Rng): (boolean, any, string?)
	if b.boss then
		return false, "blocked"
	end
	local ok = rng:chance(Battle.fleeChance(party, b.foes))
	local ev: { Event } = { { t = "flee", ok = ok } }
	if ok then
		return true, ev, "fled"
	end
	local lead = leader(party)
	if lead then
		lead.gauge = 0
	end
	b.lock = Battle.playTime(ev)
	b.undo = nil
	b.paused = false
	return true, ev, nil
end

-- A learnt skill (Data/Skills): `who` (a standing member who knows it at their level) uses it on `target` (a member,
-- a downed member or a wild one, as the skill aims), paying its cost in skill points; their timer starts again and
-- the battle runs again. Returns (true, events, result) or (false, an ErrCode).
function Battle.useSkill(party: { Fighter }, b: Battle, who: string, id: string, target: string?, rng: Rng): (boolean, any, string?)
	local d = Skills.byId[id]
	if d == nil then
		return false, "not_found"
	end
	local user: Fighter? = nil
	for _, f in party do
		if f.key == who and f.hp > 0 then
			user = f
		end
	end
	if user == nil then
		return false, "not_found"
	end
	local u = user :: Fighter
	if not Skills.knows(Skills.lineOf(u.kind, u.skill), u.lvl, id) then
		return false, "locked"
	end
	if b.sp + 1e-6 < d.cost then
		return false, "sp"
	end
	-- the target the skill aims at
	local tgt: Fighter? = nil
	if d.target ~= "none" then
		local list: { Fighter } = if d.target == "foe" then b.foes else party
		for _, f in list do
			if f.key == target and not (f :: any).friend then
				if (d.target == "down" and f.hp <= 0) or (d.target ~= "down" and f.hp > 0) then
					tgt = f
				end
			end
		end
		if tgt == nil then
			return false, "not_found"
		end
	end
	b.sp -= d.cost
	u.gauge = 0
	local ev: { Event } = { { t = "skill", by = u.key, id = id } }
	local function healOne(f: Fighter, share: number)
		local amt = math.min(f.maxHp - f.hp, math.ceil(f.maxHp * share))
		f.hp += amt
		table.insert(ev, { t = "heal", by = u.key, to = f.key, amt = amt })
	end
	if d.dmg then
		local foes: { Fighter } = if d.all then Battle.alive(b.foes) else { tgt :: Fighter }
		for _ = 1, d.hits or 1 do
			for _, foe in foes do
				if foe.hp > 0 then
					local dmg = damage(u, foe, d.dmg, rng, if b.foeShield > 0 then Tuning.ShieldTake else 1)
					foe.hp = math.max(0, foe.hp - dmg)
					table.insert(ev, { t = "hit", by = u.key, to = foe.key, dmg = dmg, skill = id, ko = foe.hp <= 0 })
				end
			end
		end
	end
	if d.shield then
		b.shield = math.max(b.shield, d.shield)
		table.insert(ev, { t = "shield", by = u.key })
	end
	if d.heal then
		if d.all then
			for _, f in Battle.alive(party) do
				healOne(f, d.heal)
			end
		elseif tgt then
			healOne(tgt, d.heal)
		end
	end
	if d.revive and tgt then
		local t = tgt :: Fighter
		local amt = math.max(1, math.ceil(t.maxHp * d.revive))
		t.hp = amt
		t.gauge = 0
		table.insert(ev, { t = "revive", by = u.key, to = t.key, amt = amt })
	end
	if d.rally then
		for _, f in Battle.alive(party) do
			f.atk = math.floor(f.atk * d.rally + 0.5)
		end
		table.insert(ev, { t = "rally", by = u.key })
	end
	if d.haste then
		for _, f in Battle.alive(party) do
			if f ~= u then
				f.gauge = math.min(1, f.gauge + (d.haste :: number))
			end
		end
		table.insert(ev, { t = "haste", by = u.key })
	end
	if d.dizzy then
		for _, f in Battle.alive(b.foes) do
			f.gauge = math.min(f.gauge, d.dizzy :: number)
		end
		table.insert(ev, { t = "dizzy", by = u.key })
	end
	b.lock = Battle.playTime(ev)
	b.undo = nil
	b.paused = false
	return true, ev, outcome(party, b)
end

-- The timers as they stand (the client runs them on between syncs): { [key] = gauge }, the hold, the pause and the
-- skill points.
function Battle.gauges(party: { Fighter }, b: Battle): { g: { [string]: number }, lock: number, paused: boolean, sp: number, crowd: number }
	local g: { [string]: number } = {}
	for _, list in { party, b.foes } :: { { Fighter } } do
		for _, f in list do
			g[f.key] = math.floor(f.gauge * 1000 + 0.5) / 1000
		end
	end
	return { g = g, lock = b.lock, paused = b.paused, sp = math.floor(b.sp * 100 + 0.5) / 100, crowd = math.floor(Battle.crowd(party, b.foes) * 1000 + 0.5) / 1000 }
end

return Battle
