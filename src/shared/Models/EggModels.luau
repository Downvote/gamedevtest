--!strict
-- The Tree of Life's eggs as models (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module: Controllers/EggView lays
-- them under the trees, UI/HatchScene holds one up close while it hatches.
--   EggModels.build(r, bare?, scale?) -> (model, parts, top, fx)   an egg of rarity r: its parts with their offsets
--                                                          from its foot, the shell's top half (it flies off when it
--                                                          hatches), the rarity's moving lights (motes, a beam);
--                                                          `bare`: no bed of straw and no glow on the lawn; `scale`
--                                                          times its size
--   EggModels.hero(r, h) -> (model, parts, top, fx, cracks)  the hatch scene's egg up close, h studs tall
--   EggModels.LOOK, EggModels.SIZE                         each rarity's shell and size
-- "color each egg differently with different effects to allow players to distinguish easily between egg rarities"
local Blocks = require(script.Parent.Blocks)

local EggModels = {}

local SIZE: { [number]: number } = { 1.25, 1.3, 1.38, 1.48, 1.62 } -- rarer eggs are a little bigger
EggModels.SIZE = SIZE
-- Each rarity's shell (its colour and its marks) and glow (Traits.RARITY's colours: grey, green, blue, purple, gold):
-- body, marks ("spots" freckles or stars, "band" a zigzag band round its middle), whether the marks glow, the glow on
-- the lawn under it.
export type Look = { body: string, mark: string, marks: string, glow: boolean, lawn: string? }
local LOOK: { [number]: Look } = {
	{ body = "cream", mark = "sand_dark", marks = "spots", glow = false },
	{ body = "green", mark = "white", marks = "band", glow = false },
	{ body = "blue", mark = "white", marks = "spots", glow = true },
	{ body = "purple", mark = "pink", marks = "spots", glow = true, lawn = "purple" },
	{ body = "gold", mark = "yellow", marks = "band", glow = true, lawn = "yellow" },
}
EggModels.LOOK = LOOK

