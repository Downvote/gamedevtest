--!strict
-- A driftling's skeleton and skin (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module (client: DriftModels.animate
-- runs it every frame a driftling is posed).
--
-- The request (2026-11-14): "right now, the models simply move by rotating or moving parts of the mesh around. please
-- use bones and rigging to make more realistic and detailed movement. follow and use as many animation principles
-- when animating as well."
--
-- Roblox's own Bone instances bend only skinned MeshParts, uploaded meshes; a driftling is built from plain parts that
-- the pixel filter draws, so its rig lives here, in code. Each joint the body plan declares (Models/DriftKit `J`) is a
-- bone: its head the joint's pivot, its tail the farthest point of what hangs on it (its parts and the bones on it),
-- so it has a direction and a length. Every part is skinned to its bone, and a small part near a joint to two bones
-- with a weight (`blend`: half and half right at the pivot, all its own bone's a third of the bone's length away), so
-- a bend at a joint is shared by the pieces either side of it and a neck, tail or limb bends smoothly instead of
-- hinging. Each frame (Rig.animate):
--   1. the mood's program and each bone's pose (Models/DriftMotion: turns, a shift and a stretch), blended from the
--      last mood's over BLEND_T s when the mood changes, so nothing snaps;
--   2. forward kinematics down the chain (a child's pose is in its parent's: an ear rides the head that rides the
--      body), a bone's stretch carrying the bones on it along;
--   3. springs (straight ahead, frame by frame: follow through and overlapping action): the ears, tails, antennae,
--      tendrils, eye stalks, fins and wing tips each have a point mass at their tip pulled toward where the pose puts
--      it, so they lag, swing past and settle when the body moves (`SPRINGS`: stiffness, damping, the most they swing);
--      the driftling's own movement about the island counts (MicroModels.place keeps its last placement);
--   4. the skin: each part where its bones put it (two bones: in between by its weight), stretched with its bone, and
--      the whole driftling squashed and stretched from the ground up by the body bone's stretch (its volume kept: as
--      it gets shorter it gets wider). Up close (the "full" level of detail) the parts' sizes squash with it too.
--   Rig.skeleton(thing) -> Skel (built once, kept on the rig), Rig.animate(thing, time, mood, k, squash)
local Kit = require(script.Parent.DriftKit)
local Motion = require(script.Parent.DriftMotion)

local Rig = {}

local BLEND_T = 0.28 -- seconds a change of mood blends over
local SIZE_STEP = 0.05 -- the squash the parts' sizes follow, in steps (up close only)
local TELEPORT = 3 -- studs it may move between two frames before the springs start again where it is

-- The springs: stiffness k (how hard the tip is pulled to its pose), damping z (1 settles without swinging past,
-- lower swings past and back: floppier), max (radians the spring turns the bone at most).
local SPRINGS: { [string]: { k: number, z: number, max: number } } = {
	ear = { k = 170, z = 0.3, max = 0.6 },
	tail = { k = 110, z = 0.36, max = 0.7 },
	antenna = { k = 140, z = 0.22, max = 0.7 },
	tendril = { k = 60, z = 0.45, max = 0.8 },
	stalk = { k = 150, z = 0.28, max = 0.5 },
	fin = { k = 200, z = 0.5, max = 0.4 },
	wingTip = { k = 240, z = 0.55, max = 0.4 },
}
Rig.SPRINGS = SPRINGS

-- The bones whose small parts near the joint share the bend with the bone above (smooth joints). The jaw and the
-- pincers hinge cleanly.
local BLEND: { [string]: boolean } = {
	neck = true,
	head = true,
	tail = true,
	ear = true,
	arm = true,
	leg = true,
	wing = true,
	fin = true,
	tendril = true,
	stalk = true,
	antenna = true,
}

