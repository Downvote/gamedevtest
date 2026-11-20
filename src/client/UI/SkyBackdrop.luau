--!strict
--!native
-- The sky round the floating islands (GAME_DESIGN 2 and 8; docs/ARCHITECTURE.md 10): the request of 2026-11-20,
-- "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the island bigger." A picture
-- painted pixel by pixel at the world's art grid (each art pixel K x K screen px, like the pixel layer) on a ScreenGui
-- behind the pixel layer: the islands' sky is see-through (CameraController's view `clear`), so they float in front of
-- it. Two images:
-- * the sky: bands of colour from the top down to a paler glow at the bottom, each meeting the next in an ordered
--   dither (never a smear), and a few far islets floating in the haze (a grass cap over a stony point, a little tree on
--   the bigger ones, faded toward the sky's colour, a 1 px outline round each);
-- * the clouds in front of it: puffy, each a row of round puffs, the frontmost puff's top lit from the top left, a
--   shade under each, along its flat bottom and on the seam where one puff stands in front of another, a 1 px outline
--   round the whole cloud a step darker than the sky there, its corners anti-aliased (a step between the outline and
--   what is behind). The picture repeats across and shows twice side by side: it drifts right a pixel every DRIFT s and
--   slides with the view a PARALLAX of its pan (whole art px), so the clouds seem nearer than the far islets and much
--   farther than the islands.
-- Each weather has its own sky (SKIES): blue on a fair day, grey in the rain, slate in a storm, pale in fog and snow,
-- warm in a haze. The hatch scene's own backdrop shows in front of it.
--   start(), paint(kind, W, H) -> (buffer, buffer)  the sky and the clouds (RGBA, W x H each; the clouds' empty pixels
--                                                    clear), debugState()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local CameraController = require(script.Parent.Parent.Controllers.CameraController)
local WeatherView = require(script.Parent.Parent.Controllers.WeatherView)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)

local SkyBackdrop = {}

local DRIFT = 1.6 -- s a pixel the clouds drift right
local PARALLAX = 1 / 8 -- of the view's pan the clouds slide with

type Sky = {
	stops: { number }, -- the sky's colours from the top down
	isle: { number }, -- the far islets before they fade: grass lit, grass, rock, rock dark, trunk
	fade: number, -- how far toward the sky's colour the far islets fade
	lit: number, -- the clouds: the lit tops, the body, the shade
	body: number,
	shade: number,
	ink: number, -- the colour the outlines lean toward from the sky's
	clouds: number, -- clouds for every 100,000 px
}

local FAIR: Sky = {
	stops = { 0x6DB7EA, 0x80C3EF, 0x94CFF4, 0xA8DAF7, 0xBDE4FA, 0xD3EEFB },
	isle = { 0xA6E08E, 0x86CC78, 0xA49AA2, 0x857C88, 0x8C6450 },
	fade = 0.5,
	lit = 0xFFFFFF,
	body = 0xF1F8FE,
	shade = 0xCFE2F3,
	ink = 0x3A5E8C,
	clouds = 6,
}
local SKIES: { [string]: Sky } = {
	sunny = FAIR,
	breezy = FAIR,
	blossom = FAIR,
	leaves = FAIR,
	rain = {
		stops = { 0x7B8FA5, 0x8698AD, 0x91A3B6, 0x9DADBF, 0xA9B8C8, 0xB6C3D1 },
		isle = { 0x93B88A, 0x7AA474, 0x948E98, 0x7A7480, 0x7A5E50 },
		fade = 0.55,
		lit = 0xE3E9F0,
		body = 0xD0D9E3,
		shade = 0xAAB8C7,
		ink = 0x34445C,
		clouds = 9,
	},
	storm = {
		stops = { 0x4B566B, 0x556177, 0x5F6C83, 0x6A778E, 0x75829A, 0x818DA5 },
		isle = { 0x7C9A78, 0x668864, 0x7C7782, 0x635F6B, 0x5E4A42 },
		fade = 0.55,
		lit = 0xB2BCCA,
		body = 0x9BA6B6,
		shade = 0x7B8698,
		ink = 0x232B3A,
		clouds = 11,
	},
	fog = {
		stops = { 0xB6C4CF, 0xBFCCD6, 0xC8D3DC, 0xD1DAE2, 0xDAE2E8, 0xE4E9EE },
		isle = { 0xB2CDA8, 0x9DBC96, 0xAEA9B0, 0x9894A0, 0x957D70 },
		fade = 0.72,
		lit = 0xF7F9FB,
		body = 0xEDF1F5,
		shade = 0xD5DEE6,
		ink = 0x6C7D8E,
		clouds = 5,
	},
	snow = {
		stops = { 0xA6BED4, 0xB1C7DA, 0xBCD0E1, 0xC7D9E7, 0xD2E2EE, 0xDEEAF3 },
		isle = { 0xE8F0F6, 0xD2E0EA, 0xA6A2AC, 0x8D8996, 0x8A6E60 },
		fade = 0.5,
		lit = 0xFFFFFF,
		body = 0xF2F6FA,
		shade = 0xD3DFEA,
		ink = 0x4B6584,
		clouds = 7,
	},
	haze = {
		stops = { 0x8FC2E2, 0xA0CAE2, 0xB3D2E1, 0xC6DADE, 0xD9E0D9, 0xEDE5D0 },
		isle = { 0xBADB8A, 0x9CC872, 0xB0A098, 0x938478, 0x92664A },
		fade = 0.55,
		lit = 0xFFFDF5,
		body = 0xF8F1E4,
		shade = 0xE3D6C2,
		ink = 0x6A6080,
		clouds = 4,
	},
}

