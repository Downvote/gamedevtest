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
		-- a glint in each eye, the brows (the expressions move them), a mouth, ears
		{ name = "GlintL", size = Vector3.new(0.125, 0.125, 0.125), at = Vector3.new(-0.41, 2.21, 0.6), color = "white" },
		{ name = "GlintR", size = Vector3.new(0.125, 0.125, 0.125), at = Vector3.new(0.29, 2.21, 0.6), color = "white" },
		{ name = "BrowL", size = Vector3.new(0.375, 0.125, 0.125), at = Vector3.new(-0.35, 2.36, 0.6), color = hair },
		{ name = "BrowR", size = Vector3.new(0.375, 0.125, 0.125), at = Vector3.new(0.35, 2.36, 0.6), color = hair },
		{ name = "Mouth", size = Vector3.new(0.25, 0.125, 0.125), at = Vector3.new(0, 1.8, 0.58), color = "black" },
		{ name = "EarL", size = Vector3.new(0.125, 0.375, 0.375), at = Vector3.new(-0.8, 2.1, 0), color = skin },
		{ name = "EarR", size = Vector3.new(0.125, 0.375, 0.375), at = Vector3.new(0.8, 2.1, 0), color = skin },
		{ name = "CheekL", size = Vector3.new(0.25, 0.125, 0.125), at = Vector3.new(-0.55, 1.88, 0.56), color = "pink" },
		{ name = "CheekR", size = Vector3.new(0.25, 0.125, 0.125), at = Vector3.new(0.55, 1.88, 0.56), color = "pink" },
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
		p.Size = sp.size -- (exact: the face's details are finer than Blocks' 0.25 grid, an art pixel and up)
		p.CastShadow = false
		parts[sp.name] = p
		rest[sp.name] = CFrame.new(sp.at)
	end
	model.PrimaryPart = parts.Torso
	return { model = model, parts = parts, rest = rest, seed = seed or 0 }
end

local HEAD_PARTS = { "Head", "EyeL", "EyeR", "GlintL", "GlintR", "BrowL", "BrowR", "Mouth", "EarL", "EarR", "CheekL", "CheekR", "HairCap", "Fringe", "HairBack", "LockL", "LockR", "Bun", "SpikeA", "SpikeB", "SpikeC" }
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

------------------------------------------------------------------ standing (the founders and visitors)
-- A founder or a visitor: the same head, hair and face as a seated one, raised a stud, on a standing body with
-- joints: shorts over bare shins, shoes on light soles, a shirt with a collar, two buttons and a belt with a buckle,
-- sleeves over bare forearms and fists. The rig's origin is between the feet on the ground, facing +Z. Poses bend the
-- knees and elbows, lean and twist the body and change the face (`Pose`: the work, the cheers and the cutscenes).
local HEAD_SET: { [string]: boolean } = {}
for _, n in HEAD_PARTS do
	HEAD_SET[n] = true
end
local HEAD_LIFT = Vector3.new(0, 1.0, 0.05)

local BODY_PARTS = { "Torso", "Belt", "Buckle", "Collar", "ButtonA", "ButtonB" }
local THIGH_L, THIGH_R = { "LegL" }, { "LegR" }
local SHIN_L, SHIN_R = { "ShinL", "ShoeL", "SoleL" }, { "ShinR", "ShoeR", "SoleR" }
local UPPER_L, UPPER_R = { "ArmL" }, { "ArmR" }
local LOWER_L, LOWER_R = { "ForeL", "HandL" }, { "ForeR", "HandR" }

