--!strict
-- The sky's ambient life (GAME_DESIGN 8; docs/ARCHITECTURE.md 10.2): a flock of white birds crossing between the
-- islands now and then (no clouds' shadows: the player asked for them gone; the sailboats went with the sea on
-- 2026-11-20, when the islands took to the sky). Client only, all in Workspace.PixelDynamic, drawn by the pixel filter
-- like the founders. Nothing here is the server's business. (The module keeps its old name: the street it once was.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.CameraController)
local Audio = require(script.Parent.Audio)

local StreetLife = {}

local started = false

type Bird = { t: MicroModels.Thing, x: number, z: number, y: number, ph: number, lag: number, parked: boolean? }

-- A bird is moved (its parts) only while it is near the view: art px past the layer's edge it still counts as near.
-- Away from the view it flies on as numbers, its model parked once far below, so no stale picture of it shows if the
-- view turns its way.
local NEAR_PX = 64
local PARK = CFrame.new(0, -400, 0)
local function nearView(t: MicroModels.Thing, rec: { parked: boolean? }, at: Vector3): boolean
	if PixelRenderer.nearScreen(at, NEAR_PX) then
		rec.parked = false
		return true
	end
	if not rec.parked then
		rec.parked = true
		MicroModels.place(t, PARK)
	end
	return false
end

local function dyn(): Instance
	local f = workspace:FindFirstChild("PixelDynamic")
	if f then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
end

local function adopt(t: MicroModels.Thing)
	-- (scenery: nothing bumps into it)
	for _, d in t.model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	t.model.Parent = dyn()
	PixelRenderer.registerDynamic(t.model)
end

function StreetLife.start()
	if started then
		return
	end
	started = true
	local b = Street.bounds()
	local birds: { Bird } = {}
	for i = 1, 3 do
		local t = MicroModels.build("bird", { color = "white" })
		adopt(t)
		table.insert(birds, { t = t, x = b.x0 - 30 - i * 3, z = 0, y = 16 + i, ph = i * 0.7, lag = 0 })
	end
	local flockAt = 4
	-- the flock's way across this time: east or west, a slant, a height, a weave
	local fdir, fslant, fweave, fwph = 1, 0, 1, 0
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - last)
		last = now
		-- a flock crosses now and then
		if now >= flockAt then
			flockAt = now + 14 + math.random() * 10
			-- (a different crossing each time: from either end, slanting, higher or lower, weaving more or less)
			fdir = if math.random() < 0.5 then 1 else -1
			fslant = (math.random() - 0.5) * 0.5
			fweave = 0.5 + math.random() * 2
			fwph = math.random() * 6
			-- (somewhere near the view: the lots reach far north since the twenty tiers, and a flock anywhere along them
			-- would seldom be seen)
			local cz = CameraController.centerWorld().Z
			local z = math.clamp(cz + (math.random() - 0.5) * 100, Street.LOT.z0, Street.LOT.z1)
			local y = 13 + math.random() * 6
			for i, bd in birds do
				local back = 20 + i * 4 + math.random() * 2
				bd.x = if fdir > 0 then b.x0 - back else b.x1 + back
				bd.z = z + (i - 2) * (2.5 + math.random())
				bd.y = y + i * 0.6 + math.random() * 0.8
				bd.lag = math.random() * 0.6
			end
		end
		-- a squawk as the flock passes over the view
		local lead = birds[1]
		if lead then
			local c = CameraController.centerWorld()
			if math.abs(lead.x - c.X) < 24 and math.abs(lead.z - c.Z) < 30 then
				Audio.play("gull")
			end
		end
		for _, bd in birds do
			-- heading along the crossing, weaving side to side; the head (+Z of the model) turned the way it flies
			local sway = math.sin((now - bd.lag) * 0.7 + fwph) * fweave
			local vx, vz = fdir * 9, (fslant + sway * 0.25) * 9
			bd.x += vx * dt
			bd.z += vz * dt
			if not nearView(bd.t, bd, Vector3.new(bd.x, bd.y, bd.z)) then
				continue
			end
			local cf = CFrame.new(bd.x, bd.y + math.sin(now * 2 + bd.ph) * 0.5, bd.z) * CFrame.Angles(0, math.atan2(vx, vz), 0)
			MicroModels.place(bd.t, cf)
			local glide = math.sin(now * 0.5 + bd.ph * 3) > 0.4
			local up = if glide then 0.1 elseif (now * 3 + bd.ph) % 1 < 0.5 then 0.3 else -0.15
			for _, n in { "WingL", "WingR" } do
				local w = bd.t.parts[n]
				if w then
					w.CFrame = cf * bd.t.rest[n] * CFrame.new(0, up, 0)
				end
			end
		end
	end)
end

-- CLI checks only: the birds there are.
function StreetLife.count(): number
	return if started then 3 else 0
end

return StreetLife
