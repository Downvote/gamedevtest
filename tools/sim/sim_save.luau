-- Saves (docs/ARCHITECTURE.md 7.6): a player builds, the Tree of Life grows driftlings (one sent on to the hut, one
-- kept in the pen), the tree's levels bought, then leaves (saved, lock released) and rejoins to the very same profile;
-- a version 9 save (the wild places, the fights, the levels and a villager in a Tent) loads with its tree planted, its
-- yard's and its Tent's prices back, no villagers and its driftlings in huts and the pen; a save under another
-- server's live lock is never overwritten; a join waits out
-- another server's lock and then takes over; a corrupt record still loads into a valid profile; a version 4 save (the
-- game studio) starts a fresh island keeping the founder's look and the settings.
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
placeAll(p, { "patch", "pier", "nest", "lumber", "stall", "flowers" })
local function housed(): number
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
E.runUntil(function()
	return housed() >= 1
end, Tuning.TreeSecs[1] * 4 + 3, 0.1)
H.expect(housed() >= 1 and prof.folk == nil, "save", "a driftling grown and sent to the hut (no villagers)", tostring(housed()))
-- (one kept in the pen by the player, its mutations kept through the save)
table.insert(prof.pals, { id = prof.nextId, sp = "gullfin", home = 0, work = 0, muts = { "angler2", "lazy" }, held = 1 })
prof.nextId += 1
prof.seen.gullfin = 2
prof.founder.shirt = 5
prof.tree.luck, prof.tree.speed = 3, 2
-- (a level from before upgrades were taken out: kept through the save)
for _, q in prof.plot.placed do
	if q.id == "patch" then
		q.lvl = 2
	end
end
prof.stats.best = math.max(prof.stats.best, 2)
-- (the tree just started on its next: none grows across the rejoin)
prof.tree.t = 0
-- (the stores never stop: they are left out of the comparison)
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
after.tree.t = before.tree.t
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved", tostring(diff))
H.expect(H.session(p2).plot == 1, "save", "island 1 again")
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ a version 9 save (the wild places, the fights)
E.phase = "v9"
local p3 = p2
seed(9206, { data = {
	v = 9,
	shells = 1000,
	food = 50,
	wood = 80,
	tier = 1,
	cap = { lvl = 7, xp = 3 },
	pouch = 3,
	islets = 2,
	sea = 4242,
	wilds = 1,
	tut = 6,
	quest = 12,
	folk = { { id = 20, name = "Mira", look = { skin = 1, hair = 2, style = 1, shirt = 3 }, work = 11, lvl = 5, xp = 9, seed = 77, day = 1 } },
	pals = {
		{ id = 30, sp = "pebblit", lvl = 4, xp = 1, work = 0, muts = { "sturdy2" } },
		{ id = 31, sp = "gullfin", lvl = 9, xp = 0, work = 0, muts = {} },
		{ id = 32, sp = "mossbun", lvl = 2, xp = 0, work = 0, muts = { "lazy" } },
	},
	plot = { placed = {
		{ uid = 10, id = "tent", x = 6, z = 2, rot = 0, lvl = 1 },
		{ uid = 11, id = "patch", x = 8, z = 6, rot = 0, lvl = 1 },
		{ uid = 12, id = "nest", x = -10, z = 4, rot = 0, lvl = 1 },
		{ uid = 13, id = "wild_tidepool", x = 4, z = -2, rot = 0, lvl = 1 },
		{ uid = 14, id = "done_tallgrass", x = -8, z = 8, rot = 0, lvl = 3 },
		{ uid = 15, id = "yard", x = -4, z = 12, rot = 0, lvl = 1 },
	} },
	seen = { pebblit = 2, gullfin = 2, mossbun = 2, clawdle = 1 },
	stats = { days = 4, built = 6, earned = 900, befriended = 3, battles = 12, cleared = 1, movedIn = 1, hatched = 0, skills = 2 },
	nextId = 40,
} })
local old = H.addPlayer({ userId = 9206, name = "Oldtimer" })
E.run(3)
local ov = H.profile(old)
H.expect(ov ~= nil and ov.v == Schema.VERSION, "save", "a version 9 save loads", tostring(ov and ov.v))
if ov then
	for _, k in { "cap", "pouch", "islets", "sea", "wilds" } do
		H.expect(ov[k] == nil, "save", "its " .. k .. " gone")
	end
	local trees, places, yards = 0, 0, 0
	for _, q in ov.plot.placed do
		if q.id == "tree" then
			trees += 1
		elseif string.sub(q.id, 1, 5) == "wild_" or string.sub(q.id, 1, 5) == "done_" then
			places += 1
		elseif q.id == "yard" then
			yards += 1
		end
	end
	H.expect(trees == 1 and places == 0 and yards == 0, "save", "a Tree of Life planted; the wild places and the yard gone", string.format("%d %d %d", trees, places, yards))
	H.expect(ov.shells >= 1000 + 450 + 30 and ov.wood >= 80 + 50, "save", "the yard's and the Tent's prices back", string.format("%s %s", tostring(ov.shells), tostring(ov.wood)))
	local inNest = 0
	for _, x in ov.pals do
		if x.home == 12 then
			inNest += 1
		end
	end
	H.expect(#ov.pals == 3 and inNest == 2, "save", "its driftlings: two in the hut, one in the pen", string.format("%d, %d in the hut", #ov.pals, inNest))
	H.expect(ov.folk == nil and ov.stats.movedIn == nil and ov.tut == 4 and ov.quest == 1 and ov.stats.grown == 3, "save", "no villagers or levels; the tips on the hut's step; the questline afresh; befriended counted as grown", string.format("tut %d", ov.tut))
	H.checkProfile(old, "v9")
	H.checkMirror(old, "v9")
end

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
} })
local c = H.addPlayer({ userId = 9204, name = "Glitch" })
E.run(3)
local cp = H.profile(c)
H.expect(cp ~= nil, "save", "a corrupt record still loads")
if cp then
	-- (its food clamped to none: the patch has made a little since, working with nobody at it)
	H.expect(cp.shells == Tuning.StartShells and cp.food >= 0 and cp.food < 2 and cp.tier == #Tuning.TierCost, "save", "into a valid profile (the tier at the top)", string.format("%s %s %d", tostring(cp.shells), tostring(cp.food), cp.tier))
	-- (the pieces built, apart from the tree it was given)
	local PlotM = H.sharedServer("Logic.Plot")
	local built = {}
	for _, x in cp.plot.placed do
		if not PlotM.isFixed(x.id) then
			table.insert(built, x)
		end
	end
	local q = built[1]
	H.expect(#built == 1 and q.id == "patch" and PlotM.fits(cp.tier, {}, q.id, q.x, q.z, q.rot), "save", "the patch off the island moved onto it, the unknown piece gone", string.format("%d pieces", #built))
	H.expect(#cp.plot.placed == 2, "save", "and a tree planted", string.format("%d pieces", #cp.plot.placed))
	H.expect(cp.folk == nil and #cp.pals == 1 and cp.pals[1].id == 8 and cp.pals[1].home == 0, "save", "only what makes sense kept (no villagers)", string.format("%d pals", #cp.pals))
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
	H.expect(op.coins == nil and op.team == nil and op.games == nil and #op.plot.placed == 1 and op.plot.placed[1].id == "tree" and op.tier == 1 and op.tut == 1, "save", "the studio gone: a fresh island with the tips (and its Tree of Life)")
	H.expect(op.shells == Tuning.StartShells, "save", "the starting shells", tostring(op.shells))
	H.checkProfile(o, "old-save")
	H.checkMirror(o, "old-save")
end

report(E, H)
