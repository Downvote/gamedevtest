--!strict
-- The street's ambient life (GAME_DESIGN 8, 12; docs/ARCHITECTURE.md 10.2): cars driving both ways along the road
-- (they wait for a founder standing in their lane), a flock of birds crossing now and then, and clouds whose
-- shadows drift over the lawns and the offices (invisible models with a blob shadow: PixelRenderer's PixelShadow).
-- Client only, all in Workspace.PixelDynamic, drawn by the pixel filter like the founders. Nothing here is the
-- server's business; the microgames' stage (far away) never shows it.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)

local StreetLife = {}

local ROAD_Y = -0.45 -- the road's top (Models/StreetModels)
local CAR_SPEED = 11 -- studs a second
local CAR_COLORS = { "berry_red", "blue", "yellow", "green", "white", "orange" }
local CLOUD_Y = 24
local started = false

type Car = { t: MicroModels.Thing, x: number, z: number, dir: number, speed: number }
type Bird = { t: MicroModels.Thing, x: number, z: number, y: number, ph: number }
type Cloud = { m: Model, x: number, z: number, speed: number }

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

local function adopt(t: MicroModels.Thing, shadow: number?, groundY: number?)
	if shadow then
		t.model:SetAttribute("PixelShadow", shadow)
		t.model:SetAttribute("PixelGroundY", groundY or ROAD_Y)
	end
	t.model.Parent = dyn()
	PixelRenderer.registerDynamic(t.model)
end

-- A founder standing in a car's lane just ahead of it.
local function blocked(car: Car): boolean
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = root.Position
			local ahead = (p.X - car.x) * car.dir
			if math.abs(p.Z - car.z) < 2.6 and ahead > 0 and ahead < 7 then
				return true
			end
		end
	end
	return false
end

function StreetLife.start()
	if started then
		return
	end
	started = true
	local b = Street.bounds()
	local laneE = Street.ROAD.z0 + 2.75 -- eastbound (+X), the north lane
	local laneW = Street.ROAD.z1 - 2.75 -- westbound
	local cars: { Car } = {}
	for i = 1, 4 do
		local t = MicroModels.build("car", { color = CAR_COLORS[(i - 1) % #CAR_COLORS + 1] })
		local east = i % 2 == 1
		adopt(t, 2.2)
		table.insert(cars, { t = t, x = b.x0 + (b.x1 - b.x0) * (i - 1) / 4, z = if east then laneE else laneW, dir = if east then 1 else -1, speed = CAR_SPEED * (0.85 + 0.1 * i) })
	end
	local birds: { Bird } = {}
	for i = 1, 3 do
		local t = MicroModels.build("bird", { color = "white" })
		adopt(t)
		table.insert(birds, { t = t, x = b.x0 - 30 - i * 3, z = 0, y = 16 + i, ph = i * 0.7 })
	end
	local flockAt = 4
	local clouds: { Cloud } = {}
	for i = 1, 2 do
		local m = Blocks.model(nil, "Cloud" .. i)
		local p = Blocks.part(m, { size = Vector3.new(1, 1, 1), cf = CFrame.new(0, CLOUD_Y, 0), color = "white", transparency = 1, collide = false, query = false })
		p.CastShadow = false
		m.PrimaryPart = p
		m:SetAttribute("PixelShadow", 15 + i * 2)
		m:SetAttribute("PixelGroundY", Street.LAWN_Y)
		m.Parent = dyn()
		PixelRenderer.registerDynamic(m)
		table.insert(clouds, { m = m, x = b.x0 + (b.x1 - b.x0) * (0.3 + 0.4 * (i - 1)), z = -6 + i * 14, speed = 1.2 + i * 0.4 })
	end
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local dt = math.min(0.1, now - last)
		last = now
		-- cars: wrap round the street's ends, wait for founders in their way, bob a little
		for _, c in cars do
			if not blocked(c) then
				c.x += c.dir * c.speed * dt
			end
			if c.dir > 0 and c.x > b.x1 + 10 then
				c.x = b.x0 - 10
			elseif c.dir < 0 and c.x < b.x0 - 10 then
				c.x = b.x1 + 10
			end
			local bob = if math.floor(now * 6 + c.x) % 2 == 0 then 0.05 else 0
			MicroModels.place(c.t, CFrame.new(c.x, ROAD_Y + bob, c.z) * CFrame.Angles(0, if c.dir > 0 then math.pi / 2 else -math.pi / 2, 0))
		end
		-- a flock crosses now and then
		if now >= flockAt then
			flockAt = now + 14 + math.random() * 10
			local z = Street.LOT.z0 + math.random() * (Street.VERGE.z1 - Street.LOT.z0)
			for i, bd in birds do
				bd.x = b.x0 - 20 - i * 4
				bd.z = z + (i - 2) * 3
			end
		end
		for _, bd in birds do
			bd.x += 9 * dt
			local cf = CFrame.new(bd.x, bd.y + math.sin(now * 2 + bd.ph) * 0.5, bd.z) * CFrame.Angles(0, math.pi / 2, 0)
			MicroModels.place(bd.t, cf)
			local up = if (now * 3 + bd.ph) % 1 < 0.5 then 0.3 else -0.15
			for _, n in { "WingL", "WingR" } do
				local w = bd.t.parts[n]
				if w then
					w.CFrame = cf * bd.t.rest[n] * CFrame.new(0, up, 0)
				end
			end
		end
		-- clouds drift east and come round again
		for _, cl in clouds do
			cl.x += cl.speed * dt
			if cl.x > b.x1 + 30 then
				cl.x = b.x0 - 30
			end
			local pp = cl.m.PrimaryPart
			if pp then
				pp.CFrame = CFrame.new(cl.x, CLOUD_Y, cl.z)
			end
		end
	end)
end

-- CLI checks only: the cars, birds and clouds there are.
function StreetLife.count(): number
	return if started then 9 else 0
end

return StreetLife
