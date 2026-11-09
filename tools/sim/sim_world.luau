-- The street and the plot (GAME_DESIGN 8, 9; docs/ARCHITECTURE.md 7.5, 10.2, 10.6, 10.7): the whole street built at
-- start (every road stretch, an empty lot on every plot); two studios on plots 1 and 2 with their offices, lands,
-- attributes and founders; each client drawing its own idea team, the neighbour's and both founders; a founder
-- walking onto the neighbour's lot (the camera follows, Home shows) and going home (and its cooldown); buying (with
-- coins), placing, moving and storing decor with every refusal, the server's Static.Decor following piece by piece;
-- the same through Build mode's UI; malicious plot payloads; a leaving player's plot back to an empty lot; an old
-- save (the old studio in its Loft) loading; a full street kicking the seventh player.
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
local Office = H.sharedServer("Data.Office")
local Decor = H.sharedServer("Data.Decor")
local Plot = H.sharedServer("Logic.Plot")
local Schema = H.sharedServer("Logic.Schema")

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

------------------------------------------------------------------ 1. the street before anyone joins
E.phase = "street"
local plots = E.workspace:FindFirstChild("Plots")
H.expect(plots ~= nil, "street", "Workspace.Plots exists")
local streetFolder = plots and plots:FindFirstChild("Street")
local roads, ends = 0, 0
if streetFolder then
	for _, c in streetFolder:GetChildren() do
		if c.Name == "Road" then
			roads += 1
		elseif c.Name == "StreetEnds" then
			ends += 1
		end
	end
end
H.expect(roads == Street.MAX and ends == 1, "street", "a road stretch per plot and the street's ends", string.format("%d roads, %d ends", roads, ends))
for i = 1, Street.MAX do
	local m = plotModel(i)
	H.expect(m ~= nil and m:GetAttribute("Owner") == 0 and m:FindFirstChild("EmptyLot", true) ~= nil and officeOf(i) == nil, "street", "plot " .. i .. " is an empty lot")
end

------------------------------------------------------------------ 2. two studios
E.phase = "studios"
local a = H.addPlayer({ userId = 9401, name = "Ava" })
E.run(2)
local b = H.addPlayer({ userId = 9402, name = "Bo" })
E.run(3)
local sa, sb = H.session(a), H.session(b)
H.expect(sa and sa.plot == 1 and sb and sb.plot == 2, "studios", "plots 1 and 2", string.format("%s %s", tostring(sa and sa.plot), tostring(sb and sb.plot)))
local function crewMatches(i, prof)
	local crew = plotModel(i):GetAttribute("Crew")
	if type(crew) ~= "string" then
		return false
	end
	local n, ok = 0, true
	for part in string.gmatch(crew, "[^;]+") do
		n += 1
		local desk, skin, hair, style, shirt = string.match(part, "^(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.%d$")
		local found = false
		for _, s in prof.team do
			local l = s.look
			if s.desk == tonumber(desk) and l.skin == tonumber(skin) and l.hair == tonumber(hair) and l.style == tonumber(style) and l.shirt == tonumber(shirt) then
				found = true
			end
		end
		ok = ok and found
	end
	return ok and n == #prof.team
end
for k, p in { a, b } do
	local m = plotModel(k)
	local prof = H.profile(p)
	H.expect(m:GetAttribute("Owner") == p.UserId and m:GetAttribute("StudioName") == p.Name .. "'s Studio", "studios", p.Name .. ": owner and studio name", tostring(m:GetAttribute("StudioName")))
	H.expect(m:GetAttribute("Tier") == 1 and m:GetAttribute("Working") == true, "studios", p.Name .. ": tier 1, the idea team at work")
	H.expect(crewMatches(k, prof), "studios", p.Name .. ": the Crew attribute is their idea team", tostring(m:GetAttribute("Crew")))
	local office = officeOf(k)
	H.expect(office ~= nil and office:GetAttribute("Tier") == 1, "studios", p.Name .. ": the office is built")
	H.expect(staticOf(k):FindFirstChild("Land") ~= nil and staticOf(k).Land:FindFirstChild("Land") ~= nil and m:FindFirstChild("EmptyLot", true) == nil, "studios", p.Name .. ": the land replaced the empty lot")
	local f = prof.founder
	H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", f.skin, f.hair, f.style, f.shirt) and p:GetAttribute("Plot") == k, "studios", p.Name .. ": Founder and Plot attributes", tostring(p:GetAttribute("Founder")))
	-- on their own footpath
	local plan = Office.plan(1)
	local sx, sz = Street.spawn(plan.maxX, plan.maxZ)
	local ox, oz = Street.origin(k)
	local root = rootOf(p)
	H.expect(root ~= nil and math.abs(root.Position.X - (ox + sx)) < 0.5 and math.abs(root.Position.Z - (oz + sz)) < 0.5, "studios", p.Name .. ": the founder appears on their footpath", root and tostring(root.Position))
	H.checkProfile(p, "studio " .. p.Name)
	H.checkMirror(p, "studio " .. p.Name)
