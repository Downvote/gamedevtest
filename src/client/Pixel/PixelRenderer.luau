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
--     otherwise; then every shared pixel next to a change of light and shadow casts its own, so shadow edges fall on
--     the 1 px grid, never in 2 px steps), depth and part id. Shaded with Render/Shading's three toon bands and palette LUT (indoor tint
--     inside the office), then the 1 px ink outline where parts meet and a contact shade at the foot of upright faces.
--   Dynamic layer: the crew (registerDynamic) are drawn analytically every tick at the tier's rate with the same
--     orthographic camera (Render/Raster), depth-tested against the static layer and outlined; only their dirty
--     rects are restored and uploaded.
--   The classic style ("off", or no EditableImage on this device): the layer hides and the Roblox camera shows the
--     3D world (CameraController poses it at CamOffFov).
-- Pans (the view following the founder down the street, Build mode's drag) scroll the static layer by whole art px
-- and cast only the strips they uncover (anchors first, so a strip's pixels share sun rays like the bake's), at most
-- Tuning.PixelPanRays rays a frame (a longer pan catches up over frames); a jump past half the layer re-bakes. Parts
-- that come or go under Workspace.Plots (a piece of decor placed, a neighbour moving in) re-cast the rect they and
-- their shadow cover (in global art px, so a pan does not move them), at most Tuning.PixelInvalidateRaysFrame rays a
-- frame; a change over a third of the layer re-bakes it whole behind the old picture. Players' characters are never
-- in the bake (AvatarView draws the founders). Nothing here moves or parents a part of the world.
-- A microgame's stage (CameraController.setStage) is a view of its own, baked with a bigger budget a frame while the
-- play overlay's curtain covers the screen; the street's finished picture is kept aside meanwhile and comes back at
-- once when the stage closes (baked again only if a part under Workspace.Plots came or went in between). A dynamic
-- model with a "PixelShadow" attribute (a radius in studs) casts a blob shadow on the static picture under it (on
-- the ground at its "PixelGroundY", default 0): the pixels there are shaded as in the sun's shadow, so it lands on the
-- palette's own shadow tones, smaller the higher the model is.
-- Water: a part with a "PixelWater" attribute (1 the sea, 2 the shallows, 3 the foam) marks its pixels in the bake
-- with that class and a wave phase from the hit point's world position (sWClass, sWave: they scroll with the
-- picture). WATER_HZ times a second (not on the low tier) the water pixels not under an ink line are shaded again
-- from their baked shade: crests of light (and the sea's darker troughs) travel across the sea and the shallows along
-- the phase's wavy lines, and the foam laps in and out along the shore. Only colours change: no ray is cast.
local GuiService = game:GetService("GuiService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Street = require(ReplicatedStorage.Shared.Data.Street)
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
local CULL = 48 -- art px past the layer's edge a dynamic model may stand and still be drawn
local PICK_LEN = 2000
local REBAKE_SHARE = 0.33 -- invalidated rects covering more of the layer than this re-bake it whole
local WATER_HZ = 6 -- the water's frames a second
local WATER_SPEED = 2 -- phase units a frame (a crest every 64 units: about 10 studs)
local WATER_CREST = 0xC8F0FA -- a crest's light blue (0xRRGGBB)
local WATER_DEEP = 0x1E5C7A
local WATER_SHALLOW = 0x6CCFD2

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
	sShadowC: buffer, -- u32 RGBA the pixel shaded as in the sun's shadow (blob shadows' cache; 0: not worked out yet)
	sAlbedo: buffer, -- u32 0xRRGGBB (+ EMISSIVE)
	sNormal: buffer, -- u8 normal index
	sLit: buffer, -- u8 0 shadow, 1 lit, 2 emissive
	sDepth: buffer, -- f32 ray distance
	sId: buffer, -- u16 part id (0 = sky)
	sShare: buffer, -- u8 1: the pixel's sun visibility was copied from its 2x2 block's anchor (refined at edges)
	sWClass: buffer, -- u8 water class (0: not water; PixelWater)
	sWave: buffer, -- u8 the water's wave phase (from the world position)
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
params.CollisionGroup = "PixelRays" -- the invisible walls ("Bounds") never meet the rays (PlotService registers both)

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
local waters: { [number]: number } = {} -- static id -> PixelWater class (0 none)
local waterClock, waterFrame = 0, 0
local waterTones: { [number]: number } = {} -- (base colour, class, tone) -> colour
local nextId = 1

local dyns: { [Model]: Dyn } = {}
local nextDyn = DYN_ID0
local dynGlow: { [number]: boolean } = {} -- dynamic part id -> Neon (it stays lit at night)
local prevRects: { Rect } = {}
local tickAcc = 0
local stats = { ticks = 0, rays = 0, bakes = 0, composeMs = 0, scrolls = 0, scrollRays = 0, recasts = 0 }
local needFull = false -- the next compose copies the whole static layer and uploads the whole image
-- the street's finished picture, kept while a microgame's stage has the view (restored when its key comes back)
type Stash = { key: string, surf: Surf, ids: { [Instance]: number }, albedos: { [number]: number }, waters: { [number]: number }, nextId: number, dirty: boolean }
local stash: Stash? = nil
local offX, offY = 0, 0 -- the layer's shake offset (art px)

-- invalidated rects in global art px, and the one being re-cast (its cursor: phase 1 anchors, phase 2 the rest)
local invQueue: { Rect } = {}
local invCur: { r: Rect, phase: number, gx: number, gy: number }? = nil

-- what the bake's rays never see: the crew's rigs and every player's character
local excluded: { Instance } = {}
local excludeDirty = true

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
	local wk = part:GetAttribute("PixelWater")
	waters[nid] = if type(wk) == "number" then wk else 0
	-- the wind: leaves sway (class 4), flags ripple (class 5)
	local wind = part:GetAttribute("PixelWind")
	if waters[nid] == 0 and (wind == 1 or wind == 2) then
		waters[nid] = 3 + (wind :: number)
	end
	return nid
end

-- the wind's paint on the static layer (the wind section): undone before a scroll, a stash or a bake
local windSaved: { [number]: number } = {} -- pixel -> its colour before the wind
local windWrote: { [number]: number } = {} -- pixel -> the colour the wind painted
local windOn: Surf? = nil -- the layer they belong to (another layer's are dropped, never painted elsewhere)

local function windRestore(s: Surf): boolean
	local color = s.sColor
	local any = false
	if windOn == s then
		for i, c in windSaved do
			if buffer.readu32(color, i * 4) == windWrote[i] then
				buffer.writeu32(color, i * 4, c)
				any = true
			end
		end
	end
	windOn = nil
	table.clear(windSaved)
	table.clear(windWrote)
	return any
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
	local shared = false
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
	-- water: its class and the wave phase at the hit point (wavy lines across the world, about 10 studs apart)
	local wcls = if part ~= nil and tint == nil then waters[id] or 0 else 0
	local wph = 0
	if wcls ~= 0 then
		local wx, wz = ox + cam.lx * depth, oz + cam.lz * depth
		if wcls == 4 then
			-- leaves: gusts sweeping slowly across the islands (a canopy moves as one)
			wph = math.floor((wx * 0.22 + wz * 0.16) * 4) % 256
		elseif wcls == 5 then
			-- flags: a quick wave along their length
			wph = math.floor((wx * 1.6 + wz * 1.1) * 4) % 256
		else
			local v = wx * 0.6 + wz * 0.35 + 1.6 * math.sin(wz * 0.23 + wx * 0.05) + 1.1 * math.sin(wx * 0.17)
			wph = math.floor(v * 9.14) % 256
		end
	end
	buffer.writeu8(s.sWClass, idx, wcls)
	buffer.writeu8(s.sWave, idx, wph)
	buffer.writeu8(s.sShare, idx, if shared then 1 else 0)
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
				buffer.writeu8(s.sShare, b, 1)
				buffer.writeu8(s.sWClass, b, wcls)
				buffer.writeu8(s.sWave, b, wph)
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
local function contactPass(s: Surf, rx0: number?, ry0: number?, rx1: number?, ry1: number?)
	local W, H = s.W, s.H
	local sId, sNormal, sDepth, sColor, sShade, sLit = s.sId, s.sNormal, s.sDepth, s.sColor, s.sShade, s.sLit
	local cam = s.cam
	local ly, jy = cam.ly, cam.jy
	local x0, y0 = math.max(0, rx0 or 0), math.max(1, ry0 or 1)
	local x1, y1 = math.min(W - 1, rx1 or (W - 1)), math.min(H - 1, ry1 or (H - 1))
	for y = y0, y1 do
		local row = y * W
		for x = x0, x1 do
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

------------------------------------------------------------------ the time of day
-- A colour grade over the picture as it is uploaded (GAME_DESIGN 8: the day and night; UI/DayLight sets it from the
-- day's clock): the layers keep their daylight colours; each uploaded pixel goes through `gradeOf` (cached by colour
-- and light level). Lamps, torches, fires and windows (Neon parts) keep their own colour and pool light round them
-- in three stepped rings on the pixel grid (`lightMap`: the static layer's lamps and the dynamic ones, rebuilt when
-- the picture moves, at most every LIGHT_EVERY seconds).
export type Grade = {
	mr: number, -- the light's colour: red, green, blue multipliers (1 by day)
	mg: number,
	mb: number,
	lift: number, -- a blue lift in the shadows (0..40)
	sat: number, -- saturation (1 by day)
	lamps: number, -- how much the lamps' pools light (0 by day, 1 at night)
}
local grade: Grade? = nil
local gradeKey = ""
local gradeMap: { [number]: number } = {}
local lightMap: buffer? = nil
local lightStale = true
local lightAt = 0
local LIGHT_EVERY = 0.4
local RING = { 3.5, 6.5, 10 } -- a pool's rings (art px, vertical; twice as wide: the ground is seen at 2:1)

local function clampByte(v: number): number
	return if v < 0 then 0 elseif v > 255 then 255 else math.floor(v + 0.5)
end

local function gradeOf(c: number, lvl: number): number
	local g = grade :: Grade
	local r, gg, b = c % 256, (c // 256) % 256, (c // 65536) % 256
	local a = c - c % 16777216
	local l = 0.3 * r + 0.59 * gg + 0.11 * b
	local sat = g.sat
	-- how dark the hour is (0 by day and in the golden dusk's warmth, 1 at night): from the light's colour
	local dark = math.clamp((1 - (g.mr + g.mg + g.mb) / 3) / 0.5, 0, 1)
	-- pale things lose more of their light than dark ones as it gets dark (the shells, the sand, a sail must not
	-- glow blue in the night): the luminance over a knee is pressed down
	local press = 1 - dark * 0.45 * math.max(0, (l - 90) / 165)
	local nr = (l + (r - l) * sat) * g.mr * press + g.lift * 0.2
	local ng = (l + (gg - l) * sat) * g.mg * press + g.lift * 0.35
	local nb = (l + (b - l) * sat) * g.mb * press + g.lift
	if lvl > 0 and g.lamps > 0 and dark > 0 then
		-- a lamp's pool: back toward the colour by day, warmed; only as strong as the dark is deep (no orange rings
		-- in the late afternoon's light), never all the way back to the day
		local k = lvl / 3 * g.lamps * dark * 0.85
		nr += (math.max(nr, r * 1.02) - nr) * k
		ng += (math.max(ng, gg * 0.9) - ng) * k
		nb += (math.max(nb, b * 0.72) - nb) * k
	end
	return clampByte(nr) + clampByte(ng) * 256 + clampByte(nb) * 65536 + a
end

local function isGlow(id: number): boolean
	if id == 0 then
		return false
	elseif id < DYN_ID0 then
		return (albedos[id] or 0) >= EMISSIVE
	end
	return dynGlow[id] == true
end

local function splat(lm: buffer, W: number, H: number, px: number, py: number)
	local R = RING[3]
	for dy = -math.floor(R), math.floor(R) do
		local y = py + dy
		if y < 0 or y >= H then
			continue
		end
		for dx = -math.floor(R * 2), math.floor(R * 2) do
			local x = px + dx
			if x < 0 or x >= W then
				continue
			end
			local e = math.sqrt((dx * 0.5) ^ 2 + dy * dy)
			local lvl = if e < RING[1] then 3 elseif e < RING[2] then 2 elseif e < R then 1 else 0
			if lvl > 0 then
				local i = y * W + x
				if buffer.readu8(lm, i) < lvl then
					buffer.writeu8(lm, i, lvl)
				end
			end
		end
	end
end

-- The lamps' pools: every 4x4 block of the static layer with a lamp's pixel, and every lit dynamic part.
local function buildLight(s: Surf)
	local W, H = s.W, s.H
	local n = W * H
	local lm = lightMap
	if lm == nil or buffer.len(lm) ~= n then
		lm = buffer.create(n)
		lightMap = lm
	else
		buffer.fill(lm, 0, 0)
	end
	local sid = s.sId
	for cy = 0, H - 1, 4 do
		for cx = 0, W - 1, 4 do
			local hit = false
			for y = cy, math.min(H - 1, cy + 3) do
				for x = cx, math.min(W - 1, cx + 3) do
					local id = buffer.readu16(sid, (y * W + x) * 2)
					if id ~= 0 and id < DYN_ID0 and (albedos[id] or 0) >= EMISSIVE then
						hit = true
						break
					end
				end
				if hit then
					break
				end
			end
			if hit then
				splat(lm :: buffer, W, H, cx + 2, cy + 5)
			end
		end
	end
	local cam = s.cam
	for model, d in dyns do
		if model.Parent == nil then
			continue
		end
		for _, p in d.parts do
			if p.glow and p.part.Parent ~= nil then
				local pos = p.part.Position
				local fx, fy = Raster.project(cam, pos.X, pos.Y, pos.Z)
				local x, y = math.floor(fx), math.floor(fy)
				if x >= -20 and x < W + 20 and y >= -10 and y < H + 10 then
					splat(lm :: buffer, W, H, x, y + 3)
				end
			end
		end
	end
	lightStale = false
	lightAt = os.clock()
end

-- n pixels of the frame from pixel i0, graded into out from pixel o0.
local function gradeSpan(s: Surf, i0: number, n: number, out: buffer, o0: number)
	local src, fid = s.frame.color, s.frame.id
	local lm = if (grade :: Grade).lamps > 0 then lightMap else nil
	local map = gradeMap
	for k = 0, n - 1 do
		local i = i0 + k
		local c = buffer.readu32(src, i * 4)
		local id = buffer.readu16(fid, i * 2)
		local o = c
		if not isGlow(id) then
			local lvl = if lm then buffer.readu8(lm, i) else 0
			local key = c + lvl * 4294967296
			o = map[key]
			if o == nil then
				o = gradeOf(c, lvl)
				map[key] = o
			end
		end
		buffer.writeu32(out, (o0 + k) * 4, o)
	end
end

local gradeBuf: buffer? = nil

------------------------------------------------------------------ upload
local function uploadAll(s: Surf)
	local im = img
	if im == nil then
		return
	end
	local f = s.frame
	local src = f.color
	if grade then
		local n = s.W * s.H
		local now = os.clock()
		if (grade :: Grade).lamps > 0 and (lightMap == nil or buffer.len(lightMap :: buffer) ~= n or ((lightStale or now - lightAt >= 1) and now - lightAt >= LIGHT_EVERY)) then
			buildLight(s)
		end
		local b = gradeBuf
		if b == nil or buffer.len(b) ~= n * 4 then
			b = buffer.create(n * 4)
			gradeBuf = b
		end
		gradeSpan(s, 0, n, b :: buffer, 0)
		src = b :: buffer
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.zero, Vector2.new(s.W, s.H), src)
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
	if grade then
		if (grade :: Grade).lamps > 0 and (lightMap == nil or buffer.len(lightMap :: buffer) ~= s.W * s.H) then
			buildLight(s)
		end
		for y = y0, y1 do
			gradeSpan(s, y * s.W + x0, w, b, (y - y0) * w)
		end
	else
		for y = y0, y1 do
			buffer.copy(b, (y - y0) * w * 4, src, (y * s.W + x0) * 4, w * 4)
		end
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), b)
	end)
