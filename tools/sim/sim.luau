-- The main simulation: a new island end to end through the real client and its UI (the campfire, the jetty, the Tree
-- of Life with its first lot of eggs round its roots, the HUD with the tree's card, the tips), building what the tips
-- ask in their order (a lumber camp, a veggie patch, a hut, then an egg hatched by tapping it, then a snack stall: the
-- starting wood and shells cover them), the tree in Build mode (moved like any piece, never cleared away), the days
-- turning (the stores grow, every building working a little with nobody at it), the tree's eggs (the plot's Eggs
-- attribute, the ring every client lays them on, the price tags and their rules, the card's best three and the time to
-- the next lot, hatching from the card, a tag and the panel, the swap picker when every hut is full, the picker going
-- back to the list when a new lot replaced its egg, a new lot every Tree.secs, a tap on the tree opening its panel),
-- the Driftlings panel (moving one to a second hut and back in a swap, Work, selling in two taps), the Index panel, the
-- founder's looks, settings, expanding for wood (the extra eggs laid at once), the questline, then a malicious client,
-- then a second player. No villagers since 2026-11-12, no food since 2026-11-13, the Tree of Life's eggs in place of
-- the tide since 2026-11-13. Every check is an H.expect; the SIM REPORT must show 0 findings and 0 errors.
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
-- the World canvas's price tag over one of the own tree's eggs (Controllers/EggView), or nil
local UIKitP = H.cmod(p, "UI.UIKit")
local EggViewP = H.cmod(p, "Controllers.EggView")
local function worldTag(id)
	return H.inClient(p, function()
		return UIKitP.canvas("World"):FindFirstChild("EggHatch_" .. id, true)
	end)
end
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
-- the own island's price tags now, as the player sees them: for each of the view's eggs EggView draws, how far under
-- the lawn it is, whether it is on screen, whether its tag shows, the tag's place on the canvas and the egg's foot there
local function tagState()
	local v = H.view(p)
	return H.inClient(p, function()
		local list = {}
		local canvas = UIKitP.canvas("World")
		for _, e in v.clutch do
			local at = EggViewP.where(s.plot, e.id)
			if at then
				local tag = canvas:FindFirstChild("EggHatch_" .. e.id, true)
				local fx0, fy0, on1 = PRp.projectPixel(at)
				local _, _, on2 = PRp.projectPixel(at + E.v3(0, 2.4, 0))
				table.insert(list, {
					e = e,
					under = Street.LAWN_Y - at.Y,
					on = on1 and on2,
					foot = { fx0, fy0 },
					shown = tag ~= nil and H.guiVisible(tag),
					rect = if tag then { tag.Position.X.Offset, tag.Position.Y.Offset, tag.Size.X.Offset, tag.Size.Y.Offset } else nil,
				})
			end
		end
		return list
	end)
