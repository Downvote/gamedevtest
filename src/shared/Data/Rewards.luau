--!strict
-- The rewards for coming back and for playing (GAME_DESIGN 15; Logic/Rewards). Pure. The request (2026-11-19): "add
-- rewards for playtime, daily rewards, streak rewards, codes, and as many retention features you can think of". In
-- Random Bakery's way (its Rewards sheet), our own tables.
--   A reward is Data/Track's shape, plus two of its own:
--     { kind = "shells", mins = m }  m minutes of what the island makes now (Logic/Store.minutes: never less than
--                                    Tuning.RewardFloor a minute times EggTier by its tier)
--     { kind = "egg", r = r }        an egg of rarity r into the bag, hatched for nothing whenever the player likes
--     { kind = "look", id = id }     a cosmetic; { kind = "title", id = id } a title (Data/Titles, how "reward")
--     { kind = "spin", n = n }       n more spins of the Lucky Shell (Logic/Rewards.spin)
--     { kind = "boost", id = "shells" | "luck", mins = m }
--                                    a timed boost for m minutes on the island (Profile.boosts; they run down while
--                                    the player is here): every shell x (1 + Tuning.TimedShells), or the tree's eggs
--                                    luckier by Tuning.TimedLuck
--   DAILY: the daily reward, a 7-day round: the day of the streak (1 .. 7, then round again) picks it; a day missed
--   starts the streak again at 1. MILESTONES: once each, the day the streak reaches it (its best kept).
--   PLAY: gifts for time on the island today (UTC), each claimed by hand once its minutes are in.
--   TASKS: three a day out of these (the ones the island is big enough for), each counting from the moment it is
--   dealt: `stat` the Profile.stats field (or "play": minutes today), n = base + per x (tier - 1) up to max ("earned":
--   `mins` minutes of what the island makes when dealt). BONUS when all three are claimed.
--   SPIN: the Lucky Shell's slices (weights add to 100); one free spin a day, more from the rewards.
--   INDEX: kinds in the Index (Profile.seen), once each.
export type Reward = { kind: string, mins: number?, r: number?, id: string?, n: number? }
export type Bundle = { Reward }
export type Milestone = { day: number, give: Bundle }
export type PlayGift = { min: number, give: Bundle }
export type TaskDef = {
	id: string,
	text: string, -- with {n}
	stat: string,
	base: number,
	per: number,
	max: number,
	mins: number?,
	tier: number, -- the island tier it is dealt from
	give: Bundle,
}
export type Slice = { w: number, give: Reward, label: string }
export type IndexGift = { n: number, give: Bundle }

local function shells(m: number): Reward
	return { kind = "shells", mins = m }
end
local function egg(r: number): Reward
	return { kind = "egg", r = r }
end
local function spin(n: number): Reward
	return { kind = "spin", n = n }
end
local function boost(id: string, m: number): Reward
	return { kind = "boost", id = id, mins = m }
end
local function title(id: string): Reward
	return { kind = "title", id = id }
end

-- stylua: ignore start
local DAILY: { Bundle } = {
	{ shells(10) },
	{ egg(2), shells(5) },
	{ shells(20), spin(1) },
	{ egg(3), boost("luck", 15) },
	{ shells(30), boost("shells", 15) },
	{ egg(4), spin(1) },
	{ egg(5), shells(60), spin(2) },
}

local MILESTONES: { Milestone } = {
	{ day = 3, give = { title("dropin"), egg(3) } },
	{ day = 7, give = { egg(5), spin(3) } },
	{ day = 14, give = { title("devoted"), egg(5), shells(120) } },
	{ day = 30, give = { title("islandheart"), egg(6), spin(5) } },
	{ day = 60, give = { egg(6), egg(6), shells(240) } },
	{ day = 100, give = { title("tidekeeper"), egg(7) } },
}

local PLAY: { PlayGift } = {
	{ min = 2, give = { shells(3) } },
	{ min = 5, give = { shells(5) } },
	{ min = 10, give = { egg(2) } },
	{ min = 15, give = { shells(10), spin(1) } },
	{ min = 20, give = { boost("luck", 10) } },
	{ min = 30, give = { egg(3), shells(15) } },
	{ min = 45, give = { boost("shells", 15), spin(1) } },
	{ min = 60, give = { egg(4), shells(30) } },
}

local TASKS: { TaskDef } = {
	{ id = "hatch", text = "Hatch {n} eggs", stat = "taken", base = 3, per = 0.5, max = 12, tier = 1, give = { egg(2), shells(5) } },
	{ id = "build", text = "Place {n} pieces", stat = "built", base = 3, per = 0.4, max = 12, tier = 1, give = { shells(10) } },
	{ id = "earn", text = "Earn {n} shells", stat = "earned", base = 0, per = 0, max = 0, mins = 20, tier = 1, give = { shells(10) } },
	{ id = "play", text = "Spend {n} minutes on your island", stat = "play", base = 15, per = 0, max = 15, tier = 1, give = { spin(1) } },
	{ id = "sell", text = "Sell {n} driftlings", stat = "sold", base = 1, per = 0.25, max = 5, tier = 2, give = { shells(8), boost("luck", 10) } },
	{ id = "breed", text = "Hatch {n} Hatchery eggs", stat = "hatched", base = 1, per = 0.1, max = 3, tier = 3, give = { egg(3) } },
}

local BONUS: Bundle = { egg(4), spin(1), shells(15) }

local SPIN: { Slice } = {
	{ w = 30, give = shells(5), label = "5 min of shells" },
	{ w = 20, give = shells(15), label = "15 min of shells" },
	{ w = 16, give = egg(2), label = "Uncommon egg" },
	{ w = 12, give = shells(30), label = "30 min of shells" },
	{ w = 8, give = boost("luck", 15), label = "Lucky Hour, 15 min" },
	{ w = 7, give = egg(3), label = "Rare egg" },
	{ w = 4, give = boost("shells", 15), label = "Busy Day, 15 min" },
	{ w = 2.5, give = egg(4), label = "Epic egg" },
	{ w = 0.5, give = egg(5), label = "Legendary egg" },
}

local INDEX: { IndexGift } = {
	{ n = 5, give = { shells(10) } },
	{ n = 10, give = { egg(3) } },
	{ n = 20, give = { spin(2), shells(20) } },
	{ n = 35, give = { egg(4) } },
	{ n = 50, give = { egg(4), spin(2) } },
	{ n = 75, give = { egg(5) } },
	{ n = 100, give = { egg(5), spin(5) } },
	{ n = 125, give = { egg(6) } },
	{ n = 145, give = { egg(7) } },
}
-- stylua: ignore end

-- The timed boosts' names (the HUD's chips and the rewards' words).
local BOOSTS: { [string]: string } = { shells = "Busy Day", luck = "Lucky Hour" }

return table.freeze({
	DAILY = DAILY,
	MILESTONES = MILESTONES,
	PLAY = PLAY,
	TASKS = TASKS,
	TASK_COUNT = 3,
	BONUS = BONUS,
	SPIN = SPIN,
	INDEX = INDEX,
	BOOSTS = BOOSTS,
	BOOST_MAX = 4 * 3600, -- a timed boost holds this many seconds at most
})
