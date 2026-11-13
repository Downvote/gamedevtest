-- The island's clock (GAME_DESIGN 3-6; docs/ARCHITECTURE.md 7.4): a turn every Tuning.TurnSeconds while the player is
-- here, open menus and Build mode holding nothing; the wood and shells a day makes matching Island.rates (to a tick);
-- the stores reaching the client every second (Fx tick); the tide on the server's time: a driftling coming in every
-- second and floating past in TideLife seconds (Fx tide, the client patching its copy with no whole view sent for it,
-- the Tide card's time-left bars running down); nothing eating (no food since 2026-11-13: the stores only grow,
-- even from none); a driftling waiting with no hut while every hut is full, moving in once a hut goes up and going to
-- work once a building of its knack does; the Hatchery's egg (a feast of shells) hatching into a hut with room, or
-- waiting with no hut; two islands each on their own clock. (The huts are full while the rates are measured, and
-- nobody takes a driftling off the tide, so nobody new goes to work.)
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
local Tide = H.sharedServer("Logic.Tide")
local Breed = H.sharedServer("Logic.Breed")

local p = H.addPlayer({ userId = 9301, name = "Clock" })
E.run(1)
local fx = H.watchFx(p)
local prof = H.profile(p)
local s = H.session(p)
-- (when each tide message reaches the client, on the server's time, and how many whole views it gets: the tide's news
-- are patched into the view, so no whole view comes every second)
local SC = H.cmod(p, "Controllers.StateClient")
local tideAt, views = {}, 0
H.inClient(p, function()
	SC.Fx:Connect(function(msg)
		if msg.kind == "tide" then
			table.insert(tideAt, { msg = msg, now = E.workspace:GetServerTimeNow() })
		end
	end)
	SC.Changed:Connect(function()
		views += 1
	end)
end)
-- every drift this session's tide has had (its `at` and `life`): the ones running past now, and each that comes in
local known = {}
for _, d in s.tide.list do
	known[d.id] = { at = d.at, life = d.life }
end
-- The client's copy of the tide follows the session's from the Fx (one a second): one that just came is on its way
-- for a moment. Wait it out before comparing the two.
local function settled(who)
	E.runUntil(function()
		local ss, v = H.session(who), H.view(who)
		if ss == nil or v == nil or #v.tide ~= #ss.tide.list then
			return false
		end
		for i, d in ss.tide.list do
			if v.tide[i].id ~= d.id then
				return false
			end
		end
		return true
	end, 1, 0.05)