end

------------------------------------------------------------------ bake
-- Shadow edges on the pixel grid: every pixel whose sun visibility was copied from its 2x2 block's anchor and that
-- borders a pixel lit differently casts its own sun ray (and is shaded again), so a shadow's edge steps by single
-- pixels like everything else, never in 2 px blocks (mixels). Over a layer rect (inclusive); a pixel it changes can
-- reveal another edge, so it goes round twice. Returns the rays cast.
local function refineShadows(s: Surf, x0: number, y0: number, x1: number, y1: number): number
	local W, H = s.W, s.H
	x0, y0 = math.max(0, x0), math.max(0, y0)
	x1, y1 = math.min(W - 1, x1), math.min(H - 1, y1)
	if x0 > x1 or y0 > y1 then
		return 0
	end
	local share, lits, ids = s.sShare, s.sLit, s.sId
	local cam = s.cam
	local rays = 0
	for _ = 1, 2 do
		local changed = false
		for y = y0, y1 do
			local row = y * W
			for x = x0, x1 do
				local i = row + x
				if buffer.readu8(share, i) == 1 then
					local lit = buffer.readu8(lits, i)
					if lit <= 1 and buffer.readu16(ids, i * 2) ~= 0 then
						local edge = false
						for dy = -1, 1 do
							local ny = y + dy
							if ny >= 0 and ny < H and not edge then
								for dx = -1, 1 do
									local nx = x + dx
									if nx >= 0 and nx < W and (dx ~= 0 or dy ~= 0) then
										local j = ny * W + nx
										local nl = buffer.readu8(lits, j)
										if nl <= 1 and nl ~= lit and buffer.readu16(ids, j * 2) ~= 0 then
											edge = true
											break
										end
									end
								end
							end
						end
						if edge then
							local ox, oy, oz = Raster.origin(cam, x, y)
							local depth = buffer.readf32(s.sDepth, i * 4)
							local k = buffer.readu8(s.sNormal, i) + 1
							local pos = Vector3.new(ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth)
							local own = BakeCast.sunVisible(params, pos, Vector3.new(NX[k], NY[k], NZ[k]), SUN_V)
							rays += 1
							buffer.writeu8(share, i, 0)
							if own ~= lit then
								buffer.writeu8(lits, i, own)
								buffer.writeu32(s.sShade, i * 4, shadeAt(s, i, x, y))
								changed = true
							end
						end
					end
				end
			end
		end
		if not changed then
			break
		end
	end
	bakeRays += rays
	return rays
