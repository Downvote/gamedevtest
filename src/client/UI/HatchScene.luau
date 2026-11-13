--!strict
-- The hatch scene (GAME_DESIGN 6.2; docs/ARCHITECTURE.md 10.11): the request of 2026-11-13, "make a cutscene for eggs
-- hatching and shows the creature hatched, listing the mutations it has as it hatches, with eggs having a chance to
-- skip to the next rarity during the cutscene. the cutscenes become more glorious as the rarity of egg increases."
--
-- An egg bought at the Tree of Life (Controllers/EggView.hatch) is shown up close on a little stage far from the
-- islands (ORIGIN): a mossy nest in a clearing at dusk, lanterns, mushrooms and a stump with a candle round it, drawn
-- by the pixel filter like the islands (the camera's stage view: CameraController.setStage). Ink blinds cover the
-- screen while the stage's picture is baked, then open on the egg in its nest. It rocks a few times (more the rarer
-- it was laid); if the server says it turned rarer as it hatched (Logic/Tree.rise: the result's `hr` over its `r`),
-- each step up is a hard shake, a flash and the egg standing there in the next rarity's colours, the light round it
-- changing with it. Then it cracks: the top flies off, bits of shell scatter and what hatched pops up in the nest,
-- its name and rarity under it and its mutations listed one by one beside it, each in its tier's colour.
-- The rarer the egg it hatched from, the grander all of it (GLORY): a longer build-up, the light of dusk turning to a
-- blue, violet or deep gold night with the lanterns and the egg's own light pooling round them (the renderer's grade,
-- held: DayLight.hold), rays of light turning behind the egg (rare and up), the clearing dimmed round it (epic and
-- up), more sparks and shell, a jolt of the picture, confetti, stars ringing it (legendary). A tap skips to what
-- hatched, a second tap (or a few seconds) goes back to the island; `after` runs then.
--   HatchScene.play(result, after?)   result: { sp, muts, r (laid), hr (hatched as) }
--   HatchScene.isOpen(), HatchScene.skip() (as a tap), HatchScene.debugState() (sims and previews: the phase and
--   what is shown), HatchScene.setQuick(on) (sims: the scene ends at once, `after` still runs), HatchScene.setWait(secs)
--   (previews: the blinds wait longer for the stage's picture)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
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
local NEST_Y = 0.3 -- the nest's bed (an egg's foot, what hatched stands here)
local EGG_H: { number } = { 2.3, 2.4, 2.5, 2.65, 2.8 } -- each rarity's egg up close (EggModels.hero), studs tall
local PAL_SCALE = 1.35 -- what hatched, a little bigger than on the island
local BLIND = 12 -- the curtain's blinds (UI px)

-- How grand each rarity's scene is (by the rarity it hatched as; the rocking by the rarity it was laid as).
type Glory = {
	rocks: number, -- times the egg rocks before anything else
	build: number, -- seconds of shaking before it cracks
	rays: number, -- rays of light turning behind it
	rayLen: number,
	sparks: number, -- sparks out of the crack
	shards: number, -- bits of shell
	flash: number, -- the white flash's strength (0 .. 1)
	dim: number, -- the clearing dimmed round the egg (PixelRenderer.setDim)
	jolt: number, -- art px the picture jolts at the crack
	confetti: number,
	stars: number, -- stars ringing it
}
local GLORY: { Glory } = {
	{ rocks = 2, build = 0.6, rays = 0, rayLen = 0, sparks = 12, shards = 6, flash = 0.25, dim = 0, jolt = 0, confetti = 0, stars = 0 },
	{ rocks = 3, build = 0.8, rays = 0, rayLen = 0, sparks = 18, shards = 8, flash = 0.3, dim = 0, jolt = 0, confetti = 0, stars = 3 },
	{ rocks = 3, build = 1.1, rays = 8, rayLen = 1.6, sparks = 26, shards = 10, flash = 0.4, dim = 0.15, jolt = 1, confetti = 0, stars = 5 },
	{ rocks = 4, build = 1.5, rays = 12, rayLen = 2.1, sparks = 36, shards = 12, flash = 0.5, dim = 0.3, jolt = 2, confetti = 50, stars = 7 },
	{ rocks = 5, build = 2.0, rays = 16, rayLen = 2.7, sparks = 50, shards = 14, flash = 0.6, dim = 0.4, jolt = 3, confetti = 110, stars = 10 },
}

-- The light of each rarity's scene (the renderer's grade, as DayLight's: a warm dusk for the commoner ones, then a blue
-- twilight, a violet night and a deep gold one; the lamps' pools stronger the darker it is).
local GRADE: { PixelRenderer.Grade } = {
	{ mr = 1.04, mg = 0.93, mb = 0.8, lift = 0, sat = 1.05, lamps = 0.3 },
	{ mr = 0.98, mg = 0.96, mb = 0.8, lift = 2, sat = 1.05, lamps = 0.4 },
	{ mr = 0.82, mg = 0.84, mb = 1.02, lift = 4, sat = 0.98, lamps = 0.6 },
	{ mr = 0.84, mg = 0.7, mb = 1.0, lift = 6, sat = 0.98, lamps = 0.75 },
	{ mr = 0.98, mg = 0.78, mb = 0.62, lift = 4, sat = 1.04, lamps = 0.9 },
}

-- Each rarity's colours in the scene: its rays and its sparks (palette keys).
local RAY: { { string } } = { { "cream", "white" }, { "green", "white" }, { "blue", "white" }, { "purple", "pink" }, { "gold", "yellow" } }

local KNACK: { [string]: string } = { farm = "good at farms", fish = "good at fishing", wood = "good with wood", shop = "good at shops" }

