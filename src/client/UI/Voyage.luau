--!strict
-- The sailing cutscene (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.8): after Set sail the founder walks down the path
-- and the jetty to the pier's end and hops into the expedition boat, where the rest of the party waits on deck
-- (cheering); the boat casts off and sails out to sea with the camera following it, and ink blinds close over the
-- island the party is heading for (its name and kind). Then the islet's screen opens (ExpeditionUI, its curtain
-- already closed: the cut is seamless) and the boat arrives at the island's shore there.
-- The boat is the one moored at the plot's pier (Models/StreetModels' Boat, part of the static street): it leaves the
-- street (the pixel filter re-casts the water where it lay) and is drawn as a dynamic model while it sails; it stays
-- away while the expedition does and is moored again once the party is home (`dock`).
-- While it plays the HUD hides, the character can't walk, AvatarView lets this module pose the own founder, and
-- CameraController follows the cutscene's focus instead of the character. Skip (or Space / Return / a tap on Skip)
-- jumps to the blinds. The whole takes about six seconds.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local CharacterModels = require(ReplicatedStorage.Shared.Models.CharacterModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local AvatarView = require(script.Parent.Parent.Controllers.AvatarView)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

local Voyage = {}

local WALK = 13 -- studs a second
local HOP = 0.45 -- seconds a hop into the boat takes
local SAIL = 3.2 -- seconds the boat sails before the blinds close
local SAIL_Z = 30 -- studs it sails out (south)
local CLOSE = 0.4 -- seconds the blinds take to close
local MAX_WALK = 46 -- a longer walk starts the founder on the jetty instead (behind the blinds)
-- where the party stands on deck (boat space: x across, z toward the bow), the founder first
local DECK = { Vector3.new(0, 0, -0.1), Vector3.new(-0.75, 0, 0.9), Vector3.new(0.75, 0, 0.9), Vector3.new(0, 0.5, 1.75) }

type Puppet = { rig: CharacterModels.Rig?, thing: MicroModels.Thing?, off: Vector3, ph: number }

type State = {
	phase: string, -- "open" (blinds opening), "walk", "hop", "sail", "close", "done"
	t: number, -- seconds in the phase
	total: number,
	route: { Vector3 }, -- the founder's walk (world, feet on the ground)
	leg: number,
	pos: Vector3, -- the founder's feet now (world)
	yaw: number,
	boat: Model?,
	rel: { [BasePart]: CFrame }, -- each of the boat's parts relative to its moored base
	base0: CFrame, -- the boat moored (its origin on the deck's level, bow south)
	base: CFrame,
	puppets: { Puppet },
	isle: Types.Isle?,
	onDone: () -> (),
	gui: Frame?,
	blinds: { Frame },
	title: Frame?,
	conns: { RBXScriptConnection },
	walkSpeed: number?,
	jump: number?,
}

local state: State? = nil
-- the boat away with the party: put back at the pier once the expedition is over
local away: { boat: Model, parent: Instance, cfs: { [BasePart]: CFrame } }? = nil

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

-- The ground's height under a point (the island, the jetty, the boardwalk, the pier), past characters and rigs.
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

local function boatOf(plot: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local street = plots and plots:FindFirstChild("Street")
	local road = street and street:FindFirstChild("Road_" .. plot)
	local b = road and road:FindFirstChild("Boat")
	return if b and b:IsA("Model") then b else nil
end

local function myHumanoid(): Humanoid?
	local char = Players.LocalPlayer.Character
	return if char then char:FindFirstChildOfClass("Humanoid") else nil
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

local function overlay(s: State)
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
	-- the letterbox: an ink bar at the top and the bottom
	local BAR = 16
	local topBar = UIKit.rect(r, UDim2.fromOffset(w, BAR), UDim2.fromOffset(0, -BAR), UIKit.color("ink"), 30)
	topBar.Name = "BarTop"
	local botBar = UIKit.rect(r, UDim2.fromOffset(w, BAR), UDim2.fromOffset(0, h), UIKit.color("ink"), 30)
	botBar.Name = "BarBottom"
	UIKit.tween(topBar, 0.3, { Position = UDim2.fromOffset(0, 0) })
	UIKit.tween(botBar, 0.3, { Position = UDim2.fromOffset(0, h - BAR) })
	UIKit.text(botBar, "Setting sail...", UDim2.fromOffset(w - 60, 10), UDim2.fromOffset(6, 3), { color = UIKit.color("accent"), z = 31, name = "Caption" })
	UIKit.button(botBar, "Skip", UDim2.fromOffset(40, 12), UDim2.fromOffset(w - 44, 2), function()
		Voyage.skip()
	end, { name = "VoyageSkip" })
	-- the blinds (closed at the end: the islet's screen opens behind them with its own, closed, curtain)
	local BLIND = 12
	for y = 0, h - 1, BLIND do
		local band = UIKit.rect(r, UDim2.fromOffset(w, 0), UDim2.fromOffset(0, y + math.floor(math.min(BLIND, h - y) / 2)), UIKit.color("ink"), 35)
		band.Name = "Blind"
		band.Visible = false
		band:SetAttribute("Y", y)
		band:SetAttribute("H", math.min(BLIND, h - y))
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 35)
		table.insert(s.blinds, band)
	end
end

-- The blinds shut (instantly or over CLOSE s) with the island's name, kind and the boat sprite.
local function closeBlinds(s: State, now: boolean)
	local r = s.gui
	if r == nil then
		return
	end
	local w, h = r.Size.X.Offset, r.Size.Y.Offset
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
	local kind = if isle then Islets.list[isle.kind] else nil
	local t = Instance.new("Frame")
	t.Name = "Title"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.ZIndex = 40
	t.Visible = now
	t.Parent = r
	PixelSprites.image(t, "mini_boat", UDim2.fromOffset(math.floor(w / 2) - 5, math.floor(h / 2) - 26), 40)
	UIKit.text(t, if isle then isle.name else "Out to sea", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 12), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 40, name = "IsleName" })
	UIKit.text(t, if kind and isle then string.format("A %s, level %d", string.lower(kind.name), isle.lvl) else "", UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(8, math.floor(h / 2) + 8), { x = "center", color = UIKit.color("text"), z = 40, name = "Blurb" })
	s.title = t
	if not now then
		task.delay(CLOSE * 0.6, function()
			if t.Parent then
				t.Visible = true
			end
		end)
	end
end

------------------------------------------------------------------ the puppets
local function posePuppets(s: State, now: number, cheer: boolean)
	for i, p in s.puppets do
		local cf = s.base * CFrame.new(p.off) * CFrame.Angles(0, if i % 2 == 0 then math.rad(-30) else math.rad(30), 0)
		if p.rig then
			CharacterModels.poseAction(p.rig :: CharacterModels.Rig, cf, now + p.ph, 0, if cheer then "cheer" else "stand")
		elseif p.thing then
			local hop = if cheer and math.floor(now * 8 + p.ph) % 2 == 0 then 0.5 else 0
			MicroModels.place(p.thing :: MicroModels.Thing, cf * CFrame.new(0, hop, 0))
		end
	end
end

local function buildPuppets(s: State, keys: { string }, v: Types.ClientView)
	for i, key in keys do
		local kind, id = string.match(key, "^([vp])(%d+)$")
		local n = tonumber(id) or 0
		local off = DECK[i + 1] or DECK[#DECK]
		if kind == "v" then
			for _, x in v.folk do
				if x.id == n then
					local rig = CharacterModels.buildStanding(x.look, "VoyageCrew", x.seed % 97)
					rig.model.Parent = dynFolder()
					PixelRenderer.registerDynamic(rig.model)
					table.insert(s.puppets, { rig = rig, thing = nil, off = off, ph = i * 0.7 })
				end
			end
		elseif kind == "p" then
			for _, x in v.pals do
				if x.id == n then
					local d = Creatures.byId[x.sp]
					local t = MicroModels.driftling(if d then d.shape else "blob", if d then d.body else "steel", if d then d.accent else "steel_dark")
					MicroModels.scale(t, Vector3.one * 0.8)
					t.model.Parent = dynFolder()
					PixelRenderer.registerDynamic(t.model)
					table.insert(s.puppets, { rig = nil, thing = t, off = off, ph = i * 0.7 })
				end
			end
		end
	end
end

local function moveBoat(s: State, base: CFrame)
	s.base = base
	for part, rel in s.rel do
		part.CFrame = base * rel
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
	-- the islet's screen opens behind the closed blinds (its own curtain closed), then the blinds go
	local ok, err = pcall(function()
		s.onDone()
	end)
	if not ok then
		warn("Voyage: " .. tostring(err))
	end
	task.delay(0.1, function()
		if s.gui then
			(s.gui :: Frame):Destroy()
		end
	end)
	for _, p in s.puppets do
		local m = if p.rig then (p.rig :: CharacterModels.Rig).model elseif p.thing then (p.thing :: MicroModels.Thing).model else nil
		if m then
			PixelRenderer.unregisterDynamic(m)
			m:Destroy()
		end
	end
	-- the boat stays away with the party
	local b = s.boat
	if b then
		PixelRenderer.unregisterDynamic(b)
		b.Parent = nil
	end
	AvatarView.setOverride(nil)
	CameraController.setFocus(nil)
	local hum = myHumanoid()
	if hum then
		pcall(function()
			hum.WalkSpeed = s.walkSpeed or 16
			hum.JumpHeight = s.jump or 7.2
		end)
	end
	if state == s then
		state = nil
	end
end

local function step(s: State, dt: number)
	if s.phase == "done" then
		return
	end
	s.t += dt
	s.total += dt
	local now = os.clock()
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
		if s.leg > #s.route then
			s.phase, s.t = "hop", 0
			Audio.play("pop", { pitch = 1.2 })
		end
	end
	local deck = s.base * CFrame.new(DECK[1])
	if s.phase == "hop" then
		local e = math.clamp(s.t / HOP, 0, 1)
		local from = s.pos
		local to = deck.Position
		local p = from:Lerp(to, e) + Vector3.new(0, math.sin(e * math.pi) * 2.2, 0)
		s.yaw = math.atan2(to.X - from.X, to.Z - from.Z)
		CameraController.setFocus(from:Lerp(to, e))
		if e >= 1 then
			s.phase, s.t = "sail", 0
			s.pos = to
			Audio.play("cheer")
			task.delay(0.5, function()
				Audio.play("trumpet")
			end)
		else
			AvatarView.setOverride(function(rig, t, _dt)
				CharacterModels.poseAction(rig, CFrame.new(p) * CFrame.Angles(0, s.yaw, 0), t, 0, "jump")
			end)
		end
	end
	if s.phase == "sail" then
		local u = math.clamp(s.t / SAIL, 0, 1)
		local ease = u * u
		local bob = if math.floor(s.total * 3) % 2 == 0 then 0 else 0.125
		moveBoat(s, s.base0 * CFrame.new(1.5 * ease, bob, SAIL_Z * ease))
		CameraController.setFocus(s.base.Position + Vector3.new(0, 0, 3))
		if s.t >= SAIL then
			s.phase, s.t = "close", 0
			closeBlinds(s, false)
		end
	end
	if s.phase == "close" then
		local u = math.clamp(s.t / SAIL, 0, 1)
		moveBoat(s, s.base0 * CFrame.new(1.5, 0, SAIL_Z + 8 * u))
		if s.t >= CLOSE + 0.25 then
			finish(s)
			return
		end
	end
	-- the founder: walking, hopping (above), or on deck with the party
	if s.phase == "open" or s.phase == "walk" then
		local pos, yaw = s.pos, s.yaw
		local speed = if s.phase == "walk" then WALK else 0
		AvatarView.setOverride(function(rig, t, _dt)
			CharacterModels.poseStanding(rig, CFrame.new(pos) * CFrame.Angles(0, yaw, 0), t, speed)
		end)
	elseif s.phase == "sail" or s.phase == "close" then
		local cf = s.base * CFrame.new(DECK[1])
		AvatarView.setOverride(function(rig, t, _dt)
			CharacterModels.poseAction(rig, cf, t, 0, if s.phase == "sail" and s.t < 1.2 then "cheer" else "stand")
		end)
	end
	posePuppets(s, now, s.phase == "hop" or (s.phase == "sail" and s.t < 1.2))
end

-- Play the cutscene for the party just set sail (`keys`: the members picked, "v<id>" / "p<id>"; `isle`: the island
-- from exp.start's answer), then `onDone` (the islet's screen). Without the plot's boat it goes straight on.
function Voyage.play(keys: { string }, isle: Types.Isle?, onDone: () -> ())
	if state then
		return
	end
	local v = StateClient.view()
	local plot = if v then v.plot else 0
	local boat = boatOf(plot)
	if v == nil or boat == nil then
		onDone()
		return
	end
	local ox, oz = Street.origin(plot)
	local pr = Street.pier()
	local moored = Vector3.new(ox + pr.x1 + 2.25, Street.WATER_Y + 0.6 + 0.025, oz + pr.z1 - 2.5)
	local base0 = CFrame.new(moored)
	local rel: { [BasePart]: CFrame } = {}
	local cfs: { [BasePart]: CFrame } = {}
	for _, d in boat:GetDescendants() do
		if d:IsA("BasePart") then
			rel[d] = base0:Inverse() * d.CFrame
			cfs[d] = d.CFrame
		end
	end
	-- the founder's walk: from where they stand (on their own island) down the path and the jetty, along the pier
	local fp = AvatarView.founderPos()
	local route: { Vector3 } = {}
	local function at(lx: number, lz: number): Vector3
		return Vector3.new(ox + lx, Street.LAWN_Y, oz + lz)
	end
	local start = at(0, Street.BOARD.z0 - 3)
	local far = true
	if fp then
		local lx, lz = fp.X - ox, fp.Z - oz
		if math.abs(lx) <= Street.SPACING / 2 and lz <= Street.PIER_Z then
			start = Vector3.new(fp.X, Street.LAWN_Y, fp.Z)
			far = false
			if lz < Street.BOARD.z0 - 1 then
				table.insert(route, at(0, math.clamp(lz, Street.PLAZA.z1, Street.BOARD.z0 - 1)))
			end
		end
	end
	table.insert(route, at(0, Street.BOARD.z0 + 2.5))
	table.insert(route, at(Street.PIER_X + 1, Street.PIER_Z - 2.5))
	local len, prev = 0, start
	for _, p in route do
		len += (p - prev).Magnitude
		prev = p
	end
	if len > MAX_WALK then
		far = true
		start = at(0, Street.BOARD.z0 - 3)
		route = { at(0, Street.BOARD.z0 + 2.5), at(Street.PIER_X + 1, Street.PIER_Z - 2.5) }
	end
	local s: State = {
		phase = "open",
		t = 0,
		total = 0,
		route = route,
		leg = 1,
		pos = Vector3.new(start.X, groundY(start.X, start.Z, Street.LAWN_Y), start.Z),
		yaw = math.pi,
		boat = boat,
		rel = rel,
		base0 = base0,
		base = base0,
		puppets = {},
		isle = isle,
		onDone = onDone,
		gui = nil,
		blinds = {},
		title = nil,
		conns = {},
		walkSpeed = nil,
		jump = nil,
	}
	state = s
	UIKit.closePanel()
	hideWorldUI(true)
	overlay(s)
	-- the character stays put while the cutscene plays
	local hum = myHumanoid()
	if hum then
		pcall(function()
			s.walkSpeed = hum.WalkSpeed
			s.jump = hum.JumpHeight
			hum.WalkSpeed = 0
			hum.JumpHeight = 0
		end)
	end
	-- the boat leaves the street's picture and is drawn as it moves
	away = { boat = boat, parent = boat.Parent :: Instance, cfs = cfs }
	boat.Parent = dynFolder()
	PixelRenderer.registerDynamic(boat)
	buildPuppets(s, keys, v)
	if far then
		-- a long way round: the founder starts on the jetty (the view jumps there)
		CameraController.setFocus(s.pos)
	end
	table.insert(s.conns, RunService.Heartbeat:Connect(function(dt: number)
		step(s, math.min(dt, 0.1))
	end))
	table.insert(s.conns, UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return) then
			Voyage.skip()
		end
	end))
	Audio.play("flip")
end

-- Straight to the closed blinds and the islet's screen.
function Voyage.skip()
	local s = state
	if s == nil or s.phase == "done" or s.phase == "close" then
		return
	end
	s.phase, s.t = "close", CLOSE
	closeBlinds(s, true)
	finish(s)
end

function Voyage.isPlaying(): boolean
	return state ~= nil
end

-- Sims and previews: the cutscene's phase now ("" when none plays) and whether the boat is away.
function Voyage.debugState(): { [string]: any }
	local s = state
	return { phase = if s then s.phase else "", away = away ~= nil, boat = if s and s.boat then s.base.Position else nil }
end

-- The boat moored again once the party is home (no expedition, no islet on screen).
function Voyage.dock()
	local a = away
	if a == nil or state ~= nil then
		return
	end
	away = nil
	PixelRenderer.unregisterDynamic(a.boat)
	for part, cf in a.cfs do
		part.CFrame = cf
	end
	a.boat.Parent = a.parent
end

function Voyage.init()
	RunService.Heartbeat:Connect(function()
		if away and state == nil and CameraController.stage() == nil then
			local v = StateClient.view()
			if v and v.exp == nil then
				Voyage.dock()
			end
		end
	end)
end

return Voyage