end

local function finishBake(s: Surf)
	baking = false
	buffer.fill(s.sShadowC, 0, 0)
	if tierSpec(tier).shadows then
		refineShadows(s, 0, 0, s.W - 1, s.H - 1)
	end
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
	lightStale = true
	table.clear(windSaved)
	table.clear(windWrote)
	windOn = nil
	table.clear(staticIds)
	table.clear(albedos)
	table.clear(waters)
	nextId = 1
	local cam = s.cam
	bakeRX0, bakeRY0 = cam.gx, cam.gy
	bakeRX1, bakeRY1 = cam.gx + s.W - 1, cam.gy + s.H - 1
	bakeOX, bakeOY = bakeRX0 - bakeRX0 % 4, bakeRY0 - bakeRY0 % 4
	bakeGX, bakeGY = bakeOX, bakeOY
	bakePass = 1
	baking = true
	invQueue = {}
	invCur = nil
end

-- The raycasts see only the static world: never the crew's rigs, never a player's character.
local function refreshExclude()
	if not excludeDirty then
		return
	end
	excludeDirty = false
	excluded = { dynFolder() }
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(excluded, pl.Character)
		end
	end
	params.FilterDescendantsInstances = excluded
end

-- A layer for the camera's view: buffers, image and a fresh bake (or the kept street picture when its view comes back).
local function buildSurf(v: CameraController.View)
	refreshExclude()
	lightStale = true
	local old = surf
	if old then
		windRestore(old) -- (the wind's paint off the layer going away: a kept street picture comes back clean)
	end
	if old and not baking and not old.view.stage and v.stage then
		-- a stage takes the view: keep the street's finished picture
		stash = { key = old.view.key, surf = old, ids = table.clone(staticIds), albedos = table.clone(albedos), waters = table.clone(waters), nextId = nextId, dirty = false }
	end
	local st = stash
	if st and not v.stage then
		stash = nil
		if st.key == v.key and not st.dirty and img and img.Size.X == st.surf.W and img.Size.Y == st.surf.H then
			surf = st.surf
			staticIds, albedos, waters, nextId = st.ids, st.albedos, st.waters, st.nextId
			baking = false
			invQueue = {}
			invCur = nil
			prevRects = {}
			needFull = true
			if image then
				image.Visible = true
				image.ImageTransparency = 0
			end
			return
		end
	end
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
	local px, py = CameraController.pan()
	local cam = Raster.gridCam(v.rot12, CameraController.gridAt(px, py), v.fullX, v.fullY, K, Tuning.CamRayBack)
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
		sShadowC = buffer.create(n * 4),
		sAlbedo = buffer.create(n * 4),
		sNormal = buffer.create(n),
		sLit = buffer.create(n),
		sDepth = sDepth,
		sId = sId,
		sShare = buffer.create(n),
		sWClass = buffer.create(n),
		sWave = buffer.create(n),
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

-- A static pixel shaded as if in the sun's shadow (a dynamic model's blob shadow), cached per pixel until the static
-- layer changes (a bake, a pan, a re-cast).
local function shadeShadowed(s: Surf, idx: number, x: number, y: number): number
	local cached = buffer.readu32(s.sShadowC, idx * 4)
	if cached ~= 0 then
		return cached
	end
	local a = buffer.readu32(s.sAlbedo, idx * 4)
	local c: number
	if a >= EMISSIVE then
		c = buffer.readu32(s.sShade, idx * 4)
	else
		local ni = buffer.readu8(s.sNormal, idx) + 1
		c = Shading.toonAt(a, NX[ni], NY[ni], NZ[ni], 0, x + s.cam.gx, y + s.cam.gy, Shading.OUTDOOR, 0)
	end
	buffer.writeu32(s.sShadowC, idx * 4, c)
	return c
