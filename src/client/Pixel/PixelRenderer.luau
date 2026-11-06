--!strict
--!native
-- The pixel filter (docs/ARCHITECTURE.md 9; Random Bakery's pipeline, cut down to one still view of one office).
--
-- One client-side EditableImage, shown by a full-screen ImageLabel (ResampleMode Pixelated) anchored at the screen's
-- top-left corner, so each art pixel is exactly K x K screen px (PixelRenderer.pixelScale(): the game's one pixel
-- size, also the UI's and the text's).
--   Static layer: a raycast G-buffer of the camera's view (CameraController.view: the 2:1 world-anchored grid),
--     baked progressively (one ray per 4x4 block, then 2x2, then every pixel; Pixel/BakeCast) and time-sliced, behind
--     a curtain the first time and behind the old picture after that. Each pixel: the part's colour (PixelColor
--     attribute, else Color; Neon = emissive), its quantised normal, sun visibility (one shadow ray per 2x2 block's
--     even-even anchor, shared by the other three pixels when they show the same part and normal, their own ray
--     otherwise), depth and part id. Shaded with Render/Shading's three toon bands and palette LUT (indoor tint
--     inside the office), then the 1 px ink outline where parts meet and a contact shade at the foot of upright faces.
--   Dynamic layer: the crew (registerDynamic) are drawn analytically every tick at the tier's rate with the same
--     orthographic camera (Render/Raster), depth-tested against the static layer and outlined; only their dirty
--     rects are restored and uploaded.
--   The classic style ("off", or no EditableImage on this device): the layer hides and the Roblox camera shows the
--     3D world (CameraController poses it at CamOffFov).
-- Changes to the office (a move rebuilds Workspace.Plots.Plot_<i>.Static) re-bake the whole layer behind the old
-- picture. Nothing here moves or parents a part of the world.
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Shading = require(ReplicatedStorage.Shared.Render.Shading)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local BakeCast = require(script.Parent.BakeCast)
local ImageMemory = require(script.Parent.ImageMemory)

local PixelRenderer = {}
PixelRenderer.Changed = Util.Signal() :: Types.Signal<Types.PixelTier>

------------------------------------------------------------------ constants
local FAR = Tuning.PixelMaxRayDist
local SUN_V = Vector3.new(Shading.SUN.x, Shading.SUN.y, Shading.SUN.z)
local LIT_UNKNOWN = BakeCast.LIT_UNKNOWN
local EMISSIVE = 0x1000000 -- flag bit stored with the albedo of Neon parts
local UP_INDEX = Shading.normalIndex(0, 1, 0)
local DYN_ID0 = 32768 -- dynamic part ids start here (static ids are 1..32767)
local MAX_RECTS = 12

local NX: { number } = {}
local NY: { number } = {}
local NZ: { number } = {}
for i = 0, 26 do
	NX[i + 1], NY[i + 1], NZ[i + 1] = Shading.normalVec(i)
end

------------------------------------------------------------------ types
type Surf = {
	W: number,
	H: number,
	K: number,
	cam: Raster.Cam,
	look: Vector3,
	view: CameraController.View,
	skyRef: number,
	sColor: buffer, -- u32 RGBA shown (shaded and outlined)
	sShade: buffer, -- u32 RGBA shaded, no outline
	sAlbedo: buffer, -- u32 0xRRGGBB (+ EMISSIVE)
	sNormal: buffer, -- u8 normal index
	sLit: buffer, -- u8 0 shadow, 1 lit, 2 emissive
	sDepth: buffer, -- f32 ray distance
	sId: buffer, -- u16 part id (0 = sky)
	static: Raster.Frame,
	frame: Raster.Frame,
}

type DynPart = { part: BasePart, id: number, shape: string, glow: boolean, rgb: number }
type Dyn = { model: Model, parts: { DynPart } }
type Rect = { x0: number, y0: number, x1: number, y1: number }

