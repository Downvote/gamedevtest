--!strict
-- The Tree of Life's eggs as models (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module: Controllers/EggView lays
-- them under the trees, UI/HatchScene holds one up close while it hatches.
--   EggModels.build(r, bare?, scale?) -> (model, parts, top, fx)   an egg of rarity r: its parts with their offsets
--                                                          from its foot, the shell's top half (it flies off when it
--                                                          hatches), the rarity's moving lights (motes, beads on an
--                                                          orbit);
--                                                          `bare`: no nest, nothing by it and no glow on the lawn;
--                                                          `scale` times its size
--   EggModels.hero(r, h) -> (model, parts, top, fx, cracks)  the hatch scene's egg up close, h studs tall
--   EggModels.heroBottom(h) -> number                      how far under its foot its shell reaches
--   EggModels.LOOK, EggModels.SIZE                         each rarity's shell and size
-- "color each egg differently with different effects to allow players to distinguish easily between egg rarities"
local Blocks = require(script.Parent.Blocks)
local WeatherData = require(script.Parent.Parent.Data.Weather)
local DynTex = require(script.Parent.Parent.Render.DynTex)

local EggModels = {}

local SIZE: { [number]: number } = { 1.25, 1.3, 1.38, 1.48, 1.62, 1.72, 1.82 } -- rarer eggs are a little bigger
EggModels.SIZE = SIZE
-- Each rarity's shell (its colour and its marks) and glow (Traits.RARITY's colours: grey, green, blue, purple, gold,
-- rose, starlight):
-- body, marks ("spots" freckles or stars, "band" a zigzag band round its middle), whether the marks glow, the glow on
-- the lawn under it.
export type Look = { body: string, mark: string, marks: string, glow: boolean, lawn: string? }
local LOOK: { [number]: Look } = {
	{ body = "cream", mark = "sand_dark", marks = "spots", glow = false },
	{ body = "green", mark = "white", marks = "band", glow = false },
	{ body = "blue", mark = "white", marks = "spots", glow = true },
	{ body = "purple", mark = "pink", marks = "spots", glow = true, lawn = "purple" },
	{ body = "gold", mark = "yellow", marks = "band", glow = true, lawn = "yellow" },
	{ body = "wall_trim", mark = "white", marks = "band", glow = true, lawn = "pink" },
	{ body = "night", mark = "screen_on", marks = "spots", glow = true, lawn = "screen_on" },
}
EggModels.LOOK = LOOK

-- What each rarity's egg has besides LOOK, under the tree: the soft highlight on its shell's lit side, its nest's two
-- tones (straw; a legendary egg's of soft cream down, a mythic one's of blossom, a celestial one's of silver wisps)
-- and what lies by the nest.
type Trim = { shine: string?, nest: { string }, by: string }
local STRAW = { "straw", "hair_blond" }
local TRIM: { [number]: Trim } = {
	{ shine = "white", nest = STRAW, by = "pebble" },
	{ shine = "screen_code", nest = STRAW, by = "leaf" },
	{ shine = "window", nest = STRAW, by = "berry" },
	{ shine = "crystal", nest = STRAW, by = "flower" },
	{ shine = "yellow", nest = { "cream", "sand" }, by = "none" },
	{ shine = "pink", nest = { "cherry", "white" }, by = "petals" },
	{ shine = nil, nest = { "steel", "white" }, by = "crystals" },
}
-- The Tree of Life's lawn under its eggs (DecorModels' EggLawn) stands this far over the grass an egg's foot is set on:
-- the nest sits on it and the glow over it.
local LAWN = 0.145

-- The camera looks from +x +z: the side of an egg at azimuth 45 degrees faces the view, and the side toward +z (a
-- bigger azimuth) is the screen's left, where the light comes from.
local FRONT = math.rad(45)

