--!strict
-- The sea chart drawn as a map (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.4): the player's own islands (Logic/Chart)
-- as real islands, pixel by pixel into an EditableImage: each its own coastline (an oval wobbled by four sines, a
-- satellite islet or two), the shallows and the surf round it, a beach, and its kind's land (Data/Islets): beaches of
-- sand and palms, green meadows with sandy clearings and woods, volcanoes of dark rock with a glowing crater and lava,
-- snowfields with icy crevasses and a frozen lake, coral reefs round a lagoon; home in the middle with its campfire
-- and flag. Every colour comes from a hue-shifted ramp (cool shadows, warm lights); the land is lit from the top left
-- along its slope and textured by a value noise of the island's own. Islands past the boat's range lie under a cool
-- fog; the range is a dotted ring (the next boat's a dim one); charted islands fly a flag; the chosen one is outlined.
-- Without EditableImages it draws the islands' chart sprites instead. A tap on an island picks it (`Isle_<id>`).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Chart = require(ReplicatedStorage.Shared.Logic.Chart)
local ImageMemory = require(script.Parent.Parent.Pixel.ImageMemory)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

local SeaMap = {}

export type Opts = {
	sea: number,
	boat: number,
	chart: { number },
	cap: number,
	chosen: number,
	onPick: (id: number) -> (),
	onFar: (id: number) -> (),
}

-- the ramps (darkest first): shadows lean blue and purple, lights lean yellow
local SEA = { 0x163F6B, 0x1D5C86, 0x24719E, 0x3C8CB8 }
local SHALLOW = { 0x2F8BB0, 0x3FA2BF, 0x69C8CF, 0xC9F0E6 }
local SAND = { 0x9C6B5E, 0xD9A86C, 0xF0D49A, 0xFFF4C8 }
local GRASS = { 0x1F4E52, 0x2E7D52, 0x58AE5E, 0xA6D86A }
local ROCK = { 0x241C3A, 0x3D3158, 0x5E5078, 0x8F82A6 }
local LAVA = { 0x9C2A3A, 0xE2562A, 0xFFB040, 0xFFE38A }
local SNOW = { 0x5E74A8, 0x9DB6DD, 0xDDEBF7, 0xFFFFFF }
local CORAL = { 0x7E2F6A, 0xC85E98, 0xF29EC4, 0xFFD9E2 }
local LAGOON = { 0x2F9CB0, 0x5CC8C9, 0x8FE3D6, 0xD2FFF0 }
local FOG = 0x15284A
local RING = 0xFFCB30
local RING2 = 0x8DBBDD
local PICK = 0xFFFFFF
local INK = 0x2B1E2E

type Shape = { x: number, y: number, r: number, amp: { number }, ph: { number } }
type Isle = { id: number, kind: number, cx: number, cy: number, r: number, shapes: { Shape }, seed: number, far: boolean, charted: boolean }

local image: EditableImage? = nil
local imageSize = 0

local function hash2(ix: number, iy: number, seed: number): number
	local h = Util.hash32(ix * 374761393 + iy * 668265263 + seed * 2246822519)
	return (h % 65536) / 65536
end

-- Value noise (0..1) at a pixel, cells of `cell` px, the island's own.
local function noise(x: number, y: number, seed: number, cell: number): number
	local fx, fy = x / cell, y / cell
	local ix, iy = math.floor(fx), math.floor(fy)
	local tx, ty = fx - ix, fy - iy
	tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
	local a = hash2(ix, iy, seed)
	local b = hash2(ix + 1, iy, seed)
	local c = hash2(ix, iy + 1, seed)
	local d = hash2(ix + 1, iy + 1, seed)
	return a + (b - a) * tx + (c - a) * ty + (a - b - c + d) * tx * ty
end

local function mix(a: number, b: number, k: number): number
	local r = math.floor(bit32.rshift(a, 16) * (1 - k) + bit32.rshift(b, 16) * k + 0.5)
	local g = math.floor(bit32.band(bit32.rshift(a, 8), 0xFF) * (1 - k) + bit32.band(bit32.rshift(b, 8), 0xFF) * k + 0.5)
	local bl = math.floor(bit32.band(a, 0xFF) * (1 - k) + bit32.band(b, 0xFF) * k + 0.5)
	return r * 65536 + g * 256 + bl
end

-- The islands on the map: their kinds, sizes and coastlines (px), home first (id 0).
local function islesOf(o: Opts, M: number): ({ Isle }, number, number, number)
	local range = Chart.radius(o.boat)
	local nextR = if Chart.boatCost(o.boat) then Chart.radius(o.boat + 1) else nil
	local viewR = math.min(Tuning.ChartMaxDist + 0.4, (nextR or range) + 1.4)
	local ppl = (M / 2 - 4) / viewR
	local c0 = M / 2
	local out: { Isle } = {}
	local function shapeOf(rng: Types.Rng, x: number, y: number, r: number): Shape
		return {
			x = x,
			y = y,
			r = r,
			amp = { 0.2 + rng:next() * 0.08, 0.12 + rng:next() * 0.06, 0.07 + rng:next() * 0.04, 0.04 + rng:next() * 0.03 },
			ph = { rng:next() * 6.28, rng:next() * 6.28, rng:next() * 6.28, rng:next() * 6.28 },
		}
	end
	local function add(id: number, kind: number, x: number, y: number, rl: number, seed: number, far: boolean, charted: boolean)
		local rng = Util.newRng(seed)
		local r = math.max(3, rl * ppl)
		local shapes = { shapeOf(rng, x, y, r) }
		-- a satellite islet or two off its coast
		for _ = 1, rng:int(0, 2) do
			local a = rng:next() * 6.28
			local d = r * (1.15 + rng:next() * 0.3)
			table.insert(shapes, shapeOf(rng, x + math.cos(a) * d, y + math.sin(a) * d, math.max(1.5, r * (0.18 + rng:next() * 0.12))))
		end
		table.insert(out, { id = id, kind = kind, cx = x, cy = y, r = r, shapes = shapes, seed = seed, far = far, charted = charted })
	end
	add(0, 0, c0, c0, 1.05, Util.hash32(o.sea) % 100000 + 7, false, false)
	for _, c in Chart.islands(o.sea) do
		if c.dist <= viewR then
			local isle = Chart.isle(o.sea, c.id) :: Types.Isle
			local rl = 0.55 + (c.seed % 1000) / 1000 * 0.5
			add(c.id, isle.kind, c0 + c.x * ppl, c0 + c.y * ppl, rl, c.seed, c.dist > range, table.find(o.chart, c.id) ~= nil)
		end
	end
	return out, ppl, range * ppl, if nextR then nextR * ppl else 0
end

-- A shape's signed distance (px; below 0 inside) at a point.
local function shapeDist(s: Shape, x: number, y: number): number
	local dx, dy = x - s.x, y - s.y
	local a = math.atan2(dy, dx)
	local w = 1 + s.amp[1] * math.sin(2 * a + s.ph[1]) + s.amp[2] * math.sin(3 * a + s.ph[2]) + s.amp[3] * math.sin(5 * a + s.ph[3]) + s.amp[4] * math.sin(7 * a + s.ph[4])
	return math.sqrt(dx * dx + dy * dy) - s.r * math.max(0.45, w)
end

-- The land's colour at a pixel of an island (inside its coast): its kind's ramp, lit and textured.
local function landColor(isle: Isle, x: number, y: number, d: number, lit: number): number
	local depth = -d / math.max(2, isle.r) -- 0 at the coast, about 1 in the middle
	local n = noise(x, y, isle.seed, 4)
	local m = noise(x, y, isle.seed + 991, 2)
	local shade = if lit > 0.45 then 3 elseif lit < -0.45 then 1 else 2
	local kind = isle.kind
	-- the beach round every island but the volcanoes' dark shore and the snowfields' ice
	if d > -1.5 then
		if kind == 3 then
			return ROCK[math.max(1, shade - 1)]
		elseif kind == 4 then
			return SNOW[shade]
		end
		return SAND[math.min(4, shade + (if m > 0.7 then 1 else 0))]
	end
	if kind == 0 then
		-- home: a meadow round a sandy plaza with the campfire's glow
		if depth > 0.72 then
			return if depth > 0.95 then LAVA[3] else SAND[math.clamp(shade + 1, 1, 4)]
		end
		return GRASS[math.clamp(shade + (if m > 0.78 then 1 elseif m < 0.15 then -1 else 0), 1, 4)]
	elseif kind == 1 then
		-- a beach: sand with tufts of palms
		if n > 0.62 and depth > 0.25 then
			return GRASS[math.clamp(shade + (if m > 0.6 then 1 else 0), 1, 4)]
		end
		return SAND[math.clamp(shade + (if m > 0.82 then 1 elseif m < 0.12 then -1 else 0), 1, 4)]
	elseif kind == 2 then
		-- a meadow: green, sandy clearings, darker woods, now and then a pond
		if n < 0.28 then
			return SAND[math.clamp(shade, 1, 4)]
		elseif n > 0.74 then
			return GRASS[math.clamp(shade - 1 - (if m > 0.6 then 1 else 0), 1, 4)]
		elseif n > 0.52 and n < 0.55 and depth > 0.5 then
			return LAGOON[2]
		end
		return GRASS[math.clamp(shade + (if m > 0.8 then 1 else 0), 1, 4)]
	elseif kind == 3 then
		-- a volcano: dark rock rising to a glowing crater, lava running down
		if depth > 0.8 then
			return if depth > 0.9 then LAVA[4] else LAVA[2]
		elseif depth > 0.66 then
			return ROCK[1]
		end
		local a = math.atan2(y - isle.cy, x - isle.cx)
		local streak = math.abs(math.sin(a * 3 + isle.seed % 7)) > 0.97
		if streak and depth > 0.2 then
			return LAVA[if m > 0.5 then 2 else 1]
		end
		return ROCK[math.clamp(shade + (if m > 0.75 then 1 elseif m < 0.2 then -1 else 0), 1, 4)]
	elseif kind == 4 then
		-- a snowfield: snow lit from the top left, icy crevasses, a frozen lake in the middle
		if depth > 0.82 then
			return LAGOON[if m > 0.5 then 3 else 2]
		end
		if n > 0.47 and n < 0.52 then
			return SNOW[1]
		end
		return SNOW[math.clamp(shade + (if m > 0.7 then 1 else 0), 1, 4)]
	end
	-- a reef: a coral ring round a lagoon
	if depth > 0.5 then
		return LAGOON[math.clamp(shade + (if m > 0.7 then 1 else 0), 1, 4)]
	end
	return CORAL[math.clamp(shade + (if m > 0.75 then 1 elseif m < 0.2 then -1 else 0), 1, 4)]
end

-- Render the map into a pixel buffer (RGBA bytes, M x M).
local function render(o: Opts, M: number): (buffer, { Isle }, number)
	local isles, ppl, ringR, ring2R = islesOf(o, M)
	local n = M * M
	local dist = buffer.create(n * 4)
	local owner = buffer.create(n)
	for i = 0, n - 1 do
		buffer.writef32(dist, i * 4, 1e6)
	end
	-- each island's coast over its own box (and the shallows round it)
	for idx, isle in isles do
		for _, s in isle.shapes do
			local ext = s.r * 1.6 + 5
			local x0, x1 = math.max(0, math.floor(s.x - ext)), math.min(M - 1, math.ceil(s.x + ext))
			local y0, y1 = math.max(0, math.floor(s.y - ext)), math.min(M - 1, math.ceil(s.y + ext))
			for y = y0, y1 do
				for x = x0, x1 do
					local d = shapeDist(s, x + 0.5, y + 0.5)
					local i = y * M + x
					if d < buffer.readf32(dist, i * 4) then
						buffer.writef32(dist, i * 4, d)
						buffer.writeu8(owner, i, idx)
					end
				end
			end
		end
	end
	local px = buffer.create(n * 4)
	local cx, cy = M / 2, M / 2
	for y = 0, M - 1 do
		for x = 0, M - 1 do
			local i = y * M + x
			local d = buffer.readf32(dist, i * 4)
			local col: number
			local isle: Isle? = nil
			if d <= 4 then
				isle = isles[buffer.readu8(owner, i)]
			end
			if isle and d <= 0 then
				-- the slope toward the light (the top left): where the coast distance falls going right and down
				local function at(xx: number, yy: number): number
					if xx < 0 or yy < 0 or xx >= M or yy >= M then
						return d
					end
					return math.min(buffer.readf32(dist, (yy * M + xx) * 4), 50)
				end
				local lit = -((at(x + 1, y) - at(x - 1, y)) + (at(x, y + 1) - at(x, y - 1))) * 0.5
				if -d > 3.5 then
					lit *= 0.35 -- the middle of an island is mostly flat
				end
				col = landColor(isle, x, y, d, lit)
			elseif isle and d <= 1 then
				col = SHALLOW[4] -- the surf on the shore
			elseif isle and d <= 2.2 then
				col = SHALLOW[3]
			elseif isle and d <= 4 then
				col = if (x + y) % 2 == 0 and d > 3.3 then SHALLOW[1] else SHALLOW[2]
			else
				-- the open sea: deeper toward the chart's edge, swells as short light dashes
				local r = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) / (M / 2)
				col = if r > 0.96 then SEA[1] elseif r > 0.8 and (x + y) % 2 == 0 then SEA[1] else SEA[2]
				if y % 9 == 4 and (x + (y * 7) % 13) % 23 < 5 then
					col = SEA[4]
				elseif y % 9 == 0 and (x + (y * 5) % 11) % 31 < 3 then
					col = SEA[3]
				end
			end
			-- past the boat's range: under a cool fog
			if isle and isle.far then
				col = mix(col, FOG, 0.55)
			end
			-- the chosen island's outline on the water
			if isle and isle.id == o.chosen and d > 1.2 and d <= 2.2 then
				col = PICK
			end
			-- the range rings: dotted
			local rr = math.sqrt((x + 0.5 - cx) ^ 2 + (y + 0.5 - cy) ^ 2)
			if math.abs(rr - ringR) < 0.5 or (ring2R > 0 and math.abs(rr - ring2R) < 0.5) then
				-- a dot every few px along the ring's length
				local onFirst = math.abs(rr - ringR) < 0.5
				local arc = (math.atan2(y + 0.5 - cy, x + 0.5 - cx) + math.pi) * rr
				if onFirst and math.floor(arc) % 3 == 0 then
					col = RING
				elseif not onFirst and math.floor(arc) % 4 == 0 then
					col = RING2
				end
			end
			-- a frame round the chart
			if x == 0 or y == 0 or x == M - 1 or y == M - 1 then
				col = INK
			end
			local o4 = i * 4
			buffer.writeu8(px, o4, bit32.rshift(col, 16))
			buffer.writeu8(px, o4 + 1, bit32.band(bit32.rshift(col, 8), 0xFF))
			buffer.writeu8(px, o4 + 2, bit32.band(col, 0xFF))
			buffer.writeu8(px, o4 + 3, 255)
		end
	end
	-- flags on the charted islands and on home: a red pennant on a dark pole
	local function flag(fx: number, fy: number, color: number)
		local function put(xx: number, yy: number, c: number)
			if xx >= 1 and yy >= 1 and xx < M - 1 and yy < M - 1 then
				local o4 = (yy * M + xx) * 4
				buffer.writeu8(px, o4, bit32.rshift(c, 16))
				buffer.writeu8(px, o4 + 1, bit32.band(bit32.rshift(c, 8), 0xFF))
				buffer.writeu8(px, o4 + 2, bit32.band(c, 0xFF))
			end
		end
		for k = 0, 4 do
			put(fx, fy + k, INK)
		end
		put(fx + 1, fy, color)
		put(fx + 2, fy, color)
		put(fx + 1, fy + 1, color)
		put(fx + 2, fy + 1, mix(color, INK, 0.35))
		put(fx + 3, fy, mix(color, 0xFFF4C8, 0.3))
	end
	for _, isle in isles do
		if isle.charted or isle.id == 0 then
			flag(math.floor(isle.cx), math.floor(isle.cy - isle.r * 0.4) - 4, if isle.id == 0 then 0xE8465B else 0xFFCB30)
		end
	end
	return px, isles, ppl
