--!strict
-- The hatch scene (GAME_DESIGN 6.2; docs/ARCHITECTURE.md 10.11): the request of 2026-11-13, "make a cutscene for eggs
-- hatching and shows the creature hatched, listing the mutations it has as it hatches, with eggs having a chance to
-- skip to the next rarity during the cutscene. the cutscenes become more glorious as the rarity of egg increases",
-- and of 2026-11-14: "could you also remove the transition that happens when clicking to hatch an egg? you can simply
-- render the floating egg in a 2d background. also, make the player click to hatch the egg, each click revealing a
-- mutation or a tier up upgrade if there is any, otherwise it just hatches"; then "make sounds when cracking the egg.
-- also, make the egg rise up into view when it is being opened".
--
-- An egg bought at the Tree of Life (Controllers/EggView.hatch) floats in front of a painted sky (UI/HatchBackdrop)
-- at once: no blinds, nothing to bake (the camera's stage view on an empty see-through stage, CameraController's
-- Stage.empty: the pixel renderer draws only the moving egg over the 2D picture). It rises up into view from below
-- (RISE s, easing out past its spot and settling back), then bobs and now and then wobbles, asking to be tapped.
-- Every tap that cracks it crunches (Audio "crack", a little higher each time) and the hatch breaks the shell open
-- ("crack_open"). Each tap takes the next of what is waiting inside: first each step up in rarity (Logic/Tree.rise:
-- the result's `hr` over its `r`: a hard shake, a flash, the egg in the next rarity's colours, the sky and the light
-- changing with it), then each mutation (a shake, a new crack, its plate sliding in at the right with its name, stars
-- and what it does). When nothing is left the cracks glow and the next tap hatches it: a flash, the top flies off, bits
-- of shell scatter and what hatched pops out, its name and rarity under it ("No mutations" on a plate if it has none).
-- One more tap goes back to the island (its picture was kept, so it is there at once) and `after` runs.
-- The rarer it hatched as, the grander (GLORY): twinkles round the egg (rare and up), more sparks and
-- shell, a jolt of the picture, confetti, stars ringing it; the light of dusk for the commoner ones, a blue, violet or
-- deep gold night for the rarer (DayLight.hold).
--   HatchScene.play(result, after?)   result: { sp, muts, r (laid), hr (hatched as) }
--   HatchScene.isOpen(), HatchScene.skip() (a tap), HatchScene.debugState() (sims and previews: the phase and what is
--   shown), HatchScene.setQuick(on) (sims: the scene ends at once, `after` still runs)
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
local Blocks = require(ReplicatedStorage.Shared.Models.Blocks)
local EggModels = require(ReplicatedStorage.Shared.Models.EggModels)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local HatchBackdrop = require(script.Parent.HatchBackdrop)

local HatchScene = {}

export type Result = { sp: string, muts: { string }, r: number, hr: number }

