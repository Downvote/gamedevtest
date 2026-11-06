--!strict
-- The street's life (docs/ARCHITECTURE.md 10.2; GAME_DESIGN 2, 12): a rig per developer at their desk
-- (Models/CharacterModels) in Workspace.PixelDynamic, registered with the pixel renderer and posed every frame:
-- typing while a game is in the works, idle otherwise, dozing ("z") when worn out, cheering on a spark. The player's
-- own crew comes from their view (and a week's work pops out of their heads: "+12" in the score's colour, a spark
-- bigger and in gold); every other studio's crew from its plot's attributes (PlotService: Crew, Working), so a visit
-- shows a studio at work. Only plots near the view are posed. Every plot sign gets its studio's name (or "Empty lot")
-- floating over it; tapping a sign shows a card about the studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local StateClient = require(script.Parent.StateClient)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldView = {}

type Entry = {
	rig: CharacterModels.Rig,
	base: CFrame,
	sig: string,
	plot: number,
	staff: number?, -- the own crew's staff id (popups), nil for another studio's
	tired: boolean,
	cheerUntil: number,
	zAt: number,
}

local rigs: { [string]: Entry } = {} -- key: "own:<staff id>" or "<plot>:<desk>"
local ownWorking = false
local othersWorking: { [number]: boolean } = {}
local signLabels: { [number]: TextLabel } = {}
local myPlot = 0
local NEAR = 90 -- studs from the view's centre a plot's crew is posed within

local function dyn(): Folder
	local found = workspace:FindFirstChild("PixelDynamic")
	if found and found:IsA("Folder") then
		return found
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
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

local function drop(key: string)
	local e = rigs[key]
	if e then
		PixelRenderer.unregisterDynamic(e.rig.model)
		e.rig.model:Destroy()
		rigs[key] = nil
	end
end

-- Make sure the rig for `key` exists with this look and seat (a changed look or seat builds a new one).
local function ensure(key: string, sig: string, plot: number, office: number, desk: number, look: Types.Look, seed: number): Entry?
	local e = rigs[key]
	if e and e.sig == sig then
		return e
	end
	drop(key)
	local base = seatBase(plot, office, desk)
	if base == nil then
		return nil
	end
	local rig = CharacterModels.build(look, "Dev_" .. key, seed)
	CharacterModels.pose(rig, base, 0, "idle")
	rig.model.Parent = dyn()
	PixelRenderer.registerDynamic(rig.model)
	local ne: Entry = { rig = rig, base = base, sig = sig, plot = plot, staff = nil, tired = false, cheerUntil = 0, zAt = 0 }
	rigs[key] = ne
	return ne
end

------------------------------------------------------------------ the own crew (the view)
local function syncOwn(v: Types.ClientView)
	myPlot = v.plot
	ownWorking = v.project ~= nil
	local keep: { [string]: boolean } = {}
	for _, s in v.staff do
		local key = "own:" .. s.id
		keep[key] = true
		local l = s.look
		local sig = string.format("%d|%d|%d|%d|%d|%d|%d", v.plot, v.office, s.desk, l.skin, l.hair, l.style, l.shirt)
		local e = ensure(key, sig, v.plot, v.office, s.desk, s.look, s.id)
		if e then
			e.staff = s.id
			e.tired = s.energy < Tuning.EnergyTired
		end
	end
	for key in rigs do
		if string.sub(key, 1, 4) == "own:" and not keep[key] then
			drop(key)
		end
	end
end

