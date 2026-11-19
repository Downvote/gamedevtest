--!strict
-- The rewards for coming back and for playing (GAME_DESIGN 15; Data/Rewards). The request (2026-11-19): "add rewards
-- for playtime, daily rewards, streak rewards, codes, and as many retention features you can think of". Pure:
-- IslandService calls these with the session's profile, the sea's clock (`now`, seconds; a day is a UTC day,
-- floor(now / 86400)) and the session's Rng. Actions return (true, data) or (false, ErrCode) and change the profile
-- only when they succeed; data's `given` lists what was given (Logic/Store's Given, and { kind = "spin", n } and
-- { kind = "boost", id, n = seconds }).
--   The daily reward (`claimDaily`): once a day; claimed the day after the last claim the streak goes on, else it
--   starts again at 1. The streak's day in the 7-day round picks the reward (Data/Rewards.DAILY); a streak reaching a
--   milestone gives it too, once (MILESTONES). `daily` says where the player stands.
--   Playtime gifts (`tick`, `claimPlay`): seconds on the island today count up while the player is here; each gift
--   is claimed by hand once its minutes are in, once a day.
--   Daily tasks (`sync` deals three a day; `taskState`, `claimTask`, `claimBonus`): each counts a stat from the
--   moment it was dealt; all three claimed, the bonus.
--   The Lucky Shell (`spins`, `spin`): one free spin a day, more from the rewards; a weighted slice of Data/Rewards.SPIN.
--   Codes (`redeem`): a code from the server's list (Config/Codes: upper case, maybe an end time), once each.
--   The Index's milestones (`claimIndex`): kinds had, once each.
local Types = require(script.Parent.Parent.Types)
local RewardsData = require(script.Parent.Parent.Data.Rewards)
local Util = require(script.Parent.Util)
local Store = require(script.Parent.Store)

type Profile = Types.Profile
type ErrCode = Types.ErrCode
type Rng = Types.Rng
type Given = Store.Given
type Reward = RewardsData.Reward

local Rewards = {}

function Rewards.day(now: number): number
	return math.floor(now / 86400)
end

-- A new save's rewards.
function Rewards.fresh(): Types.RewardsSave
	return {
		daily = { last = -1, streak = 0, best = 0, miles = {} },
		play = { day = -1, secs = 0, got = {} },
		tasks = { day = -1, list = {}, got = {}, bonus = false },
		spin = { day = -1, extra = 0, total = 0 },
		codes = {},
		index = { got = {} },
	}
end

------------------------------------------------------------------ giving
-- One reward: shells, an egg, a look or a title through Logic/Store.give; spins and timed boosts here.
function Rewards.give(p: Profile, r: Reward): Given
	if r.kind == "spin" then
		local n = math.max(0, math.floor(r.n or 1))
		p.rewards.spin.extra = math.min(999, p.rewards.spin.extra + n)
		return { kind = "spin", n = n }
	elseif r.kind == "boost" then
		local id = r.id or ""
		if RewardsData.BOOSTS[id] == nil then
			return { kind = "none" }
		end
		local secs = math.max(0, math.floor((r.mins or 1) * 60))
		p.boosts[id] = math.min(RewardsData.BOOST_MAX, (p.boosts[id] or 0) + secs)
		return { kind = "boost", id = id, n = secs }
	end
	return Store.give(p, { kind = r.kind, mins = r.mins, r = r.r, id = r.id })
end

local function giveAll(p: Profile, list: { Reward }, into: { Given }?): { Given }
	local out: { Given } = into or {}
	for _, r in list do
		table.insert(out, Rewards.give(p, r))
	end
	return out
end

