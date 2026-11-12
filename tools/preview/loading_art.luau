-- The loading card's scene art (src/first/LoadingCard, docs/ARCHITECTURE.md 8.0), drawn ahead of time for the preview
-- scenario "ploadingart" (tools/README.md). The card goes up before the game has arrived and the client is busy
-- loading, so its island is not built and drawn live: it is drawn here, piece by piece and frame by frame, through the
-- game's own picture path (Pixel/Snapshot: the world's palette, toon bands, dither, sun shadows and the 1 px ink
-- outline), and tools/preview/gen_loading_art.py packs the frames into src/first/LoadingArt.luau.
--
-- What is drawn (art px; SCALE art px a stud, the world's own size on a 1080p screen):
--   * two villagers (CharacterModels, Island.randomLook) walking, one cycle of their gait each, facing left and (flipped)
--     right; a third cheering by the fire (poseAction "cheer");
--   * three driftlings of the beach and the meadow (MicroModels.driftling: Clawdle, Mossbun, Gullfin) on the move, as
--     the island shows them (MicroModels.animate "walk" and their hop), facing left and right;
--   * the campfire (a ring of stones, crossed logs and MicroModels' flame flickering in thirds, as WorldView's);
--   * the island's pieces (DecorModels): two palms, a Grass Hut, a Tent, a Tiki Torch, a Flower Bed and the wild Tide
--     Pool (its eyes open and shut);
--   * the expedition boat (MicroModels "ship", BoatSpec level 2) rocking on the swell, a step smaller (it is out at sea);
--   * hand-made 2D bits: a gull flapping, a star twinkling, a wave crest rising and falling, an ember, a glint of sun.
-- Output (the scenario's log): per frame `@@LART <seq> <i> <w> <h> <RGBA hex>`, per sequence
-- `@@LSEQ <seq> <frames> <seconds a frame> <anchor x> <anchor y>`, and points (`@@LPT <seq> <name> <x> <y>`, art px from
-- the anchor: head, a word rises there; flame, the embers rise from it).
return function(env)
	local E, H, log, capture = env.E, env.H, env.log, env.capture
	local Instance, Enum, UDim2, Color3 = E.Instance, E.Enum, E.types.UDim2, E.types.Color3
	local Vector2, Vector3, CFrame = E.types.Vector2, E.types.Vector3, E.types.CFrame
	local p = env.join(7301, "Lou")
	env.settle(p, 30, 1)
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	local CM = env.cshared(p, "Models.CharacterModels")
	local MM = env.cshared(p, "Models.MicroModels")
	local DM = env.cshared(p, "Models.DecorModels")
	local Blocks = env.cshared(p, "Models.Blocks")
	local Raster = env.cshared(p, "Render.Raster")
	local Creatures = env.cshared(p, "Data.Creatures")
	local Island = env.cshared(p, "Logic.Island")
	local Util = env.cshared(p, "Logic.Util")
	local Tuning = env.cshared(p, "Config.Tuning")
	if Snapshot == nil then
		log("ploadingart: this tree has no Pixel/Snapshot")
		return p
	end

	local SCALE = 6 -- art px a stud (the world on a 1080p screen)
	local FAR = 4 -- the boat's: out at sea
	local WALK_N = 8 -- frames a walk cycle
	local rot = Raster.rotation(Tuning.CamYaw, Tuning.CamPitch)
	local RIGHT = Vector3.new(rot[4], rot[7], rot[10])
	local UP = Vector3.new(rot[5], rot[8], rot[11])
	-- art px from the frame's anchor of a point in the world (studs)
	local function project(v, scale)
		local s = scale or SCALE
		return math.floor(v:Dot(RIGHT) * s + 0.5), math.floor(-v:Dot(UP) * s + 0.5)
	end

	------------------------------------------------------------------ sequences
	local order = {}
	local snapsLeft = 0
	-- n pictures, picture i of build(i) -> Model, all framed alike (box: w x h art px, the world origin at ax, ay);
	-- o: scale, mirror (flipped left to right when logged: the sun lights faces turned three quarters to the left, so
	-- one facing right is drawn facing left and flipped), base (a sequence framed alike whose first frame this one's is
	-- packed as a change on)
	local function seq(name, n, dur, box, build, pts, o)
		o = o or {}
		local s = { name = name, n = n, dur = dur, w = box.w, h = box.h, ax = box.ax, ay = box.ay, snaps = {}, pts = pts or {}, mirror = o.mirror, base = o.base }
		table.insert(order, s)
		H.inClient(p, function()
			for i = 1, n do
				s.snaps[i] = Snapshot.get("lart:" .. name .. ":" .. i, function()
					return build(i)
				end, { w = box.w, h = box.h, scale = o.scale or SCALE, anchor = Vector2.new(box.ax, box.ay), keep = true })
				snapsLeft += 1
			end
		end)
		return s
	end
	-- a sequence of hand-made pixel rows (2D): frames { { rows } }, colours char -> Color3
	local function flat(name, frames, colors, dur, ax, ay, pts)
		local w = #frames[1][1]
		local s = { name = name, n = #frames, dur = dur, w = w, h = #frames[1], ax = ax or 0, ay = ay or 0, rows = frames, colors = colors, pts = pts or {} }
		table.insert(order, s)
		return s
	end
	local function blk(m, sx, sy, sz, cf, color, o)
		local spec = { size = Vector3.new(sx, sy, sz), cf = cf, color = color, name = "Piece", collide = false, query = false }
		if o then
			for k, v in o do
				spec[k] = v
			end
		end
		return Blocks.part(m, spec)
	end
	-- a model moved so its foot's middle (the bounding box's bottom centre) is at the origin
	local function grounded(m)
		local cf, size = m:GetBoundingBox()
		local shift = Vector3.new(-cf.Position.X, -(cf.Position.Y - size.Y / 2), -cf.Position.Z)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = d.CFrame + shift
			end
		end
		return m
	end

	------------------------------------------------------------------ the villagers
	local WALKER = { w = 40, h = 46, ax = 20, ay = 40 }
	local function lookOf(seed)
		return Island.randomLook(Util.newRng(seed))
	end
	local lookA, lookB, lookC = lookOf(41), lookOf(77), lookOf(123)
	local function headPt(look, seed)
		local rig
		H.inClient(p, function()
			rig = CM.buildStanding(look, "Head", seed)
		end)
		local x, y = project(CM.STAND_TOP)
		rig.model:Destroy()
		return { head = { x, y } }
	end
	-- one cycle of the gait (CharacterModels' walkPose: 13 radians a second at a brisk walk), played a little slower
	local WALK_V = 12
	local GAIT = 2 * math.pi / 13
	local CYCLE = 0.64 -- a walk cycle on the card (seconds)
	local function walkSeq(name, look, seed, mirror)
		return seq(name, WALK_N, CYCLE / WALK_N, WALKER, function(i)
			local rig = CM.buildStanding(look, name, seed)
			CM.poseStanding(rig, CFrame.identity, 3 + (i - 1) * GAIT / WALK_N, WALK_V)
			return rig.model
		end, headPt(look, seed), { mirror = mirror })
	end
	walkSeq("walk_a", lookA, 41, false)
	walkSeq("walk_a_r", lookA, 41, true)
	walkSeq("walk_b", lookB, 77, false)
	walkSeq("walk_b_r", lookB, 77, true)
	-- a villager by the fire, cheering (arms up and waving: poseAction "cheer", one wave)
	do
		local n = 6
		seq("cheer", n, 0.09, WALKER, function(i)
			local rig = CM.buildStanding(lookC, "cheer", 123)
			CM.poseAction(rig, CFrame.Angles(0, math.rad(30), 0), 5 + (i - 1) * (2 * math.pi / 12) / n, 0, "cheer")
			return rig.model
		end, headPt(lookC, 123), { mirror = true })
	end

	------------------------------------------------------------------ the driftlings
	local CRITTER = { w = 52, h = 44, ax = 26, ay = 34 }
	local function critterSeq(name, sp, mirror, hop)
		local def = Creatures.byId[sp]
		local n = 8
		return seq(name, n, 0.085, CRITTER, function(i)
			local t = MM.driftling(def.shape, def.body, def.accent)
			local time = 4 + (i - 1) * (math.pi / 9) / n * 2
			MM.animate(t, time, "walk", 0)
			local bob = if hop then math.abs(math.sin(time * 9)) * 0.5 else 0
			MM.place(t, CFrame.new(0, bob, 0))
			return t.model
		end, nil, { mirror = mirror })
	end
	critterSeq("crab", "clawdle", false, false)
	critterSeq("crab_r", "clawdle", true, false)
	critterSeq("bun", "mossbun", false, true)
	critterSeq("bun_r", "mossbun", true, true)
	critterSeq("gullfin", "gullfin", false, true)
	critterSeq("gullfin_r", "gullfin", true, true)

	------------------------------------------------------------------ the campfire
	do
		local FIRE = { w = 34, h = 40, ax = 17, ay = 30 }
		local function camp(i)
			local m = Instance.new("Model")
			m.Name = "Camp"
			for k = 0, 6 do
				local a = k / 7 * math.pi * 2
				blk(m, 0.55, 0.4, 0.55, CFrame.new(math.cos(a) * 1.1, 0.2, math.sin(a) * 1.1) * CFrame.Angles(0, a, 0), if k % 2 == 0 then "rock" else "rock_dark")
			end
			blk(m, 1.6, 0.3, 0.35, CFrame.new(0, 0.2, 0) * CFrame.Angles(0, math.rad(35), 0), "wood_dark")
			blk(m, 1.6, 0.3, 0.35, CFrame.new(0, 0.3, 0) * CFrame.Angles(0, math.rad(-55), 0), "wood")
			-- (the flame half again the plaza's size: the card's fire is the scene's middle)
			local flame = MM.build("flame")
			MM.scale(flame, Vector3.new(1.5, 1.5 * (0.85 + ((i - 1) % 3) * 0.15), 1.5))
			MM.place(flame, CFrame.new(0, 0.45, 0))
			flame.model.Parent = m
			return m
		end
		local fx, fy = project(Vector3.new(0, 2, 0))
		seq("fire", 3, 0.1, FIRE, camp, { flame = { fx, fy } })
	end

	------------------------------------------------------------------ the island's pieces
	local function piece(name, id, box, yaw, frames, edit)
		seq(name, frames or 1, 0.25, box, function(i)
			local m = DM.build(id, CFrame.Angles(0, math.rad(yaw or 0), 0))
			if edit then
				edit(m, i)
			end
			return grounded(m)
		end)
	end
	piece("palm", "palm", { w = 64, h = 84, ax = 32, ay = 74 }, 0)
	piece("palm_b", "palm", { w = 64, h = 84, ax = 32, ay = 74 }, 140)
	piece("hut", "hut", { w = 72, h = 64, ax = 36, ay = 50 }, 0)
	piece("tent", "tent", { w = 60, h = 50, ax = 30, ay = 38 }, 0)
	piece("torch", "torch", { w = 20, h = 40, ax = 10, ay = 34 }, 0)
	piece("flowers", "flowers", { w = 40, h = 30, ax = 20, ay = 20 }, 0)
	piece("bush", "bush", { w = 32, h = 30, ax = 16, ay = 22 }, 0)
	-- the wild Tide Pool: its eyes open, then shut (a blink)
	piece("pool", "wild_tidepool", { w = 64, h = 50, ax = 32, ay = 34 }, 0, 2, function(m, i)
		if i == 2 then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Eye" then
					d.Transparency = 1
				end
			end
		end
	end)

	------------------------------------------------------------------ the boat
	do
		local BOAT = { w = 64, h = 60, ax = 32, ay = 44 }
		local n = 4
		seq("boat", n, 0.32, BOAT, function(i)
			local t = MM.build("ship", { level = 2 })
			local a = (i - 1) / n * math.pi * 2
			MM.place(t, CFrame.new(0, math.sin(a) * 0.15, 0) * CFrame.Angles(0, math.rad(90), math.rad(math.sin(a) * 3)))
			return t.model
		end, nil, { scale = FAR })
	end

	------------------------------------------------------------------ the hand-made bits
	local C3 = Color3.fromRGB
	-- a gull: wings up, level, down, level (ink outline, white body)
	flat("gull", {
		{ "k.......k", "wk.....kw", ".wk...kw.", "..wkkkw..", "...kkk...", "........." },
		{ ".........", "kk.....kk", "wwk...kww", "..wkkkw..", "...kkk...", "........." },
		{ ".........", ".........", "kkk...kkk", "wwwkkkwww", "..kkkkk..", "........." },
		{ ".........", "kk.....kk", "wwk...kww", "..wkkkw..", "...kkk...", "........." },
	}, { k = C3(43, 30, 46), w = C3(244, 240, 232) }, 0.14, 4, 3)
	-- a star: a dot, a cross, a sparkle, a cross
	flat("star", {
		{ ".....", ".....", "..y..", ".....", "....." },
		{ ".....", "..y..", ".yWy.", "..y..", "....." },
		{ "..y..", "..y..", "yyWyy", "..y..", "..y.." },
		{ ".....", "..y..", ".yWy.", "..y..", "....." },
	}, { y = C3(255, 225, 140), W = C3(255, 252, 238) }, 0.18, 2, 2)
	-- a wave crest: foam rising, curling, falling away
	flat("crest", {
		{ ".......", ".......", "..fff.." },
		{ ".......", "..fff..", ".fFFFf." },
		{ "..fff..", ".fFFFf.", "f.....f" },
		{ ".......", ".fffff.", "f.....f" },
		{ ".......", ".......", ".f...f." },
	}, { f = C3(150, 210, 230), F = C3(232, 248, 252) }, 0.22, 3, 2)
	-- an ember rising from the fire: bright, then dimming
	flat("ember", {
		{ "y" },
		{ "o" },
		{ "r" },
	}, { y = C3(255, 230, 120), o = C3(255, 160, 60), r = C3(190, 70, 50) }, 0.3, 0, 0)
	-- a glint of the low sun on the sea
	flat("glint", {
		{ "..g..", "....." },
		{ ".ggg.", "..W.." },
		{ "ggWgg", ".ggg." },
		{ ".ggg.", "....." },
	}, { g = C3(255, 214, 140), W = C3(255, 248, 225) }, 0.2, 2, 1)

	------------------------------------------------------------------ draw and log
	local t = 0
	while t < 900 and Snapshot.pending() > 0 do
		E.step(E.dt)
		t += E.dt
	end
	log("ploadingart: %d pictures drawn in %.1f s (simulated)", snapsLeft, t)
	local function hexOf(buf, n)
		local out = table.create(n)
		for i = 0, n - 1 do
			out[i + 1] = string.format("%08x", buffer.readu32(buf, i * 4))
		end
		return table.concat(out)
	end
	local bad = 0
	for _, s in order do
		for k, v in s.pts do
			print(string.format("@@LPT %s %s %d %d", s.name, k, if s.mirror then -v[1] else v[1], v[2]))
		end
		print(string.format("@@LSEQ %s %d %.4f %d %d%s", s.name, s.n, s.dur, if s.mirror then s.w - 1 - s.ax else s.ax, s.ay, if s.base then " " .. s.base else ""))
		for i = 1, s.n do
			local hex
			if s.rows then
				local rows = s.rows[i]
				local buf = buffer.create(s.w * s.h * 4)
				for y, row in rows do
					for x = 1, #row do
						local col = s.colors[string.sub(row, x, x)]
						if col then
							local r, g, b = math.floor(col.R * 255 + 0.5), math.floor(col.G * 255 + 0.5), math.floor(col.B * 255 + 0.5)
							buffer.writeu32(buf, ((y - 1) * s.w + x - 1) * 4, r + g * 256 + b * 65536 + 0xFF000000)
						end
					end
				end
				hex = hexOf(buf, s.w * s.h)
			else
				local snap = s.snaps[i]
				if snap == nil or not snap.ready or snap.image == nil then
					bad += 1
					log("ploadingart: %s frame %d was not drawn", s.name, i)
					continue
				end
				local buf
				H.inClient(p, function()
					buf = snap.image:ReadPixelsBuffer(Vector2.zero, Vector2.new(s.w, s.h))
				end)
				if s.mirror then
					local flipped = buffer.create(s.w * s.h * 4)
					for y = 0, s.h - 1 do
						for x = 0, s.w - 1 do
							buffer.writeu32(flipped, (y * s.w + s.w - 1 - x) * 4, buffer.readu32(buf, (y * s.w + x) * 4))
						end
					end
					buf = flipped
				end
				hex = hexOf(buf, s.w * s.h)
			end
			print(string.format("@@LART %s %d %d %d %s", s.name, i, s.w, s.h, hex))
		end
	end
	log("ploadingart: %d sequences, %d frames not drawn", #order, bad)
	-- a look at them: every sequence's frames in a row on the card's dusk sky
	H.inClient(p, function()
		local g = Instance.new("ScreenGui")
		g.Name = "ArtSheet"
		g.DisplayOrder = 5000
		g.IgnoreGuiInset = true
		g.ScreenInsets = Enum.ScreenInsets.None
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(59, 47, 92)
		bg.BorderSizePixel = 0
		bg.Parent = g
		local canvas = Instance.new("Frame")
		canvas.BackgroundTransparency = 1
		canvas.Size = UDim2.fromScale(1, 1)
		canvas.Parent = g
		local sc = Instance.new("UIScale")
		sc.Scale = 2
		sc.Parent = canvas
		local x, y, rowH = 2, 2, 0
		for _, s in order do
			if s.snaps and s.snaps[1] then
				if x + s.w * math.min(s.n, 8) > 950 then
					x, y, rowH = 2, y + rowH + 2, 0
				end
				for i = 1, math.min(s.n, 8) do
					local im = Snapshot.label(s.snaps[i], canvas, true)
					im.Position = UDim2.fromOffset(x, y)
					x += s.w
				end
				x += 6
				rowH = math.max(rowH, s.h)
			end
		end
		g.Parent = p:FindFirstChildOfClass("PlayerGui")
	end)
	E.run(0.2)
	capture(p, "ploadingart_sheet")
	return p
end
