-- The island's clock (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 7.4): a turn every Tuning.TurnSeconds while the player is
-- here, open menus and Build mode holding nothing; the shells a day makes matching Island.rates (to a tick);
-- the stores and the time to the Tree of Life's next eggs reaching the client every second (Fx tick, patched into the
-- view with no whole view sent); the tree's eggs: its first lot laid when the island comes, a new lot every Tree.secs
-- (Fx eggs with a whole view: the old ones gone, the clock wound again, the ticks' time running down and starting over,
-- the HUD's Tree card counting down), sooner with the huts' tree shares, the extra eggs laid at once when the island
-- grows, and the clock running only while the player is here (nothing laid while they're away); nothing eating (no
-- food since 2026-11-13: the stores only grow, even from none); a driftling waiting with no hut while every hut is
-- full, moving in once a hut goes up and going to work once a building of its knack does; the Hatchery's egg (paid for
-- in shells) hatching into a hut with room, or waiting with no hut; two islands each on their own clocks. (The huts are
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
local Buildings = H.sharedServer("Data.Buildings")
local Tree = H.sharedServer("Logic.Tree")
local Traits = H.sharedServer("Data.Traits")
local Breed = H.sharedServer("Logic.Breed")
local Numbers = H.sharedServer("Logic.Numbers")
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
prof.shells = 22000
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
	H.expect(fill ~= nil and math.abs(fill.Size.X.Offset - width) <= 1 and width <= back.Size.X.Offset - 2, "eggs", "and its bar runs down with it", string.format("%s px, %d due", tostring(fill and fill.Size.X.Offset), width))
	-- the tree keeps its 6 minutes (10 before 2026-11-17) whatever the huts hold (the request of 2026-11-14: "keep it at 10 minutes throughout
	-- the whole game unless a gamepass is bought"): a once-Leafy driftling changes nothing; the Quick Tree pass makes it
	-- five (the ticks say so, the next lot is wound to the shorter time)
	local lush = prof.pals[1]
	local muts0 = lush.muts
	lush.muts = Traits.clean({ "swift3" })
	H.push(p, 0.2)
	H.expect(Tree.secs(prof) == Tuning.EggSecs and Tuning.EggSecs == 360, "eggs", "a once-Leafy driftling in a hut: still 6 minutes", tostring(Tree.secs(prof)))
	lush.muts = muts0
	prof.passes.QuickTree = true
	H.push(p, 0.2)
	local sooner = Tree.secs(prof)
	H.expect(sooner == Tuning.EggSecsPass and sooner == 180, "eggs", "the Quick Tree pass: every 3 minutes", string.format("%.2f s", sooner))
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
	-- (the pass off again for the rest: the lots EggSecs apart, the one on the way still the shorter time off)
	prof.passes.QuickTree = nil
	H.push(p, 0.2)
	H.expect(math.abs(Tree.secs(prof) - Tuning.EggSecs) < 1e-9, "eggs", "and back to EggSecs without it", tostring(Tree.secs(prof)))
	settled(p)
	H.checkProfile(p, "eggs")
end

------------------------------------------------------------------ making shells to the rates
E.phase = "rates"
local r = Island.rates(prof)
local sh0 = prof.shells
E.run(10)
local k = 10 / Tuning.TurnSeconds
H.expect(hutsN() == 4, "rates", "(nobody new at work meanwhile)")
H.expect(math.abs((prof.shells - sh0) - r.shells * k) <= r.shells * 0.02 + 0.5, "rates", "shells to the day's rate (the farms, the camp and the stall all sell for shells)", string.format("%.2f vs %.2f", prof.shells - sh0, r.shells * k))
H.expect(r.shells > 0 and r.wood == nil, "rates", "the farms, the camp and the stall make shells (no wood)", tostring(r.shells))
local v = H.view(p)
H.expect(v ~= nil and math.abs(v.rates.shells - r.shells) < 1e-6 and v.rates.wood == nil and v.rates.food == nil, "rates", "the view says the rate (shells, no wood, no food)")
H.expect(v ~= nil and v.wood == nil and v.visitors == nil and v.charmBonus ~= nil and math.abs(v.charmBonus - Island.charmBonus(Island.charm(prof))) < 1e-9, "rates", "the view: no wood, no visitors, the charm bonus", string.format("%s %s %s", tostring(v and v.wood), tostring(v and v.visitors), tostring(v and v.charmBonus)))
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
local wA = prof.shells
E.run(4)
H.expect(prof.shells > wA, "menus", "and in Build mode")
H.clickNamed(p, "BuildDone", { wait = 0.3 })

------------------------------------------------------------------ nothing eats
-- (food went on 2026-11-13: no hunger, so the stores only ever grow, and the shops stay open with nothing in store)
E.phase = "stores"
prof.shells = 0
H.push(p, 0.2)
E.run(3)
H.expect(prof.shells > 0, "stores", "from an empty store the island makes shells (nothing eats)", tostring(prof.shells))
local rz = Island.rates(prof)
H.expect(rz.shells > 0 and math.abs(rz.shells - r.shells) < 1e-6, "stores", "the same rate with nothing in store (no hunger shutting the shops)", string.format("%s vs %s", tostring(rz.shells), tostring(r.shells)))
v = H.view(p)
H.expect(v ~= nil and v.food == nil and v.rates.food == nil, "stores", "no food in the view")
local pg = p:FindFirstChild("PlayerGui")
H.expect(pg ~= nil and pg:FindFirstChild("Chip_wood", true) == nil and pg:FindFirstChild("Chip_shells", true) ~= nil and pg:FindFirstChild("Chip_food", true) == nil, "stores", "the HUD's chips: shells, no wood, no food")
do
	-- the island card: the charm and what it adds to every shell (no visitors since 2026-11-14)
	local cardF = pg and pg:FindFirstChild("IslandCard", true)
	local bonus = cardF and cardF:FindFirstChild("CharmBonusR", true)
	local want = string.format("+%d%%", math.round(Island.charmBonus(Island.charm(prof)) * 100))
	H.expect(cardF ~= nil and bonus ~= nil and table.find(H.textsOf(bonus), want) ~= nil and cardF:FindFirstChild("Visitors", true) == nil, "stores", "the island card shows the charm bonus, no visitors", bonus and table.concat(H.textsOf(bonus), "/") or "none")
end
local hud = H.buttonNamed(p, "Menu_build")
H.expect(hud ~= nil, "stores", "the HUD stays usable")

------------------------------------------------------------------ waiting for a hut, then for work
-- (GAME_DESIGN 6: a driftling with no hut waits on the island, working nowhere, and moves in the moment a hut has
-- room; in a hut it goes to a free place, its knack's first, once there is one)
E.phase = "work"
do
	prof.shells = 1e6
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
	local function isWork(uid: number): boolean
		for _, q in prof.plot.placed do
			if q.uid == uid then
				local b = Buildings.byId[q.id]
				return b ~= nil and b.kind == "work"
			end
		end
		return false
	end
	H.expect(crab.home == hutUid and (crab.work == 0 or isWork(crab.work)), "work", "it moves into the new hut at once; with nowhere to fish it takes another free place, or rests", string.format("home %d work %d", crab.home, crab.work))
	-- (the player sends it to rest: that's a pick, kept while the pier goes up and the rest are arranged round it;
	-- Auto hands it back to the arrangement, Island.arrange: the request of 2026-11-14, "make it such that driftlings
	-- will automatically work at whatever they do best in, at the best work areas")
	local rr = H.req(p, "pal.work", { id = crab.id, uid = 0 })
	E.run(0.2)
	H.expect(rr.ok and crab.work == 0, "work", "sent to rest", tostring(rr.err))
	-- (the first island's work cap full, Plot.workLimit: a workplace nobody fishes at put away for the pier, as a
	-- player makes room)
	if Plot.work(prof.plot.placed) + Buildings.byId.pier.jobs > Plot.workLimit(prof.tier) then
		for i = #prof.plot.placed, 1, -1 do
			local b = Buildings.byId[prof.plot.placed[i].id]
			if b and b.jobs > 0 and b.act ~= "farm" then
				H.req(p, "plot.store", { i = i })
				break
			end
		end
	end
	local rp = place("pier")
	H.expect(rp.ok, "work", "a fishing pier", tostring(rp.err))
	E.run(0.3)
	local pierUid = 0
	for _, q in prof.plot.placed do
		if q.id == "pier" then
			pierUid = q.uid
		end
	end
	local atPier = 0
	for _, x in prof.pals do
		if x.work == pierUid then
			atPier += 1
		end
	end
	H.expect(crab.home == hutUid and crab.work == 0 and crab.pin == true and atPier > 0, "work", "resting by the player's hand it stays resting; the pier gets the arrangement's workers", string.format("home %d work %d, %d at the pier", crab.home, crab.work, atPier))
	local ra = H.req(p, "pal.auto", { id = crab.id })
	E.run(0.2)
	H.expect(ra.ok and crab.pin == nil and crab.work ~= 0 and isWork(crab.work), "work", "Auto: back to work where the arrangement puts it", string.format("%s work %d", tostring(ra.err), crab.work))
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
	prof.shells = 1e7
	while prof.tier < 3 do
		local r = H.req(p, "island.expand", {})
		if not H.expect(r.ok, "hatchery", "expanding to the third tier", tostring(r.err)) then
			break
		end
		E.run(0.5)
	end
	-- a Hatchery and a den with room; a second Hatchery waits for a bigger island (Tuning.HatcheryLimit: the request of
	-- 2026-11-14, "there should also be a hatchery limit per expansion. the first expansion where you unlock hatcheries,
	-- make the limit 1")
	for _, id in { "hatchery", "den" } do
		local rh = place(id)
		H.expect(rh.ok, "hatchery", "a " .. id .. " at the third tier", tostring(rh.err))
	end
	do
		local n0 = #prof.plot.placed
		local r2 = place("hatchery")
		H.expect(not r2.ok and r2.err == "hatcheries" and #prof.plot.placed == n0 and Plot.hatcheryLimit(prof.tier) == 1, "hatchery", "a second Hatchery at the third tier is refused (hatcheries)", tostring(r2.err))
		-- (an older save's second one stays where it stands: a second egg alongside, to hatch on the same turn)
		local hx, hz, hr = Plot.spot(prof.tier, prof.plot.placed, "hatchery", 0, 0, 0)
		if H.expect(hx ~= nil, "hatchery", "(room for an older save's second Hatchery)") then
			table.insert(prof.plot.placed, { uid = prof.nextId, id = "hatchery", x = hx :: number, z = hz :: number, rot = hr or 0, lvl = 1 })
			prof.nextId += 1
		end
	end
	-- the menu bar's Hatchery button now the island has them (the request of 2026-11-14: "add a hatchery tab once it is
	-- unlocked too"), and a tap on the Hatchery itself ("allow clicking on a hatchery to open the hatchery menu")
	H.push(p, 0.4)
	H.expect(H.buttonNamed(p, "Menu_hatch") ~= nil, "hatchery", "the menu bar has a Hatchery button from the third tier")
	H.clickNamed(p, "Menu_hatch", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "hatch", "hatchery", "it opens the Hatchery", tostring(H.currentPanel(p)))
	H.closePanel(p)
	do
		local model: Instance? = nil
		local plotModel = E.workspace.Plots:FindFirstChild("Plot_" .. H.session(p).plot)
		for _, d in (if plotModel then plotModel:GetDescendants() else {}) do
			if model == nil and d:IsA("Model") and d:GetAttribute("Decor") == "hatchery" then
				model = d
			end
		end
		local PRh = H.cmod(p, "Pixel.PixelRenderer")
		local WVh = H.cmod(p, "Controllers.WorldView")
		if H.expect(model ~= nil, "hatchery", "(the Hatchery's model on the island)") then
			local at = (model :: Model):GetPivot().Position + E.v3(0, 1.5, 0)
			local pos = H.inClient(p, function()
				local sp = PRh.project(at)
				return E.v2(sp.X, sp.Y - E.inset)
			end)
			E.raycastParts = true
			H.inClient(p, WVh.tapScreen, pos)
			E.raycastParts = nil
			E.run(0.4)
			H.expect(H.currentPanel(p) == "hatch", "hatchery", "a tap on the Hatchery opens its panel", tostring(H.currentPanel(p)))
			H.closePanel(p)
		end
	end
	-- two windmills: they stack, the second at Tuning.BoostStack of the first (the request of 2026-11-15: "make it such
	-- that boost buildings can stack, but with diminishing returns"); a tap on one: the farms' boost from both together
	-- and what one more would add ("when hovering over a boost building, show how much the total boosts ... with all
	-- other same type boost buildings together")
	do
		-- (every boost building boosts every workplace since the request of 2026-11-19: "All boost buildings should also
		-- just boost everything instead")
		local raw0 = Island.boostRaw(prof)
		local w1, w2 = place("windmill"), place("windmill")
		local by = Buildings.byId.windmill.boostBy
		H.expect(w1.ok and w2.ok and math.abs(Island.boostRaw(prof) - (raw0 + by + by * Tuning.BoostStack)) < 1e-9, "boost", "two windmills stack: the second gives BoostStack of the first", string.format("%s %s raw %.3f", tostring(w1.err), tostring(w2.err), Island.boostRaw(prof)))
		-- two of each at most (the request of 2026-11-20: "make the max of each boosts building to be 2"): a third
		-- windmill refused with nothing paid, another kind of boost building still going up
		do
			local n0, s0 = #prof.plot.placed, prof.shells
			local w3 = place("windmill")
			H.expect(not w3.ok and w3.err == "boosts" and #prof.plot.placed == n0 and prof.shells >= s0 and Plot.boostLimit() == 2, "boost", "a third windmill is refused (boosts), nothing paid", tostring(w3.err))
			local sh = place("smokehouse")
			H.expect(sh.ok, "boost", "another kind of boost building still goes up", tostring(sh.err))
			local si = #prof.plot.placed
			local rp = H.req(p, "plot.replace", { i = si, id = "windmill" })
			H.expect(not rp.ok and rp.err == "boosts" and prof.plot.placed[si].id == "smokehouse", "boost", "nor can a smokehouse become a third windmill (boosts)", tostring(rp.err))
			H.req(p, "plot.store", { i = si })
			H.push(p, 0.4)
			-- Build mode: the windmill's card greyed, "Max" and its count 2/2; another's count 0/2; a tap on it picks nothing
			H.clickNamed(p, "Menu_build", { wait = 0.4 })
			H.clickNamed(p, "Tab_work", { wait = 0.3 })
			H.clickNamed(p, "Chip_gen", { wait = 0.25 })
			local card = H.buttonNamed(p, "Buy_windmill", true)
			local texts = if card then H.textsOf(card) else {}
			H.expect(card ~= nil and table.find(texts, "Max") ~= nil and table.find(texts, "2/2") ~= nil, "boost", "the windmill's card says Max with its count 2/2", table.concat(texts, "/"))
			local other = H.buttonNamed(p, "Buy_toolshed", true)
			H.expect(other ~= nil and table.find(H.textsOf(other), "0/2") ~= nil and table.find(H.textsOf(other), "Max") == nil, "boost", "a boost building with none yet shows 0/2 and its price", other and table.concat(H.textsOf(other), "/"))
			H.clickNamed(p, "Buy_windmill", { includeDisabled = true, wait = 0.3 })
			local said = false
			for _, d in p.PlayerGui:GetDescendants() do
				if d:IsA("TextLabel") and string.find(d.Text, "Two of each boost building", 1, true) and H.guiVisible(d) then
					said = true
				end
			end
			H.expect(H.buttonNamed(p, "Place", true) == nil and said, "boost", "a tap on it picks nothing up and says why")
			H.clickNamed(p, "BuildDone", { wait = 0.3 })
		end
		H.push(p, 0.4)
		E.run(0.7)
		local BTc = H.cmod(p, "Controllers.BuildingTags")
		local mill = nil
		for _, sp in H.inClient(p, BTc.debugSpots) do
			if sp.id == "windmill" and sp.kind == "boost" and sp.tap and mill == nil then
				mill = sp
			end
		end
		E.raycastParts = true
		local shown = mill ~= nil and H.inClient(p, BTc.tapAt, mill.tap)
		E.raycastParts = nil
		E.run(0.3)
		local st = H.inClient(p, BTc.debugState)
		local info = Island.boostInfo(prof, "windmill")
		local function pct(x)
			local v = math.floor(x * 1000 + 0.5) / 10
			return if v == math.floor(v) then string.format("%d%%", v) else string.format("%.1f%%", v)
		end
		local want1 = string.format("Windmill +%s to all from %d boosts", pct(info.total), info.count)
		-- (two is the most of a kind since 2026-11-20: the card says so in place of what one more would add)
		local want2 = "2 of 2 built"
		H.expect(shown and info.count == 2 and info.more == 0 and st.card == want1 and st.card2 == want2, "boost", "a tap on a windmill: everything's boost from both, and that two is the most", string.format("%q / %q (want %q / %q)", st.card, st.card2, want1, want2))
		local roomy = 0
		for _, sp in H.inClient(p, BTc.debugSpots) do
			if sp.kind == "boost" and sp.room ~= 0 then
				roomy += 1
			end
		end
		H.expect(roomy == 0, "boost", "a boost building takes no workers: no Empty alert over it", tostring(roomy))
		-- (cleared away again for the checks below)
		for _ = 1, 2 do
			for i, q in prof.plot.placed do
				if q.id == "windmill" then
					H.req(p, "plot.store", { i = i })
					break
				end
			end
		end
		H.push(p, 0.3)
		E.run(3.2)
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
		local x = Tree.add(prof, "gullfin", { "swift2", if k == 1 then "grower1" else "lazy" })
		table.insert(ids, x.id)
	end
	-- (and two more for the parent picker's orders: the rarest kind with no mutations, a common one with a tier 4 one)
	local rareId = Tree.add(prof, "pyrelord", {}).id
	local mutId = Tree.add(prof, "gullfin", { Traits.at("busy", 4) }).id
	H.push(p, 0.4)
	-- through the panels as a player: the Driftlings panel's Hatchery button, a parent in each slot, Breed
	H.openPanel(p, "pals")
	H.clickNamed(p, "OpenHatch", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "hatch", "hatchery", "the Driftlings panel opens the Hatchery")
	H.clickNamed(p, "Slot_a_" .. uid, { wait = 0.4 })
	-- the parent picker's search and orders (the request of 2026-11-19: "for hatchery, make a search function, and a
	-- sort by mutation rarity or creature rarity"): the rarest kind first, or the rarest mutations first; the search
	-- looks through each one's kind, rarity, passive and mutations
	do
		local MenusC = H.cmod(p, "UI.Menus")
		local CreaturesC = H.sharedServer("Data.Creatures")
		-- (the list makes only the rows near what shows, UIKit.lazyList: it is scrolled from top to foot a window at a
		-- time and every row seen is taken, then put back at the top)
		local UIKitC = H.cmod(p, "UI.UIKit")
		local function listed(): { number }
			local panel = p.PlayerGui:FindFirstChild("Panel_hatch", true)
			local list = if panel then panel:FindFirstChild("List", true) else nil
			local rows = {}
			local seen = {}
			local function take()
				for _, c in if list then list:GetChildren() else {} do
					local id = tonumber(string.match(c.Name, "^Parent_(%d+)$"))
					if id and not seen[id] then
						seen[id] = true
						table.insert(rows, { id = id, o = c.LayoutOrder })
					end
				end
			end
			take()
			if list then
				local win = math.max(20, list.Size.Y.Offset)
				local total = list.CanvasSize.Y.Offset
				local y = 0
				while y + win < total do
					y = math.min(y + win, total - win)
					H.inClient(p, function()
						list.CanvasPosition = E.v2(0, y * UIKitC.P())
					end)
					E.run(0.05)
					take()
				end
				H.inClient(p, function()
					list.CanvasPosition = E.v2(0, 0)
				end)
				E.run(0.05)
			end
			table.sort(rows, function(a, b)
				return a.o < b.o
			end)
			local out = {}
			for _, r in rows do
				table.insert(out, r.id)
			end
			return out
		end
		local function palOf(id)
			for _, x in prof.pals do
				if x.id == id then
					return x
				end
			end
			return nil
		end
		local function rarityOf(id): number
			local x = palOf(id)
			local d = if x then CreaturesC.byId[x.sp] else nil
			return if d then d.rarity else 0
		end
		local function topTier(id): number
			local x = palOf(id)
			local best = 0
			for _, m in Traits.clean(if x then x.muts else nil) do
				local t = Traits.byId[m]
				if t and t.tier > best then
					best = t.tier
				end
			end
			return best
		end
		local function wordsOf(x): string
			local d = CreaturesC.byId[x.sp]
			local w = { d.name, (Traits.RARITY[d.rarity] or Traits.RARITY[1]).name, d.passive.name }
			for _, m in Traits.clean(x.muts) do
				table.insert(w, Traits.byId[m].name)
			end
			return string.lower(table.concat(w, " "))
		end
		local function pos(list, id): number
			return table.find(list, id) or 0
		end
		local box = p.PlayerGui:FindFirstChild("PalSearch", true)
		local tb = if box then box:FindFirstChild("Box") else nil
		H.expect(tb ~= nil and tb:IsA("TextBox") and H.buttonNamed(p, "Sort_rarity") ~= nil and H.buttonNamed(p, "Sort_muts") ~= nil, "hatchery", "the parent picker: a search box and two orders, Rarity and Mutations")
		local all = listed()
		local byRarity = true
		for i = 2, #all do
			if rarityOf(all[i]) > rarityOf(all[i - 1]) then
				byRarity = false
			end
		end
		H.expect(#all == #prof.pals and byRarity and pos(all, rareId) > 0 and pos(all, rareId) < pos(all, mutId), "hatchery", "every driftling, the rarest kind first (Rarity, the order it opens with)", string.format("%d of %d listed, Pyrelord %d, the Workaholic Gullfin %d", #all, #prof.pals, pos(all, rareId), pos(all, mutId)))
		H.clickNamed(p, "Sort_muts", { wait = 0.2 })
		local bym = listed()
		local byMuts = true
		for i = 2, #bym do
			if topTier(bym[i]) > topTier(bym[i - 1]) then
				byMuts = false
			end
		end
		local want = H.inClient(p, MenusC.debugParents, nil, "", "muts")
		H.expect(#bym == #all and byMuts and pos(bym, mutId) < pos(bym, rareId) and table.concat(bym, ",") == table.concat(want, ","), "hatchery", "Mutations: the rarest mutations first (a tier 4 one before the rarest kind with none)", string.format("Gullfin %d, Pyrelord %d", pos(bym, mutId), pos(bym, rareId)))
		local function search(text: string): { number }
			H.inClient(p, function()
				(tb :: any).Text = text
			end)
			E.run(0.2)
			return listed()
		end
		-- (what it finds is exactly the ones with those words, in any case)
		local function exact(got: { number }, q: string): boolean
			local n = 0
			for _, x in prof.pals do
				local has = string.find(wordsOf(x), string.lower(q), 1, true) ~= nil
				if has then
					n += 1
				end
				if has ~= (pos(got, x.id) > 0) then
					return false
				end
			end
			return n == #got
		end
		local byKind = search("Pyre")
		H.expect(pos(byKind, rareId) > 0 and exact(byKind, "pyre"), "hatchery", "the search finds a kind by name (\"Pyre\": the Pyrelords)", #byKind .. " listed")
		local mname = Traits.byId[Traits.at("busy", 4)].name
		local byMut = search(string.upper(mname))
		H.expect(pos(byMut, mutId) > 0 and exact(byMut, mname), "hatchery", "and a mutation by its name, in any case", mname .. ": " .. #byMut .. " listed")
		local none = search("zzqx")
		H.expect(#none == 0 and p.PlayerGui:FindFirstChild("NoParent", true) ~= nil, "hatchery", "nothing matching: a line saying so")
		local back = search("")
		H.expect(#back == #all, "hatchery", "an empty search lists them all again", #back .. " of " .. #all)
		H.clickNamed(p, "Sort_rarity", { wait = 0.2 })
		H.expect(table.concat(listed(), ",") == table.concat(all, ","), "hatchery", "and Rarity puts the rarest kind first again")
	end
	H.clickNamed(p, "PickParent_" .. ids[1], { wait = 0.4 })
	H.clickNamed(p, "Slot_b_" .. uid, { wait = 0.4 })
	H.expect(H.buttonNamed(p, "PickParent_" .. ids[1]) == nil, "hatchery", "the first parent is not offered again")
	H.clickNamed(p, "PickParent_" .. ids[2], { wait = 0.4 })
	-- the panel's words (2026-11-15: "say Breed two driftlings for an egg. also, specify what happens to the result,
	-- such as mutations and rarity"; 2026-11-19: "In hatchery, show the resultant mutation combination the pet will
	-- have"): the rule in the hint, the egg's own mutations (Logic/Breed.preview) and its price on the pair's line
	local preview = Breed.preview(prof, ids[1], ids[2])
	do
		local hint = p.PlayerGui:FindFirstChild("Hint", true)
		local cost = p.PlayerGui:FindFirstChild("Cost", true)
		local ht = if hint then table.concat(H.textsOf(hint), " ") else ""
		local ct = if cost then table.concat(H.textsOf(cost), " ") else ""
		H.expect(string.find(ht, "Breed two driftlings for an egg.", 1, true) ~= nil and string.find(ht, "best mutations", 1, true) ~= nil, "hatchery", "the hint: breed two for an egg, it gets their best mutations", ht)
		H.expect(preview ~= nil and string.find(ct, Numbers.coins(preview.price) .. " coins, hatches in", 1, true) ~= nil, "hatchery", "the pair's line: the price and the time", ct)
		local row = p.PlayerGui:FindFirstChild("Hatch_" .. uid, true)
		local shown = 0
		for _, id in if preview then preview.muts else {} do
			if row and row:FindFirstChild("Mut_" .. id, true) then
				shown += 1
			end
		end
		H.expect(preview ~= nil and row ~= nil and row:FindFirstChild("MutsLead", true) ~= nil and (shown == #preview.muts or (#preview.muts == 0 and row:FindFirstChild("Muts", true) ~= nil)), "hatchery", "the egg's mutations shown before Breed (Hatches with:)", string.format("%d of %d", shown, if preview then #preview.muts else -1))
		local panel = if hint then hint.Parent else nil
		local feastSeen = false
		for _, t in if panel then H.textsOf(panel) else {} do
			if string.find(string.lower(t), "feast", 1, true) then
				feastSeen = true
			end
		end
		H.expect(not feastSeen, "hatchery", "no feast in the panel")
	end
	-- the egg is paid for in shells: none in store, no egg
	local feast = Breed.cost("gullfin")
	prof.shells = 0
	H.push(p, 0.3)
	H.openPanel(p, "hatch")
	H.expect(H.buttonNamed(p, "Breed_" .. uid) == nil and H.buttonNamed(p, "Breed_" .. uid, true) ~= nil, "hatchery", "Breed is off without the shells")
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
	H.expect(egg ~= nil and preview ~= nil and table.concat(egg.muts, ",") == table.concat(preview.muts, ","), "hatchery", "with the very mutations the panel showed", egg and table.concat(egg.muts, ","))
	local paid = shells0 - prof.shells
	H.expect(paid <= feast + 1e-6 and paid >= feast - made, "hatchery", "the egg paid for in shells", string.format("%.2f paid, the price %d", paid, feast))
	-- (Finish now sits in the warming egg's row, the hint the panel's whole width)
	H.push(p, 0.3)
	H.openPanel(p, "hatch")
	local hrow = p.PlayerGui:FindFirstChild("Hatch_" .. uid, true)
	H.expect(hrow ~= nil and hrow:FindFirstChild("FinishNow", true) ~= nil, "hatchery", "Finish now in the warming egg's row")
	local swift = false
	for _, id in egg and egg.muts or {} do
		-- (the parents' Leafy mutation loads as Lucky since 2026-11-14)
		if id == "bright2" or id == "bright3" then
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
	-- the turns: the egg on the panel and the tag over the Hatchery count down; then they are ready and wait for a tap
	-- (the request of 2026-11-20: "the hatchery should have the timer above its building, and show ready! once the egg
	-- is ready. clicking it while ready shows the hatching screen just like hatching an egg normally, but with the
	-- resultant creature")
	H.openPanel(p, "hatch")
	local BTh = H.cmod(p, "Controllers.BuildingTags")
	local HSh = H.cmod(p, "UI.HatchScene")
	local NumbersH = H.sharedServer("Logic.Numbers")
	-- (the time left: its turns, the one going now partly done, Tuning.TurnSeconds each)
	local function dueIn(e): number
		return (e.left - 1) * Tuning.TurnSeconds + (Tuning.TurnSeconds - H.session(p).turnClock)
	end
	-- (the time left in minutes or hours, never turns: "instead of "Hatches after x turns", describe it in minutes or
	-- hours")
	do
		local left = p.PlayerGui:FindFirstChild("EggLeft", true)
		local due = if egg then dueIn(egg) else 0
		local ok = left ~= nil and not string.find(left.Text, "turn", 1, true) and (left.Text == "Hatches in " .. NumbersH.duration(due) or left.Text == "Hatches in " .. NumbersH.duration(due + 2) or left.Text == "Hatches in " .. NumbersH.duration(due - 2))
		H.expect(ok, "hatchery", "the egg's time left in minutes", left and left.Text)
	end
	H.closePanel(p)
	H.push(p, 0.6)
	local function tagOf(u: number)
		for _, t in H.inClient(p, BTh.debugHatch) do
			if t.uid == u then
				return t
			end
		end
		return nil
	end
	do
		local t = tagOf(uid)
		local m, sec = string.match(t and t.words or "", "^(%d+):(%d%d)$")
		local shown = (tonumber(m) or -1) * 60 + (tonumber(sec) or 0)
		local due = if egg then dueIn(egg) else -99
		H.expect(t ~= nil and t.shown and not t.ready and m ~= nil and math.abs(shown - due) <= 2, "hatchery", "a timer over the Hatchery: the time till the egg is ready", string.format("%s, due in %.1f s", t and t.words or "no tag", due))
		H.expect(tagOf(uids[2] or 0) ~= nil, "hatchery", "and over the other Hatchery with its egg")
		H.push(p, 2)
		local t2 = tagOf(uid)
		local m2, s2 = string.match(t2 and t2.words or "", "^(%d+):(%d%d)$")
		local shown2 = (tonumber(m2) or -1) * 60 + (tonumber(s2) or 0)
		H.expect(m2 ~= nil and shown2 < shown and shown - shown2 <= 3, "hatchery", "counting down by the second", string.format("%s then %s", t and t.words or "?", t2 and t2.words or "?"))
	end
	local pals0 = #prof.pals
	local i0 = #fx
	local turns = egg and egg.left or 0
	for _ = 1, turns do
		nextTurn()
	end
	E.run(0.5)
	local news = nil
	for i = i0 + 1, #fx do
		if fx[i].kind == "turn" and type(fx[i].ready) == "table" then
			news = fx[i].ready
		end
	end
	H.expect(news ~= nil and #news == 2 and news[1].sp == "gullfin" and news[2].sp == "gullfin" and news[1].uid == uid, "hatchery", "both eggs ready after their turns (the turn's news)", tostring(news and #news))
	H.expect(#prof.eggs == 2 and prof.eggs[1].left == 0 and prof.eggs[2].left == 0 and #prof.pals == pals0 and prof.stats.hatched == 0, "hatchery", "nothing hatches by itself: the ready eggs wait at their Hatcheries", string.format("%d eggs, %d -> %d driftlings", #prof.eggs, pals0, #prof.pals))
	nextTurn()
	H.expect(#prof.eggs == 2 and prof.eggs[1].left == 0 and #prof.pals == pals0, "hatchery", "a turn later still waiting")
	H.push(p, 0.3)
	do
		local t = tagOf(uid)
		H.expect(t ~= nil and t.shown and t.ready and t.words == "Ready!", "hatchery", "the tag says Ready!", t and t.words)
	end
	-- the panel: Ready to hatch, a Hatch button (no Finish now: nothing warming)
	H.openPanel(p, "hatch")
	do
		local left = p.PlayerGui:FindFirstChild("EggLeft", true)
		H.expect(left ~= nil and left.Text == "Ready to hatch." and H.buttonNamed(p, "HatchNow_" .. uid) ~= nil and H.buttonNamed(p, "FinishNow") == nil, "hatchery", "the panel: Ready to hatch., a Hatch button and no Finish now", left and left.Text)
		H.expect(H.buttonNamed(p, "HatchAll") ~= nil, "hatchery", "two ready: Hatch all too")
	end
	H.closePanel(p)
	-- a tap on the tag: the hatch scene with what came out, the driftling into the hut with room
	H.clickNamed(p, "HatchTap_" .. uid, { wait = 0.5 })
	local hs = H.inClient(p, HSh.debugState)
	H.expect(hs.open and hs.r == 2 and hs.hr == 2, "hatchery", "a tap on Ready! plays the hatch scene with the hatchling (an uncommon egg for a Gullfin, no rarer roll)", string.format("open %s, r %d hr %d", tostring(hs.open), hs.r, hs.hr))
	H.expect(tagOf(uid) == nil and tagOf(uids[2] or 0) == nil, "hatchery", "no tags over the hatch scene")
	-- (tapped through to its end, as a player would)
	local function sceneOut()
		for _ = 1, 60 do
			if not H.inClient(p, HSh.isOpen) then
				break
			end
			H.inClient(p, HSh.skip)
			E.run(0.4)
		end
		E.run(0.4)
	end
	sceneOut()
	H.expect(not H.inClient(p, HSh.isOpen), "hatchery", "(the hatch scene over)")
	H.expect(#prof.eggs == 1 and #prof.pals == pals0 + 1 and prof.stats.hatched == 1 and tagOf(uid) == nil, "hatchery", "hatched: the egg gone, its tag too, one more driftling", string.format("%d eggs, %d driftlings", #prof.eggs, #prof.pals))
	-- the other with a tap on the Hatchery itself (into no hut: they're full)
	do
		local model: Instance? = nil
		local plotModel = E.workspace.Plots:FindFirstChild("Plot_" .. H.session(p).plot)
		for _, d in (if plotModel then plotModel:GetDescendants() else {}) do
			if model == nil and d:IsA("Model") and d:GetAttribute("Decor") == "hatchery" and string.match(d.Name, "^(%d+):") == tostring(uids[2]) then
				model = d
			end
		end
		local PRh = H.cmod(p, "Pixel.PixelRenderer")
		local WVh = H.cmod(p, "Controllers.WorldView")
		if H.expect(model ~= nil, "hatchery", "(the second Hatchery's model)") then
			local at = (model :: Model):GetPivot().Position + E.v3(0, 1.5, 0)
			local pos = H.inClient(p, function()
				local sp = PRh.project(at)
				return E.v2(sp.X, sp.Y - E.inset)
			end)
			E.raycastParts = true
			H.inClient(p, WVh.tapScreen, pos)
			E.raycastParts = nil
			E.run(0.6)
		end
	end
	H.expect(#prof.eggs == 0 and #prof.pals == pals0 + 2 and prof.stats.hatched == 2, "hatchery", "a tap on the other Hatchery hatches its ready egg", string.format("%d eggs, %d driftlings", #prof.eggs, #prof.pals))
	sceneOut()
	H.expect(H.req(p, "breed.hatch", { uid = uid }).err == "not_found", "hatchery", "nothing left to hatch there (not_found)")
	local born = {}
	for _, x in prof.pals do
		if x.sp == "gullfin" and x.id ~= ids[1] and x.id ~= ids[2] and table.find(fillers, x.id) == nil then
			table.insert(born, x)
		end
	end
	table.sort(born, function(a, b)
		return a.id < b.id
	end)
	-- (the two newest Gullfins)
	while #born > 2 do
		table.remove(born, 1)
	end
	H.expect(#born == 2 and born[1].home ~= 0 and born[2].home == 0 and born[2].work == 0, "hatchery", "the first into the hut with room, the second waiting with no hut", string.format("homes %s %s", tostring(born[1] and born[1].home), tostring(born[2] and born[2].home)))
	H.expect(#born == 2 and born[1].lvl == nil and born[1].sp == "gullfin", "hatchery", "its parents' kind (no levels)")
	H.checkProfile(p, "hatched")
	-- a place freed (one sold): the waiting one moves in
	local rs = H.req(p, "pal.sell", { id = fillers[1] or 0 })
	H.expect(rs.ok and born[2] ~= nil and born[2].home ~= 0, "hatchery", "one sold: the hatchling waiting moves into its place", string.format("%s home %s", tostring(rs.err), tostring(born[2] and born[2].home)))
	H.closePanel(p)
	-- Hatch all (the request of 2026-11-22: "and hatchery as well, make a open all hatchery eggs"): two eggs ready at
	-- once, the panel's Hatch all hatches both with no hatch scene, the Hatched panel shows a card for each, Back goes
	-- to the Hatchery
	do
		for _, u in uids do
			H.req(p, "breed.start", { uid = u, a = ids[1], b = ids[2] })
		end
		local hatched0 = prof.stats.hatched
		H.expect(H.req(p, "breed.hatchAll", {}).err == "not_found", "hatchall", "none ready: not_found")
		for _, e in prof.eggs do
			e.left = 0
		end
		local n0 = #prof.pals
		H.push(p, 0.4)
		H.openPanel(p, "hatch")
		H.expect(#prof.eggs == 2 and H.buttonNamed(p, "HatchAll") ~= nil, "hatchall", "two ready: the panel's Hatch all", tostring(#prof.eggs))
		H.clickNamed(p, "HatchAll", { wait = 0.6 })
		local cards = 0
		for _, d in p.PlayerGui:GetDescendants() do
			if string.sub(d.Name, 1, 4) == "Got_" then
				cards += 1
			end
		end
		H.expect(#prof.eggs == 0 and #prof.pals == n0 + 2 and prof.stats.hatched == hatched0 + 2, "hatchall", "both hatched at once", string.format("%d eggs, %d new", #prof.eggs, #prof.pals - n0))
		H.expect(not H.inClient(p, HSh.isOpen) and H.currentPanel(p) == "hatched" and cards == 2, "hatchall", "no hatch scene: the Hatched panel with a card each", string.format("%s, %d cards", tostring(H.currentPanel(p)), cards))
		H.clickNamed(p, "Back", { wait = 0.4 })
		H.expect(H.currentPanel(p) == "hatch" and H.buttonNamed(p, "HatchAll") == nil, "hatchall", "Back to the Hatchery, nothing left to hatch", tostring(H.currentPanel(p)))
		H.closePanel(p)
	end
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
------------------------------------------------------------------ the seasons and the weather
E.phase = "weather"
-- (GAME_DESIGN 13: "also, make weather and seasons, and eggs spawns are affected by these with different mutations"):
-- the client's sea clock follows the server's, the HUD's status lines show the season and the weather of that clock, the
-- weather turning is told (Fx weather) and the islands show it; the tree's eggs keep the season they were laid in,
-- some laid in the rain are touched by it (the plot's Eggs attribute marks them) and one hatches with the rain's
-- mutation
do
	local WC = H.smod("WorldClock")
	local WL = H.sharedServer("Logic.Weather")
	local SCp = H.cmod(p, "Controllers.StateClient")
	local Chip = H.cmod(p, "UI.WeatherChip")
	local WV = H.cmod(p, "Controllers.WeatherView")
	E.run(1.2)
	local v = H.view(p)
	local sea, seen = WC.now(), H.inClient(p, SCp.seaClock)
	H.expect(v ~= nil and type(v.clock) == "number" and math.abs(seen - sea) < 1.5, "weather", "the client's sea clock is the server's", string.format("%.1f vs %.1f", seen, sea))
	E.run(0.6)
	local st = WL.at(WC.now())
	local chip = H.inClient(p, Chip.debugState)
	H.expect(chip.season == st.season and chip.weather == st.kind, "weather", "the HUD shows the season and the weather now", string.format("%s %s vs %s %s", chip.season, chip.weather, st.season, st.kind))
	-- (one line: the top bar's chips after the shells, Hud.topChip: the season's name, the weather's name; no day count:
	-- "also, this can be compressed into one line. remove the "day 1" as well")
	do
		local WD = H.sharedServer("Data.Weather")
		local pg = p:FindFirstChild("PlayerGui")
		local bar: Instance? = nil
		local function words(name: string): string
			local c = pg and pg:FindFirstChild("Chip_" .. name, true)
			bar = bar or (c and c.Parent)
			local t = c and c:FindFirstChild("Value")
			return if t and t:IsA("TextLabel") then t.Text else ""
		end
		local sw, ww = words("season"), words("weather")
		H.expect(bar ~= nil and (bar :: any).Name == "TopBar" and string.find(sw, WD.seasonById[st.season].name, 1, true) == 1 and string.find(ww, WD.byId[st.kind].name, 1, true) == 1, "weather", "the top bar's line has a chip for each", string.format("%q %q", tostring(sw), tostring(ww)))
		H.expect(pg ~= nil and pg:FindFirstChild("Chip_day", true) == nil and pg:FindFirstChild("Status_season", true) == nil, "weather", "no day count, no second line")
	end
	-- a rainy spell ahead: the clock jumped just into it
	local target = nil
	for k = 1, 600 do
		local tt = WC.now() + k * Tuning.WeatherSecs
		if WL.at(tt).kind == "rain" then
			target = tt
			break
		end
	end
	if H.expect(target ~= nil, "weather", "(a rainy spell ahead)") then
		local f0 = #fx
		local start = Tuning.WeatherEpoch + WL.at(target :: number).spell * Tuning.WeatherSecs
		WC.shift(start + 5 - WC.now())
		E.run(1.5)
		local told = false
		for k = f0 + 1, #fx do
			if fx[k].kind == "weather" and fx[k].wx == "rain" then
				told = true
			end
		end
		H.expect(told, "weather", "the weather turning is told to the player (Fx weather)")
		E.run(0.6)
		chip = H.inClient(p, Chip.debugState)
		local wv = H.inClient(p, WV.debugState)
		H.expect(chip.weather == "rain" and wv.kind == "rain", "weather", "the HUD and the islands show the rain", string.format("%s %s", chip.weather, wv.kind))
		-- lots laid in the rain until an egg is touched
		local touched = nil
		local season = WL.at(WC.now()).season
		local allSeason = true
		for _ = 1, 15 do
			prof.clutch.left = 0.05
			E.run(0.3)
			for _, e in prof.clutch.list do
				allSeason = allSeason and e.ss == season
				if e.wx == "rain" and touched == nil then
					touched = e
				end
			end
			if touched then
				break
			end
		end
		H.expect(allSeason, "weather", "every egg keeps the season it was laid in", season)
		if H.expect(touched ~= nil, "weather", "an egg laid in the rain is touched by it") then
			local egg = touched :: any
			E.run(0.4)
			local m = E.workspace.Plots:FindFirstChild("Plot_" .. s.plot)
			local attr = m and m:GetAttribute("Eggs") or ""
			H.expect(string.find(";" .. tostring(attr) .. ";", string.format(";%d.%d.rain;", egg.id, egg.r), 1, true) ~= nil, "weather", "the plot's Eggs attribute marks it (id.r.rain)", tostring(attr))
			local ve = nil
			for _, x in (H.view(p) :: any).clutch do
				if x.id == egg.id then
					ve = x
				end
			end
			H.expect(ve ~= nil and ve.wx == "rain" and ve.wt == egg.wt, "weather", "the client's view has its weather and tier")
			-- hatched (every hut is full here: swapping out the weakest)
			prof.shells += Tree.cost(prof, egg.r) + 10
			local swap = 0
			for _, x in prof.pals do
				if x.home ~= 0 then
					swap = x.id
				end
			end
			local want = WL.mutation(egg.wx, egg.wt)
			local res = H.req(p, "egg.hatch", { id = egg.id, swap = if Tree.room(prof) > 0 then 0 else swap })
			local d = res and res.data
			H.expect(res.ok and type(d) == "table" and d.wm == want and table.find(d.muts, want) ~= nil, "weather", "it hatches with the rain's mutation", string.format("%s %s %s", tostring(res.err), tostring(d and d.wm), tostring(want)))
		end
	end
	H.checkProfile(p, "weather")
end

------------------------------------------------------------------ no night
E.phase = "daynight"
-- no day and night (the request of 2026-11-14: "remove the day night cycle, and make everything brighter"): whatever
-- the sea's clock says, the light is the same bright day (UI/DayLight's BRIGHT grade: lighter, never dark, no lamp
-- pools; with the filter off, as in this engine, Roblox's own clock stays at early afternoon) and the music is the
-- day's; the crickets follow the sky's own night since 2026-11-20 (only the sky turns to night)
do
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local DL = H.cmod(p, "Controllers.DayLight")
	local Aud = H.cmod(p, "Controllers.Audio")
	local same = true
	for _, f in { 0.05, 0.35, 0.68, 0.75, 0.88 } do
		local g = DL.at(f)
		same = same and g ~= nil and g.mr >= 1 and g.mg >= 1 and g.mb >= 1 and g.lamps == 0 and g == DL.at(0.35)
	end
	H.expect(same, "daynight", "the same bright grade at every hour (lighter than plain, no lamps)")
	local WC = H.smod("WorldClock")
	local function at(want)
		WC.shift(((want - WC.dayFrac()) % 1) * Tuning.DaySeconds)
		E.run(1.3)
		local off = H.inClient(p, PR.tier) == "off"
		local st = H.inClient(p, DL.debugState)
		return st, off
	end
	local _ = Aud
	for _, f in { 0.3, 0.86, 0.1 } do
		local st, off = at(f)
		H.expect(st.frac == DL.frac() and (if off then st.clock >= 12 and st.clock <= 15 else true), "daynight", string.format("bright day at %.2f of the calendar day", f), string.format("frac %.2f, clock %s", st.frac, tostring(st.clock)))
	end
	-- the crickets follow the sky's own night (DayLight.night, the request of 2026-11-20 for a day and night cycle in the
	-- sky), not the calendar: silent with the sky held at noon, singing with it held at midnight
	local function crickets(h)
		H.inClient(p, DL.debugSky, h)
		E.run(2.5)
		return H.inClient(p, function()
			local snd = E.find("SoundService"):FindFirstChild("Ambience_crickets", true)
			return if snd and snd:IsA("Sound") then snd.Volume else 0
		end)
	end
	local noonVol, nightVol = crickets(0.5), crickets(0.95)
	H.inClient(p, DL.debugSky, nil)
	H.expect(noonVol < 0.01 and nightVol > 0.05, "daynight", "the crickets sing in the sky's night and not at its noon, whatever the calendar's hour", string.format("noon %.3f, midnight %.3f", noonVol, nightVol))
end

------------------------------------------------------------------ the rewards (GAME_DESIGN 15)
-- The request (2026-11-19): "add rewards for playtime, daily rewards, streak rewards, codes, and as many retention
-- features you can think of". Through the Rewards sheet as a player: the menu bar's Gifts and its dot, the daily reward
-- and its streak over two days, a gift for playing, a task and the bonus, the Lucky Spin, the codes, an Index gift.
E.phase = "rewards"
do
	local RewardsL = H.sharedServer("Logic.Rewards")
	local RewardsD = H.sharedServer("Data.Rewards")
	local WC = H.smod("WorldClock")
	H.closePanel(p)
	H.push(p, 0.4)
	E.run(0.6)
	local gifts = H.buttonNamed(p, "Menu_rewards")
	local dot = gifts and gifts:FindFirstChild("Dot")
	H.expect(gifts ~= nil and dot ~= nil and dot.Visible, "rewards", "the menu bar's Gifts, a red dot on it while something waits")
	local st = p.PlayerGui:FindFirstChild("Status_gift", true)
	H.expect(st ~= nil, "rewards", "the HUD's line about the next gift")
	-- (the request of 2026-11-20: "make this clickable to open the gift tab": today's reward waits, so Today)
	local RewardsC = H.cmod(p, "UI.RewardsUI")
	H.expect(H.clickNamed(p, "StatusTap_gift", { wait = 0.5 }) and H.currentPanel(p) == "rewards" and RewardsC.tabOf() == "today", "rewards", "a tap on the gift's line opens the Rewards sheet on Today, where the gift waits", tostring(H.currentPanel(p)) .. " " .. tostring(RewardsC.tabOf()))
	H.closePanel(p)
	E.run(0.4)
	H.clickNamed(p, "Menu_rewards", { wait = 0.5 })
	H.expect(H.currentPanel(p) == "rewards", "rewards", "Gifts opens the Rewards sheet", tostring(H.currentPanel(p)))
	-- the daily reward: today's, then refused till tomorrow; tomorrow's goes on the streak
	local n0 = #fx
	H.clickNamed(p, "DailyClaim", { wait = 0.5 })
	local d = prof.rewards.daily
	local today = RewardsL.day(WC.now())
	H.expect(d.last == today and d.streak >= 1, "rewards", "Claim takes today's reward", string.format("last %d today %d streak %d", d.last, today, d.streak))
	local told = false
	for i = n0 + 1, #fx do
		if fx[i].kind == "rewards" and fx[i].from == "daily" then
			told = true
		end
	end
	H.expect(told, "rewards", "and says what came (Fx rewards)")
	H.expect(H.req(p, "reward.daily", {}).err == "cooldown", "rewards", "a second claim the same day is refused (cooldown)")
	local streak1 = d.streak
	WC.shift(86400)
	H.push(p, 0.5)
	H.openPanel(p, "rewards", "today")
	H.clickNamed(p, "DailyClaim", { wait = 0.5 })
	H.expect(prof.rewards.daily.streak == streak1 + 1, "rewards", "the next day's claim carries the streak on", string.format("%d -> %d", streak1, prof.rewards.daily.streak))
	-- a gift for playing: the first one's minutes in, Claim on the sheet
	prof.rewards.play.secs = RewardsD.PLAY[1].min * 60 + 5
	H.push(p, 0.5)
	H.openPanel(p, "rewards", "today")
	local s0 = prof.shells
	H.clickNamed(p, "PlayClaim", { wait = 0.5 })
	H.expect(table.find(prof.rewards.play.got, 1) ~= nil and prof.shells > s0, "rewards", "the first gift for playing claimed", string.format("got %d, shells %+d", #prof.rewards.play.got, prof.shells - s0))
	H.expect(H.req(p, "reward.play", { i = 2 }).err == "not_done", "rewards", "the next one waits for its minutes (not_done)")
	-- today's tasks: one done (its stat moved on from where it was dealt), Claim; the bonus once all three are in
	H.openPanel(p, "rewards", "tasks")
	local tk = prof.rewards.tasks
	H.expect(#tk.list == RewardsD.TASK_COUNT, "rewards", "three tasks dealt today", tostring(#tk.list))
	for _, t in tk.list do
		t.at -= t.n + 1
	end
	if tk.list[1] and tk.list[1].id == "earn" then
		-- (the shells task counts what the island earned)
		prof.stats.earned += tk.list[1].n + 1
	end
	H.push(p, 0.5)
	H.openPanel(p, "rewards", "tasks")
	H.clickNamed(p, "TaskClaim_1", { wait = 0.4 })
	H.expect(tk.got[1] == true, "rewards", "a done task claimed from the sheet")
	H.expect(H.req(p, "reward.bonus", {}).err == "not_done", "rewards", "no bonus before all three are claimed")
	for i = 2, #tk.list do
		H.req(p, "reward.task", { i = i })
	end
	H.push(p, 0.4)
	H.openPanel(p, "rewards", "tasks")
	H.clickNamed(p, "BonusClaim", { wait = 0.4 })
	H.expect(tk.bonus == true, "rewards", "the bonus for all three")
	-- the Lucky Spin: the free spin (and the spins the rewards gave), the light stops on the prize
	H.openPanel(p, "rewards", "spin")
	local spins0 = RewardsL.spins(prof, WC.now())
	local total0 = prof.rewards.spin.total
	H.expect(spins0 >= 1, "rewards", "a spin in hand", tostring(spins0))
	H.clickNamed(p, "Spin", { wait = 0.3 })
	H.expect(prof.rewards.spin.total == total0 + 1, "rewards", "Spin turns the Lucky Spin", tostring(prof.rewards.spin.total))
	E.run(6)
	local said = H.inClient(p, function()
		local sheet = p.PlayerGui:FindFirstChild("Panel_rewards", true)
		local s = sheet and sheet:FindFirstChild("Status", true)
		return if s and s:IsA("TextLabel") then s.Text else ""
	end)
	H.expect(string.find(said, "Lucky Spin", 1, true) ~= nil, "rewards", "once the light stops, the sheet says what it gave", said)
	-- Skip (the request of 2026-11-20: "make a skip for lucky shell spinning"): while the light runs, Spin reads Skip,
	-- and a tap lands it on the prize at once
	prof.rewards.spin.extra = (prof.rewards.spin.extra or 0) + 1
	H.push(p, 0.4)
	H.openPanel(p, "rewards", "spin")
	local total1 = prof.rewards.spin.total
	H.clickNamed(p, "Spin", { wait = 0.2 })
	H.expect(prof.rewards.spin.total == total1 + 1, "rewards", "a second spin turns", tostring(prof.rewards.spin.total))
	H.expect(H.buttonNamed(p, "SkipSpin") ~= nil and H.buttonNamed(p, "Spin", true) == nil, "rewards", "while the light runs, Spin reads Skip")
	H.clickNamed(p, "SkipSpin", { wait = 0.3 })
	H.expect(H.buttonNamed(p, "Spin", true) ~= nil and H.buttonNamed(p, "SkipSpin", true) == nil, "rewards", "Skip lands the light on the prize at once (Spin is back)")
	prof.rewards.spin.extra = 0
	local rs = H.req(p, "reward.spin", {})
	H.expect(not rs.ok and rs.err == "not_done", "rewards", "no spins left: refused (not_done)", tostring(rs.err))
	-- the codes: a good one once, a used one, a made-up one
	H.openPanel(p, "rewards", "codes")
	local box = p.PlayerGui:FindFirstChild("CodeField", true)
	local tb = box and box:FindFirstChild("Box")
	if H.expect(tb ~= nil, "rewards", "the code box") then
		local luck0 = prof.boosts.luck or 0
		H.inClient(p, function()
			tb.Text = "  welcome "
		end)
		H.clickNamed(p, "Redeem", { wait = 0.5 })
		H.expect(prof.rewards.codes.WELCOME == true and (prof.boosts.luck or 0) > luck0, "rewards", "a code typed any case with spaces round it gives its gift (WELCOME: shells and a Lucky Hour)", tostring(prof.boosts.luck))
		H.expect(H.req(p, "code.redeem", { code = "WELCOME" }).err == "used", "rewards", "the same code again: used")
		H.expect(H.req(p, "code.redeem", { code = "NOTACODE" }).err == "not_found", "rewards", "a made-up code: not_found")
		H.expect(H.req(p, "code.redeem", { code = string.rep("x", 400) }).err ~= nil, "rewards", "a very long code is refused")
	end
	-- the Lucky Hour on the HUD and in the eggs' luck
	E.run(0.6)
	H.expect(p.PlayerGui:FindFirstChild("Status_boost_luck", true) ~= nil, "rewards", "the Lucky Hour's line on the HUD")
	H.expect(Tree.luck(prof) >= 1 + Tuning.EggLuck[prof.tier] + Tuning.TimedLuck - 1e-9, "rewards", "and the eggs that much luckier", string.format("%.2f", Tree.luck(prof)))
	-- the Index's first gift
	local need = RewardsD.INDEX[1].n
	local CreaturesD = H.sharedServer("Data.Creatures")
	local k = 0
	for _, c in CreaturesD.list do
		if k < need then
			prof.seen[c.id] = 2
			k += 1
		end
	end
	H.push(p, 0.4)
	H.openPanel(p, "rewards", "index")
	H.clickNamed(p, "IndexClaim_1", { wait = 0.4 })
	H.expect(table.find(prof.rewards.index.got, need) ~= nil, "rewards", "the Index's first gift claimed", tostring(#prof.rewards.index.got))
	H.expect(H.req(p, "reward.index", { i = 1 }).err == "used", "rewards", "and only once (used)")
	H.closePanel(p)
	H.checkProfile(p, "rewards")
end

H.checkProfile(p, "end")
settled(p)
H.checkMirror(p, "end")
H.checkProfile(q, "end")
settled(q)
H.checkMirror(q, "end")

report(E, H)
