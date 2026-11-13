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

------------------------------------------------------------------ bridges and the dock (over water and grass)

-- The plank bridge's deck top at z: low on the banks, a gentle hump mid-stream.
local function plankY(z: number): number
	return 0.22 + 0.4 * (1 - (z / 3) ^ 2)
end

-- Plank Bridge (2 x 6): boards of two tones laid across two beams in a gentle hump, a stone sill on each bank,
-- short posts at its corners.
M.plankbridge = function(m, f)
	for _, x in { -0.625, 0.625 } do
		for _, s in { -1, 1 } do
			seg(m, f, V(x, plankY(3) - 0.375, 3 * s), V(x, plankY(0) - 0.375, 0), 0.25, 0.25, "wood_dark", "Beam")
		end
	end
	for i = 0, 11 do
		local z = -2.75 + i * 0.5
		local short = i % 3 == 1
		local x = if short then (if i % 2 == 0 then 0.125 else -0.125) else 0
		seg(m, f, V(x, plankY(z - 0.25) - 0.125, z - 0.25), V(x, plankY(z + 0.25) - 0.125, z + 0.25), if short then 1.75 else 2, 0.25, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	for _, s in { -1, 1 } do
		Parts.box(m, f, 0, 0.05, 2.75 * s, 2, 0.25, 0.5, "rock", "Sill")
		for _, x in { -0.875, 0.875 } do
			post(m, f, x, plankY(2.4) + 0.35, 2.4 * s, 0.25, 0.75, 0.25, "wood_dark", "Post")
		end
	end
end

-- Little Dock (3 x 4): a deck of boards on piles, framed by dark beams, its land end at -Z with a stone step; at the
-- far end two mooring posts (a lantern on one) and a ladder down into the water; a coil of rope, a bucket, a crate
-- to sit on.
M.dock = function(m, f)
	local top = 0.55
	for _, x in { -1.125, 1.125 } do
		for _, z in { -1.5, 0.25 } do
			Parts.cyl(m, f, x, top - 0.25 - 0.5, z, 0.5, 1, "wood_dark", "Pile")
		end
		Parts.cyl(m, f, x, top + 0.45 - 0.75, 1.7, 0.5, 1.5, "wood_dark", "Post")
		Parts.box(m, f, x, top - 0.125, 0, 0.25, 0.25, 4, "wood_dark", "Beam")
	end
	for i = 0, 7 do
		local short = i % 3 == 1
		Parts.box(m, f, if short then 0.06 else 0, top - 0.125, -1.75 + i * 0.5, if short then 1.75 else 2, 0.25, 0.5, if i % 2 == 0 then "wood" else "sand_dark", "Board")
	end
	-- the ladder: its rails rise above the deck as handholds
	for _, x in { -0.375, 0.375 } do
		post(m, f, x, top + 0.3, 1.875, 0.25, 1, 0.25, "wood_dark", "Ladder")
	end
	Parts.box(m, f, 0, 0.12, 1.875, 0.5, 0.25, 0.25, "wood", "Rung")
	-- a lantern on the right post
	Parts.glow(m, f, 1.125, top + 0.575, 1.7, 0.25, 0.25, 0.25, "yellow", "Lamp")
	Parts.box(m, f, 1.125, top + 0.8, 1.7, 0.5, 0.25, 0.5, "wood_dark", "LampCap")
	-- a coil of rope by the left post, a bucket, a crate
	Parts.cyl(m, f, -0.6, top + 0.125, 1.1, 0.75, 0.25, "straw", "Coil")
	Parts.cyl(m, f, -0.6, top + 0.14, 1.1, 0.25, 0.25, "wood_dark", "CoilEye")
	Parts.cyl(m, f, 0.65, top + 0.25, -0.9, 0.5, 0.5, "blue", "Bucket")
	Parts.cyl(m, f, 0.65, top + 0.38, -0.9, 0.25, 0.25, "water", "BucketWater")
	Parts.box(m, f, -0.55, top + 0.25, -1.1, 0.5, 0.5, 0.5, "wood", "Crate")
	Parts.box(m, f, -0.55, top + 0.25, -1.1, 0.75, 0.25, 0.5, "wood_dark", "Strap")
	-- a step up from the grass
	Parts.box(m, f, 0, 0.12, -2 + 0.1, 1.5, 0.25, 0.25, "rock", "Step")
end

-- A rope's height at z along the rope bridge: lo mid-stream, hi at the posts (z = +-2.75).
local function sag(z: number, lo: number, hi: number): number
	return lo + (hi - lo) * (z / 2.75) ^ 2
end

-- Rope Bridge (2 x 6): four tall posts on the banks, two deck ropes sagging low over the water with slats hung on
-- them, two hand ropes above tied down to the deck ropes, a stone landing at each end.
M.ropebridge = function(m, f)
	for _, x in { -0.875, 0.875 } do
		for _, s in { -1, 1 } do
			post(m, f, x, 1.75, 2.75 * s, 0.25, 2, 0.25, "wood_dark", "Post")
		end
	end
	local zs = { -2.75, -1.4, 0, 1.4, 2.75 }
	for k = 1, 4 do
		local z0, z1 = zs[k], zs[k + 1]
		for _, x in { -0.875, 0.875 } do
			seg(m, f, V(x, sag(z0, 0.95, 1.6), z0), V(x, sag(z1, 0.95, 1.6), z1), 0.25, 0.25, "straw", "HandRope")
		end
		for _, x in { -0.625, 0.625 } do
			seg(m, f, V(x, sag(z0, 0.35, 0.8), z0), V(x, sag(z1, 0.35, 0.8), z1), 0.25, 0.25, "straw", "DeckRope")
		end
	end
	for _, z in { -1.4, 0, 1.4 } do
		for _, s in { -1, 1 } do
			seg(m, f, V(0.875 * s, sag(z, 0.95, 1.6), z), V(0.625 * s, sag(z, 0.35, 0.8) + 0.05, z), 0.25, 0.25, "straw", "Tie")
		end
	end
	for i = 0, 9 do
		local z = -2.25 + i * 0.5
		local tilt = math.atan(2 * (0.8 - 0.35) * z / 2.75 ^ 2)
		local jig = ((i * 7) % 5 - 2) * 0.03
		Parts.at(m, f, CFrame.new(jig, sag(z, 0.35, 0.8) + 0.18, z) * CFrame.Angles(-tilt, jig, 0), 1.5, 0.25, 0.25, if i % 2 == 0 then "wood" else "sand_dark", "Slat")
	end
	for _, s in { -1, 1 } do
		post(m, f, 0, 0.62, 2.75 * s, 1.5, 0.75, 0.5, "rock", "Landing")
	end
end

-- The stone bridge's deck top at z: a flat crown between z = -1 and 1, straight ramps down to the banks.
local function stoneY(z: number): number
	local a = math.abs(z)
	return if a <= 1 then 1.5 else 1.5 - (a - 1) * 0.675
end

-- Stone Bridge (3 x 6): one round arch of stones (two tones, a pale keystone, standing a little proud of the sides)
-- under a paved hump, the ramps filled down to the banks, low parapets with end posts, odd stones in its sides, moss.
M.stonebridge = function(m, f)
	local W = 2.5
	-- the arch: seven stones on a circle of radius 2.4 round (0, -1.25), springing at z = +-1.75 on the water
	local phiMax = math.asin(1.75 / 2.15)
	for k = 0, 6 do
		local phi = -phiMax + (k + 0.5) * (2 * phiMax / 7)
		local cf = CFrame.new(0, -1.25 + 2.4 * math.cos(phi), 2.4 * math.sin(phi)) * CFrame.Angles(phi, 0, 0)
		Parts.at(m, f, cf, W + 0.25, 0.5, 0.75, if k % 2 == 0 then "rock" else "pavement", "Voussoir")
	end
	-- the deck: a flat crown and two ramps
	Parts.box(m, f, 0, 1.25, 0, W, 0.5, 2, "pavement", "Deck")
	for _, s in { -1, 1 } do
		seg(m, f, V(0, stoneY(0.9) - 0.25, 0.9 * s), V(0, stoneY(2.9) - 0.25, 2.9 * s), W, 0.5, "pavement", "Ramp")
		-- the fill under the ramp, down to the bank
		Parts.wedge(m, f, 0, 0.375, 2.375 * s, W, 0.75, 1.25, "rock", if s > 0 then math.pi else 0, "Fill")
	end
	-- the parapets on both sides, an end post at each corner
	for _, x in { -1.125, 1.125 } do
		Parts.box(m, f, x, stoneY(0) + 0.25, 0, 0.25, 0.5, 2, "rock_dark", "Parapet")
		for _, s in { -1, 1 } do
			seg(m, f, V(x, stoneY(0.95) + 0.25, 0.95 * s), V(x, stoneY(2.55) + 0.25, 2.55 * s), 0.25, 0.5, "rock_dark", "Parapet")
			post(m, f, x, stoneY(2.6) + 0.6, 2.6 * s, 0.5, 0.75, 0.5, "rock", "EndPost")
		end
	end
	-- odd stones in the sides
	for _, x in { -1.2, 1.2 } do
		Parts.box(m, f, x, 0.35, 2.2, 0.25, 0.25, 0.5, "rock_dark", "Stone")
		Parts.box(m, f, x, 0.3, -2.3, 0.25, 0.25, 0.5, "pavement", "Stone")
		Parts.box(m, f, x, 1.1, -1.35, 0.25, 0.25, 0.5, "rock_dark", "Stone")
	end
	-- moss on a parapet and at the arch's foot
	Parts.box(m, f, 1.125, stoneY(1.6) + 0.55, 1.6, 0.25, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, 1.2, 0.12, 1.85, 0.25, 0.25, 0.5, "moss", "Moss")
end

-- Waterwheel (3 x 2): a big wheel standing in the current, its axle along Z: a dark solid wheel, a pale eight-sided
-- rim and a cross of spokes on its face, eight paddles round it dipping into the water, an iron hub; the axle
-- rests on a stone pier behind and a slim post in front; white water where the paddles dip and where it runs on.
M.waterwheel = function(m, f)
	local cy = 1.2
	Parts.logZ(m, f, 0, cy, 0, 0.5, 2, "wood_dark", "Wheel")
	for k = 0, 7 do
		local a = k * QUARTER
		Parts.at(m, f, CFrame.new(math.cos(a), cy + math.sin(a), 0.3) * CFrame.Angles(0, 0, a + math.pi / 2), 0.75, 0.25, 0.25, "sand_dark", "Rim")
	end
	for k = 0, 1 do
		Parts.at(m, f, CFrame.new(0, cy, 0.3) * CFrame.Angles(0, 0, k * math.pi / 2 + QUARTER), 1.75, 0.25, 0.25, "sand_dark", "Spoke")
	end
	for k = 0, 7 do
		local a = k * QUARTER + QUARTER / 2
		Parts.at(m, f, CFrame.new(math.cos(a) * 1.18, cy + math.sin(a) * 1.18, 0) * CFrame.Angles(0, 0, a), 0.5, 0.25, 0.75, "wood", "Paddle")
	end
	Parts.logZ(m, f, 0, cy, 0.3, 0.5, 0.5, "steel_dark", "Hub")
	Parts.logZ(m, f, 0, cy, 0, 2, 0.25, "steel_dark", "Axle")
	-- a stone pier behind under the axle, a slim post in front
	post(m, f, 0, cy - 0.1, -0.8, 0.5, 1.5, 0.25, "rock", "Pier")
	Parts.box(m, f, 0, cy - 0.05, -0.8, 0.5, 0.25, 0.25, "rock_dark", "Cap")
	post(m, f, 0, cy - 0.1, 0.8, 0.25, 1.5, 0.25, "wood_dark", "Post")
	-- white water
	foam(m, f, 0, 0.02, 0, 1.5, 0.25, 0.75)
	foam(m, f, 1.15, 0.0, 0.1, 0.5, 0.25, 0.75)
end

-- The moon bridge's deck top at z: a high round hump.
local function moonY(z: number): number
	return 0.15 + 2 * math.cos(math.pi * z / 6)
end

-- Moon Bridge (3 x 6): a high red arch: two curved stringers, steps of wood between them, a railing of posts and a
-- curved top rail on each side, gold caps on the end posts. The water shows through under it.
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
	end
end

------------------------------------------------------------------ on the water (floating, about y 0 to 0.25)

-- Lily Pads (2 x 2): round leaves in two greens floating flat across the water, one with its notch, a white lily open
-- on the biggest, a bud.
M.lilypads = function(m, f)
	local pads = {
		{ x = -0.4, z = -0.35, d = 1.25, c = "leaf" },
		{ x = 0.5, z = 0.25, d = 1, c = "leaf_dark" },
		{ x = -0.45, z = 0.6, d = 0.75, c = "leaf_dark" },
		{ x = 0.6, z = -0.6, d = 0.75, c = "leaf" },
		{ x = 0.05, z = 0.75, d = 0.5, c = "leaf" },
	}
	for _, p in pads do
		Parts.cyl(m, f, p.x, 0.06, p.z, p.d, 0.25, p.c, "Pad")
	end
	Parts.turned(m, f, 0.12, 0.09, 0.42, 0.25, 0.25, 0.25, QUARTER, "water", "Notch")
	Parts.turned(m, f, -0.45, 0.24, -0.4, 0.5, 0.25, 0.5, QUARTER, "white", "Petals")
	Parts.box(m, f, -0.45, 0.3, -0.4, 0.5, 0.25, 0.5, "white", "Petals")
	Parts.box(m, f, -0.45, 0.4, -0.4, 0.25, 0.25, 0.25, "yellow", "Heart")
	point(m, f, 0.62, 0.28, -0.6, 0.25, "white", "Bud")
end

-- Reeds (2 x 2): four clumps of tall blades fanning out in three greens from tussocks in the water, and three
-- cattails standing up out of them with brown heads.
M.reeds = function(m, f)
	local greens = { "leaf", "moss", "leaf_dark" }
	local clumps = { { -0.55, -0.55 }, { 0.6, -0.35 }, { -0.35, 0.6 }, { 0.55, 0.65 } }
	for k, c in clumps do
		Parts.cyl(m, f, c[1], 0.02, c[2], 0.5, 0.25, "swamp", "Tussock")
		for j = 0, 2 do
			local h = 1 + ((j + k) % 3) * 0.25
			local cf = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0, k * 0.8, 0) * CFrame.Angles(0, 0, (j - 1) * 0.45 + 0.05) * CFrame.new(0, h / 2, 0)
			Parts.at(m, f, cf, 0.25, h, 0.25, greens[j + 1], "Blade")
		end
	end
	for k, c in { { -0.45, -0.4, 1.75 }, { 0.5, -0.2, 1.5 }, { -0.2, 0.5, 1.5 } } do
		local base = CFrame.new(c[1], 0, c[2]) * CFrame.Angles(0.06 * k - 0.1, 0, 0.08 * (k - 2))
		Parts.at(m, f, base * CFrame.new(0, c[3] / 2, 0), 0.25, c[3], 0.25, "moss", "Stalk")
		Parts.at(m, f, base * CFrame.new(0, c[3] - 0.42, 0), 0.25, 0.5, 0.25, "wood_dark", "Cattail")
	end