local ORIGIN = Vector3.new(0, 0, 9000) -- far from the islands (z 0 .. -160)
local FLOAT_Y = 1.2 -- the egg's foot above ORIGIN (it floats: nothing under it)
local EGG_H: { number } = { 2.3, 2.4, 2.5, 2.65, 2.8 } -- each rarity's egg up close (EggModels.hero), studs tall
local PAL_SCALE = 1.35 -- what hatched, a little bigger than on the island
local TAP_GAP = 0.22 -- seconds a tap waits after the last one (a double tap is one)
-- the box the stage view fits is this many times the egg's own room, about the egg's middle: bigger draws the egg and
-- what hatches smaller on the screen (the request of 2026-11-14: "make the egg and creature smaller in the hatching
-- screen"; it was 1)
local STAGE_ROOM = 1.45
local RISE = 0.95 -- seconds the egg takes to rise into view when the scene opens (taps wait for it)
local RISE_FROM = 7 -- studs under its spot it starts, out of the picture

-- How grand each rarity's scene is (by the rarity it is now; the hatch's by the rarity it hatched as).
type Glory = {
	rays: number, -- twinkles round it at once, about (they took the place of rays of light)
	rayLen: number, -- (unused since the twinkles)
	sparks: number, -- sparks out of the crack
	shards: number, -- bits of shell
	flash: number, -- the white flash's strength (0 .. 1)
	jolt: number, -- art px the picture jolts at the crack
	confetti: number,
	stars: number, -- stars ringing it
}
local GLORY: { Glory } = {
	{ rays = 0, rayLen = 0, sparks = 12, shards = 6, flash = 0.25, jolt = 0, confetti = 0, stars = 0 },
	{ rays = 0, rayLen = 0, sparks = 18, shards = 8, flash = 0.3, jolt = 0, confetti = 0, stars = 3 },
	{ rays = 8, rayLen = 1.6, sparks = 26, shards = 10, flash = 0.4, jolt = 1, confetti = 0, stars = 5 },
	{ rays = 12, rayLen = 2.1, sparks = 36, shards = 12, flash = 0.5, jolt = 2, confetti = 50, stars = 7 },
	{ rays = 16, rayLen = 2.7, sparks = 50, shards = 14, flash = 0.6, jolt = 3, confetti = 110, stars = 10 },
}

-- The light of each rarity's scene (the renderer's grade, as DayLight's: a warm dusk for the commoner ones, then a blue
-- twilight, a violet night and a deep gold one; the egg's own lights pooling stronger the darker it is).
local GRADE: { PixelRenderer.Grade } = {
	{ mr = 1.04, mg = 0.93, mb = 0.8, lift = 0, sat = 1.05, lamps = 0.3 },
	{ mr = 0.98, mg = 0.96, mb = 0.8, lift = 2, sat = 1.05, lamps = 0.4 },
	{ mr = 0.82, mg = 0.84, mb = 1.02, lift = 4, sat = 0.98, lamps = 0.6 },
	{ mr = 0.84, mg = 0.7, mb = 1.0, lift = 6, sat = 0.98, lamps = 0.75 },
	{ mr = 0.98, mg = 0.78, mb = 0.62, lift = 4, sat = 1.04, lamps = 0.9 },
}

-- Each rarity's colours in the scene: its sparks and its cracks' light (palette keys).
local RAY: { { string } } = { { "cream", "white" }, { "green", "white" }, { "blue", "white" }, { "purple", "pink" }, { "gold", "yellow" } }

local KNACK: { [string]: string } = { farm = "good at farms", wood = "good with wood", shop = "good at shops" }

------------------------------------------------------------------ state
type Reveal = { kind: string, r: number?, i: number? } -- "rise" (to rarity r) | "mut" (the i-th mutation)
type Shard = { p: BasePart, v: Vector3, w: number, at: Vector3, born: number }
type Dot = { gui: GuiObject, world: Vector3?, x: number, y: number, vx: number, vy: number, g: number, born: number, life: number, frames: { GuiObject }? }
type Scene = {
	res: Result,
	after: (() -> ())?,
	r: number, -- the rarity shown now (it climbs to res.hr)
	dyn: Folder,
	clock: number,
	phase: string, -- "egg" (taps reveal) | "hatched" (what hatched popping out) | "done" (a tap goes back)
	queue: { Reveal }, -- what the next taps reveal, in order
	total: number, -- reveals in all
	crack: number, -- the cracks shown (0 .. 3)
	lastTap: number, -- the scene clock at the last tap taken
	kickAt: number, -- the last shake (scene clock) and how hard
	kick: number,
	-- the egg
	egg: Model?,
	parts: { { p: BasePart, off: CFrame } },
	top: { BasePart },
	fx: { { p: BasePart, kind: string, k: number } },
	cracks: { EggModels.Crack },
	glowing: boolean, -- the cracks lit from inside (nothing left to reveal: the next tap hatches it)
	arrived: boolean, -- it has risen into view (a soft chime as it gets there)
	topOff: number?, -- when it hatched (the top flew off)
	rays: { { p: BasePart, a: number, k: number } }, -- (none since the twinkles took their place)
	twinkleN: number, -- twinkles round it at once, about (GLORY.rays; 0: none)
	twinkleAt: number, -- the scene clock when the next one comes
	shards: { Shard },
	pal: MicroModels.Thing?,
	popAt: number?,
	dots: { Dot },
	-- the overlay
	root: Frame,
	title: TextLabel?,
	name: TextLabel?,
	line: TextLabel?,
	hint: TextLabel?,
	plates: { Frame },
	shown: number, -- mutation plates shown
	flash: Frame?,
	beat: RBXScriptConnection?,
	keys: RBXScriptConnection?,
	closing: boolean,
}

