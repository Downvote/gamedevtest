-- The main simulation: a new island end to end through the real client and its UI (the campfire, the sign, the Tree of
-- Life with its first lot of eggs round its roots, the HUD with the tree's card, the tips), building what the tips ask
-- in their order (a lumber camp, a veggie patch, a hut, then an egg hatched by tapping it, then a snack stall: the
-- starting wood and shells cover them; Build mode turns its tray to Work's Wood row, then Farms, Huts and Shops), the
-- tree in Build mode (moved like any piece, never cleared away), the days turning (the stores grow, every building
-- working a little with nobody at it), the tree's eggs (the plot's Eggs attribute, the ring every client lays them on,
-- the price tags and their rules, the card's best three and the time to the next lot, hatching from the card, a tag and
-- the panel, the swap picker when every hut is full, the picker going back to the list when a new lot replaced its egg,
-- a new lot every Tree.secs, a tap on the tree opening its panel), the Driftlings panel (moving one to a second hut and
-- back in a swap, Work, selling in two taps), the Index panel, the founder's looks, settings, expanding for wood (the
-- extra eggs laid at once, the cheer naming the new island), the build catalog (the tray's tabs and icons, each tab's
-- chips, Decor's 13 themes, the cards cheapest first with the locked ones after, a card's tooltip, the search box, each
-- tab's count), fences drawn through the UI (a line, a box, one over another, Erase), a river two tiles wide (its
-- tiles' banks in their model names) with a bridge over it and lily pads on it (refused on the grass, taken up with
-- their tile), decor put down with its effects (BuildFx's drop, Puffs' particles, with the pixel filter on for them),
-- Copy, Replace within the row, the keys R and Esc, the questline (Go on an old tab's name opening Work's row), then a
-- malicious client (the fences' and tiles' payloads among the rest), then a second player, then the first island grown
-- past Sunspire Capital to Driftling Haven (tier 10, Island max, land north of z -64, the pieces of tiers 7 to 10 built
-- up there). No villagers since 2026-11-12, no food since 2026-11-13, the Tree of Life's eggs in place of the tide
-- since 2026-11-13, the build catalog since 2026-11-13. Every check is an H.expect; the SIM REPORT must show 0 findings
-- and 0 errors.
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
local Traits = H.sharedServer("Data.Traits")
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Island = H.sharedServer("Logic.Island")
local Numbers = H.sharedServer("Logic.Numbers")
local TreeL = H.sharedServer("Logic.Tree")
local DecorModels = H.sharedServer("Models.DecorModels")