------------------------------------------------------------------ state
type Shard = { p: BasePart, v: Vector3, w: number, at: Vector3, born: number, rest: boolean }
type Dot = { gui: GuiObject, world: Vector3?, x: number, y: number, vx: number, vy: number, g: number, born: number, life: number, frames: { GuiObject }? }
type Scene = {
	res: Result,
	after: (() -> ())?,
	r: number, -- the rarity shown now (it climbs to res.hr)
	folder: Folder,
	dyn: Folder,
	t0: number, -- when the blinds opened (the scene's clock runs from here; nil while they are shut: lifted)
	lifted: boolean,
	opened: number,
	clock: number,
	phase: string,
	-- the timeline (scene seconds)
	rises: { number }, -- when each step up flashes
	crackAt: number,
	listAt: number,
	endAt: number,
	-- the egg
	egg: Model?,
	parts: { { p: BasePart, off: CFrame } },
	top: { BasePart },
	fx: { { p: BasePart, kind: string, k: number } },
	cracks: { EggModels.Crack },
	glowing: boolean, -- the cracks lit from inside (the end of the build-up)
	topOff: number?, -- when the top flew off
	rays: { { p: BasePart, a: number, k: number } },
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
	shown: number, -- mutations listed so far
	flash: Frame?,
	curtain: Frame?,
	beat: RBXScriptConnection?,
	keys: RBXScriptConnection?,
	closing: boolean,
	events: { [string]: boolean },
}

local scene: Scene? = nil
local quick = false
local waitMax: number? = nil -- previews: how long the blinds may wait for the stage's picture (Tuning.HatchSceneWait)

local function glory(r: number): Glory
	return GLORY[math.clamp(r, 1, 5)]
end

local function ease(u: number): number
	local k = math.clamp(u, 0, 1)
	return k * k * (3 - 2 * k)
end

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

-- The camera's own axes (world): toward the picture's right and up, and the way it looks.
local LOOK = Vector3.new(-1, -1.15, -1).Unit
local RIGHT = Vector3.new(1, 0, -1).Unit
local UP = RIGHT:Cross(LOOK)
if UP.Y < 0 then
	UP = -UP
end

------------------------------------------------------------------ the stage
-- A little islet floating in the painted sky (UI/HatchBackdrop shows round it: the stage's sky is see-through): a grassy
-- top with a darker rim and a mossy middle, a band of soil, a rounded rocky underside of overlapping stones with roots
-- and moss hanging off its edge; in the middle a woven nest (three rings of twigs, feathers and moss on its rim, a bed
-- of straw); round the back two big spotted mushrooms and a little cluster, a stump with a candle, two lanterns on
-- posts, ferns, grass tufts, flowers and pebbles. Everything world-aligned on the iso grid.
local ISLE = 4.2 -- the islet's radius
local function buildSet(folder: Folder)
	local seed = 4217
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local function part(size: Vector3, cf: CFrame, color: string, shape: string?, neon: boolean?): BasePart
		return Blocks.part(folder, { size = size, cf = CFrame.new(ORIGIN) * cf, color = color, shape = shape :: any, neon = neon, collide = false })
	end
	local function disc(dia: number, h: number, x: number, y: number, z: number, color: string, neon: boolean?): BasePart
		return part(Vector3.new(h, dia, dia), CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2), color, "Cylinder", neon)
	end
	local function post(dia: number, h: number, x: number, y0: number, z: number, color: string): BasePart
		return part(Vector3.new(h, dia, dia), CFrame.new(x, y0 + h / 2, z) * CFrame.Angles(0, 0, math.pi / 2), color, "Cylinder")
	end
	local function ball(dia: number, x: number, y: number, z: number, color: string, neon: boolean?): BasePart
		return part(Vector3.new(dia, dia, dia), CFrame.new(x, y, z), color, "Ball", neon)
	end
	-- (a thin piece from a to b, `w` thick)
	local function rod(a: Vector3, b: Vector3, w: number, color: string): BasePart
		return part(Vector3.new(w, w, (b - a).Magnitude + w * 0.5), CFrame.lookAt((a + b) / 2, b), color)
	end
	-- (a round twig or stem from a to b)
	local function twig(a: Vector3, b: Vector3, w: number, color: string): BasePart
		return part(Vector3.new((b - a).Magnitude + w * 0.4, w, w), CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), color, "Cylinder")
	end
	-- (a pointed leaf or blade from a to its tip b, `w` wide, lying in the plane facing `n`: a wedge turned so its
	-- triangle is the leaf; it sways in the wind like the islands' leaves)
	local function blade(a: Vector3, b: Vector3, w: number, n: Vector3, color: string): BasePart
		local p = part(Vector3.new(0.06, w, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b, n) * CFrame.Angles(0, 0, math.pi / 2), color, "Wedge")
		p:SetAttribute("PixelWind", 1)
		return p
	end
	-- (a four-sided pyramid on `base`: four corner wedges, their points over the middle)
	local QUARTERS = { { -1, 1, 0 }, { 1, 1, math.pi / 2 }, { 1, -1, math.pi }, { -1, -1, -math.pi / 2 } }
	local function cone(base: CFrame, w: number, h: number, color: string)
		local q = w / 2
		for _, sq in QUARTERS do
			Blocks.part(folder, { size = Vector3.new(q, h, q), cf = CFrame.new(ORIGIN) * base * CFrame.new(sq[1] * q / 2, h / 2, sq[2] * q / 2) * CFrame.Angles(0, sq[3], 0), color = color, shape = "CornerWedge", collide = false })
		end
	end
	-- the islet: grass on top, soil under it, stones under that
	disc(ISLE * 2, 0.3, 0, -0.15, 0, "grass_dark")
	disc(ISLE * 2 - 0.9, 0.06, 0, 0.03, 0, "grass")
	disc(4.6, 0.06, 0.15, 0.05, 0.15, "moss")
	disc(ISLE * 2 - 0.2, 0.75, 0, -0.66, 0, "wood_dark")
	disc(ISLE * 2 - 1.0, 0.6, 0, -1.3, 0, "rock")
	for k = 0, 17 do
		local a = k / 18 * math.pi * 2 + rnd() * 0.2
		local rr = ISLE - 0.75 - rnd() * 0.3
		local cf = CFrame.new(math.cos(a) * rr, -1.45 - rnd() * 0.3, math.sin(a) * rr) * CFrame.Angles(rnd() * 0.4, -a, rnd() * 0.4)
		part(Vector3.new(1.1 + rnd() * 0.5, 0.8 + rnd() * 0.4, 0.9), cf, if k % 3 == 0 then "rock_dark" else "rock", if k % 3 == 1 then "Wedge" else nil)
		-- (a chip of stone jutting under it, a facet catching the light)
		part(Vector3.new(0.5, 0.6, 0.5), cf * CFrame.new(0.2, -0.55, 0.15) * CFrame.Angles(math.pi, rnd() * 3, 0), "rock_dark", "CornerWedge")
	end
	for _, b in { { 0, -2.5, 0, 3.6, "rock_dark" }, { 1.3, -2.0, -0.7, 2.4, "rock" }, { -1.2, -2.1, 0.8, 2.6, "rock" }, { 0.7, -3.2, 0.8, 1.9, "rock_dark" }, { -0.5, -3.8, -0.3, 1.3, "rock" }, { 1.6, -1.8, 1.5, 1.4, "rock_dark" }, { -1.7, -1.9, -1.4, 1.5, "rock_dark" } } :: { { any } } do
		ball(b[4], b[1], b[2], b[3], b[5])
	end
	-- roots and moss hanging off the edge (the front, where the view sees them)
	for k = 0, 6 do
		local a = math.rad(-40 + k * 27 + rnd() * 8)
		local x, z = math.cos(a) * (ISLE - 0.1), math.sin(a) * (ISLE - 0.1)
		local len = 0.5 + rnd() * 0.9
		if k % 2 == 0 then
			local mid = Vector3.new(x * 0.97 + 0.1, -0.7 - len * 0.5, z * 0.97)
			rod(Vector3.new(x, -0.5, z), mid, 0.07, "wood_dark")
			rod(mid, Vector3.new(x * 0.93, -0.8 - len, z * 0.93 + 0.1), 0.05, "wood_dark")
		else
			rod(Vector3.new(x, -0.3, z), Vector3.new(x * 1.01, -0.4 - len * 0.6, z * 1.01), 0.08, "leaf_dark")
			ball(0.16, x * 1.01, -0.4 - len * 0.6, z * 1.01, "leaf")
		end
	end
	-- the nest: three rings of twigs, each wider and higher, laid round in turn; a bed of straw; feathers and moss
	disc(2.9, 0.18, 0, 0.12, 0, "sand_dark")
	disc(2.2, 0.08, 0, NEST_Y - 0.03, 0, "straw")
	local TWIG = { "wood", "straw", "wood_dark", "sand_dark" }
	for ring = 0, 2 do
		local n = 16 + ring * 4
		local rr = 1.2 + ring * 0.2
		for k = 0, n - 1 do
			local a = (k + ring * 0.5) / n * math.pi * 2
			local y = 0.2 + ring * 0.13 + (k % 2) * 0.04
			local len = 0.85 + rnd() * 0.3
			local tang = Vector3.new(-math.sin(a), (rnd() - 0.5) * 0.4, math.cos(a)).Unit
			local c0 = Vector3.new(math.cos(a) * rr, y, math.sin(a) * rr)
			twig(c0 - tang * len / 2, c0 + tang * len / 2, 0.13, TWIG[(k + ring) % #TWIG + 1])
		end
	end
	-- (twigs sticking out of it)
	for k = 0, 6 do
		local a = k * 0.9 + 0.3
		local p0 = Vector3.new(math.cos(a) * 1.3, 0.5, math.sin(a) * 1.3)
		twig(p0, p0 + Vector3.new(math.cos(a + 0.4) * 0.6, 0.15 + rnd() * 0.25, math.sin(a + 0.4) * 0.6), 0.08, TWIG[k % #TWIG + 1])
	end
	for k, f in { { 0.9, "white" }, { 2.0, "cream" }, { 3.3, "white" }, { 5.0, "cream" } } :: { { any } } do
		local a = f[1]
		local p0 = Vector3.new(math.cos(a) * 1.45, 0.62, math.sin(a) * 1.45)
		part(Vector3.new(0.18, 0.05, 0.62), CFrame.lookAt(p0, p0 + Vector3.new(math.cos(a), 0.35, math.sin(a))) * CFrame.new(0, 0, -0.25), f[2])
		local _ = k
	end
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + 0.2
		ball(0.26 + rnd() * 0.1, math.cos(a) * 1.55, 0.52, math.sin(a) * 1.55, if k % 2 == 0 then "moss" else "leaf")
	end
	-- two big spotted mushrooms at the back and a little cluster
	local function mushroom(x: number, z: number, sc: number)
		post(0.55 * sc, 1.4 * sc, x, 0, z, "cream")
		disc(0.75 * sc, 0.08, x, 0.02, z, "moss")
		-- the cap: a wide brim and a dome over it, white spots set into the dome on the side the view sees
		disc(1.9 * sc, 0.35 * sc, x, 1.5 * sc, z, "berry_red")
		part(Vector3.new(1.7 * sc, 1.7 * sc, 1.7 * sc), CFrame.new(x, 1.35 * sc, z), "berry_red", "Ball")
		disc(1.6 * sc, 0.08, x, 1.3 * sc, z, "cream")
		disc(1.2 * sc, 0.06, x, 1.26 * sc, z, "sand_dark")
		disc(0.75 * sc, 0.1, x, 0.95 * sc, z, "cream")
		for k, d in { { 0.6, 0.5 }, { 1.4, 0.75 }, { 2.3, 0.45 }, { 0.2, 1.1 }, { 1.0, 1.25 }, { 2.0, 1.0 } } do
			local _ = k
			local a, e = d[1], d[2]
			local rr = 0.84 * sc
			ball(0.3 * sc, x + math.cos(a) * math.cos(e) * rr, 1.35 * sc + math.sin(e) * rr, z + math.sin(a) * math.cos(e) * rr, "white")
		end
	end
	mushroom(-3.0, -1.5, 0.8)
	mushroom(-1.3, -3.2, 0.58)
	for k, m in { { -2.0, -2.2, 0.32 }, { -2.3, -2.6, 0.24 }, { -1.7, -2.6, 0.2 } } do
		local _ = k
		post(0.16 * m[3] / 0.3, 0.45 * m[3] / 0.3, m[1], 0, m[2], "cream")
		ball(m[3] * 1.6, m[1], 0.5 * m[3] / 0.3, m[2], "orange")
	end
	-- a stump with a candle on it
	post(1.2, 0.7, 2.6, 0, -1.9, "wood_dark")
	disc(1.05, 0.06, 2.6, 0.71, -1.9, "wood")
	disc(0.75, 0.065, 2.6, 0.72, -1.9, "sand_dark")
	disc(0.45, 0.07, 2.6, 0.73, -1.9, "wood")
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.3
		part(Vector3.new(0.3, 0.4, 0.55), CFrame.new(2.6 + math.cos(a) * 0.7, 0.2, -1.9 + math.sin(a) * 0.7) * CFrame.Angles(0, -a - math.pi / 2, 0), "wood_dark", "Wedge")
	end
	post(0.22, 0.4, 2.65, 0.74, -1.85, "cream")
	part(Vector3.new(0.14, 0.2, 0.14), CFrame.new(2.65, 1.25, -1.85), "orange", nil, true)
	rod(Vector3.new(2.1, 0.05, -1.4), Vector3.new(1.8, 0.05, -1.1), 0.16, "wood_dark")
	-- two lanterns on posts, either side
	local function lantern(x: number, z: number)
		post(0.22, 2.4, x, 0, z, "wood_dark")
		part(Vector3.new(0.7, 0.12, 0.12), CFrame.new(x + 0.3, 2.35, z), "wood_dark")
		part(Vector3.new(0.42, 0.5, 0.42), CFrame.new(x + 0.62, 1.95, z), "yellow", nil, true)
		part(Vector3.new(0.56, 0.08, 0.56), CFrame.new(x + 0.62, 2.22, z), "wood_dark")
		cone(CFrame.new(x + 0.62, 2.26, z), 0.62, 0.32, "wood_dark")
		part(Vector3.new(0.52, 0.08, 0.52), CFrame.new(x + 0.62, 1.66, z), "wood_dark")
		cone(CFrame.new(x + 0.62, 1.62, z) * CFrame.Angles(math.pi, 0, 0), 0.4, 0.14, "wood_dark")
		part(Vector3.new(0.06, 0.5, 0.06), CFrame.new(x + 0.4, 1.95, z + 0.21), "wood_dark")
		part(Vector3.new(0.06, 0.5, 0.06), CFrame.new(x + 0.84, 1.95, z - 0.21), "wood_dark")
	end
	lantern(-3.3, 1.5)
	lantern(1.3, -3.4)
	-- ferns, grass tufts, flowers and pebbles round the edge
	local function fern(x: number, z: number, sc: number)
		for k = 0, 6 do
			local a = k / 7 * math.pi * 2 + x
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local base = Vector3.new(x, 0.1, z)
			local mid = base + dir * 0.55 * sc + Vector3.new(0, 0.55 * sc, 0)
			local tip = base + dir * 1.15 * sc + Vector3.new(0, 0.3 * sc, 0)
			local n = Vector3.new(0, 1, 0)
			blade(base, mid, 0.3 * sc, n, if k % 2 == 0 then "leaf" else "leaf_dark")
			blade(mid, tip, 0.26 * sc, n, if k % 2 == 0 then "leaf" else "leaf_dark")
		end
	end
	fern(-3.4, -2.4, 1.05)
	fern(0.7, -3.9, 0.9)
	fern(3.6, -0.3, 1)
	fern(-3.9, 0.3, 0.85)
	for k = 0, 8 do
		local a = math.rad(-60 + k * 24) + rnd() * 0.2
		local rr = ISLE - 0.4 - rnd() * 0.9
		local x, z = math.cos(a) * rr, math.sin(a) * rr
		for j = 0, 2 do
			local lean = Vector3.new((j - 1) * 0.12 + (rnd() - 0.5) * 0.1, 0.32 + rnd() * 0.2, (rnd() - 0.5) * 0.1)
			local b0 = Vector3.new(x + (j - 1) * 0.08, 0.02, z)
			blade(b0, b0 + lean, 0.1, Vector3.new(1, 0, 1).Unit, if (k + j) % 2 == 0 then "grass" else "leaf")
		end
	end
	for k, f in { { 2.3, 2.0, "pink" }, { 2.8, 1.2, "yellow" }, { -1.6, 2.7, "white" }, { -2.4, 2.1, "pink" }, { 3.2, -2.9, "white" }, { -3.1, -3.4, "yellow" }, { 1.0, 3.1, "yellow" }, { 3.3, 0.9, "purple" }, { -0.4, 3.4, "pink" } } :: { { any } } do
		local _ = k
		twig(Vector3.new(f[1], 0, f[2]), Vector3.new(f[1] + 0.03, 0.34, f[2]), 0.06, "leaf_dark")
		blade(Vector3.new(f[1], 0.04, f[2]), Vector3.new(f[1] + 0.22, 0.2, f[2] + 0.05), 0.12, Vector3.new(1, 0, 1).Unit, "leaf")
		for j = 0, 5 do
			local a = j / 6 * math.pi * 2
			disc(0.16, 0.05, f[1] + math.cos(a) * 0.11, 0.37, f[2] + math.sin(a) * 0.11, f[3])
		end
		ball(0.12, f[1], 0.39, f[2], "yellow")
	end
	for k, pb in { { 1.7, 1.6 }, { -1.5, 1.8 }, { 1.9, -1.2 }, { -0.4, 2.3 }, { 2.9, 2.6 }, { -2.8, 2.9 } } do
		part(Vector3.new(0.4, 0.22, 0.32), CFrame.new(pb[1], 0.11, pb[2]) * CFrame.Angles(0, pb[1], 0), if k % 2 == 0 then "rock" else "rock_dark")
	end
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
	m:SetAttribute("PixelShadow", 1.1)
	m:SetAttribute("PixelGroundY", ORIGIN.Y + NEST_Y)
	m.Parent = s.dyn
	PixelRenderer.registerDynamic(m)
	s.egg, s.parts, s.top, s.fx, s.cracks, s.glowing = m, parts, top, fx, cracks, false
end

-- The rays of light behind the egg: thin bright blades in the picture's own plane (they face the camera), turning
-- round the egg's middle a little behind it.
local function newRays(s: Scene, r: number)
	for _, ray in s.rays do
		ray.p:Destroy()
	end
	table.clear(s.rays)
	local g = glory(r)
	if g.rays <= 0 then
		return
	end
	local m = Blocks.model(nil, "HatchRays")
	for k = 1, g.rays do
		local p = Blocks.part(m, { size = Vector3.new(0.25, 0.05, 1), cf = CFrame.new(ORIGIN), color = RAY[r][(k % 2) + 1], neon = true, collide = false, query = false, name = "Ray" })
		table.insert(s.rays, { p = p, a = (k - 1) / g.rays * math.pi * 2, k = k })
	end
	m.Parent = s.dyn
	PixelRenderer.registerDynamic(m)
end

local function eggMiddle(r: number): Vector3
	return at(0, NEST_Y + 0.5 * (EGG_H[r] or 2.4), 0)
end

-- The painted sky behind the stage (UI/HatchBackdrop), the egg's glow round where it stands on screen; only with the
-- pixel filter on (in the classic look Roblox's own sky shows).
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

------------------------------------------------------------------ the timeline
-- The scene's beats (scene seconds from the blinds opening): the egg rocks GLORY.rocks times (by the rarity it was
-- laid as), then each step up (1.7 s each), then the build-up to the crack (by the rarity it hatched as), what hatched
-- (its name at once, the mutations listed half a second apart), and a short hold before Tap shows.
local INTRO = 0.7
local ROCK = 0.55
local RISE = 1.7
local function plan(s: Scene)
	local res = s.res
	local t = INTRO + glory(res.r).rocks * ROCK
	s.rises = {}
	for _ = res.r + 1, res.hr do
		table.insert(s.rises, t + 0.9)
		t += RISE
	end
	s.crackAt = t + glory(res.hr).build
	s.listAt = s.crackAt + 1.1
	s.endAt = s.listAt + 0.5 * #res.muts + 0.6
end

-- What hatched, under it: its name in its rarity's colour, its rarity and knack.
local function showName(s: Scene)
	local w, h = canvasSize()
	local def = Creatures.byId[s.res.sp]
	local rar = Traits.RARITY[if def then def.rarity else s.r] or Traits.RARITY[1]
	local nm = UIKit.text(s.root, if def then def.name else "A driftling", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, h - 36), { x = "center", face = "big", kind = "title", color = UIKit.color(rar.color), z = 33, name = "HatchName" })
	local line = UIKit.text(s.root, if def then string.format("%s, %s", rar.name, KNACK[def.knack] or "a hard worker") else rar.name, UDim2.fromOffset(w, 10), UDim2.fromOffset(0, h - 18), { x = "center", color = UIKit.color("paper"), z = 33, name = "HatchLine" })
	s.name, s.line = nm, line
	nm.Position = UDim2.fromOffset(0, h - 30)
	UIKit.tween(nm, 0.2, { Position = UDim2.fromOffset(0, h - 36) })
	local old = s.title
	if old then
		old:Destroy()
		s.title = nil
	end
	setTitle(s, "It hatched", "paper")
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
	local f = UIKit.plate(s.root, UDim2.fromOffset(PLATE_W, PLATE_H), UDim2.fromOffset(x + 30, y), UIKit.color("plate"), 0.04, 3, { shadow = true })
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

------------------------------------------------------------------ every frame
local closeScene: (s: Scene) -> ()

local function once(s: Scene, key: string): boolean
	if s.events[key] then
		return false
	end
	s.events[key] = true
	return true
end

local function stepEgg(s: Scene, c: number)
	local r = s.r
	local g = glory(s.res.hr)
	local foot = at(0, NEST_Y, 0)
	local tilt, lift = 0, 0
	-- rocking: each rock a little harder than the last
	local rocks = glory(s.res.r).rocks
	local u = (c - INTRO) / ROCK
	if u >= 0 and u < rocks then
		local k = u % 1
		if k < 0.6 then
			tilt = math.sin(k / 0.6 * math.pi * 2) * (0.07 + 0.035 * math.floor(u))
			if once(s, "rock" .. math.floor(u)) then
				Audio.play("tick", { pitch = 0.9 + 0.1 * math.floor(u) })
				local mid = eggMiddle(r)
				burst(s, mid, r, 3 + math.floor(u), 30)
			end
		end
	end
	-- a step up: a hard shake, then the flash and the next rarity's egg
	for i, rt in s.rises do
		local d = c - (rt - 0.9)
		if d >= 0 and d < 0.9 then
			tilt = math.sin(d * 46) * (0.1 + d * 0.14)
			lift = math.abs(math.sin(d * 23)) * 0.06
			if once(s, "riseshake" .. i) then
				Audio.play("tick", { pitch = 1.3 })
			end
		end
		if c >= rt and once(s, "rise" .. i) then
			s.r = math.min(5, s.res.r + i)
			newEgg(s, s.r)
			newRays(s, if s.r >= 3 then s.r else 0)
			DayLight.hold(GRADE[s.r])
			backdrop(s)
			flash(s, 0.45)
			burst(s, eggMiddle(s.r), s.r, 18 + s.r * 4, 70)
			for k = 1, 4 + s.r do
				local a = k / (4 + s.r) * math.pi * 2
				local px, py = PixelRenderer.projectPixel(eggMiddle(s.r))
				addStar(s, { "twinkle_1", "twinkle_2", "twinkle_1" }, px + math.cos(a) * 26, py + math.sin(a) * 20, 0.6)
			end
			Audio.play("level_up")
			Audio.play("rare")
			setTitle(s, "It turned " .. string.lower((Traits.RARITY[s.r] or Traits.RARITY[1]).name), (Traits.RARITY[s.r] or Traits.RARITY[1]).color)
			s.phase = "rise"
		end
	end
	-- the build-up: shaking harder and harder, the light gathering, the clearing dimming (epic and up)
	local b0 = s.crackAt - g.build
	if c >= b0 and c < s.crackAt then
		local k = (c - b0) / g.build
		tilt = math.sin(c * (30 + k * 30)) * (0.05 + k * 0.16)
		lift = math.abs(math.sin(c * 21)) * 0.05 * k
		if once(s, "build") then
			s.phase = "build"
			Audio.play("tick", { pitch = 1.1 })
		end
		if g.dim > 0 then
			PixelRenderer.setDim(g.dim * ease(k))
		end
		-- sparks drawn in toward the egg
		if math.random() < 0.25 + k * 0.6 then
			local mid = eggMiddle(r)
			local a = math.random() * math.pi * 2
			local px, py = PixelRenderer.projectPixel(mid)
			local d = 40 + math.random() * 30
			addDot(s, RAY[r][(math.random(1, 2))], nil, px + math.cos(a) * d, py + math.sin(a) * d, -math.cos(a) * d * 2.2, -math.sin(a) * d * 2.2, 0, 0.42)
		end
	end
	-- the crack
	if c >= s.crackAt and once(s, "crack") then
		s.phase = "crack"
		s.topOff = c
		local mid = eggMiddle(r)
		local look = EggModels.LOOK[r] or EggModels.LOOK[1]
		Audio.play("pop", { pitch = 0.8 })
		if s.res.hr >= 3 then
			Audio.play("rare")
		end
		if s.res.hr >= 4 then
			Audio.play("reward")
		end
		flash(s, g.flash)
		burst(s, mid, r, g.sparks, 90)
		-- bits of shell flying out
		local bits = Blocks.model(nil, "HatchShards")
		for k = 1, g.shards do
			local a = k / g.shards * math.pi * 2 + math.random() * 0.4
			local sz = 0.14 + math.random() * 0.14
			local p = Blocks.part(bits, { size = Vector3.new(sz, sz * 0.6, sz), cf = CFrame.new(mid), color = if k % 3 == 0 then look.mark else look.body, collide = false, query = false, name = "Shard" })
			local v = Vector3.new(math.cos(a) * (2 + math.random() * 2.5), 4 + math.random() * 3, math.sin(a) * (2 + math.random() * 2.5))
			table.insert(s.shards, { p = p, v = v, w = (math.random() - 0.5) * 14, at = mid, born = c, rest = false })
		end
		bits.Parent = s.dyn
		PixelRenderer.registerDynamic(bits)
		-- what hatched
		local def = Creatures.byId[s.res.sp]
		local thing = MicroModels.driftling(if def then def.shape else "blob", if def then def.body else "steel", if def then def.accent else "steel_dark")
		thing.model:SetAttribute("PixelShadow", 1.1)
		thing.model:SetAttribute("PixelGroundY", ORIGIN.Y + NEST_Y)
		MicroModels.scale(thing, Vector3.one * 0.3)
		thing.model.Parent = s.dyn
		PixelRenderer.registerDynamic(thing.model)
		s.pal = thing
		s.popAt = c + 0.12
		-- the picture jolts (epic and up), confetti falls (epic and up), stars ring it (legendary)
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
	end
	-- the egg: lying, rocking, shaking; at the crack its top flies off and the rest sinks into the straw
	local eh = EGG_H[r] or 2.4
	local cf = CFrame.new(foot + Vector3.new(0, lift, 0)) * CFrame.Angles(tilt, 0, tilt * 0.6)
	local off = s.topOff
	for _, rp in s.parts do
		local here = cf * rp.off
		if off then
			local k = (c - off) / 0.6
			if table.find(s.top, rp.p) then
				here = cf * CFrame.new(1.1 * k, eh * (1.1 * k - 0.8 * k * k), 0.7 * k) * CFrame.Angles(0, 0, -2.6 * k) * rp.off
			else
				here = here - Vector3.new(0, ease(k) * eh * 0.7, 0)
			end
		end
		rp.p.CFrame = here
	end
	-- its cracks: the first at its second rock, running down and branching as the shaking starts, round its middle
	-- halfway through it, and lit from inside near the end (the rarity's light through them)
	local rocks2 = INTRO + ROCK * math.min(1, rocks - 1) + 0.15
	local stage = if c >= b0 + g.build * 0.5 then 3 elseif c >= b0 then 2 elseif c >= rocks2 then 1 else 0
	if stage >= 1 and once(s, "crackline" .. stage .. ":" .. r) then
		Audio.play("tick", { pitch = 0.7 + stage * 0.12 })
	end
	if not s.glowing and c >= b0 + g.build * 0.6 and s.egg then
		s.glowing = true
		for _, k in s.cracks do
			k.p.Color = Blocks.color(RAY[r][2])
			k.p.Material = Enum.Material.Neon
		end
		PixelRenderer.refreshDynamic(s.egg :: Model)
	end
	for _, k in s.cracks do
		k.p.CFrame = if off == nil and k.stage <= stage then cf * k.off else CFrame.new(foot - Vector3.new(0, 9, 0))
	end
	if off and c - off > 0.6 and s.egg then
		dropEgg(s)
	end
	-- the rarity's lights on the egg: motes circling it, a halo turning over it, a beam out of its top
	local er = 0.37 * eh
	for _, f in s.fx do
		if off then
			f.p.CFrame = CFrame.new(foot - Vector3.new(0, 9, 0))
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
	-- the rays: grow in the build-up, flare at the crack, then stay turning slowly behind what hatched (epic and up) or
	-- fade (rare)
	if #s.rays > 0 then
		local grow = if c < b0 then 0 else ease((c - b0) / math.max(0.1, g.build))
		local after = if c >= s.crackAt then c - s.crackAt else -1
		local len = g.rayLen * grow
		local wid = 0.2
		if after >= 0 then
			len = g.rayLen * (1 + 0.35 * math.max(0, 1 - after / 0.5))
			if s.res.hr <= 3 then
				local fade = math.clamp(1 - (after - 0.6) / 0.8, 0, 1)
				len *= fade
				wid *= math.max(0.4, fade)
			end
		end
		local mid = eggMiddle(math.max(r, 1)) + LOOK * 2.4
		for _, ray in s.rays do
			local a = ray.a + c * (0.35 + 0.05 * (ray.k % 3))
			local dir = RIGHT * math.cos(a) + UP * math.sin(a)
			local l = len * (if ray.k % 2 == 0 then 1 else 0.7)
			if l < 0.1 then
				ray.p.CFrame = CFrame.new(mid - Vector3.new(0, 30, 0))
			else
				local center = mid + dir * (0.6 + l / 2)
				ray.p.Size = Vector3.new(wid, 0.05, l)
				ray.p.CFrame = CFrame.lookAt(center, center + dir, -LOOK)
			end
		end
	end
end

local function stepPal(s: Scene, c: number, dt: number)
	local thing = s.pal
	local pop = s.popAt
	if thing == nil or pop == nil then
		return
	end
	local k = (c - pop) / 0.45
	local sc = if k < 0 then 0.3 elseif k < 0.6 then 0.3 + (PAL_SCALE * 1.15 - 0.3) * ease(k / 0.6) else PAL_SCALE * (1.15 - 0.15 * ease((k - 0.6) / 0.4))
	MicroModels.scale(thing, Vector3.one * sc)
	local hop = if k < 1 then math.sin(math.clamp(k, 0, 1) * math.pi) * 0.9 else math.max(0, math.sin((c - pop) * 5.5)) * 0.08
	local mood = if c - pop < 2.2 then "cheer" else "idle"
	MicroModels.animate(thing, c, mood, 0)
	MicroModels.place(thing, CFrame.new(at(0, NEST_Y + hop, 0)) * CFrame.Angles(0, math.pi / 4, 0))
	local _ = dt
end

local function stepShards(s: Scene, c: number, dt: number)
	local keep: { Shard } = {}
	for _, sh in s.shards do
		local age = c - sh.born
		if age > 3 then
			sh.p:Destroy()
			continue
		end
		if not sh.rest then
			sh.v -= Vector3.new(0, 26 * dt, 0)
			sh.at += sh.v * dt
			local floor = ORIGIN.Y + (if (sh.at - ORIGIN).Magnitude < 1.2 then NEST_Y else 0.06)
			if sh.at.Y < floor then
				sh.at = Vector3.new(sh.at.X, floor, sh.at.Z)
				if math.abs(sh.v.Y) < 1.2 then
					sh.rest = true
				end
				sh.v = Vector3.new(sh.v.X * 0.5, -sh.v.Y * 0.35, sh.v.Z * 0.5)
			end
		end
		-- (late on they sink into the grass)
		local sink = math.max(0, age - 2.2) * 0.5
		sh.p.CFrame = CFrame.new(sh.at - Vector3.new(0, sink, 0)) * CFrame.Angles(sh.w * age * 0.3, sh.w * age, 0)
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

local function step(s: Scene, dt: number)
	local now = os.clock()
	if not s.lifted then
		-- the blinds open once the stage's picture is done (or after a while whatever happens)
		if (PixelRenderer.ready() and now - s.opened >= 0.35) or now - s.opened > (waitMax or Tuning.HatchSceneWait) then
			s.lifted = true
			s.t0 = now
			local cur = s.curtain
			if cur then
				local _, h = canvasSize()
				local mid = math.ceil(h / BLIND) / 2
				for i, band in cur:GetChildren() do
					if band:IsA("Frame") and band.Name == "Blind" then
						local d = math.min(math.abs(i - 0.5 - mid), mid + 1) * 0.015
						local y0 = band.Position.Y.Offset
						local bh = band.Size.Y.Offset
						task.delay(d, function()
							if band.Parent then
								UIKit.tween(band, 0.16, { Size = UDim2.new(1, 0, 0, 0), Position = UDim2.fromOffset(0, y0 + math.floor(bh / 2)) })
							end
						end)
					end
				end
				task.delay(0.5, function()
					if cur.Parent then
						cur:Destroy()
					end
				end)
				s.curtain = nil
			end
			setTitle(s, eggWords(s.r), (Traits.RARITY[s.r] or Traits.RARITY[1]).color)
			s.phase = "egg"
			if s.res.r >= 4 then
				Audio.play("egg")
			end
		end
		return
	end
	local d = math.min(dt, 0.1)
	s.clock += d
	local c = s.clock
	stepEgg(s, c)
	stepPal(s, c, d)
	stepShards(s, c, d)
	fireflies(s, c)
	stepDots(s, d)
	HatchBackdrop.step(d)
	if c >= s.crackAt + 0.35 and once(s, "name") then
		showName(s)
		s.phase = "reveal"
		if s.res.hr >= 4 then
			Audio.play("cheer")
		end
		if s.res.hr >= 3 then
			PixelRenderer.setDim(glory(s.res.hr).dim * 0.5)
		end
	end
	-- the mutations, one by one
	local n = math.max(1, #s.res.muts)
	while s.shown < n and c >= s.listAt + s.shown * 0.5 do
		s.shown += 1
		showMut(s, s.shown)
	end
	if c >= s.endAt and once(s, "hint") then
		s.phase = "done"
		local w, h = canvasSize()
		local hint = UIKit.text(s.root, "Tap to go on", UDim2.fromOffset(w, 10), UDim2.fromOffset(0, 30), { x = "center", color = UIKit.color("text_dim"), z = 33, name = "HatchHint" })
		s.hint = hint
		local _ = h
	end
	local hint = s.hint
	if hint then
		hint.Visible = math.floor(c * 2) % 2 == 0
	end
	if c >= s.endAt + Tuning.HatchSceneHold then
		closeScene(s)
	end
end

------------------------------------------------------------------ open and close
-- A tap: before the crack it jumps to the crack (the steps up all taken at once); before the list is done it shows the
-- rest of it; after that it goes back to the island.
function HatchScene.skip()
	local s = scene
	if s == nil or s.closing then
		return
	end
	if not s.lifted then
		return
	end
	if s.clock < s.crackAt - 0.05 then
		-- (the steps up at once: the egg in the last rarity, no shake)
		if s.r ~= s.res.hr then
			s.r = s.res.hr
			newEgg(s, s.r)
			newRays(s, if s.r >= 3 then s.r else 0)
			DayLight.hold(GRADE[s.r])
			backdrop(s)
			setTitle(s, eggWords(s.r), (Traits.RARITY[s.r] or Traits.RARITY[1]).color)
		end
		for i = 1, #s.rises do
			s.events["rise" .. i] = true
			s.events["riseshake" .. i] = true
		end
		s.events["build"] = true
		for k = 0, 8 do
			s.events["rock" .. k] = true
		end
		s.clock = s.crackAt - 0.02
	elseif s.clock < s.endAt then
		s.clock = s.endAt
		while s.shown < math.max(1, #s.res.muts) do
			s.shown += 1
			showMut(s, s.shown)
		end
	else
		closeScene(s)
	end
end

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
	for _, c in s.dyn:GetChildren() do
		if c:IsA("Model") then
			PixelRenderer.unregisterDynamic(c)
		end
	end
	s.dyn:Destroy()
	s.folder:Destroy()
	HatchBackdrop.hide()
	DayLight.hold(nil)
	PixelRenderer.setDim(0)
	PixelRenderer.setOffset(0, 0)
	if CameraController.stage() then
		CameraController.setStage(nil)
	end
	UIKit.root("Hud").Enabled = true
	UIKit.root("World").Enabled = true
end

-- The blinds close over the stage; behind them the stage goes, the island's picture comes back; they open on it and
-- `after` runs.
closeScene = function(s: Scene)
	if s.closing then
		return
	end
	s.closing = true
	local w, h = canvasSize()
	local cur = Instance.new("Frame")
	cur.Name = "HatchCurtainOut"
	cur.BackgroundTransparency = 1
	cur.Size = UDim2.fromScale(1, 1)
	cur.ZIndex = 45
	cur.Parent = s.root
	local bands: { Frame } = {}
	local n = 0
	for y = 0, 3 * h - 1, BLIND do
		local band = UIKit.rect(cur, UDim2.new(1, 0, 0, 0), UDim2.fromOffset(0, y + math.floor(BLIND / 2)), UIKit.color("ink"), 45)
		band.Name = "Blind"
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 45)
		table.insert(bands, band)
		n += 1
		local yy = y
		task.delay(math.min(n, math.ceil(h / BLIND)) * 0.01, function()
			if band.Parent then
				UIKit.tween(band, 0.16, { Size = UDim2.new(1, 0, 0, BLIND), Position = UDim2.fromOffset(0, yy) })
			end
		end)
	end
	local _ = w
	task.delay(0.4, function()
		restore(s)
		-- (the island's picture back: kept while the stage had the view, so it is there at once, or baked again)
		local t0 = os.clock()
		while not PixelRenderer.ready() and os.clock() - t0 < 2 do
			task.wait()
		end
		for i, band in bands do
			local bh = BLIND
			local y0 = band.Position.Y.Offset
			task.delay(math.abs(i - #bands / 6) * 0.004, function()
				if band.Parent then
					UIKit.tween(band, 0.16, { Size = UDim2.new(1, 0, 0, 0), Position = UDim2.fromOffset(0, y0 + math.floor(bh / 2)) })
				end
			end)
		end
		task.delay(0.35, function()
			s.root:Destroy()
		end)
		if scene == s then
			scene = nil
		end
		local after = s.after
		if after then
			after()
		end
	end)
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
	local folder = Instance.new("Folder")
	folder.Name = "HatchStage"
	buildSet(folder)
	folder.Parent = workspace
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
	local s: Scene = {
		res = res,
		after = after,
		r = math.clamp(res.r, 1, 5),
		folder = folder,
		dyn = dyn,
		t0 = 0,
		lifted = false,
		opened = os.clock(),
		clock = 0,
		phase = "curtain",
		rises = {},
		crackAt = 0,
		listAt = 0,
		endAt = 0,
		egg = nil,
		parts = {},
		top = {},
		fx = {},
		cracks = {},
		glowing = false,
		topOff = nil,
		rays = {},
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
		curtain = nil,
		beat = nil,
		keys = nil,
		closing = false,
		events = {},
	}
	res.hr = math.clamp(res.hr, s.r, 5)
	plan(s)
	-- the curtain while the stage's picture is baked (three screens deep: the pixel size may change under it)
	local _, h = canvasSize()
	local cur = Instance.new("Frame")
	cur.Name = "HatchCurtain"
	cur.BackgroundTransparency = 1
	cur.Size = UDim2.fromScale(1, 1)
	cur.ZIndex = 40
	cur.Parent = root
	for y = 0, 3 * h - 1, BLIND do
		local band = UIKit.rect(cur, UDim2.new(1, 0, 0, BLIND), UDim2.fromOffset(0, y), UIKit.color("ink"), 40)
		band.Name = "Blind"
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 40)
	end
	PixelSprites.image(cur, "egg_" .. s.r, UDim2.new(0.5, -6, 0.5, -8), 41).Name = "CurtainEgg"
	s.curtain = cur
	-- a tap anywhere: skip ahead (HatchScene.skip)
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
	-- the egg in its nest, the light of its rarity, the camera on the nest
	newEgg(s, s.r)
	newRays(s, if s.r >= 3 then s.r else 0)
	DayLight.hold(GRADE[s.r])
	scene = s
	-- (the islet's top whole, a little of its stones under it, the egg's top; the sky see-through round it)
	local pts: { number } = {}
	local e = ISLE * 0.707
	local wide = ISLE * 0.707 + 1.2
	for _, p in { { wide, 0, -wide }, { -wide, 0, wide }, { e, 0, e }, { -e, 0, -e }, { e * 0.8, -2.6, e * 0.8 }, { 0, NEST_Y + (EGG_H[5] or 2.8) + 0.5, 0 } } do
		table.insert(pts, ORIGIN.X + p[1])
		table.insert(pts, ORIGIN.Y + p[2])
		table.insert(pts, ORIGIN.Z + p[3])
	end
	CameraController.setStage({ name = "hatch", origin = ORIGIN, pts = pts, tight = nil, top = 30, bottom = 40, clear = true })
	backdrop(s)
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

-- Previews: the blinds wait up to `secs` for the stage's picture (the fake engine casts its rays slowly); nil: as set.
function HatchScene.setWait(secs: number?)
	waitMax = secs
end

-- Sims and previews: what the scene shows now.
function HatchScene.debugState(): { open: boolean, phase: string, r: number, hr: number, clock: number, crackAt: number, endAt: number, shown: number, muts: number, rays: number, shards: number, pal: boolean, egg: boolean, title: string, name: string }
	local s = scene
	if s == nil then
		return { open = false, phase = "", r = 0, hr = 0, clock = 0, crackAt = 0, endAt = 0, shown = 0, muts = 0, rays = 0, shards = 0, pal = false, egg = false, title = "", name = "" }
	end
	local t, n = s.title, s.name
	return {
		open = true,
		phase = s.phase,
		r = s.r,
		hr = s.res.hr,
		clock = s.clock,
		crackAt = s.crackAt,
		endAt = s.endAt,
		shown = s.shown,
		muts = #s.res.muts,
		rays = #s.rays,
		shards = #s.shards,
		pal = s.pal ~= nil,
		egg = s.egg ~= nil,
		title = if t then t.Text else "",
		name = if n then n.Text else "",
	}
end

return HatchScene
