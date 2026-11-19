--!strict
-- The fences, the bridges and what floats on the water (GAME_DESIGN 4; Data/Buildings). Roblox module.
-- Builders(m, f, lvl): f is the footprint's centre on the grass, turned; +Z faces the view before the turn.
--
-- A fence is one length of 2 studs drawn along a grid line: it runs along X from -1 to +1 at z = 0, with a post (or a
-- pier, a lump, a cane) at each end, the same shape seen from any side, so the lengths of a run share their posts and
-- a corner closes with no gap. The plain walls run 0.25 past their ends instead, and the palisade's logs keep the
-- same spacing from one length to the next. Each stays within about 0.35 of its line and at most 8 parts.
-- A bridge runs along Z: its ends land on the grass at z = -3 and +3 and its middle rises over the stream. The dock's
-- land end is at -Z. Floating pieces sit on the water's surface (about y 0 to 0.1).
local Parts = require(script.Parent.Parts)

local M: { [string]: Parts.Builder } = {}

local V = Vector3.new
local QUARTER = math.pi / 4

-- A box from point a to point b: its length along the line, w across it level, h across it upright.
local function seg(m: Model, f: CFrame, a: Vector3, b: Vector3, w: number, h: number, color: string, name: string?, neon: boolean?): BasePart
	return Parts.at(m, f, CFrame.lookAt((a + b) / 2, b), w, h, (b - a).Magnitude, color, name, neon)
end

-- A cube turned 45 degrees about Z at (x, y, z): its top half is a point (a picket's, a spear's, a log's).
local function point(m: Model, f: CFrame, x: number, y: number, z: number, s: number, color: string, name: string?, neon: boolean?): BasePart
	return Parts.at(m, f, CFrame.new(x, y, z) * CFrame.Angles(0, 0, QUARTER), s, s, s, color, name, neon)
end

-- A cube of side s standing on one corner, its top corner at height `tip`: a short pyramid that reads as a point from
-- any side (a log's sharpened end, a crystal's tip).
local CORNER = CFrame.Angles(0, 0, math.atan(math.sqrt(2))) * CFrame.Angles(0, QUARTER, 0)
local function peak(m: Model, f: CFrame, x: number, tip: number, z: number, s: number, color: string, name: string?, neon: boolean?): BasePart
	return Parts.at(m, f, CFrame.new(x, tip - s * math.sqrt(3) / 2, z) * CORNER, s, s, s, color, name, neon)
end

-- An upright box whose top is at `top` (sizes keep to the 0.25 grid, so a post is sunk into the grass to stand lower).
local function post(m: Model, f: CFrame, x: number, top: number, z: number, w: number, h: number, d: number, color: string, name: string?): BasePart
	return Parts.box(m, f, x, top - h / 2, z, w, h, d, color, name)
end

-- White water (the pixel filter's foam: class 3), flat at height y.
local function foam(m: Model, f: CFrame, x: number, y: number, z: number, w: number, h: number, d: number): BasePart
	local p = Parts.box(m, f, x, y, z, w, h, d, "foam", "Foam")
	p:SetAttribute("PixelWater", 3)
	return p
end

------------------------------------------------------------------ fences (one 2-stud length each)

-- Rope Fence: two round posts, a rope wound round each post's top and sagging between them.
M.ropefence = function(m, f)
	for _, x in { -1, 1 } do
		Parts.cyl(m, f, x, 0.85 - 0.5, 0, 0.5, 1, "wood", "Post")
		Parts.cyl(m, f, x, 0.66, 0, 0.75, 0.25, "straw", "Wrap")
	end
	local a, b, c, d = V(-1, 0.66, 0.2), V(-0.4, 0.46, 0.2), V(0.4, 0.46, 0.2), V(1, 0.66, 0.2)
	seg(m, f, a, b, 0.25, 0.25, "straw", "Rope")
	seg(m, f, b, c, 0.25, 0.25, "straw", "Rope")
	seg(m, f, c, d, 0.25, 0.25, "straw", "Rope")
end

-- Picket Fence: square white posts, two pointed pickets between them, two rails behind.
M.picket = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1, 0, 0.25, 1.25, 0.25, "white", "Post")
	end
	for _, y in { 0.25, 0.6 } do
		Parts.box(m, f, 0, y, -0.125, 2, 0.25, 0.25, "wall", "Rail")
	end
	for _, x in { -1 / 3, 1 / 3 } do
		post(m, f, x, 0.75, 0.125, 0.25, 1, 0.25, "white", "Picket")
		point(m, f, x, 0.75, 0.125, 0.25, "white", "Point")
	end
end

-- Split Rail: stout dark posts, three rough rails split from logs (a ridge on top), each a little askew.
M.splitrail = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1, 0, 0.5, 1.25, 0.5, "wood_dark", "Post")
	end
	local rails = { { 0.28, 0.04, 0.05 }, { 0.58, -0.05, -0.06 }, { 0.86, 0.03, 0.04 } }
	for i, r in rails do
		local cf = CFrame.new(0, r[1], 0.06) * CFrame.Angles(0, r[3], r[2]) * CFrame.Angles(QUARTER, 0, 0)
		Parts.at(m, f, cf, 2.25, 0.25, 0.25, if i == 2 then "sand_dark" else "wood", "Rail")
	end
end

-- Bamboo Fence: a screen of canes, yellow and green in turn and cut at uneven heights, a dark cord tied across; the
-- end canes are the posts.
M.bamboofence = function(m, f)
	local tops = { 1.3, 1.1, 1.22, 1.02, 1.18, 1.06, 1.3 }
	for i = 0, 6 do
		Parts.cyl(m, f, -1 + i / 3, tops[i + 1] - 0.75, 0, 0.25, 1.5, if i % 2 == 0 then "bamboo" else "green", "Cane")
	end
	Parts.box(m, f, 0, 0.85, 0.125, 2, 0.25, 0.25, "wood_dark", "Cord")
end

-- Driftwood Fence: pale bleached posts, two crooked branches lashed across, a twig, a red float hung on a cord.
M.driftwood = function(m, f)
	for _, x in { -1, 1 } do
		Parts.cyl(m, f, x, 0.9 - 0.5, 0, 0.5, 1, "pavement", "Post")
	end
	seg(m, f, V(-1, 0.76, 0.18), V(1, 0.58, 0.18), 0.25, 0.25, "pavement", "Branch")
	seg(m, f, V(-1, 0.3, 0.18), V(1, 0.42, 0.18), 0.25, 0.25, "sand", "Branch")
	seg(m, f, V(0.25, 0.66, 0.18), V(0.55, 0.95, 0.12), 0.25, 0.25, "pavement", "Twig")
	Parts.cyl(m, f, -1, 0.72, 0, 0.75, 0.25, "straw", "Lashing")
	Parts.ball(m, f, -0.3, 0.42, 0.22, 0.25, "berry_red", "Float")
end

-- Woven Fence: willow withies woven between dark stakes, each row bent in front of the middle and behind the ends,
-- the next row the other way, in two tones.
M.wattle = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1.15, 0, 0.25, 1.25, 0.25, "wood_dark", "Stake")
	end
	for r = 0, 2 do
		local bend = if r % 2 == 0 then 0.22 else -0.22
		for _, s in { -1, 1 } do
			local cf = CFrame.new(0.5 * s, 0.28 + r * 0.27, 0) * CFrame.Angles(0, bend * s, 0)
			Parts.at(m, f, cf, 1.25, 0.25, 0.25, if r % 2 == 0 then "straw" else "wood", "Withy")
		end
	end
end

-- Hedgerow: a clipped block of dark leaves, a lighter clipped top, a few tufts and two flowers on its face. It runs
-- a little past its ends so a corner closes.
M.hedgerow = function(m, f)
	Parts.box(m, f, 0, 0.375, 0, 2.5, 0.75, 0.5, "leaf_dark", "Hedge")
	Parts.box(m, f, 0, 0.875, 0, 2.5, 0.25, 0.5, "leaf", "Top")
	Parts.box(m, f, -0.55, 0.55, 0.2, 0.5, 0.25, 0.25, "leaf", "Tuft")
	Parts.box(m, f, 0.45, 0.3, 0.2, 0.25, 0.25, 0.25, "leaf", "Tuft")
	Parts.box(m, f, 0.7, 0.62, 0.2, 0.25, 0.25, 0.25, "leaf", "Tuft")
	Parts.box(m, f, -0.15, 0.32, 0.22, 0.25, 0.25, 0.25, "white", "Flower")
	Parts.box(m, f, 0.2, 0.7, 0.22, 0.25, 0.25, 0.25, "pink", "Flower")
end

-- Garden Gate: tall white posts joined by a little round arch, the gate between them a frame with a brace.
M.gardengate = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1.5, 0, 0.25, 1.75, 0.25, "white", "Post")
	end
	seg(m, f, V(-1, 1.42, 0), V(-0.45, 1.76, 0), 0.25, 0.25, "white", "Arch")
	Parts.box(m, f, 0, 1.8, 0, 1, 0.25, 0.25, "white", "Arch")
	seg(m, f, V(0.45, 1.76, 0), V(1, 1.42, 0), 0.25, 0.25, "white", "Arch")
	Parts.box(m, f, 0, 0.82, 0, 1.75, 0.25, 0.25, "white", "Rail")
	Parts.box(m, f, 0, 0.25, 0, 1.75, 0.25, 0.25, "white", "Rail")
	seg(m, f, V(-0.72, 0.3, 0), V(0.72, 0.78, 0), 0.25, 0.25, "wall", "Brace")
end

