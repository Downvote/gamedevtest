-- Fake Roblox engine for the integrated simulation and the previews (tools/; never shipped in the place).
-- Loads the real src/ modules by Rojo instance path (loadstring + setfenv, chunk names = instance full names), runs
-- them against a simulated clock, defs-validated instances, in-process remotes with Roblox serialization checks and
-- in-memory web services. Anything the fake does not implement raises "FAKE-GAP" loudly.
local DEFS = require("./defs_gen")
local REAL = {
	print = print,
	typeof = typeof,
	os = os,
	error = error,
	tostring = tostring,
}

local E = {}
E.verbose = false
E.netLatency = 0.03
E.isStudio = false
E.errors = {} -- { {kind, msg, trace, ctx, t} }
E.issues = {} -- engine-detected API misuse { {kind, msg, ctx, t} }
E.warnings = {} -- warn() output { {ctx, text, t} }
E.prints = {}
E.frame = 0

------------------------------------------------------------------ clock
local SIM = { now = 1792713600.0, clockBase = 0, lastClock = 0 }
E.SIM = SIM
function E.now()
	return SIM.now
end
function E.setTime(t)
	SIM.now = t
end
local function simClock()
	-- os.clock: simulated seconds, strictly increasing by a tiny step per call so CPU-budget loops terminate
	local base = SIM.now - 1792000000
	local v = math.max(SIM.lastClock, base) + 1e-5
	SIM.lastClock = v
	return v
end

------------------------------------------------------------------ contexts / logging
local MAIN_CTX = { name = "harness", kind = "harness", alive = true, modules = {} }
E.mainCtx = MAIN_CTX
local coCtx = setmetatable({}, { __mode = "k" })
local function curCtx()
	local co = coroutine.running()
	return coCtx[co] or MAIN_CTX
end
E.curCtx = curCtx

local function fmtTime()
	return string.format("%8.2f", SIM.now - (E.t0 or SIM.now))
end
local function out(line)
	REAL.print(line)
end
E.out = out

local function argsText(...)
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

function E.recordError(kind, msg, trace, ctx)
	ctx = ctx or curCtx()
	local e = { kind = kind, msg = tostring(msg), trace = trace or "", ctx = ctx.name, t = SIM.now - (E.t0 or SIM.now), phase = E.phase }
	table.insert(E.errors, e)
	out(string.format("[%s] !!ERROR %s (%s) [%s]: %s\n%s", fmtTime(), kind, ctx.name, tostring(E.phase), e.msg, e.trace))
end
function E.issue(kind, msg)
	local ctx = curCtx()
	local tb = debug.traceback("", 3)
	table.insert(E.issues, { kind = kind, msg = msg, ctx = ctx.name, t = SIM.now - (E.t0 or SIM.now), trace = tb, phase = E.phase })
	out(string.format("[%s] !!ISSUE %s (%s): %s%s", fmtTime(), kind, ctx.name, msg, tb))
end
local function gap(what)
	error("FAKE-GAP: " .. what, 3)
end
E.gap = gap

------------------------------------------------------------------ scheduler
local heap = {}
local seqN = 0
local function hless(a, b)
	if a.t ~= b.t then
		return a.t < b.t
	end
	return a.seq < b.seq
end
local function hpush(e)
	seqN += 1
	e.seq = seqN
	table.insert(heap, e)
	local i = #heap
	while i > 1 do
		local p = i // 2
		if hless(heap[i], heap[p]) then
			heap[i], heap[p] = heap[p], heap[i]
			i = p
		else
			break
		end
	end
end
local function hpop()
	local n = #heap
	if n == 0 then
		return nil
	end
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = 2 * i, 2 * i + 1
		local m = i
		if l <= n and hless(heap[l], heap[m]) then
			m = l
		end
		if r <= n and hless(heap[r], heap[m]) then
			m = r
		end
		if m == i then
			break
		end
		heap[i], heap[m] = heap[m], heap[i]
		i = m
	end
	return top
end

local cancelled = setmetatable({}, { __mode = "k" })
local deferred = {}

