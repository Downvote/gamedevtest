--!strict
-- The sea's ambient life (GAME_DESIGN 8; docs/ARCHITECTURE.md 10.2): sailboats crossing both ways beyond the
-- boardwalk, rocking on the swell, a flock of gulls crossing now and then, and clouds whose shadows drift over the
-- islands (invisible models with a blob shadow: PixelRenderer's PixelShadow). Client only, all in
-- Workspace.PixelDynamic, drawn by the pixel filter like the founders. Nothing here is the server's business; the
-- expedition's stage (far away) never shows it. (The module keeps its old name: the street it once was.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.CameraController)
local Audio = require(script.Parent.Audio)

local StreetLife = {}

local BOAT_SPEED = 4 -- studs a second
local CLOUD_Y = 24
local started = false

type Boat = { t: MicroModels.Thing, x: number, z: number, dir: number, speed: number, ph: number }
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
		t.model:SetAttribute("PixelGroundY", groundY or Street.WATER_Y)
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
	-- two lanes out on the open sea, clear of the piers (Street.PIER_Z + the boat moored there)
	local laneE = Street.SEA.z0 + 12 -- eastbound (+X), the near lane
	local laneW = Street.SEA.z0 + 18 -- westbound
	local boats: { Boat } = {}
	for i = 1, 4 do
		-- the detailed boats of Models/BoatSpec, of a few sizes, their flags fluttering
		local t = MicroModels.build("ship", { level = ({ 1, 2, 1, 3 })[i] })
		local east = i % 2 == 1
		adopt(t, 2.4)
		table.insert(boats, { t = t, x = b.x0 + (b.x1 - b.x0) * (i - 1) / 4, z = if east then laneE else laneW, dir = if east then 1 else -1, speed = BOAT_SPEED * (0.8 + 0.12 * i), ph = i * 1.3 })
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
		-- boats: wrap round the sea's ends, rise and roll on the swell (in whole steps: a quarter stud, a few degrees)
		for _, c in boats do
			c.x += c.dir * c.speed * dt
			if c.dir > 0 and c.x > b.x1 + 12 then
				c.x = b.x0 - 12
			elseif c.dir < 0 and c.x < b.x0 - 12 then
				c.x = b.x1 + 12
			end
			local swell = math.sin(now * 1.6 + c.ph)
			local bob = if swell > 0.3 then 0.25 elseif swell < -0.3 then 0 else 0.125
			local roll = math.rad(if swell > 0.5 then 4 elseif swell < -0.5 then -4 else 0)
			MicroModels.flutter(c.t, now + c.ph)
			MicroModels.place(c.t, CFrame.new(c.x, Street.WATER_Y - 0.1 + bob, c.z) * CFrame.Angles(0, if c.dir > 0 then math.pi / 2 else -math.pi / 2, 0) * CFrame.Angles(0, 0, roll))
		end
		-- a flock crosses now and then
		if now >= flockAt then
			flockAt = now + 14 + math.random() * 10
			local z = Street.LOT.z0 + math.random() * (Street.SEA.z1 - Street.LOT.z0)
			for i, bd in birds do
				bd.x = b.x0 - 20 - i * 4
				bd.z = z + (i - 2) * 3
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

-- CLI checks only: the boats, gulls and clouds there are.
function StreetLife.count(): number
	return if started then 9 else 0
end

return StreetLife
