-- The island's clock (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 7.4): a day every Tuning.DaySeconds while the player is
-- here, open menus and Build mode holding nothing; what a day makes and eats matching Island.rates (to a tick); the
-- stores reaching the client every second (Fx tick); the food running out (everything at half, the shops shut, the
-- chip red) and coming back; a villager moving in only into a free bed with the charm high enough; the training
-- yard training the resting; an expedition's party neither working nor eating; two islands each on their own clock.
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
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Island = H.sharedServer("Logic.Island")

local p = H.addPlayer({ userId = 9301, name = "Clock" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)
local s = H.session(p)

local function place(id)
	local pr = Street.plot(prof.tier)
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if Plot.fits(prof.tier, prof.plot.placed, id, x, z, 0) then
				return H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 })
			end
		end
	end
	return { ok = false, err = "blocked" }
end
local function count(kind, i0)
	local n = 0
	for i = i0 + 1, #fx do
		if fx[i].kind == kind then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------ the day's pace
E.phase = "pace"
prof.shells, prof.wood = 20000, 2000
for _, id in { "patch", "patch", "lumber", "tent", "hut", "nest", "stall", "flowers", "palm" } do
	local r = place(id)
	H.expect(r.ok, "clock", "place " .. id, tostring(r.err))
end
local d0 = prof.day
E.runUntil(function()
	return prof.day > d0
end, Tuning.DaySeconds + 2, 0.05)

