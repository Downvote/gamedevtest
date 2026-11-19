--!strict
-- The hatch scene (GAME_DESIGN 6.2; docs/ARCHITECTURE.md 10.11): the request of 2026-11-13, "make a cutscene for eggs
-- hatching and shows the creature hatched, listing the mutations it has as it hatches, with eggs having a chance to
-- skip to the next rarity during the cutscene. the cutscenes become more glorious as the rarity of egg increases",
-- and of 2026-11-14: "could you also remove the transition that happens when clicking to hatch an egg? you can simply
-- render the floating egg in a 2d background. also, make the player click to hatch the egg, each click revealing a
-- mutation or a tier up upgrade if there is any, otherwise it just hatches"; then "make sounds when cracking the egg.
-- also, make the egg rise up into view when it is being opened"; then "Make eggs shake while being cracked open" (each
-- crack shakes it, the glowing egg trembles, and the tap that hatches it shakes it harder and harder before the shell
-- opens); and of 2026-11-15: "make the egg revealing much more grander with more animations and effects".
--
-- An egg bought at the Tree of Life (Controllers/EggView.hatch) shows in front of a painted sky (UI/HatchBackdrop)
-- at once: no blinds, nothing to bake (the camera's stage view on an empty see-through stage, CameraController's
-- Stage.empty: the pixel renderer draws only the moving egg over the 2D picture). Since 2026-11-14 ("Make the egg drop
-- down and bounce a bit instead of appearing by going up. Polish the egg opening backgrounds even more, drawing in a
-- base for the eggs to land on") it drops in from above onto a pedestal painted into the backdrop (FALL s, then two
-- bounces, DROP s in all), lands with a thud and a puff of dust, and rings of light start spreading from under it
-- over the pedestal (HatchBackdrop.land); then it rests there and now and then wobbles, asking to be tapped. Its shell
-- wears its rarity's pattern, drawn by the pixel filter (EggModels.hero, Render/DynTex.EGG).
-- Every tap that cracks it crunches (Audio "crack", a little higher each time) and the hatch breaks the shell open
-- ("crack_open"). Each tap takes the next of what is waiting inside: first each step up in rarity (Logic/Tree.rise:
-- the result's `hr` over its `r`), then each mutation (its plate sliding in at the right with its name, star sprites
-- and what it does). When nothing is left the cracks glow and the next tap shakes it open and hatches it: the top
-- flies off, bits of shell scatter and what hatched pops out, its name and rarity under it, its passive on a plate
-- above its mutations. One more tap goes back to the island (its picture was kept, so it is there at once) and `after`
-- runs.
-- Since 2026-11-15 every stage is a moment of its own, grander the rarer it is (GLORY):
--   the way in: before it falls (GLORY.wait, 0.12 s for a common egg up to 0.7 s for a celestial one) its shadow grows
--     on the pedestal and, from rare up, a twinkle blinks there; it lands squashing on its foot, a ring of dust spreads
--     over the pedestal, the pedestal's rings pulse, and from rare up the picture jolts.
--   waiting: it breathes (a slow squash and stretch), wobbles more often and harder the longer it waits, and hops a
--     little once it has waited a while; motes circle it, passing behind it and in front (from uncommon up), a halo
--     pulses round it (rare up) and, from epic up, faint god rays stand behind it (the backdrop's light).
--   each tap: it squashes and springs back, a flare of white light where the new crack opens, sparks from there, the
--     rays out of the cracks flare anew, a pedestal ring and, from rare up, a thin shockwave. A step up is the big one:
--     the egg leaps up spinning and comes down squashing, a flash in the new rarity's colour, god rays fanning out in
--     that colour, two shockwaves, a jolt, the sky changing, stars flying out, a chime a step higher each time and the
--     new rarity's name dropping in white and turning to its colour. A mutation's plate slides in past its place and
--     back, a starburst of its tier's colour over its stars (sparkles running along it from tier 3, a white blink at
--     tier 4).
--   the hatch: a build-up (GLORY.build, 0.6 s to 1.4 s): it shakes harder and faster, swelling, the cracks blazing
--     between white and the rarity's light, more rays out of them, sparks spitting, a crackle rising in pitch, the halo
--     and the god rays growing and, from rare up, the sky going dark (a hush). Then the break: a flash, shockwave rings
--     (one to four), the top flying off, shell and confetti (fluttering: each bit turns its two shades), the god rays
--     at full, the picture jolting; from legendary up the scene runs in slow motion for a moment (GLORY.slow). What
--     hatched shoots up out of the shell as a white silhouette, stretched, takes its colours, lands squashing with a
--     thud and a puff of dust, then stands idle (no jump for joy since 2026-11-16); stars circle it.
--   the card: the name slides up past its place and back (common, uncommon) or drops in letter by letter, each white
--     for a moment (rare up); from uncommon up its line sits on a ribbon in the rarity's colour; "New!" slams down with
--     a flare, a starburst and a ring of bits; the passive's plate slides in with a starburst. From legendary up the
--     sky fills with glints, a mythic egg's petals fall thicker and a celestial one's sky rains glints. The god rays
--     stay turning behind what hatched from epic up (their colours shifting for a mythic or celestial one).
-- Taps skip ahead: one during the build-up breaks it at once, one while what hatched comes out shows the whole card.
-- The rarer, the grander also in the old ways: twinkles round the egg (rare and up), more sparks and shell, confetti;
-- the light of dusk for the commoner ones, a blue, violet or deep gold night for the rarer, a rose night for a mythic
-- one and a deep starry blue for a celestial one (DayLight.hold). A mythic egg's twinkles are pink, a celestial one's
-- long glints of white and cyan, and petals or motes drift by.
--   HatchScene.play(result, after?)   result: { sp, muts, r (laid), hr (hatched as), new? (a kind never had: "New!") };
--                                     while a scene shows, the hatch waits and plays when it ends (HatchScene.waiting():
--                                     how many wait)
--   HatchScene.isOpen(), HatchScene.skip() (a tap), HatchScene.debugState() (sims and previews: the phase and what is
--   shown), HatchScene.setQuick(on) (sims: the scene ends at once, `after` still runs)
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Palette = require(ReplicatedStorage.Shared.Data.Palette)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local EggModels = require(ReplicatedStorage.Shared.Models.EggModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local TierStars = require(script.Parent.TierStars)
local HatchBackdrop = require(script.Parent.HatchBackdrop)

local HatchScene = {}

-- `new`: a kind the player never had before (Logic/Tree.hatch's `new`): a "New!" badge pops up by its name.
export type Result = { sp: string, muts: { string }, r: number, hr: number, new: boolean? }

local ORIGIN = Vector3.new(0, 0, 9000) -- far from the islands (z 0 .. -160)
local FLOAT_Y = 1.2 -- the pedestal's top above ORIGIN: the egg rests on it, what hatched stands on it
local EGG_H: { number } = { 2.3, 2.4, 2.5, 2.65, 2.8, 2.9, 3.0 } -- each rarity's egg up close (EggModels.hero), studs tall
local PAL_SCALE = 1.35 -- what hatched, a little bigger than on the island
local TAP_GAP = 0.22 -- seconds a tap waits after the last one (a double tap is one)
-- the box the stage view fits is this many times the egg's own room, about the egg's middle: bigger draws the egg and
-- what hatches smaller on the screen (the request of 2026-11-14: "make the egg and creature smaller in the hatching
-- screen"; it was 1)
local STAGE_ROOM = 1.45
-- the egg's way in (the request of 2026-11-14: "Make the egg drop down and bounce a bit instead of appearing by going
-- up"): after its wait (GLORY.wait) it falls from out of the picture onto the pedestal (FALL s, gravity), bounces up
-- BOUNCE[1] studs and down (BOUNCE_T[1] s), then a little bounce, then rests; taps wait till it does (its wait and
-- DROP s)
local DROP_FROM = 9 -- studs over its spot it starts
local FALL = 0.52
local BOUNCE = { 0.75, 0.2 }
local BOUNCE_T = { 0.3, 0.18 }
local DROP = FALL + BOUNCE_T[1] + BOUNCE_T[2]
local RISE_T = 0.6 -- a step up: the egg leaps up spinning and comes back down in this long
local RISE_H = 0.8 -- studs it leaps
local SLOW = 0.3 -- how fast the scene runs in its slow motion at the break
local POP_UP = 0.12 -- what hatched: seconds it takes to come up out of the shell, stretched, before its leap

-- How grand each rarity's scene is (by the rarity it is now; the hatch's by the rarity it hatched as).
type Glory = {
	rays: number, -- twinkles round it at once, about (they took the place of rays of light)
	sparks: number, -- sparks out of the crack
	shards: number, -- bits of shell
	flash: number, -- the white flash's strength (0 .. 1)
	jolt: number, -- art px the picture jolts at the crack
	confetti: number,
	stars: number, -- stars circling what hatched
	wait: number, -- seconds before it falls (its shadow growing, a twinkle on the pedestal)
	build: number, -- seconds it shakes open between the tap that hatches it and the shell opening
	slow: number, -- seconds of slow motion at the break (real time)
	show: number, -- seconds from the break to "Tap to go on"
	beams: number, -- god rays in the fan behind it (0: none)
	reach: number, -- the long ones' length, share of the screen's height
	hush: number, -- how dark the sky goes in the build-up (0 .. 1)
	rings: number, -- shockwave rings at the break
	motes: number, -- motes circling it while it waits
	hop: number, -- studs what hatched leaps out of the shell
}
-- stylua: ignore start
local GLORY: { Glory } = {
	{ rays = 0, sparks = 12, shards = 6, flash = 0.25, jolt = 0, confetti = 0, stars = 0, wait = 0.12, build = 0.6, slow = 0, show = 0.7, beams = 0, reach = 0, hush = 0, rings = 1, motes = 0, hop = 0.45 },
	{ rays = 0, sparks = 18, shards = 8, flash = 0.3, jolt = 0, confetti = 0, stars = 3, wait = 0.18, build = 0.65, slow = 0, show = 0.8, beams = 8, reach = 0.32, hush = 0, rings = 1, motes = 2, hop = 0.55 },
	{ rays = 8, sparks = 26, shards = 10, flash = 0.4, jolt = 1, confetti = 0, stars = 5, wait = 0.28, build = 0.75, slow = 0, show = 1.0, beams = 10, reach = 0.42, hush = 0.15, rings = 2, motes = 3, hop = 0.65 },
	{ rays = 12, sparks = 36, shards = 12, flash = 0.5, jolt = 2, confetti = 50, stars = 7, wait = 0.38, build = 0.9, slow = 0, show = 1.2, beams = 12, reach = 0.52, hush = 0.3, rings = 2, motes = 4, hop = 0.75 },
	{ rays = 16, sparks = 50, shards = 14, flash = 0.6, jolt = 3, confetti = 110, stars = 9, wait = 0.5, build = 1.05, slow = 0.3, show = 1.4, beams = 14, reach = 0.62, hush = 0.4, rings = 3, motes = 5, hop = 0.85 },
	{ rays = 21, sparks = 64, shards = 16, flash = 0.7, jolt = 4, confetti = 150, stars = 10, wait = 0.6, build = 1.2, slow = 0.4, show = 1.6, beams = 16, reach = 0.72, hush = 0.45, rings = 3, motes = 6, hop = 0.95 },
	{ rays = 26, sparks = 80, shards = 18, flash = 0.8, jolt = 5, confetti = 200, stars = 12, wait = 0.7, build = 1.4, slow = 0.5, show = 1.8, beams = 18, reach = 0.85, hush = 0.5, rings = 4, motes = 8, hop = 1.05 },
}
-- stylua: ignore end

-- The light of each rarity's scene (the renderer's grade, as DayLight's: a warm dusk for the commoner ones, then a blue
-- twilight, a violet night, a deep gold one, a rose one and a starry blue one; the egg's own lights pooling stronger
-- the darker it is).
local GRADE: { PixelRenderer.Grade } = {
	{ mr = 1.04, mg = 0.93, mb = 0.8, lift = 0, sat = 1.05, lamps = 0.3 },
	{ mr = 0.98, mg = 0.96, mb = 0.8, lift = 2, sat = 1.05, lamps = 0.4 },
	{ mr = 0.82, mg = 0.84, mb = 1.02, lift = 4, sat = 0.98, lamps = 0.6 },
	{ mr = 0.84, mg = 0.7, mb = 1.0, lift = 6, sat = 0.98, lamps = 0.75 },
	{ mr = 0.98, mg = 0.78, mb = 0.62, lift = 4, sat = 1.04, lamps = 0.9 },
	{ mr = 1.0, mg = 0.86, mb = 0.94, lift = 5, sat = 1.02, lamps = 0.9 },
	{ mr = 0.8, mg = 0.88, mb = 1.08, lift = 6, sat = 1.02, lamps = 0.6 }, -- (its ring of lights close round it: less pooling, so they never blot the shell)
}

-- Each rarity's colours in the scene: its sparks and its cracks' light (palette keys).
local RAY: { { string } } = { { "cream", "white" }, { "green", "white" }, { "blue", "white" }, { "purple", "pink" }, { "gold", "yellow" }, { "pink", "cherry" }, { "crystal", "screen_on" } }
-- The god rays' colours, beam by beam (palette keys); a mythic or celestial egg's travel round the fan.
local SHINE: { { string } } = {
	{ "cream", "white" },
	{ "screen_code", "cream" },
	{ "screen_on", "white" },
	{ "crystal", "pink", "white" },
	{ "cream", "yellow", "white" },
	{ "pink", "cherry", "white" },
	{ "screen_on", "crystal", "pink", "white", "yellow" },
}

-- Each rarity's twinkle (its frames, opening and closing): white and cyan stars, gold sparks for a legendary egg, pink
-- stars for a mythic one, long white and cyan glints for a celestial one.
local TWINKLE: { { string } } = {
	{ "twinkle_1", "twinkle_2", "twinkle_1" },
	{ "twinkle_1", "twinkle_2", "twinkle_1" },
	{ "twinkle_1", "twinkle_2", "twinkle_1" },
	{ "twinkle_1", "twinkle_2", "twinkle_1" },
	{ "spark_1", "spark_2", "spark_3", "spark_2" },
	{ "twinkle_p1", "twinkle_p2", "twinkle_p3", "twinkle_p2" },
	{ "glint_1", "glint_2", "glint_3", "glint_2", "glint_1" },
}
-- A flare of white light (a crack opening, "New!" landing): it grows its arms and closes again.
local FLARE = { "flare_1", "flare_2", "flare_3", "flare_2", "flare_1" }
-- Confetti: each bit's two shades, the side it shows turning as it flutters down.
local CONFETTI: { { string } } = { { "pink", "wall_trim" }, { "yellow", "gold" }, { "blue", "hair_blue" }, { "green", "leaf_dark" }, { "orange", "clay" }, { "crystal", "purple" }, { "white", "cherry" } }

------------------------------------------------------------------ state
type Reveal = { kind: string, r: number?, i: number? } -- "rise" (to rarity r) | "mut" (the i-th mutation)
type Shard = { p: BasePart, v: Vector3, w: number, at: Vector3, born: number }
-- a bit on the overlay: a 1 px dot, or a sprite's frames (`frames`, run once over its life or round every `loop` s);
-- `alt` a confetti bit's other shade; `orbit` circling a point: centre x, y, radii, starting angle, turn a second
type Dot = { gui: GuiObject, world: Vector3?, x: number, y: number, vx: number, vy: number, g: number, born: number, life: number, frames: { GuiObject }?, loop: number?, hw: number, hh: number, col: Color3?, alt: Color3?, ph: number, orbit: { number }? }
-- a ray of light out of a crack: its 1 px pixels in a holder at the crack (stepBeams)
type Beam = { holder: Frame, px: { Frame }, from: BasePart?, len: number, born: number, life: number, shown: number, dim: boolean, placed: boolean }
-- an overlay piece moving to `to` from `dx`, `dy` px off it (whole px; `over`: past its place and back)
type Move = { gui: GuiObject, to: UDim2, dx: number, dy: number, born: number, dur: number, over: boolean }
type Cue = { at: number, fn: () -> () }
-- a starburst: 1 px pixels on rays out of a point, each `j` px out, shooting out and then going from the inside out
type Burst = { px: { Frame }, j: { number }, len: number, born: number, life: number }
-- a ring on the backdrop's light (art px; a shockwave flat 1, a ring of dust on the pedestal flatter)
type Wave = { x: number, y: number, from: number, to: number, flat: number, col: number, k: number, born: number, life: number }
type Scene = {
	res: Result,
	after: (() -> ())?,
	r: number, -- the rarity shown now (it climbs to res.hr)
	dyn: Folder,
	clock: number, -- the scene's own clock (it runs slower in the slow motion)
	real: number, -- real seconds since it opened
	slowUntil: number, -- real seconds: the slow motion runs till then
	phase: string, -- "egg" (taps reveal) | "breaking" (shaking open) | "hatched" (what hatched popping out) | "done" (a tap goes back)
	queue: { Reveal }, -- what the next taps reveal, in order
	total: number, -- reveals in all
	rises: number, -- steps up shown so far (each one's chime a step higher)
	crack: number, -- the cracks shown (0 .. 3)
	lastTap: number, -- the scene clock at the last tap taken
	tapAt: number, -- real seconds at the last tap taken (a double tap is one, slow motion or not)
	hatchAt: number, -- real seconds when it hatched
	wait: number, -- seconds before it falls (GLORY.wait of the rarity it was laid as)
	landAt: number, -- when it came to rest on the pedestal (its waiting counts from then or the last tap)
	wob: number, -- its waiting wobbles' phase (one a turn)
	kickAt: number, -- the last shake (scene clock) and how hard
	kick: number,
	squashAt: number, -- the last squash (scene clock) and how hard (+ squashed, - stretched)
	squashK: number,
	sq: number, -- the squash on it now (sims and previews; 0 at rest)
	riseAt: number, -- the last step up (it leaps and spins) and whether it is down again
	riseDown: boolean,
	breakAt: number, -- when the tap that hatches it came (it shakes open for `build` s)
	build: number,
	tick: number, -- the build-up's next crackle (scene clock)
	shake: number, -- how hard it shakes this frame (0 at rest; sims and previews)
	-- the egg
	egg: Model?,
	parts: { { p: BasePart, off: CFrame } },
	sizes: { Vector3 }, -- each part's own size (squashing scales it)
	top: { BasePart },
	fx: { { p: BasePart, kind: string, k: number } },
	cracks: { EggModels.Crack },
	crackSizes: { Vector3 },
	cf: CFrame, -- the egg's foot now
	mid: Vector3, -- its middle now
	glowing: boolean, -- the cracks lit from inside (nothing left to reveal: the next tap hatches it)
	blaze: number, -- the cracks' colour in the build-up (0 white, 1 the rarity's light)
	beams: { Beam }, -- the rays of light out of the cracks (stepBeams)
	beamsMade: number, -- rays let out so far (sims and previews)
	placedAt: number, -- the scene clock when the rays were last put on their cracks (placeBeams)
	arrived: boolean, -- it has landed on the pedestal (a thud, dust, the rings start)
	bounced: boolean, -- it has come down from its first bounce (a softer thud)
	topOff: number?, -- when it hatched (the top flew off)
	rays: { { p: BasePart, a: number, k: number } }, -- (none since the twinkles took their place)
	twinkleN: number, -- twinkles round it at once, about (GLORY.rays; 0: none)
	twinkleAt: number, -- the scene clock when the next one comes
	shards: { Shard },
	pal: MicroModels.Thing?,
	popAt: number?,
	whiteUntil: number, -- what hatched shows as a white silhouette till then
	palDown: boolean, -- it has landed from its leap out of the shell
	palLand: number,
	dots: { Dot },
	motes: { Frame }, -- the motes circling the egg (in front of it; behind it they are the backdrop's)
	moveList: { Move },
	cues: { Cue },
	bursts: { Burst },
	waves: { Wave },
	lightAt: number, -- the god rays' last burst (fanning out) and how strong
	lightK: number,
	joltAt: number, -- the last jolt of the picture and how far (art px); the offset now
	joltK: number,
	jx: number,
	jy: number,
	hush: number, -- the sky darkened now (0 .. 1)
	eggPx: number, -- the egg's half width on the screen (art px), the pedestal's top centre and half width
	baseX: number,
	baseY: number,
	baseW: number,
	-- the overlay
	root: Frame,
	title: TextLabel?,
	name: TextLabel?,
	line: TextLabel?,
	hint: TextLabel?,
	letters: { TextLabel },
	ribbon: Frame?,
	plates: { Frame },
	shown: number, -- mutation plates shown
	passive: boolean, -- the passive's plate shown (as it hatches)
	flash: Frame?,
	flashAt: number,
	flashK: number,
	flashT: number,
	beat: RBXScriptConnection?,
	keys: RBXScriptConnection?,
	resize: RBXScriptConnection?, -- the Stage canvas changing size (relayout)
	closing: boolean,
}

local scene: Scene? = nil
-- hatches that came while a scene showed, each played when the one before it ends
local waiting: { { res: Result, after: (() -> ())? } } = {}
local quick = false

local function glory(r: number): Glory
	return GLORY[math.clamp(r, 1, #GLORY)]
end

local function twinkle(r: number): { string }
	return TWINKLE[math.clamp(r, 1, #TWINKLE)]
end

local function ease(u: number): number
	local x = math.clamp(u, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

-- Out past the end and back (an overshoot of about a tenth of the way).
local function back(u: number): number
	local x = math.clamp(u, 0, 1) - 1
	return 1 + 2.7 * x * x * x + 1.7 * x * x
end

local PAL_TURN = math.rad(30) -- the creature's turn from facing the viewer: three quarters, as the portraits

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- A palette key's colour as 0xRRGGBB (the backdrop's light) and as a Color3.
local function hexOf(key: string): number
	return Palette.ui[key] or Palette.colors[key] or 0xFFFFFF
end

local function rarColor(r: number): Color3
	return UIKit.color((Traits.RARITY[r] or Traits.RARITY[1]).color)
end

------------------------------------------------------------------ the egg and what hatches
local function dropEgg(s: Scene)
	local m = s.egg
	if m then
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
	end
	s.egg, s.parts, s.top, s.fx, s.cracks, s.glowing = nil, {}, {}, {}, {}, false
	s.sizes, s.crackSizes = {}, {}
end

local function newEgg(s: Scene, r: number)
	dropEgg(s)
	local m, parts, top, fx, cracks = EggModels.hero(r, EGG_H[r] or 2.4)
	-- (each crack glows in the rarity's light, rays streaming out of it: stepBeams; coloured before the pixel filter
	-- takes the model in, which reads the colours then)
	for _, k in cracks do
		k.p.Color = Blocks.color(RAY[r][2])
	end
	m.Parent = s.dyn
	PixelRenderer.registerDynamic(m)
	s.egg, s.parts, s.top, s.fx, s.cracks, s.glowing = m, parts, top, fx, cracks, false
	for i, rp in parts do
		s.sizes[i] = rp.p.Size
	end
	for i, k in cracks do
		s.crackSizes[i] = k.p.Size
	end
	s.sq = 0
end

-- Twinkles round the egg (the request of 2026-11-14: "remove these rectangular effects everywhere, instead make it
-- twinkles": they took the place of rays of light, thin bright bars turning behind it): from a rare egg up, little
-- stars blink in and out at random round it, more the rarer it is (GLORY.rays), and round what hatched after.
local function newRays(s: Scene, r: number)
	s.twinkleN = glory(r).rays
end

-- The egg's foot when it rests on the pedestal (its lowest slice bulges past the foot: EggModels.heroBottom).
local function footY(r: number): number
	return FLOAT_Y - EggModels.heroBottom(EGG_H[r] or 2.4)
end

local function eggMiddle(r: number): Vector3
	return at(0, footY(r) + 0.5 * (EGG_H[r] or 2.4), 0)
end

-- How far over its spot the egg is while it comes in (0 once it rests): out of the picture while it waits, then
-- falling faster and faster, then each bounce a quick arc, the second lower and quicker than the first.
local function liftOf(s: Scene, clock: number): number
	local c = clock - s.wait
	if c < 0 then
		return DROP_FROM
	elseif c >= DROP then
		return 0
	elseif c < FALL then
		local u = c / FALL
		return DROP_FROM * (1 - u * u)
	end
	local k = c - FALL
	for i, d in BOUNCE_T do
		if k < d then
			local u = k / d
			return 4 * BOUNCE[i] * u * (1 - u)
		end
		k -= d
	end
	return 0
end

-- The painted sky (UI/HatchBackdrop), the egg's glow round where it floats on screen; only with the pixel filter on
-- (in the classic look Roblox's own sky shows). Also where the egg and the pedestal are on the screen, for the light.
local function backdrop(s: Scene)
	if not PixelRenderer.isActive() then
		return
	end
	local ex, ey = PixelRenderer.projectPixel(eggMiddle(s.r))
	-- (the pedestal: its top where the egg rests, twice the egg's widest across)
	local top = at(0, FLOAT_Y, 0)
	local bx, by = PixelRenderer.projectPixel(top)
	local cam = workspace.CurrentCamera
	local rv = if cam then cam.CFrame.RightVector else Vector3.xAxis
	local right = Vector3.new(rv.X, 0, rv.Z)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local rx = PixelRenderer.projectPixel(top + right * (0.37 * (EGG_H[s.r] or 2.4) * 2))
	local w = math.abs(rx - bx)
	s.baseX, s.baseY, s.baseW, s.eggPx = bx, by, w, math.max(4, w / 2)
	HatchBackdrop.show(s.r, ex, ey, { x = bx, y = by, w = w })
end

------------------------------------------------------------------ the overlay's bits
local function canvasSize(): (number, number)
	local v = UIKit.size("Stage")
	return v.X, v.Y
end

local function addDot(s: Scene, color: string, world: Vector3?, x: number, y: number, vx: number, vy: number, g: number, life: number): Dot?
	if #s.dots > 420 then
		return nil
	end
	local col = UIKit.color(color)
	local gui: GuiObject = UIKit.rect(s.root, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, y), col, 30)
	gui.Name = "HatchDot"
	local d: Dot = { gui = gui, world = world, x = x, y = y, vx = vx, vy = vy, g = g, born = s.clock, life = life, frames = nil, loop = nil, hw = 0, hh = 0, col = col, alt = nil, ph = math.random(), orbit = nil }
	table.insert(s.dots, d)
	return d
end

local function addStar(s: Scene, names: { string }, x: number, y: number, life: number, vy: number?, vx: number?): Dot
	local holder = Instance.new("Frame")
	holder.Name = "HatchStar"
	holder.BackgroundTransparency = 1
	local w, h = PixelSprites.size(names[1])
	holder.Size = UDim2.fromOffset(w, h)
	local frames: { GuiObject } = {}
	for k, n in names do
		local im = PixelSprites.image(holder, n, UDim2.fromOffset(0, 0), 31)
		im.Visible = k == 1
		frames[k] = im
	end
	holder.Position = UDim2.fromOffset(x - math.floor(w / 2), y - math.floor(h / 2))
	holder.Parent = s.root
	local gui: GuiObject = holder
	local d: Dot = { gui = gui, world = nil, x = x - math.floor(w / 2), y = y - math.floor(h / 2), vx = vx or 0, vy = vy or 0, g = 0, born = s.clock, life = life, frames = frames, loop = nil, hw = math.floor(w / 2), hh = math.floor(h / 2), col = nil, alt = nil, ph = 0, orbit = nil }
	table.insert(s.dots, d)
	return d
end

-- A burst of sparks from a world point: n bits flying out and falling, the rarity's two colours.
local function burst(s: Scene, from: Vector3, r: number, n: number, speed: number)
	local px, py = PixelRenderer.projectPixel(from)
	local cols = { RAY[r][1], RAY[r][2], "white" }
	for k = 1, n do
		local a = math.random() * math.pi * 2
		local v = speed * (0.4 + math.random() * 0.8)
		addDot(s, cols[(k % #cols) + 1], nil, px, py, math.cos(a) * v, math.sin(a) * v - speed * 0.6, speed * 1.4, 0.6 + math.random() * 0.7)
	end
end

-- The screen flashes (k: how strong, 0 .. 1), fading in four steps over `dur` s of the scene's clock.
local function flash(s: Scene, k: number, color: Color3?, dur: number?)
	if k <= 0 then
		return
	end
	local f = s.flash
	if f == nil then
		local nf = UIKit.rect(s.root, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), UIKit.color("white"), 32)
		nf.Name = "HatchFlash"
		s.flash = nf
		f = nf
	end
	if f then
		f.BackgroundColor3 = color or UIKit.color("white")
		f.BackgroundTransparency = 1 - k
		f.Visible = true
	end
	s.flashAt, s.flashK, s.flashT = s.clock, k, dur or 0.3
end

-- Something on the overlay moves into place (`to`) from dx, dy px off it, on whole px.
local function slide(s: Scene, gui: GuiObject, to: UDim2, dx: number, dy: number, dur: number, over: boolean)
	for i = #s.moveList, 1, -1 do
		if s.moveList[i].gui == gui then
			table.remove(s.moveList, i)
		end
	end
	gui.Position = UDim2.new(to.X.Scale, to.X.Offset + dx, to.Y.Scale, to.Y.Offset + dy)
	table.insert(s.moveList, { gui = gui, to = to, dx = dx, dy = dy, born = s.clock, dur = dur, over = over })
end

-- Something to do at a time on the scene's clock (the hatch's card, one piece after another; a tap runs them all).
local function cue(s: Scene, t: number, fn: () -> ())
	table.insert(s.cues, { at = t, fn = fn })
end

-- A starburst at (x, y): n rays (4: the axes, 8: and the diagonals) of 1 px pixels from 2 px out to len, white at the
-- core and then the colour.
local function starburst(s: Scene, x: number, y: number, color: Color3, n: number, len: number, life: number)
	local dirs = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
	local b: Burst = { px = {}, j = {}, len = len, born = s.clock, life = life }
	local white = UIKit.color("white")
	for i = 1, math.min(n, #dirs) do
		local d = dirs[i]
		-- (the diagonals a little shorter, so the burst reads round)
		local l = if i > 4 then math.floor(len * 0.7 + 0.5) else len
		for j = 2, l do
			local f = UIKit.rect(s.root, UDim2.fromOffset(1, 1), UDim2.fromOffset(x + d[1] * j, y + d[2] * j), if j <= 2 + math.floor(l / 3) then white else color, 36)
			f.Name = "HatchBurst"
			f.Visible = false
			table.insert(b.px, f)
			table.insert(b.j, j / l)
		end
	end
	table.insert(s.bursts, b)
end

-- A ring spreading on the backdrop's light from (x, y) (art px), from one radius to another over `life` s.
local function wave(s: Scene, x: number, y: number, col: number, from: number, to: number, flat: number, k: number, life: number)
	table.insert(s.waves, { x = x, y = y, from = from, to = to, flat = flat, col = col, k = k, born = s.clock, life = life })
end

local function squash(s: Scene, k: number)
	s.squashAt, s.squashK = s.clock, k
end

local function jolt(s: Scene, k: number)
	if k <= 0 then
		return
	end
	local left = s.joltK * math.max(0, 1 - (s.clock - s.joltAt) / 0.32)
	if k >= left then
		s.joltAt, s.joltK = s.clock, k
	end
end

-- (the words at the top and the foot span the overlay by scale, not by the canvas's size when they were made: the
-- canvas can settle or change after the scene opens, a window resized, the top bar's inset arriving, the pixel scale
-- stepping, and a label as wide as the old canvas would sit off centre)
-- `slam`: it drops in from above the screen past its place and back, white at first and then its colour (a step up).
local function setTitle(s: Scene, text: string, color: string, slam: boolean?)
	local old = s.title
	if old then
		old:Destroy()
	end
	local t = UIKit.text(s.root, text, UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 8), { x = "center", face = "big", kind = "title", color = UIKit.color(if slam then "white" else color), z = 33, name = "HatchTitle" })
	s.title = t
	if slam then
		slide(s, t, UDim2.fromOffset(0, 8), 0, -26, 0.32, true)
		cue(s, s.clock + 0.12, function()
			if t.Parent then
				UIKit.setTextColor(t, UIKit.color(color))
			end
		end)
	else
		-- (it drops in: a few px down to rest)
		slide(s, t, UDim2.fromOffset(0, 8), 0, -4, 0.2, true)
	end
end

-- The egg's title: its rarity alone ("Legendary"; the request of 2026-11-14: "no need for "A x egg" for rarities for
-- eggs, just do "Legendary" "Common" etc. do the same for "It turned x", just the rarity is enough").
local function eggWords(r: number): string
	local rar = Traits.RARITY[r] or Traits.RARITY[1]
	return rar.name
end

-- Where the "New!" tag goes: just right of the name (never off the screen's right edge).
local function newTagAt(nm: TextLabel): (number, number)
	local w, h = canvasSize()
	local nameW = UIKit.textWidth(nm.Text, "big")
	local tw = UIKit.textWidth("New!") + 6
	return math.min(w - tw - 2, math.floor((w + nameW) / 2) + 4), h - 40
end

-- A ribbon in the rarity's colour under the line ("Rare, good at farms"): a band w px wide with a 1 px ink outline, a
-- lighter top row and a darker bottom one, and a tail at each end a little lower and a shade darker, its end cut in a
-- notch. Drawn in 1 px rects on the overlay's grid.
local TAIL: { string } = {
	"kkkkkkkkkk",
	".kdddddddd",
	"..kddddddd",
	"...kdddddd",
	"....kddddd",
	"....kddddd",
	"...kdddddd",
	"..kddddddd",
	".kdddddddd",
	"kkkkkkkkkk",
}
local function ribbon(s: Scene, w: number, r: number): Frame
	local base = rarColor(r)
	local ink = UIKit.color("ink")
	local light = base:Lerp(UIKit.color("white"), 0.35)
	local dark = base:Lerp(ink, 0.32)
	local deep = base:Lerp(ink, 0.5)
	local total = w + 2 * 7
	local holder = Instance.new("Frame")
	holder.Name = "HatchRibbon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(total, 14)
	holder.Parent = s.root
	local function rect(x: number, y: number, rw: number, rh: number, c: Color3, z: number)
		UIKit.rect(holder, UDim2.fromOffset(rw, rh), UDim2.fromOffset(x, y), c, z)
	end
	-- the tails: the left one as drawn, the right one turned about; behind the band
	for side = 0, 1 do
		for y, row in TAIL do
			local x = 1
			while x <= #row do
				local ch = string.sub(row, x, x)
				local run = x
				while run + 1 <= #row and string.sub(row, run + 1, run + 1) == ch do
					run += 1
				end
				if ch ~= "." then
					local c = if ch == "k" then ink else (if side == 0 then dark else deep)
					local lx = if side == 0 then x - 1 else total - run
					rect(lx, y + 3, run - x + 1, 1, c, 33)
				end
				x = run + 1
			end
		end
	end
	-- the band over them
	rect(7, 0, w, 12, ink, 34)
	rect(8, 1, w - 2, 10, base, 34)
	rect(8, 1, w - 2, 1, light, 34)
	rect(8, 10, w - 2, 1, dark, 34)
	return holder
end

-- "New!" by the name (a kind never had before: the request of 2026-11-14, "there should a tip saying "New!" If the
-- creature caught is new"): a mango tag slamming down past its place and back, with a flare, a starburst and a ring of
-- bits.
local function showNew(s: Scene)
	local nm = s.name
	if nm == nil or s.res.new ~= true or s.root:FindFirstChild("HatchNew") then
		return
	end
	local tw = UIKit.textWidth("New!") + 6
	local bx, by = newTagAt(nm)
	local tag = UIKit.plate(s.root, UDim2.fromOffset(tw, 12), UDim2.fromOffset(bx, by), UIKit.color("accent"), 0, 1)
	tag.Name = "HatchNew"
	tag.ZIndex = 34
	UIKit.text(tag, "New!", UDim2.fromOffset(tw, 12), UDim2.fromOffset(0, 0), { x = "center", color = UIKit.color("text_ink"), kind = "plain", z = 35, name = "Word" })
	slide(s, tag, UDim2.fromOffset(bx, by), 0, -16, 0.26, true)
	-- (a word new to the pixel font shows two frames after it is drawn: the tag stays hidden that long, so its plate
	-- never shows empty)
	tag.Visible = false
	task.delay(0.07, function()
		if tag.Parent then
			tag.Visible = true
		end
	end)
	local cx, cy = bx + math.floor(tw / 2), by + 6
	for k = 1, 12 do
		local a = k / 12 * math.pi * 2
		addDot(s, if k % 2 == 0 then "accent" else "white", nil, cx, cy, math.cos(a) * 40, math.sin(a) * 30 - 10, 30, 0.6)
	end
	cue(s, s.clock + 0.16, function()
		starburst(s, cx, cy, UIKit.color("accent"), 8, 9, 0.4)
		addStar(s, FLARE, bx + tw, by, 0.3)
	end)
	Audio.play("sparkle", { pitch = 1.12 })
end

-- The name dropped in letter by letter (rare and up): each a label of its own, dropping from above past its place and
-- back, white for a moment and then the rarity's colour, a tick higher each time. The name's own label stays (its
-- words for the sims) but hidden.
local function showLetters(s: Scene, nm: TextLabel, color: Color3, start: number): number
	local text = nm.Text
	local W = UIKit.textWidth(text, "big")
	local x0 = -math.floor(W / 2)
	local acc, i = 0, 0
	nm.Visible = false
	for _, cp in utf8.codes(text) do
		local ch = utf8.char(cp)
		local cw = UIKit.textWidth(ch, "big")
		if ch ~= " " then
			local x, n = x0 + acc, i
			cue(s, start + n * 0.035, function()
				if s.closing then
					return
				end
				local l = UIKit.text(s.root, ch, UDim2.fromOffset(cw + 6, 18), UDim2.new(0.5, x - 3, 1, -42), { x = "center", face = "big", kind = "title", color = UIKit.color("white"), z = 36, name = "HatchLetter" })
				table.insert(s.letters, l)
				slide(s, l, UDim2.new(0.5, x - 3, 1, -42), 0, -12, 0.22, true)
				Audio.play("tick", { pitch = 1 + n * 0.05, volume = 0.8 })
				cue(s, s.clock + 0.08, function()
					if l.Parent then
						UIKit.setTextColor(l, color)
					end
				end)
			end)
			i += 1
		end
		acc += cw
	end
	return start + i * 0.035
end

-- What hatched, under it: its name in its rarity's colour, its rarity and how fast it works (on a ribbon from uncommon
-- up; it named the kind of work it was good at till every workplace became one kind, 2026-11-19). Its
-- "New!" comes once the name is in.
local function showName(s: Scene)
	local def = Creatures.byId[s.res.sp]
	local r = if def then def.rarity else s.r
	local rar = Traits.RARITY[r] or Traits.RARITY[1]
	local nm = UIKit.text(s.root, if def then def.name else "A driftling", UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 1, -42), { x = "center", face = "big", kind = "title", color = UIKit.color(rar.color), z = 36, name = "HatchName" })
	local speed = if def then (Tuning.RarityWork[def.rarity] or 1) * (1 + Traits.work(Traits.sum(def.passive.fx, s.res.muts))) else 1
	local words = if def then string.format("%s, works x%.1f", rar.name, speed) else rar.name
	-- (on its ribbon from uncommon up, in ink)
	local onRibbon = s.r >= 2
	local line = UIKit.text(s.root, words, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -24), { x = "center", color = UIKit.color(if onRibbon then "text_ink" else "paper"), kind = if onRibbon then "plain" else nil, z = 35, name = "HatchLine" })
	s.name, s.line = nm, line
	local newAt = s.clock + 0.15
	if s.r >= 3 then
		newAt = showLetters(s, nm, UIKit.color(rar.color), s.clock) + 0.06
	else
		slide(s, nm, UDim2.new(0, 0, 1, -42), 0, 8, 0.24, true)
	end
	slide(s, line, UDim2.new(0, 0, 1, -24), 0, 6, 0.22, true)
	if onRibbon then
		local w = UIKit.textWidth(words) + 14
		cue(s, s.clock + 0.06, function()
			if s.closing then
				return
			end
			local rb = ribbon(s, w, r)
			s.ribbon = rb
			slide(s, rb, UDim2.new(0.5, -math.floor((w + 14) / 2), 1, -25), 0, 8, 0.22, true)
		end)
	end
	if s.res.new == true then
		cue(s, newAt, function()
			showNew(s)
		end)
	end
	-- (the egg's title goes and nothing takes its place: the request of 2026-11-14, "remove the it hatched text")
	local old = s.title
	if old then
		old:Destroy()
		s.title = nil
	end
end

-- The plates at the right: its passive on top (shown as it hatches: the request of 2026-11-14, "also, show the passive
-- of creatures when hatching eggs, above all mutations. if no mutations, show this tab instead of the no mutations
-- tab"), each of its mutations under it as the taps reveal them. Slot 0 is the passive's, kept free till it hatches.
local PLATE_W, PLATE_H = 122, 22
-- The passive's plate: as wide as its words, but never past the room right of the driftling (a phone): there its
-- words wrap onto more lines and the plate grows taller.
local function passiveBox(s: Scene): (number, number, { string })
	local w = canvasSize()
	local def = Creatures.byId[s.res.sp]
	if def == nil then
		return PLATE_W, PLATE_H, {}
	end
	local words = Traits.describe(def.passive.fx)
	local room = math.max(PLATE_W, w - (math.floor(w / 2) + 78) - 6)
	local width = math.min(room, math.max(PLATE_W, 15 + math.max(UIKit.textWidth(def.passive.name), UIKit.textWidth(words)) + 5))
	local lines: { string } = {}
	local cur = ""
	for word in string.gmatch(words, "%S+") do
		local try = if cur == "" then word else cur .. " " .. word
		if cur ~= "" and 15 + UIKit.textWidth(try) + 5 > width then
			table.insert(lines, cur)
			cur = word
		else
			cur = try
		end
	end
	if cur ~= "" then
		table.insert(lines, cur)
	end
	return width, 12 + math.max(1, #lines) * 10, lines
end
local function plateAt(s: Scene, slot: number, width: number): (number, number)
	local w, h = canvasSize()
	local x = math.min(w - width - 6, math.floor(w / 2) + 78)
	local _, ph = passiveBox(s)
	local total = ph + 3 + #s.res.muts * (PLATE_H + 3)
	local y0 = math.floor((h - total) / 2) - 6
	return x, if slot == 0 then y0 else y0 + ph + 3 + (slot - 1) * (PLATE_H + 3)
end

-- Sparkles running along a plate's top edge (a rare mutation): n bits of its colour from its left end to its right,
-- over the plate.
local function sparkleAlong(s: Scene, x: number, y: number, width: number, color: string, n: number)
	for k = 1, n do
		local d = addDot(s, if k % 2 == 0 then "white" else color, nil, x + 2, y + 1, width * (1.6 + k * 0.1), 0, 0, 0.5)
		if d then
			d.x -= k * 5
			d.gui.ZIndex = 36
		end
	end
end

-- Its passive on the top plate: a star, its name in the accent and what it does ("+35% at shops, +45% sell price"),
-- sliding in past its place and back with a starburst over its star.
local function showPassive(s: Scene)
	local def = Creatures.byId[s.res.sp]
	if def == nil or s.passive then
		return
	end
	local width, height, lines = passiveBox(s)
	local words = table.concat(lines, "\n")
	local x, y = plateAt(s, 0, width)
	local f = UIKit.glass(s.root, UDim2.fromOffset(width, height), UDim2.fromOffset(x + 30, y), 2)
	f.Name = "HatchPassive"
	f.ZIndex = 33
	f:SetAttribute("Slot", 0)
	f:SetAttribute("PlateW", width)
	table.insert(s.plates, f)
	s.passive = true
	slide(s, f, UDim2.fromOffset(x, y), 34, 0, 0.28, true)
	PixelSprites.image(f, "mini_star", UDim2.fromOffset(3, 2), 34)
	UIKit.text(f, def.passive.name, UDim2.fromOffset(width - 19, 10), UDim2.fromOffset(15, 1), { color = UIKit.color("accent"), z = 34, name = "Name" })
	UIKit.text(f, words, UDim2.fromOffset(width - 19, height - 12), UDim2.fromOffset(15, 11), { color = UIKit.color("text"), z = 34, name = "Blurb", y = "top" })
	Audio.play("ding", { pitch = 1.2 })
	cue(s, s.clock + 0.2, function()
		starburst(s, x + 8, y + 7, UIKit.color("accent"), if s.r >= 4 then 8 else 4, if s.r >= 4 then 8 else 6, 0.4)
		if s.r >= 4 then
			sparkleAlong(s, x, y, width, "accent", 5)
		end
	end)
end

-- One more of its mutations, on a plate sliding in at the right under the passive's, past its place and back: its
-- name and stars in its tier's colour, what it does under it; a starburst of its tier's colour over its stars (from
-- tier 1; sparkles along the plate from tier 3; a white blink over it at tier 4).
local function showMut(s: Scene, i: number)
	local muts = s.res.muts
	local x, y = plateAt(s, i, PLATE_W)
	local f = UIKit.glass(s.root, UDim2.fromOffset(PLATE_W, PLATE_H), UDim2.fromOffset(x + 30, y), 2)
	f.Name = "HatchMut_" .. i
	f.ZIndex = 33
	f:SetAttribute("Slot", i)
	f:SetAttribute("PlateW", PLATE_W)
	table.insert(s.plates, f)
	slide(s, f, UDim2.fromOffset(x, y), 34, 0, 0.28, true)
	local m = Traits.byId[muts[i]]
	if m then
		local tier = m.tier
		TierStars.label(f, m.name, tier, 4, 1, { z = 34, name = "Name" })
		UIKit.text(f, m.blurb, UDim2.fromOffset(PLATE_W - 8, 10), UDim2.fromOffset(4, 11), { color = UIKit.color("text_dim"), z = 34, name = "Blurb" })
		Audio.play(if tier >= 3 then "sparkle" elseif tier == 0 then "flip" else "ding", { pitch = 0.9 + tier * 0.08 })
		local col = Traits.TIER_COLOR[tier] or "text"
		cue(s, s.clock + 0.2, function()
			if s.closing then
				return
			end
			if tier >= 1 then
				local sw = TierStars.width(tier)
				local sx = x + 4 + TierStars.measure(m.name, tier) - math.floor(sw / 2)
				starburst(s, sx, y + 6, UIKit.color(col), if tier >= 2 then 8 else 4, 4 + tier * 2, 0.35 + tier * 0.04)
			end
			if tier >= 3 then
				sparkleAlong(s, x, y, PLATE_W, col, 2 + tier)
			end
			if tier >= 4 then
				local blink = UIKit.rect(f, UDim2.new(1, -2, 1, -2), UDim2.fromOffset(1, 1), UIKit.color("white"), 36)
				blink.Name = "Blink"
				blink.BackgroundTransparency = 0.4
				cue(s, s.clock + 0.06, function()
					blink.BackgroundTransparency = 0.7
				end)
				cue(s, s.clock + 0.12, function()
					blink:Destroy()
				end)
			end
		end)
		if tier >= 2 then
			for k = 1, tier * 4 do
				local a = k / (tier * 4) * math.pi * 2
				addDot(s, col, nil, x + 8, y + PLATE_H / 2, math.cos(a) * 40, math.sin(a) * 40, 30, 0.5)
			end
		end
	end
end

-- The hint at the foot of the screen, blinking: what a tap does now.
local function setHint(s: Scene, text: string)
	local old = s.hint
	if old then
		old:Destroy()
	end
	s.hint = UIKit.text(s.root, text, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 1, -13), { x = "center", color = UIKit.color("text_dim"), z = 33, name = "HatchHint" })
end

-- The screen changed size while the scene shows (the user's report of 2026-11-14: "it sometimes doesnt center the
-- text here"): the words follow by themselves (scale), the plates and the "New!" tag are placed again for the new
-- size (any slide they were in ends there) and the sky is painted again round where the egg now is.
local function relayout(s: Scene)
	if scene ~= s or s.closing then
		return
	end
	local function settle(gui: GuiObject)
		for i = #s.moveList, 1, -1 do
			if s.moveList[i].gui == gui then
				table.remove(s.moveList, i)
			end
		end
	end
	for _, f in s.plates do
		local slot, width = f:GetAttribute("Slot"), f:GetAttribute("PlateW")
		if typeof(slot) == "number" and typeof(width) == "number" then
			settle(f)
			local x, y = plateAt(s, slot, width)
			f.Position = UDim2.fromOffset(x, y)
		end
	end
	local tag = s.root:FindFirstChild("HatchNew")
	local nm = s.name
	if tag and tag:IsA("GuiObject") and nm then
		settle(tag)
		local bx, by = newTagAt(nm)
		tag.Position = UDim2.fromOffset(bx, by)
	end
	backdrop(s)
end

------------------------------------------------------------------ the taps
-- Where the newest cracks are now (their middle), for the flare and the sparks.
local function crackPoint(s: Scene): Vector3
	local sum, n = Vector3.zero, 0
	for _, k in s.cracks do
		if k.stage == s.crack then
			sum += (s.cf * k.off).Position
			n += 1
		end
	end
	return if n > 0 then sum / n else s.mid
end

-- A crack opening (every reveal tap): it squashes and springs back, a flare where the crack opens, sparks from there,
-- the rays out of the cracks flare anew, a pedestal ring; from rare up a thin shockwave.
local function crackFx(s: Scene, k: number)
	squash(s, 0.7 * k)
	local p = crackPoint(s)
	local px, py = PixelRenderer.projectPixel(p)
	addStar(s, FLARE, px, py, 0.22)
	burst(s, p, s.r, 6 + s.r * 2, 45)
	for _, b in s.beams do
		b.life = 0
	end
	HatchBackdrop.pulse()
	if s.r >= 3 then
		local ex, ey = PixelRenderer.projectPixel(s.mid)
		wave(s, ex, ey, hexOf(RAY[s.r][2]), s.eggPx * 0.9, s.eggPx * 2.6, 1, 0.55, 0.36)
	end
end

-- A step up: the egg leaps up spinning in the next rarity's colours (its cracks as far as they had got) and comes back
-- down, a flash of that colour, god rays fanning out in it, two shockwaves, a jolt, its light and its sky, sparks and
-- stars flying out, a chime a step higher each time, the title the new rarity alone ("Epic") dropping in.
local function rise(s: Scene, r: number)
	s.r = math.clamp(r, 1, Traits.RMAX)
	s.rises += 1
	newEgg(s, s.r)
	newRays(s, if s.r >= 3 then s.r else 0)
	DayLight.hold(GRADE[s.r])
	backdrop(s)
	local col = rarColor(s.r)
	flash(s, 0.5, col:Lerp(UIKit.color("white"), 0.35), 0.4)
	s.kickAt, s.kick = s.clock, 1
	s.riseAt, s.riseDown = s.clock, false
	squash(s, -0.9)
	s.lightAt, s.lightK = s.clock, 1
	jolt(s, 1 + math.floor(s.r / 3))
	burst(s, eggMiddle(s.r), s.r, 18 + s.r * 4, 70)
	local px, py = PixelRenderer.projectPixel(eggMiddle(s.r))
	local _, H = canvasSize()
	wave(s, px, py, hexOf(RAY[s.r][1]), s.eggPx, H * 0.55, 1, 0.8, 0.55)
	wave(s, px, py, hexOf(RAY[s.r][2]), s.eggPx * 0.8, H * 0.38, 1, 0.6, 0.7)
	for k = 1, 4 + s.r do
		local a = k / (4 + s.r) * math.pi * 2
		addStar(s, twinkle(s.r), px + math.cos(a) * 22, py + math.sin(a) * 16, 0.7, math.sin(a) * 34, math.cos(a) * 46)
	end
	Audio.play("level_up")
	Audio.play("rare")
	Audio.play("ding", { pitch = 0.95 + 0.12 * s.rises, volume = 1.4 })
	local rar = Traits.RARITY[s.r] or Traits.RARITY[1]
	setTitle(s, rar.name, rar.color, true)
end

-- It hatches: a flash, shockwaves, the top flies off, bits of shell scatter, confetti, the god rays at full, the
-- picture jolts and, from legendary up, slow motion; what hatched comes out of the shell (stepPal) and its card comes
-- in piece by piece (cues), all by the rarity it hatched as.
local function hatch(s: Scene)
	local r = s.r
	local g = glory(r)
	local c = s.clock
	s.phase = "hatched"
	s.topOff = c
	s.hatchAt = s.real
	s.hush = 0
	local mid = eggMiddle(r)
	local look = EggModels.LOOK[r] or EggModels.LOOK[1]
	Audio.play("crack_open")
	Audio.play("pop", { pitch = 0.8 })
	if r >= 3 then
		Audio.play("rare")
	end
	if r >= 4 then
		Audio.play("reward")
	end
	if g.slow > 0 then
		s.slowUntil = s.real + g.slow
	end
	flash(s, g.flash, nil, 0.25 + 0.03 * r)
	burst(s, mid, r, g.sparks, 90)
	s.lightAt, s.lightK = c, 1
	local ex, ey = PixelRenderer.projectPixel(mid)
	local W, H = canvasSize()
	-- (the shockwaves reach further the rarer it is: a common one's a ring round it, a celestial one's off the screen)
	local far = math.sqrt(W * W + H * H) * 0.6 * math.min(1, 0.3 + 0.1 * r)
	for k = 1, g.rings do
		local col = hexOf(if k % 2 == 1 then "white" else RAY[r][2])
		cue(s, c + (k - 1) * 0.07, function()
			wave(s, ex, ey, col, s.eggPx * 0.8, far * (0.5 + 0.5 * k / g.rings), 1, 0.85 - k * 0.08, 0.55 + k * 0.08)
		end)
	end
	-- (a ring of dust over the pedestal)
	wave(s, s.baseX, s.baseY, hexOf("cream"), s.baseW * 0.5, s.baseW * 1.45, 0.42, 0.55, 0.5)
	HatchBackdrop.pulse()
	local bits = Blocks.model(nil, "HatchShards")
	for k = 1, g.shards do
		local a = k / g.shards * math.pi * 2 + math.random() * 0.4
		local sz = 0.14 + math.random() * 0.14
		local p = Blocks.part(bits, { size = Vector3.new(sz, sz * 0.6, sz), cf = CFrame.new(mid), color = if k % 3 == 0 then look.mark else look.body, collide = false, query = false, name = "Shard" })
		local v = Vector3.new(math.cos(a) * (2 + math.random() * 2.5), 3 + math.random() * 3, math.sin(a) * (2 + math.random() * 2.5))
		table.insert(s.shards, { p = p, v = v, w = (math.random() - 0.5) * 14, at = mid, born = c })
	end
	bits.Parent = s.dyn
	PixelRenderer.registerDynamic(bits)
	-- what hatched: a white silhouette at first, small in the shell
	local thing = MicroModels.species(s.res.sp)
	MicroModels.scale(thing, Vector3.one * 0.3)
	MicroModels.recolor(thing, "white")
	thing.model.Parent = s.dyn
	PixelRenderer.registerDynamic(thing.model)
	s.pal = thing
	s.popAt = c + 0.03
	s.whiteUntil = c + 0.1 + 0.035 * r
	jolt(s, g.jolt)
	for k = 1, g.confetti do
		local pair = CONFETTI[(k % #CONFETTI) + 1]
		local d = addDot(s, pair[1], nil, math.random(0, W), -math.random(0, 60), (math.random() - 0.5) * 30, 20 + math.random() * 40, 18, 2.4 + math.random())
		if d then
			d.alt = UIKit.color(pair[2])
		end
	end
	-- the card, piece by piece
	local tName = if r >= 3 then 0.3 else 0.12
	cue(s, c + tName, function()
		showName(s)
	end)
	cue(s, c + tName + (if r >= 3 then 0.35 else 0.15), function()
		showPassive(s)
	end)
	local hint = s.hint
	if hint then
		hint:Destroy()
		s.hint = nil
	end
end

-- The cracks lit from inside in the rarity's light: nothing is left to reveal, the next tap hatches it.
local function glow(s: Scene)
	if s.glowing or s.egg == nil then
		return
	end
	s.glowing = true
	s.blaze = 0
	-- (white hot, and more rays: stepBeams)
	for _, k in s.cracks do
		k.p.Color = Blocks.color("white")
	end
	PixelRenderer.refreshDynamic(s.egg :: Model)
end

-- The whole card at once (a tap while what hatched comes out): every piece still to come, every slide at its end.
local function finish(s: Scene)
	local guard = 0
	while #s.cues > 0 and guard < 200 do
		guard += 1
		table.sort(s.cues, function(a: Cue, b: Cue): boolean
			return a.at < b.at
		end)
		local cu = table.remove(s.cues, 1) :: Cue
		cu.fn()
	end
	for _, mv in s.moveList do
		mv.gui.Position = mv.to
	end
	table.clear(s.moveList)
	s.slowUntil = 0
end

local closeScene: (s: Scene) -> ()

-- A tap: the next step up or mutation; with nothing left, it hatches; a tap in the build-up breaks it at once, one
-- while what hatched comes out shows its whole card; once that is done, back to the island.
function HatchScene.skip()
	local s = scene
	if s == nil or s.closing then
		return
	end
	if s.real - s.tapAt < TAP_GAP then
		return
	end
	if s.phase == "egg" and s.clock < s.wait + DROP then
		return -- (still coming down onto the pedestal)
	end
	if s.phase == "done" then
		s.lastTap, s.tapAt = s.clock, s.real
		closeScene(s)
		return
	elseif s.phase == "breaking" then
		if s.clock - s.breakAt >= 0.35 then
			s.lastTap, s.tapAt = s.clock, s.real
			hatch(s)
		end
		return
	elseif s.phase == "hatched" then
		if s.real - s.hatchAt >= 0.3 then
			s.lastTap, s.tapAt = s.clock, s.real
			finish(s)
			s.phase = "done"
			setHint(s, "Tap to go on")
		end
		return
	end
	s.lastTap, s.tapAt = s.clock, s.real
	local nxt = table.remove(s.queue, 1)
	if nxt == nil then
		-- (the request of 2026-11-14: "Make eggs shake while being cracked open": every crack lit, it shakes harder
		-- and harder for its build-up, crunching, then the shell opens)
		s.phase = "breaking"
		s.breakAt = s.clock
		s.build = glory(s.r).build
		s.tick = s.clock + 0.15
		s.crack = 3
		glow(s)
		squash(s, 0.6)
		Audio.play("crack", { pitch = 1.15 })
		if s.r >= 5 then
			Audio.play("thunder", { volume = 0.45, pitch = 0.7 })
		end
		local hint = s.hint
		if hint then
			hint:Destroy()
			s.hint = nil
		end
		return
	end
	s.crack = math.min(3, s.crack + 1)
	Audio.play("crack", { pitch = 0.9 + s.crack * 0.07 })
	if nxt.kind == "rise" then
		crackFx(s, 0.4)
		rise(s, nxt.r or s.r + 1)
	else
		s.kickAt, s.kick = s.clock, 0.6
		s.shown += 1
		showMut(s, s.shown)
		crackFx(s, 1)
		flash(s, 0.1, nil, 0.16)
	end
	if #s.queue == 0 then
		glow(s)
		setHint(s, "Tap to hatch")
	end
end

------------------------------------------------------------------ every frame
-- The egg comes down on the pedestal (k: how hard, 1 the first time): a thud, it squashes on its foot, a puff of dust
-- either side of it and a ring of dust over the pedestal, a pedestal ring, a little shake; the first time from rare up
-- the picture jolts and from legendary up twinkles skip out over the pedestal.
local function landed(s: Scene, k: number)
	Audio.play("pop", { pitch = 0.5 + (1 - k) * 0.2 })
	s.kickAt, s.kick = s.clock, 0.35 * k
	squash(s, k)
	local fx, fy = PixelRenderer.projectPixel(at(0, FLOAT_Y, 0))
	local g = glory(s.r)
	for i = 1, math.floor((10 + s.r * 2) * k) do
		local side = if i % 2 == 0 then 1 else -1
		addDot(s, if i % 3 == 0 then "cream" else "white", nil, fx + side * (6 + math.random(0, 6)), fy - math.random(0, 2), side * (18 + math.random() * 22), -(10 + math.random() * 14), 50, 0.45 + math.random() * 0.25)
	end
	wave(s, s.baseX, s.baseY, hexOf("cream"), s.baseW * 0.45, s.baseW * (1.1 + 0.3 * k), 0.42, 0.5 * k, 0.45)
	if k >= 1 then
		jolt(s, if s.r >= 3 then math.max(1, math.floor(g.jolt / 2)) else 0)
		if s.r >= 5 then
			for i = 1, 6 do
				local a = i / 6 * math.pi * 2
				addStar(s, twinkle(s.r), fx + math.cos(a) * 8, fy + math.sin(a) * 3, 0.5, math.sin(a) * 12, math.cos(a) * 60)
			end
		end
	else
		HatchBackdrop.pulse()
	end
end

-- How squashed the egg is now (+ squashed, - stretched): the last squash springing back, its breath while it waits,
-- swelling in pulses as it is about to burst.
local function squashOf(s: Scene, c: number): number
	local q = 0
	local k = c - s.squashAt
	if k >= 0 and k < 0.7 then
		q = s.squashK * math.exp(-7 * k) * math.cos(k * 20)
	end
	if s.phase == "egg" and s.arrived and c >= s.landAt then
		q += 0.03 * math.sin((c - s.landAt) * 2.4)
	elseif s.phase == "breaking" then
		local u = math.clamp((c - s.breakAt) / s.build, 0, 1)
		q -= 0.07 * u * math.abs(math.sin((c - s.breakAt) * (10 + 16 * u)))
	end
	return q
end

local function stepEgg(s: Scene, c: number, d: number)
	local r = s.r
	local eh = EGG_H[r] or 2.4
	-- resting on the pedestal, the faintest sway. Each tap that cracks it shakes it (rocking side to side on its foot
	-- and jumping sideways, a step up's the hardest), dying away; once every crack is lit it trembles, waiting; the tap
	-- that hatches it shakes it harder and faster until the shell opens (its build-up). While it waits it wobbles
	-- now and then, asking to be tapped, more often and harder the longer it waits, and after a while with a hop.
	local bob = 0
	local tilt = math.sin(c * 1.1) * 0.012
	local rock, side, amp = 0, 0, 0
	local spin = 0
	local k = c - s.kickAt
	if s.phase == "breaking" then
		local b = c - s.breakAt
		local u = math.clamp(b / s.build, 0, 1)
		amp = 0.55 + 0.9 * u * u
		local ph = b * (36 + 34 * u)
		rock = math.sin(ph) * 0.2 * amp
		side = math.sin(ph * 1.37 + 1) * 0.1 * amp
		bob += math.abs(math.sin(ph * 0.5)) * 0.05 * amp
		-- (from epic up it lifts off the pedestal as it shakes)
		if r >= 4 then
			bob += 0.22 * ease(u)
		end
	elseif k >= 0 and k < 0.6 then
		amp = s.kick * (1 - k / 0.6)
		rock = math.sin(k * 42) * 0.22 * amp
		side = math.sin(k * 55) * 0.12 * amp
		bob += math.abs(math.sin(k * 21)) * 0.06 * amp
	elseif s.phase == "egg" and s.glowing then
		amp = 0.15
		rock = math.sin(c * 34) * 0.035
		side = math.sin(c * 47 + 2) * 0.02
	elseif s.phase == "egg" and s.arrived then
		local idle = c - math.max(s.landAt, s.lastTap)
		local every = math.max(1.1, 2.6 - idle * 0.16)
		s.wob += d / every
		local w = (s.wob % 1) * every
		if w < 0.45 then
			local hard = 0.05 + math.min(0.05, idle * 0.006)
			tilt += math.sin(w / 0.45 * math.pi * 2) * hard
			if idle > 6 then
				bob += 0.12 * math.sin(w / 0.45 * math.pi)
			end
		end
	end
	s.shake = amp
	-- a step up: it leaps up spinning and comes back down
	local kr = c - s.riseAt
	if kr >= 0 and kr < RISE_T then
		local u = kr / RISE_T
		bob += RISE_H * 4 * u * (1 - u)
		spin = math.pi * 2 * (1 - (1 - u) ^ 3)
	end
	-- (the shake goes across the screen: the camera's right, flat, and a rock about the line it looks along)
	local cam = workspace.CurrentCamera
	local rv = if cam then cam.CFrame.RightVector else Vector3.xAxis
	local right = Vector3.new(rv.X, 0, rv.Z)
	right = if right.Magnitude > 1e-3 then right.Unit else Vector3.xAxis
	local fwd = Vector3.new(-right.Z, 0, right.X)
	local lift = liftOf(s, c)
	local foot = at(0, footY(r) + bob + lift, 0) + right * side
	local cf = CFrame.new(foot) * CFrame.fromAxisAngle(fwd, rock) * CFrame.Angles(tilt, 0, tilt * 0.6) * CFrame.Angles(0, spin, 0)
	s.cf = cf
	local off = s.topOff
	-- its squash: wider and lower, or thinner and taller (in steps of a hundredth, so it is not re-sized every frame)
	local q = if off then 0 else math.floor(squashOf(s, c) * 100 + 0.5) / 100
	local sx, sy = 1 + 0.08 * q, 1 - 0.13 * q
	local resize = q ~= s.sq
	s.sq = q
	s.mid = (cf * CFrame.new(0, eh * 0.5 * sy, 0)).Position
	for i, rp in s.parts do
		local o = rp.off
		local here = cf * CFrame.new(o.X * sx, o.Y * sy, o.Z * sx) * o.Rotation
		if resize then
			local base = s.sizes[i]
			if base then
				rp.p.Size = base * sx
			end
		end
		if off then
			local u = (c - off) / 0.6
			if table.find(s.top, rp.p) then
				here = cf * CFrame.new(1.1 * u, eh * (1.1 * u - 0.8 * u * u), 0.7 * u) * CFrame.Angles(0, 0, -2.6 * u) * rp.off
			else
				-- (the rest of the shell falls away under what hatched)
				here = here - Vector3.new(0, ease(u) * eh * 1.6, 0)
			end
		end
		rp.p.CFrame = here
	end
	for i, kk in s.cracks do
		local o = kk.off
		if resize then
			local base = s.crackSizes[i]
			if base then
				kk.p.Size = base * sx
			end
		end
		kk.p.CFrame = if off == nil and kk.stage <= s.crack then cf * CFrame.new(o.X * sx, o.Y * sy, o.Z * sx) * o.Rotation else CFrame.new(foot - Vector3.new(0, 30, 0))
	end
	if off and c - off > 0.6 and s.egg then
		dropEgg(s)
	end
	-- the rarity's lights on the egg: motes circling it, a halo turning over it, a ring of lights orbiting it
	local er = 0.37 * eh
	for _, f in s.fx do
		if off then
			f.p.CFrame = CFrame.new(foot - Vector3.new(0, 30, 0))
		elseif f.kind == "mote" then
			local a = c * 1.5 + f.k * math.pi * 2 / 3
			f.p.CFrame = cf * CFrame.new(math.cos(a) * er * 1.45, eh * (0.45 + 0.12 * math.sin(c * 2.1 + f.k * 2)), math.sin(a) * er * 1.45)
		elseif f.kind == "halo" then
			local a = c * 0.9 + f.k / 20 * math.pi * 2
			f.p.CFrame = cf * CFrame.new(math.cos(a) * er * 0.75, eh + 0.45 + 0.05 * math.sin(c * 2), math.sin(a) * er * 0.75)
		elseif f.kind == "orbit" then
			-- (a celestial egg's ring of lights: round its middle, tilted like a planet's ring)
			local a = c * 0.7 + f.k / 28 * math.pi * 2
			f.p.CFrame = cf * CFrame.new(math.cos(a) * er * 1.7, eh * 0.5 + math.cos(a) * er * 0.45, math.sin(a) * er * 1.7)
		elseif f.kind == "beam" then
			local hb = 3.4 + 0.6 * math.sin(c * 1.9)
			f.p.Size = Vector3.new(0.3, Blocks.snap(hb), 0.3)
			f.p.CFrame = cf * CFrame.new(0, eh + 0.2 + Blocks.snap(hb) / 2, 0)
		end
	end
	-- the build-up: the cracks blaze between white and the rarity's light, faster and faster
	if s.phase == "breaking" and s.egg and r >= 2 then
		local u = math.clamp((c - s.breakAt) / s.build, 0, 1)
		local want = if math.floor((c - s.breakAt) * (5 + 12 * u)) % 2 == 0 then 0 else 1
		if want ~= s.blaze then
			s.blaze = want
			for _, kk in s.cracks do
				kk.p.Color = Blocks.color(if want == 0 then "white" else RAY[r][2])
			end
			PixelRenderer.refreshDynamic(s.egg :: Model)
		end
	end
end

-- What hatched: up out of the shell as a white silhouette, stretched tall, taking its colours, a leap and down on the
-- pedestal squashing (a thud, a puff of dust, a ring, a jolt from rare up), springing back, stars circling it; then it
-- stands where the egg was.
local function stepPal(s: Scene, c: number)
	local thing = s.pal
	local pop = s.popAt
	if thing == nil or pop == nil then
		return
	end
	local g = glory(s.r)
	local k = c - pop
	local air = 0.32 + 0.02 * s.r
	local grow, sx, sy, hop = 1, 1, 1, 0
	if k < 0 then
		grow = 0.3
		sx, sy = 0.8, 1.3
	elseif k < POP_UP then
		local u = k / POP_UP
		grow = 0.3 + 0.7 * ease(u)
		sx, sy = 0.78 + 0.1 * u, 1.32 - 0.12 * u
		hop = 0.18 * u
	elseif k < POP_UP + air then
		local u = (k - POP_UP) / air
		hop = (1 - u) * 0.18 + g.hop * 4 * u * (1 - u)
		-- (stretched by its speed, round at the top of its leap)
		local v = math.abs(1 - 2 * u)
		sx, sy = 1 - 0.12 * v, 1 + 0.2 * v
	else
		if not s.palDown then
			s.palDown, s.palLand = true, c
			Audio.play("pop", { pitch = 0.6 })
			Audio.play("jump", { pitch = 0.9 })
			local fx, fy = PixelRenderer.projectPixel(at(0, FLOAT_Y, 0))
			for i = 1, 8 + s.r do
				local side = if i % 2 == 0 then 1 else -1
				addDot(s, if i % 3 == 0 then "cream" else "white", nil, fx + side * (5 + math.random(0, 5)), fy - math.random(0, 2), side * (14 + math.random() * 20), -(8 + math.random() * 12), 50, 0.4 + math.random() * 0.2)
			end
			wave(s, s.baseX, s.baseY, hexOf("cream"), s.baseW * 0.35, s.baseW * 1.2, 0.42, 0.45, 0.4)
			HatchBackdrop.pulse()
			jolt(s, if s.r >= 3 then 1 else 0)
			-- stars circling it (uncommon up): round above its middle, a flat ring
			if g.stars > 0 then
				local cx, cy = PixelRenderer.projectPixel(at(0, FLOAT_Y + 0.75 * PAL_SCALE, 0))
				for i = 1, g.stars do
					local st = addStar(s, twinkle(s.r), cx, cy, if s.r >= 5 then 600 else 2.6, 0, 0)
					st.loop = 0.5 + (i % 3) * 0.12
					st.orbit = { cx, cy, s.eggPx * 1.7, s.eggPx * 0.42, i / g.stars * math.pi * 2, 1.6 }
				end
			end
		end
		local t = c - s.palLand
		if t < 0.6 then
			local q = 0.9 * math.exp(-7 * t) * math.cos(t * 22)
			sx, sy = 1 + 0.2 * q, 1 - 0.28 * q
		end
	end
	if s.whiteUntil > 0 and c >= s.whiteUntil then
		s.whiteUntil = 0
		MicroModels.recolor(thing, nil)
		PixelRenderer.refreshDynamic(thing.model)
	end
	local sc = PAL_SCALE * grow
	MicroModels.scale(thing, Vector3.new(sx * sc, sy * sc, sx * sc))
	-- (idle from the start: no jump for joy once it lands, the request of 2026-11-16, "remove the creatures celebrating
	-- after hatching, just make them idle from the start of hatching")
	MicroModels.animate(thing, c, "idle", 0)
	-- (turned three quarters, as its portrait: the world's view is from yaw 45, so 45 degrees faces us square on and
	-- 30 more shows the face and the side of the body; the request of 2026-11-16, "could the creatures appear at a 3/4
	-- angle instead of facing the player?")
	MicroModels.place(thing, CFrame.new(at(0, FLOAT_Y + hop, 0)) * CFrame.Angles(0, math.pi / 4 + PAL_TURN, 0))
end

-- Bits of shell: flying out and falling away out of the picture (nothing to land on).
local function stepShards(s: Scene, c: number, dt: number)
	local keep: { Shard } = {}
	for _, sh in s.shards do
		local age = c - sh.born
		if age > 2 then
			sh.p:Destroy()
			continue
		end
		sh.v -= Vector3.new(0, 18 * dt, 0)
		sh.at += sh.v * dt
		sh.p.CFrame = CFrame.new(sh.at) * CFrame.Angles(sh.w * age * 0.3, sh.w * age, 0)
		table.insert(keep, sh)
	end
	s.shards = keep
end

local function stepDots(s: Scene, dt: number)
	local keep: { Dot } = {}
	for _, d in s.dots do
		local age = s.clock - d.born
		if age >= d.life then
			d.gui:Destroy()
			continue
		end
		local orb = d.orbit
		if orb then
			-- (circling: hidden while it passes behind what hatched)
			local a = orb[5] + orb[6] * age
			local ca, sa = math.cos(a), math.sin(a)
			d.x, d.y = orb[1] + ca * orb[3] - d.hw, orb[2] + sa * orb[4] - d.hh
			d.gui.Visible = not (sa < -0.2 and math.abs(ca) < 0.55)
		else
			d.vy += d.g * dt
			local sway = if d.alt then math.sin(age * 5 + d.ph * 6) * 10 else 0
			d.x += (d.vx + sway) * dt
			d.y += d.vy * dt
		end
		d.gui.Position = UDim2.fromOffset(math.floor(d.x), math.floor(d.y))
		local alt, col = d.alt, d.col
		if alt and col then
			-- (a bit of confetti turning: its two sides in turn)
			d.gui.BackgroundColor3 = if math.floor(age * 9 + d.ph * 2) % 2 == 0 then col else alt
		end
		local fr = d.frames
		if fr then
			local lp = d.loop
			local k = if lp then math.floor(age / lp * #fr) % #fr + 1 else math.clamp(math.floor(age / d.life * #fr) + 1, 1, #fr)
			for i, f in fr do
				f.Visible = i == k
			end
		end
		table.insert(keep, d)
	end
	s.dots = keep
end

-- The starbursts: each pixel shows from when the ray reaches it (a tenth of a second to the tip) till it goes, the
-- inner ones first.
local function stepBursts(s: Scene, c: number)
	local keep: { Burst } = {}
	for _, b in s.bursts do
		local age = c - b.born
		if age >= b.life then
			for _, f in b.px do
				f:Destroy()
			end
			continue
		end
		for i, f in b.px do
			local j = b.j[i]
			f.Visible = age >= 0.1 * j and age < 0.12 + (b.life - 0.12) * j
		end
		table.insert(keep, b)
	end
	s.bursts = keep
end

local function stepMoves(s: Scene, c: number)
	local keep: { Move } = {}
	for _, mv in s.moveList do
		if mv.gui.Parent == nil then
			continue
		end
		local u = math.clamp((c - mv.born) / mv.dur, 0, 1)
		local e = if mv.over then back(u) else ease(u)
		local to = mv.to
		mv.gui.Position = UDim2.new(to.X.Scale, to.X.Offset + math.floor(mv.dx * (1 - e) + 0.5), to.Y.Scale, to.Y.Offset + math.floor(mv.dy * (1 - e) + 0.5))
		if u < 1 then
			table.insert(keep, mv)
		end
	end
	s.moveList = keep
end

local function stepCues(s: Scene, c: number)
	local due: { Cue } = {}
	local keep: { Cue } = {}
	for _, cu in s.cues do
		table.insert(if cu.at <= c then due else keep, cu)
	end
	if #due == 0 then
		return
	end
	s.cues = keep
	table.sort(due, function(a: Cue, b: Cue): boolean
		return a.at < b.at
	end)
	for _, cu in due do
		cu.fn()
	end
end

local function stepFlash(s: Scene, c: number)
	local f = s.flash
	if f == nil or not f.Visible then
		return
	end
	local u = (c - s.flashAt) / s.flashT
	if u >= 1 then
		f.Visible = false
		return
	end
	f.BackgroundTransparency = 1 - s.flashK * (1 - math.floor(u * 4) / 4)
end

-- The picture jolting: the pixel layer, the painted sky with its light and the overlay all together, by whole art px,
-- dying away over a third of a second.
local function stepJolt(s: Scene, c: number)
	local k = c - s.joltAt
	local dx, dy = 0, 0
	if k >= 0 and k < 0.32 and s.joltK > 0 then
		local a = s.joltK * (1 - k / 0.32)
		local n = math.floor(k / 0.04)
		dx = math.floor((if n % 2 == 0 then a else -a) + 0.5)
		dy = math.floor((if n % 3 == 0 then -a else a) * 0.6 + 0.5)
	end
	if dx ~= s.jx or dy ~= s.jy then
		s.jx, s.jy = dx, dy
		PixelRenderer.setOffset(dx, dy)
		HatchBackdrop.offset(dx, dy)
		s.root.Position = UDim2.fromOffset(dx, dy)
	end
end

-- What drifts in the air (1 px dots): by day (a common or uncommon egg's sky) seeds and petals blowing across, by
-- night fireflies rising and blinking; under the rose night pink petals falling slowly (thick for a while after a
-- mythic hatch), under the starry sky white and cyan motes rising (and after a celestial hatch glints raining down).
local function fireflies(s: Scene, c: number)
	local off = s.topOff
	local after = off ~= nil and c - (off :: number) < 3.5
	local w, h = canvasSize()
	if s.r >= 7 and after and math.random() < 0.3 then
		addDot(s, if math.random() < 0.5 then "white" else "screen_on", nil, math.random(0, math.max(1, w)), -2, (math.random() - 0.5) * 6, 40 + math.random() * 30, 0, h / 40)
	end
	if math.random() < (if s.r == 6 and after then 0.4 else 0.08) then
		if s.r == 6 then
			local x = math.random(0, math.max(1, w))
			local d = addDot(s, if math.random() < 0.6 then "cherry" else "pink", nil, x, -2, (math.random() - 0.3) * 8, 9 + math.random() * 6, 0, h / 10)
			if d and after then
				d.alt = UIKit.color("wall_trim")
			end
		elseif s.r >= 7 then
			local x, y = math.random(10, math.max(11, w - 10)), math.random(40, math.max(41, h - 30))
			addDot(s, if math.random() < 0.5 then "white" else "screen_on", nil, x, y, (math.random() - 0.5) * 4, -8 - math.random() * 8, 0, 2.2)
		elseif s.r <= 2 then
			local y = math.random(20, math.max(21, h - 40))
			addDot(s, if math.random() < 0.6 then "white" elseif math.random() < 0.5 then "pink" else "cream", nil, -2, y, 14 + math.random() * 10, (math.random() - 0.5) * 4, 1, w / 14)
		else
			local x, y = math.random(10, math.max(11, w - 10)), math.random(30, math.max(31, h - 50))
			addDot(s, if math.random() < 0.5 then "yellow" else "cream", nil, x, y, (math.random() - 0.5) * 8, -4 - math.random() * 6, 0, 1.6)
		end
	end
end

-- Rays of light streaming out of the cracks (the requests of 2026-11-14: "cracks sometimes become filled like this, can
-- you make it such that light streams out instead when this happens?", then "make light stream out, as in rays of
-- light streaming out, like the image"): thin rays from places along the cracks shown, fanning out away from the egg's
-- middle. A ray is a 1 px line on one of sixteen clean pixel-art slopes (flat, 2:1, 1:1, 1:2, upright: even steps,
-- no jaggies), white at the crack, then the rarity's light, fading out in four steps toward its tip. It grows out
-- fast, holds, dims, and goes, and another comes from somewhere else on the cracks. More rays and longer as the egg
-- cracks further, the most and the whitest once every crack glows, more still through the build-up. A tap lets them
-- all out anew (crackFx).
local BEAM_DIRS: { { number } } = {
	{ 1, 0 }, { 2, 1 }, { 1, 1 }, { 1, 2 }, { 0, 1 }, { -1, 2 }, { -1, 1 }, { -2, 1 },
	{ -1, 0 }, { -2, -1 }, { -1, -1 }, { -1, -2 }, { 0, -1 }, { 1, -2 }, { 1, -1 }, { 2, -1 },
}
local BEAM_MAX = 44 -- px, the longest ray
local BEAM_FADE = { 0.05, 0.3, 0.52, 0.74 } -- how see-through each quarter of a ray is, from the crack out
local BEAM_COUNT = { 4, 7, 10 } -- rays at once by the cracks shown (14 once they glow, up to 22 in the build-up)

local function makeBeam(s: Scene): Beam
	local holder = Instance.new("Frame")
	holder.Name = "HatchBeam"
	holder.BackgroundTransparency = 1
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromOffset(1, 1)
	holder.ZIndex = 29
	holder.Visible = false
	holder.Parent = s.root
	local px: { Frame } = {}
	for i = 1, BEAM_MAX do
		local f = UIKit.rect(holder, UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0), UIKit.color("white"), 29)
		f.Visible = false
		px[i] = f
	end
	return { holder = holder, px = px, from = nil, len = 0, born = -10, life = 0, shown = 0, dim = false, placed = false }
end

-- A ray anew from a crack: its slope (outward from the egg's middle, now and then the next slope round, so they fan
-- out), its length, its pixels' places, colours and fade.
local function seedBeam(s: Scene, b: Beam, from: BasePart, mx: number, my: number, c: number)
	local fx, fy = PixelRenderer.projectPixel(from.Position)
	local a = math.atan2(fy - my, fx - mx)
	local k = math.floor(a / (math.pi * 2) * 16 + 0.5) + math.random(-1, 1)
	local d = BEAM_DIRS[k % 16 + 1]
	local dx, dy = d[1], d[2]
	local major = math.max(math.abs(dx), math.abs(dy))
	local len = if s.glowing then math.random(22, BEAM_MAX) else math.random(8 + 3 * s.crack, 16 + 7 * s.crack)
	len = math.min(len, BEAM_MAX)
	local white = if s.glowing then 0.5 else 0.25
	local light = UIKit.color(RAY[s.r][2])
	local wc = UIKit.color("white")
	for i = 1, BEAM_MAX do
		local f = b.px[i]
		f.Visible = false
		if i <= len then
			f.Position = UDim2.fromOffset(math.floor(i * dx / major), math.floor(i * dy / major))
			f.BackgroundColor3 = if i <= len * white then wc else light
			f.BackgroundTransparency = BEAM_FADE[math.min(4, math.floor((i - 1) / len * 4) + 1)]
		end
	end
	b.from, b.len, b.born, b.shown, b.dim, b.placed = from, len, c, 0, false, false
	b.life = if s.glowing then 0.3 + math.random() * 0.4 else 0.45 + math.random() * 0.5
	s.beamsMade += 1
end

-- Each ray onto its crack where the picture shows it ("some lightrays are misalinged with the cracks", 2026-11-14): the
-- pixel filter draws the egg fewer times a second than the screen, so the rays move only when it draws, from the
-- cracks as it drew them (PixelRenderer.onComposed); a new ray waits for that before it shows.
local function placeBeams(s: Scene)
	s.placedAt = s.clock
	for _, b in s.beams do
		local where = b.from
		if where and where.Parent ~= nil and b.life > 0 then
			local fx, fy = PixelRenderer.projectPixel(where.Position)
			b.holder.Position = UDim2.fromOffset(fx, fy)
			b.placed = true
		end
	end
end

local function stepBeams(s: Scene, c: number)
	local want = if s.topOff ~= nil or s.egg == nil or s.crack <= 0 then 0 elseif s.glowing then 14 else BEAM_COUNT[math.min(s.crack, #BEAM_COUNT)]
	if want > 0 and s.phase == "breaking" then
		want += math.floor(8 * math.clamp((c - s.breakAt) / s.build, 0, 1))
	end
	local from: { BasePart } = {}
	if want > 0 then
		for _, k in s.cracks do
			if k.stage <= s.crack then
				table.insert(from, k.p)
			end
		end
		if #from == 0 then
			want = 0
		end
	end
	while #s.beams < want do
		local b = makeBeam(s)
		table.insert(s.beams, b)
	end
	local mx, my = PixelRenderer.projectPixel(s.mid)
	-- (with no new picture for a while, the pixel filter off, they place themselves)
	if c - s.placedAt > 0.25 then
		placeBeams(s)
	end
	for i, b in s.beams do
		if i > want then
			b.holder.Visible = false
			b.life = 0
			continue
		end
		local src = b.from
		if src == nil or src.Parent == nil or c - b.born >= b.life then
			seedBeam(s, b, from[math.random(1, #from)], mx, my, c)
			-- (the first rays start at different points of their lives, so they don't all come and go together)
			if src == nil then
				b.born = c - math.random() * b.life * 0.5
			end
		end
		local age = c - b.born
		b.holder.Visible = b.placed
		local n = math.floor(b.len * math.min(1, age / 0.12) + 0.5)
		if n ~= b.shown then
			for j = math.min(n, b.shown) + 1, math.max(n, b.shown) do
				b.px[j].Visible = j <= n
			end
			b.shown = n
		end
		if not b.dim and age >= b.life * 0.7 then
			b.dim = true
			for j = 1, b.len do
				local f = b.px[j]
				f.BackgroundTransparency = math.min(0.92, f.BackgroundTransparency + 0.3)
			end
		end
	end
end

-- A twinkle now and then round the egg (from a rare one up), and round what hatched after: a rare one's go out a
-- moment after the hatch, an epic or legendary one's stay. Each blinks through its frames where it appeared. For a
-- while after a legendary, mythic or celestial hatch they fill the sky.
local function stepTwinkles(s: Scene, c: number)
	local off = s.topOff
	if off and s.r >= 5 and c - (off :: number) < 3 and math.random() < 0.18 then
		local w, h = canvasSize()
		addStar(s, twinkle(s.r), math.random(4, math.max(5, w - 4)), math.random(4, math.max(5, math.floor(h * 0.7))), 0.5 + math.random() * 0.4, -2)
	end
	local n = s.twinkleN
	if n <= 0 or c < s.twinkleAt then
		return
	end
	if off and s.r <= 3 and c - (off :: number) > 1.4 then
		return
	end
	local life = 0.55 + math.random() * 0.35
	s.twinkleAt = c + 0.7 / n * (0.6 + math.random() * 0.8)
	local px, py = PixelRenderer.projectPixel(if off then eggMiddle(s.r) else s.mid)
	local a = math.random() * math.pi * 2
	local x = px + math.cos(a) * (20 + math.random() * 22)
	local y = py + math.sin(a) * (16 + math.random() * 18)
	addStar(s, twinkle(s.r), math.floor(x), math.floor(y), life, -3)
end

-- The motes circling the egg while it waits (GLORY.motes, uncommon up): on a flat ring round it, rising and sinking
-- along it, in front of it on the overlay and behind it on the backdrop's light. Returns those behind (x, y, colour).
local function stepMotes(s: Scene, c: number): { number }
	local behind: { number } = {}
	local n = if s.topOff == nil and s.arrived and s.egg then glory(s.r).motes else 0
	while #s.motes < n do
		local f = UIKit.rect(s.root, UDim2.fromOffset(1, 1), UDim2.fromOffset(0, 0), UIKit.color("white"), 30)
		f.Name = "HatchMote"
		table.insert(s.motes, f)
	end
	local mx, my = PixelRenderer.projectPixel(s.mid)
	local eh = s.eggPx
	for i, f in s.motes do
		if i > n then
			f.Visible = false
			continue
		end
		local a = c * (1.2 + 0.08 * i) + i * math.pi * 2 / math.max(1, n)
		local x = mx + math.cos(a) * eh * 1.45
		local y = my + math.sin(a) * eh * 0.4 + math.sin(c * 1.3 + i * 1.7) * eh * 0.8
		local key = RAY[s.r][(i % 2) + 1]
		if math.sin(a) >= 0 then
			f.Visible = true
			f.BackgroundColor3 = UIKit.color(key)
			f.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		else
			f.Visible = false
			table.insert(behind, x)
			table.insert(behind, y)
			table.insert(behind, hexOf(key))
		end
	end
	return behind
end

-- The light behind the egg on the backdrop (HatchBackdrop.light): the god rays (epic up while it waits, rare up once
-- it glows, uncommon up through the build-up, fanning out at a step up and at the hatch and staying behind what
-- hatched from epic up), each beam's brightness a wave travelling round the fan so it seems to turn; the halo round
-- it; its shadow growing while it falls; the rings; the motes behind it; the hush.
local function stepLight(s: Scene, c: number, behind: { number })
	if not PixelRenderer.isActive() then
		return
	end
	local g = glory(s.r)
	local _, H = canvasSize()
	local r = s.r
	local cx, cy = PixelRenderer.projectPixel(eggMiddle(r))
	local off = s.topOff
	local base, share = 0, 0.5
	local halo, haloK = 0, 0
	local eh = s.eggPx
	if off then
		local t = c - (off :: number)
		base, share = (if r >= 4 then 0.6 else 0), 1
		haloK = (if r >= 4 then 0.4 else 0) + math.max(0, 1 - t / 0.7) * 0.6
		halo = eh * (2.2 + 0.8 * math.max(0, 1 - t / 0.7))
	elseif s.phase == "breaking" then
		local u = math.clamp((c - s.breakAt) / s.build, 0, 1)
		base, share = (if r >= 2 then 0.25 + 0.6 * u else 0), 0.6 + 0.4 * u
		haloK = (if r >= 3 then 0.55 else 0.35) + 0.45 * u
		halo = eh * (2.3 + 1.1 * u)
	elseif s.arrived and s.glowing then
		base, share = (if r >= 3 then 0.4 else 0), 0.6
		haloK = (if r >= 3 then 0.55 else 0.3) + 0.12 * math.sin(c * 5)
		halo = eh * (2.25 + 0.15 * math.sin(c * 5))
	elseif s.arrived then
		base = if r >= 4 then 0.3 else 0
		if r >= 3 then
			haloK = 0.45 + 0.1 * math.sin(c * 2.2)
			halo = eh * (2.0 + 0.12 * math.sin(c * 2.2))
		end
	end
	-- (a burst: they fan out from nothing and fade back to where they were)
	local bt = c - s.lightAt
	local burstK = if bt >= 0 then s.lightK * math.max(0, 1 - bt / (if off then 1.6 else 1.2)) else 0
	local grow = if bt >= 0 and bt < 0.3 then ease(bt / 0.3) else 1
	if r == 3 and off then
		base = 0
	end
	local n = g.beams
	local levels, lens, cols = {}, {}, {}
	local list = SHINE[math.clamp(r, 1, #SHINE)]
	local shift = if r >= 6 then math.floor(c * 1.5) else 0
	for i = 1, n do
		local wv = 0.7 + 0.3 * math.sin(c * 2.4 - i * math.pi * 4 / n)
		local lv = math.max(base * wv, burstK * (0.75 + 0.25 * wv))
		levels[i] = lv
		lens[i] = math.min(1, share * (0.9 + 0.1 * math.sin(c * 1.7 + i * 1.3))) * (if burstK > base then grow else 1)
		cols[i] = hexOf(list[((i - 1 + shift) % #list) + 1])
	end
	-- (its shadow on the pedestal, growing and darkening as it comes down)
	local shadow: { number }? = nil
	if c < s.wait + FALL then
		local t = 1 - liftOf(s, c) / DROP_FROM
		shadow = { s.baseX + s.baseW * 0.08, s.baseY + s.baseW * 0.04, s.baseW * 0.44 * (0.35 + 0.65 * t), 0.3 + 0.7 * t }
	end
	-- the rings now
	local rings: { HatchBackdrop.Ring } = {}
	local keep: { Wave } = {}
	for _, w in s.waves do
		local u = (c - w.born) / w.life
		if u < 1 then
			table.insert(keep, w)
			if u >= 0 then
				table.insert(rings, { x = w.x, y = w.y, r = w.from + (w.to - w.from) * ease(u), flat = w.flat, k = w.k * (1 - u), col = w.col })
			end
		end
	end
	s.waves = keep
	-- the hush: the sky going dark through the build-up, gone at the flash
	if s.phase == "breaking" then
		s.hush = g.hush * ease((c - s.breakAt) / s.build)
	elseif off then
		s.hush = 0
	end
	HatchBackdrop.light({
		x = cx,
		y = cy,
		rays = n,
		reach = H * g.reach,
		levels = levels,
		lens = lens,
		cols = cols,
		halo = halo,
		haloK = haloK,
		haloCol = hexOf(RAY[r][1]),
		shadow = shadow,
		rings = rings,
		motes = behind,
		hush = s.hush,
	})
end

local function step(s: Scene, dt: number)
	s.real += dt
	-- (the slow motion at the break: the scene's clock runs slower for a moment)
	local d = math.min(dt, 0.1) * (if s.real < s.slowUntil then SLOW else 1)
	s.clock += d
	local c = s.clock
	stepEgg(s, c, d)
	stepBeams(s, c)
	if s.phase == "breaking" then
		local b = c - s.breakAt
		if b >= s.build then
			hatch(s)
		elseif c >= s.tick then
			-- (a crackle a step higher each time, coming faster, and sparks spitting from the cracks)
			local u = b / s.build
			Audio.play("tick", { pitch = 0.8 + 0.7 * u, volume = 1.2 })
			s.tick = c + 0.2 - 0.12 * u
			local cr = s.cracks[math.random(1, math.max(1, #s.cracks))]
			if cr then
				burst(s, (s.cf * cr.off).Position, s.r, 2 + math.floor(4 * u), 40)
			end
		end
	end
	-- before it falls: from rare up a twinkle on the pedestal; from epic up motes rising off it
	if not s.arrived and c < s.wait and s.r >= 4 and PixelRenderer.isActive() and math.random() < 0.3 then
		addDot(s, RAY[s.r][(math.random(1, 2))], nil, s.baseX + math.random(-math.floor(s.baseW * 0.6), math.floor(s.baseW * 0.6)), s.baseY - math.random(0, 3), 0, -30 - math.random() * 20, 0, 0.6)
	end
	-- down on the pedestal: a thud, a puff of dust, a little shake, and the rings start spreading from under it; the
	-- second time down a softer thud
	if not s.arrived and c >= s.wait + FALL then
		s.arrived = true
		landed(s, 1)
		HatchBackdrop.land()
		Audio.play("sparkle", { pitch = 0.9 + s.r * 0.04 })
	elseif s.arrived and not s.bounced and c >= s.wait + FALL + BOUNCE_T[1] then
		s.bounced = true
		landed(s, 0.45)
		s.landAt = s.wait + DROP
	end
	-- down again after a step up's leap: a thud, it squashes, dust
	if not s.riseDown and c - s.riseAt >= RISE_T then
		s.riseDown = true
		landed(s, 0.7)
	end
	stepPal(s, c)
	stepShards(s, c, d)
	stepTwinkles(s, c)
	fireflies(s, c)
	stepCues(s, c)
	stepMoves(s, c)
	stepDots(s, d)
	stepBursts(s, c)
	stepFlash(s, c)
	stepJolt(s, c)
	stepLight(s, c, stepMotes(s, c))
	HatchBackdrop.step(d)
	if s.phase == "hatched" and s.topOff and c - (s.topOff :: number) > glory(s.r).show then
		finish(s)
		s.phase = "done"
		setHint(s, "Tap to go on")
	end
	local hint = s.hint
	if hint then
		hint.Visible = c % 1.2 < 0.85
	end
end

------------------------------------------------------------------ open and close
local function restore(s: Scene)
	local beat = s.beat
	if beat then
		beat:Disconnect()
	end
	PixelRenderer.onComposed(nil)
	local keys = s.keys
	if keys then
		keys:Disconnect()
	end
	local resize = s.resize
	if resize then
		resize:Disconnect()
	end
	dropEgg(s)
	for _, d in s.dots do
		d.gui:Destroy()
	end
	table.clear(s.dots)
	for _, c in s.dyn:GetDescendants() do
		if c:IsA("Model") then
			PixelRenderer.unregisterDynamic(c)
		end
	end
	s.dyn:Destroy()
	HatchBackdrop.light(nil)
	HatchBackdrop.hide()
	DayLight.hold(nil)
	PixelRenderer.setOffset(0, 0)
	if CameraController.stage() then
		CameraController.setStage(nil)
	end
	UIKit.root("Hud").Enabled = true
	UIKit.root("World").Enabled = true
	pcall(function()
		GuiService.TouchControlsEnabled = true
	end)
end

-- Back to the island at once (its picture kept while the scene had the view), and `after` runs.
closeScene = function(s: Scene)
	if s.closing then
		return
	end
	s.closing = true
	restore(s)
	s.root:Destroy()
	if scene == s then
		scene = nil
	end
	local after = s.after
	if after then
		after()
	end
	-- (a hatch that came while this one showed plays now, the sheet the first one brought back put away for it)
	local nxt = table.remove(waiting, 1)
	if nxt then
		UIKit.closePanel()
		HatchScene.play(nxt.res, nxt.after)
	end
end

-- How many hatches wait for the scene showing now to end (EggView: the tree's sheet comes back only after the last).
function HatchScene.waiting(): number
	return #waiting
end

function HatchScene.play(res: Result, after: (() -> ())?)
	if scene ~= nil then
		-- (one at a time: a second hatch while one shows plays when it ends. It used to run its `after` at once, so the
		-- tree's sheet came back over the scene still playing and the second egg's reveal never showed: a second Hatch
		-- tapped while the first was on its way)
		table.insert(waiting, { res = res, after = after })
		return
	end
	if quick then
		if after then
			task.defer(after)
		end
		return
	end
	local dyn = Instance.new("Folder")
	dyn.Name = "HatchDynamic"
	dyn.Parent = workspace
	-- the overlay: everything of the scene's on the Stage canvas (the world's art grid), the HUD and the world's tags
	-- hidden meanwhile
	local root = Instance.new("Frame")
	root.Name = "HatchScene"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 30
	root.Parent = UIKit.canvas("Stage")
	UIKit.root("Hud").Enabled = false
	UIKit.root("World").Enabled = false
	-- (the phone's jump button and stick too: a tap there would jump instead of going on)
	pcall(function()
		GuiService.TouchControlsEnabled = false
	end)
	local r0 = math.clamp(res.r, 1, Traits.RMAX)
	res.hr = math.clamp(res.hr, r0, Traits.RMAX)
	-- what the taps will reveal: each step up first, then each mutation
	local queue: { Reveal } = {}
	for r = r0 + 1, res.hr do
		table.insert(queue, { kind = "rise", r = r })
	end
	for i = 1, #res.muts do
		table.insert(queue, { kind = "mut", i = i })
	end
	local wait = glory(r0).wait
	local s: Scene = {
		res = res,
		after = after,
		r = r0,
		dyn = dyn,
		clock = 0,
		real = 0,
		slowUntil = 0,
		phase = "egg",
		queue = queue,
		total = #queue,
		rises = 0,
		crack = 0,
		lastTap = 0,
		tapAt = -10,
		hatchAt = -10,
		wait = wait,
		landAt = wait + DROP,
		wob = 0,
		kickAt = -10,
		kick = 0,
		squashAt = -10,
		squashK = 0,
		sq = 0,
		riseAt = -10,
		riseDown = true,
		breakAt = -10,
		build = glory(r0).build,
		tick = 0,
		shake = 0,
		egg = nil,
		parts = {},
		sizes = {},
		top = {},
		fx = {},
		cracks = {},
		crackSizes = {},
		cf = CFrame.new(eggMiddle(r0)),
		mid = eggMiddle(r0),
		glowing = false,
		blaze = 0,
		beams = {},
		beamsMade = 0,
		placedAt = -10,
		arrived = false,
		bounced = false,
		topOff = nil,
		rays = {},
		twinkleN = 0,
		twinkleAt = 0,
		shards = {},
		pal = nil,
		popAt = nil,
		whiteUntil = 0,
		palDown = false,
		palLand = 0,
		dots = {},
		motes = {},
		moveList = {},
		cues = {},
		bursts = {},
		waves = {},
		lightAt = -10,
		lightK = 0,
		joltAt = -10,
		joltK = 0,
		jx = 0,
		jy = 0,
		hush = 0,
		eggPx = 10,
		baseX = 0,
		baseY = 0,
		baseW = 20,
		root = root,
		title = nil,
		name = nil,
		line = nil,
		hint = nil,
		letters = {},
		ribbon = nil,
		plates = {},
		shown = 0,
		passive = false,
		flash = nil,
		flashAt = -10,
		flashK = 0,
		flashT = 0.3,
		beat = nil,
		keys = nil,
		resize = nil,
		closing = false,
	}
	-- a tap anywhere: the next reveal (HatchScene.skip)
	local tap = Instance.new("TextButton")
	tap.Name = "HatchTap"
	tap.Text = ""
	tap.AutoButtonColor = true -- (an enabled button: see-through, so the press shows nothing)
	tap.BackgroundTransparency = 1
	tap.Size = UDim2.fromScale(1, 1)
	tap.ZIndex = 50
	tap.Parent = root
	tap.Activated:Connect(function()
		HatchScene.skip()
	end)
	-- (the screen settling or changing size: lay the overlay out again once the Stage canvas has, in UI px: a change
	-- of pixel scale can leave the screen size as it was and still change the canvas)
	local relayoutPending = false
	local laidW, laidH = canvasSize()
	s.resize = UIKit.canvas("Stage"):GetPropertyChangedSignal("Size"):Connect(function()
		if relayoutPending then
			return
		end
		relayoutPending = true
		task.defer(function()
			relayoutPending = false
			local w, h = canvasSize()
			if w ~= laidW or h ~= laidH then
				laidW, laidH = w, h
				relayout(s)
			end
		end)
	end)
	s.keys = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.ButtonA then
			HatchScene.skip()
		end
	end)
	-- the egg floating, the light of its rarity, the camera on it (an empty see-through stage: shown at once)
	newEgg(s, s.r)
	newRays(s, if s.r >= 3 then s.r else 0)
	DayLight.hold(GRADE[s.r])
	scene = s
	local pts: { number } = {}
	local wide = 3.5
	local midY = FLOAT_Y + 0.5 * (EGG_H[3] or 2.5)
	for _, p in { { wide, FLOAT_Y - 0.6, -wide }, { -wide, FLOAT_Y - 0.6, wide }, { 2.2, FLOAT_Y - 1, 2.2 }, { -2.2, FLOAT_Y - 1, -2.2 }, { 0, FLOAT_Y + (EGG_H[5] or 2.8) + 1.4, 0 } } do
		table.insert(pts, ORIGIN.X + p[1] * STAGE_ROOM)
		table.insert(pts, ORIGIN.Y + midY + (p[2] - midY) * STAGE_ROOM)
		table.insert(pts, ORIGIN.Z + p[3] * STAGE_ROOM)
	end
	CameraController.setStage({ name = "hatch", origin = ORIGIN, pts = pts, tight = nil, top = 30, bottom = 40, clear = true, empty = true })
	backdrop(s)
	setTitle(s, eggWords(s.r), (Traits.RARITY[s.r] or Traits.RARITY[1]).color)
	setHint(s, if #queue > 0 then "Tap the egg" else "Tap to hatch")
	if #queue == 0 then
		glow(s)
	end
	-- (from rare up a twinkle blinks on the pedestal before it falls)
	if s.r >= 3 and PixelRenderer.isActive() then
		addStar(s, twinkle(s.r), math.floor(s.baseX), math.floor(s.baseY) - 3, wait + 0.15)
		Audio.play("ding", { pitch = 0.75 + 0.05 * s.r, volume = 0.8 })
	end
	if s.r >= 4 then
		Audio.play("egg")
	end
	Audio.play("open")
	s.beat = RunService.Heartbeat:Connect(function(dt: number)
		if scene ~= s or s.closing then
			return
		end
		step(s, dt)
	end)
	PixelRenderer.onComposed(function()
		if scene == s and not s.closing then
			placeBeams(s)
		end
	end)
end

function HatchScene.isOpen(): boolean
	return scene ~= nil
end

-- Sims: the scene ends at once (its `after` still runs, as after a real one).
function HatchScene.setQuick(on: boolean)
	quick = on
end

-- Sims and previews: what the scene shows now (`reveals`: the taps' reveals in all, `left`: still to come; `light`:
-- god rays lit behind it, `hush` how dark the sky is, `slow` whether the slow motion runs, `jolt` the picture's
-- offset now, `squash` the egg's, `letters` the name's letters in, `ribbon` its ribbon shown, `stars` circling,
-- `wait` the seconds before it fell, `build` the build-up's).
function HatchScene.debugState(): { open: boolean, phase: string, r: number, hr: number, clock: number, lift: number, rings: number, reveals: number, left: number, crack: number, shake: number, shown: number, muts: number, rays: number, shards: number, pal: boolean, egg: boolean, glowing: boolean, beams: number, title: string, titleOff: number, name: string, fresh: boolean, passive: string, light: number, hush: number, slow: boolean, jolt: number, squash: number, letters: number, ribbon: boolean, stars: number, wait: number, build: number }
	local s = scene
	if s == nil then
		return { open = false, phase = "", r = 0, hr = 0, clock = 0, lift = 0, rings = 0, reveals = 0, left = 0, crack = 0, shake = 0, shown = 0, muts = 0, rays = 0, shards = 0, pal = false, egg = false, glowing = false, beams = 0, title = "", titleOff = 0, name = "", fresh = false, passive = "", light = 0, hush = 0, slow = false, jolt = 0, squash = 0, letters = 0, ribbon = false, stars = 0, wait = 0, build = 0 }
	end
	local t, n = s.title, s.name
	local orbiting = 0
	for _, d in s.dots do
		if d.orbit then
			orbiting += 1
		end
	end
	return {
		open = true,
		phase = s.phase,
		r = s.r,
		hr = s.res.hr,
		clock = s.clock,
		lift = liftOf(s, s.clock),
		rings = HatchBackdrop.rings(),
		reveals = s.total,
		left = #s.queue,
		crack = s.crack,
		shake = s.shake,
		shown = s.shown,
		muts = #s.res.muts,
		rays = #s.rays,
		shards = #s.shards,
		pal = s.pal ~= nil,
		egg = s.egg ~= nil,
		glowing = s.glowing,
		beams = s.beamsMade,
		title = if t then t.Text else "",
		-- how far the title's box sits off the middle of the screen, in screen px (0: centred)
		titleOff = if t then (t.AbsolutePosition.X + t.AbsoluteSize.X / 2) - (s.root.AbsolutePosition.X + s.root.AbsoluteSize.X / 2) else 0,
		name = if n then n.Text else "",
		fresh = s.root:FindFirstChild("HatchNew") ~= nil, -- the "New!" tag by the name
		passive = (function()
			-- the passive's plate words ("" until it hatches)
			local pf = s.root:FindFirstChild("HatchPassive")
			local nm = pf and pf:FindFirstChild("Name")
			return if nm and nm:IsA("TextLabel") then nm.Text else ""
		end)(),
		light = HatchBackdrop.debugLight().beams,
		hush = s.hush,
		slow = s.real < s.slowUntil,
		jolt = math.abs(s.jx) + math.abs(s.jy),
		squash = s.sq,
		letters = #s.letters,
		ribbon = s.ribbon ~= nil,
		stars = orbiting,
		wait = s.wait,
		build = s.build,
	}
end

return HatchScene
