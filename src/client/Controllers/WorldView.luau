--!strict
-- The islands' life (docs/ARCHITECTURE.md 10.2; GAME_DESIGN 5, 6, 8): every villager a standing chibi
-- (Models/CharacterModels) and every driftling its 3D model (Models/MicroModels), in Workspace.PixelDynamic,
-- registered with the pixel renderer and moved every frame. A villager walks to the building they work at, works
-- there a while (chopping, digging, fishing, selling), strolls round the island, and back; one with no job strolls.
-- A driftling potters round the building it helps at (or a nest), hopping as it goes. Who lives on each island comes
-- from its plot's attributes (PlotService: Folk, Pals, Tier), where the buildings stand from its Static.Decor models'
-- names (uid:id:x:z:rot:lvl), so a visit shows a neighbour's island alive too; those away on an expedition are not
-- there. Only islands near the view get models. Every island's sign gets its name (or "Unclaimed isle") floating over
-- it; tapping a sign shows a card about the island. A newcomer moving in arrives with a cheer.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Office = require(ReplicatedStorage.Shared.Data.Office)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local StateClient = require(script.Parent.StateClient)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local WorldView = {}

-- One islander: a villager ("v") or a driftling ("p") of plot `plot`, walking about its island.
type Walker = {
	key: string,
	kind: string,
	id: number,
	plot: number,
	sig: string,
	work: number,
	rig: CharacterModels.Rig?,
	thing: MicroModels.Thing?,
	x: number, -- world
	z: number,
	tx: number,
	tz: number,
	yaw: number,
	state: string, -- "walk" | "work" | "stroll" | "idle"
	untilT: number,
	nextWork: boolean,
	action: string,
	cheerUntil: number,
	rng: Types.Rng,
}

local walkers: { [string]: Walker } = {} -- key: "<plot>:v<id>" / "<plot>:p<id>"
local signLabels: { [number]: TextLabel } = {}
local myPlot = 0
local NEAR = 100 -- studs from the view's centre an island is peopled within
local WALK = 5 -- studs a second
local HOP = 4

-- what a villager does at each kind of building (CharacterModels.poseAction)
local WORK_ACTION: { [string]: string } = {
	patch = "reach",
	orchard = "reach",
	greenhouse = "reach",
	pier = "cast",
	lumber = "swing",
	sawmill = "swing",
	stall = "pet",
	cafe = "pet",
	inn = "cheer",
}

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

