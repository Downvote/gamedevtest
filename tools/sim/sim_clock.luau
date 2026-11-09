-- The idea loop's clocks (GAME_DESIGN 3, 4, 6, 7; docs/ARCHITECTURE.md 7.4): an idea every Studio.rollEvery seconds,
-- faster after the speed upgrade, on through open menus and cards (nothing holds it any more); the full board's rule
-- (a rarer idea takes the commonest one's place, a commoner one is dropped but still counted in the Index); the
-- income paid every second at the games' rate; a microgame left open past Tuning.MicroMaxSec dropped; two studios
-- each on their own clock.
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
local Ideas = H.sharedServer("Logic.Ideas")
local Studio = H.sharedServer("Logic.Studio")

local p = H.addPlayer({ userId = 9301, name = "Clock" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)
local s = H.session(p)

local function rollsDuring(sec: number): number
	local r0 = prof.stats.rolls
	E.run(sec)
	return prof.stats.rolls - r0
end

------------------------------------------------------------------ the pace
E.phase = "pace"
E.runUntil(function()
	return prof.stats.rolls >= 1
end, Tuning.RollBase + 2, 0.05)
local n = rollsDuring(Tuning.RollBase * 4 + 0.2)
H.expect(n == 4, "clock", "an idea every RollBase seconds", tostring(n))
-- the speed upgrade: faster ideas
prof.coins = 1e9
for _ = 1, 10 do
	H.req(p, "upgrade.buy", { k = "speed" })
end
H.expect(prof.upgrades.speed == 10, "clock", "ten speed levels bought", tostring(prof.upgrades.speed))
local every = Studio.rollEvery(prof)
H.expect(math.abs(every - Tuning.RollBase * Tuning.RollStep ^ 10) < 1e-9, "clock", "rollEvery follows the level", tostring(every))
n = rollsDuring(every * 6 + 0.1)
H.expect(n >= 5 and n <= 7, "clock", "ideas at the faster pace", string.format("%d in %.1fs", n, every * 6))
H.expect(math.abs(H.view(p).rollEvery - every) < 1e-9, "clock", "the view says the pace")

------------------------------------------------------------------ menus and cards hold nothing
E.phase = "open-menus"
H.openPanel(p, "index")
E.run(0.3)
n = rollsDuring(every * 3 + 0.1)
H.expect(n >= 2, "clock", "ideas keep coming while a menu is open", tostring(n))
H.closePanel(p)
H.signal(p, "pause", { key = "menu", on = true })
n = rollsDuring(every * 3 + 0.1)
H.expect(n >= 2, "clock", "the old pause signal holds nothing", tostring(n))

------------------------------------------------------------------ the full board
E.phase = "board"
prof.ideas = {}
for _ = 1, Tuning.BoardSize do
	table.insert(prof.ideas, { id = "school", mod = "plain" })
end
H.push(p, 0.2)
local f0 = #fx
local rolls0 = prof.stats.rolls
local found0 = 0
for _, c in prof.found do
	found0 += c
end
E.run(every * 30)
local bad = 0
local dropped, replaced = 0, 0
-- a replica of the board, replayed from the ideas the client was told of
local replica = {}
for _ = 1, Tuning.BoardSize do
	table.insert(replica, { id = "school", mod = "plain" })
end
for i = f0 + 1, #fx do
	local m = fx[i]
	if m.kind == "idea" then
		local nIn = Ideas.oneIn(m.card)
		local least = math.huge
		for _, c in replica do
			least = math.min(least, Ideas.oneIn(c))
		end
		if m.slot == 0 then
			dropped += 1
			if nIn > least then
				bad += 1
			end
		else
			replaced += 1
			if not m.replaced or nIn <= Ideas.oneIn(m.replaced) or Ideas.oneIn(replica[m.slot]) ~= least then
				bad += 1
			end
			replica[m.slot] = m.card
		end
	end
end
H.expect(#prof.ideas == Tuning.BoardSize, "clock", "the board stays at BoardSize", tostring(#prof.ideas))
H.expect(bad == 0, "clock", "only a rarer idea takes a place; only a commoner one is dropped", tostring(bad))
H.expect(dropped + replaced == prof.stats.rolls - rolls0, "clock", "every idea on a full board is dropped or replaces one", string.format("%d + %d of %d", dropped, replaced, prof.stats.rolls - rolls0))
local found1 = 0
for _, c in prof.found do
	found1 += c
end
H.expect(found1 - found0 == prof.stats.rolls - rolls0, "clock", "the Index counts every idea, dropped ones too", string.format("%d of %d", found1 - found0, prof.stats.rolls - rolls0))

------------------------------------------------------------------ the income
E.phase = "income"
prof.coins = 0
prof.rate = 12.5
H.push(p, 0.2)
E.run(1.05)
local c0 = prof.coins
E.run(10)
local got = prof.coins - c0
H.expect(got >= 12.5 * 10 - 13 and got <= 12.5 * 10 + 13, "clock", "about ten seconds of income at 12.5 a second", tostring(got))
H.expect(prof.stats.earned >= got, "clock", "the earnings stat follows")

------------------------------------------------------------------ a microgame left open
E.phase = "micro-open"
prof.ideas = { { id = "action", mod = "plain" }, { id = "puzzle", mod = "plain" }, { id = "space", mod = "plain" } }
H.push(p, 0.2)
local res = H.req(p, "game.make", { a = 1, b = 2, c = 3 })
H.expect(res.ok, "clock", "a game to play", tostring(res.err))
res = H.req(p, "micro.start", { slot = 2 })
H.expect(res.ok and s.micro ~= nil, "clock", "a microgame started and left open")
local token = res.data and res.data.token or 0
E.run(Tuning.MicroMaxSec + 1)
H.expect(s.micro == nil, "clock", "dropped after MicroMaxSec")
res = H.req(p, "micro.finish", { token = token, won = 1 })
H.expect(not res.ok and prof.project.won[2] == -1, "clock", "its late finish refused: nothing recorded", tostring(res.err))

------------------------------------------------------------------ two studios, two clocks
E.phase = "two"
local q = H.addPlayer({ userId = 9302, name = "Tick" })
E.run(1)
local qp = H.profile(q)
local r0, rq0 = prof.stats.rolls, qp.stats.rolls
E.run(Tuning.RollBase * 2 + 0.5)
H.expect(qp.stats.rolls - rq0 >= 2, "clock", "the new studio rolls on its own clock", tostring(qp.stats.rolls - rq0))
H.expect(prof.stats.rolls - r0 >= 2 * Tuning.RollBase / every - 1, "clock", "the first keeps its faster pace", tostring(prof.stats.rolls - r0))
H.checkProfile(p, "clock")
H.checkMirror(p, "clock")
H.checkProfile(q, "clock-2")

report(E, H)
