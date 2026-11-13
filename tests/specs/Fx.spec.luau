-- tests/specs/Fx.spec.luau: the pixel layer's effects (Render/Fx; Controllers/AmbientView draws the islands' small
-- lives with it): packed colours and a tinted sprite's tones, sprites from ArtData's format drawn depth-tested and
-- recorded (flipped, tinted, faded), sticky sprites, the gusts and the grass's patches, and the particles (a fall, a
-- splash's arc, a lit firefly's glow id).
local T = require("../TestKit")
local Fx = require("../../build/luautest/shared/Render/Fx")
local Raster = require("../../build/luautest/shared/Render/Raster")

local ALPHA = 255 * 16777216
local BG = 0x112233 -- the frame's colour (0xRRGGBB)

local function isoCam(W: number, H: number, K: number): any
	local c = Raster.rotation(45, 30)
	c[1], c[2], c[3] = 0, 0, 0
	return Raster.cam(c, 12, W * K, H * K, K, 150)
end

-- A context over a W x H frame, everything at depth `depth` (frame and static), the static ids 1, facing up.
local function ctxOf(W: number, H: number, depth: number): any
	local f = Raster.newFrame(W, H)
	local n = W * H
	local sDepth, sId, sNormal = buffer.create(n * 4), buffer.create(n * 2), buffer.create(n)
	for i = 0, n - 1 do
		buffer.writeu32(f.color, i * 4, Fx.pack(BG))
		buffer.writef32(f.depth, i * 4, depth)
		buffer.writef32(sDepth, i * 4, depth)
		buffer.writeu16(sId, i * 2, 1)
		buffer.writeu8(sNormal, i, Fx.UP_NORMAL)
	end
	local stuck: { [number]: number } = {}
	local c = {
		f = f,
		W = W,
		H = H,
		cam = isoCam(W, H, 2),
		sColor = buffer.create(n * 4),
		sId = sId,
		sNormal = sNormal,
		sAlbedo = buffer.create(n * 4),
		sDepth = sDepth,
		sWClass = buffer.create(n),
		ppu = 8,
		ver = 1,
		now = 0,
		dt = 0,
		idOf = function(_: any): number
			return 0
		end,
		stick = function(i: number, col: number)
			stuck[i] = col
		end,
		unstick = function(i: number)
			stuck[i] = nil
		end,
		px = buffer.create(8 * 4), -- (small: put must grow it)
		npx = 0,
		cap = 8,
		stuck = stuck,
	}
	return c
end

local function at(c: any, x: number, y: number): number
	return Fx.unpack(buffer.readu32(c.f.color, (y * c.W + x) * 4))
end