------------------------------------------------------------------ the daily reward and the streak
export type Daily = {
	ready: boolean, -- today's reward waits
	streak: number, -- the streak today's claim makes (ready) or made (claimed)
	round: number, -- that streak's day in the 7-day round (1 .. 7)
	best: number,
	next: number, -- the next milestone's day not given yet (0: none left)
}
function Rewards.daily(p: Profile, now: number): Daily
	local d = p.rewards.daily
	local today = Rewards.day(now)
	local ready = d.last ~= today
	local streak = if not ready then d.streak elseif d.last == today - 1 then d.streak + 1 else 1
	local nextM = 0
	for _, m in RewardsData.MILESTONES do
		if table.find(d.miles, m.day) == nil then
			nextM = m.day
			break
		end
	end
	return { ready = ready, streak = streak, round = (streak - 1) % #RewardsData.DAILY + 1, best = d.best, next = nextM }
end

-- Today's daily reward (and a milestone the streak reaches). cooldown: already claimed today.
function Rewards.claimDaily(p: Profile, now: number): (boolean, any)
	local st = Rewards.daily(p, now)
	if not st.ready then
		return false, "cooldown" :: ErrCode
	end
	local d = p.rewards.daily
	d.last = Rewards.day(now)
	d.streak = st.streak
	d.best = math.max(d.best, st.streak)
	local given = giveAll(p, RewardsData.DAILY[st.round])
	local miles: { number } = {}
	for _, m in RewardsData.MILESTONES do
		if st.streak >= m.day and table.find(d.miles, m.day) == nil then
			table.insert(d.miles, m.day)
			table.insert(miles, m.day)
			giveAll(p, m.give, given)
		end
	end
	return true, { given = given, streak = st.streak, round = st.round, miles = miles }
end

------------------------------------------------------------------ the day rolling over: playtime and the tasks
-- A counter a task counts (Data/Rewards.TASKS `stat`).
local function stat(p: Profile, key: string): number
	if key == "play" then
		return p.rewards.play.secs / 60
	end
	local v = (p.stats :: any)[key]
	return if type(v) == "number" then v else 0
end

-- A task's goal on this island now.
local function goalOf(p: Profile, def: RewardsData.TaskDef): number
	if def.mins then
		local n = Store.minutes(p, def.mins)
		local step = 10 ^ math.max(0, math.floor(math.log10(math.max(1, n))) - 1)
		return math.max(1, math.floor(n / step + 0.5) * step)
	end
	return math.max(1, math.min(def.max, math.floor(def.base + def.per * (p.tier - 1))))
end

-- The day's playtime and tasks: a new day starts the playtime again and deals three tasks (the ones the island is big
-- enough for, picked by the day and the island's own seed, so the same three come back on a rejoin). Returns whether
-- anything changed.
function Rewards.sync(p: Profile, now: number): boolean
	local rw = p.rewards
	local today = Rewards.day(now)
	local changed = false
	if rw.play.day ~= today then
		rw.play = { day = today, secs = 0, got = {} }
		changed = true
	end
	if rw.tasks.day ~= today then
		local pool: { RewardsData.TaskDef } = {}
		for _, t in RewardsData.TASKS do
			if p.tier >= t.tier then
				table.insert(pool, t)
			end
		end
		local rng = Util.newRng(Util.hash32(string.format("tasks:%d:%d", today, math.floor(p.createdAt))))
		local list: { Types.TaskSave } = {}
		while #list < RewardsData.TASK_COUNT and #pool > 0 do
			local t = table.remove(pool, rng:int(1, #pool)) :: RewardsData.TaskDef
			table.insert(list, { id = t.id, n = goalOf(p, t), at = stat(p, t.stat) })
		end
		rw.tasks = { day = today, list = list, got = table.create(#list, false), bonus = false }
		changed = true
	end
	return changed
end

-- dt seconds on the island (the session's clock tick): today's playtime.
function Rewards.tick(p: Profile, now: number, dt: number)
	Rewards.sync(p, now)
	p.rewards.play.secs += math.clamp(dt, 0, 5)
end

-- A playtime gift (Data/Rewards.PLAY's index): not_done (its minutes aren't in), used (claimed today), bad_payload.
function Rewards.claimPlay(p: Profile, i: number, now: number): (boolean, any)
	Rewards.sync(p, now)
	local g = RewardsData.PLAY[i]
	if g == nil then
		return false, "bad_payload" :: ErrCode
	end
	local pl = p.rewards.play
	if table.find(pl.got, i) then
		return false, "used" :: ErrCode
	end
	if pl.secs < g.min * 60 then
		return false, "not_done" :: ErrCode
	end
	table.insert(pl.got, i)
	return true, { given = giveAll(p, g.give), i = i }
end

local TASK_BY_ID: { [string]: RewardsData.TaskDef } = {}
for _, t in RewardsData.TASKS do
	TASK_BY_ID[t.id] = t
end
Rewards.taskDef = TASK_BY_ID

-- Today's tasks as the panel shows them: id, words, goal, how far, done, claimed.
export type TaskState = { id: string, text: string, n: number, have: number, done: boolean, got: boolean }
function Rewards.taskState(p: Profile): { TaskState }
	local out: { TaskState } = {}
	local tk = p.rewards.tasks
	for i, t in tk.list do
		local def = TASK_BY_ID[t.id]
		if def then
			local have = math.max(0, math.floor(stat(p, def.stat) - t.at + 1e-6))
			table.insert(out, { id = t.id, text = def.text, n = t.n, have = math.min(have, t.n), done = have >= t.n, got = tk.got[i] == true })
		end
	end
	return out
end

-- A task's reward (its index today): not_done, used, bad_payload.
function Rewards.claimTask(p: Profile, i: number, now: number): (boolean, any)
	Rewards.sync(p, now)
	local tk = p.rewards.tasks
	local t = tk.list[i]
	local def = if t then TASK_BY_ID[t.id] else nil
	if t == nil or def == nil then
		return false, "bad_payload" :: ErrCode
	end
	if tk.got[i] then
		return false, "used" :: ErrCode
	end
	if not Rewards.taskState(p)[i].done then
		return false, "not_done" :: ErrCode
	end
	tk.got[i] = true
	return true, { given = giveAll(p, def.give), i = i }
end

-- The bonus once every task today is claimed: not_done, used.
function Rewards.claimBonus(p: Profile, now: number): (boolean, any)
	Rewards.sync(p, now)
	local tk = p.rewards.tasks
	if tk.bonus then
		return false, "used" :: ErrCode
	end
	if #tk.list == 0 then
		return false, "not_done" :: ErrCode
	end
	for i = 1, #tk.list do
		if not tk.got[i] then
			return false, "not_done" :: ErrCode
		end
	end
	tk.bonus = true
	return true, { given = giveAll(p, RewardsData.BONUS) }
end

------------------------------------------------------------------ the Lucky Shell
-- Spins in hand: today's free one (not used yet) and the extra ones.
function Rewards.spins(p: Profile, now: number): number
	local sp = p.rewards.spin
	return (if sp.day ~= Rewards.day(now) then 1 else 0) + sp.extra
end

-- A spin (the free one first): a slice by weight, its reward given. not_done: no spin in hand. The slice's index
-- tells the wheel where to stop.
function Rewards.spin(p: Profile, rng: Rng, now: number): (boolean, any)
	local sp = p.rewards.spin
	local today = Rewards.day(now)
	if sp.day ~= today then
		sp.day = today
	elseif sp.extra > 0 then
		sp.extra -= 1
	else
		return false, "not_done" :: ErrCode
	end
	sp.total += 1
	local ws: { number } = {}
	for _, s in RewardsData.SPIN do
		table.insert(ws, s.w)
	end
	local i = rng:weighted(ws)
	if i < 1 then
		i = 1
	end
	return true, { slice = i, given = { Rewards.give(p, RewardsData.SPIN[i].give) } }
end

------------------------------------------------------------------ codes
export type CodeDef = { give: { Reward }, ends: number? }

-- A code as typed: trimmed and upper case.
function Rewards.norm(code: string): string
	return string.upper((string.gsub(code, "^%s*(.-)%s*$", "%1")))
end

-- Redeem `code` against the server's list `defs`: not_found (no such code, or it ended), used (this player had it).
function Rewards.redeem(p: Profile, code: string, defs: { [string]: CodeDef }, now: number): (boolean, any)
	local c = Rewards.norm(code)
	local def = defs[c]
	if def == nil or (def.ends ~= nil and now > def.ends) then
		return false, "not_found" :: ErrCode
	end
	if p.rewards.codes[c] then
		return false, "used" :: ErrCode
	end
	p.rewards.codes[c] = true
	return true, { given = giveAll(p, def.give), code = c }
end

------------------------------------------------------------------ the Index's milestones
-- Kinds in the Index (had one).
function Rewards.kinds(p: Profile): number
	local n = 0
	for _, c in p.seen do
		if c >= 2 then
			n += 1
		end
	end
	return n
end

-- An Index milestone (Data/Rewards.INDEX's index): not_done (too few kinds yet), used, bad_payload.
function Rewards.claimIndex(p: Profile, i: number): (boolean, any)
	local g = RewardsData.INDEX[i]
	if g == nil then
		return false, "bad_payload" :: ErrCode
	end
	local got = p.rewards.index.got
	if table.find(got, g.n) then
		return false, "used" :: ErrCode
	end
	if Rewards.kinds(p) < g.n then
		return false, "not_done" :: ErrCode
	end
	table.insert(got, g.n)
	return true, { given = giveAll(p, g.give), i = i }
end

------------------------------------------------------------------ the client's view
-- What the Rewards panel and the HUD show (Session.view's `rewards`), and how many things wait to be claimed (its
-- red dot).
export type View = {
	daily: Daily,
	play: number, -- seconds on the island today
	playGot: { number },
	tasks: { TaskState },
	bonus: boolean,
	spins: number,
	kinds: number,
	indexGot: { number },
	ready: number, -- things to claim now
}
function Rewards.view(p: Profile, now: number): View
	Rewards.sync(p, now)
	local rw = p.rewards
	local daily = Rewards.daily(p, now)
	local tasks = Rewards.taskState(p)
	local kinds = Rewards.kinds(p)
	local ready = if daily.ready then 1 else 0
	for i, g in RewardsData.PLAY do
		if rw.play.secs >= g.min * 60 and table.find(rw.play.got, i) == nil then
			ready += 1
		end
	end
	local all = #tasks > 0
	for _, t in tasks do
		if t.done and not t.got then
			ready += 1
		end
		all = all and t.got
	end
	if all and not rw.tasks.bonus then
		ready += 1
	end
	local spins = Rewards.spins(p, now)
	ready += math.min(spins, 1)
	for _, g in RewardsData.INDEX do
		if kinds >= g.n and table.find(rw.index.got, g.n) == nil then
			ready += 1
		end
	end
	return {
		daily = daily,
		play = rw.play.secs,
		playGot = table.clone(rw.play.got),
		tasks = tasks,
		bonus = rw.tasks.bonus,
		spins = spins,
		kinds = kinds,
		indexGot = table.clone(rw.index.got),
		ready = ready,
	}
end

return table.freeze(Rewards)
