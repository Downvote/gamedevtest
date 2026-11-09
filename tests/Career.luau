-- A sensible player for the Economy spec and the tuning runs: plays a session second by second through Logic/Studio
-- (the server's own rules) and logs what happened minute by minute. The idea team rolls on its clock; with three
-- ideas on the board the player makes a game of the three most valuable, plays its minigames (each about
-- MicroIntro + its clock long, won with a chance by difficulty and `skill`, a lost one retried up to `retries` times)
-- and launches it; the games pay their income every second; coins go on the cheaper of the two upgrades.
local Tuning = require("../build/luautest/shared/Config/Tuning")
local Schema = require("../build/luautest/shared/Logic/Schema")
local Studio = require("../build/luautest/shared/Logic/Studio")
local Ideas = require("../build/luautest/shared/Logic/Ideas")
local Util = require("../build/luautest/shared/Logic/Util")

local Career = {}

export type Opts = { skill: number?, retries: number?, log: ((string) -> ())? }

-- The chance to win a minigame of difficulty d (1 .. DiffMax) for a player of `skill` (0..1).
function Career.winChance(skill: number, d: number): number
	return math.clamp(skill - 0.07 * (d - 1), 0.05, 0.98)
end

local function microSeconds(d: number): number
	return Tuning.MicroIntro + math.max(Tuning.MicroSecondsMin, Tuning.MicroSeconds - Tuning.MicroSecondsStep * (d - 1)) + 1.5
end

function Career.play(seed: number, seconds: number, opts: Opts?)
	local o: Opts = opts or {}
	local skill = o.skill or 0.85
	local retries = o.retries or 1
	local p = Schema.default(0, seed)
	local rng = Util.newRng(seed * 7 + 1)
	local roll = 0
	local busy = 0 -- seconds left playing minigames
	local frac = 0
	local log = o.log
	local firstGame: number? = nil
	local firstUpgrade: number? = nil
	local firstTier: { [number]: number } = {}
	local timeline = {}
	local function say(s: string)
		if log then
			log(s)
		end
	end
	for t = 1, seconds do
		-- the idea team
		roll += 1
		while roll >= Studio.rollEvery(p) do
			roll -= Studio.rollEvery(p)
			local r = Studio.rollIdea(p, rng)
			if firstTier[r.tier] == nil then
				firstTier[r.tier] = t
				if r.tier >= 3 then
					say(string.format("  %5ds first %s: %s (%s)", t, Ideas.tierName(r.tier), Ideas.name(r.card), tostring(r.oneIn)))
				end
			end
		end
		-- the games' income
		frac += p.rate
		local whole = math.floor(frac)
		frac -= whole
		Studio.earn(p, whole)
		-- making a game
		if busy > 0 then
			busy -= 1
			if busy <= 0 and p.project then
				Studio.launch(p, t)
				firstGame = firstGame or t
			end
		elseif p.project == nil and #p.ideas >= 3 then
			local order = {}
			for i = 1, #p.ideas do
				table.insert(order, i)
			end
			table.sort(order, function(a, b)
				return Ideas.value(p.ideas[a]) > Ideas.value(p.ideas[b])
			end)
			Studio.make(p, order[1], order[2], order[3], t)
			local proj = p.project :: any
			local spent = 4 -- picking
			for slot, c in proj.ideas do
				local d = Ideas.difficulty(c)
				for _ = 0, retries do
					spent += microSeconds(d)
					if rng:chance(Career.winChance(skill, d)) then
						Studio.result(p, slot, true)
						break
					end
					Studio.result(p, slot, false)
				end
			end
			busy = math.ceil(spent)
		end
		-- upgrades: the cheaper one
		local guard = 0
		while guard < 20 do
			guard += 1
			local cs = if Studio.speedMaxed(p) then math.huge else Studio.upgradeCost("speed", p.upgrades.speed)
			local cl = Studio.upgradeCost("luck", p.upgrades.luck)
			local k = if cs <= cl then "speed" else "luck"
			if not Studio.buyUpgrade(p, k) then
				break
			end
			firstUpgrade = firstUpgrade or t
		end
		if t % 600 == 0 then
			local nextCost = math.min(if Studio.speedMaxed(p) then math.huge else Studio.upgradeCost("speed", p.upgrades.speed), Studio.upgradeCost("luck", p.upgrades.luck))
			local row = { t = t, coins = p.coins, rate = p.rate, games = p.stats.games, speed = p.upgrades.speed, luck = p.upgrades.luck, best = p.stats.best, wait = (nextCost - p.coins) / math.max(1e-9, p.rate) }
			table.insert(timeline, row)
			say(string.format("%3dmin coins %s rate %.1f/s games %d speed %d (%.1fs) luck %d (x%.1f) best 1 in %d next upgrade in %.0fs", t // 60, tostring(math.floor(p.coins)), p.rate, p.stats.games, p.upgrades.speed, Studio.rollEvery(p), p.upgrades.luck, Studio.luck(p), p.stats.best, row.wait))
		end
	end
	return { profile = p, timeline = timeline, firstGame = firstGame, firstUpgrade = firstUpgrade, firstTier = firstTier }
end

return Career