-- Low Stone Wall: a wall of grey field stones, darker and paler stones in its face, a rough top course with moss.
M.stonewall = function(m, f)
	Parts.box(m, f, 0, 0.35, 0, 2.5, 0.75, 0.5, "rock", "Wall")
	Parts.box(m, f, -0.6, 0.2, 0.19, 0.75, 0.25, 0.25, "rock_dark", "Stone")
	Parts.box(m, f, 0.35, 0.28, 0.19, 0.5, 0.25, 0.25, "pavement", "Stone")
	Parts.box(m, f, -0.15, 0.5, 0.19, 0.5, 0.25, 0.25, "rock_dark", "Stone")
	Parts.box(m, f, 0.78, 0.52, 0.19, 0.5, 0.25, 0.25, "rock_dark", "Stone")
	Parts.at(m, f, CFrame.new(-0.62, 0.8, 0) * CFrame.Angles(0, 0.1, 0.08), 0.75, 0.25, 0.5, "rock_dark", "Cope")
	Parts.at(m, f, CFrame.new(0.08, 0.83, 0) * CFrame.Angles(0, -0.08, -0.06), 0.75, 0.25, 0.5, "rock", "Cope")
	Parts.at(m, f, CFrame.new(0.72, 0.79, 0.02) * CFrame.Angles(0, 0.06, 0.05), 0.5, 0.25, 0.5, "moss", "Moss")
end

-- Log Palisade: three stout logs a hand apart (the same spacing on to the next length), the middle one taller, each
-- sharpened to a pale point, a rope lashed across behind them.
M.palisade = function(m, f)
	for i, x in { -2 / 3, 0, 2 / 3 } do
		local top = if i == 2 then 1.1 else 0.9
		Parts.cyl(m, f, x, top - 0.75, 0, 0.5, 1.5, if i == 2 then "wood" else "wood_dark", "Log")
		peak(m, f, x, top + 0.24, 0, 0.5, "sand", "Point")
	end
	Parts.box(m, f, 0, 0.6, -0.12, 2, 0.25, 0.25, "straw", "Lashing")
end

-- Iron Railing: black posts, a top and a bottom rail, two bars between ending in gold spear tips.
M.ironrail = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1.15, 0, 0.25, 1.25, 0.25, "black", "Post")
	end
	Parts.box(m, f, 0, 0.25, 0, 2, 0.25, 0.25, "black", "Rail")
	Parts.box(m, f, 0, 0.82, 0, 2, 0.25, 0.25, "black", "Rail")
	for _, x in { -1 / 3, 1 / 3 } do
		post(m, f, x, 0.98, 0, 0.25, 1, 0.25, "black", "Bar")
		point(m, f, x, 1.02, 0, 0.25, "gold", "Tip")
	end
end

-- Lantern Rope: tall dark posts, a cord sagging between them, three little lights hung from it.
M.lanternrope = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1.2, 0, 0.25, 1.25, 0.25, "wood_dark", "Post")
	end
	local hi, lo = 1.08, 0.82
	seg(m, f, V(-1, hi, 0.1), V(0, lo, 0.1), 0.25, 0.25, "black", "Cord")
	seg(m, f, V(0, lo, 0.1), V(1, hi, 0.1), 0.25, 0.25, "black", "Cord")
	for i, x in { -0.5, 0, 0.5 } do
		local y = lo + (hi - lo) * math.abs(x) - 0.24
		Parts.glow(m, f, x, y, 0.1, 0.25, 0.25, 0.25, if i == 2 then "orange" else "yellow", "Bulb")
	end
end

-- Brick Wall: a red brick wall with a pale stone coping, square piers at its ends with caps, a few bricks of
-- another fire set in its face.
M.brickwall = function(m, f)
	for _, x in { -1, 1 } do
		post(m, f, x, 1.125, 0, 0.75, 1.25, 0.75, "brick", "Pier")
		Parts.box(m, f, x, 1.25, 0, 0.75, 0.25, 0.75, "pavement", "PierCap")
	end
	post(m, f, 0, 0.75, 0, 2, 1, 0.5, "brick", "Wall")
	Parts.box(m, f, 0, 0.875, 0, 2, 0.25, 0.75, "pavement", "Coping")
	Parts.box(m, f, -0.4, 0.25, 0.19, 0.5, 0.25, 0.25, "clay", "Brick")
	Parts.box(m, f, 0.3, 0.55, 0.19, 0.5, 0.25, 0.25, "clay", "Brick")
end

-- Adobe Wall: a smooth mud wall with a rounded top and rounded ends, two roof beams poking out of its face.
M.adobe = function(m, f)
	post(m, f, 0, 0.75, 0, 2, 1, 0.5, "sand_dark", "Wall")
	Parts.log(m, f, 0, 0.75, 0, 2, 0.5, "sand_dark", "Top")
	for _, x in { -1, 1 } do
		Parts.cyl(m, f, x, 0.25, 0, 0.5, 1, "sand_dark", "End")
		Parts.ball(m, f, x, 0.75, 0, 0.5, "sand_dark", "Round")
	end
	for _, x in { -0.5, 0.5 } do
		Parts.box(m, f, x, 0.56, 0.22, 0.25, 0.25, 0.25, "wood_dark", "Beam")
	end
end

-- Snowbank: a bank of packed snow, lumpy at its ends, an icy crust along its face with blue icicles hanging from it.
M.icewall = function(m, f)
	post(m, f, 0, 0.5, 0, 2, 0.75, 0.5, "snow", "Bank")
	Parts.log(m, f, 0, 0.55, 0, 2, 0.5, "snow", "Top")
	for _, x in { -1, 1 } do
		Parts.ball(m, f, x, 0.45, 0, 0.75, "snow", "Lump")
	end
	Parts.box(m, f, 0, 0.66, 0.24, 1.5, 0.25, 0.25, "ice", "Crust")
	post(m, f, -0.45, 0.6, 0.26, 0.25, 0.5, 0.25, "screen_on", "Icicle")
	post(m, f, 0.05, 0.6, 0.26, 0.25, 0.25, 0.25, "screen_on", "Icicle")
	post(m, f, 0.5, 0.6, 0.26, 0.25, 0.5, 0.25, "screen_on", "Icicle")
end

-- Shell Wall: a white stone wall with a sandy coping, scallops, a spiral and a bit of sea glass set in its face.
M.shellwall = function(m, f)
	Parts.box(m, f, 0, 0.375, 0, 2.5, 0.75, 0.5, "white", "Wall")
	Parts.box(m, f, 0, 0.875, 0, 2.5, 0.25, 0.75, "sand", "Coping")
	Parts.ball(m, f, -0.55, 0.45, 0.1, 0.5, "pink", "Scallop")
	Parts.ball(m, f, 0.5, 0.32, 0.1, 0.5, "coral", "Scallop")
	point(m, f, 0.02, 0.6, 0.22, 0.25, "teal", "SeaGlass")
	Parts.box(m, f, -0.05, 0.2, 0.22, 0.25, 0.25, 0.25, "orange", "Spiral")
	Parts.ball(m, f, 0.3, 1.02, 0.05, 0.25, "cream", "Shell")
end

-- Crystal Fence: a dark stone sill, a stout crystal at each end with a glowing point, three glowing shards leaning
-- between them.
M.crystalfence = function(m, f)
	Parts.box(m, f, 0, 0.1, 0, 2.5, 0.25, 0.5, "basalt", "Sill")
	for _, x in { -1, 1 } do
		post(m, f, x, 0.95, 0, 0.5, 1, 0.5, "crystal", "Crystal").CFrame = f * CFrame.new(x, 0.45, 0) * CFrame.Angles(0, QUARTER, 0)
		peak(m, f, x, 1.2, 0, 0.5, "crystal", "Point", true)
	end
	for _, s in { { -0.45, 0.45, 0.32 }, { 0.05, 0.55, -0.1 }, { 0.5, 0.4, -0.38 } } do
		Parts.at(m, f, CFrame.new(s[1], s[2], 0) * CFrame.Angles(0, 0, s[3]) * CFrame.Angles(0, QUARTER, 0), 0.25, 0.75, 0.25, "crystal", "Shard", true)
	end
end

------------------------------------------------------------------ the water pieces' small parts

-- Short dashes of foam on the water round (x, z), r out: n of them, the first at angle a0 (radians from +X toward +Z),
-- each `len` long along the ring. White water lapping where a thing meets the water.
local function lap(m: Model, f: CFrame, x: number, z: number, r: number, n: number, a0: number, len: number?)
	for k = 0, n - 1 do
		local a = a0 + k * 2 * math.pi / n
		local p = Parts.at(m, f, CFrame.new(x + math.cos(a) * r, 0.01, z + math.sin(a) * r) * CFrame.Angles(0, -a, 0), 0.25, 0.25, len or 0.5, "foam", "Foam")
		p:SetAttribute("PixelWater", 3)
	end
end

