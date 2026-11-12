--!strict
-- Going into a wild place and coming home (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.8). The module keeps its old name
-- (the voyages by boat it once played are gone with the sea chart).
--   Going in (`play`): the founder walks from where they stand to the wild place on the island (Data/Sites: its front,
--   where its mouth or pool is), the camera following; ink blinds close over it with the place's name, kind and level.
--   Then the place's screen opens (ExpeditionUI, its curtain already closed, so there is no visible cut).
--   Coming home (`home`): the place's screen closes behind blinds; behind them the founder is put in front of the place
--   and the view goes there; they open on the island and the founder cheers. `reveal` is the plain blinds opening on
--   the island (Leave it here for now).
-- While one plays the HUD hides, the character can't walk, AvatarView lets this module pose the own founder, and
-- CameraController follows the cutscene's focus instead of the character. Skip (or Space / Return) jumps to its end.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local SiteData = require(ReplicatedStorage.Shared.Data.Sites)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local AvatarView = require(script.Parent.Parent.Controllers.AvatarView)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

local Voyage = {}

local WALK = 13 -- studs a second
local CLOSE = 0.4 -- seconds the blinds take to close (or open)
local MAX_WALK = 40 -- a longer walk starts the founder closer to the place (behind the letterbox's first moment)
local OPEN_WAIT = 4 -- seconds the blinds wait at most for the island's picture before opening

type State = {
	dir: string, -- "out" (going in) | "home" (coming home) | "reveal"
	phase: string, -- out: "open" "walk" "close" "done"; home: "wait" "land" "done"; reveal: "wait" "open" "done"
	t: number, -- seconds in the phase
	total: number,
	route: { Vector3 }, -- the founder's walk (world, feet on the ground)
	leg: number,
	pos: Vector3, -- the founder's feet now (world)
	yaw: number,
	spot: Vector3, -- where the founder ends up: in front of the place
	isle: Types.Isle?,
	site: string?, -- the place's kind (Data/Sites id)
	onDone: () -> (),
	gui: Frame?,
	blinds: { Frame },
	title: Frame?,
	conns: { RBXScriptConnection },
	walkSpeed: number?,
	jump: number?,
	stepT: number?, -- seconds since the walk's last footstep
}

local state: State? = nil

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.CollisionGroup = "PixelRays"

local function dynFolder(): Instance
	local f = workspace:FindFirstChild("PixelDynamic")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "PixelDynamic"
		nf.Parent = workspace
		f = nf
	end
	return f :: Instance
end

-- The ground's height under a point (the island, the jetty, the boardwalk), past characters and rigs.
local function groundY(x: number, z: number, fallback: number): number
	local list: { Instance } = { dynFolder() }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	rayParams.FilterDescendantsInstances = list
	local hit = workspace:Raycast(Vector3.new(x, 30, z), Vector3.new(0, -60, 0), rayParams)
	if hit and hit.Position.Y > Street.WATER_Y then
		return hit.Position.Y
	end
	return fallback
end

local function myHumanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
end

-- The spot in front of a wild place (world, on the grass: a stud and a half off its south side's middle) and its
-- kind, from the view's pieces.
local function frontOf(v: Types.ClientView, uid: number): (Vector3?, string?)
	for _, q in v.pieces do
		if q.uid == uid then
			local sd = SiteData.of(q.id)
			local w, d = Plot.footprint(q.id, q.rot)
			local ox, oz = Street.origin(v.plot)
			return Vector3.new(ox + q.x + w / 2, Street.LAWN_Y, oz + q.z + d + 1.5), if sd then sd.id else nil
		end
	end
	return nil, nil
end

------------------------------------------------------------------ the overlay: letterbox bars, Skip, the blinds
local function hideWorldUI(on: boolean)
	for _, name in { "Hud", "World" } do
		UIKit.root(name).Enabled = not on
	end
	pcall(function()
		GuiService.TouchControlsEnabled = not on
	end)
end

local function overlay(s: State, caption: string?, closed: boolean)
	local canvas = UIKit.canvas("Stage")
	local size = UIKit.size("Stage")
	local w, h = size.X, size.Y
	local r = Instance.new("Frame")
	r.Name = "Voyage"
	r.BackgroundTransparency = 1
	r.BorderSizePixel = 0
	r.Size = UDim2.fromOffset(w, h)
	r.ZIndex = 30
	r.Parent = canvas
	s.gui = r
	if caption then
		-- the letterbox: an ink bar at the top and the bottom
		local BAR = 16
		local topBar = UIKit.rect(r, UDim2.fromOffset(w, BAR), UDim2.fromOffset(0, -BAR), UIKit.color("ink"), 30)
		topBar.Name = "BarTop"
		local botBar = UIKit.rect(r, UDim2.fromOffset(w, BAR), UDim2.fromOffset(0, h), UIKit.color("ink"), 30)
		botBar.Name = "BarBottom"
		UIKit.tween(topBar, 0.3, { Position = UDim2.fromOffset(0, 0) })
		UIKit.tween(botBar, 0.3, { Position = UDim2.fromOffset(0, h - BAR) })
		UIKit.text(botBar, caption, UDim2.fromOffset(w - 60, 10), UDim2.fromOffset(6, 3), { color = UIKit.color("accent"), z = 31, name = "Caption" })
		UIKit.button(botBar, "Skip", UDim2.fromOffset(40, 12), UDim2.fromOffset(w - 44, 2), function()
			Voyage.skip()
		end, { name = "VoyageSkip" })
	end
	-- the blinds: open (closing at the end of going in) or closed (opening on the island coming home)
	local BLIND = 12
	for y = 0, h - 1, BLIND do
		local bh = math.min(BLIND, h - y)
		local band = UIKit.rect(r, if closed then UDim2.fromOffset(w, bh) else UDim2.fromOffset(w, 0), if closed then UDim2.fromOffset(0, y) else UDim2.fromOffset(0, y + math.floor(bh / 2)), UIKit.color("ink"), 35)
		band.Name = "Blind"
		band.Visible = closed
		band:SetAttribute("Y", y)
		band:SetAttribute("H", bh)
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 35)
		table.insert(s.blinds, band)
	end
end

local function title(s: State, name: string, line: string, visible: boolean)
	local r = s.gui :: Frame
	local w, h = r.Size.X.Offset, r.Size.Y.Offset
	local t = Instance.new("Frame")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.ZIndex = 40
	t.Visible = visible
	t.Parent = r
	PixelSprites.image(t, "mini_wild", UDim2.fromOffset(math.floor(w / 2) - 5, math.floor(h / 2) - 26), 40)
	UIKit.text(t, name, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 12), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 40, name = "IsleName" })
	UIKit.text(t, line, UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(8, math.floor(h / 2) + 8), { x = "center", color = UIKit.color("text"), z = 40, name = "Blurb" })
	s.title = t
