-- The game passes' and developer products' icons, part 1: the game's own models drawn through its picture path
-- (Pixel/Snapshot: the world's palette, toon bands, sun shadows and the 1 px outline) for the preview scenario
-- "picons" (tools/README.md), each the subject of one or more icons (tools/preview/product_icons.py lays them on their
-- badges with the overlays and scales them up: sh tools/preview/product_icons.sh does both).
-- Output (the scenario's log): per subject `@@ICON <id> <w> <h> <RGBA hex>`.
return function(env)
	local E, H, log = env.E, env.H, env.log
	local Instance, Vector2, CFrame = E.Instance, E.types.Vector2, E.types.CFrame
	local p = env.join(7305, "Iconist")
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	-- (flat ink: the tidying finds the outline and the creases by the ink's colour, then gives each its darker step)
	local ShadingMod = env.cshared(p, "Render.Shading")
	if ShadingMod and ShadingMod.setFlatInk then
		ShadingMod.setFlatInk(true)
	end
	if Snapshot == nil then
		log("picons: this tree has no Pixel/Snapshot")
		return p
	end
	local EggModels = env.cshared(p, "Models.EggModels")
	local DecorModels = env.cshared(p, "Models.DecorModels")
	local WearModels = env.cshared(p, "Models.WearModels")
	local CharacterModels = env.cshared(p, "Models.CharacterModels")
	local Blocks = env.cshared(p, "Models.Blocks")
	local Plot = env.cshared(p, "Logic.Plot")

	local function egg(root: Instance, r: number, at: CFrame, bare: boolean?)
		local m = EggModels.build(r, bare)
		m:PivotTo(at)
		m.Parent = root
	end
	local function decor(root: Instance, id: string, x: number, z: number, rot: number?)
		local w, d = Plot.footprint(id, rot or 0)
		local m = DecorModels.build(id, CFrame.new(x + w / 2, 0, z + d / 2) * CFrame.Angles(0, math.rad(rot or 0), 0), 1)
		m.Parent = root
	end
	local function wear(root: Instance, id: string)
		local turn = CFrame.Angles(0, math.rad(25), 0)
		for _, sp in WearModels.piece(id) do
			local cf = turn * CFrame.new(sp.at) * (sp.rot or CFrame.new())
			local part = Blocks.part(root, { size = sp.size, cf = cf, color = sp.color, shape = sp.shape, collide = false, query = false, neon = sp.neon })
			part.Size = sp.size
		end
	end

	-- each subject: its picture's size (art px) and how its model is put together
	local SUBJECTS = {
		{ id = "egg2", size = 48, make = function(root) egg(root, 2, CFrame.new()) end },
		{ id = "egg3", size = 48, make = function(root) egg(root, 3, CFrame.new()) end },
		{ id = "egg4", size = 48, make = function(root) egg(root, 4, CFrame.new()) end },
		{ id = "egg5", size = 48, make = function(root) egg(root, 5, CFrame.new()) end },
		{ id = "egg6", size = 48, make = function(root) egg(root, 6, CFrame.new()) end },
		{ id = "egg7", size = 48, make = function(root) egg(root, 7, CFrame.new()) end },
		-- a lot of eggs: three bare ones side by side
		{ id = "eggs3", size = 46, make = function(root)
			egg(root, 3, CFrame.new(-1.15, 0, 0.35), true)
			egg(root, 5, CFrame.new(0, 0, -0.3), true)
			egg(root, 4, CFrame.new(1.15, 0, 0.35), true)
		end },
		-- the starter pack: an epic and a legendary egg on a pile of shells
		{ id = "starter", size = 46, make = function(root)
			decor(root, "shellpile", -1, -1)
			egg(root, 4, CFrame.new(-0.55, 0.35, 0.2), true)
			egg(root, 5, CFrame.new(0.6, 0.35, -0.15), true)
		end },
		{ id = "crown", size = 44, pitch = 14, make = function(root) wear(root, "crown_gold") end },
		{ id = "tree", size = 48, make = function(root) decor(root, "tree", -4, -4) end },
		{ id = "hatchery", size = 44, make = function(root) decor(root, "hatchery", -2, -2) end },
		{ id = "stall", size = 42, make = function(root) decor(root, "stall", -1.5, -1) end },
		{ id = "fountain", size = 44, make = function(root) decor(root, "fountain", -2.5, -2.5) end },
		-- a founder dozing on its feet (the Offline Pass: the island earns while they sleep)
		{ id = "sleeper", size = 42, pitch = 12, make = function(root)
			local rig = CharacterModels.buildStanding({ skin = 2, hair = 1, style = 1, shirt = 9 }, "Sleeper", 1)
			CharacterModels.posePose(rig, CFrame.Angles(0, math.rad(20), 0), {
				mood = "sleep",
				head = CFrame.Angles(math.rad(14), 0, math.rad(10)),
				lean = math.rad(4),
				armL = CFrame.Angles(0, 0, math.rad(-6)),
				armR = CFrame.Angles(0, 0, math.rad(6)),
			})
			for _, c in rig.model:GetChildren() do
				c.Parent = root
			end
			rig.model:Destroy()
		end },
	}

	local only = nil
	if env.only then
		only = {}
		for _, id in env.only do
			only[id] = true
		end
	end
	local jobs = {}
	H.inClient(p, function()
		Snapshot.setBudget(1000)
		for _, s in SUBJECTS do
			if only and not only[s.id] then
				continue
			end
			local snap = Snapshot.get("icon:" .. s.id, function()
				local root = Instance.new("Model")
				root.Name = "Icon_" .. s.id
				s.make(root)
				return root
			end, { size = s.size, pad = 1, outline = "outer", shadows = true, keep = true, pitch = s.pitch, yaw = s.yaw })
			table.insert(jobs, { id = s.id, snap = snap })
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
			log("picons: %s was not drawn", j.id)
			continue
		end
		local buf
		H.inClient(p, function()
			buf = snap.image:ReadPixelsBuffer(Vector2.zero, Vector2.new(snap.w, snap.h))
		end)
		local count = snap.w * snap.h
		local out = table.create(count)
		for i = 0, count - 1 do
			out[i + 1] = string.format("%08x", buffer.readu32(buf, i * 4))
		end
		print(string.format("@@ICON %s %d %d %s", j.id, snap.w, snap.h, table.concat(out)))
	end
	log("picons: %d pictures, %d not drawn", #jobs, bad)
	return p
end
