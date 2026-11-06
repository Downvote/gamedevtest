-- The game clock (GAME_DESIGN 3, 8; docs/ARCHITECTURE.md 7.4): a week every Tuning.WeekSec, held while the client
-- signals pause (every key it set, until each is let go; junk ignored), salaries and rent on a month's first week,
-- new candidates each month, and the awards night after a year's last week (Critics' Choice, Game of the Year).
local E = require("./loader")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.dt = 0.05
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Dev = H.sharedServer("Logic.Dev")
local Crew = H.sharedServer("Logic.Crew")

local p = H.addPlayer({ userId = 9301, name = "Clock" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)

-- Steps until the next game week has been processed (the session's clock just turned over).
local function waitTick()
	local w = prof.week
	E.runUntil(function()
		return prof.week ~= w
	end, Tuning.WeekSec * 3, 0.05)
end

------------------------------------------------------------------ the pace
E.phase = "pace"
waitTick()
local w0 = prof.week
E.run(Tuning.WeekSec * 4 + Tuning.WeekSec / 2)
H.expect(prof.week == w0 + 4, "clock", "a week every WeekSec", string.format("%d -> %d", w0, prof.week))

------------------------------------------------------------------ pause
E.phase = "pause"
waitTick()
w0 = prof.week
H.signal(p, "pause", { key = "wizard", on = true })
H.signal(p, "pause", { key = "review", on = true })
E.run(Tuning.WeekSec * 3)
H.expect(prof.week == w0, "clock", "the clock holds while paused", string.format("%d -> %d", w0, prof.week))
H.expect(H.view(p).paused == true, "clock", "the view says paused")
H.signal(p, "pause", { key = "wizard", on = false })
E.run(Tuning.WeekSec * 2)
H.expect(prof.week == w0, "clock", "still held while one key is on", string.format("%d -> %d", w0, prof.week))
H.signal(p, "pause", { key = "review", on = false })
E.run(Tuning.WeekSec * 2 + 0.3)
H.expect(prof.week > w0, "clock", "it runs again once every key is off", string.format("%d -> %d", w0, prof.week))
H.expect(H.view(p).paused == false, "clock", "the view says running")
-- junk pause signals are ignored
H.rawSignal(p, "pause", "x")
H.rawSignal(p, "pause", { key = string.rep("k", 100), on = true })
H.rawSignal(p, "pause", { key = 5, on = true })
H.rawSignal(p, "nonsense", { key = "a", on = true })
E.run(0.3)
H.expect(next(H.session(p).paused) == nil, "clock", "junk pause signals hold nothing")
for i = 1, 6 do
	H.signal(p, "pause", { key = "k" .. i, on = true })
end
E.run(0.3)
local held = 0
for _ in H.session(p).paused do
	held += 1
end
H.expect(held <= 4, "clock", "at most four pause keys", tostring(held))
for i = 1, 6 do
	H.signal(p, "pause", { key = "k" .. i, on = false })
end
E.run(0.3)
H.expect(next(H.session(p).paused) == nil, "clock", "every key let go")

------------------------------------------------------------------ pay day
E.phase = "payday"
waitTick()
-- the next tick processes week 3, the one after week 4: a month's first week
prof.week = 3
prof.money = 50000
waitTick()
local money0 = prof.money
local month0 = prof.candMonth
local n0 = #fx
waitTick()
local bill = Crew.payroll(prof.staff) + Tuning.Offices[prof.office].rent
E.run(0.2) -- the Fx message's way to the client
H.expect(prof.money == money0 - bill, "clock", "salaries and rent on the month's first week", string.format("paid %d, bill %d", money0 - prof.money, bill))
local paid = false
for i = n0 + 1, #fx do
	for _, e in fx[i].events or {} do
		if e.kind == "pay" and e.amount == bill then
			paid = true
		end
	end
end
H.expect(paid, "clock", "the client is told what was paid")
H.expect(prof.candMonth ~= month0 and #prof.candidates == Tuning.Candidates, "clock", "new candidates for the new month", string.format("%d -> %d", month0, prof.candMonth))

------------------------------------------------------------------ awards
E.phase = "awards"
local function plant(week, total, title)
	local proj = Dev.newProject("puzzle", "animals", "pc", "small", "fun", title, week)
	local r = Dev.release(proj, prof.nextRelease, week, { total // 4, total // 4, total // 4, total - 3 * (total // 4) }, total, "great", 0)
	r.onSale = false
	prof.nextRelease += 1
	table.insert(prof.releases, r)
end
-- Year 1: a 30 is a Critics' Choice
waitTick()
plant(20, 30, "Kitty Blocks")
prof.week = 46
prof.fans = 1000
waitTick()
local m1, f1 = prof.money, prof.fans
local n1 = #fx
waitTick() -- week 47: the year's last
E.run(0.2)
H.expect(#prof.awards == 1 and prof.awards[1].kind == "pick" and prof.awards[1].year == 1, "clock", "a Critics' Choice for a 30", tostring(prof.awards[1] and prof.awards[1].kind))
H.expect(prof.money == m1 + Tuning.PickMoney * 1, "clock", "its prize", tostring(prof.money - m1))
H.expect(prof.fans == f1 + math.floor(f1 * Tuning.PickFans + 0.5), "clock", "its fans", tostring(prof.fans - f1))
local told = false
for i = n1 + 1, #fx do
	for _, e in fx[i].events or {} do
		if e.kind == "award" and e.award == "pick" and e.title == "Kitty Blocks" then
			told = true
		end
	end
end
H.expect(told, "clock", "the client hears of the award")
-- the awards card holds the clock until it is dismissed
H.expect(H.view(p).paused == true or next(H.session(p).paused) ~= nil, "clock", "the awards card holds the clock")
H.expect(H.dismissCards(p) >= 1, "clock", "the awards card is dismissed with its button")
E.run(0.3)
H.expect(next(H.session(p).paused) == nil, "clock", "the clock runs again once the card is gone")
-- Year 2: a 36 is Game of the Year (week 48 is a month start: the pay is counted in)
waitTick()
plant(60, 36, "Galaxy Blocks")
prof.week = 94
waitTick()
local m2, f2 = prof.money, prof.fans
waitTick() -- week 95
H.expect(#prof.awards == 2 and prof.awards[2].kind == "goty" and prof.awards[2].year == 2, "clock", "Game of the Year for a 36", tostring(prof.awards[2] and prof.awards[2].kind))
H.expect(prof.money == m2 + Tuning.GotyMoney * 2, "clock", "its prize, times the year", tostring(prof.money - m2))
H.expect(prof.fans == f2 + math.floor(f2 * Tuning.GotyFans + 0.5), "clock", "its fans", tostring(prof.fans - f2))
E.run(0.3)
H.dismissCards(p)
-- Year 3: nothing good enough, a quiet night
waitTick()
plant(100, 20, "Bunny Tales")
prof.week = 142
waitTick()
waitTick()
H.expect(#prof.awards == 2, "clock", "no award for a 20", tostring(#prof.awards))
E.run(0.4)
H.checkProfile(p, "clock")
H.checkMirror(p, "clock")

report(E, H)
