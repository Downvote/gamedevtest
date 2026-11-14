--!strict
-- The founders (GAME_DESIGN 12; docs/ARCHITECTURE.md 10.6): every player walks the street as a little chibi in the
-- crew's style (Models/CharacterModels.buildStanding), their look from the player's "Founder" attribute (the server
-- sets it from profile.founder). The rig follows the player's character every frame: its feet on the ground under the
-- HumanoidRootPart, facing where the character faces, its legs and arms swinging with its speed. The Roblox avatar
-- itself is hidden on this client (LocalTransparencyModifier; the pixel bake never sees characters), so the classic
-- style shows the chibis too. Other players' names float over their heads; walking feet kick up puffs of dust. In the
-- sea (GAME_DESIGN 8: no docks since 2026-11-13, "players can swim around in water to reach other player islands") a
-- founder swims: the rig sinks to its chest at the water's surface and crawls (treads water when still), splashing,
-- the strokes heard; the HUD slows the character to Tuning.SwimSpeed there and holds its jump.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Shared.Types)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local Audio = require(script.Parent.Audio)
local Puffs = require(script.Parent.Puffs)
local UIKit = require(script.Parent.Parent.UI.UIKit)

local AvatarView = {}

type Rec = {
	rig: CharacterModels.Rig,
	sig: string,
	last: Vector3?,
	speed: number,
	label: TextLabel?,
	char: Model?,
	dustAt: number, -- when their feet next kick up a puff of dust (walking)
	air: boolean, -- in the air (a jump) last frame
	rest: number?, -- the root's height over the ground as it last stood
	floor: string, -- what the feet are on: "grass", "sand", "wood", "water" (a river on an island) or "swim" (the sea)
	stepAt: number, -- when the own founder's next footstep sounds
	ripple: Model, -- a ring of foam on the water round them while they swim (deep under the sea otherwise)
}

-- What a ground hit is, for the footsteps: the sea, its shallows and its foam (or the seabed under them) mean swimming,
-- a river or pond drawn on the island wading, planks and beams wood, the beach (lower than the lawn) sand, everything
-- else (the lawn, a path, a piece) grass.
local function floorOf(hit: RaycastResult?): string
	if hit == nil then
		return "grass"
	end
	local n = hit.Instance.Name
	-- (a river or pond drawn on the island: the founder wades through it, splashing: GAME_DESIGN 4.3; the sea, lower
	-- down: it swims)
	if hit.Instance:GetAttribute("PixelWater") ~= nil then
		return if hit.Position.Y > Street.LAWN_Y - 0.3 then "water" else "swim"
	end
	if n == "Seabed" or n == "Shelf" then
		return "swim"
	end
	if string.find(n, "Plank", 1, true) or string.find(n, "Beam", 1, true) or n == "Pier" or n == "Edge" then
		return "wood"
	end
	if hit.Position.Y < Street.LAWN_Y - 0.05 then
		return "sand"
	end
	return "grass"
end

local recs: { [Player]: Rec } = {}
-- (swimming: the rig's feet this far under the water's surface, so it shows from the chest up)
local SWIM_SINK = 1.8
local HIDDEN = CFrame.new(0, -60, 0)

-- A swimmer's ring of foam: four flat strips round them on the water (it grows and shrinks in two whole steps).
local function rippleModel(): Model
	local m = Blocks.model(nil, "Ripple")
	for k = 1, 4 do
		local p = Blocks.part(m, { size = Vector3.new(1, 0.05, 0.25), cf = HIDDEN, color = "foam", name = "Ring" .. k })
		p.CanCollide = false
		p.CanQuery = false
		p.CastShadow = false
	end
	return m
end