export type Spring = { k: number, c: number, max: number }
export type Bone = {
	name: string,
	parent: number, -- 0: the root
	pivot: Vector3,
	kind: string,
	side: number,
	phase: number,
	axis: Vector3, -- from the pivot toward its tail (unit)
	len: number,
	spring: Spring?,
	children: { number },
}
export type Skin = {
	name: string,
	part: BasePart,
	r0: CFrame,
	b1: number, -- its bone
	b2: number, -- the second bone it is skinned to (0: none)
	w: number, -- the second bone's weight (0 .. 0.5)
	face: string?, -- a face part's kind (DriftKit: "eye" | "lid" | "open" | "closed")
	tuck: Vector3?,
	shine: boolean,
	blink: string?, -- an old-style "eye" or "mouth" part that changes size
	size: Vector3,
}
export type Skel = { bones: { Bone }, skins: { Skin }, root: number, ground: boolean, tempo: number, seed: number, full: boolean }
type State = {
	mood: string,
	moodAt: number,
	from: string?,
	fromAt: number,
	last: number?,
	cur: Motion.Prog,
	prev: Motion.Prog,
	world: { CFrame },
	sq: { number },
	sx: { Vector3? },
	sv: { Vector3? },
	sizeQ: number,
	ang: { number }, -- each spring's turn last frame (radians; sims and previews)
	at: Vector3?, -- where it was placed last frame (a jump of more than TELEPORT studs resets the springs)
}

local made = 0

