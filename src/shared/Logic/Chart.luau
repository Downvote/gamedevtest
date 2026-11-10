--!strict
-- The sea chart (GAME_DESIGN 7; docs/ARCHITECTURE.md 6): every player's own sea of islands round their home island,
-- made from their sea seed (profile.sea) and the same every time. An island's level grows with its distance from
-- home; how far the party can sail is the boat's range, bigger with each boat level (shells and wood). Pure.
--   islands(sea) -> { ChartIsle }   (Tuning.ChartIslands of them, id 1.., nearest first: x, y in leagues from home)
--   isle(sea, id) -> Isle?          (what the island holds: Logic/Expedition.chart from its level and seed)
--   radius(boat), reachable(p, id), boatCost(boat), upgradeBoat(p)
local Types = require(script.Parent.Parent.Types)
local Tuning = require(script.Parent.Parent.Config.Tuning)
local Util = require(script.Parent.Util)
local Expedition = require(script.Parent.Expedition)

type Profile = Types.Profile
type ErrCode = Types.ErrCode

export type ChartIsle = { id: number, x: number, y: number, dist: number, lvl: number, seed: number }

local Chart = {}

local cache: { [number]: { ChartIsle } } = {}

-- An island's level at a distance (leagues) from home.
function Chart.levelAt(dist: number): number
	return math.clamp(math.floor(1 + math.max(0, dist - Tuning.ChartMinDist) * Tuning.ChartLvlPerLeague + 0.5), 1, Tuning.LevelMax)
end

-- The islands of a sea: the first few within the first boat's range, the rest spread out to the chart's edge, never
-- too close to each other or to home; nearest first.
function Chart.islands(sea: number): { ChartIsle }
	local hit = cache[sea]
	if hit then
		return hit
	end
	local rng = Util.newRng(Util.hash32(sea) + 101)
	local pts: { { number } } = {}
	local function free(x: number, y: number): boolean
		for _, q in pts do
			local dx, dy = x - q[1], y - q[2]
			if dx * dx + dy * dy < Tuning.ChartSpacing * Tuning.ChartSpacing then
				return false
			end
		end
		return true
	end
	local tries = 0
	while #pts < Tuning.ChartIslands and tries < 4000 do
		tries += 1
		-- the first ones near home (the first boat reaches them), then anywhere out to the edge
		local near = #pts < Tuning.ChartNear
		local lo = Tuning.ChartMinDist
		local hi = if near then Tuning.BoatRadius[1] - 0.3 else Tuning.ChartMaxDist
		local d = lo + (hi - lo) * rng:next()
		local a = rng:next() * math.pi * 2
		local x, y = math.cos(a) * d, math.sin(a) * d
		if free(x, y) then
			table.insert(pts, { x, y, d })
		end
	end
	table.sort(pts, function(a, b)
		return a[3] < b[3]
	end)
	local out: { ChartIsle } = {}
	for i, q in pts do
		table.insert(out, {
			id = i,
			x = q[1],
			y = q[2],
			dist = q[3],
			lvl = Chart.levelAt(q[3]),
			seed = Util.hash32(sea * 7919 + i * 104729) % 2147483646 + 1,
		})
	end
	cache[sea] = out
	return out
end

-- What an island holds (its kind, name, driftlings, guardian, loot: Expedition.chart), with its chart id.
function Chart.isle(sea: number, id: number): Types.Isle?
	local c = Chart.islands(sea)[id]
	if c == nil then
		return nil
	end
	local isle = Expedition.chart(c.lvl, c.seed)
	isle.id = id
	return isle
end

-- How far a boat of a level sails (leagues).
function Chart.radius(boat: number): number
	local r = Tuning.BoatRadius
	return r[math.clamp(math.floor(boat), 1, #r)]
end

function Chart.reachable(p: Profile, id: number): boolean
	local c = Chart.islands(p.sea)[id]
	return c ~= nil and c.dist <= Chart.radius(p.boat)
end

-- Whether the island has been charted (its guardian beaten once).
function Chart.charted(p: Profile, id: number): boolean
	return table.find(p.chart, id) ~= nil
end

-- The next boat level's price, or nil at the top.
function Chart.boatCost(boat: number): { shells: number, wood: number }?
	return Tuning.BoatCost[math.floor(boat) + 1]
end

-- Set sail for an island of the chart: bad_payload (no such island), far (past the boat's range), then
-- Expedition.start's own refusals.
function Chart.sail(p: Profile, id: number, members: { string }): (boolean, any)
	local isle = Chart.isle(p.sea, id)
	if isle == nil then
		return false, "bad_payload" :: ErrCode
	end
	if not Chart.reachable(p, id) then
		return false, "far" :: ErrCode
	end
	return Expedition.start(p, isle, members)
end

function Chart.upgradeBoat(p: Profile): (boolean, any)
	local cost = Chart.boatCost(p.boat)
	if cost == nil then
		return false, "max" :: ErrCode
	end
	if p.shells < cost.shells then
		return false, "money" :: ErrCode
	end
	if p.wood < cost.wood then
		return false, "wood" :: ErrCode
	end
	p.shells -= cost.shells
	p.wood -= cost.wood
	p.boat += 1
	return true, { boat = p.boat, radius = Chart.radius(p.boat) }
end

return Chart
