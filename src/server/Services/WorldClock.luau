--!strict
-- The sea's clock (GAME_DESIGN 3, 8; docs/ARCHITECTURE.md 7.4): one time of day for every island on the server,
-- in seconds since the epoch (os.time() at start, then advanced by IslandService.step: real time in a live game,
-- simulated time in the sims). A calendar day is Tuning.DaySeconds of it (hours); dawn at each multiple.
--   now(), advance(dt), shift(seconds) (sims and previews), dayIndex(), dayFrac() (0 dawn .. 1)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)

local WorldClock = {}

local t = os.time()

function WorldClock.now(): number
	return t
end

function WorldClock.advance(dt: number)
	if dt > 0 and dt == dt then
		t += dt
	end
end

-- Sims and previews: jump the clock (a day's end, a night).
function WorldClock.shift(seconds: number)
	if seconds == seconds then
		t += seconds
	end
end

function WorldClock.dayIndex(): number
	return math.floor(t / Tuning.DaySeconds)
end

function WorldClock.dayFrac(): number
	return (t % Tuning.DaySeconds) / Tuning.DaySeconds
end

return WorldClock
