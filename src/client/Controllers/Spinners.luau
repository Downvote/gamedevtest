--!strict
-- What moves on the islands (GAME_DESIGN 11; docs/ARCHITECTURE.md 10.2). The request of 2026-11-14: "other models
-- should be animated if possible too, such as windmills being able to spin". A windmill's sails, a waterwheel's rim,
-- spokes and paddles, and the Grand Mill's paddles leave the baked picture (PixelRenderer.hideStatic: the static part
-- looked through) and turn as a moving model of their own round their hub (PixelRenderer.registerDynamic). Since the
-- request of 2026-11-19 ("detail all decor more, some having animations, as much as in the bakery game") any part a
-- builder marked with Models/Parts.move moves the same way: it spins (a carousel, a big wheel, a clock's hands),
-- swings (a swing's seat, a hammock, a bell, wind chimes) or bobs (a buoy, a boat on its mooring). The piece's model
-- carries its frame (DecorModels.build's "At" attribute), so the hub and the axis come from the piece's own builder.
-- Every piece with moving parts on an island near the view gets its moving copy once (its parts leave the baked
-- picture once: a part going in and out of it as the view walked cast the picture again every second, and on a full
-- island the renderer baked again and again and drew nothing new: the stress test of 2026-11-19); of those, at most
-- MAX_MOVING move, the ones on the screen nearest the view's middle, and the rest stand still at rest (reduced
-- motion: all of them). A piece moved, rebuilt or cleared away drops its copy; the new model gets a new one.
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
-- pieces moving at a time (each a model the pixel filter draws afresh every tick it moves): 12, posed 10 times a
-- second, since the request of 2026-11-23, "optimize the game much much more. its ok to drop graphics where it most
-- affects performance" (40, 20 times a second, before: on a dense island every turn was a picture drawn again); 6
-- since the next request that day, "optimize it even further. you can cut down even more on graphics"; 3 since the
-- request of 2026-11-23, "try removing more graphics and a deeper rework of the renderer" (the nearest to the view)
local MAX_MOVING = 3
local SCREEN_PAD = 24 -- art px off the screen a piece may stand and still move
local POSE_SECS = 0.1 -- the moving parts posed this often (posing all of 40 every frame took about 2 ms a frame on a
-- full island, the stress test of 2026-11-19)
local AXES: { [string]: Vector3 } = { X = Vector3.xAxis, Y = Vector3.yAxis, Z = Vector3.zAxis }

-- A moving part as its builder marked it (Parts.move): what it does, round what, how fast and how far.
type Plan = { part: BasePart, kind: string, hub: Vector3, axis: string, speed: number, amp: number, phase: number }
type Mover = { p: BasePart, off: CFrame, kind: string, hub: CFrame, axis: Vector3, speed: number, amp: number, phase: number }
type Spin = { model: Model, copy: Model, at: Vector3, movers: { Mover }, originals: { BasePart }, active: boolean }
local spins: { [Model]: Spin } = {}
-- (the ones moving now, for the tick: the cap's 40 at most)
local active: { Spin } = {}
-- (each piece's moving parts, looked for once: false for a piece with none)
local plans: { [Model]: { Plan } | false } = setmetatable({} :: any, { __mode = "k" })
local scanAt = 0
local poseAt = 0

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

local function drop(s: Spin)
	PixelRenderer.unregisterDynamic(s.copy)
	s.copy:Destroy()
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
		if d.Parent == nil or d.Transparency >= 0.95 then
			continue
		end
		local hub = at * CFrame.new(e.hub)
		local c = d:Clone()
		c.Anchored = true
		c.CanCollide = false
		c.CanQuery = false
		c.CanTouch = false
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
	return { model = m, copy = copy, at = at.Position, movers = movers, originals = originals, active = false }
end

-- The islands near the view: a moving copy for every piece with moving parts (gone pieces' copies dropped); then the
-- MAX_MOVING of them on the screen nearest the view's middle are the ones that move, the rest put back at rest.
local function rest(s: Spin)
	for _, e in s.movers do
		e.p.CFrame = e.hub * e.off
	end
end

local function scan()
	for m, s in spins do
		if m.Parent == nil or not m:IsDescendantOf(workspace) then
			drop(s)
		end
	end
	local plots = workspace:FindFirstChild("Plots")
	if plots == nil then
		return
	end
	local centre = CameraController.centerWorld()
	local cx = centre.X
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
			-- (a piece looked at before, with no moving parts or with its copy, costs a lookup: a full island holds
			-- thousands)
			if spins[c :: any] ~= nil or plans[c :: any] == false or not c:IsA("Model") then
				continue
			end
			local id = c:GetAttribute("Decor")
			if type(id) ~= "string" then
				continue
			end
			local got = planOf(c, id)
			if got ~= false then
				local sp = make(c, got :: { Plan })
				if sp then
					spins[c] = sp
				end
			end
		end
	end
	-- which move: on the screen, the nearest the view's middle first (none with reduced motion)
	local found: { { s: Spin, d: number } } = {}
	if not quiet() then
		for _, sp in spins do
			if PixelRenderer.nearScreen(sp.at, SCREEN_PAD) then
				table.insert(found, { s = sp, d = (sp.at - centre).Magnitude })
			end
		end
		table.sort(found, function(a, b)
			return a.d < b.d
		end)
	end
	local on: { [Spin]: boolean } = {}
	for k = 1, math.min(#found, MAX_MOVING) do
		on[found[k].s] = true
	end
	for _, sp in spins do
		local now = on[sp] == true
		if sp.active and not now then
			rest(sp)
		end
		sp.active = now
	end
	table.clear(active)
	for k = 1, math.min(#found, MAX_MOVING) do
		table.insert(active, found[k].s)
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
	if quiet() or t < poseAt then
		return
	end
	poseAt = t + POSE_SECS
	for _, s in active do
		-- (only the ones picked to move, and of those only those still on the screen: the rest keep their pose. It was
		-- the same east-west band of the view, so on a long island every windmill from one end to the other turned and
		-- was drawn each frame: the request of 2026-11-17, "do a stress test with the maximum amount of decor and
		-- buildings at the highest expansion level")
		if s.model.Parent == nil or not PixelRenderer.nearScreen(s.at, SCREEN_PAD) then
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

-- Sims and previews: the moving copies (each piece's id and how many parts move), how many of them move now, the parts
-- by kind, and whether reduced motion holds them still.
function Spinners.debugState(): { count: number, moving: number, parts: number, ids: { string }, kinds: { [string]: number }, still: boolean }
	local ids: { string } = {}
	local kinds: { [string]: number } = {}
	local n, moving = 0, 0
	for m, s in spins do
		if s.active then
			moving += 1
		end
		local id = m:GetAttribute("Decor")
		table.insert(ids, if type(id) == "string" then id else "?")
		n += #s.movers
		for _, e in s.movers do
			kinds[e.kind] = (kinds[e.kind] or 0) + 1
		end
	end
	table.sort(ids)
	return { count = #ids, moving = moving, parts = n, ids = ids, kinds = kinds, still = quiet() }
end

return Spinners
