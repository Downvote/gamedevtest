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
--     inside the office) with its material's surface texture (wood grain, grass blades, sand and stone specks, thatch,
--     brick courses, a metal or glass streak: 1 px marks a band darker or lighter, no rays; the surface textures
--     section), then the 1 px ink outline where parts meet and a contact shade at the foot of upright faces.
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
-- A stage (CameraController.setStage: the hatch scene's, UI/HatchScene) is a view of its own, baked with a bigger
-- budget a frame; the street's finished picture is kept aside meanwhile and comes back at once when the stage closes
-- (baked again only if a part under Workspace.Plots came or went in between). An empty stage (Stage.empty: nothing
-- static on it, the hatch scene's) is not baked at all: its picture is empty and ready at once. A stage with a see-through sky (Stage.clear) leaves the pixels its rays miss empty (alpha 0, never graded
-- or dimmed), so a picture behind the layer (the hatch scene's painted backdrop) shows round what stands there. A dynamic
-- model with a "PixelShadow" attribute (a radius in studs) casts a blob shadow on the static picture under it (on
-- the ground at its "PixelGroundY", default 0): the pixels there are shaded as in the sun's shadow, so it lands on the
-- palette's own shadow tones, smaller the higher the model is (none when it is hidden or below its ground).
-- Water: a part with a "PixelWater" attribute (1 the sea, 2 the shallows, 3 the foam) marks its pixels in the bake
-- with that class and a wave phase from the hit point's world position (sWClass, sWave: they scroll with the
-- picture). WATER_HZ times a second (not on the low tier) the water pixels not under an ink line are shaded again
-- from their baked shade: crests of light (and the sea's darker troughs) travel across the sea and the shallows along
-- the phase's wavy lines, and the foam laps in and out along the shore. Only colours change: no ray is cast.
-- Effects (addFxLayer; Render/Fx): drawn every tick over the dynamic models and their outline, depth-tested, colour
-- only (a light's pixel also takes Fx.GLOW_ID, which the night's grade leaves alone). The pixels they wrote go back to
-- the static picture on the next tick; only the pixels whose colour changed since the image last showed them are
-- uploaded, in runs of 16 x 8 tiles (a tuft at rest costs nothing). Controllers/AmbientView draws the islands' small
-- lives this way. They pause with the renderer and run at its tick rate.
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
local SmoothParts = require(script.Parent.SmoothParts)
local Fx = require(ReplicatedStorage.Shared.Render.Fx)
local DynTex = require(ReplicatedStorage.Shared.Render.DynTex)
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
-- The founders' white outline (registerDynamic outline "self" / "player"; the request of 2026-11-14: "make the player be
-- outlined white like the bakery game"): Random Bakery's rim. Each founder's whole silhouette, hidden parts too, is drawn
-- again flat into a scratch window of its own rect (Raster.window), and Shading.rim lays a 1 px white line on its edge
-- pixels over the ink one, dotted where something nearer hides that part of it (x-ray), so a founder behind a tree still
-- shows. At most Rims.max (8) a tick: the own founder first, then the nearest to the layer's middle.
local PICK_LEN = 2000
local REBAKE_SHARE = 0.33 -- invalidated rects covering more of the layer than this re-bake it whole
local WATER_HZ = 6 -- the water's frames a second
local WATER_SPEED = 2 -- phase units a frame (a crest every 64 units: about 10 studs)
local WATER_CREST = 0xCDF7F0 -- a crest's light aqua (0xRRGGBB)
local WATER_DEEP = 0x1C6272 -- (turquoise, like the sea: Data/Palette)
local WATER_SHALLOW = Palette.colors.shallow

local NX: { number } = {}
local NY: { number } = {}
local NZ: { number } = {}
for i = 0, 255 do
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
	ready: boolean?, -- a finished bake is in its buffers (a re-bake then works behind it: `back`)
	-- the screen's window of the layer: the margin kept round it (art px; 0 on a stage), its size, and where it stands in
	-- the layer now (showWindow: CameraController.pan less the layer's top-left)
	m: number,
	vw: number,
	vh: number,
	ox: number,
	oy: number,
}

-- A static part's surface texture (Shading.TEX_*), worked out once per part and id table: its colour (a pixel tinted
-- by glass in front shows none), its screen box in global art px, how its long axis runs on screen (Shading.grain's
-- fam) and a number from where it stands. NO_TEX: a part with none.
type TexInfo = { kind: number, rgb: number, x0: number, y0: number, w: number, h: number, fam: number, seed: number }
type Texs = { [number]: TexInfo }
local NO_TEX: TexInfo = table.freeze({ kind = 0, rgb = -1, x0 = 0, y0 = 0, w = 0, h = 0, fam = 0, seed = 0 })

-- a painted eye (Render/EyeTex): its style's code, its colours (0xRRGGBB) and its side
type EyeSpec = { code: number, iris: number, dark: number, lid: number, side: number }
type DynPart = { part: BasePart, id: number, shape: string, glow: boolean, rgb: number, tex: number, texV: number, texSeed: number?, texSoft: number, sm: number, prm: number?, eye: EyeSpec?, blend: number?, paint: { a: Vector3, b: Vector3, n: Vector3 }? }
-- rim: a founder (registerDynamic outline "self" or "player"): a white rim in place of its ink edge (GAME_DESIGN 14.1);
-- own: the local player's (drawn first when there are more than Rims.max)
-- A moving model's picture last time it was drawn (DynCache in the compose section): its pixels that won against the
-- static picture (dx, dy from the global art px (gx, gy), colour, depth, id: PX_BYTES each), its parts as they stood
-- then, the static picture's epoch (SG.ver) and the scale. cache false: never kept (its ids wrap round).
-- shp: where the model's blob shadow is cast from as it was drawn (its PrimaryPart's position; nil: it cast none), so
-- the shadow shown with a kept picture is the picture's, not the live model's.
type DynCache = { gx: number, gy: number, w: number, h: number, n: number, px: buffer, cfs: { CFrame }, szs: { Vector3 }, gone: { boolean }, ver: number, ppu: number, shp: Vector3?, anchor: Vector3?, from: DynCache? }
-- (what it shows since the last compose, for the incremental compose: shC the kept picture put down, nil when it was
-- drawn and not kept; shR its rect a pixel round, in global art px; sx, sy, srx, sry its blob shadow's centre (global
-- art px) and radii, sR the shadow's rect (global); sChg, sIn whether this compose draws the shadow because it changed
-- or because a changed tile meets it)
type Dyn = {
	model: Model,
	parts: { DynPart },
	rim: boolean?,
	own: boolean?,
	smooth: boolean?,
	lo: number,
	hi: number,
	cache: DynCache?,
	drawnAt: number?,
	shC: DynCache?,
	shR: Rect?,
	shDz: number?,
	gNow: Vector3?,
	gPosed: Vector3?,
	sx: number?,
	sy: number?,
	srx: number?,
	sry: number?,
	sR: Rect?,
	sChg: boolean?,
	sIn: boolean?,
	lead: number?, -- studs nearer than it stands when put down on the frame (its "PixelLead" attribute)
	-- (PixelRenderer.pose: the pose it says it is in, its pictures kept by pose (at most POSE_KEEP, the oldest going
	-- first) and the order they came in)
	poseKey: string?,
	poses: { [string]: DynCache }?,
	poseOrder: { string }?,
}
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
-- the bake's finishing passes, a band of rows at a time once every pixel is cast (bakePass 4): 1 the sun's rays at the
-- shadows' edges, 2 the ink outline and the contact shade; bakeFinY the next band's first row
local bakeFin, bakeFinY = 0, 0
local FIN_ROWS = 12
local bakeRays = 0
local rebakeAt = -1 -- SG.clock() when a pending re-bake starts (debounce)
local preReset: () -> () = function() end -- (the next tier's pre-cast forgotten: set below, where it is kept)
local rush = false -- a big change's re-bake: more ms a frame (the player is waiting to see it)
-- A re-bake while a finished picture is on screen writes into these (fresh buffers and id tables) instead, so the
-- picture keeps living meanwhile (the crew, driftlings, water and wind go on drawing over it at its camera); the
-- finished bake swaps in whole. Without it the screen stood still for the whole bake: the lag before an expansion.
type BackTabs = { ids: { [Instance]: number }, albedos: { [number]: number }, waters: { [number]: number }, texs: Texs, nextId: number }
local back: Surf? = nil
local backTabs: BackTabs? = nil
local afterBake: { () -> () } = {} -- called once when the next bake is on screen (PixelRenderer.afterBake)
-- (The island no longer grows into its next tier on the picture: the request of 2026-11-19, "Expansion is very slow and
-- laggy, especially at higher levels. Is it possible to optimize and speed it up? No need for the transition anymore".
-- The land's chunks that changed come and go like any part, re-cast where they show.)

local staticIds: { [Instance]: number } = {}
local albedos: { [number]: number } = {}
local waters: { [number]: number } = {} -- static id -> PixelWater class (0 none)
local texs: Texs = {} -- static id -> its surface texture (worked out when the bake first meets it)
local waterClock, waterFrame = 0, 0
local waterTones: { [number]: number } = {} -- (base colour, class, tone) -> colour
local nextId = 1

local dyns: { [Model]: Dyn } = {}
local nextDyn = DYN_ID0
local dynGlow: { [number]: boolean } = { [Fx.GLOW_ID] = true } -- dynamic part id -> Neon (it stays lit at night)
local prevRects: { Rect } = {}
local tickAcc = 0
-- (`perf`: where a frame's time goes, ms summed since the last read: debugPerf; previews measure a walk with it)
local stats = {
	ticks = 0,
	rays = 0,
	bakes = 0,
	composeMs = 0,
	scrolls = 0,
	scrollRays = 0,
	recasts = 0,
	perf = { frames = 0, panFrames = 0, invMs = 0, invFinMs = 0, pokeMs = 0, pokes = 0, preMs = 0, scrollMs = 0, composeMs = 0, uploadMs = 0, gradeMs = 0, stepMs = 0, uploads = 0, regrades = 0, castMs = 0, inkMs = 0, dynMs = 0, outlineMs = 0, rimMs = 0, fxMs = 0, waterMs = 0, windMs = 0, copyMs = 0, maxMs = 0, slow = 0, incFrames = 0, incPx = 0, fullFrames = 0 },
}
local staticVer = 0 -- bumped whenever the static picture changes (a bake, a scroll, a re-cast): Fx.Ctx.ver
-- Sticky effect pixels (Fx.stickSprite): small things that stay put on the picture (the lawn's tufts) are kept here and
-- put back over the static picture wherever the frame takes it back (a model's rect restored, a full compose, last
-- tick's effects undone), so they are drawn once and again only when they change. A change to the static picture
-- drops them all (Fx.Ctx.ver changes: their owner sticks them again).
local stickCol: buffer? = nil -- u32 a layer pixel: the colour stuck there (0: none)
local stickList: { number } = {} -- the pixels stuck (one unstuck stays listed until the list is rebuilt)
local stickLive = 0
local stickDirty: { number } = {} -- pixels stuck or unstuck since the last compose (their tiles go up)

-- The static picture changed: what was worked out from it is stale and the sticky pixels go. (Every caller uploads the
-- whole picture next.)
local function staticChanged()
	staticVer += 1
	local sc = stickCol
	if sc then
		local len = buffer.len(sc)
		for _, i in stickList do
			if i * 4 < len then
				buffer.writeu32(sc, i * 4, 0)
			end
		end
	end
	table.clear(stickList)
	table.clear(stickDirty)
	stickLive = 0
end
local needFull = false -- the next compose copies the whole static layer and uploads the whole image
-- invalidated rects in global art px, and the one being re-cast (its cursor: phase 1 anchors, phase 2 the rest)
-- phase 1 and 2: the cast (anchors, then the rest); 3: the shadow edges refined, 4: the ink and contact shade, each in
-- bands of FIN_ROWS rows from global row fy; 5: done
type InvCur = { r: Rect, phase: number, gx: number, gy: number, fy: number }
local invQueue: { Rect } = {}
local invCur: InvCur? = nil

-- the island's finished picture, kept while a stage (the hatch scene's) has the view and put back when its key comes
-- back; `dirty`: out of date (a bake was going on behind it or was due, or a part came or went meanwhile), so it is
-- baked again behind the picture then; `inv`, `cur`: the rects still to cast again on it
type Stash = { key: string, surf: Surf, ids: { [Instance]: number }, albedos: { [number]: number }, waters: { [number]: number }, texs: Texs, nextId: number, dirty: boolean, inv: { Rect }, cur: InvCur? }
local stash: Stash? = nil

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
	texs[nid] = nil -- (worked out afresh for the part that has the id now)
	local attr = part:GetAttribute("PixelColor")
	local rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(part.Color)
	if part.Material == Enum.Material.Neon then
		rgb += EMISSIVE
	end
	albedos[nid] = rgb
	local wk = part:GetAttribute("PixelWater")
	-- (PixelWater 4: falling water, class 6: streaks running down it)
	waters[nid] = if wk == 4 then 6 elseif type(wk) == "number" then wk else 0
	-- (no wind classes since 2026-11-20: "no need to add rustling to the tree and other objects anymore, these cause
	-- broken outlines"; leaves and flags hold still)
	return nid
end

-- The static picture graded (the grade section): the time of day's grade, the spotlight's dim and the lamps' pools
-- over sColor, kept in step with it so a whole upload copies it and grades only what is drawn over it (the dynamic
-- rects, the effects' pixels, the stuck ones). The request of 2026-11-15: "the camera moving is always very laggy":
-- every pan used to grade the whole picture again, pixel by pixel. ok: buf matches sColor, sId and the lamps' pools
-- of layer `on` under the grade now. Whatever changes them grades its own pixels again (a pan shifts buf and grades
-- the strips it uncovers, a re-cast rect, the water's and the wind's pixels) or clears ok (a bake,
-- a new grade, the pools built again: the next upload grades it all).
local SG = {
	-- (the pan cache, Pixel/PanCache: a pan's strips that were on screen before are copied back, not cast again)
	Tiles = require(script.Parent.PanCache),
	exclVer = 0, -- (refreshExclude's count: the pre-cast's filter follows it)
	panAt = -1, -- SG.clock() of the view's last pan (SG.keep keeps a moving model's picture while one goes on)
	need = {} :: { Dyn }, -- (a compose's models to draw afresh, in their order)
	-- (the water's tone tables, and whether its next frame shades every water pixel: SG.waterSlice)
	waterWas = table.create(7 * 256, 0) :: { number },
	waterNow = table.create(7 * 256, 0) :: { number },
	waterAll = true,
	waterGrade = {} :: { [number]: number }, -- (a water colour and part -> its graded colour, under the grade named by waterGradeKey)
	waterGradeKey = "",
	-- (the water's next frame worked out a slice at a time: SG.waterSlice; the slices done this period, the pending
	-- pixels as global x, global y, colour now, colour next, and whether this period shades every water pixel)
	WATER_SLICES = 8,
	waterDone = 0,
	waterPend = {} :: { number },
	waterPendN = 0,
	waterAllNow = false,
	-- (the wind's frame, kept empty: the wind's pass went on 2026-11-20, the resets that clear these stay harmless)
	windPend = {} :: { [number]: number },
	windDone = 0,
	windVoid = false,
	-- (a driftling's painted eyes: Render/EyeTex, the eye being drawn, its shade: kept here, not as locals of their
	-- own, for the module's top-level local limit)
	EyeTex = require(ReplicatedStorage.Shared.Render.EyeTex),
	eyeOpt = { code = 1, iris = 0, dark = 0, lid = 0, white = 0xF4F4F4, side = 1, hx = 0.1, hy = 0.1 },
	shadeEye = nil :: Raster.Shade?,
	-- (the smooth solids pieces can lie on, by shape: Render/Smooth.packSolid's kinds)
	solidKind = { Ell = 1, Egg = 2, EggBot = 4, EggTop = 5 } :: { [string]: number },
	-- (a model's body drawn as one blended surface, Raster.drawBlend: its members this frame, their parts and frames,
	-- the member whose texture is set up, and the shade that sets it)
	blendM = {} :: { Raster.BlendMember },
	blendP = {} :: { any },
	blendCf = {} :: { { number } },
	blendLast = 0,
	blendTex = false,
	shadeMember = nil :: Raster.BlendShade?,
	-- (a model's marks painted on this frame, Kit.blush: per mark PAINT_STRIDE numbers, its centre, its oval's three
	-- scaled axes in world, its colour, its edge's scale and its reach; how many; whether the part being drawn is near
	-- one; each blend member's; the paint, and a plain shade that paints)
	paints = {} :: { number },
	paintN = 0,
	paintOn = false,
	blendPaint = {} :: { boolean },
	paintAt = nil :: ((rgb: number, x: number, y: number, t: number) -> number)?,
	shadePaint = nil :: Raster.Shade?,
	buf = nil :: buffer?,
	out = nil :: buffer?, -- (the whole image graded, as it goes up)
	on = nil :: Surf?,
	ok = false,
	ver = 0, -- the static picture's epoch: bumped whenever it changes other than by a pan (a model's kept picture is good within one)
	dynAcc = 0, -- seconds since the moving models were last all due (they redraw at the tier's hz, panning or not)
	off = false, -- (debugKeepCheck: every model drawn afresh)
	quiet = false, -- (debugKeepCheck: the effects left out of a compose)
	hits = 0, -- (kept pictures used, models drawn afresh: debugPerf)
	draws = 0,
	seq = 0, -- (bumped by every compose and every rect upload: debugGradeCheck)
	fullAt = -1, -- (seq when the whole image last went up graded)
	-- (the clock the frame's budgets and the timings read: os.clock; a preview walking the world at a fixed 60 frames a
	-- second hands its real clock in: PixelRenderer.debugClock)
	clock = os.clock,
	iso = nil :: Raster.Frame?,
	ISO_M = 96,
	isoCam = nil :: Raster.Cam?,
	isoOf = nil :: Raster.Cam?,
	farRow = nil :: buffer?,
	none = buffer.create(0),
	-- (the incremental compose: the layer's tiles to draw again, TILE art px square, a byte each, and their columns and
	-- rows; global art px rects to draw again at the next compose; the frame as it stood before the effects, and the
	-- layer it belongs to; whether this frame composes because the water or the wind changed what shows, whether a pan
	-- shifted the frame, whether the whole image goes up; a debug check's draws without a budget, the models drawn
	-- past the rect worked out for them (none, unless a part reaches past its box), the check armed and its last
	-- result; a compose's changed models, unchanged ones, blob shadows and kept pictures to put down)
	TILE = 4,
	bits = buffer.create(0),
	tcols = 0,
	trows = 0,
	dirty = {} :: { Rect },
	base = nil :: { color: buffer, id: buffer }?,
	incOn = nil :: Surf?,
	touch = false,
	panned = false,
	upWhole = false,
	noBudget = false,
	incArm = false,
	incResult = { off = -1, checked = 0, px = 0 },
	snap = false,
	markBy = {} :: { [string]: number }, -- (tiles each source marked, since the last debugPerf)
	skips = 0, -- (models left out of a compose: past the tick's budget with no kept picture; since the last debugPerf)
	skipWhy = {} :: { [string]: number },
	sweep = 0,
	strips = {} :: { Rect }, -- (layer rects a pan brought in this frame: SG.panShift)
	snapped = nil :: { color: buffer, id: buffer, depth: buffer }?,
	still = {} :: { Dyn },
	shad = {} :: { Dyn },
	live = (nil :: any) :: (s: Surf) -> boolean,
	sync = (nil :: any) :: (s: Surf, i: number, old: number, new: number) -> (),
	px = (nil :: any) :: (s: Surf, i: number) -> (),
	rect = (nil :: any) :: (s: Surf, x0: number, y0: number, x1: number, y1: number) -> (),
}

-- the wind's paint on the static layer (the wind section): undone before a scroll, a stash or a bake
local windSaved: { [number]: number } = {} -- pixel -> its colour before the wind
local windWrote: { [number]: number } = {} -- pixel -> the colour the wind painted
local windOn: Surf? = nil -- the layer they belong to (another layer's are dropped, never painted elsewhere)

local function windRestore(s: Surf): boolean
	local color = s.sColor
	local any = false
	if windOn == s then
		local inc = not needFull and SG.live(s)
		for i, c in windSaved do
			local w = windWrote[i]
			if buffer.readu32(color, i * 4) == w then
				buffer.writeu32(color, i * 4, c)
				SG.px(s, i)
				if inc then
					SG.sync(s, i, w, c)
				end
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
	-- (sized in art px and scaled by K here: Roblox keeps an Offset whole, so W * K units given as an offset lost its
	-- fraction when K was fitted to a screen scaled by 125%)
	local sc = Instance.new("UIScale")
	sc.Name = "PixelSize"
	sc.Scale = 1
	sc.Parent = label
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
	rush = false
	back, backTabs = nil, nil
	-- no bake is coming: whoever waits for one goes on now
	local fns = afterBake
	afterBake = {}
	for _, fn in fns do
		task.spawn(fn)
	end
end

------------------------------------------------------------------ surface textures
-- Material detail at bake time (Render/Shading's patterns; Random Bakery's wood grain and metal streak among them):
-- each static pixel of a textured colour may shift a band darker or lighter on its own ramp, by a pattern on the
-- global art grid and numbers worked out once per part (its screen box, its long axis, where it stands), so a pan's
-- strips, a re-cast and a fresh bake all agree. No ray is cast for it. The water (PixelWater: animated on its own) and
-- glowing parts have none, and a part too small on screen for its pattern to read (TEX_MIN) neither. The dynamic layer
-- has none: a pattern on the screen's grid would slide over a model as it moves.
local TEX_GRASS, TEX_SAND, TEX_STONE = Shading.TEX_GRASS, Shading.TEX_SAND, Shading.TEX_STONE
local TEX_WOOD, TEX_THATCH, TEX_BRICK = Shading.TEX_WOOD, Shading.TEX_THATCH, Shading.TEX_BRICK
local TEX_METAL = Shading.TEX_METAL
local TEX_SOFT = Shading.TEX_SOFT
-- the least screen box (art px wide, tall) each kind needs
local TEX_MIN: { [number]: { number } } = {
	[Shading.TEX_WOOD] = { 6, 4 },
	[Shading.TEX_METAL] = { 4, 4 },
	[Shading.TEX_GLASS] = { 3, 3 },
	[Shading.TEX_GRASS] = { 8, 5 },
	[Shading.TEX_SAND] = { 6, 4 },
	[Shading.TEX_STONE] = { 6, 4 },
	[Shading.TEX_THATCH] = { 6, 4 },
	[Shading.TEX_BRICK] = { 8, 6 },
}
local UP_FACING = 0.7 -- grass marks only on faces whose normal looks up at least this much
local FLAT_TOP = 0.9 -- thatch strokes only on faces whose normal looks up less than this (a roof's slope, a side)

-- A part's texture for the view of layer s (NO_TEX: none).
local function texInfoOf(s: Surf, part: BasePart, rgb: number, wcls: number): TexInfo
	if rgb >= EMISSIVE or (wcls >= 1 and wcls <= 3) or wcls == 6 then
		return NO_TEX
	end
	local kind = Shading.texKind(rgb)
	if kind == 0 then
		return NO_TEX
	end
	if kind == TEX_BRICK and not (part:IsA("WedgePart") or (part:IsA("Part") and (part :: Part).Shape == Enum.PartType.Block)) then
		return NO_TEX -- (a round thing in brick red is a berry, a pot or a crown of leaves, not a wall)
	end
	local v = s.view
	local rot, g = v.rot12, v.grid
	local size = part.Size
	local px, py, pz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
	-- the part's own axes on the global grid (art px per stud right and down: Raster.gridPoint without its offset)
	local q = g.q
	local sr4, sr7, sr10 = rot[4] * q, rot[7] * q, rot[10] * q
	local sd5, sd8, sd11 = -rot[5] * q, -rot[8] * q, -rot[11] * q
	local xx, xy = r00 * sr4 + r10 * sr7 + r20 * sr10, r00 * sd5 + r10 * sd8 + r20 * sd11
	local yx, yy = r01 * sr4 + r11 * sr7 + r21 * sr10, r01 * sd5 + r11 * sd8 + r21 * sd11
	local zx, zy = r02 * sr4 + r12 * sr7 + r22 * sr10, r02 * sd5 + r12 * sd8 + r22 * sd11
	-- its screen box: the centre and the half extents of the box's projection
	local cx, cy = Raster.gridPoint(rot, g, px, py, pz)
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local ex = math.abs(xx) * hx + math.abs(yx) * hy + math.abs(zx) * hz
	local ey = math.abs(xy) * hx + math.abs(yy) * hy + math.abs(zy) * hz
	local bx0, by0 = math.floor(cx - ex), math.floor(cy - ey)
	local w, h = math.ceil(cx + ex) - bx0, math.ceil(cy + ey) - by0
	local min = TEX_MIN[kind]
	if min and (w < min[1] or h < min[2]) then
		return NO_TEX
	end
	-- the long axis on screen: 1 upright, 2 level, 3 down to the right (2:1), 4 down to the left
	local dx: number, dy: number
	if size.X >= size.Y and size.X >= size.Z then
		dx, dy = xx, xy
	elseif size.Y >= size.Z then
		dx, dy = yx, yy
	else
		dx, dy = zx, zy
	end
	local fam = if math.abs(dx) < 0.35 * math.abs(dy) then 1 elseif math.abs(dy) < 0.2 * math.abs(dx) then 2 elseif dx * dy > 0 then 3 else 4
	-- (from where the part stands, not its id: a fresh bake numbers the parts afresh)
	local seed = math.floor(math.abs(px * 7.3 + py * 13.1 + pz * 17.7) * 4) % 997
	return { kind = kind, rgb = rgb, x0 = bx0, y0 = by0, w = w, h = h, fam = fam, seed = seed }
end

-- How a brick face's courses run (Shading.courseFam) by normal index, for the view rotation they were worked out for.
local courseFams: { number } = {}
local courseRot: { number }? = nil
local function courseFamOf(rot: { number }, ni: number): number
	if courseRot ~= rot then
		courseRot = rot
		for i = 1, 256 do
			courseFams[i] = Shading.courseFam(rot, NX[i], NY[i], NZ[i])
		end
	end
	return courseFams[ni]
end

-- The band shift texture t gives global pixel (gx, gy), which shows normal index ni - 1 (NX's index ni) with shadow
-- factor lit. A lighter mark shows only on a face in full light (one in the shade would read as light leaking in); a
-- darker one shows wherever there is a darker band to take.
local function texLift(s: Surf, t: TexInfo, ni: number, lit: number, gx: number, gy: number): number
	local kind = t.kind
	local mark: number
	if kind == TEX_GRASS then
		if NY[ni] < UP_FACING then
			return 0
		end
		mark = Shading.grassMark(gx, gy)
	elseif kind == TEX_SAND then
		mark = Shading.sandMark(gx, gy)
	elseif kind == TEX_STONE then
		mark = Shading.stoneMark(gx, gy)
	elseif kind == TEX_WOOD then
		mark = Shading.grain(t.fam, t.seed, gx, gy)
	elseif kind == TEX_THATCH then
		if NY[ni] >= FLAT_TOP then
			return 0
		end
		mark = Shading.thatchMark(gx, gy)
	elseif kind == TEX_BRICK then
		local fam = courseFamOf(s.view.rot12, ni)
		if fam == 0 then
			return 0
		end
		mark = Shading.mortar(fam, gx, gy)
	elseif kind == TEX_METAL then
		if lit ~= 1 then
			return 0
		end
		mark = Shading.streak(t.x0, t.y0, t.w, t.h, gx, gy)
	else
		mark = Shading.glass(t.x0, t.y0, t.w, t.h, gx, gy)
	end
	if mark > 0 and (lit ~= 1 or Shading.band(NX[ni], NY[ni], NZ[ni], lit) ~= 1) then
		return 0
	end
	return mark
end

------------------------------------------------------------------ static shading
local function shadeAt(s: Surf, idx: number, x: number, y: number): number
	local gx, gy = x + s.cam.gx, y + s.cam.gy
	if buffer.readu16(s.sId, idx * 2) == 0 then
		-- (a stage with a see-through sky: nothing there, the picture behind the layer shows)
		return if s.view.clear then 0 else Shading.sky(gx, gy - s.skyRef, s.H)
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
	-- the surface's texture (not where glass in front tints it: NO_TEX's colour matches none)
	local lift, soft = 0, 1
	local t = texs[buffer.readu16(s.sId, idx * 2)]
	if t and t.rgb == a then
		lift = texLift(s, t, ni, lit, gx, gy)
		soft = TEX_SOFT[t.kind] or 1 -- (a mark a gentle tone, not a whole band: Shading.TEX_SOFT)
	end
	return Shading.toonAt(a, NX[ni], NY[ni], NZ[ni], lit, gx, gy, place, lift, soft)
end

-- One bake sample at global (gx, gy), filling the block up to (bx1, by1) (global, inclusive) on the layer.
-- The sea's wave phase at a world point (wavy lines across the world, about 10 studs apart): the bake's.
local function waterPhase(wx: number, wz: number): number
	local v = wx * 0.6 + wz * 0.35 + 1.6 * math.sin(wz * 0.23 + wx * 0.05) + 1.1 * math.sin(wx * 0.17)
	return math.floor(v * 9.14) % 256
end

local function castSample(s: Surf, gx: number, gy: number, bx1: number, by1: number, own: boolean, shadows: boolean)
	local cam = s.cam
	local x, y = gx - cam.gx, gy - cam.gy
	local ox, oy, oz = Raster.origin(cam, x, y)
	local mode = if own then (if shadows then BakeCast.SHADOW_TEST else BakeCast.SHADOW_OFF) else BakeCast.shadowMode(shadows, gx, gy)
	local part, depth, ni, lit, rays, tint = BakeCast.cast(params, Vector3.new(ox, oy, oz), s.look, FAR, mode, SUN_V)
	bakeRays += rays
	if part ~= nil then
		-- (a part of a model lit smooth, the Tree of Life: the normal blended across its balls, in a fine direction;
		-- Render/Smooth)
		local k0 = ni + 1
		local snx, sny, snz = SmoothParts.staticNormal(part, ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth, NX[k0], NY[k0], NZ[k0])
		if snx and sny and snz then
			ni = Shading.fineIndex(snx, sny, snz)
		end
	end
	local id, albedo = 0, 0
	local shared = false
	if part ~= nil then
		id = staticIdOf(part)
		albedo = albedos[id]
		if texs[id] == nil then
			texs[id] = texInfoOf(s, part, albedo, waters[id] or 0)
		end
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
		elseif wcls == 6 then
			-- falling water: by height (the streaks run down it), each thin column of it a little apart from the next
			local wy = oy + cam.ly * depth
			wph = (math.floor(wy * 6) + math.floor((wx + wz) * 3) * 5) % 256
		else
			wph = waterPhase(wx, wz)
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
-- A spotlight (from the old fights; nothing sets it now): the static picture darkened by `dim` (0 .. 1, in tenths: each step re-uploads the picture), the
-- dynamic things (the fighters, their effects) and glowing parts left as they are.
local dim = 0
local dimMap: { [number]: number } = {}
local lightMap: buffer? = nil
local lightStale = true
local lightAt = 0
local LIGHT_EVERY = 0.4
-- A pool's rings as shares of its radius (art px, vertical; twice as wide: the ground is seen at 2:1). The radius
-- follows the light's size ("lights seem off, the all have the same size even though the light source might be
-- smaller or bigger"): LIGHT_K x how many pixels the light covers to the power LIGHT_POW (a glint on the tree 1, the
-- tree's lanterns about 10, a pier lantern about 19, a torch about 40, the campfire over 120: radii about 2, 5, 7, 11
-- and 21), between LIGHT_MIN and LIGHT_MAX.
local RING = { 0.35, 0.65, 1 }
local LIGHT_K = 1.2
local LIGHT_POW = 0.6
local LIGHT_MIN = 2
local LIGHT_MAX = 22
local function lightRadius(area: number): number
	return math.clamp(LIGHT_K * area ^ LIGHT_POW, LIGHT_MIN, LIGHT_MAX)
end

local function clampByte(v: number): number
	return if v < 0 then 0 elseif v > 255 then 255 else math.floor(v + 0.5)
end

local function gradeOf(c: number, lvl: number, with: Grade?): number
	local g = (with or grade) :: Grade
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

-- One light's pool of radius R (art px) round (px, py), stepped on the pixel grid.
local function splat(lm: buffer, W: number, H: number, px: number, py: number, R: number)
	local r1, r2 = RING[1] * R, RING[2] * R
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
			local lvl = if e < r1 then 3 elseif e < r2 then 2 elseif e < R then 1 else 0
			if lvl > 0 then
				local i = y * W + x
				if buffer.readu8(lm, i) < lvl then
					buffer.writeu8(lm, i, lvl)
				end
			end
		end
	end
end

-- The lamps' pools, each as big as its light: on the static layer a light is a patch of lamp pixels touching each
-- other (8 ways), its pool round the patch's middle, a little lower; a dynamic model's lit parts together are
-- one light (a fire's flames, a driftling's glowing eyes), their size the faces they show (art px per stud: cam.s / K).
local lightSeen: buffer? = nil
local lightStack: { number } = {}
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
	local seen: buffer
	local had = lightSeen
	if had == nil or buffer.len(had) ~= n then
		seen = buffer.create(n)
		lightSeen = seen
	else
		seen = had
		buffer.fill(seen, 0, 0)
	end
	local sid = s.sId
	local lamp: { [number]: boolean } = {}
	local function isLamp(i: number): boolean
		local id = buffer.readu16(sid, i * 2)
		if id == 0 or id >= DYN_ID0 then
			return false
		end
		local v = lamp[id]
		if v == nil then
			v = (albedos[id] or 0) >= EMISSIVE
			lamp[id] = v
		end
		return v
	end
	local stack = lightStack
	for i0 = 0, n - 1 do
		if buffer.readu8(seen, i0) ~= 0 or not isLamp(i0) then
			continue
		end
		-- the patch: how many pixels and their middle
		buffer.writeu8(seen, i0, 1)
		local top = 1
		stack[1] = i0
		local count, sumX, sumY = 0, 0, 0
		while top > 0 do
			local i = stack[top]
			top -= 1
			local x, y = i % W, i // W
			count += 1
			sumX += x
			sumY += y
			for dy = -1, 1 do
				local yy = y + dy
				if yy < 0 or yy >= H then
					continue
				end
				for dx = -1, 1 do
					local xx = x + dx
					if xx >= 0 and xx < W then
						local j = yy * W + xx
						if buffer.readu8(seen, j) == 0 and isLamp(j) then
							buffer.writeu8(seen, j, 1)
							top += 1
							stack[top] = j
						end
					end
				end
			end
		end
		-- (the pool a little under the light: on the ground round its foot)
		splat(lm :: buffer, W, H, math.floor(sumX / count + 0.5), math.floor(sumY / count + 0.5) + 3, lightRadius(count))
	end
	local cam = s.cam
	local ppu = cam.s / cam.K
	for model, d in dyns do
		if model.Parent == nil then
			continue
		end
		local area, sx, sy, any = 0, 0, 0, false
		for _, p in d.parts do
			-- (a part marked "PixelNoPool" glows but pools no light round it: a hatching egg's cracks)
			if p.glow and p.part.Parent ~= nil and p.part:GetAttribute("PixelNoPool") ~= true then
				local pos = p.part.Position
				local fx, fy = Raster.project(cam, pos.X, pos.Y, pos.Z)
				-- (the faces it shows: its two biggest sides, on the screen)
				local sz = p.part.Size
				local a, b, c = sz.X, sz.Y, sz.Z
				local face = (a * b + b * c + a * c - math.min(a * b, b * c, a * c)) * 0.5 * ppu * ppu
				area += face
				sx += fx * face
				sy += fy * face
				any = true
			end
		end
		if any and area > 0 then
			local x, y = math.floor(sx / area + 0.5), math.floor(sy / area + 0.5)
			if x >= -20 and x < W + 20 and y >= -10 and y < H + 10 then
				splat(lm :: buffer, W, H, x, y + 3, lightRadius(area))
			end
		end
	end
	lightStale = false
	lightAt = os.clock()
	SG.ok = false -- (the pools graded into the static picture moved)
end

-- A static pixel in the spotlight: darker, a little greyer and cooler (what moves stands out against it).
local function dimOf(c: number): number
	local r, gg, b = c % 256, (c // 256) % 256, (c // 65536) % 256
	local a = c - c % 16777216
	local l = 0.3 * r + 0.59 * gg + 0.11 * b
	local mix, keep = 0.35 * dim, 1 - 0.5 * dim
	local nr = (r + (l - r) * mix) * keep + 8 * dim
	local ng = (gg + (l - gg) * mix) * keep + 6 * dim
	local nb = (b + (l - b) * mix) * keep + 18 * dim
	return clampByte(nr) + clampByte(ng) * 256 + clampByte(nb) * 65536 + a
end

-- n pixels of a picture (colours src, ids fid: the frame's or the static layer's) from pixel i0, graded (the time
-- of day) and dimmed (the spotlight) into out from pixel o0.
local function gradeSpan(src: buffer, fid: buffer, i0: number, n: number, out: buffer, o0: number)
	local g = grade
	local lm = if g and g.lamps > 0 then lightMap else nil
	local map = gradeMap
	local dmap = dimMap
	-- (a run of one colour of one part under one pool, as pixel art is mostly: graded once)
	local lastC, lastId, lastL, lastO = -1, -1, -1, 0
	for k = 0, n - 1 do
		local i = i0 + k
		local c = buffer.readu32(src, i * 4)
		local id = buffer.readu16(fid, i * 2)
		local lvl = if lm then buffer.readu8(lm, i) else 0
		local o = c
		if c == lastC and id == lastId and lvl == lastL then
			o = lastO
		else
			if c ~= 0 and not isGlow(id) then
				if g then
					local key = c + lvl * 4294967296
					o = map[key]
					if o == nil then
						o = gradeOf(c, lvl)
						map[key] = o
					end
				end
				if dim > 0 and id < DYN_ID0 then
					local d = dmap[o]
					if d == nil then
						d = dimOf(o)
						dmap[o] = d
					end
					o = d
				end
			end
			lastC, lastId, lastL, lastO = c, id, lvl, o
		end
		buffer.writeu32(out, (o0 + k) * 4, o)
	end
end

-- Pixel i of the static layer graded again into SG (when SG is in step with layer s).
function SG.px(s: Surf, i: number)
	local b = SG.buf
	if SG.ok and SG.on == s and b then
		gradeSpan(s.sColor, s.sId, i, 1, b, i)
	end
end

-- A static layer rect (inclusive, clipped to the layer) graded again into SG.
function SG.rect(s: Surf, x0: number, y0: number, x1: number, y1: number)
	local b = SG.buf
	if not (SG.ok and SG.on == s and b) then
		return
	end
	x0, y0, x1, y1 = math.max(0, x0), math.max(0, y0), math.min(s.W - 1, x1), math.min(s.H - 1, y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local w = x1 - x0 + 1
	for y = y0, y1 do
		local i = y * s.W + x0
		gradeSpan(s.sColor, s.sId, i, w, b :: buffer, i)
	end
end

------------------------------------------------------------------ upload
-- The whole image up. Graded, the static picture comes from SG (graded all again only when out of step) and only what
-- is drawn over it is graded from the frame: the rects `over` (the dynamic layer's, the effects'), the pixels the
-- effects wrote this tick (fxn of them in book fxb) and the stuck ones (sticks). Nothing over it: the frame is the
-- static picture alone (a bake).
local function uploadAll(s: Surf, over: { Rect }?, sticks: boolean?, fxb: buffer?, fxn: number?)
	local im = img
	if im == nil then
		return
	end
	local u0 = SG.clock()
	local f = s.frame
	local src = f.color
	if grade or dim > 0 then
		local n = s.W * s.H
		local now = os.clock()
		if grade and (grade :: Grade).lamps > 0 and (lightMap == nil or buffer.len(lightMap :: buffer) ~= n or ((lightStale or now - lightAt >= 1) and now - lightAt >= LIGHT_EVERY)) then
			buildLight(s)
		end
		local b = SG.out
		if b == nil or buffer.len(b) ~= n * 4 then
			b = buffer.create(n * 4)
			SG.out = b
		end
		local g0 = SG.clock()
		local sg = SG.buf
		if not SG.ok or SG.on ~= s or sg == nil or buffer.len(sg) ~= n * 4 then
			if sg == nil or buffer.len(sg) ~= n * 4 then
				sg = buffer.create(n * 4)
				SG.buf = sg
			end
			gradeSpan(s.sColor, s.sId, 0, n, sg :: buffer, 0)
			SG.on, SG.ok = s, true
			stats.perf.regrades += 1
		end
		buffer.copy(b :: buffer, 0, sg :: buffer, 0, n * 4)
		local W, H = s.W, s.H
		local list: { Rect } = over or {}
		-- (in each rect only the pixels the frame has other than the static picture's: the rest are graded in SG.buf,
		-- copied above; a crowd's rects are mostly ground, and grading it all again was a fifth of a frame)
		local fc, fi, sc, si = f.color, f.id, s.sColor, s.sId
		for _, r in list do
			local x0, y0, x1, y1 = math.max(0, r.x0), math.max(0, r.y0), math.min(W - 1, r.x1), math.min(H - 1, r.y1)
			if x0 <= x1 then
				for y = y0, y1 do
					local row = y * W
					local run = -1
					for x = x0, x1 + 1 do
						local i = row + x
						local differs = x <= x1 and (buffer.readu32(fc, i * 4) ~= buffer.readu32(sc, i * 4) or buffer.readu16(fi, i * 2) ~= buffer.readu16(si, i * 2))
						if differs then
							if run < 0 then
								run = i
							end
						elseif run >= 0 then
							gradeSpan(fc, fi, run, i - run, b :: buffer, run)
							run = -1
						end
					end
				end
			end
		end
		if fxb and fxn then
			-- (this tick's effect pixels: the book they were written in)
			for k = 0, fxn - 1 do
				local i = buffer.readu32(fxb, k * 4)
				if i < n then
					gradeSpan(f.color, f.id, i, 1, b :: buffer, i)
				end
			end
		end
		if sticks then
			for _, i in stickList do
				if i < n then
					gradeSpan(f.color, f.id, i, 1, b :: buffer, i)
				end
			end
		end
		stats.perf.gradeMs += (SG.clock() - g0) * 1000
		SG.fullAt = SG.seq
		src = b :: buffer
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.zero, Vector2.new(s.W, s.H), src)
	end)
	stats.perf.uploads += 1
	stats.perf.uploadMs += (SG.clock() - u0) * 1000
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
	SG.seq += 1
	if grade or dim > 0 then
		if grade and (grade :: Grade).lamps > 0 and (lightMap == nil or buffer.len(lightMap :: buffer) ~= s.W * s.H) then
			buildLight(s)
		end
		for y = y0, y1 do
			gradeSpan(s.frame.color, s.frame.id, y * s.W + x0, w, b, (y - y0) * w)
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

-- (`done`: the finishing passes were run in bands as part of the bake, bakeRun's pass 4; else here, all at once)
local function finishBake(s: Surf, b: Surf, done: boolean?)
	baking = false
	if b ~= s then
		-- the bake behind the picture is done: its buffers become the layer's (the old picture's wind paint goes
		-- with its buffers)
		s.sColor, s.sShade, s.sShadowC, s.sAlbedo = b.sColor, b.sShade, b.sShadowC, b.sAlbedo
		s.sNormal, s.sLit, s.sDepth, s.sId = b.sNormal, b.sLit, b.sDepth, b.sId
		s.sShare, s.sWClass, s.sWave, s.static = b.sShare, b.sWClass, b.sWave, b.static
		windOn = nil
		table.clear(windSaved)
		table.clear(windWrote)
		SG.windVoid = true
		table.clear(SG.windPend)
		lightStale = true
		back, backTabs = nil, nil
	end
	s.ready = true
	SG.waterAll = true -- (the new picture's sea is its bare shade: the next water pass shades all of it)
	SG.waterDone, SG.waterPendN = 0, 0
	buffer.fill(s.sShadowC, 0, 0)
	if not done then
		if tierSpec(tier).shadows then
			refineShadows(s, 0, 0, s.W - 1, s.H - 1)
		end
		Shading.outline(s.static, 0, 0, s.W - 1, s.H - 1, s.sShade)
		contactPass(s)
	end
	local f = s.frame
	buffer.copy(f.color, 0, s.sColor, 0, s.W * s.H * 4)
	buffer.copy(f.depth, 0, s.sDepth, 0, s.W * s.H * 4)
	buffer.copy(f.id, 0, s.sId, 0, s.W * s.H * 2)
	prevRects = {}
	SG.ok = false
	SG.ver += 1
	-- (the next compose is a whole one, so the incremental composes start again from this picture: without it they
	-- went on from the old picture's base, and every effect taken off the frame put back a pixel of the old place,
	-- each moving leaf or wisp of wind leaving a row of another spot's colours behind it; the sweep of 2026-11-19
	-- found them after a long walk's re-bake)
	needFull = true
	uploadAll(s)
	stats.bakes += 1
	staticChanged()
	rush = false
	if #afterBake > 0 then
		local fns = afterBake
		afterBake = {}
		for _, fn in fns do
			task.spawn(fn)
		end
	end
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

-- Bake samples into b (the layer s itself, or the buffers behind it) until the deadline; true when the bake is done.
local function bakeRun(s: Surf, b: Surf, deadline: number): boolean
	local shadows = tierSpec(tier).shadows
	local steps = BakeCast.STEPS
	while bakePass <= 3 do
		local st = steps[bakePass]
		while bakeGY <= bakeRY1 do
			while bakeGX <= bakeRX1 do
				if SG.clock() > deadline then
					return false
				end
				local bx, by = bakeGX, bakeGY
				bakeGX += st
				local x, y = math.max(bx, bakeRX0), math.max(by, bakeRY0)
				if x == bx and y == by then
					if not BakeCast.skip(bakePass, x, y) then
						castSample(b, x, y, bx + st - 1, by + st - 1, false, shadows)
					end
				elseif bakePass < 3 then
					-- a block starting off the layer: a stand-in at its first pixel on it (later passes replace it)
					castSample(b, x, y, bx + st - 1, by + st - 1, true, shadows)
				end
			end
			bakeGX = bakeOX
			bakeGY += st
		end
		bakePass += 1
		bakeGX, bakeGY = bakeOX, bakeOY
		if bakePass == 4 then
			bakeFin, bakeFinY = 1, 0
		end
	end
	-- (pass 4: the finishing passes over the new picture a band of rows at a time, the old one still showing, so the
	-- frame that swaps it in only copies and uploads. They ran over the whole layer in that one frame: 344 ms of it in
	-- the simulator after a tier 3 island grew, the request of 2026-11-19 "Expansion is very slow and laggy")
	while bakeFin == 1 do
		if SG.clock() > deadline then
			return false
		end
		local y1 = math.min(b.H - 1, bakeFinY + FIN_ROWS - 1)
		if shadows then
			refineShadows(b, 0, bakeFinY, b.W - 1, y1)
		end
		bakeFinY = y1 + 1
		if bakeFinY >= b.H then
			bakeFin, bakeFinY = 2, 0
		end
	end
	while bakeFin == 2 do
		if SG.clock() > deadline then
			return false
		end
		local y1 = math.min(b.H - 1, bakeFinY + FIN_ROWS - 1)
		Shading.outline(b.static, 0, bakeFinY, b.W - 1, y1, b.sShade)
		contactPass(b, 0, bakeFinY, b.W - 1, y1)
		bakeFinY = y1 + 1
		if bakeFinY >= b.H then
			bakeFin, bakeFinY = 0, 0
		end
	end
	finishBake(s, b, true)
	return true
end

-- Bake until the deadline; true when the bake is done. A bake behind the picture casts with its own id tables
-- (swapped in for the call), so the picture's stay whole for the water, wind and lamps drawn over it meanwhile.
local function bakeSome(deadline: number): boolean
	local s = surf
	if s == nil or not baking then
		return true
	end
	local b, t = back, backTabs
	if b == nil or t == nil then
		return bakeRun(s, s, deadline)
	end
	local fIds, fAlb, fWat, fTex, fNext = staticIds, albedos, waters, texs, nextId
	staticIds, albedos, waters, texs, nextId = t.ids, t.albedos, t.waters, t.texs, t.nextId
	local done = bakeRun(s, b, deadline)
	if not done then
		t.nextId = nextId
		staticIds, albedos, waters, texs, nextId = fIds, fAlb, fWat, fTex, fNext
	end
	return done
end

local function startBake()
	local s = surf
	if s == nil then
		return
	end
	-- (the smooth models' balls gathered again: the island may have changed)
	SmoothParts.reset()
	-- (a new picture of the island: the pan cache starts again, and the next tier's pre-cast, its part ids renumbered; a
	-- stage's bake leaves the island's be)
	if not s.view.stage then
		SG.Tiles.setMax(Tuning.PixelPanCacheTiles)
		SG.Tiles.clear()
		preReset()
	end
	if s.view.empty then
		-- an empty see-through stage (CameraController's Stage.empty: only moving things in front of a 2D picture, the
		-- hatch scene's egg): every pixel is the clear sky a ray would find, written at once, no rays and no wait
		local n = s.W * s.H
		buffer.fill(s.sColor, 0, 0)
		buffer.fill(s.sShade, 0, 0)
		buffer.fill(s.sAlbedo, 0, 0)
		buffer.fill(s.sId, 0, 0)
		buffer.fill(s.sNormal, 0, 0)
		buffer.fill(s.sLit, 0, 1)
		buffer.fill(s.sShare, 0, 0)
		buffer.fill(s.sWClass, 0, 0)
		buffer.fill(s.sWave, 0, 0)
		for i = 0, n - 1 do
			buffer.writef32(s.sDepth, i * 4, FAR)
		end
		back, backTabs = nil, nil
		table.clear(staticIds)
		table.clear(albedos)
		table.clear(waters)
		table.clear(texs)
		nextId = 1
		invQueue = {}
		invCur = nil
		finishBake(s, s)
		return
	end
	if s.ready and shown then
		-- a finished picture is on screen: bake behind it, into fresh buffers and id tables
		local n = s.W * s.H
		local sColor, sDepth, sId = buffer.create(n * 4), buffer.create(n * 4), buffer.create(n * 2)
		back = {
			W = s.W,
			H = s.H,
			K = s.K,
			cam = s.cam,
			look = s.look,
			view = s.view,
			skyRef = s.skyRef,
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
			static = { W = s.W, H = s.H, color = sColor, depth = sDepth, id = sId },
			frame = s.frame,
			m = s.m,
			vw = s.vw,
			vh = s.vh,
			ox = s.ox,
			oy = s.oy,
		}
		backTabs = { ids = {}, albedos = {}, waters = {}, texs = {}, nextId = 1 }
	else
		back, backTabs = nil, nil
		lightStale = true
		table.clear(windSaved)
		table.clear(windWrote)
		windOn = nil
		table.clear(staticIds)
		table.clear(albedos)
		table.clear(waters)
		table.clear(texs)
		nextId = 1
	end
	local cam = s.cam
	bakeRX0, bakeRY0 = cam.gx, cam.gy
	bakeRX1, bakeRY1 = cam.gx + s.W - 1, cam.gy + s.H - 1
	bakeOX, bakeOY = bakeRX0 - bakeRX0 % 4, bakeRY0 - bakeRY0 % 4
	bakeGX, bakeGY = bakeOX, bakeOY
	bakePass = 1
	bakeFin, bakeFinY = 0, 0
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
	SG.exclVer += 1
end

-- The picture is kept `marginOf` art px past each edge of the screen: the view moves within it by showing another
-- window of the image (`showWindow`), and the picture scrolls only once the view comes within Tuning.PixelPanEdge of
-- its edge, re-centred under it (the request of 2026-11-21: "camera moving is extremely laggy still. could you make it
-- smooth and lerp to the player?": every frame the view moved, every buffer of the picture shifted and the whole image
-- went up again; now that happens once every few frames). A stage keeps the same margin, its view standing in the
-- middle, so the island's kept picture and a stage's are one size and the island's comes back after it (the stash).
local function marginOf(_v: CameraController.View): number
	return Tuning.PixelPanMargin
end

-- The layer's camera with its top-left global art px at (gx, gy): the screen's size and the margin all round.
local function layerCam(v: CameraController.View, gx: number, gy: number, K: number): Raster.Cam
	local m = marginOf(v)
	local fx, fy = v.fullX, v.fullY
	if m > 0 then
		-- (Raster.cam takes ceil(full / K) pixels: half a pixel short of the whole count, so no rounding adds one)
		local w0, h0 = math.ceil(fx / K), math.ceil(fy / K)
		fx, fy = (w0 + 2 * m - 0.5) * K, (h0 + 2 * m - 0.5) * K
	end
	return Raster.gridCam(v.rot12, CameraController.gridAt(gx, gy), fx, fy, K, Tuning.CamRayBack)
end

-- The screen's window of layer s: where the view stands now (CameraController.pan) less the layer's top-left, kept
-- on the picture (a view that ran ahead of the picture's scroll waits at its edge), shown through the image's
-- ImageRectOffset (exact at any pixel size: an Offset is a whole number of units, a pixel 2.4 at 125%).
local function showWindow(s: Surf)
	local im = image
	if s.m == 0 then
		s.ox, s.oy = 0, 0
		if im and im.ImageRectSize ~= Vector2.zero then
			im.ImageRectOffset, im.ImageRectSize = Vector2.zero, Vector2.zero
		end
		return
	end
	local px, py = CameraController.pan()
	s.ox = math.clamp(px - s.cam.gx, 0, s.W - s.vw)
	s.oy = math.clamp(py - s.cam.gy, 0, s.H - s.vh)
	if im then
		local o, z = Vector2.new(s.ox, s.oy), Vector2.new(s.vw, s.vh)
		if im.ImageRectOffset ~= o then
			im.ImageRectOffset = o
		end
		if im.ImageRectSize ~= z then
			im.ImageRectSize = z
		end
	end
end

-- A layer for the camera's view: buffers, image and a fresh bake (or the kept street picture when its view comes back).
local function buildSurf(v: CameraController.View)
	preReset() -- (another view: another grid)
	refreshExclude()
	lightStale = true
	local old = surf
	if old then
		windRestore(old) -- (the wind's paint off the layer going away: a kept street picture comes back clean)
	end
	SG.windVoid = true
	table.clear(SG.windPend)
	if old and old.ready and not old.view.stage and v.stage then
		-- a stage takes the view: keep the island's finished picture. The report of 2026-11-18, "a glitch happens
		-- when expanding and then immediately hatching somthing after, which causes the filter to be disabled": a
		-- picture with a re-bake going on behind it (or one due) was dropped, so the island came back to a bake from
		-- nothing, the scene's last frame left over the world meanwhile. It is kept too now, out of date. (The id
		-- tables here are always the picture's: a bake behind swaps its own in only inside bakeSome.)
		local due = baking or rebakeAt >= 0
		stash = { key = old.view.key, surf = old, ids = table.clone(staticIds), albedos = table.clone(albedos), waters = table.clone(waters), texs = table.clone(texs), nextId = nextId, dirty = due, inv = invQueue, cur = invCur }
		rebakeAt = -1 -- (the island's re-bake waits for the island; the stage bakes its own picture now)
	end
	local st = stash
	if st and not v.stage then
		stash = nil
		if st.key == v.key and img and img.Size.X == st.surf.W and img.Size.Y == st.surf.H then
			surf = st.surf
			staticIds, albedos, waters, texs, nextId = st.ids, st.albedos, st.waters, st.texs, st.nextId
			baking = false
			back, backTabs = nil, nil
			invQueue = if st.dirty then {} else st.inv
			invCur = if st.dirty then nil else st.cur
			prevRects = {}
			needFull = true
			SG.ok = false
			SG.ver += 1
			SG.waterAll = true
			SG.waterDone, SG.waterPendN = 0, 0
			staticChanged()
			if image then
				image.Visible = true
				image.ImageTransparency = 0
				image.Size = UDim2.fromOffset(st.surf.vw, st.surf.vh)
			end
			showWindow(st.surf)
			if st.dirty then
				-- (on screen at once, baked again behind it)
				rush = true
				startBake()
			end
			return
		end
	end
	local K = v.K
	local m = marginOf(v)
	local W0, H0 = math.ceil(v.fullX / K), math.ceil(v.fullY / K)
	local W, H = W0 + 2 * m, H0 + 2 * m
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
	im.Size = UDim2.fromOffset(W0, H0)
	local psz = im:FindFirstChildOfClass("UIScale")
	if psz then
		psz.Scale = K
	end
	im.Visible = true
	if old and old.view.stage and not v.stage then
		-- back from a stage with no picture kept (the screen changed size meanwhile): the stage's last frame must not
		-- stay over the world while the island bakes; the new picture fades in when it is done
		shown = false
		im.ImageTransparency = 1
	end
	local px, py = CameraController.pan()
	local cam = layerCam(v, px - m, py - m, K)
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
		m = m,
		vw = W0,
		vh = H0,
		ox = m,
		oy = m,
	}
	showWindow(surf :: Surf)
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

-- A textured part (a driftling's fur, scales, shell...: its "PixelTex" attribute, Render/DynTex): the pixel's ray hits
-- the part at distance t; that point in the part's own frame, laid out flat round the part's axis, picks a step
-- lighter or darker on the colour's ramp, so the pattern turns and walks with the part and keeps to the pixel grid.
-- The part being drawn is set in these before each draw (compose).
local texCam: Raster.Cam? = nil
local texCF: { number } = {}
local texShape = "Block"
local texKind = 0
-- the part's pattern seed, the studs added to its v (PixelTexV: a hatch-scene egg's slices share one pattern) and how
-- far a mark steps (PixelTexSoft)
-- and, for a model lit smooth (Render/Smooth), its balls this frame (xs ys zs rs, cnt of them), the ones near the
-- part being drawn (idx, n) and the part's role
local texOpt = {
	seed = 0,
	v = 0,
	soft = DynTex.SOFT,
	xs = {} :: { number },
	ys = {} :: { number },
	zs = {} :: { number },
	rs = {} :: { number },
	cnt = 0,
	idx = {} :: { number },
	n = 0,
	role = 0,
	-- the model's smooth solids this frame (Render/Smooth.packSolid), how many, and the ones near the part being drawn
	sol = {} :: { number },
	scnt = 0,
	sidx = {} :: { number },
	sn = 0,
}
local texPx = 1 -- studs a layer pixel
local function shadeTex(rgb: number, nx: number, ny: number, nz: number, x: number, y: number, t: number?): number
	local lift = 0
	local cam = texCam
	local T = texOpt
	if t and cam and T.role > 0 then
		-- (lit smooth: the normal blended across the model's balls near the part)
		local wx = cam.ox + x * cam.ix + y * cam.jx + t * cam.lx
		local wy = cam.oy + x * cam.iy + y * cam.jy + t * cam.ly
		local wz = cam.oz + x * cam.iz + y * cam.jz + t * cam.lz
		nx, ny, nz = SmoothParts.Smooth.normal(T.xs, T.ys, T.zs, T.rs, T.idx, T.n, wx, wy, wz, nx, ny, nz, T.role)
		if T.role == SmoothParts.Smooth.ROLE_FOLLOW and T.sn > 0 then
			-- (a piece on a smooth solid: the solid's normal under it)
			local sx, sy, sz, w = SmoothParts.Smooth.onSolids(T.sol, T.sidx, T.sn, wx, wy, wz)
			if w > 0 then
				local bx, by, bz = nx * (1 - w) + sx * w, ny * (1 - w) + sy * w, nz * (1 - w) + sz * w
				local l = math.sqrt(bx * bx + by * by + bz * bz)
				if l > 1e-6 then
					nx, ny, nz = bx / l, by / l, bz / l
				end
			end
		end
	end
	if t and cam and texKind > 0 then
		-- the hit point, from the pixel's ray (the same origin the solids step their rays from)
		local ox = cam.ox + x * cam.ix + y * cam.jx
		local oy = cam.oy + x * cam.iy + y * cam.jy
		local oz = cam.oz + x * cam.iz + y * cam.jz
		local cf = texCF
		local px, py, pz = ox + t * cam.lx - cf[1], oy + t * cam.ly - cf[2], oz + t * cam.lz - cf[3]
		-- in the part's frame (its axes are the columns of the rotation)
		local lx = px * cf[4] + py * cf[7] + pz * cf[10]
		local ly = px * cf[5] + py * cf[8] + pz * cf[11]
		local lz = px * cf[6] + py * cf[9] + pz * cf[12]
		local u, v = DynTex.uv(texShape, lx, ly, lz)
		lift = DynTex.lift(texKind, u, v + texOpt.v, texPx, texOpt.seed)
	end
	if t and SG.paintOn then
		rgb = (SG.paintAt :: any)(rgb, x, y, t)
	end
	return Shading.toonAt(rgb, nx, ny, nz, 1, x + panX, y + panY, Shading.INDOOR, lift, texOpt.soft)
end

-- A driftling's eye (Render/EyeTex): the hit point on the eyeball in its own frame, its face's (u, v), the layers the
-- eye paints there, each lit as its own palette colour (a catchlight glows), the edge layer mixed over in its share.
SG.shadeEye = function(rgb: number, nx: number, ny: number, nz: number, x: number, y: number, t: number?): number
	local cam = texCam
	if t == nil or cam == nil then
		return Shading.toonAt(rgb, nx, ny, nz, 1, x + panX, y + panY, Shading.INDOOR, 0)
	end
	local E = SG.eyeOpt
	local cf = texCF
	local px = cam.ox + x * cam.ix + y * cam.jx + t * cam.lx - cf[1]
	local py = cam.oy + x * cam.iy + y * cam.jy + t * cam.ly - cf[2]
	local pz = cam.oz + x * cam.iz + y * cam.jz + t * cam.lz - cf[3]
	local u = (px * cf[4] + py * cf[7] + pz * cf[10]) / E.hx
	local v = (px * cf[5] + py * cf[8] + pz * cf[11]) / E.hy
	local ppu = math.min(E.hx, E.hy) / texPx
	local a1, l1, g1, a2, l2, g2, k = SG.EyeTex.sample(E.code, u, v, E.side, ppu, E.iris, E.dark, E.lid, E.white)
	local gx, gy = x + panX, y + panY
	local c1 = Shading.toonAt(a1, nx, ny, nz, if g1 then 2 else 1, gx, gy, Shading.INDOOR, if g1 then 0 else l1)
	if k <= 0.04 then
		return c1
	end
	local c2 = Shading.toonAt(a2, nx, ny, nz, if g2 then 2 else 1, gx, gy, Shading.INDOOR, if g2 then 0 else l2)
	if k >= 0.96 then
		return c2
	end
	return Shading.softMix(c1, c2, k)
end

-- A member of a model's blended body (Raster.drawBlend): its texture set up when the member changes, then lit like any
-- textured part, with the union's normal as it comes (no leaning: the blend is the smooth surface).
-- A mark painted onto the face (Kit.blush; the request of 2026-11-16, "make the blushes drawn on instead of discs
-- too"): the pixel's point on the surface, in each mark's oval (across and up the face, and along its normal); inside,
-- the mark's colour, the head keeping its own light; on the edge, one step between the two (anti-aliased).
local PAINT_STRIDE = 15
SG.paintAt = function(rgb: number, x: number, y: number, t: number): number
	local cam = texCam
	if cam == nil then
		return rgb
	end
	local px = cam.ox + x * cam.ix + y * cam.jx + t * cam.lx
	local py = cam.oy + x * cam.iy + y * cam.jy + t * cam.ly
	local pz = cam.oz + x * cam.iz + y * cam.jz + t * cam.lz
	local P = SG.paints
	for k = 0, SG.paintN - 1 do
		local o = k * PAINT_STRIDE
		local dx, dy, dz = px - P[o + 1], py - P[o + 2], pz - P[o + 3]
		local c = dx * P[o + 10] + dy * P[o + 11] + dz * P[o + 12]
		if c > -1 and c < 1 then
			local a = dx * P[o + 4] + dy * P[o + 5] + dz * P[o + 6]
			local b = dx * P[o + 7] + dy * P[o + 8] + dz * P[o + 9]
			local e = math.sqrt(a * a + b * b)
			local half = 0.5 * texPx * P[o + 14]
			if e <= 1 - half then
				return P[o + 13]
			elseif e < 1 + half then
				local q = P[o + 13]
				local r = (bit32.rshift(rgb, 16) + bit32.rshift(q, 16)) // 2
				local g = (bit32.band(bit32.rshift(rgb, 8), 0xFF) + bit32.band(bit32.rshift(q, 8), 0xFF)) // 2
				local bb = (bit32.band(rgb, 0xFF) + bit32.band(q, 0xFF)) // 2
				return r * 65536 + g * 256 + bb
			end
		end
	end
	return rgb
end
-- (a plain lit part near a mark: shadeLit's look, per pixel so it can paint)
SG.shadePaint = function(rgb: number, nx: number, ny: number, nz: number, x: number, y: number, t: number?): number
	if t then
		rgb = (SG.paintAt :: any)(rgb, x, y, t)
	end
	return Shading.toonAt(rgb, nx, ny, nz, 1, x + panX, y + panY, Shading.INDOOR, 0)
end

SG.shadeMember = function(m: number, rgb: number, nx: number, ny: number, nz: number, x: number, y: number, t: number): number
	if m ~= SG.blendLast then
		SG.blendLast = m
		SG.paintOn = SG.blendPaint[m] == true
		local p = SG.blendP[m]
		texCF, texShape, texKind = SG.blendCf[m], p.shape, if SG.blendTex then p.tex else 0
		texOpt.seed, texOpt.v, texOpt.soft = p.texSeed or p.id % 97, p.texV, p.texSoft
		texOpt.role = 0
	end
	return shadeTex(rgb, nx, ny, nz, x, y, t)
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

-- A blob shadow's ellipse on layer s, under a dynamic model: its centre and radii in layer px, or nil when it casts
-- none now. The centre lies on a 1/64 px grid of the world's art grid and the radii on 1/64 px, so a pan leaves the
-- ellipse as it was and an incremental compose that draws it again draws the very pixels a whole compose does.
-- held: the kept picture the model shows (its shadow is cast from where the model stood when it was drawn).
function SG.shadowGeo(s: Surf, model: Model, first: BasePart, held: DynCache?): (number?, number, number, number)
	local radius = model:GetAttribute("PixelShadow")
	if type(radius) ~= "number" or radius <= 0 then
		return nil, 0, 0, 0
	end
	local g = model:GetAttribute("PixelGroundY")
	local ground = if type(g) == "number" then g else 0
	local p: Vector3
	if held then
		local at = held.shp
		if at == nil then
			return nil, 0, 0, 0
		end
		p = at
	else
		local pp = model.PrimaryPart or first
		-- a model out of sight casts none: hidden (see-through) or parked below its ground (a thing put away),
		-- which would else leave a blob on the floor where nothing stands
		if pp.Transparency >= 0.95 then
			return nil, 0, 0, 0
		end
		p = pp.Position
	end
	if p.Y < ground - 1 then
		return nil, 0, 0, 0
	end
	local h = math.max(0, p.Y - ground)
	local r = radius * math.clamp(1 - h / 26, 0.45, 1)
	local cam = s.cam
	local cx, cy = Raster.project(cam, p.X, ground, p.Z)
	local ex = Raster.project(cam, p.X + GROUND_R.X * r, ground, p.Z + GROUND_R.Z * r)
	local _, ey = Raster.project(cam, p.X + GROUND_D.X * r, ground, p.Z + GROUND_D.Z * r)
	local rx, ry = math.floor(math.abs(ex - cx) * 64 + 0.5) / 64, math.floor(math.abs(ey - cy) * 64 + 0.5) / 64
	if rx < 0.5 or ry < 0.5 then
		return nil, 0, 0, 0
	end
	local gx, gy = cam.gx, cam.gy
	return math.floor((cx + gx) * 64 + 0.5) / 64 - gx, math.floor((cy + gy) * 64 + 0.5) / 64 - gy, rx, ry
end

-- The layer rect a blob shadow of centre (cx, cy) and radii (rx, ry) can darken, a pixel round it.
function SG.shadowRect(cx: number, cy: number, rx: number, ry: number): (number, number, number, number)
	return math.floor(cx - rx) - 1, math.floor(cy - ry) - 1, math.ceil(cx + rx) + 1, math.ceil(cy + ry) + 1
end

-- studs over a model's ground (PixelGroundY) a surface may stand and still take its blob shadow (paths, flowers, a
-- low step); a higher one (a roof, an awning, a wall in front of it) does not
local SHADOW_LIFT = 0.9

-- A blob shadow under a dynamic model; returns its rect on the layer (nil when none shows). The ellipse may be given
-- (SG.shadowGeo's), else it is worked out.
local function drawShadow(s: Surf, model: Model, first: BasePart, gcx: number?, gcy: number?, grx: number?, gry: number?, clip: boolean?): Rect?
	local cx, cy, rx, ry
	if gcx and gcy and grx and gry then
		cx, cy, rx, ry = gcx, gcy, grx, gry
	else
		local ax, ay, arx, ary = SG.shadowGeo(s, model, first)
		if ax == nil then
			return nil
		end
		cx, cy, rx, ry = ax, ay, arx, ary
	end
	local W, H = s.W, s.H
	local f = s.frame
	local y0, y1 = math.max(0, math.floor(cy - ry)), math.min(H - 1, math.ceil(cy + ry))
	local any = false
	-- (clip: only in the incremental compose's marked tiles, where the frame was put back to the static picture)
	local T, bits, cols = SG.TILE, SG.bits, SG.tcols
	-- Only on the ground the model stands on. The report of 2026-11-18, "also, shadows clip through buildings": a
	-- driftling walking behind a stall had its blob darken the stall's awning, which stood in front of it on the
	-- screen. A static pixel's surface lies where its ray met it (Raster.origin plus the look times its depth), and
	-- one higher than SHADOW_LIFT over the model's ground is a roof, a wall or a sign: the blob passes it by.
	local g = model:GetAttribute("PixelGroundY")
	local top = (if type(g) == "number" then g else 0) + SHADOW_LIFT
	local cam = s.cam
	local ly, iy, sDepth = cam.ly, cam.iy, s.sDepth
	for y = y0, y1 do
		local dy = (y + 0.5 - cy) / ry
		if math.abs(dy) < 1 then
			local half = rx * math.sqrt(1 - dy * dy)
			local x0, x1 = math.max(0, math.floor(cx - half + 0.5)), math.min(W - 1, math.floor(cx + half + 0.5) - 1)
			local trow = (y // T) * cols
			-- (the rays' height at the row's left: Raster.origin's y)
			local oy0 = cam.goy + cam.gx * iy + (y + cam.gy) * cam.jy
			for x = x0, x1 do
				if clip and buffer.readu8(bits, trow + x // T) == 0 then
					continue
				end
				local idx = y * W + x
				local id = buffer.readu16(f.id, idx * 2)
				-- the static picture only, never its ink lines or the sky, and only at the model's ground
				if id ~= 0 and id < DYN_ID0 and oy0 + x * iy + ly * buffer.readf32(sDepth, idx * 4) <= top and (buffer.readu32(s.sColor, idx * 4) == buffer.readu32(s.sShade, idx * 4) or (buffer.readu8(s.sWClass, idx) ~= 0 and buffer.readu8(s.sWClass, idx) <= 3)) then
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
	-- (the sticky effect pixels over it again)
	local sc = stickCol
	if stickLive > 0 and sc and buffer.len(sc) == W * s.H * 4 then
		for y = y0, y1 do
			local row = y * W
			for x = x0, x1 do
				local c = buffer.readu32(sc, (row + x) * 4)
				if c ~= 0 then
					buffer.writeu32(f.color, (row + x) * 4, c)
				end
			end
		end
	end
end

------------------------------------------------------------------ water
-- A water pixel's colour at frame k: its baked shade, lit along a crest, darker in the sea's troughs, the foam
-- drawing back toward the shallows' colour now and then.
local function waterTone(cls: number, ph: number, k: number): number
	if cls == 3 then
		return if (ph + k * 3) % 32 < 20 then 0 else 3
	elseif cls == 6 then
		-- falling water: a pale streak and a lighter band under it running down (the request of 2026-11-14,
		-- "waterfalls having flowing water")
		local t = (ph + k * 3) % 14
		return if t < 2 then 1 elseif t < 4 then 3 else 0
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
	local key = base * 32 + cls * 4 + tone -- (cls up to 6: room for it)
	local c = waterTones[key]
	if c == nil then
		if tone == 1 then
			c = mixShaded(WATER_CREST, base, if cls == 2 then 0.4 elseif cls == 6 then 0.45 else 0.34)
		elseif cls == 6 then
			c = mixShaded(WATER_CREST, base, 0.18)
		elseif tone == 2 then
			c = mixShaded(WATER_DEEP, base, 0.18)
		else
			c = mixShaded(WATER_SHALLOW, base, 0.55)
		end
		waterTones[key] = c
	end
	return c :: number
end

-- The water tones of the frame before and the frame now, by class and wave phase (index class * 256 + phase + 1;
-- -1: a class the water pass leaves alone, leaves and flags).
function SG.waterTables(k: number)
	local was, now = SG.waterWas, SG.waterNow
	for c = 0, 6 do
		for ph = 0, 255 do
			local j = c * 256 + ph + 1
			if c == 0 or c == 4 or c == 5 then
				was[j], now[j] = -1, -1
			else
				was[j], now[j] = waterTone(c, ph, k - 1), waterTone(c, ph, k)
			end
		end
	end
end

-- The water's next frame, worked out a slice at a time and put on the picture all at once (the request of 2026-11-16,
-- "is there any way to optimize the camera movement? it is still very laggy when moving around": the pass over every
-- pixel of the layer was a 20 to 30 ms hitch six times a second, standing or walking). A slice is every
-- SG.WATER_SLICES-th row of the world's art grid (a pan in between moves no pixel into another slice); the frame's
-- period sees them all, a few rows a frame. In a slice, a water pixel not under an ink line (its colour its baked
-- shade or this frame's) whose tone changes for the next frame (most of the sea, most frames, keeps its tone: the
-- crest is two steps of the sixty-four), or every one when SG.waterAll asks (after a whole bake), goes in the pending
-- list: its global art px, the colour it has and the one it takes. `SG.waterApply` puts them on when the frame comes.
function SG.waterSlice(s: Surf, j: number)
	local S = SG.WATER_SLICES
	if j == 0 then
		SG.waterTables(waterFrame + 1)
		SG.waterAllNow = SG.waterAll
		SG.waterAll = false
		SG.waterPendN = 0
	end
	local W, H = s.W, s.H
	local cls, wave, shade, color = s.sWClass, s.sWave, s.sShade, s.sColor
	local was, now = SG.waterWas, SG.waterNow
	local all = SG.waterAllNow
	local pend = SG.waterPend
	local pn = SG.waterPendN
	local gx0, gy0 = s.cam.gx, s.cam.gy
	for y = (j - gy0) % S, H - 1, S do
		local row = y * W
		for x = 0, W - 1 do
			local i = row + x
			local c = buffer.readu8(cls, i)
			if c ~= 0 then
				local jj = c * 256 + buffer.readu8(wave, i) + 1
				local t1 = now[jj]
				if t1 >= 0 then
					local t0 = was[jj]
					if t1 ~= t0 or all then
						local base = buffer.readu32(shade, i * 4)
						local cur = buffer.readu32(color, i * 4)
						if cur == base or cur == waterColor(base, c, t0) then
							local nc = waterColor(base, c, t1)
							if nc ~= cur then
								pend[pn + 1], pend[pn + 2], pend[pn + 3], pend[pn + 4] = x + gx0, y + gy0, cur, nc
								pn += 4
							end
						end
					end
				end
			end
		end
	end
	SG.waterPendN = pn
end

-- The water frame worked out by the slices, put on the layer: each pending pixel still on it and still the colour it
-- had (a pan, a re-cast or the wind may have changed it since) takes its new one. True when any changed.
function SG.waterApply(s: Surf): boolean
	local W, H = s.W, s.H
	local color, ids = s.sColor, s.sId
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local pend = SG.waterPend
	-- (a water pixel's graded colour from a little table of its own, by colour and part: the sea is a few colours,
	-- and grading each written pixel on its own took most of the time; with the lamps' pools on, the plain way)
	local gb = SG.buf
	local gOn = SG.ok and SG.on == s and gb ~= nil
	local lamps = grade ~= nil and (grade :: Grade).lamps > 0 and lightMap ~= nil
	local wkey = gradeKey .. "|" .. dim
	if SG.waterGradeKey ~= wkey then
		table.clear(SG.waterGrade)
		SG.waterGradeKey = wkey
	end
	local wg = SG.waterGrade
	local changed = false
	local inc = not needFull and SG.live(s)
	for k = 1, SG.waterPendN, 4 do
		local x, y = pend[k] - gx0, pend[k + 1] - gy0
		if x >= 0 and y >= 0 and x < W and y < H then
			local i = y * W + x
			local was = pend[k + 2]
			if buffer.readu32(color, i * 4) == was then
				local nc = pend[k + 3]
				buffer.writeu32(color, i * 4, nc)
				changed = true
				if gOn and not lamps then
					local key = nc * 65536 + buffer.readu16(ids, i * 2)
					local o = wg[key]
					if o == nil then
						gradeSpan(color, ids, i, 1, gb :: buffer, i)
						wg[key] = buffer.readu32(gb :: buffer, i * 4)
					else
						buffer.writeu32(gb :: buffer, i * 4, o)
					end
				elseif gOn then
					SG.px(s, i)
				end
				if inc then
					-- (composing incrementally: the frame takes it now, SG.sync)
					SG.sync(s, i, was, nc)
				end
			end
		end
	end
	SG.waterPendN = 0
	return changed
end

-- The water of a layer rect just cast or inked again (its colours are the bare shade) put at the frame now, so a
-- strip a pan brings in shows the same sea as the rest; where its slice was already worked out this period, its next
-- frame goes in the pending list too. The caller grades the rect again.
function SG.waterFix(s: Surf, x0: number, y0: number, x1: number, y1: number)
	if tier == "low" then
		return
	end
	x0, y0 = math.max(0, x0), math.max(0, y0)
	x1, y1 = math.min(s.W - 1, x1), math.min(s.H - 1, y1)
	local cls, wave, shade, color = s.sWClass, s.sWave, s.sShade, s.sColor
	local k = waterFrame
	local S = SG.WATER_SLICES
	local done = SG.waterDone
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local pend = SG.waterPend
	for y = y0, y1 do
		local row = y * s.W
		local later = (y + gy0) % S < done
		for x = x0, x1 do
			local i = row + x
			local c = buffer.readu8(cls, i)
			if c ~= 0 and (c <= 3 or c == 6) then
				local base = buffer.readu32(shade, i * 4)
				if buffer.readu32(color, i * 4) == base then
					local ph = buffer.readu8(wave, i)
					local nc = waterColor(base, c, waterTone(c, ph, k))
					if nc ~= base then
						buffer.writeu32(color, i * 4, nc)
					end
					if later then
						local nx = waterColor(base, c, waterTone(c, ph, k + 1))
						if nx ~= nc then
							local pn = SG.waterPendN
							pend[pn + 1], pend[pn + 2], pend[pn + 3], pend[pn + 4] = x + gx0, y + gy0, nc, nx
							SG.waterPendN = pn + 4
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------ the wind
-- The wind's pass (leaves rustling at a canopy's edge, flags rippling: 2026-11-14 to 2026-11-20) went with the request
-- of 2026-11-20, "the outlines are still broken on the tree. no need to add rustling to the tree and other objects
-- anymore, these cause broken outlines": it moved pixels of the outline itself. Nothing paints the wind now; its
-- undo (`windRestore`) has nothing to undo.

------------------------------------------------------------------ effect layers (Render/Fx)
-- Two books of written pixels swap every tick: the ones last tick's effects wrote (put back to the static picture
-- before the dynamic layer is drawn) and this tick's. `fxShown` holds, per layer pixel, the effect colour the image
-- shows there (0: none), its top byte the tick's mark (1 or 2, alternating) instead of the alpha: a pixel written
-- this tick whose colour differs, or one last tick's effects left, marks its 16 x 8 tile, and the tiles' runs are
-- uploaded. The static picture under an effect at rest costs nothing to keep.
type FxLayer = { name: string, draw: (ctx: Fx.Ctx) -> (), last: number }
local fxLayers: { FxLayer } = {}
local fxStats = { ms = 0, bookMs = 0, px = 0, changed = 0, rects = 0, upPx = 0, ticks = 0, layers = 0 }
local fxPrev, fxCur = Fx.newBook(), Fx.newBook()
local fxPrevN = 0
local fxCtx: Fx.Ctx? = nil
local fxShown: buffer? = nil
local fxTiles: buffer? = nil
local fxMark = 1 -- this tick's mark (1 or 2)
local fxOn: Surf? = nil -- the layer the books belong to
local FX_TW, FX_TH = 16, 8 -- an upload tile (art px)
local FX_MAX_RUNS = 40 -- more runs than this: one rect a row of tiles

-- The books for layer s (a new layer starts them afresh: its picture is uploaded whole anyway).
local function fxBooks(s: Surf)
	local n = s.W * s.H
	local shownBuf = fxShown
	if fxOn ~= s or shownBuf == nil or buffer.len(shownBuf) ~= n * 4 then
		fxOn = s
		fxPrevN = 0
		fxShown = buffer.create(n * 4)
		fxTiles = buffer.create(((s.W + FX_TW - 1) // FX_TW) * ((s.H + FX_TH - 1) // FX_TH))
		stickCol = buffer.create(n * 4)
		table.clear(stickList)
		table.clear(stickDirty)
		stickLive = 0
		staticVer += 1
	end
end

-- Put the static picture back where last tick's effects drew (the dynamic layer is drawn over it again anyway).
local function fxRestore(s: Surf)
	local f = s.frame
	local color, id = f.color, f.id
	local len = s.W * s.H
	local sc = stickCol :: buffer
	for k = 0, fxPrevN - 1 do
		local i = buffer.readu32(fxPrev, k * 4)
		if i < len then
			local c = buffer.readu32(sc, i * 4)
			buffer.writeu32(color, i * 4, if c ~= 0 then c else buffer.readu32(s.sColor, i * 4))
			buffer.writeu16(id, i * 2, buffer.readu16(s.sId, i * 2))
		end
	end
end

-- Stick colour c at layer pixel i (Fx.stickSprite): kept until unstuck or the static picture changes; drawn into the
-- frame now where it shows the static picture (a model over it keeps it hidden).
local function stickAt(i: number, c: number)
	local s = surf
	local sc = stickCol
	if s == nil or sc == nil or i * 4 >= buffer.len(sc) then
		return
	end
	local old = buffer.readu32(sc, i * 4)
	if old == 0 then
		table.insert(stickList, i)
		stickLive += 1
	end
	buffer.writeu32(sc, i * 4, c)
	SG.stickPut(s, i, old, c)
	table.insert(stickDirty, i)
end

local function unstickAt(i: number)
	local s = surf
	local sc = stickCol
	if s == nil or sc == nil or i * 4 >= buffer.len(sc) or buffer.readu32(sc, i * 4) == 0 then
		return
	end
	local old = buffer.readu32(sc, i * 4)
	buffer.writeu32(sc, i * 4, 0)
	stickLive -= 1
	SG.stickPut(s, i, old, buffer.readu32(s.sColor, i * 4))
	table.insert(stickDirty, i)
	-- (the list keeps unstuck pixels until it is twice what is stuck: then it is rebuilt)
	if #stickList > stickLive * 2 + 512 then
		local keep: { number } = {}
		local seen: { [number]: boolean } = {}
		for _, k in stickList do
			if not seen[k] and buffer.readu32(sc, k * 4) ~= 0 then
				seen[k] = true
				table.insert(keep, k)
			end
		end
		stickList = keep
	end
end

-- Run the effect layers (newest first) over the composed frame; returns the rects whose pixels changed.
local function runFx(s: Surf, now: number): { Rect }
	local W, H = s.W, s.H
	local cam = s.cam
	local c: Fx.Ctx = fxCtx or {
		f = s.frame,
		W = W,
		H = H,
		cam = cam,
		sColor = s.sColor,
		sId = s.sId,
		sNormal = s.sNormal,
		sAlbedo = s.sAlbedo,
		sDepth = s.sDepth,
		sWClass = s.sWClass,
		ppu = cam.s / cam.K,
		ver = staticVer,
		now = now,
		dt = 0,
		idOf = function(inst: any): number
			return if typeof(inst) == "Instance" then (staticIds[inst] or 0) else 0
		end,
		stick = stickAt,
		unstick = unstickAt,
		px = fxCur,
		npx = 0,
		cap = buffer.len(fxCur) // 4,
	}
	fxCtx = c
	c.f, c.W, c.H, c.cam = s.frame, W, H, cam
	c.sColor, c.sId, c.sNormal, c.sAlbedo, c.sDepth, c.sWClass = s.sColor, s.sId, s.sNormal, s.sAlbedo, s.sDepth, s.sWClass
	c.ppu = cam.s / cam.K
	c.ver = staticVer
	c.now = now
	c.px, c.cap = fxCur, buffer.len(fxCur) // 4
	Fx.reset(c)
	local t0 = SG.clock()
	for i = #fxLayers, 1, -1 do
		local L = fxLayers[i]
		c.dt = math.clamp(now - L.last, 0, 0.25)
		L.last = now
		local f: any = L.draw -- (typed through any: pcall mis-infers the returns of a () -> () function)
		local ok, err = pcall(f, c)
		if not ok then
			warn("[PixelRenderer] effect layer " .. L.name .. " failed and was removed: " .. tostring(err))
			table.remove(fxLayers, i)
			fxStats.layers = #fxLayers
			staticChanged()
			needFull = true
			SG.ok = false
			SG.ver += 1
		end
	end
	local t1 = SG.clock()
	-- what changed: this tick's pixels against what the image shows, and the pixels the effects left
	local shown, tiles = fxShown :: buffer, fxTiles :: buffer
	local color = s.frame.color
	local tx = (W + FX_TW - 1) // FX_TW
	buffer.fill(tiles, 0, 0)
	fxMark = 3 - fxMark
	local mark = fxMark * 16777216
	local written, n = c.px, c.npx
	local changed = 0
	for k = 0, n - 1 do
		local i = buffer.readu32(written, k * 4)
		local col = buffer.readu32(color, i * 4) % 16777216 + mark
		local was = buffer.readu32(shown, i * 4)
		if was ~= col then
			buffer.writeu32(shown, i * 4, col)
			-- (only the colour counts: a pixel shown last tick in the same colour needs no upload)
			if was % 16777216 ~= col % 16777216 or was == 0 then
				buffer.writeu8(tiles, ((i // W) // FX_TH) * tx + (i % W) // FX_TW, 1)
				changed += 1
			end
		end
	end
	local len = W * H
	for _, i in stickDirty do
		if i < len then
			buffer.writeu8(tiles, ((i // W) // FX_TH) * tx + (i % W) // FX_TW, 1)
			changed += 1
		end
	end
	table.clear(stickDirty)
	for k = 0, fxPrevN - 1 do
		local i = buffer.readu32(fxPrev, k * 4)
		if i < len then
			local was = buffer.readu32(shown, i * 4)
			if was ~= 0 and was - was % 16777216 ~= mark then
				buffer.writeu32(shown, i * 4, 0)
				buffer.writeu8(tiles, ((i // W) // FX_TH) * tx + (i % W) // FX_TW, 1)
				changed += 1
			end
		end
	end
	-- the books swap (Fx.put may have grown this tick's)
	fxPrev, fxCur = written, fxPrev
	fxPrevN = n
	c.px, c.cap = fxCur, buffer.len(fxCur) // 4
	-- the changed tiles in runs along their rows (a gap of one clean tile joins two runs)
	local out: { Rect } = {}
	if changed > 0 then
		local ty = (H + FX_TH - 1) // FX_TH
		for row = 0, ty - 1 do
			local o = row * tx
			local a = -1
			local last = -1
			for col = 0, tx - 1 do
				if buffer.readu8(tiles, o + col) ~= 0 then
					if a < 0 then
						a = col
					elseif col - last > 2 then
						table.insert(out, { x0 = a * FX_TW, y0 = row * FX_TH, x1 = (last + 1) * FX_TW - 1, y1 = (row + 1) * FX_TH - 1 })
						a = col
					end
					last = col
				end
			end
			if a >= 0 then
				table.insert(out, { x0 = a * FX_TW, y0 = row * FX_TH, x1 = (last + 1) * FX_TW - 1, y1 = (row + 1) * FX_TH - 1 })
			end
		end
		if #out > FX_MAX_RUNS then
			-- too many: one rect a row of tiles, from its first changed tile to its last
			local rows: { [number]: Rect } = {}
			for _, r in out do
				local have = rows[r.y0]
				if have then
					have.x0, have.x1 = math.min(have.x0, r.x0), math.max(have.x1, r.x1)
				else
					rows[r.y0] = { x0 = r.x0, y0 = r.y0, x1 = r.x1, y1 = r.y1 }
				end
			end
			out = {}
			for _, r in rows do
				table.insert(out, r)
			end
		end
	end
	local up = 0
	for _, r in out do
		up += (math.min(r.x1, W - 1) - r.x0 + 1) * (math.min(r.y1, H - 1) - r.y0 + 1)
	end
	fxStats.ms = (t1 - t0) * 1000
	fxStats.bookMs = (SG.clock() - t1) * 1000
	fxStats.px = n
	fxStats.changed = changed
	fxStats.rects = #out
	fxStats.upPx = up
	fxStats.ticks += 1
	return out
end

------------------------------------------------------------------ the founders' rims
-- The scratch window a rim's silhouette is drawn into (grown on demand, never shrunk) and a far depth to clear it with.
-- (one table: the renderer's main chunk is at Luau's 200 registers; number constants cost none)
local Rims = {
	rgb = Palette.colors.white or 0xFFFFFF,
	max = 8, -- MAX_RIMS
	-- the scratch window a rim's silhouette is drawn into (grown on demand, never shrunk) and a far depth to clear it
	-- with
	mask = { W = 0, H = 0, color = buffer.create(0), depth = buffer.create(0), id = buffer.create(0) } :: Raster.Frame,
	cap = 0,
	far = buffer.create(0),
	list = {} :: { Dyn }, -- this tick's founders drawn, and each one's parts' rect (clipped to the layer)
	rects = {} :: { Rect },
	stats = { drawn = 0, px = 0, ms = 0 },
}
function Rims.flat(_rgb: number, _nx: number, _ny: number, _nz: number, _x: number, _y: number): number
	return 0
end
Raster.markUniform(Rims.flat)

-- The white rim of founder e, whose parts (drawn this tick) cover layer rect r. Returns the rim pixels laid.
function Rims.draw(s: Surf, e: Dyn, r: Rect): number
	local w, h = r.x1 - r.x0 + 1, r.y1 - r.y0 + 1
	if w <= 0 or h <= 0 then
		return 0
	end
	local n = w * h
	local m = Rims.mask
	if n > Rims.cap then
		local cap = math.max(n, Rims.cap * 2)
		Rims.cap = cap
		m.color = buffer.create(cap * 4)
		m.depth = buffer.create(cap * 4)
		m.id = buffer.create(cap * 2)
		local far = buffer.create(cap * 4)
		for i = 0, cap - 1 do
			buffer.writef32(far, i * 4, FAR)
		end
		Rims.far = far
	end
	m.W, m.H = w, h
	buffer.fill(m.id, 0, 0, n * 2)
	buffer.copy(m.depth, 0, Rims.far, 0, n * 4)
	local wcam = Raster.window(s.cam, r.x0, r.y0, w, h)
	for _, p in e.parts do
		local part = p.part
		if part.Parent ~= nil and part.Transparency < 0.95 then
			local sz = part.Size
			Raster.drawPart(m, wcam, p.shape, { part.CFrame:GetComponents() }, sz.X, sz.Y, sz.Z, 0, p.id, Rims.flat, nil, p.prm)
		end
	end
	return Shading.rim(s.frame, m, r.x0, r.y0, Rims.rgb, Rims.rgb, nil, true, s.cam.gx, s.cam.gy)
end

-- Every founder drawn this tick gets its rim (at most Rims.max: the own one first, then the nearest to (cx, cy)).
function Rims.drawAll(s: Surf, cx: number, cy: number)
	local t0 = SG.clock()
	local list, rects = Rims.list, Rims.rects
	local nr = #list
	if nr > Rims.max then
		local order = {}
		for i = 1, nr do
			local r = rects[i]
			local mx, my = (r.x0 + r.x1) * 0.5 - cx, (r.y0 + r.y1) * 0.5 - cy
			order[i] = { e = list[i], r = r, k = if list[i].own then -1 else mx * mx + my * my }
		end
		table.sort(order, function(x, y)
			return x.k < y.k
		end)
		for i = 1, nr do
			list[i], rects[i] = order[i].e, order[i].r
		end
		nr = Rims.max
	end
	local px = 0
	for i = 1, nr do
		px += Rims.draw(s, list[i], rects[i])
	end
	local st = Rims.stats
	st.drawn, st.px, st.ms = nr, px, (SG.clock() - t0) * 1000
	table.clear(list)
	table.clear(rects)
end

------------------------------------------------------------------ the moving models' kept pictures (DynCache)
-- The request of 2026-11-15: "the camera moving is always very laggy". A moving model that stands still (an egg on the
-- lawn between its rocks, a hut's sign) is not drawn again every tick: its pixels from the last draw are put back where
-- they belong on the layer (the grid is the world's, so a pan only moves them by whole art px), depth tested as the
-- draw would be. A kept picture is used while every part stands as it did, the static picture is the same (SG.ver: a
-- pan keeps it), the scale is the same and the model lies wholly on the layer. While the camera pans every frame is
-- composed, but the moving models still change at the tier's hz like everywhere else: on a frame between two of
-- those a model shows its kept picture even when it has moved since, except the founders (the camera follows the
-- player's own, and a founder's white rim is drawn round where it stands now).
local PX_BYTES = 14 -- a kept pixel: dx u16, dy u16, colour u32, depth f32, id u16
-- A model that says which pose it is in (PixelRenderer.pose: the hatch scene's egg, rocking, wobbling and shaking
-- through the same few poses) keeps a picture for each of up to POSE_KEEP poses: posed again in one it had, that
-- picture is put down (slid to where the model stands, SG.glideOf) in place of a draw. The user's report of 2026-11-21:
-- "it still is pretty laggy while hatching, even when the egg is dropping down".
local POSE_KEEP = 32

-- Parts as they stand now against a snapshot (cfs, szs, gone); nil snapshot: never the same.
function SG.same(d: Dyn, cfs: { CFrame }?, szs: { Vector3 }?, gone: { boolean }?): boolean
	if cfs == nil or szs == nil or gone == nil then
		return false
	end
	for i, p in d.parts do
		local part = p.part
		if part.CFrame ~= cfs[i] or part.Size ~= szs[i] or (part.Parent == nil or part.Transparency >= 0.95) ~= gone[i] then
			return false
		end
	end
	return true
end

-- Model d drawn afresh. It goes into a scratch frame of its own (SG.isoFor: far and empty), so its picture is the whole
-- model whatever else stands on the layer; the picture is kept (Dyn.cache) and put down on the frame depth tested, as a
-- draw straight onto it would be. A kept picture stands for the model on a later tick while it has not moved, or past
-- the tick's budget wherever it last stood. Before (the stress test of 2026-11-17, "do a stress test with the maximum
-- amount of decor and buildings at the highest expansion level"), a model that moved every tick was kept only while the
-- view panned and only with no other model in its rect, so in a crowd past the budget about 48 models a frame had no
-- picture at all and were left out. A model partly off the layer is put down from the scratch and not kept. The
-- scratch is wiped where it drew. Returns the layer rect its parts cover (x0 > x1: none).
function SG.drawPic(s: Surf, d: Dyn, ppu: number, texOn: boolean): (DynCache?, number, number, number, number)
	local iso, icam = SG.isoFor(s)
	local M = SG.ISO_M
	-- (drawn at the scratch's camera: a window M px larger all round, so a model standing past the layer's edge is
	-- drawn whole; the shades read their pixel's global art px and world point from it)
	local px0, py0, tc0 = panX, panY, texCam
	panX, panY, texCam = icam.gx, icam.gy, icam
	local ix0, iy0, ix1, iy1 = SG.drawModel(iso, d, icam, texOn)
	panX, panY, texCam = px0, py0, tc0
	local cfs, szs, gone = {}, {}, {}
	for i, p in d.parts do
		local part = p.part
		cfs[i], szs[i], gone[i] = part.CFrame, part.Size, part.Parent == nil or part.Transparency >= 0.95
	end
	local IW, IH = iso.W, iso.H
	local cx0, cy0 = math.max(0, math.floor(ix0)), math.max(0, math.floor(iy0))
	local cx1, cy1 = math.min(IW - 1, math.ceil(ix1)), math.min(IH - 1, math.ceil(iy1))
	-- (the layer rect its parts cover)
	local x0, y0, x1, y1 = ix0 - M, iy0 - M, ix1 - M, iy1 - M
	if cx0 > cx1 or cy0 > cy1 then
		d.cache = { gx = 0, gy = 0, w = 0, h = 0, n = -1, px = SG.none, cfs = cfs, szs = szs, gone = gone, ver = -1, ppu = ppu }
		return nil, x0, y0, x1, y1
	end
	local color, depth, ids = iso.color, iso.depth, iso.id
	local n = 0
	for y = cy0, cy1 do
		local row = y * IW
		for x = cx0, cx1 do
			if buffer.readu16(ids, (row + x) * 2) ~= 0 then
				n += 1
			end
		end
	end
	local px = buffer.create(math.max(1, n) * PX_BYTES)
	local k = 0
	for y = cy0, cy1 do
		local row = y * IW
		for x = cx0, cx1 do
			local i = row + x
			local id = buffer.readu16(ids, i * 2)
			if id ~= 0 then
				local o = k * PX_BYTES
				buffer.writeu16(px, o, x - cx0)
				buffer.writeu16(px, o + 2, y - cy0)
				buffer.writeu32(px, o + 4, buffer.readu32(color, i * 4))
				buffer.writef32(px, o + 8, buffer.readf32(depth, i * 4))
				buffer.writeu16(px, o + 12, id)
				k += 1
			end
		end
		-- (the scratch wiped behind it)
		local i = row + cx0
		buffer.copy(depth, i * 4, SG.farRow :: buffer, 0, (cx1 - cx0 + 1) * 4)
		buffer.fill(ids, i * 2, 0, (cx1 - cx0 + 1) * 2)
	end
	-- (whole: nothing of it fell past the scratch's edge)
	local whole = ix0 >= 0 and iy0 >= 0 and ix1 <= IW - 1 and iy1 <= IH - 1
	local pp = d.model.PrimaryPart or d.parts[1].part
	local lx0, ly0 = cx0 - M, cy0 - M
	local pic: DynCache = { gx = lx0 + s.cam.gx, gy = ly0 + s.cam.gy, w = cx1 - cx0 + 1, h = cy1 - cy0 + 1, n = n, px = px, cfs = cfs, szs = szs, gone = gone, ver = SG.ver, ppu = ppu, shp = if pp.Transparency < 0.95 then pp.Position else nil, anchor = d.gPosed }
	if whole then
		d.cache = pic
		local key = d.poseKey
		if key then
			local poses, order = d.poses or {}, d.poseOrder or {}
			d.poses, d.poseOrder = poses, order
			if poses[key] == nil then
				table.insert(order, key)
				if #order > POSE_KEEP then
					poses[table.remove(order, 1) :: string] = nil
				end
			end
			poses[key] = pic
		end
	else
		d.cache = { gx = 0, gy = 0, w = 0, h = 0, n = -1, px = SG.none, cfs = cfs, szs = szs, gone = gone, ver = -1, ppu = ppu }
	end
	return pic, lx0, ly0, lx0 + pic.w - 1, ly0 + pic.h - 1
end

-- What every moving model shows this compose and the blob shadow under it (both composes work from it): a model on the
-- layer shows its kept picture when one stands for it this tick (SG.blitOk), else it is drawn afresh into its own
-- scratch (SG.drawPic) within the tick's budget (Tuning.PixelDynMs of drawing and Tuning.PixelMaxDyn models; the
-- founders always), the founders first, then a model with no picture at all, then the longest undrawn; past the
-- budget it shows its kept picture a tick longer, where it last stood, or (with none) nothing. Its shadow is the
-- picture's (cast from where the model stood when it was drawn), so the two go together; a model off the layer or with
-- nothing to show casts its shadow from where it stands. Entries: the model, its picture and the layer rect it covers
-- (pic nil: none), its shadow's centre and radii in layer px (sx nil: none).
-- (dz: the depth its kept picture goes down with, gx, gy: how far it slid with the model, SG.glideOf)
type PlanEntry = { d: Dyn, pic: DynCache?, x0: number, y0: number, x1: number, y1: number, dz: number, gx: number, gy: number, sx: number?, sy: number, srx: number, sry: number }

-- How far model d has walked on since kept picture c was drawn (PixelRenderer.glide: a driftling between two of its
-- poses): whole art px across and down the layer, and the depth to add to its pixels. The request of 2026-11-18, "make
-- it such that overworld creatures move smoother": on a busy island a driftling is posed a few times a second (its
-- pose and its picture within their budgets), and its picture stood still between poses and then jumped 4 to 7 px.
-- Now the picture slides with it every tick by whole art px, and only its pose waits for the budget. (The grid is the
-- world's, so the slide is the same at every pan.)
function SG.glideOf(s: Surf, d: Dyn, c: DynCache): (number, number, number)
	local now, at = d.gNow, c.anchor
	if now == nil or at == nil then
		return 0, 0, 0
	end
	local qx, qy, qz = now.X - at.X, now.Y - at.Y, now.Z - at.Z
	if qx == 0 and qy == 0 and qz == 0 then
		return 0, 0, 0
	end
	local cam = s.cam
	local k = cam.s / cam.K
	local a = qx * cam.rx + qy * cam.ry + qz * cam.rz
	local b = qx * cam.ux + qy * cam.uy + qz * cam.uz
	return math.floor(a * k + 0.5), math.floor(-b * k + 0.5), qx * cam.lx + qy * cam.ly + qz * cam.lz
end

function SG.plan(s: Surf, fresh: boolean, ppu: number, texOn: boolean): { PlanEntry }
	local cam = s.cam
	local W, H = s.W, s.H
	local out: { PlanEntry } = {}
	local need = SG.need
	table.clear(need)
	local at: { [Dyn]: PlanEntry } = {}
	-- (picture c over layer rect x0..y1 for entry e, slid on with its model: nothing when that takes it off the layer)
	local function put(e: PlanEntry, d: Dyn, c: DynCache, x0: number, y0: number, x1: number, y1: number)
		local gx, gy, gz = SG.glideOf(s, d, c)
		x0, y0, x1, y1 = x0 + gx, y0 + gy, x1 + gx, y1 + gy
		if x1 < 0 or y1 < 0 or x0 > W - 1 or y0 > H - 1 then
			return
		end
		e.pic, e.x0, e.y0, e.x1, e.y1, e.dz, e.gx, e.gy = c, x0, y0, x1, y1, gz - (d.lead or 0), gx, gy
	end
	for model, d in dyns do
		local first = d.parts[1]
		local culled = model.Parent == nil or first == nil
		if not culled then
			local fp = (first :: DynPart).part.Position
			local fx, fy = Raster.project(cam, fp.X, fp.Y, fp.Z)
			culled = fx < -CULL or fy < -CULL or fx > W + CULL or fy > H + CULL
		end
		-- (off the layer now and nothing of it on the layer from before: no entry, nothing to show or to take off. A model
		-- far away got a new entry every compose: the other islands' moving pieces, the boats and gulls out at sea, every
		-- other founder)
		if culled and d.shR == nil and d.sR == nil then
			continue
		end
		local e: PlanEntry = { d = d, pic = nil, x0 = 0, y0 = 0, x1 = -1, y1 = -1, dz = 0, gx = 0, gy = 0, sx = nil, sy = 0, srx = 0, sry = 0 }
		table.insert(out, e)
		at[d] = e
		if culled then
			continue
		end
		local c, x0, y0, x1, y1 = SG.blitOk(s, d, fresh, ppu)
		if c then
			put(e, d, c, x0, y0, x1, y1)
		elseif not SG.offPic(s, d, ppu) or not SG.same(d, (d.cache :: DynCache).cfs, (d.cache :: DynCache).szs, (d.cache :: DynCache).gone) then
			-- (a model whose picture lies wholly off the layer and has not moved shows nothing and needs no draw)
			table.insert(need, d)
		end
	end
	if #need > 1 then
		table.sort(need, function(a: Dyn, b: Dyn): boolean
			local ao, bo = a.own == true or a.rim == true, b.own == true or b.rim == true
			if ao ~= bo then
				return ao
			end
			-- (one whose last picture lay wholly off the layer comes last: it most likely still does)
			local af, bf = SG.offPic(s, a, ppu), SG.offPic(s, b, ppu)
			if af ~= bf then
				return bf
			end
			-- (then a model with no picture to show, which past the budget would be left out)
			local an, bn = SG.bare(a, ppu), SG.bare(b, ppu)
			if an ~= bn then
				return an
			end
			return (a.drawnAt or 0) < (b.drawnAt or 0)
		end)
	end
	local budgetEnd = SG.clock() + Tuning.PixelDynMs / 1000
	local drawn = 0
	for _, d in need do
		local e = at[d]
		if not SG.noBudget and (drawn >= Tuning.PixelMaxDyn or SG.clock() > budgetEnd) and not d.own and not d.rim then
			local c, x0, y0, x1, y1 = SG.blitOk(s, d, false, ppu)
			if c then
				put(e, d, c, x0, y0, x1, y1)
			else
				SG.skips += 1
				local k = d.cache
				local why = if k == nil then "never drawn" elseif k.n < 0 then "not kept" elseif k.ver ~= SG.ver then "old picture" elseif k.ppu ~= ppu then "other scale" else "moved, last seen off the layer"
				SG.skipWhy[why] = (SG.skipWhy[why] or 0) + 1
			end
			continue
		end
		drawn += 1
		local pic, x0, y0, x1, y1 = SG.drawPic(s, d, ppu, texOn)
		d.drawnAt = SG.clock()
		SG.draws += 1
		if pic then
			put(e, d, pic, x0, y0, x1, y1)
		end
	end
	for _, e in out do
		local d = e.d
		local model = d.model
		local first = d.parts[1]
		if model.Parent ~= nil and first ~= nil and model:GetAttribute("PixelShadow") ~= nil then
			local cx, cy, rx, ry = SG.shadowGeo(s, model, first.part, e.pic)
			if cx then
				-- (it slides with its picture, by the same whole px)
				e.sx, e.sy, e.srx, e.sry = cx + e.gx, cy + e.gy, rx, ry
			end
		end
	end
	return out
end

-- Whether model d's kept picture (good at scale ppu) lies wholly off the layer.
function SG.offPic(s: Surf, d: Dyn, ppu: number): boolean
	local c = d.cache
	if c == nil or c.n < 0 or c.ver ~= SG.ver or c.ppu ~= ppu then
		return false
	end
	local x0, y0 = c.gx - s.cam.gx, c.gy - s.cam.gy
	return x0 + c.w - 1 < 0 or y0 + c.h - 1 < 0 or x0 > s.W - 1 or y0 > s.H - 1
end

-- Whether model d has no kept picture that could stand for it (at scale ppu) on this layer.
function SG.bare(d: Dyn, ppu: number): boolean
	local c = d.cache
	return c == nil or c.n < 0 or c.ver ~= SG.ver or c.ppu ~= ppu
end

-- The scratch frame a model is drawn afresh into, far and empty (each draw wipes what it wrote): the layer's size and
-- SG.ISO_M px more all round (a model up to CULL px past the edge, and its own size, drawn whole), and its camera (the
-- layer's, windowed out by that much; made again when the layer's camera changes).
function SG.isoFor(s: Surf): (Raster.Frame, Raster.Cam)
	local f = SG.iso
	local M = SG.ISO_M
	local IW, IH = s.W + 2 * M, s.H + 2 * M
	if f == nil or f.W ~= IW or f.H ~= IH then
		local n = IW * IH
		local depth = buffer.create(n * 4)
		local row = buffer.create(IW * 4)
		for i = 0, IW - 1 do
			buffer.writef32(row, i * 4, FAR)
		end
		for y = 0, IH - 1 do
			buffer.copy(depth, y * IW * 4, row, 0, IW * 4)
		end
		SG.farRow = row
		f = { W = IW, H = IH, color = buffer.create(n * 4), depth = depth, id = buffer.create(n * 2) }
		SG.iso = f
	end
	local c = SG.isoCam
	if c == nil or SG.isoOf ~= s.cam then
		c = Raster.window(s.cam, -M, -M, IW, IH)
		SG.isoCam, SG.isoOf = c, s.cam
	end
	return f :: Raster.Frame, c :: Raster.Cam
end

-- The models' rects for the ink pass, those that overlap joined while their box is no bigger than the two apart (a
-- crowd's rects overlap a lot, and the ink pass over a pixel twice gives the same picture as once; the stress test of
-- 2026-11-17 spent a fifth of a frame inking the same pixels over).
function SG.mergeRects(rects: { Rect }): { Rect }
	if #rects < 2 then
		return rects
	end
	local out: { Rect } = {}
	for _, r in rects do
		table.insert(out, { x0 = r.x0, y0 = r.y0, x1 = r.x1, y1 = r.y1 })
	end
	local function area(q: Rect): number
		return (q.x1 - q.x0 + 1) * (q.y1 - q.y0 + 1)
	end
	local merged = true
	while merged do
		merged = false
		for i = #out, 2, -1 do
			local a = out[i]
			for j = i - 1, 1, -1 do
				local b = out[j]
				if a.x0 <= b.x1 and b.x0 <= a.x1 and a.y0 <= b.y1 and b.y0 <= a.y1 then
					local u = { x0 = math.min(a.x0, b.x0), y0 = math.min(a.y0, b.y0), x1 = math.max(a.x1, b.x1), y1 = math.max(a.y1, b.y1) }
					if area(u) <= area(a) + area(b) then
						out[j] = u
						table.remove(out, i)
						merged = true
						break
					end
				end
			end
		end
	end
	return out
end

-- A drawn model's rect, a pixel round it, for the ink and the upload; a founder's for its white rim too.
function SG.addRect(rects: { Rect }, d: Dyn, x0: number, y0: number, x1: number, y1: number)
	if x0 > x1 then
		return
	end
	table.insert(rects, { x0 = x0 - 1, y0 = y0 - 1, x1 = x1 + 1, y1 = y1 + 1 })
	if d.rim then
		local s = surf :: Surf
		table.insert(Rims.list, d)
		table.insert(Rims.rects, { x0 = math.max(0, x0), y0 = math.max(0, y0), x1 = math.min(s.W - 1, x1), y1 = math.min(s.H - 1, y1) })
	end
end

-- Model d's kept picture when it can stand for a draw this tick (fresh: every model is due, so only one that has not
-- moved; otherwise a model that is not a founder may show it though it has moved), and the layer rect it covers; nil:
-- draw it.
function SG.blitOk(s: Surf, d: Dyn, fresh: boolean, ppu: number): (DynCache?, number, number, number, number)
	-- (posed in a pose it has a picture of: that picture stands for its parts as they are now)
	local key, poses = d.poseKey, d.poses
	if key and poses then
		local pc = poses[key]
		local cur = d.cache
		if pc and pc.ver == SG.ver and pc.ppu == ppu and cur ~= pc and (cur == nil or cur.from ~= pc) then
			local cfs, szs, gone = {}, {}, {}
			for i, p in d.parts do
				local part = p.part
				cfs[i], szs[i], gone[i] = part.CFrame, part.Size, part.Parent == nil or part.Transparency >= 0.95
			end
			local cc = table.clone(pc)
			cc.cfs, cc.szs, cc.gone, cc.from = cfs, szs, gone, pc
			d.cache = cc
		end
	end
	local c = d.cache
	if c == nil or c.n < 0 or c.ver ~= SG.ver or c.ppu ~= ppu or SG.off then
		return nil, 0, 0, 0, 0
	end
	if (fresh or d.rim) and not SG.same(d, c.cfs, c.szs, c.gone) then
		return nil, 0, 0, 0, 0
	end
	local x0, y0 = c.gx - s.cam.gx, c.gy - s.cam.gy
	local x1, y1 = x0 + c.w - 1, y0 + c.h - 1
	-- (a picture reaching off the layer is put down clipped: it was drawn whole, past the layer's edge)
	if x1 < 0 or y1 < 0 or x0 > s.W - 1 or y0 > s.H - 1 then
		return nil, 0, 0, 0, 0
	end
	return c, x0, y0, x1, y1
end

-- Kept picture c put down on the frame with its top left at layer (x0, y0), depth tested as the draw would be (where
-- it already shows, nothing changes: a pixel it won has its own depth, which it does not beat).
function SG.blitAt(s: Surf, c: DynCache, x0: number, y0: number, dz: number?)
	local W, H = s.W, s.H
	local z = dz or 0
	local f = s.frame
	local color, depth, ids = f.color, f.depth, f.id
	local bias = s.cam.bias
	local px = c.px
	if x0 >= 0 and y0 >= 0 and x0 + c.w <= W and y0 + c.h <= H then
		for k = 0, c.n - 1 do
			local o = k * PX_BYTES
			local i = (y0 + buffer.readu16(px, o + 2)) * W + x0 + buffer.readu16(px, o)
			local t = buffer.readf32(px, o + 8) + z
			if t + bias < buffer.readf32(depth, i * 4) then
				buffer.writeu32(color, i * 4, buffer.readu32(px, o + 4))
				buffer.writef32(depth, i * 4, t)
				buffer.writeu16(ids, i * 2, buffer.readu16(px, o + 12))
			end
		end
		return
	end
	-- (reaching off the layer: its pixels on it)
	for k = 0, c.n - 1 do
		local o = k * PX_BYTES
		local x, y = x0 + buffer.readu16(px, o), y0 + buffer.readu16(px, o + 2)
		if x >= 0 and y >= 0 and x < W and y < H then
			local i = y * W + x
			local t = buffer.readf32(px, o + 8) + z
			if t + bias < buffer.readf32(depth, i * 4) then
				buffer.writeu32(color, i * 4, buffer.readu32(px, o + 4))
				buffer.writef32(depth, i * 4, t)
				buffer.writeu16(ids, i * 2, buffer.readu16(px, o + 12))
			end
		end
	end
end

-- Puts model d's kept picture on the frame when it can stand for a draw this tick (SG.blitOk). Returns the layer rect
-- it covers, or nil (draw it).
function SG.blit(s: Surf, d: Dyn, fresh: boolean, ppu: number): (number?, number?, number?, number?)
	local c, x0, y0, x1, y1 = SG.blitOk(s, d, fresh, ppu)
	if c == nil then
		return nil
	end
	SG.blitAt(s, c, x0, y0)
	return x0, y0, x1, y1
end

-- Draws moving model d into frame f (the layer's, or the scratch a still model's clean picture is drawn in) at camera
-- cam; returns the layer rect its parts cover (x0 > x1: none).
function SG.drawModel(f: Raster.Frame, d: Dyn, cam: Raster.Cam, texOn: boolean): (number, number, number, number)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	-- (a model lit smooth: its balls as they stand this frame; Render/Smooth)
	local smooth = d.smooth
	if smooth then
		local T = texOpt
		local cnt = 0
		for _, p in d.parts do
			local part = p.part
			if p.sm == SmoothParts.Smooth.ROLE_BALL and part.Parent ~= nil and part.Transparency < 0.95 then
				local pos, psz = part.Position, part.Size
				cnt += 1
				T.xs[cnt], T.ys[cnt], T.zs[cnt] = pos.X, pos.Y, pos.Z
				T.rs[cnt] = math.min(psz.X, psz.Y, psz.Z) * 0.5
			end
		end
		T.cnt = cnt
		-- (and its smooth solids: the pieces lying on them take their normals)
		local sc = 0
		for _, p in d.parts do
			local part = p.part
			local sk = SG.solidKind[p.shape]
			if sk and not p.glow and part.Parent ~= nil and part.Transparency < 0.95 then
				local psz = part.Size
				SmoothParts.Smooth.packSolid(T.sol, sc, { part.CFrame:GetComponents() }, psz.X, psz.Y, psz.Z, sk, p.prm)
				sc += 1
			end
		end
		T.scnt = sc
	end
	-- (the marks painted on: each one's oval this frame, world space)
	local PS = SG.paints
	local pn = 0
	for _, p in d.parts do
		local pt = p.paint
		local part = p.part
		if pt and part.Parent ~= nil then
			local c = { part.CFrame:GetComponents() }
			local o = pn * PAINT_STRIDE
			PS[o + 1], PS[o + 2], PS[o + 3] = c[1], c[2], c[3]
			local la, lb, ln = pt.a, pt.b, pt.n
			for k, v in { la, lb, ln } do
				local q = o + 1 + 3 * k
				PS[q] = c[4] * v.X + c[5] * v.Y + c[6] * v.Z
				PS[q + 1] = c[7] * v.X + c[8] * v.Y + c[9] * v.Z
				PS[q + 2] = c[10] * v.X + c[11] * v.Y + c[12] * v.Z
			end
			PS[o + 13] = p.rgb
			local sa, sb = la.Magnitude, lb.Magnitude
			PS[o + 14] = math.max(sa, sb)
			PS[o + 15] = 1 / math.max(1e-6, math.min(sa, sb, ln.Magnitude))
			pn += 1
		end
	end
	SG.paintN = pn
	local function nearPaint(cx: number, cy: number, cz: number, r: number): boolean
		for k = 0, pn - 1 do
			local o = k * PAINT_STRIDE
			local dx, dy, dz = cx - PS[o + 1], cy - PS[o + 2], cz - PS[o + 3]
			local lim = r + PS[o + 15]
			if dx * dx + dy * dy + dz * dz < lim * lim then
				return true
			end
		end
		return false
	end
	-- (the body's blend radius: its members' shares of their sizes, averaged; drawn blended only where it shows)
	local blendN, blendSum = 0, 0
	for _, p in d.parts do
		local part = p.part
		if p.blend and part.Parent ~= nil and part.Transparency < 0.95 then
			local sz = part.Size
			blendN += 1
			blendSum += p.blend * math.max(sz.X, sz.Y, sz.Z)
		end
	end
	local blendOn = blendN > 1 and Raster.blendWorth(cam, blendSum / blendN)
	for _, p in d.parts do
		local part = p.part
		if part.Parent == nil or part.Transparency >= 0.95 then
			continue
		end
		local sz = part.Size
		if p.paint then
			continue -- (painted onto the face, not drawn)
		end
		if p.blend and blendOn then
			-- (the body's blended members go last, as one surface: the details under them, so an eye or a claw stands
			-- clear of the body unless the body is truly in front)
			continue
		end
		local cf12 = { part.CFrame:GetComponents() }
		local bx0, by0, bx1, by1 = Raster.boxRect(cam, cf12, sz.X, sz.Y, sz.Z)
		if bx0 and by0 and bx1 and by1 then
			local shade = if p.glow then shadeGlow else shadeLit
			local lean = smooth and (p.sm == SmoothParts.Smooth.ROLE_BALL or p.sm == SmoothParts.Smooth.ROLE_FOLLOW)
			local eye = p.eye
			if eye then
				-- (a painted eye: Render/EyeTex)
				texCF = cf12
				local E = SG.eyeOpt
				E.code, E.iris, E.dark, E.lid, E.side = eye.code, eye.iris, eye.dark, eye.lid, eye.side
				E.hx, E.hy = math.max(1e-3, sz.X * 0.5), math.max(1e-3, sz.Y * 0.5)
				shade = SG.shadeEye :: Raster.Shade
			elseif (texOn and p.tex > 0) or lean then
				texCF, texShape, texKind = cf12, p.shape, if texOn then p.tex else 0
				texOpt.seed, texOpt.v, texOpt.soft = p.texSeed or p.id % 97, p.texV, p.texSoft
				if lean then
					local T = texOpt
					T.n = SmoothParts.Smooth.near(T.xs, T.ys, T.zs, T.rs, T.cnt, cf12[1], cf12[2], cf12[3], 0.5 * sz.Magnitude, T.idx)
					T.role = p.sm
					-- (the solids within reach of this piece)
					local sn = 0
					if p.sm == SmoothParts.Smooth.ROLE_FOLLOW then
						local S, stride = T.sol, SmoothParts.Smooth.SOLID_STRIDE
						local reach = 0.5 * sz.Magnitude + SmoothParts.Smooth.SOLID_REACH
						for k = 0, T.scnt - 1 do
							local o = k * stride
							local dx, dy, dz = cf12[1] - S[o + 1], cf12[2] - S[o + 2], cf12[3] - S[o + 3]
							local lim = reach + S[o + 18]
							if dx * dx + dy * dy + dz * dz <= lim * lim then
								sn += 1
								T.sidx[sn] = k + 1
							end
						end
					end
					T.sn = sn
				else
					texOpt.role = 0
				end
				shade = shadeTex
			end
			SG.paintOn = pn > 0 and not p.glow and eye == nil and nearPaint(cf12[1], cf12[2], cf12[3], 0.5 * sz.Magnitude)
			if SG.paintOn and shade == shadeLit then
				shade = SG.shadePaint :: Raster.Shade
			end
			Raster.drawPart(f, cam, p.shape, cf12, sz.X, sz.Y, sz.Z, p.rgb, p.id, shade, nil, p.prm)
			x0, y0, x1, y1 = math.min(x0, bx0), math.min(y0, by0), math.max(x1, bx1), math.max(y1, by1)
		end
	end
	SG.paintOn = false
	if blendOn then
		-- the blended body
		local k = blendSum / blendN
		local M, P, C = SG.blendM, SG.blendP, SG.blendCf
		local n = 0
		for _, p in d.parts do
			local part = p.part
			if p.blend and part.Parent ~= nil and part.Transparency < 0.95 then
				local cf12 = { part.CFrame:GetComponents() }
				local sz = part.Size
				local m = Raster.blendMember(cam, p.shape, cf12, sz.X, sz.Y, sz.Z, p.prm, p.rgb, p.id, k)
				if m then
					n += 1
					M[n], P[n], C[n] = m, p, cf12
					SG.blendPaint[n] = pn > 0 and nearPaint(cf12[1], cf12[2], cf12[3], 0.5 * sz.Magnitude)
				end
			end
		end
		for i = n + 1, #M do
			M[i], P[i], C[i] = nil :: any, nil, nil :: any
		end
		if n > 0 then
			SG.blendLast, SG.blendTex = 0, texOn
			local w, bx0, by0, bx1, by1 = Raster.drawBlend(f, cam, M, n, k, SG.shadeMember :: Raster.BlendShade)
			SG.paintOn = false
			if w >= 0 and bx1 >= bx0 then
				x0, y0, x1, y1 = math.min(x0, bx0), math.min(y0, by0), math.max(x1, bx1), math.max(y1, by1)
			end
		end
	end
	return x0, y0, x1, y1
end

------------------------------------------------------------------ the incremental compose
-- The stress test of 2026-11-17 ("do a stress test with the maximum amount of decor and buildings at the highest
-- expansion level. Try walking around to move the camera. It should be smooth. If not, find ways to optimize it"): a
-- whole compose puts every moving model on the screen back over the static picture, then inks and grades all of it,
-- and while the view panned every frame was composed whole. On a full Everdrift that was most of a frame. Now the
-- composed frame stays. A pan shifts it with the static layer (the grid is the world's, so every pixel moves by the
-- same whole art px), and a compose redoes only the layer's tiles (SG.TILE art px square) where something changed:
-- where a model that moved or changed its picture was and is, where a blob shadow moved, where a model went, the
-- strips a pan brought in, a static pixel the water or the wind changed under a model. In those tiles the static
-- picture goes back, the blob shadows over them are drawn again (whole: a shadow the tiles meet marks its own), then
-- the models (an unchanged model the tiles meet is put down whole: outside them its pixels already show it, and a
-- kept picture never beats its own depth), and the tiles are inked, graded and uploaded. `SG.base` keeps the frame as
-- it stands before the effects: last tick's effect pixels are put back from it (the static picture alone would leave
-- holes in the models they were over).

-- Whether layer s composes incrementally now: its whole compose set SG.base up and the graded static picture is in
-- step (not with the lamps' pools on: they are built again every LIGHT_EVERY s).
function SG.live(s: Surf): boolean
	if SG.incOn ~= s or Tuning.PixelIncCompose == 0 then
		return false
	end
	local b = SG.base
	local n = s.W * s.H
	if b == nil or buffer.len(b.color) ~= n * 4 then
		return false
	end
	local g = grade
	if g and g.lamps > 0 then
		return false
	end
	if g or dim > 0 then
		local o = SG.out
		return SG.ok and SG.on == s and o ~= nil and buffer.len(o) == n * 4
	end
	return true
end

-- Static pixel i of layer s changed from colour old to new (the water's or the wind's frame; SG.buf graded already):
-- where the frame shows the static picture it takes the new colour, else the pixel's tile is drawn again.
function SG.sync(s: Surf, i: number, old: number, new: number)
	local f, b = s.frame, SG.base :: { color: buffer, id: buffer }
	local sid = buffer.readu16(s.sId, i * 2)
	if buffer.readu16(b.id, i * 2) == sid and buffer.readu32(b.color, i * 4) == old then
		buffer.writeu32(b.color, i * 4, new)
		-- (an effect over it keeps showing: it comes off next tick, from the base)
		if buffer.readu16(f.id, i * 2) == sid and buffer.readu32(f.color, i * 4) == old then
			buffer.writeu32(f.color, i * 4, new)
			local o, g = SG.out, SG.buf
			if o and g and (grade or dim > 0) then
				buffer.writeu32(o, i * 4, buffer.readu32(g, i * 4))
			end
		end
		SG.upWhole = true
	else
		local x, y = i % s.W + s.cam.gx, i // s.W + s.cam.gy
		table.insert(SG.dirty, { x0 = x, y0 = y, x1 = x, y1 = y })
	end
	SG.touch = true
end

-- Pixel i graded again into the image's copy (the incremental compose keeps it in step with the frame).
function SG.gradePx(s: Surf, i: number)
	local o = SG.out
	if SG.incOn == s and (grade or dim > 0) and o and buffer.len(o) == s.W * s.H * 4 then
		gradeSpan(s.frame.color, s.frame.id, i, 1, o, i)
	end
end

-- A sticky pixel i changed from colour old (0: none) to c (the static colour: unstuck): on the frame, and on the base,
-- where each shows the static picture or the old sticky colour there (a blob shadow or a model over it stays).
function SG.stickPut(s: Surf, i: number, old: number, c: number)
	local sid = buffer.readu16(s.sId, i * 2)
	local stat = buffer.readu32(s.sColor, i * 4)
	local f = s.frame
	if buffer.readu16(f.id, i * 2) == sid then
		local cur = buffer.readu32(f.color, i * 4)
		if cur == stat or (old ~= 0 and cur == old) then
			buffer.writeu32(f.color, i * 4, c)
			SG.gradePx(s, i)
		end
	end
	local b = SG.base
	if SG.incOn == s and b and buffer.len(b.color) == s.W * s.H * 4 and buffer.readu16(b.id, i * 2) == sid then
		local cur = buffer.readu32(b.color, i * 4)
		if cur == stat or (old ~= 0 and cur == old) then
			buffer.writeu32(b.color, i * 4, c)
		end
	end
end

-- Before a pan drops the sticky pixels (their owner sticks them again where they now lie), each comes off the frame
-- and the base where it shows.
function SG.unstickFrame(s: Surf)
	local sc = stickCol
	if stickLive == 0 or sc == nil or buffer.len(sc) ~= s.W * s.H * 4 then
		return
	end
	for _, i in stickList do
		local c = buffer.readu32(sc, i * 4)
		if c ~= 0 then
			SG.stickPut(s, i, c, buffer.readu32(s.sColor, i * 4))
		end
	end
end

-- The tiles of layer s, all clean.
function SG.tilesClear(s: Surf)
	local T = SG.TILE
	local c, r = (s.W + T - 1) // T, (s.H + T - 1) // T
	if c ~= SG.tcols or r ~= SG.trows then
		SG.tcols, SG.trows = c, r
		SG.bits = buffer.create(c * r)
	else
		buffer.fill(SG.bits, 0, 0)
	end
end

-- Marks the tiles under a layer rect (inclusive) to draw again; returns how many of them were clean.
function SG.mark(x0: number, y0: number, x1: number, y1: number): number
	local T = SG.TILE
	local cols = SG.tcols
	local tx0, ty0 = math.max(0, x0 // T), math.max(0, y0 // T)
	local tx1, ty1 = math.min(cols - 1, x1 // T), math.min(SG.trows - 1, y1 // T)
	local bits = SG.bits
	local n = 0
	for ty = ty0, ty1 do
		local o = ty * cols
		for tx = tx0, tx1 do
			if buffer.readu8(bits, o + tx) == 0 then
				buffer.writeu8(bits, o + tx, 1)
				n += 1
			end
		end
	end
	return n
end

-- Whether a layer rect (inclusive) meets a marked tile (all: whether every tile under it is marked).
function SG.hit(x0: number, y0: number, x1: number, y1: number, all: boolean?): boolean
	local T = SG.TILE
	local cols = SG.tcols
	local tx0, ty0 = math.max(0, x0 // T), math.max(0, y0 // T)
	local tx1, ty1 = math.min(cols - 1, x1 // T), math.min(SG.trows - 1, y1 // T)
	local bits = SG.bits
	for ty = ty0, ty1 do
		local o = ty * cols
		for tx = tx0, tx1 do
			local on = buffer.readu8(bits, o + tx) ~= 0
			if on and not all then
				return true
			elseif all and not on then
				return false
			end
		end
	end
	return all == true
end

-- The marked tiles as layer rects (clipped to the layer): runs along each row of tiles, a run joined to the one above
-- it when the two span the same columns.
function SG.runs(s: Surf): { Rect }
	local T = SG.TILE
	local cols, rows = SG.tcols, SG.trows
	local bits = SG.bits
	local W, H = s.W, s.H
	local out: { Rect } = {}
	local open: { [number]: Rect } = {}
	for ty = 0, rows - 1 do
		local now: { [number]: Rect } = {}
		local o = ty * cols
		local tx = 0
		while tx < cols do
			if buffer.readu8(bits, o + tx) ~= 0 then
				local a = tx
				while tx + 1 < cols and buffer.readu8(bits, o + tx + 1) ~= 0 do
					tx += 1
				end
				local key = a * 4096 + tx
				local y1 = math.min(H - 1, ty * T + T - 1)
				local up = open[key]
				if up then
					up.y1 = y1
					now[key] = up
				else
					local r = { x0 = a * T, y0 = ty * T, x1 = math.min(W - 1, tx * T + T - 1), y1 = y1 }
					table.insert(out, r)
					now[key] = r
				end
			end
			tx += 1
		end
		open = now
	end
	return out
end

-- What model d shows after a compose: kept picture c (nil: one that is not the same next time) over layer rect
-- (x0, y0)-(x1, y1), remembered in global art px a pixel round it; a founder's rim goes round it (rim).
function SG.shown(s: Surf, d: Dyn, c: DynCache?, x0: number, y0: number, x1: number, y1: number, rim: boolean, dz: number?)
	local gx, gy = s.cam.gx, s.cam.gy
	d.shC = c
	d.shDz = dz or 0
	d.shR = { x0 = x0 - 1 + gx, y0 = y0 - 1 + gy, x1 = x1 + 1 + gx, y1 = y1 + 1 + gy }
	if rim and d.rim then
		table.insert(Rims.list, d)
		table.insert(Rims.rects, { x0 = math.max(0, x0), y0 = math.max(0, y0), x1 = math.min(s.W - 1, x1), y1 = math.min(s.H - 1, y1) })
	end
end

-- A layer rect of the frame graded into the image's copy: the static picture's grade copied, the pixels the frame
-- has other than the static picture's graded from it.
function SG.gradeRect(s: Surf, r: Rect)
	local W, H = s.W, s.H
	local x0, y0, x1, y1 = math.max(0, r.x0), math.max(0, r.y0), math.min(W - 1, r.x1), math.min(H - 1, r.y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local out, sg = SG.out :: buffer, SG.buf :: buffer
	local f = s.frame
	local fc, fi, sc, si = f.color, f.id, s.sColor, s.sId
	for y = y0, y1 do
		local row = y * W
		buffer.copy(out, (row + x0) * 4, sg, (row + x0) * 4, (x1 - x0 + 1) * 4)
		local run = -1
		for x = x0, x1 + 1 do
			local i = row + x
			local differs = x <= x1 and (buffer.readu32(fc, i * 4) ~= buffer.readu32(sc, i * 4) or buffer.readu16(fi, i * 2) ~= buffer.readu16(si, i * 2))
			if differs then
				if run < 0 then
					run = i
				end
			elseif run >= 0 then
				gradeSpan(fc, fi, run, i - run, out, run)
				run = -1
			end
		end
	end
end

-- A layer rect of the image (src: the graded copy, or the frame's colours ungraded) uploaded.
function SG.upRect(s: Surf, r: Rect, src: buffer)
	local im = img
	if im == nil then
		return
	end
	local W = s.W
	local x0, y0, x1, y1 = math.max(0, r.x0), math.max(0, r.y0), math.min(W - 1, r.x1), math.min(s.H - 1, r.y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local w, h = x1 - x0 + 1, y1 - y0 + 1
	local b = buffer.create(w * h * 4)
	for y = y0, y1 do
		buffer.copy(b, (y - y0) * w * 4, src, (y * W + x0) * 4, w * 4)
	end
	pcall(function()
		im:WritePixelsBuffer(Vector2.new(x0, y0), Vector2.new(w, h), b)
	end)
	stats.perf.uploads += 1
end

-- The frame's rect kept as the base (the frame before the effects).
function SG.toBase(s: Surf, r: Rect)
	local W = s.W
	local x0, y0, x1, y1 = math.max(0, r.x0), math.max(0, r.y0), math.min(W - 1, r.x1), math.min(s.H - 1, r.y1)
	if x0 > x1 or y0 > y1 then
		return
	end
	local b = SG.base :: { color: buffer, id: buffer }
	local f = s.frame
	local w = x1 - x0 + 1
	for y = y0, y1 do
		local o = y * W + x0
		buffer.copy(b.color, o * 4, f.color, o * 4, w * 4)
		buffer.copy(b.id, o * 2, f.id, o * 2, w * 2)
	end
end

-- After a whole compose (before its effects): the base taken, every model's picture and blob shadow remembered by it,
-- and layer s composes incrementally from now on when it can.
function SG.incStart(s: Surf)
	local n = s.W * s.H
	if Tuning.PixelIncCompose == 0 or s.view.stage or SG.off or SG.quiet then
		SG.incOn = nil
		return
	end
	local b = SG.base
	if b == nil or buffer.len(b.color) ~= n * 4 then
		b = { color = buffer.create(n * 4), id = buffer.create(n * 2) }
		SG.base = b
	end
	local bb = b :: { color: buffer, id: buffer }
	buffer.copy(bb.color, 0, s.frame.color, 0, n * 4)
	buffer.copy(bb.id, 0, s.frame.id, 0, n * 2)
	SG.incOn = s
end

-- The incremental compose of layer s (due: the moving models are all due, as compose's).
function SG.incCompose(s: Surf, due: boolean?)
	local W, H = s.W, s.H
	local n = W * H
	local cam = s.cam
	local gx, gy = cam.gx, cam.gy
	local f = s.frame
	local base = SG.base :: { color: buffer, id: buffer }
	local pf = stats.perf
	local k0 = SG.clock()
	-- last tick's effects come off (the frame as it stood before them); their book is kept to grade those pixels
	local oldBook, oldN = fxPrev, fxPrevN
	local color, ids = f.color, f.id
	for k = 0, oldN - 1 do
		local i = buffer.readu32(oldBook, k * 4)
		if i < n then
			buffer.writeu32(color, i * 4, buffer.readu32(base.color, i * 4))
			buffer.writeu16(ids, i * 2, buffer.readu16(base.id, i * 2))
		end
	end
	SG.tilesClear(s)
	local hit = SG.hit
	local by = SG.markBy
	local tag = "dirty"
	local function mark(x0: number, y0: number, x1: number, y1: number): number
		local k = SG.mark(x0, y0, x1, y1)
		by[tag] = (by[tag] or 0) + k
		return k
	end
	for _, r in SG.dirty do
		mark(r.x0 - gx, r.y0 - gy, r.x1 - gx, r.y1 - gy)
	end
	tag = "sweep"
	table.clear(SG.dirty)
	-- (a band of the layer drawn again every compose, round and round: whatever a compose of a few tiles might leave
	-- behind lasts a second or two at most)
	local T = SG.TILE
	SG.sweep += 1
	if SG.sweep % 3 == 0 then
		local row = (SG.sweep // 3) % math.max(1, SG.trows)
		mark(0, row * T, W - 1, row * T + T - 1)
	end
	local strips = SG.strips
	local ppu = cam.s / cam.K
	local texOn = ppu >= DynTex.MIN_PX_PER_STUD
	texCam = cam
	texPx = 1 / ppu
	local fresh = due ~= false
	local still, shad = SG.still, SG.shad
	table.clear(still)
	table.clear(shad)
	-- what every model shows now (SG.plan: the ones drawn afresh are drawn into their own scratch, the frame untouched)
	local plan = SG.plan(s, fresh, ppu, texOn)
	local chg: { PlanEntry } = {}
	for _, e in plan do
		local d = e.d
		-- its blob shadow: unchanged, or off where it was and on where it is
		tag = "shadow"
		d.sIn = false
		local old = d.sR
		local cx = e.sx
		if cx == nil then
			if old then
				mark(old.x0 - gx, old.y0 - gy, old.x1 - gx, old.y1 - gy)
				d.sR, d.sx = nil, nil
			end
		elseif cx + gx == d.sx and e.sy + gy == d.sy and e.srx == d.srx and e.sry == d.sry then
			d.sChg = false
			table.insert(shad, d)
		else
			if old then
				mark(old.x0 - gx, old.y0 - gy, old.x1 - gx, old.y1 - gy)
			end
			local sx0, sy0, sx1, sy1 = SG.shadowRect(cx, e.sy, e.srx, e.sry)
			mark(sx0, sy0, sx1, sy1)
			d.sR = { x0 = sx0 + gx, y0 = sy0 + gy, x1 = sx1 + gx, y1 = sy1 + gy }
			d.sx, d.sy, d.srx, d.sry = cx + gx, e.sy + gy, e.srx, e.sry
			d.sChg = true
			table.insert(shad, d)
		end
		-- its picture: the same one where it was (unchanged), or off where it was and on where it is now
		tag = if d.own or d.rim then "founder" elseif e.pic == nil then "gone" else "changed"
		local pic = e.pic
		local was0 = d.shR
		if pic ~= nil and pic == d.shC and not d.rim and was0 ~= nil and was0.x0 + 1 == e.x0 + gx and was0.y0 + 1 == e.y0 + gy and d.shDz == e.dz then
			table.insert(still, d)
		else
			local was = d.shR
			if was then
				mark(was.x0 - gx, was.y0 - gy, was.x1 - gx, was.y1 - gy)
			end
			if pic then
				mark(e.x0 - 1, e.y0 - 1, e.x1 + 1, e.y1 + 1)
				table.insert(chg, e)
			else
				d.shR, d.shC = nil, nil
			end
		end
	end
	-- where an unchanged model or blob shadow meets a strip a pan brought in (the strip is the static picture alone),
	-- its tiles are drawn again
	tag = "strips"
	for _, r in strips do
		for _, d in still do
			local q = d.shR :: Rect
			local x0, y0, x1, y1 = math.max(r.x0, q.x0 - gx), math.max(r.y0, q.y0 - gy), math.min(r.x1, q.x1 - gx), math.min(r.y1, q.y1 - gy)
			if x0 <= x1 and y0 <= y1 then
				mark(x0, y0, x1, y1)
			end
		end
		for _, d in shad do
			local q = d.sR
			if q then
				local x0, y0, x1, y1 = math.max(r.x0, q.x0 - gx), math.max(r.y0, q.y0 - gy), math.min(r.x1, q.x1 - gx), math.min(r.y1, q.y1 - gy)
				if x0 <= x1 and y0 <= y1 then
					mark(x0, y0, x1, y1)
				end
			end
		end
	end
	-- an unchanged blob shadow the tiles meet is drawn again within them (clipped: outside, its pixels are as they were)
	for _, d in shad do
		local q = d.sR
		if not d.sChg and q and hit(q.x0 - gx, q.y0 - gy, q.x1 - gx, q.y1 - gy) then
			d.sIn = true
		end
	end
	for _, r in strips do
		restoreRect(s, r)
	end
	local runs = SG.runs(s)
	for _, r in runs do
		restoreRect(s, r)
	end
	local k1 = SG.clock()
	pf.copyMs += (k1 - k0) * 1000
	for _, d in shad do
		if d.sChg or d.sIn then
			drawShadow(s, d.model, d.parts[1].part, (d.sx :: number) - gx, (d.sy :: number) - gy, d.srx, d.sry, true)
		end
	end
	-- the models: the unchanged ones the tiles meet put down again (outside them their pixels already show them, and a
	-- kept picture never beats its own depth), the changed ones where they are now
	for _, d in still do
		local q = d.shR :: Rect
		if hit(q.x0 - gx, q.y0 - gy, q.x1 - gx, q.y1 - gy) then
			local c = d.shC :: DynCache
			-- (where it went down last time: its kept picture, slid on with the model)
			SG.blitAt(s, c, q.x0 + 1 - gx, q.y0 + 1 - gy, d.shDz)
			SG.hits += 1
		end
	end
	for _, e in chg do
		local pic = e.pic :: DynCache
		SG.blitAt(s, pic, e.x0, e.y0, e.dz)
		SG.hits += 1
		SG.shown(s, e.d, pic, e.x0, e.y0, e.x1, e.y1, true, e.dz)
	end
	local k2 = SG.clock()
	for _, r in runs do
		Shading.outline(f, r.x0, r.y0, r.x1, r.y1, nil, nil, DYN_ID0)
	end
	local k3 = SG.clock()
	Rims.drawAll(s, W * 0.5, H * 0.5)
	local k4 = SG.clock()
	for _, list in { strips, runs } do
		for _, r in list do
			SG.toBase(s, r)
		end
	end
	-- (a strip's pixels outside the tiles are the static picture's: its grade copied, before the effects, whose
	-- pixels and the sticky ones they lay are graded one by one; the tiles are graded below)
	local out = SG.out
	local graded = (grade ~= nil or dim > 0) and out ~= nil
	if graded then
		local o, sg = out :: buffer, SG.buf :: buffer
		for _, r in strips do
			for y = r.y0, r.y1 do
				local i = y * W + r.x0
				buffer.copy(o, i * 4, sg, i * 4, (r.x1 - r.x0 + 1) * 4)
			end
		end
	end
	-- the effects over everything
	local fxRects: { Rect } = if SG.quiet then {} else runFx(s, os.clock())
	local k5 = SG.clock()
	pf.dynMs += (k2 - k1) * 1000
	pf.outlineMs += (k3 - k2) * 1000
	pf.rimMs += (k4 - k3) * 1000
	pf.fxMs += (k5 - k4) * 1000
	-- graded: the tiles, and the effects' pixels (last tick's, taken off, and this tick's)
	if graded then
		for _, r in runs do
			SG.gradeRect(s, r)
		end
		local o = out :: buffer
		for k = 0, oldN - 1 do
			local i = buffer.readu32(oldBook, k * 4)
			if i < n then
				gradeSpan(color, ids, i, 1, o, i)
			end
		end
		for k = 0, fxPrevN - 1 do
			local i = buffer.readu32(fxPrev, k * 4)
			if i < n then
				gradeSpan(color, ids, i, 1, o, i)
			end
		end
		SG.fullAt = SG.seq
	end
	local k6 = SG.clock()
	pf.gradeMs += (k6 - k5) * 1000
	-- up: the whole image after a pan or a water frame (or when the rects are many), else the tiles and the effects'
	local src = if graded then out :: buffer else f.color
	local area = 0
	for _, r in runs do
		area += (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1)
	end
	pf.incPx += area
	pf.incFrames += 1
	if SG.panned or SG.upWhole or #runs + #fxRects > 3 * MAX_RECTS or area * 3 > n then
		local im = img
		if im then
			pcall(function()
				im:WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), src)
			end)
			pf.uploads += 1
		end
	else
		for _, r in runs do
			SG.upRect(s, r, src)
		end
		for _, r in fxRects do
			SG.upRect(s, r, src)
		end
	end
	SG.panned, SG.upWhole, SG.touch = false, false, false
	table.clear(strips)
	pf.uploadMs += (SG.clock() - k6) * 1000
	return area
end

local function compose(due: boolean?)
	local s = surf
	if s == nil then
		return
	end
	local t0 = SG.clock()
	local cam = s.cam
	panX, panY = cam.gx, cam.gy
	SG.seq += 1
	fxBooks(s)
	-- (the incremental compose when the layer has one going: SG.incCompose)
	local live = SG.live(s)
	if not needFull and SG.incOn == s and not live then
		needFull = true
	end
	if not needFull and live then
		local arm = SG.incArm
		SG.noBudget = arm
		local area = SG.incCompose(s, due)
		prevRects = {}
		stats.ticks += 1
		stats.composeMs = (SG.clock() - t0) * 1000
		stats.perf.composeMs += stats.composeMs
		if arm then
			-- (debugIncCheck: the frame before the effects against a whole compose's at the same moment)
			SG.incArm = false
			local n = s.W * s.H
			local b = SG.base :: { color: buffer, id: buffer }
			local a, ai, ad = buffer.create(n * 4), buffer.create(n * 2), buffer.create(n * 4)
			buffer.copy(a, 0, b.color, 0, n * 4)
			buffer.copy(ai, 0, b.id, 0, n * 2)
			buffer.copy(ad, 0, s.frame.depth, 0, n * 4)
			-- (the whole compose's base is taken before its effects run: a lawn tuft they stick anew would differ)
			SG.snap = true
			needFull = true
			compose(false)
			local snap = SG.snapped :: { color: buffer, id: buffer, depth: buffer }
			local off, ties = 0, 0
			local bias = s.cam.bias
			local seen: { string } = {}
			for i = 0, n - 1 do
				local ia, ib = buffer.readu16(ai, i * 2), buffer.readu16(snap.id, i * 2)
				if buffer.readu32(a, i * 4) ~= buffer.readu32(snap.color, i * 4) or ia ~= ib then
					local da, db = buffer.readf32(ad, i * 4), buffer.readf32(snap.depth, i * 4)
					if ia >= DYN_ID0 and ib >= DYN_ID0 and ia ~= ib and math.abs(da - db) <= 2 * bias then
						-- (two models within the depth bias of each other: the one put down first keeps the pixel)
						ties += 1
					else
						off += 1
						if #seen < 6 then
							local x, y = i % s.W, i // s.W
							local T = SG.TILE
							local tile = buffer.readu8(SG.bits, (y // T) * SG.tcols + x // T)
							table.insert(seen, string.format("(%d,%d) inc %06x id %d depth %.2f, whole %06x id %d depth %.2f, static %06x id %d, tile %d", x, y, buffer.readu32(a, i * 4) % 16777216, ia, da, buffer.readu32(snap.color, i * 4) % 16777216, ib, db, buffer.readu32(s.sColor, i * 4) % 16777216, buffer.readu16(s.sId, i * 2), tile))
						end
					end
				end
			end
			SG.incResult = { off = off, ties = ties, checked = n, px = area, seen = table.concat(seen, "; ") } :: any
			SG.noBudget = false
			return
		end
		local after = (PixelRenderer :: any)._composed
		if after then
			after()
		end
		return
	end
	local full = needFull
	local pf = stats.perf
	local k0 = SG.clock()
	if full then
		local n = s.W * s.H
		local f = s.frame
		pf.fullFrames += 1
		-- (what every model shows is remembered afresh below, for the incremental composes after it)
		for _, d in dyns do
			d.shR, d.shC, d.sR, d.sx = nil, nil, nil, nil
		end
		table.clear(SG.dirty)
		table.clear(SG.strips)
		buffer.copy(f.color, 0, s.sColor, 0, n * 4)
		buffer.copy(f.depth, 0, s.sDepth, 0, n * 4)
		buffer.copy(f.id, 0, s.sId, 0, n * 2)
		local sc = stickCol :: buffer
		for _, i in stickList do
			local c = buffer.readu32(sc, i * 4)
			if c ~= 0 then
				buffer.writeu32(f.color, i * 4, c)
			end
		end
		prevRects = {}
	else
		for _, r in prevRects do
			restoreRect(s, r)
		end
		fxRestore(s)
	end
	local rects: { Rect } = {}
	local k1 = SG.clock()
	pf.copyMs += (k1 - k0) * 1000
	-- (textures only where a driftling is drawn big enough for a one-pixel pattern to read: Render/DynTex)
	local pxPerStud = cam.s / cam.K
	local texOn = pxPerStud >= DynTex.MIN_PX_PER_STUD
	texCam = cam
	texPx = 1 / pxPerStud
	-- What every model shows and its shadow (SG.plan: in a crowd, a full Everdrift's driftlings on the screen, the
	-- request of 2026-11-17: "do a stress test with the maximum amount of decor and buildings at the highest expansion
	-- level", every one of them changes a little less often rather than the frame taking ever longer). The blob
	-- shadows go on first (on the static picture), then the models over them.
	local plan = SG.plan(s, due ~= false, pxPerStud, texOn)
	for _, e in plan do
		local d = e.d
		local cx = e.sx
		if cx then
			local r = drawShadow(s, d.model, d.parts[1].part, cx, e.sy, e.srx, e.sry)
			if r then
				table.insert(rects, r)
			end
			if full then
				local x0, y0, x1, y1 = SG.shadowRect(cx, e.sy, e.srx, e.sry)
				local gx, gy = cam.gx, cam.gy
				d.sR = { x0 = x0 + gx, y0 = y0 + gy, x1 = x1 + gx, y1 = y1 + gy }
				d.sx, d.sy, d.srx, d.sry = cx + gx, e.sy + gy, e.srx, e.sry
			end
		end
	end
	for _, e in plan do
		local pic = e.pic
		if pic then
			SG.blitAt(s, pic, e.x0, e.y0, e.dz)
			SG.hits += 1
			SG.addRect(rects, e.d, e.x0, e.y0, e.x1, e.y1)
			SG.shown(s, e.d, pic, e.x0, e.y0, e.x1, e.y1, false, e.dz)
		end
	end
	local k2 = SG.clock()
	local merged = SG.mergeRects(rects)
	for _, r in merged do
		Shading.outline(s.frame, r.x0, r.y0, r.x1, r.y1, nil, nil, DYN_ID0)
	end
	local k3 = SG.clock()
	-- the founders' white rims, once every model and its ink edge is in (a later model's ink must not cover one)
	Rims.drawAll(s, s.W * 0.5, s.H * 0.5)
	local k4 = SG.clock()
	if full then
		-- (the frame before the effects: the incremental composes start from it)
		SG.incStart(s)
		if SG.snap then
			-- (debugIncCheck: this compose's frame before the effects)
			SG.snap = false
			local f = s.frame
			local n = s.W * s.H
			local sc, si, sd = buffer.create(n * 4), buffer.create(n * 2), buffer.create(n * 4)
			buffer.copy(sc, 0, f.color, 0, n * 4)
			buffer.copy(si, 0, f.id, 0, n * 2)
			buffer.copy(sd, 0, f.depth, 0, n * 4)
			SG.snapped = { color = sc, id = si, depth = sd }
		end
	end
	-- the effects over everything (their changed pixels' tiles go up with the rest)
	local fxRects: { Rect } = if SG.quiet then {} else runFx(s, os.clock())
	local k5 = SG.clock()
	pf.dynMs += (k2 - k1) * 1000
	pf.outlineMs += (k3 - k2) * 1000
	pf.rimMs += (k4 - k3) * 1000
	pf.fxMs += (k5 - k4) * 1000
	if full then
		needFull = false
		SG.panned, SG.upWhole, SG.touch = false, false, false
		-- (the effects' pixels are graded one by one from their book: their tiles need nothing more)
		uploadAll(s, merged, true, fxPrev, fxPrevN)
	else
		for _, r in fxRects do
			uploadRect(s, r)
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
	end
	prevRects = rects
	stats.ticks += 1
	stats.composeMs = (SG.clock() - t0) * 1000
	stats.perf.composeMs += stats.composeMs
	-- (what draws over the picture in step with it: PixelRenderer.onComposed)
	local after = (PixelRenderer :: any)._composed
	if after then
		after()
	end
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

-- A pan of the incremental compose (SG.incCompose): the finished frame, the base, the image's graded copy and the
-- effects' books shift with the static layer (by sx, sy as `shift`'s dx, dy); the strips it brought in (and the
-- pixels their cast, ink and contact shade touched round them: strips, layer rects at the new pan) are drawn again.
function SG.panShift(s: Surf, sx: number, sy: number, strips: { Rect })
	local W, H = s.W, s.H
	local n = W * H
	local f = s.frame
	shift(f.color, W, H, 4, sx, sy)
	shift(f.depth, W, H, 4, sx, sy)
	shift(f.id, W, H, 2, sx, sy)
	local b = SG.base :: { color: buffer, id: buffer }
	shift(b.color, W, H, 4, sx, sy)
	shift(b.id, W, H, 2, sx, sy)
	local o = SG.out
	if o and buffer.len(o) == n * 4 then
		shift(o, W, H, 4, sx, sy)
	end
	-- (last tick's effect pixels where they now lie; those that left the layer dropped)
	for k = 0, fxPrevN - 1 do
		local i = buffer.readu32(fxPrev, k * 4)
		if i < n then
			local x, y = i % W - sx, i // W - sy
			buffer.writeu32(fxPrev, k * 4, if x >= 0 and y >= 0 and x < W and y < H then y * W + x else n)
		end
	end
	local sh = fxShown
	if sh and buffer.len(sh) == n * 4 then
		shift(sh, W, H, 4, sx, sy)
		if sx > 0 then
			for y = 0, H - 1 do
				buffer.fill(sh, (y * W + W - sx) * 4, 0, sx * 4)
			end
		elseif sx < 0 then
			for y = 0, H - 1 do
				buffer.fill(sh, y * W * 4, 0, -sx * 4)
			end
		end
		if sy > 0 then
			buffer.fill(sh, (H - sy) * W * 4, 0, sy * W * 4)
		elseif sy < 0 then
			buffer.fill(sh, 0, 0, -sy * W * 4)
		end
	end
	-- (the strips go in as the static picture alone: no model or blob shadow is drawn again for them unless one meets
	-- them; the sticky pixels are all dropped by a pan, so there are none to put back either)
	for _, r in strips do
		table.insert(SG.strips, { x0 = math.max(0, r.x0 - 3), y0 = math.max(0, r.y0 - 3), x1 = math.min(W - 1, r.x1 + 3), y1 = math.min(H - 1, r.y1 + 3) })
	end
	SG.panned = true
end

-- Cast every pixel of a layer rect (inclusive) by the bake's last pass: the 2x2 anchors first, then the pixels that
-- share their sun rays. Returns the rays cast.
local function castRect(s: Surf, x0: number, y0: number, x1: number, y1: number, noRefine: boolean?): number
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
	if shadows and not noRefine then
		refineShadows(s, x0 - 1, y0 - 1, x1 + 1, y1 + 1)
	end
	return bakeRays - before
end

-- Whether the pan cache works for the layer now: the island's own view (not a stage).
function SG.tilesOk(s: Surf): boolean
	return not s.view.stage and Tuning.PixelPanCacheTiles > 0
end

-- Whether a global art px rect meets a re-cast still queued or going (its pixels on the layer may be stale yet).
function SG.pendingOver(x0: number, y0: number, x1: number, y1: number): boolean
	local cur = invCur
	if cur and not (cur.r.x1 < x0 or cur.r.x0 > x1 or cur.r.y1 < y0 or cur.r.y0 > y1) then
		return true
	end
	for _, q in invQueue do
		if not (q.x1 < x0 or q.x0 > x1 or q.y1 < y0 or q.y0 > y1) then
			return true
		end
	end
	return false
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
	SG.windVoid = true -- (the wind's frame being worked out is of the old pan: it waits for the view to stand)
	table.clear(SG.windPend)
	local W, H = s.W, s.H
	local v = s.view
	if math.abs(dx) >= W // 2 or math.abs(dy) >= H // 2 then
		-- a jump (the view sent home from the far end of the street): bake again at the new pan
		s.cam = layerCam(v, tx, ty, s.K)
		s.ready = false -- (the picture on screen is of another place: no point keeping it alive)
		startBake()
		return
	end
	-- the step this frame: the strips' rays within the budget (a strip pixel costs about 1.5 rays with its sun ray)
	local budget = Tuning.PixelPanRays
	local mx = math.max(1, math.floor(budget / (H * 1.5)))
	local my = math.max(1, math.floor(budget / (W * 1.5)))
	local sx, sy = math.clamp(dx, -mx, mx), math.clamp(dy, -my, my)
	-- (composing incrementally: the sticky pixels come off the frame before it shifts, as they are dropped below)
	local inc = not needFull and SG.live(s)
	if inc then
		SG.unstickFrame(s)
	end
	-- the strips about to scroll off are kept in the pan cache (a pan back over them copies them in again), all but
	-- what a re-cast still has to redo
	local cacheOn = SG.tilesOk(s)
	if cacheOn then
		local gx0, gy0 = cam.gx, cam.gy
		local leave: { Rect } = {}
		if sx > 0 then
			table.insert(leave, { x0 = 0, y0 = 0, x1 = sx - 1, y1 = H - 1 })
		elseif sx < 0 then
			table.insert(leave, { x0 = W + sx, y0 = 0, x1 = W - 1, y1 = H - 1 })
		end
		if sy > 0 then
			table.insert(leave, { x0 = 0, y0 = 0, x1 = W - 1, y1 = sy - 1 })
		elseif sy < 0 then
			table.insert(leave, { x0 = 0, y0 = H + sy, x1 = W - 1, y1 = H - 1 })
		end
		for _, r in leave do
			if not SG.pendingOver(gx0 + r.x0, gy0 + r.y0, gx0 + r.x1, gy0 + r.y1) then
				SG.Tiles.save(s, gx0, gy0, r.x0, r.y0, r.x1, r.y1)
			end
		end
	end
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
	local sg = SG.buf
	if SG.ok and SG.on == s and sg and buffer.len(sg) == W * H * 4 then
		shift(sg, W, H, 4, sx, sy) -- (the strips it uncovers are graded once cast, below)
	else
		SG.ok = false
	end
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
	s.cam = layerCam(v, cam.gx + sx, cam.gy + sy, s.K)
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
	local c0 = SG.clock()
	local shadows = tierSpec(tier).shadows
	for _, r in strips do
		if cacheOn then
			-- (a piece of the strip the cache holds whole is copied in; the rest is cast)
			local gx1, gy1 = s.cam.gx, s.cam.gy
			for _, q in SG.Tiles.split(gx1, gy1, r.x0, r.y0, r.x1, r.y1) do
				if not SG.Tiles.load(s, gx1, gy1, q.x0, q.y0, q.x1, q.y1) then
					rays += castRect(s, q.x0, q.y0, q.x1, q.y1, true)
				end
			end
		else
			rays += castRect(s, r.x0, r.y0, r.x1, r.y1, true)
		end
	end
	-- the strips' shadow edges once they are all in (a strip's border meets the other strip and the old picture)
	if shadows then
		for _, r in strips do
			rays += refineShadows(s, r.x0 - 1, r.y0 - 1, r.x1 + 1, r.y1 + 1)
		end
	end
	local c1 = SG.clock()
	for _, r in strips do
		reoutline(s, r.x0, r.y0, r.x1, r.y1)
		SG.waterFix(s, r.x0 - 1, r.y0 - 1, r.x1 + 1, r.y1 + 1)
	end
	stats.perf.castMs += (c1 - c0) * 1000
	stats.perf.inkMs += (SG.clock() - c1) * 1000
	-- (what a strip's cast, ink and contact shade touched: the strip and a few pixels round it)
	for _, r in strips do
		SG.rect(s, r.x0 - 3, r.y0 - 3, r.x1 + 3, r.y1 + 3)
	end
	if inc and not needFull and SG.live(s) then
		SG.panShift(s, sx, sy, strips)
	else
		needFull = true
	end
	stats.scrolls += 1
	staticChanged()
	stats.scrollRays += rays
	lightStale = true
end

------------------------------------------------------------------ invalidation
-- The global art px rect a part and its sun shadow on the lawn cover (nil when the view has none yet).
function SG.boxRect(cf: CFrame, full: Vector3): Rect?
	local v = CameraController.view()
	local size = full / 2
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	local sun = SUN_V
	local ground = Street.LAWN_Y - 0.6 -- the lowest ground a shadow lands on (the top of an island's lip), so the rect holds it
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
local function partRect(part: BasePart): Rect?
	return SG.boxRect(part.CFrame, part.Size)
end

local function queueRect(r: Rect)
	lightStale = true
	-- (whatever the cache kept under it is cast again, on the layer or once a pan brings it in)
	SG.Tiles.drop(r.x0, r.y0, r.x1, r.y1)
	local s = surf
	if s == nil then
		return
	end
	-- only what is on the layer (a rect off it is cast when a pan uncovers it)
	local gx0, gy0 = s.cam.gx, s.cam.gy
	if r.x1 < gx0 or r.y1 < gy0 or r.x0 > gx0 + s.W - 1 or r.y0 > gy0 + s.H - 1 then
		return
	end
	-- a rect over (or mostly over) one already queued joins it while their box is no bigger than the two apart: the
	-- parts that land together (an endless islet's area: hundreds of boxes, long ones lying across the screen) are
	-- re-cast as their union once, and the share below counts what is really cast
	local function rectArea(q: Rect): number
		return (q.x1 - q.x0 + 1) * (q.y1 - q.y0 + 1)
	end
	local merged = true
	while merged do
		merged = false
		for i, q in invQueue do
			local u = { x0 = math.min(q.x0, r.x0), y0 = math.min(q.y0, r.y0), x1 = math.max(q.x1, r.x1), y1 = math.max(q.y1, r.y1) }
			if rectArea(u) <= rectArea(q) + rectArea(r) then
				table.remove(invQueue, i)
				r = u
				merged = true
				break
			end
		end
	end
	table.insert(invQueue, r)
	local area = 0
	for _, q in invQueue do
		area += (math.min(q.x1, gx0 + s.W - 1) - math.max(q.x0, gx0) + 1) * (math.min(q.y1, gy0 + s.H - 1) - math.max(q.y0, gy0) + 1)
	end
	if area > s.W * s.H * REBAKE_SHARE then
		-- a big change (the island grew): bake again, behind the old picture, soon (the parts of one rebuild land
		-- together) and with a bigger budget a frame
		rebakeAt = os.clock() + 0.15
		rush = true
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
	-- (the screen hidden: far more a frame, nobody sees the frame rate)
	local hidden = (PixelRenderer :: any)._hidden == true
	local budget = if hidden then Tuning.PixelInvalidateRaysFrame * 8 else Tuning.PixelInvalidateRaysFrame
	local start = bakeRays
	local deadline = SG.clock() + (if hidden then Tuning.PixelHiddenMs else Tuning.PixelInvalidateMs) / 1000
	while bakeRays - start < budget and SG.clock() < deadline do
		local cur = invCur
		if cur == nil then
			local r = table.remove(invQueue, 1)
			if r == nil then
				return
			end
			cur = { r = r, phase = 1, gx = r.x0, gy = r.y0, fy = r.y0 - 1 }
			invCur = cur
		end
		local c = cur :: InvCur
		local r = c.r
		local shadows = tierSpec(tier).shadows
		local gx0, gy0 = s.cam.gx, s.cam.gy
		local n = 0
		while c.phase <= 2 and bakeRays - start < budget do
			n += 1
			if n % 32 == 0 and SG.clock() >= deadline then
				break
			end
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
		if c.phase == 3 or c.phase == 4 then
			-- the finishing passes in bands of rows, within the frame's time (rects that land together merge, so one can
			-- be most of the layer: the land's chunks an expansion swaps in used to finish in one 120 ms frame)
			local f0 = SG.clock()
			local fx0, fx1 = r.x0 - gx0 - 1, r.x1 - gx0 + 1
			if c.phase == 3 and not shadows then
				c.phase = 4
			end
			while c.phase == 3 and SG.clock() < deadline do
				-- the rect's shadow edges on the pixel grid, and its border's, which meet the old picture (the report
				-- of 2026-11-18: "some shadows still appear stepped like this": a rect cast again on its own, when a
				-- part came or went, kept its 2x2 blocks' shared sun and stepped two pixels at a time)
				refineShadows(s, fx0, c.fy - gy0, fx1, math.min(r.y1 + 1, c.fy + FIN_ROWS - 1) - gy0)
				c.fy += FIN_ROWS
				if c.fy > r.y1 + 1 then
					c.phase, c.fy = 4, r.y0 - 1
				end
			end
			while c.phase == 4 and SG.clock() < deadline do
				-- the ink and the contact shade over the rect and a pixel round it (as reoutline draws them)
				local y, yb = c.fy - gy0, math.min(r.y1 + 1, c.fy + FIN_ROWS - 1) - gy0
				Shading.outline(s.static, fx0, y, fx1, yb, s.sShade)
				contactPass(s, fx0, y, fx1, yb)
				c.fy += FIN_ROWS
				if c.fy > r.y1 + 1 then
					c.phase = 5
				end
			end
			stats.perf.invFinMs += (SG.clock() - f0) * 1000
		end
		if c.phase == 5 then
			SG.waterFix(s, r.x0 - gx0 - 1, r.y0 - gy0 - 1, r.x1 - gx0 + 1, r.y1 - gy0 + 1)
			SG.rect(s, r.x0 - gx0 - 3, r.y0 - gy0 - 3, r.x1 - gx0 + 3, r.y1 - gy0 + 3)
			SG.ver += 1
			buffer.fill(s.sShadowC, 0, 0)
			invCur = nil
			stats.recasts += 1
			staticChanged()
			needFull = true
		end
	end
end


------------------------------------------------------------------ the next tier, cast ahead
-- The request of 2026-11-20: "Is there a way to make island expansion seamless, with no lag? Could you pre render max
-- expansion floors so that expanding simply switches to that expansion level?" PlotService puts the player's next
-- island in the world ahead of time (workspace.Staged.Plot_<i>: the chunks the next tier changes, and the Tree of
-- Life's next stage when it grows one) in collision groups that nothing collides with and no ray meets but "PreCast".
-- Here, in the frames' spare time, the picture of the island as the next tier will have it is cast tile by tile of the
-- pan cache's grid (into a store of its own, PanCache.new) around the view: the bake's own casts on a small layer of
-- a tile and 2 px round it, its rays in "PreCast" and past the chunks and the tree the staged ones replace. When the
-- expansion moves them onto the island, those tiles go into the pan cache and onto the layer the way a pan brings a
-- strip back (no ray at all), and the comings and goings of the parts under them cast nothing. Whatever the pre-cast
-- had not reached by then is cast the old way. Every bake, view, tier or stage starts it again (the part ids and the
-- grid it used are gone), and a part that comes or goes over a pre-cast tile drops that tile.
local PC = {}
PC.store = SG.Tiles.new()
PC.TILE = SG.Tiles.TILE
PC.PAD = 2
PC.SIDE = PC.TILE + PC.PAD * 2
PC.MARGIN = 160 -- art px round the layer the pre-cast covers (where the view may be when the island grows)
type PreJob = {
	folder: Instance,
	tier: number,
	newSet: { [Instance]: boolean }, -- the staged models (chunks, the tree)
	newNames: { [string]: Instance }, -- (the same by name: a copy of one arriving in its place is known)
	recast: { [Instance]: boolean }, -- (such copies, each re-cast whole once)
	oldSet: { [Instance]: boolean }, -- the island's models they replace
	region: { [number]: { number } }, -- every tile the swap changes, by key: { tx, ty }
	modelTiles: { [Instance]: { number } }, -- each model's tile keys
	queue: { { number } }, -- tiles to cast, nearest the view first
	done: { [number]: boolean },
	cur: { tx: number, ty: number, phase: number, x: number, y: number }?,
	params: RaycastParams,
	exclVer: number,
	ps: any, -- the small layer a tile is cast on
	olds: { Instance }, -- (oldSet as a list: the rays' filter)
	oldParts: { [Instance]: boolean }, -- every part of the replaced models (a part going may be cut off from its model by then)
	switched: boolean,
	untilT: number, -- (after the swap: kept this long for the parts' comings and goings)
}
PC.job = nil :: PreJob?
PC.dirty = true
PC.tried = -math.huge -- (when a job was last looked for: once a second while there is none)
PC.stats = { tiles = 0, rays = 0, pasted = 0, cast = 0, skipped = 0, reset = 0, other = 0, early = 0, qx = 0, qy = 0, ax = 0, ay = 0 }

function PC.key(tx: number, ty: number): number
	return (tx + 32768) * 65536 + (ty + 32768)
end

-- Forget the pre-cast (it starts again when the frames have time).
preReset = function()
	if PC.job and PC.job.switched and os.clock() < PC.job.untilT then
		return -- (a swap is landing: its sets still answer for the parts coming and going)
	end
	PC.store.clear()
	PC.job = nil
	PC.dirty = true
	PC.stats.reset += 1
end

function PC.myStaged(): Instance?
	local root = workspace:FindFirstChild("Staged")
	local i = Players.LocalPlayer:GetAttribute("Plot")
	if root == nil or type(i) ~= "number" then
		return nil
	end
	return root:FindFirstChild("Plot_" .. i)
end

-- The model of the staged set (or of the ones it replaces) a part belongs to, if any.
function PC.modelOf(job: PreJob, d: Instance): Instance?
	local m: Instance? = d
	for _ = 1, 8 do
		if m == nil then
			return nil
		end
		if job.newSet[m] or job.oldSet[m] then
			return m
		end
		m = m.Parent
	end
	return nil
end

function PC.modelRect(m: Instance): Rect?
	if m:IsA("Model") then
		local cf, size = m:GetBoundingBox()
		return SG.boxRect(cf, size)
	elseif m:IsA("BasePart") then
		return partRect(m)
	end
	return nil
end

-- A job for the staged next island, once all of it is there (its Tier attribute) and the island's picture is up.
function PC.start(s: Surf): boolean
	PC.dirty = false
	local folder = PC.myStaged()
	local tierAttr = if folder then folder:GetAttribute("Tier") else nil
	if folder == nil or type(tierAttr) ~= "number" then
		return false
	end
	local i = Players.LocalPlayer:GetAttribute("Plot")
	local plots = workspace:FindFirstChild("Plots")
	local pm = plots and plots:FindFirstChild("Plot_" .. tostring(i))
	local static = pm and pm:FindFirstChild("Static")
	local landF = static and static:FindFirstChild("Land")
	local land = landF and landF:FindFirstChild("Land")
	local decor = static and static:FindFirstChild("Decor")
	if land == nil then
		return false
	end
	local job: PreJob = {
		folder = folder,
		tier = tierAttr,
		newSet = {},
		newNames = {},
		recast = {},
		oldSet = {},
		region = {},
		modelTiles = {},
		queue = {},
		done = {},
		cur = nil,
		params = RaycastParams.new(),
		exclVer = -1,
		ps = nil,
		olds = {},
		oldParts = {},
		switched = false,
		untilT = 0,
	}
	-- the staged models and the island's ones they stand in for: a chunk by its place (Chunk_<cx>_<cz>_...), the tree
	-- by its piece (<uid>:tree:...)
	local olds: { Instance } = {}
	for _, m in folder:GetChildren() do
		job.newSet[m] = true
		job.newNames[m.Name] = m
		local cxz = string.match(m.Name, "^(Chunk_%-?%d+_%-?%d+_)")
		local uid = string.match(m.Name, "^(%d+:tree:)")
		local from = if cxz then land elseif uid then decor else nil
		local prefix = cxz or uid
		if from and prefix then
			for _, o in from:GetChildren() do
				if o.Name ~= m.Name and string.sub(o.Name, 1, #prefix) == prefix then
					job.oldSet[o] = true
					table.insert(olds, o)
				end
			end
		end
	end
	-- the tiles each of them covers (with its shadow)
	for m in job.newSet do
		job.modelTiles[m] = {}
	end
	for m in job.oldSet do
		job.modelTiles[m] = {}
	end
	for m, keys in job.modelTiles do
		local r = PC.modelRect(m)
		if r then
			for ty = r.y0 // PC.TILE, r.y1 // PC.TILE do
				for tx = r.x0 // PC.TILE, r.x1 // PC.TILE do
					local k = PC.key(tx, ty)
					job.region[k] = { tx, ty }
					table.insert(keys, k)
				end
			end
		end
	end
	-- the rays: as the bake's, past the replaced models and every other plot's staged island, meeting the staged parts
	job.params.FilterType = Enum.RaycastFilterType.Exclude
	job.params.IgnoreWater = true
	job.params.CollisionGroup = "PreCast"
	job.olds = olds
	for _, o in olds do
		for _, d in o:GetDescendants() do
			if d:IsA("BasePart") then
				job.oldParts[d] = true
			end
		end
	end
	local n = PC.SIDE * PC.SIDE
	job.ps = {
		W = PC.SIDE,
		H = PC.SIDE,
		K = s.K,
		view = s.view,
		look = s.look,
		skyRef = s.skyRef,
		cam = s.cam,
		sShade = buffer.create(n * 4),
		sAlbedo = buffer.create(n * 4),
		sDepth = buffer.create(n * 4),
		sNormal = buffer.create(n),
		sLit = buffer.create(n),
		sId = buffer.create(n * 2),
		sShare = buffer.create(n),
		sWClass = buffer.create(n),
		sWave = buffer.create(n),
		m = 0,
		vw = PC.SIDE,
		vh = PC.SIDE,
		ox = 0,
		oy = 0,
	}
	PC.store.setMax(900)
	PC.store.clear()
	PC.job = job
	return true
end

-- The tiles of the region near the layer not cast yet, nearest the middle of the view first.
function PC.queue(job: PreJob, s: Surf)
	PC.stats.qx, PC.stats.qy = s.cam.gx, s.cam.gy
	local gx0, gy0 = s.cam.gx - PC.MARGIN, s.cam.gy - PC.MARGIN
	local gx1, gy1 = s.cam.gx + s.W - 1 + PC.MARGIN, s.cam.gy + s.H - 1 + PC.MARGIN
	local mx, my = (s.cam.gx + s.W / 2) / PC.TILE, (s.cam.gy + s.H / 2) / PC.TILE
	local q = {}
	for k, t in job.region do
		local tx, ty = t[1], t[2]
		if not job.done[k] and tx * PC.TILE + PC.TILE - 1 >= gx0 and tx * PC.TILE <= gx1 and ty * PC.TILE + PC.TILE - 1 >= gy0 and ty * PC.TILE <= gy1 then
			table.insert(q, { tx, ty, (tx + 0.5 - mx) ^ 2 + (ty + 0.5 - my) ^ 2 })
		end
	end
	table.sort(q, function(a, b)
		return a[3] < b[3]
	end)
	job.queue = q
end

-- Cast pre-cast tiles until `deadline`.
function PC.step(s: Surf, deadline: number)
	-- (a swap that has landed lets go once its parts have come and gone: the next island's job can start. Kept, it
	-- cast nothing ahead for the next expansion and went on calling the swapped models' later changes its own: the
	-- report of 2026-11-20, "there are artifacts that appear around after expanding")
	if PC.job and PC.job.switched and os.clock() >= PC.job.untilT then
		preReset()
	end
	if PC.job == nil then
		if not PC.dirty and os.clock() - PC.tried < 1 then
			return
		end
		PC.tried = os.clock()
		if not PC.start(s) then
			return
		end
	end
	local job = PC.job
	if job == nil or job.switched then
		return
	end
	if job.exclVer ~= SG.exclVer then
		job.exclVer = SG.exclVer
		local list = table.clone(excluded)
		for _, o in job.olds do
			table.insert(list, o)
		end
		local root = workspace:FindFirstChild("Staged")
		if root then
			for _, f in root:GetChildren() do
				if f ~= job.folder then
					table.insert(list, f)
				end
			end
		end
		job.params.FilterDescendantsInstances = list
	end
	if job.cur == nil and #job.queue == 0 then
		PC.queue(job, s)
		if #job.queue == 0 then
			return
		end
	end
	local shadows = tierSpec(tier).shadows
	local ps = job.ps
	local saved = params
	params = job.params
	local r0 = bakeRays
	while SG.clock() < deadline do
		local c = job.cur
		if c == nil then
			local nxt = table.remove(job.queue, 1)
			if nxt == nil then
				break
			end
			if job.done[PC.key(nxt[1], nxt[2])] then
				continue
			end
			local v = s.view
			ps.cam = Raster.gridCam(v.rot12, CameraController.gridAt(nxt[1] * PC.TILE - PC.PAD, nxt[2] * PC.TILE - PC.PAD), PC.SIDE, PC.SIDE, s.K, Tuning.CamRayBack)
			c = { tx = nxt[1], ty = nxt[2], phase = 1, x = 0, y = 0 }
			job.cur = c
		end
		local cc = c :: { tx: number, ty: number, phase: number, x: number, y: number }
		local gx0, gy0 = ps.cam.gx, ps.cam.gy
		local n = 0
		while cc.phase <= 2 do
			n += 1
			if n % 24 == 0 and SG.clock() >= deadline then
				break
			end
			local gx, gy = cc.x + gx0, cc.y + gy0
			if (gx % 2 == 0 and gy % 2 == 0) == (cc.phase == 1) then
				castSample(ps, gx, gy, gx, gy, false, shadows)
			end
			cc.x += 1
			if cc.x >= PC.SIDE then
				cc.x = 0
				cc.y += 1
				if cc.y >= PC.SIDE then
					cc.y = 0
					cc.phase += 1
				end
			end
		end
		if cc.phase == 3 then
			-- the tile's shadow edges (its 2 px border sees the neighbours'), then its middle into the store
			if shadows then
				refineShadows(ps, 0, 0, PC.SIDE - 1, PC.SIDE - 1)
			end
			PC.store.save(ps, gx0, gy0, PC.PAD, PC.PAD, PC.PAD + PC.TILE - 1, PC.PAD + PC.TILE - 1)
			-- (a pixel of open sky is drawn by the layer's own height: a tile with any is left to the old way)
			local sky = false
			for y = PC.PAD, PC.PAD + PC.TILE - 1 do
				for x = PC.PAD, PC.PAD + PC.TILE - 1 do
					if buffer.readu16(ps.sId, (y * PC.SIDE + x) * 2) == 0 then
						sky = true
						break
					end
				end
				if sky then
					break
				end
			end
			local k = PC.key(cc.tx, cc.ty)
			if sky then
				PC.store.take(cc.tx, cc.ty)
			else
				job.done[k] = true
				PC.stats.tiles += 1
			end
			job.cur = nil
		end
	end
	params = saved
	PC.stats.rays += bakeRays - r0
end

-- A part came or went over the pre-cast: the tiles under it are cast again (before the swap).
function PC.drop(r: Rect)
	local job = PC.job
	if job == nil or job.switched then
		return
	end
	for ty = r.y0 // PC.TILE, r.y1 // PC.TILE do
		for tx = r.x0 // PC.TILE, r.x1 // PC.TILE do
			local k = PC.key(tx, ty)
			if job.done[k] then
				job.done[k] = nil
				PC.store.take(tx, ty)
			end
		end
	end
	if job.cur then
		local c = job.cur :: { tx: number, ty: number, phase: number, x: number, y: number }
		if c.tx >= r.x0 // PC.TILE and c.tx <= r.x1 // PC.TILE and c.ty >= r.y0 // PC.TILE and c.ty <= r.y1 // PC.TILE then
			job.cur = nil
		end
	end
	job.queue = {}
end

-- The swap: every pre-cast tile of the region into the pan cache and onto the layer (as a pan copies a strip back);
-- the region's other tiles are cast the old way.
function PC.apply(job: PreJob)
	job.switched = true
	job.untilT = os.clock() + 8
	local s = surf
	if s == nil then
		return
	end
	-- (the pan cache starts again from the island as it is now: a tile kept from before the expansion came back on a
	-- pan wherever a change had not dropped it, a square of the old picture, sky where the new rocks are: the report
	-- of 2026-11-20, "there are artifacts that appear around after expanding". The tiles cast ahead go in below.)
	SG.Tiles.clear()
	if baking then
		-- (a whole bake under way has cast part of the island as it was: it starts again, or the rows it had done would
		-- come up with the old island in them, the swap's parts never cast again)
		rebakeAt = os.clock()
		rush = true
	end
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local lx1, ly1 = gx0 + s.W - 1, gy0 + s.H - 1
	PC.stats.ax, PC.stats.ay = gx0, gy0
	local pasted: { Rect } = {}
	local rows: { [number]: { number } } = {}
	for k, t in job.region do
		local tx, ty = t[1], t[2]
		local x0, y0 = tx * PC.TILE, ty * PC.TILE
		local x1, y1 = x0 + PC.TILE - 1, y0 + PC.TILE - 1
		local tile = if job.done[k] then PC.store.take(tx, ty) else nil
		if tile then
			SG.Tiles.put(tx, ty, tile)
			if x1 >= gx0 and y1 >= gy0 and x0 <= lx1 and y0 <= ly1 then
				local q = { x0 = math.max(x0, gx0) - gx0, y0 = math.max(y0, gy0) - gy0, x1 = math.min(x1, lx1) - gx0, y1 = math.min(y1, ly1) - gy0 }
				if SG.Tiles.load(s, gx0, gy0, q.x0, q.y0, q.x1, q.y1) then
					table.insert(pasted, q)
					PC.stats.pasted += 1
				else
					queueRect({ x0 = x0, y0 = y0, x1 = x1, y1 = y1 })
				end
			end
		else
			job.done[k] = nil
			SG.Tiles.drop(x0, y0, x1, y1)
			if x1 >= gx0 and y1 >= gy0 and x0 <= lx1 and y0 <= ly1 then
				PC.stats.cast += 1
				local row = rows[ty]
				if row == nil then
					row = {}
					rows[ty] = row
				end
				table.insert(row, tx)
			end
		end
	end
	-- (the tiles on the layer not cast ahead, joined into runs along each row: a few rects to queue, not hundreds)
	for ty, row in rows do
		table.sort(row)
		local i = 1
		while i <= #row do
			local j = i
			while j < #row and row[j + 1] == row[j] + 1 do
				j += 1
			end
			queueRect({ x0 = row[i] * PC.TILE, y0 = ty * PC.TILE, x1 = row[j] * PC.TILE + PC.TILE - 1, y1 = ty * PC.TILE + PC.TILE - 1 })
			i = j + 1
		end
	end
	if #pasted > 0 then
		-- the ink and the contact shade over the pasted tiles and their edges, the water's frames, the grade
		for _, q in pasted do
			reoutline(s, q.x0, q.y0, q.x1, q.y1)
			SG.waterFix(s, q.x0 - 1, q.y0 - 1, q.x1 + 1, q.y1 + 1)
			SG.rect(s, q.x0 - 3, q.y0 - 3, q.x1 + 3, q.y1 + 3)
		end
		SG.ver += 1
		buffer.fill(s.sShadowC, 0, 0)
		lightStale = true
		staticChanged()
		needFull = true
	end
end

-- Whether part d's coming or going is the swap's and already in the picture (true: nothing to cast for it).
function PC.swap(d: Instance): boolean
	local job = PC.job
	if job == nil then
		return false
	end
	if job.switched and os.clock() >= job.untilT then
		-- (a swap long landed: its models' changes now are ordinary ones)
		preReset()
		return false
	end
	if job.oldParts[d] then
		if not job.switched then
			PC.stats.early += 1
			return false -- (a replaced model's part going before the swap: an ordinary change)
		end
		PC.stats.skipped += 1
		return true
	end
	local m = PC.modelOf(job, d)
	if m == nil then
		if job.switched then
			-- (another copy of a staged model come in its place, as a client sees a model the server parented to nil
			-- on the way: the pre-cast drew the staged copy, so the new one is cast again whole, once, its ids its own,
			-- never a patchwork of the two)
			local a: Instance? = d.Parent
			for _ = 1, 8 do
				if a == nil then
					break
				end
				local twin = job.newNames[(a :: Instance).Name]
				if twin and twin ~= a then
					if not job.recast[a :: Instance] then
						job.recast[a :: Instance] = true
						local r = PC.modelRect(a :: Instance)
						if r then
							queueRect(r)
						end
					end
					PC.stats.skipped += 1
					return true
				end
				a = (a :: Instance).Parent
			end
		end
		PC.stats.other += 1
		return false
	end
	if not job.switched then
		if not job.newSet[m] or d:IsDescendantOf(job.folder) then
			PC.stats.early += 1
			return false -- (an old model's part going before the swap: an ordinary change)
		end
		PC.apply(job)
	end
	-- (a part of a model some of whose tiles were not pre-cast: those were queued by preApply)
	PC.stats.skipped += 1
	return true
end

-- The staged islands (workspace.Staged): their parts hidden from Roblox's own picture (it shows when the pixel filter
-- is off) until they are on an island (watchStatic shows them again), and the player's own pre-cast started again
-- when theirs changes (built afresh, or let go after a swap).
function PC.watch()
	local root = workspace:WaitForChild("Staged", 60)
	if root == nil then
		return
	end
	local function hide(d: Instance)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
	for _, d in root:GetDescendants() do
		hide(d)
	end
	local function mine(d: Instance): boolean
		local f = PC.myStaged()
		return f ~= nil and (d == f or d:IsDescendantOf(f))
	end
	root.DescendantAdded:Connect(function(d: Instance)
		hide(d)
		if mine(d) then
			preReset()
		end
	end)
	root.DescendantRemoving:Connect(function(d: Instance)
		-- (a staged part moving onto the island at a swap is the swap's own: watchStatic sees it land)
		if d:IsA("Folder") and mine(d) then
			preReset()
		end
	end)
	root.ChildAdded:Connect(function(f: Instance)
		f.AttributeChanged:Connect(function(name: string)
			if name == "Tier" and mine(f) then
				PC.dirty = true
			end
		end)
	end)
	for _, f in root:GetChildren() do
		f.AttributeChanged:Connect(function(name: string)
			if name == "Tier" and mine(f) then
				PC.dirty = true
			end
		end)
	end
	Players.LocalPlayer:GetAttributeChangedSignal("Plot"):Connect(preReset)
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
		SG.Tiles.clear() -- (another tier casts its shadows its own way)
		preReset()
		PixelRenderer.Changed:Fire(tier)
	end
end

------------------------------------------------------------------ lifecycle
local function frameStep(dt: number)
	if not started or paused or tier == "off" then
		return
	end
	if rebakeAt >= 0 and os.clock() >= rebakeAt then
		rebakeAt = -1
		startBake()
	end
	refreshExclude()
	if baking then
		local budget = if (PixelRenderer :: any)._hidden then Tuning.PixelHiddenMs else Tuning.PixelBakeMsPerFrame + (if shown and not rush then 0 else 8)
		bakeSome(SG.clock() + budget / 1000)
		if baking and back == nil then
			return -- nothing on screen to keep alive (the first bake, a jump)
		end
	end
	local s = surf
	if s and not baking then
		-- (the picture scrolls only when the view nears its edge, re-centred under it; the view's window moves every
		-- frame: showWindow)
		local tx, ty = CameraController.pan()
		local m = s.m
		local ox, oy = tx - s.cam.gx, ty - s.cam.gy
		local edge = math.min(Tuning.PixelPanEdge, m)
		local sc0 = SG.clock()
		local before = stats.scrolls
		if m == 0 or ox < edge or oy < edge or ox > s.W - s.vw - edge or oy > s.H - s.vh - edge then
			scrollToward(s, tx - m, ty - m)
		end
		showWindow(s)
		if stats.scrolls ~= before then
			SG.panAt = os.clock()
			stats.perf.panFrames += 1
			stats.perf.scrollMs += (SG.clock() - sc0) * 1000
		end
		if baking then
			return -- a jump started a bake
		end
		local i0 = SG.clock()
		processInvalidation()
		stats.perf.invMs += (SG.clock() - i0) * 1000
		-- the frame's spare time: the next tier's picture, cast ahead (nothing else is waiting to be cast)
		if rebakeAt < 0 and invCur == nil and #invQueue == 0 and not s.view.stage and Tuning.PixelPreCastMs > 0 then
			local p0 = SG.clock()
			PC.step(s, p0 + Tuning.PixelPreCastMs / 1000)
			stats.perf.preMs += (SG.clock() - p0) * 1000
		end
	elseif s then
		-- (a re-bake behind the picture on screen: the view still moves within its margin)
		showWindow(s)
	end
	-- the water's frames (not on the low tier): a changed frame is copied and uploaded whole by the next compose
	if s and tier ~= "low" then
		waterClock += dt
		local w0 = SG.clock()
		-- (the next frame's slices due by now: all of them by the period's end; SG.waterSlice)
		local S = SG.WATER_SLICES
		local due = math.min(S, math.floor(waterClock * WATER_HZ * S))
		while SG.waterDone < due do
			SG.waterSlice(s, SG.waterDone)
			SG.waterDone += 1
		end
		local w1 = SG.clock()
		if waterClock >= 1 / WATER_HZ then
			waterClock = 0
			if SG.waterApply(s) and not SG.live(s) then
				needFull = true
			end
			waterFrame += 1
			SG.waterDone = 0
			SG.windDone, SG.windVoid = 0, false
			stats.perf.waterMs += (SG.clock() - w0) * 1000
		else
			stats.perf.waterMs += (w1 - w0) * 1000
		end
	end
	local hz = tierSpec(tier).hz
	tickAcc += dt
	SG.dynAcc += dt
	if tickAcc >= 1 / hz or needFull or SG.panned or SG.touch then
		tickAcc = 0
		-- (the moving models change at hz even while a pan composes every frame)
		local due = SG.dynAcc >= 1 / hz
		if due then
			SG.dynAcc = 0
		end
		compose(due)
	end
end

local function watchStatic()
	-- a part that comes or goes anywhere on the street (decor placed, a neighbour's studio built or gone) re-casts
	-- the rect it and its shadow cover (a big change re-bakes the layer behind the old picture)
	local plots = workspace:WaitForChild("Plots", 30)
	if plots == nil then
		return
	end
	-- A part came to or left a model lit as one smooth surface (the Tree of Life; `sm`, SmoothParts.changed has dropped
	-- its balls already): the whole model's box is cast again once this frame, since every pixel of it was lit from the
	-- balls there were (in the game the tree's parts arrive over several frames).
	local smoothDirty: { [Model]: boolean } = {}
	local function smoothRecast(m: Model)
		if smoothDirty[m] then
			return
		end
		smoothDirty[m] = true
		task.defer(function()
			smoothDirty[m] = nil
			if rebakeAt >= 0 or m.Parent == nil or surf == nil or CameraController.view().stage then
				return
			end
			local cf, size = m:GetBoundingBox()
			local r = SG.boxRect(cf, size)
			if r then
				queueRect(r)
				PC.drop(r)
			end
		end)
	end
	local function poke(d: Instance, sm: Model?)
		if not d:IsA("BasePart") or surf == nil then
			return
		end
		-- (an invisible wall, or the part keeping a bevel's cut corner solid: never in the picture)
		local g = d.CollisionGroup
		if g == "Bounds" or g == "StagedBounds" or d.Transparency >= 1 then
			return
		end
		if CameraController.view().stage then
			-- the street is not on screen: its kept picture is out of date
			local st = stash
			if st then
				st.dirty = true
			end
			preReset()
			return
		end
		-- (the next island's parts landing, and the ones they replace going: already in the picture, pre-cast)
		if PC.swap(d) then
			return
		end
		if rebakeAt >= 0 then
			return -- a whole re-bake is coming: no rect to work out (a rebuilt island is ~2,500 of these at once)
		end
		local p0 = SG.clock()
		local r = partRect(d)
		if r then
			queueRect(r)
			PC.drop(r)
		end
		if sm then
			smoothRecast(sm)
		end
		stats.perf.pokes += 1
		stats.perf.pokeMs += (SG.clock() - p0) * 1000
	end
	plots.DescendantAdded:Connect(function(d: Instance)
		-- (a staged part, hidden from Roblox's own picture while it waited, is on the island now)
		if d:IsA("BasePart") and d.LocalTransparencyModifier ~= 0 then
			d.LocalTransparencyModifier = 0
		end
		poke(d, SmoothParts.changed(d))
	end)
	plots.DescendantRemoving:Connect(function(d: Instance)
		poke(d, SmoothParts.changed(d))
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
	RunService.Heartbeat:Connect(function(dt: number)
		local t0 = SG.clock()
		frameStep(dt)
		stats.perf.frames += 1
		local ms = (SG.clock() - t0) * 1000
		stats.perf.stepMs += ms
		stats.perf.maxMs = math.max(stats.perf.maxMs, ms)
		if ms > 25 then
			stats.perf.slow += 1
		end
	end)
	task.spawn(watchStatic)
	task.spawn(PC.watch)
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
	if bakePass > 3 then
		return false, 0.99
	end
	local p = math.clamp(bakePass, 1, 3)
	return false, math.clamp(passShare[p] + weight[p] * (bakeGY - bakeRY0) / rows, 0, 0.99)
end

function PixelRenderer.registerDynamic(model: Model, outline: string?)
	local parts: { DynPart } = {}
	-- (an egg, a driftling: lit as one smooth surface across its balls, Render/Smooth)
	local smoothModel = model:GetAttribute("PixelSmooth") == true
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
			-- (a smooth solid the driftling kit sculpts with: an ellipsoid, an egg, a tapered limb, Raster.drawSolid)
			local solid = d:GetAttribute("PixelShape")
			local prm = d:GetAttribute("PixelK")
			if type(solid) == "string" and Raster.SOLID_KIND[solid] then
				shape = solid
			end
			-- (a mark painted onto the face, not drawn: Kit.blush's "PixelPaint" oval)
			local paint: { a: Vector3, b: Vector3, n: Vector3 }? = nil
			if d:GetAttribute("PixelPaint") == true then
				local pa, pb, pn = d:GetAttribute("PixelPaintA"), d:GetAttribute("PixelPaintB"), d:GetAttribute("PixelPaintN")
				if typeof(pa) == "Vector3" and typeof(pb) == "Vector3" and typeof(pn) == "Vector3" then
					paint = { a = pa, b = pb, n = pn }
				end
			end
			-- (a member of the model's blended body: its blend radius as a share of its largest size, Raster.drawBlend)
			local blendAttr = d:GetAttribute("PixelBlend")
			local blend = if type(blendAttr) == "number" and blendAttr > 0 and (shape == "Ell" or shape == "Egg" or shape == "Cone") then blendAttr else nil
			-- (a driftling's eye: painted as it is drawn, Render/EyeTex)
			local eyeStyle = d:GetAttribute("PixelEye")
			local eye: EyeSpec? = nil
			if type(eyeStyle) == "string" and SG.EyeTex.STYLE[eyeStyle] then
				local ci, cd, cl = d:GetAttribute("PixelEyeIris"), d:GetAttribute("PixelEyeDark"), d:GetAttribute("PixelEyeLid")
				local sd = d:GetAttribute("PixelEyeSide")
				eye = {
					code = SG.EyeTex.STYLE[eyeStyle],
					iris = if typeof(ci) == "Color3" then rgbOf(ci) else 0x4060C0,
					dark = if typeof(cd) == "Color3" then rgbOf(cd) else 0x202028,
					lid = if typeof(cl) == "Color3" then rgbOf(cl) else 0x808080,
					side = if type(sd) == "number" then sd else 1,
				}
			end
			local attr = d:GetAttribute("PixelColor")
			local rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(d.Color)
			nextDyn += 1
			if nextDyn >= 65535 then
				nextDyn = DYN_ID0 + 1
			end
			local glow = d.Material == Enum.Material.Neon
			dynGlow[nextDyn] = glow
			local texName = d:GetAttribute("PixelTex")
			local tex = if glow or type(texName) ~= "string" then 0 else DynTex.kind(texName)
			-- (a pattern shared by several parts: PixelTexV lifts v by studs, PixelTexSeed keeps one seed; PixelTexSoft
			-- how far its marks step, DynTex.SOFT unless set)
			local tv, ts, tsoft = d:GetAttribute("PixelTexV"), d:GetAttribute("PixelTexSeed"), d:GetAttribute("PixelTexSoft")
			-- (in a model lit smooth: the part's role, Render/Smooth)
			local sm = if smoothModel then SmoothParts.role(d) else 0
			table.insert(parts, {
				part = d,
				id = nextDyn,
				shape = shape,
				glow = glow,
				rgb = rgb,
				tex = tex,
				texV = if type(tv) == "number" then tv else 0,
				texSeed = if type(ts) == "number" then ts else nil,
				texSoft = if type(tsoft) == "number" then tsoft else DynTex.SOFT,
				sm = sm,
				prm = if type(prm) == "number" then prm else nil,
				eye = eye,
				blend = blend,
				paint = paint,
			})
		end
	end
	-- (its ids run lo .. hi unless they wrapped round past 65535: then hi < lo and its picture is never kept)
	local lo = if #parts > 0 then parts[1].id else 0
	local hi = if #parts > 0 then parts[#parts].id else -1
	SG.forget(dyns[model])
	-- (a model standing where a static one is being cast, Build mode's landed stand-in: "PixelLead" studs nearer, so it
	-- wins the ties with the static pixels cast under it so far and they never show through it)
	local lead = model:GetAttribute("PixelLead")
	dyns[model] = { model = model, parts = parts, rim = outline == "self" or outline == "player", own = outline == "self", smooth = smoothModel, lo = lo, hi = hi, lead = if type(lead) == "number" then lead else nil }
end

-- A static part leaves the picture (Controllers/Spinners: a turning copy of it is drawn as a moving model instead):
-- looked through from now on (Transparency 1: BakeCast passes it by), the rect it and its shadow cover cast again.
function PixelRenderer.hideStatic(part: BasePart)
	if part.Transparency >= 0.95 then
		return
	end
	part.Transparency = 1
	if surf == nil then
		return
	end
	if CameraController.view().stage then
		local st = stash
		if st then
			st.dirty = true
		end
		return
	end
	if rebakeAt >= 0 then
		return
	end
	local r = partRect(part)
	if r then
		queueRect(r)
	end
end

-- Moving model `model` stands at `now` (world), its parts posed at `posed` (Controllers/WorldView: a driftling walks on
-- every frame, its pose waits for the frame's budget). Its kept picture slides from where it was drawn to `now` by whole
-- art px every tick (SG.glideOf), its blob shadow with it; nil: no more of it.
function PixelRenderer.glide(model: Model, now: Vector3?, posed: Vector3?)
	local d = dyns[model]
	if d then
		d.gNow, d.gPosed = now, posed
	end
end

function PixelRenderer.unregisterDynamic(model: Model)
	SG.forget(dyns[model])
	dyns[model] = nil
end

-- A moving model leaves (or is registered again): where it and its blob shadow showed is drawn again by the next
-- incremental compose.
function SG.forget(d: Dyn?)
	if d == nil or SG.incOn == nil then
		return
	end
	if d.shR then
		table.insert(SG.dirty, d.shR)
	end
	if d.sR then
		table.insert(SG.dirty, d.sR)
	end
end

-- Re-colour a registered model's parts after their Color changed (a monitor lighting up).
function PixelRenderer.refreshDynamic(model: Model, keepPoses: boolean?)
	local d = dyns[model]
	if d then
		for _, p in d.parts do
			local attr = p.part:GetAttribute("PixelColor")
			p.rgb = if typeof(attr) == "Color3" then rgbOf(attr) else rgbOf(p.part.Color)
			p.glow = p.part.Material == Enum.Material.Neon
			dynGlow[p.id] = p.glow
		end
		d.cache = nil
		-- (its pictures by pose go too, unless its pose keys already tell its colours apart: keepPoses)
		if not keepPoses then
			d.poses, d.poseOrder = nil, nil
		end
	end
end

-- Moving model `model` is posed as `key` from now on (nil: it says no more): each pose's picture is kept, and posed in
-- one it had again (its parts placed the same way round the point it glides from, PixelRenderer.glide) that picture is
-- put down, slid to where it stands, in place of a draw. Say the key whenever the parts are posed.
function PixelRenderer.pose(model: Model, key: string?)
	local d = dyns[model]
	if d then
		d.poseKey = key
		if key == nil then
			d.poses, d.poseOrder = nil, nil
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

-- While the screen is hidden (Build mode's expansion behind the loading card), a bake or a re-cast may take
-- Tuning.PixelHiddenMs of each frame (kept on the module table: the main chunk is at Luau's 200 registers).
function PixelRenderer.setHidden(on: boolean)
	(PixelRenderer :: any)._hidden = on
end

-- Whether the picture has work still to come: a bake under way or due, rects waiting to be cast again (Build mode's
-- expansion keeps its cover up until there is none). False in the classic style.
function PixelRenderer.busy(): boolean
	if tier == "off" or surf == nil then
		return false
	end
	return baking or rebakeAt >= 0 or #invQueue > 0 or invCur ~= nil
end

-- fn runs right after each new picture is drawn (nil: none), with the world as that picture shows it: an overlay that
-- must sit on a moving model (the hatch scene's rays on the egg's cracks) places itself then, not on every frame, since
-- the picture is drawn fewer times a second than the screen. (Kept on the module table: the main chunk is at Luau's
-- 200 registers.)
function PixelRenderer.onComposed(fn: (() -> ())?)
	(PixelRenderer :: any)._composed = fn
end

-- The layer shifted by whole art px (a hit's jolt on a minigame's stage); 0, 0 puts it back.
function PixelRenderer.setOffset(dx: number, dy: number)
	-- (kept nowhere else: the main chunk is at Luau's 200 registers)
	local offX, offY = math.floor(dx + 0.5), math.floor(dy + 0.5)
	local im = image
	if im then
		local K = if surf then (surf :: Surf).K else CameraController.pixelK()
		im.Position = UDim2.fromOffset(offX * K, offY * K)
	end
end

-- fn runs once the picture shows what is in the world now: after the pending or running bake, or at once when none
-- is coming (or the filter is off). Build mode's expansion cheers when the bigger island is on screen.
function PixelRenderer.afterBake(fn: () -> ())
	if surf == nil or tier == "off" or not started or (not baking and rebakeAt < 0) then
		task.spawn(fn)
		return
	end
	table.insert(afterBake, fn)
end

-- Whether the picture has still to catch up with model `model` where it stands: a whole bake running or coming, or a
-- re-cast queued or under way over any of its parts (their rects with their shadows). Build mode keeps a piece's
-- stand-in drawn until this is false, so the piece never leaves the screen between its landing and its cast (the report
-- of 2026-11-20: "they seem to vanish for awhile before appearing, especially for bigger buildings"). Always false in
-- the classic style.
function PixelRenderer.casting(model: Instance): boolean
	if tier == "off" or surf == nil then
		return false
	end
	if baking or rebakeAt >= 0 then
		return true
	end
	local cur = invCur
	if #invQueue == 0 and cur == nil then
		return false
	end
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local r = partRect(d)
			if r then
				x0, y0, x1, y1 = math.min(x0, r.x0), math.min(y0, r.y0), math.max(x1, r.x1), math.max(y1, r.y1)
			end
		end
	end
	if x0 > x1 then
		return false
	end
	local function over(q: Rect): boolean
		return q.x1 >= x0 and q.x0 <= x1 and q.y1 >= y0 and q.y0 <= y1
	end
	if cur and over(cur.r) then
		return true
	end
	for _, q in invQueue do
		if over(q) then
			return true
		end
	end
	return false
end

-- A stage's folder of static parts (an endless islet's areas come and go as the party runs on): a part added or
-- removed while the stage is in view re-casts the rect it covers, like the islands' (a whole re-bake is never needed:
-- the areas are built and dropped out of sight).
function PixelRenderer.watchStage(root: Instance)
	local function poke(d: Instance)
		if not d:IsA("BasePart") or surf == nil or rebakeAt >= 0 or not CameraController.view().stage then
			return
		end
		local r = partRect(d)
		if r then
			queueRect(r)
		end
	end
	root.DescendantAdded:Connect(poke)
	root.DescendantRemoving:Connect(function(d: Instance)
		poke(d)
		staticIds[d] = nil
	end)
end

function PixelRenderer.rebake()
	if surf then
		startBake()
	end
end

function PixelRenderer.setPaused(on: boolean)
	paused = on
end

-- An effect layer (Render/Fx): `draw` runs every tick (the tier's rate, not while paused or in the classic style)
-- after the dynamic models, with a Fx.Ctx over the frame (Fx.dot / mix / drawSprite / step). Layers added later draw
-- first, under the older ones. A layer that errors is removed (with a warning). Returns a function that removes it.
function PixelRenderer.addFxLayer(name: string, draw: (ctx: Fx.Ctx) -> ()): () -> ()
	local L: FxLayer = { name = name, draw = draw, last = os.clock() }
	table.insert(fxLayers, L)
	fxStats.layers = #fxLayers
	return function()
		local i = table.find(fxLayers, L)
		if i then
			table.remove(fxLayers, i)
		end
		fxStats.layers = #fxLayers
		-- (what it stuck goes with it)
		staticChanged()
		needFull = true
		SG.ok = false
	end
end

-- Previews and sims: the last tick's effects: the layers' ms, the books' ms (what changed, the runs), the pixels
-- written, those that changed, the rects uploaded and their pixels, the ticks so far and the layers.
function PixelRenderer.fxStats(): { ms: number, bookMs: number, px: number, changed: number, rects: number, upPx: number, ticks: number, layers: number }
	return table.clone(fxStats)
end

-- A world point in full-screen px (ScreenInsets None space) and whether it is on screen: the layer's own camera
-- snapped to K when the filter is on, the Roblox camera otherwise.
function PixelRenderer.project(world: Vector3): (Vector2, boolean)
	local s = surf
	if s and tier ~= "off" then
		local px, py, d = Raster.project(s.cam, world.X, world.Y, world.Z)
		-- (on the screen: the layer less the window's place in it, showWindow)
		local x, y = (math.floor(px) - s.ox) * s.K, (math.floor(py) - s.oy) * s.K
		return Vector2.new(x, y), d > 0 and x >= 0 and y >= 0 and x < s.view.fullX and y < s.view.fullY
	end
	local cam = workspace.CurrentCamera
	if cam == nil then
		return Vector2.zero, false
	end
	local p, on = cam:WorldToViewportPoint(world)
	return Vector2.new(p.X, p.Y), on
end

-- The art pixel under a screen point (pos = InputObject.Position, below the top bar), as `projectPixel` gives
-- them: the stage's screens compare a pointer with what stands there.
function PixelRenderer.pixelAt(pos: Vector2): (number, number)
	local inset = GuiService:GetGuiInset()
	local x, y = pos.X + inset.X, pos.Y + inset.Y
	local s = surf
	if s and tier ~= "off" then
		local cam = s.cam
		return math.floor((x + cam.offX) / cam.K), math.floor((y + cam.offY) / cam.K)
	end
	local k = PixelRenderer.pixelScale()
	return math.floor(x / k), math.floor(y / k)
end

-- The pick ray through a screen point (pos = InputObject.Position, below the top bar): origin and direction * length,
-- through what the layer shows (its own camera, the pan it shows) when the filter is on, the Roblox camera's otherwise.
function PixelRenderer.screenRay(pos: Vector2): (Vector3, Vector3)
	local inset = GuiService:GetGuiInset()
	local x, y = pos.X + inset.X, pos.Y + inset.Y
	local s = surf
	if s and tier ~= "off" then
		local cam = s.cam
		local i = math.clamp(math.floor((x + cam.offX) / cam.K) + s.ox, 0, cam.W - 1)
		local j = math.clamp(math.floor((y + cam.offY) / cam.K) + s.oy, 0, cam.H - 1)
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
-- Whether a world point is on the screen or within `pad` art px of it (the pixel layer's; the camera's viewport in the
-- classic style). The world view gives a driftling its model by it, the spinners turn by it.
function PixelRenderer.nearScreen(world: Vector3, pad: number): boolean
	local s = surf
	if s and tier ~= "off" then
		local px, py = Raster.project(s.cam, world.X, world.Y, world.Z)
		px, py = px - s.ox, py - s.oy
		return px >= -pad and py >= -pad and px < s.vw + pad and py < s.vh + pad
	end
	local cam = workspace.CurrentCamera
	if cam == nil then
		return true
	end
	local p = cam:WorldToViewportPoint(world)
	local v = cam.ViewportSize
	local k = pad * 3
	return p.Z > 0 and p.X >= -k and p.Y >= -k and p.X < v.X + k and p.Y < v.Y + k
end

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
	SG.ok = false
end

-- A packed pixel (R in the low byte, alpha in the high one, as Pixel/Snapshot's pictures) in the light the world is
-- drawn in now (the grade; as it is with none), or in grade `g`: a picture drawn apart from the world that sits in it,
-- the hatch scene's baked driftling (UI/HatchScene).
function PixelRenderer.gradePixel(c: number, g: Grade?): number
	local use = g or grade
	if use == nil then
		return c
	end
	return gradeOf(c, 0, use)
end

-- The spotlight (nothing sets it now): the static picture darkened by k (0 .. 1, taken in tenths; each step
-- re-uploads the picture), the dynamic things as they are.
function PixelRenderer.setDim(k: number)
	local q = math.floor(math.clamp(k, 0, 1) * 10 + 0.5) / 10
	if q == dim then
		return
	end
	dim = q
	table.clear(dimMap)
	needFull = true
	SG.ok = false
end

-- Sims and previews: the founders' rims last tick (how many, the white pixels laid, the ms they took) and the models
-- registered with a rim now.
function PixelRenderer.debugRims(): { drawn: number, px: number, ms: number, registered: number }
	local reg = 0
	for _, d in dyns do
		if d.rim then
			reg += 1
		end
	end
	local st = Rims.stats
	return { drawn = st.drawn, px = st.px, ms = st.ms, registered = reg }
end

-- Whether a model is registered with a founder's white rim (registerDynamic outline "self" or "player").
function PixelRenderer.hasRim(model: Model): boolean
	local d = dyns[model]
	return d ~= nil and d.rim == true
end

-- Sims and previews: the spotlight's dimming now.
-- Previews: where the frames' time went since the last read (ms summed: the scrolls of the frames that panned, the
-- composes, the full uploads and their grade), then the counters start again.
function PixelRenderer.debugPerf(): { frames: number, panFrames: number, scrollMs: number, composeMs: number, uploadMs: number, gradeMs: number, stepMs: number, invMs: number, invFinMs: number, pokeMs: number, pokes: number, uploads: number, regrades: number, castMs: number, inkMs: number, dynMs: number, outlineMs: number, rimMs: number, fxMs: number, waterMs: number, windMs: number, copyMs: number, maxMs: number, slow: number, hits: number, draws: number, incFrames: number, incPx: number, fullFrames: number }
	local perf = stats.perf
	local out: any = table.clone(perf)
	for k in perf do
		perf[k] = 0
	end
	out.hits, out.draws = SG.hits, SG.draws
	SG.hits, SG.draws = 0, 0
	local by = {}
	for k, v in SG.markBy do
		table.insert(by, string.format("%s %d", k, v))
	end
	table.sort(by)
	out.markBy = table.concat(by, ", ")
	table.clear(SG.markBy)
	out.skips = SG.skips
	SG.skips = 0
	local why = {}
	for k, v in SG.skipWhy do
		table.insert(why, string.format("%s %d", k, v))
	end
	out.skipWhy = table.concat(why, ", ")
	table.clear(SG.skipWhy)
	out.cache = SG.Tiles.stats()
	return out
end

-- The next tier's pre-cast: its counts since the last call (tiles cast, their rays, tiles pasted at a swap, tiles cast
-- the old way at a swap, parts whose coming or going cast nothing, resets) and the job now (nil: none).
function PixelRenderer.debugPre(): { tiles: number, rays: number, pasted: number, cast: number, skipped: number, reset: number, job: { tier: number, region: number, done: number, queued: number, switched: boolean, news: number, olds: number }? }
	local out: any = table.clone(PC.stats)
	for k in PC.stats do
		PC.stats[k] = 0
	end
	local job = PC.job
	if job then
		local region, done, news, olds = 0, 0, 0, 0
		for _ in job.region do
			region += 1
		end
		for _ in job.done do
			done += 1
		end
		for _ in job.newSet do
			news += 1
		end
		for _ in job.oldSet do
			olds += 1
		end
		out.job = { tier = job.tier, region = region, done = done, queued = #job.queue, switched = job.switched, news = news, olds = olds }
	end
	return out
end

-- Sims and previews: the sea as the water pass leaves it against shading every water pixel for the frame now (off:
-- the water pixels showing a tone not the frame's; ink and the wind's paint are not water colours and are left out).
function PixelRenderer.debugWaterCheck(): { off: number, checked: number, wind: number }
	local s = surf
	local wind = 0
	for _ in windWrote do
		wind += 1
	end
	local out = { off = -1, checked = 0, wind = wind }
	if s == nil or baking or tier == "low" then
		return out
	end
	out.off = 0
	local cls, wave, shade, color = s.sWClass, s.sWave, s.sShade, s.sColor
	for i = 0, s.W * s.H - 1 do
		local c = buffer.readu8(cls, i)
		if c ~= 0 and (c <= 3 or c == 6) then
			local base = buffer.readu32(shade, i * 4)
			local cur = buffer.readu32(color, i * 4)
			if cur == base or cur == waterColor(base, c, 1) or cur == waterColor(base, c, 2) or cur == waterColor(base, c, 3) then
				out.checked += 1
				if cur ~= waterColor(base, c, waterTone(c, buffer.readu8(wave, i), waterFrame)) then
					out.off += 1
				end
			end
		end
	end
	return out
end

-- Sims and previews: the static layer against casting all of it afresh at the pan it is at (a pan's strips, cast or
-- taken back from the pan cache, should give the same pixels as one whole cast). off: the pixels whose part, depth,
-- normal, light, water or shade differ. The layer is put back as it was afterwards.
-- With `full`: the ink and the contact shade are drawn again too and the colour compared (inkOff: pixels whose cast
-- matched but whose drawn colour did not, water left out), and the off pixels sorted: skyOver (the layer shows nothing
-- where a fresh cast meets a part), ghost (the layer shows a part where a fresh cast meets nothing), the 32 px tiles of
-- the world's grid they fall in (tiles), their box on the layer (box) and, with `mask`, a byte a layer pixel (1 sky
-- over, 2 ghost, 3 another part or depth, 4 ink only, 5 a tie: another part at the same depth).
function PixelRenderer.debugCastCheck(full: boolean?, mask: boolean?): { off: number, checked: number, ids: number, lits: number, shades: number, ties: number?, ex: string?, tieEx: string?, inkOff: number?, skyOver: number?, ghost: number?, tiles: number?, box: { number }?, mask: buffer? }
	local s = surf
	local out: any = { off = -1, checked = 0, ids = 0, lits = 0, shades = 0 }
	if s == nil or baking then
		return out
	end
	windRestore(s)
	SG.windVoid = true
	table.clear(SG.windPend)
	local saved: { [string]: buffer } = {}
	local names = { "sShade", "sAlbedo", "sDepth", "sNormal", "sLit", "sId", "sShare", "sWClass", "sWave" }
	if full then
		table.insert(names, "sColor")
	end
	local sa = s :: any
	for _, k in names do
		saved[k] = buffer.create(buffer.len(sa[k]))
		buffer.copy(saved[k], 0, sa[k], 0)
	end
	local rays0 = bakeRays
	castRect(s, 0, 0, s.W - 1, s.H - 1)
	if full then
		reoutline(s, 0, 0, s.W - 1, s.H - 1)
	end
	bakeRays = rays0
	out.off = 0
	local n = s.W * s.H
	local mk = if mask then buffer.create(n) else nil
	local tileSet: { [number]: boolean } = {}
	local bx0, by0, bx1, by1 = math.huge, math.huge, -1, -1
	local gx0, gy0 = s.cam.gx, s.cam.gy
	if full then
		out.inkOff, out.skyOver, out.ghost = 0, 0, 0
	end
	for i = 0, n - 1 do
		local idOff = buffer.readu16(s.sId, i * 2) ~= buffer.readu16(saved.sId, i * 2)
		local litOff = buffer.readu8(s.sLit, i) ~= buffer.readu8(saved.sLit, i)
		local shadeOff = buffer.readu32(s.sShade, i * 4) ~= buffer.readu32(saved.sShade, i * 4)
		local other = math.abs(buffer.readf32(s.sDepth, i * 4) - buffer.readf32(saved.sDepth, i * 4)) > 1e-3
			or buffer.readu8(s.sNormal, i) ~= buffer.readu8(saved.sNormal, i)
			or buffer.readu32(s.sAlbedo, i * 4) ~= buffer.readu32(saved.sAlbedo, i * 4)
			or buffer.readu8(s.sWClass, i) ~= buffer.readu8(saved.sWClass, i)
			or buffer.readu8(s.sWave, i) ~= buffer.readu8(saved.sWave, i)
		if idOff then
			out.ids += 1
		end
		if litOff then
			out.lits += 1
		end
		if shadeOff then
			out.shades += 1
		end
		-- (two parts' faces at the very same depth: which one a ray meets first is the ray index's to say, and an index
		-- built for other filters may say the other)
		local tie = idOff and math.abs(buffer.readf32(s.sDepth, i * 4) - buffer.readf32(saved.sDepth, i * 4)) <= 1e-3
		if tie then
			out.ties = (out.ties or 0) + 1
		end
		local inkOnly = full and not (idOff or litOff or shadeOff or other) and buffer.readu8(s.sWClass, i) == 0 and buffer.readu32(s.sColor, i * 4) ~= buffer.readu32(saved.sColor, i * 4)
		if full and (idOff or litOff or shadeOff or other or inkOnly) then
			local code = if tie then 5 else 3
			if inkOnly then
				out.inkOff += 1
				code = 4
			elseif buffer.readu16(saved.sId, i * 2) == 0 and buffer.readu16(s.sId, i * 2) ~= 0 then
				out.skyOver += 1
				code = 1
			elseif buffer.readu16(saved.sId, i * 2) ~= 0 and buffer.readu16(s.sId, i * 2) == 0 then
				out.ghost += 1
				code = 2
			end
			local x, y = i % s.W, i // s.W
			tileSet[((gx0 + x) // 32 + 32768) * 65536 + ((gy0 + y) // 32 + 32768)] = true
			bx0, by0, bx1, by1 = math.min(bx0, x), math.min(by0, y), math.max(bx1, x), math.max(by1, y)
			if mk then
				buffer.writeu8(mk, i, code)
			end
		end
		if tie and full and (out.tieN or 0) < 6 then
			-- (a few of the ties too, for the log: which two parts the layer and a fresh cast meet)
			out.tieN = (out.tieN or 0) + 1
			local idNames: { [number]: string } = out.revFull or {}
			if out.revFull == nil then
				for part, id in staticIds do
					local ok, name = pcall(function(): string
						return (part :: Instance):GetFullName()
					end)
					idNames[id] = (if ok then name else "?") .. (if (part :: Instance):IsDescendantOf(game) then "" else " (gone)")
				end
				out.revFull = idNames
			end
			local a, b = buffer.readu16(saved.sId, i * 2), buffer.readu16(s.sId, i * 2)
			out.tieEx = (out.tieEx or "") .. string.format("[%d,%d %s #%d / %s #%d at %.2f] ", i % s.W, i // s.W, tostring(idNames[a]), a, tostring(idNames[b]), b, buffer.readf32(s.sDepth, i * 4))
		end
		if idOff or litOff or shadeOff or other then
			out.off += 1
			if not tie and (out.real or 0) < 8 then
				out.real = (out.real or 0) + 1
				-- (a few of them, for the log: the part each cast met and how deep)
				local rev: { [number]: string } = out.rev or {}
				if out.rev == nil then
					for part, id in staticIds do
						local par = (part :: Instance).Parent
						rev[id] = (part :: Instance).Name .. "@" .. (if par then par.Name else "?")
					end
					out.rev = rev
				end
				local a, b = buffer.readu16(saved.sId, i * 2), buffer.readu16(s.sId, i * 2)
				out.ex = (out.ex or "") .. string.format("[%d,%d %s %.2f / %s %.2f%s%s] ", i % s.W, i // s.W, tostring(rev[a]), buffer.readf32(saved.sDepth, i * 4), tostring(rev[b]), buffer.readf32(s.sDepth, i * 4), if shadeOff then " shade" else "", if litOff then " sun" else "")
			end
		end
	end
	out.rev = nil
	out.revFull = nil
	out.checked = n
	for _, k in names do
		buffer.copy(sa[k], 0, saved[k], 0)
	end
	if full then
		local nt = 0
		for _ in tileSet do
			nt += 1
		end
		out.tiles = nt
		out.box = if bx1 >= 0 then { bx0, by0, bx1, by1 } else nil
		out.mask = mk
	end
	return out
end

-- Sims and previews: whether the graded static picture (SG) is in step with the static layer (off: its pixels that
-- differ from grading sColor afresh; a re-cast still going may differ where it has got to), and whether the whole
-- image last uploaded matches grading the frame afresh (image: pixels off, -1 when the last upload was not whole).
function PixelRenderer.debugGradeCheck(): { checked: number, off: number, image: number, recasting: boolean }
	local s = surf
	local b = SG.buf
	local out = { checked = 0, off = 0, image = -1, recasting = invCur ~= nil }
	if s == nil or b == nil or not SG.ok or SG.on ~= s or not (grade or dim > 0) then
		return out
	end
	local n = s.W * s.H
	local t = buffer.create(n * 4)
	gradeSpan(s.sColor, s.sId, 0, n, t, 0)
	for i = 0, n - 1 do
		if buffer.readu32(t, i * 4) ~= buffer.readu32(b, i * 4) then
			out.off += 1
		end
	end
	out.checked = n
	local o = SG.out
	if SG.fullAt == SG.seq and o and buffer.len(o) == n * 4 then
		gradeSpan(s.frame.color, s.frame.id, 0, n, t, 0)
		out.image = 0
		for i = 0, n - 1 do
			if buffer.readu32(t, i * 4) ~= buffer.readu32(o, i * 4) then
				out.image += 1
			end
		end
	end
	return out
end

-- Sims and previews: the incremental compose's base against its frame. Pixels where the frame differs from the base
-- other than this tick's effects and the stuck ones: the base is out of step there, and taking an effect off would put
-- back a wrong colour (n: how many, -1 when no incremental compose is going; rows: the rows with eight or more). The
-- sweep of 2026-11-19 found a re-bake leaving the old place's base under the new picture.
function PixelRenderer.debugBaseCheck(): { n: number, rows: string }
	local s = surf
	local b = SG.base
	if s == nil or b == nil or SG.incOn ~= s then
		return { n = -1, rows = "" }
	end
	local W, H = s.W, s.H
	local skip: { [number]: boolean } = {}
	for k = 0, fxPrevN - 1 do
		skip[buffer.readu32(fxPrev, k * 4)] = true
	end
	for _, i in stickList do
		skip[i] = true
	end
	local f = s.frame
	local total = 0
	local rows: { string } = {}
	for y = 0, H - 1 do
		local c = 0
		for x = 0, W - 1 do
			local i = y * W + x
			if not skip[i] and buffer.readu32(f.color, i * 4) ~= buffer.readu32(b.color, i * 4) then
				c += 1
			end
		end
		total += c
		if c >= 8 then
			table.insert(rows, y .. ":" .. c)
		end
	end
	return { n = total, rows = table.concat(rows, " ") }
end

-- Sims and previews: the moving models' kept pictures against drawing every model afresh, at one moment: two whole
-- composes (the effects left out), the first using the kept pictures that stand for a still model, the second drawing
-- everything; off: the pixels (colour or id) that differ, hits: the kept pictures the first used.
function PixelRenderer.debugKeepCheck(): { off: number, hits: number, checked: number }
	local s = surf
	if s == nil or baking then
		return { off = -1, hits = 0, checked = 0 }
	end
	local n = s.W * s.H
	SG.quiet = true
	needFull = true
	local h0 = SG.hits
	compose(true)
	local hits = SG.hits - h0
	local a, ai = buffer.create(n * 4), buffer.create(n * 2)
	buffer.copy(a, 0, s.frame.color, 0, n * 4)
	buffer.copy(ai, 0, s.frame.id, 0, n * 2)
	SG.off = true
	needFull = true
	compose(true)
	SG.off, SG.quiet = false, false
	local off = 0
	for i = 0, n - 1 do
		if buffer.readu32(a, i * 4) ~= buffer.readu32(s.frame.color, i * 4) or buffer.readu16(ai, i * 2) ~= buffer.readu16(s.frame.id, i * 2) then
			off += 1
		end
	end
	needFull = true
	return { off = off, hits = hits, checked = n }
end

-- Sims and previews: the incremental compose against a whole compose at the same moment. Arms the check for the next
-- incremental compose (drawn without the tick's budget, then composed whole at once, the frames before the effects
-- compared) and returns the last one's result: off, the pixels (colour or id) that differ (-1: none ran yet); ties,
-- those where two models meet within the depth bias (the one put down first keeps them); px, the art px it redid.
function PixelRenderer.debugIncCheck(): { off: number, checked: number, px: number }
	SG.incArm = true
	return SG.incResult
end

-- Sims and previews: the clock the frame's budgets and timings read (nil: os.clock again).
function PixelRenderer.debugClock(fn: (() -> number)?)
	SG.clock = fn or os.clock
end

-- Whether the island composes incrementally now (SG.live).
function PixelRenderer.debugInc(): boolean
	local s = surf
	return s ~= nil and SG.live(s)
end

function PixelRenderer.debugDim(): number
	return dim
end

-- Sims and previews: the grade now ("" by day).
function PixelRenderer.debugGrade(): string
	return gradeKey
end

-- CLI checks only: the layer, its bake and what the ticks cost.
-- Previews: the blob shadows on the frame now, pixel by pixel in each one's ellipse: `high` static pixels of a surface
-- more than 0.9 studs over the model's ground (a roof, an awning, a wall), `darkened` of those the shadow darkened
-- (the report of 2026-11-18, "also, shadows clip through buildings": none since), `ground` the ground pixels it did.
function PixelRenderer.debugShadowCheck(): { high: number, darkened: number, ground: number, shadows: number }
	local out = { high = 0, darkened = 0, ground = 0, shadows = 0 }
	local s = surf
	if s == nil then
		return out
	end
	local f, W, H, cam = s.frame, s.W, s.H, s.cam
	for model, d in dyns do
		local gcx, gcy, rx, ry = d.sx, d.sy, d.srx, d.sry
		if gcx and gcy and rx and ry then
			out.shadows += 1
			local g = model:GetAttribute("PixelGroundY")
			local top = (if type(g) == "number" then g else 0) + 0.9
			local cx, cy = gcx - cam.gx, gcy - cam.gy
			for y = math.max(0, math.floor(cy - ry)), math.min(H - 1, math.ceil(cy + ry)) do
				local dy = (y + 0.5 - cy) / ry
				if math.abs(dy) < 1 then
					local half = rx * math.sqrt(1 - dy * dy)
					local oy0 = cam.goy + cam.gx * cam.iy + (y + cam.gy) * cam.jy
					for x = math.max(0, math.floor(cx - half + 0.5)), math.min(W - 1, math.floor(cx + half + 0.5) - 1) do
						local idx = y * W + x
						local id = buffer.readu16(f.id, idx * 2)
						if id ~= 0 and id < DYN_ID0 then
							local c = buffer.readu32(f.color, idx * 4)
							local dark = c ~= buffer.readu32(s.sColor, idx * 4) and c == shadeShadowed(s, idx, x, y)
							if oy0 + x * cam.iy + cam.ly * buffer.readf32(s.sDepth, idx * 4) > top then
								out.high += 1
								out.darkened += if dark then 1 else 0
							elseif dark then
								out.ground += 1
							end
						end
					end
				end
			end
		end
	end
	return out
end

-- Previews: where moving model `model`'s picture went down in the last compose (the top left in layer px), or nil.
function PixelRenderer.debugShown(model: Model): (number?, number?)
	local d, s = dyns[model], surf
	local r = if d then d.shR else nil
	if r == nil or s == nil then
		return nil, nil
	end
	return r.x0 + 1 - s.cam.gx, r.y0 + 1 - s.cam.gy
end

function PixelRenderer.debugStatic(): { W: number, H: number, K: number, baking: boolean, behind: boolean, shown: boolean, color: buffer?, rays: number, bakes: number, ticks: number, composeMs: number, dyn: number, px: number, py: number, ox: number, oy: number, scrolls: number, scrollRays: number, recasts: number, queued: number }
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
		behind = back ~= nil,
		shown = shown,
		color = if s then s.frame.color else nil,
		rays = bakeRays,
		bakes = stats.bakes,
		ticks = stats.ticks,
		composeMs = stats.composeMs,
		dyn = n,
		-- (the pan the screen shows: the layer's top-left plus the window's place in it)
		px = if s then s.cam.gx + s.ox else 0,
		py = if s then s.cam.gy + s.oy else 0,
		ox = if s then s.ox else 0,
		oy = if s then s.oy else 0,
		scrolls = stats.scrolls,
		scrollRays = stats.scrollRays,
		recasts = stats.recasts,
		queued = #invQueue + (if invCur then 1 else 0),
	}
end

-- Sims and previews: the static picture's buffers (its colour as shown, its depth, its ids; nil before a bake) and
-- the ids the parts under `root` got, each with its part, and Shading.isInk (whether a pixel is an outline's).
function PixelRenderer.debugStaticIds(root: Instance?): (Raster.Frame?, { [number]: BasePart }, (number) -> boolean)
	local out: { [number]: BasePart } = {}
	if root then
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and staticIds[d] then
				out[staticIds[d]] = d
			end
		end
	else
		for d, id in staticIds do
			out[id] = d :: BasePart
		end
	end
	local s = surf
	return if s then s.static else nil, out, Shading.isInk
end

-- (Palette is read so the LUT carries the office themes' colours.)
Shading.setPalette(Shading.defaultColors())
Shading.setMode("day")
local _ = Palette

return PixelRenderer
