-- Real WorldRoot:Raycast for the fake engine (preview tool).
-- Every queryable BasePart under the WorldRoot (Workspace or a WorldModel) is intersected exactly with its CFrame and
-- Size: Block (and every Part shape that is not Ball/Cylinder/Wedge/CornerWedge), Ball (diameter = smallest side),
-- Cylinder (axis = local X, diameter = smaller of Y and Z), Wedge (WedgePart or Part.Shape Wedge: full bottom and
-- back faces, slope facing front/up) and CornerWedge (CornerWedgePart or Part.Shape CornerWedge; assumed apex above
-- the (+X, -Z) bottom corner).
-- Engine rules mirrored here:
--   * Transparency never matters (Roblox rays hit invisible parts; callers skip them themselves).
--   * A part is queryable when CanQuery is true or CanCollide is true (CanQuery only takes effect with CanCollide off).
--   * A ray whose origin is inside a part does not hit that part.
--   * RaycastParams: FilterType Include/Exclude over FilterDescendantsInstances (descendants included),
--     RespectCanCollide, CollisionGroup (E.collisionGroupsCollide(a, b), default: everything collides), IgnoreWater
--     (no terrain water exists in the fake, so it is a no-op).
-- Acceleration: one BVH per (WorldRoot, filter contents, filter type, RespectCanCollide, CollisionGroup), rebuilt when
-- the set of parts changes (reparent into/out of a world, Shape/CanQuery/CanCollide/CollisionGroup writes) and
-- refitted when a member part moves or resizes. Moving parts that the filter excludes (customers in PixelDynamic for
-- the pixel renderer) never touch that BVH.
local E = require("./engine")
local I = require("./inst")
local getD = I.getD
local isA = I.isA
local v3 = E.v3
local Enum = E.Enum
local CF = E.cf

local R = {}
E.raycastStats = { rays = 0, builds = 0, refits = 0, nodeTests = 0, itemTests = 0 }
local STATS = E.raycastStats

------------------------------------------------------------------ change tracking
local structVersion = 1
local caches = {}
local MAX_CACHES = 8

local basePartCls = {}
local function isBasePart(cls)
	local v = basePartCls[cls]
	if v == nil then
		v = isA(cls, "BasePart")
		basePartCls[cls] = v
	end
	return v
end
local worldRootCls = {}
local function isWorldRoot(cls)
	local v = worldRootCls[cls]
	if v == nil then
		v = isA(cls, "WorldRoot")
		worldRootCls[cls] = v
	end
	return v
end
local function inWorld(inst)
	local cur = inst
	while cur do
		local d = getD(cur)
		if isWorldRoot(d.cls) then
			return true
		end
		cur = d.props.Parent
	end
	return false
end
R.inWorld = inWorld

E.onPartGeom = function(part)
	for _, c in caches do
		if c.members[part] then
			c.dirty[part] = true
			c.anyDirty = true
		end
	end
end
local prevReparent = I.onReparent
I.onReparent = function(subtree, old, new)
	if prevReparent then
		prevReparent(subtree, old, new)
	end
	local any = false
	for _, x in subtree do
		if isBasePart(getD(x).cls) then
			any = true
			break
		end
	end
	if not any then
		return
	end
	if (old ~= nil and inWorld(old)) or (new ~= nil and inWorld(new)) then
		structVersion += 1
	end
end
local STRUCT_PROPS = { Shape = true, CanQuery = true, CanCollide = true, CollisionGroup = true }
local prevPropWrite = I.onPropWrite
I.onPropWrite = function(self, d, k)
	if prevPropWrite then
		prevPropWrite(self, d, k)
	end
	if STRUCT_PROPS[k] and isBasePart(d.cls) and d.props.Parent ~= nil and inWorld(self) then
		structVersion += 1
	end
end
function R.invalidateAll()
	structVersion += 1
end

E.collisionGroupsCollide = E.collisionGroupsCollide or function(_a, _b)
	return true