function CharacterModels.buildStanding(look: Types.Look, name: string, seed: number?): Rig
	local model = Blocks.model(nil, name)
	local parts: { [string]: BasePart } = {}
	local rest: { [string]: CFrame } = {}
	local skin = Looks.skin[look.skin] or "skin1"
	local shirt = Looks.shirt[look.shirt] or "blue"
	local trim = if shirt == "white" then "blue" else "cream"
	local list: { Spec } = {
		{ name = "SoleL", size = Vector3.new(0.5, 0.125, 0.75), at = Vector3.new(-0.3, 0.0625, 0.1), color = "cream" },
		{ name = "SoleR", size = Vector3.new(0.5, 0.125, 0.75), at = Vector3.new(0.3, 0.0625, 0.1), color = "cream" },
		{ name = "ShoeL", size = Vector3.new(0.5, 0.25, 0.625), at = Vector3.new(-0.3, 0.25, 0.06), color = "black" },
		{ name = "ShoeR", size = Vector3.new(0.5, 0.25, 0.625), at = Vector3.new(0.3, 0.25, 0.06), color = "black" },
		{ name = "ShinL", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(-0.3, 0.5625, 0), color = skin },
		{ name = "ShinR", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(0.3, 0.5625, 0), color = skin },
		{ name = "LegL", size = Vector3.new(0.5, 0.5, 0.5), at = Vector3.new(-0.3, 1.0, 0), color = "jeans" },
		{ name = "LegR", size = Vector3.new(0.5, 0.5, 0.5), at = Vector3.new(0.3, 1.0, 0), color = "jeans" },
		{ name = "Torso", size = Vector3.new(1.25, 1.25, 0.75), at = Vector3.new(0, 1.875, 0), color = shirt },
		{ name = "Belt", size = Vector3.new(1.375, 0.125, 0.875), at = Vector3.new(0, 1.3125, 0), color = "wood_dark" },
		{ name = "Buckle", size = Vector3.new(0.25, 0.125, 0.125), at = Vector3.new(0, 1.3125, 0.45), color = "gold" },
		{ name = "Collar", size = Vector3.new(0.75, 0.125, 0.25), at = Vector3.new(0, 2.4375, 0.28), color = trim },
		{ name = "ButtonA", size = Vector3.new(0.125, 0.125, 0.125), at = Vector3.new(0, 2.125, 0.4), color = trim },
		{ name = "ButtonB", size = Vector3.new(0.125, 0.125, 0.125), at = Vector3.new(0, 1.75, 0.4), color = trim },
		{ name = "ArmL", size = Vector3.new(0.375, 0.5, 0.375), at = Vector3.new(-0.8125, 2.2, 0), color = shirt },
		{ name = "ArmR", size = Vector3.new(0.375, 0.5, 0.375), at = Vector3.new(0.8125, 2.2, 0), color = shirt },
		{ name = "ForeL", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(-0.8125, 1.7625, 0), color = skin },
		{ name = "ForeR", size = Vector3.new(0.375, 0.375, 0.375), at = Vector3.new(0.8125, 1.7625, 0), color = skin },
		{ name = "HandL", size = Vector3.new(0.5, 0.375, 0.5), at = Vector3.new(-0.8125, 1.39, 0), color = skin },
		{ name = "HandR", size = Vector3.new(0.5, 0.375, 0.5), at = Vector3.new(0.8125, 1.39, 0), color = skin },
	}
	for _, sp in specs(look) do
		if HEAD_SET[sp.name] then
			table.insert(list, { name = sp.name, size = sp.size, at = sp.at + HEAD_LIFT, color = sp.color, shape = sp.shape })
		end
	end
	for _, sp in list do
		local p = Blocks.part(model, { size = sp.size, cf = CFrame.new(sp.at), color = sp.color, name = sp.name, shape = sp.shape, collide = false, query = false })
		p.Size = sp.size -- exact (an art pixel and up)
		p.CastShadow = false
		parts[sp.name] = p
		rest[sp.name] = CFrame.new(sp.at)
	end
	model.PrimaryPart = parts.Torso
	return { model = model, parts = parts, rest = rest, seed = seed or 0 }
end

local HIP_L, HIP_R = Vector3.new(-0.3, 1.25, 0), Vector3.new(0.3, 1.25, 0)
local KNEE_L, KNEE_R = Vector3.new(-0.3, 0.75, 0), Vector3.new(0.3, 0.75, 0)
local ARM_L, ARM_R = Vector3.new(-0.8125, 2.4, 0), Vector3.new(0.8125, 2.4, 0)
local ELBOW_L, ELBOW_R = Vector3.new(-0.8125, 1.95, 0), Vector3.new(0.8125, 1.95, 0)
local WAIST = Vector3.new(0, 1.25, 0)
local STAND_NECK = Vector3.new(0, 2.5, 0)

