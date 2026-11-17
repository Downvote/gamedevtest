--!strict
-- What turns on the islands (GAME_DESIGN 11; docs/ARCHITECTURE.md 10.2). The request of 2026-11-14: "other models
-- should be animated if possible too, such as windmills being able to spin". A windmill's sails, a waterwheel's rim,
-- spokes and paddles, and the Grand Mill's paddles leave the baked picture (PixelRenderer.hideStatic: the static part
-- looked through) and turn as a moving model of their own round their hub (PixelRenderer.registerDynamic), on every
-- island near the view. The piece's model carries its frame (DecorModels.build's "At" attribute), so the hub and the
-- axis come from the piece's own builder. A piece moved, rebuilt or cleared away drops its turning copy; the new model
-- gets a new one. Reduced motion keeps them still.
--   start(), debugState()
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)

local Spinners = {}

-- What turns on each piece: its parts by name, the hub in the piece's frame, the axis (the frame's Z or X) and the
-- speed (radians a second; a wheel turned by the stream goes the other way round).
type Spec = { parts: { [string]: boolean }, hub: Vector3, axis: string, speed: number }
local SPECS: { [string]: Spec } = {
	windmill = { parts = { SailArm = true, Sail = true }, hub = Vector3.new(0, 3.4, 0.9), axis = "Z", speed = 0.9 },
	waterwheel = { parts = { Rim = true, Spoke = true, Paddle = true }, hub = Vector3.new(0, 1.2, 0), axis = "Z", speed = -0.7 },
	grandmill = { parts = { Paddle = true }, hub = Vector3.new(1.6, 1.5, -0.6), axis = "X", speed = 0.7 },
}
local SCAN_SECS = 1 -- the islands near the view looked over this often
local NEAR = 220 -- studs from the view's middle (along the street) an island is near

type Spin = { model: Model, copy: Model, hub: CFrame, speed: number, phase: number, parts: { { p: BasePart, off: CFrame } } }
local spins: { [Model]: Spin } = {}
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

local function drop(s: Spin)
	PixelRenderer.unregisterDynamic(s.copy)
	s.copy:Destroy()
	spins[s.model] = nil
end

-- A piece's turning copy: its turning parts cloned into a moving model, the originals out of the picture.
local function make(m: Model, spec: Spec): Spin?
	local at = m:GetAttribute("At")
	if typeof(at) ~= "CFrame" then
		return nil
	end
	local hub = at * CFrame.new(spec.hub)
	if spec.axis == "X" then
		hub = hub * CFrame.Angles(0, math.pi / 2, 0)
	end
	local copy = Instance.new("Model")
	copy.Name = "Spin_" .. m.Name
	local parts: { { p: BasePart, off: CFrame } } = {}
	local originals: { BasePart } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and spec.parts[d.Name] and d.Transparency < 0.95 then
			local c = d:Clone()
			c.Anchored = true
			c.CanCollide = false
			c.CanQuery = false
			c.CanTouch = false
			c.Parent = copy
			table.insert(parts, { p = c, off = hub:ToObjectSpace(d.CFrame) })
			table.insert(originals, d)
		end
	end
	if #parts == 0 then
		copy:Destroy()
		return nil
	end
	copy.Parent = dynFolder()
	PixelRenderer.registerDynamic(copy)
	for _, d in originals do
		PixelRenderer.hideStatic(d)
	end
	-- (each piece a little out of step with the next)
	local phase = (#m.Name * 0.37) % (math.pi * 2)
	return { model = m, copy = copy, hub = hub, speed = spec.speed, phase = phase, parts = parts }
end

-- The islands near the view: a turning copy for each piece that has turning parts and none yet; gone pieces' copies
-- dropped.
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
	local cx = CameraController.centerWorld().X
	for i = 1, Street.MAX do
		local ox = Street.origin(i)
		if math.abs(ox - cx) > NEAR then
			continue
		end
		local pm = plots:FindFirstChild("Plot_" .. i)
		local decor = if pm then pm:FindFirstChild("Decor", true) else nil
		if decor == nil then
			continue
		end
		for _, c in decor:GetChildren() do
			if c:IsA("Model") and spins[c] == nil then
				local id = c:GetAttribute("Decor")
				local spec = if type(id) == "string" then SPECS[id] else nil
				if spec then
					local s = make(c, spec)
					if s then
						spins[c] = s
					end
				end
			end
		end
	end
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
		-- (only those on or near the screen move: the rest keep their last turn. It was the same east-west band of the
		-- view, so on a long island every windmill from one end to the other turned and was drawn each frame: the
		-- request of 2026-11-17, "do a stress test with the maximum amount of decor and buildings at the highest
		-- expansion level")
		if not PixelRenderer.nearScreen(s.hub.Position, 24) then
			continue
		end
		local turn = s.hub * CFrame.Angles(0, 0, s.phase + t * s.speed)
		for _, e in s.parts do
			e.p.CFrame = turn * e.off
		end
	end
end

function Spinners.start()
	RunService.Heartbeat:Connect(function()
		step(os.clock())
	end)
end

-- Sims and previews: the turning copies (each piece's id and how many parts turn) and whether they move now.
function Spinners.debugState(): { count: number, parts: number, ids: { string }, still: boolean }
	local ids: { string } = {}
	local n = 0
	for m, s in spins do
		local id = m:GetAttribute("Decor")
		table.insert(ids, if type(id) == "string" then id else "?")
		n += #s.parts
	end
	table.sort(ids)
	return { count = #ids, parts = n, ids = ids, still = quiet() }
end

return Spinners