end

-- The ground's screen-right and toward-the-viewer directions (unit, on the ground): the blob shadows' ellipse axes.
local GROUND_R, GROUND_D = Vector3.xAxis, Vector3.zAxis
do
	local rot = Raster.rotation(Tuning.CamYaw, Tuning.CamPitch)
	local r = Vector3.new(rot[4], 0, rot[10])
	local d = Vector3.new(rot[6], 0, rot[12])
	if r.Magnitude > 1e-6 then
		GROUND_R = r.Unit
	end
	if d.Magnitude > 1e-6 then
		GROUND_D = d.Unit
	end
end

-- A blob shadow under a dynamic model; returns its rect on the layer (nil when none shows).
local function drawShadow(s: Surf, model: Model, first: BasePart): Rect?
	local radius = model:GetAttribute("PixelShadow")
	if type(radius) ~= "number" or radius <= 0 then
		return nil
	end
	local g = model:GetAttribute("PixelGroundY")
	local ground = if type(g) == "number" then g else 0
	local pp = model.PrimaryPart or first
	local p = pp.Position
	local h = math.max(0, p.Y - ground)
	local r = radius * math.clamp(1 - h / 26, 0.45, 1)
	local cam = s.cam
	local cx, cy = Raster.project(cam, p.X, ground, p.Z)
	local ex = Raster.project(cam, p.X + GROUND_R.X * r, ground, p.Z + GROUND_R.Z * r)
	local _, ey = Raster.project(cam, p.X + GROUND_D.X * r, ground, p.Z + GROUND_D.Z * r)
	local rx, ry = math.abs(ex - cx), math.abs(ey - cy)
	if rx < 0.5 or ry < 0.5 then
		return nil
	end
	local W, H = s.W, s.H
	local f = s.frame
	local y0, y1 = math.max(0, math.floor(cy - ry)), math.min(H - 1, math.ceil(cy + ry))
	local any = false
	for y = y0, y1 do
		local dy = (y + 0.5 - cy) / ry
		if math.abs(dy) < 1 then
			local half = rx * math.sqrt(1 - dy * dy)
			local x0, x1 = math.max(0, math.floor(cx - half + 0.5)), math.min(W - 1, math.floor(cx + half + 0.5) - 1)
			for x = x0, x1 do
				local idx = y * W + x
				local id = buffer.readu16(f.id, idx * 2)
				-- the static picture only, never its ink lines or the sky
				if id ~= 0 and id < DYN_ID0 and (buffer.readu32(s.sColor, idx * 4) == buffer.readu32(s.sShade, idx * 4) or (buffer.readu8(s.sWClass, idx) ~= 0 and buffer.readu8(s.sWClass, idx) <= 3)) then
					buffer.writeu32(f.color, idx * 4, shadeShadowed(s, idx, x, y))
					any = true
				end
			end
		end
	end
	if not any then
		return nil
	end
	return { x0 = math.floor(cx - rx) - 1, y0 = y0 - 1, x1 = math.ceil(cx + rx) + 1, y1 = y1 + 1 }
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

