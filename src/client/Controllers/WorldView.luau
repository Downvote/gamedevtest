--!strict
-- The islands' life (docs/ARCHITECTURE.md 10.2; GAME_DESIGN 5, 6, 8): every driftling living in a hut is its 3D
-- model (Models/MicroModels) in Workspace.PixelDynamic, registered with the pixel renderer and moved every frame (the
-- driftlings do all the work: no villagers since 2026-11-12). It walks to the building it works at and works there a
-- while (pecking in the fields, dipping for fish, pushing at the wood, waving at the shops: what it works at flies off
-- now and then), strolls round the island, and back; one with nowhere to work naps at its hut. One just hatched from
-- the Tree of Life's eggs steps out of its egg (Controllers/EggView: the eggs themselves) and walks off to work. Who
-- lives on each
-- island comes from its plot's attributes (PlotService: Pals, Tier), where the buildings stand from its Static.Decor
-- models' names (uid:id:x:z:rot:lvl), so a visit shows a neighbour's island alive too. Only islands near the view get
-- models. Every island's sign gets its name (or "Unclaimed isle") floating over it; tapping a sign shows a card about
-- the island; tapping the own Tree of Life opens its panel.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Buildings = require(ReplicatedStorage.Shared.Data.Buildings)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local StateClient = require(script.Parent.StateClient)
local CameraController = require(script.Parent.CameraController)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.Parent.UI.UIKit)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local EggView = require(script.Parent.EggView)

local WorldView = {}

-- One islander: a driftling ("p") of plot `plot` living in a hut, walking about its island.
type Walker = {
	key: string,
	kind: string,
	id: number,
	plot: number,
	sig: string,
	work: number,
	home: number, -- its hut (the hut's uid)
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
	mood: string, -- a driftling's work (DriftModels: "peck" "push" "dip" "wave" "nap" "hop")
	beat: number, -- the work's beats so far, last frame (a blow's chips as a beat passes its moment)
	ph: number, -- where in its beat it started
	cheerUntil: number,
	rng: Types.Rng,
}

local walkers: { [string]: Walker } = {} -- key: "<plot>:p<id>"
-- Each peopled island's campfire: a flickering flame over the static fire, three puffs of smoke rising from it.
type Fire = { flame: MicroModels.Thing, smoke: Model, puffs: { BasePart }, x: number, z: number, ph: number }
local fires: { [number]: Fire } = {}
local signLabels: { [number]: TextLabel } = {}
local myPlot = 0
local NEAR = 100 -- studs from the view's centre an island is peopled within
local HOP = 4 -- studs a second