-- An egg of rarity r (LOOK): a round shell on a bed of straw, its marks on it (freckles, stars or a zigzag band; glowing
-- from rare up), and from epic up its lights: a glow on the lawn under it, two motes circling it (epic) or a beam of
-- light standing up out of its top (legendary). Its parts' offsets from its foot; the top half (it flies off when it
-- hatches); the lights (moved every frame: stepEgg).
function EggModels.build(r: number, bare: boolean?, scale: number?): (Model, { { p: BasePart, off: CFrame } }, { BasePart }, { { p: BasePart, kind: string, k: number } })
	local m = Blocks.model(nil, "TreeEgg")
	local parts: { { p: BasePart, off: CFrame } } = {}
	local top: { BasePart } = {}
	local fx: { { p: BasePart, kind: string, k: number } } = {}
	local s = (SIZE[r] or 1) * (scale or 1)
	local look = LOOK[r] or LOOK[1]
	local function add(size: Vector3, off: CFrame, color: string, neon: boolean?, upper: boolean?, shape: string?)
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = neon, shape = shape :: any, name = if upper then "Top" else "Shell" })
		table.insert(parts, { p = p, off = off })
		if upper then
			table.insert(top, p)
		end
		return p
	end
	-- the glow on the lawn (epic and legendary): a thin disc of light just over the grass, round the straw
	if look.lawn and not bare then
		add(Vector3.new(0.25, 1.5 * s, 1.5 * s), CFrame.new(0, -0.11, 0) * CFrame.Angles(0, 0, math.pi / 2), look.lawn, true, nil, "Cylinder")
	end
	-- the bed of straw (not in the hatch scene's nest: `bare`)
	if not bare then
		add(Vector3.new(1.1 * s, 0.08, 0.55 * s), CFrame.new(0, 0.04, -0.25 * s), "sand")
		add(Vector3.new(0.55 * s, 0.08, 1.1 * s), CFrame.new(0.25 * s, 0.05, 0), "sand_dark")
		add(Vector3.new(1.0 * s, 0.06, 0.5 * s), CFrame.new(-0.05 * s, 0.06, 0.3 * s), "sand")
	end
	-- the shell: a broad round bottom and a smaller round top, overlapping (an egg's curve); the top the half that flies
	-- off when it hatches
	local y0 = 0.06
	local function ball(dia: number, off: CFrame, color: string, neon: boolean?, upper: boolean?)
		add(Vector3.new(dia, dia, dia), off, color, neon, upper, "Ball")
	end
	ball(0.86 * s, CFrame.new(0, y0 + 0.4 * s, 0), look.body)
	ball(0.78 * s, CFrame.new(0, y0 + 0.53 * s, 0), look.body)
	ball(0.66 * s, CFrame.new(0, y0 + 0.7 * s, 0), look.body, nil, true)
	if look.marks == "spots" then
		-- freckles or stars on the side facing the view, little round dabs set into the shell
		local sp = { { 0.3, 0.3, 0.22 }, { 0.48, 0.05, 0.4 }, { 0.56, 0.38, -0.02 }, { 0.36, -0.2, 0.33 }, { 0.82, 0.18, 0.2 }, { 0.62, -0.12, 0.3 } }
		for k, d in sp do
			ball(0.17 * s, CFrame.new(d[2] * s, y0 + d[1] * s, d[3] * s), look.mark, look.glow, k == 5)
		end
	else
		-- a zigzag band round its middle: dabs a little up and down in turn, all the way round
		for k = 0, 11 do
			local a = k * math.pi / 6
			local up = if k % 2 == 0 then 0.07 else -0.07
			ball(0.16 * s, CFrame.new(math.cos(a) * 0.4 * s, y0 + (0.46 + up) * s, math.sin(a) * 0.4 * s), look.mark, look.glow)
		end
	end
	if r >= 5 then
		-- a legendary egg: a band of light round its middle, and a beam standing up out of its top
		add(Vector3.new(0.62 * s, 0.06, 0.62 * s), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
		add(Vector3.new(0.06, 0.06, 0.9 * s), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
		add(Vector3.new(0.9 * s, 0.06, 0.06), CFrame.new(0, y0 + 0.4 * s, 0), "yellow", true)
		local beam = Blocks.part(m, { size = Vector3.new(0.25, 2, 0.25), cf = CFrame.new(0, y0 + 2 * s, 0), color = "yellow", collide = false, query = false, neon = true, name = "Beam" })
		table.insert(fx, { p = beam, kind = "beam", k = 0 })
	elseif r == 4 then
		-- an epic egg: two motes of light circling it, a pink one and a white one
		for k, c in { "pink", "white" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.25, 0.25, 0.25), cf = CFrame.new(0, y0 + 0.6 * s, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	end
	return m, parts, top, fx
end

------------------------------------------------------------------ the hatch scene's egg
-- The egg up close (UI/HatchScene): the request of 2026-11-13, "the egg hatching scene isnt detailed enough. add much
-- much more detail to it, especially the egg". Built `h` studs tall on its foot, facing the view (the camera looks from
-- +x +z: the side at azimuth 45 degrees is the front). The shell is 25 overlapping balls along its axis, sized to an
-- egg's profile (broad low, narrow high), so its outline is smooth; a shine high on the lit side (the top left); and the
-- rarity's own work on it:
--   common: cream with soft sandy patches and freckles of two browns;
--   uncommon: green with a white zigzag band, a vine winding up it with leaves, a sprout on top;
--   rare: sky blue with glowing white stars (each a bright middle and four points), a frosty band with icicles;
--   epic: purple with two pink stripes spiralling up it, glowing runes between them, a pink ring at its foot, three
--     motes circling it;
--   legendary: gold with a raised band set with red, blue and green gems in bezels, filigree scrolls, a crown of points
--     round its top, a halo of light turning over it and a beam standing up out of it.
-- Its cracks (`cracks`: each part with its stage, 1 a short crack at the top, 2 running down and branching, 3 round its
-- middle where the top comes off) are kept out of sight until the scene shows them; the top is what lies above the
-- middle crack. fx: "mote", "beam", "halo" (moved by the scene).
export type Crack = { p: BasePart, off: CFrame, stage: number }
local PROFILE: { { number } } = {
	{ 0, 0 },
	{ 0.04, 0.45 },
	{ 0.1, 0.72 },
	{ 0.2, 0.9 },
	{ 0.32, 0.99 },
	{ 0.45, 1 },
	{ 0.58, 0.95 },
	{ 0.7, 0.85 },
	{ 0.8, 0.72 },
	{ 0.88, 0.57 },
	{ 0.94, 0.41 },
	{ 0.98, 0.24 },
	{ 1, 0 },
}
local function prof(t: number): number
	local u = math.clamp(t, 0, 1)
	for i = 1, #PROFILE - 1 do
		local a, b = PROFILE[i], PROFILE[i + 1]
		if u <= b[1] then
			return a[2] + (b[2] - a[2]) * (u - a[1]) / math.max(1e-6, b[1] - a[1])
		end
	end
	return 0
end
local SPLIT = 0.56 -- where the top comes off (share of the height)

function EggModels.hero(r: number, h: number): (Model, { { p: BasePart, off: CFrame } }, { BasePart }, { { p: BasePart, kind: string, k: number } }, { Crack })
	local m = Blocks.model(nil, "HeroEgg")
	local parts: { { p: BasePart, off: CFrame } } = {}
	local top: { BasePart } = {}
	local fx: { { p: BasePart, kind: string, k: number } } = {}
	local cracks: { Crack } = {}
	local look = LOOK[r] or LOOK[1]
	local R = 0.37 * h -- the widest radius
	local seed = r * 7919 + 17
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	type AddOpts = { neon: boolean?, shape: string?, name: string? }
	local NONE: AddOpts = {}
	local function add(size: Vector3, off: CFrame, color: string, t: number, opts: AddOpts?): BasePart
		local o: AddOpts = opts or NONE
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = o.neon, shape = o.shape :: any, name = o.name or (if t > SPLIT then "Top" else "Shell") })
		table.insert(parts, { p = p, off = off })
		if t > SPLIT then
			table.insert(top, p)
		end
		return p
	end
	-- a point on the shell: height share t, azimuth a (radians), `out` studs off its surface
	local function at(t: number, a: number, out: number?): Vector3
		local rr = prof(t) * R + (out or 0)
		return Vector3.new(math.cos(a) * rr, t * h, math.sin(a) * rr)
	end
	-- a mark painted on the shell: a thin disc of diameter d lying flat on it at (t, a) (its axis along the shell's
	-- normal there, taken from the egg's middle)
	local MID = Vector3.new(0, 0.45 * h, 0)
	local function dab(t: number, a: number, d: number, color: string, neon: boolean?)
		local p = at(t, a, 0.005)
		local n = (p - MID).Unit
		add(Vector3.new(0.05, d, d), CFrame.lookAt(p, p + n) * CFrame.Angles(0, math.pi / 2, 0), color, t, { neon = neon, shape = "Cylinder", name = "Mark" })
	end
	-- a bead standing out of the shell (gems, the crown's points)
	local function bead(t: number, a: number, d: number, color: string, neon: boolean?)
		add(Vector3.new(d, d, d), CFrame.new(at(t, a, d * 0.15)), color, t, { neon = neon, shape = "Ball", name = "Bead" })
	end
	-- a flat piece lying on the shell at (t, a), `len` along its run from (t, a) to (t2, a2)
	local function strip(t: number, a: number, t2: number, a2: number, w: number, color: string, neon: boolean?, name: string?): BasePart
		local p0, p1 = at(t, a, 0.01), at(t2, a2, 0.01)
		local mid = (p0 + p1) / 2
		local outward = Vector3.new(mid.X, 0, mid.Z).Unit
		local len = math.max(0.05, (p1 - p0).Magnitude)
		return add(Vector3.new(w, w * 0.6, len + w * 0.5), CFrame.lookAt(mid, p1, outward), color, (t + t2) / 2, { neon = neon, name = name })
	end
	local FRONT = math.rad(45)
	local function front(spread: number): number
		return FRONT + (rnd() * 2 - 1) * spread
	end
	-- the shell
	-- (25 slices: close enough that the light never steps where two meet)
	for k = 0, 24 do
		local t = 0.1 + k / 24 * 0.81
		local d = prof(t) * R * 2 * 0.99
		add(Vector3.new(d, d, d), CFrame.new(0, t * h, 0), look.body, t, { shape = "Ball" })
	end
	local u = h / 2.4 -- (sizes below are for an egg 2.4 studs tall)
	-- the shine, where the light off the top left meets the view: an oval of white and a dot under it (marks are plain
	-- colour: only the egg's real lights glow, the cracks' light, the motes, the halo and the beam, since anything that
	-- glows pools light round it at night)
	local SHINE = math.rad(95)
	dab(0.72, SHINE, 0.24 * u, "white")
	dab(0.76, SHINE + 0.12, 0.14 * u, "white")
	dab(0.64, SHINE - 0.05, 0.08 * u, "white")
	if r == 1 then
		-- soft sandy patches, then freckles of two browns
		for _ = 1, 7 do
			local t = 0.18 + rnd() * 0.62
			dab(t, front(1.4), (0.34 + rnd() * 0.18) * u, "sand")
		end
		for k = 1, 40 do
			local t = 0.12 + rnd() * 0.8
			dab(t, front(1.7), (0.06 + rnd() * 0.07) * u, if k % 3 == 0 then "wood" else "sand_dark")
		end
	elseif r == 2 then
		-- a white zigzag band round its middle
		for k = 0, 27 do
			local a = k / 28 * math.pi * 2
			dab(0.44 + (if k % 2 == 0 then 0.035 else -0.035), a, 0.13 * u, "white")
		end
		-- a vine winding up it, a leaf every few turns of it
		local prev: Vector3? = nil
		for k = 0, 23 do
			local t = 0.1 + k / 23 * 0.78
			local a = FRONT - 1.4 + k / 23 * math.pi * 2.4
			dab(t, a, 0.1 * u, "leaf_dark")
			if k % 3 == 1 then
				local leaf = strip(t, a, t + 0.05, a + 0.35, 0.12 * u, "leaf", false, "Leaf")
				local _ = leaf
			end
			prev = at(t, a)
		end
		local _ = prev
		-- a sprout on top: a stem and two leaves
		add(Vector3.new(0.3 * u, 0.07 * u, 0.07 * u), CFrame.new(0, h + 0.1 * u, 0) * CFrame.Angles(0, 0, math.pi / 2), "leaf_dark", 1, { shape = "Cylinder", name = "Sprout" })
		for k, sgn in { -1, 1 } do
			local _ = k
			add(Vector3.new(0.34 * u, 0.05 * u, 0.16 * u), CFrame.new(sgn * 0.16 * u, h + 0.26 * u, 0) * CFrame.Angles(0, FRONT, sgn * math.rad(25)), "leaf", 1, { name = "Sprout" })
		end
	elseif r == 3 then
		-- glowing stars: a bright middle and four points round it
		for k = 1, 10 do
			local t = 0.18 + rnd() * 0.68
			local a = front(1.5)
			local d = (0.09 + rnd() * 0.05) * u
			dab(t, a, d, "white")
			local dt = d * 1.1 / h
			local da = d * 1.1 / math.max(0.2, prof(t) * R)
			dab(t + dt, a, d * 0.5, "white")
			dab(t - dt, a, d * 0.5, "white")
			dab(t, a + da, d * 0.5, "white")
			dab(t, a - da, d * 0.5, "white")
			local _ = k
		end
		-- a frosty band round its middle, icicles hanging off it at the front
		for k = 0, 35 do
			local a = k / 36 * math.pi * 2
			dab(0.42 + (if k % 3 == 0 then 0.015 else 0), a, 0.17 * u, "ice")
			dab(0.455, a + 0.08, 0.08 * u, "white")
		end
		for k = 0, 7 do
			local a = FRONT - 1.3 + k * 0.37
			local len = (0.08 + (k % 3) * 0.05) * u * 2.4 / h
			strip(0.41, a, 0.41 - len, a, 0.07 * u, "ice", false, "Icicle")
		end
	elseif r == 4 then
		-- two pink stripes spiralling up it, glowing runes between them, a pink ring round its foot
		for s = 0, 1 do
			for k = 0, 47 do
				local t = 0.13 + k / 47 * 0.76
				local a = FRONT - 1.6 + s * math.pi + k / 47 * math.pi * 3
				dab(t, a, 0.17 * u, "pink")
			end
		end
		for k = 1, 9 do
			local t = 0.2 + rnd() * 0.6
			dab(t, front(1.3), 0.07 * u, if k % 3 == 0 then "pink" else "white")
		end
		for k = 0, 27 do
			dab(0.12, k / 28 * math.pi * 2, 0.15 * u, "pink")
		end
		for k, c in { "pink", "white", "purple" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.18, 0.18, 0.18) * u, cf = CFrame.new(0, h * 0.6, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	else
		-- a band of gold set with gems in bezels, a thin band of amber under it and over it
		for k = 0, 39 do
			local a = k / 40 * math.pi * 2
			dab(0.43, a, 0.17 * u, "yellow")
			dab(0.385, a + 0.07, 0.08 * u, "orange")
			dab(0.475, a + 0.07, 0.08 * u, "orange")
		end
		for k = 0, 5 do
			local a = FRONT - 1.5 + k * 0.6
			dab(0.43, a, 0.27 * u, "orange")
			dab(0.43, a, 0.21 * u, "yellow")
			bead(0.43, a, 0.14 * u, ({ "berry_red", "blue", "green" })[k % 3 + 1])
		end
		-- glints of light here and there on the gold
		for _ = 1, 7 do
			local t = 0.2 + rnd() * 0.6
			if math.abs(t - 0.43) > 0.06 then
				bead(t, front(1.3), 0.09 * u, "white")
			end
		end
		-- a crown round its top: a ring and points standing up out of it, each tipped with light
		for k = 0, 23 do
			dab(0.85, k / 24 * math.pi * 2, 0.12 * u, "yellow")
		end
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			bead(0.88, a, 0.1 * u, "yellow")
			bead(0.915, a, 0.07 * u, "yellow")
			bead(0.945, a, 0.05 * u, "white")
		end
		-- the halo over it and the beam out of its top
		for k = 0, 19 do
			local halo = Blocks.part(m, { size = Vector3.new(0.09, 0.09, 0.09) * u, cf = CFrame.new(0, h + 0.4, 0), color = if k % 4 == 0 then "white" else "yellow", collide = false, query = false, neon = true, shape = "Ball", name = "Halo" })
			table.insert(fx, { p = halo, kind = "halo", k = k })
		end
		local beam = Blocks.part(m, { size = Vector3.new(0.3, 2, 0.3), cf = CFrame.new(0, h + 1, 0), color = "yellow", collide = false, query = false, neon = true, name = "Beam" })
		table.insert(fx, { p = beam, kind = "beam", k = 0 })
	end
	-- the cracks (out of sight until the scene shows them): a crack from the top down the front, its branch, then the
	-- ring round the middle
	local function crack(path: { { number } }, stage: number)
		for i = 1, #path - 1 do
			local a0, a1 = path[i], path[i + 1]
			local p0, p1 = at(a0[1], math.rad(a0[2]), 0.02), at(a1[1], math.rad(a1[2]), 0.02)
			local mid = (p0 + p1) / 2
			local off = CFrame.lookAt(mid, p1, Vector3.new(mid.X, 0, mid.Z).Unit)
			local p = Blocks.part(m, { size = Vector3.new(0.07 * u, 0.05 * u, (p1 - p0).Magnitude + 0.04), cf = off, color = "ink", collide = false, query = false, name = "Crack" })
			table.insert(cracks, { p = p, off = off, stage = stage })
		end
	end
	crack({ { 0.95, 50 }, { 0.88, 40 }, { 0.83, 56 }, { 0.77, 44 } }, 1)
	crack({ { 0.77, 44 }, { 0.71, 60 }, { 0.66, 47 }, { 0.6, 62 }, { 0.56, 50 } }, 2)
	crack({ { 0.83, 56 }, { 0.78, 74 }, { 0.74, 88 }, { 0.69, 84 } }, 2)
	local ring: { { number } } = {}
	for k = 0, 16 do
		table.insert(ring, { SPLIT + (if k % 2 == 0 then -0.02 else 0.025), -40 + k * 11 })
	end
	crack(ring, 3)
	return m, parts, top, fx, cracks
end

return EggModels