------------------------------------------------------------------ water
-- A water pixel's colour at frame k: its baked shade, lit along a crest, darker in the sea's troughs, the foam
-- drawing back toward the shallows' colour now and then.
local function waterTone(cls: number, ph: number, k: number): number
	if cls == 3 then
		return if (ph + k * 3) % 32 < 20 then 0 else 3
	end
	local t = (ph + k * WATER_SPEED) % 64
	if t < 2 then
		return 1
	elseif cls == 1 and t >= 30 and t < 32 then
		return 2
	end
	return 0
end

-- `over` (0xRRGGBB) laid over a shaded pixel (packed as Shading.pack: red in the low byte, alpha on top) at `a`.
local function mixShaded(over: number, under: number, a: number): number
	local r = bit32.rshift(over, 16) * a + bit32.band(under, 0xFF) * (1 - a)
	local g = bit32.band(bit32.rshift(over, 8), 0xFF) * a + bit32.band(bit32.rshift(under, 8), 0xFF) * (1 - a)
	local b = bit32.band(over, 0xFF) * a + bit32.band(bit32.rshift(under, 16), 0xFF) * (1 - a)
	return Shading.pack(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5))
end

local function waterColor(base: number, cls: number, tone: number): number
	if tone == 0 then
		return base
	end
	local key = base * 16 + cls * 4 + tone
	local c = waterTones[key]
	if c == nil then
		if tone == 1 then
			c = mixShaded(WATER_CREST, base, if cls == 2 then 0.4 else 0.34)
		elseif tone == 2 then
			c = mixShaded(WATER_DEEP, base, 0.18)
		else
			c = mixShaded(WATER_SHALLOW, base, 0.55)
		end
		waterTones[key] = c
	end
	return c :: number
end

