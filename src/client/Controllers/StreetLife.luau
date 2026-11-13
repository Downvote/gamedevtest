--!strict
-- The sea's ambient life (GAME_DESIGN 8; docs/ARCHITECTURE.md 10.2): sailboats crossing both ways south of the
-- islands, rocking on the swell (nothing a swimming founder bumps into), and a flock of gulls crossing now and then (no clouds' shadows: the player asked for
-- them gone). Client only, all in
-- Workspace.PixelDynamic, drawn by the pixel filter like the founders. Nothing here is the server's business. (The module keeps its old name: the street it once was.)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.CameraController)
local Audio = require(script.Parent.Audio)

local StreetLife = {}

local BOAT_SPEED = 4 -- studs a second
local started = false

type Boat = { t: MicroModels.Thing, x: number, z: number, dir: number, speed: number, ph: number }
type Bird = { t: MicroModels.Thing, x: number, z: number, y: number, ph: number, lag: number }

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
	-- (scenery: a founder swimming by passes through it)
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
	-- two lanes out on the open sea, south of the islands' shallows
	local laneE = Street.SEA.z0 + 17 -- eastbound (+X), the near lane
	local laneW = Street.SEA.z0 + 23 -- westbound
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
			-- (a different crossing each time: from either end, slanting, higher or lower, weaving more or less)
			fdir = if math.random() < 0.5 then 1 else -1
			fslant = (math.random() - 0.5) * 0.5
			fweave = 0.5 + math.random() * 2
			fwph = math.random() * 6
			local z = Street.LOT.z0 + math.random() * (Street.SEA.z1 - Street.LOT.z0)
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

-- CLI checks only: the boats and gulls there are.
function StreetLife.count(): number
	return if started then 7 else 0
end

return StreetLife
