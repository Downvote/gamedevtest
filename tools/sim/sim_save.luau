-- Saves (docs/ARCHITECTURE.md 7.6): a player plays, leaves (saved, lock released) and rejoins to the very same
-- profile; a save under another server's live lock is never overwritten; a join waits out another server's lock and
-- then takes over; a corrupt record still loads into a valid profile; a version 2 save (the old studio) loads into the
-- idea loop with its room, crew, founder and decor.
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
local STORE = Tuning.DataStoreName .. "/global" -- the fake engine keys stores by name and scope
local function record(userId)
	local st = E.cloud.stores[STORE]
	return st and st["u_" .. userId]
end
local function seed(userId, value)
	E.cloud.stores[STORE] = E.cloud.stores[STORE] or {}
	E.cloud.stores[STORE]["u_" .. userId] = { value = value, meta = {}, userIds = {}, version = 1, created = E.SIM.now, updated = E.SIM.now }
end

------------------------------------------------------------------ play, leave, rejoin
E.phase = "play"
local p = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
H.expect(not H.smod("DataService").usingMemory(), "save", "the DataStore is used (not the memory fallback)")
local prof = H.profile(p)
E.runUntil(function()
	return #prof.ideas >= 6
end, Tuning.RollBase * 8, 0.2)
-- a launched game, then a second in the works with one minigame played
local function play(won: number)
	local r = H.req(p, "micro.start", { slot = 1 })
	E.run(Tuning.MicroMinSec + 0.2)
	H.req(p, "micro.finish", { token = r.data and r.data.token or 0, won = won })
end
local res = H.req(p, "game.make", { a = 1, b = 2, c = 3 })
H.expect(res.ok, "save", "game.make", tostring(res.err))
for slot = 1, 3 do
	local r = H.req(p, "micro.start", { slot = slot })
	E.run(Tuning.MicroMinSec + 0.2)
	H.req(p, "micro.finish", { token = r.data and r.data.token or 0, won = 1 })
end
res = H.req(p, "game.launch", {})
H.expect(res.ok and prof.rate > 0, "save", "a game launched", tostring(res.err))
res = H.req(p, "game.make", { a = 1, b = 2, c = 3 })
H.expect(res.ok, "save", "a second game in the works", tostring(res.err))
play(1)
prof.coins = 4242
prof.upgrades.luck = 3
prof.founder.shirt = 5
prof.plot.owned.gnome = true
E.run(0.5)
-- the clocks never stop: snapshot and leave in the same step
local before = E.deepCopy(H.profile(p))
H.expect(before.project ~= nil and before.project.won[1] == 1 and #before.games == 1, "save", "a game launched and one in the works")
E.phase = "leave"
E.removePlayer(p, "leave")
E.run(2)
local rec = record(9201)
H.expect(rec ~= nil and type(rec.value) == "table" and type(rec.value.data) == "table", "save", "the profile is saved on leave")
H.expect(rec ~= nil and rec.value.lock == nil, "save", "the lock is released on leave")
local freed = E.workspace.Plots:FindFirstChild("Plot_1")
H.expect(freed ~= nil and freed:GetAttribute("Owner") == 0 and freed:FindFirstChild("EmptyLot", true) ~= nil and freed:FindFirstChild("Office", true) == nil, "save", "the plot is freed: an empty lot again")
E.phase = "rejoin"
local p2 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
local after = E.deepCopy(H.profile(p2))
-- the games have earned since the rejoin (nothing happens offline: only since)
local earned = after.coins - before.coins
H.expect(earned >= 0 and earned <= before.rate * 4 + 1, "save", "the coins are the saved ones plus what was earned since the rejoin", string.format("+%s", tostring(earned)))
after.coins, after.stats.earned = before.coins, before.stats.earned
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved", tostring(diff))
H.expect(H.session(p2).plot == 1, "save", "plot 1 again")
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ another server's live lock
E.phase = "foreign-lock"
rec = record(9201)
rec.value.lock = { job = "another-server", t = math.floor(E.SIM.now) }
rec.value.data.coins = 777
local DataService = H.smod("DataService")
local okSave = nil
local co = coroutine.create(function()
	okSave = DataService.save(9201, H.profile(p2), false)
end)
E.tagThread(co, E.serverCtx)
E.resume(co)
E.run(1)
rec = record(9201)
H.expect(rec.value.data.coins == 777, "save", "a save never overwrites another server's live lock", tostring(rec.value.data.coins))
H.expect(rec.value.lock.job == "another-server", "save", "their lock stays")
rec.value.lock = nil

------------------------------------------------------------------ a join that waits out a lock
E.phase = "takeover"
seed(9203, { data = { v = 3, coins = 12345, upgrades = { speed = 2, luck = 1 } }, lock = { job = "crashed-server", t = math.floor(E.SIM.now) } })
local q = H.addPlayer({ userId = 9203, name = "Waiter" })
E.run(2)
H.expect(H.session(q) == nil, "save", "the join waits while another server holds the lock")
E.run(Tuning.LoadRetries * 4 + 4)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready, "save", "then takes over")
if sq then
	H.expect(sq.profile.coins == 12345 and sq.profile.upgrades.speed == 2, "save", "with the saved coins and upgrades", string.format("%s %s", tostring(sq.profile.coins), tostring(sq.profile.upgrades.speed)))
	H.expect(record(9203).value.lock.job ~= "crashed-server", "save", "the lock is ours now")
	H.checkProfile(q, "takeover")
end

------------------------------------------------------------------ a corrupt record
E.phase = "corrupt"
seed(9204, { data = { v = 3, coins = "lots", team = { 1, 2, "x" }, office = 99, games = "nope", ideas = { { id = "chess", mod = "plain" } }, project = { won = 7 } } })
local c = H.addPlayer({ userId = 9204, name = "Glitch" })
E.run(3)
local cp = H.profile(c)
H.expect(cp ~= nil, "save", "a corrupt record still loads")
if cp then
	H.expect(cp.coins == Tuning.StartCoins and #cp.team >= 1 and cp.office >= 1 and cp.office <= 3 and #cp.games == 0 and cp.project == nil, "save", "into a valid profile", string.format("%s %d %d", tostring(cp.coins), #cp.team, cp.office))
	H.checkProfile(c, "corrupt")
	H.checkMirror(c, "corrupt")
end

------------------------------------------------------------------ an old save (version 2: the old studio)
E.phase = "old-save"
seed(9205, { data = {
	v = 2,
	money = 99999,
	fans = 5000,
	week = 200,
	office = 2,
	staff = { { id = 4, name = "Ada Byte", look = { skin = 2, hair = 3, style = 1, shirt = 4 }, desk = 1 } },
	releases = { { title = "Old Game" } },
	founder = { skin = 3, hair = 2, style = 4, shirt = 6 },
	plot = { owned = { oak = true }, placed = {} },
} })
local o = H.addPlayer({ userId = 9205, name = "Veteran" })
E.run(3)
local op = H.profile(o)
H.expect(op ~= nil and op.v == 3, "save", "a version 2 save loads into the idea loop", tostring(op and op.v))
if op then
	H.expect(op.office == 2 and op.team[1].name == "Ada Byte" and op.founder.shirt == 6 and op.plot.owned.oak == true, "save", "the room, the crew (the idea team now), the founder and the decor kept")
	H.expect(op.coins >= Tuning.StartCoins and op.money == nil and op.releases == nil, "save", "the old studio's money and releases gone")
	H.checkProfile(o, "old-save")
	H.checkMirror(o, "old-save")
end

report(E, H)
