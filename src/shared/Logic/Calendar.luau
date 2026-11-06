--!strict
-- The game calendar (GAME_DESIGN 3). Pure. A week index counts from 0 = Year 1, Month 1, Week 1.
local Tuning = require(script.Parent.Parent.Config.Tuning)

local Calendar = {}

local WPM = Tuning.WeeksPerMonth
local MPY = Tuning.MonthsPerYear
local WPY = WPM * MPY

-- Year, month (1..12) and week of the month (1..4) of a week index.
function Calendar.parts(week: number): (number, number, number)
	local w = math.max(0, math.floor(week))
	return w // WPY + 1, (w // WPM) % MPY + 1, w % WPM + 1
end

function Calendar.year(week: number): number
	return math.max(0, math.floor(week)) // WPY + 1
end

-- The absolute month index (0-based) of a week: what monthly cooldowns compare.
function Calendar.month(week: number): number
	return math.max(0, math.floor(week)) // WPM
end

-- The first week of a year.
function Calendar.yearStart(year: number): number
	return (math.max(1, year) - 1) * WPY
end

function Calendar.isMonthStart(week: number): boolean
	return week % WPM == 0
end

-- The last week of a year (the awards night follows it).
function Calendar.isYearEnd(week: number): boolean
	return (week + 1) % WPY == 0
end

function Calendar.label(week: number): string
	local y, m, w = Calendar.parts(week)
	return string.format("Y%d M%d W%d", y, m, w)
end

function Calendar.long(week: number): string
	local y, m, w = Calendar.parts(week)
	return string.format("Year %d, Month %d, Week %d", y, m, w)
end

Calendar.WEEKS_PER_YEAR = WPY

return Calendar