------------------------------------------------------------------ state
local started = false
local setting = "high"
local tier: Types.PixelTier = "off"
local reason: string? = nil
local layer: ScreenGui? = nil
local image: ImageLabel? = nil
local img: EditableImage? = nil
local surf: Surf? = nil
local shown = false -- the first finished bake is on screen
local paused = false

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true

-- bake cursor (global art px)
local baking = false
local bakePass = 0
local bakeGX, bakeGY = 0, 0
local bakeRX0, bakeRY0, bakeRX1, bakeRY1 = 0, 0, -1, -1
local bakeOX, bakeOY = 0, 0
local bakeRays = 0
local rebakeAt = -1 -- os.clock() when a pending re-bake starts (debounce)

local staticIds: { [Instance]: number } = {}
local albedos: { [number]: number } = {}
local nextId = 1

local dyns: { [Model]: Dyn } = {}
local nextDyn = DYN_ID0
local prevRects: { Rect } = {}
local tickAcc = 0
local stats = { ticks = 0, rays = 0, bakes = 0, composeMs = 0 }

------------------------------------------------------------------ helpers
local function rgbOf(c: Color3): number
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local function tierSpec(t: string): Tuning.PixelTierSpec
	return Tuning.PixelTiers[t] or Tuning.PixelTiers.high
end

local function dynFolder(): Folder
	local f = workspace:FindFirstChild("PixelDynamic")
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "PixelDynamic"
	nf.Parent = workspace
	return nf
end

local function staticIdOf(part: BasePart): number
	local id = staticIds[part]
	if id then
		return id
	end
	local nid = nextId
	nextId += 1
	if nextId >= DYN_ID0 then
		nextId = 1 -- wraps only in a very long session; a re-bake renumbers
	end
	staticIds[part] = nid
	local attr = part:GetAttribute("PixelColor")
	local rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(part.Color)
	if part.Material == Enum.Material.Neon then
		rgb += EMISSIVE
	end
	albedos[nid] = rgb
	return nid
end

local function mixRgb(over: number, under: number, a: number): number
	local r = bit32.rshift(over, 16) * a + bit32.rshift(under, 16) * (1 - a)
	local g = bit32.band(bit32.rshift(over, 8), 0xFF) * a + bit32.band(bit32.rshift(under, 8), 0xFF) * (1 - a)
	local b = bit32.band(over, 0xFF) * a + bit32.band(under, 0xFF) * (1 - a)
	return math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(b + 0.5)
end

------------------------------------------------------------------ lighting (every tier)
local function applyLighting()
	pcall(function()
		(Lighting :: any).LightingStyle = Enum.LightingStyle.Soft
	end)
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0
	Lighting.ClockTime = 14
	Lighting.Ambient = Color3.fromRGB(150, 140, 160)
	Lighting.OutdoorAmbient = Color3.fromRGB(170, 165, 180)
	if Lighting:FindFirstChild("PixelGrade") == nil then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "PixelGrade"
		cc.Saturation = 0.2
		cc.Contrast = 0.1
		cc.Parent = Lighting
	end
end

------------------------------------------------------------------ layer
local function ensureLayer(): (ScreenGui, ImageLabel)
	local l, im = layer, image
	if l and im then
		return l, im
	end
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Instance.new("ScreenGui")
	gui.Name = "PixelLayer"
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = Tuning.PixelDisplayOrder
	gui.ResetOnSpawn = false
	local label = Instance.new("ImageLabel")
	label.Name = "Image"
	label.AnchorPoint = Vector2.zero
	label.Position = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Active = false
	label.ResampleMode = Enum.ResamplerMode.Pixelated
	label.ImageTransparency = 1
	label.Parent = gui
	gui.Parent = pg
	layer, image = gui, label
	return gui, label
end

local function deactivate(why: string?)
	baking = false
	if img then
		img:Destroy()
		img = nil
	end
	surf = nil
	shown = false
	reason = why
	if image then
		image.ImageTransparency = 1
		image.Visible = false
	end
	prevRects = {}