-- An egg of rarity r (LOOK) in a nest: a round shell, its marks set into it (freckles of two sizes and two browns,
-- stars, spots or a zigzag band; glowing from rare up), a soft highlight on its lit side, and from epic up its lights: a
-- ring of glow on the lawn round the nest and two motes circling it (epic); a legendary one twinkles instead (its beam
-- of light went on 2026-11-14) and has a red, a blue and a green gem set in its band. A mythic one is rose with a
-- glowing white band, pink buds round its crown and two motes; a celestial one the dark blue of a night sky, its spots
-- glowing like stars, white dust between them, a gold star on its crown and a ring of little lights orbiting it, tilted
-- like a planet's. The nest (not `bare`; the request of 2026-11-15, after the buildings were rebuilt: "can you also do
-- the same with creature and egg models?"): tufts of straw round the shell's foot in two tones, stalks sticking out of
-- it, and by it what the rarity has (a pebble, a leaf and a clover, a blue berry, a pink flower, petals, two crystals);
-- a legendary egg's nest is of cream down, a mythic one's of blossom, a celestial one's of silver wisps. Its parts'
-- offsets from its foot; the top half (it flies off when it hatches); the lights (moved every frame: stepEgg).
function EggModels.build(r: number, bare: boolean?, scale: number?, wx: string?): (Model, { { p: BasePart, off: CFrame } }, { BasePart }, { { p: BasePart, kind: string, k: number } })
	local m = Blocks.model(nil, "TreeEgg")
	-- (lit as one smooth surface across its balls, Render/Smooth: "egg and creature models look blotchy", 2026-11-14)
	m:SetAttribute("PixelSmooth", true)
	local parts: { { p: BasePart, off: CFrame } } = {}
	local top: { BasePart } = {}
	local fx: { { p: BasePart, kind: string, k: number } } = {}
	local s = (SIZE[r] or 1) * (scale or 1)
	local look = LOOK[r] or LOOK[1]
	local trim = TRIM[r] or TRIM[1]
	local function add(size: Vector3, off: CFrame, color: string, neon: boolean?, upper: boolean?, shape: string?)
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = neon, shape = shape :: any, name = if upper then "Top" else "Shell" })
		table.insert(parts, { p = p, off = off })
		if upper then
			table.insert(top, p)
		end
		return p
	end
	local function ball(dia: number, off: CFrame, color: string, neon: boolean?, upper: boolean?)
		add(Vector3.new(dia, dia, dia), off, color, neon, upper, "Ball")
	end
	-- the nest's pieces keep their own light (they lean nothing on the shell's smooth surface)
	local function straw(size: Vector3, off: CFrame, color: string, shape: string?)
		local p = add(size, off, color, nil, nil, shape)
		p:SetAttribute("PixelOwn", true)
		return p
	end
	-- the glow on the lawn (epic and up): a thin disc of light just over the tree's lawn, a ring of it showing round the
	-- nest (its face far enough over the lawn to be drawn over it: Render/Raster's depth bias)
	if look.lawn and not bare then
		add(Vector3.new(0.25, 1.4 * s, 1.4 * s), CFrame.new(0, LAWN + 0.06 - 0.125, 0) * CFrame.Angles(0, 0, math.pi / 2), look.lawn, true, nil, "Cylinder")
	end
	-- the nest (not in the hatch scene's: `bare`): a ring of round tufts of straw hugging the shell's foot, lit as one
	-- soft roll with it, and stalks sticking out of it; no wider than the old bed of straw, so the eggs round the tree
	-- keep their room. (Only from the left round the front to the right: the shell hides the back.)
	local tuft = math.max(0.5, Blocks.snap(0.4 * s))
	local rn = 0.6 * s - tuft / 2 -- the ring's middle, from the egg's axis
	local ty = LAWN + tuft * 0.1 -- the tufts' middle
	if not bare then
		for k = -2, 2 do
			local a = FRONT + k * math.pi / 4
			add(Vector3.new(tuft, tuft, tuft), CFrame.new(math.cos(a) * rn, ty + (if k % 2 == 0 then 0 else 0.03), math.sin(a) * rn), trim.nest[k % 2 + 1], nil, nil, "Ball")
		end
		-- stray stalks standing up out of it, leaning out: one at the front left, one at the right
		for _, st in { { 32, 0.45 }, { -70, 0.55 } } do
			local a = FRONT + math.rad(st[1])
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			straw(Vector3.new(0.25, 0.5, 0.25), CFrame.fromMatrix(radial * (rn + 0.08) + Vector3.new(0, ty + tuft * 0.45, 0), radial:Cross(Vector3.yAxis), Vector3.yAxis) * CFrame.Angles(st[2], 0, 0), trim.nest[1])
		end
	end
	-- the shell: a broad round bottom and a smaller round top, overlapping (an egg's curve); the top the half that flies
	-- off when it hatches
	local y0 = 0.06
	local balls: { { y: number, r: number } } = {}
	local function shell(dia: number, y: number, upper: boolean?)
		local p = add(Vector3.new(dia, dia, dia), CFrame.new(0, y, 0), look.body, nil, upper, "Ball")
		table.insert(balls, { y = y, r = p.Size.X / 2 })
	end
	-- (a fuller base and a narrower top, never a plain oval: "The eggs also look too much like perfect ovals, they
	-- should be more like eggs, with a bigger base", 2026-11-14)
	shell(0.9 * s, y0 + 0.45 * s)
	shell(0.74 * s, y0 + 0.62 * s)
	shell(0.5 * s, y0 + 0.78 * s, true)
	local crownY = 0
	for _, b in balls do
		crownY = math.max(crownY, b.y + b.r)
	end
	-- the shell's outside at height share h (of the egg's height) and `deg` degrees from the side facing the view: the
	-- point and the shell's normal there
	local function onShell(h: number, deg: number): (Vector3, Vector3)
		local y = h * crownY
		local best, by = 0, y0
		for _, b in balls do
			local dy = y - b.y
			if dy * dy < b.r * b.r then
				local rr = math.sqrt(b.r * b.r - dy * dy)
				if rr > best then
					best, by = rr, b.y
				end
			end
		end
		local a = FRONT + math.rad(deg)
		local pt = Vector3.new(math.cos(a) * best, y, math.sin(a) * best)
		local n = pt - Vector3.new(0, by, 0)
		return pt, if n.Magnitude > 1e-6 then n.Unit else Vector3.yAxis
	end
	-- a mark set into the shell: a ball of diameter d sunk into it so only a round cap `poke` studs high shows (past
	-- the pixel filter's depth bias, Render/Raster's 0.03, or it would hide in the shell), lit as the shell under it
	-- (PixelFollow) so it shades like paint, or keeping its own light (`own`: a gem; a glowing one always does); above
	-- 0.86 of the height it goes with the top
	local function mark(h: number, deg: number, d: number, color: string, poke: number, neon: boolean?, own: boolean?)
		local pt, n = onShell(h, deg)
		local dd = math.max(0.25, Blocks.snap(d))
		local p = add(Vector3.new(dd, dd, dd), CFrame.new(pt + n * (poke - dd / 2)), color, neon, h > 0.86, "Ball")
		p:SetAttribute(if own or neon then "PixelOwn" else "PixelFollow", true)
		return p
	end
	-- the soft highlight high on the lit side, a lighter tone of the shell
	local shine = trim.shine
	if shine then
		mark(0.72, 48, 0.25, shine, 0.06)
	end
	if look.marks == "spots" then
		-- freckles or stars of two sizes on the side facing the view
		-- (a common egg's in two browns: big soft sandy ones and small caramel ones; the glowing ones all small, the
		-- bigger ones standing out further)
		local sp = { { 0.6, 22, 0.5 }, { 0.3, -28, 0.5 }, { 0.8, -14, 0.25 }, { 0.44, 12, 0.25 }, { 0.52, -55, 0.25 }, { 0.24, 38, 0.25 } }
		for k, d in sp do
			if (r == 1 or r == 3) and k == 6 then
				break
			end
			local big = d[3] > 0.3
			if look.glow then
				mark(d[1], d[2], 0.25, look.mark, if big then 0.1 else 0.07, true)
			else
				mark(d[1], d[2], d[3], if big then "sand_dark" else "wood", if big then 0.07 else 0.08)
			end
		end
	else
		-- a zigzag band round its middle on the side facing the view: dabs up and down in turn (a legendary egg's one
		-- fewer, its gems between them)
		local n = if r == 5 then 7 else 8
		for k = 0, n - 1 do
			local deg = -62 + k * 140 / (n - 1)
			mark(if k % 2 == 0 then 0.39 else 0.5, deg, 0.25, look.mark, 0.08, look.glow)
		end
	end
	-- an egg the weather touched (GAME_DESIGN 13: it hatches with that weather's mutation): a little piece of that
	-- weather over its crown, its own shape so it reads on any shell: a rain cloud with three drops under it, a dark
	-- storm cloud with a bolt, a cap of snow, a pink flower, a fallen leaf, a small hot sun, puffs of mist round it.
	-- What sits on or over the crown is part of the top half (it goes with the top when the egg hatches).
	local wdef = if wx then WeatherData.byId[wx] else nil
	if wdef and wdef.family then
		local crown = y0 + 1.03 * s -- the top of the shell
		local function cloud(y: number, color: string)
			ball(0.34 * s, CFrame.new(0, y, 0), color, nil, true)
			ball(0.26 * s, CFrame.new(-0.2 * s, y - 0.04 * s, 0.12 * s), color, nil, true)
			ball(0.26 * s, CFrame.new(0.2 * s, y - 0.04 * s, -0.12 * s), color, nil, true)
		end
		if wdef.id == "rain" then
			local y = crown + 0.36 * s
			cloud(y, "white")
			for k, d in { { -0.16, 0.1 }, { 0.02, -0.02 }, { 0.18, -0.12 } } do
				ball(0.11 * s, CFrame.new(d[1] * s, y - (0.24 + 0.06 * (k % 2)) * s, d[2] * s), "blue", nil, true)
			end
		elseif wdef.id == "storm" then
			local y = crown + 0.38 * s
			cloud(y, "slate")
			-- the bolt: two short bars in a zigzag, lit
			add(Vector3.new(0.07 * s, 0.2 * s, 0.07 * s), CFrame.new(0.02 * s, y - 0.24 * s, 0) * CFrame.Angles(0, 0, 0.5), "yellow", true, true)
			add(Vector3.new(0.07 * s, 0.18 * s, 0.07 * s), CFrame.new(-0.03 * s, y - 0.4 * s, 0) * CFrame.Angles(0, 0, -0.5), "yellow", true, true)
		elseif wdef.id == "snow" then
			-- a cap of snow over its top, a lump on it
			-- (a ball sunk into the shell's top: only its dome shows, white over the shell)
			ball(0.64 * s, CFrame.new(0, crown - 0.21 * s, 0), "snow", nil, true)
			ball(0.2 * s, CFrame.new(0.06 * s, crown + 0.06 * s, -0.04 * s), "white", nil, true)
		elseif wdef.id == "blossom" then
			-- a flower on its crown: five petals round a yellow middle
			for k = 0, 4 do
				local a = k * math.pi * 2 / 5
				ball(0.17 * s, CFrame.new(math.cos(a) * 0.13 * s, crown + 0.04 * s, math.sin(a) * 0.13 * s), "pink", nil, true)
			end
			ball(0.12 * s, CFrame.new(0, crown + 0.07 * s, 0), "yellow", nil, true)
		elseif wdef.id == "leaves" then
			-- a fallen leaf lying on its crown, its stalk up
			add(Vector3.new(0.42 * s, 0.05 * s, 0.24 * s), CFrame.new(0, crown, 0) * CFrame.Angles(0.2, 0.7, 0.15), "maple", nil, true)
			add(Vector3.new(0.2 * s, 0.05 * s, 0.12 * s), CFrame.new(0.12 * s, crown + 0.01 * s, -0.08 * s) * CFrame.Angles(0.2, 0.7, 0.15), "orange", nil, true)
			add(Vector3.new(0.04 * s, 0.14 * s, 0.04 * s), CFrame.new(-0.14 * s, crown + 0.08 * s, 0.1 * s), "wood_dark", nil, true)
		elseif wdef.id == "haze" then
			-- a small hot sun over it
			ball(0.3 * s, CFrame.new(0, crown + 0.34 * s, 0), "orange", true, true)
			ball(0.18 * s, CFrame.new(-0.04 * s, crown + 0.38 * s, 0.04 * s), "yellow", true, true)
		else
			-- fog (and any other): puffs of mist round its middle
			for k = 0, 4 do
				local a = k * math.pi * 2 / 5 + 0.4
				ball(0.26 * s, CFrame.new(math.cos(a) * 0.5 * s, y0 + (0.3 + 0.08 * (k % 2)) * s, math.sin(a) * 0.5 * s), "white")
			end
		end
	end
	-- what lies by the nest, on its front edge
	if not bare then
		local function at(deg: number, out: number, y: number): CFrame
			local a = FRONT + math.rad(deg)
			return CFrame.new(math.cos(a) * (rn + out), LAWN + y, math.sin(a) * (rn + out))
		end
		local by = trim.by
		if by == "pebble" then
			-- a grey pebble
			straw(Vector3.new(0.25, 0.25, 0.25), at(-20, tuft / 2 + 0.05, 0.02), "rock", "Ball")
		elseif by == "leaf" then
			-- a green leaf tucked under the rim, and a clover
			straw(Vector3.new(0.5, 0.25, 0.25), at(-24, tuft / 2, 0.02) * CFrame.Angles(0, math.rad(24) - FRONT, 0.15), "leaf")
			straw(Vector3.new(0.25, 0.25, 0.25), at(28, tuft / 2 + 0.05, 0.02), "leaf_dark", "Ball")
		elseif by == "berry" then
			-- a blue berry at the nest's edge
			straw(Vector3.new(0.25, 0.25, 0.25), at(-20, tuft / 2 + 0.03, 0.04), "blue", "Ball")
		elseif by == "flower" then
			-- a little pink flower at the nest's edge
			straw(Vector3.new(0.25, 0.25, 0.25), at(-20, tuft / 2, 0.08), "pink", "Ball")
		elseif by == "petals" then
			-- pink petals fallen at the nest's front
			straw(Vector3.new(0.25, 0.25, 0.25), at(-24, tuft / 2 + 0.03, 0.02), "cherry", "Ball")
			straw(Vector3.new(0.25, 0.25, 0.25), at(16, tuft / 2 + 0.03, 0.02), "pink", "Ball")
		elseif by == "crystals" then
			-- two little crystals by the nest, a lilac one and a cyan one
			straw(Vector3.new(0.25, 0.5, 0.25), at(-26, tuft / 2, 0.15) * CFrame.Angles(0, 0.7, 0.3), "crystal")
			straw(Vector3.new(0.25, 0.25, 0.25), at(-8, tuft / 2 + 0.04, 0.06) * CFrame.Angles(0.6, 0.7, 0), "screen_on")
		end
	end
	if r == 7 then
		-- a celestial egg: white dust between its glowing spots, a gold star on its crown, and a ring of little lights
		-- orbiting it
		for _, d in { { 0.36, -5 }, { 0.68, 10 }, { 0.5, 45 }, { 0.22, -48 }, { 0.62, -40 } } do
			mark(d[1], d[2], 0.25, "white", 0.06, true)
		end
		mark(0.99, 0, 0.25, "yellow", 0.12, true)
		for k = 1, 9 do
			local c = ({ "white", "screen_on", "yellow" })[k % 3 + 1]
			local bead = Blocks.part(m, { size = Vector3.new(0.16, 0.16, 0.16), cf = CFrame.new(0, y0 + 0.6 * s, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Orbit" })
			table.insert(fx, { p = bead, kind = "orbit", k = k })
		end
	elseif r == 6 then
		-- a mythic egg: pink buds round its crown, two motes circling it (a pink one and a white one)
		for k = 0, 4 do
			local a = k * math.pi * 2 / 5 + 0.3
			ball(0.15 * s, CFrame.new(math.cos(a) * 0.24 * s, y0 + 0.92 * s, math.sin(a) * 0.24 * s), "cherry", nil, true)
		end
		for k, c in { "cherry", "white" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.25, 0.25, 0.25), cf = CFrame.new(0, y0 + 0.6 * s, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	elseif r >= 5 then
		-- a legendary egg: three gems set in its band, a red, a blue and a green (they keep their own light); its gold
		-- sparks and stars twinkle round it (EggView). The band of light and the beam of light that stood out of its top
		-- went (the request of 2026-11-14: "remove these rectangular effects everywhere, instead make it twinkles")
		for k, c in { "berry_red", "blue", "green" } do
			mark(if k == 2 then 0.5 else 0.39, -40 + (k - 1) * 47, 0.25, c, 0.12, nil, true)
		end
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
-- egg's profile (broad low, narrow high) on a fine grid, so its outline is smooth; a shine high on the lit side (the
-- top left: a soft oval of the shell's lighter tone with a white glint in it); and the rarity's own work on it, painted
-- as marks set into the shell, on the side the view sees (rebuilt finer on 2026-11-15: "can you also do the same with
-- creature and egg models?"):
--   common: cream with freckles of three browns, big and small, thicker toward the top;
--   uncommon: green with a white zigzag band edged in dark green, a vine winding up it with leaves, a sprout on top;
--   rare: sky blue with glowing white four-pointed stars, a frosty band with white sparkles and icicles;
--   epic: purple with two pink stripes spiralling up it, runes between them, a pink ring at its foot, three motes
--     circling it;
--   legendary: gold with a band edged in brown and set with red, blue and green gems in gold bezels, gold curls over
--     and under it, glints of light, a crown of points round its top and a halo of light turning over it (its beam
--     went on 2026-11-14);
--   mythic: rose with white polka dots, two strings of pearls round its middle and a pink band between them, a ring of
--     pearls round its top, a halo of pink and white lights over it and three motes circling it;
--   celestial: the dark blue of a night sky, constellations (glowing white stars joined by lilac dots), a few cyan
--     stars, a gold star on its crown, a tilted ring of little lights orbiting it like a planet's and three motes.
-- Its cracks (`cracks`: each part with its stage, 1 a short crack at the top, 2 running down and branching, 3 round its
-- middle where the top comes off; each a thin glowing line, Neon) are kept out of sight until the scene shows them;
-- the top is what lies above the middle crack. fx: "mote", "halo", "orbit" (moved by the scene).
export type Crack = { p: BasePart, off: CFrame, stage: number }
-- (an egg's curve: the widest a little below the middle over a full, round base, the top narrowing to a softer point;
-- "The eggs also look too much like perfect ovals, they should be more like eggs, with a bigger base", 2026-11-14)
local PROFILE: { { number } } = {
	{ 0, 0 },
	{ 0.03, 0.44 },
	{ 0.08, 0.68 },
	{ 0.15, 0.86 },
	{ 0.24, 0.96 },
	{ 0.34, 1 },
	{ 0.42, 1 },
	{ 0.52, 0.95 },
	{ 0.62, 0.87 },
	{ 0.72, 0.75 },
	{ 0.81, 0.61 },
	{ 0.88, 0.47 },
	{ 0.94, 0.32 },
	{ 0.98, 0.17 },
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
local FINE = 0.05
local function fine(v: number): number
	return math.max(FINE, math.floor(v / FINE + 0.5) * FINE)
end

-- How far under its foot the hero egg's shell reaches (studs, below 0): its slices are balls, the lowest bulging past
-- the foot. The hatch scene sets the egg down on its pedestal by it.
function EggModels.heroBottom(h: number): number
	local R = 0.37 * h
	local low = 0
	for k = 0, 24 do
		local t = 0.1 + k / 24 * 0.81
		low = math.min(low, t * h - prof(t) * R * 0.99)
	end
	return low
end

function EggModels.hero(r: number, h: number): (Model, { { p: BasePart, off: CFrame } }, { BasePart }, { { p: BasePart, kind: string, k: number } }, { Crack })
	local m = Blocks.model(nil, "HeroEgg")
	-- (lit as one smooth surface across its 25 slices, its marks shading with it: Render/Smooth; the request of
	-- 2026-11-14, "egg and creature models look blotchy due to how they are detailed using balls and other small shapes")
	m:SetAttribute("PixelSmooth", true)
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
	-- (up close its parts are on the creatures' fine grid, FINE studs (Models/DriftKit, after the bakery's FoodKit): on
	-- Blocks' quarter-stud grid its slices stepped an eighth of a stud from one to the next, so its outline jogged and
	-- the marks set into it hid in the steps)
	local function add(size: Vector3, off: CFrame, color: string, t: number, opts: AddOpts?): BasePart
		local o: AddOpts = opts or NONE
		local p = Blocks.part(m, { size = size, cf = off, color = color, collide = false, query = false, neon = o.neon, shape = o.shape :: any, name = o.name or (if t > SPLIT then "Top" else "Shell") })
		p.Size = Vector3.new(fine(size.X), fine(size.Y), fine(size.Z))
		table.insert(parts, { p = p, off = off })
		if t > SPLIT then
			table.insert(top, p)
		end
		return p
	end
	-- the shell
	-- (25 slices: close enough that the light never steps where two meet)
	-- (each slice wears the rarity's pattern, drawn by the pixel filter on the shell (Render/DynTex.EGG: freckles,
	-- dapples, frost, swirls, a filigree, little flowers, stardust); the slices share one pattern: PixelTexV lifts each
	-- one's v to its height on the egg, one seed for all. The request of 2026-11-14: "Could you detail the eggs in the
	-- egg hatching screen more? You are allowed to draw in the detail on the eggs instead of adding more meshes")
	local pattern = DynTex.EGG[r] or DynTex.EGG[1]
	local slices: { { y: number, r: number } } = {}
	for k = 0, 24 do
		local t = 0.1 + k / 24 * 0.81
		local d = prof(t) * R * 2 * 0.99
		local p = add(Vector3.new(d, d, d), CFrame.new(0, t * h, 0), look.body, t, { shape = "Ball" })
		table.insert(slices, { y = t * h, r = p.Size.X / 2 })
		p:SetAttribute("PixelTex", pattern)
		p:SetAttribute("PixelTexV", t * h)
		p:SetAttribute("PixelTexSeed", 11 + r)
		p:SetAttribute("PixelTexSoft", 0.8)
	end
	local u = h / 2.4 -- (sizes below are for an egg 2.4 studs tall)
	-- the shell's true radius at height share t: its slices are balls (their sizes on the grid), so where the egg
	-- narrows a lower ball bulges past the profile; and the point `out` studs off it at azimuth a, with the shell's
	-- normal there
	local function shellR(t: number): number
		local y, best = t * h, 0
		for _, sl in slices do
			local dy = y - sl.y
			if dy * dy < sl.r * sl.r then
				best = math.max(best, math.sqrt(sl.r * sl.r - dy * dy))
			end
		end
		return best
	end
	local function surf(t: number, a: number, out: number): (Vector3, Vector3)
		local rr = shellR(t)
		local slope = (shellR(t + 0.01) - shellR(t - 0.01)) / (0.02 * h)
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local n = (radial - Vector3.yAxis * slope).Unit
		return radial * rr + Vector3.new(0, t * h, 0) + n * out, n
	end
	-- A mark painted on the shell: a ball sunk into it at (t, a) so only a round cap about c studs across shows,
	-- standing a hair proud of it (just past the pixel filter's depth bias, Render/Raster's 0.03; `over` lifts it over
	-- another mark) and lit as the shell under it (PixelFollow), so it shades like paint and never stands out of the
	-- outline the way the old flat discs did (they were a grid step thick and showed their edges). A star's light
	-- (`lit`) glows instead and pools none round it (PixelNoPool, as the cracks).
	local BIAS, RISE = 0.03, 0.02
	local function spot(t: number, a: number, c: number, color: string, over: number?, lit: boolean?): BasePart
		-- (the cap shows where the ball stands more than the bias out of the shell: a ball sized so a cap c across rises
		-- RISE past it, no bigger than a few tenths of a stud so it never reaches through the egg)
		local rb = math.clamp((c * c / 4 + RISE * RISE) / (2 * RISE), FINE, 0.3)
		local dd = fine(2 * rb)
		rb = dd / 2
		local rise = if c / 2 < rb then math.max(0.012, rb - math.sqrt(rb * rb - c * c / 4)) else rb
		local pt = surf(t, a, BIAS + rise + (over or 0) - rb)
		local p = add(Vector3.new(dd, dd, dd), CFrame.new(pt), color, t, { shape = "Ball", name = "Mark", neon = lit })
		if lit then
			p:SetAttribute("PixelNoPool", true)
		else
			p:SetAttribute("PixelFollow", true)
		end
		return p
	end
	-- a bead standing out of the shell (gems, pearls), keeping its own light, `out` of its middle off the shell
	local function bead(t: number, a: number, d: number, color: string, out: number?)
		local dd = fine(d)
		local pt = surf(t, a, out or 0)
		local p = add(Vector3.new(dd, dd, dd), CFrame.new(pt), color, t, { shape = "Ball", name = "Bead" })
		p:SetAttribute("PixelOwn", true)
	end
	-- a line of marks from (t0, a0) to (t1, a1), about `gap` studs apart (not the first when `skip`, so a path of lines
	-- doesn't double its corners)
	local function line(t0: number, a0: number, t1: number, a1: number, c: number, gap: number, color: string, skip: boolean?)
		local p0, p1 = surf(t0, a0, 0), surf(t1, a1, 0)
		local n = math.max(1, math.floor((p1 - p0).Magnitude / gap + 0.5))
		for i = if skip then 1 else 0, n do
			local k = i / n
			spot(t0 + (t1 - t0) * k, a0 + (a1 - a0) * k, c, color)
		end
	end
	-- a star of light lying on the shell at (t, a): two thin bars crossing, `len` studs long, upright and across, over a
	-- round middle; it glows and pools no light (as the cracks). (Bars, not dots: a cross of little round marks only
	-- came out as a blot of pixels.)
	local function star(t: number, a: number, len: number, color: string)
		local pt, n = surf(t, a, 0)
		local up = (Vector3.yAxis - n * n.Y).Unit
		local side = n:Cross(up)
		local w = FINE
		for _, dir in { up, side } do
			local cf = CFrame.lookAt(pt + n * (BIAS + w), pt + n * (BIAS + w) + dir, n)
			local p = add(Vector3.new(w, w, len), cf, color, t, { neon = true, name = "Star" })
			p:SetAttribute("PixelNoPool", true)
		end
		spot(t, a, len * 0.42, color, nil, true)
	end
	-- the side the view sees: within about 105 degrees of the front (nothing is painted round the back)
	local WINDOW = math.rad(105)
	local function front(spread: number): number
		return FRONT + (rnd() * 2 - 1) * spread
	end
	-- whether (t, a) lies on the way of the cracks (below): a star there would be lost in a crack's light
	local function nearCrack(t: number, a: number): boolean
		local deg = (math.deg(a) + 180) % 360 - 180
		if math.abs(t - SPLIT) < 0.06 and deg > -28 and deg < 118 then
			return true
		elseif t > SPLIT and math.abs(deg - 50) < 13 then
			return true
		end
		return t > 0.7 and t < 0.9 and math.abs(deg - (51 + (0.85 - t) * 230)) < 11
	end
	-- a band of marks round the side the view sees at height share t: about `gap` studs apart, each c across, `wave`
	-- up and down in turn (a zigzag), `shift` turning it a little, `over` lifting it over marks already there
	local function band(t: number, c: number, gap: number, color: string, wave: number?, shift: number?, over: number?)
		local rr = math.max(0.2, shellR(t))
		local n = math.max(2, math.floor(2 * WINDOW * rr / gap + 0.5))
		for k = 0, n do
			local a = FRONT - WINDOW + 2 * WINDOW * k / n + (shift or 0)
			spot(t + (if wave and k % 2 == 1 then wave else 0), a, c, color, over)
		end
	end
	-- the shine, where the light off the top left meets the view: a soft oval of the shell's lighter tone with a white
	-- glint in it (marks are plain colour: only the egg's real lights glow, its stars, the cracks' light, the motes and
	-- the halo, and only the motes and the halo pool light round them)
	local SHINE = math.rad(95)
	local glint = ({ "white", "screen_code", "window", "crystal", "yellow", "pink", "slate" })[r] or "white"
	spot(0.72, SHINE, 0.3 * u, glint)
	spot(0.77, SHINE + 0.1, 0.16 * u, "white", 0.03)
	spot(0.66, SHINE - 0.06, 0.07 * u, "white", 0.03)
	if r == 1 then
		-- freckles of three browns, big and small, thicker toward the top (the soft sandy patches went on 2026-11-14:
		-- big flat dabs stood out of the shell's edge; the drawn freckles do that work now)
		for k = 1, 46 do
			local t = 0.13 + (1 - rnd() ^ 1.4) * 0.78
			local c = (0.05 + rnd() * 0.1) * u
			local col = if k % 7 == 0 then "wood_dark" elseif k % 3 == 0 then "wood" else "sand_dark"
			spot(t, front(1.75), if col == "wood_dark" then c * 0.6 else c, col)
		end
	elseif r == 2 then
		-- a white zigzag band round its middle, a darker green edge under it
		local zt, za = 0.43, 0.06
		local n = 14
		for k = 0, n - 1 do
			local a0 = FRONT - WINDOW + 2 * WINDOW * k / n
			local a1 = FRONT - WINDOW + 2 * WINDOW * (k + 1) / n
			local t0 = zt + (if k % 2 == 0 then za else -za)
			local t1 = zt + (if k % 2 == 0 then -za else za)
			line(t0, a0, t1, a1, 0.2 * u, 0.09 * u, "white", k > 0)
			line(t0 - 0.06, a0, t1 - 0.06, a1, 0.1 * u, 0.09 * u, "leaf_dark", k > 0)
		end
		-- a vine winding up across it, a leaf every few steps of it
		local prevT, prevA = 0.14, FRONT + 1.3
		for k = 1, 10 do
			local t = 0.14 + k / 10 * 0.72
			local a = FRONT + 1.3 - k / 10 * 2.4 + math.sin(k * 1.3) * 0.12
			line(prevT, prevA, t, a, 0.1 * u, 0.08 * u, "chalk", true)
			if k % 2 == 1 and k < 10 then
				local side = if k % 4 == 1 then 1 else -1
				spot(t + 0.035 * side, a + 0.1, 0.2 * u, "leaf_dark", 0.02)
				spot(t + 0.065 * side, a + 0.19, 0.13 * u, "leaf_dark", 0.02)
			end
			prevT, prevA = t, a
		end
		-- a sprout on top: a little stem and two leaves of two little balls each, across the view (they keep their own
		-- light)
		local across = Vector3.new(math.cos(FRONT + math.pi / 2), 0, math.sin(FRONT + math.pi / 2))
		for _, d in { { x = 0, y = 0.08, d = 0.25, c = "leaf_dark" }, { x = 0.02, y = 0.2, d = 0.25, c = "leaf_dark" }, { x = -0.12, y = 0.27, d = 0.25, c = "leaf" }, { x = -0.24, y = 0.33, d = 0.25, c = "leaf" }, { x = 0.15, y = 0.3, d = 0.25, c = "leaf" }, { x = 0.27, y = 0.37, d = 0.25, c = "leaf" } } do
			local p = add(Vector3.new(d.d, d.d, d.d), CFrame.new(across * d.x * u + Vector3.new(0, h + d.y * u, 0)), d.c, 1, { shape = "Ball", name = "Sprout" })
			p:SetAttribute("PixelOwn", true)
		end
	elseif r == 3 then
		-- white four-pointed stars over its front
		local placed = 0
		for _ = 1, 60 do
			local t = 0.2 + rnd() * 0.66
			local a = front(1.05)
			local len = (0.22 + rnd() * 0.12) * u
			if math.abs(t - 0.42) > 0.08 and not nearCrack(t, a) and placed < 10 then
				star(t, a, len, "white")
				placed += 1
			end
		end
		-- a frosty band round its middle, white sparkles along its top, icicles hanging off it
		band(0.42, 0.22 * u, 0.12 * u, "ice")
		band(0.455, 0.07 * u, 0.2 * u, "white", nil, 0.05, 0.03)
		for k = 0, 8 do
			local a = FRONT - 1.45 + k * 0.36
			local len = 1 + (k % 3)
			for j = 1, len do
				spot(0.4 - j * 0.035, a, (0.15 - j * 0.035) * u, "ice")
			end
		end
	elseif r == 4 then
		-- two pink stripes spiralling up it, runes between them, a pink ring round its foot, three motes circling it
		for sIdx = 0, 1 do
			local prevT: number?, prevA: number? = nil, nil
			for k = 0, 60 do
				local t = 0.13 + k / 60 * 0.76
				local a = FRONT - 1.6 + sIdx * math.pi + k / 60 * math.pi * 3
				local off = (a - FRONT + math.pi) % (2 * math.pi) - math.pi
				if math.abs(off) < WINDOW then
					if prevT and prevA then
						line(prevT, prevA, t, a, 0.18 * u, 0.1 * u, "pink", true)
					else
						spot(t, a, 0.18 * u, "pink")
					end
					prevT, prevA = t, a
				else
					prevT, prevA = nil, nil
				end
			end
		end
		-- runes: little diamonds of four dots, a dot in the middle
		for k = 1, 8 do
			local t = 0.22 + rnd() * 0.56
			local a = front(1.3)
			local c = 0.07 * u
			local col = if k % 3 == 0 then "pink" else "white"
			local dt, da = 0.05, 0.1
			spot(t + dt, a, c, col, 0.03)
			spot(t - dt, a, c, col, 0.03)
			spot(t, a + da, c, col, 0.03)
			spot(t, a - da, c, col, 0.03)
			spot(t, a, c * 0.8, col, 0.03)
		end
		band(0.12, 0.15 * u, 0.1 * u, "pink")
		for k, c in { "pink", "white", "purple" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.18, 0.18, 0.18) * u, cf = CFrame.new(0, h * 0.6, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	elseif r == 6 then
		-- a pink band round its middle between two strings of pearls
		-- (the pearls keep off the outline: only the front's, sunk to half; and they go first, so the band never covers
		-- them)
		local rr = shellR(0.44)
		local PEARLS = math.rad(78)
		local n = math.floor(2 * PEARLS * rr / (0.14 * u) + 0.5)
		for k = 0, n do
			local a = FRONT - PEARLS + 2 * PEARLS * k / n
			bead(0.395, a, 0.17 * u, "white", -0.02)
			bead(0.485, a + 0.04, 0.17 * u, "white", -0.02)
		end
		band(0.44, 0.17 * u, 0.1 * u, "cherry")
		-- white polka dots in even rows over and under the band
		for row, t in { 0.18, 0.28, 0.6, 0.7, 0.8 } do
			local rt = math.max(0.2, shellR(t))
			local cnt = math.max(3, math.floor(2 * WINDOW * rt / (0.32 * u) + 0.5))
			for k = 0, cnt do
				spot(t, FRONT - WINDOW + 2 * WINDOW * (k + (row % 2) * 0.5) / (cnt + 0.5), 0.12 * u, "white")
			end
		end
		-- a ring of pearls round its top, pink buds between them
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			if k % 2 == 0 then
				bead(0.87, a, 0.17 * u, "white", -0.02)
			else
				spot(0.87, a, 0.11 * u, "cherry")
			end
		end
		-- the halo over it, pink and white, and three motes circling it
		for k = 0, 19 do
			local halo = Blocks.part(m, { size = Vector3.new(0.09, 0.09, 0.09) * u, cf = CFrame.new(0, h + 0.4, 0), color = if k % 2 == 0 then "white" else "pink", collide = false, query = false, neon = true, shape = "Ball", name = "Halo" })
			table.insert(fx, { p = halo, kind = "halo", k = k })
		end
		for k, c in { "pink", "white", "cherry" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.18, 0.18, 0.18) * u, cf = CFrame.new(0, h * 0.6, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	elseif r >= 7 then
		-- constellations: white four-pointed stars joined by lines of lilac dots, and a few cyan stars on their own (the
		-- dust of tiny ones between is drawn on the shell, DynTex's stardust)
		-- (off the way of the cracks)
		local groups: { { { number } } } = {
			{ { 0.82, -0.95 }, { 0.7, -0.62 }, { 0.76, -0.3 }, { 0.64, -0.24 } },
			{ { 0.3, 0.05 }, { 0.2, 0.5 }, { 0.33, 0.85 } },
			{ { 0.86, 0.78 }, { 0.7, 0.98 } },
		}
		for _, g in groups do
			for i, st in g do
				local t, a = st[1], FRONT + st[2]
				star(t, a, 0.3 * u, "white")
				local nx = g[i + 1]
				if nx then
					local t2, a2 = nx[1], FRONT + nx[2]
					-- (the dots stop short of the stars at both ends)
					local k0, k1 = 0.22, 0.78
					line(t + (t2 - t) * k0, a + (a2 - a) * k0, t + (t2 - t) * k1, a + (a2 - a) * k1, 0.05 * u, 0.12 * u, "crystal")
				end
			end
		end
		for _, st in { { 0.45, -0.7 }, { 0.44, 0.6 }, { 0.15, -0.35 }, { 0.9, -0.55 } } do
			star(st[1], FRONT + st[2], 0.24 * u, "screen_on")
		end
		-- a gold star on its crown
		star(0.975, FRONT - 0.35, 0.32 * u, "yellow")
		-- the ring of little lights orbiting it, and three motes
		for k = 0, 27 do
			local c = ({ "white", "screen_on", "crystal", "white" })[k % 4 + 1]
			local orb = Blocks.part(m, { size = Vector3.new(0.08, 0.08, 0.08) * u, cf = CFrame.new(0, h * 0.5, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Orbit" })
			table.insert(fx, { p = orb, kind = "orbit", k = k })
		end
		for k, c in { "white", "screen_on", "yellow" } do
			local mote = Blocks.part(m, { size = Vector3.new(0.16, 0.16, 0.16) * u, cf = CFrame.new(0, h * 0.6, 0), color = c, collide = false, query = false, neon = true, shape = "Ball", name = "Mote" })
			table.insert(fx, { p = mote, kind = "mote", k = k })
		end
	else
		-- a band of gold round its middle, lit along its top edge and dark along its foot, set with gems in gold bezels
		-- (the gems and their bezels first: a mark drawn after another shows only where it stands clear of it)
		local rr = math.max(0.2, shellR(0.43))
		for k = 0, 4 do
			local a = FRONT + (k - 2) * 0.42
			local big = k % 2 == 0
			bead(0.43, a, if big then 0.34 * u else 0.24 * u, ({ "berry_red", "blue", "green", "blue", "berry_red" })[k + 1], if big then -0.05 else -0.01)
			local ring = if big then 0.2 * u else 0.15 * u
			for j = 0, 7 do
				local b = j / 8 * math.pi * 2
				spot(0.43 + math.sin(b) * ring / h, a + math.cos(b) * ring / rr, 0.08 * u, "orange", 0.02)
			end
		end
		band(0.43, 0.28 * u, 0.11 * u, "yellow")
		band(0.373, 0.1 * u, 0.09 * u, "wood", nil, 0.03)
		band(0.487, 0.1 * u, 0.09 * u, "cream", nil, 0.03)
		-- filigree: little curls of gold over and under the band
		for k = 0, 5 do
			local a0 = FRONT - 1.3 + k * 0.52
			local up = if k % 2 == 0 then 1 else -1
			local t0 = 0.43 + up * 0.12
			for j = 0, 6 do
				local w = j / 6 * math.pi * 1.6
				local rad = 0.04 * (1 - j / 9)
				spot(t0 + up * math.sin(w) * rad, a0 + math.cos(w) * rad * 2.2, 0.08 * u, "orange")
			end
		end
		-- glints of light here and there on the gold
		for _ = 1, 7 do
			local t = 0.2 + rnd() * 0.6
			local a = front(1.2)
			if math.abs(t - 0.43) > 0.12 and not nearCrack(t, a) then
				star(t, a, 0.22 * u, "white")
			end
		end
		-- a crown round its top: a ring and points rising out of it, each tipped with light
		for k = 0, 23 do
			spot(0.84, k / 24 * math.pi * 2, 0.12 * u, "orange")
		end
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2 + math.pi / 8
			spot(0.875, a, 0.11 * u, "yellow")
			spot(0.905, a, 0.08 * u, "yellow")
			spot(0.93, a, 0.06 * u, "white")
		end
		-- the halo over it (the beam of light out of its top went: "remove these rectangular effects everywhere, instead
		-- make it twinkles", 2026-11-14; the hatch scene's twinkles stand in for it)
		for k = 0, 19 do
			local halo = Blocks.part(m, { size = Vector3.new(0.09, 0.09, 0.09) * u, cf = CFrame.new(0, h + 0.4, 0), color = if k % 4 == 0 then "white" else "yellow", collide = false, query = false, neon = true, shape = "Ball", name = "Halo" })
			table.insert(fx, { p = halo, kind = "halo", k = k })
		end
	end
	-- the cracks (out of sight until the scene shows them): a crack from the top down the front, its branch, then the
	-- ring round the front of its middle. Each is a thin line the scene lights from inside in its rarity's light, with
	-- rays of light streaming out of it (HatchScene's beams), no dark edge (the requests of 2026-11-14: "cracks
	-- sometimes become filled like this, can you make it such that light streams out instead when this happens?", then
	-- "make light stream out, as in rays of light streaming out, like the image. no need for the black outlines when
	-- cracking"): short pieces lying on the shell, each only half its width past its ends, the turns a pixel or two, so
	-- a line never bunches into a blot where it turns or meets another. They pool no light on the shell ("PixelNoPool").
	-- They stand LIFT studs off the shell's true surface: over the painted marks and the beads and past the pixel
	-- filter's depth bias (Render/Raster: 0.03), or they would hide them; the ring keeps to the front of the egg, well
	-- inside its outline, so standing off it never shows.
	local WIDE, LIFT = 0.055 * u, 0.13 -- (about two art px wide)
	local function crack(path: { { number } }, stage: number)
		for i = 1, #path - 1 do
			local a0, a1 = path[i], path[i + 1]
			local p0, n0 = surf(a0[1], math.rad(a0[2]), LIFT)
			local p1, n1 = surf(a1[1], math.rad(a1[2]), LIFT)
			local mid = (p0 + p1) / 2
			local base = CFrame.lookAt(mid, p1, (n0 + n1).Unit)
			local len = (p1 - p0).Magnitude
			local size = Vector3.new(WIDE, 0.03 * u, len + WIDE)
			local p = Blocks.part(m, { size = size, cf = base, color = "white", collide = false, query = false, neon = true, name = "Crack" })
			-- (its own size, off the 0.25 stud grid Blocks.part snaps to: snapped, a crack was a bar 0.25 wide and
			-- deep, standing off the shell, and the lines ran together into blots)
			p.Size = size
			p:SetAttribute("PixelNoPool", true)
			table.insert(cracks, { p = p, off = base, stage = stage })
		end
	end
	crack({ { 0.95, 50 }, { 0.9, 47.5 }, { 0.85, 51 }, { 0.8, 48.5 }, { 0.76, 51 } }, 1)
	crack({ { 0.76, 51 }, { 0.71, 48 }, { 0.66, 51.5 }, { 0.61, 49 }, { 0.56, 52 } }, 2)
	crack({ { 0.85, 51 }, { 0.825, 57 }, { 0.8, 63 }, { 0.78, 69 }, { 0.75, 74 } }, 2)
	local ring: { { number } } = {}
	for k = 0, 12 do
		table.insert(ring, { SPLIT + (if k % 2 == 0 then -0.01 else 0.012), -15 + k * 10 })
	end
	crack(ring, 3)
	return m, parts, top, fx, cracks
end

return EggModels
