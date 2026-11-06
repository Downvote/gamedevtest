--!strict
-- The office's life (docs/ARCHITECTURE.md 10.2): a rig per developer at their desk (Models/CharacterModels) in
-- Workspace.PixelDynamic, registered with the pixel renderer and posed every frame: typing while a game is in the
-- works, idle otherwise, dozing ("z") when worn out, cheering on a spark. A week's work pops out of their heads:
-- "+12" in the score's colour, a spark bigger and in gold.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local StateClient = require(script.Parent.StateClient)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldView = {}

type Entry = { rig: CharacterModels.Rig, base: CFrame, sig: string, id: number, cheerUntil: number, zAt: number }

local rigs: { [number]: Entry } = {}
local working = false
local folder: Folder? = nil

local function dyn(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local found = workspace:FindFirstChild("PixelDynamic")
	if found and found:IsA("Folder") then
		folder = found
		return found
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	folder = nf
	return nf
end

local function sigOf(s: Types.Staff, plot: number, office: number): string
	local l = s.look
	return string.format("%d|%d|%d|%d|%d|%d|%d|%d", plot, office, s.desk, l.skin, l.hair, l.style, l.shirt, s.id)
end

local function seatBase(plot: number, office: number, desk: number): CFrame?
	local plan = Office.plan(office)
	local a = plan.desks[desk]
	if a == nil then
		return nil
	end
	local ox, oz = Office.origin(plot)
	local x, y, z = Office.seat(a)
	return CFrame.new(ox + x, y, oz + z)
end

local function drop(id: number)
	local e = rigs[id]
	if e then
		PixelRenderer.unregisterDynamic(e.rig.model)
		e.rig.model:Destroy()
		rigs[id] = nil
	end
end

-- Rigs follow the view's crew: new developers get a rig, a changed look or desk a new one, the gone lose theirs.
local function sync(v: Types.ClientView)
	working = v.project ~= nil
	local keep: { [number]: boolean } = {}
	for _, s in v.staff do
		keep[s.id] = true
		local sig = sigOf(s, v.plot, v.office)
		local e = rigs[s.id]
		if e == nil or e.sig ~= sig then
			drop(s.id)
			local base = seatBase(v.plot, v.office, s.desk)
			if base then
				local rig = CharacterModels.build(s.look, "Dev_" .. s.id, s.id)
				CharacterModels.pose(rig, base, 0, "idle")
				rig.model.Parent = dyn()
				PixelRenderer.registerDynamic(rig.model)
				rigs[s.id] = { rig = rig, base = base, sig = sig, id = s.id, cheerUntil = 0, zAt = 0 }
			end
		end
	end
	for id in rigs do
		if not keep[id] then
			drop(id)
		end
	end
end

local function energyOf(id: number): number
	local v = StateClient.view()
	if v then
		for _, s in v.staff do
			if s.id == id then
				return s.energy
			end
		end
	end
	return 100
end

local function axisColor(axis: string): Color3
	return UIKit.hex(Palette.axis[axis] or 0xFFFFFF)
end

-- A week's popups over the crew's heads.
local function onWeek(msg: { [string]: any })
	local events = msg.events
	if type(events) ~= "table" then
		return
	end
	for _, e in events do
		if type(e) == "table" and e.kind == "work" and type(e.pops) == "table" then
			for k, pop in e.pops do
				local entry = rigs[pop.id]
				if entry then
					local at = (entry.base * CFrame.new(CharacterModels.HEAD_TOP)).Position
					local delay = (k - 1) * 0.12
					task.delay(delay, function()
						if pop.spark then
							entry.cheerUntil = os.clock() + 1.2
							UIKit.floatText(at, "Spark! +" .. tostring(pop.n), UIKit.color("accent"), true)
						elseif pop.n > 0 then
							UIKit.floatText(at, "+" .. tostring(pop.n), axisColor(pop.axis), false)
						end
					end)
				end
			end
		end
	end
end

function WorldView.init() end

function WorldView.start()
	StateClient.Changed:Connect(sync)
	local v = StateClient.view()
	if v then
		sync(v)
	end
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "week" then
			onWeek(msg)
		end
	end)
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		for id, e in rigs do
			local state = "idle"
			local energy = energyOf(id)
			if t < e.cheerUntil then
				state = "cheer"
			elseif energy < Tuning.EnergyTired then
				state = "tired"
			elseif working then
				state = "type"
			end
			CharacterModels.pose(e.rig, e.base, t, state)
			if state == "tired" and t >= e.zAt then
				e.zAt = t + 2.2
				UIKit.floatText((e.base * CFrame.new(CharacterModels.HEAD_TOP + Vector3.new(0.6, 0, 0))).Position, "z", UIKit.color("text_dim"), false)
			end
		end
	end)
end

-- CLI checks only: the rigs drawn now.
function WorldView.rigCount(): number
	local n = 0
	for _ in rigs do
		n += 1
	end
	return n
end

return WorldView