end

------------------------------------------------------------------ static shading
local function shadeAt(s: Surf, idx: number, x: number, y: number): number
	local gx, gy = x + s.cam.gx, y + s.cam.gy
	if buffer.readu16(s.sId, idx * 2) == 0 then
		return Shading.sky(gx, gy - s.skyRef, s.H)
	end
	local a = buffer.readu32(s.sAlbedo, idx * 4)
	if a >= EMISSIVE then
		return Shading.toonAt(a - EMISSIVE, 0, 1, 0, 2, gx, gy, Shading.INDOOR, 0)
	end
	local ni = buffer.readu8(s.sNormal, idx) + 1
	local lit = buffer.readu8(s.sLit, idx)
	-- indoors: the hit point inside the office's room box
	local cam = s.cam
	local depth = buffer.readf32(s.sDepth, idx * 4)
	local ox, oy, oz = Raster.origin(cam, x, y)
	local wx, wy, wz = ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth
	local r = s.view.room
	local place = if wx >= r.x0 and wx <= r.x1 and wz >= r.z0 and wz <= r.z1 and wy <= r.y1 then Shading.INDOOR else Shading.OUTDOOR
	return Shading.toonAt(a, NX[ni], NY[ni], NZ[ni], lit, gx, gy, place, 0)
end

-- One bake sample at global (gx, gy), filling the block up to (bx1, by1) (global, inclusive) on the layer.
local function castSample(s: Surf, gx: number, gy: number, bx1: number, by1: number, own: boolean, shadows: boolean)
	local cam = s.cam
	local x, y = gx - cam.gx, gy - cam.gy
	local ox, oy, oz = Raster.origin(cam, x, y)
	local mode = if own then (if shadows then BakeCast.SHADOW_TEST else BakeCast.SHADOW_OFF) else BakeCast.shadowMode(shadows, gx, gy)
	local part, depth, ni, lit, rays, tint = BakeCast.cast(params, Vector3.new(ox, oy, oz), s.look, FAR, mode, SUN_V)
	bakeRays += rays
	local id, albedo = 0, 0
	if part ~= nil then
		id = staticIdOf(part)
		albedo = albedos[id]
		if tint ~= nil then
			local tid = staticIdOf(tint)
			local over = albedos[tid] % EMISSIVE
			albedo = mixRgb(over, albedo % EMISSIVE, 1 - tint.Transparency) + (if albedo >= EMISSIVE then EMISSIVE else 0)
		end
		if albedo >= EMISSIVE then
			lit = 2
		elseif lit == LIT_UNKNOWN then
			-- share the 2x2 block's anchor when it shows the same part and normal, else a ray of its own
			local ax, ay = x - gx % 2, y - gy % 2
			local shared = false
			if ax >= 0 and ay >= 0 then
				local c = ay * s.W + ax
				local alit = buffer.readu8(s.sLit, c)
				if buffer.readu16(s.sId, c * 2) == id and buffer.readu8(s.sNormal, c) == ni and alit <= 1 then
					lit = alit
					shared = true
				end
			end
			if not shared then
				local k = ni + 1
				local pos = Vector3.new(ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth)
				lit = BakeCast.sunVisible(params, pos, Vector3.new(NX[k], NY[k], NZ[k]), SUN_V)
				bakeRays += 1
			end
		end
	else
		lit = 1
	end
	local W = s.W
	local x1, y1 = math.min(bx1 - cam.gx, W - 1), math.min(by1 - cam.gy, s.H - 1)
	local idx = y * W + x
	buffer.writeu16(s.sId, idx * 2, id)
	buffer.writef32(s.sDepth, idx * 4, depth)
	buffer.writeu32(s.sAlbedo, idx * 4, albedo)
	buffer.writeu8(s.sNormal, idx, ni)
	buffer.writeu8(s.sLit, idx, lit)
	local c = shadeAt(s, idx, x, y)
	buffer.writeu32(s.sShade, idx * 4, c)
	for by = y, y1 do
		local row = by * W
		for bx = x, x1 do
			local b = row + bx
			if b ~= idx then
				buffer.writeu16(s.sId, b * 2, id)
				buffer.writef32(s.sDepth, b * 4, depth)
				buffer.writeu32(s.sAlbedo, b * 4, albedo)
				buffer.writeu8(s.sNormal, b, ni)
				buffer.writeu8(s.sLit, b, lit)
				buffer.writeu32(s.sShade, b * 4, c)
			end
		end
	end