-- One water frame: every water pixel not under an ink line (its colour is its baked shade or last frame's) shaded
-- for the frame now; true when any changed.
local function animateWater(s: Surf): boolean
	local n = s.W * s.H
	local cls, wave, shade, color = s.sWClass, s.sWave, s.sShade, s.sColor
	local k = waterFrame
	local changed = false
	for i = 0, n - 1 do
		local c = buffer.readu8(cls, i)
		if c ~= 0 and c <= 3 then
			local base = buffer.readu32(shade, i * 4)
			local cur = buffer.readu32(color, i * 4)
			local ph = buffer.readu8(wave, i)
			if cur == base or cur == waterColor(base, c, waterTone(c, ph, k - 1)) then
				local nc = waterColor(base, c, waterTone(c, ph, k))
				if nc ~= cur then
					buffer.writeu32(color, i * 4, nc)
					changed = true
				end
			end
		end
	end
	return changed
end

------------------------------------------------------------------ the wind
-- Leaves sway and flags ripple without a ray: a canopy leans a pixel one way, rests, leans back, rests (about 2.7 s a
-- sway, the phase drifting slowly across the island): its edges (the outline and the leaf next to it) move a pixel
-- that way, the leading one out over what lies behind it (never over something nearer), the trailing one in, what
-- lay behind it showing a pixel further; a flag's columns hang a pixel lower in
-- the wave's crests and lift a pixel in its troughs (the lifted ones a fold darker). What the wind paints is undone
-- before the next frame, a scroll or a bake (`windRestore`).

local function animateWind(s: Surf, k: number): boolean
	local any = windRestore(s)
	local W, H = s.W, s.H
	local cls, wave, depth, color = s.sWClass, s.sWave, s.sDepth, s.sColor
	local function orig(i: number): number
		return windSaved[i] or buffer.readu32(color, i * 4)
	end
	local function put(i: number, c: number)
		windOn = s
		if windSaved[i] == nil then
			windSaved[i] = buffer.readu32(color, i * 4)
		end
		buffer.writeu32(color, i * 4, c)
		windWrote[i] = c
		any = true
	end
	for y = 1, H - 2 do
		local row = y * W
		for x = 1, W - 2 do
			local i = row + x
			local c = buffer.readu8(cls, i)
			if c == 4 then
				local g = (buffer.readu8(wave, i) + k * 3) % 48
				local dx = if g < 12 then 1 elseif g >= 24 and g < 36 then -1 else 0
				if dx ~= 0 then
					local t, b = i + dx, i - dx
					local d = buffer.readf32(depth, i * 4) + 0.5
					if buffer.readu8(cls, t) ~= 4 and buffer.readf32(depth, t * 4) > d then
						-- the leading edge: the outline moves out over what lies behind
						put(t, orig(i))
						if buffer.readu8(cls, b) == 4 then
							put(i, orig(b))
						end
					elseif buffer.readu8(cls, b) ~= 4 and buffer.readf32(depth, b * 4) > d and buffer.readu8(cls, t) == 4 then
						-- the trailing edge: what lies behind shows a pixel further in, the outline follows
						put(i, orig(b))
						put(t, orig(i))
					end
				end
			elseif c == 5 then
				local g = (buffer.readu8(wave, i) + k * 5) % 32
				local dy = if g < 12 then 1 elseif g >= 16 and g < 28 then -1 else 0
				if dy ~= 0 then
					local t = i + dy * W
					if buffer.readu8(cls, t) ~= 5 and buffer.readf32(depth, t * 4) > buffer.readf32(depth, i * 4) + 0.5 then
						put(t, orig(i))
						if buffer.readu8(cls, i - dy * W) == 5 then
							put(i, orig(i - dy * W))
						end
					elseif dy < 0 and buffer.readu8(cls, t) == 5 then
						-- a lifted column's fold, a shade darker
						put(i, mixShaded(0x2B1E2E, orig(i), 0.16))
					end
				end
			end
		end
	end
	return any
end

local function compose()
	local s = surf
	if s == nil then
		return
	end
	local t0 = os.clock()
	local cam = s.cam
	panX, panY = cam.gx, cam.gy
	local full = needFull
	if full then
		local n = s.W * s.H
		local f = s.frame
		buffer.copy(f.color, 0, s.sColor, 0, n * 4)
		buffer.copy(f.depth, 0, s.sDepth, 0, n * 4)
		buffer.copy(f.id, 0, s.sId, 0, n * 2)
		prevRects = {}
	else
		for _, r in prevRects do
			restoreRect(s, r)
		end
	end
	local rects: { Rect } = {}
	-- the blob shadows first (on the static picture), then the models over them
	for model, d in dyns do
		local first = d.parts[1]
		if model.Parent ~= nil and first ~= nil and model:GetAttribute("PixelShadow") ~= nil then
			local r = drawShadow(s, model, first.part)
			if r then
				table.insert(rects, r)
			end
		end
	end
	local drawn = 0
	for model, d in dyns do
		if model.Parent == nil then
			continue
		end
		-- off the layer: skip it (one projected point: its first part)
		local first = d.parts[1]
		if first == nil then
			continue
		end
		local fp = first.part.Position
		local fx, fy = Raster.project(cam, fp.X, fp.Y, fp.Z)
		if fx < -CULL or fy < -CULL or fx > s.W + CULL or fy > s.H + CULL then
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
	if full then
		needFull = false
		uploadAll(s)
	else
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
	end
	prevRects = rects
	stats.ticks += 1
	stats.composeMs = (os.clock() - t0) * 1000
end

------------------------------------------------------------------ pans
-- Shift a buffer of W x H elements of e bytes so that new (x, y) = old (x + dx, y + dy) (rows overlap: buffer.copy
-- moves overlapping bytes correctly).
local function shift(b: buffer, W: number, H: number, e: number, dx: number, dy: number)
	local w = W - math.abs(dx)
	if w <= 0 or math.abs(dy) >= H then
		return
	end
	local sx, tx = math.max(0, dx), math.max(0, -dx)
	if dy >= 0 then
		for y = 0, H - 1 - dy do
			buffer.copy(b, (y * W + tx) * e, b, ((y + dy) * W + sx) * e, w * e)
		end
	else
		for y = H - 1, -dy, -1 do
			buffer.copy(b, (y * W + tx) * e, b, ((y + dy) * W + sx) * e, w * e)
		end
	end
end

-- Cast every pixel of a layer rect (inclusive) by the bake's last pass: the 2x2 anchors first, then the pixels that
-- share their sun rays. Returns the rays cast.
local function castRect(s: Surf, x0: number, y0: number, x1: number, y1: number): number
	x0, y0 = math.max(0, x0), math.max(0, y0)
	x1, y1 = math.min(s.W - 1, x1), math.min(s.H - 1, y1)
	if x0 > x1 or y0 > y1 then
		return 0
	end
	local shadows = tierSpec(tier).shadows
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local before = bakeRays
	for phase = 1, 2 do
		for y = y0, y1 do
			local gy = y + gy0
			for x = x0, x1 do
				local gx = x + gx0
				local anchor = gx % 2 == 0 and gy % 2 == 0
				if anchor == (phase == 1) then
					castSample(s, gx, gy, gx, gy, false, shadows)
				end
			end
		end
	end
	-- the rect's shadow edges (and its border's, which may meet a changed pixel) on the pixel grid
	if shadows then
		refineShadows(s, x0 - 1, y0 - 1, x1 + 1, y1 + 1)
	end
	return bakeRays - before
end

-- The ink and the contact shade over a layer rect and one pixel round it.
local function reoutline(s: Surf, x0: number, y0: number, x1: number, y1: number)
	Shading.outline(s.static, x0 - 1, y0 - 1, x1 + 1, y1 + 1, s.sShade)
	contactPass(s, x0 - 1, y0 - 1, x1 + 1, y1 + 1)
end