------------------------------------------------------------------ other studios (plot attributes)
local function syncPlot(plotModel: Instance)
	local i = tonumber(string.match(plotModel.Name, "^Plot_(%d+)$"))
	if i == nil or i == myPlot then
		return
	end
	local owner = plotModel:GetAttribute("Owner")
	local tier = plotModel:GetAttribute("Tier")
	local crew = plotModel:GetAttribute("Crew")
	othersWorking[i] = plotModel:GetAttribute("Working") == true
	local keep: { [string]: boolean } = {}
	if type(owner) == "number" and owner ~= 0 and type(tier) == "number" and type(crew) == "string" then
		for part in string.gmatch(crew, "[^;]+") do
			local d, k, h, st, sh, tired = string.match(part, "^(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d)$")
			if d and k and h and st and sh and tired then
				local desk = tonumber(d) :: number
				local key = i .. ":" .. desk
				keep[key] = true
				local look = { skin = tonumber(k) :: number, hair = tonumber(h) :: number, style = tonumber(st) :: number, shirt = tonumber(sh) :: number }
				local e = ensure(key, string.format("%d|%s", tier, part:sub(1, #part - 2)), i, tier, desk, look, i * 10 + desk)
				if e then
					e.tired = tired == "1"
				end
			end
		end
	end
	for key, e in rigs do
		if e.plot == i and e.staff == nil and not keep[key] then
			drop(key)
		end
	end
end

local function watchPlots()
	local plots = workspace:WaitForChild("Plots", 30)
	if plots == nil then
		return
	end
	local function hook(m: Instance)
		if not string.match(m.Name, "^Plot_%d+$") then
			return
		end
		syncPlot(m)
		m.AttributeChanged:Connect(function()
			syncPlot(m)
		end)
	end
	for _, m in plots:GetChildren() do
		hook(m)
	end
	plots.ChildAdded:Connect(hook)
end

------------------------------------------------------------------ plot signs
local function signPoint(i: number): Vector3?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	local board = if m then m:FindFirstChild("SignBoard", true) else nil
	if board and board:IsA("BasePart") then
		return board.Position + Vector3.new(0, 1.4, 0)
	end
	return nil
end

local function signText(i: number): (string, Color3)
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	local name = if m then m:GetAttribute("StudioName") else nil
	if type(name) == "string" then
		return name, if i == myPlot then UIKit.color("accent") else UIKit.color("text")
	end
	return "Empty lot", UIKit.color("text_dim")
end

local function updateSigns()
	for i = 1, Street.MAX do
		local at = signPoint(i)
		local text, color = signText(i)
		local l = signLabels[i]
		if not l then
			l = UIKit.text(UIKit.canvas("World"), text, UDim2.fromOffset(UIKit.textWidth(text) + 4, 10), nil, { x = "center", kind = "outline", color = color, name = "Sign_" .. i })
			signLabels[i] = l
		end
		local label = l :: TextLabel
		if label.Text ~= text then
			label.Size = UDim2.fromOffset(UIKit.textWidth(text) + 4, 10)
			UIKit.setText(label, text)
		end
		UIKit.setTextColor(label, color)
		if at then
			local x, y, on = PixelRenderer.projectPixel(at)
			label.Visible = on
			if on then
				label.Position = UDim2.fromOffset(x - math.floor(label.Size.X.Offset / 2), y - 10)
			end
		else
			label.Visible = false
		end
	end
end

-- A card about the studio whose sign was tapped.
function WorldView.signCard(i: number)
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	if m == nil then
		return
	end
	local name = m:GetAttribute("StudioName")
	if type(name) ~= "string" then
		UIKit.notice("An empty lot: a new studio could move in here.", UIKit.color("text_dim"))
		return
	end
	local tier = m:GetAttribute("Tier")
	local games = m:GetAttribute("Games")
	local best = m:GetAttribute("Best")
	local office = Office.plan(if type(tier) == "number" then tier else 1).name
	UIKit.notice(string.format("%s: %s, %s games, best %d/40%s", name, office, Numbers.int(if type(games) == "number" then games else 0), if type(best) == "number" then best else 0, if m:GetAttribute("Working") == true then ", a game in the works" else ""), UIKit.color("accent"), 5)
end

-- A tap (not a drag, not on the interface, not in Build mode) on a plot sign shows its card.
local function onTap(pos: Vector2)
	if CameraController.isFree() then
		return
	end
	local origin, dir = PixelRenderer.screenRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { dyn() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	params.FilterDescendantsInstances = list
	local hit = workspace:Raycast(origin, dir, params)
	if hit == nil then
		return
	end
	local sign = hit.Instance:FindFirstAncestor("PlotSign")
	local plotModel = if sign then sign:FindFirstAncestorWhichIsA("Model") else nil
	while plotModel and not string.match(plotModel.Name, "^Plot_%d+$") do
		plotModel = plotModel.Parent and plotModel.Parent:FindFirstAncestorWhichIsA("Model") or nil
	end
	if plotModel then
		local i = tonumber(string.match(plotModel.Name, "^Plot_(%d+)$"))
		if i then
			WorldView.signCard(i)
		end
	end
end

------------------------------------------------------------------ the week's popups
local function axisColor(axis: string): Color3
	return UIKit.hex(Palette.axis[axis] or 0xFFFFFF)
end

local function onWeek(msg: { [string]: any })
	local events = msg.events
	if type(events) ~= "table" then
		return
	end
	for _, e in events do
		if type(e) == "table" and e.kind == "work" and type(e.pops) == "table" then
			for k, pop in e.pops do
				local entry = rigs["own:" .. tostring(pop.id)]
				if entry then
					local at = (entry.base * CFrame.new(CharacterModels.HEAD_TOP)).Position
					task.delay((k - 1) * 0.12, function()
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

------------------------------------------------------------------ lifecycle
function WorldView.init() end

function WorldView.start()
	StateClient.Changed:Connect(syncOwn)
	local v = StateClient.view()
	if v then
		syncOwn(v)
	end
	task.spawn(watchPlots)
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "week" then
			onWeek(msg)
		end
	end)
	-- taps on the world (a press let go within 8 px of where it began)
	local downAt: Vector2? = nil
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input, processed)
		local d = downAt
		if processed or d == nil then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			downAt = nil
			if (pos - d).Magnitude <= 8 then
				onTap(pos)
			end
		end
	end)
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local c = CameraController.centerWorld()
		for _, e in rigs do
			local ox = Street.origin(e.plot)
			if math.abs(ox - c.X) > NEAR then
				continue
			end
			local working = if e.staff then ownWorking else othersWorking[e.plot] == true
			local state = "idle"
			if t < e.cheerUntil then
				state = "cheer"
			elseif e.tired then
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
		updateSigns()
	end)
end

-- CLI checks only: the rigs drawn now (own crew and other studios').
function WorldView.rigCount(): number
	local n = 0
	for _ in rigs do
		n += 1
	end
	return n
end

function WorldView.ownRigCount(): number
	local n = 0
	for key in rigs do
		if string.sub(key, 1, 4) == "own:" then
			n += 1
		end
	end
	return n
end

return WorldView
