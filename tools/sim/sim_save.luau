-- Saves (docs/ARCHITECTURE.md 7.6): a player builds, hatches one of the Tree of Life's eggs into the hut (a second
-- driftling put there with its mutations), then leaves (saved with the tree's eggs and their clock, lock released) and
-- rejoins to the very same profile: the same eggs with the same ids, their clock where it stopped (it only runs while
-- the player is here, so no new lot came while they were away); a version 12 save (the tide: no tree, no eggs) loads
-- as version 13 with its Tree of Life planted and a lot laid on the first step; a version 11 save (the old Tree of
-- Life, its levels, food, a pen with one held) loads with the old tree and its levels gone and a new tree planted (the
-- patch making room for it), the pen sold for its price, the food gone and what the old tree grew counted as hatched; a
-- version 9 save (the wild places, the fights, the levels and a villager in a Tent) loads with its yard's and its
-- Tent's prices back, no villagers, two driftlings in the hut, the pen's one sold and a tree planted; a save under
-- another server's live lock is never overwritten; a join waits out another server's lock and then takes over; a
-- corrupt record still loads into a valid profile, and junk eggs are cleaned; a version 4 save (the game studio)
-- starts a fresh island keeping the founder's look and the settings, its tree's first lot starting with two cheap
-- commons.
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
local Tree = H.sharedServer("Logic.Tree")
local Traits = H.sharedServer("Data.Traits")
local Buildings = H.sharedServer("Data.Buildings")
local STORE = Tuning.DataStoreName .. "/global" -- the fake engine keys stores by name and scope
local function record(userId)
	local st = E.cloud.stores[STORE]
	return st and st["u_" .. userId]
end
local function seed(userId, value)
	E.cloud.stores[STORE] = E.cloud.stores[STORE] or {}
	E.cloud.stores[STORE]["u_" .. userId] = { value = value, meta = {}, userIds = {}, version = 1, created = E.SIM.now, updated = E.SIM.now }
end
-- The tree's eggs as "id.r;..." (to compare two lists of eggs).
local function eggsOf(c): string
	local out = {}
	for _, e in if type(c) == "table" and type(c.list) == "table" then c.list else {} do
		table.insert(out, string.format("%s.%s", tostring(e.id), tostring(e.r)))
	end
	return table.concat(out, ";")
end
-- A lot just laid: as many eggs as the tree lays at the island's tier, their ids one after another up to the next
-- one's, its clock wound to Tree.secs less the few seconds since (`since`).
local function lot(prof, since): (boolean, string)
	local c = prof.clutch
	local secs = Tree.secs(prof)
	local ok = #c.list == Tree.count(prof.tier) and c.left <= secs + 1e-6 and c.left >= secs - since
	for i, e in c.list do
		ok = ok and e.id == c.next - #c.list + i - 1
	end
	return ok, string.format("%d eggs (%d a lot), %.1f s of %.1f to the next: %s", #c.list, Tree.count(prof.tier), c.left, secs, eggsOf(c))
end
-- The tree in the island's pieces: how many, and the first.
local function treesOf(prof): (number, any)
	local n, first = 0, nil
	for _, q in prof.plot.placed do
		if Plot.isFixed(q.id) then
			n += 1
			first = first or q
		end
	end
	return n, first
end
-- The client's view follows the profile's eggs (a new lot reaches it with the next whole view). Wait it out before
-- comparing the two.
local function settled(p)
	E.runUntil(function()
		local prof, v = H.profile(p), H.view(p)
		if prof == nil or v == nil or type(v.clutch) ~= "table" or #v.clutch ~= #prof.clutch.list then
			return false
		end
		for i, e in prof.clutch.list do
			if v.clutch[i].id ~= e.id then
				return false
			end
		end
		return true
	end, 1, 0.05)
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
-- (a new island: its tree laid its first lot on the first step, the first two cheap commons)
local okLot, whyLot = lot(prof, 2.5)
local c1 = prof.clutch.list
H.expect(okLot and c1[1].id == 1 and c1[1].r == 1 and c1[2].r == 1, "save", "the tree laid its first lot when the player arrived (the first two commons)", whyLot)
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
-- one egg hatched (the first, a common): into the hut, the rest left lying
local first = prof.clutch.list[1]
local restOf = {}
for i = 2, #prof.clutch.list do
	local e = prof.clutch.list[i]
	table.insert(restOf, string.format("%d.%d", e.id, e.r))
end
local rt = first and H.req(p, "egg.hatch", { id = first.id, swap = 0 })
H.expect(rt ~= nil and rt.ok and housed() == 1 and prof.stats.taken == 1 and prof.folk == nil, "save", "an egg hatched into the hut (no villagers)", string.format("%s, %d in the hut", tostring(rt and rt.err), housed()))
H.expect(eggsOf(prof.clutch) == table.concat(restOf, ";"), "save", "the hatched egg gone, the others still lying", eggsOf(prof.clutch))
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
-- the eggs' clock runs on before the player leaves (no new lot yet: one comes every few minutes)
local left0, next0, eggs0 = prof.clutch.left, prof.clutch.next, eggsOf(prof.clutch)
E.run(3)
H.expect(prof.clutch.left < left0 - 2.5 and prof.clutch.left > left0 - 3.5 and prof.clutch.next == next0 and eggsOf(prof.clutch) == eggs0 and housed() == 2, "save", "the eggs' clock runs on meanwhile, the same eggs lying (no new lot yet)", string.format("%.2f -> %.2f s, %s", left0, prof.clutch.left, eggsOf(prof.clutch)))
local before = E.deepCopy(H.profile(p))
local leftAt = E.SIM.now
E.phase = "leave"
E.removePlayer(p, "leave")
E.run(2)
local rec = record(9201)
H.expect(rec ~= nil and type(rec.value) == "table" and type(rec.value.data) == "table", "save", "the profile is saved on leave")
H.expect(rec ~= nil and rec.value.lock == nil, "save", "the lock is released on leave")
H.expect(rec ~= nil and rec.value.data.tide == nil and rec.value.data.tree == nil and rec.value.data.food == nil, "save", "no tide, old tree levels or food in the record")
local savedC = rec and rec.value.data.clutch
local savedLeft = if type(savedC) == "table" then savedC.left else nil
H.expect(type(savedC) == "table" and eggsOf(savedC) == eggs0 and savedC.next == next0 and type(savedLeft) == "number" and math.abs(savedLeft - before.clutch.left) < 0.25, "save", "the tree's eggs saved with their ids and their clock", string.format("%s, next %s, %s s", eggsOf(savedC), tostring(type(savedC) == "table" and savedC.next), tostring(savedLeft)))
local freed = E.workspace.Plots:FindFirstChild("Plot_1")
H.expect(freed ~= nil and freed:GetAttribute("Owner") == 0 and freed:FindFirstChild("EmptyLot", true) ~= nil and freed:GetAttribute("Eggs") == nil, "save", "the island is freed: open water again, no eggs listed")
E.phase = "rejoin"
local p2 = H.addPlayer({ userId = 9201, name = "Saver" })
E.run(2)
local after = E.deepCopy(H.profile(p2))
-- the clock ran a little since: the day's making (nothing happens offline)
after.shells, after.wood, after.stats.earned = before.shells, before.wood, before.stats.earned
-- (the eggs' clock ran on only while the player was here again, never while they were away)
local away = E.SIM.now - leftAt
local ran = before.clutch.left - after.clutch.left
after.clutch.left = before.clutch.left
local diff = H.diff(before, after)
H.expect(diff == nil, "save", "the rejoined profile is the one saved (the same eggs, the same ids)", tostring(diff))
H.expect(ran >= 0 and ran <= 2.05 and ran < away - 1.5, "save", "the eggs' clock where it stopped: it ran only since the player came back, not while away", string.format("%.2f s off the clock in %.1f s since leaving", ran, away))
H.expect(H.session(p2).plot == 1, "save", "island 1 again")
local isle = E.workspace.Plots:FindFirstChild("Plot_1")
H.expect(isle ~= nil and isle:GetAttribute("Eggs") == eggs0, "save", "the plot lists the same eggs again", tostring(isle and isle:GetAttribute("Eggs")))
settled(p2)
H.checkProfile(p2, "rejoin")
H.checkMirror(p2, "rejoin")

------------------------------------------------------------------ a version 12 save (the tide: no tree, no eggs)
E.phase = "v12"
seed(9208, { data = {
	v = 12,
	shells = 800,
	wood = 120,
	tier = 2,
	tut = 0,
	quest = 4,
	pals = {
		{ id = 20, sp = "mossbun", home = 11, work = 10, muts = {} },
		{ id = 21, sp = "pebblit", home = 11, work = 0, muts = {} },
	},
	plot = { placed = {
		{ uid = 10, id = "patch", x = 8, z = 6, rot = 0, lvl = 1 },
		{ uid = 11, id = "nest", x = -10, z = 4, rot = 0, lvl = 1 },
		{ uid = 12, id = "flowers", x = -4, z = -6, rot = 0, lvl = 1 },
	} },
	seen = { mossbun = 2, pebblit = 2, gullfin = 1 },
	stats = { days = 6, built = 3, earned = 1500, taken = 2, sold = 0, best = 1, hatched = 0 },
	nextId = 30,
} })
local v12 = H.addPlayer({ userId = 9208, name = "Tidewatcher" })
E.run(3)
local pt = H.profile(v12)
H.expect(pt ~= nil and pt.v == Schema.VERSION and Schema.VERSION == 13, "save", "a version 12 save loads as version 13", tostring(pt and pt.v))
if pt then
	local trees, tq = treesOf(pt)
	local kept = 0
	for _, q in pt.plot.placed do
		if q.uid == 10 or q.uid == 11 or q.uid == 12 then
			kept += 1
		end
	end
	H.expect(trees == 1 and tq.uid >= 30 and kept == 3 and #pt.plot.placed == 4, "save", "its Tree of Life planted (a new piece), the patch, the hut and the flowers kept", string.format("%d trees, %d kept of %d pieces", trees, kept, #pt.plot.placed))
	local ok, why = lot(pt, 3)
	H.expect(ok and pt.clutch.list[1].id == 1, "save", "and a lot of eggs laid on the first step (the tier's count, ids from 1)", why)
	local inHut = 0
	for _, x in pt.pals do
		if x.home == 11 then
			inHut += 1
		end
	end
	H.expect(#pt.pals == 2 and inHut == 2 and pt.stats.taken == 2 and pt.stats.sold == 0, "save", "its driftlings kept in the hut, the ones taken in off the tide counted as hatched", string.format("%d pals, %d in the hut, taken %d", #pt.pals, inHut, pt.stats.taken))
	H.expect(pt.shells >= 800 and pt.wood == 120 and pt.tut == 0 and pt.quest == 4 and pt.seen.gullfin == 1, "save", "its stores, the tips, the questline and the Index kept", string.format("%s %s", tostring(pt.shells), tostring(pt.wood)))
	H.checkProfile(v12, "v12")
	settled(v12)
	H.checkMirror(v12, "v12")
end
-- (they leave again: six islands to a sea, and more joins follow)
E.removePlayer(v12, "leave")
E.run(1)

------------------------------------------------------------------ a version 11 save (the old Tree of Life, its pen, food)
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
-- what the pen sells for (Logic/Tree.price)
local penPrice = Tree.price({ id = 0, sp = "gullfin", home = 0, work = 0, muts = Traits.clean({ "angler2" }) })
	+ Tree.price({ id = 0, sp = "clawdle", home = 0, work = 0, muts = Traits.clean({}) })
local v11 = H.addPlayer({ userId = 9207, name = "Treekeeper" })
E.run(3)
local pv = H.profile(v11)
H.expect(pv ~= nil and pv.v == Schema.VERSION and Schema.VERSION == 13, "save", "a version 11 save loads as version 13", tostring(pv and pv.v))
if pv then
	-- (the old tree went at version 12 with its levels; version 13 plants a new one, with a new uid. A tier-1 island has
	-- few places an 8 by 8 tree fits, and the patch and the hut take them all: the patch makes room, its whole price
	-- back, as Logic/Tree.plant clears the nearest piece that houses nobody)
	local trees, tq = treesOf(pv)
	local hut, patch = 0, 0
	for _, q in pv.plot.placed do
		if q.uid == 12 and q.id == "nest" then
			hut += 1
		elseif q.id == "patch" then
			patch += 1
		end
	end
	H.expect(trees == 1 and tq.uid ~= 10 and pv.tree == nil, "save", "the old Tree of Life and its levels gone, a new tree planted", string.format("%d trees (uid %s)", trees, tostring(tq and tq.uid)))
	H.expect(#pv.plot.placed == 2 and hut == 1 and patch == 0, "save", "the patch made room for it, the hut kept", string.format("%d pieces, %d huts, %d patches", #pv.plot.placed, hut, patch))
	local ok, why = lot(pv, 3)
	H.expect(ok, "save", "its first lot of eggs laid", why)
	local inHut = 0
	for _, x in pv.pals do
		if x.home == 12 and (x.id == 30 or x.id == 31) then
			inHut += 1
		end
	end
	H.expect(#pv.pals == 2 and inHut == 2, "save", "the hut's two kept, the pen's two gone", string.format("%d pals, %d in the hut", #pv.pals, inHut))
	-- (the shells since: nothing sold, the patch gone, its worker resting)
	local made = pv.stats.earned - (2000 + penPrice)
	H.expect(made >= 0 and made < 5 and math.abs((pv.shells - pv.stats.earned) - (1000 - 2000)) < 1e-6, "save", "the pen sold for its price into shells (counted as earned)", string.format("%s shells, %s earned, the pen %d", tostring(pv.shells), tostring(pv.stats.earned), penPrice))
	H.expect(pv.stats.sold == 3 + 2, "save", "and as sold", tostring(pv.stats.sold))
	H.expect(pv.food == nil and pv.wood == 80 + Buildings.byId.patch.wood, "save", "the food gone, the wood kept and the patch's wood back", string.format("%s %s", tostring(pv.food), tostring(pv.wood)))
	local st = pv.stats :: any
	H.expect(st.taken == 7 and st.grown == nil, "save", "what the old tree grew counted as hatched", string.format("taken %s grown %s", tostring(st.taken), tostring(st.grown)))
	H.expect(pv.tut == 5 and pv.quest == 3 and pv.seen.conchy == 1, "save", "the tips, the questline and the Index kept", string.format("tut %d quest %d", pv.tut, pv.quest))
	H.checkProfile(v11, "v11")
	settled(v11)
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
	H.expect(trees == 1 and places == 0 and yards == 0 and #ov.plot.placed == 2, "save", "a Tree of Life planted (the patch made room for it); the wild places, the yard and the Tent gone (the hut kept)", string.format("%d %d %d, %d pieces", trees, places, yards, #ov.plot.placed))
	-- (the third went to the pen at version 10, and the pen was sold at version 12)
	local sold = Tree.price({ id = 0, sp = "mossbun", home = 0, work = 0, muts = Traits.clean({ "lazy" }) })
	H.expect(ov.shells >= 1000 + 450 + 30 + sold and ov.wood >= 80 + 50, "save", "the yard's and the Tent's prices back, and the pen's driftling sold", string.format("%s %s (the pen's %d)", tostring(ov.shells), tostring(ov.wood), sold))
	local inNest = 0
	for _, x in ov.pals do
		if x.home == 12 then
			inNest += 1
		end
	end
	H.expect(#ov.pals == 2 and inNest == 2 and ov.stats.sold == 1, "save", "its driftlings: two in the hut, the pen's one sold", string.format("%d, %d in the hut, %d sold", #ov.pals, inNest, ov.stats.sold))
	local st = ov.stats :: any
	H.expect(ov.folk == nil and st.movedIn == nil and ov.tut == 4 and ov.quest == 1 and st.taken == 3 and st.grown == nil, "save", "no villagers or levels; the tips on step 4; the questline afresh; befriended counted as hatched", string.format("tut %d taken %s", ov.tut, tostring(st.taken)))
	H.checkProfile(old, "v9")
	settled(old)
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
	local crab = Tree.price({ id = 8, sp = "clawdle", home = 0, work = 0, muts = Traits.clean(Traits.roll(Util.newRng(Util.hash32("clawdle:8")), 1)) })
	H.expect(cp.shells >= crab and cp.shells < crab + 2 and cp.wood == Tuning.StartWood and cp.food == nil and cp.tier == #Tuning.TierCost, "save", "into a valid profile (the tier at the top)", string.format("%s %s %d (the Clawdle %d)", tostring(cp.shells), tostring(cp.wood), cp.tier, crab))
	local pq, tq = cp.plot.placed[1], cp.plot.placed[2]
	H.expect(#cp.plot.placed == 2 and pq.id == "patch" and Plot.fits(cp.tier, {}, pq.id, pq.x, pq.z, pq.rot) and tq.id == "tree", "save", "the patch off the island moved onto it, the unknown piece gone, a Tree of Life planted", string.format("%d pieces", #cp.plot.placed))
	H.expect(cp.folk == nil and #cp.pals == 0 and cp.stats.sold == 1, "save", "only what makes sense kept (no villagers, the unknown kind gone, the pen's Clawdle sold)", string.format("%d pals, %d sold", #cp.pals, cp.stats.sold))
	local ok, why = lot(cp, 3)
	H.expect(ok, "save", "its tree's first lot laid (the top tier's count)", why)
	H.checkProfile(c, "corrupt")
	settled(c)
	H.checkMirror(c, "corrupt")
end
-- junk eggs in a version 13 save: only eggs with an id of their own and a rarity in range, no more than the tree lays,
-- the next id past them all, the clock no longer than a lot's
E.phase = "corrupt-eggs"
seed(9209, { data = {
	v = 13,
	shells = 300,
	wood = 40,
	tier = 1,
	tut = 0,
	quest = 2,
	clutch = {
		left = 1e9,
		next = 2,
		list = {
			{ id = 3, r = 2 },
			{ id = 3, r = 4 }, -- (the same id again)
			"an egg",
			{ id = -1, r = 1 }, -- (no id)
			{ id = 7, r = 99 }, -- (past legendary)
			{ id = 8, r = 0 },
			{ id = 9.5, r = 2.7 },
			{ id = 10, r = "rare" },
			{ id = 11, r = 1 }, -- (one past the five a tier-1 tree lays)
		},
	},
	stats = { taken = 3 },
	nextId = 5,
} })
local j = H.addPlayer({ userId = 9209, name = "Scrambled" })
E.run(3)
local jp = H.profile(j)
H.expect(jp ~= nil, "save", "a save with junk eggs still loads")
if jp then
	local jc = jp.clutch
	H.expect(eggsOf(jc) == "3.2;7.5;8.1;9.2;10.1", "save", "its eggs cleaned: one an id, rarities 1 to 5, at most the tree's five", eggsOf(jc))
	H.expect(jc.next == 11 and jc.left <= Tuning.EggSecs and jc.left > Tuning.EggSecs - 3, "save", "the next id past them, the clock cut to a lot's (no new lot laid)", string.format("next %d, %.1f s", jc.next, jc.left))
	H.expect((treesOf(jp)) == 1, "save", "and its Tree of Life planted")
	H.checkProfile(j, "corrupt-eggs")
	settled(j)
	H.checkMirror(j, "corrupt-eggs")
end
E.removePlayer(j, "leave")
E.run(1)

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
	H.expect(op.coins == nil and op.team == nil and op.games == nil and #op.plot.placed == 1 and op.plot.placed[1].id == "tree" and #op.pals == 0 and op.tier == 1 and op.tut == 1, "save", "the studio gone: a fresh island with the tips (nothing built but its Tree of Life)")
	H.expect(op.shells == Tuning.StartShells and op.wood == Tuning.StartWood, "save", "the starting shells and wood", string.format("%s %s", tostring(op.shells), tostring(op.wood)))
	-- (a fresh island's first lot: the first two cheap commons, for the tips' first driftling)
	local ok, why = lot(op, 3)
	local ol = op.clutch.list
	H.expect(ok and ol[1].id == 1 and ol[1].r == 1 and ol[2].r == 1, "save", "its tree's first lot laid, the first two commons", why)
	settled(o)
	H.checkProfile(o, "old-save")
	H.checkMirror(o, "old-save")
end

report(E, H)