------------------------------------------------------------------ colours
local BAYER: { number } = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 }
local function bay(x: number, y: number): number
	return (BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5) / 16
end

local function rgb(c: number): (number, number, number)
	return bit32.rshift(c, 16) % 256, bit32.rshift(c, 8) % 256, c % 256
end

local function mix(a: number, b: number, k: number): number
	local ar, ag, ab = rgb(a)
	local br, bg, bb = rgb(b)
	local r = math.floor(ar + (br - ar) * k + 0.5)
	local g = math.floor(ag + (bg - ag) * k + 0.5)
	local bl = math.floor(ab + (bb - ab) * k + 0.5)
	return r * 65536 + g * 256 + bl
end

-- a 0xRRGGBB colour as the image's RGBA bytes (little-endian u32, opaque)
local function packed(c: number): number
	local r, g, b = rgb(c)
	return r + g * 256 + b * 65536 + 255 * 16777216
end

local function hash(n: number): number
	local x = math.floor(n) % 2147483647
	x = (x * 1103515245 + 12345) % 2147483648
	x = (x * 1103515245 + 12345) % 2147483648
	return x / 2147483648
end

------------------------------------------------------------------ painting
-- The sky's band at row y (and the mean of the two colours meeting there, for what blends into it): flat in the
-- middle of each band, an ordered dither where two meet.
local function bandAt(sky: Sky, x: number, y: number, H: number): number
	local n = #sky.stops
	local t = y / math.max(1, H - 1) * (n - 1)
	local i = math.floor(t)
	if i >= n - 1 then
		return sky.stops[n]
	end
	local k = math.clamp((t - i - 0.35) / 0.3, 0, 1)
	return if k > bay(x, y) then sky.stops[i + 2] else sky.stops[i + 1]
end
local function meanAt(sky: Sky, y: number, H: number): number
	local n = #sky.stops
	local t = y / math.max(1, H - 1) * (n - 1)
	local i = math.floor(t)
	if i >= n - 1 then
		return sky.stops[n]
	end
	return mix(sky.stops[i + 1], sky.stops[i + 2], math.clamp((t - i - 0.35) / 0.3, 0, 1))
end

