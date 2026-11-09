--!strict
-- The microgames' backdrops (GAME_DESIGN 5, 12; docs/ARCHITECTURE.md 10.8): a small pixel-art scene behind each idea's
-- microgame, drawn on the grid from 1 px rects and sprites (no pixel bigger than the grid's): Action's night city,
-- Racing's road, Cooking's kitchen tiles, Space's stars, Ocean's water and bubbles, Music's stage... Some move: a
-- scene returns an update(t, pace?) the runner calls each frame (pace: the engine's scroll speed, px/s, for Racing's
-- road). Everything sits under the game (ZIndex 4-6).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local _ = ReplicatedStorage

local Types = require(ReplicatedStorage.Shared.Types)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

local Scenes = {}

type Update = (t: number, pace: number?) -> ()

local function hex(c: number): Color3
	return UIKit.hex(c)
end

local function box(p: Instance, x: number, y: number, w: number, h: number, c: number, z: number?, a: number?): Frame
	local r = UIKit.rect(p, UDim2.fromOffset(math.max(0, math.floor(w)), math.max(0, math.floor(h))), UDim2.fromOffset(math.floor(x), math.floor(y)), hex(c), z or 4)
	r.Name = "Bg"
	r.Active = false
	if a then
		r.BackgroundTransparency = 1 - a
	end
	return r
end

-- Horizontal bands from the top: { { height, colour } ... } (the last fills to the bottom), with a 1 px dither row
-- between two bands (every other pixel of the lower colour), so a sky's gradient has no hard steps.
local function bands(p: Instance, w: number, h: number, list: { { number } }, dither: boolean?)
	local y = 0
	for i, b in list do
		local hh = if i == #list then h - y else b[1]
		box(p, 0, y, w, hh, b[2], 4)
		if dither and i > 1 and y > 0 then
			local prev = list[i - 1][2]
			for x = 0, w - 1, 2 do
				box(p, x, y, 1, 1, prev, 4)
			end
			for x = 1, w - 1, 2 do
				box(p, x, y - 1, 1, 1, b[2], 4)
			end
		end
		y += hh
	end
end

-- A filled circle on the grid (row spans), edge pixels in `edge` (anti-aliasing against the sky).
local function disc(p: Instance, cx: number, cy: number, r: number, fill: number, edge: number?, z: number?)
	for dy = -r, r do
		local half = math.sqrt(math.max(0, r * r - dy * dy))
		local hw = math.floor(half + 0.5)
		if hw > 0 then
			box(p, cx - hw, cy + dy, hw * 2, 1, fill, z or 4)
			if edge then
				box(p, cx - hw - 1, cy + dy, 1, 1, edge, z or 4)
				box(p, cx + hw, cy + dy, 1, 1, edge, z or 4)
			end
		end
	end
end

local function stars(p: Instance, w: number, h: number, rng: Types.Rng, n: number, maxY: number): Update
	local twinkle: { GuiObject } = {}
	for i = 1, n do
		local x, y = rng:int(1, w - 2), rng:int(1, maxY)
		if i % 6 == 0 then
			table.insert(twinkle, PixelSprites.image(p, "star", UDim2.fromOffset(x - 2, y - 2), 5))
		else
			box(p, x, y, 1, 1, if i % 3 == 0 then 0xC9F2FF else 0xFFFFFF, 5, if i % 2 == 0 then 1 else 0.6)
		end
	end
	return function(t: number)
		for i, s in twinkle do
			s.Visible = math.floor(t * 2 + i * 0.7) % 3 ~= 0
		end
	end
end

------------------------------------------------------------------ the scenes, by Data/Ideas variant
local BUILD: { [string]: (p: Frame, w: number, h: number, rng: Types.Rng) -> Update? } = {}

BUILD.blocks = function(p, w, h, rng)
	bands(p, w, h, { { 30, 0x1F2552 }, { 30, 0x2C2F6B }, { 1, 0x46407E } }, true)
	local up = stars(p, w, h, rng, 18, 40)
	local x = 0
	while x < w do
		local bw, bh = rng:int(14, 30), rng:int(22, 46)
		box(p, x, h - bh, bw, bh, 0x2B1E2E, 5)
		box(p, x, h - bh, bw, 1, 0x463B5C, 5)
		for wy = h - bh + 4, h - 6, 6 do
			for wx = x + 3, x + bw - 4, 5 do
				if rng:chance(0.45) then
					box(p, wx, wy, 2, 2, 0xFFCB30, 5, 0.85)
				end
			end
		end
		x += bw + 2
	end
	return up
end

BUILD.race = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0x5E8A3C, 4)
	local roadW = math.floor(w * 0.62)
	local rx = math.floor((w - roadW) / 2)
	box(p, rx, 0, roadW, h, 0x625E6B, 4)
	box(p, rx - 1, 0, 1, h, 0x2B1E2E, 4)
	box(p, rx + roadW, 0, 1, h, 0x2B1E2E, 4)
	local kerbs: { Frame } = {}
	for i = 0, math.ceil(h / 8) + 1 do
		local c = if i % 2 == 0 then 0xE8465B else 0xFFFFFF
		table.insert(kerbs, box(p, rx - 4, i * 8, 3, 8, c, 5))
		table.insert(kerbs, box(p, rx + roadW + 1, i * 8, 3, 8, c, 5))
	end
	local grass: { Frame } = {}
	for i = 0, math.ceil(h / 16) + 1 do
		table.insert(grass, box(p, 0, i * 16, rx - 5, 8, 0x6CA046, 4))
		table.insert(grass, box(p, rx + roadW + 5, i * 16, w - rx - roadW - 5, 8, 0x6CA046, 4))
	end
	return function(t: number, pace: number?)
		local off = math.floor(t * (pace or 90)) % 16
		for i, k in kerbs do
			local row = (i - 1) // 2
			k.Position = UDim2.fromOffset(k.Position.X.Offset, row * 8 + off - 16)
		end
		for i, g in grass do
			local row = (i - 1) // 2
			g.Position = UDim2.fromOffset(g.Position.X.Offset, row * 16 + off - 16)
		end
	end