local function threadError(co, err)
	local tb = debug.traceback(co)
	E.recordError("thread", err, tb, coCtx[co])
end

-- profiling (off unless E.prof is set): the real CPU of every resume, exclusive of threads it resumed in turn,
-- reported to E.prof(rootFn, seconds, ctx)
local coFn = setmetatable({}, { __mode = "k" })
local profStack = {}
local realClock = REAL.os.clock
local function resume(co, ...)
	if cancelled[co] or coroutine.status(co) ~= "suspended" then
		return
	end
	local ctx = coCtx[co]
	if ctx and not ctx.alive then
		return
	end
	local prof = E.prof
	local t0, ok, err
	if prof then
		t0 = realClock()
		table.insert(profStack, 0)
		ok, err = coroutine.resume(co, ...)
		local inner = table.remove(profStack)
		local dt = realClock() - t0
		prof(coFn[co], dt - inner, ctx)
		local n = #profStack
		if n > 0 then
			profStack[n] += dt
		end
	else
		ok, err = coroutine.resume(co, ...)
	end
	if not ok then
		threadError(co, err)
	end
end
E.resume = resume

local function newThread(fn, ctx)
	local co = coroutine.create(fn)
	coCtx[co] = ctx or curCtx()
	coFn[co] = fn
	return co
end
E.newThread = newThread
function E.tagThread(th, ctx)
	coCtx[th] = ctx
end
E.simClock = simClock

local function flushDeferred()
	local guard = 0
	while #deferred > 0 do
		guard += 1
		if guard > 100000 then
			E.issue("scheduler", "deferred queue does not drain (re-entrant defer loop?)")
			table.clear(deferred)
			break
		end
		local batch = deferred
		deferred = {}
		for _, d in batch do
			if d.co then
				resume(d.co, table.unpack(d.args, 1, d.args.n))
			elseif d.conn and not d.conn.Connected then
				-- disconnected before the deferred invocation: Roblox skips it
			else
				local ctx = d.ctx
				if ctx == nil or ctx.alive then
					local co = newThread(d.fn, ctx)
					resume(co, table.unpack(d.args, 1, d.args.n))
				end
			end
		end
	end
end
E.flushDeferred = flushDeferred

function E.pushDeferred(c, args)
	table.insert(deferred, { fn = c.fn, ctx = c.ctx, args = args, conn = c })
end

local function schedule(at, fn, ctx)
	hpush({ t = at, fn = fn, ctx = ctx })
end
E.schedule = schedule

