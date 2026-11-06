-- Saves (docs/ARCHITECTURE.md 8): a player plays, leaves (saved, lock released) and rejoins to the very same profile;
-- a save under another server's live lock is never overwritten; a join waits out another server's lock and then takes
-- over; a corrupt record still loads into a valid profile.
local E = require("./loader")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.dt = 0.1
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
local res = H.req(p, "project.start", { genre = "adventure", topic = "pirates", platform = "pocket", size = "small", focus = "ideas", seed = 3 })
H.expect(res.ok, "save", "project.start", tostring(res.err))
E.run(Tuning.WeekSec * 3 + 0.3)
local prof = H.profile(p)
prof.rp = 42
prof.matches["action|space"] = "good"
prof.genres.rpg = true
H.signal(p, "pause", { key = "sim", on = true })
E.run(0.5)
local before = E.deepCopy(H.profile(p))
H.expect(before.project ~= nil and before.project.weeksDone >= 3, "save", "a project in the works", tostring(before.project and before.project.weeksDone))
E.phase = "leave"
E.removePlayer(p, "leave")
E.run(2)
local rec = record(9201)
H.expect(rec ~= nil and type(rec.value) == "table" and type(rec.value.data) == "table", "save", "the profile is saved on leave")
H.expect(rec ~= nil and rec.value.lock == nil, "save", "the lock is released on leave")
H.expect(not E.workspace.Plots:FindFirstChild("Plot_1"), "save", "the plot is freed")
E.phase = "rejoin"
local p2 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
local after = H.profile(p2)
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved", tostring(diff))
H.expect(H.session(p2).plot == 1, "save", "plot 1 again")
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ another server's live lock
E.phase = "foreign-lock"
rec = record(9201)
rec.value.lock = { job = "another-server", t = math.floor(E.SIM.now) }
rec.value.data.money = 777
local DataService = H.smod("DataService")
local okSave = nil
local co = coroutine.create(function()
	okSave = DataService.save(9201, H.profile(p2), false)
end)
E.tagThread(co, E.serverCtx)
E.resume(co)
E.run(1)
rec = record(9201)
H.expect(rec.value.data.money == 777, "save", "a save never overwrites another server's live lock", tostring(rec.value.data.money))
H.expect(rec.value.lock.job == "another-server", "save", "their lock stays")
rec.value.lock = nil

------------------------------------------------------------------ a join that waits out a lock
E.phase = "takeover"
seed(9203, { data = { money = 12345, fans = 50 }, lock = { job = "crashed-server", t = math.floor(E.SIM.now) } })
local q = H.addPlayer({ userId = 9203, name = "Waiter" })
E.run(2)
H.expect(H.session(q) == nil, "save", "the join waits while another server holds the lock")
E.run(Tuning.LoadRetries * 4 + 4)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready, "save", "then takes over")
if sq then
	H.expect(sq.profile.money == 12345 and sq.profile.fans == 50, "save", "with the saved money and fans", string.format("%s %s", tostring(sq.profile.money), tostring(sq.profile.fans)))
	H.expect(record(9203).value.lock.job ~= "crashed-server", "save", "the lock is ours now")
	H.checkProfile(q, "takeover")
end

------------------------------------------------------------------ a corrupt record
E.phase = "corrupt"
seed(9204, { data = { money = "lots", staff = { 1, 2, "x" }, office = 99, releases = "nope", week = -5, project = { phase = 7 } } })
local c = H.addPlayer({ userId = 9204, name = "Glitch" })
E.run(3)
local cp = H.profile(c)
H.expect(cp ~= nil, "save", "a corrupt record still loads")
if cp then
	H.expect(cp.money == Tuning.StartMoney and #cp.staff >= 1 and cp.office >= 1 and cp.office <= #Tuning.Offices and cp.week >= 0, "save", "into a valid profile", string.format("%s %d %d %d", tostring(cp.money), #cp.staff, cp.office, cp.week))
	H.checkProfile(c, "corrupt")
	H.checkMirror(c, "corrupt")
end

report(E, H)