end

------------------------------------------------------------------ shapes
local SH_BLOCK, SH_BALL, SH_CYL, SH_WEDGE, SH_CORNER = 1, 2, 3, 4, 5
local function shapeOf(d)
	local cls = d.cls
	if cls == "WedgePart" then
		return SH_WEDGE
	elseif cls == "CornerWedgePart" then
		return SH_CORNER
	end
	local s = d.props.Shape
	if s ~= nil then
		local name = if type(s) == "table" then rawget(s, "Name") elseif type(s) == "number" then ({ "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" })[s + 1] else tostring(s)
		if name == "Ball" then
			return SH_BALL
		elseif name == "Cylinder" then
			return SH_CYL
		elseif name == "Wedge" then
			return SH_WEDGE
		elseif name == "CornerWedge" then
			return SH_CORNER
		end
	end
	return SH_BLOCK
end
R.shapeOf = shapeOf
R.SHAPES = { block = SH_BLOCK, ball = SH_BALL, cylinder = SH_CYL, wedge = SH_WEDGE, cornerwedge = SH_CORNER }

local DEFAULT_SIZE = v3(4, 1, 2)
local IDENT_R = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }

------------------------------------------------------------------ cache (struct of arrays)
local function newCache(root, key, include, respect, group)
	return {
		root = root,
		key = key,
		include = include,
		respect = respect,
		group = group,
		version = -1,
		members = {},
		dirty = {},
		anyDirty = false,
		-- items
		n = 0,
		part = {},
		shape = {},
		cx = {}, cy = {}, cz = {},
		r0 = {}, r1 = {}, r2 = {}, r3 = {}, r4 = {}, r5 = {}, r6 = {}, r7 = {}, r8 = {},
		hx = {}, hy = {}, hz = {},
		planes = {},
		bx0 = {}, by0 = {}, bz0 = {}, bx1 = {}, by1 = {}, bz1 = {},
		itemLeaf = {},
		-- nodes
		order = {},
		nn = 0,
		nx0 = {}, ny0 = {}, nz0 = {}, nx1 = {}, ny1 = {}, nz1 = {},
		left = {}, right = {}, lo = {}, hi = {}, parent = {},
	}
end

local function loadItem(c, i, p)
	local d = getD(p)
	local cf = d.props.CFrame or CF.identity
	local size = d.props.Size or DEFAULT_SIZE
	local r = rawget(cf, "_r") or IDENT_R
	local shape = shapeOf(d)
	c.part[i] = p
	c.shape[i] = shape
	local px, py, pz = cf.X, cf.Y, cf.Z
	c.cx[i], c.cy[i], c.cz[i] = px, py, pz
	local a0, a1, a2, a3, a4, a5, a6, a7, a8 = r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
	c.r0[i], c.r1[i], c.r2[i], c.r3[i], c.r4[i], c.r5[i], c.r6[i], c.r7[i], c.r8[i] = a0, a1, a2, a3, a4, a5, a6, a7, a8
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	c.hx[i], c.hy[i], c.hz[i] = hx, hy, hz
	local ex, ey, ez
	if shape == SH_BALL then
		local rad = math.min(hx, hy, hz)
		ex, ey, ez = rad, rad, rad
	else
		ex = math.abs(a0) * hx + math.abs(a1) * hy + math.abs(a2) * hz
		ey = math.abs(a3) * hx + math.abs(a4) * hy + math.abs(a5) * hz
		ez = math.abs(a6) * hx + math.abs(a7) * hy + math.abs(a8) * hz
	end
	c.bx0[i], c.by0[i], c.bz0[i] = px - ex, py - ey, pz - ez
	c.bx1[i], c.by1[i], c.bz1[i] = px + ex, py + ey, pz + ez
	if shape == SH_WEDGE then
		-- inside: x <= hx, -x <= hx, -y <= hy, z <= hz, hz*y - hy*z <= 0 (top edge at the back, slope faces -Z / +Y)
		c.planes[i] = {
			1, 0, 0, hx,
			-1, 0, 0, hx,
			0, -1, 0, hy,
			0, 0, 1, hz,
			0, hz, -hy, 0,
		}
	elseif shape == SH_CORNER then
		-- pyramid over the full bottom face, apex above (+hx, -hz): faces x = hx and z = -hz are vertical triangles,
		-- the two slopes run down to the x = -hx and z = +hz bottom edges
		-- slope A: (y + hy)/(2hy) <= (x + hx)/(2hx)  ->  hx*y - hy*x <= 0
		-- slope B: (y + hy)/(2hy) <= (hz - z)/(2hz)  ->  hz*y + hy*z <= 0
		c.planes[i] = {
			1, 0, 0, hx,
			0, 0, -1, hz,
			0, -1, 0, hy,
			-hy, hx, 0, 0,
			0, hz, hy, 0,
		}
	else
		c.planes[i] = nil
	end
