--!strict
-- The crew: little chibi developers from parts (docs/ARCHITECTURE.md 6; GAME_DESIGN 2). Roblox module (client: WorldView
-- builds one per developer at their desk; Snapshot draws portraits of the same). Built seated, facing +Z, with the
-- rig's origin on the seat's top centre; `pose` moves the parts every frame from their rest offsets.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Blocks = require(script.Parent.Blocks)

local CharacterModels = {}

export type Rig = {
	model: Model,
	parts: { [string]: BasePart },
	rest: { [string]: CFrame }, -- each part's offset from the rig's origin
	seed: number,
}

type Spec = { name: string, size: Vector3, at: Vector3, color: string, shape: ("Block" | "Ball")? }

-- The parts of a developer, rest pose (seat top centre = origin, facing +Z).
local function specs(look: Types.Look): { Spec }
	local skin = Looks.skin[look.skin] or "skin1"
	local hair = Looks.hair[look.hair] or "hair_brown"
	local shirt = Looks.shirt[look.shirt] or "blue"
	local style = Looks.styles[look.style] or "short"
	local list: { Spec } = {
		{ name = "LegL", size = Vector3.new(0.5, 0.5, 1.0), at = Vector3.new(-0.32, 0.25, 0.4), color = "jeans" },
		{ name = "LegR", size = Vector3.new(0.5, 0.5, 1.0), at = Vector3.new(0.32, 0.25, 0.4), color = "jeans" },
		{ name = "ShinL", size = Vector3.new(0.5, 1.25, 0.5), at = Vector3.new(-0.32, -0.5, 0.75), color = "jeans" },
		{ name = "ShinR", size = Vector3.new(0.5, 1.25, 0.5), at = Vector3.new(0.32, -0.5, 0.75), color = "jeans" },
		{ name = "Torso", size = Vector3.new(1.25, 1.25, 0.75), at = Vector3.new(0, 0.875, -0.1), color = shirt },
		{ name = "Head", size = Vector3.new(1.5, 1.25, 1.25), at = Vector3.new(0, 2.125, -0.05), color = skin },
		{ name = "EyeL", size = Vector3.new(0.25, 0.25, 0.25), at = Vector3.new(-0.35, 2.15, 0.5), color = "black" },
		{ name = "EyeR", size = Vector3.new(0.25, 0.25, 0.25), at = Vector3.new(0.35, 2.15, 0.5), color = "black" },
		{ name = "CheekL", size = Vector3.new(0.25, 0.25, 0.25), at = Vector3.new(-0.55, 1.85, 0.5), color = "pink" },
		{ name = "CheekR", size = Vector3.new(0.25, 0.25, 0.25), at = Vector3.new(0.55, 1.85, 0.5), color = "pink" },
		{ name = "HairCap", size = Vector3.new(1.75, 0.5, 1.5), at = Vector3.new(0, 2.8, -0.1), color = hair },
		{ name = "Fringe", size = Vector3.new(1.5, 0.25, 0.25), at = Vector3.new(0, 2.55, 0.55), color = hair },
		{ name = "ArmL", size = Vector3.new(0.375, 0.375, 1.25), at = Vector3.new(-0.7, 1.15, 0.45), color = shirt },
		{ name = "ArmR", size = Vector3.new(0.375, 0.375, 1.25), at = Vector3.new(0.7, 1.15, 0.45), color = shirt },
		{ name = "HandL", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(-0.55, 1.15, 1.15), color = skin },
		{ name = "HandR", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(0.55, 1.15, 1.15), color = skin },
	}
	if style == "long" then
		table.insert(list, { name = "HairBack", size = Vector3.new(1.75, 1.75, 0.5), at = Vector3.new(0, 1.95, -0.75), color = hair })
		table.insert(list, { name = "LockL", size = Vector3.new(0.25, 1.25, 0.75), at = Vector3.new(-0.85, 2.0, -0.2), color = hair })
		table.insert(list, { name = "LockR", size = Vector3.new(0.25, 1.25, 0.75), at = Vector3.new(0.85, 2.0, -0.2), color = hair })
	elseif style == "bun" then
		table.insert(list, { name = "HairBack", size = Vector3.new(1.75, 1.0, 0.5), at = Vector3.new(0, 2.35, -0.75), color = hair })
		table.insert(list, { name = "Bun", size = Vector3.new(0.875, 0.875, 0.875), at = Vector3.new(0, 3.2, -0.5), color = hair, shape = "Ball" })
	elseif style == "spiky" then
		table.insert(list, { name = "HairBack", size = Vector3.new(1.75, 1.0, 0.5), at = Vector3.new(0, 2.35, -0.75), color = hair })
		table.insert(list, { name = "SpikeA", size = Vector3.new(0.5, 0.5, 0.5), at = Vector3.new(-0.5, 3.15, 0.0), color = hair })
		table.insert(list, { name = "SpikeB", size = Vector3.new(0.5, 0.75, 0.5), at = Vector3.new(0.05, 3.25, -0.2), color = hair })
		table.insert(list, { name = "SpikeC", size = Vector3.new(0.5, 0.5, 0.5), at = Vector3.new(0.55, 3.1, 0.1), color = hair })
	else
		table.insert(list, { name = "HairBack", size = Vector3.new(1.75, 1.0, 0.5), at = Vector3.new(0, 2.35, -0.75), color = hair })
	end
	return list
