--!strict
-- The seasons and the weather from the sea's clock (GAME_DESIGN 13; docs/ARCHITECTURE.md 6). Pure: the server and
-- every client work out the same season and weather from the same clock (WorldClock on the server, the view's `clock`
-- run on by StateClient on a client), so nothing about it is saved or sent but the clock. The request (2026-11-14):
-- "also, make weather and seasons, and eggs spawns are affected by these with different mutations".
--   at(t) -> State: the season (Tuning.SeasonSecs each from Tuning.WeatherEpoch, in Data/Weather.SEASONS' order) and
--   the weather (spells of Tuning.WeatherSecs, a whole number of them a season, so a spell never runs across a season
--   change; each spell's kind picked by the season's odds from a hash of its number; a storm never twice running), with
--   the seconds left in each.
--   touch(rng, state, rarity) -> (kind?, tier?): whether an egg laid now is touched by the weather and its mutation's
--   tier; mutation(kind, tier) -> the mutation id; luck(state) -> the luck the weather adds to the tree's eggs.
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Data = require(script.Parent.Parent.Data.Weather)
local Traits = require(script.Parent.Parent.Data.Traits)
local Util = require(script.Parent.Util)

local Weather = {}

export type State = {
	season: string, -- Data/Weather.SEASONS id
	seasonLeft: number, -- seconds till the next season
	kind: string, -- Data/Weather.KINDS id
	kindLeft: number, -- seconds till the next spell
	spell: number, -- the spell's number (from the epoch)
	year: number, -- seasons gone round (from the epoch)
}

local function seasonIndex(t: number): number
	return (t - Tuning.WeatherEpoch) // Tuning.SeasonSecs
end

-- The season at time t: its id, the seconds left in it, its number from the epoch.
function Weather.season(t: number): (string, number, number)
	local i = seasonIndex(t)
	local s = Data.SEASONS[i % #Data.SEASONS + 1]
	local ends = Tuning.WeatherEpoch + (i + 1) * Tuning.SeasonSecs
	return s.id, ends - t, i
end

-- The kind a spell's hash picks by its season's odds (before the no-two-storms rule).
local function raw(spell: number): string
	local t = Tuning.WeatherEpoch + spell * Tuning.WeatherSecs
	local sid = Weather.season(t)
	local odds = Data.seasonById[sid].odds
	local total = 0
	for _, o in odds do
		total += o.w
	end
	local x = (Util.hash32("weather:" .. string.format("%d", spell)) % 1000003) / 1000003 * total
	for _, o in odds do
		x -= o.w
		if x < 0 then
			return o.kind
		end
	end
	return odds[#odds].kind
end

-- A spell's kind: the hash's pick, but a storm right after a storm is the season's first kind instead.
function Weather.kindOf(spell: number): string
	local k = raw(spell)
	if k == "storm" and raw(spell - 1) == "storm" then
		local sid = Weather.season(Tuning.WeatherEpoch + spell * Tuning.WeatherSecs)
		return Data.seasonById[sid].odds[1].kind
	end
	return k
end

-- The season and the weather at time t (seconds on the sea's clock).
function Weather.at(t: number): State
	local sid, sLeft, si = Weather.season(t)
	local spell = (t - Tuning.WeatherEpoch) // Tuning.WeatherSecs
	local ends = Tuning.WeatherEpoch + (spell + 1) * Tuning.WeatherSecs
	return {
		season = sid,
		seasonLeft = sLeft,
		kind = Weather.kindOf(spell),
		kindLeft = ends - t,
		spell = spell,
		year = si // #Data.SEASONS,
	}
end

-- The luck the weather adds to the tree's eggs now (Tuning.WeatherLuck: a storm's eggs come rarer).
function Weather.luck(state: State?): number
	if state == nil then
		return 0
	end
	return Tuning.WeatherLuck[state.kind] or 0
end

-- An egg laid now: touched by the weather (Tuning.WeatherTouch by kind) or not; touched, its mutation's tier (by
-- Tuning.WeatherTierW, a rarer egg rolling higher, a storm a tier higher and at least 2). Draws from rng only while a
-- touching weather lasts.
function Weather.touch(rng: any, state: State?, rarity: number): (string?, number?)
	if state == nil then
		return nil, nil
	end
	local def = Data.byId[state.kind]
	local chance = Tuning.WeatherTouch[state.kind] or 0
	if def == nil or def.family == nil or chance <= 0 then
		return nil, nil
	end
	if rng:next() >= chance then
		return nil, nil
	end
	local w = table.clone(Tuning.WeatherTierW)
	local r = math.clamp(rarity, 1, Traits.RMAX)
	-- (a rarer egg: fewer first tiers, more of the top ones)
	w[1] = math.max(8, w[1] - (r - 1) * 8)
	w[3] += (r - 1) * 3
	w[4] += (r - 1) * 2
	local total = 0
	for _, x in w do
		total += x
	end
	local x = rng:next() * total
	local tier = #w
	for i, v in w do
		x -= v
		if x < 0 then
			tier = i
			break
		end
	end
	if state.kind == "storm" then
		tier = math.clamp(tier + 1, 2, 4)
	end
	return state.kind, tier
end

-- The mutation an egg touched by `kind` at `tier` hatches with ("rain", 2 -> "rainy2"); nil for a kind that touches
-- no egg.
function Weather.mutation(kind: string?, tier: number?): string?
	local def = if kind then Data.byId[kind] else nil
	if def == nil or def.family == nil then
		return nil
	end
	local id = Traits.at(def.family :: string, tier or 1)
	return if Traits.byId[id] then id else nil
end

-- Whether a kind and a season id are known (a save's egg, a payload).
function Weather.known(kind: any): boolean
	return type(kind) == "string" and Data.byId[kind] ~= nil
end
function Weather.knownSeason(season: any): boolean
	return type(season) == "string" and Data.seasonById[season] ~= nil
end

-- A length of time for the HUD's status lines, in whole minutes rounded up: "2 h 10 min", "2 h", "45 min", "1 min".
function Weather.left(secs: number): string
	local m = math.max(1, math.ceil(math.max(0, secs) / 60))
	if m >= 60 then
		local h, rest = m // 60, m % 60
		return if rest == 0 then string.format("%d h", h) else string.format("%d h %d min", h, rest)
	end
	return string.format("%d min", m)
end

return Weather
