--!strict
-- The founders (GAME_DESIGN 12; docs/ARCHITECTURE.md 10.6): every player walks the street as a little chibi in the
-- crew's style (Models/CharacterModels.buildStanding), their look from the player's "Founder" attribute (the server
-- sets it from profile.founder). The rig follows the player's character every frame: its feet on the ground under the
-- HumanoidRootPart, facing where the character faces, its legs and arms swinging with its speed. The Roblox avatar
-- itself is hidden on this client (LocalTransparencyModifier; the pixel bake never sees characters), so the classic
-- style shows the chibis too. Every founder (GAME_DESIGN 14.1; the request of 2026-11-14: "make the player be outlined
-- white like the bakery game, with the name and title on top") wears the pieces of its look (Data/Looks.decode of the
-- "Founder" attribute: the colours, the hair style and a piece in each of Data/Cosmetics' slots, built by
-- Models/CharacterModels), is outlined in white (PixelRenderer's rim: outline "self" for the player's own, "player" for
-- the others; a white Highlight in the classic style) and has a name tag over its head with the title it wears
-- (Controllers/NameTags, the "Title" attribute). Walking feet kick up puffs of dust, and splashes in a river or pond
-- laid on an island. (The founders swam between the islands from 2026-11-13 until the islands took to the sky on
-- 2026-11-20: GAME_DESIGN 8.)
-- Standing about (the request of 2026-11-15: "add more motion to the player, just like in the bakery game, like dozing
-- off while afk"): a founder breathes, shifts its weight, blinks, and every few seconds still does a fidget
-- (CharacterModels.poseFounder: a look round, a toe tap, a yawn, a scratch, a hum, rocking, a stretch). Left alone
-- Tuning.DozeSecs it dozes off where it stands, nodding, and Z's float up from its head (`zz_s` and `zz_b`, on the
-- World canvas at whole UI px, a pair a nod, floating up beside the name tag). The own founder counts the time since the player last touched a key,
-- the mouse or the screen and since it last moved; another player's, since it last moved. A landing squashes the
-- legs for a moment; a quest claimed or the island grown makes the own founder cheer (`cheer`). Reduced motion: no
-- fidgets, the Z's stay put.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Cosmetics = require(ReplicatedStorage.Shared.Data.Cosmetics)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.CameraController)
local Audio = require(script.Parent.Audio)
local Puffs = require(script.Parent.Puffs)
local NameTags = require(script.Parent.NameTags)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local PixelSprites = require(script.Parent.Parent.UI.PixelSprites)

local AvatarView = {}

type Rec = {
	rig: CharacterModels.Rig,
	sig: string,
	last: Vector3?,
	speed: number,
	tag: NameTags.Tag, -- the name and title over its head
	hl: Highlight?, -- its white outline in the classic style (the pixel filter off)
	top: number?, -- how high over its feet its head (and hat) reach: the name tag's place
	char: Model?,
	dustAt: number, -- when their feet next kick up a puff of dust (walking)
	air: boolean, -- in the air (a jump) last frame
	rest: number?, -- the root's height over the ground as it last stood
	floor: string, -- what the feet are on: "grass", "sand", "wood" or "water" (a river or pond on an island)
	stepAt: number, -- when the own founder's next footstep sounds
	idle: number, -- seconds standing still on the ground (0 while walking, jumping or in a cutscene)
	landAt: number, -- when it last landed from a jump (the squash)
	zAt: number, -- when its next Z floats up while dozing
	zBig: boolean, -- the next Z the big one
}

-- What a ground hit is, for the footsteps: a river or pond drawn on the island wading, planks and beams wood, anything
-- lower than the lawn sand, everything else (the lawn, a path, a piece) grass.
local function floorOf(hit: RaycastResult?): string
	if hit == nil then
		return "grass"
	end
	local n = hit.Instance.Name
	-- (a river or pond drawn on the island: the founder wades through it, splashing: GAME_DESIGN 4.3)
	if hit.Instance:GetAttribute("PixelWater") ~= nil then
		return "water"
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
local inputAt = os.clock() -- when the player last touched a key, the mouse or the screen
local cheerUntil = 0 -- the own founder cheers until then (`cheer`)
local CHEER_SECS = 1.6
local LAND_SECS = 0.2 -- a landing's squash
local Z_LIFE, Z_POP, Z_BLINK = 1.8, 0.12, 0.3 -- a Z's life, its pop in and its blinking out (seconds)

-- The Z's over dozing founders: each floats up and to the right of the head it came from, swaying, and blinks out.
type Zed = { img: GuiObject, pl: Player, rec: Rec, t0: number, w: number, h: number }
local zeds: { Zed } = {}

