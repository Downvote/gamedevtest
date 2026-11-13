--!strict
--!native
-- The pixel layer's effects (docs/ARCHITECTURE.md 9.4; Random Bakery's Render/Fx, cut down): depth-tested pixels and
-- sprites on the art grid, and a small particle system for falling leaves, smoke, steam, fireflies and splashes. Pure
-- (no Instances).
--
-- PixelRenderer hands every effect layer (PixelRenderer.addFxLayer) a context once per tick, after the dynamic models
-- and their outline and before the upload: the frame being composed (the static picture with the dynamic models on it,
-- their depth and ids), its camera and the static G-buffer. Effects write colour, never depth; every pixel they write
-- is recorded (Fx.put), the renderer puts the static picture back there on the next tick and uploads only the pixels
-- whose colour changed. A light that keeps its colour through the night (a firefly) also writes Fx.GLOW_ID into the
-- frame's ids (Fx.glow), which the night's grade leaves alone. Small things that stay put (the lawn's tufts) are
-- sticky instead (Fx.stickSprite): the renderer keeps them over the static picture until they are unstuck or the
-- picture changes (Ctx.ver), so a tuft at rest costs nothing a tick. Nothing here casts a ray.
--
-- Depth: an effect at depth d (studs along the view rays, Fx.project) shows at a pixel whose frame depth D satisfies
-- d - tol < D, so buildings, trees and driftlings in front hide it; tol lets a bird stand on a rail or a ridge.
--
-- Sprites come from UI/ArtData (scripts/gen_art.py, the "fx_" ones; Fx.define): one sprite pixel is one art pixel,
-- never scaled (a smaller one is its own sprite). A tinted sprite's tone markers (Fx.TONES, the four values gen_art.py
-- gives "tn0".."tn3") are drawn in the tones of a colour given at draw time (Fx.tones: a tuft in the lawn's own green,
-- a leaf in its tree's).
local Raster = require(script.Parent.Raster)
local Ramp = require(script.Parent.Ramp)
local Shading = require(script.Parent.Shading)

export type Frame = Raster.Frame
export type Ctx = {
	f: Frame, -- the frame being composed
	W: number,
	H: number,
	cam: Raster.Cam,
	sColor: buffer, -- the static picture (read only): u32 packed colour as shown (with the water's and the wind's paint)
	sId: buffer, -- u16 part id (0 sky)
	sNormal: buffer, -- u8 normal index (Shading.normalIndex)
	sAlbedo: buffer, -- u32 0xRRGGBB (+ the emissive flag)
	sDepth: buffer, -- f32 depth along the rays
	sWClass: buffer, -- u8 water class (1 the sea, 2 the shallows, 3 the foam; 4, 5 the wind's leaves and flags)
	ppu: number, -- art px per stud along the screen axes
	ver: number, -- changes whenever the static picture does (a bake, a scroll, a re-cast): what is worked out from
	-- it may be kept until then
	now: number, -- os.clock() of this tick
	dt: number, -- seconds since this layer's previous tick (clamped to 0.25)
	idOf: (inst: any) -> number, -- static id of a part in the bake (0 when it is not drawn)
	stick: (i: number, c: number) -> (), -- a sticky pixel (Fx.stickSprite): kept until unstuck or `ver` changes
	unstick: (i: number) -> (),
	-- bookkeeping, written by Fx.put
	px: buffer, -- pixel indices written this tick (u32)
	npx: number,
	cap: number,
}

local Fx = {}

local ALPHA = 255 * 16777216
local FAR = 1e29
local CORE = 0xE6FFFF + ALPHA -- a firefly's core (packed: 0xFFFFE6)
-- a firefly's glow round its core and its dim pixel coming on or going out: its yellow green on a night lawn, lit
-- through the night's grade like the core (packed: 0x9BC45C and 0x5E8A4A)
local HALO = 0x5CC49B + ALPHA
local DIM = 0x4A8A5E + ALPHA
local PLAIN = 0x62B876 + ALPHA -- a tinted sprite drawn with no tint: its markers' base (packed: 0x76B862)
Fx.UP_NORMAL = Shading.normalIndex(0, 1, 0)
-- A frame id no part ever has (PixelRenderer's dynamic ids stop at 65534): the night's grade leaves its pixels as
-- they are.
Fx.GLOW_ID = 65535
-- The tone markers of a tinted sprite: colour -> tone (1 deep, 2 shadow, 3 base, 4 light). The same values as
-- scripts/gen_art.py's "tn0".."tn3".
Fx.TONES = { [0x2E5937] = 1, [0x4A8A4C] = 2, [0x76B862] = 3, [0xB7E08B] = 4 } :: { [number]: number }

------------------------------------------------------------------ colours
-- 0xRRGGBB -> a packed frame colour (R + G * 256 + B * 65536, opaque).
function Fx.pack(rgb: number): number
	return bit32.rshift(rgb, 16) + bit32.band(rgb, 0xFF00) + bit32.band(rgb, 0xFF) * 65536 + ALPHA
end

-- A packed frame colour -> 0xRRGGBB.
function Fx.unpack(c: number): number
	return bit32.band(c, 0xFF) * 65536 + bit32.band(c, 0xFF00) + bit32.band(bit32.rshift(c, 16), 0xFF)
end

-- Packed colour `over` at opacity a (0..1) on packed colour `under` (opaque).
local function blend(over: number, under: number, a: number): number
	local k = if a < 0 then 0 elseif a > 1 then 1 else a
	local r = bit32.band(over, 0xFF) * k + bit32.band(under, 0xFF) * (1 - k)
	local g = bit32.band(bit32.rshift(over, 8), 0xFF) * k + bit32.band(bit32.rshift(under, 8), 0xFF) * (1 - k)
	local b = bit32.band(bit32.rshift(over, 16), 0xFF) * k + bit32.band(bit32.rshift(under, 16), 0xFF) * (1 - k)
	return math.floor(r + 0.5) + math.floor(g + 0.5) * 256 + math.floor(b + 0.5) * 65536 + ALPHA
end
Fx.blend = blend

-- The four packed tones of a colour (0xRRGGBB) a tinted sprite is drawn in: Render/Ramp's hue-shifted ramp (a dark and
-- a shadow step cooler, the colour itself, a light step warmer). Cached.
local toneCache: { [number]: { number } } = {}
local toneCount = 0
function Fx.tones(rgb: number): { number }
	local t = toneCache[rgb]
	if t then
		return t
	end
	if toneCount > 1024 then
		table.clear(toneCache)
		toneCount = 0
	end
	local r = Ramp.hex(rgb)
	local made = { Fx.pack(r[1]), Fx.pack(r[2]), Fx.pack(rgb), Fx.pack(r[4]) }
	toneCache[rgb] = made
	toneCount += 1
	return made
end

------------------------------------------------------------------ bookkeeping
-- A fresh book of written pixels.
function Fx.newBook(): buffer
	return buffer.create(4096 * 4)
end

-- Start a tick: no pixels written yet.
function Fx.reset(ctx: Ctx)
	ctx.npx = 0
end

-- Write packed colour c at layer pixel (x, y) (inside the layer) and record it.
local function put(ctx: Ctx, x: number, y: number, c: number)
	local i = y * ctx.W + x
	buffer.writeu32(ctx.f.color, i * 4, c)
	local n = ctx.npx
	if n >= ctx.cap then
		local cap = ctx.cap * 2
		local nb = buffer.create(cap * 4)
		buffer.copy(nb, 0, ctx.px, 0, n * 4)
		ctx.px, ctx.cap = nb, cap
	end
	buffer.writeu32(ctx.px, n * 4, i)
	ctx.npx = n + 1
end
Fx.put = put

-- A light's pixel: colour c at (x, y) with the glow id, so the night's grade keeps its colour.
function Fx.glow(ctx: Ctx, x: number, y: number, d: number, c: number, tol: number?)
	if x < 0 or y < 0 or x >= ctx.W or y >= ctx.H then
		return
	end
	local i = y * ctx.W + x
	if d - (tol or 0.05) < buffer.readf32(ctx.f.depth, i * 4) then
		put(ctx, x, y, c)
		buffer.writeu16(ctx.f.id, i * 2, Fx.GLOW_ID)
	end
end

------------------------------------------------------------------ geometry
-- World point -> layer pixel (float) and depth along the rays (<= 0: behind the ray plane). Raster.project.
Fx.projectCam = Raster.project

function Fx.project(ctx: Ctx, x: number, y: number, z: number): (number, number, number)
	return Raster.project(ctx.cam, x, y, z)
end

-- Frame depth at layer pixel (x, y) (FAR off the layer).
function Fx.depthAt(ctx: Ctx, x: number, y: number): number
	if x < 0 or y < 0 or x >= ctx.W or y >= ctx.H then
		return FAR
	end
	return buffer.readf32(ctx.f.depth, (y * ctx.W + x) * 4)
end

-- The static surface at layer pixel (x, y): its depth, normal index and part id (FAR, 13, 0 for the sky or off the
-- layer).
function Fx.staticAt(ctx: Ctx, x: number, y: number): (number, number, number)
	if x < 0 or y < 0 or x >= ctx.W or y >= ctx.H then
		return FAR, 13, 0
	end
	local i = y * ctx.W + x
	local id = buffer.readu16(ctx.sId, i * 2)
	if id == 0 then
		return FAR, 13, 0
	end
	return buffer.readf32(ctx.sDepth, i * 4), buffer.readu8(ctx.sNormal, i), id
end

-- The screen's x axis on the ground (unit, horizontal): the way things sway.
function Fx.swayAxis(cam: Raster.Cam): (number, number)
	local l = math.sqrt(cam.rx * cam.rx + cam.rz * cam.rz)
	if l < 1e-6 then
		return 1, 0
	end
	return cam.rx / l, cam.rz / l
end

-- A gust rolling across the ground at world (x, z) at time t: -1.25 .. 1.25 (a crest leans grass with the wind, a
-- trough leans it back). `phase` (0..2 pi) adds each tuft's own flutter.
function Fx.gust(x: number, z: number, t: number, phase: number): number
	return math.sin(t * 1.1 - (x * 0.31 + z * 0.17)) + 0.25 * math.sin(t * 3.1 + phase)
end

-- How lush the grass is round world cell (x, z): 0 .. 1 in soft patches a few studs across (the tufts are sown by it,
-- so some stretches are bare and some thick).
function Fx.patch(x: number, z: number): number
	local n = math.sin(x * 0.37 + z * 0.21) + math.sin(x * 0.13 - z * 0.41 + 1.7) + 0.6 * math.sin(z * 0.29 + x * 0.07 + 4.1)
	return math.clamp((n + 0.6) / 2.4, 0, 1)
end

-- The frame of a swaying tuft for a gust value: 1 upright, 2 leaning with the wind, 3 leaning back.
function Fx.swayFrame(g: number): number
	return if g > 0.75 then 2 elseif g < -0.95 then 3 else 1
end

------------------------------------------------------------------ pixels
-- Packed colour c at layer pixel (x, y) when an effect at depth d shows there (see the header).
function Fx.dot(ctx: Ctx, x: number, y: number, d: number, c: number, tol: number?)
	if x < 0 or y < 0 or x >= ctx.W or y >= ctx.H then
		return
	end
	if d - (tol or 0.05) < buffer.readf32(ctx.f.depth, (y * ctx.W + x) * 4) then
		put(ctx, x, y, c)
	end
end

-- Packed colour c at opacity a (0..1) over what the frame shows at (x, y).
function Fx.mix(ctx: Ctx, x: number, y: number, d: number, c: number, a: number, tol: number?)
	if x < 0 or y < 0 or x >= ctx.W or y >= ctx.H or a <= 0.02 then
		return
	end
	local i = (y * ctx.W + x) * 4
	if d - (tol or 0.05) < buffer.readf32(ctx.f.depth, i) then
		put(ctx, x, y, if a >= 0.98 then c else blend(c, buffer.readu32(ctx.f.color, i), a))
	end
end

------------------------------------------------------------------ sprites
-- One frame: flat triples (dx, dy, colour), the colour packed, or -k for tone k of the draw's tint.
type SpriteFrame = { w: number, h: number, px: { number } }
export type Sprite = {
	name: string,
	frames: { SpriteFrame },
	anchor: string, -- "bottom": (x, y) is the bottom centre (feet); "centre": the middle
	tinted: boolean,
}
-- UI/ArtData's format (scripts/gen_art.py)
export type SpriteData = { w: number, h: number, px: string, pal: { number }, alpha: { number } }

local CHARS = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!$%&*+-/:;<=>?@^_~"
local INDEX: { [string]: number } = {}
for i = 1, #CHARS do
	INDEX[string.sub(CHARS, i, i)] = i
end

local SPRITES: { [string]: Sprite } = {}

-- A sprite from its frames' data (each frame in ArtData's format, the same size), anchored at its feet ("bottom") or
-- its middle ("centre"). Pixels less than half opaque are left out.
function Fx.define(name: string, frames: { SpriteData }, anchor: string): Sprite
	local out: { SpriteFrame } = {}
	local tinted = false
	for _, d in frames do
		local px: { number } = {}
		for i = 1, math.min(#d.px, d.w * d.h) do
			local k = INDEX[string.sub(d.px, i, i)]
			if k and (d.alpha[k] or 1) >= 0.5 then
				local rgb = d.pal[k]
				local tone = Fx.TONES[rgb]
				table.insert(px, (i - 1) % d.w)
				table.insert(px, (i - 1) // d.w)
				if tone then
					tinted = true
					table.insert(px, -tone)
				else
					table.insert(px, Fx.pack(rgb))
				end
			end
		end
		table.insert(out, { w = d.w, h = d.h, px = px })
	end
	local s: Sprite = { name = name, frames = out, anchor = anchor, tinted = tinted }
	SPRITES[name] = s
	return s
end

function Fx.sprite(name: string): Sprite?
	return SPRITES[name]
end

-- The width and height of a sprite frame (the frame index wraps).
function Fx.size(s: Sprite, frame: number): (number, number)
	local fr = s.frames[(math.floor(frame) - 1) % #s.frames + 1]
	return fr.w, fr.h
end

-- Draw frame `frame` (1-based, wraps) of sprite s at layer pixel (x, y) (its anchor), at depth d, facing right or
-- (flip) left. Each pixel is depth-tested (tol, default 0.4 stud). `tint` (Fx.tones) colours a tinted sprite's tone
-- markers; `alpha` below 1 blends it over the frame (a leaf fading). Returns whether any pixel was drawn.
function Fx.drawSprite(ctx: Ctx, s: Sprite, frame: number, x: number, y: number, d: number, flip: boolean, tol: number?, tint: { number }?, alpha: number?): boolean
	local fr = s.frames[(math.floor(frame) - 1) % #s.frames + 1]
	local left = math.floor(x) - fr.w // 2
	local top = if s.anchor == "bottom" then math.floor(y) - fr.h + 1 else math.floor(y) - fr.h // 2
	local W, H = ctx.W, ctx.H
	if left >= W or top >= H or left + fr.w <= 0 or top + fr.h <= 0 then
		return false
	end
	local depth, color = ctx.f.depth, ctx.f.color
	local lim = d - (tol or 0.4)
	local px = fr.px
	local a = alpha or 1
	-- (the book has room for the whole sprite first; then each pixel is written and recorded in line)
	local n = ctx.npx
	local need = n + #px // 3
	if need > ctx.cap then
		local cap = math.max(ctx.cap * 2, need)
		local nb = buffer.create(cap * 4)
		buffer.copy(nb, 0, ctx.px, 0, n * 4)
		ctx.px, ctx.cap = nb, cap
	end
	local book = ctx.px
	local n0 = n
	local w1 = left + fr.w - 1
	for i = 1, #px, 3 do
		local dx = px[i]
		local sx = if flip then w1 - dx else left + dx
		local sy = top + px[i + 1]
		if sx >= 0 and sy >= 0 and sx < W and sy < H then
			local o = sy * W + sx
			if lim < buffer.readf32(depth, o * 4) then
				local c = px[i + 2]
				if c < 0 then
					c = if tint then tint[-c] else PLAIN
				end
				if a < 0.98 then
					c = blend(c, buffer.readu32(color, o * 4), a)
				end
				buffer.writeu32(color, o * 4, c)
				buffer.writeu32(book, n * 4, o)
				n += 1
			end
		end
	end
	ctx.npx = n
	return n > n0
end

-- Fx.drawSprite's sticky twin: the sprite's pixels stuck (ctx.stick) where it shows in front of the static picture
-- (depth-tested against the static depth: a model drawn later hides it as it would the ground), their pixel indices
-- added to `out` (for Fx.unstick). Returns how many were stuck.
function Fx.stickSprite(ctx: Ctx, s: Sprite, frame: number, x: number, y: number, d: number, flip: boolean, tol: number?, tint: { number }?, out: { number }): number
	local fr = s.frames[(math.floor(frame) - 1) % #s.frames + 1]
	local left = math.floor(x) - fr.w // 2
	local top = if s.anchor == "bottom" then math.floor(y) - fr.h + 1 else math.floor(y) - fr.h // 2
	local W, H = ctx.W, ctx.H
	local depth = ctx.sDepth
	local lim = d - (tol or 0.4)
	local px = fr.px
	local w1 = left + fr.w - 1
	local stick = ctx.stick
	local n = 0
	for i = 1, #px, 3 do
		local dx = px[i]
		local sx = if flip then w1 - dx else left + dx
		local sy = top + px[i + 1]
		if sx >= 0 and sy >= 0 and sx < W and sy < H then
			local o = sy * W + sx
			if lim < buffer.readf32(depth, o * 4) then
				local c = px[i + 2]
				if c < 0 then
					c = if tint then tint[-c] else PLAIN
				end
				stick(o, c)
				table.insert(out, o)
				n += 1
			end
		end
	end
	return n
end

-- Unstick the pixels in `list` (Fx.stickSprite's out) and empty it.
function Fx.unstick(ctx: Ctx, list: { number })
	local unstick = ctx.unstick
	for _, o in list do
		unstick(o)
	end
	table.clear(list)
end

------------------------------------------------------------------ particles
-- Kinds: how a particle moves, lands and is drawn.
--   fall: vertical speed (studs/s, negative falls); grav: it slows by this much a second (a splash's drops arc back);
--   sway: sideways amplitude (studs, along the screen's x) at swayHz; tumble: sprite frames a second; land: lie on an
--   up-facing static surface for `linger` seconds (else vanish against a wall); fadeIn / fadeOut: seconds of the
--   opacity ramps; sprite (a tinted one takes the particle's tint) or a dot of `rgb` at `alpha`; blink: on and off
--   (seconds a cycle: a firefly, its core glowing through the night); wide: a dot two pixels wide this long after
--   birth (a wisp's root).
export type Kind = {
	fall: number,
	grav: number,
	sway: number,
	swayHz: number,
	tumble: number,
	land: boolean,
	linger: number,
	fadeIn: number,
	fadeOut: number,
	sprite: string?,
	rgb: number,
	alpha: number,
	blink: number?,
	wide: number?,
}

local KINDS: { [string]: Kind } = {
	leaf = { fall = -0.7, grav = 0, sway = 1, swayHz = 0.28, tumble = 4, land = true, linger = 5, fadeIn = 0.4, fadeOut = 1, sprite = "fx_leaf", rgb = 0x76B862, alpha = 1 },
	petal = { fall = -0.5, grav = 0, sway = 0.8, swayHz = 0.32, tumble = 3, land = true, linger = 4, fadeIn = 0.4, fadeOut = 0.8, sprite = "fx_petal", rgb = 0xFFC3DA, alpha = 1 },
	smoke = { fall = 0.9, grav = 0, sway = 0.18, swayHz = 0.6, tumble = 0, land = false, linger = 0, fadeIn = 0.2, fadeOut = 1.2, rgb = 0xE4E0EA, alpha = 0.8, wide = 1 },
	steam = { fall = 0.75, grav = 0, sway = 0.12, swayHz = 0.9, tumble = 0, land = false, linger = 0, fadeIn = 0.15, fadeOut = 0.9, rgb = 0xFFFFFF, alpha = 0.7, wide = 0.5 },
	firefly = { fall = 0.03, grav = 0, sway = 0.6, swayHz = 0.15, tumble = 0, land = false, linger = 0, fadeIn = 0.8, fadeOut = 0.8, rgb = 0xEAFF8A, alpha = 1, blink = 2.6 },
	drop = { fall = 0, grav = 14, sway = 0, swayHz = 1, tumble = 0, land = true, linger = 0, fadeIn = 0.02, fadeOut = 0.1, rgb = 0xEEF9F6, alpha = 1 },
}
Fx.KINDS = KINDS

export type System = {
	n: number,
	cap: number,
	kind: { Kind },
	tint: { { number } | false },
	x: { number },
	y: { number },
	z: { number },
	vx: { number },
	vz: { number },
	vy: { number },
	age: { number },
	life: { number },
	phase: { number },
	landed: { number }, -- 0 in flight, else the age it landed at
	seed: number,
}

function Fx.newSystem(cap: number): System
	return {
		n = 0,
		cap = cap,
		kind = {},
		tint = {},
		x = {},
		y = {},
		z = {},
		vx = {},
		vz = {},
		vy = {},
		age = {},
		life = {},
		phase = {},
		landed = {},
		seed = 12345,
	}
end

-- A deterministic pseudo-random number in [0, 1) (the system's own stream).
function Fx.rand(sys: System): number
	local s = (sys.seed * 1103515245 + 12345) % 2147483648
	sys.seed = s
	return s / 2147483648
end

-- Spawn one particle (false when the system is full). v*: velocity (studs/s) on top of the kind's fall; phase: the
-- sway's phase (radians; random by default: an emitter giving its particles the same phase draws one continuous wisp);
-- tint: a tinted sprite's tones (Fx.tones).
function Fx.spawn(sys: System, kind: Kind, x: number, y: number, z: number, life: number, vx: number?, vz: number?, vy: number?, tint: { number }?, phase: number?): boolean
	if sys.n >= sys.cap then
		return false
	end
	local i = sys.n + 1
	sys.n = i
	sys.kind[i] = kind
	sys.tint[i] = tint or false
	sys.x[i], sys.y[i], sys.z[i] = x, y, z
	sys.vx[i], sys.vz[i], sys.vy[i] = vx or 0, vz or 0, vy or 0
	sys.age[i] = 0
	sys.life[i] = life
	sys.phase[i] = phase or Fx.rand(sys) * 6.2832
	sys.landed[i] = 0
	return true
end

local function remove(sys: System, i: number)
	local n = sys.n
	if i ~= n then
		sys.kind[i], sys.tint[i] = sys.kind[n], sys.tint[n]
		sys.x[i], sys.y[i], sys.z[i] = sys.x[n], sys.y[n], sys.z[n]
		sys.vx[i], sys.vz[i], sys.vy[i] = sys.vx[n], sys.vz[n], sys.vy[n]
		sys.age[i], sys.life[i], sys.phase[i], sys.landed[i] = sys.age[n], sys.life[n], sys.phase[n], sys.landed[n]
	end
	sys.tint[n] = false
	sys.n = n - 1
end

function Fx.clear(sys: System)
	for i = 1, sys.n do
		sys.tint[i] = false
	end
	sys.n = 0
end

-- Move every particle by dt and draw it. Particles that leave the layer (by `margin` px) or outlive their life are
-- removed; landing ones lie where they touched an up-facing static surface. `still` (reduced motion) freezes the sway
-- and the tumble. `ctx` nil: only move them (nothing is drawn, nothing lands, nothing leaves by the screen). Returns
-- the particles drawn.
function Fx.step(ctx: Ctx?, sys: System, dt: number, margin: number, still: boolean): number
	local drawn = 0
	local i = 1
	local sxa, sza = 1, 0
	if ctx then
		sxa, sza = Fx.swayAxis(ctx.cam)
	end
	while i <= sys.n do
		local k = sys.kind[i]
		local age = sys.age[i] + dt
		sys.age[i] = age
		if age >= sys.life[i] then
			remove(sys, i)
			continue
		end
		local landedAt = sys.landed[i]
		local x, y, z = sys.x[i], sys.y[i], sys.z[i]
		local phase = sys.phase[i]
		if landedAt == 0 then
			if k.grav ~= 0 then
				sys.vy[i] -= k.grav * dt
			end
			x += sys.vx[i] * dt
			z += sys.vz[i] * dt
			y += (k.fall + sys.vy[i]) * dt
			sys.x[i], sys.y[i], sys.z[i] = x, y, z
		end
		if ctx == nil then
			i += 1
			continue
		end
		local W, H = ctx.W, ctx.H
		local sw = if still or landedAt > 0 then 0 else k.sway * math.sin(age * k.swayHz * 6.2832 + phase)
		local fx, fy, d = Raster.project(ctx.cam, x + sxa * sw, y, z + sza * sw)
		local ix, iy = math.floor(fx), math.floor(fy)
		if d <= 0 or ix < -margin or iy < -margin or ix >= W + margin or iy >= H + margin then
			remove(sys, i)
			continue
		end
		-- landing: the particle reached the static surface its pixel shows
		if k.land and landedAt == 0 and (age > 0.25 or k.grav > 0) and ix >= 0 and iy >= 0 and ix < W and iy < H then
			local o = iy * W + ix
			local falling = k.grav == 0 or (k.fall + sys.vy[i]) < 0
			if falling and buffer.readu16(ctx.sId, o * 2) ~= 0 and d >= buffer.readf32(ctx.sDepth, o * 4) - 0.05 then
				if buffer.readu8(ctx.sNormal, o) == Fx.UP_NORMAL and k.linger > 0 then
					sys.landed[i] = age
					sys.life[i] = age + k.linger * (0.6 + 0.8 * ((phase * 7.3) % 1))
				else
					remove(sys, i)
					continue
				end
			end
		end
		-- opacity: fade in after birth, out before death
		local a = 1
		if age < k.fadeIn then
			a = age / k.fadeIn
		end
		local left = sys.life[i] - age
		if left < k.fadeOut then
			a = math.min(a, left / k.fadeOut)
		end
		local spriteName = k.sprite
		if spriteName then
			local s = SPRITES[spriteName]
			if s and a > 0.08 then
				local frame = if still or landedAt > 0 or k.tumble <= 0 then 1 else math.floor(age * k.tumble + phase) % #s.frames + 1
				local t = sys.tint[i]
				Fx.drawSprite(ctx, s, frame, ix, iy, d, phase > 3.14, 0.1, if type(t) == "table" then t else nil, a)
				drawn += 1
			end
		else
			local alpha = k.alpha * a
			local blink = k.blink
			if blink then
				local t = (age / blink + phase) % 1
				alpha *= if t < 0.6 then math.min(1, t * 8) * (1 - t / 0.6 * 0.3) else 0
			end
			if alpha > 0.05 then
				local c = Fx.pack(k.rgb)
				if blink then
					-- a firefly: lit, a pale core in a ring of glow, both keeping their colour through the night;
					-- coming on or going out, one dim pixel
					if alpha > 0.5 then
						Fx.glow(ctx, ix - 1, iy, d, HALO)
						Fx.glow(ctx, ix + 1, iy, d, HALO)
						Fx.glow(ctx, ix, iy - 1, d, HALO)
						Fx.glow(ctx, ix, iy + 1, d, HALO)
						Fx.glow(ctx, ix, iy, d, CORE)
					else
						Fx.glow(ctx, ix, iy, d, DIM)
					end
				else
					Fx.mix(ctx, ix, iy, d, c, alpha)
					local wide = k.wide
					if wide and age < wide then
						-- a thicker start (a wisp's root): the pixel beside it, a little fainter
						Fx.mix(ctx, ix + 1, iy, d, c, alpha * 0.7)
					end
				end
				drawn += 1
			end
		end
		i += 1
	end
	return drawn
end

return Fx