-- A far islet into px (0xRRGGBB, row by row, W x H): a grass cap (an ellipse w wide, its top half the lawn, lit at the
-- top left, a step of earth along its front) over a stony point that narrows to a tip with a jagged edge, a little
-- tree on the bigger ones, all faded toward the sky, a 1 px outline round it.
local function islet(px: { number }, W: number, H: number, sky: Sky, cx: number, cy: number, w: number, seed: number)
	local a = w / 2
	local b = math.max(2, math.floor(w / 7))
	local depth = math.floor(w * 0.62)
	local x0, x1 = math.floor(cx - a) - 2, math.ceil(cx + a) + 2
	local y0, y1 = cy - b - 6, cy + depth + 2
	-- the islet's own pixels by place: 1 lawn lit, 2 lawn, 3 earth, 4 rock, 5 rock dark, 6 trunk
	local mask: { [number]: number } = {}
	local function set(x: number, y: number, v: number)
		if x >= 0 and x < W and y >= 0 and y < H then
			mask[y * W + x] = v
		end
	end
	for y = cy - b, cy + depth do
		local half: number
		if y <= cy then
			local dy = (y - cy) / b
			half = a * math.sqrt(math.max(0, 1 - dy * dy))
		else
			local f = (y - cy) / depth
			half = a * (1 - f) ^ 0.85 + (hash(seed * 31 + math.floor(y / 2)) - 0.5) * 1.6
		end
		if half >= 0.5 then
			for x = math.floor(cx - half + 0.5), math.floor(cx + half - 0.5) do
				local v: number
				if y < cy then
					local lit = (x - cx) / a + (y - cy) / b < -0.45
					v = if lit then 1 else 2
				elseif y == cy then
					v = 2
				elseif y <= cy + 1 then
					v = 3
				else
					local f = (y - cy) / depth
					v = if f > 0.55 or x > cx + half * 0.35 then 5 else 4
				end
				set(x, y, v)
			end
		end
	end
	-- a little tree on the bigger islets: a trunk and a round crown, left of the middle
	if w >= 24 then
		local tx = math.floor(cx - a * 0.3)
		for y = cy - b - 2, cy - b + 1 do
			set(tx, y, 6)
		end
		for dy = -2, 2 do
			for dx = -2, 2 do
				if dx * dx + dy * dy <= 5 then
					set(tx + dx, cy - b - 4 + dy, if dx + dy < -1 then 1 else 2)
				end
			end
		end
	end
	local cols = { sky.isle[1], sky.isle[2], mix(sky.isle[3], sky.isle[5], 0.5), sky.isle[3], sky.isle[4], sky.isle[5] }
	for y = math.max(0, y0), math.min(H - 1, y1) do
		local back = meanAt(sky, y, H)
		local ink = mix(mix(sky.isle[4], back, sky.fade), sky.ink, 0.3)
		for x = math.max(0, x0), math.min(W - 1, x1) do
			local i = y * W + x
			local v = mask[i]
			if v then
				px[i + 1] = mix(cols[v], back, sky.fade)
			elseif mask[i - 1] and x > 0 or mask[i + 1] and x < W - 1 or mask[i - W] or mask[i + W] then
				px[i + 1] = ink
			end
		end
	end
end

-- One cloud into the clouds' picture (0xRRGGBB per pixel, 0 clear, row by row, W x H, repeating across): puffs
-- { cx, cy, r } over a flat bottom at `base`.
local function cloud(px: { number }, W: number, H: number, sky: Sky, puffs: { { number } }, base: number)
	local x0, x1, y0 = math.huge, -math.huge, math.huge
	for _, p in puffs do
		x0 = math.min(x0, math.floor(p[1] - p[3]) - 1)
		x1 = math.max(x1, math.ceil(p[1] + p[3]) + 1)
		y0 = math.min(y0, math.floor(p[2] - p[3]) - 1)
	end
	-- (which puff a pixel is in: the frontmost, the lowest centre; and whether a puff behind it holds it too)
	local function inside(x: number, y: number): (number, boolean)
		if y > base then
			return 0, false
		end
		local front, behind = 0, false
		for k, p in puffs do
			local dx, dy = x + 0.5 - p[1], y + 0.5 - p[2]
			if dx * dx + dy * dy <= p[3] * p[3] then
				if front == 0 or p[2] > puffs[front][2] then
					behind = behind or front ~= 0
					front = k
				else
					behind = true
				end
			end
		end
		return front, behind
	end
	local yTop, yBot = math.max(0, y0 - 1), math.min(H - 1, base + 1)
	-- the cloud's own pixels first (by place), then its outline round them
	local own: { [number]: number } = {}
	for y = yTop, yBot do
		for x = x0, x1 do
			local k, behind = inside(x, y)
			if k == 0 then
				continue
			end
			local p = puffs[k]
			local nx, ny = (x + 0.5 - p[1]) / p[3], (y + 0.5 - p[2]) / p[3]
			local c: number
			if y >= base - 1 then
				c = sky.shade
			elseif behind and math.sqrt(nx * nx + ny * ny) > 0.9 then
				-- (the seam where this puff stands in front of another)
				c = sky.shade
			elseif nx * -0.55 + ny * -0.83 > 0.45 then
				c = sky.lit
			elseif ny > 0.4 then
				c = sky.shade
			else
				c = sky.body
			end
			own[y * 65536 + (x + 32768)] = c
		end
	end
	local function has(x: number, y: number): boolean
		return own[y * 65536 + (x + 32768)] ~= nil
	end
	for y = yTop, yBot do
		local back = meanAt(sky, y, H)
		for x = x0 - 1, x1 + 1 do
			local i = y * W + (x % W)
			local c = own[y * 65536 + (x + 32768)]
			if c then
				px[i + 1] = c
			elseif has(x - 1, y) or has(x + 1, y) or has(x, y - 1) or has(x, y + 1) then
				-- the outline: a step darker than what is behind it (the sky, or a cloud drawn before)
				local under = px[i + 1]
				px[i + 1] = mix(if under ~= 0 then under else back, sky.ink, 0.32)
			elseif has(x - 1, y - 1) or has(x + 1, y - 1) or has(x - 1, y + 1) or has(x + 1, y + 1) then
				-- its corners anti-aliased: half a step
				local under = px[i + 1]
				px[i + 1] = mix(if under ~= 0 then under else back, sky.ink, 0.15)
			end
		end
	end