end

-- The blinds shut (instantly or over CLOSE s) with the place's name, kind and level.
local function closeBlinds(s: State, now: boolean)
	local r = s.gui
	if r == nil then
		return
	end
	local w = r.Size.X.Offset
	local mid = #s.blinds / 2
	for i, band in s.blinds do
		local y, bh = band:GetAttribute("Y") :: number, band:GetAttribute("H") :: number
		band.Visible = true
		if now then
			band.Size = UDim2.fromOffset(w, bh)
			band.Position = UDim2.fromOffset(0, y)
		else
			local d = (mid - math.abs(i - 0.5 - mid)) * 0.012
			task.delay(d, function()
				if band.Parent then
					UIKit.tween(band, 0.16, { Size = UDim2.fromOffset(w, bh), Position = UDim2.fromOffset(0, y) })
				end
			end)
		end
	end
	local isle = s.isle
	local sd = if s.site then SiteData.byId[s.site :: string] elseif isle then SiteData.byIslet[isle.kind] else nil
	local kind = if isle then Islets.list[isle.kind] else nil
	local kindName = if sd then sd.name elseif kind then kind.name else ""
	title(s, if isle then isle.name else "Into the wild", if isle then string.format("%s, level %d", kindName, isle.lvl) else "", now)
	if not now then
		local t = s.title :: Frame
		task.delay(CLOSE * 0.6, function()
			if t.Parent then
				t.Visible = true
			end
		end)
	end
end

-- The blinds open from the middle (the picture behind them ready).
local function openBlinds(s: State)
	local r = s.gui
	if r == nil then
		return
	end
	local w = r.Size.X.Offset
	local mid = #s.blinds / 2
	if s.title then
		(s.title :: Frame).Visible = false
	end
	for i, band in s.blinds do
		local y, bh = band:GetAttribute("Y") :: number, band:GetAttribute("H") :: number
		local d = math.abs(i - 0.5 - mid) * 0.018
		task.delay(d, function()
			if band.Parent then
				UIKit.tween(band, 0.16, { Size = UDim2.fromOffset(w, 0), Position = UDim2.fromOffset(0, y + math.floor(bh / 2)) })
			end
		end)
		task.delay(d + 0.2, function()
			band.Visible = false
		end)
	end
end

local function newState(dir: string, onDone: () -> ()): State
	return {
		dir = dir,
		phase = "",
		t = 0,
		total = 0,
		route = {},
		leg = 1,
		pos = Vector3.zero,
		yaw = math.pi,
		spot = Vector3.zero,
		isle = nil,
		site = nil,
		onDone = onDone,
		gui = nil,
		blinds = {},
		title = nil,
		conns = {},
		walkSpeed = nil,
		jump = nil,
	}
