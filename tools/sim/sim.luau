-- The main simulation: a new island end to end through the real client and its UI (the campfire, the jetty, the tide
-- already floating past, the HUD with its tide card, the tips), building what the tips ask in their order (a lumber
-- camp, a veggie patch, a hut, then a driftling taken off the tide by tapping it as it floats past, then a snack stall:
-- the starting wood and shells cover them), the days turning (the stores grow, every building working a little with
-- nobody at it), the tide (one coming in every TideSecs and floating past the island in TideLife seconds, then gone;
-- each in the Index; the plot's Tide attribute; the lane every client draws them on; the price tags, hidden while one
-- is under and where they'd cover a better one's, names only on the rarer ones; the HUD's card with the best three and
-- the time they have left, one taken in from it; the tide's panel with the best four, rebuilt only when they change,
-- its Take opening the swap picker once the hut is full; a world tag's swap picker going back to the list when its
-- driftling floats off), the Driftlings panel (moving one to a second hut and back in a swap, Work, selling in two
-- taps), the Index panel, the founder's looks, settings, expanding for wood, the questline, then a malicious client,
-- then a second player. No villagers since 2026-11-12, no Tree of Life and no food since 2026-11-13, the tide a
-- conveyor since 2026-11-13. Every check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
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
local SCp = H.cmod(p, "Controllers.StateClient")
local PRp = H.cmod(p, "Pixel.PixelRenderer")
local WVp = H.cmod(p, "Controllers.WorldView")
local CCp = H.cmod(p, "Controllers.CameraController")
-- the session's drift `id` while it is still floating past, or nil
local function onTide(id)
	for _, d in s.tide.list do
		if d.id == id then
			return d
		end
	end
	return nil
end
local function idsOf(list)
	local out = {}
	for _, d in list do
		table.insert(out, tostring(d.id))
	end
	return table.concat(out, ",")
