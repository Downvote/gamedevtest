-- The main simulation: a new island end to end through the real client and its UI (the campfire, the jetty with the
-- tide's first two driftlings bobbing there, the HUD with its tide card, the tips), building what the tips ask in their
-- order (a lumber camp, a veggie patch, a hut, then a driftling taken off the tide from the HUD's card, then a snack
-- stall: the starting wood and shells cover them), the days turning (the stores grow, every building working a little
-- with nobody at it), the tide (one drifting in every TideSecs, never more than TideMax, the oldest drifting off; each
-- in the Index; the HUD's card and the world's price tags; the tide's panel taking one in, then the swap picker once
-- the hut is full; one taken in walking the island), the Driftlings panel (moving one to a second hut and back in a
-- swap, Work, selling in two taps), the Index panel, the founder's looks, settings, expanding for wood, the questline,
-- then a malicious client, then a second player. No villagers since 2026-11-12, no Tree of Life and no food since
-- 2026-11-13. Every check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
local E = require("./loader")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.verboseUi = false
E.dt = 0.05
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Buildings = H.sharedServer("Data.Buildings")
local Creatures = H.sharedServer("Data.Creatures")
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Island = H.sharedServer("Logic.Island")
local TideL = H.sharedServer("Logic.Tide")

------------------------------------------------------------------ 1. a new island
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(1.5)
local fx = H.watchFx(p)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(prof.shells == Tuning.StartShells and prof.wood == Tuning.StartWood and prof.food == nil, "join", "the starting stores (wood and shells, no food)", string.format("%s %s %s", tostring(prof.shells), tostring(prof.wood), tostring(prof.food)))
H.expect(prof.tier == 1 and prof.tut == 1 and prof.folk == nil and #prof.plot.placed == 0 and prof.tree == nil, "join", "a new island, tips at step 1, no villagers, nothing built (no Tree of Life)", string.format("%d pieces", #prof.plot.placed))
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local land1 = static and static:FindFirstChild("Land")
H.expect(land1 ~= nil and land1:FindFirstChild("Land") ~= nil and static:FindFirstChild("Office") == nil, "join", "the island is built under Plots.Plot_1.Static.Land (no house)")
H.expect(land1 ~= nil and land1:FindFirstChild("FireStone", true) ~= nil and land1:FindFirstChild("JettyPlank", true) ~= nil, "join", "its plaza's campfire and the jetty")
H.expect(plot1 and plot1:GetAttribute("StudioName") == "Pixel's Isle", "join", "the island's name", tostring(plot1 and plot1:GetAttribute("StudioName")))
local dyn = E.workspace:FindFirstChild("PixelDynamic")
H.expect(dyn ~= nil and dyn:FindFirstChild("Founder_9101") ~= nil, "join", "the founder's chibi is there")
for _, n in { "Menu_build", "Menu_pals", "Menu_index", "Menu_looks" } do
	H.expect(H.buttonNamed(p, n) ~= nil, "join", "the menu bar's " .. n)
end
H.expect(H.buttonNamed(p, "Menu_folk") == nil, "join", "no Villagers button (the driftlings do all the work)")
H.expect(#H.buttons(p, "^Wood pays", true) == 0, "join", "(tips are text, not buttons)")
-- the loading card (src/first/LoadingCard: ReplicatedFirst's Boot put it up before the rest arrived): it went up, its
-- title centred on the canvas, and it is gone once the first picture is on screen
do
	local ctx = E.clientCtx(p)
	local inst = E.find("ReplicatedFirst.Loading.LoadingCard")
	local entry = ctx and inst and ctx.modules[inst]
	local st = entry and H.inClient(p, entry.value.state)
	H.expect(st ~= nil and st.finished and not st.up, "join", "the loading card went up and is gone now the island shows", st and string.format("finished %s up %s", tostring(st.finished), tostring(st.up)))
	local mid = st and st.title and (st.title.x0 + st.title.x1) / 2
	H.expect(mid ~= nil and math.abs(mid - st.size.X / 2) <= 1, "join", "its title centred on the screen", if st and st.title then string.format("%s of %d", tostring(mid), st.size.X) else "no title")
	local pg = p:FindFirstChildOfClass("PlayerGui")
	H.expect(pg ~= nil and pg:FindFirstChild("LoadingCard") == nil, "join", "and nothing of it left on the screen")
end
-- the background music: the island's tunes by the clock; the note in the corner switches it off and on (kept)
local AudioM = H.cmod(p, "Controllers.Audio")
local ms = H.inClient(p, AudioM.musicState)
H.expect((ms.mood == "day" or ms.mood == "night") and ms.on and ms.tracks >= 1, "join", "the island's music plays", string.format("%s %s %d", tostring(ms.mood), tostring(ms.on), ms.tracks))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "off" and not H.inClient(p, AudioM.musicState).on, "join", "the note switches the music off, kept with the profile", tostring(prof.settings.music))
H.expect(H.clickNamed(p, "MusicToggle", { wait = 0.5 }) and prof.settings.music == "on" and H.inClient(p, AudioM.musicState).on, "join", "and on again", tostring(prof.settings.music))
-- the sounds (GAME_DESIGN 11): every event has a library sound, each of its takes too; the founder's feet are heard
-- (the game's own step sounds: Roblox's are switched off by the empty RbxCharacterSounds)
local Mon = H.sharedServer("Config.Monetization")
local noSound = {}
for name, ev in AudioM.EVENTS do
	local ok = H.inClient(p, AudioM.has, name)
	for _, k in ev.ids or {} do
		ok = ok and (Mon.Sounds[k] or 0) > 0
	end
	if not ok then
		table.insert(noSound, name)
	end
end
table.sort(noSound)
H.expect(#noSound == 0, "join", "every sound has a library sound behind it (each take too)", table.concat(noSound, ","))
local function stepSounds(): number
	return H.inClient(p, AudioM.playCount, "step_grass") + H.inClient(p, AudioM.playCount, "step_sand") + H.inClient(p, AudioM.playCount, "step_wood")
end
local steps0 = stepSounds()
local walkRoot = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
if walkRoot then
	local at = walkRoot.Position
	for k = 1, 16 do
		p.Character:PivotTo(E.cf.new(at.X + k * 0.6, at.Y, at.Z))
		E.run(0.05)
	end
	p.Character:PivotTo(E.cf.new(at.X, at.Y, at.Z))
	E.run(0.3)
end
H.expect(stepSounds() > steps0, "join", "the founder's footsteps are heard as they walk", string.format("%d -> %d", steps0, stepSounds()))
local tipsOk = H.buttonNamed(p, "TipsOk")
H.expect(tipsOk == nil, "join", "the first tips have no OK (they move on by building)")
-- a line of the HUD or a notice saying `pattern` (plain)
local function statusSays(pattern)
	for _, d in p.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, pattern, 1, true) then
			return true
		end
	end
	return false
end
-- the World canvas's price tag over one of the own tide's driftlings (Controllers/TideView), or nil
local UIKitP = H.cmod(p, "UI.UIKit")
local TideViewP = H.cmod(p, "Controllers.TideView")
local function worldTag(id)
	return H.inClient(p, function()
		return UIKitP.canvas("World"):FindFirstChild("TideTake_" .. id, true)
	end)
end
-- the tide (GAME_DESIGN 6): TideStart driftlings bob at the jetty already, a new island's two commons good at its first
-- buildings (one with wood, one at a farm), each one seen in the Index; the HUD's tide card lists them with their
-- prices, and TideView floats them on rafts by the jetty with a price tag over each
do
	local list = s.tide.list
	local commons, knacks, seen = true, {}, true
	for _, d in list do
		local c = Creatures.byId[d.sp]
		commons = commons and c ~= nil and c.rarity == 1
		if c then
			knacks[c.knack] = true
		end
		seen = seen and (prof.seen[d.sp] or 0) >= 1
	end
	H.expect(#list == Tuning.TideStart, "join", "TideStart driftlings bobbing at the jetty already", tostring(#list))
	H.expect(commons and knacks.wood and knacks.farm, "join", "a new island's first two: commons, one good with wood, one at a farm", table.concat((function()
		local out = {}
		for _, d in list do
			table.insert(out, d.sp)
		end
		return out
	end)(), ","))
	H.expect(seen, "join", "each one seen is in the Index")
	local v0 = H.view(p)
	H.expect(v0 ~= nil and #v0.tide == #list and v0.tideSecs == TideL.secs(prof) and v0.tree == nil and v0.penN == nil, "join", "the view carries the tide and its pace (no tree, no pen)", v0 and string.format("%d of %d, %s s", #v0.tide, #list, tostring(v0.tideSecs)))
	local card = p.PlayerGui:FindFirstChild("TideCard", true)
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TideOpen") ~= nil, "join", "the HUD's tide card with Open")
	local rows = 0
	for _, d in list do
		if H.buttonNamed(p, "CardTake_" .. d.id, true) ~= nil then
			rows += 1
		end
	end
	H.expect(rows == #list, "join", "the card lists each one with its price", string.format("%d of %d", rows, #list))
	E.runUntil(function()
		return H.inClient(p, TideViewP.count, s.plot) >= #list
	end, 2, 0.1)
	local tags = 0
	for _, d in list do
		if worldTag(d.id) ~= nil then
			tags += 1
		end
	end
	H.expect(H.inClient(p, TideViewP.count, s.plot) >= #list and tags == #list, "join", "each one floats by the jetty with a price tag over it", string.format("%d drawn, %d tags", H.inClient(p, TideViewP.count, s.plot), tags))
	-- no hut yet: a tap on a price is refused (no_hut) and says why
	local d1 = list[1]
	local sh = prof.shells
	H.clickNamed(p, "CardTake_" .. d1.id, { wait = 0.5 })
	H.expect(#prof.pals == 0 and prof.shells == sh and s.tide.list[1] == d1, "join", "no hut yet: taking one in is refused, nothing paid", string.format("%d driftlings, %s shells", #prof.pals, tostring(prof.shells)))
	H.expect(statusSays("Build a hut first"), "join", "and the notice says to build a hut first")
	local res = H.req(p, "tide.take", { id = d1.id, swap = 0 })
	H.expect(not res.ok and res.err == "no_hut", "join", "the server's word for it: no_hut", tostring(res.err))
end
H.checkProfile(p, "join")
H.checkMirror(p, "join")

------------------------------------------------------------------ 2. building
E.phase = "build"
-- a cell where a piece fits (from the south-east, the side the camera sees)
local function spot(id, rot)
	local pr = Street.plot(prof.tier)
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if Plot.fits(prof.tier, prof.plot.placed, id, x, z, rot) then
				return x, z
			end
		end
	end
	return nil, nil
end
local function place(id)
	local x, z = spot(id, 0)
	return H.req(p, "plot.place", { id = id, x = x or 0, z = z or 0, rot = 0 })
end
local function pieceOf(id)
	for _, q in prof.plot.placed do
		if q.id == id then
			return q
		end
	end
	return nil
end
-- the tips in Build mode: the tray opens on the tip's tab, its building pulsing, the tip's banner over the tray
local BuildUI = H.cmod(p, "UI.BuildUI")
local function tipShown()
	local pg = p:FindFirstChild("PlayerGui")
	for _, x in pg:GetDescendants() do
		if x.Name == "Tips" and H.guiVisible(x) then
			return true
		end
	end
	return false
end
H.expect(H.clickNamed(p, "Menu_build", { wait = 0.4 }) and BuildUI.isOpen(), "build", "Build mode opens")
local bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "wood" and bst.goal == "lumber", "build", "the first tip: the Wood tab, the lumber camp to build", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the tip's banner shows in Build mode")
H.clickNamed(p, "Tab_decor", { wait = 0.3 })
H.expect(H.inClient(p, BuildUI.debugState).tab == "decor", "build", "the player can still look round the other tabs")
local wood0, sh0 = prof.wood, prof.shells
local res = place("lumber")
E.run(0.5)
bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "farm" and bst.goal == "patch" and H.buttonNamed(p, "Buy_patch") ~= nil, "build", "the camp built: the tray turns to the Farms tab and the veggie patch", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the next tip's banner over the tray")
H.clickNamed(p, "BuildDone", { wait = 0.3 })
H.expect(not BuildUI.isOpen() and tipShown(), "build", "Done: the tray goes, the tip stays")
H.expect(res.ok and #prof.plot.placed == 1 and prof.plot.placed[1].id == "lumber", "build", "a lumber camp", tostring(res.err))
H.expect(math.abs(prof.wood - (wood0 - Buildings.byId.lumber.wood)) < 2 and math.abs(prof.shells - sh0) < 1, "build", "paid for in wood, no shells", string.format("wood %s -> %s, shells %s -> %s", wood0, prof.wood, sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to a farm (wood built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: the tips move on to a hut", tostring(res.err))
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: the tips move on to a driftling off the tide", string.format("%s tut %d", tostring(res.err), prof.tut))
-- step 4: one off the tide, its price tapped on the HUD's tide card (one good at a building the island has: the tips'
-- first two are), into the hut and off to work at a building of its knack
do
	local has = {}
	for _, q in prof.plot.placed do
		has[Buildings.byId[q.id].knack] = true
	end
	local pick = nil
	for _, d in s.tide.list do
		local c = Creatures.byId[d.sp]
		if c and has[c.knack] and (pick == nil or d.cost < pick.cost) then
			pick = d
		end
	end
	H.expect(pick ~= nil and prof.shells >= pick.cost, "build", "the starting shells cover one at the jetty that has work here", pick and string.format("%s shells, it costs %d", tostring(prof.shells), pick.cost) or "none with work here")
	if pick then
		H.push(p, 0.3)
		local sh1 = prof.shells
		local fTaken = #fx
		H.clickNamed(p, "CardTake_" .. pick.id, { wait = 0.6 })
		local first = prof.pals[1]
		H.expect(#prof.pals == 1 and prof.stats.taken == 1 and first.sp == pick.sp and math.abs(prof.shells - (sh1 - pick.cost)) < 2, "build", "a tap on its price on the tide's card takes it in for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		local gone = true
		for _, d in s.tide.list do
			gone = gone and d.id ~= pick.id
		end
		H.expect(gone, "build", "and it leaves the jetty")
		local takenFx = 0
		for i = fTaken + 1, #fx do
			if fx[i].kind == "taken" then
				takenFx += 1
			end
		end
		H.expect(takenFx == 1, "build", "the client hears of it (Fx taken)", tostring(takenFx))
		local hut = pieceOf("nest")
		H.expect(first ~= nil and hut ~= nil and first.home == hut.uid and first.work ~= 0, "build", "it moves into the hut and goes to work at a building of its knack", first and string.format("home %d work %d", first.home, first.work))
		H.expect(prof.tut == 5, "build", "the tips move on to a shop", tostring(prof.tut))
	end
end
res = place("stall")
H.expect(res.ok and prof.tut == 6, "build", "a snack stall: the tips move on to the last", string.format("%s tut %d", tostring(res.err), prof.tut))
local tipWood = Buildings.byId.lumber.wood + Buildings.byId.patch.wood + Buildings.byId.nest.wood + Buildings.byId.stall.wood
H.expect(#prof.plot.placed == 4 and tipWood <= Tuning.StartWood and prof.wood >= 0, "build", "the starting wood paid for every building the tips ask for", string.format("%d pieces, %d wood of %d, %.0f left", #prof.plot.placed, tipWood, Tuning.StartWood, prof.wood))
res = place("orchard")
H.expect(not res.ok and res.err == "locked", "build", "an orchard waits for a bigger island", tostring(res.err))
res = place("tent")
H.expect(not res.ok and res.err == "bad_payload", "build", "no homes to build any more (the Tent is gone)", tostring(res.err))
res = place("tree")
H.expect(not res.ok and res.err == "bad_payload", "build", "no Tree of Life to build (gone with the tide)", tostring(res.err))
do
	local w, sh = prof.wood, prof.shells
	prof.wood = 5
	res = place("nest")
	H.expect(not res.ok and res.err == "wood", "build", "not enough wood", tostring(res.err))
	prof.wood, prof.shells = 1000, 0
	res = place("flowers")
	H.expect(res.ok, "build", "no shells needed to build (wood pays)", tostring(res.err))
	if res.ok then
		res = H.req(p, "plot.store", { i = #prof.plot.placed })
		H.expect(res.ok, "build", "(the flowers cleared away again)", tostring(res.err))
	end
	prof.wood, prof.shells = w, sh
end
H.push(p, 0.4)
local v = H.view(p)
H.expect(v ~= nil and #v.pieces == 4 and v.nests == 2 and v.beds == nil and v.pen == nil and v.folk == nil and v.food == nil, "build", "the view: four pieces, a hut's room for two (no beds, no pen, no food)", v and string.format("%d %d", #v.pieces, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 4, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
H.checkProfile(p, "build")
H.checkMirror(p, "build")

------------------------------------------------------------------ 3. turns and days
E.phase = "days"
local day0 = prof.day
local turnFx = 0
local f0 = #fx
local t0 = E.now()
E.runUntil(function()
	for i = f0 + 1, #fx do
		if fx[i].kind == "turn" then
			return true
		end
	end
	return false
end, Tuning.TurnSeconds + 2, 0.1)
E.run(0.3)
for i = f0 + 1, #fx do
	if fx[i].kind == "turn" then
		turnFx += 1
	end
end
H.expect(turnFx == 1 and prof.day == day0, "days", "a turn ends every TurnSeconds (Fx turn), not a day", string.format("%d fx, day %d", turnFx, prof.day))
local ticks, tideTicks = 0, 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
		if H.finite(fx[i].tideT) and H.finite(fx[i].tideSecs) and fx[i].tideSecs > 0 and fx[i].grow == nil and fx[i].food == nil then
			tideTicks += 1
		end
	end
end
H.expect(ticks >= math.floor(E.now() - t0) - 3, "days", "the stores reach the client every second (Fx tick)", string.format("%d ticks in %.1f s", ticks, E.now() - t0))
H.expect(tideTicks == ticks, "days", "each tick carries the tide's clock (no tree, no food)", string.format("%d of %d", tideTicks, ticks))
-- a calendar day is hours of the sea's clock: jumped to a day's end, the island counts one (Fx day)
do
	local WC = H.smod("WorldClock")
	local d1 = prof.day
	local f1 = #fx
	WC.shift(Tuning.DaySeconds - (WC.now() % Tuning.DaySeconds) - 0.5)
	E.run(1.2)
	local days = 0
	for i = f1 + 1, #fx do
		if fx[i].kind == "day" then
			days += 1
		end
	end
	H.expect(prof.day == d1 + 1 and days == 1, "days", "the sea's clock passing a day's end counts a day (Fx day)", string.format("day %d -> %d, %d fx", d1, prof.day, days))
	local v1 = H.view(p)
	H.expect(v1 ~= nil and v1.dayFrac < 0.01, "days", "the view's clock at the new day's dawn", tostring(v1 and v1.dayFrac))
end
E.run(0.6)
local WV = H.cmod(p, "Controllers.WorldView")
local function housedN(): number
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
H.expect(housedN() == 1 and H.inClient(p, WV.ownCount) == housedN(), "days", "the hut's driftling walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
local r = Island.rates(prof)
H.expect(r.shells > 0 and r.wood > 0 and r.food == nil, "days", "wood and shells come in (a building works a little with nobody at it)", string.format("%.1f %.1f", r.wood, r.shells))
H.checkProfile(p, "days")
H.checkMirror(p, "days")

------------------------------------------------------------------ 4. the tide (GAME_DESIGN 6)
E.phase = "tide"
-- (wait for a quiet moment: at least `need` seconds before the next one drifts in, so two taps or a panel are not cut
-- across by the view changing)
local function calm(need)
	E.runUntil(function()
		return TideL.secs(prof) - s.tide.t >= (need or 2)
	end, TideL.secs(prof) + 1, 0.05)
end
-- the cheapest one at the jetty (that `ok` likes)
local function cheapest(ok)
	local best = nil
	for _, d in s.tide.list do
		if (ok == nil or ok(d)) and (best == nil or d.cost < best.cost) then
			best = d
		end
	end
	return best
end
-- a fishing pier, so every kind of the first island's driftlings has a building of its knack to work at
prof.wood = math.max(prof.wood, 400)
res = place("pier")
H.expect(res.ok, "tide", "a fishing pier", tostring(res.err))
-- one drifts in every Tide.secs (Fx tide); the jetty holds TideMax and the oldest drifts off as the next comes
do
	local secs = TideL.secs(prof)
	local arrivals = {}
	local most = #s.tide.list
	local fT = #fx
	local function came()
		local n = 0
		for i = fT + 1, #fx do
			if fx[i].kind == "tide" and type(fx[i].came) == "table" then
				n += #fx[i].came
			end
		end
		return n
	end
	for k = 1, 3 do
		E.runUntil(function()
			most = math.max(most, #s.tide.list)
			return came() >= k
		end, secs + 2, 0.05)
		table.insert(arrivals, E.now())
	end
	local even = #arrivals == 3
	for k = 2, #arrivals do
		even = even and math.abs(arrivals[k] - arrivals[k - 1] - secs) <= 0.3
	end
	H.expect(came() == 3 and even, "tide", "one drifts in every Tide.secs (Fx tide)", string.format("%d came, %s apart (every %.1f s)", came(), if #arrivals >= 2 then string.format("%.2f s", arrivals[#arrivals] - arrivals[#arrivals - 1]) else "?", secs))
	local goneIds = {}
	for i = fT + 1, #fx do
		if fx[i].kind == "tide" and type(fx[i].gone) == "table" then
			for _, id in fx[i].gone do
				table.insert(goneIds, id)
			end
		end
	end
	local stillThere = false
	for _, id in goneIds do
		for _, d in s.tide.list do
			stillThere = stillThere or d.id == id
		end
	end
	H.expect(most <= Tuning.TideMax and #s.tide.list == Tuning.TideMax and #goneIds >= 1 and not stillThere, "tide", "TideMax at the jetty at most: the oldest drifts off as the next comes (Fx tide gone)", string.format("%d at most, %d now, %d gone", most, #s.tide.list, #goneIds))
	local seen = true
	for _, d in s.tide.list do
		seen = seen and (prof.seen[d.sp] or 0) >= 1
	end
	H.expect(seen, "tide", "each one that drifts in is seen in the Index")
	local k, every = H.inClient(p, H.cmod(p, "Controllers.StateClient").tideFrac)
	H.expect(k >= 0 and k <= 1 and math.abs(every - secs) < 1e-6, "tide", "the client runs the tide's clock on (StateClient.tideFrac)", string.format("%.2f of %.1f s", k, every))
end
-- the HUD's tide card and the world's price tags: one each for every one at the jetty
calm(2)
H.push(p, 0.6)
do
	local rows, tags = 0, 0
	for _, d in s.tide.list do
		if H.buttonNamed(p, "CardTake_" .. d.id, true) ~= nil then
			rows += 1
		end
		if worldTag(d.id) ~= nil then
			tags += 1
		end
	end
	H.expect(rows == #s.tide.list, "tide", "the tide's card lists every one at the jetty", string.format("%d of %d", rows, #s.tide.list))
	H.expect(tags == #s.tide.list and H.inClient(p, TideViewP.count, s.plot) >= #s.tide.list, "tide", "every one floats by the jetty with its price tag", string.format("%d tags, %d drawn of %d", tags, H.inClient(p, TideViewP.count, s.plot), #s.tide.list))
end
-- the tide's panel from the card's Open: how often, the odds, the ones at the jetty with Take
prof.shells = math.max(prof.shells, 2000)
H.push(p, 0.4)
calm(3)
H.clickNamed(p, "TideOpen", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tide", "tide", "Open on the tide's card opens the tide's panel", tostring(H.currentPanel(p)))
do
	local pg = p.PlayerGui
	local rows = 0
	for _, d in s.tide.list do
		if pg:FindFirstChild("Drift_" .. d.id, true) and H.buttonNamed(p, "PanelTake_" .. d.id) ~= nil then
			rows += 1
		end
	end
	H.expect(rows == #s.tide.list, "tide", "the panel lists every one at the jetty with Take", string.format("%d of %d", rows, #s.tide.list))
	H.expect(pg:FindFirstChild("Pace", true) ~= nil and pg:FindFirstChild("Odds_1", true) ~= nil and pg:FindFirstChild("Room", true) ~= nil, "tide", "its pace, the huts' room and the odds")
	local card = pg:FindFirstChild("TideCard", true)
	H.expect(card == nil or not H.guiVisible(card), "tide", "the HUD's cards step aside for the wide panel")
end
-- Take: the hut has room for one more
do
	local d = cheapest()
	local sh1, n0 = prof.shells, #prof.pals
	H.clickNamed(p, "PanelTake_" .. d.id, { wait = 0.6 })
	local x = prof.pals[#prof.pals]
	H.expect(#prof.pals == n0 + 1 and prof.stats.taken == 2 and x.sp == d.sp and math.abs(prof.shells - (sh1 - d.cost)) < 2, "tide", "Take in the panel takes it in for its price", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, d.cost))
	H.expect(x.home == pieceOf("nest").uid, "tide", "into the hut with room", tostring(x.home))
	H.expect(H.currentPanel(p) == "tide", "tide", "the panel stays open", tostring(H.currentPanel(p)))
	-- the one taken in comes ashore and walks the island
	E.runUntil(function()
		return H.inClient(p, WV.ownCount) == housedN()
	end, 3, 0.25)
	H.expect(H.inClient(p, WV.ownCount) == housedN() and housedN() == 2, "tide", "the one taken in walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
end
-- every hut full: a tap on a world price tag opens the swap picker instead; Swap sells the one picked and the new one
-- takes its place
H.closePanel(p)
calm(4)
do
	local d = cheapest()
	local tag = worldTag(d.id)
	local n0, taken0 = #prof.pals, prof.stats.taken
	H.expect(tag ~= nil and H.guiVisible(tag), "tide", "its price tag shows over it by the jetty")
	H.clickNamed(p, "TideTake_" .. d.id, { wait = 0.6 })
	H.expect(#prof.pals == n0 and prof.stats.taken == taken0, "tide", "every hut full: nothing taken yet", string.format("%d driftlings", #prof.pals))
	H.expect(H.currentPanel(p) == "tide", "tide", "the tide's panel opens on the swap picker", tostring(H.currentPanel(p)))
	local pg = p.PlayerGui
	local rows = 0
	for _, x in prof.pals do
		if x.home ~= 0 and pg:FindFirstChild("SwapOut_" .. x.id, true) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil then
			rows += 1
		end
	end
	H.expect(rows == housedN(), "tide", "the picker lists every hut driftling with Swap", string.format("%d of %d", rows, housedN()))
	-- (the weakest, the picker's first)
	local weak = nil
	for _, x in prof.pals do
		if x.home ~= 0 and (weak == nil or TideL.better(weak, x)) then
			weak = x
		end
	end
	local price = TideL.price(weak)
	local sh1, sold0, hut = prof.shells, prof.stats.sold, weak.home
	H.clickNamed(p, "SwapTake_" .. weak.id, { wait = 0.6 })
	local x = prof.pals[#prof.pals]
	H.expect(table.find(prof.pals, weak) == nil and prof.stats.sold == sold0 + 1 and prof.stats.taken == taken0 + 1, "tide", "Swap: the one picked is sold", string.format("sold %d, taken %d", prof.stats.sold, prof.stats.taken))
	H.expect(x.sp == d.sp and x.home == hut and #prof.pals == n0 and math.abs(prof.shells - (sh1 - d.cost + price)) < 2, "tide", "and the new one takes its place in the hut, paid less what the other sold for", string.format("%+.1f shells (cost %d, sold for %d)", prof.shells - sh1, d.cost, price))
	H.closePanel(p)
end
-- not enough shells: refused, nothing changes
do
	local sh = prof.shells
	prof.shells = 0
	local d = cheapest()
	local n0 = #prof.pals
	res = H.req(p, "tide.take", { id = d.id, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "money" and #prof.pals == n0, "tide", "not enough shells", tostring(res.err))
	res = H.req(p, "tide.take", { id = 424242, swap = 0 })
	H.expect(not res.ok and res.err == "not_found", "tide", "one that has drifted off", tostring(res.err))
	prof.shells = sh
end
-- the Index: every kind seen on the tide counts
do
	local seen = 0
	for _, n in prof.seen do
		if n >= 1 then
			seen += 1
		end
	end
	H.push(p, 0.3)
	H.openPanel(p, "index")
	H.expect(statusSays(string.format("Seen %d of %d kinds", seen, #Creatures.list)), "tide", "the Index counts every kind seen on the tide", string.format("%d seen", seen))
	H.closePanel(p)
end
H.checkProfile(p, "tide")
H.checkMirror(p, "tide")

------------------------------------------------------------------ 5. the Driftlings panel: moving, working, selling
E.phase = "pals"
-- a second hut, so there is somewhere to move one to
prof.wood = math.max(prof.wood, 200)
res = place("nest")
local hutA = pieceOf("nest")
local hutB = prof.plot.placed[#prof.plot.placed]
H.expect(res.ok and hutB.id == "nest" and hutB ~= hutA, "pals", "a second hut", tostring(res.err))
H.push(p, 0.4)
calm(4)
local pal = nil
for _, x in prof.pals do
	if x.home == hutA.uid and x.work ~= 0 and pal == nil then
		pal = x
	end
end
H.clickNamed(p, "Menu_pals", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "pals", "the Driftlings panel opens")
H.expect(pal ~= nil and H.buttonNamed(p, "Move_" .. pal.id) ~= nil and H.buttonNamed(p, "Help_" .. pal.id) ~= nil and H.buttonNamed(p, "Sell_" .. pal.id) ~= nil, "pals", "Move, Work and Sell on its row")
H.expect(H.buttonNamed(p, "OpenTide") ~= nil and H.buttonNamed(p, "OpenTree", true) == nil and H.buttonNamed(p, "EquipBest", true) == nil, "pals", "Tide beside the hint (no tree, no Equip best)")
-- its mutations on its row, each by name (Data/Traits), or "No mutations"
do
	local pg = p:FindFirstChild("PlayerGui")
	local shown = 0
	for _, id in pal.muts or {} do
		if pg and pg:FindFirstChild("Mut_" .. id, true) then
			shown += 1
		end
	end
	local none = pg and pg:FindFirstChild("Muts", true)
	H.expect(if #(pal.muts or {}) > 0 then shown == #(pal.muts or {}) else none ~= nil, "pals", "its mutations on its row", string.format("%d of %d", shown, #(pal.muts or {})))
end
-- Work: the work picker (its knack's buildings and Rest); Rest, then back to work
do
	local job = pal.work
	H.clickNamed(p, "Help_" .. pal.id, { wait = 0.4 })
	H.expect(H.buttonNamed(p, "Go_0") ~= nil and H.buttonNamed(p, "Go_" .. job, true) ~= nil, "pals", "Work opens the work picker (its building, Rest)")
	H.clickNamed(p, "Go_0", { wait = 0.5 })
	H.expect(pal.work == 0, "pals", "Rest: it stops work", tostring(pal.work))
	H.openPanel(p, "pals", { pal = pal.id })
	H.clickNamed(p, "Go_" .. job, { wait = 0.5 })
	H.expect(pal.work == job, "pals", "Go: back to work there", tostring(pal.work))
end
-- Move: the hut picker (both huts, no pen); to the empty one it goes
calm(4)
H.openPanel(p, "pals")
H.clickNamed(p, "Move_" .. pal.id, { wait = 0.4 })
H.expect(H.buttonNamed(p, "Move_" .. hutB.uid) ~= nil and H.buttonNamed(p, "Move_" .. hutA.uid, true) ~= nil, "pals", "the hut picker lists both huts")
H.expect(H.buttonNamed(p, "Move_0", true) == nil, "pals", "and no pen")
H.clickNamed(p, "Move_" .. hutB.uid, { wait = 0.5 })
H.expect(pal.home == hutB.uid and H.currentPanel(p) == "pals", "pals", "moved to the second hut", string.format("home %d", pal.home))
-- back in a swap: one more off the tide fills the first hut again, so it swaps with one living there
do
	prof.shells = math.max(prof.shells, 2000)
	local d = cheapest()
	res = H.req(p, "tide.take", { id = d.id, swap = 0 })
	local x = prof.pals[#prof.pals]
	H.expect(res.ok and x.home == hutA.uid, "pals", "one more off the tide into the first hut (the comfiest with room)", string.format("%s home %d", tostring(res.err), x.home))
end
calm(4)
H.openPanel(p, "pals", { move = pal.id })
local other = nil
for _, x in prof.pals do
	if x.home == hutA.uid and other == nil then
		other = x
	end
end
H.expect(other ~= nil and H.buttonNamed(p, "SwapWith_" .. other.id) ~= nil, "pals", "a full hut: swap with one of its driftlings")
H.clickNamed(p, "SwapWith_" .. (if other then other.id else 0), { wait = 0.5 })
H.expect(pal.home == hutA.uid and other ~= nil and other.home == hutB.uid, "pals", "swapped: it lives in the first hut again, the other in the second", string.format("%d / %s", pal.home, tostring(other and other.home)))
-- selling from the panel takes two taps
calm(4)
do
	local nPals, sold0, sh1, t1 = #prof.pals, prof.stats.sold, prof.shells, E.now()
	local price = TideL.price(pal)
	H.openPanel(p, "pals")
	E.run(0.3)
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.3 })
	H.expect(#prof.pals == nPals, "pals", "one tap only asks Sure?")
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.5 })
	-- (the island earns meanwhile: its shells a second, a turn's rate over TurnSeconds)
	local earned = Island.rates(prof).shells / Tuning.TurnSeconds * (E.now() - t1) * 1.5 + 0.5
	local got = prof.shells - sh1
	H.expect(#prof.pals == nPals - 1 and table.find(prof.pals, pal) == nil and prof.stats.sold == sold0 + 1 and got >= price - 0.5 and got <= price + earned, "pals", "the second sells it for its price", string.format("%d driftlings, %+.1f shells (price %d, the island's own %.1f at most)", #prof.pals, got, price, earned))
end
-- Tide beside the hint opens the tide's panel
H.openPanel(p, "pals")
H.clickNamed(p, "OpenTide", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tide", "pals", "Tide opens the tide's panel", tostring(H.currentPanel(p)))
H.closePanel(p)
H.checkProfile(p, "pals")
H.checkMirror(p, "pals")

------------------------------------------------------------------ 6. the founder's looks
E.phase = "looks"
local skin0 = prof.founder.skin
H.openPanel(p, "looks")
E.run(0.4)
H.clickNamed(p, "Next_skin", { wait = 0.2 })
H.clickNamed(p, "SaveLook", { wait = 0.6 })
H.expect(prof.founder.skin == skin0 % 4 + 1, "looks", "the new skin is saved", string.format("%d -> %d", skin0, prof.founder.skin))
H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", prof.founder.skin, prof.founder.hair, prof.founder.style, prof.founder.shirt), "looks", "every client sees the new look (the Founder attribute)", tostring(p:GetAttribute("Founder")))
H.closePanel(p)

------------------------------------------------------------------ 7. the other panels, settings, tips, expanding
E.phase = "panels"
local errs0 = #E.errors
for _, name in { "pals", "tide", "hatch", "index", "looks" } do
	H.openPanel(p, name)
	E.run(0.3)
	H.expect(H.currentPanel(p) == name, "panels", name .. " opens")
end
H.closePanel(p)
H.openPanel(p, "tree")
H.expect(H.currentPanel(p) == nil, "panels", "no tree panel any more", tostring(H.currentPanel(p)))
H.expect(#E.errors == errs0, "panels", "no script errors in the panels", tostring(#E.errors - errs0))
res = H.req(p, "settings.set", { k = "pixel", v = "low" })
H.expect(res.ok and prof.settings.pixel == "low", "panels", "the pixel tier setting")
res = H.req(p, "settings.set", { k = "pixel", v = "ultra" })
H.expect(not res.ok and res.err == "bad_payload", "panels", "an unknown tier refused")
H.req(p, "settings.set", { k = "pixel", v = "high" })
E.run(0.4)
H.expect(H.buttonNamed(p, "TipsOk") ~= nil, "panels", "the last tip has an OK")
H.clickNamed(p, "TipsOk", { wait = 0.5 })
H.expect(prof.tut == 0 and H.buttonNamed(p, "TipsOk") == nil, "panels", "OK puts the tips away for good")
-- expanding costs wood (GAME_DESIGN 3: "make wood the main resource for building/expanding"): short of it, refused
-- whatever the shells
prof.shells, prof.wood = 1e6, 10
res = H.req(p, "island.expand", {})
H.expect(not res.ok and res.err == "wood" and prof.tier == 1, "panels", "Expand short of wood is refused, shells or not", tostring(res.err))
-- expanding from the build tray: the next island was built ahead in the background, so the expansion swaps it in (no
-- ~1,200 parts made in the frame of the click), and the cheer waits for the bigger island's picture
prof.shells, prof.wood = 500, Tuning.TierCost[2] + 300
H.push(p, 0.4)
local PS = H.smod("PlotService")
local guardNext = 0
while not select(2, PS.debugNext(1)) and guardNext < 40 do
	guardNext += 1
	E.run(0.25)
end
local nt, nready, swaps0 = PS.debugNext(1)
H.expect(nt == 2 and nready, "panels", "the next island is built ahead in the background", string.format("%s %s", tostring(nt), tostring(nready)))
H.clickNamed(p, "Menu_build", { wait = 0.5 })
local woodX, shellsX = prof.wood, prof.shells
H.clickNamed(p, "Expand", { wait = 0 })
H.expect(prof.tier == 2, "panels", "Expand: the island grows", tostring(prof.tier))
H.expect(math.abs(prof.wood - (woodX - Tuning.TierCost[2])) < 2 and prof.shells >= shellsX - 1, "panels", "for its wood (no shells)", string.format("wood %+.1f (cost %d), shells %+.1f", prof.wood - woodX, Tuning.TierCost[2], prof.shells - shellsX))
local _, _, swaps1 = PS.debugNext(1)
H.expect(swaps1 == swaps0 + 1, "panels", "the expansion swaps in the island built ahead", string.format("%d -> %d", swaps0, swaps1))
local cheerAt = -1
for k = 1, 30 do
	E.run(0.05)
	if statusSays("Your island grew") then
		cheerAt = k * 0.05
		break
	end
end
H.expect(cheerAt > 0 and cheerAt <= 1.5, "panels", "the cheer comes with the bigger island's picture", string.format("%.2f s", cheerAt))
local PRx = H.cmod(p, "Pixel.PixelRenderer")
H.log("expansion: the next island was ready, swapped in; the cheer came %.2f s after the click (filter %s, bakes %d)", cheerAt, tostring(PRx.tier()), PRx.debugStatic().bakes)
E.run(0.5)
local st2 = E.workspace.Plots.Plot_1:FindFirstChild("Static")
H.expect(st2 ~= nil and st2:GetAttribute("Built") == 2, "panels", "the island is rebuilt bigger", tostring(st2 and st2:GetAttribute("Built")))
local lands = 0
for _, c in st2:GetChildren() do
	if c.Name == "Land" then
		lands += 1
	end
end
H.expect(lands == 1, "panels", "one island model after the swap", tostring(lands))
H.expect((PS.debugNext(1)) == 3, "panels", "the island after that is planned", tostring((PS.debugNext(1))))
H.clickNamed(p, "BuildDone", { wait = 0.4 })
H.checkProfile(p, "panels")
H.checkMirror(p, "panels")

------------------------------------------------------------------ the questline (GAME_DESIGN 9)
-- once the tips are over a card down the left names the quest on the go: Go opens the place it needs, and when its
-- goal is met Claim pays its reward and the next quest comes up; claims too early or during the tips are refused
E.phase = "quests"
local Quests = H.sharedServer("Data.Quests")
local function questAt(id)
	for i, q in Quests.list do
		if q.id == id then
			return i
		end
	end
	return 1
end
prof.quest = 1
for _, x in prof.pals do
	x.work = 0
end
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestGo") ~= nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "the first quest's card: put a driftling to work, Go")
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "pals", "quests", "Go opens the Driftlings panel", tostring(H.currentPanel(p)))
H.expect(H.buttonNamed(p, "QuestGo") == nil, "quests", "the card steps aside for the panel")
H.closePanel(p)
E.run(0.3)
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "a claim before the goal is met is refused", tostring(res.err))
-- (a driftling sent to work at a building of its knack, the way the Driftlings panel's Work does)
local sent = false
for _, x in prof.pals do
	if x.home == 0 then
		continue
	end
	local d = Creatures.byId[x.sp]
	for _, q in prof.plot.placed do
		local b = Buildings.byId[q.id]
		if not sent and d and b and b.knack == d.knack and Island.works(q.id) then
			sent = H.req(p, "pal.work", { id = x.id, uid = q.uid }).ok
		end
	end
end
H.expect(sent, "quests", "a driftling sent to work at a building of its knack")
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "a driftling at work: Claim shows")
do
	local shells0, wood0q = prof.shells, prof.wood
	local reward = Quests.list[1].reward
	H.clickNamed(p, "QuestClaim", { wait = 0.5 })
	H.expect(prof.quest == 2 and prof.shells >= shells0 + (reward.shells or 0) and prof.wood >= wood0q + (reward.wood or 0), "quests", "Claim pays the reward (shells and wood) and moves on", string.format("quest %d, shells %+d, wood %+d", prof.quest, prof.shells - shells0, prof.wood - wood0q))
end
-- the tide's quests: Go opens the tide's panel; sixty taken in is a long way off, three are done by now
prof.quest = questAt("crowd")
H.push(p, 0.5)
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tide", "quests", "Go on a tide quest opens the tide's panel", tostring(H.currentPanel(p)))
H.closePanel(p)
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "sixty off the tide not reached: not done", string.format("%s taken %d", tostring(res.err), prof.stats.taken))
prof.quest = questAt("take3")
H.push(p, 0.5)
H.expect(prof.stats.taken >= 3 and H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "three taken in off the tide: Claim shows", string.format("taken %d", prof.stats.taken))
H.clickNamed(p, "QuestClaim", { wait = 0.5 })
H.expect(prof.quest == questAt("take3") + 1, "quests", "and Claim moves on", tostring(prof.quest))
prof.quest = questAt("paths")
H.push(p, 0.5)
local paths = 0
for _, q in prof.plot.placed do
	if Plot.isPath(q.id) then
		paths += 1
	end
end
if paths < 8 then
	H.clickNamed(p, "QuestGo", { wait = 0.5 })
	H.expect(H.inClient(p, BuildUI.isOpen) and H.inClient(p, BuildUI.debugState).tab == "path", "quests", "Go opens Build mode on the Paths tab")
	H.clickNamed(p, "BuildDone", { wait = 0.4 })
end
prof.tut = 5
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_found", "quests", "no quests while the tips are on", tostring(res.err))
prof.tut = 0
prof.quest = #Quests.list + 1
H.push(p, 0.4)
H.expect(H.buttonNamed(p, "QuestGo") == nil and H.buttonNamed(p, "QuestClaim") == nil, "quests", "every quest done: no card")
prof.quest = 2
H.push(p, 0.3)
H.checkProfile(p, "quests")
H.checkMirror(p, "quests")

------------------------------------------------------------------ 8. a malicious client
E.phase = "malicious"
local function snap()
	local q = H.profile(p)
	return { placed = #q.plot.placed, pals = #q.pals, tier = q.tier, skin = q.founder.skin, tut = q.tut, sold = q.stats.sold, taken = q.stats.taken, wood = math.floor(q.wood / 1000) }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
-- (every hut full first, so a take asks for a swap)
prof.shells = math.max(prof.shells, 5000)
for _ = 1, 4 do
	local d = cheapest()
	if TideL.room(prof) > 0 and d then
		H.req(p, "tide.take", { id = d.id, swap = 0 })
	end
end
H.expect(TideL.room(prof) == 0, "malicious", "(the huts filled off the tide)", tostring(TideL.room(prof)))
-- (the shells aside: every building works a little with nobody at it, so the farms and the stall go on selling;
-- they are checked apart, a jump being what a refusal let through)
prof.wood = 5500
H.push(p, 0.3)
local before = snap()
local shellsBefore = prof.shells
local ok, out = H.raw(p, "shells.give", { n = 1e9 })
expectRefused("an unknown action", ok, out, "unknown_action")
ok, out = H.rawArgs(p, nil)
expectRefused("no action", ok, out, "unknown_action")
ok, out = H.raw(p, "game.make", { a = 1, b = 2, c = 3 })
expectRefused("the old studio's actions", ok, out, "unknown_action")
-- (the run's two deliberate non-finite payloads: the engine lists them apart)
ok, out = H.raw(p, "pal.work", { id = 0 / 0, uid = 1 })
expectRefused("NaN", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = math.huge, uid = 0, swap = 0 })
expectRefused("infinity", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = string.rep("a", 100000), x = 0, z = 0, rot = 0 })
expectRefused("a huge string", ok, out, "bad_payload")
ok, out = H.raw(p, "island.expand", { x = 1 })
expectRefused("an extra field", ok, out, "bad_payload")
ok, out = H.rawArgs(p, "island.expand", "x")
expectRefused("a string payload", ok, out, "bad_payload")
for _, old in { "exp.start", "exp.next", "exp.snack", "exp.skill", "exp.flee", "exp.pause", "exp.home", "pouch.upgrade", "pal.release", "boat.upgrade" } do
	ok, out = H.raw(p, old, {})
	expectRefused("the expeditions' " .. old .. " (gone)", ok, out, "unknown_action")
end
for _, old in { "folk.work", "folk.dismiss" } do
	ok, out = H.raw(p, old, { id = 1, uid = 0 })
	expectRefused("the villagers' " .. old .. " (gone)", ok, out, "unknown_action")
end
-- the Tree of Life's and its pen's actions (gone with the tide)
ok, out = H.raw(p, "pen.sell", { r = 1 })
expectRefused("the pen's pen.sell (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "pen.best", {})
expectRefused("the pen's pen.best (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "tree.upgrade", { what = "speed" })
expectRefused("the tree's tree.upgrade (gone)", ok, out, "unknown_action")
-- the tide's: bad payloads, one not there, a swap that isn't in a hut
ok, out = H.raw(p, "tide.take", { id = "1", swap = 0 })
expectRefused("a tide id that isn't a number", ok, out, "bad_payload")
ok, out = H.raw(p, "tide.take", { id = -1, swap = 0 })
expectRefused("a negative tide id", ok, out, "bad_payload")
ok, out = H.raw(p, "tide.take", { id = 1.5, swap = 0 })
expectRefused("a tide id with a fraction", ok, out, "bad_payload")
ok, out = H.raw(p, "tide.take", { id = 1 })
expectRefused("a take without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "tide.take", { id = 1, swap = 0, n = 5 })
expectRefused("a take with an extra field", ok, out, "bad_payload")
ok, out = H.raw(p, "tide.take", { id = 424242, swap = 0 })
expectRefused("a driftling not at the jetty", ok, out, "not_found")
do
	-- (every hut full, so a swap is asked for: one that lives nowhere is no swap)
	local d = cheapest()
	if TideL.room(prof) == 0 and d then
		ok, out = H.raw(p, "tide.take", { id = d.id, swap = 424242 })
		expectRefused("a swap that isn't one of theirs", ok, out, "bad_payload")
		ok, out = H.raw(p, "tide.take", { id = d.id, swap = 0 })
		expectRefused("every hut full and no swap", ok, out, "full")
	end
end
ok, out = H.raw(p, "pal.house", { id = 424242, uid = 0, swap = 0 })
expectRefused("a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = pieceOf("lumber").uid, swap = 0 })
expectRefused("a lumber camp is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0, swap = 0 })
expectRefused("moving out of every hut (no pen)", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0 })
expectRefused("a move without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.sell", { id = 424242 })
expectRefused("selling a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "plot.store", { i = 1000 })
expectRefused("clearing away a piece that isn't there", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 })
expectRefused("a Tree of Life (gone)", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "cottage", x = 0, z = 0, rot = 0 })
expectRefused("a home (gone)", ok, out, "bad_payload")
ok, out = H.raw(p, "founder.set", { skin = 9, hair = 1, style = 1, shirt = 1 })
expectRefused("a skin that does not exist", ok, out, "bad_payload")
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
H.expect(math.abs(prof.shells - shellsBefore) < 50, "malicious", "and moved no shells (the island's own earnings aside)", string.format("%+.1f", prof.shells - shellsBefore))
-- a flood: 30 requests at once, the rate limit refuses most
local results = {}
H.inClient(p, function()
	local remote = E.find("ReplicatedStorage.Remotes.Request")
	local done = 0
	for i = 1, 30 do
		E.task.spawn(function()
			results[i] = remote:InvokeServer("tut.next", {})
			done += 1
		end)
	end
	while done < 30 do
		E.task.wait(0.05)
	end
end)
local rated = 0
for _, x in results do
	if type(x) == "table" and x.err == "rate" then
		rated += 1
	end
end
H.expect(rated >= 30 - Tuning.RateLimitPerSec, "malicious", "the rate limit refuses a flood", string.format("%d of 30 refused", rated))
E.run(0.5)
H.checkProfile(p, "malicious")
H.checkMirror(p, "malicious")

------------------------------------------------------------------ 9. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets island 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their island is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own island")
H.expect(housedN() > 0 and H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount) >= housedN(), "second", "the second client draws the first island's hut driftlings", string.format("%d of %d", H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount), housedN()))
do
	local TVq = H.cmod(q, "Controllers.TideView")
	H.expect(H.inClient(q, TVq.count, 1) >= 1 and H.inClient(q, TVq.count, 2) >= Tuning.TideStart, "second", "the second client draws both islands' tides", string.format("island 1: %d, island 2: %d", H.inClient(q, TVq.count, 1), H.inClient(q, TVq.count, 2)))
	local first = true
	for _, d in sq.tide.list do
		local c = Creatures.byId[d.sp]
		first = first and c ~= nil and c.rarity == 1
	end
	H.expect(#sq.tide.list == Tuning.TideStart and first, "second", "their own tide starts with two commons too", tostring(#sq.tide.list))
end
H.checkProfile(q, "second")
H.checkMirror(q, "second")
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