end

local function holdCharacter(s: State)
	local hum = myHumanoid()
	if hum then
		pcall(function()
			s.walkSpeed = hum.WalkSpeed
			s.jump = hum.JumpHeight
			hum.WalkSpeed = 0
			hum.JumpHeight = 0
		end)
	end
end

-- The character stands at a spot (feet on the ground there), facing `yaw`.
local function putCharacter(at: Vector3, yaw: number)
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if char and root and root:IsA("BasePart") then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local hip = if hum then hum.HipHeight else 2
		char:PivotTo(CFrame.new(at + Vector3.new(0, hip + root.Size.Y / 2 + 0.2, 0)) * CFrame.Angles(0, yaw, 0))
	end
end

------------------------------------------------------------------ the run
local function finish(s: State)
	if s.phase == "done" then
		return
	end
	s.phase = "done"
	for _, c in s.conns do
		c:Disconnect()
	end
	if s.dir == "home" then
		-- the founder stands in front of the place they came out of (the character is put there)
		if state == s then
			state = nil
		end
		putCharacter(s.spot, 0)
	end
	if s.dir ~= "out" then
		hideWorldUI(false)
	end
	local ok, err = pcall(function()
		s.onDone()
	end)
	if not ok then
		warn("Voyage: " .. tostring(err))
	end
	local g = s.gui
	task.delay(if s.dir == "out" then 0.1 else 0.45, function()
		if g then
			g:Destroy()
		end
	end)
	AvatarView.setOverride(nil)
	CameraController.setFocus(nil)
	local hum = myHumanoid()
	if hum and s.walkSpeed then
		pcall(function()
			-- (never back to a standstill: a speed held at 0 when the hold began is the game's own default)
			hum.WalkSpeed = if (s.walkSpeed or 0) > 0 then s.walkSpeed :: number else 16
			hum.JumpHeight = if (s.jump or 0) > 0 then s.jump :: number else 7.2
		end)
	end
	if state == s then
		state = nil
	end
end

local function stepOut(s: State, dt: number)
	if s.phase == "open" then
		CameraController.setFocus(s.pos)
		if s.t >= 0.3 then
			s.phase, s.t = "walk", 0
		end
	end
	if s.phase == "walk" then
		local left = WALK * dt
		while left > 0 and s.leg <= #s.route do
			local goal = s.route[s.leg]
			local d = Vector3.new(goal.X - s.pos.X, 0, goal.Z - s.pos.Z)
			local m = d.Magnitude
			if m <= left then
				s.pos = Vector3.new(goal.X, s.pos.Y, goal.Z)
				left -= m
				s.leg += 1
			else
				local u = d.Unit
				s.pos += u * left
				s.yaw = math.atan2(u.X, u.Z)
				left = 0
			end
		end
		s.pos = Vector3.new(s.pos.X, groundY(s.pos.X, s.pos.Z, s.pos.Y), s.pos.Z)
		CameraController.setFocus(s.pos)
		-- footsteps on the way (by the ground's height: the boards stand over the lawn, the beach under it)
		s.stepT = (s.stepT or 0) + dt
		if s.stepT >= 5.4 / WALK then
			s.stepT = 0
			local y = s.pos.Y
			Audio.play(if y > Street.LAWN_Y + 0.1 then "step_wood" elseif y < Street.LAWN_Y - 0.05 then "step_sand" else "step_grass")
		end
		if s.leg > #s.route then
			-- at the place: a look at it (facing north, into it), and the blinds close
			s.phase, s.t = "close", 0
			s.yaw = math.pi
			Audio.play("whoosh_heavy")
			closeBlinds(s, false)
		end
	end
	if s.phase == "close" then
		CameraController.setFocus(s.pos)
		if s.t >= CLOSE + 0.35 then
			finish(s)
			return
		end
	end
	local pos, yaw = s.pos, s.yaw
	local speed = if s.phase == "walk" then WALK else 0
	AvatarView.setOverride(function(rig, t, _dt)
		CharacterModels.poseStanding(rig, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), t, speed)
	end)
end

local function stepHome(s: State, _dt: number)
	if s.phase == "wait" then
		-- behind the closed blinds: the view is put on the place (never on the land first), the picture bakes; the
		-- blinds open once the view is there
		CameraController.setFocus(s.spot, true)
		if (s.t >= 0.5 and PixelRenderer.ready() and CameraController.stage() == nil and CameraController.settled()) or s.t >= OPEN_WAIT then
			s.phase, s.t = "land", 0
			openBlinds(s)
			Audio.play("cheer")
		end
	end
	local pos = s.spot
	if s.phase == "land" then
		CameraController.setFocus(pos)
		if s.t >= 1.0 then
			finish(s)
			return
		end
	end
	local cheer = s.phase == "land"
	AvatarView.setOverride(function(rig, t, _dt)
		CharacterModels.poseAction(rig, CFrame.new(pos), t, 0, if cheer then "cheer" else "stand")
	end)
end

local function run(s: State)
	table.insert(s.conns, RunService.Heartbeat:Connect(function(dt: number)
		if s.phase == "done" then
			return
		end
		local d = math.min(dt, 0.1)
		s.t += d
		s.total += d
		if s.dir == "out" then
			stepOut(s, d)
		elseif s.dir == "home" then
			stepHome(s, d)
		elseif s.phase == "wait" and ((s.t >= 0.3 and PixelRenderer.ready() and CameraController.stage() == nil) or s.t >= OPEN_WAIT) then
			s.phase, s.t = "open", 0
			openBlinds(s)
		elseif s.phase == "open" and s.t >= CLOSE + 0.1 then
			finish(s)
		end
	end))
	table.insert(s.conns, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			Voyage.skip()
		end
	end))
