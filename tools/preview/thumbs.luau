-- The build catalog's pictures, drawn ahead of time for the preview scenario "pthumbs" (tools/README.md) through the
-- game's own picture path (Pixel/Snapshot: the world's palette, toon bands, sun shadows and the 1 px ink outline):
-- every piece in Data/Buildings but the Tree of Life, built by Models/DecorModels at lvl 1, seen from the world's camera
-- (Tuning.CamYaw and CamPitch: three quarters from the south-east, as the island shows it) and fitted to SIZE x SIZE art
-- px with 1 px kept for the outline, so a tall narrow piece and a wide flat one both fill the square.
-- Some pieces don't read alone, so the picture is a little scene:
--   a path or water tile: a 2 x 2 block of four tiles (the water's banks round the block, each tile's lvl from its
--     neighbours the way PlotService.waterMasks gives it in the world);
--   a fence length: a corner, one length running east and one running south from the same post (rot 0 and rot 90);
--   a piece that stands over water (a bridge, the dock, the waterwheel): a stream two tiles wide under its middle, at
--     right angles to its long side;
--   a piece that floats (lily pads, the rowboat): a pond a stud wider all round (in whole tiles).
-- tools/preview/gen_thumbs.py tidies them to the pixel art rules into scripts/thumbs.txt, which scripts/gen_art.py turns
-- into the "thumb_<id>" sprites of UI/ThumbData (sh tools/preview/thumbs.sh does all three).
-- Output (the scenario's log): per piece and canvas size `@@THUMB <id>@<size> <w> <h> <RGBA hex>`.
-- env.only: the ids to draw (all when nil); env.part / env.parts: draw every parts-th piece from the part-th (thumbs.sh
-- splits the catalog over a few runs that go in parallel).
return function(env)
	local E, H, log = env.E, env.H, env.log
	local Instance, Vector2, CFrame = E.Instance, E.types.Vector2, E.types.CFrame
	local p = env.join(7303, "Builder")
	local Snapshot = env.modOr(p, "Pixel.Snapshot")
	if Snapshot == nil then
		log("pthumbs: this tree has no Pixel/Snapshot")
		return p
	end
	local Buildings = env.cshared(p, "Data.Buildings")
	local DecorModels = env.cshared(p, "Models.DecorModels")
	local Plot = env.cshared(p, "Logic.Plot")
	local Street = env.cshared(p, "Data.Street")
	local PlotService = H.smod("PlotService")
	local SIZE = env.size or 24
	-- each piece is drawn on a few canvases a pixel apart, each at its own scale (the renderer fits the parts' boxes to
	-- the canvas, and a roof's wedges or a diamond's tips come out a pixel short of them): gen_thumbs.py keeps the
	-- biggest drawing that still fits SIZE x SIZE. Nothing is ever scaled.
	local SIZES = { SIZE, SIZE + 1, SIZE + 2, SIZE + 3, SIZE + 4 }
	local WATER = "stream" -- (the plain water tile, under the pieces that need water)
	-- the parts DecorModels' `pennant` adds to a piece of lvl 2 and 3 (its pole, knob and flags, and the lamp)
	local UPGRADE = { PennantPole = true, Knob = true, Flag = true, LampPost = true, LampLight = true, LampCap = true }

	-- the pieces: { id, x, z, rot, lvl? } with x, z the footprint's corner as a placed piece's (Types.Piece)
	local function scene(d): { { any } }
		local list = {}
		local function put(id: string, x: number, z: number, rot: number?)
			table.insert(list, { id, x, z, rot or 0 })
		end
		-- water tiles over a w x d stud area centred on the origin (whole tiles)
		local function pond(w: number, dd: number)
			local nx, nz = math.ceil(w / 2), math.ceil(dd / 2)
			for tz = 0, nz - 1 do
				for tx = 0, nx - 1 do
					put(WATER, -nx + tx * 2, -nz + tz * 2)
				end
			end
		end
		if d.kind == "path" or d.kind == "water" then
			for k = 0, 3 do
				put(d.id, -2 + (k % 2) * 2, -2 + (k // 2) * 2)
			end
		elseif d.kind == "fence" then
			put(d.id, 0, 0, 0)
			put(d.id, 0, 0, 90)
		elseif d.water == "on" then
			pond(d.w + 2, d.d + 2)
			put(d.id, -d.w / 2, -d.d / 2)
		elseif d.water == "over" then
			-- the stream runs under the piece's middle at right angles to its long side, a stud of water showing past
			-- each of its edges
			if d.d >= d.w then
				pond(d.w + 2, 4)
			else
				pond(4, d.d + 2)
			end
			put(d.id, -d.w / 2, -d.d / 2)
		else
			put(d.id, -d.w / 2, -d.d / 2)
		end
		-- each water tile's lvl: 1 + the mask of its water neighbours (the world's own rule)
		local masks = PlotService.waterMasks((function()
			local placed = {}
			for _, q in list do
				table.insert(placed, { id = q[1], x = q[2], z = q[3], rot = q[4] })
			end
			return placed
		end)())
		for _, q in list do
			if Plot.isWater(q[1]) then
				q[5] = masks[Street.cellKey(q[2], q[3])] or 1
			end
		end
		return list
	end

	local only: { [string]: boolean }? = nil
	if env.only then
		only = {}
		for _, id in env.only do
			(only :: any)[id] = true
		end
	end
	local defs = {}
	local n = 0
	for _, d in Buildings.list do
		if d.kind == "tree" or (only and not only[d.id]) then
			continue
		end
		n += 1
		if env.parts and (n - 1) % env.parts ~= (env.part or 1) - 1 then
			continue
		end
		table.insert(defs, d)
	end

	-- the scene's model (built afresh for each picture: Snapshot destroys what its source returns)
	local function build(d, pieces): Instance
		local root = Instance.new("Model")
		root.Name = "Thumb_" .. d.id
		for _, q in pieces do
			local w, dd = Plot.footprint(q[1], q[4])
			local at = CFrame.new(q[2] + w / 2, 0, q[3] + dd / 2) * CFrame.Angles(0, math.rad(q[4]), 0)
			local m = DecorModels.build(q[1], at, q[5] or 1)
			if (q[5] or 1) >= 2 and Plot.isWater(q[1]) then
				-- (DecorModels.build flies an upgraded building's pennant, and at lvl 3 hangs its lamp, on any piece of
				-- lvl 2 or more, a water tile's neighbour mask too: never on a tile's picture)
				for _, c in m:GetDescendants() do
					if UPGRADE[c.Name] then
						c:Destroy()
					end
				end
			end
			m.Parent = root
		end
		return root
	end

	local jobs = {}
	H.inClient(p, function()
		Snapshot.setBudget(1000) -- (nothing else to draw: as much a frame as it takes)
		for _, d in defs do
			local pieces = scene(d)
			for _, size in SIZES do
				local snap = Snapshot.get("thumb:" .. d.id .. ":" .. size, function()
					return build(d, pieces)
				end, { size = size, pad = 1, outline = "outer", shadows = true, keep = true })
				table.insert(jobs, { id = d.id .. "@" .. size, snap = snap })
			end
		end
	end)
	local t = 0
	while t < 900 and Snapshot.pending() > 0 do
		E.step(E.dt)
		t += E.dt
	end
	log("pthumbs: %d pictures drawn in %.1f s (simulated)", #jobs, t)
	local bad = 0
	for _, j in jobs do
		local snap = j.snap
		if snap == nil or not snap.ready or snap.image == nil then
			bad += 1
			log("pthumbs: %s was not drawn", j.id)
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
	log("pthumbs: %d pictures, %d not drawn", #jobs, bad)
	return p
end