end

-- Contact shade (Random Bakery's gentle ambient occlusion): an up-facing pixel whose neighbour above it on screen is
-- the foot of an upright face standing on it shades one band darker, so desks, shelves and pots sit on the floor.
local function contactPass(s: Surf)
	local W, H = s.W, s.H
	local sId, sNormal, sDepth, sColor, sShade, sLit = s.sId, s.sNormal, s.sDepth, s.sColor, s.sShade, s.sLit
	local cam = s.cam
	local ly, jy = cam.ly, cam.jy
	for y = 1, H - 1 do
		local row = y * W
		for x = 0, W - 1 do
			local i = row + x
			local id = buffer.readu16(sId, i * 2)
			if id ~= 0 and buffer.readu8(sNormal, i) == UP_INDEX and buffer.readu8(sLit, i) <= 1 then
				local u = i - W
				local uid = buffer.readu16(sId, u * 2)
				if uid ~= 0 and uid ~= id and (buffer.readu8(sNormal, u) // 3) % 3 == 1 then
					local d, du = buffer.readf32(sDepth, i * 4), buffer.readf32(sDepth, u * 4)
					local rise = (du - d) * ly - jy
					if math.abs(du - d) < 1.2 and rise < 1 and rise > -0.2 and buffer.readu32(sColor, i * 4) == buffer.readu32(sShade, i * 4) then
						local a = buffer.readu32(s.sAlbedo, i * 4)
						if a < EMISSIVE then
							local ni = buffer.readu8(sNormal, i) + 1
							local gx, gy = x + cam.gx, y + cam.gy
							buffer.writeu32(sColor, i * 4, Shading.toonAt(a, NX[ni], NY[ni], NZ[ni], buffer.readu8(sLit, i), gx, gy, Shading.INDOOR, -1))
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ upload
local function uploadAll(s: Surf)
	local im = img
	if im == nil then
		return
	end
	local f = s.frame
	pcall(function()
		im:WritePixelsBuffer(Vector2.zero, Vector2.new(s.W, s.H), f.color)
	end)
end

local function uploadRect(s: Surf, r: Rect)
	local im = img
	if im == nil then
		return
	end
	local x0, y0 = math.max(0, r.x0), math.max(0, r.y0)
	local x1, y1 = math.min(s.W - 1, r.x1), math.min(s.H - 1, r.y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local w, h = x1 - x0 + 1, y1 - y0 + 1
	local b = buffer.create(w * h * 4)
	local src = s.frame.color
	for y = y0, y1 do
		buffer.copy(b, (y - y0) * w * 4, src, (y * s.W + x0) * 4, w * 4)
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), b)
	end)
end

------------------------------------------------------------------ bake
local function finishBake(s: Surf)
	baking = false
	Shading.outline(s.static, 0, 0, s.W - 1, s.H - 1, s.sShade)
	contactPass(s)
	local f = s.frame
	buffer.copy(f.color, 0, s.sColor, 0, s.W * s.H * 4)
	buffer.copy(f.depth, 0, s.sDepth, 0, s.W * s.H * 4)
	buffer.copy(f.id, 0, s.sId, 0, s.W * s.H * 2)
	prevRects = {}
	uploadAll(s)
	stats.bakes += 1
	local im = image
	if im then
		im.Visible = true
		if not shown then
			shown = true
			local tw = TweenService:Create(im, TweenInfo.new(0.35), { ImageTransparency = 0 })
			tw:Play()
			task.delay(0.4, function()
				if image == im then
					im.ImageTransparency = 0
				end
			end)
		else
			im.ImageTransparency = 0
		end
	end