local function placeRipple(m: Model, at: Vector3?, half: number)
	for k = 1, 4 do
		local p = m:FindFirstChild("Ring" .. k) :: BasePart?
		if p then
			if at == nil then
				p.CFrame = HIDDEN
			else
				local across = k <= 2
				local side = if k % 2 == 0 then 1 else -1
				p.Size = if across then Vector3.new(half * 2 + 0.25, 0.05, 0.25) else Vector3.new(0.25, 0.05, half * 2 + 0.25)
				p.CFrame = CFrame.new(at + (if across then Vector3.new(0, 0, side * half) else Vector3.new(side * half, 0, 0)))
			end
		end
	end
end
-- A cutscene's hold on the own founder (UI/Voyage): it poses the rig instead of the character
local override: ((rig: CharacterModels.Rig, t: number, dt: number) -> ())? = nil
-- The ground under a founder: only what it can stand on (the lawn, a floor, the boardwalk). The buildings, decor and
-- trees on an island don't collide (the founder walks through them), so a ray that met them would put the chibi up
-- on a roof as it walked through (the bug report of 2026-11-14: "there is a bug where the player snaps above
-- buildings while walking over them"). A second ray, `wetParams`, still finds the water a founder wades in.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local wetParams = RaycastParams.new()
wetParams.FilterType = Enum.RaycastFilterType.Exclude

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
		PixelRenderer.unregisterDynamic(r.ripple)
		r.ripple:Destroy()
		if r.label then
			r.label:Destroy()
		end
		recs[pl] = nil
	end
end

-- Where a character's feet are: on the ground under it (the lawn, a floor, the boardwalk) while it stands there; in the
-- air (a jump: Humanoid.FloorMaterial is Air) at its root's height less the root's height over the ground as it last
-- stood (learnt, whatever the avatar's size), so the chibi leaves the ground with it. True while airborne.
local function feetY(rec: Rec, char: Model, root: BasePart): (number, boolean)
	local list: { Instance } = { dyn() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	groundParams.FilterDescendantsInstances = list
	local hum = char:FindFirstChildOfClass("Humanoid")
	local inAir = hum ~= nil and hum.FloorMaterial == Enum.Material.Air
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), groundParams)
	if hit then
		rec.floor = floorOf(hit)
		if rec.floor ~= "swim" then
			-- (a river, pond or pool laid on the ground doesn't collide either: wading in it splashes)
			wetParams.FilterDescendantsInstances = list
			local wet = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), wetParams)
			if wet and wet.Instance:GetAttribute("PixelWater") ~= nil and wet.Position.Y <= hit.Position.Y + 1 then
				rec.floor = floorOf(wet)
			end
		end
	end
	if hit and not inAir then
		rec.rest = root.Position.Y - hit.Position.Y
		return hit.Position.Y, false
	end
	local hip = if hum then hum.HipHeight else 2
	local rest = rec.rest or (hip + root.Size.Y / 2)
	local fy = root.Position.Y - rest
	if hit then
		fy = math.max(fy, hit.Position.Y)
	end
	return fy, inAir
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
			local ripple = rippleModel()
			ripple.Parent = dyn()
			PixelRenderer.registerDynamic(ripple)
			r = { rig = rig, sig = sig, last = nil, speed = 0, label = label, char = nil, dustAt = 0, air = false, floor = "grass", stepAt = 0, ripple = ripple }
			recs[pl] = r
		end
		local rec = r :: Rec
		if rec.char ~= char then
			rec.char = char
			hide(char)
		end
		if pl == me and override then
			(override :: (CharacterModels.Rig, number, number) -> ())(rec.rig, t, dt)
			rec.last = nil
			continue
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
		local wasFloor = rec.floor
		local fy, airborne = feetY(rec, char, root)
		local base = CFrame.new(pos.X, fy, pos.Z) * CFrame.Angles(0, yaw, 0)
		-- (the own founder's feet are heard: library sounds in place of Roblox's own, which RbxCharacterSounds turns off)
		local mine = pl == me
		if rec.floor == "swim" and not airborne then
			-- swimming: sunk to the chest at the surface, a crawl or treading water; a splash going in, the strokes
			-- heard, drops off the arms
			base = CFrame.new(pos.X, Street.WATER_Y - SWIM_SINK, pos.Z) * CFrame.Angles(0, yaw, 0)
			CharacterModels.poseAction(rec.rig, base, t, rec.speed, "swim")
			local surface = Vector3.new(pos.X, Street.WATER_Y + 0.1, pos.Z)
			placeRipple(rec.ripple, Vector3.new(pos.X, Street.WATER_Y + 0.03, pos.Z), if math.floor(t * 2.5) % 2 == 0 then 1 else 1.25)
			if wasFloor ~= "swim" then
				Puffs.burst("drop", surface, 10, 0.6)
				if mine then
					Audio.play("step_water", { volume = 1.6 })
				end
				rec.stepAt = t + 0.4
			elseif rec.speed > 2 and t >= rec.stepAt then
				rec.stepAt = t + 0.55
				Puffs.burst("drop", surface + (base.LookVector * 0.6), 3, 0.4)
				if mine then
					Audio.play("step_water", { volume = 0.8 })
				end
			elseif rec.speed <= 2 and t >= rec.dustAt then
				rec.dustAt = t + 1.2
				Puffs.burst("drop", surface, 2, 0.5)
			end
			rec.air = false
		elseif airborne then
			placeRipple(rec.ripple, nil, 1)
			-- a jump: knees up, arms up, off the ground with the character
			CharacterModels.poseAction(rec.rig, base, t, 0, "jump")
			if mine and not rec.air then
				Audio.play("jump")
			end
			rec.air = true
		else
			placeRipple(rec.ripple, nil, 1)
			if rec.air then
				-- landing: a puff of dust at the feet (and a thump: on the boards, a firmer step)
				UIKit.bitsAt((base * CFrame.new(0, 0.1, 0)).Position, { "white", "text_dim" }, 4, 18, 40)
				if mine then
					if rec.floor == "wood" then
						Audio.play("step_wood", { volume = 1.8 })
					else
						Audio.play("land")
					end
					rec.stepAt = t + 0.25
				end
			elseif mine and rec.speed > 4 and t >= rec.stepAt then
				-- a step every stride (quicker the faster they go)
				rec.stepAt = t + math.clamp(5.4 / rec.speed, 0.24, 0.5)
				Audio.play("step_" .. rec.floor)
			end
			rec.air = false
			CharacterModels.poseStanding(rec.rig, base, t, rec.speed)
		end
		-- a walk kicks up a puff of dust now and then, a run more often (in water: splashes; swimming has its own)
		if rec.floor == "swim" then
			-- (the strokes' drops above)
		elseif not airborne and rec.speed > 6 and t >= rec.dustAt and rec.floor == "water" then
			rec.dustAt = t + (if rec.speed > 14 then 0.14 else 0.24)
			Puffs.burst("drop", (base * CFrame.new(0, 0.1, -0.3)).Position, 3, 0.3)
		elseif not airborne and rec.speed > 6 and t >= rec.dustAt then
			rec.dustAt = t + (if rec.speed > 14 then 0.18 else 0.3)
			UIKit.bitsAt((base * CFrame.new(0, 0.1, -0.4)).Position, { "white", "text_dim" }, 2, 14, 40)
		end
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

-- Whether the own founder is swimming in the sea now (the HUD slows it to Tuning.SwimSpeed and holds its jump).
function AvatarView.swimming(): boolean
	local r = recs[Players.LocalPlayer]
	return r ~= nil and r.floor == "swim" and not r.air
end

-- A cutscene poses the own founder (nil: back to following the character).
function AvatarView.setOverride(fn: ((rig: CharacterModels.Rig, t: number, dt: number) -> ())?)
	override = fn
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

-- A player's founder look (the microgames' stage dresses the player's own rig in it).
function AvatarView.lookOf(pl: Player): Types.Look
	local look = lookOf(pl)
	return look
end

return AvatarView
