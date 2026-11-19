--!strict
--!native
-- The weather on the islands (GAME_DESIGN 13; docs/ARCHITECTURE.md 10.12), drawn in the pixel layer: one effect layer
-- of its own (PixelRenderer.addFxLayer, Render/Fx: depth-tested pixels and sprites on whole art pixels, no parts, no
-- rays). The request (2026-11-14): "also, make weather and seasons, and eggs spawns are affected by these with
-- different mutations". The season and the weather come from the sea's clock (Logic/Weather.at(StateClient.seaClock()),
-- the same on every client and the server):
--   rain: thin streaks falling at a slant, a pixel or two of splash where they land, a soft drizzle loop;
--   storm: heavier, faster rain, a darker light, now and then a soft flash of lightning and a roll of thunder;
--   snow: flakes (a pixel, a round one, a star) drifting down and settling on what faces up for a moment;
--   fog: soft clouds of mist drifting over the island, dithered thicker in their middles, moving with the world;
--   blossom wind: pink petals tumbling across on the wind; falling leaves: orange and red leaves;
--   heat haze: pale motes rising off the ground; breezy: quick lines of wind and a few leaves blowing past;
--   sunny: nothing but the light.
-- Each weather brings its own light over the bright day (Data/Weather `grade`, DayLight.setWeather), changed in a
-- few steps when the weather turns, and its sounds (Audio.ambience "rain", "downpour", "wind"). A new spell fades in
-- over a few seconds. Nothing shows on the hatch scene's stage, nothing moves with reduced motion (the light stays),
-- and there is less of it on the lower tiers.
--   start(), debugSet(kind?) (previews and sims: a weather held), debugFlash(secs?) (previews: lightning now), debugState()
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Street = require(ReplicatedStorage.Shared.Data.Street)
local Data = require(ReplicatedStorage.Shared.Data.Weather)
local Weather = require(ReplicatedStorage.Shared.Logic.Weather)
local Raster = require(ReplicatedStorage.Shared.Render.Raster)
local Fx = require(ReplicatedStorage.Shared.Render.Fx)
local CameraController = require(script.Parent.CameraController)
local StateClient = require(script.Parent.StateClient)
local DayLight = require(script.Parent.DayLight)
local Audio = require(script.Parent.Audio)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ArtData = require(script.Parent.Parent.UI.ArtData)

local WeatherView = {}

