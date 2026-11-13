-- Saves (docs/ARCHITECTURE.md 7.6): a player builds, takes a driftling off the tide into the hut (a second one put
-- there with its mutations), then leaves (saved, lock released) and rejoins to the very same profile, with a fresh tide
-- (the drifts are the session's, never saved); a version 11 save (the Tree of Life, its levels, food, a pen with one
-- held) loads as version 12 with the tree and its levels gone, the pen sold for its price, the food gone and what the
-- tree grew counted as taken in; a version 9 save (the wild places, the fights, the levels and a villager in a Tent)
-- loads with its yard's and its Tent's prices back, no villagers, two driftlings in the hut and the pen's one sold; a
-- save under another server's live lock is never overwritten; a join waits out another server's lock and then takes
-- over; a corrupt record still loads into a valid profile; a version 4 save (the game studio) starts a fresh island
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
local Tide = H.sharedServer("Logic.Tide")
local Traits = H.sharedServer("Data.Traits")
local Creatures = H.sharedServer("Data.Creatures")
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
-- one off the tide taken in (a new island's first two drifts are commons): into the hut
local s1 = H.session(p)
H.expect(#s1.tide.list == Tuning.TideStart, "save", "the jetty has its first drifts", tostring(#s1.tide.list))
local first = s1.tide.list[1]
local rt = first and H.req(p, "tide.take", { id = first.id, swap = 0 })
H.expect(rt ~= nil and rt.ok and housed() == 1 and prof.stats.taken == 1 and prof.folk == nil, "save", "a driftling taken off the tide into the hut (no villagers)", string.format("%s, %d in the hut", tostring(rt and rt.err), housed()))
-- (a second one in the hut, its mutations kept through the save)
local nestUid = 0
for _, q in prof.plot.placed do
	if q.id == "nest" then
		nestUid = q.uid
	end
end
table.insert(prof.pals, { id = prof.nextId, sp = "gullfin", home = nestUid, work = 0, muts = { "angler2", "lazy" } })
prof.nextId += 1
prof.seen.gullfin = 2
prof.founder.shirt = 5
-- (a level from before upgrades were taken out: kept through the save)
for _, q in prof.plot.placed do
	if q.id == "patch" then
		q.lvl = 2
	end
end
prof.stats.best = math.max(prof.stats.best, 2)
H.push(p, 0.5)
-- the tide goes on: more bob at the jetty before the player leaves
E.runUntil(function()
	return #s1.tide.list >= Tuning.TideStart + 1
end, Tuning.TideSecs * 3 + 2, 0.1)
local oldTide = #s1.tide.list
H.expect(oldTide > Tuning.TideStart and housed() == 2, "save", "the tide brought more in meanwhile", tostring(oldTide))
local before = E.deepCopy(H.profile(p))
E.phase = "leave"
E.removePlayer(p, "leave")
E.run(2)
local rec = record(9201)
H.expect(rec ~= nil and type(rec.value) == "table" and type(rec.value.data) == "table", "save", "the profile is saved on leave")
H.expect(rec ~= nil and rec.value.lock == nil, "save", "the lock is released on leave")
H.expect(rec ~= nil and rec.value.data.tide == nil and rec.value.data.tree == nil and rec.value.data.food == nil, "save", "no tide, tree or food in the record (the tide is the session's)")
local freed = E.workspace.Plots:FindFirstChild("Plot_1")
H.expect(freed ~= nil and freed:GetAttribute("Owner") == 0 and freed:FindFirstChild("EmptyLot", true) ~= nil, "save", "the island is freed: open water again")
E.phase = "rejoin"
local p2 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
local after = E.deepCopy(H.profile(p2))
-- the clock ran a little since: the day's making (nothing happens offline)
after.shells, after.wood, after.stats.earned = before.shells, before.wood, before.stats.earned
-- (the fresh tide's drifts go in the Index as seen: kinds never seen before are left out of the comparison)
for k, n in after.seen do
	if before.seen[k] == nil and n == 1 then
		after.seen[k] = nil
	end
end
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved", tostring(diff))
H.expect(H.session(p2).plot == 1, "save", "island 1 again")
local s2 = H.session(p2)
H.expect(s2 ~= nil and #s2.tide.list == Tuning.TideStart and s2.tide.next == Tuning.TideStart + 1, "save", "a fresh tide: its first drifts again, none of the last visit's", string.format("%d bobbing (%d before), next %d", s2 and #s2.tide.list or -1, oldTide, s2 and s2.tide.next or -1))
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ a version 11 save (the Tree of Life, its pen, food)
E.phase = "v11"
seed(9207, { data = {
	v = 11,
	shells = 1000,
	food = 120,
	wood = 80,
	tier = 1,
	tut = 5,
	quest = 3,
	tree = { luck = 3, speed = 2, t = 4.5 },
	pals = {
		{ id = 30, sp = "mossbun", home = 12, work = 11, muts = { "lazy" } },
		{ id = 31, sp = "pebblit", home = 12, work = 0, muts = {} },
		{ id = 32, sp = "gullfin", home = 0, work = 0, muts = { "angler2" }, held = 1 },
		{ id = 33, sp = "clawdle", home = 0, work = 0, muts = {} },
	},
	plot = { placed = {
		{ uid = 10, id = "tree", x = -6, z = -8, rot = 0, lvl = 1 },
		{ uid = 11, id = "patch", x = 8, z = 6, rot = 0, lvl = 1 },
		{ uid = 12, id = "nest", x = -10, z = 4, rot = 0, lvl = 1 },
	} },
	seen = { mossbun = 2, pebblit = 2, gullfin = 2, clawdle = 2, conchy = 1 },
	stats = { days = 9, built = 5, earned = 2000, grown = 7, sold = 3, best = 2, hatched = 0 },
	nextId = 40,
} })
-- what the pen sells for (Logic/Tide.price)
local penPrice = Tide.price({ id = 0, sp = "gullfin", home = 0, work = 0, muts = Traits.clean({ "angler2" }) })
	+ Tide.price({ id = 0, sp = "clawdle", home = 0, work = 0, muts = Traits.clean({}) })
local v11 = H.addPlayer({ userId = 9207, name = "Treekeeper" })
E.run(3)
local pv = H.profile(v11)
H.expect(pv ~= nil and pv.v == Schema.VERSION and Schema.VERSION == 12, "save", "a version 11 save loads as version 12", tostring(pv and pv.v))
if pv then
	local trees = 0
	for _, q in pv.plot.placed do
		if q.id == "tree" then
			trees += 1
		end
	end
	H.expect(trees == 0 and #pv.plot.placed == 2 and pv.tree == nil, "save", "the Tree of Life and its levels gone, the patch and the hut kept", string.format("%d trees, %d pieces", trees, #pv.plot.placed))
	local inHut = 0
	for _, x in pv.pals do
		if x.home == 12 and (x.id == 30 or x.id == 31) then
			inHut += 1
		end
	end
	H.expect(#pv.pals == 2 and inHut == 2, "save", "the hut's two kept, the pen's two gone", string.format("%d pals, %d in the hut", #pv.pals, inHut))
	-- (the shells since: the patch sold a little, counted as earned too)
	local made = pv.stats.earned - (2000 + penPrice)
	H.expect(made >= 0 and made < 5 and math.abs((pv.shells - pv.stats.earned) - (1000 - 2000)) < 1e-6, "save", "the pen sold for its price into shells (counted as earned)", string.format("%s shells, %s earned, the pen %d", tostring(pv.shells), tostring(pv.stats.earned), penPrice))
	H.expect(pv.stats.sold == 3 + 2, "save", "and as sold", tostring(pv.stats.sold))
	H.expect(pv.food == nil and pv.wood == 80, "save", "the food gone, the wood kept", string.format("%s %s", tostring(pv.food), tostring(pv.wood)))
	local st = pv.stats :: any
	H.expect(st.taken == 7 and st.grown == nil, "save", "what the tree grew counted as taken in", string.format("taken %s grown %s", tostring(st.taken), tostring(st.grown)))
	H.expect(pv.tut == 5 and pv.quest == 3 and pv.seen.conchy == 1, "save", "the tips, the questline and the Index kept", string.format("tut %d quest %d", pv.tut, pv.quest))
	H.checkProfile(v11, "v11")
	H.checkMirror(v11, "v11")
end

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
	H.expect(trees == 0 and places == 0 and yards == 0 and #ov.plot.placed == 2, "save", "no Tree of Life; the wild places, the yard and the Tent gone (the patch and the hut kept)", string.format("%d %d %d, %d pieces", trees, places, yards, #ov.plot.placed))
	-- (the third went to the pen at version 10, and the pen was sold at version 12)
	local sold = Tide.price({ id = 0, sp = "mossbun", home = 0, work = 0, muts = Traits.clean({ "lazy" }) })
	H.expect(ov.shells >= 1000 + 450 + 30 + sold and ov.wood >= 80 + 50, "save", "the yard's and the Tent's prices back, and the pen's driftling sold", string.format("%s %s (the pen's %d)", tostring(ov.shells), tostring(ov.wood), sold))
	local inNest = 0
	for _, x in ov.pals do
		if x.home == 12 then
			inNest += 1
		end
	end
	H.expect(#ov.pals == 2 and inNest == 2 and ov.stats.sold == 1, "save", "its driftlings: two in the hut, the pen's one sold", string.format("%d, %d in the hut, %d sold", #ov.pals, inNest, ov.stats.sold))
	local st = ov.stats :: any
	H.expect(ov.folk == nil and st.movedIn == nil and ov.tut == 4 and ov.quest == 1 and st.taken == 3 and st.grown == nil, "save", "no villagers or levels; the tips on step 4; the questline afresh; befriended counted as taken in", string.format("tut %d taken %s", ov.tut, tostring(st.taken)))
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
	-- (a version 5 save: the Clawdle rolled its mutations at version 7, went to the pen at version 10 with no hut to go
	-- to, and was sold at version 12; the shells it held were junk, so its price is all there is, and the patch has
	-- sold a little since, working with nobody at it)
	local Util = H.sharedServer("Logic.Util")
	local crab = Tide.price({ id = 8, sp = "clawdle", home = 0, work = 0, muts = Traits.clean(Traits.roll(Util.newRng(Util.hash32("clawdle:8")), 1)) })
	H.expect(cp.shells >= crab and cp.shells < crab + 2 and cp.wood == Tuning.StartWood and cp.food == nil and cp.tier == #Tuning.TierCost, "save", "into a valid profile (the tier at the top)", string.format("%s %s %d (the Clawdle %d)", tostring(cp.shells), tostring(cp.wood), cp.tier, crab))
	local q = cp.plot.placed[1]
	H.expect(#cp.plot.placed == 1 and q.id == "patch" and Plot.fits(cp.tier, {}, q.id, q.x, q.z, q.rot), "save", "the patch off the island moved onto it, the unknown piece gone (no tree planted)", string.format("%d pieces", #cp.plot.placed))
	H.expect(cp.folk == nil and #cp.pals == 0 and cp.stats.sold == 1, "save", "only what makes sense kept (no villagers, the unknown kind gone, the pen's Clawdle sold)", string.format("%d pals, %d sold", #cp.pals, cp.stats.sold))
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
	H.expect(op.coins == nil and op.team == nil and op.games == nil and #op.plot.placed == 0 and #op.pals == 0 and op.tier == 1 and op.tut == 1, "save", "the studio gone: a fresh island with the tips (nothing built, no Tree of Life)")
	H.expect(op.shells == Tuning.StartShells and op.wood == Tuning.StartWood, "save", "the starting shells and wood", string.format("%s %s", tostring(op.shells), tostring(op.wood)))
	-- (a fresh island's first drifts: commons, one good with wood and one at a farm, for the tips' first buildings)
	local so = H.session(o)
	local knacks = {}
	for _, d in so and so.tide.list or {} do
		local cd = Creatures.byId[d.sp]
		if d.id <= Tuning.TideStart and cd and cd.rarity == 1 then
			knacks[cd.knack] = true
		end
	end
	H.expect(so ~= nil and #so.tide.list == Tuning.TideStart and knacks.wood and knacks.farm, "save", "its tide starts with two commons: one for the camp, one for a farm", so and tostring(#so.tide.list))
	H.checkProfile(o, "old-save")
	H.checkMirror(o, "old-save")
end

report(E, H)
