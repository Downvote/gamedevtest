-- The Tree of Life and its pen (GAME_DESIGN 6; Logic/Tree): the tree growing a driftling every few seconds while the
-- player is here, the pen never full ("pens should be infinite") and never drawn on the island; past Tuning.PenKeep
-- waiting, the least useful sold as each new one grows; its Speed and Luck bought to the top (and every refusal); the
-- odds the panel shows; a rare one announced; the pen sending its best on to the huts with room, but only those a
-- building of their knack has a place for; a sold hut driftling's place filled from the pen, a hut cleared away sending
-- its driftlings back; the Driftlings panel's hut picker moving one in a swap; expanding the island giving the tree new
-- kinds; the tree moved; a second player's client drawing the first island's hut driftlings (not its pen).
local E = require("./loader")
local H = require("./harness")
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
local Street = H.sharedServer("Data.Street")
local Plot = H.sharedServer("Logic.Plot")
local Tree = H.sharedServer("Logic.Tree")
local Creatures = H.sharedServer("Data.Creatures")
local Buildings = H.sharedServer("Data.Buildings")
local Islets = H.sharedServer("Data.Islets")

local p = H.addPlayer({ userId = 9501, name = "Grower" })
E.run(2)
local fx = H.watchFx(p)
local prof = H.profile(p)
prof.tut = 0
prof.shells, prof.wood, prof.food = 2e6, 2e5, 5000
H.push(p, 0.3)

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
local function grownSince(i0)
	local n = 0
	for i = i0 + 1, #fx do
		if fx[i].kind == "tree" and type(fx[i].grown) == "table" then
			n += #fx[i].grown
		end
	end
	return n
end