end

local function nodeBoxFromItems(c, node)
	local order = c.order
	local x0, y0, z0, x1, y1, z1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	local bx0, by0, bz0, bx1, by1, bz1 = c.bx0, c.by0, c.bz0, c.bx1, c.by1, c.bz1
	for k = c.lo[node], c.hi[node] do
		local i = order[k]
		if bx0[i] < x0 then x0 = bx0[i] end
		if by0[i] < y0 then y0 = by0[i] end
		if bz0[i] < z0 then z0 = bz0[i] end
		if bx1[i] > x1 then x1 = bx1[i] end
		if by1[i] > y1 then y1 = by1[i] end
		if bz1[i] > z1 then z1 = bz1[i] end
	end
	c.nx0[node], c.ny0[node], c.nz0[node], c.nx1[node], c.ny1[node], c.nz1[node] = x0, y0, z0, x1, y1, z1
end

local LEAF = 4
local function buildNode(c, lo, hi, parentNode)
	c.nn += 1
	local node = c.nn
	c.lo[node], c.hi[node], c.parent[node] = lo, hi, parentNode
	nodeBoxFromItems(c, node)
	if hi - lo + 1 <= LEAF then
		c.left[node], c.right[node] = 0, 0
		for k = lo, hi do
			c.itemLeaf[c.order[k]] = node
		end
		return node
	end
	-- split at the centroid midpoint of the longest centroid axis
	local order = c.order
	local bx0, by0, bz0, bx1, by1, bz1 = c.bx0, c.by0, c.bz0, c.bx1, c.by1, c.bz1
	local mx0, my0, mz0, mx1, my1, mz1 = math.huge, math.huge, math.huge, -math.huge, -math.huge, -math.huge
	for k = lo, hi do
		local i = order[k]
		local x, y, z = bx0[i] + bx1[i], by0[i] + by1[i], bz0[i] + bz1[i]
		if x < mx0 then mx0 = x end
		if y < my0 then my0 = y end
		if z < mz0 then mz0 = z end
		if x > mx1 then mx1 = x end
		if y > my1 then my1 = y end
		if z > mz1 then mz1 = z end
	end
	local ax0, ax1 = bx0, bx1
	local mid = (mx0 + mx1) / 2
	local ext = mx1 - mx0
	if my1 - my0 > ext then
		ax0, ax1, mid, ext = by0, by1, (my0 + my1) / 2, my1 - my0
	end
	if mz1 - mz0 > ext then
		ax0, ax1, mid, ext = bz0, bz1, (mz0 + mz1) / 2, mz1 - mz0
	end
	local i, j = lo, hi
	while i <= j do
		local it = order[i]
		if ax0[it] + ax1[it] < mid then
			i += 1
		else
			order[i], order[j] = order[j], order[i]
			j -= 1
		end
	end
	local split = i - 1
	if split < lo or split >= hi then
		split = (lo + hi) // 2 -- every centroid on one side (stacked parts): split by count
	end
	local l = buildNode(c, lo, split, node)
	local r = buildNode(c, split + 1, hi, node)
	c.left[node], c.right[node] = l, r
	return node
