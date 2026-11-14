-- The driftlings' portraits (GAME_DESIGN 2: "instead of character sprites for the creatures, can you take their
-- pixellated models in a 3/4 angle, and polish them to follow pixel art rules if required?"), drawn ahead of time for
-- the preview scenario "pportraits" (tools/README.md) through the game's own picture path (Pixel/Snapshot: the
-- world's palette, toon bands, sun shadows and the 1 px ink outline): each driftling's model (Models/DriftModels via
-- MicroModels.driftling) standing at rest, eyes open, turned three quarters to the left, fitted to SIZE x SIZE art px,
-- in a portrait's own proportions (a bigger head and eyes, a lower camera: "most of those sprites look unreadable. try
-- to tweak them so they look more readable").
-- tools/preview/gen_portraits.py tidies them to the pixel art rules and writes scripts/portraits.txt, which
-- scripts/gen_art.py turns into the "icon_<species>" sprites (sh tools/preview/portraits.sh does all three).
-- Output (the scenario's log): per driftling `@@PORT <species> <w> <h> <RGBA hex>`. With `env.yaws` (a list of
-- degrees) every driftling is drawn at each, for choosing the angle (`@@PORT <species>@<yaw> ...`).
return function(env)
	local E, H, log, capture = env.E, env.H, env.log, env.capture
	local Instance, Enum, UDim2, Color3 = E.Instance, E.Enum, E.types.UDim2, E.types.Color3
	local Vector2, Vector3, CFrame = E.types.Vector2, E.types.Vector3, E.types.CFrame
	local p = env.join(7302, "Painter")
	env.settle(p, 30, 1)
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	local MM = env.cshared(p, "Models.MicroModels")
	local Creatures = env.cshared(p, "Data.Creatures")
	local Blocks = env.cshared(p, "Models.Blocks")
	if Snapshot == nil then
		log("pportraits: this tree has no Pixel/Snapshot")
		return p
	end
	local SIZE = env.size or 32
	-- (turned 30 degrees from the world's own view, its face toward +Z: three quarters, turned left, the face toward us
	-- and the body's side still showing)
	local YAW = env.yaw or 30
	local REST = 2.3 -- (any time: the "rest" mood is the pose as built, eyes open: Models/DriftMotion)
	-- (a portrait's own proportions, so it reads at 32 px: the head and everything on it bigger about the neck, the eyes
	-- bigger again, and the camera lower than the world's, so the face shows more and the top of the head less)
	local HEAD = env.head or 1.45
	local EYES = env.eyes or 1.1 -- (about the model's own: "the eyes are too big in the sprites")
	local PITCH = env.pitch or 15
	-- each body plan's eyes (the golem keeps its glowing slits): sx, sy their size; iris a colour (none: the model's
	-- dark eye) taken from the species' accent when useAccent and it shows; pupil "dot", "slit" or "bar"; shine false
	-- for none; glow for a lit eye
	local EYE_STYLE = {
		blob = { sx = 0.85, sy = 0.5, shine = false }, -- a stone's squint
		crab = { sx = 0.85, sy = 0.85 }, -- beads on stalks
		snail = { sx = 0.85, sy = 0.85 },
		bird = { sx = 0.85, sy = 0.85 }, -- bright beads
		bun = { sx = 0.95, sy = 1.1 },
		pup = { sx = 0.95, sy = 1.05 },
		seal = { sx = 0.9, sy = 0.9 }, -- round and glossy
		jelly = { sx = 0.9, sy = 0.9 },
		turtle = { sx = 0.85, sy = 0.7 }, -- small and wise
		mole = { sx = 0.85, sy = 0.45, shine = false }, -- squinting at the light
		-- (an iris with a pupil needs room to show both: these eyes are a little bigger than the plain dark ones)
		lizard = { iris = "yellow", alt = "orange", pupil = "slit", useAccent = true, sx = 1.3, sy = 1.15, shine = false },
		wyrm = { iris = "yellow", alt = "orange", pupil = "slit", useAccent = true, sx = 1.35, sy = 1.05, shine = false },
		drake = { iris = "yellow", alt = "orange", pupil = "slit", useAccent = true, sx = 1.3, sy = 1.0, shine = false },
		owl = { iris = "orange", alt = "yellow", pupil = "dot", useAccent = true, sx = 1.35, sy = 1.2 },
		yeti = { iris = "blue", alt = "screen_on", pupil = "dot", useAccent = true, sx = 0.95, sy = 0.95, shine = false },
		frog = { iris = "yellow", alt = "orange", pupil = "bar", useAccent = true, sx = 1.05, sy = 1.0 },
		bat = { iris = "berry_red", alt = "orange", useAccent = true, sx = 1.0, sy = 1.0 }, -- red
		moth = { iris = "berry_red", alt = "purple", useAccent = true, sx = 1.15, sy = 1.2 }, -- one colour, no pupil
		sprite = { iris = "screen_on", alt = "white", useAccent = true, glow = true, sx = 0.9 },
	}
	-- accents too dull or pale to read as an eye's colour
	local DULL = { white = true, cream = true, sand = true, sand_dark = true, wood = true, wood_dark = true, leaf_dark = true, steel = true, steel_dark = true, rock = true, rock_dark = true, black = true, night = true, chalk = true, window = true, shallow = true, green = true }
	local function far(a: string, b: string): boolean
		local ca, cb = Blocks.color(a), Blocks.color(b)
		local dr, dg, db = (ca.R - cb.R) * 255, (ca.G - cb.G) * 255, (ca.B - cb.B) * 255
		return dr * dr + dg * dg + db * db > 120 * 120
	end
	local function portraitPose(t, shape, body, accent)
		local rig = t.rig
		if rig == nil then
			return
		end
		local inHead = {}
		for _, name in rig.order do
			local j = rig.joints[name]
			if name == "head" or (j.parent and inHead[j.parent]) then
				inHead[name] = true
			end
		end
		local hj = rig.joints.head
		local hw = rig.world.head
		if hj and hw then
			local pivot = hw * hj.pivot
			for name, p in t.parts do
				if inHead[rig.of[name] or "body"] then
					local r = t.rest[name]
					t.rest[name] = CFrame.new(pivot + (r.Position - pivot) * HEAD) * r.Rotation
					p.Size = p.Size * HEAD
				end
			end
		end
		-- the eyes in their body plan's style ("the eyes all look the same"): their size and shape, an iris in the
		-- species' accent (or the plan's own colour when the accent is too dull or too near the body) with a dot, slit
		-- or bar pupil, a glow, a glint or none
		local st = EYE_STYLE[shape] or {}
		local iris: string? = st.iris
		if iris and st.useAccent and not DULL[accent] and far(accent, body) then
			iris = accent
		end
		if iris and not far(iris, body) then
			iris = st.alt or "white"
		end
		for _, side in { "L", "R" } do
			local e = t.parts["Eye" .. side]
			if e and shape ~= "golem" then
				local rest = t.rest["Eye" .. side]
				local c = rest.Position
				local sx, sy = (st.sx or 1) * EYES, (st.sy or 1) * EYES
				e.Size = Vector3.new(e.Size.X * sx, e.Size.Y * sy, e.Size.Z)
				if iris then
					e.Color = Blocks.color(iris)
					if st.glow then
						e.Material = Enum.Material.Neon
					end
					if st.pupil then
						local pw, ph = 0.45, 0.45
						if st.pupil == "slit" then
							pw, ph = 0.3, 0.9
						elseif st.pupil == "bar" then
							pw, ph = 0.8, 0.3
						end
						local pupil = Blocks.part(t.model, { size = Vector3.new(math.max(0.06, e.Size.X * pw), math.max(0.06, e.Size.Y * ph), 0.08), cf = CFrame.new(), color = "black", name = "Pupil" .. side, collide = false, query = false })
						t.parts["Pupil" .. side] = pupil
						t.rest["Pupil" .. side] = rest * CFrame.new(0, -e.Size.Y * 0.05, 0.05)
					end
				end
				-- (the glint stays small and glows white, moved with the eye's edge; none on a squint or a glow)
				local sh = t.parts["Shine" .. side]
				if sh then
					if st.shine == false or st.glow then
						sh:Destroy()
						t.parts["Shine" .. side] = nil
					else
						local r = t.rest["Shine" .. side]
						local off = r.Position - c
						t.rest["Shine" .. side] = CFrame.new(c + Vector3.new(off.X * sx, off.Y * sy, off.Z)) * r.Rotation
						sh.Material = Enum.Material.Neon
					end
				end
			end
		end
	end
	local list = env.species or Creatures.list
	local jobs = {}
	H.inClient(p, function()
		for _, d in list do
			local def = if type(d) == "string" then Creatures.byId[d] else d
			for _, yaw in env.yaws or { YAW } do
				local name = if env.yaws then def.id .. "@" .. yaw else def.id
				local snap = Snapshot.get("portrait:" .. name, function()
					local t = MM.species(def.id)
					MM.animate(t, REST, "rest", 0)
					portraitPose(t, def.shape, def.body, def.accent)
					MM.place(t, CFrame.new())
					return t.model
				end, { size = SIZE, yaw = yaw, pitch = PITCH, pad = 1, outline = "outer", shadows = true, keep = true })
				table.insert(jobs, { name = name, snap = snap })
			end
		end
	end)
	local t = 0
	while t < 900 and Snapshot.pending() > 0 do
		E.step(E.dt)
		t += E.dt
	end
	log("pportraits: %d pictures drawn in %.1f s (simulated)", #jobs, t)
	local bad = 0
	for _, j in jobs do
		local snap = j.snap
		if snap == nil or not snap.ready or snap.image == nil then
			bad += 1
			log("pportraits: %s was not drawn", j.name)
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
		print(string.format("@@PORT %s %d %d %s", j.name, snap.w, snap.h, table.concat(out)))
	end
	log("pportraits: %d portraits, %d not drawn", #jobs, bad)
	-- a look at them, raw: on the panels' plate colour at 3x
	H.inClient(p, function()
		local g = Instance.new("ScreenGui")
		g.Name = "PortraitSheet"
		g.DisplayOrder = 5000
		g.IgnoreGuiInset = true
		g.ScreenInsets = Enum.ScreenInsets.None
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(84, 58, 44)
		bg.BorderSizePixel = 0
		bg.Parent = g
		local canvas = Instance.new("Frame")
		canvas.BackgroundTransparency = 1
		canvas.Size = UDim2.fromScale(1, 1)
		canvas.Parent = g
		local sc = Instance.new("UIScale")
		sc.Scale = 3
		sc.Parent = canvas
		local x, y = 2, 2
		for _, j in jobs do
			if j.snap then
				local im = Snapshot.label(j.snap, canvas, true)
				im.Position = UDim2.fromOffset(x, y)
				x += SIZE + 3
				if x + SIZE > 630 then
					x, y = 2, y + SIZE + 3
				end
			end
		end
		g.Parent = p:FindFirstChildOfClass("PlayerGui")
	end)
	E.run(0.2)
	capture(p, "pportraits_sheet")
	return p
end
