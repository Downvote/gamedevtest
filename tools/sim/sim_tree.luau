-- The Tree of Life's eggs (GAME_DESIGN 6; Logic/Tree, Controllers/EggView): "bring back the tree of life and remove the
-- converyer belt system. it now spawns eggs around it that the player can choose to hatch for some shells. it spawns
-- in 5 eggs around it, which refreshes every few minutes to spawn in another 5 eggs, replacing any existing eggs that
-- were not taken. expanding the island increases the quality of eggs spawned and amount of eggs spawned". End to end
-- through the real server and client: a new island's tree (one piece, never bought, cleared away or replaced, moved
-- like any other, outside the piece limit) and its first lot laid at once (Tree.count eggs, two cheap commons first),
-- the profile's clutch, the plot's Eggs attribute, the view, the client drawing them on the arc round the tree's front
-- (EggView), the HUD's Tree card (the time to the next lot, the best three with their prices) and no price tags over
-- the eggs at all (the request of 2026-11-13: "remove these, the eggs should be buyable only after the player clicks on
-- the tree or enters the tree menu": the card, an egg or the tree tapped opens the tree's panel, which alone buys);
-- refusals (no hut, gone, malformed, a shell short, every hut full); hatching from the panel opened by the card, its
-- Open, a tapped egg and the tree, each paid for (the hatch scene ends at once here: HatchScene.setQuick; sim.luau plays
-- it), into a hut and off to work, the egg cracking where it lay (the first two good with wood, then at a farm);
-- the swap picker; the lot replaced on the tree's clock (every old egg gone, new ids, Fx eggs), a hatched-down lot too,
-- and the swap picker going back to the list when its egg goes; the eggs and their clock kept over a leave and a
-- rejoin; the huts' tree, luck and cost shares; expanding (the extra eggs at once, dearer, better odds, the ring
-- spaced out again); the own tree tapped opens its panel, a neighbour's says whose it is; a neighbour's eggs drawn by
-- both clients, with no price tags on either.
local E = require("./loader")
local H = require("./harness")
local I = require("./inst")
local report = require("./report")
local sources = require("./sources")
E.verbose = false
E.dt = 0.1
H.patchMonetizationIds(sources)
E.boot(sources)
E.phase = "boot"
E.startServer()
E.run(1)

local Tuning = H.sharedServer("Config.Tuning")
local Plot = H.sharedServer("Logic.Plot")
local Tree = H.sharedServer("Logic.Tree")
local Island = H.sharedServer("Logic.Island")
local Numbers = H.sharedServer("Logic.Numbers")
local Creatures = H.sharedServer("Data.Creatures")
local Buildings = H.sharedServer("Data.Buildings")
local Traits = H.sharedServer("Data.Traits")
local Street = H.sharedServer("Data.Street")
local DecorModels = H.sharedServer("Models.DecorModels")

-- EggView's arc round the tree (radians from the south, east positive: the side the view looks at) and the seconds a
-- new lot takes to be drawn and risen out of the lawn (a sync every half second, then each egg a beat after the last)
local ARC0, ARC1 = math.rad(-62), math.rad(152)
local RISEN = 2.4
local STORE = Tuning.DataStoreName .. "/global"

------------------------------------------------------------------ the player and its client
local joinT = E.now()
local p = H.addPlayer({ userId = 9701, name = "Gardener" })
E.run(2)
local s = H.session(p)
local prof = H.profile(p)

local function clientOf(pl)
	-- (the hatch scene ends at once: these hatches test the rules, the panels and the island)
	H.inClient(pl, H.cmod(pl, "UI.HatchScene").setQuick, true)
	return {
		EV = H.cmod(pl, "Controllers.EggView"),
		WV = H.cmod(pl, "Controllers.WorldView"),
		SC = H.cmod(pl, "Controllers.StateClient"),
		PR = H.cmod(pl, "Pixel.PixelRenderer"),
		UIKit = H.cmod(pl, "UI.UIKit"),
		BuildUI = H.cmod(pl, "UI.BuildUI"),
		Words = H.cmod(pl, "UI.Words"),
		HS = H.cmod(pl, "UI.HatchScene"),
	}
end
local C = clientOf(p)

-- every Fx message a client gets (with the time it came) and how many whole views
local function watch(pl)
	local w = { fx = {}, states = 0 }
	local c = clientOf(pl)
	H.inClient(pl, function()
		c.SC.Fx:Connect(function(msg)
			table.insert(w.fx, { msg = msg, t = E.now() })
		end)
		c.SC.Changed:Connect(function()
			w.states += 1
		end)
	end)
	return w
end
local W = watch(p)