end

local function rebuild(c)
	STATS.builds += 1
	table.clear(c.members)
	table.clear(c.dirty)
	c.anyDirty = false
	table.clear(c.planes)
	c.n = 0
	c.nn = 0
	local filterSet = c.filterSet
	local include = c.include
	local respect = c.respect
	local group = c.group
	local collide = E.collisionGroupsCollide
	local n = 0
	local function walk(inst, inFilter)
		local d = getD(inst)
		local f = inFilter or (filterSet[inst] == true)
		if isBasePart(d.cls) then
			local props = d.props
			local canCollide = props.CanCollide ~= false
			local queryable = canCollide or props.CanQuery ~= false
			local pass = if include then f else not f
			if queryable and pass and (not respect or canCollide) then
				local pg = props.CollisionGroup or "Default"
				if collide(group, pg) then
					n += 1
					loadItem(c, n, inst)
					c.members[inst] = n
				end
			end
		end
		for _, ch in d.children do
			walk(ch, f)
		end
	end
	for _, ch in getD(c.root).children do
		walk(ch, false)
	end
	c.n = n
	local order = c.order
	table.clear(order)
	for i = 1, n do
		order[i] = i
	end
	if n > 0 then
		buildNode(c, 1, n, 0)
	end
	c.version = structVersion
end

local function refit(c)
	STATS.refits += 1
	local touched = {}
	for part in c.dirty do
		local i = c.members[part]
		if i then
			loadItem(c, i, part)
			touched[c.itemLeaf[i]] = true
		end
	end
	table.clear(c.dirty)
	c.anyDirty = false
	local parent = c.parent
	local left, right = c.left, c.right
	local nx0, ny0, nz0, nx1, ny1, nz1 = c.nx0, c.ny0, c.nz0, c.nx1, c.ny1, c.nz1
	for leaf in touched do
		nodeBoxFromItems(c, leaf)
		local p = parent[leaf]
		while p ~= 0 do
			local a, b = left[p], right[p]
			nx0[p] = math.min(nx0[a], nx0[b])
			ny0[p] = math.min(ny0[a], ny0[b])
			nz0[p] = math.min(nz0[a], nz0[b])
			nx1[p] = math.max(nx1[a], nx1[b])
			ny1[p] = math.max(ny1[a], ny1[b])
			nz1[p] = math.max(nz1[a], nz1[b])
			p = parent[p]
		end
	end
end

------------------------------------------------------------------ filter keys
local filterKeys = setmetatable({}, { __mode = "k" }) -- the params' internal list -> "id,id,..."
local EMPTY = {}
local function filterKey(list)
	local k = filterKeys[list]
	if k then
		return k
	end
	local ids = {}
	for _, x in list do
		table.insert(ids, getD(x).id)
	end
	table.sort(ids)
	k = table.concat(ids, ",")
	filterKeys[list] = k
	return k
end

local function cacheFor(root, params)
	local list, include, respect, group = EMPTY, false, false, "Default"
	if params ~= nil then
		list = rawget(params, "_f") or EMPTY
		local p = rawget(params, "_p")
		include = p.FilterType == Enum.RaycastFilterType.Include
		respect = p.RespectCanCollide == true
		group = p.CollisionGroup or "Default"
	end
	local key = filterKey(list)
	local found = nil
	for idx, c in caches do
		if c.root == root and c.key == key and c.include == include and c.respect == respect and c.group == group then
			found = c
			if idx ~= #caches then
				table.remove(caches, idx)
				table.insert(caches, c)
			end
			break
		end
	end
	if not found then
		found = newCache(root, key, include, respect, group)
		if #caches >= MAX_CACHES then
			table.remove(caches, 1)
		end
		table.insert(caches, found)
	end
	if found.version ~= structVersion then
		local set = {}
		for _, x in list do
			set[x] = true
		end
		found.filterSet = set
		rebuild(found)
	elseif found.anyDirty then
		refit(found)
	end
	return found
