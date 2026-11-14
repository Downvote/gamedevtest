--!strict
-- The islands' small lives, drawn in the pixel layer (GAME_DESIGN 8; docs/ARCHITECTURE.md 10.2): one effect layer
-- (PixelRenderer.addFxLayer, Render/Fx: depth-tested sprites and pixels, no parts, no rays). The request (2026-11-13):
-- "like the bakery game, you can use 2d details to add to the athmosphere, such as grass, wood detail, birds and other
-- details". Every island near the view (a claimed plot whose land the screen shows) has:
-- * birds: teal pips and sandy wrens alight on the lawns, the fences' rails, the roofs' ridges, the island's sign and
--   the beach, hop, peck and look round, and fly off when anyone walks within a few studs (a founder, a driftling),
--   coming back a while later; a gull glides in to the beach now and then. They leave at dusk and come back at dawn;
-- * grass tufts and little flowers on the lawn, swaying as gusts roll across it (Fx.gust), each in the lawn's own green
--   (a tinted sprite: the colour of the lawn under it) and only where the lawn itself shows;
-- * butterflies flitting between the flowers by day (the decor's and the lawn's), fireflies drifting over the lawn at
--   night (the clock of Controllers/DayLight), their cores lit through the night's grade;
-- * leaves and petals coming down from the trees now and then (in their tree's colour), smoke curling from the
--   chimneys, the smokehouse's vent and the grills' coals, steam off the hot springs and the teapots (found by the
--   parts' names in the island's models: Chimney, Smoke, Coals, Steam, Teapot, Mug);
-- * glints of light on the sea now and then, and a fish jumping out of the water near the shore once in a while, a
--   splash and a ring where it goes out and back in.
-- Everything is culled to the screen (an island off it is let go after a while), scaled by the renderer's tier (low
-- half, medium three quarters), paused with the renderer (no tick, no drawing) and drawn on whole art pixels, the
-- creatures with their ink outline (UI/ArtData's "fx_" sprites, scripts/gen_art.py). A screen that shows the island
-- small (a phone) gets the small sprites. While a stage has the view (the hatch scene) none of it shows. Reduced
-- motion (Roblox's setting): no particles, flights or sway; the birds sit still.
--   start(), stats(), birds(plot), debugRun(on) (sims: live without a picture), debugHurry() (everything due now)
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Street = require(ReplicatedStorage.Shared.Data.Street)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Plot = require(ReplicatedStorage.Shared.Logic.Plot)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Fx = require(ReplicatedStorage.Shared.Render.Fx)
local CameraController = require(script.Parent.CameraController)
local DayLight = require(script.Parent.DayLight)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ArtData = require(script.Parent.Parent.UI.ArtData)

local AmbientView = {}

------------------------------------------------------------------ constants
local TIER_SCALE: { [string]: number } = { low = 0.5, medium = 0.75, high = 1 }
local BIG_PPU = 7 -- art px a stud (along the screen) from which the big sprites are drawn, else the small ones
local ISLE_EVERY = 0.5 -- s between looks at which islands the screen shows
local ISLE_KEEP = 10 -- s an island keeps its lives after it left the screen
local SCAN_DEBOUNCE = 0.6 -- s after a change to an island's pieces before they are looked at again
local RIGS_EVERY = 0.15 -- s between looks at where everyone walking stands
local SCARE_R2, SCARE_DY = 3.5 * 3.5, 5
local GULL_R2 = 5 * 5
local LAWN_Y, SAND_Y = Street.LAWN_Y, Street.SAND_Y
local LAWN_RGB: { [number]: boolean } = { [Palette.colors.grass] = true, [Palette.colors.grass_dark] = true }
-- (the palette's own pastels: pink, yellow, cream, crystal, coral; the butterflies sky blue among them)
local PC = Palette.colors
local FLOWER_RGB = { PC.pink, PC.yellow, PC.cream, PC.crystal, PC.coral }
local BFLY_RGB = { PC.yellow, PC.pink, PC.sky_day, PC.cream, PC.coral }
-- the parts that smoke or steam (by name), how often a wisp comes (s) and how long one lives
local PUFFS: { [string]: { kind: string, every: number, life: number } } = {
	Chimney = { kind = "smoke", every = 0.13, life = 2.6 },
	Smoke = { kind = "smoke", every = 0.15, life = 2.2 },
	Coals = { kind = "smoke", every = 0.2, life = 1.8 },
	Steam = { kind = "steam", every = 0.22, life = 1.4 },
	Teapot = { kind = "steam", every = 0.4, life = 1 },
	Mug = { kind = "steam", every = 0.5, life = 0.9 },
}
local VENTS: { [string]: boolean } = { smokehouse = true } -- pieces whose "Vent" smokes
local LEAFY: { [string]: boolean } = { Leaves = true, Blossom = true, Leaf = true }
local FLOWERY: { [string]: boolean } = { Flower = true, Bloom = true, Blossom = true, Petals = true, FlowerHeart = true }

------------------------------------------------------------------ types
type Perch = { x: number, y: number, z: number, ax: number, az: number, r: number, kind: string }
type Bird = {
	sp: string, -- "pip" | "wren" | "gull"
	state: string, -- "away" | "in" | "perched" | "flee"
	t0: number,
	untilT: number,
	x: number, -- where it is now (world)
	y: number,
	z: number,
	sx: number, -- flying in: where it started; fleeing: its velocity
	sy: number,
	sz: number,
	perch: Perch?,
	off: number, -- along the perch
	hopFrom: number,
	hopT: number,
	flip: boolean,
	peckUntil: number,
	actAt: number,
	hidden: number, -- s perched off the screen
}
type Bfly = { x: number, y: number, z: number, tx: number, ty: number, tz: number, rest: number, tint: { number }, flip: boolean, phase: number }
-- a tuft or a flower; what the static picture says at its foot is kept until the picture changes (ver): its pixel, its
-- depth, whether the lawn shows there and (a tuft) the lawn's tones; it is drawn sticky (Fx.stickSprite: `px` the
-- pixels stuck, `pf` the frame they show, 0 none) and again only when its frame changes
type Deco = { x: number, z: number, flower: boolean, tint: { number }?, phase: number, ver: number, i: number, j: number, d: number, ok: boolean, px: { number }, pf: number }
type Chunk = { x: number, z: number, list: { Deco } }
type Puff = { x: number, y: number, z: number, kind: string, every: number, life: number, nextAt: number, phase: number }
type Canopy = { x: number, y: number, z: number, hx: number, hy: number, hz: number, tint: { number }, petal: boolean, nextAt: number }
type Fish = { x0: number, z0: number, x1: number, z1: number, y: number, t0: number, dur: number, h: number }
type Ripple = { x: number, y: number, z: number, t0: number }
type Glint = { x: number, y: number, z: number, t0: number, life: number }
type Isle = {
	plot: number,
	tier: number,
	ox: number,
	oz: number,
	box: { x0: number, z0: number, x1: number, z1: number }, -- world: the island and its shallows
	visible: boolean,
	seenAt: number,
	lawn: { number }, -- flat x, z (world): grass cells a bird may stand on (off the pieces and the plaza)
	sand: { number }, -- flat x, z: the dry beach
	shore: { number }, -- flat x, z, y: water near the shore (a fish jumps there)
	chunks: { Chunk },
	flowers: { number }, -- flat x, y, z: flowers the butterflies visit
	perches: { Perch }, -- rails, ridges, flat roofs, the sign
	canopies: { Canopy },
	puffs: { Puff },
	birds: { Bird },
	gull: Bird,
	bflies: { Bfly },
	fish: Fish?,
	fishAt: number,
	decor: Instance?,
	seen: { [Instance]: any }, -- each model's spots (Spots), looked at once
	conns: { RBXScriptConnection },
	scanDirty: boolean,
	scanAt: number,
}

------------------------------------------------------------------ state
local started = false
local running = false -- (sims) the life goes on without a picture
local rng = Random.new(os.clock() * 1e6 % 2147483647)
local isles: { [number]: Isle } = {}
local islesAt = -math.huge
local rigs: { number } = {} -- where everyone walking stands: x, y, z, ...
local rigsAt = -math.huge
local drift = Fx.newSystem(80) -- leaves and petals
local wisps = Fx.newSystem(260) -- smoke and steam
local bugs = Fx.newSystem(64) -- fireflies
local drops = Fx.newSystem(48) -- a fish's splash
local glints: { Glint } = {}
local ripples: { Ripple } = {}
local lastStep = os.clock()
local onStage = false
local drawn = { decos = 0, birds = 0, bflies = 0, fish = 0, glints = 0, particles = 0 }
local cost = { life = 0, decos = 0, particles = 0, creatures = 0 } -- ms of the last tick's parts
local sprites: { [string]: Fx.Sprite } = {}

------------------------------------------------------------------ helpers
local function rand(a: number, b: number): number
	return a + rng:NextNumber() * (b - a)
end

local function tierScale(): number
	return TIER_SCALE[PixelRenderer.tier()] or 1
end

-- Roblox's reduced motion setting (read once a second).
local still, stillAt = false, -math.huge
local function reduceMotion(now: number): boolean
	if now - stillAt >= 1 then
		stillAt = now
		local ok, on = pcall(function(): any
			return (GuiService :: any).ReducedMotionEnabled
		end)
		still = ok and on == true
	end
	return still
end

-- The hour: birds about by day (not from dusk to dawn), butterflies in the day's middle, fireflies at night.
local function hour(): (boolean, boolean, boolean)
	local f = DayLight.frac()
	return f >= 0.03 and f < 0.72, f >= 0.06 and f < 0.68, f >= 0.78 and f < 0.97
end

local function onLayer(cam: Raster.Cam, W: number, H: number, x: number, y: number, z: number, margin: number): (boolean, number, number, number)
	local px, py, d = Raster.project(cam, x, y, z)
	return d > 0 and px >= -margin and py >= -margin and px < W + margin and py < H + margin, px, py, d
end

-- The camera the life is stepped with when no picture is drawn (sims): the view's own.
local function viewCam(): (Raster.Cam, number, number)
	local v = CameraController.view()
	local px, py = CameraController.pan()
	local cam = Raster.gridCam(v.rot12, CameraController.gridAt(px, py), v.fullX, v.fullY, v.K, Tuning.CamRayBack)
	return cam, math.ceil(v.fullX / v.K), math.ceil(v.fullY / v.K)
end

local function loadSprites()
	for name in ArtData do
		local group = string.match(name, "^fx_(.-)_1$")
		if group then
			local frames: { Fx.SpriteData } = {}
			local k = 1
			while ArtData["fx_" .. group .. "_" .. k] do
				table.insert(frames, ArtData["fx_" .. group .. "_" .. k])
				k += 1
			end
			local centre = group == "fish" or group == "fishs" or group == "bfly" or group == "leaf" or group == "petal" or group == "glint" or group == "ripple"
			sprites[group] = Fx.define("fx_" .. group, frames, if centre then "centre" else "bottom")
		end
	end
end

-- The sprite of a group at this screen's size (its small one where the island shows small).
local function spriteFor(group: string, ppu: number): Fx.Sprite?
	if ppu < BIG_PPU then
		return sprites[group .. "s"] or sprites[group]
	end
	return sprites[group]
end

------------------------------------------------------------------ who walks about (birds fly off from them)
local function gatherRigs(now: number)
	if now - rigsAt < RIGS_EVERY then
		return
	end
	rigsAt = now
	table.clear(rigs)
	for _, pl in Players:GetPlayers() do
		local ch = pl.Character
		local root = if ch then (ch:FindFirstChild("HumanoidRootPart") or ch.PrimaryPart) else nil
		if root and root:IsA("BasePart") then
			local p = root.Position
			table.insert(rigs, p.X)
			table.insert(rigs, p.Y)
			table.insert(rigs, p.Z)
		end
	end
	-- the driftlings at work (WorldView's models on the lawn)
	local dyn = workspace:FindFirstChild("PixelDynamic")
	if dyn then
		for _, m in dyn:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("PixelGroundY") == LAWN_Y then
				local p = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
				if p then
					local q = p.Position
					table.insert(rigs, q.X)
					table.insert(rigs, LAWN_Y)
					table.insert(rigs, q.Z)
				end
			end
		end
	end
end

local function scared(x: number, y: number, z: number, r2: number): (boolean, number, number)
	for i = 1, #rigs, 3 do
		local dx, dy, dz = x - rigs[i], y - rigs[i + 1], z - rigs[i + 2]
		if dx * dx + dz * dz < r2 and math.abs(dy) < SCARE_DY then
			return true, dx, dz
		end
	end
	return false, 0, 0
end

------------------------------------------------------------------ an island's land and pieces
local function plotModel(i: number): Model?
	local plots = workspace:FindFirstChild("Plots")
	local m = if plots then plots:FindFirstChild("Plot_" .. i) else nil
	return if m and m:IsA("Model") then m else nil
end

local function newBird(sp: string, k: number): Bird
	return {
		sp = sp,
		state = "away",
		t0 = 0,
		untilT = os.clock() + 1 + k * 1.3 + rng:NextNumber() * 2,
		x = 0,
		y = 0,
		z = 0,
		sx = 0,
		sy = 0,
		sz = 0,
		perch = nil,
		off = 0,
		hopFrom = 0,
		hopT = -1,
		flip = false,
		peckUntil = 0,
		actAt = 0,
		hidden = 0,
	}
end

-- The land's cells (by the tier's shape) and the tufts and flowers on the grass, the same every time for a plot.
local function buildLand(I: Isle)
	local tier, ox, oz = I.tier, I.ox, I.oz
	local b = Street.cellBounds(tier)
	I.box = { x0 = ox + b.x0, z0 = oz + b.z0, x1 = ox + b.x1 + 1, z1 = oz + b.z1 + 1 }
	local r = Random.new(I.plot * 7919 + tier * 104729)
	local chunks: { [number]: Chunk } = {}
	table.clear(I.sand)
	table.clear(I.shore)
	for z = b.z0, b.z1 do
		for x = b.x0, b.x1 do
			local l = Street.layer(tier, x, z)
			if l == Street.GRASS then
				local key = (x // 8) * 1000 + z // 8
				local ch = chunks[key]
				if ch == nil then
					ch = { x = ox + (x // 8) * 8 + 4, z = oz + (z // 8) * 8 + 4, list = {} }
					chunks[key] = ch
				end
				-- tufts in patches (a lusher stretch here, bare grass there), a cell in twenty on average (the request of
				-- 2026-11-14: "no need to use so much grass on the floor, it just looks noisy")
				if r:NextNumber() < Fx.patch(x, z) * 0.1 then
					table.insert(ch.list, { x = ox + x + r:NextNumber(), z = oz + z + r:NextNumber(), flower = false, tint = nil, phase = r:NextNumber() * 6.28, ver = -1, i = 0, j = 0, d = 0, ok = false, px = {}, pf = 0 })
				end
				if r:NextNumber() < 0.025 then
					local tint = Fx.tones(FLOWER_RGB[r:NextInteger(1, #FLOWER_RGB)])
					for _ = 1, r:NextInteger(2, 3) do
						table.insert(ch.list, { x = ox + x + r:NextNumber(-0.6, 1.6), z = oz + z + r:NextNumber(-0.6, 1.6), flower = true, tint = tint, phase = r:NextNumber() * 6.28, ver = -1, i = 0, j = 0, d = 0, ok = false, px = {}, pf = 0 })
					end
				end
			elseif l == Street.SAND then
				table.insert(I.sand, ox + x + 0.5)
				table.insert(I.sand, oz + z + 0.5)
			elseif l == Street.SHALLOW or l == Street.SEA_CELL then
				local d = Street.cellDist(tier, x, z)
				if d > Street.BANDS.foam + 0.8 and d < Street.BANDS.shallow + 3 and x % 2 == 0 and z % 2 == 0 then
					table.insert(I.shore, ox + x + 0.5)
					table.insert(I.shore, oz + z + 0.5)
					table.insert(I.shore, if l == Street.SHALLOW then Street.SHALLOW_Y else Street.WATER_Y)
				end
			end
		end
	end
	table.clear(I.chunks)
	for _, ch in chunks do
		if #ch.list > 0 then
			table.insert(I.chunks, ch)
		end
	end
end

local function topOf(p: BasePart): number
	local s = p.Size
	-- (the highest corner: a part turned on its side still has its top where its box's is)
	local cf = p.CFrame
	return p.Position.Y + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
end

local function colourOf(p: BasePart): number
	local attr = p:GetAttribute("PixelColor")
	local c = if typeof(attr) == "Color3" then attr else p.Color
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

-- A part's long horizontal axis (unit) and its half length along it.
local function longAxis(p: BasePart): (number, number, number)
	local cf, s = p.CFrame, p.Size
	if s.X >= s.Z then
		local v = cf.RightVector
		local l = math.sqrt(v.X * v.X + v.Z * v.Z)
		return v.X / math.max(l, 1e-6), v.Z / math.max(l, 1e-6), s.X / 2
	end
	local v = cf.LookVector
	local l = math.sqrt(v.X * v.X + v.Z * v.Z)
	return v.X / math.max(l, 1e-6), v.Z / math.max(l, 1e-6), s.Z / 2
end

-- One model's spots for the lives (kept by model: only a new one is looked at).
type Spots = { perches: { Perch }, flowers: { number }, canopies: { Canopy }, puffs: { Puff } }

-- What a model (a piece, `id` its kind, or the island's land) holds for the lives: the top of a fence, ridges, flat
-- roofs and the sign's top to perch on; flowers; leafy crowns; chimneys and steaming things.
local function look(model: Instance, id: string?): Spots
	local out: Spots = { perches = {}, flowers = {}, canopies = {}, puffs = {} }
	local perches, flowers, canopies, puffs = out.perches, out.flowers, out.canopies, out.puffs
	local fence = id ~= nil and Plot.isFence(id)
	local top: BasePart? = nil
	local topY = -math.huge
	local seenFlower: { [number]: boolean } = {}
	for _, p in model:GetDescendants() do
		if not p:IsA("BasePart") or p.Transparency >= 0.9 then
			continue
		end
		local n = p.Name
		if fence and (n == "Post" or n == "Rail" or n == "Top") then
			local y = topOf(p)
			if y > topY then
				top, topY = p, y
			end
		elseif n == "Ridge" or (n == "Roof" and p.Size.Y <= 0.3 and p:IsA("Part") and p.Shape == Enum.PartType.Block) or (n == "Top" and p.Parent ~= nil and p.Parent.Name == "PlotSign") then
			local ax, az, half = longAxis(p)
			if half >= 0.6 then
				local c = p.Position
				table.insert(perches, { x = c.X, y = topOf(p), z = c.Z, ax = ax, az = az, r = math.max(0, half - 0.35), kind = "roof" })
			end
		elseif FLOWERY[n] then
			local c = p.Position
			local key = math.floor(c.X) * 4096 + math.floor(c.Z)
			if not seenFlower[key] then
				seenFlower[key] = true
				table.insert(flowers, c.X)
				table.insert(flowers, topOf(p))
				table.insert(flowers, c.Z)
			end
		end
		if LEAFY[n] and math.max(p.Size.X, p.Size.Y, p.Size.Z) >= 0.9 then
			local rgb = colourOf(p)
			local r, g, b = rgb // 65536, (rgb // 256) % 256, rgb % 256
			local petal = n == "Blossom" or (r > 200 and b > 150 and r > g)
			local c, sz = p.Position, p.Size
			table.insert(canopies, { x = c.X, y = c.Y, z = c.Z, hx = sz.X / 2, hy = sz.Y / 2, hz = sz.Z / 2, tint = Fx.tones(rgb), petal = petal, nextAt = os.clock() + rand(2, 12) })
		end
		local puff = PUFFS[n] or (if n == "Vent" and id and VENTS[id] then PUFFS.Chimney else nil)
		if puff then
			local c = p.Position
			table.insert(puffs, { x = c.X, y = topOf(p) + 0.05, z = c.Z, kind = puff.kind, every = puff.every, life = puff.life, nextAt = 0, phase = rand(0, 6.28) })
		end
	end
	if top then
		-- a fence's highest part: a post's top (a bird sits still on it) or a rail along its length
		local ax, az, half = longAxis(top)
		local c = top.Position
		local r = if top.Name == "Post" then 0 else math.max(0, half - 0.3)
		table.insert(perches, { x = c.X, y = topY, z = c.Z, ax = ax, az = az, r = r, kind = "fence" })
	end
	return out
end

local NONE: Spots = { perches = {}, flowers = {}, canopies = {}, puffs = {} }

-- What the island's models hold for its lives (each model looked at once: `I.seen`), and the cells its pieces cover
-- (no bird stands inside a building), gathered into the island's lists (at most 40 perches, 240 flowers, 60 leafy
-- crowns, 40 smoking spots).
local function scan(I: Isle)
	I.scanDirty = false
	I.scanAt = os.clock()
	local m = plotModel(I.plot)
	local static = if m then m:FindFirstChild("Static") else nil
	local land = if static then static:FindFirstChild("Land") else nil
	local decor = if static then static:FindFirstChild("Decor") else nil
	if decor ~= I.decor then
		for _, c in I.conns do
			c:Disconnect()
		end
		table.clear(I.conns)
		I.decor = decor
		if decor then
			local function dirty()
				I.scanDirty = true
				I.scanAt = os.clock()
			end
			table.insert(I.conns, decor.ChildAdded:Connect(dirty))
			table.insert(I.conns, decor.ChildRemoved:Connect(dirty))
		end
	end
	local seen: { [Instance]: Spots } = {}
	local order: { Spots } = {}
	if land then
		local had = I.seen[land]
		local sp = if had then had else look(land, nil)
		seen[land] = sp
		table.insert(order, sp)
	end
	local covered: { [number]: boolean } = {}
	if decor then
		for _, c in decor:GetChildren() do
			local id, x, z, rot = string.match(c.Name, "^%d+:([%w_]+):(%-?%d+):(%-?%d+):(%d+)")
			local xx, zz, rr = tonumber(x), tonumber(z), tonumber(rot)
			if id and xx and zz and rr then
				local w, d = Plot.footprint(id, rr)
				for cz = zz, zz + math.max(1, d) - 1 do
					for cx = xx, xx + math.max(1, w) - 1 do
						covered[Street.cellKey(cx, cz)] = true
					end
				end
				-- (a path's or a water tile's parts never perch, flower or smoke: not looked at)
				local had = I.seen[c]
				local sp = if had then had elseif Plot.isTile(id) then NONE else look(c, id)
				seen[c] = sp
				table.insert(order, sp)
			end
		end
	end
	I.seen = seen
	local perches: { Perch } = {}
	local flowers: { number } = {}
	local canopies: { Canopy } = {}
	local puffs: { Puff } = {}
	for _, sp in order do
		for _, q in sp.perches do
			if #perches < 40 then
				table.insert(perches, q)
			end
		end
		for k = 1, #sp.flowers, 3 do
			if #flowers < 180 * 3 then
				table.insert(flowers, sp.flowers[k])
				table.insert(flowers, sp.flowers[k + 1])
				table.insert(flowers, sp.flowers[k + 2])
			end
		end
		for _, q in sp.canopies do
			if #canopies < 60 then
				table.insert(canopies, q)
			end
		end
		for _, q in sp.puffs do
			if #puffs < 40 then
				table.insert(puffs, q)
			end
		end
	end
	-- the lawn a bird stands on: the grass a stud in from its edge, off the pieces and the plaza
	local lawn: { number } = {}
	local b = Street.plot(I.tier)
	local pz = Street.PLAZA
	for z = b.z0, b.z1 - 1 do
		for x = b.x0, b.x1 - 1 do
			if Street.buildable(I.tier, x, z) and not covered[Street.cellKey(x, z)] and not (x >= pz.x0 and x < pz.x1 and z >= pz.z0 and z < pz.z1) then
				table.insert(lawn, I.ox + x + 0.5)
				table.insert(lawn, I.oz + z + 0.5)
			end
		end
	end
	-- the lawn's own flowers for the butterflies too
	for _, ch in I.chunks do
		for _, dc in ch.list do
			if dc.flower and #flowers < 240 * 3 then
				table.insert(flowers, dc.x)
				table.insert(flowers, LAWN_Y + 0.4)
				table.insert(flowers, dc.z)
			end
		end
	end
	I.lawn, I.perches, I.flowers, I.canopies, I.puffs = lawn, perches, flowers, canopies, puffs
	-- a bird whose perch went (a building cleared away) flies off
	local kept: { [Perch]: boolean } = {}
	for _, q in perches do
		kept[q] = true
	end
	for _, bd in I.birds do
		local p = bd.perch
		if (bd.state == "perched" or bd.state == "in") and p and (p.kind == "roof" or p.kind == "fence") and not kept[p] then
			bd.state = "flee"
			bd.t0 = os.clock()
			bd.untilT = bd.t0 + 2
			bd.sx, bd.sy, bd.sz = 0, 3, 0
		end
	end
end

local function newIsle(i: number, tier: number): Isle
	local ox, oz = Street.origin(i)
	local scale = tierScale()
	local I: Isle = {
		plot = i,
		tier = tier,
		ox = ox,
		oz = oz,
		box = { x0 = 0, z0 = 0, x1 = 0, z1 = 0 },
		visible = true,
		seenAt = os.clock(),
		lawn = {},
		sand = {},
		shore = {},
		chunks = {},
		flowers = {},
		perches = {},
		canopies = {},
		puffs = {},
		birds = {},
		gull = newBird("gull", 4),
		bflies = {},
		fish = nil,
		fishAt = os.clock() + rand(4, 12),
		decor = nil,
		seen = {},
		conns = {},
		scanDirty = true,
		scanAt = -math.huge,
	}
	I.gull.untilT = os.clock() + rand(8, 30)
	buildLand(I)
	scan(I)
	local n = math.max(1, math.floor(4 * scale + 0.5))
	for k = 1, n do
		table.insert(I.birds, newBird(if k % 2 == 0 then "wren" else "pip", k))
	end
	for k = 1, math.max(1, math.floor(3 * scale + 0.5)) do
		table.insert(I.bflies, { x = ox, y = LAWN_Y + 1, z = oz, tx = ox, ty = LAWN_Y + 1, tz = oz, rest = 0, tint = Fx.tones(BFLY_RGB[(k - 1) % #BFLY_RGB + 1]), flip = false, phase = k * 1.7 })
	end
	return I
end

local function dropIsle(I: Isle)
	for _, c in I.conns do
		c:Disconnect()
	end
	table.clear(I.conns)
end

-- Which islands the screen shows (their lives are made when they come into view, let go ISLE_KEEP after they leave).
local function updateIsles(cam: Raster.Cam, W: number, H: number, now: number)
	if now - islesAt < ISLE_EVERY then
		return
	end
	islesAt = now
	for i = 1, Street.MAX do
		local m = plotModel(i)
		local owner = if m then tonumber(m:GetAttribute("Owner")) or 0 else 0
		local static = if m then m:FindFirstChild("Static") else nil
		local built = if static then static:GetAttribute("Built") else nil
		local tier = if type(built) == "number" then built else 0
		local I: Isle? = isles[i]
		if owner == 0 or tier < 1 then
			if I then
				dropIsle(I)
				isles[i] = nil
			end
			continue
		end
		-- the island's box on the screen
		local ox, oz = Street.origin(i)
		local b = Street.cellBounds(tier)
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, c in { { b.x0, b.z0 }, { b.x1 + 1, b.z0 }, { b.x0, b.z1 + 1 }, { b.x1 + 1, b.z1 + 1 } } do
			for _, y in { LAWN_Y, LAWN_Y + 8 } do
				local px, py = Raster.project(cam, ox + c[1], y, oz + c[2])
				x0, y0, x1, y1 = math.min(x0, px), math.min(y0, py), math.max(x1, px), math.max(y1, py)
			end
		end
		local inView = x1 >= -40 and y1 >= -40 and x0 <= W + 40 and y0 <= H + 40
		if inView then
			if I and I.tier ~= tier then
				dropIsle(I)
				I = nil
			end
			local cur = if I then I else newIsle(i, tier)
			isles[i] = cur
			cur.visible = true
			cur.seenAt = now
		elseif I then
			I.visible = false
			if now - I.seenAt > ISLE_KEEP then
				dropIsle(I)
				isles[i] = nil
			end
		end
	end
end

------------------------------------------------------------------ birds
-- A perch for a bird on screen with nobody near and no other bird on it (nil when none): a rail, a ridge or the sign
-- now and then, else a spot on the lawn or (a gull, sometimes a pip) the beach.
local function pickPerch(I: Isle, b: Bird, cam: Raster.Cam, W: number, H: number): Perch?
	local gull = b.sp == "gull"
	for _ = 1, 12 do
		local p: Perch? = nil
		local roll = rng:NextNumber()
		if not gull and roll < 0.45 and #I.perches > 0 then
			p = I.perches[rng:NextInteger(1, #I.perches)]
		elseif (gull or roll > 0.88) and #I.sand > 0 then
			local k = rng:NextInteger(1, #I.sand // 2)
			p = { x = I.sand[k * 2 - 1] + rand(-0.3, 0.3), y = SAND_Y, z = I.sand[k * 2] + rand(-0.3, 0.3), ax = 1, az = 0, r = 0.8, kind = "sand" }
		elseif #I.lawn > 0 then
			local k = rng:NextInteger(1, #I.lawn // 2)
			p = { x = I.lawn[k * 2 - 1] + rand(-0.3, 0.3), y = LAWN_Y, z = I.lawn[k * 2] + rand(-0.3, 0.3), ax = 1, az = 0, r = 0.8, kind = "lawn" }
		end
		if p then
			-- (round the middle of the screen, where the founder is: never under the HUD's cards or at an edge)
			local ok, px, py = onLayer(cam, W, H, p.x, p.y, p.z, 0)
			local ex, ey = (px - W / 2) / (W * (if gull then 0.3 else 0.24)), (py - H / 2) / (H * (if gull then 0.36 else 0.3))
			local free = ok and ex * ex + ey * ey < 1
			if free then
				for _, o in I.birds do
					if o ~= b and o.state ~= "away" and math.abs(o.x - p.x) < 1 and math.abs(o.z - p.z) < 1 and math.abs(o.y - p.y) < 1 then
						free = false
					end
				end
			end
			if free and not (scared(p.x, p.y, p.z, if gull then GULL_R2 else SCARE_R2)) then
				return p
			end
		end
	end
	return nil
end

local function perchPoint(p: Perch, off: number): (number, number, number)
	return p.x + p.ax * off, p.y, p.z + p.az * off
end

local function stepBird(I: Isle, b: Bird, cam: Raster.Cam, W: number, H: number, now: number, dt: number, day: boolean, quiet: boolean)
	local gull = b.sp == "gull"
	if b.state == "away" then
		if now >= b.untilT and day and I.visible then
			local p = pickPerch(I, b, cam, W, H)
			if p == nil then
				b.untilT = now + rand(2, 5)
				return
			end
			b.perch = p
			b.off = rand(-p.r, p.r) * 0.5
			local x, y, z = perchPoint(p, b.off)
			if quiet then
				b.x, b.y, b.z = x, y, z
				b.state = "perched"
				b.actAt = math.huge
				b.untilT = now + rand(30, 90)
				return
			end
			-- in from one side of the screen, high up (a gull from the sea)
			local sxa, sza = Fx.swayAxis(cam)
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local reach = if gull then 12 else 8
			b.sx, b.sy, b.sz = x + sxa * reach * side, y + (if gull then 7 else 5), z + sza * reach * side + (if gull then 6 else 0)
			b.x, b.y, b.z = b.sx, b.sy, b.sz
			b.flip = side > 0 -- coming from the right: facing left
			b.state = "in"
			b.t0 = now
			b.untilT = now + (if gull then 2.4 else 1.6)
			b.peckUntil = 0
		end
		return
	end
	local p = b.perch
	if b.state == "in" then
		if p == nil then
			b.state = "away"
			return
		end
		local x, y, z = perchPoint(p, b.off)
		local dur = if gull then 2.4 else 1.6
		local t = math.clamp((now - b.t0) / dur, 0, 1)
		local e = 1 - (1 - t) * (1 - t)
		b.x = b.sx + (x - b.sx) * e
		b.y = b.sy + (y - b.sy) * e + math.sin(t * math.pi) * 0.8
		b.z = b.sz + (z - b.sz) * e
		if t >= 1 then
			b.x, b.y, b.z = x, y, z
			b.state = "perched"
			b.actAt = now + rand(0.4, 1.5)
			b.untilT = now + (if gull then rand(12, 30) else rand(20, 70))
		end
		return
	end
	if b.state == "perched" then
		local isScared, dx, dz = scared(b.x, b.y, b.z, if gull then GULL_R2 else SCARE_R2)
		if not day or (not quiet and (isScared or now >= b.untilT)) then
			if quiet then
				b.state = "away"
				b.untilT = now + rand(8, 16)
				return
			end
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 1e-3 then
				local sxa, sza = Fx.swayAxis(cam)
				dx, dz, len = sxa * (if rng:NextNumber() < 0.5 then -1 else 1), sza, 1
			end
			local speed = if gull then 6 else 5
			b.state = "flee"
			b.t0 = now
			b.untilT = now + 2.5
			b.sx, b.sy, b.sz = dx / len * speed, if gull then 2.5 else 3.2, dz / len * speed + (if gull then 2 else 0)
			local _, fpx = Raster.project(cam, b.x + b.sx, b.y, b.z + b.sz)
			local _, px = Raster.project(cam, b.x, b.y, b.z)
			b.flip = fpx < px
			return
		end
		if quiet or p == nil then
			return
		end
		-- perched off the screen a while (the view moved on): it slips away, to alight again where it is seen
		if onLayer(cam, W, H, b.x, b.y, b.z, 0) then
			b.hidden = 0
		else
			b.hidden += dt
			if b.hidden > 3 then
				b.hidden = 0
				b.state = "away"
				b.untilT = now + rand(1, 4)
				return
			end
		end
		if b.hopT >= 0 then
			-- a hop along the perch
			b.hopT += dt / 0.25
			local t = math.min(1, b.hopT)
			local off = b.hopFrom + (b.off - b.hopFrom) * t
			local x, y, z = perchPoint(p, off)
			b.x, b.y, b.z = x, y + 0.35 * math.sin(t * math.pi), z
			if t >= 1 then
				b.hopT = -1
			end
		elseif now >= b.actAt then
			local r = rng:NextNumber()
			if r < 0.4 then
				b.peckUntil = now + (if gull then 0.6 else 0.3)
			elseif r < 0.72 and not gull and p.r > 0.05 then
				local to = math.clamp(b.off + (if rng:NextNumber() < 0.5 then -0.4 else 0.4), -p.r, p.r)
				if to ~= b.off then
					b.hopFrom, b.off, b.hopT = b.off, to, 0
					local ax = Raster.project(cam, p.x + p.ax * to, p.y, p.z + p.az * to)
					local bx = Raster.project(cam, b.x, b.y, b.z)
					b.flip = ax < bx
				end
			elseif r < 0.9 then
				b.flip = not b.flip -- a look round
			end
			b.actAt = now + rand(0.7, 2.6)
		end
		return
	end
	-- flee: off and away, flapping
	b.x += b.sx * dt
	b.y += b.sy * dt
	b.z += b.sz * dt
	if now >= b.untilT then
		b.state = "away"
		b.perch = nil
		b.untilT = now + (if gull then rand(25, 60) else rand(6, 16))
	end
end

local function drawBird(ctx: Fx.Ctx, b: Bird, now: number)
	if b.state == "away" then
		return
	end
	local frame = 1
	if b.state == "in" then
		local t = (now - b.t0) / (if b.sp == "gull" then 2.4 else 1.6)
		frame = if t > 0.85 then 4 elseif math.floor(now * (if b.sp == "gull" then 6 else 10)) % 2 == 0 then 3 else 4
	elseif b.state == "flee" then
		frame = if math.floor(now * (if b.sp == "gull" then 7 else 12)) % 2 == 0 then 3 else 4
	elseif now < b.peckUntil then
		frame = 2
	end
	local ok, px, py, d = onLayer(ctx.cam, ctx.W, ctx.H, b.x, b.y, b.z, 12)
	if ok then
		local s = spriteFor(b.sp, ctx.ppu)
		if s and Fx.drawSprite(ctx, s, frame, px, py, d, b.flip, 0.6) then
			drawn.birds += 1
		end
	end
end

------------------------------------------------------------------ butterflies
local function stepBfly(I: Isle, f: Bfly, cam: Raster.Cam, W: number, H: number, now: number, dt: number)
	local list = I.flowers
	if #list == 0 then
		return
	end
	if not onLayer(cam, W, H, f.x, f.y, f.z, 6) then
		-- off the screen: to a flower that is on it
		local k = rng:NextInteger(1, #list // 3)
		local x, y, z = list[k * 3 - 2], list[k * 3 - 1], list[k * 3]
		if onLayer(cam, W, H, x, y, z, -8) then
			f.x, f.y, f.z = x, y + 0.8, z
			f.tx, f.ty, f.tz = x, y + 0.2, z
		end
		return
	end
	if now < f.rest then
		return
	end
	local dx, dy, dz = f.tx - f.x, f.ty - f.y, f.tz - f.z
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 0.15 then
		-- on to another flower nearby (or rest on this one a while)
		if rng:NextNumber() < 0.3 then
			f.rest = now + rand(1.2, 3.5)
		end
		local best, bestD = 0, math.huge
		for _ = 1, 4 do
			local k = rng:NextInteger(1, #list // 3)
			local x, z = list[k * 3 - 2], list[k * 3]
			local dd = (x - f.x) ^ 2 + (z - f.z) ^ 2
			if dd < bestD and dd > 0.5 then
				best, bestD = k, dd
			end
		end
		if best > 0 and bestD < 64 and rng:NextNumber() < 0.6 then
			f.tx, f.ty, f.tz = list[best * 3 - 2], list[best * 3 - 1] + 0.25, list[best * 3]
		else
			f.tx, f.ty, f.tz = f.x + rand(-2.5, 2.5), LAWN_Y + rand(0.8, 2.2), f.z + rand(-2.5, 2.5)
		end
	else
		local sp = math.min(len, 1.4 * dt)
		f.x += dx / len * sp
		f.y += dy / len * sp
		f.z += dz / len * sp
		local a = Raster.project(cam, f.tx, f.ty, f.tz)
		local bx = Raster.project(cam, f.x, f.y, f.z)
		f.flip = a < bx
	end
end

local function drawBfly(ctx: Fx.Ctx, f: Bfly, now: number)
	local ok, px, py, d = onLayer(ctx.cam, ctx.W, ctx.H, f.x, f.y, f.z, 4)
	if not ok then
		return
	end
	local resting = now < f.rest
	local open = if resting then math.floor(now * 1.5 + f.phase) % 3 == 0 else math.floor(now * 9 + f.phase) % 2 == 0
	local bob = if resting then 0 else math.floor(math.sin(now * 7 + f.phase) * 1.2)
	if ctx.ppu >= BIG_PPU then
		local s = sprites.bfly
		if s and Fx.drawSprite(ctx, s, if open then 1 else 2, px, py + bob, d, f.flip, 0.4, f.tint) then
			drawn.bflies += 1
		end
	else
		-- small: a flutter of one or two pixels
		local x, y = math.floor(px), math.floor(py) + bob
		Fx.dot(ctx, x, y, d, f.tint[4], 0.4)
		if open then
			Fx.dot(ctx, x + (if f.flip then 1 else -1), y, d, f.tint[3], 0.4)
		end
		drawn.bflies += 1
	end
end

------------------------------------------------------------------ the lawn's tufts and flowers
local lawnTones: { [number]: { number } } = {} -- a lawn pixel's packed colour -> a tuft's tones there
local lawnCount = 0

local function drawDecos(ctx: Fx.Ctx, I: Isle, now: number, quiet: boolean)
	local W, H = ctx.W, ctx.H
	local cam = ctx.cam
	local sAlbedo, sColor = ctx.sAlbedo, ctx.sColor
	local big = ctx.ppu >= BIG_PPU
	local tuft = if big then sprites.tuft else sprites.tufts
	local flower = if big then sprites.flower else sprites.flowers
	if tuft == nil or flower == nil then
		return
	end
	local margin = 6 * ctx.ppu
	-- (on the lawn's plane the projection is affine in x and z: three points give it)
	local x0, y0, d0 = Raster.project(cam, 0, LAWN_Y, 0)
	local xx, yx, dxx = Raster.project(cam, 1, LAWN_Y, 0)
	local xz, yz, dzz = Raster.project(cam, 0, LAWN_Y, 1)
	xx, yx, dxx = xx - x0, yx - y0, dxx - d0
	xz, yz, dzz = xz - x0, yz - y0, dzz - d0
	local sId, sNormal, sDepth = ctx.sId, ctx.sNormal, ctx.sDepth
	local up = Fx.UP_NORMAL
	local ver = ctx.ver
	local thin = tierScale() * 6.2832 -- (a lower tier draws a share of the tufts)
	local t1, t3 = now * 1.1, now * 3.1
	for _, ch in I.chunks do
		if not onLayer(cam, W, H, ch.x, LAWN_Y, ch.z, margin) then
			continue
		end
		for _, dc in ch.list do
			if dc.ver ~= ver then
				-- the static picture changed (its sticky pixels went with it): is the lawn itself still what shows at
				-- its foot (not a path, a piece or something in front), and in which green
				dc.ver = ver
				dc.pf = 0
				table.clear(dc.px)
				local x, z = dc.x, dc.z
				local i, j = math.floor(x0 + x * xx + z * xz), math.floor(y0 + x * yx + z * yz)
				local d = d0 + x * dxx + z * dzz
				dc.i, dc.j, dc.d, dc.ok = i, j, d, false
				if i >= 0 and j >= 0 and i < W and j < H then
					local o = j * W + i
					if buffer.readu8(sNormal, o) == up and buffer.readu16(sId, o * 2) ~= 0 and math.abs(buffer.readf32(sDepth, o * 4) - d) < 0.35 and LAWN_RGB[buffer.readu32(sAlbedo, o * 4) % 16777216] then
						dc.ok = true
						if not dc.flower then
							local base = buffer.readu32(sColor, o * 4)
							local tint = lawnTones[base]
							if tint == nil then
								if lawnCount > 512 then
									table.clear(lawnTones)
									lawnCount = 0
								end
								tint = Fx.tones(Fx.unpack(base))
								lawnTones[base] = tint
								lawnCount += 1
							end
							dc.tint = tint
						end
					end
				end
			end
			if dc.ok and (dc.flower or dc.phase <= thin) then
				-- a gust rolling across the lawn (Fx.gust, Fx.swayFrame); stuck again only when its frame changes
				local g = if quiet then 0 else math.sin(t1 - (dc.x * 0.31 + dc.z * 0.17)) + 0.25 * math.sin(t3 + dc.phase)
				local frame = if g > 0.75 then 2 elseif g < -0.95 then 3 else 1
				if frame ~= dc.pf then
					if dc.pf ~= 0 then
						Fx.unstick(ctx, dc.px)
					end
					if dc.flower then
						Fx.stickSprite(ctx, flower, if frame == 1 then 1 else 2, dc.i, dc.j, dc.d, frame == 3, 0.3, dc.tint, dc.px)
					else
						Fx.stickSprite(ctx, tuft, frame, dc.i, dc.j, dc.d, false, 0.3, dc.tint, dc.px)
					end
					dc.pf = frame
				end
				drawn.decos += 1
			elseif dc.pf ~= 0 then
				Fx.unstick(ctx, dc.px)
				dc.pf = 0
			end
		end
	end
end

------------------------------------------------------------------ trees, chimneys
local function stepCanopies(I: Isle, cam: Raster.Cam, W: number, H: number, now: number, scale: number)
	for _, c in I.canopies do
		if now >= c.nextAt then
			c.nextAt = now + rand(6, 18) / scale
			if onLayer(cam, W, H, c.x, c.y, c.z, 8) then
				local x, y, z = c.x + rand(-c.hx, c.hx) * 0.8, c.y - c.hy * 0.4, c.z + rand(-c.hz, c.hz) * 0.8
				local kind = if c.petal then Fx.KINDS.petal else Fx.KINDS.leaf
				local sxa, sza = Fx.swayAxis(cam)
				local w = rand(0.1, 0.35)
				Fx.spawn(drift, kind, x, y, z, (y - LAWN_Y) / -kind.fall + 6, sxa * w, sza * w, 0, c.tint)
			end
		end
	end
end

local function stepPuffs(I: Isle, cam: Raster.Cam, W: number, H: number, now: number, scale: number)
	local sxa, sza = Fx.swayAxis(cam)
	for _, e in I.puffs do
		if now >= e.nextAt then
			if not onLayer(cam, W, H, e.x, e.y, e.z, 12) then
				e.nextAt = now + 0.5 -- off the screen: look again in a while
			else
				e.nextAt = now + e.every / scale
				local kind = Fx.KINDS[e.kind]
				-- the same sway phase along a wisp (drifting slowly) draws one curl; it leans a little with the wind
				Fx.spawn(wisps, kind, e.x + rand(-0.05, 0.05), e.y, e.z + rand(-0.05, 0.05), e.life * rand(0.85, 1.1), sxa * 0.22, sza * 0.22, 0, nil, e.phase + now * 0.35)
			end
		end
	end
end

------------------------------------------------------------------ the sea: glints, a fish
local function stepGlints(ctx: Fx.Ctx, now: number, dt: number, scale: number, day: boolean)
	local W, H = ctx.W, ctx.H
	-- a few a second over a screen of sea, fewer by night
	local rate = (if day then 3 else 1) * scale * (W * H) / (640 * 360)
	local tries = 0
	local want = rate * dt
	while want > 0 and tries < 6 do
		tries += 1
		if want < 1 and rng:NextNumber() > want then
			break
		end
		want -= 1
		local i, j = rng:NextInteger(0, W - 1), rng:NextInteger(0, H - 1)
		local o = j * W + i
		local cls = buffer.readu8(ctx.sWClass, o)
		if (cls == 1 or cls == 2) and #glints < 24 then
			local depth = buffer.readf32(ctx.sDepth, o * 4)
			local ox, oy, oz = Raster.origin(ctx.cam, i, j)
			local cam = ctx.cam
			table.insert(glints, { x = ox + cam.lx * depth, y = oy + cam.ly * depth, z = oz + cam.lz * depth, t0 = now, life = rand(0.45, 0.8) })
		end
	end
	local s = sprites.glint
	local k = 1
	while k <= #glints do
		local g = glints[k]
		local t = (now - g.t0) / g.life
		if t >= 1 then
			glints[k] = glints[#glints]
			glints[#glints] = nil
			continue
		end
		local px, py, d = Raster.project(ctx.cam, g.x, g.y, g.z)
		if s then
			-- a dot, a cross, the streak, a cross, a dot (the small screen: no streak)
			local frame = if t < 0.2 or t > 0.8 then 1 elseif t < 0.4 or t > 0.6 then 2 else 3
			if ctx.ppu < BIG_PPU then
				frame = math.min(frame, 2)
			end
			Fx.drawSprite(ctx, s, frame, px, py, d, false, 0.7)
			drawn.glints += 1
		end
		k += 1
	end
end

local function splash(x: number, y: number, z: number, now: number)
	table.insert(ripples, { x = x, y = y, z = z, t0 = now })
	for _ = 1, 5 do
		local a = rand(0, 6.28)
		local out = rand(0.4, 1.1)
		Fx.spawn(drops, Fx.KINDS.drop, x, y + 0.05, z, 0.9, math.cos(a) * out, math.sin(a) * out, rand(2.6, 4.2))
	end
end

local function stepFish(I: Isle, cam: Raster.Cam, W: number, H: number, now: number, scale: number)
	local f = I.fish
	if f == nil then
		if now >= I.fishAt and #I.shore > 0 then
			I.fishAt = now + rand(9, 22) / scale
			for _ = 1, 8 do
				local k = rng:NextInteger(1, #I.shore // 3)
				local x, z, y = I.shore[k * 3 - 2], I.shore[k * 3 - 1], I.shore[k * 3]
				-- (where the player looks: not under the HUD's cards)
				local ok, px, py = onLayer(cam, W, H, x, y, z, 0)
				local ex, ey = (px - W / 2) / (W * 0.42), (py - H / 2) / (H * 0.4)
				if ok and ex * ex + ey * ey < 1 then
					-- along the shore, a little out to sea (never into the foam)
					local isle = Street.isle(I.tier)
					local ux, uz = x - (I.ox + isle.cx), z - (I.oz + isle.cz)
					local ul = math.max(1e-3, math.sqrt(ux * ux + uz * uz))
					ux, uz = ux / ul, uz / ul
					local side = if rng:NextNumber() < 0.5 then -1 else 1
					local dx, dz = -uz * side * 0.85 + ux * 0.5, ux * side * 0.85 + uz * 0.5
					local dl = math.sqrt(dx * dx + dz * dz)
					I.fish = { x0 = x, z0 = z, x1 = x + dx / dl * 1.7, z1 = z + dz / dl * 1.7, y = y, t0 = now, dur = rand(0.75, 0.95), h = rand(1, 1.5) }
					splash(x, y, z, now)
					break
				end
			end
		end
		return
	end
	if now - f.t0 >= f.dur then
		splash(f.x1, f.y, f.z1, now)
		I.fish = nil
	end
end

local function drawFish(ctx: Fx.Ctx, I: Isle, now: number)
	local f = I.fish
	local s = spriteFor("fish", ctx.ppu)
	if f == nil or s == nil then
		return
	end
	local t = math.clamp((now - f.t0) / f.dur, 0, 1)
	local x, z = f.x0 + (f.x1 - f.x0) * t, f.z0 + (f.z1 - f.z0) * t
	local y = f.y + 4 * f.h * t * (1 - t)
	local ok, px, py, d = onLayer(ctx.cam, ctx.W, ctx.H, x, y, z, 6)
	if ok then
		local ax = Raster.project(ctx.cam, f.x0, f.y, f.z0)
		local bx = Raster.project(ctx.cam, f.x1, f.y, f.z1)
		local frame = if t < 0.38 then 1 elseif t < 0.62 then 2 else 3
		if Fx.drawSprite(ctx, s, frame, px, py, d, bx < ax, 0.3) then
			drawn.fish += 1
		end
	end
end

local function drawRipples(ctx: Fx.Ctx, now: number)
	local s = sprites.ripple
	local k = 1
	while k <= #ripples do
		local r = ripples[k]
		local t = now - r.t0
		if t >= 0.7 or s == nil then
			ripples[k] = ripples[#ripples]
			ripples[#ripples] = nil
			continue
		end
		local px, py, d = Raster.project(ctx.cam, r.x, r.y, r.z)
		-- (flat on the water: its lower rows are nearer than its middle, so a wider tolerance)
		Fx.drawSprite(ctx, s :: Fx.Sprite, if t < 0.3 then 1 else 2, px, py, d, false, 0.7, nil, if t < 0.45 then 1 else (0.7 - t) / 0.25)
		k += 1
	end
end

------------------------------------------------------------------ fireflies
local function spawnFireflies(I: Isle, cam: Raster.Cam, W: number, H: number, want: number)
	if bugs.n >= want or #I.chunks == 0 then
		return
	end
	for _ = 1, 3 do
		local ch = I.chunks[rng:NextInteger(1, #I.chunks)]
		local dc = ch.list[rng:NextInteger(1, #ch.list)]
		local y = LAWN_Y + rand(0.4, 1.8)
		if onLayer(cam, W, H, dc.x, y, dc.z, -4) then
			Fx.spawn(bugs, Fx.KINDS.firefly, dc.x, y, dc.z, rand(7, 11), rand(-0.15, 0.15), rand(-0.15, 0.15), 0)
			return
		end
	end
end

------------------------------------------------------------------ the life, a tick
-- Step every island's lives (with or without a picture: ctx nil steps the birds and the timers only, as in the sims).
local function stepLife(cam: Raster.Cam, W: number, H: number, now: number, dt: number, ctx: Fx.Ctx?)
	local quiet = reduceMotion(now)
	local scale = tierScale()
	local day, mild, night = hour()
	gatherRigs(now)
	updateIsles(cam, W, H, now)
	for _, I in isles do
		if I.scanDirty and now - I.scanAt >= SCAN_DEBOUNCE then
			scan(I)
		end
		for _, b in I.birds do
			stepBird(I, b, cam, W, H, now, dt, day, quiet)
		end
		stepBird(I, I.gull, cam, W, H, now, dt, day, quiet)
		if I.visible and not quiet and ctx then
			if mild then
				for _, f in I.bflies do
					stepBfly(I, f, cam, W, H, now, dt)
				end
			end
			stepCanopies(I, cam, W, H, now, scale)
			stepPuffs(I, cam, W, H, now, scale)
			stepFish(I, cam, W, H, now, scale)
			if night then
				spawnFireflies(I, cam, W, H, math.floor(22 * scale + 0.5))
			end
		end
	end
end

-- The effect layer: a tick of the life, then everything drawn, the ground first.
local function draw(ctx: Fx.Ctx)
	drawn.decos, drawn.birds, drawn.bflies, drawn.fish, drawn.glints, drawn.particles = 0, 0, 0, 0, 0, 0
	local stage = CameraController.view().stage
	if stage then
		-- the hatch scene's stage: nothing of the islands
		if not onStage then
			onStage = true
			Fx.clear(drift)
			Fx.clear(wisps)
			Fx.clear(bugs)
			Fx.clear(drops)
			table.clear(glints)
			table.clear(ripples)
		end
		return
	end
	onStage = false
	local now, dt = ctx.now, ctx.dt
	lastStep = now
	local c0 = os.clock()
	stepLife(ctx.cam, ctx.W, ctx.H, now, dt, ctx)
	local quiet = reduceMotion(now)
	local day, mild, night = hour()
	local scale = tierScale()
	local c1 = os.clock()
	for _, I in isles do
		if I.visible then
			drawDecos(ctx, I, now, quiet)
		end
	end
	local c2 = os.clock()
	if not quiet then
		stepGlints(ctx, now, dt, scale, day)
		drawRipples(ctx, now)
	end
	for _, I in isles do
		if I.visible then
			drawFish(ctx, I, now)
		end
	end
	local n = 0
	if quiet then
		Fx.clear(drift)
		Fx.clear(wisps)
		Fx.clear(drops)
	end
	n += Fx.step(ctx, drops, dt, 4, quiet)
	n += Fx.step(ctx, wisps, dt, 6, quiet)
	n += Fx.step(ctx, drift, dt, 10, quiet)
	local c3 = os.clock()
	cost.life, cost.decos, cost.particles = (c1 - c0) * 1000, (c2 - c1) * 1000, (c3 - c2) * 1000
	for _, I in isles do
		if I.visible then
			for _, b in I.birds do
				drawBird(ctx, b, now)
			end
			drawBird(ctx, I.gull, now)
			if mild and not quiet then
				for _, f in I.bflies do
					drawBfly(ctx, f, now)
				end
			end
		end
	end
	if not night then
		-- (the fireflies fade as the night ends)
		for i = 1, bugs.n do
			bugs.life[i] = math.min(bugs.life[i], bugs.age[i] + 0.8)
		end
	end
	n += Fx.step(ctx, bugs, dt, 4, quiet)
	drawn.particles = n
	cost.creatures = (os.clock() - c3) * 1000
end

-- Sims: the life without a picture (the classic style), on its own clock.
local function onHeartbeat()
	if not running or PixelRenderer.isActive() then
		return
	end
	local now = os.clock()
	local dt = math.clamp(now - lastStep, 0, 0.25)
	lastStep = now
	if CameraController.view().stage then
		return
	end
	local cam, W, H = viewCam()
	stepLife(cam, W, H, now, dt, nil)
end

------------------------------------------------------------------ API
local removeLayer: (() -> ())? = nil

function AmbientView.start()
	if started then
		return
	end
	started = true
	loadSprites()
	removeLayer = PixelRenderer.addFxLayer("ambient", draw)
	RunService.Heartbeat:Connect(onHeartbeat)
end

-- Previews (a timing's A/B): draw nothing (true) or everything again (false).
function AmbientView.setSuspended(on: boolean)
	local rm = removeLayer
	if on and rm then
		rm()
		removeLayer = nil
	elseif not on and rm == nil and started then
		removeLayer = PixelRenderer.addFxLayer("ambient", draw)
	end
end

-- What is alive now (previews and sims).
function AmbientView.stats(): { [string]: any }
	local fishAt: { number }? = nil
	for _, I in isles do
		local f = I.fish
		if f then
			local t = math.clamp((os.clock() - f.t0) / f.dur, 0, 1)
			fishAt = { f.x0 + (f.x1 - f.x0) * t, f.y + 4 * f.h * t * (1 - t), f.z0 + (f.z1 - f.z0) * t }
		end
	end
	local nIsles, nVisible, perched, flying, gulls, decos, perches, puffs, canopies = 0, 0, 0, 0, 0, 0, 0, 0, 0
	for _, I in isles do
		nIsles += 1
		if I.visible then
			nVisible += 1
		end
		for _, b in I.birds do
			if b.state == "perched" then
				perched += 1
			elseif b.state ~= "away" then
				flying += 1
			end
		end
		if I.gull.state ~= "away" then
			gulls += 1
		end
		for _, ch in I.chunks do
			decos += #ch.list
		end
		perches += #I.perches
		puffs += #I.puffs
		canopies += #I.canopies
	end
	return {
		isles = nIsles,
		visible = nVisible,
		birdsPerched = perched,
		birdsFlying = flying,
		gulls = gulls,
		decos = decos,
		perches = perches,
		puffs = puffs,
		canopies = canopies,
		leaves = drift.n,
		wisps = wisps.n,
		fireflies = bugs.n,
		drops = drops.n,
		glints = #glints,
		onStage = onStage,
		drawnDecos = drawn.decos,
		drawnBirds = drawn.birds,
		drawnButterflies = drawn.bflies,
		drawnFish = drawn.fish,
		drawnGlints = drawn.glints,
		drawnParticles = drawn.particles,
		msLife = cost.life,
		msDecos = cost.decos,
		msParticles = cost.particles,
		msCreatures = cost.creatures,
		fishAt = fishAt, -- a fish in the air now (world: x, y, z), else nil
	}
end

-- The birds of an island (sims and previews): kind, state, where, what it stands on.
function AmbientView.birds(plot: number): { { sp: string, state: string, x: number, y: number, z: number, on: string } }
	local out = {}
	local I = isles[plot]
	if I then
		local all = table.clone(I.birds)
		table.insert(all, I.gull)
		for _, b in all do
			table.insert(out, { sp = b.sp, state = b.state, x = b.x, y = b.y, z = b.z, on = if b.perch then (b.perch :: Perch).kind else "" })
		end
	end
	return out
end

-- Sims: step the life on its own while no picture is drawn (the classic style), so the birds can be watched.
function AmbientView.debugRun(on: boolean)
	running = on
	lastStep = os.clock()
end

-- Previews: every island's models looked at from scratch, then again as after a piece placed (each model kept):
-- the ms each took and the spots found (perches, flowers, crowns, smoking spots).
function AmbientView.debugScan(): (number, number, number)
	local t0 = os.clock()
	local n = 0
	for _, I in isles do
		table.clear(I.seen)
		scan(I)
		n += #I.perches + #I.flowers // 3 + #I.canopies + #I.puffs
	end
	local t1 = os.clock()
	for _, I in isles do
		scan(I)
	end
	return (t1 - t0) * 1000, (os.clock() - t1) * 1000, n
end

-- Previews and sims: every bird away, the gull, the next fish and every falling leaf due now.
function AmbientView.debugHurry()
	local now = os.clock()
	for _, I in isles do
		for _, b in I.birds do
			if b.state == "away" then
				b.untilT = now
			end
		end
		if I.gull.state == "away" then
			I.gull.untilT = now
		end
		I.fishAt = now
		for _, c in I.canopies do
			c.nextAt = math.min(c.nextAt, now + rand(0, 2))
		end
	end
	islesAt = -math.huge
end

return AmbientView