end
-- what's wrong with the tags now: one showing while its egg is under the lawn, one not over its egg, two showing over
-- each other, the rarest egg up and on screen without its tag (a tag only gives way to a rarer egg's)
local function tagProblems(st)
	local bad = {}
	local shown = {}
	local best = nil
	for _, t in st do
		if t.shown and t.under >= 0.3 then
			table.insert(bad, "under " .. t.e.id)
		end
		if t.shown then
			local a = t.rect
			if math.abs(a[1] + math.floor(a[3] / 2) - t.foot[1]) > 1 or a[2] + a[4] > t.foot[2] then
				table.insert(bad, "off its egg " .. t.e.id)
			end
			for _, o in shown do
				local b = o.rect
				if a[1] < b[1] + b[3] and b[1] < a[1] + a[3] and a[2] < b[2] + b[4] and b[2] < a[2] + a[4] then
					table.insert(bad, string.format("overlap %d/%d", t.e.id, o.e.id))
				end
			end
			table.insert(shown, t)
		end
		if t.on and t.under < 0.05 and (best == nil or t.e.r > best.e.r or (t.e.r == best.e.r and t.e.id < best.e.id)) then
			best = t
		end
	end
	if best and not best.shown then
		table.insert(bad, "rarest hidden " .. best.e.id)
	end
	return bad
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
	local rows, cardRows = 0, 0
	for _, e in best3 do
		local b = H.buttonNamed(p, "CardHatch_" .. e.id, true)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if b and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and table.find(H.textsOf(b), Numbers.coins(e.cost)) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardHatch_" then
			cardRows += 1
		end
	end
	H.expect(#best3 == 3 and idsOf(best3) == idsOf(bestOf(v0.clutch, v0.shells, 3)) and rows == #best3 and cardRows == #best3, "join", "the card shows the best three eggs, each with its egg, its rarity and its price", string.format("%s: %d rows, %d on the card", idsOf(best3), rows, cardRows))
	-- (each egg rises out of the lawn, one after another)
	E.runUntil(function()
		return H.inClient(p, EggViewP.count, s.plot) == #c.list
	end, 3, 0.1)
	E.run(1.5)
	local drawn, onRing, apart, clash = ringState(p, s.plot, c.list, treeQ)
	H.expect(drawn == #c.list and H.inClient(p, EggViewP.count, s.plot) == #c.list and onRing and apart, "join", "EggView lays every egg on the ring round the tree, each on its own spot", string.format("%d drawn of %d, ring %s, on one spot: %s", drawn, #c.list, tostring(onRing), clash))
	local st = tagState()
	local shownTags = 0
	for _, t in st do
		if t.shown then
			shownTags += 1
		end
	end
	local bad = tagProblems(st)
	H.expect(shownTags >= 1 and #bad == 0, "join", "price tags over the eggs (not while under the lawn, not over a rarer one's)", string.format("%d eggs, %d tags showing: %s", #st, shownTags, table.concat(bad, " ")))
	H.log("eggs: %s laid, %d drawn, %d tags showing", eggsAttr(c.list), drawn, shownTags)
	local named = H.inClient(p, function()
		for _, d in UIKitP.canvas("World"):GetDescendants() do
			if string.sub(d.Name, 1, 8) == "EggName_" then
				return true
			end
		end
		return false
	end)
	H.expect(not named, "join", "no names over the eggs (their spots show the rarity)")
	-- no hut yet: a tap on a price on the card is refused (no_hut) and says why
	local e1 = nil
	for _, e in best3 do
		if e.cost <= prof.shells and (e1 == nil or e.cost < e1.cost) then
			e1 = e
		end
	end
	H.expect(e1 ~= nil, "join", "an egg on the card the starting shells cover")
	if e1 then
		local sh = prof.shells
		H.clickNamed(p, "CardHatch_" .. e1.id, { wait = 0.5 })
		H.expect(#prof.pals == 0 and prof.shells == sh and eggOf(e1.id) ~= nil, "join", "no hut yet: hatching is refused, nothing paid, the egg still there", string.format("%d driftlings, %s shells", #prof.pals, tostring(prof.shells)))
		H.expect(statusSays("Build a hut first"), "join", "and the notice says to build a hut first")
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
H.expect(H.clickNamed(p, "Menu_build", { wait = 0.4 }) and BuildUI.isOpen(), "build", "Build mode opens")
local bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "wood" and bst.goal == "lumber", "build", "the first tip: the Wood tab, the lumber camp to build", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the tip's banner shows in Build mode")
H.clickNamed(p, "Tab_decor", { wait = 0.3 })
H.expect(H.inClient(p, BuildUI.debugState).tab == "decor", "build", "the player can still look round the other tabs")
H.expect(H.buttonNamed(p, "Buy_tree", true) == nil, "build", "no Tree of Life in the tray (every island has its one)")
local wood0, sh0 = prof.wood, prof.shells
local res = place("lumber")
E.run(0.5)
bst = H.inClient(p, BuildUI.debugState)
H.expect(bst.tab == "farm" and bst.goal == "patch" and H.buttonNamed(p, "Buy_patch") ~= nil, "build", "the camp built: the tray turns to the Farms tab and the veggie patch", string.format("%s %s", tostring(bst.tab), tostring(bst.goal)))
H.expect(tipShown(), "build", "the next tip's banner over the tray")
H.clickNamed(p, "BuildDone", { wait = 0.3 })
H.expect(not BuildUI.isOpen() and tipShown(), "build", "Done: the tray goes, the tip stays")
H.expect(res.ok and #prof.plot.placed == 2 and pieceOf("lumber") ~= nil, "build", "a lumber camp", tostring(res.err))
H.expect(math.abs(prof.wood - (wood0 - Buildings.byId.lumber.wood)) < 2 and math.abs(prof.shells - sh0) < 1, "build", "paid for in wood, no shells", string.format("wood %s -> %s, shells %s -> %s", wood0, prof.wood, sh0, prof.shells))
H.expect(prof.tut == 2, "build", "the tips move on to a farm (wood built)", tostring(prof.tut))
H.expect(H.buttonNamed(p, "TipsOk") == nil, "build", "no OK on the early tips")
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: the tips move on to a hut", tostring(res.err))
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: the tips move on to hatching an egg", string.format("%s tut %d", tostring(res.err), prof.tut))
-- step 4: an egg hatched, the egg itself tapped under the tree (EggView.tapAt: WorldView's taps ask it first): the
-- cheapest the shells cover, up out of the lawn and on screen; what hatches (a new island's first: good with wood) moves
-- into the hut and goes to work at the lumber camp
do
	H.push(p, 0.3)
	H.expect(statusSays("The Tree of Life laid eggs round its roots. Tap one to hatch it."), "build", "the tip asks for an egg hatched")
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
		local first = prof.pals[1]
		local c = first and Creatures.byId[first.sp]
		H.expect(#prof.pals == 1 and prof.stats.taken == 1 and paid(sh1, -pick.cost, t1, rate0), "build", "a tap on the egg itself hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r) and c.knack == "wood", "build", "a driftling of the egg's rarity, good with wood (a new island's first)", first and string.format("%s r%d", first.sp, pick.r))
		H.expect(eggOf(pick.id) == nil, "build", "and the egg is gone from under the tree")
		local hatched = fxSince(f1, "hatched")
		H.expect(#hatched == 1 and type(hatched[1].data) == "table" and hatched[1].data.egg == pick.id and hatched[1].data.sp == (first and first.sp), "build", "the client hears of it (Fx hatched)", tostring(#hatched))
		H.expect(statusSays("It hatched"), "build", "and says what hatched")
		E.runUntil(function()
			return H.inClient(p, EggViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(H.inClient(p, EggViewP.where, s.plot, pick.id) == nil and H.inClient(p, EggViewP.count, s.plot) == #prof.clutch.list, "build", "its egg cracks open and is gone, the others stay", tostring(H.inClient(p, EggViewP.count, s.plot)))
		local hut = pieceOf("nest")
		H.expect(first ~= nil and hut ~= nil and first.home == hut.uid and first.work == pieceOf("lumber").uid, "build", "it moves into the hut and goes to work at the lumber camp", first and string.format("home %d work %d", first.home, first.work))
		H.expect(prof.tut == 5, "build", "the tips move on to a shop", tostring(prof.tut))
	end
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
-- the HUD's tree card: the best three eggs, each with its egg, its rarity's name and its price on a button that hatches
-- it; over them the time to the next lot, counting down, with a bar running down beside it. A tap on a price hatches
-- that egg (the hut has room for one more), and what hatches walks the island
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
		local b = H.buttonNamed(p, "CardHatch_" .. e.id)
		local name = card and card:FindFirstChild("EggName_" .. e.id, true)
		if b and name and name.Text == Traits.RARITY[e.r].name and card:FindFirstChild("EggIcon_" .. e.id, true) and table.find(H.textsOf(b), Numbers.coins(e.cost)) then
			rows += 1
		end
	end
	for _, x in (card and card:GetDescendants() or {}) do
		if string.sub(x.Name, 1, 10) == "CardHatch_" then
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
	-- hatch one from the card
	local pick = nil
	for _, e in H.inClient(p, EggViewP.best, H.view(p), 3) do
		if e.cost <= prof.shells and H.buttonNamed(p, "CardHatch_" .. e.id) ~= nil and (pick == nil or e.cost < pick.cost) then
			pick = e
		end
	end
	H.expect(pick ~= nil, "tree", "an egg on the card the shells cover")
	if pick then
		local sh1, n0, t1, rate0 = prof.shells, #prof.pals, E.now(), Island.rates(prof).shells
		local f1 = #fx
		H.clickNamed(p, "CardHatch_" .. pick.id, { wait = 0.6 })
		local x = prof.pals[#prof.pals]
		local c = x and Creatures.byId[x.sp]
		H.expect(#prof.pals == n0 + 1 and prof.stats.taken == 2 and paid(sh1, -pick.cost, t1, rate0), "tree", "a tap on its price on the card hatches it for its shells", string.format("%d driftlings, %+.1f shells (cost %d)", #prof.pals, prof.shells - sh1, pick.cost))
		H.expect(c ~= nil and c.rarity == hatchRarity(pick.r) and (c.knack == "farm" or not hasKnack(pick.r, "farm")), "tree", "a driftling of the egg's rarity (a new island's second: good at a farm)", x and string.format("%s r%d", x.sp, pick.r))
		H.expect(x.home == pieceOf("nest").uid and eggOf(pick.id) == nil, "tree", "into the hut with room, the egg gone from under the tree", tostring(x.home))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
		H.expect(#hatched == 1 and type(data) == "table" and data.egg == pick.id and data.id == x.id and data.r == pick.r and data.cost == pick.cost and data.sold == 0 and data.swapped == 0, "tree", "the client hears of it (Fx hatched: the egg, what hatched, its price)", tostring(#hatched))
		E.runUntil(function()
			return H.buttonNamed(p, "CardHatch_" .. pick.id, true) == nil and H.inClient(p, EggViewP.where, s.plot, pick.id) == nil
		end, 2, 0.1)
		H.expect(plot1:GetAttribute("Eggs") == eggsAttr(prof.clutch.list) and H.buttonNamed(p, "CardHatch_" .. pick.id, true) == nil, "tree", "gone from the plot's Eggs attribute and from the card", tostring(plot1:GetAttribute("Eggs")))
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
-- every hut full: a world tag (one showing, the shells there) opens the swap picker; Swap sells the one picked and what
-- hatches takes its place
do
	local e = nil
	E.runUntil(function()
		e = nil
		for _, t in tagState() do
			if e == nil and t.shown and t.e.cost <= prof.shells then
				e = t.e
			end
		end
		return e ~= nil
	end, 3, 0.1)
	H.expect(e ~= nil and H.guiVisible(worldTag(e.id)), "tree", "a price tag shows over an egg the shells cover")
	if e then
		local n0, taken0 = #prof.pals, prof.stats.taken
		H.clickNamed(p, "EggHatch_" .. e.id, { wait = 0.6 })
		H.expect(#prof.pals == n0 and prof.stats.taken == taken0 and eggOf(e.id) ~= nil, "tree", "every hut full: a tap on the tag hatches nothing yet", string.format("%d driftlings", #prof.pals))
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
		H.expect(c ~= nil and c.rarity == hatchRarity(e.r) and x.home == hut and #prof.pals == n0 and eggOf(e.id) == nil and paid(sh1, price - e.cost, t1, rate0), "tree", "and what hatches takes its place in the hut, paid less what the other sold for", string.format("%+.1f shells (cost %d, sold for %d)", prof.shells - sh1, e.cost, price))
		local hatched = fxSince(f1, "hatched")
		local data = hatched[1] and hatched[1].data
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
		local bad = tagProblems(tagState())
		H.expect(#bad == 0, "tree", "the new lot's price tags keep their rules", table.concat(bad, " "))
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
	H.clickNamed(p, "Tab_farm", { wait = 0.3 })
	count = p.PlayerGui:FindFirstChild("Count", true)
	local nPaths = 0
	for _, q in prof.plot.placed do
		if Plot.isPath(q.id) then
			nPaths += 1
		end
	end
	H.expect(count ~= nil and count.Text == string.format("%d/%d", #prof.plot.placed - nPaths - 1, Plot.limit(prof.tier)), "panels", "the other tabs count the pieces, the tree left out", count and count.Text)
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
	local tags, theirs, shownOwn = 0, 0, 0
	H.inClient(q, function()
		for _, d in UIKitQ.canvas("World"):GetDescendants() do
			local id = tonumber(string.match(d.Name, "^EggHatch_(%d+)$"))
			if id then
				tags += 1
				if not own[id] then
					theirs += 1
				elseif H.guiVisible(d) then
					shownOwn += 1
				end
			end
		end
	end)
	H.expect(theirs == 0 and tags <= #qc.list, "second", "the first island's eggs carry no price tags on the second client", string.format("%d tags, %d not theirs", tags, theirs))
	H.expect(shownOwn >= 1, "second", "their own eggs do", tostring(shownOwn))
end
H.checkProfile(q, "second")
mirror(q, "second")
H.checkProfile(p, "end")
mirror(p, "end")

report(E, H)