local function quietMotion(): boolean
	local ok, on = pcall(function(): boolean
		return GuiService.ReducedMotionEnabled
	end)
	return ok and on == true
end

local function dozing(pl: Player, rec: Rec, t: number): boolean
	if rec.idle < Tuning.DozeSecs then
		return false
	end
	return pl ~= Players.LocalPlayer or t - inputAt >= Tuning.DozeSecs
end

-- A Z from a dozing founder's head (the small one, then the big one, by turns).
local function puffZ(pl: Player, rec: Rec, t: number)
	local name = if rec.zBig then "zz_b" else "zz_s"
	rec.zBig = not rec.zBig
	local img = PixelSprites.image(UIKit.canvas("World"), name, UDim2.fromOffset(0, 0), 6)
	img.Name = "Zed"
	img.Visible = false
	local s = img.Size
	table.insert(zeds, { img = img, pl = pl, rec = rec, t0 = t, w = s.X.Offset, h = s.Y.Offset })
end

local function stepZeds(t: number)
	local still = quietMotion()
	for i = #zeds, 1, -1 do
		local z = zeds[i]
		local age = t - z.t0
		local rig = z.rec.rig
		local head: BasePart? = rig.parts.Head
		if age >= Z_LIFE or head == nil or recs[z.pl] ~= z.rec then
			z.img:Destroy()
			table.remove(zeds, i)
			continue
		end
		local hp = head :: BasePart
		local top = hp.Position + Vector3.new(0, hp.Size.Y * 0.5, 0)
		local x0, y0, on = PixelRenderer.projectPixel(top)
		local u = if still then 0 else age / Z_LIFE
		-- (from just right of the name tag over the head, up and to the right, swaying; 2 px then 1 px low as it pops
		-- in; blinking out at the end; whole UI px)
		local half = math.floor(z.rec.tag.frame.Size.X.Offset / 2)
		local pop = if age < Z_POP * 0.5 then 2 elseif age < Z_POP then 1 else 0
		local dx = half + 1 + math.floor(u * 8 + (if still then 0 else math.sin(age * 9) * 1.5) + 0.5)
		local dy = 2 - math.floor(u * 16 + 0.5) + pop
		local blink = age > Z_LIFE - Z_BLINK and math.floor((age - (Z_LIFE - Z_BLINK)) / 0.08) % 2 == 1
		z.img.Visible = on and not blink
		z.img.Position = UDim2.fromOffset(x0 + dx, y0 + dy - z.h)
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

