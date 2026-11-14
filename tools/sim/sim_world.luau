-- The sea and the islands (GAME_DESIGN 4, 6, 8; docs/ARCHITECTURE.md 7.5, 10.2, 10.6, 10.7): the whole sea built at
-- start (no docks: open water on every lot with the seabed the founders swim on); two islands on plots 1 and 2 with
-- their lands (no coast walls, the sign on the beach), attributes and founders, each with its Tree of Life (its model
-- by its stage) and its first lot of eggs (the plot's Eggs attribute its session's); each client drawing its own
-- island's hut driftlings, the neighbour's and both founders, no villagers, and both islands' eggs round their trees;
-- the sea between two islands open to swim; a founder going onto the neighbour's island (the camera follows, Home
-- shows) and going home (and its cooldown); the island's small lives (AmbientView: birds alighting on the own island,
-- flying off when the founder walks up, back later, away at night); placing (paid in shells), moving and clearing
-- buildings with every refusal (no upgrades, the piece limit with the tree apart, the huts' limit), the server's
-- Static.Decor following piece by piece; the same through Build mode's catalog (the Work tab's Farms row, a locked card
-- and its tooltip, the Nature tab's Plants row, the Huts tab at the huts' limit, paths, fences drawn as a line and a
-- box and erased, water dug and a path's eraser leaving it); fences and water on both islands (their models in
-- Static.Decor, a water tile's name carrying its neighbours and built again when one is dug next to it, lily pads only
-- on water and gone with it, the eraser's kind, a fence never through a building but along its side, a building never
-- across a fence, the founder wading through a river); the piece, tile and fence limits each refusing one more (full)
-- on their own while the others still take theirs, Build mode's count on each tab; malicious plot payloads (fences and
-- erasers among them); a leaving player's island back to open water with its eggs gone; a full sea kicking the seventh
-- player; a newcomer's tree planted and its first lot laid; every claimed island's eggs in its attribute, drawn by the
-- clients near it, the price tags over the own ones only; the tree fixed (a tap opens its panel; never cleared away,
-- bought or replaced; it moves like any piece, its eggs with it; Build mode's Clear away off for it) while every other
-- piece clears away; a tier 20 island from a saved profile (its land far north of Driftling Haven's end, no walls up
-- there either and the seabed under the sea there, the founder at home up there, pieces, tiles and fences fitting
-- there, the pieces of tiers 11 to 20 built there, Build mode's button saying Island max).
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
local IslandL = H.sharedServer("Logic.Island")
-- The shells profile `pr` gained since `s0` come to `want`, give or take what its island made on its own since `t0` (the
-- one store: the buildings go on selling while a request is answered).
local function shellsNear(pr: any, s0: number, want: number, t0: number): (boolean, string)
	local got = pr.shells - s0
	local own = math.max(0, IslandL.rates(pr).shells) / Tuning.TurnSeconds * (E.now() - t0) * 1.5 + 1
	return got >= want - 1 and got <= want + own, string.format("%+.1f shells (want %+d)", got, want)
end
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
H.expect(stretches == Street.MAX and ends == 1, "sea", "the water of every plot and the sea's ends", string.format("%d stretches, %d ends", stretches, ends))
-- no docks: no boardwalk, pier or boat; the water lets a founder through, the seabed under it holds them, out of the
-- pixel filter's rays
do
	local docks, water, bed = {}, 0, 0
	for _, d in if seaFolder then seaFolder:GetDescendants() else {} do
		if d:IsA("BasePart") then
			if d.Name == "Plank" or d.Name == "Boardwalk" or d.Name == "Pier" or d.Name == "Post" or d.Name == "Mailbox" then
				table.insert(docks, d.Name)
			elseif d.Name == "Water" then
				water += if d.CanCollide == false and d:GetAttribute("PixelWater") == 1 then 1 else 0
			elseif d.Name == "Seabed" then
				local top = d.Position.Y + d.Size.Y / 2
				bed += if d.CanCollide and d.Transparency == 1 and d.CollisionGroup == "Bounds" and math.abs(top - Street.SEABED_Y) < 1e-3 then 1 else 0
			end
		end
	end
	H.expect(#docks == 0, "sea", "no docks on the sea", table.concat(docks, ", "))
	H.expect(water >= Street.MAX and bed >= Street.MAX, "sea", "water a founder swims through, an invisible seabed under it for every plot", string.format("%d water, %d seabeds", water, bed))
end
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
	-- no docks and no coast walls: the founder swims off any beach; the foam and the shallows let them through, an
	-- invisible shelf under the foam is the step back up to the wet sand
	H.expect(land ~= nil and land:FindFirstChild("Bound", true) == nil and land:FindFirstChild("JettyPlank", true) == nil and land:FindFirstChild("Mailbox", true) == nil, "islands", p.Name .. ": no coast walls, no jetty, no mailbox")
	local through, shelf = true, nil :: BasePart?
	for _, d in (land :: Instance):GetDescendants() do
		if d:IsA("BasePart") and (d.Name == "Foam" or d.Name == "Shallows") and d.CanCollide then
			through = false
		elseif d:IsA("BasePart") and d.Name == "Shelf" then
			shelf = d
		end
	end
	H.expect(through, "islands", p.Name .. ": the foam and the shallows let a swimmer through")
	local shelfTop = if shelf then shelf.Position.Y + shelf.Size.Y / 2 else 0
	H.expect(shelf ~= nil and shelf.CanCollide and shelf.Transparency == 1 and shelf.CollisionGroup == "Bounds" and shelfTop > Street.SEABED_Y and shelfTop < Street.WET_Y, "islands", p.Name .. ": an invisible shelf under the foam, a step between the seabed and the wet sand", tostring(shelfTop))
	-- the island's sign on its south beach
	local sign = land and land:FindFirstChild("SignBoard", true)
	local gx, gz = Street.sign(1)
	local ox0, oz0 = Street.origin(k)
	H.expect(sign ~= nil and sign:IsA("BasePart") and math.abs(sign.Position.X - (ox0 + gx)) < 1 and math.abs(sign.Position.Z - (oz0 + gz)) < 1, "islands", p.Name .. ": its sign on the south beach", sign and tostring(sign.Position))
	local f = prof.founder
	H.expect(p:GetAttribute("Founder") == string.format("%d.%d.%d.%d", f.skin, f.hair, f.style, f.shirt) and p:GetAttribute("Plot") == k, "islands", p.Name .. ": Founder and Plot attributes", tostring(p:GetAttribute("Founder")))
	local sx, sz = Street.spawn()
	local ox, oz = Street.origin(k)
	local root = rootOf(p)
	H.expect(root ~= nil and math.abs(root.Position.X - (ox + sx)) < 0.5 and math.abs(root.Position.Z - (oz + sz)) < 0.5, "islands", p.Name .. ": the founder appears on their plaza", root and tostring(root.Position))
	H.checkProfile(p, "island " .. p.Name)
	settled(p)
	H.checkMirror(p, "island " .. p.Name)
end
-- driftlings on both islands (the hut's; no villagers)
for k, p in { a, b } do
	local prof = H.profile(p)
	prof.shells = 55000
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

------------------------------------------------------------------ 3. swimming over to the neighbour
E.phase = "walk"
-- the sea between island 1 and island 2 is open to swim: across from one's east shallows to the other's west ones,
-- nothing collidable stands between the seabed and a head's height (the islands' land and the sailboats apart), and the
-- seabed runs under all of it
do
	local o1, o2 = Street.origin(1), Street.origin(2)
	local x0, x1 = o1 + Street.isle(1).rx + 10, o2 - Street.isle(1).rx - 10
	local blockers, holes = {}, 0
	for _, z in { 0, 12, 24, 40 } do
		for _, d in plots:GetDescendants() do
			if d:IsA("BasePart") and d.CanCollide then
				local c, sz = d.Position, d.Size
				local y0, y1 = c.Y - sz.Y / 2, c.Y + sz.Y / 2
				if c.X + sz.X / 2 > x0 and c.X - sz.X / 2 < x1 and c.Z + sz.Z / 2 > z and c.Z - sz.Z / 2 < z and y1 > Street.SEABED_Y + 0.05 and y0 < 3 then
					table.insert(blockers, string.format("%s (%s) at z %d", d.Name, d.Parent and d.Parent.Name or "?", z))
				end
			end
		end
		for x = math.ceil(x0), math.floor(x1), 4 do
			local held = false
			for _, d in plots:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Seabed" then
					local c, sz = d.Position, d.Size
					if math.abs(x - c.X) <= sz.X / 2 and math.abs(z - c.Z) <= sz.Z / 2 then
						held = true
						break
					end
				end
			end
			holes += if held then 0 else 1
		end
	end
	H.expect(#blockers == 0, "walk", "the sea between two islands is open to swim", table.concat(blockers, ", "))
	H.expect(holes == 0, "walk", "the seabed under all of it", tostring(holes))
end
-- a founder in that sea swims (AvatarView: the ground under them is the sea, the rig sunk to its chest at the
-- surface, the strokes heard, a ring of foam round them; the HUD holds the jump and slows them to Tuning.SwimSpeed);
-- with E.raycastParts the ground ray hits every part, as in Roblox
do
	local AV = H.cmod(a, "Controllers.AvatarView")
	local AudioA = H.cmod(a, "Controllers.Audio")
	local mid = (Street.origin(1) + Street.origin(2)) / 2
	local s0 = H.inClient(a, AudioA.playCount, "step_water")
	E.raycastParts = true
	for k = 0, 19 do
		a.Character:PivotTo(E.cf.new(mid + k * 0.6, 3, 16))
		E.run(0.1)
	end
	local swimming = H.inClient(a, AV.swimming)
	local s1 = H.inClient(a, AudioA.playCount, "step_water")
	local dynF = E.workspace:FindFirstChild("PixelDynamic")
	local rig = dynF and dynF:FindFirstChild("Founder_" .. a.UserId)
	local torso = rig and rig:FindFirstChild("Torso", true)
	local ring = dynF and dynF:FindFirstChild("Ripple", true)
	local ringPart = ring and ring:FindFirstChild("Ring1")
	local hum = a.Character:FindFirstChildOfClass("Humanoid")
	E.raycastParts = nil
	H.expect(swimming == true, "walk", "in the sea between two islands the founder swims", tostring(swimming))
	H.expect(torso ~= nil and torso.Position.Y < Street.WATER_Y + 1 and torso.Position.Y > Street.WATER_Y - 1.5, "walk", "the rig sunk to its chest at the surface", torso and string.format("%.2f", torso.Position.Y))
	H.expect(ringPart ~= nil and math.abs(ringPart.Position.Y - Street.WATER_Y) < 0.2, "walk", "a ring of foam round them on the water", ringPart and string.format("%.2f", ringPart.Position.Y))
	H.expect(s1 > s0, "walk", "the strokes heard", string.format("%d -> %d", s0, s1))
	H.expect(hum ~= nil and hum.WalkSpeed == Tuning.SwimSpeed and hum.JumpHeight == 0, "walk", "slower in the water, and no jump", hum and string.format("speed %s jump %s", tostring(hum.WalkSpeed), tostring(hum.JumpHeight)))
	-- back home on the plaza for the camera's checks
	local hx, hz = Street.spawn()
	local hox, hoz = Street.origin(1)
	a.Character:PivotTo(E.cf.new(hox + hx, 3, hoz + hz))
	E.run(1)
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
-- a tap on one of Bo's driftlings there opens its details, only to look at (the request of 2026-11-14, "allow players
-- to click on creatures to open up a menu seeing their details"): its mutations come with its island's Pals attribute
do
	local CreaturesW = H.sharedServer("Data.Creatures")
	local WVw = H.cmod(a, "Controllers.WorldView")
	local pb = H.profile(b)
	local bx = nil
	for _, x in pb.pals do
		if x.home ~= 0 then
			bx = x
			break
		end
	end
	H.expect(bx ~= nil, "walk", "Bo has a driftling in a hut")
	if bx then
		local muts0 = bx.muts
		bx.muts = { "bright2", "rainy1" }
		H.push(b, 0.8)
		local attr = plotModel(2):GetAttribute("Pals")
		H.expect(type(attr) == "string" and string.find(attr, string.format("%d.%s.%d.%d.bright2,rainy1", bx.id, bx.sp, bx.work, bx.home), 1, true) ~= nil, "walk", "the Pals attribute carries each one's mutations", tostring(attr))
		H.inClient(a, WVw.holdPal, 2, bx.id, 6)
		E.run(0.2)
		local pos = H.inClient(a, WVw.palScreen, 2, bx.id)
		H.expect(pos ~= nil, "walk", "Bo's driftling on Ava's screen", tostring(pos))
		if pos then
			H.inClient(a, WVw.tapScreen, pos)
			E.run(0.4)
			local panel = a.PlayerGui:FindFirstChild("Panel_pal", true)
			local function label(name)
				local l = panel and panel:FindFirstChild(name, true)
				return if l and l:IsA("TextLabel") then l.Text else nil
			end
			local d = CreaturesW.byId[bx.sp]
			H.expect(H.currentPanel(a) == "pal" and d ~= nil and label("Name") == d.name, "walk", "a tap on it opens its details on Ava's screen", string.format("%s %s", tostring(H.currentPanel(a)), tostring(label("Name"))))
			H.expect(label("Mut_bright2") ~= nil and label("Mut_rainy1") ~= nil, "walk", "with its mutations", string.format("%s / %s", tostring(label("Mut_bright2")), tostring(label("Mut_rainy1"))))
			local where = panel and panel:FindFirstChild("Where", true)
			local whereTop = where and where:FindFirstChild("Top")
			H.expect(whereTop ~= nil and whereTop.Text == "Works at the " .. Buildings.byId.patch.name, "walk", "where it works on Bo's island", whereTop and whereTop.Text)
			local ro = label("ReadOnly")
			H.expect(ro ~= nil and string.find(ro, "Bo's Isle", 1, true) ~= nil and H.buttonNamed(a, "PalWork", true) == nil and H.buttonNamed(a, "PalMove", true) == nil and H.buttonNamed(a, "PalSell", true) == nil, "walk", "someone else's: only to look at, no Work, Move or Sell", tostring(ro))
			H.closePanel(a)
		end
		bx.muts = muts0
		H.push(b, 0.4)
	end
end
-- a few steps on the own island: the view moves with every one
local res = H.req(a, "char.home", {})
H.expect(res.ok, "walk", "char.home", tostring(res.err))
E.run(0.5)
local sx, sz = Street.spawn()
local ox1, oz1 = Street.origin(1)
local root = rootOf(a)
H.expect(root ~= nil and math.abs(root.Position.X - (ox1 + sx)) < 0.5 and math.abs(root.Position.Z - (oz1 + sz)) < 0.5, "walk", "home: back on the plaza", root and tostring(root.Position))
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

------------------------------------------------------------------ 3b. the island's small lives (Controllers/AmbientView)
-- Drawn in the pixel layer, which the sims have no picture of: AmbientView.debugRun steps the lives with the view's own
-- camera. By day the birds alight on the own island (its grass, its beach, a fence, a roof or the sign, never the
-- water), fly off when the founder walks up to one and come back a while later; they leave for the night.
E.phase = "ambient"
do
	local AVa = H.cmod(a, "Controllers.AmbientView")
	local DLa = H.cmod(a, "Controllers.DayLight")
	local myPlot = H.session(a).plot
	local tierA = H.profile(a).tier
	local ox, oz = Street.origin(myPlot)
	H.inClient(a, DLa.debugSet, 0.3)
	H.inClient(a, AVa.debugRun, true)
	E.run(1)
	H.inClient(a, AVa.debugHurry)
	E.run(5)
	local st = H.inClient(a, AVa.stats)
	H.expect(st.isles >= 1 and st.visible >= 1, "ambient", "the own island's lives are made while it is in view", string.format("%d islands, %d in view", st.isles, st.visible))
	H.expect(st.decos >= 40, "ambient", "tufts and flowers sown on its lawn", tostring(st.decos))
	local function onIsland(b)
		if Street.plotAt(b.x, b.z) ~= myPlot then
			return false
		end
		local l = Street.layer(tierA, math.floor(b.x - ox), math.floor(b.z - oz))
		if b.on == "lawn" then
			return l == Street.GRASS and math.abs(b.y - Street.LAWN_Y) < 0.01
		elseif b.on == "sand" then
			return l == Street.SAND and math.abs(b.y - Street.SAND_Y) < 0.01
		end
		return (b.on == "roof" or b.on == "fence") and b.y > Street.LAWN_Y and l ~= Street.SEA_CELL and l ~= Street.SHALLOW
	end
	local function perched()
		local list, bad = {}, {}
		for k, b in H.inClient(a, AVa.birds, myPlot) do
			if b.state == "perched" then
				table.insert(list, k)
				if not onIsland(b) then
					table.insert(bad, string.format("%s on %s at %.1f,%.1f,%.1f", b.sp, b.on, b.x, b.y, b.z))
				end
			end
		end
		return list, bad
	end
	local landed, bad = perched()
	H.expect(#landed >= 2, "ambient", "birds alight on the own island by day", tostring(#landed))
	H.expect(#bad == 0, "ambient", "each on its grass, its beach, a fence, a roof or the sign", table.concat(bad, "; "))
	-- the founder walks up to a perched bird: it flies off (and the island's other birds stay put unless near too)
	local k = landed[1]
	local b0 = k and H.inClient(a, AVa.birds, myPlot)[k]
	if b0 then
		a.Character:PivotTo(E.cf.new(b0.x + 1, 3, b0.z + 0.6))
		E.run(0.5)
		local b1 = H.inClient(a, AVa.birds, myPlot)[k]
		H.expect(b1.state == "flee", "ambient", "a bird flies off when the founder walks up to it", b1.state)
		H.expect(b1.y > b0.y, "ambient", "up and away", string.format("%.2f -> %.2f", b0.y, b1.y))
		E.run(3)
		local b2 = H.inClient(a, AVa.birds, myPlot)[k]
		H.expect(b2.state == "away", "ambient", "and is gone a little later", b2.state)
		-- the founder back on the plaza: the birds come back
		a.Character:PivotTo(E.cf.new(ox1 + sx, 3, oz1 + sz))
		E.run(1)
		H.inClient(a, AVa.debugHurry)
		E.run(5)
		local again = perched()
		local b3 = H.inClient(a, AVa.birds, myPlot)[k]
		H.expect(#again >= 2 and b3.state ~= "away", "ambient", "and they come back a while later", string.format("%d perched, the one that fled %s", #again, b3.state))
		-- the founder walking right through them: none stays within a few studs
		local near = 0
		for _, kk in again do
			local bb = H.inClient(a, AVa.birds, myPlot)[kk]
			a.Character:PivotTo(E.cf.new(bb.x, 3, bb.z))
			E.run(0.4)
			if H.inClient(a, AVa.birds, myPlot)[kk].state == "perched" then
				near += 1
			end
		end
		H.expect(near == 0, "ambient", "no bird sits still under the founder's feet", tostring(near))
		a.Character:PivotTo(E.cf.new(ox1 + sx, 3, oz1 + sz))
		E.run(1)
	end
	-- no night (the request of 2026-11-14: "remove the day night cycle"): at the calendar's late hours the birds
	-- are still about
	H.inClient(a, DLa.debugSet, 0.88)
	E.run(4)
	H.inClient(a, AVa.debugHurry)
	E.run(2)
	local about = 0
	for _, b in H.inClient(a, AVa.birds, myPlot) do
		about += if b.state ~= "away" then 1 else 0
	end
	H.expect(about >= 2, "ambient", "the birds stay about at every hour (no night)", tostring(about))
	H.inClient(a, DLa.debugSet, nil)
	H.inClient(a, AVa.debugRun, false)
	E.run(0.5)
end

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
local s0, t0 = prof.shells, E.now()
local gx, gz = spot("stall", 0, prof.plot.placed)
res = H.req(a, "plot.place", { id = "stall", x = gx, z = gz, rot = 0 })
H.expect(res.ok and #prof.plot.placed == n0 + 1, "build", "place a snack stall", tostring(res.err))
-- (shells pay for every piece: "make shells the main currency, allowing you to buy decor and expansions with it"; the
-- island makes a little meanwhile)
do
	local ok, say = shellsNear(prof, s0, -Buildings.byId.stall.shells, t0)
	H.expect(Buildings.byId.stall.shells > 0 and ok and prof.wood == nil, "build", "its shells paid", say)
end
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
do
	-- (the land where the path to the jetty ran, x -2 .. 2 south of the plaza: buildable now)
	local free = false
	for z = Street.PLAZA.z1, Street.PLAZA.z1 + 6 do
		for x = -2, 1 do
			free = free or Plot.fits(1, prof.plot.placed, "torch", x, z, 0)
		end
	end
	H.expect(free, "build", "where the path to the jetty ran: the island's to build on now")
end
res = H.req(a, "plot.place", { id = "torch", x = Street.plot(1).x1 + 5, z = 10, rot = 0 })
H.expect(not res.ok and res.err == "blocked", "build", "not off the island", tostring(res.err))
res = H.req(a, "plot.place", { id = "cafe", x = 10, z = 10, rot = 0 })
H.expect(not res.ok and res.err == "locked", "build", "not a bigger island's building", tostring(res.err))
-- short of shells: refused; with them: built
do
	local shells = prof.shells
	local tx, tz = spot("torch", 0, prof.plot.placed)
	prof.shells = 0
	H.push(a, 0.2)
	res = H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	H.expect(not res.ok and res.err == "money" and #prof.plot.placed == n0 + 1, "build", "not without the shells", tostring(res.err))
	prof.shells = shells
	H.push(a, 0.2)
	res = H.req(a, "plot.place", { id = "torch", x = tx, z = tz, rot = 0 })
	H.expect(res.ok and res.err == nil, "build", "with them: built", tostring(res.err))
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
s0 = prof.shells
res = H.req(a, "plot.upgrade", { i = #prof.plot.placed })
H.expect(not res.ok and res.err == "unknown_action" and stall.lvl == 1 and prof.shells >= s0 - 0.5, "build", "no upgrades: the action is refused, nothing paid", string.format("%s lvl %s shells %s -> %s", tostring(res.err), tostring(stall.lvl), tostring(s0), tostring(prof.shells)))
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
s0, t0 = prof.shells, E.now()
local n1 = #prof.plot.placed
res = H.req(a, "plot.store", { i = #prof.plot.placed })
H.expect(res.ok and #prof.plot.placed == n1 - 1, "build", "clear the stall away", tostring(res.err))
do
	local ok, say = shellsNear(prof, s0, math.floor(Buildings.byId.stall.shells * Tuning.Refund), t0)
	H.expect(ok, "build", "half its price back", say)
end
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
-- the housing limit (GAME_DESIGN 4, Tuning.HousingLimit: since 2026-11-14 the huts' room together, not their count): a
-- tier-1 island houses eight, four Driftling Huts; one more is refused (huts) with nothing paid
local most = Plot.housingLimit(prof.tier)
local addedHuts = {}
prof.shells += 2000
H.push(a, 0.2)
while Plot.housing(prof.plot.placed) + Buildings.byId.nest.slots <= most and #addedHuts < 10 do
	local x, z = spot("nest", 0, prof.plot.placed)
	res = if x then H.req(a, "plot.place", { id = "nest", x = x, z = z, rot = 0 }) else { ok = false, err = "no spot" }
	if not H.expect(res.ok, "build", "a hut under the limit", tostring(res.err)) then
		break
	end
	table.insert(addedHuts, prof.plot.placed[#prof.plot.placed].uid)
end
H.expect(most == Tuning.HousingLimit[1] and Plot.housing(prof.plot.placed) == most, "build", "huts up to the island's room", string.format("%d of %d", Plot.housing(prof.plot.placed), most))
do
	local hx, hz = spot("nest", 0, prof.plot.placed)
	local n, shellsH = #prof.plot.placed, prof.shells
	res = H.req(a, "plot.place", { id = "nest", x = hx or 20, z = hz or 20, rot = 0 })
	H.expect(hx ~= nil and not res.ok and res.err == "huts" and #prof.plot.placed == n and prof.shells >= shellsH - 1e-6, "build", "one hut past the limit refused (huts), nothing paid", tostring(res.err))
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
-- the view still follows the founder in Build mode (2026-11-14: "in build mode, make the camera still follow the player
-- as they walk around, even though it is displaced downwards abit"): a walk moves it, a drag moves it from there and
-- holds while they stand, and walking on eases it back onto them
do
	local root = a.Character and a.Character:FindFirstChild("HumanoidRootPart")
	if root then
		local x0, z0 = root.Position.X, root.Position.Z
		local px0, py0 = CCa.pan()
		for k = 1, 10 do
			a.Character:PivotTo(E.cf.new(x0 + k * 0.5, 3, z0 + k * 0.3))
			E.run(0.05)
		end
		E.run(0.6)
		local px1, py1 = CCa.pan()
		H.expect(CCa.isFree() and (px1 ~= px0 or py1 ~= py0) and select(1, CCa.buildDrag()) == 0, "build", "Build mode: the view follows the founder as they walk", string.format("(%d, %d) -> (%d, %d)", px0, py0, px1, py1))
		H.inClient(a, CCa.panBy, -120, -60)
		E.run(0.6)
		local dx, dy = CCa.buildDrag()
		local px2, py2 = CCa.pan()
		H.expect((dx ~= 0 or dy ~= 0) and (px2 ~= px1 or py2 ~= py1), "build", "a drag moves the view off the founder", string.format("drag %d %d, pan (%d, %d)", dx, dy, px2, py2))
		E.run(0.8)
		local dx2, dy2 = CCa.buildDrag()
		H.expect(dx2 == dx and dy2 == dy, "build", "and it holds while they stand", string.format("drag %d %d", dx2, dy2))
		for k = 1, 30 do
			a.Character:PivotTo(E.cf.new(x0 + 5 - k * 0.17, 3, z0 + 3 - k * 0.1))
			E.run(0.05)
		end
		E.run(0.6)
		local dx3, dy3 = CCa.buildDrag()
		H.expect(dx3 == 0 and dy3 == 0, "build", "walking on eases the view back onto them", string.format("drag %d %d", dx3, dy3))
		a.Character:PivotTo(E.cf.new(x0, 3, z0))
		E.run(1)
	end
end
-- (the catalog: the Work tab's Farms row, then the Nature tab's Plants row; the tray's tab and row as BuildUI keeps them)
H.clickNamed(a, "Tab_work", { wait = 0.3 })
H.clickNamed(a, "Chip_farm", { wait = 0.3 })
do
	local st = BuildUI.debugState()
	H.expect(st.tab == "work" and st.chip == "farm", "build", "the Work tab on its Farms row", string.format("%s %s", st.tab, st.chip))
	H.expect(H.buttonNamed(a, "Buy_patch") ~= nil and H.buttonNamed(a, "Buy_lumber", true) == nil, "build", "the Farms row offers the veggie patch (and no lumber camp)")
	local orchard = H.buttonNamed(a, "Buy_orchard", true)
	local lock = orchard and orchard:FindFirstChild("Lock", true)
	H.expect(lock ~= nil and lock.Text == "Lv" .. Buildings.byId.orchard.tier, "build", "the orchard shows, locked with its level", lock and lock.Text)
	-- (a card's tooltip: its name, what it is, the level it opens at)
	local shown = H.inClient(a, BuildUI.debugTip, "orchard")
	local tipF = a.PlayerGui:FindFirstChild("BuildTip", true)
	local tName = tipF and tipF:FindFirstChild("TipName", true)
	local tLock = tipF and tipF:FindFirstChild("TipLocked", true)
	H.expect(shown and tName ~= nil and tName.Text == Buildings.byId.orchard.name and tLock ~= nil and string.find(tLock.Text, tostring(Buildings.byId.orchard.tier), 1, true) ~= nil, "build", "a card's tooltip names it and says when it opens", tLock and tLock.Text)
end
H.clickNamed(a, "Tab_nature", { wait = 0.3 })
H.clickNamed(a, "Chip_plants", { wait = 0.3 })
H.expect(H.buttonNamed(a, "Buy_flowers") ~= nil and H.buttonNamed(a, "Buy_patch", true) == nil, "build", "the Nature tab's Plants row offers the flower bed (and no farm)")
-- the Huts tab at the huts' limit: its count says so, the hut's card shows No room and picks nothing; then the huts
-- put up for it go again
H.clickNamed(a, "Tab_nest", { wait = 0.3 })
do
	local count = a.PlayerGui:FindFirstChild("Count", true)
	H.expect(count ~= nil and count.Text == string.format("%d/%d", most, most), "build", "the Huts tab's count: the room of the limit", count and count.Text)
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
	H.expect(Plot.housing(prof.plot.placed) == 0 and #prof.plot.placed == 5, "build", "(the huts cleared away again)", tostring(Plot.housing(prof.plot.placed)))
	local c2 = a.PlayerGui:FindFirstChild("Count", true)
	H.expect(c2 ~= nil and c2.Text == string.format("0/%d", most), "build", "the count follows", c2 and c2.Text)
	H.clickNamed(a, "Tab_nature", { wait = 0.3 })
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
	prof.shells += 500
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
	prof.shells = 1e6
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
	local wood0, tE = prof.shells, E.now()
	local planE = H.inClient(a, BuildUI.debugDraw, { a0, a1 }, "erase")
	E.run(0.4)
	local lifts = 0
	for _, w in planE do
		if w == "lift" then
			lifts += 1
		end
	end
	H.expect(lifts == lays and paths() == p1 + laysB - lays, "build", "Erase takes the line's tiles up", string.format("%d lifted, %d paths", lifts, paths()))
	local back = math.floor(Buildings.byId.dirtpath.shells * Tuning.Refund) * lifts
	local okE, sayE = shellsNear(prof, wood0, back, tE)
	H.expect(back > 0 and okE, "build", "and gives half their price back", sayE)
	-- the server's side: a non-path id, junk cells
	local ok, out = H.raw(a, "plot.paint", { id = "patch", cells = "0,0" })
	H.expect(ok and type(out) == "table" and out.ok == false, "build", "paint refuses a building", tostring(type(out) == "table" and out.err))
	ok, out = H.raw(a, "plot.paint", { id = "dirtpath", cells = "0,0;;1" })
	H.expect(ok and type(out) == "table" and out.err == "bad_payload", "build", "junk cells refused")
	H.clickNamed(a, "Cancel", { optional = true })
end
-- drawing fences ("much, much more building options, like paths and fences"): 2-stud lengths along the grid lines,
-- a line going along x then z between the corners the pointer passes, a box running all the way round; Erase takes
-- them down, half their price back (BuildUI.debugDraw: for a fence the cells are grid corners)
local function countOf(group: string): number
	local n = 0
	for _, q in prof.plot.placed do
		if Plot.group(q.id) == group then
			n += 1
		end
	end
	return n
end
local function hasFence(x: number, z: number, rot: number): boolean
	for _, q in prof.plot.placed do
		if Plot.isFence(q.id) and q.x == x and q.z == z and q.rot == rot then
			return true
		end
	end
	return false
end
local function countWord(): string
	local c = a.PlayerGui:FindFirstChild("Count", true)
	return if c then c.Text else "none"
end
local function planCount(plan: { string }, what: string): number
	local n = 0
	for _, w in plan do
		if w == what then
			n += 1
		end
	end
	return n
end
-- the north-west corner of a square of the grid `side` studs across where every length round it fits (corners on the
-- even studs, grass on a side, no piece crossing)
local function fenceSquare(side: number): (number?, number?)
	local r = Street.plot(prof.tier)
	for z = r.z0 - r.z0 % 2, r.z1, 2 do
		for x = r.x0 - r.x0 % 2, r.x1, 2 do
			local ok = true
			for k = 0, side - 2, 2 do
				ok = ok
					and Plot.fits(prof.tier, prof.plot.placed, "ropefence", x + k, z, 0)
					and Plot.fits(prof.tier, prof.plot.placed, "ropefence", x + k, z + side, 0)
					and Plot.fits(prof.tier, prof.plot.placed, "ropefence", x, z + k, 90)
					and Plot.fits(prof.tier, prof.plot.placed, "ropefence", x + side, z + k, 90)
			end
			if ok then
				return x, z
			end
		end
	end
	return nil, nil
end
do
	H.clickNamed(a, "Tab_fence", { wait = 0.3 })
	H.expect(countWord() == string.format("%d/%d", countOf("fence"), Plot.fenceLimit(prof.tier)), "build", "the Fences tab counts the lengths against their own limit", countWord())
	local crystal = H.buttonNamed(a, "Buy_crystalfence", true)
	local lock = crystal and crystal:FindFirstChild("Lock", true)
	H.expect(H.buttonNamed(a, "Buy_picket") ~= nil and lock ~= nil and lock.Text == "Lv" .. Buildings.byId.crystalfence.tier, "build", "the fences on offer, a bigger island's locked", lock and lock.Text)
	H.clickNamed(a, "Buy_ropefence", { wait = 0.3 })
	H.expect(H.buttonNamed(a, "DrawLine") ~= nil and H.buttonNamed(a, "DrawBox") ~= nil and H.buttonNamed(a, "DrawErase") ~= nil, "build", "a fence picked: Line, Box and Erase")
	local fx, fz = fenceSquare(4)
	if H.expect(fx ~= nil, "build", "(a free square of the grid for a fence)") then
		local x, z = fx :: number, fz :: number
		local f0 = countOf("fence")
		local plan = H.inClient(a, BuildUI.debugDraw, { { x, z }, { x + 4, z + 4 } }, "line")
		E.run(0.4)
		local along = hasFence(x, z, 0) and hasFence(x + 2, z, 0) and hasFence(x + 4, z, 90) and hasFence(x + 4, z + 2, 90)
		H.expect(#plan == 4 and planCount(plan, "lay") == 4 and countOf("fence") == f0 + 4 and along, "build", "a fence line goes along x, then down z to the corner: four lengths", string.format("%d planned, %d -> %d", #plan, f0, countOf("fence")))
		-- a box elsewhere: every length round it
		local bx, bz = fenceSquare(4)
		if H.expect(bx ~= nil, "build", "(a second square for a fence box)") then
			local x2, z2 = bx :: number, bz :: number
			local f1 = countOf("fence")
			local planB = H.inClient(a, BuildUI.debugDraw, { { x2, z2 }, { x2 + 4, z2 + 4 } }, "box")
			E.run(0.4)
			local round = true
			for k = 0, 2, 2 do
				round = round and hasFence(x2 + k, z2, 0) and hasFence(x2 + k, z2 + 4, 0) and hasFence(x2, z2 + k, 90) and hasFence(x2 + 4, z2 + k, 90)
			end
			H.expect(#planB == 8 and countOf("fence") == f1 + 8 and round, "build", "a fence box runs all the way round: eight lengths", string.format("%d planned, %d -> %d", #planB, f1, countOf("fence")))
		end
		-- the line taken down again
		local wood0, tE = prof.shells, E.now()
		local planE = H.inClient(a, BuildUI.debugDraw, { { x, z }, { x + 4, z + 4 } }, "erase")
		E.run(0.4)
		local back = math.floor(Buildings.byId.ropefence.shells * Tuning.Refund) * 4
		local okE, sayE = shellsNear(prof, wood0, back, tE)
		H.expect(planCount(planE, "lift") == 4 and not hasFence(x, z, 0) and not hasFence(x + 4, z + 2, 90) and okE, "build", "Erase takes the fence line down, half its price back", string.format("%d lifted, %s", planCount(planE, "lift"), sayE))
	end
	H.clickNamed(a, "Cancel", { optional = true })
end
-- digging water (rivers and ponds: "add the ability to add water to make rivers"): drawn like paths, counted with
-- them; a path laid on in the same row; Erase takes up only the kind picked
local river: { { number } } = {}
do
	H.clickNamed(a, "Tab_water", { wait = 0.3 })
	H.clickNamed(a, "Chip_tiles", { wait = 0.3 })
	H.expect(H.buttonNamed(a, "Buy_stream") ~= nil and H.buttonNamed(a, "Buy_plankbridge", true) == nil and H.buttonNamed(a, "Buy_lilypads", true) == nil, "build", "the Water tab's water row: the tiles only")
	H.expect(countWord() == string.format("%d/%d", countOf("tile"), Plot.pathLimit(prof.tier)), "build", "the Water tab counts its tiles with the paths, against their limit", countWord())
	-- six free cells in a row, west to east: three for water, three for a path after them
	local row = nil
	local r = Street.plot(prof.tier)
	for z = r.z0 - r.z0 % 2, r.z1, 2 do
		for x = r.x0 - r.x0 % 2, r.x1, 2 do
			if row == nil then
				local ok = true
				for k = 0, 5 do
					ok = ok and Plot.fits(prof.tier, prof.plot.placed, "stream", x + 2 * k, z, 0)
				end
				if ok then
					row = { x, z }
				end
			end
		end
	end
	if H.expect(row ~= nil, "build", "(six free cells in a row)") then
		local x, z = row[1], row[2]
		H.clickNamed(a, "Buy_stream", { wait = 0.3 })
		local t0, w0 = countOf("tile"), 0
		local plan = H.inClient(a, BuildUI.debugDraw, { { x, z }, { x + 4, z } }, "line")
		E.run(0.4)
		for _, q in prof.plot.placed do
			if Plot.isWater(q.id) then
				w0 += 1
			end
		end
		H.expect(planCount(plan, "lay") == 3 and countOf("tile") == t0 + 3 and w0 == 3, "build", "a river dug: three water tiles", string.format("%d planned, %d water", planCount(plan, "lay"), w0))
		H.clickNamed(a, "Cancel", { optional = true })
		H.clickNamed(a, "Tab_path", { wait = 0.3 })
		H.clickNamed(a, "Buy_dirtpath", { wait = 0.3 })
		local planP = H.inClient(a, BuildUI.debugDraw, { { x + 6, z }, { x + 10, z } }, "line")
		E.run(0.4)
		H.expect(planCount(planP, "lay") == 3 and countOf("tile") == t0 + 6, "build", "and a path on from it in the same row", tostring(countOf("tile")))
		-- with the path picked, Erase down the whole row takes up the path only
		local planE = H.inClient(a, BuildUI.debugDraw, { { x, z }, { x + 10, z } }, "erase")
		E.run(0.4)
		local water = 0
		for _, q in prof.plot.placed do
			if Plot.isWater(q.id) then
				water += 1
				table.insert(river, { q.x, q.z })
			end
		end
		H.expect(planCount(planE, "lift") == 3 and planCount(planE, "no") == 3 and countOf("tile") == t0 + 3 and water == 3, "build", "Erase with a path picked takes up the path, the water stays", string.format("%d lifted, %d water", planCount(planE, "lift"), water))
		H.clickNamed(a, "Cancel", { optional = true })
	end
end
H.clickNamed(a, "BuildDone")
E.run(0.4)
H.expect(not BuildUI.isOpen() and not CCa.isFree(), "build", "Done: closed, the view follows again")
H.expect(ghostFootprint() == nil, "build", "no ghost left")

------------------------------------------------------------------ 6. fences and water on both islands
E.phase = "fences-water"
-- A water tile's neighbour mask as PlotService puts it in its model's name (1, and north 1, east 2, south 4, west 8
-- for each side with water next to it), worked out here from the pieces.
local function tileKey(placed, q): string
	local wet = {}
	for _, o in placed do
		if Plot.isWater(o.id) then
			wet[o.x .. "," .. o.z] = true
		end
	end
	local m = 1
	for _, s in { { 0, -2, 1 }, { 2, 0, 2 }, { 0, 2, 4 }, { -2, 0, 8 } } do
		if wet[(q.x + s[1]) .. "," .. (q.z + s[2])] then
			m += s[3]
		end
	end
	return string.format("%d:%s:%d:%d:%d:%d", q.uid, q.id, q.x, q.z, q.rot, m)
end
do
	local pb = H.profile(b)
	pb.shells = math.max(pb.shells, 1e5)
	H.push(b, 0.3)
	local tierB = pb.tier
	-- the first even cell (x, z) from the north-west where `ok` agrees
	local function firstCell(tier: number, ok: (number, number) -> boolean): (number?, number?)
		local r = Street.plot(tier)
		for z = r.z0 - r.z0 % 2, r.z1, 2 do
			for x = r.x0 - r.x0 % 2, r.x1, 2 do
				if ok(x, z) then
					return x, z
				end
			end
		end
		return nil, nil
	end
	local function wetAt(placed, x: number, z: number): boolean
		for _, q in placed do
			if Plot.isWater(q.id) and q.x == x and q.z == z then
				return true
			end
		end
		return false
	end
	-- Bo digs a river four tiles long and fences its north bank with pickets (by requests; Ava drew hers in Build mode)
	local rx, rz = firstCell(tierB, function(x, z)
		local ok = true
		for k = 0, 4 do
			ok = ok and Plot.fits(tierB, pb.plot.placed, "stream", x + 2 * k, z, 0) and Plot.fits(tierB, pb.plot.placed, "picket", x + 2 * k, z, 0)
		end
		return ok
	end)
	if H.expect(rx ~= nil, "fences", "(room for a river on Bo's island)") then
		local cells, edges = {}, {}
		for k = 0, 3 do
			table.insert(cells, { rx + 2 * k, rz })
			table.insert(edges, { rx + 2 * k, rz, 0 })
		end
		local r1 = H.req(b, "plot.paint", { id = "stream", cells = Plot.cellString(cells) })
		local r2 = H.req(b, "plot.fence", { id = "picket", edges = Plot.edgeString(edges) })
		H.expect(r1.ok and r1.data.placed == 4 and r2.ok and r2.data.placed == 4, "fences", "Bo digs a river four tiles long and fences its bank", string.format("%s %s", tostring(r1.err), tostring(r2.err)))
	end
	E.run(0.5)
	-- both islands' fences and water stand in their Static.Decor, a model a piece named by it, a water tile's with its
	-- neighbour mask in the level's place and its surface animated (PixelWater); the fake engine shares one DataModel
	-- between the clients, so what the server builds there is what both clients' pixel filters draw
	for _, pair in { { 1, a }, { 2, b } } do
		local i, owner = pair[1], pair[2]
		local placed = H.profile(owner).plot.placed
		local decor = decorOf(i)
		local fences, tiles, masks, missing = 0, 0, {}, {}
		for _, q in placed do
			local name = nil
			if Plot.isFence(q.id) then
				fences += 1
				name = keyOf(q)
			elseif Plot.isWater(q.id) then
				tiles += 1
				name = tileKey(placed, q)
				table.insert(masks, string.match(name, "(%d+)$"))
			end
			if name then
				local m = decor and decor:FindFirstChild(name)
				local parts, wet = 0, false
				for _, d in if m then m:GetDescendants() else {} do
					if d:IsA("BasePart") then
						parts += 1
						wet = wet or d:GetAttribute("PixelWater") ~= nil
					end
				end
				if m == nil or parts == 0 or (Plot.isWater(q.id) and not wet) then
					table.insert(missing, name)
				end
			end
		end
		local want = if i == 1 then "3,11,9" else "3,11,11,9"
		H.expect(fences >= 4 and #missing == 0 and decor ~= nil and #decor:GetChildren() == #placed, "fences", string.format("island %d's fence lengths stand for both clients, a model each", i), string.format("%d fences, missing %s", fences, table.concat(missing, " ")))
		H.expect(tiles >= 3 and table.concat(masks, ",") == want, "fences", string.format("island %d's river stands for both clients, each tile's model named with its neighbours (%s)", i, want), table.concat(masks, ","))
	end
	-- a lone tile on Bo's island, then one dug east of it: the first one's model is built again with its new mask (and
	-- again when the neighbour is taken up)
	local lx, lz = firstCell(tierB, function(x, z)
		if not (Plot.fits(tierB, pb.plot.placed, "stream", x, z, 0) and Plot.fits(tierB, pb.plot.placed, "stream", x + 2, z, 0)) then
			return false
		end
		for _, c in { { 0, -2 }, { 0, 2 }, { -2, 0 }, { 2, -2 }, { 2, 2 }, { 4, 0 } } do
			if wetAt(pb.plot.placed, x + c[1], z + c[2]) then
				return false
			end
		end
		return true
	end)
	if H.expect(lx ~= nil, "fences", "(room for two tiles apart from the river)") then
		local decorB = decorOf(2)
		local function tileAt(x: number, z: number)
			for _, q in pb.plot.placed do
				if Plot.isWater(q.id) and q.x == x and q.z == z then
					return q
				end
			end
			return nil
		end
		H.req(b, "plot.paint", { id = "stream", cells = string.format("%d,%d", lx, lz) })
		E.run(0.3)
		local t = tileAt(lx, lz)
		local m1 = t and decorB:FindFirstChild(tileKey(pb.plot.placed, t))
		H.expect(m1 ~= nil and string.sub(m1.Name, -2) == ":1", "fences", "a lone tile's model: no water round it (mask 1)", m1 and m1.Name)
		H.req(b, "plot.paint", { id = "stream", cells = string.format("%d,%d", lx + 2, lz) })
		E.run(0.3)
		local e = tileAt(lx + 2, lz)
		local m2 = t and decorB:FindFirstChild(tileKey(pb.plot.placed, t))
		local me = e and decorB:FindFirstChild(tileKey(pb.plot.placed, e))
		H.expect(m1 ~= nil and m1.Parent == nil and m2 ~= nil and m2 ~= m1 and string.sub(m2.Name, -2) == ":3" and me ~= nil and string.sub(me.Name, -2) == ":9", "fences", "a tile dug next to it: its model built again with water to the east (3), the new one's to the west (9)", string.format("%s, %s", tostring(m2 and m2.Name), tostring(me and me.Name)))
		H.req(b, "plot.unpaint", { cells = string.format("%d,%d", lx + 2, lz), kind = "water" })
		E.run(0.3)
		local m3 = t and decorB:FindFirstChild(tileKey(pb.plot.placed, t))
		H.expect(m2 ~= nil and m2.Parent == nil and m3 ~= nil and string.sub(m3.Name, -2) == ":1" and me ~= nil and me.Parent == nil, "fences", "and back to a lone tile when the neighbour is taken up", m3 and m3.Name)
	end
	-- floating: lily pads only go on water (not on the grass), and taking the water up takes them with it, half the
	-- price of each back
	if rx then
		-- (a patch of grass a flower bed of the same size fits on)
		local gx, gz = spot("flowers", 0, pb.plot.placed, tierB)
		local rg = H.req(b, "plot.place", { id = "lilypads", x = gx or 0, z = gz or 0, rot = 0 })
		H.expect(gx ~= nil and not rg.ok and rg.err == "blocked", "fences", "lily pads on the grass: refused (blocked)", string.format("%s %s", tostring(gx), tostring(rg.err)))
		local n0 = #pb.plot.placed
		local rl = H.req(b, "plot.place", { id = "lilypads", x = rx, z = rz, rot = 0 })
		H.expect(rl.ok and #pb.plot.placed == n0 + 1, "fences", "lily pads on the river: placed", tostring(rl.err))
		local wood0, tU = pb.shells, E.now()
		local ru = H.req(b, "plot.unpaint", { cells = string.format("%d,%d", rx, rz), kind = "water" })
		local pads = 0
		for _, q in pb.plot.placed do
			if q.id == "lilypads" then
				pads += 1
			end
		end
		local due = math.floor(Buildings.byId.stream.shells * Tuning.Refund) + math.floor(Buildings.byId.lilypads.shells * Tuning.Refund)
		H.expect(ru.ok and ru.data.removed == 1 and ru.data.floated == 1 and pads == 0 and #pb.plot.placed == n0 - 1, "fences", "the water under them taken up: the pads go with it", string.format("%s, %d pads left", tostring(ru.err), pads))
		local okU, sayU = shellsNear(pb, wood0, due, tU)
		H.expect(okU, "fences", "half the tile's and the pads' price back", sayU)
		-- (the river whole again, for the walk below and the limits)
		H.req(b, "plot.paint", { id = "stream", cells = string.format("%d,%d", rx, rz) })
	end
	-- the eraser's kind: water's eraser leaves a path where it is, a path's leaves water
	local pathQ, waterQ = nil, nil
	for _, q in prof.plot.placed do
		if Plot.isPath(q.id) then
			pathQ = pathQ or q
		elseif Plot.isWater(q.id) then
			waterQ = waterQ or q
		end
	end
	if H.expect(pathQ ~= nil and waterQ ~= nil, "fences", "(Ava has a path and water)") then
		local n0 = #prof.plot.placed
		local e1 = H.req(a, "plot.unpaint", { cells = string.format("%d,%d", pathQ.x, pathQ.z), kind = "water" })
		local e2 = H.req(a, "plot.unpaint", { cells = string.format("%d,%d", waterQ.x, waterQ.z), kind = "path" })
		H.expect(e1.err == "not_found" and e2.err == "not_found" and #prof.plot.placed == n0, "fences", "the water eraser leaves a path, the path eraser leaves water (not_found)", string.format("%s %s", tostring(e1.err), tostring(e2.err)))
	end
	-- a fence never runs through a building but may run along its side: a veggie patch put down on the even studs,
	-- lengths through its middle refused (blocked, nothing paid), along its north and west sides put up
	local px, pz = firstCell(prof.tier, function(x, z)
		local placed = prof.plot.placed
		return Plot.fits(prof.tier, placed, "patch", x, z, 0)
			and Plot.fits(prof.tier, placed, "picket", x, z, 0)
			and Plot.fits(prof.tier, placed, "picket", x, z, 90)
			and Plot.fits(prof.tier, placed, "picket", x, z + 2, 0)
			and Plot.fits(prof.tier, placed, "picket", x + 2, z, 90)
	end)
	if H.expect(px ~= nil, "fences", "(room for a patch on the even studs)") then
		local rp = H.req(a, "plot.place", { id = "patch", x = px, z = pz, rot = 0 })
		local f0, wood0 = countOf("fence"), prof.shells
		local t1 = H.req(a, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", px, pz + 2) })
		local t2 = H.req(a, "plot.fence", { id = "picket", edges = string.format("%d,%d,90", px + 2, pz) })
		H.expect(rp.ok and t1.err == "blocked" and t2.err == "blocked" and countOf("fence") == f0 and prof.shells >= wood0 - 1e-6, "fences", "a fence through a building: refused (blocked), nothing paid", string.format("%s %s %s", tostring(rp.err), tostring(t1.err), tostring(t2.err)))
		local t3 = H.req(a, "plot.fence", { id = "picket", edges = string.format("%d,%d,0;%d,%d,90", px, pz, px, pz) })
		H.expect(t3.ok and t3.data.placed == 2 and hasFence(px, pz, 0) and hasFence(px, pz, 90), "fences", "along its north and west sides: put up", tostring(t3.err))
	end
	-- a building never stands across a fence: a lone fence length, an oak where it would fit but for the fence refused
	-- (and moved there refused), right up against it put down
	local gx, gz = firstCell(prof.tier, function(x, z)
		local placed = prof.plot.placed
		return Plot.fits(prof.tier, placed, "picket", x, z, 0) and Plot.fits(prof.tier, placed, "oak", x, z - 1, 0) and Plot.fits(prof.tier, placed, "oak", x, z - 3, 0)
	end)
	if H.expect(gx ~= nil, "fences", "(room for a fence and an oak)") then
		local rf = H.req(a, "plot.fence", { id = "picket", edges = string.format("%d,%d,0", gx, gz) })
		local n0, wood0 = #prof.plot.placed, prof.shells
		local o1 = H.req(a, "plot.place", { id = "oak", x = gx, z = gz - 1, rot = 0 })
		H.expect(rf.ok and o1.err == "blocked" and #prof.plot.placed == n0 and prof.shells >= wood0 - 1e-6, "fences", "a building across a fence: refused (blocked), nothing paid", string.format("%s %s", tostring(rf.err), tostring(o1.err)))
		local o2 = H.req(a, "plot.place", { id = "oak", x = gx, z = gz - 3, rot = 0 })
		H.expect(o2.ok, "fences", "right up against the fence: put down", tostring(o2.err))
		local o3 = H.req(a, "plot.move", { i = #prof.plot.placed, x = gx, z = gz - 1, rot = 0 })
		H.expect(o2.ok and o3.err == "blocked", "fences", "and moved across it: refused", tostring(o3.err))
	end
	E.run(0.3)
	-- the founder wades through Ava's river (GAME_DESIGN 4.3): the ground under their feet is the tile's water, so
	-- AvatarView's floor reads "water" and the wading steps are heard (Audio "step_water"); with E.raycastParts the
	-- ground ray hits every part, as in Roblox
	if H.expect(#river == 3, "wade", "(Ava's river of three tiles)", tostring(#river)) then
		local AudioA = H.cmod(a, "Controllers.Audio")
		local wx, wz = math.huge, river[1][2]
		for _, c in river do
			wx = math.min(wx, c[1])
		end
		local wet0 = H.inClient(a, AudioA.playCount, "step_water")
		E.raycastParts = true
		for k = 0, 19 do
			local along = 0.5 + (if k < 10 then k else 19 - k) * 0.55
			a.Character:PivotTo(E.cf.new(ox1 + wx + along, 3, oz1 + wz + 1))
			E.run(0.1)
		end
		local wet1 = H.inClient(a, AudioA.playCount, "step_water")
		-- (then the ground ray down onto the middle tile, the founder off it)
		a.Character:PivotTo(E.cf.new(ox1 + sx, 3, oz1 + sz))
		E.run(0.2)
		local hit = E.workspace:Raycast(E.v3(ox1 + wx + 3, Street.LAWN_Y + 2, oz1 + wz + 1), E.v3(0, -10, 0))
		E.raycastParts = nil
		H.expect(wet1 > wet0, "wade", "the founder wades through the river: AvatarView's floor is water (its steps heard)", string.format("%d -> %d", wet0, wet1))
		local part = hit and hit.Instance
		local inTile = part ~= nil and part:IsDescendantOf(decorOf(1)) and string.find(part.Parent.Name, ":stream:", 1, true) ~= nil
		H.expect(inTile and part:GetAttribute("PixelWater") ~= nil and hit.Position.Y > Street.LAWN_Y - 0.3, "wade", "the ground ray hits the tile's water, over the lawn", part and string.format("%s in %s at %.2f", part.Name, part.Parent.Name, hit.Position.Y) or "nothing")
	end
	-- the founder walks through a building (they don't collide): the chibi stays on the lawn, never up on its roof
	-- (the bug report of 2026-11-14: "there is a bug where the player snaps above buildings while walking over them")
	do
		local AVa = H.cmod(a, "Controllers.AvatarView")
		local best, bx, bz = nil, 0, 0
		for _, m in decorOf(1):GetChildren() do
			if m:IsA("Model") and string.find(m.Name, ":tree", 1, true) == nil then
				local top, n, mx, mz = -math.huge, 0, 0, 0
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d.CanCollide == false then
						top = math.max(top, d.Position.Y + d.Size.Y / 2)
						n += 1
						mx += d.Position.X
						mz += d.Position.Z
					end
				end
				if n > 0 and top > Street.LAWN_Y + 2 and (best == nil or top > best) then
					best, bx, bz = top, mx / n, mz / n
				end
			end
		end
		if H.expect(best ~= nil, "walk-through", "(a building on Ava's island)") then
			E.raycastParts = true
			a.Character:PivotTo(E.cf.new(ox1 + sx, 3, oz1 + sz))
			E.run(0.3)
			local open = H.inClient(a, AVa.founderPos)
			a.Character:PivotTo(E.cf.new(bx, 3, bz))
			E.run(0.3)
			local inside = H.inClient(a, AVa.founderPos)
			E.raycastParts = nil
			local ok = open ~= nil and inside ~= nil and math.abs(inside.Y - open.Y) < 0.3
			H.expect(ok, "walk-through", "walking through a building the founder stays on the lawn, not on its roof", string.format("open %.2f, inside %.2f, roof %.2f", open and open.Y or -1, inside and inside.Y or -1, best :: number))
		end
	end
	H.checkProfile(a, "fences-water")
	H.checkMirror(a, "fences-water")
	H.checkProfile(b, "fences-water")
	H.checkMirror(b, "fences-water")
end

------------------------------------------------------------------ 7. each count to its own limit
-- (GAME_DESIGN 4: paths and water count together against Tuning.PathPieces, fence lengths against
-- Tuning.FencePieces, the rest against the piece limit, Tuning.PlotPieces; the tree in none) on Bo's island, grown to
-- tier 2 for the room: each count fills to its limit and refuses one more (full, nothing paid) while the others still
-- take theirs
E.phase = "limits"
do
	local pb = H.profile(b)
	pb.shells = 1e6 + 1e5
	H.push(b, 0.3)
	local rx = H.req(b, "island.expand", {})
	E.run(1.5)
	H.expect(rx.ok and pb.tier == 2, "limits", "Bo's island grown to tier 2", tostring(rx.err))
	local T = pb.tier
	local function count(g: string): number
		local n = 0
		for _, q in pb.plot.placed do
			if Plot.group(q.id) == g then
				n += 1
			end
		end
		return n
	end
	-- free places now: tile cells (even studs), fence edges (x, z, rot), single cells (a torch)
	local function freeOf(id: string, n: number, rots: { number }): { { number } }
		local out = {}
		local r = Street.plot(T)
		local step = if id == "torch" then 1 else 2
		for z = r.z0 - r.z0 % 2, r.z1, step do
			for x = r.x0 - r.x0 % 2, r.x1, step do
				for _, rot in rots do
					if #out < n and Plot.fits(T, pb.plot.placed, id, x, z, rot) then
						table.insert(out, if id == "picket" then { x, z, rot } else { x, z })
					end
				end
			end
		end
		return out
	end
	local function batches(action: string, ids: { string }, list: { { number } })
		local k, look = 1, 0
		while k <= #list do
			local part = table.move(list, k, math.min(#list, k + Plot.PAINT_MAX - 1), 1, {})
			local id = ids[look % #ids + 1]
			local r = if action == "plot.fence" then H.req(b, action, { id = id, edges = Plot.edgeString(part) }) else H.req(b, action, { id = id, cells = Plot.cellString(part) })
			if not H.expect(r.ok, "limits", "(a batch of " .. id .. ")", tostring(r.err)) then
				break
			end
			E.run(0.1)
			k += Plot.PAINT_MAX
			look += 1
		end
	end
	local function full(label: string, action: string, payload)
		local n, wood = #pb.plot.placed, pb.shells
		local r = H.req(b, action, payload)
		E.run(0.1)
		H.expect(not r.ok and r.err == "full" and #pb.plot.placed == n and pb.shells >= wood - 1e-6, "limits", label, tostring(r.err))
	end
	local function goes(label: string, action: string, payload)
		local n = #pb.plot.placed
		local r = H.req(b, action, payload)
		E.run(0.1)
		H.expect(r.ok and #pb.plot.placed == n + 1, "limits", label, tostring(r.err))
	end
	local function one(c: { number }): string
		return if #c == 3 then Plot.edgeString({ c }) else Plot.cellString({ c })
	end
	-- the tiles: paths and water by turns up to the tile limit
	local tileMost = Plot.pathLimit(T)
	local tiles = freeOf("stream", tileMost - count("tile"), { 0 })
	if H.expect(#tiles == tileMost - count("tile"), "limits", "(room for the tile limit)", string.format("%d free of %d", #tiles, tileMost - count("tile"))) then
		batches("plot.paint", { "dirtpath", "stream" }, tiles)
		local paths, water = 0, 0
		for _, q in pb.plot.placed do
			paths += if Plot.isPath(q.id) then 1 else 0
			water += if Plot.isWater(q.id) then 1 else 0
		end
		H.expect(count("tile") == tileMost and paths > 40 and water > 40 and paths + water == tileMost, "limits", string.format("paths and water fill the tile limit together (%d)", tileMost), string.format("%d paths, %d water", paths, water))
		local spare = freeOf("stream", 1, { 0 })[1]
		full("a path past the tile limit: refused (full)", "plot.paint", { id = "dirtpath", cells = one(spare) })
		full("water past it too: they count together", "plot.paint", { id = "stream", cells = one(spare) })
		goes("at the tile limit a fence still goes up (its own count)", "plot.fence", { id = "picket", edges = one(freeOf("picket", 1, { 0, 90 })[1]) })
		goes("and a piece still goes down", "plot.place", { id = "torch", x = freeOf("torch", 1, { 0 })[1][1], z = freeOf("torch", 1, { 0 })[1][2], rot = 0 })
	end
	-- the fence lengths up to theirs
	local fenceMost = Plot.fenceLimit(T)
	local edges = freeOf("picket", fenceMost - count("fence"), { 0, 90 })
	if H.expect(#edges == fenceMost - count("fence"), "limits", "(room for the fence limit)", tostring(#edges)) then
		batches("plot.fence", { "picket", "splitrail" }, edges)
		H.expect(count("fence") == fenceMost, "limits", string.format("fence lengths fill their limit (%d)", fenceMost), tostring(count("fence")))
		full("a fence past the fence limit: refused (full)", "plot.fence", { id = "picket", edges = one(freeOf("picket", 1, { 0, 90 })[1]) })
		local c = freeOf("torch", 1, { 0 })[1]
		goes("at the fence limit a piece still goes down", "plot.place", { id = "torch", x = c[1], z = c[2], rot = 0 })
	end
	-- the pieces up to theirs (the tree apart)
	local pieceMost = Plot.limit(T)
	local cells = freeOf("torch", pieceMost - count("piece") + 1, { 0 })
	if H.expect(#cells == pieceMost - count("piece") + 1, "limits", "(room for the piece limit)", tostring(#cells)) then
		local k = 1
		while count("piece") < pieceMost and k < #cells do
			H.req(b, "plot.place", { id = "torch", x = cells[k][1], z = cells[k][2], rot = 0 })
			E.run(0.1)
			k += 1
		end
		H.expect(count("piece") == pieceMost and count("fixed") == 1, "limits", string.format("pieces fill their limit (%d), the tree not counted", pieceMost), tostring(count("piece")))
		full("a piece past the piece limit: refused (full)", "plot.place", { id = "torch", x = cells[#cells][1], z = cells[#cells][2], rot = 0 })
	end
	-- every count at its limit: a tile taken up makes room for another (another look), a fence length the same
	-- (a path with nothing standing on it: decor and fun pieces may stand on paths, and the torches filled spots there)
	local function bare(t: any): boolean
		local r = Plot.rect(t.id, t.x, t.z, t.rot)
		for _, o in pb.plot.placed do
			if not Plot.isDrawn(o.id) then
				local orr = Plot.rect(o.id, o.x, o.z, o.rot)
				if orr.x0 < r.x1 and r.x0 < orr.x1 and orr.z0 < r.z1 and r.z0 < orr.z1 then
					return false
				end
			end
		end
		return true
	end
	local pathQ, fenceQ = nil, nil
	for _, q in pb.plot.placed do
		if Plot.isPath(q.id) then
			pathQ = pathQ or (if bare(q) then q else nil)
		elseif Plot.isFence(q.id) and q.id == "picket" then
			fenceQ = fenceQ or q
		end
	end
	if H.expect(pathQ ~= nil and fenceQ ~= nil, "limits", "(a path and a fence to take up)") then
		local cell, edge = { pathQ.x, pathQ.z }, { fenceQ.x, fenceQ.z, fenceQ.rot }
		local u1 = H.req(b, "plot.unpaint", { cells = one(cell), kind = "path" })
		E.run(0.1)
		goes("at the piece limit a tile taken up makes room for water there", "plot.paint", { id = "stream", cells = one(cell) })
		local u2 = H.req(b, "plot.unfence", { edges = one(edge) })
		E.run(0.1)
		goes("and a fence taken down for another look of fence", "plot.fence", { id = "ropefence", edges = one(edge) })
		H.expect(u1.ok and u2.ok and count("tile") == tileMost and count("fence") == fenceMost and count("piece") == pieceMost, "limits", "(every count at its limit again)", string.format("%s %s", tostring(u1.err), tostring(u2.err)))
	end
	-- the tray's count on each tab: Paths and Water the same tiles, Fences its lengths, Decor the pieces
	local BuildB = H.cmod(b, "UI.BuildUI")
	H.inClient(b, BuildB.open)
	E.run(0.5)
	local words = {}
	for _, t in { "path", "water", "fence", "decor" } do
		H.clickNamed(b, "Tab_" .. t, { wait = 0.3 })
		local c = b.PlayerGui:FindFirstChild("Count", true)
		table.insert(words, if c then c.Text else "none")
	end
	local want = string.format("%d/%d %d/%d %d/%d %d/%d", tileMost, tileMost, tileMost, tileMost, fenceMost, fenceMost, pieceMost, pieceMost)
	H.expect(table.concat(words, " ") == want, "limits", "Build mode's count on each tab: Paths and Water the tiles together, Fences the lengths, Decor the pieces", table.concat(words, " "))
	H.inClient(b, BuildB.close)
	E.run(0.3)
	H.checkProfile(b, "limits")
	settled(b)
	H.checkMirror(b, "limits")
end

------------------------------------------------------------------ 8. malicious plot payloads
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
local storesBefore = { shells = prof.shells }
refused("a fractional x", "bad_payload", "plot.place", { id = "torch", x = 1.5, z = 20, rot = 0 })
refused("x out of range", "bad_payload", "plot.place", { id = "torch", x = 100, z = 20, rot = 0 })
refused("a 45 degree turn", "bad_payload", "plot.place", { id = "torch", x = 20, z = 20, rot = 45 })
refused("NaN", "bad_payload", "plot.place", { id = "torch", x = 0 / 0, z = 20, rot = 0 })
refused("index 0", "bad_payload", "plot.move", { i = 0, x = 20, z = 20, rot = 0 })
refused("index 999", "bad_payload", "plot.store", { i = 999 })
refused("a piece not there", "bad_payload", "plot.store", { i = #prof.plot.placed + 1 })
refused("an index past any island's pieces", "bad_payload", "plot.store", { i = 8193 })
refused("z past the far north", "bad_payload", "plot.place", { id = "torch", x = 0, z = -241, rot = 0 })
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
-- fences (plot.fence / plot.unfence: edges "x,z,r", r 0 or 90, at most Plot.PAINT_MAX) and the eraser's kind
do
	local ex, ez = fenceSquare(2)
	local free = string.format("%d,%d,0", ex or 0, ez or 0)
	local many = {}
	for k = 1, Plot.PAINT_MAX + 1 do
		table.insert(many, string.format("%d,%d,0", 2 * k - 40, 0))
	end
	refused("a fence turned 45 degrees", "bad_payload", "plot.fence", { id = "picket", edges = "0,-4,45" })
	refused("a fence turned 180", "bad_payload", "plot.fence", { id = "picket", edges = "0,-4,180" })
	refused("a fence edge out of range", "bad_payload", "plot.fence", { id = "picket", edges = "0,-242,0" })
	refused("a fractional fence edge", "bad_payload", "plot.fence", { id = "picket", edges = "0.5,-4,0" })
	refused("an edge with no way", "bad_payload", "plot.fence", { id = "picket", edges = "0,-4" })
	refused("junk edges", "bad_payload", "plot.fence", { id = "picket", edges = "0,-4,0;;2,-4,0" })
	refused("more lengths than one request takes", "bad_payload", "plot.fence", { id = "picket", edges = table.concat(many, ";") })
	refused("edges as a table", "bad_payload", "plot.fence", { id = "picket", edges = { "0,-4,0" } })
	refused("a fence with a price", "bad_payload", "plot.fence", { id = "picket", edges = free, price = 0 })
	refused("a fence with no id", "bad_payload", "plot.fence", { edges = free })
	refused("a building drawn as a fence", "bad_payload", "plot.fence", { id = "patch", edges = free })
	refused("a path drawn as a fence", "bad_payload", "plot.fence", { id = "dirtpath", edges = free })
	refused("an unknown fence", "bad_payload", "plot.fence", { id = "castlewall", edges = free })
	refused("a fence painted as tiles", "bad_payload", "plot.paint", { id = "picket", cells = "0,0" })
	refused("a bigger island's fence", "locked", "plot.fence", { id = "crystalfence", edges = free })
	refused("a fence off the grid", "blocked", "plot.fence", { id = "picket", edges = string.format("%d,%d,0", (ex or 0) + 1, ez or 0) })
	refused("a fence off the island", "blocked", "plot.fence", { id = "picket", edges = "60,0,0" })
	refused("a fence across the plaza", "blocked", "plot.fence", { id = "picket", edges = "-2,6,0" })
	refused("a fence down the middle of the path", "blocked", "plot.fence", { id = "picket", edges = "0,12,90" })
	refused("a fence taken down with an id", "bad_payload", "plot.unfence", { id = "picket", edges = free })
	refused("a fence taken down at 45 degrees", "bad_payload", "plot.unfence", { edges = "0,-4,45" })
	refused("no edges to take down", "bad_payload", "plot.unfence", {})
	refused("no fence there to take down", "not_found", "plot.unfence", { edges = free })
	refused("an eraser of lava", "bad_payload", "plot.unpaint", { cells = "0,0", kind = "lava" })
	refused("an eraser's kind as a number", "bad_payload", "plot.unpaint", { cells = "0,0", kind = 1 })
end
local diff = H.diff(before, snap())
H.expect(diff == nil, "malicious", "the refusals changed nothing", tostring(diff))
-- (the stores: nothing paid; the island only made a little meanwhile)
H.expect(prof.shells >= storesBefore.shells - 1e-6 and prof.wood == nil, "malicious", "and took nothing from the shells", string.format("%s -> %s", storesBefore.shells, prof.shells))
E.run(0.3)

------------------------------------------------------------------ 9. a player leaves
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

------------------------------------------------------------------ 10. a full sea
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
local extras = {}
for k = 1, Street.MAX - 2 do
	table.insert(extras, H.addPlayer({ userId = 9410 + k, name = "Extra" .. k, client = false, noCharacter = true }))
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

------------------------------------------------------------------ 11. every island's tree and eggs; the tree fixed (GAME_DESIGN 4, 6)
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
	-- (no price tags over anyone's eggs: the eggs are bought in the tree's panel, the request of 2026-11-13)
	local canvasC = c.PlayerGui:FindFirstChild("World") and c.PlayerGui.World:FindFirstChild("Canvas")
	E.run(0.5)
	local tags = 0
	for _, g in canvasC and canvasC:GetDescendants() or {} do
		if string.match(g.Name, "^EggHatch_(%d+)$") then
			tags += 1
		end
	end
	H.expect(tags == 0 and EVc.count(cPlot) == #sc.profile.clutch.list, "eggs", "Cy's own eggs drawn, with no price tags over them or the neighbours'", string.format("%d tags, %d of %d eggs drawn", tags, EVc.count(cPlot), #sc.profile.clutch.list))
end
-- the tree on Cy's island: a tap on it opens its panel; it is never cleared away, bought or replaced, but it moves like
-- any piece (its model and its eggs with it); in Build mode a tap picks it up with Clear away off. Every other piece
-- clears away.
E.phase = "fixed"
local cp = H.profile(c)
cp.shells = 55000
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

------------------------------------------------------------------ 12. a big island (GAME_DESIGN 4: "allow the player to expand their land even more")
-- A tier 20 save (Everdrift, the last of the twenty tiers since the request of 2026-11-14: "allow expansion up to level
-- 20") joins on the plot the last server-side neighbour leaves: its land reaches far north of where Driftling Haven
-- (tier 10) ended, no coast walls up there and the seabed under the sea past its north shore, the founder walks up
-- there and is still at home with the view on them, pieces, tiles and fences fit up there (the saved oak among them),
-- the pieces of tiers 11 to 20 build there, and Build mode's button says Island max.
E.phase = "big-island"
do
	local last = extras[#extras]
	local freed = H.session(last) and H.session(last).plot
	E.removePlayer(last, "leave")
	E.run(2)
	local TB = #Tuning.TierCost
	local tx, tz, trot = Plot.spot(TB, {}, Tree.ID, Tree.SPOT.x, Tree.SPOT.z, 0)
	local treeQ = { uid = 10, id = Tree.ID, x = tx, z = tz, rot = trot, lvl = 1 }
	local pr = Street.plot(TB)
	local oak = nil
	for z = pr.z0, -80 do
		for x = pr.x0, pr.x1 do
			if oak == nil and Plot.fits(TB, { treeQ }, "oak", x, z, 0) then
				oak = { uid = 11, id = "oak", x = x, z = z, rot = 0, lvl = 1 }
			end
		end
	end
	local store = Tuning.DataStoreName .. "/global"
	E.cloud.stores[store] = E.cloud.stores[store] or {}
	E.cloud.stores[store]["u_9430"] = {
		value = { data = { v = 14, shells = 1e5, wood = 1e5, tier = TB, tut = 0, quest = 5, plot = { placed = { treeQ, oak } }, nextId = 20 } },
		meta = {},
		userIds = {},
		version = 1,
		created = E.SIM.now,
		updated = E.SIM.now,
	}
	local big = H.addPlayer({ userId = 9430, name = "Everdrift" })
	E.run(4)
	local sb, bp = H.session(big), H.profile(big)
	H.expect(sb ~= nil and sb.plot == freed and bp.tier == TB and plotModel(freed):GetAttribute("Tier") == TB and TB == 20, "big", "a tier 20 island takes the freed plot", string.format("%s on %s", tostring(bp and bp.tier), tostring(sb and sb.plot)))
	local bi = if sb then sb.plot else freed
	local land = staticOf(bi) and staticOf(bi):FindFirstChild("Land")
	local box = Street.origin(bi)
	-- the lawn reaches the island's northern edge, far past z -64
	local north = math.huge
	for _, d in if land then land:GetDescendants() else {} do
		if d.Name == "Lawn" and d:IsA("BasePart") then
			north = math.min(north, d.Position.Z - d.Size.Z / 2)
		end
	end
	H.expect(pr.z0 < Street.plot(10).z0 - 60 and math.abs(north - pr.z0) < 0.01, "big", "its land reaches far north of where Driftling Haven ended (the lawn to its edge)", string.format("lawn to z %.2f, grass to %d (Driftling Haven %d)", north, pr.z0, Street.plot(10).z0))
	-- no walls in the far north either (the founder swims off any beach), and the seabed under the sea up there
	H.expect(land ~= nil and land:FindFirstChild("Bound", true) == nil, "big", "no coast walls up north either")
	local bedNorth = false
	for _, d in plots:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Seabed" then
			local c, sz = d.Position, d.Size
			if math.abs(box - c.X) <= sz.X / 2 and math.abs(Street.plot(TB).z0 - 6 - c.Z) <= sz.Z / 2 then
				bedNorth = true
			end
		end
	end
	H.expect(bedNorth, "big", "the seabed reaches past its north shore")
	-- the saved oak stands up there
	local decorB = decorOf(bi)
	H.expect(oak ~= nil and decorB ~= nil and decorB:FindFirstChild(keyOf(oak)) ~= nil, "big", "the saved oak far north stands there", oak and keyOf(oak))
	-- the founder walks up there: still on their own island (no Home button), the view keeping them in the middle
	local CCb = H.cmod(big, "Controllers.CameraController")
	local wz = -180
	local wxs = nil
	for x = pr.x0, pr.x1 do
		if wxs == nil and Street.buildable(TB, x, wz) then
			wxs = x + 8
		end
	end
	E.run(1)
	local p0x, p0y = CCb.pan()
	if big.Character and wxs then
		big.Character:PivotTo(E.cf.new(box + wxs + 0.5, 3, wz + 0.5))
	end
	E.run(3)
	local p1x, p1y = CCb.pan()
	local r = rootOf(big)
	local v = CCb.view()
	local gx, gy = RasterW.gridPoint(v.rot12, v.grid, r.Position.X, Street.LAWN_Y + 1.5, r.Position.Z)
	local sx2, sy2 = (gx - p1x) * v.K, (gy - p1y) * v.K
	local mid = math.abs(sx2 - v.fullX / 2) <= v.fullX * 0.06 and sy2 >= v.fullY * 0.3 and sy2 <= v.fullY * 0.7
	H.expect(r ~= nil and r.Position.Z < -170 and (p1x ~= p0x or p1y ~= p0y) and mid, "big", "the founder walks far north, the view following them there", string.format("%d,%d on %dx%d", sx2, sy2, v.fullX, v.fullY))
	H.expect(H.buttonNamed(big, "Home") == nil, "big", "and they are still at home there (no Home button)")
	-- pieces, tiles and fences fit up there: a torch on the northernmost grass a piece may stand on, a water tile, a
	-- length of brick wall; past the island's edge refused
	local placed = bp.plot.placed
	local nx, nz = nil, nil
	for z = pr.z0, pr.z1 do
		for x = pr.x0, pr.x1 do
			if nx == nil and Plot.fits(TB, placed, "torch", x, z, 0) then
				nx, nz = x, z
			end
		end
	end
	local function evenFree(id: string, rot: number, zMax: number): (number?, number?)
		for z = zMax - zMax % 2, pr.z0, -2 do
			for x = pr.x0 - pr.x0 % 2, pr.x1, 2 do
				if Plot.fits(TB, placed, id, x, z, rot) then
					return x, z
				end
			end
		end
		return nil, nil
	end
	local ok1 = nx ~= nil and H.req(big, "plot.place", { id = "torch", x = nx, z = nz, rot = 0 }).ok
	local wx, wz2 = evenFree("stream", 0, -70)
	local ok2 = wx ~= nil and H.req(big, "plot.paint", { id = "stream", cells = string.format("%d,%d", wx, wz2) }).ok
	local fx, fz = evenFree("brickwall", 0, -76)
	local ok3 = fx ~= nil and H.req(big, "plot.fence", { id = "brickwall", edges = string.format("%d,%d,0", fx, fz) }).ok
	E.run(0.5)
	local built = 0
	for _, q in placed do
		-- (the lone water tile's mask is 1, its level's place: keyOf's name all the same)
		if q.z < -64 and decorB and decorB:FindFirstChild(keyOf(q)) then
			built += 1
		end
	end
	H.expect(ok1 and ok2 and ok3 and (nz or 0) < -100 and built == 4, "big", "a torch on its northernmost grass, a water tile and a wall up there: placed and built", string.format("torch at %s, %s %s %s, %d built", tostring(nz), tostring(ok1), tostring(ok2), tostring(ok3), built))
	local off = H.req(big, "plot.place", { id = "oak", x = 0, z = pr.z0 - 12, rot = 0 })
	H.expect(not off.ok and off.err == "blocked", "big", "past the island's northern edge: refused (blocked)", tostring(off.err))
	-- the pieces of the tiers past Driftling Haven build up north (a hut, a workplace, a boost and a grand piece of
	-- tier 20, 19, 17 and 14), each with its model
	bp.shells = 1e11
	local function pieceAt(id: string, x: number, z: number): any
		for _, q in bp.plot.placed do
			if q.id == id and q.x == x and q.z == z then
				return q
			end
		end
		return nil
	end
	local high = {}
	for _, id in { "citadel", "vineyard", "tidebell", "canopymill", "ironwood", "seacrown" } do
		local d = Buildings.byId[id]
		local hx, hz = nil, nil
		for z = Street.plot(10).z0 - 4, pr.z0, -1 do
			for x = pr.x0, pr.x1 do
				if hx == nil and Plot.fits(TB, placed, id, x, z, 0) then
					hx, hz = x, z
				end
			end
			if hx then
				break
			end
		end
		local rq = if hx then H.req(big, "plot.place", { id = id, x = hx, z = hz, rot = 0 }) else { ok = false, err = "no spot" }
		E.run(0.3)
		local q = if hx then pieceAt(id, hx :: number, hz :: number) else nil
		table.insert(high, string.format("%s (tier %d) %s", id, d.tier, if rq.ok and q and decorB and decorB:FindFirstChild(keyOf(q)) then "built" else tostring(rq.err)))
		H.expect(d.tier > 10 and rq.ok and q ~= nil and decorB ~= nil and decorB:FindFirstChild(keyOf(q)) ~= nil, "big", string.format("a %s (tier %d) placed far north and built", d.name, d.tier), tostring(rq.err))
	end
	H.log("big: %s", table.concat(high, ", "))
	-- the expansion's button in Build mode: Island max, greyed, no price; the server grows it no more
	H.clickNamed(big, "Menu_build", { wait = 0.4 })
	local maxB = H.buttonNamed(big, "Expand", true)
	H.expect(maxB ~= nil and table.find(H.textsOf(maxB), "Island max") ~= nil and H.buttonNamed(big, "Expand") == nil and big.PlayerGui:FindFirstChild("ExpandCost", true) == nil, "big", "Build mode's button says Island max, greyed, no price", maxB and table.concat(H.textsOf(maxB), "/"))
	local more = H.req(big, "island.expand", {})
	H.expect(not more.ok and more.err == "max" and bp.tier == 20, "big", "and the server grows it no more (max)", tostring(more.err))
	H.clickNamed(big, "BuildDone", { wait = 0.3 })
	H.checkProfile(big, "big island")
	settled(big)
	H.checkMirror(big, "big island")
end

report(E, H)