end
-- A session's tide runs full: life / secs at once (one more or less for the moment one comes in as another leaves).
local function full(ss, pr): boolean
	return math.abs(#ss.tide.list - math.floor(Tide.life(pr) / Tide.secs(pr))) <= 1
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
-- own yet: the tide's are only taken in by the player)
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
	Tide.add(prof, sp, {})
end
H.push(p, 0.2)
local working = 0
for _, x in prof.pals do
	if x.work ~= 0 then
		working += 1
	end
end
H.expect(hutsN() == 4 and working == 4 and Tide.room(prof) == 0, "clock", "the two huts full, all four at work", string.format("%d in huts, %d at work", hutsN(), working))
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
local tf0, views0 = #tideAt, views
E.runUntil(function()
	return count("turn", f0) >= 2
end, Tuning.TurnSeconds * 3 + 3, 0.05)
local took = E.SIM.now - t0
H.expect(math.abs(took - Tuning.TurnSeconds * 2) < 0.6, "clock", "a turn every TurnSeconds", string.format("two turns in %.2fs", took))
E.run(0.3)
H.expect(count("turn", f0) == 2, "clock", "an Fx turn each", tostring(count("turn", f0)))
H.expect(prof.day == d0, "clock", "turns are not days (a day is hours of the sea's clock)", string.format("%d -> %d", d0, prof.day))
H.expect(math.abs(count("tick", f0) - took) <= 2, "clock", "an Fx tick every second", string.format("%d in %.1fs", count("tick", f0), took))

------------------------------------------------------------------ the tide on the server's time
-- (one comes in every second and floats past the island in TideLife seconds, on the server's time, which is
-- workspace:GetServerTimeNow: each one that came carries the moment it came, `at`, a second after the one before, and
-- its `life`, and leaves once its life is up. The ticks carry the seconds between two, no tide clock. The client
-- patches its copy of the tide from these messages, with no whole view for them, and the Tide card's bars run down.)
E.phase = "tide"
do
	local secs, life = Tide.secs(prof), Tide.life(prof)
	H.expect(math.abs(secs - Tuning.TideSecs) < 1e-9 and math.abs(life - Tuning.TideLife) < 1e-9, "tide", "one comes in every TideSecs and floats past in TideLife (no tide shares in the huts)", string.format("%s %s", tostring(secs), tostring(life)))
	local ticks = {}
	for i = f0 + 1, #fx do
		if fx[i].kind == "tick" then
			table.insert(ticks, fx[i])
		end
	end
	local carried = true
	for _, m in ticks do
		carried = carried and m.tideT == nil and type(m.tideSecs) == "number" and math.abs(m.tideSecs - secs) < 1e-9
	end
	H.expect(#ticks >= 10 and carried, "tide", "every tick carries the seconds between two (no tide clock any more)", string.format("%d ticks", #ticks))
	-- what came and what left over the two turns, and when each reached the client
	local came, gone = {}, {}
	for i = 1, #tideAt do
		local m, now = tideAt[i].msg, tideAt[i].now
		for _, d in if type(m.came) == "table" then m.came else {} do
			if type(d) == "table" and type(d.id) == "number" then
				known[d.id] = { at = d.at, life = d.life }
				if i > tf0 then
					table.insert(came, { d = d, now = now })
				end
			end
		end
		for _, id in if type(m.gone) == "table" then m.gone else {} do
			if i > tf0 then
				table.insert(gone, { id = id, now = now })
			end
		end
	end
	local spaced, onTime, lives = true, true, true
	for k, c in came do
		local prev = came[k - 1]
		if prev then
			spaced = spaced and math.abs((c.d.at - prev.d.at) - secs) < 1e-3
		end
		-- (it came at `at`: the server's step that saw it, the message on its way)
		onTime = onTime and type(c.d.at) == "number" and c.now >= c.d.at and c.now - c.d.at <= 0.25
		lives = lives and type(c.d.life) == "number" and math.abs(c.d.life - life) < 1e-6 and type(c.d.cost) == "number"
	end
	H.expect(math.abs(#came - took / secs) <= 1, "tide", "one came in every second", string.format("%d came in %.1fs", #came, took))
	H.expect(#came > 0 and spaced, "tide", "each a second after the one before, on the tide's clock")
	H.expect(#came > 0 and onTime, "tide", "each came at the server's time it says (its at)")
	H.expect(#came > 0 and lives, "tide", "each with its life (TideLife) and its cost on this island")
	local afterLife, unknown = true, 0
	for _, g in gone do
		local k = known[g.id]
		if k == nil then
			unknown += 1
		else
			afterLife = afterLife and g.now >= k.at + k.life - 1e-6 and g.now - (k.at + k.life) <= 0.25
		end
	end
	H.expect(math.abs(#gone - #came) <= 1 and unknown == 0, "tide", "as many floated off as came in", string.format("%d gone, %d came, %d unknown", #gone, #came, unknown))
	H.expect(#gone > 0 and afterLife, "tide", "each left once its life was up, on the server's time")
	local now = E.workspace:GetServerTimeNow()
	H.expect(full(s, prof) and math.abs(s.tide.clock - now) < 0.2, "tide", "TideLife / TideSecs floating past at once, the tide's clock the server's", string.format("%d floating past, clock %.2f behind", #s.tide.list, now - s.tide.clock))
	-- the client: its copy patched from the messages (the whole view only came with the turns)
	H.expect(views - views0 <= count("turn", f0) + 1, "tide", "no whole view sent for the tide (the client patches its copy)", string.format("%d views, %d tide messages", views - views0, #tideAt - tf0))
	settled(p)
	local v = H.view(p)
	local same = v ~= nil and #v.tide == #s.tide.list
	for i, d in s.tide.list do
		local e = v and v.tide[i]
		same = same and e ~= nil and e.id == d.id and e.sp == d.sp and math.abs(e.at - d.at) < 1e-6 and math.abs(e.life - d.life) < 1e-6
	end
	H.expect(same and v.tideT == nil and v.tideSecs == secs, "tide", "the view's tide is the session's, drift by drift (when each came, its life)", string.format("%d vs %d", v and #v.tide or -1, #s.tide.list))
	local along = v ~= nil
	local nowV = E.workspace:GetServerTimeNow()
	for _, d in v and v.tide or {} do
		along = along and math.abs(SC.along(d) - Tide.along(d, nowV)) < 1e-6
	end
	H.expect(along, "tide", "the client puts each one as far along as the server's time says (StateClient.along)")
	-- the Tide card: the best few, each with its time left (a bar under its name, running down)
	local TV = H.cmod(p, "Controllers.TideView")
	local UIKit = H.cmod(p, "UI.UIKit")
	local best = TV.best(v, if UIKit.phone() then 1 else 3)
	local function barOf(d): (any, any)
		local card = p.PlayerGui:FindFirstChild("TideCard", true)
		local back = card and card:FindFirstChild("TideLeft_" .. d.id)
		return back, back and back:FindFirstChild("Fill")
	end
	local bars, why = 0, {}
	local w0 = {}
	for _, d in best do
		local back, fill = barOf(d)
		if fill then
			local want = (back.Size.X.Offset - 2) * (1 - SC.along(d))
			w0[d.id] = fill.Size.X.Offset
			if math.abs(fill.Size.X.Offset - want) <= 1 then
				bars += 1
			else
				table.insert(why, string.format("%d: %d px, %.1f due", d.id, fill.Size.X.Offset, want))
			end
		else
			table.insert(why, string.format("%d: no bar", d.id))
		end
	end
	H.expect(#best >= 1 and bars == #best, "tide", "the Tide card's bars: each one's time left", table.concat(why, ", "))
	-- (a moment on, the ones still on the card have shorter bars)
	E.run(2)
	local still, shorter = 0, 0
	for _, d in best do
		local _, fill = barOf(d)
		if fill and w0[d.id] then
			still += 1
			shorter += if fill.Size.X.Offset < w0[d.id] then 1 else 0
		end
	end
	H.expect(still >= 1 and shorter == still, "tide", "and they run down", string.format("%d of %d shorter", shorter, still))
	H.expect(hutsN() == 4 and #prof.pals == 4, "tide", "nobody comes in off the tide by themselves", string.format("%d driftlings", #prof.pals))
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
	local crab = Tide.add(prof, "clawdle", {}) -- (good at fishing: nowhere on the island to fish yet)
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
	-- the island expanded twice (the buildings where the coast changed make room)
	for _ = 1, 2 do
		local rx = H.req(p, "island.expand", {})
		H.expect(rx.ok, "work", "the island expands", tostring(rx.err))
	end
	H.expect(prof.tier == 3, "work", "to the third tier", tostring(prof.tier))
	H.checkProfile(p, "expanded")
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
		local x = Tide.add(prof, "gullfin", { "swift2", if k == 1 then "angler1" else "lazy" })
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
	while Tide.room(prof) > 1 do
		table.insert(fillers, Tide.add(prof, "pebblit", {}).id)
	end
	H.push(p, 0.3)
	H.expect(Tide.room(prof) == 1, "hatchery", "(one place left in the huts)", tostring(Tide.room(prof)))
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

------------------------------------------------------------------ two islands, two clocks
E.phase = "two"
local q = H.addPlayer({ userId = 9302, name = "Tock" })
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
local nowT = E.workspace:GetServerTimeNow()
H.expect(sq.tide ~= s.tide and full(sq, pq) and full(s, prof) and sq.tide.t < Tide.secs(pq) and s.tide.t < Tide.secs(prof), "two", "each its own tide running past", string.format("%d and %d floating past", #sq.tide.list, #s.tide.list))
H.expect(math.abs(sq.tide.clock - nowT) < 0.2 and math.abs(s.tide.clock - nowT) < 0.2, "two", "both tides on the server's time", string.format("%.2f %.2f behind", nowT - sq.tide.clock, nowT - s.tide.clock))
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
