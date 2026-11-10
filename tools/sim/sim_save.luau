-- Saves (docs/ARCHITECTURE.md 7.6): a player builds, a villager moves in, a driftling joins, then leaves (saved, lock
-- released) and rejoins to the very same profile; leaving mid-expedition brings the party home with the loot; a save
-- under another server's live lock is never overwritten; a join waits out another server's lock and then takes over;
-- a corrupt record still loads into a valid profile; a version 4 save (the game studio) starts a fresh island
-- keeping the founder's look and the settings.
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
local Schema = H.sharedServer("Logic.Schema")
local STORE = Tuning.DataStoreName .. "/global" -- the fake engine keys stores by name and scope
local function record(userId)
	local st = E.cloud.stores[STORE]
	return st and st["u_" .. userId]
end
local function seed(userId, value)
	E.cloud.stores[STORE] = E.cloud.stores[STORE] or {}
	E.cloud.stores[STORE]["u_" .. userId] = { value = value, meta = {}, userIds = {}, version = 1, created = E.SIM.now, updated = E.SIM.now }
end
local function placeAll(p, ids)
	local prof = H.profile(p)
	for _, id in ids do
		local pr = Street.plot(prof.tier)
		local done = false
		for z = pr.z1 - 2, pr.z0 + 1, -1 do
			for x = pr.x1 - 2, pr.x0 + 1, -1 do
				if not done and Plot.fits(prof.tier, prof.plot.placed, id, x, z, 0) then
					local r = H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 })
					H.expect(r.ok, "save", "place " .. id, tostring(r.err))
					done = true
				end
			end
		end
	end
end

------------------------------------------------------------------ play, leave, rejoin
E.phase = "play"
local p = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
H.expect(not H.smod("DataService").usingMemory(), "save", "the DataStore is used (not the memory fallback)")
local prof = H.profile(p)
prof.shells, prof.wood = 5000, 500
placeAll(p, { "patch", "tent", "nest", "lumber", "stall", "flowers" })
E.runUntil(function()
	return #prof.folk >= 1
end, Tuning.TurnSeconds + 3, 0.1)
H.expect(#prof.folk == 1, "save", "a villager moved in", tostring(#prof.folk))
table.insert(prof.pals, { id = prof.nextId, sp = "gullfin", lvl = 3, xp = 4, work = 0, muts = { "angler2", "lazy" } }) -- (its mutations kept through the save)
prof.nextId += 1
prof.seen.gullfin = 2
prof.founder.shirt = 5
prof.islets = 1
local r0 = H.req(p, "plot.upgrade", { i = 1 })
H.expect(r0.ok and prof.plot.placed[1].lvl == 2, "save", "the patch upgraded", tostring(r0.err))
-- the stores never stop: food stops (nobody eats nothing made) so the snapshot is stable
for _, v in prof.folk do
	v.work = 0
end
prof.food = 0
H.push(p, 0.5)
local before = E.deepCopy(H.profile(p))
E.phase = "leave"
E.removePlayer(p, "leave")
E.run(2)
local rec = record(9201)
H.expect(rec ~= nil and type(rec.value) == "table" and type(rec.value.data) == "table", "save", "the profile is saved on leave")
H.expect(rec ~= nil and rec.value.lock == nil, "save", "the lock is released on leave")
local freed = E.workspace.Plots:FindFirstChild("Plot_1")
H.expect(freed ~= nil and freed:GetAttribute("Owner") == 0 and freed:FindFirstChild("EmptyLot", true) ~= nil, "save", "the island is freed: open water again")
E.phase = "rejoin"
local p2 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
local after = E.deepCopy(H.profile(p2))
-- the clock ran a little since: the day's making and eating (nothing happens offline)
after.shells, after.food, after.wood, after.stats.earned = before.shells, before.food, before.wood, before.stats.earned
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved", tostring(diff))
H.expect(H.session(p2).plot == 1, "save", "island 1 again")
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ leaving mid-expedition
E.phase = "leave-exp"
local pp = H.profile(p2)
pp.food = 100
local res = H.req(p2, "exp.start", { isle = 1, party = "" })
H.expect(res.ok, "save", "an expedition sets sail", tostring(res.err))
H.req(p2, "exp.next", {})
local s2 = H.session(p2)
local gathered = s2.exp and E.deepCopy(s2.exp.loot)
local sh0, food0 = pp.shells, pp.food
E.removePlayer(p2, "leave")
E.run(2)
rec = record(9201)
local saved = rec and rec.value.data
H.expect(saved ~= nil and gathered ~= nil and saved.food >= food0 + gathered.food - 1, "save", "the loot gathered came home when the player left", string.format("%s food saved, %s + %s", saved and saved.food, food0, gathered and gathered.food))
H.expect(saved ~= nil and saved.shells >= sh0 + (gathered and gathered.shells or 0) - 1, "save", "and its shells", tostring(saved and saved.shells))
local p3 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
H.expect(H.session(p3) and H.session(p3).exp == nil, "save", "no expedition after a rejoin")
H.checkProfile(p3, "leave-exp")

------------------------------------------------------------------ another server's live lock
E.phase = "foreign-lock"
rec = record(9201)
rec.value.lock = { job = "another-server", t = math.floor(E.SIM.now) }
rec.value.data.shells = 777
local DataService = H.smod("DataService")
local co = coroutine.create(function()
	DataService.save(9201, H.profile(p3), false)
end)
E.tagThread(co, E.serverCtx)
E.resume(co)
E.run(1)
rec = record(9201)
H.expect(rec.value.data.shells == 777, "save", "a save never overwrites another server's live lock", tostring(rec.value.data.shells))
H.expect(rec.value.lock.job == "another-server", "save", "their lock stays")
rec.value.lock = nil

------------------------------------------------------------------ a join that waits out a lock
E.phase = "takeover"
seed(9203, { data = { v = 5, shells = 12345, food = 77, wood = 66, tier = 2 }, lock = { job = "crashed-server", t = math.floor(E.SIM.now) } })
local q = H.addPlayer({ userId = 9203, name = "Waiter" })
E.run(2)
H.expect(H.session(q) == nil, "save", "the join waits while another server holds the lock")
E.run(Tuning.LoadRetries * 4 + 4)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready, "save", "then takes over")
if sq then
	H.expect(math.floor(sq.profile.shells) >= 12345 and sq.profile.tier == 2, "save", "with the saved shells and the island's size", string.format("%s %s", tostring(sq.profile.shells), tostring(sq.profile.tier)))
	H.expect(record(9203).value.lock.job ~= "crashed-server", "save", "the lock is ours now")
	H.checkProfile(q, "takeover")
