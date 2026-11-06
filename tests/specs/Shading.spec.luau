-- tests/specs/Shading.spec.luau (WP8): packing, palette LUT, toon bands + dithering, the fixed day palette of UI
-- pictures, see-through blending, sky, outline (and its depth tolerance), sprites.
local T = require("../TestKit")
local Shading = require("../../build/luautest/shared/Render/Shading")
local Palette = require("../../build/luautest/shared/Data/Palette")

local ALPHA = 255 * 16777216

local function frame(W: number, H: number, fill: number)
	local color = buffer.create(W * H * 4)
	local depth = buffer.create(W * H * 4)
	local id = buffer.create(W * H * 2)
	for i = 0, W * H - 1 do
		buffer.writeu32(color, i * 4, fill)
		buffer.writef32(depth, i * 4, 1000)
	end
	return { W = W, H = H, color = color, depth = depth, id = id }
end

local function px(f: any, x: number, y: number): number
	return buffer.readu32(f.color, (y * f.W + x) * 4)
end

local function unpackRGB(c: number): number
	-- packed RGBA (R low byte) -> 0xRRGGBB
	return bit32.band(c, 0xFF) * 65536 + bit32.band(bit32.rshift(c, 8), 0xFF) * 256 + bit32.band(bit32.rshift(c, 16), 0xFF)
end

-- well-separated test palette (pure black is avoided: its darker ramp shades share its 32-level LUT cell)
local PRIMARIES = { 0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0xFFFF00 }

local function restoreDefaults()
	Shading.setPalette(Shading.defaultColors())
	Shading.setMode("day")
end