end
-- the best n floating by, as the HUD's card and the tide panel pick them (GAME_DESIGN 6): the best workers first
-- (Tide.worth, the newer of two the same), and if the shells cover none of those, the best one they do in the last place
local function bestOf(list, shells, n)
	local sorted = table.clone(list)
	local function w(d)
		return TideL.worth({ id = 0, sp = d.sp, home = 0, work = 0, muts = d.muts })
	end
	table.sort(sorted, function(a, b)
		if math.abs(w(a) - w(b)) > 1e-9 then
			return w(a) > w(b)
		end
		return a.id > b.id
	end)
	local out, can = {}, false
	for i = 1, math.min(n, #sorted) do
		table.insert(out, sorted[i])
		can = can or shells >= sorted[i].cost
	end
	if not can and #out > 0 then
		for i = n + 1, #sorted do
			if shells >= sorted[i].cost then
				out[#out] = sorted[i]
				break
			end
		end
	end
	return out
end
-- the view's tide and the session's hold the same ones (an Fx tide reaches the client a frame after the server's step)
local function tideSynced(pl)
	local v, ss = H.view(pl), H.session(pl)
	return v ~= nil and ss ~= nil and idsOf(v.tide) == idsOf(ss.tide.list)
end
local function mirror(pl, label)
	E.runUntil(function()
		return tideSynced(pl)
	end, 0.5)
	H.checkMirror(pl, label)
end
-- the own island's price tags now, as the player sees them: for each of the view's drifts that has a tag on the World
-- canvas, how far along and under it is, whether its tag and name show, whether it is on screen, its worth and its tag's
-- place on the canvas (Controllers/TideView)
local function tagState()
	local v = H.view(p)
	local ox = Street.origin(s.plot)
	local out = H.inClient(p, function()
		local list = {}
		local canvas = UIKitP.canvas("World")
		for _, d in v.tide do
			local tag = canvas:FindFirstChild("TideTake_" .. d.id, true)
			local x, y, z = TideViewP.where(s.plot, d.id)
			if tag and x then
				local k = SCp.along(d)
				local depth = TideViewP.depth(x - ox, k)
				local _, _, on = PRp.projectPixel(E.v3(x, y + depth + 2.9, z))
				local name = canvas:FindFirstChild("TideName_" .. d.id, true)
				table.insert(list, {
					d = d,
					k = k,
					depth = depth,
					on = on,
					shown = H.guiVisible(tag),
					hasName = name ~= nil,
					nameShown = name ~= nil and H.guiVisible(name),
					rect = { tag.Position.X.Offset, tag.Position.Y.Offset, tag.Size.X.Offset, tag.Size.Y.Offset },
				})
			end
		end
		return list
	end)
	for _, e in out do
		e.worth = TideL.worth({ id = 0, sp = e.d.sp, home = 0, work = 0, muts = e.d.muts })
		local c = Creatures.byId[e.d.sp]
		e.rarity = c and c.rarity or 1
	end
	return out
end
-- what's wrong with the tags now: one showing while under, a name on a common (or missing on a rarer one, or showing
-- apart from its price), two showing over each other, the best worker on screen and above the water without its tag
local function tagProblems(st)
	local bad = {}
	local shown = {}
	local best = nil
	for _, e in st do
		if e.shown and e.depth >= 0.6 then
			table.insert(bad, "under " .. e.d.id)
		end
		if e.hasName ~= (e.rarity >= 2) or (e.hasName and e.nameShown ~= e.shown) then
			table.insert(bad, "name " .. e.d.id)
		end
		if e.shown then
			for _, o in shown do
				local a, b = e.rect, o.rect
				if a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4] then
					table.insert(bad, string.format("overlap %d/%d", e.d.id, o.d.id))
				end
			end
			table.insert(shown, e)
		end
		if e.on and e.depth < 0.6 and (best == nil or e.worth > best.worth + 1e-9 or (math.abs(e.worth - best.worth) <= 1e-9 and e.d.id < best.d.id)) then
			best = e
		end
	end
	if best and not best.shown then
		table.insert(bad, "best hidden " .. best.d.id)
	end
	return bad
end
-- the shells the island may have earned on its own since t1 (a turn's rate over TurnSeconds, with room to spare;
-- `rate`: the rate before a change that may have lowered it)
local function earnedSince(t1, rate)
	return math.max(rate or 0, Island.rates(prof).shells) / Tuning.TurnSeconds * (E.now() - t1) * 1.5 + 0.5
end
-- the shells moved since sh1 come to `want`, give or take what the island earned on its own since t1
local function paid(sh1, want, t1, rate)
	local got = prof.shells - sh1
	return got >= want - 0.5 and got <= want + earnedSince(t1, rate)
end
-- the tide (GAME_DESIGN 6): already running when the player arrives, one coming in every TideSecs and floating past the
-- island in TideLife seconds, so TideLife / TideSecs are on the way at once; while the island has taken nothing in,
-- every third one is a common good at its first buildings (with wood or at a farm, by turns); each one seen is in the
-- Index. The HUD's tide card shows the best three (TideView.best) with their prices, and TideView floats every one
-- along the lane past the island, the price tags over the ones it can show
do
	local list = s.tide.list
	local secs, life = TideL.secs(prof), TideL.life(prof)
	local n = math.floor(life / secs + 1e-9)
	H.expect(math.abs(life - Tuning.TideLife) < 1e-9 and math.abs(secs - Tuning.TideSecs) < 1e-9 and Tuning.TideMax == nil and Tuning.TideStart == nil, "join", "the tide's pace on a new island: one every TideSecs, TideLife seconds to float past (no TideMax, no TideStart)", string.format("%.2f s, %.2f s", secs, life))
	H.expect(math.abs(#list - n) <= 1, "join", "the tide is already running: TideLife / TideSecs floating past", string.format("%d of %d", #list, n))
	local spaced, onWay = true, true
	for i, d in list do
		onWay = onWay and s.tide.clock - d.at < d.life and math.abs(d.life - life) < 1e-9
		if i > 1 then
			spaced = spaced and math.abs(d.at - list[i - 1].at - secs) < 1e-6
		end
	end
	H.expect(spaced and onWay, "join", "each one came in TideSecs after the last and is still on its way", string.format("%s %s", tostring(spaced), tostring(onWay)))
	local firsts, okFirst, knacks, seen = 0, true, {}, true
	for _, d in list do
		local c = Creatures.byId[d.sp]
		if d.id % 3 == 1 then
			firsts += 1
			okFirst = okFirst and c ~= nil and c.rarity == 1 and (c.knack == "wood" or c.knack == "farm")
			if c then
				knacks[c.knack] = true
			end
		end
		seen = seen and (prof.seen[d.sp] or 0) >= 1
	end
	H.expect(firsts >= 2 and okFirst and knacks.wood and knacks.farm, "join", "a new island's every third one: a common good with wood or at a farm, by turns", table.concat((function()
		local out = {}
		for _, d in list do
			table.insert(out, d.id .. "." .. d.sp)
		end
		return out
	end)(), ","))
	H.expect(seen, "join", "each one seen is in the Index")
	E.runUntil(function()
		return tideSynced(p)
	end, 0.5)
	local v0 = H.view(p)
	local same = v0 ~= nil and #v0.tide == #list
	for i, d in list do
		same = same and v0.tide[i].id == d.id and v0.tide[i].at == d.at and v0.tide[i].life == d.life and v0.tide[i].cost == d.cost
	end
	H.expect(same and v0.tideSecs == secs and v0.tideT == nil and v0.tree == nil and v0.penN == nil, "join", "the view carries the tide (each one's time it came and its time to float past) and its pace (no tideT, no tree, no pen)", v0 and string.format("%d of %d, %s s", #v0.tide, #list, tostring(v0.tideSecs)))
	local card = p.PlayerGui:FindFirstChild("TideCard", true)
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TideOpen") ~= nil and card:FindFirstChild("TideBar", true) == nil, "join", "the HUD's tide card with Open (no bar to the next one)")
	local best3 = H.inClient(p, TideViewP.best, v0, 3)
	local rows, cardRows = 0, 0
	for _, d in best3 do
		if H.buttonNamed(p, "CardTake_" .. d.id, true) ~= nil and card and card:FindFirstChild("TideName_" .. d.id, true) and card:FindFirstChild("TideLeft_" .. d.id, true) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 9) == "CardTake_" then
			cardRows += 1
		end
	end
	H.expect(#best3 == math.min(3, #list) and rows == #best3 and cardRows == #best3, "join", "the card shows the best three floating by, each with its name, its price and the time it has left", string.format("%d rows of %d, %d on the card", rows, #best3, cardRows))
	E.runUntil(function()
		return H.inClient(p, TideViewP.count, s.plot) >= #list - 1
	end, 2, 0.1)
	local followed, drawn = H.inClient(p, TideViewP.count, s.plot)
	H.expect(followed >= #list - 1 and followed <= #list + 2 and drawn >= 1, "join", "TideView floats them past the island (the ones near the view drawn)", string.format("%d followed, %d drawn of %d", followed, drawn, #list))
	local st = tagState()
	local shownTags = 0
	for _, e in st do
		if e.shown then
			shownTags += 1
		end
	end
	local bad = tagProblems(st)
	H.expect(shownTags >= 1 and #bad == 0, "join", "price tags over the ones it can show (not while under, not over a better one's; names on the rarer ones only)", string.format("%d tags, %d showing: %s", #st, shownTags, table.concat(bad, " ")))
	-- no hut yet: a tap on a price is refused (no_hut) and says why (the newest on the card: it has the most time left)
	local d1 = nil
	for _, d in best3 do
		if d1 == nil or d.at > d1.at then
			d1 = d
		end
	end
	local sh = prof.shells
	H.clickNamed(p, "CardTake_" .. d1.id, { wait = 0.5 })
	H.expect(#prof.pals == 0 and prof.shells == sh and onTide(d1.id) ~= nil, "join", "no hut yet: taking one in is refused, nothing paid", string.format("%d driftlings, %s shells", #prof.pals, tostring(prof.shells)))
	H.expect(statusSays("Build a hut first"), "join", "and the notice says to build a hut first")
	local res = H.req(p, "tide.take", { id = d1.id, swap = 0 })
	H.expect(not res.ok and res.err == "no_hut", "join", "the server's word for it: no_hut", tostring(res.err))
end
H.checkProfile(p, "join")
mirror(p, "join")

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
-- step 4: one off the tide, the driftling itself tapped as it floats past (TideView.tapAt: WorldView's taps ask it
-- first): one good at a building the island has (every third one on a new island is) that the shells cover, above the
-- water and in view; into the hut and off to work at a building of its knack
do
	local has = {}
	for _, q in prof.plot.placed do
		has[Buildings.byId[q.id].knack] = true
	end
	H.push(p, 0.3)
	local ox = Street.origin(s.plot)
	-- (in the client: the cheapest such one now, and the screen point in the middle of it, as a tap's position)
	local function target()
		local v = H.view(p)
		return H.inClient(p, function()
			local focus = CCp.centerWorld()
			local pick, pos = nil, nil
			for _, d in v.tide do
				local c = Creatures.byId[d.sp]
				local k = SCp.along(d)
				local x, y, z = TideViewP.where(s.plot, d.id)
				if c and has[c.knack] and d.cost <= v.shells and k > 0.1 and k < 0.75 and x and math.abs(x - focus.X) < 55 then
					local depth = TideViewP.depth(x - ox, k)
					local feet, on = PRp.project(E.v3(x, y + depth, z))
					local head = PRp.project(E.v3(x, y + depth + 2.4, z))
					if depth < 0.3 and on and (pick == nil or d.cost < pick.cost) then
						pick, pos = d, E.v2(feet.X, (feet.Y + head.Y) / 2 - E.inset)
					end
				end
			end
			return pick, pos
		end)
	end
	local pick, pos = nil, nil
	E.runUntil(function()
		pick, pos = target()
		return pick ~= nil
	end, Tuning.TideLife, 0.1)
	H.expect(pick ~= nil and prof.shells >= pick.cost, "build", "one floating past has work here, the starting shells cover it and it's in view", pick and string.format("%s shells, it costs %d", tostring(prof.shells), pick.cost) or "none with work here")
	if pick then
		local sh1, t1, rate0 = prof.shells, E.now(), Island.rates(prof).shells
		local fTaken = #fx
		H.inClient(p, WVp.tapScreen, pos)
		E.run(0.6)
		local first = prof.pals[1]
		H.expect(#prof.pals == 1 and prof.stats.taken == 1 and first.sp == pick.sp and paid(sh1, -pick.cost, t1, rate0), "build", "a tap on the driftling itself as it floats past takes it in for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(onTide(pick.id) == nil, "build", "and it leaves the tide")
		E.runUntil(function()
			return H.inClient(p, TideViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(H.inClient(p, TideViewP.where, s.plot, pick.id) == nil, "build", "it hops ashore and is gone from the lane")
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
mirror(p, "build")

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
		if fx[i].tideT == nil and H.finite(fx[i].tideSecs) and fx[i].tideSecs > 0 and fx[i].grow == nil and fx[i].food == nil then
			tideTicks += 1
		end
	end
end
H.expect(ticks >= math.floor(E.now() - t0) - 3, "days", "the stores reach the client every second (Fx tick)", string.format("%d ticks in %.1f s", ticks, E.now() - t0))
H.expect(tideTicks == ticks, "days", "each tick carries the tide's pace (no tideT: the tide runs on the server's time; no tree, no food)", string.format("%d of %d", tideTicks, ticks))
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
mirror(p, "days")

------------------------------------------------------------------ 4. the tide (GAME_DESIGN 6)
E.phase = "tide"
-- the cheapest one floating past (that `ok` likes) with a few seconds left, so a request for it isn't cut off by its
-- floating off
local function cheapest(ok)
	local best = nil
	for _, d in s.tide.list do
		if TideL.along(d, E.now()) < 0.75 and (ok == nil or ok(d)) and (best == nil or d.cost < best.cost) then
			best = d
		end
	end
	return best
end
-- (the full views the client gets from now on: the tide alone sends none, only patches)
local views = 0
H.inClient(p, function()
	SCp.Changed:Connect(function()
		views += 1
	end)
end)
-- a fishing pier, so every kind of the first island's driftlings has a building of its knack to work at
prof.wood = math.max(prof.wood, 400)
res = place("pier")
H.expect(res.ok, "tide", "a fishing pier", tostring(res.err))
-- one comes in every Tide.secs and floats past the island in Tide.life seconds, then it's gone (Fx tide came and gone),
-- so the count on the way stays put; meanwhile the price tags keep their rules at every moment
local goneId = nil
do
	local secs, life = TideL.secs(prof), TideL.life(prof)
	local n = math.floor(life / secs + 1e-9)
	local known = {}
	for _, d in s.tide.list do
		known[d.id] = { at = d.at, life = d.life }
	end
	local cameAt, goneAt, cameIds = {}, {}, {}
	local lo, hi = #s.tide.list, #s.tide.list
	local samples, bad, under, crowded = 0, {}, 0, 0
	local fSeen = #fx
	local views0 = views
	local t0 = E.now()
	while E.now() - t0 < 6 do
		E.run(E.dt)
		for i = fSeen + 1, #fx do
			local m = fx[i]
			if m.kind == "tide" then
				for _, x in (if type(m.came) == "table" then m.came else {}) do
					cameAt[x.id] = E.now()
					known[x.id] = { at = x.at, life = x.life }
					table.insert(cameIds, x.id)
				end
				for _, id in (if type(m.gone) == "table" then m.gone else {}) do
					goneAt[id] = E.now()
				end
			end
		end
		fSeen = #fx
		lo, hi = math.min(lo, #s.tide.list), math.max(hi, #s.tide.list)
		local st = tagState()
		samples += 1
		for _, b in tagProblems(st) do
			table.insert(bad, string.format("%.2f %s", E.now() - t0, b))
		end
		for _, e in st do
			if e.depth >= 0.6 then
				under += 1
			elseif e.on and not e.shown then
				crowded += 1
			end
		end
	end
	local want = 6 / secs
	H.expect(#cameIds >= math.floor(want) - 1 and #cameIds <= math.ceil(want) + 1, "tide", "one comes in every Tide.secs (Fx tide came)", string.format("%d in 6 s (every %.2f s)", #cameIds, secs))
	local spaced, onTime = true, true
	for i, id in cameIds do
		local k = known[id]
		onTime = onTime and cameAt[id] - k.at >= -1e-6 and cameAt[id] - k.at <= 0.25 and math.abs(k.life - life) < 1e-6
		if i > 1 then
			spaced = spaced and math.abs(k.at - known[cameIds[i - 1]].at - secs) < 1e-6
		end
	end
	H.expect(spaced and onTime, "tide", "each one's time it came in is the moment it came, Tide.secs after the last, its time to float past Tide.life", string.format("%s %s", tostring(spaced), tostring(onTime)))
	local gones, ontimeGone, stillThere = 0, true, false
	for id, at in goneAt do
		gones += 1
		goneId = goneId or id
		local k = known[id]
		ontimeGone = ontimeGone and k ~= nil and at - (k.at + k.life) >= -1e-6 and at - (k.at + k.life) <= 0.25
		stillThere = stillThere or onTide(id) ~= nil
	end
	H.expect(gones >= math.floor(want) - 1 and ontimeGone and not stillThere, "tide", "each one is gone once it has floated past for Tide.life seconds (Fx tide gone)", string.format("%d gone, on time %s, still there %s", gones, tostring(ontimeGone), tostring(stillThere)))
	H.expect(lo >= n - 1 and hi <= n + 1, "tide", "so Tide.life / Tide.secs float past at any moment", string.format("%d to %d (%d)", lo, hi, n))
	H.expect(views == views0, "tide", "the tide sends no whole view (the client patches its copy)", string.format("%d views", views - views0))
	local seen = true
	for _, d in s.tide.list do
		seen = seen and (prof.seen[d.sp] or 0) >= 1
	end
	H.expect(seen, "tide", "each one that comes in is seen in the Index")
	H.expect(samples > 0 and #bad == 0, "tide", "at every moment the price tags keep their rules (none while under, none over another, names on the rarer ones only, the best one in view always tagged)", string.format("%d samples: %s", samples, string.sub(table.concat(bad, "; "), 1, 600)))
	H.expect(under > 0, "tide", "(some went under the jetty or at the ends meanwhile, their tags hidden)", string.format("%d under, %d crowded out", under, crowded))
	H.log("tide: %d came, %d gone in 6 s; tags: %d under, %d crowded out over %d samples", #cameIds, gones, under, crowded, samples)
end
-- every client draws them from the plot's Tide attribute: "id.species.at.life" (tenths of a second, the server's time)
do
	local raw = plot1:GetAttribute("Tide")
	local parsed = {}
	for entry in string.gmatch(raw or "", "[^;]+") do
		local id, sp, at, life = string.match(entry, "^(%d+)%.([%w_]+)%.(%d+)%.(%d+)$")
		table.insert(parsed, { id = tonumber(id), sp = sp, at = tonumber(at), life = tonumber(life) })
	end
	local same = #parsed == #s.tide.list
	for i, d in s.tide.list do
		local e = parsed[i]
		same = same and e ~= nil and e.id == d.id and e.sp == d.sp and e.at == math.floor(d.at * 10 + 0.5) and e.life == math.floor(d.life * 10 + 0.5)
	end
	H.expect(same, "tide", "the plot's Tide attribute: each one's id, kind, time it came and time to float past", string.sub(tostring(raw), 1, 200))
end
-- the client's clock is the server's, so it puts each one where the server's clock says, on the lane past the island
-- (Street.TIDE: from x0 to x1, west to east)
do
	E.runUntil(function()
		return tideSynced(p)
	end, 0.5)
	local v1 = H.view(p)
	local now, okAlong = H.inClient(p, SCp.tideNow), true
	for _, d in v1.tide do
		okAlong = okAlong and math.abs(H.inClient(p, SCp.along, d) - TideL.along(d, E.now())) < 1e-6
	end
	H.expect(math.abs(now - E.now()) < 1e-6 and okAlong and v1.tideT == nil, "tide", "the client's tide clock is the server's time (StateClient.tideNow, along)", string.format("%.3f vs %.3f", now, E.now()))
	local ox, oz = Street.origin(s.plot)
	local lane = Street.TIDE
	local onLane, followed, worst = true, 0, 0
	for _, d in s.tide.list do
		local x, _, z = H.inClient(p, TideViewP.where, s.plot, d.id)
		if x then
			followed += 1
			local want = ox + lane.x0 + (lane.x1 - lane.x0) * TideL.along(d, E.now())
			worst = math.max(worst, math.abs(x - want))
			onLane = onLane and math.abs(z - (oz + lane.z)) < 1e-6 and math.abs(x - want) < 0.3
		end
	end
	local nf, drawn = H.inClient(p, TideViewP.count, s.plot)
	H.expect(onLane and followed >= #s.tide.list - 1, "tide", "each one rides the lane past the island, as far along as its time says", string.format("%d of %d followed, %.2f studs off at most", followed, #s.tide.list, worst))
	H.expect(drawn >= 1 and drawn <= nf, "tide", "the ones near the view have models", string.format("%d drawn of %d followed", drawn, nf))
end
-- TideView.best's rule on a made-up tide: three uncommons the shells don't cover and two commons they do; the best
-- uncommons first and the better common in the last place. With the shells, the best three
do
	local made = {
		{ id = 1, sp = "gullfin", muts = {}, cost = 80, at = 0, life = 16 },
		{ id = 2, sp = "pebblit", muts = {}, cost = 20, at = 0, life = 16 },
		{ id = 3, sp = "conchy", muts = {}, cost = 80, at = 0, life = 16 },
		{ id = 4, sp = "frondle", muts = {}, cost = 20, at = 0, life = 16 },
		{ id = 5, sp = "twiggle", muts = {}, cost = 80, at = 0, life = 16 },
	}
	local poor = H.inClient(p, TideViewP.best, { tide = made, shells = 50 }, 3)
	local want = bestOf(made, 50, 3)
	local c3 = poor[3] and Creatures.byId[poor[3].sp]
	H.expect(idsOf(poor) == idsOf(want) and c3 ~= nil and c3.rarity == 1 and Creatures.byId[poor[1].sp].rarity == 2, "tide", "the best three: the best workers, the best one the shells cover last when they cover none of those", idsOf(poor))
	local rich = H.inClient(p, TideViewP.best, { tide = made, shells = 500 }, 3)
	local all = true
	for _, d in rich do
		all = all and Creatures.byId[d.sp].rarity == 2
	end
	H.expect(#rich == 3 and all and idsOf(rich) == idsOf(bestOf(made, 500, 3)), "tide", "and with the shells, simply the best three", idsOf(rich))
end
-- the HUD's tide card: the best three floating by, each with its name, its price and a bar of the time it has left
-- (running down); a tap on a price takes it in (the hut has room for one more), and it comes ashore to walk the island
prof.shells = math.max(prof.shells, 2000)
H.push(p, 0.4)
do
	E.runUntil(function()
		return tideSynced(p)
	end, 0.5)
	local v1 = H.view(p)
	local best3 = H.inClient(p, TideViewP.best, v1, 3)
	H.expect(idsOf(best3) == idsOf(bestOf(v1.tide, v1.shells, 3)), "tide", "TideView.best picks the best three workers floating by", idsOf(best3))
	local card = p.PlayerGui:FindFirstChild("TideCard", true)
	local rows, bars, cardRows = 0, 0, 0
	for _, d in best3 do
		local back = card and card:FindFirstChild("TideLeft_" .. d.id, true)
		local fill = back and back:FindFirstChild("Fill")
		if H.buttonNamed(p, "CardTake_" .. d.id) ~= nil and card:FindFirstChild("TideName_" .. d.id, true) then
			rows += 1
		end
		if fill then
			local w = math.floor((back.Size.X.Offset - 2) * (1 - TideL.along(d, E.now())) + 0.5)
			if math.abs(fill.Size.X.Offset - w) <= 1 then
				bars += 1
			end
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 9) == "CardTake_" then
			cardRows += 1
		end
	end
	H.expect(card ~= nil and H.guiVisible(card) and rows == #best3 and cardRows == #best3 and #best3 == 3, "tide", "the tide's card shows the best three floating by, with their names and prices", string.format("%d of %d, %d on the card", rows, #best3, cardRows))
	H.expect(bars == #best3, "tide", "each with a bar of the time it has left", string.format("%d of %d", bars, #best3))
	-- (the bar runs down: two seconds later the newest of them has less left)
	local d1 = best3[1]
	for _, d in best3 do
		if d.at > d1.at then
			d1 = d
		end
	end
	local function barOf(d)
		local c = p.PlayerGui:FindFirstChild("TideCard", true)
		local back = c and c:FindFirstChild("TideLeft_" .. d.id, true)
		local fill = back and back:FindFirstChild("Fill")
		return fill and fill.Size.X.Offset
	end
	local w1 = barOf(d1)
	E.run(2)
	local w2 = barOf(d1)
	H.expect(w1 == nil or w2 == nil or w2 < w1, "tide", "and it runs down", string.format("%s -> %s", tostring(w1), tostring(w2)))
	-- take one in from the card (one with a few seconds left)
	local pick = nil
	E.runUntil(function()
		pick = nil
		for _, d in H.inClient(p, TideViewP.best, H.view(p), 3) do
			if pick == nil and d.cost <= prof.shells and TideL.along(d, E.now()) < 0.75 and H.buttonNamed(p, "CardTake_" .. d.id) ~= nil then
				pick = d
			end
		end
		return pick ~= nil
	end, Tuning.TideLife, 0.1)
	H.expect(pick ~= nil, "tide", "one on the card with time left that the shells cover")
	if pick then
		local sh1, n0, t1, rate0 = prof.shells, #prof.pals, E.now(), Island.rates(prof).shells
		local fTaken = #fx
		H.clickNamed(p, "CardTake_" .. pick.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		H.expect(#prof.pals == n0 + 1 and prof.stats.taken == 2 and x.sp == pick.sp and paid(sh1, -pick.cost, t1, rate0), "tide", "a tap on its price on the tide's card takes it in for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(x.home == pieceOf("nest").uid and onTide(pick.id) == nil, "tide", "into the hut with room, gone from the tide", tostring(x.home))
		local takenFx = 0
		for i = fTaken + 1, #fx do
			if fx[i].kind == "taken" then
				takenFx += 1
			end
		end
		H.expect(takenFx == 1, "tide", "the client hears of it (Fx taken)", tostring(takenFx))
		E.runUntil(function()
			return H.inClient(p, WV.ownCount) == housedN()
		end, 3, 0.25)
		H.expect(H.inClient(p, WV.ownCount) == housedN() and housedN() == 2, "tide", "the one taken in walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
	end
end
-- the tide's panel from the card's Open: how often one comes in, the huts' room, the odds, and the best four floating
-- by with Take and the time they have left; it is rebuilt only when what it shows changes
H.clickNamed(p, "TideOpen", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tide", "tide", "Open on the tide's card opens the tide's panel", tostring(H.currentPanel(p)))
do
	local pg = p.PlayerGui
	local function panelKey()
		local v1 = H.view(p)
		local parts = {}
		for _, d in H.inClient(p, TideViewP.best, v1, 4) do
			table.insert(parts, string.format("%d:%d:%s", d.id, d.cost, if v1.shells >= d.cost then "y" else "n"))
		end
		return table.concat(parts, ",")
	end
	local function panelRows()
		local best4 = H.inClient(p, TideViewP.best, H.view(p), 4)
		local rows, all = 0, 0
		for _, d in best4 do
			local f = pg:FindFirstChild("Drift_" .. d.id, true)
			if f and H.buttonNamed(p, "PanelTake_" .. d.id) ~= nil and f:FindFirstChild("Left") then
				rows += 1
			end
		end
		for _, x in pg:GetDescendants() do
			if string.sub(x.Name, 1, 6) == "Drift_" then
				all += 1
			end
		end
		return rows, all, best4
	end
	local rows, all, best4 = panelRows()
	H.expect(#best4 == 4 and rows == 4 and all == 4, "tide", "the panel shows the best four floating by, each with Take and the time it has left", string.format("%d of %d, %d rows", rows, #best4, all))
	local v1 = H.view(p)
	local pace = pg:FindFirstChild("Pace", true)
	local paceWant = if math.abs(v1.tideSecs - 1) < 0.05 then "One floats by every second" else string.format("One floats by every %.1fs", v1.tideSecs)
	H.expect(pace ~= nil and pace.Text == paceWant and pg:FindFirstChild("Odds_1", true) ~= nil and pg:FindFirstChild("Odds_5", true) ~= nil and pg:FindFirstChild("Room", true) ~= nil, "tide", "its pace, the huts' room and the odds", pace and pace.Text)
	local head = pg:FindFirstChild("Jetty", true)
	H.expect(head ~= nil and head.Text == "Floating by" and pg:FindFirstChild("TideBar", true) == nil and pg:FindFirstChild("Leaving", true) == nil, "tide", "under Floating by (no bar to the next one, no Leaving soon)", head and head.Text)
	local card = pg:FindFirstChild("TideCard", true)
	H.expect(card == nil or not H.guiVisible(card), "tide", "the HUD's cards step aside for the wide panel")
	-- (while the best four stay the same, the panel keeps its rows: the tide moving every second doesn't rebuild it)
	local key0, row0 = panelKey(), pg:FindFirstChild("Drift_" .. best4[1].id, true)
	local views0 = views
	local held, steps = true, 0
	while steps < 40 do
		E.run(E.dt)
		if panelKey() ~= key0 then
			break
		end
		steps += 1
		held = held and row0.Parent ~= nil
	end
	if views == views0 and steps >= 10 then
		H.expect(held, "tide", "the panel isn't rebuilt while what it shows stays the same", string.format("%d steps", steps))
	else
		H.log("tide: the panel's rows changed too soon to see them held (%d steps, %d views)", steps, views - views0)
	end
	-- (and when they change, the panel follows)
	local key1 = panelKey()
	E.runUntil(function()
		return panelKey() ~= key1
	end, Tuning.TideLife + 1, E.dt)
	E.run(0.1)
	rows, all, best4 = panelRows()
	H.expect(rows == #best4 and all == #best4, "tide", "once they change, the panel shows the new best four", string.format("%d of %d, %d rows", rows, #best4, all))
end
-- every hut full: Take opens the swap picker instead; Swap sells the one picked and the new one takes its place
do
	local d = nil
	E.runUntil(function()
		d = nil
		for _, x in H.inClient(p, TideViewP.best, H.view(p), 4) do
			if d == nil and TideL.along(x, E.now()) < 0.7 and H.buttonNamed(p, "PanelTake_" .. x.id) ~= nil then
				d = x
			end
		end
		return d ~= nil
	end, Tuning.TideLife, 0.1)
	H.expect(d ~= nil, "tide", "one in the panel with time left")
	if d then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.clickNamed(p, "PanelTake_" .. d.id, { wait = 0.6 })
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0, "tide", "every hut full: Take takes nothing yet", string.format("%d driftlings", #prof.pals))
		H.expect(H.currentPanel(p) == "tide", "tide", "the tide's panel turns to the swap picker", tostring(H.currentPanel(p)))
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
		local sh1, sold0, hut, t1, rate0 = prof.shells, prof.stats.sold, weak.home, E.now(), Island.rates(prof).shells
		H.clickNamed(p, "SwapTake_" .. weak.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		H.expect(table.find(prof.pals, weak) == nil and prof.stats.sold == sold0 + 1 and prof.stats.taken == taken0 + 1, "tide", "Swap: the one picked is sold", string.format("sold %d, taken %d", prof.stats.sold, prof.stats.taken))
		H.expect(x.sp == d.sp and x.home == hut and #prof.pals == n0 and paid(sh1, price - d.cost, t1, rate0), "tide", "and the new one takes its place in the hut, paid less what the other sold for", string.format("%+.1f shells (cost %d, sold for %d)", prof.shells - sh1, d.cost, price))
		H.expect(H.currentPanel(p) == "tide" and H.buttonNamed(p, "SwapTake_" .. (prof.pals[1] and prof.pals[1].id or 0)) == nil, "tide", "the panel stays open, back on the ones floating by", tostring(H.currentPanel(p)))
	end
	H.closePanel(p)
end
-- a world price tag (one showing, the shells there): every hut full, the swap picker opens; when its driftling floats
-- off meanwhile, the picker gives way to the list and says so
do
	local d = nil
	E.runUntil(function()
		d = nil
		for _, e in tagState() do
			if d == nil and e.shown and e.d.cost <= prof.shells and e.k > 0.6 and e.k < 0.9 then
				d = e.d
			end
		end
		return d ~= nil
	end, Tuning.TideLife, 0.1)
	H.expect(d ~= nil and H.guiVisible(worldTag(d.id)), "tide", "a price tag shows over one floating past that the shells cover")
	if d then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.clickNamed(p, "TideTake_" .. d.id, { wait = 0.6 })
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0, "tide", "every hut full: a tap on the tag takes nothing yet", string.format("%d driftlings", #prof.pals))
		local hutPal = nil
		for _, x in prof.pals do
			if x.home ~= 0 and hutPal == nil then
				hutPal = x
			end
		end
		H.expect(H.currentPanel(p) == "tide" and hutPal ~= nil and H.buttonNamed(p, "SwapTake_" .. hutPal.id) ~= nil, "tide", "the tide's panel opens on the swap picker", tostring(H.currentPanel(p)))
		E.runUntil(function()
			return onTide(d.id) == nil
		end, Tuning.TideLife, E.dt)
		E.run(0.2)
		H.expect(onTide(d.id) == nil and H.currentPanel(p) == "tide" and hutPal ~= nil and H.buttonNamed(p, "SwapTake_" .. hutPal.id) == nil and p.PlayerGui:FindFirstChild("Pace", true) ~= nil, "tide", "it floats off: the picker gives way to the ones floating by", tostring(H.currentPanel(p)))
		H.expect(statusSays("That one has floated off."), "tide", "and says it has floated off")
	end
	H.closePanel(p)
end
-- not enough shells, or one that has floated off: refused, nothing changes
do
	local sh = prof.shells
	prof.shells = 0
	local d = cheapest()
	local n0 = #prof.pals
	res = H.req(p, "tide.take", { id = d.id, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "money" and #prof.pals == n0, "tide", "not enough shells", tostring(res.err))
	prof.shells = sh
	res = H.req(p, "tide.take", { id = goneId or 424242, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "not_found" and #prof.pals == n0, "tide", "one that has floated off past the island", string.format("%s (%s)", tostring(res.err), tostring(goneId)))
	res = H.req(p, "tide.take", { id = 424242, swap = 0 })
	H.expect(not res.ok and res.err == "not_found", "tide", "one that never came", tostring(res.err))
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
mirror(p, "tide")

------------------------------------------------------------------ 5. the Driftlings panel: moving, working, selling
E.phase = "pals"
-- a second hut, so there is somewhere to move one to
prof.wood = math.max(prof.wood, 200)
res = place("nest")
local hutA = pieceOf("nest")
local hutB = prof.plot.placed[#prof.plot.placed]
H.expect(res.ok and hutB.id == "nest" and hutB ~= hutA, "pals", "a second hut", tostring(res.err))
H.push(p, 0.4)
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
do
	local nPals, sold0, sh1, t1 = #prof.pals, prof.stats.sold, prof.shells, E.now()
	local price, rate0 = TideL.price(pal), Island.rates(prof).shells
	H.openPanel(p, "pals")
	E.run(0.3)
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.3 })
	H.expect(#prof.pals == nPals, "pals", "one tap only asks Sure?")
	H.clickNamed(p, "Sell_" .. pal.id, { wait = 0.5 })
	-- (the island earns meanwhile: its shells a second, a turn's rate over TurnSeconds, at the rate before the sale)
	local earned = earnedSince(t1, rate0)
	local got = prof.shells - sh1
	H.expect(#prof.pals == nPals - 1 and table.find(prof.pals, pal) == nil and prof.stats.sold == sold0 + 1 and got >= price - 0.5 and got <= price + earned, "pals", "the second sells it for its price", string.format("%d driftlings, %+.1f shells (price %d, the island's own %.1f at most)", #prof.pals, got, price, earned))
end
-- Tide beside the hint opens the tide's panel
H.openPanel(p, "pals")
H.clickNamed(p, "OpenTide", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tide", "pals", "Tide opens the tide's panel", tostring(H.currentPanel(p)))
H.closePanel(p)
H.checkProfile(p, "pals")
mirror(p, "pals")

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
mirror(p, "panels")

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
mirror(p, "quests")

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
expectRefused("a driftling not on the tide", ok, out, "not_found")
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
mirror(p, "malicious")

------------------------------------------------------------------ 9. a second player
E.phase = "second"
local q = H.addPlayer({ userId = 9102, name = "Byte" })
E.run(3)
local sq = H.session(q)
H.expect(sq ~= nil and sq.ready and sq.plot == 2, "second", "the second player gets island 2", tostring(sq and sq.plot))
H.expect(E.workspace.Plots:FindFirstChild("Plot_2") ~= nil, "second", "their island is built")
H.expect(H.cmod(q, "Controllers.CameraController").view().plot == 2, "second", "their camera frames their own island")
H.expect(housedN() > 0 and H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount) >= housedN(), "second", "the second client draws the first island's hut driftlings", string.format("%d of %d", H.inClient(q, H.cmod(q, "Controllers.WorldView").rigCount), housedN()))
-- both islands' tides float past on the second client too, each one where the first client puts it (both run them on
-- the server's time from the plot's Tide attribute); the first island's carry no price tags there
do
	local TVq = H.cmod(q, "Controllers.TideView")
	local UIKitQ = H.cmod(q, "UI.UIKit")
	E.runUntil(function()
		return H.inClient(q, TVq.count, 2) >= #sq.tide.list - 1 and H.inClient(q, TVq.count, 1) >= 1
	end, 2, 0.1)
	local n1, n2 = H.inClient(q, TVq.count, 1), H.inClient(q, TVq.count, 2)
	H.expect(n1 >= 1 and n2 >= #sq.tide.list - 1 and n2 <= #sq.tide.list + 2, "second", "the second client follows both islands' tides", string.format("island 1: %d, island 2: %d of %d", n1, n2, #sq.tide.list))
	local both, same, tagged = 0, true, 0
	local own = {}
	for _, d in sq.tide.list do
		own[d.id] = true
	end
	for _, d in s.tide.list do
		local xq, _, zq = H.inClient(q, TVq.where, 1, d.id)
		local xp, _, zp = H.inClient(p, TideViewP.where, 1, d.id)
		if xq and xp then
			both += 1
			same = same and math.abs(xq - xp) < 1e-6 and math.abs(zq - zp) < 1e-6
		end
		if not own[d.id] and H.inClient(q, function()
			return UIKitQ.canvas("World"):FindFirstChild("TideTake_" .. d.id, true)
		end) ~= nil then
			tagged += 1
		end
	end
	H.expect(both >= 1 and same, "second", "each of the first island's is at the same place on both clients", string.format("%d on both", both))
	H.expect(tagged == 0, "second", "and the first island's carry no price tags on the second client", tostring(tagged))
	local n = math.floor(TideL.life(sq.profile) / TideL.secs(sq.profile) + 1e-9)
	local okFirst, firsts = true, 0
	for _, d in sq.tide.list do
		local c = Creatures.byId[d.sp]
		if d.id % 3 == 1 then
			firsts += 1
			okFirst = okFirst and c ~= nil and c.rarity == 1 and (c.knack == "wood" or c.knack == "farm")
		end
	end
	H.expect(math.abs(#sq.tide.list - n) <= 1 and firsts >= 2 and okFirst, "second", "their own tide is running too, every third one a common good with wood or at a farm", string.format("%d of %d, %d firsts", #sq.tide.list, n, firsts))
end
H.checkProfile(q, "second")
mirror(q, "second")
H.checkProfile(p, "end")
mirror(p, "end")

report(E, H)