end

BUILD.flip = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0xFFF3D9, 4)
	for y = 7, h, 8 do
		box(p, 0, y, w, 1, 0xEAD9BF, 4)
	end
	for x = 7, w, 8 do
		box(p, x, 0, 1, h, 0xEAD9BF, 4)
	end
	-- a window with the sky and a cross of bars
	local wx, wy, ww, wh = w - 58, 32, 40, 30
	box(p, wx, wy, ww, wh, 0x2B1E2E, 4)
	box(p, wx + 1, wy + 1, ww - 2, wh - 2, 0x9FD8F2, 4)
	box(p, wx + 1, wy + 1, ww - 2, 9, 0xC2EAF8, 4)
	for x = wx + 1, wx + ww - 2, 2 do
		box(p, x, wy + 10, 1, 1, 0xC2EAF8, 4)
	end
	box(p, wx + 6, wy + 16, 10, 3, 0xFFFFFF, 4)
	box(p, wx + 8, wy + 14, 5, 2, 0xFFFFFF, 4)
	box(p, wx + math.floor(ww / 2), wy + 1, 1, wh - 2, 0xFFF3D9, 5)
	box(p, wx + 1, wy + math.floor(wh / 2), ww - 2, 1, 0xFFF3D9, 5)
	box(p, wx - 2, wy + wh, ww + 4, 2, 0x8B5B3D, 5)
	box(p, wx - 2, wy + wh, ww + 4, 1, 0xC88D5C, 5)
	-- a shelf of jars (1 px ink outlines, a light edge each)
	local sx, sy = 16, 40
	box(p, sx, sy, 64, 2, 0x8B5B3D, 5)
	box(p, sx, sy, 64, 1, 0xC88D5C, 5)
	box(p, sx, sy + 2, 64, 1, 0xEAD9BF, 4)
	for i, c in { 0xE8465B, 0x6CC06A, 0xFFCB30, 0xA77DD7 } do
		local jx = sx + 4 + (i - 1) * 15
		local jh = 9 + (i % 2) * 2
		box(p, jx, sy - jh, 9, jh, 0x2B1E2E, 5)
		box(p, jx + 1, sy - jh + 3, 7, jh - 4, c, 5)
		box(p, jx + 1, sy - jh + 3, 1, jh - 4, 0xFFFFFF, 5, 0.5)
		box(p, jx + 1, sy - jh + 1, 7, 2, 0xC88D5C, 5)
	end
	-- the counter
	box(p, 0, h - 24, w, 24, 0xC88D5C, 5)
	box(p, 0, h - 24, w, 1, 0xEDC293, 5)
	box(p, 0, h - 25, w, 1, 0x2B1E2E, 5)
	box(p, 0, h - 14, w, 1, 0x8B5B3D, 5)
	-- the stove's knobs on the counter's front
	for i = -1, 1 do
		local kx = math.floor(w / 2) + i * 8 - 1
		box(p, kx, h - 20, 3, 3, 0x2B1E2E, 5)
		box(p, kx + 1, h - 20, 1, 1, 0xAEB8C5, 5)
	end
	return nil
