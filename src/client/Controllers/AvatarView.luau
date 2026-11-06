--!strict
-- The founders (GAME_DESIGN 12; docs/ARCHITECTURE.md 10.6): every player walks the street as a little chibi in the
-- crew's style (Models/CharacterModels.buildStanding), their look from the player's "Founder" attribute (the server
-- sets it from profile.founder). The rig follows the player's character every frame: its feet on the ground under the
-- HumanoidRootPart, facing where the character faces, its legs and arms swinging with its speed. The Roblox avatar
-- itself is hidden on this client (LocalTransparencyModifier; the pixel bake never sees characters), so the classic
-- style shows the chibis too. Other players' names float over their heads.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local AvatarView = {}

type Rec = {
	rig: CharacterModels.Rig,
	sig: string,
	last: Vector3?,
	speed: number,
	label: TextLabel?,
	char: Model?,
}

local recs: { [Player]: Rec } = {}
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function lookOf(pl: Player): (Types.Look, string)
	local a = pl:GetAttribute("Founder")
	local s = if type(a) == "string" then a else ""
	local k, h, st, sh = string.match(s, "^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
	if k and h and st and sh then
		return { skin = tonumber(k) :: number, hair = tonumber(h) :: number, style = tonumber(st) :: number, shirt = tonumber(sh) :: number }, s
	end
	local u = pl.UserId
	local look = { skin = u % 4 + 1, hair = (u // 4) % 5 + 1, style = (u // 20) % 4 + 1, shirt = (u // 80) % 8 + 1 }
	return look, "default"
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

-- The Roblox avatar stays out of sight on this client.
local function hide(char: Model)
	local function one(d: Instance)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 1
		end
	end
	for _, d in char:GetDescendants() do
		one(d)
	end
	char.DescendantAdded:Connect(one)
end

local function drop(pl: Player)
	local r = recs[pl]
	if r then
		PixelRenderer.unregisterDynamic(r.rig.model)
		r.rig.model:Destroy()
		if r.label then
			r.label:Destroy()
		end
		recs[pl] = nil
	end
end

-- The ground under a character (the lawn, a floor, the road), else its root's height less a standing body.
local function feetY(char: Model, root: BasePart): number
	local list: { Instance } = { dyn() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), groundParams)
	if hit then
		return hit.Position.Y
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hip = if hum then hum.HipHeight else 2
	return root.Position.Y - hip - root.Size.Y / 2
end

local function step(dt: number)
	local t = os.clock()
	local me = Players.LocalPlayer
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		local root = if char then char:FindFirstChild("HumanoidRootPart") else nil
		if char == nil or root == nil or not root:IsA("BasePart") then
			drop(pl)
			continue
		end
		local look, sig = lookOf(pl)
		local r = recs[pl]
		if r == nil or r.sig ~= sig then
			drop(pl)
			local rig = CharacterModels.buildStanding(look, "Founder_" .. pl.UserId, pl.UserId % 97)
			rig.model.Parent = dyn()
			PixelRenderer.registerDynamic(rig.model)
			local label: TextLabel? = nil
			if pl ~= me then
				label = UIKit.text(UIKit.canvas("World"), pl.DisplayName, UDim2.fromOffset(UIKit.textWidth(pl.DisplayName) + 4, 10), nil, { x = "center", kind = "outline", name = "Name" })
			end
			r = { rig = rig, sig = sig, last = nil, speed = 0, label = label, char = nil }
			recs[pl] = r
		end
		local rec = r :: Rec
		if rec.char ~= char then
			rec.char = char
			hide(char)
		end
		local pos = root.Position
		if rec.last and dt > 0 then
			local d = pos - (rec.last :: Vector3)
			local v = Vector3.new(d.X, 0, d.Z).Magnitude / dt
			rec.speed = rec.speed + (math.min(v, 30) - rec.speed) * math.min(1, dt * 10)
		end
		rec.last = pos
		local fwd = root.CFrame.LookVector
		local flat = Vector3.new(fwd.X, 0, fwd.Z)
		local yaw = if flat.Magnitude > 1e-3 then math.atan2(flat.X, flat.Z) else 0
		local base = CFrame.new(pos.X, feetY(char, root), pos.Z) * CFrame.Angles(0, yaw, 0)
		CharacterModels.poseStanding(rec.rig, base, t, rec.speed)
		local label = rec.label
		if label then
			local top = (base * CFrame.new(CharacterModels.STAND_TOP)).Position
			local i, j, on = PixelRenderer.projectPixel(top)
			label.Visible = on
			if on then
				local w = label.Size.X.Offset
				label.Position = UDim2.fromOffset(i - math.floor(w / 2), j - 10)
			end
		end
	end
	for pl in recs do
		if pl.Parent == nil then
			drop(pl)
		end
	end
end

-- The founder's position on this client (the local player's rig's feet), for the HUD and Build mode.
function AvatarView.founderPos(): Vector3?
	local r = recs[Players.LocalPlayer]
	local torso = if r then r.rig.parts.Torso else nil
	return if torso then torso.Position else nil
end

-- CLI checks only: the founders drawn now.
function AvatarView.count(): number
	local n = 0
	for _ in recs do
		n += 1
	end
	return n
end

function AvatarView.start()
	RunService.Heartbeat:Connect(step)
	Players.PlayerRemoving:Connect(drop)
end

return AvatarView
