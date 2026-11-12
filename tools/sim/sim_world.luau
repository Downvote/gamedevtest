-- The sea and the islands (GAME_DESIGN 4, 8; docs/ARCHITECTURE.md 7.5, 10.2, 10.6, 10.7): the whole sea built at
-- start (the boardwalk, open water on every lot); two islands on plots 1 and 2 with their lodges, lands, attributes
-- and founders; each client drawing its own villagers and driftlings, the neighbour's and both founders; a founder
-- walking onto the neighbour's island (the camera follows, Home shows) and going home (and its cooldown); placing,
-- moving, upgrading and clearing buildings with every refusal, the server's Static.Decor following piece by piece;
-- the same through Build mode's UI; malicious plot payloads; a leaving player's island back to open water; a full
-- sea kicking the seventh player; a newcomer's Tree of Life (its model, a tap on it, moved but never cleared away).
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
-- both new islands have their Tree of Life (the tree's own checks come at the end, on another newcomer's island);
-- the trees wait with full pens here so the islanders counted below hold still
local PlotRules = H.sharedServer("Logic.Plot")
local TreeW = H.sharedServer("Logic.Tree")
local function fillPen(prof)
	while not TreeW.waiting(prof) do
		TreeW.add(prof, "pebblit", {}).held = 1
	end
end
for _, p in { a, b } do
	local prof = H.profile(p)
	local trees = 0
	for _, q in prof.plot.placed do
		if PlotRules.isFixed(q.id) then
			trees += 1
		end
	end
	H.expect(trees == 1, "islands", p.Name .. ": a new island's Tree of Life", tostring(trees))
	fillPen(prof)
	H.push(p, 0.2)
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
	H.checkMirror(p, "island " .. p.Name)