local scene: Scene? = nil
local quick = false

local function glory(r: number): Glory
	return GLORY[math.clamp(r, 1, 5)]
end

local function ease(u: number): number
	local x = math.clamp(u, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end


------------------------------------------------------------------ the egg and what hatches
local function dropEgg(s: Scene)
	local m = s.egg
	if m then
		PixelRenderer.unregisterDynamic(m)
		m:Destroy()
	end
	s.egg, s.parts, s.top, s.fx, s.cracks, s.glowing = nil, {}, {}, {}, {}, false
end

local function newEgg(s: Scene, r: number)
	dropEgg(s)
	local m, parts, top, fx, cracks = EggModels.hero(r, EGG_H[r] or 2.4)
	m.Parent = s.dyn
	PixelRenderer.registerDynamic(m)
	s.egg, s.parts, s.top, s.fx, s.cracks, s.glowing = m, parts, top, fx, cracks, false
end

-- Twinkles round the egg (the request of 2026-11-14: "remove these rectangular effects everywhere, instead make it
-- twinkles": they took the place of rays of light, thin bright bars turning behind it): from a rare egg up, little
-- stars blink in and out at random round it, more the rarer it is (GLORY.rays), and round what hatched after.
local function newRays(s: Scene, r: number)
	s.twinkleN = glory(r).rays
end

local function eggMiddle(r: number): Vector3
	return at(0, FLOAT_Y + 0.5 * (EGG_H[r] or 2.4), 0)
end

-- How far under its spot the egg still is while it rises into view (0 once it has): fast at first, easing out a
-- little past its spot and settling back (an ease-out-back, so it arrives with some weight).
local function liftOf(c: number): number
	if c >= RISE then
		return 0
	end
	local u = math.clamp(c / RISE, 0, 1) - 1
	local back = 1 + 2.2 * u * u * u + 1.2 * u * u -- (0 at the start, 1 at the end, about 1.05 two thirds of the way)
	return -RISE_FROM * (1 - back)
end

-- The painted sky (UI/HatchBackdrop), the egg's glow round where it floats on screen; only with the pixel filter on
-- (in the classic look Roblox's own sky shows).
local function backdrop(s: Scene)
	if not PixelRenderer.isActive() then
		return
	end
	local ex, ey = PixelRenderer.projectPixel(eggMiddle(s.r))
	HatchBackdrop.show(s.r, ex, ey)
end

------------------------------------------------------------------ the overlay's bits
local function canvasSize(): (number, number)
	local v = UIKit.size("Stage")
	return v.X, v.Y
end

local function addDot(s: Scene, color: string, world: Vector3?, x: number, y: number, vx: number, vy: number, g: number, life: number)
	if #s.dots > 260 then
		return
	end
	local gui: GuiObject = UIKit.rect(s.root, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, y), UIKit.color(color), 30)
	gui.Name = "HatchDot"
	table.insert(s.dots, { gui = gui, world = world, x = x, y = y, vx = vx, vy = vy, g = g, born = s.clock, life = life, frames = nil })
end

local function addStar(s: Scene, names: { string }, x: number, y: number, life: number, vy: number?)
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
	holder.Parent = s.root
	local gui: GuiObject = holder
	table.insert(s.dots, { gui = gui, world = nil, x = x - math.floor(w / 2), y = y - math.floor(h / 2), vx = 0, vy = vy or 0, g = 0, born = s.clock, life = life, frames = frames })
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

local function flash(s: Scene, k: number, color: Color3?)
	if k <= 0 then
		return
	end
	local old = s.flash
	if old then
		old:Destroy()
	end
	local f = UIKit.rect(s.root, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), color or UIKit.color("white"), 32)
	f.Name = "HatchFlash"
	f.BackgroundTransparency = 1 - k
	s.flash = f
	UIKit.tween(f, 0.28, { BackgroundTransparency = 1 })
	task.delay(0.4, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

local function setTitle(s: Scene, text: string, color: string)
	local w = canvasSize()
	local old = s.title
	if old then
		old:Destroy()
	end
	local t = UIKit.text(s.root, text, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, 8), { x = "center", face = "big", kind = "title", color = UIKit.color(color), z = 33, name = "HatchTitle" })
	s.title = t
	-- (it drops in: two px down to rest)
	t.Position = UDim2.fromOffset(0, 5)
	UIKit.tween(t, 0.18, { Position = UDim2.fromOffset(0, 8) })
end

local function eggWords(r: number): string
	local rar = Traits.RARITY[r] or Traits.RARITY[1]
	return string.format("%s %s egg", if r == 2 or r == 4 then "An" else "A", string.lower(rar.name))
end

-- What hatched, under it: its name in its rarity's colour, its rarity and knack.
local function showName(s: Scene)
	local w, h = canvasSize()
	local def = Creatures.byId[s.res.sp]
	local rar = Traits.RARITY[if def then def.rarity else s.r] or Traits.RARITY[1]
	local nm = UIKit.text(s.root, if def then def.name else "A driftling", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, h - 42), { x = "center", face = "big", kind = "title", color = UIKit.color(rar.color), z = 33, name = "HatchName" })
	local line = UIKit.text(s.root, if def then string.format("%s, %s", rar.name, KNACK[def.knack] or "a hard worker") else rar.name, UDim2.fromOffset(w, 10), UDim2.fromOffset(0, h - 24), { x = "center", color = UIKit.color("paper"), z = 33, name = "HatchLine" })
	s.name, s.line = nm, line
	nm.Position = UDim2.fromOffset(0, h - 36)
	UIKit.tween(nm, 0.2, { Position = UDim2.fromOffset(0, h - 42) })
	-- (the egg's title goes and nothing takes its place: the request of 2026-11-14, "remove the it hatched text")
	local old = s.title
	if old then
		old:Destroy()
		s.title = nil
	end
end

-- One more of its mutations, on a plate sliding in at the right: its name and stars in its tier's colour, what it
-- does under it. With none, one plate says so.
local PLATE_W, PLATE_H = 122, 22
local function showMut(s: Scene, i: number)
	local w, h = canvasSize()
	local muts = s.res.muts
	local x = math.min(w - PLATE_W - 6, math.floor(w / 2) + 78)
	local n = math.max(1, #muts)
	local y0 = math.floor((h - n * (PLATE_H + 3)) / 2) - 6
	local y = y0 + (i - 1) * (PLATE_H + 3)
	local f = UIKit.glass(s.root, UDim2.fromOffset(PLATE_W, PLATE_H), UDim2.fromOffset(x + 30, y), 2)
	f.Name = "HatchMut_" .. i
	f.ZIndex = 33
	table.insert(s.plates, f)
	UIKit.tween(f, 0.2, { Position = UDim2.fromOffset(x, y) })
	local m = if #muts > 0 then Traits.byId[muts[i]] else nil
	if m then
		local tier = m.tier
		UIKit.text(f, m.name .. " " .. (Traits.TIER_STARS[tier] or ""), UDim2.fromOffset(PLATE_W - 8, 10), UDim2.fromOffset(4, 1), { color = UIKit.color(Traits.TIER_COLOR[tier] or "text"), z = 34, name = "Name" })
		UIKit.text(f, m.blurb, UDim2.fromOffset(PLATE_W - 8, 10), UDim2.fromOffset(4, 11), { color = UIKit.color("text_dim"), z = 34, name = "Blurb" })
		Audio.play(if tier >= 3 then "sparkle" elseif tier == 0 then "flip" else "ding", { pitch = 0.9 + tier * 0.08 })
		if tier >= 2 then
			for k = 1, tier * 4 do
				local a = k / (tier * 4) * math.pi * 2
				addDot(s, Traits.TIER_COLOR[tier] or "text", nil, x + 8, y + PLATE_H / 2, math.cos(a) * 40, math.sin(a) * 40, 30, 0.5)
			end
		end
	else
		UIKit.text(f, "No mutations", UDim2.fromOffset(PLATE_W - 8, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("text"), z = 34, name = "Name" })
		UIKit.text(f, "Just itself", UDim2.fromOffset(PLATE_W - 8, 10), UDim2.fromOffset(4, 11), { color = UIKit.color("text_dim"), z = 34, name = "Blurb" })
		Audio.play("flip")
	end
end


-- The hint at the foot of the screen, blinking: what a tap does now.
local function setHint(s: Scene, text: string)
	local old = s.hint
	if old then
		old:Destroy()
	end
	local w, h = canvasSize()
	s.hint = UIKit.text(s.root, text, UDim2.fromOffset(w, 10), UDim2.fromOffset(0, h - 13), { x = "center", color = UIKit.color("text_dim"), z = 33, name = "HatchHint" })
end

------------------------------------------------------------------ the taps
-- A step up: a hard shake, a flash, the next rarity's egg (its cracks as far as they had got), its rays, its light
-- and its sky, sparks and stars, "It turned epic".
local function rise(s: Scene, r: number)
	s.r = math.clamp(r, 1, 5)
	newEgg(s, s.r)
	newRays(s, if s.r >= 3 then s.r else 0)
	DayLight.hold(GRADE[s.r])
	backdrop(s)
	flash(s, 0.45)
	s.kickAt, s.kick = s.clock, 1
	burst(s, eggMiddle(s.r), s.r, 18 + s.r * 4, 70)
	local px, py = PixelRenderer.projectPixel(eggMiddle(s.r))
	for k = 1, 4 + s.r do
		local a = k / (4 + s.r) * math.pi * 2
		addStar(s, { "twinkle_1", "twinkle_2", "twinkle_1" }, px + math.cos(a) * 26, py + math.sin(a) * 20, 0.6)
	end
	Audio.play("level_up")
	Audio.play("rare")
	local rar = Traits.RARITY[s.r] or Traits.RARITY[1]
	setTitle(s, "It turned " .. string.lower(rar.name), rar.color)
end

-- It hatches: a flash, the top flies off, bits of shell scatter, what hatched pops out (its name under it, "No
-- mutations" on a plate when it has none), the picture jolts, confetti, stars (by the rarity it hatched as).
local function hatch(s: Scene)
	local r = s.r
	local g = glory(r)
	local c = s.clock
	s.phase = "hatched"
	s.topOff = c
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
	flash(s, g.flash)
	burst(s, mid, r, g.sparks, 90)
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
	local thing = MicroModels.species(s.res.sp)
	MicroModels.scale(thing, Vector3.one * 0.3)
	thing.model.Parent = s.dyn
	PixelRenderer.registerDynamic(thing.model)
	s.pal = thing
	s.popAt = c + 0.12
	if g.jolt > 0 then
		task.spawn(function()
			for k = 1, 6 do
				local j = math.max(1, math.floor(g.jolt * (1 - k / 7) + 0.5))
				PixelRenderer.setOffset(if k % 2 == 0 then j else -j, if k % 3 == 0 then -j else j)
				task.wait(0.04)
			end
			PixelRenderer.setOffset(0, 0)
		end)
	end
	local w = canvasSize()
	for k = 1, g.confetti do
		local cols = { "pink", "yellow", "blue", "green", "orange", "purple", "white" }
		addDot(s, cols[(k % #cols) + 1], nil, math.random(0, w), -math.random(0, 60), (math.random() - 0.5) * 30, 20 + math.random() * 40, 18, 2.4 + math.random())
	end
	if g.stars > 0 then
		local px, py = PixelRenderer.projectPixel(mid)
		for k = 1, g.stars do
			local a = k / g.stars * math.pi * 2
			addStar(s, if r >= 5 then { "spark_1", "spark_2", "spark_3" } else { "twinkle_1", "twinkle_2", "twinkle_1" }, px + math.cos(a) * 34, py + math.sin(a) * 26, 0.8 + k * 0.03, -6)
		end
	end
	showName(s)
	if #s.res.muts == 0 then
		s.shown += 1
		showMut(s, s.shown)
	end
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
	for _, k in s.cracks do
		k.p.Color = Blocks.color(RAY[s.r][2])
		k.p.Material = Enum.Material.Neon
	end
	PixelRenderer.refreshDynamic(s.egg :: Model)
end

local closeScene: (s: Scene) -> ()

-- A tap: the next step up or mutation; with nothing left, it hatches; once what hatched is out, back to the island.
function HatchScene.skip()
	local s = scene
	if s == nil or s.closing then
		return
	end
	if s.clock - s.lastTap < TAP_GAP and s.lastTap > 0 then
		return
	end
	if s.phase == "egg" and s.clock < RISE then
		return -- (still rising into view)
	end
	s.lastTap = s.clock
	if s.phase == "done" then
		closeScene(s)
		return
	elseif s.phase ~= "egg" then
		return
	end
	local nxt = table.remove(s.queue, 1)
	if nxt == nil then
		hatch(s)
		return
	end
	s.crack = math.min(3, s.crack + 1)
	Audio.play("crack", { pitch = 0.9 + s.crack * 0.07 })
	if nxt.kind == "rise" then
		rise(s, nxt.r or s.r + 1)
	else
		s.kickAt, s.kick = s.clock, 0.6
		s.shown += 1
		showMut(s, s.shown)
		burst(s, eggMiddle(s.r), s.r, 8, 50)
	end
	if #s.queue == 0 then
		glow(s)
		setHint(s, "Tap to hatch it")
	end
end

------------------------------------------------------------------ every frame
local function stepEgg(s: Scene, c: number)
	local r = s.r
	local eh = EGG_H[r] or 2.4
	-- floating: a slow bob, a sway; a shake after a tap (a step up's the hardest), dying away; now and then, while it
	-- waits, a little wobble asking to be tapped
	local bob = math.sin(c * 1.6) * 0.08
	local tilt = math.sin(c * 1.1) * 0.03
	local k = c - s.kickAt
	if k >= 0 and k < 0.7 then
		tilt += math.sin(k * 40) * 0.16 * s.kick * (1 - k / 0.7)
		bob += math.abs(math.sin(k * 20)) * 0.06 * s.kick * (1 - k / 0.7)
	elseif s.phase == "egg" then
		local w = (c + 0.8) % 2.6
		if w < 0.45 then
			tilt += math.sin(w / 0.45 * math.pi * 2) * (if s.glowing then 0.1 else 0.05)
		end
	end
	local lift = liftOf(c)
	local foot = at(0, FLOAT_Y + bob + lift, 0)
	local cf = CFrame.new(foot) * CFrame.Angles(tilt, 0, tilt * 0.6)
	local off = s.topOff
	for _, rp in s.parts do
		local here = cf * rp.off
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
	for _, kk in s.cracks do
		kk.p.CFrame = if off == nil and kk.stage <= s.crack then cf * kk.off else CFrame.new(foot - Vector3.new(0, 30, 0))
	end
	if off and c - off > 0.6 and s.egg then
		dropEgg(s)
	end
	-- the rarity's lights on the egg: motes circling it, a halo turning over it, a beam out of its top
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
		elseif f.kind == "beam" then
			local hb = 3.4 + 0.6 * math.sin(c * 1.9)
			f.p.Size = Vector3.new(0.3, Blocks.snap(hb), 0.3)
			f.p.CFrame = cf * CFrame.new(0, eh + 0.2 + Blocks.snap(hb) / 2, 0)
		end
	end

end

-- What hatched: popping out of the shell (small to a little over its size and back) with one jump and its arms up
-- ("hooray"), then floating where the egg was with a slow bob.
local function stepPal(s: Scene, c: number)
	local thing = s.pal
	local pop = s.popAt
	if thing == nil or pop == nil then
		return
	end
	local k = (c - pop) / 0.45
	local sc = if k < 0 then 0.3 elseif k < 0.6 then 0.3 + (PAL_SCALE * 1.15 - 0.3) * ease(k / 0.6) else PAL_SCALE * (1.15 - 0.15 * ease((k - 0.6) / 0.4))
	MicroModels.scale(thing, Vector3.one * sc)
	-- (it jumps once on its skeleton as it pops out, then floats with a slow bob: "make the pet jump only once instead
	-- of a few times after hatching", 2026-11-14)
	local hop = if k < 1 then 0 else math.sin((c - pop - 0.45) * 1.6) * 0.08
	local mood = if c - pop < 2.2 then "hooray" else "idle"
	MicroModels.animate(thing, c, mood, 0)
	MicroModels.place(thing, CFrame.new(at(0, FLOAT_Y + hop, 0)) * CFrame.Angles(0, math.pi / 4, 0))
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
		d.vy += d.g * dt
		d.x += d.vx * dt
		d.y += d.vy * dt
		d.gui.Position = UDim2.fromOffset(math.floor(d.x), math.floor(d.y))
		local fr = d.frames
		if fr then
			local k = math.clamp(math.floor(age / d.life * #fr) + 1, 1, #fr)
			for i, f in fr do
				f.Visible = i == k
			end
		end
		table.insert(keep, d)
	end
	s.dots = keep
end

-- What drifts in the air (1 px dots): by day (a common or uncommon egg's sky) seeds and petals blowing across, by
-- night fireflies rising and blinking.
local function fireflies(s: Scene, c: number)
	if math.random() < 0.08 then
		local w, h = canvasSize()
		if s.r <= 2 then
			local y = math.random(20, math.max(21, h - 40))
			addDot(s, if math.random() < 0.6 then "white" elseif math.random() < 0.5 then "pink" else "cream", nil, -2, y, 14 + math.random() * 10, (math.random() - 0.5) * 4, 1, w / 14)
		else
			local x, y = math.random(10, math.max(11, w - 10)), math.random(30, math.max(31, h - 50))
			addDot(s, if math.random() < 0.5 then "yellow" else "cream", nil, x, y, (math.random() - 0.5) * 8, -4 - math.random() * 6, 0, 1.6)
		end
	end
	local _ = c
end


-- A twinkle now and then round the egg (from a rare one up), and round what hatched after: a rare one's go out a
-- moment after the hatch, an epic or legendary one's stay. Each blinks through its frames where it appeared.
local function stepTwinkles(s: Scene, c: number)
	local n = s.twinkleN
	if n <= 0 or c < s.twinkleAt then
		return
	end
	local off = s.topOff
	if off and s.r <= 3 and c - (off :: number) > 1.4 then
		return
	end
	local life = 0.55 + math.random() * 0.35
	s.twinkleAt = c + 0.7 / n * (0.6 + math.random() * 0.8)
	local px, py = PixelRenderer.projectPixel(eggMiddle(s.r) + Vector3.new(0, liftOf(c), 0))
	local a = math.random() * math.pi * 2
	local x = px + math.cos(a) * (20 + math.random() * 22)
	local y = py + math.sin(a) * (16 + math.random() * 18)
	local frames = if s.r >= 5 then { "spark_1", "spark_2", "spark_3", "spark_2" } else { "twinkle_1", "twinkle_2", "twinkle_1" }
	addStar(s, frames, math.floor(x), math.floor(y), life, -3)
end

local function step(s: Scene, dt: number)
	local d = math.min(dt, 0.1)
	s.clock += d
	local c = s.clock
	stepEgg(s, c)
	if not s.arrived and c >= RISE * 0.65 then
		s.arrived = true
		Audio.play("sparkle", { pitch = 0.9 + s.r * 0.04 })
	end
	stepPal(s, c)
	stepShards(s, c, d)
	stepTwinkles(s, c)
	fireflies(s, c)
	stepDots(s, d)
	HatchBackdrop.step(d)
	if s.phase == "hatched" and s.topOff and c - (s.topOff :: number) > 0.7 then
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
	local keys = s.keys
	if keys then
		keys:Disconnect()
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
end

function HatchScene.play(res: Result, after: (() -> ())?)
	if scene ~= nil then
		-- (one at a time: a second hatch while one shows just says so when it ends)
		if after then
			task.defer(after)
		end
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
	local r0 = math.clamp(res.r, 1, 5)
	res.hr = math.clamp(res.hr, r0, 5)
	-- what the taps will reveal: each step up first, then each mutation
	local queue: { Reveal } = {}
	for r = r0 + 1, res.hr do
		table.insert(queue, { kind = "rise", r = r })
	end
	for i = 1, #res.muts do
		table.insert(queue, { kind = "mut", i = i })
	end
	local s: Scene = {
		res = res,
		after = after,
		r = r0,
		dyn = dyn,
		clock = 0,
		phase = "egg",
		queue = queue,
		total = #queue,
		crack = 0,
		lastTap = 0,
		kickAt = -10,
		kick = 0,
		egg = nil,
		parts = {},
		top = {},
		fx = {},
		cracks = {},
		glowing = false,
		arrived = false,
		topOff = nil,
		rays = {},
		twinkleN = 0,
		twinkleAt = 0,
		shards = {},
		pal = nil,
		popAt = nil,
		dots = {},
		root = root,
		title = nil,
		name = nil,
		line = nil,
		hint = nil,
		plates = {},
		shown = 0,
		flash = nil,
		beat = nil,
		keys = nil,
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
	setHint(s, if #queue > 0 then "Tap the egg" else "Tap to hatch it")
	if #queue == 0 then
		glow(s)
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
end

function HatchScene.isOpen(): boolean
	return scene ~= nil
end

-- Sims: the scene ends at once (its `after` still runs, as after a real one).
function HatchScene.setQuick(on: boolean)
	quick = on
end

-- Sims and previews: what the scene shows now (`reveals`: the taps' reveals in all, `left`: still to come).
function HatchScene.debugState(): { open: boolean, phase: string, r: number, hr: number, clock: number, lift: number, reveals: number, left: number, crack: number, shown: number, muts: number, rays: number, shards: number, pal: boolean, egg: boolean, glowing: boolean, title: string, name: string }
	local s = scene
	if s == nil then
		return { open = false, phase = "", r = 0, hr = 0, clock = 0, lift = 0, reveals = 0, left = 0, crack = 0, shown = 0, muts = 0, rays = 0, shards = 0, pal = false, egg = false, glowing = false, title = "", name = "" }
	end
	local t, n = s.title, s.name
	return {
		open = true,
		phase = s.phase,
		r = s.r,
		hr = s.res.hr,
		clock = s.clock,
		lift = liftOf(s.clock),
		reveals = s.total,
		left = #s.queue,
		crack = s.crack,
		shown = s.shown,
		muts = #s.res.muts,
		rays = #s.rays,
		shards = #s.shards,
		pal = s.pal ~= nil,
		egg = s.egg ~= nil,
		glowing = s.glowing,
		title = if t then t.Text else "",
		name = if n then n.Text else "",
	}
end

return HatchScene
