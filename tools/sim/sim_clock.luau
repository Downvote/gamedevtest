-- The island's clock (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 7.4): a turn every Tuning.TurnSeconds while the player is
-- here, open menus and Build mode holding nothing; the wood and shells a day makes matching Island.rates (to a tick);
-- the stores and the time to the Tree of Life's next eggs reaching the client every second (Fx tick, patched into the
-- view with no whole view sent); the tree's eggs: its first lot laid when the island comes, a new lot every Tree.secs
-- (Fx eggs with a whole view: the old ones gone, the clock wound again, the ticks' time running down and starting over,
-- the HUD's Tree card counting down), sooner with the huts' tree shares, the extra eggs laid at once when the island
-- grows, and the clock running only while the player is here (nothing laid while they're away); nothing eating (no
-- food since 2026-11-13: the stores only grow, even from none); a driftling waiting with no hut while every hut is
-- full, moving in once a hut goes up and going to work once a building of its knack does; the Hatchery's egg (a feast
-- of shells) hatching into a hut with room, or waiting with no hut; two islands each on their own clocks. (The huts are
-- full while the rates are measured, and nobody hatches one of the tree's eggs, so nobody new goes to work.)
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
local Tree = H.sharedServer("Logic.Tree")
local Traits = H.sharedServer("Data.Traits")
local Breed = H.sharedServer("Logic.Breed")
local STORE = Tuning.DataStoreName .. "/global" -- the fake engine keys stores by name and scope

local p = H.addPlayer({ userId = 9301, name = "Clock" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)
local s = H.session(p)
-- (when each lot of eggs reaches the client, the Tree.secs it was laid with, and how many whole views the client gets:
-- the ticks are patched into the view, so no whole view comes every second)
local SC = H.cmod(p, "Controllers.StateClient")
local lots, views = {}, 0
H.inClient(p, function()
	SC.Fx:Connect(function(msg)
		if msg.kind == "eggs" then
			table.insert(lots, { msg = msg, now = E.SIM.now, secs = Tree.secs(prof), at = #fx })
		end
	end)
	SC.Changed:Connect(function()
		views += 1
	end)
end)
-- The tree's eggs as "id.r;..." (to compare two lists of eggs).
local function eggsOf(c): string
	local out = {}
	for _, e in if type(c) == "table" and type(c.list) == "table" then c.list else {} do
		table.insert(out, string.format("%s.%s", tostring(e.id), tostring(e.r)))
	end
	return table.concat(out, ";")
end
-- The client's view follows the profile's eggs (a new lot reaches it with the next whole view). Wait it out before
-- comparing the two.
local function settled(who)
	E.runUntil(function()
		local pr, v = H.profile(who), H.view(who)
		if pr == nil or v == nil or type(v.clutch) ~= "table" or #v.clutch ~= #pr.clutch.list then
			return false
		end
		for i, e in pr.clutch.list do
			if v.clutch[i].id ~= e.id then
				return false
			end
		end
		return true
	end, 1, 0.05)
end
-- The next lot laid from now on (the tree's clock runs out on the server; its Fx reaches the client): the entry in
-- `lots`, or nil within `limit` seconds. A top-up (more > 0, the island grown) is no lot.
local function nextLot(limit: number)
	local n0 = #lots
	local found = nil
	E.runUntil(function()
		for k = n0 + 1, #lots do
			if lots[k].msg.more == 0 then
				found = lots[k]
				return true
			end
		end
		return false
	end, limit, 0.05)
	return found
end
-- "m:ss", as the HUD shows the time to the next lot.
local function clock(secs: number): string
	local x = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", x // 60, x % 60)
end

------------------------------------------------------------------ the first lot
-- (a new island: the tree laid its first lot the moment it came, the first two cheap commons, its clock wound)
E.phase = "first"
do
	local c = prof.clutch
	local n = Tree.count(prof.tier)
	H.expect(#c.list == n and c.next == n + 1 and c.list[1].id == 1 and c.list[1].r == 1 and c.list[2].r == 1, "eggs", "the tree laid its first lot when the island came (the first two commons)", eggsOf(c))
	H.expect(c.left <= Tuning.EggSecs and c.left > Tuning.EggSecs - 2.5, "eggs", "its clock wound to EggSecs and running", string.format("%.2f", c.left))
end

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
for _, id in { "patch", "patch", "lumber", "nest", "nest", "stall", "flowers" } do
	local r = place(id)
	H.expect(r.ok, "clock", "place " .. id, tostring(r.err))
end
-- the huts filled: four driftlings with places at the farms, the camp and the stall (a new island has none of its
-- own yet: the tree's eggs are only hatched by the player)
local function hutsN(): number
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
H.expect(#prof.pals == 0, "clock", "a new island has no driftling yet", tostring(#prof.pals))
for _, sp in { "mossbun", "frondle", "pebblit", "conchy" } do
	Tree.add(prof, sp, {})
end
H.push(p, 0.2)
local working = 0
for _, x in prof.pals do
	if x.work ~= 0 then
		working += 1
	end
end
H.expect(hutsN() == 4 and working == 4 and Tree.room(prof) == 0, "clock", "the two huts full, all four at work", string.format("%d in huts, %d at work", hutsN(), working))
-- the next turn's end (its Fx turn)
local function nextTurn(limit: number?)
	local i0 = #fx
	E.runUntil(function()
		return count("turn", i0) >= 1
	end, limit or Tuning.TurnSeconds + 2, 0.05)
end
local d0 = prof.day
nextTurn()

local t0 = E.SIM.now
E.run(0.3) -- (the first turn's Fx on its way)
local f0 = #fx
local views0 = views
E.runUntil(function()
	return count("turn", f0) >= 2
end, Tuning.TurnSeconds * 3 + 3, 0.05)
local took = E.SIM.now - t0
H.expect(math.abs(took - Tuning.TurnSeconds * 2) < 0.6, "clock", "a turn every TurnSeconds", string.format("two turns in %.2fs", took))
E.run(0.3)
H.expect(count("turn", f0) == 2, "clock", "an Fx turn each", tostring(count("turn", f0)))
H.expect(prof.day == d0, "clock", "turns are not days (a day is hours of the sea's clock)", string.format("%d -> %d", d0, prof.day))
H.expect(math.abs(count("tick", f0) - took) <= 2, "clock", "an Fx tick every second", string.format("%d in %.1fs", count("tick", f0), took))

------------------------------------------------------------------ the tree's eggs on the island's clock
-- (the tree lays a new lot every Tree.secs while the player is here: the eggs left go, Tree.count new ones come with
-- their prices, an Fx eggs and a whole view; the ticks carry the time to the next lot, a second less each, and the
-- seconds between two; the HUD's Tree card counts down from StateClient.clutchLeft. The huts' tree shares bring the
-- lots sooner.)
E.phase = "eggs"
local lastForced = nil -- (the lot brought on last here: the lots phase waits for the one after it)
do
	local secs = Tree.secs(prof)
	H.expect(math.abs(secs - Tuning.EggSecs) < 1e-9, "eggs", "a lot every EggSecs (no tree shares in the huts)", tostring(secs))
	local ticks = {}
	for i = f0 + 1, #fx do
		if fx[i].kind == "tick" then
			table.insert(ticks, fx[i])
		end
	end
	local carried, down = true, true
	for k, m in ticks do
		carried = carried and m.tideSecs == nil and type(m.clutchLeft) == "number" and type(m.clutchSecs) == "number" and math.abs(m.clutchSecs - secs) < 1e-9
		local prev = ticks[k - 1]
		if prev and type(prev.clutchLeft) == "number" and type(m.clutchLeft) == "number" then
			down = down and math.abs((prev.clutchLeft - m.clutchLeft) - 1) < 0.15
		end
	end
	H.expect(#ticks >= 10 and carried, "eggs", "every tick carries the time to the next lot and the seconds between two (no tide)", string.format("%d ticks", #ticks))
	H.expect(#ticks >= 10 and down, "eggs", "the time to the next lot a second less each tick")
	H.expect(views - views0 <= count("turn", f0) + 1, "eggs", "no whole view a second (the ticks are patched into the view)", string.format("%d views in %d ticks", views - views0, #ticks))
	local v = H.view(p)
	H.expect(v ~= nil and v.tide == nil and v.tideSecs == nil and math.abs(v.clutchLeft - prof.clutch.left) <= 1.1 and v.clutchSecs == secs, "eggs", "the view's clock the server's, to a tick", string.format("%s vs %.2f", tostring(v and v.clutchLeft), prof.clutch.left))
	H.expect(hutsN() == 4 and #prof.pals == 4, "eggs", "nobody hatches by themselves", string.format("%d driftlings", #prof.pals))
	-- the clock brought near its end: the eggs left go and a new lot comes, with its Fx and a whole view
	local old = {}
	for _, e in prof.clutch.list do
		old[e.id] = true
	end
	local next0, views1 = prof.clutch.next, views
	prof.clutch.left = 1.5
	local due = E.SIM.now + 1.5
	local got = nextLot(3)
	local n = Tree.count(prof.tier)
	H.expect(got ~= nil and math.abs(got.now - due) <= 0.25, "eggs", "a new lot the moment the clock runs out (Fx eggs)", string.format("%s s off", got and string.format("%.2f", got.now - due) or "none"))
	local kept = 0
	for _, e in prof.clutch.list do
		if old[e.id] then
			kept += 1
		end
	end
	H.expect(kept == 0 and #prof.clutch.list == n and prof.clutch.list[1].id == next0 and prof.clutch.next == next0 + n, "eggs", "the old eggs gone, a whole new lot laid, the ids carrying on", eggsOf(prof.clutch))
	local same = got ~= nil and type(got.msg.laid) == "table" and #got.msg.laid == n
	for i, e in prof.clutch.list do
		local x = got and type(got.msg.laid) == "table" and got.msg.laid[i]
		same = same and x ~= nil and x.id == e.id and x.r == e.r and x.cost == Tree.cost(prof, e.r)
	end
	H.expect(same, "eggs", "the message lists the new lot, each egg with its price")
	H.expect(prof.clutch.left <= secs and prof.clutch.left > secs - 0.6, "eggs", "the clock wound to Tree.secs again", string.format("%.2f", prof.clutch.left))
	settled(p)
	H.expect(views > views1, "eggs", "a whole view sent with the new lot", string.format("%d views", views - views1))
	H.checkMirror(p, "lot")
	-- (the first tick after it: the time to the next lot starting over)
	local iLot = got and got.at or #fx
	E.runUntil(function()
		return count("tick", iLot) >= 1
	end, 1.5, 0.05)
	local tk = nil
	for i = iLot + 1, #fx do
		if fx[i].kind == "tick" then
			tk = fx[i]
			break
		end
	end
	H.expect(tk ~= nil and tk.clutchLeft <= secs and tk.clutchLeft > secs - 1.1, "eggs", "the next tick's time to the next lot starts over from the top", tostring(tk and tk.clutchLeft))
	-- the HUD's Tree card: "New eggs in m:ss" and its bar, run down from the client's clock
	E.run(2)
	local card = p.PlayerGui:FindFirstChild("TreeCard", true)
	local label = card and card:FindFirstChild("TreeNext")
	local back = card and card:FindFirstChild("TreeBar")
	local fill = back and back:FindFirstChildWhichIsA("Frame")
	local cl = H.inClient(p, function()
		local left, between = SC.clutchLeft()
		return { left = left, secs = between }
	end)
	H.expect(math.abs(cl.left - prof.clutch.left) <= 1.1 and cl.secs == secs, "eggs", "the client's clock (StateClient.clutchLeft) the server's, to a tick", string.format("%.2f vs %.2f", cl.left, prof.clutch.left))
	local text = label and label.Text or "none"
	H.expect(text == "New eggs in " .. clock(cl.left) or text == "New eggs in " .. clock(cl.left + E.dt), "eggs", "the Tree card counts down to the next lot", string.format("%q, %.2f s left", text, cl.left))
	local width = if back then math.floor((back.Size.X.Offset - 2) * math.clamp(cl.left / cl.secs, 0, 1) + 0.5) else -1
	H.expect(fill ~= nil and math.abs(fill.Size.X.Offset - width) <= 1 and width < back.Size.X.Offset - 2, "eggs", "and its bar runs down with it", string.format("%s px, %d due", tostring(fill and fill.Size.X.Offset), width))
	-- the huts' tree shares: a Lush driftling in a hut brings every lot 14% sooner (the ticks say so, the next lot is
	-- wound to the shorter time)
	local lush = prof.pals[1]
	local muts0 = lush.muts
	lush.muts = { "swift3" }
	H.push(p, 0.2)
	local share = Traits.byId.swift3.fx.tree
	local sooner = Tree.secs(prof)
	H.expect(share > 0 and math.abs(sooner - Tuning.EggSecs / (1 + share)) < 1e-6, "eggs", "a Lush driftling in a hut: the lots come sooner", string.format("%.2f s (%.2f share)", sooner, share))
	local iT = #fx
	E.runUntil(function()
		return count("tick", iT) >= 1
	end, 1.5, 0.05)
	local said = nil
	for i = iT + 1, #fx do
		if fx[i].kind == "tick" then
			said = fx[i].clutchSecs
		end
	end
	H.expect(said ~= nil and math.abs(said - sooner) < 1e-6, "eggs", "the ticks say the shorter time between two", tostring(said))
	prof.clutch.left = 1
	local got2 = nextLot(2.5)
	lastForced = got2
	H.expect(got2 ~= nil and prof.clutch.left <= sooner and prof.clutch.left > sooner - 0.6, "eggs", "the next lot wound to the shorter time", string.format("%.2f of %.2f", prof.clutch.left, sooner))
	-- (the Lush one back to what it was: the lots EggSecs apart again, the one on the way still the shorter time off)
	lush.muts = muts0
	H.push(p, 0.2)
	H.expect(math.abs(Tree.secs(prof) - Tuning.EggSecs) < 1e-9, "eggs", "and back to EggSecs without it", tostring(Tree.secs(prof)))
	settled(p)
	H.checkProfile(p, "eggs")
end

------------------------------------------------------------------ making wood and shells to the rates
E.phase = "rates"
local r = Island.rates(prof)
local wood0, sh0 = prof.wood, prof.shells
E.run(10)
local k = 10 / Tuning.TurnSeconds
H.expect(hutsN() == 4, "rates", "(nobody new at work meanwhile)")
H.expect(r.wood > 0, "rates", "the camp makes wood", tostring(r.wood))
H.expect(math.abs((prof.wood - wood0) - r.wood * k) <= r.wood * 0.02 + 0.5, "rates", "wood to the day's rate", string.format("%.2f vs %.2f", prof.wood - wood0, r.wood * k))
H.expect(math.abs((prof.shells - sh0) - r.shells * k) <= r.shells * 0.02 + 0.5, "rates", "shells to the day's rate (the farms sell what they grow, the stall sells to visitors)", string.format("%.2f vs %.2f", prof.shells - sh0, r.shells * k))
H.expect(r.shells > 0, "rates", "the farms and the stall make shells", tostring(r.shells))
local v = H.view(p)
H.expect(v ~= nil and math.abs(v.rates.wood - r.wood) < 1e-6 and math.abs(v.rates.shells - r.shells) < 1e-6 and v.rates.food == nil, "rates", "the view says the rates (wood and shells, no food)")
H.expect(v ~= nil and math.abs(v.wood - prof.wood) <= r.wood / Tuning.TurnSeconds * 1.5 + 1, "rates", "the view's wood follows the ticks", string.format("%s vs %s", v and v.wood, prof.wood))
H.expect(v ~= nil and math.abs(v.shells - prof.shells) <= r.shells / Tuning.TurnSeconds * 1.5 + 1, "rates", "the view's shells follow the ticks", string.format("%s vs %s", v and v.shells, prof.shells))
settled(p)
H.checkMirror(p, "rates")

------------------------------------------------------------------ open menus and Build mode hold nothing
E.phase = "menus"
H.openPanel(p, "index")
E.run(0.3)
local sA = prof.shells
E.run(4)
H.expect(prof.shells > sA, "menus", "the island goes on while a menu is open")
H.closePanel(p)
H.clickNamed(p, "Menu_build", { wait = 0.3 })
local wA = prof.wood
E.run(4)
H.expect(prof.wood > wA, "menus", "and in Build mode")
H.clickNamed(p, "BuildDone", { wait = 0.3 })

------------------------------------------------------------------ nothing eats
-- (food went on 2026-11-13: no hunger, so the stores only ever grow, and the shops stay open with nothing in store)
E.phase = "stores"
prof.shells, prof.wood = 0, 0
H.push(p, 0.2)
E.run(3)
H.expect(prof.shells > 0 and prof.wood > 0, "stores", "from empty stores the island makes wood and shells (nothing eats)", string.format("%s %s", tostring(prof.shells), tostring(prof.wood)))
local rz = Island.rates(prof)
H.expect(rz.shells > 0 and math.abs(rz.shells - r.shells) < 1e-6 and math.abs(rz.wood - r.wood) < 1e-6, "stores", "the same rates with nothing in store (no hunger shutting the shops)", string.format("%s vs %s", tostring(rz.shells), tostring(r.shells)))
v = H.view(p)
H.expect(v ~= nil and v.food == nil and v.rates.food == nil, "stores", "no food in the view")
local pg = p:FindFirstChild("PlayerGui")
H.expect(pg ~= nil and pg:FindFirstChild("Chip_wood", true) ~= nil and pg:FindFirstChild("Chip_shells", true) ~= nil and pg:FindFirstChild("Chip_food", true) == nil, "stores", "the HUD's chips: wood and shells, no food")
local hud = H.buttonNamed(p, "Menu_build")
H.expect(hud ~= nil, "stores", "the HUD stays usable")

------------------------------------------------------------------ waiting for a hut, then for work
-- (GAME_DESIGN 6: a driftling with no hut waits on the island, working nowhere, and moves in the moment a hut has
-- room; in a hut it goes to a free place at a building of its knack once there is one)
E.phase = "work"
do
	prof.shells, prof.wood = 1e6, 1e5
	local crab = Tree.add(prof, "clawdle", {}) -- (good at fishing: nowhere on the island to fish yet)
	H.push(p, 0.2)
	H.expect(crab.home == 0 and crab.work == 0, "work", "every hut full: the Clawdle waits with no hut", string.format("home %d", crab.home))
	H.checkProfile(p, "waiting")
	local rn = place("nest")
	H.expect(rn.ok, "work", "a new hut with room", tostring(rn.err))
	E.run(0.3)
	local hutUid = 0
	for _, q in prof.plot.placed do
		if q.id == "nest" then
			hutUid = math.max(hutUid, q.uid)
		end
	end
	H.expect(crab.home == hutUid and crab.work == 0, "work", "it moves into the new hut at once; with nowhere to fish it rests there", string.format("home %d work %d", crab.home, crab.work))
	local rp = place("pier")
	H.expect(rp.ok, "work", "a fishing pier", tostring(rp.err))
	E.run(0.3)
	local pierUid = 0
	for _, q in prof.plot.placed do
		if q.id == "pier" then
			pierUid = q.uid
		end
	end
	H.expect(crab.home == hutUid and crab.work == pierUid, "work", "a place at the pier: it fishes there", string.format("home %d work %d", crab.home, crab.work))
	H.checkProfile(p, "work")
	settled(p)
	H.checkMirror(p, "work")
	-- the island expanded twice (the buildings where the coast changed make room); each time the tree lays the extra
	-- eggs a bigger island has at once (Fx eggs with how many more), the ones lying there kept, its clock as it was
	for _ = 1, 2 do
		local eggs0, n0, left0, l0 = eggsOf(prof.clutch), #prof.clutch.list, prof.clutch.left, #lots
		local rx = H.req(p, "island.expand", {})
		H.expect(rx.ok, "work", "the island expands", tostring(rx.err))
		E.run(0.3)
		local more = Tree.count(prof.tier) - n0
		local msg = lots[l0 + 1] and lots[l0 + 1].msg
		H.expect(more >= 1 and #prof.clutch.list == Tree.count(prof.tier) and string.sub(eggsOf(prof.clutch), 1, #eggs0) == eggs0, "work", "a bigger island: the tree lays its extra eggs at once, the others kept", string.format("%d -> %d eggs", n0, #prof.clutch.list))
		H.expect(msg ~= nil and msg.more == more and type(msg.laid) == "table" and #msg.laid == #prof.clutch.list and #lots == l0 + 1, "work", "and says so (Fx eggs with how many more)", tostring(msg and msg.more))
		H.expect(prof.clutch.left < left0 and prof.clutch.left > left0 - 1, "work", "its clock running on as it was (no new lot)", string.format("%.2f -> %.2f", left0, prof.clutch.left))
	end
	H.expect(prof.tier == 3, "work", "to the third tier", tostring(prof.tier))
	H.checkProfile(p, "expanded")
	settled(p)
	H.checkMirror(p, "expanded")
end

------------------------------------------------------------------ the Hatchery: two parents, an egg, its turns, a hatching
E.phase = "hatchery"
do
	prof.shells, prof.wood = 1e7, 1e6
	while prof.tier < 3 do
		local r = H.req(p, "island.expand", {})
		if not H.expect(r.ok, "hatchery", "expanding to the third tier", tostring(r.err)) then
			break
		end
		E.run(0.5)
	end
	-- two Hatcheries (a second egg alongside, to hatch on the same turn) and a den with room
	for _, id in { "hatchery", "hatchery", "den" } do
		local rh = place(id)
		H.expect(rh.ok, "hatchery", "a " .. id .. " at the third tier", tostring(rh.err))
	end
	local uids = {}
	for _, q in prof.plot.placed do
		if q.id == "hatchery" then
			table.insert(uids, q.uid)
		end
	end
	local uid = uids[1] or 0
	-- two parents of one kind (the egg is theirs), carrying a shared mutation
	local ids = {}
	for k = 1, 2 do
		local x = Tree.add(prof, "gullfin", { "swift2", if k == 1 then "angler1" else "lazy" })
		table.insert(ids, x.id)
	end
	H.push(p, 0.4)
	-- through the panels as a player: the Driftlings panel's Hatchery button, a parent in each slot, Breed
	H.openPanel(p, "pals")
	H.clickNamed(p, "OpenHatch", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "hatch", "hatchery", "the Driftlings panel opens the Hatchery")
	H.clickNamed(p, "Slot_a_" .. uid, { wait = 0.4 })
	H.clickNamed(p, "PickParent_" .. ids[1], { wait = 0.4 })
	H.clickNamed(p, "Slot_b_" .. uid, { wait = 0.4 })
	H.expect(H.buttonNamed(p, "PickParent_" .. ids[1]) == nil, "hatchery", "the first parent is not offered again")
	H.clickNamed(p, "PickParent_" .. ids[2], { wait = 0.4 })
	-- the feast is paid in shells: none in store, no egg
	local feast = Breed.cost("gullfin")
	prof.shells = 0
	H.push(p, 0.3)
	H.openPanel(p, "hatch")
	H.expect(H.buttonNamed(p, "Breed_" .. uid) == nil and H.buttonNamed(p, "Breed_" .. uid, true) ~= nil, "hatchery", "Breed is off without the feast's shells")
	H.expect(H.req(p, "breed.start", { uid = uid, a = ids[1], b = ids[2] }).err == "money", "hatchery", "and the server refuses it (money)")
	-- (both eggs laid early in one turn, so they hatch on the same turn)
	nextTurn()
	prof.shells = 5000
	H.push(p, 0.3)
	H.openPanel(p, "hatch")
	local shells0 = prof.shells
	local made = Island.rates(prof).shells * 2 / Tuning.TurnSeconds + 0.5
	H.clickNamed(p, "Breed_" .. uid, { wait = 0.6 })
	local egg = prof.eggs[1]
	H.expect(egg ~= nil and egg.uid == uid and egg.sp == "gullfin", "hatchery", "an egg of their kind is laid", tostring(egg and egg.sp))
	local paid = shells0 - prof.shells
	H.expect(paid <= feast + 1e-6 and paid >= feast - made, "hatchery", "the feast paid in shells", string.format("%.2f paid, the feast %d", paid, feast))
	local swift = false
	for _, id in egg and egg.muts or {} do
		if id == "swift2" or id == "swift3" then
			swift = true
		end
	end
	H.expect(swift, "hatchery", "the shared mutation passes on")
	local r2 = H.req(p, "breed.start", { uid = uids[2] or 0, a = ids[1], b = ids[2] })
	H.expect(r2.ok and #prof.eggs == 2 and prof.eggs[2].left == prof.eggs[1].left, "hatchery", "a second egg at the other Hatchery, due the same turn", tostring(r2.err))
	-- refusals
	H.expect(H.req(p, "breed.start", { uid = uid, a = ids[1], b = ids[2] }).err == "egg", "hatchery", "one egg a Hatchery")
	H.expect(H.req(p, "breed.start", { uid = 99999, a = ids[1], b = ids[2] }).err == "not_found", "hatchery", "no Hatchery there")
	H.expect(H.req(p, "breed.start", { uid = uid, a = ids[1], b = ids[1] }).err ~= nil, "hatchery", "the same one twice")
	H.expect(H.req(p, "breed.start", { uid = uid, a = -1, b = 0.5 }).err == "bad_payload", "hatchery", "a bad payload")
	local function indexOf(u)
		for i, q in prof.plot.placed do
			if q.uid == u then
				return i
			end
		end
		return 0
	end
	H.expect(H.req(p, "plot.store", { i = indexOf(uid) }).err == "egg", "hatchery", "not cleared away with an egg in it")
	-- the huts filled to one place left: the first to hatch takes it, the second waits with no hut
	local fillers = {}
	while Tree.room(prof) > 1 do
		table.insert(fillers, Tree.add(prof, "pebblit", {}).id)
	end
	H.push(p, 0.3)
	H.expect(Tree.room(prof) == 1, "hatchery", "(one place left in the huts)", tostring(Tree.room(prof)))
	-- the turns: the egg on the panel counts down, then they hatch (announced)
	H.openPanel(p, "hatch")
	local pals0 = #prof.pals
	local i0 = #fx
	local turns = egg and egg.left or 0
	for _ = 1, turns do
		nextTurn()
	end
	E.run(0.5)
	local news = nil
	for i = i0 + 1, #fx do
		if fx[i].kind == "turn" and type(fx[i].hatched) == "table" then
			news = fx[i].hatched
		end
	end
	H.expect(news ~= nil and #news == 2 and news[1].sp == "gullfin" and news[2].sp == "gullfin", "hatchery", "both eggs hatched after their turns (the turn's news)", tostring(news and #news))
	local born = {}
	for _, n in news or {} do
		for _, x in prof.pals do
			if x.id == n.id then
				table.insert(born, x)
			end
		end
	end
	H.expect(#born == 2 and #prof.eggs == 0 and prof.stats.hatched == 2 and #prof.pals == pals0 + 2, "hatchery", "two new driftlings", string.format("%d -> %d", pals0, #prof.pals))
	H.expect(#born == 2 and born[1].home ~= 0 and born[2].home == 0 and born[2].work == 0, "hatchery", "the first into the hut with room, the second waiting with no hut", string.format("homes %s %s", tostring(born[1] and born[1].home), tostring(born[2] and born[2].home)))
	H.expect(#born == 2 and born[1].lvl == nil and born[1].sp == "gullfin", "hatchery", "its parents' kind (no levels)")
	H.checkProfile(p, "hatched")
	-- a place freed (one sold): the waiting one moves in
	local rs = H.req(p, "pal.sell", { id = fillers[1] or 0 })
	H.expect(rs.ok and born[2] ~= nil and born[2].home ~= 0, "hatchery", "one sold: the hatchling waiting moves into its place", string.format("%s home %s", tostring(rs.err), tostring(born[2] and born[2].home)))
	H.closePanel(p)
	for _, u in uids do
		H.expect(H.req(p, "plot.store", { i = indexOf(u) }).ok, "hatchery", "a Hatchery cleared away once empty")
	end
	H.checkProfile(p, "hatchery")
end

------------------------------------------------------------------ a lot every Tree.secs
-- (the lot laid with the Lush driftling in a hut was wound to the shorter time: the next comes that long after it, by
-- itself, whatever happened on the island meanwhile)
E.phase = "lots"
do
	local last = lastForced
	local wound = last and last.secs or 0
	-- (the first lot after it, waited for if it hasn't come yet)
	local nextOne = nil
	for _, l in lots do
		if last and nextOne == nil and l.msg.more == 0 and l.now > last.now then
			nextOne = l
		end
	end
	if nextOne == nil and last then
		nextOne = nextLot(math.max(1, last.now + wound + 2 - E.SIM.now))
	end
	H.expect(last ~= nil and nextOne ~= nil and math.abs((nextOne.now - last.now) - wound) <= 0.25, "lots", "the next lot came by itself, Tree.secs after the last", string.format("%s s apart, wound to %.2f", if last and nextOne then string.format("%.2f", nextOne.now - last.now) else "none", wound))
	H.expect(nextOne ~= nil and math.abs(prof.clutch.left - (nextOne.secs - (E.SIM.now - nextOne.now))) <= 0.25, "lots", "and wound the clock to Tree.secs as it stood then", string.format("%.2f left, %.2f then", prof.clutch.left, nextOne and nextOne.secs or -1))
	settled(p)
	H.checkMirror(p, "lots")
end

------------------------------------------------------------------ two islands, two clocks
E.phase = "two"
local pLeft0, pNext0, pAt = prof.clutch.left, prof.clutch.next, E.SIM.now
local q = H.addPlayer({ userId = 9302, name = "Tock" })
E.runUntil(function()
	local ss = H.session(q)
	return ss ~= nil and ss.ready
end, 5, 0.05)
local qAt = E.SIM.now
E.run(2)
local sq = H.session(q)
local pq = H.profile(q)
local fq = H.watchFx(q)
local fp0 = #fx
E.run(Tuning.TurnSeconds + 1)
local qt = 0
for _, m in fq do
	if m.kind == "turn" then
		qt += 1
	end
end
H.expect(qt >= 1 and count("turn", fp0) >= 1, "two", "both islands' turns end", string.format("%d, %d", qt, count("turn", fp0)))
H.expect(sq.turnClock >= 0 and sq.turnClock < Tuning.TurnSeconds and s.turnClock >= 0 and s.turnClock < Tuning.TurnSeconds, "two", "each on its own turn clock", string.format("%.2f %.2f", sq.turnClock, s.turnClock))
local vq, vp = H.view(q), H.view(p)
H.expect(vq ~= nil and vp ~= nil and math.abs(vq.dayFrac - vp.dayFrac) < 0.001, "two", "one sea, one time of day", string.format("%s %s", vq and vq.dayFrac, vp and vp.dayFrac))
-- (each its own tree and eggs: Tock's first lot laid when Tock came, its clock from then; Clock's eggs and clock going
-- on as they were, untouched by the newcomer)
local nq = Tree.count(pq.tier)
H.expect(pq.clutch ~= prof.clutch and #pq.clutch.list == nq and pq.clutch.next == nq + 1 and math.abs(pq.clutch.left - (Tree.secs(pq) - (E.SIM.now - qAt))) <= 0.25, "two", "the newcomer's tree laid its own first lot when they came, its clock from then", string.format("%d eggs, %.2f s left, %.2f s since", #pq.clutch.list, pq.clutch.left, E.SIM.now - qAt))
H.expect(prof.clutch.next == pNext0 and math.abs(prof.clutch.left - (pLeft0 - (E.SIM.now - pAt))) <= 0.25, "two", "the first island's eggs and clock going on as they were", string.format("%.2f s left, %.2f before", prof.clutch.left, pLeft0))

------------------------------------------------------------------ away
-- (the eggs' clock only runs while the player is here: Tock leaves with the next lot three seconds off and stays away
-- twice that long, comes back to the same eggs three seconds from a lot, and the lot comes three seconds later)
E.phase = "away"
do
	pq.clutch.left = 3
	local eggsQ, nextQ = eggsOf(pq.clutch), pq.clutch.next
	E.removePlayer(q, "leave")
	E.run(6)
	local st = E.cloud.stores[STORE]
	local rec = st and st["u_9302"]
	local saved = rec and rec.value and rec.value.data and rec.value.data.clutch
	H.expect(type(saved) == "table" and eggsOf(saved) == eggsQ and saved.next == nextQ and math.abs(saved.left - 3) < 0.15, "away", "saved on leaving: the eggs and three seconds to the next lot", string.format("%s, %s s", eggsOf(saved), tostring(type(saved) == "table" and saved.left)))
	q = H.addPlayer({ userId = 9302, name = "Tock" })
	E.runUntil(function()
		local ss = H.session(q)
		return ss ~= nil and ss.ready
	end, 5, 0.05)
	local back = E.SIM.now
	pq = H.profile(q)
	H.expect(pq ~= nil and eggsOf(pq.clutch) == eggsQ and pq.clutch.next == nextQ and pq.clutch.left > 2.8 and pq.clutch.left <= 3, "away", "back: the same eggs, their clock where it stopped (nothing laid while away)", string.format("%.2f s left", pq and pq.clutch.left or -1))
	E.runUntil(function()
		return pq ~= nil and pq.clutch.next > nextQ
	end, 4, 0.05)
	H.expect(pq ~= nil and pq.clutch.next == nextQ + Tree.count(pq.tier) and math.abs((E.SIM.now - back) - 3) <= 0.25, "away", "the lot comes once those three seconds have run with them here", string.format("%.2f s after coming back", E.SIM.now - back))
	E.run(1)
end
------------------------------------------------------------------ day and night
E.phase = "daynight"
-- the day and night (GAME_DESIGN 8): the sea's clock grades the picture: plain by day, dark blue at night with the
-- lamps lit, bright again at dawn (UI/DayLight; with the filter off, as in this engine, Roblox's own clock follows)
do
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local DL = H.cmod(p, "Controllers.DayLight")
	local nightGrade = DL.at(0.88)
	H.expect(DL.at(0.35) == nil and nightGrade ~= nil and nightGrade.mr < 0.6 and nightGrade.lamps > 0.9, "daynight", "the grade: none at noon, dark with the lamps lit at night")
	local dusk = DL.at(0.68)
	H.expect(dusk ~= nil and dusk.mr > dusk.mb, "daynight", "a warm dusk")
	-- (a day is hours: the sea's clock jumps to the time of day, then runs on a moment)
	local WC = H.smod("WorldClock")
	local function at(lo, hi)
		local want = (lo + hi) / 2
		WC.shift(((want - WC.dayFrac()) % 1) * Tuning.DaySeconds)
		E.run(1.3)
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
settled(p)
H.checkMirror(p, "end")
H.checkProfile(q, "end")
settled(q)
H.checkMirror(q, "end")

report(E, H)