end

------------------------------------------------------------------ intersection
local stack = table.create(128, 0)

-- Returns t (fraction of dir), item index, local normal (lnx, lny, lnz) or nil.
local function cast(c, ox, oy, oz, dx, dy, dz, tmax)
	if c.n == 0 then
		return nil
	end
	local INF = math.huge
	local ix = if dx ~= 0 then 1 / dx else INF
	local iy = if dy ~= 0 then 1 / dy else INF
	local iz = if dz ~= 0 then 1 / dz else INF
	local nx0, ny0, nz0, nx1, ny1, nz1 = c.nx0, c.ny0, c.nz0, c.nx1, c.ny1, c.nz1
	local left, right, lo, hi, order = c.left, c.right, c.lo, c.hi, c.order
	local shape = c.shape
	local cxA, cyA, czA = c.cx, c.cy, c.cz
	local r0, r1, r2, r3, r4, r5, r6, r7, r8 = c.r0, c.r1, c.r2, c.r3, c.r4, c.r5, c.r6, c.r7, c.r8
	local hxA, hyA, hzA = c.hx, c.hy, c.hz
	local best = tmax
	local bestItem = 0
	local bnx, bny, bnz = 0, 0, 0
	local sp = 1
	stack[1] = 1
	local nodeTests, itemTests = 0, 0
	while sp > 0 do
		local node = stack[sp]
		sp -= 1
		nodeTests += 1
		-- slab test against the node box (handles zero direction components through +-inf)
		local t1, t2
		if ix == INF then
			if ox < nx0[node] or ox > nx1[node] then
				continue
			end
			t1, t2 = -INF, INF
		else
			t1 = (nx0[node] - ox) * ix
			t2 = (nx1[node] - ox) * ix
			if t1 > t2 then
				t1, t2 = t2, t1
			end
		end
		local u1, u2
		if iy == INF then
			if oy < ny0[node] or oy > ny1[node] then
				continue
			end
			u1, u2 = -INF, INF
		else
			u1 = (ny0[node] - oy) * iy
			u2 = (ny1[node] - oy) * iy
			if u1 > u2 then
				u1, u2 = u2, u1
			end
		end
		if u1 > t1 then t1 = u1 end
		if u2 < t2 then t2 = u2 end
		if iz == INF then
			if oz < nz0[node] or oz > nz1[node] then
				continue
			end
		else
			local w1 = (nz0[node] - oz) * iz
			local w2 = (nz1[node] - oz) * iz
			if w1 > w2 then
				w1, w2 = w2, w1
			end
			if w1 > t1 then t1 = w1 end
			if w2 < t2 then t2 = w2 end
		end
		if t1 > t2 or t2 < 0 or t1 > best then
			continue
		end
		local l = left[node]
		if l ~= 0 then
			sp += 1
			stack[sp] = right[node]
			sp += 1
			stack[sp] = l
			continue
		end
		for k = lo[node], hi[node] do
			local i = order[k]
			itemTests += 1
			local a0, a1, a2, a3, a4, a5, a6, a7, a8 = r0[i], r1[i], r2[i], r3[i], r4[i], r5[i], r6[i], r7[i], r8[i]
			local rx, ry, rz = ox - cxA[i], oy - cyA[i], oz - czA[i]
			local sh = shape[i]
			if sh == SH_BALL then
				local rad = math.min(hxA[i], hyA[i], hzA[i])
				local qa = dx * dx + dy * dy + dz * dz
				local qb = 2 * (dx * rx + dy * ry + dz * rz)
				local qc = rx * rx + ry * ry + rz * rz - rad * rad
				local disc = qb * qb - 4 * qa * qc
				if disc >= 0 and qc > 0 then
					local t = (-qb - math.sqrt(disc)) / (2 * qa)
					if t >= 0 and t < best then
						best, bestItem = t, i
						bnx, bny, bnz = (rx + dx * t) / rad, (ry + dy * t) / rad, (rz + dz * t) / rad
					end
				end
				continue
			end
			-- local ray: R^T * (o - c), R^T * d
			local lox = a0 * rx + a3 * ry + a6 * rz
			local loy = a1 * rx + a4 * ry + a7 * rz
			local loz = a2 * rx + a5 * ry + a8 * rz
			local ldx = a0 * dx + a3 * dy + a6 * dz
			local ldy = a1 * dx + a4 * dy + a7 * dz
			local ldz = a2 * dx + a5 * dy + a8 * dz
			local hx, hy, hz = hxA[i], hyA[i], hzA[i]
			if sh == SH_BLOCK then
				local te, tx = -INF, INF
				local ax = 0
				if ldx > -1e-12 and ldx < 1e-12 then
					if lox < -hx or lox > hx then
						continue
					end
				else
					local s1 = (-hx - lox) / ldx
					local s2 = (hx - lox) / ldx
					if s1 > s2 then
						s1, s2 = s2, s1
					end
					if s1 > te then
						te, ax = s1, 1
					end
					if s2 < tx then
						tx = s2
					end
				end
				if ldy > -1e-12 and ldy < 1e-12 then
					if loy < -hy or loy > hy then
						continue
					end
				else
					local s1 = (-hy - loy) / ldy
					local s2 = (hy - loy) / ldy
					if s1 > s2 then
						s1, s2 = s2, s1
					end
					if s1 > te then
						te, ax = s1, 2
					end
					if s2 < tx then
						tx = s2
					end
				end
				if ldz > -1e-12 and ldz < 1e-12 then
					if loz < -hz or loz > hz then
						continue
					end
				else
					local s1 = (-hz - loz) / ldz
					local s2 = (hz - loz) / ldz
					if s1 > s2 then
						s1, s2 = s2, s1
					end
					if s1 > te then
						te, ax = s1, 3
					end
					if s2 < tx then
						tx = s2
					end
				end
				if te <= tx and te >= 0 and te < best and ax ~= 0 then
					best, bestItem = te, i
					if ax == 1 then
						bnx, bny, bnz = if ldx > 0 then -1 else 1, 0, 0
					elseif ax == 2 then
						bnx, bny, bnz = 0, if ldy > 0 then -1 else 1, 0
					else
						bnx, bny, bnz = 0, 0, if ldz > 0 then -1 else 1
					end
					-- convert local normal to world now (stored as world below)
					local wx = a0 * bnx + a1 * bny + a2 * bnz
					local wy = a3 * bnx + a4 * bny + a5 * bnz
					local wz = a6 * bnx + a7 * bny + a8 * bnz
					bnx, bny, bnz = wx, wy, wz
				end
			elseif sh == SH_CYL then
				local rad = math.min(hy, hz)
				local te, tx = -INF, INF
				local enterCap = false
				local qa = ldy * ldy + ldz * ldz
				if qa < 1e-18 then
					if loy * loy + loz * loz > rad * rad then
						continue
					end
				else
					local qb = 2 * (loy * ldy + loz * ldz)
					local qc = loy * loy + loz * loz - rad * rad
					local disc = qb * qb - 4 * qa * qc
					if disc < 0 then
						continue
					end
					local sq = math.sqrt(disc)
					te = (-qb - sq) / (2 * qa)
					tx = (-qb + sq) / (2 * qa)
				end
				if ldx > -1e-12 and ldx < 1e-12 then
					if lox < -hx or lox > hx then
						continue
					end
				else
					local s1 = (-hx - lox) / ldx
					local s2 = (hx - lox) / ldx
					if s1 > s2 then
						s1, s2 = s2, s1
					end
					if s1 > te then
						te, enterCap = s1, true
					end
					if s2 < tx then
						tx = s2
					end
				end
				if te <= tx and te >= 0 and te < best and te > -INF then
					best, bestItem = te, i
					local lnx, lny, lnz
					if enterCap then
						lnx, lny, lnz = if ldx > 0 then -1 else 1, 0, 0
					else
						lnx, lny, lnz = 0, (loy + ldy * te) / rad, (loz + ldz * te) / rad
					end
					bnx = a0 * lnx + a1 * lny + a2 * lnz
					bny = a3 * lnx + a4 * lny + a5 * lnz
					bnz = a6 * lnx + a7 * lny + a8 * lnz
				end
			else
				local pl = c.planes[i]
				local te, tx = -INF, INF
				local en = 0
				local miss = false
				for q = 1, #pl, 4 do
					local px, py, pz, pd = pl[q], pl[q + 1], pl[q + 2], pl[q + 3]
					local denom = px * ldx + py * ldy + pz * ldz
					local num = pd - (px * lox + py * loy + pz * loz)
					if denom > -1e-12 and denom < 1e-12 then
						if num < 0 then
							miss = true
							break
						end
					else
						local t = num / denom
						if denom < 0 then
							if t > te then
								te, en = t, q
							end
						elseif t < tx then
							tx = t
						end
					end
				end
				if not miss and en ~= 0 and te <= tx and te >= 0 and te < best then
					best, bestItem = te, i
					local lnx, lny, lnz = pl[en], pl[en + 1], pl[en + 2]
					local m = math.sqrt(lnx * lnx + lny * lny + lnz * lnz)
					lnx, lny, lnz = lnx / m, lny / m, lnz / m
					bnx = a0 * lnx + a1 * lny + a2 * lnz
					bny = a3 * lnx + a4 * lny + a5 * lnz
					bnz = a6 * lnx + a7 * lny + a8 * lnz
				end
			end
		end
	end
	STATS.nodeTests += nodeTests
	STATS.itemTests += itemTests
	if bestItem == 0 then
		return nil
	end
	return best, bestItem, bnx, bny, bnz