end

-- Stepping Stones (2 x 2): two flat grey stones a pace apart along Z (so a row of tiles keeps the step), each on a dark
-- wet footing with a worn pale top, a pebble to one side, a tuft of moss.
M.steppingstones = function(m, f)
	for _, s in { { -0.25, -0.5 }, { 0.3, 0.5 } } do
		Parts.cyl(m, f, s[1], -0.02, s[2], 1, 0.25, "rock_dark", "Footing")
		Parts.cyl(m, f, s[1], 0.12, s[2], 0.75, 0.25, "rock", "Stone")
		Parts.cyl(m, f, s[1] - 0.06, 0.15, s[2] - 0.06, 0.5, 0.25, "pavement", "Top")
	end
	Parts.cyl(m, f, 0.65, 0.02, -0.4, 0.5, 0.25, "rock_dark", "Pebble")
	Parts.cyl(m, f, 0.65, 0.1, -0.4, 0.25, 0.25, "rock", "Pebble")
	Parts.box(m, f, -0.55, 0.22, -0.6, 0.25, 0.25, 0.25, "moss", "Moss")
end

-- Duck Decoy (2 x 2): a painted wooden duck turned a little off square and tipped as it bobs in a ring of ripples: a
-- pale body, brown wings with a blue flash, a dark breast, a black tail, a green head with a white collar, a yellow
-- bill.
M.duckfloat = function(m, f)
	Parts.cyl(m, f, 0, -0.02, 0, 1.75, 0.25, "foam", "Ripple"):SetAttribute("PixelWater", 3)
	local d = f * CFrame.Angles(0, math.rad(-25), 0) * CFrame.Angles(0, 0, math.rad(3))
	Parts.box(m, d, -0.15, 0.3, 0, 1.5, 0.5, 0.75, "sand", "Body")
	Parts.ball(m, d, 0.55, 0.36, 0, 0.75, "wood_dark", "Breast")
	Parts.box(m, d, -0.25, 0.6, 0, 1, 0.25, 0.5, "wood", "Wings")
	Parts.box(m, d, 0.1, 0.57, 0, 0.25, 0.25, 0.75, "blue", "Flash")
	Parts.wedge(m, d, -1.0, 0.55, 0, 0.25, 0.25, 0.5, "black", -math.pi / 2, "Tail")
	Parts.box(m, d, 0.6, 0.72, 0, 0.25, 0.25, 0.25, "white", "Collar")
	Parts.ball(m, d, 0.62, 0.98, 0, 0.5, "teal", "Head")
	Parts.box(m, d, 0.92, 0.92, 0, 0.25, 0.25, 0.25, "gold", "Bill")