return function()
	T.it("pack", function()
		T.eq(Shading.pack(255, 0, 0), 0xFF0000FF)
		T.eq(Shading.pack(0, 0, 0), 0xFF000000)
		T.eq(Shading.pack(1, 2, 3), 1 + 2 * 256 + 3 * 65536 + ALPHA)
		T.eq(Shading.pack(300, -5, 255.4), 255 + 0 + 255 * 65536 + ALPHA, "clamped and rounded")
	end)

	T.it("SUN is normalised and points up", function()
		local s = Shading.SUN
		T.near(s.x * s.x + s.y * s.y + s.z * s.z, 1, 1e-9)
		T.truthy(s.y > 0.8 and s.x < 0 and s.z > 0)
	end)

	T.it("LUT nearest colour", function()
		Shading.setPalette(PRIMARIES)
		Shading.setMode("day")
		-- exact palette colours map to themselves
		for _, c in PRIMARIES do
			T.eq(Shading.lut(c), c, string.format("exact %06X", c))
		end
		T.eq(Shading.lut(0xF01010), 0xFF0000)
		T.eq(Shading.lut(0x10F020), 0x00FF00)
		T.eq(Shading.lut(0x10D020), 0x02C702, "closer to green's 0.82 ramp shade than to pure green")
		T.eq(Shading.lut(0x1010F0), 0x0000FF)
		T.eq(Shading.lut(0xF0F0F8), 0xFFFFFF)
		T.eq(Shading.lut(0xEEEE11), 0xFFFF00)
		-- the darker toon bands of every palette colour are targets too (dark red stays red, not black)
		local darkRed = Shading.lut(0x960305)
		T.truthy(bit32.rshift(darkRed, 16) > 120 and bit32.band(darkRed, 0xFF) < 20, string.format("dark red -> %06X", darkRed))
		-- lookups are deterministic and cached per cell
		T.eq(Shading.lut(0xF01010), Shading.lut(0xF01010))
		restoreDefaults()
	end)

	T.it("mode tint moves the palette", function()
		Shading.setPalette(PRIMARIES)
		Shading.setMode("night") -- r 0.8, g 0.84, b 1.15
		T.eq(Shading.lut(0xCC0000), 0xCC0000, "tinted red is a target")
		T.eq(Shading.lut(0xFF0000), 0xCC0000, "untinted red snaps to the tinted one")
		Shading.setMode("no_such_mode") -- falls back to day
		T.eq(Shading.lut(0xFF0000), 0xFF0000)
		restoreDefaults()
	end)

	T.it("toon bands, shadow and emissive", function()
		Shading.setPalette(PRIMARIES)
		Shading.setMode("day")
		local top = Shading.toon(0xFF0000, 0, 1, 0, 1, 0, 0)
		T.eq(top, 0xFF0000FF, "lit top face is the full colour")
		local east = Shading.toon(0xFF0000, 1, 0, 0, 1, 0, 0)
		local south = Shading.toon(0xFF0000, 0, 0, 1, 1, 0, 0)
		local shadowed = Shading.toon(0xFF0000, 0, 1, 0, 0, 0, 0)
		local rTop, rSouth, rEast = bit32.band(top, 0xFF), bit32.band(south, 0xFF), bit32.band(east, 0xFF)
		T.truthy(rTop > rSouth and rSouth > rEast, string.format("bands %d > %d > %d", rTop, rSouth, rEast))
		T.eq(shadowed, east, "a top face in a cast shadow uses the darkest band")
		T.eq(Shading.toon(0xFF0000, 1, 0, 0, 2, 3, 3), 0xFF0000FF, "emissive ignores light")
		for _, c in { top, east, south, shadowed } do
			T.eq(bit32.rshift(c, 24), 255, "opaque")
		end
		restoreDefaults()
	end)

	T.it("no dithering at band edges: a face is one band", function()
		Shading.setPalette(PRIMARIES)
		Shading.setMode("day")
		local function distinct(nx: number, ny: number, nz: number): number
			local seen, n = {}, 0
			for y = 0, 3 do
				for x = 0, 3 do
					local c = Shading.toon(0x00FF00, nx, ny, nz, 1, x, y)
					if not seen[c] then
						seen[c] = true
						n += 1
					end
				end
			end
			return n
		end
		T.eq(distinct(0, 1, 0), 1, "flat lit top")
		T.eq(distinct(1, 0, 0), 1, "facing away")
		-- a normal whose light value sits exactly on the upper band edge (d * 1 + 0.1 * ny = 0.5)
		local s = Shading.SUN
		-- n = a*SUN + b*up-ish: search along the great circle from up toward +X for v == 0.5
		local best, bestErr = nil :: { number }?, math.huge
		for k = 0, 2000 do
			local ang = k / 2000 * math.pi / 2
			local nx, ny = math.sin(ang), math.cos(ang)
			local v = math.max(0, nx * s.x + ny * s.y) + 0.1 * ny
			if math.abs(v - 0.5) < bestErr then
				bestErr = math.abs(v - 0.5)
				best = { nx, ny }
			end
		end
		local b = best :: { number }
		-- (no checker field on a face whose light sits on a band edge: PIXEL_RULES 16, and no flicker on moving rigs)
		T.eq(distinct(b[1], b[2], 0), 1, "edge normal: one band, no checker")
		restoreDefaults()
	end)

	T.it("default palette: Palette.order plus the office themes' colours", function()
		local cols = Shading.defaultColors()
		for i, k in Palette.order do
			T.eq(cols[i], Palette.colors[k], "order first: " .. k)
		end
		local has = {}
		for _, c in cols do
			T.truthy(not has[c], string.format("no duplicates (%06X)", c))
			has[c] = true
		end
		for name, overrides in Palette.themes do
			for key, c in overrides do
				T.truthy(has[c], name .. "." .. key .. " is a LUT colour")
			end
		end
	end)

	T.it("office theme colours keep their own hue on a lit top face", function()
		restoreDefaults()
		local function top(c: number): number
			return unpackRGB(Shading.toon(c, 0, 1, 0, 1, 0, 0))
		end
		for name, overrides in Palette.themes do
			for key, c in overrides do
				T.eq(top(c), c, name .. "." .. key)
			end
		end
		-- an office's two floor tones and its wall and trim stay apart on a lit top face
		for name, o in Palette.themes do
			T.truthy(top(o.floor_a) ~= top(o.floor_b), name .. ": the floor's two tones differ")
			T.truthy(top(o.wall) ~= top(o.wall_trim), name .. ": wall and trim differ")
		end
	end)

	T.it("sky is opaque, a vertical gradient, and darker at night", function()
		restoreDefaults()
		local function lum(c: number): number
			local rgb = unpackRGB(c)
			return bit32.rshift(rgb, 16) + bit32.band(bit32.rshift(rgb, 8), 0xFF) + bit32.band(rgb, 0xFF)
		end
		for y = 0, 9 do
			T.eq(bit32.rshift(Shading.sky(0, y * 10, 100), 24), 255)
		end
		local top, bottom = Shading.sky(0, 0, 100), Shading.sky(0, 99, 100)
		T.truthy(lum(bottom) > lum(top), "lighter toward the horizon")
		Shading.setMode("night")
		T.truthy(lum(Shading.sky(0, 0, 100)) < lum(top), "night sky")
		restoreDefaults()
	end)

	T.it("outline detection", function()
		local f = frame(6, 3, 0xFFFFFFFF)
		-- left 3 columns: id 1 at depth 10; right 3 columns: id 2 at depth 20
		for y = 0, 2 do
			for x = 0, 5 do
				local i = y * 6 + x
				buffer.writeu16(f.id, i * 2, if x < 3 then 1 else 2)
				buffer.writef32(f.depth, i * 4, if x < 3 then 10 else 20)
			end
		end
		Shading.outline(f, 0, 0, 5, 2)
		local ink = Shading.pack(
			bit32.rshift(Palette.colors.ink, 16),
			bit32.band(bit32.rshift(Palette.colors.ink, 8), 0xFF),
			bit32.band(Palette.colors.ink, 0xFF)
		)
		for y = 0, 2 do
			for x = 0, 5 do
				local want = if x == 2 then ink else 0xFFFFFFFF
				T.eq(px(f, x, y), want, string.format("pixel %d,%d", x, y))
			end
		end
	end)

	T.it("outline ignores same id and shallow steps", function()
		local f = frame(4, 1, 0xFF000000)
		local ids = { 1, 1, 2, 3 }
		local depths = { 5, 30, 30.5, 31 } -- same id with a big step; different ids with small steps
		for x = 0, 3 do
			buffer.writeu16(f.id, x * 2, ids[x + 1])
			buffer.writef32(f.depth, x * 4, depths[x + 1])
		end
		Shading.outline(f, -5, -5, 50, 50) -- rect is clipped
		for x = 0, 3 do
			T.eq(px(f, x, 0), 0xFF000000, "no ink at " .. x)
		end
	end)

	T.it("outline depth tolerance (Snapshot passes its own)", function()
		local f = frame(4, 1, 0xFF000000)
		for x = 0, 3 do
			buffer.writeu16(f.id, x * 2, if x < 2 then 1 else 2)
			buffer.writef32(f.depth, x * 4, if x < 2 then 10 else 10.4)
		end
		Shading.outline(f, 0, 0, 3, 0)
		T.eq(px(f, 1, 0), 0xFF000000, "0.4 is shallower than the default 0.75")
		Shading.outline(f, 0, 0, 3, 0, nil, 0.3)
		T.truthy(px(f, 1, 0) ~= 0xFF000000, "but deeper than 0.3: ink")
		T.eq(px(f, 2, 0), 0xFF000000, "the deeper side stays")
	end)

	T.it("day palette: UI pictures ignore the world's mode tint", function()
		Shading.setPalette(Shading.defaultColors())
		Shading.setMode("day")
		local c = Palette.colors.pink or 0xF2A7C3
		local day = Shading.toon(c, 0, 1, 0, 1, 0, 0)
		Shading.setMode("night")
		local nightWorld = Shading.toon(c, 0, 1, 0, 1, 0, 0)
		local nightUi = Shading.toon(c, 0, 1, 0, 1, 0, 0, true)
		Shading.setMode("day")
		T.truthy(nightWorld ~= day, "the world is tinted at night")
		T.eq(nightUi, day, "the day context is not")
	end)

	T.it("blend: on-palette mix, see-through over transparency", function()
		Shading.setPalette(Shading.defaultColors())
		Shading.setMode("day")
		local red = Shading.toon(Palette.colors.berry_red or 0xE0303A, 0, 1, 0, 1, 0, 0)
		local cream = Shading.toon(Palette.colors.cream or 0xFFF3D9, 0, 1, 0, 1, 0, 0)
		T.eq(Shading.blend(red, cream, 1), red, "opaque over: itself")
		T.eq(Shading.blend(red, cream, 0), cream, "invisible over: what is behind")
		local mid = Shading.blend(red, cream, 0.5)
		T.eq(bit32.rshift(mid, 24), 255, "opaque result")
		T.eq(Shading.lut(unpackRGB(mid)), unpackRGB(mid), "on the palette")
		local glass = Shading.blend(red, 0, 0.4)
		T.eq(bit32.rshift(glass, 24), math.floor(0.4 * 255 + 0.5), "over a transparent pixel: alpha = opacity")
		T.eq(bit32.band(glass, 0xFFFFFF), bit32.band(red, 0xFFFFFF), "keeps its colour")
	end)

	T.it("sprites draw, animate and clip", function()
		local f = frame(16, 16, 0)
		Shading.sprite(f, "coin", 8, 8, 0)
		local drawn = 0
		for y = 0, 15 do
			for x = 0, 15 do
				if px(f, x, y) ~= 0 then
					drawn += 1
					T.truthy(math.abs(x - 8) <= 3 and math.abs(y - 8) <= 3, "inside the 7x7 box")
				end
			end
		end
		T.truthy(drawn > 20, "coin has pixels")
		-- another frame of the animation differs
		local g = frame(16, 16, 0)
		Shading.sprite(g, "coin", 8, 8, 2)
		local diff = false
		for i = 0, 255 do
			if buffer.readu32(f.color, i * 4) ~= buffer.readu32(g.color, i * 4) then
				diff = true
			end
		end
		T.truthy(diff, "coin spins")
		-- every kind draws; off-frame positions and unknown kinds are harmless
		for _, kind in { "sparkle", "star", "ghost", "petal", "heart", "perfect", "make" } do
			local h = frame(9, 9, 0)
			Shading.sprite(h, kind, 4, 4, 1)
			local any = false
			for i = 0, 80 do
				if buffer.readu32(h.color, i * 4) ~= 0 then
					any = true
				end
			end
			T.truthy(any, kind)
			Shading.sprite(h, kind, -2, 10, 3)
			Shading.sprite(h, kind, 100, -100, 3)
		end
		local e = frame(4, 4, 0)
		Shading.sprite(e, "nope", 2, 2, 0)
		for i = 0, 15 do
			T.eq(buffer.readu32(e.color, i * 4), 0)
		end
	end)
	T.it("sprites scale by whole layer pixels and report their extent", function()
		local one = frame(32, 32, 0)
		local two = frame(32, 32, 0)
		Shading.sprite(one, "coin", 16, 16, 0)
		Shading.sprite(two, "coin", 16, 16, 0, 2)
		local n1, n2 = 0, 0
		for y = 0, 31 do
			for x = 0, 31 do
				if px(one, x, y) ~= 0 then
					n1 += 1
				end
				if px(two, x, y) ~= 0 then
					n2 += 1
					T.truthy(math.abs(x - 16) <= 7 and math.abs(y - 16) <= 7, "inside the 14x14 box")
				end
			end
		end
		T.eq(n2, n1 * 4, "each sprite pixel becomes 2x2")
		local ex, ey = Shading.spriteExtent("coin")
		T.truthy(ex >= 4 and ey >= 4, "coin extent covers 7x7")
		local gx, gy = Shading.spriteExtent("ghost")
		T.truthy(gy >= gx, "bobbing sprites reserve room for the bob")
		T.deepEq({ Shading.spriteExtent("nope") }, { 0, 0 })
		-- the make puff is the same sprite under both names
		local a, b = frame(16, 16, 0), frame(16, 16, 0)
		Shading.sprite(a, "make", 8, 8, 2)
		Shading.sprite(b, "perfect", 8, 8, 2)
		for i = 0, 255 do
			T.eq(buffer.readu32(a.color, i * 4), buffer.readu32(b.color, i * 4))
		end
	end)

	T.it("outline with a base buffer also removes stale ink", function()
		local f = frame(6, 1, 0xFF0000FF)
		local base = buffer.create(6 * 4)
		for x = 0, 5 do
			buffer.writeu32(base, x * 4, 0xFF00FF00)
			buffer.writeu16(f.id, x * 2, if x < 3 then 1 else 2)
			buffer.writef32(f.depth, x * 4, if x < 3 then 10 else 20)
		end
		Shading.outline(f, 0, 0, 5, 0, base)
		local ink = Shading.pack(
			bit32.rshift(Palette.colors.ink, 16),
			bit32.band(bit32.rshift(Palette.colors.ink, 8), 0xFF),
			bit32.band(Palette.colors.ink, 0xFF)
		)
		for x = 0, 5 do
			T.eq(px(f, x, 0), if x == 2 then ink else 0xFF00FF00, "pixel " .. x)
		end
		-- the edge goes away: re-outlining with the base clears its ink
		for x = 0, 5 do
			buffer.writeu16(f.id, x * 2, 1)
		end
		Shading.outline(f, 0, 0, 5, 0, base)
		T.eq(px(f, 2, 0), 0xFF00FF00, "stale ink removed")
	end)

	T.it("quantised normals round-trip the axes and diagonals", function()
		local seen = {}
		for qx = -1, 1 do
			for qy = -1, 1 do
				for qz = -1, 1 do
					if qx ~= 0 or qy ~= 0 or qz ~= 0 then
						local len = math.sqrt(qx * qx + qy * qy + qz * qz)
						local i = Shading.normalIndex(qx / len, qy / len, qz / len)
						T.truthy(i >= 0 and i <= 26 and i ~= 13, "index " .. i)
						T.truthy(not seen[i], "distinct")
						seen[i] = true
						local x, y, z = Shading.normalVec(i)
						T.near(x, qx / len, 1e-9)
						T.near(y, qy / len, 1e-9)
						T.near(z, qz / len, 1e-9)
					end
				end
			end
		end
		-- a nearly flat normal snaps to its dominant axis
		local x, y, z = Shading.normalVec(Shading.normalIndex(0.2, 0.95, 0.1))
		T.deepEq({ x, y, z }, { 0, 1, 0 })
		local ux, uy, uz = Shading.normalVec(13)
		T.deepEq({ ux, uy, uz }, { 0, 1, 0 }, "13 decodes as up")
	end)
end
