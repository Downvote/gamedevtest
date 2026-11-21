-- The game's thumbnails and icon, part 1 (the request of 2026-11-20: "could you make thumbnails that are engaging and
-- show the gameplay well, along with an icon? use creature models, dont need to show the player"), for the preview
-- scenario "gthumbs" (tools/README.md). The pictures are the game's own, drawn its own way:
--   * "gthumbs" (or "gthumbs=<shot>,<shot>"): the world as the game draws it (the pixel filter), the HUD off and the
--     founder parked out of every frame, on a decorated tier 8 town (tools/preview/showcase.luau) in a sunny spell
--     with the rarest eggs under the Tree of Life: frames gth_tree (the tree and its eggs), gth_tree_near (closer)
--     and gth_town (the town from further out); "crowd" adds gth_crowd, driftlings gathered by the tree.
--   * "gthumbs=hatch": the hatch scene (UI/HatchScene) for the rarest egg with no mutations, so no cards beside it:
--     gth_hatch_egg, gth_hatch_blaze, gth_hatch_out, gth_hatch_reveal.
--   * "gthumbs=lawn": a round islet far from the others (palms, bushes, flowers, two rare eggs) with twenty
--     driftlings on it cheering, framed close by a stage view: gth_lawn.
--   * "gthumbs=cast": driftlings (and the rarest egg) drawn alone through Pixel/Snapshot (the world's palette, bands,
--     shadows and its 1 px ink outline) at the sizes the thumbnails show them, mid-cheer, logged as
--     `@@GTH <name> <w> <h> <RGBA hex>` lines with a `gthumbs: <n> kinds` line for the captions.
--     "gthumbs=cast:<id>,<id>" (an id may carry its cheer's time, "skyfox@0.3") draws those at 64 px to choose from.
-- Frames are captured at the device's size (desktop: 1920 x 1080, 4 screen px an art px). tools/preview/game_thumbs.py
-- lays them out with the title and the captions (sh tools/preview/game_thumbs.sh runs all of it).
return function(env)
	local E, H, log, capture = env.E, env.H, env.log, env.capture
	local Vector2, Vector3, CFrame = E.types.Vector2, E.types.Vector3, E.types.CFrame
	local mode = env.mode or "scene"

	-- Every frame at one pixel size the layout knows (tools/preview/game_thumbs.py reads them back pixel for pixel):
	-- 4 screen px an art px for the scenes laid out on the 480 x 270 grid, 2 for the before-and-after pair on its
	-- 960 x 540 one (the request of 2026-11-21: "could you increase the pixel resolution of the islands?"). The game
	-- picks 3 at 1080p (Tuning.PixelScaleSides), which the layout once read as 4, resampling every frame unevenly.
	local artK = if mode == "day1" or mode == "icon" or string.sub(mode, 1, 6) == "day100" then 2 else 4
	-- (the icon's island drawn at ICON_SMALL art px a stud while this is on, the widest View notch answering that in
	-- place of 5: the island whole under a tree drawn bigger, the requests of 2026-11-21, "Make the island small enough
	-- for the whole island to be in frame of the icon, without changing the tree size")
	local ICON_SMALL = 3
	local iconSmall = false
	local join0 = env.join
	env.join = function(uid: number, name: string)
		local p = join0(uid, name)
		-- (Tuning is frozen: the camera's fit, Render/Raster.pixelScale, answers artK for this run's client instead)
		local R = env.cshared(p, "Render.Raster")
		local CCk = env.modOr(p, "Controllers.CameraController")
		if R and CCk then
			H.inClient(p, function()
				R.pixelScale = function()
					return artK
				end
				if mode == "icon" then
					local gs0 = R.gridScale
					R.gridScale = function(fit: number, zoom: number, even: boolean): number
						if iconSmall and fit == 5 and zoom == 1 and not even then
							return gs0(ICON_SMALL, 1, false)
						end
						return gs0(fit, zoom, even)
					end
				end
				CCk.refit()
			end)
		end
		E.run(0.5)
		return p
	end

	-- the cast: { name, species (or "egg<r>": an egg of rarity r, "egg": the rarest), size, yaw, cheer's time }
	local CAST = {
		-- the title thumbnail's two in front, and a third smaller between them
		{ "hero_l", "blazemane", 150, 32, 0.1 },
		{ "hero_r", "skyfox", 136, -30, 0.3 },
		{ "hero_s", "emberpup", 92, 36, 0.5 },
		-- the building thumbnail's two
		{ "build_1", "frostcrown", 104, 30, 0.1 },
		{ "build_2", "mossbun", 72, 24, 0.15 },
	}

	if mode == "cast" or string.sub(mode, 1, 5) == "cast:" then
		local p = env.join(7306, "Caster")
		env.settle(p, 30, 1)
		local Snapshot = env.modOr(p, "Pixel.Snapshot")
		local MM = env.cshared(p, "Models.MicroModels")
		local EggModels = env.cshared(p, "Models.EggModels")
		local Traits = env.cshared(p, "Data.Traits")
		local Creatures = env.cshared(p, "Data.Creatures")
		-- (the thumbnails' captions count the kinds)
		log("gthumbs: %d kinds of driftling, rarest egg %d", #Creatures.list, Traits.RMAX)
		local list = CAST
		if string.sub(mode, 1, 5) == "cast:" then
			list = {}
			-- (an id may carry its cheer's time, "skyfox@0.7")
			for id in string.gmatch(string.sub(mode, 6), "[^,]+") do
				local sp, t = string.match(id, "^([%w_]+)@([%d%.]+)$")
				table.insert(list, { id, sp or id, 64, 28, tonumber(t) or 0.4 })
			end
		end
		local jobs = {}
		H.inClient(p, function()
			Snapshot.setBudget(1000)
			for _, c in list do
				local name, sp, size, yaw, time = c[1], c[2], c[3], c[4], c[5]
				local snap = Snapshot.get("gth:" .. name, function()
					if string.sub(sp, 1, 3) == "egg" then
						local r = tonumber(string.sub(sp, 4)) or Traits.RMAX
						local m = EggModels.build(r)
						m:PivotTo(CFrame.new())
						return m
					end
					local t = MM.species(sp, "full")
					MM.animate(t, time, "cheer", 0)
					MM.place(t, CFrame.new())
					return t.model
				end, { size = size, yaw = yaw, pitch = 22, pad = 1, outline = "outer", shadows = true, keep = true })
				table.insert(jobs, { name = name, snap = snap })
			end
		end)
		local t = 0
		while t < 900 and Snapshot.pending() > 0 do
			E.step(E.dt)
			t += E.dt
		end
		local bad = 0
		for _, j in jobs do
			local snap = j.snap
			if snap == nil or not snap.ready or snap.image == nil then
				bad += 1
				log("gthumbs: %s was not drawn", j.name)
				continue
			end
			local buf
			H.inClient(p, function()
				buf = snap.image:ReadPixelsBuffer(Vector2.zero, Vector2.new(snap.w, snap.h))
			end)
			local n = snap.w * snap.h
			local out = table.create(n)
			for i = 0, n - 1 do
				out[i + 1] = string.format("%08x", buffer.readu32(buf, i * 4))
			end
			print(string.format("@@GTH %s %d %d %s", j.name, snap.w, snap.h, table.concat(out)))
		end
		log("gthumbs: %d pictures, %d not drawn", #jobs, bad)
		return p
	end

	-- the hatch: the rarest egg on its pedestal (UI/HatchScene), no mutations so no cards beside it, hatching the first
	-- kind of its rarity, new; frames as it blazes, breaks and shows what came out
	if mode == "hatch" then
		local Traits = H.sharedServer("Data.Traits")
		local Creatures = H.sharedServer("Data.Creatures")
		local r = Traits.RMAX
		local sp = nil
		for _, d in Creatures.list do
			if d.rarity == r and sp == nil then
				sp = d.id
			end
		end
		env.seedProfile(7308, 10, { pals = { "mossbun" }, shells = 9e6 })
		local p = env.join(7308, "Hatcher")
		env.settle(p, 30, 1)
		local HS = env.modOr(p, "UI.HatchScene")
		H.inClient(p, function()
			HS.play({ sp = sp or "mossbun", muts = {}, r = r, hr = r, new = true }, nil)
		end)
		local function state()
			return H.inClient(p, HS.debugState)
		end
		local function runTo(t)
			E.runUntil(function()
				return state().clock >= t
			end, 10, 0.05)
		end
		E.run(0.12)
		local st = state()
		runTo(st.wait + 1.35)
		capture(p, "gth_hatch_egg")
		for _ = 1, st.reveals do
			H.inClient(p, HS.skip)
			E.run(0.3)
		end
		H.inClient(p, HS.skip)
		E.run(0.35)
		st = state()
		runTo(st.clock - 0.35 + st.build * 0.85)
		capture(p, "gth_hatch_blaze")
		E.runUntil(function()
			return state().phase ~= "breaking"
		end, 5, 0.05)
		local t0 = state().clock
		runTo(t0 + 0.55)
		capture(p, "gth_hatch_out")
		E.runUntil(function()
			return state().phase == "done"
		end, 5, 0.05)
		E.run(0.4)
		capture(p, "gth_hatch_reveal")
		log("gthumbs: hatched %s (rarity %d)", tostring(sp), r)
		return p
	end

	-- the lawn: a little floating islet far from the others (grass over an earth lip and rock, palms, bushes and flowers at the
	-- back, two rare eggs in front), a crowd of driftlings on it cheering, framed close by a stage view (the pals'
	-- way): frame gth_lawn
	if mode == "lawn" then
		env.seedProfile(7309, 1, {})
		local p = env.join(7309, "Keeper")
		env.settle(p, 30, 1)
		for _, g in p.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
				g.Enabled = false
			end
		end
		local MM = env.cshared(p, "Models.MicroModels")
		local Blocks = env.cshared(p, "Models.Blocks")
		local DecorModels = env.cshared(p, "Models.DecorModels")
		local EggModels = env.cshared(p, "Models.EggModels")
		local Plot = env.cshared(p, "Logic.Plot")
		local Traits = env.cshared(p, "Data.Traits")
		local PR = H.cmod(p, "Pixel.PixelRenderer")
		local CC = H.cmod(p, "Controllers.CameraController")
		local OX, OZ = 0, 9400
		local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
		local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
		local faceViewer = math.atan2(vx, vz)
		local function at(u: number, v: number): (number, number)
			return OX + ux * u + vx * v, OZ + uz * u + vz * v
		end
		local CROWD = {
			-- the back row (biggest), then the middle and the front
			{ "glimmerfleece", "blazemane", "cloudwhale", "frostcrown", "pyredrake" },
			{ "crystowl", "bloomoth", "skyfox", "lumajelly", "novafox", "tidewyrm" },
			{ "mossbun", "emberpup", "amethare", "hopsprout", "sunsprite" },
			{ "conchy", "frostling", "cloudjelly", "gullfin" },
		}
		local things = {}
		H.inClient(p, function()
			local m = Blocks.model(E.workspace, "ThumbLawn")
			-- (round: discs standing on their axis, a little floating islet: the grass, its earth lip, the rock under it)
			local up = CFrame.Angles(0, 0, math.rad(90))
			Blocks.part(m, { shape = "Cylinder", size = Vector3.new(3, 29, 29), cf = CFrame.new(OX, -4.75, OZ) * up, color = "rock" })
			Blocks.part(m, { shape = "Cylinder", size = Vector3.new(2.25, 33, 33), cf = CFrame.new(OX, -2.125, OZ) * up, color = "chocolate" })
			Blocks.part(m, { shape = "Cylinder", size = Vector3.new(1, 33, 33), cf = CFrame.new(OX, -0.5, OZ) * up, color = "grass" })
			local function decor(id: string, u: number, v: number, rot: number?)
				local x, z = at(u, v)
				local w, d = Plot.footprint(id, rot or 0)
				local dm = DecorModels.build(id, CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(rot or 0), 0) * CFrame.new(w / 2 - w / 2, 0, d / 2 - d / 2), 1)
				dm.Parent = m
			end
			decor("palm", -9, -12)
			decor("palm", 8, -13)
			decor("palm", -14, -5)
			decor("palm", 14, -6)
			decor("bush", -3, -13)
			decor("bush", 3.5, -13)
			decor("flowers", -12, 3)
			decor("flowers", 12, 4)
			decor("shellpile", 9, 9)
			decor("torch", -6, -11)
			decor("torch", 6, -11)
			-- (the eggs are the client's moving models in the game too: Controllers/EggView)
			for k, eu in { { -10.5, 5 }, { 10.5, 5.5 } } do
				local x, z = at(eu[1], eu[2])
				local egg = EggModels.build(Traits.RMAX - (k - 1))
				-- (standing on the grass: its box's foot at the ground)
				local cf, size = egg:GetBoundingBox()
				egg:PivotTo(CFrame.new(x, egg:GetPivot().Y - (cf.Y - size.Y / 2), z))
				egg:SetAttribute("PixelShadow", 1)
				egg:SetAttribute("PixelGroundY", 0)
				egg.Parent = E.workspace
				PR.registerDynamic(egg)
			end
			for row, list in CROWD do
				local n = #list
				local gap = if row == 1 then 4.2 else 3.6
				for i, sp in list do
					local th = MM.species(sp, "full")
					th.model:SetAttribute("PixelShadow", 1)
					th.model:SetAttribute("PixelGroundY", 0)
					th.model.Parent = E.workspace
					PR.registerDynamic(th.model)
					local u = (i - (n + 1) / 2) * gap
					local v = -6 + (row - 1) * 3.4
					local x, z = at(u, v)
					table.insert(things, { t = th, x = x, z = z, turn = -u * 3.2 })
				end
			end
			local pts = {}
			for _, q in { { -12.5, -12.5 }, { 12.5, -12.5 }, { -12.5, 7 }, { 12.5, 7 } } do
				for _, y in { 0, 3.2 } do
					local x, z = at(q[1], q[2])
					table.insert(pts, x)
					table.insert(pts, y)
					table.insert(pts, z)
				end
			end
			CC.setStage({ name = "thumbs", origin = Vector3.new(OX, 0, OZ), pts = pts, tight = nil, top = 4, bottom = 4 })
		end)
		H.inClient(p, function()
			for j, x in things do
				MM.animate(x.t, ({ 0.1, 0.3, 0.5 })[j % 3 + 1], "cheer", 0)
				MM.place(x.t, CFrame.new(x.x, 0, x.z) * CFrame.Angles(0, faceViewer + math.rad(x.turn), 0))
			end
		end)
		env.settle(p, 60, 0.5)
		E.run(0.5)
		capture(p, "gth_lawn")
		return p
	end

	-- the sky: a Grand Isle (tier 3, the harbour island's pieces) floating in the painted sky, its town round the tree,
	-- from a little further out: frame gth_sky
	if mode == "sky" then
		env.seedProfile(7310, 3, { pieces = env.harbor, pals = env.pals, shells = 65000 })
		local p = env.join(7310, "Rocky")
		env.settle(p, 60, 1)
		local Street = H.sharedServer("Data.Street")
		local ox = Street.origin(H.session(p).plot)
		for _, g in p.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
				g.Enabled = false
			end
		end
		-- (the founder on the empty islet of the last plot, out of the frame)
		if p.Character then
			local lx, lz = Street.origin(Street.MAX)
			p.Character:PivotTo(E.cf.new(lx, 3, lz + Street.CENTER.z))
		end
		local SU = env.modOr(p, "UI.SettingsUI")
		H.openPanel(p, "settings")
		E.run(0.4)
		if SU then
			H.inClient(p, SU.setZoom, 3)
		end
		E.run(0.8)
		H.closePanel(p)
		E.run(0.5)
		for _, g in p.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
				g.Enabled = false
			end
		end
		local CC = env.modOr(p, "Controllers.CameraController")
		if CC then
			H.inClient(p, CC.setFocus, Vector3.new(ox + 2, Street.LAWN_Y, 4), true)
		end
		-- (the sky held at a warm late afternoon, the sun low over the sea of clouds, the weather clear)
		local SB = env.modOr(p, "UI.SkyBackdrop")
		local WVs = env.modOr(p, "Controllers.WeatherView")
		if WVs then
			H.inClient(p, WVs.debugSet, "sunny")
		end
		if SB then
			H.inClient(p, SB.debugHour, 0.735, 0)
		end
		E.run(1)
		env.settle(p, 60, 1)
		E.run(1.5)
		capture(p, "gth_sky")
		return p
	end

	-- "gthumbs=day1" / "gthumbs=day100": the two halves of the before-and-after thumbnail (the request of 2026-11-21:
	-- "research other island building games, and make a thumbnail referencing their framing as close as possible":
	-- the genre's most liked builders split the frame into a first island alone in open sky and a full one bleeding off
	-- the edge). day1: a new island (the tree and its first eggs, nothing built); day100: a decorated tier 8 town
	-- (tools/preview/showcase.luau; "day100:<tier>" another tier). Both whole, the View slider far out, a clear morning
	-- sky, the HUD off and the founder parked off the island: frames gth_day1 and gth_day100. "gthumbs=icon": the icon's
	-- island (the request of 2026-11-21: "make an icon, with the island being the centerpiece"), a first island
	-- furnished by tools/preview/icon_island.luau, whole in the middle at the widest View notch: gth_icon. Each frame is
	-- captured twice, the second time with the world's layer hidden (gth_<name>_sky): where the two differ is the
	-- island, which tools/preview/game_thumbs.py outlines and sets in front of a sky it paints itself.
	if mode == "day1" or mode == "icon" or string.sub(mode, 1, 6) == "day100" then
		local Plot = H.sharedServer("Logic.Plot")
		local Street = H.sharedServer("Data.Street")
		local Buildings = H.sharedServer("Data.Buildings")
		local Creatures = H.sharedServer("Data.Creatures")
		local Traits = H.sharedServer("Data.Traits")
		local icon = mode == "icon"
		local big = mode ~= "day1" and not icon
		-- (the full island's tier: "day100:<tier>" to try another; 8 by default, the widest View notch keeping its
		-- buildings readable while it runs off the frame's edge)
		local bigTier = tonumber(string.match(mode, "^day100:(%d+)$")) or 8
		local uid = if icon then 7314 elseif big then 7313 else 7312
		if big then
			local plan = require("./showcase")({ Plot = Plot, Buildings = Buildings, Street = Street, log = log })
			local pals = {}
			for k = 1, math.min(Plot.housingLimit(bigTier), 40) do
				table.insert(pals, Creatures.list[(k * 7 - 1) % #Creatures.list + 1].id)
			end
			env.seedProfile(uid, bigTier, {
				fill = function(prof)
					plan(prof)
				end,
				pals = pals,
				shells = 9e9,
				eggs = { Traits.RMAX, Traits.RMAX - 1, Traits.RMAX - 2, Traits.RMAX, Traits.RMAX - 3, Traits.RMAX - 1 },
			})
		elseif icon then
			local plan = require("./icon_island")({ Plot = Plot, Buildings = Buildings, Street = Street, log = log })
			env.seedProfile(uid, 1, {
				fill = function(prof)
					plan(prof)
				end,
				pals = { "emberpup", "mossbun", "skyfox", "pebblit", "bloomoth", "snowpuff", "gullfin", "sunsprite" },
				shells = 9e6,
				eggs = { Traits.RMAX, Traits.RMAX - 1, Traits.RMAX - 2, Traits.RMAX - 3, Traits.RMAX - 1, Traits.RMAX - 4, Traits.RMAX - 2 },
			})
		else
			env.seedProfile(uid, 1, { pals = {}, shells = 600 })
		end
		local p = env.join(uid, if icon then "Icon" elseif big then "Later" else "Sooner")
		env.settle(p, if big or icon then 120 else 60, 2)
		E.run(2)
		local ox = Street.origin(H.session(p).plot)
		-- the middle of what is on the island (the land's own middle for an empty one)
		local prof = H.profile(p)
		local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
		for _, q in prof.plot.placed do
			local r = Plot.rect(q.id, q.x, q.z, q.rot)
			x0, z0, x1, z1 = math.min(x0, r.x0), math.min(z0, r.z0), math.max(x1, r.x1), math.max(z1, r.z1)
		end
		local cx, cz = if x0 < math.huge then (x0 + x1) / 2 else 0, if z0 < math.huge then (z0 + z1) / 2 else Street.CENTER.z
		if icon then
			-- (the icon centres on the Tree of Life: the request of 2026-11-21, "zoom in more, with the tree as the
			-- centerpiece"; the layout crops round it)
			cx, cz = Street.CENTER.x, Street.CENTER.z
			for _, q in prof.plot.placed do
				local d = Buildings.byId[q.id]
				if d and d.kind == "tree" then
					local r = Plot.rect(q.id, q.x, q.z, q.rot)
					cx, cz = (r.x0 + r.x1) / 2, (r.z0 + r.z1) / 2
				end
			end
		end
		log("gthumbs: %s pieces %d, middle %.1f, %.1f", mode, #prof.plot.placed, cx, cz)
		local function hud()
			for _, g in p.PlayerGui:GetChildren() do
				if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
					g.Enabled = false
				end
			end
		end
		hud()
		if p.Character then
			local lx, lz = Street.origin(Street.MAX)
			p.Character:PivotTo(E.cf.new(lx, 3, lz + Street.CENTER.z))
		end
		local SU = env.modOr(p, "UI.SettingsUI")
		-- the icon in two captures from one camera point (the tree's foot): first the island without its tree, small
		-- enough to be whole in the frame (ICON_SMALL a stud); then the tree and its eggs alone, close (notch 5);
		-- tools/preview/game_thumbs.py sets the big tree on the small island
		local plotI = H.session(p).plot
		local treeModel: Instance? = nil
		local function decorOf(): Instance?
			local plots = E.workspace:FindFirstChild("Plots")
			local pm = if plots then plots:FindFirstChild("Plot_" .. plotI) else nil
			local st = if pm then pm:FindFirstChild("Static") else nil
			return if st then st:FindFirstChild("Decor") else nil
		end
		if icon then
			iconSmall = true
			H.inClient(p, function()
				local d = decorOf()
				if d then
					for _, c in d:GetChildren() do
						if string.find(c.Name, ":tree:", 1, true) then
							treeModel = c
							c.Parent = nil
						end
					end
				end
			end)
			log("gthumbs: icon tree model %s", if treeModel then "set aside" else "not found")
		end
		H.openPanel(p, "settings")
		E.run(0.4)
		if SU then
			-- (about the widest notch's span of sky at twice the pixels: 7 art px a stud, notch 3, on the 960 x 540 grid;
			-- the icon's island at the widest notch, drawn smaller still: iconSmall)
			H.inClient(p, SU.setZoom, if icon then 1 else 3)
		end
		E.run(0.8)
		H.closePanel(p)
		E.run(0.5)
		hud()
		local WVd = env.modOr(p, "Controllers.WeatherView")
		if WVd then
			H.inClient(p, WVd.debugSet, "sunny")
		end
		-- (a clear morning, the sun up in the first island's half, clear of the divide)
		local SBd = env.modOr(p, "UI.SkyBackdrop")
		if SBd then
			H.inClient(p, SBd.debugHour, 0.37, 0)
		end
		-- (each island moved inside its half of the frame by the camera, so the sky behind stays whole: the first one
		-- left of the divide, the full one right of it and lower, under the words; studs along the ground's
		-- screen-right and away-from-the-viewer directions)
		local shift = if icon then { 0, 0 } elseif big then { -30, 18 } else { 30, 0 }
		local rx, rz = math.sqrt(0.5), -math.sqrt(0.5)
		local ax, az = -math.sqrt(0.5), -math.sqrt(0.5)
		local fx = ox + cx + rx * shift[1] + ax * shift[2]
		local fz = cz + rz * shift[1] + az * shift[2]
		local CCd = env.modOr(p, "Controllers.CameraController")
		if CCd then
			H.inClient(p, CCd.setFocus, Vector3.new(fx, Street.LAWN_Y, fz), true)
		end
		E.run(1)
		env.settle(p, 60, 1)
		-- (four times the pixels take longer to bake: wait until the bake has ended, which the cast check needs)
		local PRd = env.modOr(p, "Pixel.PixelRenderer")
		if PRd then
			local t, cc = 0, nil
			while t < 900 do
				cc = H.inClient(p, PRd.debugCastCheck, false)
				if cc and cc.off ~= -1 then
					break
				end
				E.run(2)
				t += 2
			end
			local ga = if CCd then H.inClient(p, function()
				return CCd.view().grid.a
			end) else nil
			log("gthumbs: %s baked after %d s more, K %s, %s art px a stud, cast check off %s of %s", mode, t, tostring(H.inClient(p, PRd.pixelScale)), tostring(ga), tostring(cc and cc.off), tostring(cc and cc.checked))
		end
		E.run(1.5)
		local name = if icon then "gth_icon" elseif big then "gth_day100" else "gth_day1"
		capture(p, name)
		-- the same frame with the world's layer hidden: the sky alone, nothing stepped in between
		local layer = p.PlayerGui:FindFirstChild("PixelLayer")
		if layer then
			layer.Enabled = false
			capture(p, name .. "_sky")
			layer.Enabled = true
		end
		if icon then
			-- the tree and its eggs alone, close: everything else on the plots out of the client's world, the
			-- driftlings sent home (an empty list from the server), the tree back
			prof.pals = {}
			H.push(p, 0.5)
			H.inClient(p, function()
				local plots = E.workspace:FindFirstChild("Plots")
				if plots then
					for _, pm in plots:GetChildren() do
						if pm.Name ~= "Plot_" .. plotI then
							pm.Parent = nil
						else
							for _, c in pm:GetChildren() do
								if c.Name ~= "Static" then
									c.Parent = nil
								end
							end
							local st = pm:FindFirstChild("Static")
							if st then
								for _, c in st:GetChildren() do
									if c.Name ~= "Decor" then
										c.Parent = nil
									end
								end
							end
						end
					end
				end
				local d = decorOf()
				if d then
					for _, c in d:GetChildren() do
						c.Parent = nil
					end
					if treeModel then
						treeModel.Parent = d
					end
				end
			end)
			iconSmall = false
			H.openPanel(p, "settings")
			E.run(0.4)
			if SU then
				H.inClient(p, SU.setZoom, 5)
			end
			E.run(0.8)
			H.closePanel(p)
			E.run(0.5)
			hud()
			if CCd then
				H.inClient(p, CCd.setFocus, Vector3.new(fx, Street.LAWN_Y, fz), true)
			end
			E.run(1)
			env.settle(p, 30, 1)
			if PRd then
				local t, cc = 0, nil
				while t < 900 do
					cc = H.inClient(p, PRd.debugCastCheck, false)
					if cc and cc.off ~= -1 then
						break
					end
					E.run(2)
					t += 2
				end
				local ga = if CCd then H.inClient(p, function()
					return CCd.view().grid.a
				end) else nil
				log("gthumbs: icon tree baked after %d s more, %s art px a stud", t, tostring(ga))
			end
			E.run(1.5)
			capture(p, "gth_icontree")
			if layer then
				layer.Enabled = false
				capture(p, "gth_icontree_sky")
				layer.Enabled = true
			end
		end
		return p
	end

	-- the scenes: a decorated tier 8 town (tools/preview/showcase.luau), rare eggs under the tree
	local TIER = 8
	local Plot = H.sharedServer("Logic.Plot")
	local Creatures = H.sharedServer("Data.Creatures")
	local Street = H.sharedServer("Data.Street")
	local Buildings = H.sharedServer("Data.Buildings")
	local Traits = H.sharedServer("Data.Traits")
	local plan = require("./showcase")({ Plot = Plot, Buildings = Buildings, Street = Street, log = log })
	local info = nil
	local pals = {}
	for k = 1, math.min(Plot.housingLimit(TIER), 40) do
		table.insert(pals, Creatures.list[(k * 7 - 1) % #Creatures.list + 1].id)
	end
	local uid = 7307
	env.seedProfile(uid, TIER, {
		fill = function(prof)
			info = plan(prof)
		end,
		pals = pals,
		shells = 9e9,
		-- (the rarest the tree lays, whatever that is now)
		eggs = { Traits.RMAX, Traits.RMAX - 1, Traits.RMAX - 2, Traits.RMAX, Traits.RMAX - 3, Traits.RMAX - 1, Traits.RMAX - 4, Traits.RMAX - 2 },
	})
	local p = env.join(uid, "Thumbs")
	-- a sunny spell on the sea's clock (no rain or leaves across the pictures)
	local WD, WL, WC = H.sharedServer("Data.Weather"), H.sharedServer("Logic.Weather"), H.smod("WorldClock")
	local Tuning = H.sharedServer("Config.Tuning")
	if WD.byId.sunny then
		for k = 0, 2000 do
			local st = WL.at(WC.now() + k * Tuning.WeatherSecs)
			if st.kind == "sunny" then
				WC.shift(math.max(0, Tuning.WeatherEpoch + st.spell * Tuning.WeatherSecs + 20 - WC.now()))
				break
			end
		end
	end
	env.settle(p, 90, 2)
	E.run(3)
	local ox = Street.origin(H.session(p).plot)
	local zN = if info then info.zN else -10
	local prof = H.profile(p)
	local tree = { x0 = -4, z0 = -6, x1 = 4, z1 = 2 }
	for _, q in prof.plot.placed do
		local d = Buildings.byId[q.id]
		if d and d.kind == "tree" then
			tree = Plot.rect(q.id, q.x, q.z, q.rot)
		end
	end
	local tx, tz = (tree.x0 + tree.x1) / 2, (tree.z0 + tree.z1) / 2
	log("gthumbs: tree at %.1f, %.1f (%d x %d), the island's north end %d", tx, tz, tree.x1 - tree.x0, tree.z1 - tree.z0, zN)
	local CC = env.modOr(p, "Controllers.CameraController")
	local SU = env.modOr(p, "UI.SettingsUI")
	local PR = H.cmod(p, "Pixel.PixelRenderer")
	local MM = env.cshared(p, "Models.MicroModels")
	-- the HUD off, the founder parked out of every frame (on the island's north rim)
	for _, g in p.PlayerGui:GetChildren() do
		if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
			g.Enabled = false
		end
	end
	if p.Character then
		p.Character:PivotTo(E.cf.new(ox - 1, 3, zN + 3))
	end
	E.run(1)
	local WV = env.modOr(p, "Controllers.WeatherView")
	if WV then
		H.inClient(p, WV.debugSet, "sunny")
	end
	-- (the sky held in the middle of a clear day)
	local SBt = env.modOr(p, "UI.SkyBackdrop")
	if SBt then
		H.inClient(p, SBt.debugHour, 0.45, 0)
	end
	E.run(2)
	local function zoom(n: number)
		H.openPanel(p, "settings")
		E.run(0.4)
		if SU then
			H.inClient(p, SU.setZoom, n)
		end
		E.run(0.8)
		H.closePanel(p)
		E.run(0.5)
		for _, g in p.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "PixelLayer" and g.Name ~= "SkyBackdrop" then
				g.Enabled = false
			end
		end
	end
	local function look(x: number, z: number)
		if CC then
			H.inClient(p, CC.setFocus, Vector3.new(ox + x, Street.LAWN_Y, z), true)
		end
		E.run(1)
		env.settle(p, 60, 1)
		E.run(1.5)
	end
	-- driftlings put down by hand, cheering (the ground's screen-right and toward-the-viewer directions: the zoo's)
	local ux, uz = math.sqrt(0.5), -math.sqrt(0.5)
	local vx, vz = math.sqrt(0.5), math.sqrt(0.5)
	local faceViewer = math.atan2(vx, vz)
	local things = {}
	local function clear()
		H.inClient(p, function()
			for _, x in things do
				PR.unregisterDynamic(x.t.model)
				x.t.model:Destroy()
			end
		end)
		things = {}
	end
	-- `spots`: { species, u, v, turn (degrees past facing the viewer) } about the point (cx, cz), u to the screen's right,
	-- v toward the viewer (studs)
	local function gather(cx: number, cz: number, spots, mood: string?)
		clear()
		H.inClient(p, function()
			for j, s in spots do
				local th = MM.species(s[1], "full")
				th.model:SetAttribute("PixelShadow", 1)
				th.model:SetAttribute("PixelGroundY", Street.LAWN_Y)
				th.model.Parent = E.workspace
				PR.registerDynamic(th.model)
				local x = ox + cx + ux * s[2] + vx * s[3]
				local z = cz + uz * s[2] + vz * s[3]
				MM.animate(th, 0.3 + j * 0.37, mood or "cheer", 0)
				MM.place(th, E.cf.new(x, Street.LAWN_Y, z) * E.cf.Angles(0, faceViewer + math.rad(s[4] or 0), 0))
				table.insert(things, { t = th })
			end
		end)
	end
	local only = env.only

	-- the shots: { name, zoom notch, x, z (plot studs: the view's middle) }
	local SHOTS = {
		{ "tree", 8, tx, tz + 3 },
		{ "tree_near", 10, tx, tz + 2 },
		{ "town", 4, 0, -22 },
	}
	for _, s in SHOTS do
		if only == nil or only[s[1]] then
			zoom(s[2])
			look(s[3], s[4])
			capture(p, "gth_" .. s[1])
		end
	end
	-- a crowd on the lawn by the tree, close in
	if only and only.crowd then
		zoom(10)
		local crowd = {
			"glimmerfleece", "pyredrake", "cloudwhale", "aurorawing", "moonveil", "tidewyrm", "prismoth", "frostcrown",
			"novafox", "crystowl", "bloomoth", "starweaver", "blazemane", "cloudjelly", "elderbark", "nebulynx",
		}
		local spots = {}
		for i, sp in crowd do
			local row = math.floor((i - 1) / 6)
			local col = (i - 1) % 6
			table.insert(spots, { sp, -8.5 + col * 3.4 + (row % 2) * 1.7, -4.5 + row * 3.0, (col - 2.5) * -9 })
		end
		gather(tx, tz + 1, spots)
		look(tx, tz + 1)
		capture(p, "gth_crowd")
		clear()
	end
	return p
end