end

------------------------------------------------------------------ public
-- Raw cast: returns part, hit x,y,z, normal x,y,z, distance (studs) or nil.
function R.castRaw(root, params, ox, oy, oz, dx, dy, dz)
	local c = cacheFor(root, params)
	local t, i, nx, ny, nz = cast(c, ox, oy, oz, dx, dy, dz, 1)
	if t == nil then
		return nil
	end
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	return c.part[i], ox + dx * t, oy + dy * t, oz + dz * t, nx, ny, nz, t * len
end

local function raycast(self, origin, dir, params)
	if not E.isV3(origin) or not E.isV3(dir) then
		error("Raycast: Vector3 expected", 2)
	end
	if params ~= nil and E.typeof(params) ~= "RaycastParams" then
		error("Raycast: RaycastParams expected, got " .. E.typeof(params), 2)
	end
	STATS.rays += 1
	E.stats.raycasts = (E.stats.raycasts or 0) + 1
	local ox, oy, oz, dx, dy, dz = origin.X, origin.Y, origin.Z, dir.X, dir.Y, dir.Z
	if dx ~= dx or dy ~= dy or dz ~= dz or ox ~= ox or oy ~= oy or oz ~= oz then
		return nil
	end
	local part, hx, hy, hz, nx, ny, nz, dist = R.castRaw(self, params, ox, oy, oz, dx, dy, dz)
	if part == nil then
		return nil
	end
	local mat = getD(part).props.Material or Enum.Material.Plastic
	return E.mkRaycastResult({
		Instance = part,
		Position = v3(hx, hy, hz),
		Normal = v3(nx, ny, nz),
		Material = mat,
		Distance = dist,
	})
end
R.raycast = raycast
I.IMPL.WorldRoot.Raycast = raycast

return R
