--!strict
-- What moves on the islands (GAME_DESIGN 11; docs/ARCHITECTURE.md 10.2). The request of 2026-11-14: "other models
-- should be animated if possible too, such as windmills being able to spin". A windmill's sails, a waterwheel's rim,
-- spokes and paddles, and the Grand Mill's paddles leave the baked picture (PixelRenderer.hideStatic: the static part
-- looked through) and turn as a moving model of their own round their hub (PixelRenderer.registerDynamic). Since the
-- request of 2026-11-19 ("detail all decor more, some having animations, as much as in the bakery game") any part a
-- builder marked with Models/Parts.move moves the same way: it spins (a carousel, a big wheel, a clock's hands),
-- swings (a swing's seat, a hammock, a bell, wind chimes) or bobs (a buoy, a boat on its mooring). The piece's model
-- carries its frame (DecorModels.build's "At" attribute), so the hub and the axis come from the piece's own builder.
-- At most MAX_MOVING pieces move at a time, the ones on the screen nearest the view's middle; a piece let go (off the
-- screen, past the cap, reduced motion) has its parts back in the baked picture at rest (PixelRenderer.showStatic). A
-- piece moved, rebuilt or cleared away drops its copy; the new model gets a new one.
--   start(), debugState()
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)

local Spinners = {}

-- The buildings that turned before parts carried their own motion: their parts by name, the hub in the piece's frame,
-- the axis and the speed (radians a second; a wheel turned by the stream goes the other way round).
type Spec = { parts: { [string]: boolean }, hub: Vector3, axis: string, speed: number }
local SPECS: { [string]: Spec } = {
	windmill = { parts = { SailArm = true, Sail = true }, hub = Vector3.new(0, 3.4, 0.9), axis = "Z", speed = 0.9 },
	waterwheel = { parts = { Rim = true, Spoke = true, Paddle = true }, hub = Vector3.new(0, 1.2, 0), axis = "Z", speed = -0.7 },
	grandmill = { parts = { Paddle = true }, hub = Vector3.new(1.6, 1.5, -0.6), axis = "X", speed = 0.7 },
}
local SCAN_SECS = 1 -- the islands near the view looked over this often
local NEAR = 220 -- studs from the view's middle (along the street) an island is near
local MAX_MOVING = 40 -- pieces moving at a time (each a model the pixel filter draws every tick)
local SCREEN_PAD = 40 -- art px off the screen a piece may stand and still move
local AXES: { [string]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

-- A moving part as its builder marked it (Parts.move): what it does, round what, how fast and how far.
type Plan = { part: BasePart, kind: string, hub: Vector3, axis: string, speed: number, amp: number, phase: number }
type Mover = { p: BasePart, off: CFrame, kind: string, hub: CFrame, axis: Vector3, speed: number, amp: number, phase: number }
type Spin = { model: Model, copy: Model, at: Vector3, movers: { Mover }, originals: { BasePart } }
local spins: { [Model]: Spin } = {}
-- (each piece's moving parts, looked for once: false for a piece with none)
local plans: { [Model]: { Plan } | false } = setmetatable({} :: any, { __mode = "k" })
local scanAt = 0

local function dynFolder(): Folder
	local f = workspace:FindFirstChild("PixelDynamic")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
end

local function quiet(): boolean
	local ok, on = pcall(function(): boolean
		return GuiService.ReducedMotionEnabled
	end)
	return ok and on == true
end

-- A piece's moving parts: the ones its builder marked (Move attributes), or an older building's by its SPECS.
local function planOf(m: Model, id: string): { Plan } | false
	local known = plans[m]
	if known ~= nil then
		return known :: any
	end
	local spec = SPECS[id]
	local list: { Plan } = {}
	for _, d in m:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local kind = d:GetAttribute("Move")
		local hub = d:GetAttribute("MoveHub")
		if type(kind) == "string" and typeof(hub) == "Vector3" then
			local axis = d:GetAttribute("MoveAxis")
			local speed, amp, phase = d:GetAttribute("MoveSpeed"), d:GetAttribute("MoveAmp"), d:GetAttribute("MovePhase")
			table.insert(list, {
				part = d,
				kind = kind,
				hub = hub,
				axis = if type(axis) == "string" and AXES[axis] then axis else "Y",
				speed = if type(speed) == "number" then speed else 1,
				amp = if type(amp) == "number" then amp else 0,
				phase = if type(phase) == "number" then phase else 0,
			})
		elseif spec and spec.parts[d.Name] then
			table.insert(list, { part = d, kind = "spin", hub = spec.hub, axis = spec.axis, speed = spec.speed, amp = 0, phase = 0 })
		end
	end
	local out: { Plan } | false = if #list > 0 then list else false
	plans[m] = out
	return out
end

local function drop(s: Spin, restore: boolean)
	PixelRenderer.unregisterDynamic(s.copy)
	s.copy:Destroy()
	if restore then
		for _, d in s.originals do
			if d.Parent then
				PixelRenderer.showStatic(d)
			end
		end
	end
	spins[s.model] = nil
end

-- A piece's moving copy: its moving parts cloned into a model the pixel filter draws every tick, the originals out
-- of the picture.
local function make(m: Model, plan: { Plan }): Spin?
	local at = m:GetAttribute("At")
	if typeof(at) ~= "CFrame" then
		return nil
	end
	local copy = Instance.new("Model")
	copy.Name = "Spin_" .. m.Name
	local movers: { Mover } = {}
	local originals: { BasePart } = {}
	-- (each piece a little out of step with the next)
	local base = (#m.Name * 0.37 + at.Position.X * 0.11) % (math.pi * 2)
	for _, e in plan do
		local d = e.part
		if d.Parent == nil or (d.Transparency >= 0.95 and d:GetAttribute("PixelWasT") == nil) then
			continue
		end
		local hub = at * CFrame.new(e.hub)
		local c = d:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
		local was = d:GetAttribute("PixelWasT")
		c.Transparency = if type(was) == "number" then was else d.Transparency
		c.Parent = copy
		table.insert(movers, { p = c, off = hub:ToObjectSpace(d.CFrame), kind = e.kind, hub = hub, axis = AXES[e.axis], speed = e.speed, amp = e.amp, phase = base + e.phase })
		table.insert(originals, d)
	end
	if #movers == 0 then
		copy:Destroy()
		return nil
	end
	copy.Parent = dynFolder()
	PixelRenderer.registerDynamic(copy)
	for _, d in originals do
		PixelRenderer.hideStatic(d)
	end
	return { model = m, copy = copy, at = at.Position, movers = movers, originals = originals }
end

-- The islands near the view: a moving copy for the pieces with moving parts on the screen, the nearest the view's
-- middle first, MAX_MOVING at most; the rest (and gone pieces) let go.
local function scan()
	for m, s in spins do
		if m.Parent == nil or not m:IsDescendantOf(workspace) then
			drop(s, false)
		end
	end
	if quiet() then
		for _, s in spins do
			drop(s, true)
		end
		return
	end
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	local centre = CameraController.centerWorld()
	local cx = centre.X
	local found: { { m: Model, plan: { Plan }, d: number } } = {}
	for i = 1, Street.MAX do
		local ox = Street.origin(i)
		if math.abs(ox - cx) > NEAR then
			continue
		end
		local pm = plots:FindFirstChild("Plot_" .. i)
		local st = if pm then pm:FindFirstChild("Static") else nil
		local decor = if st then st:FindFirstChild("Decor") else nil
		if decor == nil then
			continue
		end
		for _, c in decor:GetChildren() do
			if not c:IsA("Model") then
				continue
			end
			local id = c:GetAttribute("Decor")
			if type(id) ~= "string" then
				continue
			end
			local got = planOf(c, id)
			if got == false then
				continue
			end
			local plan = got :: { Plan }
			local at = c:GetAttribute("At")
			if typeof(at) == "CFrame" and PixelRenderer.nearScreen(at.Position, SCREEN_PAD) then
				table.insert(found, { m = c, plan = plan, d = (at.Position - centre).Magnitude })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.d < b.d
	end)
	local keep: { [Model]: boolean } = {}
	for k = 1, math.min(#found, MAX_MOVING) do
		keep[found[k].m] = true
	end
	for m, s in spins do
		if not keep[m] then
			drop(s, true)
		end
	end
	for k = 1, math.min(#found, MAX_MOVING) do
		local e = found[k]
		if spins[e.m] == nil then
			local s = make(e.m, e.plan)
			if s then
				spins[e.m] = s
			end
		end
	end
end

-- Where a moving part stands at time t.
local function pose(e: Mover, t: number): CFrame
	local a = e.phase + t * e.speed
	if e.kind == "swing" then
		return e.hub * CFrame.fromAxisAngle(e.axis, e.amp * math.sin(a)) * e.off
	elseif e.kind == "bob" then
		-- (lifted and lowered, rocking a little as it rides)
		return (e.hub + Vector3.new(0, e.amp * math.sin(a), 0)) * CFrame.fromAxisAngle(e.axis, 0.06 * math.sin(a * 0.8 + 1.3)) * e.off
	end
	return e.hub * CFrame.fromAxisAngle(e.axis, a) * e.off
end

local function step(t: number)
	if t >= scanAt then
		scanAt = t + SCAN_SECS
		scan()
	end
	if quiet() then
		return
	end
	for _, s in spins do
		-- (only those on or near the screen move: the rest keep their last pose. It was the same east-west band of the
		-- view, so on a long island every windmill from one end to the other turned and was drawn each frame: the
		-- request of 2026-11-17, "do a stress test with the maximum amount of decor and buildings at the highest
		-- expansion level")
		if not PixelRenderer.nearScreen(s.at, 24) then
			continue
		end
		for _, e in s.movers do
			e.p.CFrame = pose(e, t)
		end
	end
end

function Spinners.start()
	RunService.Heartbeat:Connect(function()
		step(os.clock())
	end)
end

-- Sims and previews: the moving copies (each piece's id and how many parts move), how many by kind, and whether they
-- move now.
function Spinners.debugState(): { count: number, parts: number, ids: { string }, kinds: { [string]: number }, still: boolean }
	local ids: { string } = {}
	local kinds: { [string]: number } = {}
	local n = 0
	for m, s in spins do
		local id = m:GetAttribute("Decor")
		table.insert(ids, if type(id) == "string" then id else "?")
		n += #s.movers
		for _, e in s.movers do
			kinds[e.kind] = (kinds[e.kind] or 0) + 1
		end
	end
	table.sort(ids)
	return { count = #ids, parts = n, ids = ids, kinds = kinds, still = quiet() }
end

return Spinners