end
local res
local pa = H.profile(a)
pa.rate = 7.5
pa.stats.games = 3
H.push(a, 0.5)
H.expect(plotModel(1):GetAttribute("Games") == 3 and plotModel(1):GetAttribute("Rate") == 7, "studios", "the plot shows the games and the income", string.format("%s %s", tostring(plotModel(1):GetAttribute("Games")), tostring(plotModel(1):GetAttribute("Rate"))))
-- each client draws its own crew, the neighbour's and both founders
for _, pair in { { a, b }, { b, a } } do
	local me, other = pair[1], pair[2]
	local WV = H.cmod(me, "Controllers.WorldView")
	local AV = H.cmod(me, "Controllers.AvatarView")
	local own, oth = #H.profile(me).team, #H.profile(other).team
	H.expect(WV.ownRigCount() == own and WV.rigCount() == own + oth, "studios", me.Name .. ": own crew and the neighbour's", string.format("%d own of %d, %d all of %d", WV.ownRigCount(), own, WV.rigCount(), own + oth))
	H.expect(AV.count() == 2, "studios", me.Name .. ": both founders", tostring(AV.count()))
end
-- the plot signs' labels
local canvasA = a.PlayerGui:FindFirstChild("World") and a.PlayerGui.World:FindFirstChild("Canvas")
local s1 = canvasA and canvasA:FindFirstChild("Sign_1")
local s3 = canvasA and canvasA:FindFirstChild("Sign_3")
H.expect(s1 ~= nil and s1.Text == "Ava's Studio", "studios", "plot 1's sign label", s1 and s1.Text)
H.expect(s3 ~= nil and s3.Text == "Empty lot", "studios", "an empty lot's sign label", s3 and s3.Text)

------------------------------------------------------------------ 3. walking the street
E.phase = "walk"
local CCa = H.cmod(a, "Controllers.CameraController")
local hx, hy = CCa.view().grid.px, CCa.view().grid.py
local px0, py0 = CCa.pan()
H.expect(px0 == hx and py0 == hy, "walk", "at home the view holds the home pan", string.format("%d,%d vs %d,%d", px0, py0, hx, hy))
H.expect(H.buttonNamed(a, "Home") == nil, "walk", "no Home button at home")
local ox2 = Street.origin(2)
a.Character:PivotTo(E.cf.new(ox2 + 18, 3, 24))
E.run(3)
local px1, py1 = CCa.pan()
H.expect(px1 ~= hx or py1 ~= hy, "walk", "the camera follows the founder onto the neighbour's lot", string.format("%d,%d", px1, py1))
H.expect(H.buttonNamed(a, "Home") ~= nil, "walk", "the Home button shows off the own lot")
-- the founder stays in view: its feet project inside the screen
local PRa = H.cmod(a, "Pixel.PixelRenderer")
local onScreen = H.inClient(a, function()
	local _, on = PRa.project(rootOf(a).Position)
	return on
end)
H.expect(onScreen == true, "walk", "the founder is on screen")
res = H.req(a, "char.home", {})
H.expect(res.ok, "walk", "char.home", tostring(res.err))
E.run(0.5)
local plan1 = Office.plan(1)
local sx, sz = Street.spawn(plan1.maxX, plan1.maxZ)
local ox1, oz1 = Street.origin(1)
local root = rootOf(a)
H.expect(root ~= nil and math.abs(root.Position.X - (ox1 + sx)) < 0.5 and math.abs(root.Position.Z - (oz1 + sz)) < 0.5, "walk", "home: back on the footpath", root and tostring(root.Position))
res = H.req(a, "char.home", {})
H.expect(not res.ok and res.err == "cooldown", "walk", "a second home within the cooldown", tostring(res.err))
E.run(3)
local px2, py2 = CCa.pan()
H.expect(px2 == hx and py2 == hy, "walk", "the view glides back home", string.format("%d,%d", px2, py2))
H.expect(H.buttonNamed(a, "Home") == nil, "walk", "the Home button goes once home")

