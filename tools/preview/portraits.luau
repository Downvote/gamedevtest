-- The driftlings' portraits (GAME_DESIGN 2: "instead of character sprites for the creatures, can you take their
-- pixellated models in a 3/4 angle, and polish them to follow pixel art rules if required?"), drawn ahead of time for
-- the preview scenario "pportraits" (tools/README.md) through the game's own picture path (Pixel/Snapshot: the
-- world's palette, toon bands, sun shadows and the 1 px ink outline): each driftling's model (Models/DriftModels via
-- MicroModels.driftling) standing at rest, eyes open, turned three quarters to the left, fitted to SIZE x SIZE art px.
-- tools/preview/gen_portraits.py tidies them to the pixel art rules and writes scripts/portraits.txt, which
-- scripts/gen_art.py turns into the "icon_<species>" sprites (sh tools/preview/portraits.sh does all three).
-- Output (the scenario's log): per driftling `@@PORT <species> <w> <h> <RGBA hex>`. With `env.yaws` (a list of
-- degrees) every driftling is drawn at each, for choosing the angle (`@@PORT <species>@<yaw> ...`).
return function(env)
	local E, H, log, capture = env.E, env.H, env.log, env.capture
	local Instance, Enum, UDim2, Color3 = E.Instance, E.Enum, E.types.UDim2, E.types.Color3
	local Vector2, CFrame = E.types.Vector2, E.types.CFrame
	local p = env.join(7302, "Painter")
	env.settle(p, 30, 1)
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	local MM = env.cshared(p, "Models.MicroModels")
	local Creatures = env.cshared(p, "Data.Creatures")
	if Snapshot == nil then
		log("pportraits: this tree has no Pixel/Snapshot")
		return p
	end
	local SIZE = env.size or 24
	-- (turned 20 degrees from the world's own view, its face toward +Z: three quarters, turned left, the face toward us
	-- and the body's side showing; chosen from -20, 0, 20 and 40 with the scenario "pportraits_try")
	local YAW = env.yaw or 20
	local REST = 2.3 -- (seconds into the idle loop: eyes open, the body at the middle of its breath)
	local list = env.species or Creatures.list
	local jobs = {}
	H.inClient(p, function()
		for _, d in list do
			local def = if type(d) == "string" then Creatures.byId[d] else d
			for _, yaw in env.yaws or { YAW } do
				local name = if env.yaws then def.id .. "@" .. yaw else def.id
				local snap = Snapshot.get("portrait:" .. name, function()
					local t = MM.driftling(def.shape, def.body, def.accent)
					MM.animate(t, REST, "idle", 0)
					MM.place(t, CFrame.new())
					return t.model
				end, { size = SIZE, yaw = yaw, pad = 1, outline = "outer", shadows = true, keep = true })
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