end

-- Bake samples until the deadline; true when the bake is done.
local function bakeSome(deadline: number): boolean
	local s = surf
	if s == nil or not baking then
		return true
	end
	local shadows = tierSpec(tier).shadows
	local steps = BakeCast.STEPS
	while bakePass <= 3 do
		local st = steps[bakePass]
		while bakeGY <= bakeRY1 do
			while bakeGX <= bakeRX1 do
				if os.clock() > deadline then
					return false
				end
				local bx, by = bakeGX, bakeGY
				bakeGX += st
				local x, y = math.max(bx, bakeRX0), math.max(by, bakeRY0)
				if x == bx and y == by then
					if not BakeCast.skip(bakePass, x, y) then
						castSample(s, x, y, bx + st - 1, by + st - 1, false, shadows)
					end
				elseif bakePass < 3 then
					-- a block starting off the layer: a stand-in at its first pixel on it (later passes replace it)
					castSample(s, x, y, bx + st - 1, by + st - 1, true, shadows)
				end
			end
			bakeGX = bakeOX
			bakeGY += st
		end
		bakePass += 1
		bakeGX, bakeGY = bakeOX, bakeOY
	end
	finishBake(s)
	return true
end

local function startBake()
	local s = surf
	if s == nil then
		return
	end
	table.clear(staticIds)
	table.clear(albedos)
	nextId = 1
	local cam = s.cam
	bakeRX0, bakeRY0 = cam.gx, cam.gy
	bakeRX1, bakeRY1 = cam.gx + s.W - 1, cam.gy + s.H - 1
	bakeOX, bakeOY = bakeRX0 - bakeRX0 % 4, bakeRY0 - bakeRY0 % 4
	bakeGX, bakeGY = bakeOX, bakeOY
	bakePass = 1
	baking = true
	-- the raycasts see only the static world: never the crew, never other players' things
	params.FilterDescendantsInstances = { dynFolder() }
end

-- A layer for the camera's view: buffers, image and a fresh bake.
local function buildSurf(v: CameraController.View)
	local K = v.K
	local W, H = math.ceil(v.fullX / K), math.ceil(v.fullY / K)
	local _, im = ensureLayer()
	local newImg = img
	if newImg == nil or newImg.Size.X ~= W or newImg.Size.Y ~= H then
		if newImg then
			newImg:Destroy()
		end
		newImg = ImageMemory.create(W, H, "world")
		if newImg == nil then
			tier = "off"
			deactivate("this device can't draw the pixel filter")
			CameraController.setPixelLimit(tierSpec("high").h, true)
			PixelRenderer.Changed:Fire(tier)
			return
		end
		img = newImg
		im.ImageContent = Content.fromObject(newImg)
		shown = false
		im.ImageTransparency = 1
	end
	im.Size = UDim2.fromOffset(W * K, H * K)
	im.Visible = true
	local cam = Raster.gridCam(v.rot12, v.grid, v.fullX, v.fullY, K, Tuning.CamRayBack)
	local n = W * H
	local frame = Raster.newFrame(W, H)
	local sColor, sDepth, sId = buffer.create(n * 4), buffer.create(n * 4), buffer.create(n * 2)
	-- the sky's gradient starts one layer height above the office's floor line (it does not crawl between views)
	local _, floorY = Raster.gridPoint(v.rot12, v.grid, v.center.X, 0, v.center.Z)
	surf = {
		W = W,
		H = H,
		K = K,
		cam = cam,
		look = v.look,
		view = v,
		skyRef = math.floor(floorY) - H,
		sColor = sColor,
		sShade = buffer.create(n * 4),
		sAlbedo = buffer.create(n * 4),
		sNormal = buffer.create(n),
		sLit = buffer.create(n),
		sDepth = sDepth,
		sId = sId,
		static = { W = W, H = H, color = sColor, depth = sDepth, id = sId },
		frame = frame,
	}
	prevRects = {}
	startBake()
