-- The tide (GAME_DESIGN 6; Logic/Tide): "use the drifting in idea. you can remove the tree of life, there should now
-- be a steady stream of driftlings, with rarities that players can pick up". End to end through the real server and
-- client: a new island's jetty with its two commons (one good with wood, one at a farm) in the view, the plot's Tide
-- attribute, the HUD's card and the world's rafts; refusals (no hut, a drift that left, malformed payloads, not enough
-- shells); the tips' buildings, then one taken in from the HUD's card and one from its price tag over the water (paid
-- for, into the hut and at work, the tips moving on); one drifting in every TideSecs, never more than TideMax, the
-- oldest drifting off (Fx tide, the Index marking each kind seen); every hut full: the swap picker, one sold for its
-- price and replaced; the tide panel's rows; selling from the Driftlings panel in two taps and filling the place from
-- the tide panel; a hut cleared away leaving its driftlings with no hut till another is built; the island grown and
-- every price going up by TideTier; a second player's client drawing the first island's tide from its attribute.
local E = require("./loader")
local H = require("./harness")
local I = require("./inst")
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
local Plot = H.sharedServer("Logic.Plot")
local Tide = H.sharedServer("Logic.Tide")
local Island = H.sharedServer("Logic.Island")
local Numbers = H.sharedServer("Logic.Numbers")
local Creatures = H.sharedServer("Data.Creatures")
local Buildings = H.sharedServer("Data.Buildings")

------------------------------------------------------------------ helpers
local p = H.addPlayer({ userId = 9601, name = "Beachcomber" })
E.run(2)
local fx = H.watchFx(p)
local s = H.session(p)
local prof = H.profile(p)
local TV = H.cmod(p, "Controllers.TideView")
local WV = H.cmod(p, "Controllers.WorldView")
local SC = H.cmod(p, "Controllers.StateClient")

-- (the tide just started on its next, so nothing drifts in while a check compares the server with the client)
local function hold()
	s.tide.t = 0
end
local function checks(label)
	hold()
	H.push(p, 0.3)
	H.checkProfile(p, label)
	H.checkMirror(p, label)
end
local function idsOf(list)
	local out = {}
	for _, d in list do
		table.insert(out, tostring(d.id))
	end
	return table.concat(out, ",")
end
-- what the plot's Tide attribute should say: "id.species" each, the oldest first
local function attrWant(sess)
	local out = {}
	for _, d in sess.tide.list do
		table.insert(out, string.format("%d.%s", d.id, d.sp))
	end
	return table.concat(out, ";")
end
local function plotModel(i)
	return E.workspace.Plots:FindFirstChild("Plot_" .. i)
end
local function gui(pl, name)
	local pg = pl:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild(name, true)
end
local function labelText(pl, name)
	local l = gui(pl, name)
	return if l and l:IsA("TextLabel") then l.Text else nil
end
local function buttonText(b)
	return if b then table.concat(H.textsOf(b), "/") else ""
