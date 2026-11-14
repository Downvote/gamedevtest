--!strict
--!native
-- The island growing into its next tier on the pixel layer (GAME_DESIGN 4; docs/ARCHITECTURE.md 9.3). The request
-- (2026-11-14): "expanding the island dosent have a good transition, it simply make the new land appear out of nowhere.
-- could you make a transition such that it feels like the island grows out the new land smoothly?"
--
-- The server swaps the bigger island in at once and the renderer bakes it behind the old picture (PixelRenderer). When
-- that bake is done, the renderer hands this module both pictures instead of showing the new one. The coast then moves
-- out from its old line to its new one over Tuning.GrowSecs: at progress e a spot's coast distance is the two tiers'
-- mixed, (1 - e) * old + e * new (Data/Street's distances), so the whole shore moves out together and reaches the new
-- one everywhere at the same moment, and with it the whole shore's profile: the grass's edge, the sand, the wet sand,
-- the foam and the shallows (Street.BANDS). Each pixel where the pictures differ shows what that profile says is there
-- now: the new picture where its layer is the one the moving coast puts there, else the old picture where its layer is,
-- the nearer of the two when both are; where neither has it (the moving beach crossing what was sea and will be grass),
-- the layer's own palette colour, shaded as a flat piece of ground there and lit as it is (the foam and the shallows
-- with the sea's own waves), so a beach rides out with the shore. Things standing on the old shore go whole (each part
-- at once) when the moving shore turns the ground under them into the next layer; the new shore's palms, rocks and
-- shells come whole near the end (NEW_THINGS); things scattered anew where the coast barely moves (a palm, a shell, the
-- sign) change halfway; whatever still differs over the last few hundredths turns in an ordered dither (SETTLE). No rays: the pictures' depths give each pixel's world point, the coast distances come from the tiers'
-- worked-out cells (Street.cellDist, between cell centres), worked out over the first few frames (`prep`) while the old
-- picture shows; then each frame only the pixels a band reaches change (each waits in the bucket of its next change).
--   Grow.begin(spec) -> State      (the old picture back on the layer, the new one kept)
--   Grow.prep(state) -> ready      (a slice of the pixels' working out; true when the coast may start)
--   Grow.step(state, e) -> (changed, front)   e: 0 .. 1 eased progress; front: world points the foam reached (spray)
--   Grow.shift(state, dx, dy), Grow.adopt(state, x0, y0, x1, y1), Grow.finish(state), Grow.stats(state)
local Street = require(game:GetService("ReplicatedStorage").Shared.Data.Street)

local Grow = {}

-- The layer's buffers (PixelRenderer's Surf, the fields this module reads and writes).
export type Bufs = {
	sColor: buffer,
	sShade: buffer,
	sShadowC: buffer,
	sAlbedo: buffer,
	sNormal: buffer,
	sLit: buffer,
	sDepth: buffer,
	sId: buffer,
	sShare: buffer,
	sWClass: buffer,
	sWave: buffer,
}

export type Spec = {
	live: Bufs, -- the layer (holding the new picture when begin is called)
	old: Bufs, -- the old picture's buffers (same size; Grow keeps them)
	W: number,
	H: number,
	-- the world point of pixel (i, j) at depth d: origin(i, j) + look * d (the layer's camera as it is now)
	origin: (i: number, j: number) -> (number, number, number),
	look: Vector3,
	far: number, -- a depth at or past this is the sky
	plot: Vector3, -- the plot's origin (Data/Street's plot-local coordinates)
	from: number, -- the tier it grows from and into
	to: number,
	remap: (oldId: number) -> number, -- an old picture's part id into the layer's id tables now
	-- the moving beach: each layer's albedo (0xRRGGBB, Data/Palette) and a part id standing for it (its colour and
	-- water class in the layer's id tables), by layer (2 sand, 3 wet sand, 4 foam, 5 shallows)
	tints: { [number]: number },
	synthId: (layer: number) -> number,
	up: number, -- the up-facing normal's index (Shading.normalIndex)
	-- an albedo shaded as the layer's pixel p is now (its normal, its sun or shade, its place on the art grid): a
	-- palette colour, never a blend
	toon: (rgb: number, p: number) -> number,
	-- the sea's wave phase at a world point (PixelRenderer's, as its bake works it out)
	wave: (wx: number, wz: number) -> number,
}