------------------------------------------------------------------ growing, never waiting
E.phase = "grow"
local GROW = 4
local i0 = #fx
local t0 = E.now()
E.runUntil(function()
	return grownSince(i0) >= GROW
end, Tuning.TreeSecs[1] * (GROW + 2), 0.2)
local took = E.now() - t0
H.expect(Tree.inPen(prof) == #prof.pals and grownSince(i0) == GROW, "grow", "the tree grows a driftling at a time into the pen (Fx tree)", string.format("%d in the pen, %d grown", Tree.inPen(prof), grownSince(i0)))
H.expect(math.abs(took - Tuning.TreeSecs[1] * GROW) <= Tuning.TreeSecs[1] + 1, "grow", "about TreeSecs each", string.format("%.1f s for %d", took, GROW))
local n0 = #prof.pals
E.run(Tuning.TreeSecs[1] * 2 + 0.5)
H.expect(#prof.pals >= n0 + 2, "grow", "no room limit: the tree never waits", string.format("%d -> %d", n0, #prof.pals))
local v = H.view(p)
H.expect(v ~= nil and v.pen == nil and #v.pals == #prof.pals, "grow", "the view: every driftling, no pen room", v and string.format("%d of %d", #v.pals, #prof.pals))
local SC = H.cmod(p, "Controllers.StateClient")
local fa = H.inClient(p, SC.treeFrac)
E.run(1)
local fb = H.inClient(p, SC.treeFrac)
H.expect(fb ~= fa and fb < 1, "grow", "the client's bar keeps filling toward the next one", string.format("%.2f -> %.2f", fa, fb))
local WVp = H.cmod(p, "Controllers.WorldView")
H.expect(H.inClient(p, WVp.ownCount) == 0, "grow", "the pen is not drawn on the island (it is a list in the tree's panel)", tostring(H.inClient(p, WVp.ownCount)))
H.checkProfile(p, "grow")
H.checkMirror(p, "grow")

------------------------------------------------------------------ huts: the pen sends its best with work to do; a sold one's place filled; a hut cleared away
E.phase = "huts"
local function hutIndex(uid)
	for i, q in prof.plot.placed do
		if q.uid == uid then
			return i
		end
	end
	return 0
end
local function inHutOf(uid)
	local out = {}
	for _, x in prof.pals do
		if x.home == uid then
			table.insert(out, x)
		end
	end
	return out
end
-- a hut but nowhere to work: the pen keeps them all
local r = place("nest")
H.expect(r.ok, "huts", "a hut", tostring(r.err))
local hutUid = r.data and r.data.uid
H.expect(#inHutOf(hutUid) == 0, "huts", "nowhere to work yet: the pen sends nobody", tostring(#inHutOf(hutUid)))
H.req(p, "plot.store", { i = hutIndex(hutUid) })
-- a building of each of the first island's knacks, then the hut
for _, id in { "patch", "lumber", "stall", "pier" } do
	local rb = place(id)
	H.expect(rb.ok, "huts", "a " .. id, tostring(rb.err))
end
r = place("nest")
hutUid = r.data and r.data.uid
local inHut = inHutOf(hutUid)
H.expect(#inHut == Buildings.byId.nest.slots and inHut[1].work ~= 0 and inHut[2].work ~= 0, "huts", "the pen sent two at once, each to work", tostring(#inHut))
local best = 0
for _, x in prof.pals do
	if x.home == 0 and x.held == nil then
		best = math.max(best, Tree.worth(x))
	end
end
H.expect(Tree.worth(inHut[1]) >= best - 1e-9 and Tree.worth(inHut[2]) >= best - 1e-9, "huts", "the best of the pen", string.format("%.2f %.2f vs %.2f", Tree.worth(inHut[1]), Tree.worth(inHut[2]), best))
local nA = #prof.pals
E.run(Tuning.TreeSecs[1] + 1)
H.expect(#prof.pals > nA, "huts", "the tree goes on growing into the pen")
-- a hut driftling sold: the pen's best moves into its place
local sold = inHut[1]
local res = H.req(p, "pal.sell", { id = sold.id })
H.expect(res.ok and table.find(prof.pals, sold) == nil, "huts", "a hut driftling sold", tostring(res.err))
H.expect(#inHutOf(hutUid) == Buildings.byId.nest.slots, "huts", "its place in the hut filled from the pen", tostring(#inHutOf(hutUid)))
-- the hut cleared away: its driftlings back to the pen, resting
res = H.req(p, "plot.store", { i = hutIndex(hutUid) })
local home0, resting = 0, 0
for _, x in prof.pals do
	if x.home == 0 then
		home0 += 1
		if x.work == 0 then
			resting += 1
		end
	end
end
H.expect(res.ok and home0 == #prof.pals and resting == home0, "huts", "a hut cleared away: its driftlings back in the pen, not working", string.format("%s, %d of %d in the pen", tostring(res.err), home0, #prof.pals))
-- two huts again for the rest
place("nest")
place("nest")
H.checkProfile(p, "huts")
H.checkMirror(p, "huts")

------------------------------------------------------------------ past PenKeep: the least useful sold as each new one grows
E.phase = "keep"
do
	prof.tree.t = 0
	local kept = Tree.add(prof, "pebblit", {})
	kept.held = 1 -- (one the player put there: never sold for room)
	local extra = {}
	while Tree.inPen(prof) < Tuning.PenKeep do
		table.insert(extra, Tree.add(prof, "pebblit", {}))
	end
	H.push(p, 0.3)
	local sold0, sh0, n1 = prof.stats.sold, prof.shells, Tree.inPen(prof)
	local i1 = #fx
	E.runUntil(function()
		return grownSince(i1) >= 2
	end, Tree.secs(prof) * 3, 0.1)
	E.run(0.3)
	H.expect(n1 == Tuning.PenKeep and Tree.inPen(prof) == Tuning.PenKeep, "keep", "the pen stays at PenKeep as new ones grow", string.format("%d -> %d", n1, Tree.inPen(prof)))
	H.expect(prof.stats.sold == sold0 + grownSince(i1) and prof.shells > sh0, "keep", "one sold for each that grew, for its price", string.format("%d sold, %+.0f shells", prof.stats.sold - sold0, prof.shells - sh0))
	H.expect(table.find(prof.pals, kept) ~= nil, "keep", "the one the player kept there is never sold for room")
	local better = 0
	for _, x in prof.pals do
		if x.home == 0 and x.held == nil and Tree.worth(x) > Tree.worth(extra[1]) then
			better += 1
		end
	end
	H.expect(better >= 1, "keep", "the commonest go first: the better ones stay")
	-- the panel lists the best of it and says how many more
	H.openPanel(p, "tree")
	E.run(0.4)
	local pg = p:FindFirstChild("PlayerGui")
	local rows = 0
	for _, d in pg:GetDescendants() do
		if string.sub(d.Name, 1, 8) == "PenSell_" and H.guiVisible(d) then
			rows += 1
		end
	end
	H.expect(rows > 0 and rows <= 40 and pg ~= nil and pg:FindFirstChild("PenMore", true) ~= nil, "keep", "the tree's panel: the best forty or so, then how many more", tostring(rows))
	H.closePanel(p)
	H.checkProfile(p, "keep")
	H.checkMirror(p, "keep")
	-- (back to a small pen for the rest)
	local gone = {}
	for _, x in extra do
		gone[x] = true
	end
	gone[kept] = true
	local keep = {}
	for _, x in prof.pals do
		if not gone[x] then
			table.insert(keep, x)
		end
	end
	prof.pals = keep
	H.push(p, 0.3)
end

------------------------------------------------------------------ the tree's upgrades and odds
E.phase = "upgrades"
local Menus = H.cmod(p, "UI.Menus")
H.openPanel(p, "tree")
E.run(0.3)
H.expect(H.buttonNamed(p, "Upgrade_luck") ~= nil and H.buttonNamed(p, "SellCommons", true) ~= nil, "upgrades", "the tree's panel: Luck, Speed, the pen")
local function oddsShown(r)
	local pg = p:FindFirstChild("PlayerGui")
	return pg and pg:FindFirstChild("Odds_" .. r, true) ~= nil
end
H.expect(oddsShown(1) and oddsShown(5), "upgrades", "the odds of every rarity")
local odds0 = Tree.odds(prof)
for lv = 2, #Tuning.TreeLuckCost do
	H.clickNamed(p, "Upgrade_luck", { wait = 0.3 })
	H.expect(prof.tree.luck == lv, "upgrades", "Luck level " .. lv, tostring(prof.tree.luck))
end
H.expect(H.buttonNamed(p, "Upgrade_luck", true) == nil, "upgrades", "at the top: no more Luck to buy")
local odds1 = Tree.odds(prof)
H.expect(odds1[3] + odds1[4] > (odds0[3] + odds0[4]) * 2, "upgrades", "luck makes the rare and epic ones far likelier", string.format("%.3f -> %.3f", odds0[3] + odds0[4], odds1[3] + odds1[4]))
for lv = 2, #Tuning.TreeSpeedCost do
	res = H.req(p, "tree.upgrade", { what = "speed" })
	H.expect(res.ok and prof.tree.speed == lv, "upgrades", "Speed level " .. lv, tostring(res.err))
end
H.expect(H.req(p, "tree.upgrade", { what = "speed" }).err == "max", "upgrades", "Speed at the top: max")
H.expect(H.req(p, "tree.upgrade", { what = "luck" }).err == "max", "upgrades", "Luck at the top: max")
H.closePanel(p)
-- a lean island: no shells, no wood
local q2 = H.addPlayer({ userId = 9502, name = "Lean" })
E.run(2)
local pq = H.profile(q2)
pq.shells = 0
H.expect(H.req(q2, "tree.upgrade", { what = "luck" }).err == "money", "upgrades", "not enough shells: money")
pq.shells, pq.wood = 1e6, 0
H.expect(H.req(q2, "tree.upgrade", { what = "speed" }).err == "wood", "upgrades", "not enough wood: wood")
H.checkProfile(q2, "lean")
-- a rare one or better announced (Fx tree, the HUD's notice)
local UIKitP = H.cmod(p, "UI.UIKit")
local rareSeen = false
for _ = 1, 40 do
	local i1 = #fx
	E.run(Tree.secs(prof) + 0.3)
	for i = i1 + 1, #fx do
		if fx[i].kind == "tree" and type(fx[i].grown) == "table" then
			for _, x in fx[i].grown do
				local d = Creatures.byId[x.sp]
				if d and d.rarity >= 3 then
					rareSeen = true
				end
			end
		end
	end
	if rareSeen then
		break
	end
end
H.expect(rareSeen, "upgrades", "a rare one grows on a lucky tree")
E.run(0.3)
local noticed = false
for _, d in p.PlayerGui:GetDescendants() do
	if d:IsA("TextLabel") and string.find(d.Text, "grew on the tree", 1, true) then
		noticed = true
	end
end
H.expect(noticed, "upgrades", "the HUD says so")
H.checkProfile(p, "upgrades")
H.checkMirror(p, "upgrades")

------------------------------------------------------------------ the island grows: new kinds
E.phase = "expand"
res = H.req(p, "island.expand", {})
H.expect(res.ok and prof.tier == 2, "expand", "the island grows", tostring(res.err))
local newKinds = {}
for _, k in Islets.list do
	if k.tier == 2 then
		for _, sp in k.wild do
			newKinds[sp] = true
		end
	end
end
local newOne = false
for _ = 1, 60 do
	local i1 = #fx
	E.run(Tree.secs(prof) + 0.3)
	for i = i1 + 1, #fx do
		if fx[i].kind == "tree" and type(fx[i].grown) == "table" then
			for _, x in fx[i].grown do
				if newKinds[x.sp] then
					newOne = true
				end
			end
		end
	end
	if newOne then
		break
	end
end
H.expect(newOne, "expand", "the tree grows the second tier's kinds now")
H.checkProfile(p, "expand")

------------------------------------------------------------------ moving one in a swap through the panel
E.phase = "swap"
-- (the tree just started on its next before the client's view is compared, so nothing grows meanwhile)
local function holdTree()
	prof.tree.t = 0
	H.push(p, 0.3)
end
local hut, inside = nil, nil
for _, q in prof.plot.placed do
	if q.id == "nest" and hut == nil then
		hut = q
	end
end
local penOne = nil
for _, x in prof.pals do
	if x.home == hut.uid and inside == nil then
		inside = x
	elseif x.home == 0 and penOne == nil then
		penOne = x
	end
end
H.expect(hut ~= nil and inside ~= nil and penOne ~= nil, "swap", "a full hut and one in the pen")
holdTree()
H.openPanel(p, "pals", { move = penOne.id })
E.run(0.3)
H.expect(H.buttonNamed(p, "SwapWith_" .. inside.id) ~= nil, "swap", "the hut picker offers a swap with each one there")
H.clickNamed(p, "SwapWith_" .. inside.id, { wait = 0.5 })
H.expect(penOne.home == hut.uid and inside.home == 0 and inside.held == 1, "swap", "swapped: the pen's one in the hut, the other kept in the pen")
H.expect(H.req(p, "pal.house", { id = inside.id, uid = hut.uid, swap = 0 }).err == "full", "swap", "a full hut without a swap: full")
H.closePanel(p)
holdTree()
H.checkProfile(p, "swap")
H.checkMirror(p, "swap")

------------------------------------------------------------------ the tree moved; another player's client sees the hut driftlings
E.phase = "moved"
local ti, tq = 0, nil
for i, q in prof.plot.placed do
	if q.id == "tree" then
		ti, tq = i, q
	end
end
local others = {}
for i, q in prof.plot.placed do
	if i ~= ti then
		table.insert(others, q)
	end
end
local mx, mz, mr = Plot.spot(prof.tier, others, "tree", tq.x + 8, tq.z - 6, 0)
res = H.req(p, "plot.move", { i = ti, x = mx or tq.x, z = mz or tq.z, rot = mr or 0 })
H.expect(res.ok and (tq.x ~= (mx or tq.x) or tq.z ~= (mz or tq.z) or mx ~= nil), "moved", "the tree moves", tostring(res.err))
local housed = 0
for _, x in prof.pals do
	if x.home ~= 0 then
		housed += 1
	end
end
E.run(1.5)
H.expect(housed > 0 and H.inClient(p, WVp.ownCount) == housed, "moved", "the hut driftlings still on the island, the pen's still not", string.format("%d drawn, %d in huts, %d in the pen", H.inClient(p, WVp.ownCount), housed, Tree.inPen(prof)))
local WVq = H.cmod(q2, "Controllers.WorldView")
H.expect(H.inClient(q2, WVq.rigCount) >= housed and H.inClient(q2, WVq.rigCount) < #prof.pals, "moved", "the neighbour's client draws the island's hut driftlings, not its pen", string.format("%d drawn of %d", H.inClient(q2, WVq.rigCount), #prof.pals))
holdTree()
H.checkProfile(p, "end")
H.checkMirror(p, "end")

report(E, H)
