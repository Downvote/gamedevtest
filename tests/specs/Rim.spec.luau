-- tests/specs/Rim.spec.luau (WP8): the player's white outline. Raster.window (a scratch window of the layer that
-- draws exactly where the full camera does) and Shading.rim (the 1 px rim of a silhouette mask: on the model's own
-- edge pixels, the x-ray part dotted where something nearer hides the model, nothing along the picture's edge), then
-- the two together the way PixelRenderer uses them: a rig half hidden behind a counter.
local T = require("../TestKit")
local Raster = require("../../build/luautest/shared/Render/Raster")
local Shading = require("../../build/luautest/shared/Render/Shading")

local ISO_PITCH = 30 -- the live camera (Tuning.CamPitch): 2:1 dimetric
local BACK = 150
local ALPHA = 255 * 16777216
local WHITE, PINK = 0xFFFFFF, 0xFFA7CA
local CW, CP = 0xFF + 0xFF * 256 + 0xFF * 65536 + ALPHA, 0xFF + 0xA7 * 256 + 0xCA * 65536 + ALPHA -- packed
local BG = 0x11 + 0x22 * 256 + 0x33 * 65536 + ALPHA

local function constShade(color: number)
	return function(_rgb: number, _nx: number, _ny: number, _nz: number, _x: number, _y: number): number
		return color
	end
end

local function isoCam(W: number, H: number, K: number): Raster.Cam
	local c = Raster.rotation(45, ISO_PITCH)
	c[1], c[2], c[3] = 0, 1.5, 0
	return Raster.cam(c, 9, W * K, H * K, K, BACK)
end

local function box(x: number, y: number, z: number): { number }
	return { x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1 }
end

local function solid(W: number, H: number, color: number, depth: number): Raster.Frame
	local f = Raster.newFrame(W, H)
	for i = 0, W * H - 1 do
		buffer.writeu32(f.color, i * 4, color)
		buffer.writef32(f.depth, i * 4, depth)
	end
	return f
end

local function px(f: Raster.Frame, x: number, y: number): number
	return buffer.readu32(f.color, (y * f.W + x) * 4)
end

-- a mask window (w x h) covering the pixels where cover(x, y) is true, each at depth d
local function mask(w: number, h: number, d: number, cover: (number, number) -> boolean): Raster.Frame
	local m = Raster.newFrame(w, h)
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if cover(x, y) then
				buffer.writeu16(m.id, (y * w + x) * 2, 40000)
				buffer.writef32(m.depth, (y * w + x) * 4, d)
			end
		end
	end
	return m
end

return function()
	T.it("window: drawing through a window of the layer lands exactly where the full camera draws", function()
		local cam = isoCam(120, 80, 3)
		local parts = {
			{ "Block", box(0.4, 1, -0.3), 1.5, 2, 1 },
			{ "Ball", box(-1.2, 2.2, 0.5), 1.2, 1.2, 1.2 },
			{ "Cylinder", box(1.5, 0.5, 1), 2, 0.8, 0.8 },
			{ "Wedge", box(-0.5, 0.3, 1.8), 1, 0.6, 1.4 },
			{ "Block", box(2.6, 2.4, -1), 0.05, 0.05, 0.05 }, -- sub-pixel: keeps one pixel
		}
		local full = Raster.newFrame(cam.W, cam.H)
		for k, p in parts do
			Raster.drawPart(full, cam, p[1], p[2], p[3], p[4], p[5], 0, 100 + k, constShade(100 + k))
		end
		for _, win in { { 30, 20, 50, 40 }, { 0, 0, 120, 80 }, { 57, 33, 9, 7 }, { 100, 60, 20, 20 } } do
			local x0, y0, w, h = win[1], win[2], win[3], win[4]
			local wc = Raster.window(cam, x0, y0, w, h)
			T.eq(wc.W, w)
			T.eq(wc.H, h)
			local px0, py0, pd0 = Raster.project(cam, 1, 2, 3)
			local px1, py1, pd1 = Raster.project(wc, 1, 2, 3)
			T.near(px1, px0 - x0, 1e-9)
			T.near(py1, py0 - y0, 1e-9)
			T.near(pd1, pd0, 1e-9)
			local ax, ay, az = Raster.origin(cam, x0 + 2, y0 + 3)
			local bx, by, bz = Raster.origin(wc, 2, 3)
			T.near(bx, ax, 1e-9)
			T.near(by, ay, 1e-9)
			T.near(bz, az, 1e-9)
			local part = Raster.newFrame(w, h)
			for k, p in parts do
				Raster.drawPart(part, wc, p[1], p[2], p[3], p[4], p[5], 0, 100 + k, constShade(100 + k))
			end
			local bad = 0
			for y = 0, h - 1 do
				for x = 0, w - 1 do
					local i, j = y * w + x, (y0 + y) * cam.W + x0 + x
					if buffer.readu16(part.id, i * 2) ~= buffer.readu16(full.id, j * 2)
						or buffer.readu32(part.color, i * 4) ~= buffer.readu32(full.color, j * 4)
						or math.abs(buffer.readf32(part.depth, i * 4) - buffer.readf32(full.depth, j * 4)) > 1e-3
					then
						bad += 1
					end
				end
			end
			T.eq(bad, 0, string.format("window %d,%d %dx%d", x0, y0, w, h))
		end
		-- the window draws the same pixels as the full frame does inside it, and something lands in it
		local wc = Raster.window(cam, 30, 20, 50, 40)
		local part = Raster.newFrame(50, 40)
		local n = 0
		for k, p in parts do
			n += Raster.drawPart(part, wc, p[1], p[2], p[3], p[4], p[5], 0, 100 + k, constShade(100 + k))
		end
		T.truthy(n > 100, "the parts are inside the test window")
	end)

	T.it("rim: the silhouette's own edge pixels turn white, the inside and the outside stay", function()
		local f = solid(12, 10, BG, 50)
		-- a 5 x 4 block at mask (2, 1) in a 9 x 6 window placed at frame (1, 2), the model at depth 50 (it is what f shows)
		local m = mask(9, 6, 50, function(x, y)
			return x >= 2 and x <= 6 and y >= 1 and y <= 4
		end)
		local n = Shading.rim(f, m, 1, 2, WHITE, PINK)
		T.eq(n, 14, "the block's border: 5 + 5 + 2 + 2")
		for y = 0, 9 do
			for x = 0, 11 do
				local mx, my = x - 1, y - 2
				local inside = mx >= 2 and mx <= 6 and my >= 1 and my <= 4
				local border = inside and (mx == 2 or mx == 6 or my == 1 or my == 4)
				T.eq(px(f, x, y), if border then CW else BG, string.format("pixel %d,%d", x, y))
			end
		end
	end)

	T.it("rim: one pixel wide parts are all rim; holes get a rim round them", function()
		local f = solid(9, 9, BG, 50)
		-- a ring of 7 x 7 with a 3 x 3 hole, plus a one pixel wide stick along the bottom edge of the picture
		local m = mask(9, 9, 50, function(x, y)
			local ring = x >= 0 and x <= 6 and y >= 0 and y <= 6 and not (x >= 2 and x <= 4 and y >= 2 and y <= 4)
			return ring or (y == 8 and x >= 1)
		end)
		Shading.rim(f, m, 0, 0, WHITE, PINK)
		-- the picture's own edge (x 0, y 0) makes no rim: (0, 3) has covered neighbours and f's edge on its left
		T.eq(px(f, 0, 3), BG)
		T.eq(px(f, 3, 0), BG)
		T.eq(px(f, 0, 0), BG)
		-- round the hole and the outer border inside the picture
		T.eq(px(f, 3, 1), CW)
		T.eq(px(f, 1, 3), CW)
		T.eq(px(f, 5, 3), CW)
		T.eq(px(f, 3, 5), CW)
		T.eq(px(f, 6, 3), CW)
		T.eq(px(f, 3, 6), CW)
		T.eq(px(f, 1, 1), BG, "covered, its 4 neighbours too")
		-- the stick: every pixel is rim (the row above it is uncovered), though f's edge runs right below it
		for x = 1, 8 do
			T.eq(px(f, x, 8), CW, "stick " .. x)
		end
		T.eq(px(f, 0, 8), BG)
		-- the hole itself stays
		T.eq(px(f, 3, 3), BG)
	end)

	T.it("rim: a window edge inside the picture is an edge; the picture's own edge is not", function()
		local f = solid(10, 6, BG, 50)
		-- fully covered 4 x 4 window at frame (6, 2): its right and bottom sides are f's edges
		local m = mask(4, 4, 50, function()
			return true
		end)
		local n = Shading.rim(f, m, 6, 2, WHITE, PINK)
		T.eq(n, 4 + 3, "left column and top row only")
		T.eq(px(f, 6, 2), CW)
		T.eq(px(f, 9, 2), CW)
		T.eq(px(f, 6, 5), CW)
		T.eq(px(f, 9, 5), BG)
		T.eq(px(f, 8, 4), BG)
		-- a window hanging off the picture: clipped, with a rim only along its sides inside the picture
		local g = solid(4, 4, BG, 50)
		local n2 = Shading.rim(g, m, -2, -2, WHITE, PINK)
		T.eq(n2, 3)
		T.eq(px(g, 0, 0), BG)
		T.eq(px(g, 1, 0), CW)
		T.eq(px(g, 0, 1), CW)
		T.eq(px(g, 1, 1), CW)
		T.eq(px(g, 2, 2), BG)
		g = solid(4, 4, BG, 50)
		local n3 = Shading.rim(g, m, 2, 2, WHITE, PINK)
		T.eq(n3, 3)
		T.eq(px(g, 2, 2), CW)
		T.eq(px(g, 3, 2), CW)
		T.eq(px(g, 2, 3), CW)
		T.eq(px(g, 3, 3), BG)
	end)

	T.it("rim: x-ray where something nearer hides the model, dotted on request", function()
		-- the model (depth 50) is hidden below row 4 by something at depth 40; rows 0..3 show the model itself
		local function scene(): Raster.Frame
			local f = solid(10, 10, BG, 50)
			for y = 4, 9 do
				for x = 0, 9 do
					buffer.writef32(f.depth, (y * 10 + x) * 4, 40)
				end
			end
			return f
		end
		local m = mask(10, 10, 50, function(x, y)
			return x >= 2 and x <= 7 and y >= 1 and y <= 8
		end)
		local f = scene()
		local n = Shading.rim(f, m, 0, 0, WHITE, PINK)
		T.eq(n, 24)
		T.eq(px(f, 2, 2), CW, "visible edge")
		T.eq(px(f, 2, 3), CW)
		T.eq(px(f, 2, 4), CP, "hidden edge: x-ray colour")
		T.eq(px(f, 5, 8), CP)
		T.eq(px(f, 4, 1), CW)
		-- a nearer surface within the tolerance still counts as the model (e.g. float noise of the same surface)
		local near = scene()
		for x = 0, 9 do
			buffer.writef32(near.depth, (1 * 10 + x) * 4, 49.98)
		end
		Shading.rim(near, m, 0, 0, WHITE, PINK)
		T.eq(px(near, 4, 1), CW)
		-- dotted: the hidden part on every other pixel along the line (a flat stretch by its column, an upright one by
		-- its row, on the global grid), the visible part solid
		local d = scene()
		local nd = Shading.rim(d, m, 0, 0, WHITE, PINK, nil, true)
		T.truthy(nd < n and nd > 10, "fewer pixels")
		for y = 1, 8 do
			for x = 2, 7 do
				local border = x == 2 or x == 7 or y == 1 or y == 8
				local want = BG
				if border then
					if y <= 3 then
						want = CW
					elseif (if y == 1 or y == 8 then x % 2 == 0 else y % 2 == 0) then
						want = CP
					end
				end
				T.eq(px(d, x, y), want, string.format("dotted %d,%d", x, y))
			end
		end
		-- the rhythm is on the global grid: f's pixel (0, 0) at global (1, 1) flips both parities
		local g = scene()
		Shading.rim(g, m, 0, 0, WHITE, PINK, nil, true, 1, 1)
		T.eq(px(g, 2, 4), BG, "the left edge's row 4 is global row 5: off")
		T.eq(px(g, 2, 5), CP, "global row 6: on")
		T.eq(px(g, 3, 8), CP, "the bottom edge's column 3 is global column 4: on")
		T.eq(px(g, 4, 8), BG)
		-- a larger tolerance makes the hidden part count as visible
		local t = scene()
		Shading.rim(t, m, 0, 0, WHITE, PINK, 20)
		T.eq(px(t, 2, 6), CW)
	end)

	T.it("rim on 2:1 edges: one pixel a column, solid where seen, dotted one on one off where hidden", function()
		-- a box's top face on the 2:1 grid (a = 8, K = 1): its silhouette mask, then f with something nearer over the
		-- bottom half (the x-ray part)
		local rot = Raster.rotation(45, 30)
		local g = { a = 8, q = 8 * math.sqrt(2), phX = 0, phY = 0, l = 0, px = -40, py = -40 }
		local cam = Raster.gridCam(rot, g, 80, 80, 1, BACK)
		local m = Raster.newFrame(cam.W, cam.H)
		Raster.drawBox(m, cam, box(0, 0.5, 0), 4, 1, 4, 0, 40000, constShade(0))
		local f = Raster.newFrame(cam.W, cam.H)
		for j = 0, cam.H - 1 do
			for i = 0, cam.W - 1 do
				local o = (j * cam.W + i) * 4
				buffer.writeu32(f.color, o, BG)
				local md = buffer.readf32(m.depth, o)
				buffer.writef32(f.depth, o, if j >= 40 then md - 5 else md)
			end
		end
		Shading.rim(f, m, 0, 0, WHITE, PINK, nil, true, cam.gx, cam.gy)
		-- per column: the topmost covered pixel (on the top face's back edges) and the bottommost one (the front)
		local tops, bottoms = 0, 0
		local hiddenOn, hiddenOff = 0, 0
		for i = 0, cam.W - 1 do
			local first, last = -1, -1
			for j = 0, cam.H - 1 do
				if buffer.readu16(m.id, (j * cam.W + i) * 2) ~= 0 then
					if first < 0 then
						first = j
					end
					last = j
				end
			end
			if first >= 0 then
				T.eq(px(f, i, first), CW, "the seen top edge is solid white at column " .. i)
				tops += 1
				-- the hidden bottom edge (rows 40 and down): every other column of the global grid
				if last >= 40 and buffer.readu16(m.id, ((last - 1) * cam.W + i) * 2) ~= 0 then
					local c = px(f, i, last)
					local on = (i + cam.gx) % 2 == 0
					if on then
						T.eq(c, CP, "x-ray dot at column " .. i)
						hiddenOn += 1
					else
						T.eq(c, BG, "x-ray gap at column " .. i)
						hiddenOff += 1
					end
					bottoms += 1
				end
				-- one pixel a column along the 2:1 edge: the one under the top edge pixel is inside the face, not rim
				-- (where the outline turns down the box's upright sides it runs a column, as it should)
				local function cov(x: number, y: number): boolean
					return x >= 0 and x < cam.W and y >= 0 and y < cam.H and buffer.readu16(m.id, (y * cam.W + x) * 2) ~= 0
				end
				if last > first + 1 and cov(i - 1, first + 1) and cov(i + 1, first + 1) and cov(i, first + 2) then
					T.eq(px(f, i, first + 1), BG, "1 px line weight at column " .. i)
				end
			end
		end
		T.truthy(tops > 50, "the top edges run across (" .. tops .. ")")
		T.truthy(hiddenOn > 10 and math.abs(hiddenOn - hiddenOff) <= 2, string.format("one on, one off along the hidden 2:1 edges (%d / %d)", hiddenOn, hiddenOff))
	end)

	T.it("rim through a window: a figure half behind a counter gets a solid rim above it, dotted below", function()
		local K = 3
		local cam = isoCam(90, 70, K)
		-- the scene: a counter block in front (toward the camera, +x +z), the figure behind it
		local f = Raster.newFrame(cam.W, cam.H)
		local counter = box(1.6, 0.6, 1.6)
		Raster.drawBox(f, cam, counter, 1, 1.2, 4, 0, 1, constShade(BG))
		local figure = { { "Block", box(0, 1.2, 0), 1, 2.4, 1 }, { "Ball", box(0, 3, 0), 1.6, 1.6, 1.6 } }
		local x0, y0, x1, y1 = math.huge, math.huge, -1, -1
		for k, p in figure do
			Raster.drawPart(f, cam, p[1], p[2], p[3], p[4], p[5], 0, 40000 + k, constShade(0xFF445566))
			local a, b, c, d = Raster.boxRect(cam, p[2], p[3], p[4], p[5])
			if a and b and c and d then
				x0, y0, x1, y1 = math.min(x0, a), math.min(y0, b), math.max(x1, c), math.max(y1, d)
			end
		end
		T.truthy(x1 > x0 and y1 > y0, "the figure is on screen")
		-- the mask: the figure alone, flat, in a window of its rect (PixelRenderer's drawRim)
		local w, h = x1 - x0 + 1, y1 - y0 + 1
		local wc = Raster.window(cam, x0, y0, w, h)
		local m = Raster.newFrame(w, h)
		for k, p in figure do
			Raster.drawPart(m, wc, p[1], p[2], p[3], p[4], p[5], 0, 40000 + k, constShade(0))
		end
		local before = buffer.create(cam.W * cam.H * 4)
		buffer.copy(before, 0, f.color)
		Shading.rim(f, m, x0, y0, WHITE, PINK, nil, true)
		local white, pink, hiddenWhite, other = 0, 0, 0, 0
		for y = 0, cam.H - 1 do
			for x = 0, cam.W - 1 do
				local i = y * cam.W + x
				local c = buffer.readu32(f.color, i * 4)
				if c ~= buffer.readu32(before, i * 4) then
					local mx, my = x - x0, y - y0
					local inMask = mx >= 0 and my >= 0 and mx < w and my < h and buffer.readu16(m.id, (my * w + mx) * 2) ~= 0
					local own = buffer.readu16(f.id, i * 2) >= 40000
					if not inMask then
						other += 1
					elseif c == CW then
						white += 1
						if not own then
							hiddenWhite += 1
						end
					elseif c == CP then
						pink += 1
						-- dotted along the line: by the column where the open side is above or below, else by the row
						local function open(dx: number, dy: number): boolean
							local ax, ay = mx + dx, my + dy
							return ax < 0 or ay < 0 or ax >= w or ay >= h or buffer.readu16(m.id, (ay * w + ax) * 2) == 0
						end
						local openV = open(0, -1) or open(0, 1)
						local on = if openV then x % 2 == 0 else y % 2 == 0
						T.truthy(not own and on, "x-ray only where the counter hides the figure, dotted")
					else
						other += 1
					end
				end
			end
		end
		T.eq(other, 0, "nothing outside the silhouette changes")
		T.eq(hiddenWhite, 0, "white only where the figure itself is seen")
		T.truthy(white > 20, "a visible rim (" .. white .. ")")
		T.truthy(pink > 3, "an x-ray rim behind the counter (" .. pink .. ")")
	end)
end