end
-- villagers and driftlings on both islands
for k, p in { a, b } do
	local prof = H.profile(p)
	prof.shells, prof.wood = 50000, 5000
	H.push(p, 0.2)
	local placed = 0
	for _, id in { "patch", "lumber", "hut", "nest" } do
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
	-- (the first home welcomed a castaway at once: GAME_DESIGN 9; one more joins them here)
	H.expect(#prof.folk == 1, "islands", p.Name .. ": the hut's first castaway moved in at once", tostring(#prof.folk))
	for j = 2, 2 do
		table.insert(prof.folk, { id = prof.nextId, name = "Folk" .. j, look = { skin = j, hair = j, style = j, shirt = j }, work = 0, day = 1 })
		prof.nextId += 1
	end
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
	local own = #H.profile(me).folk + #H.profile(me).pals
	local oth = #H.profile(other).folk + #H.profile(other).pals
	H.expect(WV.ownRigCount() == own and WV.rigCount() == own + oth, "islands", me.Name .. ": own islanders and the neighbour's", string.format("%d own of %d, %d all of %d", WV.ownRigCount(), own, WV.rigCount(), own + oth))
	H.expect(AV.count() == 2, "islands", me.Name .. ": both founders", tostring(AV.count()))
end
local folkAttr = plotModel(1):GetAttribute("Folk")
H.expect(type(folkAttr) == "string" and #string.split(folkAttr, ";") == #H.profile(a).folk and #H.profile(a).folk == 2, "islands", "the Folk attribute lists the villagers", tostring(folkAttr))
local palsAttr = plotModel(1):GetAttribute("Pals")
H.expect(type(palsAttr) == "string" and string.find(palsAttr, "mossbun") ~= nil, "islands", "the Pals attribute lists the driftlings", tostring(palsAttr))
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
for _, x in prof.folk do
	x.work = 0 -- (nothing made while the stores are compared)
end
prof.food = 0
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
H.expect(math.abs(prof.shells - (s0 - Buildings.byId.stall.shells)) < 1 and math.abs(prof.wood - (w0 - Buildings.byId.stall.wood)) < 1, "build", "its shells and wood paid", string.format("%s %s", prof.shells, prof.wood))
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
	if q.id == "hut" then
		fi = i
	end
end
-- replacing: only with another of its kind, a real index
H.expect(H.req(a, "plot.replace", { i = fi, id = "patch" }).err == "bad_payload", "build", "a home replaced by a farm: refused")
H.expect(H.req(a, "plot.replace", { i = 2000, id = "hut" }).err == "bad_payload", "build", "a replace past the pieces: refused")
H.expect(H.req(a, "plot.replace", { i = fi, id = "nope" }).err == "bad_payload", "build", "an unknown piece: refused")
H.expect(H.req(a, "plot.replace", { i = fi, id = "manor" }).err == "locked", "build", "a capital's home on a small island: locked")
E.run(0.3)
H.expect(decor:FindFirstChild(keyOf(stall)) ~= nil, "build", "the moved model is still built (its key carries the level)")
-- clear it away: half back
s0 = prof.shells
local n1 = #prof.plot.placed
res = H.req(a, "plot.store", { i = #prof.plot.placed })
H.expect(res.ok and #prof.plot.placed == n1 - 1, "build", "clear the stall away", tostring(res.err))
H.expect(math.abs(prof.shells - (s0 + math.floor(Buildings.byId.stall.shells * Tuning.Refund))) < 1, "build", "half its price back", string.format("%s -> %s", s0, prof.shells))
-- a home whose beds are needed stays
res = H.req(a, "plot.store", { i = fi })
H.expect(not res.ok and res.err == "no_room", "build", "the only home with villagers in it stays", tostring(res.err))
E.run(0.3)
H.expect(#decor:GetChildren() == #prof.plot.placed, "build", "a model a piece", string.format("%d vs %d", #decor:GetChildren(), #prof.plot.placed))
-- the piece limit
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
H.expect(#decor:GetChildren() == 5, "build", "and back (four and the tree)", tostring(#decor:GetChildren()))
H.checkProfile(a, "build")
H.checkMirror(a, "build")

------------------------------------------------------------------ 5. Build mode through the UI
E.phase = "build-ui"
E.run(0.3)
local BuildUI = H.cmod(a, "UI.BuildUI")
H.expect(H.clickNamed(a, "Menu_build"), "build", "the HUD's Build button")
H.expect(BuildUI.isOpen() and CCa.isFree(), "build", "Build mode is open, the view free")
E.run(0.4)
H.clickNamed(a, "Tab_food", { wait = 0.3 }) -- (the tray opens on the tip's tab)
H.expect(H.buttonNamed(a, "Buy_patch") ~= nil, "build", "the Food tab offers the veggie patch")
H.expect(H.buttonNamed(a, "Buy_orchard", true) ~= nil, "build", "the orchard shows, locked")
H.clickNamed(a, "Tab_decor", { wait = 0.3 })
H.expect(H.buttonNamed(a, "Buy_flowers") ~= nil and H.buttonNamed(a, "Buy_patch", true) == nil, "build", "the Decor tab")
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
-- a building that makes something: no Upgrade in its bar either
E.raycastParts = true
local q1 = prof.plot.placed[1]
for _, q in prof.plot.placed do
	if q1.id == "tree" and q.id ~= "tree" then
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
	prof.shells += 5000
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
	local shells0 = prof.shells
	local planE = H.inClient(a, BuildUI.debugDraw, { a0, a1 }, "erase")
	E.run(0.4)
	local lifts = 0
	for _, w in planE do
		if w == "lift" then
			lifts += 1
		end
	end
	H.expect(lifts == lays and paths() == p1 + laysB - lays, "build", "Erase takes the line's tiles up", string.format("%d lifted, %d paths", lifts, paths()))
	H.expect(prof.shells > shells0, "build", "and gives part of their price back")
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
	return { shells = math.floor(q.shells), wood = math.floor(q.wood), placed = table.concat(placed, ";"), tier = q.tier }
end
local function refused(label, err, action, payload)
	local ok, out = H.raw(a, action, payload)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, type(out) == "table" and tostring(out.err) or tostring(out))
	E.run(0.15)
end
local before = snap()
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
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
E.run(0.3)

------------------------------------------------------------------ 7. a player leaves
E.phase = "leave"
E.removePlayer(b, "leave")
E.run(2)
local m2 = plotModel(2)
H.expect(m2 and m2:GetAttribute("Owner") == 0 and m2:GetAttribute("StudioName") == nil and m2:FindFirstChild("EmptyLot", true) ~= nil and officeOf(2) == nil, "leave", "their island is open water again")
local WVa = H.cmod(a, "Controllers.WorldView")
H.expect(WVa.rigCount() == WVa.ownRigCount(), "leave", "Ava no longer draws Bo's islanders", string.format("%d all, %d own", WVa.rigCount(), WVa.ownRigCount()))
H.expect(H.cmod(a, "Controllers.AvatarView").count() == 1, "leave", "one founder left")

------------------------------------------------------------------ 8. a full sea
E.phase = "full"
local c = H.addPlayer({ userId = 9403, name = "Cy" })
E.run(3)
H.expect(H.session(c) and H.session(c).plot == 2, "full", "a newcomer gets the freed island 2", tostring(H.session(c) and H.session(c).plot))
H.checkProfile(c, "newcomer")
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

------------------------------------------------------------------ 9. the Tree of Life (GAME_DESIGN 6)
E.phase = "tree"
-- Cy's island (a newcomer's): its tree stands there as a model (the tree and its pen); a tap on it on Cy's screen
-- opens its panel; it can be moved (its model follows), never cleared away, replaced or bought; in Build mode a tap
-- picks it up with Clear away off
local cp = H.profile(c)
local ti, tq = nil, nil
for i, q in cp.plot.placed do
	if q.id == "tree" then
		ti, tq = i, q
	end
end
H.expect(tq ~= nil, "tree", "the newcomer's island has its Tree of Life")
local cdecor = decorOf(H.session(c).plot)
local treeModels = 0
for _, m in cdecor:GetChildren() do
	if m:GetAttribute("Decor") == "tree" then
		treeModels += 1
	end
end
H.expect(treeModels == 1, "tree", "its model on the island", tostring(treeModels))
-- a tap on it on Cy's screen opens its panel (the tap's ray passes the island's invisible coast walls)
local WorldViewC = H.cmod(c, "Controllers.WorldView")
local PRc = H.cmod(c, "Pixel.PixelRenderer")
local cox, coz = Street.origin(H.session(c).plot)
local tw, td = PlotRules.footprint(tq.id, tq.rot)
local at = E.v3(cox + tq.x + tw / 2 + 0.3, Street.LAWN_Y + 0.05, coz + tq.z + td / 2 + 0.3)
E.run(1)
E.raycastParts = true
H.inClient(c, function()
	local pos = PRc.project(at)
	WorldViewC.tapScreen(E.v2(pos.X, pos.Y - E.inset))
end)
E.raycastParts = nil
E.run(0.5)
H.expect(H.currentPanel(c) == "tree", "tree", "a tap on it opens its panel", tostring(H.currentPanel(c)))
H.closePanel(c)
cp.shells, cp.wood = 50000, 5000
H.expect(H.req(c, "plot.store", { i = ti }).err == "fixed", "tree", "it isn't cleared away")
H.expect(H.req(c, "plot.place", { id = "tree", x = 0, z = 0, rot = 0 }).err == "bad_payload", "tree", "or bought")
H.expect(H.req(c, "plot.replace", { i = ti, id = "nest" }).err == "bad_payload", "tree", "or replaced")
local mx, mz, mr = PlotRules.spot(cp.tier, (function()
	local others = {}
	for i, q in cp.plot.placed do
		if i ~= ti then
			table.insert(others, q)
		end
	end
	return others
end)(), "tree", tq.x + 6, tq.z + 4, 0)
H.expect(mx ~= nil and H.req(c, "plot.move", { i = ti, x = mx, z = mz, rot = mr }).ok and tq.x == mx and tq.z == mz, "tree", "it moves like any piece", string.format("to %s,%s", tostring(mx), tostring(mz)))
E.run(0.4)
local moved = false
for _, m in cdecor:GetChildren() do
	if m:GetAttribute("Decor") == "tree" and string.find(m.Name, string.format(":tree:%d:%d:", tq.x, tq.z), 1, true) then
		moved = true
	end
end
H.expect(moved, "tree", "its model rebuilt where it stands now")
tw, td = PlotRules.footprint(tq.id, tq.rot)
-- Build mode: tapping the tree picks it up to move, Clear away off
local BuildC = H.cmod(c, "UI.BuildUI")
H.inClient(c, BuildC.open)
E.run(0.5)
E.raycastParts = true
H.inClient(c, function()
	local pos = PRc.project(E.v3(cox + tq.x + tw / 2 + 0.3, Street.LAWN_Y + 0.05, coz + tq.z + td / 2 + 0.3))
	BuildC.tapScreen(E.v2(pos.X, pos.Y - E.inset), false)
end)
E.raycastParts = nil
E.run(0.4)
local store = H.buttonNamed(c, "Store", true)
H.expect(store ~= nil and H.buttonNamed(c, "Store") == nil, "tree", "Build mode: the tree picked up, Clear away greyed out")
H.inClient(c, BuildC.close)
E.run(0.3)
H.checkProfile(c, "tree")
H.checkMirror(c, "tree")

report(E, H)