-- A pose: the body's lean (+ forward) and twist, a crouch (studs down; the knees bend to keep the feet down), each
-- leg's hip and knee (+ the knee bends back), each arm's shoulder (a CFrame: -X raises it forward) and elbow (+
-- bends forward), the head's turn, and the face.
export type Pose = {
	lean: number?,
	twist: number?,
	crouch: number?,
	lift: number?,
	hipL: number?,
	kneeL: number?,
	hipR: number?,
	kneeR: number?,
	armL: CFrame?,
	elbowL: number?,
	armR: CFrame?,
	elbowR: number?,
	head: CFrame?,
	mood: string?,
}

-- The faces: the eyes' height (closed: a line), the brows' tilt and lift, the mouth's size and colour.
type Mood = { eyeH: number, eyeDy: number, brow: number, browDy: number, mouth: Vector3, mouthColor: string, glint: boolean }
local MOODS: { [string]: Mood } = {
	calm = { eyeH = 0.25, eyeDy = 0, brow = 0, browDy = 0, mouth = Vector3.new(0.25, 0.125, 0.125), mouthColor = "black", glint = true },
	fierce = { eyeH = 0.25, eyeDy = 0, brow = math.rad(24), browDy = -0.04, mouth = Vector3.new(0.375, 0.125, 0.125), mouthColor = "black", glint = true },
	shout = { eyeH = 0.25, eyeDy = 0, brow = math.rad(24), browDy = -0.04, mouth = Vector3.new(0.25, 0.25, 0.125), mouthColor = "berry_red", glint = true },
	hurt = { eyeH = 0.125, eyeDy = 0, brow = math.rad(-20), browDy = 0.04, mouth = Vector3.new(0.25, 0.25, 0.125), mouthColor = "berry_red", glint = false },
	happy = { eyeH = 0.125, eyeDy = 0.06, brow = 0, browDy = 0.06, mouth = Vector3.new(0.375, 0.25, 0.125), mouthColor = "berry_red", glint = false },
	ko = { eyeH = 0.125, eyeDy = -0.04, brow = math.rad(-12), browDy = 0, mouth = Vector3.new(0.125, 0.125, 0.125), mouthColor = "black", glint = false },
}
local moodOf: { [Rig]: string } = setmetatable({}, { __mode = "k" }) :: any
local restOf: { [Rig]: { [string]: CFrame } } = setmetatable({}, { __mode = "k" }) :: any

local function setMood(rig: Rig, mood: string)
	if moodOf[rig] == mood then
		return
	end
	moodOf[rig] = mood
	local m = MOODS[mood] or MOODS.calm
	local base = restOf[rig]
	if base == nil then
		base = table.clone(rig.rest)
		restOf[rig] = base
	end
	for _, side in { "L", "R" } do
		local sign = if side == "L" then -1 else 1
		local eye = rig.parts["Eye" .. side]
		if eye and base["Eye" .. side] then
			eye.Size = Vector3.new(0.25, m.eyeH, 0.25)
			rig.rest["Eye" .. side] = base["Eye" .. side] * CFrame.new(0, m.eyeDy, 0)
		end
		local brow = rig.parts["Brow" .. side]
		if brow and base["Brow" .. side] then
			rig.rest["Brow" .. side] = base["Brow" .. side] * CFrame.new(0, m.browDy, 0) * CFrame.Angles(0, 0, -sign * m.brow)
		end
		local glint = rig.parts["Glint" .. side]
		if glint then
			glint.Transparency = if m.glint then 0 else 1
		end
	end
	local mouth = rig.parts.Mouth
	if mouth then
		mouth.Size = m.mouth
		mouth.Color = Blocks.color(m.mouthColor)
	end
end