end

-- Going in: the founder walks to the wild place with piece uid `site` (`isle`: what it holds, from exp.start's
-- answer), then `onDone` (the place's screen). Without the place in the view it goes straight on.
function Voyage.play(site: number, isle: Types.Isle?, onDone: () -> ())
	if state then
		-- (another cutscene is playing: straight on to the place's screen, as reveal does)
		onDone()
		return
	end
	local v = StateClient.view()
	local spot: Vector3?, kind: string? = nil, nil
	if v then
		spot, kind = frontOf(v, site)
	end
	if v == nil or spot == nil then
		onDone()
		return
	end
	local s = newState("out", onDone)
	s.phase = "open"
	s.isle = isle
	s.site = kind
	s.spot = spot :: Vector3
	local to = Vector3.new(s.spot.X, groundY(s.spot.X, s.spot.Z, Street.LAWN_Y), s.spot.Z)
	-- from where the founder stands (on their own island; else from beside the place)
	local fp = AvatarView.founderPos()
	local start = to + Vector3.new(0, 0, 6)
	if fp and (Vector3.new(fp.X, 0, fp.Z) - Vector3.new(to.X, 0, to.Z)).Magnitude <= MAX_WALK then
		start = Vector3.new(fp.X, groundY(fp.X, fp.Z, Street.LAWN_Y), fp.Z)
	end
	s.route = { to }
	s.pos = start
	state = s
	UIKit.closePanel()
	hideWorldUI(true)
	overlay(s, "Into the wild...", false)
	holdCharacter(s)
	run(s)
	Audio.play("flip")
end

-- Coming home: the blinds (closed) open on the island with the founder in front of the wild place `site` (they
-- cheer); then `onDone`. Without the place in the view (cleared away meanwhile), `reveal` instead.
function Voyage.home(site: number?, onDone: () -> ())
	local v = StateClient.view()
	local spot = if v and site then frontOf(v, site) else nil
	if state or v == nil or spot == nil then
		Voyage.reveal(onDone)
		return
	end
	local s = newState("home", onDone)
	s.phase = "wait"
	s.spot = Vector3.new(spot.X, groundY(spot.X, spot.Z, Street.LAWN_Y), spot.Z)
	state = s
	hideWorldUI(true)
	overlay(s, "Heading home...", true)
	title(s, Players.LocalPlayer.DisplayName .. "'s Isle", "Home again.", true)
	holdCharacter(s)
	putCharacter(s.spot, 0)
	CameraController.setFocus(s.spot, true)
	run(s)
end

-- A plain transition back to the island: closed blinds that open once its picture is there; then `onDone`.
function Voyage.reveal(onDone: (() -> ())?)
	if state then
		if onDone then
			onDone()
		end
		return
	end
	local s = newState("reveal", onDone or function() end)
	s.phase = "wait"
	state = s
	overlay(s, nil, true)
	run(s)
end

-- Straight to the end: the closed blinds and the place's screen (going in), or home with the founder at the place.
function Voyage.skip()
	local s = state
	if s == nil or s.phase == "done" then
		return
	end
	if s.dir == "out" then
		if s.phase == "close" then
			return
		end
		s.phase, s.t = "close", CLOSE
		closeBlinds(s, true)
	elseif s.dir == "home" then
		if s.phase == "wait" then
			openBlinds(s)
		end
	end
	finish(s)
end

function Voyage.isPlaying(): boolean
	return state ~= nil
end

-- Sims and previews: the cutscene's way and phase now ("" when none plays) and where the founder is in it.
function Voyage.debugState(): { [string]: any }
	local s = state
	return { dir = if s then s.dir else "", phase = if s then s.phase else "", pos = if s then s.pos else nil, spot = if s then s.spot else nil }
end

function Voyage.init() end

return Voyage