end

BUILD.kick = function(p, w, h, rng)
	bands(p, w, h, { { 18, 0x9FD8F2 }, { 1, 0xC2EAF8 } }, true)
	box(p, 0, 18, w, 22, 0x463B5C, 4)
	for x = 1, w - 2, 3 do
		for y = 20, 38, 3 do
			box(p, x, y, 1, 1, ({ 0xE8465B, 0xFFCB30, 0x70A9EA, 0xFFFFFF, 0x7DC971 })[rng:int(1, 5)], 5)
		end
	end
	box(p, 0, 40, w, h - 40, 0x6CC06A, 4)
	for x = 0, w, 32 do
		box(p, x, 40, 16, h - 40, 0x5BAF5A, 4)
	end
	box(p, 0, 40, w, 1, 0xFFFFFF, 5)
	return nil
end

BUILD.strike = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0x3E4554, 4)
	for y = 0, h - 20, 6 do
		box(p, 0, y + 5, w, 1, 0x2B1E2E, 4)
		local shift = if (y // 6) % 2 == 0 then 0 else 6
		for x = shift, w, 12 do
			box(p, x, y, 1, 5, 0x2B1E2E, 4)
			box(p, x + 1, y, 10, 1, 0x6E7888, 4)
		end
	end
	box(p, 0, h - 20, w, 20, 0x4A2E1E, 5)
	box(p, 0, h - 20, w, 1, 0x8B5B3D, 5)
	local flames: { Frame } = {}
	for _, x in { 16, w - 20 } do
		box(p, x + 1, 26, 2, 10, 0x8B5B3D, 5)
		table.insert(flames, box(p, x, 21, 4, 5, 0xFFA553, 5))
		table.insert(flames, box(p, x + 1, 22, 2, 3, 0xFFF0A0, 5))
	end
	return function(t: number)
		for i, f in flames do
			f.Position = UDim2.fromOffset(f.Position.X.Offset, (if i % 2 == 1 then 21 else 22) - (math.floor(t * 8 + i) % 2))
		end
	end
end

BUILD.pet = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0xF6D2C5, 4)
	for y = 4, h - 30, 8 do
		for x = (y // 8) % 2 * 4 + 2, w, 8 do
			box(p, x, y, 1, 1, 0xE8A898, 4)
		end
	end
	box(p, 0, h - 26, w, 26, 0xC88D5C, 5)
	box(p, 0, h - 26, w, 1, 0x8B5B3D, 5)
	local rw = math.floor(w * 0.7)
	box(p, math.floor((w - rw) / 2), h - 18, rw, 10, 0xE86F6F, 5)
	box(p, math.floor((w - rw) / 2) + 2, h - 16, rw - 4, 1, 0xFFA7CA, 5)
	return nil
end

BUILD.space = function(p, w, h, rng)
	bands(p, w, h, { { 40, 0x0E0B1F }, { 40, 0x1A1440 }, { 1, 0x24346E } }, true)
	local up = stars(p, w, h, rng, 40, h - 4)
	disc(p, w - 34, 26, 12, 0x6A4BA8, 0x3E2A66, 4)
	box(p, w - 44, 20, 8, 2, 0xA77DD7, 4)
	box(p, w - 40, 30, 12, 1, 0x3E2A66, 4)
	return up
end

BUILD.water = function(p, w, h, _rng)
	bands(p, w, h, { { 24, 0x9FD8F2 }, { 1, 0xC2EAF8 } }, true)
	disc(p, 24, 12, 7, 0xFFE172, 0xFFCB30, 4)
	box(p, 0, 26, w, h - 26, 0x8B5B3D, 4)
	for y = 30, h, 7 do
		box(p, 0, y, w, 1, 0x6E4630, 4)
		box(p, 0, y + 1, w, 1, 0xA06B48, 4)
	end
	return nil
end

BUILD.zombie = function(p, w, h, rng)
	-- a night sky over a graveyard: the ground is most of the scene (the holes are dug in it)
	local horizon = 34
	bands(p, w, horizon, { { 16, 0x1F1A33 }, { 1, 0x2E2550 } }, true)
	stars(p, w, h, rng, 10, horizon - 6)
	disc(p, 30, 16, 8, 0xFFF3D9, 0xEAD9BF, 4)
	-- a crooked fence and tombstones on the horizon
	for x = 0, w - 1, 6 do
		box(p, x + 2, horizon - 6 + (x // 6) % 2, 1, 6, 0x2B1E2E, 4)
	end
	box(p, 0, horizon - 4, w, 1, 0x2B1E2E, 4)
	for x = 14, w - 14, 44 do
		local hh = rng:int(7, 10)
		box(p, x - 1, horizon - hh - 1, 10, hh + 1, 0x2B1E2E, 5)
		box(p, x, horizon - hh, 8, hh, 0x6E7888, 5)
		box(p, x, horizon - hh, 1, hh, 0xAEB8C5, 5)
		box(p, x + 3, horizon - hh + 2, 2, 5, 0x3E4554, 5)
		box(p, x + 2, horizon - hh + 3, 4, 1, 0x3E4554, 5)
	end
	box(p, 0, horizon, w, h - horizon, 0x24563A, 4)
	box(p, 0, horizon, w, 1, 0x3F8F4F, 4)
	box(p, 0, horizon + 1, w, 1, 0x2B6B45, 4)
	for _ = 1, 40 do
		box(p, rng:int(0, w - 2), rng:int(horizon + 3, h - 2), 1, 2, 0x3F8F4F, 4)
	end
	return nil
end

BUILD.match = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0xFFFDF4, 4)
	for y = 5, h, 6 do
		box(p, 0, y, w, 1, 0xD8E6F5, 4)
	end
	for x = 5, w, 6 do
		box(p, x, 0, 1, h, 0xD8E6F5, 4)
	end
	box(p, 14, 0, 1, h, 0xFF9AA8, 4)
	return nil
end

BUILD.answer = function(p, w, h, rng)
	box(p, 0, 0, w, h, 0x8B5B3D, 4)
	box(p, 4, 3, w - 8, h - 14, 0x2F5A3E, 4)
	box(p, 4, 3, w - 8, 1, 0x24563A, 4)
	box(p, 4, h - 11, w - 8, 3, 0xC88D5C, 5)
	box(p, 4, h - 11, w - 8, 1, 0xEDC293, 5)
	for _ = 1, 10 do
		box(p, rng:int(8, w - 20), rng:int(6, h - 20), rng:int(3, 9), 1, 0x8FB89A, 4, 0.5)
	end
	box(p, w - 30, h - 10, 6, 2, 0xFFFFFF, 5)
	return nil
end

BUILD.count = function(p, w, h, rng)
	box(p, 0, 0, w, h, 0xEDD9AA, 4)
	for y = 7, h, 10 do
		box(p, 0, y, w, 1, 0xD9C08E, 4)
	end
	for x = 9, w, 10 do
		box(p, x, 0, 1, h, 0xD9C08E, 4)
	end
	local y = rng:int(10, 30)
	for x = 0, w - 1, 2 do
		y = math.clamp(y + rng:int(-1, 1), 6, h - 40)
		box(p, x, y, 2, 2, 0x70A9EA, 4)
	end
	return nil
end

BUILD.spot = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0x4A2E1E, 4)
	for y = 0, h, 9 do
		box(p, 0, y, w, 1, 0x3A2416, 4)
	end
	box(p, 6, 10, w - 12, h - 18, 0xFFF3D9, 4)
	box(p, 6, 10, w - 12, 1, 0xFFFDF4, 4)
	box(p, 7, h - 8, w - 12, 1, 0x2B1E2E, 4, 0.4)
	return nil
end

BUILD.cast = function(p, w, h, rng)
	bands(p, w, h, { { 30, 0x2A1A4A }, { 30, 0x3E2A66 }, { 1, 0x5A3E8A } }, true)
	local up = stars(p, w, h, rng, 26, h - 30)
	disc(p, w - 26, 20, 8, 0xFFF0A0, nil, 4)
	disc(p, w - 22, 17, 7, 0x2A1A4A, nil, 4)
	return up
end

BUILD.program = function(p, w, h, rng)
	box(p, 0, 0, w, h, 0x1E4630, 4)
	for _ = 1, 14 do
		local x, y = rng:int(4, w - 30), rng:int(4, h - 10)
		local len = rng:int(12, 40)
		box(p, x, y, len, 1, 0xC8A050, 4, 0.7)
		box(p, x + len - 1, y, 1, rng:int(4, 14), 0xC8A050, 4, 0.7)
		box(p, x - 1, y - 1, 3, 3, 0xD9C08E, 4)
	end
	for x = 0, w, 4 do
		box(p, x, 0, 1, 1, 0x2E6A48, 4)
	end
	return nil
end

BUILD.simon = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0x1A1430, 4)
	box(p, 0, 0, 16, h, 0xB0304A, 5)
	box(p, w - 16, 0, 16, h, 0xB0304A, 5)
	for x = 2, 14, 4 do
		box(p, x, 0, 1, h, 0x6E1F33, 5)
		box(p, w - 16 + x, 0, 1, h, 0x6E1F33, 5)
	end
	local beams: { Frame } = {}
	for k, cx in { math.floor(w * 0.3), math.floor(w * 0.7) } do
		for y = 0, h - 12, 2 do
			local half = 3 + math.floor(y / 4)
			table.insert(beams, box(p, cx - half, y, half * 2, 2, if k == 1 then 0xFFF0A0 else 0xC9F2FF, 4, 0.12))
		end
	end
	box(p, 0, h - 10, w, 10, 0x4A2E1E, 5)
	box(p, 0, h - 10, w, 1, 0xC88D5C, 5)
	return function(t: number)
		local on = math.floor(t * 2) % 2 == 0
		for i, b in beams do
			b.BackgroundTransparency = if (i % 2 == 0) == on then 0.86 else 0.92
		end
	end