------------------------------------------------------------------ constants
local TIER_SCALE: { [string]: number } = { low = 0.5, medium = 0.75, high = 1 }
local LAWN_Y = Street.LAWN_Y
local FADE_IN = 4 -- seconds a new spell's weather takes to fill the sky
local GRADE_STEPS = 4 -- a change of light goes in this many steps ...
local GRADE_SECS = 2 -- ... over this long
-- particles spawned a second at full strength, per 1000 layer pixels
local DENSITY: { [string]: number } = { rain = 3.2, storm = 5, snow = 1.2, blossom = 0.45, leaves = 0.4, haze = 0.25, breezy = 0.35 }
local RAIN_RGB, SPLASH_RGB = 0xDDEBF7, 0xF2F8FF
-- snowflakes: a pixel, a round one, a star (ArtData's fx_flake_1 .. 3), the small ones the most
local SNOW = {
	{ fall = -1.3, grav = 0, sway = 0.45, swayHz = 0.25, tumble = 0, land = true, linger = 1.5, fadeIn = 0.3, fadeOut = 0.6, rgb = 0xFAFCFF, alpha = 1, sprite = "fx_flake1" } :: Fx.Kind,
	{ fall = -1.1, grav = 0, sway = 0.5, swayHz = 0.22, tumble = 0, land = true, linger = 1.5, fadeIn = 0.3, fadeOut = 0.6, rgb = 0xFAFCFF, alpha = 1, sprite = "fx_flake2" } :: Fx.Kind,
	{ fall = -0.9, grav = 0, sway = 0.6, swayHz = 0.2, tumble = 0, land = true, linger = 1.5, fadeIn = 0.3, fadeOut = 0.6, rgb = 0xFAFCFF, alpha = 1, sprite = "fx_flake3" } :: Fx.Kind,
}
local SHIMMER = { fall = 0.5, grav = 0, sway = 0.3, swayHz = 0.4, tumble = 0, land = false, linger = 0, fadeIn = 0.5, fadeOut = 0.8, rgb = 0xFFF2DA, alpha = 0.45 } :: Fx.Kind
local SPLASH = { fall = 0, grav = 14, sway = 0, swayHz = 1, tumble = 0, land = false, linger = 0, fadeIn = 0.02, fadeOut = 0.08, rgb = SPLASH_RGB, alpha = 0.8 } :: Fx.Kind
local PETAL_TINTS = { Fx.tones(0xFFB7D0), Fx.tones(0xFFD2E2), Fx.tones(0xF59AC0) }
local LEAF_TINTS = { Fx.tones(0xF29C3A), Fx.tones(0xD9572E), Fx.tones(0xE8BE3A), Fx.tones(0xB8462E) }

------------------------------------------------------------------ state
local started = false
local forced: string? = nil
local flakes = Fx.newSystem(1000) -- snow, petals, leaves, motes, splashes
-- rain drops and wind lines: world x, y, z, their speed, how long they live
type Streak = { x: number, y: number, z: number, vx: number, vy: number, vz: number, life: number, age: number, len: number, wind: boolean }
local streaks: { Streak } = {}
local MAX_STREAKS = 1600
-- a breezy day's wisps of wind on screen at once (at the high tier; fewer below). It was some fifty faint streaks,
-- which in a still frame read as a broken picture rather than wind (the sweep of 2026-11-19).
local MAX_WISPS = 7
local WISP_RGB = 0xF6FAFF
local strength: { [string]: number } = {} -- each kind's strength now (0 .. 1), fading in and out
local shownKind = "sunny" -- the spell's kind (for the light and the sounds)
local gradeFrom: Data.Grade? = nil -- the light being stepped from and to
local gradeTo: Data.Grade? = nil
local gradeAt = -100
local gradeStep = -1
local flashUntil = 0 -- a lightning flash's end (os.clock)
local wasFlashing = false
local nextFlash = 0
local thunderAt = 0
local onStage = false
local counts = { drops = 0, flakes = 0, fog = 0, lines = 0 }
local rng = Random.new(1717)

------------------------------------------------------------------ helpers
local function nowState(): Weather.State?
	local c = StateClient.seaClock()
	if c <= 0 then
		return nil
	end
	return Weather.at(c)
end

local function kindNow(): string
	if forced then
		return forced :: string
	end
	local st = nowState()
	return if st then st.kind else "sunny"
end

local function quiet(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

local function tierScale(): number
	return TIER_SCALE[PixelRenderer.tier()] or 0
end

local function lerpGrade(a: Data.Grade?, b: Data.Grade?, t: number): Data.Grade?
	if a == nil and b == nil then
		return nil
	end
	local A: Data.Grade = a or { mr = 1, mg = 1, mb = 1, lift = 0, sat = 1 }
	local B: Data.Grade = b or { mr = 1, mg = 1, mb = 1, lift = 0, sat = 1 }
	return {
		mr = A.mr + (B.mr - A.mr) * t,
		mg = A.mg + (B.mg - A.mg) * t,
		mb = A.mb + (B.mb - A.mb) * t,
		lift = A.lift + (B.lift - A.lift) * t,
		sat = A.sat + (B.sat - A.sat) * t,
	}
end

-- A point on the ground plane (y) under layer pixel (i, j), along the camera's look.
local function groundAt(cam: Raster.Cam, i: number, j: number, y: number): (number, number, number)
	local ox, oy, oz = Raster.origin(cam, i, j)
	local t = if math.abs(cam.ly) > 1e-4 then (y - oy) / cam.ly else 0
	return ox + cam.lx * t, y, oz + cam.lz * t
end

------------------------------------------------------------------ spawning
local function spawnStreak(cam: Raster.Cam, W: number, H: number, storm: boolean)
	if #streaks >= MAX_STREAKS then
		return
	end
	local gx, _, gz = groundAt(cam, rng:NextNumber(-0.1, 1.1) * W, rng:NextNumber(-0.3, 1) * H, LAWN_Y)
	local h = rng:NextNumber(6, 16)
	local speed = if storm then rng:NextNumber(22, 28) else rng:NextNumber(15, 19)
	local slant = if storm then 0.35 else 0.15
	table.insert(streaks, {
		x = gx - slant * h,
		y = LAWN_Y + h,
		z = gz,
		vx = slant * speed,
		vy = -speed,
		vz = 0,
		life = 2,
		age = 0,
		len = if storm then 1.1 else 0.8,
		wind = false,
	})
end

local function spawnWind(cam: Raster.Cam, W: number, H: number)
	if #streaks >= MAX_STREAKS then
		return
	end
	local gx, _, gz = groundAt(cam, rng:NextNumber(-0.05, 0.7) * W, rng:NextNumber(0.05, 0.95) * H, LAWN_Y)
	-- (len: the wisp's length in layer pixels, the same at every zoom)
	table.insert(streaks, { x = gx, y = LAWN_Y + rng:NextNumber(1, 5), z = gz, vx = cam.rx * 16, vy = 0, vz = cam.rz * 16, life = 1.6, age = 0, len = rng:NextInteger(12, 20), wind = true })
end

local function spawnFlake(cam: Raster.Cam, W: number, H: number, kind: string)
	local top = kind ~= "haze"
	local gx, _, gz = groundAt(cam, rng:NextNumber(-0.1, 1.1) * W, rng:NextNumber(if top then -0.3 else 0.05, 1) * H, LAWN_Y)
	if kind == "snow" then
		local roll = rng:NextNumber()
		local k = if roll < 0.45 then SNOW[1] elseif roll < 0.8 then SNOW[2] else SNOW[3]
		Fx.spawn(flakes, k, gx, LAWN_Y + rng:NextNumber(4, 14), gz, 16)
	elseif kind == "haze" then
		Fx.spawn(flakes, SHIMMER, gx, LAWN_Y + rng:NextNumber(0.1, 1), gz, rng:NextNumber(2, 3.5))
	else
		-- petals and leaves on the wind: across the screen as they fall
		local leaf = kind == "leaves" or (kind == "breezy" and rng:NextNumber() < 0.6)
		local k = if leaf then Fx.KINDS.leaf else Fx.KINDS.petal
		local tints = if leaf then LEAF_TINTS else PETAL_TINTS
		local wind = if kind == "breezy" then 5 else 2.2
		Fx.spawn(flakes, k, gx - cam.rx * 6, LAWN_Y + rng:NextNumber(4, 10), gz - cam.rz * 6, 10, cam.rx * wind, cam.rz * wind, nil, tints[rng:NextInteger(1, #tints)])
	end
end

------------------------------------------------------------------ drawing
-- A streak: a short line of pixels from its head up its trail, faint, depth-tested; a raindrop splashes where it
-- reaches the ground.
local function stepStreaks(ctx: Fx.Ctx, dt: number)
	local cam, W, H = ctx.cam, ctx.W, ctx.H
	local rc, wc = Fx.pack(RAIN_RGB), Fx.pack(WISP_RGB)
	local drops, lines = 0, 0
	-- (the live ones kept in place, moved down over the gone: a new list every frame was up to 1,600 entries in a storm)
	local kept = 0
	local list = streaks
	for i = 1, #list do
		local s = list[i]
		s.age += dt
		s.x += s.vx * dt
		s.y += s.vy * dt
		s.z += s.vz * dt
		if s.age >= s.life then
			continue
		end
		if not s.wind and s.y <= LAWN_Y then
			-- (the ground: a little splash, a pixel or two thrown up)
			if rng:NextNumber() < 0.5 then
				Fx.spawn(flakes, SPLASH, s.x, LAWN_Y + 0.05, s.z, 0.25, rng:NextNumber(-0.6, 0.6), rng:NextNumber(-0.6, 0.6), 1.5)
			end
			continue
		end
		local hx, hy, hd = Raster.project(cam, s.x, s.y, s.z)
		if hy >= H + 4 or hx < -40 or hx >= W + 40 then
			continue -- (gone off the bottom or the sides; one still above the top falls into view)
		end
		if s.wind then
			-- a wisp: a near-white line of its own length straight back from its head, a pixel lower over its back
			-- part (one step, no jaggies), its two ends fading out and the whole of it fading in and out
			local fade = math.min(1, s.age * 4, (s.life - s.age) * 2)
			local n = s.len
			local x0, y0 = math.floor(hx + 0.5), math.floor(hy + 0.5)
			for q = 0, n - 1 do
				local u = q / (n - 1)
				local a = 0.7 * fade * math.min(1, (1 - u) * 3, 0.3 + u * 3)
				Fx.mix(ctx, x0 - q, y0 + (if u > 0.55 then 1 else 0), hd, wc, a)
			end
			lines += 1
			kept += 1
			list[kept] = s
			continue
		end
		-- the trail: back along its motion
		local sp = math.sqrt(s.vx * s.vx + s.vy * s.vy + s.vz * s.vz)
		local k = s.len / math.max(0.01, sp)
		local tx, ty = Raster.project(cam, s.x - s.vx * k, s.y - s.vy * k, s.z - s.vz * k)
		local n = math.max(1, math.floor(math.max(math.abs(tx - hx), math.abs(ty - hy)) + 0.5))
		for q = 0, n do
			local u = q / n
			Fx.mix(ctx, math.floor(hx + (tx - hx) * u), math.floor(hy + (ty - hy) * u), hd, rc, 0.75 * (1 - u * 0.5))
		end
		drops += 1
		kept += 1
		list[kept] = s
	end
	for i = #list, kept + 1, -1 do
		list[i] = nil
	end
	counts.drops, counts.lines = drops, lines
end

-- Fog (the request of 2026-11-14: "the fog weather dosent look good. polish it more, with dithered fog clouds that
-- move"): soft clouds of mist hanging over the island, drifting slowly downwind. A cloud is a few overlapping
-- flattened puffs, its top lumpy, its underside flatter. How thick it is at a pixel (thickest in the middle, thinning
-- to its edge, in four steps) is drawn with a 4x4 ordered dither fixed to the cloud, so the pattern moves with it and
-- never crawls: every pixel in the middle, three in four, every other one, then one in four at the edge. The underside
-- is a shade cooler than the top (lit from above). The clouds hang over the world (they scroll with the island when
-- the view pans), come and go by the same dither, and one that drifts off the screen comes back in from upwind with a
-- new shape.
local FOG_TOP, FOG_LOW = 0xF6F8FC, 0xDCE3EE
local FOG_ALPHA = 0.62
local FOG_CLOUDS = 8 -- clouds at once on the high tier (fewer on the lower ones)
local FOG_FADE = 2.5 -- seconds a cloud takes to come in
local BAYER = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
-- a cloud: where it is (global art px: Raster cams carry their pan as gx, gy), how fast it drifts, when it came in,
-- its size, and its pixels: each one's place, thickness step, dither threshold and whether it is on the underside
type Cloud = { x: number, y: number, vx: number, born: number, w: number, h: number, dx: { number }, dy: { number }, d: { number }, b: { number }, low: { boolean }, n: number }
local clouds: { Cloud } = {}

-- A new cloud's shape, w art px wide.
local function shapeCloud(c: Cloud, w: number)
	local h = math.floor(w * 0.5)
	local puffs: { { number } } = {}
	local n = 4 + rng:NextInteger(0, 3)
	for k = 1, n do
		local u = (k - 0.5) / n
		local r = w * (0.18 + rng:NextNumber() * 0.12) * (1 - math.abs(u - 0.5) * 0.6)
		table.insert(puffs, { w * (0.12 + 0.76 * u) + (rng:NextNumber() - 0.5) * w * 0.06, h * 0.66 - rng:NextNumber() * h * 0.16, r })
	end
	local dx, dy, d, b, low = {}, {}, {}, {}, {}
	local m = 0
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			local best, under = 0, false
			for _, p in puffs do
				local px, py, r = p[1], p[2], p[3]
				local below = y + 0.5 > py
				local ex = (x + 0.5 - px) / r
				local ey = (y + 0.5 - py) / (r * (if below then 0.4 else 0.74))
				local v = 1 - math.sqrt(ex * ex + ey * ey)
				if v > best then
					best, under = v, y + 0.5 > py + r * 0.08
				end
			end
			-- (thickness in four steps: the core from a little under half way in)
			local step = math.ceil(math.clamp(best / 0.45, 0, 1) * 4 - 1e-6) / 4
			if step > 0 then
				m += 1
				dx[m], dy[m], d[m] = x, y, step
				b[m] = (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16
				low[m] = under
			end
		end
	end
	c.w, c.h, c.dx, c.dy, c.d, c.b, c.low, c.n = w, h, dx, dy, d, b, low, m
end

-- A cloud put somewhere: the first ones spread over the screen (slot `slot` of `of`: across it, in staggered rows),
-- one coming back just upwind of it.
local function placeCloud(c: Cloud, cam: Raster.Cam, W: number, H: number, upwind: boolean, now: number, slot: number?, of: number?)
	-- (sized to the screen: a phone's smaller picture gets smaller clouds, so they hang over it the same)
	local fit = math.clamp(math.min(W / 640, H / 360), 0.6, 1.2)
	shapeCloud(c, math.floor(rng:NextInteger(110, 210) * fit))
	local lx, ly
	if upwind or slot == nil or of == nil then
		lx = -c.w - rng:NextInteger(0, 60)
		ly = rng:NextInteger(math.floor(H * 0.04), math.floor(H * 0.8))
	else
		lx = math.floor((slot - 0.5) / of * W - c.w / 2 + rng:NextInteger(-20, 20))
		ly = math.floor(H * (if slot % 2 == 0 then 0.12 else 0.5) + rng:NextInteger(-20, 30))
	end
	c.x, c.y = lx + cam.gx, ly + cam.gy
	c.vx = 2.5 + rng:NextNumber() * 3.5
	c.born = if upwind then now else now - FOG_FADE
end

local function drawFog(ctx: Fx.Ctx, k: number, now: number, dt: number, still: boolean, scale: number)
	local W, H, cam = ctx.W, ctx.H, ctx.cam
	local want = math.max(2, math.floor(FOG_CLOUDS * scale + 0.5))
	while #clouds < want do
		local c: Cloud = { x = 0, y = 0, vx = 0, born = 0, w = 0, h = 0, dx = {}, dy = {}, d = {}, b = {}, low = {}, n = 0 }
		placeCloud(c, cam, W, H, false, now, #clouds + 1, want)
		table.insert(clouds, c)
	end
	local top, under = Fx.pack(FOG_TOP), Fx.pack(FOG_LOW)
	local drawn = 0
	for i, c in clouds do
		if i > want then
			break
		end
		if not still then
			c.x += c.vx * dt
		end
		local lx, ly = math.floor(c.x - cam.gx), math.floor(c.y - cam.gy)
		-- (gone off downwind: back in from upwind with a new shape; left behind by the view as it pans: round to the
		-- far side of the screen, so there are always clouds about the screen)
		if lx > W + 4 then
			placeCloud(c, cam, W, H, true, now)
		elseif lx + c.w < -40 then
			c.x += W + c.w + 40 + rng:NextInteger(0, 30)
		end
		if ly > H + 4 then
			c.y -= H + c.h + 8
		elseif ly + c.h < -4 then
			c.y += H + c.h + 8
		end
		lx, ly = math.floor(c.x - cam.gx), math.floor(c.y - cam.gy)
		if lx + c.w < 0 or lx >= W or ly + c.h < 0 or ly >= H then
			continue
		end
		local kk = k * math.clamp((now - c.born) / FOG_FADE, 0, 1)
		local dxs, dys, ds, bs, lows = c.dx, c.dy, c.d, c.b, c.low
		for m = 1, c.n do
			if ds[m] * kk > bs[m] then
				Fx.mix(ctx, lx + dxs[m], ly + dys[m], 0, if lows[m] then under else top, FOG_ALPHA, 1e9)
				drawn += 1
			end
		end
	end
	counts.fog = drawn
end

local function draw(ctx: Fx.Ctx)
	local view = CameraController.view()
	if view.stage then
		if not onStage then
			onStage = true
			Fx.clear(flakes)
			table.clear(streaks)
		end
		return
	end
	onStage = false
	local dt, now = ctx.dt, ctx.now
	local still = quiet()
	local scale = tierScale()
	local kind = kindNow()
	-- each kind's strength: the spell's own fades in, the others out
	for _, def in Data.KINDS do
		local id = def.id
		local want = if id == kind then 1 else 0
		local s = strength[id] or 0
		s += math.clamp(want - s, -dt / FADE_IN, dt / FADE_IN)
		strength[id] = s
	end
	local area = ctx.W * ctx.H / 1000
	if not still and scale > 0 then
		for id, dens in DENSITY do
			local s = strength[id] or 0
			if s > 0.01 then
				local want = dens * area * s * scale * dt * (if id == "rain" or id == "storm" then 1 else 0.6)
				local spawnN = math.floor(want) + (if rng:NextNumber() < want % 1 then 1 else 0)
				for _ = 1, spawnN do
					if id == "rain" or id == "storm" then
						spawnStreak(ctx.cam, ctx.W, ctx.H, id == "storm")
					elseif id == "breezy" then
						if rng:NextNumber() < 0.7 then
							if counts.lines < math.ceil(MAX_WISPS * scale * s) and rng:NextNumber() < 0.08 then
								spawnWind(ctx.cam, ctx.W, ctx.H)
								counts.lines += 1
							end
						else
							spawnFlake(ctx.cam, ctx.W, ctx.H, id)
						end
					else
						spawnFlake(ctx.cam, ctx.W, ctx.H, id)
					end
				end
			end
		end
	end
	if still then
		Fx.clear(flakes)
		table.clear(streaks)
	end
	stepStreaks(ctx, dt)
	counts.flakes = Fx.step(ctx, flakes, dt, 12, still)
	local fog = strength.fog or 0
	if fog > 0.02 then
		drawFog(ctx, fog, now, dt, still, math.max(scale, 0.5))
	else
		counts.fog = 0
		table.clear(clouds)
	end
end

------------------------------------------------------------------ the light and the sounds
local function heartbeat()
	local kind = kindNow()
	local now = os.clock()
	-- the light: stepped toward the spell's (a few steps, each a re-upload of the picture)
	local def = Data.byId[kind]
	local target = if def then def.grade else nil
	if kind ~= shownKind then
		gradeFrom = lerpGrade(gradeFrom, gradeTo, math.clamp(gradeStep / GRADE_STEPS, 0, 1))
		gradeTo = target
		gradeAt = now
		gradeStep = -1
		shownKind = kind
	end
	local step = math.clamp(math.floor((now - gradeAt) / GRADE_SECS * GRADE_STEPS), 0, GRADE_STEPS)
	local flashing = now < flashUntil
	if step ~= gradeStep or flashing ~= wasFlashing then
		gradeStep, wasFlashing = step, flashing
		local g = lerpGrade(gradeFrom, gradeTo, step / GRADE_STEPS)
		if flashing then
			-- (a lightning flash: the storm's light lifted for a moment, then back)
			local b: Data.Grade = g or { mr = 1, mg = 1, mb = 1, lift = 0, sat = 1 }
			g = { mr = b.mr * 1.28, mg = b.mg * 1.28, mb = b.mb * 1.3, lift = b.lift + 10, sat = b.sat * 0.9 }
		end
		DayLight.setWeather(g)
	end
	-- a storm's lightning: a soft flash every 7 to 16 seconds, its thunder a moment after
	local storm = strength.storm or 0
	if kind == "storm" and storm > 0.5 and not onStage and not quiet() then
		if nextFlash == 0 then
			nextFlash = now + rng:NextNumber(3, 8)
		elseif now >= nextFlash then
			flashUntil = now + 0.12
			thunderAt = now + rng:NextNumber(0.6, 1.4)
			nextFlash = now + rng:NextNumber(7, 16)
		end
	else
		nextFlash = 0
	end
	if thunderAt > 0 and now >= thunderAt then
		thunderAt = 0
		Audio.play("thunder")
	end
	-- the sounds: the drizzle in the rain, the downpour in a storm, the wind on a breezy day and with petals or leaves
	local rain, wind = strength.rain or 0, math.max(strength.breezy or 0, (strength.blossom or 0) * 0.5, (strength.leaves or 0) * 0.5, storm * 0.6)
	Audio.ambience("rain", 1.4 * rain)
	Audio.ambience("downpour", 0.45 * storm)
	Audio.ambience("wind", 0.5 * wind)
end

------------------------------------------------------------------ API
function WeatherView.start()
	if started then
		return
	end
	started = true
	-- (the snowflakes, one sprite each)
	for k = 1, 3 do
		local data = ArtData["fx_flake_" .. k]
		if data and Fx.sprite("fx_flake" .. k) == nil then
			Fx.define("fx_flake" .. k, { data }, "centre")
		end
	end
	-- (the leaf and petal sprites, as AmbientView defines them)
	for _, group in { "leaf", "petal" } do
		if Fx.sprite("fx_" .. group) == nil and ArtData["fx_" .. group .. "_1"] then
			local frames: { Fx.SpriteData } = {}
			local k = 1
			while ArtData["fx_" .. group .. "_" .. k] do
				table.insert(frames, ArtData["fx_" .. group .. "_" .. k])
				k += 1
			end
			Fx.define("fx_" .. group, frames, "centre")
		end
	end
	PixelRenderer.addFxLayer("weather", draw)
	RunService.Heartbeat:Connect(heartbeat)
end

-- Previews and sims: hold a weather (a Data/Weather.KINDS id; nil: the sea's own again). A held weather is at full
-- strength at once.
function WeatherView.debugSet(kind: string?)
	forced = if kind and Data.byId[kind] then kind else nil
	if forced then
		for _, def in Data.KINDS do
			strength[def.id] = if def.id == forced then 1 else 0
		end
		-- (its light at once, no steps)
		local g = Data.byId[forced :: string].grade
		shownKind, gradeFrom, gradeTo, gradeStep = forced :: string, g, g, -1
	end
end

-- Previews: a storm's lightning now, held `secs` (0.12 s, a real flash's length, when not given).
function WeatherView.debugFlash(secs: number?)
	flashUntil = os.clock() + (secs or 0.12)
end

-- What shows now (previews and sims).
function WeatherView.debugState(): { kind: string, season: string, strength: number, drops: number, flakes: number, fog: number, lines: number, flashing: boolean }
	local st = nowState()
	local kind = kindNow()
	return {
		kind = kind,
		season = if st then st.season else "",
		strength = strength[kind] or 0,
		drops = counts.drops,
		flakes = counts.flakes,
		fog = counts.fog,
		lines = counts.lines,
		flashing = os.clock() < flashUntil,
	}
end

return WeatherView
