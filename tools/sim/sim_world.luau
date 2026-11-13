-- The sea and the islands (GAME_DESIGN 4, 6, 8; docs/ARCHITECTURE.md 7.5, 10.2, 10.6, 10.7): the whole sea built at
-- start (the boardwalk, open water on every lot); two islands on plots 1 and 2 with their lands, attributes and
-- founders, each with its Tree of Life (its model by its stage) and its first lot of eggs (the plot's Eggs attribute
-- its session's); each client drawing its own island's hut driftlings, the neighbour's and both founders, no villagers,
-- and both islands' eggs round their trees; a founder walking onto the neighbour's island (the camera follows, Home
-- shows) and going home (and its cooldown); placing (paid in wood), moving and clearing buildings with every refusal
-- (no upgrades, the piece limit with the tree apart, the huts' limit), the server's Static.Decor following piece by
-- piece; the same through Build mode's UI (the Huts tab at the huts' limit); malicious plot payloads; a leaving
-- player's island back to open water with its eggs gone; a full sea kicking the seventh player; a newcomer's tree
-- planted and its first lot laid; every claimed island's eggs in its attribute, drawn by the clients near it, the
-- price tags over the own ones only; the tree fixed (a tap opens its panel; never cleared away, bought or replaced; it
-- moves like any piece, its eggs with it; Build mode's Clear away off for it) while every other piece clears away.
local E = require("./loader")
local I = require("./inst")
local H = require("./harness")
local report = require("./report")
local tree = require("./sources")
E.verbose = false
E.verboseUi = false
E.dt = 0.1
H.patchMonetizationIds(tree)
E.boot(tree)
E.phase = "boot"
E.startServer()
E.run(1)

local getD = I.getD
local Tuning = H.sharedServer("Config.Tuning")
local Street = H.sharedServer("Data.Street")
local Buildings = H.sharedServer("Data.Buildings")
local Plot = H.sharedServer("Logic.Plot")
local Tree = H.sharedServer("Logic.Tree")
local DecorModels = H.sharedServer("Models.DecorModels")

local function plotModel(i)
	return E.workspace.Plots:FindFirstChild("Plot_" .. i)
end
local function staticOf(i)
	local m = plotModel(i)
	return m and m:FindFirstChild("Static")
end
local function officeOf(i)
	local st = staticOf(i)
	local f = st and st:FindFirstChild("Office")
	return f and f:FindFirstChild("Office")
end
local function decorOf(i)
	local st = staticOf(i)
	return st and st:FindFirstChild("Decor")
end
local function rootOf(p)
	return p.Character and p.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ 1. the sea before anyone joins
E.phase = "sea"
local plots = E.workspace:FindFirstChild("Plots")
H.expect(plots ~= nil, "sea", "Workspace.Plots exists")
local seaFolder = plots and plots:FindFirstChild("Street")
local stretches, ends = 0, 0
if seaFolder then
	for _, c in seaFolder:GetChildren() do
		if string.match(c.Name, "^Road_%d+$") then
			stretches += 1
		elseif c.Name == "StreetEnds" then
			ends += 1
		end
	end
end
H.expect(stretches == Street.MAX and ends == 1, "sea", "a boardwalk stretch per plot and the sea's ends", string.format("%d stretches, %d ends", stretches, ends))
for i = 1, Street.MAX do
	local m = plotModel(i)
	H.expect(m ~= nil and m:GetAttribute("Owner") == 0 and m:FindFirstChild("EmptyLot", true) ~= nil and officeOf(i) == nil, "sea", "plot " .. i .. " is open water")
end

------------------------------------------------------------------ 2. two islands
E.phase = "islands"
local a = H.addPlayer({ userId = 9401, name = "Ava" })
E.run(2)
local b = H.addPlayer({ userId = 9402, name = "Bo" })
E.run(3)
local sa, sb = H.session(a), H.session(b)
H.expect(sa and sa.plot == 1 and sb and sb.plot == 2, "islands", "plots 1 and 2", string.format("%s %s", tostring(sa and sa.plot), tostring(sb and sb.plot)))
-- both new islands start with their Tree of Life and nothing else (no driftling: the player hatches them from the
-- tree's eggs), so the hut driftlings counted below are the ones put there
local function housed(prof): number
	local n = 0
	for _, x in prof.pals do
		if x.home ~= 0 then
			n += 1
		end
	end
	return n
end
local function sessionOn(i)
	for _, s in H.smod("Session").all() do
		if s.plot == i then
			return s
		end
	end
	return nil
end
-- The Tree of Life on island i: its piece (the session's profile) and its model in Static.Decor (named by its piece,
-- its stage in place of a level: Tree.stage, grander with the island).
local function treeOn(i)
	local s = sessionOn(i)
	local q = s and Tree.piece(s.profile)
	local decor = decorOf(i)
	local model = nil
	if q and decor then
		model = decor:FindFirstChild(string.format("%d:tree:%d:%d:%d:%d", q.uid, q.x, q.z, q.rot, Tree.stage(s.profile.tier)))
	end
	return q, model
end
-- the tree's eggs on island i: its plot's "Eggs" attribute ("id.rarity;..."), every client draws them near its view
local function eggsAttr(i): { string }
	local m = plotModel(i)
	local raw = m and m:GetAttribute("Eggs")
	local out = {}
	if type(raw) == "string" then
		for entry in string.gmatch(raw, "[^;]+") do
			table.insert(out, entry)
		end
	end
	return out
end
-- The plot's attribute is its session's eggs, egg by egg, a whole lot (nobody hatches one here).
local function eggsMatch(i, s): (boolean, string)
	local list = eggsAttr(i)
	local want = {}
	for _, e in if s then s.profile.clutch.list else {} do
		table.insert(want, string.format("%d.%d", e.id, e.r))
	end
	local ok = s ~= nil and #list >= 1 and table.concat(list, ";") == table.concat(want, ";") and #want == Tree.count(s.profile.tier)
	return ok, string.format("%s (the session's %s)", table.concat(list, ";"), table.concat(want, ";"))
end
-- The client of `p` draws every egg in island i's attribute (EggView draws the islands within 100 studs of the view's
-- centre: its own and the next ones), each lying on the lawn on the ring round that island's tree (DecorModels.EGG_RING
-- from its middle), no two in one place. A new lot rising out of the lawn is waited out.
local function drawsEggs(p, i): (boolean, string)
	local EV = H.cmod(p, "Controllers.EggView")
	local why = ""
	local ok = E.runUntil(function()
		local q = treeOn(i)
		local list = eggsAttr(i)
		if q == nil or #list == 0 or EV.count(i) ~= #list then
			why = string.format("%d drawn of %d listed", EV.count(i), #list)
			return false
		end
		local ox, oz = Street.origin(i)
		local w, d = Plot.footprint(q.id, q.rot)
		local cx, cz = ox + q.x + w / 2, oz + q.z + d / 2
		local spots = {}
		for _, e in list do
			local id = tonumber(string.match(e, "^(%d+)%.")) or 0
			local at = EV.where(i, id)
			if at == nil then
				why = "egg " .. id .. " not drawn"
				return false
			end
			local r = math.sqrt((at.X - cx) ^ 2 + (at.Z - cz) ^ 2)
			if math.abs(r - DecorModels.EGG_RING) > 0.05 or math.abs(at.Y - Street.LAWN_Y) > 0.05 then
				why = string.format("egg %d %.2f studs from the tree's middle, at %.2f high", id, r, at.Y)
				return false
			end
			for _, o in spots do
				if math.abs(o.X - at.X) + math.abs(o.Z - at.Z) < 0.5 then
					why = "two eggs in one place"
					return false
				end
			end
			table.insert(spots, at)
		end
		why = string.format("%d drawn round the tree", #list)
		return true
	end, 5, 0.1)
	return ok, why
end
-- The client's view follows the profile's eggs (a new lot reaches it with the next whole view). Wait it out before
-- comparing the two.
local function settled(p)
	E.runUntil(function()
		local prof, v = H.profile(p), H.view(p)
		if prof == nil or v == nil or type(v.clutch) ~= "table" or #v.clutch ~= #prof.clutch.list then
			return false
		end
		for i, e in prof.clutch.list do
			if v.clutch[i].id ~= e.id then
				return false
			end
		end
		return true
	end, 1, 0.05)
end
for _, p in { a, b } do
	local prof = H.profile(p)
	H.expect(#prof.plot.placed == 1 and prof.plot.placed[1].id == "tree" and #prof.pals == 0, "islands", p.Name .. ": a new island has its Tree of Life and nothing else yet (no driftling)", string.format("%d pieces, %d driftlings", #prof.plot.placed, #prof.pals))
	local s = H.session(p)
	local q, model = treeOn(s.plot)
	H.expect(q ~= nil and model ~= nil and model:GetAttribute("Decor") == "tree", "islands", p.Name .. ": its tree's model on the island, by its stage", q and string.format("%d:tree:%d:%d", q.uid, q.x, q.z) or "no tree")
	local ok, why = eggsMatch(s.plot, s)
	H.expect(ok, "islands", p.Name .. ": its first lot of eggs listed in the plot's Eggs attribute, the session's", why)
end
for k, p in { a, b } do
	local m = plotModel(k)
	local prof = H.profile(p)
	H.expect(m:GetAttribute("Owner") == p.UserId and m:GetAttribute("StudioName") == p.Name .. "'s Isle", "islands", p.Name .. ": owner and island name", tostring(m:GetAttribute("StudioName")))
	H.expect(m:GetAttribute("Tier") == 1 and m:GetAttribute("Day") == prof.day and m:GetAttribute("Sailing") == nil, "islands", p.Name .. ": tier 1, the day (no sailing any more)")
	H.expect(officeOf(k) == nil, "islands", p.Name .. ": no house any more")
	local land = staticOf(k):FindFirstChild("Land")
	H.expect(land ~= nil and m:FindFirstChild("EmptyLot", true) == nil, "islands", p.Name .. ": the island replaced the open water")
	H.expect(land ~= nil and land:FindFirstChild("Foam", true) ~= nil and land:FindFirstChild("Shallows", true) ~= nil and land:FindFirstChild("Lawn", true) ~= nil, "islands", p.Name .. ": its coast (grass, foam, shallows)")
	local fw = land and land:FindFirstChild("Foam", true)
	H.expect(fw ~= nil and fw:GetAttribute("PixelWater") == 3, "islands", p.Name .. ": the foam animates (PixelWater)")
	local bound = land and land:FindFirstChild("Bound", true)
	H.expect(bound ~= nil and bound.CollisionGroup == "Bounds" and bound.Transparency == 1, "islands", p.Name .. ": invisible coast walls out of the pixel filter's rays")
	-- (far over a jump: nobody hops the coast onto the sea)
	local lowest = math.huge
	for _, d in (land :: Instance):GetDescendants() do
		if d.Name == "Bound" and d:IsA("BasePart") then
			lowest = math.min(lowest, d.Position.Y + d.Size.Y / 2)
		end
	end
	H.expect(lowest >= Street.LAWN_Y + Tuning.JumpHeight + 6, "islands", p.Name .. ": every coast wall far higher than a jump", tostring(lowest))
	local f = prof.founder
	H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", f.skin, f.hair, f.style, f.shirt) and p:GetAttribute("Plot") == k, "islands", p.Name .. ": Founder and Plot attributes", tostring(p:GetAttribute("Founder")))
	local sx, sz = Street.spawn()
	local ox, oz = Street.origin(k)
	local root = rootOf(p)
	H.expect(root ~= nil and math.abs(root.Position.X - (ox + sx)) < 0.5 and math.abs(root.Position.Z - (oz + sz)) < 0.5, "islands", p.Name .. ": the founder appears on their path", root and tostring(root.Position))
	H.checkProfile(p, "island " .. p.Name)
	settled(p)
	H.checkMirror(p, "island " .. p.Name)
end
-- driftlings on both islands (the hut's; no villagers)
for k, p in { a, b } do
	local prof = H.profile(p)
	prof.shells, prof.wood = 50000, 5000
	H.push(p, 0.2)
	local placed = 0
	for _, id in { "patch", "lumber", "flowers", "nest" } do
		local pr = Street.plot(1)
		local done = false
		for z = pr.z1 - 2, pr.z0 + 1, -1 do
			for x = pr.x1 - 2, pr.x0 + 1, -1 do
				if not done and Plot.fits(1, prof.plot.placed, id, x, z, 0) then
					done = H.req(p, "plot.place", { id = id, x = x, z = z, rot = 0 }).ok
				end
			end
		end
		placed += if done then 1 else 0
	end
	H.expect(placed == 4, "islands", p.Name .. ": four buildings", tostring(placed))
	H.expect(prof.folk == nil, "islands", p.Name .. ": no villagers")
	local patchUid, nestUid = 0, 0
	for _, q in prof.plot.placed do
		if q.id == "patch" then
			patchUid = q.uid
		elseif q.id == "nest" then
			nestUid = q.uid
		end
	end
	table.insert(prof.pals, { id = prof.nextId, sp = "mossbun", home = nestUid, work = patchUid, muts = {} })
	prof.nextId += 1
	prof.seen.mossbun = 2
	H.push(p, 0.2)
	local _ = k
end
E.run(1.5)
for _, pair in { { a, b }, { b, a } } do
	local me, other = pair[1], pair[2]
	local WV = H.cmod(me, "Controllers.WorldView")
	local AV = H.cmod(me, "Controllers.AvatarView")
	local own = housed(H.profile(me))
	local oth = housed(H.profile(other))
	H.expect(own >= 1 and WV.ownRigCount() == own and WV.rigCount() == own + oth, "islands", me.Name .. ": own hut driftlings and the neighbour's", string.format("%d own of %d, %d all of %d", WV.ownRigCount(), own, WV.rigCount(), own + oth))
	H.expect(AV.count() == 2, "islands", me.Name .. ": both founders", tostring(AV.count()))
	-- both islands' eggs: its own round its tree and the neighbour's round theirs
	local myPlot, otherPlot = H.session(me).plot, H.session(other).plot
	local okOwn, whyOwn = drawsEggs(me, myPlot)
	H.expect(okOwn, "islands", me.Name .. ": draws its own eggs round its tree", whyOwn)
	local okOther, whyOther = drawsEggs(me, otherPlot)
	H.expect(okOther, "islands", me.Name .. ": and the neighbour's round theirs", whyOther)
end
H.expect(plotModel(1):GetAttribute("Folk") == nil, "islands", "no Folk attribute (no villagers)", tostring(plotModel(1):GetAttribute("Folk")))
local palsAttr = plotModel(1):GetAttribute("Pals")
H.expect(type(palsAttr) == "string" and string.find(palsAttr, "mossbun") ~= nil and #string.split(palsAttr, ";") == housed(H.profile(a)), "islands", "the Pals attribute lists the hut driftlings", tostring(palsAttr))
-- the island signs' labels
local canvasA = a.PlayerGui:FindFirstChild("World") and a.PlayerGui.World:FindFirstChild("Canvas")
local s1 = canvasA and canvasA:FindFirstChild("Sign_1")
local s3 = canvasA and canvasA:FindFirstChild("Sign_3")
H.expect(s1 ~= nil and s1.Text == "Ava's Isle", "islands", "island 1's sign label", s1 and s1.Text)
H.expect(s3 ~= nil and s3.Text == "Unclaimed isle", "islands", "open water's sign label", s3 and s3.Text)

------------------------------------------------------------------ 3. walking the boardwalk
E.phase = "walk"
-- the way from an island's jetty across the boardwalk to its pier's end is open: nothing collidable stands in its
-- middle (the bug: the street's east end once ran its invisible walls along the whole boardwalk, across every pier
-- and jetty, and a founder put on the pier after the voyage home could not leave it)
do
	local pr = Street.pier()
	local blockers = {}
	-- plot 1 an island (from its jetty), the last plot open water (from the boardwalk: an empty lot has no jetty)
	for _, i in { 1, Street.MAX } do
		local ox, oz = Street.origin(i)
		local from = if i == 1 then Street.BOARD.z0 - 3 else Street.BOARD.z0 + 0.1
		for _, d in plots:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local c, sz = d.Position, d.Size
				local x0, x1 = c.X - sz.X / 2 - ox, c.X + sz.X / 2 - ox
				local z0, z1 = c.Z - sz.Z / 2 - oz, c.Z + sz.Z / 2 - oz
				local y0, y1 = c.Y - sz.Y / 2, c.Y + sz.Y / 2
				if x1 > Street.PIER_X - 1 and x0 < Street.PIER_X + 1 and z1 > from and z0 < pr.z1 - 0.5 and y1 > -0.25 and y0 < 4 then
					table.insert(blockers, string.format("%s (%s) on plot %d", d.Name, d.Parent and d.Parent.Name or "?", i))
				end
			end
		end
	end
	H.expect(#blockers == 0, "sea", "the way from the jetty across the boardwalk to the pier's end is open", table.concat(blockers, ", "))
end
local CCa = H.cmod(a, "Controllers.CameraController")
local PRa = H.cmod(a, "Pixel.PixelRenderer")
-- the founder in the middle of the screen (the camera always centres on them): their feet's screen point
-- (measured on the camera's own grid and pan: the renderer's picture may still be catching up)
local RasterW = H.sharedServer("Render.Raster")
local function centred(label)
	local r = rootOf(a)
	local v = CCa.view()
	local gx, gy = RasterW.gridPoint(v.rot12, v.grid, r.Position.X, Street.LAWN_Y + 1.5, r.Position.Z)
	local px, py = CCa.pan()
	local x, y = (gx - px) * v.K, (gy - py) * v.K
	local ok = math.abs(x - v.fullX / 2) <= v.fullX * 0.06 and y >= v.fullY * 0.3 and y <= v.fullY * 0.7
	H.expect(ok, "walk", label, string.format("%d,%d on %dx%d", x, y, v.fullX, v.fullY))
end
E.run(1)
centred("at home the view centres on the founder")
H.expect(H.buttonNamed(a, "Home") == nil, "walk", "no Home button at home")
local px0, py0 = CCa.pan()
local ox2 = Street.origin(2)
a.Character:PivotTo(E.cf.new(ox2 + 6, 3, 12))
E.run(3)
local px1, py1 = CCa.pan()
H.expect(px1 ~= px0 or py1 ~= py0, "walk", "the camera follows the founder onto the neighbour's island", string.format("%d,%d", px1, py1))
centred("and keeps them in the middle there")
H.expect(H.buttonNamed(a, "Home") ~= nil, "walk", "the Home button shows off the own island")
-- a few steps on the own island: the view moves with every one
local res = H.req(a, "char.home", {})
H.expect(res.ok, "walk", "char.home", tostring(res.err))
E.run(0.5)
local sx, sz = Street.spawn()
local ox1, oz1 = Street.origin(1)
local root = rootOf(a)
H.expect(root ~= nil and math.abs(root.Position.X - (ox1 + sx)) < 0.5 and math.abs(root.Position.Z - (oz1 + sz)) < 0.5, "walk", "home: back on the path", root and tostring(root.Position))
res = H.req(a, "char.home", {})
H.expect(not res.ok and res.err == "cooldown", "walk", "a second home within the cooldown", tostring(res.err))
E.run(3)
centred("the view glides back to the founder at home")
local pxh, pyh = CCa.pan()
a.Character:PivotTo(E.cf.new(ox1 + 8, 3, oz1 + 2))
E.run(2.5)
local pxs, pys = CCa.pan()
H.expect(pxs ~= pxh or pys ~= pyh, "walk", "a walk across the own island moves the view too", string.format("%d,%d -> %d,%d", pxh, pyh, pxs, pys))
centred("still in the middle")
H.expect(H.buttonNamed(a, "Home") == nil, "walk", "the Home button stays away on the own island")
a.Character:PivotTo(E.cf.new(ox1 + sx, 3, oz1 + sz))
E.run(2.5)

------------------------------------------------------------------ 4. building: place, move, clear away (no upgrades)
E.phase = "build"
local prof = H.profile(a)
prof.pals[1].work = 0
H.push(a, 0.3)
local function spot(id, rot, placed, tier)
	local pr = Street.plot(tier or prof.tier)
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if Plot.fits(tier or prof.tier, placed, id, x, z, rot) then
				return x, z
			end
		end
	end
	return nil, nil
end
local n0 = #prof.plot.placed
local s0, w0 = prof.shells, prof.wood
local gx, gz = spot("stall", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "stall", x = gx, z = gz, rot = 0 })
H.expect(res.ok and #prof.plot.placed == n0 + 1, "build", "place a snack stall", tostring(res.err))
-- (wood pays for every piece: "make wood the main resource for building/expanding"; the island makes a little of both
-- meanwhile)
H.expect(Buildings.byId.stall.shells == 0 and Buildings.byId.stall.wood > 0 and math.abs(prof.wood - (w0 - Buildings.byId.stall.wood)) < 1 and prof.shells >= s0 - 1e-6, "build", "its wood paid (no shells)", string.format("%s %s", prof.shells, prof.wood))
E.run(0.3)
local decor = decorOf(1)
local stall = prof.plot.placed[#prof.plot.placed]
local function keyOf(q)
	return string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, q.lvl)
end
local modelS = decor and decor:FindFirstChild(keyOf(stall))
H.expect(modelS ~= nil, "build", "the server built it as " .. keyOf(stall))
res = H.req(a, "plot.place", { id = "stall", x = gx, z = gz, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "build", "not on another piece", tostring(res.err))
res = H.req(a, "plot.place", { id = "flowers", x = 0, z = 4, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "build", "not on the plaza", tostring(res.err))
local fp = Street.footpath()
res = H.req(a, "plot.place", { id = "torch", x = math.floor(fp.x0) + 1, z = math.floor(fp.z0) + 2, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "build", "not on the path", tostring(res.err))
res = H.req(a, "plot.place", { id = "torch", x = Street.plot(1).x1 + 5, z = 10, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "build", "not off the island", tostring(res.err))
res = H.req(a, "plot.place", { id = "cafe", x = 10, z = 10, rot = 0 })
H.expect(not res.ok and res.err == "locked", "build", "not a bigger island's building", tostring(res.err))
-- short of wood: refused; no shells at all: built all the same (shells only buy driftlings and feasts)
do
	local wood, shells = prof.wood, prof.shells
	local tx, tz = spot("torch", 0, prof.plot.placed)
	prof.wood = Buildings.byId.torch.wood - 1
	H.push(a, 0.2)
	res = H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	H.expect(not res.ok and res.err == "wood" and #prof.plot.placed == n0 + 1, "build", "not without the wood", tostring(res.err))
	prof.wood, prof.shells = wood, 0
	H.push(a, 0.2)
	res = H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	H.expect(res.ok and res.err == nil, "build", "with no shells at all: built (money is never asked for a building)", tostring(res.err))
	if res.ok then
		res = H.req(a, "plot.store", { i = #prof.plot.placed })
		H.expect(res.ok and prof.plot.placed[#prof.plot.placed] == stall, "build", "(the torch cleared away again)", tostring(res.err))
	end
	prof.shells = shells
	H.push(a, 0.2)
end
-- move it
local others = {}
for i, q in prof.plot.placed do
	if i ~= #prof.plot.placed then
		table.insert(others, q)
	end
end
local mx, mz = nil, nil
local pr1 = Street.plot(1)
for z = pr1.z0 + 1, pr1.z1 - 2 do
	for x = pr1.x0 + 1, pr1.x1 - 2 do
		if mx == nil and (x ~= gx or z ~= gz) and Plot.fits(1, others, "stall", x, z, 90) then
			mx, mz = x, z
		end
	end
end
res = H.req(a, "plot.move", { i = #prof.plot.placed, x = mx, z = mz, rot = 90 })
H.expect(res.ok and stall.x == mx and stall.z == mz and stall.rot == 90, "build", "move it, turned", tostring(res.err))
E.run(0.3)
H.expect(decor:FindFirstChild(keyOf(stall)) ~= nil and decor:FindFirstChild(string.format("%d:stall:%d:%d:0:1", stall.uid, gx, gz)) == nil, "build", "its model moved with it")
-- no upgrades (taken out: "remove the ability to upgrade buildings", 2026-11-11): the action is gone, nothing changes
s0, w0 = prof.shells, prof.wood
res = H.req(a, "plot.upgrade", { i = #prof.plot.placed })
H.expect(not res.ok and res.err == "unknown_action" and stall.lvl == 1 and prof.shells >= s0 - 0.5 and prof.wood >= w0 - 0.5, "build", "no upgrades: the action is refused, nothing paid", string.format("%s lvl %s shells %s -> %s", tostring(res.err), tostring(stall.lvl), tostring(s0), tostring(prof.shells)))
local fi = nil
for i, q in prof.plot.placed do
	if q.id == "nest" then
		fi = i
	end
end
-- replacing: only with another of its kind, a real index
H.expect(H.req(a, "plot.replace", { i = fi, id = "patch" }).err == "bad_payload", "build", "a hut replaced by a farm: refused")
H.expect(H.req(a, "plot.replace", { i = 2000, id = "nest" }).err == "bad_payload", "build", "a replace past the pieces: refused")
H.expect(H.req(a, "plot.replace", { i = fi, id = "nope" }).err == "bad_payload", "build", "an unknown piece: refused")
H.expect(H.req(a, "plot.replace", { i = fi, id = "burrow" }).err == "locked", "build", "a bigger hut on a small island: locked")
H.expect(H.req(a, "plot.replace", { i = fi, id = "cottage" }).err == "bad_payload", "build", "a home (gone): refused")
E.run(0.3)
H.expect(decor:FindFirstChild(keyOf(stall)) ~= nil, "build", "the moved model is still built (its key carries the level)")
-- clear it away: half back
w0 = prof.wood
local n1 = #prof.plot.placed
res = H.req(a, "plot.store", { i = #prof.plot.placed })
H.expect(res.ok and #prof.plot.placed == n1 - 1, "build", "clear the stall away", tostring(res.err))
H.expect(math.abs(prof.wood - (w0 + math.floor(Buildings.byId.stall.wood * Tuning.Refund))) < 1, "build", "half its wood back", string.format("%s -> %s", w0, prof.wood))
-- a hut cleared away: its driftlings wait with no hut (and move in once a hut has room)
local hutUid = prof.plot.placed[fi].uid
res = H.req(a, "plot.store", { i = fi })
local stillIn, waiting = 0, 0
for _, x in prof.pals do
	if x.home == hutUid then
		stillIn += 1
	elseif x.home == 0 and x.work == 0 then
		waiting += 1
	end
end
H.expect(res.ok and stillIn == 0 and waiting == #prof.pals and waiting >= 1, "build", "a hut with driftlings in it cleared away: they wait with no hut", string.format("%s, %d waiting", tostring(res.err), waiting))
E.run(0.3)
H.expect(plotModel(1):GetAttribute("Pals") == "", "build", "and are not drawn on the island meanwhile (the Pals attribute leaves them out)", tostring(plotModel(1):GetAttribute("Pals")))
E.run(0.3)
H.expect(#decor:GetChildren() == #prof.plot.placed, "build", "a model a piece", string.format("%d vs %d", #decor:GetChildren(), #prof.plot.placed))
-- the piece limit
-- (the tree apart: it isn't counted)
local limit = Plot.limit(1)
local guard = 0
while #prof.plot.placed < limit + 1 and guard < 80 do
	guard += 1
	local x, z = spot("torch", 0, prof.plot.placed)
	if x == nil then
		break
	end
	res = H.req(a, "plot.place", { id = "torch", x = x, z = z, rot = 0 })
	E.run(0.1)
end
H.expect(#prof.plot.placed == limit + 1, "build", "the island fills to its limit (the tree apart)", tostring(#prof.plot.placed))
local lx, lz = spot("torch", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "torch", x = lx or 20, z = lz or 20, rot = 0 })
H.expect(not res.ok and (res.err == "full" or res.err == "blocked"), "build", "the island's piece limit", tostring(res.err))
while #prof.plot.placed > 5 do
	H.req(a, "plot.store", { i = #prof.plot.placed })
	E.run(0.1)
end
E.run(0.5)
H.expect(#decor:GetChildren() == 5, "build", "and back (three, a torch and the tree)", tostring(#decor:GetChildren()))
-- the huts' limit (GAME_DESIGN 4: "make a limit of huts per island expansion level", Tuning.HutLimit): a tier-1 island
-- takes four; one more is refused (huts) with nothing paid
local most = Plot.hutLimit(prof.tier)
local addedHuts = {}
prof.wood += 2000
H.push(a, 0.2)
while Plot.huts(prof.plot.placed) < most and #addedHuts < 10 do
	local x, z = spot("nest", 0, prof.plot.placed)
	res = if x then H.req(a, "plot.place", { id = "nest", x = x, z = z, rot = 0 }) else { ok = false, err = "no spot" }
	if not H.expect(res.ok, "build", "a hut under the limit", tostring(res.err)) then
		break
	end
	table.insert(addedHuts, prof.plot.placed[#prof.plot.placed].uid)
end
H.expect(most == Tuning.HutLimit[1] and Plot.huts(prof.plot.placed) == most, "build", "huts up to the island's limit", string.format("%d of %d", Plot.huts(prof.plot.placed), most))
do
	local hx, hz = spot("nest", 0, prof.plot.placed)
	local n, wood = #prof.plot.placed, prof.wood
	res = H.req(a, "plot.place", { id = "nest", x = hx or 20, z = hz or 20, rot = 0 })
	H.expect(hx ~= nil and not res.ok and res.err == "huts" and #prof.plot.placed == n and prof.wood >= wood - 1e-6, "build", "one hut past the limit refused (huts), nothing paid", tostring(res.err))
end
H.checkProfile(a, "build")
H.checkMirror(a, "build")

------------------------------------------------------------------ 5. Build mode through the UI
E.phase = "build-ui"
E.run(0.3)
local BuildUI = H.cmod(a, "UI.BuildUI")
H.expect(H.clickNamed(a, "Menu_build"), "build", "the HUD's Build button")
H.expect(BuildUI.isOpen() and CCa.isFree(), "build", "Build mode is open, the view free")
E.run(0.4)
H.clickNamed(a, "Tab_farm", { wait = 0.3 }) -- (the tray opens on the tip's tab)
H.expect(H.buttonNamed(a, "Buy_patch") ~= nil, "build", "the Farms tab offers the veggie patch")
H.expect(H.buttonNamed(a, "Buy_orchard", true) ~= nil, "build", "the orchard shows, locked")
H.clickNamed(a, "Tab_decor", { wait = 0.3 })
H.expect(H.buttonNamed(a, "Buy_flowers") ~= nil and H.buttonNamed(a, "Buy_patch", true) == nil, "build", "the Decor tab")
-- the Huts tab at the huts' limit: its count says so, the hut's card shows No room and picks nothing; then the huts
-- put up for it go again
H.clickNamed(a, "Tab_nest", { wait = 0.3 })
do
	local count = a.PlayerGui:FindFirstChild("Count", true)
	H.expect(count ~= nil and count.Text == string.format("%d/%d", most, most), "build", "the Huts tab's count: the huts of the limit", count and count.Text)
	local hutCard = H.buttonNamed(a, "Buy_nest", true)
	local words = if hutCard then table.concat(H.textsOf(hutCard), "/") else ""
	H.expect(hutCard ~= nil and string.find(words, "No room", 1, true) ~= nil, "build", "the hut's card shows No room", words)
	H.clickNamed(a, "Buy_nest", { includeDisabled = true, wait = 0.3 })
	local ghost = false
	for _, d in E.workspace:GetDescendants() do
		if d.Name == "Ghost" then
			ghost = true
		end
	end
	H.expect(not ghost, "build", "and a tap on it picks nothing")
	for _, uid in addedHuts do
		for i, q in prof.plot.placed do
			if q.uid == uid then
				H.req(a, "plot.store", { i = i })
				break
			end
		end
	end
	E.run(0.3)
	H.expect(Plot.huts(prof.plot.placed) == 0 and #prof.plot.placed == 5, "build", "(the huts cleared away again)", tostring(Plot.huts(prof.plot.placed)))
	local c2 = a.PlayerGui:FindFirstChild("Count", true)
	H.expect(c2 ~= nil and c2.Text == string.format("0/%d", most), "build", "the count follows", c2 and c2.Text)
	H.clickNamed(a, "Tab_decor", { wait = 0.3 })
end
local function screenOf(world)
	return H.inClient(a, function()
		local pos = PRa.project(world)
		return E.v2(pos.X, pos.Y - E.inset)
	end)
end
local function ghostFootprint()
	for _, d in E.workspace:GetDescendants() do
		if d.Name == "Footprint" and d.Parent and d.Parent.Name == "Ghost" then
			return d
		end
	end
	return nil
end
H.clickNamed(a, "Buy_flowers", { wait = 0.2 })
local ux, uz = spot("flowers", 0, prof.plot.placed)
local cellWorld = E.v3(ox1 + ux + 1, Street.LAWN_Y, oz1 + uz + 1)
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(cellWorld), false)
end)
E.run(0.3)
local fpGhost = ghostFootprint()
H.expect(fpGhost ~= nil, "build", "a ghost with its footprint")
local Blocks = H.sharedServer("Models.Blocks")
local function edgeColor(fpm)
	local e = fpm and fpm:FindFirstChildWhichIsA("BasePart")
	return e and e.Color
end
H.expect(edgeColor(fpGhost) == Blocks.color("screen_on"), "build", "cyan where it fits", tostring(edgeColor(fpGhost)))
local placedBefore = #prof.plot.placed
H.expect(H.clickNamed(a, "Place"), "build", "the Place button")
E.run(0.3)
local last = prof.plot.placed[#prof.plot.placed]
H.expect(#prof.plot.placed == placedBefore + 1 and last.id == "flowers" and last.x == ux and last.z == uz, "build", "placed where tapped", last and string.format("%s %d,%d (wanted %d,%d)", last.id, last.x, last.z, ux, uz))
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(E.v3(ox1 + Street.CENTER.x + 0.5, Street.LAWN_Y, oz1 + Street.CENTER.z + 0.5)), false)
end)
E.run(0.3)
fpGhost = ghostFootprint()
H.expect(edgeColor(fpGhost) == Blocks.color("berry_red"), "build", "red on the plaza", tostring(edgeColor(fpGhost)))
local placeBtn = H.buttonNamed(a, "Place", true)
H.expect(placeBtn ~= nil and getD(placeBtn).props.AutoButtonColor == false, "build", "Place is off where it does not fit")
H.clickNamed(a, "Cancel")
H.expect(ghostFootprint() == nil, "build", "Cancel takes the ghost away")
-- tap the placed flowers: picked up (Clear away; nothing to upgrade)
E.raycastParts = true
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(E.v3(ox1 + ux + 1, Street.LAWN_Y + 0.4, oz1 + uz + 1)), false)
end)
E.raycastParts = nil
E.run(0.3)
H.expect(H.buttonNamed(a, "Store") ~= nil and H.buttonNamed(a, "Upgrade", true) == nil, "build", "tapping a piece picks it up (Clear away, no Upgrade)")
H.clickNamed(a, "Store")
E.run(0.3)
H.expect(#prof.plot.placed == placedBefore, "build", "cleared through the UI", tostring(#prof.plot.placed))
-- a building that makes something (the first piece after the tree): no Upgrade in its bar either
E.raycastParts = true
local q1 = prof.plot.placed[1]
for _, q in prof.plot.placed do
	if Plot.isFixed(q1.id) and not Plot.isFixed(q.id) then
		q1 = q
	end
end
local w1, d1 = Plot.footprint(q1.id, q1.rot)
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(E.v3(ox1 + q1.x + w1 / 2, Street.LAWN_Y + 0.3, oz1 + q1.z + d1 / 2)), false)
end)
E.raycastParts = nil
E.run(0.3)
H.expect(H.buttonNamed(a, "Upgrade", true) == nil, "build", "a " .. q1.id .. " picked up shows no Upgrade")
-- Replace: the others of its kind, each with its price after the refund; a tap swaps it where it stands
local alt = Plot.replacements(q1, prof.tier)[1]
if H.expect(alt ~= nil and H.buttonNamed(a, "Replace", true) ~= nil, "build", "a " .. q1.id .. " picked up shows Replace") then
	prof.wood += 500
	H.push(a, 0.3)
	H.clickNamed(a, "Replace", { wait = 0.3 })
	H.expect(H.buttonNamed(a, "SwapTo_" .. alt, true) ~= nil, "build", "Replace lists the others of its kind")
	local uid0 = q1.uid
	H.clickNamed(a, "SwapTo_" .. alt, { wait = 0.6 })
	H.expect(q1.id == alt and q1.uid == uid0 and q1.lvl == 1, "build", "replaced through the UI where it stood, its uid kept", string.format("%s uid %d", q1.id, q1.uid))
	E.run(0.3)
	H.expect(decor:FindFirstChild(keyOf(q1)) ~= nil, "build", "the new model stands")
end
H.clickNamed(a, "Cancel", { optional = true })
-- drawing paths (GAME_DESIGN 4: "drawn or made in a box like ... the bakery game"): the Paths tab's tile picked,
-- the tools in its bar; a line, a box and an erase as a player drags them (BuildUI.debugDraw: the same stroke code)
do
	prof.shells, prof.wood = 1e6, 1e5
	H.push(a, 0.3)
	H.clickNamed(a, "Tab_path", { wait = 0.3 })
	H.clickNamed(a, "Buy_dirtpath", { wait = 0.3 })
	H.expect(H.buttonNamed(a, "DrawLine") ~= nil and H.buttonNamed(a, "DrawBox") ~= nil and H.buttonNamed(a, "DrawErase") ~= nil and H.buttonNamed(a, "DrawLook") ~= nil, "build", "a path picked: Line, Box, Erase and Look around")
	local free = {}
	local r = Street.plot(prof.tier)
	for z = r.z0 - r.z0 % 2, r.z1, 2 do
		for x = r.x0 - r.x0 % 2, r.x1, 2 do
			if #free < 400 and Plot.fits(prof.tier, prof.plot.placed, "dirtpath", x, z, 0) then
				table.insert(free, { x, z })
			end
		end
	end
	-- a line: from one free cell to one four cells along (the stroke fills the cells between)
	local a0 = free[1]
	local a1 = { a0[1] + 8, a0[2] }
	local paths0 = 0
	for _, q in prof.plot.placed do
		if Plot.isPath(q.id) then
			paths0 += 1
		end
	end
	local plan = H.inClient(a, BuildUI.debugDraw, { a0, a1 }, "line")
	E.run(0.4)
	local lays = 0
	for _, w in plan do
		if w == "lay" then
			lays += 1
		end
	end
	local function paths()
		local n = 0
		for _, q in prof.plot.placed do
			if Plot.isPath(q.id) then
				n += 1
			end
		end
		return n
	end
	H.expect(#plan == 5, "build", "a line's stroke fills the cells between its ends", tostring(#plan))
	H.expect(lays >= 1 and paths() == paths0 + lays, "build", "the line's tiles go down where the plan said", string.format("%d planned, %d -> %d", lays, paths0, paths()))
	-- a box: two corners, every cell between
	local b0 = free[#free]
	local b1 = { b0[1] - 4, b0[2] - 4 }
	local p1 = paths()
	local planB = H.inClient(a, BuildUI.debugDraw, { b0, b1 }, "box")
	E.run(0.4)
	local laysB = 0
	for _, w in planB do
		if w == "lay" then
			laysB += 1
		end
	end
	H.expect(#planB == 9, "build", "a box's stroke is every cell between its corners", tostring(#planB))
	H.expect(paths() == p1 + laysB, "build", "the box's tiles go down", string.format("%d planned, %d -> %d", laysB, p1, paths()))
	-- erase the line again: half the price back for each tile
	local wood0 = prof.wood
	local planE = H.inClient(a, BuildUI.debugDraw, { a0, a1 }, "erase")
	E.run(0.4)
	local lifts = 0
	for _, w in planE do
		if w == "lift" then
			lifts += 1
		end
	end
	H.expect(lifts == lays and paths() == p1 + laysB - lays, "build", "Erase takes the line's tiles up", string.format("%d lifted, %d paths", lifts, paths()))
	local back = math.floor(Buildings.byId.dirtpath.wood * Tuning.Refund) * lifts
	H.expect(back > 0 and math.abs((prof.wood - wood0) - back) < 1, "build", "and gives half their wood back", string.format("%.2f back, %d due", prof.wood - wood0, back))
	-- the server's side: a non-path id, junk cells
	local ok, out = H.raw(a, "plot.paint", { id = "patch", cells = "0,0" })
	H.expect(ok and type(out) == "table" and out.ok == false, "build", "paint refuses a building", tostring(type(out) == "table" and out.err))
	ok, out = H.raw(a, "plot.paint", { id = "dirtpath", cells = "0,0;;1" })
	H.expect(ok and type(out) == "table" and out.err == "bad_payload", "build", "junk cells refused")
	H.clickNamed(a, "Cancel", { optional = true })
end
H.clickNamed(a, "BuildDone")
E.run(0.4)
H.expect(not BuildUI.isOpen() and not CCa.isFree(), "build", "Done: closed, the view follows again")
H.expect(ghostFootprint() == nil, "build", "no ghost left")

------------------------------------------------------------------ 6. malicious plot payloads
E.phase = "malicious"
local function snap()
	local q = H.profile(a)
	local placed = {}
	for _, x in q.plot.placed do
		table.insert(placed, string.format("%s:%d:%d:%d:%d", x.id, x.x, x.z, x.rot, x.lvl))
	end
	return { placed = table.concat(placed, ";"), tier = q.tier, nextId = q.nextId }
end
local function refused(label, err, action, payload)
	local ok, out = H.raw(a, action, payload)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, type(out) == "table" and tostring(out.err) or tostring(out))
	E.run(0.15)
end
local before = snap()
local storesBefore = { shells = prof.shells, wood = prof.wood }
refused("a fractional x", "bad_payload", "plot.place", { id = "torch", x = 1.5, z = 20, rot = 0 })
refused("x out of range", "bad_payload", "plot.place", { id = "torch", x = 100, z = 20, rot = 0 })
refused("a 45 degree turn", "bad_payload", "plot.place", { id = "torch", x = 20, z = 20, rot = 45 })
refused("NaN", "bad_payload", "plot.place", { id = "torch", x = 0 / 0, z = 20, rot = 0 })
refused("index 0", "bad_payload", "plot.move", { i = 0, x = 20, z = 20, rot = 0 })
refused("index 999", "bad_payload", "plot.store", { i = 999 })
refused("a piece not there", "bad_payload", "plot.store", { i = 60 })
refused("an upgrade (there are none now)", "unknown_action", "plot.upgrade", { i = 1 })
refused("an extra field", "bad_payload", "plot.place", { id = "torch", x = 20, z = 20, rot = 0, price = 0 })
refused("a home with a payload", "bad_payload", "char.home", { x = 1 })
refused("an unknown piece", "bad_payload", "plot.place", { id = "castle", x = 20, z = 20, rot = 0 })
refused("a string coord", "bad_payload", "plot.place", { id = "torch", x = "20", z = 20, rot = 0 })
local treeI = 0
for i, q in prof.plot.placed do
	if Plot.isFixed(q.id) then
		treeI = i
	end
end
refused("the Tree of Life cleared away", "fixed", "plot.store", { i = treeI })
refused("a Tree of Life bought", "bad_payload", "plot.place", { id = "tree", x = 20, z = 20, rot = 0 })
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
-- (the stores: nothing paid; the island only made a little meanwhile)
H.expect(prof.shells >= storesBefore.shells - 1e-6 and prof.wood >= storesBefore.wood - 1e-6, "malicious", "and took nothing from the stores", string.format("%s -> %s, %s -> %s", storesBefore.shells, prof.shells, storesBefore.wood, prof.wood))
E.run(0.3)

------------------------------------------------------------------ 7. a player leaves
E.phase = "leave"
local EVa = H.cmod(a, "Controllers.EggView")
local followed2 = EVa.count(2)
E.removePlayer(b, "leave")
-- (their eggs go with them: the plot's Eggs attribute cleared with the island, and Ava's client lets them go at once,
-- the tree they lay round gone)
E.runUntil(function()
	return plotModel(2):GetAttribute("Eggs") == nil
end, 3, 0.02)
local dropped2 = E.runUntil(function()
	return EVa.count(2) == 0
end, 0.55, 0.02)
E.run(2)
local m2 = plotModel(2)
H.expect(m2 and m2:GetAttribute("Owner") == 0 and m2:GetAttribute("StudioName") == nil and m2:FindFirstChild("EmptyLot", true) ~= nil and officeOf(2) == nil, "leave", "their island is open water again")
local WVa = H.cmod(a, "Controllers.WorldView")
H.expect(WVa.rigCount() == WVa.ownRigCount(), "leave", "Ava no longer draws Bo's islanders", string.format("%d all, %d own", WVa.rigCount(), WVa.ownRigCount()))
H.expect(H.cmod(a, "Controllers.AvatarView").count() == 1, "leave", "one founder left")
H.expect(m2 ~= nil and m2:GetAttribute("Eggs") == nil and followed2 >= 1 and dropped2 and EVa.count(2) == 0, "leave", "and their eggs are gone with the island (the attribute cleared, none drawn)", string.format("%s, %d drawn before, %d now", tostring(m2 and m2:GetAttribute("Eggs")), followed2, EVa.count(2)))
H.expect(EVa.count(1) == #eggsAttr(1) and #eggsAttr(1) >= 1, "leave", "Ava's own eggs still drawn", string.format("%d of %d", EVa.count(1), #eggsAttr(1)))

------------------------------------------------------------------ 8. a full sea
E.phase = "full"
local c = H.addPlayer({ userId = 9403, name = "Cy" })
E.run(3)
H.expect(H.session(c) and H.session(c).plot == 2, "full", "a newcomer gets the freed island 2", tostring(H.session(c) and H.session(c).plot))
H.checkProfile(c, "newcomer")
do
	-- (a newcomer's tree planted and its first lot laid: the first two cheap commons, in the plot's attribute)
	local sc0 = H.session(c)
	local cl = sc0 and sc0.profile.clutch.list or {}
	local ok, why = eggsMatch(2, sc0)
	local _, model = treeOn(2)
	H.expect(model ~= nil and ok and cl[1].r == 1 and cl[2].r == 1, "full", "the newcomer's tree planted and its first lot laid, the first two commons", why)
end
for k = 1, Street.MAX - 2 do
	H.addPlayer({ userId = 9410 + k, name = "Extra" .. k, client = false, noCharacter = true })
	E.run(1.5)
end
local taken = 0
for i = 1, Street.MAX do
	if plotModel(i):GetAttribute("Owner") ~= 0 then
		taken += 1
	end
end
H.expect(taken == Street.MAX, "full", "every island taken", tostring(taken))
local seventh = H.addPlayer({ userId = 9420, name = "Late", client = false, noCharacter = true })
E.run(2)
local kicked = false
for _, k in E.kicks or {} do
	if k.userId == 9420 then
		kicked = true
	end
end
H.expect(kicked and H.session(seventh) == nil, "full", "the seventh player is told the sea is full")

------------------------------------------------------------------ 9. every island's tree and eggs; the tree fixed (GAME_DESIGN 4, 6)
E.phase = "eggs"
-- every claimed island has its tree and its eggs (the server-side players' too): its plot's Eggs attribute is its
-- session's, egg by egg; the clients draw the eggs of the islands near their view: Cy's own and the neighbours' on
-- either side, and Ava's client Cy's next door; Cy's price tags hang over its own only
local claimed = 0
for i = 1, Street.MAX do
	local m = plotModel(i)
	if m:GetAttribute("Owner") ~= 0 then
		claimed += 1
		local q, model = treeOn(i)
		H.expect(q ~= nil and model ~= nil and model:GetAttribute("Decor") == "tree", "eggs", "island " .. i .. ": its Tree of Life stands there")
		local ok, why = eggsMatch(i, sessionOn(i))
		H.expect(ok, "eggs", "island " .. i .. ": its eggs listed in its Eggs attribute", why)
	end
end
H.expect(claimed == Street.MAX, "eggs", "(every island claimed)", tostring(claimed))
local cPlot = H.session(c).plot
local sc = H.session(c)
for _, i in { cPlot, cPlot - 1, cPlot + 1 } do
	local ok, why = drawsEggs(c, i)
	H.expect(ok, "eggs", "Cy's client draws island " .. i .. "'s eggs round its tree", why)
end
local okA, whyA = drawsEggs(a, cPlot)
H.expect(okA, "eggs", "Ava's client draws the newcomer's next door", whyA)
local EVc = H.cmod(c, "Controllers.EggView")
H.expect(#eggsAttr(cPlot + 3) >= 1 and EVc.count(cPlot + 3) == 0, "eggs", "a far island's eggs are not drawn (only those near the view)", tostring(EVc.count(cPlot + 3)))
do
	-- (a price tag for each of its own, none for the neighbours': the ids are each island's own, so the tags are
	-- counted against Cy's eggs; the ones crowding a rarer one's wait, the rest show)
	local canvasC = c.PlayerGui:FindFirstChild("World") and c.PlayerGui.World:FindFirstChild("Canvas")
	local function tagsNow(): (number, number, boolean)
		local mine = {}
		for _, e in sc.profile.clutch.list do
			mine[e.id] = true
		end
		local tags, shown, own = 0, 0, true
		for _, g in canvasC and canvasC:GetChildren() or {} do
			local id = tonumber(string.match(g.Name, "^EggHatch_(%d+)$"))
			if id then
				tags += 1
				own = own and mine[id] == true
				shown += if g.Visible then 1 else 0
			end
		end
		return tags, shown, own
	end
	E.runUntil(function()
		return (tagsNow()) == #sc.profile.clutch.list
	end, 5, 0.1)
	local tags, shown, own = tagsNow()
	H.expect(tags == #sc.profile.clutch.list and tags == EVc.count(cPlot) and own, "eggs", "a price tag for each of Cy's own eggs, none for the neighbours'", string.format("%d tags, %d eggs", tags, #sc.profile.clutch.list))
	H.expect(shown >= 1, "eggs", "and they show over the eggs", string.format("%d of %d shown", shown, tags))
end
-- the tree on Cy's island: a tap on it opens its panel; it is never cleared away, bought or replaced, but it moves like
-- any piece (its model and its eggs with it); in Build mode a tap picks it up with Clear away off. Every other piece
-- clears away.
E.phase = "fixed"
local cp = H.profile(c)
cp.shells, cp.wood = 50000, 5000
H.push(c, 0.2)
local ti, tq = 0, nil
for i, q in cp.plot.placed do
	if Plot.isFixed(q.id) then
		ti, tq = i, q
	end
end
H.expect(#cp.plot.placed == 1 and tq ~= nil, "fixed", "the newcomer's island has its tree and nothing else yet", tostring(#cp.plot.placed))
local cox, coz = Street.origin(cPlot)
local function treeMiddle()
	local tw, td = Plot.footprint(tq.id, tq.rot)
	return E.v3(cox + tq.x + tw / 2 + 0.3, Street.LAWN_Y + 0.05, coz + tq.z + td / 2 + 0.3)
end
-- (a tap on it on Cy's screen: the ray passes the island's invisible coast walls)
local WorldViewC = H.cmod(c, "Controllers.WorldView")
local PRc = H.cmod(c, "Pixel.PixelRenderer")
E.run(1)
E.raycastParts = true
H.inClient(c, function()
	local pos = PRc.project(treeMiddle())
	WorldViewC.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.raycastParts = nil
E.run(0.5)
H.expect(H.currentPanel(c) == "tree", "fixed", "a tap on the tree opens its panel", tostring(H.currentPanel(c)))
H.closePanel(c)
H.expect(H.req(c, "plot.store", { i = ti }).err == "fixed", "fixed", "the tree isn't cleared away (fixed)")
H.expect(H.req(c, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 }).err == "bad_payload", "fixed", "or bought")
H.expect(H.req(c, "plot.replace", { i = ti, id = "nest" }).err == "bad_payload", "fixed", "or replaced")
do
	local others = {}
	for i, q in cp.plot.placed do
		if i ~= ti then
			table.insert(others, q)
		end
	end
	local x0, z0 = tq.x, tq.z
	local mx, mz = spot("tree", 0, others, cp.tier)
	local r = if mx then H.req(c, "plot.move", { i = ti, x = mx, z = mz, rot = 0 }) else { ok = false, err = "no spot" }
	H.expect(r.ok and (mx ~= x0 or mz ~= z0) and tq.x == mx and tq.z == mz, "fixed", "it moves like any piece", string.format("%s: %d,%d to %s,%s", tostring(r.err), x0, z0, tostring(mx), tostring(mz)))
	E.run(0.4)
	local _, model = treeOn(cPlot)
	H.expect(model ~= nil, "fixed", "its model rebuilt where it stands now")
	local ok, why = drawsEggs(c, cPlot)
	H.expect(ok, "fixed", "and its eggs lie round it there", why)
end
-- Build mode: tapping the tree picks it up to move, Clear away off
local BuildC = H.cmod(c, "UI.BuildUI")
H.inClient(c, BuildC.open)
E.run(0.5)
E.raycastParts = true
H.inClient(c, function()
	local pos = PRc.project(treeMiddle())
	BuildC.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
end)
E.raycastParts = nil
E.run(0.4)
H.expect(H.buttonNamed(c, "Store", true) ~= nil and H.buttonNamed(c, "Store") == nil, "fixed", "Build mode: the tree picked up, Clear away off")
H.clickNamed(c, "Cancel", { optional = true })
H.inClient(c, BuildC.close)
E.run(0.3)
-- every other piece clears away (a Hatchery with an egg in it apart: sim_clock)
local kinds = { "patch", "lumber", "stall", "nest", "flowers", "torch" }
for _, id in kinds do
	local x, z = spot(id, 0, cp.plot.placed, cp.tier)
	local r = H.req(c, "plot.place", { id = id, x = x, z = z, rot = 0 })
	H.expect(r.ok, "fixed", "place a " .. id, tostring(r.err))
end
local cleared = 0
for i = #cp.plot.placed, 1, -1 do
	local q = cp.plot.placed[i]
	if not Plot.isFixed(q.id) then
		local r = H.req(c, "plot.store", { i = i })
		if not H.expect(r.ok, "fixed", "clear away a " .. q.id, tostring(r.err)) then
			break
		end
		cleared += 1
	end
end
H.expect(cleared == #kinds and #cp.plot.placed == 1 and Plot.isFixed(cp.plot.placed[1].id), "fixed", "every other piece clears away, the tree stays", string.format("%d of %d", cleared, #kinds))
E.run(0.4)
H.expect(#decorOf(cPlot):GetChildren() == 1, "fixed", "their models gone, the tree's left", tostring(#decorOf(cPlot):GetChildren()))
H.checkProfile(c, "fixed")
settled(c)
H.checkMirror(c, "fixed")

report(E, H)