end
-- the GUI objects whose names start with `prefix` (visible ones only when `vis`)
local function named(pl, prefix, vis)
	local out = {}
	for _, d in pl:FindFirstChild("PlayerGui"):GetDescendants() do
		if string.sub(d.Name, 1, #prefix) == prefix and (not vis or H.guiVisible(d)) then
			table.insert(out, d)
		end
	end
	return out
end
local function fxSince(i0, kind)
	local out = {}
	for i = i0 + 1, #fx do
		if fx[i].kind == kind then
			table.insert(out, fx[i])
		end
	end
	return out
end
local function inTide(id)
	for _, d in s.tide.list do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function viewTide(id)
	local v = H.view(p)
	for _, d in (v and v.tide or {}) do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function palOf(id)
	for _, x in prof.pals do
		if x.id == id then
			return x
		end
	end
	return nil
end
local function newPal(ids0)
	for _, x in prof.pals do
		if not ids0[x.id] then
			return x
		end
	end
	return nil
end
local function palIds()
	local out = {}
	for _, x in prof.pals do
		out[x.id] = true
	end
	return out
end
local function hutIndex(uid)
	for i, q in prof.plot.placed do
		if q.uid == uid then
			return i
		end
	end
	return 0
end
local function pieceOf(uid)
	local i = hutIndex(uid)
	return if i > 0 then prof.plot.placed[i] else nil
end
-- at work at a building of its knack, or no free place of its knack anywhere
local function workingOrNoPlace(x)
	local d = Creatures.byId[x.sp]
	if x.work ~= 0 then
		local q = pieceOf(x.work)
		return q ~= nil and Buildings.byId[q.id].knack == d.knack
	end
	return Island.freeJob(prof, d.knack) == 0
end
-- shells the island may earn in `secs` (its buildings sell while the checks run)
local function earnSlack(secs)
	return math.abs(Island.rates(prof).shells) / Tuning.TurnSeconds * (secs + 1) + 2
end
-- a raw request's refusal code (the malicious path: the remote directly)
local function rawErr(pl, action, payload)
	local okc, res = H.raw(pl, action, payload)
	E.run(0.1)
	if not okc then
		return "threw: " .. tostring(res)
	end
	if type(res) ~= "table" then
		return "no response"
	end
	return if res.ok then "ok" else tostring(res.err)
end
local function place(id)
	local x, z, rot = Plot.spot(prof.tier, prof.plot.placed, id, 6, 14, 0)
	if x == nil then
		return { ok = false, err = "no spot" }
	end
	local res = H.req(p, "plot.place", { id = id, x = x, z = z, rot = rot })
	E.run(0.2)
	return res
end
-- tap a button wherever it is (a world tag may be off screen in the fake camera): true when it was visible
local function tap(pl, name)
	local b = gui(pl, name)
	if b == nil then
		return false, false
	end
	local vis = H.guiVisible(b)
	I.fire(I.getSig(b, "Activated"), nil, 1)
	I.fire(I.getSig(b, "MouseButton1Click"))
	E.flushDeferred()
	E.run(0.6)
	return true, vis
end
local function drawn(pl, plot)
	return H.inClient(pl, H.cmod(pl, "Controllers.TideView").count, plot)
end
-- the newest one bobbing at the jetty (waiting for one when it is empty), the tide held after
local function aDrift()
	if #s.tide.list == 0 then
		E.runUntil(function()
			return #s.tide.list > 0
		end, Tide.secs(prof) + 2, 0.1)
		E.run(0.3)
	end
	hold()
	return s.tide.list[#s.tide.list] or { id = 0, sp = "", muts = {}, cost = 0 }
end

------------------------------------------------------------------ 1. a new island's jetty
E.phase = "join"
hold()
H.push(p, 0.6)
H.expect(s ~= nil and s.ready and prof.tut == 1 and #prof.pals == 0 and prof.stats.taken == 0, "join", "a new island: tips at step 1, no driftlings yet", string.format("tut %d, %d pals", prof.tut, #prof.pals))
H.expect(math.abs(prof.shells - Tuning.StartShells) < 1 and math.abs(prof.wood - Tuning.StartWood) < 1, "join", "the starting shells and wood", string.format("%s %s", tostring(prof.shells), tostring(prof.wood)))
local start = table.clone(s.tide.list)
H.expect(#start == Tuning.TideStart, "join", "TideStart already bobbing at the jetty", tostring(#start))
local knacks = {}
local sum = 0
for _, d in start do
	local def = Creatures.byId[d.sp]
	H.expect(def ~= nil and def.rarity == 1, "join", "a new island's first ones are commons", tostring(d.sp))
	if def then
		knacks[def.knack] = (knacks[def.knack] or 0) + 1
	end
	H.expect(d.cost == Tide.cost(prof, d.sp, d.muts), "join", "its cost is Tide.cost", string.format("%s %d", d.sp, d.cost))
	H.expect(prof.seen[d.sp] == 1, "join", "seen at the jetty: in the Index (1)", string.format("%s %s", d.sp, tostring(prof.seen[d.sp])))
	sum += d.cost
end
H.expect(knacks.wood == 1 and knacks.farm == 1, "join", "one good with wood, one at a farm (the tips' first buildings)", string.format("wood %s farm %s", tostring(knacks.wood), tostring(knacks.farm)))
H.expect(sum <= Tuning.StartShells, "join", "the starting shells cover both", string.format("%d of %d", sum, Tuning.StartShells))
local v = H.view(p)
H.expect(v ~= nil and idsOf(v.tide) == idsOf(start), "join", "the view carries the tide", v and idsOf(v.tide))
for _, d in (v and v.tide or {}) do
	local sd = inTide(d.id)
	H.expect(sd ~= nil and d.sp == sd.sp and d.cost == sd.cost, "join", "the view's drift matches the server's", tostring(d.id))
end
H.expect(v ~= nil and v.tideSecs == Tide.secs(prof) and Tide.secs(prof) == Tuning.TideSecs, "join", "one every TideSecs (no huts to speed it up)", v and tostring(v.tideSecs))
local m1 = plotModel(s.plot)
H.expect(m1 ~= nil and m1:GetAttribute("Tide") == attrWant(s), "join", "the plot's Tide attribute lists them", m1 and tostring(m1:GetAttribute("Tide")))
-- the HUD's card: Open and each one's name and price, the oldest first
local card = gui(p, "TideCard")
H.expect(card ~= nil and H.guiVisible(card), "join", "the tide's card on the HUD")
H.expect(H.buttonNamed(p, "TideOpen") ~= nil, "join", "the card's Open")
for _, d in start do
	local b = H.buttonNamed(p, "CardTake_" .. d.id)
	H.expect(b ~= nil and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) ~= nil, "join", "the card's price button for each", string.format("%d: %s", d.id, buttonText(b)))
	local nm = card and card:FindFirstChild("TideName_" .. d.id, true)
	H.expect(nm ~= nil and nm.Text == Creatures.byId[d.sp].name, "join", "the card names each", nm and nm.Text or "none")
end
-- the world: each on its raft by the jetty, a price tag over it
H.expect(drawn(p, s.plot) == Tuning.TideStart, "join", "the rafts by the jetty (TideView)", tostring(drawn(p, s.plot)))
for _, d in start do
	local tag = gui(p, "TideTake_" .. d.id)
	H.expect(tag ~= nil and tag:IsA("TextButton") and string.find(buttonText(tag), Numbers.coins(d.cost), 1, true) ~= nil, "join", "a price tag over each in the world", string.format("%d: %s", d.id, buttonText(tag)))
end
checks("join")

------------------------------------------------------------------ 2. refusals before a hut
E.phase = "refuse"
hold()
local first = start[1]
local sh0 = prof.shells
H.expect(rawErr(p, "tide.take", { id = first.id, swap = 0 }) == "no_hut", "refuse", "no hut yet: no_hut")
H.expect(rawErr(p, "tide.take", { id = 99999, swap = 0 }) == "not_found", "refuse", "one that never came: not_found")
H.expect(rawErr(p, "tide.take", { id = 0, swap = 0 }) == "not_found", "refuse", "id 0: not_found")
local bad = {
	{ "a string id", { id = tostring(first.id), swap = 0 } },
	{ "no swap", { id = first.id } },
	{ "no id", { swap = 0 } },
	{ "an extra field", { id = first.id, swap = 0, uid = 1 } },
	{ "a negative id", { id = -1, swap = 0 } },
	{ "a fraction", { id = 1.5, swap = 0 } },
	{ "a huge id", { id = 2e6, swap = 0 } },
	{ "a string swap", { id = first.id, swap = "x" } },
	{ "a boolean id", { id = true, swap = 0 } },
	{ "a table id", { id = {}, swap = 0 } },
	{ "a list", { first.id, 0 } },
	{ "a string payload", "take" },
	{ "a number payload", 42 },
}
for _, b in bad do
	local err = rawErr(p, "tide.take", b[2])
	H.expect(err == "bad_payload", "refuse", "a malformed payload (" .. b[1] .. "): bad_payload", err)
end
H.expect(rawErr(p, "tide.take", nil) == "bad_payload", "refuse", "no payload: bad_payload")
H.expect(#s.tide.list == Tuning.TideStart and #prof.pals == 0 and prof.stats.taken == 0 and math.abs(prof.shells - sh0) < 1, "refuse", "nothing changed", string.format("%d drifts, %d pals", #s.tide.list, #prof.pals))
checks("refuse")

------------------------------------------------------------------ 3. the tips' buildings, then not enough shells
E.phase = "build"
hold()
local res = place("lumber")
H.expect(res.ok and prof.tut == 2, "build", "a lumber camp: the tips move on to the farm", string.format("%s tut %d", tostring(res.err), prof.tut))
local lumberUid = res.data and res.data.uid
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: on to the hut", string.format("%s tut %d", tostring(res.err), prof.tut))
local patchUid = res.data and res.data.uid
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: on to taking one in off the tide", string.format("%s tut %d", tostring(res.err), prof.tut))
local hutUid = res.data and res.data.uid
H.push(p, 0.3)
v = H.view(p)
H.expect(v.nests == Buildings.byId.nest.slots and Tide.room(prof) == Buildings.byId.nest.slots, "build", "the hut's room", tostring(v.nests))
H.expect(#s.tide.list == Tuning.TideStart, "build", "the starting ones still there", tostring(#s.tide.list))
-- not enough shells (a hut now, so the money check comes next)
hold()
local cheap = start[1]
for _, d in start do
	if d.cost < cheap.cost then
		cheap = d
	end
end
local keepShells = prof.shells
prof.shells = cheap.cost - 1
H.push(p, 0.3)
H.expect(rawErr(p, "tide.take", { id = cheap.id, swap = 0 }) == "money", "build", "a shell short: money")
local cb = H.buttonNamed(p, "CardTake_" .. cheap.id)
H.expect(cb ~= nil, "build", "the card still offers it (greyed: the shells aren't there)")
H.expect(#prof.pals == 0 and inTide(cheap.id) ~= nil, "build", "nothing taken")
prof.shells = keepShells
checks("build")

------------------------------------------------------------------ 4. taking one in: the HUD's card, then a world tag
E.phase = "take"
hold()
H.push(p, 0.3)
local woody, farmy = nil, nil
for _, d in start do
	local k = Creatures.byId[d.sp].knack
	if k == "wood" then
		woody = d
	elseif k == "farm" then
		farmy = d
	end
end
-- (the wood one from the card)
local ids0 = palIds()
local i0, t0 = #fx, E.now()
sh0 = prof.shells
H.expect(H.clickNamed(p, "CardTake_" .. woody.id, { wait = 0.6 }), "take", "the card's price button")
local x1 = newPal(ids0)
H.expect(x1 ~= nil and x1.sp == woody.sp, "take", "taken in", x1 and x1.sp or "none")
H.expect(x1 ~= nil and x1.home == hutUid, "take", "into the hut", x1 and tostring(x1.home))
H.expect(x1 ~= nil and x1.work == lumberUid, "take", "at work at the lumber camp (its knack)", x1 and tostring(x1.work))
H.expect(math.abs((sh0 - prof.shells) - woody.cost) <= earnSlack(E.now() - t0), "take", "its cost paid in shells", string.format("%.1f -> %.1f, cost %d", sh0, prof.shells, woody.cost))
H.expect(prof.stats.taken == 1 and prof.tut == 5 and prof.seen[woody.sp] == 2, "take", "stats.taken, the tips on to the shop, the Index has it (2)", string.format("taken %d tut %d seen %s", prof.stats.taken, prof.tut, tostring(prof.seen[woody.sp])))
local tk = fxSince(i0, "taken")
H.expect(#tk == 1 and type(tk[1].data) == "table" and tk[1].data.id == (x1 and x1.id) and tk[1].data.cost == woody.cost and tk[1].data.sold == 0, "take", "Fx taken: its id and cost, nothing sold", tostring(#tk))
H.expect(inTide(woody.id) == nil and viewTide(woody.id) == nil, "take", "gone from the tide (server and view)")
local noticed = false
for _, d in p.PlayerGui:GetDescendants() do
	if d:IsA("TextLabel") and string.find(d.Text, "moved into a hut", 1, true) then
		noticed = true
	end
end
H.expect(noticed, "take", "the HUD says it moved in")
E.run(1.2)
H.expect(H.buttonNamed(p, "CardTake_" .. woody.id) == nil and gui(p, "TideTake_" .. woody.id) == nil, "take", "its price buttons gone (card and world)")
H.expect(drawn(p, s.plot) == #s.tide.list, "take", "it hopped off its raft", string.format("%d drawn, %d bobbing", drawn(p, s.plot), #s.tide.list))
H.expect(H.inClient(p, WV.ownCount) == 1, "take", "and walks the island from its hut", tostring(H.inClient(p, WV.ownCount)))
H.expect(m1:GetAttribute("Tide") == attrWant(s), "take", "the attribute follows", tostring(m1:GetAttribute("Tide")))
-- (the farm one from its price tag over the water)
hold()
if prof.shells < farmy.cost then
	H.log("topping up %d shells for the second", farmy.cost - prof.shells)
	prof.shells = farmy.cost + 1
	H.push(p, 0.3)
end
ids0 = palIds()
i0, t0 = #fx, E.now()
sh0 = prof.shells
local found, vis = tap(p, "TideTake_" .. farmy.id)
H.expect(found, "take", "the world tag is there")
H.expect(vis, "take", "and on screen over the jetty")
local x2 = newPal(ids0)
H.expect(x2 ~= nil and x2.sp == farmy.sp and x2.home == hutUid and x2.work == patchUid, "take", "the farm one: into the hut, at work at the patch", x2 and string.format("%s home %d work %d", x2.sp, x2.home, x2.work) or "none")
H.expect(math.abs((sh0 - prof.shells) - farmy.cost) <= earnSlack(E.now() - t0), "take", "its cost paid", string.format("%.1f -> %.1f, cost %d", sh0, prof.shells, farmy.cost))
H.expect(prof.stats.taken == 2 and prof.tut == 5 and Tide.room(prof) == 0, "take", "two taken, the tips still on the shop, the hut full", string.format("taken %d tut %d room %d", prof.stats.taken, prof.tut, Tide.room(prof)))
H.expect(#s.tide.list == 0, "take", "the jetty empty", tostring(#s.tide.list))
E.run(0.5)
H.expect(#named(p, "CardTake_") == 0 and #named(p, "TideTake_") == 0, "take", "no price buttons left")
checks("take")

------------------------------------------------------------------ 5. arrivals: one every TideSecs, never more than TideMax, the oldest drifting off
E.phase = "arrive"
local most = 0
local function track()
	most = math.max(most, #s.tide.list)
end
hold()
i0, t0 = #fx, E.now()
E.runUntil(function()
	track()
	return #s.tide.list >= 1
end, Tuning.TideSecs + 2, 0.1)
local took = E.now() - t0
E.run(0.2) -- (the news reaches the client)
H.expect(#s.tide.list == 1 and math.abs(took - Tide.secs(prof)) <= 0.5, "arrive", "one drifts in after TideSecs", string.format("%d after %.1f s (secs %.1f)", #s.tide.list, took, Tide.secs(prof)))
local tf = fxSince(i0, "tide")
local came1 = tf[1] and type(tf[1].came) == "table" and tf[1].came[1]
local d1 = s.tide.list[1]
H.expect(#tf == 1 and #tf[1].came == 1 and came1 and d1 and came1.id == d1.id and #tf[1].gone == 0, "arrive", "Fx tide: it came, none gone", tostring(#tf))
H.expect(came1 and d1 and came1.cost == Tide.cost(prof, d1.sp, d1.muts), "arrive", "with its cost")
local fa = H.inClient(p, SC.tideFrac)
E.run(1)
local fb = H.inClient(p, SC.tideFrac)
H.expect(fb > fa and fb < 1, "arrive", "the client's bar fills toward the next", string.format("%.2f -> %.2f", fa, fb))
E.runUntil(function()
	track()
	return #s.tide.list >= Tuning.TideMax
end, Tide.secs(prof) * (Tuning.TideMax - 1) + 3, 0.1)
E.run(0.2)
tf = fxSince(i0, "tide")
local goneN = 0
for _, m in tf do
	goneN += #m.gone
end
H.expect(#s.tide.list == Tuning.TideMax and #tf == Tuning.TideMax and goneN == 0, "arrive", "up to TideMax, none leaving yet", string.format("%d bobbing, %d Fx, %d gone", #s.tide.list, #tf, goneN))
local oldest, second = s.tide.list[1].id, s.tide.list[2].id
local i1 = #fx
E.runUntil(function()
	track()
	return s.tide.list[1].id ~= oldest
end, Tide.secs(prof) + 2, 0.1)
E.run(0.2)
tf = fxSince(i1, "tide")
local newest = s.tide.list[#s.tide.list]
H.expect(#s.tide.list == Tuning.TideMax and s.tide.list[1].id == second, "arrive", "another comes: still TideMax, the oldest gone", idsOf(s.tide.list))
H.expect(#tf == 1 and #tf[1].gone == 1 and tf[1].gone[1] == oldest and #tf[1].came == 1 and tf[1].came[1].id == newest.id, "arrive", "Fx tide: came the new one, gone the oldest", tf[1] and string.format("came %d gone %s", #tf[1].came, tostring(tf[1].gone[1])) or "none")
-- (the client: the leaving one floats off, still drawn while it goes; its tags go at once)
E.run(1)
H.expect(drawn(p, s.plot) == Tuning.TideMax + 1, "arrive", "the oldest floats off along the channel (still drawn)", tostring(drawn(p, s.plot)))
H.expect(gui(p, "TideTake_" .. oldest) == nil and H.buttonNamed(p, "CardTake_" .. oldest) == nil, "arrive", "its price buttons gone at once")
H.expect(H.buttonNamed(p, "CardTake_" .. newest.id) ~= nil and gui(p, "TideTake_" .. newest.id) ~= nil, "arrive", "the new one's on the card and over its raft")
H.expect(m1:GetAttribute("Tide") == attrWant(s), "arrive", "the attribute follows", tostring(m1:GetAttribute("Tide")))
v = H.view(p)
H.expect(idsOf(v.tide) == idsOf(s.tide.list), "arrive", "the view follows", idsOf(v.tide))
E.run(3)
H.expect(drawn(p, s.plot) == Tuning.TideMax, "arrive", "and is gone once it has floated away", tostring(drawn(p, s.plot)))
H.expect(most <= Tuning.TideMax, "arrive", "never more than TideMax at the jetty", tostring(most))
-- the Index: every kind that drifted in is seen; one never taken in is seen (1), not had
local kinds = {}
for _, m in fxSince(i0, "tide") do
	for _, d in m.came do
		kinds[d.sp] = true
	end
end
local had = {}
for _, x in prof.pals do
	had[x.sp] = true
end
local seenOnly = 0
for sp in kinds do
	H.expect((prof.seen[sp] or 0) >= 1, "arrive", "a kind that drifted in is in the Index", sp)
	if not had[sp] then
		H.expect(prof.seen[sp] == 1, "arrive", "seen but never taken in: 1", string.format("%s %s", sp, tostring(prof.seen[sp])))
		seenOnly += 1
	end
end
H.log("arrive: %d kinds drifted in, %d seen but not had", (function()
	local n = 0
	for _ in kinds do
		n += 1
	end
	return n
end)(), seenOnly)
hold()
H.openPanel(p, "index")
for sp in kinds do
	local entry = gui(p, "Entry_" .. sp)
	local nm = entry and entry:FindFirstChild("Name")
	H.expect(nm ~= nil and nm.Text == Creatures.byId[sp].name, "arrive", "the Index panel shows it by name", string.format("%s: %s", sp, nm and nm.Text or "none"))
end
H.closePanel(p)
-- a drift that left
H.expect(rawErr(p, "tide.take", { id = oldest, swap = 0 }) == "not_found", "arrive", "taking one that drifted off: not_found")
checks("arrive")

------------------------------------------------------------------ 6. every hut full: the swap picker
E.phase = "full"
hold()
prof.shells = 50000
H.push(p, 0.4)
local target = aDrift()
local n0, taken0, sold0 = #prof.pals, prof.stats.taken, prof.stats.sold
H.expect(Tide.room(prof) == 0, "full", "every hut full", tostring(Tide.room(prof)))
H.expect(H.clickNamed(p, "CardTake_" .. target.id, { wait = 0.6 }), "full", "the card's price button")
H.expect(prof.stats.taken == taken0 and #prof.pals == n0 and inTide(target.id) ~= nil, "full", "refused (full): nothing taken, still bobbing")
H.expect(H.currentPanel(p) == "tide", "full", "the tide panel opens", tostring(H.currentPanel(p)))
local hutPals = {}
for _, x in prof.pals do
	if x.home ~= 0 then
		table.insert(hutPals, x)
	end
end
table.sort(hutPals, function(a, b)
	return Tide.better(b, a)
end)
for _, x in hutPals do
	local row = gui(p, "SwapOut_" .. x.id)
	H.expect(row ~= nil and H.guiVisible(row) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil, "full", "the swap picker: a row and Swap for each in a hut", tostring(x.id))
end
H.expect(not H.guiVisible(gui(p, "TideCard")), "full", "the HUD's card steps aside for the panel")
local out = hutPals[1]
local price, outHome = Tide.price(out), out.home
ids0 = palIds()
i0, t0 = #fx, E.now()
sh0 = prof.shells
H.expect(H.clickNamed(p, "SwapTake_" .. out.id, { wait = 0.6 }), "full", "Swap on the weakest")
local y = newPal(ids0)
H.expect(palOf(out.id) == nil, "full", "the swapped one is gone")
H.expect(y ~= nil and y.sp == target.sp and y.home == outHome, "full", "the new one in its place", y and string.format("%s home %d", y.sp, y.home) or "none")
H.expect(y ~= nil and workingOrNoPlace(y), "full", "at work, or no free place of its knack", y and tostring(y.work))
H.expect(#prof.pals == n0 and prof.stats.taken == taken0 + 1 and prof.stats.sold == sold0 + 1, "full", "one in, one sold", string.format("%d pals, taken %d sold %d", #prof.pals, prof.stats.taken, prof.stats.sold))
tk = fxSince(i0, "taken")
H.expect(#tk == 1 and tk[1].data.sold == price and tk[1].data.cost == target.cost and tk[1].data.swapped == out.id, "full", "Fx taken: sold for Tide.price, its cost", tk[1] and string.format("sold %s cost %s", tostring(tk[1].data.sold), tostring(tk[1].data.cost)) or "none")
H.expect(math.abs((prof.shells - sh0) - (price - target.cost)) <= earnSlack(E.now() - t0), "full", "shells: the price back, the cost paid", string.format("%.1f -> %.1f (price %d, cost %d)", sh0, prof.shells, price, target.cost))
H.expect(inTide(target.id) == nil, "full", "it left the jetty")
H.expect(H.currentPanel(p) == "tide" and #named(p, "SwapOut_", true) == 0, "full", "the panel back on the tide")
H.closePanel(p)
-- swaps the server refuses
local d2 = aDrift()
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = 0 }) == "full", "full", "every hut full and no swap: full")
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = 99999 }) == "bad_payload", "full", "a swap that isn't a driftling: bad_payload")
H.expect(rawErr(p, "tide.take", { id = d2.id, swap = hutUid }) == "bad_payload", "full", "a swap that is a hut: bad_payload")
H.expect(#prof.pals == n0 and inTide(d2.id) ~= nil, "full", "nothing changed")
checks("full")

------------------------------------------------------------------ 7. the tide panel
E.phase = "panel"
hold()
H.push(p, 0.3)
H.expect(H.clickNamed(p, "TideOpen", { wait = 0.4 }) and H.currentPanel(p) == "tide", "panel", "the card's Open opens the tide panel")
v = H.view(p)
for _, d in v.tide do
	local row = gui(p, "Drift_" .. d.id)
	local b = H.buttonNamed(p, "PanelTake_" .. d.id)
	H.expect(row ~= nil and H.guiVisible(row), "panel", "a row for each at the jetty", tostring(d.id))
	H.expect(b ~= nil and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) ~= nil, "panel", "its price on Take", string.format("%d: %s", d.id, buttonText(b)))
end
H.expect(#named(p, "Drift_", true) == #v.tide, "panel", "no other rows", tostring(#named(p, "Drift_", true)))
for r = 1, 5 do
	H.expect(gui(p, "Odds_" .. r) ~= nil, "panel", "the odds of rarity " .. r)
end
H.expect(labelText(p, "Pace") == string.format("One drifts in every %.0fs", Tide.secs(prof)), "panel", "how often", tostring(labelText(p, "Pace")))
H.expect(labelText(p, "Room") == string.format("In huts %d/%d", #prof.pals, Island.nests(prof)), "panel", "the huts' room", tostring(labelText(p, "Room")))
H.expect((gui(p, "Leaving") ~= nil) == (#v.tide >= Tuning.TideMax), "panel", "Leaving soon on the oldest only at TideMax", string.format("%d bobbing", #v.tide))
-- Take with every hut full: the swap picker, and Back
local d3 = aDrift()
H.expect(H.clickNamed(p, "PanelTake_" .. d3.id, { wait = 0.6 }) and #named(p, "SwapOut_", true) == #prof.pals, "panel", "Take with every hut full: the swap picker", tostring(#named(p, "SwapOut_", true)))
H.expect(H.clickNamed(p, "Back", { wait = 0.4 }) and #named(p, "SwapOut_", true) == 0 and #named(p, "Drift_", true) == #s.tide.list, "panel", "Back to the tide")
H.closePanel(p)
H.expect(H.guiVisible(gui(p, "TideCard")), "panel", "the HUD's card back once it closes")
checks("panel")

------------------------------------------------------------------ 8. selling from the Driftlings panel; a hut cleared away
E.phase = "sell"
hold()
H.push(p, 0.3)
H.openPanel(p, "pals")
local sellOne = nil
for _, x in prof.pals do
	if x.home ~= 0 and (sellOne == nil or Tide.better(sellOne, x)) then
		sellOne = x
	end
end
price = Tide.price(sellOne)
sold0 = prof.stats.sold
H.expect(H.clickNamed(p, "Sell_" .. sellOne.id, { wait = 0.3 }), "sell", "Sell on the weakest")
H.expect(palOf(sellOne.id) ~= nil and string.find(buttonText(H.buttonNamed(p, "Sell_" .. sellOne.id)), "Sure?", 1, true) ~= nil, "sell", "one tap asks: Sure?", buttonText(H.buttonNamed(p, "Sell_" .. sellOne.id)))
sh0, t0 = prof.shells, E.now()
H.expect(H.clickNamed(p, "Sell_" .. sellOne.id, { wait = 0.6 }), "sell", "the second tap")
H.expect(palOf(sellOne.id) == nil and prof.stats.sold == sold0 + 1, "sell", "sold", string.format("sold %d", prof.stats.sold))
H.expect(math.abs((prof.shells - sh0) - price) <= earnSlack(E.now() - t0), "sell", "for Tide.price", string.format("%.1f -> %.1f (price %d)", sh0, prof.shells, price))
H.expect(Tide.room(prof) == 1, "sell", "a place in the hut free", tostring(Tide.room(prof)))
H.closePanel(p)
-- the free place filled from the tide panel (no swap)
hold()
H.openPanel(p, "tide")
local d4 = aDrift()
ids0 = palIds()
sold0 = prof.stats.sold
H.expect(H.clickNamed(p, "PanelTake_" .. d4.id, { wait = 0.6 }), "sell", "Take on the tide panel")
local z1 = newPal(ids0)
H.expect(z1 ~= nil and z1.sp == d4.sp and z1.home == hutUid and prof.stats.sold == sold0 and Tide.room(prof) == 0, "sell", "into the free place, nothing sold", z1 and string.format("%s home %d", z1.sp, z1.home) or "none")
H.expect(H.currentPanel(p) == "tide" and gui(p, "Drift_" .. d4.id) == nil, "sell", "the panel stays open without it")
H.closePanel(p)
checks("sell")

E.phase = "clear"
hold()
local homed = {}
for _, x in prof.pals do
	table.insert(homed, x)
end
res = H.req(p, "plot.store", { i = hutIndex(hutUid) })
E.run(0.2)
local noHut = 0
for _, x in prof.pals do
	if x.home == 0 and x.work == 0 then
		noHut += 1
	end
end
H.expect(res.ok and #Tide.huts(prof) == 0 and noHut == #prof.pals and #prof.pals == #homed, "clear", "the hut cleared away: its driftlings kept, with no hut and not working", string.format("%s, %d of %d", tostring(res.err), noHut, #prof.pals))
E.run(1)
H.expect(m1:GetAttribute("Pals") == "" and H.inClient(p, WV.ownCount) == 0, "clear", "none drawn on the island while they have no hut", string.format("%s, %d drawn", tostring(m1:GetAttribute("Pals")), H.inClient(p, WV.ownCount)))
H.openPanel(p, "pals")
for _, x in prof.pals do
	local row = gui(p, "Pal_" .. x.id)
	local where = row and row:FindFirstChild("Where")
	H.expect(where ~= nil and string.sub(where.Text, 1, 6) == "No hut", "clear", "the Driftlings panel says it has no hut", where and where.Text or "none")
end
H.closePanel(p)
H.expect(rawErr(p, "tide.take", { id = aDrift().id, swap = 0 }) == "no_hut", "clear", "no hut to take one into: no_hut")
checks("clear")
hold()
res = place("nest")
local hut2 = res.data and res.data.uid
for _, x in prof.pals do
	H.expect(x.home == hut2, "clear", "another hut: they move in (Tide.settle)", string.format("%d home %d", x.id, x.home))
	H.expect(workingOrNoPlace(x), "clear", "and go back to work", string.format("%s work %d", x.sp, x.work))
end
H.expect(res.ok and Tide.room(prof) == Buildings.byId.nest.slots - #prof.pals, "clear", "the new hut's room", tostring(Tide.room(prof)))
E.run(1)
H.expect(H.inClient(p, WV.ownCount) == #prof.pals, "clear", "drawn on the island again", tostring(H.inClient(p, WV.ownCount)))
hutUid = hut2
checks("rehoused")

------------------------------------------------------------------ 9. the island grows: every price up by TideTier
E.phase = "expand"
hold()
prof.wood = Tuning.TierCost[2] + 300
H.push(p, 0.4)
local before = {}
v = H.view(p)
for _, d in v.tide do
	before[d.id] = d.cost
end
hold()
res = H.req(p, "island.expand", {})
E.run(1.5)
H.expect(res.ok and prof.tier == 2, "expand", "the island grows", tostring(res.err))
local ratio = Tuning.TideTier[2] / Tuning.TideTier[1]
v = H.view(p)
H.expect(idsOf(v.tide) == idsOf(s.tide.list), "expand", "the same ones bobbing", idsOf(v.tide))
for _, d in v.tide do
	local was = before[d.id]
	local want = Tide.cost(prof, d.sp, d.muts)
	H.expect(was ~= nil and d.cost == want and math.abs(d.cost - was * ratio) <= ratio / 2 + 0.5, "expand", "its cost times TideTier", string.format("%s %s -> %d (want %d)", d.sp, tostring(was), d.cost, want))
	local b = H.buttonNamed(p, "CardTake_" .. d.id)
	H.expect(b ~= nil and string.find(buttonText(b), Numbers.coins(d.cost), 1, true) ~= nil, "expand", "the card shows the new price", buttonText(b))
	local tag = gui(p, "TideTake_" .. d.id)
	H.expect(tag ~= nil and string.find(buttonText(tag), Numbers.coins(d.cost), 1, true) ~= nil, "expand", "so does its tag over the water", buttonText(tag))
end
H.expect(m1:GetAttribute("Tier") == 2 and m1:GetAttribute("Tide") == attrWant(s) and drawn(p, s.plot) == #s.tide.list, "expand", "the bigger island keeps its tide (attribute and rafts)", string.format("%s, %d drawn", tostring(m1:GetAttribute("Tide")), drawn(p, s.plot)))
checks("expand")

------------------------------------------------------------------ 10. a second player sees the first island's tide
E.phase = "neighbour"
local q = H.addPlayer({ userId = 9602, name = "Neighbour" })
hold()
E.run(2.5)
hold()
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot ~= s.plot, "neighbour", "a second island", sq and tostring(sq.plot))
local mq = plotModel(sq.plot)
E.run(1)
H.expect(m1:GetAttribute("Tide") == attrWant(s), "neighbour", "the first island's tide in its plot attribute", tostring(m1:GetAttribute("Tide")))
H.expect(mq ~= nil and mq:GetAttribute("Tide") == attrWant(sq), "neighbour", "and the second's in its own", mq and tostring(mq:GetAttribute("Tide")))
H.expect(drawn(q, s.plot) == #s.tide.list, "neighbour", "the second player's client draws the first island's rafts", string.format("%d of %d", drawn(q, s.plot), #s.tide.list))
H.expect(drawn(q, sq.plot) == #sq.tide.list, "neighbour", "and its own", string.format("%d of %d", drawn(q, sq.plot), #sq.tide.list))
H.expect(drawn(p, sq.plot) == #sq.tide.list, "neighbour", "the first player's client draws the second's", string.format("%d of %d", drawn(p, sq.plot), #sq.tide.list))
H.expect(#named(q, "TideTake_") == #sq.tide.list and #named(p, "TideTake_") == #s.tide.list, "neighbour", "price tags only over the own island's", string.format("%d / %d", #named(q, "TideTake_"), #named(p, "TideTake_")))
-- one more drifts in on the first island: the neighbour sees it too
local was = attrWant(s)
E.runUntil(function()
	return attrWant(s) ~= was
end, Tide.secs(prof) + 2, 0.1)
H.expect(attrWant(s) ~= was and #s.tide.list <= Tuning.TideMax, "neighbour", "another drifts in", attrWant(s))
E.run(Tide.secs(prof) / 3)
H.expect(m1:GetAttribute("Tide") == attrWant(s) and drawn(q, s.plot) == #s.tide.list, "neighbour", "the neighbour's client follows it", string.format("%d of %d", drawn(q, s.plot), #s.tide.list))
H.checkProfile(q, "neighbour")
H.checkMirror(q, "neighbour")
checks("end")

report(E, H)