------------------------------------------------------------------ 4. decor: buy, place, move, store
E.phase = "decor"
local prof = H.profile(a)
prof.rate = 0 -- no income ticks while the coins are compared
prof.coins = 1000000
local m0 = prof.coins
res = H.req(a, "plot.buy", { id = "gnome" })
H.expect(res.ok and prof.coins == m0 - Decor.byId.gnome.price and prof.plot.owned.gnome, "decor", "buy a gnome: its price in coins", tostring(res.err))
res = H.req(a, "plot.buy", { id = "gnome" })
H.expect(not res.ok and res.err == "max", "decor", "a piece once", tostring(res.err))
H.req(a, "plot.buy", { id = "flowers" })
H.req(a, "plot.buy", { id = "bench" })
local keep = prof.coins
prof.coins = 10
res = H.req(a, "plot.buy", { id = "oak" })
H.expect(not res.ok and res.err == "money", "decor", "not enough coins", tostring(res.err))
prof.coins = keep
E.run(0.3)
H.checkMirror(a, "bought")
local v = H.view(a)
H.expect(v.decor and v.decor.owned.gnome and v.decor.owned.flowers, "decor", "the view mirrors the owned decor")

-- a cell where a piece fits (from the south-east yard, the side the camera sees)
local function spot(id, rot, placed, tier)
	local pr = Street.plot(tier or 1)
	for z = pr.z1 - 2, pr.z0 + 1, -1 do
		for x = pr.x1 - 2, pr.x0 + 1, -1 do
			if Plot.fits(tier or 1, placed, id, x, z, rot) then
				return x, z
			end
		end
	end
	return nil, nil