-- Scroll the layer toward the pan (tx, ty): by whole art px, the uncovered strips cast, within the frame's ray budget.
local function scrollToward(s: Surf, tx: number, ty: number)
	local cam = s.cam
	local dx, dy = tx - cam.gx, ty - cam.gy
	if dx == 0 and dy == 0 then
		return
	end
	windRestore(s)
	local W, H = s.W, s.H
	local v = s.view
	if math.abs(dx) >= W // 2 or math.abs(dy) >= H // 2 then
		-- a jump (the view sent home from the far end of the street): bake again at the new pan
		s.cam = Raster.gridCam(v.rot12, CameraController.gridAt(tx, ty), v.fullX, v.fullY, s.K, Tuning.CamRayBack)
		startBake()
		return
	end
	-- the step this frame: the strips' rays within the budget (a strip pixel costs about 1.5 rays with its sun ray)
	local budget = Tuning.PixelPanRays
	local mx = math.max(1, math.floor(budget / (H * 1.5)))
	local my = math.max(1, math.floor(budget / (W * 1.5)))
	local sx, sy = math.clamp(dx, -mx, mx), math.clamp(dy, -my, my)
	for _, b in { s.sColor, s.sShade, s.sAlbedo, s.sDepth } do
		shift(b, W, H, 4, sx, sy)
	end
	shift(s.sNormal, W, H, 1, sx, sy)
	buffer.fill(s.sShadowC, 0, 0)
	shift(s.sLit, W, H, 1, sx, sy)
	shift(s.sId, W, H, 2, sx, sy)
	shift(s.sShare, W, H, 1, sx, sy)
	shift(s.sWClass, W, H, 1, sx, sy)
	shift(s.sWave, W, H, 1, sx, sy)
	-- the lamps' pools move with the picture (the strips coming in are dark until the next rebuild adds their lamps)
	local lm = lightMap
	if lm and buffer.len(lm) == W * H then
		shift(lm, W, H, 1, sx, sy)
		if sx > 0 then
			for y = 0, H - 1 do
				buffer.fill(lm, y * W + W - sx, 0, sx)
			end
		elseif sx < 0 then
			for y = 0, H - 1 do
				buffer.fill(lm, y * W, 0, -sx)
			end
		end
		if sy > 0 then
			buffer.fill(lm, (H - sy) * W, 0, sy * W)
		elseif sy < 0 then
			buffer.fill(lm, 0, 0, -sy * W)
		end
	end
	s.cam = Raster.gridCam(v.rot12, CameraController.gridAt(cam.gx + sx, cam.gy + sy), v.fullX, v.fullY, s.K, Tuning.CamRayBack)
	local rays = 0
	local strips: { Rect } = {}
	if sx > 0 then
		table.insert(strips, { x0 = W - sx, y0 = 0, x1 = W - 1, y1 = H - 1 })
	elseif sx < 0 then
		table.insert(strips, { x0 = 0, y0 = 0, x1 = -sx - 1, y1 = H - 1 })
	end
	local cx0, cx1 = if sx > 0 then 0 else -sx, if sx > 0 then W - sx - 1 else W - 1
	if sy > 0 then
		table.insert(strips, { x0 = cx0, y0 = H - sy, x1 = cx1, y1 = H - 1 })
	elseif sy < 0 then
		table.insert(strips, { x0 = cx0, y0 = 0, x1 = cx1, y1 = -sy - 1 })
	end
	for _, r in strips do
		rays += castRect(s, r.x0, r.y0, r.x1, r.y1)
	end
	for _, r in strips do
		reoutline(s, r.x0, r.y0, r.x1, r.y1)
	end
	stats.scrolls += 1
	stats.scrollRays += rays
	needFull = true
	lightStale = true
end

------------------------------------------------------------------ invalidation
-- The global art px rect a part and its sun shadow on the lawn cover (nil when the view has none yet).
local function partRect(part: BasePart): Rect?
	local v = CameraController.view()
	local cf, size = part.CFrame, part.Size / 2
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	local sun = SUN_V
	local ground = Street.WATER_Y -- the lowest ground a shadow lands on (the sea), so the rect holds it wherever it falls
	for _, sxk in { -1, 1 } do
		for _, syk in { -1, 1 } do
			for _, szk in { -1, 1 } do
				local p = cf:PointToWorldSpace(Vector3.new(size.X * sxk, size.Y * syk, size.Z * szk))
				local gx, gy = Raster.gridPoint(v.rot12, v.grid, p.X, p.Y, p.Z)
				x0, y0, x1, y1 = math.min(x0, gx), math.min(y0, gy), math.max(x1, gx), math.max(y1, gy)
				if p.Y > ground then
					local t = (p.Y - ground) / sun.Y
					local q = p - sun * t
					local qx, qy = Raster.gridPoint(v.rot12, v.grid, q.X, q.Y, q.Z)
					x0, y0, x1, y1 = math.min(x0, qx), math.min(y0, qy), math.max(x1, qx), math.max(y1, qy)
				end
			end
		end
	end
	if x0 > x1 then
		return nil
	end
	return { x0 = math.floor(x0) - 2, y0 = math.floor(y0) - 2, x1 = math.ceil(x1) + 2, y1 = math.ceil(y1) + 2 }
end

local function queueRect(r: Rect)
	lightStale = true
	local s = surf
	if s == nil then
		return
	end
	-- only what is on the layer (a rect off it is cast when a pan uncovers it)
	local gx0, gy0 = s.cam.gx, s.cam.gy
	if r.x1 < gx0 or r.y1 < gy0 or r.x0 > gx0 + s.W - 1 or r.y0 > gy0 + s.H - 1 then
		return
	end
	table.insert(invQueue, r)
	local area = 0
	for _, q in invQueue do
		area += (math.min(q.x1, gx0 + s.W - 1) - math.max(q.x0, gx0) + 1) * (math.min(q.y1, gy0 + s.H - 1) - math.max(q.y0, gy0) + 1)
	end
	if area > s.W * s.H * REBAKE_SHARE then
		-- a big change (a new office): bake again, behind the old picture
		rebakeAt = os.clock() + 0.5
		invQueue = {}
		invCur = nil
	end
end

-- Re-cast queued rects within the frame's ray budget. A rect's pixels are cast exactly by the bake's rule; once a
-- rect is done its ink and contact shade are drawn again and the frame takes the new pixels.
local function processInvalidation()
	local s = surf
	if s == nil then
		return
	end
	local budget = Tuning.PixelInvalidateRaysFrame
	local start = bakeRays
	while bakeRays - start < budget do
		local cur = invCur
		if cur == nil then
			local r = table.remove(invQueue, 1)
			if r == nil then
				return
			end
			cur = { r = r, phase = 1, gx = r.x0, gy = r.y0 }
			invCur = cur
		end
		local c = cur :: { r: Rect, phase: number, gx: number, gy: number }
		local r = c.r
		local shadows = tierSpec(tier).shadows
		local gx0, gy0 = s.cam.gx, s.cam.gy
		while c.phase <= 2 and bakeRays - start < budget do
			local gx, gy = c.gx, c.gy
			local x, y = gx - gx0, gy - gy0
			if x >= 0 and y >= 0 and x < s.W and y < s.H and ((gx % 2 == 0 and gy % 2 == 0) == (c.phase == 1)) then
				castSample(s, gx, gy, gx, gy, false, shadows)
			end
			c.gx += 1
			if c.gx > r.x1 then
				c.gx = r.x0
				c.gy += 1
				if c.gy > r.y1 then
					c.gy = r.y0
					c.phase += 1
				end
			end
		end
		if c.phase > 2 then
			reoutline(s, r.x0 - gx0, r.y0 - gy0, r.x1 - gx0, r.y1 - gy0)
			buffer.fill(s.sShadowC, 0, 0)
			invCur = nil
			stats.recasts += 1
			needFull = true
		end
	end
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
	refreshExclude()
	if baking then
		-- a stage bakes behind the play overlay's curtain: faster
		local budget = Tuning.PixelBakeMsPerFrame + (if shown then 0 else 8) + (if surf and surf.view.stage then Tuning.PixelStageBakeMs else 0)
		bakeSome(os.clock() + budget / 1000)
		return
	end
	local s = surf
	if s then
		local tx, ty = CameraController.pan()
		scrollToward(s, tx, ty)
		if baking then
			return -- a jump started a bake
		end
		processInvalidation()
	end
	-- the water's frames (not on the low tier): a changed frame is copied and uploaded whole by the next compose
	if s and tier ~= "low" then
		waterClock += dt
		if waterClock >= 1 / WATER_HZ then
			waterClock = 0
			waterFrame += 1
			if animateWater(s) then
				needFull = true
			end
			if animateWind(s, waterFrame) then
				needFull = true
			end
		end
	end
	local hz = tierSpec(tier).hz
	tickAcc += dt
	if tickAcc >= 1 / hz or needFull then
		tickAcc = 0
		compose()
	end