end

-- A developer's rig (unparented; the caller parents it into Workspace.PixelDynamic). Parts are not queryable or
-- collidable: the static bake never sees them.
function CharacterModels.build(look: Types.Look, name: string, seed: number?): Rig
	local model = Blocks.model(nil, name)
	local parts: { [string]: BasePart } = {}
	local rest: { [string]: CFrame } = {}
	for _, sp in specs(look) do
		local p = Blocks.part(model, {
			size = sp.size,
			cf = CFrame.new(sp.at),
			color = sp.color,
			name = sp.name,
			shape = sp.shape,
			collide = false,
			query = false,
		})
		p.CastShadow = false
		parts[sp.name] = p
		rest[sp.name] = CFrame.new(sp.at)
	end
	model.PrimaryPart = parts.Torso
	return { model = model, parts = parts, rest = rest, seed = seed or 0 }
end

local HEAD_PARTS = { "Head", "EyeL", "EyeR", "CheekL", "CheekR", "HairCap", "Fringe", "HairBack", "LockL", "LockR", "Bun", "SpikeA", "SpikeB", "SpikeC" }
local NECK = Vector3.new(0, 1.5, -0.05)
local SHOULDER_L, SHOULDER_R = Vector3.new(-0.7, 1.3, -0.1), Vector3.new(0.7, 1.3, -0.1)

-- Moves a group of parts about a pivot (rig space) by `rot`.
local function turn(rig: Rig, base: CFrame, names: { string }, pivot: Vector3, rot: CFrame, lift: Vector3?)
	local around = CFrame.new(pivot) * rot * CFrame.new(-pivot)
	local up = if lift then CFrame.new(lift) else CFrame.identity
	for _, n in names do
		local p = rig.parts[n]
		if p then
			p.CFrame = base * up * around * rig.rest[n]
		end
	end
end

-- Pose the rig at `base` (the seat's top centre, facing +Z) at time t: "type" (typing), "idle" (hands on the desk,
-- looking round now and then, a stretch), "tired" (head down, slow breathing) or "cheer" (arms up: a spark).
function CharacterModels.pose(rig: Rig, base: CFrame, t: number, state: string)
	local ph = rig.seed * 1.7
	local breathe = math.sin((t + ph) * 2) * 0.03
	local body = Vector3.new(0, breathe, 0)
	for _, n in { "Torso", "LegL", "LegR", "ShinL", "ShinR" } do
		local p = rig.parts[n]
		if p then
			p.CFrame = base * CFrame.new(if n == "Torso" then body else Vector3.zero) * rig.rest[n]
		end
	end
	-- head
	local headRot = CFrame.identity
	if state == "type" then
		headRot = CFrame.Angles(math.rad(4 + 3 * math.sin((t + ph) * 3)), 0, 0)
	elseif state == "idle" then
		local look = math.sin((t + ph) * 0.7)
		local yaw = if math.abs(look) > 0.8 then math.rad(18) * math.sign(look) else 0
		headRot = CFrame.Angles(0, yaw, 0)
	elseif state == "tired" then
		headRot = CFrame.Angles(math.rad(18), 0, math.rad(10 + 3 * math.sin((t + ph) * 1.2)))
	elseif state == "cheer" then
		headRot = CFrame.Angles(math.rad(-8), 0, 0)
	end
	turn(rig, base, HEAD_PARTS, NECK, headRot, body)
	-- arms and hands
	if state == "cheer" then
		local wave = math.sin((t + ph) * 10) * 0.15
		local up = CFrame.Angles(math.rad(-120), 0, 0)
		turn(rig, base, { "ArmL", "HandL" }, SHOULDER_L, up * CFrame.Angles(0, 0, math.rad(-12 + wave * 20)), body)
		turn(rig, base, { "ArmR", "HandR" }, SHOULDER_R, up * CFrame.Angles(0, 0, math.rad(12 - wave * 20)), body)
	elseif state == "idle" and math.sin((t + ph) * 0.23) > 0.96 then
		-- a stretch now and then
		local up = CFrame.Angles(math.rad(-150), 0, 0)
		turn(rig, base, { "ArmL", "HandL" }, SHOULDER_L, up, body)
		turn(rig, base, { "ArmR", "HandR" }, SHOULDER_R, up, body)
	else
		local tapL, tapR = 0, 0
		if state == "type" then
			local k = (t + ph) * 9
			tapL = math.max(0, math.sin(k)) * 0.14
			tapR = math.max(0, math.sin(k + 2.1)) * 0.14
		end
		turn(rig, base, { "ArmL" }, SHOULDER_L, CFrame.identity, body + Vector3.new(0, tapL * 0.5, 0))
		turn(rig, base, { "ArmR" }, SHOULDER_R, CFrame.identity, body + Vector3.new(0, tapR * 0.5, 0))
		turn(rig, base, { "HandL" }, SHOULDER_L, CFrame.identity, body + Vector3.new(0, tapL, 0))
		turn(rig, base, { "HandR" }, SHOULDER_R, CFrame.identity, body + Vector3.new(0, tapR, 0))
	end
end

-- Where the popups float from (rig space): just above the hair.
CharacterModels.HEAD_TOP = Vector3.new(0, 3.4, 0)

return CharacterModels