end

------------------------------------------------------------------ a corrupt record
E.phase = "corrupt"
seed(9204, { data = {
	v = 5,
	shells = "lots",
	food = -5,
	tier = 99,
	folk = { 1, 2, "x", { id = 7, name = 5, work = 999 } },
	pals = { { id = 7, sp = "dragon" }, { id = 8, sp = "clawdle", lvl = 1e9, work = 3 } },
	plot = { placed = { { uid = 3, id = "patch", x = 999, z = 0, rot = 0 }, { uid = 4, id = "castle", x = 0, z = 0 } } },
	seen = { clawdle = 9, nothing = 1 },
	islets = 42,
} })
local c = H.addPlayer({ userId = 9204, name = "Glitch" })
E.run(3)
local cp = H.profile(c)
H.expect(cp ~= nil, "save", "a corrupt record still loads")
if cp then
	H.expect(cp.shells == Tuning.StartShells and cp.food == 0 and cp.tier == 3, "save", "into a valid profile", string.format("%s %s %d", tostring(cp.shells), tostring(cp.food), cp.tier))
	local q = cp.plot.placed[1]
	H.expect(#cp.plot.placed == 1 and q.id == "patch" and H.sharedServer("Logic.Plot").fits(cp.tier, {}, q.id, q.x, q.z, q.rot), "save", "the patch off the island moved onto it, the unknown piece gone", string.format("%d pieces", #cp.plot.placed))
	H.expect(#cp.folk == 1 and cp.folk[1].work == 0 and #cp.pals == 1 and cp.pals[1].id == 8 and cp.islets == 42, "save", "only what makes sense kept", string.format("%d folk, %d pals, %d islands", #cp.folk, #cp.pals, cp.islets))
	H.checkProfile(c, "corrupt")
	H.checkMirror(c, "corrupt")
end

------------------------------------------------------------------ an old save (version 4: the game studio)
E.phase = "old-save"
seed(9205, { data = {
	v = 4,
	coins = 99999,
	office = 2,
	team = { { id = 4, name = "Ada Byte", look = { skin = 2, hair = 3, style = 1, shirt = 4 }, desk = 1 } },
	games = { { title = "Old Game" } },
	founder = { skin = 3, hair = 2, style = 4, shirt = 6 },
	settings = { pixel = "low" },
	plot = { owned = { oak = true }, placed = { { id = "gnome", x = 10, z = 10, rot = 0 } } },
	createdAt = 1234,
} })
local o = H.addPlayer({ userId = 9205, name = "Veteran" })
E.run(3)
local op = H.profile(o)
H.expect(op ~= nil and op.v == Schema.VERSION, "save", "a version 4 save loads as an island", tostring(op and op.v))
if op then
	H.expect(op.founder.shirt == 6 and op.settings.pixel == "low" and op.createdAt == 1234, "save", "the founder's look, the settings and the start kept")
	H.expect(op.coins == nil and op.team == nil and op.games == nil and #op.plot.placed == 0 and op.tier == 1 and op.tut == 1, "save", "the studio gone: a fresh island with the tips")
	H.expect(op.shells == Tuning.StartShells, "save", "the starting shells", tostring(op.shells))
	H.checkProfile(o, "old-save")
	H.checkMirror(o, "old-save")
end

report(E, H)