end

local function watchStatic()
	-- a part that comes or goes anywhere on the street (decor placed, a neighbour's studio built or gone) re-casts
	-- the rect it and its shadow cover (a big change re-bakes the layer behind the old picture)
	local plots = workspace:WaitForChild("Plots", 30)
	if plots == nil then
		return
	end
	local function poke(d: Instance)
		if not d:IsA("BasePart") or surf == nil then
			return
		end
		if CameraController.view().stage then
			-- the street is not on screen: its kept picture is out of date
			local st = stash
			if st then
				st.dirty = true
			end
			return
		end
		local r = partRect(d)
		if r then
			queueRect(r)
		end
	end
	plots.DescendantAdded:Connect(poke)
	plots.DescendantRemoving:Connect(function(d: Instance)
		poke(d)
		staticIds[d] = nil
	end)
end

-- Characters come and go: the bake's filter follows.
local function watchCharacters()
	local function hook(pl: Player)
		pl.CharacterAdded:Connect(function()
			excludeDirty = true
		end)
		pl.CharacterRemoving:Connect(function()
			excludeDirty = true
		end)
	end
	for _, pl in Players:GetPlayers() do
		hook(pl)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function()
		excludeDirty = true
	end)
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
	watchCharacters()
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
			local glow = d.Material == Enum.Material.Neon
			dynGlow[nextDyn] = glow
			table.insert(parts, { part = d, id = nextDyn, shape = shape, glow = glow, rgb = rgb })
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
			dynGlow[p.id] = p.glow
		end
	end
end

-- Whether the picture of the camera's view now is finished (a stage's bake done; always true in the classic style).
function PixelRenderer.ready(): boolean
	if tier == "off" then
		return true
	end
	local s = surf
	return s ~= nil and not baking and s.view.key == CameraController.view().key
end

-- The layer shifted by whole art px (a hit's jolt on a minigame's stage); 0, 0 puts it back.
function PixelRenderer.setOffset(dx: number, dy: number)
	offX, offY = math.floor(dx + 0.5), math.floor(dy + 0.5)
	local im = image
	if im then
		local K = if surf then (surf :: Surf).K else CameraController.pixelK()
		im.Position = UDim2.fromOffset(offX * K, offY * K)
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

-- The pick ray through a screen point (pos = InputObject.Position, below the top bar): origin and direction * length,
-- through what the layer shows (its own camera, the pan it shows) when the filter is on, the Roblox camera's otherwise.
function PixelRenderer.screenRay(pos: Vector2): (Vector3, Vector3)
	local inset = GuiService:GetGuiInset()
	local x, y = pos.X + inset.X, pos.Y + inset.Y
	local s = surf
	if s and tier ~= "off" then
		local cam = s.cam
		local i = math.clamp(math.floor((x + cam.offX) / cam.K), 0, cam.W - 1)
		local j = math.clamp(math.floor((y + cam.offY) / cam.K), 0, cam.H - 1)
		local ox, oy, oz = Raster.origin(cam, i, j)
		return Vector3.new(ox, oy, oz), Vector3.new(cam.lx, cam.ly, cam.lz) * FAR
	end
	local cam = workspace.CurrentCamera
	if cam == nil then
		return Vector3.zero, Vector3.new(0, -PICK_LEN, 0)
	end
	local ray = cam:ViewportPointToRay(x, y)
	return ray.Origin, ray.Direction.Unit * PICK_LEN
end

-- The art pixel (i, j) of the top-left grid that shows a world point (UI on a pixel canvas), and whether on screen.
function PixelRenderer.projectPixel(world: Vector3): (number, number, boolean)
	local pos, on = PixelRenderer.project(world)
	local k = PixelRenderer.pixelScale()
	return math.floor(pos.X / k), math.floor(pos.Y / k), on
end

-- The time of day's grade (UI/DayLight; nil: daylight as baked). A changed grade re-uploads the whole picture.
function PixelRenderer.setGrade(g: Grade?)
	local key = if g then string.format("%.2f %.2f %.2f %.0f %.2f %.2f", g.mr, g.mg, g.mb, g.lift, g.sat, g.lamps) else ""
	if key == gradeKey then
		return
	end
	gradeKey = key
	grade = g
	table.clear(gradeMap)
	needFull = true
end

-- Sims and previews: the grade now ("" by day).
function PixelRenderer.debugGrade(): string
	return gradeKey
end

-- CLI checks only: the layer, its bake and what the ticks cost.
function PixelRenderer.debugStatic(): { W: number, H: number, K: number, baking: boolean, shown: boolean, color: buffer?, rays: number, bakes: number, ticks: number, composeMs: number, dyn: number, px: number, py: number, scrolls: number, scrollRays: number, recasts: number, queued: number }
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
		px = if s then s.cam.gx else 0,
		py = if s then s.cam.gy else 0,
		scrolls = stats.scrolls,
		scrollRays = stats.scrollRays,
		recasts = stats.recasts,
		queued = #invQueue + (if invCur then 1 else 0),
	}
end

-- (Palette is read so the LUT carries the office themes' colours.)
Shading.setPalette(Shading.defaultColors())
Shading.setMode("day")
local _ = Palette

return PixelRenderer