end

------------------------------------------------------------------ dynamic layer
local panX, panY = 0, 0
local function shadeLit(rgb: number, nx: number, ny: number, nz: number, x: number, y: number): number
	return Shading.toonAt(rgb, nx, ny, nz, 1, x + panX, y + panY, Shading.INDOOR, 0)
end
local function shadeGlow(rgb: number, nx: number, ny: number, nz: number, x: number, y: number): number
	return Shading.toonAt(rgb, nx, ny, nz, 2, x + panX, y + panY, Shading.INDOOR, 0)
end
Raster.markUniform(shadeLit)
Raster.markUniform(shadeGlow)

local function restoreRect(s: Surf, r: Rect)
	local W = s.W
	local x0, y0 = math.max(0, r.x0), math.max(0, r.y0)
	local x1, y1 = math.min(W - 1, r.x1), math.min(s.H - 1, r.y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local f = s.frame
	local w = x1 - x0 + 1
	for y = y0, y1 do
		local o = y * W + x0
		buffer.copy(f.color, o * 4, s.sColor, o * 4, w * 4)
		buffer.copy(f.depth, o * 4, s.sDepth, o * 4, w * 4)
		buffer.copy(f.id, o * 2, s.sId, o * 2, w * 2)
	end
end

local function compose()
	local s = surf
	if s == nil then
		return
	end
	local t0 = os.clock()
	local cam = s.cam
	panX, panY = cam.gx, cam.gy
	for _, r in prevRects do
		restoreRect(s, r)
	end
	local rects: { Rect } = {}
	local drawn = 0
	for model, d in dyns do
		if model.Parent == nil then
			continue
		end
		drawn += 1
		if drawn > Tuning.PixelMaxDyn then
			break
		end
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, p in d.parts do
			local part = p.part
			if part.Parent == nil or part.Transparency >= 0.95 then
				continue
			end
			local cf12 = { part.CFrame:GetComponents() }
			local sz = part.Size
			local bx0, by0, bx1, by1 = Raster.boxRect(cam, cf12, sz.X, sz.Y, sz.Z)
			if bx0 and by0 and bx1 and by1 then
				Raster.drawPart(s.frame, cam, p.shape, cf12, sz.X, sz.Y, sz.Z, p.rgb, p.id, if p.glow then shadeGlow else shadeLit)
				x0, y0, x1, y1 = math.min(x0, bx0), math.min(y0, by0), math.max(x1, bx1), math.max(y1, by1)
			end
		end
		if x0 <= x1 then
			table.insert(rects, { x0 = x0 - 1, y0 = y0 - 1, x1 = x1 + 1, y1 = y1 + 1 })
		end
	end
	for _, r in rects do
		Shading.outline(s.frame, r.x0, r.y0, r.x1, r.y1)
	end
	-- upload the old and the new rects (merged when there are many)
	local up: { Rect } = table.clone(prevRects)
	for _, r in rects do
		table.insert(up, r)
	end
	if #up > MAX_RECTS then
		local u: Rect = { x0 = math.huge, y0 = math.huge, x1 = -math.huge, y1 = -math.huge }
		for _, r in up do
			u.x0, u.y0, u.x1, u.y1 = math.min(u.x0, r.x0), math.min(u.y0, r.y0), math.max(u.x1, r.x1), math.max(u.y1, r.y1)
		end
		up = { u }
	end
	for _, r in up do
		uploadRect(s, r)
	end
	prevRects = rects
	stats.ticks += 1
	stats.composeMs = (os.clock() - t0) * 1000
end

------------------------------------------------------------------ tiers
local function effective(t: string): Types.PixelTier
	if t == "off" then
		return "off"
	elseif t == "low" then
		return "low"
	elseif t == "medium" then
		return "medium"
	end
	return "high"
end

local function applyTier(want: string)
	local t: Types.PixelTier = effective(want)
	local before = tier
	tier = (t :: any) :: Types.PixelTier
	if t == "off" then
		deactivate("the classic look is on")
		CameraController.setPixelLimit(tierSpec("high").h, true)
	else
		reason = nil
		CameraController.setPixelLimit(tierSpec(t).h, false)
		-- a view whose key did not change (same K) keeps its layer; otherwise ViewChanged rebuilds it
		if surf == nil then
			buildSurf(CameraController.view())
		end
	end
	if before ~= tier then
		PixelRenderer.Changed:Fire(tier)
	end
end

------------------------------------------------------------------ lifecycle
local function onHeartbeat(dt: number)
	if not started or paused or tier == "off" then
		return
	end
	if rebakeAt >= 0 and os.clock() >= rebakeAt then
		rebakeAt = -1
		startBake()
	end
	if baking then
		local budget = Tuning.PixelBakeMsPerFrame + (if shown then 0 else 8)
		bakeSome(os.clock() + budget / 1000)
		return
	end
	local hz = tierSpec(tier).hz
	tickAcc += dt
	if tickAcc >= 1 / hz then
		tickAcc = 0
		compose()
	end
end

local function watchStatic()
	-- a change to any plot's Static (the office rebuilt on a move) re-bakes the layer behind the old picture
	local plots = workspace:WaitForChild("Plots", 30)
	if plots == nil then
		return
	end
	-- only the player's own plot: other players' offices are far off screen
	local function poke(d: Instance)
		local s = surf
		if s == nil then
			return
		end
		local mine = plots:FindFirstChild("Plot_" .. s.view.plot)
		if mine and d:IsDescendantOf(mine) then
			rebakeAt = os.clock() + 0.5
		end
	end
	plots.DescendantAdded:Connect(poke)
	plots.DescendantRemoving:Connect(poke)
end

function PixelRenderer.init()
	applyLighting()
end

function PixelRenderer.start()
	if started then
		return
	end
	started = true
	dynFolder()
	CameraController.ViewChanged:Connect(function(v)
		if tier ~= "off" then
			buildSurf(v)
		end
	end)
	StateClient.Changed:Connect(function(v)
		local want = v.settings.pixel
		if want ~= setting then
			setting = want
			applyTier(want)
		end
	end)
	local v = StateClient.view()
	if v then
		setting = v.settings.pixel
	end
	applyTier(setting)
	RunService.Heartbeat:Connect(onHeartbeat)
	task.spawn(watchStatic)
end

------------------------------------------------------------------ API
function PixelRenderer.setTier(t: string): Types.PixelTier
	setting = t
	applyTier(t)
	return tier
end

function PixelRenderer.tier(): Types.PixelTier
	return tier
end

function PixelRenderer.isActive(): boolean
	return tier ~= "off" and surf ~= nil
end

function PixelRenderer.unavailableReason(): string?
	return reason
end

-- The game's one pixel size K (the classic style keeps the high tier's).
function PixelRenderer.pixelScale(): number
	local s = surf
	if s then
		return s.K
	end
	return CameraController.pixelK()
