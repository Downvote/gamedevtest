-- The cosmetics' pictures (GAME_DESIGN 14.1), drawn ahead of time for the preview scenario "cthumbs" (tools/README.md)
-- through the game's own picture path (Pixel/Snapshot: the world's palette, toon bands, sun shadows and the 1 px ink
-- outline), the way the build catalog's are (tools/preview/thumbs.luau): every piece in Data/Cosmetics built from its
-- parts (Models/CosmeticModels) alone, seen from the world's camera and fitted to SIZE x SIZE art px with 1 px kept for
-- the outline. A top is drawn on a little body (the torso, the sleeves and the belt in the top's colours: a shirt's
-- overlays alone would float); everything else is drawn by itself.
-- tools/preview/gen_thumbs.py tidies them to the pixel art rules into scripts/cosmetic_thumbs.txt, which
-- scripts/gen_art.py turns into the "look_<id>" sprites of UI/CosmeticThumbData (sh tools/preview/cosmetic_thumbs.sh
-- does all three).
-- Output (the scenario's log): per piece and canvas size `@@THUMB <id>@<size> <w> <h> <RGBA hex>`.
-- env.only: the ids to draw (all when nil); env.part / env.parts: draw every parts-th piece from the part-th.
return function(env)
	local E, H, log = env.E, env.H, env.log
	local Instance, Vector2, CFrame = E.Instance, E.types.Vector2, E.types.CFrame
	local Vector3 = E.types.Vector3
	local p = env.join(7304, "Tailor")
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	if Snapshot == nil then
		log("cthumbs: this tree has no Pixel/Snapshot")
		return p
	end
	local Cosmetics = env.cshared(p, "Data.Cosmetics")
	local CosmeticModels = env.cshared(p, "Models.CosmeticModels")
	local Blocks = env.cshared(p, "Models.Blocks")
	local SIZE = env.size or 24
	local SIZES = { SIZE, SIZE + 1, SIZE + 2, SIZE + 3, SIZE + 4 }

	local only = nil
	if env.only then
		only = {}
		for _, id in env.only do
			only[id] = true
		end
	end
	local defs = {}
	local n = 0
	for _, c in Cosmetics.list do
		if only and not only[c.id] then
			continue
		end
		n += 1
		if env.parts and (n - 1) % env.parts ~= (env.part or 1) - 1 then
			continue
		end
		table.insert(defs, c)
	end

	-- the piece's model (built afresh for each picture: Snapshot destroys what its source returns), turned to show the
	-- camera its front three quarters on (a back piece its back: the side the world sees of it), and a part thinner than
	-- a sixteenth of the piece's height or width made that thick (a stick a pixel wide at this size would vanish)
	local function build(c): Instance
		local root = Instance.new("Model")
		root.Name = "Look_" .. c.id
		local turn = CFrame.Angles(0, math.rad(if c.slot == "back" then 205 else 25), 0)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, sp in CosmeticModels.parts(c.id) do
			lo = Vector3.new(math.min(lo.X, sp.at.X - sp.size.X / 2), math.min(lo.Y, sp.at.Y - sp.size.Y / 2), math.min(lo.Z, sp.at.Z - sp.size.Z / 2))
			hi = Vector3.new(math.max(hi.X, sp.at.X + sp.size.X / 2), math.max(hi.Y, sp.at.Y + sp.size.Y / 2), math.max(hi.Z, sp.at.Z + sp.size.Z / 2))
		end
		local span = hi - lo
		local least = math.max(span.X, span.Y, span.Z, 1) / 16
		local function put(size, at, color, shape, rot, neon)
			local cf = turn * CFrame.new(at) * (rot or CFrame.new())
			local sz = Vector3.new(math.max(size.X, least), math.max(size.Y, least), math.max(size.Z, least))
			local part = Blocks.part(root, { size = sz, cf = cf, color = color, shape = shape, collide = false, query = false, neon = neon })
			part.Size = sz
		end
		local top = CosmeticModels.top(c.id)
		if c.slot == "top" then
			local shirt = (top and top.torso) or "blue"
			local arms = (top and top.arms) or shirt
			put(Vector3.new(1.25, 1.25, 0.75), Vector3.new(0, 1.875, 0), shirt)
			put(Vector3.new(0.375, 0.5, 0.375), Vector3.new(-0.8125, 2.2, 0), arms)
			put(Vector3.new(0.375, 0.5, 0.375), Vector3.new(0.8125, 2.2, 0), arms)
			local hide = {}
			for _, h in (top and top.hide) or {} do
				hide[h] = true
			end
			if not hide.Belt then
				put(Vector3.new(1.375, 0.125, 0.875), Vector3.new(0, 1.3125, 0), "wood_dark")
			end
		end
		for _, sp in CosmeticModels.parts(c.id) do
			put(sp.size, sp.at, sp.color, sp.shape, sp.rot, sp.neon)
		end
		return root
	end

	local jobs = {}
	H.inClient(p, function()
		Snapshot.setBudget(1000)
		for _, c in defs do
			for _, size in SIZES do
				local snap = Snapshot.get("look:" .. c.id .. ":" .. size, function()
					return build(c)
				end, { size = size, pad = 1, outline = "outer", shadows = true, keep = true })
				table.insert(jobs, { id = c.id .. "@" .. size, snap = snap })
			end
		end
	end)
	local t = 0
	while t < 900 and Snapshot.pending() > 0 do
		E.step(E.dt)
		t += E.dt
	end
	log("cthumbs: %d pictures drawn in %.1f s (simulated)", #jobs, t)
	local bad = 0
	for _, j in jobs do
		local snap = j.snap
		if snap == nil or not snap.ready or snap.image == nil then
			bad += 1
			log("cthumbs: %s was not drawn", j.id)
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
		print(string.format("@@THUMB %s %d %d %s", j.id, snap.w, snap.h, table.concat(out)))
	end
	log("cthumbs: %d pictures, %d not drawn", #jobs, bad)
	return p
end