------------------------------------------------------------------ helpers
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
-- the GUI objects whose names start with `prefix` (visible ones only when `vis`), under `root` (the PlayerGui)
local function named(pl, prefix, vis, root)
	local out = {}
	for _, d in (root or pl:FindFirstChild("PlayerGui")):GetDescendants() do
		if string.sub(d.Name, 1, #prefix) == prefix and (not vis or H.guiVisible(d)) then
			table.insert(out, d)
		end
	end
	return out
end
-- a visible line of text saying `text` (a notice, or the open panel's status line)
local function says(pl, text)
	for _, d in pl:FindFirstChild("PlayerGui"):GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, text, 1, true) and H.guiVisible(d) then
			return true
		end
	end
	return false
end
local function fxSince(w, i0, kind)
	local out = {}
	for i = i0 + 1, #w.fx do
		if w.fx[i].msg.kind == kind then
			table.insert(out, w.fx[i])
		end
	end
	return out
end
-- a raw request's refusal code (the remote directly: the malicious path)
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
local function placeFor(pl, id, x0, z0)
	local pr = H.profile(pl)
	local x, z, rot = Plot.spot(pr.tier, pr.plot.placed, id, x0 or 6, z0 or 14, 0)
	if x == nil then
		return { ok = false, err = "no spot" }
	end
	local res = H.req(pl, "plot.place", { id = id, x = x, z = z, rot = rot })
	E.run(0.2)
	return res
end
local function place(id, x0, z0)
	return placeFor(p, id, x0, z0)
end
-- tap a button wherever it is: true when it was there, and whether it was visible
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
-- "m:ss", as the card and the panel write a time
local function clock(secs)
	local n = math.max(0, math.ceil(secs))
	return string.format("%d:%02d", n // 60, n % 60)
end
local function secsOf(text, prefix)
	local m, ss = string.match(text or "", "^" .. prefix .. "(%d+):(%d%d)$")
	return if m then tonumber(m) * 60 + tonumber(ss) else nil
end

-- the eggs
local function idsOf(list)
	local out = {}
	for _, e in list do
		table.insert(out, tostring(e.id))
	end
	return table.concat(out, ",")
end
local function eggOf(pr, id)
	for _, e in pr.clutch.list do
		if e.id == id then
			return e
		end
	end
	return nil
end
local function viewEgg(pl, id)
	local v = H.view(pl)
	for _, e in (v and v.clutch or {}) do
		if e.id == id then
			return e
		end
	end
	return nil
end
-- what the plot's Eggs attribute should say: "id.rarity" each, in the order laid
local function attrWant(pr)
	local out = {}
	for _, e in pr.clutch.list do
		table.insert(out, string.format("%d.%d", e.id, e.r) .. (if e.wx then "." .. e.wx else ""))
	end
	return table.concat(out, ";")
end
-- the middle of island `plot`'s tree on the lawn (world), from its piece
local function centreOf(pr, plot)
	local q = Tree.piece(pr)
	if q == nil then
		return E.v3(0, 0, 0)
	end
	local w, d = Plot.footprint(q.id, q.rot)
	local ox, oz = Street.origin(plot)
	return E.v3(ox + q.x + w / 2, Street.LAWN_Y, oz + q.z + d / 2)
end
local function treeIndex(pr)
	for i, q in pr.plot.placed do
		if q.id == Tree.ID then
			return i
		end
	end
	return 0
end
-- the eggs as the HUD's card and the panel order them: the rarest first, the oldest first among them; when the shells
-- cover none of the first `n`, the first they do cover in the last place
local function bestOf(v, n)
	local list = table.clone(v.clutch)
	table.sort(list, function(a, b)
		if a.r ~= b.r then
			return a.r > b.r
		end
		return a.id < b.id
	end)
	local out, can = {}, false
	for i = 1, math.min(n, #list) do
		table.insert(out, list[i])
		can = can or v.shells >= list[i].cost
	end
	if not can and #out > 0 then
		for i = n + 1, #list do
			if v.shells >= list[i].cost then
				out[#out] = list[i]
				break
			end
		end
	end
	return out
end
-- the panel's words for a rarity's odds
local function oddsWords(o)
	local pct = o * 100
	return if o <= 0 then "not yet" elseif pct < 0.1 then "<0.1%" elseif pct < 1 then string.format("%.1f%%", pct) else string.format("%d%%", math.round(pct))
end
-- what hatches from an egg of rarity r on an island of `tier`: that rarity, or the next commoner one any open kind has
local function hatchRarity(tier, r)
	local pool = Tree.pool(tier)
	while r > 1 and #pool[r] == 0 do
		r -= 1
	end
	return r
end

-- the driftlings
local function palOf(id)
	for _, x in prof.pals do
		if x.id == id then
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
local function newPal(ids0)
	for _, x in prof.pals do
		if not ids0[x.id] then
			return x
		end
	end
	return nil
end
local function pieceOf(uid)
	for _, q in prof.plot.placed do
		if q.uid == uid then
			return q
		end
	end
	return nil
end
-- at work at a workplace (any knack: its own first when one had room), or no free place anywhere
local function workingOrNoPlace(x)
	local d = Creatures.byId[x.sp]
	if x.work ~= 0 then
		local q = pieceOf(x.work)
		return q ~= nil and Island.works(q.id)
	end
	return Island.freeJob(prof, d.knack) == 0
end
local function housed()
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
-- the weakest driftling in a hut (the first a swap would offer)
local function weakest()
	local w = nil
	for _, x in prof.pals do
		if x.home ~= 0 and (w == nil or Tree.better(w, x)) then
			w = x
		end
	end
	return w
end
-- shells the island may earn in `secs` (its buildings sell while the checks run)
local function earnSlack(secs)
	return math.abs(Island.rates(prof).shells) / Tuning.TurnSeconds * (secs + 1) + 2
end

------------------------------------------------------------------ the checks
-- the view's eggs are the profile's (each with Tree.cost here), the plot's attribute too, and the clock
local function eggMirror(pl, label)
	local pr = H.profile(pl)
	local sess = H.session(pl)
	local v = H.view(pl)
	local same = v ~= nil and #v.clutch == #pr.clutch.list
	local bad = nil
	for i, e in pr.clutch.list do
		local c = v and v.clutch[i]
		if not (c and c.id == e.id and c.r == e.r and c.cost == Tree.cost(pr, e.r)) then
			same = false
			bad = bad or e.id
		end
	end
	H.expect(same, "mirror", label .. ": the view's eggs are the profile's (id, rarity, cost)", string.format("%d vs %d, first bad %s", v and #v.clutch or -1, #pr.clutch.list, tostring(bad)))
	local m = plotModel(sess.plot)
	H.expect(m ~= nil and m:GetAttribute("Eggs") == attrWant(pr), "mirror", label .. ": the plot's Eggs attribute is the profile's", m and tostring(m:GetAttribute("Eggs")))
	H.expect(v ~= nil and v.clutchSecs == Tree.secs(pr) and math.abs(v.clutchLeft - pr.clutch.left) <= 1.2, "mirror", label .. ": the view's clock (clutchSecs, clutchLeft within a tick)", v and string.format("%.2f / %.2f vs %.2f / %.2f", v.clutchLeft, v.clutchSecs, pr.clutch.left, Tree.secs(pr)))
end
local function checks(label)
	H.push(p, 0.3)
	H.checkProfile(p, label)
	H.checkMirror(p, label)
	eggMirror(p, label)
end

-- what a client draws of island `sess`'s eggs: each one the profile has (no others), on the lawn on the ring round the
-- tree's middle (EGG_RING), at one of the arc's evenly spaced places for the island's count (Tree.count), each at its
-- own place, the arc on the side the view looks at
local function drawnCheck(pl, sess, label)
	local c = clientOf(pl)
	local pr = sess.profile
	local plot = sess.plot
	local n = Tree.count(pr.tier)
	local centre = centreOf(pr, plot)
	local list = pr.clutch.list
	local cnt = H.inClient(pl, c.EV.count, plot)
	H.expect(cnt == #list, "drawn", label .. ": every egg under the tree drawn, and no others", string.format("%d drawn, %d laid", cnt, #list))
	local missing, offRing, offArc, offSlot, offLawn, shared = nil, nil, nil, nil, nil, nil
	local used = {}
	local behind, k0 = nil, 0
	for _, e in list do
		local w = H.inClient(pl, c.EV.where, plot, e.id)
		if w == nil then
			missing = missing or e.id
			continue
		end
		local dx, dz = w.X - centre.X, w.Z - centre.Z
		local dist = math.sqrt(dx * dx + dz * dz)
		local a = math.atan2(dx, dz)
		local k = (a - ARC0) / (ARC1 - ARC0) * (n - 1)
		if math.abs(dist - DecorModels.EGG_RING) > 0.02 then
			offRing = offRing or string.format("%d at %.2f", e.id, dist)
		end
		if a < ARC0 - 1e-3 or a > ARC1 + 1e-3 then
			offArc = offArc or string.format("%d at %.0f deg", e.id, math.deg(a))
		end
		if math.abs(k - math.round(k)) > 0.01 then
			offSlot = offSlot or string.format("%d at place %.2f of %d", e.id, k + 1, n)
		end
		if math.abs(w.Y - Street.LAWN_Y) > 0.01 then
			offLawn = offLawn or string.format("%d at y %.2f", e.id, w.Y)
		end
		local kk = math.round(k)
		if used[kk] then
			shared = shared or string.format("%d and %d at place %d", used[kk], e.id, kk + 1)
		end
		used[kk] = e.id
		local look = E.workspace.CurrentCamera.CFrame.LookVector
		local tl = math.max(math.sqrt(look.X * look.X + look.Z * look.Z), 1e-6)
		if (dx * -look.X + dz * -look.Z) / (math.max(dist, 1e-6) * tl) < -0.35 then
			behind = behind or tostring(e.id)
		end
		k0 += 1
	end
	H.expect(missing == nil, "drawn", label .. ": EggView.where knows each one", tostring(missing))
	H.expect(offRing == nil, "drawn", label .. ": each on the ring round the tree's middle (EGG_RING)", tostring(offRing))
	H.expect(offArc == nil, "drawn", label .. ": each on the arc round the tree's front", tostring(offArc))
	H.expect(offSlot == nil, "drawn", label .. ": each at one of the arc's evenly spaced places for the island's count", tostring(offSlot))
	H.expect(shared == nil, "drawn", label .. ": no two eggs at the same place", tostring(shared))
	H.expect(offLawn == nil, "drawn", label .. ": each lying on the lawn (risen)", tostring(offLawn))
	if k0 > 0 then
		-- (the arc's middle points back at the camera, level, and no egg lies on the far side of the trunk)
		local look = E.workspace.CurrentCamera.CFrame.LookVector
		local tl = math.max(math.sqrt(look.X * look.X + look.Z * look.Z), 1e-6)
		local mid = (ARC0 + ARC1) / 2
		local dot = (math.sin(mid) * -look.X + math.cos(mid) * -look.Z) / tl
		H.expect(dot > 0.95 and behind == nil, "drawn", label .. ": the arc on the side of the tree the view looks at", string.format("%.2f, behind: %s", dot, tostring(behind)))
	end
end

-- no price tags over any egg (the World canvas has no EggHatch_<id>): the eggs are bought in the tree's panel
local function tagCheck(pl, label, sharedCam)
	local c = clientOf(pl)
	local canvas = H.inClient(pl, c.UIKit.canvas, "World")
	local ntags = 0
	for _, g in canvas:GetDescendants() do
		if string.match(g.Name, "^EggHatch_(%d+)$") then
			ntags += 1
		end
	end
	H.expect(ntags == 0, "tags", label .. ": no price tags over the eggs", tostring(ntags))
	local _ = sharedCam
	return ntags
end

-- the HUD's card: Open, the time to the next lot (the server's clock, a tick behind at most) with its bar, and a row
-- for each of the best three (EggView.best): the egg, its rarity's name, its price (no buy button: a tap anywhere on the
-- card opens the tree's panel)
local function cardCheck(label)
	local v = H.view(p)
	local want = bestOf(v, 3)
	local card = gui(p, "TreeCard")
	H.expect(card ~= nil and H.guiVisible(card) and H.buttonNamed(p, "TreeOpen") ~= nil, "card", label .. ": the Tree of Life's card on the HUD with Open")
	if card == nil then
		return
	end
	H.expect(idsOf(want) == idsOf(H.inClient(p, C.EV.best, v, 3)), "card", label .. ": EggView.best: the rarest first, the oldest among them, one the shells cover last", idsOf(want))
	local badRow = nil
	for _, e in want do
		local b = card:FindFirstChild("CardPrice_" .. e.id, true)
		local nm = card:FindFirstChild("EggName_" .. e.id, true)
		local icon = card:FindFirstChild("EggIcon_" .. e.id, true)
		if not (b and b:IsA("TextLabel") and b.Text == Numbers.coins(e.cost) and nm and nm.Text == Traits.RARITY[e.r].name and icon) then
			badRow = badRow or string.format("%d: %s / %s", e.id, b and b:IsA("TextLabel") and b.Text or "no price", nm and nm.Text or "no name")
		end
	end
	H.expect(badRow == nil, "card", label .. ": each row's egg, rarity and price", tostring(badRow))
	H.expect(#named(p, "CardPrice_", false, card) == #want and #named(p, "EggName_", false, card) == #want, "card", label .. ": no other rows", string.format("%d rows, %d wanted", #named(p, "CardPrice_", false, card), #want))
	H.expect(#named(p, "CardHatch_", false, card) == 0 and card:FindFirstChild("TreeCardTap", true) ~= nil, "card", label .. ": no buy buttons; the card opens the tree's panel")
	if #want == 0 then
		H.expect(says(p, "No eggs right now"), "card", label .. ": no eggs: it says so")
	end
	local left, secs = H.inClient(p, C.SC.clutchLeft)
	local shownSecs = secsOf(labelText(p, "TreeNext"), "New eggs in ")
	H.expect(shownSecs ~= nil and math.abs(shownSecs - math.ceil(left)) <= 1, "card", label .. ": New eggs in m:ss, the time left", string.format("%s for %.1f s", tostring(labelText(p, "TreeNext")), left))
	H.expect(math.abs(left - prof.clutch.left) <= 1.2 and secs == Tree.secs(prof), "card", label .. ": the client's clock is the server's", string.format("%.2f / %.2f vs %.2f / %.2f", left, secs, prof.clutch.left, Tree.secs(prof)))
	local back = card:FindFirstChild("TreeBar", true)
	local fill = back and back:FindFirstChildWhichIsA("Frame")
	local wantW = back and math.floor((back.Size.X.Offset - 2) * math.clamp(left / math.max(1, secs), 0, 1) + 0.5)
	H.expect(fill ~= nil and math.abs(fill.Size.X.Offset - wantW) <= 1, "card", label .. ": its bar runs down to the next lot", fill and string.format("%d of %d", fill.Size.X.Offset, wantW) or "no bar")
end

-- the tree panel (open): how often it lays, the time to the next lot and its bar, the eggs a lot and the huts' room,
-- the odds now, and a row for every egg, the rarest first, each with Hatch and its price
local function panelCheck(label)
	local v = H.view(p)
	H.expect(H.currentPanel(p) == "tree" and labelText(p, "Title") ~= nil, "panel", label .. ": the tree panel is open", tostring(H.currentPanel(p)))
	local frame = gui(p, "Panel_tree")
	local title = frame and frame:FindFirstChild("Title", true)
	H.expect(title ~= nil and title.Text == "Tree of Life", "panel", label .. ": its title", title and title.Text)
	H.expect(labelText(p, "Pace") == "New eggs every " .. clock(Tree.secs(prof)), "panel", label .. ": how often it lays", tostring(labelText(p, "Pace")))
	local left = H.inClient(p, C.SC.clutchLeft)
	local nextSecs = secsOf(labelText(p, "Next"), "Next in ")
	H.expect(nextSecs ~= nil and math.abs(nextSecs - math.ceil(left)) <= 1 and math.abs(left - prof.clutch.left) <= 1.2, "panel", label .. ": Next in m:ss", string.format("%s, %.1f s on the server", tostring(labelText(p, "Next")), prof.clutch.left))
	H.expect(gui(p, "TreeBar") ~= nil, "panel", label .. ": the bar to the next lot")
	H.expect(labelText(p, "Room") == string.format("%d eggs a lot. In huts %d/%d", Tree.count(prof.tier), housed(), Island.nests(prof)), "panel", label .. ": the eggs a lot and the huts' room", tostring(labelText(p, "Room")))
	local odds = Tree.odds(prof)
	local badOdds = nil
	for r = 1, 5 do
		local l = gui(p, "Odds_" .. r)
		local words = nil
		if l then
			for _, sib in l.Parent:GetChildren() do
				if sib ~= l and sib:IsA("TextLabel") and sib.Position.Y.Offset == l.Position.Y.Offset and sib.Position.X.Offset > l.Position.X.Offset then
					words = sib.Text
				end
			end
		end
		if not (l and l.Text == Traits.RARITY[r].name and words == oddsWords(odds[r])) then
			badOdds = badOdds or string.format("%d: %s %s, want %s", r, l and l.Text or "none", tostring(words), oddsWords(odds[r]))
		end
	end
	H.expect(badOdds == nil, "panel", label .. ": the odds of each rarity now (Tree.odds)", tostring(badOdds))
	H.expect(labelText(p, "Eggs") == "Under the tree", "panel", label .. ": the eggs' header", tostring(labelText(p, "Eggs")))
	local want = bestOf(v, #v.clutch)
	local badRow, prevOrder, ordered = nil, -math.huge, true
	for _, e in want do
		local row = gui(p, "Egg_" .. e.id)
		local b = H.buttonNamed(p, "PanelHatch_" .. e.id, true)
		local nm = row and row:FindFirstChild("Name")
		if not (row and H.guiVisible(row) and b and string.find(buttonText(b), Numbers.coins(e.cost), 1, true) and nm and nm.Text == Traits.RARITY[e.r].name .. " egg") then
			badRow = badRow or string.format("%d: %s", e.id, buttonText(b))
		end
		if row then
			ordered = ordered and row.LayoutOrder > prevOrder
			prevOrder = row.LayoutOrder
		end
	end
	H.expect(badRow == nil, "panel", label .. ": a row for every egg: its rarity, Hatch with its price", tostring(badRow))
	H.expect(ordered, "panel", label .. ": the rarest first")
	H.expect(#named(p, "Egg_", true) == #v.clutch, "panel", label .. ": no other rows", string.format("%d rows, %d eggs", #named(p, "Egg_", true), #v.clutch))
	if #v.clutch == 0 then
		H.expect(says(p, "No eggs left. The tree lays more soon."), "panel", label .. ": no eggs: it says so")
	end
end

-- tap the screen on egg `id` of island `plot` (its middle, as a player's tap arrives: below the top bar), through
-- WorldView's taps; true when it was drawn there
local function tapEgg(pl, plot, id)
	local c = clientOf(pl)
	return H.inClient(pl, function()
		local w = c.EV.where(plot, id)
		if w == nil then
			return false
		end
		local pos = c.PR.project(w + E.v3(0, 0.6, 0))
		c.WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
		return true
	end)
end

-- one egg hatched: the before (driftlings, shells, the time, Fx, taken, where it lay) and what should follow: paid for,
-- the egg gone (server, view, attribute), a driftling of its rarity in a hut and at work, taken counted, the Index, Fx
-- hatched; then the client: the egg cracks where it lay (EggView.hatchPoint), its tag and card row gone
local function before(e)
	return { ids = palIds(), shells = prof.shells, t = E.now(), fx = #W.fx, taken = prof.stats.taken, sold = prof.stats.sold, n = #prof.pals, spot = H.inClient(p, C.EV.where, s.plot, e.id), drawn = H.inClient(p, C.EV.count, s.plot), cost = Tree.cost(prof, e.r) }
end
local function hatched(label, e, b, opts)
	opts = opts or {}
	local x = newPal(b.ids)
	local sold = opts.sold or 0
	H.expect(x ~= nil, "hatch", label .. ": a driftling hatched", tostring(e.id))
	H.expect(eggOf(prof, e.id) == nil and viewEgg(p, e.id) == nil and not string.find(";" .. tostring(plotModel(s.plot):GetAttribute("Eggs")) .. ";", ";" .. e.id .. ".", 1, true), "hatch", label .. ": the egg gone (server, view, attribute)")
	H.expect(math.abs((b.shells - prof.shells) - (b.cost - sold)) <= earnSlack(E.now() - b.t), "hatch", label .. ": its price paid in shells" .. (if sold > 0 then ", the swapped one's back" else ""), string.format("%.1f -> %.1f, cost %d, sold %d", b.shells, prof.shells, b.cost, sold))
	H.expect(prof.stats.taken == b.taken + 1 and prof.stats.sold == b.sold + (if sold > 0 then 1 else 0), "hatch", label .. ": stats.taken counts it", string.format("taken %d sold %d", prof.stats.taken, prof.stats.sold))
	if x == nil then
		return nil
	end
	local d = Creatures.byId[x.sp]
	local hf0 = fxSince(W, b.fx, "hatched")
	local hr = hf0[1] and type(hf0[1].msg.data) == "table" and hf0[1].msg.data.hr or 0
	H.expect(d ~= nil and hr >= e.r and d.rarity == hatchRarity(prof.tier, hr), "hatch", label .. ": one of the rarity the egg hatched as (its own, or rarer: Tree.rise)", string.format("%s (%s) from a rarity %d egg hatched as %d", x.sp, d and tostring(d.rarity) or "?", e.r, hr))
	H.expect(x.home ~= 0 and (opts.home == nil or x.home == opts.home), "hatch", label .. ": into a hut" .. (if opts.home then " (the one expected)" else ""), string.format("home %d, want %s", x.home, tostring(opts.home)))
	H.expect(workingOrNoPlace(x), "hatch", label .. ": at work (or no free place anywhere)", string.format("%s work %d", x.sp, x.work))
	H.expect(prof.seen[x.sp] == 2, "hatch", label .. ": in the Index", tostring(prof.seen[x.sp]))
	local hf = fxSince(W, b.fx, "hatched")
	local data = hf[1] and hf[1].msg.data
	H.expect(#hf == 1 and type(data) == "table" and data.id == x.id and data.sp == x.sp and data.egg == e.id and data.r == e.r and data.cost == b.cost and data.sold == sold and data.swapped == (opts.swapped or 0), "hatch", label .. ": Fx hatched: its id, kind, egg, rarity, cost, sold and swapped", data and string.format("id %s egg %s r %s cost %s sold %s swapped %s", tostring(data.id), tostring(data.egg), tostring(data.r), tostring(data.cost), tostring(data.sold), tostring(data.swapped)) or tostring(#hf))
	-- the client
	E.run(0.6)
	H.expect(H.inClient(p, C.EV.count, s.plot) == b.drawn - 1, "hatch", label .. ": one egg fewer drawn", string.format("%d, was %d", H.inClient(p, C.EV.count, s.plot), b.drawn))
	local hx, hz = H.inClient(p, C.EV.hatchPoint, s.plot)
	H.expect(b.spot ~= nil and math.abs(hx - b.spot.X) < 1e-3 and math.abs(hz - b.spot.Z) < 1e-3, "hatch", label .. ": what hatched steps out where the egg lay (EggView.hatchPoint)", b.spot and string.format("%.2f,%.2f vs %.2f,%.2f", hx, hz, b.spot.X, b.spot.Z) or "not drawn")
	H.expect(gui(p, "CardPrice_" .. e.id) == nil, "hatch", label .. ": its card row gone")
	E.run(1)
	H.expect(H.inClient(p, C.EV.where, s.plot, e.id) == nil, "hatch", label .. ": it cracked open and is gone")
	H.expect(H.inClient(p, C.WV.ownCount) == housed(), "hatch", label .. ": walking the island from its hut", string.format("%d walking, %d in huts", H.inClient(p, C.WV.ownCount), housed()))
	return x
end

-- a lot just laid (at `at`, the Fx log from `f0`, the whole views from `st0`): a whole lot of Tree.count eggs with the
-- next ids, none of `old` left, the clock set to Tree.secs, Fx eggs with the lot and its prices (more 0), a whole view,
-- the HUD saying so (`said`: other words that say it, when a panel was open)
local function lotCheck(label, at, old, next0, f0, st0, said)
	local wantIds = {}
	for id = next0, next0 + Tree.count(prof.tier) - 1 do
		table.insert(wantIds, tostring(id))
	end
	local kept = 0
	for _, e in old do
		if eggOf(prof, e.id) then
			kept += 1
		end
	end
	H.expect(at ~= nil and #prof.clutch.list == Tree.count(prof.tier) and idsOf(prof.clutch.list) == table.concat(wantIds, ","), "lot", label .. ": a whole new lot, Tree.count eggs with the next ids", idsOf(prof.clutch.list))
	H.expect(kept == 0, "lot", label .. ": none of the eggs left before it kept", tostring(kept))
	H.expect(at ~= nil and math.abs(prof.clutch.left - (Tree.secs(prof) - (E.now() - at))) <= 0.15, "lot", label .. ": the clock set again to Tree.secs", string.format("%.2f", prof.clutch.left))
	E.run(0.3)
	local ef = fxSince(W, f0, "eggs")
	local ok = #ef == 1 and type(ef[1].msg.laid) == "table" and ef[1].msg.more == 0 and #ef[1].msg.laid == #prof.clutch.list
	if ok then
		for i, e in prof.clutch.list do
			local l = ef[1].msg.laid[i]
			ok = ok and l.id == e.id and l.r == e.r and l.cost == Tree.cost(prof, e.r)
		end
	end
	H.expect(ok, "lot", label .. ": Fx eggs: the new lot with its prices, more 0", tostring(#ef))
	H.expect(W.states > st0, "lot", label .. ": and a whole view")
	local best = 1
	for _, e in prof.clutch.list do
		best = math.max(best, e.r)
	end
	H.expect(says(p, said or (if best >= 4 then "egg is waiting under the tree" else "The Tree of Life laid new eggs.")), "lot", label .. ": the HUD says the tree laid", said)
end

-- the time the server's step laid the next lot: wait for it (no longer than `timeout`)
local function waitLot(timeout)
	local next0 = prof.clutch.next
	local list0 = table.clone(prof.clutch.list)
	local at = nil
	E.runUntil(function()
		if prof.clutch.next ~= next0 or idsOf(prof.clutch.list) ~= idsOf(list0) then
			at = at or E.now()
			return true
		end
		return false
	end, timeout, 0.1)
	return at, list0, next0
end

------------------------------------------------------------------ 1. a new island: its tree and its first lot
E.phase = "join"
H.push(p, 0.6)
E.run(RISEN)
H.expect(s ~= nil and s.ready and prof.tut == 1 and #prof.pals == 0 and prof.stats.taken == 0, "join", "a new island: the tips at step 1, no driftlings yet", string.format("tut %d, %d pals", prof.tut, #prof.pals))
-- the tree: one piece of its own kind, never in the limit, its model by its stage
local tq = Tree.piece(prof)
local nTrees = 0
for _, q in prof.plot.placed do
	if q.id == Tree.ID then
		nTrees += 1
	end
end
H.expect(tq ~= nil and nTrees == 1 and Buildings.byId.tree.kind == "tree" and Plot.isFixed("tree"), "tree", "a new island's Tree of Life planted: one piece, kind tree, fixed", tostring(nTrees))
H.expect(#prof.plot.placed == 1 and (Plot.used(prof, "torch")) == 0, "tree", "the only piece, and not counted in the piece limit", string.format("%d placed, %d used", #prof.plot.placed, (Plot.used(prof, "torch"))))
local decor = plotModel(s.plot):FindFirstChild("Decor", true)
local function treeModel()
	local q = Tree.piece(prof)
	return decor and q and decor:FindFirstChild(string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, Tree.stage(prof.tier)))
end
H.expect(treeModel() ~= nil and treeModel():GetAttribute("Decor") == "tree", "tree", "its model on the island, by its stage (Tree.stage)", tostring(Tree.stage(prof.tier)))
-- the first lot, laid when the player arrived
local c0 = prof.clutch
H.expect(Tree.count(1) == 5 and #c0.list == Tree.count(1), "eggs", "the first lot laid at once: Tree.count(1), five eggs", tostring(#c0.list))
H.expect(idsOf(c0.list) == "1,2,3,4,5" and c0.next == 6, "eggs", "their ids 1 to 5, the next 6", idsOf(c0.list))
local commons = 0
for _, e in c0.list do
	if e.r == 1 then
		commons += 1
	end
end
H.expect(c0.list[2] ~= nil and c0.list[1].r == 1 and c0.list[2].r == 1 and commons >= 2, "eggs", "a new island's first lot: two commons first", string.format("%d commons", commons))
H.expect(Tree.secs(prof) == Tuning.EggSecs, "eggs", "no huts: a lot every EggSecs", tostring(Tree.secs(prof)))
local layAt = E.now() - (Tree.secs(prof) - c0.left) -- when the first lot was laid
H.expect(layAt >= joinT and layAt <= joinT + 2.2, "eggs", "laid when the player arrived", string.format("%.2f s after the join", layAt - joinT))
local cheap = 0
for _, e in c0.list do
	if e.r == 1 then
		cheap += Tree.cost(prof, 1)
	end
end
H.expect(Tree.cost(prof, 1) == Tuning.EggPrice[1] * Tuning.EggTier[1] and 2 * Tree.cost(prof, 1) <= Tuning.StartShells, "eggs", "a common egg costs EggPrice[1]: the starting shells hatch the two", tostring(Tree.cost(prof, 1)))
-- the attribute, read back
local m1 = plotModel(s.plot)
local parsed, attrOk = 0, true
for entry in string.gmatch(tostring(m1:GetAttribute("Eggs") or ""), "[^;]+") do
	local id, r = string.match(entry, "^(%d+)%.(%d)%.?%a*$")
	local e = id and eggOf(prof, tonumber(id))
	attrOk = attrOk and e ~= nil and e.r == tonumber(r)
	parsed += 1
end
H.expect(attrOk and parsed == #c0.list, "eggs", "the plot's Eggs attribute reads back as id.rarity", tostring(m1:GetAttribute("Eggs")))
H.expect(m1:GetAttribute("Tide") == nil, "eggs", "no Tide attribute any more")
eggMirror(p, "join")
drawnCheck(p, s, "join")
tagCheck(p, "join")
cardCheck("join")
local n1s = secsOf(labelText(p, "TreeNext"), "New eggs in ")
E.run(3)
local n2s = secsOf(labelText(p, "TreeNext"), "New eggs in ")
H.expect(n1s ~= nil and n2s ~= nil and n1s - n2s >= 2 and n1s - n2s <= 4, "card", "join: New eggs in m:ss counts down", string.format("%s then %s", tostring(n1s), tostring(n2s)))
H.expect(tostring(gui(p, "Tips") and gui(p, "Tips"):FindFirstChild("Words") and gui(p, "Tips").Words:GetAttribute("Source")) == "Wood pays for everything you build. Tap Build and place a Lumber Camp.", "join", "the first tip")
-- Fx tick every second: the clock running down, and the seconds between two lots
local i0 = #W.fx
E.run(3.2)
local ticks = fxSince(W, i0, "tick")
local tickOk, prevLeft = #ticks >= 3, nil
for _, f in ticks do
	tickOk = tickOk and f.msg.clutchSecs == Tree.secs(prof) and type(f.msg.clutchLeft) == "number" and f.msg.tideSecs == nil
	if prevLeft then
		tickOk = tickOk and math.abs((prevLeft - f.msg.clutchLeft) - 1) < 0.15
	end
	prevLeft = f.msg.clutchLeft
end
H.expect(tickOk, "eggs", "Fx tick: clutchLeft a second less each time, clutchSecs", string.format("%d ticks", #ticks))
H.expect(prevLeft ~= nil and math.abs(prevLeft - prof.clutch.left) <= 1.2, "eggs", "the tick's clock is the server's", string.format("%s vs %.2f", tostring(prevLeft), prof.clutch.left))
checks("join")

------------------------------------------------------------------ 2. the tree stays: never cleared away, bought or replaced; moved like any piece
E.phase = "piece"
local ti = treeIndex(prof)
local placed0 = #prof.plot.placed
H.expect(rawErr(p, "plot.store", { i = ti }) == "fixed", "piece", "clearing the tree away: fixed")
H.expect(H.inClient(p, C.Words.errText, "fixed") == "The Tree of Life stays on your island. You can move it.", "piece", "and the words for it")
local sx, sz = Plot.spot(prof.tier, prof.plot.placed, "tree", 14, 14, 0)
H.expect(rawErr(p, "plot.place", { id = "tree", x = sx or 0, z = sz or 0, rot = 0 }) == "bad_payload", "piece", "placing another tree: bad_payload")
H.expect(rawErr(p, "plot.replace", { i = ti, id = "nest" }) == "bad_payload" and rawErr(p, "plot.replace", { i = ti, id = "tree" }) == "bad_payload", "piece", "replacing the tree (with a hut, with itself): bad_payload")
H.expect(#Plot.replacements(tq, prof.tier) == 0, "piece", "nothing to replace it with")
H.expect(#prof.plot.placed == placed0 and Tree.piece(prof) == tq and prof.plot.placed[ti] == tq, "piece", "nothing changed")
-- Build mode: the tree picked up can be moved, not cleared away or replaced; no tab offers one
H.expect(H.clickNamed(p, "Menu_build"), "piece", "the HUD's Build button")
local centre = centreOf(prof, s.plot)
E.raycastParts = true
H.inClient(p, function()
	local pos = C.PR.project(centre + E.v3(0, 0.3, 0))
	C.BuildUI.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
end)
E.raycastParts = nil
E.run(0.3)
local storeB = H.buttonNamed(p, "Store", true)
H.expect(labelText(p, "What") == "Moving: Tree of Life", "piece", "a tap on the tree picks it up", tostring(labelText(p, "What")))
H.expect(storeB ~= nil and storeB.AutoButtonColor == false and H.buttonNamed(p, "Replace", true) == nil and H.buttonNamed(p, "Place", true) ~= nil, "piece", "Move here, Clear away off, no Replace")
H.clickNamed(p, "Cancel", { wait = 0.2 })
local trayTree = false
for _, t in { "farm", "wood", "shop", "nest", "gen", "path", "decor" } do
	H.clickNamed(p, "Tab_" .. t, { wait = 0.2, optional = true })
	trayTree = trayTree or H.buttonNamed(p, "Buy_tree", true) ~= nil
end
H.expect(not trayTree, "piece", "no tab offers a tree to buy")
H.clickNamed(p, "BuildDone", { wait = 0.3 })
-- moved: the eggs go with it
local rest = {}
for i, q in prof.plot.placed do
	if i ~= ti then
		table.insert(rest, q)
	end
end
local nx, nz = nil, nil
for _, at in { { 14, 10 }, { -18, 8 }, { 10, -14 }, { 16, 2 } } do
	local x, z = Plot.spot(prof.tier, rest, "tree", at[1], at[2], 90)
	if x and (x ~= tq.x or z ~= tq.z) then
		nx, nz = x, z
		break
	end
end
local ox0, oz0 = tq.x, tq.z
local res = H.req(p, "plot.move", { i = ti, x = nx or ox0, z = nz or oz0, rot = 90 })
H.expect(res.ok and nx ~= nil and tq.x == nx and tq.z == nz and tq.rot == 90, "piece", "moving the tree: allowed", tostring(res.err))
E.run(1.2)
H.expect(treeModel() ~= nil, "piece", "its model where it went")
drawnCheck(p, s, "moved")
tagCheck(p, "moved")
res = H.req(p, "plot.move", { i = ti, x = ox0, z = oz0, rot = 0 })
E.run(1.2)
H.expect(res.ok and tq.x == ox0 and tq.z == oz0, "piece", "and back", tostring(res.err))
drawnCheck(p, s, "moved back")
-- the piece limit: the island fills with Plot.limit pieces besides the tree
prof.wood = 1e5
H.push(p, 0.3)
local limit = Plot.limit(prof.tier)
local guard = 0
while (Plot.used(prof, "torch")) < limit and guard < 80 do
	guard += 1
	local x, z = Plot.spot(prof.tier, prof.plot.placed, "torch", 20, 20, 0)
	if x == nil then
		break
	end
	H.req(p, "plot.place", { id = "torch", x = x, z = z, rot = 0 })
	E.run(0.1)
end
H.expect((Plot.used(prof, "torch")) == limit and #prof.plot.placed == limit + 1, "piece", "the island holds its limit of pieces and the tree besides", string.format("%d used, %d placed, limit %d", (Plot.used(prof, "torch")), #prof.plot.placed, limit))
local lx, lz = Plot.spot(prof.tier, prof.plot.placed, "torch", 20, 20, 0)
H.expect(rawErr(p, "plot.place", { id = "torch", x = lx or 20, z = lz or 20, rot = 0 }) == "full", "piece", "and no more: full")
for i = #prof.plot.placed, 1, -1 do
	if prof.plot.placed[i].id == "torch" then
		H.req(p, "plot.store", { i = i })
		E.run(0.1)
	end
end
H.expect(#prof.plot.placed == 1 and Tree.piece(prof) ~= nil, "piece", "the torches cleared away, the tree stays", tostring(#prof.plot.placed))
prof.wood = Tuning.StartWood
E.run(0.5)
checks("piece")

------------------------------------------------------------------ 3. refusals before a hut
E.phase = "refuse"
local first = prof.clutch.list[1]
local sh0 = prof.shells
H.expect(rawErr(p, "egg.hatch", { id = first.id, swap = 0 }) == "no_hut", "refuse", "no hut yet: no_hut")
H.expect(rawErr(p, "egg.hatch", { id = 99999, swap = 0 }) == "not_found", "refuse", "an egg never laid: not_found")
H.expect(rawErr(p, "egg.hatch", { id = 0, swap = 0 }) == "not_found", "refuse", "id 0: not_found")
local bad = {
	{ "a string id", { id = tostring(first.id), swap = 0 } },
	{ "no swap", { id = first.id } },
	{ "no id", { swap = 0 } },
	{ "an extra field", { id = first.id, swap = 0, r = 5 } },
	{ "a negative id", { id = -1, swap = 0 } },
	{ "a fraction", { id = 1.5, swap = 0 } },
	{ "a huge id", { id = 2e6, swap = 0 } },
	{ "a string swap", { id = first.id, swap = "x" } },
	{ "a negative swap", { id = first.id, swap = -3 } },
	{ "a boolean id", { id = true, swap = 0 } },
	{ "a table id", { id = {}, swap = 0 } },
	{ "a list", { first.id, 0 } },
	{ "a string payload", "hatch" },
	{ "a number payload", 42 },
}
for _, b in bad do
	local err = rawErr(p, "egg.hatch", b[2])
	H.expect(err == "bad_payload", "refuse", "a malformed payload (" .. b[1] .. "): bad_payload", err)
end
H.expect(rawErr(p, "egg.hatch", nil) == "bad_payload", "refuse", "no payload: bad_payload")
H.expect(rawErr(p, "tide.take", { id = first.id, swap = 0 }) ~= "ok", "refuse", "the old tide.take is gone")
H.expect(#prof.clutch.list == 5 and #prof.pals == 0 and prof.stats.taken == 0 and math.abs(prof.shells - sh0) < 1, "refuse", "nothing changed (the lot still whole)", string.format("%d eggs, %d pals", #prof.clutch.list, #prof.pals))
-- the client asking for one with no hut: refused, said so
H.inClient(p, C.EV.hatch, first.id)
E.run(0.2)
H.expect(says(p, C.Words.errText("no_hut")) and #prof.pals == 0, "refuse", "the client says why", tostring(C.Words.errText("no_hut")))
checks("refuse")

------------------------------------------------------------------ 4. the tips' buildings, then a shell short
E.phase = "build"
res = place("lumber")
H.expect(res.ok and prof.tut == 2, "build", "a lumber camp: the tips move on to the farm", string.format("%s tut %d", tostring(res.err), prof.tut))
local lumberUid = res.data and res.data.uid
res = place("patch")
H.expect(res.ok and prof.tut == 3, "build", "a veggie patch: on to the hut", string.format("%s tut %d", tostring(res.err), prof.tut))
local patchUid = res.data and res.data.uid
res = place("nest")
H.expect(res.ok and prof.tut == 4, "build", "a hut: on to hatching an egg", string.format("%s tut %d", tostring(res.err), prof.tut))
local hutUid = res.data and res.data.uid
H.push(p, 0.4)
H.expect(tostring(gui(p, "Tips") and gui(p, "Tips").Words:GetAttribute("Source")) == "The Tree of Life laid eggs round its roots. Tap the tree to pick one to hatch.", "build", "the tip: hatch an egg")
H.expect(Tree.room(prof) == Buildings.byId.nest.slots, "build", "the hut's room", tostring(Tree.room(prof)))
local keepShells = prof.shells
prof.shells = Tree.cost(prof, first.r) - 1
H.push(p, 0.3)
H.expect(rawErr(p, "egg.hatch", { id = first.id, swap = 0 }) == "money", "build", "a shell short: money")
H.expect(#prof.pals == 0 and eggOf(prof, first.id) ~= nil, "build", "nothing hatched, the egg still there")
prof.shells = keepShells
checks("build")

------------------------------------------------------------------ 5. hatching: the card, a world tag, the egg itself, the panel
E.phase = "hatch"
H.push(p, 0.3)
local v = H.view(p)
-- (from the card: a row the shells cover)
local pick = nil
for _, e in bestOf(v, 3) do
	if pick == nil and v.shells >= e.cost then
		pick = e
	end
end
H.expect(pick ~= nil, "hatch", "the card offers an egg the shells cover")
pick = pick or prof.clutch.list[1]
local b = before(pick)
H.expect(H.clickNamed(p, "TreeCardTap", { wait = 0.4 }) and H.currentPanel(p) == "tree" and prof.stats.taken == b.taken, "hatch", "a tap on the card opens the tree's panel, nothing bought", tostring(H.currentPanel(p)))
H.expect(H.clickNamed(p, "PanelHatch_" .. pick.id, { wait = 0.6 }), "hatch", "Hatch on the egg the card showed")
local x1 = hatched("card", pick, b, { home = hutUid })
H.expect(x1 ~= nil and Creatures.byId[x1.sp].knack == "wood" and x1.work == lumberUid, "hatch", "a new island's first hatchling: good with wood, at the lumber camp", x1 and string.format("%s at %d", x1.sp, x1.work))
H.expect(prof.tut == 5, "hatch", "the tips on to the shop", tostring(prof.tut))
H.expect(says(p, "It hatched") and H.currentPanel(p) == "tree", "hatch", "the panel there again after the hatch scene, saying what hatched")
H.closePanel(p)
tagCheck(p, "card")
cardCheck("card")
-- (from the card's Open: the cheapest the shells cover)
local tagPick = nil
for _, e in prof.clutch.list do
	if Tree.cost(prof, e.r) <= prof.shells and (tagPick == nil or e.r < tagPick.r) then
		tagPick = e
	end
end
H.expect(tagPick ~= nil, "hatch", "an egg the shells cover")
tagPick = tagPick or prof.clutch.list[1]
b = before(tagPick)
local found, vis = tap(p, "TreeOpen")
H.expect(found and vis and H.currentPanel(p) == "tree", "hatch", "the card's Open opens the tree's panel")
H.expect(H.clickNamed(p, "PanelHatch_" .. tagPick.id, { wait = 0.6 }), "hatch", "Hatch on it")
local x2 = hatched("the card's Open", tagPick, b, { home = hutUid })
H.closePanel(p)
H.expect(x2 ~= nil and Creatures.byId[x2.sp].knack == "farm" and x2.work == patchUid, "hatch", "the second: at a farm, at the veggie patch", x2 and string.format("%s at %d", x2.sp, x2.work))
H.expect(Tree.room(prof) == 0, "hatch", "the hut full", tostring(Tree.room(prof)))
-- (a second hut; a tap on the lawn hatches nothing, a tap on an egg hatches it)
prof.wood = math.max(prof.wood, Buildings.byId.nest.wood + 10)
prof.shells = 50000
H.push(p, 0.3)
res = place("nest")
local hut2 = res.data and res.data.uid
H.expect(res.ok and Tree.room(prof) == Buildings.byId.nest.slots, "hatch", "a second hut", tostring(res.err))
local taken0 = prof.stats.taken
local nothing = H.inClient(p, function()
	local ox, oz = Street.origin(s.plot)
	local pos = C.PR.project(E.v3(ox + Street.CENTER.x, Street.LAWN_Y, oz + Street.CENTER.z))
	return C.EV.tapAt(E.v2(pos.X, pos.Y - E.inset))
end)
H.inClient(p, function()
	local pos = C.PR.project(centre + E.v3(0, 0, -DecorModels.EGG_RING))
	C.WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.run(0.6)
H.expect(nothing == false and prof.stats.taken == taken0 and H.currentPanel(p) == nil, "hatch", "a tap on the lawn (by the plaza, behind the tree) hatches nothing")
local tapPick = nil
for _, e in prof.clutch.list do
	local on = H.inClient(p, function()
		local w = C.EV.where(s.plot, e.id)
		local _, o = C.PR.project(w)
		return o
	end)
	if on and (tapPick == nil or e.r > tapPick.r) then
		tapPick = e
	end
end
H.expect(tapPick ~= nil, "hatch", "an egg on screen")
tapPick = tapPick or prof.clutch.list[1]
b = before(tapPick)
H.expect(tapEgg(p, s.plot, tapPick.id), "hatch", "a tap on the egg itself")
E.run(0.6)
H.expect(H.currentPanel(p) == "tree" and prof.stats.taken == b.taken and eggOf(prof, tapPick.id) ~= nil, "hatch", "a tap on the egg opens the tree's panel and buys nothing", tostring(H.currentPanel(p)))
H.expect(H.clickNamed(p, "PanelHatch_" .. tapPick.id, { wait = 0.6 }), "hatch", "Hatch on the egg tapped")
hatched("tapping the egg", tapPick, b, { home = hut2 })
H.closePanel(p)
-- (from the tree panel: Open on the card)
H.expect(H.clickNamed(p, "TreeOpen", { wait = 0.4 }), "hatch", "the card's Open")
panelCheck("open")
H.expect(not H.guiVisible(gui(p, "TreeCard")), "hatch", "the HUD's card steps aside for the panel")
v = H.view(p)
local panelPick = bestOf(v, #v.clutch)[1]
b = before(panelPick)
H.expect(panelPick ~= nil and H.clickNamed(p, "PanelHatch_" .. panelPick.id, { wait = 0.6 }), "hatch", "Hatch on the tree panel")
hatched("the panel", panelPick, b, { home = hut2 })
H.expect(H.currentPanel(p) == "tree" and gui(p, "Egg_" .. panelPick.id) == nil, "hatch", "the panel stays open without it")
H.expect(says(p, "It hatched"), "hatch", "the panel's status line says what hatched")
panelCheck("after")
H.closePanel(p)
H.expect(H.guiVisible(gui(p, "TreeCard")), "hatch", "the card back once it closes")
H.openPanel(p, "pals")
local openTree = H.buttonNamed(p, "OpenTree")
H.expect(openTree ~= nil and string.find(buttonText(openTree), "Eggs", 1, true) ~= nil and H.clickNamed(p, "OpenTree", { wait = 0.4 }) and H.currentPanel(p) == "tree", "hatch", "the Driftlings panel's Eggs opens the tree panel", buttonText(openTree))
H.closePanel(p)
H.expect(Tree.room(prof) == 0 and #prof.clutch.list == 1, "hatch", "every hut full, one egg left", string.format("room %d, %d eggs", Tree.room(prof), #prof.clutch.list))
checks("hatch")

------------------------------------------------------------------ 6. every hut full: the swap picker
E.phase = "full"
local last = prof.clutch.list[1]
-- (the server first: no swap, a swap that isn't theirs, one that is a hut)
H.expect(rawErr(p, "egg.hatch", { id = last.id, swap = 0 }) == "full", "full", "every hut full and no swap: full")
H.expect(rawErr(p, "egg.hatch", { id = last.id, swap = 99999 }) == "bad_payload", "full", "a swap that isn't a driftling: bad_payload")
H.expect(rawErr(p, "egg.hatch", { id = last.id, swap = hutUid }) == "bad_payload", "full", "a swap that is a hut: bad_payload")
H.expect(rawErr(p, "egg.hatch", { id = 99999, swap = prof.pals[1].id }) == "not_found", "full", "a swap for an egg never laid: not_found")
H.expect(#prof.pals == 4 and eggOf(prof, last.id) ~= nil and prof.stats.sold == 0, "full", "nothing changed")
local n0 = #prof.pals
H.expect(H.clickNamed(p, "TreeCardTap", { wait = 0.4 }) and H.clickNamed(p, "PanelHatch_" .. last.id, { wait = 0.6 }), "full", "Hatch in the panel the card opens")
H.expect(#prof.pals == n0 and eggOf(prof, last.id) ~= nil, "full", "refused (full): nothing hatched")
H.expect(H.currentPanel(p) == "tree" and #named(p, "SwapOut_", true) == housed(), "full", "the tree panel opens on the swap picker: a row for each in a hut", string.format("%s, %d rows", tostring(H.currentPanel(p)), #named(p, "SwapOut_", true)))
local hutPals = {}
for _, x in prof.pals do
	if x.home ~= 0 then
		table.insert(hutPals, x)
	end
end
table.sort(hutPals, function(a, c)
	return Tree.better(c, a)
end)
local swapOk, prevO = true, -math.huge
for _, x in hutPals do
	local row = gui(p, "SwapOut_" .. x.id)
	swapOk = swapOk and row ~= nil and H.guiVisible(row) and H.buttonNamed(p, "SwapTake_" .. x.id) ~= nil and row.LayoutOrder > prevO
	prevO = row and row.LayoutOrder or prevO
end
H.expect(swapOk, "full", "each with Swap, the weakest first")
H.expect(says(p, string.lower(Traits.RARITY[last.r].name) .. " egg"), "full", "it names the egg")
H.expect(not H.guiVisible(gui(p, "TreeCard")), "full", "the HUD's card steps aside")
H.expect(H.clickNamed(p, "Back", { wait = 0.4 }) and H.currentPanel(p) == "tree" and #named(p, "SwapOut_", true) == 0 and gui(p, "Egg_" .. last.id) ~= nil, "full", "Back: the list again")
H.expect(H.clickNamed(p, "PanelHatch_" .. last.id, { wait = 0.6 }) and #named(p, "SwapOut_", true) == housed(), "full", "Hatch on the list: the picker again")
local out = hutPals[1]
local price, outHome = Tree.price(out), out.home
b = before(last)
H.expect(H.clickNamed(p, "SwapTake_" .. out.id, { wait = 0.6 }), "full", "Swap on the weakest")
H.expect(palOf(out.id) == nil, "full", "the swapped one is gone")
local y = hatched("a swap", last, b, { home = outHome, sold = price, swapped = out.id })
H.expect(y ~= nil and #prof.pals == n0, "full", "one in, one sold", tostring(#prof.pals))
H.expect(H.currentPanel(p) == "tree" and #named(p, "SwapOut_", true) == 0, "full", "the panel back on the list")
H.expect(says(p, "sold for " .. Numbers.coins(price)), "full", "and says what the swapped one sold for")
-- the lot hatched down: none left
H.expect(#prof.clutch.list == 0 and m1:GetAttribute("Eggs") == "" and H.inClient(p, C.EV.count, s.plot) == 0, "full", "the whole lot hatched: no eggs left (server, attribute, drawn)", string.format("%d, %s", #prof.clutch.list, tostring(m1:GetAttribute("Eggs"))))
panelCheck("none left")
H.closePanel(p)
cardCheck("none left")
tagCheck(p, "none left")
checks("full")

------------------------------------------------------------------ 7. new lots on the tree's clock
E.phase = "lot"
-- (the clock never stopped or started again for a hatch: the next lot is due Tree.secs after the first)
H.expect(math.abs((E.now() + prof.clutch.left) - (layAt + Tuning.EggSecs)) <= 0.25, "lot", "the clock ran on through every hatch: the next lot due EggSecs after the first", string.format("due at %.2f, want %.2f", E.now() + prof.clutch.left, layAt + Tuning.EggSecs))
local due = E.now() + prof.clutch.left
local f0, st0 = #W.fx, W.states
local at, old, next0 = waitLot(prof.clutch.left + 2)
H.expect(at ~= nil and math.abs(at - due) <= 0.15, "lot", "a hatched-down lot replaced on time", at and string.format("%.2f vs %.2f", at, due) or "none")
H.expect(next0 == 6, "lot", "after the first lot (ids 1 to 5)", tostring(next0))
lotCheck("hatched down", at, old, next0, f0, st0)
E.run(RISEN)
eggMirror(p, "lot 2")
drawnCheck(p, s, "lot 2")
tagCheck(p, "lot 2")
cardCheck("lot 2")
checks("lot 2")
-- the next lot replaces every egg left unhatched, while the swap picker is open on one of them
local lot2 = table.clone(prof.clutch.list)
local picked = bestOf(H.view(p), 3)[1]
H.inClient(p, C.EV.hatch, picked.id)
E.run(0.4)
H.expect(H.currentPanel(p) == "tree" and #named(p, "SwapOut_", true) == housed(), "lot", "every hut full: the swap picker for an egg")
due = E.now() + prof.clutch.left
H.expect(math.abs(due - (at + Tree.secs(prof))) <= 0.15, "lot", "the next due Tree.secs after the last (the huts' tree shares counted)", string.format("%.2f vs %.2f", due, at + Tree.secs(prof)))
f0, st0 = #W.fx, W.states
local sinkSeen = false
local at3 = nil
E.runUntil(function()
	if prof.clutch.next ~= 11 then
		at3 = at3 or E.now()
	end
	-- (the old ones sink back into the lawn while the new ones rise)
	if at3 then
		for _, e in lot2 do
			local w = H.inClient(p, C.EV.where, s.plot, e.id)
			if w and w.Y < Street.LAWN_Y - 0.1 then
				sinkSeen = true
			end
		end
	end
	return at3 ~= nil and E.now() - at3 > 1.2
end, prof.clutch.left + 3, 0.1)
H.expect(at3 ~= nil and math.abs(at3 - due) <= 0.15, "lot", "the next lot on time", at3 and string.format("%.2f vs %.2f", at3, due) or "none")
local keptOld = 0
for _, e in lot2 do
	if eggOf(prof, e.id) then
		keptOld += 1
	end
end
H.expect(keptOld == 0 and #prof.clutch.list == Tree.count(prof.tier) and idsOf(prof.clutch.list) == "11,12,13,14,15", "lot", "every egg left unhatched gone, a whole new lot", idsOf(prof.clutch.list))
lotCheck("none hatched", at3, lot2, 11, f0, st0, "The tree laid new ones.")
H.expect(sinkSeen, "lot", "the old ones sink back into the lawn")
local gone = 0
for _, e in lot2 do
	if H.inClient(p, C.EV.where, s.plot, e.id) == nil then
		gone += 1
	end
end
H.expect(gone == #lot2, "lot", "and are gone", string.format("%d of %d", gone, #lot2))
H.expect(H.currentPanel(p) == "tree" and #named(p, "SwapOut_", true) == 0 and #named(p, "Egg_", true) == #prof.clutch.list, "lot", "the swap picker back on the list when its egg went", string.format("%d swap rows, %d egg rows", #named(p, "SwapOut_", true), #named(p, "Egg_", true)))
H.expect(says(p, "That egg is gone. The tree laid new ones."), "lot", "and says why")
H.expect(rawErr(p, "egg.hatch", { id = picked.id, swap = prof.pals[1].id }) == "not_found" and #prof.pals == n0, "lot", "a swap for an egg gone: not_found, nothing sold")
H.closePanel(p)
H.inClient(p, C.EV.hatch, picked.id)
E.run(0.2)
H.expect(says(p, "That egg is gone. The tree laid new ones."), "lot", "the client hatching it: told it's gone")
E.run(RISEN)
drawnCheck(p, s, "lot 3")
tagCheck(p, "lot 3")
cardCheck("lot 3")
checks("lot 3")

------------------------------------------------------------------ 8. the eggs are saved: leave and come back to the same eggs and clock
E.phase = "save"
if prof.clutch.left < 30 then
	waitLot(prof.clutch.left + 2)
	E.run(RISEN)
end
local plot1 = s.plot
local keptList = {}
for _, e in prof.clutch.list do
	-- (each with the season it was laid in and the weather that touched it, if any: GAME_DESIGN 13)
	table.insert(keptList, { id = e.id, r = e.r, ss = e.ss, wx = e.wx, wt = e.wt })
end
local keptNext = prof.clutch.next
E.removePlayer(p, "leave")
local leftAtLeave = prof.clutch.left
E.run(2)
local rec = E.cloud.stores[STORE] and E.cloud.stores[STORE]["u_9701"]
local saved = rec and type(rec.value) == "table" and rec.value.data and rec.value.data.clutch
H.expect(type(saved) == "table" and type(saved.list) == "table" and H.diff(saved.list, keptList) == nil and saved.next == keptNext, "save", "the eggs saved with the profile", saved and tostring(H.diff(saved.list, keptList)) or "no clutch")
H.expect(saved ~= nil and math.abs(saved.left - leftAtLeave) < 1e-6, "save", "and the time to the next lot", saved and string.format("%.2f vs %.2f", saved.left, leftAtLeave))
H.expect(plotModel(plot1):GetAttribute("Eggs") == nil, "save", "the island freed: its Eggs attribute gone with it", tostring(plotModel(plot1):GetAttribute("Eggs")))
local back = E.now()
p = H.addPlayer({ userId = 9701, name = "Gardener" })
E.run(2)
s = H.session(p)
prof = H.profile(p)
C = clientOf(p)
W = watch(p)
H.expect(s ~= nil and s.ready and s.plot == plot1, "save", "back on the same island")
local again = {}
for _, e in prof.clutch.list do
	table.insert(again, { id = e.id, r = e.r, ss = e.ss, wx = e.wx, wt = e.wt })
end
H.expect(H.diff(again, keptList) == nil and prof.clutch.next == keptNext, "save", "the same eggs: no new lot laid on the way in", idsOf(prof.clutch.list))
H.expect(prof.clutch.left < leftAtLeave and prof.clutch.left >= leftAtLeave - (E.now() - back) - 0.2, "save", "the clock goes on from where it stopped (it runs only while the player is here)", string.format("%.2f, %.2f at the leave", prof.clutch.left, leftAtLeave))
E.run(RISEN)
m1 = plotModel(s.plot)
decor = m1:FindFirstChild("Decor", true)
drawnCheck(p, s, "rejoin")
tagCheck(p, "rejoin")
cardCheck("rejoin")
checks("rejoin")

------------------------------------------------------------------ 9. the huts' shares: eggs sooner, luckier, cheaper
E.phase = "shares"
local keptMuts = {}
for _, x in prof.pals do
	keptMuts[x.id] = x.muts
	x.muts = {}
end
H.push(p, 0.3)
local secs0, luck0, cost0, odds0 = Tree.secs(prof), Tree.luck(prof), Tree.cost(prof, 3), Tree.odds(prof)
-- (one hut driftling Evergreen, Starborn and Frugal)
local star = nil
for _, x in prof.pals do
	if x.home ~= 0 and star == nil then
		star = x
	end
end
star.muts = { "swift4", "bright4", "sturdy2" }
local tS, lS, cS = 0, 0, 0
for _, x in prof.pals do
	if x.home ~= 0 then
		local d = Creatures.byId[x.sp]
		local f = Traits.sum(d and d.passive.fx, x.muts)
		tS += f.tree or 0
		lS += f.luck or 0
		cS -= f.cost or 0
	end
end
local wantSecs = Tuning.EggSecs / (1 + math.clamp(tS, 0, Tuning.HutTree))
local wantLuck = 1 + Tuning.EggLuck[prof.tier] + math.clamp(lS, 0, Tuning.HutLuck)
local wantCost = math.max(1, math.floor(Tuning.EggPrice[3] * Tuning.EggTier[prof.tier] * (1 - math.clamp(cS, 0, Tuning.HutCost)) + 0.5))
H.push(p, 0.3)
H.expect(Tree.secs(prof) < secs0 and math.abs(Tree.secs(prof) - wantSecs) < 1e-9, "shares", "a Leafy kind's tree share: the eggs come sooner", string.format("%.2f s, was %.2f", Tree.secs(prof), secs0))
H.expect(Tree.luck(prof) > luck0 and math.abs(Tree.luck(prof) - wantLuck) < 1e-9, "shares", "a Lucky kind's luck share: luckier eggs", string.format("%.3f, was %.3f", Tree.luck(prof), luck0))
H.expect(Tree.cost(prof, 3) < cost0 and Tree.cost(prof, 3) == wantCost, "shares", "a Thrifty kind's cost share: cheaper eggs", string.format("%d, was %d", Tree.cost(prof, 3), cost0))
local odds1 = Tree.odds(prof)
local top = 1
for r = 2, 5 do
	if odds0[r] > 0 then
		top = r
	end
end
H.expect(top >= 3 and odds1[1] < odds0[1] and odds1[top] > odds0[top], "shares", "the odds lean rarer (fewer commons, more of the rarest open here)", string.format("common %.3f -> %.3f, rarity %d %.4f -> %.4f", odds0[1], odds1[1], top, odds0[top], odds1[top]))
eggMirror(p, "shares")
tagCheck(p, "shares")
cardCheck("shares")
H.openPanel(p, "tree")
panelCheck("shares")
H.closePanel(p)
-- (the lot laid now waits the shorter time: brought on early, then a whole wait on the clock)
prof.clutch.left = 1.5
local atA = waitLot(4)
H.expect(atA ~= nil and math.abs(prof.clutch.left - (wantSecs - (E.now() - atA))) <= 0.15, "shares", "the next lot's clock set to the shorter Tree.secs", string.format("%.2f", prof.clutch.left))
E.run(1.2)
local tk = fxSince(W, 0, "tick")
H.expect(#tk > 0 and math.abs(tk[#tk].msg.clutchSecs - wantSecs) < 1e-9, "shares", "Fx tick: the shorter clutchSecs", tk[#tk] and tostring(tk[#tk].msg.clutchSecs))
local atB = waitLot(wantSecs + 2)
H.expect(atA ~= nil and atB ~= nil and math.abs((atB - atA) - wantSecs) <= 0.15, "shares", "and the one after comes that much sooner", atB and atA and string.format("%.2f s apart", atB - atA) or "none")
for _, x in prof.pals do
	if keptMuts[x.id] then
		x.muts = keptMuts[x.id]
	end
end
H.push(p, 0.3)
E.run(RISEN)
drawnCheck(p, s, "shares")
checks("shares")

------------------------------------------------------------------ 10. the island grows: more eggs at once, dearer, better
E.phase = "expand"
prof.shells = 1e6
prof.wood = Tuning.TierCost[2] + 300
H.push(p, 0.3)
-- (two of the lot hatched first, so the extra eggs fill the places they left as well as the new ones)
for k = 1, 2 do
	local e = prof.clutch.list[k]
	local w = weakest()
	res = H.req(p, "egg.hatch", { id = e.id, swap = w.id })
	E.run(0.3)
	H.expect(res.ok, "expand", "an egg hatched before the island grows", tostring(res.err))
end
E.run(1.2)
local before1 = {}
for _, e in prof.clutch.list do
	before1[e.id] = { r = e.r, cost = Tree.cost(prof, e.r) }
end
local n1, nextE = #prof.clutch.list, prof.clutch.next
local odds1t = Tree.odds(prof)
f0 = #W.fx
res = H.req(p, "island.expand", {})
E.run(1.5)
H.expect(res.ok and prof.tier == 2, "expand", "the island grows", tostring(res.err))
H.expect(#prof.clutch.list == Tree.count(2) and Tree.count(2) == 6, "expand", "the tree lays the extra eggs at once: up to Tree.count(2)", string.format("%d of %d", #prof.clutch.list, Tree.count(2)))
local keptAll, newIds = true, {}
for id, was in before1 do
	local e = eggOf(prof, id)
	keptAll = keptAll and e ~= nil and e.r == was.r
end
for _, e in prof.clutch.list do
	if before1[e.id] == nil then
		table.insert(newIds, e.id)
	end
end
table.sort(newIds)
local wantNew = {}
for id = nextE, nextE + Tree.count(2) - n1 - 1 do
	table.insert(wantNew, id)
end
H.expect(keptAll, "expand", "the eggs already there kept")
H.expect(table.concat(newIds, ",") == table.concat(wantNew, ","), "expand", "the extra ones with the next ids", table.concat(newIds, ","))
E.run(0.3)
ef = fxSince(W, f0, "eggs")
fxOk = #ef == 1 and ef[1].msg.more == Tree.count(2) - n1 and type(ef[1].msg.laid) == "table" and #ef[1].msg.laid == #prof.clutch.list
if fxOk then
	for i, e in prof.clutch.list do
		local l = ef[1].msg.laid[i]
		fxOk = fxOk and l.id == e.id and l.cost == Tree.cost(prof, e.r)
	end
end
H.expect(fxOk, "expand", "Fx eggs: the whole lot with its new prices, more = the extra ones", ef[1] and tostring(ef[1].msg.more) or "none")
local bestE = 1
for _, e in ef[1] and ef[1].msg.laid or {} do
	bestE = math.max(bestE, e.r)
end
H.expect(says(p, if bestE >= 4 then "egg is waiting under the tree" else string.format("The tree laid %d more eggs.", Tree.count(2) - n1)), "expand", "the HUD says how many more")
local ratio = Tuning.EggTier[2] / Tuning.EggTier[1]
local priced = true
for id, was in before1 do
	local e = eggOf(prof, id)
	priced = priced and e ~= nil and Tree.cost(prof, e.r) == Tuning.EggPrice[e.r] * Tuning.EggTier[2] and math.abs(Tree.cost(prof, e.r) - was.cost * ratio) <= ratio
end
H.expect(priced, "expand", "every egg's price times EggTier[2]")
local odds2 = Tree.odds(prof)
H.expect(odds2[1] < odds1t[1] and odds2[2] > odds1t[2] and odds2[4] > odds1t[4], "expand", "better odds on the bigger island (EggLuck)", string.format("common %.3f -> %.3f", odds1t[1], odds2[1]))
H.expect(m1:GetAttribute("Tier") == 2 and treeModel() ~= nil and Tree.stage(2) > Tree.stage(1), "expand", "the tree grows grander with it (its model at stage 2)")
E.run(RISEN)
drawnCheck(p, s, "expand")
tagCheck(p, "expand")
cardCheck("expand")
H.openPanel(p, "tree")
panelCheck("expand")
H.closePanel(p)
checks("expand")

------------------------------------------------------------------ 11. a tap on the own tree opens its panel
E.phase = "tap"
centre = centreOf(prof, s.plot)
local eggs0 = #prof.clutch.list
E.raycastParts = true
H.inClient(p, function()
	local pos = C.PR.project(centre + E.v3(0, 5, 0))
	C.WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.raycastParts = nil
E.run(0.5)
H.expect(H.currentPanel(p) == "tree" and #prof.clutch.list == eggs0, "tap", "a tap on the own Tree of Life opens its panel, hatching nothing", tostring(H.currentPanel(p)))
H.closePanel(p)
checks("tap")

------------------------------------------------------------------ 12. a neighbour: both islands' eggs on both clients, tags only on the own
E.phase = "neighbour"
local q = H.addPlayer({ userId = 9702, name = "Neighbour" })
E.run(2.5)
local sq = H.session(q)
local qprof = H.profile(q)
local CQ = clientOf(q)
local WQ = watch(q)
H.expect(sq ~= nil and sq.ready and sq.plot ~= s.plot and math.abs(Street.origin(sq.plot) - Street.origin(s.plot)) <= Tuning.PlotSpacing, "neighbour", "a second island next door", sq and tostring(sq.plot))
E.run(RISEN)
local mq = plotModel(sq.plot)
H.expect(#qprof.clutch.list == 5 and qprof.clutch.list[1].r == 1 and qprof.clutch.list[2].r == 1 and mq:GetAttribute("Eggs") == attrWant(qprof), "neighbour", "its own first lot, two commons first, in its own attribute", tostring(mq:GetAttribute("Eggs")))
-- (both islands count their eggs from 1, so their ids meet: here the neighbour's take the first island's own, so a
-- tag or a tap that took the other island's egg for its own would show)
for k, e in qprof.clutch.list do
	e.id = prof.clutch.list[k].id
end
qprof.clutch.next = prof.clutch.next
H.push(q, 0.3)
E.run(RISEN)
H.expect(m1:GetAttribute("Eggs") == attrWant(prof), "neighbour", "the first island's still in its own")
-- (the two clients share the fake engine's one camera, so the screen is checked on each client's own island only)
drawnCheck(q, sq, "neighbour, its own")
drawnCheck(q, s, "neighbour, the first island's")
drawnCheck(p, sq, "first, the neighbour's")
drawnCheck(p, s, "first, its own")
tagCheck(q, "neighbour", true)
tagCheck(p, "first", true)
eggMirror(q, "neighbour")
-- a tap on the neighbour's egg hatches nothing
local theirs = qprof.clutch.list[3]
local takenP = prof.stats.taken
local hitTheirs = H.inClient(p, function()
	local w = C.EV.where(sq.plot, theirs.id)
	if w == nil then
		return nil
	end
	local pos = C.PR.project(w + E.v3(0, 0.6, 0))
	return C.EV.tapAt(E.v2(pos.X, pos.Y - E.inset))
end)
E.run(0.6)
H.expect(hitTheirs == false and prof.stats.taken == takenP and qprof.stats.taken == 0 and eggOf(qprof, theirs.id) ~= nil, "neighbour", "a tap on the neighbour's egg hatches nothing", tostring(hitTheirs))
-- the neighbour's tree tapped: whose it is
p.Character:PivotTo(E.cf.new(Street.origin(sq.plot) + 6, 3, 12))
E.run(1.5)
local qCentre = centreOf(qprof, sq.plot)
E.raycastParts = true
H.inClient(p, function()
	local pos = C.PR.project(qCentre + E.v3(0, 5, 0))
	C.WV.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.raycastParts = nil
E.run(0.4)
H.expect(H.currentPanel(p) == nil and says(p, "Someone else's Tree of Life. Yours is on your own island."), "neighbour", "a tap on the neighbour's tree: it says whose it is, no panel")
res = H.req(p, "char.home", {})
E.run(1.5)
-- the neighbour hatches one: the first client sees it crack and go
qprof.wood = math.max(qprof.wood, Buildings.byId.nest.wood + 10)
H.push(q, 0.3)
res = placeFor(q, "nest")
H.expect(res.ok, "neighbour", "the neighbour builds a hut", tostring(res.err))
local qe = qprof.clutch.list[1]
local seenBy = H.inClient(p, C.EV.count, sq.plot)
local pf0 = #W.fx
res = H.req(q, "egg.hatch", { id = qe.id, swap = 0 })
H.expect(res.ok and #qprof.pals == 1 and Creatures.byId[qprof.pals[1].sp].knack == "wood", "neighbour", "the neighbour hatches its first egg (good with wood)", tostring(res.err))
local hq = fxSince(WQ, 0, "hatched")
H.expect(#hq == 1 and #fxSince(W, pf0, "hatched") == 0, "neighbour", "Fx hatched to the neighbour only")
E.run(0.6)
H.expect(H.inClient(p, C.EV.count, sq.plot) == seenBy - 1, "neighbour", "the first client: one of the neighbour's eggs fewer", string.format("%d, was %d", H.inClient(p, C.EV.count, sq.plot), seenBy))
E.run(1)
H.expect(H.inClient(p, C.EV.where, sq.plot, qe.id) == nil and H.inClient(q, CQ.EV.where, sq.plot, qe.id) == nil, "neighbour", "it cracked open and is gone on both clients")
tagCheck(q, "neighbour hatched", true)
drawnCheck(p, sq, "first, the neighbour's after its hatch")
H.checkProfile(q, "neighbour")
H.checkMirror(q, "neighbour")
eggMirror(q, "neighbour")
checks("end")

report(E, H)