end

BUILD.loot = function(p, w, h, _rng)
	bands(p, w, h, { { 22, 0x9FD8F2 }, { 1, 0xC2EAF8 } }, true)
	box(p, 0, 22, w, 14, 0x3FA6C4, 4)
	box(p, 0, 22, w, 1, 0xC9F2FF, 4)
	box(p, 0, 36, w, h - 36, 0xF2D49B, 4)
	box(p, 0, 36, w, 1, 0xFFF3D9, 4)
	for x = 4, w, 11 do
		box(p, x, 44 + (x * 7) % 30, 2, 1, 0xD9B577, 4)
	end
	return nil
end

BUILD.fish = function(p, w, h, rng)
	bands(p, w, h, { { 20, 0x6FD3F2 }, { 24, 0x3FA6C4 }, { 30, 0x2F7FB5 }, { 1, 0x24346E } }, true)
	type Bubble = { f: Frame, x: number, y: number, v: number }
	local bubbles: { Bubble } = {}
	for _ = 1, 8 do
		local b = Instance.new("Frame")
		b.Name = "Bubble"
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromOffset(3, 3)
		b.ZIndex = 5
		box(b, 1, 0, 1, 1, 0xC9F2FF, 5)
		box(b, 0, 1, 1, 1, 0xC9F2FF, 5)
		box(b, 2, 1, 1, 1, 0xC9F2FF, 5)
		box(b, 1, 2, 1, 1, 0xC9F2FF, 5)
		b.Parent = p
		table.insert(bubbles, { f = b, x = rng:int(4, w - 6), y = rng:int(0, h), v = 8 + rng:next() * 10 })
	end
	for x = 0, w, 5 do
		box(p, x, h - 6 + (x // 5) % 2, 3, 6, 0x24346E, 4)
	end
	return function(t: number)
		for _, b in bubbles do
			local y = (b.y - t * b.v) % (h + 6) - 3
			b.f.Position = UDim2.fromOffset(b.x + (math.floor(t * 2 + b.x) % 2), math.floor(y))
		end
	end
end

BUILD.leap = function(p, w, h, rng)
	bands(p, w, h, { { 24, 0x9FD8F2 }, { 24, 0xB5E4F7 }, { 1, 0xC9F2FF } }, true)
	for _ = 1, 3 do
		local cx, cy = rng:int(10, w - 40), rng:int(4, 24)
		box(p, cx, cy + 3, 26, 4, 0xFFFFFF, 4)
		box(p, cx + 5, cy, 12, 3, 0xFFFFFF, 4)
		box(p, cx, cy + 7, 26, 1, 0xC2EAF8, 4)
	end
	for x = 0, w, 2 do
		local hh = 14 + math.floor(math.sin(x / 19) * 6 + math.sin(x / 7) * 2)
		box(p, x, h - 22 - hh, 2, hh, 0x6FAE57, 4)
	end
	box(p, 0, h - 22, w, 22, 0x8ACB6C, 4)
	box(p, 0, h - 12, w, 12, 0x8B5B3D, 4)
	return nil
end

BUILD.dino = function(p, w, h, rng)
	bands(p, w, h, { { 20, 0xFFA553 }, { 20, 0xFFC27A }, { 1, 0xFFE0A8 } }, true)
	disc(p, w - 30, 24, 10, 0xFFF0A0, 0xFFCB30, 4)
	local x = 0
	while x < w do
		local mw, mh = rng:int(20, 40), rng:int(10, 24)
		box(p, x, h - 22 - mh, mw, mh, 0xC86A3A, 4)
		box(p, x, h - 22 - mh, mw, 1, 0xE8925A, 4)
		x += mw + rng:int(10, 30)
	end
	box(p, 0, h - 22, w, 22, 0xF2C27A, 4)
	for xx = 3, w, 9 do
		box(p, xx, h - 14 + (xx * 3) % 8, 2, 1, 0xD9A55A, 4)
	end
	return nil
end

BUILD.beat = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0x1A1430, 4)
	local tiles: { Frame } = {}
	local cols = { 0xE8465B, 0xFFCB30, 0x70A9EA, 0x7DC971, 0xA77DD7 }
	for y = 0, h - 1, 12 do
		for x = 0, w - 1, 12 do
			local t = box(p, x, y, 11, 11, cols[((x // 12) + (y // 12)) % #cols + 1], 4, 0.18)
			table.insert(tiles, t)
		end
	end
	return function(t: number)
		local k = math.floor(t * 2)
		for i, tile in tiles do
			tile.BackgroundTransparency = if (i + k) % 3 == 0 then 0.72 else 0.9
		end
	end
end

BUILD.fruit = function(p, w, h, _rng)
	box(p, 0, 0, w, h, 0xFFF3D9, 4)
	for x = 0, w, 22 do
		box(p, x, 0, 2, h - 20, 0x8B5B3D, 4)
	end
	for y = 14, h - 20, 16 do
		box(p, 0, y, w, 1, 0xC88D5C, 4)
	end
	box(p, 0, h - 20, w, 20, 0xC88D5C, 5)
	for x = 0, w, 30 do
		box(p, x, h - 20, 1, 20, 0x8B5B3D, 5)
	end
	box(p, 0, h - 20, w, 1, 0xEDC293, 5)
	return nil
end

BUILD.ghost = function(p, w, h, rng)
	box(p, 0, 0, w, h, 0x2A1F3D, 4)
	for x = 0, w, 10 do
		box(p, x, 0, 4, h - 24, 0x33264A, 4)
	end
	box(p, 20, 10, 22, 26, 0x1F2552, 4)
	box(p, 30, 10, 1, 26, 0x2B1E2E, 4)
	box(p, 20, 22, 22, 1, 0x2B1E2E, 4)
	disc(p, 26, 16, 3, 0xFFF3D9, nil, 4)
	box(p, 0, h - 24, w, 24, 0x4A2E1E, 5)
	for x = 0, w, 16 do
		box(p, x, h - 24, 1, 24, 0x3A2416, 5)
	end
	box(p, 0, h - 24, w, 1, 0x6E4630, 5)
	local _ = rng
	return nil
end

BUILD.tower = function(p, w, h, rng)
	bands(p, w, h, { { 26, 0x9FD8F2 }, { 30, 0xB5E4F7 }, { 1, 0xC9F2FF } }, true)
	local x = 0
	while x < w do
		local bw, bh = rng:int(10, 22), rng:int(18, 46)
		box(p, x, h - 22 - bh, bw, bh, 0xAEB8C5, 4)
		box(p, x, h - 22 - bh, 1, bh, 0xC9D2DC, 4)
		x += bw + rng:int(1, 6)
	end
	box(p, 0, h - 22, w, 22, 0x7B8696, 4)
	box(p, 0, h - 22, w, 1, 0xAEB8C5, 4)
	return nil
end

-- The scene for a Data/Ideas variant under everything else in the area; returns its update (or a no-op).
function Scenes.build(area: Frame, variant: string, w: number, h: number, rng: Types.Rng): Update
	local layer = Instance.new("Frame")
	layer.Name = "Scene"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromOffset(w, h)
	layer.ZIndex = 4
	layer.Active = false
	layer.Parent = area
	local fn = BUILD[variant]
	local up = if fn then fn(layer, w, h, rng) else nil
	return up or function(_t: number, _pace: number?) end
end

function Scenes.has(variant: string): boolean
	return BUILD[variant] ~= nil
end

return Scenes
