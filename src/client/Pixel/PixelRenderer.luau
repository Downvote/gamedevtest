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
-- the water's frames a second (4 since the request of 2026-11-23, "optimize the game much much more"; 6 before: each
-- frame sends the water's changed pixels up; 2 since the next, "optimize it even further. you can cut down even more
-- on graphics")
local WATER_HZ = 2
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
type DynCache = { gx: number, gy: number, w: number, h: number, n: number, px: buffer, cfs: { CFrame }?, szs: { Vector3 }?, gone: { boolean }?, ver: number, ppu: number, shp: Vector3?, anchor: Vector3?, from: DynCache? }
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
	updAt: number?, -- (the tick it last moved on: SG.budgetPlan)
	sameSeq: number?, -- (the tick it was last looked at for a change: SG.blitOk)
	drawMs: number?, -- (ms its draws took lately, and since when it has waited for one: SG.plan)
	wantAt: number?,
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
	-- (PixelRenderer.pose's group: models posed alike share their pictures by pose, SG.groupPoses)
	poseGroup: string?,
	-- (its "PixelFocus" attribute: what the view is about, the hatch scene's egg and its lights: moved and drawn every
	-- tick at once, as a founder is, never left for a later tick or drawn over a few frames)
	focus: boolean?,
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
	perf = { frames = 0, panFrames = 0, invMs = 0, invFinMs = 0, pokeMs = 0, pokes = 0, preMs = 0, aheadMs = 0, scrollMs = 0, composeMs = 0, uploadMs = 0, gradeMs = 0, stepMs = 0, uploads = 0, regrades = 0, castMs = 0, inkMs = 0, dynMs = 0, outlineMs = 0, rimMs = 0, fxMs = 0, waterMs = 0, windMs = 0, copyMs = 0, maxMs = 0, slow = 0, incFrames = 0, incPx = 0, fullFrames = 0 },
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
-- (how many pixels are stuck on each layer row, u16 a row: restoreRect passes over the rows with none; the request of
-- 2026-11-23, "optimize the game much much more": the lawn's tufts keep some stuck nearly always, and every pixel put
-- back looked for one)
local stickRows: buffer? = nil

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
	local sr = stickRows
	if sr then
		buffer.fill(sr, 0, 0)
	end
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

-- whether any tier casts sun shadows: none since 2026-11-23 ("try removing more graphics"), so the sun's map (SG.SunMap)
-- is neither watched nor built
local SUN_ANY = false
for _, spec in Tuning.PixelTiers do
	if spec.shadows then
		SUN_ANY = true
	end
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
	-- (which parts can meet the rays where, Pixel/RayMap: pixels it answers need no ray; SG.castPx. noShare: every
	-- pixel cast, for debugCastCheck's fresh picture; the pixels written as sky and as shared since debugShare)
	Map = require(script.Parent.RayMap).new(0.1, 0.5),
	-- (the same seen from the sun: a sun ray's hit, or that it meets nothing, worked out without the ray: SG.sunAt)
	SunMap = require(script.Parent.RayMap).new(0.6, 0.6),
	sunView = nil :: CameraController.View?,
	sunRot = nil :: { number }?,
	sunL0 = 0,
	sunN = 0,
	mapView = nil :: CameraController.View?,
	noShare = false,
	planes = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: { [number]: { number } | false } }, -- (SG.facePlane's)
	geom = (setmetatable({}, { __mode = "k" }) :: any) :: { [BasePart]: { number } }, -- (SG.geomOf's)
	probe = nil :: { cert: number, agree: number, off: number, tried: number, ex: { string } }?,
	lastHit = nil :: BasePart?,
	-- (the hit SG.solve worked out without a ray, for castSample)
	aPart = nil :: BasePart?,
	aDepth = 0,
	aNx = 0,
	aNy = 0,
	aNz = 0,
	solvedN = 0,
	skyN = 0,
	aheadSkyMask = nil :: buffer?, -- (the cast ahead's runs of sky on its small layer, SG.aheadPiece: 1 where filled)
	sharedN = 0,
	raysAt = 0,
	frameLog = nil :: { over: number, list: { string } }?, -- (previews: the slow frames' breakdowns, debugFrameLog)
	exclVer = 0, -- (refreshExclude's count: the pre-cast's filter follows it)
	panAt = -1, -- SG.clock() of the view's last pan (SG.keep keeps a moving model's picture while one goes on)
	need = {} :: { Dyn }, -- (a compose's models to draw afresh, in their order)
	unfin = nil :: { Rect }?, -- (the last scroll's strips, their shadow edges, ink and grade still to do: SG.finishStrips)
	unfinAt = 0, -- (the frame they came in on)
	-- (strips shown before they were whole, the rest of their pixels still to cast: SG.release, SG.refineStep)
	refine = {} :: { { r: Rect, x: number, y: number, pass: number } },
	fin = nil :: { list: { Rect }, phase: number, i: number, y: number? }?, -- (SG.finishStep's place)
	finCoarse = false, -- (the strips being finished were shown from their anchors' blocks: SG.release)
	vpBlocked = false,
	vpLag = 0, -- (art px the window was behind the camera this frame: SG.pendStep's coarser pass past PixelHoldMaxPx)
	-- (the pieces of the last scroll's strips still to cast, a few a frame: SG.pendStep; nil: none)
	pend = nil :: { pieces: { Rect }, phase: number, i: number, x: number, y: number, started: boolean, c4: boolean? }?,
	-- (the frame's deadlines: frameEnd, the renderer's whole frame; castEnd, the casting that can wait, leaving the
	-- compose its time: frameStep)
	frameEnd = 0,
	castEnd = 0,
	estTick = 6, -- (ms a tick's compose and the rest of its frame took lately, and a lite frame's: the cast's share is what is left)
	estLite = 3,
	castSpent = 0, -- (ms this frame spent on the casting that can wait)
	usPerPx = 1, -- (µs a pixel a tick's compose took lately to redo: SG.budgetPlan's budget in pixels)
	updSeq = 0, -- (the ticks composed: a model's updAt is the one it last moved on)
	drawAvg = 6, -- (ms a model's draw took lately: SG.plan's estimate for a model not drawn yet)
	drawByName = {} :: { [string]: number }, -- (and a model of the same name's: a driftling of the same kind)
	needMid = {} :: { [any]: number },
	groupPoses = {} :: { [string]: { pics: { [string]: any }, order: { string } } }, -- (PixelRenderer.pose's groups) -- (SG.plan: how far from the screen's middle each model with no picture stands)
	firstPerPart = Tuning.PixelFirstPartMs, -- (ms a part a model's first draw takes, of a kind never drawn: SG.plan)
	sameEvery = 1, -- (ticks between two looks at whether a model not posed has changed: SG.blitOk, more in a crowd)
	sameT = 0, -- (s this tick's looks took)
	job = nil :: any, -- (the model being drawn over a few frames, SG.jobStart; its scratch frame, and what drawModel sets up for it)
	jobIso = nil :: Raster.Frame?,
	jobMode = false,
	jobBlend = nil :: any,
	jobDone = false,
	heavyDraws = {} :: { [string]: { n: number, ms: number, parts: number, px: number, blend: number? } }, -- (previews: debugFrameLog)
	blendMs = 0, -- (previews: the last draw's blended body)
	-- (the window's pan this frame, held off what is not cast yet: SG.viewPan; the camera's own pan the frame before)
	vpX = 0,
	vpY = 0,
	vpAt = -1,
	vpFX = nil :: number?, -- (the window's place with its fraction, and its speed in art px a second: SG.windowAxis)
	vpFY = nil :: number?,
	vpVX = 0,
	vpVY = 0,
	waterSeen = 0, -- (water pixels the water's slices met this period; none: SG.waterRest)
	waterRows = nil :: buffer?, -- (a byte a layer row: 1 once a slice met no water in it; good while staticVer is waterRowsVer)
	waterRowsVer = -1,
	waterRest = 0, -- (os.clock() till which the water's slices rest: the last period met no water on the layer)
	vpCX = 0, -- (the camera's speed last frame, art px a second)
	vpCY = 0,
	dt = 1 / 60, -- (this frame's length, seconds: frameStep)
	pendCalls = 0, -- (pixels SG.pendStep cast this frame, and per frame lately while it had work: SG.pendLeft's pace)
	pendRate = 300,
	vpRawX = nil :: number?,
	vpRawY = nil :: number?,
	vpView = nil :: CameraController.View?,
	vpJump = false, -- (this frame's window jumped: SG.viewPan; the scroll re-bakes at it even with strips pending)
	isleOff = false, -- (previews: the whole island's cast held off, PixelRenderer.debugIsleOff)
	budgetScale = 1, -- (previews: the frame's own share scaled, a slower machine's: PixelRenderer.debugBudget)
	castSlowUs = 0, -- (previews: microseconds added to every pixel cast, a slower machine's: PixelRenderer.debugCastSlow)
	frameNo = 0, -- (frames stepped)
	tickNow = false, -- (this frame composes a tick: frameStep)
	tickRun = false, -- (and so did the frame before it)
	preSaved = -1, -- (the scroll count when the margin the view leaves was last kept: SG.preSave)
	ringTurn = false, -- (standing, the ring's frame or the pre-cast's: frameStep)
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
	markY0 = math.huge, -- (the rows of tiles marked since tilesClear: SG.runs looks at those alone)
	markY1 = -1,
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
-- The static shade of global pixel (gx, gy) from what it shows: its static id (0: the sky), albedo, normal index + 1,
-- sun visibility and the hit point (world). castSample hands its own values in; shadeAt reads them off the layer.
function SG.shadeOf(s: Surf, gx: number, gy: number, id: number, a: number, ni: number, lit: number, wx: number, wy: number, wz: number): number
	if id == 0 then
		-- (a stage with a see-through sky: nothing there, the picture behind the layer shows)
		return if s.view.clear then 0 else Shading.sky(gx, gy - s.skyRef, s.H)
	end
	if a >= EMISSIVE then
		return Shading.toonAt(a - EMISSIVE, 0, 1, 0, 2, gx, gy, Shading.INDOOR, 0)
	end
	-- indoors: the hit point inside the office's room box
	local r = s.view.room
	local place = if wx >= r.x0 and wx <= r.x1 and wz >= r.z0 and wz <= r.z1 and wy <= r.y1 then Shading.INDOOR else Shading.OUTDOOR
	-- the surface's texture (not where glass in front tints it: NO_TEX's colour matches none)
	local lift, soft = 0, 1
	local t = texs[id]
	if t and t.rgb == a then
		lift = texLift(s, t, ni, lit, gx, gy)
		soft = TEX_SOFT[t.kind] or 1 -- (a mark a gentle tone, not a whole band: Shading.TEX_SOFT)
	end
	return Shading.toonAt(a, NX[ni], NY[ni], NZ[ni], lit, gx, gy, place, lift, soft)
end

local function shadeAt(s: Surf, idx: number, x: number, y: number): number
	local cam = s.cam
	local gx, gy = x + cam.gx, y + cam.gy
	local id = buffer.readu16(s.sId, idx * 2)
	if id == 0 then
		return SG.shadeOf(s, gx, gy, 0, 0, 0, 0, 0, 0, 0)
	end
	local depth = buffer.readf32(s.sDepth, idx * 4)
	local ox, oy, oz = Raster.origin(cam, x, y)
	return SG.shadeOf(s, gx, gy, id, buffer.readu32(s.sAlbedo, idx * 4), buffer.readu8(s.sNormal, idx) + 1, buffer.readu8(s.sLit, idx), ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth)
end

-- One bake sample at global (gx, gy), filling the block up to (bx1, by1) (global, inclusive) on the layer.
-- The sea's wave phase at a world point (wavy lines across the world, about 10 studs apart): the bake's.
local function waterPhase(wx: number, wz: number): number
	local v = wx * 0.6 + wz * 0.35 + 1.6 * math.sin(wz * 0.23 + wx * 0.05) + 1.1 * math.sin(wx * 0.17)
	return math.floor(v * 9.14) % 256
end

local function castSample(s: Surf, gx: number, gy: number, bx1: number, by1: number, own: boolean, shadows: boolean, given: boolean?)
	local cam = s.cam
	local x, y = gx - cam.gx, gy - cam.gy
	-- (Raster.origin and BakeCast.shadowMode, written out: this runs for every pixel cast)
	local ox, oy, oz = cam.gox + gx * cam.ix + gy * cam.jx, cam.goy + gx * cam.iy + gy * cam.jy, cam.goz + gx * cam.iz + gy * cam.jz
	local mode = if not shadows then BakeCast.SHADOW_OFF elseif own or (gx % 2 == 0 and gy % 2 == 0) then BakeCast.SHADOW_TEST else BakeCast.SHADOW_DEFER
	local part: BasePart?, depth: number, ni: number, lit: number, rays: number, tint: BasePart?, face: boolean
	if given then
		-- (the hit worked out without a ray: SG.solve; its sun as BakeCast.cast tests it)
		part, depth, tint, rays, lit, face = SG.aPart, SG.aDepth, nil, 0, 1, false
		local nx, ny, nz = SG.aNx, SG.aNy, SG.aNz
		ni = Shading.normalIndex(nx, ny, nz)
		if mode ~= BakeCast.SHADOW_OFF and nx * SUN_V.X + ny * SUN_V.Y + nz * SUN_V.Z > 0 then
			face = true
			if mode == BakeCast.SHADOW_TEST then
				local hx, hy, hz = ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth
				local l = SG.sunAt(part :: BasePart, hx, hy, hz, nx, ny, nz)
				if l then
					lit = l
				else
					rays = 1
					lit = BakeCast.sunVisible(params, Vector3.new(hx, hy, hz), Vector3.new(nx, ny, nz), SUN_V)
				end
			else
				lit = BakeCast.LIT_UNKNOWN
			end
		end
	else
		-- (the sun tested here, the sun's map first: SG.sunAt; its ray as BakeCast's own when the map cannot say)
		local test = mode == BakeCast.SHADOW_TEST and SG.sunRot ~= nil and not SG.noShare
		part, depth, ni, lit, rays, tint, face = BakeCast.cast(params, Vector3.new(ox, oy, oz), s.look, FAR, if test then BakeCast.SHADOW_DEFER else mode, SUN_V)
		if test and face and lit == BakeCast.LIT_UNKNOWN and part then
			-- (from the hit's own position, as BakeCast's ray starts: a point on a shadow's edge is told the same way)
			local n = BakeCast.lastN
			local hp = (BakeCast.lastRes :: RaycastResult).Position
			local l = SG.sunAt(part, hp.X, hp.Y, hp.Z, n.X, n.Y, n.Z)
			if l then
				lit = l
			else
				lit = BakeCast.sunVisible(params, hp, n, SUN_V)
				rays += 1
			end
		end
	end
	bakeRays += rays
	if SG.probe then
		SG.lastHit = part
	end
	-- (the hit point)
	local wx, wy, wz = ox + cam.lx * depth, oy + cam.ly * depth, oz + cam.lz * depth
	if part ~= nil then
		-- (a part of a model lit smooth, the Tree of Life: the normal blended across its balls, in a fine direction;
		-- Render/Smooth)
		local k0 = ni + 1
		local snx, sny, snz = SmoothParts.staticNormal(part, wx, wy, wz, NX[k0], NY[k0], NZ[k0])
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
				local l = SG.sunAt(part, wx, wy, wz, NX[k], NY[k], NZ[k])
				if l then
					lit = l
				else
					lit = BakeCast.sunVisible(params, Vector3.new(wx, wy, wz), Vector3.new(NX[k], NY[k], NZ[k]), SUN_V)
					bakeRays += 1
				end
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
		if wcls == 4 then
			-- leaves: gusts sweeping slowly across the islands (a canopy moves as one)
			wph = math.floor((wx * 0.22 + wz * 0.16) * 4) % 256
		elseif wcls == 5 then
			-- flags: a quick wave along their length
			wph = math.floor((wx * 1.6 + wz * 1.1) * 4) % 256
		elseif wcls == 6 then
			-- falling water: by height (the streaks run down it), each thin column of it a little apart from the next
			wph = (math.floor(wy * 6) + math.floor((wx + wz) * 3) * 5) % 256
		else
			wph = waterPhase(wx, wz)
		end
	end
	buffer.writeu8(s.sWClass, idx, wcls)
	buffer.writeu8(s.sWave, idx, wph)
	-- (1: the sun copied from the anchor; 2: a face toward the sun with a ray of its own, which a pixel sharing this
	-- anchor's face takes its sun from: SG.shareAt)
	buffer.writeu8(s.sShare, idx, if shared then 1 elseif face then 2 else 0)
	buffer.writeu16(s.sId, idx * 2, id)
	buffer.writef32(s.sDepth, idx * 4, depth)
	buffer.writeu32(s.sAlbedo, idx * 4, albedo)
	buffer.writeu8(s.sNormal, idx, ni)
	buffer.writeu8(s.sLit, idx, lit)
	local c = SG.shadeOf(s, gx, gy, id, albedo, ni + 1, lit, wx, wy, wz)
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

-- Layer row y, pixels x0 .. x1, as the see-through sky (a view whose sky is clear: its shade 0), all at once: what
-- SG.skyAt writes pixel by pixel, in a few fills a field (the request of 2026-11-23, "a deeper rework of the renderer":
-- the cast ahead of a walk spent a quarter of its time writing sky one pixel at a time). Each pixel counts as its own.
local farRow: buffer? = nil
function SG.skyRow(s: Surf, y: number, x0: number, x1: number)
	local n = x1 - x0 + 1
	if n <= 0 then
		return
	end
	local fr = farRow
	if fr == nil or buffer.len(fr) < n * 4 then
		local m = math.max(n, 256)
		local b = buffer.create(m * 4)
		for i = 0, m - 1 do
			buffer.writef32(b, i * 4, FAR)
		end
		fr = b
		farRow = b
	end
	local b0 = y * s.W + x0
	buffer.fill(s.sShare, b0, 0, n)
	buffer.fill(s.sWClass, b0, 0, n)
	buffer.fill(s.sWave, b0, 0, n)
	buffer.fill(s.sId, b0 * 2, 0, n * 2)
	buffer.copy(s.sDepth, b0 * 4, fr :: buffer, 0, n * 4)
	buffer.fill(s.sAlbedo, b0 * 4, 0, n * 4)
	buffer.fill(s.sNormal, b0, BakeCast.SKY_NORMAL, n)
	buffer.fill(s.sLit, b0, 1, n)
	buffer.fill(s.sShade, b0 * 4, 0, n * 4)
	SG.skyN += n
end

-- Global pixel (gx, gy) as the sky, filling its block up to (bx1, by1) as castSample would after a ray that met
-- nothing: for a pixel no part can reach (Pixel/RayMap), no ray needed.
function SG.skyAt(s: Surf, gx: number, gy: number, bx1: number, by1: number)
	local cam = s.cam
	local W = s.W
	local x, y = gx - cam.gx, gy - cam.gy
	local c = SG.shadeOf(s, gx, gy, 0, 0, 0, 0, 0, 0, 0)
	local x1, y1 = math.min(bx1 - cam.gx, W - 1), math.min(by1 - cam.gy, s.H - 1)
	local idx = y * W + x
	for by = y, y1 do
		local row = by * W
		for bx = x, x1 do
			local b = row + bx
			buffer.writeu8(s.sShare, b, if b == idx then 0 else 1)
			buffer.writeu8(s.sWClass, b, 0)
			buffer.writeu8(s.sWave, b, 0)
			buffer.writeu16(s.sId, b * 2, 0)
			buffer.writef32(s.sDepth, b * 4, FAR)
			buffer.writeu32(s.sAlbedo, b * 4, 0)
			buffer.writeu8(s.sNormal, b, BakeCast.SKY_NORMAL)
			buffer.writeu8(s.sLit, b, 1)
			buffer.writeu32(s.sShade, b * 4, c)
		end
	end
	SG.skyN += 1
end

-- The plane of flat part p's face that shows normal index ni (front on to the view along (lx, ly, lz)): { nx, ny, nz,
-- d } with n . point = d on it, worked out from the part's frame and size once and kept; false when no face of it
-- fits. A block's six faces; a wedge's too, and its slope either way round (the one that is not the slope's is never
-- met: the anchors' depths settle it, SG.shareAt).
function SG.facePlane(p: BasePart, ni: number, lx: number, ly: number, lz: number): { number } | false
	local byNi = SG.planes[p]
	if byNi == nil then
		byNi = {}
		SG.planes[p] = byNi
	end
	local got = byNi[ni]
	if got ~= nil then
		return got :: any
	end
	local cx, cy, cz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local size = p.Size
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local cands = {
		{ r00, r10, r20, hx },
		{ -r00, -r10, -r20, hx },
		{ r01, r11, r21, hy },
		{ -r01, -r11, -r21, hy },
		{ r02, r12, r22, hz },
		{ -r02, -r12, -r22, hz },
	}
	if p:IsA("WedgePart") then
		-- (the slope, through the box's middle, its normal (0, sz, -+sy) in the part's own axes)
		for _, sg in { -1, 1 } do
			local a, b = size.Z, sg * size.Y
			local len = math.sqrt(a * a + b * b)
			if len > 0 then
				a, b = a / len, b / len
				table.insert(cands, { r01 * a + r02 * b, r11 * a + r12 * b, r21 * a + r22 * b, 0 })
			end
		end
	end
	local best: { number } | false = false
	local k = ni + 1
	local bestDot = -2
	for _, c in cands do
		local nx, ny, nz = c[1], c[2], c[3]
		if nx * lx + ny * ly + nz * lz < 0 and Shading.normalIndex(nx, ny, nz) == ni then
			local dot = nx * NX[k] + ny * NY[k] + nz * NZ[k]
			if dot > bestDot then
				bestDot = dot
				best = { nx, ny, nz, nx * cx + ny * cy + nz * cz + c[4] }
			end
		end
	end
	byNi[ni] = best :: any
	return best :: any
end

-- Whether the ray from (ox, oy, oz) along (lx, ly, lz) meets part p's box (grown by 0.01 studs) before the depth
-- tmax (and a hair past it: a face level with the one at tmax counts as in front). The part is inside its box
-- whatever its shape, so a miss is a miss of the part.
function SG.boxHit(p: BasePart, ox: number, oy: number, oz: number, lx: number, ly: number, lz: number, tmax: number): boolean
	local cx, cy, cz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local size = p.Size
	local dx, dy, dz = ox - cx, oy - cy, oz - cz
	local t0, t1 = -math.huge, math.huge
	for axis = 1, 3 do
		local ax, ay, az, h
		if axis == 1 then
			ax, ay, az, h = r00, r10, r20, size.X / 2
		elseif axis == 2 then
			ax, ay, az, h = r01, r11, r21, size.Y / 2
		else
			ax, ay, az, h = r02, r12, r22, size.Z / 2
		end
		h += 0.01
		local o = dx * ax + dy * ay + dz * az
		local d = lx * ax + ly * ay + lz * az
		if math.abs(d) < 1e-9 then
			if o < -h or o > h then
				return false
			end
		else
			local ta, tb = (-h - o) / d, (h - o) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			t0, t1 = math.max(t0, ta), math.min(t1, tb)
			if t0 > t1 then
				return false
			end
		end
	end
	return t1 >= 0 and t0 < tmax + 0.02
end

-- Global pixel (gx, gy), not a 2x2 anchor, from the anchors either side of it (left and right, above and below) or
-- round it (both odd), with no ray, when the anchors, all inside the layer rect being cast (rx0 .. rx1, ry0 .. ry1,
-- layer px), met the same flat face of one of the block's two nearest parts (Pixel/RayMap: p1, p2, how near p2 and the
-- third come, whether p1 and p2 are flat), and nothing else can be in front of that face at the pixel: the third part
-- on comes no nearer, and the other of the two comes no nearer or the pixel's ray misses its box. The pixel's ray
-- would cross the face between the anchors, at the depth between theirs, and meet nothing before it (the request of
-- 2026-11-21, "Cast fewer main rays"). Its sun is its block's anchor's, as castSample shares it. Writes the pixel as
-- castSample would and returns true; false when it needs its ray.
function SG.shareAt(s: Surf, gx: number, gy: number, p1: BasePart, p2: BasePart?, near2: number, near3: number, flat1: boolean, flat2: boolean, shadows: boolean, rx0: number, ry0: number, rx1: number, ry1: number): boolean
	-- (the cheap tests first: the part's own properties are read last, each read goes into the engine)
	local cam = s.cam
	local W = s.W
	local x, y = gx - cam.gx, gy - cam.gy
	local ax0, ay0 = x - gx % 2, y - gy % 2
	local ax1, ay1 = x + gx % 2, y + gy % 2
	if ax0 < rx0 or ay0 < ry0 or ax1 > rx1 or ay1 > ry1 then
		return false
	end
	local sId, sNormal, sDepth = s.sId, s.sNormal, s.sDepth
	local a0 = ay0 * W + ax0 -- (the block's anchor)
	local id = buffer.readu16(sId, a0 * 2)
	-- the face the anchors met: of the block's nearest part, or of the next (the nearest then the one to test)
	local part: BasePart, other: BasePart?
	if id == 0 then
		return false
	elseif staticIds[p1] == id then
		if not flat1 then
			return false
		end
		part, other = p1, p2
	elseif p2 and staticIds[p2] == id then
		if not flat2 then
			return false
		end
		part, other = p2, p1
		near2 = 0 -- (the nearest may come in front: its box is tested below)
	else
		return false
	end
	local ni = buffer.readu8(sNormal, a0)
	local a1 = ay0 * W + ax1
	local a2 = ay1 * W + ax0
	local a3 = ay1 * W + ax1
	if buffer.readu16(sId, a1 * 2) ~= id or buffer.readu8(sNormal, a1) ~= ni then
		return false
	end
	local d0, d1 = buffer.readf32(sDepth, a0 * 4), buffer.readf32(sDepth, a1 * 4)
	local depth: number
	if a2 == a0 then
		depth = (d0 + d1) / 2
	else
		if buffer.readu16(sId, a2 * 2) ~= id or buffer.readu8(sNormal, a2) ~= ni then
			return false
		end
		local d2 = buffer.readf32(sDepth, a2 * 4)
		if a3 == a2 then
			depth = (d0 + d2) / 2
		else
			if buffer.readu16(sId, a3 * 2) ~= id or buffer.readu8(sNormal, a3) ~= ni then
				return false
			end
			local d3 = buffer.readf32(sDepth, a3 * 4)
			if math.abs(d0 + d3 - d1 - d2) > 1e-3 then
				return false
			end
			depth = (d0 + d1 + d2 + d3) / 4
		end
	end
	-- the depth where the pixel's ray crosses the face's plane, worked out from the part itself (the anchors' depths are
	-- kept to single precision: their mean could stray a hair from a ray's own, enough to tip a sun ray at a shadow's
	-- edge one way or the other), so long as the plane puts the anchors where they are
	local ox, oy, oz = Raster.origin(cam, x, y)
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local found = SG.facePlane(part, ni, lx, ly, lz)
	if not found then
		return false
	end
	local pl = found :: { number }
	local nx, ny, nz, pd = pl[1], pl[2], pl[3], pl[4]
	local nl = nx * lx + ny * ly + nz * lz
	local exact = (pd - (nx * ox + ny * oy + nz * oz)) / nl
	-- (an anchor one pixel over: its origin a pixel's step along the grid)
	local stepX, stepY = (nx * cam.ix + ny * cam.iy + nz * cam.iz) / nl, (nx * cam.jx + ny * cam.jy + nz * cam.jz) / nl
	local ex0 = exact + (gx % 2) * stepX + (gy % 2) * stepY
	if math.abs(ex0 - d0) > 2e-3 or math.abs(ex0 - (gx % 2) * 2 * stepX - d1) > 2e-3 then
		return false
	end
	if math.abs(exact - depth) > 2e-3 then
		return false
	end
	depth = exact
	-- nothing else of the block in front of the face here: the third part on comes no nearer than the face, and the
	-- other of the two either does not or its box is not on the pixel's ray before the face
	if near2 <= depth then
		if near3 <= depth or other == nil then
			return false
		end
		if SG.boxHit(other :: BasePart, ox, oy, oz, lx, ly, lz, depth) then
			return false
		end
	end
	if (waters[id] or 0) ~= 0 then
		return false -- (the water's phase comes from the hit point: left to its ray, to the last bit)
	end
	if part.Transparency >= BakeCast.CLEAR_MIN then
		return false -- (a see-through face: what its ray meets behind it is not on the map)
	end
	local albedo = albedos[id]
	local lit, shared = 1, false
	if albedo >= EMISSIVE then
		lit = 2
	elseif shadows and buffer.readu8(s.sShare, a0) == 2 then
		-- (the face looks at the sun: the anchor's sun, as castSample copies it)
		local alit = buffer.readu8(s.sLit, a0)
		if alit > 1 then
			return false
		end
		lit, shared = alit, true
	end
	if texs[id] == nil then
		texs[id] = texInfoOf(s, part, albedo, 0)
	end
	local idx = y * W + x
	buffer.writeu8(s.sWClass, idx, 0)
	buffer.writeu8(s.sWave, idx, 0)
	buffer.writeu8(s.sShare, idx, if shared then 1 else 0)
	buffer.writeu16(sId, idx * 2, id)
	buffer.writef32(sDepth, idx * 4, depth)
	buffer.writeu32(s.sAlbedo, idx * 4, albedo)
	buffer.writeu8(sNormal, idx, ni)
	buffer.writeu8(s.sLit, idx, lit)
	buffer.writeu32(s.sShade, idx * 4, SG.shadeOf(s, gx, gy, id, albedo, ni + 1, lit, ox + lx * depth, oy + ly * depth, oz + lz * depth))
	SG.sharedN += 1
	return true
end

-- A part as the pixel rays meet it, worked out once: { centre, its axes (the CFrame's columns), half sizes, kind, met }
-- with kind 1 a block, 2 a ball, 3 a cylinder (along its X axis), 4 a wedge (its slope facing front and up), 0 a shape
-- not worked out here (only its box is known); met 0 for a part no pixel ray meets (CanQuery and CanCollide off), 1
-- for one in the rays' collision group, 2 for one in another group (whether the rays meet it is not known here); then
-- its Transparency. A static part does not move (Pixel/RayMap); one hidden is forgotten (PixelRenderer.hideStatic).
function SG.geomOf(p: BasePart): { number }
	local got = SG.geom[p]
	if got ~= nil then
		return got :: any
	end
	local cg = p.CollisionGroup
	local kind = 0
	if p:IsA("Part") then
		local sh = (p :: Part).Shape
		kind = if sh == Enum.PartType.Block then 1 elseif sh == Enum.PartType.Ball then 2 elseif sh == Enum.PartType.Cylinder then 3 elseif sh == Enum.PartType.Wedge then 4 else 0
	elseif p:IsA("WedgePart") then
		kind = 4
	end
	local met = if not (p.CanQuery or p.CanCollide) then 0 elseif cg == "Default" or cg == nil or cg == "" then 1 else 2
	local cx, cy, cz, r00, r01, r02, r10, r11, r12, r20, r21, r22 = p.CFrame:GetComponents()
	local size = p.Size
	local out = { cx, cy, cz, r00, r10, r20, r01, r11, r21, r02, r12, r22, size.X / 2, size.Y / 2, size.Z / 2, kind, met, p.Transparency }
	SG.geom[p] = out :: any
	return out
end

-- Whether the ray from (ox, oy, oz) along (lx, ly, lz) meets box g (SG.geomOf, grown by 0.01 studs) before the depth
-- tmax and a hair past it, as SG.boxHit for a part.
function SG.boxHitG(g: { number }, ox: number, oy: number, oz: number, lx: number, ly: number, lz: number, tmax: number): boolean
	local dx, dy, dz = ox - g[1], oy - g[2], oz - g[3]
	local t0, t1 = -math.huge, math.huge
	for a = 0, 2 do
		local ax, ay, az, h = g[4 + a * 3], g[5 + a * 3], g[6 + a * 3], g[13 + a] + 0.01
		local o = dx * ax + dy * ay + dz * az
		local d = lx * ax + ly * ay + lz * az
		if math.abs(d) < 1e-9 then
			if o < -h or o > h then
				return false
			end
		else
			local ta, tb = (-h - o) / d, (h - o) / d
			if ta > tb then
				ta, tb = tb, ta
			end
			if ta > t0 then
				t0 = ta
			end
			if tb < t1 then
				t1 = tb
			end
			if t0 > t1 then
				return false
			end
		end
	end
	return t1 >= 0 and t0 < tmax + 0.02
end

-- Where the ray from (ox, oy, oz) along the unit (lx, ly, lz) enters part shape g (SG.geomOf): the depth and the outward
-- normal there. Returns nil and false when it misses, nil and true when it meets it so near an edge, a rim or a
-- silhouette that a ray's own rounding could tell otherwise (the ray decides those).
function SG.rayShape(g: { number }, ox: number, oy: number, oz: number, lx: number, ly: number, lz: number): (number?, boolean, number, number, number)
	local dx, dy, dz = ox - g[1], oy - g[2], oz - g[3]
	local kind = g[16]
	local EDGE = 1e-3 -- (studs)
	if kind == 2 then
		-- a ball as wide as the part's smallest side
		local r = math.min(g[13], g[14], g[15])
		local b = dx * lx + dy * ly + dz * lz
		local d2 = dx * dx + dy * dy + dz * dz - b * b -- (the square of how near the ray passes the centre)
		local pass = math.sqrt(math.max(0, d2))
		if math.abs(pass - r) < 0.01 then
			return nil, true, 0, 0, 0
		elseif pass > r then
			return nil, false, 0, 0, 0
		end
		local t = -b - math.sqrt(r * r - d2)
		if t < 0 then
			return nil, true, 0, 0, 0
		end
		local px, py, pz = dx + lx * t, dy + ly * t, dz + lz * t
		return t, false, px / r, py / r, pz / r
	end
	-- (the ray in the part's own axes)
	local ax, ay, az = g[4], g[5], g[6]
	local bx, by, bz = g[7], g[8], g[9]
	local cxv, cyv, czv = g[10], g[11], g[12]
	local o1, o2, o3 = dx * ax + dy * ay + dz * az, dx * bx + dy * by + dz * bz, dx * cxv + dy * cyv + dz * czv
	local l1, l2, l3 = lx * ax + ly * ay + lz * az, lx * bx + ly * by + lz * bz, lx * cxv + ly * cyv + lz * czv
	local h1, h2, h3 = g[13], g[14], g[15]
	if kind == 3 then
		-- a cylinder along X, as wide as the smaller of the other two sides
		local r = math.min(h2, h3)
		local best, n1, n2, n3 = math.huge, 0, 0, 0
		local A = l2 * l2 + l3 * l3
		if A > 1e-12 then
			local B = o2 * l2 + o3 * l3
			local C = o2 * o2 + o3 * o3 - r * r
			local pass = math.sqrt(math.max(0, C + r * r - B * B / A))
			if math.abs(pass - r) < 0.01 then
				return nil, true, 0, 0, 0
			end
			if pass < r then
				local t = (-B - math.sqrt(math.max(0, B * B - A * C))) / A
				local x = o1 + l1 * t
				if math.abs(math.abs(x) - h1) < 0.01 then
					return nil, true, 0, 0, 0
				end
				if math.abs(x) <= h1 and t >= 0 then
					best, n1, n2, n3 = t, 0, (o2 + l2 * t) / r, (o3 + l3 * t) / r
				end
			end
		end
		if math.abs(l1) > 1e-12 then
			local face = if l1 > 0 then -h1 else h1
			local t = (face - o1) / l1
			local y, z = o2 + l2 * t, o3 + l3 * t
			local rad = math.sqrt(y * y + z * z)
			if math.abs(rad - r) < 0.01 then
				return nil, true, 0, 0, 0
			end
			if rad <= r and t >= 0 and t < best then
				best, n1, n2, n3 = t, if l1 > 0 then -1 else 1, 0, 0
			end
		end
		if best == math.huge then
			return nil, false, 0, 0, 0
		end
		return best, false, n1 * ax + n2 * bx + n3 * cxv, n1 * ay + n2 * by + n3 * cyv, n1 * az + n2 * bz + n3 * czv
	end
	-- a block, or a wedge (the block cut by its slope): the faces the ray goes in through, the last of them its entry
	local t0, t1, second = -math.huge, math.huge, -math.huge
	local n1, n2, n3 = 0, 0, 0
	-- (X)
	if math.abs(l1) < 1e-12 then
		if o1 < -h1 or o1 > h1 then
			return nil, false, 0, 0, 0
		end
	else
		local enter, exit = (-h1 - o1) / l1, (h1 - o1) / l1
		local sg = -1
		if l1 < 0 then
			enter, exit, sg = exit, enter, 1
		end
		second, t0, t1 = t0, enter, exit
		n1 = sg
	end
	-- (Y)
	if math.abs(l2) < 1e-12 then
		if o2 < -h2 or o2 > h2 then
			return nil, false, 0, 0, 0
		end
	else
		local enter, exit = (-h2 - o2) / l2, (h2 - o2) / l2
		local sg = -1
		if l2 < 0 then
			enter, exit, sg = exit, enter, 1
		end
		if enter > t0 then
			second, t0 = t0, enter
			n1, n2, n3 = 0, sg, 0
		elseif enter > second then
			second = enter
		end
		if exit < t1 then
			t1 = exit
		end
	end
	-- (Z)
	if math.abs(l3) < 1e-12 then
		if o3 < -h3 or o3 > h3 then
			return nil, false, 0, 0, 0
		end
	else
		local enter, exit = (-h3 - o3) / l3, (h3 - o3) / l3
		local sg = -1
		if l3 < 0 then
			enter, exit, sg = exit, enter, 1
		end
		if enter > t0 then
			second, t0 = t0, enter
			n1, n2, n3 = 0, 0, sg
		elseif enter > second then
			second = enter
		end
		if exit < t1 then
			t1 = exit
		end
	end
	if kind == 4 then
		-- the slope through the bottom front edge and the top back edge, its normal (0, size Z, -size Y) made unit
		local len = math.sqrt(h3 * h3 + h2 * h2)
		local m2, m3 = h3 / len, -h2 / len
		local dist = m2 * (o2 + h2) + m3 * (o3 + h3)
		local den = m2 * l2 + m3 * l3
		if math.abs(den) < 1e-12 then
			if dist > 0 then
				return nil, false, 0, 0, 0
			end
		elseif den < 0 then
			local t = -dist / den
			if t > t0 then
				second, t0 = t0, t
				n1, n2, n3 = 0, m2, m3
			elseif t > second then
				second = t
			end
		else
			local t = -dist / den
			if t < t1 then
				t1 = t
			end
		end
	end
	if t0 > t1 + EDGE then
		return nil, false, 0, 0, 0
	end
	if t0 > t1 - EDGE or second > t0 - EDGE or t0 < 0 then
		return nil, true, 0, 0, 0
	end
	return t0, false, n1 * ax + n2 * bx + n3 * cxv, n1 * ay + n2 * by + n3 * cyv, n1 * az + n2 * bz + n3 * czv
end

-- The sun at a surface point (px, py, pz) of part `own`, its outward normal (nx, ny, nz) facing the sun, worked out
-- without the sun ray where the sun's map (SG.SunMap: Pixel/RayMap seen along the sun) is sure of it: the ray starts
-- 0.05 studs off the face, as BakeCast's does, and every point of it falls in one block of that map, which names the
-- two parts that come nearest the sun there and how near the third comes. The point's own part never shades its own
-- face (a convex shape: the ray leaves it). Of the others nearer the sun than the ray's start, one whose shape the ray
-- enters within its length shades it (0); none, with no third part nearer, leaves it lit (1); nil when the ray decides
-- (the map not ready, an edge, a shape not worked out, a third part that may be in the way). The request of
-- 2026-11-22, "optimize it to the max": the sun rays had become most of the rays left.
function SG.sunAt(own: BasePart, px: number, py: number, pz: number, nx: number, ny: number, nz: number): number?
	local R = SG.sunRot
	if R == nil or SG.noShare then
		return nil
	end
	local sx, sy, sz = px + nx * 0.05, py + ny * 0.05, pz + nz * 0.05
	local q = Tuning.PixelSunMapQ
	local u = (sx * R[4] + sy * R[7] + sz * R[10]) * q
	local v = -(sx * R[5] + sy * R[8] + sz * R[11]) * q
	local p1, p2, d2, d3, _, _, d1 = SG.SunMap.at(math.floor(u), math.floor(v))
	if p1 == nil then
		return nil
	elseif p1 == false then
		return SG.sunDone(1, px, py, pz, nx, ny, nz)
	end
	local dS = -(sx * R[6] + sy * R[9] + sz * R[12]) - SG.sunL0
	local LX, LY, LZ = SUN_V.X, SUN_V.Y, SUN_V.Z
	local far = BakeCast.SHADOW_RAY
	local geom = SG.geom
	for k = 1, 2 do
		local p: BasePart? = if k == 1 then p1 :: BasePart else p2
		local near = if k == 1 then d1 else d2
		if p and near < dS + 1e-3 then
			local g = geom[p] or SG.geomOf(p :: BasePart)
			if p == own then
				if g[16] == 0 or g[17] ~= 1 then
					return nil -- (a shape not worked out may not be convex)
				end
			elseif g[17] == 1 and g[16] ~= 0 then
				local t, edge = SG.rayShape(g, sx, sy, sz, LX, LY, LZ)
				if edge then
					return nil
				elseif t then
					if t < far - 0.01 then
						return SG.sunDone(0, px, py, pz, nx, ny, nz)
					elseif t < far + 0.01 then
						return nil
					end
				end
			elseif g[17] ~= 0 and SG.boxHitG(g, sx, sy, sz, LX, LY, LZ, far) then
				return nil
			end
		end
	end
	if d3 < dS + 1e-3 then
		return nil
	end
	return SG.sunDone(1, px, py, pz, nx, ny, nz)
end

-- (SG.sunAt's answer counted; previews: checked against the sun ray's own)
function SG.sunDone(l: number, px: number, py: number, pz: number, nx: number, ny: number, nz: number): number
	SG.sunN += 1
	local pr = SG.probe :: any
	if pr then
		local real = BakeCast.sunVisible(params, Vector3.new(px, py, pz), Vector3.new(nx, ny, nz), SUN_V)
		pr.sunN = (pr.sunN or 0) + 1
		if real ~= l then
			pr.sunOff = (pr.sunOff or 0) + 1
		end
	end
	return l
end

-- The pixel ray's hit worked out without a ray where the map (Pixel/RayMap) is sure of it: of the block's two nearest
-- parts, the one the ray enters first (its shape worked out exactly, SG.rayShape; a part of another shape only so long
-- as the ray misses its box), with the third part on no nearer, and opaque; or the sky, when the ray misses both and
-- there is no third. Sets SG.aPart (nil: the sky), SG.aDepth and the normal SG.aNx, aNy, aNz; false when it needs its
-- ray (the request of 2026-11-22, "optimize it to the max": a third of the dense town's rays).
function SG.solve(s: Surf, gx: number, gy: number, p1: BasePart, p2: BasePart?, near2: number, near3: number): boolean
	local cam = s.cam
	local ox, oy, oz = cam.gox + gx * cam.ix + gy * cam.jx, cam.goy + gx * cam.iy + gy * cam.jy, cam.goz + gx * cam.iz + gy * cam.jz
	local lx, ly, lz = cam.lx, cam.ly, cam.lz
	local best, bp, bnx, bny, bnz = math.huge, nil :: BasePart?, 0, 0, 0
	local geom = SG.geom
	local g1 = geom[p1] or SG.geomOf(p1)
	local met1 = g1[17]
	if met1 == 1 and g1[16] ~= 0 then
		local t, edge, nx, ny, nz = SG.rayShape(g1, ox, oy, oz, lx, ly, lz)
		if edge then
			return false
		elseif t then
			best, bp, bnx, bny, bnz = t, p1, nx, ny, nz
		end
	elseif met1 ~= 0 and SG.boxHitG(g1, ox, oy, oz, lx, ly, lz, math.huge) then
		return false
	end
	if p2 and near2 < best + 1e-3 then
		local g2 = geom[p2] or SG.geomOf(p2 :: BasePart)
		local met2 = g2[17]
		if met2 == 1 and g2[16] ~= 0 then
			local t, edge, nx, ny, nz = SG.rayShape(g2, ox, oy, oz, lx, ly, lz)
			if edge then
				return false
			elseif t then
				if math.abs(t - best) <= 2e-3 then
					return false -- (two faces level with each other: the ray's own pick)
				elseif t < best then
					best, bp, bnx, bny, bnz = t, p2, nx, ny, nz
				end
			end
		elseif met2 ~= 0 and SG.boxHitG(g2, ox, oy, oz, lx, ly, lz, best) then
			return false
		end
	end
	if near3 <= best + 1e-3 then
		return false
	end
	if bp and (geom[bp] :: { number })[18] >= BakeCast.CLEAR_MIN then
		return false
	end
	SG.aPart, SG.aDepth, SG.aNx, SG.aNy, SG.aNz = bp, best, bnx, bny, bnz
	return true
end

-- One pixel of a cast over a layer rect (rx0 .. rx1, ry0 .. ry1, layer px), filling its block up to (bx1, by1) (global,
-- inclusive) as castSample does: the sky with no ray where no part reaches it (Pixel/RayMap), the face its anchors met
-- where it is sure to show (SG.shareAt; a pixel of its own, not an anchor or a stand-in), else its ray. The island's own view
-- only: a stage's parts are not on the map, nor is the next island the pre-cast draws.
function SG.castPx(s: Surf, gx: number, gy: number, bx1: number, by1: number, own: boolean, shadows: boolean, rx0: number, ry0: number, rx1: number, ry1: number)
	if SG.castSlowUs > 0 then
		-- (previews: a slower machine's cast, PixelRenderer.debugCastSlow)
		local until0 = os.clock() + SG.castSlowUs / 1e6
		while os.clock() < until0 do
		end
	end
	if not SG.noShare and not s.view.stage then
		local part, p2, near2, near3, flat1, flat2 = SG.Map.at(gx, gy)
		if part == false then
			SG.skyAt(s, gx, gy, bx1, by1)
			return
		end
		if part and SG.solve(s, gx, gy, part :: BasePart, p2, near2, near3) then
			local pr = SG.probe
			if pr then
				-- (previews: the hit worked out without a ray against the ray's own)
				local ap, ad, anx, any_, anz = SG.aPart, SG.aDepth, SG.aNx, SG.aNy, SG.aNz
				pr.cert += 1
				castSample(s, gx, gy, bx1, by1, own, shadows)
				local i = (gy - s.cam.gy) * s.W + (gx - s.cam.gx)
				local id = buffer.readu16(s.sId, i * 2)
				local dd = buffer.readf32(s.sDepth, i * 4)
				local nn = buffer.readu8(s.sNormal, i)
				local want = if ap then staticIdOf(ap) else 0
				local an = if ap then Shading.normalIndex(anx, any_, anz) else BakeCast.SKY_NORMAL
				if ap and SmoothParts.model(ap) then
					an = nn -- (the normal of a model lit smooth is its own, worked out after the hit)
				end
				if id == want and (ap == nil or math.abs(dd - ad) < 2e-3) and nn == an then
					pr.agree += 1
				else
					pr.off += 1
					if #pr.ex < 6 then
						table.insert(pr.ex, string.format("[%d,%d %s %.3f n%d / %s %.3f n%d]", gx, gy, if ap then ap.Name else "sky", ad, an, tostring(id), dd, nn))
					end
				end
				return
			end
			SG.solvedN += 1
			if SG.aPart == nil then
				SG.skyAt(s, gx, gy, bx1, by1)
			else
				castSample(s, gx, gy, bx1, by1, own, shadows, true)
			end
			return
		end
		if part and not own and bx1 == gx and by1 == gy and (gx % 2 == 1 or gy % 2 == 1) and SG.shareAt(s, gx, gy, part :: BasePart, p2, near2, near3, flat1, flat2, shadows, rx0, ry0, rx1, ry1) then
			return
		end
		local pr = SG.probe
		if pr then
			pr.tried += 1
			-- (what the rays the map could not answer met)
			castSample(s, gx, gy, bx1, by1, own, shadows)
			local h = SG.lastHit
			local k = if h == nil then "sky" elseif h:IsA("Part") then "part " .. tostring((h :: Part).Shape) elseif h:IsA("WedgePart") then "wedge" else h.ClassName
			if h and part == nil then
				k ..= " (no map)"
			elseif h and h ~= part and h ~= p2 then
				k ..= " (third or further)"
			elseif h and h == p2 then
				k ..= " (second)"
			end
			local hs = (pr :: any).hits or {}
			;(pr :: any).hits = hs
			hs[k] = (hs[k] or 0) + 1
			return
		end
	end
	castSample(s, gx, gy, bx1, by1, own, shadows)
end

-- The map of which parts reach where (Pixel/RayMap) kept for the island in view: its window the plot's lot from as low
-- as an island's rock hangs to as high as anything on it stands (Tuning.PixelMapLow, PixelMapHigh: past it pixels are
-- cast as ever), a little of its queue a frame (more while it is being made, and with the screen hidden).
function SG.mapStep()
	local v = CameraController.view()
	if v.stage then
		return
	end
	if v ~= SG.mapView then
		SG.mapView = v
		local ox = Street.origin(v.plot)
		local L = Street.LOT
		local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
		for _, wx in { ox + L.x0, ox + L.x1 } do
			for _, wy in { Tuning.PixelMapLow, Tuning.PixelMapHigh } do
				for _, wz in { L.z0, L.z1 } do
					local px, py = Raster.gridPoint(v.rot12, v.grid, wx, wy, wz)
					x0, y0, x1, y1 = math.min(x0, px), math.min(y0, py), math.max(x1, px), math.max(y1, py)
				end
			end
		end
		SG.Map.setView(v.rot12, v.grid.q, v.grid.phX, v.grid.phY, v.grid.l - Tuning.CamRayBack, math.floor(x0), math.floor(y0), math.ceil(x1), math.ceil(y1))
		-- the sun's map: the same lot seen along the sun (looking away from it, so depth grows away from the sun), its
		-- window the lot's box as the sun sees it
		local R = SG.sunRot or { CFrame.lookAt(Vector3.zero, -SUN_V):GetComponents() }
		local q = Tuning.PixelSunMapQ
		local u0, v0, u1, v1, dmin = math.huge, math.huge, -math.huge, -math.huge, math.huge
		for _, wx in { ox + L.x0, ox + L.x1 } do
			for _, wy in { Tuning.PixelMapLow, Tuning.PixelMapHigh } do
				for _, wz in { L.z0, L.z1 } do
					local u = (wx * R[4] + wy * R[7] + wz * R[10]) * q
					local w = -(wx * R[5] + wy * R[8] + wz * R[11]) * q
					local d = -(wx * R[6] + wy * R[9] + wz * R[12])
					u0, v0, u1, v1, dmin = math.min(u0, u), math.min(v0, w), math.max(u1, u), math.max(v1, w), math.min(dmin, d)
				end
			end
		end
		SG.sunL0 = dmin - 8
		SG.SunMap.setView(R, q, 0, 0, SG.sunL0, math.floor(u0), math.floor(v0), math.ceil(u1), math.ceil(v1))
		SG.sunRot = R
	end
	local ms = if (PixelRenderer :: any)._hidden then Tuning.PixelHiddenMs elseif SG.Map.ready() and (not SUN_ANY or SG.SunMap.ready()) then Tuning.PixelMapMs else Tuning.PixelMapBuildMs
	local m0 = SG.clock()
	local did = SG.Map.step(m0 + ms / 1000, SG.clock)
	if SUN_ANY and SG.Map.ready() and SG.SunMap.step(m0 + ms / 1000, SG.clock) then
		did = true
	end
	if did then
		stats.perf.mapMs = (stats.perf.mapMs or 0) + (SG.clock() - m0) * 1000
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
						SG.castPx(b, x, y, bx + st - 1, by + st - 1, false, shadows, 0, 0, b.W - 1, b.H - 1)
					end
				elseif bakePass < 3 then
					-- a block starting off the layer: a stand-in at its first pixel on it (later passes replace it)
					SG.castPx(b, x, y, bx + st - 1, by + st - 1, true, shadows, 0, 0, b.W - 1, b.H - 1)
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

-- The pan cache's tiles at most on this device: enough for the whole island (SG.isle), fewer on a touch screen with no
-- keyboard (its View starts further out, so an island takes fewer tiles, and a phone has less memory).
function SG.cacheCap(): number
	local uis = game:GetService("UserInputService")
	return if uis.TouchEnabled and not uis.KeyboardEnabled then Tuning.PixelPanCacheTilesTouch else Tuning.PixelPanCacheTiles
end

local function startBake()
	SG.unfin = nil -- (a bake casts every pixel again)
	SG.fin, SG.finCoarse = nil, false
	SG.pend = nil
	table.clear(SG.refine)
	local s = surf
	if s == nil then
		return
	end
	-- (the smooth models' balls gathered again: the island may have changed)
	SmoothParts.reset()
	-- (a new picture of the island: the pan cache starts again, and the next tier's pre-cast, its part ids renumbered; a
	-- stage's bake leaves the island's be)
	if not s.view.stage then
		SG.Tiles.setMax(SG.cacheCap())
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
	local px, py = CameraController.drawnPan()
	if SG.vpAt == SG.frameNo and SG.vpView == s.view then
		px, py = SG.vpX, SG.vpY -- (held off strips not cast yet: SG.viewPan)
	end
	local ox = math.clamp(px - s.cam.gx, 0, s.W - s.vw)
	local oy = math.clamp(py - s.cam.gy, 0, s.H - s.vh)
	if ox ~= s.ox or oy ~= s.oy then
		-- (the window moved: this frame composes, so the founder the view follows is drawn where it stands now. Composed
		-- only at the tier's hz, it kept still on the picture for a frame while the window moved under it and then jumped
		-- on: the report of 2026-11-21, "the camera now stutters the player as they walk")
		SG.touch = true
	end
	s.ox, s.oy = ox, oy
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
	SG.unfin = nil
	SG.fin, SG.finCoarse = nil, false
	SG.pend = nil
	table.clear(SG.refine)
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
	elseif old and old.ready and not old.view.stage and not v.stage and old.view.plot == v.plot and old.view.key ~= v.key and (old.K ~= v.K or old.view.fullX ~= v.fullX or old.view.fullY ~= v.fullY) then
		-- the screen changed size (a window made smaller or bigger, fullscreen and back): the island's picture is kept,
		-- and if the screen comes back to that size it shows again at once, baked again behind it (the world may
		-- have changed meanwhile). The report of 2026-11-21, "the island sometimes disappeared when the player tabs
		-- out": each size had its picture baked from nothing, the island hidden until it was done.
		stash = { key = old.view.key, surf = old, ids = table.clone(staticIds), albedos = table.clone(albedos), waters = table.clone(waters), texs = table.clone(texs), nextId = nextId, dirty = true, inv = invQueue, cur = invCur }
		rebakeAt = -1
	end
	local st = stash
	if st and st.surf.view.plot ~= v.plot then
		-- (another island: its picture will not be wanted)
		stash, st = nil, nil
	elseif st and not v.stage and st.key ~= v.key then
		-- (not its view yet: it waits, kept for when the screen comes back to its size; the world may change meanwhile)
		st.dirty = true
		st = nil
	end
	if st and not v.stage then
		stash = nil
		if st.key == v.key and not (img and img.Size.X == st.surf.W and img.Size.Y == st.surf.H) then
			-- (the image went with the other size: one of this size again, the picture sent up whole below)
			local _, im0 = ensureLayer()
			local ni = ImageMemory.create(st.surf.W, st.surf.H, "world")
			if ni then
				if img then
					img:Destroy()
				end
				img = ni
				im0.ImageContent = Content.fromObject(ni)
			end
		end
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
				local psz0 = image:FindFirstChildOfClass("UIScale")
				if psz0 then
					psz0.Scale = st.surf.K
				end
			end
			shown = true
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
	if m > 0 then
		-- (an even size at an even pan: a scroll's strips then cover whole 2x2 blocks of the global grid, SG.pendStep)
		W += W % 2
		H += H % 2
	end
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
	elseif old and not old.view.stage and not v.stage and (old.K ~= K or old.vw ~= W0 or old.vh ~= H0) then
		-- (the same image for another screen size or pixel size: what it holds is the old picture, drawn for the other
		-- size; hidden until the new one is baked)
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
	local lgx, lgy = px - m, py - m
	if m > 0 then
		lgx -= lgx % 2
		lgy -= lgy % 2
	end
	local cam = layerCam(v, lgx, lgy, K)
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
	-- (the sticky effect pixels over it again, on the rows that have any)
	local sc = stickCol
	local sr = stickRows
	if stickLive > 0 and sc and sr and buffer.len(sc) == W * s.H * 4 and buffer.len(sr) == s.H * 2 then
		for y = y0, y1 do
			if buffer.readu16(sr, y * 2) == 0 then
				continue
			end
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
		SG.waterSeen = 0
	end
	local W, H = s.W, s.H
	local cls, wave, shade, color = s.sWClass, s.sWave, s.sShade, s.sColor
	local was, now = SG.waterWas, SG.waterNow
	local all = SG.waterAllNow
	local pend = SG.waterPend
	local pn = SG.waterPendN
	local gx0, gy0 = s.cam.gx, s.cam.gy
	-- (the rows a slice met no water in are passed over till the static picture changes: the request of 2026-11-23,
	-- "optimize the game much much more"; a village's ponds take a few rows, and every row was looked at)
	local rows = SG.waterRows
	if rows == nil or buffer.len(rows) ~= H or SG.waterRowsVer ~= staticVer then
		rows = buffer.create(H)
		SG.waterRows, SG.waterRowsVer = rows, staticVer
	end
	local rowsB = rows :: buffer
	for y = (j - gy0) % S, H - 1, S do
		if buffer.readu8(rowsB, y) == 1 then
			continue
		end
		local row = y * W
		local seen0 = SG.waterSeen
		for x = 0, W - 1 do
			local i = row + x
			local c = buffer.readu8(cls, i)
			if c ~= 0 then
				SG.waterSeen += 1
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
		if SG.waterSeen == seen0 then
			buffer.writeu8(rowsB, y, 1)
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
		stickRows = buffer.create(s.H * 2)
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
		local sr = stickRows
		local y = i // s.W
		if sr and y * 2 < buffer.len(sr) then
			buffer.writeu16(sr, y * 2, math.min(65535, buffer.readu16(sr, y * 2) + 1))
		end
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
	local sr = stickRows
	local y = i // s.W
	if sr and y * 2 < buffer.len(sr) then
		buffer.writeu16(sr, y * 2, math.max(0, buffer.readu16(sr, y * 2) - 1))
	end
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
	-- (the strips not finished, and those shown before they were whole, SG.release: the effects leave them alone)
	local wait = SG.unfin
	if #SG.refine > 0 then
		local list = table.clone(wait or {})
		for _, j in SG.refine do
			table.insert(list, j.r)
		end
		wait = list
	end
	c.wait = wait
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
	-- and the picture each one was put down from, with its top left on the layer and its depth offset (false: none)
	pics = {} :: { any },
	check = false, -- (debugRimCheck)
	stats = { drawn = 0, px = 0, ms = 0 },
}
function Rims.flat(_rgb: number, _nx: number, _ny: number, _nz: number, _x: number, _y: number): number
	return 0
end
Raster.markUniform(Rims.flat)

-- The white rim of founder e, whose parts (drawn this tick) cover layer rect r. Returns the rim pixels laid. Put down
-- from a kept picture (`pic`: { c, x0, y0, dz }), its silhouette is that picture's pixels: the parts are not drawn
-- again (a founder walking showed one of its steps' pictures every frame and drew every part again for its rim).
function Rims.draw(s: Surf, e: Dyn, r: Rect, pic: any): number
	local w, h = r.x1 - r.x0 + 1, r.y1 - r.y0 + 1
	if w <= 0 or h <= 0 then
		return 0
	end
	if pic and not Rims.check then
		local m = Rims.fromPic(w, h, r, pic)
		return Shading.rim(s.frame, m, r.x0, r.y0, Rims.rgb, Rims.rgb, nil, true, s.cam.gx, s.cam.gy)
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
	if pic and Rims.check then
		-- (debugRimCheck: the silhouette a kept picture gives against the parts drawn)
		local ids, dep = buffer.create(n * 2), buffer.create(n * 4)
		buffer.copy(ids, 0, m.id, 0, n * 2)
		buffer.copy(dep, 0, m.depth, 0, n * 4)
		local q = Rims.fromPic(w, h, r, pic)
		local st = Rims.checked
		for i = 0, n - 1 do
			local a, b = buffer.readu16(ids, i * 2) ~= 0, buffer.readu16(q.id, i * 2) ~= 0
			st.px += if a then 1 else 0
			if a ~= b then
				st.off += 1
			elseif a and math.abs(buffer.readf32(dep, i * 4) - buffer.readf32(q.depth, i * 4)) > 1e-3 then
				st.depth += 1
			end
		end
		buffer.copy(m.id, 0, ids, 0, n * 2)
		buffer.copy(m.depth, 0, dep, 0, n * 4)
	end
	return Shading.rim(s.frame, m, r.x0, r.y0, Rims.rgb, Rims.rgb, nil, true, s.cam.gx, s.cam.gy)
end
Rims.checked = { px = 0, off = 0, depth = 0 }

-- A founder's silhouette for its rim over layer rect r (w x h), from the picture it was put down from: the mask's ids and
-- depths where the picture's pixels fall (depth as the picture was put down, its depth offset added).
function Rims.fromPic(w: number, h: number, r: Rect, pic: any): Raster.Frame
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
	if Rims.check then
		m = { W = w, H = h, color = buffer.create(n * 4), depth = buffer.create(n * 4), id = buffer.create(n * 2) }
	end
	m.W, m.H = w, h
	local mid, mdepth = m.id, m.depth
	buffer.fill(mid, 0, 0, n * 2)
	local c = pic.c :: DynCache
	local px = c.px
	local ox, oy, z = pic.x0 - r.x0, pic.y0 - r.y0, pic.dz
	for k = 0, c.n - 1 do
		local o = k * 14 -- (PX_BYTES)
		local x, y = ox + buffer.readu16(px, o), oy + buffer.readu16(px, o + 2)
		if x >= 0 and y >= 0 and x < w and y < h then
			local i = y * w + x
			buffer.writeu16(mid, i * 2, buffer.readu16(px, o + 12))
			buffer.writef32(mdepth, i * 4, buffer.readf32(px, o + 8) + z)
		end
	end
	return m
end

-- Every founder drawn this tick gets its rim (at most Rims.max: the own one first, then the nearest to (cx, cy)).
function Rims.drawAll(s: Surf, cx: number, cy: number)
	local t0 = SG.clock()
	local list, rects = Rims.list, Rims.rects
	local nr = #list
	local pics = Rims.pics
	if nr > Rims.max then
		local order = {}
		for i = 1, nr do
			local r = rects[i]
			local mx, my = (r.x0 + r.x1) * 0.5 - cx, (r.y0 + r.y1) * 0.5 - cy
			order[i] = { e = list[i], r = r, p = pics[i], k = if list[i].own then -1 else mx * mx + my * my }
		end
		table.sort(order, function(x, y)
			return x.k < y.k
		end)
		for i = 1, nr do
			list[i], rects[i], pics[i] = order[i].e, order[i].r, order[i].p
		end
		nr = Rims.max
	end
	local px = 0
	for i = 1, nr do
		px += Rims.draw(s, list[i], rects[i], pics[i] or nil)
	end
	local st = Rims.stats
	st.drawn, st.px, st.ms = nr, px, (SG.clock() - t0) * 1000
	table.clear(list)
	table.clear(rects)
	table.clear(pics)
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
local POSE_KEEP = 48
local GROUP_KEEP = 128 -- (pictures kept by pose for a group of models posed alike: PixelRenderer.pose)

-- Parts as they stand now against a snapshot (cfs, szs, gone); nil snapshot: never the same.
function SG.same(d: Dyn, cfs: { CFrame }?, szs: { Vector3 }?, gone: { boolean }?): boolean
	if cfs == nil or szs == nil or gone == nil then
		return false
	end
	local pf = stats.perf :: any
	pf.sameCalls = (pf.sameCalls or 0) + 1
	pf.sameParts = (pf.sameParts or 0) + #d.parts
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
	return SG.takePic(s, d, iso, ix0, iy0, ix1, iy1, ppu, s.cam.gx, s.cam.gy, d.gPosed, cfs, szs, gone, d.poseKey, SG.ver)
end

-- The picture of model d drawn into scratch frame f over its rect ix0 .. iy1 (the scratch's px; it stands at layer px
-- M less, the layer's pan then gx0, gy0), taken out into a kept picture and the scratch wiped there: kept for the model
-- (and for its pose, `key`) when it lies wholly on the scratch. Returns it and the layer rect it covers.
function SG.takePic(s: Surf, d: Dyn, iso: Raster.Frame, ix0: number, iy0: number, ix1: number, iy1: number, ppu: number, gx0: number, gy0: number, anchor: Vector3?, cfs: { CFrame }?, szs: { Vector3 }?, gone: { boolean }?, key: string?, ver: number): (DynCache?, number, number, number, number)
	local M = SG.ISO_M
	local IW, IH = iso.W, iso.H
	local cx0, cy0 = math.max(0, math.floor(ix0)), math.max(0, math.floor(iy0))
	local cx1, cy1 = math.min(IW - 1, math.ceil(ix1)), math.min(IH - 1, math.ceil(iy1))
	-- (the layer rect its parts cover, at the layer's pan now)
	local x0, y0, x1, y1 = ix0 - M + gx0 - s.cam.gx, iy0 - M + gy0 - s.cam.gy, ix1 - M + gx0 - s.cam.gx, iy1 - M + gy0 - s.cam.gy
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
	local lx0, ly0 = cx0 - M + gx0 - s.cam.gx, cy0 - M + gy0 - s.cam.gy
	local pic: DynCache = { gx = cx0 - M + gx0, gy = cy0 - M + gy0, w = cx1 - cx0 + 1, h = cy1 - cy0 + 1, n = n, px = px, cfs = cfs, szs = szs, gone = gone, ver = ver, ppu = ppu, shp = if pp.Transparency < 0.95 then pp.Position else nil, anchor = anchor }
	if whole then
		d.cache = pic
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
			local grp = d.poseGroup
			if grp and anchor then
				-- (its group's too, for the others of its kind: only a picture that knows where its model stood, so it
				-- can slide to wherever another one stands)
				local g = SG.groupPoses[grp]
				if g == nil then
					g = { pics = {}, order = {} }
					SG.groupPoses[grp] = g
				end
				if g.pics[key] == nil then
					table.insert(g.order, key)
					if #g.order > GROUP_KEEP then
						g.pics[table.remove(g.order, 1) :: string] = nil
					end
				end
				g.pics[key] = pic
			end
		end
	else
		d.cache = { gx = 0, gy = 0, w = 0, h = 0, n = -1, px = SG.none, cfs = cfs, szs = szs, gone = gone, ver = -1, ppu = ppu }
	end
	return pic, lx0, ly0, lx0 + pic.w - 1, ly0 + pic.h - 1
end

-- A model too costly to draw within a tick's time (a big driftling's blended body: 10 to 20 ms in the stress walk),
-- drawn over a few frames instead: its parts at once into a scratch of its own, as they stand now, its body a few ms a
-- frame after (Raster.blendJob), then its picture taken (SG.jobStep). It shows its last picture meanwhile. The request
-- of 2026-11-22, "ms at all times should not go above 20ms even at the highest stress tests".
function SG.jobStart(s: Surf, d: Dyn, ppu: number, texOn: boolean)
	local js0 = SG.clock()
	local _, icam = SG.isoFor(s)
	local f = SG.jobIso
	if f == nil or f.W ~= (SG.iso :: Raster.Frame).W or f.H ~= (SG.iso :: Raster.Frame).H then
		local src = SG.iso :: Raster.Frame
		local n = src.W * src.H
		local depth = buffer.create(n * 4)
		for y = 0, src.H - 1 do
			buffer.copy(depth, y * src.W * 4, SG.farRow :: buffer, 0, src.W * 4)
		end
		f = { W = src.W, H = src.H, color = buffer.create(n * 4), depth = depth, id = buffer.create(n * 2) }
		SG.jobIso = f
	end
	local px0, py0, tc0 = panX, panY, texCam
	panX, panY, texCam = icam.gx, icam.gy, icam
	SG.jobMode, SG.jobBlend = true, nil
	local ix0, iy0, ix1, iy1 = SG.drawModel(f :: Raster.Frame, d, icam, texOn)
	SG.jobMode = false
	panX, panY, texCam = px0, py0, tc0
	local cfs, szs, gone = {}, {}, {}
	for i, p in d.parts do
		local part = p.part
		cfs[i], szs[i], gone[i] = part.CFrame, part.Size, part.Parent == nil or part.Transparency >= 0.95
	end
	-- (the marks painted on, as they stood: the body's shading reads them)
	local PS = table.move(SG.paints, 1, SG.paintN * PAINT_STRIDE, 1, {})
	SG.job = { d = d, f = f, icam = icam, b = SG.jobBlend, ix0 = ix0, iy0 = iy0, ix1 = ix1, iy1 = iy1, gx0 = s.cam.gx, gy0 = s.cam.gy, ver = SG.ver, ppu = ppu, anchor = d.gPosed, cfs = cfs, szs = szs, gone = gone, key = d.poseKey, PS = PS, pn = SG.paintN, texPx = texPx, ms = 0 }
	SG.jobBlend = nil
	d.wantAt = nil
	SG.job.ms = (SG.clock() - js0) * 1000
end

-- The draw spread over frames (SG.jobStart) drawn on until `deadline`; its picture taken when it is done (the model
-- shows it from then on). True when there is none left.
function SG.jobStep(s: Surf, deadline: number): boolean
	local j = SG.job
	if j == nil then
		return true
	end
	local d = j.d
	if dyns[d.model] ~= d or j.ppu ~= s.cam.s / s.cam.K then
		SG.job = nil -- (the model went, or the view's scale changed: a fresh draw later)
		return true
	end
	local b = j.b
	local js0 = SG.clock()
	if b and b.J then
		local px0, py0, tc0, tp0 = panX, panY, texCam, texPx
		local bP, bC, bQ, bT, PS0, pn0 = SG.blendP, SG.blendCf, SG.blendPaint, SG.blendTex, SG.paints, SG.paintN
		panX, panY, texCam, texPx = j.icam.gx, j.icam.gy, j.icam, j.texPx
		SG.blendP, SG.blendCf, SG.blendPaint, SG.blendTex, SG.blendLast = b.P, b.C, b.paint, b.texOn, 0
		SG.paints, SG.paintN = j.PS, j.pn
		local done = Raster.blendStep(b.J, deadline)
		SG.paintOn = false
		panX, panY, texCam, texPx = px0, py0, tc0, tp0
		SG.blendP, SG.blendCf, SG.blendPaint, SG.blendTex, SG.paints, SG.paintN = bP, bC, bQ, bT, PS0, pn0
		SG.blendLast = 0
		j.ms += (SG.clock() - js0) * 1000
		if not done then
			return false
		end
		local J = b.J
		if J.written >= 0 and J.X1 >= J.X0 then
			j.ix0, j.iy0, j.ix1, j.iy1 = math.min(j.ix0, J.X0), math.min(j.iy0, J.Y0), math.max(j.ix1, J.X1), math.max(j.iy1, J.Y1)
		end
	end
	SG.job = nil
	SG.takePic(s, d, j.f, j.ix0, j.iy0, j.ix1, j.iy1, j.ppu, j.gx0, j.gy0, j.anchor, j.cfs, j.szs, j.gone, j.key, j.ver)
	d.drawnAt = SG.clock()
	-- (what the whole draw took, as a draw within a tick would have: the next draw of it and of its kind are planned by
	-- it, and the first draws of kinds not drawn yet)
	local took = j.ms + (SG.clock() - js0) * 1000
	local nm = d.model.Name
	if d.drawMs == nil and SG.drawByName[nm] == nil and #d.parts > 0 then
		SG.firstPerPart = math.max(Tuning.PixelFirstPartMs, SG.firstPerPart * 0.7 + took / #d.parts * 0.3)
	end
	d.drawMs = if d.drawMs then d.drawMs * 0.5 + took * 0.5 else took
	SG.drawByName[nm] = math.max(took, (SG.drawByName[nm] or took) * 0.8 + took * 0.2)
	local pf = stats.perf :: any
	pf.jobs = (pf.jobs or 0) + 1
	return true
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

function SG.plan(s: Surf, fresh: boolean, ppu: number, texOn: boolean, lite: boolean?): { PlanEntry }
	local cam = s.cam
	local W, H = s.W, s.H
	local out: { PlanEntry } = {}
	local need = SG.need
	table.clear(need)
	local at: { [Dyn]: PlanEntry } = {}
	local held: { [Dyn]: boolean } = {}
	-- (picture c over layer rect x0..y1 for entry e, slid on with its model: nothing when that takes it off the layer)
	local function put(e: PlanEntry, d: Dyn, c: DynCache, x0: number, y0: number, x1: number, y1: number)
		local gx, gy, gz = SG.glideOf(s, d, c)
		x0, y0, x1, y1 = x0 + gx, y0 + gy, x1 + gx, y1 + gy
		if x1 < 0 or y1 < 0 or x0 > W - 1 or y0 > H - 1 then
			return
		end
		e.pic, e.x0, e.y0, e.x1, e.y1, e.dz, e.gx, e.gy = c, x0, y0, x1, y1, gz - (d.lead or 0), gx, gy
	end
	local pq0 = SG.clock()
	local pqb = 0
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
		if lite and not d.rim then
			-- (a frame between two ticks, composed for the founder the view follows: every other model shows just
			-- what it showed, where it showed it, and its blob shadow too)
			local r, c = d.shR, d.shC
			if (r == nil or c == nil) and d.sR == nil then
				continue
			end
			local gx, gy = cam.gx, cam.gy
			local e: PlanEntry = { d = d, pic = nil, x0 = 0, y0 = 0, x1 = -1, y1 = -1, dz = 0, gx = 0, gy = 0, sx = nil, sy = 0, srx = 0, sry = 0 }
			if r and c then
				e.pic, e.x0, e.y0, e.x1, e.y1, e.dz = c, r.x0 + 1 - gx, r.y0 + 1 - gy, r.x1 - 1 - gx, r.y1 - 1 - gy, d.shDz or 0
			end
			local sx, sy = d.sx, d.sy
			if sx and sy and d.sR then
				e.sx, e.sy, e.srx, e.sry = sx - gx, sy - gy, d.srx or 0, d.sry or 0
			end
			held[d] = true
			table.insert(out, e)
			continue
		end
		local e: PlanEntry = { d = d, pic = nil, x0 = 0, y0 = 0, x1 = -1, y1 = -1, dz = 0, gx = 0, gy = 0, sx = nil, sy = 0, srx = 0, sry = 0 }
		table.insert(out, e)
		at[d] = e
		if culled then
			continue
		end
		local pb = SG.clock()
		local c, x0, y0, x1, y1 = SG.blitOk(s, d, fresh, ppu)
		pqb += SG.clock() - pb
		if c then
			put(e, d, c, x0, y0, x1, y1)
		elseif not SG.offPic(s, d, ppu) or not SG.same(d, (d.cache :: DynCache).cfs, (d.cache :: DynCache).szs, (d.cache :: DynCache).gone) then
			-- (a model whose picture lies wholly off the layer and has not moved shows nothing and needs no draw)
			table.insert(need, d)
		end
	end
	do
		local pfq = stats.perf :: any
		pfq.planLoopMs = (pfq.planLoopMs or 0) + (SG.clock() - pq0) * 1000
		pfq.planBlitOkMs = (pfq.planBlitOkMs or 0) + pqb * 1000
	end
	if #need > 1 then
		-- (of the models with no picture, the one nearest the middle of the screen's window first: one coming in at the
		-- margin past the screen waits, one on the screen does not)
		local mid = SG.needMid
		table.clear(mid)
		local wcx = (if SG.vpX then (SG.vpX :: number) - cam.gx else s.m) + s.vw * 0.5
		local wcy = (if SG.vpY then (SG.vpY :: number) - cam.gy else s.m) + s.vh * 0.5
		for _, d in need do
			local fp = d.parts[1]
			if d.drawnAt == nil and fp then
				local pp = fp.part.Position
				local fx, fy = Raster.project(cam, pp.X, pp.Y, pp.Z)
				mid[d] = math.abs(fx - wcx) / s.vw + math.abs(fy - wcy) / s.vh
			end
		end
		table.sort(need, function(a: Dyn, b: Dyn): boolean
			local ao, bo = a.own == true or a.rim == true or a.focus == true, b.own == true or b.rim == true or b.focus == true
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
			local ma, mb = mid[a], mid[b]
			if ma and mb then
				return ma < mb
			end
			return (a.drawnAt or 0) < (b.drawnAt or 0)
		end)
	end
	-- (within the tick's time and the frame's: a model is drawn only if what it took last time, or what one of its kind
	-- took, still fits; a costlier one is drawn over a few frames, SG.jobStart)
	local now0 = SG.clock()
	local budgetEnd = math.min(now0 + Tuning.PixelDynMs / 1000, math.max(now0, SG.frameEnd - Tuning.PixelComposeMs / 1000))
	local drawn = 0
	for _, d in need do
		local e = at[d]
		local nm0 = d.model.Name
		local estMs = math.max(d.drawMs or 0, SG.drawByName[nm0] or 0)
		if d.drawMs == nil and SG.drawByName[nm0] == nil then
			-- (never drawn, nor one of its kind: guessed from its parts, as the first draws of the others went. A
			-- driftling's first draw blends its body, 10 to 30 ms in the stress walk)
			estMs = math.max(SG.drawAvg, SG.firstPerPart * #d.parts)
		end
		local est = estMs / 1000
		local t = SG.clock()
		-- (one with no picture at all shows nothing till it is drawn: it may take the frame's time, not just the tick's)
		local cap = if d.cache == nil then math.max(budgetEnd, SG.frameEnd - Tuning.PixelComposeMs / 1000, now0 + Tuning.PixelDynMs / 1000) else budgetEnd
		local fits = t + est <= cap and not (SG.job and SG.job.d == d)
		if not d.wantAt then
			d.wantAt = t
		end
		if not SG.noBudget and (drawn >= Tuning.PixelMaxDyn or not fits) and not d.own and not d.rim and not d.focus then
			-- (too costly for the tick's time: drawn over a few frames, one model at a time; SG.jobStart)
			if SG.job == nil and not SG.jobDone and estMs > Tuning.PixelDynMs * 0.5 then
				SG.jobStart(s, d, ppu, texOn)
			end
			local c, x0, y0, x1, y1 = SG.blitOk(s, d, false, ppu)
			if c then
				put(e, d, c, x0, y0, x1, y1)
			else
				SG.skips += 1
				local k = d.cache
				local why = if k == nil then "never drawn" elseif k.n < 0 then "not kept" elseif k.ver ~= SG.ver then "old picture" elseif k.ppu ~= ppu then "other scale" else "moved, last seen off the layer"
				SG.skipWhy[why] = (SG.skipWhy[why] or 0) + 1
				local fp = d.parts[1]
				if k == nil and fp and SG.vpX then
					-- (previews: one the screen's window shows, not just the margin past it)
					local pp = fp.part.Position
					local fx, fy = Raster.project(cam, pp.X, pp.Y, pp.Z)
					local wx, wy = (SG.vpX :: number) - cam.gx, (SG.vpY :: number) - cam.gy
					if fx >= wx and fy >= wy and fx < wx + s.vw and fy < wy + s.vh then
						SG.skipWhy["never drawn, on screen"] = (SG.skipWhy["never drawn, on screen"] or 0) + 1
					end
				end
			end
			continue
		end
		drawn += 1
		local kd = SG.clock()
		local pic, x0, y0, x1, y1 = SG.drawPic(s, d, ppu, texOn)
		d.drawnAt = SG.clock()
		d.wantAt = nil
		-- (what it took: the next draw of it, and of a model not drawn yet, is planned by it)
		local took = ((d.drawnAt :: number) - kd) * 1000
		if took > 8 and SG.frameLog then
			-- (previews: the costly draws, what they were)
			local hd = SG.heavyDraws
			local name = d.model.Name
			hd[name] = hd[name] or { n = 0, ms = 0, parts = #d.parts, px = 0 }
			hd[name].n += 1
			hd[name].ms = math.max(hd[name].ms, took)
			hd[name].px = math.max(hd[name].px, if pic then pic.n else 0)
			hd[name].blend = math.max(hd[name].blend or 0, SG.blendMs)
		end
		local nm = d.model.Name
		if d.drawMs == nil and SG.drawByName[nm] == nil and #d.parts > 0 then
			SG.firstPerPart = math.max(Tuning.PixelFirstPartMs, SG.firstPerPart * 0.7 + took / #d.parts * 0.3)
		end
		d.drawMs = if d.drawMs then d.drawMs * 0.5 + took * 0.5 else took
		SG.drawAvg += (took - SG.drawAvg) * 0.2
		SG.drawByName[nm] = math.max(took, (SG.drawByName[nm] or took) * 0.8 + took * 0.2)
		local pfp = stats.perf
		local who = if d.own then "own" elseif d.rim then "rim" else "other"
		pfp[who .. "Draws"] = (pfp[who .. "Draws"] or 0) + 1
		pfp[who .. "DrawMs"] = (pfp[who .. "DrawMs"] or 0) + ((d.drawnAt :: number) - kd) * 1000
		SG.draws += 1
		if pic then
			put(e, d, pic, x0, y0, x1, y1)
		end
	end
	local ps0 = SG.clock()
	-- (the draw spread over frames: on with what is left of the tick's draw time, and of the frame's)
	SG.jobDone = false
	if SG.job and not lite then
		local kj = SG.clock()
		local dl = math.max(budgetEnd, math.min(SG.frameEnd, kj + Tuning.PixelJobMs / 1000))
		if SG.jobStep(s, math.max(kj + 0.0005, dl)) then
			SG.jobDone = true
		end
		local pfj = stats.perf :: any
		pfj.jobMs = (pfj.jobMs or 0) + (SG.clock() - kj) * 1000
	end
	for _, e in out do
		local d = e.d
		local model = d.model
		local first = d.parts[1]
		if not held[d] and model.Parent ~= nil and first ~= nil and model:GetAttribute("PixelShadow") ~= nil then
			local cx, cy, rx, ry = SG.shadowGeo(s, model, first.part, e.pic)
			if cx then
				-- (it slides with its picture, by the same whole px)
				e.sx, e.sy, e.srx, e.sry = cx + e.gx, cy + e.gy, rx, ry
			end
		end
	end
	local pfs = stats.perf :: any
	pfs.planShadowMs = (pfs.planShadowMs or 0) + (SG.clock() - ps0) * 1000
	pfs.planModels = (pfs.planModels or 0) + #out
	if fresh and not lite then
		-- (the looks at whether models changed kept to about Tuning.PixelSameMs a tick)
		local ms = SG.sameT * 1000
		if ms > Tuning.PixelSameMs then
			SG.sameEvery = math.min(12, SG.sameEvery + 1)
		elseif ms < Tuning.PixelSameMs * 0.4 then
			SG.sameEvery = math.max(1, SG.sameEvery - 1)
		end
		SG.sameT = 0
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

-- A drawn model's rect, a pixel round it, for the ink and the upload; a founder's for its white rim too (drawn from
-- `pic`, the picture it was put down from, when given: Rims.draw).
function SG.addRect(rects: { Rect }, d: Dyn, x0: number, y0: number, x1: number, y1: number, pic: any?)
	if x0 > x1 then
		return
	end
	table.insert(rects, { x0 = x0 - 1, y0 = y0 - 1, x1 = x1 + 1, y1 = y1 + 1 })
	if d.rim then
		local s = surf :: Surf
		table.insert(Rims.list, d)
		table.insert(Rims.rects, { x0 = math.max(0, x0), y0 = math.max(0, y0), x1 = math.min(s.W - 1, x1), y1 = math.min(s.H - 1, y1) })
		table.insert(Rims.pics, pic or false)
	end
end

-- Model d's kept picture when it can stand for a draw this tick (fresh: every model is due, so only one that has not
-- moved; otherwise a model that is not a founder may show it though it has moved), and the layer rect it covers; nil:
-- draw it.
function SG.blitOk(s: Surf, d: Dyn, fresh: boolean, ppu: number): (DynCache?, number, number, number, number)
	-- (posed in a pose it has a picture of: that picture stands for its parts as they are now)
	local key, poses = d.poseKey, d.poses
	local posed = false
	if key then
		local pc = if poses then poses[key] else nil
		local grp = d.poseGroup
		if pc == nil and grp then
			-- (one of its group's: a driftling of the same kind drew it, posed the same way)
			local g = SG.groupPoses[grp]
			pc = if g then g.pics[key] else nil
			if pc and (pc.anchor == nil or d.gNow == nil) then
				pc = nil
			end
			if pc then
				local pfg = stats.perf :: any
				pfg.groupHits = (pfg.groupHits or 0) + 1
			end
		end
		if pc and pc.ver == SG.ver and pc.ppu == ppu then
			-- (its picture stands for the parts wherever the model has gone since: the founder walking keeps stepping
			-- through the same few poses, slid on, SG.glideOf)
			posed = true
			local cur = d.cache
			if cur ~= pc and (cur == nil or cur.from ~= pc) then
				-- (the parts as they stand are not read: while posed, nothing compares them; once not, it is drawn
				-- afresh, SG.same. Reading every part of every driftling whose pose changed was most of a tick's plan
				-- in the stress walk)
				local cc = table.clone(pc)
				cc.cfs, cc.szs, cc.gone, cc.from = nil, nil, nil, pc
				d.cache = cc
				-- (the poses used last are the ones kept: POSE_KEEP)
				local order = d.poseOrder
				if order and poses and poses[key] and order[#order] ~= key then
					local at = table.find(order, key)
					if at then
						table.remove(order, at)
						table.insert(order, key)
					end
				end
			end
		end
	end
	local c = d.cache
	if c == nil or c.n < 0 or c.ver ~= SG.ver or c.ppu ~= ppu or SG.off then
		return nil, 0, 0, 0, 0
	end
	if not posed and (key or d.wantAt) and (fresh or d.rim) then
		-- (posed in a pose it has no picture of yet, or already found changed and waiting for its draw: its parts have
		-- moved, nothing to compare)
		return nil, 0, 0, 0, 0
	end
	if not posed and (fresh or d.rim) then
		-- (a crowd's models looked at a share a tick, the founders every tick: SG.sameEvery)
		-- (and no more than Tuning.PixelSameMs of looks a tick: the rest keep their pictures till a later tick)
		if d.rim or d.own or d.focus or (SG.updSeq - (d.sameSeq or -1e9) >= SG.sameEvery and SG.sameT * 1000 < Tuning.PixelSameMs) then
			d.sameSeq = SG.updSeq
			local k0 = SG.clock()
			local same = SG.same(d, c.cfs, c.szs, c.gone)
			SG.sameT += SG.clock() - k0
			if not same then
				return nil, 0, 0, 0, 0
			end
		end
	end
	local x0, y0 = c.gx - s.cam.gx, c.gy - s.cam.gy
	local x1, y1 = x0 + c.w - 1, y0 + c.h - 1
	-- (a picture reaching off the layer is put down clipped: it was drawn whole, past the layer's edge. Where it goes is
	-- where it slides to: a founder's step drawn far back along the walk)
	local gx, gy = SG.glideOf(s, d, c)
	if x1 + gx < 0 or y1 + gy < 0 or x0 + gx > s.W - 1 or y0 + gy > s.H - 1 then
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
	SG.blendMs = 0
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
		if n > 0 and SG.jobMode then
			-- (a draw spread over frames, SG.jobStart: the body set up to be drawn a few ms a frame, its members and
			-- what shades them kept apart, since the next draw fills the same tables)
			local JM, JP, JC, JQ = table.create(n), table.create(n), table.create(n), table.create(n)
			for i = 1, n do
				JM[i], JP[i], JC[i], JQ[i] = M[i], P[i], C[i], SG.blendPaint[i]
			end
			SG.jobBlend = { J = Raster.blendJob(f, cam, JM, n, k, SG.shadeMember :: Raster.BlendShade), P = JP, C = JC, paint = JQ, texOn = texOn }
		elseif n > 0 then
			SG.blendLast, SG.blendTex = 0, texOn
			local kb0 = SG.clock()
			local w, bx0, by0, bx1, by1 = Raster.drawBlend(f, cam, M, n, k, SG.shadeMember :: Raster.BlendShade)
			SG.blendMs = (SG.clock() - kb0) * 1000
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
	SG.markY0, SG.markY1 = math.huge, -1
end

-- Marks the tiles under a layer rect (inclusive) to draw again; returns how many of them were clean.
function SG.mark(x0: number, y0: number, x1: number, y1: number): number
	local T = SG.TILE
	local cols = SG.tcols
	local tx0, ty0 = math.max(0, x0 // T), math.max(0, y0 // T)
	local tx1, ty1 = math.min(cols - 1, x1 // T), math.min(SG.trows - 1, y1 // T)
	local bits = SG.bits
	local n = 0
	-- (the rows of tiles marked, so SG.runs looks at those alone)
	if ty0 <= ty1 and tx0 <= tx1 then
		SG.markY0, SG.markY1 = math.min(SG.markY0, ty0), math.max(SG.markY1, ty1)
	end
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
	for ty = math.max(0, SG.markY0), math.min(rows - 1, SG.markY1) do
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
		table.insert(Rims.pics, if c then { c = c, x0 = x0, y0 = y0, dz = dz or 0 } else false)
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
-- The models that changed this tick (a picture moved, a new picture, gone, a blob shadow moved) moved within the tick's
-- budget (Tuning.PixelComposeMs, worked out in pixels redone at the cost a pixel had lately): the founders always, then
-- the others that have waited longest, the nearest the middle of the screen first; the rest show what they showed and
-- where, as a lite frame leaves them, and wait for a later tick. The request of 2026-11-22, "ms at all times should not
-- go above 20ms even at the highest stress tests": in the stress walk's crowd a tick redid up to 190,000 px, 200 ms.
function SG.budgetPlan(s: Surf, plan: { PlanEntry })
	local gx, gy = s.cam.gx, s.cam.gy
	local cx, cy = s.ox + s.vw / 2, s.oy + s.vh / 2
	SG.updSeq += 1
	local seq = SG.updSeq
	local cands: { { e: PlanEntry, cost: number, age: number, dist: number, pri: number, vis: boolean } } = {}
	local wx0, wy0, wx1, wy1 = s.ox, s.oy, s.ox + s.vw - 1, s.oy + s.vh - 1
	local spent = 0
	for _, e in plan do
		local d = e.d
		local pic = e.pic
		local was = d.shR
		local picSame = pic ~= nil and pic == d.shC and not d.rim and was ~= nil and was.x0 + 1 == e.x0 + gx and was.y0 + 1 == e.y0 + gy and d.shDz == e.dz
		local picNone = pic == nil and was == nil
		local shSame = (e.sx == nil and d.sR == nil) or (e.sx ~= nil and e.sx + gx == d.sx and e.sy + gy == d.sy and e.srx == d.srx and e.sry == d.sry)
		if (picSame or picNone) and shSame then
			continue
		end
		-- (what it redoes: where it was and where it goes, its picture and its blob shadow, in layer px; a step of a
		-- pixel or two redoes much the same pixels twice, so where the two overlap their box is the cost, else both)
		local ox0, oy0, ox1, oy1 = math.huge, math.huge, -math.huge, -math.huge
		local nx0, ny0, nx1, ny1 = math.huge, math.huge, -math.huge, -math.huge
		if not (picSame or picNone) then
			if was then
				ox0, oy0, ox1, oy1 = was.x0 - gx, was.y0 - gy, was.x1 - gx, was.y1 - gy
			end
			if pic then
				nx0, ny0, nx1, ny1 = e.x0 - 1, e.y0 - 1, e.x1 + 1, e.y1 + 1
			end
		end
		if not shSame then
			local sr = d.sR
			if sr then
				ox0, oy0, ox1, oy1 = math.min(ox0, sr.x0 - gx), math.min(oy0, sr.y0 - gy), math.max(ox1, sr.x1 - gx), math.max(oy1, sr.y1 - gy)
			end
			if e.sx then
				local sx0, sy0, sx1, sy1 = SG.shadowRect(e.sx, e.sy, e.srx, e.sry)
				nx0, ny0, nx1, ny1 = math.min(nx0, sx0), math.min(ny0, sy0), math.max(nx1, sx1), math.max(ny1, sy1)
			end
		end
		local function box(x0: number, y0: number, x1: number, y1: number): number
			return if x1 >= x0 and y1 >= y0 then (x1 - x0 + 1) * (y1 - y0 + 1) else 0
		end
		local cost
		if ox1 >= nx0 and nx1 >= ox0 and oy1 >= ny0 and ny1 >= oy0 then
			cost = box(math.min(ox0, nx0), math.min(oy0, ny0), math.max(ox1, nx1), math.max(oy1, ny1))
		else
			cost = box(ox0, oy0, ox1, oy1) + box(nx0, ny0, nx1, ny1)
		end
		-- (the founders always; and one shown from a picture not kept, which cannot be shown as it was)
		if d.own or d.rim or d.focus or (was ~= nil and d.shC == nil) then
			spent += cost
			d.updAt = seq
		else
			local mx = if pic then (e.x0 + e.x1) / 2 elseif was then (was.x0 + was.x1) / 2 - gx else cx
			local my = if pic then (e.y0 + e.y1) / 2 elseif was then (was.y0 + was.y1) / 2 - gy else cy
			-- (first one coming into sight or leaving it, then one that moved, then one only posed anew in place: a
			-- picture held where it was reads as a jump, a pose held a tick longer does not)
			local pri = if was == nil or pic == nil then 0 elseif was.x0 + 1 ~= e.x0 + gx or was.y0 + 1 ~= e.y0 + gy then 1 else 2
			-- (whether the screen shows it, where it was or where it goes)
			local vis = false
			if pic then
				vis = not (e.x1 < wx0 or e.x0 > wx1 or e.y1 < wy0 or e.y0 > wy1)
			end
			if not vis and was then
				vis = not (was.x1 - gx < wx0 or was.x0 - gx > wx1 or was.y1 - gy < wy0 or was.y0 - gy > wy1)
			end
			table.insert(cands, { e = e, cost = cost, age = seq - (d.updAt or -1e6), dist = math.abs(mx - cx) + math.abs(my - cy), pri = pri, vis = vis })
		end
	end
	if #cands == 0 then
		return
	end
	table.sort(cands, function(a, b)
		if a.pri ~= b.pri then
			return a.pri < b.pri
		end
		if a.vis ~= b.vis then
			return a.vis
		end
		if a.age ~= b.age then
			return a.age > b.age
		end
		return a.dist < b.dist
	end)
	local budget = Tuning.PixelComposeMs * 1000 / math.max(0.05, SG.usPerPx)
	-- (one moving, coming or going may take Tuning.PixelMoveMs more)
	local moveBudget = budget + Tuning.PixelMoveMs * 1000 / math.max(0.05, SG.usPerPx)
	local held = 0
	local sure = 0
	local sureBudget = moveBudget + Tuning.PixelMoveCapMs * 1000 / math.max(0.05, SG.usPerPx)
	do
		-- (previews: what the budget saw)
		local pfb = stats.perf :: any
		pfb.budUs = SG.usPerPx
		pfb.budTicks = (pfb.budTicks or 0) + 1
		pfb.budForced = (pfb.budForced or 0) + spent
		for _, c in cands do
			pfb.budCands = (pfb.budCands or 0) + 1
			pfb.budCost = (pfb.budCost or 0) + c.cost
		end
	end
	for _, c in cands do
		local e, d = c.e, c.e.d
		local ok = spent + c.cost <= (if c.pri < 2 then moveBudget else budget)
		if not ok and c.pri < 2 and c.vis and sure < Tuning.PixelMoveMin and spent + c.cost <= sureBudget then
			-- (on the screen and moving, coming or going: it moves this tick whatever the budget says, up to
			-- Tuning.PixelMoveMin of them; one held where it was jumped the tick it moved again)
			ok = true
			sure += 1
		end
		if ok then
			spent += c.cost
			d.updAt = seq
		else
			-- (as it was: its picture where it showed it, its blob shadow where it lay)
			held += 1
			local r, pc = d.shR, d.shC
			if r and pc then
				e.pic, e.x0, e.y0, e.x1, e.y1, e.dz = pc, r.x0 + 1 - gx, r.y0 + 1 - gy, r.x1 - 1 - gx, r.y1 - 1 - gy, d.shDz or 0
			else
				e.pic = nil
			end
			local sx, sy, sr = d.sx, d.sy, d.sR
			if sx and sy and sr then
				e.sx, e.sy, e.srx, e.sry = sx - gx, sy - gy, d.srx or 0, d.sry or 0
			else
				e.sx = nil
			end
		end
	end
	local pf = stats.perf :: any
	pf.heldModels = (pf.heldModels or 0) + held
end

function SG.incCompose(s: Surf, due: boolean?)
	local W, H = s.W, s.H
	local n = W * H
	local cam = s.cam
	local gx, gy = cam.gx, cam.gy
	local f = s.frame
	local base = SG.base :: { color: buffer, id: buffer }
	local pf = stats.perf
	local k0 = SG.clock()
	-- A frame between two of the tier's ticks, composed only because the view moved (`lite`: the founder the view follows
	-- is drawn where it stands now, the rest as it was). The request of 2026-11-21, "optimize it, find ways until you
	-- manage to reduce the frame speed close to the frame speed while standing without scrolling": every frame of a
	-- walk was a whole tick (every model planned, the effects run, a band swept), twice the work of a frame standing.
	local lite = due == false and Tuning.PixelLiteFollow
	-- last tick's effects come off (the frame as it stood before them); their book is kept to grade those pixels. A lite
	-- frame keeps them: their pixels are noted and put back over whatever it draws again
	local oldBook, oldN = fxPrev, fxPrevN
	local color, ids = f.color, f.id
	local fxKeep: buffer? = nil
	if lite then
		if oldN > 0 then
			local kb = buffer.create(oldN * 6)
			for k = 0, oldN - 1 do
				local i = buffer.readu32(oldBook, k * 4)
				if i < n then
					buffer.writeu32(kb, k * 6, buffer.readu32(color, i * 4))
					buffer.writeu16(kb, k * 6 + 4, buffer.readu16(ids, i * 2))
				end
			end
			fxKeep = kb
		end
	else
		for k = 0, oldN - 1 do
			local i = buffer.readu32(oldBook, k * 4)
			if i < n then
				buffer.writeu32(color, i * 4, buffer.readu32(base.color, i * 4))
				buffer.writeu16(ids, i * 2, buffer.readu16(base.id, i * 2))
			end
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
	-- (a band of the layer drawn again every tenth compose, round and round: whatever a compose of a few tiles might
	-- leave behind lasts a few seconds at most. Every third until the request of 2026-11-23, "optimize the game much
	-- much more": the band was as many pixels as all the rest a compose redid; the checks against whole composes find
	-- none left behind)
	local T = SG.TILE
	if not lite then
		SG.sweep += 1
		if SG.sweep % 10 == 0 then
			local row = (SG.sweep // 10) % math.max(1, SG.trows)
			mark(0, row * T, W - 1, row * T + T - 1)
		end
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
	local kp = SG.clock()
	local plan = SG.plan(s, fresh, ppu, texOn, lite)
	pf.planMs = (pf.planMs or 0) + (SG.clock() - kp) * 1000
	if fresh and not lite and not SG.noBudget then
		SG.budgetPlan(s, plan)
	end
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
	local kr = SG.clock()
	for _, r in strips do
		restoreRect(s, r)
	end
	local runs = SG.runs(s)
	for _, r in runs do
		restoreRect(s, r)
	end
	local k1 = SG.clock()
	pf.restoreMs = (pf.restoreMs or 0) + (k1 - kr) * 1000
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
	-- the effects over everything (a lite frame: last tick's, where they were)
	local fxRects: { Rect } = {}
	if fxKeep then
		local kb = fxKeep :: buffer
		for k = 0, oldN - 1 do
			local i = buffer.readu32(oldBook, k * 4)
			if i < n then
				buffer.writeu32(color, i * 4, buffer.readu32(kb, k * 6))
				buffer.writeu16(ids, i * 2, buffer.readu16(kb, k * 6 + 4))
			end
		end
	elseif not lite and not SG.quiet then
		fxRects = runFx(s, os.clock())
	end
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
		if not lite then
			for k = 0, fxPrevN - 1 do
				local i = buffer.readu32(fxPrev, k * 4)
				if i < n then
					gradeSpan(color, ids, i, 1, o, i)
				end
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
	local runArea = area
	-- (strips finished a frame after their scroll go up as rects: SG.finishStrips)
	local lateUp: { Rect } = if SG.panned then {} else strips
	for _, r in lateUp do
		area += (r.x1 - r.x0 + 1) * (r.y1 - r.y0 + 1)
	end
	if SG.panned or SG.upWhole or #runs + #fxRects + #lateUp > 3 * MAX_RECTS or area * 3 > n then
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
		for _, r in lateUp do
			SG.upRect(s, r, src)
		end
	end
	pf.uploadMs += (SG.clock() - k6) * 1000
	if fresh and not lite and runArea >= 2000 then
		-- (what a pixel redone cost this tick, for the next ticks' budget: SG.budgetPlan; the tiles redone only, not the
		-- strips sent up late)
		-- (the stages that grow with the pixels redone: putting the static picture back, the models and shadows down,
		-- the ink and the grade; the effects, the rims and the sending up cost about the same whatever moved, and counted
		-- in made a moving driftling look several times dearer than it is)
		local us = ((k3 - kr) + (k6 - k5)) * 1e6 / runArea
		SG.usPerPx += (math.clamp(us, 0.1, 20) - SG.usPerPx) * 0.3
	end
	SG.panned, SG.upWhole, SG.touch = false, false, false
	table.clear(strips)
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
	if SG.unfin and (needFull or not SG.live(s)) then
		SG.finishStrips(s)
	end
	-- (the incremental compose when the layer has one going: SG.incCompose)
	local live = SG.live(s)
	if not needFull and SG.incOn == s and not live then
		needFull = true
	end
	if not needFull and live then
		local arm = SG.incArm
		SG.noBudget = arm
		-- (debugIncCheck's compose is a whole tick: a lite frame leaves the other models where they were, which a whole
		-- compose at the same moment does not)
		local area = SG.incCompose(s, if arm then nil else due)
		prevRects = {}
		stats.ticks += 1
		stats.composeMs = (SG.clock() - t0) * 1000
		stats.perf.composeMs += stats.composeMs
		-- (the frames between ticks apart: SG.incCompose's lite compose)
		local lk = if due == false then "lite" else "tick"
		local pfx = stats.perf :: any
		pfx[lk .. "Ms"] = (pfx[lk .. "Ms"] or 0) + stats.composeMs
		pfx[lk .. "Frames"] = (pfx[lk .. "Frames"] or 0) + 1
		if arm then
			-- (debugIncCheck: the frame before the effects against a whole compose's at the same moment)
			SG.incArm = false
			local n = s.W * s.H
			local b = SG.base :: { color: buffer, id: buffer }
			local a, ai, ad = buffer.create(n * 4), buffer.create(n * 2), buffer.create(n * 4)
			buffer.copy(a, 0, b.color, 0, n * 4)
			buffer.copy(ai, 0, b.id, 0, n * 2)
			buffer.copy(ad, 0, s.frame.depth, 0, n * 4)
			-- (the whole compose's base is taken before its effects run: a lawn tuft they stick anew would differ; strips a
			-- scroll brought in that are not finished yet lie past the screen's edge and are left out, SG.finishStrips)
			local waiting = SG.unfin
			SG.snap = true
			needFull = true
			compose(false)
			local snap = SG.snapped :: { color: buffer, id: buffer, depth: buffer }
			local off, ties = 0, 0
			local bias = s.cam.bias
			local seen: { string } = {}
			local function waits(i: number): boolean
				if waiting == nil then
					return false
				end
				local x, y = i % s.W, i // s.W
				for _, r in waiting do
					if x >= r.x0 - 3 and x <= r.x1 + 3 and y >= r.y0 - 3 and y <= r.y1 + 3 then
						return true
					end
				end
				return false
			end
			for i = 0, n - 1 do
				local ia, ib = buffer.readu16(ai, i * 2), buffer.readu16(snap.id, i * 2)
				if (buffer.readu32(a, i * 4) ~= buffer.readu32(snap.color, i * 4) or ia ~= ib) and not waits(i) then
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
			SG.addRect(rects, e.d, e.x0, e.y0, e.x1, e.y1, { c = pic, x0 = e.x0, y0 = e.y0, dz = e.dz })
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
	-- (one copy of the whole buffer by the pixel offset, not a copy a row: a pixel whose source lay past the side of its
	-- row gets the next row's, but those are the strips coming in, which are always written afresh; a scroll moved
	-- some twenty buffers a row at a time, about a third of its fixed cost)
	local k = (dy * W + dx) * e
	local len = W * H * e
	if k >= 0 then
		buffer.copy(b, 0, b, k, len - k)
	else
		buffer.copy(b, -k, b, 0, len + k)
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
	-- (strips queued before it, finished this frame, move with the picture)
	local kept: { Rect } = {}
	for _, r in SG.strips do
		local q = { x0 = math.max(0, r.x0 - sx), y0 = math.max(0, r.y0 - sy), x1 = math.min(W - 1, r.x1 - sx), y1 = math.min(H - 1, r.y1 - sy) }
		if q.x0 <= q.x1 and q.y0 <= q.y1 then
			table.insert(kept, q)
		end
	end
	SG.strips = kept
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
					SG.castPx(s, gx, gy, gx, gy, false, shadows, x0, y0, x1, y1)
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

-- Cast the pieces of a scroll's strips (layer rects, inclusive) by the bake's last pass, the anchors of all of them
-- first: then every pixel of the layer is cast once the anchors are, so a pixel by a piece's edge may take its face
-- from an anchor past it (SG.castPx), unless a re-cast is still to come somewhere (its pixels may be of a part that has
-- moved since). No shadow edges refined here (SG.finishStrips does them). Returns the rays cast.
function SG.castStrips(s: Surf, pieces: { Rect }): number
	local shadows = tierSpec(tier).shadows
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local whole = invCur == nil and #invQueue == 0
	local before = bakeRays
	for phase = 1, 2 do
		for _, q in pieces do
			local x0, y0 = math.max(0, q.x0), math.max(0, q.y0)
			local x1, y1 = math.min(s.W - 1, q.x1), math.min(s.H - 1, q.y1)
			local ax0, ay0, ax1, ay1 = x0, y0, x1, y1
			if whole then
				ax0, ay0, ax1, ay1 = 0, 0, s.W - 1, s.H - 1
			end
			for y = y0, y1 do
				local gy = y + gy0
				for x = x0, x1 do
					local gx = x + gx0
					if (gx % 2 == 0 and gy % 2 == 0) == (phase == 1) then
						SG.castPx(s, gx, gy, gx, gy, false, shadows, ax0, ay0, ax1, ay1)
					end
				end
			end
		end
	end
	return bakeRays - before
end

-- Cast the last scroll's pieces still to cast (SG.pend) until `deadline`, as SG.castStrips would: the anchors of all
-- of them first, then the rest. True when none is left (SG.pend is nil then).
function SG.pendStep(s: Surf, deadline: number): boolean
	local P = SG.pend
	if P == nil then
		return true
	end
	local shadows = tierSpec(tier).shadows
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local W, H = s.W, s.H
	-- (the anchors a pixel takes its face from may lie anywhere on the layer once every anchor of the pieces is cast,
	-- unless a re-cast is still to come somewhere: SG.castStrips)
	local whole = invCur == nil and #invQueue == 0
	local n = 0
	local pf = stats.perf :: any
	local t0 = SG.clock()
	if not Tuning.PixelCoarseLead and SG.vpLag > Tuning.PixelHoldMaxPx then
		-- (the window that far behind the camera, with no coarse pass: what is left of the strips is cast in full now,
		-- whatever it takes. Every pixel shown is a whole one; the camera lags no further)
		deadline = math.huge
	end
	if Tuning.PixelCoarseLead and P.phase == 1 and not P.c4 and SG.vpLag > Tuning.PixelHoldMaxPx then
		-- (the view this far behind the camera: the strips get one ray a 4x4 block first, each filling its block, shown
		-- as soon as that is done and cast in full after, SG.release; the camera keeps up, the strip at its edge is
		-- coarse for a moment)
		P.phase, P.i, P.started, P.c4 = 0, 1, false, true
		pf.coarse4 = (pf.coarse4 or 0) + 1
	end
	-- (twice that far behind: the coarse pass gets Tuning.PixelCoarseMs this frame at least; four times, all it takes,
	-- so the camera lags no further. The rest waits for the frames after, SG.release)
	local cdl = deadline
	if SG.vpLag > 4 * Tuning.PixelHoldMaxPx then
		cdl = math.huge
	elseif SG.vpLag > 2 * Tuning.PixelHoldMaxPx then
		cdl = math.max(deadline, t0 + Tuning.PixelCoarseMs / 1000)
	end
	while P.phase == 0 do
		local q = P.pieces[P.i]
		if q == nil then
			P.phase, P.i, P.started = 2, 1, false
			pf.pendMs = (pf.pendMs or 0) + (SG.clock() - t0) * 1000
			return false
		end
		local x0, y0 = math.max(0, q.x0), math.max(0, q.y0)
		local x1, y1 = math.min(W - 1, q.x1), math.min(H - 1, q.y1)
		if not P.started then
			P.started, P.x, P.y = true, x0, y0
		end
		while P.y <= y1 do
			while P.x <= x1 do
				local x, y = P.x, P.y
				local kc = SG.clock()
				local r0 = bakeRays
				SG.castPx(s, x + gx0, y + gy0, math.min(x + 3, x1) + gx0, math.min(y + 3, y1) + gy0, false, shadows, 0, 0, W - 1, H - 1)
				pf.coarseN = (pf.coarseN or 0) + 1
				pf.coarseRays = (pf.coarseRays or 0) + (bakeRays - r0)
				pf.coarseMs = (pf.coarseMs or 0) + (SG.clock() - kc) * 1000
				P.x += 4
				n += 1
				if n % 4 == 0 and SG.clock() >= cdl then
					pf.pendMs = (pf.pendMs or 0) + (SG.clock() - t0) * 1000
					return false
				end
			end
			P.x = x0
			P.y += 4
		end
		P.i += 1
		P.started = false
	end
	while P.phase >= 1 and P.phase <= 2 do
		local q = P.pieces[P.i]
		if q == nil then
			P.phase += 1
			P.i, P.started = 1, false
			continue
		end
		local x0, y0 = math.max(0, q.x0), math.max(0, q.y0)
		local x1, y1 = math.min(W - 1, q.x1), math.min(H - 1, q.y1)
		local ax0, ay0, ax1, ay1 = x0, y0, x1, y1
		if whole then
			ax0, ay0, ax1, ay1 = 0, 0, W - 1, H - 1
		end
		if not P.started then
			P.started, P.x, P.y = true, x0, y0
		end
		local want = P.phase == 1
		local y = P.y
		local x = P.x
		while y <= y1 do
			local gy = y + gy0
			while x <= x1 do
				local gx = x + gx0
				if (gx % 2 == 0 and gy % 2 == 0) == want then
					-- (an anchor fills its 2x2 block for now: the strip shows whole, a little coarse, should the view
					-- need it before the rest is cast; SG.release)
					if want then
						SG.castPx(s, gx, gy, math.min(gx + 1, x1 + gx0), math.min(gy + 1, y1 + gy0), false, shadows, ax0, ay0, ax1, ay1)
					else
						SG.castPx(s, gx, gy, gx, gy, false, shadows, ax0, ay0, ax1, ay1)
					end
					n += 1
					if n % 8 == 0 and SG.clock() >= deadline then
						P.x, P.y = x + 1, y
						if P.x > x1 then
							P.x, P.y = x0, y + 1
						end
						SG.pendCalls += n
						pf.pendMs = (pf.pendMs or 0) + (SG.clock() - t0) * 1000
						return false
					end
				end
				x += 1
			end
			x = x0
			y += 1
		end
		P.i += 1
		P.started = false
	end
	SG.pend = nil
	SG.pendCalls += n
	pf.pendMs = (pf.pendMs or 0) + (SG.clock() - t0) * 1000
	return true
end

-- The pixels SG.pendStep still has to cast for the last scroll's strips (its anchors a quarter of each piece, the
-- rest three quarters), 0 with none.
function SG.pendLeft(s: Surf): number
	local P = SG.pend
	if P == nil then
		return 0
	end
	local W, H = s.W, s.H
	local total, before = 0, 0
	for i, q in P.pieces do
		local x0, y0 = math.max(0, q.x0), math.max(0, q.y0)
		local x1, y1 = math.min(W - 1, q.x1), math.min(H - 1, q.y1)
		local area = math.max(0, x1 - x0 + 1) * math.max(0, y1 - y0 + 1)
		total += area
		if i < P.i then
			before += area
		elseif i == P.i and P.started then
			before += math.max(0, P.y - y0) * math.max(0, x1 - x0 + 1)
		end
	end
	if P.phase <= 1 then
		return math.max(0, total - before) / 4 + total * 3 / 4
	end
	return math.max(0, total - before) * 3 / 4
end

-- The last scroll's strips shown as they stand (SG.pend past its anchors: every 2x2 block filled from its anchor), when
-- the view would have to wait for them: their shadow edges, ink and grade done, the screen free to show them; the rest
-- of their pixels go into SG.refine, cast in the frames' spare time after (SG.refineStep), and the strips finished again
-- then. A walk onto ground not cast yet needs more a frame than a frame has to spare in the densest town (the request
-- of 2026-11-22, "ms at all times should not go above 20ms even at the highest stress tests").
function SG.release(s: Surf)
	local P = SG.pend
	if P == nil or P.phase < 2 then
		return
	end
	local W, H = s.W, s.H
	-- (a coarser pass covered every piece: each starts again at its 2x2 anchors; else the pieces past the one going)
	for i = if P.c4 then 1 else P.i, #P.pieces do
		local q = P.pieces[i]
		local r = { x0 = math.max(0, q.x0), y0 = math.max(0, q.y0), x1 = math.min(W - 1, q.x1), y1 = math.min(H - 1, q.y1) }
		if r.x0 <= r.x1 and r.y0 <= r.y1 then
			table.insert(SG.refine, { r = r, x = r.x0, y = r.y0, pass = if P.c4 then 1 else 2 })
		end
	end
	SG.pend = nil
	SG.finCoarse = true
	SG.fin = nil
	local pf = stats.perf :: any
	pf.releases = (pf.releases or 0) + 1
end

-- Cast the rest of the strips shown before they were whole (SG.release) until `deadline`, each finished again once
-- it is cast (its shadow edges, ink and grade, and the frame takes it back). True when none is left.
function SG.refineStep(s: Surf, deadline: number): boolean
	local Q = SG.refine
	if #Q == 0 then
		return true
	end
	local shadows = tierSpec(tier).shadows
	local gx0, gy0 = s.cam.gx, s.cam.gy
	local W, H = s.W, s.H
	local pf = stats.perf :: any
	local t0 = SG.clock()
	local n = 0
	while #Q > 0 do
		local j = Q[1]
		local r = j.r
		local y, x = j.y, j.x
		local p1 = j.pass == 1
		while y <= r.y1 do
			local gy = y + gy0
			while x <= r.x1 do
				local gx = x + gx0
				local anchor = gx % 2 == 0 and gy % 2 == 0
				if anchor == p1 then
					if p1 then
						SG.castPx(s, gx, gy, math.min(gx + 1, r.x1 + gx0), math.min(gy + 1, r.y1 + gy0), false, shadows, r.x0, r.y0, r.x1, r.y1)
					else
						SG.castPx(s, gx, gy, gx, gy, false, shadows, r.x0, r.y0, r.x1, r.y1)
					end
					n += 1
					if n % 8 == 0 and SG.clock() >= deadline then
						j.x, j.y = x + 1, y
						if j.x > r.x1 then
							j.x, j.y = r.x0, y + 1
						end
						pf.refineCastMs = (pf.refineCastMs or 0) + (SG.clock() - t0) * 1000
						return false
					end
				end
				x += 1
			end
			x = r.x0
			y += 1
		end
		if p1 then
			-- (its anchors cast: the rest of its pixels next)
			j.pass, j.x, j.y = 2, r.x0, r.y0
			continue
		end
		-- (cast: finished again, as SG.finishStrips finishes a strip)
		if shadows then
			refineShadows(s, r.x0 - 1, r.y0 - 1, r.x1 + 1, r.y1 + 1)
		end
		SG.reoutline(s, r.x0, r.y0, r.x1, r.y1)
		SG.waterFix(s, r.x0 - 1, r.y0 - 1, r.x1 + 1, r.y1 + 1)
		SG.rect(s, r.x0 - 3, r.y0 - 3, r.x1 + 3, r.y1 + 3)
		table.insert(SG.strips, { x0 = math.max(0, r.x0 - 3), y0 = math.max(0, r.y0 - 3), x1 = math.min(W - 1, r.x1 + 3), y1 = math.min(H - 1, r.y1 + 3) })
		table.remove(Q, 1)
		if SG.clock() >= deadline then
			break
		end
	end
	pf.refineCastMs = (pf.refineCastMs or 0) + (SG.clock() - t0) * 1000
	return #Q == 0
end

-- The pan the screen's window of layer s shows this frame: the camera's (CameraController.drawnPan), but held off the
-- last scroll's strips while they are not finished (SG.pend, SG.unfin: 3 px clear of them, as far as finishing them
-- changes the pixels beside them) and, once let go, catching up with the camera a little faster than it moves rather
-- than in one jump. Worked out once a frame, before a scroll (showWindow takes it).
-- One axis of the window a frame (the report of 2026-11-22: "when moving the player around and the camera follows, it
-- stutters, moving a bit, stopping, then moving again. if its neccessary, can you make it one smooth motion as the
-- player moves instead, even if the camera moves slower instead if theres alot to render?"). `f`: the window's place
-- (art px, with its fraction); `u`: its speed less the camera's last frame (art px a second); `cvp`: the camera's
-- speed last frame; `cam`, `was`: the camera's place now and last frame; `cv`: its speed now (eased over a few frames,
-- SG.viewPan: in whole art px it goes 2 and 3 a frame by turns); `wlo`, `whi`: how far it may go before strips not cast yet (math.huge: none that way);
-- `lo`, `hi`: the layer's own bounds; `allow`: the speed at which it reaches those strips just as they are done
-- (SG.viewPan: what is left of them at the pace they are being cast). On the camera last frame and free to follow
-- it, it stays on it exactly (locked), as before. Otherwise it keeps its own speed or its speed against the camera's,
-- whichever is nearer the camera's now (a turn of the camera's passes through; the camera slowing after the window was
-- held back does not send it backwards), and eases toward the camera's speed plus its own toward the camera, PixelWindowCatch of the gap a second (PixelWindowMinPx at
-- least, never faster than stops on it) reached at PixelWindowAccel a second each second and dropped at
-- PixelWindowBrake; held to `allow` and to what stops short of the strips (PixelWindowBrake): one smooth motion,
-- slower while there is a lot to cast, where it stopped dead short of the strips and then jumped to catch up.
-- Returns the new place, the new `u` and whether it is locked.
function SG.windowAxis(f: number, u: number, cvp: number, cam: number, was: number, cv: number, wlo: number, whi: number, lo: number, hi: number, allow: number, dt: number): (number, number, boolean)
	local brake = Tuning.PixelWindowBrake
	-- (on the camera last frame, or on it now: it stays on it, if it may go there)
	if (math.abs(f - was) < 0.5 or math.abs(f - cam) < 0.5) and math.abs(cv) <= allow and cam >= wlo and cam <= whi and cam >= lo and cam <= hi then
		return cam, 0, true
	end
	-- (its speed against the camera's now: as it was against the camera's, or its own speed kept, the nearer)
	if math.abs(cvp + u - cv) < math.abs(u) then
		u = cvp + u - cv
	end
	local rel = cam - f
	local catch = 0
	if math.abs(rel) >= 0.5 then
		local most = math.sqrt(2 * brake * math.abs(rel))
		catch = math.sign(rel) * math.min(most, math.max(math.abs(rel) * Tuning.PixelWindowCatch, Tuning.PixelWindowMinPx))
	end
	-- (its own speed toward the camera, eased)
	local acc = (if math.abs(catch) < math.abs(u) or catch * u < 0 then brake else Tuning.PixelWindowAccel) * dt
	local nu = u + math.clamp(catch - u, -acc, acc)
	local nv = cv + nu
	-- (held to the strips' pace: no faster than meets them as they are done, slowing at PixelWindowBrake)
	if math.abs(nv) > allow then
		local prev = cv + u
		local want = math.clamp(nv, -allow, allow)
		nv = if math.abs(prev) > math.abs(want) then prev + math.clamp(want - prev, -brake * dt, brake * dt) else want
	end
	-- (never faster than stops short of the strips not cast yet)
	if nv > 0 and whi < math.huge then
		nv = math.min(nv, math.sqrt(2 * brake * math.max(0, whi - f)))
	elseif nv < 0 and wlo > -math.huge then
		nv = math.max(nv, -math.sqrt(2 * brake * math.max(0, f - wlo)))
	end
	local nf = f + nv * dt
	-- (a step that reaches or passes the camera lands on it, locked, where it may be: stepping half a pixel a frame it
	-- went over the half pixel either side of the camera and swung back and forth round it for good; the request of
	-- 2026-11-23, "optimize the game much much more", found it)
	if (cam - nf) * (cam - f) <= 0 or math.abs(cam - nf) < 0.5 then
		if math.abs(cv) <= allow and cam >= wlo and cam <= whi and cam >= lo and cam <= hi then
			return cam, 0, true
		end
	end
	local top, bottom = math.min(hi, whi), math.max(lo, wlo)
	if nf > top then
		nf, nv = top, math.min(nv, 0)
	elseif nf < bottom then
		nf, nv = bottom, math.max(nv, 0)
	end
	return nf, nv - cv, false
end

function SG.viewPan(s: Surf): (number, number)
	local rx, ry = CameraController.drawnPan()
	-- (a jump, to another island or home: the camera's pan half the layer or more from the picture, scrollToward's own
	-- rule. The window goes straight there, unclamped, so the scroll re-bakes at the new pan: held to the old picture
	-- it caught up a share a frame and the layer scrolled after it across the sky, about 1,500 px over a second; the
	-- request of 2026-11-22, "make the camera snap to the player instead of the camera having to travel all the way")
	if s.m > 0 and (math.abs(rx - s.m - s.cam.gx) >= s.W // 2 or math.abs(ry - s.m - s.cam.gy) >= s.H // 2) then
		SG.vpRawX, SG.vpRawY = rx, ry
		SG.vpX, SG.vpY, SG.vpAt, SG.vpView = rx, ry, -1, s.view
		SG.vpFX, SG.vpFY, SG.vpVX, SG.vpVY = rx, ry, 0, 0
		SG.vpLag, SG.vpBlocked, SG.vpJump = 0, false, true
		return rx, ry
	end
	SG.vpJump = false
	local dt = SG.dt
	local fresh = not (SG.vpView == s.view and SG.vpAt >= 0 and SG.vpRawX ~= nil and SG.vpRawY ~= nil)
	local wasX = if fresh then rx else SG.vpRawX :: number
	local wasY = if fresh then ry else SG.vpRawY :: number
	SG.vpRawX, SG.vpRawY = rx, ry
	-- (the camera's speed, eased: Tuning.PixelWindowCamEase of each frame's step)
	local cpx, cpy = SG.vpCX, SG.vpCY
	local k = Tuning.PixelWindowCamEase
	local cvx = if fresh then 0 else cpx + ((rx - wasX) / dt - cpx) * k
	local cvy = if fresh then 0 else cpy + ((ry - wasY) / dt - cpy) * k
	SG.vpCX, SG.vpCY = cvx, cvy
	local px, py = rx, ry
	if s.m > 3 then
		local gx, gy, W, H, vw, vh = s.cam.gx, s.cam.gy, s.W, s.H, s.vw, s.vh
		-- how far the window may go: never the layer's outer 3 px, which the next scroll's strips would change (a
		-- scroll's strips then never come in that close to the window, however far it moves), and 3 px clear of the
		-- strips not finished yet
		local loX, hiX = gx + 3, gx + W - vw - 3
		local loY, hiY = gy + 3, gy + H - vh - 3
		-- (the strips not finished yet: walls the window eases off before)
		local wloX, whiX, wloY, whiY = -math.huge, math.huge, -math.huge, math.huge
		local strips: { Rect } = SG.unfin or {}
		for _, r in strips do
			if r.x1 - r.x0 < r.y1 - r.y0 then
				-- (a strip down the layer's side)
				if r.x0 > W // 2 then
					whiX = math.min(whiX, gx + r.x0 - 3 - vw)
				else
					wloX = math.max(wloX, gx + r.x1 + 4)
				end
			else
				if r.y0 > H // 2 then
					whiY = math.min(whiY, gy + r.y0 - 3 - vh)
				else
					wloY = math.max(wloY, gy + r.y1 + 4)
				end
			end
		end
		if fresh or SG.vpFX == nil or SG.vpFY == nil then
			-- (a new view: the window starts on the camera, within the layer)
			SG.vpFX, SG.vpFY = math.clamp(rx, loX, hiX), math.clamp(ry, loY, hiY)
			SG.vpVX, SG.vpVY = 0, 0
		end
		-- (the speed at which the window meets the strips not cast yet just as they are done: the distance to them over
		-- the frames what is left of them takes at the pace they are being cast, and a frame to finish them; none to
		-- wait for, any speed)
		local allowX, allowY = math.huge, math.huge
		if SG.unfin then
			local frames = 1 + SG.pendLeft(s) / math.max(SG.pendRate, 1)
			local secs = frames * dt
			local fx0, fy0 = SG.vpFX :: number, SG.vpFY :: number
			if cvx > 0 and whiX < math.huge then
				allowX = math.max(0, whiX - fx0) / secs
			elseif cvx < 0 and wloX > -math.huge then
				allowX = math.max(0, fx0 - wloX) / secs
			end
			if cvy > 0 and whiY < math.huge then
				allowY = math.max(0, whiY - fy0) / secs
			elseif cvy < 0 and wloY > -math.huge then
				allowY = math.max(0, fy0 - wloY) / secs
			end
		end
		local fx, vx, lockX = SG.windowAxis(SG.vpFX :: number, SG.vpVX, cpx, rx, wasX, cvx, wloX, whiX, loX, hiX, allowX, dt)
		local fy, vy, lockY = SG.windowAxis(SG.vpFY :: number, SG.vpVY, cpy, ry, wasY, cvy, wloY, whiY, loY, hiY, allowY, dt)
		SG.vpFX, SG.vpFY, SG.vpVX, SG.vpVY = fx, fy, vx, vy
		-- (in whole art px, never past the layer nor into a strip not finished)
		local topX, botX = math.min(hiX, whiX), math.max(loX, wloX)
		local topY, botY = math.min(hiY, whiY), math.max(loY, wloY)
		px = if lockX then rx else math.floor(fx + 0.5)
		py = if lockY then ry else math.floor(fy + 0.5)
		px = math.clamp(px, math.min(botX, topX), math.max(botX, topX))
		py = math.clamp(py, math.min(botY, topY), math.max(botY, topY))
		px = math.clamp(px, gx, gx + W - vw)
		py = math.clamp(py, gy, gy + H - vh)
		-- (whether the strips hold it this frame: SG.release lets them be shown)
		SG.vpBlocked = not (lockX and lockY)
	else
		SG.vpFX, SG.vpFY, SG.vpVX, SG.vpVY = rx, ry, 0, 0
	end
	if px ~= rx or py ~= ry then
		local pf = stats.perf :: any
		pf.heldFrames = (pf.heldFrames or 0) + 1
		pf.heldPx = math.max(pf.heldPx or 0, math.abs(px - rx), math.abs(py - ry))
	end
	SG.vpX, SG.vpY, SG.vpAt, SG.vpView = px, py, SG.frameNo, s.view
	SG.vpLag = math.max(math.abs(px - rx), math.abs(py - ry))
	if SG.vpBlocked and (SG.pend or SG.unfin) then
		-- (behind the camera, or easing off before ground not cast yet: the strips get more of the frame the further
		-- behind it is, Tuning.PixelLagMs at PixelHoldMaxPx, so the window keeps moving rather than one long frame
		-- catching it up)
		SG.castEnd += Tuning.PixelLagMs * math.clamp((SG.vpLag + 4) / Tuning.PixelHoldMaxPx, 0, 1) / 1000
	end
	if SG.vpLag > Tuning.PixelHoldMaxPx then
		local pf = stats.perf :: any
		pf.lagFrames = (pf.lagFrames or 0) + 1
		if SG.vpLag > 4 * Tuning.PixelHoldMaxPx then
			pf.lagFar = (pf.lagFar or 0) + 1
		end
	end
	return px, py
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
	-- (a strip shown before it was whole: SG.release; kept out of the pan cache till it is)
	local s = surf
	if s and #SG.refine > 0 then
		local gx, gy = s.cam.gx, s.cam.gy
		for _, j in SG.refine do
			local q = j.r
			if not (q.x1 + gx < x0 or q.x0 + gx > x1 or q.y1 + gy < y0 or q.y0 + gy > y1) then
				return true
			end
		end
	end
	return false
end

-- The ink and the contact shade over a layer rect and one pixel round it.
local function reoutline(s: Surf, x0: number, y0: number, x1: number, y1: number)
	Shading.outline(s.static, x0 - 1, y0 - 1, x1 + 1, y1 + 1, s.sShade)
	contactPass(s, x0 - 1, y0 - 1, x1 + 1, y1 + 1)
end
SG.reoutline = reoutline

-- The last scroll's strips (SG.unfin, layer rects) finished: their shadow edges on the pixel grid, the ink and contact
-- shade over them and the old picture's pixels beside them, the water's frames and the grade; then queued for the
-- next compose, which draws them and sends them up (`now`: the scroll's own frame, which queues them itself).
function SG.finishStrips(s: Surf, now: boolean?)
	if SG.unfin and SG.pend then
		-- (their pieces still to cast, all of them now: a whole compose, a jump, a check)
		SG.pendStep(s, math.huge)
	end
	SG.finishStep(s, math.huge, now)
end

-- SG.finishStrips a band of rows at a time (FIN_ROWS) until `deadline`: the shadow edges of every strip first (not
-- for strips shown from their anchors' blocks, SG.release: their rest is cast later and finished then), then the ink
-- and the water's edges, then the grade, as one pass over all of them did. True when they are finished (SG.unfin
-- nil). The request of 2026-11-22, "ms at all times should not go above 20ms even at the highest stress tests".
function SG.finishStep(s: Surf, deadline: number, now: boolean?): boolean
	local F = SG.fin
	if F == nil or F.list ~= SG.unfin then
		local list = SG.unfin
		if list == nil then
			SG.fin = nil
			return true
		end
		F = { list = list, phase = if tierSpec(tier).shadows and not SG.finCoarse then 1 else 2, i = 1, y = nil }
		SG.fin = F
	end
	local f = F :: { list: { Rect }, phase: number, i: number, y: number? }
	local list = f.list
	local pf = stats.perf :: any
	local t0 = SG.clock()
	while f.phase <= 3 do
		local r = list[f.i]
		if r == nil then
			f.phase += 1
			f.i, f.y = 1, nil
			continue
		end
		-- (the rows each phase covers: the shadow edges and the ink a pixel round, the grade three)
		local pad = if f.phase == 3 then 3 else 1
		local ya, yb = r.y0 - pad, r.y1 + pad
		local y = f.y or ya
		local ye = math.min(yb, y + FIN_ROWS - 1)
		local p0 = SG.clock()
		if f.phase == 1 then
			refineShadows(s, r.x0 - 1, y, r.x1 + 1, ye)
			pf.refineMs = (pf.refineMs or 0) + (SG.clock() - p0) * 1000
		elseif f.phase == 2 then
			reoutline(s, r.x0, math.max(y, r.y0), r.x1, math.min(ye, r.y1))
			SG.waterFix(s, r.x0 - 1, y, r.x1 + 1, ye)
			pf.inkMs += (SG.clock() - p0) * 1000
		else
			SG.rect(s, r.x0 - 3, y, r.x1 + 3, ye)
			pf.rectMs = (pf.rectMs or 0) + (SG.clock() - p0) * 1000
		end
		if ye >= yb then
			f.i += 1
			f.y = nil
		else
			f.y = ye + 1
		end
		if SG.clock() >= deadline and f.phase <= 3 and not (f.phase == 3 and list[f.i] == nil) then
			if not now then
				pf.lateMs = (pf.lateMs or 0) + (SG.clock() - t0) * 1000
			end
			return false
		end
	end
	SG.fin = nil
	SG.finCoarse = false
	SG.unfin = nil
	SG.waterRowsVer = -1 -- (the strips' rows may hold water now: SG.waterSlice looks at every row again)
	if not now then
		pf.lateMs = (pf.lateMs or 0) + (SG.clock() - t0) * 1000
		local W, H = s.W, s.H
		for _, r in list do
			table.insert(SG.strips, { x0 = math.max(0, r.x0 - 3), y0 = math.max(0, r.y0 - 3), x1 = math.min(W - 1, r.x1 + 3), y1 = math.min(H - 1, r.y1 + 3) })
		end
		-- (the static picture's version is the scroll's: what the effects read from it then is still good, but for
		-- sColor in the strips, which they left alone till now: Fx.Ctx.wait)
	end
	return true
end

-- Whether a strip of the last scroll (SG.unfin) or the old pixels beside it fall in the screen's window of layer s.
function SG.unfinSeen(s: Surf): boolean
	local list = SG.unfin
	if list == nil then
		return false
	end
	local x0, y0, x1, y1 = s.ox, s.oy, s.ox + s.vw - 1, s.oy + s.vh - 1
	for _, r in list do
		if r.x0 - 1 <= x1 and r.x1 + 1 >= x0 and r.y0 - 1 <= y1 and r.y1 + 1 >= y0 then
			return true
		end
	end
	return false
end

-- Keep the margin of layer s on the side the view moves away from (SG.ahead's way) in the pan cache, once a scroll.
function SG.preSave(s: Surf)
	if SG.preSaved == stats.scrolls or not SG.tilesOk(s) then
		return
	end
	local A = SG.ahead
	if A.dx == 0 and A.dy == 0 then
		return
	end
	SG.preSaved = stats.scrolls
	local t0 = SG.clock()
	local W, H, m = s.W, s.H, s.m
	local gx, gy = s.cam.gx, s.cam.gy
	local bands: { { number } } = {}
	if A.dx > 0 then
		table.insert(bands, { 0, 0, m - 1, H - 1 })
	elseif A.dx < 0 then
		table.insert(bands, { W - m, 0, W - 1, H - 1 })
	end
	if A.dy > 0 then
		table.insert(bands, { 0, 0, W - 1, m - 1 })
	elseif A.dy < 0 then
		table.insert(bands, { 0, H - m, W - 1, H - 1 })
	end
	for _, b in bands do
		if not SG.pendingOver(gx + b[1], gy + b[2], gx + b[3], gy + b[4]) then
			SG.Tiles.save(s, gx, gy, b[1], b[2], b[3], b[4])
		end
	end
	local pf = stats.perf :: any
	pf.preSaveMs = (pf.preSaveMs or 0) + (SG.clock() - t0) * 1000
end

-- Whether the pan cache holds every pixel of the strips a scroll of layer s by (dx, dy) would bring in.
function SG.stripsHeld(s: Surf, dx: number, dy: number): boolean
	local gx, gy, W, H = s.cam.gx, s.cam.gy, s.W, s.H
	local nx, ny = gx + dx, gy + dy
	local T = SG.Tiles
	if dx > 0 and not T.okRect(gx + W, ny, gx + W + dx - 1, ny + H - 1) then
		return false
	elseif dx < 0 and not T.okRect(nx, ny, gx - 1, ny + H - 1) then
		return false
	end
	if dy > 0 and not T.okRect(nx, gy + H, nx + W - 1, gy + H + dy - 1) then
		return false
	elseif dy < 0 and not T.okRect(nx, ny, nx + W - 1, gy - 1) then
		return false
	end
	return true
end

-- Scroll the layer toward the pan (tx, ty): by whole art px, the uncovered strips cast, within the frame's ray budget.
local function scrollToward(s: Surf, tx: number, ty: number)
	local cam = s.cam
	local dx, dy = tx - cam.gx, ty - cam.gy
	if dx == 0 and dy == 0 then
		return
	end
	-- (the last scroll's strips are finished before the picture moves again: SG.finishStrips)
	if SG.unfin then
		SG.finishStrips(s)
	end
	windRestore(s)
	SG.windVoid = true -- (the wind's frame being worked out is of the old pan: it waits for the view to stand)
	table.clear(SG.windPend)
	local W, H = s.W, s.H
	local v = s.view
	if math.abs(dx) >= W // 2 or math.abs(dy) >= H // 2 then
		-- a jump (the view sent home from the far end of the street): bake again at the new pan
		if s.m > 0 then
			tx -= tx % 2
			ty -= ty % 2
		end
		s.cam = layerCam(v, tx, ty, s.K)
		s.ready = false -- (the picture on screen is of another place: no point keeping it alive)
		startBake()
		return
	end
	-- (composing incrementally with a margin: the strips' pieces the pan cache does not hold are cast over the next
	-- frames, SG.pendStep, the view held off them till then, SG.viewPan)
	local defer = not needFull and SG.live(s) and Tuning.PixelPanLate and s.m > 0 and not v.stage
	-- the step this frame: the strips' rays within the budget (a strip pixel costs about 1.5 rays with its sun ray)
	local budget = Tuning.PixelPanRays
	local mx = math.max(1, math.floor(budget / (H * 1.5)))
	local my = math.max(1, math.floor(budget / (W * 1.5)))
	local sx, sy = math.clamp(dx, -mx, mx), math.clamp(dy, -my, my)
	if defer then
		sx, sy = dx, dy
	elseif (sx ~= dx or sy ~= dy) and SG.tilesOk(s) and SG.stripsHeld(s, dx, dy) then
		-- (strips the pan cache holds whole are copied in, not cast: the whole step at once, the view put back in the
		-- middle of its margin, so the next scroll comes no sooner than it must)
		sx, sy = dx, dy
	end
	if s.m > 0 then
		-- (by whole 2x2 blocks: the pan stays even, SG.pendStep)
		if sx % 2 ~= 0 then
			sx += if sx > 0 then 1 else -1
		end
		if sy % 2 ~= 0 then
			sy += if sy > 0 then 1 else -1
		end
	end
	-- (composing incrementally: the sticky pixels come off the frame before it shifts, as they are dropped below)
	local inc = not needFull and SG.live(s)
	if inc then
		SG.unstickFrame(s)
	end
	-- the strips about to scroll off are kept in the pan cache (a pan back over them copies them in again), all but
	-- what a re-cast still has to redo
	local cacheOn = SG.tilesOk(s)
	local pf = stats.perf
	local q0 = SG.clock()
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
	local q1 = SG.clock()
	pf.saveMs = (pf.saveMs or 0) + (q1 - q0) * 1000
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
	-- (strips shown before they were whole move with the picture, what is left of them on it: SG.refineStep)
	if #SG.refine > 0 then
		local kept = {}
		for _, j in SG.refine do
			local r = j.r
			local q = { x0 = math.max(0, r.x0 - sx), y0 = math.max(0, r.y0 - sy), x1 = math.min(W - 1, r.x1 - sx), y1 = math.min(H - 1, r.y1 - sy) }
			if q.x0 <= q.x1 and q.y0 <= q.y1 then
				local jy, jx = math.max(q.y0, j.y - sy), j.x - sx
				if jy ~= j.y - sy or jx < q.x0 or jx > q.x1 then
					jx = q.x0 -- (cut by the layer's edge: the row it had got to, from its start)
				end
				table.insert(kept, { r = q, x = jx, y = jy, pass = j.pass })
			end
		end
		SG.refine = kept
	end
	pf.shiftMs = (pf.shiftMs or 0) + (SG.clock() - q1) * 1000
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
	local pieces: { Rect } = {}
	for _, r in strips do
		if cacheOn then
			-- (a piece of the strip the cache holds whole is copied in; the rest is cast)
			local gx1, gy1 = s.cam.gx, s.cam.gy
			for _, q in SG.Tiles.split(gx1, gy1, r.x0, r.y0, r.x1, r.y1) do
				if not SG.Tiles.load(s, gx1, gy1, q.x0, q.y0, q.x1, q.y1) then
					table.insert(pieces, q)
				end
			end
		else
			table.insert(pieces, r)
		end
	end
	-- the strips' shadow edges, ink, contact shade and grade: on a later frame while the strips lie in the margin past
	-- the screen's edge (SG.finishStrips; a scroll frame did all of a strip's work at once, three times a frame's
	-- spare time), else now
	local late = inc and not needFull and SG.live(s) and Tuning.PixelPanLate
	SG.unfin = strips
	SG.unfinAt = SG.frameNo

	if defer and late and #pieces > 0 then
		-- (the request of 2026-11-22, "ms at all times should not go above 20ms even at the highest stress tests": a
		-- scroll onto ground the look-ahead had not cast took 170 to 230 ms in one frame of the stress walk)
		SG.pend = { pieces = pieces, phase = 1, i = 1, x = 0, y = 0, started = false }
		do
			local pfp = stats.perf :: any
			pfp.pendPieces = (pfp.pendPieces or 0) + #pieces
			for _, q in pieces do
				pfp.pendPx = (pfp.pendPx or 0) + (q.x1 - q.x0 + 1) * (q.y1 - q.y0 + 1)
			end
		end
		SG.pendStep(s, SG.castEnd)
	else
		rays += SG.castStrips(s, pieces)
	end
	local c1 = SG.clock()
	stats.perf.castMs += (c1 - c0) * 1000
	if not late then
		SG.finishStrips(s, true)
	end
	local q2 = SG.clock()
	if inc and not needFull and SG.live(s) then
		SG.panShift(s, sx, sy, if late then {} else strips)
	else
		needFull = true
	end
	pf.panShiftMs = (pf.panShiftMs or 0) + (SG.clock() - q2) * 1000
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
		-- (the rect on the layer: the anchors a pixel may take its face from)
		local lx0, ly0 = math.max(0, r.x0 - gx0), math.max(0, r.y0 - gy0)
		local lx1, ly1 = math.min(s.W - 1, r.x1 - gx0), math.min(s.H - 1, r.y1 - gy0)
		local n = 0
		while c.phase <= 2 and bakeRays - start < budget do
			n += 1
			if n % 32 == 0 and SG.clock() >= deadline then
				break
			end
			local gx, gy = c.gx, c.gy
			local x, y = gx - gx0, gy - gy0
			if x >= 0 and y >= 0 and x < s.W and y < s.H and ((gx % 2 == 0 and gy % 2 == 0) == (c.phase == 1)) then
				SG.castPx(s, gx, gy, gx, gy, false, shadows, lx0, ly0, lx1, ly1)
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
function PC.step(s: Surf, deadline: number): boolean
	-- (a swap that has landed lets go once its parts have come and gone: the next island's job can start. Kept, it
	-- cast nothing ahead for the next expansion and went on calling the swapped models' later changes its own: the
	-- report of 2026-11-20, "there are artifacts that appear around after expanding")
	if PC.job and PC.job.switched and os.clock() >= PC.job.untilT then
		preReset()
	end
	if PC.job == nil then
		if not PC.dirty and os.clock() - PC.tried < 1 then
			return false
		end
		PC.tried = os.clock()
		if not PC.start(s) then
			return false
		end
	end
	local job = PC.job
	if job == nil or job.switched then
		return false
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
			return false
		end
	end
	local shadows = tierSpec(tier).shadows
	local ps = job.ps
	local saved = params
	params = job.params
	-- (the next tier's world, not the one on the maps: every pixel and its sun by its own rays, SG.sunAt)
	local nsh = SG.noShare
	SG.noShare = true
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
	SG.noShare = nsh
	params = saved
	PC.stats.rays += bakeRays - r0
	return true
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

------------------------------------------------------------------ look-ahead
-- While the view moves, the pan cache's tiles just past the layer's leading edge (Tuning.PixelAheadPx), nearest first,
-- are cast a few ms a frame on a small layer of their own (as the pre-cast casts the next tier's) and kept, so the
-- strip a scroll uncovers is copied in from the cache instead of all cast in the one frame (the user's question of
-- 2026-11-21, "what is the most performance intensive thing the camera needs when scrolling?": that cast, 29 ms in
-- one frame of every four walking over new ground in the simulator, the frames the view stuttered on). A tile whose
-- ground changes while it is cast (the cache's epoch moved) is not kept.
SG.ahead = {
	ps = nil :: any,
	view = nil :: any,
	-- (the piece being cast: its tile, phase and pixel, the cache's epoch when it began, the rect cast on the small
	-- layer (the piece and PAD px round it, for the shadows' edges) and the rect kept)
	cur = nil :: { tx: number, ty: number, phase: number, x: number, y: number, epoch: number, cx0: number, cy0: number, cx1: number, cy1: number, kx0: number, ky0: number, kx1: number, ky1: number, g1: number, g2: number, g3: number, g4: number, ring: boolean, sky: boolean? }?,
	lx = nil :: number?,
	ly = nil :: number?,
	dx = 0,
	dy = 0,
	at = -math.huge,
	stats = { tiles = 0, dropped = 0, rays = 0 },
}

-- The next piece to cast ahead: its tile (tx, ty) and the global art px rect of it outside the layer that the cache does
-- not hold yet, nearest the layer's edge and the middle of its side first; nil: none. Moving (dx, dy not both 0): on the
-- sides the view moves toward, Tuning.PixelAheadPx deep. Standing: all round the layer, corners too,
-- Tuning.PixelRingPx deep (the walk that comes next starts on ground cast while the founder stood).
function SG.aheadNext(s: Surf, dx: number, dy: number): (number?, number?, { number }?)
	local T = SG.Tiles.TILE
	local gx, gy, W, H = s.cam.gx, s.cam.gy, s.W, s.H
	local ring = dx == 0 and dy == 0
	local far = if ring then Tuning.PixelRingPx else Tuning.PixelAheadPx
	local midX, midY = (gx + W / 2) / T, (gy + H / 2) / T
	local best, bx, by, br = math.huge, nil, nil, nil
	-- (the tiles of a band outside the layer, each clipped to it)
	local function band(x0: number, y0: number, x1: number, y1: number)
		for tx = x0 // T, x1 // T do
			for ty = y0 // T, y1 // T do
				local r = { math.max(tx * T, x0), math.max(ty * T, y0), math.min(tx * T + T - 1, x1), math.min(ty * T + T - 1, y1) }
				if r[1] > r[3] or r[2] > r[4] then
					continue
				end
				-- (how far its nearest pixel lies past the layer's edge, then how far from the middle of its side)
				local ox = if r[3] < gx then gx - r[3] elseif r[1] > gx + W - 1 then r[1] - (gx + W - 1) else 0
				local oy = if r[4] < gy then gy - r[4] elseif r[2] > gy + H - 1 then r[2] - (gy + H - 1) else 0
				local side = if ox >= oy then math.abs(ty + 0.5 - midY) else math.abs(tx + 0.5 - midX)
				local d = math.max(ox, oy) * 4 + side
				if d < best and not SG.Tiles.okRect(r[1], r[2], r[3], r[4]) then
					best, bx, by, br = d, tx, ty, r
				end
			end
		end
	end
	local cy0, cy1 = if ring then gy - far else gy, if ring then gy + H + far - 1 else gy + H - 1
	if ring or dx > 0 then
		band(gx + W, cy0, gx + W + far - 1, cy1)
	end
	if ring or dx < 0 then
		band(gx - far, cy0, gx - 1, cy1)
	end
	if ring or dy > 0 then
		band(gx, gy + H, gx + W - 1, gy + H + far - 1)
	end
	if ring or dy < 0 then
		band(gx, gy - far, gx + W - 1, gy - 1)
	end
	return bx, by, br
end

-- The look-ahead's small layer (a tile and PC.PAD px round it), made again for a new view.
function SG.aheadLayer(s: Surf)
	local A = SG.ahead
	if A.view ~= s.view or A.ps == nil then
		local n = PC.SIDE * PC.SIDE
		A.ps = {
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
		A.view, A.cur = s.view, nil
	end
end

-- Cast ahead until `deadline`; true when there was something to do (the pre-cast then waits). `ring`: standing too, the
-- tiles all round the layer (SG.aheadNext).
function SG.aheadStep(s: Surf, deadline: number, ring: boolean?): boolean
	local A = SG.ahead
	local t0 = SG.clock()
	if not SG.tilesOk(s) then
		return false
	end
	-- the way the view is going: the drawn pan's last move, held half a second
	local tx, ty = CameraController.drawnPan()
	local now = os.clock()
	if A.lx ~= nil and A.ly ~= nil then
		local mx, my = tx - A.lx, ty - A.ly
		if mx ~= 0 or my ~= 0 then
			A.dx, A.dy, A.at = math.sign(mx), math.sign(my), now
		end
	end
	A.lx, A.ly = tx, ty
	if now - A.at > 0.5 then
		A.dx, A.dy = 0, 0
	end
	SG.aheadLayer(s)
	-- (a tile the next scroll or two will want, Tuning.PixelAheadNearPx from the layer's edge, gets the frame's larger
	-- budget: on ground not seen yet a walk needs more cast a frame than the plain budget gives)
	local slow = deadline
	local fast = math.min(SG.castEnd, math.max(deadline, t0 + Tuning.PixelAheadNearMs / 1000))
	local did = false
	-- (a ring's tile half cast is the ring's to finish on its own turn; once the view moves, a tile ahead comes first)
	local held = A.cur
	if not ring and held and held.ring then
		if A.dx == 0 and A.dy == 0 then
			return false
		end
		A.cur = nil
	end
	while true do
		if A.cur == nil and not SG.aheadPick(s, ring) then
			break
		end
		local cc = A.cur :: any
		local gx, gy = s.cam.gx, s.cam.gy
		local ox = if cc.g3 < gx then gx - cc.g3 elseif cc.g1 > gx + s.W - 1 then cc.g1 - (gx + s.W - 1) else 0
		local oy = if cc.g4 < gy then gy - cc.g4 elseif cc.g2 > gy + s.H - 1 then cc.g2 - (gy + s.H - 1) else 0
		local dl = if not ring and math.max(ox, oy) < Tuning.PixelAheadNearPx then fast else slow
		if SG.clock() >= dl then
			break
		end
		SG.aheadPiece(s, dl)
		did = true
	end
	return did
end

-- Pick the look-ahead's next tile (SG.aheadNext); false when there is none to cast.
function SG.aheadPick(s: Surf, ring: boolean?): boolean
	local A = SG.ahead
	if not ring and A.dx == 0 and A.dy == 0 then
		return false
	end
	local ntx, nty, nr = SG.aheadNext(s, if ring then 0 else A.dx, if ring then 0 else A.dy)
	if ntx == nil or nty == nil or nr == nil then
		return false
	end
	SG.aheadSet(s, ntx, nty, nr, ring == true)
	return true
end

-- The look-ahead's tile (tx, ty) to cast next: `nr` the global art px rect of it to keep (the island's whole cast,
-- SG.isleStep, sets one too). `ring`: let go once the view moves.
function SG.aheadSet(s: Surf, ntx: number, nty: number, nr: { number }, ring: boolean)
	local A = SG.ahead
	local ox, oy = ntx * PC.TILE - PC.PAD, nty * PC.TILE - PC.PAD
	A.ps.cam = Raster.gridCam(s.view.rot12, CameraController.gridAt(ox, oy), PC.SIDE, PC.SIDE, s.K, Tuning.CamRayBack)
	local kx0, ky0, kx1, ky1 = nr[1] - ox, nr[2] - oy, nr[3] - ox, nr[4] - oy
	local cx0, cy0 = math.max(0, kx0 - PC.PAD), math.max(0, ky0 - PC.PAD)
	A.cur = { tx = ntx, ty = nty, phase = 1, x = cx0, y = cy0, epoch = SG.Tiles.epoch(), cx0 = cx0, cy0 = cy0, cx1 = math.min(PC.SIDE - 1, kx1 + PC.PAD), cy1 = math.min(PC.SIDE - 1, ky1 + PC.PAD), kx0 = kx0, ky0 = ky0, kx1 = kx1, ky1 = ky1, g1 = nr[1], g2 = nr[2], g3 = nr[3], g4 = nr[4], ring = ring }
end

-- The look-ahead's tile going (SG.aheadPick) cast until `deadline` or done.
function SG.aheadPiece(s: Surf, deadline: number): boolean
	local A = SG.ahead
	local ps = A.ps
	local cc = A.cur :: { tx: number, ty: number, phase: number, x: number, y: number, epoch: number, cx0: number, cy0: number, cx1: number, cy1: number, kx0: number, ky0: number, kx1: number, ky1: number, g1: number, g2: number, g3: number, g4: number, ring: boolean, sky: boolean? }
	local shadows = tierSpec(tier).shadows
	local gx0, gy0 = ps.cam.gx, ps.cam.gy
	local r0 = bakeRays
	local n = 0
	-- (first, the tile's runs of sky, filled a row at a time and marked so the passes below leave them: the request of
	-- 2026-11-23, "a deeper rework of the renderer". Only a see-through sky, whose every pixel is the same)
	local skyMask = SG.aheadSkyMask
	if cc.phase == 1 and cc.sky == nil then
		cc.sky = false
		if ps.view.clear and not SG.noShare and not ps.view.stage then
			local W = ps.W
			if skyMask == nil or buffer.len(skyMask) < W * ps.H then
				skyMask = buffer.create(W * ps.H)
				SG.aheadSkyMask = skyMask
			end
			local mk = skyMask :: buffer
			local runs = 0
			for y = cc.cy0, cc.cy1 do
				buffer.fill(mk, y * W + cc.cx0, 0, cc.cx1 - cc.cx0 + 1)
				local x = cc.cx0
				while x <= cc.cx1 do
					local e = SG.Map.skyTo(x + gx0, y + gy0, cc.cx1 + gx0) - gx0
					if e >= x then
						SG.skyRow(ps, y, x, e)
						buffer.fill(mk, y * W + x, 1, e - x + 1)
						runs += 1
						x = e + 1
					else
						x += 1
					end
				end
			end
			cc.sky = runs > 0
		end
	end
	local useMask = cc.sky == true
	local mk = skyMask
	while cc.phase <= 2 do
		n += 1
		if n % 24 == 0 and SG.clock() >= deadline then
			break
		end
		local gx, gy = cc.x + gx0, cc.y + gy0
		if (gx % 2 == 0 and gy % 2 == 0) == (cc.phase == 1) and not (useMask and buffer.readu8(mk :: buffer, cc.y * ps.W + cc.x) == 1) then
			SG.castPx(ps, gx, gy, gx, gy, false, shadows, cc.cx0, cc.cy0, cc.cx1, cc.cy1)
		end
		cc.x += 1
		if cc.x > cc.cx1 then
			cc.x = cc.cx0
			cc.y += 1
			if cc.y > cc.cy1 then
				cc.y = cc.cy0
				cc.phase += 1
			end
		end
	end
	A.stats.rays += bakeRays - r0
	if cc.phase == 3 then
		A.cur = nil
		if SG.Tiles.epoch() ~= cc.epoch then
			-- (the ground under it changed while it was cast: it is cast again later if it is still wanted)
			A.stats.dropped += 1
			return true
		end
		if shadows then
			refineShadows(ps, cc.cx0, cc.cy0, cc.cx1, cc.cy1)
		end
		-- (a sky drawn by the layer's height, not see-through, is not kept: as the pre-cast)
		local keep = true
		if not s.view.clear then
			for y = cc.ky0, cc.ky1 do
				for x = cc.kx0, cc.kx1 do
					if buffer.readu16(ps.sId, (y * PC.SIDE + x) * 2) == 0 then
						keep = false
						break
					end
				end
			end
		end
		if keep then
			SG.Tiles.save(ps, gx0, gy0, cc.kx0, cc.ky0, cc.kx1, cc.ky1)
			A.stats.tiles += 1
		end
	end
	return true
end

------------------------------------------------------------------ the whole island, cast ahead
-- The request of 2026-11-22: "could the whole player island be prerendered during the loading scene, such that walking
-- around unrendered areas wont need to lag so much?". Every pan cache tile the island under the founder covers (its
-- parts' boxes on the grid: open sky is no tile) is cast on the look-ahead's small layer and kept, nearest the view
-- first: behind the loading card with the hidden budget (PixelRenderer.prerender says how far it has come; the cards
-- wait on it, Tuning.PixelIsleWaitSecs at most), then in the frame's spare time once nothing else has work
-- (Tuning.PixelIsleMs). A walk anywhere on the island then copies its strips from the cache instead of casting them.
SG.isle = {
	key = "", -- (the island and the view its list is for)
	plot = 0,
	tx = {} :: { number },
	ty = {} :: { number },
	set = {} :: { [number]: boolean }, -- (the tiles listed, by SG.isleKey)
	n = 0,
	idx = 1, -- (the first tile in the list the cache may not hold yet)
	epoch = -1, -- (the cache's epoch when the list was last read from its start)
	ready = false,
	parts = nil :: { Instance }?, -- (the island's instances still to look at while the list is made)
	pi = 1,
	lin = nil :: { number }?, -- (the grid's slopes: art px a stud along x, y and z, across then down)
	full = false, -- (the cache held all it may)
	stats = { tiles = 0, listed = 0, buildMs = 0, castMs = 0 },
}

function SG.isleKey(tx: number, ty: number): number
	return (tx + 32768) * 65536 + (ty + 32768)
end

-- The island the founder stands on (the view's own when they stand on none).
function SG.islePlot(): number
	local at = CameraController.founderAt()
	local p = if at then Street.plotAt(at.X, at.Z) else 0
	return if p ~= 0 then p else CameraController.view().plot
end

-- A tile (tx, ty) onto the list, once.
function SG.isleTile(tx: number, ty: number)
	local I = SG.isle
	local k = SG.isleKey(tx, ty)
	if not I.set[k] then
		I.set[k] = true
		I.n += 1
		I.tx[I.n], I.ty[I.n] = tx, ty
	end
end

-- A part that came onto the island: the tiles of its rect (and its shadow's) that the list lacks go on it, last.
function SG.isleAdd(r: Rect)
	local I = SG.isle
	if not I.ready then
		return
	end
	local T = SG.Tiles.TILE
	for tx = r.x0 // T, r.x1 // T do
		for ty = r.y0 // T, r.y1 // T do
			SG.isleTile(tx, ty)
		end
	end
end

-- Make the list a little at a time until `deadline`: every part of the island's model, its box on the grid, the tiles
-- it touches; then nearest the view first. True once it is made.
function SG.isleBuild(s: Surf, deadline: number): boolean
	local I = SG.isle
	local b0 = SG.clock()
	if I.parts == nil then
		local plots = workspace:FindFirstChild("Plots")
		local m = if plots then plots:FindFirstChild("Plot_" .. I.plot) else nil
		I.parts = if m then m:GetDescendants() else {}
		I.pi = 1
		local v = s.view
		local x0, y0 = Raster.gridPoint(v.rot12, v.grid, 0, 0, 0)
		local xa, ya = Raster.gridPoint(v.rot12, v.grid, 1, 0, 0)
		local xb, yb = Raster.gridPoint(v.rot12, v.grid, 0, 1, 0)
		local xc, yc = Raster.gridPoint(v.rot12, v.grid, 0, 0, 1)
		I.lin = { xa - x0, xb - x0, xc - x0, ya - y0, yb - y0, yc - y0, x0, y0 }
	end
	local list = I.parts :: { Instance }
	local L = I.lin :: { number }
	local ax, bx, cx, ay, by, cy, ox, oy = L[1], L[2], L[3], L[4], L[5], L[6], L[7], L[8]
	local T = SG.Tiles.TILE
	local n = 0
	while I.pi <= #list do
		local d = list[I.pi]
		I.pi += 1
		n += 1
		if n % 64 == 0 and SG.clock() >= deadline then
			I.stats.buildMs += (SG.clock() - b0) * 1000
			return false
		end
		if d:IsA("BasePart") and d.Transparency < 1 then
			local g = d.CollisionGroup
			if g ~= "Bounds" and g ~= "StagedBounds" then
				-- (its box on the grid: the middle's point, then each of its three half sides across and down)
				local cf, sz = d.CFrame, d.Size
				local p = cf.Position
				local u, w, f = cf.XVector * (sz.X / 2), cf.YVector * (sz.Y / 2), cf.ZVector * (sz.Z / 2)
				local mx = ox + ax * p.X + bx * p.Y + cx * p.Z
				local my = oy + ay * p.X + by * p.Y + cy * p.Z
				local hx = math.abs(ax * u.X + bx * u.Y + cx * u.Z) + math.abs(ax * w.X + bx * w.Y + cx * w.Z) + math.abs(ax * f.X + bx * f.Y + cx * f.Z)
				local hy = math.abs(ay * u.X + by * u.Y + cy * u.Z) + math.abs(ay * w.X + by * w.Y + cy * w.Z) + math.abs(ay * f.X + by * f.Y + cy * f.Z)
				for tx = math.floor(mx - hx - 2) // T, math.ceil(mx + hx + 2) // T do
					for ty = math.floor(my - hy - 2) // T, math.ceil(my + hy + 2) // T do
						SG.isleTile(tx, ty)
					end
				end
			end
		end
	end
	-- (nearest the middle of the layer first)
	local midX, midY = (s.cam.gx + s.W / 2) / T - 0.5, (s.cam.gy + s.H / 2) / T - 0.5
	local order = table.create(I.n)
	for i = 1, I.n do
		order[i] = i
	end
	local txs, tys = I.tx, I.ty
	local function dist(i: number): number
		return math.max(math.abs(txs[i] - midX), math.abs(tys[i] - midY) * 1.6)
	end
	table.sort(order, function(a: number, b: number): boolean
		return dist(a) < dist(b)
	end)
	local ntx, nty = table.create(I.n), table.create(I.n)
	for i, k in order do
		ntx[i], nty[i] = txs[k], tys[k]
	end
	I.tx, I.ty = ntx, nty
	I.parts, I.ready, I.idx, I.epoch, I.full = nil, true, 1, -1, false
	I.stats.listed = I.n
	I.stats.buildMs += (SG.clock() - b0) * 1000
	return true
end

-- The island's next tile the cache lacks, from `idx` on (tiles wholly on the layer are there already); nil: none.
function SG.isleNext(s: Surf): (number?, number?, { number }?)
	local I = SG.isle
	local T = SG.Tiles.TILE
	local gx, gy, W, H = s.cam.gx, s.cam.gy, s.W, s.H
	while I.idx <= I.n do
		local tx, ty = I.tx[I.idx], I.ty[I.idx]
		local x0, y0 = tx * T, ty * T
		local x1, y1 = x0 + T - 1, y0 + T - 1
		local inside = x0 >= gx and y0 >= gy and x1 <= gx + W - 1 and y1 <= gy + H - 1
		if not inside and not SG.Tiles.full(tx, ty) then
			return tx, ty, { x0, y0, x1, y1 }
		end
		I.idx += 1
	end
	return nil, nil, nil
end

-- Cast the island's tiles until `deadline`; true when there was something to do.
function SG.isleStep(s: Surf, deadline: number): boolean
	if not SG.tilesOk(s) or SG.isleOff then
		return false
	end
	local I = SG.isle
	local c0 = SG.clock()
	local plot = SG.islePlot()
	local key = plot .. "|" .. tostring(s.view)
	if key ~= I.key then
		I.key, I.plot, I.parts, I.ready, I.n, I.idx, I.full = key, plot, nil, false, 0, 1, false
		table.clear(I.set)
		I.tx, I.ty = {}, {}
	end
	if not I.ready then
		SG.isleBuild(s, deadline)
		return true
	end
	-- (anything dropped since the list was read: from its start again)
	if SG.Tiles.epoch() ~= I.epoch then
		I.epoch, I.idx, I.full = SG.Tiles.epoch(), 1, false
	end
	local A = SG.ahead
	SG.aheadLayer(s)
	local did = false
	while SG.clock() < deadline do
		if A.cur == nil then
			-- (never past the cache's size, less some room for the layer's own strips: a tile it let go of for this one
			-- would only be cast again)
			if SG.Tiles.size() >= SG.cacheCap() - Tuning.PixelIsleSpare then
				I.full = true
				break
			end
			local tx, ty, r = SG.isleNext(s)
			if tx == nil or ty == nil or r == nil then
				break
			end
			SG.aheadSet(s, tx, ty, r, true)
		end
		local t0 = A.stats.tiles
		SG.aheadPiece(s, deadline)
		I.stats.tiles += A.stats.tiles - t0
		did = true
	end
	I.stats.castMs += (SG.clock() - c0) * 1000
	return did
end

------------------------------------------------------------------ lifecycle
local function frameStep(dt: number)
	if not started or paused or tier == "off" then
		return
	end
	local f0 = SG.clock()
	SG.dt = math.clamp(dt, 1 / 240, 0.1)
	-- (the strips' pace: pixels SG.pendStep cast a frame lately, over the frames it had work)
	if SG.pendCalls > 0 then
		SG.pendRate = SG.pendRate * 0.7 + SG.pendCalls * 0.3
		SG.pendCalls = 0
	end
	SG.frameEnd = f0 + Tuning.PixelFrameMs * SG.budgetScale / 1000
	SG.castEnd = SG.frameEnd
	SG.castSpent = 0
	local pfs = stats.perf :: any
	if rebakeAt >= 0 and os.clock() >= rebakeAt then
		rebakeAt = -1
		startBake()
	end
	refreshExclude()
	SG.mapStep()
	pfs.secHeadMs = (pfs.secHeadMs or 0) + (SG.clock() - f0) * 1000
	if baking then
		local budget = if (PixelRenderer :: any)._hidden then Tuning.PixelHiddenMs else Tuning.PixelBakeMsPerFrame + (if shown and not rush then 0 else 8)
		bakeSome(SG.clock() + budget / 1000)
		if baking and back == nil then
			return -- nothing on screen to keep alive (the first bake, a jump)
		end
	end
	local s = surf
	if s and not baking then
		-- (whether this frame composes a whole tick of the moving models: the heavier frame, on which the work that can
		-- wait a frame waits; frames between two ticks, which compose only for the view, take it)
		local wasTick = SG.tickNow
		SG.tickNow = needFull or SG.dynAcc + dt >= 1 / tierSpec(tier).hz
		-- (every frame a tick, two running: a frame rate at or under the tier's hz, with no lighter frames to wait for)
		SG.tickRun = SG.tickNow and wasTick
		SG.frameNo += 1
		-- (what can wait gets the frame's time the compose and the rest are not likely to need: the request of
		-- 2026-11-22, "ms at all times should not go above 20ms even at the highest stress tests")
		local est = if SG.tickNow then SG.estTick else SG.estLite
		SG.castEnd = f0 + math.max(Tuning.PixelMinCastMs, Tuning.PixelFrameMs - est) / 1000
		-- (the picture scrolls only when the view nears its edge, re-centred under it, and not while the last scroll's
		-- strips are still being cast; the view's window moves every frame, held off them: SG.viewPan, showWindow)
		local tx, ty = SG.viewPan(s)
		local m = s.m
		local ox, oy = tx - s.cam.gx, ty - s.cam.gy
		local edge = math.min(Tuning.PixelPanEdge, m)
		local sc0 = SG.clock()
		local before = stats.scrolls
		if (SG.pend == nil or SG.vpJump) and (m == 0 or ox < edge or oy < edge or ox > s.W - s.vw - edge or oy > s.H - s.vh - edge) then
			scrollToward(s, tx - m, ty - m)
		end
		showWindow(s)
		-- the last scroll's pieces still to cast, then its strips finished (SG.pendStep, SG.finishStrips): in the frame's
		-- spare time, or now if the screen would show them
		local c0 = SG.clock()
		-- (the last scroll's strips always get Tuning.PixelMinCastMs of the frame, wherever it stands: with a compose
		-- longer than the frame's share, the frame's cast time was gone before they were reached and the window waited
		-- short of them for good; the request of 2026-11-23, "optimize the game much much more", found it)
		local stripEnd = math.max(SG.castEnd, c0 + Tuning.PixelMinCastMs / 1000)
		if SG.pend and stats.scrolls == before then
			-- (past its anchors with the view waiting on it: shown as it stands, the rest cast after; SG.release)
			-- (Tuning.PixelCoarseLead: shown from their anchors' blocks when the view waits on them, the rest cast after)
			local P = SG.pend
			local coarse = Tuning.PixelCoarseLead
			if coarse and P and P.phase >= 2 and (SG.vpBlocked or P.c4) then
				SG.release(s)
			else
				SG.pendStep(s, stripEnd)
				P = SG.pend
				if coarse and P and P.phase >= 2 and (SG.vpBlocked or P.c4) then
					SG.release(s)
				end
			end
		end
		if SG.unfin and SG.unfinSeen(s) then
			SG.finishStrips(s)
		elseif SG.unfin and SG.pend == nil then
			SG.finishStep(s, math.max(stripEnd, SG.clock() + 0.0002))
		end
		if #SG.refine > 0 and SG.pend == nil and SG.unfin == nil and SG.clock() < SG.castEnd then
			SG.refineStep(s, SG.castEnd)
		end
		if #SG.refine > 0 then
			-- (previews: how much of the layer still shows its coarse pass, and for how many frames)
			local pfr = stats.perf :: any
			local npx = 0
			for _, j in SG.refine do
				npx += (j.r.x1 - j.r.x0 + 1) * (j.r.y1 - j.r.y0 + 1)
			end
			pfr.refineFrames = (pfr.refineFrames or 0) + 1
			pfr.refinePxMax = math.max(pfr.refinePxMax or 0, npx)
		end
		SG.castSpent += (SG.clock() - c0) * 1000
		if stats.scrolls ~= before then
			SG.panAt = os.clock()
			stats.perf.panFrames += 1
			stats.perf.scrollMs += (SG.clock() - sc0) * 1000
		end
		if baking then
			return -- a jump started a bake
		end
		local i0 = SG.clock()
		pfs.secScrollMs = (pfs.secScrollMs or 0) + (i0 - sc0) * 1000
		processInvalidation()
		stats.perf.invMs += (SG.clock() - i0) * 1000
		-- the frame's spare time (nothing else is waiting to be cast): while the view moves, the tiles past the edge it
		-- moves toward (on a frame it did not scroll), else the next tier's picture, cast ahead
		if rebakeAt < 0 and invCur == nil and #invQueue == 0 and not s.view.stage and stats.scrolls == before and SG.pend == nil and #SG.refine == 0 and (SG.clock() < SG.castEnd or (PixelRenderer :: any)._hidden) then
			local p0 = SG.clock()
			-- (moving: the margin on the side the view leaves goes into the pan cache now, so the scroll that takes it off
			-- finds it kept and has nothing to save)
			if Tuning.PixelPanLate and SG.unfin == nil then
				SG.preSave(s)
			end
			-- (standing, the ring round the layer and the next tier's picture take turns, a frame each, while both have
			-- something to cast)
			-- (all of it on the frames between two ticks, with twice the time, but for the look-ahead's tiles the next
			-- scroll or two wants: a tick's frame is the heavy one, so the work that can wait leaves it alone. With
			-- every frame a tick, a slow frame rate, each gets the plain time)
			local k = if not SG.tickNow then 2 elseif SG.tickRun then 1 else 0
			if k > 0 then
				SG.ringTurn = not SG.ringTurn
			end
			-- (moving, the look-ahead has all the frame's spare time: what it does not cast in time the view waits for)
			local ce = SG.castEnd
			local pa = SG.clock()
			if (PixelRenderer :: any)._hidden then
				-- (behind the loading card: the whole island, with the hidden budget; nobody sees the frame rate)
				if SG.isleStep(s, p0 + Tuning.PixelHiddenMs / 1000) then
					stats.perf.isleMs = ((stats.perf :: any).isleMs or 0) + (SG.clock() - p0) * 1000
				end
			elseif Tuning.PixelAheadMs > 0 and SG.aheadStep(s, ce) then
				stats.perf.aheadMs += (SG.clock() - p0) * 1000
			elseif k == 0 then
				-- (a tick's frame: nothing more)
			elseif SG.ringTurn and Tuning.PixelRingMs > 0 and SG.aheadStep(s, math.min(ce, p0 + k * Tuning.PixelRingMs / 1000), true) then
				stats.perf.aheadMs += (SG.clock() - p0) * 1000
			elseif Tuning.PixelPreCastMs > 0 and PC.step(s, math.min(ce, p0 + k * Tuning.PixelPreCastMs / 1000)) then
				stats.perf.preMs += (SG.clock() - p0) * 1000
			elseif not SG.ringTurn and Tuning.PixelRingMs > 0 and SG.aheadStep(s, math.min(ce, p0 + k * Tuning.PixelRingMs / 1000), true) then
				stats.perf.aheadMs += (SG.clock() - p0) * 1000
			elseif Tuning.PixelIsleMs > 0 and SG.isleStep(s, math.min(ce, p0 + k * Tuning.PixelIsleMs / 1000)) then
				-- (the rest of the island, once nothing nearer has work)
				stats.perf.isleMs = ((stats.perf :: any).isleMs or 0) + (SG.clock() - p0) * 1000
			end
			SG.castSpent += (SG.clock() - pa) * 1000
		end
	elseif s then
		-- (a re-bake behind the picture on screen: the view still moves within its margin)
		showWindow(s)
	end
	local wv0 = SG.clock()
	-- the water's frames (on a tier whose spec has water: none since the request of 2026-11-23, "try removing more
	-- graphics and a deeper rework of the renderer"; the water keeps the frame SG.waterFix put it at): a changed frame
	-- is copied and uploaded whole by the next compose
	-- (a period that met no water on the layer: the slices rest for 2 s, then look again; the request of 2026-11-23,
	-- "optimize the game much much more": every layer pixel was looked at six times a second, about 1.2 ms a frame, on
	-- islands with no water at all)
	if s and tier ~= "low" and tierSpec(tier).water and os.clock() >= SG.waterRest then
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
			if SG.waterSeen == 0 then
				SG.waterRest = os.clock() + 2
			end
			waterFrame += 1
			SG.waterDone = 0
			SG.windDone, SG.windVoid = 0, false
			stats.perf.waterMs += (SG.clock() - w0) * 1000
		else
			stats.perf.waterMs += (w1 - w0) * 1000
		end
	end
	pfs.secWaterMs = (pfs.secWaterMs or 0) + (SG.clock() - wv0) * 1000
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
	SG.Map.watch(plots)
	if SUN_ANY then
		SG.SunMap.watch(plots)
	end
	-- (each part's shape for SG.solve worked out as the map takes it in, within the map's time, not the first time a
	-- ray needs it: a walk onto new ground spent 30 ms of one frame on that)
	SG.Map.onAdd = SG.geomOf
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
			-- (a part on the island being cast whole: its tiles on that list)
			if Street.plotAt(d.Position.X, d.Position.Z) == SG.isle.plot then
				SG.isleAdd(r)
			end
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
		if d:IsA("BasePart") then
			-- (its shape as the rays met it, should it come back elsewhere: SG.geomOf, SG.facePlane)
			SG.geom[d] = nil
			SG.planes[d] = nil
		end
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
		local fl = SG.frameLog
		local before = if fl then table.clone(stats.perf) else nil
		local kb0 = if fl then gcinfo() else 0
		local t0 = SG.clock()
		frameStep(dt)
		stats.perf.frames += 1
		local ms = (SG.clock() - t0) * 1000
		-- (what the frame took besides the casting that can wait: the next frames of its kind leave it that much)
		local rest = math.clamp(ms - SG.castSpent, 0, Tuning.PixelFrameMs)
		if SG.tickNow then
			SG.estTick += (rest - SG.estTick) * 0.25
		else
			SG.estLite += (rest - SG.estLite) * 0.25
		end
		stats.perf.stepMs += ms
		stats.perf.maxMs = math.max(stats.perf.maxMs, ms)
		if ms > 25 then
			stats.perf.slow += 1
		end
		if fl and before and ms > fl.over then
			-- (previews: what a slow frame spent its time on, the counters it moved)
			local parts: { { k: string, d: number } } = {}
			for k, v in stats.perf :: { [string]: number } do
				local d = v - ((before :: any)[k] or 0)
				if d > 0.05 and k ~= "stepMs" and k ~= "maxMs" and k ~= "frames" then
					table.insert(parts, { k = k, d = d })
				end
			end
			table.sort(parts, function(a, b)
				return a.d > b.d
			end)
			local words = {}
			for _, p in parts do
				table.insert(words, string.format("%s %.1f", p.k, p.d))
			end
			table.insert(fl.list, string.format("%.1f ms (memory %+d KB): %s", ms, gcinfo() - kb0, table.concat(words, ", ")))
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

-- The pan look-ahead's counts since the last call (previews): tiles cast and kept, cast and dropped (their ground
-- changed meanwhile), rays.
-- Previews: the pixels written as sky with no ray and as shared from their anchors (SG.castPx), and the rays cast,
-- since the last call, and the map's state (Pixel/RayMap).
function PixelRenderer.debugShare(): { sky: number, shared: number, solved: number, suns: number, rays: number, map: { parts: number, chunks: number, queued: number, ready: boolean }, sunMap: { parts: number, chunks: number, queued: number, ready: boolean } }
	local out = { sky = SG.skyN, shared = SG.sharedN, solved = SG.solvedN, suns = SG.sunN, rays = bakeRays - SG.raysAt, map = SG.Map.debugState(), sunMap = SG.SunMap.debugState() }
	SG.skyN, SG.sharedN, SG.solvedN, SG.sunN, SG.raysAt = 0, 0, 0, 0, bakeRays
	return out
end

function PixelRenderer.debugAhead(): { tiles: number, dropped: number, rays: number }
	local st = SG.ahead.stats
	local out = table.clone(st)
	st.tiles, st.dropped, st.rays = 0, 0, 0
	return out
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
	dyns[model] = { model = model, parts = parts, rim = outline == "self" or outline == "player", own = outline == "self", focus = model:GetAttribute("PixelFocus") == true, smooth = smoothModel, lo = lo, hi = hi, lead = if type(lead) == "number" then lead else nil }
end

-- A static part leaves the picture (Controllers/Spinners: a turning copy of it is drawn as a moving model instead):
-- looked through from now on (Transparency 1: BakeCast passes it by), the rect it and its shadow cover cast again.
function PixelRenderer.hideStatic(part: BasePart)
	if part.Transparency >= 0.95 then
		return
	end
	part.Transparency = 1
	SG.geom[part] = nil -- (its Transparency as SG.geomOf kept it)
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
function PixelRenderer.pose(model: Model, key: string?, hold: boolean?, group: string?)
	local d = dyns[model]
	if d then
		d.poseKey = key
		-- (group: every model posed alike under it, its parts placed the same way round where it glides from for each
		-- key, shares one picture a key, SG.groupPoses: a driftling of a kind already seen in that pose is never drawn)
		d.poseGroup = group
		-- (hold: posed in none of them now, but its pictures kept for when it is again: a founder between two walks)
		if key == nil and not hold then
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

-- How far the whole island's cast has come (SG.isle; the loading cards wait on it): done (every tile of the island
-- under the founder held, or the cache as full as it may be, or nothing to cast in this view) and the share held.
function PixelRenderer.prerender(): (boolean, number)
	local s = surf
	if tier == "off" or s == nil or not SG.tilesOk(s) or SG.isleOff then
		return true, 1
	end
	local I = SG.isle
	if not I.ready or I.key ~= SG.islePlot() .. "|" .. tostring(s.view) then
		return false, 0
	end
	if I.full then
		return true, 1
	end
	local T = SG.Tiles.TILE
	local gx, gy, W, H = s.cam.gx, s.cam.gy, s.W, s.H
	local held = 0
	for i = 1, I.n do
		local tx, ty = I.tx[i], I.ty[i]
		local x0, y0 = tx * T, ty * T
		if (x0 >= gx and y0 >= gy and x0 + T - 1 <= gx + W - 1 and y0 + T - 1 <= gy + H - 1) or SG.Tiles.full(tx, ty) then
			held += 1
		end
	end
	return held >= I.n, if I.n > 0 then held / I.n else 1
end

-- Behind a loading card: the whole island's cast (PixelRenderer.prerender) waited on for Tuning.PixelIsleWaitSecs at most,
-- `report(share)` told how far it has come every 20th of a second (the request of 2026-11-22: "could the whole player
-- island be prerendered during the loading scene, such that walking around unrendered areas wont need to lag so
-- much?"). What it has not cast by then is cast after the card opens, nearest the founder first. `stop()` true ends the
-- wait early (the card's Skip, LoadingCard.offerSkip: the request of 2026-11-23, "give an option to skip loading"; the
-- rest is cast after the card opens all the same). Yields.
function PixelRenderer.waitPrerender(report: (number) -> (), stop: (() -> boolean)?)
	local t0 = os.clock()
	while os.clock() - t0 < Tuning.PixelIsleWaitSecs do
		if stop and stop() then
			return
		end
		local done, share = PixelRenderer.prerender()
		report(share)
		if done then
			return
		end
		task.wait(0.05)
	end
end

-- Previews: the filter's own share of a frame (Tuning.PixelFrameMs) scaled by `k`, so the work that can wait gets what
-- a slower machine's frame would leave it (the stop-go of 2026-11-22 seen on a client slower than the emulator).
function PixelRenderer.debugBudget(k: number)
	SG.budgetScale = k
end

-- Previews: `us` microseconds added to every pixel cast (0: none), as a machine that casts slower than the emulator.
function PixelRenderer.debugCastSlow(us: number)
	SG.castSlowUs = us
end

-- Previews: the whole island's cast held off (true) or let go again.
function PixelRenderer.debugIsleOff(on: boolean)
	SG.isleOff = on
end

-- Previews: the whole island's cast (SG.isle): tiles listed and cast, ms making the list and casting, whether the
-- cache filled, and the cache's size.
function PixelRenderer.debugIsle(): { listed: number, cast: number, buildMs: number, castMs: number, full: boolean, cacheTiles: number, ready: boolean }
	local I = SG.isle
	return { listed = I.stats.listed, cast = I.stats.tiles, buildMs = I.stats.buildMs, castMs = I.stats.castMs, full = I.full, cacheTiles = SG.Tiles.size(), ready = I.ready }
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
	-- (the last scroll's strips finished first, as the next frame would: SG.finishStrips; and any shown before they were
	-- whole cast to the end, SG.refineStep)
	if SG.unfin then
		SG.finishStrips(s)
	end
	SG.refineStep(s, math.huge)
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
	-- (every pixel's own ray: the pixels the layer took from the map, SG.castPx, are checked against them)
	SG.noShare = true
	castRect(s, 0, 0, s.W - 1, s.H - 1)
	SG.noShare = false
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

-- Previews: the whole layer cast again `reps` times each way, every pixel its own ray and with the map's answers
-- (SG.castPx), alternately, the shadow edges left alone; the ms each way took on average, the rays each cast, and the
-- pixels the map answered. The layer is put back as it was.
function PixelRenderer.debugCastBench(reps: number): { plainMs: number, mapMs: number, plainRays: number, mapRays: number, sky: number, shared: number, rayMs: number, restMs: number, castCalls: number, split: string, probe: string, solved: number }
	local s = surf
	local out = { plainMs = 0, mapMs = 0, plainRays = 0, mapRays = 0, sky = 0, shared = 0, rayMs = 0, restMs = 0, castCalls = 0, split = "", probe = "", solved = 0 }
	if s == nil or baking then
		return out
	end
	local names = { "sShade", "sAlbedo", "sDepth", "sNormal", "sLit", "sId", "sShare", "sWClass", "sWave" }
	local sa = s :: any
	local saved: { [string]: buffer } = {}
	for _, k in names do
		saved[k] = buffer.create(buffer.len(sa[k]))
		buffer.copy(saved[k], 0, sa[k], 0)
	end
	local rays0, sky0, shared0, solved0 = bakeRays, SG.skyN, SG.sharedN, SG.solvedN
	for _ = 1, reps do
		for pass = 1, 2 do
			SG.noShare = pass == 1
			local r0 = bakeRays
			local sk, sh, so = SG.skyN, SG.sharedN, SG.solvedN
			local t0 = os.clock()
			castRect(s, 0, 0, s.W - 1, s.H - 1, true)
			local ms = (os.clock() - t0) * 1000
			if pass == 1 then
				out.plainMs += ms / reps
				out.plainRays += (bakeRays - r0) / reps
			else
				out.mapMs += ms / reps
				out.mapRays += (bakeRays - r0) / reps
				out.sky += (SG.skyN - sk) / reps
				out.shared += (SG.sharedN - sh) / reps
				out.solved += (SG.solvedN - so) / reps
			end
		end
	end
	SG.noShare = false
	-- (the map's pass once more with the ray calls timed apart: what a pixel costs besides its rays)
	do
		local real = BakeCast.cast
		local inRay = 0
		local calls = 0
		local realRay = BakeCast.sunVisible
		;(BakeCast :: any).cast = function(...)
			local t = os.clock()
			local a, b, c, d, e, f, g = real(...)
			inRay += os.clock() - t
			calls += 1
			return a, b, c, d, e, f, g
		end
		;(BakeCast :: any).sunVisible = function(...)
			local t = os.clock()
			local a = realRay(...)
			inRay += os.clock() - t
			return a
		end
		-- (and a few of the pixel's own steps timed apart)
		local parts: { [string]: number } = {}
		local saves: { [string]: any } = {}
		local function wrap(tab: any, key: string, label: string)
			local f = tab[key]
			saves[label] = { tab, key, f }
			parts[label] = 0
			tab[key] = function(...)
				local t = os.clock()
				local a, b, c, d, e, f2, g = f(...)
				parts[label] += os.clock() - t
				return a, b, c, d, e, f2, g
			end
		end
		wrap(SG, "shadeOf", "shade")
		wrap(SG.Map, "at", "map")
		wrap(SG, "shareAt", "share")
		wrap(SG, "skyAt", "sky")
		wrap(SmoothParts, "staticNormal", "smooth")
		wrap(SG, "solve", "solve")
		wrap(SG, "sunAt", "sunmap")
		wrap(SG, "castPx", "px")
		local t0 = os.clock()
		castRect(s, 0, 0, s.W - 1, s.H - 1, true)
		local all = os.clock() - t0
		for _, v in saves do
			v[1][v[2]] = v[3]
		end
		local words = {}
		for k, v in parts do
			table.insert(words, string.format("%s %.0f", k, v * 1000))
		end
		;(BakeCast :: any).cast = real
		;(BakeCast :: any).sunVisible = realRay
		out.rayMs = inRay * 1000
		out.restMs = (all - inRay) * 1000
		out.castCalls = calls
		-- (then once more checked against the rays: every hit worked out without a ray cast as well, and what the rays
		-- the maps could not answer met)
		SG.probe = { cert = 0, agree = 0, off = 0, tried = 0, ex = {} }
		castRect(s, 0, 0, s.W - 1, s.H - 1, true)
		local pr = SG.probe :: any
		SG.probe = nil
		local whys = {}
		for k, v in pr.why or {} do
			table.insert(whys, k .. " " .. v)
		end
		local hl = {}
		for k, v in pr.hits or {} do
			table.insert(hl, { k, v })
		end
		table.sort(hl, function(a, b)
			return a[2] > b[2]
		end)
		for _, e in hl do
			table.insert(whys, "ray met " .. e[1] .. " " .. e[2])
		end
		out.split = table.concat(words, ", ")
		out.probe = string.format("sun without a ray: %d, %d off; without a ray: %d of %d cast pixels, %d agree, %d off %s; %s", pr.sunN or 0, pr.sunOff or 0, pr.cert, pr.tried + pr.cert, pr.agree, pr.off, table.concat(pr.ex, " "), table.concat(whys, ", "))
	end
	bakeRays, SG.skyN, SG.sharedN, SG.solvedN = rays0, sky0, shared0, solved0
	for _, k in names do
		buffer.copy(sa[k], 0, saved[k], 0)
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
-- Previews: while on, every founder's rim put down from a kept picture is drawn from its parts as before, and the two
-- silhouettes are compared (px: the parts' pixels, off: pixels in one and not the other, depth: in both, depth apart).
function PixelRenderer.debugRimCheck(on: boolean?): { px: number, off: number, depth: number }
	if on ~= nil then
		Rims.check = on
	end
	return table.clone(Rims.checked)
end

function PixelRenderer.debugIncCheck(): { off: number, checked: number, px: number }
	SG.incArm = true
	return SG.incResult
end

-- Sims and previews: the clock the frame's budgets and timings read (nil: os.clock again).
-- Previews: from now on every frame slower than `over` ms is written down with what it spent its time on (the perf
-- counters it moved); returns the frames written down since the last call. nil stops it.
function PixelRenderer.debugFrameLog(over: number?): { string }
	local out = if SG.frameLog then SG.frameLog.list else {}
	local rows: { { name: string, h: { n: number, ms: number, parts: number, px: number, blend: number? } } } = {}
	for name, h in SG.heavyDraws do
		table.insert(rows, { name = name, h = h })
	end
	table.sort(rows, function(a, b)
		return a.h.ms > b.h.ms
	end)
	for i = 1, math.min(8, #rows) do
		local h = rows[i].h
		table.insert(out, string.format("0 ms: heavy draw %s: %d draws over 8 ms, the slowest %.1f ms (its blended body %.1f), %d parts, %d px", rows[i].name, h.n, h.ms, h.blend or 0, h.parts, h.px))
	end
	table.clear(SG.heavyDraws)
	SG.frameLog = if over then { over = over, list = {} } else nil
	return out
end

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