end
local gx, gz = spot("gnome", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "gnome", x = gx, z = gz, rot = 0 })
H.expect(res.ok and #prof.plot.placed == 1, "decor", "place a gnome", tostring(res.err))
E.run(0.3)
local decor = decorOf(1)
local keyG = string.format("gnome:%d:%d:0", gx, gz)
local modelG = decor and decor:FindFirstChild(keyG)
H.expect(modelG ~= nil, "decor", "the server built it as " .. keyG)
res = H.req(a, "plot.place", { id = "gnome", x = gx, z = gz, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "decor", "not on another piece", tostring(res.err))
res = H.req(a, "plot.place", { id = "gnome", x = 0, z = 0, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "decor", "not in the office", tostring(res.err))
local fp = Street.footpath(plan1.maxX, plan1.maxZ)
res = H.req(a, "plot.place", { id = "gnome", x = math.floor(fp.x0) + 1, z = math.floor(fp.z0) + 3, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "decor", "not on the footpath", tostring(res.err))
res = H.req(a, "plot.place", { id = "gnome", x = Street.plot(1).x1 + 5, z = 10, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "decor", "not off the plot", tostring(res.err))
res = H.req(a, "plot.place", { id = "oak", x = 15, z = 15, rot = 0 })
H.expect(not res.ok and res.err == "locked", "decor", "not a piece not owned", tostring(res.err))
local fx, fz = spot("flowers", 90, prof.plot.placed)
res = H.req(a, "plot.place", { id = "flowers", x = fx, z = fz, rot = 90 })
H.expect(res.ok and #prof.plot.placed == 2, "decor", "place flowers turned a quarter", tostring(res.err))
E.run(0.3)
H.expect(decor:FindFirstChild(keyG) == modelG, "decor", "the gnome's model was kept (only the new piece built)")
H.expect(#decor:GetChildren() == 2, "decor", "a model a piece", tostring(#decor:GetChildren()))
-- move the gnome, then store the flowers
local mx, mz = spot("gnome", 0, prof.plot.placed)
res = H.req(a, "plot.move", { i = 1, x = mx, z = mz, rot = 0 })
H.expect(res.ok and prof.plot.placed[1].x == mx and prof.plot.placed[1].z == mz, "decor", "move the gnome", tostring(res.err))
E.run(0.3)
H.expect(decor:FindFirstChild(keyG) == nil and decor:FindFirstChild(string.format("gnome:%d:%d:0", mx, mz)) ~= nil, "decor", "its model moved with it")
local keyF = string.format("flowers:%d:%d:90", fx, fz)
local modelF = decor:FindFirstChild(keyF)
H.expect(modelF ~= nil, "decor", "the flowers' model is there")
res = H.req(a, "plot.move", { i = 1, x = 0, z = 0, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "decor", "not moved into the office", tostring(res.err))
res = H.req(a, "plot.store", { i = 2 })
H.expect(res.ok and #prof.plot.placed == 1 and prof.plot.owned.flowers, "decor", "store the flowers (still owned)", tostring(res.err))
E.run(0.3)
H.expect(decor:FindFirstChild(keyF) == nil and #decor:GetChildren() == 1, "decor", "their model went")
-- the piece limit
local Session = H.smod("Session")
local PlotService = H.smod("PlotService")
local limit = Plot.limit(1)
while #prof.plot.placed < limit - 1 do
	local x, z = spot("gnome", 0, prof.plot.placed)
	if x == nil then
		break
	end
	table.insert(prof.plot.placed, { id = "gnome", x = x, z = z, rot = 0 })
end
H.inClient(a, function() end)
local co = coroutine.create(function()
	PlotService.buildDecor(sa)
	Session.markDirty(sa)
end)
E.tagThread(co, E.serverCtx)
E.resume(co)
E.run(0.5)
H.expect(#decor:GetChildren() == limit - 1, "decor", "the server builds a filled plot", tostring(#decor:GetChildren()))
local lx, lz = spot("gnome", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "gnome", x = lx, z = lz, rot = 0 })
H.expect(res.ok and #prof.plot.placed == limit, "decor", "the last piece fits", tostring(res.err))
E.run(0.2)
local lx2, lz2 = spot("gnome", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "gnome", x = lx2 or 20, z = lz2 or 20, rot = 0 })
H.expect(not res.ok and res.err == "full", "decor", "the plot's piece limit", tostring(res.err))
-- back to two pieces for the rest
while #prof.plot.placed > 2 do
	table.remove(prof.plot.placed)
end
co = coroutine.create(function()
	PlotService.buildDecor(sa)
	Session.markDirty(sa)
end)
E.tagThread(co, E.serverCtx)
E.resume(co)
E.run(0.5)
H.expect(#decor:GetChildren() == 2, "decor", "and back", tostring(#decor:GetChildren()))
H.checkProfile(a, "decor")
H.checkMirror(a, "decor")

------------------------------------------------------------------ 5. Build mode through the UI
E.phase = "build-ui"
E.run(0.3)
local BuildUI = H.cmod(a, "UI.BuildUI")
local UIKit = H.cmod(a, "UI.UIKit")
H.expect(H.clickNamed(a, "Menu_build"), "build", "the HUD's Build button")
H.expect(BuildUI.isOpen() and CCa.isFree(), "build", "Build mode is open, the view free")
E.run(0.4)
H.expect(H.buttonNamed(a, "Buy_oak") ~= nil, "build", "the tray offers what the coins can buy")
-- the screen point (InputObject space: below the top bar) where the client shows a world point
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
H.inClient(a, function()
	BuildUI.pick("gnome", 0)
end)
local ux, uz = spot("gnome", 0, prof.plot.placed)
local cellWorld = E.v3(ox1 + ux + 0.5, Street.LAWN_Y, oz1 + uz + 0.5)
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(cellWorld), false)
end)
E.run(0.3)
local fpGhost = ghostFootprint()
H.expect(fpGhost ~= nil, "build", "a ghost with its footprint")
-- the footprint is a raised neon frame of edges: cyan (screen_on) where it fits, red (berry_red) where not
local Blocks = H.sharedServer("Models.Blocks")
local function edgeColor(fp)
	local e = fp and fp:FindFirstChildWhichIsA("BasePart")
	return e and e.Color
end
H.expect(edgeColor(fpGhost) == Blocks.color("screen_on"), "build", "cyan where it fits", tostring(edgeColor(fpGhost)))
local placedBefore = #prof.plot.placed
H.expect(H.clickNamed(a, "Place"), "build", "the Place button")
E.run(0.3)
local last = prof.plot.placed[#prof.plot.placed]
H.expect(#prof.plot.placed == placedBefore + 1 and last.id == "gnome" and last.x == ux and last.z == uz, "build", "placed where tapped", last and string.format("%s %d,%d (wanted %d,%d)", last.id, last.x, last.z, ux, uz))
-- red on the office
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(E.v3(ox1, 0, oz1)), false)
end)
E.run(0.3)
fpGhost = ghostFootprint()
H.expect(edgeColor(fpGhost) == Blocks.color("berry_red"), "build", "red on the office", tostring(edgeColor(fpGhost)))
local placeBtn = H.buttonNamed(a, "Place", true)
H.expect(placeBtn ~= nil and getD(placeBtn).props.AutoButtonColor == false, "build", "Place is off where it does not fit")
H.clickNamed(a, "Cancel")
H.expect(ghostFootprint() == nil, "build", "Cancel takes the ghost away")
-- tap the placed gnome: picked up to move; store it (the sim engine casts rays against parts only when asked:
-- just for this tap, AvatarView's ground ray every frame would be slow)
E.raycastParts = true
H.inClient(a, function()
	BuildUI.tapScreen(screenOf(E.v3(ox1 + ux + 0.5, Street.LAWN_Y + 0.6, oz1 + uz + 0.5)), false)
end)
E.raycastParts = nil
E.run(0.3)
H.expect(H.buttonNamed(a, "Store") ~= nil, "build", "tapping a piece picks it up (Store shows)")
H.clickNamed(a, "Store")
E.run(0.3)
H.expect(#prof.plot.placed == placedBefore, "build", "stored through the UI", tostring(#prof.plot.placed))
H.clickNamed(a, "BuildDone")
E.run(0.4)
H.expect(not BuildUI.isOpen() and not CCa.isFree(), "build", "Done: closed, the view follows again")
H.expect(ghostFootprint() == nil, "build", "no ghost left")

------------------------------------------------------------------ 6. a bigger room from an old save
E.phase = "loft"
-- no office moves any more: a studio keeps the room its save had (an old Loft save, here), and its plot
H.expect(plotModel(1):GetAttribute("Tier") == 1 and officeOf(1):GetAttribute("Tier") == 1, "loft", "a new studio stays in the garage")
H.checkProfile(a, "loft")
H.checkMirror(a, "loft")

------------------------------------------------------------------ 7. malicious plot payloads
E.phase = "malicious"
local function snap()
	local q = H.profile(a)
	local owned = {}
	for k in q.plot.owned do
		table.insert(owned, k)
	end
	table.sort(owned)
	local placed = {}
	for _, x in q.plot.placed do
		table.insert(placed, string.format("%s:%d:%d:%d", x.id, x.x, x.z, x.rot))
	end
	return { coins = q.coins, owned = table.concat(owned, ","), placed = table.concat(placed, ";") }
end
local function refused(label, err, action, payload)
	local ok, out = H.raw(a, action, payload)
	H.expect(ok and type(out) == "table" and out.ok == false and out.err == err, "malicious", label .. " refused with " .. err, type(out) == "table" and tostring(out.err) or tostring(out))
	E.run(0.15)
end
local before = snap()
refused("a fractional x", "bad_payload", "plot.place", { id = "gnome", x = 1.5, z = 20, rot = 0 })
refused("x out of range", "bad_payload", "plot.place", { id = "gnome", x = 100, z = 20, rot = 0 })
refused("a 45 degree turn", "bad_payload", "plot.place", { id = "gnome", x = 20, z = 20, rot = 45 })
refused("NaN", "bad_payload", "plot.place", { id = "gnome", x = 0 / 0, z = 20, rot = 0 })
refused("index 0", "bad_payload", "plot.move", { i = 0, x = 20, z = 20, rot = 0 })
refused("index 999", "bad_payload", "plot.store", { i = 999 })
refused("a piece not there", "bad_payload", "plot.store", { i = 60 })
refused("an unknown piece", "bad_payload", "plot.buy", { id = "castle" })
refused("an extra field", "bad_payload", "plot.buy", { id = "gnome", price = 0 })
refused("a home with a payload", "bad_payload", "char.home", { x = 1 })
refused("placing an unknown piece", "locked", "plot.place", { id = "castle", x = 20, z = 20, rot = 0 })
refused("a string coord", "bad_payload", "plot.place", { id = "gnome", x = "20", z = 20, rot = 0 })
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
E.run(0.3)

------------------------------------------------------------------ 8. a player leaves
E.phase = "leave"
E.removePlayer(b, "leave")
E.run(2)
local m2 = plotModel(2)
H.expect(m2 and m2:GetAttribute("Owner") == 0 and m2:GetAttribute("StudioName") == nil and m2:FindFirstChild("EmptyLot", true) ~= nil and officeOf(2) == nil, "leave", "their plot is an empty lot again")
local WVa = H.cmod(a, "Controllers.WorldView")
H.expect(WVa.rigCount() == WVa.ownRigCount(), "leave", "Ava no longer draws Bo's crew", string.format("%d all, %d own", WVa.rigCount(), WVa.ownRigCount()))
H.expect(H.cmod(a, "Controllers.AvatarView").count() == 1, "leave", "one founder left")

------------------------------------------------------------------ 9. an old save (version 2, the old studio in the Loft)
E.phase = "v1"
local STORE = Tuning.DataStoreName .. "/global"
local old = {
	v = 2,
	money = 23456,
	office = 2,
	staff = { { id = 1, name = "Old Timer", look = { skin = 1, hair = 2, style = 3, shirt = 4 }, desk = 2 } },
	founder = { skin = 4, hair = 1, style = 2, shirt = 3 },
	plot = { owned = { gnome = true }, placed = { { id = "gnome", x = 30, z = 30, rot = 0 } } },
}
E.cloud.stores[STORE] = E.cloud.stores[STORE] or {}
E.cloud.stores[STORE]["u_9403"] = { value = { data = E.deepCopy(old) }, meta = {}, userIds = {}, version = 1, created = E.SIM.now, updated = E.SIM.now }
local c = H.addPlayer({ userId = 9403, name = "Old" })
E.run(3)
local cp = H.profile(c)
H.expect(cp ~= nil and cp.v == Schema.VERSION and cp.money == nil, "v1", "a version 2 save loads as the idea loop", cp and string.format("v%d", cp.v))
H.expect(cp ~= nil and cp.office == 2 and cp.founder.skin == 4 and cp.plot.owned.gnome and cp.team[1].name == "Old Timer", "v1", "its Loft, founder, decor and crew kept")
H.expect(H.session(c) and H.session(c).plot == 2, "v1", "on the freed plot 2", tostring(H.session(c) and H.session(c).plot))
H.expect(officeOf(2) ~= nil and officeOf(2):GetAttribute("Tier") == 2, "v1", "its Loft is built")
H.checkProfile(c, "v1")
H.checkMirror(c, "v1")

------------------------------------------------------------------ 10. a full street
E.phase = "full"
local extra = {}
for k = 1, Street.MAX - 2 do
	table.insert(extra, H.addPlayer({ userId = 9410 + k, name = "Extra" .. k, client = false, noCharacter = true }))
	E.run(1.5)
end
local taken = 0
for i = 1, Street.MAX do
	if plotModel(i):GetAttribute("Owner") ~= 0 then
		taken += 1
	end
end
H.expect(taken == Street.MAX, "full", "every plot taken", tostring(taken))
local seventh = H.addPlayer({ userId = 9420, name = "Late", client = false, noCharacter = true })
E.run(2)
local kicked = false
for _, k in E.kicks or {} do
	if k.userId == 9420 then
		kicked = true
	end
end
H.expect(kicked and H.session(seventh) == nil, "full", "the seventh player is told the street is full")

report(E, H)