------------------------------------------------------------------ 1. a new island
E.phase = "join"
local p = H.addPlayer({ userId = 9101, name = "Pixel" })
E.run(1.5)
local fx = H.watchFx(p)
local s = H.session(p)
H.expect(s ~= nil and s.ready, "join", "the session is ready")
local prof = H.profile(p)
H.expect(prof.shells == Tuning.StartShells and prof.wood == Tuning.StartWood and prof.food == nil, "join", "the starting stores (wood and shells, no food)", string.format("%s %s %s", tostring(prof.shells), tostring(prof.wood), tostring(prof.food)))
H.expect(prof.tier == 1 and prof.tut == 1 and prof.folk == nil and #prof.plot.placed == 1 and prof.plot.placed[1].id == "tree" and prof.tree == nil, "join", "a new island, tips at step 1, no villagers, nothing built but its Tree of Life", string.format("%d pieces", #prof.plot.placed))
H.expect(s.plot == 1, "join", "the first player gets island 1", tostring(s.plot))
local plot1 = E.workspace:FindFirstChild("Plots") and E.workspace.Plots:FindFirstChild("Plot_1")
local static = plot1 and plot1:FindFirstChild("Static")
local land1 = static and static:FindFirstChild("Land")
H.expect(land1 ~= nil and land1:FindFirstChild("Land") ~= nil and static:FindFirstChild("Office") == nil, "join", "the island is built under Plots.Plot_1.Static.Land (no house)")
H.expect(land1 ~= nil and land1:FindFirstChild("FireStone", true) ~= nil and land1:FindFirstChild("PlotSign", true) ~= nil, "join", "its plaza's campfire and its sign")
H.expect(land1 ~= nil and land1:FindFirstChild("JettyPlank", true) == nil and land1:FindFirstChild("Mailbox", true) == nil and land1:FindFirstChild("Bound", true) == nil, "join", "no docks: no jetty, no mailbox, no coast walls (the founders swim)")
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
-- the Fx messages of `kind` the first player's client heard since the i0-th
local function fxSince(i0, kind)
	local out = {}
	for i = i0 + 1, #fx do
		if fx[i].kind == kind then
			table.insert(out, fx[i])
		end
	end
	return out
end
local UIKitP = H.cmod(p, "UI.UIKit")
local EggViewP = H.cmod(p, "Controllers.EggView")
local SCp = H.cmod(p, "Controllers.StateClient")
local PRp = H.cmod(p, "Pixel.PixelRenderer")
local WVp = H.cmod(p, "Controllers.WorldView")
-- the profile's egg `id` while it is still under the tree, or nil
local function eggOf(id)
	for _, e in prof.clutch.list do
		if e.id == id then
			return e
		end
	end
	return nil
end
local function idsOf(list)
	local out = {}
	for _, e in list do
		table.insert(out, tostring(e.id))
	end
	return table.concat(out, ",")
end
-- the eggs as the plot's Eggs attribute writes them: "id.rarity;..."
local function eggsAttr(list)
	local out = {}
	for _, e in list do
		table.insert(out, string.format("%d.%d", e.id, e.r))
	end
	return table.concat(out, ";")
end
-- the best n eggs, as the HUD's card picks them (GAME_DESIGN 6): the rarest first (the older of two the same), and if
-- the shells cover none of those, the best one they do in the last place
local function bestOf(list, shells, n)
	local sorted = table.clone(list)
	table.sort(sorted, function(a, b)
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
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
-- the view's eggs and the profile's are the same ones (a whole view reaches the client a frame after the server's change)
local function eggsSynced(pl)
	local v, pr = H.view(pl), H.profile(pl)
	return v ~= nil and pr ~= nil and type(v.clutch) == "table" and idsOf(v.clutch) == idsOf(pr.clutch.list)
end
local function mirror(pl, label)
	E.runUntil(function()
		return eggsSynced(pl)
	end, 0.5)
	H.checkMirror(pl, label)
end
-- the Tree of Life's piece on a profile's island
local function treePiece(pr)
	for _, q in (pr or prof).plot.placed do
		if q.id == "tree" then
			return q
		end
	end
	return nil
end
-- its middle on the lawn (world), as EggView finds it from its model
local function treeMiddle(plot, q)
	local ox, oz = Street.origin(plot)
	local w, d = Plot.footprint(q.id, q.rot)
	return E.v3(ox + q.x + w / 2, Street.LAWN_Y, oz + q.z + d / 2)
end
-- the tree's model on island `plot` (Static.Decor: "uid:tree:x:z:rot:stage"), or nil
local function treeModel(plot)
	local pm = E.workspace.Plots:FindFirstChild("Plot_" .. plot)
	local decor = pm and pm:FindFirstChild("Decor", true)
	for _, c in (decor and decor:GetChildren() or {}) do
		if c:GetAttribute("Decor") == "tree" then
			return c
		end
	end
	return nil
end
-- island `plot`'s eggs as client `pl` draws them (EggView.where): how many, whether each lies on the ring round the
-- tree's middle, on the lawn, and none on another's spot
local function ringState(pl, plot, list, q)
	local ev = H.cmod(pl, "Controllers.EggView")
	local mid = treeMiddle(plot, q)
	local drawn, onRing, apart = 0, true, true
	local spots = {}
	local clash = {}
	for _, e in list do
		local at = H.inClient(pl, ev.where, plot, e.id)
		if at then
			drawn += 1
			local dx, dz = at.X - mid.X, at.Z - mid.Z
			onRing = onRing and math.abs(math.sqrt(dx * dx + dz * dz) - DecorModels.EGG_RING) < 0.01 and math.abs(at.Y - Street.LAWN_Y) < 0.01
			for _, o in spots do
				if (at.X - o.at.X) ^ 2 + (at.Z - o.at.Z) ^ 2 <= 1 then
					apart = false
					table.insert(clash, string.format("%d/%d", o.id, e.id))
				end
			end
			table.insert(spots, { id = e.id, at = at })
		end
	end
	return drawn, onRing, apart, table.concat(clash, " ")
end
-- "m:ss", as the HUD and the panel write a time; and the seconds in such a text
local function clockOf(secs)
	local n = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", n // 60, n % 60)
end
local function secsIn(text)
	local m, ss = string.match(text or "", "(%d+):(%d%d)")
	return if m then tonumber(m) * 60 + tonumber(ss) else nil
end
-- the rarity an egg of rarity r hatches at the island's tier (one none of the open kinds has falls to the next commoner),
-- and whether that rarity has a kind of `knack`
local function hatchRarity(r)
	local pool = TreeL.pool(prof.tier)
	while r > 1 and #pool[r] == 0 do
		r -= 1
	end
	return r
end
local function hasKnack(r, knack)
	for _, sp in TreeL.pool(prof.tier)[hatchRarity(r)] do
		if Creatures.byId[sp].knack == knack then
			return true
		end
	end
	return false
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
-- the Tree of Life (GAME_DESIGN 6): every island has one behind the campfire, its model by its stage. Its first lot of
-- eggs is laid the moment the island wakes (Tree.count by the tier, the first two cheap commons on a new island), the
-- next lot Tree.secs away. The view carries the eggs with their prices; the HUD's tree card shows the time to the next
-- lot and the best three (EggView.best); EggView lays every egg on a ring round the tree, the price tags over them
local treeQ = treePiece()
do
	local model = treeModel(s.plot)
	H.expect(treeQ ~= nil and model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", treeQ.uid, treeQ.x, treeQ.z, treeQ.rot, TreeL.stage(prof.tier)), "join", "the tree's model on the island, named by its piece and its stage", model and model.Name)
	local c = prof.clutch
	local n = TreeL.count(prof.tier)
	H.expect(n == Tuning.EggCount[1] and #c.list == n and c.next == n + 1, "join", "its first lot laid at once: Tree.count(1) eggs round its roots", string.format("%d of %d, next %d", #c.list, n, c.next))
	local common = TreeL.cost(prof, 1)
	H.expect(#c.list >= 2 and c.list[1].r == 1 and c.list[2].r == 1 and common == Tuning.EggPrice[1] * Tuning.EggTier[1] and 2 * common <= Tuning.StartShells, "join", "the first two cheap commons the starting shells cover", eggsAttr(c.list))
	H.expect(math.abs(TreeL.secs(prof) - Tuning.EggSecs) < 1e-9 and c.left > TreeL.secs(prof) - 6 and c.left <= TreeL.secs(prof), "join", "the next lot Tree.secs (EggSecs) away", string.format("%.1f s of %.1f", c.left, TreeL.secs(prof)))
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list) and plot1:GetAttribute("Tide") == nil, "join", "the plot's Eggs attribute: each egg's id and rarity (no Tide)", tostring(plot1:GetAttribute("Eggs")))
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local v0 = H.view(p)
	local same = v0 ~= nil and #v0.clutch == #c.list
	for i, e in c.list do
		same = same and v0.clutch[i].id == e.id and v0.clutch[i].r == e.r and v0.clutch[i].cost == TreeL.cost(prof, e.r)
	end
	H.expect(same and v0.clutchSecs == TreeL.secs(prof) and math.abs(v0.clutchLeft - c.left) <= 1.1 and v0.tide == nil and v0.tideSecs == nil and v0.tree == nil and v0.penN == nil, "join", "the view carries the eggs with their prices, the time to the next lot and between two (no tide, no tree levels, no pen)", v0 and string.format("%d of %d, %s s, %s left", #v0.clutch, #c.list, tostring(v0.clutchSecs), tostring(v0.clutchLeft)))
	local left, secs = H.inClient(p, SCp.clutchLeft)
	H.expect(math.abs(left - c.left) < 0.6 and secs == TreeL.secs(prof), "join", "StateClient.clutchLeft: the server's time to the next lot, run down by the clock", string.format("%.2f vs %.2f, %s", left, c.left, tostring(secs)))
	local card = p.PlayerGui:FindFirstChild("TreeCard", true)
	local nextL = card and card:FindFirstChild("TreeNext", true)
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TreeOpen") ~= nil and card:FindFirstChild("TreeBar", true) ~= nil and nextL ~= nil, "join", "the HUD's Tree of Life card with Open, the time to the next lot and its bar")
	H.expect(nextL ~= nil and nextL.Text == "New eggs in " .. clockOf(left), "join", "its time to the next lot", nextL and nextL.Text)
	H.expect(p.PlayerGui:FindFirstChild("TideCard", true) == nil and H.buttonNamed(p, "TideOpen", true) == nil, "join", "(no tide card)")
	local best3 = H.inClient(p, EggViewP.best, v0, 3)
	local rows, cardRows, buys = 0, 0, 0
	for _, e in best3 do
		local price = card and card:FindFirstChild("CardPrice_" .. e.id, true)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if price and price:IsA("TextLabel") and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and price.Text == Numbers.coins(e.cost) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardPrice_" then
			cardRows += 1
		end
		if string.sub(x.Name, 1, 10) == "CardHatch_" then
			buys += 1
		end
	end
	H.expect(#best3 == 3 and idsOf(best3) == idsOf(bestOf(v0.clutch, v0.shells, 3)) and rows == #best3 and cardRows == #best3, "join", "the card shows the best three eggs, each with its egg, its rarity and its price", string.format("%s: %d rows, %d on the card", idsOf(best3), rows, cardRows))
	-- (the request of 2026-11-13: "the eggs should be buyable only after the player clicks on the tree or enters the tree
	-- menu": the card has no buy buttons, a tap on it opens the tree's panel)
	H.expect(buys == 0 and H.buttonNamed(p, "TreeCardTap") ~= nil, "join", "the card buys nothing itself: a tap on it opens the tree's panel", string.format("%d buy buttons", buys))
	-- (each egg rises out of the lawn, one after another)
	E.runUntil(function()
		return H.inClient(p, EggViewP.count, s.plot) == #c.list
	end, 3, 0.1)
	E.run(1.5)
	local drawn, onRing, apart, clash = ringState(p, s.plot, c.list, treeQ)
	H.expect(drawn == #c.list and H.inClient(p, EggViewP.count, s.plot) == #c.list and onRing and apart, "join", "EggView lays every egg on the ring round the tree, each on its own spot", string.format("%d drawn of %d, ring %s, on one spot: %s", drawn, #c.list, tostring(onRing), clash))
	local tags = H.inClient(p, function()
		local n = 0
		for _, d in UIKitP.canvas("World"):GetDescendants() do
			if string.sub(d.Name, 1, 9) == "EggHatch_" then
				n += 1
			end
		end
		return n
	end)
	H.expect(tags == 0, "join", "no price tags over the eggs (they are bought in the tree's panel)", tostring(tags))
	H.log("eggs: %s laid, %d drawn", eggsAttr(c.list), drawn)
	local named = H.inClient(p, function()
		for _, d in UIKitP.canvas("World"):GetDescendants() do
			if string.sub(d.Name, 1, 8) == "EggName_" then
				return true
			end
		end
		return false
	end)
	H.expect(not named, "join", "no names over the eggs (their spots show the rarity)")
	-- no hut yet: a tap on the card opens the tree's panel; Hatch there is refused (no_hut) and says why
	local e1 = nil
	for _, e in best3 do
		if e.cost <= prof.shells and (e1 == nil or e.cost < e1.cost) then
			e1 = e
		end
	end
	H.expect(e1 ~= nil, "join", "an egg on the card the starting shells cover")
	if e1 then
		local sh = prof.shells
		H.clickNamed(p, "TreeCardTap", { wait = 0.5 })
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "PanelHatch_" .. e1.id) ~= nil, "join", "a tap on the card opens the tree's panel, the egg there with its Hatch", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. e1.id, { wait = 0.5 })
		H.expect(#prof.pals == 0 and prof.shells == sh and eggOf(e1.id) ~= nil, "join", "no hut yet: hatching is refused, nothing paid, the egg still there", string.format("%d driftlings, %s shells", #prof.pals, tostring(prof.shells)))
		H.expect(statusSays("Build a hut first"), "join", "and the notice says to build a hut first")
		H.closePanel(p)
		local res = H.req(p, "egg.hatch", { id = e1.id, swap = 0 })
		H.expect(not res.ok and res.err == "no_hut", "join", "the server's word for it: no_hut", tostring(res.err))
	end
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
-- the card of the tip's building in the tray, marked to pulse (TutGoal), or nil
local function goalCard(id)
	local c = p.PlayerGui:FindFirstChild("Card_" .. id, true)
	return if c and c:GetAttribute("TutGoal") == true then c else nil
end
-- opens Build mode and says where the tray turned: its tab, its row and the tip's building
local function trayOn()
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	local st = H.inClient(p, BuildUI.debugState)
	return st, string.format("%s %s %s", tostring(st.tab), tostring(st.chip), tostring(st.goal))
end
H.expect(H.clickNamed(p, "Menu_build", { wait = 0.4 }) and BuildUI.isOpen(), "build", "Build mode opens")
local bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "work" and bst.chip == "wood" and bst.goal == "lumber" and goalCard("lumber") ~= nil, "build", "the first tip: the Work tab on its Wood row, the lumber camp's card pulsing", string.format("%s %s %s", tostring(bst.tab), tostring(bst.chip), tostring(bst.goal)))
H.expect(tipShown(), "build", "the tip's banner shows in Build mode")
H.clickNamed(p, "Tab_decor", { wait = 0.3 })
H.expect(H.inClient(p, BuildUI.debugState).tab == "decor", "build", "the player can still look round the other tabs")
H.expect(H.buttonNamed(p, "Buy_tree", true) == nil, "build", "no Tree of Life in the tray (every island has its one)")
local wood0, sh0 = prof.wood, prof.shells
local res = place("lumber")
E.run(0.5)
bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "work" and bst.chip == "farm" and bst.goal == "patch" and H.buttonNamed(p, "Buy_patch") ~= nil and goalCard("patch") ~= nil, "build", "the camp built: the tray turns to Work's Farms row and the veggie patch", string.format("%s %s %s", tostring(bst.tab), tostring(bst.chip), tostring(bst.goal)))
H.expect(tipShown(), "build", "the next tip's banner over the tray")
H.clickNamed(p, "BuildDone", { wait = 0.3 })
H.expect(not BuildUI.isOpen() and tipShown(), "build", "Done: the tray goes, the tip stays")
H.expect(res.ok and #prof.plot.placed == 2 and pieceOf("lumber") ~= nil, "build", "a lumber camp", tostring(res.err))
H.expect(math.abs(prof.wood - (wood0 - Buildings.byId.lumber.wood)) < 2 and math.abs(prof.shells - sh0) < 1, "build", "paid for in wood, no shells", string.format("wood %s -> %s, shells %s -> %s", wood0, prof.wood, sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to a farm (wood built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: the tips move on to a hut", tostring(res.err))
do
	E.run(0.3)
	local st, say = trayOn()
	H.expect(st.tab == "nest" and st.goal == "nest" and goalCard("nest") ~= nil, "build", "Build mode opens on the Huts tab for the hut tip, the hut's card pulsing", say)
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: the tips move on to hatching an egg", string.format("%s tut %d", tostring(res.err), prof.tut))
-- step 4: an egg hatched. A tap on an egg under the tree (EggView.tapAt: WorldView's taps ask it first) opens the tree's
-- panel and buys nothing (the request of 2026-11-13: "the eggs should be buyable only after the player clicks on the tree
-- or enters the tree menu"); Hatch there on the cheapest the shells cover plays the hatch scene (UI/HatchScene: the egg
-- floating, each tap revealing a step up or a mutation, the tap after them hatching it), one more goes back; what hatches (a new island's
-- first: good with wood) moves into the hut and goes to work at the lumber camp, and the panel is there again
local HSp = H.cmod(p, "UI.HatchScene")
do
	H.push(p, 0.3)
	H.expect(statusSays("The Tree of Life laid eggs round its roots. Tap the tree to pick one to hatch."), "build", "the tip asks for an egg hatched")
	-- (in the client: the cheapest such egg and the screen point in the middle of it, as a tap's position)
	local function target()
		local v = H.view(p)
		return H.inClient(p, function()
			local pick, pos = nil, nil
			for _, e in v.clutch do
				local at = EggViewP.where(s.plot, e.id)
				if at and (e.cost or math.huge) <= v.shells and Street.LAWN_Y - at.Y < 0.05 then
					local foot, on = PRp.project(at)
					local top = PRp.project(at + E.v3(0, 1.3, 0))
					if on and (pick == nil or e.cost < pick.cost) then
						pick, pos = e, E.v2(foot.X, (foot.Y + top.Y) / 2 - E.inset)
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
	end, 3, 0.1)
	H.expect(pick ~= nil and prof.shells >= pick.cost, "build", "an egg under the tree the starting shells cover, in view", pick and string.format("%s shells, it costs %d", tostring(prof.shells), pick.cost) or "none")
	if pick then
		local sh1, t1, rate0 = prof.shells, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.inClient(p, WVp.tapScreen, pos)
		E.run(0.6)
		H.expect(#prof.pals == 0 and eggOf(pick.id) ~= nil and H.currentPanel(p) == "tree", "build", "a tap on the egg opens the tree's panel and buys nothing", string.format("%d driftlings, panel %s", #prof.pals, tostring(H.currentPanel(p))))
		H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.3 })
		local hs = H.inClient(p, HSp.debugState)
		H.expect(hs.open and hs.r == pick.r and hs.hr == pick.r and H.currentPanel(p) == nil, "build", "Hatch: the hatch scene opens on the egg (the panel shut meanwhile; a new island's first never turns rarer)", string.format("open %s r %d hr %d", tostring(hs.open), hs.r, hs.hr))
		-- (the request of 2026-11-14: "make the player click to hatch the egg, each click revealing a mutation or a tier
		-- up upgrade if there is any, otherwise it just hatches": no blinds, the egg there at once)
		hs = H.inClient(p, HSp.debugState)
		H.expect(hs.phase == "egg" and hs.egg and not hs.pal, "build", "the egg floats there at once, waiting for a tap", string.format("phase %s", hs.phase))
		-- (then "make the egg rise up into view when it is being opened": it comes up from below, and a tap while it
		-- rises waits; the cracks crunch, Audio "crack", and the hatch breaks it open, "crack_open")
		H.expect(hs.lift < -0.5, "build", "it is still rising into view", string.format("%.2f studs under its spot at %.2f s", -hs.lift, hs.clock))
		local Aud = H.cmod(p, "Controllers.Audio")
		local crack0, open0 = H.inClient(p, Aud.playCount, "crack"), H.inClient(p, Aud.playCount, "crack_open")
		H.inClient(p, HSp.skip)
		E.run(0.05)
		local hsr = H.inClient(p, HSp.debugState)
		H.expect(hsr.left == hsr.reveals and not hsr.pal, "build", "a tap while it rises does nothing yet", string.format("%d of %d left", hsr.left, hsr.reveals))
		E.run(1)
		hs = H.inClient(p, HSp.debugState)
		H.expect(hs.lift == 0, "build", "it has risen to its spot", string.format("%.2f", hs.lift))
		local taps, revealed = 0, 0
		while not hs.pal and taps < 12 do
			H.inClient(p, HSp.skip)
			E.run(0.35)
			taps += 1
			local before = revealed
			hs = H.inClient(p, HSp.debugState)
			revealed = hs.reveals - hs.left
			if not hs.pal then
				H.expect(revealed == before + 1, "build", "a tap before it hatches reveals one step up or mutation", string.format("tap %d: %d revealed", taps, revealed))
			end
		end
		H.expect(hs.pal and taps == hs.reveals + 1, "build", "each tap reveals a step up or a mutation, the one after them hatches it", string.format("%d taps, %d reveals", taps, hs.reveals))
		local crack1, open1 = H.inClient(p, Aud.playCount, "crack"), H.inClient(p, Aud.playCount, "crack_open")
		H.expect(crack1 - crack0 == hs.reveals and open1 - open0 == 1, "build", "each reveal cracks it with a crunch, the hatch breaks it open with a sound", string.format("%d crunches for %d reveals, %d opens", crack1 - crack0, hs.reveals, open1 - open0))
		E.run(0.8)
		hs = H.inClient(p, HSp.debugState)
		local def0 = prof.pals[1] and Creatures.byId[prof.pals[1].sp]
		H.expect(hs.name == (def0 and def0.name) and hs.shown == math.max(1, hs.muts) and hs.phase == "done", "build", "its name under it, its mutations listed (or that it has none)", string.format("%q, %d of %d, %s", hs.name, hs.shown, hs.muts, hs.phase))
		H.inClient(p, HSp.skip)
		E.runUntil(function()
			return not H.inClient(p, HSp.debugState).open
		end, 4, 0.1)
		E.run(0.3)
		H.expect(not H.inClient(p, HSp.debugState).open and H.currentPanel(p) == "tree", "build", "a tap goes back to the island, the tree's panel there again", tostring(H.currentPanel(p)))
		local first = prof.pals[1]
		local c = first and Creatures.byId[first.sp]
		H.expect(#prof.pals == 1 and prof.stats.taken == 1 and paid(sh1, -pick.cost, t1, rate0), "build", "Hatch in the tree's panel hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r) and c.knack == "wood", "build", "a driftling of the egg's rarity, good with wood (a new island's first)", first and string.format("%s r%d", first.sp, pick.r))
		H.expect(eggOf(pick.id) == nil, "build", "and the egg is gone from under the tree")
		local hatched = fxSince(f1, "hatched")
		H.expect(#hatched == 1 and type(hatched[1].data) == "table" and hatched[1].data.egg == pick.id and hatched[1].data.sp == (first and first.sp), "build", "the client hears of it (Fx hatched)", tostring(#hatched))
		H.expect(statusSays("It hatched"), "build", "and says what hatched")
		H.closePanel(p)
		-- (from here on the scene ends at once: the hatches below test the rules and the panels, not the scene)
		H.inClient(p, HSp.setQuick, true)
		E.runUntil(function()
			return H.inClient(p, EggViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(H.inClient(p, EggViewP.where, s.plot, pick.id) == nil and H.inClient(p, EggViewP.count, s.plot) == #prof.clutch.list, "build", "its egg cracks open and is gone, the others stay", tostring(H.inClient(p, EggViewP.count, s.plot)))
		local hut = pieceOf("nest")
		H.expect(first ~= nil and hut ~= nil and first.home == hut.uid and first.work == pieceOf("lumber").uid, "build", "it moves into the hut and goes to work at the lumber camp", first and string.format("home %d work %d", first.home, first.work))
		H.expect(prof.tut == 5, "build", "the tips move on to a shop", tostring(prof.tut))
	end
end
do
	E.run(0.3)
	local st, say = trayOn()
	H.expect(st.tab == "work" and st.chip == "shop" and st.goal == "stall" and goalCard("stall") ~= nil, "build", "then on Work's Shops row for the shop tip, the stall's card pulsing", say)
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end
res = place("stall")
H.expect(res.ok and prof.tut == 6, "build", "a snack stall: the tips move on to the last", string.format("%s tut %d", tostring(res.err), prof.tut))
local tipWood = Buildings.byId.lumber.wood + Buildings.byId.patch.wood + Buildings.byId.nest.wood + Buildings.byId.stall.wood
H.expect(#prof.plot.placed == 5 and tipWood <= Tuning.StartWood and prof.wood >= 0, "build", "the starting wood paid for every building the tips ask for (beside the tree)", string.format("%d pieces, %d wood of %d, %.0f left", #prof.plot.placed, tipWood, Tuning.StartWood, prof.wood))
res = place("orchard")
H.expect(not res.ok and res.err == "locked", "build", "an orchard waits for a bigger island", tostring(res.err))
res = place("tent")
H.expect(not res.ok and res.err == "bad_payload", "build", "no homes to build any more (the Tent is gone)", tostring(res.err))
res = place("tree")
H.expect(not res.ok and res.err == "bad_payload", "build", "a second Tree of Life can't be bought", tostring(res.err))
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
H.expect(v ~= nil and #v.pieces == 5 and v.nests == 2 and v.beds == nil and v.pen == nil and v.folk == nil and v.food == nil, "build", "the view: four pieces and the tree, a hut's room for two (no beds, no pen, no food)", v and string.format("%d %d", #v.pieces, v.nests))
local decor = static and static:FindFirstChild("Decor")
H.expect(decor ~= nil and #decor:GetChildren() == 5, "build", "the server built a model a piece", tostring(decor and #decor:GetChildren()))
-- the tree in Build mode: tapped, it is picked up like any piece, but Clear away is off for it and nothing replaces it;
-- moved to another free spot, its model and its eggs go with it. The server refuses clearing it away too (fixed)
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	local q = treePiece()
	local ti = table.find(prof.plot.placed, q)
	local uid0 = q.uid
	local function screenOf(world)
		return H.inClient(p, function()
			local pos = PRp.project(world)
			return E.v2(pos.X, pos.Y - E.inset)
		end)
	end
	E.raycastParts = true
	H.inClient(p, BuildUI.tapScreen, screenOf(treeMiddle(s.plot, q) + E.v3(0, 2, 0)), false)
	E.raycastParts = nil
	E.run(0.3)
	local what = p.PlayerGui:FindFirstChild("What", true)
	H.expect(what ~= nil and what.Text == "Moving: Tree of Life" and H.buttonNamed(p, "Place") ~= nil, "build", "a tap on the tree picks it up to move", what and what.Text)
	H.expect(H.buttonNamed(p, "Store", true) ~= nil and H.buttonNamed(p, "Store") == nil and H.buttonNamed(p, "Replace", true) == nil, "build", "Clear away is off for it, and nothing replaces it")
	H.clickNamed(p, "Store", { includeDisabled = true, wait = 0.3 })
	H.expect(treePiece() == q and #prof.plot.placed == 5, "build", "(a tap on Clear away does nothing)")
	-- (a free spot a few cells off)
	local w, d = Plot.footprint("tree", q.rot)
	local pr = Street.plot(prof.tier)
	local tx, tz, best = nil, nil, math.huge
	for z = pr.z0, pr.z1 do
		for x = pr.x0, pr.x1 do
			local dd = (x - q.x) ^ 2 + (z - q.z) ^ 2
			if dd >= 4 and dd < best and Plot.fits(prof.tier, prof.plot.placed, "tree", x, z, q.rot, ti) then
				tx, tz, best = x, z, dd
			end
		end
	end
	H.expect(tx ~= nil, "build", "(a free spot for the tree)")
	if tx then
		local ox, oz = Street.origin(s.plot)
		H.inClient(p, BuildUI.tapScreen, screenOf(E.v3(ox + tx + w / 2, Street.LAWN_Y, oz + tz + d / 2)), false)
		E.run(0.2)
		H.clickNamed(p, "Place", { wait = 0.6 })
		H.expect(q.x == tx and q.z == tz and q.uid == uid0 and treePiece() == q, "build", "Move here: the tree moves, its uid kept", string.format("%d,%d (wanted %d,%d)", q.x, q.z, tx, tz))
		E.run(0.6)
		local model = treeModel(s.plot)
		H.expect(model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, TreeL.stage(prof.tier)), "build", "its model stands in its new place", model and model.Name)
		local drawn, onRing, apart, clash = ringState(p, s.plot, prof.clutch.list, q)
		H.expect(drawn == #prof.clutch.list and onRing and apart, "build", "and its eggs lie round it there", string.format("%d of %d, ring %s, on one spot: %s", drawn, #prof.clutch.list, tostring(onRing), clash))
	end
	H.clickNamed(p, "Cancel", { optional = true, wait = 0.2 })
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	res = H.req(p, "plot.store", { i = table.find(prof.plot.placed, q) })
	H.expect(not res.ok and res.err == "fixed" and treePiece() == q, "build", "the server won't clear the tree away (fixed)", tostring(res.err))
end
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
local ticks, treeTicks = 0, 0
for i = f0 + 1, #fx do
	if fx[i].kind == "tick" then
		ticks += 1
		if H.finite(fx[i].clutchLeft) and H.finite(fx[i].clutchSecs) and fx[i].clutchSecs > 0 and fx[i].tideSecs == nil and fx[i].tideT == nil and fx[i].grow == nil and fx[i].food == nil then
			treeTicks += 1
		end
	end
end
H.expect(ticks >= math.floor(E.now() - t0) - 3, "days", "the stores reach the client every second (Fx tick)", string.format("%d ticks in %.1f s", ticks, E.now() - t0))
H.expect(treeTicks == ticks, "days", "each tick carries the time to the tree's next eggs and the time between two (no tide, no food)", string.format("%d of %d", treeTicks, ticks))
do
	local left = H.inClient(p, SCp.clutchLeft)
	H.expect(math.abs(left - prof.clutch.left) < 0.6, "days", "the client's time to the next lot keeps up with the server's", string.format("%.2f vs %.2f", left, prof.clutch.left))
end
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

------------------------------------------------------------------ 4. the Tree of Life's eggs (GAME_DESIGN 6)
E.phase = "tree"
-- the cheapest egg under the tree (that `ok` likes), or nil
local function cheapestEgg(ok)
	local best = nil
	for _, e in prof.clutch.list do
		if (ok == nil or ok(e)) and (best == nil or TreeL.cost(prof, e.r) < TreeL.cost(prof, best.r)) then
			best = e
		end
	end
	return best
end
-- the hut driftling the swap picker lists first: the weakest worker
local function weakest()
	local weak = nil
	for _, x in prof.pals do
		if x.home ~= 0 and (weak == nil or TreeL.better(weak, x)) then
			weak = x
		end
	end
	return weak
end
-- a fishing pier, so every kind of the first island's driftlings has a building of its knack to work at
prof.wood = math.max(prof.wood, 400)
res = place("pier")
H.expect(res.ok, "tree", "a fishing pier", tostring(res.err))
-- EggView.best's rule on made-up eggs: three uncommons the shells don't cover and two commons they do; the uncommons
-- first, the older first, and the older common in the last place. With the shells, the three uncommons
do
	local made = {
		{ id = 1, r = 2, cost = 90 },
		{ id = 2, r = 1, cost = 20 },
		{ id = 3, r = 2, cost = 90 },
		{ id = 4, r = 1, cost = 20 },
		{ id = 5, r = 2, cost = 90 },
	}
	local poor = H.inClient(p, EggViewP.best, { clutch = made, shells = 50 }, 3)
	H.expect(idsOf(poor) == "1,3,2" and idsOf(poor) == idsOf(bestOf(made, 50, 3)), "tree", "the best three: the rarest, the best one the shells cover last when they cover none of those", idsOf(poor))
	local rich = H.inClient(p, EggViewP.best, { clutch = made, shells = 500 }, 3)
	H.expect(idsOf(rich) == "1,3,5" and idsOf(rich) == idsOf(bestOf(made, 500, 3)), "tree", "and with the shells, simply the rarest three", idsOf(rich))
end
-- the HUD's tree card: the best three eggs, each with its egg, its rarity's name and its price; over them the time to the
-- next lot, counting down, with a bar running down beside it. A tap on the card opens the tree's panel, where Hatch
-- hatches an egg (the hut has room for one more), and what hatches walks the island
prof.shells = math.max(prof.shells, 2000)
H.push(p, 0.4)
do
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local v1 = H.view(p)
	local best3 = H.inClient(p, EggViewP.best, v1, 3)
	H.expect(idsOf(best3) == idsOf(bestOf(v1.clutch, v1.shells, 3)), "tree", "EggView.best picks the rarest three under the tree", idsOf(best3))
	local card = p.PlayerGui:FindFirstChild("TreeCard", true)
	local rows, cardRows = 0, 0
	for _, e in best3 do
		local price = card and card:FindFirstChild("CardPrice_" .. e.id, true)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if price and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and price.Text == Numbers.coins(e.cost) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardPrice_" then
			cardRows += 1
		end
	end
	H.expect(card ~= nil and H.guiVisible(card) and #best3 == math.min(3, #v1.clutch) and rows == #best3 and cardRows == #best3, "tree", "the tree's card shows them, each with its rarity and its price", string.format("%d of %d, %d on the card", rows, #best3, cardRows))
	local function nextText()
		local c = p.PlayerGui:FindFirstChild("TreeCard", true)
		local t = c and c:FindFirstChild("TreeNext", true)
		return t and t.Text
	end
	local left, secs = H.inClient(p, SCp.clutchLeft)
	local text1 = nextText()
	H.expect(text1 == "New eggs in " .. clockOf(left) and math.abs(left - prof.clutch.left) < 0.6, "tree", "the time to the next lot on the card", string.format("%s (%.1f s on the server)", tostring(text1), prof.clutch.left))
	local back = card and card:FindFirstChild("TreeBar", true)
	local fill = back and back:GetChildren()[1]
	local want = back and math.floor((back.Size.X.Offset - 2) * math.clamp(left / math.max(1, secs), 0, 1) + 0.5)
	H.expect(fill ~= nil and math.abs(fill.Size.X.Offset - want) <= 1, "tree", "its bar as long as the time left", string.format("%s of %s", tostring(fill and fill.Size.X.Offset), tostring(want)))
	local w1 = fill and fill.Size.X.Offset
	E.run(3)
	local text2 = nextText()
	local down = (secsIn(text1) or 0) - (secsIn(text2) or 0)
	H.expect(down >= 2 and down <= 4, "tree", "and it counts down", string.format("%s -> %s", tostring(text1), tostring(text2)))
	card = p.PlayerGui:FindFirstChild("TreeCard", true)
	back = card and card:FindFirstChild("TreeBar", true)
	fill = back and back:GetChildren()[1]
	H.expect(fill ~= nil and w1 ~= nil and fill.Size.X.Offset <= w1, "tree", "the bar with it", string.format("%s -> %s", tostring(w1), tostring(fill and fill.Size.X.Offset)))
	-- hatch one: a tap on the card opens the panel, Hatch there
	local pick = nil
	for _, e in H.inClient(p, EggViewP.best, H.view(p), 3) do
		if e.cost <= prof.shells and card and card:FindFirstChild("CardPrice_" .. e.id, true) ~= nil and (pick == nil or e.cost < pick.cost) then
			pick = e
		end
	end
	H.expect(pick ~= nil, "tree", "an egg on the card the shells cover")
	if pick then
		local sh1, n0, t1, rate0 = prof.shells, #prof.pals, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.clickNamed(p, "TreeCardTap", { wait = 0.4 })
		H.expect(H.currentPanel(p) == "tree" and #prof.pals == n0, "tree", "a tap on the card opens the tree's panel, nothing bought", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		local c = x and Creatures.byId[x.sp]
		H.expect(#prof.pals == n0 + 1 and prof.stats.taken == 2 and paid(sh1, -pick.cost, t1, rate0), "tree", "Hatch in the panel hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(H.currentPanel(p) == "tree", "tree", "and the panel is there again after the hatch scene", tostring(H.currentPanel(p)))
		H.closePanel(p)
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r) and (c.knack == "farm" or not hasKnack(pick.r, "farm")), "tree", "a driftling of the egg's rarity (a new island's second: good at a farm)", x and string.format("%s r%d", x.sp, pick.r))
		H.expect(x.home == pieceOf("nest").uid and eggOf(pick.id) == nil, "tree", "into the hut with room, the egg gone from under the tree", tostring(x.home))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
		H.expect(#hatched == 1 and type(data) == "table" and data.egg == pick.id and data.id == x.id and data.r == pick.r and data.hr == pick.r and data.cost == pick.cost and data.sold == 0 and data.swapped == 0, "tree", "the client hears of it (Fx hatched: the egg, what hatched, its price; the tips' second never turns rarer)", tostring(#hatched))
		local function onCard(id)
			local cd = p.PlayerGui:FindFirstChild("TreeCard", true)
			return cd ~= nil and cd:FindFirstChild("CardPrice_" .. id, true) ~= nil
		end
		E.runUntil(function()
			return not onCard(pick.id) and H.inClient(p, EggViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list) and not onCard(pick.id), "tree", "gone from the plot's Eggs attribute and from the card", tostring(plot1:GetAttribute("Eggs")))
		H.expect(H.inClient(p, EggViewP.where, s.plot, pick.id) == nil, "tree", "its egg cracks open under the tree and is gone")
		E.runUntil(function()
			return H.inClient(p, WV.ownCount) == housedN()
		end, 3, 0.25)
		H.expect(H.inClient(p, WV.ownCount) == housedN() and housedN() == 2, "tree", "what hatched walks the island", string.format("%d drawn, %d in huts", H.inClient(p, WV.ownCount), housedN()))
	end
end
-- the tree's panel from the card's Open: how often it lays and the time to the next lot with its bar, how many eggs a
-- lot and the huts' room, the odds, and under the tree every egg with Hatch, the rarest first
H.clickNamed(p, "TreeOpen", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "tree", "Open on the tree's card opens the tree's panel", tostring(H.currentPanel(p)))
local function panelRows()
	local pg = p.PlayerGui
	local v1 = H.view(p)
	local rows, all = 0, 0
	for _, e in v1.clutch do
		local f = pg:FindFirstChild("Egg_" .. e.id, true)
		local name = f and f:FindFirstChild("Name")
		local b = H.buttonNamed(p, "PanelHatch_" .. e.id, true)
		if f and name and name.Text == Traits.RARITY[e.r].name .. " egg" and b and table.find(H.textsOf(b), Numbers.coins(e.cost)) then
			rows += 1
		end
	end
	for _, x in pg:GetDescendants() do
		if string.sub(x.Name, 1, 4) == "Egg_" then
			all += 1
		end
	end
	return rows, all, #v1.clutch
end
do
	local pg = p.PlayerGui
	local v1 = H.view(p)
	local pace = pg:FindFirstChild("Pace", true)
	local body = pace and pace.Parent
	local nxt = body and body:FindFirstChild("Next")
	local room = body and body:FindFirstChild("Room")
	H.expect(pace ~= nil and pace.Text == "New eggs every " .. clockOf(v1.clutchSecs) and v1.clutchSecs == TreeL.secs(prof), "tree", "how often it lays", pace and pace.Text)
	local left = H.inClient(p, SCp.clutchLeft)
	H.expect(nxt ~= nil and nxt.Text == "Next in " .. clockOf(left) and body:FindFirstChild("TreeBar") ~= nil, "tree", "the time to the next lot and its bar", nxt and nxt.Text)
	H.expect(room ~= nil and room.Text == string.format("%d eggs a lot. In huts %d/%d", TreeL.count(prof.tier), housedN(), v1.nests), "tree", "how many eggs a lot and the huts' room", room and room.Text)
	local odds = 0
	for k = 1, 5 do
		local o = body and body:FindFirstChild("Odds_" .. k)
		if o and o.Text == Traits.RARITY[k].name then
			odds += 1
		end
	end
	H.expect(odds == 5, "tree", "the odds of each rarity", tostring(odds))
	local head = body and body:FindFirstChild("Eggs")
	H.expect(head ~= nil and head.Text == "Under the tree" and body:FindFirstChild("Jetty") == nil, "tree", "under the tree", head and head.Text)
	local rows, all, n = panelRows()
	H.expect(n == #prof.clutch.list and rows == n and all == n, "tree", "every egg under the tree with its rarity and Hatch at its price", string.format("%d of %d, %d rows", rows, n, all))
	local card = pg:FindFirstChild("TreeCard", true)
	H.expect(card == nil or not H.guiVisible(card), "tree", "the HUD's cards step aside for the wide panel")
end
H.closePanel(p)
-- every hut full: an egg tapped under the tree opens the tree's panel; Hatch there opens the swap picker; Swap sells
-- the one picked and what hatches takes its place
do
	local e, pos = nil, nil
	E.runUntil(function()
		local v = H.view(p)
		e, pos = H.inClient(p, function()
			local pick, at2 = nil, nil
			for _, x in v.clutch do
				local at = EggViewP.where(s.plot, x.id)
				if at and (x.cost or math.huge) <= v.shells and Street.LAWN_Y - at.Y < 0.05 then
					local foot, on = PRp.project(at)
					local top = PRp.project(at + E.v3(0, 1.3, 0))
					if on and pick == nil then
						pick, at2 = x, E.v2(foot.X, (foot.Y + top.Y) / 2 - E.inset)
					end
				end
			end
			return pick, at2
		end)
		return e ~= nil
	end, 3, 0.1)
	H.expect(e ~= nil, "tree", "an egg in view under the tree the shells cover")
	if e then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.inClient(p, WVp.tapScreen, pos)
		E.run(0.5)
		H.expect(H.currentPanel(p) == "tree" and #prof.pals == n0, "tree", "a tap on the egg opens the tree's panel", tostring(H.currentPanel(p)))
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0 and eggOf(e.id) ~= nil, "tree", "every hut full: Hatch hatches nothing yet", string.format("%d driftlings", #prof.pals))
		local pg = p.PlayerGui
		local rows = 0
		for _, x in prof.pals do
			if x.home ~= 0 and pg:FindFirstChild("SwapOut_" .. x.id, true) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil then
				rows += 1
			end
		end
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "Back") ~= nil and pg:FindFirstChild("Pace", true) == nil, "tree", "the tree's panel opens on the swap picker", tostring(H.currentPanel(p)))
		H.expect(rows == housedN(), "tree", "the picker lists every hut driftling with Swap", string.format("%d of %d", rows, housedN()))
		local weak = weakest()
		local price = TreeL.price(weak)
		local sh1, sold0, hut, t1, rate0 = prof.shells, prof.stats.sold, weak.home, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.clickNamed(p, "SwapTake_" .. weak.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		local c = x and Creatures.byId[x.sp]
		H.expect(table.find(prof.pals, weak) == nil and prof.stats.sold == sold0 + 1 and prof.stats.taken == taken0 + 1, "tree", "Swap: the one picked is sold", string.format("sold %d, taken %d", prof.stats.sold, prof.stats.taken))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
		H.expect(c ~= nil and type(data) == "table" and data.hr >= e.r and c.rarity == hatchRarity(data.hr) and x.home == hut and #prof.pals == n0 and eggOf(e.id) == nil and paid(sh1, price - e.cost, t1, rate0), "tree", "and what hatches (of the rarity it hatched as) takes its place in the hut, paid less what the other sold for", string.format("%+.1f shells (cost %d, sold for %d)", prof.shells - sh1, e.cost, price))
		H.expect(#hatched == 1 and type(data) == "table" and data.egg == e.id and data.swapped == weak.id and data.sold == price, "tree", "the client hears of the swap (Fx hatched: the one swapped out and what it sold for)", tostring(#hatched))
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "SwapTake_" .. (prof.pals[1] and prof.pals[1].id or 0)) == nil and pg:FindFirstChild("Pace", true) ~= nil, "tree", "the panel stays open, back on the eggs", tostring(H.currentPanel(p)))
	end
	H.closePanel(p)
end
-- the panel's Hatch with every hut full opens the picker too. Then the tree lays a new lot (its time cut short on the
-- server): Tree.count new eggs, the ones left gone, the next lot Tree.secs away (Fx eggs and a whole view), and the
-- picker's egg is gone, so it gives way to the list and says so. EggView sinks the old eggs and raises the new ones
local oldEgg = nil
do
	H.openPanel(p, "tree")
	local e = cheapestEgg(function(x)
		return TreeL.cost(prof, x.r) <= prof.shells and H.buttonNamed(p, "PanelHatch_" .. x.id) ~= nil
	end)
	H.expect(e ~= nil, "tree", "an egg in the panel the shells cover")
	if e then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
		local hutPal = weakest()
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0 and H.currentPanel(p) == "tree" and hutPal ~= nil and H.buttonNamed(p, "SwapTake_" .. hutPal.id) ~= nil, "tree", "every hut full: Hatch in the panel opens the swap picker", tostring(H.currentPanel(p)))
		local old = {}
		for _, x in prof.clutch.list do
			old[x.id] = true
		end
		oldEgg = e.id
		local next0 = prof.clutch.next
		local f1 = #fx
		prof.clutch.left = 2
		E.run(1.5)
		H.expect(eggOf(e.id) ~= nil and #fxSince(f1, "eggs") == 0, "tree", "no new lot before its time")
		E.runUntil(function()
			return #fxSince(f1, "eggs") > 0
		end, 2, E.dt)
		E.run(0.3)
		local c = prof.clutch
		local fresh = #c.list == TreeL.count(prof.tier)
		for _, x in c.list do
			fresh = fresh and not old[x.id] and x.id >= next0
		end
		H.expect(fresh and c.next == next0 + #c.list, "tree", "when its time comes the tree lays a new lot: Tree.count new eggs, the ones left gone", string.format("%s (next %d)", eggsAttr(c.list), c.next))
		H.expect(math.abs(c.left - TreeL.secs(prof)) < 0.5, "tree", "the next lot Tree.secs away", string.format("%.1f of %.1f", c.left, TreeL.secs(prof)))
		local laid = fxSince(f1, "eggs")
		local vw = TreeL.view(prof)
		local same = #laid == 1 and laid[1].more == 0 and type(laid[1].laid) == "table" and #laid[1].laid == #vw
		if same then
			for i, x in vw do
				local y = laid[1].laid[i]
				same = same and type(y) == "table" and y.id == x.id and y.r == x.r and y.cost == x.cost
			end
		end
		H.expect(same, "tree", "the client hears of it (Fx eggs: the new lot with its prices)", tostring(#laid))
		H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list), "tree", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
		E.runUntil(function()
			return eggsSynced(p)
		end, 0.5)
		H.expect(eggsSynced(p), "tree", "a whole view brings the new lot to the client")
		E.run(0.3)
		H.expect(H.currentPanel(p) == "tree" and H.buttonNamed(p, "SwapTake_" .. hutPal.id) == nil and p.PlayerGui:FindFirstChild("Pace", true) ~= nil, "tree", "the picker's egg gone, it gives way to the eggs under the tree", tostring(H.currentPanel(p)))
		H.expect(statusSays("That egg is gone. The tree laid new ones."), "tree", "and says the egg is gone")
		local rows, all, n = panelRows()
		H.expect(rows == n and all == n and n == #c.list, "tree", "the panel lists the new lot", string.format("%d of %d, %d rows", rows, n, all))
		E.run(1.5)
		local oldDrawn = 0
		for id in old do
			if H.inClient(p, EggViewP.where, s.plot, id) ~= nil then
				oldDrawn += 1
			end
		end
		local drawn, onRing, apart, clash = ringState(p, s.plot, c.list, treePiece())
		H.expect(oldDrawn == 0 and drawn == #c.list and H.inClient(p, EggViewP.count, s.plot) == #c.list and onRing and apart, "tree", "the old eggs sink into the lawn, the new ones rise on the ring", string.format("%d old left, %d of %d new, ring %s, on one spot: %s", oldDrawn, drawn, #c.list, tostring(onRing), clash))
	end
	H.closePanel(p)
end
-- not enough shells, an egg of a lot gone, one never laid: refused, nothing changes
do
	local sh = prof.shells
	prof.shells = 0
	local e = cheapestEgg()
	local n0 = #prof.pals
	res = H.req(p, "egg.hatch", { id = e.id, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "money" and #prof.pals == n0 and eggOf(e.id) ~= nil, "tree", "not enough shells", tostring(res.err))
	prof.shells = sh
	res = H.req(p, "egg.hatch", { id = oldEgg or 424242, swap = prof.pals[1].id })
	H.expect(not res.ok and res.err == "not_found" and #prof.pals == n0, "tree", "an egg of the lot the new one replaced", string.format("%s (%s)", tostring(res.err), tostring(oldEgg)))
	res = H.req(p, "egg.hatch", { id = 424242, swap = 0 })
	H.expect(not res.ok and res.err == "not_found", "tree", "an egg never laid", tostring(res.err))
end
-- a tap on the own Tree of Life in the world opens its panel
do
	local n0 = #prof.pals
	E.raycastParts = true
	H.inClient(p, function()
		local pos = PRp.project(treeMiddle(s.plot, treePiece()) + E.v3(0, 2, 0))
		WVp.tapScreen(E.v2(pos.X, pos.Y - E.inset))
	end)
	E.raycastParts = nil
	E.run(0.5)
	H.expect(H.currentPanel(p) == "tree" and p.PlayerGui:FindFirstChild("Pace", true) ~= nil and H.buttonNamed(p, "Back") == nil and #prof.pals == n0, "tree", "a tap on the tree opens its panel (on its eggs, no egg hatched)", tostring(H.currentPanel(p)))
	H.closePanel(p)
end
-- the Index: every kind hatched counts
do
	local seen = 0
	for _, n in prof.seen do
		if n >= 1 then
			seen += 1
		end
	end
	H.push(p, 0.3)
	H.openPanel(p, "index")
	H.expect(statusSays(string.format("Seen %d of %d kinds", seen, #Creatures.list)), "tree", "the Index counts every kind hatched", string.format("%d seen", seen))
	H.closePanel(p)
end
H.checkProfile(p, "tree")
mirror(p, "tree")

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
do
	local b = H.buttonNamed(p, "OpenTree")
	H.expect(b ~= nil and table.find(H.textsOf(b), "Eggs") and H.buttonNamed(p, "OpenTide", true) == nil and H.buttonNamed(p, "EquipBest", true) == nil, "pals", "Eggs beside the hint (no Tide, no Equip best)")
end
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
-- Work: the work picker (every workplace, whatever its knack, its speed at each, and Rest); Rest, then back to work
do
	local job = pal.work
	H.clickNamed(p, "Help_" .. pal.id, { wait = 0.4 })
	H.expect(H.buttonNamed(p, "Go_0") ~= nil and H.buttonNamed(p, "Go_" .. job, true) ~= nil, "pals", "Work opens the work picker (its building, Rest)")
	local listed, n = true, 0
	for _, q in prof.plot.placed do
		if Island.works(q.id) then
			n += 1
			listed = listed and H.buttonNamed(p, "Go_" .. q.uid, true) ~= nil
		end
	end
	local speed = p.PlayerGui:FindFirstChild("Speed", true)
	H.expect(listed and n >= 3, "pals", "the work picker lists every workplace, whatever its knack", tostring(n))
	H.expect(speed ~= nil and string.match(speed.Text, "^x%d+%.%d$") ~= nil, "pals", "with how fast it works at each", speed and speed.Text)
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
-- back in a swap: one more hatched from the tree's panel fills the first hut again, so it swaps with one living there
do
	prof.shells = math.max(prof.shells, 2000)
	H.push(p, 0.3)
	H.openPanel(p, "tree")
	local e = cheapestEgg(function(x)
		return H.buttonNamed(p, "PanelHatch_" .. x.id) ~= nil
	end)
	local n0 = #prof.pals
	if e then
		H.clickNamed(p, "PanelHatch_" .. e.id, { wait = 0.6 })
	end
	local x = prof.pals[#prof.pals]
	H.expect(e ~= nil and #prof.pals == n0 + 1 and x.home == hutA.uid and eggOf(e.id) == nil, "pals", "one more hatched from Hatch in the tree's panel, into the first hut (the comfiest with room)", string.format("%d driftlings, home %d", #prof.pals, x.home))
	H.expect(H.currentPanel(p) == "tree" and p.PlayerGui:FindFirstChild("Pace", true) ~= nil, "pals", "(the panel stays open on the eggs)", tostring(H.currentPanel(p)))
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
	local price, rate0 = TreeL.price(pal), Island.rates(prof).shells
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
-- Eggs beside the hint opens the tree's panel
H.openPanel(p, "pals")
H.clickNamed(p, "OpenTree", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "pals", "Eggs opens the tree's panel", tostring(H.currentPanel(p)))
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
for _, name in { "pals", "tree", "hatch", "index", "looks" } do
	H.openPanel(p, name)
	E.run(0.3)
	H.expect(H.currentPanel(p) == name, "panels", name .. " opens")
end
H.closePanel(p)
H.openPanel(p, "tide")
H.expect(H.currentPanel(p) == nil, "panels", "no tide panel any more", tostring(H.currentPanel(p)))
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
-- (the eggs before: a bigger island lays more)
local eggs0, eggIds0, fEggs = #prof.clutch.list, {}, #fx
for _, e in prof.clutch.list do
	eggIds0[e.id] = true
end
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
H.expect(statusSays("Your island grew into " .. H.sharedServer("Data.Office").plan(2).name .. "."), "panels", "and names the island it grew into (tier 2's)")
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
-- a bigger island lays more eggs: the extra ones at once (Fx eggs saying how many more), the ones there kept, each
-- priced by the bigger island (EggTier); the tree's model grows to its next stage
do
	local c = prof.clutch
	local kept = true
	for id in eggIds0 do
		kept = kept and eggOf(id) ~= nil
	end
	H.expect(#c.list == TreeL.count(2) and TreeL.count(2) == Tuning.EggCount[2] and TreeL.count(2) > eggs0 and kept, "panels", "the tree lays its extra eggs at once, the ones there kept", string.format("%d -> %d of %d", eggs0, #c.list, TreeL.count(2)))
	local laid = fxSince(fEggs, "eggs")
	H.expect(#laid == 1 and laid[1].more == TreeL.count(2) - eggs0 and type(laid[1].laid) == "table" and #laid[1].laid == #c.list, "panels", "the client hears of it (Fx eggs: how many more)", string.format("%d fx, more %s", #laid, tostring(laid[1] and laid[1].more)))
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(c.list), "panels", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
	E.runUntil(function()
		return eggsSynced(p)
	end, 0.5)
	local _, _, off = TreeL.hutFx(prof)
	local priced = true
	for _, e in H.view(p).clutch do
		priced = priced and e.cost == math.max(1, math.floor(Tuning.EggPrice[e.r] * Tuning.EggTier[2] * (1 - off) + 0.5))
	end
	H.expect(priced, "panels", "each egg priced by the bigger island (EggPrice x EggTier[2])")
	local q = treePiece()
	local model = treeModel(s.plot)
	H.expect(TreeL.stage(2) == Tuning.TreeStage[2] and model ~= nil and model.Name == string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, TreeL.stage(2)), "panels", "the tree's model at its next stage", model and model.Name)
	E.runUntil(function()
		return H.inClient(p, EggViewP.count, s.plot) == #c.list
	end, 2, 0.1)
	E.run(1.5)
	local drawn, onRing, apart, clash = ringState(p, s.plot, c.list, q)
	H.expect(drawn == #c.list and onRing and apart, "panels", "EggView lays the extra eggs on the ring too, each on its own spot", string.format("%d of %d, ring %s, on one spot: %s", drawn, #c.list, tostring(onRing), clash))
end
-- the huts' limit by the island's tier (Tuning.HutLimit; GAME_DESIGN 4): huts up to it, one more refused (huts); in Build
-- mode the Huts tab counts the huts out of the limit and the hut cards say No room, while the other tabs' count leaves
-- the Tree of Life out; a bigger hut still replaces a small one at the limit. The huts added go again after
do
	prof.wood = math.max(prof.wood, 3000)
	local most = Plot.hutLimit(prof.tier)
	local added = {}
	local placedOk = most == Tuning.HutLimit[2] and Plot.huts(prof.plot.placed) < most
	while placedOk and Plot.huts(prof.plot.placed) < most do
		-- (the first where a bigger hut fits in its place)
		local bx, bz = spot("burrow", 0)
		res = if #added == 0 and bx then H.req(p, "plot.place", { id = "nest", x = bx, z = bz, rot = 0 }) else place("nest")
		placedOk = res.ok
		if res.ok then
			table.insert(added, prof.plot.placed[#prof.plot.placed].uid)
		end
	end
	H.expect(placedOk and Plot.huts(prof.plot.placed) == most, "panels", "huts up to the island's limit (HutLimit by its tier)", string.format("%d of %d", Plot.huts(prof.plot.placed), most))
	local n0 = #prof.plot.placed
	res = place("nest")
	H.expect(not res.ok and res.err == "huts" and #prof.plot.placed == n0, "panels", "one hut past the limit is refused (huts)", tostring(res.err))
	H.push(p, 0.3)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_nest", { wait = 0.3 })
	local count = p.PlayerGui:FindFirstChild("Count", true)
	H.expect(count ~= nil and count.Text == string.format("%d/%d", most, most), "panels", "the Huts tab counts the huts out of the limit", count and count.Text)
	local card = H.buttonNamed(p, "Buy_nest", true)
	H.expect(card ~= nil and table.find(H.textsOf(card), "No room") ~= nil, "panels", "the hut card says No room", card and table.concat(H.textsOf(card), "/"))
	H.clickNamed(p, "Buy_nest", { includeDisabled = true, wait = 0.3 })
	H.expect(H.buttonNamed(p, "Place", true) == nil and statusSays("No room for another hut here."), "panels", "a tap on it picks nothing up and says why")
	H.clickNamed(p, "Tab_work", { wait = 0.3 })
	count = p.PlayerGui:FindFirstChild("Count", true)
	local pieces = 0
	for _, q in prof.plot.placed do
		if Plot.group(q.id) == "piece" then
			pieces += 1
		end
	end
	H.expect(count ~= nil and pieces == #prof.plot.placed - 1 and count.Text == string.format("%d/%d", pieces, Plot.limit(prof.tier)), "panels", "the Work tab counts the pieces, the tree left out", count and count.Text)
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	local function indexOf(uid)
		for i, q in prof.plot.placed do
			if q.uid == uid then
				return i
			end
		end
		return 0
	end
	if #added > 0 then
		res = H.req(p, "plot.replace", { i = indexOf(added[1]), id = "burrow" })
		local q = prof.plot.placed[indexOf(added[1])]
		H.expect(res.ok and q ~= nil and q.id == "burrow" and Plot.huts(prof.plot.placed) == most, "panels", "at the limit a bigger hut still replaces a small one", tostring(res.err))
	end
	for _, uid in added do
		H.req(p, "plot.store", { i = indexOf(uid) })
	end
	H.expect(#prof.plot.placed == n0 - #added and Plot.huts(prof.plot.placed) == most - #added, "panels", "(the huts added cleared away again)", string.format("%d pieces, %d huts", #prof.plot.placed, Plot.huts(prof.plot.placed)))
end
H.checkProfile(p, "panels")
mirror(p, "panels")

------------------------------------------------------------------ 7b. the build catalog (GAME_DESIGN 4)
-- "Make much, much more building options, like paths and fences. Polish the build ui more, just like the bakery game,
-- and reference bloxburg. Also, add effects and polish when putting down decor and other amenities." The tray: its
-- tabs and their icons, each tab's row of chips, the cards (cheapest first, the locked ones after with their level),
-- a card's tooltip, the search box, the count on each tab. Then fences drawn through the UI (a line, a box, one fence
-- over another, Erase), a river two tiles wide with a bridge over it and lily pads on it, decor put down with its
-- effects, Copy, Replace within the row, and the keys R and Esc
E.phase = "tray"
local TrayCheck = {}
do
	local PixelSpritesP = H.cmod(p, "UI.PixelSprites")
	local TABS = { "work", "nest", "path", "fence", "water", "nature", "decor", "fun" }
	local ROWS: { [string]: { string } } = {
		work = { "farm", "wood", "shop", "gen" },
		water = { "tiles", "bridge", "float" },
		nature = { "trees", "plants", "rocks" },
		decor = { "beach", "garden", "farm", "harbour", "town", "jungle", "frost", "autumn", "desert", "fairy", "zen", "volcano", "grand" },
		fun = { "seats", "lights", "play", "treats", "fountains" },
	}
	-- every piece but the tree is on one of the tabs, in one of its rows
	local stray = {}
	for _, d in Buildings.list do
		if d.kind ~= "tree" and (not table.find(TABS, d.tab) or (ROWS[d.tab] ~= nil and not table.find(ROWS[d.tab], d.sub))) then
			table.insert(stray, d.id .. "@" .. d.tab .. "/" .. d.sub)
		end
	end
	H.expect(#stray == 0 and #ROWS.decor == 13, "tray", "every piece sits on a tab and one of its rows (Decor's 13 themes)", table.concat(stray, " "))
	-- the cards in the tray now, in their order: each with its id and its corner label (a level, No room, or nil)
	local function trayCards()
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local list = tray and tray:FindFirstChild("Cards", true)
		local out = {}
		for _, c in (list and list:GetChildren() or {}) do
			local id = string.match(c.Name, "^Card_(.+)$")
			if id then
				local lock = c:FindFirstChild("Lock", true)
				table.insert(out, { id = id, order = c.LayoutOrder, lock = lock and lock.Text })
			end
		end
		table.sort(out, function(a, b)
			return a.order < b.order
		end)
		return out
	end
	TrayCheck.cards = trayCards
	-- what's wrong with the cards shown for a tab's row ("" all): not the row's pieces, or not cheapest first with the
	-- locked ones after (by the level they open at, each saying "Lv<n>")
	local function cardProblems(tabKey, row)
		local shown = trayCards()
		local bad = {}
		local want = {}
		for _, d in Buildings.list do
			if d.kind ~= "tree" and d.tab == tabKey and (row == "" or d.sub == row) then
				want[d.id] = true
			end
		end
		local n = 0
		for _ in want do
			n += 1
		end
		if #shown ~= n then
			table.insert(bad, string.format("%d cards of %d", #shown, n))
		end
		local lastWood, lastTier, sawLocked = -1, 0, false
		for _, c in shown do
			local d = Buildings.byId[c.id]
			if not want[c.id] or d == nil then
				table.insert(bad, "stray " .. c.id)
				continue
			end
			if d.tier > prof.tier then
				if c.lock ~= "Lv" .. d.tier then
					table.insert(bad, string.format("%s says %s", c.id, tostring(c.lock)))
				end
				if d.tier < lastTier then
					table.insert(bad, "level order at " .. c.id)
				end
				sawLocked, lastTier = true, d.tier
			else
				if sawLocked then
					table.insert(bad, "open after a locked one: " .. c.id)
				end
				if c.lock ~= nil and c.lock ~= "No room" then
					table.insert(bad, string.format("%s says %s", c.id, tostring(c.lock)))
				end
				if d.wood < lastWood then
					table.insert(bad, "price order at " .. c.id)
				end
				lastWood = d.wood
			end
		end
		return bad, #shown
	end
	TrayCheck.problems = cardProblems
	-- the count a tab shows: the pieces against the piece limit, the huts against theirs, the tiles (paths and water
	-- together) and the fences against their own
	local function wantCount(tabKey)
		if tabKey == "nest" then
			return string.format("%d/%d", Plot.huts(prof.plot.placed), Plot.hutLimit(prof.tier))
		end
		local group = if tabKey == "path" or tabKey == "water" then "tile" elseif tabKey == "fence" then "fence" else "piece"
		local n = 0
		for _, q in prof.plot.placed do
			if Plot.group(q.id) == group then
				n += 1
			end
		end
		return string.format("%d/%d", n, Plot.groupLimit(group, prof.tier))
	end
	TrayCheck.count = wantCount
	local function countText()
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local c = tray and tray:FindFirstChild("Count", true)
		return c and c.Text
	end
	TrayCheck.countText = countText
	prof.wood = math.max(prof.wood, 20000)
	H.push(p, 0.4)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	for _, t in TABS do
		local b = H.buttonNamed(p, "Tab_" .. t)
		local icon = b and b:FindFirstChild("Sprite_mini_" .. t, true)
		H.expect(b ~= nil and icon ~= nil and H.inClient(p, PixelSpritesP.has, "mini_" .. t), "tray", "the " .. t .. " tab with its icon", tostring(b))
		H.clickNamed(p, "Tab_" .. t, { wait = 0.25 })
		H.expect(H.inClient(p, BuildUI.debugState).tab == t, "tray", "a tap on it turns the tray to it", H.inClient(p, BuildUI.debugState).tab)
		H.expect(countText() == wantCount(t), "tray", "the " .. t .. " tab's count", string.format("%s, want %s", tostring(countText()), wantCount(t)))
		local rows = ROWS[t]
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		if rows then
			local chips = 0
			for _, x in (tray and tray:GetDescendants() or {}) do
				if string.sub(x.Name, 1, 5) == "Chip_" and x:IsA("GuiButton") then
					chips += 1
				end
			end
			H.expect(chips == #rows + 1, "tray", "the " .. t .. " tab's chips: All and one a row", string.format("%d of %d", chips, #rows + 1))
			H.clickNamed(p, "Chip_all", { wait = 0.25 })
			local bad, n = cardProblems(t, "")
			H.expect(#bad == 0 and n > 0 and H.inClient(p, BuildUI.debugState).chip == "", "tray", "All shows the whole " .. t .. " tab, cheapest first, the locked ones after", table.concat(bad, " "))
			H.log("tray: %s has %d cards in %d rows", t, n, #rows)
			for _, row in rows do
				H.clickNamed(p, "Chip_" .. row, { wait = 0.2 })
				local badR, nR = cardProblems(t, row)
				H.expect(#badR == 0 and nR > 0 and H.inClient(p, BuildUI.debugState).chip == row, "tray", string.format("the %s chip narrows the %s cards to its row", row, t), table.concat(badR, " "))
			end
			H.clickNamed(p, "Chip_all", { wait = 0.2 })
		else
			local hint = tray and tray:FindFirstChild("TabHint", true)
			local bad, n = cardProblems(t, "")
			H.expect(hint ~= nil and (tray :: Instance):FindFirstChild("Chips", true) == nil and #bad == 0 and n > 0, "tray", "the " .. t .. " tab: a hint in place of chips, every card in order", table.concat(bad, " "))
		end
	end
	-- a card's tooltip (a mouse over it): its name, what it is (its blurb, its charm, whether it goes on or over water)
	-- and, on a locked one, the level it opens at
	local function tipOf(id)
		local ok = H.inClient(p, BuildUI.debugTip, id)
		local tipF = p.PlayerGui:FindFirstChild("BuildTip", true)
		local function txt(n)
			local l = tipF and tipF:FindFirstChild(n, true)
			return l and l.Text
		end
		return ok and tipF ~= nil, txt("TipName"), txt("TipAbout"), txt("TipLocked")
	end
	H.clickNamed(p, "Tab_decor", { wait = 0.2 })
	H.clickNamed(p, "Chip_beach", { wait = 0.2 })
	do
		local d = Buildings.byId.sandcastle
		local shown, name, about, locked = tipOf("sandcastle")
		H.expect(shown and name == d.name and about ~= nil and string.find(about, "Charm +" .. math.floor(d.charm), 1, true) ~= nil and locked == nil, "tray", "a card's tooltip: its name and what it is, nothing locked", string.format("%s / %s / %s", tostring(name), tostring(about), tostring(locked)))
		local lg = Buildings.byId.lifeguard
		shown, name, about, locked = tipOf("lifeguard")
		H.expect(lg.tier > prof.tier and shown and name == lg.name and locked == string.format("Opens at island level %d.", lg.tier), "tray", "a locked one's says the level it opens at", string.format("%s / %s", tostring(name), tostring(locked)))
	end
	H.clickNamed(p, "Tab_water", { wait = 0.2 })
	do
		local _, name, about = tipOf("lilypads")
		H.expect(name == Buildings.byId.lilypads.name and about ~= nil and string.find(about, "Goes on water.", 1, true) ~= nil, "tray", "lily pads go on water, the tooltip says", tostring(about))
		_, name, about = tipOf("plankbridge")
		H.expect(name == Buildings.byId.plankbridge.name and about ~= nil and string.find(about, "Goes over water.", 1, true) ~= nil, "tray", "a bridge goes over it", tostring(about))
		local d = Buildings.byId.stream
		_, name, about = tipOf("stream")
		H.expect(name == d.name and about ~= nil and (d.blurb == "" or string.find(about, d.blurb, 1, true) ~= nil), "tray", "and a water tile's tooltip has its blurb", tostring(about))
	end
	-- the search box: "lantern" lists every piece with lantern in its name from every tab (the chips give way to a line
	-- saying what it found; a Carved Pumpkin isn't one); clearing it brings the tab back
	H.clickNamed(p, "Tab_decor", { wait = 0.2 })
	H.clickNamed(p, "Chip_zen", { wait = 0.2 })
	do
		local box = p.PlayerGui:FindFirstChild("BuildSearch", true)
		H.expect(box ~= nil and box:FindFirstChild("Box") ~= nil and H.guiVisible(box), "tray", "the search box")
		-- the search button by it puts the cursor in the box
		local sb = p.PlayerGui:FindFirstChild("SearchButton", true)
		local tb = if box then box:FindFirstChild("Box") else nil
		H.expect(sb ~= nil and H.guiVisible(sb), "tray", "the search button by the box")
		H.expect(H.clickNamed(p, "SearchButton", { wait = 0.2 }) and tb ~= nil and tb:IsFocused(), "tray", "the search button puts the cursor in the box")
		if tb then
			H.inClient(p, function()
				tb:ReleaseFocus()
			end)
		end
		H.inClient(p, BuildUI.debugSearch, "lantern")
		E.run(0.3)
		local got = {}
		for _, c in trayCards() do
			table.insert(got, c.id)
		end
		table.sort(got)
		local want = { "fairylantern", "icelantern", "lanternrope", "lanterntower", "paperlanterns", "stonelantern", "waterlanterns" }
		local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		local hint = tray and tray:FindFirstChild("TabHint", true)
		local query = p.PlayerGui:FindFirstChild("Query", true)
		H.expect(table.concat(got, ",") == table.concat(want, ","), "tray", "\"lantern\" lists the lantern pieces from every tab (not the Carved Pumpkin)", table.concat(got, ","))
		H.expect(hint ~= nil and hint.Text == "Everything called \"lantern\":" and tray:FindFirstChild("Chips", true) == nil and query ~= nil and query.Text == "lantern", "tray", "the chips give way to a line saying what it found", hint and hint.Text)
		H.expect(H.clickNamed(p, "ClearSearch", { wait = 0.3 }), "tray", "the search's clear mark")
		local bad, n = cardProblems("decor", "zen")
		tray = p.PlayerGui:FindFirstChild("BuildTray", true)
		H.expect(#bad == 0 and n > 0 and tray ~= nil and tray:FindFirstChild("Chips", true) ~= nil and tray:FindFirstChild("TabHint", true) == nil, "tray", "clearing it brings the tab and its row back", table.concat(bad, " "))
	end
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end

-- Fences drawn through Build mode's draw bar (BuildUI.debugDraw, corner to corner, as a drag along the grid lines):
-- a line goes along x then z, a box runs all the way round; each length lies on the even grid running east (rot 0) or
-- south (rot 90). One fence drawn over another swaps it; Erase takes them down, half their price back
E.phase = "fences"
-- the wood moved since w1 comes to `want`, give or take what the island made on its own since t1
local function woodMoved(w1, want, t1)
	local got = prof.wood - w1
	local own = math.max(0, Island.rates(prof).wood) / Tuning.TurnSeconds * (E.now() - t1) * 1.5 + 0.5
	return got >= want - 0.5 and got <= want + own, string.format("%+.1f wood (want %+d)", got, want)
end
-- the fence length on edge e of the island, or nil
local function fenceOn(e)
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) and q.x == e[1] and q.z == e[2] and q.rot == e[3] then
			return q
		end
	end
	return nil
end
-- the edges of a line from corner a to corner b (along x, then z) and of the box between them
local function lineEdges(a, b)
	local out = {}
	for x = math.min(a[1], b[1]), math.max(a[1], b[1]) - 2, 2 do
		table.insert(out, { x, a[2], 0 })
	end
	for z = math.min(a[2], b[2]), math.max(a[2], b[2]) - 2, 2 do
		table.insert(out, { b[1], z, 90 })
	end
	return out
end
local function boxEdges(a, b)
	local out = {}
	for x = a[1], b[1] - 2, 2 do
		table.insert(out, { x, a[2], 0 })
		table.insert(out, { x, b[2], 0 })
	end
	for z = a[2], b[2] - 2, 2 do
		table.insert(out, { a[1], z, 90 })
		table.insert(out, { b[1], z, 90 })
	end
	return out
end
-- the even corner nearest the island's south-east (the side the camera sees) where every edge edgesAt(x, z) gives fits
local function fenceSpot(id, edgesAt)
	local pr = Street.plot(prof.tier)
	local z1, x1 = math.floor(pr.z1 / 2) * 2, math.floor(pr.x1 / 2) * 2
	for z = z1, math.floor(pr.z0), -2 do
		for x = x1, math.floor(pr.x0), -2 do
			local ok = true
			for _, e in edgesAt(x, z) do
				if not Plot.fits(prof.tier, prof.plot.placed, id, e[1], e[2], e[3]) then
					ok = false
					break
				end
			end
			if ok then
				return x, z
			end
		end
	end
	return nil, nil
end
local function plannedAll(plan, what, n)
	local k = 0
	for _, x in plan do
		if x == what then
			k += 1
		end
	end
	return k == n and #plan == n
end
local fenceBox = nil
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_fence", { wait = 0.3 })
	H.clickNamed(p, "Buy_ropefence", { wait = 0.3 })
	H.expect(H.buttonNamed(p, "DrawLine") ~= nil and H.buttonNamed(p, "DrawBox") ~= nil and H.buttonNamed(p, "DrawErase") ~= nil, "fences", "a fence picked: the draw bar (Line, Box, Erase)")
	-- a box 8 by 6 studs
	local bx, bz = fenceSpot("ropefence", function(x, z)
		return boxEdges({ x, z }, { x + 8, z + 6 })
	end)
	H.expect(bx ~= nil, "fences", "(room for a fenced box)")
	if bx then
		local a, b = { bx, bz }, { bx + 8, bz + 6 }
		fenceBox = { a, b }
		H.log("fences: a box from %d,%d to %d,%d", a[1], a[2], b[1], b[2])
		local edges = boxEdges(a, b)
		local n0, w1, t1 = #prof.plot.placed, prof.wood, E.now()
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "box")
		E.run(0.4)
		local all = true
		for _, e in edges do
			local q = fenceOn(e)
			all = all and q ~= nil and q.id == "ropefence"
		end
		H.expect(plannedAll(plan, "lay", #edges) and #edges == 14, "fences", "Box: the plan runs a length along each of the box's 14 edges", table.concat(plan, ","))
		H.expect(all and #prof.plot.placed == n0 + #edges, "fences", "and the island gets them, all the way round", string.format("%d pieces (was %d)", #prof.plot.placed, n0))
		local ok, say = woodMoved(w1, -#edges * Buildings.byId.ropefence.wood, t1)
		H.expect(ok, "fences", "paid in wood, a length at a time", say)
	end
	-- a line from one corner to another: along x, then z
	local lx, lz = fenceSpot("ropefence", function(x, z)
		return lineEdges({ x, z }, { x + 6, z + 4 })
	end)
	H.expect(lx ~= nil, "fences", "(room for a line of fence)")
	if lx then
		local a, b = { lx, lz }, { lx + 6, lz + 4 }
		local edges = lineEdges(a, b)
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "line")
		E.run(0.4)
		local all = true
		for _, e in edges do
			all = all and fenceOn(e) ~= nil
		end
		H.expect(plannedAll(plan, "lay", 5) and all, "fences", "Line: three lengths along x, then two along z", table.concat(plan, ","))
		-- every fence on the island: on the even grid, running east or south
		local off = {}
		for _, q in prof.plot.placed do
			if Plot.isFence(q.id) and (q.x % 2 ~= 0 or q.z % 2 ~= 0 or (q.rot ~= 0 and q.rot ~= 90)) then
				table.insert(off, string.format("%d,%d,%d", q.x, q.z, q.rot))
			end
		end
		H.expect(#off == 0, "fences", "every length on the even grid, turned 0 or 90", table.concat(off, " "))
		-- Erase: the line taken down, half its price back
		local n0, w1, t1 = #prof.plot.placed, prof.wood, E.now()
		plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "erase")
		E.run(0.4)
		local gone = true
		for _, e in edges do
			gone = gone and fenceOn(e) == nil
		end
		H.expect(plannedAll(plan, "lift", 5) and gone and #prof.plot.placed == n0 - 5, "fences", "Erase takes the line down", table.concat(plan, ","))
		local ok, say = woodMoved(w1, 5 * math.floor(Buildings.byId.ropefence.wood * Tuning.Refund), t1)
		H.expect(ok, "fences", "half their price back", say)
	end
	-- one fence over another: a picket line along the box's north side swaps the rope there, the count unchanged
	if fenceBox then
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		H.clickNamed(p, "Buy_picket", { wait = 0.3 })
		local a = fenceBox[1]
		local b = { a[1] + 8, a[2] }
		local edges = lineEdges(a, b)
		local uids = {}
		for i, e in edges do
			local q = fenceOn(e)
			uids[i] = q and q.uid
		end
		local n0, w1, t1 = #prof.plot.placed, prof.wood, E.now()
		local plan = H.inClient(p, BuildUI.debugDraw, { a, b }, "line")
		E.run(0.4)
		local swapped = true
		for i, e in edges do
			local q = fenceOn(e)
			swapped = swapped and q ~= nil and q.id == "picket" and q.uid == uids[i]
		end
		H.expect(plannedAll(plan, "swap", 4) and swapped and #prof.plot.placed == n0, "fences", "a picket fence drawn over the rope one swaps it where it runs", table.concat(plan, ","))
		local ok, say = woodMoved(w1, -4 * (Buildings.byId.picket.wood - math.floor(Buildings.byId.ropefence.wood * Tuning.Refund)), t1)
		H.expect(ok, "fences", "for its price less half the old one's", say)
	end
	H.clickNamed(p, "Cancel", { wait = 0.2 })
	H.expect(TrayCheck.countText() == TrayCheck.count("fence"), "fences", "the Fences tab counts the fence lengths", string.format("%s, want %s", tostring(TrayCheck.countText()), TrayCheck.count("fence")))
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	E.run(0.3)
	local models = 0
	local decorF = static:FindFirstChild("Decor")
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) and decorF and decorF:FindFirstChild(string.format("%d:%s:%d:%d:%d:1", q.uid, q.id, q.x, q.z, q.rot)) then
			models += 1
		end
	end
	local fences = 0
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) then
			fences += 1
		end
	end
	H.expect(fences == 14 and models == fences, "fences", "a model for each length in Static.Decor", string.format("%d of %d", models, fences))
end
H.checkProfile(p, "fences")
mirror(p, "fences")

------------------------------------------------------------------ 7c. water
-- ("add the ability to add water to make rivers")
-- A river two tiles wide dug through the draw bar, each tile's model named with the water round it (its banks drawn
-- only where the water ends); a bridge put over it and lily pads on it as a player does (pick, tap, Place), lily pads
-- refused on the grass; a tile taken up takes the lily pads floating on it
E.phase = "water"
-- the screen point (as an InputObject's) where the pixel layer shows a world point
local function screenAt(world)
	return H.inClient(p, function()
		local pos = PRp.project(world)
		return E.v2(pos.X, pos.Y - E.inset)
	end)
end
-- a tap on the lawn over the middle of piece id's footprint at plot-local (x, z) (a touch: the ghost goes there)
local function tapFor(id, x, z, rot)
	local ox, oz = Street.origin(s.plot)
	local w, d = Plot.footprint(id, rot or 0)
	H.inClient(p, BuildUI.tapScreen, screenAt(E.v3(ox + x + w / 2, Street.LAWN_Y, oz + z + d / 2)), false)
	E.run(0.2)
end
-- the piece `id` standing at (x, z), or nil
local function pieceAt(id, x, z)
	for _, q in prof.plot.placed do
		if q.id == id and q.x == x and q.z == z then
			return q
		end
	end
	return nil
end
local function countOf(id)
	local n = 0
	for _, q in prof.plot.placed do
		if q.id == id then
			n += 1
		end
	end
	return n
end
-- what's wrong with the water tiles' models (Static.Decor "uid:id:x:z:rot:mask"): the mask 1 + north 1, east 2, south
-- 4, west 8 for each side with water next to it
local function maskProblems()
	local wet = {}
	for _, q in prof.plot.placed do
		if Plot.isWater(q.id) then
			wet[q.x .. "," .. q.z] = true
		end
	end
	local decorF = static:FindFirstChild("Decor")
	local bad, n = {}, 0
	for _, q in prof.plot.placed do
		if Plot.isWater(q.id) then
			n += 1
			local m = 1
			m += if wet[q.x .. "," .. (q.z - 2)] then 1 else 0
			m += if wet[(q.x + 2) .. "," .. q.z] then 2 else 0
			m += if wet[q.x .. "," .. (q.z + 2)] then 4 else 0
			m += if wet[(q.x - 2) .. "," .. q.z] then 8 else 0
			local name = string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, m)
			if decorF == nil or decorF:FindFirstChild(name) == nil then
				table.insert(bad, name)
			end
		end
	end
	return bad, n
end
do
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_water", { wait = 0.3 })
	H.clickNamed(p, "Chip_tiles", { wait = 0.2 })
	H.clickNamed(p, "Buy_stream", { wait = 0.3 })
	H.expect(H.buttonNamed(p, "DrawBox") ~= nil, "water", "a water tile picked: the draw bar")
	-- (a spot for a river five tiles long and two wide with grass at both ends of a bridge across its middle)
	local L = 5
	local function riverCells(x, z)
		local out = {}
		for j = 0, 1 do
			for i = 0, L - 1 do
				table.insert(out, { x + 2 * i, z + 2 * j })
			end
		end
		return out
	end
	local pr = Street.plot(prof.tier)
	local rx, rz = nil, nil
	for z = math.floor(pr.z1 / 2) * 2, math.floor(pr.z0), -2 do
		for x = math.floor(pr.x1 / 2) * 2, math.floor(pr.x0), -2 do
			if rx == nil and Plot.fits(prof.tier, prof.plot.placed, "plankbridge", x + 4, z - 1, 0) then
				local ok = true
				for _, c in riverCells(x, z) do
					ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stream", c[1], c[2], 0)
				end
				if ok then
					rx, rz = x, z
				end
			end
		end
	end
	H.expect(rx ~= nil, "water", "(room for a river)")
	if rx then
		H.log("water: a river from %d,%d, five tiles long and two wide", rx, rz)
		local cells = riverCells(rx, rz)
		local n0, w1, t1 = #prof.plot.placed, prof.wood, E.now()
		local plan = H.inClient(p, BuildUI.debugDraw, { { rx, rz }, { rx + 2 * (L - 1), rz + 2 } }, "box")
		E.run(0.5)
		local all = true
		for _, c in cells do
			all = all and pieceAt("stream", c[1], c[2]) ~= nil
		end
		H.expect(plannedAll(plan, "lay", 2 * L) and all and #prof.plot.placed == n0 + 2 * L, "water", "a river two tiles wide dug in one box", table.concat(plan, ","))
		local ok, say = woodMoved(w1, -2 * L * Buildings.byId.stream.wood, t1)
		H.expect(ok, "water", "paid in wood, a tile at a time", say)
		local bad, n = maskProblems()
		H.expect(n == 2 * L and #bad == 0, "water", "each tile's model in Static.Decor carries the water round it (its banks only at the river's edge)", table.concat(bad, " "))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		local tiles = TrayCheck.count("water")
		H.expect(TrayCheck.countText() == tiles and tiles == TrayCheck.count("path"), "water", "the Water tab counts the tiles", string.format("%s, want %s", tostring(TrayCheck.countText()), tiles))
		H.clickNamed(p, "Tab_path", { wait = 0.2 })
		H.expect(TrayCheck.countText() == tiles, "water", "and so does Paths: paths and water count together", tostring(TrayCheck.countText()))
		-- a bridge over it: picked, tapped where it spans the river, Place
		H.clickNamed(p, "Tab_water", { wait = 0.2 })
		H.clickNamed(p, "Chip_bridge", { wait = 0.2 })
		H.clickNamed(p, "Buy_plankbridge", { wait = 0.3 })
		local bx, bz = rx + 4, rz - 1
		tapFor("plankbridge", bx, bz)
		H.expect(H.buttonNamed(p, "Place") ~= nil, "water", "the bridge's ghost fits across the river (Place on)")
		H.clickNamed(p, "Place", { wait = 0.6 })
		local bridge = pieceAt("plankbridge", bx, bz)
		H.expect(bridge ~= nil and pieceAt("stream", bx, rz) ~= nil and pieceAt("stream", bx, rz + 2) ~= nil, "water", "Place: a plank bridge stands over the water tiles", string.format("%s at %d,%d", tostring(bridge ~= nil), bx, bz))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- lily pads: refused on the grass (the ghost red, Place off, the server says blocked), they float on the river
		H.clickNamed(p, "Chip_float", { wait = 0.2 })
		H.clickNamed(p, "Buy_lilypads", { wait = 0.3 })
		local gx, gz = spot("sandcastle", 0)
		local nPads = countOf("lilypads")
		if gx then
			tapFor("lilypads", gx, gz)
			H.expect(H.buttonNamed(p, "Place") == nil and H.buttonNamed(p, "Place", true) ~= nil, "water", "lily pads over the grass: Place is off")
			H.clickNamed(p, "Place", { includeDisabled = true, wait = 0.4 })
			H.expect(countOf("lilypads") == nPads, "water", "(a tap on it puts nothing down)")
			res = H.req(p, "plot.place", { id = "lilypads", x = gx, z = gz, rot = 0 })
			H.expect(not res.ok and res.err == "blocked" and countOf("lilypads") == nPads, "water", "the server refuses lily pads on the grass (blocked)", tostring(res.err))
		end
		tapFor("lilypads", rx, rz)
		H.expect(H.buttonNamed(p, "Place") ~= nil, "water", "over the water Place is on")
		H.clickNamed(p, "Place", { wait = 0.6 })
		local pads = pieceAt("lilypads", rx, rz)
		H.expect(pads ~= nil and countOf("lilypads") == nPads + 1, "water", "Place: lily pads float on the river")
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- Erase the tile under them: they come up with it, half of both prices back; the bridge stays
		H.clickNamed(p, "Chip_tiles", { wait = 0.2 })
		H.clickNamed(p, "Buy_stream", { wait = 0.3 })
		local w2, t2 = prof.wood, E.now()
		plan = H.inClient(p, BuildUI.debugDraw, { { rx, rz } }, "erase")
		E.run(0.5)
		H.expect(plannedAll(plan, "lift", 1) and pieceAt("stream", rx, rz) == nil and countOf("lilypads") == nPads, "water", "Erase on the tile under the lily pads takes them up with it", table.concat(plan, ","))
		ok, say = woodMoved(w2, math.floor(Buildings.byId.stream.wood * Tuning.Refund) + math.floor(Buildings.byId.lilypads.wood * Tuning.Refund), t2)
		H.expect(ok, "water", "half the tile's price back and half the lily pads'", say)
		H.expect(pieceAt("plankbridge", bx, bz) ~= nil, "water", "the bridge stays")
		bad = maskProblems()
		H.expect(#bad == 0, "water", "the tiles next to it are built again with their new banks", table.concat(bad, " "))
		H.clickNamed(p, "Cancel", { wait = 0.2 })
	end
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
end
H.checkProfile(p, "water")
mirror(p, "water")

------------------------------------------------------------------ 7d. decor put down: its effects, Copy, Replace, keys
-- ("add effects and polish when putting down decor and other amenities"). The effects draw over the pixel filter, so
-- the filter is switched on for them (the sims run the classic look otherwise: EditableImages allowed for a moment);
-- a piece put down drops in (BuildFx: a stand-in falls while the server's model is held back) and lands in a burst of
-- 1 px particles (Puffs), all gone within a second, the real model back in its place. Then a piece picked up off the
-- island: Copy puts down another, Replace offers its own row only; R turns the piece picked, Esc drops it, then leaves
E.phase = "decor"
do
	local I = require("./inst")
	local BuildFxP = H.cmod(p, "Controllers.BuildFx")
	local PuffsP = H.cmod(p, "Controllers.Puffs")
	-- a key pressed as Roblox reports it to the game (UserInputService.InputBegan, not over a text box)
	local function press(key)
		local input = I.new("InputObject")
		input.UserInputType = E.Enum.UserInputType.Keyboard
		input.KeyCode = E.Enum.KeyCode[key]
		input.UserInputState = E.Enum.UserInputState.Begin
		I.fire(I.getSig(E.services.UserInputService, "InputBegan"), input, false)
		E.flushDeferred()
		E.run(0.3)
	end
	-- the model of piece q in Static.Decor, if it is there now
	local function modelOf(q)
		local decorF = static:FindFirstChild("Decor")
		return decorF and decorF:FindFirstChild(string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl))
	end
	-- a tap on piece q in Build mode (the ray hits its model's biggest part)
	local function tapPiece(q)
		local m = modelOf(q)
		local big, vol = nil, 0
		for _, part in (m and m:GetDescendants() or {}) do
			if part:IsA("BasePart") and part.Size.X * part.Size.Y * part.Size.Z > vol then
				big, vol = part, part.Size.X * part.Size.Y * part.Size.Z
			end
		end
		if big then
			E.raycastParts = true
			H.inClient(p, BuildUI.tapScreen, screenAt(big.Position), false)
			E.raycastParts = nil
			E.run(0.3)
		end
		local what = p.PlayerGui:FindFirstChild("What", true)
		return what and what.Text
	end
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_decor", { wait = 0.3 })
	H.clickNamed(p, "Chip_beach", { wait = 0.2 })
	H.clickNamed(p, "Buy_sandcastle", { wait = 0.3 })
	local sx, sz = spot("sandcastle", 0)
	H.expect(sx ~= nil, "decor", "(room for a sandcastle)")
	tapFor("sandcastle", sx, sz)
	-- the pixel filter on, Place
	E.editableImageMode = "ok"
	H.inClient(p, PRp.setTier, "low")
	H.expect(H.inClient(p, PRp.isActive), "decor", "(the pixel filter on for the effects)")
	local dyn2 = E.workspace:FindFirstChild("PixelDynamic")
	H.clickNamed(p, "Place", { wait = 0 })
	local q = nil
	local firstShow, firstPuffs, standIn, heldBack = -1, -1, false, false
	local t0 = E.now()
	for _ = 1, 16 do
		E.run(0.05)
		q = q or pieceAt("sandcastle", sx, sz)
		local sh = H.inClient(p, BuildFxP.showing)
		if sh > 0 and firstShow < 0 then
			firstShow = E.now() - t0
		end
		if H.inClient(p, PuffsP.count) > 0 and firstPuffs < 0 then
			firstPuffs = E.now() - t0
		end
		if sh > 0 then
			standIn = standIn or (dyn2 ~= nil and dyn2:FindFirstChild("DropIn") ~= nil)
			heldBack = heldBack or (q ~= nil and modelOf(q) == nil)
		end
	end
	H.expect(q ~= nil, "decor", "Place: a sandcastle on the island", tostring(q))
	H.expect(firstShow >= 0 and firstShow <= 0.3 and standIn and heldBack, "decor", "right after it's put down it drops in (BuildFx.showing, a stand-in falling, the server's model held back)", string.format("showing after %.2f s, stand-in %s, held %s", firstShow, tostring(standIn), tostring(heldBack)))
	H.expect(firstPuffs >= 0 and firstPuffs <= 0.5, "decor", "and lands in a burst of particles (Puffs.count)", string.format("puffs after %.2f s", firstPuffs))
	local quiet = E.runUntil(function()
		return H.inClient(p, BuildFxP.showing) == 0 and H.inClient(p, PuffsP.count) == 0
	end, 2, 0.05)
	H.expect(quiet and H.inClient(p, BuildFxP.showing) == 0 and H.inClient(p, PuffsP.count) == 0, "decor", "both back to nothing within a moment", string.format("%d showing, %d particles, %.2f s", H.inClient(p, BuildFxP.showing), H.inClient(p, PuffsP.count), E.now() - t0))
	H.expect((dyn2 == nil or dyn2:FindFirstChild("DropIn") == nil) and q ~= nil and modelOf(q) ~= nil, "decor", "the stand-in gone and the real model back in Static.Decor")
	H.log("effects: dropping %.2f s after the click, particles %.2f s, quiet %.2f s", firstShow, firstPuffs, E.now() - t0)
	-- (the classic look again)
	H.inClient(p, PRp.setTier, "off")
	E.editableImageMode = "fail"
	H.clickNamed(p, "Cancel", { wait = 0.2 })
	-- Copy: the sandcastle tapped, Copy picks another of it; tapped elsewhere and Place puts the second down
	if q then
		local what = tapPiece(q)
		H.expect(what == "Moving: Sandcastle" and H.buttonNamed(p, "Copy") ~= nil and H.buttonNamed(p, "Replace") ~= nil and H.buttonNamed(p, "Store") ~= nil, "decor", "a tap on it picks it up: Copy, Replace, Clear away", tostring(what))
		H.clickNamed(p, "Copy", { wait = 0.3 })
		local what2 = p.PlayerGui:FindFirstChild("What", true)
		H.expect(what2 ~= nil and what2.Text == "Placing: Sandcastle" and H.buttonNamed(p, "Copy") == nil, "decor", "Copy: another sandcastle picked to place", what2 and what2.Text)
		local cx, cz = spot("sandcastle", 0)
		local n0, w1, t1 = countOf("sandcastle"), prof.wood, E.now()
		if cx then
			tapFor("sandcastle", cx, cz)
			H.clickNamed(p, "Place", { wait = 0.6 })
		end
		local copy = cx and pieceAt("sandcastle", cx, cz)
		H.expect(copy ~= nil and countOf("sandcastle") == n0 + 1 and pieceAt("sandcastle", sx, sz) == q, "decor", "Place: a second sandcastle, the first where it was", string.format("%d sandcastles", countOf("sandcastle")))
		local ok, say = woodMoved(w1, -Buildings.byId.sandcastle.wood, t1)
		H.expect(ok, "decor", "the copy paid for", say)
		H.clickNamed(p, "Cancel", { wait = 0.2 })
		-- Replace: only the others of its row (the beach's, open at this level), each with its price; one taken
		if copy then
			tapPiece(copy)
			H.clickNamed(p, "Replace", { wait = 0.3 })
			local offered = {}
			local tray = p.PlayerGui:FindFirstChild("BuildTray", true)
			for _, x in (tray and tray:GetDescendants() or {}) do
				local id = string.match(x.Name, "^Swap_(.+)$")
				if id then
					table.insert(offered, id)
				end
			end
			table.sort(offered)
			local want = {}
			for _, d in Buildings.list do
				if d.tab == "decor" and d.sub == "beach" and d.id ~= "sandcastle" and d.tier <= prof.tier then
					table.insert(want, d.id)
				end
			end
			table.sort(want)
			H.expect(#want >= 3 and table.concat(offered, ",") == table.concat(want, ","), "decor", "Replace lists the beach row's others, nothing from another row", table.concat(offered, ","))
			local uid = copy.uid
			H.clickNamed(p, "SwapTo_umbrella", { wait = 0.6 })
			local rq = pieceAt("umbrella", cx, cz)
			H.expect(rq ~= nil and rq.uid == uid and countOf("sandcastle") == n0, "decor", "a tap on one replaces it where it stands", tostring(rq and rq.uid))
		end
	end
	-- the keys: R turns the piece picked a quarter, Esc drops it, a second Esc leaves Build mode
	H.clickNamed(p, "Tab_decor", { optional = true, wait = 0.2 })
	H.clickNamed(p, "Chip_garden", { wait = 0.2 })
	H.clickNamed(p, "Buy_gnome", { wait = 0.3 })
	local gx, gz = spot("gnome", 0)
	if gx then
		tapFor("gnome", gx, gz)
	end
	press("R")
	H.clickNamed(p, "Place", { wait = 0.6 })
	local g = gx and pieceAt("gnome", gx, gz)
	H.expect(g ~= nil and g.rot == 90, "decor", "R turns the piece picked a quarter before it goes down", tostring(g and g.rot))
	H.expect(H.buttonNamed(p, "Place", true) ~= nil, "decor", "(still picked for another)")
	press("Escape")
	H.expect(H.buttonNamed(p, "Place", true) == nil and H.buttonNamed(p, "Tab_decor") ~= nil and H.inClient(p, BuildUI.isOpen), "decor", "Esc drops what is picked, Build mode stays open")
	press("Escape")
	H.expect(not H.inClient(p, BuildUI.isOpen) and p.PlayerGui:FindFirstChild("BuildTray", true) == nil, "decor", "a second Esc leaves Build mode")
	if H.inClient(p, BuildUI.isOpen) then
		H.clickNamed(p, "BuildDone", { wait = 0.3 })
	end
end
H.checkProfile(p, "decor")
mirror(p, "decor")

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
-- (a driftling sent to work at a building of another knack, the way the Driftlings panel's Work does: any driftling
-- works anywhere)
local sent = false
for _, x in prof.pals do
	if x.home == 0 then
		continue
	end
	local d = Creatures.byId[x.sp]
	for _, q in prof.plot.placed do
		local b = Buildings.byId[q.id]
		if not sent and d and b and b.knack ~= d.knack and Island.works(q.id) then
			sent = H.req(p, "pal.work", { id = x.id, uid = q.uid }).ok
		end
	end
end
H.expect(sent, "quests", "a driftling sent to work at a building of another knack")
H.push(p, 0.5)
H.expect(H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "a driftling at work: Claim shows")
do
	local shells0, wood0q = prof.shells, prof.wood
	local reward = Quests.list[1].reward
	H.clickNamed(p, "QuestClaim", { wait = 0.5 })
	H.expect(prof.quest == 2 and prof.shells >= shells0 + (reward.shells or 0) and prof.wood >= wood0q + (reward.wood or 0), "quests", "Claim pays the reward (shells and wood) and moves on", string.format("quest %d, shells %+d, wood %+d", prof.quest, prof.shells - shells0, prof.wood - wood0q))
end
-- a quest's Go naming an old tab ("build:wood": More wood) opens Build mode on Work's row of that name
do
	prof.quest = questAt("camp")
	H.push(p, 0.5)
	H.expect(Quests.list[questAt("camp")].go == "build:wood" and H.buttonNamed(p, "QuestGo") ~= nil, "quests", "the quest card: More wood, with Go")
	H.clickNamed(p, "QuestGo", { wait = 0.5 })
	local st = H.inClient(p, BuildUI.debugState)
	H.expect(H.inClient(p, BuildUI.isOpen) and st.tab == "work" and st.chip == "wood" and H.buttonNamed(p, "Buy_lumber") ~= nil, "quests", "Go on it opens Build mode on Work's Wood row", string.format("%s %s", tostring(st.tab), tostring(st.chip)))
	H.clickNamed(p, "BuildDone", { wait = 0.4 })
end
-- the tree's quests: "Hatch three eggs" counts the eggs hatched (two of three: Go opens the tree's panel, a claim is
-- refused; three: Claim), and sixty hatched is a long way off
do
	local taken0 = prof.stats.taken
	prof.quest = questAt("take3")
	prof.stats.taken = 2
	H.push(p, 0.5)
	H.expect(Quests.list[questAt("take3")].go == "tree" and statusSays("Hatch three eggs") and H.buttonNamed(p, "QuestGo") ~= nil, "quests", "the quest card: Hatch three eggs, with Go")
	H.clickNamed(p, "QuestGo", { wait = 0.4 })
	H.expect(H.currentPanel(p) == "tree", "quests", "Go on a tree quest opens the tree's panel", tostring(H.currentPanel(p)))
	H.closePanel(p)
	res = H.req(p, "quest.claim", {})
	H.expect(not res.ok and res.err == "not_done", "quests", "two eggs hatched: not done", tostring(res.err))
	prof.stats.taken = taken0
	H.push(p, 0.5)
	H.expect(prof.stats.taken >= 3 and H.buttonNamed(p, "QuestClaim") ~= nil, "quests", "three eggs hatched: Claim shows", string.format("taken %d", prof.stats.taken))
	H.clickNamed(p, "QuestClaim", { wait = 0.5 })
	H.expect(prof.quest == questAt("take3") + 1, "quests", "and Claim moves on", tostring(prof.quest))
end
prof.quest = questAt("crowd")
H.push(p, 0.5)
H.clickNamed(p, "QuestGo", { wait = 0.4 })
H.expect(H.currentPanel(p) == "tree", "quests", "Go on sixty hatched opens the tree's panel too", tostring(H.currentPanel(p)))
H.closePanel(p)
res = H.req(p, "quest.claim", {})
H.expect(not res.ok and res.err == "not_done", "quests", "sixty hatched not reached: not done", string.format("%s taken %d", tostring(res.err), prof.stats.taken))
-- a quest asking for a rarity (the request of 2026-11-14: "also, while the rare one quest is active or any rarity
-- related quests, make it such that an egg of that rarity will always spawn in the tree of life."): with none of it
-- under the tree the commonest egg turns into one within a second (the same eggs), the client hears of it and says so,
-- the view and the plot's Eggs attribute follow, and the next lot holds one too; once it's met the help stops
do
	local qid = if #TreeL.pool(prof.tier)[3] > 0 then "rare" else "uncommon"
	local want = Quests.list[questAt(qid)].goal.n
	local best0 = prof.stats.best
	prof.stats.best = want - 1
	for i, e in prof.clutch.list do
		if e.r == want or i == 1 then
			e.r = 1
		end
	end
	local ids0 = idsOf(prof.clutch.list)
	local f1 = #fx
	prof.quest = questAt(qid)
	E.run(1.4)
	local function wanted(list)
		local n = 0
		for _, e in list do
			if e.r == want then
				n += 1
			end
		end
		return n
	end
	local heard = fxSince(f1, "eggs")
	H.expect(TreeL.wanted(prof) == want and wanted(prof.clutch.list) == 1 and idsOf(prof.clutch.list) == ids0, "quests", "a quest asking for a rarity: one egg of it under the tree within a second, the same eggs", string.format("%s: %s", qid, eggsAttr(prof.clutch.list)))
	H.expect(#heard >= 1 and heard[#heard].turned == want and heard[#heard].more == 0, "quests", "the client hears of it (Fx eggs with turned)", tostring(#heard))
	local rar = Traits.RARITY[want]
	H.expect(statusSays(string.lower(rar.name) .. " egg is waiting under the tree."), "quests", "and a notice names it")
	local v = H.view(p)
	H.expect(v ~= nil and wanted(v.clutch) == 1, "quests", "the view has it, at its price")
	H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list), "quests", "the plot's Eggs attribute follows", tostring(plot1:GetAttribute("Eggs")))
	-- the next lot holds one too
	local f2 = #fx
	prof.clutch.left = 0.05
	E.runUntil(function()
		return #fxSince(f2, "eggs") > 0
	end, 2, E.dt)
	E.run(0.3)
	H.expect(wanted(prof.clutch.list) >= 1 and #prof.clutch.list == TreeL.count(prof.tier), "quests", "a new lot while it's on: one egg of that rarity among them", eggsAttr(prof.clutch.list))
	-- met: the help stops
	prof.stats.best = want
	H.expect(TreeL.wanted(prof) == 0, "quests", "met: no more help")
	prof.stats.best = best0
end
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
	return { placed = #q.plot.placed, pals = #q.pals, tier = q.tier, skin = q.founder.skin, tut = q.tut, sold = q.stats.sold, taken = q.stats.taken, wood = math.floor(q.wood / 1000), eggs = idsOf(q.clutch.list), eggNext = q.clutch.next }
end
local function expectRefused(label, ok, out, err)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, string.format("%s %s", tostring(ok), type(out) == "table" and tostring(out.err) or tostring(out)))
end
-- (every hut full first, so a hatch asks for a swap)
prof.shells = math.max(prof.shells, 5000)
for _ = 1, 4 do
	local e = cheapestEgg()
	if TreeL.room(prof) > 0 and e then
		H.req(p, "egg.hatch", { id = e.id, swap = 0 })
	end
end
H.expect(TreeL.room(prof) == 0 and #prof.clutch.list > 0, "malicious", "(the huts filled from the tree's eggs, some left)", string.format("room %d, %d eggs", TreeL.room(prof), #prof.clutch.list))
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
-- the old pen's and tree levels' actions, and the tide's (all gone)
ok, out = H.raw(p, "pen.sell", { r = 1 })
expectRefused("the pen's pen.sell (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "pen.best", {})
expectRefused("the pen's pen.best (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "tree.upgrade", { what = "speed" })
expectRefused("the tree's tree.upgrade (gone)", ok, out, "unknown_action")
ok, out = H.raw(p, "tide.take", { id = 1, swap = 0 })
expectRefused("the tide's tide.take (gone)", ok, out, "unknown_action")
-- the eggs': bad payloads, an egg not there, a swap that isn't in a hut, every hut full and no swap
ok, out = H.raw(p, "egg.hatch", { id = "1", swap = 0 })
expectRefused("an egg id that isn't a number", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = -1, swap = 0 })
expectRefused("a negative egg id", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1.5, swap = 0 })
expectRefused("an egg id with a fraction", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1 })
expectRefused("a hatch without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 1, swap = 0, n = 5 })
expectRefused("a hatch with an extra field", ok, out, "bad_payload")
ok, out = H.raw(p, "egg.hatch", { id = 424242, swap = 0 })
expectRefused("an egg that isn't under the tree", ok, out, "not_found")
do
	-- (every hut full, so a swap is asked for: one that lives nowhere is no swap)
	local e = cheapestEgg()
	if H.expect(TreeL.room(prof) == 0 and e ~= nil and TreeL.cost(prof, e.r) <= prof.shells, "malicious", "(every hut full, an egg the shells cover)") then
		ok, out = H.raw(p, "egg.hatch", { id = e.id, swap = 424242 })
		expectRefused("a swap that isn't one of theirs", ok, out, "bad_payload")
		ok, out = H.raw(p, "egg.hatch", { id = e.id, swap = 0 })
		expectRefused("every hut full and no swap", ok, out, "full")
	end
end
ok, out = H.raw(p, "pal.house", { id = 424242, uid = 0, swap = 0 })
expectRefused("a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = pieceOf("lumber").uid, swap = 0 })
expectRefused("a lumber camp is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = treePiece().uid, swap = 0 })
expectRefused("the Tree of Life is no hut", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0, swap = 0 })
expectRefused("moving out of every hut (no pen)", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.house", { id = prof.pals[1].id, uid = 0 })
expectRefused("a move without its swap field", ok, out, "bad_payload")
ok, out = H.raw(p, "pal.sell", { id = 424242 })
expectRefused("selling a driftling not there", ok, out, "not_found")
ok, out = H.raw(p, "plot.store", { i = 1000 })
expectRefused("clearing away a piece that isn't there", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.store", { i = table.find(prof.plot.placed, treePiece()) })
expectRefused("clearing the Tree of Life away", ok, out, "fixed")
ok, out = H.raw(p, "plot.replace", { i = table.find(prof.plot.placed, treePiece()), id = "nest" })
expectRefused("replacing the Tree of Life", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 })
expectRefused("buying a second Tree of Life", ok, out, "bad_payload")
ok, out = H.raw(p, "plot.place", { id = "cottage", x = 0, z = 0, rot = 0 })
expectRefused("a home (gone)", ok, out, "bad_payload")
-- the fences' and the tiles' payloads (plot.fence / plot.unfence / plot.unpaint): bad edges, a turn that isn't 0 or 90,
-- odd corners, more than 40 at once, the eraser's kind missing or unknown, an unknown id, a fence painted as a tile
do
	local function many(n, rot)
		local parts = {}
		for k = 0, n - 1 do
			table.insert(parts, if rot then string.format("%d,0,%d", 2 * (k % 20) - 20, rot) else string.format("%d,%d", 2 * (k % 20) - 20, 2 * (k // 20)))
		end
		return table.concat(parts, ";")
	end
	-- (a free stretch of grass by the fenced box: odd corners there, and an even edge where nothing stands)
	local fx0, fz0 = 0, 0
	if fenceBox then
		fx0, fz0 = fenceBox[1][1] + 2, fenceBox[1][2] + 2
	end
	for _, bad in { "a,b,c", "0,0", "0,0,0;;2,0,0", ";0,0,0", "0,0,0;", "9999,0,0", "0,-999,0", "0.5,0,0", "0,0,180" } do
		ok, out = H.raw(p, "plot.fence", { id = "picket", edges = bad })
		expectRefused(string.format("fence edges \"%s\"", bad), ok, out, "bad_payload")
	end
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,45", fx0, fz0) })
	expectRefused("a fence turned 45", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0;%d,%d,90", fx0 + 1, fz0 + 1, fx0 + 3, fz0 - 1) })
	expectRefused("fence lengths from odd corners (off the even grid)", ok, out, "blocked")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = many(41, 0) })
	expectRefused("41 fence lengths at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "laserfence", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence that doesn't exist", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "stream", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("water drawn as a fence", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { id = "crystalfence", edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence of a bigger island", ok, out, "locked")
	ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", fx0, fz0), n = 1 })
	expectRefused("a fence request with an extra field", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.fence", { edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a fence request without its id", ok, out, "bad_payload")
	do
		-- (through the Tree of Life, through the plaza round the campfire)
		local tq = treePiece()
		local ex, ez = math.floor((tq.x + 2) / 2) * 2, math.floor((tq.z + 4) / 2) * 2
		ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", ex, ez) })
		expectRefused("a fence through the Tree of Life", ok, out, "blocked")
		local px, pz = math.floor((Street.PLAZA.x0 + 2) / 2) * 2, math.floor((Street.PLAZA.z0 + Street.PLAZA.z1) / 4) * 2
		ok, out = H.raw(p, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", px, pz) })
		expectRefused("a fence across the plaza", ok, out, "blocked")
	end
	ok, out = H.raw(p, "plot.unfence", { edges = string.format("%d,%d,45", fx0, fz0) })
	expectRefused("taking down a fence turned 45", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = many(41, 90) })
	expectRefused("taking down 41 lengths at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = "x" })
	expectRefused("taking down bad edges", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unfence", { edges = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("taking down a fence that isn't there", ok, out, "not_found")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("an eraser without its kind", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "lava" })
	expectRefused("an eraser of an unknown kind", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "fence" })
	expectRefused("an eraser of fences on the tiles' action", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = many(41), kind = "all" })
	expectRefused("erasing 41 cells at once", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.unpaint", { cells = string.format("%d,%d", fx0, fz0), kind = "water" })
	expectRefused("erasing water where there's none", ok, out, "not_found")
	ok, out = H.raw(p, "plot.paint", { id = "picket", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("a fence painted as a tile", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.paint", { id = "sandcastle", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("decor painted as a tile", ok, out, "bad_payload")
	ok, out = H.raw(p, "plot.paint", { id = "icepond", cells = string.format("%d,%d", fx0, fz0) })
	expectRefused("water of a bigger island", ok, out, "locked")
	ok, out = H.raw(p, "plot.paint", { id = "stream", cells = string.format("%d,%d,0", fx0, fz0) })
	expectRefused("a cell with an edge's turn", ok, out, "bad_payload")
end
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
-- their own Tree of Life with its first lot (the first two cheap commons); the second client draws both islands' eggs
-- round their trees (each from its plot's Eggs attribute), and the first island's carry no price tags there
do
	local qp = sq.profile
	local qTree = treePiece(qp)
	local qc = qp.clutch
	local plot2 = E.workspace.Plots:FindFirstChild("Plot_2")
	H.expect(qTree ~= nil and #qp.plot.placed == 1 and #qc.list == TreeL.count(1) and qc.list[1].r == 1 and qc.list[2].r == 1, "second", "their own Tree of Life, its first lot laid, the first two commons", eggsAttr(qc.list))
	H.expect(plot2 ~= nil and plot2:GetAttribute("Eggs") == eggsAttr(qc.list), "second", "their plot's Eggs attribute", tostring(plot2 and plot2:GetAttribute("Eggs")))
	local EVq = H.cmod(q, "Controllers.EggView")
	local UIKitQ = H.cmod(q, "UI.UIKit")
	E.runUntil(function()
		return H.inClient(q, EVq.count, 2) == #qc.list and H.inClient(q, EVq.count, 1) == #prof.clutch.list
	end, 3, 0.1)
	E.run(1.5)
	local d1, ring1, apart1, clash1 = ringState(q, 1, prof.clutch.list, treePiece())
	local d2, ring2, apart2, clash2 = ringState(q, 2, qc.list, qTree)
	H.expect(d1 == #prof.clutch.list and ring1 and apart1, "second", "the second client lays the first island's eggs round its tree", string.format("%d of %d, ring %s, on one spot: %s", d1, #prof.clutch.list, tostring(ring1), clash1))
	H.expect(d2 == #qc.list and ring2 and apart2, "second", "and their own round theirs", string.format("%d of %d, ring %s, on one spot: %s", d2, #qc.list, tostring(ring2), clash2))
	local own = {}
	for _, e in qc.list do
		own[e.id] = true
	end
	local tags = 0
	H.inClient(q, function()
		for _, d in UIKitQ.canvas("World"):GetDescendants() do
			if string.match(d.Name, "^EggHatch_(%d+)$") then
				tags += 1
			end
		end
	end)
	H.expect(tags == 0, "second", "no egg carries a price tag on the second client, theirs or the first island's", tostring(tags))
	local _ = own
end
H.checkProfile(q, "second")
mirror(q, "second")

------------------------------------------------------------------ 10. past Sunspire Capital
-- ("allow the player to expand their land even more")
-- The first island pushed to tier 9 (Skyreach Isle) as if expanded that far, then Expand from the tray to tier 10:
-- Driftling Haven, the last (the button says Island max after), its land reaching on north past where the old
-- islands ended (z -64), the pieces of tiers 7 to 10 open and built up there
E.phase = "haven"
do
	local Office = H.sharedServer("Data.Office")
	prof.tier = 9
	Plot.refit(prof)
	PS.build(s)
	H.push(p, 0.5)
	H.expect(static:GetAttribute("Built") == 9 and Office.plan(9).name == "Skyreach Isle", "haven", "(the island at tier 9, Skyreach Isle)", tostring(static:GetAttribute("Built")))
	local guard = 0
	while not select(2, PS.debugNext(1)) and guard < 80 do
		guard += 1
		E.run(0.25)
	end
	local nt, nready, swaps0 = PS.debugNext(1)
	H.expect(nt == 10 and nready, "haven", "Driftling Haven is built ahead in the background", string.format("%s %s", tostring(nt), tostring(nready)))
	prof.wood = Tuning.TierCost[10] + 3000000
	H.push(p, 0.4)
	H.clickNamed(p, "Menu_build", { wait = 0.4 })
	H.clickNamed(p, "Tab_decor", { wait = 0.3 })
	H.clickNamed(p, "Chip_grand", { wait = 0.3 })
	local function lockOf(id)
		for _, c in TrayCheck.cards() do
			if c.id == id then
				return c.lock, true
			end
		end
		return nil, false
	end
	local lock, has = lockOf("rainbowarch")
	H.expect(has and lock == "Lv10" and Buildings.byId.rainbowarch.tier == 10, "haven", "at tier 9 the Rainbow Arch waits for level 10", tostring(lock))
	res = H.req(p, "plot.place", { id = "rainbowarch", x = 0, z = -20, rot = 0 })
	H.expect(not res.ok and res.err == "locked", "haven", "and the server won't build it yet (locked)", tostring(res.err))
	local cost = p.PlayerGui:FindFirstChild("ExpandCost", true)
	H.expect(H.buttonNamed(p, "Expand") ~= nil and cost ~= nil and table.find(H.textsOf(cost), Numbers.coins(Tuning.TierCost[10])) ~= nil, "haven", "Expand on, its price the last step's wood", cost and table.concat(H.textsOf(cost), "/"))
	local wood1, f1, eggs1 = prof.wood, #fx, #prof.clutch.list
	H.clickNamed(p, "Expand", { wait = 0 })
	local cheer = E.runUntil(function()
		return statusSays("Your island grew into Driftling Haven.")
	end, 2, 0.05)
	H.expect(prof.tier == 10 and math.abs(prof.wood - (wood1 - Tuning.TierCost[10])) < 2, "haven", "Expand: tier 10 for its wood", string.format("tier %d, wood %+.0f", prof.tier, prof.wood - wood1))
	local grew = ""
	for _, d in p.PlayerGui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "grew", 1, true) then
			grew = d.Text
		end
	end
	H.expect(cheer and Office.plan(10).name == "Driftling Haven", "haven", "the cheer names the island it grew into: Driftling Haven", grew)
	local _, _, swaps1 = PS.debugNext(1)
	E.run(0.5)
	H.expect(swaps1 == swaps0 + 1 and static:GetAttribute("Built") == 10, "haven", "the island built ahead swapped in", string.format("%d -> %d, built %s", swaps0, swaps1, tostring(static:GetAttribute("Built"))))
	local maxB = H.buttonNamed(p, "Expand", true)
	H.expect(maxB ~= nil and table.find(H.textsOf(maxB), "Island max") ~= nil and H.buttonNamed(p, "Expand") == nil and p.PlayerGui:FindFirstChild("ExpandCost", true) == nil, "haven", "the button says Island max after, greyed, no price", maxB and table.concat(H.textsOf(maxB), "/"))
	res = H.req(p, "island.expand", {})
	H.expect(not res.ok and res.err == "max" and prof.tier == 10, "haven", "and the server grows it no more (max)", tostring(res.err))
	H.expect(#prof.clutch.list == TreeL.count(10) and #prof.clutch.list >= eggs1 and #fxSince(f1, "eggs") >= (if TreeL.count(10) > eggs1 then 1 else 0), "haven", "the tree lays the biggest island's eggs", string.format("%d of %d", #prof.clutch.list, TreeL.count(10)))
	-- the land reaches north past z -64, where the islands up to Sunspire Capital ended
	local pr10, pr6 = Street.plot(10), Street.plot(6)
	local north = 0
	for x = math.floor(pr10.x0), math.floor(pr10.x1) do
		if Street.buildable(10, x, -70) then
			north += 1
		end
	end
	local ox, oz = Street.origin(s.plot)
	local landParts = 0
	local landM = static:FindFirstChild("Land")
	for _, d in (landM and landM:GetDescendants() or {}) do
		if d:IsA("BasePart") and d.Position.Z < oz - 64 and math.abs(d.Position.X - ox) < 40 then
			landParts += 1
		end
	end
	H.expect(pr6.z0 >= -64 and pr10.z0 < -64 and north > 0 and landParts > 0, "haven", "the land reaches north of z -64 (grass to build on, the island's model there)", string.format("grass from z %d (Sunspire %d), %d cells at z -70, %d parts", pr10.z0, pr6.z0, north, landParts))
	-- every card open now: no level on any of them
	local locked = {}
	for _, t in { "work", "nest", "path", "fence", "water", "nature", "decor", "fun" } do
		H.clickNamed(p, "Tab_" .. t, { wait = 0.2 })
		H.clickNamed(p, "Chip_all", { optional = true, wait = 0.2 })
		for _, c in TrayCheck.cards() do
			if c.lock ~= nil and c.lock ~= "No room" then
				table.insert(locked, c.id)
			end
		end
	end
	local high = 0
	for _, d in Buildings.list do
		if d.tier >= 7 and d.tier <= 10 then
			high += 1
		end
	end
	H.expect(#locked == 0 and high >= 10, "haven", "every card open at tier 10, the pieces of tiers 7 to 10 among them", table.concat(locked, " "))
	H.clickNamed(p, "BuildDone", { wait = 0.3 })
	-- tiers 7 to 10 built up north: a Rainbow Arch (10), a Crystal Fence (8), a Gilded Walk (7), a Lava Rock (7)
	-- (the first spot north of z -64 where every one of the pieces at(x, z) gives, {dx, dz, rot} from it, fits)
	local function northSpot(id, at)
		for z = -66, math.floor(pr10.z0), -1 do
			for x = math.floor(pr10.x0), math.floor(pr10.x1) do
				local ok = not Plot.isDrawn(id) or (x % 2 == 0 and z % 2 == 0)
				for _, o in at or { { 0, 0, 0 } } do
					ok = ok and Plot.fits(prof.tier, prof.plot.placed, id, x + o[1], z + o[2], o[3])
				end
				if ok then
					return x, z
				end
			end
		end
		return nil, nil
	end
	local got = {}
	for _, id in { "rainbowarch", "lavarock" } do
		local x, z = northSpot(id)
		res = if x then H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 }) else { ok = false, err = "no spot" }
		table.insert(got, string.format("%s %s", id, if res.ok then "ok" else tostring(res.err)))
		H.expect(res.ok and z ~= nil and z < -64 and pieceAt(id, x, z) ~= nil, "haven", string.format("a %s (tier %d) built north of z -64", Buildings.byId[id].name, Buildings.byId[id].tier), tostring(res.err))
	end
	do
		local x, z = northSpot("goldpath", { { 0, 0, 0 }, { 2, 0, 0 } })
		res = if x then H.req(p, "plot.paint", { id = "goldpath", cells = string.format("%d,%d;%d,%d", x, z, x + 2, z) }) else { ok = false, err = "no spot" }
		H.expect(res.ok and type(res.data) == "table" and res.data.placed == 2 and pieceAt("goldpath", x, z) ~= nil, "haven", "a Gilded Walk (tier 7) laid up there", tostring(res.err))
		x, z = northSpot("crystalfence", { { 0, 0, 0 }, { 0, 0, 90 } })
		res = if x then H.req(p, "plot.fence", { id = "crystalfence", edges = string.format("%d,%d,0;%d,%d,90", x, z, x, z) }) else { ok = false, err = "no spot" }
		H.expect(res.ok and type(res.data) == "table" and res.data.placed == 2 and fenceOn({ x, z, 0 }) ~= nil and fenceOn({ x, z, 90 }) ~= nil, "haven", "a Crystal Fence (tier 8) run along the grid up there", tostring(res.err))
	end
	H.log("haven: %s", table.concat(got, ", "))
	E.run(0.4)
	local card = p.PlayerGui:FindFirstChild("IslandCard", true)
	local title = card and card:FindFirstChild("Title", true)
	H.expect(title ~= nil and title.Text == "Driftling Haven", "haven", "the HUD's island card says Driftling Haven", title and title.Text)
end
H.checkProfile(p, "haven")
mirror(p, "haven")
H.checkProfile(p, "end")
mirror(p, "end")

report(E, H)