-- A tuft of blades standing at (x, y, z): n of them fanned out across `turn` (radians about Y; 0 fans them along X),
-- h tall, in turn in the given greens.
local function tuft(m: Model, f: CFrame, x: number, y: number, z: number, n: number, h: number, turn: number, greens: { string })
	for j = 0, n - 1 do
		local lean = (j - (n - 1) / 2) * 0.5
		local cf = CFrame.new(x, y, z) * CFrame.Angles(0, turn, 0) * CFrame.Angles(0, 0, lean) * CFrame.new(0, h / 2, 0)
		Parts.at(m, f, cf, 0.25, h, 0.25, greens[j % #greens + 1], "Blade")
	end
end

-- A fern at (x, y, z): one frond 0.5 long leaning out toward each angle in `toward` (radians from +X toward +Z), the
-- middle one darker.
local function fern(m: Model, f: CFrame, x: number, y: number, z: number, toward: { number })
	for j, psi in toward do
		local cf = CFrame.new(x, y, z) * CFrame.Angles(0, -psi, 0) * CFrame.Angles(0, 0, -0.6) * CFrame.new(0, 0.25, 0)
		Parts.at(m, f, cf, 0.25, 0.5, 0.25, if j == 2 then "leaf_dark" else "leaf", "Fern")
	end
end

-- Every part in `list` moving the same way (Parts.move): one rigid group.
local function ride(list: { BasePart }, kind: string, hub: Vector3, axis: string, speed: number, amp: number, phase: number)
	for _, p in list do
		Parts.move(p, kind, hub, axis, speed, amp, phase)
	end
end

-- A lantern hung from a hook at `hub`, swinging a little round it along `axis` ("X": to and fro along Z, "Z": side to
-- side): a short cord, a dark cap w x d over the lit glass in `glass`, and with `foot` a dark foot under it (a paper
-- lantern's two rings). It hangs 1 below the hook, 1.25 with a foot.
local function hangLantern(m: Model, f: CFrame, hub: Vector3, axis: string, phase: number, glass: string, w: number, d: number, foot: boolean)
	local x, y, z = hub.X, hub.Y, hub.Z
	local parts = {
		Parts.box(m, f, x, y - 0.125, z, 0.25, 0.25, 0.25, "black", "Cord"),
		Parts.box(m, f, x, y - 0.375, z, w, 0.25, d, "black", "LanternCap"),
		Parts.glow(m, f, x, y - 0.75, z, w, 0.5, d, glass, "Lantern"),
	}
	if foot then
		table.insert(parts, Parts.box(m, f, x, y - 1.125, z, w, 0.25, d, "black", "LanternFoot"))
	end
	ride(parts, "swing", hub, axis, 1.5, 0.16, phase)
end

-- A round leaf floating at (x, y, z) (y its middle): the leaf (dia across, in `c`), a paler sheen to the top left if
-- given, the split from its middle out to the rim at angle `cut` (radians from +X toward +Z) in a deeper green. Returns
-- its parts (to set them moving).
local function pad(m: Model, f: CFrame, x: number, y: number, z: number, dia: number, c: string, sheen: string?, cut: number?): { BasePart }
	local out = { Parts.cyl(m, f, x, y, z, dia, 0.25, c, "Pad") }
	if sheen and dia >= 0.75 then
		table.insert(out, Parts.cyl(m, f, x - dia * 0.12, y + 0.03, z - dia * 0.1, dia - 0.5, 0.25, sheen, "Pad"))
	end
	if cut then
		local len = if dia >= 1 then 0.5 else 0.25
		local r = dia / 2 - len / 2
		local cf = CFrame.new(x + math.cos(cut) * r, y + 0.045, z + math.sin(cut) * r) * CFrame.Angles(0, math.pi / 2 - cut, 0)
		table.insert(out, Parts.at(m, f, cf, 0.25, 0.25, len, if c == "leaf_dark" then "chalk" else "leaf_dark", "Split"))
	end
	return out
end

------------------------------------------------------------------ bridges and the dock (over water and grass)

-- The plank bridge's deck top at z: low on the banks, a gentle hump mid-stream.
local function plankY(z: number): number
	return 0.22 + 0.4 * (1 - (z / 3) ^ 2)
end

-- Plank Bridge (2 x 6): ten planks of two tones laid across two beams in a gentle hump, a crack of water between each,
-- every third one shorter and set off to one side; stone sills under the ends. Four posts along each side carry a pale
-- hand rail; the corner posts are taller, lashed with rope and capped. A lantern hangs from a crook on the near left
-- post and sways; moss grows on the end planks and a pail stands at the far end.
M.plankbridge = function(m, f)
	for _, x in { -0.625, 0.625 } do
		for _, s in { -1, 1 } do
			seg(m, f, V(x, plankY(3) - 0.375, 3 * s), V(x, plankY(0) - 0.375, 0), 0.25, 0.25, "wood_dark", "Beam")
		end
	end
	for i = 0, 9 do
		local z = -2.7 + i * 0.6
		local short = i % 3 == 1
		local x = if short then (if i % 2 == 0 then 0.125 else -0.125) else 0
		seg(m, f, V(x, plankY(z - 0.25) - 0.125, z - 0.25), V(x, plankY(z + 0.25) - 0.125, z + 0.25), if short then 1.75 else 2, 0.25, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	for _, s in { -1, 1 } do
		Parts.box(m, f, 0, 0.0, 2.75 * s, 2, 0.25, 0.5, "rock", "Sill")
	end
	-- the posts and the rails along both sides
	local zs = { -2.45, -0.85, 0.85, 2.45 }
	for _, x in { -0.75, 0.75 } do
		for k, z in zs do
			local corner = k == 1 or k == #zs
			local lamp = corner and x < 0 and z > 0
			local above = if lamp then 1.75 elseif corner then 1 else 0.5
			post(m, f, x, plankY(z) + above, z, 0.25, above + 0.5, 0.25, "wood_dark", "Post")
			if corner then
				Parts.box(m, f, x, plankY(z) + 0.75, z, 0.5, 0.25, 0.5, "straw", "Lashing")
				Parts.box(m, f, x, plankY(z) + above + 0.06, z, 0.25, 0.25, 0.25, "sand", "Cap")
			end
			if k < #zs then
				local z1 = zs[k + 1]
				seg(m, f, V(x, plankY(z) + 0.5, z), V(x, plankY(z1) + 0.5, z1), 0.25, 0.25, "wood", "Rail")
			end
		end
	end
	-- the lantern on its crook (it sways along the bridge)
	local lampTop = plankY(2.45) + 1.75
	Parts.box(m, f, -0.5, lampTop - 0.06, 2.45, 0.75, 0.25, 0.25, "wood_dark", "Crook")
	hangLantern(m, f, V(-0.2, lampTop - 0.19, 2.45), "X", 0, "yellow", 0.5, 0.5, false)
	-- moss on the end planks, a pail
	Parts.box(m, f, -0.62, plankY(-2.7) + 0.02, -2.75, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.7, plankY(2.7) + 0.02, 2.8, 0.25, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, -0.85, plankY(-1.5) + 0.02, -1.5, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.cyl(m, f, -0.3, plankY(-2.1) + 0.2, -2.1, 0.5, 0.5, "steel", "Pail")
	Parts.cyl(m, f, -0.3, plankY(-2.1) + 0.33, -2.1, 0.25, 0.25, "water", "PailWater")
end

-- Little Dock (3 x 4): a deck of seven boards on piles, framed by dark beams and braced across the piles on its
-- sides, its land end at -Z with a stone step and stones by it. At the far end two mooring posts wound with rope (the
-- right one tall, a lantern hung from its arm, swaying) and a ladder down into the water; foam round the piles in the
-- water. On the deck a coil of rope tied to the left post, a crate with a cushion, a creel with a fish's tail out of
-- it, a pail with a cane rod stood in it, the rod's tip out over the side above a red float that bobs.
M.dock = function(m, f)
	local top = 0.55
	for _, x in { -1.125, 1.125 } do
		for _, z in { -1.5, 0.25 } do
			Parts.cyl(m, f, x, top - 0.25 - 0.5, z, 0.5, 1, "wood_dark", "Pile")
		end
		local ptop = if x > 0 then 2.25 else 1.0
		Parts.cyl(m, f, x, (ptop - 0.5) / 2, 1.6, 0.5, ptop + 0.5, "wood_dark", "Post")
		Parts.cyl(m, f, x, 0.8, 1.6, 0.75, 0.25, "straw", "Wrap")
		Parts.cyl(m, f, x, ptop + 0.06, 1.6, 0.5, 0.25, "wood", "PostCap")
		Parts.box(m, f, x, top - 0.125, 0, 0.25, 0.25, 4, "wood_dark", "Beam")
		-- the braces on the outside of the piles (none by the float on the right)
		local s = if x > 0 then 1 else -1
		seg(m, f, V(1.3 * s, top - 0.3, -1.5), V(1.3 * s, 0.0, 0.25), 0.25, 0.25, "wood", "Brace")
		if s < 0 then
			seg(m, f, V(-1.3, top - 0.3, 0.25), V(-1.3, 0.0, 1.6), 0.25, 0.25, "wood", "Brace")
		end
		-- white water round the piles and posts standing in the stream
		for _, z in { 0.25, 1.6 } do
			local p = Parts.cyl(m, f, x, -0.02, z, 0.75, 0.25, "foam", "Foam")
			p:SetAttribute("PixelWater", 3)
		end
	end
	for i = 0, 6 do
		local short = i % 3 == 1
		Parts.box(m, f, if short then 0.06 else 0, top - 0.125, -1.75 + i * 3.5 / 6, if short then 1.75 else 2, 0.25, 0.5, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	-- the ladder: its rails rise above the deck as handholds
	for _, x in { -0.3, 0.3 } do
		post(m, f, x, top + 0.3, 1.875, 0.25, 1, 0.25, "wood_dark", "Ladder")
	end
	Parts.box(m, f, 0, 0.12, 1.875, 0.5, 0.25, 0.25, "wood", "Rung")
	-- the lantern on the tall post's arm
	Parts.box(m, f, 0.86, 2.1, 1.6, 0.75, 0.25, 0.25, "wood_dark", "Arm")
	hangLantern(m, f, V(0.6, 1.975, 1.6), "X", 0, "yellow", 0.5, 0.5, false)
	-- a coil of rope by the left post, tied to it
	Parts.cyl(m, f, -0.6, top + 0.125, 1.1, 0.75, 0.25, "straw", "Coil")
	Parts.cyl(m, f, -0.6, top + 0.14, 1.1, 0.25, 0.25, "wood_dark", "CoilEye")
	seg(m, f, V(-0.85, top + 0.15, 1.2), V(-1.0, 0.8, 1.5), 0.25, 0.25, "straw", "Rope")
	-- a crate to sit on, a cushion on it
	Parts.box(m, f, -0.55, top + 0.25, -1.1, 0.5, 0.5, 0.5, "wood", "Crate")
	Parts.box(m, f, -0.55, top + 0.25, -1.1, 0.75, 0.25, 0.5, "wood_dark", "Strap")
	Parts.box(m, f, -0.55, top + 0.56, -1.1, 0.5, 0.25, 0.5, "sofa", "Cushion")
	-- a creel, its lid half open and a fish's tail out of it
	Parts.box(m, f, -0.55, top + 0.25, 0.3, 0.5, 0.5, 0.5, "straw", "Creel")
	Parts.box(m, f, -0.55, top + 0.56, 0.18, 0.5, 0.25, 0.25, "wood_dark", "Lid")
	Parts.at(m, f, CFrame.new(-0.45, top + 0.6, 0.42) * CFrame.Angles(0, 0.4, 0.5), 0.25, 0.25, 0.25, "teal", "Fish")
	-- a pail with the rod stood in it, its tip out over the float
	Parts.cyl(m, f, 0.45, top + 0.25, 0.95, 0.5, 0.5, "blue", "Bucket")
	Parts.cyl(m, f, 0.45, top + 0.38, 0.95, 0.25, 0.25, "water", "BucketWater")
	seg(m, f, V(0.45, top + 0.3, 0.95), V(1.375, top + 0.95, 0.95), 0.25, 0.25, "bamboo", "Rod")
	ride({
		Parts.box(m, f, 1.375, 0.08, 0.95, 0.25, 0.25, 0.25, "berry_red", "Float"),
		Parts.box(m, f, 1.375, 0.28, 0.95, 0.25, 0.25, 0.25, "white", "Float"),
	}, "bob", V(1.375, 0.1, 0.95), "Z", 1.7, 0.07, 1.2)
	-- a step up from the grass, stones beside it
	Parts.box(m, f, 0, 0.12, -1.9, 1.5, 0.25, 0.25, "rock", "Step")
	Parts.box(m, f, 1.375, 0.1, -1.85, 0.25, 0.25, 0.25, "rock_dark", "Stone")
	Parts.box(m, f, -1.375, 0.08, -1.88, 0.25, 0.25, 0.25, "pavement", "Stone")
end

-- A rope's height at z along the rope bridge: lo mid-stream, hi at the posts (z = +-2.75).
local function sag(z: number, lo: number, hi: number): number
	return lo + (hi - lo) * (z / 2.75) ^ 2
end

-- Rope Bridge (2 x 6): four tall posts on the banks with pointed tops and rope wound round them, two deck ropes
-- sagging low over the water with slats hung on them, two hand ropes above tied down to the deck ropes every few
-- slats in a paler cord. A stone landing with a paler top at each end, stones and moss round it, tufts of grass by
-- the posts; a red flag on a pole above the far left post.
M.ropebridge = function(m, f)
	for _, x in { -0.75, 0.75 } do
		for _, s in { -1, 1 } do
			post(m, f, x, 1.75, 2.75 * s, 0.25, 2, 0.25, "wood_dark", "Post")
			Parts.cyl(m, f, x, 1.55, 2.75 * s, 0.5, 0.25, "straw", "Wrap")
			if not (x < 0 and s < 0) then
				point(m, f, x, 1.78, 2.75 * s, 0.25, "wood", "Point")
			end
		end
	end
	local zs = { -2.75, -1.4, 0, 1.4, 2.75 }
	for k = 1, 4 do
		local z0, z1 = zs[k], zs[k + 1]
		for _, x in { -0.75, 0.75 } do
			seg(m, f, V(x, sag(z0, 0.95, 1.6), z0), V(x, sag(z1, 0.95, 1.6), z1), 0.25, 0.25, "straw", "HandRope")
		end
		for _, x in { -0.625, 0.625 } do
			seg(m, f, V(x, sag(z0, 0.35, 0.8), z0), V(x, sag(z1, 0.35, 0.8), z1), 0.25, 0.25, "straw", "DeckRope")
		end
	end
	for _, z in { -2.1, -1.4, -0.7, 0, 0.7, 1.4, 2.1 } do
		for _, s in { -1, 1 } do
			seg(m, f, V(0.75 * s, sag(z, 0.95, 1.6) - 0.05, z), V(0.625 * s, sag(z, 0.35, 0.8) + 0.1, z), 0.25, 0.25, "sand_dark", "Tie")
		end
	end
	for i = 0, 9 do
		local z = -2.25 + i * 0.5
		local tilt = math.atan(2 * (0.8 - 0.35) * z / 2.75 ^ 2)
		local jig = ((i * 7) % 5 - 2) * 0.03
		Parts.at(m, f, CFrame.new(jig, sag(z, 0.35, 0.8) + 0.18, z) * CFrame.Angles(-tilt, jig, 0), 1.5, 0.25, 0.25, if i % 2 == 0 then "wood" else "sand_dark", "Slat")
	end
	-- the landings, their stones and moss, tufts by the posts
	for _, s in { -1, 1 } do
		post(m, f, 0, 0.55, 2.75 * s, 1.5, 0.75, 0.5, "rock", "Landing")
		Parts.box(m, f, -0.06 * s, 0.6, 2.75 * s, 1.25, 0.25, 0.5, "pavement", "LandingTop")
		Parts.box(m, f, 0.875 * s, 0.1, 2.35 * s, 0.25, 0.25, 0.5, "rock_dark", "Stone")
		Parts.box(m, f, 0.4 * s, 0.7, 2.9 * s, 0.5, 0.25, 0.25, "moss", "Moss")
		tuft(m, f, -0.875 * s, 0, 2.35 * s, 2, 0.5, math.pi / 2, { "leaf", "leaf_dark" })
	end
	-- the flag over the far left post
	post(m, f, -0.75, 2.45, -2.75, 0.25, 0.75, 0.25, "wood_dark", "FlagPole")
	Parts.box(m, f, -0.75, 2.2, -2.39, 0.25, 0.5, 0.5, "berry_red", "Flag")
	Parts.box(m, f, -0.75, 2.28, -2.1, 0.25, 0.25, 0.25, "berry_red", "Flag")
end

-- The stone bridge's deck top at z: a flat crown between z = -1 and 1, straight ramps down to the banks.
local function stoneY(z: number): number
	local a = math.abs(z)
	return if a <= 1 then 1.5 else 1.5 - (a - 1) * 0.675
end

-- Stone Bridge (3 x 6): one round arch of stones (two tones, standing a little proud of the sides) with a pale
-- keystone, under a paved hump with two steps across each ramp, the ramps filled down to the banks. Low parapets with
-- a pale coping, square end posts with pale caps; on two of them an iron crook holds a lantern that sways. Odd stones
-- in its sides, ivy trailing down the near side, moss, white water where the arch stands in the stream, stones and
-- grass at its feet on the banks.
M.stonebridge = function(m, f)
	local W = 2.5
	-- the arch: seven stones on a circle of radius 2.4 round (0, -1.25), springing at z = +-1.75 on the water
	local phiMax = math.asin(1.75 / 2.15)
	for k = 0, 6 do
		local phi = -phiMax + (k + 0.5) * (2 * phiMax / 7)
		local cf = CFrame.new(0, -1.25 + 2.4 * math.cos(phi), 2.4 * math.sin(phi)) * CFrame.Angles(phi, 0, 0)
		Parts.at(m, f, cf, W + 0.25, 0.5, 0.75, if k % 2 == 0 then "rock" else "rock_dark", "Voussoir")
	end
	Parts.box(m, f, 0, 1.12, 0, 3, 0.75, 0.5, "pavement", "Keystone")
	-- the deck: a flat crown and two ramps, steps across the ramps
	Parts.box(m, f, 0, 1.25, 0, W, 0.5, 2, "pavement", "Deck")
	for _, s in { -1, 1 } do
		seg(m, f, V(0, stoneY(0.9) - 0.25, 0.9 * s), V(0, stoneY(2.9) - 0.25, 2.9 * s), W, 0.5, "pavement", "Ramp")
		-- the fill under the ramp, down to the bank
		Parts.wedge(m, f, 0, 0.375, 2.375 * s, W, 0.75, 1.25, "rock", if s > 0 then math.pi else 0, "Fill")
		for _, z in { 1.55, 2.25 } do
			Parts.at(m, f, CFrame.new(0, stoneY(z), z * s) * CFrame.Angles(0.594 * s, 0, 0), 2, 0.25, 0.25, "sand_dark", "Step")
		end
	end
	-- the parapets with their coping, an end post with a cap at each corner
	for _, x in { -1.125, 1.125 } do
		Parts.box(m, f, x, stoneY(0) + 0.25, 0, 0.25, 0.5, 2, "rock_dark", "Parapet")
		Parts.box(m, f, x, stoneY(0) + 0.56, 0, 0.5, 0.25, 2, "pavement", "Coping")
		for _, s in { -1, 1 } do
			seg(m, f, V(x, stoneY(0.95) + 0.25, 0.95 * s), V(x, stoneY(2.55) + 0.25, 2.55 * s), 0.25, 0.5, "rock_dark", "Parapet")
			seg(m, f, V(x, stoneY(1.0) + 0.56, 1.0 * s), V(x, stoneY(2.4) + 0.56, 2.4 * s), 0.5, 0.25, "pavement", "Coping")
			post(m, f, x, stoneY(2.6) + 0.6, 2.6 * s, 0.5, 0.75, 0.5, "rock", "EndPost")
			Parts.box(m, f, x, stoneY(2.6) + 0.66, 2.6 * s, 0.75, 0.25, 0.75, "pavement", "PostCap")
		end
	end
	-- the lanterns: an iron crook on the near right and the far left end posts, the lantern hung in over the deck
	for _, c in { { 1.125, 2.6, 0 }, { -1.125, -2.6, 2.1 } } do
		local x, z = c[1], c[2]
		local capTop = stoneY(2.6) + 0.79
		local s = if x > 0 then 1 else -1
		post(m, f, x, capTop + 0.95, z, 0.25, 1, 0.25, "steel_dark", "Crook")
		Parts.box(m, f, x - 0.3 * s, capTop + 0.85, z, 0.75, 0.25, 0.25, "steel_dark", "Crook")
		hangLantern(m, f, V(x - 0.625 * s, capTop + 0.72, z), "X", c[3], "yellow", 0.5, 0.5, false)
	end
	-- odd stones in the sides
	for _, x in { -1.3, 1.3 } do
		Parts.box(m, f, x, 0.35, 2.2, 0.25, 0.25, 0.5, "rock_dark", "Stone")
		Parts.box(m, f, x, 0.3, -2.3, 0.25, 0.25, 0.5, "pavement", "Stone")
		Parts.box(m, f, x, 1.15, -1.3, 0.25, 0.25, 0.5, "rock_dark", "Stone")
		Parts.box(m, f, x, 1.35, 0.7, 0.25, 0.25, 0.5, "rock_dark", "Stone")
	end
	-- ivy trailing down the near side, moss
	Parts.box(m, f, 1.3, 1.75, -0.55, 0.25, 0.5, 0.5, "leaf_dark", "Ivy")
	Parts.box(m, f, 1.32, 1.4, -0.7, 0.25, 0.5, 0.25, "leaf", "Ivy")
	Parts.box(m, f, 1.32, 1.05, -0.62, 0.25, 0.5, 0.25, "leaf_dark", "Ivy")
	Parts.box(m, f, 1.3, 1.8, -0.15, 0.25, 0.25, 0.5, "leaf", "Ivy")
	Parts.box(m, f, 1.3, 0.12, 1.95, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, -1.3, 0.15, -2.0, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, -1.0, stoneY(1.7) + 0.72, 1.7, 0.5, 0.25, 0.5, "moss", "Moss")
	-- white water at the arch's feet
	for _, s in { -1, 1 } do
		foam(m, f, 0, 0.0, 1.62 * s, 2.75, 0.25, 0.25)
	end
	-- stones and grass at its feet on the banks
	Parts.box(m, f, 1.375, 0.08, 2.85, 0.25, 0.25, 0.25, "rock", "Stone")
	Parts.box(m, f, -1.375, 0.08, -2.85, 0.25, 0.25, 0.25, "rock_dark", "Stone")
	tuft(m, f, -1.37, 0, 2.7, 2, 0.5, math.pi / 2, { "leaf", "leaf_dark" })
	tuft(m, f, 1.37, 0, -2.7, 2, 0.5, math.pi / 2, { "leaf_dark", "leaf" })
end

-- Waterwheel (3 x 2): an open wheel standing in the current, its axle along Z: a pale rim of eight felloes on its
-- face, a dark cross of spokes, eight paddles set behind the rim dipping into the water (the Rim, Spoke and Paddle
-- parts turn: Controllers/Spinners). An iron hub with a nut, the axle running back into an iron bearing on a stone
-- pier. Behind it a stone race wall with a pale coping, stones in its face, moss and a tuft on it; a stone in the
-- stream. White water where the paddles dip, spray thrown up where they come out, foam running off.
M.waterwheel = function(m, f)
	local cy = 1.2
	for k = 0, 7 do
		local a = k * QUARTER
		Parts.at(m, f, CFrame.new(math.cos(a), cy + math.sin(a), 0.3) * CFrame.Angles(0, 0, a + math.pi / 2), 0.75, 0.25, 0.25, "sand_dark", "Rim")
	end
	for k = 0, 1 do
		Parts.at(m, f, CFrame.new(0, cy, 0.3) * CFrame.Angles(0, 0, k * math.pi / 2 + QUARTER), 1.75, 0.25, 0.25, "wood_dark", "Spoke")
	end
	for k = 0, 7 do
		local a = k * QUARTER + QUARTER / 2
		Parts.at(m, f, CFrame.new(math.cos(a) * 1.2, cy + math.sin(a) * 1.2, 0) * CFrame.Angles(0, 0, a), 0.5, 0.25, 0.5, "wood", "Paddle")
	end
	Parts.logZ(m, f, 0, cy, 0, 0.75, 0.5, "steel_dark", "Hub")
	Parts.box(m, f, 0, cy, 0.45, 0.25, 0.25, 0.25, "steel", "Nut")
	Parts.logZ(m, f, 0, cy, -0.5, 1, 0.25, "steel_dark", "Axle")
	-- the race wall behind, the pier on it under the axle, the bearing
	Parts.box(m, f, 0, 0.15, -0.875, 3, 0.75, 0.25, "rock", "Wall")
	Parts.box(m, f, 0, 0.6, -0.75, 3, 0.25, 0.5, "pavement", "Coping")
	for _, s in { { x = -1.0, y = 0.2, w = 0.75, c = "rock_dark" }, { x = 0.85, y = 0.05, w = 0.5, c = "pavement" }, { x = 0.2, y = 0.3, w = 0.5, c = "rock_dark" } } do
		Parts.box(m, f, s.x, s.y, -0.72, s.w, 0.25, 0.25, s.c, "Stone")
	end
	Parts.box(m, f, 0, 0.92, -0.85, 0.75, 0.5, 0.25, "rock_dark", "Pier")
	Parts.box(m, f, 0, cy, -0.85, 0.5, 0.25, 0.25, "steel_dark", "Bearing")
	Parts.box(m, f, -0.95, 0.75, -0.85, 0.75, 0.25, 0.25, "moss", "Moss")
	tuft(m, f, 1.1, 0.68, -0.85, 3, 0.5, 0.1, { "leaf", "leaf_dark" })
	Parts.box(m, f, 1.15, 0.05, 0.7, 0.5, 0.25, 0.5, "rock", "Stone")
	Parts.box(m, f, 1.2, 0.15, 0.78, 0.25, 0.25, 0.25, "moss", "Moss")
	-- white water: where the paddles dip, spray where they rise (the wheel turns downstream toward -X), foam running off
	foam(m, f, 0, 0.0, 0, 1.5, 0.25, 0.75)
	foam(m, f, -0.95, 0.03, 0.1, 0.5, 0.25, 0.5).Name = "Spray"
	foam(m, f, -1.2, 0.0, 0.35, 0.5, 0.25, 0.25)
	foam(m, f, -1.25, 0.0, -0.3, 0.5, 0.25, 0.25)
	foam(m, f, 0.85, 0.0, 0.55, 0.25, 0.25, 0.5)
end

-- The moon bridge's deck top at z: a high round hump.
local function moonY(z: number): number
	return 0.15 + 2 * math.cos(math.pi * z / 6)
end

-- Moon Bridge (3 x 6): a high red arch: two curved stringers, steps of wood between them, a railing of posts and a
-- curved top rail on each side, gold caps on the end posts. Stone footings under the stringers' ends and a stone
-- threshold at each end, grass by them; two paper lanterns hung outside the rail, one each side, swaying. The water
-- shows through under it.
M.moonbridge = function(m, f)
	for i = 0, 10 do
		local z = -2.5 + i * 0.5
		Parts.box(m, f, 0, moonY(z) - 0.125, z, 2, 0.25, 0.5, if i % 2 == 0 then "wood" else "wood_dark", "Step")
	end
	for _, x in { -1.125, 1.125 } do
		for k = 0, 11 do
			local z0, z1 = -3 + k * 0.5, -2.5 + k * 0.5
			seg(m, f, V(x, moonY(z0) - 0.25, z0), V(x, moonY(z1) - 0.25, z1), 0.25, 0.5, "berry_red", "Stringer")
		end
		local zs = { -2.5, -1.5, -0.5, 0.5, 1.5, 2.5 }
		for k, z in zs do
			post(m, f, x, moonY(z) + 0.75, z, 0.25, 0.75, 0.25, "berry_red", "RailPost")
			if k < #zs then
				local z1 = zs[k + 1]
				seg(m, f, V(x, moonY(z) + 0.65, z), V(x, moonY(z1) + 0.65, z1), 0.25, 0.25, "berry_red", "Rail")
			end
		end
		for _, z in { -2.5, 2.5 } do
			Parts.box(m, f, x, moonY(z) + 0.875, z, 0.25, 0.25, 0.25, "gold", "Cap")
		end
		-- the footings
		for _, s in { -1, 1 } do
			Parts.box(m, f, x, 0.05, 2.75 * s, 0.75, 0.25, 0.5, "rock", "Footing")
		end
	end
	for _, s in { -1, 1 } do
		Parts.box(m, f, 0, 0.06, 2.875 * s, 2, 0.25, 0.25, "pavement", "Threshold")
		tuft(m, f, 1.37 * s, 0, 2.35 * s, 2, 0.5, math.pi / 2, { "leaf", "leaf_dark" })
	end
	-- the lanterns, hung from hooks on the rail's outside halfway between two posts
	local railY = moonY(0.5) + 0.65 + (moonY(1.5) - moonY(0.5)) * 0.5
	for _, c in { { 1, 1.0, 0 }, { -1, -1.0, 1.9 } } do
		local s, z = c[1], c[2]
		Parts.box(m, f, 1.375 * s, railY, z, 0.25, 0.25, 0.25, "black", "Hook")
		hangLantern(m, f, V(1.375 * s, railY - 0.125, z), "X", c[3], "orange", 0.25, 0.5, true)
	end
end

------------------------------------------------------------------ on the water (floating, about y 0 to 0.25)

-- Lily Pads (2 x 2): five round leaves in two greens at their own heights across the water, each but the smallest
-- split to its middle, the big ones with a paler sheen; a white lily open on one (a star of petals, a pink cup, a
-- yellow heart) and a pink bud on another, those two pads riding the ripples; a small pink flower; a frog sitting on
-- the pad at the front; foam where the pads meet the water.
M.lilypads = function(m, f)
	-- (each moving pad has the water round it to itself: no other pad under or over it)
	local a = pad(m, f, -0.45, 0.06, -0.4, 1, "leaf_dark", "leaf", math.rad(110))
	table.insert(a, Parts.turned(m, f, -0.3, 0.24, -0.5, 0.5, 0.25, 0.5, QUARTER, "white", "Petals"))
	table.insert(a, Parts.box(m, f, -0.3, 0.24, -0.5, 0.5, 0.25, 0.5, "white", "Petals"))
	table.insert(a, Parts.turned(m, f, -0.3, 0.36, -0.5, 0.25, 0.25, 0.25, QUARTER, "cherry", "Petals"))
	table.insert(a, Parts.box(m, f, -0.3, 0.45, -0.5, 0.25, 0.25, 0.25, "yellow", "FlowerHeart"))
	ride(a, "bob", V(-0.45, 0.06, -0.4), "X", 1.1, 0.05, 0)
	local d = pad(m, f, 0.55, 0.065, -0.5, 0.75, "leaf", nil, math.rad(200))
	table.insert(d, Parts.box(m, f, 0.62, 0.25, -0.45, 0.25, 0.25, 0.25, "leaf_dark", "Sepal"))
	table.insert(d, point(m, f, 0.62, 0.42, -0.45, 0.25, "cherry", "Bud"))
	ride(d, "bob", V(0.55, 0.065, -0.5), "Z", 1.3, 0.05, 2.4)
	-- the still ones
	pad(m, f, 0.45, 0.07, 0.45, 1, "leaf", "green", math.rad(130))
	pad(m, f, -0.5, 0.08, 0.55, 0.75, "leaf_dark", nil, math.rad(-20))
	pad(m, f, 0.1, 0.09, 0.12, 0.5, "leaf_dark")
	Parts.turned(m, f, -0.55, 0.25, 0.6, 0.5, 0.25, 0.5, 0.3, "pink", "Flower")
	Parts.box(m, f, -0.55, 0.36, 0.6, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	-- the frog, facing the view
	local fr = f * CFrame.new(0.5, 0, 0.5) * CFrame.Angles(0, 0.5, 0)
	Parts.box(m, fr, 0, 0.3, -0.05, 0.75, 0.25, 0.25, "moss", "Frog")
	Parts.box(m, fr, 0, 0.36, 0.1, 0.5, 0.25, 0.5, "moss", "Frog")
	Parts.box(m, fr, 0, 0.28, 0.3, 0.5, 0.25, 0.25, "bamboo", "Throat")
	for _, x in { -0.17, 0.17 } do
		Parts.box(m, fr, x, 0.55, 0.2, 0.25, 0.25, 0.25, "cream", "Eye")
	end
	foam(m, f, 0.05, 0.0, -0.85, 0.5, 0.25, 0.25)
	foam(m, f, 0.85, 0.0, -0.05, 0.25, 0.25, 0.5)
end

-- Reeds (2 x 2): four clumps of tall blades fanned out in three greens from tussocks in the water, the outer blades
-- bent over at their tips, three cattails standing up out of them with brown heads, a blue dragonfly resting on the
-- tallest; a purple iris in flower between the clumps, duckweed and white water lapping at the tussocks.
M.reeds = function(m, f)
	local greens = { "leaf", "moss", "leaf_dark" }
	local clumps = { { -0.4, -0.4 }, { 0.45, -0.3 }, { -0.3, 0.45 }, { 0.4, 0.45 } }
	for k, c in clumps do
		Parts.cyl(m, f, c[1], 0.02, c[2], 0.5, 0.25, "swamp", "Tussock")
		-- (the blades fan out along the rim, so the clump keeps to its corner)
		local yaw = -(math.atan2(c[2], c[1]) + math.pi / 2) + 0.12 * (k - 2)
		for j = 0, 2 do
			local h = 1 + ((j + k) % 3) * 0.25
			local lean = (j - 1) * 0.3 + 0.05
			local base = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, lean)
			Parts.at(m, f, base * CFrame.new(0, h / 2, 0), 0.25, h, 0.25, greens[j + 1], "Blade")
			if j ~= 1 then
				Parts.at(m, f, base * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, lean) * CFrame.new(0, 0.125, 0), 0.25, 0.5, 0.25, greens[j + 1], "Blade")
			end
		end
	end
	for k, c in { { -0.4, -0.35, 1.75 }, { 0.45, -0.25, 1.5 }, { -0.25, 0.45, 1.5 } } do
		local base = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0.06 * k - 0.1, 0, 0.08 * (k - 2))
		Parts.at(m, f, base * CFrame.new(0, c[3] / 2, 0), 0.25, c[3], 0.25, "moss", "Stalk")
		Parts.at(m, f, base * CFrame.new(0, c[3] - 0.42, 0), 0.25, 0.5, 0.25, "wood_dark", "Cattail")
		if k == 1 then
			-- the dragonfly on its tip
			Parts.at(m, f, base * CFrame.new(0, c[3] + 0.06, 0), 0.25, 0.25, 0.5, "blue", "Dragonfly")
			Parts.at(m, f, base * CFrame.new(0, c[3] + 0.12, -0.05), 0.75, 0.25, 0.25, "ice", "Wings")
		end
	end
	-- the iris
	Parts.box(m, f, 0.05, 0.4, 0.05, 0.25, 0.75, 0.25, "leaf", "Stem")
	Parts.turned(m, f, 0.05, 0.85, 0.05, 0.5, 0.25, 0.5, QUARTER, "purple", "Flower")
	Parts.box(m, f, 0.05, 0.95, 0.05, 0.25, 0.25, 0.25, "yellow", "FlowerHeart")
	-- duckweed and white water
	for _, d in { { 0.15, -0.75 }, { -0.8, 0.1 }, { 0.8, 0.15 } } do
		Parts.cyl(m, f, d[1], 0.0, d[2], 0.25, 0.25, "green", "Duckweed")
	end
	lap(m, f, 0.5, -0.35, 0.4, 2, 1.0)
	lap(m, f, -0.35, 0.5, 0.4, 2, 0.1)
end

-- Stepping Stones (2 x 2): two flat grey stones a pace apart along Z (so a row of tiles keeps the step), each on a dark
-- wet foot with a worn pale top and foam lapping round it, moss on its side, a crack across one; a snail on the near
-- stone, pebbles round them, a tuft of reeds, a small lily pad and a red leaf floating by.
M.steppingstones = function(m, f)
	for _, s in { { -0.25, -0.5, 0 }, { 0.3, 0.5, 0.3 } } do
		local x, z = s[1], s[2]
		Parts.cyl(m, f, x, 0.0, z, 1, 0.25, "rock_dark", "Footing")
		Parts.cyl(m, f, x, 0.18, z, 0.75, 0.25, "rock", "Stone")
		Parts.cyl(m, f, x - 0.06, 0.21, z - 0.06, 0.5, 0.25, "pavement", "Top")
		lap(m, f, x, z, 0.5, 2, s[3])
	end
	Parts.box(m, f, -0.5, 0.25, -0.75, 0.5, 0.25, 0.25, "moss", "Moss")
	Parts.box(m, f, 0.62, 0.22, 0.55, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.turned(m, f, 0.36, 0.24, 0.5, 0.5, 0.25, 0.25, 0.6, "rock_dark", "Crack")
	-- the snail
	Parts.box(m, f, 0.12, 0.37, 0.62, 0.25, 0.25, 0.5, "sand", "Snail")
	Parts.box(m, f, 0.12, 0.5, 0.55, 0.25, 0.25, 0.25, "coral", "Shell")
	-- pebbles
	Parts.cyl(m, f, 0.7, 0.0, -0.1, 0.5, 0.25, "rock_dark", "Pebble")
	Parts.cyl(m, f, 0.7, 0.08, -0.1, 0.25, 0.25, "rock", "Pebble")
	Parts.cyl(m, f, -0.75, 0.02, 0.35, 0.25, 0.25, "rock", "Pebble")
	Parts.cyl(m, f, 0.25, 0.02, -0.15, 0.25, 0.25, "pavement", "Pebble")
	-- the reeds, the lily pad, the leaf
	Parts.cyl(m, f, -0.68, 0.02, 0.7, 0.5, 0.25, "swamp", "Tussock")
	tuft(m, f, -0.68, 0, 0.7, 3, 0.5, -QUARTER, { "leaf", "moss", "leaf_dark" })
	pad(m, f, 0.7, 0.06, -0.75, 0.5, "leaf")
	Parts.turned(m, f, -0.62, 0.02, 0.0, 0.25, 0.25, 0.5, 0.9, "maple", "Leaf")
end

-- Duck Decoy (2 x 2): a painted wooden duck turned a little off square, bobbing and rocking: a pale body, brown wings
-- with a blue flash, a dark breast, a black tail, a green head with a white collar, black eyes and a yellow bill. A
-- yellow duckling decoy rides behind it, out of step. White water along the duck's sides and at its breast, two lily
-- pads (a bud on one, a white flower on the other), a feather and duckweed floating.
M.duckfloat = function(m, f)
	local yaw = math.rad(-25)
	local w = f * CFrame.Angles(0, yaw, 0)
	local d = w * CFrame.Angles(0, 0, math.rad(3))
	ride({
		Parts.box(m, d, -0.05, 0.3, 0, 1.25, 0.5, 0.75, "sand", "Body"),
		Parts.ball(m, d, 0.5, 0.36, 0, 0.75, "wood_dark", "Breast"),
		Parts.box(m, d, -0.15, 0.6, 0, 0.75, 0.25, 0.5, "wood", "Wings"),
		Parts.box(m, d, 0.1, 0.57, 0, 0.25, 0.25, 0.75, "blue", "Flash"),
		Parts.wedge(m, d, -0.8, 0.55, 0, 0.25, 0.25, 0.5, "black", -math.pi / 2, "Tail"),
		Parts.box(m, d, 0.55, 0.72, 0, 0.25, 0.25, 0.25, "white", "Collar"),
		Parts.ball(m, d, 0.57, 0.98, 0, 0.5, "teal", "Head"),
		Parts.box(m, d, 0.86, 0.92, 0, 0.25, 0.25, 0.25, "gold", "Bill"),
		Parts.box(m, d, 0.64, 1.04, 0.17, 0.25, 0.25, 0.25, "black", "Eye"),
		Parts.box(m, d, 0.64, 1.04, -0.17, 0.25, 0.25, 0.25, "black", "Eye"),
	}, "bob", V(0, 0.1, 0), "Z", 1.4, 0.08, 0)
	-- the duckling
	local k = f * CFrame.new(-0.6, 0, 0.55) * CFrame.Angles(0, yaw, 0)
	ride({
		Parts.box(m, k, 0, 0.18, 0, 0.5, 0.25, 0.5, "yellow", "Body"),
		Parts.box(m, k, 0.12, 0.4, 0, 0.25, 0.25, 0.25, "yellow", "Head"),
		Parts.box(m, k, 0.3, 0.38, 0, 0.25, 0.25, 0.25, "orange", "Bill"),
	}, "bob", V(-0.6, 0.1, 0.55), "Z", 1.7, 0.07, 2.1)
	-- white water, the pad, a feather
	for _, z in { -0.55, 0.55 } do
		Parts.box(m, w, 0.05, 0.01, z, 0.75, 0.25, 0.25, "foam", "Foam"):SetAttribute("PixelWater", 3)
	end
	Parts.box(m, w, 0.85, 0.01, 0, 0.25, 0.25, 0.5, "foam", "Foam"):SetAttribute("PixelWater", 3)
	pad(m, f, 0.65, 0.06, -0.65, 0.5, "leaf_dark")
	point(m, f, 0.7, 0.28, -0.62, 0.25, "cherry", "Bud")
	pad(m, f, 0.05, 0.07, 0.72, 0.5, "leaf")
	Parts.turned(m, f, 0.05, 0.22, 0.72, 0.25, 0.25, 0.25, QUARTER, "white", "Flower")
	Parts.turned(m, f, -0.2, 0.02, -0.75, 0.25, 0.25, 0.5, 1.2, "white", "Feather")
	for _, q in { { 0.85, 0.6 }, { -0.85, -0.2 }, { 0.2, -0.85 } } do
		Parts.cyl(m, f, q[1], 0.0, q[2], 0.25, 0.25, "green", "Duckweed")
	end
end

-- Rowboat (2 x 4): a little boat pointing +Z, moored: a teal hull with a white gunwale all round, a pointed bow with a
-- stem post, a square stern, a dark floor, two seats, a pair of oars shipped along the seats with red blades over the
-- stern, a coil of rope in the bow; the whole boat bobs and rocks on the water. A mooring stake by the bow with a
-- little lamp on top and a rope lashing, the painter tied from it to the stem; foam along the hull, at the bow and the
-- stern; a reed tuft by the bow.
M.rowboat = function(m, f)
	local y0 = -0.05
	local boat: { BasePart } = {}
	local function b(p: BasePart)
		table.insert(boat, p)
	end
	b(Parts.box(m, f, 0, y0 + 0.15, -0.25, 1, 0.25, 2.5, "wood_dark", "Floor"))
	b(Parts.box(m, f, 0, y0 + 0.15, 1.15, 0.5, 0.25, 0.75, "wood_dark", "BowFloor"))
	for _, x in { -0.625, 0.625 } do
		b(Parts.box(m, f, x, y0 + 0.3, -0.25, 0.25, 0.5, 2.5, "teal", "Side"))
		b(Parts.box(m, f, x, y0 + 0.6, -0.25, 0.25, 0.25, 2.5, "white", "Gunwale"))
		b(seg(m, f, V(x, y0 + 0.3, 0.95), V(0, y0 + 0.35, 1.85), 0.25, 0.5, "teal", "Bow"))
		b(seg(m, f, V(x, y0 + 0.6, 0.95), V(0, y0 + 0.65, 1.85), 0.25, 0.25, "white", "Gunwale"))
	end
	b(Parts.box(m, f, 0, y0 + 0.82, 1.78, 0.25, 0.25, 0.25, "wood_dark", "Stem"))
	b(Parts.box(m, f, 0, y0 + 0.3, -1.5, 1.5, 0.5, 0.25, "teal", "Stern"))
	b(Parts.box(m, f, 0, y0 + 0.6, -1.5, 1.5, 0.25, 0.25, "white", "Gunwale"))
	for _, z in { -0.85, 0.4 } do
		b(Parts.box(m, f, 0, y0 + 0.42, z, 1, 0.25, 0.5, "wood", "Seat"))
	end
	for _, x in { -0.3, 0.3 } do
		b(Parts.logZ(m, f, x, y0 + 0.62, -0.3, 2.5, 0.25, "sand", "Oar"))
		b(Parts.box(m, f, x, y0 + 0.6, -1.55, 0.25, 0.25, 0.5, "berry_red", "Blade"))
	end
	b(Parts.cyl(m, f, 0, y0 + 0.4, 1.2, 0.5, 0.25, "straw", "Rope"))
	ride(boat, "bob", V(0, 0.1, 0), "Z", 1.2, 0.09, 0)
	-- the stake, its painter to the stem
	post(m, f, 0.75, 0.95, 1.6, 0.25, 1.25, 0.25, "wood_dark", "Stake")
	Parts.box(m, f, 0.75, 1.0, 1.6, 0.25, 0.25, 0.25, "sand", "Cap")
	Parts.glow(m, f, 0.75, 1.25, 1.6, 0.25, 0.25, 0.25, "yellow", "Lantern")
	Parts.box(m, f, 0.75, 1.45, 1.6, 0.5, 0.25, 0.5, "black", "LanternCap")
	Parts.cyl(m, f, 0.75, 0.75, 1.6, 0.5, 0.25, "straw", "Lashing")
	seg(m, f, V(0.6, 0.75, 1.62), V(0.24, 0.75, 1.74), 0.25, 0.25, "straw", "Painter")
	-- white water along the hull, at the bow and the stern
	for _, x in { -0.85, 0.85 } do
		foam(m, f, x, 0.0, -0.4, 0.25, 0.25, 1.75)
	end
	foam(m, f, 0, 0.0, 1.87, 0.5, 0.25, 0.25)
	foam(m, f, 0.2, 0.0, -1.8, 0.75, 0.25, 0.25)
	-- the reeds by the bow
	Parts.cyl(m, f, -0.76, 0.02, 1.6, 0.5, 0.25, "swamp", "Tussock")
	tuft(m, f, -0.8, 0, 1.5, 3, 0.5, math.pi / 2, { "leaf", "moss", "leaf_dark" })
end

-- One lotus flower at (x, z), its base at y: green sepals under a star of deep pink petals, a ring of pale petals
-- cupped up round them, a seed head in the middle. Returns its parts.
local function lotusFlower(m: Model, f: CFrame, x: number, y: number, z: number, turn: number): { BasePart }
	local c = f * CFrame.new(x, y, z) * CFrame.Angles(0, turn, 0)
	local out = {
		Parts.box(m, c, 0, 0.0, 0, 0.5, 0.25, 0.5, "leaf_dark", "Sepal"),
		Parts.turned(m, c, 0, 0.1, 0, 0.75, 0.25, 0.75, QUARTER, "pink", "Petals"),
	}
	for k = 0, 3 do
		local a = k * math.pi / 2
		table.insert(out, Parts.at(m, c, CFrame.Angles(0, a, 0) * CFrame.new(0, 0.32, 0.22) * CFrame.Angles(0.45, 0, 0), 0.25, 0.5, 0.25, "cherry", "Petals"))
	end
	table.insert(out, Parts.box(m, c, 0, 0.32, 0, 0.25, 0.25, 0.25, "bamboo", "FlowerHeart"))
	return out
end

-- Lotus Flowers (2 x 2): round leaves flat on the water, two with a paler sheen, the big ones split to the middle, one
-- leaf curling up on its stalk; two pink flowers open (one with its leaf riding the ripples), a bud on a stalk, a seed
-- pod gone brown; a small leaf bobbing, foam where they meet the water.
M.lotus = function(m, f)
	-- the leaf and the flower that ride together, a small leaf bobbing on its own
	local a = pad(m, f, -0.45, 0.06, 0.45, 1, "leaf", "green", math.rad(200))
	for _, p in lotusFlower(m, f, -0.28, 0.27, 0.5, 0.2) do
		table.insert(a, p)
	end
	ride(a, "bob", V(-0.45, 0.06, 0.45), "X", 1.0, 0.05, 0)
	ride(pad(m, f, 0.7, 0.06, -0.7, 0.5, "leaf_dark"), "bob", V(0.7, 0.06, -0.7), "Z", 1.3, 0.05, 1.9)
	-- the still leaves
	pad(m, f, 0.6, 0.07, 0.55, 0.75, "leaf_dark", nil, math.rad(160))
	pad(m, f, 0.33, 0.08, -0.02, 0.75, "leaf", "green", math.rad(70))
	-- a leaf curling up out of the water on its stalk
	Parts.box(m, f, -0.5, 0.25, -0.45, 0.25, 0.5, 0.25, "leaf_dark", "Stalk")
	Parts.cyl(m, f, -0.5, 0.5, -0.5, 0.75, 0.25, "leaf_dark", "Leaf").CFrame = f * CFrame.new(-0.5, 0.55, -0.5) * CFrame.Angles(0.35, 0, -0.6) * CFrame.Angles(0, 0, math.pi / 2)
	-- the second flower, on its leaf
	lotusFlower(m, f, 0.45, 0.3, -0.15, -0.3)
	-- a bud on a stalk, a seed pod
	Parts.box(m, f, 0.65, 0.35, 0.5, 0.25, 0.5, 0.25, "leaf_dark", "Stalk")
	point(m, f, 0.65, 0.7, 0.5, 0.25, "pink", "Bud")
	Parts.box(m, f, 0.05, 0.35, -0.75, 0.25, 0.5, 0.25, "moss", "Stalk")
	Parts.cyl(m, f, 0.05, 0.65, -0.75, 0.5, 0.25, "wood", "SeedPod")
	lap(m, f, 0.33, -0.02, 0.5, 2, 0)
end

-- Little Waterfall (2 x 2): mossy rocks across the back, darker wet ledges at their feet and a pale chip lit on top, a
-- lower stone in the middle where a stream runs over the lip (white where it breaks) and falls into a small pool, a
-- white streak down the fall, a thin trickle down the right rock, spray thrown up and foam at the foot. Stones round
-- the pool with paler tops, pebbles, a lily pad on it, ferns at the sides and small flowers in the moss.
M.littlefall = function(m, f)
	-- the rocks
	post(m, f, -0.62, 1.25, -0.62, 0.75, 1.5, 0.75, "rock", "Rock")
	post(m, f, 0.62, 1.05, -0.62, 0.75, 1.25, 0.75, "rock_dark", "Rock")
	post(m, f, 0, 0.82, -0.62, 0.5, 1, 0.75, "rock", "Lip")
	Parts.box(m, f, -0.62, 0.1, -0.45, 0.75, 0.25, 0.75, "rock_dark", "Ledge")
	Parts.box(m, f, 0.62, 0.08, -0.45, 0.75, 0.25, 0.75, "basalt", "Ledge")
	Parts.at(m, f, CFrame.new(-0.68, 1.35, -0.68) * CFrame.Angles(0, 0.3, 0.15), 0.5, 0.25, 0.5, "rock_dark", "Rock")
	Parts.box(m, f, 0.5, 1.02, -0.72, 0.5, 0.25, 0.5, "rock", "Rock")
	Parts.box(m, f, -0.85, 1.0, -0.3, 0.25, 0.25, 0.25, "pavement", "Rock")
	-- moss on the tops and down a side, flowers in it
	Parts.box(m, f, -0.62, 1.3, -0.5, 0.75, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, 0.65, 1.1, -0.55, 0.75, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, -0.88, 0.85, -0.55, 0.25, 0.5, 0.5, "moss", "Moss")
	Parts.box(m, f, 0.87, 0.75, -0.65, 0.25, 0.25, 0.5, "leaf_dark", "Moss")
	for _, b in { { x = -0.75, y = 1.47, z = -0.45, c = "pink" }, { x = -0.45, y = 1.45, z = -0.6, c = "white" }, { x = 0.75, y = 1.25, z = -0.45, c = "yellow" } } do
		Parts.box(m, f, b.x, b.y, b.z, 0.25, 0.25, 0.25, b.c, "Flower")
	end
	-- the stream over the lip and the fall
	Parts.water(m, f, 0, 0.78, -0.62, 0.5, 0.75, "water", "Stream")
	foam(m, f, 0, 0.84, -0.3, 0.5, 0.25, 0.25)
	local fall = Parts.box(m, f, 0, 0.44, -0.15, 0.5, 0.75, 0.25, "shallow", "Fall")
	-- (falling water: streaks run down it in the pixel filter, "waterfalls having flowing water", 2026-11-14)
	fall:SetAttribute("PixelWater", 4)
	foam(m, f, 0.1, 0.4, -0.06, 0.25, 0.5, 0.25)
	-- a trickle down the right rock
	Parts.box(m, f, 0.38, 0.6, -0.2, 0.25, 0.75, 0.25, "shallow", "Trickle"):SetAttribute("PixelWater", 4)
	-- the pool, its foam and spray, its stones
	Parts.water(m, f, 0, -0.02, 0.4, 2, 1.25, "water", "Pool")
	foam(m, f, 0, 0.08, 0.1, 1, 0.25, 0.5)
	foam(m, f, 0.02, 0.1, 0.12, 0.5, 0.25, 0.25).Name = "Spray"
	foam(m, f, 0.4, 0.06, 0.05, 0.25, 0.25, 0.25)
	foam(m, f, -0.25, 0.06, 0.45, 0.5, 0.25, 0.25)
	for k, s in { { -0.75, 0.3 }, { -0.55, 0.75 }, { 0.2, 0.75 }, { 0.75, 0.75 }, { 0.75, 0.15 } } do
		Parts.box(m, f, s[1], 0.12, s[2], 0.5, 0.25, 0.5, if k % 2 == 0 then "rock_dark" else "rock", "Stone")
		if k % 2 == 1 then
			Parts.box(m, f, s[1] - 0.06, 0.17, s[2] - 0.06, 0.25, 0.25, 0.25, "pavement", "Stone")
		end
	end
	Parts.cyl(m, f, -0.3, 0.06, 0.85, 0.25, 0.25, "rock", "Pebble")
	pad(m, f, 0.3, 0.06, 0.55, 0.5, "leaf")
	-- the ferns: fronds fanning out at each side
	fern(m, f, -0.68, 0.15, -0.1, { 0.9, 1.6, 2.3 })
	fern(m, f, 0.6, 0.15, -0.1, { 0.5, 1.3, 2.2 })
end

-- One floating lantern at (x, z): a little raft, a glowing paper box (its light the "Flame" the sparks rise from),
-- a lid over it with a knob. Returns its parts.
local function floatLantern(m: Model, f: CFrame, x: number, z: number, turn: number, color: string, lid: string, h: number): { BasePart }
	local c = f * CFrame.new(x, 0, z) * CFrame.Angles(0, turn, 0)
	return {
		Parts.box(m, c, 0, 0.06, 0, 0.75, 0.25, 0.75, "wood_dark", "Raft"),
		Parts.box(m, c, 0, 0.175 + h / 2, 0, 0.5, h, 0.5, color, "Flame", true),
		Parts.box(m, c, 0, 0.25 + h, 0, 0.5, 0.25, 0.5, lid, "Lid"),
		Parts.box(m, c, 0, 0.45 + h, 0, 0.25, 0.25, 0.25, lid, "Knob"),
	}
end

-- Floating Lanterns (2 x 2): three paper lanterns on little rafts drifting apart (the one at the back taller), each
-- turned its own way, in warm colours, each bobbing out of step with the others; foam lapping at the rafts, a lily pad
-- with a bud and a candle burning on it, a petal or two floating.
M.waterlanterns = function(m, f)
	local lanterns = {
		{ x = -0.52, z = -0.5, turn = 0.3, c = "yellow", lid = "wood_dark", h = 0.75, foam = -0.2 },
		{ x = 0.52, z = -0.2, turn = -0.25, c = "orange", lid = "berry_red", h = 0.5, foam = -1.4 },
		{ x = -0.2, z = 0.48, turn = 0.6, c = "pink", lid = "wood_dark", h = 0.5, foam = 2.9 },
	}
	for i, l in lanterns do
		ride(floatLantern(m, f, l.x, l.z, l.turn, l.c, l.lid, l.h), "bob", V(l.x, 0.1, l.z), if i % 2 == 0 then "X" else "Z", 1.1 + i * 0.2, 0.07, i * 2.1)
		-- foam at the raft's side
		lap(m, f, l.x, l.z, 0.5, 1, l.foam)
	end
	pad(m, f, 0.65, 0.06, 0.65, 0.5, "leaf_dark")
	point(m, f, 0.75, 0.28, 0.58, 0.25, "pink", "Bud")
	Parts.box(m, f, 0.58, 0.28, 0.7, 0.25, 0.25, 0.25, "cream", "Candle")
	Parts.glow(m, f, 0.58, 0.48, 0.7, 0.25, 0.25, 0.25, "yellow", "Flame")
	Parts.turned(m, f, -0.82, 0.02, 0.15, 0.25, 0.25, 0.25, 0.4, "cherry", "Petal")
	Parts.turned(m, f, 0.1, 0.02, -0.82, 0.25, 0.25, 0.25, 1.1, "cherry", "Petal")
end

return M