local function plotModel(i: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	return if m and m:IsA("Model") then m else nil
end

-- The buildings standing on island i: uid -> { id, cx, cz (world centre), w, d (turned footprint) }.
type Spot = { id: string, cx: number, cz: number, w: number, d: number }
local function spotsOf(i: number): { [number]: Spot }
	local out: { [number]: Spot } = {}
	local m = plotModel(i)
	local decor = if m then m:FindFirstChild("Decor", true) else nil
	if decor == nil then
		return out
	end
	local ox, oz = Street.origin(i)
	for _, c in decor:GetChildren() do
		local uid, id, x, z, rot = string.match(c.Name, "^(%d+):([%w_]+):(%-?%d+):(%-?%d+):(%d+)")
		local u, xx, zz, r = tonumber(uid), tonumber(x), tonumber(z), tonumber(rot)
		if u and id and xx and zz and r then
			local w, d = Plot.footprint(id, r)
			out[u] = { id = id, cx = ox + xx + w / 2, cz = oz + zz + d / 2, w = w, d = d }
		end
	end
	return out
end

-- A random point on island i's grass (world), clear of the lodge.
local function strollPoint(i: number, rng: Types.Rng): (number, number)
	local m = plotModel(i)
	local tier = if m then (m:GetAttribute("Tier") :: number?) or 1 else 1
	local r = Street.plot(tier)
	local plan = Office.plan(tier)
	local ox, oz = Street.origin(i)
	for _ = 1, 8 do
		local x, z = r.x0 + 2 + rng:next() * (r.x1 - r.x0 - 4), r.z0 + 2 + rng:next() * (r.z1 - r.z0 - 4)
		if not (x > plan.minX - 2 and x < plan.maxX + 1 and z > plan.minZ - 2 and z < plan.maxZ + 1) then
			return ox + x, oz + z
		end
	end
	return ox + plan.maxX + 3, oz + plan.maxZ + 3
end

local function drop(key: string)
	local w = walkers[key]
	if w == nil then
		return
	end
	local model = if w.rig then w.rig.model elseif w.thing then w.thing.model else nil
	if model then
		PixelRenderer.unregisterDynamic(model)
		model:Destroy()
	end
	walkers[key] = nil
end

local function groundY(): number
	return Street.LAWN_Y
end

local function newWalker(key: string, kind: string, id: number, plot: number, sig: string, work: number, look: Types.Look?, sp: string?): Walker
	local rng = Util.newRng(Util.hash32(key))
	local x, z = strollPoint(plot, rng)
	local w: Walker = {
		key = key,
		kind = kind,
		id = id,
		plot = plot,
		sig = sig,
		work = work,
		rig = nil,
		thing = nil,
		x = x,
		z = z,
		tx = x,
		tz = z,
		yaw = 0,
		state = "idle",
		untilT = os.clock() + rng:next() * 2,
		nextWork = true,
		action = "stand",
		cheerUntil = 0,
		rng = rng,
	}
	if kind == "v" and look then
		local rig = CharacterModels.buildStanding(look, "Villager", id)
		rig.model:SetAttribute("PixelShadow", 1.2)
		rig.model:SetAttribute("PixelGroundY", groundY())
		rig.model.Parent = dyn()
		PixelRenderer.registerDynamic(rig.model)
		w.rig = rig
	elseif kind == "p" and sp then
		local def = Creatures.byId[sp]
		local t = MicroModels.driftling(if def then def.shape else "blob", if def then def.body else "steel", if def then def.accent else "steel_dark")
		t.model:SetAttribute("PixelShadow", 1)
		t.model:SetAttribute("PixelGroundY", groundY())
		t.model.Parent = dyn()
		PixelRenderer.registerDynamic(t.model)
		w.thing = t
	end
	return w
end

-- One island's islanders from its attributes (only when near the view; far ones are let go).
local function syncPlot(i: number, near: boolean)
	local m = plotModel(i)
	local want: { [string]: boolean } = {}
	if m and near and (tonumber(m:GetAttribute("Owner")) or 0) ~= 0 then
		local folk = m:GetAttribute("Folk")
		if type(folk) == "string" then
			for entry in string.gmatch(folk, "[^;]+") do
				local id, skin, hair, style, shirt, work, away = string.match(entry, "^(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d+)%.(%d)$")
				if id and away == "0" then
					local key = i .. ":v" .. id
					local sig = table.concat({ skin, hair, style, shirt }, ".")
					want[key] = true
					local w: Walker? = walkers[key]
					if w and w.sig ~= sig then
						drop(key)
						w = nil
					end
					if w == nil then
						local look = { skin = tonumber(skin) or 1, hair = tonumber(hair) or 1, style = tonumber(style) or 1, shirt = tonumber(shirt) or 1 }
						walkers[key] = newWalker(key, "v", tonumber(id) or 0, i, sig, tonumber(work) or 0, look, nil)
					else
						w.work = tonumber(work) or 0
					end
				end
			end
		end
		local pals = m:GetAttribute("Pals")
		if type(pals) == "string" then
			for entry in string.gmatch(pals, "[^;]+") do
				local id, sp, work, away = string.match(entry, "^(%d+)%.([%w_]+)%.(%d+)%.(%d)$")
				if id and sp and away == "0" then
					local key = i .. ":p" .. id
					want[key] = true
					local w: Walker? = walkers[key]
					if w and w.sig ~= sp then
						drop(key)
						w = nil
					end
					if w == nil then
						walkers[key] = newWalker(key, "p", tonumber(id) or 0, i, sp, tonumber(work) or 0, nil, sp)
					else
						w.work = tonumber(work) or 0
					end
				end
			end
		end
	end
	for key, w in walkers do
		if w.plot == i and not want[key] then
			drop(key)
		end
	end
end

------------------------------------------------------------------ moving them
local spotCache: { [number]: { at: number, spots: { [number]: Spot } } } = {}
local function spotsNow(i: number): { [number]: Spot }
	local c = spotCache[i]
	local now = os.clock()
	if c == nil or now - c.at > 1 then
		c = { at = now, spots = spotsOf(i) }
		spotCache[i] = c
	end
	return (c :: any).spots
end

-- Where a walker heads next: their building (in front of it), or a stroll.
local function decide(w: Walker, t: number)
	local spots = spotsNow(w.plot)
	local s = if w.work ~= 0 then spots[w.work] else nil
	if w.kind == "p" and s == nil then
		-- resting at a nest
		for _, sp in spots do
			local d = Buildings.byId[sp.id]
			if d and d.kind == "nest" then
				s = sp
				break
			end
		end
	end
	local isPal = w.kind == "p"
	if s and (w.nextWork or isPal) then
		local side = if isPal then (w.rng:next() - 0.5) * s.w else 0
		w.tx, w.tz = s.cx + side, s.cz + s.d / 2 + (if isPal then 0.6 + w.rng:next() else 0.9)
		w.state = "walk"
		w.nextWork = false
		w.action = WORK_ACTION[s.id] or "reach"
	else
		w.tx, w.tz = strollPoint(w.plot, w.rng)
		w.state = "walk"
		w.nextWork = true
		w.action = "stand"
	end
	w.untilT = t + 20
end

local function stepWalker(w: Walker, t: number, dt: number)
	local dx, dz = w.tx - w.x, w.tz - w.z
	local d = math.sqrt(dx * dx + dz * dz)
	local speed = 0
	if w.state == "walk" then
		if d < 0.2 or t > w.untilT then
			-- arrived: work a while at a building, or idle a moment after a stroll
			if w.action ~= "stand" then
				w.state = "work"
				w.untilT = t + 8 + w.rng:next() * 6
				w.yaw = math.pi -- facing the building (north)
			else
				w.state = "idle"
				w.untilT = t + 1.5 + w.rng:next() * 3
			end
		else
			local step = math.min(d, (if w.kind == "v" then WALK else HOP) * dt)
			w.x += dx / d * step
			w.z += dz / d * step
			w.yaw = math.atan2(dx, dz)
			speed = if w.kind == "v" then WALK else HOP
		end
	elseif t >= w.untilT then
		decide(w, t)
	end
	local y = groundY()
	if w.rig then
		local action = if t < w.cheerUntil then "cheer" elseif w.state == "work" then w.action else "stand"
		local k = if action == "swing" then (t * 1.2) % 1 else 0
		CharacterModels.poseAction(w.rig, CFrame.new(w.x, y, w.z) * CFrame.Angles(0, w.yaw, 0), t, speed, action, k)
	elseif w.thing then
		local hop = if speed > 0 then math.abs(math.sin(t * 9 + w.id)) * 0.5 else math.abs(math.sin(t * 2 + w.id)) * 0.12
		local bob = if t < w.cheerUntil then math.abs(math.sin(t * 12)) * 1.2 else hop
		MicroModels.place(w.thing, CFrame.new(w.x, y + bob, w.z) * CFrame.Angles(0, w.yaw, 0))
	end
end

------------------------------------------------------------------ island signs
local function signPoint(i: number): Vector3?
	local m = plotModel(i)
	local board = if m then m:FindFirstChild("SignBoard", true) else nil
	if board and board:IsA("BasePart") then
		return board.Position + Vector3.new(0, 1.4, 0)
	end
	return nil
end

local function signText(i: number): (string, Color3)
	local m = plotModel(i)
	local name = if m then m:GetAttribute("StudioName") else nil
	if type(name) == "string" then
		return name, if i == myPlot then UIKit.color("accent") else UIKit.color("text")
	end
	return "Unclaimed isle", UIKit.color("text_dim")
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

-- A card about the island whose sign was tapped.
function WorldView.signCard(i: number)
	local m = plotModel(i)
	if m == nil then
		return
	end
	local name = m:GetAttribute("StudioName")
	if type(name) ~= "string" then
		UIKit.notice("An unclaimed isle: a new castaway could settle here.", UIKit.color("text_dim"))
		return
	end
	local function n(k: string): number
		local v = m:GetAttribute(k)
		return if type(v) == "number" then v else 0
	end
	local function count(k: string): number
		local v = m:GetAttribute(k)
		local c = 0
		if type(v) == "string" then
			for _ in string.gmatch(v, "[^;]+") do
				c += 1
			end
		end
		return c
	end
	UIKit.notice(string.format("%s: day %s, %d villagers, %d driftlings, charm %s, %d islets explored", name, Numbers.int(n("Day")), count("Folk"), count("Pals"), Numbers.int(n("Charm")), n("Islets")), UIKit.color("accent"), 5)
end

-- A tap (not a drag, not on the interface, not in Build mode) on an island sign shows its card.
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
	local pm = if sign then sign:FindFirstAncestorWhichIsA("Model") else nil
	while pm and not string.match(pm.Name, "^Plot_%d+$") do
		pm = pm.Parent and pm.Parent:FindFirstAncestorWhichIsA("Model") or nil
	end
	if pm then
		local i = tonumber(string.match(pm.Name, "^Plot_(%d+)$"))
		if i then
			WorldView.signCard(i)
		end
	end
end

------------------------------------------------------------------ cheers
local function headOf(w: Walker): Vector3
	if w.rig and w.rig.parts.Head then
		return w.rig.parts.Head.Position + Vector3.new(0, 1.2, 0)
	end
	return Vector3.new(w.x, groundY() + 3, w.z)
end

-- The own island's villagers cheer (arms up) with a word over each head, one after another.
function WorldView.cheer(words: { string }, color: Color3)
	local k = 0
	for _, w in walkers do
		if w.plot ~= myPlot or w.kind ~= "v" then
			continue
		end
		k += 1
		local word = words[(k - 1) % math.max(1, #words) + 1] or "!"
		local first = k == 1
		task.delay((k - 1) * 0.1, function()
			w.cheerUntil = os.clock() + 1.4
			local at = headOf(w)
			UIKit.floatText(at, word, color, first)
			UIKit.bitsAt(at, { "accent", "fun", "good", "white" }, 12, 40, 80)
		end)
	end
end

-- A newcomer on the own island (Fx "day" movedIn): a word over their head and confetti, once their model is there.
local function welcome(v: { [string]: any })
	task.delay(0.6, function()
		local w = walkers[myPlot .. ":v" .. tostring(v.id)]
		if w then
			w.cheerUntil = os.clock() + 2
			local at = headOf(w)
			UIKit.floatText(at, tostring(v.name) .. " moved in!", UIKit.color("accent"), true)
			UIKit.bitsAt(at, { "accent", "good", "white", "pink" }, 18, 50, 90)
		end
	end)
end

------------------------------------------------------------------ lifecycle
function WorldView.init() end

function WorldView.start()
	local function own(v: Types.ClientView)
		myPlot = v.plot
	end
	StateClient.Changed:Connect(own)
	local v = StateClient.view()
	if v then
		own(v)
	end
	StateClient.Fx:Connect(function(msg)
		if msg.kind == "day" and type(msg.movedIn) == "table" then
			welcome(msg.movedIn)
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
	local syncAt = 0
	local last = os.clock()
	RunService.Heartbeat:Connect(function()
		local t = os.clock()
		local dt = math.min(0.1, t - last)
		last = t
		local c = CameraController.centerWorld()
		-- who is on the islands near the view (twice a second: attributes change rarely)
		if t >= syncAt then
			syncAt = t + 0.5
			for i = 1, Street.MAX do
				local ox = Street.origin(i)
				syncPlot(i, math.abs(ox - c.X) <= NEAR)
			end
		end
		for _, w in walkers do
			stepWalker(w, t, dt)
		end
		updateSigns()
	end)
end

-- CLI checks only: the islanders drawn now (all islands', and the own island's).
function WorldView.rigCount(): number
	local n = 0
	for _ in walkers do
		n += 1
	end
	return n
end

function WorldView.ownRigCount(): number
	local n = 0
	for _, w in walkers do
		if w.plot == myPlot then
			n += 1
		end
	end
	return n
end

return WorldView