local t0 = E.SIM.now
E.run(0.3) -- (the first day's Fx on its way)
local f0 = #fx
E.runUntil(function()
	return prof.day >= d0 + 3
end, Tuning.DaySeconds * 3 + 3, 0.05)
local took = E.SIM.now - t0
H.expect(math.abs(took - Tuning.DaySeconds * 2) < 0.6, "clock", "a day every DaySeconds", string.format("two days in %.2fs", took))
E.run(0.3)
H.expect(count("day", f0) == 2, "clock", "an Fx day each", tostring(count("day", f0)))
H.expect(math.abs(count("tick", f0) - took) <= 2, "clock", "an Fx tick every second", string.format("%d in %.1fs", count("tick", f0), took))
H.expect(#prof.folk >= 2, "clock", "villagers moved into the beds", tostring(#prof.folk))

------------------------------------------------------------------ making and eating to the rates
E.phase = "rates"
prof.food = 500
H.push(p, 0.2)
local r = Island.rates(prof, s.away)
local food0, wood0, sh0 = prof.food, prof.wood, prof.shells
local folk0 = #prof.folk
E.run(10)
local k = 10 / Tuning.DaySeconds
H.expect(#prof.folk == folk0, "rates", "(nobody new moved in meanwhile)")
H.expect(math.abs((prof.food - food0) - r.food * k) <= math.abs(r.food) * 0.02 + 0.5, "rates", "food to the day's rate", string.format("%.2f vs %.2f", prof.food - food0, r.food * k))
H.expect(math.abs((prof.wood - wood0) - r.wood * k) <= r.wood * 0.02 + 0.5, "rates", "wood to the day's rate", string.format("%.2f vs %.2f", prof.wood - wood0, r.wood * k))
H.expect(math.abs((prof.shells - sh0) - r.shells * k) <= r.shells * 0.02 + 0.5, "rates", "shells to the day's rate (the stall sells to visitors)", string.format("%.2f vs %.2f", prof.shells - sh0, r.shells * k))
H.expect(r.shells > 0, "rates", "the stall makes shells", tostring(r.shells))
local v = H.view(p)
H.expect(v ~= nil and math.abs(v.rates.food - r.food) < 1e-6 and math.abs(v.rates.shells - r.shells) < 1e-6, "rates", "the view says the rates")
H.expect(v ~= nil and math.abs(v.food - prof.food) <= math.abs(r.food) / Tuning.DaySeconds * 1.5 + 1, "rates", "the view's food follows the ticks", string.format("%s vs %s", v and v.food, prof.food))
H.checkMirror(p, "rates")

------------------------------------------------------------------ open menus and Build mode hold nothing
E.phase = "menus"
H.openPanel(p, "index")
E.run(0.3)
local fA = prof.food
E.run(4)
H.expect(prof.food ~= fA, "menus", "the island goes on while a menu is open")
H.closePanel(p)
H.clickNamed(p, "Menu_build", { wait = 0.3 })
local wA = prof.wood
E.run(4)
H.expect(prof.wood > wA, "menus", "and in Build mode")
H.clickNamed(p, "BuildDone", { wait = 0.3 })

------------------------------------------------------------------ hunger
E.phase = "hunger"
prof.food = 0.5
for _, q in prof.plot.placed do
	if q.id == "patch" then
		q.id = "flowers" -- (no food made: the island runs dry; whoever worked there rests)
		for _, x in prof.folk do
			if x.work == q.uid then
				x.work = 0
			end
		end
		for _, x in prof.pals do
			if x.work == q.uid then
				x.work = 0
			end
		end
	end
end
H.push(p, 0.2)
E.runUntil(function()
	return prof.food <= 0
end, 10, 0.05)
H.expect(prof.food == 0, "hunger", "the food runs out and stays at none", tostring(prof.food))
E.run(1.2)
local rh = Island.rates(prof, s.away)
H.expect(rh.shells == 0, "hunger", "the shops shut while hungry", tostring(rh.shells))
v = H.view(p)
H.expect(v ~= nil and v.food == 0 and v.rates.shells == 0, "hunger", "the view says so (the HUD goes red)")
local hud = H.buttonNamed(p, "Menu_build")
H.expect(hud ~= nil, "hunger", "the HUD stays usable")
prof.food = 100
H.push(p, 0.3)
H.expect(Island.rates(prof, s.away).shells > 0, "hunger", "fed again: the shops open")

------------------------------------------------------------------ moving in: beds and charm
E.phase = "move-in"
local beds = Island.beds(prof)
while #prof.folk < beds do
	table.insert(prof.folk, { id = prof.nextId, name = "Extra", look = { skin = 1, hair = 1, style = 1, shirt = 1 }, work = 0, lvl = 1, xp = 0, seed = 7, day = prof.day })
	prof.nextId += 1
end
H.push(p, 0.2)
local n0 = #prof.folk
local dd = prof.day
E.runUntil(function()
	return prof.day > dd
end, Tuning.DaySeconds + 2, 0.1)
H.expect(#prof.folk == n0, "move-in", "no free bed: nobody moves in", tostring(#prof.folk))
-- a free bed but not charm enough (MoveInCharm a villager)
local r1 = place("cottage")
local r2 = place("hut")
H.expect(r1.ok or r2.ok, "move-in", "a new home", tostring(r2.err))
local charm = Island.charm(prof)
H.expect(charm < Tuning.MoveInCharm * #prof.folk, "move-in", "(the charm is too low for this many)", string.format("%d < %d", charm, Tuning.MoveInCharm * #prof.folk))
dd = prof.day
E.runUntil(function()
	return prof.day > dd
end, Tuning.DaySeconds + 2, 0.1)
H.expect(#prof.folk == n0, "move-in", "not charming enough: nobody moves in", tostring(#prof.folk))
-- decor raises the charm (the island expanded for the grand pieces: the buildings where the coast changed make room)
prof.shells, prof.wood = 1e6, 1e5
for _ = 1, 2 do
	local rx = H.req(p, "island.expand", {})
	H.expect(rx.ok, "move-in", "the island expands", tostring(rx.err))
end
H.expect(prof.tier == 3, "move-in", "to its biggest", tostring(prof.tier))
H.checkProfile(p, "expanded")
H.push(p, 0.3)
local guard = 0
while Island.charm(prof) < Tuning.MoveInCharm * #prof.folk and guard < 10 do
	guard += 1
	local rr = place("statue")
	if not rr.ok then
		rr = place("lighthouse")
	end
end
H.expect(Island.charm(prof) >= Tuning.MoveInCharm * #prof.folk, "move-in", "decor raises the charm", tostring(Island.charm(prof)))
dd = prof.day
E.runUntil(function()
	return prof.day > dd
end, Tuning.DaySeconds + 2, 0.1)
H.expect(#prof.folk == n0 + 1, "move-in", "charming enough: a visitor moves in", tostring(#prof.folk))
H.checkProfile(p, "move-in")

------------------------------------------------------------------ the training yard
E.phase = "yard"
local ry = place("yard")
H.expect(ry.ok, "yard", "a training yard", tostring(ry.err))
local idle = nil
for _, x in prof.folk do
	if x.work == 0 then
		idle = x
	end
end
if idle == nil then
	idle = prof.folk[1]
	idle.work = 0
end
local xp0, lvl0 = idle.xp, idle.lvl
dd = prof.day
E.runUntil(function()
	return prof.day > dd
end, Tuning.DaySeconds + 2, 0.1)
H.expect(idle.lvl > lvl0 or idle.xp >= xp0 + Tuning.TrainXp, "yard", "a resting villager trains at dawn", string.format("lv %d xp %d -> lv %d xp %d", lvl0, xp0, idle.lvl, idle.xp))

------------------------------------------------------------------ away on an expedition
E.phase = "away"
prof.food = 500
local worker = nil
for _, x in prof.folk do
	if x.work ~= 0 then
		worker = x
	end
end
H.expect(worker ~= nil, "away", "someone is working")
if worker then
	local before = Island.rates(prof, s.away)
	local res = H.req(p, "exp.start", { isle = 1, party = "v" .. worker.id })
	H.expect(res.ok, "away", "they set sail", tostring(res.err))
	local during = Island.rates(prof, s.away)
	H.expect(during.food > before.food - 0.001 + Tuning.EatFolk - 0.001 or during.wood < before.wood or during.shells < before.shells or during.food < before.food, "away", "the island makes and eats without them", string.format("%.1f/%.1f -> %.1f/%.1f", before.food, before.wood, during.food, during.wood))
	E.run(1)
	local folkAttr = E.workspace.Plots.Plot_1:GetAttribute("Folk")
	H.expect(type(folkAttr) == "string" and string.find(folkAttr, "^" .. worker.id .. "%.") ~= nil or string.find(folkAttr, ";" .. worker.id .. "%.") ~= nil, "away", "the Folk attribute lists them")
	H.expect(string.find(folkAttr, worker.id .. "%.%d+%.%d+%.%d+%.%d+%.%d+%.1") ~= nil, "away", "marked away", folkAttr)
	H.req(p, "exp.home", {})
	E.run(0.5)
	H.expect(next(s.away) == nil, "away", "home: back at work")
end

------------------------------------------------------------------ two islands, two clocks
E.phase = "two"
local q = H.addPlayer({ userId = 9302, name = "Tock" })
E.run(2)
local sq = H.session(q)
local pq = H.profile(q)
local dq, dp = pq.day, prof.day
E.run(Tuning.DaySeconds + 1)
H.expect(pq.day == dq + 1 and prof.day == dp + 1, "two", "both islands' days turn", string.format("%d->%d, %d->%d", dq, pq.day, dp, prof.day))
H.expect(sq.dayClock >= 0 and sq.dayClock < Tuning.DaySeconds and s.dayClock >= 0 and s.dayClock < Tuning.DaySeconds, "two", "each on its own clock")
------------------------------------------------------------------ day and night
E.phase = "daynight"
-- the day and night (GAME_DESIGN 8): the island's clock grades the picture: plain by day, dark blue at night with the
-- lamps lit, bright again at dawn (UI/DayLight; with the filter off, as in this engine, Roblox's own clock follows)
do
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local DL = H.cmod(p, "Controllers.DayLight")
	local nightGrade = DL.at(0.88)
	H.expect(DL.at(0.35) == nil and nightGrade ~= nil and nightGrade.mr < 0.6 and nightGrade.lamps > 0.9, "daynight", "the grade: none at noon, dark with the lamps lit at night")
	local dusk = DL.at(0.68)
	H.expect(dusk ~= nil and dusk.mr > dusk.mb, "daynight", "a warm dusk")
	local function at(lo, hi)
		E.runUntil(function()
			local v = H.view(p)
			return v ~= nil and v.dayFrac >= lo and v.dayFrac <= hi
		end, Tuning.DaySeconds + 2, 0.05)
		E.run(0.3)
		local off = H.inClient(p, PR.tier) == "off"
		local st = H.inClient(p, DL.debugState)
		return st.grade, off, st.clock
	end
	local noon, off1, c1 = at(0.3, 0.45)
	H.expect(noon == "" and (not off1 or (c1 >= 9 and c1 <= 15)), "daynight", "plain daylight at noon", string.format("%q %s %s", noon, tostring(off1), tostring(c1)))
	local night, off2, c2 = at(0.84, 0.92)
	local mr = tonumber(string.match(night, "^(%S+)"))
	H.expect(if off2 then (c2 >= 19 or c2 <= 5) else (mr ~= nil and mr < 0.6), "daynight", "dark at night", string.format("%q %s %s", night, tostring(off2), tostring(c2)))
	local dawn, off3, c3 = at(0.08, 0.2)
	H.expect(dawn == "" and (not off3 or (c3 >= 6 and c3 <= 11)), "daynight", "bright again in the morning", string.format("%q %s %s", dawn, tostring(off3), tostring(c3)))
end

H.checkProfile(p, "end")
H.checkMirror(p, "end")
H.checkProfile(q, "end")
H.checkMirror(q, "end")

report(E, H)