local task = {}
function task.spawn(f, ...)
	local co = if type(f) == "thread" then f else newThread(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = if type(f) == "thread" then f else newThread(f)
	table.insert(deferred, { co = co, args = table.pack(...) })
	return co
end
function task.delay(t, f, ...)
	local co = if type(f) == "thread" then f else newThread(f)
	local args = table.pack(...)
	hpush({ t = SIM.now + math.max(tonumber(t) or 0, 1e-6), co = co, args = args })
	return co
end
function task.wait(t)
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		error("task.wait called from a non-yieldable thread", 2)
	end
	local start = SIM.now
	hpush({ t = SIM.now + math.max(tonumber(t) or 0, 1e-6), co = co, args = nil, waitStart = start })
	return coroutine.yield()
end
function task.cancel(co)
	cancelled[co] = true
	pcall(coroutine.close, co)
end
function task.synchronize() end
function task.desynchronize() end
E.task = task

local function runEntry(e)
	if e.fn then
		local ctx = e.ctx
		if ctx and not ctx.alive then
			return
		end
		local co = newThread(e.fn, ctx or MAIN_CTX)
		resume(co)
	elseif e.co then
		if e.waitStart then
			resume(e.co, SIM.now - e.waitStart)
		else
			resume(e.co, table.unpack(e.args, 1, e.args.n))
		end
	end
end

function E.runTimers()
	local guard = 0
	while heap[1] and heap[1].t <= SIM.now do
		guard += 1
		if guard > 200000 then
			E.issue("scheduler", "timer storm: >200000 timers due in one frame")
			break
		end
		local e = hpop()
		runEntry(e)
		flushDeferred()
	end
end
function E.pendingTimers()
	return #heap
end

------------------------------------------------------------------ datatypes
local TYPEOF = setmetatable({}, { __mode = "k" }) -- metatable -> type name
local function typeOf(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt then
			local n = TYPEOF[mt]
			if n then
				return n
			end
		end
	end
	return REAL.typeof(v)
end
E.typeof = typeOf
function E.TYPEOF_REGISTER(mt, name)
	TYPEOF[mt] = name
end

local function immutable(name)
	return function(_, k)
		error(tostring(k) .. " cannot be assigned to", 2)
	end
end

-- Vector3
local V3 = {}
local V3MT = { __newindex = immutable("Vector3") }
TYPEOF[V3MT] = "Vector3"
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3MT)
end
local V3M = {}
V3MT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" or k == "y" or k == "z" then
		return rawget(v, string.upper(k))
	end
	local f = V3M[k]
	if f then
		return f
	end
	error(tostring(k) .. " is not a valid member of Vector3", 2)
end
local function isV3(v)
	return getmetatable(v) == V3MT
end
V3MT.__add = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid Vector3 addition", 2)
	end
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3MT.__sub = function(a, b)
	if not isV3(a) or not isV3(b) then
		error("invalid Vector3 subtraction", 2)
	end
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3MT.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	error("invalid Vector3 multiplication", 2)
end
V3MT.__div = function(a, b)
	if type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	elseif isV3(a) and isV3(b) then
		return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
	end
	error("invalid Vector3 division", 2)
end
V3MT.__idiv = function(a, b)
	return v3(a.X // b, a.Y // b, a.Z // b)
end
V3MT.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3MT.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3M.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3M.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function V3M.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function V3M.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function V3M.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function V3M.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function V3M.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
function V3M.Angle(a, b)
	local d = V3M.Dot(a, b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
V3.new = function(x, y, z)
	return v3(x, y, z)
end
V3.zero = v3(0, 0, 0)
V3.one = v3(1, 1, 1)
V3.xAxis = v3(1, 0, 0)
V3.yAxis = v3(0, 1, 0)
V3.zAxis = v3(0, 0, 1)
V3.FromNormalId = function()
	gap("Vector3.FromNormalId")
end
E.v3 = v3

-- Vector2
local V2 = {}
local V2MT = { __newindex = immutable("Vector2") }
TYPEOF[V2MT] = "Vector2"
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2MT)
end
local V2M = {}
V2MT.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return v2(v.X / m, v.Y / m)
	end
	local f = V2M[k]
	if f then
		return f
	end
	error(tostring(k) .. " is not a valid member of Vector2", 2)
end
local function isV2(v)
	return getmetatable(v) == V2MT
end
V2MT.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2MT.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2MT.__mul = function(a, b)
	if type(a) == "number" then
		return v2(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2MT.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2MT.__tostring = function(a)
	return string.format("%g, %g", a.X, a.Y)
end
function V2M.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function V2M.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function V2M.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function V2M.Min(a, b)
	return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function V2M.Max(a, b)
	return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function V2M.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
V2.new = function(x, y)
	return v2(x, y)
end
V2.zero = v2(0, 0)
V2.one = v2(1, 1)
V2.xAxis = v2(1, 0)
V2.yAxis = v2(0, 1)
E.v2 = v2

-- CFrame (3x4)
local CF = {}
local CFMT = { __newindex = immutable("CFrame") }
TYPEOF[CFMT] = "CFrame"
local function cfr(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	return setmetatable({ X = x, Y = y, Z = z, _r = { r00, r01, r02, r10, r11, r12, r20, r21, r22 } }, CFMT)
end
local function isCF(v)
	return getmetatable(v) == CFMT
end
local CFM = {}
CFMT.__index = function(c, k)
	local r = rawget(c, "_r")
	if k == "Position" or k == "p" then
		return v3(c.X, c.Y, c.Z)
	elseif k == "Rotation" then
		return cfr(0, 0, 0, table.unpack(r))
	elseif k == "LookVector" or k == "lookVector" then
		return v3(-r[3], -r[6], -r[9])
	elseif k == "RightVector" or k == "XVector" then
		return v3(r[1], r[4], r[7])
	elseif k == "UpVector" or k == "YVector" then
		return v3(r[2], r[5], r[8])
	elseif k == "ZVector" then
		return v3(r[3], r[6], r[9])
	elseif k == "x" or k == "y" or k == "z" then
		return rawget(c, string.upper(k))
	end
	local f = CFM[k]
	if f then
		return f
	end
	error(tostring(k) .. " is not a valid member of CFrame", 2)
end
local function cfMul(a, b)
	local A, B = a._r, b._r
	return cfr(
		A[1] * b.X + A[2] * b.Y + A[3] * b.Z + a.X,
		A[4] * b.X + A[5] * b.Y + A[6] * b.Z + a.Y,
		A[7] * b.X + A[8] * b.Y + A[9] * b.Z + a.Z,
		A[1] * B[1] + A[2] * B[4] + A[3] * B[7],
		A[1] * B[2] + A[2] * B[5] + A[3] * B[8],
		A[1] * B[3] + A[2] * B[6] + A[3] * B[9],
		A[4] * B[1] + A[5] * B[4] + A[6] * B[7],
		A[4] * B[2] + A[5] * B[5] + A[6] * B[8],
		A[4] * B[3] + A[5] * B[6] + A[6] * B[9],
		A[7] * B[1] + A[8] * B[4] + A[9] * B[7],
		A[7] * B[2] + A[8] * B[5] + A[9] * B[8],
		A[7] * B[3] + A[8] * B[6] + A[9] * B[9]
	)
end
local function cfApply(a, v)
	local A = a._r
	return v3(A[1] * v.X + A[2] * v.Y + A[3] * v.Z + a.X, A[4] * v.X + A[5] * v.Y + A[6] * v.Z + a.Y, A[7] * v.X + A[8] * v.Y + A[9] * v.Z + a.Z)
end
local function cfInv(a)
	local A = a._r
	local x, y, z = a.X, a.Y, a.Z
	return cfr(
		-(A[1] * x + A[4] * y + A[7] * z),
		-(A[2] * x + A[5] * y + A[8] * z),
		-(A[3] * x + A[6] * y + A[9] * z),
		A[1], A[4], A[7], A[2], A[5], A[8], A[3], A[6], A[9]
	)
end
CFMT.__mul = function(a, b)
	if not isCF(a) then
		error("invalid CFrame multiplication (lhs " .. typeOf(a) .. ")", 2)
	end
	if isCF(b) then
		return cfMul(a, b)
	elseif isV3(b) then
		return cfApply(a, b)
	end
	error("invalid CFrame multiplication (rhs " .. typeOf(b) .. ")", 2)
end
CFMT.__add = function(a, b)
	if not isCF(a) or not isV3(b) then
		error("invalid CFrame addition", 2)
	end
	local r = a._r
	return cfr(a.X + b.X, a.Y + b.Y, a.Z + b.Z, table.unpack(r))
end
CFMT.__sub = function(a, b)
	if not isCF(a) or not isV3(b) then
		error("invalid CFrame subtraction", 2)
	end
	local r = a._r
	return cfr(a.X - b.X, a.Y - b.Y, a.Z - b.Z, table.unpack(r))
end
CFMT.__eq = function(a, b)
	if a.X ~= b.X or a.Y ~= b.Y or a.Z ~= b.Z then
		return false
	end
	for i = 1, 9 do
		if a._r[i] ~= b._r[i] then
			return false
		end
	end
	return true
end
CFMT.__tostring = function(a)
	return string.format("%g, %g, %g, %s", a.X, a.Y, a.Z, table.concat(a._r, ", "))
end
function CFM.Inverse(a)
	return cfInv(a)
end
function CFM.inverse(a)
	return cfInv(a)
end
function CFM.PointToWorldSpace(a, v)
	return cfApply(a, v)
end
function CFM.PointToObjectSpace(a, v)
	return cfApply(cfInv(a), v)
end
function CFM.VectorToWorldSpace(a, v)
	local A = a._r
	return v3(A[1] * v.X + A[2] * v.Y + A[3] * v.Z, A[4] * v.X + A[5] * v.Y + A[6] * v.Z, A[7] * v.X + A[8] * v.Y + A[9] * v.Z)
end
function CFM.VectorToObjectSpace(a, v)
	local A = a._r
	return v3(A[1] * v.X + A[4] * v.Y + A[7] * v.Z, A[2] * v.X + A[5] * v.Y + A[8] * v.Z, A[3] * v.X + A[6] * v.Y + A[9] * v.Z)
end
function CFM.ToWorldSpace(a, b)
	return cfMul(a, b)
end
function CFM.ToObjectSpace(a, b)
	return cfMul(cfInv(a), b)
end
function CFM.GetComponents(a)
	local r = a._r
	return a.X, a.Y, a.Z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9]
end
CFM.components = CFM.GetComponents
local function orthonormalize(r)
	-- Gram-Schmidt on columns
	local x = v3(r[1], r[4], r[7])
	local y = v3(r[2], r[5], r[8])
	x = x.Unit
	y = (y - x * x:Dot(y)).Unit
	local z = x:Cross(y)
	return { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }
end
function CFM.Lerp(a, b, t)
	local r = {}
	for i = 1, 9 do
		r[i] = a._r[i] + (b._r[i] - a._r[i]) * t
	end
	local ok, o = pcall(orthonormalize, r)
	if not ok or o[1] ~= o[1] then
		o = if t < 0.5 then a._r else b._r
	end
	return cfr(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t, table.unpack(o))
end
function CFM.Orthonormalize(a)
	return cfr(a.X, a.Y, a.Z, table.unpack(orthonormalize(a._r)))
end
function CFM.ToEulerAnglesXYZ(a)
	local r = a._r
	local ry = math.asin(math.clamp(r[3], -1, 1))
	local rx, rz
	if math.abs(r[3]) < 0.9999999 then
		rx = math.atan2(-r[6], r[9])
		rz = math.atan2(-r[2], r[1])
	else
		rx = math.atan2(r[8], r[5])
		rz = 0
	end
	return rx, ry, rz
end
function CFM.ToEulerAnglesYXZ(a)
	local r = a._r
	local rx = math.asin(math.clamp(-r[6], -1, 1))
	local ry, rz
	if math.abs(r[6]) < 0.9999999 then
		ry = math.atan2(r[3], r[9])
		rz = math.atan2(r[4], r[5])
	else
		ry = math.atan2(-r[7], r[1])
		rz = 0
	end
	return rx, ry, rz
end
CFM.ToOrientation = CFM.ToEulerAnglesYXZ
function CFM.ToAxisAngle(a)
	gap("CFrame:ToAxisAngle")
end
function CFM.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	if math.abs(a.X - b.X) > eps or math.abs(a.Y - b.Y) > eps or math.abs(a.Z - b.Z) > eps then
		return false
	end
	for i = 1, 9 do
		if math.abs(a._r[i] - b._r[i]) > eps then
			return false
		end
	end
	return true
end
local function rotX(a)
	local c, s = math.cos(a), math.sin(a)
	return cfr(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(a)
	local c, s = math.cos(a), math.sin(a)
	return cfr(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(a)
	local c, s = math.cos(a), math.sin(a)
	return cfr(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end
local IDENT = cfr(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
local function lookAt(at, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - at)
	if look.Magnitude < 1e-9 then
		return cfr(at.X, at.Y, at.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-9 then
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local u = right:Cross(look)
	return cfr(at.X, at.Y, at.Z, right.X, u.X, -look.X, right.Y, u.Y, -look.Y, right.Z, u.Z, -look.Z)
end
CF.new = function(...)
	local n = select("#", ...)
	if n == 0 then
		return IDENT
	end
	local a, b = ...
	if n == 1 and isV3(a) then
		return cfr(a.X, a.Y, a.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 2 and isV3(a) and isV3(b) then
		return lookAt(a, b)
	elseif n == 3 then
		local x, y, z = ...
		if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
			error("CFrame.new: bad arguments", 2)
		end
		return cfr(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	elseif n == 7 then
		gap("CFrame.new quaternion form")
	elseif n == 12 then
		return cfr(...)
	end
	error("CFrame.new: unsupported argument form (" .. n .. " args)", 2)
end
CF.Angles = function(rx, ry, rz)
	return cfMul(cfMul(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))
end
CF.fromEulerAnglesXYZ = CF.Angles
CF.fromEulerAnglesYXZ = function(rx, ry, rz)
	return cfMul(cfMul(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0))
end
CF.fromOrientation = CF.fromEulerAnglesYXZ
CF.lookAt = function(at, target, up)
	return lookAt(at, target, up)
end
CF.lookAlong = function(at, dir, up)
	return lookAt(at, at + dir, up)
end
CF.fromAxisAngle = function(axis, ang)
	local u = axis.Unit
	local c, s = math.cos(ang), math.sin(ang)
	local t = 1 - c
	local x, y, z = u.X, u.Y, u.Z
	return cfr(0, 0, 0, t * x * x + c, t * x * y - s * z, t * x * z + s * y, t * x * y + s * z, t * y * y + c, t * y * z - s * x, t * x * z - s * y, t * y * z + s * x, t * z * z + c)
end
CF.fromMatrix = function(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cfr(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
CF.identity = IDENT
E.cf = CF

-- Color3
local C3 = {}
local C3MT = { __newindex = immutable("Color3") }
TYPEOF[C3MT] = "Color3"
local C3M = {}
local function c3(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3MT)
end
C3MT.__index = function(c, k)
	local f = C3M[k]
	if f then
		return f
	end
	if k == "r" or k == "g" or k == "b" then
		return rawget(c, string.upper(k))
	end
	error(tostring(k) .. " is not a valid member of Color3", 2)
end
C3MT.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3MT.__tostring = function(a)
	return string.format("%g, %g, %g", a.R, a.G, a.B)
end
function C3M.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3M.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local h, s, v = 0, 0, mx
	local d = mx - mn
	if mx > 0 then
		s = d / mx
	end
	if d > 0 then
		if mx == r then
			h = (g - b) / d % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h /= 6
	end
	return h, s, v
end
function C3M.ToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
C3.new = function(r, g, b)
	return c3(r, g, b)
end
C3.fromRGB = function(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
C3.fromHSV = function(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return c3(v, t, p)
	elseif i == 1 then
		return c3(q, v, p)
	elseif i == 2 then
		return c3(p, v, t)
	elseif i == 3 then
		return c3(p, q, v)
	elseif i == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
C3.fromHex = function(hex)
	hex = string.gsub(hex, "#", "")
	return c3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
end
C3.toHSV = function(c)
	return C3M.ToHSV(c)
end

-- UDim / UDim2
local UD = {}
local UDMT = { __newindex = immutable("UDim") }
TYPEOF[UDMT] = "UDim"
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0 }, UDMT)
end
UDMT.__index = function(_, k)
	error(tostring(k) .. " is not a valid member of UDim", 2)
end
UDMT.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDMT.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDMT.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDMT.__tostring = function(a)
	return string.format("%g, %g", a.Scale, a.Offset)
end
UD.new = function(s, o)
	return udim(s, o)
end
local UD2 = {}
local UD2MT = { __newindex = immutable("UDim2") }
TYPEOF[UD2MT] = "UDim2"
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, UD2MT)
end
UD2MT.__index = function(u, k)
	if k == "Width" then
		return u.X
	elseif k == "Height" then
		return u.Y
	elseif k == "Lerp" then
		return function(a, b, t)
			return udim2(a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t, a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t)
		end
	end
	error(tostring(k) .. " is not a valid member of UDim2", 2)
end
UD2MT.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UD2MT.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UD2MT.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UD2MT.__tostring = function(a)
	return "{" .. tostring(a.X) .. "}, {" .. tostring(a.Y) .. "}"
end
UD2.new = function(a, b, c, d)
	if getmetatable(a) == UDMT then
		return setmetatable({ X = a, Y = b }, UD2MT)
	end
	for _, x in { a or 0, b or 0, c or 0, d or 0 } do
		if type(x) ~= "number" then
			error("UDim2.new: number expected, got " .. typeOf(x), 2)
		end
	end
	return udim2(a, b, c, d)
end
UD2.fromOffset = function(x, y)
	return udim2(0, x or 0, 0, y or 0)
end
UD2.fromScale = function(x, y)
	return udim2(x or 0, 0, y or 0, 0)
end

-- misc value types
local function valueType(name, fields)
	local mt = { __newindex = immutable(name) }
	mt.__index = function(_, k)
		error(tostring(k) .. " is not a valid member of " .. name, 2)
	end
	TYPEOF[mt] = name
	return function(t)
		return setmetatable(t, mt)
	end, mt
end
local mkTweenInfo = valueType("TweenInfo")
local TweenInfo = {
	new = function(time, style, dir, repeatCount, reverses, delayTime)
		return mkTweenInfo({ Time = time or 1, EasingStyle = style, EasingDirection = dir, RepeatCount = repeatCount or 0, Reverses = reverses or false, DelayTime = delayTime or 0 })
	end,
}
local mkCSK = valueType("ColorSequenceKeypoint")
local mkCS = valueType("ColorSequence")
local ColorSequenceKeypoint = {
	new = function(t, c)
		return mkCSK({ Time = t, Value = c })
	end,
}
local ColorSequence = {
	new = function(a, b)
		if typeOf(a) == "Color3" then
			return mkCS({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } })
		end
		if type(a) ~= "table" then
			error("ColorSequence.new: bad argument", 2)
		end
		return mkCS({ Keypoints = a })
	end,
}
local mkNSK = valueType("NumberSequenceKeypoint")
local mkNS = valueType("NumberSequence")
local NumberSequenceKeypoint = {
	new = function(t, v, e)
		return mkNSK({ Time = t, Value = v, Envelope = e or 0 })
	end,
}
local NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			return mkNS({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } })
		end
		return mkNS({ Keypoints = a })
	end,
}
local mkNR = valueType("NumberRange")
local NumberRange = {
	new = function(a, b)
		return mkNR({ Min = a, Max = b or a })
	end,
}
local mkRect = valueType("Rect")
local Rect = {
	new = function(a, b, c, d)
		if typeOf(a) == "Vector2" then
			return mkRect({ Min = a, Max = b, Width = b.X - a.X, Height = b.Y - a.Y })
		end
		return mkRect({ Min = v2(a, b), Max = v2(c, d), Width = c - a, Height = d - b })
	end,
}
local mkContent, ContentMT = valueType("Content")
local Content = {
	none = mkContent({ SourceType = "None" }),
	fromObject = function(obj)
		if obj == nil then
			error("Content.fromObject: object expected", 2)
		end
		return mkContent({ SourceType = "Object", Object = obj })
	end,
	fromUri = function(u)
		return mkContent({ SourceType = "Uri", Uri = u })
	end,
}
local mkFont = valueType("Font")
local Font = {
	new = function(family, weight, style)
		return mkFont({ Family = family, Weight = weight, Style = style })
	end,
	fromEnum = function(e)
		return mkFont({ Family = "rbxasset://fonts/families/" .. tostring(e) .. ".json" })
	end,
	fromName = function(n, weight, style)
		return mkFont({ Family = "rbxasset://fonts/families/" .. n .. ".json", Weight = weight, Style = style })
	end,
	fromId = function(id)
		return mkFont({ Family = "rbxassetid://" .. tostring(id) })
	end,
}
local mkRaycastResult = valueType("RaycastResult")

-- Random
local RandomMT = {}
TYPEOF[RandomMT] = "Random"
local RandomM = {}
RandomMT.__index = RandomM
local randSeed = 12345
local function newRandom(seed)
	if seed == nil then
		randSeed += 7919
		seed = randSeed
	end
	local s = math.floor(seed) % 4294967296
	if s == 0 then
		s = 0x9E3779B9
	end
	return setmetatable({ s = s }, RandomMT)
end
function RandomM:_next()
	local x = self.s
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.s = x
	return x / 4294967296
end
function RandomM:NextNumber(a, b)
	a = a or 0
	b = b or 1
	return a + self:_next() * (b - a)
end
function RandomM:NextInteger(a, b)
	return a + math.floor(self:_next() * (b - a + 1))
end
function RandomM:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function RandomM:Clone()
	return setmetatable({ s = self.s }, RandomMT)
end
local RandomLib = { new = newRandom }

------------------------------------------------------------------ Enum
local EnumItemMT = {}
TYPEOF[EnumItemMT] = "EnumItem"
local EnumMT = {}
TYPEOF[EnumMT] = "Enum"
local EnumsMT = {}
TYPEOF[EnumsMT] = "Enums"
local ENUM_VALUES = {
	RenderPriority = { First = 0, Input = 100, Camera = 200, Character = 300, Last = 2000 },
	ProductPurchaseDecision = { NotProcessedYet = 0, PurchaseGranted = 1 },
}
local enumCache = {}
local function makeEnum(name)
	local items = DEFS.enums[name]
	if not items then
		return nil
	end
	local en = setmetatable({ __name = name, __items = {}, __list = {} }, EnumMT)
	for i, itemName in items do
		local val = (ENUM_VALUES[name] and ENUM_VALUES[name][itemName]) or (i - 1)
		local item = setmetatable({ Name = itemName, Value = val, EnumType = en, __full = "Enum." .. name .. "." .. itemName }, EnumItemMT)
		en.__items[itemName] = item
		table.insert(en.__list, item)
	end
	return en
end
EnumItemMT.__index = function(item, k)
	if k == "IsA" then
		return function(self, n)
			return rawget(rawget(self, "EnumType"), "__name") == n
		end
	end
	error(tostring(k) .. " is not a valid member of EnumItem " .. rawget(item, "__full"), 2)
end
EnumItemMT.__newindex = immutable("EnumItem")
EnumItemMT.__tostring = function(item)
	return rawget(item, "__full")
end
EnumMT.__index = function(en, k)
	local item = rawget(en, "__items")[k]
	if item then
		return item
	end
	if k == "GetEnumItems" then
		return function(self)
			return table.clone(rawget(self, "__list"))
		end
	elseif k == "FromName" then
		return function(self, n)
			return rawget(self, "__items")[n]
		end
	elseif k == "FromValue" then
		return function(self, v)
			for _, it in rawget(self, "__list") do
				if it.Value == v then
					return it
				end
			end
			return nil
		end
	end
	error(tostring(k) .. " is not a valid member of \"Enum." .. rawget(en, "__name") .. "\"", 2)
end
EnumMT.__newindex = immutable("Enum")
EnumMT.__tostring = function(en)
	return rawget(en, "__name")
end
local Enum = setmetatable({}, EnumsMT)
EnumsMT.__index = function(_, k)
	local en = enumCache[k]
	if en == nil then
		en = makeEnum(k)
		if en == nil then
			error(tostring(k) .. " is not a valid member of \"Enum\"", 2)
		end
		enumCache[k] = en
	end
	return en
end
EnumsMT.__newindex = immutable("Enums")
E.Enum = Enum
local function isEnumItem(v)
	return getmetatable(v) == EnumItemMT
end

E.types = {
	Vector3 = V3, Vector2 = V2, CFrame = CF, Color3 = C3, UDim = UD, UDim2 = UD2, TweenInfo = TweenInfo,
	ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint, NumberRange = NumberRange, Rect = Rect, Content = Content,
	Font = Font, Random = RandomLib,
}
E.isV3, E.isCF = isV3, isCF
E.c3 = c3
E.mkRaycastResult = mkRaycastResult

return E