-- What the work at each building is ("there are also no proper animations for creatures and villagers that are working
-- on something in the island", 2026-11-11): its beat and what flies off at each (soil in the fields, wood chips at the
-- camps, a splash at the piers, a coin at the shops, sparks at the tool shed). Unlisted: tending (nothing flies).
local WORK_ACTION: { [string]: string } = {
	patch = "dig",
	paddy = "dig",
	greenhouse = "tend",
	orchard = "pick",
	skygarden = "pick",
	pier = "fish",
	kelpfarm = "fish",
	lumber = "chop",
	timber = "chop",
	bamboo = "chop",
	sawmill = "saw",
	grandmill = "saw",
	stall = "sell",
	bakery = "sell",
	bazaar = "sell",
	market = "sell",
	townhall = "sell",
	cafe = "serve",
	inn = "serve",
	hotel = "serve",
	toolshed = "hammer",
	watertower = "hammer",
	hatchery = "tend",
	windmill = "tend",
	smokehouse = "tend",
	beacon = "tend",
}
-- the beats a second of each (a driftling's chips fly at every other beat)
local WORK_RATE: { [string]: number } = { dig = 0.9, pick = 0.5, fish = 0.25, chop = 0.8, saw = 0.6, sell = 0.4, serve = 0.3, hammer = 0.7, tend = 0.5 }
-- what flies off at a blow: its colours, how many, how hard up and out, glowing
type Chips = { colors: { string }, n: number, up: number, out: number, glow: boolean?, ahead: number, y: number }
local WORK_CHIPS: { [string]: Chips } = {
	dig = { colors = { "hair_brown", "sand_dark" }, n = 3, up = 5, out = 2, ahead = 1.3, y = 0.2 },
	chop = { colors = { "wood", "wood_dark", "sand" }, n = 3, up = 6, out = 3, ahead = 1.2, y = 0.8 },
	hammer = { colors = { "yellow", "white" }, n = 2, up = 4, out = 2.5, glow = true, ahead = 1, y = 0.5 },
	fish = { colors = { "water", "white", "window" }, n = 4, up = 7, out = 1.5, ahead = 2.6, y = -0.4 },
	sell = { colors = { "gold" }, n = 1, up = 3, out = 0, glow = true, ahead = 0.9, y = 1.6 },
}
-- what a driftling does where it helps (DriftModels' work moods): by the building's kind
local function palMoodOf(id: string): string
	if id == "pier" or id == "kelpfarm" then
		return "dip"
	end
	local d = Buildings.byId[id]
	local kind = if d then d.kind else ""
	if kind == "farm" then
		return "peck"
	elseif kind == "shop" then
		return "wave"
	elseif kind == "nest" or kind == "breed" then
		return "nap"
	end
	return "push"
end

------------------------------------------------------------------ the chips a blow sends flying (one pooled model)
type Bit = { p: BasePart, pos: Vector3, vel: Vector3, life: number, age: number, grav: number }
local BITS = 40
local bits: { Bit } = {}
local bitModel: Model? = nil
local bitCursor = 0
local bitsDirty = false
local BIT_HIDE = CFrame.new(0, -500, 0)

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

local function ensureBits()
	if bitModel then
		return
	end
	local m = Instance.new("Model")
	m.Name = "WorkBits"
	for i = 1, BITS do
		local p = Instance.new("Part")
		p.Name = "Bit" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Size = Vector3.one * 0.35
		p.CFrame = BIT_HIDE
		p.Transparency = 1
		p.Parent = m
		bits[i] = { p = p, pos = BIT_HIDE.Position, vel = Vector3.zero, life = 0, age = 1, grav = 0 }
	end
	m.Parent = dyn()
	PixelRenderer.registerDynamic(m)
	bitModel = m
end

local function chipsAt(pos: Vector3, c: Chips)
	ensureBits()
	for i = 1, c.n do
		bitCursor = bitCursor % BITS + 1
		local b = bits[bitCursor]
		local a = math.random() * math.pi * 2
		local out = c.out * (0.5 + 0.5 * math.random())
		b.pos = pos
		b.vel = Vector3.new(math.cos(a) * out, c.up * (0.7 + 0.5 * math.random()), math.sin(a) * out)
		b.age, b.life = 0, 0.45 + 0.25 * math.random()
		b.grav = if c.glow then 2 else 22
		b.p.Color = Blocks.color(c.colors[(i - 1) % #c.colors + 1])
		b.p.Material = if c.glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		b.p.Transparency = 0
	end
	bitsDirty = true
end

local function stepBits(dt: number)
	for _, b in bits do
		if b.age < b.life then
			b.age += dt
			if b.age >= b.life then
				b.p.Transparency = 1
				b.p.CFrame = BIT_HIDE
			else
				b.vel += Vector3.new(0, -b.grav * dt, 0)
				b.pos += b.vel * dt
				local floor = Street.WATER_Y
				if b.pos.Y < floor then
					b.age = b.life
				end
				b.p.CFrame = CFrame.new(b.pos)
			end
		end
	end
	if bitsDirty and bitModel then
		bitsDirty = false
		PixelRenderer.refreshDynamic(bitModel :: Model)
	end
end

local function plotModel(i: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	return if m and m:IsA("Model") then m else nil
end

-- The buildings standing on island i: uid -> { id, cx, cz (world centre), w, d (turned footprint), rot }.
type Spot = { id: string, cx: number, cz: number, w: number, d: number, rot: number }
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
			out[u] = { id = id, cx = ox + xx + w / 2, cz = oz + zz + d / 2, w = w, d = d, rot = r }
		end
	end
	return out
end

-- A random point on island i's grass (world), off the plaza's campfire.
local function strollPoint(i: number, rng: Types.Rng): (number, number)
	local m = plotModel(i)
	local tier = if m then (m:GetAttribute("Tier") :: number?) or 1 else 1
	local r = Street.plot(tier)
	local ox, oz = Street.origin(i)
	local c = Street.CENTER
	for _ = 1, 12 do
		local x, z = r.x0 + rng:next() * (r.x1 - r.x0), r.z0 + rng:next() * (r.z1 - r.z0)
		if Street.buildable(tier, math.floor(x), math.floor(z)) and (x - c.x) ^ 2 + (z - c.z) ^ 2 > 6 then
			return ox + x, oz + z
		end
	end
	return ox + c.x + 3, oz + c.z + 3
end

local function fireOn(i: number, on: boolean)
	local f = fires[i]
	if on and f == nil then
		local ox, oz = Street.origin(i)
		local c = Street.CENTER
		local flame = MicroModels.build("flame")
		flame.model.Name = "Campfire_" .. i
		flame.model.Parent = dyn()
		PixelRenderer.registerDynamic(flame.model)
		local smoke = Instance.new("Model")
		smoke.Name = "CampSmoke_" .. i
		local puffs: { BasePart } = {}
		for k = 1, 3 do
			local p = Instance.new("Part")
			p.Name = "Puff" .. k
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Color = if k == 2 then Color3.fromRGB(214, 220, 228) else Color3.fromRGB(240, 244, 248)
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.CFrame = CFrame.new(ox + c.x, -50, oz + c.z)
			p.Parent = smoke
			table.insert(puffs, p)
		end
		smoke.Parent = dyn()
		PixelRenderer.registerDynamic(smoke)
		fires[i] = { flame = flame, smoke = smoke, puffs = puffs, x = ox + c.x, z = oz + c.z, ph = i * 1.7 }
	elseif not on and f then
		PixelRenderer.unregisterDynamic(f.flame.model)
		f.flame.model:Destroy()
		PixelRenderer.unregisterDynamic(f.smoke)
		f.smoke:Destroy()
		fires[i] = nil
	end
end

-- The flame flickers in whole steps (its size by thirds), the smoke rises, drifts and shrinks, then starts again.
local function stepFire(f: Fire, t: number)
	local k = math.floor(t * 10 + f.ph) % 3
	MicroModels.scale(f.flame, Vector3.new(1, 0.85 + k * 0.15, 1))
	MicroModels.place(f.flame, CFrame.new(f.x, Street.LAWN_Y + 0.55, f.z))
	for n, p in f.puffs do
		local a = (t * 0.35 + n / 3 + f.ph) % 1
		local size = if a < 0.45 then 0.5 else 0.25
		p.Size = Vector3.new(size, size, size)
		p.CFrame = CFrame.new(f.x + a * 1.5 + math.sin(t + n) * 0.25, Street.LAWN_Y + 1.6 + a * 4.5, f.z - a * 0.75)
		p.Transparency = if a > 0.8 then 1 else 0
	end
	PixelRenderer.refreshDynamic(f.smoke)
end

local function drop(key: string)
	local w = walkers[key]
	if w == nil then
		return
	end
	local model = if w.thing then w.thing.model else nil
	if model then
		PixelRenderer.unregisterDynamic(model)
		model:Destroy()
	end
	walkers[key] = nil
end

local function groundY(): number
	return Street.LAWN_Y
end

local function newWalker(key: string, id: number, plot: number, sp: string, work: number, home: number, at: Vector2?): Walker
	local rng = Util.newRng(Util.hash32(key))
	local x, z = strollPoint(plot, rng)
	if at then
		x, z = at.X, at.Y
	end
	local w: Walker = {
		key = key,
		kind = "p",
		id = id,
		plot = plot,
		sig = sp,
		work = work,
		home = home,
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
		mood = "idle",
		beat = 0,
		ph = rng:next(),
		cheerUntil = 0,
		rng = rng,
	}
	local def = Creatures.byId[sp]
	local t = MicroModels.driftling(if def then def.shape else "blob", if def then def.body else "steel", if def then def.accent else "steel_dark", "world")
	t.model:SetAttribute("PixelShadow", 1)
	t.model:SetAttribute("PixelGroundY", groundY())
	t.model.Parent = dyn()
	PixelRenderer.registerDynamic(t.model)
	w.thing = t
	return w
end

-- One island's driftlings from its attributes (only when near the view; far ones are let go). One new in a hut on an
-- island already peopled just hatched (from the tree's egg, or a Hatchery's): it steps out where its egg lay and walks
-- off.
local peopled: { [number]: boolean } = {}
local born: { [string]: number } = {} -- key -> when it popped out (the arrival's cheer)
local function syncPlot(i: number, near: boolean)
	local m = plotModel(i)
	local want: { [string]: boolean } = {}
	if m and near and (tonumber(m:GetAttribute("Owner")) or 0) ~= 0 then
		local pals = m:GetAttribute("Pals")
		if type(pals) == "string" then
			for entry in string.gmatch(pals, "[^;]+") do
				local id, sp, work, home = string.match(entry, "^(%d+)%.([%w_]+)%.(%d+)%.(%d+)$")
				if id and sp then
					local key = i .. ":p" .. id
					want[key] = true
					local w: Walker? = walkers[key]
					if w and w.sig ~= sp then
						drop(key)
						w = nil
					end
					local hm = tonumber(home) or 0
					if w == nil then
						-- (just hatched: out of its egg, then off to work)
						local at: Vector2? = nil
						if peopled[i] then
							local hx, hz = EggView.hatchPoint(i)
							at = Vector2.new(hx, hz)
							born[key] = os.clock()
						end
						local nw = newWalker(key, tonumber(id) or 0, i, sp, tonumber(work) or 0, hm, at)
						if at then
							nw.cheerUntil = os.clock() + 1.2
							nw.untilT = os.clock() + 1.2
						end
						walkers[key] = nw
					else
						local moved = w.home ~= hm or w.work ~= (tonumber(work) or 0)
						w.work = tonumber(work) or 0
						w.home = hm
						if moved then
							-- (a new place: off it goes now)
							w.untilT = 0
							w.state = "idle"
						end
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
	peopled[i] = m ~= nil and near
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

-- Where a driftling heads next: the building it works at (somewhere along its front), its hut for a nap when it has
-- nowhere to work, or a stroll now and then.
local function decide(w: Walker, t: number)
	local spots = spotsNow(w.plot)
	local s = if w.work ~= 0 then spots[w.work] else nil
	if s == nil then
		-- resting at its hut
		s = spots[w.home]
	end
	if s and (w.nextWork or w.work == 0 or w.rng:next() < 0.75) then
		local side = (w.rng:next() - 0.5) * s.w
		w.tx, w.tz = s.cx + side, s.cz + s.d / 2 + 0.6 + w.rng:next()
		w.state = "walk"
		w.nextWork = false
		w.action = WORK_ACTION[s.id] or "tend"
		w.mood = if w.work == 0 then "nap" else palMoodOf(s.id)
	else
		w.tx, w.tz = strollPoint(w.plot, w.rng)
		w.state = "walk"
		w.nextWork = true
		w.action = "stand"
		w.mood = "idle"
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
				-- (a nap lasts longer)
				w.untilT = t + 8 + w.rng:next() * 6 + (if w.mood == "nap" then 12 else 0)
				-- (turned three-quarters to the view, so the work reads: east along the front, or south)
				w.yaw = if w.rng:next() < 0.5 then 0 else math.pi / 2
				w.beat = t * (WORK_RATE[w.action] or 0.5) + w.ph
			else
				w.state = "idle"
				w.untilT = t + 1.5 + w.rng:next() * 3
			end
		else
			local step = math.min(d, HOP * dt)
			w.x += dx / d * step
			w.z += dz / d * step
			w.yaw = math.atan2(dx, dz)
			speed = HOP
		end
	elseif t >= w.untilT then
		decide(w, t)
	end
	local y = groundY()
	if w.thing then
		local working = w.state == "work" and speed == 0 and t >= w.cheerUntil
		-- its work's beat: at every other beat what it works at flies off (near the view only)
		local chips = WORK_CHIPS[w.action]
		if working and chips and w.work ~= 0 then
			local beats = (t * (WORK_RATE[w.action] or 0.5) + w.ph) / 2
			if math.floor(beats) > math.floor(w.beat) then
				local c = CameraController.centerWorld()
				if math.abs(w.x - c.X) < 40 and math.abs(w.z - c.Z) < 40 then
					local fx, fz = math.sin(w.yaw), math.cos(w.yaw)
					chipsAt(Vector3.new(w.x + fx * chips.ahead * 0.6, y + chips.y * 0.6, w.z + fz * chips.ahead * 0.6), chips)
				end
			end
			w.beat = beats
		end
		local hop = if speed > 0 then math.abs(math.sin(t * 9 + w.id)) * 0.5 elseif working then 0 else math.abs(math.sin(t * 2 + w.id)) * 0.12
		local bob = if t < w.cheerUntil then math.abs(math.sin(t * 12)) * 1.2 else hop
		-- its limbs alive: blinks, a wagging tail, stepping legs, a cheer, and its work where it works (or a nap at
		-- its hut)
		MicroModels.animate(w.thing, t + w.id, if t < w.cheerUntil then "cheer" elseif speed > 0 then "walk" elseif working then w.mood else "idle", 0)
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
		UIKit.notice("Nobody has claimed this one yet.", UIKit.color("text_dim"))
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
	UIKit.notice(string.format("%s: day %s, %d driftlings at home, charm %s", name, Numbers.int(n("Day")), count("Pals"), Numbers.int(n("Charm"))), UIKit.color("accent"), 5)
end

-- The Tree of Life under a world hit: true for the own island's, false for a neighbour's, nil for anything else.
local function treeOf(inst: Instance): boolean?
	local m: Instance? = inst
	while m and m ~= workspace do
		if m:IsA("Model") and m:GetAttribute("Decor") == "tree" then
			return m:FindFirstAncestor("Plot_" .. myPlot) ~= nil
		end
		m = m.Parent
	end
	return nil
end

-- A tap (not a drag, not on the interface, not in Build mode) on one of the own tree's eggs hatches it
-- (Controllers/EggView); on the own Tree of Life it opens its panel; on an island sign, it shows its card.
local function onTap(pos: Vector2)
	if CameraController.isFree() then
		return
	end
	-- (an egg under the own tree: hatched)
	if EggView.tapAt(pos) then
		return
	end
	local origin, dir = PixelRenderer.screenRay(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	-- (the pixel filter's group: the invisible coast walls stand far taller than anything on the island and, since
	-- they collide, Roblox still hits them whatever their CanQuery says; only this group passes through them)
	params.CollisionGroup = "PixelRays"
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
	-- the Tree of Life: the own one's panel (its eggs)
	local mine = treeOf(hit.Instance)
	if mine == true then
		UIKit.openPanel("tree")
		return
	elseif mine == false then
		UIKit.notice("Someone else's Tree of Life. Yours is on your own island.", UIKit.color("text_dim"), 3)
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
	return Vector3.new(w.x, groundY() + 3, w.z)
end

-- The own island's driftlings cheer (arms up) with a word over each head, one after another.
function WorldView.cheer(words: { string }, color: Color3)
	local k = 0
	for _, w in walkers do
		if w.plot ~= myPlot then
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

-- One hatched from the own tree's egg (Fx "hatched"): bits of its rarity's colour where the egg lay; a rare one or
-- better has its name float up there too.
local function hatchedOne(x: { [string]: any })
	local hx, hz = EggView.hatchPoint(myPlot)
	local d = if type(x.sp) == "string" then Creatures.byId[x.sp] else nil
	if d then
		local rar = Traits.RARITY[d.rarity] or Traits.RARITY[1]
		local at = Vector3.new(hx, groundY() + 1.5, hz)
		if d.rarity >= 3 then
			UIKit.floatText(at, d.name .. "!", UIKit.color(rar.color), d.rarity >= 4)
		end
		UIKit.bitsAt(at, { rar.color, "good", "white" }, if d.rarity >= 3 then 18 else 8, 40, 70)
	end
end

-- A hatchling (Logic/Breed): its kind's name floats up over the Hatchery with pink and gold bits (it moves into a hut
-- with room like one out of the tree's eggs).
local function hatched(x: { [string]: any })
	local at: Vector3? = nil
	for _, sp in spotsOf(myPlot) do
		local b = Buildings.byId[sp.id]
		if b and b.kind == "breed" then
			at = Vector3.new(sp.cx, groundY() + 3, sp.cz)
		end
	end
	local d = if type(x.sp) == "string" then Creatures.byId[x.sp] else nil
	if at then
		UIKit.floatText(at, (if d then d.name else "A driftling") .. " hatched!", UIKit.color("pink"), true)
		UIKit.bitsAt(at, { "pink", "accent", "white", "good" }, 18, 50, 90)
	end
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
		if msg.kind == "turn" and type(msg.hatched) == "table" then
			for _, x in msg.hatched do
				if type(x) == "table" then
					hatched(x)
				end
			end
		end
		if msg.kind == "hatched" and type(msg.data) == "table" then
			hatchedOne(msg.data)
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
				local near = math.abs(ox - c.X) <= NEAR
				syncPlot(i, near)
				local m = plotModel(i)
				fireOn(i, near and m ~= nil and (tonumber(m:GetAttribute("Owner")) or 0) ~= 0)
			end
		end
		for _, w in walkers do
			stepWalker(w, t, dt)
		end
		for _, f in fires do
			stepFire(f, t)
		end
		stepBits(dt)
		updateSigns()
		-- the tree's eggs on every island near the view
		EggView.step(t, c.X)
	end)
end

-- Sims: a tap on the screen at `pos` (screen px, as an InputObject's), as a player's tap is handled (a sign shows its
-- card).
function WorldView.tapScreen(pos: Vector2)
	onTap(pos)
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

-- Sims: the own island's driftlings drawn now (those in huts).
function WorldView.ownCount(): number
	local n = 0
	for _, w in walkers do
		if w.plot == myPlot then
			n += 1
		end
	end
	return n
end

return WorldView