end

-- The map in a frame of size x size UI px on `parent`; islands tap to pick (`Isle_<id>` buttons), reachable ones
-- labelled with their level (green at or under the captain's, yellow a little over, red well over).
function SeaMap.draw(parent: Instance, size: number, pos: UDim2, o: Opts): Frame
	local M = math.max(40, math.floor(size))
	local f = Instance.new("Frame")
	f.Name = "Chart"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromOffset(M, M)
	f.Position = pos
	f.ZIndex = 3
	f.Parent = parent
	local px, isles, _ppl = render(o, M)
	local img = image
	if img == nil or imageSize ~= M then
		if img then
			img:Destroy()
		end
		img = ImageMemory.create(M, M, "map")
		image, imageSize = img, M
	end
	local shown = false
	if img then
		local ok = pcall(function()
			(img :: EditableImage):WritePixelsBuffer(Vector2.zero, Vector2.new(M, M), px)
		end)
		if ok then
			local l = Instance.new("ImageLabel")
			l.Name = "MapImage"
			l.BackgroundTransparency = 1
			l.BorderSizePixel = 0
			l.Size = UDim2.fromOffset(M, M)
			l.ResampleMode = Enum.ResamplerMode.Pixelated
			l.ImageContent = Content.fromObject(img)
			l.ZIndex = 3
			l.Parent = f
			shown = true
		end
	end
	if not shown then
		-- no EditableImages: a sea plate and the islands' chart sprites
		UIKit.rect(f, UDim2.fromOffset(M, M), UDim2.fromOffset(0, 0), UIKit.hex(SEA[2]), 3)
		local names = { [0] = "home", "beach", "meadow", "volcano", "snow", "reef" }
		for _, isle in isles do
			PixelSprites.image(f, "chart_" .. (names[isle.kind] or "beach") .. (if isle.far then "_sil" else ""), UDim2.fromOffset(math.floor(isle.cx) - 6, math.floor(isle.cy) - 5), 4)
		end
	end
	-- labels and the taps
	local levels: { [number]: number } = {}
	for _, c in Chart.islands(o.sea) do
		levels[c.id] = c.lvl
	end
	table.sort(isles, function(a, b)
		return a.r > b.r -- the small ones over the big ones (their taps win)
	end)
	-- the level labels: under an island, else over it, else none where it would cover another's (big islands first)
	local taken: { { number } } = {}
	local function free(x: number, y: number, w: number): boolean
		for _, r in taken do
			if x < r[1] + r[3] + 2 and r[1] < x + w + 2 and y < r[2] + 8 and r[2] < y + 8 then
				return false
			end
		end
		return true
	end
	for z, isle in isles do
		if isle.id == 0 then
			continue
		end
		local lvl = levels[isle.id] or 1
		if not isle.far then
			local col = if lvl <= o.cap then UIKit.color("good") elseif lvl <= o.cap + 3 then UIKit.color("accent") else UIKit.color("bad")
			local text = "Lv" .. lvl
			local w = UIKit.textWidth(text) + 2
			local lx = math.floor(isle.cx) - math.floor(w / 2)
			for _, ly in { math.floor(isle.cy + isle.r * 0.6) + 1, math.floor(isle.cy - isle.r * 0.6) - 9 } do
				if free(lx, ly, w) then
					table.insert(taken, { lx, ly, w })
					UIKit.text(f, text, UDim2.fromOffset(w, 8), UDim2.fromOffset(lx, ly), { x = "center", color = col, kind = "outline", z = 6 })
					break
				end
			end
		end
		local box = math.max(10, math.floor(isle.r * 1.7))
		local hit = Instance.new("TextButton")
		hit.Name = "Isle_" .. isle.id
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.AutoButtonColor = true -- (its background stays clear: the map shows through)
		hit.Size = UDim2.fromOffset(box, box)
		hit.Position = UDim2.fromOffset(math.floor(isle.cx - box / 2), math.floor(isle.cy - box / 2))
		hit.ZIndex = 7 + z
		hit.Parent = f
		local id, far = isle.id, isle.far
		hit.Activated:Connect(function()
			if far then
				o.onFar(id)
			else
				o.onPick(id)
			end
		end)
	end
	return f
end

return SeaMap