end

-- Rowboat (2 x 4): a little boat pointing +Z: a teal hull with a white gunwale all round, a pointed bow, a square
-- stern, a dark floor, two seats, a pair of oars shipped along the seats with red blades over the stern, oarlocks, a
-- coil of rope in the bow.
M.rowboat = function(m, f)
	local y0 = -0.05
	Parts.box(m, f, 0, y0, -0.25, 1, 0.25, 2.5, "teal", "Bottom")
	Parts.box(m, f, 0, y0 + 0.15, -0.25, 1, 0.25, 2.5, "wood_dark", "Floor")
	for _, x in { -0.625, 0.625 } do
		Parts.box(m, f, x, y0 + 0.3, -0.25, 0.25, 0.5, 2.5, "teal", "Side")
		Parts.box(m, f, x, y0 + 0.6, -0.25, 0.25, 0.25, 2.5, "white", "Gunwale")
		seg(m, f, V(x, y0 + 0.3, 0.95), V(0, y0 + 0.35, 1.85), 0.25, 0.5, "teal", "Bow")
		seg(m, f, V(x, y0 + 0.6, 0.95), V(0, y0 + 0.65, 1.85), 0.25, 0.25, "white", "Gunwale")
	end
	Parts.box(m, f, 0, y0 + 0.3, -1.5, 1.5, 0.5, 0.25, "teal", "Stern")
	Parts.box(m, f, 0, y0 + 0.6, -1.5, 1.5, 0.25, 0.25, "white", "Gunwale")
	Parts.box(m, f, 0, y0 + 0.15, 1.15, 0.5, 0.25, 0.75, "wood_dark", "BowFloor")
	for _, z in { -0.85, 0.4 } do
		Parts.box(m, f, 0, y0 + 0.42, z, 1, 0.25, 0.5, "wood", "Seat")
	end
	for _, x in { -0.3, 0.3 } do
		Parts.logZ(m, f, x, y0 + 0.62, -0.3, 2.5, 0.25, "sand", "Oar")
		Parts.box(m, f, x, y0 + 0.6, -1.55, 0.25, 0.25, 0.5, "berry_red", "Blade")
	end
	for _, x in { -0.625, 0.625 } do
		Parts.box(m, f, x, y0 + 0.8, -0.2, 0.25, 0.25, 0.25, "steel_dark", "Oarlock")
	end
	Parts.cyl(m, f, 0, y0 + 0.4, 1.2, 0.5, 0.25, "straw", "Rope")