-- A player's look from their "Founder" attribute (Data/Looks.decode: indices clamped to the lists, a piece kept only
-- when it is a known one of that slot), or one from their user id while there is none. The string is the rig's key:
-- a new one rebuilds it.
-- (each player's look as last decoded, by the attribute's words: decoded again only when they change; it was every
-- player's every frame)
local lookCache: { [Player]: { raw: string, look: Types.Look, sig: string } } = setmetatable({}, { __mode = "k" }) :: any
local decodeLook: (pl: Player, s: string) -> (Types.Look, string)
local function lookOf(pl: Player): (Types.Look, string)
	local a = pl:GetAttribute("Founder")
	local s = if type(a) == "string" then a else ""
	local c = lookCache[pl]
	if c and c.raw == s then
		return c.look, c.sig
	end
	local look, sig = decodeLook(pl, s)
	lookCache[pl] = { raw = s, look = look, sig = sig }
	return look, sig
end
decodeLook = function(pl: Player, s: string): (Types.Look, string)
	local d = Looks.decode(s)
	if d then
		local look: Types.Look = {
			skin = math.clamp(math.floor(tonumber(d.skin) or 1), 1, #Looks.skin),
			hair = math.clamp(math.floor(tonumber(d.hair) or 1), 1, #Looks.hair),
			style = math.clamp(math.floor(tonumber(d.style) or 1), 1, #Looks.styles),
			shirt = math.clamp(math.floor(tonumber(d.shirt) or 1), 1, #Looks.shirt),
		}
		for _, slot in Looks.worn do
			local id = d[slot]
			local c = if type(id) == "string" then Cosmetics.byId[id] else nil
			if c and c.slot == slot then
				(look :: any)[slot] = id
			end
		end
		return look, s
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

local still = false -- (previews: debugStill)

local function drop(pl: Player)
	if pl == Players.LocalPlayer then
		CameraController.setDrawn(nil)
	end
	local r = recs[pl]
	if r then
		PixelRenderer.unregisterDynamic(r.rig.model)
		r.rig.model:Destroy()
		NameTags.drop(r.tag)
		recs[pl] = nil
	end
end

-- Where a character's feet are: on the ground under it (the lawn, a floor, the boardwalk) while it stands there; in the
-- air (a jump: Humanoid.FloorMaterial is Air) at its root's height less the root's height over the ground as it last
-- stood (learnt, whatever the avatar's size), so the chibi leaves the ground with it. True while airborne.
-- (what the ground rays leave out: the dynamic models and every character, set on the rays' params only when the
-- characters change; it was rebuilt and set on both params for every player every frame)
local filterList: { Instance } = {}
local function updateFilter()
	local list: { Instance } = { dyn() }
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		if ch then
			table.insert(list, ch)
		end
	end
	local same = #list == #filterList
	if same then
		for i, x in list do
			if filterList[i] ~= x then
				same = false
				break
			end
		end
	end
	if not same then
		filterList = list
		groundParams.FilterDescendantsInstances = list
		wetParams.FilterDescendantsInstances = list
	end
end
local function feetY(rec: Rec, char: Model, root: BasePart): (number, boolean)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local inAir = hum ~= nil and hum.FloorMaterial == Enum.Material.Air
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), groundParams)
	if hit then
		rec.floor = floorOf(hit)
		-- (a river, pond or pool laid on the ground doesn't collide either: wading in it splashes)
		local wet = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), wetParams)
		if wet and wet.Instance:GetAttribute("PixelWater") ~= nil and wet.Position.Y <= hit.Position.Y + 1 then
			rec.floor = floorOf(wet)
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
	updateFilter()
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
			CharacterModels.setScale(rig, Tuning.FounderScale)
			rig.model.Parent = dyn()
			-- (outlined in white: the player's own "self", everyone else's "player")
			PixelRenderer.registerDynamic(rig.model, if pl == me then "self" else "player")
			r = { rig = rig, sig = sig, last = nil, speed = 0, tag = NameTags.make(pl), char = nil, dustAt = 0, air = false, floor = "grass", stepAt = 0, idle = 0, landAt = -1, zAt = 0, zBig = false }
			recs[pl] = r
		end
		local rec = r :: Rec
		if rec.char ~= char then
			rec.char = char
			hide(char)
		end
		-- the classic style (no pixel filter) outlines the founders with a white Highlight in place of the rim (the own
		-- one seen through the scenery, like the rim's dotted part)
		local classic = PixelRenderer.tier() == "off"
		if classic and rec.hl == nil then
			local hl = Instance.new("Highlight")
			hl.Name = "Outline"
			hl.FillTransparency = 1
			hl.OutlineColor = Color3.new(1, 1, 1)
			hl.OutlineTransparency = 0
			hl.DepthMode = if pl == me then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
			hl.Adornee = rec.rig.model
			hl.Parent = rec.rig.model
			rec.hl = hl
		elseif not classic and rec.hl then
			(rec.hl :: Highlight):Destroy()
			rec.hl = nil
		end
		NameTags.refresh(rec.tag, pl)
		if pl == me and override then
			-- (a cutscene poses the own founder: its tag steps aside)
			(override :: (CharacterModels.Rig, number, number) -> ())(rec.rig, t, dt)
			CameraController.setDrawn(nil)
			rec.tag.frame.Visible = false
			rec.last = nil
			rec.idle = 0
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
		local fy, airborne = feetY(rec, char, root)
		local mine = pl == me
		local at = Vector3.new(pos.X, fy, pos.Z)
		if mine then
			-- (the own founder on a whole art px of the view's grid, and the camera told where: the layer's window is put
			-- from it, so the founder keeps still on the screen as they walk; the report of 2026-11-21, "the camera now
			-- stutters the player as they walk")
			at = CameraController.snapGround(at)
			CameraController.setDrawn(at)
		end
		local base = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
		-- (the own founder's feet are heard: library sounds in place of Roblox's own, which RbxCharacterSounds turns off)
		if airborne then
			-- a jump: knees up, arms up, off the ground with the character
			CharacterModels.poseAction(rec.rig, base, t, 0, "jump")
			rec.idle = 0
			if mine and not rec.air then
				Audio.play("jump")
			end
			rec.air = true
		else
			if rec.air then
				rec.landAt = t
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
			-- standing about: fidgets once still a while, the doze once left alone (the Z's a pair a nod), the cheer
			rec.idle = if rec.speed > 1.5 then 0 else rec.idle + dt
			local asleep = dozing(pl, rec, t)
			local squash = if rec.landAt >= 0 and t - rec.landAt < LAND_SECS then 1 - (t - rec.landAt) / LAND_SECS else 0
			if mine and t < cheerUntil then
				CharacterModels.poseAction(rec.rig, base, t, rec.speed, "cheer")
			elseif still then
				-- (previews: standing, so a probe follows where the picture goes and nothing else)
				CharacterModels.poseFounder(rec.rig, base, 0, 0, 0, false, true, 0)
			else
				CharacterModels.poseFounder(rec.rig, base, t, rec.speed, rec.idle, asleep, quietMotion(), squash)
			end
			if asleep and t >= rec.zAt then
				rec.zAt = t + CharacterModels.NOD_SEC * 0.5
				puffZ(pl, rec, t)
			elseif not asleep then
				rec.zAt = t + 1
			end
		end
		-- a walk kicks up a puff of dust now and then, a run more often (in water: splashes)
		if not airborne and rec.speed > 6 and t >= rec.dustAt and rec.floor == "water" then
			rec.dustAt = t + (if rec.speed > 14 then 0.14 else 0.24)
			Puffs.burst("drop", (base * CFrame.new(0, 0.1, -0.3)).Position, 3, 0.3)
		elseif not airborne and rec.speed > 6 and t >= rec.dustAt then
			rec.dustAt = t + (if rec.speed > 14 then 0.18 else 0.3)
			UIKit.bitsAt((base * CFrame.new(0, 0.1, -0.4)).Position, { "white", "text_dim" }, 2, 14, 40)
		end
		-- the name tag over the head, and over a hat when one is worn (CharacterModels.topOf, worked out once a rig)
		local top = rec.top or CharacterModels.topOf(rec.rig)
		rec.top = top
		NameTags.place(rec.tag, (base * CFrame.new(0, top + 0.2, 0)).Position)
	end
	for pl in recs do
		if pl.Parent == nil then
			drop(pl)
		end
	end
	stepZeds(t)
end

-- Previews: founders posed standing still whatever they do (debugStill), so a probe follows their picture alone.
function AvatarView.debugStill(on: boolean)
	still = on
end

-- The founder's position on this client (the local player's rig's feet), for the HUD and Build mode.
function AvatarView.founderPos(): Vector3?
	local r = recs[Players.LocalPlayer]
	local torso = if r then r.rig.parts.Torso else nil
	return if torso then torso.Position else nil
end

-- A cutscene poses the own founder (nil: back to following the character).
function AvatarView.setOverride(fn: ((rig: CharacterModels.Rig, t: number, dt: number) -> ())?)
	override = fn
end

-- CLI checks only: a player's name tag (its name, its title line or nil, whether it shows), the rig and whether it
-- is outlined (the pixel filter's rim registered, or its Highlight in the classic style).
function AvatarView.debugTag(pl: Player): (string?, string?, boolean)
	local r = recs[pl]
	if r == nil then
		return nil, nil, false
	end
	return NameTags.texts(r.tag)
end
function AvatarView.debugRig(pl: Player): (CharacterModels.Rig?, boolean)
	local r = recs[pl]
	if r == nil then
		return nil, false
	end
	return r.rig, PixelRenderer.hasRim(r.rig.model) or r.hl ~= nil
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
	-- (the player is here while they touch anything: a key, the mouse, the screen, a pad)
	UserInputService.InputBegan:Connect(function()
		inputAt = os.clock()
	end)
	UserInputService.InputChanged:Connect(function()
		inputAt = os.clock()
	end)
end

-- The own founder cheers a moment (a quest claimed, the island grown): arms up, waving, smiling. It wakes it too.
function AvatarView.cheer()
	cheerUntil = os.clock() + CHEER_SECS
	inputAt = os.clock()
	local r = recs[Players.LocalPlayer]
	if r then
		r.idle = 0
	end
end

-- Sims and previews: a player's founder standing about (seconds still, dozing, the fidget now, the Z's in the air),
-- and the clock of the last input moved back `secs` (as if the player had left the keys that long ago).
function AvatarView.debugIdle(pl: Player): { idle: number, dozing: boolean, fidget: string?, zeds: number, cheering: boolean }
	local r = recs[pl]
	local t = os.clock()
	if r == nil then
		return { idle = 0, dozing = false, fidget = nil, zeds = 0, cheering = false }
	end
	local name = CharacterModels.fidgetAt(r.rig, t, r.idle)
	local n = 0
	for _, z in zeds do
		if z.rec == r then
			n += 1
		end
	end
	return { idle = r.idle, dozing = dozing(pl, r, t), fidget = name, zeds = n, cheering = pl == Players.LocalPlayer and t < cheerUntil }
end
function AvatarView.debugAway(secs: number)
	inputAt = os.clock() - secs
	local r = recs[Players.LocalPlayer]
	if r then
		r.idle = math.max(r.idle, secs)
	end
end

-- A player's founder look (the microgames' stage dresses the player's own rig in it).
function AvatarView.lookOf(pl: Player): Types.Look
	local look = lookOf(pl)
	return look
end

return AvatarView