-- Moves the upper and lower part of a limb: the upper about its joint, the lower about its own joint after that.
local function limb(rig: Rig, at: CFrame, upper: { string }, pivot: Vector3, rot: CFrame, lower: { string }, pivot2: Vector3, rot2: CFrame)
	local up = at * CFrame.new(pivot) * rot * CFrame.new(-pivot)
	for _, n in upper do
		local p = rig.parts[n]
		if p then
			p.CFrame = up * rig.rest[n]
		end
	end
	local low = up * CFrame.new(pivot2) * rot2 * CFrame.new(-pivot2)
	for _, n in lower do
		local p = rig.parts[n]
		if p then
			p.CFrame = low * rig.rest[n]
		end
	end
end

-- Pose a standing rig at `base` (the ground between the feet, facing +Z).
function CharacterModels.posePose(rig: Rig, base: CFrame, P: Pose)
	setMood(rig, P.mood or "calm")
	local crouch = P.crouch or 0
	-- a crouch: the thighs forward and the knees back by the angle that drops the hips this far
	local bend = math.acos(math.clamp(1 - crouch / 1.1, -1, 1))
	local root = base * CFrame.new(0, -crouch + (P.lift or 0), 0)
	limb(rig, root, THIGH_L, HIP_L, CFrame.Angles(-bend + (P.hipL or 0), 0, 0), SHIN_L, KNEE_L, CFrame.Angles(bend * 2 + (P.kneeL or 0), 0, 0))
	limb(rig, root, THIGH_R, HIP_R, CFrame.Angles(-bend + (P.hipR or 0), 0, 0), SHIN_R, KNEE_R, CFrame.Angles(bend * 2 + (P.kneeR or 0), 0, 0))
	-- the body leans and twists about the waist; the arms and the head go with it
	local body = root * CFrame.new(WAIST) * CFrame.Angles(P.lean or 0, P.twist or 0, 0) * CFrame.new(-WAIST)
	for _, n in BODY_PARTS do
		local p = rig.parts[n]
		if p then
			p.CFrame = body * rig.rest[n]
		end
	end
	limb(rig, body, UPPER_L, ARM_L, P.armL or CFrame.identity, LOWER_L, ELBOW_L, CFrame.Angles(-(P.elbowL or 0), 0, 0))
	limb(rig, body, UPPER_R, ARM_R, P.armR or CFrame.identity, LOWER_R, ELBOW_R, CFrame.Angles(-(P.elbowR or 0), 0, 0))
	local head = body * CFrame.new(STAND_NECK) * (P.head or CFrame.identity) * CFrame.new(-STAND_NECK)
	for _, n in HEAD_PARTS do
		local p = rig.parts[n]
		if p and rig.rest[n] then
			p.CFrame = head * rig.rest[n]
		end
	end
end

-- The walk or the stand (breathing, looking round now and then) at `speed` studs a second, as a Pose.
local function walkPose(rig: Rig, t: number, speed: number): Pose
	local ph = rig.seed * 1.3
	local walk = math.clamp(speed / 16, 0, 1)
	local cycle = (t + ph) * (if walk > 0.7 then 13 else 11)
	local swing = math.sin(cycle) * math.rad(34) * walk
	local bob = if walk > 0.05 then math.abs(math.cos(cycle)) * 0.12 * walk else math.sin((t + ph) * 2) * 0.03
	local headRot = CFrame.identity
	if walk <= 0.05 then
		local look = math.sin((t + ph) * 0.6)
		headRot = CFrame.Angles(0, if math.abs(look) > 0.85 then math.rad(20) * math.sign(look) else 0, 0)
	end
	-- the knee bends as the leg swings back; the elbows bend a little
	return {
		lean = math.rad(8) * walk,
		lift = bob,
		hipL = -swing,
		kneeL = math.max(0, swing) * 1.1,
		hipR = swing,
		kneeR = math.max(0, -swing) * 1.1,
		armL = CFrame.Angles(swing * 0.8, 0, 0),
		elbowL = math.rad(15) + math.max(0, -swing) * 0.6,
		armR = CFrame.Angles(-swing * 0.8, 0, 0),
		elbowR = math.rad(15) + math.max(0, swing) * 0.6,
		head = headRot,
		mood = "calm",
	}