-- The skeleton of a built driftling (its rig's joints and parts), worked out the first time it is posed.
function Rig.skeleton(t: Kit.Thing): Skel
	local rig = t.rig :: Kit.Rig
	local have = rig.skel
	if have ~= nil then
		return have :: Skel
	end
	local bones: { Bone } = {}
	local index: { [string]: number } = {}
	for i, name in rig.order do
		local j = rig.joints[name]
		index[name] = i
		bones[i] = { name = name, parent = 0, pivot = j.pivot, kind = j.kind, side = j.side, phase = j.phase, axis = Vector3.yAxis, len = 0.3, spring = nil, children = {} }
	end
	for i, name in rig.order do
		local j = rig.joints[name]
		local p = if j.parent then index[j.parent :: string] else nil
		if p then
			bones[i].parent = p
			table.insert(bones[p].children, i)
		end
	end
	-- each bone's tail: the farthest of its parts' centres and the pivots of the bones on it
	local far: { number } = table.create(#bones, 0)
	local tip: { Vector3 } = {}
	for i, b in bones do
		tip[i] = b.pivot + Vector3.yAxis * 0.3
		for _, c in b.children do
			local d = (bones[c].pivot - b.pivot).Magnitude
			if d > far[i] then
				far[i], tip[i] = d, bones[c].pivot
			end
		end
	end
	for name, _ in t.parts do
		local i = index[rig.of[name] or "body"] or 1
		local c = t.baseRest[name].Position
		local d = (c - bones[i].pivot).Magnitude
		if d > far[i] then
			far[i], tip[i] = d, c
		end
	end
	for i, b in bones do
		local v = tip[i] - b.pivot
		if v.Magnitude > 1e-3 then
			b.axis = v.Unit
		end
		b.len = math.max(0.15, v.Magnitude)
		local sp: { k: number, z: number, max: number }? = SPRINGS[b.kind]
		if b.kind == "wing" then
			sp = if b.phase >= 1 then SPRINGS.wingTip else nil
		end
		if sp then
			b.spring = { k = sp.k, c = 2 * sp.z * math.sqrt(sp.k), max = sp.max }
		end
	end
	local root = 1
	for i, b in bones do
		if b.parent == 0 then
			root = i
			break
		end
	end
	-- the skin: each part on its bone, a small one near a joint shared with the bone across it
	local skins: { Skin } = {}
	for name, part in t.parts do
		local b1 = index[rig.of[name] or "body"] or root
		local r0 = t.baseRest[name]
		local c = r0.Position
		local size = t.baseSize[name]
		local b2, w = 0, 0
		local small = math.max(size.X, size.Y, size.Z) <= 0.55
		if t.face[name] == nil and small then
			local b = bones[b1]
			if b.parent > 0 and BLEND[b.kind] then
				local R = math.clamp(b.len * 0.33, 0.12, 0.32)
				local d = (c - b.pivot).Magnitude
				if d < R then
					b2, w = b.parent, 0.5 * (1 - d / R)
				end
			end
			if b2 == 0 then
				for _, ch in b.children do
					local cb = bones[ch]
					if BLEND[cb.kind] then
						local R = math.clamp(cb.len * 0.33, 0.12, 0.32)
						local d = (c - cb.pivot).Magnitude
						local wc = if d < R then 0.5 * (1 - d / R) else 0
						if wc > w then
							b2, w = ch, wc
						end
					end
				end
			end
		end
		local blink: string? = nil
		if t.face[name] == nil then
			blink = if name == "EyeL" or name == "EyeR" then "eye" elseif name == "Mouth" then "mouth" else nil
		end
		table.insert(skins, {
			name = name,
			part = part,
			r0 = r0,
			b1 = b1,
			b2 = b2,
			w = w,
			face = t.face[name],
			tuck = t.tuck[name],
			shine = string.sub(name, 1, 5) == "Shine",
			blink = blink,
			size = size,
		})
	end
	made += 1
	local sk: Skel = {
		bones = bones,
		skins = skins,
		root = root,
		ground = rig.gait ~= "fly",
		-- (a bigger driftling moves a little slower: timing)
		tempo = math.clamp((1.9 / math.max(0.5, t.h)) ^ 0.35, 0.82, 1.18),
		seed = (made * 0.6180339887) % 1 * 10,
		full = t.lod ~= "world",
	}
	rig.skel = sk
	return sk
end

-- p stretched by s along the unit axis `ax` through `o`, its volume kept (1/sqrt(s) across).
local function stretchAt(p: Vector3, o: Vector3, ax: Vector3, s: number): Vector3
	local d = p - o
	local along = d:Dot(ax)
	local perp = d - ax * along
	return o + ax * (along * s) + perp / math.sqrt(s)
end
Rig.stretchAt = stretchAt

local function newState(n: number): State
	return {
		mood = "",
		moodAt = 0,
		from = nil,
		fromAt = 0,
		last = nil,
		cur = Motion.newProg(),
		prev = Motion.newProg(),
		world = table.create(n, CFrame.identity),
		sq = table.create(n, 1),
		sx = {},
		sv = {},
		sizeQ = 1,
		ang = table.create(n, 0),
	}
end

-- how much a part's side along `e` (a unit direction) grows under the squash (inv across, q up)
local function grow(e: Vector3, inv: number, q: number): number
	local x, y, z = e.X * inv, e.Y * q, e.Z * inv
	return math.sqrt(x * x + y * y + z * z)
end

-- Pose a driftling for the moment: `time` its clock (seconds, offset per driftling), `mood` (DriftMotion's moods),
-- `k` an action's progress, `sc` MicroModels.scale's squash. Writes the thing's rest poses (and, up close, sizes).
function Rig.animate(t: Kit.Thing, time: number, mood: string, k: number?, sc: Vector3)
	local rig = t.rig :: Kit.Rig
	local sk = Rig.skeleton(t)
	local bones = sk.bones
	local st: State = (rig.anim :: State?) or newState(#bones)
	rig.anim = st
	local last = st.last
	local dt = if last then time - last else -1
	local jumped = dt <= 0 or dt > 0.25 -- (the first pose, or the clock jumped: no springs, no blend)
	st.last = time
	if mood ~= st.mood then
		if not jumped and st.mood ~= "" then
			st.from, st.fromAt = st.mood, time
		end
		st.mood, st.moodAt = mood, time
	end
	if jumped then
		st.from = nil
		if last == nil then
			st.moodAt = time - 10 -- (first seen mid-mood: a hurt one already flinched)
		end
	end
	local kk = math.clamp(k or 0, 0, 1)
	local cur = Motion.program(mood, time, time - st.moodAt, kk, rig.gait, sk.tempo, sk.seed, st.cur)
	local blend = 1
	local prev = st.prev
	local from = st.from
	if from then
		local e = (time - st.fromAt) / BLEND_T
		if e >= 1 then
			st.from = nil
		else
			blend = Motion.ease(Motion.SMOOTH, e)
			Motion.program(from, time, 10, kk, rig.gait, sk.tempo, sk.seed, prev)
		end
	end
	local world, sqs = st.world, st.sq
	local placed = rig.placed or CFrame.identity
	-- (put somewhere new: placed for the first time, or moved further than a walk in one frame: the springs start
	-- again where it is rather than swinging across the gap)
	local at, was = placed.Position, st.at
	local resprung = jumped or was == nil or (at - (was :: Vector3)).Magnitude > TELEPORT
	st.at = at
	local root = sk.root
	-- 2. forward kinematics, 3. the springs
	for i, b in bones do
		local rx, ry, rz, tx, ty, tz, sq = Motion.bone(cur, b.kind, b.side, b.phase)
		if blend < 1 then
			local px, py, pz, qx, qy, qz, psq = Motion.bone(prev, b.kind, b.side, b.phase)
			rx, ry, rz = px + (rx - px) * blend, py + (ry - py) * blend, pz + (rz - pz) * blend
			tx, ty, tz = qx + (tx - qx) * blend, qy + (ty - qy) * blend, qz + (tz - qz) * blend
			sq = psq + (sq - psq) * blend
		end
		local pv = b.pivot
		local L = CFrame.new(pv.X + tx, pv.Y + ty, pv.Z + tz) * CFrame.fromEulerAnglesXYZ(rx, ry, rz) * CFrame.new(-pv)
		local p = b.parent
		local W = if p > 0 then world[p] * L else L
		if p > 0 and p ~= root and sqs[p] ~= 1 then
			-- (the bone above is stretched: this one's pivot goes with it)
			local pb, Wp = bones[p], world[p]
			local P = W * pv
			W = CFrame.new(stretchAt(P, Wp * pb.pivot, Wp:VectorToWorldSpace(pb.axis), sqs[p]) - P) * W
		end
		local spr = b.spring
		if spr then
			local tipM = W * (pv + b.axis * b.len)
			local pivM = W * pv
			local tipW = placed * (tipM * sc)
			local m, v = st.sx[i], st.sv[i]
			if m == nil or v == nil or resprung then
				m, v = tipW, Vector3.zero
			else
				local n = math.clamp(math.ceil(dt * 60), 1, 4)
				local h = dt / n
				local mm, vv = m :: Vector3, v :: Vector3
				for _ = 1, n do
					vv += ((tipW - mm) * spr.k - vv * spr.c) * h
					mm += vv * h
				end
				m, v = mm, vv
			end
			st.sx[i], st.sv[i] = m, v
			local mo = placed:PointToObjectSpace(m :: Vector3)
			local mM = Vector3.new(mo.X / sc.X, mo.Y / sc.Y, mo.Z / sc.Z)
			local a, c = tipM - pivM, mM - pivM
			local la, lc = a.Magnitude, c.Magnitude
			if la > 1e-4 and lc > 1e-4 then
				local ua, uc = a / la, c / lc
				local ang = math.acos(math.clamp(ua:Dot(uc), -1, 1))
				local ax = ua:Cross(uc)
				st.ang[i] = 0
				if ang > 1e-3 and ax.Magnitude > 1e-5 then
					st.ang[i] = math.min(ang, spr.max)
					W = CFrame.new(pivM) * CFrame.fromAxisAngle(ax.Unit, math.min(ang, spr.max)) * CFrame.new(-pivM) * W
				end
			end
		end
		world[i], sqs[i] = W, sq
	end
	-- 4. the skin
	local gsq = sqs[root]
	local inv = 1 / math.sqrt(gsq)
	local gy0 = if sk.ground then 0 else bones[root].pivot.Y
	local shut, open = cur.shut, cur.open
	local rest = t.rest
	for _, s in sk.skins do
		local r0 = s.r0
		local fk = s.face
		if fk then
			-- the kit's face parts: each tucked in along its normal while it is hidden (a blink, a smile)
			local hide = if fk == "eye" then shut elseif fk == "lid" then not shut elseif fk == "open" then not open else open
			if hide then
				r0 = r0 * CFrame.new(s.tuck or Vector3.new(-Kit.TUCK, 0, 0))
			end
		elseif s.shine and shut then
			r0 = r0 * CFrame.new(0, 0, -0.25) -- (a shut eye hides its shine)
		end
		local rr = world[s.b1] * r0
		if s.w > 0 then
			rr = rr:Lerp(world[s.b2] * r0, s.w)
		end
		local pos = rr.Position
		local b1 = s.b1
		local bsq = sqs[b1]
		if b1 ~= root and bsq ~= 1 then
			local b, Wb = bones[b1], world[b1]
			pos = stretchAt(pos, Wb * b.pivot, Wb:VectorToWorldSpace(b.axis), bsq)
		end
		if gsq ~= 1 then
			pos = Vector3.new(pos.X * inv, gy0 + (pos.Y - gy0) * gsq, pos.Z * inv)
		end
		rest[s.name] = CFrame.new(pos * sc) * rr.Rotation
	end
	-- the sizes: up close they squash with the body (in steps, written only when they change); an old-style eye or
	-- mouth part shrinks to blink and grows to open
	local q = if sk.full then 1 + math.floor((gsq - 1) / SIZE_STEP + 0.5) * SIZE_STEP else 1
	local resize = q ~= 1 or st.sizeQ ~= 1
	st.sizeQ = q
	local qi = 1 / math.sqrt(q)
	for _, s in sk.skins do
		if resize or s.blink then
			local b = s.size
			local sx, sy, sz = b.X * sc.X, b.Y * sc.Y, b.Z * sc.Z
			if s.blink == "eye" and shut then
				sy = 0.125 * sc.Y
			elseif s.blink == "mouth" and open then
				sy = math.max(0.25, b.Y * 2.5) * sc.Y
			end
			if q ~= 1 then
				local r = rest[s.name]
				sx *= grow(r.RightVector, qi, q)
				sy *= grow(r.UpVector, qi, q)
				sz *= grow(r.LookVector, qi, q)
			end
			local want = Vector3.new(sx, sy, sz)
			if s.part.Size ~= want then
				s.part.Size = want
			end
		end
	end
end

-- (previews) Each spring bone's turn last frame, degrees, by bone name.
function Rig.debugSprings(t: Kit.Thing): { [string]: number }
	local sk = Rig.skeleton(t)
	local st = (t.rig :: Kit.Rig).anim :: State?
	local out: { [string]: number } = {}
	for i, b in sk.bones do
		if b.spring then
			out[b.name] = if st then math.floor(math.deg(st.ang[i] or 0) + 0.5) else 0
		end
	end
	return out
end

-- (sims and specs) A driftling's skeleton in numbers: bones, springs, skinned parts, parts shared by two bones.
function Rig.stats(t: Kit.Thing): { bones: number, springs: number, parts: number, shared: number }
	local sk = Rig.skeleton(t)
	local springs, shared = 0, 0
	for _, b in sk.bones do
		if b.spring then
			springs += 1
		end
	end
	for _, s in sk.skins do
		if s.w > 0 then
			shared += 1
		end
	end
	return { bones = #sk.bones, springs = springs, parts = #sk.skins, shared = shared }
end

return Rig