-- ArtData's format: one character a pixel ("." clear, else an index into pal).
local function data(rows: { string }, pal: { number }): any
	return { w = #rows[1], h = #rows, px = table.concat(rows), pal = pal, alpha = table.create(#pal, 1) }
end

local TN = { 0x2E5937, 0x4A8A4C, 0x76B862, 0xB7E08B } -- the tone markers

return function()
	T.it("colours: pack and unpack round trip, blend halfway, the tones of a tint", function()
		for _, rgb in { 0x000000, 0xFFFFFF, 0x123456, 0xFFA7CA, 0x8ACB6C } do
			T.eq(Fx.unpack(Fx.pack(rgb)), rgb)
			T.eq(Fx.pack(rgb) // 16777216, 255, "opaque")
		end
		local g = Fx.unpack(Fx.blend(Fx.pack(0xFFFFFF), Fx.pack(0x000000), 0.5))
		T.eq(g, 0x808080)
		T.eq(Fx.blend(Fx.pack(0xFF0000), Fx.pack(0x0000FF), 1), Fx.pack(0xFF0000), "fully over")
		local t = Fx.tones(0x8ACB6C)
		T.eq(#t, 4)
		T.eq(t[3], Fx.pack(0x8ACB6C), "the base is the colour itself")
		local function lum(c: number): number
			local rgb = Fx.unpack(c)
			return 0.3 * (rgb // 65536) + 0.59 * ((rgb // 256) % 256) + 0.11 * (rgb % 256)
		end
		T.truthy(lum(t[1]) < lum(t[2]) and lum(t[2]) < lum(t[3]) and lum(t[3]) < lum(t[4]), "dark, shadow, base, light")
		T.eq(Fx.tones(0x8ACB6C), t, "cached")
		for k, v in TN do
			T.eq(Fx.TONES[v], k, "the markers' tones")
		end
	end)

	T.it("sprites: drawn at their anchor, depth-tested, recorded, flipped, tinted and faded", function()
		-- a 3 x 2 sprite: a red pixel, a tone-3 marker, a tone-4 marker; a clear one
		local s = Fx.define("spec_a", { data({ "01.", ".22" }, { 0xFF0000, TN[3], TN[4] }) }, "bottom")
		T.truthy(s.tinted, "it has tone markers")
		T.eq(Fx.sprite("spec_a"), s)
		local w, h = Fx.size(s, 1)
		T.eq(w, 3)
		T.eq(h, 2)
		local c = ctxOf(12, 10, 10)
		Fx.reset(c)
		local tint = Fx.tones(0x3366CC)
		-- bottom anchor at (5, 6): the sprite's left is 5 - 1 = 4, its top 6 - 2 + 1 = 5
		T.truthy(Fx.drawSprite(c, s, 1, 5, 6, 5, false, 0.4, tint))
		T.eq(at(c, 4, 5), 0xFF0000)
		T.eq(at(c, 5, 5), Fx.unpack(tint[3]), "a marker takes the tint's tone")
		T.eq(at(c, 6, 5), BG, "clear stays clear")
		T.eq(at(c, 5, 6), Fx.unpack(tint[4]))
		T.eq(c.npx, 4, "each pixel recorded")
		-- flipped: mirrored in its box
		Fx.reset(c)
		Fx.drawSprite(c, s, 1, 5, 2, 5, true, 0.4, tint)
		T.eq(at(c, 6, 1), 0xFF0000, "the red pixel on the right")
		T.eq(at(c, 4, 2), Fx.unpack(tint[4]))
		-- behind the frame: nothing drawn; within the tolerance: drawn
		Fx.reset(c)
		T.truthy(not Fx.drawSprite(c, s, 1, 9, 9, 20, false, 0.4, tint), "hidden behind")
		T.eq(c.npx, 0)
		T.truthy(Fx.drawSprite(c, s, 1, 9, 9, 10.3, false, 0.4, tint), "a stud's fraction behind still shows (a bird on a rail)")
		-- off the layer: clipped, nothing written outside
		Fx.reset(c)
		T.truthy(not Fx.drawSprite(c, s, 1, -5, -5, 5, false, 0.4, tint))
		-- faded: halfway between the red and the frame
		local c2 = ctxOf(12, 10, 10)
		Fx.drawSprite(c2, s, 1, 5, 6, 5, false, 0.4, tint, 0.5)
		T.eq(at(c2, 4, 5), Fx.unpack(Fx.blend(Fx.pack(0xFF0000), Fx.pack(BG), 0.5)))
		-- the book grows past its room
		local c3 = ctxOf(12, 10, 10)
		for k = 0, 5 do
			Fx.drawSprite(c3, s, 1, 2 + k, 3, 5, false, 0.4, tint)
		end
		T.eq(c3.npx, 24)
		T.truthy(c3.cap >= 24, "grown")
		for k = 0, c3.npx - 1 do
			local i = buffer.readu32(c3.px, k * 4)
			T.truthy(i >= 0 and i < 120, "an index on the layer")
		end
	end)

	T.it("sticky sprites: stuck through the context, against the static depth, and unstuck", function()
		local s = Fx.define("spec_b", { data({ "00", "0." }, { 0x00FF00 }) }, "bottom")
		local c = ctxOf(8, 8, 10)
		-- a model in front in the frame does not matter: the static depth decides
		buffer.writef32(c.f.depth, (3 * 8 + 3) * 4, 1)
		local out = {}
		T.eq(Fx.stickSprite(c, s, 1, 4, 4, 5, false, 0.4, nil, out), 3)
		T.eq(#out, 3)
		T.eq(c.stuck[3 * 8 + 3], Fx.pack(0x00FF00))
		T.eq(c.stuck[4 * 8 + 3], Fx.pack(0x00FF00))
		Fx.unstick(c, out)
		T.eq(#out, 0)
		T.eq(next(c.stuck), nil, "all unstuck")
		T.eq(Fx.stickSprite(c, s, 1, 4, 4, 30, false, 0.4, nil, out), 0, "behind the ground: nothing stuck")
	end)

	T.it("gusts and patches: within their ranges, the frames by the gust", function()
		for k = 0, 200 do
			local x, z, t = k * 1.7 - 90, k * 0.9 - 40, k * 0.37
			local g = Fx.gust(x, z, t, k % 7)
			T.truthy(g >= -1.25 and g <= 1.25, "a gust's range")
			local p = Fx.patch(x, z)
			T.truthy(p >= 0 and p <= 1, "a patch's range")
		end
		T.eq(Fx.swayFrame(0), 1)
		T.eq(Fx.swayFrame(1), 2)
		T.eq(Fx.swayFrame(-1), 3)
		-- some ground bare, some thick
		local bare, thick = 0, 0
		for x = -40, 40 do
			for z = -40, 40 do
				local p = Fx.patch(x, z)
				bare += if p == 0 then 1 else 0
				thick += if p > 0.7 then 1 else 0
			end
		end
		T.truthy(bare > 300 and thick > 300, string.format("patches: %d bare, %d thick", bare, thick))
	end)

	T.it("particles: deterministic, falling, arcing, gone after their life", function()
		local a, b = Fx.newSystem(4), Fx.newSystem(4)
		for _ = 1, 20 do
			local r = Fx.rand(a)
			T.eq(r, Fx.rand(b), "the same stream")
			T.truthy(r >= 0 and r < 1)
		end
		local sys = Fx.newSystem(2)
		T.truthy(Fx.spawn(sys, Fx.KINDS.leaf, 0, 5, 0, 1))
		T.truthy(Fx.spawn(sys, Fx.KINDS.drop, 0, 0, 0, 3, 0, 0, 4))
		T.truthy(not Fx.spawn(sys, Fx.KINDS.leaf, 0, 5, 0, 1), "full")
		Fx.step(nil, sys, 0.1, 4, false)
		T.near(sys.y[1], 5 + Fx.KINDS.leaf.fall * 0.1, 1e-9, "a leaf falls")
		T.truthy(sys.y[2] > 0, "a drop goes up first")
		for _ = 1, 10 do
			Fx.step(nil, sys, 0.1, 4, false)
		end
		T.eq(sys.n, 1, "the leaf's life is over")
		T.truthy(sys.vy[1] < 0 and sys.y[1] < 0.8, "the drop arcs back down")
		Fx.clear(sys)
		T.eq(sys.n, 0)
	end)

	T.it("a lit firefly keeps its colour through the night (its pixels take the glow id)", function()
		local c = ctxOf(40, 30, 1000)
		local sys = Fx.newSystem(4)
		-- in the middle of the camera's view, lit (blink phase 0.1 of its cycle)
		local cam = c.cam
		local x, y, z = cam.cx, cam.cy, cam.cz
		Fx.spawn(sys, Fx.KINDS.firefly, x, y, z, 10, 0, 0, 0, nil, 0)
		Fx.reset(c)
		local drawnN = Fx.step(c, sys, Fx.KINDS.firefly.blink * 0.1 + 0.9, 4, false)
		T.eq(drawnN, 1)
		local glows = 0
		for i = 0, c.W * c.H - 1 do
			if buffer.readu16(c.f.id, i * 2) == Fx.GLOW_ID then
				glows += 1
			end
		end
		T.eq(glows, 5, "a core and its ring")
	end)
end