end

-- The sky and its clouds for a weather (Data/Weather id) at W x H art px: RGBA buffers, the clouds' empty pixels clear.
function SkyBackdrop.paint(kind: string, W: number, H: number): (buffer, buffer)
	local sky = SKIES[kind] or FAIR
	local n = W * H
	local px = table.create(n, 0)
	for y = 0, H - 1 do
		for x = 0, W - 1 do
			px[y * W + x + 1] = bandAt(sky, x, y, H)
		end
	end
	-- the far islets: the same places in every weather (a fixed seed), apart from one another
	local count = math.clamp(math.floor(W * H / 60000 + 0.5), 3, 6)
	local placed: { { number } } = {}
	local tries = 0
	while #placed < count and tries < 60 do
		tries += 1
		local s = tries * 7 + 3
		local w = 14 + math.floor(hash(s) * 20)
		local cx = math.floor(w / 2 + 4 + hash(s + 1) * (W - w - 8))
		local cy = math.floor(H * 0.22 + hash(s + 2) * H * 0.5)
		local ok = true
		for _, q in placed do
			if math.abs(q[1] - cx) < (q[3] + w) * 0.7 + 8 and math.abs(q[2] - cy) < (q[3] + w) * 0.6 + 6 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, { cx, cy, w })
			islet(px, W, H, sky, cx, cy, w, s)
		end
	end
	local skyBuf = buffer.create(n * 4)
	for i = 1, n do
		buffer.writeu32(skyBuf, (i - 1) * 4, packed(px[i]))
	end
	-- the clouds: the farther (higher) first, so a nearer one's outline crosses them
	local cp = table.create(n, 0)
	local many = math.max(3, math.floor(W * H / 100000 * sky.clouds + 0.5))
	local list: { { number } } = {}
	for k = 1, many do
		local s = k * 13 + 101
		table.insert(list, { hash(s) * W, math.floor(H * 0.06 + hash(s + 1) * H * 0.9), s })
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	for _, c in list do
		local s = c[3]
		local cx, base = c[1], c[2]
		-- nearer clouds (lower on the screen) a little bigger
		local scale = 0.75 + (base / H) * 0.5
		local puffs: { { number } } = {}
		local np = 3 + math.floor(hash(s + 2) * 4)
		local span = (22 + hash(s + 3) * 40) * scale
		for p = 1, np do
			local u = (p - 1) / math.max(1, np - 1) - 0.5 -- -0.5 .. 0.5 across
			local r = (6 + 8 * (1 - math.abs(u) * 1.4) + hash(s + 10 + p) * 4) * scale
			table.insert(puffs, { cx + u * span + (hash(s + 20 + p) - 0.5) * 3, base - r * 0.55 - hash(s + 30 + p) * 3 * scale, r })
		end
		cloud(cp, W, H, sky, puffs, base)
	end
	local cloudBuf = buffer.create(n * 4)
	for i = 1, n do
		local c = cp[i]
		buffer.writeu32(cloudBuf, (i - 1) * 4, if c ~= 0 then packed(c) else 0)
	end
	return skyBuf, cloudBuf