end

-- One lotus flower at (x, z): a star of deep pink petals, a ring of pale petals cupped up round it, a gold heart.
local function lotusFlower(m: Model, f: CFrame, x: number, z: number, turn: number)
	local c = f * CFrame.new(x, 0, z) * CFrame.Angles(0, turn, 0)
	Parts.turned(m, c, 0, 0.2, 0, 0.75, 0.25, 0.75, QUARTER, "pink", "Petals")
	for k = 0, 3 do
		local a = k * math.pi / 2
		Parts.at(m, c, CFrame.Angles(0, a, 0) * CFrame.new(0, 0.42, 0.22) * CFrame.Angles(0.45, 0, 0), 0.25, 0.5, 0.25, "cherry", "Petal")
	end
	Parts.box(m, c, 0, 0.42, 0, 0.25, 0.25, 0.25, "gold", "Heart")
end

-- Lotus Flowers (2 x 2): round leaves flat on the water, one curling up, two pink flowers open and a bud.
M.lotus = function(m, f)
	Parts.cyl(m, f, -0.45, 0.08, 0.45, 1, 0.25, "leaf", "Pad")
	Parts.cyl(m, f, 0.55, 0.08, 0.5, 0.75, 0.25, "leaf_dark", "Pad")
	Parts.cyl(m, f, 0.5, 0.08, -0.55, 0.75, 0.25, "leaf", "Pad")
	-- a leaf curling up out of the water
	Parts.cyl(m, f, -0.5, 0.3, -0.5, 0.75, 0.25, "leaf_dark", "Leaf").CFrame = f * CFrame.new(-0.5, 0.3, -0.5) * CFrame.Angles(0.35, 0, -0.6) * CFrame.Angles(0, 0, math.pi / 2)
	lotusFlower(m, f, -0.35, 0.4, 0.2)
	lotusFlower(m, f, 0.45, -0.3, -0.3)
	-- a bud on a stalk
	Parts.box(m, f, 0.6, 0.35, 0.4, 0.25, 0.5, 0.25, "leaf_dark", "Stalk")
	point(m, f, 0.6, 0.7, 0.4, 0.25, "pink", "Bud")