end

-- Pose a founder at `base` walking at `speed` studs a second (0: standing, breathing, looking round now and then).
function CharacterModels.poseStanding(rig: Rig, base: CFrame, t: number, speed: number)
	CharacterModels.posePose(rig, base, walkPose(rig, t, speed))
end

-- Work at a building on the island (GAME_DESIGN 5; WorldView): each a loop, `k` the beat's phase (0 .. 1, round and
-- round), `t` the clock for the small moves. WORK_HIT says where in the beat a blow lands (WorldView puts the chips,
-- the dirt or the splash there).
local function rad(d: number): number
	return math.rad(d)
end
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
-- the tool's height through a beat: up slowly, down fast at `hit`, a moment at the bottom
local function strokeOf(k: number, hit: number): number
	if k < hit - 0.12 then
		return smooth(k / (hit - 0.12))
	elseif k < hit then
		return 1 - (k - (hit - 0.12)) / 0.12
	end
	return 0
end
local WORK: { [string]: (P: any, t: number, k: number) -> () } = {
	-- a hoe at a field: up over the head, down into the soil
	dig = function(P, _t, k)
		local up = strokeOf(k, 0.62)
		P.lean = rad(12 + 16 * (1 - up))
		P.crouch = 0.08 + 0.14 * (1 - up)
		P.hipL, P.kneeL = rad(-25), rad(15)
		P.hipR, P.kneeR = rad(20), rad(20)
		local a = rad(-35 - 135 * up)
		P.armR, P.armL = CFrame.Angles(a, 0, rad(-6)), CFrame.Angles(a, 0, rad(6))
		P.elbowL, P.elbowR = rad(15), rad(15)
	end,
	-- picking fruit: one hand up into the branches, then the other, up on the toes
	pick = function(P, t, k)
		local left = k < 0.5
		local reach = math.sin((k % 0.5) / 0.5 * math.pi)
		local hi, lo = CFrame.Angles(rad(-150 - 20 * reach), 0, rad(8)), CFrame.Angles(rad(-40), 0, 0)
		P.armL, P.armR = if left then hi else lo, if left then lo else hi
		P.elbowL, P.elbowR = if left then rad(10) else rad(60), if left then rad(60) else rad(10)
		P.lift = 0.12 * reach
		P.head = CFrame.Angles(rad(-25), rad(6 * math.sin(t * 2)), 0)
		P.mood = "happy"
	end,
	-- a line in the water: the rod held out, bobbing, and a tug at the end of the beat
	fish = function(P, t, k)
		local tug = if k > 0.82 then math.sin((k - 0.82) / 0.18 * math.pi) else 0
		local a = rad(-100 + 4 * math.sin(t * 3) - 55 * tug)
		P.armR, P.armL = CFrame.Angles(a, 0, rad(-10)), CFrame.Angles(a + rad(15), 0, rad(10))
		P.elbowL, P.elbowR = rad(25), rad(25)
		P.lean = rad(4 - 14 * tug)
		P.hipL, P.hipR = rad(-12), rad(12)
	end,
	-- an axe at a log: back over the shoulder, then a hard chop
	chop = function(P, _t, k)
		local up = strokeOf(k, 0.7)
		P.lean = rad(6 + 16 * (1 - up))
		P.crouch = 0.1 + 0.1 * (1 - up)
		P.hipL, P.kneeL = rad(-30), rad(10)
		P.hipR, P.kneeR = rad(28), rad(22)
		P.armR = CFrame.Angles(rad(-15 - 160 * up), 0, rad(-8))
		P.armL = CFrame.Angles(rad(-25 - 140 * up), 0, rad(8))
		P.elbowL, P.elbowR = rad(20), rad(10)
		P.twist = rad(-18 * up + 8 * (1 - up))
		P.mood = if up < 0.2 then "shout" else nil
	end,
	-- a saw through a plank: both hands on it, to and fro
	saw = function(P, _t, k)
		local s = math.sin(k * math.pi * 4)
		P.lean = rad(14 + 6 * s)
		P.crouch = 0.12
		P.hipL, P.hipR = rad(-25), rad(18)
		P.armR, P.armL = CFrame.Angles(rad(-70 - 18 * s), 0, 0), CFrame.Angles(rad(-60 - 18 * s), 0, rad(10))
		P.elbowL, P.elbowR = rad(40 + 25 * s), rad(40 + 25 * s)
	end,
	-- behind a counter: handing something over, then a wave to the next one
	sell = function(P, t, k)
		if k < 0.55 then
			local out = math.sin(k / 0.55 * math.pi)
			P.armR = CFrame.Angles(rad(-45 - 45 * out), 0, 0)
			P.elbowR = rad(50 * (1 - out))
			P.lean = rad(8 * out)
		else
			P.armL = CFrame.Angles(0, 0, rad(-140 + 20 * math.sin(t * 14)))
			P.elbowL = rad(25)
		end
		P.mood = "happy"
	end,
	-- carrying a tray round: held up on one hand, a turn this way and that, a small bow
	serve = function(P, t, k)
		P.armR = CFrame.Angles(rad(-95), 0, rad(-10))
		P.elbowR = rad(80)
		P.armL = CFrame.Angles(rad(-20), 0, rad(-10))
		P.twist = rad(14 * math.sin(k * math.pi * 2))
		local bow = if k > 0.8 then math.sin((k - 0.8) / 0.2 * math.pi) else 0
		P.lean = rad(22 * bow)
		P.head = CFrame.Angles(rad(4 * math.sin(t * 3)), 0, 0)
		P.mood = "happy"
	end,
	-- a hammer on a nail: short quick taps, crouched
	hammer = function(P, _t, k)
		local up = strokeOf((k * 2) % 1, 0.7)
		P.crouch = 0.3
		P.lean = rad(20)
		P.armR = CFrame.Angles(rad(-40 - 80 * up), 0, 0)
		P.elbowR = rad(30 + 40 * up)
		P.armL = CFrame.Angles(rad(-50), 0, rad(15))
		P.elbowL = rad(40)
	end,
	-- training: a punch with each hand, bouncing on the feet
	train = function(P, _t, k)
		local left = k < 0.5
		local out = math.sin((k % 0.5) / 0.5 * math.pi)
		local punch, guard = CFrame.Angles(rad(-90), 0, 0), CFrame.Angles(rad(-70), rad(20), 0)
		P.armL, P.armR = if left then punch else guard, if left then guard else punch
		P.elbowL, P.elbowR = if left then rad(90 * (1 - out)) else rad(95), if left then rad(95) else rad(90 * (1 - out))
		P.twist = rad(if left then 14 * out else -14 * out)
		P.lift = 0.08 * math.abs(math.sin(k * math.pi * 4))
		P.hipL, P.hipR = rad(-15), rad(15)
		P.mood = "fierce"
	end,
	-- tending something low (eggs, a still, the beacon's fire): crouched, patting it now and then
	tend = function(P, t, k)
		local pat = if k < 0.4 then math.abs(math.sin(k / 0.4 * math.pi * 2)) else 0
		P.crouch = 0.35
		P.lean = rad(18)
		P.armL, P.armR = CFrame.Angles(rad(-55 - 20 * pat), 0, 0), CFrame.Angles(rad(-55 - 20 * pat), 0, 0)
		P.elbowL, P.elbowR = rad(35), rad(35)
		P.head = CFrame.Angles(rad(15), rad(8 * math.sin(t * 0.8)), 0)
	end,
}
CharacterModels.WORK_HIT = { dig = { 0.62 }, chop = { 0.7 }, hammer = { 0.35, 0.85 }, fish = { 0.9 }, sell = { 0.27 }, train = { 0.25, 0.75 } } :: { [string]: { number } }

-- A founder doing something (the islands, the cutscenes): the walk or stand of poseStanding, then the
-- action, k 0..1 its progress where it has one:
--   "cheer" both arms up waving, happy; "hurt" flinching back, arms flung out; "swing" the right arm from high up (k 0)
--   down in front (k 1); "reach" both arms out in front; "pet" the right arm patting; "cast" the right arm raised;
--   "jump" knees up and arms up; "sneak" crouched with arms forward; "dance" the arms in turn; and (from the old fights)
--   "windup" (crouched, leaning back, the fist drawn back: fierce), "strike" (a lunge, the fist swinging through
--   with k: shouting), "guard" (crouched behind crossed arms), "throw" (an overhand throw with k), "run" (leaning
--   into a sprint), "victory" (a jump with a fist pumped up), "ko" (flat on the back, eyes shut); "swim" (in the sea:
--   a crawl when speed > 1, else treading water).
function CharacterModels.poseAction(rig: Rig, base: CFrame, t: number, speed: number, action: string, k: number?)
	local kk = math.clamp(k or 0, 0, 1)
	local P = walkPose(rig, t, if action == "run" then math.max(speed, 20) else (if action == "jump" or action == "ko" or action == "swim" then 0 else speed))
	if action == "cheer" then
		local wave = math.sin(t * 12) * 0.25
		P.armL = CFrame.Angles(0, 0, math.rad(-150 + wave * 25))
		P.armR = CFrame.Angles(0, 0, math.rad(150 - wave * 25))
		P.elbowL, P.elbowR = math.rad(20), math.rad(20)
		P.mood = "happy"
	elseif action == "hurt" then
		P.lean = math.rad(-18)
		P.armL = CFrame.Angles(math.rad(-20), 0, math.rad(-100))
		P.armR = CFrame.Angles(math.rad(-20), 0, math.rad(100))
		P.elbowL, P.elbowR = math.rad(30), math.rad(30)
		P.head = CFrame.Angles(math.rad(-15), 0, math.rad(10))
		P.crouch = 0.1
		P.mood = "hurt"
	elseif action == "swing" or action == "strike" then
		P.lean = math.rad(16)
		P.crouch = 0.15
		P.hipL, P.kneeL = math.rad(-35), math.rad(10)
		P.hipR, P.kneeR = math.rad(30), math.rad(25)
		P.armR = CFrame.Angles(math.rad(-165 + 150 * kk), 0, 0)
		P.elbowR = math.rad(10)
		P.armL = CFrame.Angles(math.rad(35), 0, math.rad(-20))
		P.elbowL = math.rad(40)
		P.twist = math.rad(-15 + 30 * kk)
		P.mood = "shout"
	elseif action == "windup" then
		P.lean = math.rad(-10)
		P.crouch = 0.35
		P.twist = math.rad(20)
		P.armR = CFrame.Angles(math.rad(55), 0, math.rad(15))
		P.elbowR = math.rad(85)
		P.armL = CFrame.Angles(math.rad(-50), 0, 0)
		P.elbowL = math.rad(40)
		P.mood = "fierce"
	elseif action == "guard" then
		P.crouch = 0.3
		P.lean = math.rad(6)
		P.armL = CFrame.Angles(math.rad(-95), math.rad(-25), 0)
		P.armR = CFrame.Angles(math.rad(-95), math.rad(25), 0)
		P.elbowL, P.elbowR = math.rad(75), math.rad(75)
		P.head = CFrame.Angles(math.rad(10), 0, 0)
		P.mood = "fierce"
	elseif action == "throw" then
		P.lean = math.rad(-12 + 28 * kk)
		P.armR = CFrame.Angles(math.rad(-210 + 150 * kk), 0, 0)
		P.elbowR = math.rad(40 * (1 - kk))
		P.armL = CFrame.Angles(math.rad(-60 + 70 * kk), 0, 0)
		P.hipL, P.hipR = math.rad(-20), math.rad(20)
		P.mood = "happy"
	elseif action == "victory" then
		local up = math.floor(t * 5) % 2 == 0
		P.lift = if up then 0.5 else 0
		P.armR = CFrame.Angles(0, 0, math.rad(165))
		P.elbowR = math.rad(10)
		P.armL = CFrame.Angles(math.rad(-30), 0, math.rad(-25))
		P.elbowL = math.rad(90)
		P.hipL, P.kneeL = if up then math.rad(-30) else 0, if up then math.rad(60) else 0
		P.mood = "happy"
	elseif action == "ko" then
		CharacterModels.posePose(rig, base * CFrame.new(0, 0.4, 0) * CFrame.Angles(math.rad(-90), 0, 0), {
			armL = CFrame.Angles(0, 0, math.rad(-60)),
			armR = CFrame.Angles(0, 0, math.rad(60)),
			head = CFrame.Angles(0, 0, math.rad(15)),
			mood = "ko",
		})
		return
	elseif action == "reach" then
		P.armL, P.armR = CFrame.Angles(math.rad(-80), 0, 0), CFrame.Angles(math.rad(-80), 0, 0)
		P.elbowL, P.elbowR = math.rad(10), math.rad(10)
	elseif action == "pet" then
		P.armR = CFrame.Angles(math.rad(-70 + math.sin(t * 16) * 14 * kk), 0, 0)
		P.elbowR = math.rad(20)
		P.mood = "happy"
	elseif action == "cast" then
		P.armR = CFrame.Angles(math.rad(-160), 0, 0)
		P.armL = CFrame.Angles(math.rad(-35), 0, 0)
	elseif action == "jump" then
		P.hipL, P.kneeL = math.rad(-50), math.rad(85)
		P.hipR, P.kneeR = math.rad(-30), math.rad(60)
		P.armL = CFrame.Angles(0, 0, math.rad(-140))
		P.armR = CFrame.Angles(0, 0, math.rad(140))
		P.mood = "happy"
	elseif action == "sneak" then
		P.crouch = 0.3
		P.armL, P.armR = CFrame.Angles(math.rad(-55), 0, 0), CFrame.Angles(math.rad(-55), 0, 0)
		P.elbowL, P.elbowR = math.rad(30), math.rad(30)
	elseif action == "dance" then
		local up = math.floor(t * 4) % 2 == 0
		P.armL = CFrame.Angles(0, 0, math.rad(if up then -150 else -30))
		P.armR = CFrame.Angles(0, 0, math.rad(if up then 30 else 150))
		P.mood = "happy"
	elseif action == "run" then
		P.lean = math.rad(18)
	elseif action == "swim" then
		-- in the sea (AvatarView sinks the rig to its chest): moving, a crawl (the arms turning over in turn, the legs
		-- kicking, leaning into it); still, treading water (the arms sweeping out and back, a slow bob)
		if speed > 1 then
			local a = (t * 5) % (math.pi * 2)
			P.lean = math.rad(30)
			P.armL = CFrame.Angles(-a, 0, math.rad(-12))
			P.armR = CFrame.Angles(-(a + math.pi), 0, math.rad(12))
			P.elbowL, P.elbowR = math.rad(15), math.rad(15)
			P.hipL, P.kneeL = math.sin(t * 12) * math.rad(20), math.rad(10)
			P.hipR, P.kneeR = -math.sin(t * 12) * math.rad(20), math.rad(10)
		else
			local sw = math.sin(t * 3)
			P.lean = 0
			P.armL = CFrame.Angles(0, sw * 0.4, math.rad(-70))
			P.armR = CFrame.Angles(0, -sw * 0.4, math.rad(70))
			P.elbowL, P.elbowR = math.rad(25), math.rad(25)
			P.hipL, P.kneeL = math.rad(-15) + sw * 0.2, math.rad(40)
			P.hipR, P.kneeR = math.rad(-15) - sw * 0.2, math.rad(40)
			P.lift = 0.06 * math.sin(t * 2)
		end
		P.mood = "happy"
	elseif WORK[action] then
		WORK[action](P, t, kk)
	end
	CharacterModels.posePose(rig, base, P)
end

-- Where a founder's name label floats (rig space).
CharacterModels.STAND_TOP = Vector3.new(0, 4.6, 0)

return CharacterModels