end

------------------------------------------------------------------ on screen
local gui: ScreenGui? = nil
local skyLabel: ImageLabel? = nil
local cloudLabels: { ImageLabel } = {}
local skyImage: EditableImage? = nil
local cloudImage: EditableImage? = nil
local shown = { kind = "", W = 0, H = 0, K = 0, off = -1, paints = 0 }
local started = false

local function label(parent: Instance, name: string, z: number): ImageLabel
	local l = Instance.new("ImageLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ResampleMode = Enum.ResamplerMode.Pixelated
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- The sky painted again for the weather and the screen (a new size, a new art scale, a new weather).
local function repaint(kind: string, W: number, H: number, K: number)
	local si, ci = skyImage, cloudImage
	if si == nil or si.Size.X ~= W or si.Size.Y ~= H then
		if si then
			si:Destroy()
		end
		si = ImageMemory.create(W, H, "sky")
		skyImage = si
	end
	if ci == nil or ci.Size.X ~= W or ci.Size.Y ~= H then
		if ci then
			ci:Destroy()
		end
		ci = ImageMemory.create(W, H, "sky clouds")
		cloudImage = ci
	end
	if si == nil or ci == nil then
		return
	end
	local skyBuf, cloudBuf = SkyBackdrop.paint(kind, W, H)
	pcall(function()
		(si :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), skyBuf);
		(ci :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(W, H), cloudBuf)
	end)
	local g = gui
	if g == nil then
		local ng = Instance.new("ScreenGui")
		ng.Name = "SkyBackdrop"
		ng.IgnoreGuiInset = true
		ng.ScreenInsets = Enum.ScreenInsets.None
		ng.DisplayOrder = Tuning.PixelDisplayOrder - 3 -- (behind the hatch scene's backdrop and the pixel layer)
		ng.ResetOnSpawn = false
		skyLabel = label(ng, "Sky", 1)
		cloudLabels = { label(ng, "CloudsA", 2), label(ng, "CloudsB", 2) }
		ng.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		gui = ng
	end
	local sl = skyLabel :: ImageLabel
	sl.ImageContent = Content.fromObject(si)
	sl.Size = UDim2.fromOffset(W * K, H * K)
	sl.Position = UDim2.fromOffset(0, 0)
	for _, l in cloudLabels do
		l.ImageContent = Content.fromObject(ci)
		l.Size = UDim2.fromOffset(W * K, H * K)
	end
	shown.kind, shown.W, shown.H, shown.K, shown.off = kind, W, H, K, -1
	shown.paints += 1
end

local function step()
	local K = math.max(1, math.floor(PixelRenderer.pixelScale()))
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local W, H = math.max(1, math.ceil(vp.X / K)), math.max(1, math.ceil(vp.Y / K))
	local kind = WeatherView.kind()
	local sky = SKIES[kind] or FAIR
	-- (a weather with the same sky as the one showing paints nothing)
	if W ~= shown.W or H ~= shown.H or K ~= shown.K or sky ~= (SKIES[shown.kind] or FAIR) or shown.paints == 0 then
		repaint(kind, W, H, K)
	end
	if shown.paints == 0 then
		return
	end
	local panX = CameraController.pan()
	local off = math.floor(os.clock() / DRIFT - panX * PARALLAX) % W
	if off ~= shown.off then
		shown.off = off
		local a, b = cloudLabels[1], cloudLabels[2]
		if a and b then
			a.Position = UDim2.fromOffset((off - W) * K, 0)
			b.Position = UDim2.fromOffset(off * K, 0)
		end
	end
end

function SkyBackdrop.start()
	if started then
		return
	end
	started = true
	step()
	RunService.Heartbeat:Connect(step)
end

-- What shows now (previews and sims): the weather painted, the picture's size, how many times it was painted, the
-- clouds' offset.
function SkyBackdrop.debugState(): { kind: string, W: number, H: number, paints: number, off: number }
	return { kind = shown.kind, W = shown.W, H = shown.H, paints = shown.paints, off = shown.off }
end

return SkyBackdrop