end

-- Little Waterfall (2 x 2): mossy rocks across the back, a lower stone in the middle where a stream runs over the lip
-- (white where it breaks) and falls into a small pool, a white streak down the fall, foam at its foot, stones round
-- the pool, ferns at the sides.
M.littlefall = function(m, f)
	-- the rocks
	post(m, f, -0.62, 1.25, -0.62, 0.75, 1.5, 0.75, "rock", "Rock")
	post(m, f, 0.62, 1.05, -0.62, 0.75, 1.25, 0.75, "rock_dark", "Rock")
	post(m, f, 0, 0.82, -0.62, 0.5, 1, 0.75, "rock", "Lip")
	Parts.at(m, f, CFrame.new(-0.72, 1.35, -0.72) * CFrame.Angles(0, 0.3, 0.15), 0.5, 0.25, 0.5, "rock_dark", "Rock")
	Parts.box(m, f, -0.62, 1.3, -0.5, 0.75, 0.25, 0.5, "moss", "Moss")
	Parts.box(m, f, 0.62, 1.1, -0.55, 0.75, 0.25, 0.5, "moss", "Moss")
	-- the stream over the lip and the fall
	Parts.water(m, f, 0, 0.78, -0.7, 0.5, 0.75, "water", "Stream")
	foam(m, f, 0, 0.84, -0.3, 0.5, 0.25, 0.25)
	local fall = Parts.box(m, f, 0, 0.44, -0.15, 0.5, 0.75, 0.25, "shallow", "Fall")
	fall:SetAttribute("PixelWater", 2)
	foam(m, f, 0.1, 0.4, -0.06, 0.25, 0.5, 0.25)
	-- the pool, its foam and its stones
	Parts.water(m, f, 0, -0.02, 0.4, 2, 1.25, "water", "Pool")
	foam(m, f, 0, 0.08, 0.1, 1, 0.25, 0.5)
	for k, s in { { -0.8, 0.3 }, { -0.55, 0.85 }, { 0.2, 0.9 }, { 0.75, 0.75 }, { 0.85, 0.15 } } do
		Parts.box(m, f, s[1], 0.12, s[2], 0.5, 0.25, 0.5, if k % 2 == 0 then "rock_dark" else "rock", "Stone")
	end
	Parts.ball(m, f, -0.9, 0.35, -0.1, 0.5, "leaf", "Fern")
	Parts.ball(m, f, 0.9, 0.3, -0.2, 0.5, "leaf_dark", "Fern")
end

-- One floating lantern at (x, z): a wooden raft, a glowing paper box, a dark frame round its top, its light on the
-- water.
local function floatLantern(m: Model, f: CFrame, x: number, z: number, turn: number, color: string)
	local c = f * CFrame.new(x, 0, z) * CFrame.Angles(0, turn, 0)
	Parts.box(m, c, 0, 0.06, 0, 0.75, 0.25, 0.75, "wood_dark", "Raft")
	Parts.box(m, c, 0, 0.5, 0, 0.5, 0.75, 0.5, color, "Paper", true)
	Parts.box(m, c, 0, 0.9, 0, 0.5, 0.25, 0.5, "wood_dark", "Frame")
	Parts.box(m, c, 0, -0.04, 0.55, 0.25, 0.25, 0.5, color, "Glint", true)
end

-- Floating Lanterns (2 x 2): three paper lanterns drifting, each turned its own way, in warm colours.
M.waterlanterns = function(m, f)
	floatLantern(m, f, -0.45, -0.45, 0.3, "yellow")
	floatLantern(m, f, 0.5, -0.05, -0.25, "orange")
	floatLantern(m, f, -0.25, 0.6, 0.6, "pink")
end

return M