export type State = {
	spec: Spec,
	n: number,
	phase: string, -- "prep" (working the pixels out, the old picture showing) | "grow" | "done"
	row: number, -- prep's next row
	-- the new picture, kept while the profile decides what shows
	nColor: buffer,
	nShade: buffer,
	nAlbedo: buffer,
	nNormal: buffer,
	nLit: buffer,
	nDepth: buffer,
	nId: buffer,
	nShare: buffer,
	nWClass: buffer,
	nWave: buffer,
	oId: buffer, -- the old picture's ids, remapped into the layer's tables
	-- per pixel: the old and new coast distances at the new picture's point (dOn, dNn) and the old one's (dOo, dNo)
	dOn: buffer,
	dNn: buffer,
	dOo: buffer,
	dNo: buffer,
	flags: buffer, -- u8: CHANGED, NEW_OBJ, OLD_OBJ, NEW_SKY, OLD_SKY, STILL, ADOPTED
	tOld: buffer, -- f32: when an old thing's pixel goes (its part's soonest: a palm's leaf goes whole)
	idGone: { [number]: number }, -- an old part (its remapped id) -> when it goes
	state: buffer, -- u8: what the pixel shows (SHOW_NEW, SHOW_OLD, or SYNTH + layer)
	all: { number }, -- every pixel that differs
	buckets: { { number } }, -- pixels by their next change
	next: number,
	e: number, -- the progress so far
	frontN: number,
	changed: number,
}

local BUCKETS = 240
local PREP_PX = 26000 -- pixels worked out a frame while prepping
local CHANGED, NEW_OBJ, OLD_OBJ, NEW_SKY, OLD_SKY, STILL, ADOPTED = 1, 2, 4, 8, 16, 32, 64
local SHOW_NEW, SHOW_OLD, SYNTH = 1, 2, 10
local GRASS, SAND, WET, FOAM, SHALLOW, SEA = 1, 2, 3, 4, 5, 6
local BANDS = Street.BANDS
local THRESH = { BANDS.shallow, BANDS.foam, BANDS.wet, BANDS.sand, 0 }
local OBJ_Y = Street.LAWN_Y + 0.12 -- a point higher than this stands on the ground (a palm, a rock, a sign)
local FAR_D = 99 -- a cell past the tier's worked-out cells: open sea
local NEW_THINGS = 0.9 -- the progress the new shore's palms, rocks and shells come at (whole, together)
local SETTLE = 0.93 -- from here every pixel still not showing the new picture turns, in a 4 x 4 ordered dither
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }

-- When pixel p turns at the latest (the settle's dither: whole pixels, never a blend).
local function settleAt(st: State, p: number): number
	local W = st.spec.W
	return SETTLE + (1 - SETTLE) * BAYER[(p % W) % 4 + ((p // W) % 4) * 4 + 1] / 16
end

-- the coast distance under which each layer ends (the next one down begins)
local FOOT = { -math.huge, 0, BANDS.sand, BANDS.wet, BANDS.foam, BANDS.shallow }

local function layerOf(d: number): number
	if d <= 0 then
		return GRASS
	elseif d <= BANDS.sand then
		return SAND
	elseif d <= BANDS.wet then
		return WET
	elseif d <= BANDS.foam then
		return FOAM
	elseif d <= BANDS.shallow then
		return SHALLOW
	end
	return SEA
end

-- A tier's coast distance at a plot-local point, between its cells' centres (smooth enough for a moving shore).
local function distAt(tier: number, x: number, z: number): number
	local fx, fz = x - 0.5, z - 0.5
	local cx, cz = math.floor(fx), math.floor(fz)
	local tx, tz = fx - cx, fz - cz
	local function at(a: number, b: number): number
		local d = Street.cellDist(tier, a, b)
		return if d > FAR_D then FAR_D else d
	end
	local d00, d10, d01, d11 = at(cx, cz), at(cx + 1, cz), at(cx, cz + 1), at(cx + 1, cz + 1)
	return (d00 * (1 - tx) + d10 * tx) * (1 - tz) + (d01 * (1 - tx) + d11 * tx) * tz
end

------------------------------------------------------------------ writing a pixel
local function putNew(st: State, p: number)
	local L = st.spec.live
	buffer.writeu32(L.sColor, p * 4, buffer.readu32(st.nColor, p * 4))
	buffer.writeu32(L.sShade, p * 4, buffer.readu32(st.nShade, p * 4))
	buffer.writeu32(L.sAlbedo, p * 4, buffer.readu32(st.nAlbedo, p * 4))
	buffer.writeu32(L.sShadowC, p * 4, 0)
	buffer.writeu8(L.sNormal, p, buffer.readu8(st.nNormal, p))
	buffer.writeu8(L.sLit, p, buffer.readu8(st.nLit, p))
	buffer.writef32(L.sDepth, p * 4, buffer.readf32(st.nDepth, p * 4))
	buffer.writeu16(L.sId, p * 2, buffer.readu16(st.nId, p * 2))
	buffer.writeu8(L.sShare, p, buffer.readu8(st.nShare, p))
	buffer.writeu8(L.sWClass, p, buffer.readu8(st.nWClass, p))
	buffer.writeu8(L.sWave, p, buffer.readu8(st.nWave, p))
end

local function putOld(st: State, p: number)
	local L, O = st.spec.live, st.spec.old
	buffer.writeu32(L.sColor, p * 4, buffer.readu32(O.sColor, p * 4))
	buffer.writeu32(L.sShade, p * 4, buffer.readu32(O.sShade, p * 4))
	buffer.writeu32(L.sAlbedo, p * 4, buffer.readu32(O.sAlbedo, p * 4))
	buffer.writeu32(L.sShadowC, p * 4, 0)
	buffer.writeu8(L.sNormal, p, buffer.readu8(O.sNormal, p))
	buffer.writeu8(L.sLit, p, buffer.readu8(O.sLit, p))
	buffer.writef32(L.sDepth, p * 4, buffer.readf32(O.sDepth, p * 4))
	buffer.writeu16(L.sId, p * 2, buffer.readu16(st.oId, p * 2))
	buffer.writeu8(L.sShare, p, buffer.readu8(O.sShare, p))
	buffer.writeu8(L.sWClass, p, buffer.readu8(O.sWClass, p))
	buffer.writeu8(L.sWave, p, buffer.readu8(O.sWave, p))
end

-- The moving beach's layer `ly` on pixel p: flat ground of its colour where the ground there is (the new picture's
-- point when that is ground, else the old one's), lit as that point is.
local function putSynth(st: State, p: number, ly: number)
	local spec = st.spec
	local L, O = spec.live, spec.old
	local f = buffer.readu8(st.flags, p)
	local useNew = bit32.band(f, NEW_OBJ + NEW_SKY) == 0
	local depth = if useNew then buffer.readf32(st.nDepth, p * 4) else buffer.readf32(O.sDepth, p * 4)
	local lit = if useNew then buffer.readu8(st.nLit, p) else buffer.readu8(O.sLit, p)
	local rgb = spec.tints[ly]
	buffer.writeu8(L.sNormal, p, spec.up)
	buffer.writeu8(L.sLit, p, if lit > 1 then 1 else lit)
	local W = spec.W
	local ox, _oy, oz = spec.origin(p % W, p // W)
	local wx, wz = ox + spec.look.X * depth, oz + spec.look.Z * depth
	local c
	if ly == SAND and (math.floor(wx * 3) * 7 + math.floor(wz * 3) * 13) % 11 == 0 then
		-- (a speckle of the wet sand's colour now and then, fixed to the ground: dry sand isn't one flat colour)
		c = spec.toon(spec.tints[WET], p)
	else
		c = spec.toon(rgb, p)
	end
	buffer.writeu32(L.sColor, p * 4, c)
	buffer.writeu32(L.sShade, p * 4, c)
	buffer.writeu32(L.sAlbedo, p * 4, rgb)
	buffer.writeu32(L.sShadowC, p * 4, 0)
	buffer.writef32(L.sDepth, p * 4, depth)
	buffer.writeu16(L.sId, p * 2, spec.synthId(ly))
	buffer.writeu8(L.sShare, p, 0)
	local cls = if ly == FOAM then 3 elseif ly == SHALLOW then 2 else 0
	buffer.writeu8(L.sWClass, p, cls)
	if cls ~= 0 then
		buffer.writeu8(L.sWave, p, spec.wave(wx, wz))
	else
		buffer.writeu8(L.sWave, p, 0)
	end
end

------------------------------------------------------------------ what a pixel shows
-- What pixel p shows at progress e (SHOW_NEW, SHOW_OLD or SYNTH + layer).
local function decide(st: State, p: number, e: number): number
	local f = buffer.readu8(st.flags, p)
	if bit32.band(f, ADOPTED) ~= 0 or e >= 1 or (e >= SETTLE and e >= settleAt(st, p)) then
		return SHOW_NEW
	end
	if bit32.band(f, STILL) ~= 0 then
		return if e >= 0.5 then SHOW_NEW else SHOW_OLD
	end
	local newSky, oldSky = bit32.band(f, NEW_SKY) ~= 0, bit32.band(f, OLD_SKY) ~= 0
	local newOK, oldOK = newSky, oldSky
	local lyN, lyO = SEA, SEA
	if not newSky then
		local dO, dN = buffer.readf32(st.dOn, p * 4), buffer.readf32(st.dNn, p * 4)
		lyN = layerOf(dO - e * (dO - dN))
		-- (a new thing standing on the new shore, a palm or a rock, comes whole near the end, not a band at a time)
		newOK = if bit32.band(f, NEW_OBJ) ~= 0 then e >= NEW_THINGS else lyN == layerOf(dN)
	end
	if not oldSky then
		local dO, dN = buffer.readf32(st.dOo, p * 4), buffer.readf32(st.dNo, p * 4)
		lyO = layerOf(dO - e * (dO - dN))
		-- (an old thing goes whole, when the ground under the soonest of its part's pixels changes)
		oldOK = if bit32.band(f, OLD_OBJ) ~= 0 then e < buffer.readf32(st.tOld, p * 4) else lyO == layerOf(dO)
	end
	if newOK and oldOK then
		-- (both are there now: the nearer shows; a sky is farthest)
		if newSky then
			return SHOW_OLD
		elseif oldSky then
			return SHOW_NEW
		end
		return if buffer.readf32(st.nDepth, p * 4) <= buffer.readf32(st.spec.old.sDepth, p * 4) + 0.02 then SHOW_NEW else SHOW_OLD
	elseif newOK then
		return SHOW_NEW
	elseif oldOK then
		return SHOW_OLD
	end
	local ly = if newSky then lyO else lyN
	if ly >= SAND and ly <= SHALLOW then
		return SYNTH + ly
	end
	return if ly == SEA then SHOW_OLD else SHOW_NEW
end

-- When (progress, after e) pixel p's view may change next: the moving coast distance at either of its points crossing
-- a band's edge, or the coast a stud past an old thing standing there (2: not before the end).
local function nextChange(st: State, p: number, e: number): number
	local f = buffer.readu8(st.flags, p)
	if bit32.band(f, ADOPTED) ~= 0 then
		return 2
	end
	if bit32.band(f, STILL) ~= 0 and e < 0.5 then
		return 0.5
	end
	local best = settleAt(st, p)
	if best <= e + 1e-6 then
		best = 2
	end
	local function cross(dO: number, dN: number)
		local k = dO - dN
		if k <= 1e-4 then
			return
		end
		local c = dO - e * k
		for _, b in THRESH do
			if b < c - 1e-5 then
				local t = (dO - b) / k
				if t < best then
					best = t
				end
				return
			end
		end
	end
	if bit32.band(f, NEW_SKY) == 0 then
		cross(buffer.readf32(st.dOn, p * 4), buffer.readf32(st.dNn, p * 4))
	end
	if bit32.band(f, OLD_SKY) == 0 then
		cross(buffer.readf32(st.dOo, p * 4), buffer.readf32(st.dNo, p * 4))
	end
	if bit32.band(f, NEW_OBJ) ~= 0 and e < NEW_THINGS and NEW_THINGS < best then
		best = NEW_THINGS
	end
	if bit32.band(f, OLD_OBJ) ~= 0 then
		local t = buffer.readf32(st.tOld, p * 4)
		if t > e + 1e-6 and t < best then
			best = t
		end
	end
	return best
end

local function schedule(st: State, p: number, t: number)
	if t >= 1 then
		return
	end
	local b = math.floor(t * BUCKETS) + 1
	if b <= st.next then
		b = st.next + 1
	end
	if b <= BUCKETS then
		table.insert(st.buckets[b], p)
	end
end

-- Show what pixel p should show now; true when that changed. (A pixel just become foam over what was there: a spray
-- point now and then.)
local function apply(st: State, p: number, e: number, front: { Vector3 }?): boolean
	local want = decide(st, p, e)
	local was = buffer.readu8(st.state, p)
	if want == was then
		return false
	end
	buffer.writeu8(st.state, p, want)
	if want == SHOW_NEW then
		putNew(st, p)
	elseif want == SHOW_OLD then
		putOld(st, p)
	else
		putSynth(st, p, want - SYNTH)
		if front and want == SYNTH + FOAM and was == SHOW_OLD then
			st.frontN += 1
			if st.frontN % 61 == 0 and #front < 8 then
				local spec = st.spec
				local W = spec.W
				local ox, oy, oz = spec.origin(p % W, p // W)
				local d = buffer.readf32(spec.live.sDepth, p * 4)
				front[#front + 1] = Vector3.new(ox + spec.look.X * d, oy + spec.look.Y * d, oz + spec.look.Z * d)
			end
		end
	end
	return true
end

------------------------------------------------------------------ the API
function Grow.begin(spec: Spec): State
	local L, O = spec.live, spec.old
	local n = spec.W * spec.H
	local function keep(b: buffer): buffer
		local c = buffer.create(buffer.len(b))
		buffer.copy(c, 0, b, 0, buffer.len(b))
		return c
	end
	local st: State = {
		spec = spec,
		n = n,
		phase = "prep",
		row = 0,
		nColor = keep(L.sColor),
		nShade = keep(L.sShade),
		nAlbedo = keep(L.sAlbedo),
		nNormal = keep(L.sNormal),
		nLit = keep(L.sLit),
		nDepth = keep(L.sDepth),
		nId = keep(L.sId),
		nShare = keep(L.sShare),
		nWClass = keep(L.sWClass),
		nWave = keep(L.sWave),
		oId = buffer.create(n * 2),
		dOn = buffer.create(n * 4),
		dNn = buffer.create(n * 4),
		dOo = buffer.create(n * 4),
		dNo = buffer.create(n * 4),
		flags = buffer.create(n),
		tOld = buffer.create(n * 4),
		idGone = {},
		state = buffer.create(n),
		all = {},
		buckets = table.create(BUCKETS),
		next = 1,
		e = 0,
		frontN = 0,
		changed = 0,
	}
	for b = 1, BUCKETS do
		st.buckets[b] = {}
	end
	-- the old picture back on the layer whole (its ids into the layer's tables), the new one kept
	local remapped: { [number]: number } = {}
	for p = 0, n - 1 do
		local oid = buffer.readu16(O.sId, p * 2)
		local nid = 0
		if oid ~= 0 then
			local m = remapped[oid]
			if m == nil then
				m = spec.remap(oid)
				remapped[oid] = m
			end
			nid = m
		end
		buffer.writeu16(st.oId, p * 2, nid)
	end
	for _, k in { "sColor", "sShade", "sAlbedo", "sNormal", "sLit", "sDepth", "sShare", "sWClass", "sWave" } do
		local src: buffer = (O :: any)[k]
		buffer.copy((L :: any)[k], 0, src, 0, buffer.len(src))
	end
	buffer.copy(L.sId, 0, st.oId, 0, n * 2)
	buffer.fill(L.sShadowC, 0, 0)
	buffer.fill(st.state, 0, SHOW_OLD)
	return st
end

-- Work out a slice of the pixels (which differ, their points' coast distances, what shows at the start, when each
-- changes next); true once all are done and the coast may start moving.
function Grow.prep(st: State): boolean
	if st.phase ~= "prep" then
		return true
	end
	local spec = st.spec
	local O = spec.old
	local W, H = spec.W, spec.H
	local rows = math.max(1, PREP_PX // W)
	local lx, ly, lz = spec.look.X, spec.look.Y, spec.look.Z
	local px, pz = spec.plot.X, spec.plot.Z
	local from, to, far = spec.from, spec.to, spec.far
	local y1 = math.min(H - 1, st.row + rows - 1)
	for j = st.row, y1 do
		for i = 0, W - 1 do
			local p = j * W + i
			local dn = buffer.readf32(st.nDepth, p * 4)
			local dold = buffer.readf32(O.sDepth, p * 4)
			local wn, wo = buffer.readu8(st.nWClass, p), buffer.readu8(O.sWClass, p)
			local same: boolean
			if wn ~= 0 and wn <= 3 and wn == wo then
				-- (water in both: its colour moves with the waves, so only where it lies counts)
				same = math.abs(dn - dold) < 0.05
			else
				same = buffer.readu32(st.nColor, p * 4) == buffer.readu32(O.sColor, p * 4) and math.abs(dn - dold) < 0.05
			end
			if same then
				continue
			end
			local f = CHANGED
			local ox, oy, oz = spec.origin(i, j)
			local kn, ko = 0, 0
			if dn < far then
				local wx, wy, wz = ox + lx * dn - px, oy + ly * dn, oz + lz * dn - pz
				local dO, dN = distAt(from, wx, wz), distAt(to, wx, wz)
				buffer.writef32(st.dOn, p * 4, dO)
				buffer.writef32(st.dNn, p * 4, dN)
				kn = dO - dN
				if wy > OBJ_Y then
					f += NEW_OBJ
				end
			else
				f += NEW_SKY
			end
			if dold < far then
				local wx, wy, wz = ox + lx * dold - px, oy + ly * dold, oz + lz * dold - pz
				local dO, dN = distAt(from, wx, wz), distAt(to, wx, wz)
				buffer.writef32(st.dOo, p * 4, dO)
				buffer.writef32(st.dNo, p * 4, dN)
				ko = dO - dN
				if wy > OBJ_Y then
					f += OLD_OBJ
					-- (when the moving coast turns the ground here into the next layer down)
					local tv = 2
					if ko > 1e-4 then
						local foot = FOOT[layerOf(dO)]
						if foot > -math.huge then
							tv = math.max(0, (dO - foot) / ko)
						end
					end
					local oid = buffer.readu16(st.oId, p * 2)
					local was = st.idGone[oid]
					if was == nil or tv < was then
						st.idGone[oid] = tv
					end
				end
			else
				f += OLD_SKY
			end
			if kn < 0.25 and ko < 0.25 then
				-- (the coast barely moves here: something scattered anew changes halfway)
				f += STILL
			end
			buffer.writeu8(st.flags, p, f)
			buffer.writef32(st.tOld, p * 4, 2)
			st.changed += 1
			table.insert(st.all, p)
		end
	end
	st.row = y1 + 1
	if st.row >= H then
		-- every pixel worked out: each old thing's pixels go with their part's soonest, then what shows at the start
		-- and when each changes next
		local idGone = st.idGone
		for _, p in st.all do
			if bit32.band(buffer.readu8(st.flags, p), OLD_OBJ) ~= 0 then
				buffer.writef32(st.tOld, p * 4, idGone[buffer.readu16(st.oId, p * 2)] or 2)
			end
			apply(st, p, 0, nil)
			schedule(st, p, nextChange(st, p, 0))
		end
		st.phase = "grow"
		return true
	end
	return false
end

-- Move the coast to progress e (0 .. 1): the pixels a band reached show what is there now; returns whether any pixel
-- changed and a few world points where the foam just came (the spray's).
function Grow.step(st: State, e: number): (boolean, { Vector3 })
	local front: { Vector3 } = {}
	if st.phase ~= "grow" then
		return false, front
	end
	st.e = e
	local changed = false
	if e >= 1 then
		for _, p in st.all do
			if apply(st, p, 1, nil) then
				changed = true
			end
		end
		st.phase = "done"
		return changed, front
	end
	local upto = math.min(BUCKETS, math.floor(e * BUCKETS) + 1)
	while st.next <= upto do
		local list = st.buckets[st.next]
		st.buckets[st.next] = {}
		for _, p in list do
			if apply(st, p, e, front) then
				changed = true
			end
			schedule(st, p, nextChange(st, p, e))
		end
		st.next += 1
	end
	return changed, front
end

-- Shift a buffer of W x H elements of e bytes so that new (x, y) = old (x + dx, y + dy) (PixelRenderer's own).
local function shiftBuf(b: buffer, W: number, H: number, e: number, dx: number, dy: number)
	local w = W - math.abs(dx)
	if w <= 0 or math.abs(dy) >= H then
		return
	end
	local sx, tx = math.max(0, dx), math.max(0, -dx)
	if dy >= 0 then
		for y = 0, H - 1 - dy do
			buffer.copy(b, (y * W + tx) * e, b, ((y + dy) * W + sx) * e, w * e)
		end
	else
		for y = H - 1, -dy, -1 do
			buffer.copy(b, (y * W + tx) * e, b, ((y + dy) * W + sx) * e, w * e)
		end
	end
end

-- The layer scrolled by (dx, dy) (the view follows the founder) while the coast moves: the kept pictures, the
-- pixels' numbers and the lists move with it; a pixel pushed off the layer is dropped (the strips coming in are cast
-- new by the renderer). False while prepping (the renderer finishes it then).
function Grow.shift(st: State, dx: number, dy: number): boolean
	if st.phase == "prep" then
		return false
	end
	if st.phase ~= "grow" or (dx == 0 and dy == 0) then
		return true
	end
	local spec = st.spec
	local O = spec.old
	local W, H = spec.W, spec.H
	for _, b in { st.nColor, st.nShade, st.nAlbedo, st.nDepth, st.dOn, st.dNn, st.dOo, st.dNo, st.tOld, O.sColor, O.sShade, O.sAlbedo, O.sDepth } do
		shiftBuf(b, W, H, 4, dx, dy)
	end
	for _, b in { st.nNormal, st.nLit, st.nShare, st.nWClass, st.nWave, st.flags, st.state, O.sNormal, O.sLit, O.sShare, O.sWClass, O.sWave } do
		shiftBuf(b, W, H, 1, dx, dy)
	end
	shiftBuf(st.nId, W, H, 2, dx, dy)
	shiftBuf(st.oId, W, H, 2, dx, dy)
	local function move(list: { number }): { number }
		local out = table.create(#list)
		for _, p in list do
			local x, y = p % W - dx, p // W - dy
			if x >= 0 and y >= 0 and x < W and y < H then
				out[#out + 1] = y * W + x
			end
		end
		return out
	end
	for b = st.next, BUCKETS do
		st.buckets[b] = move(st.buckets[b])
	end
	st.all = move(st.all)
	return true
end

-- A rect of the layer (inclusive) was cast again (something there changed): what it shows now is the new picture
-- there, kept as such until the end.
function Grow.adopt(st: State, x0: number, y0: number, x1: number, y1: number)
	if st.phase == "done" then
		return
	end
	local spec = st.spec
	local L, W, H = spec.live, spec.W, spec.H
	x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(W - 1, x1), math.min(H - 1, y1)
	local w = x1 - x0 + 1
	if w <= 0 then
		return
	end
	for y = y0, y1 do
		local o = y * W + x0
		buffer.copy(st.nColor, o * 4, L.sColor, o * 4, w * 4)
		buffer.copy(st.nShade, o * 4, L.sShade, o * 4, w * 4)
		buffer.copy(st.nAlbedo, o * 4, L.sAlbedo, o * 4, w * 4)
		buffer.copy(st.nDepth, o * 4, L.sDepth, o * 4, w * 4)
		buffer.copy(st.nId, o * 2, L.sId, o * 2, w * 2)
		buffer.copy(st.nNormal, o, L.sNormal, o, w)
		buffer.copy(st.nLit, o, L.sLit, o, w)
		buffer.copy(st.nShare, o, L.sShare, o, w)
		buffer.copy(st.nWClass, o, L.sWClass, o, w)
		buffer.copy(st.nWave, o, L.sWave, o, w)
		for x = x0, x1 do
			local p = y * W + x
			buffer.writeu8(st.flags, p, bit32.bor(buffer.readu8(st.flags, p), ADOPTED))
			buffer.writeu8(st.state, p, SHOW_NEW)
		end
	end
end

-- The new picture everywhere now (a pan while prepping, a new bake: they can't wait for the coast).
function Grow.finish(st: State)
	if st.phase == "done" then
		return
	end
	local L = st.spec.live
	if st.phase == "prep" then
		-- (nothing has moved yet: the kept picture back whole)
		buffer.copy(L.sColor, 0, st.nColor, 0, buffer.len(st.nColor))
		buffer.copy(L.sShade, 0, st.nShade, 0, buffer.len(st.nShade))
		buffer.copy(L.sAlbedo, 0, st.nAlbedo, 0, buffer.len(st.nAlbedo))
		buffer.copy(L.sNormal, 0, st.nNormal, 0, buffer.len(st.nNormal))
		buffer.copy(L.sLit, 0, st.nLit, 0, buffer.len(st.nLit))
		buffer.copy(L.sDepth, 0, st.nDepth, 0, buffer.len(st.nDepth))
		buffer.copy(L.sId, 0, st.nId, 0, buffer.len(st.nId))
		buffer.copy(L.sShare, 0, st.nShare, 0, buffer.len(st.nShare))
		buffer.copy(L.sWClass, 0, st.nWClass, 0, buffer.len(st.nWClass))
		buffer.copy(L.sWave, 0, st.nWave, 0, buffer.len(st.nWave))
		buffer.fill(L.sShadowC, 0, 0)
		st.phase = "done"
		return
	end
	Grow.step(st, 1)
	st.phase = "done"
end

-- Previews and sims: how far it has got (pixels that differ, those not yet showing the new picture, on the moving
-- beach now).
function Grow.stats(st: State): { phase: string, changed: number, pending: number, fresh: number, e: number }
	local pending, fresh = 0, 0
	for _, p in st.all do
		local s = buffer.readu8(st.state, p)
		if s ~= SHOW_NEW then
			pending += 1
			if s >= SYNTH then
				fresh += 1
			end
		end
	end
	return { phase = st.phase, changed = st.changed, pending = pending, fresh = fresh, e = st.e }
end

return Grow