end

-- Whether the first picture is on screen (or the classic style shows the world), and the bake's progress 0..1.
function PixelRenderer.firstPicture(): (boolean, number)
	if tier == "off" then
		return true, 1
	end
	if shown then
		return true, 1
	end
	if not baking then
		return false, 0
	end
	local s = surf
	if s == nil then
		return false, 0
	end
	local passShare = { 0, 1 / 21, 5 / 21 }
	local weight = { 1 / 21, 4 / 21, 16 / 21 }
	local rows = math.max(1, bakeRY1 - bakeRY0 + 1)
	local p = math.clamp(bakePass, 1, 3)
	return false, math.clamp(passShare[p] + weight[p] * (bakeGY - bakeRY0) / rows, 0, 0.99)
end

function PixelRenderer.registerDynamic(model: Model)
	local parts: { DynPart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local shape = "Block"
			if d:IsA("Part") then
				if d.Shape == Enum.PartType.Ball then
					shape = "Ball"
				elseif d.Shape == Enum.PartType.Cylinder then
					shape = "Cylinder"
				end
			elseif d:IsA("WedgePart") then
				shape = "Wedge"
			elseif d:IsA("CornerWedgePart") then
				shape = "CornerWedge"
			end
			local attr = d:GetAttribute("PixelColor")
			local rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(d.Color)
			nextDyn += 1
			if nextDyn >= 65535 then
				nextDyn = DYN_ID0 + 1
			end
			table.insert(parts, { part = d, id = nextDyn, shape = shape, glow = d.Material == Enum.Material.Neon, rgb = rgb })
		end
	end
	dyns[model] = { model = model, parts = parts }
end

function PixelRenderer.unregisterDynamic(model: Model)
	dyns[model] = nil
end

-- Re-colour a registered model's parts after their Color changed (a monitor lighting up).
function PixelRenderer.refreshDynamic(model: Model)
	local d = dyns[model]
	if d then
		for _, p in d.parts do
			local attr = p.part:GetAttribute("PixelColor")
			p.rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(p.part.Color)
			p.glow = p.part.Material == Enum.Material.Neon
		end
	end
end

function PixelRenderer.rebake()
	if surf then
		startBake()
	end
end

function PixelRenderer.setPaused(on: boolean)
	paused = on
end

-- A world point in full-screen px (ScreenInsets None space) and whether it is on screen: the layer's own camera
-- snapped to K when the filter is on, the Roblox camera otherwise.
function PixelRenderer.project(world: Vector3): (Vector2, boolean)
	local s = surf
	if s and tier ~= "off" then
		local px, py, d = Raster.project(s.cam, world.X, world.Y, world.Z)
		local x, y = math.floor(px) * s.K, math.floor(py) * s.K
		return Vector2.new(x, y), d > 0 and x >= 0 and y >= 0 and x < s.view.fullX and y < s.view.fullY
	end
	local cam = workspace.CurrentCamera
	if cam == nil then
		return Vector2.zero, false
	end
	local p, on = cam:WorldToViewportPoint(world)
	return Vector2.new(p.X, p.Y), on
end

-- The art pixel (i, j) of the top-left grid that shows a world point (UI on a pixel canvas), and whether on screen.
function PixelRenderer.projectPixel(world: Vector3): (number, number, boolean)
	local pos, on = PixelRenderer.project(world)
	local k = PixelRenderer.pixelScale()
	return math.floor(pos.X / k), math.floor(pos.Y / k), on
end

-- CLI checks only: the layer, its bake and what the ticks cost.
function PixelRenderer.debugStatic(): { W: number, H: number, K: number, baking: boolean, shown: boolean, color: buffer?, rays: number, bakes: number, ticks: number, composeMs: number, dyn: number }
	local s = surf
	local n = 0
	for _ in dyns do
		n += 1
	end
	return {
		W = if s then s.W else 0,
		H = if s then s.H else 0,
		K = if s then s.K else 0,
		baking = baking,
		shown = shown,
		color = if s then s.frame.color else nil,
		rays = bakeRays,
		bakes = stats.bakes,
		ticks = stats.ticks,
		composeMs = stats.composeMs,
		dyn = n,
	}
end

-- (Palette is read so the LUT carries the office themes' colours.)
Shading.setPalette(Shading.defaultColors())
Shading.setMode("day")
local _ = Palette

return PixelRenderer
